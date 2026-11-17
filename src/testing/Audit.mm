// Textpad++ — command audit (test-only): every menu command runs once against a prepared document and the audit
// records what it changed. Dialogs, panels, browser / Finder / Terminal launches, printing and quitting are
// intercepted and recorded instead of run. Run with: TEXTPAD_AUDIT=1 Textpad++ --self-test out.jsonl
// GPL-3.0-or-later.
#import "testing/Audit.h"
#import "app/MainWindowController.h"
#import "app/EditorPane.h"
#import "app/Document.h"
#import "app/Preferences.h"
#import "app/ToolbarView.h"
#import "app/Sci.h"
#import "panels/Panels.h"
#import "search/IncrementalSearchBar.h"
#import "commands/CommandRegistry.h"
#import <objc/runtime.h>
#include <functional>
using namespace npp;

@interface TPMainWindowController (AuditHelpers)
- (void)closeAll_forTests;
@end

static NSMutableArray<NSString *> *g_events;
static void note(NSString *s) { [g_events addObject:s ?: @"?"]; }
// the smallest common Mac screen: a 13-inch 1440 x 900 display less the menu bar and Dock
static const NSSize kSmallScreen = {1400, 820};
static void checkSize(NSString *what, NSWindow *w) {
    if (!w) return;
    const NSSize z = w.frame.size;
    if (z.height > kSmallScreen.height || z.width > kSmallScreen.width) note([NSString stringWithFormat:@"OVERSIZE %@: %.0f x %.0f", what, z.width, z.height]);
}

static void replace(Class cls, SEL sel, id block) {
    Method m = class_getInstanceMethod(cls, sel);
    if (m) method_setImplementation(m, imp_implementationWithBlock(block));
}

