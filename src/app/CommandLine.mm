// Textpad++ — command-line parameters (port of upstream winmain.cpp parsing). GPL-3.0-or-later.
#import "app/CommandLine.h"
#include <fnmatch.h>

@implementation TPCommandLine

+ (NSString *)helpText {
    return @"Usage:\n\n"
    "Textpad++ [--help] [-multiInst] [-noPlugin] [-lLanguage] [-udl=\"My UDL Name\"]\n"
    "[-LlangCode] [-nLineNumber] [-cColumnNumber] [-pPosition] [-xLeftPos] [-yTopPos]\n"
    "[-monitor] [-monitoringMode] [-nosession] [-notabbar] [-systemtray] [-loadingTime]\n"
    "[-alwaysOnTop] [-ro] [-fullReadOnly] [-fullReadOnlySavingForbidden] [-openSession] [-r]\n"
    "[-qt=\"a text to display.\" | -qf=\"/path/my quote.txt\"]\n"
    "[-qSpeed1|2|3] [-quickPrint] [-settingsDir=\"/path/settings dir/\"]\n"
    "[-openFoldersAsWorkspace]  [-titleAdd=\"additional title bar text\"]\n"
    "[filePath]\n\n"
    "--help: This help message\n"
    "-multiInst: Launch another Textpad++ instance\n"
    "-noPlugin: Launch Textpad++ without loading any plugin\n"
    "-l: Open file or Ghost type with syntax highlighting of choice\n"
    "-udl=\"My UDL Name\": Open file by applying User Defined Language\n"
    "-L: Apply indicated localization, langCode is a language file name, e.g. -Lfrench (menus and commands)\n"
    "-n: Scroll to indicated line on filePath\n"
    "-c: Scroll to indicated column on filePath\n"
    "-p: Scroll to indicated position on filePath\n"
    "-x: Move Textpad++ to indicated left side position on the screen\n"
    "-y: Move Textpad++ to indicated top position on the screen\n"
    "-monitor: Open files given in arguments with file monitoring enabled\n"
    "-monitoringMode: Monitoring all files opened in Textpad++\n"
    "-nosession: Launch Textpad++ without previous session\n"
    "-notabbar: Launch Textpad++ without tab bar\n"
    "-ro: Make the filePath read-only\n"
    "-fullReadOnly: Open all files read-only by default, toggling the R/O off and saving is allowed\n"
    "-fullReadOnlySavingForbidden: Open all files read-only by default, toggling the R/O off and saving is disabled\n"
    "-systemtray: Launch Textpad++ hidden (macOS has no system tray; click the Dock icon to show it)\n"
    "-loadingTime: Display Textpad++ loading time\n"
    "-alwaysOnTop: Make Textpad++ always on top\n"
    "-openSession: Open a session. filePath must be a session file\n"
    "-r: Open files recursively. This argument will be ignored if filePath contains no wildcard character\n"
    "-qt=\"text to display.\": Ghost type the given text\n"
    "-qf=\"/path/my quote.txt\": Ghost type a file content via the file path\n"
    "-qSpeed: Ghost typing speed. Value from 1 to 3 for slow, fast and fastest\n"
    "-quickPrint: Print the file given as argument then quit Textpad++\n"
    "-settingsDir=\"/path/settings dir/\": Override the default settings dir\n"
    "-openFoldersAsWorkspace: open filePath of folder(s) as workspace (opens the folder's files until Folder as Workspace exists)\n"
    "-titleAdd=\"string\": add string to Textpad++ title bar\n"
    "filePath: file or folder name to open (absolute or relative path name)\n\n"
    "Also: open -a Textpad++ file ...   (Finder / Launch Services)\n";
}

static NSString *unquote(NSString *s) {
    if (s.length >= 2 && [s hasPrefix:@"\""] && [s hasSuffix:@"\""]) return [s substringWithRange:NSMakeRange(1, s.length - 2)];
    return s;
}

static BOOL numberAfter(NSString *arg, NSString *prefix, NSInteger *out) {
    if (![arg hasPrefix:prefix] || arg.length <= prefix.length) return NO;
    NSString *rest = [arg substringFromIndex:prefix.length];
    NSScanner *sc = [NSScanner scannerWithString:rest];
    NSInteger v = 0;
    if (![sc scanInteger:&v] || !sc.isAtEnd) return NO;
    *out = v;
    return YES;
}

