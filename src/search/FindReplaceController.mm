// Textpad++ — Find / Replace / Find in Files / Mark dialog. GPL-3.0-or-later.
#import "search/FindReplaceController.h"
#import "search/SearchResultsPanel.h"
#import "app/MainWindowController.h"
#import "app/Preferences.h"
#include "core/Encoding.h"
#include <fnmatch.h>

using namespace tpp::search;

@implementation TPFindReplaceController {
    __weak TPMainWindowController *_c;
    NSSegmentedControl *_tabs;
    NSComboBox *_findCombo, *_replaceCombo;
    NSTextField *_findLabel, *_replaceLabel, *_filtersLabel, *_dirLabel, *_status;
    NSTextField *_filtersField, *_dirField;
    NSButton *_dirBrowse, *_followDoc, *_subFolders, *_hiddenCheck, *_proj1, *_proj2, *_proj3;
    NSButton *_highlightCheck, *_transCheck, *_transLossFocus, *_transAlways;
    NSSlider *_transSlider;
    NSButton *_backward, *_wholeWord, *_matchCase, *_wrap, *_inSelection;
    NSButton *_modeNormal, *_modeExtended, *_modeRegex, *_dotNewline;
    NSButton *_bookmarkLine, *_purge;
    NSBox *_modeBox;
    NSMutableArray<NSButton *> *_actionButtons;
    TPFindTab _tab;
    NSString *_statusText;
}

- (instancetype)initWithController:(TPMainWindowController *)c {
    NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 600, 345)
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow
                                              backing:NSBackingStoreBuffered defer:YES];
    if ((self = [super initWithWindow:p])) {
        _c = c;
        p.title = @"Find";
        p.floatingPanel = YES;
        p.hidesOnDeactivate = YES;
        p.becomesKeyOnlyIfNeeded = NO;
        p.delegate = self;
        _filters = @"*.*";
        _directory = NSHomeDirectory();
        // fields are created in -build; initial values applied after
        _recursive = YES;
        _statusText = @"";
        [self build];
        _filtersField.stringValue = _filters;
        _dirField.stringValue = _directory;
        [self layoutForTab:TPFindTabFind];
    }
    return self;
}

- (NSButton *)check:(NSString *)t at:(NSPoint)pt {
    NSButton *b = [NSButton checkboxWithTitle:t target:self action:@selector(optionsChanged:)];
    [b setFrameOrigin:pt];
    [b sizeToFit];
    [self.window.contentView addSubview:b];
    return b;
}

- (NSTextField *)label:(NSString *)t frame:(NSRect)r {
    NSTextField *l = [NSTextField labelWithString:t];
    l.frame = r;
    l.alignment = NSTextAlignmentRight;
    [self.window.contentView addSubview:l];
    return l;
}

