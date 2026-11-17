// Textpad++ — View > Git Change Markers: a thin bar beside the text shows the lines added (green), changed (blue)
// and deleted (red arrow) since the last commit of a file in a Git repository; updated as you type. Uses the git
// of Homebrew or of the Command Line Tools / Xcode, never the /usr/bin/git stub that asks to install them.
// GPL-3.0-or-later.
#import "app/GitMarkers.h"
#import "app/Document.h"
#import "app/EditorPane.h"
#import "app/Preferences.h"
#import "app/Sci.h"
#include "core/Diff.h"
#include "core/Encoding.h"
#include <functional>

static const int kMarkGitAdded = 13, kMarkGitChanged = 14, kMarkGitDeleted = 15, kMarginGit = 4;
NSString *TPGitPathOverride = nil;   // tests

@interface TPGitHead : NSObject
@property (nonatomic, copy) NSString *text;   // nil: not in a repository, untracked, or no git
@property (nonatomic, strong) NSDate *fetched;
@property (nonatomic, strong) NSDate *fileDate;
@end
@implementation TPGitHead
@end

static NSMutableDictionary<NSString *, TPGitHead *> *g_heads;
static NSTimer *g_gitTimer;
static size_t g_lastHash;
static __weak TPDocument *g_lastDoc;

NSString *TPGitExecutable(void) {
    if (TPGitPathOverride) return TPGitPathOverride.length ? TPGitPathOverride : nil;
    static NSString *found;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        for (NSString *p in @[@"/opt/homebrew/bin/git", @"/usr/local/bin/git", @"/Library/Developer/CommandLineTools/usr/bin/git",
                              @"/Applications/Xcode.app/Contents/Developer/usr/bin/git"])
            if ([fm isExecutableFileAtPath:p]) { found = p; break; }
    });
    return found;
}

// the folder holding .git above `path`, or nil
NSString *TPGitRepositoryRoot(NSString *path) {
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *dir = path.stringByDeletingLastPathComponent; dir.length > 1; dir = dir.stringByDeletingLastPathComponent) {
        if ([fm fileExistsAtPath:[dir stringByAppendingPathComponent:@".git"]]) return dir;
        if ([dir isEqualToString:@"/"]) break;
    }
    return nil;
}

// the committed (HEAD) text of `path` as UTF-8, or nil
NSString *TPGitHeadText(NSString *path) {
    NSString *git = TPGitExecutable(), *root = TPGitRepositoryRoot(path);
    if (!git || !root) return nil;
    NSString *rel = [path substringFromIndex:MIN(path.length, root.length + 1)];
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:git];
    t.arguments = @[@"-C", root, @"show", [@"HEAD:" stringByAppendingString:rel]];
    t.environment = @{@"GIT_OPTIONAL_LOCKS": @"0", @"PATH": @"/usr/bin:/bin"};
    NSPipe *out = [NSPipe pipe];
    t.standardOutput = out;
    t.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![t launchAndReturnError:nil]) return nil;
    NSData *d = [out.fileHandleForReading readDataToEndOfFile];
    [t waitUntilExit];
    if (t.terminationStatus != 0) return nil;
    const std::string bytes(static_cast<const char *>(d.bytes), d.length);
    const tpp::DecodeResult r = tpp::detectAndDecode(bytes, true, true);
    return [[NSString alloc] initWithBytes:r.utf8.data() length:r.utf8.size() encoding:NSUTF8StringEncoding];
}

@implementation TPMainWindowController (GitMarkers)

- (void)gitDefineMarkers:(ScintillaView *)v {
    const BOOL dark = [TPChrome dark];
    if (SCI(v, SCI_GETMARGINS) < kMarginGit + 1) SCI(v, SCI_SETMARGINS, kMarginGit + 1);
    SCI(v, SCI_SETMARGINTYPEN, kMarginGit, SC_MARGIN_SYMBOL);
    SCI(v, SCI_SETMARGINMASKN, kMarginGit, (1 << kMarkGitAdded) | (1 << kMarkGitChanged) | (1 << kMarkGitDeleted));
    SCI(v, SCI_MARKERDEFINE, kMarkGitAdded, SC_MARK_FULLRECT);
    SCI(v, SCI_MARKERSETBACK, kMarkGitAdded, dark ? 0x5FB34E : 0x3FA64A);    // BGR
    SCI(v, SCI_MARKERDEFINE, kMarkGitChanged, SC_MARK_FULLRECT);
    SCI(v, SCI_MARKERSETBACK, kMarkGitChanged, dark ? 0xE09A4C : 0xD8822F);
    SCI(v, SCI_MARKERDEFINE, kMarkGitDeleted, SC_MARK_ARROW);
    SCI(v, SCI_MARKERSETBACK, kMarkGitDeleted, dark ? 0x5A5AF0 : 0x3030D8);
    SCI(v, SCI_MARKERSETFORE, kMarkGitDeleted, dark ? 0x5A5AF0 : 0x3030D8);
}

