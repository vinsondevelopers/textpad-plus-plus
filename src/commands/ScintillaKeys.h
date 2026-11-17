// Textpad++ — Scintilla command keys (upstream scintKeyDefs + shortcuts.xml <ScintillaKeys>, Shortcut Mapper
// "Scintilla commands" tab). macOS scheme: Scintilla Cocoa's native macOS keys; Windows scheme: upstream's
// Notepad++ keys (Ctrl = Control). User assignments replace a command's keys in either scheme. GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>
#import "ScintillaView.h"

@class TPKeyBinding;

NS_ASSUME_NONNULL_BEGIN

@interface TPScintillaKey : NSObject
@property (nonatomic) int message;          // SCI_*
@property (nonatomic, copy) NSString *name; // "SCI_WORDLEFT"
@property (nonatomic) int menuCommand;      // != 0: the key belongs to that menu command (edited there)
@end

@interface TPScintillaKeys : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSArray<TPScintillaKey *> *keys;     // one row per command (upstream order)
- (void)registerView:(ScintillaView *)view;                          // views to keep in sync
- (void)applyToAllViews;                                             // after a scheme or user change
- (NSArray<TPKeyBinding *> *)bindingsForMessage:(int)message;        // effective keys in the active scheme
- (nullable TPKeyBinding *)userBindingForMessage:(int)message;
- (void)setUserBinding:(nullable TPKeyBinding *)binding forMessage:(int)message;   // nil = default keys
- (NSArray<NSNumber *> *)userBoundMessages;
- (NSArray<NSNumber *> *)messagesBoundToKey:(NSString *)key modifiers:(NSEventModifierFlags)modifiers;
- (int)keyDefinitionForBinding:(TPKeyBinding *)binding;              // SCI_ASSIGNCMDKEY key definition
@end

NS_ASSUME_NONNULL_END
