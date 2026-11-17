// Textpad++ — command audit (test-only). GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>
@class TPMainWindowController;
@interface TPAudit : NSObject
+ (int)runWithController:(TPMainWindowController *)c output:(NSString *)outPath;
@end
