// Textpad++ — main window controller. GPL-3.0-or-later.
#import "app/MainWindowController.h"
#import "app/EscapeKey.h"
#import "app/Features.h"
#import "app/Snippets.h"
#import "app/AutoCompletion.h"
#import "app/HideLines.h"
#import "app/TagMatch.h"
#import "panels/DockManager.h"
#import "panels/Panels.h"
#import "search/IncrementalSearchBar.h"
#import "app/MenuBarView.h"
#import "app/LargeFiles.h"
#import "plugins/PluginHost.h"
#import "app/SystemTray.h"
#import "app/LanguageService.h"
#import "app/Session.h"
#import "search/FindReplaceController.h"
#import "search/SearchResultsPanel.h"
#import "app/Preferences.h"
#import "app/UserDefinedLanguages.h"

#include <copyfile.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>

using namespace npp;

// Container with manual layout: toolbar / editors (+ results) / status bar
extern BOOL (^TPScintillaFileDropHandler)(NSArray<NSURL *> *urls);   // third_party/scintilla/cocoa/ScintillaView.mm (Textpad++ hook)

@interface TPContainerView : NSView
@property (nonatomic, weak) NSView *top;
@property (nonatomic, weak) NSView *middle;
@property (nonatomic, weak) NSView *bottom;
@property (nonatomic, weak) TPIncrementalSearchBar *incBar;   // Search > Incremental Search, above or below the editors
@property (nonatomic, weak) TPMenuBarView *menuBar;           // Preferences > General > Menu: in-window menu bar
@end
@implementation TPContainerView
- (BOOL)isFlipped { return YES; }
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return [sender.draggingPasteboard canReadObjectForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}] ? NSDragOperationCopy : NSDragOperationNone;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray *urls = [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    return urls.count && TPScintillaFileDropHandler && TPScintillaFileDropHandler(urls);
}
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize { [self layoutParts]; }
- (void)layoutParts {
    NSRect b = self.bounds;
    const CGFloat menuH = (_menuBar && !_menuBar.hidden) ? _menuBar.preferredHeight : 0;
    if (_menuBar) _menuBar.frame = NSMakeRect(0, 0, NSWidth(b), menuH);
    CGFloat topH = _top.hidden ? 0 : [(TPToolbarView *)_top preferredHeight], botH = _bottom.hidden ? 0 : 22;
    _top.frame = NSMakeRect(0, menuH, NSWidth(b), topH);
    topH += menuH;
    _bottom.frame = NSMakeRect(0, NSHeight(b) - botH, NSWidth(b), botH);
    CGFloat incH = (_incBar && !_incBar.hidden) ? 30 : 0;
    if (incH) _incBar.frame = _incBar.atTop ? NSMakeRect(0, topH, NSWidth(b), incH) : NSMakeRect(0, NSHeight(b) - botH - incH, NSWidth(b), incH);
    _middle.frame = NSMakeRect(0, topH + (_incBar.atTop ? incH : 0), NSWidth(b), MAX(0, NSHeight(b) - topH - botH - incH));
}
@end

// Safe write: temp file in the same folder, metadata (mode, ACL, xattrs) copied from the
// original, fsync, atomic rename. Symlinks are resolved so the link itself survives.
BOOL TPSafeWriteFileProducer(NSString *path, BOOL (^produce)(TPByteSink sink), NSString **error) {
    // resolve symlinks so the link itself is preserved
    NSString *target = path;
    NSDictionary *lattrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if ([lattrs.fileType isEqualToString:NSFileTypeSymbolicLink]) target = path.stringByResolvingSymlinksInPath;

    NSString *dir = target.stringByDeletingLastPathComponent;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:target];
    if (exists && ![[NSFileManager defaultManager] isWritableFileAtPath:target]) {
        if (error) *error = @"The file is read-only on disk.";
        return NO;
    }
    NSString *tmpTemplate = [dir stringByAppendingPathComponent:@".textpad-save-XXXXXX"];
    std::string tmpl = StdStr(tmpTemplate);
    std::vector<char> buf(tmpl.begin(), tmpl.end());
    buf.push_back('\0');
    int fd = mkstemp(buf.data());
    BOOL wroteOK = NO;
    NSString *tmpPath = nil;
    if (fd >= 0) {
        tmpPath = @(buf.data());
        const int wfd = fd;
        wroteOK = produce(^BOOL(const char *data, size_t len) {
            size_t off = 0;
            while (off < len) {
                ssize_t n = write(wfd, data + off, len - off);
                if (n < 0) { if (errno == EINTR) continue; return NO; }
                off += static_cast<size_t>(n);
            }
            return YES;
        });
        if (wroteOK && fsync(fd) != 0) wroteOK = NO;
        close(fd);
        if (wroteOK) {
            if (exists) {
                copyfile(target.fileSystemRepresentation, tmpPath.fileSystemRepresentation, nullptr, COPYFILE_SECURITY | COPYFILE_XATTR);
            } else {
                mode_t um = umask(0); umask(um);
                chmod(tmpPath.fileSystemRepresentation, 0666 & ~um);
            }
            if (rename(tmpPath.fileSystemRepresentation, target.fileSystemRepresentation) != 0) wroteOK = NO;
        }
        if (!wroteOK) unlink(tmpPath.fileSystemRepresentation);
    }
    if (!wroteOK && fd >= 0) {
        // The temp write itself failed (e.g. disk full): never touch the original.
        if (error) *error = [NSString stringWithFormat:@"Write failed (%s). The original file was not modified.", strerror(errno)];
        return NO;
    }
    if (!wroteOK) {
        // Folder not writable but the file is: in-place overwrite is the only option (upstream does the same).
        if (!exists) { if (error) *error = @"The folder is not writable."; return NO; }
        int ofd = open(target.fileSystemRepresentation, O_WRONLY | O_TRUNC);
        if (ofd < 0) { if (error) *error = @(strerror(errno)); return NO; }
        BOOL ok = produce(^BOOL(const char *data, size_t len) {
            size_t off = 0;
            while (off < len) {
                ssize_t n = write(ofd, data + off, len - off);
                if (n < 0) { if (errno == EINTR) continue; return NO; }
                off += static_cast<size_t>(n);
            }
            return YES;
        });
        close(ofd);
        if (!ok) { if (error) *error = @"Write failed"; return NO; }
    }
    return YES;
}

BOOL TPSafeWriteFile(NSString *path, const std::string &bytes, NSString **error) {
    return TPSafeWriteFileProducer(path, ^BOOL(TPByteSink sink) { return sink(bytes.data(), bytes.size()); }, error);
}

// the splitter between the two views: right-click it to rotate them (upstream "Rotate to right / left")
@interface TPViewSplitView : NSSplitView
@end
@implementation TPViewSplitView
- (NSRect)dividerRect {
    if (self.subviews.count < 2 || self.subviews[1].hidden) return NSZeroRect;
    NSRect a = self.subviews[0].frame;
    return self.vertical ? NSMakeRect(NSMaxX(a) - 3, 0, self.dividerThickness + 6, NSHeight(self.bounds))
                         : NSMakeRect(0, NSMaxY(a) - 3, NSWidth(self.bounds), self.dividerThickness + 6);
}
- (NSMenu *)menuForEvent:(NSEvent *)e {
    if (!NSPointInRect([self convertPoint:e.locationInWindow fromView:nil], self.dividerRect)) return [super menuForEvent:e];
    NSMenu *m = [[NSMenu alloc] initWithTitle:@"Splitter"];
    [m addItemWithTitle:@"Rotate to right" action:@selector(rotateViews:) keyEquivalent:@""].target = self;
    [m addItemWithTitle:@"Rotate to left" action:@selector(rotateViews:) keyEquivalent:@""].target = self;
    return m;
}
- (void)rotateViews:(id)sender {
    const CGFloat ratio = self.vertical ? NSWidth(self.subviews[0].frame) / MAX(1.0, NSWidth(self.bounds))
                                        : NSHeight(self.subviews[0].frame) / MAX(1.0, NSHeight(self.bounds));
    self.vertical = !self.vertical;
    [[NSUserDefaults standardUserDefaults] setBool:!self.vertical forKey:@"views.stacked"];
    [self adjustSubviews];
    if (self.subviews.count > 1 && !self.subviews[1].hidden)
        [self setPosition:ratio * (self.vertical ? NSWidth(self.bounds) : NSHeight(self.bounds)) ofDividerAtIndex:0];
}
@end

@interface TPMainWindowController ()
@end

@implementation TPMainWindowController {
    TPEditorPane *_mainPane;
    TPEditorPane *_subPane;
    TPEditorPane *_activePane;
    NSSplitView *_split;        // main | sub
    NSSplitView *_vsplit;       // editors / search results
    TPContainerView *_container;
    TPToolbarView *_toolbar;
    TPStatusBarView *_statusBar;
    ScintillaView *_worker;
    sptr_t _workerScratch;
    sptr_t _paneScratch[2];
    int _untitledCounter;
    NSTimer *_fileCheckTimer;
    NSMutableArray<NSString *> *_recentFiles;
    NSMutableArray<NSString *> *_closedFiles;
    BOOL _checkingFiles;
    id _eventMonitor;
    TPFindReplaceController *_findController;
    TPSearchResultsPanel *_resultsPanel;
    TPDockManager *_docks;
    TPIncrementalSearchBar *_incBar;
}

- (instancetype)init {
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(120, 120, 1100, 720)
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:w])) {
        w.delegate = self;
        w.minSize = NSMakeSize(420, 260);
        w.frameAutosaveName = @"TextpadMainWindow";
        w.tabbingMode = NSWindowTabbingModeDisallowed;
        w.collectionBehavior |= NSWindowCollectionBehaviorFullScreenPrimary;
        _recentFiles = [[[NSUserDefaults standardUserDefaults] arrayForKey:@"RecentFiles"] mutableCopy] ?: [NSMutableArray array];
        _closedFiles = [NSMutableArray array];
        [self installPreferenceObservers];
        [self buildUI];
        [self installEventMonitor];
        [self installTrayHooks];
        _fileCheckTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(fileCheckTick:) userInfo:nil repeats:YES];
    }
    return self;
}

