// Textpad++ — central command registry. GPL-3.0-or-later.
#import "commands/CommandRegistry.h"
#import "app/Localization.h"
#import "commands/ScintillaKeys.h"

#include <map>
#include <string>
#include <vector>

using namespace npp;

struct MenuRow { int depth; int kind; const char *label; int cmd; const char *idName; };
static const MenuRow kMenuRows[] = {
#include "NppMenuTable.inc"
};

static NSString *macDescriptionFor(NSString *key, NSEventModifierFlags m);
static NSString *windowsDescriptionFor(NSString *key, NSEventModifierFlags m);
struct ShortcutRow { int cmd; const char *vk; bool ctrl, alt, shift; const char *name; };
static const ShortcutRow kShortcutRows[] = {
#include "NppShortcutTable.inc"
};

@implementation TPKeyBinding
+ (instancetype)bindingWithKey:(NSString *)key modifiers:(NSEventModifierFlags)m command:(int)cmd {
    TPKeyBinding *b = [TPKeyBinding new];
    b.keyEquivalent = key ?: @"";
    b.modifiers = m;
    b.command = cmd;
    b.macDescription = b.keyEquivalent.length ? macDescriptionFor(b.keyEquivalent, m) : @"";
    b.windowsDescription = b.keyEquivalent.length ? windowsDescriptionFor(b.keyEquivalent, m) : @"";
    return b;
}
- (BOOL)isEmpty { return self.keyEquivalent.length == 0; }
- (BOOL)matchesKey:(NSString *)key modifiers:(NSEventModifierFlags)m {
    const NSEventModifierFlags relevant = NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift | NSEventModifierFlagNumericPad;
    return !self.isEmpty && (self.modifiers & relevant) == (m & relevant) && [self.keyEquivalent.lowercaseString isEqualToString:key.lowercaseString];
}
@end

struct Entry {
    TPCommandHandler handler = nil;
    TPCommandPredicate enabled = nil;
    TPCommandPredicate checked = nil;
};

// Labels that must carry the Textpad++ identity or a macOS equivalent.
static NSDictionary<NSNumber *, NSString *> *labelOverrides() {
    static NSDictionary *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = @{
            @(IDM_ABOUT): @"About Textpad++",
            @(IDM_UPDATE_NPP): @"Update Textpad++",
            @(IDM_FILE_DELETE): @"Move to Trash",
            @(IDM_FILE_OPEN_FOLDER): @"Finder",
            @(IDM_FILE_OPEN_CMD): @"Terminal",
            @(IDM_FILE_EXIT): @"Exit",
            @(IDM_EDIT_OPENSELECTEDFILEFOLDERINEXPLORER): @"Open Containing Folder in Finder",
            @(IDM_EDIT_TOGGLESYSTEMREADONLY): @"Read-Only Attribute on Disk",
            @(IDM_VIEW_IN_IE): @"Safari",
        };
    });
    return d;
}

static NSString *cleanLabel(const char *raw) {
    NSString *s = @(raw);
    // RC mnemonics: "&&" is a literal ampersand, single "&" marks the access key.
    s = [s stringByReplacingOccurrencesOfString:@"&&" withString:@"\u0001"];
    s = [s stringByReplacingOccurrencesOfString:@"&" withString:@""];
    s = [s stringByReplacingOccurrencesOfString:@"\u0001" withString:@"&"];
    return s;
}

static NSString *popupLabel(const char *raw) {
    NSString *s = cleanLabel(raw);
    if ([s isEqualToString:@"?"]) return @"Help";
    return s;
}

