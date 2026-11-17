// Textpad++ — Windows-style in-window menu bar. GPL-3.0-or-later.
#import "app/MenuBarView.h"
#import "app/MainWindowController.h"
#import "app/EditorPane.h"
#import "app/Document.h"
#import "app/Preferences.h"
#import "commands/CommandRegistry.h"
#import <Carbon/Carbon.h>
#import <objc/runtime.h>

using namespace npp;

extern NSString *TPMenuFileName(NSString *path, NSUInteger pos, BOOL ordinal);   // CommandsTools.mm

@implementation TPMenuBarView {
    __weak TPMainWindowController *_c;
    NSMutableArray<NSButton *> *_menuButtons, *_shortcutButtons;
    NSInteger _keyboardIndex;
}

- (instancetype)initWithController:(TPMainWindowController *)c {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 1100, 22)])) {
        _c = c;
        _keyboardIndex = -1;
        _menuButtons = [NSMutableArray array];
        _shortcutButtons = [NSMutableArray array];
        self.accessibilityRole = NSAccessibilityMenuBarRole;
        self.accessibilityLabel = @"Menu bar";
        [self rebuild];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }
- (CGFloat)preferredHeight { return 22; }
- (NSArray<NSButton *> *)menuButtons { return _menuButtons; }
- (NSArray<NSButton *> *)shortcutButtons { return _shortcutButtons; }

- (NSButton *)button:(NSString *)title action:(SEL)action {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    b.bordered = NO;
    b.font = [NSFont menuBarFontOfSize:0];
    b.contentTintColor = NSColor.labelColor;
    [b sizeToFit];
    return b;
}

- (void)rebuild {
    for (NSButton *b in [_menuButtons arrayByAddingObjectsFromArray:_shortcutButtons]) [b removeFromSuperview];
    [_menuButtons removeAllObjects];
    [_shortcutButtons removeAllObjects];
    NSArray<NSMenuItem *> *tops = NSApp.mainMenu.itemArray;
    for (NSUInteger i = 1; i < tops.count; ++i) {            // item 0 is the macOS application menu
        if (!tops[i].submenu || tops[i].hidden) continue;
        NSButton *b = [self button:tops[i].title action:@selector(openMenu:)];
        b.tag = (NSInteger)i;
        [self addSubview:b];
        [_menuButtons addObject:b];
    }
    // upstream Notepad_plus.rc: "＋" IDM_FILE_NEW, "▼" the tab list, "✕" IDM_FILE_CLOSE
    NSArray *shortcuts = @[@[@"＋", @(IDM_FILE_NEW), @"New"], @[@"▼", @0, @"List of the opened documents"], @[@"✕", @(IDM_FILE_CLOSE), @"Close"]];
    for (NSArray *s in shortcuts) {
        NSButton *b = [self button:s[0] action:@selector(shortcut:)];
        b.tag = [s[1] integerValue];
        b.toolTip = s[2];
        b.accessibilityLabel = s[2];
        [self addSubview:b];
        [_shortcutButtons addObject:b];
    }
    self.needsLayout = YES;
    [self layoutButtons];
}

- (void)layoutButtons {
    CGFloat x = 4, h = NSHeight(self.bounds);
    for (NSButton *b in _menuButtons) {
        b.frame = NSMakeRect(x, 0, NSWidth(b.frame) + 12, h);
        x += NSWidth(b.frame);
    }
    BOOL hideRight = [TPPrefs b:@"pref.hideRightShortcuts"];
    CGFloat r = NSWidth(self.bounds) - 4;
    for (NSButton *b in _shortcutButtons.reverseObjectEnumerator) {
        b.hidden = hideRight;
        b.frame = NSMakeRect(r - 26, 0, 26, h);
        r -= 26;
    }
}
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize { [self layoutButtons]; }

- (void)drawRect:(NSRect)dirtyRect {
    [[TPChrome barBackground] setFill];
    NSRectFill(self.bounds);
    [[TPChrome border] setFill];
    NSRectFill(NSMakeRect(0, NSHeight(self.bounds) - 1, NSWidth(self.bounds), 1));
}

// a fresh copy of the top-level menu: its dynamic items (recent files, Window list, macros…) refreshed first
- (NSMenu *)menuForButton:(NSButton *)button {
    NSArray<NSMenuItem *> *tops = NSApp.mainMenu.itemArray;
    if (button.tag <= 0 || button.tag >= (NSInteger)tops.count) return nil;
    NSMenu *orig = tops[(NSUInteger)button.tag].submenu;
    if ([orig.delegate respondsToSelector:@selector(menuNeedsUpdate:)]) [orig.delegate menuNeedsUpdate:orig];
    return [orig copy];
}

