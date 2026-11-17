// Textpad++ — typed preference store + Preferences window. GPL-3.0-or-later.
//
// The 24 pages and their controls follow upstream PowerEditor/src/WinControls/Preference/preference.rc
// (v8.9.9.1). Every control is either wired to real behaviour (see PreferencesApply.mm and the
// features that read TPPrefs) or shown disabled with the reason ("na"). Nothing is decorative.
#import "app/Preferences.h"
#import "app/Localization.h"
#include <functional>
#import "app/LanguageService.h"
#include "core/Encoding.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

NSNotificationName const TPPrefsChangedNotification = @"TPPrefsChangedNotification";

static NSString *const kNAPlatform = @"Not applicable on macOS";
static NSString *const kNANotBuilt = @"Feature not implemented yet";

@implementation TPPrefs

+ (void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        // General / Toolbar / Tab bar
        @"pref.statusBarHidden": @NO, @"pref.localization": @"",
        @"pref.inWindowMenu": @NO, @"pref.menuHidden": @NO, @"pref.hideRightShortcuts": @NO,
        @"pref.toolbarHidden": @NO, @"pref.toolbarIconSet": @5,
        @"pref.toolbarColorMode": @1, @"pref.toolbarColor": @7, @"pref.toolbarCustomColor": @"000000",
        @"pref.tabHidden": @NO, @"pref.tabLock": @NO, @"pref.tabDblClickClose": @NO, @"pref.tabExitOnLast": @NO,
        @"pref.tabMaxLabel": @0, @"pref.tabReduce": @YES, @"pref.tabAltIcons": @NO, @"pref.tabDrawInactive": @YES,
        @"pref.tabOrangeBar": @YES, @"pref.tabShowClose": @YES, @"pref.tabEnablePin": @YES, @"pref.tabOnlyPinnedButton": @NO,
        @"pref.tabInactiveButtons": @NO,
        // Editing 1 / 2
        @"pref.currentLineMode": @1, @"pref.currentLineFrameWidth": @1, @"pref.caretWidth": @1, @"pref.caretBlink": @600,
        @"pref.wrapIndentMode": @1, @"pref.smoothFont": @YES, @"pref.virtualSpace": @NO, @"pref.foldToggle": @NO,
        @"pref.copyCutLine": @YES, @"pref.selFgCustom": @NO, @"pref.scrollBeyondLast": @YES, @"pref.disableDragDrop": @NO,
        @"pref.multiEditing": @YES, @"pref.crlfPlain": @NO, @"pref.crlfCustomColor": @NO, @"pref.npcCodepoint": @NO,
        @"pref.npcCustomColor": @NO, @"pref.npcIncludeCC": @NO,
        @"pref.rightClickKeepsSel": @NO, @"pref.column2Multi": @YES, @"pref.npcNoInputC0": @YES,
        @"pref.suppress2GB": @NO, @"pref.detectEncoding": @YES, @"pref.autoUpdater": @YES, @"pref.autoInstallUpdates": @YES, @"pref.updatePublicKey": @"", @"pref.updateFeedURL": @"", @"pref.pluginListURL": @"", @"pref.systray": @0, @"pref.borderWidth": @2, @"pref.borderEdge": @YES,
        @"pref.dialogFont": @NO, @"pref.dialogFontName": @"", @"pref.dialogFontSize": @0, @"pref.docPeekOnTab": @NO, @"pref.docPeekOnMap": @NO,
        @"pref.markdownOpen": @0, @"pref.modernLook": @YES, @"pref.gitMarkers": @YES, @"pref.csvRainbow": @YES, @"pref.snippets": @YES, @"pref.compareIgnoreSpaces": @NO,
        // Dark mode
        @"pref.darkMode": @0,
        // Margins / Border / Edge
        @"pref.foldStyle": @3, @"pref.edgeEnabled": @NO, @"pref.edgeColumns": @"80", @"pref.edgeBgMode": @NO,
        @"pref.chMargin": @YES, @"pref.chText": @NO, @"pref.lineNumbers": @YES, @"pref.lineNumDynamic": @YES,
        @"pref.padLeft": @0, @"pref.padRight": @0, @"pref.distractionFreeWidth": @4, @"pref.bookmarkMargin": @YES,
        // New document
        @"NewDocEOL": @2, @"NewDocUniMode": @4, @"NewDocCodepage": @(-1), @"pref.openAnsiAsUtf8": @YES,
        @"pref.defaultLanguage": @"normal", @"pref.newDocOnStartup": @NO, @"pref.firstLineAsTabName": @NO,
        // Default directory / Recent files / Language
        @"pref.defaultDirMode": @0, @"pref.defaultDirPath": @"",
        @"pref.recentDontCheck": @NO, @"RecentFilesMax": @10, @"pref.recentInSubmenu": @NO, @"pref.recentDisplay": @1,
        @"pref.recentCustomLength": @100, @"pref.langMenuCompact": @YES, @"pref.hiddenLanguages": @[], @"pref.sqlBackslash": @NO,
        // Indentation
        @"TabWidth": @4, @"UseSpaces": @NO, @"pref.langIndent": @{}, @"pref.backspaceUnindent": @NO, @"pref.autoIndent": @2,
        // Highlighting
        @"pref.markAllMatchCase": @NO, @"pref.markAllWholeWord": @YES, @"pref.smartHL": @YES, @"pref.smartHLOtherView": @YES,
        @"pref.smartHLMatchCase": @NO, @"pref.smartHLWholeWord": @YES, @"pref.smartHLUseFind": @NO,
        // Print
        @"pref.printLineNumbers": @YES, @"pref.printFormfeed": @NO, @"pref.printColorMode": @3, @"pref.printMarginTop": @0, @"pref.printMarginLeft": @0,
        @"pref.printMarginRight": @0, @"pref.printMarginBottom": @0, @"pref.printHeaderLeft": @"", @"pref.printHeaderMiddle": @"",
        @"pref.printHeaderRight": @"", @"pref.printFooterLeft": @"", @"pref.printFooterMiddle": @"", @"pref.printFooterRight": @"",
        @"pref.printHeaderBold": @NO, @"pref.printHeaderItalic": @NO, @"pref.printFooterBold": @NO, @"pref.printFooterItalic": @NO,
        @"pref.printHFSize": @9,
        // Searching
        @"pref.inSelThreshold": @1024, @"pref.fifDirFromActive": @NO, @"pref.fillFindWithSelection": @YES,
        @"pref.fillFindMaxChars": @1024, @"pref.selectWordUnderCaret": @YES, @"pref.findMonospace": @NO,
        @"pref.findDlgStaysOpen": @YES, @"pref.oneEntryPerLine": @NO, @"pref.fifPreferDisk": @NO,
        // Backup
        @"RememberSession": @YES, @"SessionSnapshot": @YES, @"BackupInterval": @7, @"pref.keepAbsentFiles": @NO,
        @"pref.backupOnSave": @0, @"pref.customBackupDirEnabled": @NO, @"pref.customBackupDir": @"",
        // Auto-completion
        @"pref.go.fg": @NO, @"pref.go.bg": @NO, @"pref.go.font": @NO, @"pref.go.fontSize": @NO, @"pref.go.bold": @NO, @"pref.go.italic": @NO, @"pref.go.underline": @NO,
        @"pref.multiInstance": @0, @"pref.tabVertical": @NO, @"pref.tabMultiline": @NO, @"pref.dropFolderOpenFiles": @NO, @"pref.tagMatch": @YES, @"pref.tagAttrs": @YES, @"pref.panelState.cliphistory": @NO, @"pref.panelState.doclist": @NO, @"pref.panelState.charpanel": @NO, @"pref.panelState.faw": @NO,
        @"pref.panelState.project": @NO, @"pref.panelState.docmap": @NO, @"pref.panelState.funclist": @NO, @"pref.docListExt": @YES, @"pref.docListPath": @NO,
        @"pref.autocEnabled": @YES, @"pref.funcParamHint": @YES, @"pref.autocMode": @2, @"pref.autocBrief": @NO, @"pref.autocFromLen": @1,
        @"pref.autocInsertTab": @YES, @"pref.autocInsertEnter": @YES, @"pref.autocIgnoreNumbers": @YES,
        @"pref.pairParen": @NO, @"pref.pairBracket": @NO, @"pref.pairBrace": @NO, @"pref.pairQuote": @NO, @"pref.pairApos": @NO,
        @"pref.pairHtmlTag": @NO, @"pref.pair1Open": @"", @"pref.pair1Close": @"", @"pref.pair2Open": @"", @"pref.pair2Close": @"",
        @"pref.pair3Open": @"", @"pref.pair3Close": @"",
        // Multi-instance & date
        @"DateTimeReverseOrder": @NO, @"DateTimeCustomFormat": @"yyyy-MM-dd HH:mm:ss",
        // Delimiter
        @"pref.wordCharsDefault": @YES, @"pref.wordCharsCustom": @"", @"pref.delimOpen": @"(", @"pref.delimClose": @")",
        @"pref.delimMultiLine": @NO,
        // Performance
        @"pref.largeFileEnabled": @YES, @"pref.largeFileMB": @200, @"pref.largeFileNoWrap": @YES, @"pref.largeFileAutoC": @NO,
        @"pref.largeFileSmartHL": @NO, @"pref.largeFileBraceMatch": @NO, @"pref.largeFileLinks": @NO,
        // Dark Mode tones (upstream NppDarkMode darkColors are the customized defaults)
        @"pref.darkTone": @0, @"pref.darkCustom.background": @"202020", @"pref.darkCustom.softerBackground": @"383838",
        @"pref.darkCustom.hotBackground": @"454545", @"pref.darkCustom.pureBackground": @"202020", @"pref.darkCustom.errorBackground": @"B00000",
        @"pref.darkCustom.text": @"E0E0E0", @"pref.darkCustom.darkerText": @"C0C0C0", @"pref.darkCustom.disabledText": @"808080",
        @"pref.darkCustom.linkText": @"FFFF00", @"pref.darkCustom.edge": @"646464", @"pref.darkCustom.hotEdge": @"9B9B9B",
        @"pref.darkCustom.disabledEdge": @"484848", @"pref.cloudPath": @"",
        // Cloud & Link
        @"pref.links": @YES, @"pref.linkNoUnderline": @NO, @"pref.linkFullBox": @NO, @"pref.uriSchemes": @"svn:// git:// ssh:// sftp:// smb:// ftp:// irc://",
        // Search engine
        @"pref.searchEngine": @1, @"pref.searchEngineCustom": @"",
        // MISC.
        @"pref.fileAutoDetect": @0, @"pref.updateSilently": @NO, @"pref.updateGotoEOF": @NO, @"pref.docSwitcherMRU": @YES,
        @"pref.muteSounds": @NO, @"pref.shortTitle": @NO, @"pref.saveAllConfirm": @NO, @"pref.sessionFileExt": @"",
        @"pref.workspaceFileExt": @"", @"pref.symlinksFaW": @NO, @"pref.fileAssocExts": @"txt log md",
    }];
}

