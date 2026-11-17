// Textpad++ — View > Document List (upstream VerticalFileSwitcher) and View > Document Map (upstream DocumentMap).
// GPL-3.0-or-later.
#import "panels/Panels.h"
#import "app/MainWindowController.h"
#import "app/EditorPane.h"
#import "app/Document.h"
#import "app/LanguageService.h"
#import "app/Preferences.h"
#import "app/Sci.h"
#import "commands/CommandRegistry.h"

using namespace npp;

static NSImage *docIcon(TPDocument *d) {
    NSString *name = d.userReadOnly ? @"readonly" : d.dirty ? @"unsaved" : @"saved";
    NSString *p = [[NSBundle mainBundle] pathForResource:name ofType:@"ico" inDirectory:[TPChrome dark] ? @"icons/tabbar-dark" : @"icons/tabbar"];
    if (!p) p = [[NSBundle mainBundle] pathForResource:name ofType:@"ico" inDirectory:@"icons/tabbar"];
    NSImage *img = p ? [[NSImage alloc] initWithContentsOfFile:p] : nil;
    img.size = NSMakeSize(16, 16);
    return img;
}

// ================================================================ Document List
@implementation TPDocumentListPanel {
    __weak TPMainWindowController *_c;
    NSScrollView *_scroll;
    NSArray<TPDocument *> *_rows;
    BOOL _reloading;
}

- (instancetype)initWithController:(TPMainWindowController *)c {
    if ((self = [super init])) {
        _c = c;
        _scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 250, 400)];
        _scroll.hasVerticalScroller = YES;
        _scroll.autohidesScrollers = YES;
        _table = [[NSTableView alloc] initWithFrame:_scroll.bounds];
        for (NSArray *col in @[@[@"name", @"Name", @150], @[@"ext", @"Ext.", @50], @[@"path", @"Path", @300]]) {
            NSTableColumn *tc = [[NSTableColumn alloc] initWithIdentifier:col[0]];
            tc.title = col[1];
            tc.width = [col[2] doubleValue];
            tc.sortDescriptorPrototype = [NSSortDescriptor sortDescriptorWithKey:col[0] ascending:YES selector:@selector(localizedStandardCompare:)];
            [_table addTableColumn:tc];
        }
        _table.allowsMultipleSelection = YES;
        _table.rowHeight = 20;
        _table.dataSource = self;
        _table.delegate = self;
        _table.target = self;
        _table.action = @selector(clicked:);
        NSMenu *m = [[NSMenu alloc] initWithTitle:@""];
        TPCommandRegistry *reg = [TPCommandRegistry shared];
        for (NSNumber *cmd in @[@(IDM_DOCLIST_FILESCLOSE), @(IDM_DOCLIST_FILESCLOSEOTHERS), @(IDM_DOCLIST_COPYNAMES), @(IDM_DOCLIST_COPYPATHS)])
            [m addItem:[reg makeItemForCommand:cmd.intValue]];
        _table.menu = m;
        // upstream: the column header's context menu shows / hides the Ext. and Path columns
        NSMenu *hm = [[NSMenu alloc] initWithTitle:@""];
        hm.delegate = self;
        _table.headerView.menu = hm;
        _scroll.documentView = _table;
        [self applyColumns];
    }
    return self;
}

- (NSString *)panelIdentifier { return @"doclist"; }
- (NSString *)panelTitle { return @"Document List"; }
- (NSView *)panelView { return _scroll; }
- (TPDockSide)defaultSide { return TPDockLeft; }
- (void)panelDidShow { [self reload]; }
- (void)documentsChanged { [self reload]; }
- (void)focusPanel { [_table.window makeFirstResponder:_table]; }

- (void)applyColumns {
    [_table tableColumnWithIdentifier:@"ext"].hidden = ![TPPrefs b:@"pref.docListExt"];
    [_table tableColumnWithIdentifier:@"path"].hidden = ![TPPrefs b:@"pref.docListPath"];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    for (NSArray *e in @[@[@"Ext.", @"pref.docListExt"], @[@"Path", @"pref.docListPath"]]) {
        NSMenuItem *mi = [menu addItemWithTitle:e[0] action:@selector(toggleColumn:) keyEquivalent:@""];
        mi.target = self;
        mi.representedObject = e[1];
        mi.state = [TPPrefs b:e[1]] ? NSControlStateValueOn : NSControlStateValueOff;
    }
}
- (void)toggleColumn:(NSMenuItem *)mi {
    [TPPrefs set:@(![TPPrefs b:mi.representedObject]) forKey:mi.representedObject];
    [self applyColumns];
}

