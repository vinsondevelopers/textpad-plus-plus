// Textpad++ — Tools (hash), Macro, Run, Window, Settings, Plugins and ? menu commands.
// GPL-3.0-or-later.
#import "app/MainWindowController.h"
#import <objc/runtime.h>
#import "dialogs/StyleConfigurator.h"
#import "app/CommandLine.h"
#import "dialogs/ShortcutMapper.h"
#import "commands/ScintillaKeys.h"
#import "plugins/PluginHost.h"
#import "app/LanguageService.h"
#import "app/Session.h"
#import "app/ToolbarView.h"
#import "app/Preferences.h"
#include <sys/sysctl.h>
#include "core/Hashing.h"
#include "core/Encoding.h"
#include <vector>
#include <objc/runtime.h>

using namespace npp;

// ---------------------------------------------------------------- macro model (upstream MacroStep)
struct TPMacroStep {
    int type = 0;            // 0 Scintilla msg (int params), 1 Scintilla msg (string param), 2 menu command
    int message = 0;
    uptr_t wParam = 0;
    sptr_t lParam = 0;
    std::string sParam;
};
struct TPMacro {
    std::string name;
    std::vector<TPMacroStep> steps;
    std::string folder;                       // FolderName: Macro menu sub-menu
    NSDictionary *__strong shortcut = nil;    // Ctrl / Alt / Shift / Key (+ Control) as in shortcuts.xml
};

static BOOL g_recording = NO;
static std::vector<TPMacroStep> g_current;
static std::vector<TPMacro> g_savedMacros;
static BOOL g_macrosLoaded = NO;
static NSMutableArray<NSDictionary *> *g_runCommands;   // {name, command, folder, shortcut}

static NSString *supportFile(NSString *name) {
    // settings files follow Preferences > Cloud & Link; plug-ins stay on this Mac
    NSString *dir = [name isEqualToString:@"plugins"] ? [TPSession shared].supportDirectory : [TPSession shared].settingsDirectory;
    return [dir stringByAppendingPathComponent:name];
}

static BOOL isStringMessage(int m) {
    return m == SCI_REPLACESEL || m == SCI_INSERTTEXT || m == SCI_ADDTEXT || m == SCI_APPENDTEXT || m == SCI_SEARCHNEXT || m == SCI_SEARCHPREV;
}

// Menu commands that are recorded (upstream records edit/search/format commands, not dialogs or file I/O)
static BOOL isRecordable(int cmd) {
    if (cmd >= IDM_EDIT && cmd < IDM_EDIT + 1000) return cmd != IDM_EDIT_COLUMNMODE && cmd != IDM_EDIT_COLUMNMODETIP && cmd != IDM_EDIT_CHAR_PANEL && cmd != IDM_EDIT_CLIPBOARDHISTORY_PANEL;
    if (cmd >= IDM_SEARCH && cmd < IDM_SEARCH + 1000) return cmd != IDM_SEARCH_FIND && cmd != IDM_SEARCH_REPLACE && cmd != IDM_SEARCH_FINDINFILES && cmd != IDM_SEARCH_MARK && cmd != IDM_SEARCH_GOTOLINE;
    if (cmd == IDM_FORMAT_TODOS || cmd == IDM_FORMAT_TOUNIX || cmd == IDM_FORMAT_TOMAC) return YES;
    if (cmd == IDM_FILE_SAVE || cmd == IDM_FILE_SAVEALL) return YES;
    return NO;
}

static NSDictionary *shortcutAttributes(NSXMLElement *e) {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *k in @[@"Ctrl", @"Alt", @"Shift", @"Key", @"Control"]) if (NSString *v = [[e attributeForName:k] stringValue]) d[k] = v;
    return d;
}

// upstream SHORTCUT_XML_CONTENT (NppConstants.h): the default macro and Run commands with their shortcuts
static NSString *const kDefaultShortcutsXml = @"<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n<NotepadPlus>\n<InternalCommands />\n<Macros>\n"
    "<Macro name=\"Trim Trailing Space and Save\" Ctrl=\"no\" Alt=\"yes\" Shift=\"yes\" Key=\"83\">\n"
    "<Action type=\"2\" message=\"0\" wParam=\"42024\" lParam=\"0\" sParam=\"\" />\n"
    "<Action type=\"2\" message=\"0\" wParam=\"41006\" lParam=\"0\" sParam=\"\" />\n</Macro>\n</Macros>\n<UserDefinedCommands>\n"
    "<Command name=\"Get PHP help\" Ctrl=\"no\" Alt=\"yes\" Shift=\"no\" Key=\"112\">https://www.php.net/$(CURRENT_WORD)</Command>\n"
    "<Command name=\"Wikipedia Search\" Ctrl=\"no\" Alt=\"yes\" Shift=\"no\" Key=\"114\">https://en.wikipedia.org/wiki/Special:Search?search=$(CURRENT_WORD)</Command>\n"
    "<Command name=\"Open selected file path in new instance\" Ctrl=\"no\" Alt=\"yes\" Shift=\"no\" Key=\"117\">$(NPP_FULL_FILE_PATH) $(CURRENT_WORD) -nosession -multiInst</Command>\n"
    "</UserDefinedCommands>\n<PluginCommands />\n<ScintillaKeys />\n</NotepadPlus>\n";

static NSXMLDocument *g_shortcutsDoc;   // parsed shortcuts.xml (applied by -applyShortcutsXml)
extern "C" NSXMLDocument *TPCurrentShortcutsXml(void) { return g_shortcutsDoc; }

static void loadShortcutsXml() {
    if (g_macrosLoaded) return;
    g_macrosLoaded = YES;
    g_runCommands = [NSMutableArray array];
    g_savedMacros.clear();
    NSString *path = supportFile(@"shortcuts.xml");
    NSXMLDocument *doc = [[NSFileManager defaultManager] fileExistsAtPath:path]
        ? [[NSXMLDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] options:0 error:nil] : nil;
    if (!doc) doc = [[NSXMLDocument alloc] initWithXMLString:kDefaultShortcutsXml options:0 error:nil];
    g_shortcutsDoc = doc;
    for (NSXMLElement *me in [doc nodesForXPath:@"//Macros/Macro" error:nil]) {
        TPMacro m;
        m.name = StdStr([[me attributeForName:@"name"] stringValue]);
        m.folder = StdStr([[me attributeForName:@"FolderName"] stringValue]);
        m.shortcut = shortcutAttributes(me);
        for (NSXMLElement *a in [me elementsForName:@"Action"]) {
            TPMacroStep s;
            s.type = [[[a attributeForName:@"type"] stringValue] intValue];
            s.message = [[[a attributeForName:@"message"] stringValue] intValue];
            s.wParam = static_cast<uptr_t>([[[a attributeForName:@"wParam"] stringValue] longLongValue]);
            s.lParam = static_cast<sptr_t>([[[a attributeForName:@"lParam"] stringValue] longLongValue]);
            s.sParam = StdStr([[a attributeForName:@"sParam"] stringValue]);
            m.steps.push_back(s);
        }
        g_savedMacros.push_back(m);
    }
    for (NSXMLElement *ce in [doc nodesForXPath:@"//UserDefinedCommands/Command" error:nil]) {
        NSString *name = [[ce attributeForName:@"name"] stringValue] ?: @"";
        [g_runCommands addObject:@{@"name": name, @"command": ce.stringValue ?: @"",
                                   @"folder": [[ce attributeForName:@"FolderName"] stringValue] ?: @"", @"shortcut": shortcutAttributes(ce)}];
    }
}

static void addAttributes(NSXMLElement *e, NSDictionary *attrs) {
    for (NSString *k in @[@"Ctrl", @"Alt", @"Shift", @"Key", @"Control"])
        if (attrs[k]) [e addAttribute:[NSXMLNode attributeWithName:k stringValue:attrs[k]]];
}