- (void)dealloc {
    if (_eventMonitor) [NSEvent removeMonitor:_eventMonitor];
}

- (void)buildUI {
    __weak TPMainWindowController *weakSelf = self;
    TPScintillaFileDropHandler = ^BOOL(NSArray<NSURL *> *urls) { return [weakSelf openDroppedURLs:urls]; };
    [self installEditorOptionHooks];
    _container = [[TPContainerView alloc] initWithFrame:self.window.contentView.bounds];
    [_container registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    _container.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.window.contentView = _container;

    _toolbar = [[TPToolbarView alloc] initWithFrame:NSMakeRect(0, 0, 1100, 28)];
    _statusBar = [[TPStatusBarView alloc] initWithFrame:NSMakeRect(0, 0, 1100, 22)];

    _mainPane = [[TPEditorPane alloc] initWithViewIndex:0 owner:self];
    _subPane = [[TPEditorPane alloc] initWithViewIndex:1 owner:self];
    _mainPane.tabBar.delegate = self;
    _subPane.tabBar.delegate = self;

    _split = [[TPViewSplitView alloc] initWithFrame:NSMakeRect(0, 0, 1100, 600)];
    _split.vertical = ![[NSUserDefaults standardUserDefaults] boolForKey:@"views.stacked"];   // views side by side or stacked
    _split.dividerStyle = NSSplitViewDividerStyleThin;
    [_split addSubview:_mainPane];
    [_split addSubview:_subPane];
    _subPane.hidden = YES;

    _resultsPanel = [[TPSearchResultsPanel alloc] initWithController:self];
    _vsplit = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 1100, 640)];
    _vsplit.vertical = NO;
    _vsplit.dividerStyle = NSSplitViewDividerStyleThin;
    [_vsplit addSubview:_split];
    [_vsplit addSubview:_resultsPanel];
    _resultsPanel.hidden = YES;

    // docking panels (Document List, Document Map, Function List, Folder as Workspace, Project Panels…) left and right
    _docks = [[TPDockManager alloc] initWithCenter:_vsplit];
    [_container addSubview:_toolbar];
    [_container addSubview:_docks.splitView];
    [_container addSubview:_statusBar];
    _container.top = _toolbar;
    _container.middle = _docks.splitView;
    _incBar = [[TPIncrementalSearchBar alloc] initWithController:self];
    _incBar.hidden = YES;
    [_container addSubview:_incBar];
    _container.incBar = _incBar;
    _container.bottom = _statusBar;
    TPMenuBarView *menuBar = [[TPMenuBarView alloc] initWithController:self];
    menuBar.hidden = YES;
    [_container addSubview:menuBar];
    _container.menuBar = menuBar;
    [_container layoutParts];

    _worker = [[ScintillaView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
    _worker.hidden = YES;
    [_container addSubview:_worker];
    SCI(_worker, SCI_SETCODEPAGE, SC_CP_UTF8);
    SCI(_worker, SCI_SETUNDOCOLLECTION, 1);
    _workerScratch = SCI(_worker, SCI_GETDOCPOINTER);
    SCI(_worker, SCI_ADDREFDOCUMENT, 0, _workerScratch);
    _paneScratch[0] = SCI(_mainPane.editor, SCI_GETDOCPOINTER);
    SCI(_mainPane.editor, SCI_ADDREFDOCUMENT, 0, _paneScratch[0]);
    _paneScratch[1] = SCI(_subPane.editor, SCI_GETDOCPOINTER);
    SCI(_subPane.editor, SCI_ADDREFDOCUMENT, 0, _paneScratch[1]);

    _activePane = _mainPane;
    _findController = [[TPFindReplaceController alloc] initWithController:self];
    _mainPane.editor.menu = [self editorContextMenu];
    _subPane.editor.menu = [self editorContextMenu];
}

// ---------------------------------------------------------------- accessors
- (TPEditorPane *)mainPane { return _mainPane; }
- (TPEditorPane *)subPane { return _subPane; }
- (TPEditorPane *)activePane { return _activePane; }
- (TPEditorPane *)otherPane { return _activePane == _mainPane ? _subPane : _mainPane; }
- (ScintillaView *)editor { return _activePane.editor; }
- (TPDocument *)currentDocument { return _activePane.currentDocument; }
- (ScintillaView *)worker { return _worker; }
- (TPStatusBarView *)statusBar { return _statusBar; }
- (TPToolbarView *)toolbar { return _toolbar; }
- (TPFindReplaceController *)findController { return _findController; }
- (TPSearchResultsPanel *)resultsPanel { return _resultsPanel; }
- (NSSplitView *)viewSplitter { return _split; }
- (void)rotateViews { [(TPViewSplitView *)_split rotateViews:nil]; }
- (TPDockManager *)docks { return _docks; }
- (TPIncrementalSearchBar *)incrementalSearchBar { return _incBar; }
- (NSMutableArray<NSString *> *)recentFiles { return _recentFiles; }
- (NSMutableArray<NSString *> *)closedFiles { return _closedFiles; }

- (NSArray<TPDocument *> *)allDocuments {
    NSMutableArray *a = [NSMutableArray arrayWithArray:_mainPane.documents];
    for (TPDocument *d in _subPane.documents) if ([a indexOfObjectIdenticalTo:d] == NSNotFound) [a addObject:d];
    return a;
}

- (TPEditorPane *)paneShowingDocument:(TPDocument *)doc {
    if (_activePane.currentDocument == doc) return _activePane;
    if (self.otherPane.currentDocument == doc && !self.otherPane.hidden) return self.otherPane;
    return nil;
}

- (void)withDocument:(TPDocument *)doc perform:(void (^)(ScintillaView *view))block {
    TPEditorPane *p = [self paneShowingDocument:doc];
    if (p) { block(p.editor); return; }
    SCI(_worker, SCI_SETDOCPOINTER, 0, doc.sciDoc);
    block(_worker);
    BOOL modified = SCI(_worker, SCI_GETMODIFY) != 0 || doc.pendingSaveChange;
    SCI(_worker, SCI_SETDOCPOINTER, 0, _workerScratch);
    if (doc.dirty != modified) { doc.dirty = modified; [self refreshUI]; }
}

// ---------------------------------------------------------------- prompts
// Long texts (help, debug info, error lists) go into a scrolling, selectable box of fixed size instead of growing the
// alert past the screen; short ones stay plain informative text.
BOOL TPAlertTextIsLong(NSString *text) {
    NSUInteger lines = 1;
    for (NSUInteger i = 0; i < text.length; ++i) if ([text characterAtIndex:i] == '\n') ++lines;
    return lines > 12 || text.length > 700;
}

void TPSetAlertText(NSAlert *alert, NSString *text) {
    if (!TPAlertTextIsLong(text)) { alert.informativeText = text; return; }
    NSRect screen = (NSScreen.mainScreen ?: NSScreen.screens.firstObject).visibleFrame;
    const CGFloat w = 560, h = MAX(160, MIN(420, NSHeight(screen) * 0.5));
    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
    sv.hasVerticalScroller = YES;
    sv.autohidesScrollers = YES;
    sv.borderType = NSBezelBorder;
    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
    tv.editable = NO;
    tv.selectable = YES;
    tv.richText = NO;
    tv.drawsBackground = YES;
    tv.backgroundColor = NSColor.textBackgroundColor;
    tv.textColor = NSColor.textColor;
    tv.font = [NSFont monospacedSystemFontOfSize:11.5 weight:NSFontWeightRegular];
    tv.textContainerInset = NSMakeSize(6, 6);
    tv.verticallyResizable = YES;
    tv.horizontallyResizable = NO;
    tv.autoresizingMask = NSViewWidthSizable;
    tv.textContainer.widthTracksTextView = YES;
    tv.string = text;
    sv.documentView = tv;
    alert.accessoryView = sv;
    alert.informativeText = @"";
}

- (NSInteger)prompt:(NSString *)message informative:(NSString *)info buttons:(NSArray<NSString *> *)buttons {
    if (self.promptOverride) return self.promptOverride(message, buttons);
    NSAlert *a = [NSAlert new];
    a.messageText = message;
    if (info) TPSetAlertText(a, info);
    for (NSString *b in buttons) [a addButtonWithTitle:b];
    NSModalResponse r = [a runModal];
    return r - NSAlertFirstButtonReturn;
}

- (void)showMessage:(NSString *)message informative:(NSString *)info {
    if (self.promptOverride) { self.promptOverride(message, @[@"OK"]); return; }
    [self prompt:message informative:info buttons:@[@"OK"]];
}

// ---------------------------------------------------------------- documents
- (sptr_t)createSciDocumentWithText:(const std::string &)utf8 eol:(int)eol {
    sptr_t doc = SCI(_worker, SCI_CREATEDOCUMENT, utf8.size() + 4096,
                     utf8.size() > (size_t)0x7FFFFFFF ? SC_DOCUMENTOPTION_TEXT_LARGE : SC_DOCUMENTOPTION_DEFAULT);
    SCI(_worker, SCI_SETDOCPOINTER, 0, doc);
    SCI(_worker, SCI_SETCODEPAGE, SC_CP_UTF8);
    SCI(_worker, SCI_SETUNDOCOLLECTION, 0);
    if (!utf8.empty()) SCI(_worker, SCI_APPENDTEXT, utf8.size(), reinterpret_cast<sptr_t>(utf8.data()));
    SCI(_worker, SCI_SETUNDOCOLLECTION, 1);
    SCI(_worker, SCI_EMPTYUNDOBUFFER);
    SCI(_worker, SCI_SETSAVEPOINT);
    SCI(_worker, SCI_SETEOLMODE, eol);
    SCI(_worker, SCI_SETCHANGEHISTORY, SC_CHANGE_HISTORY_ENABLED | SC_CHANGE_HISTORY_MARKERS);
    SCI(_worker, SCI_SETDOCPOINTER, 0, _workerScratch);
    return doc;
}

- (ScintillaView *)workerView { return _worker; }

- (int)defaultEol {
    return static_cast<int>([TPPrefs i:@"NewDocEOL"]);   // registered default LF on macOS; upstream Windows default is CR LF
}

- (TPDocument *)newDocument {
    NSMutableSet *used = [NSMutableSet set];
    for (TPDocument *d in self.allDocuments) if (d.isUntitled) [used addObject:d.untitledName];
    int n = 1;
    while ([used containsObject:[NSString stringWithFormat:@"new %d", n]]) ++n;
    TPDocument *doc = [[TPDocument alloc] initUntitled:[NSString stringWithFormat:@"new %d", n]];
    doc.eolMode = [self defaultEol];
    NSInteger cp = [TPPrefs i:@"NewDocCodepage"];
    doc.encoding = tpp::TextEncoding{static_cast<tpp::UniMode>([TPPrefs i:@"NewDocUniMode"]), cp > 0 && tpp::converterAvailable(static_cast<int>(cp)) ? static_cast<int>(cp) : -1};
    NSString *defLang = [TPPrefs s:@"pref.defaultLanguage"];
    if (defLang.length && [[TPLanguageService shared] languageForId:defLang]) doc.languageId = defLang;
    doc.sciDoc = [self createSciDocumentWithText:"" eol:doc.eolMode];
    [self activateDocument:doc inPane:_activePane];
    return doc;
}

- (TPDocument *)documentForPath:(NSString *)path {
    NSString *norm = path.stringByStandardizingPath;
    for (TPDocument *d in self.allDocuments)
        if (d.path && [d.path.stringByStandardizingPath isEqualToString:norm]) return d;
    return nil;
}

- (TPDocument *)openFile:(NSString *)path { return [self openFile:path activate:YES error:nil]; }

- (BOOL)readFile:(NSString *)path into:(std::string &)bytes error:(NSString **)error {
    NSError *err = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:&err];
    if (!data) {
        if (error) *error = err.localizedDescription ?: @"Cannot read file";
        return NO;
    }
    bytes.assign(static_cast<const char *>(data.bytes), data.length);
    return YES;
}

