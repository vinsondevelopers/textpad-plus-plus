// Textpad++ — features beyond the Windows editor: Live Preview, Compare, Command Palette, Git change
// markers, CSV columns, snippets, modern look. Commands are in commands/ExtraCommands.h. GPL-3.0-or-later.
#pragma once
#import "app/MainWindowController.h"
#import "commands/CommandRegistry.h"

@class TPPreviewPanel;

NS_ASSUME_NONNULL_BEGIN
@interface TPMainWindowController (Features)
- (void)registerFeatureCommands:(TPCommandRegistry *)reg;   // after registerPanelCommands, before the menu is built
@property (nonatomic, readonly) TPPreviewPanel *previewPanel;
- (void)showLivePreview:(BOOL)show;
// a Markdown file was opened by the user: ask Preview / Text (Preferences > Textpad++ Features remembers the answer)
- (void)offerPreviewForDocument:(TPDocument *)doc;
@end
NS_ASSUME_NONNULL_END
