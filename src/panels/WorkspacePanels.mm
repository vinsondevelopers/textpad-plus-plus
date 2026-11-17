// Textpad++ — View > Folder as Workspace (upstream WinControls/FileBrowser) and View > Project Panels 1–3
// (upstream WinControls/ProjectPanel, workspace XML files). GPL-3.0-or-later.
#import "panels/Panels.h"
#import "app/MainWindowController.h"
#import "app/EditorPane.h"
#import "app/Document.h"
#import "app/Preferences.h"
#import "search/FindReplaceController.h"
#include <CoreServices/CoreServices.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"   // FSEventStreamScheduleWithRunLoop (fires in nested run loops)

static NSImage *sysIcon(NSString *name) { NSImage *i = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil]; return i; }

static BOOL isSymlink(NSString *path) {
    NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    return [a.fileType isEqualToString:NSFileTypeSymbolicLink];
}


// ================================================================ Folder as Workspace
@implementation TPFSNode
- (NSString *)name { return _path.lastPathComponent; }
- (NSString *)description { return _path; }
@end

@interface TPFolderAsWorkspacePanel () <NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate>
@end

static void fsEventsCallback(ConstFSEventStreamRef stream, void *info, size_t n, void *paths, const FSEventStreamEventFlags flags[], const FSEventStreamEventId ids[]) {
    TPFolderAsWorkspacePanel *panel = (__bridge TPFolderAsWorkspacePanel *)info;
    char **p = static_cast<char **>(paths);
    for (size_t i = 0; i < n; ++i) [panel refreshFolder:[@(p[i]) stringByStandardizingPath]];
}

@implementation TPFolderAsWorkspacePanel {
    __weak TPMainWindowController *_c;
    NSView *_box;
    NSScrollView *_scroll;
    NSMutableArray<TPFSNode *> *_roots;
    FSEventStreamRef _stream;
}

- (instancetype)initWithController:(TPMainWindowController *)c {
    if ((self = [super init])) {
        _c = c;
        _roots = [NSMutableArray array];
        _box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 250, 400)];
        NSStackView *bar = [NSStackView stackViewWithViews:@[]];
        bar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        bar.spacing = 2;
        for (NSArray *b in @[@[@"chevron.down.2", @"Unfold all", @"expandAll"], @[@"chevron.up.2", @"Fold all", @"collapseAll"],
                             @[@"scope", @"Locate current file", @"locateCurrentFile"]]) {
            NSButton *btn = [NSButton buttonWithImage:sysIcon(b[0]) ?: [NSImage new] target:self action:NSSelectorFromString(b[2])];
            btn.bordered = NO; btn.toolTip = b[1];
            btn.accessibilityLabel = b[1];
            [bar addView:btn inGravity:NSStackViewGravityTrailing];
        }
        bar.frame = NSMakeRect(0, 372, 250, 26);
        bar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
        [_box addSubview:bar];
        _scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 250, 370)];
        _scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _scroll.hasVerticalScroller = YES; _scroll.autohidesScrollers = YES;
        _outline = [[NSOutlineView alloc] initWithFrame:_scroll.bounds];
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"n"];
        col.resizingMask = NSTableColumnAutoresizingMask;
        [_outline addTableColumn:col];
        _outline.outlineTableColumn = col;
        _outline.headerView = nil;
        _outline.dataSource = self; _outline.delegate = self;
        _outline.target = self; _outline.doubleAction = @selector(doubleClicked:);
        _outline.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
        NSMenu *m = [[NSMenu alloc] initWithTitle:@""];
        m.delegate = self;
        _outline.menu = m;
        _scroll.documentView = _outline;
        [_box addSubview:_scroll];
        for (NSString *p in [[NSUserDefaults standardUserDefaults] stringArrayForKey:@"faw.roots"] ?: @[]) {
            BOOL dir = NO;
            if ([[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&dir] && dir) [self addRootFolder:p persist:NO];
        }
    }
    return self;
}

- (NSString *)panelIdentifier { return @"faw"; }
- (NSString *)panelTitle { return @"Folder as Workspace"; }
- (NSView *)panelView { return _box; }
- (TPDockSide)defaultSide { return TPDockLeft; }
- (void)focusPanel { [_outline.window makeFirstResponder:_outline]; }

- (NSArray<NSString *> *)rootPaths { return [_roots valueForKey:@"path"]; }

- (void)persist { [[NSUserDefaults standardUserDefaults] setObject:self.rootPaths forKey:@"faw.roots"]; }