+ (BOOL)b:(NSString *)key { return [[NSUserDefaults standardUserDefaults] boolForKey:key]; }
+ (NSInteger)i:(NSString *)key { return [[NSUserDefaults standardUserDefaults] integerForKey:key]; }
+ (NSString *)s:(NSString *)key { return [[NSUserDefaults standardUserDefaults] stringForKey:key] ?: @""; }
+ (id)o:(NSString *)key { return [[NSUserDefaults standardUserDefaults] objectForKey:key]; }

+ (void)set:(id)value forKey:(NSString *)key {
    if (value) [[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    [[NSNotificationCenter defaultCenter] postNotificationName:TPPrefsChangedNotification object:nil userInfo:@{@"key": key}];
}

+ (NSInteger)tabSizeForLanguage:(NSString *)langId {
    NSDictionary *d = [self o:@"pref.langIndent"][langId];
    if (d && ![d[@"useDefault"] boolValue] && [d[@"size"] integerValue] > 0) return [d[@"size"] integerValue];
    return MAX(1, [self i:@"TabWidth"]);
}

+ (BOOL)useSpacesForLanguage:(NSString *)langId {
    NSDictionary *d = [self o:@"pref.langIndent"][langId];
    if (d && ![d[@"useDefault"] boolValue]) return [d[@"spaces"] boolValue];
    return [self b:@"UseSpaces"];
}

// ---------------------------------------------------------------- page spec
#define GROUP(t) @{@"t": @"group", @"label": t}
#define CHECK(k, l) @{@"t": @"check", @"key": k, @"label": l}
#define CHECKX(k, l, ...) @{@"t": @"check", @"key": k, @"label": l, __VA_ARGS__}
#define RADIO(k, l, opts) @{@"t": @"radio", @"key": k, @"label": l, @"options": opts}
#define RADIOX(k, l, opts, ...) @{@"t": @"radio", @"key": k, @"label": l, @"options": opts, __VA_ARGS__}
#define POPUP(k, l, opts) @{@"t": @"popup", @"key": k, @"label": l, @"options": opts}
#define INTF(k, l, mn, mx) @{@"t": @"int", @"key": k, @"label": l, @"min": @(mn), @"max": @(mx)}
#define INTFX(k, l, mn, mx, ...) @{@"t": @"int", @"key": k, @"label": l, @"min": @(mn), @"max": @(mx), __VA_ARGS__}
#define TEXTF(k, l) @{@"t": @"text", @"key": k, @"label": l}
#define TEXTFX(k, l, ...) @{@"t": @"text", @"key": k, @"label": l, __VA_ARGS__}
#define SLIDER(k, l, mn, mx) @{@"t": @"slider", @"key": k, @"label": l, @"min": @(mn), @"max": @(mx)}
#define NOTE(l) @{@"t": @"note", @"label": l}
#define COLOR(k, l) @{@"t": @"color", @"key": k, @"label": l, @"depValue": @[@"pref.darkTone", @7]}
#define NA(k, l, why) @{@"t": @"check", @"key": k, @"label": l, @"na": why}

+ (NSArray<NSDictionary *> *)pages {
    static NSArray *pages;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *encOpts = [NSMutableArray arrayWithArray:@[@"ANSI", @"UTF-8-BOM", @"UTF-16 Big Endian with BOM", @"UTF-16 Little Endian with BOM", @"UTF-8"]];
        NSMutableArray *langOpts = [NSMutableArray array], *langVals = [NSMutableArray array];
        for (TPLanguage *l in [TPLanguageService shared].languages) {
            if (!l.menuCommand || [l.langId isEqualToString:@"udf"]) continue;
            [langOpts addObject:l.shortName]; [langVals addObject:l.langId];
        }
        NSMutableArray *cpOpts = [NSMutableArray arrayWithObject:@"(none: use the encoding above)"], *cpVals = [NSMutableArray arrayWithObject:@(-1)];
        for (const auto &cp : tpp::codepageTable()) if (cp.codepage != 720) { [cpOpts addObject:@(cp.menuName)]; [cpVals addObject:@(cp.codepage)]; }
        pages = @[
            @{@"title": @"General", @"rows": @[
                GROUP(@"Localization"),
                @{@"t": @"popup", @"key": @"pref.localization", @"label": @"Language:", @"options": [TPLocalization shared].languageNames,
                  @"values": [TPLocalization shared].languageFiles, @"note": @"Menus and command names; dialogs stay in English"},
                GROUP(@"Menu"),
                CHECK(@"pref.inWindowMenu", @"Show a Windows-style menu bar inside the window (the macOS menu bar stays)"),
                CHECKX(@"pref.menuHidden", @"Hide (use ⌥ Option or F10 key to toggle)", @"dep": @"pref.inWindowMenu"),
                CHECKX(@"pref.hideRightShortcuts", @"Hide right shortcuts ＋ ▼ ✕", @"dep": @"pref.inWindowMenu"),
                GROUP(@"Status Bar"),
                CHECK(@"pref.statusBarHidden", @"Hide"),
                GROUP(@"Dialog Font (Need to restart)"),
                CHECK(@"pref.dialogFont", @"Use a custom dialog font"),
                TEXTFX(@"pref.dialogFontName", @"Font name (empty = system font):", @"dep": @"pref.dialogFont"),
                INTFX(@"pref.dialogFontSize", @"Size (0 = as designed):", 0, 24, @"dep": @"pref.dialogFont")]},
            @{@"title": @"Toolbar", @"rows": @[
                CHECK(@"pref.toolbarHidden", @"Hide"),
                RADIO(@"pref.toolbarIconSet", @"Icon set", (@[@"Fluent UI: small", @"Fluent UI: large", @"Filled Fluent UI: small", @"Filled Fluent UI: large", @"Standard icons: small", @"Colourful: small", @"Colourful: large"])),
                GROUP(@"Colorization"),
                RADIOX(@"pref.toolbarColorMode", @"Colorization (Fluent UI icons)", (@[@"Complete", @"Partial"]), @"depValueBelow": @[@"pref.toolbarIconSet", @4]),
                RADIOX(@"pref.toolbarColor", @"Color choice", (@[@"Red", @"Green", @"Blue", @"Purple", @"Cyan", @"Olive", @"Yellow", @"Default", @"System Accent", @"Custom"]),
                       @"depValueBelow": @[@"pref.toolbarIconSet", @4]),
                @{@"t": @"color", @"key": @"pref.toolbarCustomColor", @"label": @"Custom colour", @"depValue": @[@"pref.toolbarColor", @9], @"depValueBelow": @[@"pref.toolbarIconSet", @4]}]},
            @{@"title": @"Tab Bar", @"rows": @[
                CHECK(@"pref.tabHidden", @"Hide"),
                GROUP(@"Behavior"),
                CHECK(@"pref.tabVertical", @"Vertical"),
                CHECK(@"pref.tabMultiline", @"Multi-line"),
                CHECK(@"pref.tabLock", @"Lock (no drag and drop)"),
                CHECK(@"pref.tabDblClickClose", @"Double click to close document"),
                CHECK(@"pref.tabExitOnLast", @"Exit on close the last tab"),
                INTF(@"pref.tabMaxLabel", @"Max. tab label length (0 = no limit):", 0, 255),
                GROUP(@"Look & feel"),
                CHECK(@"pref.tabReduce", @"Reduce"),
                CHECK(@"pref.tabAltIcons", @"Alternate icons"),
                CHECK(@"pref.tabDrawInactive", @"Change inactive tab color"),
                CHECK(@"pref.tabOrangeBar", @"Draw a coloured bar on active tab"),
                CHECK(@"pref.tabShowClose", @"Show close button"),
                CHECK(@"pref.tabEnablePin", @"Enable pin tab feature"),
                CHECKX(@"pref.tabOnlyPinnedButton", @"Show only pinned button", @"dep": @"pref.tabEnablePin"),
                CHECK(@"pref.tabInactiveButtons", @"Show buttons on inactive tabs")]},
            @{@"title": @"Editing 1", @"rows": @[
                RADIO(@"pref.currentLineMode", @"Current Line Indicator", (@[@"None", @"Highlight Background", @"Frame"])),
                SLIDER(@"pref.currentLineFrameWidth", @"Frame width:", 1, 6),
                POPUP(@"pref.caretWidth", @"Caret width:", (@[@"0", @"1", @"2", @"3", @"Block", @"Block After"])),
                SLIDER(@"pref.caretBlink", @"Blink rate (ms, 0 = no blink):", 0, 2000),
                RADIO(@"pref.wrapIndentMode", @"Line Wrap", (@[@"Default", @"Aligned", @"Indent"])),
                CHECK(@"pref.smoothFont", @"Enable smooth font"),
                CHECK(@"pref.virtualSpace", @"Enable virtual space"),
                CHECK(@"pref.foldToggle", @"Make current level folding/unfolding commands toggleable"),
                CHECK(@"pref.rightClickKeepsSel", @"Keep selection when right-click outside of selection"),
                CHECK(@"pref.copyCutLine", @"Enable Copy/Cut Line without selection"),
                CHECK(@"pref.selFgCustom", @"Apply custom color to selected text foreground"),
                CHECK(@"pref.scrollBeyondLast", @"Enable scrolling beyond last line"),
                NA(@"pref.disableAdvScroll", @"Disable advanced scrolling feature due to touchpad issue", kNAPlatform),
                CHECK(@"pref.disableDragDrop", @"Disable selected text drag-and-drop")]},
            @{@"title": @"Editing 2", @"rows": @[
                GROUP(@"Multi-Editing"),
                CHECK(@"pref.multiEditing", @"Enable Multi-Editing (⌘+Mouse click/selection)"),
                CHECKX(@"pref.column2Multi", @"Enable Column Selection to Multi-Editing", @"dep": @"pref.multiEditing"),
                GROUP(@"EOL (CRLF)"),
                RADIO(@"pref.crlfPlain", @"Appearance", (@[@"Default", @"Plain Text"])),
                CHECK(@"pref.crlfCustomColor", @"Custom Color (uses the theme's White space symbol colour)"),
                GROUP(@"Non-Printing Characters"),
                RADIO(@"pref.npcCodepoint", @"Appearance", (@[@"Abbreviation", @"Codepoint"])),
                CHECK(@"pref.npcCustomColor", @"Custom Color (uses the theme's White space symbol colour)"),
                CHECK(@"pref.npcIncludeCC", @"Apply Appearance settings to C0, C1 & Unicode EOL"),
                CHECK(@"pref.npcNoInputC0", @"Prevent control character (C0 code) typing into document")]},
            @{@"title": @"Dark Mode", @"rows": @[
                RADIO(@"pref.darkMode", @"Mode", (@[@"Light mode", @"Dark mode", @"Follow macOS"])),
                RADIOX(@"pref.darkTone", @"Tones", (@[@"Black tone", @"Red tone", @"Green tone", @"Blue tone", @"Purple tone", @"Cyan tone", @"Olive tone", @"Customized tone"]),
                       @"depValueNot": @[@"pref.darkMode", @0]),
                GROUP(@"Customized tone colours"),
                COLOR(@"pref.darkCustom.background", @"Top"), COLOR(@"pref.darkCustom.pureBackground", @"Main"),
                COLOR(@"pref.darkCustom.softerBackground", @"Active"), COLOR(@"pref.darkCustom.hotBackground", @"Menu hot"),
                COLOR(@"pref.darkCustom.text", @"Text"), COLOR(@"pref.darkCustom.darkerText", @"Darker text"),
                COLOR(@"pref.darkCustom.disabledText", @"Disabled text"), COLOR(@"pref.darkCustom.linkText", @"Link"),
                COLOR(@"pref.darkCustom.edge", @"Edge"), COLOR(@"pref.darkCustom.hotEdge", @"Hot edge"),
                COLOR(@"pref.darkCustom.disabledEdge", @"Disabled edge"), COLOR(@"pref.darkCustom.errorBackground", @"Error")]},
            @{@"title": @"Margins/Border/Edge", @"rows": @[
                RADIO(@"pref.foldStyle", @"Fold Margin Style", (@[@"Simple", @"Arrow", @"Circle tree", @"Box tree", @"None"])),
                GROUP(@"Border"),
                SLIDER(@"pref.borderWidth", @"Border Width:", 0, 30),
                CHECK(@"pref.borderEdge", @"Draw an edge around the editor (off = \"No edge\")"),
                GROUP(@"Vertical Edge Settings"),
                CHECK(@"pref.edgeEnabled", @"Show vertical edge(s)"),
                TEXTFX(@"pref.edgeColumns", @"Columns (space separated, e.g. 80 120):", @"dep": @"pref.edgeEnabled"),
                CHECKX(@"pref.edgeBgMode", @"Background mode", @"dep": @"pref.edgeEnabled"),
                GROUP(@"Change History"),
                CHECK(@"pref.chMargin", @"Show in the margin"),
                CHECK(@"pref.chText", @"Show in the text"),
                GROUP(@"Line Number"),
                CHECK(@"pref.lineNumbers", @"Display"),
                @{@"t": @"radio", @"key": @"pref.lineNumDynamic", @"label": @"Width", @"options": @[@"Dynamic width", @"Constant width"], @"values": @[@1, @0], @"dep": @"pref.lineNumbers"},
                SLIDER(@"pref.padLeft", @"Padding left:", 0, 30),
                SLIDER(@"pref.padRight", @"Padding right:", 0, 30),
                SLIDER(@"pref.distractionFreeWidth", @"Distraction Free (text width: 3 = narrow … 9 = wide):", 3, 9),
                CHECK(@"pref.bookmarkMargin", @"Display bookmark")]},
            @{@"title": @"New Document", @"rows": @[
                @{@"t": @"radio", @"key": @"NewDocEOL", @"label": @"Format (Line ending)", @"options": @[@"Windows (CR LF)", @"Unix (LF)", @"Macintosh (CR)"], @"values": @[@0, @2, @1]},
                @{@"t": @"radio", @"key": @"NewDocUniMode", @"label": @"Encoding", @"options": encOpts, @"values": @[@0, @1, @2, @3, @4]},
                @{@"t": @"popup", @"key": @"NewDocCodepage", @"label": @"Other character set:", @"options": cpOpts, @"values": cpVals},
                CHECK(@"pref.openAnsiAsUtf8", @"Apply to opened ANSI files (pure ASCII files open as UTF-8)"),
                @{@"t": @"popup", @"key": @"pref.defaultLanguage", @"label": @"Default language:", @"options": langOpts, @"values": langVals},
                CHECK(@"pref.newDocOnStartup", @"Always open a new document in addition at startup"),
                CHECK(@"pref.firstLineAsTabName", @"Use the first line of document as untitled tab name")]},
            @{@"title": @"Default Directory", @"rows": @[
                RADIO(@"pref.defaultDirMode", @"Default Open/Save file Directory", (@[@"Follow current document", @"Remember last used directory", @"Use this folder:"])),
                @{@"t": @"path", @"key": @"pref.defaultDirPath", @"label": @"Folder:", @"depValue": @[@"pref.defaultDirMode", @2]},
                CHECK(@"pref.dropFolderOpenFiles", @"Open all files of folder instead of launching Folder as Workspace on folder dropping")]},
            @{@"title": @"Recent Files History", @"rows": @[
                CHECK(@"pref.recentDontCheck", @"Don't check at launch time"),
                INTF(@"RecentFilesMax", @"Max. number of entries (0 – 30):", 0, 30),
                CHECK(@"pref.recentInSubmenu", @"In Submenu"),
                RADIO(@"pref.recentDisplay", @"Display", (@[@"Only File Name", @"Full File Name Path", @"Customize Maximum Length:"])),
                INTFX(@"pref.recentCustomLength", @"Maximum length (1 – 259):", 1, 259, @"depValue": @[@"pref.recentDisplay", @2])]},
            @{@"title": @"File Association", @"rows": @[
                NOTE(@"macOS keeps file associations per content type (Finder > Get Info > Open with > Change All…)."),
                @{@"t": @"fileassoc", @"key": @"pref.fileAssocExts", @"label": @"Extensions (space separated):"}]},
            @{@"title": @"Language", @"rows": @[
                CHECK(@"pref.langMenuCompact", @"Make language menu compact"),
                @{@"t": @"langlist", @"key": @"pref.hiddenLanguages", @"label": @"Languages shown in the Language menu (uncheck to remove):"},
                CHECK(@"pref.sqlBackslash", @"Treat backslash as escape character for SQL")]},
            @{@"title": @"Indentation", @"rows": @[
                INTF(@"TabWidth", @"Default indent size:", 1, 64),
                RADIO(@"UseSpaces", @"Default indent using", (@[@"Tab character", @"Space character(s)"])),
                @{@"t": @"langindent", @"key": @"pref.langIndent", @"label": @"Per-language indent settings:"},
                CHECK(@"pref.backspaceUnindent", @"Backspace key unindents instead of removing single space"),
                RADIO(@"pref.autoIndent", @"Auto-indent", (@[@"None", @"Basic", @"Advanced"]))]},
            @{@"title": @"Highlighting", @"rows": @[
                GROUP(@"Style All Occurrences of Token"),
                CHECK(@"pref.markAllMatchCase", @"Match case"),
                CHECK(@"pref.markAllWholeWord", @"Match whole word only"),
                GROUP(@"Highlight Matching Tags"),
                GROUP(@"Highlight Matching Tags"),
                CHECK(@"pref.tagMatch", @"Enable"),
                CHECKX(@"pref.tagAttrs", @"Highlight tag attributes", @"dep": @"pref.tagMatch"),
                NA(@"pref.tagNonHtmlZone", @"Highlight comment/php/asp zone", @"Has no effect (the option is stored but never used)"),
                GROUP(@"Smart Highlighting"),
                CHECK(@"pref.smartHL", @"Enable"),
                CHECKX(@"pref.smartHLOtherView", @"Highlight another view", @"dep": @"pref.smartHL"),
                CHECKX(@"pref.smartHLMatchCase", @"Match case", @"dep": @"pref.smartHL"),
                CHECKX(@"pref.smartHLWholeWord", @"Match whole word only", @"dep": @"pref.smartHL"),
                CHECKX(@"pref.smartHLUseFind", @"Use Find dialog settings", @"dep": @"pref.smartHL")]},
            @{@"title": @"Print", @"rows": @[
                CHECK(@"pref.printLineNumbers", @"Print line number"),
                CHECK(@"pref.printFormfeed", @"Print formfeed as page break"),
                RADIO(@"pref.printColorMode", @"Color Options", (@[@"WYSIWYG", @"Invert", @"Black on white", @"No background color"])),
                GROUP(@"Margin Setting (Unit: mm, 0 = printer default)"),
                INTF(@"pref.printMarginTop", @"Top:", 0, 100), INTF(@"pref.printMarginLeft", @"Left:", 0, 100),
                INTF(@"pref.printMarginRight", @"Right:", 0, 100), INTF(@"pref.printMarginBottom", @"Bottom:", 0, 100),
                GROUP(@"Header and Footer — variables: $(FULL_CURRENT_PATH) $(FILE_NAME) $(SHORT_DATE) $(LONG_DATE) $(TIME) $(CURRENT_PRINTING_PAGE)"),
                TEXTF(@"pref.printHeaderLeft", @"Header left:"), TEXTF(@"pref.printHeaderMiddle", @"Header middle:"), TEXTF(@"pref.printHeaderRight", @"Header right:"),
                CHECK(@"pref.printHeaderBold", @"Header bold"), CHECK(@"pref.printHeaderItalic", @"Header italic"),
                TEXTF(@"pref.printFooterLeft", @"Footer left:"), TEXTF(@"pref.printFooterMiddle", @"Footer middle:"), TEXTF(@"pref.printFooterRight", @"Footer right:"),
                CHECK(@"pref.printFooterBold", @"Footer bold"), CHECK(@"pref.printFooterItalic", @"Footer italic"),
                INTF(@"pref.printHFSize", @"Header/footer font size:", 6, 24)]},
            @{@"title": @"Searching", @"rows": @[
                GROUP(@"When Find Dialog is Invoked"),
                INTF(@"pref.inSelThreshold", @"Minimum Size for Auto-Checking \"In selection\":", 0, 1000000),
                CHECK(@"pref.fifDirFromActive", @"Fill Find in Files Directory Field Based On Active Document"),
                CHECK(@"pref.fillFindWithSelection", @"Fill Find Field with Selected Text"),
                INTFX(@"pref.fillFindMaxChars", @"Max Characters to Auto-Fill Find Field from Selection:", 1, 16384, @"dep": @"pref.fillFindWithSelection"),
                CHECKX(@"pref.selectWordUnderCaret", @"Select Word Under Caret when Nothing Selected", @"dep": @"pref.fillFindWithSelection"),
                CHECK(@"pref.findMonospace", @"Use Monospaced font in Find dialog"),
                CHECK(@"pref.findDlgStaysOpen", @"Find dialog remains open after search that outputs to results window"),
                CHECK(@"pref.oneEntryPerLine", @"Search Result window: show only one entry per found line if possible"),
                CHECK(@"pref.fifPreferDisk", @"Find in Files: Prefer on-disk file content over open buffers")]},
            @{@"title": @"Backup", @"rows": @[
                GROUP(@"Session snapshot and periodic backup"),
                CHECK(@"RememberSession", @"Remember current session for next launch"),
                CHECKX(@"SessionSnapshot", @"Enable session snapshot and periodic backup", @"dep": @"RememberSession"),
                INTFX(@"BackupInterval", @"Trigger backup on modification in every (seconds):", 1, 3600, @"dep": @"SessionSnapshot"),
                @{@"t": @"note", @"label": @"Backup path: ~/Library/Application Support/Textpad++/backup"},
                CHECK(@"pref.keepAbsentFiles", @"Remember inaccessible files from past session"),
                RADIO(@"pref.backupOnSave", @"Backup on save", (@[@"None", @"Simple backup", @"Verbose backup"])),
                CHECK(@"pref.customBackupDirEnabled", @"Custom Backup Directory"),
                @{@"t": @"path", @"key": @"pref.customBackupDir", @"label": @"Directory:", @"dep": @"pref.customBackupDirEnabled"}]},
            @{@"title": @"Auto-Completion", @"rows": @[
                CHECK(@"pref.autocEnabled", @"Enable auto-completion on each input"),
                RADIOX(@"pref.autocMode", @"Completion source", (@[@"Function completion", @"Word completion", @"Function and word completion"]), @"dep": @"pref.autocEnabled"),
                CHECKX(@"pref.autocBrief", @"Make auto-completion list brief", @"dep": @"pref.autocEnabled"),
                CHECK(@"pref.funcParamHint", @"Function parameters hint on input"),
                INTFX(@"pref.autocFromLen", @"From the Nth character (1 – 9):", 1, 9, @"dep": @"pref.autocEnabled"),
                CHECKX(@"pref.autocInsertTab", @"Insert Selection: TAB", @"dep": @"pref.autocEnabled"),
                CHECKX(@"pref.autocInsertEnter", @"Insert Selection: ENTER", @"dep": @"pref.autocEnabled"),
                CHECKX(@"pref.autocIgnoreNumbers", @"Ignore numbers", @"dep": @"pref.autocEnabled"),
                GROUP(@"Auto-Insert"),
                CHECK(@"pref.pairParen", @"( )"), CHECK(@"pref.pairBracket", @"[ ]"), CHECK(@"pref.pairBrace", @"{ }"),
                CHECK(@"pref.pairQuote", @"\" \""), CHECK(@"pref.pairApos", @"' '"), CHECK(@"pref.pairHtmlTag", @"html/xml close tag"),
                TEXTF(@"pref.pair1Open", @"Matched pair 1 open:"), TEXTF(@"pref.pair1Close", @"Matched pair 1 close:"),
                TEXTF(@"pref.pair2Open", @"Matched pair 2 open:"), TEXTF(@"pref.pair2Close", @"Matched pair 2 close:"),
                TEXTF(@"pref.pair3Open", @"Matched pair 3 open:"), TEXTF(@"pref.pair3Close", @"Matched pair 3 close:")]},
            @{@"title": @"Multi-Instance & Date", @"rows": @[
                GROUP(@"Multi-instance settings"),
                @{@"t": @"radio", @"key": @"pref.multiInstance", @"label": @"",
                  @"options": @[@"Open session in a new instance (and save session on exit)", @"Always in multi-instance mode", @"Default (mono-instance)"],
                  @"values": @[@1, @2, @0]},
                GROUP(@"Customize insert Date Time"),
                CHECK(@"DateTimeReverseOrder", @"Reverse default date time order (short & long formats)"),
                TEXTF(@"DateTimeCustomFormat", @"Custom format (Unicode date pattern):"),
                GROUP(@"Panel State and [-nosession]"),
                NOTE(@"Remember panel state (panel is open) in other instances (multi-instance mode) or with [-nosession]:"),
                CHECK(@"pref.panelState.cliphistory", @"Clipboard History"), CHECK(@"pref.panelState.doclist", @"Document List"),
                CHECK(@"pref.panelState.charpanel", @"Character Panel"), CHECK(@"pref.panelState.faw", @"Folder as Workspace"),
                CHECK(@"pref.panelState.project", @"Project Panels"), CHECK(@"pref.panelState.docmap", @"Document Map"),
                CHECK(@"pref.panelState.funclist", @"Function List")]},
            @{@"title": @"Delimiter", @"rows": @[
                @{@"t": @"radio", @"key": @"pref.wordCharsDefault", @"label": @"Word character list", @"options": @[@"Use default Word character list as it is", @"Add your character as part of word"], @"values": @[@1, @0]},
                TEXTFX(@"pref.wordCharsCustom", @"Extra word characters:", @"depNot": @"pref.wordCharsDefault"),
                GROUP(@"Delimiter selection settings (⌘ + mouse double click)"),
                TEXTF(@"pref.delimOpen", @"Open:"), TEXTF(@"pref.delimClose", @"Close:"),
                CHECK(@"pref.delimMultiLine", @"Allow on several lines")]},
            @{@"title": @"Performance", @"rows": @[
                CHECK(@"pref.largeFileEnabled", @"Enable Large File Restriction (no syntax highlighting)"),
                INTFX(@"pref.largeFileMB", @"Define Large File Size (MB, 1 – 2046):", 1, 2046, @"dep": @"pref.largeFileEnabled"),
                CHECKX(@"pref.largeFileNoWrap", @"Deactivate Word Wrap globally", @"dep": @"pref.largeFileEnabled"),
                CHECKX(@"pref.largeFileAutoC", @"Allow Auto-Completion", @"dep": @"pref.largeFileEnabled"),
                CHECKX(@"pref.largeFileSmartHL", @"Allow Smart Highlighting", @"dep": @"pref.largeFileEnabled"),
                CHECKX(@"pref.largeFileBraceMatch", @"Allow Brace Match", @"dep": @"pref.largeFileEnabled"),
                CHECKX(@"pref.largeFileLinks", @"Allow URL Clickable Link", @"dep": @"pref.largeFileEnabled"),
                CHECK(@"pref.suppress2GB", @"Suppress warning when opening ≥2GB files")]},
            @{@"title": @"Cloud & Link", @"rows": @[
                GROUP(@"Settings on cloud"),
                @{@"t": @"path", @"key": @"pref.cloudPath", @"label": @"Set your cloud location path here (empty = no cloud):"},
                NOTE(@"Preferences, shortcuts.xml, themes, User Defined Languages and API files are kept in <path>/Textpad++. Restart Textpad++ to apply."),
                GROUP(@"Clickable Link Settings (⌘-click to open)"),
                CHECK(@"pref.links", @"Enable"),
                CHECKX(@"pref.linkNoUnderline", @"No underline", @"dep": @"pref.links"),
                CHECKX(@"pref.linkFullBox", @"Enable fullbox mode", @"dep": @"pref.links"),
                TEXTFX(@"pref.uriSchemes", @"URI customized schemes:", @"dep": @"pref.links")]},
            @{@"title": @"Search Engine", @"rows": @[
                RADIO(@"pref.searchEngine", @"Search Engine (for command \"Search on Internet\")", (@[@"DuckDuckGo", @"Google", @"Yahoo!", @"Stack Overflow", @"Set your search engine here:"])),
                TEXTFX(@"pref.searchEngineCustom", @"URL ($(CURRENT_WORD) = selection):", @"depValue": @[@"pref.searchEngine", @4]),
                NOTE(@"Example: https://www.google.com/search?q=$(CURRENT_WORD)")]},
            @{@"title": @"MISC.", @"rows": @[
                POPUP(@"pref.fileAutoDetect", @"File Status Auto-Detection:", (@[@"Enable for current file(s)", @"Enable for all opened files", @"Disable"])),
                CHECKX(@"pref.updateSilently", @"Update silently", @"depValueNot": @[@"pref.fileAutoDetect", @2]),
                CHECKX(@"pref.updateGotoEOF", @"Scroll to the last line after update", @"depValueNot": @[@"pref.fileAutoDetect", @2]),
                GROUP(@"Document Switcher (⌃Tab)"),
                CHECK(@"pref.docSwitcherMRU", @"Enable MRU behaviour"),
                GROUP(@"Document Peeker"),
                CHECK(@"pref.docPeekOnTab", @"Peek on tab"),
                CHECK(@"pref.docPeekOnMap", @"Peek on document map"),
                GROUP(@"Other"),
                POPUP(@"pref.systray", @"Menu bar extra (system tray):", (@[@"No action on", @"Minimize to", @"Close to", @"Minimize / Close to"])),
                NA(@"pref.rendering", @"Rendering mode", @"Scintilla on macOS has a single rendering technology (Core Graphics)"),
                CHECK(@"pref.autoUpdater", @"Enable Textpad++ auto-updater (checks every 15 days)"),
                CHECKX(@"pref.autoInstallUpdates", @"Install updates automatically (applied when Textpad++ quits)", @"dep": @"pref.autoUpdater"),
                CHECK(@"pref.muteSounds", @"Mute all sounds"),
                CHECK(@"pref.detectEncoding", @"Autodetect character encoding"),
                CHECK(@"pref.shortTitle", @"Show only filename in title bar"),
                CHECK(@"pref.saveAllConfirm", @"Enable Save All confirm dialog"),
                CHECK(@"pref.symlinksFaW", @"Allow loading symlinks in Folder as Workspace panel"),
                TEXTF(@"pref.sessionFileExt", @"Session file ext.:"),
                TEXTF(@"pref.workspaceFileExt", @"Workspace file ext.:")]},
            @{@"title": @"Textpad++ Features", @"rows": @[
                GROUP(@"Markdown"),
                POPUP(@"pref.markdownOpen", @"When a Markdown file opens:", (@[@"Ask every time", @"Open with Live Preview", @"Text only"])),
                GROUP(@"Look"),
                CHECK(@"pref.modernLook", @"Modern look: rounded tabs, unified title bar, macOS-style themes"),
                GROUP(@"Editing"),
                CHECK(@"pref.snippets", @"Snippets: type a trigger (for, def, html5...) and press Tab"),
                CHECK(@"pref.gitMarkers", @"Show Git changes (added, changed, deleted lines) in the margin"),
                CHECK(@"pref.csvRainbow", @"Colour each column of CSV / TSV files"),
                CHECK(@"pref.compareIgnoreSpaces", @"Compare: ignore spaces and tabs")]},
        ];
    });
    return pages;
}

