// Textpad++ — Search > Incremental Search (port of upstream FindIncrementDlg). GPL-3.0-or-later.
#import "search/IncrementalSearchBar.h"
#import "search/SearchEngine.h"
#import "app/MainWindowController.h"
#import "app/Preferences.h"

using namespace tpp::search;

@implementation TPIncrementalSearchBar {
    __weak TPMainWindowController *_c;
    NSButton *_close, *_upDown, *_prev, *_next;
    NSTextField *_status;
    std::vector<Match> _matches;
}

- (instancetype)initWithController:(TPMainWindowController *)c {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 900, 30)])) {
        _c = c;
        _close = [NSButton buttonWithTitle:@"✕" target:self action:@selector(closeClicked:)];
        _upDown = [NSButton buttonWithTitle:@"˄" target:self action:@selector(toggleTop:)];
        NSTextField *label = [NSTextField labelWithString:@"Find:"];
        _field = [[NSTextField alloc] initWithFrame:NSZeroRect];
        _field.delegate = self;
        _field.placeholderString = @"";
        _prev = [NSButton buttonWithTitle:@"<" target:self action:@selector(prevClicked:)];
        _next = [NSButton buttonWithTitle:@">" target:self action:@selector(nextClicked:)];
        _matchCaseCheck = [NSButton checkboxWithTitle:@"Match case" target:self action:@selector(optionChanged:)];
        _highlightAllCheck = [NSButton checkboxWithTitle:@"Highlight all" target:self action:@selector(optionChanged:)];
        _countCheck = [NSButton checkboxWithTitle:@"Count" target:self action:@selector(optionChanged:)];
        _status = [NSTextField labelWithString:@""];
        _status.textColor = NSColor.secondaryLabelColor;
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        _matchCaseCheck.state = [ud boolForKey:@"incfind.matchCase"];
        _highlightAllCheck.state = [ud boolForKey:@"incfind.highlightAll"];
        _countCheck.state = [ud boolForKey:@"incfind.count"];
        _atTop = [ud boolForKey:@"incfind.atTop"];
        CGFloat x = 6;
        for (NSView *v in @[_close, _upDown, label, _field, _prev, _next, _matchCaseCheck, _highlightAllCheck, _countCheck, _status]) {
            CGFloat w = v == _field ? 260 : v == label ? 38 : v == _status ? 340 : [v isKindOfClass:[NSButton class]] && ((NSButton *)v).bezelStyle != 0 && ((NSButton *)v).title.length <= 1 ? 28 : 110;
            if (v == _close || v == _upDown || v == _prev || v == _next) { w = 28; ((NSButton *)v).bezelStyle = NSBezelStyleInline; }
            v.frame = NSMakeRect(x, v == label || v == _status ? 7 : 3, w, 24);
            [self addSubview:v];
            x += w + 4;
        }
        [_upDown setTitle:_atTop ? @"˅" : @"˄"];
        _close.toolTip = @"Close"; _upDown.toolTip = @"Move the bar to the top / bottom";
        _close.accessibilityLabel = @"Close incremental search";
    }
    return self;
}

- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)r {
    [[TPChrome barBackground] setFill];
    NSRectFill(self.bounds);
    [[TPChrome border] setFill];
    NSRectFill(NSMakeRect(0, _atTop ? NSHeight(self.bounds) - 1 : 0, NSWidth(self.bounds), 1));
}

- (NSString *)statusText { return _status.stringValue; }

- (void)show {
    self.hidden = NO;
    [_c applyChromeVisibility];   // the container lays the bar out
    std::string sel = sciSelectedText(_c.editor);
    if (!sel.empty() && sel.find('\n') == std::string::npos) _field.stringValue = NSStr(sel);
    [self.window makeFirstResponder:_field];
    [_field selectText:nil];
}

