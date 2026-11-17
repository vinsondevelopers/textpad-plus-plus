// Textpad++ — sessions, snapshot and periodic backup. GPL-3.0-or-later.
// Session XML follows the upstream session.xml layout (NotepadPlus/Session/mainView|subView/File)
// so files can be exchanged; Textpad++-only attributes are prefixed "tp".
#import "app/Session.h"
#import "app/LargeFiles.h"
#import "app/MainWindowController.h"
#import "app/LanguageService.h"

void TPSessionReloadSettings(TPMainWindowController *c) {
    TPSession *s = [TPSession shared];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    s.rememberSession = [ud boolForKey:@"RememberSession"];
    s.snapshotEnabled = [ud boolForKey:@"SessionSnapshot"];
    s.backupInterval = MAX(1.0, [ud doubleForKey:@"BackupInterval"]);
    [s startPeriodicBackupForController:c];
}

@implementation TPSession {
    NSMutableDictionary<NSNumber *, NSString *> *_backupSignatures;   // per document: length/undo state last written
    NSTimer *_timer;
    __weak TPMainWindowController *_controller;
    NSMutableDictionary<NSNumber *, NSString *> *_backupPaths;   // doc uid -> backup file
    NSString *_settingsDirectory;
}

+ (instancetype)shared {
    static TPSession *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [TPSession new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSString *base = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject
                          stringByAppendingPathComponent:@"Textpad++"];
        NSString *override = [[NSProcessInfo processInfo].environment objectForKey:@"TEXTPAD_SUPPORT_DIR"];
        if (override.length) base = override;   // used by the self-test to stay isolated
        _supportDirectory = base;
        _backupDirectory = [base stringByAppendingPathComponent:@"backup"];
        _sessionPath = [base stringByAppendingPathComponent:@"session.xml"];
        [[NSFileManager defaultManager] createDirectoryAtPath:_backupDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        _rememberSession = [ud objectForKey:@"RememberSession"] ? [ud boolForKey:@"RememberSession"] : YES;
        _snapshotEnabled = [ud objectForKey:@"SessionSnapshot"] ? [ud boolForKey:@"SessionSnapshot"] : YES;
        _backupInterval = [ud objectForKey:@"BackupInterval"] ? [ud doubleForKey:@"BackupInterval"] : 7.0;
        _backupPaths = [NSMutableDictionary dictionary];
        _backupSignatures = [NSMutableDictionary dictionary];
    }
    return self;
}

// ---------------------------------------------------------------- settings on cloud (Preferences > Cloud & Link)
- (NSString *)settingsDirectory {
    if (!_settingsDirectory) [self reloadSettingsDirectory];
    return _settingsDirectory;
}

- (void)reloadSettingsDirectory {
    NSString *cloud = [[[NSUserDefaults standardUserDefaults] stringForKey:@"pref.cloudPath"] stringByExpandingTildeInPath];
    BOOL isDir = NO;
    if (cloud.length && [[NSFileManager defaultManager] fileExistsAtPath:cloud isDirectory:&isDir] && isDir) {
        NSString *dir = [cloud stringByAppendingPathComponent:@"Textpad++"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        _settingsDirectory = dir;
        _cloudActive = YES;
    } else {
        _settingsDirectory = _supportDirectory;
        _cloudActive = NO;
    }
}

static BOOL isSyncedPreference(NSString *k) {
    if ([k isEqualToString:@"pref.cloudPath"]) return NO;   // where the cloud is stays a local choice
    return [k hasPrefix:@"pref."] || [@[@"NewDocEOL", @"NewDocUniMode", @"NewDocCodepage", @"TabWidth", @"UseSpaces", @"WordWrap", @"ShowWhitespace",
                                         @"ShowEOL", @"ShowNPC", @"ShowCCUniEOL", @"ShowIndentGuide", @"ShowWrapSymbol", @"ShortcutScheme",
                                         @"AnsiCodepage", @"DateTimeReverseOrder", @"DateTimeCustomFormat", @"RememberSession", @"SessionSnapshot",
                                         @"BackupInterval"] containsObject:k];
}

- (void)exportPreferencesToCloud {
    if (!self.cloudActive) return;
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    NSDictionary *all = [[NSUserDefaults standardUserDefaults] persistentDomainForName:[NSBundle mainBundle].bundleIdentifier ?: @"com.textpadplusplus.app"];
    for (NSString *k in all) if (isSyncedPreference(k)) d[k] = all[k];
    [d writeToFile:[self.settingsDirectory stringByAppendingPathComponent:@"preferences.plist"] atomically:YES];
}

- (BOOL)importPreferencesFromCloud {
    if (!self.cloudActive) return NO;
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:[self.settingsDirectory stringByAppendingPathComponent:@"preferences.plist"]];
    if (!d) return NO;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    for (NSString *k in d) if (isSyncedPreference(k)) [ud setObject:d[k] forKey:k];
    return YES;
}

