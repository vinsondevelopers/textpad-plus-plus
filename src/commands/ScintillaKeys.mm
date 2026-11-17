// Textpad++ — Scintilla command keys. GPL-3.0-or-later.
#import "commands/ScintillaKeys.h"
#import "commands/CommandRegistry.h"
#import "app/Sci.h"
#include <map>
#include <string>
#include <vector>

namespace {
struct ScintRow { int message; const char *name; const char *vk; bool ctrl, alt, shift; int menuCommand; };
const ScintRow kScintRows[] = {
#include "NppScintKeyTable.inc"
};
struct NativeRow { int key; int modifiers; int message; };
const NativeRow kNative[] = {
#include "ScintillaCocoaKeyMap.inc"
};
}

@implementation TPScintillaKey
@end

@implementation TPScintillaKeys {
    NSArray<TPScintillaKey *> *_keys;
    NSHashTable<ScintillaView *> *_views;
    NSMutableDictionary<NSNumber *, TPKeyBinding *> *_user;
    std::vector<int> _assigned;   // key definitions changed from Scintilla's native map
}

+ (instancetype)shared {
    static TPScintillaKeys *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [TPScintillaKeys new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _views = [NSHashTable weakObjectsHashTable];
        _user = [NSMutableDictionary dictionary];
        NSMutableArray *keys = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        for (const ScintRow &r : kScintRows) {
            if ([seen containsObject:@(r.message)]) continue;
            [seen addObject:@(r.message)];
            TPScintillaKey *k = [TPScintillaKey new];
            k.message = r.message;
            k.name = @(r.name);
            k.menuCommand = r.menuCommand;
            [keys addObject:k];
        }
        _keys = keys;
    }
    return self;
}

- (NSArray<TPScintillaKey *> *)keys { return _keys; }

// upstream key definition -> binding in the Windows scheme (Ctrl = Control)
static TPKeyBinding *windowsBinding(const ScintRow &r) {
    if (!strcmp(r.vk, "0")) return nil;
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    TPShortcutScheme saved = reg.scheme;
    (void)saved;
    // build through the registry's upstream converter with Ctrl -> Control explicitly
    NSString *vk = @(r.vk);
    int code = 0;
    if (vk.length == 4 && [vk hasPrefix:@"VK_"]) code = [vk characterAtIndex:3];
    NSDictionary *codes = @{@"VK_BACK": @0x08, @"VK_TAB": @0x09, @"VK_RETURN": @0x0D, @"VK_ESCAPE": @0x1B, @"VK_SPACE": @0x20, @"VK_PRIOR": @0x21,
                            @"VK_NEXT": @0x22, @"VK_END": @0x23, @"VK_HOME": @0x24, @"VK_LEFT": @0x25, @"VK_UP": @0x26, @"VK_RIGHT": @0x27,
                            @"VK_DOWN": @0x28, @"VK_INSERT": @0x2D, @"VK_DELETE": @0x2E, @"VK_ADD": @0x6B, @"VK_SUBTRACT": @0x6D, @"VK_DIVIDE": @0x6F,
                            @"VK_MULTIPLY": @0x6A, @"VK_OEM_2": @0xBF, @"VK_OEM_4": @0xDB, @"VK_OEM_5": @0xDC, @"VK_OEM_6": @0xDD};
    if (!code) code = [codes[vk] intValue];
    if ([vk hasPrefix:@"VK_F"] && vk.length <= 6 && [[vk substringFromIndex:4] intValue] > 0) code = 0x70 + [[vk substringFromIndex:4] intValue] - 1;
    if (!code) return nil;
    NSDictionary *attrs = @{@"Ctrl": @"no", @"Control": r.ctrl ? @"yes" : @"no", @"Alt": r.alt ? @"yes" : @"no", @"Shift": r.shift ? @"yes" : @"no",
                            @"Key": [@(code) stringValue]};
    return [reg bindingFromUpstreamAttributes:attrs command:r.message];
}

- (NSArray<TPKeyBinding *> *)bindingsForMessage:(int)message {
    if (TPKeyBinding *u = _user[@(message)]) return u.isEmpty ? @[] : @[u];
    NSMutableArray *r = [NSMutableArray array];
    if ([TPCommandRegistry shared].scheme == TPShortcutSchemeWindows) {
        for (const ScintRow &row : kScintRows)
            if (row.message == message) if (TPKeyBinding *b = windowsBinding(row)) [r addObject:b];
    }
    return r;
}

- (TPKeyBinding *)userBindingForMessage:(int)message { return _user[@(message)]; }
- (NSArray<NSNumber *> *)userBoundMessages { return [_user.allKeys sortedArrayUsingSelector:@selector(compare:)]; }

