// Textpad++ — "Define your language..." dialog. GPL-3.0-or-later.
// Layout follows upstream UserDefineDialog: language selector + Create new / Save as / Rename /
// Remove / Import / Export, Ext., Ignore case, and the four tabs Folder & Default, Keywords Lists,
// Comment & Number, Operators & Delimiters, each group with a Styler. Edits apply live to every
// open document using the language and are saved to the user folder (upstream format).
#import "dialogs/UDLDialog.h"
#import "app/UserDefinedLanguages.h"
#import "app/LanguageService.h"
#import "app/MainWindowController.h"
#import "panels/DockManager.h"

// the dialog docked (upstream: the UDL dialog's Dock button turns it into a docking panel)
@interface TPUDLDockPanel : NSObject <TPPanel>
@property (nonatomic, strong) NSScrollView *scroll;
@end
@implementation TPUDLDockPanel
- (instancetype)init {
    if ((self = [super init])) {
        _scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 820, 320)];
        _scroll.hasVerticalScroller = YES; _scroll.hasHorizontalScroller = YES; _scroll.autohidesScrollers = YES;
        _scroll.drawsBackground = NO;
    }
    return self;
}
- (NSString *)panelIdentifier { return @"udl"; }
- (NSString *)panelTitle { return @"User Defined Language"; }
- (NSView *)panelView { return _scroll; }
- (TPDockSide)defaultSide { return TPDockBottom; }
@end

@interface TPUDLFlipped : NSView
@end
@implementation TPUDLFlipped
- (BOOL)isFlipped { return YES; }
@end

@implementation TPUDLDialog {
    __weak TPMainWindowController *_c;
    NSView *_content;
    NSButton *_dockButton;
    TPUDLDockPanel *_dockPanel;
    NSPopUpButton *_langPopup;
    NSTextField *_ext;
    NSButton *_ignoreCase;
    NSTabView *_tabs;
    NSMutableArray<NSDictionary *> *_bindings;   // {view, kind, list, code}
    NSTimer *_saveTimer;
    BOOL _loading;
}

+ (instancetype)sharedWithController:(TPMainWindowController *)c {
    static TPUDLDialog *d;
    if (!d) d = [[TPUDLDialog alloc] initWithController:c];
    return d;
}

- (instancetype)initWithController:(TPMainWindowController *)c {
    NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 820, 600) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow
                                              backing:NSBackingStoreBuffered defer:YES];
    if ((self = [super initWithWindow:p])) {
        _c = c;
        _bindings = [NSMutableArray array];
        p.title = @"User Defined Language";
        p.hidesOnDeactivate = YES;
        [self build];
        [self reloadLanguages];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(languagesChanged:) name:TPUserLanguagesChangedNotification object:nil];
    }
    return self;
}

// ---------------------------------------------------------------- docking
- (BOOL)docked { return [[NSUserDefaults standardUserDefaults] boolForKey:@"udl.docked"]; }

- (BOOL)isShown { return self.docked ? [_c.docks isPanelVisible:@"udl"] : self.window.isVisible; }

- (void)present {
    if (self.docked) {
        if (!_dockPanel) {
            _dockPanel = [TPUDLDockPanel new];
            [_c.docks registerPanel:_dockPanel];
        }
        if (_content.superview != _dockPanel.scroll.contentView) {
            self.window.contentView = [[NSView alloc] initWithFrame:_content.frame];
            [self.window orderOut:nil];
            _content.autoresizingMask = NSViewNotSizable;
            _content.frame = NSMakeRect(0, 0, 820, 600);
            _dockPanel.scroll.documentView = _content;
        }
        _dockButton.title = @"Undock";
        [_c.docks showPanel:@"udl"];
        return;
    }
    if (_content.superview != self.window.contentView.superview && self.window.contentView != _content) {
        if (_dockPanel) [_c.docks hidePanel:@"udl"];
        _dockPanel.scroll.documentView = nil;
        _content.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self.window.contentView = _content;
    }
    _dockButton.title = @"Dock";
    if (!self.window.isVisible) [self.window center];
    [self showWindow:nil];
}

