// Textpad++ — Command Palette. GPL-3.0-or-later.
#import "dialogs/CommandPalette.h"
#import "commands/CommandRegistry.h"

@implementation TPPaletteEntry
@end

@interface TPPalettePanel : NSPanel
@end
@implementation TPPalettePanel
- (BOOL)canBecomeKeyWindow { return YES; }
@end

@implementation TPCommandPalette {
    NSSearchField *_search;
    NSTableView *_table;
    NSArray<TPPaletteEntry *> *_all;
    NSArray<TPPaletteEntry *> *_results;
    __weak NSWindow *_owner;
}

+ (instancetype)shared {
    static TPCommandPalette *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [TPCommandPalette new]; });
    return s;
}

- (NSArray<TPPaletteEntry *> *)results { return _results ?: @[]; }

// ------------------------------------------------------------ the commands: everything in the menu bar
- (void)collectFrom:(NSMenu *)menu path:(NSString *)path into:(NSMutableArray *)out seen:(NSMutableSet *)seen {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    for (NSMenuItem *mi in menu.itemArray) {
        if (mi.isSeparatorItem || mi.isHidden) continue;
        NSString *title = [mi.title stringByReplacingOccurrencesOfString:@"&" withString:@""];
        if (mi.submenu) {
            if (menu.delegate && [menu.delegate respondsToSelector:@selector(menuNeedsUpdate:)]) [menu.delegate menuNeedsUpdate:mi.submenu];
            [self collectFrom:mi.submenu path:path.length ? [NSString stringWithFormat:@"%@ › %@", path, title] : title into:out seen:seen];
            continue;
        }
        const int cmd = (int)mi.tag;
        if (mi.action != NSSelectorFromString(@"menuCommand:") || cmd <= 0 || [seen containsObject:@(cmd)] || ![reg hasHandler:cmd]) continue;
        [seen addObject:@(cmd)];
        TPPaletteEntry *e = [TPPaletteEntry new];
        e.command = cmd;
        e.title = title;
        e.path = path;
        TPKeyBinding *kb = [reg primaryBindingForCommand:cmd];
        e.shortcut = kb && !kb.isEmpty ? (reg.scheme == TPShortcutSchemeMac ? kb.macDescription : kb.windowsDescription) ?: @"" : @"";
        [out addObject:e];
    }
}

- (NSArray<TPPaletteEntry *> *)allEntries {
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSMenuItem *top in NSApp.mainMenu.itemArray) {
        if (!top.submenu) continue;
        NSString *t = [top.title isEqualToString:@"Textpad++"] ? @"Textpad++" : top.title;
        if (top.submenu.delegate && [top.submenu.delegate respondsToSelector:@selector(menuNeedsUpdate:)]) [top.submenu.delegate menuNeedsUpdate:top.submenu];
        [self collectFrom:top.submenu path:t into:out seen:seen];
    }
    return out;
}

