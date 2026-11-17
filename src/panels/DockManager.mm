// Textpad++ — docking panels. GPL-3.0-or-later.
#import "panels/DockManager.h"
#import "app/Preferences.h"

@interface TPDockHeader : NSView
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) void (^onClose)(void);
@property (nonatomic, copy, nullable) void (^onMenu)(NSEvent *e, NSView *v);
@end
@implementation TPDockHeader
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)r {
    [[TPChrome tabStripBackground] setFill];
    NSRectFill(self.bounds);
    [[TPChrome border] setFill];
    NSRectFill(NSMakeRect(0, NSHeight(self.bounds) - 1, NSWidth(self.bounds), 1));
    [_title drawAtPoint:NSMakePoint(8, 4) withAttributes:@{NSFontAttributeName: [NSFont boldSystemFontOfSize:11.5], NSForegroundColorAttributeName: [TPChrome statusText]}];
    NSRect x = [self closeRect];
    NSBezierPath *p = [NSBezierPath bezierPath];
    [p moveToPoint:NSMakePoint(NSMinX(x) + 4, NSMinY(x) + 4)]; [p lineToPoint:NSMakePoint(NSMaxX(x) - 4, NSMaxY(x) - 4)];
    [p moveToPoint:NSMakePoint(NSMaxX(x) - 4, NSMinY(x) + 4)]; [p lineToPoint:NSMakePoint(NSMinX(x) + 4, NSMaxY(x) - 4)];
    [[TPChrome tabInactiveText] setStroke];
    p.lineWidth = 1.4;
    [p stroke];
    NSRect m = [self menuRect];   // the dock menu: a small chevron
    NSBezierPath *c = [NSBezierPath bezierPath];
    [c moveToPoint:NSMakePoint(NSMinX(m) + 4, NSMinY(m) + 6)]; [c lineToPoint:NSMakePoint(NSMidX(m), NSMaxY(m) - 5)]; [c lineToPoint:NSMakePoint(NSMaxX(m) - 4, NSMinY(m) + 6)];
    c.lineWidth = 1.4;
    [c stroke];
}
- (NSRect)closeRect { return NSMakeRect(NSWidth(self.bounds) - 22, 3, 16, 16); }
- (NSRect)menuRect { return NSMakeRect(NSWidth(self.bounds) - 42, 3, 16, 16); }
- (void)mouseDown:(NSEvent *)e {
    NSPoint pt = [self convertPoint:e.locationInWindow fromView:nil];
    if (NSPointInRect(pt, [self closeRect]) && _onClose) _onClose();
    else if ((NSPointInRect(pt, [self menuRect]) || e.type == NSEventTypeRightMouseDown) && _onMenu) _onMenu(e, self);
}
- (void)rightMouseDown:(NSEvent *)e { if (_onMenu) _onMenu(e, self); }
- (BOOL)isAccessibilityElement { return YES; }
- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityGroupRole; }
- (NSString *)accessibilityLabel { return _title; }
@end