- (void)hideDialog {
    if (self.docked) [_c.docks hidePanel:@"udl"];
    else [self.window orderOut:nil];
}

- (void)toggleDock:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:!self.docked forKey:@"udl.docked"];
    [self present];
}

- (void)languagesChanged:(NSNotification *)n {
    if (!_loading) [self reloadLanguages];
}

// ---------------------------------------------------------------- building
- (NSButton *)button:(NSString *)t action:(SEL)a frame:(NSRect)r in:(NSView *)v {
    NSButton *b = [NSButton buttonWithTitle:t target:self action:a];
    b.frame = r;
    b.font = [NSFont systemFontOfSize:11.5];
    [v addSubview:b];
    return b;
}

- (NSTextField *)label:(NSString *)t frame:(NSRect)r in:(NSView *)v {
    NSTextField *l = [NSTextField labelWithString:t];
    l.frame = r;
    l.font = [NSFont systemFontOfSize:11.5];
    [v addSubview:l];
    return l;
}

- (NSTextField *)field:(NSRect)r list:(int)list code:(int)code in:(NSView *)v {
    NSTextField *f = [[NSTextField alloc] initWithFrame:r];
    f.font = [NSFont userFixedPitchFontOfSize:11.5];
    f.delegate = self;
    [v addSubview:f];
    [_bindings addObject:@{@"view": f, @"kind": code < 0 ? @"list" : @"field", @"list": @(list), @"code": @(code)}];
    return f;
}

- (NSTextView *)textArea:(NSRect)r list:(int)list in:(NSView *)v {
    NSScrollView *sv = [NSTextView scrollableTextView];
    sv.frame = r;
    sv.borderType = NSBezelBorder;
    NSTextView *tv = sv.documentView;
    tv.font = [NSFont userFixedPitchFontOfSize:11.5];
    tv.richText = NO;
    tv.automaticQuoteSubstitutionEnabled = NO;
    tv.automaticDashSubstitutionEnabled = NO;
    tv.delegate = self;
    [v addSubview:sv];
    [_bindings addObject:@{@"view": tv, @"kind": @"list", @"list": @(list), @"code": @(-1)}];
    return tv;
}

- (NSButton *)check:(NSString *)t key:(NSString *)key frame:(NSRect)r in:(NSView *)v {
    NSButton *b = [NSButton checkboxWithTitle:t target:self action:@selector(settingChanged:)];
    b.frame = r;
    b.font = [NSFont systemFontOfSize:11.5];
    b.identifier = key;
    [v addSubview:b];
    [_bindings addObject:@{@"view": b, @"kind": @"setting", @"key": key}];
    return b;
}

- (void)styler:(int)styleId frame:(NSRect)r in:(NSView *)v {
    NSButton *b = [self button:@"Styler" action:@selector(openStyler:) frame:r in:v];
    b.tag = styleId;
}

- (NSView *)tabView:(NSString *)title {
    NSTabViewItem *it = [[NSTabViewItem alloc] initWithIdentifier:title];
    it.label = title;
    TPUDLFlipped *v = [[TPUDLFlipped alloc] initWithFrame:NSMakeRect(0, 0, 780, 480)];
    it.view = v;
    [_tabs addTabViewItem:it];
    return v;
}

