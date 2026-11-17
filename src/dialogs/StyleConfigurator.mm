// Textpad++ — Settings > Style Configurator... (upstream WinControls/ColourPicker/WordStyleDlg). GPL-3.0-or-later.
// Same controls as upstream WordStyleDlg.rc: Select theme, Language (Global Styles + every LexerType), Style list,
// Colour Style (foreground / background), Font Style (name, size, bold, italic, underline), Default ext. + User ext.,
// Default keywords + User-defined keywords, Global override check boxes, Go to settings, Save & Close, Cancel.
// Every change is previewed in the open documents immediately; Cancel restores the theme as it was.
#import "dialogs/StyleConfigurator.h"
#import "app/MainWindowController.h"
#import "app/EditorPane.h"
#import "app/Document.h"
#import "app/LanguageService.h"
#import "app/Preferences.h"
#import "app/Session.h"

@interface TPStyleConfigurator () <NSWindowDelegate>
@end

static NSString *const kGlobalStyles = @"Global Styles";
static NSString *const kDefaultThemeTitle = @"Default (stylers.xml)";

@implementation TPStyleConfigurator {
    __weak TPMainWindowController *_c;
    NSPopUpButton *_themePopup, *_languagePopup;
    NSTableView *_styleTable;
    NSArray<TPStyleSpec *> *_styles;
    NSArray<NSString *> *_themePaths;
    NSTextField *_description, *_whatIsGO;
    NSBox *_colourBox, *_fontBox;
    NSView *_keywordsGroup, *_globalGroup;
    NSScrollView *_defKwScroll, *_userKwScroll;
    BOOL _populating;
    // state Cancel restores
    NSString *_originalThemePath;
    NSDictionary *_originalGO;
}

+ (instancetype)sharedWithController:(TPMainWindowController *)c {
    static TPStyleConfigurator *shared;
    if (!shared) shared = [[TPStyleConfigurator alloc] initWithController:c];
    shared->_c = c;
    return shared;
}

static NSTextField *label(NSString *s, NSRect r, NSView *v, NSTextAlignment a = NSTextAlignmentLeft) {
    NSTextField *l = [NSTextField labelWithString:s];
    l.frame = r;
    l.alignment = a;
    [v addSubview:l];
    return l;
}

static NSScrollView *textArea(NSRect r, NSView *parent, NSTextView *__strong *outView, BOOL editable) {
    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:r];
    sv.hasVerticalScroller = YES;
    sv.borderType = NSBezelBorder;
    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, r.size.width - 16, r.size.height)];
    tv.editable = editable;
    tv.richText = NO;
    tv.font = [NSFont userFixedPitchFontOfSize:11];
    tv.automaticQuoteSubstitutionEnabled = tv.automaticDashSubstitutionEnabled = tv.automaticTextReplacementEnabled = NO;
    tv.verticallyResizable = YES;
    tv.textContainer.widthTracksTextView = YES;
    sv.documentView = tv;
    [parent addSubview:sv];
    *outView = tv;
    return sv;
}

