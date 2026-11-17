// Textpad++ — languages, lexers and styles (upstream: NppParameters lang/style loading +
// ScintillaEditView::defineDocType / makeStyle / set*Lexer). GPL-3.0-or-later.
#pragma once

#import <Cocoa/Cocoa.h>
#import "app/Sci.h"

@class TPDocument;

NS_ASSUME_NONNULL_BEGIN

@interface TPLanguage : NSObject
@property (nonatomic, copy) NSString *langId;        // langs.model.xml name ("cpp")
@property (nonatomic, copy) NSString *shortName;     // "C++"
@property (nonatomic, copy) NSString *longName;      // "C++ source file" (status bar)
@property (nonatomic, copy) NSString *lexerName;     // Lexilla lexer name ("cpp"), "null" for plain text
@property (nonatomic) int menuCommand;               // IDM_LANG_*
@property (nonatomic, copy) NSArray<NSString *> *extensions;
@property (nonatomic, copy, nullable) NSString *commentLine;
@property (nonatomic, copy, nullable) NSString *commentStart;
@property (nonatomic, copy, nullable) NSString *commentEnd;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *keywords;  // "instre1" -> words
@end

@interface TPStyleSpec : NSObject <NSCopying>
@property (nonatomic, copy) NSString *name;
@property (nonatomic) int styleID;
@property (nonatomic) int fg;          // 0xRRGGBB or -1
@property (nonatomic) int bg;          // 0xRRGGBB or -1
@property (nonatomic, copy, nullable) NSString *fontName;
@property (nonatomic) int fontStyle;   // bit 1 bold, 2 italic, 4 underline; -1 unset
@property (nonatomic) double fontSize; // Windows points; 0 unset
@property (nonatomic, copy, nullable) NSString *keywordClass;
@property (nonatomic) int colorStyle;   // bit 1 foreground, bit 2 background (upstream COLORSTYLE_*); 3 when absent
@property (nonatomic) int nesting;      // UDL nesting mask
@property (nonatomic, copy) NSString *userKeywords;               // Style Configurator "User-defined keywords"
@property (nonatomic, strong, nullable) NSXMLElement *element;    // the theme XML element it came from
@end

// A <LexerType> of the theme (Style Configurator "Language" list)
@interface TPLexerType : NSObject
@property (nonatomic, copy) NSString *name;     // langs.model.xml name ("cpp")
@property (nonatomic, copy) NSString *desc;     // "C++"
@property (nonatomic, copy) NSString *userExt;  // Style Configurator "User ext."
@property (nonatomic, copy) NSArray<TPStyleSpec *> *styles;
@property (nonatomic, strong, nullable) NSXMLElement *element;
@end

@interface TPLanguageService : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSArray<TPLanguage *> *languages;
@property (nonatomic, copy) NSString *themePath;    // stylers file in use
- (nullable TPLanguage *)languageForId:(NSString *)langId;
- (nullable TPLanguage *)languageForMenuCommand:(int)cmd;
- (TPLanguage *)languageForFileName:(NSString *)fileName;
- (nullable TPStyleSpec *)globalStyle:(NSString *)name;
- (NSArray<TPStyleSpec *> *)stylesForLexerType:(NSString *)langId;
- (BOOL)loadTheme:(NSString *)stylersPath error:(NSString *_Nullable *_Nullable)error;

// Style Configurator support (upstream WordStyleDlg): edits go into the loaded theme XML and are saved to a
// user-writable copy (stylers.xml / themes/<name>.xml in the support folder), as upstream does.
@property (nonatomic, readonly) NSArray<TPLexerType *> *lexerTypes;
@property (nonatomic, readonly) NSArray<TPStyleSpec *> *globalStyleList;
@property (nonatomic, readonly) BOOL themeModified;
- (nullable TPLexerType *)lexerTypeNamed:(NSString *)name;
- (void)styleDidChange:(TPStyleSpec *)style;
- (void)setUserExt:(NSString *)ext forLexerType:(TPLexerType *)lexerType;
- (void)setUserKeywords:(NSString *)words forStyle:(TPStyleSpec *)style;
- (nullable NSString *)saveThemeWithError:(NSString *_Nullable *_Nullable)error;   // returns the path written
- (NSString *)defaultKeywordsForLanguage:(NSString *)langId keywordClass:(NSString *)keywordClass;
+ (NSString *)writableThemePathFor:(NSString *)path;
+ (NSString *)defaultThemePath;                   // the user's stylers.xml when it exists, else the bundled model
+ (nullable NSString *)themePathForFileName:(NSString *)fileName;   // user copy first, then bundled themes/

// Sets the lexer on the view's current document when needed, then applies styles to the view.
- (void)applyLanguageOfDocument:(TPDocument *)doc toView:(ScintillaView *)view;
// One-time per-view setup (margins, markers, indicators, caret, change history...).
- (void)configureView:(ScintillaView *)view;
// Windows point size -> macOS point size (96 dpi vs 72 dpi user space).
+ (double)macPointsFromWindowsPoints:(double)pt;
@end

NS_ASSUME_NONNULL_END