- (void)build {
    TPUDLFlipped *cv = [[TPUDLFlipped alloc] initWithFrame:self.window.contentView.bounds];
    cv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.window.contentView = cv;
    _content = cv;
    _dockButton = [self button:@"Dock" action:@selector(toggleDock:) frame:NSMakeRect(NSWidth(cv.bounds) - 84, 9, 74, 26) in:cv];
    _dockButton.autoresizingMask = NSViewMinXMargin;
    [self label:@"User language:" frame:NSMakeRect(12, 14, 100, 18) in:cv];
    _langPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(110, 9, 220, 26)];
    _langPopup.target = self; _langPopup.action = @selector(languageSelected:);
    [cv addSubview:_langPopup];
    CGFloat x = 336;
    for (NSArray *b in @[@[@"Create new...", @"createNew:", @96], @[@"Save as...", @"saveAs:", @80], @[@"Rename", @"renameLang:", @74],
                         @[@"Remove", @"removeLang:", @74], @[@"Import...", @"importLang:", @74], @[@"Export...", @"exportLang:", @74]]) {
        CGFloat w = [b[2] doubleValue];
        [self button:b[0] action:NSSelectorFromString(b[1]) frame:NSMakeRect(x, 9, w, 26) in:cv];
        x += w;
    }
    [self label:@"Ext.:" frame:NSMakeRect(12, 46, 40, 18) in:cv];
    _ext = [[NSTextField alloc] initWithFrame:NSMakeRect(50, 43, 200, 22)];
    _ext.delegate = self;
    [cv addSubview:_ext];
    _ignoreCase = [NSButton checkboxWithTitle:@"Ignore case" target:self action:@selector(settingChanged:)];
    _ignoreCase.frame = NSMakeRect(270, 44, 120, 20);
    _ignoreCase.identifier = @"caseIgnored";
    [cv addSubview:_ignoreCase];
    [self button:@"Apply to current document" action:@selector(applyToCurrent:) frame:NSMakeRect(600, 40, 200, 26) in:cv];

    _tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(8, 74, 804, 518)];
    _tabs.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [cv addSubview:_tabs];

    // Folder & Default
    NSView *t1 = [self tabView:@"Folder & Default"];
    [self label:@"Default style:" frame:NSMakeRect(16, 16, 120, 18) in:t1];
    [self styler:0 frame:NSMakeRect(130, 10, 80, 26) in:t1];
    [self check:@"Fold compact (fold empty lines too)" key:@"foldCompact" frame:NSMakeRect(240, 14, 300, 20) in:t1];
    NSArray *folds = @[@[@"Folding in code 1 style:", @10, @13], @[@"Folding in code 2 style (separators needed):", @13, @14], @[@"Folding in comment style:", @16, @15]];
    CGFloat y = 56;
    for (NSArray *f in folds) {
        [self label:f[0] frame:NSMakeRect(16, y, 330, 18) in:t1];
        [self styler:[f[2] intValue] frame:NSMakeRect(360, y - 6, 80, 26) in:t1];
        int base = [f[1] intValue];
        NSArray *parts = @[@"Open:", @"Middle:", @"Close:"];
        for (int i = 0; i < 3; ++i) {
            [self label:parts[i] frame:NSMakeRect(16, y + 30 + i * 56, 80, 18) in:t1];
            [self textArea:NSMakeRect(80, y + 26 + i * 56, 360, 48) list:base + i in:t1];
        }
        y += 0;
        break;   // first group on the left column, the others below
    }
    y = 56;
    for (NSUInteger g = 1; g < folds.count; ++g) {
        NSArray *f = folds[g];
        CGFloat gx = g == 1 ? 460 : 460;
        CGFloat gy = g == 1 ? 56 : 266;
        [self label:f[0] frame:NSMakeRect(gx, gy, 230, 18) in:t1];
        [self styler:[f[2] intValue] frame:NSMakeRect(gx + 236, gy - 6, 70, 26) in:t1];
        int base = [f[1] intValue];
        NSArray *parts = @[@"Open:", @"Middle:", @"Close:"];
        for (int i = 0; i < 3; ++i) {
            [self label:parts[i] frame:NSMakeRect(gx, gy + 28 + i * 56, 60, 18) in:t1];
            [self textArea:NSMakeRect(gx + 60, gy + 24 + i * 56, 250, 48) list:base + i in:t1];
        }
    }

    // Keywords Lists
    NSView *t2 = [self tabView:@"Keywords Lists"];
    for (int i = 0; i < 8; ++i) {
        CGFloat gx = (i % 2) ? 400 : 12, gy = 10 + (i / 2) * 116;
        [self label:[NSString stringWithFormat:@"%d%@ group", i + 1, i == 0 ? @"st" : i == 1 ? @"nd" : i == 2 ? @"rd" : @"th"] frame:NSMakeRect(gx, gy + 4, 80, 18) in:t2];
        NSButton *pfx = [NSButton checkboxWithTitle:@"Prefix mode" target:self action:@selector(prefixChanged:)];
        pfx.frame = NSMakeRect(gx + 90, gy + 2, 110, 20);
        pfx.tag = i;
        pfx.font = [NSFont systemFontOfSize:11.5];
        [t2 addSubview:pfx];
        [_bindings addObject:@{@"view": pfx, @"kind": @"prefix", @"list": @(i)}];
        [self styler:4 + i frame:NSMakeRect(gx + 290, gy - 2, 80, 26) in:t2];
        [self textArea:NSMakeRect(gx, gy + 26, 370, 84) list:19 + i in:t2];
    }

    // Comment & Number
    NSView *t3 = [self tabView:@"Comment & Number"];
    [self label:@"Line comment position:" frame:NSMakeRect(16, 12, 180, 18) in:t3];
    NSArray *lcp = @[@"Allow anywhere", @"Force at beginning of line", @"Allow preceding whitespace"];
    for (int i = 0; i < 3; ++i) {
        NSButton *r = [NSButton radioButtonWithTitle:lcp[i] target:self action:@selector(forceLCChanged:)];
        r.frame = NSMakeRect(190 + i * 190, 10, 190, 20);
        r.tag = i;
        r.font = [NSFont systemFontOfSize:11.5];
        [t3 addSubview:r];
        [_bindings addObject:@{@"view": r, @"kind": @"forceLC"}];
    }
    [self check:@"Allow folding of comments" key:@"allowFoldOfComments" frame:NSMakeRect(16, 38, 250, 20) in:t3];
    [self label:@"Comment line style" frame:NSMakeRect(16, 70, 160, 18) in:t3];
    [self styler:2 frame:NSMakeRect(180, 64, 80, 26) in:t3];
    NSArray *cl = @[@[@"Open:", @0], @[@"Continue character:", @1], @[@"Close:", @2]];
    for (int i = 0; i < 3; ++i) {
        [self label:cl[i][0] frame:NSMakeRect(16, 100 + i * 30, 140, 18) in:t3];
        [self field:NSMakeRect(160, 98 + i * 30, 200, 22) list:0 code:[cl[i][1] intValue] in:t3];
    }
    [self label:@"Comment style" frame:NSMakeRect(16, 200, 160, 18) in:t3];
    [self styler:1 frame:NSMakeRect(180, 194, 80, 26) in:t3];
    [self label:@"Open:" frame:NSMakeRect(16, 230, 140, 18) in:t3];
    [self field:NSMakeRect(160, 228, 200, 22) list:0 code:3 in:t3];
    [self label:@"Close:" frame:NSMakeRect(16, 260, 140, 18) in:t3];
    [self field:NSMakeRect(160, 258, 200, 22) list:0 code:4 in:t3];
    [self label:@"Number style" frame:NSMakeRect(420, 70, 160, 18) in:t3];
    [self styler:3 frame:NSMakeRect(580, 64, 80, 26) in:t3];
    NSArray *nums = @[@"Prefix 1:", @"Prefix 2:", @"Extras 1:", @"Extras 2:", @"Suffix 1:", @"Suffix 2:", @"Range:"];
    for (int i = 0; i < 7; ++i) {
        [self label:nums[i] frame:NSMakeRect(420, 100 + i * 30, 80, 18) in:t3];
        [self field:NSMakeRect(500, 98 + i * 30, 260, 22) list:1 + i code:-1 in:t3];
    }
    [self label:@"Decimal separator:" frame:NSMakeRect(420, 316, 130, 18) in:t3];
    NSArray *ds = @[@"Dot", @"Comma", @"Both"];
    for (int i = 0; i < 3; ++i) {
        NSButton *r = [NSButton radioButtonWithTitle:ds[i] target:self action:@selector(decimalChanged:)];
        r.frame = NSMakeRect(550 + i * 70, 314, 70, 20);
        r.tag = i;
        r.font = [NSFont systemFontOfSize:11.5];
        [t3 addSubview:r];
        [_bindings addObject:@{@"view": r, @"kind": @"decimal"}];
    }

    // Operators & Delimiters
    NSView *t4 = [self tabView:@"Operators & Delimiters"];
    [self label:@"Operators style" frame:NSMakeRect(16, 12, 160, 18) in:t4];
    [self styler:12 frame:NSMakeRect(180, 6, 80, 26) in:t4];
    [self label:@"Operators 1 (no separator needed):" frame:NSMakeRect(16, 42, 240, 18) in:t4];
    [self field:NSMakeRect(16, 62, 360, 22) list:8 code:-1 in:t4];
    [self label:@"Operators 2 (separators required):" frame:NSMakeRect(400, 42, 240, 18) in:t4];
    [self field:NSMakeRect(400, 62, 360, 22) list:9 code:-1 in:t4];
    for (int d = 0; d < 8; ++d) {
        CGFloat gx = (d % 2) ? 400 : 16, gy = 100 + (d / 2) * 94;
        [self label:[NSString stringWithFormat:@"Delimiter %d style", d + 1] frame:NSMakeRect(gx, gy, 140, 18) in:t4];
        [self styler:16 + d frame:NSMakeRect(gx + 150, gy - 6, 80, 26) in:t4];
        NSArray *p = @[@"Open:", @"Escape:", @"Close:"];
        for (int i = 0; i < 3; ++i) {
            [self label:p[i] frame:NSMakeRect(gx + i * 122, gy + 26, 60, 18) in:t4];
            [self field:NSMakeRect(gx + i * 122, gy + 44, 114, 22) list:27 code:d * 3 + i in:t4];
        }
    }
}