static void installInterceptors(void) {
    replace(NSAlert.class, @selector(runModal), ^NSModalResponse(NSAlert *a) { note([@"alert: " stringByAppendingString:a.messageText ?: @""]); [a layout]; checkSize([@"alert " stringByAppendingString:a.messageText ?: @""], a.window); return NSAlertSecondButtonReturn; });
    replace(NSAlert.class, @selector(beginSheetModalForWindow:completionHandler:), ^(NSAlert *a, NSWindow *w, void (^h)(NSModalResponse)) {
        note([@"alert sheet: " stringByAppendingString:a.messageText ?: @""]); [a layout]; checkSize([@"alert " stringByAppendingString:a.messageText ?: @""], a.window); if (h) h(NSAlertSecondButtonReturn);
    });
    replace(NSSavePanel.class, @selector(runModal), ^NSModalResponse(NSSavePanel *p) { note([NSString stringWithFormat:@"%@: %@", p.class, p.title ?: p.message ?: @""]); return NSModalResponseCancel; });
    replace(NSSavePanel.class, @selector(beginSheetModalForWindow:completionHandler:), ^(NSSavePanel *p, NSWindow *w, void (^h)(NSModalResponse)) {
        note([NSString stringWithFormat:@"%@ sheet: %@", p.class, p.title ?: @""]); if (h) h(NSModalResponseCancel);
    });
    replace(NSApplication.class, @selector(runModalForWindow:), ^NSModalResponse(NSApplication *app, NSWindow *w) { note([@"modal window: " stringByAppendingString:w.title ?: @""]); checkSize(w.title ?: @"modal window", w); return NSModalResponseCancel; });
    replace(NSApplication.class, @selector(terminate:), ^(NSApplication *app, id s) { note(@"quit"); });
    replace(NSWorkspace.class, @selector(openURL:), ^BOOL(NSWorkspace *ws, NSURL *u) { note([@"open URL: " stringByAppendingString:u.absoluteString ?: @""]); return YES; });
    replace(NSWorkspace.class, @selector(openURL:configuration:completionHandler:), ^(NSWorkspace *ws, NSURL *u, id cfg, id h) { note([@"open URL: " stringByAppendingString:u.absoluteString ?: @""]); });
    replace(NSWorkspace.class, @selector(openURLs:withApplicationAtURL:configuration:completionHandler:), ^(NSWorkspace *ws, NSArray *u, NSURL *app, id cfg, id h) {
        note([NSString stringWithFormat:@"open %lu URL(s) with %@", (unsigned long)u.count, app.lastPathComponent]);
    });
    replace(NSWorkspace.class, @selector(openApplicationAtURL:configuration:completionHandler:), ^(NSWorkspace *ws, NSURL *app, id cfg, id h) { note([@"launch app: " stringByAppendingString:app.lastPathComponent ?: @""]); });
    replace(NSWorkspace.class, @selector(activateFileViewerSelectingURLs:), ^(NSWorkspace *ws, NSArray *u) { note(@"reveal in Finder"); });
    replace(NSWorkspace.class, @selector(selectFile:inFileViewerRootedAtPath:), ^BOOL(NSWorkspace *ws, NSString *f, NSString *r) { note(@"reveal in Finder"); return YES; });
    replace(NSWorkspace.class, @selector(openFile:), ^BOOL(NSWorkspace *ws, NSString *f) { note([@"open file: " stringByAppendingString:f.lastPathComponent ?: @""]); return YES; });
    replace(NSWorkspace.class, @selector(openFile:withApplication:), ^BOOL(NSWorkspace *ws, NSString *f, NSString *a) { note([@"open file with app: " stringByAppendingString:a ?: @""]); return YES; });
    replace(NSTask.class, @selector(launch), ^(NSTask *t) { note([@"process: " stringByAppendingString:t.launchPath ?: t.executableURL.path ?: @""]); });
    replace(NSTask.class, @selector(launchAndReturnError:), ^BOOL(NSTask *t, NSError **e) { note([@"process: " stringByAppendingString:t.executableURL.path ?: @""]); return YES; });
    replace(NSTask.class, @selector(waitUntilExit), ^(NSTask *t) {});
    replace(NSTask.class, @selector(isRunning), ^BOOL(NSTask *t) { return NO; });
    replace(NSTask.class, @selector(terminationStatus), ^int(NSTask *t) { return 0; });
    // class clusters: the objects are private subclasses that override these methods, so replace them there too
    NSPrintOperation *sampleOp = [NSPrintOperation printOperationWithView:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)]];
    for (Class k : {NSPrintOperation.class, sampleOp.class}) {
        replace(k, @selector(runOperation), ^BOOL(NSPrintOperation *op) { note(@"print"); return YES; });
        replace(k, @selector(runOperationModalForWindow:delegate:didRunSelector:contextInfo:), ^(NSPrintOperation *op, NSWindow *w, id d, SEL s, void *ci) { note(@"print"); });
    }
    Class taskClass = [NSTask new].class;
    if (taskClass != NSTask.class) {
        replace(taskClass, @selector(launch), ^(NSTask *t) { note([@"process: " stringByAppendingString:t.launchPath ?: t.executableURL.path ?: @""]); });
        replace(taskClass, @selector(launchAndReturnError:), ^BOOL(NSTask *t, NSError **e) { note([@"process: " stringByAppendingString:t.executableURL.path ?: @""]); return YES; });
        replace(taskClass, @selector(waitUntilExit), ^(NSTask *t) {});
        replace(taskClass, @selector(isRunning), ^BOOL(NSTask *t) { return NO; });
        replace(taskClass, @selector(terminationStatus), ^int(NSTask *t) { return 0; });
    }
}

