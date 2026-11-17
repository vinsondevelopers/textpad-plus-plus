// Textpad++ — Edit > Character Panel (upstream AnsiCharPanel / asciiListView) and Edit > Clipboard History
// (upstream ClipboardHistoryPanel). GPL-3.0-or-later.
#import "panels/Panels.h"
#import "app/MainWindowController.h"
#import "app/Document.h"
#import "app/Preferences.h"
#import "app/Sci.h"
#include "core/Encoding.h"

#include "generated/NppAsciiTables.inc"

// the document's single-byte code page: its own for ANSI documents, the ANSI code page setting otherwise
static int codepageOf(TPDocument *d) {
    if (d && d.encoding.mode == tpp::UniMode::Ansi && d.encoding.codepage > 0) return d.encoding.codepage;
    return tpp::ansiCodepage();
}

static NSString *charFromByte(unsigned char b, int cp) {
    CFStringEncoding enc = CFStringConvertWindowsCodepageToEncoding(static_cast<UInt32>(cp));
    if (enc == kCFStringEncodingInvalidId) enc = kCFStringEncodingWindowsLatin1;
    NSString *s = [[NSString alloc] initWithBytes:&b length:1 encoding:CFStringConvertEncodingToNSStringEncoding(enc)];
    return s ?: @"";
}

// ================================================================ Character Panel
@interface TPCharacterPanel () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation TPCharacterPanel {
    __weak TPMainWindowController *_c;
    NSScrollView *_scroll;
    int _codepage;
}

- (instancetype)initWithController:(TPMainWindowController *)c {
    if ((self = [super init])) {
        _c = c;
        _codepage = 1252;
        _scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 300, 400)];
        _scroll.hasVerticalScroller = YES; _scroll.hasHorizontalScroller = YES; _scroll.autohidesScrollers = YES;
        _table = [[NSTableView alloc] initWithFrame:_scroll.bounds];
        for (NSArray *col in @[@[@"Value", @44], @[@"Hex", @36], @[@"Character", @70], @[@"HTML Name", @80], @[@"HTML Decimal", @82], @[@"HTML Hexadecimal", @100]]) {
            NSTableColumn *tc = [[NSTableColumn alloc] initWithIdentifier:col[0]];
            tc.title = col[0]; tc.width = [col[1] doubleValue];
            [_table addTableColumn:tc];
        }
        _table.dataSource = self; _table.delegate = self;
        _table.target = self; _table.doubleAction = @selector(doubleClicked:);
        _table.usesAlternatingRowBackgroundColors = YES;
        _scroll.documentView = _table;
    }
    return self;
}

- (NSString *)panelIdentifier { return @"charpanel"; }
- (NSString *)panelTitle { return @"Character Panel"; }
- (NSView *)panelView { return _scroll; }
- (TPDockSide)defaultSide { return TPDockRight; }
- (void)panelDidShow { [self documentsChanged]; }
- (void)focusPanel { [_table.window makeFirstResponder:_table]; }
- (void)documentsChanged {
    int cp = codepageOf(_c.currentDocument);
    if (cp != _codepage) { _codepage = cp; [_table reloadData]; }   // upstream AsciiListView::resetValues(codepage)
}

// upstream AsciiListView::setValues
- (NSString *)textForColumn:(NSInteger)col row:(NSInteger)i {
    const BOOL latin1 = _codepage == 1252;
    switch (col) {
        case 0: return [NSString stringWithFormat:@"%ld", (long)i];
        case 1: return [NSString stringWithFormat:@"%02lX", (long)i];
        case 2: return kAsciiNames[i] ? @(kAsciiNames[i]) : charFromByte(static_cast<unsigned char>(i), _codepage);
        case 3: return latin1 && kHtmlNames[i] ? @(kHtmlNames[i]) : @"";
        case 4: case 5: {
            if (!latin1) return @"";
            int n = ((i >= 32 && i <= 126 && i != 45) || (i >= 160 && i <= 255)) ? static_cast<int>(i) : kHtmlNumbers[i];
            if (n < 0) return @"";
            return col == 4 ? [NSString stringWithFormat:@"&#%d;", n] : [NSString stringWithFormat:@"&#x%x;", n];
        }
    }
    return @"";
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return 256; }
- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    NSTextField *t = [tv makeViewWithIdentifier:col.identifier owner:self];
    if (!t) { t = [NSTextField labelWithString:@""]; t.identifier = col.identifier; }
    t.stringValue = [self textForColumn:(NSInteger)[tv.tableColumns indexOfObject:col] row:row];
    return t;
}

// double-click: the Character column inserts the character, the other columns insert their text (upstream)
- (void)doubleClicked:(id)sender {
    NSInteger row = _table.clickedRow, col = _table.clickedColumn;
    if (row < 0) return;
    if (col == 2 || col < 0) [self insertCharacter:(unsigned char)row];
    else [self insertText:[self textForColumn:col row:row]];
}

