// Textpad++ — View > Compare: the documents of the two views side by side, lines added (green), deleted (red) and
// changed (yellow, with the changed characters boxed), blank space keeping both sides level, synchronized
// scrolling, next / previous difference, re-compared as either side is edited. GPL-3.0-or-later.
#import "app/Compare.h"
#import "app/Document.h"
#import "app/EditorPane.h"
#import "app/Preferences.h"
#import "app/Sci.h"
#import "commands/CommandRegistry.h"
#import "generated/NppCommandIds.h"
#include "core/Diff.h"
#include <functional>
#include <map>
using namespace npp;

NSInteger TPComparePickOverride = -1;   // tests: which other document "Compare with" picks

static const int kMarkChanged = 0, kMarkAdded = 16, kMarkDeleted = 17, kIndicChars = 20;   // 21-25 are Mark Style 1-5; plugins get 9-19

@interface TPCompareState : NSObject
@property (nonatomic, weak) TPDocument *left, *right;
@property (nonatomic) BOOL turnedOnSync;
@property (nonatomic) size_t hashLeft, hashRight;
@property (nonatomic) std::vector<std::pair<size_t, size_t>> starts;   // hunk starts: left line, right line
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic) TPCompareSummary summary;
@end
@implementation TPCompareState
@end

static TPCompareState *g_state;

static void defineMarks(ScintillaView *v) {
    const BOOL dark = [TPChrome dark];
    SCI(v, SCI_MARKERDEFINE, kMarkChanged, SC_MARK_BACKGROUND);
    SCI(v, SCI_MARKERSETBACK, kMarkChanged, dark ? 0x1E4A5A : 0xC8F2FF);   // BGR: yellow-ish
    SCI(v, SCI_MARKERDEFINE, kMarkAdded, SC_MARK_BACKGROUND);
    SCI(v, SCI_MARKERSETBACK, kMarkAdded, dark ? 0x2A4A22 : 0xD4F5D4);
    SCI(v, SCI_MARKERDEFINE, kMarkDeleted, SC_MARK_BACKGROUND);
    SCI(v, SCI_MARKERSETBACK, kMarkDeleted, dark ? 0x2A2A5C : 0xD8D8FF);
    SCI(v, SCI_INDICSETSTYLE, kIndicChars, INDIC_FULLBOX);
    SCI(v, SCI_INDICSETFORE, kIndicChars, dark ? 0x30A0F0 : 0x0090F0);
    SCI(v, SCI_INDICSETALPHA, kIndicChars, dark ? 90 : 70);
    SCI(v, SCI_INDICSETOUTLINEALPHA, kIndicChars, 140);
    SCI(v, SCI_INDICSETUNDER, kIndicChars, 1);
    SCI(v, SCI_ANNOTATIONSETVISIBLE, ANNOTATION_STANDARD);
}

static void clearMarks(ScintillaView *v) {
    for (int m : {kMarkChanged, kMarkAdded, kMarkDeleted}) SCI(v, SCI_MARKERDELETEALL, m);
    SCI(v, SCI_SETINDICATORCURRENT, kIndicChars);
    SCI(v, SCI_INDICATORCLEARRANGE, 0, SCI(v, SCI_GETLENGTH));
    SCI(v, SCI_ANNOTATIONCLEARALL);
}

static void addGap(size_t beforeLine, size_t count, std::map<size_t, size_t> &gaps) { if (count) gaps[beforeLine] += count; }

@implementation TPMainWindowController (Compare)

- (BOOL)isComparing { return g_state != nil; }
- (TPCompareSummary)compareSummary { return g_state ? g_state.summary : TPCompareSummary{}; }

- (nullable TPDocument *)pickDocumentToCompareWith:(TPDocument *)a among:(NSArray<TPDocument *> *)others {
    if (others.count == 1) return others[0];
    if (TPComparePickOverride >= 0) return TPComparePickOverride < (NSInteger)others.count ? others[TPComparePickOverride] : nil;
    if (self.selfTestMode) return others[0];
    NSAlert *al = [NSAlert new];
    al.messageText = [NSString stringWithFormat:@"Compare “%@” with:", a.displayName];
    al.informativeText = @"The second file opens in the other view, side by side.";
    NSPopUpButton *pop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 360, 26) pullsDown:NO];
    for (TPDocument *d in others) [pop addItemWithTitle:d.path ?: d.displayName];
    al.accessoryView = pop;
    [al addButtonWithTitle:@"Compare"];
    [al addButtonWithTitle:@"Cancel"];
    if ([al runModal] != NSAlertFirstButtonReturn) return nil;
    return others[(NSUInteger)MAX(0, pop.indexOfSelectedItem)];
}

