// Textpad++ — interface languages (upstream nativeLang/*.xml): menus, sub-menus and every command label, which also
// feeds context menus, toolbar tooltips and the Shortcut Mapper. Switched live by Preferences > General > Localization.
// GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface TPLocalization : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSArray<NSString *> *languageNames;   // "English" first, then by name
@property (nonatomic, readonly) NSArray<NSString *> *languageFiles;   // same order; "" for English
@property (nonatomic, readonly) NSString *currentFile;                // "" = English
- (BOOL)applyLanguageFile:(NSString *)file;                           // "" restores English
- (void)applyPreference;                                              // pref.localization
- (nullable NSString *)labelForCommand:(int)cmd;                      // the translated label, nil in English
// dialogs: the language file's <Dialog> strings, matched through english.xml by the English text of a control
- (nullable NSString *)translateDialogString:(NSString *)english;     // nil when unknown or in English
- (void)translateWindow:(NSWindow *)window;                           // buttons, labels, tabs, boxes, columns, title
@end

NS_ASSUME_NONNULL_END