static BOOL saveShortcutsXml(NSString **error) {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    NSXMLElement *root = [NSXMLElement elementWithName:@"NotepadPlus"];
    NSXMLElement *internal = [NSXMLElement elementWithName:@"InternalCommands"];
    for (NSNumber *n in reg.userBoundCommands) {
        int cmd = n.intValue;
        if ((cmd >= TP_ID_MACRO && cmd <= TP_ID_MACRO_LIMIT) || (cmd >= TP_ID_USER_CMD && cmd <= TP_ID_USER_CMD_LIMIT)) continue;
        if (cmd >= TP_ID_PLUGINS_CMD && cmd <= TP_ID_PLUGINS_CMD_DYNAMIC_LIMIT) continue;   // <PluginCommands>, by module
        NSXMLElement *sc = [NSXMLElement elementWithName:@"Shortcut"];
        [sc addAttribute:[NSXMLNode attributeWithName:@"id" stringValue:[n stringValue]]];
        addAttributes(sc, [reg upstreamAttributesForBinding:[reg userBindingForCommand:cmd]]);
        [internal addChild:sc];
    }
    [root addChild:internal];
    NSXMLElement *macros = [NSXMLElement elementWithName:@"Macros"];
    for (size_t i = 0; i < g_savedMacros.size(); ++i) {
        const TPMacro &m = g_savedMacros[i];
        NSXMLElement *me = [NSXMLElement elementWithName:@"Macro"];
        [me addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:NSStr(m.name)]];
        addAttributes(me, [reg upstreamAttributesForBinding:[reg userBindingForCommand:TP_ID_MACRO + static_cast<int>(i)]]);
        if (!m.folder.empty()) [me addAttribute:[NSXMLNode attributeWithName:@"FolderName" stringValue:NSStr(m.folder)]];
        for (const TPMacroStep &s : m.steps) {
            NSXMLElement *a = [NSXMLElement elementWithName:@"Action"];
            [a addAttribute:[NSXMLNode attributeWithName:@"type" stringValue:[@(s.type) stringValue]]];
            [a addAttribute:[NSXMLNode attributeWithName:@"message" stringValue:[@(s.message) stringValue]]];
            [a addAttribute:[NSXMLNode attributeWithName:@"wParam" stringValue:[@(s.wParam) stringValue]]];
            [a addAttribute:[NSXMLNode attributeWithName:@"lParam" stringValue:[@(s.lParam) stringValue]]];
            [a addAttribute:[NSXMLNode attributeWithName:@"sParam" stringValue:NSStr(s.sParam)]];
            [me addChild:a];
        }
        [macros addChild:me];
    }
    [root addChild:macros];
    NSXMLElement *cmds = [NSXMLElement elementWithName:@"UserDefinedCommands"];
    for (NSUInteger i = 0; i < g_runCommands.count; ++i) {
        NSDictionary *c = g_runCommands[i];
        NSXMLElement *ce = [NSXMLElement elementWithName:@"Command" stringValue:c[@"command"]];
        [ce addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:c[@"name"]]];
        addAttributes(ce, [reg upstreamAttributesForBinding:[reg userBindingForCommand:TP_ID_USER_CMD + static_cast<int>(i)]]);
        if ([c[@"folder"] length]) [ce addAttribute:[NSXMLNode attributeWithName:@"FolderName" stringValue:c[@"folder"]]];
        [cmds addChild:ce];
    }
    [root addChild:cmds];
    NSXMLElement *plugins = [NSXMLElement elementWithName:@"PluginCommands"];
    [[TPPluginHost shared] writeShortcutsTo:plugins];
    [root addChild:plugins];
    NSXMLElement *sk = [NSXMLElement elementWithName:@"ScintillaKeys"];
    for (NSNumber *msg in [TPScintillaKeys shared].userBoundMessages) {
        NSXMLElement *k = [NSXMLElement elementWithName:@"ScintKey"];
        [k addAttribute:[NSXMLNode attributeWithName:@"ScintID" stringValue:[msg stringValue]]];
        [k addAttribute:[NSXMLNode attributeWithName:@"menuCmdID" stringValue:@"0"]];
        addAttributes(k, [reg upstreamAttributesForBinding:[[TPScintillaKeys shared] userBindingForMessage:msg.intValue]]);
        [sk addChild:k];
    }
    [root addChild:sk];
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement:root];
    doc.characterEncoding = @"UTF-8";
    NSData *d = [doc XMLDataWithOptions:NSXMLNodePrettyPrint];
    std::string bytes(static_cast<const char *>(d.bytes), d.length);
    [[NSFileManager defaultManager] createDirectoryAtPath:[TPSession shared].settingsDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    return TPSafeWriteFile(supportFile(@"shortcuts.xml"), bytes, error);
}

// ---------------------------------------------------------------- hash dialog
@interface TPHashDialog : NSWindowController
@property (nonatomic) tpp::HashAlgorithm algorithm;
@end
@implementation TPHashDialog {
    NSTextView *_input, *_output;
    NSButton *_perLine;
}
- (instancetype)initWithAlgorithm:(tpp::HashAlgorithm)a {
    NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 620, 420) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:YES];
    if ((self = [super initWithWindow:p])) {
        _algorithm = a;
        p.title = [NSString stringWithFormat:@"Generate %s digest", tpp::hashName(a)];
        NSView *cv = p.contentView;
        NSScrollView *s1 = [NSTextView scrollableTextView], *s2 = [NSTextView scrollableTextView];
        s1.frame = NSMakeRect(12, 240, 596, 150); s2.frame = NSMakeRect(12, 50, 596, 150);
        s1.autoresizingMask = s2.autoresizingMask = NSViewWidthSizable;
        _input = s1.documentView; _output = s2.documentView;
        _input.font = _output.font = [NSFont userFixedPitchFontOfSize:12];
        _input.richText = _output.richText = NO;
        _output.editable = NO;
        _perLine = [NSButton checkboxWithTitle:@"Treat each line as a separate string" target:self action:@selector(update:)];
        _perLine.frame = NSMakeRect(12, 208, 400, 20);
        NSTextField *l = [NSTextField labelWithString:@"Text:"]; l.frame = NSMakeRect(12, 394, 200, 18);
        NSButton *copy = [NSButton buttonWithTitle:@"Copy to Clipboard" target:self action:@selector(copyOut:)];
        copy.frame = NSMakeRect(318, 10, 150, 30);
        NSButton *close = [NSButton buttonWithTitle:@"Close" target:self action:@selector(closeIt:)];
        close.frame = NSMakeRect(478, 10, 130, 30);
        for (NSView *v in @[l, s1, _perLine, s2, copy, close]) [cv addSubview:v];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(update:) name:NSTextDidChangeNotification object:_input];
    }
    return self;
}
- (void)update:(id)sender {
    std::string text = StdStr(_input.string);
    std::string out;
    if (_perLine.state == NSControlStateValueOn) {
        size_t start = 0;
        while (start <= text.size()) {
            size_t nl = text.find('\n', start);
            std::string line = text.substr(start, nl == std::string::npos ? std::string::npos : nl - start);
            if (!line.empty() && line.back() == '\r') line.pop_back();
            if (!line.empty()) out += tpp::hashHex(_algorithm, line) + "  " + line + "\n";
            if (nl == std::string::npos) break;
            start = nl + 1;
        }
    } else if (!text.empty()) {
        out = tpp::hashHex(_algorithm, text);
    }
    _output.string = NSStr(out);
}
- (void)copyOut:(id)s { [[NSPasteboard generalPasteboard] clearContents]; [[NSPasteboard generalPasteboard] setString:_output.string forType:NSPasteboardTypeString]; }
- (void)closeIt:(id)s { [self.window orderOut:nil]; }
@end