@end

// ---------------------------------------------------------------- window
@interface TPFlippedView : NSView
@end
@implementation TPFlippedView
- (BOOL)isFlipped { return YES; }
@end

@implementation TPPreferencesWindow {
    NSTableView *_list;
    NSScrollView *_scroll;
    TPFlippedView *_page;
    NSInteger _pageIndex;
    NSMutableArray<NSDictionary *> *_bindings;   // {view, row}
    NSPopUpButton *_langIndentPopup;
    NSButton *_langIndentDefault, *_langIndentSpaces;
    NSTextField *_langIndentSize;
}

+ (instancetype)shared {
    static TPPreferencesWindow *w;
    if (!w) w = [TPPreferencesWindow new];
    return w;
}

- (instancetype)init {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 860, 560)
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                backing:NSBackingStoreBuffered defer:YES];
    if ((self = [super initWithWindow:w])) {
        w.title = @"Textpad++ Preferences";
        w.minSize = NSMakeSize(700, 420);
        NSScrollView *ls = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 50, 200, 500)];
        ls.autoresizingMask = NSViewHeightSizable;
        _list = [[NSTableView alloc] initWithFrame:ls.bounds];
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"t"];
        col.width = 190;
        [_list addTableColumn:col];
        _list.headerView = nil;
        _list.dataSource = self;
        _list.delegate = self;
        ls.documentView = _list;
        ls.hasVerticalScroller = YES;
        [w.contentView addSubview:ls];
        _scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(220, 50, 630, 500)];
        _scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _scroll.hasVerticalScroller = YES;
        _scroll.drawsBackground = NO;
        [w.contentView addSubview:_scroll];
        NSButton *close = [NSButton buttonWithTitle:@"Close" target:self action:@selector(closeIt:)];
        close.frame = NSMakeRect(760, 10, 90, 30);
        close.autoresizingMask = NSViewMinXMargin;
        close.keyEquivalent = @"\e";
        [w.contentView addSubview:close];
        _bindings = [NSMutableArray array];
        [_list reloadData];
        [_list selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [self buildPage:0];
    }
    return self;
}

