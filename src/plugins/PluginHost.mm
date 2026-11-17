// Textpad++ — plugin host (upstream PluginsManager.cpp + the NPPM_* cases of NppBigSwitch.cpp). GPL-3.0-or-later.
#import "plugins/PluginHost.h"
#import "commands/DevTools.h"
#import "plugins/PluginsAdmin.h"
#import "app/MainWindowController.h"
#import "app/EditorPane.h"
#import "app/Document.h"
#import "app/Session.h"
#import "app/Preferences.h"
#import "app/LanguageService.h"
#import "app/ToolbarView.h"
#import "panels/DockManager.h"
#import "app/Sci.h"
#import "commands/CommandRegistry.h"
#include "core/Encoding.h"
#include "TextpadPlusPlusPlugin.h"
#include <vector>

using namespace npp;

typedef void (*PFUNCSETINFO)(NppData);
typedef const char *(*PFUNCGETNAME)(void);
typedef FuncItem *(*PFUNCGETFUNCSARRAY)(int *);
typedef void (*PBENOTIFIED)(SCNotification *);
typedef intptr_t (*PMESSAGEPROC)(uint32_t, uintptr_t, intptr_t);
typedef int (*PFUNCAPIVERSION)(void);

extern int (^TPContextMenuPluginResolver)(NSString *pluginName, NSString *commandName);

static_assert(NPPN_READY == NPPN_READY_CODE && NPPN_FILEBEFORECLOSE == NPPN_FILEBEFORECLOSE_CODE && NPPN_FILEOPENED == NPPN_FILEOPENED_CODE &&
              NPPN_FILECLOSED == NPPN_FILECLOSED_CODE && NPPN_FILEBEFOREOPEN == NPPN_FILEBEFOREOPEN_CODE && NPPN_FILEBEFORESAVE == NPPN_FILEBEFORESAVE_CODE &&
              NPPN_FILESAVED == NPPN_FILESAVED_CODE && NPPN_SHUTDOWN == NPPN_SHUTDOWN_CODE && NPPN_BUFFERACTIVATED == NPPN_BUFFERACTIVATED_CODE &&
              NPPN_LANGCHANGED == NPPN_LANGCHANGED_CODE && NPPN_BEFORESHUTDOWN == NPPN_BEFORESHUTDOWN_CODE && NPPN_CANCELSHUTDOWN == NPPN_CANCELSHUTDOWN_CODE,
              "NPPN codes match the SDK header");

// the three handles plugins pass back to sendMessage
static char kNppHandle, kSciMainHandle, kSciSubHandle;

// upstream ScintillaEditView::_langNameInfoArray, indexed by LangType
namespace { struct LangRow { const char *name, *shortName, *longName, *lexer; int menuCmd; }; }
static const LangRow kLangRows[] = {
#include "NppLangTable.inc"
};
static const int kLangCount = static_cast<int>(sizeof(kLangRows) / sizeof(kLangRows[0]));

static int langTypeOf(TPDocument *d) {
    if (!d) return -1;
    if ([d.languageId hasPrefix:@"udl:"]) return L_USER;
    for (int i = 0; i < kLangCount; ++i) if ([d.languageId isEqualToString:@(kLangRows[i].name)]) return i;
    return L_TEXT;
}

// UTF-8 into a plugin buffer of `cap` bytes: NO when it does not fit (upstream returns FALSE)
static BOOL copyOut(NSString *s, uintptr_t cap, intptr_t buf) {
    const char *u = (s ?: @"").UTF8String;
    const size_t n = strlen(u);
    if (!buf || cap == 0 || n >= cap) return NO;
    memcpy(reinterpret_cast<char *>(buf), u, n + 1);
    return YES;
}
static intptr_t copyOutLength(NSString *s, intptr_t buf) {   // NULL buffer: just the length (upstream convention)
    const char *u = (s ?: @"").UTF8String;
    const size_t n = strlen(u);
    if (buf) memcpy(reinterpret_cast<char *>(buf), u, n + 1);
    return static_cast<intptr_t>(n);
}
static NSString *strArg(intptr_t p) { return p ? @(reinterpret_cast<const char *>(p)) : nil; }

static intptr_t hostSendMessage(void *handle, uint32_t msg, uintptr_t w, intptr_t l);

// ================================================================ a plugin's docking dialog (NPPM_DMMREGASDCKDLG)
@interface TPPluginPanel : NSObject <TPPanel>
@property (nonatomic, copy) NSString *identifier, *title;
@property (nonatomic, strong) NSView *view;
@property (nonatomic) TPDockSide side;
@end
@implementation TPPluginPanel
- (NSString *)panelIdentifier { return _identifier; }
- (NSString *)panelTitle { return _title; }
- (NSView *)panelView { return _view; }
- (TPDockSide)defaultSide { return _side; }
@end

// ================================================================ TPPlugin
@interface TPPlugin ()
@property (nonatomic, readwrite) NSString *moduleName, *displayName, *path, *version;
@property (nonatomic, readwrite) NSArray<NSString *> *itemNames;
@property (nonatomic, readwrite) NSArray<NSNumber *> *commands;
@property (nonatomic, readwrite) BOOL removed;
@property (nonatomic, readwrite) BOOL builtIn;
@property (nonatomic) CFBundleRef bundle;
@property (nonatomic) FuncItem *funcItems;
@property (nonatomic) int funcCount;
@property (nonatomic) PBENOTIFIED beNotified;
@property (nonatomic) PMESSAGEPROC messageProc;
@end
@implementation TPPlugin
- (void *)functionNamed:(NSString *)symbol {
    return _bundle ? CFBundleGetFunctionPointerForName(_bundle, (__bridge CFStringRef)symbol) : nullptr;
}
@end

// ================================================================ TPPluginHost
@implementation TPPluginHost {
    NSMutableArray<TPPlugin *> *_plugins;
    NSMutableArray<NSDictionary *> *_incompatible;
    NSMutableSet<NSNumber *> *_checked;
    NSMutableDictionary<NSNumber *, TPKeyBinding *> *_defaults;   // the plugin's own ShortcutKey per command
    int _nextCmd, _nextDynamicCmd, _nextMarker, _nextIndicator;
    NSMutableArray<TPPluginPanel *> *_pluginPanels;
}

+ (instancetype)shared {
    static TPPluginHost *h;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ h = [TPPluginHost new]; });
    return h;
}