- (void)build {
    NSView *cv = self.window.contentView;
    // AppKit coordinates (origin bottom-left); dialog height 345
    _tabs = [NSSegmentedControl segmentedControlWithLabels:@[@"Find", @"Replace", @"Find in Files", @"Find in Projects", @"Mark"]
                                              trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(tabChanged:)];
    _tabs.frame = NSMakeRect(12, 310, 470, 24);
    [cv addSubview:_tabs];

    _findLabel = [self label:@"Find what :" frame:NSMakeRect(8, 272, 100, 18)];
    _findCombo = [[NSComboBox alloc] initWithFrame:NSMakeRect(112, 268, 312, 26)];
    _findCombo.completes = NO;
    _findCombo.delegate = (id<NSComboBoxDelegate>)self;
    // upstream IDC_HIGHLIGHT_MODE: highlight every match of "Find what" while the dialog is open
    _highlightCheck = [NSButton checkboxWithTitle:@"" target:self action:@selector(highlightModeChanged:)];
    _highlightCheck.frame = NSMakeRect(428, 272, 20, 18);
    _highlightCheck.toolTip = @"Highlight all matches of the current search in the active document while typing";
    _highlightCheck.accessibilityLabel = @"Highlight all matches";
    _highlightCheck.state = [[NSUserDefaults standardUserDefaults] boolForKey:@"find.highlightMatches"];
    [cv addSubview:_highlightCheck];
    [cv addSubview:_findCombo];
    _replaceLabel = [self label:@"Replace with :" frame:NSMakeRect(8, 240, 100, 18)];
    _replaceCombo = [[NSComboBox alloc] initWithFrame:NSMakeRect(112, 236, 330, 26)];
    [cv addSubview:_replaceCombo];
    _filtersLabel = [self label:@"Filters :" frame:NSMakeRect(8, 208, 100, 18)];
    _filtersField = [[NSTextField alloc] initWithFrame:NSMakeRect(112, 205, 220, 24)];
    [cv addSubview:_filtersField];
    _dirLabel = [self label:@"Directory :" frame:NSMakeRect(8, 177, 100, 18)];
    _dirField = [[NSTextField alloc] initWithFrame:NSMakeRect(112, 174, 300, 24)];
    [cv addSubview:_dirField];
    _dirBrowse = [NSButton buttonWithTitle:@"..." target:self action:@selector(browseDir:)];
    _dirBrowse.frame = NSMakeRect(414, 172, 30, 28);
    [cv addSubview:_dirBrowse];
    _followDoc = [self check:@"Follow current doc." at:NSMakePoint(336, 206)];
    _subFolders = [self check:@"In all sub-folders" at:NSMakePoint(112, 150)];
    _hiddenCheck = [self check:@"In hidden folders" at:NSMakePoint(260, 150)];
    _subFolders.state = NSControlStateValueOn;
    _proj1 = [self check:@"Project Panel 1" at:NSMakePoint(112, 208)];
    _proj2 = [self check:@"Project Panel 2" at:NSMakePoint(112, 186)];
    _proj3 = [self check:@"Project Panel 3" at:NSMakePoint(112, 164)];

    _bookmarkLine = [self check:@"Bookmark line" at:NSMakePoint(16, 205)];
    _purge = [self check:@"Purge for each search" at:NSMakePoint(16, 183)];
    _inSelection = [self check:@"In selection" at:NSMakePoint(330, 205)];

    _backward = [self check:@"Backward direction" at:NSMakePoint(16, 118)];
    _wholeWord = [self check:@"Match whole word only" at:NSMakePoint(16, 96)];
    _matchCase = [self check:@"Match case" at:NSMakePoint(16, 74)];
    _wrap = [self check:@"Wrap around" at:NSMakePoint(16, 52)];
    _wrap.state = NSControlStateValueOn;

    _modeBox = [[NSBox alloc] initWithFrame:NSMakeRect(200, 30, 245, 112)];
    _modeBox.title = @"Search Mode";
    [cv addSubview:_modeBox];
    NSView *mb = _modeBox.contentView;
    _modeNormal = [NSButton radioButtonWithTitle:@"Normal" target:self action:@selector(modeChanged:)];
    _modeNormal.frame = NSMakeRect(6, 66, 220, 18);
    _modeExtended = [NSButton radioButtonWithTitle:@"Extended (\\n, \\r, \\t, \\0, \\x...)" target:self action:@selector(modeChanged:)];
    _modeExtended.frame = NSMakeRect(6, 44, 230, 18);
    _modeRegex = [NSButton radioButtonWithTitle:@"Regular expression" target:self action:@selector(modeChanged:)];
    _modeRegex.frame = NSMakeRect(6, 22, 150, 18);
    _dotNewline = [NSButton checkboxWithTitle:@". matches newline" target:nil action:nil];
    _dotNewline.frame = NSMakeRect(24, 2, 160, 18);
    for (NSView *v in @[_modeNormal, _modeExtended, _modeRegex, _dotNewline]) [mb addSubview:v];
    _modeNormal.state = NSControlStateValueOn;
    _dotNewline.enabled = NO;

    // upstream Transparency: check box, "On losing focus" / "Always", slider
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    _transCheck = [NSButton checkboxWithTitle:@"Transparency" target:self action:@selector(transparencyChanged:)];
    _transCheck.frame = NSMakeRect(452, 104, 140, 18);
    _transLossFocus = [NSButton radioButtonWithTitle:@"On losing focus" target:self action:@selector(transparencyChanged:)];
    _transLossFocus.frame = NSMakeRect(466, 84, 130, 18);
    _transAlways = [NSButton radioButtonWithTitle:@"Always" target:self action:@selector(transparencyChanged:)];
    _transAlways.frame = NSMakeRect(466, 64, 130, 18);
    _transSlider = [NSSlider sliderWithValue:[ud objectForKey:@"find.transparency"] ? [ud integerForKey:@"find.transparency"] : 150
                                    minValue:20 maxValue:225 target:self action:@selector(transparencyChanged:)];
    _transSlider.frame = NSMakeRect(466, 40, 120, 20);
    for (NSView *v in @[_transCheck, _transLossFocus, _transAlways, _transSlider]) [cv addSubview:v];
    NSInteger tm = [ud integerForKey:@"find.transparencyMode"];   // 0 none, 1 on losing focus, 2 always
    _transCheck.state = tm != 0;
    _transLossFocus.state = tm != 2; _transAlways.state = tm == 2;
    [self applyTransparencyActive:YES];

    _status = [NSTextField labelWithString:@""];
    _status.frame = NSMakeRect(12, 6, 576, 18);
    _status.font = [NSFont systemFontOfSize:11.5];
    [cv addSubview:_status];
    _actionButtons = [NSMutableArray array];
}

- (void)setActionButtons:(NSArray<NSArray *> *)defs {
    for (NSButton *b in _actionButtons) [b removeFromSuperview];
    [_actionButtons removeAllObjects];
    CGFloat y = 268;
    for (NSArray *d in defs) {
        NSButton *b = [NSButton buttonWithTitle:d[0] target:self action:NSSelectorFromString(d[1])];
        b.frame = NSMakeRect(452, y, 140, 28);
        b.font = [NSFont systemFontOfSize:12];
        [self.window.contentView addSubview:b];
        [_actionButtons addObject:b];
        y -= 32;
    }
    if (_actionButtons.count) self.window.defaultButtonCell = _actionButtons.firstObject.cell;
}