- (void)closeIt:(id)s { [self.window orderOut:nil]; }
- (NSString *)currentPage { return TPPrefs.pages[_pageIndex][@"title"]; }

- (void)showPage:(NSString *)title {
    NSArray *pages = TPPrefs.pages;
    for (NSUInteger i = 0; i < pages.count; ++i)
        if ([pages[i][@"title"] isEqualToString:title]) {
            [_list selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            [self buildPage:(NSInteger)i];
        }
    if (!self.window.isVisible) [self.window center];
    [self showWindow:nil];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return (NSInteger)TPPrefs.pages.count; }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)r { return TPPrefs.pages[r][@"title"]; }
- (void)tableViewSelectionDidChange:(NSNotification *)n { if (_list.selectedRow >= 0) [self buildPage:_list.selectedRow]; }

// ---------------------------------------------------------------- page building
- (BOOL)rowEnabled:(NSDictionary *)row {
    if (row[@"na"]) return NO;
    if (row[@"dep"] && ![TPPrefs b:row[@"dep"]]) return NO;
    if (row[@"depNot"] && [TPPrefs b:row[@"depNot"]]) return NO;
    if (row[@"depValue"]) { NSArray *dv = row[@"depValue"]; if ([TPPrefs i:dv[0]] != [dv[1] integerValue]) return NO; }
    if (row[@"depValueNot"]) { NSArray *dv = row[@"depValueNot"]; if ([TPPrefs i:dv[0]] == [dv[1] integerValue]) return NO; }
    if (row[@"depValueBelow"]) { NSArray *dv = row[@"depValueBelow"]; if ([TPPrefs i:dv[0]] >= [dv[1] integerValue]) return NO; }
    return YES;
}