- (instancetype)initWithController:(TPMainWindowController *)c {
    NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 760, 400)
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow
                                              backing:NSBackingStoreBuffered defer:YES];
    p.title = @"Style Configurator";
    p.hidesOnDeactivate = NO;
    p.releasedWhenClosed = NO;
    if (!(self = [super initWithWindow:p])) return nil;
    p.delegate = self;
    _c = c;
    NSView *v = p.contentView;
    const CGFloat H = 400;
    auto R = [&](CGFloat x, CGFloat yTop, CGFloat w, CGFloat h) { return NSMakeRect(x, H - yTop - h, w, h); };   // top-left layout

    label(@"Select theme:", R(16, 14, 120, 18), v, NSTextAlignmentRight);
    _themePopup = [[NSPopUpButton alloc] initWithFrame:R(142, 10, 220, 26)];
    _themePopup.target = self; _themePopup.action = @selector(themeChosen:);
    [v addSubview:_themePopup];

    // left column: Language, Style, Default ext. + User ext.
    NSBox *left = [[NSBox alloc] initWithFrame:R(10, 40, 250, 316)];
    left.title = @""; left.titlePosition = NSNoTitle;
    [v addSubview:left];
    NSView *lv = left.contentView;
    const CGFloat LH = NSHeight(lv.bounds);
    auto L = [&](CGFloat x, CGFloat yTop, CGFloat w, CGFloat h) { return NSMakeRect(x, LH - yTop - h, w, h); };
    label(@"Language:", L(8, 6, 200, 16), lv);
    _languagePopup = [[NSPopUpButton alloc] initWithFrame:L(6, 24, 226, 26)];
    _languagePopup.target = self; _languagePopup.action = @selector(languageChosen:);
    [lv addSubview:_languagePopup];
    label(@"Style:", L(8, 56, 200, 16), lv);
    NSScrollView *ss = [[NSScrollView alloc] initWithFrame:L(6, 74, 226, 170)];
    ss.hasVerticalScroller = YES; ss.borderType = NSBezelBorder;
    _styleTable = [[NSTableView alloc] initWithFrame:ss.bounds];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"style"];
    col.width = 210;
    [_styleTable addTableColumn:col];
    _styleTable.headerView = nil;
    _styleTable.dataSource = self; _styleTable.delegate = self;
    ss.documentView = _styleTable;
    [lv addSubview:ss];
    label(@"Default ext.:", L(8, 252, 100, 16), lv);
    _defaultExtField = [[NSTextField alloc] initWithFrame:L(6, 270, 100, 22)];
    _defaultExtField.editable = NO; _defaultExtField.selectable = YES;
    [lv addSubview:_defaultExtField];
    label(@"+", L(110, 272, 14, 16), lv, NSTextAlignmentCenter);
    label(@"User ext.:", L(128, 252, 100, 16), lv);
    _userExtField = [[NSTextField alloc] initWithFrame:L(126, 270, 106, 22)];
    _userExtField.delegate = self;
    [lv addSubview:_userExtField];

    // right side
    NSBox *right = [[NSBox alloc] initWithFrame:R(270, 40, 480, 316)];
    right.title = @""; right.titlePosition = NSNoTitle;
    [v addSubview:right];
    NSView *rv = right.contentView;
    const CGFloat RH = NSHeight(rv.bounds);
    auto RR = [&](CGFloat x, CGFloat yTop, CGFloat w, CGFloat h) { return NSMakeRect(x, RH - yTop - h, w, h); };
    _description = label(@"", RR(8, 4, 450, 18), rv);
    _description.font = [NSFont boldSystemFontOfSize:12];

    _colourBox = [[NSBox alloc] initWithFrame:RR(4, 26, 196, 112)];
    _colourBox.title = @"Colour Style";
    [rv addSubview:_colourBox];
    NSView *cb = _colourBox.contentView;
    label(@"Foreground colour", NSMakeRect(2, 52, 136, 18), cb, NSTextAlignmentRight);
    label(@"Background colour", NSMakeRect(2, 14, 136, 18), cb, NSTextAlignmentRight);
    _foregroundWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(144, 48, 36, 26)];
    _backgroundWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(144, 10, 36, 26)];
    for (NSColorWell *w in @[_foregroundWell, _backgroundWell]) { w.target = self; w.action = @selector(controlChanged:); [cb addSubview:w]; }

    _fontBox = [[NSBox alloc] initWithFrame:RR(206, 26, 266, 112)];
    _fontBox.title = @"Font Style";
    [rv addSubview:_fontBox];
    NSView *fb = _fontBox.contentView;
    label(@"Font name:", NSMakeRect(2, 60, 74, 18), fb, NSTextAlignmentRight);
    _fontPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(80, 56, 172, 26)];
    [_fontPopup addItemWithTitle:@""];
    for (NSString *f in [[NSFontManager sharedFontManager].availableFontFamilies sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)])
        [_fontPopup addItemWithTitle:f];
    label(@"Font size:", NSMakeRect(110, 28, 68, 18), fb, NSTextAlignmentRight);
    _fontSizePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(182, 24, 70, 26)];
    for (NSString *sz in @[@"", @"5", @"6", @"7", @"8", @"9", @"10", @"11", @"12", @"14", @"16", @"18", @"20", @"22", @"24", @"26", @"28"])
        [_fontSizePopup addItemWithTitle:sz];   // upstream fontSizeStrs
    _boldCheck = [NSButton checkboxWithTitle:@"Bold" target:self action:@selector(controlChanged:)];
    _italicCheck = [NSButton checkboxWithTitle:@"Italic" target:self action:@selector(controlChanged:)];
    _underlineCheck = [NSButton checkboxWithTitle:@"Underline" target:self action:@selector(controlChanged:)];
    _boldCheck.frame = NSMakeRect(10, 32, 110, 18);
    _italicCheck.frame = NSMakeRect(10, 14, 110, 18);
    _underlineCheck.frame = NSMakeRect(110, 2, 140, 18);
    for (NSControl *x in @[_fontPopup, _fontSizePopup]) { x.target = self; x.action = @selector(controlChanged:); }
    for (NSView *x in @[_fontPopup, _fontSizePopup, _boldCheck, _italicCheck, _underlineCheck]) [fb addSubview:x];

    // keywords (styles with a keyword class)
    _keywordsGroup = [[NSView alloc] initWithFrame:RR(0, 142, 478, 150)];
    [rv addSubview:_keywordsGroup];
    label(@"Default keywords", NSMakeRect(8, 130, 200, 16), _keywordsGroup);
    label(@"User-defined keywords", NSMakeRect(250, 130, 200, 16), _keywordsGroup);
    _defKwScroll = textArea(NSMakeRect(6, 4, 220, 124), _keywordsGroup, &_defaultKeywordsView, NO);
    label(@"+", NSMakeRect(228, 60, 18, 16), _keywordsGroup, NSTextAlignmentCenter);
    _userKwScroll = textArea(NSMakeRect(248, 4, 222, 124), _keywordsGroup, &_userKeywordsView, YES);
    _userKeywordsView.delegate = self;

    // Global override (only for the "Global override" style)
    _globalGroup = [[NSView alloc] initWithFrame:RR(0, 142, 478, 150)];
    [rv addSubview:_globalGroup];
    NSArray *goTitles = @[@"Force foreground color for all styles", @"Force background color for all styles", @"Force font choice for all styles",
                          @"Force font size choice for all styles", @"Force bold choice for all styles", @"Force italic choice for all styles",
                          @"Force underline choice for all styles"];
    NSMutableArray *checks = [NSMutableArray array];
    for (NSUInteger i = 0; i < goTitles.count; ++i) {
        NSButton *b = [NSButton checkboxWithTitle:goTitles[i] target:self action:@selector(controlChanged:)];
        b.frame = i < 2 ? NSMakeRect(8, 124 - 22.0 * i, 230, 18) : NSMakeRect(240, 124 - 22.0 * (i - 2), 236, 18);
        [_globalGroup addSubview:b];
        [checks addObject:b];
    }
    _globalOverrideChecks = checks;
    _whatIsGO = label(@"What is Global override?", NSMakeRect(8, 60, 200, 18), _globalGroup);
    _whatIsGO.textColor = NSColor.linkColor;
    _whatIsGO.toolTip = @"Global override lets you choose properties that apply to every style of every language. "
                         "The properties you check here replace those of all styles while this mode is enabled.";
    _goToSettingsButton = [NSButton buttonWithTitle:@"Go to settings" target:self action:@selector(goToSettings:)];
    _goToSettingsButton.bezelStyle = NSBezelStyleInline;
    _goToSettingsButton.frame = RR(8, 290, 140, 20);
    [rv addSubview:_goToSettingsButton];

    NSButton *save = [NSButton buttonWithTitle:@"Save & Close" target:self action:@selector(saveAndClose:)];
    save.frame = R(470, 362, 130, 28);
    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
    cancel.frame = R(610, 362, 130, 28);
    cancel.keyEquivalent = @"\033";
    [v addSubview:save]; [v addSubview:cancel];
    [p center];
    return self;
}

