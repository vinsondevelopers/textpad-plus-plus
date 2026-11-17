// Textpad++ — Search > Find characters in range... (upstream WinControls/FindCharsInRange). GPL-3.0-or-later.
// Same controls and defaults as upstream findCharsInRange.rc: Non-ASCII / ASCII / custom range radios,
// Direction Up / Down (Down), Wrap around (off), Find and Close.
#import "dialogs/FindCharsInRangeDialog.h"
#import "app/MainWindowController.h"
#import "app/Preferences.h"
#import "app/Sci.h"

@interface TPFindCharsInRangeDialog () <NSWindowDelegate>
@end

@implementation TPFindCharsInRangeDialog {
    __weak TPMainWindowController *_c;
    NSButton *_nonAscii, *_ascii, *_custom, *_up, *_down, *_wrap;
    NSTextField *_start, *_end, *_dash;
}

+ (instancetype)sharedWithController:(TPMainWindowController *)c {
    static TPFindCharsInRangeDialog *shared;
    if (!shared) shared = [[TPFindCharsInRangeDialog alloc] initWithController:c];
    shared->_c = c;
    return shared;
}

- (NSButton *)radio:(NSString *)title frame:(NSRect)r action:(SEL)a in:(NSView *)v {
    NSButton *b = [NSButton radioButtonWithTitle:title target:self action:a];
    b.frame = r;
    [v addSubview:b];
    return b;
}

- (instancetype)initWithController:(TPMainWindowController *)c {
    NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 420, 156)
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow
                                              backing:NSBackingStoreBuffered defer:YES];
    p.title = @"Find Characters in Range...";
    p.hidesOnDeactivate = NO;
    p.releasedWhenClosed = NO;
    if ((self = [super initWithWindow:p])) {
        _c = c;
        NSView *v = p.contentView;
        // Range radios share one action so AppKit groups them
        _nonAscii = [self radio:@"Non-ASCII characters (128–255)" frame:NSMakeRect(14, 124, 260, 20) action:@selector(rangeChanged:) in:v];
        _ascii = [self radio:@"ASCII characters (0–127)" frame:NSMakeRect(14, 100, 260, 20) action:@selector(rangeChanged:) in:v];
        _custom = [self radio:@"Custom range (0–255):" frame:NSMakeRect(14, 76, 170, 20) action:@selector(rangeChanged:) in:v];
        _start = [[NSTextField alloc] initWithFrame:NSMakeRect(186, 75, 44, 22)];
        _end = [[NSTextField alloc] initWithFrame:NSMakeRect(250, 75, 44, 22)];
        for (NSTextField *f in @[_start, _end]) { f.alignment = NSTextAlignmentCenter; [v addSubview:f]; }
        _start.stringValue = @"0"; _end.stringValue = @"255";
        _dash = [NSTextField labelWithString:@"–"];
        _dash.frame = NSMakeRect(233, 78, 14, 16);
        _dash.alignment = NSTextAlignmentCenter;
        [v addSubview:_dash];
        NSBox *dir = [[NSBox alloc] initWithFrame:NSMakeRect(10, 8, 120, 62)];
        dir.title = @"Direction";
        [v addSubview:dir];
        _up = [self radio:@"Up" frame:NSMakeRect(10, 22, 90, 18) action:@selector(directionChanged:) in:dir.contentView];
        _down = [self radio:@"Down" frame:NSMakeRect(10, 2, 90, 18) action:@selector(directionChanged:) in:dir.contentView];
        _wrap = [NSButton checkboxWithTitle:@"Wrap around" target:nil action:nil];
        _wrap.frame = NSMakeRect(142, 12, 160, 20);
        [v addSubview:_wrap];
        NSButton *find = [NSButton buttonWithTitle:@"Find" target:self action:@selector(findNext:)];
        find.frame = NSMakeRect(310, 118, 100, 28);
        find.keyEquivalent = @"\r";
        NSButton *close = [NSButton buttonWithTitle:@"Close" target:self action:@selector(closeDialog:)];
        close.frame = NSMakeRect(310, 88, 100, 28);
        close.keyEquivalent = @"\033";
        [v addSubview:find]; [v addSubview:close];
        // upstream WM_INITDIALOG defaults
        self.rangeMode = 0;
        self.directionDown = YES;
        self.wrapAround = NO;
        [p center];
    }
    return self;
}