- (void)buildPage:(NSInteger)index {
    _pageIndex = index;
    [_bindings removeAllObjects];
    _page = [[TPFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 600, 100)];
    CGFloat y = 8;
    NSArray *rows = TPPrefs.pages[index][@"rows"];
    NSTextField *title = [NSTextField labelWithString:TPPrefs.pages[index][@"title"]];
    title.font = [NSFont boldSystemFontOfSize:15];
    title.frame = NSMakeRect(8, y, 580, 22);
    [_page addSubview:title];
    y += 32;
    for (NSDictionary *row in rows) y = [self addRow:row atY:y];
    _page.frame = NSMakeRect(0, 0, 600, y + 20);
    _scroll.documentView = _page;
    [_page scrollPoint:NSZeroPoint];
    [self refreshEnabled];
}

- (NSTextField *)label:(NSString *)s x:(CGFloat)x y:(CGFloat)y w:(CGFloat)w {
    NSTextField *l = [NSTextField wrappingLabelWithString:s];
    l.frame = NSMakeRect(x, y + 2, w, 18);
    [_page addSubview:l];
    return l;
}

- (void)bind:(NSView *)v row:(NSDictionary *)row { [_bindings addObject:@{@"view": v, @"row": row}]; }

- (CGFloat)addRow:(NSDictionary *)row atY:(CGFloat)y {
    NSString *t = row[@"t"], *key = row[@"key"], *label = row[@"label"];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    CGFloat x = 24;
    if ([t isEqualToString:@"group"]) {
        NSTextField *g = [self label:label x:8 y:y + 4 w:580];
        g.font = [NSFont boldSystemFontOfSize:12];
        return y + 28;
    }
    if ([t isEqualToString:@"note"]) {
        NSTextField *n = [self label:label x:x y:y w:560];
        n.textColor = NSColor.secondaryLabelColor;
        return y + 24;
    }
    if ([t isEqualToString:@"check"]) {
        NSButton *b = [NSButton checkboxWithTitle:label target:self action:@selector(changed:)];
        b.frame = NSMakeRect(x, y, 560, 20);
        b.state = row[@"na"] ? NSControlStateValueOff : ([ud boolForKey:key] ? NSControlStateValueOn : NSControlStateValueOff);
        if (row[@"na"]) b.toolTip = row[@"na"], b.title = [label stringByAppendingFormat:@"  — %@", row[@"na"]];
        [_page addSubview:b];
        [self bind:b row:row];
        return y + 24;
    }
    if ([t isEqualToString:@"radio"]) {
        [self label:label x:x y:y w:560].font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
        y += 22;
        NSArray *opts = row[@"options"], *vals = row[@"values"];
        NSInteger cur = [ud integerForKey:key];
        for (NSUInteger i = 0; i < opts.count; ++i) {
            NSInteger v = vals ? [vals[i] integerValue] : (NSInteger)i;
            NSButton *b = [NSButton radioButtonWithTitle:opts[i] target:self action:@selector(changed:)];
            b.frame = NSMakeRect(x + 16, y, 540, 20);
            b.tag = v;
            b.state = cur == v ? NSControlStateValueOn : NSControlStateValueOff;
            [_page addSubview:b];
            [self bind:b row:row];
            y += 22;
        }
        return y + 4;
    }
    if ([t isEqualToString:@"popup"]) {
        [self label:label x:x y:y w:230];
        NSPopUpButton *p = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x + 236, y - 2, 300, 26)];
        [p addItemsWithTitles:row[@"options"]];
        NSArray *vals = row[@"values"];
        id cur = [ud objectForKey:key];
        if (vals) { NSUInteger i = [vals indexOfObject:cur]; if (i != NSNotFound) [p selectItemAtIndex:i]; }
        else [p selectItemAtIndex:MAX(0, MIN((NSInteger)p.numberOfItems - 1, [cur integerValue]))];
        p.target = self; p.action = @selector(changed:);
        [_page addSubview:p];
        [self bind:p row:row];
        return y + 30;
    }
    if ([t isEqualToString:@"int"] || [t isEqualToString:@"text"] || [t isEqualToString:@"path"]) {
        [self label:label x:x y:y w:300];
        BOOL isInt = [t isEqualToString:@"int"];
        NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(x + 306, y, isInt ? 90 : 230, 22)];
        f.stringValue = isInt ? [@([ud integerForKey:key]) stringValue] : ([ud stringForKey:key] ?: @"");
        f.target = self; f.action = @selector(changed:);
        f.identifier = key;
        [_page addSubview:f];
        [self bind:f row:row];
        if ([t isEqualToString:@"path"]) {
            NSButton *b = [NSButton buttonWithTitle:@"..." target:self action:@selector(choosePath:)];
            b.frame = NSMakeRect(x + 540, y - 3, 34, 28);
            b.identifier = key;
            [_page addSubview:b];
            [self bind:b row:row];
        }
        return y + 28;
    }
    if ([t isEqualToString:@"color"]) {
        [self label:label x:x y:y w:200];
        NSColorWell *w = [[NSColorWell alloc] initWithFrame:NSMakeRect(x + 206, y - 2, 44, 24)];
        unsigned v = 0;
        [[NSScanner scannerWithString:[ud stringForKey:key] ?: @"000000"] scanHexInt:&v];
        w.color = [NSColor colorWithSRGBRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:1];
        w.target = self; w.action = @selector(changed:);
        [_page addSubview:w];
        [self bind:w row:row];
        return y + 28;
    }
    if ([t isEqualToString:@"slider"]) {
        [self label:label x:x y:y w:230];
        NSSlider *s = [NSSlider sliderWithValue:[ud integerForKey:key] minValue:[row[@"min"] doubleValue] maxValue:[row[@"max"] doubleValue] target:self action:@selector(changed:)];
        s.frame = NSMakeRect(x + 236, y, 220, 22);
        s.continuous = NO;
        [_page addSubview:s];
        [self bind:s row:row];
        NSTextField *v = [self label:[@([ud integerForKey:key]) stringValue] x:x + 464 y:y w:60];
        v.identifier = [key stringByAppendingString:@".value"];
        return y + 28;
    }
    if ([t isEqualToString:@"langlist"]) {
        [self label:label x:x y:y w:560];
        y += 22;
        NSArray *hidden = [ud arrayForKey:key] ?: @[];
        NSView *box = [[TPFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 540, 10)];
        CGFloat by = 0;
        NSInteger col = 0;
        for (TPLanguage *l in [TPLanguageService shared].languages) {
            if (!l.menuCommand || [l.langId isEqualToString:@"udf"] || [l.langId isEqualToString:@"normal"]) continue;
            NSButton *b = [NSButton checkboxWithTitle:l.shortName target:self action:@selector(langListChanged:)];
            b.frame = NSMakeRect(col * 180, by, 176, 20);
            b.identifier = l.langId;
            b.state = [hidden containsObject:l.langId] ? NSControlStateValueOff : NSControlStateValueOn;
            [box addSubview:b];
            if (++col == 3) { col = 0; by += 22; }
        }
        box.frame = NSMakeRect(0, 0, 540, by + 24);
        NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(x, y, 556, 200)];
        sv.documentView = box;
        sv.hasVerticalScroller = YES;
        sv.borderType = NSBezelBorder;
        [_page addSubview:sv];
        return y + 208;
    }
    if ([t isEqualToString:@"fileassoc"]) {
        [self label:label x:x y:y w:200];
        NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(x + 206, y, 200, 22)];
        f.stringValue = [ud stringForKey:key] ?: @"";
        f.target = self; f.action = @selector(changed:);
        [_page addSubview:f];
        [self bind:f row:@{@"t": @"text", @"key": key}];
        NSButton *b = [NSButton buttonWithTitle:@"Make Textpad++ the default app" target:self action:@selector(associate:)];
        b.frame = NSMakeRect(x, y + 30, 260, 28);
        [_page addSubview:b];
        NSTextField *status = [self label:@"" x:x + 268 y:y + 34 w:300];
        status.identifier = @"assoc.status";
        return y + 66;
    }
    if ([t isEqualToString:@"langindent"]) {
        [self label:label x:x y:y w:560];
        y += 24;
        _langIndentPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, y, 220, 26)];
        for (TPLanguage *l in [TPLanguageService shared].languages) {
            if (!l.menuCommand || [l.langId isEqualToString:@"udf"]) continue;
            [_langIndentPopup addItemWithTitle:l.shortName];
            _langIndentPopup.lastItem.representedObject = l.langId;
        }
        _langIndentPopup.target = self; _langIndentPopup.action = @selector(langIndentSelect:);
        _langIndentDefault = [NSButton checkboxWithTitle:@"Use default value" target:self action:@selector(langIndentChanged:)];
        _langIndentDefault.frame = NSMakeRect(x + 230, y + 2, 150, 20);
        _langIndentSize = [[NSTextField alloc] initWithFrame:NSMakeRect(x + 384, y + 1, 40, 22)];
        _langIndentSize.target = self; _langIndentSize.action = @selector(langIndentChanged:);
        _langIndentSpaces = [NSButton checkboxWithTitle:@"Spaces" target:self action:@selector(langIndentChanged:)];
        _langIndentSpaces.frame = NSMakeRect(x + 430, y + 2, 100, 20);
        for (NSView *v in @[_langIndentPopup, _langIndentDefault, _langIndentSize, _langIndentSpaces]) [_page addSubview:v];
        [self langIndentSelect:nil];
        return y + 34;
    }
    return y;
}