- (void)layoutForTab:(TPFindTab)tab {
    _tab = tab;
    _tabs.selectedSegment = tab;
    BOOL fip = tab == TPFindTabFindInProjects;
    BOOL rep = tab == TPFindTabReplace || tab == TPFindTabFindInFiles || fip;
    BOOL fif = tab == TPFindTabFindInFiles;
    _proj1.hidden = _proj2.hidden = _proj3.hidden = !fip;
    BOOL mark = tab == TPFindTabMark;
    _replaceLabel.hidden = _replaceCombo.hidden = !rep;
    _filtersLabel.hidden = _filtersField.hidden = _dirLabel.hidden = _dirField.hidden = _dirBrowse.hidden = !fif;
    _followDoc.hidden = _subFolders.hidden = _hiddenCheck.hidden = !fif;
    _bookmarkLine.hidden = _purge.hidden = !mark;
    _inSelection.hidden = fif || fip;
    _backward.hidden = fif || fip || mark;
    _wrap.hidden = fif || fip || mark;
    NSArray *titles = @[@"Find", @"Replace", @"Find in Files", @"Find in Projects", @"Mark"];
    self.window.title = titles[tab];
    switch (tab) {
        case TPFindTabFind:
            [self setActionButtons:@[@[@"Find Next", @"actFindNext:"], @[@"Count", @"actCount:"],
                                     @[@"Find All in All Opened Documents", @"actFindAllOpened:"],
                                     @[@"Find All in Current Document", @"actFindAllCurrent:"], @[@"Close", @"actClose:"]]];
            break;
        case TPFindTabReplace:
            [self setActionButtons:@[@[@"Find Next", @"actFindNext:"], @[@"Replace", @"actReplace:"], @[@"Replace All", @"actReplaceAll:"],
                                     @[@"Replace All in All Opened Documents", @"actReplaceAllOpened:"], @[@"Close", @"actClose:"]]];
            break;
        case TPFindTabFindInFiles:
            [self setActionButtons:@[@[@"Find All", @"actFindInFiles:"], @[@"Replace in Files", @"actReplaceInFiles:"], @[@"Close", @"actClose:"]]];
            if (!_filtersField.stringValue.length) _filtersField.stringValue = _filters;
            if (!_dirField.stringValue.length) _dirField.stringValue = _directory;
            break;
        case TPFindTabFindInProjects:
            [self setActionButtons:@[@[@"Find All", @"actFindInFiles:"], @[@"Replace in Projects", @"actReplaceInFiles:"], @[@"Close", @"actClose:"]]];
            break;
        case TPFindTabMark:
            [self setActionButtons:@[@[@"Mark All", @"actMarkAll:"], @[@"Clear all marks", @"actClearMarks:"],
                                     @[@"Copy Marked Text", @"actCopyMarked:"], @[@"Close", @"actClose:"]]];
            break;
    }
    // long button titles: shrink font so they fit like upstream's two-line buttons
    for (NSButton *b in _actionButtons) if (b.title.length > 18) b.font = [NSFont systemFontOfSize:9.5];
}

- (void)tabChanged:(id)sender { [self layoutForTab:static_cast<TPFindTab>(_tabs.selectedSegment)]; [self updateMatchHighlighting]; }

// ---------------------------------------------------------------- live highlighting (upstream updateMatchHighlighting)
- (BOOL)highlightMatches { return _highlightCheck.state == NSControlStateValueOn; }
- (void)setHighlightMatches:(BOOL)v { _highlightCheck.state = v; [self highlightModeChanged:nil]; }
- (void)highlightModeChanged:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:self.highlightMatches forKey:@"find.highlightMatches"];
    [self updateMatchHighlighting];
}
- (void)optionsChanged:(id)sender { [self modeChanged:nil]; [self updateMatchHighlighting]; }
- (void)controlTextDidChange:(NSNotification *)n { if (n.object == _findCombo) [self updateMatchHighlighting]; }
- (void)comboBoxSelectionDidChange:(NSNotification *)n { dispatch_async(dispatch_get_main_queue(), ^{ [self updateMatchHighlighting]; }); }

- (void)clearMatchHighlighting {
    for (ScintillaView *v in @[_c.mainPane.editor, _c.subPane.editor]) {
        SCI(v, SCI_SETINDICATORCURRENT, TPP_INDIC_FINDDLG);
        SCI(v, SCI_INDICATORCLEARRANGE, 0, SCI(v, SCI_GETLENGTH));
    }
}

// while the dialog shows the Find or Replace tab: every match of "Find what" in the visible lines and one screen
// below, with the dialog's options; follows scrolling (cost independent of the document size)
- (void)updateMatchHighlighting {
    [self clearMatchHighlighting];
    if (!self.highlightMatches || !self.window.isVisible) return;
    if (_tab != TPFindTabFind && _tab != TPFindTabReplace) return;
    if ([_c isLargeDocument:_c.currentDocument] && ![TPPrefs b:@"pref.largeFileSmartHL"]) return;
    Options o = [self currentOptions];
    o.inSelection = NO;
    if (o.find.empty()) return;
    ScintillaView *v = _c.editor;
    sptr_t first = SCI(v, SCI_DOCLINEFROMVISIBLE, SCI(v, SCI_GETFIRSTVISIBLELINE));
    sptr_t screen = SCI(v, SCI_LINESONSCREEN);
    sptr_t last = SCI(v, SCI_DOCLINEFROMVISIBLE, SCI(v, SCI_GETFIRSTVISIBLELINE) + 2 * screen);
    sptr_t from = SCI(v, SCI_POSITIONFROMLINE, first);
    sptr_t to = last + 1 < SCI(v, SCI_GETLINECOUNT) ? SCI(v, SCI_POSITIONFROMLINE, last + 1) : SCI(v, SCI_GETLENGTH);
    std::vector<Match> m;
    if (!findAll(v, o, from, to, m)) return;
    SCI(v, SCI_SETINDICATORCURRENT, TPP_INDIC_FINDDLG);
    for (const Match &x : m) if (x.end > x.start) SCI(v, SCI_INDICATORFILLRANGE, x.start, x.end - x.start);
}