- (void)addRootFolder:(NSString *)path { [self addRootFolder:path persist:YES]; }
- (void)addRootFolder:(NSString *)path persist:(BOOL)persist {
    path = path.stringByStandardizingPath;
    for (TPFSNode *r in _roots) if ([r.path isEqualToString:path]) return;
    TPFSNode *n = [TPFSNode new];
    n.path = path; n.isDir = YES; n.isRoot = YES;
    [_roots addObject:n];
    [_outline reloadData];
    [_outline expandItem:n];
    [self restartWatching];
    if (persist) [self persist];
}
- (void)removeRoot:(NSString *)path {
    NSIndexSet *ix = [_roots indexesOfObjectsPassingTest:^BOOL(TPFSNode *n, NSUInteger i, BOOL *s) { return [n.path isEqualToString:path.stringByStandardizingPath]; }];
    [_roots removeObjectsAtIndexes:ix];
    [_outline reloadData];
    [self restartWatching];
    [self persist];
}
- (void)removeAllRoots { [_roots removeAllObjects]; [_outline reloadData]; [self restartWatching]; [self persist]; }

// folders first, then files, case-insensitive (upstream sorts the same way); hidden (dot) files are not shown
- (void)loadChildren:(TPFSNode *)n {
    NSMutableArray *dirs = [NSMutableArray array], *files = [NSMutableArray array];
    BOOL allowLinks = [TPPrefs b:@"pref.symlinksFaW"];
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:n.path error:nil]) {
        if ([name hasPrefix:@"."]) continue;
        NSString *p = [n.path stringByAppendingPathComponent:name];
        TPFSNode *c = [TPFSNode new];
        c.path = p; c.parent = n;
        c.isLink = isSymlink(p);
        BOOL dir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&dir];
        c.isDir = dir && (!c.isLink || allowLinks);   // upstream: symlinks followed only when allowed
        [(c.isDir ? dirs : files) addObject:c];
    }
    NSSortDescriptor *sd = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedStandardCompare:)];
    [dirs sortUsingDescriptors:@[sd]]; [files sortUsingDescriptors:@[sd]];
    n.children = [[dirs arrayByAddingObjectsFromArray:files] mutableCopy];
}

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(TPFSNode *)item {
    if (!item) return (NSInteger)_roots.count;
    if (!item.isDir) return 0;
    if (!item.children) [self loadChildren:item];
    return (NSInteger)item.children.count;
}
- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)i ofItem:(TPFSNode *)item { return item ? item.children[(NSUInteger)i] : _roots[(NSUInteger)i]; }
- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(TPFSNode *)item { return item.isDir; }
- (NSView *)outlineView:(NSOutlineView *)ov viewForTableColumn:(NSTableColumn *)col item:(TPFSNode *)item {
    NSTableCellView *cell = [ov makeViewWithIdentifier:@"faw" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 20)];
        cell.identifier = @"faw";
        NSImageView *iv = [NSImageView imageViewWithImage:[NSImage new]];
        NSTextField *t = [NSTextField labelWithString:@""];
        t.lineBreakMode = NSLineBreakByTruncatingMiddle;
        for (NSView *v in @[iv, t]) { v.translatesAutoresizingMaskIntoConstraints = NO; [cell addSubview:v]; }
        cell.imageView = iv; cell.textField = t;
        [NSLayoutConstraint activateConstraints:@[[iv.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor], [iv.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [iv.widthAnchor constraintEqualToConstant:16], [iv.heightAnchor constraintEqualToConstant:16],
            [t.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:4], [t.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor],
            [t.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]]];
    }
    cell.textField.stringValue = item.name;
    cell.imageView.image = [[NSWorkspace sharedWorkspace] iconForFile:item.path];
    cell.toolTip = item.path;
    return cell;
}

- (TPFSNode *)nodeForPath:(NSString *)path inNodes:(NSArray<TPFSNode *> *)nodes {
    for (TPFSNode *n in nodes) {
        if ([n.path isEqualToString:path]) return n;
        if (n.children && [path hasPrefix:[n.path stringByAppendingString:@"/"]]) { TPFSNode *f = [self nodeForPath:path inNodes:n.children]; if (f) return f; }
    }
    return nil;
}

// FSEvents: re-read a changed folder that is loaded (upstream FolderUpdater / ReadDirectoryChanges)
- (void)refreshFolder:(NSString *)path {
    if ([path hasSuffix:@"/"] && path.length > 1) path = [path substringToIndex:path.length - 1];
    TPFSNode *n = [self nodeForPath:path inNodes:_roots];
    if (!n || !n.isDir || !n.children) return;
    NSMutableSet *expanded = [NSMutableSet set];
    for (TPFSNode *c in n.children) if ([_outline isItemExpanded:c]) [expanded addObject:c.path];
    NSDictionary *old = [NSDictionary dictionaryWithObjects:n.children forKeys:[n.children valueForKey:@"path"]];
    [self loadChildren:n];
    for (NSUInteger i = 0; i < n.children.count; ++i) {   // keep loaded sub-trees
        TPFSNode *prev = old[n.children[i].path];
        if (prev && prev.isDir == n.children[i].isDir) { prev.parent = n; n.children[i] = prev; }
    }
    [_outline reloadItem:n reloadChildren:YES];
    for (TPFSNode *c in n.children) if ([expanded containsObject:c.path]) [_outline expandItem:c];
}