// ---------------------------------------------------------------- observable state
static NSDictionary *snapshot(TPMainWindowController *c, NSString *fixtureDir) {
    NSMutableDictionary *s = [NSMutableDictionary dictionary];
    ScintillaView *ed = c.editor;
    TPDocument *d = c.currentDocument;
    std::string text = sciGetText(ed);
    s[@"text"] = @(std::hash<std::string>{}(text));
    s[@"selection"] = [NSString stringWithFormat:@"%ld:%ld-%ld/%ld", (long)SCI(ed, SCI_GETSELECTIONS), (long)SCI(ed, SCI_GETSELECTIONSTART), (long)SCI(ed, SCI_GETSELECTIONEND), (long)SCI(ed, SCI_GETSELECTIONMODE)];
    s[@"scroll"] = [NSString stringWithFormat:@"%ld,%ld", (long)SCI(ed, SCI_GETFIRSTVISIBLELINE), (long)SCI(ed, SCI_GETXOFFSET)];
    s[@"view"] = [NSString stringWithFormat:@"wrap%ld zoom%ld ws%ld eol%ld ig%ld ro%ld eolmode%ld edge%ld ovr%ld", (long)SCI(ed, SCI_GETWRAPMODE), (long)SCI(ed, SCI_GETZOOM),
                  (long)SCI(ed, SCI_GETVIEWWS), (long)SCI(ed, SCI_GETVIEWEOL), (long)SCI(ed, SCI_GETINDENTATIONGUIDES), (long)SCI(ed, SCI_GETREADONLY),
                  (long)SCI(ed, SCI_GETEOLMODE), (long)SCI(ed, SCI_GETEDGEMODE), (long)SCI(ed, SCI_GETOVERTYPE)];
    char lexer[64] = {};
    SCI(ed, SCI_GETLEXERLANGUAGE, 0, reinterpret_cast<sptr_t>(lexer));
    s[@"lexer"] = @(lexer);
    NSMutableString *margins = [NSMutableString string];
    for (int i = 0; i < 5; ++i) [margins appendFormat:@"%ld ", (long)SCI(ed, SCI_GETMARGINWIDTHN, i)];
    s[@"margins"] = margins;
    long folded = 0, hidden = 0, markers = 0, styledMarks = 0;
    const sptr_t lines = SCI(ed, SCI_GETLINECOUNT);
    for (sptr_t l = 0; l < lines && l < 400; ++l) {
        if (!SCI(ed, SCI_GETFOLDEXPANDED, l)) ++folded;
        if (!SCI(ed, SCI_GETLINEVISIBLE, l)) ++hidden;
        markers += SCI(ed, SCI_MARKERGET, l) * (l + 1);
    }
    const sptr_t len = SCI(ed, SCI_GETLENGTH);
    for (sptr_t p = 0; p < len && p < 4000; ++p) styledMarks += (SCI(ed, SCI_INDICATORALLONFOR, p) & ~0x1FF) ? 1 : 0;
    s[@"folds/hidden"] = [NSString stringWithFormat:@"%ld/%ld", folded, hidden];
    s[@"markers"] = @(markers);
    s[@"indicators"] = @(styledMarks);
    s[@"popups"] = [NSString stringWithFormat:@"autoc%ld calltip%ld", (long)SCI(ed, SCI_AUTOCACTIVE), (long)SCI(ed, SCI_CALLTIPACTIVE)];
    NSMutableArray *enabledCmds = [NSMutableArray array];
    for (NSNumber *n in [TPCommandRegistry shared].allMenuCommands) if ([[TPCommandRegistry shared] isEnabled:n.intValue]) [enabledCmds addObject:n];
    s[@"enabled commands"] = @([enabledCmds componentsJoinedByString:@","].hash);
    s[@"annotations"] = @(SCI(ed, SCI_ANNOTATIONGETLINES, SCI(ed, SCI_LINEFROMPOSITION, SCI(ed, SCI_GETCURRENTPOS))));
    if (d) s[@"document"] = [NSString stringWithFormat:@"%d/%d %@ eol%d dirty%d ro%d pin%d col%ld mon%d %@", (int)d.encoding.mode, d.encoding.codepage, d.languageId, d.eolMode, d.dirty,
                             d.userReadOnly, d.pinned, (long)d.tabColor, d.monitoring, d.path.lastPathComponent ?: d.displayName];
    s[@"documents"] = [NSString stringWithFormat:@"main%lu sub%lu subHidden%d active%d current%ld", (unsigned long)c.mainPane.documents.count, (unsigned long)c.subPane.documents.count,
                       c.subPane.hidden, c.activePane == c.subPane, (long)[c.activePane indexOfDocument:d]];
    NSMutableArray *wins = [NSMutableArray array];
    for (NSWindow *w in NSApp.windows) if (w.isVisible && w != c.window) [wins addObject:w.title.length ? w.title : NSStringFromClass(w.class)];
    s[@"windows"] = [[wins sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" | "];
    s[@"panels"] = [c.docks.visiblePanelIdentifiers componentsJoinedByString:@","] ?: @"";
    s[@"chrome"] = [NSString stringWithFormat:@"tb%d tab%d sb%d inc%d full%d alpha%.2f level%ld title%@", c.toolbar.hidden, c.mainPane.tabBar.hidden, c.statusBar.hidden,
                    !c.incrementalSearchBar.hidden, (c.window.styleMask & NSWindowStyleMaskFullScreen) != 0, c.window.alphaValue, (long)c.window.level,
                    (c.window.styleMask & NSWindowStyleMaskTitled) != 0 ? @"y" : @"n"];
    NSMutableDictionary *prefs = [[[NSUserDefaults standardUserDefaults] persistentDomainForName:NSBundle.mainBundle.bundleIdentifier] mutableCopy] ?: [NSMutableDictionary dictionary];
    for (NSString *k in prefs.allKeys) if ([k hasPrefix:@"NSWindow"] || [k hasPrefix:@"NSSplitView"] || [k hasPrefix:@"dock."] || [k isEqualToString:@"RecentFiles"]) [prefs removeObjectForKey:k];
    s[@"preferences"] = @(prefs.description.hash);
    s[@"clipboard"] = @([NSPasteboard generalPasteboard].changeCount);
    NSMutableString *status = [NSMutableString string];
    for (int i = 0; i < 6; ++i) [status appendFormat:@"%@|", [c.statusBar textForPart:i]];
    s[@"status bar"] = status;
    NSMutableString *files = [NSMutableString string];
    for (NSString *f in [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:fixtureDir error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
        NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:[fixtureDir stringByAppendingPathComponent:f] error:nil];
        [files appendFormat:@"%@:%llu:%.3f:%lo ", f, a.fileSize, a.fileModificationDate.timeIntervalSinceReferenceDate, (unsigned long)a.filePosixPermissions];
    }
    s[@"files"] = files;
    NSMutableArray *checked = [NSMutableArray array];
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    for (NSNumber *n in reg.allMenuCommands) if ([reg isChecked:n.intValue]) [checked addObject:n];
    s[@"checked commands"] = [checked componentsJoinedByString:@","];
    return s;
}

static sptr_t findText(ScintillaView *ed, const char *what) {
    std::string t = sciGetText(ed);
    size_t p = t.find(what);
    return p == std::string::npos ? 0 : static_cast<sptr_t>(p);
}

static const char *kFixture =
    "// audit fixture\n"
    "#include <stdio.h>\n"
    "int main(int argc, char **argv) {\n"
    "    int value = 42;   // TODO check\n"
    "    printf(\"hello world %d\\n\", value);\n"
    "\tif (value > 1) {\n"
    "        value = value + 1;\n"
    "    }\n"
    "    return 0;\n"
    "}\n"
    "\n"
    "class Foo { public: void bar(); };\n"
    "see https://example.com/page and value again\n"
    "zeta\nalpha\nbeta\nalpha\nalpha\n"
    "  trailing spaces   \n"
    "Mixed VALUE Case\n"
    "/* block comment */\n"
    "3,5\n1,25\n2,0\n"
    "void deep() { if (1) { if (2) { if (3) { if (4) { if (5) { if (6) { if (7) {\n"
    "        x();\n"
    "    } } } } } } }\n"
    "}\n";

@implementation TPAudit

+ (int)runWithController:(TPMainWindowController *)c output:(NSString *)outPath {
    g_events = [NSMutableArray array];
    installInterceptors();
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    c.promptOverride = ^NSInteger(NSString *msg, NSArray<NSString *> *buttons) {
        note([@"prompt: " stringByAppendingString:msg ?: @""]);
        NSUInteger cancel = [buttons indexOfObject:@"Cancel"];
        return cancel != NSNotFound ? (NSInteger)cancel : (NSInteger)buttons.count - 1;   // the safest answer
    };
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"textpad-audit-%d", getpid()]];
    NSString *bid = NSBundle.mainBundle.bundleIdentifier;
    NSDictionary *savedDefaults = [[NSUserDefaults standardUserDefaults] persistentDomainForName:bid] ?: @{};
    NSString *savedClip = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
    FILE *out = fopen(outPath.fileSystemRepresentation, "w");
    c.window.alphaValue = 0;
    NSArray<NSNumber *> *cmds = reg.allMenuCommands;
    NSString *only = [NSProcessInfo processInfo].environment[@"TEXTPAD_AUDIT_ONLY"];   // "44034,44032": just these, in this order
    if (only.length) {
        NSMutableArray *sel = [NSMutableArray array];
        for (NSString *x in [only componentsSeparatedByString:@","]) [sel addObject:@(x.intValue)];
        cmds = sel;
    }
    int done = 0;
    for (NSNumber *n in cmds) {
        const int cmd = n.intValue;
        @autoreleasepool {
            // ---- reset
            for (NSWindow *w in [NSApp.windows copy]) if (w.isVisible && w != c.window) [w orderOut:nil];
            if (c.window.styleMask & NSWindowStyleMaskFullScreen) [c.window toggleFullScreen:nil];
            [c closeAll_forTests];
            [[NSUserDefaults standardUserDefaults] setPersistentDomain:savedDefaults forName:bid];
            for (NSString *pid in [c.docks.visiblePanelIdentifiers copy]) [c.docks hidePanel:pid];
            [c applyAllPreferences];
            [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *file = [dir stringByAppendingPathComponent:@"audit.cpp"];
            [[NSData dataWithBytes:kFixture length:strlen(kFixture)] writeToFile:file atomically:NO];
            [c openFile:file];
            ScintillaView *ed = c.editor;
            // a richer starting point: three tabs (+ a clone in the second view), undo and redo history, bookmarks,
            // styled tokens, change history, a tab colour
            NSString *fileB = [dir stringByAppendingPathComponent:@"notes.txt"], *fileC = [dir stringByAppendingPathComponent:@"script.py"];
            [@"note one\nnote two\n" writeToFile:fileB atomically:NO encoding:NSUTF8StringEncoding error:nil];
            [@"def f():\n    return 1\n" writeToFile:fileC atomically:NO encoding:NSUTF8StringEncoding error:nil];
            [c openFile:fileB];
            [c openFile:fileC];
            TPDocument *docA = [c documentForPath:file];
            [c activateDocument:docA inPane:c.mainPane];
            [reg execute:IDM_VIEW_CLONE_TO_ANOTHER_VIEW];
            [c activateDocument:docA inPane:c.mainPane];
            ed = c.editor;
            SCI(ed, SCI_DOCUMENTEND);
            SCI(ed, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>("// edit one\n"));
            SCI(ed, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>("// edit two\n"));
            SCI(ed, SCI_UNDO);
            for (sptr_t line : {1, 4}) { SCI(ed, SCI_GOTOLINE, line); [reg execute:IDM_SEARCH_TOGGLE_BOOKMARK]; }
            const sptr_t hello = findText(ed, "hello");
            for (int k = 0; k < 5; ++k) { SCI(ed, SCI_SETSEL, hello, hello + 5); [reg execute:IDM_SEARCH_MARKALLEXT1 + 2 * k]; }
            const sptr_t value = findText(ed, "value");
            SCI(ed, SCI_SETSEL, value, value + 5);                          // "value" on line 4
            NSString *nm = [reg idNameForCommand:cmd];
            // commands that need a particular starting point
            if ([nm hasPrefix:@"IDM_VIEW_UNFOLD"]) [reg execute:IDM_VIEW_FOLDALL];
            if ([nm isEqualToString:@"IDM_EDIT_BLOCK_UNCOMMENT"]) SCI(ed, SCI_SETSEL, 0, 0);
            if ([nm isEqualToString:@"IDM_EDIT_STREAM_UNCOMMENT"]) { sptr_t b = findText(ed, "/* block"); SCI(ed, SCI_SETSEL, b + 3, b + 3); }
            if ([nm containsString:@"SORTLINES_DECIMAL"]) { sptr_t b = findText(ed, "3,5"); SCI(ed, SCI_SETSEL, b, findText(ed, "2,0") + 3); }
            if ([nm containsString:@"DUP_LINES"]) { sptr_t b = findText(ed, "zeta"); SCI(ed, SCI_SETSEL, b, findText(ed, "  trailing")); }
            if ([nm isEqualToString:@"IDM_EDIT_LOWERCASE"]) { sptr_t b = findText(ed, "VALUE"); SCI(ed, SCI_SETSEL, b, b + 5); }
            if ([nm isEqualToString:@"IDM_SEARCH_GOTOMATCHINGBRACE"]) { sptr_t b = findText(ed, "{\n"); SCI(ed, SCI_SETSEL, b, b); }
            if ([nm isEqualToString:@"IDM_VIEW_ZOOMRESTORE"]) SCI(ed, SCI_SETZOOM, 3);
            if ([nm isEqualToString:@"IDM_VIEW_TAB_COLOUR_NONE"]) [reg execute:IDM_VIEW_TAB_COLOUR_1];
            if ([nm isEqualToString:@"IDM_EDIT_CLEARREADONLYFORALLDOCS"]) [reg execute:IDM_EDIT_TOGGLEREADONLY];
            if ([nm hasPrefix:@"IDM_FORMAT_AS_UTF_8"] || [nm hasPrefix:@"IDM_FORMAT_CONV2_AS_UTF_8"]) { [reg execute:IDM_FORMAT_ANSI]; }
            if ([nm isEqualToString:@"IDM_FORMAT_TOUNIX"]) [reg execute:IDM_FORMAT_TODOS];
            if ([nm isEqualToString:@"IDM_MACRO_STOPRECORDINGMACRO"]) [reg execute:IDM_MACRO_STARTRECORDINGMACRO];
            if ([nm hasPrefix:@"IDM_EDIT_AUTOCOMPLETE"] || [nm hasPrefix:@"IDM_EDIT_FUNCCALLTIP"]) {
                sptr_t b = findText(ed, "printf(");
                SCI(ed, SCI_SETSEL, b + ([nm hasPrefix:@"IDM_EDIT_FUNCCALLTIP"] ? 7 : 3), b + ([nm hasPrefix:@"IDM_EDIT_FUNCCALLTIP"] ? 7 : 3));
                if ([nm isEqualToString:@"IDM_EDIT_AUTOCOMPLETE_PATH"]) { SCI(ed, SCI_DOCUMENTEND); SCI(ed, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>("/usr/")); }
            }
            [[NSPasteboard generalPasteboard] clearContents];
            [[NSPasteboard generalPasteboard] setString:@"pasted text" forType:NSPasteboardTypeString];
            [c refreshUI];
            const BOOL enabled = [reg isEnabled:cmd];
            NSDictionary *before = snapshot(c, dir);
            [g_events removeAllObjects];
            fprintf(stderr, "AUDIT %d %s\n", cmd, [reg idNameForCommand:cmd].UTF8String);
            fflush(stderr);
            NSString *error = nil;
            BOOL ran = NO;
            @try { ran = [reg execute:cmd]; } @catch (NSException *e) { error = e.reason; }
            NSDictionary *after = snapshot(c, dir);
            for (NSWindow *w in NSApp.windows) if (w.isVisible && w != c.window) checkSize(w.title.length ? w.title : NSStringFromClass(w.class), w);
            NSMutableArray *changed = [NSMutableArray array];
            for (NSString *k in before) if (![before[k] isEqual:after[k]]) [changed addObject:k];
            NSDictionary *row = @{@"id": n, @"name": [reg idNameForCommand:cmd], @"label": [[reg menuPathForCommand:cmd] componentsJoinedByString:@" > "] ?: @"",
                                  @"enabled": @(enabled), @"ran": @(ran), @"changed": changed, @"events": [g_events copy], @"error": error ?: @"",
                                  @"windows": after[@"windows"]};
            NSData *json = [NSJSONSerialization dataWithJSONObject:row options:0 error:nil];
            fwrite(json.bytes, 1, json.length, out);
            fputc('\n', out);
            fflush(out);
            ++done;
        }
    }
    fclose(out);
    [[NSUserDefaults standardUserDefaults] setPersistentDomain:savedDefaults forName:bid];
    [[NSPasteboard generalPasteboard] clearContents];
    if (savedClip) [[NSPasteboard generalPasteboard] setString:savedClip forType:NSPasteboardTypeString];
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
    fprintf(stderr, "AUDIT done: %d commands\n", done);
    return 0;
}

@end