// ---------------------------------------------------------------- themes
- (void)reloadThemeList {
    NSMutableArray *paths = [NSMutableArray arrayWithObject:[TPLanguageService defaultThemePath]];
    NSMutableArray *titles = [NSMutableArray arrayWithObject:kDefaultThemeTitle];
    NSMutableDictionary *byName = [NSMutableDictionary dictionary];
    for (NSString *dir in @[[[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:@"data/themes"],
                            [[TPSession shared].settingsDirectory stringByAppendingPathComponent:@"themes"]])
        for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil])
            if ([f.pathExtension.lowercaseString isEqualToString:@"xml"]) byName[f] = [dir stringByAppendingPathComponent:f];   // user copy wins
    for (NSString *f in [byName.allKeys sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
        [paths addObject:byName[f]];
        [titles addObject:f.stringByDeletingPathExtension];
    }
    _themePaths = paths;
    _themeNames = titles;
    [_themePopup removeAllItems];
    [_themePopup addItemsWithTitles:titles];
    NSString *cur = [TPLanguageService shared].themePath;
    NSUInteger i = [paths indexOfObject:cur];
    if (i == NSNotFound) i = [[paths valueForKey:@"lastPathComponent"] indexOfObject:cur.lastPathComponent];
    if (cur && [cur.lastPathComponent isEqualToString:@"stylers.model.xml"]) i = 0;
    [_themePopup selectItemAtIndex:i == NSNotFound ? 0 : (NSInteger)i];
}

