// Textpad++ — "Define your language..." dialog (upstream ScintillaComponent/UserDefineDialog).
// GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>

@class TPUserLang;
@class TPMainWindowController;

NS_ASSUME_NONNULL_BEGIN

@interface TPUDLDialog : NSWindowController <NSTextViewDelegate, NSTextFieldDelegate>
+ (instancetype)sharedWithController:(TPMainWindowController *)c;
@property (nonatomic, strong, nullable) TPUserLang *current;
- (void)selectLanguageNamed:(nullable NSString *)name;
- (void)reloadLanguages;
@property (nonatomic, readonly) BOOL docked;     // shown as a docking panel ("Dock" / "Undock" button, remembered)
@property (nonatomic, readonly) BOOL isShown;
- (void)present;                                 // the window, or the panel when docked
- (void)hideDialog;
- (void)toggleDock:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
