// Textpad++ — main window (upstream equivalent: Notepad_plus / Notepad_plus_Window).
// GPL-3.0-or-later.
#pragma once

#import <Cocoa/Cocoa.h>
#import "app/Sci.h"
#import "app/EditorPane.h"
#import "app/Document.h"
#import "app/ToolbarView.h"
#import "commands/CommandRegistry.h"
#include "core/Encoding.h"
#include <string>
#include <vector>

@class TPDockManager;
@class TPIncrementalSearchBar;
@class TPFindReplaceController;
@class TPUserLang;
@class TPSearchResultsPanel;

NS_ASSUME_NONNULL_BEGIN

BOOL TPSafeWriteFile(NSString *path, const std::string &bytes, NSString *_Nullable *_Nullable error);
typedef BOOL (^TPByteSink)(const char *data, size_t len);
// the same safe write, with the bytes handed over in pieces (large documents are never copied whole)
BOOL TPSafeWriteFileProducer(NSString *path, BOOL (^produce)(TPByteSink sink), NSString *_Nullable *_Nullable error);

typedef NS_ENUM(NSInteger, TPSaveResult) { TPSaveOK, TPSaveCancelled, TPSaveFailed };

#ifdef __cplusplus
extern "C" {
#endif
BOOL TPAlertTextIsLong(NSString *text);
void TPSetAlertText(NSAlert *alert, NSString *text);   // long text scrolls inside a fixed-size box
#ifdef __cplusplus
}
#endif

@interface TPMainWindowController : NSWindowController <NSWindowDelegate, TPTabBarDelegate, TPEditorPaneOwner, NSMenuDelegate>

@property (nonatomic, readonly) TPEditorPane *mainPane;
@property (nonatomic, readonly) TPEditorPane *subPane;
@property (nonatomic, readonly) TPEditorPane *activePane;
@property (nonatomic, readonly) TPEditorPane *otherPane;
@property (nonatomic, readonly) ScintillaView *editor;                 // active pane's Scintilla view
@property (nonatomic, readonly, nullable) TPDocument *currentDocument;
@property (nonatomic, readonly) NSArray<TPDocument *> *allDocuments;   // unique, main view order then sub view
@property (nonatomic, readonly) ScintillaView *worker;                 // hidden view for background buffers
@property (nonatomic, readonly) TPStatusBarView *statusBar;
@property (nonatomic, readonly) TPToolbarView *toolbar;
@property (nonatomic, readonly) TPDockManager *docks;                    // docking panels
@property (nonatomic, readonly) TPIncrementalSearchBar *incrementalSearchBar;
@property (nonatomic, strong, readonly) TPFindReplaceController *findController;
@property (nonatomic, strong, readonly) TPSearchResultsPanel *resultsPanel;
@property (nonatomic, readonly) NSSplitView *viewSplitter;   // main | sub view, side by side or stacked
- (void)rotateViews;                                         // the splitter's "Rotate to right / left"
@property (nonatomic, readonly) NSMutableArray<NSString *> *recentFiles;
@property (nonatomic, readonly) NSMutableArray<NSString *> *closedFiles;  // for Restore Recent Closed File
@property (nonatomic) BOOL selfTestMode;                                 // suppress modal prompts
@property (nonatomic, copy, nullable) NSInteger (^promptOverride)(NSString *message, NSArray<NSString *> *buttons);

// ---- document lifecycle
- (TPDocument *)newDocument;
- (nullable TPDocument *)openFile:(NSString *)path;
- (nullable TPDocument *)openFile:(NSString *)path activate:(BOOL)activate error:(NSString *_Nullable *_Nullable)error;
- (nullable TPDocument *)documentForPath:(NSString *)path;
- (TPSaveResult)saveDocument:(TPDocument *)doc;
- (TPSaveResult)saveDocumentAs:(TPDocument *)doc copy:(BOOL)asCopy;
- (BOOL)writeDocument:(TPDocument *)doc toPath:(NSString *)path updateDocument:(BOOL)update error:(NSString *_Nullable *_Nullable)error;
- (BOOL)closeDocument:(TPDocument *)doc inPane:(TPEditorPane *)pane;     // prompts when dirty; NO if cancelled
- (BOOL)closeDocuments:(NSArray<TPDocument *> *)docs inPane:(TPEditorPane *)pane;
- (BOOL)reloadDocument:(TPDocument *)doc encoding:(const tpp::TextEncoding *_Nullable)enc;
- (void)activateDocument:(TPDocument *)doc inPane:(TPEditorPane *)pane;
- (void)activatePane:(TPEditorPane *)pane;
- (BOOL)prepareToQuit;                                                   // prompts for unsaved docs
- (void)addRecentFile:(NSString *)path;