// subsequence match; letters at word starts and runs of letters score higher; every word of the query must match
+ (NSInteger)scoreOf:(NSString *)query in:(NSString *)candidate {
    NSString *c = candidate.lowercaseString;
    NSInteger total = 0;
    for (NSString *word in [query.lowercaseString componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) {
        if (!word.length) continue;
        NSRange exact = [c rangeOfString:word];
        if (exact.location != NSNotFound) {
            const BOOL wordStart = exact.location == 0 || ![NSCharacterSet.alphanumericCharacterSet characterIsMember:[c characterAtIndex:exact.location - 1]];
            total += 100 + word.length * 10 + (wordStart ? 60 : 0) - (NSInteger)MIN((NSUInteger)40, exact.location);
            continue;
        }
        NSInteger s = 0, run = 0;
        NSUInteger at = 0;
        for (NSUInteger i = 0; i < word.length; ++i) {
            const unichar w = [word characterAtIndex:i];
            BOOL found = NO;
            for (; at < c.length; ++at) {
                if ([c characterAtIndex:at] != w) { run = 0; continue; }
                const BOOL start = at == 0 || ![NSCharacterSet.alphanumericCharacterSet characterIsMember:[c characterAtIndex:at - 1]];
                s += 2 + (start ? 8 : 0) + run * 4;
                ++run;
                ++at;
                found = YES;
                break;
            }
            if (!found) return 0;
        }
        total += s;
    }
    return total;
}

- (NSArray<TPPaletteEntry *> *)entriesForQuery:(NSString *)query {
    if (!_all || !_panel.isVisible) _all = [self allEntries];
    NSArray *recent = [[NSUserDefaults standardUserDefaults] arrayForKey:@"palette.recent"] ?: @[];
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    NSString *q = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSMutableArray *out = [NSMutableArray array];
    for (TPPaletteEntry *e in _all) {
        e.enabled = [reg isEnabled:e.command];
        const NSUInteger r = [recent indexOfObject:@(e.command)];
        const NSInteger bonus = r == NSNotFound ? 0 : 30 - (NSInteger)MIN((NSUInteger)29, r);
        if (!q.length) { e.score = bonus; if (r != NSNotFound) [out addObject:e]; continue; }
        // the title counts most; the menu path helps ("view wrap")
        NSInteger s = [TPCommandPalette scoreOf:q in:e.title] * 2;
        if (!s) s = [TPCommandPalette scoreOf:q in:[NSString stringWithFormat:@"%@ %@", e.path, e.title]];
        if (!s) continue;
        e.score = s + bonus + (e.enabled ? 5 : 0);
        [out addObject:e];
    }
    if (!q.length && out.count < 12)   // nothing typed: recent commands, then everything in menu order
        for (TPPaletteEntry *e in _all) if (![out containsObject:e]) [out addObject:e];
    [out sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(TPPaletteEntry *a, TPPaletteEntry *b) {
        return a.score > b.score ? NSOrderedAscending : a.score < b.score ? NSOrderedDescending : NSOrderedSame;
    }];
    return out;
}

// ------------------------------------------------------------ the window
- (void)build {
    _panel = [[TPPalettePanel alloc] initWithContentRect:NSMakeRect(0, 0, 640, 400)
                                               styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskFullSizeContentView
                                                 backing:NSBackingStoreBuffered defer:YES];
    _panel.floatingPanel = YES;
    _panel.hidesOnDeactivate = YES;
    _panel.releasedWhenClosed = NO;
    _panel.delegate = self;
    _panel.opaque = NO;
    _panel.backgroundColor = NSColor.clearColor;
    _panel.hasShadow = YES;
    _panel.title = @"Command Palette";
    NSVisualEffectView *bg = [[NSVisualEffectView alloc] initWithFrame:_panel.contentView.bounds];
    bg.material = NSVisualEffectMaterialPopover;
    bg.state = NSVisualEffectStateActive;
    bg.wantsLayer = YES;
    bg.layer.cornerRadius = 12;
    bg.layer.masksToBounds = YES;
    bg.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _panel.contentView = bg;
    _search = [[NSSearchField alloc] initWithFrame:NSMakeRect(14, 400 - 48, 612, 34)];
    _search.placeholderString = @"Type a command — e.g. “save as”, “wrap”, “json format”";
    _search.font = [NSFont systemFontOfSize:16];
    _search.delegate = self;
    _search.focusRingType = NSFocusRingTypeNone;
    _search.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [bg addSubview:_search];
    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(8, 8, 624, 400 - 64)];
    sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    sv.drawsBackground = NO;
    sv.hasVerticalScroller = YES;
    sv.autohidesScrollers = YES;
    _table = [[NSTableView alloc] initWithFrame:sv.bounds];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"c"];
    col.width = 600;
    [_table addTableColumn:col];
    _table.headerView = nil;
    _table.rowHeight = 30;
    _table.backgroundColor = NSColor.clearColor;
    _table.style = NSTableViewStyleSourceList;
    _table.dataSource = self;
    _table.delegate = self;
    _table.target = self;
    _table.doubleAction = @selector(runSelected:);
    _table.action = @selector(runSelected:);
    sv.documentView = _table;
    [bg addSubview:sv];
}

- (void)showOverWindow:(NSWindow *)w { [self showOverWindow:w query:@""]; }

- (void)showOverWindow:(NSWindow *)w query:(NSString *)query {
    if (!_panel) [self build];
    _owner = w;
    _all = [self allEntries];
    _search.stringValue = query ?: @"";
    [self refilter];
    const NSRect f = w ? w.frame : NSScreen.mainScreen.visibleFrame;
    [_panel setFrameOrigin:NSMakePoint(NSMidX(f) - 320, NSMaxY(f) - 120 - 400)];
    [_panel makeKeyAndOrderFront:nil];
    [_panel makeFirstResponder:_search];
}