static NSString *sortKey(TPDocument *d, NSString *key) {
    if ([key isEqualToString:@"ext"]) return d.displayName.pathExtension;
    if ([key isEqualToString:@"path"]) return d.path ?: d.displayName;
    return d.displayName;
}

- (void)reload {
    TPMainWindowController *c = _c;
    NSMutableArray *rows = [NSMutableArray array];
    for (TPEditorPane *p in @[c.mainPane, c.subPane])
        for (TPDocument *d in p.documents) if (![rows containsObject:d]) [rows addObject:d];
    NSSortDescriptor *sd = _table.sortDescriptors.firstObject;
    if (sd) {
        [rows sortUsingComparator:^NSComparisonResult(TPDocument *a, TPDocument *b) {
            NSComparisonResult r = [sortKey(a, sd.key) localizedStandardCompare:sortKey(b, sd.key)];
            return sd.ascending ? r : (NSComparisonResult)(-r);
        }];
    }
    _rows = rows;
    _reloading = YES;
    [self applyColumns];
    [_table reloadData];
    NSUInteger cur = [rows indexOfObject:c.currentDocument];
    NSIndexSet *sel = _table.selectedRowIndexes;
    if (cur != NSNotFound && !(sel.count > 1 && [sel containsIndex:cur])) [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:cur] byExtendingSelection:NO];
    _reloading = NO;
}

- (NSArray<TPDocument *> *)rows { return _rows ?: @[]; }
- (NSArray<TPDocument *> *)selectedDocuments { return [_rows objectsAtIndexes:_table.selectedRowIndexes] ?: @[]; }

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return (NSInteger)_rows.count; }
- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    TPDocument *d = _rows[(NSUInteger)row];
    NSTableCellView *cell = [tv makeViewWithIdentifier:col.identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, col.width, 20)];
        cell.identifier = col.identifier;
        NSTextField *t = [NSTextField labelWithString:@""];
        t.lineBreakMode = NSLineBreakByTruncatingMiddle;
        t.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:t];
        cell.textField = t;
        if ([col.identifier isEqualToString:@"name"]) {
            NSImageView *iv = [NSImageView imageViewWithImage:[NSImage new]];
            iv.translatesAutoresizingMaskIntoConstraints = NO;
            [cell addSubview:iv];
            cell.imageView = iv;
            [NSLayoutConstraint activateConstraints:@[
                [iv.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2], [iv.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
                [iv.widthAnchor constraintEqualToConstant:16], [iv.heightAnchor constraintEqualToConstant:16],
                [t.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:4]]];
        } else {
            [t.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2].active = YES;
        }
        [NSLayoutConstraint activateConstraints:@[[t.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2],
                                                  [t.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]]];
    }
    if ([col.identifier isEqualToString:@"name"]) {
        cell.textField.stringValue = d.displayName.stringByDeletingPathExtension.length && [TPPrefs b:@"pref.docListExt"] ? d.displayName.stringByDeletingPathExtension : d.displayName;
        cell.imageView.image = docIcon(d);
    } else if ([col.identifier isEqualToString:@"ext"]) {
        cell.textField.stringValue = d.displayName.pathExtension.length ? [@"." stringByAppendingString:d.displayName.pathExtension] : @"";
    } else {
        cell.textField.stringValue = d.path ?: d.displayName;
    }
    cell.toolTip = d.path ?: d.displayName;
    return cell;
}

- (void)tableView:(NSTableView *)tv sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)old { [self reload]; }

- (void)clicked:(id)sender {
    if (_reloading || _table.clickedRow < 0 || _table.selectedRowIndexes.count != 1) return;
    [self activateRow:_table.clickedRow];
}

- (void)activateRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)_rows.count) return;
    TPMainWindowController *c = _c;
    TPDocument *d = _rows[(NSUInteger)row];
    TPEditorPane *p = [c.activePane indexOfDocument:d] != NSNotFound ? c.activePane
                    : ([c.mainPane indexOfDocument:d] != NSNotFound ? c.mainPane : c.subPane);
    [c activateDocument:d inPane:p];
}

@end