- (void)open {
    _originalThemePath = [TPLanguageService shared].themePath;
    NSMutableDictionary *go = [NSMutableDictionary dictionary];
    for (NSString *k in [self goKeys]) go[k] = @([TPPrefs b:k]);
    _originalGO = go;
    [self reloadThemeList];
    [self reloadLanguages];
    [self showWindow:nil];
}

- (NSArray<NSString *> *)goKeys {
    return @[@"pref.go.fg", @"pref.go.bg", @"pref.go.font", @"pref.go.fontSize", @"pref.go.bold", @"pref.go.italic", @"pref.go.underline"];
}

- (void)themeChosen:(id)sender {
    TPLanguageService *ls = [TPLanguageService shared];
    if (ls.themeModified) {
        NSInteger r = [_c prompt:@"Save the changes made to the current theme?" informative:nil buttons:@[@"Save", @"Don't Save"]];
        if (r == 0) [ls saveThemeWithError:nil];
    }
    NSString *path = _themePaths[(NSUInteger)_themePopup.indexOfSelectedItem];
    NSString *err = nil;
    if (![ls loadTheme:path error:&err]) { [_c showMessage:@"Cannot load the theme." informative:err]; return; }
    NSString *lang = _languagePopup.selectedItem.representedObject;
    NSString *style = self.currentStyle.name;
    [self reloadLanguages];
    if (lang) [self selectLanguageNamed:lang];
    if (style) [self selectStyleNamed:style];
    [self reapplyEverywhere];
}

- (void)selectThemeNamed:(NSString *)name {
    NSUInteger i = [_themeNames indexOfObject:name];
    if (i == NSNotFound) return;
    [_themePopup selectItemAtIndex:(NSInteger)i];
    [self themeChosen:_themePopup];
}

// ---------------------------------------------------------------- language / style lists
- (void)reloadLanguages {
    TPLanguageService *ls = [TPLanguageService shared];
    [_languagePopup removeAllItems];
    [_languagePopup addItemWithTitle:kGlobalStyles];
    _languagePopup.lastItem.representedObject = kGlobalStyles;
    for (TPLexerType *t in ls.lexerTypes) {
        if ([t.name isEqualToString:@"searchResult"]) continue;   // upstream lists it too, but under "Search result"
        NSString *title = t.desc.length ? t.desc : t.name;
        if ([_languagePopup itemWithTitle:title]) title = [NSString stringWithFormat:@"%@ (%@)", title, t.name];
        [_languagePopup addItemWithTitle:title];
        _languagePopup.lastItem.representedObject = t.name;
    }
    if (TPLexerType *sr = [ls lexerTypeNamed:@"searchResult"]) {
        [_languagePopup addItemWithTitle:sr.desc.length ? sr.desc : @"Search result"];
        _languagePopup.lastItem.representedObject = sr.name;
    }
    [self languageChosen:nil];
}

- (void)languageChosen:(id)sender {
    NSString *name = _languagePopup.selectedItem.representedObject;
    TPLanguageService *ls = [TPLanguageService shared];
    _styles = [name isEqualToString:kGlobalStyles] ? ls.globalStyleList : ([ls lexerTypeNamed:name].styles ?: @[]);
    [_styleTable reloadData];
    [_styleTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self populate];
}

- (void)selectLanguageNamed:(NSString *)name {
    for (NSMenuItem *mi in _languagePopup.itemArray)
        if ([mi.representedObject isEqual:name]) { [_languagePopup selectItem:mi]; [self languageChosen:nil]; return; }
}

- (void)selectStyleNamed:(NSString *)name {
    for (NSUInteger i = 0; i < _styles.count; ++i)
        if ([_styles[i].name isEqualToString:name]) {
            [_styleTable selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            [self populate];
            return;
        }
}

- (TPStyleSpec *)currentStyle {
    NSInteger r = _styleTable.selectedRow;
    return r >= 0 && r < (NSInteger)_styles.count ? _styles[(NSUInteger)r] : nil;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return (NSInteger)_styles.count; }
- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    NSTextField *t = [tv makeViewWithIdentifier:@"cell" owner:self];
    if (!t) { t = [NSTextField labelWithString:@""]; t.identifier = @"cell"; t.lineBreakMode = NSLineBreakByTruncatingTail; }
    t.stringValue = _styles[(NSUInteger)row].name;
    return t;
}
- (void)tableViewSelectionDidChange:(NSNotification *)n { [self populate]; }