- (void)close { [_panel orderOut:nil]; if (_owner) [_owner makeKeyWindow]; }
- (void)cancelOperation:(id)sender { [self close]; }
- (void)windowDidResignKey:(NSNotification *)n { [_panel orderOut:nil]; }

- (void)refilter {
    _results = [self entriesForQuery:_search.stringValue];
    [_table reloadData];
    if (_results.count) [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [_table scrollRowToVisible:0];
}

- (void)controlTextDidChange:(NSNotification *)n { [self refilter]; }

- (BOOL)control:(NSControl *)c textView:(NSTextView *)tv doCommandBySelector:(SEL)sel {
    NSInteger row = _table.selectedRow;
    if (sel == @selector(moveDown:)) { row = MIN(row + 1, (NSInteger)_results.count - 1); }
    else if (sel == @selector(moveUp:)) { row = MAX(row - 1, 0); }
    else if (sel == @selector(insertNewline:)) { [self runSelected:nil]; return YES; }
    else if (sel == @selector(cancelOperation:)) { [self close]; return YES; }
    else return NO;
    if (row >= 0) { [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO]; [_table scrollRowToVisible:row]; }
    return YES;
}

- (void)runSelected:(id)sender {
    const NSInteger row = _table.selectedRow;
    if (row < 0 || row >= (NSInteger)_results.count) return;
    TPPaletteEntry *e = _results[row];
    if (!e.enabled) { NSBeep(); return; }
    [self close];
    [self runEntry:e];
}

- (void)runEntry:(TPPaletteEntry *)e {
    NSMutableArray *recent = [[[NSUserDefaults standardUserDefaults] arrayForKey:@"palette.recent"] ?: @[] mutableCopy];
    [recent removeObject:@(e.command)];
    [recent insertObject:@(e.command) atIndex:0];
    while (recent.count > 20) [recent removeLastObject];
    [[NSUserDefaults standardUserDefaults] setObject:recent forKey:@"palette.recent"];
    [[TPCommandRegistry shared] execute:e.command];
}

// ------------------------------------------------------------ table
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return (NSInteger)_results.count; }

- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    NSTableCellView *cell = [t makeViewWithIdentifier:@"pc" owner:self];
    NSTextField *title, *path, *keys;
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 600, 30)];
        cell.identifier = @"pc";
        title = [NSTextField labelWithString:@""];
        title.font = [NSFont systemFontOfSize:13.5 weight:NSFontWeightMedium];
        title.frame = NSMakeRect(8, 7, 300, 18);
        title.tag = 1;
        path = [NSTextField labelWithString:@""];
        path.font = [NSFont systemFontOfSize:11.5];
        path.textColor = NSColor.secondaryLabelColor;
        path.frame = NSMakeRect(300, 8, 190, 16);
        path.lineBreakMode = NSLineBreakByTruncatingHead;
        path.tag = 2;
        keys = [NSTextField labelWithString:@""];
        keys.font = [NSFont monospacedSystemFontOfSize:11.5 weight:NSFontWeightRegular];
        keys.textColor = NSColor.secondaryLabelColor;
        keys.alignment = NSTextAlignmentRight;
        keys.frame = NSMakeRect(490, 8, 104, 16);
        keys.autoresizingMask = NSViewMinXMargin;
        keys.tag = 3;
        for (NSTextField *f in @[title, path, keys]) [cell addSubview:f];
    }
    TPPaletteEntry *e = _results[row];
    title = [cell viewWithTag:1]; path = [cell viewWithTag:2]; keys = [cell viewWithTag:3];
    title.stringValue = e.title;
    [title sizeToFit];
    NSRect tf = title.frame; tf.size.width = MIN(tf.size.width, 330); title.frame = tf;
    path.frame = NSMakeRect(NSMaxX(tf) + 8, 8, MAX(40, 486 - NSMaxX(tf) - 8), 16);
    path.stringValue = e.path;
    keys.stringValue = e.shortcut;
    title.textColor = e.enabled ? NSColor.labelColor : NSColor.tertiaryLabelColor;
    return cell;
}

@end
