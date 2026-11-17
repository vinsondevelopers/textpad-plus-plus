// Textpad++ — very large files: background loading, chunked saving, append-only reload. GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>
#import "app/MainWindowController.h"

NS_ASSUME_NONNULL_BEGIN

extern const unsigned long long TPStreamedFileBytes;   // from this size files load in the background

@interface TPMainWindowController (LargeFiles)
- (nullable TPDocument *)loadLargeFile:(NSString *)path error:(NSString *_Nullable *_Nullable)error;
- (sptr_t)adoptLoadedDocument:(sptr_t)doc eol:(int)eol;
- (BOOL)forEachChunkOfDocument:(TPDocument *)doc perform:(BOOL (^)(const char *data, size_t len))block;
- (BOOL)streamDocument:(TPDocument *)doc toPath:(NSString *)path allowLoss:(BOOL)allowLoss lossy:(nullable BOOL *)lossy error:(NSString *_Nullable *_Nullable)error;
- (BOOL)appendGrowthOfDocument:(TPDocument *)doc;
@end

NS_ASSUME_NONNULL_END
