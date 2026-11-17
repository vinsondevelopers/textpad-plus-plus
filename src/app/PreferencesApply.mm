// Textpad++ — applying preferences to the editors and the window, plus the editing assists that
// preferences control (upstream: ScintillaEditView::init/performGlobalStyles, AutoCompletion,
// SmartHighlighter, URL indicators, delimiter selection, backup on save). GPL-3.0-or-later.
#import "app/MainWindowController.h"
#import "app/Preferences.h"
#import "app/MenuBarView.h"
#import "app/Localization.h"
#import "app/LanguageService.h"
#import "app/UserDefinedLanguages.h"
#import "app/Session.h"
#import "app/AutoCompletion.h"

using namespace npp;

static const int kIndicURL = 8;   // upstream URL_INDIC

void TPBeep(void) {
    if (![TPPrefs b:@"pref.muteSounds"]) NSBeep();
}

@implementation TPChrome
+ (BOOL)dark {
    NSInteger m = [TPPrefs i:@"pref.darkMode"];
    if (m == 1) return YES;
    if (m == 2) return [[NSApp.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    return NO;
}
static NSColor *rgb(int v) { return [NSColor colorWithSRGBRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:1]; }
// Preferences > Dark Mode > Tones (upstream NppDarkMode): every background and edge colour gets the tone's offset
// (red 0x100000, green 0x001000, blue 0x000020, purple 0x100020, cyan 0x001020, olive 0x101000; edges + 0x1C1C1C);
// "Customized" takes the user's colours.
static int toneOffset() {
    static const int offsets[] = {0, 0x100000, 0x001000, 0x000020, 0x100020, 0x001020, 0x101000};
    NSInteger t = [TPPrefs i:@"pref.darkTone"];
    return t >= 0 && t < 7 ? offsets[t] : 0;
}
static int customColor(NSString *name) {
    unsigned v = 0;
    [[NSScanner scannerWithString:[TPPrefs s:[@"pref.darkCustom." stringByAppendingString:name]] ?: @""] scanHexInt:&v];
    return static_cast<int>(v & 0xFFFFFF);
}
static NSColor *toned(int base, NSString *customName, BOOL edge) {
    if ([TPPrefs i:@"pref.darkTone"] == 7) return rgb(customColor(customName));
    int off = toneOffset();
    if (off && edge) off += 0x1C1C1C;
    return rgb(base + off);
}
+ (NSColor *)barBackground { return [self dark] ? toned(0x202020, @"background", NO) : rgb(0xF5F5F5); }
+ (NSColor *)tabStripBackground { return [self dark] ? toned(0x1B1B1B, @"pureBackground", NO) : rgb(0xF0F0F0); }
+ (NSColor *)tabActive { return [self dark] ? toned(0x3A3A3A, @"softerBackground", NO) : NSColor.whiteColor; }
+ (NSColor *)tabInactive { return [self dark] ? toned(0x262626, @"background", NO) : rgb(0xDBDBDB); }
+ (NSColor *)tabHover { return [self dark] ? toned(0x303030, @"hotBackground", NO) : rgb(0xE6E6E6); }
+ (NSColor *)tabActiveText { return [self dark] ? ([TPPrefs i:@"pref.darkTone"] == 7 ? rgb(customColor(@"text")) : rgb(0xEFEFEF)) : NSColor.blackColor; }
+ (NSColor *)tabInactiveText { return [self dark] ? ([TPPrefs i:@"pref.darkTone"] == 7 ? rgb(customColor(@"darkerText")) : rgb(0x9A9A9A)) : rgb(0x808080); }
+ (NSColor *)border { return [self dark] ? toned(0x404040, @"edge", YES) : rgb(0xB8B8B8); }
+ (NSColor *)separator { return [self dark] ? toned(0x4A4A4A, @"disabledEdge", YES) : rgb(0xC8C8C8); }
+ (NSColor *)statusText { return [self dark] ? ([TPPrefs i:@"pref.darkTone"] == 7 ? rgb(customColor(@"text")) : rgb(0xDCDCDC)) : NSColor.blackColor; }
@end

@implementation TPMainWindowController (Prefs)

- (void)installPreferenceObservers {
    [TPPrefs registerDefaults];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(preferencesChanged:) name:TPPrefsChangedNotification object:nil];
    [NSApp addObserver:self forKeyPath:@"effectiveAppearance" options:0 context:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"effectiveAppearance"] && [TPPrefs i:@"pref.darkMode"] == 2) [self applyAllPreferences];
}

