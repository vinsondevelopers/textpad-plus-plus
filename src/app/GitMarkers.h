// Textpad++ — View > Git Change Markers. GPL-3.0-or-later.
#pragma once
#import "app/MainWindowController.h"

NS_ASSUME_NONNULL_BEGIN
extern NSString *_Nullable TPGitPathOverride;          // tests: the git to use ("" = none)
NSString *_Nullable TPGitExecutable(void);
NSString *_Nullable TPGitRepositoryRoot(NSString *path);
NSString *_Nullable TPGitHeadText(NSString *path);     // the committed text, nil when untracked / not in a repository

@interface TPMainWindowController (GitMarkers)
- (void)gitStartWatching;                               // at launch; follows the current document
- (void)gitApplyHead:(nullable NSString *)headText toEditor:(ScintillaView *)v;
- (void)gitJump:(BOOL)forward;
- (void)gitTick;
@end
NS_ASSUME_NONNULL_END
