// Textpad++ — Live Preview panel. GPL-3.0-or-later.
#import "panels/PreviewPanel.h"
#import "app/MainWindowController.h"
#import "app/Document.h"
#import "app/Sci.h"
#include <functional>
#import <objc/runtime.h>

@implementation TPPreviewPanel {
    __weak TPMainWindowController *_c;
    NSView *_box;
    __weak TPDocument *_shown;
    size_t _lastHash;
    NSTimer *_renderTimer;
    NSString *_htmlTemp;
    BOOL _pageLoaded;
    CGFloat _lastScrollLine;
    NSDate *_previewScrolledAt;
}

+ (BOOL)isMarkdownPath:(NSString *)path {
    static NSSet *ext = [NSSet setWithArray:@[@"md", @"markdown", @"mdown", @"mkd", @"mkdn", @"mdwn", @"mdtxt", @"mdtext", @"rmd"]];
    return path && [ext containsObject:path.pathExtension.lowercaseString];
}

+ (TPPreviewMode)modeForDocument:(TPDocument *)doc {
    if (!doc) return TPPreviewNone;
    NSString *lang = doc.languageId ?: @"";
    if ([self isMarkdownPath:doc.path ?: doc.displayName] || [lang.lowercaseString containsString:@"markdown"]) return TPPreviewMarkdown;
    NSString *e = (doc.path ?: doc.displayName).pathExtension.lowercaseString;
    if ([lang isEqualToString:@"html"] || [@[@"html", @"htm", @"xhtml", @"shtml"] containsObject:e]) return TPPreviewHTML;
    return TPPreviewNone;
}

- (instancetype)initWithController:(TPMainWindowController *)c {
    if ((self = [super init])) {
        _c = c;
        _box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420, 500)];
        _box.autoresizesSubviews = YES;
        WKWebViewConfiguration *cfg = [WKWebViewConfiguration new];
        [cfg.userContentController addScriptMessageHandler:self name:@"tp"];
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = NO;
        cfg.suppressesIncrementalRendering = NO;
        _webView = [[WKWebView alloc] initWithFrame:_box.bounds configuration:cfg];
        _webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _webView.navigationDelegate = self;
        _webView.allowsMagnification = YES;
        [_box addSubview:_webView];
    }
    return self;
}

- (void)dealloc {
    [_webView.configuration.userContentController removeScriptMessageHandlerForName:@"tp"];
    if (_htmlTemp) [[NSFileManager defaultManager] removeItemAtPath:_htmlTemp error:nil];
}

- (NSString *)panelIdentifier { return @"preview"; }
- (NSString *)panelTitle { return @"Live Preview"; }
- (NSView *)panelView { return _box; }
- (TPDockSide)defaultSide { return TPDockRight; }
- (void)focusPanel { [_webView.window makeFirstResponder:_webView]; }
- (void)panelDidShow { _shown = nil; [self documentsChanged]; }
- (void)panelDidHide { [_renderTimer invalidate]; _shown = nil; }

- (void)documentsChanged {
    TPDocument *d = _c.currentDocument;
    if (d != _shown || [TPPreviewPanel modeForDocument:d] != _mode) { _shown = d; [self load]; }
    else [self scheduleRender];
}

- (void)editorViewChanged {
    if (_c.currentDocument != _shown) { [self documentsChanged]; return; }
    [self scheduleRender];
    [self syncScrollFromEditor];
}

// ------------------------------------------------------------ loading and rendering
- (void)load {
    _mode = [TPPreviewPanel modeForDocument:_shown];
    _lastHash = 0;
    _ready = NO;
    _pageLoaded = NO;
    if (_mode == TPPreviewMarkdown) {
        NSString *page = [[NSBundle mainBundle] pathForResource:@"markdown" ofType:@"html" inDirectory:@"data/preview"];
        if (!page) return;
        [_webView loadFileURL:[NSURL fileURLWithPath:page] allowingReadAccessToURL:[NSURL fileURLWithPath:@"/"]];
    } else if (_mode == TPPreviewHTML) {
        [self renderHTML];
    } else {
        NSString *msg = _shown ? @"Live Preview shows Markdown (.md) and HTML files.<br>Open one, or set the language to HTML."
                               : @"No document.";
        [_webView loadHTMLString:[NSString stringWithFormat:@"<html><head><meta name=color-scheme content='light dark'></head><body style='font:13px -apple-system;color:#888;text-align:center;margin-top:35vh'>%@</body></html>", msg]
                         baseURL:nil];
    }
}

- (void)scheduleRender {
    if (_mode == TPPreviewNone) return;
    [_renderTimer invalidate];
    _renderTimer = [NSTimer scheduledTimerWithTimeInterval:_mode == TPPreviewHTML ? 0.45 : 0.12 target:self selector:@selector(renderTick) userInfo:nil repeats:NO];
}

- (void)renderTick { [self renderIfChanged:NO]; }
- (void)refreshNow { [self renderIfChanged:YES]; }