// ---------------------------------------------------------------- table helper window (Windows…, Shortcut Mapper)
@interface TPTableWindow : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, copy) NSArray<NSString *> *columns;
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *allRows;
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *rows;
@property (nonatomic, strong) NSTableView *table;
@property (nonatomic, copy) void (^onActivate)(NSInteger row);
@end
@implementation TPTableWindow {
    NSSearchField *_filter;
}
- (instancetype)initWithTitle:(NSString *)title columns:(NSArray *)cols rows:(NSArray *)rows buttons:(NSArray<NSArray *> *)buttons filter:(BOOL)filter {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 820, 480) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:YES];
    if ((self = [super initWithWindow:w])) {
        w.title = title;
        _columns = cols; _allRows = rows; _rows = rows;
        NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(12, 52, 796, filter ? 386 : 416)];
        sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _table = [[NSTableView alloc] initWithFrame:sv.bounds];
        for (NSUInteger i = 0; i < cols.count; ++i) {
            NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:[@(i) stringValue]];
            c.title = cols[i];
            c.width = i == 0 ? 300 : 160;
            [_table addTableColumn:c];
        }
        _table.dataSource = self; _table.delegate = self;
        _table.allowsMultipleSelection = YES;
        _table.doubleAction = @selector(activate:);
        _table.target = self;
        _table.usesAlternatingRowBackgroundColors = YES;
        sv.documentView = _table;
        sv.hasVerticalScroller = YES;
        [w.contentView addSubview:sv];
        if (filter) {
            _filter = [[NSSearchField alloc] initWithFrame:NSMakeRect(12, 446, 300, 24)];
            _filter.autoresizingMask = NSViewMinYMargin;
            _filter.target = self; _filter.action = @selector(filterChanged:);
            _filter.placeholderString = @"Filter";
            [w.contentView addSubview:_filter];
        }
        CGFloat x = 820 - 12;
        for (NSArray *b in buttons.reverseObjectEnumerator) {
            NSButton *btn = [NSButton buttonWithTitle:b[0] target:b[1] action:NSSelectorFromString(b[2])];
            [btn sizeToFit];
            x -= MAX(90, btn.frame.size.width + 10);
            btn.frame = NSMakeRect(x, 10, MAX(90, btn.frame.size.width + 10), 30);
            btn.autoresizingMask = NSViewMinXMargin;
            [w.contentView addSubview:btn];
            x -= 6;
        }
    }
    return self;
}
- (void)filterChanged:(id)s {
    NSString *f = _filter.stringValue.lowercaseString;
    if (!f.length) { self.rows = self.allRows; }
    else {
        NSMutableArray *r = [NSMutableArray array];
        for (NSArray *row in self.allRows) for (NSString *cell in row) if ([cell.lowercaseString containsString:f]) { [r addObject:row]; break; }
        self.rows = r;
    }
    [_table reloadData];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return (NSInteger)_rows.count; }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)r {
    NSInteger i = c.identifier.integerValue;
    NSArray *row = _rows[r];
    return i < (NSInteger)row.count ? row[i] : @"";
}
- (void)activate:(id)s { if (self.onActivate && _table.clickedRow >= 0) self.onActivate(_table.clickedRow); }
- (void)closeIt:(id)s { [self.window orderOut:nil]; }
@end

static TPHashDialog *g_hashDialogs[4];
static TPTableWindow *g_windowsDialog, *g_shortcutMapper;

@implementation TPMainWindowController (ToolCommands)

- (BOOL)macroRecording { return g_recording; }

- (void)registerToolCommands:(TPCommandRegistry *)reg {
    __weak TPMainWindowController *ws = self;
    struct { int gen, file, clip; tpp::HashAlgorithm a; } hashes[] = {
        {IDM_TOOL_MD5_GENERATE, IDM_TOOL_MD5_GENERATEFROMFILE, IDM_TOOL_MD5_GENERATEINTOCLIPBOARD, tpp::HashAlgorithm::MD5},
        {IDM_TOOL_SHA1_GENERATE, IDM_TOOL_SHA1_GENERATEFROMFILE, IDM_TOOL_SHA1_GENERATEINTOCLIPBOARD, tpp::HashAlgorithm::SHA1},
        {IDM_TOOL_SHA256_GENERATE, IDM_TOOL_SHA256_GENERATEFROMFILE, IDM_TOOL_SHA256_GENERATEINTOCLIPBOARD, tpp::HashAlgorithm::SHA256},
        {IDM_TOOL_SHA512_GENERATE, IDM_TOOL_SHA512_GENERATEFROMFILE, IDM_TOOL_SHA512_GENERATEINTOCLIPBOARD, tpp::HashAlgorithm::SHA512}};
    for (int i = 0; i < 4; ++i) {
        tpp::HashAlgorithm a = hashes[i].a;
        int idx = i;
        [reg registerCommand:hashes[i].gen handler:^(int c) {
            if (!g_hashDialogs[idx]) g_hashDialogs[idx] = [[TPHashDialog alloc] initWithAlgorithm:a];
            [g_hashDialogs[idx].window center];
            [g_hashDialogs[idx] showWindow:nil];
        }];
        [reg registerCommand:hashes[i].file handler:^(int c) {
            NSOpenPanel *op = [NSOpenPanel openPanel];
            op.allowsMultipleSelection = YES;
            if ([op runModal] != NSModalResponseOK) return;
            NSMutableString *out = [NSMutableString string];
            for (NSURL *u in op.URLs) {
                std::string hex, err;
                if (tpp::hashFileHex(a, StdStr(u.path), hex, err)) [out appendFormat:@"%s  %@\n", hex.c_str(), u.path];
                else [out appendFormat:@"(error: %s)  %@\n", err.c_str(), u.path];
            }
            if (!g_hashDialogs[idx]) g_hashDialogs[idx] = [[TPHashDialog alloc] initWithAlgorithm:a];
            [[NSPasteboard generalPasteboard] clearContents];
            [[NSPasteboard generalPasteboard] setString:out forType:NSPasteboardTypeString];
            [ws showMessage:[NSString stringWithFormat:@"%s digests (copied to clipboard)", tpp::hashName(a)] informative:out];
        }];
        [reg registerCommand:hashes[i].clip handler:^(int c) {
            std::string sel = sciSelectedText(ws.editor);
            [[NSPasteboard generalPasteboard] clearContents];
            [[NSPasteboard generalPasteboard] setString:NSStr(tpp::hashHex(a, sel)) forType:NSPasteboardTypeString];
        } enabled:^BOOL(int c) { return SCI(ws.editor, SCI_GETSELECTIONEMPTY) == 0 && SCI(ws.editor, SCI_GETSELECTIONS) == 1; } checked:nil];
    }

    // Run
    [reg registerCommand:IDM_EXECUTE handler:^(int c) { [ws runDialog]; }];
    [reg registerCommand:IDM_EXECUTE_VALIDATE_SHORTCUTSXML handler:^(int c) {
        NSString *p = supportFile(@"shortcuts.xml");
        if (![[NSFileManager defaultManager] fileExistsAtPath:p]) { [ws showMessage:@"shortcuts.xml" informative:@"No shortcuts.xml yet (defaults in use)."]; return; }
        NSError *err = nil;
        NSXMLDocument *d = [[NSXMLDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:p] options:0 error:&err];
        [ws showMessage:@"Validate shortcuts.xml" informative:d ? [NSString stringWithFormat:@"%@\n\nThe file is well-formed XML.", p] : err.localizedDescription];
    }];

    // Settings
    [reg registerCommand:IDM_SETTING_PREFERENCE handler:^(int c) { [[TPPreferencesWindow shared] showPage:[TPPreferencesWindow shared].currentPage]; }];
    [reg registerCommand:IDM_LANGSTYLE_CONFIG_DLG handler:^(int c) { [ws showStyleConfigurator]; }];
    [reg registerCommand:IDM_SETTING_SHORTCUT_MAPPER handler:^(int c) { [ws showShortcutMapper]; }];
    [reg registerCommand:IDM_SETTING_EDITCONTEXTMENU handler:^(int c) { [ws editContextMenuFile]; }];
    [reg registerCommand:IDM_SETTING_IMPORTSTYLETHEMES handler:^(int c) {
        NSOpenPanel *op = [NSOpenPanel openPanel];
        op.allowsMultipleSelection = YES;
        if ([op runModal] != NSModalResponseOK) return;
        NSString *dir = supportFile(@"themes");
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        for (NSURL *u in op.URLs) {
            NSString *dest = [dir stringByAppendingPathComponent:u.lastPathComponent];
            if ([[NSFileManager defaultManager] fileExistsAtPath:dest]) {
                NSInteger r = [ws prompt:[NSString stringWithFormat:@"\"%@\" already exists. Replace it?", u.lastPathComponent] informative:nil buttons:@[@"Replace", @"Skip"]];
                if (r != 0) continue;
                [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
            }
            [[NSFileManager defaultManager] copyItemAtPath:u.path toPath:dest error:nil];
        }
    }];
    [reg registerCommand:IDM_SETTING_OPENPLUGINSDIR handler:^(int c) {
        NSString *dir = supportFile(@"plugins");
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:dir]];
    }];
}