// ---------------------------------------------------------------- key mapping
static NSString *keyForVK(const std::string &vk, BOOL *numpad) {
    *numpad = NO;
    if (vk.size() == 4 && vk.rfind("VK_", 0) == 0) {
        char c = vk[3];
        if (c >= 'A' && c <= 'Z') return [NSString stringWithFormat:@"%c", c - 'A' + 'a'];
        if (c >= '0' && c <= '9') return [NSString stringWithFormat:@"%c", c];
    }
    static const std::map<std::string, unichar> special = {
        {"VK_F1", NSF1FunctionKey}, {"VK_F2", NSF2FunctionKey}, {"VK_F3", NSF3FunctionKey}, {"VK_F4", NSF4FunctionKey},
        {"VK_F5", NSF5FunctionKey}, {"VK_F6", NSF6FunctionKey}, {"VK_F7", NSF7FunctionKey}, {"VK_F8", NSF8FunctionKey},
        {"VK_F9", NSF9FunctionKey}, {"VK_F10", NSF10FunctionKey}, {"VK_F11", NSF11FunctionKey}, {"VK_F12", NSF12FunctionKey},
        {"VK_UP", NSUpArrowFunctionKey}, {"VK_DOWN", NSDownArrowFunctionKey}, {"VK_LEFT", NSLeftArrowFunctionKey},
        {"VK_RIGHT", NSRightArrowFunctionKey}, {"VK_HOME", NSHomeFunctionKey}, {"VK_END", NSEndFunctionKey},
        {"VK_PRIOR", NSPageUpFunctionKey}, {"VK_NEXT", NSPageDownFunctionKey}, {"VK_DELETE", NSDeleteFunctionKey},
        {"VK_INSERT", NSInsertFunctionKey}, {"VK_RETURN", '\r'}, {"VK_TAB", '\t'}, {"VK_SPACE", ' '},
        {"VK_BACK", NSBackspaceCharacter}, {"VK_ESCAPE", 0x1B}, {"VK_ADD", '+'}, {"VK_SUBTRACT", '-'},
        {"VK_DIVIDE", '/'}, {"VK_MULTIPLY", '*'}, {"VK_OEM_1", ';'}, {"VK_OEM_2", '/'}, {"VK_OEM_3", '`'},
        {"VK_OEM_4", '['}, {"VK_OEM_5", '\\'}, {"VK_OEM_6", ']'}, {"VK_OEM_7", '\''}, {"VK_OEM_PLUS", '='},
        {"VK_OEM_MINUS", '-'}, {"VK_OEM_COMMA", ','}, {"VK_OEM_PERIOD", '.'},
    };
    if (vk.rfind("VK_NUMPAD", 0) == 0 && vk.size() == 10) {
        *numpad = YES;
        return [NSString stringWithFormat:@"%c", vk[9]];
    }
    auto it = special.find(vk);
    if (it == special.end()) return nil;
    unichar ch = it->second;
    return [NSString stringWithCharacters:&ch length:1];
}

static NSString *windowsDescription(const ShortcutRow &r) {
    NSMutableString *s = [NSMutableString string];
    if (r.ctrl) [s appendString:@"Ctrl+"];
    if (r.alt) [s appendString:@"Alt+"];
    if (r.shift) [s appendString:@"Shift+"];
    std::string vk = r.vk;
    std::string k = vk.rfind("VK_", 0) == 0 ? vk.substr(3) : vk;
    static const std::map<std::string, std::string> names = {
        {"PRIOR", "PgUp"}, {"NEXT", "PgDn"}, {"RETURN", "Enter"}, {"BACK", "Backspace"}, {"DELETE", "Del"},
        {"INSERT", "Ins"}, {"ADD", "Num +"}, {"SUBTRACT", "Num -"}, {"DIVIDE", "Num /"}, {"OEM_2", "/"},
        {"OEM_4", "["}, {"OEM_5", "\\"}, {"OEM_6", "]"}};
    auto it = names.find(k);
    if (it != names.end()) k = it->second;
    else if (k.rfind("NUMPAD", 0) == 0) k = "Num " + k.substr(6);
    else if (k.size() > 1) { for (size_t i = 1; i < k.size(); ++i) k[i] = static_cast<char>(tolower(k[i])); }
    [s appendString:@(k.c_str())];
    return s;
}

// Is a Command-based combination reserved by macOS (cannot be delivered to apps or would
// break a core system convention)? Those keep the Control key in the macOS scheme.
static BOOL macReserved(NSString *key, BOOL alt, BOOL shift) {
    if ([key isEqualToString:@" "]) return YES;                          // Spotlight / input sources
    if ([key isEqualToString:@"\t"]) return YES;                         // app switcher
    if ([key isEqualToString:@"q"]) return YES;                          // Quit / Log Out
    if (shift && ([key isEqualToString:@"3"] || [key isEqualToString:@"4"] || [key isEqualToString:@"5"])) return YES;  // screenshots
    if ([key isEqualToString:@"`"]) return YES;                          // window cycling
    if (alt && [key isEqualToString:@"d"]) return YES;                   // Dock hiding
    return NO;
}

static NSString *macDescription(NSString *key, NSEventModifierFlags m, BOOL numpad);
static NSString *macDescriptionFor(NSString *key, NSEventModifierFlags m) {
    return macDescription(key, m & ~NSEventModifierFlagNumericPad, (m & NSEventModifierFlagNumericPad) != 0);
}
// "Ctrl+Alt+Shift+K" in the active scheme's terms (Ctrl = ⌘ in the macOS scheme, ⌃ in the Windows scheme)
static NSString *windowsDescriptionFor(NSString *key, NSEventModifierFlags m) {
    TPShortcutScheme scheme = static_cast<TPShortcutScheme>([[NSUserDefaults standardUserDefaults] integerForKey:@"ShortcutScheme"]);
    NSMutableString *s = [NSMutableString string];
    BOOL ctrl = scheme == TPShortcutSchemeWindows ? (m & NSEventModifierFlagControl) != 0 : (m & NSEventModifierFlagCommand) != 0;
    if (scheme == TPShortcutSchemeMac && (m & NSEventModifierFlagControl)) [s appendString:@"Control+"];
    if (ctrl) [s appendString:@"Ctrl+"];
    if (m & NSEventModifierFlagOption) [s appendString:@"Alt+"];
    if (m & NSEventModifierFlagShift) [s appendString:@"Shift+"];
    NSString *k = macDescription(key, 0, (m & NSEventModifierFlagNumericPad) != 0);
    [s appendString:k];
    return s;
}