- (instancetype)init {
    if ((self = [super init])) {
        _plugins = [NSMutableArray array];
        _incompatible = [NSMutableArray array];
        _checked = [NSMutableSet set];
        _defaults = [NSMutableDictionary dictionary];
        _pluginPanels = [NSMutableArray array];
        _nextCmd = TP_ID_PLUGINS_CMD;
        _nextDynamicCmd = TP_ID_PLUGINS_CMD_DYNAMIC;
        _nextMarker = 1;       // upstream MARKER_PLUGINS .. MARKER_PLUGINS_LIMIT (1–15)
        _nextIndicator = 9;    // upstream INDICATOR_PLUGINS .. INDICATOR_PLUGINS_LIMIT (9–20)
        __weak TPPluginHost *ws = self;
        TPContextMenuPluginResolver = ^int(NSString *plugin, NSString *item) { return [ws commandForPluginNamed:plugin item:item]; };
    }
    return self;
}

- (NSArray<TPPlugin *> *)plugins { return _plugins; }
- (NSArray<NSDictionary<NSString *, NSString *> *> *)incompatible { return _incompatible; }
- (NSString *)pluginsDirectory {
    return _pluginsDirectoryOverride ?: [[TPSession shared].supportDirectory stringByAppendingPathComponent:@"plugins"];
}
- (NSString *)pluginsConfigDirectory { return [self.pluginsDirectory stringByAppendingPathComponent:@"Config"]; }

// ---------------------------------------------------------------- commands
- (void)registerCommands {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    __weak TPPluginHost *ws = self;
    [reg registerCommand:IDM_SETTING_IMPORTPLUGIN handler:^(int c) { [ws runImportDialog]; }];
    [reg registerCommand:IDM_SETTING_PLUGINADM handler:^(int c) { [[TPPluginsAdmin shared] showWindow:nil]; }];
    // Plugins > JSON Tools (built in; the Windows editor needs a plugin such as JSON Viewer or JSTool for this)
    __weak TPMainWindowController *wc = _controller;
    NSDictionary *(^keys)(NSString *) = ^NSDictionary *(NSString *vk) { return @{@"Ctrl": @"yes", @"Alt": @"yes", @"Shift": @"yes", @"Key": vk}; };
    [self registerBuiltInToolNamed:@"JSON Tools" module:@"JSONTools" items:@[
        @[@"Format JSON", ^{ [wc runJsonTool:0]; }, keys(@"77")],     // Ctrl+Alt+Shift+M (⌘⌥⇧M)
        @[@"Compress JSON", ^{ [wc runJsonTool:1]; }, keys(@"67")],   // Ctrl+Alt+Shift+C (⌘⌥⇧C)
        @[@"", NSNull.null, NSNull.null],
        @[@"Validate JSON", ^{ [wc runJsonTool:2]; }, keys(@"74")],   // Ctrl+Alt+Shift+J (⌘⌥⇧J)
        // new items only ever go at the end: shortcuts.xml keys plugin commands by their index
        @[@"", NSNull.null, NSNull.null],
        @[@"Sort Keys A-Z", ^{ [wc runDevTool:TPDevToolJsonSortKeys]; }, NSNull.null],
        @[@"Escape as JSON String", ^{ [wc runDevTool:TPDevToolJsonEscape]; }, NSNull.null],
        @[@"Unescape JSON String", ^{ [wc runDevTool:TPDevToolJsonUnescape]; }, NSNull.null],
        @[@"", NSNull.null, NSNull.null],
        @[@"JSON to CSV (New Tab)", ^{ [wc runDevTool:TPDevToolJsonToCsv]; }, NSNull.null],
        @[@"Decode JWT (New Tab)", ^{ [wc runDevTool:TPDevToolJwtDecode]; }, NSNull.null],
    ]];
    void (^(^tool)(TPDevTool))(void) = ^(TPDevTool t) { return ^{ [wc runDevTool:t]; }; };
    [self registerBuiltInToolNamed:@"XML Tools" module:@"XMLTools" items:@[
        @[@"Pretty Print XML", tool(TPDevToolXmlPretty), keys(@"66")],   // Ctrl+Alt+Shift+B (⌘⌥⇧B)
        @[@"Compress XML", tool(TPDevToolXmlCompress), NSNull.null],
        @[@"", NSNull.null, NSNull.null],
        @[@"Check XML Is Well-Formed", tool(TPDevToolXmlValidate), NSNull.null],
        @[@"XPath Query...", tool(TPDevToolXPath), NSNull.null],
    ]];
    [self registerBuiltInToolNamed:@"Encode - Decode" module:@"EncodeDecode" items:@[
        @[@"Base64 Encode", tool(TPDevToolBase64Encode), NSNull.null],
        @[@"Base64 Decode", tool(TPDevToolBase64Decode), NSNull.null],
        @[@"", NSNull.null, NSNull.null],
        @[@"URL Encode", tool(TPDevToolURLEncode), NSNull.null],
        @[@"URL Decode", tool(TPDevToolURLDecode), NSNull.null],
        @[@"", NSNull.null, NSNull.null],
        @[@"HTML Entities Encode", tool(TPDevToolHTMLEncode), NSNull.null],
        @[@"HTML Entities Decode", tool(TPDevToolHTMLDecode), NSNull.null],
        @[@"", NSNull.null, NSNull.null],
        @[@"Unicode Escape (\\uXXXX)", tool(TPDevToolUnicodeEscape), NSNull.null],
        @[@"Unicode Unescape", tool(TPDevToolUnicodeUnescape), NSNull.null],
        @[@"", NSNull.null, NSNull.null],
        @[@"Text to Hex Bytes", tool(TPDevToolHexEncode), NSNull.null],
        @[@"Hex Bytes to Text", tool(TPDevToolHexDecode), NSNull.null],
    ]];
    [self registerBuiltInToolNamed:@"Text Tools" module:@"TextTools" items:@[
        @[@"camelCase", tool(TPDevToolCamel), NSNull.null],
        @[@"PascalCase", tool(TPDevToolPascal), NSNull.null],
        @[@"snake_case", tool(TPDevToolSnake), NSNull.null],
        @[@"CONSTANT_CASE", tool(TPDevToolConstant), NSNull.null],
        @[@"kebab-case", tool(TPDevToolKebab), NSNull.null],
        @[@"dot.case", tool(TPDevToolDot), NSNull.null],
        @[@"", NSNull.null, NSNull.null],
        @[@"Align on =", tool(TPDevToolAlignEquals), NSNull.null],
        @[@"Align on :", tool(TPDevToolAlignColon), NSNull.null],
        @[@"Sort Lines by Length", tool(TPDevToolSortByLength), NSNull.null],
        @[@"", NSNull.null, NSNull.null],
        @[@"Escape for Regular Expression", tool(TPDevToolEscapeRegex), NSNull.null],
    ]];
    [self registerBuiltInToolNamed:@"Convert" module:@"Convert" items:@[
        @[@"CSV to JSON (New Tab)", tool(TPDevToolCsvToJson), NSNull.null],
        @[@"CSV to Markdown Table (New Tab)", tool(TPDevToolCsvToMarkdown), NSNull.null],
        @[@"JSON to CSV (New Tab)", tool(TPDevToolJsonToCsv), NSNull.null],
        @[@"", NSNull.null, NSNull.null],
        @[@"Unix Time <-> Date", tool(TPDevToolTimestamp), NSNull.null],
        @[@"Decimal to Hex", tool(TPDevToolDecToHex), NSNull.null],
        @[@"Hex to Decimal", tool(TPDevToolHexToDec), NSNull.null],
    ]];
    [self registerBuiltInToolNamed:@"Code Formatter" module:@"CodeFormatter" items:@[
        @[@"Format Document (by language)", tool(TPDevToolFormatAuto), keys(@"76")],   // Ctrl+Alt+Shift+L (⌥⇧⌘L)
        @[@"", NSNull.null, NSNull.null],
        @[@"Format SQL", tool(TPDevToolFormatSQL), NSNull.null],
        @[@"Format HTML", tool(TPDevToolFormatHTML), NSNull.null],
        @[@"Format CSS", tool(TPDevToolFormatCSS), NSNull.null],
        @[@"Minify CSS", tool(TPDevToolMinifyCSS), NSNull.null],
    ]];
    [self registerBuiltInToolNamed:@"Insert" module:@"Insert" items:@[
        @[@"UUID", tool(TPDevToolInsertUUID), keys(@"73")],   // Ctrl+Alt+Shift+I (⌘⌥⇧I)
        @[@"Unix Timestamp", tool(TPDevToolInsertUnixTime), NSNull.null],
        @[@"Date and Time (ISO 8601)", tool(TPDevToolInsertISODate), NSNull.null],
        @[@"", NSNull.null, NSNull.null],
        @[@"Lorem Ipsum Paragraph", tool(TPDevToolInsertLorem), NSNull.null],
        @[@"Random Password", tool(TPDevToolInsertPassword), NSNull.null],
    ]];
    [self rebuildPluginsMenu];
}

