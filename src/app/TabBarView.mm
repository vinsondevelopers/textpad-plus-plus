// Textpad++ — Notepad++-style document tab bar. GPL-3.0-or-later.
// Geometry from upstream NppConstants.h: tab height 22 (reduced) / 25, min width 45, close/pin
// button 11, icon 16. Behaviour follows Preferences > Tab Bar.
#import "app/TabBarView.h"
#import "app/Accessibility.h"
#import "app/Document.h"
#import "app/LanguageService.h"
#import "app/Preferences.h"

static const CGFloat kTabMinWidth = 45;
static const CGFloat kIconSize = 16;
static const CGFloat kBtnSize = 11;
static const CGFloat kPad = 5;

static NSColor *hexColor(int rgb) {
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

static NSImage *tabIcon(NSString *name) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSString *dir = [TPChrome dark] ? @"icons/tabbar-dark" : @"icons/tabbar";
    NSString *key = [dir stringByAppendingPathComponent:name];
    NSImage *img = cache[key];
    if (!img) {
        NSString *p = [[NSBundle mainBundle] pathForResource:name ofType:@"ico" inDirectory:dir];
        if (!p) p = [[NSBundle mainBundle] pathForResource:name ofType:@"ico" inDirectory:@"icons/tabbar"];
        img = p ? [[NSImage alloc] initWithContentsOfFile:p] : nil;
        if (img) { img.size = NSMakeSize(kIconSize, kIconSize); cache[key] = img; }
    }
    return img;
}

@implementation TPTabBarView {
    NSMutableArray<NSValue *> *_rects;
    NSInteger _hoverIndex;
    NSInteger _hoverButton;   // 0 none, 1 close, 2 pin
    NSInteger _dragIndex;
    NSPoint _dragStart;
    BOOL _dragging;
    NSTrackingArea *_tracking;
}

+ (CGFloat)preferredHeight { return ([TPPrefs b:@"pref.tabReduce"] ? 22 : 25) + 3; }

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _rects = [NSMutableArray array];
        _hoverIndex = -1;
        _dragIndex = -1;
        _documents = @[];
        _selectedIndex = -1;
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:self.bounds
                                             options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                               owner:self userInfo:nil];
    [self addTrackingArea:_tracking];
}

- (NSFont *)tabFont { return [NSFont systemFontOfSize:[TPPrefs b:@"pref.tabReduce"] ? 12 : 13]; }
- (CGFloat)tabHeight { return [TPPrefs b:@"pref.tabReduce"] ? 22 : 25; }

- (NSString *)labelFor:(TPDocument *)d {
    NSString *s = d.tabLabel;
    NSInteger max = [TPPrefs i:@"pref.tabMaxLabel"];
    if (max > 0 && (NSInteger)s.length > max) s = [[s substringToIndex:max] stringByAppendingString:@"…"];
    return s;
}

- (BOOL)showPinFor:(NSInteger)i {
    if (![TPPrefs b:@"pref.tabEnablePin"]) return _documents[i].pinned;
    if (_documents[i].pinned) return YES;
    if ([TPPrefs b:@"pref.tabOnlyPinnedButton"]) return NO;
    return i == _selectedIndex || i == _hoverIndex || [TPPrefs b:@"pref.tabInactiveButtons"];
}

- (BOOL)showCloseFor:(NSInteger)i {
    if (![TPPrefs b:@"pref.tabShowClose"]) return NO;
    return i == _selectedIndex || i == _hoverIndex || [TPPrefs b:@"pref.tabInactiveButtons"];
}