static NSString *macDescription(NSString *key, NSEventModifierFlags m, BOOL numpad) {
    NSMutableString *s = [NSMutableString string];
    if (m & NSEventModifierFlagControl) [s appendString:@"⌃"];
    if (m & NSEventModifierFlagOption) [s appendString:@"⌥"];
    if (m & NSEventModifierFlagShift) [s appendString:@"⇧"];
    if (m & NSEventModifierFlagCommand) [s appendString:@"⌘"];
    unichar c = key.length ? [key characterAtIndex:0] : 0;
    NSString *k = key.uppercaseString;
    if (c >= NSF1FunctionKey && c <= NSF12FunctionKey) k = [NSString stringWithFormat:@"F%d", c - NSF1FunctionKey + 1];
    else if (c == NSUpArrowFunctionKey) k = @"↑";
    else if (c == NSDownArrowFunctionKey) k = @"↓";
    else if (c == NSLeftArrowFunctionKey) k = @"←";
    else if (c == NSRightArrowFunctionKey) k = @"→";
    else if (c == NSPageUpFunctionKey) k = @"PgUp";
    else if (c == NSPageDownFunctionKey) k = @"PgDn";
    else if (c == NSDeleteFunctionKey) k = @"⌦";
    else if (c == NSBackspaceCharacter) k = @"⌫";
    else if (c == '\r') k = @"↩";
    else if (c == '\t') k = @"⇥";
    else if (c == ' ') k = @"Space";
    else if (c == NSInsertFunctionKey) k = @"Ins";
    else if (c == 0x1B) k = @"Esc";
    if (numpad) k = [@"Num " stringByAppendingString:k];
    [s appendString:k];
    return s;
}

// ---------------------------------------------------------------- virtual-key codes (shortcuts.xml "Key")
struct VKName { int code; const char *name; };
static const VKName kVKNames[] = {
    {0x08, "VK_BACK"}, {0x09, "VK_TAB"}, {0x0D, "VK_RETURN"}, {0x1B, "VK_ESCAPE"}, {0x20, "VK_SPACE"}, {0x21, "VK_PRIOR"},
    {0x22, "VK_NEXT"}, {0x23, "VK_END"}, {0x24, "VK_HOME"}, {0x25, "VK_LEFT"}, {0x26, "VK_UP"}, {0x27, "VK_RIGHT"},
    {0x28, "VK_DOWN"}, {0x2D, "VK_INSERT"}, {0x2E, "VK_DELETE"}, {0x6A, "VK_MULTIPLY"}, {0x6B, "VK_ADD"}, {0x6D, "VK_SUBTRACT"},
    {0x6F, "VK_DIVIDE"}, {0xBA, "VK_OEM_1"}, {0xBB, "VK_OEM_PLUS"}, {0xBC, "VK_OEM_COMMA"}, {0xBD, "VK_OEM_MINUS"},
    {0xBE, "VK_OEM_PERIOD"}, {0xBF, "VK_OEM_2"}, {0xC0, "VK_OEM_3"}, {0xDB, "VK_OEM_4"}, {0xDC, "VK_OEM_5"}, {0xDD, "VK_OEM_6"},
    {0xDE, "VK_OEM_7"},
};
static std::string vkNameForCode(int code) {
    if ((code >= 'A' && code <= 'Z') || (code >= '0' && code <= '9')) return std::string("VK_") + static_cast<char>(code);
    if (code >= 0x70 && code <= 0x7B) return "VK_F" + std::to_string(code - 0x70 + 1);
    if (code >= 0x60 && code <= 0x69) return "VK_NUMPAD" + std::to_string(code - 0x60);
    for (const VKName &v : kVKNames) if (v.code == code) return v.name;
    return "";
}
static NSString *keyForVK(const std::string &vk, BOOL *numpad);
static int vkCodeForKey(NSString *key, BOOL numpad) {
    for (int code = 1; code < 0xFF; ++code) {
        std::string n = vkNameForCode(code);
        if (n.empty()) continue;
        BOOL np = NO;
        NSString *k = keyForVK(n, &np);
        if (k && np == numpad && [k isEqualToString:key.lowercaseString]) return code;
    }
    return 0;
}