- (void)runImportDialog {
    NSOpenPanel *p = [NSOpenPanel openPanel];
    p.title = @"Import plugin(s)";
    p.allowsMultipleSelection = YES;
    p.canChooseDirectories = NO;
    p.treatsFilePackagesAsDirectories = NO;
    p.allowedFileTypes = @[@"tpplugin"];
    if ([p runModal] != NSModalResponseOK) return;
    NSMutableArray *paths = [NSMutableArray array];
    for (NSURL *u in p.URLs) [paths addObject:u.path];
    [self importPluginsFromPaths:paths];
}

// upstream Notepad_plus::addNppPlugins: copy to <plugins>/<name>/<name>.<ext>, overwriting
- (NSArray<NSString *> *)importPluginsFromPaths:(NSArray<NSString *> *)paths {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *copied = [NSMutableArray array];
    BOOL needRestart = NO;
    NSMutableArray *errors = [NSMutableArray array];
    for (NSString *src in paths) {
        NSString *nameExt = src.lastPathComponent, *name = nameExt.stringByDeletingPathExtension;
        if (!name.length || ![nameExt.pathExtension.lowercaseString isEqualToString:@"tpplugin"]) continue;
        NSString *dir = [self.pluginsDirectory stringByAppendingPathComponent:name];
        NSString *dest = [dir stringByAppendingPathComponent:nameExt];
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        BOOL loaded = NO;
        for (TPPlugin *pl in _plugins) if ([pl.moduleName caseInsensitiveCompare:nameExt] == NSOrderedSame && !pl.removed) loaded = YES;
        if (![src.stringByStandardizingPath isEqualToString:dest.stringByStandardizingPath]) {
            [fm removeItemAtPath:dest error:nil];
            NSError *e = nil;
            if (![fm copyItemAtPath:src toPath:dest error:&e]) { [errors addObject:[NSString stringWithFormat:@"%@: %@", nameExt, e.localizedDescription]]; continue; }
        }
        [copied addObject:dest];
        if (loaded) { needRestart = YES; continue; }   // the running copy cannot be replaced in this process
        NSString *err = nil;
        if (![self loadPluginAtPath:dest error:&err]) [errors addObject:[NSString stringWithFormat:@"%@: %@", nameExt, err]];
    }
    [self afterLoading];
    TPMainWindowController *c = _controller;
    if (errors.count) [c showMessage:@"Some plugins could not be loaded" informative:[errors componentsJoinedByString:@"\n"]];
    else if (needRestart) [c showMessage:@"You have to restart Textpad++ to load plugins you installed." informative:@"Textpad++ needs to be relaunched"];
    return copied;
}

- (TPPlugin *)registerBuiltInToolNamed:(NSString *)name module:(NSString *)module items:(NSArray<NSArray *> *)items {
    for (TPPlugin *p in _plugins) if (p.builtIn && [p.moduleName isEqualToString:module]) return p;
    TPPlugin *p = [TPPlugin new];
    p.builtIn = YES;
    p.moduleName = module;
    p.displayName = name;
    p.path = NSBundle.mainBundle.bundlePath;
    p.version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    NSMutableArray *names = [NSMutableArray array], *cmds = [NSMutableArray array];
    __weak TPPluginHost *ws = self;
    for (NSArray *it in items) {
        if ([it[0] length] == 0) { [names addObject:@""]; [cmds addObject:@0]; continue; }
        const int cmd = _nextCmd++;
        void (^run)(void) = it[1];
        [names addObject:it[0]];
        [cmds addObject:@(cmd)];
        [reg setLabel:it[0] forDynamicCommand:cmd];
        [reg registerCommand:cmd handler:^(int c) { run(); }
                     enabled:^BOOL(int c) { return ws.controller.currentDocument != nil; } checked:nil];
        if ([it[2] isKindOfClass:NSDictionary.class])
            if (TPKeyBinding *kb = [reg bindingFromUpstreamAttributes:it[2] command:cmd]) if (!kb.isEmpty) { _defaults[@(cmd)] = kb; [reg setUserBinding:kb forCommand:cmd]; }
    }
    p.itemNames = names;
    p.commands = cmds;
    [_plugins addObject:p];
    [self rebuildPluginsMenu];
    return p;
}

