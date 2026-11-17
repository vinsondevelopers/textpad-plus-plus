// Textpad++ — over-the-air updates: the feed's archive (a .zip of Textpad++.app, or a .dmg) is downloaded,
// checked (SHA-256, and an ECDSA P-256 signature against the public key built into the app), unpacked and
// verified (same bundle identifier, the announced version, a valid code signature); a small helper then swaps it
// in for the running app once Textpad++ has quit, and relaunches it. GPL-3.0-or-later.
#import "app/Updater.h"
#import "app/Preferences.h"
#import "app/ToolbarView.h"
#import <Security/Security.h>
#include "core/Hashing.h"
#include <unistd.h>

static int runTool(NSString *path, NSArray<NSString *> *args) {
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:path];
    t.arguments = args;
    t.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    t.standardError = [NSFileHandle fileHandleWithNullDevice];
    if (![t launchAndReturnError:nil]) return -1;
    [t waitUntilExit];
    return t.terminationStatus;
}

@implementation TPUpdater (Install)

// the public key: Info.plist TPUpdatePublicKey (base64 of the 65-byte uncompressed P-256 point), or pref.updatePublicKey
- (NSData *)publicKeyData {
    NSString *s = [TPPrefs s:@"pref.updatePublicKey"];
    if (!s.length) s = [NSBundle.mainBundle objectForInfoDictionaryKey:@"TPUpdatePublicKey"];
    if (!s.length || [s hasPrefix:@"@"]) return nil;
    return [[NSData alloc] initWithBase64EncodedString:s options:NSDataBase64DecodingIgnoreUnknownCharacters];
}

- (BOOL)verifyArchive:(NSData *)archive info:(TPUpdateInfo *)info error:(NSString **)error {
    if (info.sha256.length) {
        std::string hex = tpp::hashHex(tpp::HashAlgorithm::SHA256, std::string(static_cast<const char *>(archive.bytes), archive.length));
        if (![@(hex.c_str()) isEqualToString:info.sha256.lowercaseString]) { if (error) *error = @"The download is damaged (SHA-256 differs from the update information)."; return NO; }
    }
    NSData *keyData = [self publicKeyData];
    if (!keyData) {   // no key built in: only accept a checksum delivered over https or a local file
        if (!info.sha256.length) { if (error) *error = @"The update is not signed and has no checksum."; return NO; }
        return YES;
    }
    NSData *sig = info.signature.length ? [[NSData alloc] initWithBase64EncodedString:info.signature options:NSDataBase64DecodingIgnoreUnknownCharacters] : nil;
    if (!sig) { if (error) *error = @"The update is not signed."; return NO; }
    NSDictionary *attrs = @{(id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom, (id)kSecAttrKeyClass: (id)kSecAttrKeyClassPublic, (id)kSecAttrKeySizeInBits: @256};
    CFErrorRef cfErr = nullptr;
    SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)keyData, (__bridge CFDictionaryRef)attrs, &cfErr);
    if (!key) { if (cfErr) CFRelease(cfErr); if (error) *error = @"The built-in update key is invalid."; return NO; }
    const BOOL ok = SecKeyVerifySignature(key, kSecKeyAlgorithmECDSASignatureMessageX962SHA256, (__bridge CFDataRef)archive, (__bridge CFDataRef)sig, &cfErr);
    if (cfErr) CFRelease(cfErr);
    CFRelease(key);
    if (!ok && error) *error = @"The update's signature is not valid: it was not published with this app's update key.";
    return ok;
}

