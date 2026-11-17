// Textpad++ — View > Command Palette (⇧⌘A): type a few letters of any menu command (plugins, macros and Run
// commands included), see its menu path and shortcut, press Return to run it. GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface TPPaletteEntry : NSObject
@property (nonatomic) int command;
@property (nonatomic, copy) NSString *title;      // "Save As..."
@property (nonatomic, copy) NSString *path;       // "File"
@property (nonatomic, copy) NSString *shortcut;   // "⇧⌘S"
@property (nonatomic) BOOL enabled;
@property (nonatomic) NSInteger score;
@end

@interface TPCommandPalette : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate>
+ (instancetype)shared;
- (void)showOverWindow:(NSWindow *)window;
- (void)showOverWindow:(NSWindow *)window query:(NSString *)query;
- (void)close;
@property (nonatomic, readonly) NSPanel *panel;
@property (nonatomic, readonly) NSArray<TPPaletteEntry *> *results;
- (NSArray<TPPaletteEntry *> *)entriesForQuery:(NSString *)query;   // every command of the menu bar, best matches first
+ (NSInteger)scoreOf:(NSString *)query in:(NSString *)candidate;    // 0 = no match
- (void)runEntry:(TPPaletteEntry *)entry;
@end

NS_ASSUME_NONNULL_END
