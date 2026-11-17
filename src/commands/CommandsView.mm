// Textpad++ — View menu commands (upstream NppCommands.cpp IDM_VIEW_*). GPL-3.0-or-later.
#import "app/MainWindowController.h"
#import "app/HideLines.h"
#import <objc/runtime.h>
#import "app/LanguageService.h"
#import "app/Preferences.h"
#include <objc/runtime.h>

using namespace npp;

static BOOL g_syncV = NO, g_syncH = NO, g_zoomSync = NO, g_postIt = NO, g_distractionFree = NO;
static BOOL g_syncing = NO;

@implementation TPMainWindowController (ViewCommands)

- (BOOL)viewFlag:(NSString *)key { return [[NSUserDefaults standardUserDefaults] boolForKey:key]; }
- (void)setViewFlag:(NSString *)key value:(BOOL)v { [[NSUserDefaults standardUserDefaults] setBool:v forKey:key]; }

- (void)applyViewFlagsToEditor:(ScintillaView *)v {
    BOOL tabSpace = [self viewFlag:@"ShowWhitespace"], eol = [self viewFlag:@"ShowEOL"];
    SCI(v, SCI_SETVIEWWS, tabSpace ? SCWS_VISIBLEALWAYS : SCWS_INVISIBLE);
    SCI(v, SCI_SETVIEWEOL, eol);
    SCI(v, SCI_SETINDENTATIONGUIDES, [[NSUserDefaults standardUserDefaults] objectForKey:@"ShowIndentGuide"] && ![self viewFlag:@"ShowIndentGuide"] ? SC_IV_NONE : SC_IV_LOOKBOTH);
    SCI(v, SCI_SETWRAPMODE, [self viewFlag:@"WordWrap"] ? SC_WRAP_WORD : SC_WRAP_NONE);
    SCI(v, SCI_SETWRAPVISUALFLAGS, [self viewFlag:@"ShowWrapSymbol"] ? SC_WRAPVISUALFLAG_END : SC_WRAPVISUALFLAG_NONE);
    // Non-printing / control characters: Scintilla representations (upstream 8.6+ uses the same mechanism)
    BOOL npc = [self viewFlag:@"ShowNPC"], cc = [self viewFlag:@"ShowCCUniEOL"];
    BOOL codepoint = [TPPrefs b:@"pref.npcCodepoint"], npcColor = [TPPrefs b:@"pref.npcCustomColor"];
    TPStyleSpec *ws = [[TPLanguageService shared] globalStyle:@"White space symbol"];
    int wsColor = rgbToSci(ws && ws.fg >= 0 ? ws.fg : 0xFFB56A);
    auto cpLabel = [](const char *utf8) -> std::string {
        std::u32string u;
        NSString *s = @(utf8);
        char32_t c = [s characterAtIndex:0];
        char buf[16];
        snprintf(buf, sizeof(buf), "U+%04X", (unsigned)c);
        (void)u;
        return buf;
    };
    auto setRep = [&](const char *chars, const char *abbrev, BOOL on, BOOL applyAppearance) {
        if (!on) { SCI(v, SCI_CLEARREPRESENTATION, reinterpret_cast<uptr_t>(chars)); return; }
        std::string text = (codepoint && applyAppearance) ? cpLabel(chars) : std::string(abbrev);
        SCI(v, SCI_SETREPRESENTATION, reinterpret_cast<uptr_t>(chars), reinterpret_cast<sptr_t>(text.c_str()));
        if (npcColor && applyAppearance) {
            SCI(v, SCI_SETREPRESENTATIONAPPEARANCE, reinterpret_cast<uptr_t>(chars), SC_REPRESENTATION_BLOB | SC_REPRESENTATION_COLOUR);
            SCI(v, SCI_SETREPRESENTATIONCOLOUR, reinterpret_cast<uptr_t>(chars), wsColor | 0xFF000000);
        }
    };
    // EOL appearance (Preferences > Editing 2 > EOL (CRLF))
    BOOL plain = [TPPrefs b:@"pref.crlfPlain"], eolColor = [TPPrefs b:@"pref.crlfCustomColor"];
    const char *eols[][2] = {{"\r\n", "CRLF"}, {"\r", "CR"}, {"\n", "LF"}};
    for (auto &e : eols) {
        if (!plain && !eolColor) { SCI(v, SCI_CLEARREPRESENTATION, reinterpret_cast<uptr_t>(e[0])); continue; }
        SCI(v, SCI_SETREPRESENTATION, reinterpret_cast<uptr_t>(e[0]), reinterpret_cast<sptr_t>(e[1]));
        SCI(v, SCI_SETREPRESENTATIONAPPEARANCE, reinterpret_cast<uptr_t>(e[0]), (plain ? SC_REPRESENTATION_PLAIN : SC_REPRESENTATION_BLOB) | (eolColor ? SC_REPRESENTATION_COLOUR : 0));
        if (eolColor) SCI(v, SCI_SETREPRESENTATIONCOLOUR, reinterpret_cast<uptr_t>(e[0]), wsColor | 0xFF000000);
    }
    // C0 / C1 controls follow the NPC appearance only when "Apply Appearance settings to C0, C1 & Unicode EOL" is on
    BOOL ccApply = [TPPrefs b:@"pref.npcIncludeCC"];
    for (int c = 1; c < 0x20; ++c) {
        if (c == '\t' || c == '\n' || c == '\r') continue;
        char s[2] = {static_cast<char>(c), 0};
        if (ccApply && (codepoint || npcColor)) {
            char lbl[8]; snprintf(lbl, sizeof(lbl), "U+%04X", c);
            SCI(v, SCI_SETREPRESENTATION, reinterpret_cast<uptr_t>(s), reinterpret_cast<sptr_t>(codepoint ? lbl : ""));
            if (!codepoint) SCI(v, SCI_CLEARREPRESENTATION, reinterpret_cast<uptr_t>(s));
            else if (npcColor) { SCI(v, SCI_SETREPRESENTATIONAPPEARANCE, reinterpret_cast<uptr_t>(s), SC_REPRESENTATION_BLOB | SC_REPRESENTATION_COLOUR); SCI(v, SCI_SETREPRESENTATIONCOLOUR, reinterpret_cast<uptr_t>(s), wsColor | 0xFF000000); }
        } else {
            SCI(v, SCI_CLEARREPRESENTATION, reinterpret_cast<uptr_t>(s));
        }
    }
    const char *npcChars[][2] = {{"\xC2\xA0", "NBSP"}, {"\xE2\x80\x8B", "ZWSP"}, {"\xE2\x80\x8C", "ZWNJ"}, {"\xE2\x80\x8D", "ZWJ"},
                                 {"\xE2\x80\x8E", "LRM"}, {"\xE2\x80\x8F", "RLM"}, {"\xEF\xBB\xBF", "BOM"}, {"\xE2\x80\xAF", "NNBSP"}};
    for (auto &p : npcChars) setRep(p[0], p[1], npc, YES);
    const char *uniEol[][2] = {{"\xC2\x85", "NEL"}, {"\xE2\x80\xA8", "LS"}, {"\xE2\x80\xA9", "PS"}};
    for (auto &p : uniEol) setRep(p[0], p[1], cc, ccApply);
}