- (void)updateDiskInfo:(TPDocument *)doc {
    if (!doc.path) return;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:doc.path error:nil];
    doc.diskModDate = attrs.fileModificationDate;
    doc.diskSize = attrs.fileSize;
    doc.diskReadOnly = attrs && ![[NSFileManager defaultManager] isWritableFileAtPath:doc.path];
    doc.deletedOnDisk = attrs == nil;
}

- (TPDocument *)openFile:(NSString *)path activate:(BOOL)activate error:(NSString **)error {
    path = path.stringByStandardizingPath;
    TPDocument *existing = [self documentForPath:path];
    if (existing) {
        if (activate) {
            TPEditorPane *p = [_activePane indexOfDocument:existing] != NSNotFound ? _activePane : self.otherPane;
            [self activateDocument:existing inPane:p];
        }
        return existing;
    }
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]) {
        // upstream: "<path> doesn't exist. Create it?"
        if (self.selfTestMode && !self.promptOverride) { if (error) *error = @"File does not exist"; return nil; }
        NSInteger r = [self prompt:[NSString stringWithFormat:@"\"%@\" doesn't exist. Create it?", path] informative:nil buttons:@[@"Yes", @"No"]];
        if (r != 0) return nil;
        if (![[NSData data] writeToFile:path atomically:YES]) {
            [self showMessage:@"Cannot create the file." informative:path];
            return nil;
        }
    } else if (isDir) {
        if (error) *error = @"Is a directory";
        return nil;
    }
    if (![self confirmOpeningFileOfSize:[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil].fileSize]) {
        if (error) *error = @"Not opened: 2GB+ file";
        return nil;
    }
    TPDocument *doc = nil;
    NSString *err = nil;
    if ([[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil].fileSize >= TPStreamedFileBytes) {
        // large files stream into Scintilla on a background thread (progress window, Cancel, no full copies)
        doc = [self loadLargeFile:path error:&err];
        if (!doc) {
            if (error) *error = err;
            else if (![err isEqualToString:@"Opening was cancelled."]) [self showMessage:[NSString stringWithFormat:@"Cannot open file \"%@\".", path] informative:err];
            return nil;
        }
    } else {
        std::string bytes;
        if (![self readFile:path into:bytes error:&err]) {
            if (error) *error = err;
            else [self showMessage:[NSString stringWithFormat:@"Cannot open file \"%@\".", path] informative:err];
            return nil;
        }
        tpp::DecodeResult dr = tpp::detectAndDecode(bytes, [TPPrefs b:@"pref.openAnsiAsUtf8"], [TPPrefs b:@"pref.detectEncoding"]);
        doc = [[TPDocument alloc] initWithPath:path];
        doc.encoding = dr.encoding;
        doc.lossyDecode = dr.lossy;
        doc.containsNul = dr.containsNul;
        doc.eolMode = static_cast<int>(tpp::detectEol(dr.utf8, static_cast<tpp::Eol>([self defaultEol])));
        doc.languageId = [[TPLanguageService shared] languageForFileName:path.lastPathComponent].langId;
        doc.sciDoc = [self createSciDocumentWithText:dr.utf8 eol:doc.eolMode];
    }
    [self updateDiskInfo:doc];
    if ([self isLargeDocument:doc]) {
        // Preferences > Performance > Large File Restriction: no syntax highlighting, optional global wrap off
        doc.languageId = @"normal";
        if ([TPPrefs b:@"pref.largeFileNoWrap"] && [TPPrefs b:@"WordWrap"]) [TPPrefs set:@NO forKey:@"WordWrap"];
    }
    // Replace a single pristine "new 1" like upstream does when opening the first file
    TPDocument *cur = _activePane.currentDocument;
    BOOL replaceEmpty = cur && cur.isUntitled && !cur.dirty && _activePane.documents.count == 1 &&
                        [self paneShowingDocument:cur] && SCI(_activePane.editor, SCI_GETLENGTH) == 0 &&
                        [_subPane indexOfDocument:cur] == NSNotFound;
    if (activate) [self activateDocument:doc inPane:_activePane];
    else [_activePane.documents addObject:doc];
    if (replaceEmpty) {
        [_activePane removeDocument:cur];
        SCI(_worker, SCI_RELEASEDOCUMENT, 0, cur.sciDoc);
        [_activePane reloadTabs];
    }
    [self addRecentFile:path];
    TPPluginNotify(NPPN_FILEOPENED_CODE, doc);
    [self applyOpenPolicyToDocument:doc];   // -fullReadOnly / -monitoringMode
    if (doc.containsNul && !self.selfTestMode) {
        // Not destructive: ANSI decoding is byte-bijective, but tell the user what they opened.
        [_statusBar setText:@"Binary content (NUL bytes) — saved byte-for-byte" forPart:0];
    }
    if (doc.lossyDecode && !self.selfTestMode) {
        [self showMessage:@"Some bytes could not be decoded with the detected encoding."
              informative:@"They are shown as replacement characters. Saving would change the file; use Encoding > Character sets to reinterpret it first."];
    }
    [self refreshUI];
    if (activate) [self offerPreviewForDocument:doc];   // Markdown: Live Preview or text only
    return doc;
}

- (void)addRecentFile:(NSString *)path {
    [_recentFiles removeObject:path];
    [_recentFiles insertObject:path atIndex:0];
    NSInteger max = [[NSUserDefaults standardUserDefaults] integerForKey:@"RecentFilesMax"] ?: 10;
    while ((NSInteger)_recentFiles.count > max) [_recentFiles removeLastObject];
    if (!self.selfTestMode) [[NSUserDefaults standardUserDefaults] setObject:_recentFiles forKey:@"RecentFiles"];
    if (!self.selfTestMode) [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:path]];
}

- (void)activatePane:(TPEditorPane *)pane {
    if (pane.hidden || !pane.currentDocument) return;
    if (_activePane != pane) {
        _activePane = pane;
    }
    _mainPane.tabBar.focused = (_activePane == _mainPane);
    _subPane.tabBar.focused = (_activePane == _subPane);
    [self.window makeFirstResponder:pane.editor.content];
    [self refreshUI];
}

- (void)activateDocument:(TPDocument *)doc inPane:(TPEditorPane *)pane {
    if (pane == _subPane && _subPane.hidden) {
        _subPane.hidden = NO;
        [_split adjustSubviews];
        CGFloat half = (_split.vertical ? NSWidth(_split.bounds) : NSHeight(_split.bounds)) / 2;
        [_split setPosition:half ofDividerAtIndex:0];
    }
    TPDocument *before = _activePane.currentDocument;
    [pane showDocument:doc];
    _activePane = pane;
    _mainPane.tabBar.focused = (_activePane == _mainPane);
    _subPane.tabBar.focused = (_activePane == _subPane);
    if (self.window.isVisible) [self.window makeFirstResponder:pane.editor.content];
    [self refreshUI];
    if (doc != before) TPPluginNotify(NPPN_BUFFERACTIVATED_CODE, doc);
}

- (void)releaseDocumentIfUnused:(TPDocument *)doc {
    if ([_mainPane indexOfDocument:doc] != NSNotFound || [_subPane indexOfDocument:doc] != NSNotFound) return;
    SCI(_worker, SCI_RELEASEDOCUMENT, 0, doc.sciDoc);
    doc.sciDoc = 0;
}

