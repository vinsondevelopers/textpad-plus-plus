// Textpad++ — entry point. GPL-3.0-or-later.
//
//   Textpad++ [options] [file ...]       see "? > Command Line Arguments..." / --help (upstream winmain.cpp options)
//   Textpad++ --self-test <results.json> run the in-app acceptance suite and exit (status = failures)
//   Textpad++ --snapshot <out.png>       render the main window (or TEXTPAD_SNAPSHOT_PANEL) and exit
#import <Cocoa/Cocoa.h>
#import "app/AppDelegate.h"
#import "app/CommandLine.h"

NSString *const TPCommandLineNotification = @"com.textpadplusplus.app.commandLine";

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSDate *start = [NSDate date];
        NSMutableArray *args = [NSMutableArray array];
        for (int i = 1; i < argc; ++i) [args addObject:@(argv[i])];
        TPCommandLine *cl = [TPCommandLine parseArguments:args currentDirectory:[NSFileManager defaultManager].currentDirectoryPath];
        if (cl.help) {
            fputs([TPCommandLine helpText].UTF8String, stdout);
            return 0;
        }
        const BOOL testRun = cl.selfTestOutput || cl.snapshotOutput || cl.crashPhase;
        if (cl.crashPhase) {
            setenv("TEXTPAD_SUPPORT_DIR", cl.crashDir.fileSystemRepresentation, 1);   // shared by both phases
        } else if (testRun) {
            NSString *iso = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"textpad-selftest-support-%d", getpid()]];
            setenv("TEXTPAD_SUPPORT_DIR", iso.fileSystemRepresentation, 1);
        } else if (cl.settingsDir.length) {
            [[NSFileManager defaultManager] createDirectoryAtPath:cl.settingsDir withIntermediateDirectories:YES attributes:nil error:nil];
            setenv("TEXTPAD_SUPPORT_DIR", cl.settingsDir.fileSystemRepresentation, 1);
        }
        BOOL secondary = NO;
        if (!testRun) {
            // upstream mono-instance mode: hand the arguments to the running Textpad++ and quit
            NSString *bid = [NSBundle mainBundle].bundleIdentifier ?: @"com.textpadplusplus.app";
            NSMutableArray<NSRunningApplication *> *others = [NSMutableArray array];
            for (NSRunningApplication *a in [NSRunningApplication runningApplicationsWithBundleIdentifier:bid])
                if (a.processIdentifier != getpid()) [others addObject:a];
            NSInteger mode = [[NSUserDefaults standardUserDefaults] integerForKey:@"pref.multiInstance"];   // 0 mono, 1 on session, 2 multi
            if (others.count && !cl.multiInst && mode != 2) {
                [[NSDistributedNotificationCenter defaultCenter] postNotificationName:TPCommandLineNotification
                                                                               object:[@(getpid()) stringValue]
                                                                             userInfo:cl.propertyList deliverImmediately:YES];
                [others.firstObject activateWithOptions:NSApplicationActivateAllWindows];
                return 0;
            }
            secondary = others.count > 0;
        }
        NSApplication *app = [NSApplication sharedApplication];
        TPAppDelegate *delegate = [TPAppDelegate new];
        delegate.selfTestOutput = cl.selfTestOutput;
        delegate.snapshotOutput = cl.snapshotOutput;
        delegate.launchFiles = cl.files;
        delegate.commandLine = cl;
        delegate.secondaryInstance = secondary;
        delegate.launchStart = start;
        if (testRun) [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        else [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
