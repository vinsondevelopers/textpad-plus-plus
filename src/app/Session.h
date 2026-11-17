// Textpad++ — sessions, session snapshot and periodic backup (upstream: Notepad_plus::saveSession /
// loadSession, NppParameters session XML, backup folder). GPL-3.0-or-later.
#pragma once

#import <Cocoa/Cocoa.h>

@class TPMainWindowController;

NS_ASSUME_NONNULL_BEGIN

@interface TPSession : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSString *supportDirectory;     // ~/Library/Application Support/Textpad++
// Settings files (shortcuts.xml, stylers.xml, themes/, userDefineLangs/, autoCompletion/, preferences.plist):
// <cloud path>/Textpad++ when Preferences > Cloud & Link sets a cloud folder (read at launch, as upstream), else the
// support directory. Session and backups always stay local.
@property (nonatomic, readonly) NSString *settingsDirectory;
@property (nonatomic, readonly) BOOL cloudActive;
- (void)reloadSettingsDirectory;            // re-reads pref.cloudPath (launch; tests)
- (void)exportPreferencesToCloud;           // pref.* -> <cloud>/Textpad++/preferences.plist
- (BOOL)importPreferencesFromCloud;         // the reverse, at launch
- (void)seedCloudFolder:(NSString *)cloudPath;   // copies the current settings files into a newly chosen cloud folder
@property (nonatomic, readonly) NSString *backupDirectory;
@property (nonatomic, readonly) NSString *sessionPath;
@property (nonatomic) BOOL rememberSession;                      // Preferences > Backup: Remember current session
@property (nonatomic) BOOL snapshotEnabled;                      // Enable session snapshot and periodic backup
@property (nonatomic) NSTimeInterval backupInterval;             // upstream default 7 s
@property (nonatomic) BOOL disabled;                             // -nosession or a second instance: no session, no snapshot
@property (nonatomic, copy, nullable) NSString *exitSessionPath;  // "Open session in a new instance (and save session on exit)"

- (void)startPeriodicBackupForController:(TPMainWindowController *)c;
- (void)writeSnapshotForController:(TPMainWindowController *)c;  // backups of dirty buffers + session.xml
// Returns YES when quitting may proceed (prompts for unsaved files when snapshot is off).
- (BOOL)saveForQuitWithController:(TPMainWindowController *)c;
- (BOOL)restoreIntoController:(TPMainWindowController *)c;      // YES if at least one document was restored
- (BOOL)saveSessionToPath:(NSString *)path controller:(TPMainWindowController *)c includeBackups:(BOOL)backups;
- (BOOL)loadSessionFromPath:(NSString *)path controller:(TPMainWindowController *)c;
@end

void TPSessionReloadSettings(TPMainWindowController *c);

NS_ASSUME_NONNULL_END