static NSColor *colorFromRGB(int rgb) {
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}
static int rgbFromColor(NSColor *c) {
    NSColor *s = [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!s) return 0;
    auto ch = [](CGFloat x) { return static_cast<int>(MAX(0.0, MIN(1.0, x)) * 255.0 + 0.5); };
    return (ch(s.redComponent) << 16) | (ch(s.greenComponent) << 8) | ch(s.blueComponent);
}

// upstream WordStyleDlg::goToPreferencesSettings
- (NSString *)settingsPageForStyle:(NSString *)n {
    if ([n isEqualToString:@"Current line background colour"] || [n isEqualToString:@"Caret colour"] || [n isEqualToString:@"Selected text colour"]) return @"Editing 1";
    if ([@[@"Multi-edit carets color", @"Multi-selected text color", @"EOL custom color", @"Non-printing characters custom color"] containsObject:n]) return @"Editing 2";
    if ([@[@"Edge colour", @"Line number margin", @"Bookmark margin", @"Change History margin", @"Change History modified", @"Change History revert modified",
           @"Change History revert origin", @"Change History saved", @"Fold", @"Fold active", @"Fold margin"] containsObject:n]) return @"Margins/Border/Edge";
    if ([n isEqualToString:@"Smart Highlighting"] || [n isEqualToString:@"Tags match highlighting"] || [n isEqualToString:@"Tags attribute"] || [n hasPrefix:@"Mark Style "]) return @"Highlighting";
    if ([n isEqualToString:@"URL hovered"]) return @"Cloud & Link";
    if ([n hasPrefix:@"Active tab "] || [n isEqualToString:@"Inactive tabs"]) return @"Tab Bar";
    return nil;
}

- (void)populate {
    _populating = YES;
    TPStyleSpec *s = self.currentStyle;
    NSString *lang = _languagePopup.selectedItem.representedObject;
    BOOL isGlobal = [lang isEqualToString:kGlobalStyles];
    _description.stringValue = s ? s.name : @"";
    _foregroundWell.color = colorFromRGB(s && s.fg >= 0 ? s.fg : 0x000000);
    _backgroundWell.color = colorFromRGB(s && s.bg >= 0 ? s.bg : 0xFFFFFF);
    _foregroundWell.enabled = _backgroundWell.enabled = s != nil;
    [_fontPopup selectItemWithTitle:s.fontName ?: @""];
    if (!_fontPopup.selectedItem || (s.fontName.length && ![_fontPopup.titleOfSelectedItem isEqualToString:s.fontName])) {
        if (s.fontName.length) { [_fontPopup addItemWithTitle:s.fontName]; [_fontPopup selectItemWithTitle:s.fontName]; }
        else [_fontPopup selectItemAtIndex:0];
    }
    NSString *sz = s.fontSize > 0 ? [NSString stringWithFormat:@"%g", s.fontSize] : @"";
    if (![_fontSizePopup itemWithTitle:sz]) [_fontSizePopup addItemWithTitle:sz];
    [_fontSizePopup selectItemWithTitle:sz];
    int fs = s && s.fontStyle >= 0 ? s.fontStyle : 0;
    _boldCheck.state = (fs & 1) != 0; _italicCheck.state = (fs & 2) != 0; _underlineCheck.state = (fs & 4) != 0;
    // keywords and extensions
    BOOL hasKw = !isGlobal && s.keywordClass.length;
    _keywordsGroup.hidden = !hasKw;
    _defaultKeywordsView.string = hasKw ? [[TPLanguageService shared] defaultKeywordsForLanguage:lang keywordClass:s.keywordClass] : @"";
    _userKeywordsView.string = hasKw ? (s.userKeywords ?: @"") : @"";
    TPLexerType *lt = isGlobal ? nil : [[TPLanguageService shared] lexerTypeNamed:lang];
    _defaultExtField.stringValue = lt ? [[[TPLanguageService shared] languageForId:lang].extensions componentsJoinedByString:@" "] ?: @"" : @"";
    _userExtField.stringValue = lt.userExt ?: @"";
    _userExtField.enabled = lt != nil;
    // Global override
    BOOL isGO = isGlobal && [s.name isEqualToString:@"Global override"];
    _globalGroup.hidden = !isGO;
    NSArray *keys = [self goKeys];
    for (NSUInteger i = 0; i < keys.count; ++i) _globalOverrideChecks[i].state = [TPPrefs b:keys[i]];
    _goToSettingsButton.hidden = [self settingsPageForStyle:s.name] == nil;
    _populating = NO;
}

