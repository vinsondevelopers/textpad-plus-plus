// Textpad++ — Settings > Shortcut Mapper... (upstream WinControls/Grid/ShortcutMapper + shortcut.cpp editor).
// Tabs Main menu / Macros / Run commands / Plugin commands / Scintilla commands, Name / Shortcut / Category columns,
// a filter, Modify / Clear / Delete / Close and the conflict report line, as upstream. GPL-3.0-or-later.
#import "dialogs/ShortcutMapper.h"
#import "app/MainWindowController.h"
#import "app/Preferences.h"
#import "commands/CommandRegistry.h"
#import "commands/ScintillaKeys.h"
#import "plugins/PluginHost.h"

namespace {
struct Row {
    int ident;            // command id or Scintilla message
    NSString *__strong name;
    NSString *__strong category;
};
}

@interface TPShortcutMapper () <NSWindowDelegate>
@end

@implementation TPShortcutMapper {
    __weak TPMainWindowController<TPShortcutMapperData> *_c;
    NSSegmentedControl *_tabs;
    NSSearchField *_filterField;
    NSTableView *_table;
    NSTextField *_conflict;
    NSButton *_modify, *_clear, *_delete;
    std::vector<Row> _rows;
}

+ (instancetype)sharedWithController:(TPMainWindowController<TPShortcutMapperData> *)c {
    static TPShortcutMapper *shared;
    if (!shared) shared = [[TPShortcutMapper alloc] initWithController:c];
    shared->_c = c;
    return shared;
}

- (instancetype)initWithController:(TPMainWindowController<TPShortcutMapperData> *)c {
    NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 720, 520)
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow
                                              backing:NSBackingStoreBuffered defer:YES];
    p.title = @"Shortcut Mapper";
    p.hidesOnDeactivate = NO;
    p.releasedWhenClosed = NO;
    p.minSize = NSMakeSize(560, 360);
    if (!(self = [super initWithWindow:p])) return nil;
    p.delegate = self;
    _c = c;
    NSView *v = p.contentView;
    _tabs = [NSSegmentedControl segmentedControlWithLabels:@[@"Main menu", @"Macros", @"Run commands", @"Plugin commands", @"Scintilla commands"]
                                              trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(tabChanged:)];
    _tabs.frame = NSMakeRect(12, 480, 696, 28);
    _tabs.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [v addSubview:_tabs];
    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(12, 112, 696, 360)];
    sv.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    sv.hasVerticalScroller = YES; sv.borderType = NSBezelBorder;
    _table = [[NSTableView alloc] initWithFrame:sv.bounds];
    for (NSArray *col in @[@[@"name", @"Name", @360], @[@"shortcut", @"Shortcut", @160], @[@"category", @"Category", @150]]) {
        NSTableColumn *tc = [[NSTableColumn alloc] initWithIdentifier:col[0]];
        tc.title = col[1]; tc.width = [col[2] doubleValue];
        [_table addTableColumn:tc];
    }
    _table.dataSource = self; _table.delegate = self;
    _table.doubleAction = @selector(modifySelected:); _table.target = self;
    _table.usesAlternatingRowBackgroundColors = YES;
    sv.documentView = _table;
    [v addSubview:sv];
    _conflict = [NSTextField wrappingLabelWithString:@""];
    _conflict.frame = NSMakeRect(12, 56, 696, 48);
    _conflict.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [v addSubview:_conflict];
    NSTextField *fl = [NSTextField labelWithString:@"Filter:"];
    fl.frame = NSMakeRect(12, 20, 44, 18);
    [v addSubview:fl];
    _filterField = [[NSSearchField alloc] initWithFrame:NSMakeRect(58, 16, 230, 24)];
    _filterField.delegate = self;
    [v addSubview:_filterField];
    _modify = [NSButton buttonWithTitle:@"Modify" target:self action:@selector(modifySelected:)];
    _clear = [NSButton buttonWithTitle:@"Clear" target:self action:@selector(clearSelected:)];
    _delete = [NSButton buttonWithTitle:@"Delete" target:self action:@selector(deleteSelected:)];
    NSButton *close = [NSButton buttonWithTitle:@"Close" target:self action:@selector(closeMapper:)];
    close.keyEquivalent = @"\033";
    CGFloat x = 316;
    for (NSButton *b in @[_modify, _clear, _delete, close]) {
        b.frame = NSMakeRect(x, 14, 92, 28);
        b.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
        [v addSubview:b];
        x += 98;
    }
    [p center];
    return self;
}