@implementation TPCommandRegistry {
    std::map<int, Entry> _entries;
    NSMutableDictionary<NSNumber *, TPKeyBinding *> *_user;
    NSMutableDictionary<NSNumber *, TPKeyBinding *> *_defaults;
    NSMutableDictionary<NSNumber *, NSString *> *_dynamicLabels;
    NSMutableDictionary<NSNumber *, NSMenuItem *> *_items;
    NSMutableDictionary<NSNumber *, TPKeyBinding *> *_primary;
    NSMutableArray<TPKeyBinding *> *_secondary;
    NSMutableArray<TPKeyBinding *> *_all;
    NSMutableDictionary<NSString *, NSMenu *> *_topMenus;
    NSMutableDictionary<NSNumber *, NSArray<NSString *> *> *_paths;
    NSMutableArray<NSDictionary *> *_extras;
}

+ (instancetype)shared {
    static TPCommandRegistry *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [TPCommandRegistry new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _items = [NSMutableDictionary dictionary];
        _topMenus = [NSMutableDictionary dictionary];
        _paths = [NSMutableDictionary dictionary];
        _user = [NSMutableDictionary dictionary];
        _dynamicLabels = [NSMutableDictionary dictionary];
        _extras = [NSMutableArray array];
        NSNumber *scheme = [[NSUserDefaults standardUserDefaults] objectForKey:@"ShortcutScheme"];
        _scheme = scheme ? static_cast<TPShortcutScheme>(scheme.integerValue) : TPShortcutSchemeMac;
        [self buildBindings];
    }
    return self;
}

- (void)registerCommand:(int)cmd handler:(TPCommandHandler)handler {
    [self registerCommand:cmd handler:handler enabled:nil checked:nil];
}

- (void)registerCommand:(int)cmd handler:(TPCommandHandler)handler enabled:(TPCommandPredicate)enabled checked:(TPCommandPredicate)checked {
    Entry e;
    e.handler = [handler copy];
    e.enabled = [enabled copy];
    e.checked = [checked copy];
    _entries[cmd] = e;
}

- (void)registerCommandsFrom:(int)first to:(int)last handler:(TPCommandHandler)handler enabled:(TPCommandPredicate)enabled checked:(TPCommandPredicate)checked {
    for (int c = first; c <= last; ++c) [self registerCommand:c handler:handler enabled:enabled checked:checked];
}

- (BOOL)hasHandler:(int)cmd { return _entries.count(cmd) && _entries[cmd].handler; }

- (BOOL)isEnabled:(int)cmd {
    auto it = _entries.find(cmd);
    if (it == _entries.end() || !it->second.handler) return NO;
    return it->second.enabled ? it->second.enabled(cmd) : YES;
}

- (BOOL)isChecked:(int)cmd {
    auto it = _entries.find(cmd);
    if (it == _entries.end() || !it->second.checked) return NO;
    return it->second.checked(cmd);
}

- (BOOL)execute:(int)cmd {
    if (![self isEnabled:cmd]) return NO;
    if (self.willExecute) self.willExecute(cmd);
    TPCommandHandler h = _entries[cmd].handler;
    h(cmd);
    return YES;
}

- (void)menuCommand:(id)sender {
    [self execute:static_cast<int>([sender tag])];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action != @selector(menuCommand:)) return YES;
    int cmd = static_cast<int>(item.tag);
    item.state = [self isChecked:cmd] ? NSControlStateValueOn : NSControlStateValueOff;
    return [self isEnabled:cmd];
}

// ---------------------------------------------------------------- bindings
- (void)setScheme:(TPShortcutScheme)scheme {
    // custom shortcuts keep their upstream meaning (Ctrl = ⌘ or ⌃ depending on the scheme)
    NSMutableDictionary *canonical = [NSMutableDictionary dictionary];
    for (NSNumber *n in _user) canonical[n] = [self upstreamAttributesForBinding:_user[n]];
    _scheme = scheme;
    [[NSUserDefaults standardUserDefaults] setInteger:scheme forKey:@"ShortcutScheme"];
    for (NSNumber *n in canonical) {
        TPKeyBinding *b = [self bindingFromUpstreamAttributes:canonical[n] command:n.intValue];
        if (b) _user[n] = b;
    }
    [self buildBindings];
    for (NSNumber *n in _items) [self applyBindingToItem:_items[n]];
    [[TPScintillaKeys shared] applyToAllViews];   // Windows scheme: upstream Scintilla keys
}

