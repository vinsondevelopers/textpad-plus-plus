// Textpad++ — View > Live Preview: Markdown (rendered block by block, editable in place: an edit in the preview is
// written back to the text as Markdown) and HTML (rendered as a page). It follows the active document, re-renders
// as the text changes and scrolls with the editor. GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "panels/DockManager.h"

@class TPMainWindowController, TPDocument;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TPPreviewMode) { TPPreviewNone, TPPreviewMarkdown, TPPreviewHTML };

@interface TPPreviewPanel : NSObject <TPPanel, WKScriptMessageHandler, WKNavigationDelegate>
- (instancetype)initWithController:(TPMainWindowController *)c;
@property (nonatomic, readonly) WKWebView *webView;
@property (nonatomic, readonly) TPPreviewMode mode;
@property (nonatomic, readonly) BOOL ready;                              // the page loaded and answered
@property (nonatomic, readonly) NSUInteger renderCount;                  // tests
+ (TPPreviewMode)modeForDocument:(nullable TPDocument *)doc;
+ (BOOL)isMarkdownPath:(nullable NSString *)path;
- (void)refreshNow;                                                     // render the current text without waiting
// what the page sends (also called by the self-tests)
- (void)handleMessage:(NSDictionary *)m;
@end

NS_ASSUME_NONNULL_END