- (void)applyViewFlagsPublic { [self applyViewFlags]; }
- (BOOL)chromeForcedHidden { return g_postIt || g_distractionFree; }
- (BOOL)postItActive { return g_postIt; }

// Distraction Free side padding (upstream NppGUI::getDistractionFreePadding): view width / N, N = 3..9 (default 4)
- (int)distractionFreePaddingForWidth:(CGFloat)w {
    NSInteger div = [TPPrefs i:@"pref.distractionFreeWidth"];
    if (div <= 2) div = 4;
    int pad = static_cast<int>(w / div);
    return pad > 0 ? pad : static_cast<int>(w / 4);
}

- (void)applyDistractionFreePadding {
    for (TPEditorPane *p in @[self.mainPane, self.subPane]) {
        if (g_distractionFree) {
            int pad = [self distractionFreePaddingForWidth:NSWidth(p.editor.bounds)];
            SCI(p.editor, SCI_SETMARGINLEFT, 0, pad);
            SCI(p.editor, SCI_SETMARGINRIGHT, 0, pad);
        } else {
            [self applyEditorPrefs:p.editor];
        }
    }
}

// A second Textpad++ process with the given arguments (macOS allows several instances of one app)
- (void)launchNewInstanceWithArguments:(NSArray<NSString *> *)args {
    self.lastNewInstanceArguments = args;
    if (self.selfTestMode) return;
    NSWorkspaceOpenConfiguration *cfg = [NSWorkspaceOpenConfiguration configuration];
    cfg.createsNewApplicationInstance = YES;
    cfg.arguments = args;
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:[NSBundle mainBundle].bundleURL configuration:cfg completionHandler:nil];
}