// ---------------------------------------------------------------- transparency (upstream FindReplaceDlg)
- (void)transparencyChanged:(id)sender {
    if (sender == _transLossFocus) _transAlways.state = NSControlStateValueOff;
    if (sender == _transAlways) _transLossFocus.state = NSControlStateValueOff;
    NSInteger mode = !_transCheck.state ? 0 : _transAlways.state ? 2 : 1;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setInteger:mode forKey:@"find.transparencyMode"];
    [ud setInteger:_transSlider.integerValue forKey:@"find.transparency"];
    _transLossFocus.enabled = _transAlways.enabled = _transSlider.enabled = mode != 0;
    [self applyTransparencyActive:self.window.isKeyWindow];
}
- (NSInteger)transparencyMode { return [[NSUserDefaults standardUserDefaults] integerForKey:@"find.transparencyMode"]; }
- (void)setTransparencyMode:(NSInteger)m {
    _transCheck.state = m != 0;
    _transAlways.state = m == 2; _transLossFocus.state = m == 1;
    [self transparencyChanged:nil];
}
- (void)applyTransparencyActive:(BOOL)active {
    NSInteger mode = [[NSUserDefaults standardUserDefaults] integerForKey:@"find.transparencyMode"];
    if (self.window.alphaValue == 0) return;   // hidden test window
    CGFloat a = _transSlider.doubleValue / 255.0;
    self.window.alphaValue = (mode == 2 || (mode == 1 && !active)) ? a : 1.0;
}
- (void)windowDidBecomeKey:(NSNotification *)n { [self applyTransparencyActive:YES]; [self updateMatchHighlighting]; }
- (void)windowDidResignKey:(NSNotification *)n { [self applyTransparencyActive:NO]; }
- (void)windowWillClose:(NSNotification *)n { [self clearMatchHighlighting]; }

- (void)modeChanged:(id)sender {
    BOOL regex = _modeRegex.state == NSControlStateValueOn;
    _dotNewline.enabled = regex;
    _wholeWord.enabled = !regex;   // upstream disables whole word in regex mode
}

- (void)browseDir:(id)sender {
    NSOpenPanel *op = [NSOpenPanel openPanel];
    op.canChooseDirectories = YES;
    op.canChooseFiles = NO;
    if ([op runModal] == NSModalResponseOK) _dirField.stringValue = op.URL.path;
}

- (void)showTab:(TPFindTab)tab {
    TPDocument *d = _c.currentDocument;
    ScintillaView *v = _c.editor;
    // Preferences > Searching > When Find Dialog is Invoked
    sptr_t selLen = SCI(v, SCI_GETSELECTIONEND) - SCI(v, SCI_GETSELECTIONSTART);
    if ([TPPrefs b:@"pref.fillFindWithSelection"]) {
        if (selLen == 0 && [TPPrefs b:@"pref.selectWordUnderCaret"]) {
            sptr_t pos = SCI(v, SCI_GETCURRENTPOS);
            sptr_t ws = SCI(v, SCI_WORDSTARTPOSITION, pos, 1), we = SCI(v, SCI_WORDENDPOSITION, pos, 1);
            if (we > ws) { SCI(v, SCI_SETSEL, ws, we); selLen = we - ws; }
        }
        std::string sel = sciSelectedText(v);
        NSString *ns = NSStr(sel);
        if (!sel.empty() && sel.find('\n') == std::string::npos && sel.find('\r') == std::string::npos &&
            (NSInteger)ns.length <= MAX(1, [TPPrefs i:@"pref.fillFindMaxChars"]))
            _findCombo.stringValue = ns;
    }
    NSInteger threshold = [TPPrefs i:@"pref.inSelThreshold"];
    _inSelection.state = (threshold > 0 && selLen >= threshold) ? NSControlStateValueOn : NSControlStateValueOff;
    NSFont *f = [TPPrefs b:@"pref.findMonospace"] ? [NSFont userFixedPitchFontOfSize:13] : [NSFont systemFontOfSize:13];
    _findCombo.font = f;
    _replaceCombo.font = f;
    if (tab == TPFindTabFindInFiles && (_followDoc.state == NSControlStateValueOn || [TPPrefs b:@"pref.fifDirFromActive"]) && d.path)
        self.directory = d.path.stringByDeletingLastPathComponent;
    [self layoutForTab:tab];
    if (!self.window.isVisible) [self.window center];
    [self showWindow:nil];
    [self updateMatchHighlighting];
    [self.window makeFirstResponder:_findCombo];
}

- (void)setFilters:(NSString *)filters {
    _filters = [filters copy];
    _filtersField.stringValue = _filters ?: @"";
}

- (void)setDirectory:(NSString *)directory {
    _directory = [directory copy];
    _dirField.stringValue = _directory ?: @"";
}

- (void)setFindText:(NSString *)text { _findCombo.stringValue = text ?: @""; }
- (void)setReplaceText:(NSString *)text { _replaceCombo.stringValue = text ?: @""; }
- (NSString *)statusText { return _statusText; }

- (void)setOptions:(const Options &)o {
    _findCombo.stringValue = NSStr(o.find);
    _replaceCombo.stringValue = NSStr(o.replace);
    _modeNormal.state = o.mode == Mode::Normal; _modeExtended.state = o.mode == Mode::Extended; _modeRegex.state = o.mode == Mode::Regex;
    _matchCase.state = o.matchCase; _wholeWord.state = o.wholeWord; _wrap.state = o.wrap; _backward.state = o.backward;
    _inSelection.state = o.inSelection; _dotNewline.state = o.dotMatchesNewline;
    _bookmarkLine.state = o.bookmarkLine; _purge.state = o.purge;
    [self modeChanged:nil];
}

- (Options)currentOptions {
    Options o;
    o.find = StdStr(_findCombo.stringValue);
    o.replace = StdStr(_replaceCombo.stringValue);
    o.mode = _modeRegex.state == NSControlStateValueOn ? Mode::Regex : (_modeExtended.state == NSControlStateValueOn ? Mode::Extended : Mode::Normal);
    o.matchCase = _matchCase.state == NSControlStateValueOn;
    o.wholeWord = _wholeWord.state == NSControlStateValueOn && o.mode != Mode::Regex;
    o.wrap = _wrap.state == NSControlStateValueOn;
    o.backward = _backward.state == NSControlStateValueOn;
    o.inSelection = _inSelection.state == NSControlStateValueOn && !_inSelection.hidden;
    o.dotMatchesNewline = _dotNewline.state == NSControlStateValueOn;
    o.bookmarkLine = _bookmarkLine.state == NSControlStateValueOn;
    o.purge = _purge.state == NSControlStateValueOn;
    return o;
}

