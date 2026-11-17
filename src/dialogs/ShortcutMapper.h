// Textpad++ — Settings > Shortcut Mapper... (upstream WinControls/Grid/ShortcutMapper + shortcut.cpp editor).
// GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>

#import "app/MainWindowController.h"
@class TPKeyBinding;

NS_ASSUME_NONNULL_BEGIN

// Macros and Run commands live with the macro recorder / Run dialog; the mapper edits them through this.
@protocol TPShortcutMapperData <NSObject>
- (NSArray<NSString *> *)macroNames;
- (NSArray<NSString *> *)runCommandNames;
- (void)renameMacroAtIndex:(NSInteger)index to:(NSString *)name;
- (void)renameRunCommandAtIndex:(NSInteger)index to:(NSString *)name;
- (void)deleteMacroAtIndex:(NSInteger)index;
- (void)deleteRunCommandAtIndex:(NSInteger)index;
- (void)shortcutsDidChange;   // persist shortcuts.xml and rebuild the Macro / Run menus
@end

@interface TPMainWindowController (ShortcutMapperData) <TPShortcutMapperData>
@end

typedef NS_ENUM(NSInteger, TPMapperTab) {
    TPMapperTabMainMenu = 0, TPMapperTabMacros, TPMapperTabRunCommands, TPMapperTabPluginCommands, TPMapperTabScintilla
};

@interface TPShortcutMapper : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate>
+ (instancetype)sharedWithController:(TPMainWindowController<TPShortcutMapperData> *)c;
- (void)openOnTab:(TPMapperTab)tab;
@property (nonatomic) TPMapperTab tab;
@property (nonatomic, copy) NSString *filter;
@property (nonatomic, readonly) NSInteger rowCount;
- (NSString *)nameAtRow:(NSInteger)row;
- (NSString *)shortcutAtRow:(NSInteger)row;
- (BOOL)selectRowNamed:(NSString *)name;
- (BOOL)selectCommand:(int)cmd;                     // main menu tab (or a macro / Run id)
- (BOOL)selectScintillaMessage:(int)message;        // Scintilla commands tab
@property (nonatomic, readonly) NSString *conflictText;   // "No shortcut conflicts for this item." / "CONFLICT FOUND! ..."
// What the shortcut editor's OK / the Clear / Delete buttons do on the selected row
- (void)assignBinding:(nullable TPKeyBinding *)binding name:(nullable NSString *)name;
- (IBAction)clearSelected:(nullable id)sender;
- (IBAction)deleteSelected:(nullable id)sender;
- (IBAction)modifySelected:(nullable id)sender;     // opens the shortcut editor (modal)
@end

NS_ASSUME_NONNULL_END