// upstream PluginsManager::loadPlugins: <plugins>/<name>/<name>.dll, folders in name order
- (void)loadInstalledPlugins {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *dirs = [[fm contentsOfDirectoryAtPath:self.pluginsDirectory error:nil] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *d in dirs) {
        if ([d isEqualToString:@"Config"] || [d hasPrefix:@"."]) continue;
        NSString *bundle = [[self.pluginsDirectory stringByAppendingPathComponent:d] stringByAppendingPathComponent:[d stringByAppendingPathExtension:@"tpplugin"]];
        if (![fm fileExistsAtPath:bundle]) continue;
        [self loadPluginAtPath:bundle error:nil];
    }
    [self afterLoading];
    [self notify:NPPN_TBMODIFICATION document:nil];   // upstream: plugins add their toolbar icons now
}

- (void)afterLoading {
    [self applyShortcutsFrom:nil];
    [[TPCommandRegistry shared] reapplyBindings];
    [self rebuildPluginsMenu];
}

- (void)recordIncompatible:(NSString *)path reason:(NSString *)reason {
    for (NSDictionary *d in [_incompatible copy]) if ([d[@"path"] isEqualToString:path]) [_incompatible removeObject:d];
    [_incompatible addObject:@{@"path": path, @"reason": reason}];
}

// upstream PluginsManager::loadPluginFromPath
- (TPPlugin *)loadPluginAtPath:(NSString *)path error:(NSString **)error {
    NSString *module = path.lastPathComponent;
    for (TPPlugin *p in _plugins)
        if ([p.moduleName caseInsensitiveCompare:module] == NSOrderedSame && !p.removed) {
            if (error) *error = @"A plugin with this name is already loaded";
            return nil;
        }
    auto fail = [&](NSString *reason) -> TPPlugin * {
        [self recordIncompatible:path reason:reason];
        if (error) *error = reason;
        return nil;
    };
    CFBundleRef b = CFBundleCreate(kCFAllocatorDefault, (__bridge CFURLRef)[NSURL fileURLWithPath:path]);
    if (!b) return fail(@"Not a plugin bundle");
    CFErrorRef cfErr = nullptr;
    if (!CFBundleLoadExecutableAndReturnError(b, &cfErr)) {
        NSString *why = @"";
        if (cfErr) { NSError *ne = (__bridge_transfer NSError *)cfErr; why = ne.localizedDescription ?: @""; }
        CFRelease(b);
        return fail(why.length ? why : @"The plugin cannot be loaded (wrong architecture or not signed)");
    }
    auto sym = [&](CFStringRef n) { return CFBundleGetFunctionPointerForName(b, n); };
    auto setInfo = reinterpret_cast<PFUNCSETINFO>(sym(CFSTR("setInfo")));
    auto getName = reinterpret_cast<PFUNCGETNAME>(sym(CFSTR("getName")));
    auto getFuncs = reinterpret_cast<PFUNCGETFUNCSARRAY>(sym(CFSTR("getFuncsArray")));
    auto notified = reinterpret_cast<PBENOTIFIED>(sym(CFSTR("beNotified")));
    auto proc = reinterpret_cast<PMESSAGEPROC>(sym(CFSTR("messageProc")));
    auto apiVersion = reinterpret_cast<PFUNCAPIVERSION>(sym(CFSTR("tppPluginAPIVersion")));
    NSString *missing = !setInfo ? @"setInfo" : !getName ? @"getName" : !getFuncs ? @"getFuncsArray" : !notified ? @"beNotified" : !proc ? @"messageProc" : nil;
    if (missing) { CFRelease(b); return fail([NSString stringWithFormat:@"Missing \"%@\" function", missing]); }
    if (apiVersion && apiVersion() != TPP_PLUGIN_API_VERSION) {
        CFRelease(b);
        return fail([NSString stringWithFormat:@"Plugin API version %d, Textpad++ supports %d", apiVersion(), TPP_PLUGIN_API_VERSION]);
    }
    TPPlugin *p = [TPPlugin new];
    p.bundle = b;
    p.path = path;
    p.moduleName = module;
    p.beNotified = notified;
    p.messageProc = proc;
    NSDictionary *info = CFBridgingRelease(CFBundleCopyInfoDictionaryInDirectory((__bridge CFURLRef)[NSURL fileURLWithPath:path]));
    p.version = info[@"CFBundleShortVersionString"] ?: @"";
    NppData data{&kNppHandle, &kSciMainHandle, &kSciSubHandle, hostSendMessage};
    int count = 0;
    FuncItem *items = nullptr;
    const char *name = nullptr;
    try {
        setInfo(data);
        name = getName();
        items = getFuncs(&count);
    } catch (...) {
        return fail(@"The plugin crashed while being loaded");
    }
    if (!items || count <= 0) return fail(@"Missing \"FuncItems\" array, or the count of FuncItem items is 0");
    p.displayName = name && *name ? @(name) : module.stringByDeletingPathExtension;
    p.funcItems = items;
    p.funcCount = count;
    // upstream addInMenuFromPMIndex: one command id per function, separators for NULL functions
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    NSMutableArray *names = [NSMutableArray array], *cmds = [NSMutableArray array];
    __weak TPPlugin *wp = p;
    __weak TPPluginHost *ws = self;
    for (int j = 0; j < count; ++j) {
        FuncItem &fi = items[j];
        if (!fi._pFunc) { [names addObject:@""]; [cmds addObject:@0]; continue; }
        if (_nextCmd > TP_ID_PLUGINS_CMD_LIMIT) break;
        const int cmd = _nextCmd++;
        fi._cmdID = cmd;
        char nameBuf[menuItemSize + 1] = {};
        memcpy(nameBuf, fi._itemName, menuItemSize);
        NSString *itemName = @(nameBuf) ?: @"";
        [names addObject:itemName];
        [cmds addObject:@(cmd)];
        PFUNCPLUGINCMD fn = fi._pFunc;
        [reg setLabel:itemName forDynamicCommand:cmd];
        [reg registerCommand:cmd handler:^(int c) { [ws runPlugin:wp function:fn]; }
                     enabled:^BOOL(int c) { return wp && !wp.removed; }
                     checked:^BOOL(int c) { TPPluginHost *s = ws; return s && [s->_checked containsObject:@(c)]; }];
        if (fi._init2Check) [_checked addObject:@(cmd)];
        if (fi._pShKey && fi._pShKey->_key) {
            NSDictionary *attrs = @{@"Ctrl": fi._pShKey->_isCtrl ? @"yes" : @"no", @"Alt": fi._pShKey->_isAlt ? @"yes" : @"no",
                                    @"Shift": fi._pShKey->_isShift ? @"yes" : @"no", @"Key": [@(fi._pShKey->_key) stringValue]};
            if (TPKeyBinding *kb = [reg bindingFromUpstreamAttributes:attrs command:cmd]) {
                if (!kb.isEmpty) { _defaults[@(cmd)] = kb; [reg setUserBinding:kb forCommand:cmd]; }
            }
        }
    }
    p.itemNames = names;
    p.commands = cmds;
    [_plugins addObject:p];
    for (NSDictionary *d in [_incompatible copy]) if ([d[@"path"] isEqualToString:path]) [_incompatible removeObject:d];
    // a plugin loaded after launch still gets NPPN_READY (upstream sends it to every plugin once Notepad++ is up)
    if (_controller.window.isVisible || _controller.selfTestMode) {
        [self notifyPlugin:p code:NPPN_TBMODIFICATION document:nil];
        [self notifyPlugin:p code:NPPN_READY document:nil];
    }
    return p;
}