- (void)preferencesChanged:(NSNotification *)n {
    NSString *key = n.userInfo[@"key"];
    if ([key isEqualToString:@"pref.darkMode"] || [key isEqualToString:@"pref.sqlBackslash"]) {
        for (TPDocument *d in self.allDocuments) d.appliedLexerLanguage = nil;
    }
    if ([key isEqualToString:@"RememberSession"] || [key isEqualToString:@"SessionSnapshot"] || [key isEqualToString:@"BackupInterval"]) {
        TPSessionReloadSettings(self);
    }
    if ([key isEqualToString:@"pref.cloudPath"]) {
        // upstream: the cloud folder is used from the next start; seed it now with the current settings
        NSString *path = [TPPrefs s:@"pref.cloudPath"];
        if (path.length) [[TPSession shared] seedCloudFolder:path];
        if (!self.selfTestMode) [self showMessage:@"Settings on cloud" informative:@"Restart Textpad++ to use the new settings location."];
    }
    [[TPSession shared] exportPreferencesToCloud];
    [self applyAllPreferences];
}

- (void)applyAllPreferences {
    [self applyDarkMode];
    for (TPEditorPane *p in @[self.mainPane, self.subPane]) {
        [self applyEditorPrefs:p.editor];
        if (p.currentDocument) [[TPLanguageService shared] applyLanguageOfDocument:p.currentDocument toView:p.editor];
        [p reloadTabs];
        [p setFrameSize:p.frame.size];
        p.tabBar.needsDisplay = YES;
    }
    [self applyViewFlagsPublic];
    if (NSApp.mainMenu) [[TPLocalization shared] applyPreference];   // Preferences > General > Localization
    [self.toolbar reloadIcons];
    [self applyChromeVisibility];
    [self refreshUI];
    self.statusBar.needsDisplay = YES;
    self.toolbar.needsDisplay = YES;
}

- (void)applyChromeVisibility {
    BOOL chromeOff = [self chromeForcedHidden];
    self.toolbar.hidden = chromeOff || [TPPrefs b:@"pref.toolbarHidden"];
    self.statusBar.hidden = chromeOff || [TPPrefs b:@"pref.statusBarHidden"];
    for (TPEditorPane *p in @[self.mainPane, self.subPane]) {
        p.tabBar.hidden = chromeOff || [TPPrefs b:@"pref.tabHidden"] || self.tabBarForcedHidden;
        [p setFrameSize:p.frame.size];
    }
    [self applyInWindowMenuVisibility];
    [self.window.contentView resizeSubviewsWithOldSize:self.window.contentView.bounds.size];
}