// download + verify + unpack; returns the new Textpad++.app in a temporary folder
- (NSString *)prepareUpdate:(TPUpdateInfo *)info error:(NSString **)error {
    if (!info.location) { if (error) *error = @"The update information has no download address."; return nil; }
    if (!info.location.isFileURL && ![info.location.scheme isEqualToString:@"https"]) { if (error) *error = @"Updates are only downloaded over https."; return nil; }
    NSString *work = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"textpad-update-" stringByAppendingString:[NSUUID UUID].UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:work withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *saved = self.downloadDirectoryOverride;
    self.downloadDirectoryOverride = work;
    NSString *archive = [self downloadUpdateFrom:info.location error:error];
    self.downloadDirectoryOverride = saved;
    if (!archive) return nil;
    NSData *bytes = [NSData dataWithContentsOfFile:archive options:NSDataReadingMappedIfSafe error:nil];
    if (![self verifyArchive:bytes info:info error:error]) return nil;
    NSString *out = [work stringByAppendingPathComponent:@"new"];
    if ([archive.pathExtension.lowercaseString isEqualToString:@"dmg"]) {
        NSString *mount = [work stringByAppendingPathComponent:@"mnt"];
        if (runTool(@"/usr/bin/hdiutil", @[@"attach", @"-nobrowse", @"-readonly", @"-noautoopen", @"-mountpoint", mount, archive]) != 0) { if (error) *error = @"The disk image could not be opened."; return nil; }
        NSString *app = nil;
        for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:mount error:nil]) if ([f.pathExtension isEqualToString:@"app"]) app = f;
        int rc = app ? runTool(@"/usr/bin/ditto", @[[mount stringByAppendingPathComponent:app], [out stringByAppendingPathComponent:app]]) : -1;
        runTool(@"/usr/bin/hdiutil", @[@"detach", mount, @"-quiet"]);
        if (rc != 0) { if (error) *error = @"The disk image holds no application."; return nil; }
    } else if (runTool(@"/usr/bin/ditto", @[@"-x", @"-k", archive, out]) != 0) {
        if (error) *error = @"The update could not be unpacked."; return nil;
    }
    NSString *app = nil;
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:out error:nil]) if ([f.pathExtension isEqualToString:@"app"]) app = [out stringByAppendingPathComponent:f];
    NSDictionary *plist = app ? [NSDictionary dictionaryWithContentsOfFile:[app stringByAppendingPathComponent:@"Contents/Info.plist"]] : nil;
    NSString *myId = NSBundle.mainBundle.bundleIdentifier ?: @"com.textpadplusplus.app";
    if (![plist[@"CFBundleIdentifier"] isEqualToString:myId]) { if (error) *error = @"The update is not Textpad++."; return nil; }
    if ([TPUpdater compareVersion:plist[@"CFBundleShortVersionString"] ?: @"0" with:info.version] != NSOrderedSame) { if (error) *error = @"The update's version does not match the update information."; return nil; }
    if (runTool(@"/usr/bin/codesign", @[@"--verify", @"--deep", @"--strict", app]) != 0) { if (error) *error = @"The update's code signature is broken."; return nil; }
    runTool(@"/usr/bin/xattr", @[@"-dr", @"com.apple.quarantine", app]);
    [[NSFileManager defaultManager] removeItemAtPath:archive error:nil];
    return app;
}

- (BOOL)canReplaceAppAt:(NSString *)target {
    return access(target.stringByDeletingLastPathComponent.fileSystemRepresentation, W_OK) == 0 && access(target.fileSystemRepresentation, W_OK) == 0;
}

// the helper: waits for process `pid` to end, swaps the bundles (restoring the old one on failure), relaunches
- (BOOL)installApp:(NSString *)newApp over:(NSString *)target afterProcess:(pid_t)pid relaunch:(BOOL)relaunch wait:(BOOL)wait error:(NSString **)error {
    if (![self canReplaceAppAt:target]) { if (error) *error = @"Textpad++ cannot replace itself here (no write permission)."; return NO; }
    NSString *script = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"textpad-install-%@.sh", [NSUUID UUID].UUIDString]];
    NSString *body = @"#!/bin/sh\n"
        "PID=\"$1\"; TARGET=\"$2\"; NEW=\"$3\"; RELAUNCH=\"$4\"; BACKUP=\"$TARGET.old-$$\"\n"
        "while kill -0 \"$PID\" 2>/dev/null; do sleep 0.3; done\n"
        "if mv \"$TARGET\" \"$BACKUP\"; then\n"
        "  if /usr/bin/ditto \"$NEW\" \"$TARGET\"; then rm -rf \"$BACKUP\" \"$(dirname \"$NEW\")\"; else rm -rf \"$TARGET\"; mv \"$BACKUP\" \"$TARGET\"; fi\n"
        "fi\n"
        "[ \"$RELAUNCH\" = 1 ] && /usr/bin/open \"$TARGET\"\n"
        "rm -f \"$0\"\n";
    if (![body writeToFile:script atomically:YES encoding:NSUTF8StringEncoding error:nil]) { if (error) *error = @"The installer could not be prepared."; return NO; }
    NSTask *t = [NSTask new];
    t.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
    t.arguments = @[script, [@(pid) stringValue], target, newApp, relaunch ? @"1" : @"0"];
    NSError *e = nil;
    if (![t launchAndReturnError:&e]) { if (error) *error = e.localizedDescription; return NO; }
    if (wait) [t waitUntilExit];   // the self-test; otherwise it outlives Textpad++ on purpose
    return YES;
}