- (BOOL)closeDocument:(TPDocument *)doc inPane:(TPEditorPane *)pane {
    BOOL shownElsewhere = (pane == _mainPane ? _subPane : _mainPane) && [(pane == _mainPane ? _subPane : _mainPane) indexOfDocument:doc] != NSNotFound;
    if (doc.dirty && !shownElsewhere) {
        [self activateDocument:doc inPane:pane];
        NSString *name = doc.path ?: doc.displayName;
        NSInteger r = [self prompt:[NSString stringWithFormat:@"Save file \"%@\" ?", name] informative:nil buttons:@[@"Yes", @"No", @"Cancel"]];
        if (r == 2 || r < 0) return NO;
        if (r == 0 && [self saveDocument:doc] != TPSaveOK) return NO;
    }
    NSInteger idx = [pane indexOfDocument:doc];
    if (idx == NSNotFound) return YES;
    if (!shownElsewhere) TPPluginNotify(NPPN_FILEBEFORECLOSE_CODE, doc);
    BOOL wasCurrent = pane.currentDocument == doc;
    if (wasCurrent) [pane saveCurrentPosition];
    [pane removeDocument:doc];
    if (doc.path && !shownElsewhere) {
        [_closedFiles removeObject:doc.path];
        [_closedFiles addObject:doc.path];
    }
    if (wasCurrent) {
        if (pane.documents.count > 0) {
            NSInteger next = MIN(idx, (NSInteger)pane.documents.count - 1);
            [pane showDocument:pane.documents[next]];
        } else if (pane == _subPane) {
            SCI(_subPane.editor, SCI_SETDOCPOINTER, 0, _paneScratch[1]);
            _subPane.hidden = YES;
            [_split adjustSubviews];
            _activePane = _mainPane;
        } else {
            SCI(_mainPane.editor, SCI_SETDOCPOINTER, 0, _paneScratch[0]);
            if ([TPPrefs b:@"pref.tabExitOnLast"] && _subPane.documents.count == 0 && !self.selfTestMode) {
                [self releaseDocumentIfUnused:doc];
                [NSApp terminate:nil];
                return YES;
            }
            if (!_subPane.hidden && _subPane.documents.count > 0) {
                // upstream: main view keeps at least a "new 1"
                _activePane = _mainPane;
                [self newDocument];
            } else {
                _activePane = _mainPane;
                [self newDocument];
            }
        }
    }
    if (!shownElsewhere) [self releaseDocumentIfUnused:doc];
    [self refreshUI];
    if (!shownElsewhere) TPPluginNotify(NPPN_FILECLOSED_CODE, doc);
    return YES;
}

- (BOOL)closeDocuments:(NSArray<TPDocument *> *)docs inPane:(TPEditorPane *)pane {
    for (TPDocument *d in [docs copy]) if (![self closeDocument:d inPane:pane]) return NO;
    return YES;
}

// ---------------------------------------------------------------- saving
- (TPSaveResult)saveDocument:(TPDocument *)doc {
    if (self.savingForbidden) { TPBeep(); return TPSaveFailed; }   // -fullReadOnlySavingForbidden
    if (doc.isUntitled) return [self saveDocumentAs:doc copy:NO];
    NSString *err = nil;
    if (doc.deletedOnDisk && ![[NSFileManager defaultManager] fileExistsAtPath:doc.path]) {
        // recreate the file at the same location (upstream behaviour when user chose to keep it)
    }
    if (![self writeDocument:doc toPath:doc.path updateDocument:YES error:&err]) {
        if (err.length) {
            NSInteger r = [self prompt:[NSString stringWithFormat:@"Cannot save file \"%@\".", doc.path] informative:[err stringByAppendingString:@"\n\nSave it somewhere else?"] buttons:@[@"Save As…", @"Cancel"]];
            if (r == 0) return [self saveDocumentAs:doc copy:NO];
            return TPSaveFailed;
        }
        return TPSaveCancelled;
    }
    return TPSaveOK;
}

- (TPSaveResult)saveDocumentAs:(TPDocument *)doc copy:(BOOL)asCopy {
    if (self.savingForbidden) { TPBeep(); return TPSaveFailed; }
    NSSavePanel *sp = [NSSavePanel savePanel];
    sp.canCreateDirectories = YES;
    sp.showsHiddenFiles = NO;
    sp.extensionHidden = NO;
    sp.allowsOtherFileTypes = YES;
    sp.nameFieldStringValue = doc.path ? doc.path.lastPathComponent : doc.displayName;
    NSURL *dirURL = [self defaultDirectoryURL];
    if (doc.path && [TPPrefs i:@"pref.defaultDirMode"] == 0) dirURL = [NSURL fileURLWithPath:doc.path.stringByDeletingLastPathComponent];
    if (dirURL) sp.directoryURL = dirURL;
    sp.title = asCopy ? @"Save a Copy As" : @"Save As";
    if ([sp runModal] != NSModalResponseOK) return TPSaveCancelled;
    NSString *path = sp.URL.path;
    [self rememberDirectory:path.stringByDeletingLastPathComponent];
    TPDocument *other = [self documentForPath:path];
    if (other && other != doc && !asCopy) {
        // upstream refuses to save over a file that is open in another tab
        [self showMessage:@"The file you're trying to save is already opened in Textpad++."
              informative:@"Close that tab first, or choose a different name."];
        return TPSaveFailed;
    }
    NSString *err = nil;
    if (![self writeDocument:doc toPath:path updateDocument:!asCopy error:&err]) {
        if (err.length) [self showMessage:[NSString stringWithFormat:@"Cannot save file \"%@\".", path] informative:err];
        return TPSaveFailed;
    }
    if (!asCopy) [self addRecentFile:path];
    return TPSaveOK;
}

// Safe write: encode, warn on lossy conversion, write to a temp file in the same folder,
// copy metadata (mode, ACL, xattrs) from the original, fsync, then atomically rename.
- (BOOL)writeDocument:(TPDocument *)doc toPath:(NSString *)path updateDocument:(BOOL)update error:(NSString **)error {
    __block sptr_t docLength = 0;
    [self withDocument:doc perform:^(ScintillaView *v) { docLength = SCI(v, SCI_GETLENGTH); }];
    if ((unsigned long long)docLength >= TPStreamedFileBytes && !doc.lossyDecode) {
        // large documents: written chunk by chunk from Scintilla's buffer (no copy of the whole text)
        BOOL lossy = NO, allow = NO;
        if (update) [self backupBeforeSave:path];
        if (update) TPPluginNotify(NPPN_FILEBEFORESAVE_CODE, doc);
        BOOL ok = [self streamDocument:doc toPath:path allowLoss:NO lossy:&lossy error:error];
        if (!ok && lossy) {
            NSString *enc = @(tpp::encodingDisplayName(doc.encoding).c_str());
            NSInteger r = [self prompt:@"Saving will lose data" informative:[NSString stringWithFormat:@"Some characters cannot be represented in %@ and will be saved as \"?\".\n\nSave anyway?", enc]
                               buttons:@[@"Cancel", @"Save Anyway"]];
            if (r != 1) { if (error) *error = nil; return NO; }
            allow = YES;
            ok = [self streamDocument:doc toPath:path allowLoss:allow lossy:nil error:error];
        }
        if (!ok) return NO;
        if (update) TPPluginNotify(NPPN_FILESAVED_CODE, doc);
        if (update) [self finishSavingDocument:doc toPath:path];
        return YES;
    }
    __block std::string utf8;
    [self withDocument:doc perform:^(ScintillaView *v) { utf8 = sciGetText(v); }];
    tpp::EncodeResult er = tpp::encode(utf8, doc.encoding);
    if (!er.ok) {
        if (error) *error = @(er.error.c_str());
        return NO;
    }
    if (er.lossy || doc.lossyDecode) {
        NSString *enc = @(tpp::encodingDisplayName(doc.encoding).c_str());
        NSString *msg = er.lossy
            ? [NSString stringWithFormat:@"%zu character(s) cannot be represented in %@ and will be saved as \"?\".", er.lossyCount, enc]
            : @"This document was opened with undecodable bytes; saving will write replacement characters instead of the original bytes.";
        NSInteger r = [self prompt:@"Saving will lose data" informative:[msg stringByAppendingString:@"\n\nSave anyway?"] buttons:@[@"Cancel", @"Save Anyway"]];
        if (r != 1) { if (error) *error = nil; return NO; }
    }
    if (update) [self backupBeforeSave:path];
    if (update) TPPluginNotify(NPPN_FILEBEFORESAVE_CODE, doc);
    if (!TPSafeWriteFile(path, er.bytes, error)) return NO;
    if (update) TPPluginNotify(NPPN_FILESAVED_CODE, doc);
    if (update) [self finishSavingDocument:doc toPath:path];
    return YES;
}

- (void)finishSavingDocument:(TPDocument *)doc toPath:(NSString *)path {
    {
        NSString *oldExt = doc.path.pathExtension.lowercaseString;
        BOOL renamed = ![doc.path isEqualToString:path];
        doc.path = path;
        [self withDocument:doc perform:^(ScintillaView *v) { SCI(v, SCI_SETSAVEPOINT); }];
        doc.dirty = NO;
        doc.pendingSaveChange = NO;
        doc.lossyDecode = NO;
        doc.deletedOnDisk = NO;
        [self updateDiskInfo:doc];
        if (renamed) {
            TPLanguage *newLang = [[TPLanguageService shared] languageForFileName:path.lastPathComponent];
            TPLanguage *oldLang = oldExt.length ? [[TPLanguageService shared] languageForFileName:[@"x." stringByAppendingString:oldExt]] : nil;
            if ([doc.languageId isEqualToString:@"normal"] || (oldLang && [oldLang.langId isEqualToString:doc.languageId]))
                [self setDocumentLanguage:doc languageId:newLang.langId];
        }
        [self refreshUI];
    }
}