- (void)compareStart {
    TPDocument *a = self.currentDocument;
    if (!a) return;
    if (g_state) [self compareClear];
    TPDocument *left = nil, *right = nil;
    if (!self.subPane.hidden && self.mainPane.currentDocument && self.subPane.currentDocument && self.mainPane.currentDocument != self.subPane.currentDocument) {
        left = self.mainPane.currentDocument;
        right = self.subPane.currentDocument;
    } else {
        NSMutableArray *others = [self.allDocuments mutableCopy];
        [others removeObject:a];
        if (!others.count) { [self showMessage:@"Open a second file to compare with." informative:@"Compare shows two documents side by side and marks what differs."]; return; }
        TPDocument *b = [self pickDocumentToCompareWith:a among:others];
        if (!b) return;
        TPEditorPane *paneA = [self.mainPane indexOfDocument:a] != NSNotFound ? self.mainPane : self.subPane;
        TPEditorPane *paneB = [self.mainPane indexOfDocument:b] != NSNotFound ? self.mainPane : self.subPane;
        if (paneA == paneB) {   // the second file goes to the other view
            [self activateDocument:b inPane:paneB];
            [self moveOrCloneToOtherView:NO];
            [self activateDocument:a inPane:paneA];
        } else [self activateDocument:b inPane:paneB];
        left = self.mainPane.currentDocument;
        right = self.subPane.currentDocument;
    }
    if (!left || !right || left == right) return;
    g_state = [TPCompareState new];
    g_state.left = left;
    g_state.right = right;
    if (![[TPCommandRegistry shared] isChecked:IDM_VIEW_SYNSCROLLV]) { [[TPCommandRegistry shared] execute:IDM_VIEW_SYNSCROLLV]; g_state.turnedOnSync = YES; }
    [self compareRun];
    if (g_state.starts.empty()) [self showMessage:@"The files are identical." informative:[NSString stringWithFormat:@"%@\n%@", left.displayName, right.displayName]];
    else { SCI(self.mainPane.editor, SCI_SETFIRSTVISIBLELINE, 0); SCI(self.subPane.editor, SCI_SETFIRSTVISIBLELINE, 0); [self compareJump:YES]; }
    __weak TPMainWindowController *ws = self;
    g_state.timer = [NSTimer scheduledTimerWithTimeInterval:0.6 repeats:YES block:^(NSTimer *t) { [ws compareWatch]; }];
}

// the documents are still side by side? re-compare when either changed
- (void)compareWatch {
    if (!g_state) return;
    if (self.subPane.hidden || self.mainPane.currentDocument != g_state.left || self.subPane.currentDocument != g_state.right) { [self compareClear]; return; }
    const size_t hl = std::hash<std::string>{}(sciGetText(self.mainPane.editor)), hr = std::hash<std::string>{}(sciGetText(self.subPane.editor));
    if (hl != g_state.hashLeft || hr != g_state.hashRight) [self compareRun];
}

