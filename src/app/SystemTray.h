// Textpad++ — Preferences > MISC. > "Minimize to / Close to system tray" (upstream trayIconControler + IDR_SYSTRAYPOPUP_MENU):
// on macOS the tray is a menu bar extra (NSStatusItem). GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>
#import "app/MainWindowController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TPTrayAction) { TPTrayNone = 0, TPTrayMinimize, TPTrayClose, TPTrayMinimizeClose };   // upstream sta_*

@interface TPMainWindowController (SystemTray)
- (void)registerTrayCommands;
- (void)installTrayHooks;                         // the window's minimize button
@property (nonatomic, readonly, nullable) NSStatusItem *trayItem;   // present while hidden in the menu bar
- (BOOL)hideToTrayIfWantedFor:(TPTrayAction)why;  // YES when the window went to the menu bar
- (void)restoreFromTray;                          // Activate
- (void)minimizeClicked:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