- (void)refreshEnabled {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    for (NSDictionary *b in _bindings) {
        NSControl *v = b[@"view"];
        NSDictionary *row = b[@"row"];
        v.enabled = [self rowEnabled:row];
        if ([row[@"t"] isEqualToString:@"radio"]) ((NSButton *)v).state = [ud integerForKey:row[@"key"]] == v.tag ? NSControlStateValueOn : NSControlStateValueOff;
    }
    BOOL def = _langIndentDefault.state == NSControlStateValueOn;
    _langIndentSize.enabled = !def;
    _langIndentSpaces.enabled = !def;
}

- (NSDictionary *)rowForView:(NSView *)v {
    for (NSDictionary *b in _bindings) if (b[@"view"] == v) return b[@"row"];
    return nil;
}

- (void)changed:(NSControl *)sender {
    NSDictionary *row = [self rowForView:sender];
    if (!row || row[@"na"]) return;
    NSString *t = row[@"t"], *key = row[@"key"];
    id value = nil;
    if ([t isEqualToString:@"check"]) value = @(((NSButton *)sender).state == NSControlStateValueOn);
    else if ([t isEqualToString:@"radio"]) value = @(sender.tag);
    else if ([t isEqualToString:@"popup"]) {
        NSInteger i = ((NSPopUpButton *)sender).indexOfSelectedItem;
        value = row[@"values"] ? row[@"values"][i] : @(i);
    } else if ([t isEqualToString:@"int"]) {
        NSInteger v = MAX([row[@"min"] integerValue], MIN([row[@"max"] integerValue], sender.integerValue));
        sender.stringValue = [@(v) stringValue];
        value = @(v);
    } else if ([t isEqualToString:@"slider"]) {
        value = @(lround(sender.doubleValue));
        for (NSView *sv in _page.subviews)
            if ([sv.identifier isEqualToString:[key stringByAppendingString:@".value"]]) ((NSTextField *)sv).stringValue = [value stringValue];
    } else if ([t isEqualToString:@"color"]) {
        NSColor *c = [((NSColorWell *)sender).color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        auto ch = [](CGFloat x) { return static_cast<int>(MAX(0.0, MIN(1.0, x)) * 255.0 + 0.5); };
        value = [NSString stringWithFormat:@"%02X%02X%02X", ch(c.redComponent), ch(c.greenComponent), ch(c.blueComponent)];
    } else value = sender.stringValue ?: @"";
    // "radio" rows bound to BOOL keys (e.g. UseSpaces, wordCharsDefault) store 0/1, which reads back as BOOL
    [TPPrefs set:value forKey:key];
    [self refreshEnabled];
}

// Preferences > File Association: register Textpad++ as the default app for the listed extensions
// (NSWorkspace / LaunchServices; the user's choice, applied per content type).
- (void)associate:(id)sender {
    NSURL *app = [NSBundle mainBundle].bundleURL;
    __block NSInteger ok = 0, failed = 0, pending = 0;
    NSTextField *status = nil;
    for (NSView *v in _page.subviews) if ([v.identifier isEqualToString:@"assoc.status"]) status = (NSTextField *)v;
    for (NSString *ext in [[TPPrefs s:@"pref.fileAssocExts"] componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) {
        if (!ext.length) continue;
        UTType *type = [UTType typeWithFilenameExtension:[ext stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"."]]];
        if (!type) { ++failed; continue; }
        ++pending;
        [[NSWorkspace sharedWorkspace] setDefaultApplicationAtURL:app toOpenContentType:type completionHandler:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) ++failed; else ++ok;
                if (--pending == 0) status.stringValue = [NSString stringWithFormat:@"%ld associated, %ld failed", (long)ok, (long)failed];
            });
        }];
    }
    if (!pending) status.stringValue = failed ? @"No valid extensions" : @"Nothing to do";
}