- (void)seedCloudFolder:(NSString *)cloudPath {
    NSString *dir = [cloudPath.stringByExpandingTildeInPath stringByAppendingPathComponent:@"Textpad++"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil]) return;
    for (NSString *item in @[@"shortcuts.xml", @"stylers.xml", @"themes", @"userDefineLangs", @"autoCompletion"]) {
        NSString *src = [self.settingsDirectory stringByAppendingPathComponent:item], *dst = [dir stringByAppendingPathComponent:item];
        if ([fm fileExistsAtPath:src] && ![fm fileExistsAtPath:dst]) [fm copyItemAtPath:src toPath:dst error:nil];
    }
    NSString *plist = [dir stringByAppendingPathComponent:@"preferences.plist"];
    if (![fm fileExistsAtPath:plist]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        NSDictionary *all = [[NSUserDefaults standardUserDefaults] persistentDomainForName:[NSBundle mainBundle].bundleIdentifier ?: @"com.textpadplusplus.app"];
        for (NSString *k in all) if (isSyncedPreference(k)) d[k] = all[k];
        [d writeToFile:plist atomically:YES];
    }
}

- (void)setRememberSession:(BOOL)v { _rememberSession = v; [[NSUserDefaults standardUserDefaults] setBool:v forKey:@"RememberSession"]; }
- (void)setSnapshotEnabled:(BOOL)v { _snapshotEnabled = v; [[NSUserDefaults standardUserDefaults] setBool:v forKey:@"SessionSnapshot"]; }

- (void)startPeriodicBackupForController:(TPMainWindowController *)c {
    _controller = c;
    [_timer invalidate];
    if (!_snapshotEnabled || _disabled) return;
    __weak TPSession *ws = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:MAX(1, _backupInterval) repeats:YES block:^(NSTimer *t) {
        TPSession *s = ws;
        TPMainWindowController *ctl = s->_controller;
        if (ctl && s.snapshotEnabled) [s writeSnapshotForController:ctl];
    }];
}

- (NSString *)backupPathForDocument:(TPDocument *)doc {
    NSString *existing = _backupPaths[@(doc.uid)];
    if (existing) return existing;
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"yyyy-MM-dd_HHmmss";
    NSString *name = [NSString stringWithFormat:@"%@@%@", doc.displayName, [f stringFromDate:[NSDate date]]];
    NSString *p = [_backupDirectory stringByAppendingPathComponent:name];
    _backupPaths[@(doc.uid)] = p;
    return p;
}

- (void)writeBackupsForController:(TPMainWindowController *)c {
    NSMutableSet *live = [NSMutableSet set];
    for (TPDocument *d in c.allDocuments) {
        if (!d.dirty) {
            NSString *old = _backupPaths[@(d.uid)];
            if (old) { [[NSFileManager defaultManager] removeItemAtPath:old error:nil]; [_backupPaths removeObjectForKey:@(d.uid)]; }
            continue;
        }
        NSString *p = [self backupPathForDocument:d];
        // rewrite only after a change since the last backup (a multi-GB document is not rewritten every few seconds)
        __block NSString *signature = nil;
        [c withDocument:d perform:^(ScintillaView *v) {
            signature = [NSString stringWithFormat:@"%ld/%ld/%ld", (long)SCI(v, SCI_GETLENGTH), (long)SCI(v, SCI_GETUNDOCURRENT), (long)SCI(v, SCI_GETUNDOACTIONS)];
        }];
        if (![_backupSignatures[@(d.uid)] isEqualToString:signature] || ![[NSFileManager defaultManager] fileExistsAtPath:p]) {
            TPSafeWriteFileProducer(p, ^BOOL(TPByteSink sink) {   // backups are raw UTF-8 buffer contents, written in pieces
                return [c forEachChunkOfDocument:d perform:^BOOL(const char *data, size_t len) { return sink(data, len); }];
            }, nil);
            _backupSignatures[@(d.uid)] = signature;
        }
        [live addObject:p];
    }
    // remove orphaned backups of closed documents
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:_backupDirectory error:nil]) {
        NSString *p = [_backupDirectory stringByAppendingPathComponent:f];
        if (![live containsObject:p] && ![_backupPaths.allValues containsObject:p]) [[NSFileManager defaultManager] removeItemAtPath:p error:nil];
    }
}

