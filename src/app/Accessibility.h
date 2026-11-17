// Textpad++ — accessibility element with actions (custom-drawn tab bar / status bar). GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface TPAXElement : NSAccessibilityElement
@property (nonatomic, copy, nullable) BOOL (^pressHandler)(void);
@end

NS_ASSUME_NONNULL_END