- (void)restartWatching {
    if (_stream) { FSEventStreamStop(_stream); FSEventStreamInvalidate(_stream); FSEventStreamRelease(_stream); _stream = nullptr; }
    if (!_roots.count) return;
    FSEventStreamContext ctx = {0, (__bridge void *)self, nullptr, nullptr, nullptr};
    _stream = FSEventStreamCreate(nullptr, fsEventsCallback, &ctx, (__bridge CFArrayRef)self.rootPaths, kFSEventStreamEventIdSinceNow, 0.3, kFSEventStreamCreateFlagNone);
    if (!_stream) return;
    FSEventStreamScheduleWithRunLoop(_stream, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    FSEventStreamStart(_stream);
}

- (void)dealloc { if (_stream) { FSEventStreamStop(_stream); FSEventStreamInvalidate(_stream); FSEventStreamRelease(_stream); } }

- (void)expandAll { for (TPFSNode *r in _roots) [_outline expandItem:r expandChildren:YES]; }
- (void)collapseAll { for (TPFSNode *r in _roots) [_outline collapseItem:r collapseChildren:YES]; }

- (BOOL)selectPath:(NSString *)path {
    path = path.stringByStandardizingPath;
    for (TPFSNode *r in _roots) {
        if (![path hasPrefix:[r.path stringByAppendingString:@"/"]]) continue;
        TPFSNode *n = r;
        NSArray *rest = [[path substringFromIndex:r.path.length + 1] pathComponents];
        for (NSString *comp in rest) {
            [_outline expandItem:n];
            if (!n.children) [self loadChildren:n];
            TPFSNode *next = nil;
            for (TPFSNode *c in n.children) if ([c.name isEqualToString:comp]) next = c;
            if (!next) return NO;
            n = next;
        }
        NSInteger row = [_outline rowForItem:n];
        if (row < 0) return NO;
        [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        [_outline scrollRowToVisible:row];
        return YES;
    }
    return NO;
}
- (void)locateCurrentFile { if (_c.currentDocument.path) [self selectPath:_c.currentDocument.path]; }

- (TPFSNode *)selectedNode { return [_outline itemAtRow:_outline.clickedRow >= 0 ? _outline.clickedRow : _outline.selectedRow]; }

- (BOOL)openNode:(TPFSNode *)n {
    if (!n || n.isDir) return NO;
    if (n.isLink && ![TPPrefs b:@"pref.symlinksFaW"]) { TPBeep(); return NO; }
    return [_c openFile:n.path] != nil;
}
- (void)doubleClicked:(id)sender {
    TPFSNode *n = self.selectedNode;
    if (n.isDir) { if ([_outline isItemExpanded:n]) [_outline collapseItem:n]; else [_outline expandItem:n]; }
    else [self openNode:n];
}

// upstream FileBrowser context menus (root / folder / file / empty area)
- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    TPFSNode *n = _outline.clickedRow >= 0 ? [_outline itemAtRow:_outline.clickedRow] : nil;
    auto add = [&](NSString *t, SEL s) { NSMenuItem *mi = [menu addItemWithTitle:t action:s keyEquivalent:@""]; mi.target = self; mi.representedObject = n; };
    if (!n) { add(@"Add", @selector(menuAdd:)); add(@"Remove All", @selector(menuRemoveAll:)); return; }
    if (n.isRoot) { add(@"Remove", @selector(menuRemove:)); [menu addItem:[NSMenuItem separatorItem]]; }
    if (!n.isDir) { add(@"Open", @selector(menuOpen:)); [menu addItem:[NSMenuItem separatorItem]]; }
    add(@"Copy path", @selector(menuCopyPath:));
    if (!n.isDir) add(@"Copy file name", @selector(menuCopyName:));
    if (n.isDir) add(@"Find in Files...", @selector(menuFindInFiles:));
    if (!n.isDir) add(@"Run by system", @selector(menuRunBySystem:));
    [menu addItem:[NSMenuItem separatorItem]];
    add(@"Finder here", @selector(menuFinder:));
    add(@"Terminal here", @selector(menuTerminal:));
    if (TPPowerShellPath()) add(@"PowerShell here", @selector(menuPowerShell:));
}
- (void)menuAdd:(id)s {
    NSOpenPanel *op = [NSOpenPanel openPanel];
    op.canChooseDirectories = YES; op.canChooseFiles = NO;
    op.message = @"Select a folder to add in Folder as Workspace panel";
    if ([op runModal] == NSModalResponseOK) [self addRootFolder:op.URL.path];
}
- (void)menuRemoveAll:(id)s { [self removeAllRoots]; }
- (void)menuRemove:(NSMenuItem *)mi { [self removeRoot:[mi.representedObject path]]; }
- (void)menuOpen:(NSMenuItem *)mi { [self openNode:mi.representedObject]; }
- (void)menuCopyPath:(NSMenuItem *)mi { [[NSPasteboard generalPasteboard] clearContents]; [[NSPasteboard generalPasteboard] setString:[mi.representedObject path] forType:NSPasteboardTypeString]; }
- (void)menuCopyName:(NSMenuItem *)mi { [[NSPasteboard generalPasteboard] clearContents]; [[NSPasteboard generalPasteboard] setString:[mi.representedObject name] forType:NSPasteboardTypeString]; }
- (void)menuRunBySystem:(NSMenuItem *)mi { [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:[mi.representedObject path]]]; }
- (NSString *)dirOf:(TPFSNode *)n { return n.isDir ? n.path : n.path.stringByDeletingLastPathComponent; }
- (void)menuFinder:(NSMenuItem *)mi { TPFSNode *n = mi.representedObject; [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:n.path]]]; }
- (void)menuTerminal:(NSMenuItem *)mi { TPOpenTerminalAt([self dirOf:mi.representedObject], NO); }
- (void)menuPowerShell:(NSMenuItem *)mi { TPOpenTerminalAt([self dirOf:mi.representedObject], YES); }
- (void)menuFindInFiles:(NSMenuItem *)mi {
    TPFindReplaceController *f = _c.findController;
    f.directory = [mi.representedObject path];
    [f showTab:TPFindTabFindInFiles];
}