- (void)setUserBinding:(TPKeyBinding *)binding forMessage:(int)message {
    if (binding) _user[@(message)] = binding; else [_user removeObjectForKey:@(message)];
    [self applyToAllViews];
}

- (NSArray<NSNumber *> *)messagesBoundToKey:(NSString *)key modifiers:(NSEventModifierFlags)m {
    NSMutableArray *r = [NSMutableArray array];
    for (TPScintillaKey *k in _keys) {
        if (k.menuCommand) continue;   // reported through the menu command
        for (TPKeyBinding *b in [self bindingsForMessage:k.message])
            if ([b matchesKey:key modifiers:m]) { [r addObject:@(k.message)]; break; }
    }
    return r;
}

// Scintilla Cocoa: Command = SCMOD_CTRL, Control = SCMOD_META, Option = SCMOD_ALT; letters arrive as typed.
- (int)keyDefinitionForBinding:(TPKeyBinding *)b {
    if (b.isEmpty) return 0;
    unichar c = [b.keyEquivalent characterAtIndex:0];
    const BOOL shift = (b.modifiers & NSEventModifierFlagShift) != 0, numpad = (b.modifiers & NSEventModifierFlagNumericPad) != 0;
    int key = 0;
    switch (c) {
        case NSUpArrowFunctionKey: key = SCK_UP; break;
        case NSDownArrowFunctionKey: key = SCK_DOWN; break;
        case NSLeftArrowFunctionKey: key = SCK_LEFT; break;
        case NSRightArrowFunctionKey: key = SCK_RIGHT; break;
        case NSHomeFunctionKey: key = SCK_HOME; break;
        case NSEndFunctionKey: key = SCK_END; break;
        case NSPageUpFunctionKey: key = SCK_PRIOR; break;
        case NSPageDownFunctionKey: key = SCK_NEXT; break;
        case NSDeleteFunctionKey: key = SCK_DELETE; break;
        case NSInsertFunctionKey: key = SCK_INSERT; break;
        case 0x1B: key = SCK_ESCAPE; break;
        case NSBackspaceCharacter: case 0x7F: key = SCK_BACK; break;
        case '\t': key = SCK_TAB; break;
        case '\r': key = SCK_RETURN; break;
        case '+': key = numpad ? SCK_ADD : '+'; break;
        case '-': key = numpad ? SCK_SUBTRACT : '-'; break;
        case '/': key = numpad ? SCK_DIVIDE : '/'; break;
        default:
            if (c >= 'a' && c <= 'z') key = shift ? c - 'a' + 'A' : c;
            else if (c < 0x80) key = c;
            else return 0;   // function keys F1-F12 are not Scintilla command keys
    }
    int mods = 0;
    if (shift) mods |= SCMOD_SHIFT;
    if (b.modifiers & NSEventModifierFlagCommand) mods |= SCMOD_CTRL;
    if (b.modifiers & NSEventModifierFlagControl) mods |= SCMOD_META;
    if (b.modifiers & NSEventModifierFlagOption) mods |= SCMOD_ALT;
    return key | (mods << 16);
}

- (void)registerView:(ScintillaView *)view {
    [_views addObject:view];
    [self applyToView:view];
}

- (void)applyToView:(ScintillaView *)v {
    // 1. undo earlier assignments: back to Scintilla's native macOS map
    std::map<int, int> native;
    for (const NativeRow &n : kNative) native[n.key | (n.modifiers << 16)] = n.message;
    for (int def : _assigned) {
        auto it = native.find(def);
        if (it != native.end()) SCI(v, SCI_ASSIGNCMDKEY, static_cast<uptr_t>(def), it->second);
        else SCI(v, SCI_CLEARCMDKEY, static_cast<uptr_t>(def));
    }
    // 2. scheme defaults / user keys; a user key for a command also removes that command's native keys
    std::vector<int> assigned;
    for (TPScintillaKey *k in _keys) {
        if (k.menuCommand) continue;   // menu commands own those keys
        BOOL hasUser = _user[@(k.message)] != nil;
        if (hasUser)
            for (const NativeRow &n : kNative)
                if (n.message == k.message) { int def = n.key | (n.modifiers << 16); SCI(v, SCI_CLEARCMDKEY, static_cast<uptr_t>(def)); assigned.push_back(def); }
        for (TPKeyBinding *b in [self bindingsForMessage:k.message]) {
            int def = [self keyDefinitionForBinding:b];
            if (!def) continue;
            SCI(v, SCI_ASSIGNCMDKEY, static_cast<uptr_t>(def), k.message);
            assigned.push_back(def);
        }
    }
    _assigned = assigned;
}

- (void)applyToAllViews {
    std::vector<int> previous = _assigned;
    for (ScintillaView *v in _views.allObjects) { _assigned = previous; [self applyToView:v]; }
}

@end
