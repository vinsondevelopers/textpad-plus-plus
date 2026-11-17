// Textpad++ — typed preference store + Preferences window (upstream: NppParameters NppGUI +
// WinControls/Preference/preferenceDlg). GPL-3.0-or-later.
#pragma once

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const TPPrefsChangedNotification;   // userInfo[@"key"]

// Keys (NSUserDefaults). Values and defaults follow upstream NppGUI defaults unless noted in docs.
@interface TPPrefs : NSObject
+ (void)registerDefaults;
+ (BOOL)b:(NSString *)key;
+ (NSInteger)i:(NSString *)key;
+ (NSString *)s:(NSString *)key;
+ (nullable id)o:(NSString *)key;
+ (void)set:(nullable id)value forKey:(NSString *)key;          // posts TPPrefsChangedNotification
+ (NSArray<NSDictionary *> *)pages;                             // declarative spec of the 24 upstream pages
// Per-language indentation (Preferences > Indentation): returns {size, spaces} for a language id.
+ (NSInteger)tabSizeForLanguage:(NSString *)langId;
+ (BOOL)useSpacesForLanguage:(NSString *)langId;
@end

// Window-chrome colours for light / dark mode (Preferences > Dark Mode).
@interface TPChrome : NSObject
+ (BOOL)dark;
+ (NSColor *)barBackground;
+ (NSColor *)tabStripBackground;
+ (NSColor *)tabActive;
+ (NSColor *)tabInactive;
+ (NSColor *)tabHover;
+ (NSColor *)tabActiveText;
+ (NSColor *)tabInactiveText;
+ (NSColor *)border;
+ (NSColor *)separator;
+ (NSColor *)statusText;
@end

#ifdef __cplusplus
extern "C" {
#endif
void TPBeep(void);   // honours Preferences > MISC. > Mute all sounds
void TPApplyDialogFont(NSWindow *w);   // Preferences > General > custom dialog font
#ifdef __cplusplus
}
#endif

@interface TPPreferencesWindow : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
+ (instancetype)shared;
- (void)showPage:(NSString *)pageTitle;
@property (nonatomic, readonly) NSString *currentPage;
@end

NS_ASSUME_NONNULL_END
