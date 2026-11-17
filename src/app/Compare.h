// Textpad++ — View > Compare (two documents side by side, differences marked). GPL-3.0-or-later.
#pragma once
#import "app/MainWindowController.h"

NS_ASSUME_NONNULL_BEGIN
typedef struct { NSUInteger changed, added, deleted, hunks; } TPCompareSummary;
extern NSInteger TPComparePickOverride;   // tests: index of the "Compare with" choice (-1 = ask)

@interface TPMainWindowController (Compare)
@property (nonatomic, readonly) BOOL isComparing;
@property (nonatomic, readonly) TPCompareSummary compareSummary;
- (void)compareStart;          // current document with the other view's, or with one picked from the open documents
- (void)compareRun;            // again, after edits (also automatic)
- (void)compareJump:(BOOL)forward;
- (void)compareClear;
@end
NS_ASSUME_NONNULL_END