// tab rectangles for a bar of the given width; Preferences > Tab Bar > Multi-line wraps them into rows
- (NSArray<NSValue *> *)layoutForWidth:(CGFloat)width {
    NSMutableArray *rects = [NSMutableArray array];
    CGFloat x = 2, y = 2;
    NSDictionary *attrs = @{NSFontAttributeName: self.tabFont};
    BOOL closeBtn = [TPPrefs b:@"pref.tabShowClose"], pinBtn = [TPPrefs b:@"pref.tabEnablePin"], multi = [TPPrefs b:@"pref.tabMultiline"];
    for (TPDocument *d in _documents) {
        CGFloat textW = ceil([[self labelFor:d] sizeWithAttributes:attrs].width);
        CGFloat w = kPad + kIconSize + 4 + textW + 6 + (closeBtn ? kBtnSize + 3 : 0) + ((pinBtn || d.pinned) ? kBtnSize + 3 : 0) + kPad;
        w = MAX(kTabMinWidth, w);
        if (multi && x > 2 && x + w > width - 2) { x = 2; y += self.tabHeight + 1; }
        [rects addObject:[NSValue valueWithRect:NSMakeRect(x, y, w, self.tabHeight)]];
        x += w + 1;
    }
    return rects;
}
- (NSInteger)rowCount {
    NSInteger rows = 1;
    for (NSValue *v in _rects) rows = MAX(rows, (NSInteger)lround((v.rectValue.origin.y - 2) / (self.tabHeight + 1)) + 1);
    return rows;
}
- (CGFloat)heightForWidth:(CGFloat)width {
    NSArray *rects = [self layoutForWidth:width];
    CGFloat bottom = self.tabHeight + 2;
    for (NSValue *v in rects) bottom = MAX(bottom, NSMaxY(v.rectValue));
    return bottom + 1;   // single row: tabHeight + 3, as before
}

- (void)reload {
    [_rects setArray:[self layoutForWidth:NSWidth(self.bounds) > 10 ? NSWidth(self.bounds) : 10000]];
    self.needsDisplay = YES;
}
- (void)setFrameSize:(NSSize)s { [super setFrameSize:s]; [self reload]; }

- (void)setDocuments:(NSArray<TPDocument *> *)documents { _documents = [documents copy]; [self reload]; }

// ---------------------------------------------------------------- accessibility (VoiceOver): a tab group of tabs
- (BOOL)isAccessibilityElement { return YES; }
- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityTabGroupRole; }
- (NSString *)accessibilityLabel { return @"Documents"; }
- (NSArray *)accessibilityChildren {
    NSMutableArray *tabs = [NSMutableArray array];
    __weak TPTabBarView *ws = self;
    for (NSInteger i = 0; i < (NSInteger)_documents.count; ++i) {
        TPDocument *d = _documents[(NSUInteger)i];
        TPAXElement *e = [TPAXElement accessibilityElementWithRole:NSAccessibilityRadioButtonRole frame:NSZeroRect
                                                             label:d.tabLabel parent:self];
        e.accessibilitySubrole = NSAccessibilityTabButtonSubrole;
        e.accessibilityRoleDescription = @"tab";
        e.accessibilityFrameInParentSpace = [self rectForTabAtIndex:i];
        e.accessibilityValue = @(i == _selectedIndex ? 1 : 0);
        e.accessibilityHelp = d.path ?: d.displayName;
        e.pressHandler = ^BOOL { TPTabBarView *b = ws; if (!b) return NO; [b.delegate tabBar:b didSelectIndex:i]; return YES; };
        e.accessibilityCustomActions = @[[[NSAccessibilityCustomAction alloc] initWithName:@"Close" handler:^BOOL {
            TPTabBarView *b = ws; if (!b) return NO; [b.delegate tabBar:b didRequestCloseIndex:i]; return YES; }]];
        [tabs addObject:e];
    }
    return tabs;
}
- (NSArray *)accessibilityTabs { return self.accessibilityChildren; }
- (void)setSelectedIndex:(NSInteger)selectedIndex { _selectedIndex = selectedIndex; self.needsDisplay = YES; }
- (void)setFocused:(BOOL)focused { _focused = focused; self.needsDisplay = YES; }

- (NSRect)rectForTabAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_rects.count) return NSZeroRect;
    return _rects[index].rectValue;
}

- (NSRect)closeRectForTab:(NSRect)r {
    return NSMakeRect(NSMaxX(r) - kPad - kBtnSize, NSMidY(r) - kBtnSize / 2, kBtnSize, kBtnSize);
}