- (void)runPlugin:(TPPlugin *)p function:(PFUNCPLUGINCMD)fn {
    if (!p || p.removed || !fn) return;
    try { fn(); }
    catch (...) {
        [_controller showMessage:[NSString stringWithFormat:@"%@ just crashed in runPluginCommand", p.moduleName]
                     informative:@"The plugin raised an exception. Save your work; consider removing the plugin (Plugins > Plugins Admin...)."];
    }
}

- (BOOL)removePlugin:(TPPlugin *)plugin error:(NSString **)error {
    NSString *folder = plugin.path.stringByDeletingLastPathComponent;
    NSURL *trashed = nil;
    NSError *e = nil;
    BOOL ok = _controller.selfTestMode ? [[NSFileManager defaultManager] removeItemAtPath:folder error:&e]   // not the user's Trash
                                       : [[NSFileManager defaultManager] trashItemAtURL:[NSURL fileURLWithPath:folder] resultingItemURL:&trashed error:&e];
    if (!ok) {
        if (error) *error = e.localizedDescription;
        return NO;
    }
    plugin.removed = YES;   // its code stays mapped until Textpad++ quits; commands, menu, panels and buttons go now
    for (NSNumber *n in plugin.commands) if (n.intValue) [_controller.toolbar removePluginButton:n.intValue];
    for (TPPluginPanel *x in [_pluginPanels copy])
        if ([x.identifier hasPrefix:[NSString stringWithFormat:@"plugin.%@.", plugin.moduleName]]) { [_controller.docks hidePanel:x.identifier]; [_pluginPanels removeObject:x]; }
    for (NSNumber *n in plugin.commands) if (n.intValue) [[TPCommandRegistry shared] setUserBinding:nil forCommand:n.intValue];
    [[TPCommandRegistry shared] reapplyBindings];
    [self rebuildPluginsMenu];
    return YES;
}

// upstream PluginsManager::initMenu: plugin sub-menus, separator, Plugins Admin..., separator, Open Plugins Folder...
- (void)rebuildPluginsMenu {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    NSMenu *menu = [reg topLevelMenuNamed:@"Plugins"];
    if (!menu) return;
    for (NSMenuItem *mi in [menu.itemArray copy]) if ([mi.representedObject isEqual:@"plugin-extra"]) [menu removeItem:mi];
    NSInteger at = 0;
    auto insert = [&](NSMenuItem *mi) { mi.representedObject = @"plugin-extra"; [menu insertItem:mi atIndex:at++]; };
    NSInteger live = 0;
    for (TPPlugin *p in _plugins) {
        if (p.removed) continue;
        ++live;
        NSMenu *sub = [[NSMenu alloc] initWithTitle:p.displayName];
        for (NSUInteger j = 0; j < p.commands.count; ++j) {
            const int cmd = p.commands[j].intValue;
            if (!cmd) { [sub addItem:[NSMenuItem separatorItem]]; continue; }
            NSMenuItem *mi = [reg makeItemForCommand:cmd];
            [reg applyBindingToItem:mi];
            [sub addItem:mi];
        }
        NSMenuItem *holder = [[NSMenuItem alloc] initWithTitle:p.displayName action:nil keyEquivalent:@""];
        holder.submenu = sub;
        insert(holder);
    }
    if (live) insert([NSMenuItem separatorItem]);
    NSMenuItem *admin = [reg makeItemForCommand:IDM_SETTING_PLUGINADM];
    admin.title = @"Plugins Admin...";
    insert(admin);
    insert([NSMenuItem separatorItem]);
}

// ---------------------------------------------------------------- notifications
- (void)notifyPlugin:(TPPlugin *)p code:(unsigned)code document:(TPDocument *)doc {
    if (p.removed) return;
    SCNotification scn = {};
    scn.nmhdr.code = code;
    scn.nmhdr.hwndFrom = &kNppHandle;
    scn.nmhdr.idFrom = doc ? doc.uid : 0;
    if (p.beNotified) { try { p.beNotified(&scn); } catch (...) {} }
}

- (void)notify:(unsigned)code document:(TPDocument *)doc {
    for (TPPlugin *p in [_plugins copy]) [self notifyPlugin:p code:code document:doc];
}

- (void)forwardScintillaNotification:(void *)scnPtr fromView:(int)viewIndex {
    if (!_plugins.count) return;
    SCNotification scn = *static_cast<SCNotification *>(scnPtr);
    scn.nmhdr.hwndFrom = viewIndex == 0 ? &kSciMainHandle : &kSciSubHandle;   // what plugins compare with their NppData
    for (TPPlugin *p in [_plugins copy]) if (!p.removed && p.beNotified) { try { p.beNotified(&scn); } catch (...) {} }
}

// ---------------------------------------------------------------- lookups
- (TPPlugin *)pluginForCommand:(int)cmd itemIndex:(NSInteger *)index {
    for (TPPlugin *p in _plugins) {
        NSUInteger j = [p.commands indexOfObject:@(cmd)];
        if (j != NSNotFound && cmd) { if (index) *index = (NSInteger)j; return p; }
    }
    return nil;
}

- (int)commandForPluginNamed:(NSString *)plugin item:(NSString *)item {
    for (TPPlugin *p in _plugins) {
        if (p.removed) continue;
        BOOL named = [p.displayName caseInsensitiveCompare:plugin] == NSOrderedSame ||
                     [p.moduleName.stringByDeletingPathExtension caseInsensitiveCompare:plugin] == NSOrderedSame ||
                     [p.moduleName caseInsensitiveCompare:plugin] == NSOrderedSame;
        if (!named) continue;
        for (NSUInteger j = 0; j < p.itemNames.count; ++j)
            if (p.commands[j].intValue && [p.itemNames[j] caseInsensitiveCompare:item] == NSOrderedSame) return p.commands[j].intValue;
    }
    return 0;
}

- (NSArray<NSArray *> *)shortcutRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (TPPlugin *p in _plugins) {
        if (p.removed) continue;
        for (NSUInteger j = 0; j < p.commands.count; ++j)
            if (p.commands[j].intValue) [rows addObject:@[p.commands[j], p.itemNames[j], p.moduleName]];
    }
    return rows;
}

