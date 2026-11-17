// Textpad++ — updater. GPL-3.0-or-later.
#import "app/Updater.h"
#import "app/Preferences.h"
#import "commands/CommandRegistry.h"

using namespace npp;

@implementation TPUpdateInfo
@end

@implementation TPUpdater

+ (instancetype)shared {
    static TPUpdater *u;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ u = [TPUpdater new]; });
    return u;
}

- (NSURL *)feedURL {
    NSString *s = [TPPrefs s:@"pref.updateFeedURL"];
    if (!s.length) s = [NSBundle.mainBundle objectForInfoDictionaryKey:@"TPUpdateFeedURL"];
    if (!s.length || [s hasPrefix:@"@"]) return nil;
    return [NSURL URLWithString:s];
}

- (NSString *)currentVersion { return [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0"; }

- (void)registerCommands {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    __weak TPUpdater *ws = self;
    [reg registerCommand:IDM_UPDATE_NPP handler:^(int c) { [ws checkForUpdatesInteractively:YES]; }];
    [reg registerCommand:IDM_CONFUPDATERPROXY handler:^(int c) { [ws showProxyDialog]; }];
}

// ---------------------------------------------------------------- proxy
- (void)setProxyHost:(NSString *)host port:(NSInteger)port {
    [TPPrefs set:host ?: @"" forKey:@"updater.proxyHost"];
    [TPPrefs set:@(MAX((NSInteger)0, port)) forKey:@"updater.proxyPort"];
}

- (NSURLSessionConfiguration *)sessionConfiguration {
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 30;
    NSString *host = [TPPrefs s:@"updater.proxyHost"];
    const NSInteger port = [TPPrefs i:@"updater.proxyPort"];
    if (host.length && port > 0) {
        cfg.connectionProxyDictionary = @{
            (NSString *)kCFNetworkProxiesHTTPEnable: @YES, (NSString *)kCFNetworkProxiesHTTPProxy: host, (NSString *)kCFNetworkProxiesHTTPPort: @(port),
            @"HTTPSEnable": @YES, @"HTTPSProxy": host, @"HTTPSPort": @(port),
        };
    }
    return cfg;
}

- (void)showProxyDialog {
    NSAlert *a = [NSAlert new];
    a.messageText = @"Proxy settings";
    a.informativeText = @"Used by Help > Update Textpad++ and the auto-updater. Leave the server empty for a direct connection.";
    NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 58)];
    NSTextField *hl = [NSTextField labelWithString:@"Proxy server:"], *pl = [NSTextField labelWithString:@"Port:"];
    hl.frame = NSMakeRect(0, 34, 90, 20); pl.frame = NSMakeRect(0, 4, 90, 20);
    NSTextField *host = [NSTextField textFieldWithString:[TPPrefs s:@"updater.proxyHost"] ?: @""];
    NSTextField *port = [NSTextField textFieldWithString:[TPPrefs i:@"updater.proxyPort"] > 0 ? [@([TPPrefs i:@"updater.proxyPort"]) stringValue] : @""];
    host.frame = NSMakeRect(94, 32, 226, 22); port.frame = NSMakeRect(94, 2, 80, 22);
    host.placeholderString = @"proxy.example.com"; port.placeholderString = @"8080";
    for (NSView *x in @[hl, pl, host, port]) [v addSubview:x];
    a.accessoryView = v;
    [a addButtonWithTitle:@"OK"];
    [a addButtonWithTitle:@"Cancel"];
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    [self setProxyHost:[host.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] port:port.integerValue];
}

// ---------------------------------------------------------------- feed
+ (TPUpdateInfo *)parseFeed:(NSData *)xml {
    NSXMLDocument *doc = xml ? [[NSXMLDocument alloc] initWithData:xml options:0 error:nil] : nil;
    NSXMLElement *root = doc.rootElement;
    if (![root.name isEqualToString:@"GUP"]) return nil;
    NSString *(^text)(NSString *) = ^NSString *(NSString *n) {
        return [[[root elementsForName:n].firstObject stringValue] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    };
    TPUpdateInfo *i = [TPUpdateInfo new];
    i.version = text(@"Version") ?: @"";
    NSString *loc = text(@"Location");
    i.location = loc.length ? [NSURL URLWithString:loc] : nil;
    i.sha256 = text(@"SHA256");
    i.signature = text(@"Signature");
    NSString *dmg = text(@"DmgLocation");
    i.dmgLocation = dmg.length ? [NSURL URLWithString:dmg] : nil;
    NSString *need = text(@"NeedToBeUpdated");
    i.needToBeUpdated = !need.length || [need caseInsensitiveCompare:@"yes"] == NSOrderedSame;
    return i.version.length ? i : nil;
}

// numeric dotted comparison: 0.10.0 > 0.9.9, 1.0 == 1.0.0
+ (NSComparisonResult)compareVersion:(NSString *)a with:(NSString *)b {
    NSArray *x = [a componentsSeparatedByString:@"."], *y = [b componentsSeparatedByString:@"."];
    for (NSUInteger i = 0; i < MAX(x.count, y.count); ++i) {
        const NSInteger p = i < x.count ? [x[i] integerValue] : 0, q = i < y.count ? [y[i] integerValue] : 0;
        if (p != q) return p < q ? NSOrderedAscending : NSOrderedDescending;
    }
    return NSOrderedSame;
}

- (BOOL)isNewer:(TPUpdateInfo *)info {
    return info.needToBeUpdated && info.location && [TPUpdater compareVersion:info.version with:self.currentVersion] == NSOrderedDescending;
}

// synchronous: the request runs on NSURLSession's queue while this thread waits (file: and https: alike)
- (NSData *)fetch:(NSURL *)url error:(NSString **)error {
    __block NSData *data = nil;
    __block NSString *err = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSURLSession *s = [NSURLSession sessionWithConfiguration:[self sessionConfiguration]];
    NSURL *req = url;
    if (!url.isFileURL) {   // upstream sends the running version (getDownloadUrl.php?version=…); a static feed ignores it
        NSURLComponents *uc = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        NSMutableArray *q = [uc.queryItems mutableCopy] ?: [NSMutableArray array];
        [q addObject:[NSURLQueryItem queryItemWithName:@"version" value:self.currentVersion]];
        uc.queryItems = q;
        req = uc.URL ?: url;
    }
    [[s dataTaskWithURL:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        NSInteger status = [r isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)r).statusCode : 200;
        if (e) err = e.localizedDescription;
        else if (status >= 400) err = [NSString stringWithFormat:@"The server answered %ld.", (long)status];
        else data = d;
        dispatch_semaphore_signal(done);
    }] resume];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC)));
    [s finishTasksAndInvalidate];
    if (!data && !err) err = @"The request timed out.";
    if (error) *error = err;
    return data;
}