- (void)rangeChanged:(NSButton *)sender {
    self.rangeMode = sender == _custom ? 2 : sender == _ascii ? 1 : 0;
}
- (void)directionChanged:(NSButton *)sender { self.directionDown = sender == _down; }

- (NSInteger)rangeMode { return _custom.state ? 2 : _ascii.state ? 1 : 0; }
- (void)setRangeMode:(NSInteger)m {
    _nonAscii.state = m == 0; _ascii.state = m == 1; _custom.state = m == 2;
    _start.enabled = _end.enabled = m == 2;
    _dash.textColor = m == 2 ? NSColor.labelColor : NSColor.disabledControlTextColor;
}
- (NSString *)rangeStart { return _start.stringValue; }
- (void)setRangeStart:(NSString *)s { _start.stringValue = s; }
- (NSString *)rangeEnd { return _end.stringValue; }
- (void)setRangeEnd:(NSString *)s { _end.stringValue = s; }
- (BOOL)directionDown { return _down.state == NSControlStateValueOn; }
- (void)setDirectionDown:(BOOL)d { _down.state = d; _up.state = !d; }
- (BOOL)wrapAround { return _wrap.state == NSControlStateValueOn; }
- (void)setWrapAround:(BOOL)w { _wrap.state = w; }

- (void)closeDialog:(id)sender { [self.window orderOut:nil]; }

static BOOL parseByte(NSString *s, int &out) {
    NSString *t = [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!t.length || t.length > 3 || [t rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound) return NO;
    out = t.intValue;
    return out <= 255;
}

- (IBAction)findNext:(id)sender {
    TPMainWindowController *c = _c;
    if (!c.currentDocument) return;
    int lo = 128, hi = 255;
    if (self.rangeMode == 1) { lo = 0; hi = 127; }
    else if (self.rangeMode == 2) {
        if (!parseByte(_start.stringValue, lo) || !parseByte(_end.stringValue, hi) || lo > hi) {
            [c showMessage:@"Range Value problem" informative:@"You should type between 0 and 255."];
            return;
        }
    }
    if (![self findCharInRange:lo to:hi]) TPBeep();
}

// upstream FindCharsInRangeDlg::findCharInRange: byte values of the document's in-memory (UTF-8) text.
// The match is selected as a whole character (upstream selects the single byte).
- (BOOL)findCharInRange:(int)lo to:(int)hi {
    ScintillaView *v = _c.editor;
    const BOOL down = self.directionDown, wrap = self.wrapAround;
    const std::string text = sciGetText(v);
    const sptr_t total = static_cast<sptr_t>(text.size());
    const sptr_t startPos = SCI(v, SCI_GETCURRENTPOS);
    auto inRange = [&](sptr_t i) { int b = static_cast<unsigned char>(text[static_cast<size_t>(i)]); return b >= lo && b <= hi; };
    sptr_t found = -1;
    if (down) { for (sptr_t i = startPos; i < total; ++i) if (inRange(i)) { found = i; break; } }
    else { for (sptr_t i = startPos - 1; i >= 0; --i) if (inRange(i)) { found = i; break; } }
    if (found < 0 && wrap) {
        if (down) { for (sptr_t i = 0; i < total; ++i) if (inRange(i)) { found = i; break; } }
        else { for (sptr_t i = total - 1; i >= 0; --i) if (inRange(i)) { found = i; break; } }
    }
    if (found < 0) return NO;
    const sptr_t chStart = SCI(v, SCI_POSITIONBEFORE, SCI(v, SCI_POSITIONAFTER, found));
    const sptr_t chEnd = SCI(v, SCI_POSITIONAFTER, chStart);
    SCI(v, SCI_ENSUREVISIBLE, SCI(v, SCI_LINEFROMPOSITION, chStart));
    if (down) SCI(v, SCI_SETSEL, chStart, chEnd); else SCI(v, SCI_SETSEL, chEnd, chStart);
    SCI(v, SCI_SCROLLCARET);
    return YES;
}

@end