- (void)writeSnapshotForController:(TPMainWindowController *)c {
    if (_disabled) return;
    [self writeBackupsForController:c];
    [self saveSessionToPath:_sessionPath controller:c includeBackups:YES];
}

- (BOOL)saveForQuitWithController:(TPMainWindowController *)c {
    if (_exitSessionPath.length) [self saveSessionToPath:_exitSessionPath controller:c includeBackups:NO];
    if (_snapshotEnabled && !_disabled) {
        [self writeSnapshotForController:c];
        return YES;
    }
    for (TPDocument *d in c.allDocuments) {
        if (!d.dirty) continue;
        TPEditorPane *p = [c.mainPane indexOfDocument:d] != NSNotFound ? c.mainPane : c.subPane;
        [c activateDocument:d inPane:p];
        NSInteger r = [c prompt:[NSString stringWithFormat:@"Save file \"%@\" ?", d.path ?: d.displayName] informative:nil buttons:@[@"Yes", @"No", @"Cancel"]];
        if (r == 2 || r < 0) return NO;
        if (r == 0 && [c saveDocument:d] != TPSaveOK) return NO;
    }
    if (_disabled) return YES;   // -nosession: the previous session file is left untouched
    if (_rememberSession) [self saveSessionToPath:_sessionPath controller:c includeBackups:NO];
    else [[NSFileManager defaultManager] removeItemAtPath:_sessionPath error:nil];
    return YES;
}

// ---------------------------------------------------------------- XML
- (NSXMLElement *)elementForDocument:(TPDocument *)d pane:(TPEditorPane *)pane controller:(TPMainWindowController *)c includeBackups:(BOOL)backups {
    NSXMLElement *f = [NSXMLElement elementWithName:@"File"];
    if (pane.currentDocument == d) [pane saveCurrentPosition];
    TPViewPosition pos = [d positionForView:pane.viewIndex];
    TPLanguage *lang = [[TPLanguageService shared] languageForId:d.languageId];
    auto attr = [&](NSString *k, NSString *v) { [f addAttribute:[NSXMLNode attributeWithName:k stringValue:v ?: @""]]; };
    attr(@"firstVisibleLine", [@(pos.valid ? pos.firstVisibleLine : 0) stringValue]);
    attr(@"xOffset", [@(pos.valid ? pos.xOffset : 0) stringValue]);
    attr(@"startPos", [@(pos.valid ? pos.anchor : 0) stringValue]);
    attr(@"endPos", [@(pos.valid ? pos.caret : 0) stringValue]);
    attr(@"selMode", [@(pos.valid ? pos.selMode : 0) stringValue]);
    attr(@"lang", lang.shortName ?: @"Normal text");
    attr(@"encoding", [@(d.encoding.codepage) stringValue]);
    attr(@"userReadOnly", d.userReadOnly ? @"yes" : @"no");
    attr(@"filename", d.path ?: d.untitledName);
    NSString *backup = (backups && d.dirty) ? _backupPaths[@(d.uid)] : nil;
    attr(@"backupFilePath", backup ?: @"");
    attr(@"originalFileLastModifTimestamp", [@((long long)d.diskModDate.timeIntervalSince1970) stringValue]);
    attr(@"tabColourId", [@(d.tabColor) stringValue]);
    attr(@"tabPinned", d.pinned ? @"yes" : @"no");
    attr(@"tpLangId", d.languageId);
    attr(@"tpUniMode", [@(static_cast<int>(d.encoding.mode)) stringValue]);
    attr(@"tpEol", [@(d.eolMode) stringValue]);
    attr(@"tpMonitoring", d.monitoring ? @"yes" : @"no");
    // bookmarks
    [c withDocument:d perform:^(ScintillaView *v) {
        sptr_t line = SCI(v, SCI_MARKERNEXT, 0, 1 << TPP_MARK_BOOKMARK);
        while (line >= 0) {
            NSXMLElement *m = [NSXMLElement elementWithName:@"Mark"];
            [m addAttribute:[NSXMLNode attributeWithName:@"line" stringValue:[@(line) stringValue]]];
            [f addChild:m];
            line = SCI(v, SCI_MARKERNEXT, line + 1, 1 << TPP_MARK_BOOKMARK);
        }
    }];
    return f;
}

