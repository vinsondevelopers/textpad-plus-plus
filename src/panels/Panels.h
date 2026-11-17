// Textpad++ — docking panels: Document List, Document Map, Function List, Folder as Workspace, Project Panels,
// Character Panel, Clipboard History (upstream WinControls/*). GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>
#import "panels/DockManager.h"
#import "ScintillaView.h"

#import "app/MainWindowController.h"
@class TPDocument, TPEditorPane, TPTabBarView;

NS_ASSUME_NONNULL_BEGIN

// View > Document List (upstream VerticalFileSwitcher)
@interface TPDocumentListPanel : NSObject <TPPanel, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate>
- (instancetype)initWithController:(TPMainWindowController *)c;
@property (nonatomic, readonly) NSTableView *table;
@property (nonatomic, readonly) NSArray<TPDocument *> *rows;        // displayed order
@property (nonatomic, readonly) NSArray<TPDocument *> *selectedDocuments;
- (void)reload;
- (void)activateRow:(NSInteger)row;                                 // a click on a row
@end

// View > Document Map (upstream DocumentMap): the current document at a small zoom with the visible zone
@interface TPDocumentMapPanel : NSObject <TPPanel>
- (instancetype)initWithController:(TPMainWindowController *)c;
@property (nonatomic, readonly) ScintillaView *mapView;
@property (nonatomic, readonly) NSRect visibleZone;                 // in mapView coordinates
- (void)scrollEditorToMapPoint:(NSPoint)p;                          // what a click / drag in the map does
- (void)sync;
// Preferences > MISC. > Document Peeker > Peek on document map: another document shown while its tab is hovered
@property (nonatomic, weak, nullable) TPDocument *peekDocument;
@property (nonatomic, readonly, nullable) TPDocument *shownDocument;
@end

// Preferences > MISC. > Document Peeker > Peek on tab (upstream DocumentPeeker): a small view of the hovered
// tab's document below the tab, at the Document Map zoom
@interface TPDocumentPeeker : NSObject
- (instancetype)initWithController:(TPMainWindowController *)c;
@property (nonatomic, readonly) NSPanel *window;
@property (nonatomic, readonly) ScintillaView *peekView;
@property (nonatomic, readonly, nullable) TPDocument *document;     // nil when hidden
- (void)showDocument:(TPDocument *)doc fromPane:(TPEditorPane *)pane belowScreenPoint:(NSPoint)p;
- (void)hide;
@end

// View > Function List (upstream FunctionListPanel + functionParser): parser rules from functionList/*.xml
@interface TPFunctionListPanel : NSObject <TPPanel>
- (instancetype)initWithController:(TPMainWindowController *)c;
@property (nonatomic, readonly) NSOutlineView *outline;
@property (nonatomic) BOOL sorted;
@property (nonatomic, copy) NSString *filter;
@property (nonatomic, readonly) NSArray<NSString *> *leafNames;     // "Class::method" or "function", display order
@property (nonatomic, readonly, nullable) NSString *markedEntryName; // entry selected for the caret line
- (void)reload;
- (BOOL)openEntryNamed:(NSString *)name;                            // what a double-click on the entry does
@end

// View > Folder as Workspace (upstream FileBrowser)
@interface TPFSNode : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic) BOOL isDir, isRoot, isLink;
@property (nonatomic, weak, nullable) TPFSNode *parent;
@property (nonatomic, strong, nullable) NSMutableArray<TPFSNode *> *children;   // nil until expanded
@end

@interface TPFolderAsWorkspacePanel : NSObject <TPPanel>
- (instancetype)initWithController:(TPMainWindowController *)c;
@property (nonatomic, readonly) NSOutlineView *outline;
@property (nonatomic, readonly) NSArray<NSString *> *rootPaths;
- (void)addRootFolder:(NSString *)path;
- (void)removeRoot:(NSString *)path;
- (void)removeAllRoots;
- (BOOL)selectPath:(NSString *)path;                 // expands to the item and selects it
- (void)expandAll;
- (void)collapseAll;
- (void)locateCurrentFile;
- (void)refreshFolder:(NSString *)path;              // FSEvents callback
- (nullable TPFSNode *)selectedNode;
- (BOOL)openNode:(nullable TPFSNode *)node;          // double-click on a file
@end

