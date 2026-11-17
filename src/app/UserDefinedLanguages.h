// Textpad++ — User Defined Languages (upstream: UserLangContainer in Parameters.h, feedUserLang*
// in Parameters.cpp, ScintillaEditView::setUserLexer, UserDefineDialog). Files use the upstream
// UDL 2.1 XML format, so Notepad++ UDLs import/export unchanged. GPL-3.0-or-later.
#pragma once

#import <Cocoa/Cocoa.h>
#import "app/Sci.h"

@class TPStyleSpec;
@class TPLanguage;

NS_ASSUME_NONNULL_BEGIN

enum { TPUDLKeywordListCount = 28, TPUDLStyleCount = 25 };

@interface TPUserLang : NSObject <NSCopying>
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *ext;                       // space separated
@property (nonatomic, copy) NSString *udlVersion;
@property (nonatomic) BOOL caseIgnored, allowFoldOfComments, foldCompact;
@property (nonatomic) int forcePureLC;                           // 0 anywhere, 1 force at BOL, 2 allow preceding whitespace
@property (nonatomic) int decimalSeparator;                      // 0 dot, 1 comma, 2 both
@property (nonatomic, strong) NSMutableArray<NSString *> *keywordLists;    // SCE_USER_KWLIST_* (28)
@property (nonatomic, strong) NSMutableArray<NSNumber *> *isPrefix;        // Keywords1..8
@property (nonatomic, strong) NSMutableArray<TPStyleSpec *> *styles;       // index == SCE_USER_STYLE_* (25)
@property (nonatomic, copy, nullable) NSString *filePath;        // where it was loaded from
@property (nonatomic) BOOL preinstalled;                         // bundled, read-only (edits are saved as a user copy)
@property (nonatomic, readonly) NSString *langId;                // "udl:<name>"
@property (nonatomic, readonly) NSUInteger numericId;            // stable id passed to LexUser (userDefine.udlName)
- (instancetype)initWithName:(NSString *)name;
// Comment and delimiter lists encode several fields with 2-digit prefixes ("00// 01 02 03/* 04*/").
- (NSString *)field:(int)code ofList:(int)list;
- (void)setField:(int)code ofList:(int)list value:(NSString *)value;
- (NSXMLElement *)xmlElement;
@end

@interface TPUserLanguages : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSArray<TPUserLang *> *languages;
@property (nonatomic, readonly) NSString *userFolder;            // ~/Library/Application Support/Textpad++/userDefineLangs
- (void)reload;
- (nullable TPUserLang *)languageNamed:(NSString *)name;
- (nullable TPUserLang *)languageForId:(NSString *)langId;
- (nullable TPUserLang *)languageForFileName:(NSString *)fileName;
- (nullable TPLanguage *)languageDescriptorForId:(NSString *)langId;   // TPLanguage facade (comment tokens, names)
- (BOOL)save:(TPUserLang *)lang error:(NSString *_Nullable *_Nullable)error;
- (BOOL)remove:(TPUserLang *)lang error:(NSString *_Nullable *_Nullable)error;
- (NSArray<TPUserLang *> *)importFile:(NSString *)path error:(NSString *_Nullable *_Nullable)error;
- (BOOL)exportLanguage:(TPUserLang *)lang toPath:(NSString *)path error:(NSString *_Nullable *_Nullable)error;
- (nullable TPUserLang *)createNamed:(NSString *)name basedOn:(nullable TPUserLang *)base error:(NSString *_Nullable *_Nullable)error;
- (BOOL)rename:(TPUserLang *)lang to:(NSString *)newName error:(NSString *_Nullable *_Nullable)error;
+ (NSArray<TPUserLang *> *)parseData:(NSData *)data source:(nullable NSString *)path error:(NSString *_Nullable *_Nullable)error;
// Port of ScintillaEditView::setUserLexer + UDL styling (call with the view showing the document).
- (void)applyLanguage:(TPUserLang *)lang toView:(ScintillaView *)v bufferId:(NSUInteger)bufferId setLexer:(BOOL)setLexer;
@end

extern NSNotificationName const TPUserLanguagesChangedNotification;

NS_ASSUME_NONNULL_END