- (void)applyDarkMode {
    // Textpad++ windows and dialogs follow Preferences > Dark Mode (as upstream), not only the main window
    NSInteger mode = [TPPrefs i:@"pref.darkMode"];
    NSAppearance *want = mode == 2 ? nil : [NSAppearance appearanceNamed:mode == 1 ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    if (NSApp.appearance != want && ![NSApp.appearance.name isEqualToString:want.name]) NSApp.appearance = want;
    BOOL dark = [TPChrome dark];
    self.window.appearance = [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua];
    // View > Modern Look: the title bar takes the toolbar's colour, so they read as one bar
    const BOOL modern = [TPPrefs b:@"pref.modernLook"];
    self.window.titlebarAppearsTransparent = modern;
    self.window.backgroundColor = modern ? [TPChrome barBackground] : NSColor.windowBackgroundColor;
    TPLanguageService *ls = [TPLanguageService shared];
    // View > Modern Look starts on the macOS-like themes (a theme chosen in the Style Configurator still wins)
    NSString *darkTheme = [TPLanguageService themePathForFileName:modern ? @"macOS Dark.xml" : @"DarkModeDefault.xml"];
    NSString *modernLight = modern ? [TPLanguageService themePathForFileName:@"macOS Light.xml"] : nil;
    // upstream keeps one theme per mode (config.xml lightThemeName / darkThemeName): the Style Configurator's
    // Save & Close stores the theme for the mode in use, dark mode starts on DarkModeDefault.xml
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *userTheme = [TPPrefs s:@"ThemePath"], *userDarkTheme = [TPPrefs s:@"ThemePathDark"];
    NSString *lightTheme = (userTheme.length && [fm fileExistsAtPath:userTheme]) ? userTheme : modernLight ?: [TPLanguageService defaultThemePath];
    NSString *wantDark = (userDarkTheme.length && [fm fileExistsAtPath:userDarkTheme]) ? userDarkTheme
                       : (userTheme.length && [userTheme.lastPathComponent.lowercaseString containsString:@"dark"] ? userTheme : darkTheme);
    NSString *wantTheme = dark ? wantDark : lightTheme;
    // Reload only when the light/dark state or the chosen theme changed: the Style Configurator previews other
    // themes and unsaved edits in the loaded theme, which an unrelated preference change must not discard.
    static NSString *lastThemeKey;
    NSString *key = [NSString stringWithFormat:@"%d|%d|%@|%@", dark, modern, userTheme ?: @"", userDarkTheme ?: @""];
    if (wantTheme && ![key isEqualToString:lastThemeKey]) {
        lastThemeKey = key;
        if (![ls.themePath isEqualToString:wantTheme]) {
            [ls loadTheme:wantTheme error:nil];
            for (TPDocument *d in self.allDocuments) d.appliedLexerLanguage = nil;
        }
    }
}

// ---------------------------------------------------------------- editor options
- (void)applyEditorPrefs:(ScintillaView *)v {
    NSInteger clm = [TPPrefs i:@"pref.currentLineMode"];
    SCI(v, SCI_SETCARETLINEVISIBLE, clm != 0);
    SCI(v, SCI_SETCARETLINEFRAME, clm == 2 ? MAX(1, [TPPrefs i:@"pref.currentLineFrameWidth"]) : 0);
    NSInteger cw = [TPPrefs i:@"pref.caretWidth"];
    if (cw <= 3) { SCI(v, SCI_SETCARETSTYLE, cw == 0 ? CARETSTYLE_INVISIBLE : CARETSTYLE_LINE); SCI(v, SCI_SETCARETWIDTH, MAX(1, cw)); }
    else SCI(v, SCI_SETCARETSTYLE, cw == 4 ? CARETSTYLE_BLOCK : (CARETSTYLE_BLOCK | CARETSTYLE_BLOCK_AFTER));
    SCI(v, SCI_SETCARETPERIOD, [TPPrefs i:@"pref.caretBlink"]);
    NSInteger wm = [TPPrefs i:@"pref.wrapIndentMode"];
    SCI(v, SCI_SETWRAPINDENTMODE, wm == 0 ? SC_WRAPINDENT_FIXED : wm == 1 ? SC_WRAPINDENT_SAME : SC_WRAPINDENT_INDENT);
    SCI(v, SCI_SETFONTQUALITY, [TPPrefs b:@"pref.smoothFont"] ? SC_EFF_QUALITY_LCD_OPTIMIZED : SC_EFF_QUALITY_DEFAULT);
    SCI(v, SCI_SETVIRTUALSPACEOPTIONS, SCVS_RECTANGULARSELECTION | ([TPPrefs b:@"pref.virtualSpace"] ? SCVS_USERACCESSIBLE | SCVS_NOWRAPLINESTART : 0));
    TPStyleSpec *sel = [[TPLanguageService shared] globalStyle:@"Selected text colour"];
    if ([TPPrefs b:@"pref.selFgCustom"] && sel.fg >= 0) SCI(v, SCI_SETELEMENTCOLOUR, SC_ELEMENT_SELECTION_TEXT, rgbToSci(sel.fg) | 0xFF000000);
    else SCI(v, SCI_RESETELEMENTCOLOUR, SC_ELEMENT_SELECTION_TEXT);
    SCI(v, SCI_SETENDATLASTLINE, ![TPPrefs b:@"pref.scrollBeyondLast"]);
    SCI(v, SCI_SETDRAGDROPENABLED, ![TPPrefs b:@"pref.disableDragDrop"]);
    BOOL multi = [TPPrefs b:@"pref.multiEditing"];
    SCI(v, SCI_SETMULTIPLESELECTION, multi);
    SCI(v, SCI_SETADDITIONALSELECTIONTYPING, multi);
    SCI(v, SCI_SETBACKSPACEUNINDENTS, [TPPrefs b:@"pref.backspaceUnindent"]);
    // word characters (Preferences > Delimiter) are a per-document setting: see TPLanguageService
    [self applyFoldStyle:v];
    // vertical edge(s)
    NSArray *cols = [[TPPrefs s:@"pref.edgeColumns"] componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSMutableArray<NSNumber *> *nums = [NSMutableArray array];
    for (NSString *c in cols) if (c.integerValue > 0) [nums addObject:@(c.integerValue)];
    TPStyleSpec *edge = [[TPLanguageService shared] globalStyle:@"Edge colour"];
    int edgeColor = rgbToSci(edge && edge.fg >= 0 ? edge.fg : 0x80FFFF);
    SCI(v, SCI_MULTIEDGECLEARALL);
    if (![TPPrefs b:@"pref.edgeEnabled"] || !nums.count) SCI(v, SCI_SETEDGEMODE, EDGE_NONE);
    else if (nums.count == 1) {
        SCI(v, SCI_SETEDGEMODE, [TPPrefs b:@"pref.edgeBgMode"] ? EDGE_BACKGROUND : EDGE_LINE);
        SCI(v, SCI_SETEDGECOLUMN, nums[0].integerValue);
        SCI(v, SCI_SETEDGECOLOUR, edgeColor);
    } else {
        SCI(v, SCI_SETEDGEMODE, EDGE_MULTILINE);
        for (NSNumber *n in nums) SCI(v, SCI_MULTIEDGEADDLINE, n.integerValue, edgeColor);
    }
    // change history
    BOOL chM = [TPPrefs b:@"pref.chMargin"], chT = [TPPrefs b:@"pref.chText"];
    int ch = (chM || chT) ? (SC_CHANGE_HISTORY_ENABLED | (chM ? SC_CHANGE_HISTORY_MARKERS : 0) | (chT ? SC_CHANGE_HISTORY_INDICATORS : 0)) : SC_CHANGE_HISTORY_DISABLED;
    if (SCI(v, SCI_GETCHANGEHISTORY) != ch) {
        // the "enabled" bit can only be switched on with an empty undo history; keep it if already on
        int cur = static_cast<int>(SCI(v, SCI_GETCHANGEHISTORY));
        if ((cur & SC_CHANGE_HISTORY_ENABLED) && (ch & SC_CHANGE_HISTORY_ENABLED)) SCI(v, SCI_SETCHANGEHISTORY, ch);
        else if (!(ch & SC_CHANGE_HISTORY_ENABLED)) SCI(v, SCI_SETCHANGEHISTORY, ch);
        else if (!SCI(v, SCI_CANUNDO)) SCI(v, SCI_SETCHANGEHISTORY, ch);
    }
    SCI(v, SCI_SETMARGINWIDTHN, TPP_MARGIN_CHANGEHISTORY, chM ? 9 : 0);
    SCI(v, SCI_SETMARGINWIDTHN, TPP_MARGIN_SYMBOL, [TPPrefs b:@"pref.bookmarkMargin"] ? 16 : 0);
    if (!self.distractionFreeActive) {
        SCI(v, SCI_SETMARGINLEFT, 0, MAX(1, [TPPrefs i:@"pref.padLeft"]));
        SCI(v, SCI_SETMARGINRIGHT, 0, MAX(1, [TPPrefs i:@"pref.padRight"]));
    }
    // clickable links indicator (upstream URL_INDIC)
    SCI(v, SCI_INDICSETSTYLE, kIndicURL, [TPPrefs b:@"pref.linkFullBox"] ? INDIC_FULLBOX : ([TPPrefs b:@"pref.linkNoUnderline"] ? INDIC_HIDDEN : INDIC_PLAIN));
    SCI(v, SCI_INDICSETFORE, kIndicURL, rgbToSci([TPChrome dark] ? 0x6CB4FF : 0x0000FF));
    SCI(v, SCI_INDICSETHOVERSTYLE, kIndicURL, INDIC_FULLBOX);
    SCI(v, SCI_INDICSETALPHA, kIndicURL, 40);
}

- (void)applyFoldStyle:(ScintillaView *)v {
    NSInteger st = [TPPrefs i:@"pref.foldStyle"];   // 0 simple, 1 arrow, 2 circle tree, 3 box tree, 4 none
    int open, folder, sub = SC_MARK_EMPTY, tail = SC_MARK_EMPTY, end = SC_MARK_EMPTY, openMid = SC_MARK_EMPTY, midTail = SC_MARK_EMPTY;
    switch (st) {
        case 0: open = SC_MARK_MINUS; folder = SC_MARK_PLUS; end = SC_MARK_PLUS; openMid = SC_MARK_MINUS; break;
        case 1: open = SC_MARK_ARROWDOWN; folder = SC_MARK_ARROW; end = SC_MARK_ARROW; openMid = SC_MARK_ARROWDOWN; break;
        case 2: open = SC_MARK_CIRCLEMINUS; folder = SC_MARK_CIRCLEPLUS; sub = SC_MARK_VLINE; tail = SC_MARK_LCORNERCURVE;
                end = SC_MARK_CIRCLEPLUSCONNECTED; openMid = SC_MARK_CIRCLEMINUSCONNECTED; midTail = SC_MARK_TCORNERCURVE; break;
        default: open = SC_MARK_BOXMINUS; folder = SC_MARK_BOXPLUS; sub = SC_MARK_VLINE; tail = SC_MARK_LCORNER;
                 end = SC_MARK_BOXPLUSCONNECTED; openMid = SC_MARK_BOXMINUSCONNECTED; midTail = SC_MARK_TCORNER; break;
    }
    SCI(v, SCI_MARKERDEFINE, SC_MARKNUM_FOLDEROPEN, open);
    SCI(v, SCI_MARKERDEFINE, SC_MARKNUM_FOLDER, folder);
    SCI(v, SCI_MARKERDEFINE, SC_MARKNUM_FOLDERSUB, sub);
    SCI(v, SCI_MARKERDEFINE, SC_MARKNUM_FOLDERTAIL, tail);
    SCI(v, SCI_MARKERDEFINE, SC_MARKNUM_FOLDEREND, end);
    SCI(v, SCI_MARKERDEFINE, SC_MARKNUM_FOLDEROPENMID, openMid);
    SCI(v, SCI_MARKERDEFINE, SC_MARKNUM_FOLDERMIDTAIL, midTail);
    SCI(v, SCI_SETMARGINWIDTHN, TPP_MARGIN_FOLDER, st == 4 ? 0 : 14);
}

// ---------------------------------------------------------------- document helpers
- (BOOL)isLargeDocument:(TPDocument *)d {
    if (![TPPrefs b:@"pref.largeFileEnabled"]) return NO;
    return d.diskSize > (unsigned long long)MAX(1, [TPPrefs i:@"pref.largeFileMB"]) * 1024ull * 1024ull;
}

- (NSURL *)defaultDirectoryURL {
    NSInteger mode = [TPPrefs i:@"pref.defaultDirMode"];
    NSString *dir = nil;
    if (mode == 2) dir = [TPPrefs s:@"pref.defaultDirPath"];
    else if (mode == 1) dir = [TPPrefs s:@"pref.lastDir"];
    if (!dir.length) dir = self.currentDocument.path.stringByDeletingLastPathComponent;
    return dir.length ? [NSURL fileURLWithPath:dir] : nil;
}

- (void)rememberDirectory:(NSString *)dir {
    if (dir.length) [[NSUserDefaults standardUserDefaults] setObject:dir forKey:@"pref.lastDir"];
}

// Preferences > Backup > "Backup on save" (upstream: nppBackup folder next to the file).
- (void)backupBeforeSave:(NSString *)path {
    NSInteger mode = [TPPrefs i:@"pref.backupOnSave"];
    if (mode == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return;
    NSString *dir = [TPPrefs b:@"pref.customBackupDirEnabled"] && [TPPrefs s:@"pref.customBackupDir"].length
        ? [TPPrefs s:@"pref.customBackupDir"] : [path.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"TextpadBackup"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *name = path.lastPathComponent;
    if (mode == 2) {
        NSDateFormatter *f = [NSDateFormatter new];
        f.dateFormat = @"yyyy-MM-dd_HHmmss";
        name = [NSString stringWithFormat:@"%@.%@.bak", name, [f stringFromDate:[NSDate date]]];
    } else {
        name = [name stringByAppendingString:@".bak"];
    }
    NSString *dest = [dir stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
    [[NSFileManager defaultManager] copyItemAtPath:path toPath:dest error:nil];
}

// ---------------------------------------------------------------- assists driven by notifications
- (void)handleCharAdded:(SCNotification *)scn pane:(TPEditorPane *)pane {
    ScintillaView *v = pane.editor;
    TPDocument *doc = pane.currentDocument;
    int ch = scn->ch;
    if (SCI(v, SCI_GETSELECTIONS) > 1) return;
    sptr_t pos = SCI(v, SCI_GETCURRENTPOS);
    // Auto-insert matched pairs (upstream AutoCompletion::insertMatchedChars, simplified)
    struct { NSString *key; int open; const char *close; } pairs[] = {
        {@"pref.pairParen", '(', ")"}, {@"pref.pairBracket", '[', "]"}, {@"pref.pairBrace", '{', "}"},
        {@"pref.pairQuote", '"', "\""}, {@"pref.pairApos", '\'', "'"}};
    for (auto &p : pairs) {
        if (![TPPrefs b:p.key]) continue;
        int next = static_cast<int>(SCI(v, SCI_GETCHARAT, pos));
        if (ch == p.close[0] && next == ch && p.open != p.close[0]) { SCI(v, SCI_DELETERANGE, pos, 1); return; }   // type over
        if (ch == p.open) {
            if (p.open == p.close[0] && next == ch) { SCI(v, SCI_DELETERANGE, pos, 1); return; }                     // quote type over
            BOOL ok = next == 0 || next == ' ' || next == '\t' || next == '\r' || next == '\n' || strchr(")]};,", next);
            if (ok) { SCI(v, SCI_INSERTTEXT, pos, reinterpret_cast<sptr_t>(p.close)); return; }
        }
    }
    for (int i = 1; i <= 3; ++i) {
        NSString *o = [TPPrefs s:[NSString stringWithFormat:@"pref.pair%dOpen", i]], *c = [TPPrefs s:[NSString stringWithFormat:@"pref.pair%dClose", i]];
        if (o.length == 1 && c.length == 1 && [o characterAtIndex:0] == ch) { SCI(v, SCI_INSERTTEXT, pos, reinterpret_cast<sptr_t>(c.UTF8String)); return; }
    }
    if (ch == '>' && [TPPrefs b:@"pref.pairHtmlTag"] && [@[@"html", @"xml", @"php", @"asp", @"jsp"] containsObject:doc.languageId]) {
        sptr_t lineStart = SCI(v, SCI_POSITIONFROMLINE, SCI(v, SCI_LINEFROMPOSITION, pos));
        std::string before = sciGetRange(v, lineStart, pos);
        size_t lt = before.rfind('<');
        if (lt != std::string::npos && before.size() >= 2 && before[before.size() - 2] != '/') {
            std::string tag = before.substr(lt + 1);
            if (!tag.empty() && tag[0] != '/' && tag[0] != '!' && tag[0] != '?') {
                size_t e = tag.find_first_of(" \t>");
                std::string name = tag.substr(0, e);
                if (!name.empty()) {
                    std::string close = "</" + name + ">";
                    SCI(v, SCI_INSERTTEXT, pos, reinterpret_cast<sptr_t>(close.c_str()));
                }
            }
        }
    }
    // Auto-completion / function parameter hint on each input (upstream AutoCompletion::update)
    if ([self isLargeDocument:doc] && ![TPPrefs b:@"pref.largeFileAutoC"]) return;
    TPAutoCompletion *ac = [TPAutoCompletion forView:v];
    [ac setLanguageId:doc.languageId ?: @"normal"];
    [ac update:ch];
}

- (void)handleDoubleClick:(SCNotification *)scn pane:(TPEditorPane *)pane {
    ScintillaView *v = pane.editor;
    sptr_t pos = scn->position;
    if (pos >= 0 && [TPPrefs b:@"pref.links"] && SCI(v, SCI_INDICATORVALUEAT, kIndicURL, pos)) {
        [self openURLAt:pos view:v];
        return;
    }
    if (!(scn->modifiers & SCMOD_CTRL) || pos < 0) return;
    // Preferences > Delimiter: ⌘ + double click selects the text between the delimiters
    std::string open = StdStr([TPPrefs s:@"pref.delimOpen"]), close = StdStr([TPPrefs s:@"pref.delimClose"]);
    if (open.empty() || close.empty()) return;
    BOOL multi = [TPPrefs b:@"pref.delimMultiLine"];
    sptr_t line = SCI(v, SCI_LINEFROMPOSITION, pos);
    sptr_t lo = multi ? 0 : SCI(v, SCI_POSITIONFROMLINE, line), hi = multi ? SCI(v, SCI_GETLENGTH) : SCI(v, SCI_GETLINEENDPOSITION, line);
    std::string text = sciGetRange(v, lo, hi);
    size_t rel = static_cast<size_t>(pos - lo);
    size_t a = text.rfind(open, rel > 0 ? rel - 1 : 0);
    size_t b = text.find(close, rel);
    if (a == std::string::npos || b == std::string::npos || a + open.size() > b) return;
    SCI(v, SCI_SETSEL, lo + a + open.size(), lo + b);
}

- (void)openURLAt:(sptr_t)pos view:(ScintillaView *)v {
    sptr_t s = SCI(v, SCI_INDICATORSTART, kIndicURL, pos), e = SCI(v, SCI_INDICATOREND, kIndicURL, pos);
    NSURL *u = [NSURL URLWithString:NSStr(sciGetRange(v, s, e))];
    if (u) [[NSWorkspace sharedWorkspace] openURL:u];
}

- (void)handleIndicatorClick:(SCNotification *)scn pane:(TPEditorPane *)pane {
    if ((scn->modifiers & SCMOD_CTRL) && SCI(pane.editor, SCI_INDICATORVALUEAT, kIndicURL, scn->position)) [self openURLAt:scn->position view:pane.editor];
}

// Mark URLs in the visible range (upstream: Notepad_plus::addHotSpot)
- (void)markLinksInView:(ScintillaView *)v document:(TPDocument *)doc {
    sptr_t len = SCI(v, SCI_GETLENGTH);
    SCI(v, SCI_SETINDICATORCURRENT, kIndicURL);
    BOOL allowed = [TPPrefs b:@"pref.links"] && (![self isLargeDocument:doc] || [TPPrefs b:@"pref.largeFileLinks"]);
    sptr_t first = SCI(v, SCI_DOCLINEFROMVISIBLE, SCI(v, SCI_GETFIRSTVISIBLELINE));
    sptr_t last = SCI(v, SCI_DOCLINEFROMVISIBLE, SCI(v, SCI_GETFIRSTVISIBLELINE) + SCI(v, SCI_LINESONSCREEN) + 1);
    sptr_t from = MAX((sptr_t)0, SCI(v, SCI_POSITIONFROMLINE, first));
    sptr_t to = last >= SCI(v, SCI_GETLINECOUNT) ? len : SCI(v, SCI_GETLINEENDPOSITION, last);
    if (to < from || to > len) to = len;
    if (to > from) SCI(v, SCI_INDICATORCLEARRANGE, from, to - from);
    if (!allowed || to <= from) return;
    std::string text = sciGetRange(v, from, to);
    NSMutableArray *schemes = [NSMutableArray arrayWithArray:@[@"http://", @"https://", @"ftp://", @"file://", @"mailto:"]];
    for (NSString *s in [[TPPrefs s:@"pref.uriSchemes"] componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet])
        if (s.length) [schemes addObject:s];
    for (NSString *scheme in schemes) {
        std::string sc = StdStr(scheme);
        size_t p = 0;
        while ((p = text.find(sc, p)) != std::string::npos) {
            if (p > 0 && (isalnum(static_cast<unsigned char>(text[p - 1])))) { p += sc.size(); continue; }
            size_t e = p + sc.size();
            while (e < text.size() && !isspace(static_cast<unsigned char>(text[e])) && !strchr("\"'<>`{}|\\^", text[e]) && static_cast<unsigned char>(text[e]) >= 0x21) ++e;
            while (e > p + sc.size() && strchr(".,;:)]!?", text[e - 1])) --e;   // trailing punctuation is not part of the URL
            if (e > p + sc.size()) SCI(v, SCI_INDICATORFILLRANGE, from + static_cast<sptr_t>(p), static_cast<sptr_t>(e - p));
            p = e;
        }
    }
}

- (NSString *)titleText {
    TPDocument *d = self.currentDocument;
    if (!d) return @"Textpad++";
    NSString *name = [TPPrefs b:@"pref.shortTitle"] ? d.displayName : (d.path ?: d.displayName);
    NSString *t = [NSString stringWithFormat:@"%@%@ - Textpad++", d.dirty ? @"*" : @"", name];
    return self.titleAddition.length ? [t stringByAppendingFormat:@" - %@", self.titleAddition] : t;   // -titleAdd
}

// Recent-file label per Preferences > Recent Files History > Display
+ (NSString *)recentLabelForPath:(NSString *)p {
    NSInteger mode = [TPPrefs i:@"pref.recentDisplay"];
    if (mode == 0) return p.lastPathComponent;
    if (mode == 2) {
        NSInteger max = MAX(1, [TPPrefs i:@"pref.recentCustomLength"]);
        if ((NSInteger)p.length > max) {
            NSInteger keep = MAX(1, (max - 3) / 2);
            return [NSString stringWithFormat:@"%@...%@", [p substringToIndex:keep], [p substringFromIndex:p.length - keep]];
        }
    }
    return p;
}

@end