- (void)registerMacroCommands:(TPCommandRegistry *)reg {
    __weak TPMainWindowController *ws = self;
    loadShortcutsXml();
    [self applyShortcutsXml];
    [reg registerCommand:IDM_SETTING_SHORTCUT_MAPPER_MACRO handler:^(int c) { [[TPShortcutMapper sharedWithController:ws] openOnTab:TPMapperTabMacros]; }];
    [reg registerCommand:IDM_SETTING_SHORTCUT_MAPPER_RUN handler:^(int c) { [[TPShortcutMapper sharedWithController:ws] openOnTab:TPMapperTabRunCommands]; }];
    reg.willExecute = ^(int cmd) { [ws recordMacroStepForCommand:cmd]; };
    [reg registerCommand:IDM_MACRO_STARTRECORDINGMACRO handler:^(int c) { [ws startRecording]; } enabled:^BOOL(int c) { return !g_recording && ws.currentDocument; } checked:nil];
    [reg registerCommand:IDM_MACRO_STOPRECORDINGMACRO handler:^(int c) { [ws stopRecording]; } enabled:^BOOL(int c) { return g_recording; } checked:nil];
    [reg registerCommand:IDC_EDIT_TOGGLEMACRORECORDING handler:^(int c) { if (g_recording) [ws stopRecording]; else [ws startRecording]; }];
    [reg registerCommand:IDM_MACRO_PLAYBACKRECORDEDMACRO handler:^(int c) { [ws playMacro:g_current times:1 untilEnd:NO]; }
                 enabled:^BOOL(int c) { return !g_recording && !g_current.empty() && [ws editableForMacro]; } checked:nil];
    [reg registerCommand:IDM_MACRO_SAVECURRENTMACRO handler:^(int c) { [ws saveCurrentMacro]; } enabled:^BOOL(int c) { return !g_recording && !g_current.empty(); } checked:nil];
    [reg registerCommand:IDM_MACRO_RUNMULTIMACRODLG handler:^(int c) { [ws runMacroMultiple]; }
                 enabled:^BOOL(int c) { return !g_recording && (!g_current.empty() || !g_savedMacros.empty()) && [ws editableForMacro]; } checked:nil];
}

- (BOOL)editableForMacro { return self.currentDocument && !self.currentDocument.userReadOnly; }

- (void)registerWindowAndHelpCommands:(TPCommandRegistry *)reg {
    __weak TPMainWindowController *ws = self;
    struct { int cmd; NSString *key; BOOL asc; } sorts[] = {
        {IDM_WINDOW_SORT_FN_ASC, @"name", YES}, {IDM_WINDOW_SORT_FN_DSC, @"name", NO}, {IDM_WINDOW_SORT_FP_ASC, @"path", YES},
        {IDM_WINDOW_SORT_FP_DSC, @"path", NO}, {IDM_WINDOW_SORT_FT_ASC, @"type", YES}, {IDM_WINDOW_SORT_FT_DSC, @"type", NO},
        {IDM_WINDOW_SORT_FS_ASC, @"size", YES}, {IDM_WINDOW_SORT_FS_DSC, @"size", NO}, {IDM_WINDOW_SORT_FD_ASC, @"date", YES},
        {IDM_WINDOW_SORT_FD_DSC, @"date", NO}};
    for (auto &s : sorts) {
        NSString *key = s.key;
        BOOL asc = s.asc;
        [reg registerCommand:s.cmd handler:^(int c) { [ws sortTabsBy:key ascending:asc]; } enabled:^BOOL(int c) { return ws.activePane.documents.count > 1; } checked:nil];
    }
    [reg registerCommand:IDM_WINDOW_WINDOWS handler:^(int c) { [ws showWindowsDialog]; }];
    // Window > the document list (upstream activateDoc(id - IDM_WINDOW_MRU_FIRST) in the current view)
    [reg registerCommandsFrom:IDM_WINDOW_MRU_FIRST to:IDM_WINDOW_MRU_LIMIT handler:^(int c) {
        NSArray *docs = ws.activePane.documents;
        const NSUInteger i = static_cast<NSUInteger>(c - IDM_WINDOW_MRU_FIRST);
        if (i < docs.count) [ws activateDocument:docs[i] inPane:ws.activePane];
    } enabled:^BOOL(int c) { return static_cast<NSUInteger>(c - IDM_WINDOW_MRU_FIRST) < ws.activePane.documents.count; }
      checked:^BOOL(int c) { NSArray *docs = ws.activePane.documents; const NSUInteger i = static_cast<NSUInteger>(c - IDM_WINDOW_MRU_FIRST); return i < docs.count && docs[i] == ws.currentDocument; }];
    [reg registerCommand:IDM_CMDLINEARGUMENTS handler:^(int c) {
        [ws showMessage:@"Command Line Arguments" informative:[TPCommandLine helpText]];
    }];
    [reg registerCommand:IDM_DEBUGINFO handler:^(int c) { [ws showDebugInfo]; }];
    [reg registerCommand:IDM_ABOUT handler:^(int c) { [ws showAbout]; }];
}

// ---------------------------------------------------------------- macros
- (void)startRecording {
    g_current.clear();
    g_recording = YES;
    for (TPEditorPane *p in @[self.mainPane, self.subPane]) SCI(p.editor, SCI_STARTRECORD);
    [self.toolbar refreshStates];
}

- (void)stopRecording {
    g_recording = NO;
    for (TPEditorPane *p in @[self.mainPane, self.subPane]) SCI(p.editor, SCI_STOPRECORD);
    [self.toolbar refreshStates];
}

- (void)recordMacroStepForCommand:(int)cmd {
    if (!g_recording || !isRecordable(cmd)) return;
    g_current.push_back({2, 0, static_cast<uptr_t>(cmd), 0, ""});
}

- (void)recordMacroStepFromNotification:(SCNotification *)scn {
    if (!g_recording) return;
    TPMacroStep s;
    s.message = static_cast<int>(scn->message);
    s.wParam = scn->wParam;
    if (isStringMessage(s.message) && scn->lParam) {
        s.type = 1;
        const char *str = reinterpret_cast<const char *>(scn->lParam);
        s.sParam = (s.message == SCI_ADDTEXT || s.message == SCI_APPENDTEXT) ? std::string(str, scn->wParam) : std::string(str);
    } else {
        s.type = 0;
        s.lParam = scn->lParam;
    }
    g_current.push_back(s);
}

- (void)playSteps:(const std::vector<TPMacroStep> &)steps {
    ScintillaView *v = self.editor;
    for (const TPMacroStep &s : steps) {
        if (s.type == 2) { [[TPCommandRegistry shared] execute:static_cast<int>(s.wParam)]; v = self.editor; continue; }
        if (s.type == 1) SCI(v, s.message, s.message == SCI_ADDTEXT || s.message == SCI_APPENDTEXT ? s.sParam.size() : s.wParam, reinterpret_cast<sptr_t>(s.sParam.c_str()));
        else SCI(v, s.message, s.wParam, s.lParam);
    }
}

- (void)playMacro:(const std::vector<TPMacroStep> &)steps times:(NSInteger)times untilEnd:(BOOL)untilEnd {
    if (steps.empty()) return;
    ScintillaView *v = self.editor;
    SCI(v, SCI_BEGINUNDOACTION);
    if (untilEnd) {
        // upstream: repeat while the caret moves and the end of the document is not reached
        sptr_t lastPos = -1, lastLen = -1;
        for (int guard = 0; guard < 1000000; ++guard) {
            [self playSteps:steps];
            sptr_t pos = SCI(self.editor, SCI_GETCURRENTPOS), len = SCI(self.editor, SCI_GETLENGTH);
            if (pos >= len || (pos == lastPos && len == lastLen)) break;
            lastPos = pos; lastLen = len;
        }
    } else {
        for (NSInteger i = 0; i < times; ++i) [self playSteps:steps];
    }
    SCI(v, SCI_ENDUNDOACTION);
}

