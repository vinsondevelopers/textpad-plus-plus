// Textpad++ — CSV Rainbow Columns and Align / Shrink Columns. GPL-3.0-or-later.
#pragma once
#import "app/MainWindowController.h"

NS_ASSUME_NONNULL_BEGIN
BOOL TPIsCsvPath(NSString *_Nullable path);   // .csv .tsv .tab .psv .dsv

@interface TPMainWindowController (CsvColumns)
- (void)csvStartWatching;
- (void)csvRainbowTick;
- (void)csvRainbowStyleLines:(sptr_t)first to:(sptr_t)last inView:(ScintillaView *)v;
- (void)csvReformat:(BOOL)alignColumns;   // selection (whole lines) or the document
@end
NS_ASSUME_NONNULL_END