- (void)buildBindings {
    _primary = [NSMutableDictionary dictionary];
    _secondary = [NSMutableArray array];
    _all = [NSMutableArray array];
    std::map<int, std::vector<const ShortcutRow *>> byCmd;
    for (const ShortcutRow &r : kShortcutRows) byCmd[r.cmd].push_back(&r);
    for (auto &kv : byCmd) {
        // primary = the letter/digit binding when a command has several (Cut: Ctrl+X over Shift+Del)
        const ShortcutRow *primary = kv.second.front();
        for (auto *r : kv.second) {
            std::string vk = r->vk;
            if (vk.size() == 4) { primary = r; break; }
        }
        for (auto *r : kv.second) {
            BOOL numpad = NO;
            NSString *key = keyForVK(r->vk, &numpad);
            if (!key) continue;
            NSEventModifierFlags m = 0;
            if (r->alt) m |= NSEventModifierFlagOption;
            if (r->shift) m |= NSEventModifierFlagShift;
            if (r->ctrl) {
                if (_scheme == TPShortcutSchemeWindows || macReserved(key, r->alt, r->shift)) m |= NSEventModifierFlagControl;
                else m |= NSEventModifierFlagCommand;
            }
            if (numpad) m |= NSEventModifierFlagNumericPad;
            TPKeyBinding *b = [TPKeyBinding new];
            b.keyEquivalent = key;
            b.modifiers = m;
            b.command = r->cmd;
            b.windowsDescription = windowsDescription(*r);
            b.macDescription = macDescription(key, m, numpad);
            [_all addObject:b];
            if (r == primary) _primary[@(r->cmd)] = b;
            else [_secondary addObject:b];
        }
    }
    // Zoom commands are bound through Scintilla key definitions upstream (Ctrl+Num+/-//).
    struct { int cmd; NSString *key; } zoom[] = {{IDM_VIEW_ZOOMIN, @"="}, {IDM_VIEW_ZOOMOUT, @"-"}, {IDM_VIEW_ZOOMRESTORE, @"/"}};
    for (auto &z : zoom) {
        if (_primary[@(z.cmd)]) continue;
        TPKeyBinding *b = [TPKeyBinding new];
        b.keyEquivalent = z.key;
        b.modifiers = _scheme == TPShortcutSchemeWindows ? NSEventModifierFlagControl : NSEventModifierFlagCommand;
        b.command = z.cmd;
        b.windowsDescription = z.cmd == IDM_VIEW_ZOOMIN ? @"Ctrl+Num +" : z.cmd == IDM_VIEW_ZOOMOUT ? @"Ctrl+Num -" : @"Ctrl+Num /";
        b.macDescription = macDescription(z.key, b.modifiers, NO);
        _primary[@(z.cmd)] = b;
        [_all addObject:b];
    }
    for (NSDictionary *x in _extras) {   // Textpad++'s own commands
        NSString *key = x[@"key"];
        if (!key.length) continue;
        const int cmd = [x[@"cmd"] intValue];
        NSEventModifierFlags m = 0;
        if ([x[@"alt"] boolValue]) m |= NSEventModifierFlagOption;
        if ([x[@"shift"] boolValue]) m |= NSEventModifierFlagShift;
        if ([x[@"ctrl"] boolValue]) m |= _scheme == TPShortcutSchemeWindows ? NSEventModifierFlagControl : NSEventModifierFlagCommand;
        TPKeyBinding *b = [TPKeyBinding new];
        b.keyEquivalent = key;
        b.modifiers = m;
        b.command = cmd;
        b.windowsDescription = [NSString stringWithFormat:@"%@%@%@%@", [x[@"ctrl"] boolValue] ? @"Ctrl+" : @"", [x[@"alt"] boolValue] ? @"Alt+" : @"",
                                [x[@"shift"] boolValue] ? @"Shift+" : @"", key.uppercaseString];
        b.macDescription = macDescription(key, m, NO);
        _primary[@(cmd)] = b;
        [_all addObject:b];
    }
    _defaults = [_primary mutableCopy];
    // User customisations replace every default binding of the command (upstream: one shortcut per command)
    for (NSNumber *n in _user) {
        int cmd = n.intValue;
        [_primary removeObjectForKey:n];
        NSIndexSet *mine = [_secondary indexesOfObjectsPassingTest:^BOOL(TPKeyBinding *b, NSUInteger i, BOOL *stop) { return b.command == cmd; }];
        [_secondary removeObjectsAtIndexes:mine];
        mine = [_all indexesOfObjectsPassingTest:^BOOL(TPKeyBinding *b, NSUInteger i, BOOL *stop) { return b.command == cmd; }];
        [_all removeObjectsAtIndexes:mine];
        TPKeyBinding *u = _user[n];
        if (!u.isEmpty) {
            TPKeyBinding *b = u;
            _primary[n] = b;
            [_all addObject:b];
        }
    }
}

- (void)setUserBinding:(TPKeyBinding *)binding forCommand:(int)cmd {
    if (binding) _user[@(cmd)] = [TPKeyBinding bindingWithKey:binding.keyEquivalent modifiers:binding.modifiers command:cmd];
    else [_user removeObjectForKey:@(cmd)];
    [self reapplyBindings];
}
- (TPKeyBinding *)userBindingForCommand:(int)cmd { return _user[@(cmd)]; }
- (NSArray<NSNumber *> *)userBoundCommands { return [_user.allKeys sortedArrayUsingSelector:@selector(compare:)]; }
- (TPKeyBinding *)defaultBindingForCommand:(int)cmd { return _defaults[@(cmd)]; }