// upstream: Save Current Recorded Macro opens the Shortcut dialog (Name, CTRL / ALT / SHIFT, key)
- (void)saveCurrentMacro {
    NSAlert *a = [NSAlert new];
    a.messageText = @"Save Current Recorded Macro";
    NSView *acc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 340, 104)];
    NSTextField *nl = [NSTextField labelWithString:@"Name:"]; nl.frame = NSMakeRect(0, 80, 50, 18);
    NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(54, 77, 286, 24)];
    BOOL mac = [TPCommandRegistry shared].scheme == TPShortcutSchemeMac;
    NSButton *ctrl = [NSButton checkboxWithTitle:mac ? @"Ctrl (⌘)" : @"Ctrl" target:nil action:nil]; ctrl.frame = NSMakeRect(0, 48, 100, 20);
    NSButton *alt = [NSButton checkboxWithTitle:mac ? @"Alt (⌥)" : @"Alt" target:nil action:nil]; alt.frame = NSMakeRect(0, 26, 100, 20);
    NSButton *shift = [NSButton checkboxWithTitle:mac ? @"Shift (⇧)" : @"Shift" target:nil action:nil]; shift.frame = NSMakeRect(0, 4, 100, 20);
    NSPopUpButton *key = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(130, 26, 210, 26)];
    [key addItemWithTitle:@"None"];
    for (NSString *k in [TPCommandRegistry assignableKeys]) { [key addItemWithTitle:[TPCommandRegistry displayNameForKey:k]]; key.lastItem.representedObject = k; }
    for (NSView *x in @[nl, tf, ctrl, alt, shift, key]) [acc addSubview:x];
    a.accessoryView = acc;
    [a addButtonWithTitle:@"OK"];
    [a addButtonWithTitle:@"Cancel"];
    if ([a runModal] != NSAlertFirstButtonReturn || !tf.stringValue.length) return;
    TPKeyBinding *b = nil;
    if (NSString *k = key.selectedItem.representedObject) {
        NSEventModifierFlags m = 0;
        if (ctrl.state) m |= mac ? NSEventModifierFlagCommand : NSEventModifierFlagControl;
        if (alt.state) m |= NSEventModifierFlagOption;
        if (shift.state) m |= NSEventModifierFlagShift;
        b = [TPKeyBinding bindingWithKey:k modifiers:m command:0];
    }
    [self saveCurrentMacroNamed:tf.stringValue shortcut:b];
}

- (BOOL)saveCurrentMacroNamed:(NSString *)name { return [self saveCurrentMacroNamed:name shortcut:nil]; }

- (BOOL)saveCurrentMacroNamed:(NSString *)name shortcut:(TPKeyBinding *)shortcut {
    TPMacro m;
    m.name = StdStr(name);
    m.steps = g_current;
    g_savedMacros.push_back(m);
    const int cmd = TP_ID_MACRO + static_cast<int>(g_savedMacros.size() - 1);
    [self registerDynamicCommands];
    if (shortcut) [[TPCommandRegistry shared] setUserBinding:[TPKeyBinding bindingWithKey:shortcut.keyEquivalent modifiers:shortcut.modifiers command:cmd] forCommand:cmd];
    NSString *err = nil;
    if (!saveShortcutsXml(&err)) { [self showMessage:@"Cannot save shortcuts.xml" informative:err]; return NO; }
    return YES;
}

- (void)runMacroMultiple {
    NSAlert *a = [NSAlert new];
    a.messageText = @"Run a Macro Multiple Times";
    NSView *acc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 90)];
    NSPopUpButton *which = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 62, 320, 26)];
    if (!g_current.empty()) [which addItemWithTitle:@"Current recorded macro"];
    for (const TPMacro &m : g_savedMacros) [which addItemWithTitle:NSStr(m.name)];
    NSButton *times = [NSButton radioButtonWithTitle:@"Run" target:nil action:nil];
    times.frame = NSMakeRect(0, 34, 60, 20); times.state = NSControlStateValueOn;
    NSTextField *n = [[NSTextField alloc] initWithFrame:NSMakeRect(60, 32, 60, 22)]; n.stringValue = @"1";
    NSTextField *tl = [NSTextField labelWithString:@"times"]; tl.frame = NSMakeRect(126, 34, 60, 18);
    NSButton *eof = [NSButton radioButtonWithTitle:@"Run until the end of file" target:nil action:nil];
    eof.frame = NSMakeRect(0, 6, 300, 20);
    times.action = eof.action = @selector(self);
    for (NSView *x in @[which, times, n, tl, eof]) [acc addSubview:x];
    a.accessoryView = acc;
    [a addButtonWithTitle:@"Run"];
    [a addButtonWithTitle:@"Cancel"];
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    NSInteger idx = which.indexOfSelectedItem;
    std::vector<TPMacroStep> steps;
    if (!g_current.empty()) { if (idx == 0) steps = g_current; else steps = g_savedMacros[static_cast<size_t>(idx - 1)].steps; }
    else steps = g_savedMacros[static_cast<size_t>(idx)].steps;
    [self playMacro:steps times:MAX(1, n.integerValue) untilEnd:eof.state == NSControlStateValueOn];
}

// Saved macros and Run commands are registry commands (upstream ID_MACRO / ID_USER_CMD), so they get shortcuts,
// appear in the Shortcut Mapper and can be recorded like any command.
- (void)registerDynamicCommands {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    __weak TPMainWindowController *ws = self;
    for (int c = TP_ID_MACRO; c <= TP_ID_MACRO_LIMIT; ++c) [reg setLabel:nil forDynamicCommand:c];
    for (int c = TP_ID_USER_CMD; c <= TP_ID_USER_CMD_LIMIT; ++c) [reg setLabel:nil forDynamicCommand:c];
    for (size_t i = 0; i < g_savedMacros.size() && i <= TP_ID_MACRO_LIMIT - TP_ID_MACRO; ++i) {
        const int cmd = TP_ID_MACRO + static_cast<int>(i);
        [reg setLabel:NSStr(g_savedMacros[i].name) forDynamicCommand:cmd];
        [reg registerCommand:cmd handler:^(int c) {
            size_t idx = static_cast<size_t>(c - TP_ID_MACRO);
            if (idx < g_savedMacros.size()) [ws playMacro:g_savedMacros[idx].steps times:1 untilEnd:NO];
        } enabled:^BOOL(int c) { return !g_recording && [ws editableForMacro]; } checked:nil];
    }
    for (NSUInteger i = 0; i < g_runCommands.count && i <= TP_ID_USER_CMD_LIMIT - TP_ID_USER_CMD; ++i) {
        const int cmd = TP_ID_USER_CMD + static_cast<int>(i);
        [reg setLabel:g_runCommands[i][@"name"] forDynamicCommand:cmd];
        [reg registerCommand:cmd handler:^(int c) {
            NSUInteger idx = static_cast<NSUInteger>(c - TP_ID_USER_CMD);
            if (idx >= g_runCommands.count) return;
            NSString *err = nil;
            if (![ws runShellCommand:g_runCommands[idx][@"command"] error:&err]) [ws showMessage:@"Cannot run the command." informative:err];
        }];
    }
}