- (void)remember {
    for (NSComboBox *cb in @[_findCombo, _replaceCombo]) {
        NSString *s = cb.stringValue;
        if (!s.length) continue;
        NSUInteger i = [cb indexOfItemWithObjectValue:s];
        if (i != NSNotFound) [cb removeItemAtIndex:i];
        [cb insertItemWithObjectValue:s atIndex:0];
        while (cb.numberOfItems > 10) [cb removeItemAtIndex:cb.numberOfItems - 1];
    }
}

// status colours from stylers.model.xml "Find status: ..." (red / blue / green)
- (void)setStatus:(NSString *)s kind:(int)kind {
    _statusText = s ?: @"";
    _status.stringValue = _statusText;
    _status.textColor = kind == 0 ? [NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1]
                      : kind == 1 ? [NSColor colorWithSRGBRed:0 green:0 blue:1 alpha:1]
                                  : [NSColor colorWithSRGBRed:0 green:0.5 blue:0 alpha:1];
}

- (BOOL)checkPrepared:(const Options &)o name:(NSString *)name {
    Prepared p = prepare(o);
    if (!p.ok) {
        [self setStatus:[NSString stringWithFormat:@"%@: %@", name, p.error.empty() ? @"Empty search text" : NSStr(p.error)] kind:0];
        return NO;
    }
    return YES;
}

- (void)selectionRange:(const Options &)o view:(ScintillaView *)v from:(sptr_t *)from to:(sptr_t *)to {
    if (o.inSelection && SCI(v, SCI_GETSELECTIONEMPTY) == 0) {
        *from = SCI(v, SCI_GETSELECTIONSTART);
        *to = SCI(v, SCI_GETSELECTIONEND);
    } else {
        *from = 0;
        *to = SCI(v, SCI_GETLENGTH);
    }
}

// ---------------------------------------------------------------- actions
- (BOOL)findNext:(BOOL)forward {
    Options o = [self currentOptions];
    if (!forward) o.backward = !o.backward;
    if (![self checkPrepared:o name:@"Find"]) return NO;
    [self remember];
    FindResult r = tpp::search::findNext(_c.editor, o);
    if (r.regexError) { [self setStatus:[@"Find: Invalid regular expression — " stringByAppendingString:NSStr(r.error)] kind:0]; return NO; }
    if (!r.found) {
        [self setStatus:[NSString stringWithFormat:@"Find: Can't find the text \"%@\"", NSStr(o.find)] kind:0];
        TPBeep();
        return NO;
    }
    if (r.wrapped) [self setStatus:o.backward ? @"Find: Found the 1st occurrence from the bottom. The beginning of the document has been reached."
                                              : @"Find: Found the 1st occurrence from the top. The end of the document has been reached." kind:2];
    else [self setStatus:@"" kind:1];
    return YES;
}

- (long)count {
    Options o = [self currentOptions];
    if (![self checkPrepared:o name:@"Count"]) return 0;
    [self remember];
    sptr_t from, to;
    [self selectionRange:o view:_c.editor from:&from to:&to];
    std::vector<Match> m;
    std::string err;
    if (!findAll(_c.editor, o, from, to, m, &err)) { [self setStatus:[@"Count: Invalid regular expression — " stringByAppendingString:NSStr(err)] kind:0]; return -1; }
    [self setStatus:[NSString stringWithFormat:@"Count: %zu match%@.", m.size(), m.size() == 1 ? @"" : @"es"] kind:1];
    return static_cast<long>(m.size());
}

- (BOOL)replaceOne {
    Options o = [self currentOptions];
    if (![self checkPrepared:o name:@"Replace"]) return NO;
    if (_c.currentDocument.userReadOnly) { [self setStatus:@"Replace: Cannot replace text. The current document is read only." kind:0]; return NO; }
    [self remember];
    ReplaceResult rr = tpp::search::replaceOne(_c.editor, o);
    if (rr.next.regexError) { [self setStatus:[@"Replace: Invalid regular expression — " stringByAppendingString:NSStr(rr.next.error)] kind:0]; return NO; }
    if (rr.replaced) [self setStatus:rr.next.found ? @"Replace: 1 occurrence was replaced. The next occurrence found." : @"Replace: 1 occurrence was replaced. No more occurrences were found." kind:rr.next.found ? 1 : 2];
    else [self setStatus:rr.next.found ? @"" : [NSString stringWithFormat:@"Replace: Can't find the text \"%@\"", NSStr(o.find)] kind:rr.next.found ? 1 : 0];
    return rr.replaced;
}

- (long)replaceAllInCurrent {
    Options o = [self currentOptions];
    if (![self checkPrepared:o name:@"Replace All"]) return 0;
    if (_c.currentDocument.userReadOnly) { [self setStatus:@"Replace All: Cannot replace text. The current document is read only." kind:0]; return 0; }
    [self remember];
    sptr_t from, to;
    [self selectionRange:o view:_c.editor from:&from to:&to];
    std::string err;
    long n = tpp::search::replaceAll(_c.editor, o, from, to, &err);
    if (n < 0) { [self setStatus:[@"Replace All: Invalid regular expression — " stringByAppendingString:NSStr(err)] kind:0]; return -1; }
    [self setStatus:[NSString stringWithFormat:@"Replace All: %ld occurrence%@ replaced in %@.", n, n == 1 ? @" was" : @"s were",
                     o.inSelection ? @"selected text" : @"entire file"] kind:n ? 1 : 0];
    return n;
}