- (void)choosePath:(NSButton *)sender {
    NSOpenPanel *op = [NSOpenPanel openPanel];
    op.canChooseDirectories = YES;
    op.canChooseFiles = NO;
    if ([op runModal] != NSModalResponseOK) return;
    [TPPrefs set:op.URL.path forKey:sender.identifier];
    for (NSView *v in _page.subviews)
        if ([v isKindOfClass:[NSTextField class]] && [v.identifier isEqualToString:sender.identifier]) ((NSTextField *)v).stringValue = op.URL.path;
}

- (void)langListChanged:(NSButton *)sender {
    NSMutableArray *hidden = [[[NSUserDefaults standardUserDefaults] arrayForKey:@"pref.hiddenLanguages"] mutableCopy] ?: [NSMutableArray array];
    [hidden removeObject:sender.identifier];
    if (sender.state == NSControlStateValueOff) [hidden addObject:sender.identifier];
    [TPPrefs set:hidden forKey:@"pref.hiddenLanguages"];
}

- (void)langIndentSelect:(id)sender {
    NSString *lid = _langIndentPopup.selectedItem.representedObject;
    NSDictionary *d = [TPPrefs o:@"pref.langIndent"][lid];
    BOOL useDefault = !d || [d[@"useDefault"] boolValue];
    _langIndentDefault.state = useDefault ? NSControlStateValueOn : NSControlStateValueOff;
    _langIndentSize.stringValue = [@([TPPrefs tabSizeForLanguage:lid]) stringValue];
    _langIndentSpaces.state = [TPPrefs useSpacesForLanguage:lid] ? NSControlStateValueOn : NSControlStateValueOff;
    [self refreshEnabled];
}

