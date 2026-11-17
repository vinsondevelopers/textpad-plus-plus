// Textpad++ — Plugins Admin. GPL-3.0-or-later.
#import "plugins/PluginsAdmin.h"
#import "plugins/PluginHost.h"
#import "app/MainWindowController.h"
#import "app/Updater.h"
#import "app/Preferences.h"
#include "core/Hashing.h"

using namespace npp;

@implementation TPPluginsAdmin {
    NSSegmentedControl *_tabs;
    NSMutableArray<NSArray<NSString *> *> *_rows;
    NSMutableArray *_objects;   // TPPlugin per Installed row, list entry per Available / Updates row
    NSArray<NSDictionary *> *_list;   // the online plugin list
    NSString *_listError;
    NSButton *_installButton;
}

+ (instancetype)shared {
    static TPPluginsAdmin *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [TPPluginsAdmin new]; });
    return s;
}

- (instancetype)init {
    NSPanel *w = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 640, 420)
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                              backing:NSBackingStoreBuffered defer:YES];
    w.title = @"Plugins Admin";
    w.releasedWhenClosed = NO;
    w.minSize = NSMakeSize(520, 300);
    if ((self = [super initWithWindow:w])) {
        _rows = [NSMutableArray array];
        _objects = [NSMutableArray array];
        NSView *cv = w.contentView;
        _tabs = [NSSegmentedControl segmentedControlWithLabels:@[@"Available", @"Updates", @"Installed", @"Incompatible"]
                                                  trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(tabChanged:)];
        _tabs.frame = NSMakeRect(16, 380, 360, 24);
        _tabs.autoresizingMask = NSViewMinYMargin;
        [cv addSubview:_tabs];
        NSScrollView *sc = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 92, 608, 280)];
        sc.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        sc.hasVerticalScroller = YES;
        _table = [[NSTableView alloc] initWithFrame:sc.bounds];
        for (NSArray *c in @[@[@"Plugin", @180], @[@"Version", @80], @[@"Folder", @330]]) {
            NSTableColumn *tc = [[NSTableColumn alloc] initWithIdentifier:c[0]];
            tc.title = c[0]; tc.width = [c[1] doubleValue];
            [_table addTableColumn:tc];
        }
        _table.dataSource = self; _table.delegate = self;
        _table.usesAlternatingRowBackgroundColors = YES;
        sc.documentView = _table;
        [cv addSubview:sc];
        _note = [NSTextField wrappingLabelWithString:@""];
        _note.frame = NSMakeRect(16, 40, 470, 44);
        _note.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
        _note.textColor = NSColor.secondaryLabelColor;
        [cv addSubview:_note];
        _installButton = [NSButton buttonWithTitle:@"Install" target:self action:@selector(installClicked:)];
        _installButton.frame = NSMakeRect(414, 12, 100, 28);
        _installButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
        [cv addSubview:_installButton];
        _removeButton = [NSButton buttonWithTitle:@"Remove" target:self action:@selector(removeClicked:)];
        _removeButton.frame = NSMakeRect(524, 12, 100, 28);
        _removeButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
        [cv addSubview:_removeButton];
        NSButton *import = [NSButton buttonWithTitle:@"Import plugin(s)..." target:self action:@selector(importClicked:)];
        import.frame = NSMakeRect(16, 12, 160, 28);
        import.autoresizingMask = NSViewMaxYMargin;
        [cv addSubview:import];
        self.tab = TPPluginsAdminInstalled;
    }
    return self;
}

- (void)showWindow:(id)sender {
    [self reload];
    self.window.alphaValue = [TPPluginHost shared].controller.selfTestMode ? 0 : 1;
    [self.window center];
    [super showWindow:sender];
}

- (void)setTab:(TPPluginsAdminTab)tab {
    _tab = tab;
    _tabs.selectedSegment = tab;
    [self reload];
}
- (void)tabChanged:(NSSegmentedControl *)s { self.tab = (TPPluginsAdminTab)s.selectedSegment; }
- (NSArray<NSArray<NSString *> *> *)rows { return _rows; }