- (long)replaceAllInAllOpened {
    Options o = [self currentOptions];
    if (![self checkPrepared:o name:@"Replace All"]) return 0;
    [self remember];
    o.inSelection = NO;
    long total = 0;
    for (TPDocument *d in _c.allDocuments) {
        if (d.userReadOnly) continue;
        __block long n = 0;
        [_c withDocument:d perform:^(ScintillaView *v) { n = tpp::search::replaceAll(v, o, 0, -1, nullptr); }];
        if (n > 0) total += n;
    }
    [_c refreshUI];
    [self setStatus:[NSString stringWithFormat:@"Replace in Opened Files: %ld occurrence%@ replaced.", total, total == 1 ? @" was" : @"s were"] kind:1];
    return total;
}

- (long)markAll {
    Options o = [self currentOptions];
    if (![self checkPrepared:o name:@"Mark"]) return 0;
    [self remember];
    ScintillaView *v = _c.editor;
    if (o.purge) [self clearMarks];
    sptr_t from, to;
    [self selectionRange:o view:v from:&from to:&to];
    std::string err;
    long n = tpp::search::markAll(v, o, TPP_INDIC_FOUND, from, to, &err);
    if (n < 0) { [self setStatus:[@"Mark: Invalid regular expression — " stringByAppendingString:NSStr(err)] kind:0]; return -1; }
    [self setStatus:[NSString stringWithFormat:@"Mark: %ld match%@.", n, n == 1 ? @"" : @"es"] kind:n ? 1 : 0];
    return n;
}

- (void)clearMarks {
    ScintillaView *v = _c.editor;
    SCI(v, SCI_SETINDICATORCURRENT, TPP_INDIC_FOUND);
    SCI(v, SCI_INDICATORCLEARRANGE, 0, SCI(v, SCI_GETLENGTH));
    [self setStatus:@"" kind:1];
}

- (void)copyMarkedText {
    ScintillaView *v = _c.editor;
    std::string out;
    sptr_t len = SCI(v, SCI_GETLENGTH);
    sptr_t pos = 0;
    while (pos < len) {
        sptr_t s = SCI(v, SCI_INDICATOREND, TPP_INDIC_FOUND, pos);
        if (SCI(v, SCI_INDICATORVALUEAT, TPP_INDIC_FOUND, pos) != 0) s = pos;
        if (s >= len || s < pos) break;
        sptr_t e = SCI(v, SCI_INDICATOREND, TPP_INDIC_FOUND, s);
        if (e <= s) break;
        if (SCI(v, SCI_INDICATORVALUEAT, TPP_INDIC_FOUND, s) != 0) {
            if (!out.empty()) out += sciEolString(v);
            out += sciGetRange(v, s, e);
        }
        pos = e;
    }
    if (out.empty()) return;
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:NSStr(out) forType:NSPasteboardTypeString];
}

- (void)collectHits:(ScintillaView *)v doc:(TPDocument *)d options:(const Options &)o from:(sptr_t)from to:(sptr_t)to into:(std::vector<TPResultHit> &)hits error:(std::string *)err {
    std::vector<Match> m;
    if (!findAll(v, o, from, to, m, err)) return;
    for (const Match &x : m) {
        TPResultHit h;
        h.fileLabel = d.path ? StdStr(d.path) : StdStr(d.displayName);
        h.path = d.path ? StdStr(d.path) : "";
        h.docUid = d.uid;
        h.line = x.line;
        sptr_t ls = SCI(v, SCI_POSITIONFROMLINE, x.line);
        h.start = x.start - ls;
        h.end = MIN(x.end, SCI(v, SCI_GETLINEENDPOSITION, x.line)) - ls;
        h.lineText = sciGetLine(v, x.line);
        hits.push_back(h);
    }
}

- (long)findAllInCurrent {
    Options o = [self currentOptions];
    if (![self checkPrepared:o name:@"Find"]) return 0;
    [self remember];
    std::vector<TPResultHit> hits;
    std::string err;
    sptr_t from, to;
    [self selectionRange:o view:_c.editor from:&from to:&to];
    [self collectHits:_c.editor doc:_c.currentDocument options:o from:from to:to into:hits error:&err];
    if (!err.empty()) { [self setStatus:[@"Find: Invalid regular expression — " stringByAppendingString:NSStr(err)] kind:0]; return -1; }
    [_c.resultsPanel addSearch:_findCombo.stringValue hits:hits filesSearched:1];
    if (![TPPrefs b:@"pref.findDlgStaysOpen"]) [self.window orderOut:nil];
    [self setStatus:[NSString stringWithFormat:@"Find All in Current Document: %zu hit%@", hits.size(), hits.size() == 1 ? @"" : @"s"] kind:1];
    return static_cast<long>(hits.size());
}

- (long)findAllInAllOpened {
    Options o = [self currentOptions];
    if (![self checkPrepared:o name:@"Find"]) return 0;
    [self remember];
    o.inSelection = NO;
    __block std::vector<TPResultHit> hits;
    NSArray *docs = _c.allDocuments;
    __block std::string err;
    for (TPDocument *d in docs) {
        [_c withDocument:d perform:^(ScintillaView *v) { [self collectHits:v doc:d options:o from:0 to:-1 into:hits error:&err]; }];
        if (!err.empty()) break;
    }
    if (!err.empty()) { [self setStatus:[@"Find: Invalid regular expression — " stringByAppendingString:NSStr(err)] kind:0]; return -1; }
    [_c.resultsPanel addSearch:_findCombo.stringValue hits:hits filesSearched:(NSInteger)docs.count];
    if (![TPPrefs b:@"pref.findDlgStaysOpen"]) [self.window orderOut:nil];
    return static_cast<long>(hits.size());
}

