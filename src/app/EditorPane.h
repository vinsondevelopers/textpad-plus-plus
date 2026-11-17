// Textpad++ — one editing view (upstream: main view / sub view = ScintillaEditView + DocTabView).
// GPL-3.0-or-later.
#pragma once

#import <Cocoa/Cocoa.h>
#import "app/Sci.h"
#import "app/TabBarView.h"

@class TPDocument;
@class TPEditorPane;

NS_ASSUME_NONNULL_BEGIN

@protocol TPEditorPaneOwner <NSObject>
- (void)pane:(TPEditorPane *)pane notification:(SCNotification *)scn;
- (void)paneDidBecomeActive:(TPEditorPane *)pane;
@end

@interface TPEditorPane : NSView <ScintillaNotificationProtocol>
@property (nonatomic, readonly) int viewIndex;                   // 0 main, 1 sub
@property (nonatomic, readonly) ScintillaView *editor;
@property (nonatomic, readonly) TPTabBarView *tabBar;
@property (nonatomic, readonly) NSMutableArray<TPDocument *> *documents;
@property (nonatomic, readonly, nullable) TPDocument *currentDocument;
@property (nonatomic, weak) id<TPEditorPaneOwner> owner;

- (instancetype)initWithViewIndex:(int)index owner:(id<TPEditorPaneOwner>)owner;
- (void)showDocument:(TPDocument *)doc;        // add if needed, switch Scintilla doc pointer, restore position
- (void)saveCurrentPosition;
- (void)removeDocument:(TPDocument *)doc;      // does not release the Scintilla document
- (void)reloadTabs;
- (NSInteger)indexOfDocument:(TPDocument *)doc;
@end

NS_ASSUME_NONNULL_END