// Preferences > MISC.: "Install updates automatically": prepared in the background, swapped in when Textpad++ quits
- (void)installUpdate:(TPUpdateInfo *)info interactive:(BOOL)interactive {
    TPMainWindowController *c = self.controller;
    NSString *target = NSBundle.mainBundle.bundlePath;
    if (![self canReplaceAppAt:target]) { [self downloadForManualInstall:info]; return; }
    NSPanel *panel = nil;
    if (interactive && !c.selfTestMode) {
        panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 360, 80) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        panel.title = @"Updating Textpad++";
        NSTextField *l = [NSTextField labelWithString:[NSString stringWithFormat:@"Downloading and checking Textpad++ %@…", info.version]];
        l.frame = NSMakeRect(20, 44, 320, 18);
        NSProgressIndicator *p = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 16, 320, 20)];
        p.indeterminate = YES;
        [p startAnimation:nil];
        for (NSView *v in @[l, p]) [panel.contentView addSubview:v];
        [panel center];
        [panel makeKeyAndOrderFront:nil];
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSString *err = nil;
        NSString *app = [self prepareUpdate:info error:&err];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *err2 = err;
            [panel orderOut:nil];
            if (!app) { if (interactive) [c showMessage:@"The update could not be installed" informative:err2]; return; }
            if (!interactive) {   // automatic: swap in when the user quits, without asking
                if ([self installApp:app over:target afterProcess:getpid() relaunch:NO wait:NO error:&err2])
                    [c.statusBar setText:[NSString stringWithFormat:@"Textpad++ %@ will be installed when you quit.", info.version] forPart:0];
                return;
            }
            NSInteger r = [c prompt:[NSString stringWithFormat:@"Textpad++ %@ is ready to install.", info.version]
                        informative:@"Textpad++ will quit, update itself and open again with your documents." buttons:@[@"Install and Relaunch", @"Install When I Quit"]];
            if (![self installApp:app over:target afterProcess:getpid() relaunch:r == 0 wait:NO error:&err2]) { [c showMessage:@"The update could not be installed" informative:err2]; return; }
            if (r == 0) [NSApp terminate:nil];
            else [c.statusBar setText:[NSString stringWithFormat:@"Textpad++ %@ will be installed when you quit.", info.version] forPart:0];
        });
    });
}

// where the app cannot replace itself (another user's /Applications): the old way, the DMG in Downloads
- (void)downloadForManualInstall:(TPUpdateInfo *)info {
    TPMainWindowController *c = self.controller;
    NSURL *dmg = info.dmgLocation ?: info.location;
    NSString *err = nil;
    NSString *file = [self downloadUpdateFrom:dmg error:&err];
    if (!file) { [c showMessage:@"The update could not be downloaded" informative:err]; return; }
    if (!c.selfTestMode) [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:file]];
    [c showMessage:[NSString stringWithFormat:@"Textpad++ %@ was downloaded.", info.version]
       informative:[NSString stringWithFormat:@"%@\n\nTextpad++ cannot update itself in its current folder. Quit it, then drag the new Textpad++ to Applications.", file]];
}

@end