static void expandWildcard(NSString *pattern, BOOL recursive, NSMutableArray *out) {
    NSString *dir = pattern.stringByDeletingLastPathComponent, *mask = pattern.lastPathComponent;
    if (!dir.length) dir = @".";
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *en = [fm enumeratorAtURL:[NSURL fileURLWithPath:dir] includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                            options:NSDirectoryEnumerationSkipsHiddenFiles | (recursive ? 0 : NSDirectoryEnumerationSkipsSubdirectoryDescendants)
                                       errorHandler:nil];
    NSMutableArray *found = [NSMutableArray array];
    for (NSURL *u in en) {
        NSNumber *isDir = nil;
        [u getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if (isDir.boolValue) continue;
        if (fnmatch(mask.fileSystemRepresentation, u.lastPathComponent.fileSystemRepresentation, FNM_CASEFOLD) == 0)
            [found addObject:u.path.stringByStandardizingPath];   // same form as the other file arguments
    }
    [found sortUsingSelector:@selector(localizedStandardCompare:)];
    [out addObjectsFromArray:found];
}

+ (instancetype)parseArguments:(NSArray<NSString *> *)args currentDirectory:(NSString *)cwd {
    TPCommandLine *cl = [TPCommandLine new];
    cl.line = cl.column = cl.position = -1;
    NSMutableArray *rawFiles = [NSMutableArray array];
    NSDictionary<NSString *, NSString *> *flags = @{
        @"--help": @"help", @"-multiInst": @"multiInst", @"-noPlugin": @"noPlugin", @"-monitor": @"monitor", @"-monitoringMode": @"monitoringMode",
        @"-nosession": @"noSession", @"-notabbar": @"noTabBar", @"-ro": @"readOnly", @"-fullReadOnly": @"fullReadOnly",
        @"-fullReadOnlySavingForbidden": @"fullReadOnlySavingForbidden", @"-systemtray": @"systemTray", @"-loadingTime": @"loadingTime",
        @"-alwaysOnTop": @"alwaysOnTop", @"-openSession": @"openSession", @"-r": @"recursive", @"-quickPrint": @"quickPrint",
        @"-openFoldersAsWorkspace": @"openFoldersAsWorkspace"};
    for (NSUInteger i = 0; i < args.count; ++i) {
        NSString *a = args[i];
        if (NSString *key = flags[a]) { [cl setValue:@YES forKey:key]; continue; }
        if ([a isEqualToString:@"--self-test"] && i + 1 < args.count) { cl.selfTestOutput = args[++i]; continue; }
        if ([a isEqualToString:@"--snapshot"] && i + 1 < args.count) { cl.snapshotOutput = args[++i]; continue; }
        if (([a isEqualToString:@"--crash-phase1"] || [a isEqualToString:@"--crash-phase2"]) && i + 1 < args.count) {
            cl.crashPhase = [a hasSuffix:@"1"] ? 1 : 2; cl.crashDir = args[++i]; continue;
        }
        if ([a hasPrefix:@"-psn_"]) continue;   // Finder process serial number (older macOS)
        NSInteger n = 0;
        if ([a hasPrefix:@"-udl="]) { cl.udl = unquote([a substringFromIndex:5]); continue; }
        if ([a hasPrefix:@"-qn="]) { cl.ghostName = unquote([a substringFromIndex:4]); continue; }
        if ([a hasPrefix:@"-qt="]) { cl.ghostText = unquote([a substringFromIndex:4]); continue; }
        if ([a hasPrefix:@"-qf="]) { cl.ghostFile = unquote([a substringFromIndex:4]); continue; }
        if ([a hasPrefix:@"-qSpeed"]) { NSInteger s = [[a substringFromIndex:7] integerValue]; cl.ghostSpeed = (s >= 1 && s <= 3) ? s : 0; continue; }
        if ([a hasPrefix:@"-settingsDir="]) { cl.settingsDir = unquote([a substringFromIndex:13]).stringByExpandingTildeInPath; continue; }
        if ([a hasPrefix:@"-titleAdd="]) { cl.titleAdd = unquote([a substringFromIndex:10]); continue; }
        if (numberAfter(a, @"-n", &n)) { cl.line = n; continue; }
        if (numberAfter(a, @"-c", &n)) { cl.column = n; continue; }
        if (numberAfter(a, @"-p", &n)) { cl.position = n; continue; }
        if (numberAfter(a, @"-x", &n)) { cl.x = n; cl.hasX = YES; continue; }
        if (numberAfter(a, @"-y", &n)) { cl.y = n; cl.hasY = YES; continue; }
        if ([a hasPrefix:@"-l"] && a.length > 2 && ![a hasPrefix:@"-loadingTime"]) { cl.language = [a substringFromIndex:2]; continue; }
        if ([a hasPrefix:@"-L"] && a.length > 2) { cl.localization = [a substringFromIndex:2]; continue; }
        if ([a hasPrefix:@"-"] && ![a hasPrefix:@"--"]) {
            // "-key value": the NSUserDefaults argument domain (not persisted), e.g. -pref.darkMode 1
            if (i + 1 < args.count && ![args[i + 1] hasPrefix:@"-"]) ++i;
            continue;
        }
        if ([a hasPrefix:@"--"]) continue;
        [rawFiles addObject:a];
    }
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *f in rawFiles) {
        NSString *p = f.stringByExpandingTildeInPath;
        if (![p hasPrefix:@"/"]) p = [cwd stringByAppendingPathComponent:p];
        p = p.stringByStandardizingPath;
        if ([p.lastPathComponent rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"*?"]].location != NSNotFound)
            expandWildcard(p, cl.recursive, files);
        else
            [files addObject:p];
    }
    cl.files = files;
    return cl;
}

- (BOOL)hasDocumentOptions {
    return self.language || self.udl || self.line >= 0 || self.column >= 0 || self.position >= 0 || self.readOnly || self.monitor;
}

- (NSDictionary *)propertyList {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *k in @[@"help", @"multiInst", @"noPlugin", @"monitor", @"monitoringMode", @"noSession", @"noTabBar", @"readOnly", @"fullReadOnly",
                          @"fullReadOnlySavingForbidden", @"systemTray", @"loadingTime", @"alwaysOnTop", @"openSession", @"recursive", @"quickPrint",
                          @"openFoldersAsWorkspace", @"hasX", @"hasY", @"line", @"column", @"position", @"x", @"y", @"ghostSpeed"])
        d[k] = [self valueForKey:k];
    for (NSString *k in @[@"language", @"udl", @"localization", @"ghostName", @"ghostText", @"ghostFile", @"settingsDir", @"titleAdd"])
        if ([self valueForKey:k]) d[k] = [self valueForKey:k];
    d[@"files"] = self.files ?: @[];
    return d;
}

+ (instancetype)commandLineFromPropertyList:(NSDictionary *)plist {
    TPCommandLine *cl = [TPCommandLine new];
    cl.line = cl.column = cl.position = -1;
    for (NSString *k in plist) {
        @try { [cl setValue:plist[k] forKey:k]; } @catch (NSException *e) {}
    }
    return cl;
}

@end
