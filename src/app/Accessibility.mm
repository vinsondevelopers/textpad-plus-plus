// Textpad++ — accessibility element with actions. GPL-3.0-or-later.
#import "app/Accessibility.h"

@implementation TPAXElement
- (BOOL)accessibilityPerformPress { return self.pressHandler ? self.pressHandler() : NO; }
- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector {
    if (selector == @selector(accessibilityPerformPress)) return self.pressHandler != nil;
    return [super isAccessibilitySelectorAllowed:selector];
}
@end