@end

// ================================================================ Project Panels
@implementation TPProjNode
@end

@interface TPProjectPanel () <NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate, NSTextFieldDelegate>
@end

@implementation TPProjectPanel {
    __weak TPMainWindowController *_c;
    NSView *_box;
    NSPopUpButton *_wsMenuButton, *_editMenuButton;
    NSScrollView *_scroll;
}

- (instancetype)initWithController:(TPMainWindowController *)c index:(NSInteger)index {
    if ((self = [super init])) {
        _c = c;
        _index = index;
        _box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 250, 400)];
        _wsMenuButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(2, 372, 110, 24) pullsDown:YES];
        _editMenuButton = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(114, 372, 80, 24) pullsDown:YES];
        for (NSPopUpButton *b in @[_wsMenuButton, _editMenuButton]) {
            b.autoresizingMask = NSViewMinYMargin;
            b.menu.delegate = self;
            b.bezelStyle = NSBezelStyleTexturedRounded;
            [_box addSubview:b];
        }
        [_wsMenuButton addItemWithTitle:@"Workspace"];
        [_editMenuButton addItemWithTitle:@"Edit"];
        _scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 250, 370)];
        _scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _scroll.hasVerticalScroller = YES; _scroll.autohidesScrollers = YES;
        _outline = [[NSOutlineView alloc] initWithFrame:_scroll.bounds];
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"n"];
        col.resizingMask = NSTableColumnAutoresizingMask;
        col.editable = YES;
        [_outline addTableColumn:col];
        _outline.outlineTableColumn = col;
        _outline.headerView = nil;
        _outline.dataSource = self; _outline.delegate = self;
        _outline.target = self; _outline.doubleAction = @selector(doubleClicked:);
        NSMenu *m = [[NSMenu alloc] initWithTitle:@"context"];
        m.delegate = self;
        _outline.menu = m;
        _scroll.documentView = _outline;
        [_box addSubview:_scroll];
        [self newWorkspaceDiscarding];
        NSString *ws = [[NSUserDefaults standardUserDefaults] stringForKey:[self defaultsKey]];
        if (ws.length && [[NSFileManager defaultManager] fileExistsAtPath:ws]) [self openWorkspace:ws];
    }
    return self;
}

- (NSString *)defaultsKey { return [NSString stringWithFormat:@"project.%ld.workspace", (long)_index]; }
- (NSString *)panelIdentifier { return [NSString stringWithFormat:@"project%ld", (long)_index]; }
- (NSString *)panelTitle { return [NSString stringWithFormat:@"Project Panel %ld", (long)_index]; }
- (NSView *)panelView { return _box; }
- (TPDockSide)defaultSide { return TPDockLeft; }
- (void)focusPanel { [_outline.window makeFirstResponder:_outline]; }

- (void)setDirty:(BOOL)d { _dirty = d; _root.name = _workspacePath ? _workspacePath.lastPathComponent : @"Workspace"; [_outline reloadItem:_root]; }

