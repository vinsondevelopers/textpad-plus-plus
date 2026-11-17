// Textpad++ — "Search results" dockable panel (upstream: FindReplaceDlg's Finder, a Scintilla
// view using the searchResult lexer). GPL-3.0-or-later.
#pragma once

#import <Cocoa/Cocoa.h>
#import "app/Sci.h"
#include <string>
#include <vector>

@class TPMainWindowController;
@class TPDocument;

NS_ASSUME_NONNULL_BEGIN

struct TPResultHit {
    std::string fileLabel;      // path or "new 1"
    std::string path;           // empty for untitled
    NSUInteger docUid;          // 0 when the hit is in a file not open
    sptr_t line;                // 0-based
    sptr_t start, end;          // byte offsets relative to the start of the line
    std::string lineText;
};

@interface TPSearchResultsPanel : NSView <ScintillaNotificationProtocol>
@property (nonatomic, readonly) ScintillaView *view;
- (instancetype)initWithController:(TPMainWindowController *)c;
// Adds a new search block on top (upstream keeps previous searches below, folded).
- (void)addSearch:(NSString *)what hits:(const std::vector<TPResultHit> &)hits filesSearched:(NSInteger)nFiles;
- (void)gotoNext:(BOOL)forward;
- (void)showPanel;
- (void)hidePanel;
@property (nonatomic) BOOL floating;   // docked under the editors, or in its own window (remembered)
@property (nonatomic, readonly) NSInteger lastHitCount;
@end

NS_ASSUME_NONNULL_END