// ---------------------------------------------------------------- reload / external changes
- (BOOL)reloadDocument:(TPDocument *)doc encoding:(const tpp::TextEncoding *)enc {
    if (!doc.path) return NO;
    if (!enc && [self appendGrowthOfDocument:doc]) return YES;   // a growing log: only the new bytes
    if ([[NSFileManager defaultManager] attributesOfItemAtPath:doc.path error:nil].fileSize >= TPStreamedFileBytes && !enc) {
        NSString *err = nil;
        TPDocument *fresh = [self loadLargeFile:doc.path error:&err];
        if (!fresh) { if (err && ![err isEqualToString:@"Opening was cancelled."]) [self showMessage:@"Cannot reload the file." informative:err]; return NO; }
        const sptr_t old = doc.sciDoc;
        for (TPEditorPane *p in @[_mainPane, _subPane])
            if (p.currentDocument == doc) SCI(p.editor, SCI_SETDOCPOINTER, 0, fresh.sciDoc);
        doc.sciDoc = fresh.sciDoc;
        fresh.sciDoc = 0;
        SCI(_worker, SCI_RELEASEDOCUMENT, 0, old);
        doc.encoding = fresh.encoding;
        doc.lossyDecode = fresh.lossyDecode;
        doc.dirty = NO;
        for (TPEditorPane *p in @[_mainPane, _subPane])
            if (p.currentDocument == doc) {
                [[TPLanguageService shared] applyLanguageOfDocument:doc toView:p.editor];
                if (doc.monitoring) SCI(p.editor, SCI_DOCUMENTEND);
            }
        [self updateDiskInfo:doc];
        [self refreshUI];
        return YES;
    }
    std::string bytes;
    NSString *err = nil;
    if (![self readFile:doc.path into:bytes error:&err]) {
        [self showMessage:@"Cannot reload the file." informative:err];
        return NO;
    }
    tpp::DecodeResult dr = enc ? tpp::decodeAs(bytes, *enc) : tpp::detectAndDecode(bytes, true, [TPPrefs b:@"pref.detectEncoding"]);
    if (!dr.ok) {
        [self showMessage:@"Cannot reinterpret the file with this encoding." informative:@(dr.error.c_str())];
        return NO;
    }
    TPEditorPane *pane = [self paneShowingDocument:doc];
    __block sptr_t caret = 0, first = 0;
    [self withDocument:doc perform:^(ScintillaView *v) {
        caret = SCI(v, SCI_GETCURRENTPOS);
        first = SCI(v, SCI_GETFIRSTVISIBLELINE);
        BOOL ro = SCI(v, SCI_GETREADONLY) != 0;
        SCI(v, SCI_SETREADONLY, 0);
        SCI(v, SCI_SETUNDOCOLLECTION, 0);
        SCI(v, SCI_CLEARALL);
        if (!dr.utf8.empty()) SCI(v, SCI_APPENDTEXT, dr.utf8.size(), reinterpret_cast<sptr_t>(dr.utf8.data()));
        SCI(v, SCI_SETUNDOCOLLECTION, 1);
        SCI(v, SCI_EMPTYUNDOBUFFER);
        SCI(v, SCI_SETSAVEPOINT);
        SCI(v, SCI_SETREADONLY, ro ? 1 : 0);
        if (doc.monitoring) {
            SCI(v, SCI_DOCUMENTEND);
        } else {
            SCI(v, SCI_GOTOPOS, MIN(caret, SCI(v, SCI_GETLENGTH)));
            SCI(v, SCI_SETFIRSTVISIBLELINE, first);
        }
    }];
    doc.encoding = dr.encoding;
    doc.lossyDecode = dr.lossy;
    doc.dirty = NO;
    [self updateDiskInfo:doc];
    (void)pane;
    [self refreshUI];
    return YES;
}

- (void)fileCheckTick:(NSTimer *)t {
    if (!self.window.isKeyWindow && ![self.allDocuments filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"monitoring == YES"]].count) return;
    [self checkFilesModifiedOnDisk];
}

- (void)checkFilesModifiedOnDisk {
    if (_checkingFiles) return;
    NSInteger mode = [TPPrefs i:@"pref.fileAutoDetect"];   // 0 current file(s), 1 all opened files, 2 disabled
    _checkingFiles = YES;
    NSMutableArray *docs = [NSMutableArray array];
    for (TPDocument *d in self.allDocuments) {
        BOOL visible = _mainPane.currentDocument == d || (!_subPane.hidden && _subPane.currentDocument == d);
        if (d.monitoring || mode == 1 || (mode == 0 && visible)) [docs addObject:d];
    }
    for (TPDocument *doc in docs) {
        if (!doc.path || !doc.diskModDate) continue;
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:doc.path error:nil];
        if (!attrs) {
            if (doc.deletedOnDisk) continue;
            doc.deletedOnDisk = YES;
            if (doc.monitoring) continue;
            // upstream: "The file ... doesn't exist anymore. Keep this file in editor?"
            NSInteger r = [self prompt:[NSString stringWithFormat:@"\"%@\"\n\ndoesn't exist anymore.\nKeep this file in editor?", doc.path] informative:nil buttons:@[@"Yes", @"No"]];
            if (r == 0) {
                doc.pendingSaveChange = YES;  // so that the user is asked to save it again
                doc.dirty = YES;
                [self refreshUI];
            } else {
                TPEditorPane *p = [_mainPane indexOfDocument:doc] != NSNotFound ? _mainPane : _subPane;
                doc.dirty = NO;
                [self closeDocument:doc inPane:p];
            }
            continue;
        }
        doc.deletedOnDisk = NO;
        NSDate *m = attrs.fileModificationDate;
        if (m && ![m isEqualToDate:doc.diskModDate]) {
            doc.diskModDate = m;
            if (doc.monitoring) { tpp::TextEncoding e = doc.encoding; [self reloadDocument:doc encoding:&e]; continue; }
            if ([TPPrefs b:@"pref.updateSilently"] && !doc.dirty) {
                [self reloadDocument:doc encoding:nullptr];
                if ([TPPrefs b:@"pref.updateGotoEOF"]) [self withDocument:doc perform:^(ScintillaView *v) { SCI(v, SCI_DOCUMENTEND); }];
                continue;
            }
            NSString *msg = doc.dirty
                ? [NSString stringWithFormat:@"\"%@\"\n\nThis file has been modified by another program.\nDo you want to reload it and lose the changes made in Textpad++?", doc.path]
                : [NSString stringWithFormat:@"\"%@\"\n\nThis file has been modified by another program.\nDo you want to reload it?", doc.path];
            NSInteger r = [self prompt:msg informative:nil buttons:@[@"Yes", @"No"]];
            if (r == 0) {
                [self reloadDocument:doc encoding:nullptr];
                if ([TPPrefs b:@"pref.updateGotoEOF"]) [self withDocument:doc perform:^(ScintillaView *v) { SCI(v, SCI_DOCUMENTEND); }];
            }
            else { doc.pendingSaveChange = YES; doc.dirty = YES; [self refreshUI]; }
        }
    }
    _checkingFiles = NO;
}

- (BOOL)prepareToQuit {
    return [[TPSession shared] saveForQuitWithController:self];
}

// ---------------------------------------------------------------- language
- (void)setDocumentLanguage:(TPDocument *)doc languageId:(NSString *)langId {
    doc.languageId = langId;
    doc.appliedLexerLanguage = nil;
    for (TPEditorPane *p in @[_mainPane, _subPane])
        if (p.currentDocument == doc) [[TPLanguageService shared] applyLanguageOfDocument:doc toView:p.editor];
    [self refreshUI];
    TPPluginNotify(NPPN_LANGCHANGED_CODE, doc);
}

// ---------------------------------------------------------------- UI refresh
- (void)updateTitle {
    TPDocument *d = self.currentDocument;
    if (!d) { self.window.title = @"Textpad++"; return; }
    self.window.title = [self titleText];
    self.window.documentEdited = d.dirty;
}

static NSString *commafy(long long v) {
    static NSNumberFormatter *f;
    if (!f) { f = [NSNumberFormatter new]; f.numberStyle = NSNumberFormatterDecimalStyle; f.usesGroupingSeparator = YES; f.groupingSeparator = @","; f.groupingSize = 3; }
    return [f stringFromNumber:@(v)];
}

- (void)updateStatusBar {
    TPDocument *d = self.currentDocument;
    ScintillaView *v = self.editor;
    if (!d) return;
    TPLanguage *lang = [[TPLanguageService shared] languageForId:d.languageId];
    [_statusBar setText:lang.longName ?: @"Normal text file" forPart:0];
    sptr_t len = SCI(v, SCI_GETLENGTH);
    sptr_t lines = SCI(v, SCI_GETLINECOUNT);
    [_statusBar setText:[NSString stringWithFormat:@"length : %@    lines : %@", commafy(len), commafy(lines)] forPart:1];
    sptr_t pos = SCI(v, SCI_GETCURRENTPOS);
    sptr_t line = SCI(v, SCI_LINEFROMPOSITION, pos);
    sptr_t col = SCI(v, SCI_GETCOLUMN, pos);
    NSString *sel;
    sptr_t nsel = SCI(v, SCI_GETSELECTIONS);
    if (nsel > 1) {
        long long chars = 0;
        for (sptr_t i = 0; i < nsel; ++i) chars += SCI(v, SCI_COUNTCHARACTERS, SCI(v, SCI_GETSELECTIONNSTART, i), SCI(v, SCI_GETSELECTIONNEND, i));
        sel = [NSString stringWithFormat:@"Sel %ld : %@ | %ld", (long)nsel, commafy(chars), (long)nsel];
    } else {
        sptr_t s = SCI(v, SCI_GETSELECTIONSTART), e = SCI(v, SCI_GETSELECTIONEND);
        if (s == e) sel = [NSString stringWithFormat:@"Pos : %@", commafy(pos + 1)];
        else {
            sptr_t chars = SCI(v, SCI_COUNTCHARACTERS, s, e);
            sptr_t l1 = SCI(v, SCI_LINEFROMPOSITION, s), l2 = SCI(v, SCI_LINEFROMPOSITION, e);
            sel = [NSString stringWithFormat:@"Sel : %@ | %@", commafy(chars), commafy(l2 - l1 + 1)];
        }
    }
    [_statusBar setText:[NSString stringWithFormat:@"Ln : %@    Col : %@    %@", commafy(line + 1), commafy(col + 1), sel] forPart:2];
    int eol = static_cast<int>(SCI(v, SCI_GETEOLMODE));
    [_statusBar setText:@(tpp::eolDisplayName(static_cast<tpp::Eol>(eol))) forPart:3];
    [_statusBar setText:@(tpp::encodingDisplayName(d.encoding).c_str()) forPart:4];
    [_statusBar setText:SCI(v, SCI_GETOVERTYPE) ? @"OVR" : @"INS" forPart:5];
}