// ================================================================ Document Map
@interface TPMapOverlay : NSView
@property (nonatomic) NSRect zone;
@property (nonatomic, weak) TPDocumentMapPanel *panel;
@end
@implementation TPMapOverlay
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)r {
    if (NSIsEmptyRect(_zone)) return;
    NSColor *c = [TPChrome dark] ? [NSColor colorWithSRGBRed:0.55 green:0.70 blue:1 alpha:1] : [NSColor colorWithSRGBRed:0.0 green:0.35 blue:0.85 alpha:1];
    [[c colorWithAlphaComponent:0.18] setFill];
    NSRectFillUsingOperation(_zone, NSCompositingOperationSourceOver);
    [[c colorWithAlphaComponent:0.7] setStroke];
    NSBezierPath *b = [NSBezierPath bezierPathWithRect:NSInsetRect(_zone, 0.5, 0.5)];
    b.lineWidth = 1;
    [b stroke];
}
- (void)mouseDown:(NSEvent *)e { [_panel scrollEditorToMapPoint:[self convertPoint:e.locationInWindow fromView:nil]]; }
- (void)mouseDragged:(NSEvent *)e { [_panel scrollEditorToMapPoint:[self convertPoint:e.locationInWindow fromView:nil]]; }
- (void)scrollWheel:(NSEvent *)e { [_panel.mapView scrollWheel:e]; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { return YES; }
@end

@implementation TPDocumentMapPanel {
    __weak TPMainWindowController *_c;
    __weak TPDocument *_peekDocument;
    NSView *_box;
    TPMapOverlay *_overlay;
    sptr_t _scratch;
    __weak TPDocument *_shown;
}

- (instancetype)initWithController:(TPMainWindowController *)c {
    if ((self = [super init])) {
        _c = c;
        _box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, 400)];
        _box.autoresizesSubviews = YES;
        _mapView = [[ScintillaView alloc] initWithFrame:_box.bounds];
        _mapView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [_box addSubview:_mapView];
        _overlay = [[TPMapOverlay alloc] initWithFrame:_box.bounds];
        _overlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _overlay.panel = self;
        [_box addSubview:_overlay];
        SCI(_mapView, SCI_SETCODEPAGE, SC_CP_UTF8);
        _scratch = SCI(_mapView, SCI_GETDOCPOINTER);
        SCI(_mapView, SCI_ADDREFDOCUMENT, 0, _scratch);
        [self configureMap];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(boxResized:) name:NSViewFrameDidChangeNotification object:_box];
    }
    return self;
}

- (NSString *)panelIdentifier { return @"docmap"; }
- (NSString *)panelTitle { return @"Document Map"; }
- (NSView *)panelView { return _box; }
- (TPDockSide)defaultSide { return TPDockRight; }
- (void)panelDidShow { _shown = nil; [self sync]; }
- (void)panelDidHide { SCI(_mapView, SCI_SETDOCPOINTER, 0, _scratch); _shown = nil; _peekDocument = nil; }   // drop the document reference
- (void)documentsChanged { [self sync]; }
- (void)editorViewChanged { [self sync]; }
- (void)boxResized:(NSNotification *)n { [self sync]; }

// upstream DocumentMap: zoom -10, no margins, no caret, no scroll bars
- (void)configureMap {
    ScintillaView *m = _mapView;
    SCI(m, SCI_SETZOOM, static_cast<uptr_t>(-10));
    for (int i = 0; i < 5; ++i) SCI(m, SCI_SETMARGINWIDTHN, i, 0);
    SCI(m, SCI_SETHSCROLLBAR, 0);
    SCI(m, SCI_SETVSCROLLBAR, 0);
    SCI(m, SCI_SETCARETSTYLE, CARETSTYLE_INVISIBLE);
    SCI(m, SCI_SETCARETLINEVISIBLE, 0);
    SCI(m, SCI_SETENDATLASTLINE, 1);
    SCI(m, SCI_SETEXTRAASCENT, 0);
    SCI(m, SCI_SETEXTRADESCENT, 0);
}

- (void)setPeekDocument:(TPDocument *)peekDocument {
    _peekDocument = peekDocument;
    [self sync];
}
- (TPDocument *)shownDocument { return _shown; }

