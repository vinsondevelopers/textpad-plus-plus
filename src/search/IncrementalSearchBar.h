// Textpad++ — Search > Incremental Search (upstream FindIncrementDlg): a bar under the editor (or above it).
// GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>

@class TPMainWindowController;

NS_ASSUME_NONNULL_BEGIN

@interface TPIncrementalSearchBar : NSView <NSTextFieldDelegate>
- (instancetype)initWithController:(TPMainWindowController *)c;
@property (nonatomic, readonly) NSTextField *field;
@property (nonatomic, readonly) NSButton *matchCaseCheck, *highlightAllCheck, *countCheck;
@property (nonatomic, readonly) NSString *statusText;
@property (nonatomic) BOOL atTop;                          // the ˄ / ˅ button (upstream _incrementalSearchBarAtTop)
- (void)show;                                              // Search > Incremental Search
- (void)close;
- (void)textChanged;                                       // typing: search from the start of the selection
- (void)findNext:(BOOL)forward;                            // < / > / Enter / Shift+Enter
@end

NS_ASSUME_NONNULL_END