- (void)langIndentChanged:(id)sender {
    NSString *lid = _langIndentPopup.selectedItem.representedObject;
    NSMutableDictionary *all = [[TPPrefs o:@"pref.langIndent"] mutableCopy] ?: [NSMutableDictionary dictionary];
    all[lid] = @{@"useDefault": @(_langIndentDefault.state == NSControlStateValueOn),
                 @"size": @(MAX(1, MIN(64, _langIndentSize.integerValue))),
                 @"spaces": @(_langIndentSpaces.state == NSControlStateValueOn)};
    [TPPrefs set:all forKey:@"pref.langIndent"];
    [self refreshEnabled];
}

@end

// ---------------------------------------------------------------- Preferences > General > Dialog Font
// applied to every Textpad++ window except the editor window when it is shown (upstream: at dialog creation)
void TPApplyDialogFont(NSWindow *w) {
    if (![TPPrefs b:@"pref.dialogFont"] || !w) return;
    NSString *name = [TPPrefs s:@"pref.dialogFontName"];
    const NSInteger size = [TPPrefs i:@"pref.dialogFontSize"];
    std::function<void(NSView *)> walk = [&](NSView *v) {
        if ([NSStringFromClass(v.class) hasPrefix:@"SCI"] || [NSStringFromClass(v.class) isEqualToString:@"ScintillaView"]) return;
        if ([v isKindOfClass:NSControl.class] && [(NSControl *)v font]) {
            NSControl *c = (NSControl *)v;
            const CGFloat pt = size > 0 ? size : c.font.pointSize;
            NSFont *f = name.length ? [NSFont fontWithName:name size:pt] : [NSFont systemFontOfSize:pt];
            if (f) c.font = f;
        }
        for (NSView *sub in v.subviews) walk(sub);
    };
    walk(w.contentView);
}