- (void)insertCharacter:(unsigned char)b {
    ScintillaView *v = _c.editor;
    if (!_c.currentDocument || SCI(v, SCI_GETREADONLY)) { TPBeep(); return; }
    std::string bytes;
    if (b < 128) bytes.assign(1, static_cast<char>(b));
    else bytes = StdStr(charFromByte(b, codepageOf(_c.currentDocument)));   // shown character, stored as UTF-8 in the buffer
    SCI(v, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>(""));
    SCI(v, SCI_ADDTEXT, bytes.size(), reinterpret_cast<sptr_t>(bytes.data()));
    [v.window makeFirstResponder:v.content];
}

- (void)insertText:(NSString *)s {
    ScintillaView *v = _c.editor;
    if (!_c.currentDocument || SCI(v, SCI_GETREADONLY) || !s.length) { TPBeep(); return; }
    SCI(v, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>(s.UTF8String));
    [v.window makeFirstResponder:v.content];
}

@end

// ================================================================ Clipboard History
@interface TPClipboardHistoryPanel () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation TPClipboardHistoryPanel {
    __weak TPMainWindowController *_c;
    NSScrollView *_scroll;
    NSMutableArray<NSString *> *_entries;
    NSInteger _changeCount;
    NSTimer *_timer;
}

- (instancetype)initWithController:(TPMainWindowController *)c {
    if ((self = [super init])) {
        _c = c;
        _entries = [NSMutableArray array];
        _scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 260, 400)];
        _scroll.hasVerticalScroller = YES; _scroll.autohidesScrollers = YES;
        _table = [[NSTableView alloc] initWithFrame:_scroll.bounds];
        NSTableColumn *tc = [[NSTableColumn alloc] initWithIdentifier:@"clip"];
        tc.resizingMask = NSTableColumnAutoresizingMask;
        [_table addTableColumn:tc];
        _table.headerView = nil;
        _table.dataSource = self; _table.delegate = self;
        _table.target = self; _table.doubleAction = @selector(doubleClicked:);
        _table.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
        _scroll.documentView = _table;
        _changeCount = [NSPasteboard generalPasteboard].changeCount;
        // macOS has no clipboard-change notification (upstream: WM_CLIPBOARDUPDATE): poll the change count
        __weak TPClipboardHistoryPanel *ws = self;
        _timer = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { [ws checkPasteboard]; }];
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    }
    return self;
}
- (void)dealloc { [_timer invalidate]; }

- (NSString *)panelIdentifier { return @"cliphistory"; }
- (NSString *)panelTitle { return @"Clipboard History"; }
- (NSView *)panelView { return _scroll; }
- (TPDockSide)defaultSide { return TPDockRight; }
- (void)focusPanel { [_table.window makeFirstResponder:_table]; }
- (NSArray<NSString *> *)entries { return _entries; }

- (void)checkPasteboard {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    if (pb.changeCount == _changeCount) return;
    _changeCount = pb.changeCount;
    NSString *s = [pb stringForType:NSPasteboardTypeString];
    if (s.length) [self addEntry:s];
}

// upstream addToClipboadHistory: newest first, an existing entry moves to the top
- (void)addEntry:(NSString *)s {
    NSUInteger i = [_entries indexOfObject:s];
    if (i == 0) return;
    if (i != NSNotFound) [_entries removeObjectAtIndex:i];
    [_entries insertObject:s atIndex:0];
    if (_entries.count > 1000) [_entries removeLastObject];
    [_table reloadData];
}

// upstream getDisplayStr: one line, at most MAX_PATH - 3 characters
- (NSString *)displayOf:(NSString *)s {
    NSString *one = [[s componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet] componentsJoinedByString:@" "];
    return one.length > 257 ? [[one substringToIndex:257] stringByAppendingString:@"..."] : one;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return (NSInteger)_entries.count; }
- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    NSTextField *t = [tv makeViewWithIdentifier:@"clip" owner:self];
    if (!t) { t = [NSTextField labelWithString:@""]; t.identifier = @"clip"; t.lineBreakMode = NSLineBreakByTruncatingTail; }
    t.stringValue = [self displayOf:_entries[(NSUInteger)row]];
    t.toolTip = [_entries[(NSUInteger)row] substringToIndex:MIN((NSUInteger)2000, _entries[(NSUInteger)row].length)];
    return t;
}

- (void)doubleClicked:(id)sender { [self pasteEntryAtIndex:_table.clickedRow]; }

// upstream onDoubleClick: replace the selection with the entry
- (BOOL)pasteEntryAtIndex:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)_entries.count) return NO;
    ScintillaView *v = _c.editor;
    if (!_c.currentDocument || SCI(v, SCI_GETREADONLY)) { TPBeep(); return NO; }
    std::string bytes = StdStr(_entries[(NSUInteger)i]);
    SCI(v, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>(""));
    SCI(v, SCI_ADDTEXT, bytes.size(), reinterpret_cast<sptr_t>(bytes.data()));
    [v.window makeFirstResponder:v.content];
    return YES;
}

@end