// <InternalCommands>, <ScintillaKeys> and the macro / Run command shortcuts of shortcuts.xml
- (void)applyShortcutsXml {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    [self registerDynamicCommands];
    for (NSNumber *n in reg.userBoundCommands) [reg setUserBinding:nil forCommand:n.intValue];
    for (NSXMLElement *e in [g_shortcutsDoc nodesForXPath:@"//InternalCommands/Shortcut" error:nil]) {
        int cmd = [[[e attributeForName:@"id"] stringValue] intValue];
        if (TPKeyBinding *b = [reg bindingFromUpstreamAttributes:shortcutAttributes(e) command:cmd]) [reg setUserBinding:b forCommand:cmd];
    }
    for (size_t i = 0; i < g_savedMacros.size(); ++i) {
        const int cmd = TP_ID_MACRO + static_cast<int>(i);
        if (TPKeyBinding *b = [reg bindingFromUpstreamAttributes:g_savedMacros[i].shortcut ?: @{} command:cmd]) if (!b.isEmpty) [reg setUserBinding:b forCommand:cmd];
    }
    for (NSUInteger i = 0; i < g_runCommands.count; ++i) {
        const int cmd = TP_ID_USER_CMD + static_cast<int>(i);
        if (TPKeyBinding *b = [reg bindingFromUpstreamAttributes:g_runCommands[i][@"shortcut"] ?: @{} command:cmd]) if (!b.isEmpty) [reg setUserBinding:b forCommand:cmd];
    }
    [[TPPluginHost shared] applyShortcutsFrom:g_shortcutsDoc];   // plugin commands loaded so far
    for (NSNumber *m in [TPScintillaKeys shared].userBoundMessages) [[TPScintillaKeys shared] setUserBinding:nil forMessage:m.intValue];
    for (NSXMLElement *e in [g_shortcutsDoc nodesForXPath:@"//ScintillaKeys/ScintKey" error:nil]) {
        int msg = [[[e attributeForName:@"ScintID"] stringValue] intValue];
        if (TPKeyBinding *b = [reg bindingFromUpstreamAttributes:shortcutAttributes(e) command:msg]) [[TPScintillaKeys shared] setUserBinding:b forMessage:msg];
    }
}

// Macro menu / Run menu tail: saved items (FolderName sub-menus) + "Modify Shortcut/Delete …" (upstream initMenu)
- (void)appendDynamicItems:(NSArray<NSNumber *> *)cmds folders:(NSArray<NSString *> *)folders mapperCommand:(int)mapperCmd toMenu:(NSMenu *)menu tag:(NSString *)tag {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    for (NSMenuItem *mi in [menu.itemArray copy]) if ([mi.representedObject isEqual:tag]) [menu removeItem:mi];
    NSMenuItem *sep = [NSMenuItem separatorItem];
    sep.representedObject = tag;
    [menu addItem:sep];
    NSMutableDictionary<NSString *, NSMenu *> *subs = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < cmds.count; ++i) {
        NSMenuItem *mi = [reg makeItemForCommand:cmds[i].intValue];
        [reg applyBindingToItem:mi];
        NSString *folder = folders[i];
        if (folder.length) {
            NSMenu *sub = subs[folder];
            if (!sub) {
                sub = [[NSMenu alloc] initWithTitle:folder];
                NSMenuItem *holder = [[NSMenuItem alloc] initWithTitle:folder action:nil keyEquivalent:@""];
                holder.submenu = sub;
                holder.representedObject = tag;
                [menu addItem:holder];
                subs[folder] = sub;
            }
            [sub addItem:mi];
        } else {
            mi.representedObject = tag;
            [menu addItem:mi];
        }
    }
    if (cmds.count) {
        NSMenuItem *sep2 = [NSMenuItem separatorItem];
        sep2.representedObject = tag;
        [menu addItem:sep2];
    }
    NSMenuItem *mapper = [reg makeItemForCommand:mapperCmd];
    mapper.title = mapperCmd == IDM_SETTING_SHORTCUT_MAPPER_MACRO ? @"Modify Shortcut/Delete Macro..." : @"Modify Shortcut/Delete Command...";
    mapper.representedObject = tag;
    [menu addItem:mapper];
}

- (void)updateMacroMenu:(NSMenu *)menu {
    NSMutableArray *cmds = [NSMutableArray array], *folders = [NSMutableArray array];
    for (size_t i = 0; i < g_savedMacros.size(); ++i) { [cmds addObject:@(TP_ID_MACRO + static_cast<int>(i))]; [folders addObject:NSStr(g_savedMacros[i].folder)]; }
    [self appendDynamicItems:cmds folders:folders mapperCommand:IDM_SETTING_SHORTCUT_MAPPER_MACRO toMenu:menu tag:@"macro-extra"];
}

- (void)updateRunMenu:(NSMenu *)menu {
    NSMutableArray *cmds = [NSMutableArray array], *folders = [NSMutableArray array];
    for (NSUInteger i = 0; i < g_runCommands.count; ++i) { [cmds addObject:@(TP_ID_USER_CMD + static_cast<int>(i))]; [folders addObject:g_runCommands[i][@"folder"] ?: @""]; }
    [self appendDynamicItems:cmds folders:folders mapperCommand:IDM_SETTING_SHORTCUT_MAPPER_RUN toMenu:menu tag:@"run-extra"];
}

static char kLastRunURLKey;
- (NSURL *)lastRunURL { return objc_getAssociatedObject(self, &kLastRunURLKey); }
- (void)setLastRunURL:(NSURL *)u { objc_setAssociatedObject(self, &kLastRunURLKey, u, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

// ---------------------------------------------------------------- TPShortcutMapperData
- (NSArray<NSString *> *)macroNames {
    NSMutableArray *a = [NSMutableArray array];
    for (const TPMacro &m : g_savedMacros) [a addObject:NSStr(m.name)];
    return a;
}
- (NSArray<NSString *> *)runCommandNames { return [g_runCommands valueForKey:@"name"] ?: @[]; }
- (void)renameMacroAtIndex:(NSInteger)i to:(NSString *)name {
    if (i >= 0 && i < (NSInteger)g_savedMacros.size()) g_savedMacros[static_cast<size_t>(i)].name = StdStr(name);
}
- (void)renameRunCommandAtIndex:(NSInteger)i to:(NSString *)name {
    if (i < 0 || i >= (NSInteger)g_runCommands.count) return;
    NSMutableDictionary *d = [g_runCommands[(NSUInteger)i] mutableCopy];
    d[@"name"] = name;
    g_runCommands[(NSUInteger)i] = d;
}
// Deleting shifts the later items' ids down, with their shortcuts (upstream re-numbers too)
- (void)shiftBindingsFrom:(int)first count:(NSUInteger)count removedIndex:(NSUInteger)removed {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    for (NSUInteger i = removed; i < count; ++i) {
        TPKeyBinding *next = i + 1 < count ? [reg userBindingForCommand:first + static_cast<int>(i + 1)] : nil;
        int cmd = first + static_cast<int>(i);
        [reg setUserBinding:next ? [TPKeyBinding bindingWithKey:next.keyEquivalent modifiers:next.modifiers command:cmd] : nil forCommand:cmd];
    }
}
- (void)deleteMacroAtIndex:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)g_savedMacros.size()) return;
    NSUInteger count = g_savedMacros.size();
    g_savedMacros.erase(g_savedMacros.begin() + i);
    [self shiftBindingsFrom:TP_ID_MACRO count:count removedIndex:(NSUInteger)i];
}
- (void)deleteRunCommandAtIndex:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)g_runCommands.count) return;
    NSUInteger count = g_runCommands.count;
    [g_runCommands removeObjectAtIndex:(NSUInteger)i];
    [self shiftBindingsFrom:TP_ID_USER_CMD count:count removedIndex:(NSUInteger)i];
}
- (void)shortcutsDidChange {
    [self registerDynamicCommands];
    [[TPPluginHost shared] rebuildPluginsMenu];   // key equivalents of the plugin sub-menus
    [self.toolbar refreshTooltips];               // tooltips show the shortcuts
    NSString *err = nil;
    if (!saveShortcutsXml(&err)) [self showMessage:@"Cannot save shortcuts.xml" informative:err];
}

