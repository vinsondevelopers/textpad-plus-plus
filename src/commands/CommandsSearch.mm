// Textpad++ — Search menu commands (upstream NppCommands.cpp IDM_SEARCH_*). GPL-3.0-or-later.
#import "app/MainWindowController.h"
#import "dialogs/FindCharsInRangeDialog.h"
#import "search/IncrementalSearchBar.h"
#import "search/FindReplaceController.h"
#import "search/SearchResultsPanel.h"
#import "app/Preferences.h"
#include "core/TextOps.h"

using namespace npp;
using namespace tpp::search;

static const int kStyleIndic[5] = {25, 24, 23, 22, 21};   // Mark Style 1..5

@implementation TPMainWindowController (SearchCommands)

- (void)registerSearchCommands:(TPCommandRegistry *)reg {
    __weak TPMainWindowController *ws = self;
    TPCommandPredicate hasDoc = ^BOOL(int c) { return ws.currentDocument != nil; };

    [reg registerCommand:IDM_SEARCH_FIND handler:^(int c) { [ws.findController showTab:TPFindTabFind]; }];
    [reg registerCommand:IDM_SEARCH_REPLACE handler:^(int c) { [ws.findController showTab:TPFindTabReplace]; }];
    [reg registerCommand:IDM_SEARCH_FINDINFILES handler:^(int c) { [ws.findController showTab:TPFindTabFindInFiles]; }];
    [reg registerCommand:IDM_SEARCH_MARK handler:^(int c) { [ws.findController showTab:TPFindTabMark]; }];
    [reg registerCommand:IDM_SEARCH_FINDNEXT handler:^(int c) {
        if (ws.findController.currentOptions.find.empty()) [ws.findController showTab:TPFindTabFind];
        else [ws.findController findNext:YES];
    } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_FINDPREV handler:^(int c) {
        if (ws.findController.currentOptions.find.empty()) [ws.findController showTab:TPFindTabFind];
        else [ws.findController findNext:NO];
    } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_SETANDFINDNEXT handler:^(int c) { [ws selectAndFind:YES volatile:NO]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_SETANDFINDPREV handler:^(int c) { [ws selectAndFind:NO volatile:NO]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_VOLATILE_FINDNEXT handler:^(int c) { [ws selectAndFind:YES volatile:YES]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_VOLATILE_FINDPREV handler:^(int c) { [ws selectAndFind:NO volatile:YES]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_FOCUS_ON_FOUND_RESULTS handler:^(int c) {
        [ws.resultsPanel showPanel];
        [ws.window makeFirstResponder:ws.resultsPanel.view.content];
    }];
    [reg registerCommand:IDM_SEARCH_GOTONEXTFOUND handler:^(int c) { [ws.resultsPanel gotoNext:YES]; } enabled:^BOOL(int c) { return ws.resultsPanel.lastHitCount > 0; } checked:nil];
    [reg registerCommand:IDM_SEARCH_GOTOPREVFOUND handler:^(int c) { [ws.resultsPanel gotoNext:NO]; } enabled:^BOOL(int c) { return ws.resultsPanel.lastHitCount > 0; } checked:nil];
    [reg registerCommand:IDM_SEARCH_GOTOLINE handler:^(int c) { [ws goToDialog]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_GOTOMATCHINGBRACE handler:^(int c) { [ws gotoBrace:NO]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_SELECTMATCHINGBRACES handler:^(int c) { [ws gotoBrace:YES]; } enabled:hasDoc checked:nil];

    // Change history
    [reg registerCommand:IDM_SEARCH_CHANGED_NEXT handler:^(int c) { [ws jumpChange:YES]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_CHANGED_PREV handler:^(int c) { [ws jumpChange:NO]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_CLEAR_CHANGE_HISTORY handler:^(int c) {
        ScintillaView *v = ws.editor;
        if (SCI(v, SCI_CANUNDO)) {
            NSInteger r = [ws prompt:@"Clear Change History" informative:@"Clearing the change history also clears the undo history of this document.\n\nContinue?" buttons:@[@"Yes", @"No"]];
            if (r != 0) return;
        }
        SCI(v, SCI_EMPTYUNDOBUFFER);
        SCI(v, SCI_SETCHANGEHISTORY, SC_CHANGE_HISTORY_DISABLED);
        SCI(v, SCI_SETCHANGEHISTORY, SC_CHANGE_HISTORY_ENABLED | SC_CHANGE_HISTORY_MARKERS);
    } enabled:hasDoc checked:nil];

    // Token styles 1..5
    int markAll[5] = {IDM_SEARCH_MARKALLEXT1, IDM_SEARCH_MARKALLEXT2, IDM_SEARCH_MARKALLEXT3, IDM_SEARCH_MARKALLEXT4, IDM_SEARCH_MARKALLEXT5};
    int markOne[5] = {IDM_SEARCH_MARKONEEXT1, IDM_SEARCH_MARKONEEXT2, IDM_SEARCH_MARKONEEXT3, IDM_SEARCH_MARKONEEXT4, IDM_SEARCH_MARKONEEXT5};
    int unmark[5] = {IDM_SEARCH_UNMARKALLEXT1, IDM_SEARCH_UNMARKALLEXT2, IDM_SEARCH_UNMARKALLEXT3, IDM_SEARCH_UNMARKALLEXT4, IDM_SEARCH_UNMARKALLEXT5};
    int prevM[5] = {IDM_SEARCH_GOPREVMARKER1, IDM_SEARCH_GOPREVMARKER2, IDM_SEARCH_GOPREVMARKER3, IDM_SEARCH_GOPREVMARKER4, IDM_SEARCH_GOPREVMARKER5};
    int nextM[5] = {IDM_SEARCH_GONEXTMARKER1, IDM_SEARCH_GONEXTMARKER2, IDM_SEARCH_GONEXTMARKER3, IDM_SEARCH_GONEXTMARKER4, IDM_SEARCH_GONEXTMARKER5};
    int toClip[5] = {IDM_SEARCH_STYLE1TOCLIP, IDM_SEARCH_STYLE2TOCLIP, IDM_SEARCH_STYLE3TOCLIP, IDM_SEARCH_STYLE4TOCLIP, IDM_SEARCH_STYLE5TOCLIP};
    for (int i = 0; i < 5; ++i) {
        int indic = kStyleIndic[i];
        [reg registerCommand:markAll[i] handler:^(int c) { [ws styleToken:indic all:YES]; } enabled:hasDoc checked:nil];
        [reg registerCommand:markOne[i] handler:^(int c) { [ws styleToken:indic all:NO]; } enabled:hasDoc checked:nil];
        [reg registerCommand:unmark[i] handler:^(int c) { [ws clearIndicator:indic]; } enabled:hasDoc checked:nil];
        [reg registerCommand:prevM[i] handler:^(int c) { [ws jumpIndicator:indic forward:NO]; } enabled:hasDoc checked:nil];
        [reg registerCommand:nextM[i] handler:^(int c) { [ws jumpIndicator:indic forward:YES]; } enabled:hasDoc checked:nil];
        [reg registerCommand:toClip[i] handler:^(int c) { [ws copyIndicators:@[@(indic)]]; } enabled:hasDoc checked:nil];
    }
    [reg registerCommand:IDM_SEARCH_CLEARALLMARKS handler:^(int c) { for (int i = 0; i < 5; ++i) [ws clearIndicator:kStyleIndic[i]]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_GOPREVMARKER_DEF handler:^(int c) { [ws jumpIndicator:TPP_INDIC_FOUND forward:NO]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_GONEXTMARKER_DEF handler:^(int c) { [ws jumpIndicator:TPP_INDIC_FOUND forward:YES]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_ALLSTYLESTOCLIP handler:^(int c) { [ws copyIndicators:@[@25, @24, @23, @22, @21]]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_MARKEDTOCLIP handler:^(int c) { [ws copyIndicators:@[@(TPP_INDIC_FOUND)]]; } enabled:hasDoc checked:nil];

    // Bookmarks
    [reg registerCommand:IDM_SEARCH_TOGGLE_BOOKMARK handler:^(int c) {
        ScintillaView *v = ws.editor;
        sptr_t line = SCI(v, SCI_LINEFROMPOSITION, SCI(v, SCI_GETCURRENTPOS));
        if (SCI(v, SCI_MARKERGET, line) & (1 << TPP_MARK_BOOKMARK)) SCI(v, SCI_MARKERDELETE, line, TPP_MARK_BOOKMARK);
        else SCI(v, SCI_MARKERADD, line, TPP_MARK_BOOKMARK);
    } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_NEXT_BOOKMARK handler:^(int c) { [ws jumpBookmark:YES]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_PREV_BOOKMARK handler:^(int c) { [ws jumpBookmark:NO]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_CLEAR_BOOKMARKS handler:^(int c) { SCI(ws.editor, SCI_MARKERDELETEALL, TPP_MARK_BOOKMARK); } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_CUTMARKEDLINES handler:^(int c) { [ws bookmarkedLinesToClipboard:YES]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_COPYMARKEDLINES handler:^(int c) { [ws bookmarkedLinesToClipboard:NO]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_PASTEMARKEDLINES handler:^(int c) { [ws pasteToBookmarkedLines]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_DELETEMARKEDLINES handler:^(int c) { [ws deleteBookmarkedLines:YES]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_DELETEUNMARKEDLINES handler:^(int c) { [ws deleteBookmarkedLines:NO]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_INVERSEMARKS handler:^(int c) {
        ScintillaView *v = ws.editor;
        sptr_t n = SCI(v, SCI_GETLINECOUNT);
        for (sptr_t l = 0; l < n; ++l) {
            if (SCI(v, SCI_MARKERGET, l) & (1 << TPP_MARK_BOOKMARK)) SCI(v, SCI_MARKERDELETE, l, TPP_MARK_BOOKMARK);
            else SCI(v, SCI_MARKERADD, l, TPP_MARK_BOOKMARK);
        }
    } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_FINDCHARINRANGE handler:^(int c) { [ws findCharsInRange]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_SEARCH_FINDINCREMENT handler:^(int c) { [ws.incrementalSearchBar show]; } enabled:hasDoc checked:nil];
}

// ---------------------------------------------------------------- helpers
- (void)selectAndFind:(BOOL)forward volatile:(BOOL)isVolatile {
    ScintillaView *v = self.editor;
    if (SCI(v, SCI_GETSELECTIONEMPTY)) {
        sptr_t pos = SCI(v, SCI_GETCURRENTPOS);
        SCI(v, SCI_SETSEL, SCI(v, SCI_WORDSTARTPOSITION, pos, 1), SCI(v, SCI_WORDENDPOSITION, pos, 1));
    }
    std::string sel = sciSelectedText(v);
    if (sel.empty()) return;
    Options o = self.findController.currentOptions;
    o.find = sel;
    o.mode = Mode::Normal;
    o.backward = !forward;
    o.wrap = YES;
    if (!isVolatile) [self.findController setFindText:NSStr(sel)];
    FindResult r = findNext(v, o);
    if (!r.found) TPBeep();
}

- (void)goToDialog {
    ScintillaView *v = self.editor;
    NSAlert *a = [NSAlert new];
    a.messageText = @"Go To...";
    NSView *acc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)];
    NSButton *lineR = [NSButton radioButtonWithTitle:@"Line" target:nil action:nil];
    NSButton *offR = [NSButton radioButtonWithTitle:@"Offset" target:nil action:nil];
    lineR.frame = NSMakeRect(0, 78, 80, 20); offR.frame = NSMakeRect(90, 78, 80, 20);
    lineR.action = offR.action = @selector(self);
    lineR.state = NSControlStateValueOn;
    sptr_t curLine = SCI(v, SCI_LINEFROMPOSITION, SCI(v, SCI_GETCURRENTPOS)) + 1;
    NSTextField *here = [NSTextField labelWithString:[NSString stringWithFormat:@"You are here :  %ld", (long)curLine]];
    here.frame = NSMakeRect(0, 54, 300, 18);
    NSTextField *want = [[NSTextField alloc] initWithFrame:NSMakeRect(130, 26, 120, 22)];
    NSTextField *wantL = [NSTextField labelWithString:@"You want to go to :"];
    wantL.frame = NSMakeRect(0, 28, 130, 18);
    NSTextField *max = [NSTextField labelWithString:[NSString stringWithFormat:@"You can't go further than :  %ld", (long)SCI(v, SCI_GETLINECOUNT)]];
    max.frame = NSMakeRect(0, 2, 300, 18);
    for (NSView *x in @[lineR, offR, here, wantL, want, max]) [acc addSubview:x];
    a.accessoryView = acc;
    [a addButtonWithTitle:@"Go"];
    [a addButtonWithTitle:@"I'm going nowhere"];
    a.window.initialFirstResponder = want;
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    long long n = want.stringValue.longLongValue;
    if (offR.state == NSControlStateValueOn) {
        sptr_t pos = MAX(0LL, MIN(n, (long long)SCI(v, SCI_GETLENGTH)));
        SCI(v, SCI_GOTOPOS, pos);
    } else {
        sptr_t line = MAX(1LL, MIN(n, (long long)SCI(v, SCI_GETLINECOUNT))) - 1;
        SCI(v, SCI_ENSUREVISIBLE, line);
        SCI(v, SCI_GOTOLINE, line);
    }
    SCI(v, SCI_SCROLLCARET);
    [self.window makeFirstResponder:v.content];
}

- (void)gotoBrace:(BOOL)selectBetween {
    ScintillaView *v = self.editor;
    sptr_t pos = SCI(v, SCI_GETCURRENTPOS);
    auto isBrace = [](int c) { return c == '(' || c == ')' || c == '[' || c == ']' || c == '{' || c == '}'; };
    sptr_t at = -1;
    if (pos > 0 && isBrace(static_cast<int>(SCI(v, SCI_GETCHARAT, pos - 1)))) at = pos - 1;
    else if (isBrace(static_cast<int>(SCI(v, SCI_GETCHARAT, pos)))) at = pos;
    if (at < 0) {
        if (!selectBetween) return;
        // upstream: select the content between the enclosing braces
        for (sptr_t p = pos - 1; p >= 0; --p) {
            int ch = static_cast<int>(SCI(v, SCI_GETCHARAT, p));
            if (ch == '(' || ch == '[' || ch == '{') {
                sptr_t m = SCI(v, SCI_BRACEMATCH, p, 0);
                if (m > pos - 1) { SCI(v, SCI_SETSEL, p + 1, m); return; }
            }
        }
        return;
    }
    sptr_t match = SCI(v, SCI_BRACEMATCH, at, 0);
    if (match < 0) return;
    if (selectBetween) {
        sptr_t a = MIN(at, match), b = MAX(at, match);
        SCI(v, SCI_SETSEL, a + 1, b);
    } else {
        SCI(v, SCI_GOTOPOS, match > at ? match + (at == pos - 1 ? 1 : 0) : match);
    }
}

// Port of Notepad_plus::changedHistoryGoTo. SCI_MARKERGET / SCI_MARKERPREVIOUS include the
// change-history markers; SCI_MARKERNEXT does not, so "next" walks lines with MARKERGET.
- (void)jumpChange:(BOOL)forward {
    ScintillaView *v = self.editor;
    const int mask = SC_MASK_HISTORY;
    sptr_t line = -1;
    sptr_t blockIndicator = SCI(v, SCI_LINEFROMPOSITION, SCI(v, SCI_GETCURRENTPOS));
    sptr_t lastLine = SCI(v, SCI_GETLINECOUNT);
    if (forward) {
        sptr_t currentLine = blockIndicator;
        for (sptr_t i = currentLine; i < lastLine; i++) {
            if (SCI(v, SCI_MARKERGET, i) & mask) {
                if (i != blockIndicator) { line = i; break; }
                else blockIndicator++;
            }
        }
        if (line == -1) {
            sptr_t endRange = currentLine + 1;
            for (sptr_t i = 0; i < endRange; i++)
                if (SCI(v, SCI_MARKERGET, i) & mask) { line = i; break; }
        }
    } else {
        while (true) {
            line = SCI(v, SCI_MARKERPREVIOUS, blockIndicator, mask);
            if (line == -1 || line != blockIndicator) break;
            else blockIndicator--;
        }
        if (line == -1) line = SCI(v, SCI_MARKERPREVIOUS, lastLine - 1, mask);
    }
    if (line != -1) {
        SCI(v, SCI_ENSUREVISIBLEENFORCEPOLICY, line);
        SCI(v, SCI_GOTOLINE, line);
    } else {
        TPBeep();
    }
}

- (void)styleToken:(int)indic all:(BOOL)all {
    ScintillaView *v = self.editor;
    BOOL hadSelection = SCI(v, SCI_GETSELECTIONEMPTY) == 0;
    sptr_t s, e;
    if (hadSelection) { s = SCI(v, SCI_GETSELECTIONSTART); e = SCI(v, SCI_GETSELECTIONEND); }
    else { sptr_t p = SCI(v, SCI_GETCURRENTPOS); s = SCI(v, SCI_WORDSTARTPOSITION, p, 1); e = SCI(v, SCI_WORDENDPOSITION, p, 1); }
    if (s >= e) return;
    SCI(v, SCI_SETINDICATORCURRENT, indic);
    if (!all) { SCI(v, SCI_INDICATORFILLRANGE, s, e - s); return; }
    Options o;
    o.find = sciGetRange(v, s, e);
    o.matchCase = [TPPrefs b:@"pref.markAllMatchCase"];          // Preferences > Highlighting > Style All Occurrences of Token
    o.wholeWord = [TPPrefs b:@"pref.markAllWholeWord"] && SCI(v, SCI_WORDSTARTPOSITION, s, 1) == s && SCI(v, SCI_WORDENDPOSITION, s, 1) == e;
    std::vector<Match> m;
    findAll(v, o, 0, -1, m, nullptr);
    for (auto &x : m) SCI(v, SCI_INDICATORFILLRANGE, x.start, x.end - x.start);
}

- (void)clearIndicator:(int)indic {
    ScintillaView *v = self.editor;
    SCI(v, SCI_SETINDICATORCURRENT, indic);
    SCI(v, SCI_INDICATORCLEARRANGE, 0, SCI(v, SCI_GETLENGTH));
}

- (void)jumpIndicator:(int)indic forward:(BOOL)forward {
    ScintillaView *v = self.editor;
    sptr_t len = SCI(v, SCI_GETLENGTH);
    sptr_t pos = forward ? SCI(v, SCI_GETSELECTIONEND) : SCI(v, SCI_GETSELECTIONSTART);
    auto findFrom = [&](sptr_t p) -> sptr_t {
        if (forward) {
            if (SCI(v, SCI_INDICATORVALUEAT, indic, p)) p = SCI(v, SCI_INDICATOREND, indic, p);
            if (p >= len) return -1;
            sptr_t s = SCI(v, SCI_INDICATORVALUEAT, indic, p) ? p : SCI(v, SCI_INDICATOREND, indic, p);
            return (s < len && SCI(v, SCI_INDICATORVALUEAT, indic, s)) ? s : -1;
        } else {
            if (p <= 0) return -1;
            sptr_t q = p - 1;
            if (SCI(v, SCI_INDICATORVALUEAT, indic, q)) q = SCI(v, SCI_INDICATORSTART, indic, q) - 1;
            while (q >= 0 && !SCI(v, SCI_INDICATORVALUEAT, indic, q)) {
                sptr_t st = SCI(v, SCI_INDICATORSTART, indic, q);
                if (st <= 0) return -1;
                q = st - 1;
            }
            return q >= 0 ? SCI(v, SCI_INDICATORSTART, indic, q) : -1;
        }
    };
    sptr_t s = findFrom(pos);
    if (s < 0) s = findFrom(forward ? 0 : len);   // wrap
    if (s < 0) { TPBeep(); return; }
    sptr_t e = SCI(v, SCI_INDICATOREND, indic, s);
    SCI(v, SCI_ENSUREVISIBLE, SCI(v, SCI_LINEFROMPOSITION, s));
    SCI(v, SCI_SETSEL, s, e);
}

- (void)copyIndicators:(NSArray<NSNumber *> *)indics {
    ScintillaView *v = self.editor;
    sptr_t len = SCI(v, SCI_GETLENGTH);
    std::string out;
    std::string eol = sciEolString(v);
    sptr_t pos = 0;
    while (pos < len) {
        BOOL on = NO;
        for (NSNumber *n in indics) if (SCI(v, SCI_INDICATORVALUEAT, n.intValue, pos)) on = YES;
        if (!on) {
            sptr_t next = len;
            for (NSNumber *n in indics) { sptr_t e = SCI(v, SCI_INDICATOREND, n.intValue, pos); if (e > pos && e < next) next = e; }
            pos = next;
            continue;
        }
        sptr_t end = pos + 1;
        while (end < len) {
            BOOL still = NO;
            for (NSNumber *n in indics) if (SCI(v, SCI_INDICATORVALUEAT, n.intValue, end)) still = YES;
            if (!still) break;
            ++end;
        }
        if (!out.empty()) out += eol;
        out += sciGetRange(v, pos, end);
        pos = end;
    }
    if (out.empty()) return;
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:NSStr(out) forType:NSPasteboardTypeString];
}

- (void)jumpBookmark:(BOOL)forward {
    ScintillaView *v = self.editor;
    sptr_t line = SCI(v, SCI_LINEFROMPOSITION, SCI(v, SCI_GETCURRENTPOS));
    int mask = 1 << TPP_MARK_BOOKMARK;
    sptr_t t = forward ? SCI(v, SCI_MARKERNEXT, line + 1, mask) : SCI(v, SCI_MARKERPREVIOUS, line - 1, mask);
    if (t < 0) t = forward ? SCI(v, SCI_MARKERNEXT, 0, mask) : SCI(v, SCI_MARKERPREVIOUS, SCI(v, SCI_GETLINECOUNT), mask);   // wrap
    if (t >= 0) { SCI(v, SCI_ENSUREVISIBLE, t); SCI(v, SCI_GOTOLINE, t); }
}

- (std::vector<sptr_t>)bookmarkedLines {
    ScintillaView *v = self.editor;
    std::vector<sptr_t> lines;
    sptr_t l = SCI(v, SCI_MARKERNEXT, 0, 1 << TPP_MARK_BOOKMARK);
    while (l >= 0) { lines.push_back(l); l = SCI(v, SCI_MARKERNEXT, l + 1, 1 << TPP_MARK_BOOKMARK); }
    return lines;
}

- (void)bookmarkedLinesToClipboard:(BOOL)cut {
    ScintillaView *v = self.editor;
    auto lines = [self bookmarkedLines];
    if (lines.empty()) return;
    std::string out;
    for (sptr_t l : lines) {
        sptr_t s = SCI(v, SCI_POSITIONFROMLINE, l), e = SCI(v, SCI_POSITIONFROMLINE, l + 1);
        if (l + 1 >= SCI(v, SCI_GETLINECOUNT)) e = SCI(v, SCI_GETLENGTH);
        out += sciGetRange(v, s, e);
    }
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:NSStr(out) forType:NSPasteboardTypeString];
    if (cut) [self deleteBookmarkedLines:YES];
}

- (void)pasteToBookmarkedLines {
    ScintillaView *v = self.editor;
    auto lines = [self bookmarkedLines];
    NSString *clip = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
    if (lines.empty() || !clip) return;
    std::string text = StdStr(clip);
    SCI(v, SCI_BEGINUNDOACTION);
    for (auto it = lines.rbegin(); it != lines.rend(); ++it) {
        sptr_t s = SCI(v, SCI_POSITIONFROMLINE, *it), e = SCI(v, SCI_POSITIONFROMLINE, *it + 1);
        if (*it + 1 >= SCI(v, SCI_GETLINECOUNT)) e = SCI(v, SCI_GETLENGTH);
        sciReplaceRange(v, s, e, text);
    }
    SCI(v, SCI_ENDUNDOACTION);
}

// Port of Notepad_plus::deleteMarkedLines / deleteMarkedline: each line is removed together with
// its own line ending ([line start, line start + SCI_LINELENGTH)), last line included.
- (void)deleteBookmarkedLines:(BOOL)marked {
    ScintillaView *v = self.editor;
    sptr_t lastLine = SCI(v, SCI_LINEFROMPOSITION, SCI(v, SCI_GETLENGTH));
    SCI(v, SCI_BEGINUNDOACTION);
    for (sptr_t l = lastLine; l >= 0; --l) {
        BOOL isMarked = (SCI(v, SCI_MARKERGET, l) & (1 << TPP_MARK_BOOKMARK)) != 0;
        if (isMarked != marked) continue;
        sptr_t begin = SCI(v, SCI_POSITIONFROMLINE, l);
        sptr_t len = SCI(v, SCI_LINELENGTH, l);
        SCI(v, SCI_MARKERDELETE, l, TPP_MARK_BOOKMARK);
        sciReplaceRange(v, begin, begin + len, "");
    }
    SCI(v, SCI_ENDUNDOACTION);
}

// upstream FindCharsInRangeDlg (non-modal)
- (void)findCharsInRange {
    [[TPFindCharsInRangeDialog sharedWithController:self] showWindow:nil];
}

@end