- (NSArray<NSNumber *> *)commandsBoundToKey:(NSString *)key modifiers:(NSEventModifierFlags)m {
    NSMutableArray *r = [NSMutableArray array];
    for (TPKeyBinding *b in _all) if ([b matchesKey:key modifiers:m] && ![r containsObject:@(b.command)]) [r addObject:@(b.command)];
    return r;
}

- (void)setLabel:(NSString *)label forDynamicCommand:(int)cmd {
    if (label) _dynamicLabels[@(cmd)] = label; else [_dynamicLabels removeObjectForKey:@(cmd)];
}

- (void)reapplyBindings {
    [self buildBindings];
    for (NSNumber *n in _items) [self applyBindingToItem:_items[n]];
}

- (NSDictionary<NSString *, NSString *> *)upstreamAttributesForBinding:(TPKeyBinding *)b {
    if (!b || b.isEmpty) return @{@"Ctrl": @"no", @"Alt": @"no", @"Shift": @"no", @"Key": @"0"};
    NSEventModifierFlags m = b.modifiers;
    BOOL ctrl = _scheme == TPShortcutSchemeWindows ? (m & NSEventModifierFlagControl) != 0 : (m & NSEventModifierFlagCommand) != 0;
    BOOL control = _scheme == TPShortcutSchemeMac && (m & NSEventModifierFlagControl);
    NSMutableDictionary *d = [@{@"Ctrl": ctrl ? @"yes" : @"no", @"Alt": (m & NSEventModifierFlagOption) ? @"yes" : @"no",
                                @"Shift": (m & NSEventModifierFlagShift) ? @"yes" : @"no",
                                @"Key": [@(vkCodeForKey(b.keyEquivalent, (m & NSEventModifierFlagNumericPad) != 0)) stringValue]} mutableCopy];
    if (control) d[@"Control"] = @"yes";
    return d;
}

- (TPKeyBinding *)bindingFromUpstreamAttributes:(NSDictionary<NSString *, NSString *> *)a command:(int)cmd {
    int code = [a[@"Key"] intValue];
    if (code == 0) return [TPKeyBinding bindingWithKey:@"" modifiers:0 command:cmd];
    BOOL numpad = NO;
    NSString *key = keyForVK(vkNameForCode(code), &numpad);
    if (!key) return nil;
    NSEventModifierFlags m = 0;
    if ([a[@"Alt"] isEqualToString:@"yes"]) m |= NSEventModifierFlagOption;
    if ([a[@"Shift"] isEqualToString:@"yes"]) m |= NSEventModifierFlagShift;
    if ([a[@"Control"] isEqualToString:@"yes"]) m |= NSEventModifierFlagControl;
    if ([a[@"Ctrl"] isEqualToString:@"yes"]) m |= _scheme == TPShortcutSchemeWindows ? NSEventModifierFlagControl : NSEventModifierFlagCommand;
    if (numpad) m |= NSEventModifierFlagNumericPad;
    return [TPKeyBinding bindingWithKey:key modifiers:m command:cmd];
}

+ (NSArray<NSString *> *)assignableKeys {
    static NSArray *keys;
    if (!keys) {
        NSMutableArray *k = [NSMutableArray array];
        for (char c = 'a'; c <= 'z'; ++c) [k addObject:[NSString stringWithFormat:@"%c", c]];
        for (char c = '0'; c <= '9'; ++c) [k addObject:[NSString stringWithFormat:@"%c", c]];
        for (int f = 0; f < 12; ++f) { unichar ch = static_cast<unichar>(NSF1FunctionKey + f); [k addObject:[NSString stringWithCharacters:&ch length:1]]; }
        unichar specials[] = {NSUpArrowFunctionKey, NSDownArrowFunctionKey, NSLeftArrowFunctionKey, NSRightArrowFunctionKey, NSHomeFunctionKey,
                              NSEndFunctionKey, NSPageUpFunctionKey, NSPageDownFunctionKey, NSDeleteFunctionKey, NSInsertFunctionKey, NSBackspaceCharacter,
                              '\r', '\t', ' ', 0x1B, ';', '=', ',', '-', '.', '/', '`', '[', '\\', ']', '\''};
        for (unichar ch : specials) [k addObject:[NSString stringWithCharacters:&ch length:1]];
        keys = k;
    }
    return keys;
}

+ (NSString *)displayNameForKey:(NSString *)key { return macDescriptionFor(key, 0); }

- (TPKeyBinding *)primaryBindingForCommand:(int)cmd { return _primary[@(cmd)]; }
- (NSArray<TPKeyBinding *> *)allBindings { return _all; }

