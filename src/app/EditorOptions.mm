// Textpad++ — editor behaviour options from Preferences that upstream implements in
// ScintillaEditView::scintillaNew_Proc (WM_CHAR, WM_KEYDOWN, WM_RBUTTONDOWN) and FileManager::loadFileData.
// GPL-3.0-or-later.
#import "app/MainWindowController.h"
#import "app/Preferences.h"
#import "app/Sci.h"
#import <Carbon/Carbon.h>   // kVK_* key codes

extern NSString *(^TPScintillaInsertTextFilter)(ScintillaView *view, NSString *text);

// a window point in the coordinates SCI_POSITIONFROMPOINT expects (ScintillaCocoa::ConvertPoint)
static NSPoint sciClientPoint(ScintillaView *ed, NSPoint windowPoint) {
    NSPoint r = [ed.content convertPoint:windowPoint fromView:nil];
    NSPoint o = ed.scrollView.contentView.bounds.origin;
    return NSMakePoint(r.x - o.x, r.y - o.y);
}

@implementation TPMainWindowController (EditorOptions)

- (void)installEditorOptionHooks {
    // Editing 2 > Prevent control character (C0 code) typing into document: upstream drops WM_CHAR 0–31 and 127.
    // On macOS they arrive as typed text (Unicode Hex Input, some layouts); Return, Tab and Backspace are keys.
    TPScintillaInsertTextFilter = ^NSString *(ScintillaView *view, NSString *text) {
        if (![TPPrefs b:@"pref.npcNoInputC0"]) return text;
        NSMutableString *kept = nil;
        for (NSUInteger i = 0; i < text.length; ++i) {
            unichar ch = [text characterAtIndex:i];
            BOOL c0 = ch <= 31 || ch == 127;
            if (c0 && !kept) kept = [[text substringToIndex:i] mutableCopy];
            else if (!c0 && kept) [kept appendFormat:@"%C", ch];
        }
        return kept ?: text;
    };
}

- (nullable ScintillaView *)editorWithKeyFocus {
    NSResponder *fr = self.window.firstResponder;
    for (TPEditorPane *p in @[self.mainPane, self.subPane])
        if (!p.hidden && [fr isKindOfClass:NSView.class] && [(NSView *)fr isDescendantOf:p.editor]) return p.editor;
    return nil;
}

// Editing 2 > Enable Column Selection to Multi-Editing (upstream WM_KEYDOWN): an arrow, Home, End, Return or
// Backspace on a column selection turns it into one caret per line; Esc keeps only the main caret.
// ⌥⇧+arrows (Scintilla's column-extend keys on macOS, Alt+Shift on Windows, which upstream never sees) are left alone.
- (BOOL)editor:(ScintillaView *)ed prepareColumnSelectionForKey:(NSEvent *)e {
    if (![TPPrefs b:@"pref.column2Multi"] || ![TPPrefs b:@"pref.multiEditing"]) return NO;
    const sptr_t mode = SCI(ed, SCI_GETSELECTIONMODE);
    if (mode != SC_SEL_RECTANGLE && mode != SC_SEL_THIN) return NO;
    const NSEventModifierFlags m = e.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if ((m & NSEventModifierFlagOption) && (m & NSEventModifierFlagShift)) return NO;
    switch (e.keyCode) {
        case kVK_LeftArrow: case kVK_RightArrow: case kVK_UpArrow: case kVK_DownArrow:
        case kVK_Home: case kVK_End: case kVK_Return: case kVK_ANSI_KeypadEnter: case kVK_Delete:
            SCI(ed, SCI_SETSELECTIONMODE, SC_SEL_STREAM);
            SCI(ed, SCI_SETSELECTIONMODE, SC_SEL_STREAM);   // second call drops the selections, keeps the carets (Scintilla bug 2412)
            return YES;
        case kVK_Escape: {
            const sptr_t caret = SCI(ed, SCI_GETSELECTIONNCARET, SCI(ed, SCI_GETMAINSELECTION));
            SCI(ed, SCI_SETSELECTION, caret, caret);
            SCI(ed, SCI_SETSELECTIONMODE, SC_SEL_STREAM);
            return YES;
        }
    }
    return NO;
}

// Editing 1 > Keep selection when right-click outside of selection. Scintilla on Windows moves the caret to a
// right-click outside the selection (upstream's default); with the option on upstream stops that in the text area.
- (void)editor:(ScintillaView *)ed rightClickAtWindowPoint:(NSPoint)windowPoint {
    if ([TPPrefs b:@"pref.rightClickKeepsSel"]) return;
    NSPoint p = sciClientPoint(ed, windowPoint);
    const uptr_t x = static_cast<uptr_t>(MAX(0.0, p.x));
    const sptr_t y = static_cast<sptr_t>(MAX(0.0, p.y));
    const sptr_t ch = SCI(ed, SCI_CHARPOSITIONFROMPOINT, x, y);   // Editor::PointInSelection
    for (sptr_t i = 0, n = SCI(ed, SCI_GETSELECTIONS); i < n; ++i) {
        const sptr_t a = SCI(ed, SCI_GETSELECTIONNSTART, i), b = SCI(ed, SCI_GETSELECTIONNEND, i);
        if (a < b && ch >= a && ch < b) return;
    }
    SCI(ed, SCI_CANCEL);
    SCI(ed, SCI_SETEMPTYSELECTION, SCI(ed, SCI_POSITIONFROMPOINT, x, y));
}

// upstream FileManager::loadFileData: buffers over INT_MAX ask first unless Performance > Suppress warning is on
- (BOOL)confirmOpeningFileOfSize:(unsigned long long)size {
    const unsigned long long requested = size + MIN(1ull << 20, size / 6);
    if (requested <= (unsigned long long)INT_MAX || [TPPrefs b:@"pref.suppress2GB"]) return YES;
    return [self prompt:@"Opening a huge file of 2GB+ could take several minutes.\nDo you want to open it?"
            informative:@"Opening huge file warning" buttons:@[@"Yes", @"No"]] == 0;
}

@end