- (void)newWorkspaceDiscarding {
    _root = [TPProjNode new];
    _root.kind = TPProjNodeWorkspace;
    _root.name = @"Workspace";
    _root.children = [NSMutableArray array];
    _workspacePath = nil;
    _dirty = NO;
    [_outline reloadData];
    [_outline expandItem:_root];
}

// "The current workspace was modified. Do you want to save the current project?" -> NO when cancelled
- (BOOL)saveIfDirtyWithTitle:(NSString *)title {
    if (!_dirty) return YES;
    NSInteger r = [_c prompt:@"The current workspace was modified. Do you want to save the current project?" informative:title buttons:@[@"Yes", @"No", @"Cancel"]];
    if (r == 2 || r < 0) return NO;
    if (r == 0) return [self saveWorkspace];
    return YES;
}

- (void)newWorkspace { if ([self saveIfDirtyWithTitle:@"New Workspace"]) { [self newWorkspaceDiscarding]; [[NSUserDefaults standardUserDefaults] removeObjectForKey:[self defaultsKey]]; } }

- (void)buildFrom:(NSXMLElement *)e into:(TPProjNode *)parent baseDir:(NSString *)base {
    for (NSXMLNode *child in e.children) {
        if (child.kind != NSXMLElementKind) continue;
        NSXMLElement *ce = (NSXMLElement *)child;
        NSString *name = [ce attributeForName:@"name"].stringValue ?: @"";
        TPProjNode *n = [TPProjNode new];
        n.parent = parent;
        if ([ce.name isEqualToString:@"Folder"] || [ce.name isEqualToString:@"Project"]) {
            n.kind = [ce.name isEqualToString:@"Project"] ? TPProjNodeProject : TPProjNodeFolder;
            n.name = name;
            n.children = [NSMutableArray array];
            [self buildFrom:ce into:n baseDir:base];
        } else if ([ce.name isEqualToString:@"File"]) {
            n.kind = TPProjNodeFile;
            NSString *p = [name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
            n.filePath = ([p hasPrefix:@"/"] ? p : [base stringByAppendingPathComponent:p]).stringByStandardizingPath;
            n.name = n.filePath.lastPathComponent;
        } else continue;
        [parent.children addObject:n];
    }
}

- (BOOL)openWorkspace:(NSString *)path {
    NSData *d = [NSData dataWithContentsOfFile:path];
    NSXMLDocument *doc = d ? [[NSXMLDocument alloc] initWithData:d options:0 error:nil] : nil;
    if (![doc.rootElement.name isEqualToString:@"NotepadPlus"]) {
        [_c showMessage:@"Open Workspace" informative:@"The workspace could not be opened. It seems the file to open is not a valid project file."];
        return NO;
    }
    [self newWorkspaceDiscarding];
    _workspacePath = path.stringByStandardizingPath;
    [self buildFrom:doc.rootElement into:_root baseDir:_workspacePath.stringByDeletingLastPathComponent];
    _root.name = _workspacePath.lastPathComponent;
    [[NSUserDefaults standardUserDefaults] setObject:_workspacePath forKey:[self defaultsKey]];
    [_outline reloadData];
    [_outline expandItem:_root expandChildren:YES];
    return YES;
}

// upstream ProjectPanel::getRelativePath: relative when under the workspace folder, else absolute
- (NSString *)relativePath:(NSString *)file to:(NSString *)wsFile {
    NSString *dir = wsFile.stringByDeletingLastPathComponent;
    if ([file hasPrefix:[dir stringByAppendingString:@"/"]]) return [file substringFromIndex:dir.length + 1];
    return file;
}

- (void)writeNode:(TPProjNode *)n into:(NSXMLElement *)e wsFile:(NSString *)ws {
    for (TPProjNode *c in n.children) {
        NSXMLElement *ce = [NSXMLElement elementWithName:c.kind == TPProjNodeProject ? @"Project" : c.kind == TPProjNodeFolder ? @"Folder" : @"File"];
        [ce addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:c.kind == TPProjNodeFile ? [self relativePath:c.filePath to:ws] : c.name]];
        if (c.kind != TPProjNodeFile) [self writeNode:c into:ce wsFile:ws];
        [e addChild:ce];
    }
}

- (BOOL)saveWorkspaceTo:(NSString *)path asCopy:(BOOL)copy {
    NSXMLElement *root = [NSXMLElement elementWithName:@"NotepadPlus"];
    [self writeNode:_root into:root wsFile:path];
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement:root];
    doc.characterEncoding = @"UTF-8";
    NSData *data = [doc XMLDataWithOptions:NSXMLNodePrettyPrint];
    std::string bytes(static_cast<const char *>(data.bytes), data.length);
    NSString *err = nil;
    if (!TPSafeWriteFile(path, bytes, &err)) {
        [_c showMessage:@"An error occurred while writing your workspace file." informative:err];
        return NO;
    }
    if (!copy) {
        _workspacePath = path.stringByStandardizingPath;
        [[NSUserDefaults standardUserDefaults] setObject:_workspacePath forKey:[self defaultsKey]];
        self.dirty = NO;
    }
    return YES;
}