// ---- keyboard menu mode (F10, or ⌥ alone with Hide): ←/→, Return/↓/Space opens, the upstream mnemonic letters, Esc
- (NSInteger)keyboardIndex { return _keyboardIndex; }
- (void)setKeyboardIndex:(NSInteger)i {
    _keyboardIndex = i < 0 ? -1 : (_menuButtons.count ? i % (NSInteger)_menuButtons.count : -1);
    for (NSUInteger k = 0; k < _menuButtons.count; ++k) {
        NSButton *b = _menuButtons[k];
        b.wantsLayer = YES;
        b.layer.cornerRadius = 4;
        b.layer.backgroundColor = (NSInteger)k == _keyboardIndex ? [NSColor.selectedContentBackgroundColor colorWithAlphaComponent:0.35].CGColor : NSColor.clearColor.CGColor;
    }
}

// upstream mnemonics: &File &Edit &Search &View Encodi&ng &Language Se&ttings T&ools &Macro &Run &Plugins &Window, and h for Help
static unichar mnemonicOf(NSString *title) {
    static NSDictionary *m = @{@"Encoding": @"n", @"Settings": @"t", @"Tools": @"o"};
    NSString *k = m[title];
    return k ? [k characterAtIndex:0] : (title.length ? [title.lowercaseString characterAtIndex:0] : 0);
}

- (BOOL)handleMenuModeKey:(NSEvent *)e {
    const NSInteger n = (NSInteger)_menuButtons.count;
    switch (e.keyCode) {
        case kVK_LeftArrow: self.keyboardIndex = (_keyboardIndex + n - 1) % n; return YES;
        case kVK_RightArrow: self.keyboardIndex = (_keyboardIndex + 1) % n; return YES;
        case kVK_Escape: self.keyboardIndex = -1; [self menuLoopEnded]; return YES;
        case kVK_Return: case kVK_DownArrow: case kVK_Space: case kVK_ANSI_KeypadEnter: [self openMenuAtIndex:_keyboardIndex]; return YES;
    }
    NSString *ch = e.charactersIgnoringModifiers.lowercaseString;
    if (ch.length == 1)
        for (NSInteger i = 0; i < n; ++i)
            if (mnemonicOf(_menuButtons[(NSUInteger)i].title) == [ch characterAtIndex:0]) { self.keyboardIndex = i; [self openMenuAtIndex:i]; return YES; }
    TPBeep();
    return YES;   // menu mode keeps the keys away from the editor
}

- (void)openMenuAtIndex:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)_menuButtons.count) return;
    NSButton *b = _menuButtons[(NSUInteger)i];
    _keyboardIndex = -1;
    [self setKeyboardIndex:-1];
    if (_c.selfTestMode) { _lastKeyboardOpened = b.title; [self menuLoopEnded]; return; }
    [self openMenu:b];
}

- (void)openMenu:(NSButton *)b {
    NSMenu *m = [self menuForButton:b];
    if (!m) return;
    b.highlighted = YES;
    [m popUpMenuPositioningItem:nil atLocation:NSMakePoint(NSMinX(b.frame), NSMaxY(b.frame)) inView:self];
    b.highlighted = NO;
    [self menuLoopEnded];
}

// upstream WindowsMenu::initPopupMenu for the drop list: the current view's tabs, the current one checked,
// "*" after a modified document
- (NSMenu *)tabDropListMenu {
    NSMenu *m = [[NSMenu alloc] initWithTitle:@"▼"];
    TPEditorPane *pane = _c.activePane;
    for (TPDocument *d in pane.documents) {
        NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:[TPMenuFileName(d.path ?: d.displayName, 0, NO) stringByAppendingString:d.dirty ? @"*" : @""]
                                                    action:@selector(activateFromList:) keyEquivalent:@""];
        mi.target = self;
        mi.representedObject = d;
        mi.state = d == pane.currentDocument ? NSControlStateValueOn : NSControlStateValueOff;
        mi.toolTip = d.path;
        [m addItem:mi];
    }
    return m;
}
- (void)activateFromList:(NSMenuItem *)mi { [_c activateDocument:mi.representedObject inPane:_c.activePane]; }