// ---------------------------------------------------------------- run
static NSString *shellQuote(NSString *s) {
    return [NSString stringWithFormat:@"'%@'", [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

// $(…) variables inside a URL are percent-encoded instead of shell-quoted
- (NSString *)expandRunURL:(NSString *)url {
    ScintillaView *v = self.editor;
    sptr_t pos = SCI(v, SCI_GETCURRENTPOS);
    std::string sel = sciSelectedText(v);
    std::string word = sel.empty() ? sciGetRange(v, SCI(v, SCI_WORDSTARTPOSITION, pos, 1), SCI(v, SCI_WORDENDPOSITION, pos, 1)) : sel;
    NSMutableCharacterSet *allowed = [NSCharacterSet.URLQueryAllowedCharacterSet mutableCopy];
    [allowed removeCharactersInString:@"&+=?#"];
    NSDictionary *vars = @{@"$(CURRENT_WORD)": NSStr(word), @"$(FULL_CURRENT_PATH)": self.currentDocument.path ?: @"",
                           @"$(FILE_NAME)": self.currentDocument.displayName ?: @""};
    for (NSString *k in vars) url = [url stringByReplacingOccurrencesOfString:k withString:[vars[k] stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @""];
    return url;
}

- (NSString *)expandRunVariables:(NSString *)cmd {
    TPDocument *d = self.currentDocument;
    ScintillaView *v = self.editor;
    NSString *full = d.path ?: @"";
    sptr_t pos = SCI(v, SCI_GETCURRENTPOS);
    std::string word = sciGetRange(v, SCI(v, SCI_WORDSTARTPOSITION, pos, 1), SCI(v, SCI_WORDENDPOSITION, pos, 1));
    std::string sel = sciSelectedText(v);
    NSDictionary *vars = @{
        @"$(FULL_CURRENT_PATH)": full,
        @"$(CURRENT_DIRECTORY)": full.stringByDeletingLastPathComponent ?: @"",
        @"$(FILE_NAME)": full.lastPathComponent ?: d.displayName,
        @"$(NAME_PART)": full.lastPathComponent.stringByDeletingPathExtension ?: @"",
        @"$(EXT_PART)": full.pathExtension.length ? [@"." stringByAppendingString:full.pathExtension] : @"",
        @"$(CURRENT_WORD)": NSStr(sel.empty() ? word : sel),
        @"$(CURRENT_LINE)": [@(SCI(v, SCI_LINEFROMPOSITION, pos) + 1) stringValue],
        @"$(CURRENT_COLUMN)": [@(SCI(v, SCI_GETCOLUMN, pos) + 1) stringValue],
        @"$(CURRENT_LINESTR)": NSStr(sciGetLine(v, SCI(v, SCI_LINEFROMPOSITION, pos))),
        @"$(NPP_DIRECTORY)": [NSBundle mainBundle].resourcePath,
        @"$(NPP_FULL_FILE_PATH)": [NSBundle mainBundle].executablePath,
    };
    NSString *out = cmd;
    for (NSString *k in vars) out = [out stringByReplacingOccurrencesOfString:k withString:shellQuote(vars[k])];
    // "$(X)" already wrapped in double quotes by the user: drop the redundant quotes around our single quotes
    out = [out stringByReplacingOccurrencesOfString:@"\"'" withString:@"'"];
    out = [out stringByReplacingOccurrencesOfString:@"'\"" withString:@"'"];
    return out;
}

- (BOOL)runShellCommand:(NSString *)cmd error:(NSString **)error {
    // upstream ShellExecute: a URL (Get PHP help, Wikipedia Search) opens in the browser
    NSString *trimmed = [cmd stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if ([trimmed rangeOfString:@"^[A-Za-z][A-Za-z0-9+.-]*://" options:NSRegularExpressionSearch].location == 0) {
        NSString *expanded = [self expandRunURL:trimmed];
        NSURL *u = [NSURL URLWithString:expanded];
        if (!u) { if (error) *error = @"Invalid URL"; return NO; }
        self.lastRunURL = u;
        if (!self.selfTestMode) [[NSWorkspace sharedWorkspace] openURL:u];
        return YES;
    }
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    t.arguments = @[@"-c", [self expandRunVariables:cmd]];
    if (self.currentDocument.path) t.currentDirectoryURL = [NSURL fileURLWithPath:self.currentDocument.path.stringByDeletingLastPathComponent];
    NSError *err = nil;
    if (![t launchAndReturnError:&err]) { if (error) *error = err.localizedDescription; return NO; }
    return YES;
}

- (void)runDialog {
    loadShortcutsXml();
    NSAlert *a = [NSAlert new];
    a.messageText = @"Run...";
    a.informativeText = @"The command is run with /bin/sh. Variables: $(FULL_CURRENT_PATH) $(CURRENT_DIRECTORY) $(FILE_NAME) $(NAME_PART) $(EXT_PART) $(CURRENT_WORD) $(CURRENT_LINE) $(CURRENT_COLUMN) $(CURRENT_LINESTR) $(NPP_DIRECTORY) $(NPP_FULL_FILE_PATH)";
    NSComboBox *cb = [[NSComboBox alloc] initWithFrame:NSMakeRect(0, 0, 420, 26)];
    for (NSDictionary *c in g_runCommands) [cb addItemWithObjectValue:c[@"command"]];
    NSString *last = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastRunCommand"];
    if (last) cb.stringValue = last;
    a.accessoryView = cb;
    [a addButtonWithTitle:@"Run"];
    [a addButtonWithTitle:@"Save..."];
    [a addButtonWithTitle:@"Cancel"];
    NSModalResponse r = [a runModal];
    NSString *cmd = cb.stringValue;
    if (!cmd.length || r == NSAlertThirdButtonReturn) return;
    [[NSUserDefaults standardUserDefaults] setObject:cmd forKey:@"LastRunCommand"];
    if (r == NSAlertSecondButtonReturn) {
        NSAlert *n = [NSAlert new];
        n.messageText = @"Name of the command";
        NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
        n.accessoryView = tf;
        [n addButtonWithTitle:@"OK"];
        [n addButtonWithTitle:@"Cancel"];
        if ([n runModal] != NSAlertFirstButtonReturn || !tf.stringValue.length) return;
        [g_runCommands addObject:@{@"name": tf.stringValue, @"command": cmd, @"folder": @"", @"shortcut": @{}}];
        [self shortcutsDidChange];
        return;
    }
    NSString *err = nil;
    if (![self runShellCommand:cmd error:&err]) [self showMessage:@"Cannot run the command." informative:err];
}

// ---------------------------------------------------------------- window
- (void)sortTabsBy:(NSString *)key ascending:(BOOL)asc {
    TPEditorPane *p = self.activePane;
    [p.documents sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(TPDocument *a, TPDocument *b) {
        NSComparisonResult r = NSOrderedSame;
        if ([key isEqualToString:@"name"]) r = [a.displayName localizedStandardCompare:b.displayName];
        else if ([key isEqualToString:@"path"]) r = [(a.path ?: a.displayName) localizedStandardCompare:(b.path ?: b.displayName)];
        else if ([key isEqualToString:@"type"]) r = [a.displayName.pathExtension compare:b.displayName.pathExtension options:NSCaseInsensitiveSearch];
        else if ([key isEqualToString:@"size"]) {
            __block sptr_t la = 0, lb = 0;
            [self withDocument:a perform:^(ScintillaView *v) { la = SCI(v, SCI_GETLENGTH); }];
            [self withDocument:b perform:^(ScintillaView *v) { lb = SCI(v, SCI_GETLENGTH); }];
            r = la < lb ? NSOrderedAscending : la > lb ? NSOrderedDescending : NSOrderedSame;
        } else {
            NSDate *da = a.diskModDate ?: [NSDate distantPast], *db = b.diskModDate ?: [NSDate distantPast];
            r = [da compare:db];
        }
        return asc ? r : (NSComparisonResult)-r;
    }];
    [p reloadTabs];
}

// upstream BuildMenuFileName(60, pos, name, true): "1: " … "10: ", the path shortened to 60 characters
// (PathCompactPathEx keeps the file name and elides the middle)
NSString *TPMenuFileName(NSString *path, NSUInteger pos, BOOL ordinal) {
    NSString *name = path ?: @"";
    if (name.length > 60) {
        NSString *file = name.lastPathComponent;
        if (file.length + 4 >= 60) name = [@"..." stringByAppendingString:[file substringFromIndex:file.length - 57]];
        else name = [NSString stringWithFormat:@"%@.../%@", [name substringToIndex:60 - 4 - file.length], file];
    }
    return ordinal ? [NSString stringWithFormat:@"%lu: %@", (unsigned long)(pos + 1), name] : name;
}

// upstream WindowsMenu::initPopupMenu: the current view's documents as IDM_WINDOW_MRU_FIRST + i (at most 40), the
// "Recent Window" placeholder becoming the first one; "*" after a modified document, the current one checked
- (void)updateWindowMenu:(NSMenu *)menu {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    NSMenuItem *placeholder = [reg menuItemForCommand:IDM_WINDOW_MRU_FIRST];
    for (NSMenuItem *mi in [menu.itemArray copy])
        if ([mi.representedObject isKindOfClass:[TPDocument class]] && mi != placeholder) [menu removeItem:mi];
    placeholder.representedObject = nil;
    placeholder.hidden = YES;
    NSArray<TPDocument *> *docs = self.activePane.documents;
    NSInteger at = placeholder && placeholder.menu == menu ? [menu indexOfItem:placeholder] : menu.numberOfItems - 1;
    for (NSUInteger i = 0; i < docs.count && i <= (NSUInteger)(IDM_WINDOW_MRU_LIMIT - IDM_WINDOW_MRU_FIRST); ++i) {
        TPDocument *d = docs[i];
        NSMenuItem *mi = (i == 0 && placeholder.menu == menu) ? placeholder : [reg makeItemForCommand:IDM_WINDOW_MRU_FIRST + static_cast<int>(i)];
        mi.title = [TPMenuFileName(d.path ?: d.displayName, i, YES) stringByAppendingString:d.dirty ? @"*" : @""];
        mi.representedObject = d;
        mi.hidden = NO;
        mi.state = d == self.currentDocument ? NSControlStateValueOn : NSControlStateValueOff;
        if (mi != placeholder) [menu insertItem:mi atIndex:++at];
    }
}

- (void)activateFromMenu:(NSMenuItem *)mi {
    TPDocument *d = mi.representedObject;
    TPEditorPane *p = [self.activePane indexOfDocument:d] != NSNotFound ? self.activePane : self.otherPane;
    [self activateDocument:d inPane:p];
}

- (void)showWindowsDialog {
    NSMutableArray *rows = [NSMutableArray array];
    NSArray *docs = self.allDocuments;
    for (TPDocument *d in docs) {
        __block sptr_t len = 0;
        [self withDocument:d perform:^(ScintillaView *v) { len = SCI(v, SCI_GETLENGTH); }];
        [rows addObject:@[[d.displayName stringByAppendingString:d.dirty ? @" *" : @""], d.path ? d.path.stringByDeletingLastPathComponent : @"",
                          d.displayName.pathExtension, [@(len) stringValue]]];
    }
    g_windowsDialog = [[TPTableWindow alloc] initWithTitle:@"Windows" columns:@[@"Name", @"Path", @"Type", @"Size"] rows:rows
                                                   buttons:@[@[@"Activate", self, @"windowsActivate:"], @[@"Save", self, @"windowsSave:"],
                                                             @[@"Close window(s)", self, @"windowsClose:"], @[@"OK", self, @"windowsOK:"]] filter:NO];
    __weak TPMainWindowController *ws = self;
    g_windowsDialog.onActivate = ^(NSInteger row) { [ws windowsActivateRow:row]; };
    objc_setAssociatedObject(g_windowsDialog, "docs", docs, OBJC_ASSOCIATION_RETAIN);
    [g_windowsDialog.window center];
    [g_windowsDialog showWindow:nil];
}

- (NSArray<TPDocument *> *)windowsDialogSelection {
    NSArray *docs = objc_getAssociatedObject(g_windowsDialog, "docs");
    NSMutableArray *sel = [NSMutableArray array];
    [g_windowsDialog.table.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *stop) { if (i < docs.count) [sel addObject:docs[i]]; }];
    return sel;
}

- (void)windowsActivateRow:(NSInteger)row {
    NSArray *docs = objc_getAssociatedObject(g_windowsDialog, "docs");
    if (row < 0 || row >= (NSInteger)docs.count) return;
    TPDocument *d = docs[row];
    [self activateDocument:d inPane:[self.mainPane indexOfDocument:d] != NSNotFound ? self.mainPane : self.subPane];
}
- (void)windowsActivate:(id)s { [self windowsActivateRow:g_windowsDialog.table.selectedRow]; }
- (void)windowsSave:(id)s { for (TPDocument *d in [self windowsDialogSelection]) [self saveDocument:d]; }
- (void)windowsClose:(id)s {
    for (TPDocument *d in [self windowsDialogSelection])
        for (TPEditorPane *p in @[self.mainPane, self.subPane]) if ([p indexOfDocument:d] != NSNotFound) [self closeDocument:d inPane:p];
    [g_windowsDialog.window orderOut:nil];
    [self showWindowsDialog];
}
- (void)windowsOK:(id)s { [g_windowsDialog.window orderOut:nil]; }

// ---------------------------------------------------------------- settings
- (void)showStyleConfigurator {
    [[TPStyleConfigurator sharedWithController:self] open];
}

- (void)showShortcutMapper {
    [[TPShortcutMapper sharedWithController:self] openOnTab:TPMapperTabMainMenu];
}
- (void)closeShortcutMapper:(id)s { [g_shortcutMapper.window orderOut:nil]; }

// ---------------------------------------------------------------- help
- (NSString *)debugInfoText {
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    NSProcessInfo *pi = [NSProcessInfo processInfo];
#if defined(__arm64__)
    NSString *arch = @"arm64";
#else
    NSString *arch = @"x86_64";
#endif
    int translated = 0;
    size_t sz = sizeof(translated);
    if (sysctlbyname("sysctl.proc_translated", &translated, &sz, nullptr, 0) != 0) translated = 0;
    arch = [arch stringByAppendingString:translated ? @", running under Rosetta 2 (Intel code on Apple silicon)" : @", native"];
    NSMutableArray *slices = [NSMutableArray array];
    for (NSNumber *n in [NSBundle mainBundle].executableArchitectures) {
        if (n.integerValue == NSBundleExecutableArchitectureARM64) [slices addObject:@"arm64"];
        else if (n.integerValue == NSBundleExecutableArchitectureX86_64) [slices addObject:@"x86_64"];
    }
    NSString *binary = slices.count > 1 ? [NSString stringWithFormat:@"universal (%@)", [slices componentsJoinedByString:@" + "]] : (slices.firstObject ?: @"unknown");
    return [NSString stringWithFormat:@"Textpad++ v%@ (running: %@)\nBinary: %@\nBuild time: %s %s\nBundle: %@\nmacOS: %@\nEngine: Scintilla 5.6.9, Lexilla 5.5.5, Boost.Regex\nSettings folder: %@\nTheme: %@\nShortcut scheme: %@\nOpen documents: %lu",
            info[@"CFBundleShortVersionString"], arch, binary, __DATE__, __TIME__, [NSBundle mainBundle].bundlePath, pi.operatingSystemVersionString,
            [TPSession shared].supportDirectory, [TPLanguageService shared].themePath.lastPathComponent,
            [TPCommandRegistry shared].scheme == TPShortcutSchemeMac ? @"macOS" : @"Windows", (unsigned long)self.allDocuments.count];
}

- (void)showDebugInfo {
    NSString *t = [self debugInfoText];
    NSInteger r = [self prompt:@"Debug Info" informative:t buttons:@[@"OK", @"Copy debug info into clipboard"]];
    if (r == 1) { [[NSPasteboard generalPasteboard] clearContents]; [[NSPasteboard generalPasteboard] setString:t forType:NSPasteboardTypeString]; }
}

- (void)showAbout {
    NSString *ver = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"];
    NSDictionary *opts = @{
        NSAboutPanelOptionApplicationName: @"Textpad++",
        NSAboutPanelOptionApplicationVersion: ver ?: @"",
        NSAboutPanelOptionVersion: @"",
        NSAboutPanelOptionCredits: [[NSAttributedString alloc] initWithString:
            @"A macOS text and source-code editor.\n\n"
             "Textpad++ is free software, licensed under the GNU General Public License v3, and comes with no warranty.\n"
             "Portions (C) Don Ho and contributors, under the GNU GPL v3.\n"
             "Editing component: Scintilla and Lexilla (C) Neil Hodgson. Regular expressions: Boost.Regex. Encoding detection: uchardet.\n"
             "Licences: Contents/Resources/licenses in the application bundle."
                                                                       attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:11]}],
    };
    [NSApp orderFrontStandardAboutPanelWithOptions:opts];
}

@end