- (void)compareRun {
    if (!g_state) return;
    ScintillaView *L = self.mainPane.editor, *R = self.subPane.editor;
    const std::string a = sciGetText(L), b = sciGetText(R);
    g_state.hashLeft = std::hash<std::string>{}(a);
    g_state.hashRight = std::hash<std::string>{}(b);
    for (ScintillaView *v : {L, R}) { defineMarks(v); clearMarks(v); }
    const auto hunks = tpp::diff::diffLines(a, b, [TPPrefs b:@"pref.compareIgnoreSpaces"]);
    std::map<size_t, size_t> gapsL, gapsR;
    std::vector<std::pair<size_t, size_t>> starts;
    TPCompareSummary sum{};
    const std::vector<std::string> la = tpp::diff::splitLines(a), lb = tpp::diff::splitLines(b);
    for (const auto &h : hunks) {
        starts.push_back({h.aStart, h.bStart});
        const size_t paired = std::min(h.aCount, h.bCount);
        for (size_t k = 0; k < paired; ++k) {
            SCI(L, SCI_MARKERADD, h.aStart + k, kMarkChanged);
            SCI(R, SCI_MARKERADD, h.bStart + k, kMarkChanged);
            const std::string &x = la[h.aStart + k], &y = lb[h.bStart + k];
            if (x.size() < 4000 && y.size() < 4000) {
                const sptr_t pa = SCI(L, SCI_POSITIONFROMLINE, h.aStart + k), pb = SCI(R, SCI_POSITIONFROMLINE, h.bStart + k);
                for (const auto &c : tpp::diff::diffChars(x, y)) {
                    SCI(L, SCI_SETINDICATORCURRENT, kIndicChars);
                    if (c.aCount) SCI(L, SCI_INDICATORFILLRANGE, pa + c.aStart, c.aCount);
                    SCI(R, SCI_SETINDICATORCURRENT, kIndicChars);
                    if (c.bCount) SCI(R, SCI_INDICATORFILLRANGE, pb + c.bStart, c.bCount);
                }
            }
        }
        sum.changed += paired;
        for (size_t k = paired; k < h.aCount; ++k) SCI(L, SCI_MARKERADD, h.aStart + k, kMarkDeleted);
        for (size_t k = paired; k < h.bCount; ++k) SCI(R, SCI_MARKERADD, h.bStart + k, kMarkAdded);
        sum.deleted += h.aCount - paired;
        sum.added += h.bCount - paired;
        // blank space on the shorter side keeps the following lines level
        if (h.aCount > h.bCount) addGap(h.bStart + h.bCount, h.aCount - h.bCount, gapsR);
        if (h.bCount > h.aCount) addGap(h.aStart + h.aCount, h.bCount - h.aCount, gapsL);
    }
    // a gap "before line n" is an annotation under line n - 1 (one under line 0 when the gap opens the file)
    for (auto [v, gaps] : {std::pair{L, &gapsL}, std::pair{R, &gapsR}}) {
        std::map<size_t, size_t> under;
        for (auto [before, n] : *gaps) under[before ? before - 1 : 0] += n;
        for (auto [line, n] : under) {
            std::string blank;
            for (size_t k = 0; k < n; ++k) blank += k ? "\n " : " ";
            SCI(v, SCI_ANNOTATIONSETTEXT, line, reinterpret_cast<sptr_t>(blank.c_str()));
            SCI(v, SCI_ANNOTATIONSETSTYLE, line, STYLE_LINENUMBER);
        }
    }
    g_state.starts = starts;
    sum.hunks = hunks.size();
    g_state.summary = sum;
    [self.statusBar setText:hunks.empty() ? @"Compare: identical" : [NSString stringWithFormat:@"Compare: %lu changed, %lu added, %lu deleted line(s)",
                             (unsigned long)sum.changed, (unsigned long)sum.added, (unsigned long)sum.deleted] forPart:0];
}

- (void)compareJump:(BOOL)forward {
    if (!g_state || g_state.starts.empty()) return;
    const BOOL right = self.activePane == self.subPane;
    ScintillaView *v = right ? self.subPane.editor : self.mainPane.editor;
    const size_t cur = SCI(v, SCI_LINEFROMPOSITION, SCI(v, SCI_GETCURRENTPOS));
    const auto &st = g_state.starts;
    NSInteger pick = -1;
    if (forward) { for (size_t k = 0; k < st.size(); ++k) if ((right ? st[k].second : st[k].first) > cur) { pick = k; break; } if (pick < 0) pick = 0; }
    else { for (NSInteger k = (NSInteger)st.size() - 1; k >= 0; --k) if ((right ? st[k].second : st[k].first) < cur) { pick = k; break; } if (pick < 0) pick = st.size() - 1; }
    for (TPEditorPane *p in @[self.mainPane, self.subPane]) {
        const size_t line = p == self.subPane ? st[pick].second : st[pick].first;
        ScintillaView *e = p.editor;
        const sptr_t lines = SCI(e, SCI_GETLINECOUNT);
        const sptr_t l = MIN((sptr_t)line, lines - 1);
        SCI(e, SCI_GOTOLINE, l);
        SCI(e, SCI_SETFIRSTVISIBLELINE, MAX((sptr_t)0, SCI(e, SCI_VISIBLEFROMDOCLINE, l) - 3));
    }
}

- (void)compareClear {
    if (!g_state) return;
    [g_state.timer invalidate];
    for (TPEditorPane *p in @[self.mainPane, self.subPane]) clearMarks(p.editor);
    if (g_state.turnedOnSync && [[TPCommandRegistry shared] isChecked:IDM_VIEW_SYNSCROLLV]) [[TPCommandRegistry shared] execute:IDM_VIEW_SYNSCROLLV];
    g_state = nil;
    [self.statusBar setText:@"" forPart:0];
    [self refreshUI];
}

@end