- (void)applyBindingToItem:(NSMenuItem *)item {
    TPKeyBinding *b = _primary[@(item.tag)];
    if (b) {
        item.keyEquivalent = b.keyEquivalent;
        item.keyEquivalentModifierMask = b.modifiers;
    } else {
        item.keyEquivalent = @"";
        item.keyEquivalentModifierMask = 0;
    }
}

- (BOOL)handleKeyEvent:(NSEvent *)event {
    NSEventModifierFlags relevant = NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift;
    NSEventModifierFlags m = event.modifierFlags & relevant;
    NSString *chars = event.charactersIgnoringModifiers.lowercaseString;
    BOOL numpad = (event.modifierFlags & NSEventModifierFlagNumericPad) != 0;
    if (!chars.length) return NO;
    // Shift+Tab arrives as backtab
    if ([chars characterAtIndex:0] == 0x19) chars = @"\t";
    for (TPKeyBinding *b in _secondary) {
        NSEventModifierFlags bm = b.modifiers & relevant;
        BOOL bNum = (b.modifiers & NSEventModifierFlagNumericPad) != 0;
        if (bm == m && bNum == numpad && [b.keyEquivalent isEqualToString:chars]) {
            if ([self isEnabled:b.command]) { [self execute:b.command]; return YES; }
        }
    }
    // Primary bindings for commands that have no menu item (e.g. IDC_NEXT_DOC) or Control-based ones
    for (NSNumber *n in _primary) {
        TPKeyBinding *b = _primary[n];
        if (_items[n] && !(b.modifiers & NSEventModifierFlagControl)) continue;  // menu handles it
        NSEventModifierFlags bm = b.modifiers & relevant;
        BOOL bNum = (b.modifiers & NSEventModifierFlagNumericPad) != 0;
        if (bm == m && bNum == numpad && [b.keyEquivalent isEqualToString:chars]) {
            if ([self isEnabled:b.command]) { [self execute:b.command]; return YES; }
        }
    }
    return NO;
}

// ---------------------------------------------------------------- menus
- (NSMenuItem *)makeItemForCommand:(int)cmd {
    NSString *label = [self labelForCommand:cmd];
    NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:label action:@selector(menuCommand:) keyEquivalent:@""];
    mi.target = self;
    mi.tag = cmd;
    return mi;
}

- (NSString *)labelForCommand:(int)cmd {
    if (NSString *d = _dynamicLabels[@(cmd)]) return d;
    if (NSString *t = [[TPLocalization shared] labelForCommand:cmd]) return t;   // Preferences > Localization
    NSString *o = labelOverrides()[@(cmd)];
    if (o) return o;
    for (const MenuRow &r : kMenuRows) if (r.kind == 0 && r.cmd == cmd) return cleanLabel(r.label);
    return @"";
}

- (NSString *)idNameForCommand:(int)cmd {
    for (const MenuRow &r : kMenuRows) if (r.kind == 0 && r.cmd == cmd) return @(r.idName);
    return @"";
}

- (NSArray<NSNumber *> *)allMenuCommands {
    NSMutableArray *a = [NSMutableArray array];
    for (const MenuRow &r : kMenuRows) if (r.kind == 0) [a addObject:@(r.cmd)];
    [a addObjectsFromArray:self.extraCommands];
    return a;
}

- (NSArray<NSNumber *> *)extraCommands {
    NSMutableArray *a = [NSMutableArray array];
    for (NSDictionary *x in _extras) [a addObject:x[@"cmd"]];
    return a;
}

- (void)addExtraCommand:(int)cmd label:(NSString *)label menu:(NSString *)menu submenu:(NSString *)submenu after:(int)after
        separatorBefore:(BOOL)separator key:(NSString *)key ctrl:(BOOL)ctrl alt:(BOOL)alt shift:(BOOL)shift {
    for (NSDictionary *x in _extras) if ([x[@"cmd"] intValue] == cmd) return;
    NSDictionary *x = @{@"cmd": @(cmd), @"label": label, @"menu": menu, @"submenu": submenu ?: @"", @"after": @(after), @"sep": @(separator),
                        @"key": key ?: @"", @"ctrl": @(ctrl), @"alt": @(alt), @"shift": @(shift)};
    [_extras addObject:x];
    _dynamicLabels[@(cmd)] = label;
    [self buildBindings];
    if (_hasBuiltMainMenu) [self insertExtra:x];
    for (NSNumber *n in _items) [self applyBindingToItem:_items[n]];
}