- (void)sync {
    TPMainWindowController *c = _c;
    if (!_box.superview) return;
    if (_peekDocument && ![c.allDocuments containsObject:_peekDocument]) _peekDocument = nil;
    TPDocument *d = _peekDocument ?: c.currentDocument;
    ScintillaView *ed = c.editor;
    if (_peekDocument) {   // upstream DocumentMap::showInMapTemporarily: that document at its own scroll position, no zone
        if (d != _shown) {
            SCI(_mapView, SCI_SETDOCPOINTER, 0, d.sciDoc);
            SCI(_mapView, SCI_SETCODEPAGE, SC_CP_UTF8);
            [[TPLanguageService shared] applyLanguageOfDocument:d toView:_mapView];
            [self configureMap];
            _shown = d;
        }
        TPViewPosition pos = [d positionForView:c.activePane.viewIndex];
        if (!pos.valid) pos = [d positionForView:1 - c.activePane.viewIndex];
        SCI(_mapView, SCI_SETFIRSTVISIBLELINE, pos.valid ? pos.firstVisibleLine : 0);
        _overlay.zone = NSZeroRect; _overlay.needsDisplay = YES;
        return;
    }
    if (d != _shown) {
        SCI(_mapView, SCI_SETDOCPOINTER, 0, d ? d.sciDoc : _scratch);
        SCI(_mapView, SCI_SETCODEPAGE, SC_CP_UTF8);
        if (d) [[TPLanguageService shared] applyLanguageOfDocument:d toView:_mapView];
        [self configureMap];
        _shown = d;
    }
    if (!d) { _overlay.zone = NSZeroRect; _overlay.needsDisplay = YES; return; }
    SCI(_mapView, SCI_SETWRAPMODE, SCI(ed, SCI_GETWRAPMODE));
    // map scrolls proportionally with the editor so the zone stays visible
    const sptr_t edFirst = SCI(ed, SCI_GETFIRSTVISIBLELINE), edScreen = MAX((sptr_t)1, SCI(ed, SCI_LINESONSCREEN));
    const sptr_t edTotal = SCI(ed, SCI_VISIBLEFROMDOCLINE, SCI(ed, SCI_GETLINECOUNT));
    const sptr_t mapScreen = MAX((sptr_t)1, SCI(_mapView, SCI_LINESONSCREEN));
    const sptr_t mapTotal = SCI(_mapView, SCI_VISIBLEFROMDOCLINE, SCI(_mapView, SCI_GETLINECOUNT));
    double ratio = edTotal > edScreen ? MIN(1.0, double(edFirst) / double(edTotal - edScreen)) : 0;
    SCI(_mapView, SCI_SETFIRSTVISIBLELINE, mapTotal > mapScreen ? static_cast<sptr_t>(ratio * double(mapTotal - mapScreen) + 0.5) : 0);
    const sptr_t firstLine = SCI(ed, SCI_DOCLINEFROMVISIBLE, edFirst);
    const sptr_t lastLine = SCI(ed, SCI_DOCLINEFROMVISIBLE, edFirst + edScreen - 1);
    CGFloat top = SCI(_mapView, SCI_POINTYFROMPOSITION, 0, SCI(_mapView, SCI_POSITIONFROMLINE, firstLine));
    CGFloat bottom;
    if (lastLine + 1 < SCI(_mapView, SCI_GETLINECOUNT)) bottom = SCI(_mapView, SCI_POINTYFROMPOSITION, 0, SCI(_mapView, SCI_POSITIONFROMLINE, lastLine + 1));
    else bottom = SCI(_mapView, SCI_POINTYFROMPOSITION, 0, SCI(_mapView, SCI_GETLENGTH)) + SCI(_mapView, SCI_TEXTHEIGHT, lastLine);
    _overlay.zone = NSMakeRect(0, top, NSWidth(_overlay.bounds), MAX(2.0, bottom - top));
    _overlay.needsDisplay = YES;
}

- (NSRect)visibleZone { return _overlay.zone; }

// click / drag: centre the editor on the clicked line (upstream DocumentMap::scrollMap)
- (void)scrollEditorToMapPoint:(NSPoint)p {
    TPMainWindowController *c = _c;
    if (!c.currentDocument) return;
    sptr_t pos = SCI(_mapView, SCI_POSITIONFROMPOINT, static_cast<uptr_t>(MAX(0.0, p.x)), static_cast<sptr_t>(MAX(0.0, p.y)));
    sptr_t line = SCI(_mapView, SCI_LINEFROMPOSITION, pos);
    ScintillaView *ed = c.editor;
    sptr_t vis = SCI(ed, SCI_VISIBLEFROMDOCLINE, line);
    SCI(ed, SCI_SETFIRSTVISIBLELINE, MAX((sptr_t)0, vis - SCI(ed, SCI_LINESONSCREEN) / 2));
    [self sync];
}

