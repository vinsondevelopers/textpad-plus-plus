// Textpad++ — in-app acceptance tests (run with: Textpad++ --self-test results.json).
// GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>

@class TPMainWindowController;

@interface TPSelfTest : NSObject
// Returns the number of failed tests. Writes a JSON report (tests, executed command ids, benchmarks).
+ (int)runWithController:(TPMainWindowController *)c output:(NSString *)path;
@end