- (void)openOnTab:(TPMapperTab)tab {
    self.tab = tab;
    [self showWindow:nil];
}

- (void)setTab:(TPMapperTab)tab {
    _tab = tab;
    _tabs.selectedSegment = tab;
    [self reloadRows];
}
- (void)tabChanged:(id)sender { self.tab = static_cast<TPMapperTab>(_tabs.selectedSegment); }

- (NSString *)filter { return _filterField.stringValue ?: @""; }
- (void)setFilter:(NSString *)f { _filterField.stringValue = f ?: @""; [self reloadRows]; }
- (void)controlTextDidChange:(NSNotification *)n { [self reloadRows]; }

// ---------------------------------------------------------------- rows
- (TPKeyBinding *)bindingForRow:(const Row &)r {
    if (_tab == TPMapperTabScintilla) {
        TPScintillaKey *k = nil;
        for (TPScintillaKey *x in [TPScintillaKeys shared].keys) if (x.message == r.ident) k = x;
        if (k.menuCommand) return [[TPCommandRegistry shared] primaryBindingForCommand:k.menuCommand];
        return [[TPScintillaKeys shared] bindingsForMessage:r.ident].firstObject;
    }
    return [[TPCommandRegistry shared] primaryBindingForCommand:r.ident];
}

- (NSString *)describe:(TPKeyBinding *)b {
    if (!b || b.isEmpty) return @"";
    return [TPCommandRegistry shared].scheme == TPShortcutSchemeWindows ? b.windowsDescription : b.macDescription;
}

- (void)reloadRows {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    _rows.clear();
    switch (_tab) {
        case TPMapperTabMainMenu: {
            NSMutableSet *seen = [NSMutableSet set];
            for (NSNumber *n in reg.allMenuCommands) {
                int cmd = n.intValue;
                if (cmd == npp::IDM_WINDOW_MRU_FIRST || [seen containsObject:n]) continue;
                NSString *label = [reg labelForCommand:cmd];
                if (!label.length) continue;
                [seen addObject:n];
                NSArray *path = [reg menuPathForCommand:cmd];
                // sub-menu items are shown with their sub-menu ("Open Containing Folder > Finder")
                if (path.count > 2) label = [[path subarrayWithRange:NSMakeRange(1, path.count - 1)] componentsJoinedByString:@" > "];
                _rows.push_back({cmd, label, path.firstObject ?: @""});
            }
            break;
        }
        case TPMapperTabMacros: {
            NSArray *names = [_c macroNames];
            for (NSUInteger i = 0; i < names.count; ++i) _rows.push_back({TP_ID_MACRO + static_cast<int>(i), names[i], @""});
            break;
        }
        case TPMapperTabRunCommands: {
            NSArray *names = [_c runCommandNames];
            for (NSUInteger i = 0; i < names.count; ++i) _rows.push_back({TP_ID_USER_CMD + static_cast<int>(i), names[i], @""});
            break;
        }
        case TPMapperTabPluginCommands:   // upstream columns: Name, Shortcut, Plugin (the module)
            for (NSArray *r in [TPPluginHost shared].shortcutRows) _rows.push_back({[r[0] intValue], r[1], r[2]});
            break;
        case TPMapperTabScintilla:
            for (TPScintillaKey *k in [TPScintillaKeys shared].keys) _rows.push_back({k.message, k.name, @""});
            break;
    }
    NSString *f = self.filter.lowercaseString;
    if (f.length) {
        std::vector<Row> kept;
        for (const Row &r : _rows) {
            NSString *hay = [NSString stringWithFormat:@"%@ %@ %@", r.name, [self describe:[self bindingForRow:r]], r.category].lowercaseString;
            if ([hay containsString:f]) kept.push_back(r);
        }
        _rows = kept;
    }
    [_table tableColumnWithIdentifier:@"category"].hidden = _tab != TPMapperTabMainMenu && _tab != TPMapperTabPluginCommands;
    [_table tableColumnWithIdentifier:@"category"].title = _tab == TPMapperTabPluginCommands ? @"Plugin" : @"Category";
    [_table reloadData];
    if (!_rows.empty() && _table.selectedRow < 0) [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self updateButtonsAndConflicts];
}

