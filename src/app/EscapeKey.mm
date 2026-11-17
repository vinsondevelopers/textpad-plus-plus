// Textpad++ — Escape closes pop-ups and dialogs. GPL-3.0-or-later.
#import "app/EscapeKey.h"

static void TPCollectButtons(NSView *v, NSMutableArray<NSButton *> *out) {
    for (NSView *s in v.subviews) {
        if ([s isKindOfClass:NSButton.class] && !s.hidden) {
            NSButton *b = (NSButton *)s;
            if (b.bezelStyle != NSBezelStyleDisclosure && b.title.length && b.enabled && ![b isKindOfClass:NSPopUpButton.class]) [out addObject:b];
        }
        TPCollectButtons(s, out);
    }
}

static BOOL TPIsCheckbox(NSButton *b) {
    // checkboxes and radio buttons keep their state; push buttons do not
    return b.allowsMixedState || ([b.cell isKindOfClass:NSButtonCell.class] && ((NSButtonCell *)b.cell).showsStateBy != NSNoCellMask);
}

NSButton *TPEscapeButtonInWindow(NSWindow *w) {
    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    if (w.contentView) TPCollectButtons(w.contentView, buttons);
    NSMutableArray<NSButton *> *push = [NSMutableArray array];
    for (NSButton *b in buttons) if (!TPIsCheckbox(b)) [push addObject:b];
    for (NSButton *b in push) if ([b.keyEquivalent isEqualToString:@"\e"]) return b;
    for (NSString *want in @[@"Cancel", @"Close", @"No", @"Later", @"Not Now", @"Remind Me Later", @"Skip", @"Dismiss", @"Done", @"OK"]) {
        for (NSButton *b in push) {
            NSString *t = [[b.title stringByReplacingOccurrencesOfString:@"…" withString:@""] stringByReplacingOccurrencesOfString:@"..." withString:@""];
            if ([t caseInsensitiveCompare:want] == NSOrderedSame) return b;
        }
    }
    return push.count == 1 ? push.firstObject : nil;
}

static BOOL TPIsPanelWindow(NSWindow *w) {
    // docked panels shown as floating windows (Function List, Search results...) are part of the main window's work
    return [NSStringFromClass(w.class) hasPrefix:@"TPFloatingPanel"] || [w.identifier isEqualToString:@"TPPanelWindow"];
}

BOOL TPHandleEscapeInWindow(NSWindow *w, NSWindow *editorWindow) {
    if (!w || w == editorWindow || TPIsPanelWindow(w)) return NO;
    const BOOL modal = NSApp.modalWindow == w, sheet = w.sheetParent != nil;
    if (modal || sheet) {
        NSButton *b = TPEscapeButtonInWindow(w);
        if (b) { [b performClick:nil]; return YES; }
        if (sheet) [w.sheetParent endSheet:w returnCode:NSModalResponseCancel];
        else { [NSApp stopModalWithCode:NSModalResponseCancel]; [w orderOut:nil]; }
        return YES;
    }
    if (w.attachedSheet) return NO;   // the sheet answers first
    if (!(w.styleMask & NSWindowStyleMaskClosable) && !w.isFloatingPanel) return NO;
    id ctl = w.windowController ?: w.delegate;
    if ([ctl respondsToSelector:@selector(cancelOperation:)]) { [ctl cancelOperation:nil]; return YES; }   // Find: also clears its marks
    [w performClose:nil];
    if (w.isVisible) [w orderOut:nil];   // a window without a close button
    return YES;
}

void TPInstallEscapeMonitor(NSWindow *editorWindow) {
    static id monitor;
    if (monitor) return;
    __weak NSWindow *weakEditor = editorWindow;
    monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e) {
        if (e.keyCode != 53 || (e.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift))) return e;
        NSWindow *w = e.window ?: NSApp.keyWindow;
        // an open combo box / completion list closes first
        if ([w.firstResponder isKindOfClass:NSTextView.class] && [(NSTextView *)w.firstResponder hasMarkedText]) return e;
        return TPHandleEscapeInWindow(w, weakEditor) ? nil : e;
    }];
}