// View > Project Panel 1–3 (upstream ProjectPanel; workspace files: <Project>/<Folder>/<File name=…>)
typedef NS_ENUM(NSInteger, TPProjNodeKind) { TPProjNodeWorkspace, TPProjNodeProject, TPProjNodeFolder, TPProjNodeFile };
@interface TPProjNode : NSObject
@property (nonatomic) TPProjNodeKind kind;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *filePath;
@property (nonatomic, strong, nullable) NSMutableArray<TPProjNode *> *children;
@property (nonatomic, weak, nullable) TPProjNode *parent;
@end

@interface TPProjectPanel : NSObject <TPPanel>
- (instancetype)initWithController:(TPMainWindowController *)c index:(NSInteger)index;
@property (nonatomic, readonly) NSInteger index;
@property (nonatomic, readonly) NSOutlineView *outline;
@property (nonatomic, readonly) TPProjNode *root;
@property (nonatomic, readonly, nullable) NSString *workspacePath;
@property (nonatomic) BOOL dirty;
- (void)newWorkspace;
- (BOOL)openWorkspace:(NSString *)path;
- (BOOL)saveWorkspaceTo:(NSString *)path asCopy:(BOOL)copy;
- (BOOL)saveWorkspace;
- (void)reloadWorkspace;
- (BOOL)saveIfDirtyWithTitle:(NSString *)title;      // NO when the user cancels
- (TPProjNode *)addProjectNamed:(nullable NSString *)name;
- (nullable TPProjNode *)addFolderNamed:(nullable NSString *)name to:(TPProjNode *)parent;
- (void)addFiles:(NSArray<NSString *> *)paths to:(TPProjNode *)parent;
- (void)addFilesFromDirectory:(NSString *)dir to:(TPProjNode *)parent;
- (void)removeNode:(TPProjNode *)node;
- (void)renameNode:(TPProjNode *)node to:(NSString *)name;
- (void)moveNode:(TPProjNode *)node by:(NSInteger)delta;
- (nullable TPProjNode *)nodeNamed:(NSString *)name;
- (NSArray<NSString *> *)allFilePaths;
- (BOOL)openNode:(TPProjNode *)node;
@end

// Edit > Character Panel (upstream AnsiCharPanel): Value, Hex, Character, HTML Name, HTML Decimal, HTML Hexadecimal
@interface TPCharacterPanel : NSObject <TPPanel>
- (instancetype)initWithController:(TPMainWindowController *)c;
@property (nonatomic, readonly) NSTableView *table;
- (NSString *)textForColumn:(NSInteger)column row:(NSInteger)row;
- (void)insertCharacter:(unsigned char)byte;                        // double-click in the Character column
- (void)insertText:(NSString *)text;                                // double-click in another column
@end

// Edit > Clipboard History (upstream ClipboardHistoryPanel)
@interface TPClipboardHistoryPanel : NSObject <TPPanel>
- (instancetype)initWithController:(TPMainWindowController *)c;
@property (nonatomic, readonly) NSTableView *table;
@property (nonatomic, readonly) NSArray<NSString *> *entries;       // newest first
- (void)checkPasteboard;                                            // polled every 0.5 s
- (BOOL)pasteEntryAtIndex:(NSInteger)index;                         // double-click
@end

#ifdef __cplusplus
extern "C" {
#endif
NSString *_Nullable TPPowerShellPath(void);              // pwsh when installed (Homebrew, Microsoft package)
void TPOpenTerminalAt(NSString *dir, BOOL powershell);  // Terminal (or pwsh in Terminal) in a folder
#ifdef __cplusplus
}
#endif

@interface TPMainWindowController (Panels)
- (void)registerPanelCommands;                                      // after the other command registrations
- (void)restorePanelsForLaunch;                                     // re-open the panels that were open
@property (nonatomic, readonly) TPDocumentListPanel *documentListPanel;
@property (nonatomic, readonly) TPDocumentMapPanel *documentMapPanel;
@property (nonatomic, readonly) TPFunctionListPanel *functionListPanel;
@property (nonatomic, readonly) TPFolderAsWorkspacePanel *folderAsWorkspacePanel;
@property (nonatomic, readonly) TPCharacterPanel *characterPanel;
@property (nonatomic, readonly) TPClipboardHistoryPanel *clipboardHistoryPanel;
@property (nonatomic, readonly) TPDocumentPeeker *documentPeeker;
- (void)tabBar:(TPTabBarView *)bar didHoverIndex:(NSInteger)index;   // Document Peeker
- (TPProjectPanel *)projectPanel:(NSInteger)index;                 // 1…3
- (void)showFindInProjectsForPanel:(NSInteger)index;
- (BOOL)saveDirtyWorkspacesForQuit;                                 // NO when the user cancels
@end

NS_ASSUME_NONNULL_END
