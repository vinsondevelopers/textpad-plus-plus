// Textpad++ — Notepad++ icon toolbar ("Standard icons: small", the upstream light-mode default).
// GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface TPToolbarView : NSView
- (void)refreshStates;   // re-query enabled/checked state from the command registry
- (void)reloadIcons;     // Preferences > Toolbar icon set / Dark Mode
@property (nonatomic, readonly) CGFloat preferredHeight;
- (nullable NSImage *)imageForCommand:(int)cmd;   // the enabled-state icon of a button
- (nullable NSString *)tooltipForCommand:(int)cmd; // "Name (shortcut)" and what the button does
- (void)refreshTooltips;
// plugin buttons (NPPM_ADDTOOLBARICON_FORDARKMODE), after a separator at the end, as upstream
- (void)addPluginButton:(int)cmd image:(nullable NSImage *)light darkImage:(nullable NSImage *)dark standardImage:(nullable NSImage *)standard tooltip:(NSString *)tip;
- (void)removePluginButton:(int)cmd;
@property (nonatomic, readonly) NSArray<NSNumber *> *pluginButtonCommands;
@end

@interface TPStatusBarView : NSView
- (void)setText:(NSString *)text forPart:(NSInteger)part;   // 0 doc type, 1 length/lines, 2 Ln/Col/Pos, 3 EOL, 4 encoding, 5 INS/OVR
- (NSString *)textForPart:(NSInteger)part;
@end

NS_ASSUME_NONNULL_END