- (NSInteger)rowCount { return static_cast<NSInteger>(_rows.size()); }
- (NSString *)nameAtRow:(NSInteger)row { return row >= 0 && row < self.rowCount ? _rows[static_cast<size_t>(row)].name : @""; }
- (NSString *)shortcutAtRow:(NSInteger)row { return row >= 0 && row < self.rowCount ? [self describe:[self bindingForRow:_rows[static_cast<size_t>(row)]]] : @""; }

- (BOOL)selectIdent:(int)ident {
    for (size_t i = 0; i < _rows.size(); ++i)
        if (_rows[i].ident == ident) {
            [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            [self updateButtonsAndConflicts];
            return YES;
        }
    return NO;
}
- (BOOL)selectCommand:(int)cmd {
    TPMapperTab want = cmd >= TP_ID_USER_CMD && cmd <= TP_ID_USER_CMD_LIMIT ? TPMapperTabRunCommands
                     : cmd >= TP_ID_MACRO && cmd <= TP_ID_MACRO_LIMIT ? TPMapperTabMacros : TPMapperTabMainMenu;
    if (_tab != want || self.filter.length) { _filterField.stringValue = @""; self.tab = want; }
    return [self selectIdent:cmd];
}
- (BOOL)selectScintillaMessage:(int)message {
    if (_tab != TPMapperTabScintilla || self.filter.length) { _filterField.stringValue = @""; self.tab = TPMapperTabScintilla; }
    return [self selectIdent:message];
}
- (BOOL)selectRowNamed:(NSString *)name {
    for (size_t i = 0; i < _rows.size(); ++i)
        if ([_rows[i].name isEqualToString:name]) { [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO]; [self updateButtonsAndConflicts]; return YES; }
    return NO;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return self.rowCount; }
- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    NSTextField *t = [tv makeViewWithIdentifier:col.identifier owner:self];
    if (!t) { t = [NSTextField labelWithString:@""]; t.identifier = col.identifier; t.lineBreakMode = NSLineBreakByTruncatingTail; }
    const Row &r = _rows[static_cast<size_t>(row)];
    if ([col.identifier isEqualToString:@"name"]) t.stringValue = r.name;
    else if ([col.identifier isEqualToString:@"shortcut"]) t.stringValue = [self describe:[self bindingForRow:r]];
    else t.stringValue = r.category;
    t.textColor = [self conflictsForRow:r].count ? NSColor.systemRedColor : NSColor.labelColor;   // upstream marks conflicts in red
    return t;
}
- (void)tableViewSelectionDidChange:(NSNotification *)n { [self updateButtonsAndConflicts]; }

