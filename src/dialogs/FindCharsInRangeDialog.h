// Textpad++ — Search > Find characters in range... (upstream WinControls/FindCharsInRange). GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>

@class TPMainWindowController;

NS_ASSUME_NONNULL_BEGIN

@interface TPFindCharsInRangeDialog : NSWindowController
+ (instancetype)sharedWithController:(TPMainWindowController *)c;
@property (nonatomic) NSInteger rangeMode;       // 0 non-ASCII (128–255), 1 ASCII (0–127), 2 custom range
@property (nonatomic, copy) NSString *rangeStart, *rangeEnd;
@property (nonatomic) BOOL directionDown, wrapAround;
- (IBAction)findNext:(nullable id)sender;        // the "Find" button
@end

NS_ASSUME_NONNULL_END
