// Textpad++ — one editing view. GPL-3.0-or-later.
#import "app/EditorPane.h"
#import "app/HideLines.h"
#import "app/Preferences.h"
#import "commands/ScintillaKeys.h"
#import "app/Document.h"
#import "app/LanguageService.h"

@implementation TPEditorPane {
    TPDocument *_current;
}

- (instancetype)initWithViewIndex:(int)index owner:(id<TPEditorPaneOwner>)owner {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 600, 400)])) {
        _viewIndex = index;
        _owner = owner;
        _documents = [NSMutableArray array];
        _tabBar = [[TPTabBarView alloc] initWithFrame:NSMakeRect(0, 0, 600, 25)];
        _tabBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
        _editor = [[ScintillaView alloc] initWithFrame:NSMakeRect(0, 0, 600, 375)];
        _editor.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _editor.delegate = self;
        [self addSubview:_editor];
        [self addSubview:_tabBar];
        [[TPLanguageService shared] configureView:_editor];
        [[TPScintillaKeys shared] registerView:_editor];
        [self layoutChildren];
    }
    return self;
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self layoutChildren];
}

// Preferences > Tab Bar: horizontal (multi-line rows) or vertical (the bar turned 90° on the left edge, as the
// Windows vertical tab control)
// Preferences > Margins/Border/Edge > Border Width / No edge (upstream defaults 2 and an edge line)
- (CGFloat)borderWidth { return MAX(0, MIN(30, [TPPrefs i:@"pref.borderWidth"])); }
- (void)drawRect:(NSRect)r {
    if (self.borderWidth <= 0 && ![TPPrefs b:@"pref.borderEdge"]) return;
    [[TPChrome barBackground] setFill];
    NSRectFill(self.bounds);
    if ([TPPrefs b:@"pref.borderEdge"]) {
        [[TPChrome border] setStroke];
        NSBezierPath *p = [NSBezierPath bezierPathWithRect:NSInsetRect(_editor.frame, -0.5, -0.5)];
        p.lineWidth = 1;
        [p stroke];
    }
}

- (void)layoutChildren {
    [self layoutChildrenWithoutBorder];
    const CGFloat w = self.borderWidth + ([TPPrefs b:@"pref.borderEdge"] ? 1 : 0);
    if (w > 0) _editor.frame = NSInsetRect(_editor.frame, MIN(w, NSWidth(_editor.frame) / 4), MIN(w, NSHeight(_editor.frame) / 4));
    self.needsDisplay = YES;
}

- (void)layoutChildrenWithoutBorder {
    NSRect b = self.bounds;
    if (_tabBar.hidden) { _tabBar.frameCenterRotation = 0; _editor.frame = b; return; }
    if ([TPPrefs b:@"pref.tabVertical"]) {
        CGFloat strip = [_tabBar heightForWidth:NSHeight(b)];
        _tabBar.frameCenterRotation = 0;
        _tabBar.frame = NSMakeRect(strip / 2 - NSHeight(b) / 2, NSHeight(b) / 2 - strip / 2, NSHeight(b), strip);
        _tabBar.frameCenterRotation = 90;
        _editor.frame = NSMakeRect(strip, 0, MAX(0, NSWidth(b) - strip), NSHeight(b));
    } else {
        CGFloat tabH = [_tabBar heightForWidth:NSWidth(b)];
        _tabBar.frameCenterRotation = 0;
        _tabBar.frame = NSMakeRect(0, NSHeight(b) - tabH, NSWidth(b), tabH);
        _editor.frame = NSMakeRect(0, 0, NSWidth(b), MAX(0, NSHeight(b) - tabH));
    }
}

- (TPDocument *)currentDocument { return _current; }

- (NSInteger)indexOfDocument:(TPDocument *)doc { return (NSInteger)[_documents indexOfObjectIdenticalTo:doc]; }

- (void)saveCurrentPosition {
    if (!_current) return;
    TPViewPosition p;
    p.anchor = SCI(_editor, SCI_GETANCHOR);
    p.caret = SCI(_editor, SCI_GETCURRENTPOS);
    p.firstVisibleLine = SCI(_editor, SCI_GETFIRSTVISIBLELINE);
    p.xOffset = SCI(_editor, SCI_GETXOFFSET);
    p.selMode = static_cast<int>(SCI(_editor, SCI_GETSELECTIONMODE));
    p.valid = YES;
    [_current setPosition:p forView:_viewIndex];
}

- (void)showDocument:(TPDocument *)doc {
    if ([self indexOfDocument:doc] == NSNotFound) [_documents addObject:doc];
    if (_current != doc) {
        [self saveCurrentPosition];
        _current = doc;
        SCI(_editor, SCI_SETDOCPOINTER, 0, doc.sciDoc);
        SCI(_editor, SCI_SETCODEPAGE, SC_CP_UTF8);
        [[TPLanguageService shared] applyLanguageOfDocument:doc toView:_editor];
        SCI(_editor, SCI_SETREADONLY, (doc.userReadOnly || doc.monitoring) ? 1 : 0);
        tpp::hidelines::restoreHiddenLines(_editor);   // line visibility is per view; the markers are in the document
        TPViewPosition p = [doc positionForView:_viewIndex];
        if (p.valid) {
            SCI(_editor, SCI_SETSELECTIONMODE, p.selMode);
            SCI(_editor, SCI_SETANCHOR, p.anchor);
            SCI(_editor, SCI_SETCURRENTPOS, p.caret);
            SCI(_editor, SCI_SETFIRSTVISIBLELINE, p.firstVisibleLine);
            SCI(_editor, SCI_SETXOFFSET, p.xOffset);
        } else {
            SCI(_editor, SCI_GOTOPOS, 0);
        }
        doc.lastAccess = [NSDate date];
    } else {
        [[TPLanguageService shared] applyLanguageOfDocument:doc toView:_editor];
    }
    [self reloadTabs];
}

- (void)removeDocument:(TPDocument *)doc {
    NSInteger i = [self indexOfDocument:doc];
    if (i == NSNotFound) return;
    if (_current == doc) {
        _current = nil;
    }
    [_documents removeObjectAtIndex:i];
    [self reloadTabs];
}

- (void)reloadTabs {
    _tabBar.documents = _documents;
    _tabBar.selectedIndex = _current ? [self indexOfDocument:_current] : -1;
    // a multi-line / vertical bar can change its thickness when tabs are added, removed or renamed
    BOOL vertical = [TPPrefs b:@"pref.tabVertical"];
    CGFloat want = [_tabBar heightForWidth:vertical ? NSHeight(self.bounds) : NSWidth(self.bounds)];
    CGFloat have = vertical ? NSMinX(_editor.frame) : NSHeight(self.bounds) - NSHeight(_editor.frame);
    if (!_tabBar.hidden && fabs(want - have) > 0.5) [self layoutChildren];
}

- (void)notification:(SCNotification *)scn {
    if (scn->nmhdr.code == SCN_FOCUSIN) [_owner paneDidBecomeActive:self];
    [_owner pane:self notification:scn];
}

@end
