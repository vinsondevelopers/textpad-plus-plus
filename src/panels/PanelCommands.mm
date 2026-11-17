// Textpad++ — commands that show / hide the docking panels and act on them. GPL-3.0-or-later.
#import "panels/Panels.h"
#import "app/MainWindowController.h"
#import "app/EditorPane.h"
#import "app/Document.h"
#import "app/Preferences.h"
#import "app/Session.h"
#import "commands/CommandRegistry.h"
#import "search/FindReplaceController.h"

using namespace npp;
#import <objc/runtime.h>

static char kDocList, kDocMap, kFuncList, kFaW, kProjects, kCharPanel, kClipHistory, kPeeker;

@implementation TPMainWindowController (Panels)

- (TPDocumentListPanel *)documentListPanel { return objc_getAssociatedObject(self, &kDocList); }
- (TPDocumentMapPanel *)documentMapPanel { return objc_getAssociatedObject(self, &kDocMap); }
- (TPFunctionListPanel *)functionListPanel { return objc_getAssociatedObject(self, &kFuncList); }
- (TPFolderAsWorkspacePanel *)folderAsWorkspacePanel { return objc_getAssociatedObject(self, &kFaW); }
- (TPCharacterPanel *)characterPanel { return objc_getAssociatedObject(self, &kCharPanel); }
- (TPClipboardHistoryPanel *)clipboardHistoryPanel { return objc_getAssociatedObject(self, &kClipHistory); }
- (TPDocumentPeeker *)documentPeeker {
    TPDocumentPeeker *p = objc_getAssociatedObject(self, &kPeeker);
    if (!p) { p = [[TPDocumentPeeker alloc] initWithController:self]; objc_setAssociatedObject(self, &kPeeker, p, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    return p;
}

// upstream NppNotification TCN_MOUSEHOVERING / TCN_MOUSELEAVING: peek at a tab's document unless it is shown in a view
- (void)tabBar:(TPTabBarView *)bar didHoverIndex:(NSInteger)index {
    TPEditorPane *pane = bar == self.subPane.tabBar ? self.subPane : self.mainPane;
    TPDocument *d = index >= 0 && index < (NSInteger)pane.documents.count ? pane.documents[(NSUInteger)index] : nil;
    const BOOL other = d && d != self.mainPane.currentDocument && d != self.subPane.currentDocument;
    if ([TPPrefs b:@"pref.docPeekOnTab"] && other && bar.window) {
        NSRect r = [bar convertRect:[bar rectForTabAtIndex:index] toView:nil];
        NSPoint bottomLeft = NSMakePoint(NSMinX(r), NSMinY(r));   // window coordinates: y up
        [self.documentPeeker showDocument:d fromPane:pane belowScreenPoint:[bar.window convertPointToScreen:bottomLeft]];
    } else [self.documentPeeker hide];
    if ([TPPrefs b:@"pref.docPeekOnMap"] && [self.docks isPanelVisible:@"docmap"]) self.documentMapPanel.peekDocument = other ? d : nil;
    else if (self.documentMapPanel.peekDocument) self.documentMapPanel.peekDocument = nil;
}
- (TPProjectPanel *)projectPanel:(NSInteger)i {
    NSArray *a = objc_getAssociatedObject(self, &kProjects);
    return i >= 1 && i <= (NSInteger)a.count ? a[(NSUInteger)i - 1] : nil;
}

- (void)showFindInProjectsForPanel:(NSInteger)i {
    TPFindReplaceController *f = self.findController;
    f.project1 = i == 1; f.project2 = i == 2; f.project3 = i == 3;
    [f showTab:TPFindTabFindInProjects];
}

// "The workspace was modified. Do you want to save it?" for each dirty Project Panel (upstream, at exit)
- (BOOL)saveDirtyWorkspacesForQuit {
    for (NSInteger i = 1; i <= 3; ++i) {
        TPProjectPanel *p = [self projectPanel:i];
        if (!p.dirty) continue;
        NSInteger r = [self prompt:[NSString stringWithFormat:@"%@: the workspace was modified. Do you want to save it?", p.panelTitle] informative:nil buttons:@[@"Yes", @"No", @"Cancel"]];
        if (r == 2 || r < 0) return NO;
        if (r == 0 && ![p saveWorkspace]) return NO;
    }
    return YES;
}

- (void)registerPanelCommands {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    __weak TPMainWindowController *ws = self;
    TPDocumentListPanel *docList = [[TPDocumentListPanel alloc] initWithController:self];
    TPDocumentMapPanel *docMap = [[TPDocumentMapPanel alloc] initWithController:self];
    objc_setAssociatedObject(self, &kDocList, docList, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &kDocMap, docMap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    TPFunctionListPanel *funcList = [[TPFunctionListPanel alloc] initWithController:self];
    objc_setAssociatedObject(self, &kFuncList, funcList, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    TPFolderAsWorkspacePanel *faw = [[TPFolderAsWorkspacePanel alloc] initWithController:self];
    NSArray *projects = @[[[TPProjectPanel alloc] initWithController:self index:1], [[TPProjectPanel alloc] initWithController:self index:2],
                          [[TPProjectPanel alloc] initWithController:self index:3]];
    objc_setAssociatedObject(self, &kFaW, faw, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &kProjects, projects, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    TPCharacterPanel *charPanel = [[TPCharacterPanel alloc] initWithController:self];
    TPClipboardHistoryPanel *clip = [[TPClipboardHistoryPanel alloc] initWithController:self];
    objc_setAssociatedObject(self, &kCharPanel, charPanel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &kClipHistory, clip, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (id<TPPanel> p in @[docList, docMap, funcList, faw, charPanel, clip]) [self.docks registerPanel:p];
    for (id<TPPanel> p in projects) [self.docks registerPanel:p];
    self.findController.projectFilesProvider = ^NSArray<NSString *> *(NSArray<NSNumber *> *panels) {
        NSMutableArray *files = [NSMutableArray array];
        for (NSNumber *n in panels) [files addObjectsFromArray:[ws projectPanel:n.integerValue].allFilePaths ?: @[]];
        return files;
    };

    // View > <panel>: toggles, checked while shown (upstream)
    struct { int cmd; NSString *panel; } toggles[] = {{IDM_VIEW_DOCLIST, @"doclist"}, {IDM_VIEW_DOC_MAP, @"docmap"}, {IDM_VIEW_FUNC_LIST, @"funclist"},
                                                    {IDM_VIEW_FILEBROWSER, @"faw"}, {IDM_VIEW_PROJECT_PANEL_1, @"project1"},
                                                    {IDM_VIEW_PROJECT_PANEL_2, @"project2"}, {IDM_VIEW_PROJECT_PANEL_3, @"project3"},
                                                    {IDM_EDIT_CHAR_PANEL, @"charpanel"}, {IDM_EDIT_CLIPBOARDHISTORY_PANEL, @"cliphistory"}};
    for (auto &t : toggles) {
        NSString *pid = t.panel;
        [reg registerCommand:t.cmd handler:^(int c) { [ws.docks togglePanel:pid]; }
                     enabled:nil checked:^BOOL(int c) { return [ws.docks isPanelVisible:pid]; }];
    }
    struct { int cmd; NSString *panel; } switches[] = {{IDM_VIEW_SWITCHTO_FILEBROWSER, @"faw"}, {IDM_VIEW_SWITCHTO_PROJECT_PANEL_1, @"project1"},
                                                       {IDM_VIEW_SWITCHTO_PROJECT_PANEL_2, @"project2"}, {IDM_VIEW_SWITCHTO_PROJECT_PANEL_3, @"project3"}};
    for (auto &sw : switches) {
        NSString *pid = sw.panel;
        [reg registerCommand:sw.cmd handler:^(int c) {
            [ws.docks showPanel:pid];
            id<TPPanel> p = [ws.docks panelWithIdentifier:pid];
            if ([p respondsToSelector:@selector(focusPanel)]) [p focusPanel];
        }];
    }
    // File > Open Folder as Workspace… / Open Containing Folder > Folder as Workspace / > PowerShell
    [reg registerCommand:IDM_FILE_OPENFOLDERASWORKSPACE handler:^(int c) {
        NSOpenPanel *op = [NSOpenPanel openPanel];
        op.canChooseDirectories = YES; op.canChooseFiles = NO; op.allowsMultipleSelection = YES;
        op.message = @"Select a folder to add in Folder as Workspace panel";
        if ([op runModal] != NSModalResponseOK) return;
        for (NSURL *u in op.URLs) [ws.folderAsWorkspacePanel addRootFolder:u.path];
        [ws.docks showPanel:@"faw"];
    }];
    TPCommandPredicate hasPath = ^BOOL(int c) { return ws.currentDocument.path != nil; };
    [reg registerCommand:IDM_FILE_CONTAININGFOLDERASWORKSPACE handler:^(int c) {
        NSString *path = ws.currentDocument.path;
        [ws.folderAsWorkspacePanel addRootFolder:path.stringByDeletingLastPathComponent];
        [ws.docks showPanel:@"faw"];
        [ws.folderAsWorkspacePanel selectPath:path];
    } enabled:hasPath checked:nil];
    [reg registerCommand:IDM_FILE_OPEN_POWERSHELL handler:^(int c) {
        TPOpenTerminalAt(ws.currentDocument.path.stringByDeletingLastPathComponent, YES);
    } enabled:^BOOL(int c) { return ws.currentDocument.path != nil && TPPowerShellPath() != nil; } checked:nil];

    [reg registerCommand:IDM_VIEW_SWITCHTO_FUNC_LIST handler:^(int c) {
        [ws.docks showPanel:@"funclist"];
        [ws.functionListPanel focusPanel];
    }];
    [reg registerCommand:IDM_VIEW_SWITCHTO_DOCLIST handler:^(int c) {
        [ws.docks showPanel:@"doclist"];
        [ws.documentListPanel focusPanel];
    }];

    // Document List context menu (upstream VerticalFileSwitcher)
    TPCommandPredicate hasSel = ^BOOL(int c) { return [ws.docks isPanelVisible:@"doclist"] && ws.documentListPanel.selectedDocuments.count > 0; };
    [reg registerCommand:IDM_DOCLIST_FILESCLOSE handler:^(int c) {
        for (TPDocument *d in ws.documentListPanel.selectedDocuments) {
            TPEditorPane *p = [ws.mainPane indexOfDocument:d] != NSNotFound ? ws.mainPane : ws.subPane;
            if (![ws closeDocument:d inPane:p]) break;
        }
        [ws refreshUI];
    } enabled:hasSel checked:nil];
    [reg registerCommand:IDM_DOCLIST_FILESCLOSEOTHERS handler:^(int c) {
        NSArray *keep = ws.documentListPanel.selectedDocuments;
        for (TPDocument *d in [ws.documentListPanel.rows copy]) {
            if ([keep containsObject:d]) continue;
            TPEditorPane *p = [ws.mainPane indexOfDocument:d] != NSNotFound ? ws.mainPane : ws.subPane;
            if (![ws closeDocument:d inPane:p]) break;
        }
        [ws refreshUI];
    } enabled:hasSel checked:nil];
    for (NSNumber *n in @[@(IDM_DOCLIST_COPYNAMES), @(IDM_DOCLIST_COPYPATHS)]) {
        BOOL paths = n.intValue == IDM_DOCLIST_COPYPATHS;
        [reg registerCommand:n.intValue handler:^(int c) {
            NSMutableArray *a = [NSMutableArray array];
            for (TPDocument *d in ws.documentListPanel.selectedDocuments) [a addObject:paths ? (d.path ?: d.displayName) : d.displayName];
            [[NSPasteboard generalPasteboard] clearContents];
            [[NSPasteboard generalPasteboard] setString:[a componentsJoinedByString:@"\n"] forType:NSPasteboardTypeString];
        } enabled:hasSel checked:nil];
    }
}

// Panels open at the last exit are opened again. With -nosession or in a second instance, only the panels
// checked in Preferences > Multi-Instance & Date > "Panel State and [-nosession]" (upstream).
- (void)restorePanelsForLaunch {
    BOOL limited = [TPSession shared].disabled;
    for (NSString *pid in @[@"doclist", @"docmap", @"funclist", @"faw", @"project1", @"project2", @"project3", @"charpanel", @"cliphistory"]) {
        if (![self.docks panelWithIdentifier:pid]) continue;
        if (![[NSUserDefaults standardUserDefaults] boolForKey:[@"panel.visible." stringByAppendingString:pid]]) continue;
        NSString *group = [pid hasPrefix:@"project"] ? @"project" : pid;
        if (limited && ![TPPrefs b:[@"pref.panelState." stringByAppendingString:group]]) continue;
        [self.docks showPanel:pid];
    }
}

@end

// ---------------------------------------------------------------- Terminal / PowerShell "here"
NSString *TPPowerShellPath(void) {
    NSMutableArray *candidates = [@[@"/opt/homebrew/bin/pwsh", @"/usr/local/bin/pwsh", @"/usr/local/microsoft/powershell/7/pwsh"] mutableCopy];
    for (NSString *dir in [[NSProcessInfo processInfo].environment[@"PATH"] componentsSeparatedByString:@":"])
        if (dir.length) [candidates addObject:[dir stringByAppendingPathComponent:@"pwsh"]];
    for (NSString *p in candidates) if ([[NSFileManager defaultManager] isExecutableFileAtPath:p]) return p;
    return nil;
}

// Terminal opens a folder directly; for PowerShell a small .command script starts pwsh in that folder
void TPOpenTerminalAt(NSString *dir, BOOL powershell) {
    NSURL *term = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"com.apple.Terminal"];
    if (!term || !dir.length) return;
    if (!powershell) {
        [[NSWorkspace sharedWorkspace] openURLs:@[[NSURL fileURLWithPath:dir]] withApplicationAtURL:term configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];
        return;
    }
    NSString *pwsh = TPPowerShellPath();
    if (!pwsh) return;
    auto q = [](NSString *s) { return [NSString stringWithFormat:@"'%@'", [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]]; };
    NSString *script = [NSString stringWithFormat:@"#!/bin/sh\ncd %@ && exec %@ -NoLogo\n", q(dir), q(pwsh)];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"textpad-pwsh-%@.command", NSUUID.UUID.UUIDString]];
    [script writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0700} ofItemAtPath:path error:nil];
    [[NSWorkspace sharedWorkspace] openURLs:@[[NSURL fileURLWithPath:path]] withApplicationAtURL:term configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];
}