- (BOOL)saveSessionToPath:(NSString *)path controller:(TPMainWindowController *)c includeBackups:(BOOL)backups {
    NSXMLElement *root = [NSXMLElement elementWithName:@"NotepadPlus"];
    NSXMLElement *session = [NSXMLElement elementWithName:@"Session"];
    [session addAttribute:[NSXMLNode attributeWithName:@"activeView" stringValue:c.activePane == c.subPane ? @"1" : @"0"]];
    for (TPEditorPane *pane in @[c.mainPane, c.subPane]) {
        NSXMLElement *view = [NSXMLElement elementWithName:pane == c.mainPane ? @"mainView" : @"subView"];
        NSInteger active = pane.currentDocument ? [pane indexOfDocument:pane.currentDocument] : 0;
        [view addAttribute:[NSXMLNode attributeWithName:@"activeIndex" stringValue:[@(MAX(0, active)) stringValue]]];
        for (TPDocument *d in pane.documents) {
            if (d.isUntitled && !d.dirty && !backups) continue;
            if (d.isUntitled && !d.dirty && pane.documents.count == 1) continue;  // a lone empty "new 1" is not worth restoring
            if (d.isUntitled && !_backupPaths[@(d.uid)] && !(backups && d.dirty)) continue;
            [view addChild:[self elementForDocument:d pane:pane controller:c includeBackups:backups]];
        }
        [session addChild:view];
    }
    [root addChild:session];
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement:root];
    doc.characterEncoding = @"UTF-8";
    doc.version = @"1.0";
    NSData *data = [doc XMLDataWithOptions:NSXMLNodePrettyPrint];
    std::string bytes(static_cast<const char *>(data.bytes), data.length);
    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    return TPSafeWriteFile(path, bytes, nil);
}

- (BOOL)restoreIntoController:(TPMainWindowController *)c {
    if (_disabled || (!_rememberSession && !_snapshotEnabled)) return NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:_sessionPath]) return NO;
    return [self loadSessionFromPath:_sessionPath controller:c];
}

- (BOOL)loadSessionFromPath:(NSString *)path controller:(TPMainWindowController *)c {
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] options:0 error:nil];
    if (!doc) return NO;
    BOOL any = NO;
    NSArray *views = [doc nodesForXPath:@"//Session/mainView|//Session/subView" error:nil];
    TPDocument *activeDocs[2] = {nil, nil};
    for (NSXMLElement *view in views) {
        TPEditorPane *pane = [view.name isEqualToString:@"subView"] ? c.subPane : c.mainPane;
        NSInteger activeIndex = [[[view attributeForName:@"activeIndex"] stringValue] integerValue];
        NSInteger i = 0;
        for (NSXMLElement *f in [view elementsForName:@"File"]) {
            TPDocument *d = [self restoreFile:f intoPane:pane controller:c];
            if (d) {
                any = YES;
                if (i == activeIndex) activeDocs[pane.viewIndex] = d;
                ++i;
            }
        }
    }
    for (int v = 1; v >= 0; --v) {
        TPEditorPane *pane = v ? c.subPane : c.mainPane;
        if (activeDocs[v]) [c activateDocument:activeDocs[v] inPane:pane];
    }
    NSString *av = [[[doc nodesForXPath:@"//Session" error:nil].firstObject attributeForName:@"activeView"] stringValue];
    if ([av isEqualToString:@"1"] && activeDocs[1]) [c activatePane:c.subPane];
    else if (activeDocs[0]) [c activatePane:c.mainPane];
    return any;
}

