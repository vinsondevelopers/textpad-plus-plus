// Textpad++ — menu bar extra for Minimize to / Close to system tray. GPL-3.0-or-later.
#import "app/SystemTray.h"
#import "app/Preferences.h"
#import "app/Document.h"
#import "app/EditorPane.h"
#import "app/Sci.h"
#import "commands/CommandRegistry.h"
#import <objc/runtime.h>

using namespace npp;

static char kTrayItem;

@implementation TPMainWindowController (SystemTray)

- (NSStatusItem *)trayItem { return objc_getAssociatedObject(self, &kTrayItem); }

- (void)registerTrayCommands {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    __weak TPMainWindowController *ws = self;
    // upstream NppCommands.cpp IDM_SYSTRAYPOPUP_*
    [reg registerCommand:IDM_SYSTRAYPOPUP_ACTIVATE handler:^(int c) { [ws restoreFromTray]; }];
    [reg registerCommand:IDM_SYSTRAYPOPUP_NEWDOC handler:^(int c) { [ws restoreFromTray]; [ws newDocument]; }];
    [reg registerCommand:IDM_SYSTRAYPOPUP_NEW_AND_PASTE handler:^(int c) {
        TPMainWindowController *s = ws;
        [s restoreFromTray];
        TPDocument *d = s.currentDocument;
        if (!d || !d.isUntitled || SCI(s.editor, SCI_GETLENGTH) != 0) [s newDocument];   // upstream: reuse an empty "new N"
        SCI(s.editor, SCI_PASTE);
    }];
    [reg registerCommand:IDM_SYSTRAYPOPUP_OPENFILE handler:^(int c) { [ws restoreFromTray]; [[TPCommandRegistry shared] execute:IDM_FILE_OPEN]; }];
    [reg registerCommand:IDM_SYSTRAYPOPUP_CLOSE handler:^(int c) {
        TPMainWindowController *s = ws;
        const BOOL hidden = !s.window.isVisible;
        [s removeTrayItem];
        if (hidden && !s.selfTestMode) [NSApp terminate:nil];   // upstream: WM_CLOSE when the window is hidden
        else if (hidden) [s.window orderFront:nil];
    }];
}

- (void)installTrayHooks {
    NSButton *mini = [self.window standardWindowButton:NSWindowMiniaturizeButton];
    mini.target = self;
    mini.action = @selector(minimizeClicked:);
}

- (void)minimizeClicked:(id)sender {
    if (![self hideToTrayIfWantedFor:TPTrayMinimize]) [self.window miniaturize:sender];
}

- (BOOL)hideToTrayIfWantedFor:(TPTrayAction)why {
    const NSInteger pref = [TPPrefs i:@"pref.systray"];
    const BOOL wanted = pref == TPTrayMinimizeClose || pref == why;
    if (!wanted) return NO;
    if (!self.trayItem) {
        NSStatusItem *it = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
        NSImage *icon = [NSApp.applicationIconImage copy];
        icon.size = NSMakeSize(18, 18);
        it.button.image = icon;
        it.button.toolTip = self.window.title;
        it.menu = [self trayMenu];
        it.visible = !self.selfTestMode;   // the self-test does not touch the real menu bar
        objc_setAssociatedObject(self, &kTrayItem, it, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [self.window orderOut:nil];
    return YES;
}

// upstream Notepad_plus.rc IDR_SYSTRAYPOPUP_MENU
- (NSMenu *)trayMenu {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    NSMenu *m = [[NSMenu alloc] initWithTitle:@"Popup"];
    NSArray *rows = @[@[@(IDM_SYSTRAYPOPUP_ACTIVATE), @"Activate"], @[@0], @[@(IDM_SYSTRAYPOPUP_NEWDOC), @"New"],
                      @[@(IDM_SYSTRAYPOPUP_NEW_AND_PASTE), @"New and Paste"], @[@(IDM_SYSTRAYPOPUP_OPENFILE), @"Open..."],
                      @[@(IDM_SEARCH_FINDINFILES), @"Find in Files..."], @[@0], @[@(IDM_SYSTRAYPOPUP_CLOSE), @"Close Tray Icon"]];
    for (NSArray *r in rows) {
        if ([r[0] intValue] == 0) { [m addItem:[NSMenuItem separatorItem]]; continue; }
        NSMenuItem *mi = [reg makeItemForCommand:[r[0] intValue]];
        mi.title = r[1];
        [m addItem:mi];
    }
    return m;
}

- (void)removeTrayItem {
    NSStatusItem *it = self.trayItem;
    if (it) [[NSStatusBar systemStatusBar] removeStatusItem:it];
    objc_setAssociatedObject(self, &kTrayItem, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)restoreFromTray {
    [self removeTrayItem];
    if (self.window.isMiniaturized) [self.window deminiaturize:nil];
    [self.window makeKeyAndOrderFront:nil];
    if (!self.selfTestMode) [NSApp activateIgnoringOtherApps:YES];
}

@end