// ---------------------------------------------------------------- conflicts (upstream ShortcutMapper::findKeyConflicts)
- (NSArray<NSString *> *)conflictsForRow:(const Row &)r {
    TPKeyBinding *b = [self bindingForRow:r];
    if (!b || b.isEmpty) return @[];
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    NSMutableArray *out = [NSMutableArray array];
    int self_cmd = _tab == TPMapperTabScintilla ? 0 : r.ident;
    int self_msg = _tab == TPMapperTabScintilla ? r.ident : 0;
    if (_tab == TPMapperTabScintilla) for (TPScintillaKey *k in [TPScintillaKeys shared].keys) if (k.message == r.ident && k.menuCommand) self_cmd = k.menuCommand;
    for (NSNumber *n in [reg commandsBoundToKey:b.keyEquivalent modifiers:b.modifiers]) {
        if (n.intValue == self_cmd) continue;
        NSString *where = n.intValue >= TP_ID_USER_CMD && n.intValue <= TP_ID_USER_CMD_LIMIT ? @"Run commands"
                        : n.intValue >= TP_ID_MACRO && n.intValue <= TP_ID_MACRO_LIMIT ? @"Macros" : @"Main menu";
        [out addObject:[NSString stringWithFormat:@"%@  |  %@  ( %@ )", where, [reg labelForCommand:n.intValue], [self describe:b]]];
    }
    for (NSNumber *m in [[TPScintillaKeys shared] messagesBoundToKey:b.keyEquivalent modifiers:b.modifiers]) {
        if (m.intValue == self_msg) continue;
        NSString *name = @"";
        for (TPScintillaKey *k in [TPScintillaKeys shared].keys) if (k.message == m.intValue) name = k.name;
        [out addObject:[NSString stringWithFormat:@"Scintilla commands  |  %@  ( %@ )", name, [self describe:b]]];
    }
    return out;
}

- (NSString *)conflictText { return _conflict.stringValue; }

- (BOOL)hasSelection { return _table.selectedRow >= 0 && _table.selectedRow < self.rowCount; }
- (const Row &)selected { return _rows[static_cast<size_t>(_table.selectedRow)]; }

- (void)updateButtonsAndConflicts {
    BOOL sel = self.hasSelection;
    _modify.enabled = sel;
    _clear.enabled = sel;
    _delete.enabled = sel && (_tab == TPMapperTabMacros || _tab == TPMapperTabRunCommands);
    if (!sel) { _conflict.stringValue = @""; return; }
    NSArray *c = [self conflictsForRow:self.selected];
    _conflict.stringValue = c.count ? [@"CONFLICT FOUND! " stringByAppendingString:[c componentsJoinedByString:@"\n"]] : @"No shortcut conflicts for this item.";
    _conflict.textColor = c.count ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
}

// ---------------------------------------------------------------- edits
- (void)assignBinding:(TPKeyBinding *)binding name:(NSString *)name {
    if (!self.hasSelection) return;
    Row r = self.selected;
    NSInteger keepRow = _table.selectedRow;
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    TPKeyBinding *b = binding ?: [TPKeyBinding bindingWithKey:@"" modifiers:0 command:r.ident];
    if (_tab == TPMapperTabScintilla) {
        TPScintillaKey *k = nil;
        for (TPScintillaKey *x in [TPScintillaKeys shared].keys) if (x.message == r.ident) k = x;
        if (k.menuCommand) [reg setUserBinding:b forCommand:k.menuCommand];
        else [[TPScintillaKeys shared] setUserBinding:b forMessage:r.ident];
    } else {
        [reg setUserBinding:b forCommand:r.ident];
        if (name.length && _tab == TPMapperTabMacros) [_c renameMacroAtIndex:r.ident - TP_ID_MACRO to:name];
        if (name.length && _tab == TPMapperTabRunCommands) [_c renameRunCommandAtIndex:r.ident - TP_ID_USER_CMD to:name];
    }
    [_c shortcutsDidChange];
    [self reloadRows];
    if (keepRow < self.rowCount) [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:static_cast<NSUInteger>(keepRow)] byExtendingSelection:NO];
    [self updateButtonsAndConflicts];
}

- (IBAction)clearSelected:(id)sender { [self assignBinding:nil name:nil]; }