// shortcuts.xml <PluginCommands><PluginCommand moduleName=… internalID=… Ctrl Alt Shift Key/> — customised ones only
- (void)writeShortcutsTo:(NSXMLElement *)pluginCommands {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    for (TPPlugin *p in _plugins) {
        if (p.removed) continue;
        for (NSUInteger j = 0; j < p.commands.count; ++j) {
            const int cmd = p.commands[j].intValue;
            if (!cmd) continue;
            TPKeyBinding *cur = [reg userBindingForCommand:cmd], *def = _defaults[@(cmd)];
            BOOL same = (!cur || cur.isEmpty) ? (!def || def.isEmpty)
                                              : (def && [cur.keyEquivalent isEqualToString:def.keyEquivalent] && cur.modifiers == def.modifiers);
            if (same) continue;
            NSXMLElement *e = [NSXMLElement elementWithName:@"PluginCommand"];
            [e addAttribute:[NSXMLNode attributeWithName:@"moduleName" stringValue:p.moduleName]];
            [e addAttribute:[NSXMLNode attributeWithName:@"internalID" stringValue:[@(j) stringValue]]];
            NSDictionary *attrs = [reg upstreamAttributesForBinding:cur];
            for (NSString *k in @[@"Ctrl", @"Alt", @"Shift", @"Key", @"Control"])
                if (attrs[k]) [e addAttribute:[NSXMLNode attributeWithName:k stringValue:attrs[k]]];
            [pluginCommands addChild:e];
        }
    }
}

extern "C" NSXMLDocument *TPCurrentShortcutsXml(void);

- (void)applyShortcutsFrom:(NSXMLDocument *)xml {
    xml = xml ?: TPCurrentShortcutsXml();
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    for (TPPlugin *p in _plugins)   // the plugin's own shortcuts first, then the user's changes
        for (NSNumber *n in p.commands) if (n.intValue) [reg setUserBinding:_defaults[n] forCommand:n.intValue];
    for (NSXMLElement *e in [xml nodesForXPath:@"//PluginCommands/PluginCommand" error:nil]) {
        NSString *module = [e attributeForName:@"moduleName"].stringValue;
        const NSInteger j = [e attributeForName:@"internalID"].stringValue.integerValue;
        for (TPPlugin *p in _plugins) {
            if (p.removed || [p.moduleName caseInsensitiveCompare:module ?: @""] != NSOrderedSame || j < 0 || j >= (NSInteger)p.commands.count) continue;
            const int cmd = p.commands[(NSUInteger)j].intValue;
            if (!cmd) continue;
            NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
            for (NSXMLNode *a in e.attributes) attrs[a.name] = a.stringValue;
            TPKeyBinding *b = [reg bindingFromUpstreamAttributes:attrs command:cmd];
            [reg setUserBinding:(b && !b.isEmpty) ? b : [TPKeyBinding bindingWithKey:@"" modifiers:0 command:cmd] forCommand:cmd];
        }
    }
}

// ---------------------------------------------------------------- NPPM_* (upstream NppBigSwitch.cpp)
- (TPDocument *)documentWithBufferID:(uintptr_t)bid {
    for (TPDocument *d in _controller.allDocuments) if (d.uid == bid) return d;
    return nil;
}

- (TPEditorPane *)paneForView:(intptr_t)view {
    TPMainWindowController *c = _controller;
    return view == SUB_VIEW ? c.subPane : c.mainPane;
}

- (NSString *)currentWord {
    ScintillaView *v = _controller.editor;
    sptr_t a = SCI(v, SCI_GETSELECTIONSTART), b = SCI(v, SCI_GETSELECTIONEND);
    if (a == b) {
        const sptr_t pos = SCI(v, SCI_GETCURRENTPOS);
        a = SCI(v, SCI_WORDSTARTPOSITION, pos, 1);
        b = SCI(v, SCI_WORDENDPOSITION, pos, 1);
    }
    return NSStr(sciGetRange(v, a, b));
}