- (TPUpdateInfo *)fetchFeed:(NSURL *)url error:(NSString **)error {
    NSString *err = nil;
    NSData *d = [self fetch:url error:&err];
    if (!d) { if (error) *error = err; return nil; }
    TPUpdateInfo *i = [TPUpdater parseFeed:d];
    if (!i && error) *error = @"The update information is not a GUP XML file.";
    return i;
}

- (void)checkAtLaunch {
    if (![TPPrefs b:@"pref.autoUpdater"] || !self.feedURL) return;
    NSDate *last = [[NSUserDefaults standardUserDefaults] objectForKey:@"updater.lastCheck"];
    if (last && -last.timeIntervalSinceNow < 15 * 24 * 3600) return;   // upstream: every 15 days
    [self checkForUpdatesInteractively:NO];
}

- (void)checkForUpdatesInteractively:(BOOL)interactive {
    NSURL *feed = self.feedURL;
    if (!feed) {
        if (interactive)
            [_controller showMessage:@"This copy of Textpad++ has no update address."
                         informative:@"It was built without UPDATE_URL. Download new versions from the website you got Textpad++ from."];
        return;
    }
    [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:@"updater.lastCheck"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *err = nil;
        TPUpdateInfo *info = [self fetchFeed:feed error:&err];
        dispatch_async(dispatch_get_main_queue(), ^{ [self handleUpdate:info error:err interactive:interactive]; });
    });
}

// GUP: "An update package is available, do you want to download it?" / "No update is available."
- (void)handleUpdate:(TPUpdateInfo *)info error:(NSString *)error interactive:(BOOL)interactive {
    TPMainWindowController *c = _controller;
    if (!info) {
        if (interactive) [c showMessage:@"Cannot check for updates" informative:error];
        return;
    }
    if (![self isNewer:info]) {
        if (interactive) [c showMessage:@"No update is available." informative:[NSString stringWithFormat:@"Textpad++ %@ is the current version.", self.currentVersion]];
        return;
    }
    // Preferences > MISC. > Install updates automatically: no question, it is installed when Textpad++ quits
    if (!interactive && [TPPrefs b:@"pref.autoInstallUpdates"]) { [self installUpdate:info interactive:NO]; return; }
    NSInteger r = [c prompt:[NSString stringWithFormat:@"An update package is available (Textpad++ %@), do you want to install it?", info.version]
                informative:[NSString stringWithFormat:@"You have version %@. Textpad++ updates itself; your documents stay open.", self.currentVersion] buttons:@[@"Yes", @"No"]];
    if (r != 0) return;
    [self installUpdate:info interactive:YES];
}

- (NSString *)downloadUpdateFrom:(NSURL *)url error:(NSString **)error {
    NSString *dir = _downloadDirectoryOverride ?: NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory, NSUserDomainMask, YES).firstObject;
    NSString *name = url.lastPathComponent.length ? url.lastPathComponent : [NSString stringWithFormat:@"Textpad++-%@.dmg", self.currentVersion];
    __block NSString *dest = nil, *err = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSURLSession *s = [NSURLSession sessionWithConfiguration:[self sessionConfiguration]];
    [[s downloadTaskWithURL:url completionHandler:^(NSURL *tmp, NSURLResponse *r, NSError *e) {
        NSInteger status = [r isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)r).statusCode : 200;
        if (e || !tmp || status >= 400) { err = e.localizedDescription ?: [NSString stringWithFormat:@"The server answered %ld.", (long)status]; dispatch_semaphore_signal(done); return; }
        NSString *target = [dir stringByAppendingPathComponent:name];
        for (int n = 2; [[NSFileManager defaultManager] fileExistsAtPath:target]; ++n)   // Finder-style "name 2.dmg"
            target = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %d.%@", name.stringByDeletingPathExtension, n, name.pathExtension]];
        NSError *me = nil;
        if ([[NSFileManager defaultManager] moveItemAtURL:tmp toURL:[NSURL fileURLWithPath:target] error:&me]) dest = target;
        else err = me.localizedDescription;
        dispatch_semaphore_signal(done);
    }] resume];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(600 * NSEC_PER_SEC)));
    [s finishTasksAndInvalidate];
    if (!dest && error) *error = err ?: @"The download timed out.";
    return dest;
}

@end
