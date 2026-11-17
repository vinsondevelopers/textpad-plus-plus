// Textpad++ — optional Windows-style menu bar inside the window (Preferences > General > Menu), with upstream's
// right shortcuts ＋ ▼ ✕ (Notepad_plus.rc). The macOS menu bar keeps the same menus. GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>
#import "app/MainWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@interface TPMenuBarView : NSView
- (instancetype)initWithController:(TPMainWindowController *)c;
@property (nonatomic, readonly) NSArray<NSButton *> *menuButtons;       // File … ?
@property (nonatomic, readonly) NSArray<NSButton *> *shortcutButtons;   // ＋ ▼ ✕
@property (nonatomic, readonly) CGFloat preferredHeight;
- (void)rebuild;                                                       // after the main menu changes
- (void)layoutButtons;
- (nullable NSMenu *)menuForButton:(NSButton *)button;                 // the copy a click pops up
- (NSMenu *)tabDropListMenu;                                           // ▼: the current view's documents
@property (nonatomic) NSInteger keyboardIndex;                         // menu mode: highlighted menu, -1 = off
- (BOOL)handleMenuModeKey:(NSEvent *)e;
@property (nonatomic, copy, nullable) NSString *lastKeyboardOpened;    // self-test: the menu menu mode opened
@end

@interface TPMainWindowController (InWindowMenu)
@property (nonatomic, readonly, nullable) TPMenuBarView *inWindowMenuBar;
@property (nonatomic) BOOL inWindowMenuTemporarilyShown;               // Hide on: ⌥ Option or F10 shows it
- (void)applyInWindowMenuVisibility;
- (BOOL)handleMenuBarToggleEvent:(NSEvent *)e;                         // YES when the event toggled the bar
@end

NS_ASSUME_NONNULL_END
