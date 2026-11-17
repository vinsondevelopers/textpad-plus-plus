// Textpad++ — interface languages. GPL-3.0-or-later.
#import "app/Localization.h"
#import "app/Preferences.h"
#import "commands/CommandRegistry.h"

namespace { struct MenuPos { int l0, l1, l2; const char *id; }; }
static const MenuPos kPositions[] = {
#include "NppMenuPositions.inc"
};

// "&Fichier" -> "Fichier", "&&" -> "&", and no "\t" accelerator text
static NSString *cleanName(NSString *s) {
    NSRange tab = [s rangeOfString:@"\t"];
    if (tab.location != NSNotFound) s = [s substringToIndex:tab.location];
    s = [s stringByReplacingOccurrencesOfString:@"&&" withString:@"\u0001"];
    s = [s stringByReplacingOccurrencesOfString:@"&" withString:@""];
    return [s stringByReplacingOccurrencesOfString:@"\u0001" withString:@"&"];
}

@implementation TPLocalization {
    NSMutableArray<NSString *> *_names, *_files;
    NSDictionary<NSNumber *, NSString *> *_commands;
    NSMapTable<NSMenuItem *, NSString *> *_originals;   // English titles to go back to
    NSDictionary<NSString *, NSString *> *_dialog;        // normalized English -> translated
    NSMapTable<id, NSString *> *_viewOriginals;          // controls -> their English text
}

// "Find what :" / "&Match case" / "Replace All..." -> "find what" / "match case" / "replace all"
static NSString *dialogKey(NSString *s) {
    NSString *t = cleanName(s ?: @"").lowercaseString;
    t = [t stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" :.…\u00a0\t"]];
    return [[t componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet] componentsJoinedByString:@" "];
}

// every string of a <Dialog> tree, by its element path + id / attribute name
static void collectDialog(NSXMLElement *e, NSString *path, NSMutableDictionary *out) {
    for (NSXMLNode *a in e.attributes) {
        if ([a.name isEqualToString:@"name"] || [a.name hasPrefix:@"title"]) {
            NSString *idv = [e attributeForName:@"id"].stringValue ?: @"";
            out[[NSString stringWithFormat:@"%@#%@#%@", path, idv, a.name]] = a.stringValue ?: @"";
        }
    }
    NSMutableDictionary<NSString *, NSNumber *> *seen = [NSMutableDictionary dictionary];
    for (NSXMLNode *c in e.children) {
        if (c.kind != NSXMLElementKind) continue;
        NSString *n = c.name;
        NSString *idv = [(NSXMLElement *)c attributeForName:@"id"].stringValue;
        const NSInteger k = seen[n].integerValue;
        seen[n] = @(k + 1);
        collectDialog((NSXMLElement *)c, [NSString stringWithFormat:@"%@/%@[%@]", path, n, idv ?: @(k)], out);
    }
}

+ (instancetype)shared {
    static TPLocalization *l;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ l = [TPLocalization new]; });
    return l;
}

- (NSString *)folder { return [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"data/nativeLang"]; }

- (instancetype)init {
    if ((self = [super init])) {
        _currentFile = @"";
        _originals = [NSMapTable weakToStrongObjectsMapTable];
        NSMutableArray *pairs = [NSMutableArray array];
        for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.folder error:nil]) {
            if (![f.pathExtension isEqualToString:@"xml"] || [f isEqualToString:@"english.xml"] || [f hasPrefix:@"english_"]) continue;
            NSData *head = [[NSFileHandle fileHandleForReadingAtPath:[self.folder stringByAppendingPathComponent:f]] readDataOfLength:2048];
            NSString *t = [[NSString alloc] initWithData:head encoding:NSUTF8StringEncoding] ?: @"";
            NSRange r = [t rangeOfString:@"<Native-Langue name=\""];
            if (r.location == NSNotFound) continue;
            NSString *rest = [t substringFromIndex:NSMaxRange(r)];
            NSString *name = [rest substringToIndex:[rest rangeOfString:@"\""].location];
            [pairs addObject:@[name, f]];
        }
        [pairs sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [a[0] localizedCaseInsensitiveCompare:b[0]]; }];
        _names = [NSMutableArray arrayWithObject:@"English"];
        _files = [NSMutableArray arrayWithObject:@""];
        for (NSArray *p in pairs) { [_names addObject:p[0]]; [_files addObject:p[1]]; }
    }
    return self;
}

- (NSArray<NSString *> *)languageNames { return _names; }
- (NSArray<NSString *> *)languageFiles { return _files; }
- (NSString *)labelForCommand:(int)cmd { return _commands[@(cmd)]; }