// ---------------------------------------------------------------- Find in Files
static BOOL matchesFilters(NSString *name, NSArray<NSString *> *include, NSArray<NSString *> *exclude) {
    const char *n = name.fileSystemRepresentation;
    for (NSString *e in exclude) if (fnmatch(e.UTF8String, n, FNM_CASEFOLD) == 0) return NO;
    if (!include.count) return YES;
    for (NSString *i in include) {
        if ([i isEqualToString:@"*.*"] || [i isEqualToString:@"*"]) return YES;
        if (fnmatch(i.UTF8String, n, FNM_CASEFOLD) == 0) return YES;
    }
    return NO;
}

- (NSArray<NSString *> *)collectFiles {
    NSString *dir = _dirField.stringValue.length ? _dirField.stringValue.stringByExpandingTildeInPath : _directory;
    _directory = dir;
    _filters = _filtersField.stringValue.length ? _filtersField.stringValue : @"*.*";
    NSMutableArray *include = [NSMutableArray array], *exclude = [NSMutableArray array], *excludeDirs = [NSMutableArray array];
    for (NSString *tok in [_filters componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" ;"]]) {
        if (!tok.length) continue;
        if ([tok hasPrefix:@"!+\\"] || [tok hasPrefix:@"!\\"]) [excludeDirs addObject:[tok substringFromIndex:[tok rangeOfString:@"\\"].location + 1]];
        else if ([tok hasPrefix:@"!"]) [exclude addObject:[tok substringFromIndex:1]];
        else [include addObject:tok];
    }
    BOOL recursive = _subFolders.state == NSControlStateValueOn;
    BOOL hidden = _hiddenCheck.state == NSControlStateValueOn;
    NSMutableArray *files = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerationOptions opts = hidden ? 0 : NSDirectoryEnumerationSkipsHiddenFiles;
    if (!recursive) opts |= NSDirectoryEnumerationSkipsSubdirectoryDescendants;
    NSDirectoryEnumerator *en = [fm enumeratorAtURL:[NSURL fileURLWithPath:dir] includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLIsDirectoryKey]
                                            options:opts errorHandler:^BOOL(NSURL *u, NSError *e) { return YES; }];
    for (NSURL *u in en) {
        NSNumber *isDir = nil, *isReg = nil;
        [u getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if (isDir.boolValue) {
            for (NSString *x in excludeDirs) if (fnmatch(x.UTF8String, u.lastPathComponent.fileSystemRepresentation, FNM_CASEFOLD) == 0) [en skipDescendants];
            continue;
        }
        [u getResourceValue:&isReg forKey:NSURLIsRegularFileKey error:nil];
        if (!isReg.boolValue) continue;
        if (matchesFilters(u.lastPathComponent, include, exclude)) [files addObject:u.path];
    }
    return files;
}

// Runs a block on a file's text: if the file is open, on its buffer (unsaved edits included, as upstream);
// otherwise on a temporary Scintilla document loaded in the hidden worker view.
- (void)onFile:(NSString *)path perform:(void (^)(ScintillaView *v, TPDocument *_Nullable openDoc, tpp::TextEncoding enc))block {
    TPDocument *open = [TPPrefs b:@"pref.fifPreferDisk"] ? nil : [_c documentForPath:path];
    if (open) { [_c withDocument:open perform:^(ScintillaView *v) { block(v, open, open.encoding); }]; return; }
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data || data.length > 512ull * 1024 * 1024) return;
    std::string bytes(static_cast<const char *>(data.bytes), data.length);
    tpp::DecodeResult dr = tpp::detectAndDecode(bytes, true, [TPPrefs b:@"pref.detectEncoding"]);
    if (dr.containsNul && dr.encoding.mode == tpp::UniMode::Ansi) return;  // skip binaries (upstream skips them too)
    ScintillaView *w = _c.worker;
    sptr_t prev = SCI(w, SCI_GETDOCPOINTER);
    SCI(w, SCI_ADDREFDOCUMENT, 0, prev);
    sptr_t tmp = SCI(w, SCI_CREATEDOCUMENT, dr.utf8.size() + 16, SC_DOCUMENTOPTION_DEFAULT);
    SCI(w, SCI_SETDOCPOINTER, 0, tmp);
    SCI(w, SCI_SETCODEPAGE, SC_CP_UTF8);
    SCI(w, SCI_SETUNDOCOLLECTION, 0);
    if (!dr.utf8.empty()) SCI(w, SCI_APPENDTEXT, dr.utf8.size(), reinterpret_cast<sptr_t>(dr.utf8.data()));
    SCI(w, SCI_SETUNDOCOLLECTION, 1);
    SCI(w, SCI_SETSAVEPOINT);
    block(w, nil, dr.encoding);
    SCI(w, SCI_SETDOCPOINTER, 0, prev);
    SCI(w, SCI_RELEASEDOCUMENT, 0, prev);
    SCI(w, SCI_RELEASEDOCUMENT, 0, tmp);
}

// Find in Files: the directory scan; Find in Projects: the files of the checked Project Panels
- (NSArray<NSString *> *)searchFiles {
    if (_tab != TPFindTabFindInProjects) return [self collectFiles];
    NSMutableArray *panels = [NSMutableArray array];
    if (_proj1.state) [panels addObject:@1];
    if (_proj2.state) [panels addObject:@2];
    if (_proj3.state) [panels addObject:@3];
    NSArray *files = _projectFilesProvider ? _projectFilesProvider(panels) : @[];
    NSMutableArray *existing = [NSMutableArray array];
    for (NSString *f in files) if ([[NSFileManager defaultManager] fileExistsAtPath:f] && ![existing containsObject:f]) [existing addObject:f];
    return existing;
}
- (BOOL)project1 { return _proj1.state == NSControlStateValueOn; }
- (void)setProject1:(BOOL)v { _proj1.state = v; }
- (BOOL)project2 { return _proj2.state == NSControlStateValueOn; }
- (void)setProject2:(BOOL)v { _proj2.state = v; }
- (BOOL)project3 { return _proj3.state == NSControlStateValueOn; }
- (void)setProject3:(BOOL)v { _proj3.state = v; }
- (TPFindTab)currentTab { return _tab; }