- (void)reload {
    TPPluginHost *h = [TPPluginHost shared];
    [_rows removeAllObjects];
    [_objects removeAllObjects];
    NSString *note = @"";
    switch (_tab) {
        case TPPluginsAdminAvailable:
        case TPPluginsAdminUpdates: {
            if (!self.listURL) {
                note = @"This copy of Textpad++ has no plugin list address (built without UPDATE_URL). Install a .tpplugin bundle with Import plugin(s)...";
                break;
            }
            if (!_list) [self fetchList];
            for (NSDictionary *e in _list) {
                TPPlugin *installed = nil;
                for (TPPlugin *p in h.plugins) if (!p.removed && [p.moduleName.stringByDeletingPathExtension caseInsensitiveCompare:e[@"folder-name"] ?: @""] == NSOrderedSame) installed = p;
                const BOOL newer = installed && [TPUpdater compareVersion:e[@"version"] ?: @"0" with:installed.version.length ? installed.version : @"0"] == NSOrderedDescending;
                if (_tab == TPPluginsAdminAvailable ? installed != nil : !newer) continue;
                [_rows addObject:@[e[@"display-name"] ?: e[@"folder-name"] ?: @"?", e[@"version"] ?: @"", e[@"description"] ?: @""]];
                [_objects addObject:e];
            }
            note = _listError ?: (_rows.count ? [NSString stringWithFormat:@"From %@", self.listURL.absoluteString] : (_tab == TPPluginsAdminAvailable ? @"Every plugin of the list is installed." : @"No updates."));
            break;
        }
        case TPPluginsAdminInstalled:
            for (TPPlugin *p in h.plugins) {
                if (p.removed || p.builtIn) continue;   // built-in tools cannot be removed
                [_rows addObject:@[p.displayName, p.version, p.path.stringByDeletingLastPathComponent]];
                [_objects addObject:p];
            }
            note = [NSString stringWithFormat:@"Plugins folder: %@", h.pluginsDirectory];
            break;
        case TPPluginsAdminIncompatible:
            for (NSDictionary<NSString *, NSString *> *d in h.incompatible) [_rows addObject:@[d[@"path"].lastPathComponent, @"", d[@"reason"]]];
            note = @"These bundles were found but could not be loaded.";
            break;
    }
    [_table tableColumnWithIdentifier:@"Folder"].title = _tab == TPPluginsAdminIncompatible ? @"Reason" : (_tab == TPPluginsAdminInstalled ? @"Folder" : @"Description");
    _installButton.hidden = _tab != TPPluginsAdminAvailable && _tab != TPPluginsAdminUpdates;
    _installButton.title = _tab == TPPluginsAdminUpdates ? @"Update" : @"Install";
    _installButton.enabled = _objects.count > 0;
    _note.stringValue = note;
    _removeButton.enabled = _tab == TPPluginsAdminInstalled && _objects.count > 0;
    [_table reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return (NSInteger)_rows.count; }
- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    NSTextField *t = [tv makeViewWithIdentifier:col.identifier owner:self];
    if (!t) { t = [NSTextField labelWithString:@""]; t.identifier = col.identifier; t.lineBreakMode = NSLineBreakByTruncatingMiddle; }
    t.stringValue = _rows[(NSUInteger)row][[tv.tableColumns indexOfObject:col]];
    return t;
}

// ---------------------------------------------------------------- the online list (upstream nppPluginList, JSON)
//  {"plugins": [{"folder-name": "MyPlugin", "display-name": "My Plugin", "version": "1.2", "id": "<SHA-256 of the zip>",
//                "repository": "https://…/MyPlugin.zip", "description": "…", "author": "…", "homepage": "…"}]}
// Its address: pref.pluginListURL, else Info.plist TPPluginListURL (make dmg UPDATE_URL=… puts pluginList.json next to update.xml)
- (NSURL *)listURL {
    NSString *s = [TPPrefs s:@"pref.pluginListURL"];
    if (!s.length) s = [NSBundle.mainBundle objectForInfoDictionaryKey:@"TPPluginListURL"];
    return s.length && ![s hasPrefix:@"@"] ? [NSURL URLWithString:s] : nil;
}

- (void)fetchList {
    NSString *err = nil;
    NSData *d = [self download:self.listURL error:&err];
    NSDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
    _list = [j[@"plugins"] isKindOfClass:NSArray.class] ? j[@"plugins"] : @[];
    _listError = d ? (j ? nil : @"The plugin list is not valid JSON.") : [@"Cannot read the plugin list: " stringByAppendingString:err ?: @""];
}