- (std::string)currentText {
    ScintillaView *v = _c.editor;
    return v ? sciGetText(v) : std::string();
}

- (void)renderIfChanged:(BOOL)force {
    if (!_shown || _c.currentDocument != _shown) return;
    const std::string text = [self currentText];
    const size_t h = std::hash<std::string>{}(text);
    if (!force && h == _lastHash) return;
    _lastHash = h;
    if (_mode == TPPreviewMarkdown) {
        if (!_ready) return;   // the page asks for the text when it is ready
        NSString *base = _shown.path.stringByDeletingLastPathComponent ?: @"";
        const sptr_t first = SCI(_c.editor, SCI_DOCLINEFROMVISIBLE, SCI(_c.editor, SCI_GETFIRSTVISIBLELINE));
        NSData *json = [NSJSONSerialization dataWithJSONObject:@[NSStr(text) ?: @"", @{@"baseDir": base, @"scrollLine": @(first)}] options:0 error:nil];
        NSString *args = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
        [_webView evaluateJavaScript:[NSString stringWithFormat:@"TP.render(...%@)", args] completionHandler:nil];
        ++_renderCount;
    } else if (_mode == TPPreviewHTML) {
        [self renderHTML];
    }
}

// HTML: a temporary copy with <base href> pointing at the file's folder, so relative images and styles load
- (void)renderHTML {
    if (!_shown) return;
    const std::string text = [self currentText];
    _lastHash = std::hash<std::string>{}(text);
    NSString *html = NSStr(text) ?: @"";
    NSString *dir = _shown.path.stringByDeletingLastPathComponent;
    if (dir.length) {
        NSString *base = [NSString stringWithFormat:@"<base href=\"%@/\">", [NSURL fileURLWithPath:dir].absoluteString];
        NSRange head = [html rangeOfString:@"<head[^>]*>" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch];
        html = head.location != NSNotFound ? [html stringByReplacingCharactersInRange:NSMakeRange(NSMaxRange(head), 0) withString:base]
                                           : [base stringByAppendingString:html];
    }
    if (!_htmlTemp) _htmlTemp = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"textpad-preview-%@.html", NSUUID.UUID.UUIDString]];
    [html writeToFile:_htmlTemp atomically:YES encoding:NSUTF8StringEncoding error:nil];
    // keep the reader's place across reloads
    __weak WKWebView *web = _webView;
    NSString *tmp = _htmlTemp;
    [_webView evaluateJavaScript:@"window.scrollY" completionHandler:^(id y, NSError *e) {
        objc_setAssociatedObject(web, "tpScrollY", y, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [web loadFileURL:[NSURL fileURLWithPath:tmp] allowingReadAccessToURL:[NSURL fileURLWithPath:@"/"]];
    }];
    ++_renderCount;
}

// ------------------------------------------------------------ scrolling
- (void)syncScrollFromEditor {
    if (_mode != TPPreviewMarkdown || !_ready) return;
    if (_previewScrolledAt && -_previewScrolledAt.timeIntervalSinceNow < 0.5) return;   // the preview is the one scrolling
    NSResponder *fr = _webView.window.firstResponder;
    if ([fr isKindOfClass:NSView.class] && [(NSView *)fr isDescendantOf:_webView]) return;
    const CGFloat line = SCI(_c.editor, SCI_DOCLINEFROMVISIBLE, SCI(_c.editor, SCI_GETFIRSTVISIBLELINE));
    if (line == _lastScrollLine) return;
    _lastScrollLine = line;
    [_webView evaluateJavaScript:[NSString stringWithFormat:@"TP.scrollToLine(%g)", line] completionHandler:nil];
}

// ------------------------------------------------------------ messages from the page
- (void)userContentController:(WKUserContentController *)ucc didReceiveScriptMessage:(WKScriptMessage *)message {
    // only our own Markdown page may talk to the editor (an HTML document being previewed may not)
    if (_mode != TPPreviewMarkdown || ![message.frameInfo.request.URL.lastPathComponent isEqualToString:@"markdown.html"]) return;
    if ([message.body isKindOfClass:NSDictionary.class]) [self handleMessage:message.body];
}