- (void)setTitle:(NSString *)t ofItem:(NSMenuItem *)mi {
    if (!mi || !t.length) return;
    if (![_originals objectForKey:mi]) [_originals setObject:mi.title forKey:mi];
    mi.title = t;
    if (mi.submenu) mi.submenu.title = t;
}

- (void)restoreEnglish {
    for (NSMenuItem *mi in _originals.keyEnumerator.allObjects) {
        NSString *t = [_originals objectForKey:mi];
        mi.title = t;
        if (mi.submenu) mi.submenu.title = t;
    }
    [_originals removeAllObjects];
}

static void walk(NSMenu *m, void (^f)(NSMenuItem *)) {
    for (NSMenuItem *mi in m.itemArray) { f(mi); if (mi.submenu) walk(mi.submenu, f); }
}

- (NSDictionary *)dialogStringsOf:(NSXMLDocument *)doc {
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    for (NSXMLElement *e in [doc nodesForXPath:@"//Native-Langue/Dialog" error:nil]) collectDialog(e, @"Dialog", m);
    for (NSXMLElement *e in [doc nodesForXPath:@"//Native-Langue/MessageBox" error:nil]) collectDialog(e, @"MessageBox", m);
    return m;
}

- (void)loadDialogStrings:(NSXMLDocument *)doc {
    static NSDictionary *english;
    if (!english) {
        NSData *d = [NSData dataWithContentsOfFile:[self.folder stringByAppendingPathComponent:@"english.xml"]];
        NSXMLDocument *en = d ? [[NSXMLDocument alloc] initWithData:d options:0 error:nil] : nil;
        english = en ? [self dialogStringsOf:en] : @{};
    }
    NSDictionary *mine = [self dialogStringsOf:doc];
    NSMutableDictionary *map = [NSMutableDictionary dictionary];
    for (NSString *k in english) {
        NSString *en = english[k], *tr = mine[k];
        if (!tr.length || !en.length) continue;
        NSString *key = dialogKey(en);
        if (key.length && !map[key]) map[key] = cleanName(tr);
    }
    _dialog = map;
}

- (NSString *)translateDialogString:(NSString *)english {
    if (!_dialog.count || !english.length) return nil;
    NSString *t = _dialog[dialogKey(english)];
    if (!t.length) return nil;
    // keep the original's ending ("…", ":")
    NSString *trimmed = [t stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" :.…"]];
    if ([english hasSuffix:@"…"] || [english hasSuffix:@"..."]) return [trimmed stringByAppendingString:@"…"];
    if ([english hasSuffix:@":"]) return [trimmed stringByAppendingString:@":"];
    return trimmed;
}

- (NSString *)translatedTextFor:(id)control english:(NSString *)current {
    if (!_viewOriginals) _viewOriginals = [NSMapTable weakToStrongObjectsMapTable];
    NSString *en = [_viewOriginals objectForKey:control];
    if (!en) { en = current; if (en) [_viewOriginals setObject:en forKey:control]; }
    return [self translateDialogString:en] ?: en;
}

- (void)translateView:(NSView *)v {
    if ([v isKindOfClass:NSClassFromString(@"ScintillaView")] || [v isKindOfClass:NSTextView.class]) return;
    if ([v isKindOfClass:NSPopUpButton.class]) { /* values, not labels */ }
    else if ([v isKindOfClass:NSButton.class]) {
        NSButton *b = (NSButton *)v;
        if (b.title.length) { NSString *t = [self translatedTextFor:b english:b.title]; if (![t isEqualToString:b.title]) b.title = t; }
    } else if ([v isKindOfClass:NSTextField.class]) {
        NSTextField *f = (NSTextField *)v;
        if (!f.editable && !f.selectable && f.stringValue.length && f.stringValue.length < 120) {
            NSString *t = [self translatedTextFor:f english:f.stringValue];
            if (![t isEqualToString:f.stringValue]) f.stringValue = t;
        }
    } else if ([v isKindOfClass:NSTabView.class]) {
        for (NSTabViewItem *it in ((NSTabView *)v).tabViewItems) {
            NSString *t = [self translatedTextFor:it english:it.label];
            if (![t isEqualToString:it.label]) it.label = t;
            [self translateView:it.view];
        }
    } else if ([v isKindOfClass:NSBox.class]) {
        NSBox *b = (NSBox *)v;
        if (b.title.length && b.titlePosition != NSNoTitle) b.title = [self translatedTextFor:b english:b.title];
    } else if ([v isKindOfClass:NSSegmentedControl.class]) {
        NSSegmentedControl *sc = (NSSegmentedControl *)v;
        for (NSInteger i = 0; i < sc.segmentCount; ++i) {
            NSString *l = [sc labelForSegment:i];
            if (!l.length) continue;
            NSString *key = [NSString stringWithFormat:@"%p:%ld", sc, (long)i];
            (void)key;
            NSString *t = [self translateDialogString:l];
            if (t) [sc setLabel:t forSegment:i];
        }
    } else if ([v isKindOfClass:NSTableView.class]) {
        for (NSTableColumn *c in ((NSTableView *)v).tableColumns) {
            NSString *t = [self translatedTextFor:c english:c.title];
            if (![t isEqualToString:c.title]) c.title = t;
        }
    }
    for (NSView *sub in v.subviews) [self translateView:sub];
}