static char kLastNewInstanceArgs;
- (NSArray<NSString *> *)lastNewInstanceArguments { return objc_getAssociatedObject(self, &kLastNewInstanceArgs); }
- (void)setLastNewInstanceArguments:(NSArray<NSString *> *)a { objc_setAssociatedObject(self, &kLastNewInstanceArgs, a, OBJC_ASSOCIATION_COPY_NONATOMIC); }

// Post-it (upstream removes the caption and all bars): the macOS title bar is hidden and the window can be
// dragged by its background; the global menu bar stays (macOS has no per-window menu bar).
- (void)applyPostItWindowStyle {
    NSWindow *w = self.window;
    BOOL on = g_postIt;
    if (on) w.styleMask |= NSWindowStyleMaskFullSizeContentView;
    else w.styleMask &= ~NSWindowStyleMaskFullSizeContentView;
    w.titlebarAppearsTransparent = on;
    w.titleVisibility = on ? NSWindowTitleHidden : NSWindowTitleVisible;
    w.movableByWindowBackground = on;
    for (NSWindowButton b : {NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton})
        [w standardWindowButton:b].hidden = on;
    [self.window.contentView setNeedsLayout:YES];
    [self.window.contentView layoutSubtreeIfNeeded];
}
- (BOOL)distractionFreeActive { return g_distractionFree; }

- (void)applyViewFlags {
    for (TPEditorPane *p in @[self.mainPane, self.subPane]) [self applyViewFlagsToEditor:p.editor];
    [self refreshUI];
}