// ---------------------------------------------------------------- edits
- (void)reapplyEverywhere {
    TPMainWindowController *c = _c;
    for (TPDocument *d in c.allDocuments) d.appliedLexerLanguage = nil;   // keyword lists are set with the lexer
    for (TPEditorPane *p in @[c.mainPane, c.subPane])
        if (p.currentDocument) [[TPLanguageService shared] applyLanguageOfDocument:p.currentDocument toView:p.editor];
    [c refreshUI];
    [c.mainPane.tabBar setNeedsDisplay:YES];
    [c.subPane.tabBar setNeedsDisplay:YES];
}

- (IBAction)controlChanged:(id)sender {
    if (_populating) return;
    TPLanguageService *ls = [TPLanguageService shared];
    NSUInteger goIndex = sender ? [_globalOverrideChecks indexOfObjectIdenticalTo:sender] : NSNotFound;
    if (goIndex != NSNotFound) {
        [TPPrefs set:@(_globalOverrideChecks[goIndex].state == NSControlStateValueOn) forKey:[self goKeys][goIndex]];
        [self reapplyEverywhere];
        return;
    }
    TPStyleSpec *s = self.currentStyle;
    if (!s) return;
    if (sender == _foregroundWell) { s.fg = rgbFromColor(_foregroundWell.color); s.colorStyle |= 1; }
    else if (sender == _backgroundWell) { s.bg = rgbFromColor(_backgroundWell.color); s.colorStyle |= 2; }
    else if (sender == _fontPopup) s.fontName = _fontPopup.titleOfSelectedItem.length ? _fontPopup.titleOfSelectedItem : nil;
    else if (sender == _fontSizePopup) s.fontSize = _fontSizePopup.titleOfSelectedItem.doubleValue;
    else if (sender == _boldCheck || sender == _italicCheck || sender == _underlineCheck)
        s.fontStyle = (_boldCheck.state ? 1 : 0) | (_italicCheck.state ? 2 : 0) | (_underlineCheck.state ? 4 : 0);
    [ls styleDidChange:s];
    [self reapplyEverywhere];
}

- (void)controlTextDidChange:(NSNotification *)n {
    if (_populating || n.object != _userExtField) return;
    TPLexerType *lt = [[TPLanguageService shared] lexerTypeNamed:_languagePopup.selectedItem.representedObject];
    if (lt) [[TPLanguageService shared] setUserExt:_userExtField.stringValue forLexerType:lt];
}

- (void)textDidChange:(NSNotification *)n {
    if (_populating || n.object != _userKeywordsView || !self.currentStyle) return;
    [[TPLanguageService shared] setUserKeywords:_userKeywordsView.string forStyle:self.currentStyle];
    [self reapplyEverywhere];
}

- (IBAction)goToSettings:(id)sender {
    NSString *page = [self settingsPageForStyle:self.currentStyle.name];
    if (page) [[TPPreferencesWindow shared] showPage:page];
}

- (IBAction)saveAndClose:(id)sender {
    TPLanguageService *ls = [TPLanguageService shared];
    if (ls.themeModified) {
        NSString *err = nil;
        if (![ls saveThemeWithError:&err]) { [_c showMessage:@"Cannot save the theme." informative:err]; return; }
    }
    [TPPrefs set:ls.themePath forKey:[TPChrome dark] ? @"ThemePathDark" : @"ThemePath"];   // the theme of the mode in use
    [self.window orderOut:nil];
}

- (IBAction)cancel:(id)sender {
    TPLanguageService *ls = [TPLanguageService shared];
    if (_originalThemePath && (ls.themeModified || ![ls.themePath isEqualToString:_originalThemePath])) [ls loadTheme:_originalThemePath error:nil];
    for (NSString *k in _originalGO) if ([TPPrefs b:k] != [_originalGO[k] boolValue]) [TPPrefs set:_originalGO[k] forKey:k];
    [self reapplyEverywhere];
    [self.window orderOut:nil];
}

- (BOOL)windowShouldClose:(NSWindow *)w { [self cancel:nil]; return NO; }

@end
