// Textpad++ — central command registry (upstream equivalent: the WM_COMMAND switch in
// NppCommands.cpp + Shortcut Mapper tables). One implementation per command id, reachable
// from menus, toolbar, keyboard shortcuts, context menus, macros and the self-test.
// GPL-3.0-or-later.
#pragma once

#import <Cocoa/Cocoa.h>
#include "NppCommandIds.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^TPCommandHandler)(int cmd);
typedef BOOL (^TPCommandPredicate)(int cmd);

typedef NS_ENUM(NSInteger, TPShortcutScheme) {
    TPShortcutSchemeMac = 0,      // Ctrl -> Command (with documented exceptions)
    TPShortcutSchemeWindows = 1,  // Ctrl -> Control, exactly as Notepad++
};

@interface TPKeyBinding : NSObject
@property (nonatomic, copy) NSString *keyEquivalent;
@property (nonatomic) NSEventModifierFlags modifiers;
@property (nonatomic) int command;
@property (nonatomic, copy) NSString *windowsDescription;   // e.g. "Ctrl+Shift+F"
@property (nonatomic, copy) NSString *macDescription;       // e.g. "⇧⌘F"
// A binding for the active scheme; an empty key means "no shortcut" (Shortcut Mapper > Clear).
+ (instancetype)bindingWithKey:(NSString *)key modifiers:(NSEventModifierFlags)modifiers command:(int)cmd;
@property (nonatomic, readonly) BOOL isEmpty;
- (BOOL)matchesKey:(NSString *)key modifiers:(NSEventModifierFlags)modifiers;
@end

// Dynamic command ranges (upstream resource.h): saved macros and Run menu commands
enum : int { TP_ID_MACRO = 20000, TP_ID_MACRO_LIMIT = 20499, TP_ID_USER_CMD = 21000, TP_ID_USER_CMD_LIMIT = 21499 };

@interface TPCommandRegistry : NSObject <NSMenuItemValidation>

+ (instancetype)shared;

- (void)registerCommand:(int)cmd handler:(TPCommandHandler)handler;
- (void)registerCommand:(int)cmd handler:(TPCommandHandler)handler
                enabled:(nullable TPCommandPredicate)enabled checked:(nullable TPCommandPredicate)checked;
- (void)registerCommandsFrom:(int)first to:(int)last handler:(TPCommandHandler)handler
                     enabled:(nullable TPCommandPredicate)enabled checked:(nullable TPCommandPredicate)checked;

- (BOOL)hasHandler:(int)cmd;
- (BOOL)isEnabled:(int)cmd;
- (BOOL)isChecked:(int)cmd;
- (BOOL)execute:(int)cmd;                       // NO when there is no handler or it is disabled

@property (nonatomic, copy, nullable) void (^willExecute)(int cmd);   // macro recorder hook
@property (nonatomic) TPShortcutScheme scheme;

// Menus generated from the upstream resource (NppMenuTable.inc)
- (NSMenu *)buildMainMenu;
- (nullable NSMenuItem *)menuItemForCommand:(int)cmd;
- (nullable NSMenu *)topLevelMenuNamed:(NSString *)title;     // "File", "Edit", ...
- (NSString *)labelForCommand:(int)cmd;                       // cleaned label ("" if unknown)
- (NSString *)idNameForCommand:(int)cmd;                      // "IDM_FILE_NEW"
- (NSArray<NSNumber *> *)allMenuCommands;
@property (nonatomic, readonly) BOOL hasBuiltMainMenu;                   // menuPathForCommand: answers after this
- (NSArray<NSString *> *)menuPathForCommand:(int)cmd;          // ["File", "Close Multiple Documents", "..."]

// Keyboard
- (nullable TPKeyBinding *)primaryBindingForCommand:(int)cmd;
- (NSArray<TPKeyBinding *> *)allBindings;
- (BOOL)handleKeyEvent:(NSEvent *)event;                      // secondary bindings not representable in menus
- (NSMenuItem *)makeItemForCommand:(int)cmd;                  // for context menus / tab menu
- (void)applyBindingToItem:(NSMenuItem *)item;                // key equivalent of the item's command (tag)

// Shortcut customisation (Shortcut Mapper, shortcuts.xml <InternalCommands>, macro / Run command shortcuts)
- (void)setUserBinding:(nullable TPKeyBinding *)binding forCommand:(int)cmd;   // nil = back to the default
- (nullable TPKeyBinding *)userBindingForCommand:(int)cmd;
- (NSArray<NSNumber *> *)userBoundCommands;
- (nullable TPKeyBinding *)defaultBindingForCommand:(int)cmd;
- (NSArray<NSNumber *> *)commandsBoundToKey:(NSString *)key modifiers:(NSEventModifierFlags)modifiers;
- (void)setLabel:(nullable NSString *)label forDynamicCommand:(int)cmd;      // macros / Run commands
// Textpad++'s own commands (ids 24000+, commands/ExtraCommands.h): a menu item in `menu` (> `submenu`), after
// `after` (0 = at the end), with a default shortcut given the upstream way (Ctrl = ⌘ in the Mac scheme)
- (void)addExtraCommand:(int)cmd label:(NSString *)label menu:(NSString *)menu submenu:(nullable NSString *)submenu after:(int)after
        separatorBefore:(BOOL)separator key:(nullable NSString *)key ctrl:(BOOL)ctrl alt:(BOOL)alt shift:(BOOL)shift;
- (NSArray<NSNumber *> *)extraCommands;
- (void)reapplyBindings;                                                      // rebuild and refresh menu key equivalents
// shortcuts.xml form: Ctrl / Alt / Shift / Key (Windows virtual-key code) + "Control" for the macOS Control key
- (NSDictionary<NSString *, NSString *> *)upstreamAttributesForBinding:(nullable TPKeyBinding *)binding;
- (nullable TPKeyBinding *)bindingFromUpstreamAttributes:(NSDictionary<NSString *, NSString *> *)attributes command:(int)cmd;
+ (NSArray<NSString *> *)assignableKeys;                                     // keys offered by the shortcut editor
+ (NSString *)displayNameForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