- (NSRect)pinRectForTab:(NSRect)r {
    CGFloat right = [TPPrefs b:@"pref.tabShowClose"] ? NSMaxX(r) - kPad - kBtnSize - 3 : NSMaxX(r) - kPad;
    return NSMakeRect(right - kBtnSize, NSMidY(r) - kBtnSize / 2, kBtnSize, kBtnSize);
}

- (NSInteger)indexAtPoint:(NSPoint)p {
    for (NSInteger i = 0; i < (NSInteger)_rects.count; ++i)
        if (NSPointInRect(p, _rects[i].rectValue)) return i;
    return -1;
}

- (void)drawRect:(NSRect)dirty {
    TPLanguageService *ls = [TPLanguageService shared];
    TPStyleSpec *focusInd = [ls globalStyle:@"Active tab focused indicator"];
    TPStyleSpec *unfocusInd = [ls globalStyle:@"Active tab unfocused indicator"];
    [[TPChrome tabStripBackground] setFill];
    NSRectFill(self.bounds);
    [[TPChrome border] setFill];
    NSRectFill(NSMakeRect(0, NSMaxY(self.bounds) - 1, NSWidth(self.bounds), 1));
    BOOL alt = [TPPrefs b:@"pref.tabAltIcons"];
    const BOOL modern = [TPPrefs b:@"pref.modernLook"];
    NSFont *font = self.tabFont;
    for (NSInteger i = 0; i < (NSInteger)_documents.count; ++i) {
        TPDocument *d = _documents[i];
        NSRect r = _rects[i].rectValue;
        BOOL active = i == _selectedIndex;
        NSColor *bg;
        if (active) bg = [TPChrome tabActive];
        else if (d.tabColor >= 0) {
            TPStyleSpec *tc = [ls globalStyle:[NSString stringWithFormat:@"Tab color %ld", (long)d.tabColor + 1]];
            bg = tc && tc.bg >= 0 ? hexColor(tc.bg) : [TPChrome tabInactive];
        } else if (i == _hoverIndex) bg = [TPChrome tabHover];
        else bg = [TPPrefs b:@"pref.tabDrawInactive"] ? [TPChrome tabInactive] : [TPChrome tabActive];
        NSRect tabRect = active ? NSMakeRect(r.origin.x, r.origin.y - 1, r.size.width, r.size.height + 1) : r;
        if (modern) {
            // View > Modern Look: rounded "card" tabs; the active one joins the editor below, others show on hover
            NSRect card = NSMakeRect(r.origin.x + 1.5, r.origin.y + 3, r.size.width - 3, r.size.height + 8);
            const BOOL filled = active || i == _hoverIndex || d.tabColor >= 0;
            if (filled) {
                [NSGraphicsContext saveGraphicsState];
                NSRectClip(NSMakeRect(card.origin.x - 2, card.origin.y - 2, card.size.width + 4, NSMaxY(self.bounds) - card.origin.y + 2));
                NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:card xRadius:7 yRadius:7];
                [(active ? bg : [bg colorWithAlphaComponent:d.tabColor >= 0 ? 0.85 : 0.7]) setFill];
                [shape fill];
                if (active) { [[[TPChrome border] colorWithAlphaComponent:0.9] setStroke]; shape.lineWidth = 1; [shape stroke]; }
                [NSGraphicsContext restoreGraphicsState];
            } else if (i + 1 < (NSInteger)_documents.count && i + 1 != _selectedIndex && i + 1 != _hoverIndex) {
                [[[TPChrome border] colorWithAlphaComponent:0.7] setFill];   // thin divider between plain tabs
                NSRectFill(NSMakeRect(NSMaxX(r) - 0.5, NSMidY(r) - 7, 1, 14));
            }
            if (active) {   // the active tab hides the strip's bottom line
                [bg setFill];
                NSRectFill(NSMakeRect(card.origin.x + 1, NSMaxY(self.bounds) - 1, card.size.width - 2, 1));
                if ([TPPrefs b:@"pref.tabOrangeBar"]) {
                    [(_focused ? NSColor.controlAccentColor : [NSColor.controlAccentColor colorWithAlphaComponent:0.45]) setFill];
                    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(card.origin.x + 8, card.origin.y + 0.5, card.size.width - 16, 2.5) xRadius:1.25 yRadius:1.25] fill];
                }
            }
        } else {
        [bg setFill];
        NSRectFill(tabRect);
        [[TPChrome border] setStroke];
        NSBezierPath *border = [NSBezierPath bezierPathWithRect:NSInsetRect(tabRect, 0.5, 0.5)];
        border.lineWidth = 1;
        [border stroke];
        if (active && [TPPrefs b:@"pref.tabOrangeBar"]) {
            int indic = _focused ? (focusInd.fg >= 0 ? focusInd.fg : 0xFAAA3C) : (unfocusInd.fg >= 0 ? unfocusInd.fg : 0xFFCAB0);
            [hexColor(indic) setFill];
            NSRectFill(NSMakeRect(tabRect.origin.x, tabRect.origin.y, tabRect.size.width, 3));
        }
        }
        NSString *iconName = (d.userReadOnly || d.diskReadOnly) ? @"readonly" : (d.dirty ? @"unsaved" : @"saved");
        if (alt) iconName = [iconName stringByAppendingString:@"_alt"];
        if (d.monitoring) iconName = @"monitoring";
        NSImage *icon = tabIcon(iconName);
        NSRect iconRect = NSMakeRect(r.origin.x + kPad, NSMidY(r) - kIconSize / 2, kIconSize, kIconSize);
        [icon drawInRect:iconRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
        NSColor *fg = active ? [TPChrome tabActiveText] : [TPChrome tabInactiveText];
        if (active && ![TPChrome dark]) {
            TPStyleSpec *at = [ls globalStyle:@"Active tab text"];
            if (at.fg >= 0) fg = hexColor(at.fg);
        }
        NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
        ps.lineBreakMode = NSLineBreakByTruncatingTail;
        NSDictionary *attrs = @{NSFontAttributeName: font, NSForegroundColorAttributeName: fg, NSParagraphStyleAttributeName: ps};
        CGFloat textRight = NSMaxX(r) - kPad;
        if ([self showCloseFor:i] || [TPPrefs b:@"pref.tabShowClose"]) textRight -= kBtnSize + 3;
        if ([TPPrefs b:@"pref.tabEnablePin"] || d.pinned) textRight -= kBtnSize + 3;
        NSRect textRect = NSMakeRect(NSMaxX(iconRect) + 4, NSMidY(r) - (font.pointSize + 4) / 2, textRight - NSMaxX(iconRect) - 4, font.pointSize + 4);
        [[self labelFor:d] drawInRect:textRect withAttributes:attrs];
        if ([self showCloseFor:i]) {
            NSString *closeName = (i == _hoverIndex && _hoverButton == 1) ? @"closeTabButton_hoverIn" : (active || i == _hoverIndex ? @"closeTabButton" : @"closeTabButton_hoverOnTab");
            [tabIcon(closeName) drawInRect:[self closeRectForTab:r] fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
        }
        if ([self showPinFor:i]) {
            NSString *pinName = d.pinned ? @"pinTabButton_pinned" : ((i == _hoverIndex && _hoverButton == 2) ? @"pinTabButton_hover" : @"pinTabButton");
            NSImage *pi = tabIcon(pinName) ?: tabIcon(@"pinTabButton");
            [pi drawInRect:[self pinRectForTab:r] fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
        }
    }
}

- (void)mouseMoved:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    NSInteger i = [self indexAtPoint:p];
    NSInteger btn = 0;
    if (i >= 0) {
        NSRect r = _rects[i].rectValue;
        if (NSPointInRect(p, NSInsetRect([self closeRectForTab:r], -2, -2)) && [TPPrefs b:@"pref.tabShowClose"]) btn = 1;
        else if (NSPointInRect(p, NSInsetRect([self pinRectForTab:r], -2, -2)) && ([TPPrefs b:@"pref.tabEnablePin"] || _documents[i].pinned)) btn = 2;
    }
    if (i != _hoverIndex || btn != _hoverButton) {
        const BOOL tabChanged = i != _hoverIndex;
        _hoverIndex = i;
        _hoverButton = btn;
        self.needsDisplay = YES;
        if (tabChanged && [self.delegate respondsToSelector:@selector(tabBar:didHoverIndex:)]) [self.delegate tabBar:self didHoverIndex:i];
    }
    if (i >= 0 && i < (NSInteger)_documents.count) self.toolTip = _documents[i].path ?: _documents[i].displayName;
}

