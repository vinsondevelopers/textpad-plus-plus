// Textpad++ — Plugins > Plugins Admin (upstream PluginsAdminDlg): Available / Updates / Installed / Incompatible.
// There is no online plugin list for macOS plugins, so Available and Updates explain how to install one.
// GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TPPluginsAdminTab) { TPPluginsAdminAvailable = 0, TPPluginsAdminUpdates, TPPluginsAdminInstalled, TPPluginsAdminIncompatible };

@interface TPPluginsAdmin : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
+ (instancetype)shared;
@property (nonatomic) TPPluginsAdminTab tab;
@property (nonatomic, readonly) NSArray<NSArray<NSString *> *> *rows;   // [Plugin, Version, Folder or reason]
@property (nonatomic, readonly) NSTableView *table;
@property (nonatomic, readonly) NSButton *removeButton;
@property (nonatomic, readonly) NSTextField *note;
- (void)reload;
- (BOOL)removeSelected;   // Installed tab: the selected plugin goes to the Trash (after a confirmation)
- (BOOL)installSelected;  // Available / Updates: download, check SHA-256, unpack, import
- (void)refreshList;      // read the online plugin list again
@property (nonatomic, readonly, nullable) NSURL *listURL;
@property (nonatomic, readonly) NSButton *installButton;
@end

NS_ASSUME_NONNULL_END