- (void)translateWindow:(NSWindow *)w {
    if (!w) return;
    if (!_dialog.count && !_viewOriginals.count) return;   // English and never translated
    if (w.title.length) { NSString *t = [self translatedTextFor:w english:w.title]; if (![t isEqualToString:w.title]) w.title = t; }
    if (w.contentView) [self translateView:w.contentView];
}

- (BOOL)applyLanguageFile:(NSString *)file {
    file = file ?: @"";
    if ([file isEqualToString:_currentFile]) return YES;
    [self restoreEnglish];
    _dialog = nil;
    _commands = nil;
    _currentFile = @"";
    if (!file.length || [file isEqualToString:@"English"]) { [[TPCommandRegistry shared] reapplyBindings]; return YES; }
    NSData *d = [NSData dataWithContentsOfFile:[self.folder stringByAppendingPathComponent:file]];
    NSXMLDocument *doc = d ? [[NSXMLDocument alloc] initWithData:d options:0 error:nil] : nil;
    if (!doc) return NO;
    [self loadDialogStrings:doc];
    NSMutableDictionary *cmds = [NSMutableDictionary dictionary];
    for (NSXMLElement *e in [doc nodesForXPath:@"//Native-Langue/Menu/Main/Commands/Item" error:nil]) {
        NSString *idv = [e attributeForName:@"id"].stringValue, *name = [e attributeForName:@"name"].stringValue;
        if (idv.intValue > 0 && name.length) cmds[@(idv.intValue)] = cleanName(name);
    }
    _commands = cmds;
    _currentFile = file;
    NSArray<NSMenuItem *> *tops = NSApp.mainMenu.itemArray;
    // top-level menus (item 0 is the macOS application menu)
    NSMutableDictionary *entries = [NSMutableDictionary dictionary];
    for (NSXMLElement *e in [doc nodesForXPath:@"//Native-Langue/Menu/Main/Entries/Item" error:nil])
        entries[[e attributeForName:@"menuId"].stringValue ?: @""] = cleanName([e attributeForName:@"name"].stringValue ?: @"");
    NSMutableDictionary *subs = [NSMutableDictionary dictionary];
    for (NSXMLElement *e in [doc nodesForXPath:@"//Native-Langue/Menu/Main/SubEntries/Item" error:nil])
        subs[[e attributeForName:@"subMenuId"].stringValue ?: @""] = cleanName([e attributeForName:@"name"].stringValue ?: @"");
    for (const MenuPos &p : kPositions) {
        NSString *pid = @(p.id);
        NSString *name = p.l1 < 0 ? entries[pid] : subs[pid];
        if (!name.length || p.l0 + 1 >= (int)tops.count) continue;
        NSMenuItem *mi = tops[(NSUInteger)(p.l0 + 1)];
        if (p.l1 >= 0) {
            NSMenu *m = mi.submenu;
            if (p.l1 >= m.numberOfItems) continue;
            mi = [m itemAtIndex:p.l1];
            if (p.l2 >= 0) { if (!mi.submenu || p.l2 >= mi.submenu.numberOfItems) continue; mi = [mi.submenu itemAtIndex:p.l2]; }
            if (!mi.submenu) continue;   // the position no longer holds a sub-menu here: leave it
        }
        [self setTitle:name ofItem:mi];
    }
    // every command
    walk(NSApp.mainMenu, ^(NSMenuItem *mi) { NSString *t = mi.tag > 0 ? cmds[@(mi.tag)] : nil; if (t) [self setTitle:t ofItem:mi]; });
    [[TPCommandRegistry shared] reapplyBindings];
    return YES;
}

- (void)applyPreference {
    NSString *v = [TPPrefs s:@"pref.localization"] ?: @"";
    [self applyLanguageFile:[v isEqualToString:@"English"] ? @"" : v];
}

@end
