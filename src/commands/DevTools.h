// Textpad++ — built-in developer tools (Plugins > JSON Tools / XML Tools / Encode-Decode / Text Tools / Convert /
// Insert). GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, TPCaseStyle) { TPCaseCamel, TPCasePascal, TPCaseSnake, TPCaseConstant, TPCaseKebab, TPCaseDot };
typedef NS_ENUM(NSInteger, TPCodec) { TPCodecBase64, TPCodecURL, TPCodecHTML, TPCodecUnicode, TPCodecHex };
typedef NS_ENUM(NSInteger, TPInsertKind) { TPInsertUUID, TPInsertUnixTime, TPInsertISODate, TPInsertLorem, TPInsertPassword };

typedef NS_ENUM(NSInteger, TPDevTool) {
    TPDevToolJsonSortKeys, TPDevToolJsonEscape, TPDevToolJsonUnescape, TPDevToolJwtDecode,
    TPDevToolXmlPretty, TPDevToolXmlCompress, TPDevToolXmlValidate, TPDevToolXPath,
    // pairs in TPCodec order: encode, decode
    TPDevToolBase64Encode, TPDevToolBase64Decode, TPDevToolURLEncode, TPDevToolURLDecode, TPDevToolHTMLEncode, TPDevToolHTMLDecode,
    TPDevToolUnicodeEscape, TPDevToolUnicodeUnescape, TPDevToolHexEncode, TPDevToolHexDecode,
    // TPCaseStyle order
    TPDevToolCamel, TPDevToolPascal, TPDevToolSnake, TPDevToolConstant, TPDevToolKebab, TPDevToolDot,
    TPDevToolSortByLength, TPDevToolAlignEquals, TPDevToolAlignColon, TPDevToolEscapeRegex,
    TPDevToolCsvToJson, TPDevToolCsvToMarkdown, TPDevToolJsonToCsv, TPDevToolTimestamp, TPDevToolDecToHex, TPDevToolHexToDec,
    // TPInsertKind order
    TPDevToolInsertUUID, TPDevToolInsertUnixTime, TPDevToolInsertISODate, TPDevToolInsertLorem, TPDevToolInsertPassword,
    // Code Formatter
    TPDevToolFormatAuto, TPDevToolFormatSQL, TPDevToolFormatHTML, TPDevToolFormatCSS, TPDevToolMinifyCSS,
};

NS_ASSUME_NONNULL_BEGIN
extern NSString *_Nullable TPDevToolsTestInput;
NSString *TPConvertCase(NSString *text, TPCaseStyle style);
NSString *_Nullable TPEncodeText(NSString *text, TPCodec codec, BOOL encode, NSString *_Nullable *_Nonnull error);
NSString *_Nullable TPDecodeJWT(NSString *token, NSString *_Nullable *_Nonnull error);
NSString *_Nullable TPConvertTimestamp(NSString *text, NSString *_Nullable *_Nonnull error);
NSString *TPConvertNumbers(NSString *text, BOOL toHex);
NSString *TPAlignOn(NSString *text, NSString *separator);
NSString *TPSortLinesByLength(NSString *text);
NSString *TPEscapeRegex(NSString *text);
BOOL TPCheckXML(NSString *xml, NSString *_Nullable *_Nonnull error, NSInteger *line, NSInteger *column);
NSString *_Nullable TPFormatXML(NSString *xml, BOOL pretty, NSString *_Nullable *_Nonnull error);
NSString *_Nullable TPRunXPath(NSString *xml, NSString *xpath, NSString *_Nullable *_Nonnull error);
NSString *TPInsertText(TPInsertKind kind);
NS_ASSUME_NONNULL_END
