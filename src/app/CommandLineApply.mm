// Textpad++ — applying command-line parameters (upstream Notepad_plus::loadCommandlineParams / showQuote).
// GPL-3.0-or-later.
#import "app/Localization.h"
#import "app/MainWindowController.h"
#import "app/CommandLine.h"
#import "app/Document.h"
#import "app/EditorPane.h"
#import "app/LanguageService.h"
#import "app/UserDefinedLanguages.h"
#import "app/Preferences.h"
#import "app/Session.h"
#import "panels/Panels.h"
#import <objc/runtime.h>

static char kForceRO, kSavingForbidden, kMonitorAll, kTitleAdd, kTabBarOff, kGhostTimer;

@implementation TPMainWindowController (CommandLine)

- (BOOL)forceReadOnly { return [objc_getAssociatedObject(self, &kForceRO) boolValue]; }
- (void)setForceReadOnly:(BOOL)v { objc_setAssociatedObject(self, &kForceRO, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)savingForbidden { return [objc_getAssociatedObject(self, &kSavingForbidden) boolValue]; }
- (void)setSavingForbidden:(BOOL)v { objc_setAssociatedObject(self, &kSavingForbidden, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (BOOL)monitorAllFiles { return [objc_getAssociatedObject(self, &kMonitorAll) boolValue]; }
- (void)setMonitorAllFiles:(BOOL)v { objc_setAssociatedObject(self, &kMonitorAll, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (NSString *)titleAddition { return objc_getAssociatedObject(self, &kTitleAdd); }
- (void)setTitleAddition:(NSString *)v { objc_setAssociatedObject(self, &kTitleAdd, v, OBJC_ASSOCIATION_COPY_NONATOMIC); [self refreshUI]; }
- (BOOL)tabBarForcedHidden { return [objc_getAssociatedObject(self, &kTabBarOff) boolValue]; }
- (void)setTabBarForcedHidden:(BOOL)v { objc_setAssociatedObject(self, &kTabBarOff, @(v), OBJC_ASSOCIATION_RETAIN_NONATOMIC); [self applyChromeVisibility]; }

// Every newly opened file (-fullReadOnly*, -monitoringMode)
- (void)applyOpenPolicyToDocument:(TPDocument *)d {
    if (self.forceReadOnly) d.userReadOnly = YES;
    if (self.monitorAllFiles && d.path) d.monitoring = YES;
    for (TPEditorPane *p in @[self.mainPane, self.subPane])
        if (p.currentDocument == d) SCI(p.editor, SCI_SETREADONLY, d.userReadOnly || d.monitoring);
}

- (void)applyDocumentOptions:(TPCommandLine *)cl toDocument:(TPDocument *)d {
    TPEditorPane *pane = [self.mainPane indexOfDocument:d] != NSNotFound ? self.mainPane : self.subPane;
    [self activateDocument:d inPane:pane];
    ScintillaView *v = pane.editor;
    if (cl.udl.length) {
        if ([[TPUserLanguages shared] languageNamed:cl.udl]) d.languageId = [@"udl:" stringByAppendingString:cl.udl];
    } else if (cl.language.length) {
        TPLanguage *lang = nil;
        for (TPLanguage *l in [TPLanguageService shared].languages)
            if ([l.langId caseInsensitiveCompare:cl.language] == NSOrderedSame || [l.shortName caseInsensitiveCompare:cl.language] == NSOrderedSame) { lang = l; break; }
        if (lang) d.languageId = lang.langId;
    }
    [[TPLanguageService shared] applyLanguageOfDocument:d toView:v];
    if (cl.readOnly) d.userReadOnly = YES;
    if (cl.monitor && d.path) d.monitoring = YES;
    SCI(v, SCI_SETREADONLY, d.userReadOnly || d.monitoring);
    // upstream: -n / -c (1-based) or -p (0-based byte position)
    if (cl.position >= 0) {
        SCI(v, SCI_GOTOPOS, MIN(cl.position, SCI(v, SCI_GETLENGTH)));
    } else if (cl.line >= 0 || cl.column >= 0) {
        sptr_t line = MAX(0, (cl.line > 0 ? cl.line : 1) - 1);
        line = MIN(line, SCI(v, SCI_GETLINECOUNT) - 1);
        sptr_t pos = SCI(v, SCI_POSITIONFROMLINE, line);
        if (cl.column > 0) pos = SCI(v, SCI_FINDCOLUMN, line, cl.column - 1);
        SCI(v, SCI_ENSUREVISIBLE, line);
        SCI(v, SCI_GOTOPOS, pos);
        SCI(v, SCI_SETFIRSTVISIBLELINE, MAX(0, SCI(v, SCI_VISIBLEFROMDOCLINE, line) - SCI(v, SCI_LINESONSCREEN) / 2));
    }
    [self refreshUI];
}

- (NSArray<TPDocument *> *)applyCommandLine:(TPCommandLine *)cl {
    if (cl.fullReadOnly || cl.fullReadOnlySavingForbidden) self.forceReadOnly = YES;
    if (cl.fullReadOnlySavingForbidden) self.savingForbidden = YES;
    if (cl.monitoringMode) self.monitorAllFiles = YES;
    if (cl.titleAdd.length) self.titleAddition = cl.titleAdd;
    if (cl.noTabBar) self.tabBarForcedHidden = YES;
    if (cl.alwaysOnTop) self.window.level = NSFloatingWindowLevel;
    if (cl.localization.length) {   // -L: for this run only; a language file name (-Lfrench) or a common code (-Lfr)
        static NSDictionary *codes = @{@"fr": @"french", @"de": @"german", @"es": @"spanish", @"it": @"italian", @"pt": @"portuguese",
            @"pt-br": @"brazilian_portuguese", @"ru": @"russian", @"zh-cn": @"chineseSimplified", @"zh-tw": @"taiwaneseMandarin",
            @"ja": @"japanese", @"ko": @"korean", @"hi": @"hindi", @"ar": @"arabic", @"tr": @"turkish", @"nl": @"dutch", @"pl": @"polish",
            @"sv": @"swedish", @"uk": @"ukrainian", @"cs": @"czech", @"el": @"greek", @"he": @"hebrew", @"en": @""};
        NSString *want = codes[cl.localization.lowercaseString] ?: cl.localization;
        for (NSString *f in [TPLocalization shared].languageFiles)
            if ([f.lastPathComponent.stringByDeletingPathExtension caseInsensitiveCompare:want] == NSOrderedSame) { [[TPLocalization shared] applyLanguageFile:f]; break; }
        if (!want.length) [[TPLocalization shared] applyLanguageFile:@""];
    }
    if (cl.hasX || cl.hasY) {
        // upstream -x / -y: top-left corner in screen coordinates (y grows downwards)
        NSRect screen = (self.window.screen ?: NSScreen.mainScreen).frame;
        NSRect f = self.window.frame;
        CGFloat left = cl.hasX ? screen.origin.x + cl.x : f.origin.x;
        CGFloat top = cl.hasY ? NSMaxY(screen) - cl.y : NSMaxY(f);
        [self.window setFrameTopLeftPoint:NSMakePoint(left, top)];
    }
    NSMutableArray<TPDocument *> *opened = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *f in cl.files) {
        BOOL isDir = NO;
        BOOL exists = [fm fileExistsAtPath:f isDirectory:&isDir];
        if (cl.openSession && exists && !isDir) { [[TPSession shared] loadSessionFromPath:f controller:self]; continue; }
        if (exists && isDir && cl.openFoldersAsWorkspace) {   // -openFoldersAsWorkspace
            [self.folderAsWorkspacePanel addRootFolder:f];
            [self.docks showPanel:@"faw"];
            continue;
        }
        if (exists && isDir) {
            // folder: its files (recursively with -r)
            NSDirectoryEnumerator *en = [fm enumeratorAtURL:[NSURL fileURLWithPath:f] includingPropertiesForKeys:@[NSURLIsRegularFileKey]
                                                    options:NSDirectoryEnumerationSkipsHiddenFiles | (cl.recursive ? 0 : NSDirectoryEnumerationSkipsSubdirectoryDescendants)
                                               errorHandler:nil];
            NSMutableArray *paths = [NSMutableArray array];
            for (NSURL *u in en) { NSNumber *reg = nil; [u getResourceValue:&reg forKey:NSURLIsRegularFileKey error:nil]; if (reg.boolValue) [paths addObject:u.path]; }
            [paths sortUsingSelector:@selector(localizedStandardCompare:)];
            for (NSString *p in paths) if (TPDocument *d = [self openFile:p]) [opened addObject:d];
            continue;
        }
        if (TPDocument *d = [self openFile:f]) [opened addObject:d];
    }
    if (cl.hasDocumentOptions) for (TPDocument *d in opened) [self applyDocumentOptions:cl toDocument:d];
    // ghost typing (upstream showQuote): a new document, the chosen language, typed at -qSpeed
    NSString *ghost = cl.ghostText;
    if (cl.ghostFile.length) ghost = [NSString stringWithContentsOfFile:cl.ghostFile.stringByExpandingTildeInPath encoding:NSUTF8StringEncoding error:nil];
    if (cl.ghostName.length && !ghost.length) ghost = TPQuoteNamed(cl.ghostName);   // -qn="Quoter" (upstream getQuoteIndexFrom)
    if (ghost.length) {
        TPDocument *d = [self newDocument];
        if (cl.language.length || cl.udl.length) {
            TPCommandLine *langOnly = [TPCommandLine new];
            langOnly.line = langOnly.column = langOnly.position = -1;
            langOnly.language = cl.language; langOnly.udl = cl.udl;
            [self applyDocumentOptions:langOnly toDocument:d];
        }
        [self ghostType:ghost speed:cl.ghostSpeed completion:nil];
    }
    return opened;
}

// -qn: upstream's quotes attributed to named people; "random" picks one
namespace { struct Quote { const char *quoter; int speed; const char *text; }; }
static const Quote kQuotes[] = {
#include "QuoteTable.inc"
};
NSString *TPQuoteNamed(NSString *name) {
    const size_t n = sizeof(kQuotes) / sizeof(kQuotes[0]);
    if ([name caseInsensitiveCompare:@"random"] == NSOrderedSame) {
        const Quote &q = kQuotes[arc4random_uniform((uint32_t)n)];
        return [NSString stringWithFormat:@"%s\n- %s", q.text, q.quoter];
    }
    for (size_t i = 0; i < n; ++i)
        if ([@(kQuotes[i].quoter) caseInsensitiveCompare:name] == NSOrderedSame) return [NSString stringWithFormat:@"%s\n- %s", kQuotes[i].text, kQuotes[i].quoter];
    return nil;
}

// upstream threadTextPlayer: random per-character delays (longer after a space or '.'), halved for "fast",
// none for "fastest"; typing stops if another document is activated.
- (void)ghostType:(NSString *)text speed:(NSInteger)speed completion:(void (^)(void))done {
    __block NSUInteger i = 0;
    TPDocument *target = self.currentDocument;
    const double x = speed == 1 ? 1 : 2, y = speed == 3 ? 0 : 1;   // upstream QuoteParams: slow 1/1, rapid 2/1, speedOfLight 1/0
    __weak TPMainWindowController *ws = self;
    __block void (^step)(void);
    void (^typeOne)(void) = ^{
        TPMainWindowController *c = ws;
        if (!c || c.currentDocument != target || i >= text.length) { objc_setAssociatedObject(c, &kGhostTimer, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); if (done) done(); return; }
        NSRange r = [text rangeOfComposedCharacterSequenceAtIndex:i];
        NSString *ch = [text substringWithRange:r];
        i = NSMaxRange(r);
        const char *u = ch.UTF8String;
        SCI(c.editor, SCI_APPENDTEXT, strlen(u), reinterpret_cast<sptr_t>(u));
        SCI(c.editor, SCI_GOTOPOS, SCI(c.editor, SCI_GETLENGTH));
        step();
    };
    step = ^{
        static const int interval[] = {30, 30, 30, 30, 200}, pause[] = {200, 400, 600};
        int ran = static_cast<int>(arc4random_uniform(200));
        unichar prev = i < text.length ? [text characterAtIndex:i] : 0;
        double ms = (ran + ((prev == ' ' || prev == '.') ? pause[ran % 3] : interval[ran % 5])) / x * y;
        // run-loop timer (also fires in nested run loops, e.g. while a menu is open)
        NSTimer *t = [NSTimer timerWithTimeInterval:MAX(0.0, ms / 1000.0) repeats:NO block:^(NSTimer *timer) { typeOne(); }];
        [[NSRunLoop currentRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
    };
    objc_setAssociatedObject(self, &kGhostTimer, step, OBJC_ASSOCIATION_COPY_NONATOMIC);
    step();
}

@end