- (TPDocument *)restoreFile:(NSXMLElement *)f intoPane:(TPEditorPane *)pane controller:(TPMainWindowController *)c {
    auto s = [&](NSString *k) -> NSString * { return [[f attributeForName:k] stringValue] ?: @""; };
    NSString *filename = s(@"filename");
    NSString *backup = s(@"backupFilePath");
    BOOL hasBackup = backup.length && [[NSFileManager defaultManager] fileExistsAtPath:backup];
    BOOL isFile = [filename hasPrefix:@"/"];
    BOOL keepAbsent = [[NSUserDefaults standardUserDefaults] boolForKey:@"pref.keepAbsentFiles"];
    if (!hasBackup && (!isFile || (![[NSFileManager defaultManager] fileExistsAtPath:filename] && !keepAbsent))) return nil;

    TPDocument *d = nil;
    if (isFile && [[NSFileManager defaultManager] fileExistsAtPath:filename]) {
        d = [c openFile:filename activate:NO error:nil];
    } else {
        d = [c newDocument];
        if (isFile) { d.path = filename; d.deletedOnDisk = ![[NSFileManager defaultManager] fileExistsAtPath:filename]; }
        else d.untitledName = filename;
    }
    if (!d) return nil;
    if ([c.mainPane indexOfDocument:d] != NSNotFound && pane == c.subPane) {
        [c.mainPane removeDocument:d];
        [pane.documents addObject:d];
    } else if ([pane indexOfDocument:d] == NSNotFound) {
        [c.activePane removeDocument:d];
        [pane.documents addObject:d];
    }
    if (hasBackup) {
        NSData *data = [NSData dataWithContentsOfFile:backup];
        std::string utf8(static_cast<const char *>(data.bytes), data.length);
        [c withDocument:d perform:^(ScintillaView *v) {
            SCI(v, SCI_SETUNDOCOLLECTION, 0);
            SCI(v, SCI_CLEARALL);
            if (!utf8.empty()) SCI(v, SCI_APPENDTEXT, utf8.size(), reinterpret_cast<sptr_t>(utf8.data()));
            SCI(v, SCI_SETUNDOCOLLECTION, 1);
            SCI(v, SCI_EMPTYUNDOBUFFER);
            if (d.isUntitled || d.deletedOnDisk) SCI(v, SCI_SETSAVEPOINT);
        }];
        // upstream: a buffer restored from its backup stays dirty (Buffer::setDirty(true)) until it is saved, even
        // though Scintilla's savepoint is at the restored text; without this, closing it would not ask to save
        d.pendingSaveChange = YES;
        d.dirty = YES;
        _backupPaths[@(d.uid)] = backup;
    }
    NSString *um = s(@"tpUniMode");
    int cp = s(@"encoding").length ? s(@"encoding").intValue : -1;
    if (um.length) d.encoding = tpp::TextEncoding{static_cast<tpp::UniMode>(um.intValue), cp};
    else if (cp > 0) d.encoding = tpp::TextEncoding{tpp::UniMode::Utf8, cp};
    NSString *langId = s(@"tpLangId");
    if (!langId.length) {
        NSString *ln = s(@"lang");
        for (TPLanguage *l in [TPLanguageService shared].languages)
            if ([l.shortName caseInsensitiveCompare:ln] == NSOrderedSame || [l.langId caseInsensitiveCompare:ln] == NSOrderedSame) langId = l.langId;
    }
    if (langId.length) { d.languageId = langId; d.appliedLexerLanguage = nil; }
    if (s(@"tpEol").length) {
        d.eolMode = s(@"tpEol").intValue;
        [c withDocument:d perform:^(ScintillaView *v) { SCI(v, SCI_SETEOLMODE, d.eolMode); }];
    }
    d.userReadOnly = [s(@"userReadOnly") isEqualToString:@"yes"];
    d.pinned = [s(@"tabPinned") isEqualToString:@"yes"];
    d.tabColor = s(@"tabColourId").length ? s(@"tabColourId").integerValue : -1;
    d.monitoring = [s(@"tpMonitoring") isEqualToString:@"yes"];
    TPViewPosition pos;
    pos.firstVisibleLine = s(@"firstVisibleLine").longLongValue;
    pos.xOffset = s(@"xOffset").longLongValue;
    pos.anchor = s(@"startPos").longLongValue;
    pos.caret = s(@"endPos").longLongValue;
    pos.selMode = s(@"selMode").intValue;
    pos.valid = YES;
    [d setPosition:pos forView:pane.viewIndex];
    NSArray *marks = [f elementsForName:@"Mark"];
    if (marks.count) {
        [c withDocument:d perform:^(ScintillaView *v) {
            for (NSXMLElement *m in marks) SCI(v, SCI_MARKERADD, [[[m attributeForName:@"line"] stringValue] longLongValue], TPP_MARK_BOOKMARK);
        }];
    }
    return d;
}

@end