- (intptr_t)sendNppMessage:(uint32_t)msg wParam:(uintptr_t)w lParam:(intptr_t)l {
    TPMainWindowController *c = _controller;
    if (!c) return 0;
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    TPDocument *cur = c.currentDocument;
    ScintillaView *ed = c.editor;
    switch (msg) {
        // ---- views and documents
        case NPPM_GETCURRENTSCINTILLA:
            if (l) *reinterpret_cast<int *>(l) = c.activePane == c.subPane ? 1 : 0;
            return 1;
        case NPPM_GETCURRENTVIEW: return c.activePane == c.subPane ? SUB_VIEW : MAIN_VIEW;
        case NPPM_GETNBOPENFILES:
            if (l == PRIMARY_VIEW) return (intptr_t)c.mainPane.documents.count;
            if (l == SECOND_VIEW) return (intptr_t)c.subPane.documents.count;
            return (intptr_t)(c.mainPane.documents.count + c.subPane.documents.count);
        case NPPM_GETCURRENTDOCINDEX: {
            TPEditorPane *p = [self paneForView:l];
            if (p.hidden || !p.currentDocument) return -1;
            return (intptr_t)[p indexOfDocument:p.currentDocument];
        }
        case NPPM_ACTIVATEDOC: {
            TPEditorPane *p = [self paneForView:(intptr_t)w];
            if (l < 0 || l >= (intptr_t)p.documents.count) return 0;
            [c activateDocument:p.documents[(NSUInteger)l] inPane:p];
            return 1;
        }
        case NPPM_GETCURRENTBUFFERID: return cur ? (intptr_t)cur.uid : 0;
        case NPPM_GETBUFFERIDFROMPOS: {
            TPEditorPane *p = [self paneForView:l];
            return w < p.documents.count ? (intptr_t)p.documents[w].uid : 0;
        }
        case NPPM_GETPOSFROMBUFFERID: {
            TPDocument *d = [self documentWithBufferID:w];
            if (!d) return -1;
            NSArray *order = l == SUB_VIEW ? @[c.subPane, c.mainPane] : @[c.mainPane, c.subPane];
            for (TPEditorPane *p in order) {
                NSInteger i = [p indexOfDocument:d];
                if (i != NSNotFound) return ((intptr_t)p.viewIndex << 30) | (intptr_t)i;
            }
            return -1;
        }
        case NPPM_GETFULLPATHFROMBUFFERID: {
            TPDocument *d = [self documentWithBufferID:w];
            return d ? copyOutLength(d.path ?: d.displayName, l) : -1;
        }
        case NPPM_GETBUFFERLANGTYPE: { TPDocument *d = [self documentWithBufferID:w]; return d ? langTypeOf(d) : -1; }
        case NPPM_GETBUFFERENCODING: { TPDocument *d = [self documentWithBufferID:w]; return d ? (intptr_t)d.encoding.mode : -1; }
        case NPPM_GETBUFFERFORMAT: { TPDocument *d = [self documentWithBufferID:w]; return d ? d.eolMode : -1; }
        case NPPM_SETBUFFERLANGTYPE: {
            TPDocument *d = [self documentWithBufferID:w];
            if (!d || l < 0 || l >= kLangCount || l == L_USER) return 0;
            [c setDocumentLanguage:d languageId:@(kLangRows[l].name)];
            return 1;
        }
        case NPPM_GETCURRENTLANGTYPE:
            if (l) *reinterpret_cast<int *>(l) = langTypeOf(cur);
            return 1;
        case NPPM_SETCURRENTLANGTYPE:
            if (!cur || l < 0 || l >= kLangCount || l == L_USER) return 0;
            [c setDocumentLanguage:cur languageId:@(kLangRows[l].name)];
            return 1;
        case NPPM_GETLANGUAGENAME:
            return (intptr_t)w < kLangCount ? copyOutLength(@(kLangRows[w].shortName), l) : -1;
        case NPPM_GETLANGUAGEDESC:
            return (intptr_t)w < kLangCount ? copyOutLength(@(kLangRows[w].longName), l) : -1;
        // ---- files
        case NPPM_DOOPEN: { NSString *p = strArg(l); return p && [c openFile:p] ? 1 : 0; }
        case NPPM_SWITCHTOFILE: {
            TPDocument *d = [c documentForPath:strArg(l) ?: @""];
            if (!d) return 0;
            [c activateDocument:d inPane:[c.subPane indexOfDocument:d] != NSNotFound && [c.mainPane indexOfDocument:d] == NSNotFound ? c.subPane : c.mainPane];
            return 1;
        }
        case NPPM_SAVECURRENTFILE: return cur && [c saveDocument:cur] == TPSaveOK;
        case NPPM_SAVEALLFILES: return [reg execute:IDM_FILE_SAVEALL];
        case NPPM_SAVEFILE: { TPDocument *d = [c documentForPath:strArg(l) ?: @""]; return d && [c saveDocument:d] == TPSaveOK; }
        case NPPM_SAVECURRENTFILEAS: {
            NSString *p = strArg(l);
            if (!cur || !p.length) return 0;
            return [c writeDocument:cur toPath:p updateDocument:w == 0 error:nil];
        }
        case NPPM_MENUCOMMAND: return [reg execute:static_cast<int>(l)];
        case NPPM_SETMENUITEMCHECK:
            if (l) [_checked addObject:@((int)w)]; else [_checked removeObject:@((int)w)];
            [c.toolbar refreshStates];
            return 1;
        // ---- paths and the current document (RUNCOMMAND_USER + VAR)
        case NPPM_GETFULLCURRENTPATH: return copyOut(cur.path ?: cur.displayName, w, l);
        case NPPM_GETCURRENTDIRECTORY: return copyOut(cur.path.stringByDeletingLastPathComponent ?: @"", w, l);
        case NPPM_GETFILENAME: return copyOut(cur.displayName, w, l);
        case NPPM_GETNAMEPART: return copyOut(cur.displayName.stringByDeletingPathExtension, w, l);
        case NPPM_GETEXTPART: {
            NSString *ext = cur.displayName.pathExtension;
            return copyOut(ext.length ? [@"." stringByAppendingString:ext] : @"", w, l);
        }
        case NPPM_GETCURRENTWORD: return copyOut([self currentWord], w, l);
        case NPPM_GETNPPDIRECTORY: return copyOut(NSBundle.mainBundle.executablePath.stringByDeletingLastPathComponent, w, l);
        case NPPM_GETNPPFULLFILEPATH: return copyOut(NSBundle.mainBundle.executablePath, w, l);
        case NPPM_GETCURRENTLINE: return SCI(ed, SCI_LINEFROMPOSITION, SCI(ed, SCI_GETCURRENTPOS));
        case NPPM_GETCURRENTCOLUMN: return SCI(ed, SCI_GETCOLUMN, SCI(ed, SCI_GETCURRENTPOS));
        case NPPM_GETCURRENTLINESTR: {
            const sptr_t line = SCI(ed, SCI_LINEFROMPOSITION, SCI(ed, SCI_GETCURRENTPOS));
            return copyOut(NSStr(sciGetRange(ed, SCI(ed, SCI_POSITIONFROMLINE, line), SCI(ed, SCI_GETLINEENDPOSITION, line))), w, l);
        }
        case NPPM_GETPLUGINSCONFIGDIR:
            [[NSFileManager defaultManager] createDirectoryAtPath:self.pluginsConfigDirectory withIntermediateDirectories:YES attributes:nil error:nil];
            return copyOut(self.pluginsConfigDirectory, w, l);
        case NPPM_GETPLUGINHOMEPATH: return copyOut(self.pluginsDirectory, w, l) ? (intptr_t)strlen(self.pluginsDirectory.UTF8String) : 0;
        case NPPM_GETNPPSETTINGSDIRPATH: return copyOut([TPSession shared].settingsDirectory, w, l) ? (intptr_t)strlen([TPSession shared].settingsDirectory.UTF8String) : 0;
        // ---- application
        case NPPM_GETNPPVERSION: return (8 << 16) | 991;   // the Notepad++ plugin API level: v8.9.9.1 ("8.991")
        case NPPM_ISDARKMODEENABLED: return [TPChrome dark];
        case NPPM_GETEDITORDEFAULTFOREGROUNDCOLOR: return SCI(ed, SCI_STYLEGETFORE, STYLE_DEFAULT);
        case NPPM_GETEDITORDEFAULTBACKGROUNDCOLOR: return SCI(ed, SCI_STYLEGETBACK, STYLE_DEFAULT);
        case NPPM_SETSTATUSBAR: {
            if ((intptr_t)w < 0 || w > 5) return 0;
            [c.statusBar setText:strArg(l) ?: @"" forPart:(NSInteger)w];
            return 1;
        }
        case NPPM_HIDETABBAR: case NPPM_HIDETOOLBAR: case NPPM_HIDESTATUSBAR: {
            NSString *key = msg == NPPM_HIDETABBAR ? @"pref.tabHidden" : msg == NPPM_HIDETOOLBAR ? @"pref.toolbarHidden" : @"pref.statusBarHidden";
            const BOOL was = [TPPrefs b:key];
            [TPPrefs set:@(l != 0) forKey:key];
            [c applyAllPreferences];
            return was;
        }
        case NPPM_ISTABBARHIDDEN: return [TPPrefs b:@"pref.tabHidden"];
        case NPPM_ISTOOLBARHIDDEN: return [TPPrefs b:@"pref.toolbarHidden"];
        case NPPM_ISSTATUSBARHIDDEN: return [TPPrefs b:@"pref.statusBarHidden"];
        // ---- allocation
        case NPPM_ALLOCATECMDID:
            if (!l || w == 0 || _nextDynamicCmd + (int)w - 1 > TP_ID_PLUGINS_CMD_DYNAMIC_LIMIT) return 0;
            *reinterpret_cast<int *>(l) = _nextDynamicCmd; _nextDynamicCmd += (int)w;
            return 1;
        case NPPM_ALLOCATEMARKER:
            if (!l || w == 0 || _nextMarker + (int)w - 1 > 12) return 0;   // 13-17 and 0: Git markers and Compare
            *reinterpret_cast<int *>(l) = _nextMarker; _nextMarker += (int)w;
            return 1;
        case NPPM_ALLOCATEINDICATOR:
            if (!l || w == 0 || _nextIndicator + (int)w - 1 > 19) return 0;   // 20: Compare
            *reinterpret_cast<int *>(l) = _nextIndicator; _nextIndicator += (int)w;
            return 1;
        // ---- docking dialogs and toolbar icons (NSView * / NSImage * instead of HWND / HICON)
        case NPPM_DMMREGASDCKDLG: {
            const tTbData *t = reinterpret_cast<const tTbData *>(l);
            if (!t || !t->hClient) return 0;
            NSView *v = (__bridge NSView *)t->hClient;
            TPPluginPanel *pp = nil;
            for (TPPluginPanel *x in _pluginPanels) if (x.view == v) pp = x;
            if (!pp) { pp = [TPPluginPanel new]; [_pluginPanels addObject:pp]; }
            pp.view = v;
            pp.identifier = [NSString stringWithFormat:@"plugin.%s.%d", t->pszModuleName ?: "?", t->dlgID];
            NSString *title = t->pszName ? @(t->pszName) : @"Plugin";
            if ((t->uMask & DWS_ADDINFO) && t->pszAddInfo && *t->pszAddInfo) title = [NSString stringWithFormat:@"%@ - %s", title, t->pszAddInfo];
            pp.title = title;
            pp.side = (t->uMask & DWS_DF_FLOATING) ? TPDockFloating : (TPDockSide)((t->uMask >> 28) & 3);
            [c.docks registerPanel:pp];
            [c.docks showPanel:pp.identifier];
            return 1;
        }
        case NPPM_DMMSHOW: case NPPM_DMMHIDE: case NPPM_DMMUPDATEDISPINFO: {
            NSView *v = (__bridge NSView *)reinterpret_cast<void *>(l);
            for (TPPluginPanel *x in _pluginPanels) {
                if (x.view != v) continue;
                if (msg == NPPM_DMMSHOW) [c.docks showPanel:x.identifier];
                else if (msg == NPPM_DMMHIDE) [c.docks hidePanel:x.identifier];
                else if ([c.docks isPanelVisible:x.identifier]) { [c.docks hidePanel:x.identifier]; [c.docks showPanel:x.identifier]; }
                return 1;
            }
            return 0;
        }
        case NPPM_DMMGETPLUGINHWNDBYNAME: {
            NSString *title = strArg((intptr_t)w);
            for (TPPluginPanel *x in _pluginPanels) if (title && [x.title hasPrefix:title]) return reinterpret_cast<intptr_t>((__bridge void *)x.view);
            return 0;
        }
        case NPPM_ADDTOOLBARICON_FORDARKMODE: case NPPM_ADDTOOLBARICON_DEPRECATED: {
            NSImage *light = nil, *dark = nil, *standard = nil;
            if (msg == NPPM_ADDTOOLBARICON_FORDARKMODE) {
                const toolbarIconsWithDarkMode *ti = reinterpret_cast<const toolbarIconsWithDarkMode *>(l);
                if (!ti) return 0;
                standard = (__bridge NSImage *)ti->hToolbarBmp; light = (__bridge NSImage *)ti->hToolbarIcon; dark = (__bridge NSImage *)ti->hToolbarIconDarkMode;
            } else {
                void *const *ti = reinterpret_cast<void *const *>(l);   // {hToolbarBmp, hToolbarIcon}
                if (!ti) return 0;
                standard = (__bridge NSImage *)ti[0]; light = (__bridge NSImage *)ti[1];
            }
            if (![light isKindOfClass:NSImage.class]) light = nil;
            if (![dark isKindOfClass:NSImage.class]) dark = nil;
            if (![standard isKindOfClass:NSImage.class]) standard = nil;
            if (!light && !dark && !standard) return 0;
            [c.toolbar addPluginButton:static_cast<int>(w) image:light darkImage:dark standardImage:standard tooltip:[reg labelForCommand:static_cast<int>(w)]];
            return 1;
        }
        case NPPM_GETTOOLBARICONSETCHOICE: {
            const NSInteger set = [TPPrefs i:@"pref.toolbarIconSet"];   // upstream: 0 Fluent small … 4 Standard small
            return set > 4 ? 0 : set;
        }
        // ---- plugin to plugin (upstream PluginsManager::relayPluginMessages)
        case NPPM_MSGTOPLUGIN: {
            NSString *dest = strArg((intptr_t)w);
            if (!dest.length || !l) return 0;
            for (TPPlugin *p in _plugins)
                if (!p.removed && [p.moduleName caseInsensitiveCompare:dest] == NSOrderedSame) {
                    if (p.messageProc) { try { p.messageProc(msg, w, l); } catch (...) {} }
                    return 1;
                }
            return 0;
        }
    }
    return 0;   // a Win32-only or not yet supported message (docs/PLUGINS.md)
}

@end

// ================================================================ the plugins' SendMessage
static intptr_t hostSendMessage(void *handle, uint32_t msg, uintptr_t w, intptr_t l) {
    TPPluginHost *h = [TPPluginHost shared];
    TPMainWindowController *c = h.controller;
    if (handle == &kNppHandle) return [h sendNppMessage:msg wParam:w lParam:l];
    if (handle == &kSciMainHandle && c) return SCI(c.mainPane.editor, msg, w, l);
    if (handle == &kSciSubHandle && c) return SCI(c.subPane.editor, msg, w, l);
    return 0;
}

extern "C" void TPPluginNotify(unsigned code, TPDocument *doc) {
    TPPluginHost *h = [TPPluginHost shared];
    if (h.plugins.count) [h notify:code document:doc];
}