- (void)mouseExited:(NSEvent *)e {
    const BOOL was = _hoverIndex >= 0;
    _hoverIndex = -1;
    _hoverButton = 0;
    self.needsDisplay = YES;
    if (was && [self.delegate respondsToSelector:@selector(tabBar:didHoverIndex:)]) [self.delegate tabBar:self didHoverIndex:-1];
}

- (void)mouseDown:(NSEvent *)e {
    if ([self.delegate respondsToSelector:@selector(tabBar:didHoverIndex:)]) [self.delegate tabBar:self didHoverIndex:-1];   // clicked: stop peeking
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    NSInteger i = [self indexAtPoint:p];
    if (i < 0) {
        if (e.clickCount == 2) [self.delegate tabBarDidDoubleClickEmptyArea:self];
        return;
    }
    NSRect r = _rects[i].rectValue;
    if ([self showCloseFor:i] && NSPointInRect(p, NSInsetRect([self closeRectForTab:r], -2, -2))) {
        [self.delegate tabBar:self didRequestCloseIndex:i];
        return;
    }
    if ([self showPinFor:i] && NSPointInRect(p, NSInsetRect([self pinRectForTab:r], -2, -2))) {
        [self.delegate tabBar:self didTogglePinIndex:i];
        return;
    }
    if (e.clickCount == 2 && [TPPrefs b:@"pref.tabDblClickClose"]) {
        [self.delegate tabBar:self didRequestCloseIndex:i];
        return;
    }
    [self.delegate tabBar:self didSelectIndex:i];
    _dragIndex = [TPPrefs b:@"pref.tabLock"] ? -1 : i;
    _dragStart = p;
    _dragging = NO;
}