- (void)shortcut:(NSButton *)b {
    if (b.tag) [[TPCommandRegistry shared] execute:static_cast<int>(b.tag)];
    else [[self tabDropListMenu] popUpMenuPositioningItem:nil atLocation:NSMakePoint(NSMinX(b.frame), NSMaxY(b.frame)) inView:self];
    [self menuLoopEnded];
}

// upstream WM_EXITMENULOOP: a hidden menu bar hides again once its menu closes
- (void)menuLoopEnded {
    if (_c.inWindowMenuTemporarilyShown) { _c.inWindowMenuTemporarilyShown = NO; [_c applyInWindowMenuVisibility]; }
}

@end

@implementation TPMainWindowController (InWindowMenu)
static char kTempShown, kOptionAlone;

- (TPMenuBarView *)inWindowMenuBar {
    for (NSView *v in self.window.contentView.subviews) if ([v isKindOfClass:TPMenuBarView.class]) return (TPMenuBarView *)v;
    return nil;
}
- (BOOL)inWindowMenuTemporarilyShown { return [objc_getAssociatedObject(self, &kTempShown) boolValue]; }
- (void)setInWindowMenuTemporarilyShown:(BOOL)v { objc_setAssociatedObject(self, &kTempShown, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

- (void)applyInWindowMenuVisibility {
    TPMenuBarView *bar = self.inWindowMenuBar;
    if (!bar) return;
    NSMutableArray *titles = [NSMutableArray array];
    for (NSUInteger i = 1; i < NSApp.mainMenu.itemArray.count; ++i) if (NSApp.mainMenu.itemArray[i].submenu) [titles addObject:NSApp.mainMenu.itemArray[i].title];
    if (![[bar.menuButtons valueForKey:@"title"] isEqualToArray:titles]) [bar rebuild];   // first time, or another interface language
    const BOOL want = [TPPrefs b:@"pref.inWindowMenu"] && !self.chromeForcedHidden &&
                      (![TPPrefs b:@"pref.menuHidden"] || self.inWindowMenuTemporarilyShown);
    if (bar.hidden == want) {
        bar.hidden = !want;
        [self.window.contentView resizeSubviewsWithOldSize:self.window.contentView.bounds.size];
    }
    [bar layoutButtons];
    bar.needsDisplay = YES;
}

// Preferences > General > Menu > Hide: F10, or ⌥ Option pressed and released alone (upstream: Alt / F10)
- (BOOL)handleMenuBarToggleEvent:(NSEvent *)e {
    if (![TPPrefs b:@"pref.inWindowMenu"]) return NO;
    TPMenuBarView *bar = self.inWindowMenuBar;
    if (bar.keyboardIndex >= 0 && e.type == NSEventTypeKeyDown && e.keyCode != kVK_F10) {
        objc_setAssociatedObject(self, &kOptionAlone, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return [bar handleMenuModeKey:e];
    }
    const BOOL hiding = [TPPrefs b:@"pref.menuHidden"];
    const NSEventModifierFlags m = e.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    BOOL toggle = NO;
    if (e.type == NSEventTypeKeyDown) {
        objc_setAssociatedObject(self, &kOptionAlone, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        toggle = e.keyCode == kVK_F10 && !(m & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift));
    } else if (e.type == NSEventTypeFlagsChanged && hiding) {   // ⌥ alone only while the bar is hidden (it would get in the way of typing)
        const NSEventModifierFlags others = NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagShift | NSEventModifierFlagFunction;
        if ((m & NSEventModifierFlagOption) && !(m & others)) objc_setAssociatedObject(self, &kOptionAlone, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        else {
            toggle = !(m & NSEventModifierFlagOption) && !(m & others) && [objc_getAssociatedObject(self, &kOptionAlone) boolValue];
            objc_setAssociatedObject(self, &kOptionAlone, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else objc_setAssociatedObject(self, &kOptionAlone, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!toggle) return NO;
    if (bar.keyboardIndex >= 0) {   // leave menu mode (upstream: Alt / F10 again)
        [bar setKeyboardIndex:-1];
        if (self.inWindowMenuTemporarilyShown) { self.inWindowMenuTemporarilyShown = NO; [self applyInWindowMenuVisibility]; }
        return YES;
    }
    if (hiding) { self.inWindowMenuTemporarilyShown = YES; [self applyInWindowMenuVisibility]; }
    [bar setKeyboardIndex:0];       // menu mode: the first menu highlighted
    return YES;
}

@end
