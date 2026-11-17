// Textpad++ — Notepad++-style document tab bar (upstream WinControls/TabBar). GPL-3.0-or-later.
#pragma once

#import <Cocoa/Cocoa.h>

@class TPDocument;
@class TPTabBarView;

NS_ASSUME_NONNULL_BEGIN

@protocol TPTabBarDelegate <NSObject>
- (void)tabBar:(TPTabBarView *)bar didSelectIndex:(NSInteger)index;
- (void)tabBar:(TPTabBarView *)bar didRequestCloseIndex:(NSInteger)index;
- (void)tabBar:(TPTabBarView *)bar didMoveFrom:(NSInteger)from to:(NSInteger)to;
- (void)tabBarDidDoubleClickEmptyArea:(TPTabBarView *)bar;
- (nullable NSMenu *)tabBar:(TPTabBarView *)bar menuForIndex:(NSInteger)index;
- (void)tabBar:(TPTabBarView *)bar didTogglePinIndex:(NSInteger)index;
@optional
// a tab dragged out of its bar and released (window coordinates; outside the window when not inside it).
// Upstream: onto the other view = move there (Ctrl = clone, ⌥ on macOS), out of the window = new instance.
- (void)tabBar:(TPTabBarView *)bar didDropIndex:(NSInteger)index atWindowPoint:(NSPoint)point copy:(BOOL)copy;
// the mouse moved onto another tab (-1: off the tabs / out of the bar / a click). Upstream TCN_MOUSEHOVERING, TCN_MOUSELEAVING.
- (void)tabBar:(TPTabBarView *)bar didHoverIndex:(NSInteger)index;
@end

@interface TPTabBarView : NSView
@property (nonatomic, weak, nullable) id<TPTabBarDelegate> delegate;
@property (nonatomic, copy) NSArray<TPDocument *> *documents;
@property (nonatomic) NSInteger selectedIndex;
@property (nonatomic) BOOL focused;               // owning view has keyboard focus (orange vs pale indicator)
+ (CGFloat)preferredHeight;                       // Preferences > Tab Bar > Reduce
- (void)reload;
- (NSRect)rectForTabAtIndex:(NSInteger)index;
- (CGFloat)heightForWidth:(CGFloat)width;          // includes the rows of a multi-line bar
@property (nonatomic, readonly) NSInteger rowCount;
- (NSInteger)indexAtPoint:(NSPoint)p;              // bar coordinates
@end

NS_ASSUME_NONNULL_END