- (void)refreshList { _list = nil; [self reload]; }

- (NSData *)download:(NSURL *)url error:(NSString **)error {
    if (!url) return nil;
    __block NSData *data = nil;
    __block NSString *err = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSURLSession *s = [NSURLSession sessionWithConfiguration:[[TPUpdater shared] sessionConfiguration]];   // the updater proxy
    [[s dataTaskWithURL:url completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        NSInteger status = [r isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)r).statusCode : 200;
        if (e || status >= 400) err = e.localizedDescription ?: [NSString stringWithFormat:@"The server answered %ld.", (long)status];
        else data = d;
        dispatch_semaphore_signal(done);
    }] resume];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(120 * NSEC_PER_SEC)));
    [s finishTasksAndInvalidate];
    if (!data && error) *error = err ?: @"The request timed out.";
    return data;
}

- (void)installClicked:(id)sender { [self installSelected]; }

// download the zip, check its SHA-256 against the list's id, unpack it and import the .tpplugin inside
- (BOOL)installSelected {
    NSInteger r = _table.selectedRow;
    if ((_tab != TPPluginsAdminAvailable && _tab != TPPluginsAdminUpdates) || r < 0 || r >= (NSInteger)_objects.count) return NO;
    NSDictionary *e = _objects[(NSUInteger)r];
    TPMainWindowController *c = [TPPluginHost shared].controller;
    NSString *err = nil;
    NSData *zip = [self download:[NSURL URLWithString:e[@"repository"] ?: @""] error:&err];
    if (!zip) { [c showMessage:@"The plugin could not be downloaded" informative:err]; return NO; }
    std::string hex = tpp::hashHex(tpp::HashAlgorithm::SHA256, std::string(static_cast<const char *>(zip.bytes), zip.length));
    if ([e[@"id"] length] && ![@(hex.c_str()) isEqualToString:[e[@"id"] lowercaseString]]) {
        [c showMessage:@"The plugin was not installed" informative:@"The downloaded file does not match the list (SHA-256 differs)."];
        return NO;
    }
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *zipPath = [dir stringByAppendingPathComponent:@"plugin.zip"];
    [zip writeToFile:zipPath atomically:NO];
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ditto"];
    t.arguments = @[@"-x", @"-k", zipPath, [dir stringByAppendingPathComponent:@"x"]];
    NSError *te = nil;
    if (![t launchAndReturnError:&te]) { [c showMessage:@"The plugin could not be unpacked" informative:te.localizedDescription]; return NO; }
    [t waitUntilExit];
    NSString *bundle = nil;
    NSDirectoryEnumerator *en = [[NSFileManager defaultManager] enumeratorAtPath:[dir stringByAppendingPathComponent:@"x"]];
    for (NSString *f in en) if ([f.pathExtension isEqualToString:@"tpplugin"]) { bundle = [[dir stringByAppendingPathComponent:@"x"] stringByAppendingPathComponent:f]; break; }
    if (!bundle) { [c showMessage:@"The plugin was not installed" informative:@"The download holds no .tpplugin bundle."]; return NO; }
    NSArray *copied = [[TPPluginHost shared] importPluginsFromPaths:@[bundle]];
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
    [self reload];
    return copied.count > 0;
}

- (void)importClicked:(id)sender { [[TPCommandRegistry shared] execute:IDM_SETTING_IMPORTPLUGIN]; [self reload]; }
- (void)removeClicked:(id)sender { [self removeSelected]; }

- (BOOL)removeSelected {
    NSInteger r = _table.selectedRow;
    if (_tab != TPPluginsAdminInstalled || r < 0 || r >= (NSInteger)_objects.count) return NO;
    TPPlugin *p = _objects[(NSUInteger)r];
    TPMainWindowController *c = [TPPluginHost shared].controller;
    NSInteger answer = [c prompt:[NSString stringWithFormat:@"Remove %@?", p.displayName]
                     informative:@"Its folder goes to the Trash. The plugin stops working now and is unloaded when Textpad++ quits."
                         buttons:@[@"Remove", @"Cancel"]];
    if (answer != 0) return NO;
    NSString *err = nil;
    if (![[TPPluginHost shared] removePlugin:p error:&err]) { [c showMessage:@"The plugin could not be removed" informative:err]; return NO; }
    [self reload];
    return YES;
}

@end
