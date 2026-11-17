// Textpad++ — ? > Update Textpad++, ? > Set Updater Proxy..., Preferences > MISC. > auto-updater
// (upstream: WinGUP, gup.exe). The feed is a GUP XML file on the website that hosts the DMG:
//   <GUP><NeedToBeUpdated>yes</NeedToBeUpdated><Version>1.0.0</Version><Location>https://…/Textpad++.dmg</Location></GUP>
// Its address is built in with `make dmg UPDATE_URL=https://…/update.xml` (Info.plist TPUpdateFeedURL).
// GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>
#import "app/MainWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@interface TPUpdateInfo : NSObject
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy, nullable) NSURL *location;
@property (nonatomic) BOOL needToBeUpdated;   // NeedToBeUpdated (absent = yes)
@property (nonatomic, copy, nullable) NSString *sha256;        // <SHA256> of the archive at Location
@property (nonatomic, copy, nullable) NSString *signature;     // <Signature>: base64 ECDSA P-256 (SHA-256) of the archive
@property (nonatomic, copy, nullable) NSURL *dmgLocation;      // <DmgLocation>: for a manual install
@end

@interface TPUpdater : NSObject
+ (instancetype)shared;
@property (nonatomic, weak, nullable) TPMainWindowController *controller;
@property (nonatomic, readonly, nullable) NSURL *feedURL;             // the built-in address, or pref.updateFeedURL
@property (nonatomic, readonly) NSString *currentVersion;             // CFBundleShortVersionString
@property (nonatomic, copy, nullable) NSString *downloadDirectoryOverride;   // self-test
- (void)registerCommands;
- (void)checkAtLaunch;                                                // every 15 days when the auto-updater is on
- (void)checkForUpdatesInteractively:(BOOL)interactive;              // in the background, answers on the main thread
// the parts, synchronous (also used by the self-test)
- (nullable TPUpdateInfo *)fetchFeed:(NSURL *)url error:(NSString *_Nullable *_Nullable)error;
+ (nullable TPUpdateInfo *)parseFeed:(NSData *)xml;
+ (NSComparisonResult)compareVersion:(NSString *)a with:(NSString *)b;
- (BOOL)isNewer:(TPUpdateInfo *)info;
- (void)handleUpdate:(nullable TPUpdateInfo *)info error:(nullable NSString *)error interactive:(BOOL)interactive;
- (nullable NSString *)downloadUpdateFrom:(NSURL *)url error:(NSString *_Nullable *_Nullable)error;   // file in Downloads
// ? > Set Updater Proxy... (GUP "Proxy settings": server and port)
- (void)showProxyDialog;
- (void)setProxyHost:(nullable NSString *)host port:(NSInteger)port;
- (NSURLSessionConfiguration *)sessionConfiguration;
@end

// over-the-air install (UpdateInstaller.mm)
@interface TPUpdater (Install)
- (BOOL)verifyArchive:(NSData *)archive info:(TPUpdateInfo *)info error:(NSString *_Nullable *_Nullable)error;
- (nullable NSString *)prepareUpdate:(TPUpdateInfo *)info error:(NSString *_Nullable *_Nullable)error;   // the new .app, checked
- (BOOL)canReplaceAppAt:(NSString *)target;
- (BOOL)installApp:(NSString *)newApp over:(NSString *)target afterProcess:(pid_t)pid relaunch:(BOOL)relaunch wait:(BOOL)wait error:(NSString *_Nullable *_Nullable)error;
- (void)installUpdate:(TPUpdateInfo *)info interactive:(BOOL)interactive;
- (void)downloadForManualInstall:(TPUpdateInfo *)info;
@end

NS_ASSUME_NONNULL_END