- (IBAction)deleteSelected:(id)sender {
    if (!self.hasSelection) return;
    Row r = self.selected;
    if (_tab == TPMapperTabMacros) [_c deleteMacroAtIndex:r.ident - TP_ID_MACRO];
    else if (_tab == TPMapperTabRunCommands) [_c deleteRunCommandAtIndex:r.ident - TP_ID_USER_CMD];
    else return;
    [_c shortcutsDidChange];
    [_table deselectAll:nil];
    [self reloadRows];
}

- (void)closeMapper:(id)sender { [self.window orderOut:nil]; }

// The shortcut editor (upstream shortcut.rc IDD_SHORTCUT_DLG): Name, CTRL / ALT / SHIFT, key list, conflict line.
- (IBAction)modifySelected:(id)sender {
    if (!self.hasSelection) return;
    Row r = self.selected;
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    TPKeyBinding *cur = [self bindingForRow:r];
    BOOL mac = reg.scheme == TPShortcutSchemeMac;
    BOOL named = _tab == TPMapperTabMacros || _tab == TPMapperTabRunCommands;
    NSAlert *a = [NSAlert new];
    a.messageText = @"Shortcut";
    a.informativeText = r.name;
    NSView *acc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 150)];
    NSTextField *nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(60, 122, 296, 24)];
    nameField.stringValue = r.name;
    nameField.enabled = named;
    NSTextField *nl = [NSTextField labelWithString:@"Name:"]; nl.frame = NSMakeRect(0, 125, 56, 18);
    NSButton *ctrl = [NSButton checkboxWithTitle:mac ? @"Ctrl (⌘)" : @"Ctrl" target:nil action:nil];
    NSButton *alt = [NSButton checkboxWithTitle:mac ? @"Alt (⌥)" : @"Alt" target:nil action:nil];
    NSButton *shift = [NSButton checkboxWithTitle:mac ? @"Shift (⇧)" : @"Shift" target:nil action:nil];
    NSButton *control = [NSButton checkboxWithTitle:@"Control (⌃)" target:nil action:nil];
    ctrl.frame = NSMakeRect(0, 92, 110, 20); alt.frame = NSMakeRect(0, 70, 110, 20); shift.frame = NSMakeRect(0, 48, 110, 20); control.frame = NSMakeRect(0, 26, 120, 20);
    control.hidden = !mac;
    NSEventModifierFlags m = cur.modifiers;
    ctrl.state = (mac ? (m & NSEventModifierFlagCommand) : (m & NSEventModifierFlagControl)) != 0;
    alt.state = (m & NSEventModifierFlagOption) != 0;
    shift.state = (m & NSEventModifierFlagShift) != 0;
    control.state = mac && (m & NSEventModifierFlagControl);
    NSPopUpButton *key = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, 70, 206, 26)];
    [key addItemWithTitle:@"None"];
    for (NSString *k in [TPCommandRegistry assignableKeys]) { [key addItemWithTitle:[TPCommandRegistry displayNameForKey:k]]; key.lastItem.representedObject = k; }
    if (cur && !cur.isEmpty) for (NSMenuItem *mi in key.itemArray) if ([mi.representedObject isEqualToString:cur.keyEquivalent.lowercaseString]) [key selectItem:mi];
    for (NSView *x in @[nl, nameField, ctrl, alt, shift, control, key]) [acc addSubview:x];
    a.accessoryView = acc;
    [a addButtonWithTitle:@"OK"];
    [a addButtonWithTitle:@"Cancel"];
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    NSString *k = key.selectedItem.representedObject;
    TPKeyBinding *nb = nil;
    if (k.length) {
        NSEventModifierFlags nm = 0;
        if (ctrl.state) nm |= mac ? NSEventModifierFlagCommand : NSEventModifierFlagControl;
        if (alt.state) nm |= NSEventModifierFlagOption;
        if (shift.state) nm |= NSEventModifierFlagShift;
        if (control.state && mac) nm |= NSEventModifierFlagControl;
        nb = [TPKeyBinding bindingWithKey:k modifiers:nm command:r.ident];
    }
    [self assignBinding:nb name:named ? nameField.stringValue : nil];
}

@end
