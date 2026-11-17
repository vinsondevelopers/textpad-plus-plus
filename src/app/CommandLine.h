// Textpad++ — command-line parameters (upstream winmain.cpp / CmdLineParams, "? > Command Line Arguments...").
// GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface TPCommandLine : NSObject
// args: argv without argv[0]; relative file names are resolved against cwd; wildcards are expanded (-r: recursively)
+ (instancetype)parseArguments:(NSArray<NSString *> *)args currentDirectory:(NSString *)cwd;
+ (NSString *)helpText;   // upstream COMMAND_ARG_HELP, Textpad++ wording

@property (nonatomic) BOOL help, multiInst, noPlugin, monitor, monitoringMode, noSession, noTabBar, readOnly, fullReadOnly,
                           fullReadOnlySavingForbidden, systemTray, loadingTime, alwaysOnTop, openSession, recursive, quickPrint,
                           openFoldersAsWorkspace;
@property (nonatomic, copy, nullable) NSString *language;      // -l<Language> (langs.model.xml name, e.g. -lpython)
@property (nonatomic, copy, nullable) NSString *udl;           // -udl="My UDL Name"
@property (nonatomic, copy, nullable) NSString *localization;  // -L<langCode> (accepted; Textpad++ is not localized)
@property (nonatomic, copy, nullable) NSString *ghostName, *ghostText, *ghostFile;   // -qn= / -qt= / -qf=
@property (nonatomic) NSInteger ghostSpeed;                    // -qSpeed1|2|3 (0 = default)
@property (nonatomic, copy, nullable) NSString *settingsDir;   // -settingsDir="..."
@property (nonatomic, copy, nullable) NSString *titleAdd;      // -titleAdd="..."
@property (nonatomic) NSInteger line, column, position;        // -n / -c / -p, -1 when absent
@property (nonatomic) NSInteger x, y;                          // -x / -y
@property (nonatomic) BOOL hasX, hasY;
@property (nonatomic, copy) NSArray<NSString *> *files;
@property (nonatomic, copy, nullable) NSString *selfTestOutput, *snapshotOutput;   // Textpad++ test options
@property (nonatomic) NSInteger crashPhase;                    // --crash-phase1/2 <dir>: kill -9 recovery test
@property (nonatomic, copy, nullable) NSString *crashDir;
@property (nonatomic, readonly) BOOL hasDocumentOptions;       // anything that applies to the opened files

// Forwarding to the running instance (mono-instance mode)
- (NSDictionary *)propertyList;
+ (instancetype)commandLineFromPropertyList:(NSDictionary *)plist;
@end

#ifdef __cplusplus
NSString *_Nullable TPQuoteNamed(NSString *name);   // -qn=: a quote by its quoter, or "random"
#endif

NS_ASSUME_NONNULL_END