- (void)handleMessage:(NSDictionary *)m {
    NSString *type = m[@"type"];
    TPMainWindowController *c = _c;
    if ([type isEqualToString:@"ready"]) { _ready = YES; [self renderIfChanged:YES]; return; }
    if (!_shown || c.currentDocument != _shown) return;
    ScintillaView *v = c.editor;
    if ([type isEqualToString:@"edit"]) {
        if (SCI(v, SCI_GETREADONLY)) { NSBeep(); [self refreshNow]; return; }
        const sptr_t lines = SCI(v, SCI_GETLINECOUNT);
        const sptr_t start = MAX((sptr_t)0, (sptr_t)[m[@"start"] integerValue]), end = MIN(lines, MAX(start, (sptr_t)[m[@"end"] integerValue]));
        const sptr_t eolMode = SCI(v, SCI_GETEOLMODE);
        NSString *eol = eolMode == SC_EOL_CRLF ? @"\r\n" : eolMode == SC_EOL_CR ? @"\r" : @"\n";
        NSString *text = [m[@"text"] ?: @"" stringByReplacingOccurrencesOfString:@"\n" withString:eol];
        sptr_t a = start < lines ? SCI(v, SCI_POSITIONFROMLINE, start) : SCI(v, SCI_GETLENGTH);
        sptr_t b = end > start ? SCI(v, SCI_GETLINEENDPOSITION, end - 1) : a;   // the block's lines, without the last line end
        if (start >= lines) text = [eol stringByAppendingString:text];
        const std::string u = text.UTF8String ?: "";
        SCI(v, SCI_BEGINUNDOACTION);
        SCI(v, SCI_SETTARGETRANGE, a, b);
        SCI(v, SCI_REPLACETARGET, u.size(), reinterpret_cast<sptr_t>(u.data()));
        SCI(v, SCI_ENDUNDOACTION);
        _lastHash = std::hash<std::string>{}([self currentText]);   // the page already shows this
        return;
    }
    if ([type isEqualToString:@"task"]) {
        const sptr_t line = [m[@"line"] integerValue];
        if (line < 0 || line >= SCI(v, SCI_GETLINECOUNT) || SCI(v, SCI_GETREADONLY)) return;
        const sptr_t a = SCI(v, SCI_POSITIONFROMLINE, line), e = SCI(v, SCI_GETLINEENDPOSITION, line);
        NSString *ls = NSStr(sciGetRange(v, a, e));
        NSRange r = [ls rangeOfString:@"\\[[ xX]\\]" options:NSRegularExpressionSearch];
        if (r.location == NSNotFound) return;
        const std::string before = std::string([ls substringToIndex:r.location].UTF8String);
        const std::string mark = [m[@"checked"] boolValue] ? "[x]" : "[ ]";
        SCI(v, SCI_SETTARGETRANGE, a + before.size(), a + before.size() + 3);
        SCI(v, SCI_REPLACETARGET, 3, reinterpret_cast<sptr_t>(mark.c_str()));
        _lastHash = std::hash<std::string>{}([self currentText]);
        return;
    }
    if ([type isEqualToString:@"scroll"]) {
        _previewScrolledAt = [NSDate date];
        const sptr_t line = (sptr_t)[m[@"line"] doubleValue];
        _lastScrollLine = line;
        SCI(v, SCI_SETFIRSTVISIBLELINE, SCI(v, SCI_VISIBLEFROMDOCLINE, line));
        return;
    }
    if ([type isEqualToString:@"link"]) {
        NSString *href = m[@"href"] ?: @"";
        NSURL *u = [NSURL URLWithString:href];
        if (u.scheme.length && ![u.scheme isEqualToString:@"file"]) {
            if ([@[@"http", @"https", @"mailto"] containsObject:u.scheme.lowercaseString]) [[NSWorkspace sharedWorkspace] openURL:u];
            return;
        }
        NSString *path = u.isFileURL ? u.path : [href.stringByRemovingPercentEncoding ?: href componentsSeparatedByString:@"#"].firstObject;
        if (!path.length) return;
        if (!path.isAbsolutePath) path = [[m[@"base"] ?: @"" stringByAppendingPathComponent:path] stringByStandardizingPath];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) [c openFile:path];   // a link to another Markdown file opens it
    }
}

// ------------------------------------------------------------ navigation: links leave for the browser
- (void)webView:(WKWebView *)w decidePolicyForNavigationAction:(WKNavigationAction *)a decisionHandler:(void (^)(WKNavigationActionPolicy))h {
    NSURL *u = a.request.URL;
    if (a.navigationType == WKNavigationTypeLinkActivated && a.targetFrame.isMainFrame) {
        if ([@[@"http", @"https", @"mailto"] containsObject:u.scheme.lowercaseString]) [[NSWorkspace sharedWorkspace] openURL:u];
        else if (u.isFileURL && [[NSFileManager defaultManager] fileExistsAtPath:u.path] && ![u.path isEqualToString:_htmlTemp]) [_c openFile:u.path];
        h(WKNavigationActionPolicyCancel);
        return;
    }
    if (!a.targetFrame) { h(WKNavigationActionPolicyCancel); return; }   // target=_blank, window.open
    h(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)w didFinishNavigation:(WKNavigation *)n {
    _pageLoaded = YES;
    if (_mode == TPPreviewHTML) {
        NSNumber *y = objc_getAssociatedObject(w, "tpScrollY");
        if (y.doubleValue > 0) [w evaluateJavaScript:[NSString stringWithFormat:@"window.scrollTo(0,%g)", y.doubleValue] completionHandler:nil];
    }
}

@end
