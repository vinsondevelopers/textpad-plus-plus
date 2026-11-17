// Textpad++ — docking panels (upstream WinControls/DockingWnd: docking containers on the four sides of the editors
// or floating windows, with a caption, a close button and tabs when several panels share a container).
// GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TPDockSide) { TPDockLeft = 0, TPDockRight = 1, TPDockTop = 2, TPDockBottom = 3, TPDockFloating = 4 };

@protocol TPPanel <NSObject>
@property (nonatomic, readonly) NSString *panelIdentifier;   // "doclist", "docmap", "funclist", "faw", "project1"…
@property (nonatomic, readonly) NSString *panelTitle;        // caption, as upstream
@property (nonatomic, readonly) NSView *panelView;
@property (nonatomic, readonly) TPDockSide defaultSide;
@optional
- (void)panelDidShow;
- (void)panelDidHide;
- (void)focusPanel;
- (void)documentsChanged;   // documents opened / closed / renamed / saved / activated (refreshUI)
- (void)editorViewChanged;  // the active editor scrolled, its selection or text changed (SCN_UPDATEUI)
@end

@interface TPDockContainer : NSView
@property (nonatomic, readonly) NSArray<id<TPPanel>> *panels;
@property (nonatomic, strong, nullable) id<TPPanel> activePanel;
@property (nonatomic, copy, nullable) void (^closeHandler)(id<TPPanel> panel);
@property (nonatomic, copy, nullable) void (^moveHandler)(id<TPPanel> panel, TPDockSide side);   // the caption's dock menu
- (void)addPanel:(id<TPPanel>)panel;
- (void)removePanel:(id<TPPanel>)panel;
@end

@interface TPDockManager : NSObject <NSSplitViewDelegate>
// center: the editor area; returns the split view that replaces it in the window
- (instancetype)initWithCenter:(NSView *)center;
@property (nonatomic, readonly) NSSplitView *splitView;
@property (nonatomic, readonly) TPDockContainer *leftDock, *rightDock, *topDock, *bottomDock;
- (TPDockSide)sideOfPanel:(NSString *)identifier;              // where it shows (or will show)
- (void)movePanel:(NSString *)identifier toSide:(TPDockSide)side;  // dock elsewhere or float; remembered
- (nullable NSWindow *)floatingWindowOfPanel:(NSString *)identifier;
- (void)registerPanel:(id<TPPanel>)panel;
- (void)ensureDockSize:(CGFloat)fraction forSide:(TPDockSide)side;   // at least this share of the window when it next opens
- (nullable id<TPPanel>)panelWithIdentifier:(NSString *)identifier;
- (BOOL)isPanelVisible:(NSString *)identifier;
- (void)showPanel:(NSString *)identifier;
- (void)hidePanel:(NSString *)identifier;
- (void)togglePanel:(NSString *)identifier;
- (NSArray<NSString *> *)visiblePanelIdentifiers;
- (void)notifyDocumentsChanged;
- (void)notifyEditorViewChanged;
@end

NS_ASSUME_NONNULL_END