- (NSString *)askSavePath {
    NSSavePanel *sp = [NSSavePanel savePanel];
    NSString *ext = [[TPPrefs s:@"pref.workspaceFileExt"] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@". "]];
    sp.nameFieldStringValue = ext.length ? [@"Workspace." stringByAppendingString:ext] : @"Workspace";
    return [sp runModal] == NSModalResponseOK ? sp.URL.path : nil;
}
- (BOOL)saveWorkspace {
    NSString *p = _workspacePath ?: [self askSavePath];
    return p && [self saveWorkspaceTo:p asCopy:NO];
}
- (void)reloadWorkspace {
    if (!_workspacePath || ![[NSFileManager defaultManager] fileExistsAtPath:_workspacePath]) { [_c showMessage:@"Reload Workspace" informative:@"Cannot find the file to reload."]; return; }
    if (_dirty && [_c prompt:@"The current workspace was modified. Reloading will discard all modifications. Do you want to continue?" informative:nil buttons:@[@"Yes", @"No"]] != 0) return;
    [self openWorkspace:_workspacePath];
}

- (TPProjNode *)addProjectNamed:(NSString *)name {
    TPProjNode *p = [TPProjNode new];
    p.kind = TPProjNodeProject; p.name = name ?: @"Project Name"; p.children = [NSMutableArray array]; p.parent = _root;
    [_root.children addObject:p];
    [self changed:p];
    return p;
}
- (TPProjNode *)addFolderNamed:(NSString *)name to:(TPProjNode *)parent {
    if (parent.kind == TPProjNodeFile || parent.kind == TPProjNodeWorkspace) return nil;
    TPProjNode *f = [TPProjNode new];
    f.kind = TPProjNodeFolder; f.name = name ?: @"Folder Name"; f.children = [NSMutableArray array]; f.parent = parent;
    [parent.children addObject:f];
    [self changed:f];
    return f;
}
- (void)addFiles:(NSArray<NSString *> *)paths to:(TPProjNode *)parent {
    if (parent.kind == TPProjNodeFile || parent.kind == TPProjNodeWorkspace) return;
    for (NSString *p in paths) {
        TPProjNode *f = [TPProjNode new];
        f.kind = TPProjNodeFile; f.filePath = p.stringByStandardizingPath; f.name = p.lastPathComponent; f.parent = parent;
        [parent.children addObject:f];
    }
    [self changed:parent];
}
// upstream "Add Files from Directory...": a folder node per sub-directory, recursively; hidden items skipped
- (void)addFilesFromDirectory:(NSString *)dir to:(TPProjNode *)parent {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *items = [[fm contentsOfDirectoryAtPath:dir error:nil] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *name in items) {
        if ([name hasPrefix:@"."]) continue;
        NSString *p = [dir stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        [fm fileExistsAtPath:p isDirectory:&isDir];
        if (isDir) [self addFilesFromDirectory:p to:[self addFolderNamed:name to:parent]];
        else [files addObject:p];
    }
    [self addFiles:files to:parent];
}
- (void)removeNode:(TPProjNode *)n {
    if (!n.parent) return;
    [n.parent.children removeObject:n];
    [self changed:n.parent];
}
- (void)renameNode:(TPProjNode *)n to:(NSString *)name {
    if (!name.length || n.kind == TPProjNodeWorkspace) return;
    if (n.kind == TPProjNodeFile) {   // upstream: renaming a file entry changes the displayed name only
        n.name = name;
    } else n.name = name;
    [self changed:n];
}
- (void)moveNode:(TPProjNode *)n by:(NSInteger)delta {
    NSMutableArray *sib = n.parent.children;
    NSInteger i = (NSInteger)[sib indexOfObject:n], j = i + delta;
    if (i == NSNotFound || j < 0 || j >= (NSInteger)sib.count) return;
    [sib exchangeObjectAtIndex:(NSUInteger)i withObjectAtIndex:(NSUInteger)j];
    [self changed:n];
}
- (void)changed:(TPProjNode *)n {
    _dirty = YES;
    _root.name = _workspacePath ? _workspacePath.lastPathComponent : @"Workspace";
    [_outline reloadData];
    [_outline expandItem:_root expandChildren:YES];
    NSInteger row = [_outline rowForItem:n];
    if (row >= 0) [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
}

- (NSArray<NSString *> *)allFilePaths {
    NSMutableArray *a = [NSMutableArray array];
    NSMutableArray *stack = [NSMutableArray arrayWithObject:_root];
    while (stack.count) {
        TPProjNode *n = stack.firstObject; [stack removeObjectAtIndex:0];
        if (n.kind == TPProjNodeFile) [a addObject:n.filePath];
        [stack addObjectsFromArray:n.children ?: @[]];
    }
    return a;
}

- (TPProjNode *)nodeNamed:(NSString *)name {
    NSMutableArray *stack = [NSMutableArray arrayWithObject:_root];
    while (stack.count) {
        TPProjNode *n = stack.lastObject; [stack removeLastObject];
        if ([n.name isEqualToString:name]) return n;
        [stack addObjectsFromArray:n.children ?: @[]];
    }
    return nil;
}

// outline
- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(TPProjNode *)item { return item ? (NSInteger)item.children.count : 1; }
- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)i ofItem:(TPProjNode *)item { return item ? item.children[(NSUInteger)i] : _root; }
- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(TPProjNode *)item { return item.kind != TPProjNodeFile; }
- (NSView *)outlineView:(NSOutlineView *)ov viewForTableColumn:(NSTableColumn *)col item:(TPProjNode *)item {
    NSTableCellView *cell = [ov makeViewWithIdentifier:@"pp" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 20)];
        cell.identifier = @"pp";
        NSImageView *iv = [NSImageView imageViewWithImage:[NSImage new]];
        NSTextField *t = [NSTextField labelWithString:@""];
        t.editable = YES; t.delegate = self;
        for (NSView *v in @[iv, t]) { v.translatesAutoresizingMaskIntoConstraints = NO; [cell addSubview:v]; }
        cell.imageView = iv; cell.textField = t;
        [NSLayoutConstraint activateConstraints:@[[iv.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor], [iv.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [iv.widthAnchor constraintEqualToConstant:16], [iv.heightAnchor constraintEqualToConstant:16],
            [t.leadingAnchor constraintEqualToAnchor:iv.trailingAnchor constant:4], [t.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor],
            [t.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]]];
    }
    NSString *name = item.name;
    if (item.kind == TPProjNodeWorkspace && _dirty) name = [name stringByAppendingString:@" *"];
    cell.textField.stringValue = name ?: @"";
    BOOL missing = item.kind == TPProjNodeFile && ![[NSFileManager defaultManager] fileExistsAtPath:item.filePath];
    cell.textField.textColor = missing ? NSColor.secondaryLabelColor : NSColor.labelColor;   // upstream: "file missing" icon
    cell.imageView.image = item.kind == TPProjNodeFile ? [[NSWorkspace sharedWorkspace] iconForFile:item.filePath]
                         : sysIcon(item.kind == TPProjNodeWorkspace ? @"square.stack.3d.up" : item.kind == TPProjNodeProject ? @"shippingbox" : @"folder");
    cell.toolTip = item.kind == TPProjNodeFile ? item.filePath : nil;
    return cell;
}
- (void)controlTextDidEndEditing:(NSNotification *)n {
    NSTextField *t = n.object;
    NSInteger row = [_outline rowForView:t];
    TPProjNode *node = row >= 0 ? [_outline itemAtRow:row] : nil;
    if (node && ![t.stringValue isEqualToString:node.name]) [self renameNode:node to:t.stringValue];
}

