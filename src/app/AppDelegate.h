// Textpad++ — application delegate. GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>

@class TPMainWindowController;
@class TPCommandLine;
extern NSString *const _Nonnull TPCommandLineNotification;   // forwarded arguments (mono-instance)

NS_ASSUME_NONNULL_BEGIN

@interface TPAppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong, readonly) TPMainWindowController *controller;
@property (nonatomic, copy, nullable) NSString *selfTestOutput;
@property (nonatomic, copy, nullable) NSString *snapshotOutput;   // --snapshot: render the window to PNG and exit
@property (nonatomic, copy) NSArray<NSString *> *launchFiles;
@property (nonatomic, strong, nullable) TPCommandLine *commandLine;   // parsed launch arguments
@property (nonatomic) BOOL secondaryInstance;                         // another Textpad++ was already running (-multiInst)
@property (nonatomic, strong, nullable) NSDate *launchStart;          // -loadingTime
@end

NS_ASSUME_NONNULL_END