@end

// ================================================================ Document Peeker
@implementation TPDocumentPeeker {
    __weak TPMainWindowController *_c;
    sptr_t _scratch;
    __weak TPDocument *_doc;
}

- (instancetype)initWithController:(TPMainWindowController *)c {
    if ((self = [super init])) {
        _c = c;
        _window = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 210, 228)
                                             styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                               backing:NSBackingStoreBuffered defer:YES];
        _window.floatingPanel = YES;
        _window.hidesOnDeactivate = YES;
        _window.hasShadow = YES;
        _window.releasedWhenClosed = NO;
        _window.ignoresMouseEvents = YES;
        _peekView = [[ScintillaView alloc] initWithFrame:_window.contentView.bounds];
        _peekView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [_window.contentView addSubview:_peekView];
        _scratch = SCI(_peekView, SCI_GETDOCPOINTER);
        SCI(_peekView, SCI_ADDREFDOCUMENT, 0, _scratch);
    }
    return self;
}

- (TPDocument *)document { return _window.isVisible ? _doc : nil; }

// upstream DocumentPeeker::doDialog / syncDisplay / scrollSnapshotWith
- (void)showDocument:(TPDocument *)doc fromPane:(TPEditorPane *)pane belowScreenPoint:(NSPoint)p {
    ScintillaView *v = _peekView, *ed = pane.editor;
    if (doc != _doc || !_window.isVisible) {
        SCI(v, SCI_SETDOCPOINTER, 0, doc.sciDoc);
        SCI(v, SCI_SETCODEPAGE, SC_CP_UTF8);
        [[TPLanguageService shared] applyLanguageOfDocument:doc toView:v];
        SCI(v, SCI_SETZOOM, static_cast<uptr_t>(-10));
        SCI(v, SCI_SETVSCROLLBAR, 0);
        SCI(v, SCI_SETHSCROLLBAR, 0);
        SCI(v, SCI_SETINDENTATIONGUIDES, SC_IV_NONE);
        for (int i = 0; i < 5; ++i) SCI(v, SCI_SETMARGINWIDTHN, i, 0);
        SCI(v, SCI_SETCARETSTYLE, CARETSTYLE_INVISIBLE);
        SCI(v, SCI_SETCARETLINEVISIBLE, 0);
        _doc = doc;
    }
    // the snapshot keeps the editor's proportions: its visible lines at the peeker's line height
    const sptr_t lines = MAX((sptr_t)8, SCI(ed, SCI_LINESONSCREEN));
    sptr_t margins = 0;
    for (int i = 0; i < 5; ++i) margins += SCI(ed, SCI_GETMARGINWIDTHN, i);
    const CGFloat h = MIN(420.0, MAX(60.0, double(lines * SCI(v, SCI_TEXTHEIGHT, 0))));
    const CGFloat edW = MAX(1.0, NSWidth(ed.bounds) - margins), edH = MAX(1.0, NSHeight(ed.bounds));
    const CGFloat w = MIN(520.0, MAX(80.0, edW / edH * h));
    [_window setFrame:NSMakeRect(p.x, p.y - 10 - h, w, h) display:NO];
    SCI(v, SCI_SETWRAPMODE, SCI(ed, SCI_GETWRAPMODE));
    SCI(v, SCI_SETWRAPINDENTMODE, SCI(ed, SCI_GETWRAPINDENTMODE));
    TPViewPosition pos = [doc positionForView:pane.viewIndex];
    SCI(v, SCI_SETFIRSTVISIBLELINE, pos.valid ? pos.firstVisibleLine : 0);
    _window.alphaValue = _c.selfTestMode ? 0 : 1;   // the self-test window is invisible too
    if (!_window.isVisible) [_window orderFront:nil];
}

- (void)hide {
    if (_window.isVisible) [_window orderOut:nil];
    if (_doc) { SCI(_peekView, SCI_SETDOCPOINTER, 0, _scratch); _doc = nil; }   // drop the document reference
}

@end