// ---------------------------------------------------------------- data <-> controls
- (void)reloadLanguages {
    NSString *keep = _current.name;
    [_langPopup removeAllItems];
    for (TPUserLang *l in [TPUserLanguages shared].languages) [_langPopup addItemWithTitle:l.name];
    [self selectLanguageNamed:keep];
}

- (void)selectLanguageNamed:(NSString *)name {
    TPUserLang *l = name ? [[TPUserLanguages shared] languageNamed:name] : nil;
    if (!l) l = [TPUserLanguages shared].languages.firstObject;
    _current = l;
    if (l) [_langPopup selectItemWithTitle:l.name];
    [self loadControls];
}

- (void)loadControls {
    _loading = YES;
    TPUserLang *l = _current;
    BOOL has = l != nil;
    _ext.stringValue = l.ext ?: @"";
    _ignoreCase.state = l.caseIgnored ? NSControlStateValueOn : NSControlStateValueOff;
    for (NSDictionary *b in _bindings) {
        id v = b[@"view"];
        NSString *kind = b[@"kind"];
        int list = [b[@"list"] intValue], code = [b[@"code"] intValue];
        if ([v respondsToSelector:@selector(setEnabled:)]) [v setEnabled:has];
        if ([v isKindOfClass:[NSTextView class]]) { ((NSTextView *)v).editable = has; }
        if (!has) continue;
        if ([kind isEqualToString:@"list"]) {
            NSString *s = l.keywordLists[list];
            if ([v isKindOfClass:[NSTextView class]]) ((NSTextView *)v).string = s; else ((NSTextField *)v).stringValue = s;
        } else if ([kind isEqualToString:@"field"]) {
            ((NSTextField *)v).stringValue = [l field:code ofList:list];
        } else if ([kind isEqualToString:@"setting"]) {
            ((NSButton *)v).state = [[l valueForKey:b[@"key"]] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
        } else if ([kind isEqualToString:@"prefix"]) {
            ((NSButton *)v).state = [l.isPrefix[list] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
        } else if ([kind isEqualToString:@"forceLC"]) {
            ((NSButton *)v).state = l.forcePureLC == ((NSButton *)v).tag ? NSControlStateValueOn : NSControlStateValueOff;
        } else if ([kind isEqualToString:@"decimal"]) {
            ((NSButton *)v).state = l.decimalSeparator == ((NSButton *)v).tag ? NSControlStateValueOn : NSControlStateValueOff;
        }
    }
    _loading = NO;
}

- (void)changedAndApply {
    if (_loading || !_current) return;
    [_c udlDidChange:_current];
    [_saveTimer invalidate];
    __weak TPUDLDialog *ws = self;
    _saveTimer = [NSTimer scheduledTimerWithTimeInterval:0.6 repeats:NO block:^(NSTimer *t) { [ws saveNow]; }];
}

- (void)saveNow {
    if (!_current) return;
    _loading = YES;
    NSString *err = nil;
    if (![[TPUserLanguages shared] save:_current error:&err]) [_c showMessage:@"Cannot save the language." informative:err];
    _loading = NO;
}

- (void)storeFromView:(id)v {
    for (NSDictionary *b in _bindings) {
        if (b[@"view"] != v) continue;
        int list = [b[@"list"] intValue], code = [b[@"code"] intValue];
        NSString *s = [v isKindOfClass:[NSTextView class]] ? ((NSTextView *)v).string : ((NSTextField *)v).stringValue;
        if ([b[@"kind"] isEqualToString:@"list"]) _current.keywordLists[list] = s ?: @"";
        else if ([b[@"kind"] isEqualToString:@"field"]) [_current setField:code ofList:list value:s ?: @""];
        [self changedAndApply];
    }
}

- (void)textDidChange:(NSNotification *)n { [self storeFromView:n.object]; }

- (void)controlTextDidChange:(NSNotification *)n {
    if (n.object == _ext) { _current.ext = _ext.stringValue; [self changedAndApply]; return; }
    [self storeFromView:n.object];
}

- (void)settingChanged:(NSButton *)b {
    [_current setValue:@(b.state == NSControlStateValueOn) forKey:b.identifier];
    [self changedAndApply];
}
- (void)prefixChanged:(NSButton *)b { _current.isPrefix[b.tag] = @(b.state == NSControlStateValueOn); [self changedAndApply]; }
- (void)forceLCChanged:(NSButton *)b { _current.forcePureLC = (int)b.tag; [self loadControls]; [self changedAndApply]; }
- (void)decimalChanged:(NSButton *)b { _current.decimalSeparator = (int)b.tag; [self loadControls]; [self changedAndApply]; }
- (void)languageSelected:(id)s { [self selectLanguageNamed:_langPopup.titleOfSelectedItem]; }
- (void)applyToCurrent:(id)s { if (_current && _c.currentDocument) [_c setDocumentLanguage:_c.currentDocument languageId:_current.langId]; }

// ---------------------------------------------------------------- language management
- (NSString *)askName:(NSString *)title initial:(NSString *)initial {
    NSAlert *a = [NSAlert new];
    a.messageText = title;
    NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)];
    tf.stringValue = initial ?: @"";
    a.accessoryView = tf;
    [a addButtonWithTitle:@"OK"];
    [a addButtonWithTitle:@"Cancel"];
    a.window.initialFirstResponder = tf;
    if ([a runModal] != NSAlertFirstButtonReturn) return nil;
    NSString *n = [tf.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    return n.length ? n : nil;
}

- (void)createNew:(id)s {
    NSString *n = [self askName:@"Create New Language..." initial:@""];
    if (!n) return;
    NSString *err = nil;
    TPUserLang *l = [[TPUserLanguages shared] createNamed:n basedOn:nil error:&err];
    if (!l) { [_c showMessage:@"Cannot create the language." informative:err]; return; }
    [self reloadLanguages];
    [self selectLanguageNamed:l.name];
}

- (void)saveAs:(id)s {
    if (!_current) return;
    NSString *n = [self askName:@"Save Current Language Name As..." initial:@""];
    if (!n) return;
    NSString *err = nil;
    TPUserLang *l = [[TPUserLanguages shared] createNamed:n basedOn:_current error:&err];
    if (!l) { [_c showMessage:@"Cannot save the language." informative:err]; return; }
    [self reloadLanguages];
    [self selectLanguageNamed:l.name];
}

- (void)renameLang:(id)s {
    if (!_current) return;
    NSString *old = _current.langId;
    NSString *n = [self askName:@"Rename Current Language Name" initial:_current.name];
    if (!n) return;
    NSString *err = nil;
    if (![[TPUserLanguages shared] rename:_current to:n error:&err]) { [_c showMessage:@"Cannot rename the language." informative:err]; return; }
    [_c udlRenamedFrom:old to:[@"udl:" stringByAppendingString:n]];
    [self reloadLanguages];
    [self selectLanguageNamed:n];
}

- (void)removeLang:(id)s {
    if (!_current) return;
    NSInteger r = [_c prompt:[NSString stringWithFormat:@"Are you sure you want to remove \"%@\"?", _current.name] informative:@"The definition file is moved to the Trash." buttons:@[@"Remove", @"Cancel"]];
    if (r != 0) return;
    NSString *old = _current.langId, *err = nil;
    if (![[TPUserLanguages shared] remove:_current error:&err]) { [_c showMessage:@"Cannot remove the language." informative:err]; return; }
    [_c udlRenamedFrom:old to:@"normal"];
    _current = nil;
    [self reloadLanguages];
}

- (void)importLang:(id)s {
    NSOpenPanel *op = [NSOpenPanel openPanel];
    op.allowsMultipleSelection = YES;
    if ([op runModal] != NSModalResponseOK) return;
    NSString *last = nil;
    for (NSURL *u in op.URLs) {
        NSString *err = nil;
        NSArray *langs = [[TPUserLanguages shared] importFile:u.path error:&err];
        if (!langs.count) [_c showMessage:@"Import failed." informative:[NSString stringWithFormat:@"%@\n%@", u.path, err ?: @""]];
        last = [langs.lastObject name] ?: last;
    }
    [self reloadLanguages];
    if (last) [self selectLanguageNamed:last];
}

- (void)exportLang:(id)s {
    if (!_current) return;
    NSSavePanel *sp = [NSSavePanel savePanel];
    sp.nameFieldStringValue = [_current.name stringByAppendingString:@".xml"];
    if ([sp runModal] != NSModalResponseOK) return;
    NSString *err = nil;
    if (![[TPUserLanguages shared] exportLanguage:_current toPath:sp.URL.path error:&err]) [_c showMessage:@"Export failed." informative:err];
}

// ---------------------------------------------------------------- styler
- (void)openStyler:(NSButton *)sender {
    if (!_current) return;
    TPStyleSpec *st = _current.styles[sender.tag];
    NSAlert *a = [NSAlert new];
    a.messageText = [NSString stringWithFormat:@"Styler Dialog — %@", st.name];
    NSView *acc = [[TPUDLFlipped alloc] initWithFrame:NSMakeRect(0, 0, 440, sender.tag >= 16 || sender.tag == 1 || sender.tag == 2 ? 300 : 150)];
    NSPopUpButton *font = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(60, 0, 220, 26)];
    [font addItemWithTitle:@"(default)"];
    [font addItemsWithTitles:[[NSFontManager sharedFontManager].availableFontFamilies sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]];
    if (st.fontName.length) [font selectItemWithTitle:st.fontName];
    [self label:@"Name:" frame:NSMakeRect(0, 4, 60, 18) in:acc];
    [acc addSubview:font];
    [self label:@"Size:" frame:NSMakeRect(290, 4, 40, 18) in:acc];
    NSTextField *size = [[NSTextField alloc] initWithFrame:NSMakeRect(330, 2, 50, 22)];
    size.stringValue = st.fontSize > 0 ? [@((int)st.fontSize) stringValue] : @"";
    size.placeholderString = @"(def.)";
    [acc addSubview:size];
    NSButton *bold = [NSButton checkboxWithTitle:@"Bold" target:nil action:nil], *ital = [NSButton checkboxWithTitle:@"Italic" target:nil action:nil], *und = [NSButton checkboxWithTitle:@"Underline" target:nil action:nil];
    bold.frame = NSMakeRect(0, 34, 80, 20); ital.frame = NSMakeRect(90, 34, 80, 20); und.frame = NSMakeRect(180, 34, 100, 20);
    bold.state = (st.fontStyle & 1) != 0; ital.state = (st.fontStyle & 2) != 0; und.state = (st.fontStyle & 4) != 0;
    for (NSView *v in @[bold, ital, und]) [acc addSubview:v];
    auto color = [](int rgb) { return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1]; };
    [self label:@"Foreground:" frame:NSMakeRect(0, 70, 80, 18) in:acc];
    NSColorWell *fg = [[NSColorWell alloc] initWithFrame:NSMakeRect(80, 64, 50, 28)];
    fg.color = color(st.fg);
    NSButton *fgT = [NSButton checkboxWithTitle:@"Transparent" target:nil action:nil];
    fgT.frame = NSMakeRect(140, 68, 110, 20);
    fgT.state = (st.colorStyle & 1) ? NSControlStateValueOff : NSControlStateValueOn;
    [self label:@"Background:" frame:NSMakeRect(0, 108, 80, 18) in:acc];
    NSColorWell *bg = [[NSColorWell alloc] initWithFrame:NSMakeRect(80, 102, 50, 28)];
    bg.color = color(st.bg);
    NSButton *bgT = [NSButton checkboxWithTitle:@"Transparent" target:nil action:nil];
    bgT.frame = NSMakeRect(140, 106, 110, 20);
    bgT.state = (st.colorStyle & 2) ? NSControlStateValueOff : NSControlStateValueOn;
    for (NSView *v in @[fg, fgT, bg, bgT]) [acc addSubview:v];
    NSMutableArray<NSButton *> *nestBoxes = [NSMutableArray array];
    if (sender.tag >= 16 || sender.tag == 1 || sender.tag == 2) {
        [self label:@"Nesting (styles allowed inside this one):" frame:NSMakeRect(0, 140, 400, 18) in:acc];
        NSArray *names = @[@"Delimiter 1", @"Delimiter 2", @"Delimiter 3", @"Delimiter 4", @"Delimiter 5", @"Delimiter 6", @"Delimiter 7", @"Delimiter 8",
                           @"Comment", @"Comment line", @"Keyword 1", @"Keyword 2", @"Keyword 3", @"Keyword 4", @"Keyword 5", @"Keyword 6", @"Keyword 7", @"Keyword 8",
                           @"Folder in code 2 open", @"Folder in code 2 middle", @"Folder in code 2 close", @"Folder in comment open", @"Folder in comment middle",
                           @"Folder in comment close", @"Operators 1", @"Operators 2", @"Numbers"];
        for (NSUInteger i = 0; i < names.count; ++i) {
            NSButton *b = [NSButton checkboxWithTitle:names[i] target:nil action:nil];
            b.font = [NSFont systemFontOfSize:10.5];
            b.frame = NSMakeRect((i % 3) * 146, 162 + (i / 3) * 15, 146, 15);
            b.state = (st.nesting & (1 << i)) ? NSControlStateValueOn : NSControlStateValueOff;
            b.tag = 1 << i;
            [acc addSubview:b];
            [nestBoxes addObject:b];
        }
    }
    a.accessoryView = acc;
    [a addButtonWithTitle:@"OK"];
    [a addButtonWithTitle:@"Cancel"];
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    st.fontName = font.indexOfSelectedItem > 0 ? font.titleOfSelectedItem : nil;
    st.fontSize = size.doubleValue;
    st.fontStyle = (bold.state ? 1 : 0) | (ital.state ? 2 : 0) | (und.state ? 4 : 0);
    auto toRGB = [](NSColor *c) {
        NSColor *s = [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        return (int)(lround(s.redComponent * 255) << 16 | lround(s.greenComponent * 255) << 8 | lround(s.blueComponent * 255));
    };
    st.fg = toRGB(fg.color);
    st.bg = toRGB(bg.color);
    st.colorStyle = (fgT.state ? 0 : 1) | (bgT.state ? 0 : 2);
    int nest = 0;
    for (NSButton *b in nestBoxes) if (b.state == NSControlStateValueOn) nest |= (int)b.tag;
    st.nesting = nest;
    [self changedAndApply];
}

@end
