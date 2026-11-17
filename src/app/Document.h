// Textpad++ — document (buffer) model. Equivalent of upstream Buffer (ScintillaComponent/Buffer.h).
// GPL-3.0-or-later.
#pragma once

#import <Cocoa/Cocoa.h>
#include "core/Encoding.h"
#include "Scintilla.h"

NS_ASSUME_NONNULL_BEGIN

// Saved per-view caret/scroll state (upstream: Position struct in Buffer.h).
typedef struct {
    sptr_t anchor;
    sptr_t caret;
    sptr_t firstVisibleLine;
    sptr_t xOffset;
    int selMode;
    BOOL valid;
} TPViewPosition;

@interface TPDocument : NSObject

@property (nonatomic, readonly) NSUInteger uid;
@property (nonatomic, copy, nullable) NSString *path;           // nil for untitled "new N"
@property (nonatomic, copy) NSString *untitledName;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, copy, nullable) NSString *contentTitle;    // Preferences > New Document > first line as untitled tab name
@property (nonatomic, readonly) NSString *tabLabel;
@property (nonatomic, readonly) BOOL isUntitled;

@property (nonatomic) sptr_t sciDoc;                             // Scintilla document (one reference held)
@property (nonatomic) tpp::TextEncoding encoding;
@property (nonatomic) int eolMode;                               // SC_EOL_*
@property (nonatomic, copy) NSString *languageId;                // langs.model.xml name, "normal" for plain text
@property (nonatomic, copy, nullable) NSString *appliedLexerLanguage;

@property (nonatomic) BOOL dirty;
@property (nonatomic) BOOL pendingSaveChange;                    // dirty for reasons outside the text (encoding change, deleted file kept)
@property (nonatomic) BOOL userReadOnly;                         // Edit > Read-Only in Textpad++
@property (nonatomic) BOOL diskReadOnly;                         // file not writable on disk
@property (nonatomic) BOOL lossyDecode;                          // some bytes could not be decoded
@property (nonatomic) BOOL containsNul;
@property (nonatomic, strong, nullable) NSDate *diskModDate;
@property (nonatomic) unsigned long long diskSize;
@property (nonatomic) BOOL deletedOnDisk;
@property (nonatomic) BOOL pinned;
@property (nonatomic) NSInteger tabColor;                        // -1 none, 0..4 = "Apply Color 1..5"
@property (nonatomic) BOOL monitoring;                           // View > Monitoring (tail -f)
@property (nonatomic, strong, nullable) NSDate *lastAccess;

- (instancetype)initUntitled:(NSString *)name;
- (instancetype)initWithPath:(NSString *)path;
- (TPViewPosition)positionForView:(int)viewIndex;
- (void)setPosition:(TPViewPosition)pos forView:(int)viewIndex;

@end

NS_ASSUME_NONNULL_END