@implementation TPDockContainer {
    NSMutableArray<id<TPPanel>> *_panels;
    TPDockHeader *_header;
    NSSegmentedControl *_tabs;
}
- (instancetype)initWithFrame:(NSRect)f {
    if ((self = [super initWithFrame:f])) {
        _panels = [NSMutableArray array];
        _header = [[TPDockHeader alloc] initWithFrame:NSMakeRect(0, 0, f.size.width, 22)];
        __weak TPDockContainer *ws = self;
        _header.onClose = ^{ TPDockContainer *s = ws; if (s.activePanel && s.closeHandler) s.closeHandler(s.activePanel); };
        _header.onMenu = ^(NSEvent *e, NSView *v) { [ws showDockMenu:e inView:v]; };
        [self addSubview:_header];
        _tabs = [NSSegmentedControl segmentedControlWithLabels:@[] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(tabClicked:)];
        _tabs.controlSize = NSControlSizeSmall;
        _tabs.font = [NSFont systemFontOfSize:10.5];
        [self addSubview:_tabs];
    }
    return self;
}
- (BOOL)isFlipped { return YES; }
- (NSArray<id<TPPanel>> *)panels { return _panels; }
- (void)showDockMenu:(NSEvent *)e inView:(NSView *)v {
    id<TPPanel> p = _activePanel;
    if (!p || !_moveHandler) return;
    NSMenu *m = [[NSMenu alloc] initWithTitle:@"Dock"];
    NSArray *titles = @[@"Dock Left", @"Dock Right", @"Dock Top", @"Dock Bottom", @"Floating"];
    for (NSUInteger i = 0; i < titles.count; ++i) {
        NSMenuItem *mi = [m addItemWithTitle:titles[i] action:@selector(dockMenuChosen:) keyEquivalent:@""];
        mi.target = self;
        mi.tag = (NSInteger)i;
    }
    [NSMenu popUpContextMenu:m withEvent:e forView:v];
}
- (void)dockMenuChosen:(NSMenuItem *)mi { if (_activePanel && _moveHandler) _moveHandler(_activePanel, (TPDockSide)mi.tag); }
- (void)addPanel:(id<TPPanel>)p {
    if (![_panels containsObject:p]) [_panels addObject:p];
    self.activePanel = p;
}
- (void)removePanel:(id<TPPanel>)p {
    [_panels removeObject:p];
    [p.panelView removeFromSuperview];
    if (_activePanel == p) self.activePanel = _panels.lastObject;
    else [self layoutContents];
}
- (void)setActivePanel:(id<TPPanel>)p {
    if (_activePanel && _activePanel != p) [_activePanel.panelView removeFromSuperview];
    _activePanel = p;
    if (p && p.panelView.superview != self) [self addSubview:p.panelView];
    [self layoutContents];
    if (p && [p respondsToSelector:@selector(panelDidShow)]) [p panelDidShow];
}
- (void)tabClicked:(id)sender {
    NSInteger i = _tabs.selectedSegment;
    if (i >= 0 && i < (NSInteger)_panels.count) self.activePanel = _panels[(NSUInteger)i];
}
- (void)resizeSubviewsWithOldSize:(NSSize)old { [self layoutContents]; }
- (void)layoutContents {
    NSRect b = self.bounds;
    _header.frame = NSMakeRect(0, 0, NSWidth(b), 22);
    _header.title = _activePanel.panelTitle ?: @"";
    _header.needsDisplay = YES;
    BOOL tabs = _panels.count > 1;   // upstream shows tabs at the bottom when a container holds several panels
    _tabs.hidden = !tabs;
    CGFloat tabH = tabs ? 24 : 0;
    if (tabs) {
        _tabs.segmentCount = (NSInteger)_panels.count;
        for (NSUInteger i = 0; i < _panels.count; ++i) {
            [_tabs setLabel:_panels[i].panelTitle forSegment:(NSInteger)i];
            [_tabs setWidth:0 forSegment:(NSInteger)i];
        }
        _tabs.selectedSegment = (NSInteger)[_panels indexOfObject:_activePanel];
        _tabs.frame = NSMakeRect(2, NSHeight(b) - tabH + 1, NSWidth(b) - 4, tabH - 2);
    }
    _activePanel.panelView.frame = NSMakeRect(0, 22, NSWidth(b), MAX(0, NSHeight(b) - 22 - tabH));
}
- (void)drawRect:(NSRect)r { [[TPChrome barBackground] setFill]; NSRectFill(self.bounds); }
@end

@interface TPFloatingPanelWindow : NSPanel
@property (nonatomic, copy) NSString *panelIdentifier;
@end
@implementation TPFloatingPanelWindow
@end

@implementation TPDockManager {
    NSMutableDictionary<NSString *, id<TPPanel>> *_panels;
    NSMutableDictionary<NSString *, TPFloatingPanelWindow *> *_floating;
    NSView *_center;
    NSSplitView *_column;      // top dock | editors | bottom dock
    CGFloat _sizes[4];
}

- (instancetype)initWithCenter:(NSView *)center {
    if ((self = [super init])) {
        _panels = [NSMutableDictionary dictionary];
        _floating = [NSMutableDictionary dictionary];
        _center = center;
        _splitView = [[NSSplitView alloc] initWithFrame:center.frame];
        _splitView.vertical = YES;
        _splitView.dividerStyle = NSSplitViewDividerStyleThin;
        _splitView.delegate = self;
        _column = [[NSSplitView alloc] initWithFrame:center.frame];
        _column.vertical = NO;
        _column.dividerStyle = NSSplitViewDividerStyleThin;
        _column.delegate = self;
        _leftDock = [[TPDockContainer alloc] initWithFrame:NSMakeRect(0, 0, 250, 600)];
        _rightDock = [[TPDockContainer alloc] initWithFrame:NSMakeRect(0, 0, 280, 600)];
        _topDock = [[TPDockContainer alloc] initWithFrame:NSMakeRect(0, 0, 600, 180)];
        _bottomDock = [[TPDockContainer alloc] initWithFrame:NSMakeRect(0, 0, 600, 180)];
        __weak TPDockManager *ws = self;
        for (TPDockContainer *d in @[_leftDock, _rightDock, _topDock, _bottomDock]) {
            d.closeHandler = ^(id<TPPanel> p) { [ws hidePanel:p.panelIdentifier]; };
            d.moveHandler = ^(id<TPPanel> p, TPDockSide side) { [ws movePanel:p.panelIdentifier toSide:side]; };
            d.hidden = YES;
        }
        [_column addSubview:_topDock];
        [_column addSubview:center];
        [_column addSubview:_bottomDock];
        [_splitView addSubview:_leftDock];
        [_splitView addSubview:_column];
        [_splitView addSubview:_rightDock];
        for (NSSplitView *sv in @[_splitView, _column]) {
            [sv setHoldingPriority:NSLayoutPriorityDefaultLow + 10 forSubviewAtIndex:0];
            [sv setHoldingPriority:NSLayoutPriorityDefaultLow - 10 forSubviewAtIndex:1];
            [sv setHoldingPriority:NSLayoutPriorityDefaultLow + 10 forSubviewAtIndex:2];
        }
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        _sizes[0] = MAX(160, [ud doubleForKey:@"dock.leftWidth"] ?: 250);
        _sizes[1] = MAX(160, [ud doubleForKey:@"dock.rightWidth"] ?: 280);
        _sizes[2] = MAX(90, [ud doubleForKey:@"dock.topHeight"] ?: 180);
        _sizes[3] = MAX(90, [ud doubleForKey:@"dock.bottomHeight"] ?: 180);
    }
    return self;
}