// ---- helpers for commands
- (void)withDocument:(TPDocument *)doc perform:(void (^)(ScintillaView *view))block;
@property (nonatomic, readonly) ScintillaView *workerView;     // hidden view for documents that are not shown
- (int)defaultEol;
- (void)updateDiskInfo:(TPDocument *)doc;
- (nullable TPEditorPane *)paneShowingDocument:(TPDocument *)doc;
- (NSInteger)prompt:(NSString *)message informative:(nullable NSString *)info buttons:(NSArray<NSString *> *)buttons;
- (void)showMessage:(NSString *)message informative:(nullable NSString *)info;
- (void)refreshUI;          // title, tabs, status bar, toolbar
- (void)updateStatusBar;
- (void)updateTitle;
- (void)setDocumentLanguage:(TPDocument *)doc languageId:(NSString *)langId;
- (void)checkFilesModifiedOnDisk;

// ---- line operation helpers (operate on the active editor, single undo step)
- (void)getLineRangeForLineOperation:(sptr_t *)fromLine to:(sptr_t *)toLine wholeDocument:(BOOL *)whole;
- (void)replaceLinesFrom:(sptr_t)fromLine to:(sptr_t)toLine withLines:(const std::vector<std::string> &)lines;

@end

// Command groups (implemented in src/commands/*.mm)
@interface TPMainWindowController (FileCommands)
- (void)registerFileCommands:(TPCommandRegistry *)reg;
@end
@interface TPMainWindowController (EditCommands)
- (void)registerEditCommands:(TPCommandRegistry *)reg;
@end
@interface TPMainWindowController (SearchCommands)
- (void)registerSearchCommands:(TPCommandRegistry *)reg;
@end
@interface TPMainWindowController (ViewCommands)
- (void)registerViewCommands:(TPCommandRegistry *)reg;
@end
@interface TPMainWindowController (FormatCommands)
- (void)registerEncodingCommands:(TPCommandRegistry *)reg;
- (void)registerLanguageCommands:(TPCommandRegistry *)reg;
@end
@interface TPMainWindowController (ToolCommands)
- (void)registerToolCommands:(TPCommandRegistry *)reg;
- (void)registerMacroCommands:(TPCommandRegistry *)reg;
- (void)registerWindowAndHelpCommands:(TPCommandRegistry *)reg;
- (void)recordMacroStepForCommand:(int)cmd;
- (void)recordMacroStepFromNotification:(SCNotification *)scn;
- (void)updateWindowMenu:(NSMenu *)menu;
- (void)updateMacroMenu:(NSMenu *)menu;
- (void)updateRunMenu:(NSMenu *)menu;
- (void)registerDynamicCommands;                    // saved macros / Run commands -> registry ids 20000+ / 21000+
- (void)applyShortcutsXml;
- (BOOL)saveCurrentMacroNamed:(NSString *)name shortcut:(nullable TPKeyBinding *)shortcut;
- (BOOL)runShellCommand:(NSString *)cmd error:(NSString *_Nullable *_Nullable)error;
@property (nonatomic, strong, nullable) NSURL *lastRunURL;   // last URL a Run command opened (tests)
- (NSString *)debugInfoText;
@property (nonatomic, readonly) BOOL macroRecording;
@end

@class TPAutoCompletion;
@class TPKeyBinding;
@interface TPMainWindowController (CompletionPublic)
- (TPAutoCompletion *)autoCompletionForEditor;   // the active view's completion state, set to the current language
@end

