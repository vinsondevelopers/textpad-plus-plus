// Textpad++ — Find / Replace / Find in Files / Mark dialog (upstream FindReplaceDlg).
// GPL-3.0-or-later.
#pragma once

#import <Cocoa/Cocoa.h>
#import "search/SearchEngine.h"

@class TPMainWindowController;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TPFindTab) { TPFindTabFind = 0, TPFindTabReplace, TPFindTabFindInFiles, TPFindTabFindInProjects, TPFindTabMark };

@interface TPFindReplaceController : NSWindowController <NSWindowDelegate>
- (instancetype)initWithController:(TPMainWindowController *)c;
- (void)showTab:(TPFindTab)tab;
- (tpp::search::Options)currentOptions;
- (void)setFindText:(NSString *)text;
- (void)setReplaceText:(NSString *)text;
- (void)setOptions:(const tpp::search::Options &)o;      // used by macros / self-test
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, copy) NSString *filters;
@property (nonatomic) BOOL recursive;
@property (nonatomic) BOOL hiddenFolders;
@property (nonatomic, readonly) NSString *statusText;
// Find in Projects (upstream): which Project Panels to search, and where their files come from
@property (nonatomic) BOOL project1, project2, project3;
@property (nonatomic, copy, nullable) NSArray<NSString *> *_Nonnull (^projectFilesProvider)(NSArray<NSNumber *> *panels);
@property (nonatomic, readonly) TPFindTab currentTab;
@property (nonatomic) BOOL highlightMatches;          // highlight all matches while the dialog is open (upstream)
@property (nonatomic) NSInteger transparencyMode;     // 0 none, 1 on losing focus, 2 always
- (void)updateMatchHighlighting;                      // also called when the editor scrolls
- (void)clearMatchHighlighting;
- (void)applyTransparencyActive:(BOOL)active;

// Actions (also used by Search menu commands and the self-test)
- (BOOL)findNext:(BOOL)forward;
- (long)count;
- (BOOL)replaceOne;
- (long)replaceAllInCurrent;
- (long)replaceAllInAllOpened;
- (long)markAll;
- (void)clearMarks;
- (void)copyMarkedText;
- (long)findAllInCurrent;
- (long)findAllInAllOpened;
- (long)findInFiles;
- (long)replaceInFiles;
@end

NS_ASSUME_NONNULL_END