- (void)registerPanel:(id<TPPanel>)p { _panels[p.panelIdentifier] = p; }

- (void)ensureDockSize:(CGFloat)fraction forSide:(TPDockSide)side {
    if (side < TPDockLeft || side > TPDockBottom) return;
    const BOOL vertical = side <= TPDockRight;
    NSSplitView *sv = vertical ? _splitView : _column;
    const CGFloat total = vertical ? NSWidth(sv.bounds) : NSHeight(sv.bounds);
    if (total > 200) _sizes[side] = MAX(_sizes[side], total * fraction);
}
- (id<TPPanel>)panelWithIdentifier:(NSString *)i { return _panels[i]; }

- (TPDockSide)sideOfPanel:(NSString *)i {
    id<TPPanel> p = _panels[i];
    NSNumber *side = [[NSUserDefaults standardUserDefaults] objectForKey:[@"dock.side." stringByAppendingString:i]];
    TPDockSide s = side ? (TPDockSide)side.integerValue : (p ? p.defaultSide : TPDockLeft);
    return s < TPDockLeft || s > TPDockFloating ? TPDockLeft : s;
}

- (NSArray<TPDockContainer *> *)docks { return @[_leftDock, _rightDock, _topDock, _bottomDock]; }

- (TPDockContainer *)dockFor:(id<TPPanel>)p {
    switch ([self sideOfPanel:p.panelIdentifier]) {
        case TPDockRight: return _rightDock;
        case TPDockTop: return _topDock;
        case TPDockBottom: return _bottomDock;
        default: return _leftDock;
    }
}

- (BOOL)isPanelVisible:(NSString *)i {
    id<TPPanel> p = _panels[i];
    if (!p) return NO;
    if (_floating[i].isVisible) return YES;
    for (TPDockContainer *d in self.docks) if ([d.panels containsObject:p]) return YES;
    return NO;
}

- (NSWindow *)floatingWindowOfPanel:(NSString *)i { return _floating[i].isVisible ? _floating[i] : nil; }

- (void)updateDock:(TPDockContainer *)d {
    BOOL want = d.panels.count > 0;
    if (want == !d.hidden) { [d layoutContents]; return; }
    const NSInteger idx = [self.docks indexOfObject:d];
    const BOOL vertical = idx < 2;
    NSSplitView *sv = vertical ? _splitView : _column;
    const CGFloat cur = vertical ? NSWidth(d.frame) : NSHeight(d.frame);
    if (!want) _sizes[idx] = cur > 50 ? cur : _sizes[idx];
    d.hidden = !want;
    [sv adjustSubviews];
    if (want) {
        const CGFloat total = vertical ? NSWidth(sv.bounds) : NSHeight(sv.bounds), w = MIN(_sizes[idx], total * 0.45);
        if (idx == 0 || idx == 2) [sv setPosition:w ofDividerAtIndex:0];
        else [sv setPosition:total - w - sv.dividerThickness ofDividerAtIndex:1];
    }
    [d layoutContents];
}

