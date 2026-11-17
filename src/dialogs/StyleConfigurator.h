// Textpad++ — Settings > Style Configurator... (upstream WinControls/ColourPicker/WordStyleDlg). GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>

@class TPMainWindowController;
@class TPStyleSpec;

NS_ASSUME_NONNULL_BEGIN

@interface TPStyleConfigurator : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate, NSTextFieldDelegate>
+ (instancetype)sharedWithController:(TPMainWindowController *)c;
- (void)open;                                         // shows the window and snapshots the state Cancel returns to

// Selection (upstream: "Select theme" combo, "Language" combo, "Style" list)
- (void)selectThemeNamed:(NSString *)displayName;     // "Default (stylers.xml)" or a theme file name without .xml
- (void)selectLanguageNamed:(NSString *)name;         // "Global Styles" or a LexerType name ("cpp")
- (void)selectStyleNamed:(NSString *)name;
@property (nonatomic, readonly, nullable) TPStyleSpec *currentStyle;
@property (nonatomic, readonly) NSArray<NSString *> *themeNames;

// Controls (exposed for the acceptance tests; changing one and calling -controlChanged: is what a click does)
@property (nonatomic, readonly) NSColorWell *foregroundWell, *backgroundWell;
@property (nonatomic, readonly) NSPopUpButton *fontPopup, *fontSizePopup;
@property (nonatomic, readonly) NSButton *boldCheck, *italicCheck, *underlineCheck;
@property (nonatomic, readonly) NSTextField *defaultExtField, *userExtField;
@property (nonatomic, readonly) NSTextView *defaultKeywordsView, *userKeywordsView;
@property (nonatomic, readonly) NSArray<NSButton *> *globalOverrideChecks;   // fg, bg, font, size, bold, italic, underline
@property (nonatomic, readonly) NSButton *goToSettingsButton;
- (IBAction)controlChanged:(nullable id)sender;
- (IBAction)saveAndClose:(nullable id)sender;
- (IBAction)cancel:(nullable id)sender;
- (IBAction)goToSettings:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