- (TPProjNode *)selectedNode { return [_outline itemAtRow:_outline.clickedRow >= 0 ? _outline.clickedRow : _outline.selectedRow] ?: _root; }
- (BOOL)openNode:(TPProjNode *)n {
    if (n.kind != TPProjNodeFile) return NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:n.filePath]) { TPBeep(); return NO; }
    return [_c openFile:n.filePath] != nil;
}
- (void)doubleClicked:(id)s {
    TPProjNode *n = self.selectedNode;
    if (n.kind == TPProjNodeFile) [self openNode:n];
    else if ([_outline isItemExpanded:n]) [_outline collapseItem:n]; else [_outline expandItem:n];
}

// Workspace menu, Edit menu and context menu (upstream ProjectManager menus)
- (void)menuNeedsUpdate:(NSMenu *)menu {
    BOOL ws = menu == _wsMenuButton.menu, edit = menu == _editMenuButton.menu;
    NSString *keep = (ws || edit) ? menu.itemArray.firstObject.title : nil;
    [menu removeAllItems];
    if (keep) [menu addItemWithTitle:keep action:nil keyEquivalent:@""];   // pull-down title item
    TPProjNode *n = self.selectedNode;
    auto add = [&](NSString *t, SEL s, BOOL enabled) { NSMenuItem *mi = [menu addItemWithTitle:t action:enabled ? s : nil keyEquivalent:@""]; mi.target = self; mi.representedObject = n; };
    if (ws || (!edit && n.kind == TPProjNodeWorkspace)) {
        add(@"New Workspace", @selector(mNewWs:), YES); add(@"Open Workspace", @selector(mOpenWs:), YES);
        add(@"Reload Workspace", @selector(mReloadWs:), _workspacePath != nil);
        add(@"Save", @selector(mSaveWs:), YES); add(@"Save As...", @selector(mSaveAsWs:), YES); add(@"Save a Copy As...", @selector(mSaveCopyWs:), YES);
        [menu addItem:[NSMenuItem separatorItem]];
        add(@"Add New Project", @selector(mNewProject:), YES);
        [menu addItem:[NSMenuItem separatorItem]];
        add(@"Find in Projects...", @selector(mFindInProjects:), YES);
        return;
    }
    BOOL container = n.kind == TPProjNodeProject || n.kind == TPProjNodeFolder;
    add(@"Rename", @selector(mRename:), n.kind != TPProjNodeWorkspace);
    if (container) {
        add(@"Add Folder", @selector(mAddFolder:), YES);
        add(@"Add Files...", @selector(mAddFiles:), YES);
        add(@"Add Files from Directory...", @selector(mAddDir:), YES);
    }
    add(@"Remove", @selector(mRemove:), n.kind != TPProjNodeWorkspace);
    if (n.kind == TPProjNodeFile) add(@"Modify File Path", @selector(mModifyPath:), YES);
    [menu addItem:[NSMenuItem separatorItem]];
    add(@"Move Up", @selector(mUp:), n.parent && [n.parent.children indexOfObject:n] > 0);
    add(@"Move Down", @selector(mDown:), n.parent && [n.parent.children indexOfObject:n] + 1 < n.parent.children.count);
}
- (void)mNewWs:(id)s { [self newWorkspace]; }
- (void)mOpenWs:(id)s {
    if (![self saveIfDirtyWithTitle:@"Open Workspace"]) return;
    NSOpenPanel *op = [NSOpenPanel openPanel];
    if ([op runModal] == NSModalResponseOK) [self openWorkspace:op.URL.path];
}
- (void)mReloadWs:(id)s { [self reloadWorkspace]; }
- (void)mSaveWs:(id)s { [self saveWorkspace]; }
- (void)mSaveAsWs:(id)s { NSString *p = [self askSavePath]; if (p) [self saveWorkspaceTo:p asCopy:NO]; }
- (void)mSaveCopyWs:(id)s { NSString *p = [self askSavePath]; if (p) [self saveWorkspaceTo:p asCopy:YES]; }
- (void)mNewProject:(id)s { TPProjNode *p = [self addProjectNamed:@"Project Name"]; [self editNameOf:p]; }
- (void)mFindInProjects:(id)s { [_c showFindInProjectsForPanel:_index]; }
- (void)editNameOf:(TPProjNode *)n {
    NSInteger row = [_outline rowForItem:n];
    if (row >= 0 && _outline.window) [_outline editColumn:0 row:row withEvent:nil select:YES];
}
- (void)mRename:(NSMenuItem *)mi { [self editNameOf:mi.representedObject]; }
- (void)mAddFolder:(NSMenuItem *)mi { TPProjNode *f = [self addFolderNamed:@"Folder Name" to:mi.representedObject]; [self editNameOf:f]; }
- (void)mAddFiles:(NSMenuItem *)mi {
    NSOpenPanel *op = [NSOpenPanel openPanel];
    op.allowsMultipleSelection = YES;
    if ([op runModal] == NSModalResponseOK) [self addFiles:[op.URLs valueForKey:@"path"] to:mi.representedObject];
}
- (void)mAddDir:(NSMenuItem *)mi {
    NSOpenPanel *op = [NSOpenPanel openPanel];
    op.canChooseDirectories = YES; op.canChooseFiles = NO;
    if ([op runModal] == NSModalResponseOK) [self addFilesFromDirectory:op.URL.path to:mi.representedObject];
}
- (void)mRemove:(NSMenuItem *)mi {
    TPProjNode *n = mi.representedObject;
    NSString *msg = n.kind == TPProjNodeFile ? @"Are you sure you want to remove this file from the project?"
                                             : @"All the sub-items will be removed. Are you sure you want to remove this folder from the project?";
    if ([_c prompt:msg informative:nil buttons:@[@"Yes", @"No"]] == 0) [self removeNode:n];
}
- (void)mModifyPath:(NSMenuItem *)mi {
    TPProjNode *n = mi.representedObject;
    NSOpenPanel *op = [NSOpenPanel openPanel];
    op.directoryURL = [NSURL fileURLWithPath:n.filePath.stringByDeletingLastPathComponent];
    if ([op runModal] != NSModalResponseOK) return;
    n.filePath = op.URL.path; n.name = op.URL.lastPathComponent;
    [self changed:n];
}
- (void)mUp:(NSMenuItem *)mi { [self moveNode:mi.representedObject by:-1]; }
- (void)mDown:(NSMenuItem *)mi { [self moveNode:mi.representedObject by:1]; }

@end