- (void)showPanel:(NSString *)i {
    id<TPPanel> p = _panels[i];
    if (!p) return;
    if ([self sideOfPanel:i] == TPDockFloating) {
        TPFloatingPanelWindow *w = _floating[i];
        if (!w) {
            w = [[TPFloatingPanelWindow alloc] initWithContentRect:NSMakeRect(0, 0, 320, 420)
                                                        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow
                                                          backing:NSBackingStoreBuffered defer:YES];
            w.panelIdentifier = i;
            w.releasedWhenClosed = NO;
            w.hidesOnDeactivate = NO;
            w.floatingPanel = YES;
            w.becomesKeyOnlyIfNeeded = YES;
            w.frameAutosaveName = [@"panel.float." stringByAppendingString:i];
            TPDockContainer *box = [[TPDockContainer alloc] initWithFrame:w.contentView.bounds];
            box.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            __weak TPDockManager *ws = self;
            box.closeHandler = ^(id<TPPanel> pp) { [ws hidePanel:pp.panelIdentifier]; };
            box.moveHandler = ^(id<TPPanel> pp, TPDockSide side) { [ws movePanel:pp.panelIdentifier toSide:side]; };
            w.contentView = box;
            [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification object:w queue:nil usingBlock:^(NSNotification *n) {
                TPDockManager *s = ws;
                if (s && s->_floating[i] == n.object && [s isPanelVisible:i]) [s hidePanel:i];
            }];
            if (![w setFrameUsingName:w.frameAutosaveName]) [w center];
            _floating[i] = w;
        }
        w.title = p.panelTitle;
        [(TPDockContainer *)w.contentView addPanel:p];
        [w orderFront:nil];
    } else {
        TPDockContainer *d = [self dockFor:p];
        [d addPanel:p];
        [self updateDock:d];
    }
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:[@"panel.visible." stringByAppendingString:i]];
}

- (void)hidePanel:(NSString *)i {
    id<TPPanel> p = _panels[i];
    if (!p) return;
    for (TPDockContainer *d in self.docks) {
        if (![d.panels containsObject:p]) continue;
        [d removePanel:p];
        [self updateDock:d];
    }
    TPFloatingPanelWindow *w = _floating[i];
    if (w) {
        [(TPDockContainer *)w.contentView removePanel:p];
        if (w.isVisible) { _floating[i] = nil; [w orderOut:nil]; _floating[i] = w; }
    }
    if ([p respondsToSelector:@selector(panelDidHide)]) [p panelDidHide];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:[@"panel.visible." stringByAppendingString:i]];
}

- (void)movePanel:(NSString *)i toSide:(TPDockSide)side {
    const BOOL wasVisible = [self isPanelVisible:i];
    if (wasVisible) [self hidePanel:i];
    [[NSUserDefaults standardUserDefaults] setInteger:side forKey:[@"dock.side." stringByAppendingString:i]];
    if (wasVisible) [self showPanel:i];
}

- (void)togglePanel:(NSString *)i {
    if ([self isPanelVisible:i]) [self hidePanel:i];
    else [self showPanel:i];
}

- (NSArray<NSString *> *)visiblePanelIdentifiers {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *i in _panels) if ([self isPanelVisible:i]) [a addObject:i];
    return [a sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray<TPDockContainer *> *)allContainers {
    NSMutableArray *a = [self.docks mutableCopy];
    for (TPFloatingPanelWindow *w in _floating.allValues) if (w.isVisible) [a addObject:(TPDockContainer *)w.contentView];
    return a;
}
- (void)notifyDocumentsChanged {
    for (TPDockContainer *d in self.allContainers)
        if ([d.activePanel respondsToSelector:@selector(documentsChanged)]) [d.activePanel documentsChanged];
}
- (void)notifyEditorViewChanged {
    for (TPDockContainer *d in self.allContainers)
        if ([d.activePanel respondsToSelector:@selector(editorViewChanged)]) [d.activePanel editorViewChanged];
}

// keep the editor area usable; remember dock sizes
- (CGFloat)splitView:(NSSplitView *)sv constrainMinCoordinate:(CGFloat)p ofSubviewAt:(NSInteger)i { return i == 0 ? (sv == _column ? 60 : 120) : p; }
- (CGFloat)splitView:(NSSplitView *)sv constrainMaxCoordinate:(CGFloat)p ofSubviewAt:(NSInteger)i {
    return i == 1 ? (sv == _column ? NSHeight(sv.bounds) - 60 : NSWidth(sv.bounds) - 120) : p;
}
- (void)splitViewDidResizeSubviews:(NSNotification *)n {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (!_leftDock.hidden && NSWidth(_leftDock.frame) > 50) [ud setDouble:NSWidth(_leftDock.frame) forKey:@"dock.leftWidth"];
    if (!_rightDock.hidden && NSWidth(_rightDock.frame) > 50) [ud setDouble:NSWidth(_rightDock.frame) forKey:@"dock.rightWidth"];
    if (!_topDock.hidden && NSHeight(_topDock.frame) > 50) [ud setDouble:NSHeight(_topDock.frame) forKey:@"dock.topHeight"];
    if (!_bottomDock.hidden && NSHeight(_bottomDock.frame) > 50) [ud setDouble:NSHeight(_bottomDock.frame) forKey:@"dock.bottomHeight"];
}

@end