- (void)close {
    self.hidden = YES;
    SCI(_c.editor, SCI_SETINDICATORCURRENT, TPP_INDIC_INC);
    SCI(_c.editor, SCI_INDICATORCLEARRANGE, 0, SCI(_c.editor, SCI_GETLENGTH));
    [_c applyChromeVisibility];
    [_c.editor.window makeFirstResponder:_c.editor.content];
}
- (void)closeClicked:(id)s { [self close]; }
- (void)toggleTop:(id)s {
    _atTop = !_atTop;
    [[NSUserDefaults standardUserDefaults] setBool:_atTop forKey:@"incfind.atTop"];
    [_upDown setTitle:_atTop ? @"˅" : @"˄"];
    [_c applyChromeVisibility];
}
- (void)setAtTop:(BOOL)t { if (t != _atTop) [self toggleTop:nil]; }
- (void)prevClicked:(id)s { [self findNext:NO]; }
- (void)nextClicked:(id)s { [self findNext:YES]; }
- (void)optionChanged:(id)s {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:_matchCaseCheck.state forKey:@"incfind.matchCase"];
    [ud setBool:_highlightAllCheck.state forKey:@"incfind.highlightAll"];
    [ud setBool:_countCheck.state forKey:@"incfind.count"];
    _matches.clear();
    if (s == _matchCaseCheck) [self search:NO forward:YES caseChanged:YES];
    else if (s == _countCheck) [self search:NO forward:YES caseChanged:NO];
    [self updateHighlight];
}

- (void)controlTextDidChange:(NSNotification *)n { [self textChanged]; }
- (BOOL)control:(NSControl *)c textView:(NSTextView *)tv doCommandBySelector:(SEL)sel {
    if (sel == @selector(insertNewline:)) { [self findNext:!(NSApp.currentEvent.modifierFlags & NSEventModifierFlagShift)]; return YES; }
    if (sel == @selector(cancelOperation:)) { [self close]; return YES; }
    return NO;
}

- (void)textChanged {
    _matches.clear();
    [self search:NO forward:YES caseChanged:NO];
    [self updateHighlight];
}
- (void)findNext:(BOOL)forward { [self search:YES forward:forward caseChanged:NO]; [self updateHighlight]; }

- (Options)options {
    Options o;
    o.find = StdStr(_field.stringValue);
    o.mode = Mode::Normal;
    o.matchCase = _matchCaseCheck.state == NSControlStateValueOn;
    o.wrap = YES;
    return o;
}

// FirstIncremental: from the start of the selection (the match grows as you type); NextIncremental: from its end
- (void)search:(BOOL)advance forward:(BOOL)forward caseChanged:(BOOL)caseChanged {
    ScintillaView *v = _c.editor;
    Options o = [self options];
    if (o.find.empty()) { _status.stringValue = @""; return; }
    o.backward = !forward;
    sptr_t s = SCI(v, SCI_GETSELECTIONSTART), e = SCI(v, SCI_GETSELECTIONEND);
    if (!advance) SCI(v, SCI_SETSEL, s, s);
    else if (forward) SCI(v, SCI_SETSEL, e, e);
    else SCI(v, SCI_SETSEL, s, s);
    FindResult r = findNext(v, o);
    NSString *msg = @"";
    if (!r.found) {
        msg = @"Phrase not found";
        if (caseChanged) SCI(v, SCI_SETSEL, s, s);
        else SCI(v, SCI_SETSEL, s, e);
    } else if (r.wrapped) {
        msg = forward ? @"Reached end of page, continued from top" : @"Reached top of page, continued from bottom";
    }
    if (_countCheck.state == NSControlStateValueOn && r.found) {
        if (_matches.empty()) findAll(v, o, 0, -1, _matches);
        size_t nth = 0;
        for (size_t i = 0; i < _matches.size(); ++i) if (_matches[i].start == r.start && _matches[i].end == r.end) { nth = i + 1; break; }
        NSString *count = [NSString stringWithFormat:@"%zu/%zu", nth, _matches.size()];
        msg = msg.length ? [NSString stringWithFormat:@"%@ - %@", count, msg] : count;
    }
    _status.stringValue = msg;
    _status.textColor = r.found ? NSColor.secondaryLabelColor : NSColor.systemRedColor;
}

// upstream markSelectedTextInc: highlight every occurrence of the selected (found) text
- (void)updateHighlight {
    ScintillaView *v = _c.editor;
    SCI(v, SCI_SETINDICATORCURRENT, TPP_INDIC_INC);
    SCI(v, SCI_INDICATORCLEARRANGE, 0, SCI(v, SCI_GETLENGTH));
    if (_highlightAllCheck.state != NSControlStateValueOn || !_field.stringValue.length) return;
    std::string sel = sciSelectedText(v);
    if (sel.empty()) return;
    Options o = [self options];
    o.find = sel;
    markAll(v, o, TPP_INDIC_INC, 0, -1);
}

@end
