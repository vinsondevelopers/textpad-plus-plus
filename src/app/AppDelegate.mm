// Textpad++ — application delegate. GPL-3.0-or-later.
#import "app/AppDelegate.h"
#import "app/Sci.h"
#import "app/Document.h"
#import "app/CommandLine.h"
#import "panels/Panels.h"
#import "plugins/PluginHost.h"
#import "app/Updater.h"
#import "app/SystemTray.h"
#import "app/MainWindowController.h"
#import "app/Features.h"
#import "app/Localization.h"
#import "panels/PreviewPanel.h"
#import "app/Session.h"
#import "testing/SelfTest.h"
#import "testing/Audit.h"
#import "app/LanguageService.h"
#import "app/Preferences.h"
#import "app/UserDefinedLanguages.h"
#import "dialogs/UDLDialog.h"
#import "dialogs/StyleConfigurator.h"
#import "dialogs/ShortcutMapper.h"
#import "dialogs/FindCharsInRangeDialog.h"

using namespace npp;

@implementation TPAppDelegate {
    TPMainWindowController *_controller;
    NSMutableArray<NSString *> *_pendingOpens;
    BOOL _launched;
}

- (instancetype)init {
    if ((self = [super init])) {
        _pendingOpens = [NSMutableArray array];
        _launchFiles = @[];
    }
    return self;
}

- (TPMainWindowController *)controller { return _controller; }

- (void)applicationWillFinishLaunching:(NSNotification *)n {
    [TPPrefs registerDefaults];
    if (!self.selfTestOutput && !self.snapshotOutput && !self.commandLine.crashPhase) [[TPSession shared] importPreferencesFromCloud];   // Settings on cloud
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud integerForKey:@"AnsiCodepage"] > 0) tpp::setAnsiCodepage(static_cast<int>([ud integerForKey:@"AnsiCodepage"]));
    NSString *theme = [ud stringForKey:@"ThemePath"];
    if (theme.length && [[NSFileManager defaultManager] fileExistsAtPath:theme] && !self.selfTestOutput) [[TPLanguageService shared] loadTheme:theme error:nil];
    _controller = [TPMainWindowController new];
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    [_controller registerFileCommands:reg];
    [_controller registerEditCommands:reg];
    [_controller registerSearchCommands:reg];
    [_controller registerViewCommands:reg];
    [_controller registerEncodingCommands:reg];
    [_controller registerLanguageCommands:reg];
    [_controller registerToolCommands:reg];
    [_controller registerMacroCommands:reg];
    [_controller registerWindowAndHelpCommands:reg];
    [_controller registerPanelCommands];
    [_controller registerFeatureCommands:reg];   // Live Preview, Compare, Command Palette, ...
    NSApp.mainMenu = [reg buildMainMenu];
    for (NSString *t in @[@"File", @"Window", @"Macro", @"Run", @"Language"]) [reg topLevelMenuNamed:t].delegate = _controller;
    [TPPluginHost shared].controller = _controller;
    [[TPPluginHost shared] registerCommands];   // Import plugin(s), Plugins Admin, the Plugins menu
    [TPUpdater shared].controller = _controller;
    [[TPUpdater shared] registerCommands];      // ? > Update Textpad++, ? > Set Updater Proxy...
    [_controller registerTrayCommands];         // the menu bar extra's menu (upstream system tray)
    // Preferences > General > custom dialog font: every Textpad++ window but the editor window, when it is shown
    __weak TPMainWindowController *wc = _controller;
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
        NSWindow *w = n.object;
        if (w != wc.window) { TPApplyDialogFont(w); [[TPLocalization shared] translateWindow:w]; }   // + the interface language
    }];
    [TPUserLanguages shared];
    [_controller applyAllPreferences];
}

static std::string textOf(TPMainWindowController *c, TPDocument *d) {
    __block std::string t;
    [c withDocument:d perform:^(ScintillaView *v) { t = sciGetText(v); }];
    return t;
}

