// Textpad++ — features beyond the Windows editor (see Features.h). GPL-3.0-or-later.
#import "app/Features.h"
#import "app/Document.h"
#import "app/Preferences.h"
#import "app/Sci.h"
#import "commands/ExtraCommands.h"
#import "panels/PreviewPanel.h"
#import "panels/DockManager.h"
#import "app/Compare.h"
#import "dialogs/CommandPalette.h"
#import "app/GitMarkers.h"
#import "app/CsvColumns.h"
#import "app/Snippets.h"
#import <objc/runtime.h>

#import "generated/NppCommandIds.h"
using namespace npp;

static char kPreviewPanel;

@implementation TPMainWindowController (Features)

- (TPPreviewPanel *)previewPanel { return objc_getAssociatedObject(self, &kPreviewPanel); }

- (void)registerFeatureCommands:(TPCommandRegistry *)reg {
    __weak TPMainWindowController *ws = self;
    // ---- Live Preview
    TPPreviewPanel *preview = [[TPPreviewPanel alloc] initWithController:self];
    objc_setAssociatedObject(self, &kPreviewPanel, preview, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self.docks registerPanel:preview];
    [reg registerCommand:IDM_TP_LIVE_PREVIEW handler:^(int c) { [ws showLivePreview:![ws.docks isPanelVisible:@"preview"]]; }
                 enabled:nil checked:^BOOL(int c) { return [ws.docks isPanelVisible:@"preview"]; }];
    [reg addExtraCommand:IDM_TP_LIVE_PREVIEW label:@"Live Preview (Markdown / HTML)" menu:@"View" submenu:nil after:IDM_VIEW_DOC_MAP
         separatorBefore:NO key:@"v" ctrl:YES alt:YES shift:YES];
    // ---- Compare
    TPCommandPredicate hasDoc = ^BOOL(int c) { return ws.currentDocument != nil; };
    TPCommandPredicate comparing = ^BOOL(int c) { return ws.isComparing; };
    [reg registerCommand:IDM_TP_COMPARE handler:^(int c) { [ws compareStart]; } enabled:hasDoc checked:comparing];
    [reg registerCommand:IDM_TP_COMPARE_CLEAR handler:^(int c) { [ws compareClear]; } enabled:comparing checked:nil];
    [reg registerCommand:IDM_TP_COMPARE_NEXT handler:^(int c) { [ws compareJump:YES]; } enabled:comparing checked:nil];
    [reg registerCommand:IDM_TP_COMPARE_PREV handler:^(int c) { [ws compareJump:NO]; } enabled:comparing checked:nil];
    [reg addExtraCommand:IDM_TP_COMPARE label:@"Compare Side by Side" menu:@"View" submenu:@"Compare" after:0 separatorBefore:NO key:@"c" ctrl:YES alt:YES shift:NO];
    [reg addExtraCommand:IDM_TP_COMPARE_NEXT label:@"Next Difference" menu:@"View" submenu:@"Compare" after:0 separatorBefore:YES key:@"n" ctrl:YES alt:YES shift:NO];
    [reg addExtraCommand:IDM_TP_COMPARE_PREV label:@"Previous Difference" menu:@"View" submenu:@"Compare" after:0 separatorBefore:NO key:@"p" ctrl:YES alt:YES shift:NO];
    [reg addExtraCommand:IDM_TP_COMPARE_CLEAR label:@"Clear Compare" menu:@"View" submenu:@"Compare" after:0 separatorBefore:YES key:@"x" ctrl:YES alt:YES shift:NO];
    // ---- Command Palette
    [reg registerCommand:IDM_TP_COMMAND_PALETTE handler:^(int c) { [[TPCommandPalette shared] showOverWindow:ws.window]; }];
    [reg addExtraCommand:IDM_TP_COMMAND_PALETTE label:@"Command Palette..." menu:@"View" submenu:nil after:IDM_VIEW_ALWAYSONTOP
         separatorBefore:NO key:@"a" ctrl:YES alt:NO shift:YES];
    // ---- Modern Look (rounded tabs, unified title bar, macOS-like themes)
    [reg registerCommand:IDM_TP_MODERN_UI handler:^(int c) {
        [TPPrefs set:@(![TPPrefs b:@"pref.modernLook"]) forKey:@"pref.modernLook"];
        [ws applyAllPreferences];
        [ws.window.contentView setNeedsDisplay:YES];
        for (NSView *v in ws.window.contentView.subviews) [v setNeedsDisplay:YES];
    } enabled:nil checked:^BOOL(int c) { return [TPPrefs b:@"pref.modernLook"]; }];
    [reg addExtraCommand:IDM_TP_MODERN_UI label:@"Modern Look" menu:@"View" submenu:nil after:IDM_TP_COMMAND_PALETTE separatorBefore:NO key:nil ctrl:NO alt:NO shift:NO];
    // ---- Git change markers
    [reg registerCommand:IDM_TP_GIT_MARKERS handler:^(int c) { [TPPrefs set:@(![TPPrefs b:@"pref.gitMarkers"]) forKey:@"pref.gitMarkers"]; [ws gitTick]; }
                 enabled:nil checked:^BOOL(int c) { return [TPPrefs b:@"pref.gitMarkers"]; }];
    TPCommandPredicate gitOn = ^BOOL(int c) { return [TPPrefs b:@"pref.gitMarkers"] && ws.currentDocument.path != nil; };
    [reg registerCommand:IDM_TP_GIT_NEXT handler:^(int c) { [ws gitJump:YES]; } enabled:gitOn checked:nil];
    [reg registerCommand:IDM_TP_GIT_PREV handler:^(int c) { [ws gitJump:NO]; } enabled:gitOn checked:nil];
    [reg addExtraCommand:IDM_TP_GIT_MARKERS label:@"Show Git Changes in the Margin" menu:@"View" submenu:@"Git Changes" after:0 separatorBefore:NO key:nil ctrl:NO alt:NO shift:NO];
    [reg addExtraCommand:IDM_TP_GIT_NEXT label:@"Next Change" menu:@"View" submenu:@"Git Changes" after:0 separatorBefore:YES key:@"]" ctrl:YES alt:YES shift:NO];
    [reg addExtraCommand:IDM_TP_GIT_PREV label:@"Previous Change" menu:@"View" submenu:@"Git Changes" after:0 separatorBefore:NO key:@"[" ctrl:YES alt:YES shift:NO];
    [self gitStartWatching];
    // ---- CSV
    [reg registerCommand:IDM_TP_CSV_RAINBOW handler:^(int c) { [TPPrefs set:@(![TPPrefs b:@"pref.csvRainbow"]) forKey:@"pref.csvRainbow"]; [ws csvRainbowTick]; }
                 enabled:nil checked:^BOOL(int c) { return [TPPrefs b:@"pref.csvRainbow"]; }];
    [reg registerCommand:IDM_TP_CSV_ALIGN handler:^(int c) { [ws csvReformat:YES]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_TP_CSV_SHRINK handler:^(int c) { [ws csvReformat:NO]; } enabled:hasDoc checked:nil];
    [reg addExtraCommand:IDM_TP_CSV_RAINBOW label:@"CSV Rainbow Columns" menu:@"View" submenu:nil after:IDM_TP_LIVE_PREVIEW separatorBefore:NO key:nil ctrl:NO alt:NO shift:NO];
    [reg addExtraCommand:IDM_TP_CSV_ALIGN label:@"Align Columns" menu:@"Edit" submenu:@"CSV Columns" after:0 separatorBefore:NO key:nil ctrl:NO alt:NO shift:NO];
    [reg addExtraCommand:IDM_TP_CSV_SHRINK label:@"Shrink Columns" menu:@"Edit" submenu:@"CSV Columns" after:0 separatorBefore:NO key:nil ctrl:NO alt:NO shift:NO];
    [self csvStartWatching];
    // ---- Snippets
    [reg registerCommand:IDM_TP_SNIPPETS handler:^(int c) { [TPPrefs set:@(![TPPrefs b:@"pref.snippets"]) forKey:@"pref.snippets"]; }
                 enabled:nil checked:^BOOL(int c) { return [TPPrefs b:@"pref.snippets"]; }];
    [reg registerCommand:IDM_TP_SNIPPETS_EDIT handler:^(int c) { [ws editSnippetsFile]; }];
    [reg addExtraCommand:IDM_TP_SNIPPETS label:@"Snippets (Trigger + Tab)" menu:@"Settings" submenu:nil after:0 separatorBefore:YES key:nil ctrl:NO alt:NO shift:NO];
    [reg addExtraCommand:IDM_TP_SNIPPETS_EDIT label:@"Edit Snippets..." menu:@"Settings" submenu:nil after:0 separatorBefore:NO key:nil ctrl:NO alt:NO shift:NO];
}


- (void)showLivePreview:(BOOL)show {
    if (show) {
        [self.docks ensureDockSize:0.45 forSide:[self.docks sideOfPanel:@"preview"]];
        [self.docks showPanel:@"preview"];
    } else [self.docks hidePanel:@"preview"];
    [self refreshUI];
}

- (void)offerPreviewForDocument:(TPDocument *)doc {
    if (![TPPreviewPanel isMarkdownPath:doc.path] || [self.docks isPanelVisible:@"preview"]) return;
    NSInteger mode = [TPPrefs i:@"pref.markdownOpen"];   // 0 ask, 1 preview, 2 text only
    if (mode == 0) {
        if (self.selfTestMode && !self.promptOverride) return;
        NSString *msg = [NSString stringWithFormat:@"How would you like to open “%@”?", doc.path.lastPathComponent];
        NSString *info = @"This is a Markdown document. Open it with a formatted Live Preview beside the text — you can edit on either side "
                          "and both stay in step — or work with the plain text only.";
        NSArray *buttons = @[@"Open with Live Preview", @"Text Only"];
        NSInteger r;
        if (self.promptOverride) r = self.promptOverride(msg, buttons);
        else {
            NSAlert *a = [NSAlert new];
            a.messageText = msg;
            a.informativeText = info;
            a.icon = [NSImage imageWithSystemSymbolName:@"doc.richtext" accessibilityDescription:nil] ?: NSApp.applicationIconImage;
            for (NSString *b in buttons) [a addButtonWithTitle:b];
            a.buttons[1].keyEquivalent = @"\e";
            a.showsSuppressionButton = YES;
            a.suppressionButton.title = @"Remember my choice (change it in Settings > Textpad++ Features)";
            r = [a runModal] - NSAlertFirstButtonReturn;
            if (a.suppressionButton.state == NSControlStateValueOn) [TPPrefs set:@(r == 0 ? 1 : 2) forKey:@"pref.markdownOpen"];
        }
        if (r != 0) return;
    } else if (mode != 1) return;
    [self showLivePreview:YES];
}

@end