- (void)refreshUI {
    [_mainPane reloadTabs];
    [_subPane reloadTabs];
    [self updateTitle];
    [self updateStatusBar];
    [_toolbar refreshStates];
    // line-number margin width follows the line count (upstream "dynamic" width)
    for (TPEditorPane *p in @[_mainPane, _subPane]) {
        if (p.hidden) continue;
        BOOL show = [TPPrefs b:@"pref.lineNumbers"];
        sptr_t lines = SCI(p.editor, SCI_GETLINECOUNT);
        if ([TPPrefs b:@"pref.lineNumDynamic"])   // upstream "Dynamic width": widest visible line number
            lines = MIN(lines, SCI(p.editor, SCI_DOCLINEFROMVISIBLE, SCI(p.editor, SCI_GETFIRSTVISIBLELINE) + SCI(p.editor, SCI_LINESONSCREEN)) + 1);
        int digits = 1;
        while (lines >= 10) { lines /= 10; ++digits; }
        digits = MAX(digits, 3);
        std::string sample(static_cast<size_t>(digits + 1), '9');
        sptr_t w = SCIS(p.editor, SCI_TEXTWIDTH, STYLE_LINENUMBER, sample.c_str());
        SCI(p.editor, SCI_SETMARGINWIDTHN, TPP_MARGIN_LINENUMBER, show ? w + 4 : 0);
    }
    [_docks notifyDocumentsChanged];
}

// ---------------------------------------------------------------- line operation helpers
- (void)getLineRangeForLineOperation:(sptr_t *)fromLine to:(sptr_t *)toLine wholeDocument:(BOOL *)whole {
    ScintillaView *v = self.editor;
    sptr_t s = SCI(v, SCI_GETSELECTIONSTART), e = SCI(v, SCI_GETSELECTIONEND);
    sptr_t l1 = SCI(v, SCI_LINEFROMPOSITION, s), l2 = SCI(v, SCI_LINEFROMPOSITION, e);
    if (s == e || l1 == l2) {
        *whole = YES;
        *fromLine = 0;
        *toLine = SCI(v, SCI_GETLINECOUNT) - 1;
        // a trailing empty line (document ends with EOL) is not part of the operation
        if (*toLine > 0 && SCI(v, SCI_POSITIONFROMLINE, *toLine) == SCI(v, SCI_GETLENGTH)) --*toLine;
    } else {
        *whole = NO;
        if (e == SCI(v, SCI_POSITIONFROMLINE, l2) && l2 > l1) --l2;
        *fromLine = l1;
        *toLine = l2;
    }
}

- (void)replaceLinesFrom:(sptr_t)fromLine to:(sptr_t)toLine withLines:(const std::vector<std::string> &)lines {
    ScintillaView *v = self.editor;
    sptr_t start = SCI(v, SCI_POSITIONFROMLINE, fromLine);
    sptr_t end = SCI(v, SCI_GETLINEENDPOSITION, toLine);
    std::string eol = sciEolString(v);
    std::string text;
    for (size_t i = 0; i < lines.size(); ++i) { if (i) text += eol; text += lines[i]; }
    std::string old = sciGetRange(v, start, end);
    if (old == text) return;
    SCI(v, SCI_BEGINUNDOACTION);
    sciReplaceRange(v, start, end, text);
    SCI(v, SCI_ENDUNDOACTION);
    SCI(v, SCI_SETSEL, start, start + text.size());
}

// ---------------------------------------------------------------- pane / Scintilla notifications
- (void)paneDidBecomeActive:(TPEditorPane *)pane {
    if (_activePane != pane && pane.currentDocument) {
        _activePane = pane;
        _mainPane.tabBar.focused = (_activePane == _mainPane);
        _subPane.tabBar.focused = (_activePane == _subPane);
        [self refreshUI];
    }
}

static BOOL *TPTextChangedFlags(void) { static BOOL f[2] = {YES, YES}; return f; }
- (void)noteTextChangedInPane:(TPEditorPane *)pane { TPTextChangedFlags()[pane.viewIndex & 1] = YES; }