@class TPCommandLine;
@interface TPMainWindowController (CommandLine)
@property (nonatomic) BOOL forceReadOnly, savingForbidden, monitorAllFiles, tabBarForcedHidden;   // -fullReadOnly…, -monitoringMode, -notabbar
@property (nonatomic, copy, nullable) NSString *titleAddition;                                    // -titleAdd
- (NSArray<TPDocument *> *)applyCommandLine:(TPCommandLine *)commandLine;   // opens the files and applies the options
- (void)applyOpenPolicyToDocument:(TPDocument *)doc;
- (void)ghostType:(NSString *)text speed:(NSInteger)speed completion:(nullable void (^)(void))done;
@end

@interface TPMainWindowController (ContextMenuConfig)
+ (nullable NSString *)contextMenuFilePath;                 // the user's contextMenu.xml, else the bundled default
+ (void)fillContextMenu:(NSMenu *)menu fromFile:(nullable NSString *)path;
- (NSMenu *)editorContextMenu;
- (void)editContextMenuFile;                                // Settings > Edit Popup ContextMenu
@end

@interface TPMainWindowController (PrintPublic)
- (NSPrintInfo *)printInfoFromPreferences;
- (NSView *)printViewWithInfo:(NSPrintInfo *)pi;   // the paginated view Print / Print Now send to the macOS print system
@end

@interface TPMainWindowController (ViewCommandsPublic)
- (void)applyViewFlagsPublic;
- (BOOL)chromeForcedHidden;
- (BOOL)distractionFreeActive;
- (BOOL)postItActive;
- (void)applyPostItWindowStyle;
- (void)applyDistractionFreePadding;
- (void)hideSelectedLines;
- (void)tagMatchInView:(ScintillaView *)v document:(nullable TPDocument *)doc;
- (BOOL)openDroppedURLs:(NSArray<NSURL *> *)urls;          // files / folders dropped on the window
- (void)moveOrCloneToOtherView:(BOOL)clone;
- (void)showHiddenSectionAt:(sptr_t)line ofDocument:(TPDocument *)doc;   // margin click on a hide-lines marker
- (int)distractionFreePaddingForWidth:(CGFloat)w;
- (void)launchNewInstanceWithArguments:(NSArray<NSString *> *)args;
@property (nonatomic, copy, nullable) NSArray<NSString *> *lastNewInstanceArguments;   // tests (no process is started in the self-test)
@end

@interface TPMainWindowController (Prefs)
- (void)installPreferenceObservers;
- (void)applyAllPreferences;
- (void)applyEditorPrefs:(ScintillaView *)v;
- (void)applyChromeVisibility;
- (BOOL)isLargeDocument:(nullable TPDocument *)d;
- (nullable NSURL *)defaultDirectoryURL;
- (void)rememberDirectory:(NSString *)dir;
- (void)backupBeforeSave:(NSString *)path;
- (void)handleCharAdded:(SCNotification *)scn pane:(TPEditorPane *)pane;
- (void)handleDoubleClick:(SCNotification *)scn pane:(TPEditorPane *)pane;
- (void)handleIndicatorClick:(SCNotification *)scn pane:(TPEditorPane *)pane;
- (void)markLinksInView:(ScintillaView *)v document:(nullable TPDocument *)doc;
- (NSString *)titleText;
+ (NSString *)recentLabelForPath:(NSString *)p;
@end

@interface TPMainWindowController (UDL)
- (void)udlDidChange:(TPUserLang *)lang;
- (void)udlRenamedFrom:(NSString *)oldId to:(NSString *)newId;
- (void)rebuildLanguageMenu:(NSMenu *)menu;
@end

// EditorOptions.mm: Preferences options upstream implements in the Scintilla window procedure
@interface TPMainWindowController (EditorOptions)
- (void)installEditorOptionHooks;
- (nullable ScintillaView *)editorWithKeyFocus;
- (BOOL)editor:(ScintillaView *)ed prepareColumnSelectionForKey:(NSEvent *)e;   // YES when the selection changed
- (void)editor:(ScintillaView *)ed rightClickAtWindowPoint:(NSPoint)windowPoint;
- (BOOL)confirmOpeningFileOfSize:(unsigned long long)size;
@end

@interface TPMainWindowController (JsonTools)
- (void)runJsonTool:(int)op;   // 0 format, 1 compress, 2 validate (Plugins > JSON Tools)
@end

@interface TPMainWindowController (DevTools)
- (void)runDevTool:(NSInteger)tool;   // a TPDevTool (commands/DevTools.h)
@end

NS_ASSUME_NONNULL_END