- (void)gitClear:(ScintillaView *)v {
    for (int m : {kMarkGitAdded, kMarkGitChanged, kMarkGitDeleted}) SCI(v, SCI_MARKERDELETEALL, m);
    if (SCI(v, SCI_GETMARGINS) > kMarginGit) SCI(v, SCI_SETMARGINWIDTHN, kMarginGit, 0);
}

- (void)gitStartWatching {
    if (g_gitTimer) return;
    __weak TPMainWindowController *ws = self;
    g_gitTimer = [NSTimer scheduledTimerWithTimeInterval:0.7 repeats:YES block:^(NSTimer *t) { [ws gitTick]; }];
}

- (void)gitTick {
    TPDocument *d = self.currentDocument;
    ScintillaView *v = self.editor;
    if (![TPPrefs b:@"pref.gitMarkers"] || !d.path || SCI(v, SCI_GETLENGTH) > 8 * 1024 * 1024) { if (v) [self gitClear:v]; g_lastDoc = nil; return; }
    const size_t h = std::hash<std::string>{}(sciGetText(v));
    TPGitHead *head = g_heads[d.path];
    NSDate *mod = [NSFileManager.defaultManager attributesOfItemAtPath:d.path error:nil].fileModificationDate;
    const BOOL stale = !head || -head.fetched.timeIntervalSinceNow > 20 || ![head.fileDate isEqual:mod];   // after a save or a commit
    if (!stale && h == g_lastHash && d == g_lastDoc) return;
    g_lastHash = h;
    g_lastDoc = d;
    if (stale) {
        if (!g_heads) g_heads = [NSMutableDictionary dictionary];
        TPGitHead *placeholder = head ?: [TPGitHead new];
        placeholder.fetched = [NSDate date];
        placeholder.fileDate = mod;
        g_heads[d.path] = placeholder;
        NSString *path = d.path;
        __weak TPMainWindowController *ws = self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSString *text = TPGitHeadText(path);
            dispatch_async(dispatch_get_main_queue(), ^{
                placeholder.text = text;
                g_lastHash = 0;   // apply on the next tick
                (void)ws;
            });
        });
        if (!head) return;
    }
    [self gitApplyHead:g_heads[d.path].text toEditor:v];
}

- (void)gitApplyHead:(NSString *)headText toEditor:(ScintillaView *)v {
    [self gitClear:v];
    if (!headText) return;
    [self gitDefineMarkers:v];
    SCI(v, SCI_SETMARGINWIDTHN, kMarginGit, 4);
    const sptr_t lines = SCI(v, SCI_GETLINECOUNT);
    for (const auto &h : tpp::diff::diffLines(headText.UTF8String ?: "", sciGetText(v))) {
        if (h.bCount == 0) { SCI(v, SCI_MARKERADD, MIN((sptr_t)h.bStart, lines - 1), kMarkGitDeleted); continue; }
        const int mark = h.aCount == 0 ? kMarkGitAdded : kMarkGitChanged;
        for (size_t k = 0; k < h.bCount; ++k) SCI(v, SCI_MARKERADD, h.bStart + k, mark);
    }
}

- (void)gitJump:(BOOL)forward {
    ScintillaView *v = self.editor;
    const int mask = (1 << kMarkGitAdded) | (1 << kMarkGitChanged) | (1 << kMarkGitDeleted);
    const sptr_t cur = SCI(v, SCI_LINEFROMPOSITION, SCI(v, SCI_GETCURRENTPOS)), lines = SCI(v, SCI_GETLINECOUNT);
    // skip the rest of the block the caret is in
    sptr_t l = cur;
    while (l >= 0 && l < lines && (SCI(v, SCI_MARKERGET, l) & mask)) l += forward ? 1 : -1;
    sptr_t found = forward ? SCI(v, SCI_MARKERNEXT, MAX((sptr_t)0, l), mask) : SCI(v, SCI_MARKERPREVIOUS, MAX((sptr_t)0, l), mask);
    if (found < 0) found = forward ? SCI(v, SCI_MARKERNEXT, 0, mask) : SCI(v, SCI_MARKERPREVIOUS, lines - 1, mask);   // wrap around
    if (!forward) while (found > 0 && (SCI(v, SCI_MARKERGET, found - 1) & mask)) --found;   // the block's first line
    if (found < 0) { NSBeep(); return; }
    SCI(v, SCI_GOTOLINE, found);
    SCI(v, SCI_SCROLLCARET);
}

@end