- (void)registerViewCommands:(TPCommandRegistry *)reg {
    __weak TPMainWindowController *ws = self;
    TPCommandPredicate hasDoc = ^BOOL(int c) { return ws.currentDocument != nil; };
    [self applyViewFlags];

    [reg registerCommand:IDM_VIEW_ALWAYSONTOP handler:^(int c) {
        ws.window.level = ws.window.level == NSFloatingWindowLevel ? NSNormalWindowLevel : NSFloatingWindowLevel;
    } enabled:nil checked:^BOOL(int c) { return ws.window.level == NSFloatingWindowLevel; }];
    [reg registerCommand:IDM_VIEW_FULLSCREENTOGGLE handler:^(int c) { [ws.window toggleFullScreen:nil]; } enabled:nil
                 checked:^BOOL(int c) { return (ws.window.styleMask & NSWindowStyleMaskFullScreen) != 0; }];
    // View > Move/Clone Current Document > Move to / Open in New Instance (upstream: -multiInst -nosession <file>)
    [reg registerCommand:IDM_VIEW_LOAD_IN_NEW_INSTANCE handler:^(int c) {
        [ws launchNewInstanceWithArguments:@[@"-multiInst", @"-nosession", ws.currentDocument.path]];
    } enabled:^BOOL(int c) { return ws.currentDocument.path != nil; } checked:nil];
    [reg registerCommand:IDM_VIEW_GOTO_NEW_INSTANCE handler:^(int c) {
        TPDocument *d = ws.currentDocument;
        if (d.dirty && [ws saveDocument:d] != TPSaveOK) return;
        [ws launchNewInstanceWithArguments:@[@"-multiInst", @"-nosession", d.path]];
        [ws closeDocument:d inPane:ws.activePane];
    } enabled:^BOOL(int c) { return ws.currentDocument.path != nil; } checked:nil];
    [reg registerCommand:IDM_VIEW_POSTIT handler:^(int c) {
        g_postIt = !g_postIt;
        [ws applyChromeVisibility];
        [ws applyPostItWindowStyle];
    } enabled:nil checked:^BOOL(int c) { return g_postIt; }];
    [reg registerCommand:IDM_VIEW_DISTRACTIONFREE handler:^(int c) {
        g_distractionFree = !g_distractionFree;
        [ws applyChromeVisibility];
        BOOL fs = (ws.window.styleMask & NSWindowStyleMaskFullScreen) != 0;
        if (fs != g_distractionFree && !ws.selfTestMode) [ws.window toggleFullScreen:nil];   // the self-test must not switch Spaces
        static id resizeObserver;
        if (g_distractionFree && !resizeObserver)
            resizeObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidResizeNotification object:ws.window queue:nil
                                                                           usingBlock:^(NSNotification *n) { [ws applyDistractionFreePadding]; }];
        else if (!g_distractionFree && resizeObserver) { [[NSNotificationCenter defaultCenter] removeObserver:resizeObserver]; resizeObserver = nil; }
        [ws applyDistractionFreePadding];
    } enabled:nil checked:^BOOL(int c) { return g_distractionFree; }];

    struct { int cmd; NSString *bundle; } browsers[] = {
        {IDM_VIEW_IN_FIREFOX, @"org.mozilla.firefox"}, {IDM_VIEW_IN_CHROME, @"com.google.Chrome"},
        {IDM_VIEW_IN_EDGE, @"com.microsoft.edgemac"}, {IDM_VIEW_IN_IE, @"com.apple.Safari"}};
    for (auto &b : browsers) {
        NSString *bid = b.bundle;
        [reg registerCommand:b.cmd handler:^(int c) {
            NSURL *app = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:bid];
            [[NSWorkspace sharedWorkspace] openURLs:@[[NSURL fileURLWithPath:ws.currentDocument.path]] withApplicationAtURL:app
                                      configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];
        } enabled:^BOOL(int c) {
            return ws.currentDocument.path && [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:bid] != nil;
        } checked:nil];
    }

    // Show Symbol
    struct { int cmd; NSString *key; } flags[] = {
        {IDM_VIEW_TAB_SPACE, @"ShowWhitespace"}, {IDM_VIEW_EOL, @"ShowEOL"}, {IDM_VIEW_NPC, @"ShowNPC"},
        {IDM_VIEW_NPC_CCUNIEOL, @"ShowCCUniEOL"}, {IDM_VIEW_WRAP_SYMBOL, @"ShowWrapSymbol"}, {IDM_VIEW_WRAP, @"WordWrap"}};
    for (auto &f : flags) {
        NSString *key = f.key;
        [reg registerCommand:f.cmd handler:^(int c) { [ws setViewFlag:key value:![ws viewFlag:key]]; [ws applyViewFlags]; }
                     enabled:nil checked:^BOOL(int c) { return [ws viewFlag:key]; }];
    }
    [reg registerCommand:IDM_VIEW_ALL_CHARACTERS handler:^(int c) {
        BOOL all = [ws viewFlag:@"ShowWhitespace"] && [ws viewFlag:@"ShowEOL"] && [ws viewFlag:@"ShowNPC"] && [ws viewFlag:@"ShowCCUniEOL"];
        for (NSString *k in @[@"ShowWhitespace", @"ShowEOL", @"ShowNPC", @"ShowCCUniEOL"]) [ws setViewFlag:k value:!all];
        [ws applyViewFlags];
    } enabled:nil checked:^BOOL(int c) { return [ws viewFlag:@"ShowWhitespace"] && [ws viewFlag:@"ShowEOL"] && [ws viewFlag:@"ShowNPC"] && [ws viewFlag:@"ShowCCUniEOL"]; }];
    [reg registerCommand:IDM_VIEW_INDENT_GUIDE handler:^(int c) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        BOOL shown = ![ud objectForKey:@"ShowIndentGuide"] || [ud boolForKey:@"ShowIndentGuide"];
        [ud setBool:!shown forKey:@"ShowIndentGuide"];
        [ws applyViewFlags];
    } enabled:nil checked:^BOOL(int c) { NSUserDefaults *ud = [NSUserDefaults standardUserDefaults]; return ![ud objectForKey:@"ShowIndentGuide"] || [ud boolForKey:@"ShowIndentGuide"]; }];

    // Zoom
    [reg registerCommand:IDM_VIEW_ZOOMIN handler:^(int c) { [ws zoom:1]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_VIEW_ZOOMOUT handler:^(int c) { [ws zoom:-1]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_VIEW_ZOOMRESTORE handler:^(int c) { [ws zoom:0]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_VIEW_ZOOM_SYNC handler:^(int c) { g_zoomSync = !g_zoomSync; } enabled:nil checked:^BOOL(int c) { return g_zoomSync; }];

    // Move / clone
    [reg registerCommand:IDM_VIEW_GOTO_ANOTHER_VIEW handler:^(int c) { [ws moveOrCloneToOtherView:NO]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_VIEW_CLONE_TO_ANOTHER_VIEW handler:^(int c) { [ws moveOrCloneToOtherView:YES]; } enabled:^BOOL(int c) {
        return ws.currentDocument && [ws.otherPane indexOfDocument:ws.currentDocument] == NSNotFound;
    } checked:nil];

    // Tabs
    int tabs[9] = {IDM_VIEW_TAB1, IDM_VIEW_TAB2, IDM_VIEW_TAB3, IDM_VIEW_TAB4, IDM_VIEW_TAB5, IDM_VIEW_TAB6, IDM_VIEW_TAB7, IDM_VIEW_TAB8, IDM_VIEW_TAB9};
    for (int i = 0; i < 9; ++i) {
        NSInteger idx = i;
        [reg registerCommand:tabs[i] handler:^(int c) { [ws selectTabIndex:idx]; } enabled:^BOOL(int c) { return (NSInteger)ws.activePane.documents.count > idx; } checked:nil];
    }
    [reg registerCommand:IDM_VIEW_TAB_START handler:^(int c) { [ws selectTabIndex:0]; }];
    [reg registerCommand:IDM_VIEW_TAB_END handler:^(int c) { [ws selectTabIndex:(NSInteger)ws.activePane.documents.count - 1]; }];
    [reg registerCommand:IDM_VIEW_TAB_NEXT handler:^(int c) { [ws cycleTab:1]; }];
    [reg registerCommand:IDM_VIEW_TAB_PREV handler:^(int c) { [ws cycleTab:-1]; }];
    [reg registerCommand:IDC_NEXT_DOC handler:^(int c) { [ws cycleTab:1]; }];
    [reg registerCommand:IDC_PREV_DOC handler:^(int c) { [ws cycleTab:-1]; }];
    [reg registerCommand:IDM_VIEW_GOTO_START handler:^(int c) { [ws moveTabTo:0]; }];
    [reg registerCommand:IDM_VIEW_GOTO_END handler:^(int c) { [ws moveTabTo:(NSInteger)ws.activePane.documents.count - 1]; }];
    [reg registerCommand:IDM_VIEW_TAB_MOVEFORWARD handler:^(int c) { [ws moveTabBy:1]; }];
    [reg registerCommand:IDM_VIEW_TAB_MOVEBACKWARD handler:^(int c) { [ws moveTabBy:-1]; }];
    int colors[6] = {IDM_VIEW_TAB_COLOUR_1, IDM_VIEW_TAB_COLOUR_2, IDM_VIEW_TAB_COLOUR_3, IDM_VIEW_TAB_COLOUR_4, IDM_VIEW_TAB_COLOUR_5, IDM_VIEW_TAB_COLOUR_NONE};
    for (int i = 0; i < 6; ++i) {
        NSInteger col = i == 5 ? -1 : i;
        [reg registerCommand:colors[i] handler:^(int c) { ws.currentDocument.tabColor = col; [ws refreshUI]; } enabled:hasDoc
                     checked:^BOOL(int c) { return col >= 0 && ws.currentDocument.tabColor == col; }];
    }

    [reg registerCommand:IDM_VIEW_SWITCHTO_OTHER_VIEW handler:^(int c) { [ws activatePane:ws.otherPane]; }
                 enabled:^BOOL(int c) { return !ws.otherPane.hidden && ws.otherPane.currentDocument != nil; } checked:nil];
    [reg registerCommand:IDM_VIEW_HIDELINES handler:^(int c) { [ws hideSelectedLines]; } enabled:hasDoc checked:nil];

    // Folding
    [reg registerCommand:IDM_VIEW_FOLDALL handler:^(int c) { SCI(ws.editor, SCI_FOLDALL, SC_FOLDACTION_CONTRACT | SC_FOLDACTION_CONTRACT_EVERY_LEVEL); } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_VIEW_UNFOLDALL handler:^(int c) { SCI(ws.editor, SCI_FOLDALL, SC_FOLDACTION_EXPAND | SC_FOLDACTION_CONTRACT_EVERY_LEVEL); } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_VIEW_FOLD_CURRENT handler:^(int c) { [ws foldCurrent:YES]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_VIEW_UNFOLD_CURRENT handler:^(int c) { [ws foldCurrent:NO]; } enabled:hasDoc checked:nil];
    int foldL[8] = {IDM_VIEW_FOLD_1, IDM_VIEW_FOLD_2, IDM_VIEW_FOLD_3, IDM_VIEW_FOLD_4, IDM_VIEW_FOLD_5, IDM_VIEW_FOLD_6, IDM_VIEW_FOLD_7, IDM_VIEW_FOLD_8};
    int unfoldL[8] = {IDM_VIEW_UNFOLD_1, IDM_VIEW_UNFOLD_2, IDM_VIEW_UNFOLD_3, IDM_VIEW_UNFOLD_4, IDM_VIEW_UNFOLD_5, IDM_VIEW_UNFOLD_6, IDM_VIEW_UNFOLD_7, IDM_VIEW_UNFOLD_8};
    for (int i = 0; i < 8; ++i) {
        int level = i;
        [reg registerCommand:foldL[i] handler:^(int c) { [ws foldLevel:level fold:YES]; } enabled:hasDoc checked:nil];
        [reg registerCommand:unfoldL[i] handler:^(int c) { [ws foldLevel:level fold:NO]; } enabled:hasDoc checked:nil];
    }

    [reg registerCommand:IDM_VIEW_SUMMARY handler:^(int c) { [ws showSummary]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_VIEW_SYNSCROLLV handler:^(int c) { g_syncV = !g_syncV; [ws.toolbar refreshStates]; }
                 enabled:^BOOL(int c) { return !ws.subPane.hidden; } checked:^BOOL(int c) { return g_syncV; }];
    [reg registerCommand:IDM_VIEW_SYNSCROLLH handler:^(int c) { g_syncH = !g_syncH; [ws.toolbar refreshStates]; }
                 enabled:^BOOL(int c) { return !ws.subPane.hidden; } checked:^BOOL(int c) { return g_syncH; }];
    [reg registerCommand:IDM_VIEW_MONITORING handler:^(int c) {
        TPDocument *d = ws.currentDocument;
        d.monitoring = !d.monitoring;
        SCI(ws.editor, SCI_SETREADONLY, d.monitoring || d.userReadOnly);
        if (d.monitoring) { tpp::TextEncoding e = d.encoding; [ws reloadDocument:d encoding:&e]; SCI(ws.editor, SCI_DOCUMENTEND); }
        [ws refreshUI];
    } enabled:^BOOL(int c) { return ws.currentDocument.path != nil && (!ws.currentDocument.dirty || ws.currentDocument.monitoring); }
                 checked:^BOOL(int c) { return ws.currentDocument.monitoring; }];

    // scroll synchronisation hook
    for (TPEditorPane *p in @[self.mainPane, self.subPane]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:NSViewBoundsDidChangeNotification object:p.editor.scrollView.contentView
                                                           queue:nil usingBlock:^(NSNotification *n) { [ws syncScrollFrom:p]; }];
        p.editor.scrollView.contentView.postsBoundsChangedNotifications = YES;
    }
}

// ---------------------------------------------------------------- helpers
- (void)setChromeHidden:(BOOL)hidden {
    self.toolbar.hidden = hidden;
    self.statusBar.hidden = hidden;
    for (TPEditorPane *p in @[self.mainPane, self.subPane]) {
        p.tabBar.hidden = hidden;
        [p setFrameSize:p.frame.size];
    }
    [self.window.contentView resizeSubviewsWithOldSize:self.window.contentView.bounds.size];
}

- (void)zoom:(int)dir {
    NSArray *targets = g_zoomSync ? @[self.mainPane.editor, self.subPane.editor] : @[self.editor];
    for (ScintillaView *v in targets) {
        if (dir > 0) SCI(v, SCI_ZOOMIN);
        else if (dir < 0) SCI(v, SCI_ZOOMOUT);
        else SCI(v, SCI_SETZOOM, 0);
    }
    [self refreshUI];
}

- (void)moveOrCloneToOtherView:(BOOL)clone {
    TPDocument *d = self.currentDocument;
    TPEditorPane *src = self.activePane, *dst = self.otherPane;
    if ([dst indexOfDocument:d] != NSNotFound) {
        // already there: just activate (upstream behaviour for "move" when cloned)
        if (!clone) {
            [src saveCurrentPosition];
            [d setPosition:[d positionForView:src.viewIndex] forView:dst.viewIndex];
            [self activateDocument:d inPane:dst];
            [self closeDocument:d inPane:src];
        }
        return;
    }
    [src saveCurrentPosition];
    [d setPosition:[d positionForView:src.viewIndex] forView:dst.viewIndex];
    [self activateDocument:d inPane:dst];
    if (!clone) {
        BOOL wasDirty = d.dirty;
        d.dirty = NO;                      // closing the source tab must not prompt: the buffer lives on
        [self closeDocument:d inPane:src];
        d.dirty = wasDirty;
        [self activatePane:dst];
    }
    [self refreshUI];
}

- (void)selectTabIndex:(NSInteger)i {
    TPEditorPane *p = self.activePane;
    if (i >= 0 && i < (NSInteger)p.documents.count) [self activateDocument:p.documents[i] inPane:p];
}

- (void)cycleTab:(int)dir {
    TPEditorPane *p = self.activePane;
    NSInteger n = (NSInteger)p.documents.count;
    if (n < 2) return;
    if ([TPPrefs b:@"pref.docSwitcherMRU"] && (NSApp.currentEvent.modifierFlags & NSEventModifierFlagControl) &&
        [NSApp.currentEvent.charactersIgnoringModifiers isEqualToString:@"\t"]) {
        // Document Switcher MRU behaviour (⌃Tab): most recently used first
        NSArray *mru = [p.documents sortedArrayUsingComparator:^NSComparisonResult(TPDocument *a, TPDocument *b) {
            return [(b.lastAccess ?: [NSDate distantPast]) compare:(a.lastAccess ?: [NSDate distantPast])];
        }];
        NSUInteger cur = [mru indexOfObjectIdenticalTo:p.currentDocument];
        TPDocument *target = mru[(cur + (dir > 0 ? 1 : mru.count - 1)) % mru.count];
        [self activateDocument:target inPane:p];
        return;
    }
    NSInteger i = [p indexOfDocument:p.currentDocument];
    [self selectTabIndex:((i + dir) % n + n) % n];
}

- (void)moveTabTo:(NSInteger)to {
    TPEditorPane *p = self.activePane;
    NSInteger from = [p indexOfDocument:p.currentDocument];
    if (from == NSNotFound || to < 0 || to >= (NSInteger)p.documents.count) return;
    [self tabBar:p.tabBar didMoveFrom:from to:to];
}

- (void)moveTabBy:(NSInteger)delta {
    TPEditorPane *p = self.activePane;
    NSInteger from = [p indexOfDocument:p.currentDocument];
    [self moveTabTo:from + delta];
}

- (void)hideSelectedLines {
    const sptr_t marker = tpp::hidelines::hideLines(self.editor);
    if (marker < 0) return;
    // upstream Buffer::setHideLineChanged(true, …): every view showing this document hides the section
    for (TPEditorPane *p in @[self.mainPane, self.subPane])
        if (p.currentDocument == self.currentDocument) tpp::hidelines::hideMarkedLines(p.editor, marker, false);
}

- (void)foldCurrent:(BOOL)fold {
    ScintillaView *v = self.editor;
    sptr_t line = SCI(v, SCI_LINEFROMPOSITION, SCI(v, SCI_GETCURRENTPOS));
    int level = static_cast<int>(SCI(v, SCI_GETFOLDLEVEL, line));
    if (!(level & SC_FOLDLEVELHEADERFLAG)) line = SCI(v, SCI_GETFOLDPARENT, line);
    if (line < 0) return;
    SCI(v, SCI_FOLDLINE, line, fold ? SC_FOLDACTION_CONTRACT : SC_FOLDACTION_EXPAND);
}

- (void)foldLevel:(int)level fold:(BOOL)fold {
    ScintillaView *v = self.editor;
    SCI(v, SCI_COLOURISE, 0, -1);
    sptr_t n = SCI(v, SCI_GETLINECOUNT);
    for (sptr_t l = 0; l < n; ++l) {
        int lv = static_cast<int>(SCI(v, SCI_GETFOLDLEVEL, l));
        if (!(lv & SC_FOLDLEVELHEADERFLAG)) continue;
        if ((lv & SC_FOLDLEVELNUMBERMASK) - SC_FOLDLEVELBASE != level) continue;
        if ((SCI(v, SCI_GETFOLDEXPANDED, l) != 0) == fold) SCI(v, SCI_FOLDLINE, l, fold ? SC_FOLDACTION_CONTRACT : SC_FOLDACTION_EXPAND);
    }
}

- (void)showSummary {
    TPDocument *d = self.currentDocument;
    ScintillaView *v = self.editor;
    std::string text = sciGetText(v);
    NSString *ns = NSStr(text);
    __block NSUInteger words = 0;
    [ns enumerateSubstringsInRange:NSMakeRange(0, ns.length) options:NSStringEnumerationByWords | NSStringEnumerationSubstringNotRequired
                        usingBlock:^(NSString *s, NSRange a, NSRange b, BOOL *stop) { ++words; }];
    sptr_t chars = SCI(v, SCI_COUNTCHARACTERS, 0, SCI(v, SCI_GETLENGTH));
    long long nonBlank = 0;
    for (unsigned char c : text) if (c != ' ' && c != '\t' && c != '\r' && c != '\n' && (c & 0xC0) != 0x80) ++nonBlank;
    NSMutableString *info = [NSMutableString string];
    if (d.path) {
        NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:d.path error:nil];
        [info appendFormat:@"Full file path: %@\nCreated: %@\nModified: %@\n\n", d.path, a.fileCreationDate, a.fileModificationDate];
    }
    [info appendFormat:@"Characters (without line endings): %ld\nWords: %lu\nLines: %ld\nDocument length: %ld\n%lld non-blank characters",
     (long)(chars - (SCI(v, SCI_GETLINECOUNT) - 1) * (SCI(v, SCI_GETEOLMODE) == SC_EOL_CRLF ? 2 : 1)), (unsigned long)words,
     (long)SCI(v, SCI_GETLINECOUNT), (long)SCI(v, SCI_GETLENGTH), nonBlank];
    if (SCI(v, SCI_GETSELECTIONEMPTY) == 0) {
        sptr_t s = SCI(v, SCI_GETSELECTIONSTART), e = SCI(v, SCI_GETSELECTIONEND);
        [info appendFormat:@"\nSelected characters: %ld (%ld bytes) in %ld ranges", (long)SCI(v, SCI_COUNTCHARACTERS, s, e), (long)(e - s), (long)SCI(v, SCI_GETSELECTIONS)];
    }
    [self showMessage:@"Summary" informative:info];
}

- (void)syncScrollFrom:(TPEditorPane *)src {
    if (g_syncing || (!g_syncV && !g_syncH) || self.subPane.hidden) return;
    TPEditorPane *dst = src == self.mainPane ? self.subPane : self.mainPane;
    static sptr_t lastFirst[2] = {0, 0}, lastX[2] = {0, 0};
    sptr_t first = SCI(src.editor, SCI_GETFIRSTVISIBLELINE), x = SCI(src.editor, SCI_GETXOFFSET);
    sptr_t df = first - lastFirst[src.viewIndex], dx = x - lastX[src.viewIndex];
    lastFirst[src.viewIndex] = first;
    lastX[src.viewIndex] = x;
    g_syncing = YES;
    if (g_syncV && df) SCI(dst.editor, SCI_LINESCROLL, 0, df);
    if (g_syncH && dx) SCI(dst.editor, SCI_SETXOFFSET, SCI(dst.editor, SCI_GETXOFFSET) + dx);
    lastFirst[dst.viewIndex] = SCI(dst.editor, SCI_GETFIRSTVISIBLELINE);
    lastX[dst.viewIndex] = SCI(dst.editor, SCI_GETXOFFSET);
    g_syncing = NO;
}

@end