- (void)insertExtra:(NSDictionary *)x {
    NSMenu *m = _topMenus[x[@"menu"]];
    if (!m) return;
    NSString *subTitle = x[@"submenu"];
    NSMutableArray *path = [NSMutableArray arrayWithObject:x[@"menu"]];
    if (subTitle.length) {
        NSMenuItem *si = [m itemWithTitle:subTitle];
        if (!si.submenu) {
            si = [[NSMenuItem alloc] initWithTitle:subTitle action:nil keyEquivalent:@""];
            si.submenu = [[NSMenu alloc] initWithTitle:subTitle];
            [m addItem:si];
        }
        m = si.submenu;
        [path addObject:subTitle];
    }
    const int cmd = [x[@"cmd"] intValue];
    if (NSMenuItem *old = _items[@(cmd)]) [old.menu removeItem:old];
    NSMenuItem *mi = [self makeItemForCommand:cmd];
    mi.title = x[@"label"];
    [self applyBindingToItem:mi];
    NSInteger at = m.numberOfItems;
    if (int after = [x[@"after"] intValue]) {
        const NSInteger k = [m indexOfItemWithTag:after];
        if (k >= 0) at = k + 1;
        // keep several extras after the same item in the order they were added
        while (at < m.numberOfItems && [_dynamicLabels objectForKey:@([m itemAtIndex:at].tag)] && [m itemAtIndex:at].tag >= 24000) ++at;
    }
    if ([x[@"sep"] boolValue]) [m insertItem:[NSMenuItem separatorItem] atIndex:at++];
    [m insertItem:mi atIndex:at];
    _items[@(cmd)] = mi;
    [path addObject:mi.title];
    _paths[@(cmd)] = path;
}

- (NSArray<NSString *> *)menuPathForCommand:(int)cmd { return _paths[@(cmd)] ?: @[]; }
- (NSMenuItem *)menuItemForCommand:(int)cmd { return _items[@(cmd)]; }
- (NSMenu *)topLevelMenuNamed:(NSString *)title { return _topMenus[title]; }

- (NSMenu *)buildMainMenu {
    NSMenu *main = [[NSMenu alloc] initWithTitle:@"MainMenu"];

    // macOS application menu (Textpad++)
    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"Textpad++" action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Textpad++"];
    NSMenuItem *about = [self makeItemForCommand:IDM_ABOUT];
    [appMenu addItem:about];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *prefs = [self makeItemForCommand:IDM_SETTING_PREFERENCE];
    prefs.title = @"Settings…";
    prefs.keyEquivalent = @",";
    prefs.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [appMenu addItem:prefs];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *services = [[NSMenuItem alloc] initWithTitle:@"Services" action:nil keyEquivalent:@""];
    NSMenu *servicesMenu = [[NSMenu alloc] initWithTitle:@"Services"];
    services.submenu = servicesMenu;
    NSApp.servicesMenu = servicesMenu;
    [appMenu addItem:services];
    [appMenu addItem:[NSMenuItem separatorItem]];
    // Cmd+H is Replace (Notepad++ Ctrl+H), so Hide has no shortcut here.
    [appMenu addItemWithTitle:@"Hide Textpad++" action:@selector(hide:) keyEquivalent:@""];
    NSMenuItem *hideOthers = [appMenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@""];
    (void)hideOthers;
    [appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quit = [self makeItemForCommand:IDM_FILE_EXIT];
    quit.title = @"Quit Textpad++";
    quit.keyEquivalent = @"q";
    quit.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [appMenu addItem:quit];
    appItem.submenu = appMenu;
    [main addItem:appItem];

    NSMutableArray<NSMenu *> *stack = [NSMutableArray arrayWithObject:main];
    NSMutableArray<NSString *> *pathStack = [NSMutableArray array];
    for (const MenuRow &r : kMenuRows) {
        while ((NSInteger)stack.count > r.depth + 1) { [stack removeLastObject]; [pathStack removeLastObject]; }
        NSMenu *parent = stack.lastObject;
        if (r.kind == 2) {
            [parent addItem:[NSMenuItem separatorItem]];
        } else if (r.kind == 1) {
            NSString *title = popupLabel(r.label);
            NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
            NSMenu *sub = [[NSMenu alloc] initWithTitle:title];
            sub.autoenablesItems = YES;
            mi.submenu = sub;
            [parent addItem:mi];
            [stack addObject:sub];
            [pathStack addObject:title];
            if (r.depth == 0) _topMenus[title] = sub;
        } else {
            NSMenuItem *mi = [self makeItemForCommand:r.cmd];
            NSString *o = labelOverrides()[@(r.cmd)];
            mi.title = o ?: cleanLabel(r.label);
            if (r.cmd == IDM_WINDOW_MRU_FIRST) { mi.hidden = YES; }
            [self applyBindingToItem:mi];
            [parent addItem:mi];
            if (!_items[@(r.cmd)]) {
                _items[@(r.cmd)] = mi;
                NSMutableArray *p = [pathStack mutableCopy];
                [p addObject:mi.title];
                _paths[@(r.cmd)] = p;
            }
        }
    }
    _hasBuiltMainMenu = YES;
    for (NSDictionary *x in _extras) [self insertExtra:x];
    return main;
}

@end