// kill -9 recovery test (T-SESS-KILL-001): phase 1 leaves unsaved edits and waits to be killed; phase 2 restores
// the session written by the periodic snapshot and reports what it found.
- (void)runCrashPhase:(NSInteger)phase dir:(NSString *)dir {
    _controller.selfTestMode = YES;
    _controller.window.alphaValue = 0;
    [_controller.window orderFront:nil];
    TPSession *s = [TPSession shared];
    NSString *edited = [dir stringByAppendingPathComponent:@"edited.txt"];
    NSString *marker = @"Unsaved text that must survive kill -9";
    if (phase == 1) {
        [s restoreIntoController:_controller];
        [_controller newDocument];
        SCI(_controller.editor, SCI_ADDTEXT, marker.length, reinterpret_cast<sptr_t>(marker.UTF8String));
        [_controller openFile:edited];
        SCI(_controller.editor, SCI_DOCUMENTEND);
        SCI(_controller.editor, SCI_ADDTEXT, 6, reinterpret_cast<sptr_t>(" edit\n"));
        [_controller refreshUI];
        [s writeSnapshotForController:_controller];   // what the periodic backup timer does
        [s startPeriodicBackupForController:_controller];
        [@"ready" writeToFile:[dir stringByAppendingPathComponent:@"ready"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;   // keep running until killed
    }
    NSMutableArray *problems = [NSMutableArray array];
    if (![s restoreIntoController:_controller]) [problems addObject:@"nothing restored"];
    TPDocument *untitled = nil, *file = nil;
    for (TPDocument *d in _controller.allDocuments) {
        std::string t = textOf(_controller, d);
        if (d.isUntitled && t == StdStr(marker)) untitled = d;
        if ([d.path isEqualToString:edited]) file = d;
    }
    if (!untitled || !untitled.dirty) [problems addObject:@"unsaved new document not restored"];
    if (!file) [problems addObject:@"edited file not reopened"];
    else if (textOf(_controller, file) != "original\n edit\n" || !file.dirty) [problems addObject:@"unsaved edit of the file lost"];
    NSString *disk = [NSString stringWithContentsOfFile:edited encoding:NSUTF8StringEncoding error:nil];
    if (![disk isEqualToString:@"original\n"]) [problems addObject:@"file on disk changed"];
    if (problems.count) {
        NSMutableArray *docs = [NSMutableArray array];
        for (TPDocument *d in _controller.allDocuments)
            [docs addObject:[NSString stringWithFormat:@"[%@ path=%@ untitled=%d dirty=%d text=%@]", d.displayName, d.path, d.isUntitled, d.dirty,
                             NSStr(textOf(_controller, d).substr(0, 60))]];
        NSString *sess = [NSString stringWithContentsOfFile:s.sessionPath encoding:NSUTF8StringEncoding error:nil];
        [problems addObject:[NSString stringWithFormat:@"docs: %@ | session: %@", [docs componentsJoinedByString:@" "], [sess substringToIndex:MIN(sess.length, (NSUInteger)900)]]];
    }
    NSString *result = problems.count ? [@"FAIL: " stringByAppendingString:[problems componentsJoinedByString:@"; "]] : @"OK";
    [result writeToFile:[dir stringByAppendingPathComponent:@"result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    exit(0);
}

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    if (self.commandLine.crashPhase) { [self runCrashPhase:self.commandLine.crashPhase dir:self.commandLine.crashDir]; return; }
    if (self.selfTestOutput) {
        _controller.selfTestMode = YES;
        [_controller newDocument];
        [_controller.window orderFront:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            int failures = [NSProcessInfo processInfo].environment[@"TEXTPAD_AUDIT"].length
                ? [TPAudit runWithController:self->_controller output:self.selfTestOutput]
                : [TPSelfTest runWithController:self->_controller output:self.selfTestOutput];
            exit(failures == 0 ? 0 : 1);
        });
        return;
    }
    if (self.snapshotOutput) {
        _controller.selfTestMode = YES;   // no prompts, no recent-file persistence
        for (NSString *f in self.launchFiles) [_controller openFile:f];
        if (_controller.mainPane.documents.count == 0) [_controller newDocument];
        [_controller.window setFrame:NSMakeRect(80, 80, 1100, 720) display:YES];
        [_controller showWindow:nil];
        [_controller refreshUI];
        // TEXTPAD_SNAPSHOT_PANEL=prefs:<page> | udl[:<tab>] renders that dialog instead of the main window
        NSString *panel = [NSProcessInfo processInfo].environment[@"TEXTPAD_SNAPSHOT_PANEL"];
        NSWindow *target = self->_controller.window;
        if ([panel hasPrefix:@"prefs"]) {
            NSString *page = [panel containsString:@":"] ? [panel substringFromIndex:[panel rangeOfString:@":"].location + 1] : @"General";
            [[TPPreferencesWindow shared] showPage:page];
            target = [TPPreferencesWindow shared].window;
        } else if ([panel hasPrefix:@"udl"]) {
            TPUDLDialog *d = [TPUDLDialog sharedWithController:_controller];
            [d reloadLanguages];
            [d showWindow:nil];
            if ([panel containsString:@":"]) {
                NSTabView *tv = nil;
                for (NSView *sv in d.window.contentView.subviews) if ([sv isKindOfClass:[NSTabView class]]) tv = (NSTabView *)sv;
                [tv selectTabViewItemWithIdentifier:[panel substringFromIndex:[panel rangeOfString:@":"].location + 1]];
            }
            target = d.window;
        } else if ([panel hasPrefix:@"style"]) {
            TPStyleConfigurator *sc = [TPStyleConfigurator sharedWithController:_controller];
            [sc open];
            if ([panel containsString:@":"]) {
                NSArray *parts = [[panel substringFromIndex:[panel rangeOfString:@":"].location + 1] componentsSeparatedByString:@"/"];
                [sc selectLanguageNamed:parts[0]];
                if (parts.count > 1) [sc selectStyleNamed:parts[1]];
            }
            target = sc.window;
        } else if ([panel hasPrefix:@"shortcuts"]) {
            TPShortcutMapper *m = [TPShortcutMapper sharedWithController:_controller];
            NSInteger tab = [panel containsString:@":"] ? [[panel substringFromIndex:[panel rangeOfString:@":"].location + 1] integerValue] : 0;
            [m openOnTab:static_cast<TPMapperTab>(tab)];
            target = m.window;
        } else if ([panel hasPrefix:@"preview"]) {   // the Live Preview beside the first file (a web view: composited below)
            [_controller showLivePreview:YES];
        } else if ([panel isEqualToString:@"fcr"]) {
            TPFindCharsInRangeDialog *f = [TPFindCharsInRangeDialog sharedWithController:_controller];
            [f showWindow:nil];
            target = f.window;
        }
        const double wait = [panel hasPrefix:@"preview"] ? 2.5 : 1.0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSView *v = target.contentView;
            NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
            NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
            [target.effectiveAppearance performAsCurrentDrawingAppearance:^{
                [NSGraphicsContext saveGraphicsState];
                NSGraphicsContext.currentContext = ctx;
                [target.backgroundColor setFill];
                NSRectFill(NSMakeRect(0, 0, rep.pixelsWide, rep.pixelsHigh));
                [NSGraphicsContext restoreGraphicsState];
                [v displayRectIgnoringOpacity:v.bounds inContext:ctx];
            }];
            WKWebView *web = self->_controller.previewPanel.webView;
            if (web.window == target && !web.hiddenOrHasHiddenAncestor) {
                const NSRect wf = [web convertRect:web.bounds toView:v];
                [web takeSnapshotWithConfiguration:nil completionHandler:^(NSImage *img, NSError *e) {
                    [NSGraphicsContext saveGraphicsState];
                    NSGraphicsContext.currentContext = ctx;
                    NSRect r = wf;
                    if (v.isFlipped) r.origin.y = NSHeight(v.bounds) - NSMaxY(wf);   // the bitmap is not flipped
                    [img drawInRect:r];
                    [NSGraphicsContext restoreGraphicsState];
                    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:self.snapshotOutput atomically:YES];
                    exit(0);
                }];
                return;
            }
            [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:self.snapshotOutput atomically:YES];
            exit(0);
        });
        return;
    }
    if (![TPPrefs b:@"pref.recentDontCheck"]) {
        // Preferences > Recent Files History: drop entries whose file no longer exists
        NSArray *alive = [_controller.recentFiles filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *p, NSDictionary *b) {
            return [[NSFileManager defaultManager] fileExistsAtPath:p];
        }]];
        [_controller.recentFiles setArray:alive];
    }
    TPSession *session = [TPSession shared];
    TPCommandLine *cl = self.commandLine;
    if (!cl.noPlugin) [[TPPluginHost shared] loadInstalledPlugins];   // upstream loads plugins before the session
    // -nosession, or a second instance (-multiInst): no session restore/save and no snapshot, so the
    // instances never overwrite each other's session.xml and backups
    if (cl.noSession || self.secondaryInstance) session.disabled = YES;
    if (cl.openSession && [TPPrefs i:@"pref.multiInstance"] == 1) session.exitSessionPath = cl.files.firstObject;
    BOOL restored = [session restoreIntoController:_controller];
    NSArray<TPDocument *> *opened = cl ? [_controller applyCommandLine:cl] : @[];
    if (!cl) for (NSString *f in self.launchFiles) [_controller openFile:f];
    for (NSString *f in _pendingOpens) [_controller openFile:f];
    [_pendingOpens removeAllObjects];
    if (_controller.mainPane.documents.count == 0) {
        [_controller activatePane:_controller.mainPane];
        [_controller newDocument];
    }
    if (restored && [TPPrefs b:@"pref.newDocOnStartup"]) [_controller newDocument];
    [_controller restorePanelsForLaunch];
    [session startPeriodicBackupForController:_controller];
    [_controller showWindow:nil];
    [_controller.window makeKeyAndOrderFront:nil];
    [_controller refreshUI];
    _launched = YES;
    TPPluginNotify(NPPN_READY_CODE, nil);
    [[TPUpdater shared] checkAtLaunch];
    if (!self.secondaryInstance) {
        __weak TPAppDelegate *ws = self;
        [[NSDistributedNotificationCenter defaultCenter] addObserverForName:TPCommandLineNotification object:nil queue:NSOperationQueue.mainQueue
                                                                 usingBlock:^(NSNotification *note) {
            TPAppDelegate *d = ws;
            if (!d || [note.object isEqual:[@(getpid()) stringValue]]) return;
            [d.controller applyCommandLine:[TPCommandLine commandLineFromPropertyList:note.userInfo ?: @{}]];
            [d.controller.window makeKeyAndOrderFront:nil];
            [NSApp activateIgnoringOtherApps:YES];
        }];
    }
    if (cl.loadingTime && self.launchStart)
        [_controller showMessage:@"Loading time" informative:[NSString stringWithFormat:@"Loading time : %.3f seconds", -self.launchStart.timeIntervalSinceNow]];
    if (cl.quickPrint) {
        // -quickPrint: print the given file(s) without the print dialog, then quit
        for (TPDocument *d in opened) {
            [_controller activateDocument:d inPane:[_controller.mainPane indexOfDocument:d] != NSNotFound ? _controller.mainPane : _controller.subPane];
            [[TPCommandRegistry shared] execute:IDM_FILE_PRINTNOW];
        }
        [NSApp terminate:nil];
        return;
    }
    if (cl.systemTray) [NSApp hide:nil];   // macOS has no system tray: start hidden, the Dock icon shows it
}

- (void)application:(NSApplication *)app openURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *u in urls) {
        if (!u.isFileURL) continue;
        if (_launched) [_controller openFile:u.path];
        else [_pendingOpens addObject:u.path];
    }
    if (_launched) [_controller.window makeKeyAndOrderFront:nil];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if (self.selfTestOutput || self.snapshotOutput) return NSTerminateNow;
    if (![_controller saveDirtyWorkspacesForQuit]) return NSTerminateCancel;   // Project Panel workspaces
    TPPluginNotify(NPPN_BEFORESHUTDOWN_CODE, nil);
    if (![_controller prepareToQuit]) { TPPluginNotify(NPPN_CANCELSHUTDOWN_CODE, nil); return NSTerminateCancel; }
    TPPluginNotify(NPPN_SHUTDOWN_CODE, nil);
    return NSTerminateNow;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [_controller restoreFromTray];   // a click on the Dock icon brings the window back from the menu bar too
    return YES;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app { return YES; }

@end