- (void)pane:(TPEditorPane *)pane notification:(SCNotification *)scn {
    [[TPPluginHost shared] forwardScintillaNotification:scn fromView:pane.viewIndex];   // upstream: every Scintilla notification
    TPDocument *doc = pane.currentDocument;
    switch (scn->nmhdr.code) {
        case SCN_SAVEPOINTLEFT:
            if (doc && !doc.dirty) { doc.dirty = YES; [self refreshUI]; }
            break;
        case SCN_SAVEPOINTREACHED:
            if (doc && doc.dirty && !doc.pendingSaveChange) { doc.dirty = NO; [self refreshUI]; }
            break;
        case SCN_UPDATEUI: {
            // Scintilla reports every document change as SC_UPDATE_CONTENT, including the indicators the highlighting
            // below sets. With one document in both views those would re-trigger each other forever (endless repaint,
            // and a hang while entering full screen), so "content" counts only after a text change or a document switch.
            BOOL *textChanged = TPTextChangedFlags();
            static __weak TPDocument *lastShown[2];
            const int vi = pane.viewIndex & 1;
            if (scn->updated & SC_UPDATE_CONTENT) {
                const BOOL real = textChanged[vi] || lastShown[vi] != doc;
                textChanged[vi] = NO;
                lastShown[vi] = doc;
                if (!real) scn->updated &= ~SC_UPDATE_CONTENT;
            }
            if (pane == _activePane) { [self updateStatusBar]; [_toolbar refreshStates]; [_docks notifyEditorViewChanged]; }
            if (scn->updated & (SC_UPDATE_SELECTION | SC_UPDATE_CONTENT)) {
                [self braceMatchInView:pane.editor];
                [self tagMatchInView:pane.editor document:doc];
                [self smartHighlightInView:pane.editor];
            } else if (scn->updated & SC_UPDATE_V_SCROLL) {
                [self smartHighlightInView:pane.editor];
            }
            if (scn->updated & (SC_UPDATE_CONTENT | SC_UPDATE_V_SCROLL)) [self markLinksInView:pane.editor document:doc];
            if (pane == _activePane && (scn->updated & (SC_UPDATE_CONTENT | SC_UPDATE_V_SCROLL)) && _findController.window.isVisible)
                [_findController updateMatchHighlighting];
            if ((scn->updated & SC_UPDATE_V_SCROLL) && [TPPrefs b:@"pref.lineNumDynamic"] && pane == _activePane) [self refreshUI];
            break;
        }
        case SCN_CHARADDED:
            if (scn->ch == '\n' || (scn->ch == '\r' && SCI(pane.editor, SCI_GETEOLMODE) == SC_EOL_CR)) [self autoIndentInView:pane.editor];
            else [self handleCharAdded:scn pane:pane];
            break;
        case SCN_DOUBLECLICK:
            [self handleDoubleClick:scn pane:pane];
            break;
        case SCN_CALLTIPCLICK:   // up/down arrows of a function parameter hint with overloads
            [[TPAutoCompletion forView:pane.editor] callTipClick:scn->position];
            break;
        case SCN_INDICATORCLICK:
            [self handleIndicatorClick:scn pane:pane];
            break;
        case SCN_MODIFIED:
            if (scn->modificationType & (SC_MOD_INSERTTEXT | SC_MOD_DELETETEXT)) [self noteTextChangedInPane:pane];
            if ((scn->modificationType & (SC_MOD_INSERTTEXT | SC_MOD_DELETETEXT)) && doc && doc.isUntitled && [TPPrefs b:@"pref.firstLineAsTabName"]) {
                std::string first = sciGetLine(pane.editor, 0);
                if (first.size() > 60) first.resize(60);
                NSString *t = [NSStr(first) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                if (![t isEqualToString:doc.contentTitle ?: @""]) { doc.contentTitle = t; [pane reloadTabs]; }
            }
            if ((scn->modificationType & (SC_MOD_INSERTTEXT | SC_MOD_DELETETEXT)) && scn->linesAdded != 0 && pane == _activePane) [self refreshUI];
            break;
        case SCN_MACRORECORD:
            [self recordMacroStepFromNotification:scn];
            break;
        case SCN_MARGINCLICK:
            if (scn->margin == TPP_MARGIN_SYMBOL || scn->margin == TPP_MARGIN_LINENUMBER) {
                sptr_t line = SCI(pane.editor, SCI_LINEFROMPOSITION, scn->position);
                if (scn->margin == TPP_MARGIN_SYMBOL && !scn->modifiers) {
                    // upstream: a hide-lines marker shows its section, otherwise the click toggles a bookmark
                    const sptr_t section = tpp::hidelines::sectionForMarkerClick(pane.editor, line);
                    if (section == -1) {
                        if (SCI(pane.editor, SCI_MARKERGET, line) & (1 << TPP_MARK_BOOKMARK)) SCI(pane.editor, SCI_MARKERDELETE, line, TPP_MARK_BOOKMARK);
                        else SCI(pane.editor, SCI_MARKERADD, line, TPP_MARK_BOOKMARK);
                    } else if (section >= 0) {
                        [self showHiddenSectionAt:section ofDocument:pane.currentDocument];
                    }
                }
            }
            break;
        case SCN_ZOOM:
            [self refreshUI];
            break;
        default:
            break;
    }
}

// upstream Buffer::setHideLineChanged(false, location): every view showing the document shows the section,
// then the markers are removed (they belong to the document)
- (void)showHiddenSectionAt:(sptr_t)line ofDocument:(TPDocument *)doc {
    ScintillaView *any = nil;
    for (TPEditorPane *p in @[_mainPane, _subPane])
        if (p.currentDocument == doc) { tpp::hidelines::showHiddenLines(p.editor, line, false, false); any = p.editor; }
    if (any) tpp::hidelines::showHiddenLines(any, line, false, true);
}

// Upstream default "Auto-indent": a new line takes the indentation of the previous line
// (C-like languages also indent after an opening brace, upstream "advanced" mode).
- (void)autoIndentInView:(ScintillaView *)v {
    NSInteger aiMode = [TPPrefs i:@"pref.autoIndent"];   // 0 none, 1 basic, 2 advanced
    if (aiMode == 0) return;
    sptr_t line = SCI(v, SCI_LINEFROMPOSITION, SCI(v, SCI_GETCURRENTPOS));
    if (line == 0 || SCI(v, SCI_GETSELECTIONS) > 1) return;
    sptr_t prev = line - 1;
    sptr_t indent = SCI(v, SCI_GETLINEINDENTATION, prev);
    std::string prevText = sciGetLine(v, prev);
    size_t last = prevText.find_last_not_of(" \t");
    NSString *lid = self.currentDocument.languageId;
    BOOL cLike = [@[@"c", @"cpp", @"cs", @"java", @"javascript.js", @"typescript", @"php", @"objc", @"go", @"rust", @"swift", @"css", @"json", @"json5", @"actionscript", @"d"] containsObject:lid];
    if (aiMode == 2 && cLike && last != std::string::npos && prevText[last] == '{') indent += SCI(v, SCI_GETINDENT) ?: SCI(v, SCI_GETTABWIDTH);
    if (aiMode == 2 && [lid isEqualToString:@"python"] && last != std::string::npos && prevText[last] == ':') indent += SCI(v, SCI_GETINDENT) ?: SCI(v, SCI_GETTABWIDTH);
    if (indent <= 0) return;
    SCI(v, SCI_SETLINEINDENTATION, line, indent);
    SCI(v, SCI_GOTOPOS, SCI(v, SCI_GETLINEINDENTPOSITION, line));
}

// Upstream default "Smart Highlighting": when the selection is a whole word, other occurrences
// in the visible range get the "Smart Highlighting" indicator (whole word, case-insensitive).
- (void)smartHighlightInView:(ScintillaView *)v {
    sptr_t len = SCI(v, SCI_GETLENGTH);
    SCI(v, SCI_SETINDICATORCURRENT, TPP_INDIC_SMART);
    SCI(v, SCI_INDICATORCLEARRANGE, 0, len);
    if (![TPPrefs b:@"pref.smartHL"]) return;
    TPEditorPane *ownerPane = v == _subPane.editor ? _subPane : _mainPane;
    if ([self isLargeDocument:ownerPane.currentDocument] && ![TPPrefs b:@"pref.largeFileSmartHL"]) return;
    if (SCI(v, SCI_GETSELECTIONS) != 1) return;
    sptr_t s = SCI(v, SCI_GETSELECTIONSTART), e = SCI(v, SCI_GETSELECTIONEND);
    if (s == e || e - s > 256) return;
    BOOL useFind = [TPPrefs b:@"pref.smartHLUseFind"];
    tpp::search::Options fo = _findController.currentOptions;
    BOOL wholeWord = useFind ? fo.wholeWord : [TPPrefs b:@"pref.smartHLWholeWord"];
    BOOL matchCase = useFind ? fo.matchCase : [TPPrefs b:@"pref.smartHLMatchCase"];
    if (SCI(v, SCI_WORDSTARTPOSITION, s, 1) != s || SCI(v, SCI_WORDENDPOSITION, s, 1) != e) return;   // the selection must be a word, as upstream
    std::string word = sciGetRange(v, s, e);
    if (word.find_first_of(" \t\r\n") != std::string::npos) return;
    sptr_t firstLine = SCI(v, SCI_DOCLINEFROMVISIBLE, SCI(v, SCI_GETFIRSTVISIBLELINE));
    sptr_t lastLine = SCI(v, SCI_DOCLINEFROMVISIBLE, SCI(v, SCI_GETFIRSTVISIBLELINE) + SCI(v, SCI_LINESONSCREEN) + 1);
    sptr_t from = MAX((sptr_t)0, SCI(v, SCI_POSITIONFROMLINE, firstLine));
    sptr_t to = lastLine >= SCI(v, SCI_GETLINECOUNT) ? len : SCI(v, SCI_GETLINEENDPOSITION, lastLine);
    if (to < from || to > len) to = len;
    SCI(v, SCI_SETSEARCHFLAGS, (wholeWord ? SCFIND_WHOLEWORD : 0) | (matchCase ? SCFIND_MATCHCASE : 0));
    sptr_t pos = from;
    int guard = 0;
    while (pos < to && guard++ < 5000) {
        SCI(v, SCI_SETTARGETRANGE, pos, to);
        sptr_t f = SCI(v, SCI_SEARCHINTARGET, word.size(), reinterpret_cast<sptr_t>(word.data()));
        if (f < 0) break;
        sptr_t te = SCI(v, SCI_GETTARGETEND);
        if (f != s) SCI(v, SCI_INDICATORFILLRANGE, f, te - f);
        pos = te > f ? te : f + 1;
    }
    // "Highlight another view": same word in the other visible view
    ScintillaView *other = v == _mainPane.editor ? _subPane.editor : _mainPane.editor;
    if ([TPPrefs b:@"pref.smartHLOtherView"] && !_subPane.hidden) {
        sptr_t olen = SCI(other, SCI_GETLENGTH);
        SCI(other, SCI_SETINDICATORCURRENT, TPP_INDIC_SMART);
        SCI(other, SCI_INDICATORCLEARRANGE, 0, olen);
        sptr_t of = SCI(other, SCI_POSITIONFROMLINE, SCI(other, SCI_DOCLINEFROMVISIBLE, SCI(other, SCI_GETFIRSTVISIBLELINE)));
        sptr_t ol = SCI(other, SCI_DOCLINEFROMVISIBLE, SCI(other, SCI_GETFIRSTVISIBLELINE) + SCI(other, SCI_LINESONSCREEN) + 1);
        sptr_t ot = ol >= SCI(other, SCI_GETLINECOUNT) ? olen : SCI(other, SCI_GETLINEENDPOSITION, ol);
        SCI(other, SCI_SETSEARCHFLAGS, (wholeWord ? SCFIND_WHOLEWORD : 0) | (matchCase ? SCFIND_MATCHCASE : 0));
        sptr_t p2 = of;
        int g2 = 0;
        BOOL same = SCI(other, SCI_GETDOCPOINTER) == SCI(v, SCI_GETDOCPOINTER);
        while (p2 < ot && g2++ < 5000) {
            SCI(other, SCI_SETTARGETRANGE, p2, ot);
            sptr_t f = SCI(other, SCI_SEARCHINTARGET, word.size(), reinterpret_cast<sptr_t>(word.data()));
            if (f < 0) break;
            sptr_t te = SCI(other, SCI_GETTARGETEND);
            if (!(same && f == s)) SCI(other, SCI_INDICATORFILLRANGE, f, te - f);
            p2 = te > f ? te : f + 1;
        }
    }
}

// Preferences > Highlighting > Highlight Matching Tags (upstream XmlMatchedTagsHighlighter, on SCN_UPDATEUI)
- (void)tagMatchInView:(ScintillaView *)v document:(TPDocument *)doc {
    NSString *l = doc.languageId ?: @"";
    BOOL php = [l isEqualToString:@"php"], aspjsp = [l isEqualToString:@"asp"] || [l isEqualToString:@"jsp"];
    BOOL tagLang = php || aspjsp || [l isEqualToString:@"xml"] || [l isEqualToString:@"html"];
    if (![TPPrefs b:@"pref.tagMatch"] || !tagLang) {
        for (int ind : {TPP_INDIC_TAGMATCH, TPP_INDIC_TAGATTR}) { SCI(v, SCI_SETINDICATORCURRENT, ind); SCI(v, SCI_INDICATORCLEARRANGE, 0, SCI(v, SCI_GETLENGTH)); }
        return;
    }
    BOOL matchCase = [l isEqualToString:@"xml"] || ([l isEqualToString:@"html"] && [doc.path.pathExtension.lowercaseString isEqualToString:@"xhtml"]);
    tpp::tagmatch::Highlighter h(v, matchCase);
    h.tagMatch([TPPrefs b:@"pref.tagAttrs"], php || aspjsp, php ? "<?" : "<%", php ? "?>" : "%>", SCI(v, SCI_GETINDENTATIONGUIDES) != SC_IV_NONE);
}

- (void)braceMatchInView:(ScintillaView *)v {
    TPEditorPane *ownerPane = v == _subPane.editor ? _subPane : _mainPane;
    if ([self isLargeDocument:ownerPane.currentDocument] && ![TPPrefs b:@"pref.largeFileBraceMatch"]) return;
    sptr_t pos = SCI(v, SCI_GETCURRENTPOS);
    auto isBrace = [](int c) { return c == '(' || c == ')' || c == '[' || c == ']' || c == '{' || c == '}'; };
    sptr_t at = -1;
    if (pos > 0 && isBrace(static_cast<int>(SCI(v, SCI_GETCHARAT, pos - 1)))) at = pos - 1;
    else if (isBrace(static_cast<int>(SCI(v, SCI_GETCHARAT, pos)))) at = pos;
    if (at < 0) { SCI(v, SCI_BRACEHIGHLIGHT, INVALID_POSITION, INVALID_POSITION); SCI(v, SCI_SETHIGHLIGHTGUIDE, 0); return; }
    sptr_t match = SCI(v, SCI_BRACEMATCH, at, 0);
    if (match < 0) SCI(v, SCI_BRACEBADLIGHT, at);
    else {
        SCI(v, SCI_BRACEHIGHLIGHT, at, match);
        SCI(v, SCI_SETHIGHLIGHTGUIDE, SCI(v, SCI_GETCOLUMN, MIN(at, match)));
    }
}

// ---------------------------------------------------------------- tab bar delegate
- (TPEditorPane *)paneForTabBar:(TPTabBarView *)bar { return bar == _mainPane.tabBar ? _mainPane : _subPane; }

- (void)tabBar:(TPTabBarView *)bar didSelectIndex:(NSInteger)index {
    TPEditorPane *p = [self paneForTabBar:bar];
    if (index >= 0 && index < (NSInteger)p.documents.count) [self activateDocument:p.documents[index] inPane:p];
}

- (void)tabBar:(TPTabBarView *)bar didRequestCloseIndex:(NSInteger)index {
    TPEditorPane *p = [self paneForTabBar:bar];
    if (index >= 0 && index < (NSInteger)p.documents.count) [self closeDocument:p.documents[index] inPane:p];
}

- (void)tabBar:(TPTabBarView *)bar didMoveFrom:(NSInteger)from to:(NSInteger)to {
    TPEditorPane *p = [self paneForTabBar:bar];
    if (from < 0 || to < 0 || from >= (NSInteger)p.documents.count || to >= (NSInteger)p.documents.count) return;
    TPDocument *d = p.documents[from];
    [p.documents removeObjectAtIndex:from];
    [p.documents insertObject:d atIndex:to];
    [p reloadTabs];
}

- (void)tabBarDidDoubleClickEmptyArea:(TPTabBarView *)bar {
    _activePane = [self paneForTabBar:bar];
    [self newDocument];
}

// A tab dragged out of its bar: onto the other view = Move (⌥ = Clone) to Other View, out of the window = Move to New Instance
- (void)tabBar:(TPTabBarView *)bar didDropIndex:(NSInteger)index atWindowPoint:(NSPoint)point copy:(BOOL)copy {
    TPEditorPane *src = [self paneForTabBar:bar];
    if (index < 0 || index >= (NSInteger)src.documents.count) return;
    TPDocument *d = src.documents[(NSUInteger)index];
    NSView *content = self.window.contentView;
    NSPoint inContent = [content convertPoint:point fromView:nil];
    if (!NSPointInRect(inContent, content.bounds)) {
        if (!d.path) { TPBeep(); return; }
        [self activateDocument:d inPane:src];
        [[TPCommandRegistry shared] execute:IDM_VIEW_GOTO_NEW_INSTANCE];
        return;
    }
    TPEditorPane *other = src == _mainPane ? _subPane : _mainPane;
    NSPoint inOther = [other convertPoint:point fromView:nil];
    BOOL overOther = !other.hidden && NSPointInRect(inOther, other.bounds);
    // with a single view, dropping on the right half of the editor area opens the second view (upstream: the
    // other view must be visible; Textpad++ also accepts a drop on the right half)
    if (other.hidden) {
        NSPoint inSrc = [src convertPoint:point fromView:nil];
        overOther = NSPointInRect(inSrc, src.bounds) && inSrc.x > NSWidth(src.bounds) / 2;
    }
    if (!overOther) return;
    [self activateDocument:d inPane:src];
    [self moveOrCloneToOtherView:copy];
}

// Files / folders dropped on the window (upstream Notepad_plus::droppedFiles): files open; a folder becomes a
// Folder as Workspace root, or with Preferences > Default Directory "Open all files of folder…" its files open
- (BOOL)openDroppedURLs:(NSArray<NSURL *> *)urls {
    NSMutableArray *files = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL folderFiles = [TPPrefs b:@"pref.dropFolderOpenFiles"];
    for (NSURL *u in urls) {
        BOOL dir = NO;
        if (![fm fileExistsAtPath:u.path isDirectory:&dir]) continue;
        if (!dir) { [files addObject:u.path]; continue; }
        if (!folderFiles) {
            [self.folderAsWorkspacePanel addRootFolder:u.path];
            [self.docks showPanel:@"faw"];
            continue;
        }
        NSDirectoryEnumerator *en = [fm enumeratorAtURL:u includingPropertiesForKeys:@[NSURLIsRegularFileKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
        NSMutableArray *inFolder = [NSMutableArray array];
        for (NSURL *f in en) { NSNumber *reg = nil; [f getResourceValue:&reg forKey:NSURLIsRegularFileKey error:nil]; if (reg.boolValue) [inFolder addObject:f.path]; }
        [inFolder sortUsingSelector:@selector(localizedStandardCompare:)];
        [files addObjectsFromArray:inFolder];
    }
    for (NSString *f in files) [self openFile:f];
    [self.window makeKeyAndOrderFront:nil];
    return YES;
}

- (void)tabBar:(TPTabBarView *)bar didTogglePinIndex:(NSInteger)index {
    TPEditorPane *p = [self paneForTabBar:bar];
    if (index < 0 || index >= (NSInteger)p.documents.count) return;
    TPDocument *d = p.documents[index];
    d.pinned = !d.pinned;
    // pinned tabs move to the front (upstream 8.8+ behaviour)
    [p.documents removeObjectAtIndex:index];
    NSUInteger firstUnpinned = 0;
    while (firstUnpinned < p.documents.count && p.documents[firstUnpinned].pinned) ++firstUnpinned;
    [p.documents insertObject:d atIndex:d.pinned ? firstUnpinned : firstUnpinned];
    [p reloadTabs];
}

- (NSMenu *)tabBar:(TPTabBarView *)bar menuForIndex:(NSInteger)index {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    NSMenu *m = [[NSMenu alloc] initWithTitle:@"Tab"];
    int items[] = {IDM_FILE_CLOSE, IDM_FILE_CLOSEALL_BUT_CURRENT, IDM_FILE_CLOSEALL_BUT_PINNED, IDM_FILE_CLOSEALL_TOLEFT,
                   IDM_FILE_CLOSEALL_TORIGHT, IDM_FILE_CLOSEALL_UNCHANGED, 0, IDM_FILE_SAVE, IDM_FILE_SAVEAS, 0,
                   IDM_FILE_OPEN_FOLDER, IDM_FILE_OPEN_CMD, 0, IDM_FILE_RENAME, IDM_FILE_DELETE, IDM_FILE_RELOAD, IDM_FILE_PRINT, 0,
                   IDM_EDIT_TOGGLEREADONLY, IDM_EDIT_TOGGLESYSTEMREADONLY, 0, IDM_EDIT_FULLPATHTOCLIP, IDM_EDIT_FILENAMETOCLIP,
                   IDM_EDIT_CURRENTDIRTOCLIP, 0, IDM_VIEW_GOTO_ANOTHER_VIEW, IDM_VIEW_CLONE_TO_ANOTHER_VIEW, 0,
                   IDM_VIEW_TAB_COLOUR_1, IDM_VIEW_TAB_COLOUR_2, IDM_VIEW_TAB_COLOUR_3, IDM_VIEW_TAB_COLOUR_4, IDM_VIEW_TAB_COLOUR_5,
                   IDM_VIEW_TAB_COLOUR_NONE};
    for (int c : items) {
        if (c == 0) { [m addItem:[NSMenuItem separatorItem]]; continue; }
        NSMenuItem *mi = [reg makeItemForCommand:c];
        if (c == IDM_FILE_OPEN_FOLDER) mi.title = @"Open Containing Folder in Finder";
        if (c == IDM_FILE_OPEN_CMD) mi.title = @"Open Containing Folder in Terminal";
        [m addItem:mi];
    }
    NSMenuItem *pin = [[NSMenuItem alloc] initWithTitle:@"Pin Tab" action:@selector(togglePinFromMenu:) keyEquivalent:@""];
    pin.target = self;
    pin.representedObject = @[bar, @(index)];
    if (index < (NSInteger)[self paneForTabBar:bar].documents.count && [self paneForTabBar:bar].documents[index].pinned) pin.title = @"Unpin Tab";
    [m insertItem:pin atIndex:0];
    [m insertItem:[NSMenuItem separatorItem] atIndex:1];
    return m;
}

- (void)togglePinFromMenu:(NSMenuItem *)mi {
    NSArray *a = mi.representedObject;
    [self tabBar:a[0] didTogglePinIndex:[a[1] integerValue]];
}

// ---------------------------------------------------------------- events
- (void)installEventMonitor {
    TPInstallEscapeMonitor(self.window);   // Escape closes pop-ups and dialogs
    __weak TPMainWindowController *weakSelf = self;
    _eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskFlagsChanged
                                                          handler:^NSEvent *(NSEvent *e) {
        TPMainWindowController *s = weakSelf;
        if (!s || e.window != s.window) return e;
        if ([s handleMenuBarToggleEvent:e] && e.type == NSEventTypeKeyDown) return nil;   // F10 / ⌥ alone: in-window menu bar
        if (e.type == NSEventTypeFlagsChanged) return e;
        if (e.type == NSEventTypeKeyDown) {
            // Preferences > Auto-Completion > Insert Selection: TAB / ENTER
            ScintillaView *ed = s.editor;
            if (SCI(ed, SCI_AUTOCACTIVE) && !(e.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl))) {
                unichar ch = e.charactersIgnoringModifiers.length ? [e.charactersIgnoringModifiers characterAtIndex:0] : 0;
                if ((ch == '\t' && ![TPPrefs b:@"pref.autocInsertTab"]) || ((ch == '\r' || ch == 3) && ![TPPrefs b:@"pref.autocInsertEnter"]))
                    SCI(ed, SCI_AUTOCCANCEL);
            }
            if (ScintillaView *focus = [s editorWithKeyFocus]) if ([s handleSnippetKey:e inEditor:focus]) return nil;   // trigger + Tab
            if ([[TPCommandRegistry shared] handleKeyEvent:e]) return nil;
            if (ScintillaView *focus = [s editorWithKeyFocus]) [s editor:focus prepareColumnSelectionForKey:e];
            return e;
        }
        NSView *hit = [s.window.contentView hitTest:[s.window.contentView convertPoint:e.locationInWindow fromView:nil]];
        for (TPEditorPane *p in @[s.mainPane, s.subPane])
            if (!p.hidden && [hit isDescendantOf:p]) { [s paneDidBecomeActive:p]; break; }
        const BOOL contextClick = e.type == NSEventTypeRightMouseDown || (e.modifierFlags & NSEventModifierFlagControl);
        for (TPEditorPane *p in @[s.mainPane, s.subPane])
            if (contextClick && !p.hidden && [hit isDescendantOf:p.editor.content]) [s editor:p.editor rightClickAtWindowPoint:e.locationInWindow];
        return e;
    }];
}

// ---------------------------------------------------------------- window delegate
- (BOOL)windowShouldClose:(NSWindow *)sender {
    if ([self hideToTrayIfWantedFor:TPTrayClose]) return NO;   // Preferences > MISC. > Close to system tray
    [NSApp terminate:nil];
    return NO;
}

- (void)windowDidBecomeKey:(NSNotification *)n {
    [self checkFilesModifiedOnDisk];
}

@end