- (void)mouseDragged:(NSEvent *)e {
    if (_dragIndex < 0) return;
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    if (!_dragging && fabs(p.x - _dragStart.x) < 4 && fabs(p.y - _dragStart.y) < 4) return;
    _dragging = YES;
    if (p.y < -NSHeight(self.bounds) || p.y > 2 * NSHeight(self.bounds)) { [[NSCursor dragCopyCursor] set]; return; }   // leaving the bar
    [[NSCursor arrowCursor] set];
    NSInteger target = [self indexAtPoint:NSMakePoint(p.x, NSMidY(self.bounds))];
    if (target < 0) target = p.x < 0 ? 0 : (NSInteger)_documents.count - 1;
    if (target != _dragIndex && target >= 0) {
        [self.delegate tabBar:self didMoveFrom:_dragIndex to:target];
        _dragIndex = target;
    }
}

- (void)mouseUp:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    BOOL outside = p.y < -NSHeight(self.bounds) || p.y > 2 * NSHeight(self.bounds) || p.x < -20 || p.x > NSWidth(self.bounds) + 20;
    if (_dragging && _dragIndex >= 0 && outside && [self.delegate respondsToSelector:@selector(tabBar:didDropIndex:atWindowPoint:copy:)])
        [self.delegate tabBar:self didDropIndex:_dragIndex atWindowPoint:e.locationInWindow copy:(e.modifierFlags & NSEventModifierFlagOption) != 0];
    [[NSCursor arrowCursor] set];
    _dragIndex = -1; _dragging = NO;
}

- (void)otherMouseUp:(NSEvent *)e {
    if (e.buttonNumber != 2) return;   // middle click closes, as upstream
    NSInteger i = [self indexAtPoint:[self convertPoint:e.locationInWindow fromView:nil]];
    if (i >= 0) [self.delegate tabBar:self didRequestCloseIndex:i];
}

- (NSMenu *)menuForEvent:(NSEvent *)e {
    NSInteger i = [self indexAtPoint:[self convertPoint:e.locationInWindow fromView:nil]];
    if (i < 0) return nil;
    [self.delegate tabBar:self didSelectIndex:i];
    return [self.delegate tabBar:self menuForIndex:i];
}

@end
