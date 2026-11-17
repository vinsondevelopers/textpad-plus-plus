// Textpad++ — plugin host (upstream PluginsManager): native macOS plugins, ".tpplugin" bundles that export the
// Notepad++ plugin functions with UTF-8 strings (sdk/TextpadPlusPlusPlugin.h, docs/PLUGINS.md). GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>
#import "app/MainWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@class TPDocument;

// upstream Notepad_plus_msgs.h NPPN_* (NPPN_FIRST 1000), for code that does not include the SDK header
enum : unsigned {
    NPPN_READY_CODE = 1001, NPPN_FILEBEFORECLOSE_CODE = 1003, NPPN_FILEOPENED_CODE = 1004, NPPN_FILECLOSED_CODE = 1005,
    NPPN_FILEBEFOREOPEN_CODE = 1006, NPPN_FILEBEFORESAVE_CODE = 1007, NPPN_FILESAVED_CODE = 1008, NPPN_SHUTDOWN_CODE = 1009,
    NPPN_BUFFERACTIVATED_CODE = 1010, NPPN_LANGCHANGED_CODE = 1011, NPPN_BEFORESHUTDOWN_CODE = 1019, NPPN_CANCELSHUTDOWN_CODE = 1020,
};

// upstream resource.h: ID_PLUGINS_CMD .. ID_PLUGINS_CMD_LIMIT, ID_PLUGINS_CMD_DYNAMIC .. _LIMIT
enum : int { TP_ID_PLUGINS_CMD = 22000, TP_ID_PLUGINS_CMD_LIMIT = 22999, TP_ID_PLUGINS_CMD_DYNAMIC = 23000, TP_ID_PLUGINS_CMD_DYNAMIC_LIMIT = 24999 };

@interface TPPlugin : NSObject
@property (nonatomic, readonly) NSString *moduleName;              // "SamplePlugin.tpplugin" (upstream: the DLL file name)
@property (nonatomic, readonly) NSString *displayName;             // getName(): the Plugins sub-menu
@property (nonatomic, readonly) NSString *path;
@property (nonatomic, readonly) NSString *version;                 // CFBundleShortVersionString, "" when absent
@property (nonatomic, readonly) NSArray<NSString *> *itemNames;    // FuncItem names, "" for separators
@property (nonatomic, readonly) NSArray<NSNumber *> *commands;     // command id per FuncItem, 0 for separators
@property (nonatomic, readonly) BOOL removed;                      // Plugins Admin > Remove: gone after a restart
@property (nonatomic, readonly) BOOL builtIn;                      // a tool that ships inside Textpad++ (JSON Tools)
- (nullable void *)functionNamed:(NSString *)symbol;              // a symbol of the plugin (tests)
@end

@interface TPPluginHost : NSObject
+ (instancetype)shared;
@property (nonatomic, weak, nullable) TPMainWindowController *controller;
@property (nonatomic, copy, nullable) NSString *pluginsDirectoryOverride;   // self-test
@property (nonatomic, readonly) NSString *pluginsDirectory;                // …/Textpad++/plugins
@property (nonatomic, readonly) NSString *pluginsConfigDirectory;          // …/plugins/Config (NPPM_GETPLUGINSCONFIGDIR)
@property (nonatomic, readonly) NSArray<TPPlugin *> *plugins;
@property (nonatomic, readonly) NSArray<NSDictionary<NSString *, NSString *> *> *incompatible;   // {path, reason}

- (void)registerCommands;                                          // Import plugin(s), Plugins Admin, built-in tools
// a built-in tool in the Plugins menu: items are @[title, handler, shortcut attributes or NSNull]; titles "" = separator
- (TPPlugin *)registerBuiltInToolNamed:(NSString *)name module:(NSString *)module items:(NSArray<NSArray *> *)items;
- (void)loadInstalledPlugins;                                      // <dir>/<Name>/<Name>.tpplugin, at launch
- (nullable TPPlugin *)loadPluginAtPath:(NSString *)path error:(NSString *_Nullable *_Nullable)error;
// Settings > Import > Import plugin(s): copy to <dir>/<Name>/<Name>.tpplugin and load. Returns the copied paths.
- (NSArray<NSString *> *)importPluginsFromPaths:(NSArray<NSString *> *)paths;
- (BOOL)removePlugin:(TPPlugin *)plugin error:(NSString *_Nullable *_Nullable)error;   // to the Trash; menu entries go now
- (void)rebuildPluginsMenu;

// notifications (upstream PluginsManager::notify)
- (void)notify:(unsigned)code document:(nullable TPDocument *)doc;   // NPPN_*
- (void)forwardScintillaNotification:(void *)scn fromView:(int)viewIndex;   // SCNotification *
- (intptr_t)sendNppMessage:(uint32_t)msg wParam:(uintptr_t)w lParam:(intptr_t)l;   // what a plugin's NPPM_* does

- (nullable TPPlugin *)pluginForCommand:(int)cmd itemIndex:(NSInteger *_Nullable)index;
- (int)commandForPluginNamed:(NSString *)plugin item:(NSString *)item;   // contextMenu.xml PluginEntryName
- (NSArray<NSArray *> *)shortcutRows;                                    // [cmd, item name, module name] (Shortcut Mapper)
- (void)writeShortcutsTo:(NSXMLElement *)pluginCommands;                 // shortcuts.xml <PluginCommands>
- (void)applyShortcutsFrom:(nullable NSXMLDocument *)shortcutsXml;
@end

#ifdef __cplusplus
extern "C" {
#endif
void TPPluginNotify(unsigned code, TPDocument *_Nullable doc);   // no-op without plugins
#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