- (long)findInFiles {
    Options o = [self currentOptions];
    o.inSelection = NO;
    if (![self checkPrepared:o name:_tab == TPFindTabFindInProjects ? @"Find in Projects" : @"Find in Files"]) return 0;
    [self remember];
    NSArray *files = [self searchFiles];
    __block std::vector<TPResultHit> hits;
    __block std::string err;
    for (NSString *f in files) {
        [self onFile:f perform:^(ScintillaView *v, TPDocument *openDoc, tpp::TextEncoding enc) {
            std::vector<Match> m;
            if (!findAll(v, o, 0, -1, m, &err)) return;
            for (const Match &x : m) {
                TPResultHit h;
                h.fileLabel = StdStr(f);
                h.path = StdStr(f);
                h.docUid = openDoc ? openDoc.uid : 0;
                h.line = x.line;
                sptr_t ls = SCI(v, SCI_POSITIONFROMLINE, x.line);
                h.start = x.start - ls;
                h.end = MIN(x.end, SCI(v, SCI_GETLINEENDPOSITION, x.line)) - ls;
                h.lineText = sciGetLine(v, x.line);
                hits.push_back(h);
            }
        }];
        if (!err.empty()) break;
    }
    if (!err.empty()) { [self setStatus:[@"Find in Files: Invalid regular expression — " stringByAppendingString:NSStr(err)] kind:0]; return -1; }
    [_c.resultsPanel addSearch:_findCombo.stringValue hits:hits filesSearched:(NSInteger)files.count];
    if (![TPPrefs b:@"pref.findDlgStaysOpen"]) [self.window orderOut:nil];
    [self setStatus:[NSString stringWithFormat:@"Find in Files: %zu hits in %lu files searched.", hits.size(), (unsigned long)files.count] kind:1];
    return static_cast<long>(hits.size());
}

- (long)replaceInFiles {
    Options o = [self currentOptions];
    o.inSelection = NO;
    if (![self checkPrepared:o name:@"Replace in Files"]) return 0;
    NSString *dir = _dirField.stringValue.length ? _dirField.stringValue : _directory;
    NSString *question = _tab == TPFindTabFindInProjects
        ? @"Do you want to replace all occurrences in all documents in the selected Project Panel(s)?"
        : [NSString stringWithFormat:@"Are you sure you want to replace all occurrences in :\n%@\nfor file type :\n%@",
           dir, _filtersField.stringValue.length ? _filtersField.stringValue : @"*.*"];
    NSInteger r = [_c prompt:question informative:nil buttons:@[@"OK", @"Cancel"]];
    if (r != 0) return 0;
    [self remember];
    NSArray *files = [self searchFiles];
    __block long total = 0;
    __block NSInteger changedFiles = 0;
    __block NSMutableArray *failed = [NSMutableArray array];
    for (NSString *f in files) {
        [self onFile:f perform:^(ScintillaView *v, TPDocument *openDoc, tpp::TextEncoding enc) {
            long n = tpp::search::replaceAll(v, o, 0, -1, nullptr);
            if (n <= 0) return;
            total += n;
            ++changedFiles;
            if (openDoc) return;  // open buffers keep the change unsaved, as upstream
            tpp::EncodeResult er = tpp::encode(sciGetText(v), enc);
            if (!er.ok || er.lossy) { [failed addObject:f]; return; }
            if (!TPSafeWriteFile(f, er.bytes, nil)) [failed addObject:f];
        }];
    }
    [_c refreshUI];
    NSString *msg = [NSString stringWithFormat:@"Replace in Files: %ld occurrence%@ replaced in %ld file%@.", total, total == 1 ? @" was" : @"s were",
                     (long)changedFiles, changedFiles == 1 ? @"" : @"s"];
    if (failed.count) msg = [msg stringByAppendingFormat:@" %lu file(s) skipped (encoding or write error).", (unsigned long)failed.count];
    [self setStatus:msg kind:failed.count ? 0 : 1];
    return total;
}

// ---------------------------------------------------------------- button actions
- (void)actFindNext:(id)s { [self findNext:YES]; }
- (void)actCount:(id)s { [self count]; }
- (void)actFindAllOpened:(id)s { [self findAllInAllOpened]; }
- (void)actFindAllCurrent:(id)s { [self findAllInCurrent]; }
- (void)actReplace:(id)s { [self replaceOne]; }
- (void)actReplaceAll:(id)s { [self replaceAllInCurrent]; }
- (void)actReplaceAllOpened:(id)s { [self replaceAllInAllOpened]; }
- (void)actFindInFiles:(id)s { [self findInFiles]; }
- (void)actReplaceInFiles:(id)s { [self replaceInFiles]; }
- (void)actMarkAll:(id)s { [self markAll]; }
- (void)actClearMarks:(id)s { [self clearMarks]; }
- (void)actCopyMarked:(id)s { [self copyMarkedText]; }
- (void)actClose:(id)s { [self.window orderOut:nil]; [self clearMatchHighlighting]; }

- (void)cancelOperation:(id)sender { [self.window orderOut:nil]; [self clearMatchHighlighting]; }

@end
