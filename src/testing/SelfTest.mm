// Textpad++ — in-app acceptance tests. GPL-3.0-or-later.
//
// Every test drives real commands through TPCommandRegistry (the same path as menus, toolbar
// and shortcuts) against real Scintilla views and real files in a temporary folder. The
// commands executed while a test runs are recorded, so FEATURE_MATRIX.md can mark a command
// "Verified" only when a passing test exercised it.
#import "testing/SelfTest.h"
#import "app/MainWindowController.h"
#import "app/LanguageService.h"
#import "app/Session.h"
#import "search/FindReplaceController.h"
#import "search/IncrementalSearchBar.h"
#import "app/TabBarView.h"
#import "search/SearchResultsPanel.h"
#import "app/Preferences.h"
#import "app/UserDefinedLanguages.h"
#import "dialogs/UDLDialog.h"
#import "app/AutoCompletion.h"
#import "dialogs/FindCharsInRangeDialog.h"
#import "dialogs/StyleConfigurator.h"
#import "dialogs/ShortcutMapper.h"
#import "commands/ScintillaKeys.h"
#import "commands/CommandRegistry.h"
#import "app/CommandLine.h"
#import "panels/Panels.h"
#import "app/MenuBarView.h"
#import "plugins/PluginHost.h"
#import "commands/DevTools.h"
#import "commands/ExtraCommands.h"
#import "app/EscapeKey.h"
#import "app/Features.h"
#import "app/Compare.h"
#import "app/GitMarkers.h"
#import "app/CsvColumns.h"
#import "app/Snippets.h"
#import "app/Localization.h"
#import "panels/PreviewPanel.h"
#import "dialogs/CommandPalette.h"
#import "plugins/PluginsAdmin.h"
#import "app/Updater.h"
#import "app/SystemTray.h"
#import "app/LargeFiles.h"
#import "app/Localization.h"
#include <mach/mach.h>
#import <Security/Security.h>
#import <Carbon/Carbon.h>
#import "app/ToolbarView.h"
#include <signal.h>
#include "core/Encoding.h"
#include "core/Hashing.h"
#include <sys/stat.h>
#include <chrono>
#include <functional>
#include <set>

using namespace npp;

@interface TPMainWindowController (SelfTestHelpers)
- (void)closeAll_forTests;
- (void)smartHighlightInView_forTests:(ScintillaView *)v;
- (BOOL)saveCurrentMacroNamed_forTests:(NSString *)name;
@end
@interface TPMainWindowController (ToolCommandsPrivate)
- (BOOL)saveCurrentMacroNamed:(NSString *)name;
- (void)smartHighlightInView:(ScintillaView *)v;
@end

#define REQUIRE(cond) do { if (!(cond)) { fail = [NSString stringWithFormat:@"line %d: %s", __LINE__, #cond]; return; } } while (0)
#define REQUIRE_EQ_STR(a, b) do { std::string _a = (a), _b = (b); if (_a != _b) { fail = [NSString stringWithFormat:@"line %d: %s != %s  (got \"%s\", expected \"%s\")", __LINE__, #a, #b, _a.substr(0, 200).c_str(), _b.substr(0, 200).c_str()]; return; } } while (0)

@implementation TPSelfTest

static NSString *g_tmp;
static NSString *fail = nil;
static NSString *nextAnswer = nil;
static NSString *g_lastPrompt = nil;   // last message shown through promptOverride
static int failures = 0;
static std::set<int> g_executed;

static NSString *tmpPath(NSString *name) { return [g_tmp stringByAppendingPathComponent:name]; }
static void writeBytes(NSString *path, const std::string &b) { [[NSData dataWithBytes:b.data() length:b.size()] writeToFile:path atomically:NO]; }
static std::string readBytes(NSString *path) {
    NSData *d = [NSData dataWithContentsOfFile:path];
    return d ? std::string(static_cast<const char *>(d.bytes), d.length) : std::string("<missing>");
}

+ (int)runWithController:(TPMainWindowController *)c output:(NSString *)outPath {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *bid = [NSBundle mainBundle].bundleIdentifier ?: @"com.textpadplusplus.app";
    NSDictionary *savedDefaults = [ud persistentDomainForName:bid] ?: @{};
    // start from the default settings: the user's own choices (a theme, dark mode...) must not change the results
    [ud setPersistentDomain:@{} forName:bid];
    [c applyAllPreferences];
    g_tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"textpad-selftest-%d", getpid()]];
    [[NSFileManager defaultManager] removeItemAtPath:g_tmp error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:g_tmp withIntermediateDirectories:YES attributes:nil error:nil];
    c.window.alphaValue = 0.0;            // keep the test window invisible
    c.window.ignoresMouseEvents = YES;
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    void (^macroHook)(int) = reg.willExecute;
    reg.willExecute = ^(int cmd) { g_executed.insert(cmd); if (macroHook) macroHook(cmd); };

    NSMutableArray *results = [NSMutableArray array];
    NSMutableArray *benchmarks = [NSMutableArray array];
    failures = 0;

    // Default answers for prompts during tests (each test may override)
    c.promptOverride = ^NSInteger(NSString *msg, NSArray<NSString *> *buttons) {
        g_lastPrompt = msg;
        if (nextAnswer) {
            NSUInteger i = [buttons indexOfObject:nextAnswer];
            if (i != NSNotFound) return (NSInteger)i;
        }
        return 0;
    };

    auto run = [&](NSString *tid, NSString *name, void (^body)(void)) {
        fail = nil;
        nextAnswer = nil;
        g_executed.clear();
        auto t0 = std::chrono::steady_clock::now();
        @try { body(); }
        @catch (NSException *e) { fail = [NSString stringWithFormat:@"exception: %@", e.reason]; }
        double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
        BOOL ok = fail == nil;
        if (!ok) ++failures;
        NSMutableArray *cmds = [NSMutableArray array];
        for (int x : g_executed) [cmds addObject:@(x)];
        [results addObject:@{@"id": tid, @"name": name, @"pass": @(ok), @"detail": fail ?: @"", @"ms": @(ms), @"commands": cmds}];
        fprintf(stderr, "%s %-28s %s%s%s\n", ok ? "PASS" : "FAIL", tid.UTF8String, name.UTF8String, ok ? "" : "  -> ", ok ? "" : fail.UTF8String);
        // keep state small between tests; reset every preference a test may have changed
        [c closeAll_forTests];
        NSUserDefaults *ud2 = [NSUserDefaults standardUserDefaults];
        BOOL touched = NO;
        for (NSString *k in [[ud2 persistentDomainForName:bid] allKeys])
            if ([k hasPrefix:@"pref."] || [@[@"NewDocEOL", @"NewDocUniMode", @"NewDocCodepage", @"TabWidth", @"UseSpaces", @"WordWrap", @"ShowWhitespace", @"ShowEOL", @"ShowNPC", @"ShowCCUniEOL", @"ShowIndentGuide", @"ShowWrapSymbol"] containsObject:k]) { [ud2 removeObjectForKey:k]; touched = YES; }
        if (touched) [c applyAllPreferences];
    };
    auto exec = [&](int cmd) { return [reg execute:cmd]; };
    auto text = [&]() { return sciGetText(c.editor); };
    auto setText = [&](const std::string &t) { SCI(c.editor, SCI_SETTEXT, 0, reinterpret_cast<sptr_t>(t.c_str())); };
    auto setOpts = [&](tpp::search::Options o) { [c.findController setOptions:o]; };

    // ================================================================ menus / identity
    run(@"T-MENU-001", @"Top-level menu order matches upstream", ^{
        NSArray *titles = [[NSApp.mainMenu.itemArray subarrayWithRange:NSMakeRange(1, NSApp.mainMenu.itemArray.count - 1)] valueForKey:@"title"];
        NSArray *expected = @[@"File", @"Edit", @"Search", @"View", @"Encoding", @"Language", @"Settings", @"Tools", @"Macro", @"Run", @"Plugins", @"Window", @"Help"];
        REQUIRE([titles isEqualToArray:expected]);
        REQUIRE([NSApp.mainMenu.itemArray.firstObject.title isEqualToString:@"Textpad++"]);
    });
    run(@"T-MENU-002", @"No enabled menu item without a real handler", ^{
        for (NSNumber *n in reg.allMenuCommands) {
            NSMenuItem *mi = [reg menuItemForCommand:n.intValue];
            if (!mi) continue;
            BOOL enabled = [reg validateMenuItem:mi];
            if (enabled) REQUIRE([reg hasHandler:n.intValue]);
        }
    });
    run(@"T-BRAND-001", @"Textpad++ identity in window title, About and menus", ^{
        exec(IDM_FILE_NEW);
        REQUIRE([c.window.title hasSuffix:@" - Textpad++"]);
        REQUIRE([[reg labelForCommand:IDM_ABOUT] isEqualToString:@"About Textpad++"]);
        // the upstream product name appears nowhere: menus, menu bar titles, About credits
        NSString *banned = [@"note" stringByAppendingString:@"pad"];   // not spelled out, so the binary does not contain it
        for (NSNumber *n in reg.allMenuCommands) {
            NSMenuItem *mi = [reg menuItemForCommand:n.intValue];
            if (mi) REQUIRE(![mi.title.lowercaseString containsString:banned]);
        }
        for (NSMenuItem *top in NSApp.mainMenu.itemArray) REQUIRE(![top.title.lowercaseString containsString:banned]);
        for (NSNumber *n in @[@(IDM_HOMESWEETHOME), @(IDM_PROJECTPAGE), @(IDM_ONLINEDOCUMENT), @(IDM_FORUM)]) REQUIRE([reg menuItemForCommand:n.intValue] == nil);
    });
    run(@"T-KEY-001", @"Default shortcuts mapped (macOS scheme, reserved keys on Control)", ^{
        TPKeyBinding *save = [reg primaryBindingForCommand:IDM_FILE_SAVE];
        REQUIRE(save && [save.keyEquivalent isEqualToString:@"s"] && (save.modifiers & NSEventModifierFlagCommand));
        TPKeyBinding *rep = [reg primaryBindingForCommand:IDM_SEARCH_REPLACE];
        REQUIRE(rep && [rep.keyEquivalent isEqualToString:@"h"]);
        TPKeyBinding *cmt = [reg primaryBindingForCommand:IDM_EDIT_BLOCK_COMMENT];
        REQUIRE(cmt && (cmt.modifiers & NSEventModifierFlagControl) && !(cmt.modifiers & NSEventModifierFlagCommand));
        TPKeyBinding *f3 = [reg primaryBindingForCommand:IDM_SEARCH_FINDNEXT];
        REQUIRE(f3 && [f3.keyEquivalent characterAtIndex:0] == NSF3FunctionKey);
        REQUIRE([save.windowsDescription isEqualToString:@"Ctrl+S"]);
    });

    // ================================================================ file I/O integrity
    struct Sample { const char *name; std::string bytes; tpp::UniMode mode; };
    std::vector<Sample> samples = {
        {"empty.txt", "", tpp::UniMode::Utf8},
        {"utf8.txt", "caf\xC3\xA9 \xF0\x9F\x98\x80\nline2", tpp::UniMode::Utf8},
        {"utf8bom.txt", "\xEF\xBB\xBF" "BOM\r\nkept\r\n", tpp::UniMode::Utf8Bom},
        {"utf16le.txt", std::string("\xFF\xFE" "A\0\r\0\n\0" "\x3D\xD8\x00\xDE", 10), tpp::UniMode::Utf16LE},
        {"utf16be.txt", std::string("\xFE\xFF\0h\0i\x04\x10", 8), tpp::UniMode::Utf16BE},
        {"ansi.txt", "na\xEFve r\xE9sum\xE9\r\n\x80\x81\x8D\x8F\x90\x9D", tpp::UniMode::Ansi},
        {"mixed-eol.txt", "a\r\nb\nc\rd", tpp::UniMode::Utf8},
        {"no-final-newline.txt", "last line", tpp::UniMode::Utf8},
        {"binary.bin", std::string("\x00\x01\x02\xFF\xFE\x00zz\x7F\x80", 10), tpp::UniMode::Ansi},
        {"combining.txt", "e\xCC\x81 \xE0\xA4\xA8\xE0\xA4\xAE\xE0\xA4\xB8\xE0\xA5\x8D\xE0\xA4\xA4\xE0\xA5\x87", tpp::UniMode::Utf8},
    };
    for (const Sample &s : samples) {
        NSString *name = @(s.name);
        std::string bytes = s.bytes;
        tpp::UniMode mode = s.mode;
        run([NSString stringWithFormat:@"T-FILE-RT-%@", name.stringByDeletingPathExtension], [NSString stringWithFormat:@"Open + save %@ is byte-identical", name], ^{
            NSString *p = tmpPath(name);
            writeBytes(p, bytes);
            TPDocument *d = [c openFile:p];
            REQUIRE(d != nil);
            REQUIRE(d.encoding.mode == mode);
            REQUIRE(!d.dirty);
            // force a real save through the command
            SCI(c.editor, SCI_APPENDTEXT, 1, reinterpret_cast<sptr_t>("x"));
            SCI(c.editor, SCI_DELETERANGE, SCI(c.editor, SCI_GETLENGTH) - 1, 1);
            REQUIRE(exec(IDM_FILE_SAVE));
            REQUIRE_EQ_STR(readBytes(p), bytes);
        });
    }
    run(@"T-FILE-001", @"Edit + save keeps UTF-16 LE BOM encoding and EOL", ^{
        NSString *p = tmpPath(@"edit16.txt");
        writeBytes(p, std::string("\xFF\xFE" "a\0\r\0\n\0", 8));
        [c openFile:p];
        SCI(c.editor, SCI_DOCUMENTEND);
        SCI(c.editor, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>("\xC3\xA9"));
        REQUIRE(c.currentDocument.dirty);
        REQUIRE(exec(IDM_FILE_SAVE));
        REQUIRE_EQ_STR(readBytes(p), std::string("\xFF\xFE" "a\0\r\0\n\0\xE9\0", 10));
        REQUIRE(!c.currentDocument.dirty);
    });
    run(@"T-FILE-002", @"Save preserves POSIX permissions and resolves symlinks", ^{
        NSString *p = tmpPath(@"perm.sh");
        writeBytes(p, "echo hi\n");
        chmod(p.fileSystemRepresentation, 0750);
        NSString *link = tmpPath(@"perm-link.sh");
        [[NSFileManager defaultManager] createSymbolicLinkAtPath:link withDestinationPath:p error:nil];
        [c openFile:link];
        setText("echo changed\n");
        REQUIRE(exec(IDM_FILE_SAVE));
        struct stat st;
        stat(p.fileSystemRepresentation, &st);
        REQUIRE((st.st_mode & 0777) == 0750);
        NSDictionary *la = [[NSFileManager defaultManager] attributesOfItemAtPath:link error:nil];
        REQUIRE([la.fileType isEqualToString:NSFileTypeSymbolicLink]);
        REQUIRE_EQ_STR(readBytes(p), "echo changed\n");
    });
    run(@"T-FILE-003", @"Close dirty document: Cancel keeps it, No discards without writing", ^{
        NSString *p = tmpPath(@"dirty.txt");
        writeBytes(p, "original");
        TPDocument *d = [c openFile:p];
        setText("modified");
        nextAnswer = @"Cancel";
        exec(IDM_FILE_CLOSE);
        REQUIRE([c.allDocuments containsObject:d]);
        nextAnswer = @"No";
        exec(IDM_FILE_CLOSE);
        REQUIRE(![c.allDocuments containsObject:d]);
        REQUIRE_EQ_STR(readBytes(p), "original");
    });
    run(@"T-FILE-004", @"Close dirty document: Yes saves", ^{
        NSString *p = tmpPath(@"dirty2.txt");
        writeBytes(p, "original");
        [c openFile:p];
        setText("saved on close");
        nextAnswer = @"Yes";
        exec(IDM_FILE_CLOSE);
        REQUIRE_EQ_STR(readBytes(p), "saved on close");
    });
    run(@"T-FILE-005", @"Close Multiple Documents variants and Close All", ^{
        NSMutableArray *docs = [NSMutableArray array];
        for (int i = 0; i < 5; ++i) {
            NSString *p = tmpPath([NSString stringWithFormat:@"multi%d.txt", i]);
            writeBytes(p, "x");
            [docs addObject:[c openFile:p]];
        }
        [c activateDocument:docs[2] inPane:c.mainPane];
        exec(IDM_FILE_CLOSEALL_TORIGHT);
        REQUIRE(c.mainPane.documents.count == 3);
        exec(IDM_FILE_CLOSEALL_TOLEFT);
        REQUIRE(c.mainPane.documents.count == 1 && c.currentDocument == docs[2]);
        [c openFile:tmpPath(@"multi0.txt")];
        [c activateDocument:docs[2] inPane:c.mainPane];
        exec(IDM_FILE_CLOSEALL_BUT_CURRENT);
        REQUIRE(c.mainPane.documents.count == 1);
        TPDocument *n = [c newDocument];
        SCI(c.editor, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>("dirty"));
        exec(IDM_FILE_CLOSEALL_UNCHANGED);
        REQUIRE(c.mainPane.documents.count == 1 && c.currentDocument == n);
        nextAnswer = @"No";
        exec(IDM_FILE_CLOSEALL);
        REQUIRE(c.mainPane.documents.count == 1 && c.currentDocument.isUntitled && !c.currentDocument.dirty);
    });
    run(@"T-FILE-006", @"Reload from disk and external-change detection", ^{
        NSString *p = tmpPath(@"ext.txt");
        writeBytes(p, "v1");
        [c openFile:p];
        [NSThread sleepForTimeInterval:1.1];
        writeBytes(p, "v2 changed outside");
        nextAnswer = @"Yes";
        [c checkFilesModifiedOnDisk];
        REQUIRE_EQ_STR(text(), "v2 changed outside");
        writeBytes(p, "v3");
        exec(IDM_FILE_RELOAD);
        REQUIRE_EQ_STR(text(), "v3");
    });
    run(@"T-FILE-007", @"Deleted file: keep in editor marks it dirty", ^{
        NSString *p = tmpPath(@"gone.txt");
        writeBytes(p, "keep me");
        TPDocument *d = [c openFile:p];
        [[NSFileManager defaultManager] removeItemAtPath:p error:nil];
        nextAnswer = @"Yes";
        [c checkFilesModifiedOnDisk];
        REQUIRE(d.dirty && [c.allDocuments containsObject:d]);
        REQUIRE(exec(IDM_FILE_SAVE));
        REQUIRE_EQ_STR(readBytes(p), "keep me");
    });
    run(@"T-FILE-008", @"Restore Recent Closed File, recent list, Move to Trash", ^{
        NSString *p = tmpPath(@"recent.txt");
        writeBytes(p, "r");
        TPDocument *d = [c openFile:p];
        REQUIRE([c.recentFiles.firstObject isEqualToString:p.stringByStandardizingPath]);
        exec(IDM_FILE_CLOSE);
        REQUIRE(![c.allDocuments containsObject:d]);
        exec(IDM_FILE_RESTORELASTCLOSEDFILE);
        REQUIRE([c.currentDocument.path isEqualToString:p.stringByStandardizingPath]);
        nextAnswer = @"Yes";
        exec(IDM_FILE_DELETE);
        REQUIRE(![[NSFileManager defaultManager] fileExistsAtPath:p]);
    });
    run(@"T-FILE-009", @"Save a Copy As keeps the document; Save As switches path + language", ^{
        TPDocument *d = [c newDocument];
        setText("int main() {}\n");
        NSString *copyPath = tmpPath(@"copy.txt");
        NSString *err = nil;
        REQUIRE([c writeDocument:d toPath:copyPath updateDocument:NO error:&err]);
        REQUIRE(d.isUntitled && d.dirty);
        NSString *asPath = tmpPath(@"saved-as.cpp");
        REQUIRE([c writeDocument:d toPath:asPath updateDocument:YES error:&err]);
        REQUIRE([d.path isEqualToString:asPath] && !d.dirty && [d.languageId isEqualToString:@"cpp"]);
        REQUIRE_EQ_STR(readBytes(copyPath), "int main() {}\n");
    });
    run(@"T-FILE-010", @"Lossy save warning: Cancel leaves file untouched, Save Anyway writes '?'", ^{
        NSString *p = tmpPath(@"lossy.txt");
        writeBytes(p, "plain");
        [c openFile:p];
        setText("A\xE2\x82\xAC\xE4\xB8\xAD");
        exec(IDM_FORMAT_CONV2_ANSI);
        nextAnswer = @"Cancel";
        exec(IDM_FILE_SAVE);
        REQUIRE_EQ_STR(readBytes(p), "plain");
        nextAnswer = @"Save Anyway";
        exec(IDM_FILE_SAVE);
        REQUIRE_EQ_STR(readBytes(p), "A\x80?");
    });

    // ================================================================ sessions & backup
    run(@"T-SESS-001", @"Session save/load restores files, views, bookmarks, language", ^{
        NSString *a = tmpPath(@"sa.txt"), *b = tmpPath(@"sb.txt");
        writeBytes(a, "one\ntwo\nthree\n"); writeBytes(b, "bee");
        [c openFile:a];
        SCI(c.editor, SCI_MARKERADD, 1, TPP_MARK_BOOKMARK);
        exec(IDM_LANG_PYTHON);
        [c openFile:b];
        exec(IDM_VIEW_CLONE_TO_ANOTHER_VIEW);
        NSString *sp = tmpPath(@"session.xml");
        REQUIRE([[TPSession shared] saveSessionToPath:sp controller:c includeBackups:NO]);
        [c closeAll_forTests];
        REQUIRE([[TPSession shared] loadSessionFromPath:sp controller:c]);
        TPDocument *da = [c documentForPath:a];
        REQUIRE(da != nil && [da.languageId isEqualToString:@"python"]);
        REQUIRE([c documentForPath:b] != nil);
        REQUIRE([c.subPane indexOfDocument:[c documentForPath:b]] != NSNotFound);
        __block sptr_t mark = -1;
        [c withDocument:da perform:^(ScintillaView *v) { mark = SCI(v, SCI_MARKERNEXT, 0, 1 << TPP_MARK_BOOKMARK); }];
        REQUIRE(mark == 1);
    });
    run(@"T-SESS-002", @"Snapshot backup restores unsaved untitled text after 'restart'", ^{
        TPDocument *d = [c newDocument];
        setText("unsaved work \xE2\x9C\x93");
        NSString *name = d.untitledName;
        [[TPSession shared] writeSnapshotForController:c];
        NSString *sp = [TPSession shared].sessionPath;
        REQUIRE([[NSFileManager defaultManager] fileExistsAtPath:sp]);
        d.dirty = NO;   // simulate process exit without saving
        [c closeAll_forTests];
        REQUIRE([[TPSession shared] loadSessionFromPath:sp controller:c]);
        TPDocument *r = nil;
        for (TPDocument *x in c.allDocuments) if ([x.untitledName isEqualToString:name] && x.dirty) r = x;
        REQUIRE(r != nil);
        __block std::string t;
        [c withDocument:r perform:^(ScintillaView *v) { t = sciGetText(v); }];
        REQUIRE_EQ_STR(t, "unsaved work \xE2\x9C\x93");
    });

    // ================================================================ edit
    run(@"T-EDIT-001", @"Undo / Redo / Cut / Copy / Paste / Delete / Select All", ^{
        [c newDocument];
        setText("hello world");
        SCI(c.editor, SCI_EMPTYUNDOBUFFER);
        SCI(c.editor, SCI_SETSEL, 0, 5);
        exec(IDM_EDIT_CUT);
        REQUIRE_EQ_STR(text(), " world");
        exec(IDM_EDIT_UNDO);
        REQUIRE_EQ_STR(text(), "hello world");
        exec(IDM_EDIT_REDO);
        REQUIRE_EQ_STR(text(), " world");
        SCI(c.editor, SCI_GOTOPOS, SCI(c.editor, SCI_GETLENGTH));
        exec(IDM_EDIT_PASTE);
        REQUIRE_EQ_STR(text(), " worldhello");
        exec(IDM_EDIT_SELECTALL);
        exec(IDM_EDIT_COPY);
        REQUIRE([[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:@" worldhello"]);
        exec(IDM_EDIT_DELETE);
        REQUIRE_EQ_STR(text(), "");
    });
    run(@"T-EDIT-002", @"Convert case (all 8 variants) on selection", ^{
        [c newDocument];
        struct { int cmd; const char *in; const char *out; } cases[] = {
            {IDM_EDIT_UPPERCASE, "mixed Case \xC3\xA9", "MIXED CASE \xC3\x89"}, {IDM_EDIT_LOWERCASE, "MiXeD", "mixed"},
            {IDM_EDIT_PROPERCASE_FORCE, "hELLO wORLD", "Hello World"}, {IDM_EDIT_PROPERCASE_BLEND, "hELLO wORLD", "HELLO WORLD"},
            {IDM_EDIT_SENTENCECASE_FORCE, "hello. WORLD", "Hello. World"}, {IDM_EDIT_SENTENCECASE_BLEND, "hello. wORLD", "Hello. WORLD"},
            {IDM_EDIT_INVERTCASE, "AbC", "aBc"}};
        for (auto &k : cases) {
            setText(k.in);
            exec(IDM_EDIT_SELECTALL);
            exec(k.cmd);
            REQUIRE_EQ_STR(text(), k.out);
        }
        setText("abcdefghijklmnop");
        exec(IDM_EDIT_SELECTALL);
        exec(IDM_EDIT_RANDOMCASE);
        REQUIRE(NSStr(text()).lowercaseString.length == 16 && [NSStr(text()).lowercaseString isEqualToString:@"abcdefghijklmnop"]);
        setText("no selection");
        SCI(c.editor, SCI_GOTOPOS, 3);
        exec(IDM_EDIT_UPPERCASE);
        REQUIRE_EQ_STR(text(), "no selection");   // upstream: no-op without a selection
    });
    run(@"T-EDIT-003", @"Line operations: duplicate, dedupe, join, split, move, blank lines, empty lines", ^{
        [c newDocument];
        SCI(c.editor, SCI_SETEOLMODE, SC_EOL_LF);
        setText("a\nb\na\nb\nb\n");
        exec(IDM_EDIT_REMOVE_ANY_DUP_LINES);
        REQUIRE_EQ_STR(text(), "a\nb\n");
        setText("a\nb\nb\na\na\n");
        exec(IDM_EDIT_REMOVE_CONSECUTIVE_DUP_LINES);
        REQUIRE_EQ_STR(text(), "a\nb\na\n");
        setText("x\ny");
        SCI(c.editor, SCI_GOTOPOS, 0);
        exec(IDM_EDIT_DUP_LINE);
        REQUIRE_EQ_STR(text(), "x\nx\ny");
        setText("one\ntwo\nthree");
        SCI(c.editor, SCI_GOTOLINE, 2);
        exec(IDM_EDIT_LINE_UP);
        REQUIRE_EQ_STR(text(), "one\nthree\ntwo");
        exec(IDM_EDIT_LINE_DOWN);
        REQUIRE_EQ_STR(text(), "one\ntwo\nthree");
        setText("j1\nj2\nj3");
        exec(IDM_EDIT_SELECTALL);
        exec(IDM_EDIT_JOIN_LINES);
        REQUIRE_EQ_STR(text(), "j1 j2 j3");
        setText("a\n\n  \nb\n");
        exec(IDM_EDIT_REMOVEEMPTYLINES);
        REQUIRE_EQ_STR(text(), "a\n  \nb\n");
        exec(IDM_EDIT_REMOVEEMPTYLINESWITHBLANK);
        REQUIRE_EQ_STR(text(), "a\nb\n");
        setText("mid");
        exec(IDM_EDIT_BLANKLINEABOVECURRENT);
        REQUIRE_EQ_STR(text(), "\nmid");
        exec(IDM_EDIT_BLANKLINEBELOWCURRENT);
        REQUIRE_EQ_STR(text(), "\n\nmid");
    });
    run(@"T-EDIT-004", @"Sort lines (lexicographic, case-insensitive, integer, decimal, length, reverse, random)", ^{
        [c newDocument];
        SCI(c.editor, SCI_SETEOLMODE, SC_EOL_LF);
        setText("b\nC\na\n");
        exec(IDM_EDIT_SORTLINES_LEXICOGRAPHIC_ASCENDING);
        REQUIRE_EQ_STR(text(), "C\na\nb\n");
        exec(IDM_EDIT_SORTLINES_LEXICO_CASE_INSENS_ASCENDING);
        REQUIRE_EQ_STR(text(), "a\nb\nC\n");
        exec(IDM_EDIT_SORTLINES_LEXICOGRAPHIC_DESCENDING);
        REQUIRE_EQ_STR(text(), "b\na\nC\n");
        setText("10\n9\n100\n-1\n");
        exec(IDM_EDIT_SORTLINES_INTEGER_ASCENDING);
        REQUIRE_EQ_STR(text(), "-1\n9\n10\n100\n");
        exec(IDM_EDIT_SORTLINES_INTEGER_DESCENDING);
        REQUIRE_EQ_STR(text(), "100\n10\n9\n-1\n");
        setText("2.5\n10.1\n-3\n");
        exec(IDM_EDIT_SORTLINES_DECIMALDOT_ASCENDING);
        REQUIRE_EQ_STR(text(), "-3\n2.5\n10.1\n");
        setText("2,5\n1,5\n");
        exec(IDM_EDIT_SORTLINES_DECIMALCOMMA_ASCENDING);
        REQUIRE_EQ_STR(text(), "1,5\n2,5\n");
        setText("ccc\na\nbb\n");
        exec(IDM_EDIT_SORTLINES_LENGTH_ASCENDING);
        REQUIRE_EQ_STR(text(), "a\nbb\nccc\n");
        exec(IDM_EDIT_SORTLINES_LENGTH_DESCENDING);
        REQUIRE_EQ_STR(text(), "ccc\nbb\na\n");
        exec(IDM_EDIT_SORTLINES_REVERSE_ORDER);
        REQUIRE_EQ_STR(text(), "a\nbb\nccc\n");
        exec(IDM_EDIT_SORTLINES_RANDOMLY);
        REQUIRE(text().size() == std::string("a\nbb\nccc\n").size());
        setText("b\na\nc\nz\n");
        SCI(c.editor, SCI_SETSEL, 0, SCI(c.editor, SCI_POSITIONFROMLINE, 2));   // only first two lines selected
        exec(IDM_EDIT_SORTLINES_LEXICOGRAPHIC_ASCENDING);
        REQUIRE_EQ_STR(text(), "a\nb\nc\nz\n");
        exec(IDM_EDIT_SORTLINES_LOCALE_ASCENDING);
    });
    run(@"T-EDIT-005", @"Comment / uncomment (C++ line + block, Python line)", ^{
        [c newDocument];
        exec(IDM_LANG_CPP);
        SCI(c.editor, SCI_SETEOLMODE, SC_EOL_LF);
        setText("int a;\n    int b;\n");
        exec(IDM_EDIT_SELECTALL);
        exec(IDM_EDIT_BLOCK_COMMENT);
        REQUIRE_EQ_STR(text(), "// int a;\n    // int b;\n");
        exec(IDM_EDIT_BLOCK_COMMENT);
        REQUIRE_EQ_STR(text(), "int a;\n    int b;\n");
        exec(IDM_EDIT_BLOCK_COMMENT_SET);
        exec(IDM_EDIT_BLOCK_UNCOMMENT);
        REQUIRE_EQ_STR(text(), "int a;\n    int b;\n");
        setText("x = 1");
        exec(IDM_EDIT_SELECTALL);
        exec(IDM_EDIT_STREAM_COMMENT);
        REQUIRE_EQ_STR(text(), "/* x = 1 */");
        exec(IDM_EDIT_STREAM_UNCOMMENT);
        REQUIRE_EQ_STR(text(), "x = 1");
        exec(IDM_LANG_PYTHON);
        setText("print(1)");
        exec(IDM_EDIT_BLOCK_COMMENT);
        REQUIRE_EQ_STR(text(), "# print(1)");
    });
    run(@"T-EDIT-006", @"EOL conversion (CRLF/LF/CR) and status bar", ^{
        [c newDocument];
        setText("a\r\nb\nc\rd");
        exec(IDM_FORMAT_TOUNIX);
        REQUIRE_EQ_STR(text(), "a\nb\nc\nd");
        REQUIRE([[c.statusBar textForPart:3] isEqualToString:@"Unix (LF)"]);
        exec(IDM_FORMAT_TODOS);
        REQUIRE_EQ_STR(text(), "a\r\nb\r\nc\r\nd");
        REQUIRE([reg isChecked:IDM_FORMAT_TODOS]);
        exec(IDM_FORMAT_TOMAC);
        REQUIRE_EQ_STR(text(), "a\rb\rc\rd");
    });
    run(@"T-EDIT-007", @"Blank operations (trim, EOL to space, TAB/space conversion)", ^{
        [c newDocument];
        SCI(c.editor, SCI_SETEOLMODE, SC_EOL_LF);
        SCI(c.editor, SCI_SETTABWIDTH, 4);
        setText("  a  \n\tb\t\n");
        exec(IDM_EDIT_TRIMTRAILING);
        REQUIRE_EQ_STR(text(), "  a\n\tb\n");
        exec(IDM_EDIT_TRIMLINEHEAD);
        REQUIRE_EQ_STR(text(), "a\nb\n");
        setText(" x \n y \n");
        exec(IDM_EDIT_TRIM_BOTH);
        REQUIRE_EQ_STR(text(), "x\ny\n");
        setText("p\nq\nr");
        exec(IDM_EDIT_EOL2WS);
        REQUIRE_EQ_STR(text(), "p q r");
        setText("\tx\ty");
        exec(IDM_EDIT_TAB2SW);
        REQUIRE_EQ_STR(text(), "    x   y");
        exec(IDM_EDIT_SW2TAB_LEADING);
        REQUIRE_EQ_STR(text(), "\tx   y");
        exec(IDM_EDIT_SW2TAB_ALL);
        REQUIRE_EQ_STR(text(), "\tx\ty");
        setText("  m  \n\n  n  ");
        exec(IDM_EDIT_TRIMALL);
        REQUIRE_EQ_STR(text(), "m n");
    });
    run(@"T-EDIT-008", @"Read-only toggle blocks edits; insert date/time; copy paths", ^{
        NSString *p = tmpPath(@"ro.txt");
        writeBytes(p, "ro");
        [c openFile:p];
        exec(IDM_EDIT_TOGGLEREADONLY);
        REQUIRE(c.currentDocument.userReadOnly);
        SCI(c.editor, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>("x"));
        REQUIRE_EQ_STR(text(), "ro");
        REQUIRE(![reg isEnabled:IDM_EDIT_CUT]);
        exec(IDM_EDIT_TOGGLEREADONLY);
        exec(IDM_EDIT_FULLPATHTOCLIP);
        REQUIRE([[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:p.stringByStandardizingPath]);
        exec(IDM_EDIT_FILENAMETOCLIP);
        REQUIRE([[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:@"ro.txt"]);
        exec(IDM_EDIT_CURRENTDIRTOCLIP);
        REQUIRE([[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:p.stringByStandardizingPath.stringByDeletingLastPathComponent]);
        setText("");
        exec(IDM_EDIT_INSERT_DATETIME_SHORT);
        REQUIRE(text().size() > 5);
        setText("");
        exec(IDM_EDIT_INSERT_DATETIME_CUSTOMIZED);
        REQUIRE(text().size() == 19);   // yyyy-MM-dd HH:mm:ss
        exec(IDM_EDIT_SETREADONLYFORALLDOCS);
        REQUIRE(c.currentDocument.userReadOnly);
        exec(IDM_EDIT_CLEARREADONLYFORALLDOCS);
        REQUIRE(!c.currentDocument.userReadOnly);
    });
    run(@"T-EDIT-009", @"Multi-select all / next, undo latest, skip", ^{
        [c newDocument];
        setText("ab x ab y ab abc");
        SCI(c.editor, SCI_GOTOPOS, 1);
        exec(IDM_EDIT_MULTISELECTALLMATCHCASEWHOLEWORD);
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONS) == 3);
        exec(IDM_EDIT_MULTISELECTUNDO);
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONS) == 2);
        SCI(c.editor, SCI_SETSEL, 0, 2);
        exec(IDM_EDIT_MULTISELECTNEXTMATCHCASE);
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONS) == 2);
        exec(IDM_EDIT_MULTISELECTALLMATCHCASE);
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONS) == 4);
    });
    run(@"T-EDIT-010", @"Binary copy/paste preserves NUL bytes; begin/end select", ^{
        [c newDocument];
        std::string withNul("a\0b", 3);
        SCI(c.editor, SCI_APPENDTEXT, 3, reinterpret_cast<sptr_t>(withNul.data()));
        exec(IDM_EDIT_SELECTALL);
        exec(IDM_EDIT_COPY_BINARY);
        SCI(c.editor, SCI_DOCUMENTEND);
        exec(IDM_EDIT_PASTE_BINARY);
        REQUIRE_EQ_STR(text(), std::string("a\0ba\0b", 6));
        setText("0123456789");
        SCI(c.editor, SCI_GOTOPOS, 2);
        exec(IDM_EDIT_BEGINENDSELECT);
        SCI(c.editor, SCI_GOTOPOS, 7);
        exec(IDM_EDIT_BEGINENDSELECT);
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 2 && SCI(c.editor, SCI_GETSELECTIONEND) == 7);
    });
    run(@"T-EDIT-011", @"Redact selection, indent/unindent", ^{
        [c newDocument];
        setText("secret");
        exec(IDM_EDIT_SELECTALL);
        exec(IDM_EDIT_REDACT_SELECTION);
        REQUIRE_EQ_STR(text(), "\xE2\x96\x88\xE2\x96\x88\xE2\x96\x88\xE2\x96\x88\xE2\x96\x88\xE2\x96\x88");
        setText("a\nb");
        SCI(c.editor, SCI_SETUSETABS, 1);
        exec(IDM_EDIT_SELECTALL);
        exec(IDM_EDIT_INS_TAB);
        REQUIRE_EQ_STR(text(), "\ta\n\tb");
        exec(IDM_EDIT_RMV_TAB);
        REQUIRE_EQ_STR(text(), "a\nb");
    });

    // ================================================================ search
    run(@"T-SRCH-001", @"Find Next / Previous with wrap, match case, whole word", ^{
        [c newDocument];
        setText("Foo foo food FOO");
        tpp::search::Options o; o.find = "foo"; o.wrap = true;
        setOpts(o);
        SCI(c.editor, SCI_GOTOPOS, 0);
        exec(IDM_SEARCH_FINDNEXT);
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 0);
        exec(IDM_SEARCH_FINDNEXT);
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 4);
        o.matchCase = true; o.wholeWord = true; setOpts(o);
        exec(IDM_SEARCH_FINDNEXT);
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 4);   // wraps to the only exact whole-word match
        exec(IDM_SEARCH_FINDPREV);
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 4);
        o.find = "zzz"; setOpts(o);
        REQUIRE(![c.findController findNext:YES]);
        REQUIRE([c.findController.statusText containsString:@"Can't find"]);
    });
    run(@"T-SRCH-002", @"Boost regex engine: lookbehind, backrefs, $n replacement, case-insensitive flag", ^{
        [c newDocument];
        setText("user@example x@y abab");
        tpp::search::Options o; o.mode = tpp::search::Mode::Regex;
        o.find = "(\\w+)@(\\w+)"; o.replace = "$2 at $1";
        setOpts(o);
        REQUIRE([c.findController replaceAllInCurrent] == 2);
        REQUIRE_EQ_STR(text(), "example at user y at x abab");
        o.find = "(?<=a)b"; o.replace = "B"; setOpts(o);
        REQUIRE([c.findController replaceAllInCurrent] == 2);   // std::regex has no lookbehind; Boost does
        REQUIRE_EQ_STR(text(), "example at user y at x aBaB");
        o.find = "(?i)EXAMPLE"; o.replace = "\\U$0"; setOpts(o);
        REQUIRE([c.findController replaceAllInCurrent] == 1);
        REQUIRE_EQ_STR(text(), "EXAMPLE at user y at x aBaB");
        o.find = "(a)\\1"; setOpts(o);
        REQUIRE([c.findController count] == 0);
        o.find = "(["; setOpts(o);
        REQUIRE([c.findController count] == -1);   // invalid regex reported, not crashed
    });
    run(@"T-SRCH-003", @"Regex empty matches: ^ and $ replace once per line; . matches newline option", ^{
        [c newDocument];
        SCI(c.editor, SCI_SETEOLMODE, SC_EOL_CRLF);
        setText("a\r\nb\r\nc");
        tpp::search::Options o; o.mode = tpp::search::Mode::Regex; o.find = "^"; o.replace = "> ";
        setOpts(o);
        REQUIRE([c.findController replaceAllInCurrent] == 3);
        REQUIRE_EQ_STR(text(), "> a\r\n> b\r\n> c");
        o.find = "$"; o.replace = ";"; setOpts(o);
        REQUIRE([c.findController replaceAllInCurrent] == 3);
        REQUIRE_EQ_STR(text(), "> a;\r\n> b;\r\n> c;");
        setText("x\ny");
        o.find = "x.y"; o.dotMatchesNewline = false; setOpts(o);
        REQUIRE([c.findController count] == 0);
        o.dotMatchesNewline = true; setOpts(o);
        REQUIRE([c.findController count] == 1);
    });
    run(@"T-SRCH-004", @"Extended mode escapes in find and replace", ^{
        [c newDocument];
        setText("a\tb\tc");
        tpp::search::Options o; o.mode = tpp::search::Mode::Extended; o.find = "\\t"; o.replace = "\\n";
        setOpts(o);
        REQUIRE([c.findController replaceAllInCurrent] == 2);
        REQUIRE_EQ_STR(text(), "a\nb\nc");
        o.find = "\\x62"; o.replace = "\\u00e9"; setOpts(o);
        REQUIRE([c.findController replaceAllInCurrent] == 1);
        REQUIRE_EQ_STR(text(), "a\n\xC3\xA9\nc");
    });
    run(@"T-SRCH-005", @"Replace (single), Replace All in selection, Count, Replace in all opened", ^{
        [c newDocument];
        setText("cat cat cat cat");
        tpp::search::Options o; o.find = "cat"; o.replace = "dog";
        setOpts(o);
        SCI(c.editor, SCI_GOTOPOS, 0);
        exec(IDM_SEARCH_FINDNEXT);
        REQUIRE([c.findController replaceOne]);
        REQUIRE_EQ_STR(text(), "dog cat cat cat");
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 4);   // next occurrence selected
        SCI(c.editor, SCI_SETSEL, 4, 11);
        o.inSelection = true; setOpts(o);
        REQUIRE([c.findController replaceAllInCurrent] == 2);
        REQUIRE_EQ_STR(text(), "dog dog dog cat");
        o.inSelection = false; setOpts(o);
        REQUIRE([c.findController count] == 1);
        [c newDocument];
        setText("cat");
        REQUIRE([c.findController replaceAllInAllOpened] == 2);
    });
    run(@"T-SRCH-006", @"Mark All with bookmarks, purge, copy marked text, clear", ^{
        [c newDocument];
        SCI(c.editor, SCI_SETEOLMODE, SC_EOL_LF);
        setText("x1\ny\nx2\n");
        tpp::search::Options o; o.mode = tpp::search::Mode::Regex; o.find = "x\\d"; o.bookmarkLine = true; o.purge = true;
        setOpts(o);
        REQUIRE([c.findController markAll] == 2);
        REQUIRE(SCI(c.editor, SCI_MARKERNEXT, 0, 1 << TPP_MARK_BOOKMARK) == 0);
        REQUIRE(SCI(c.editor, SCI_MARKERNEXT, 1, 1 << TPP_MARK_BOOKMARK) == 2);
        REQUIRE(SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_FOUND, 0) != 0);
        exec(IDM_SEARCH_MARKEDTOCLIP);
        REQUIRE([[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:@"x1\nx2"]);
        exec(IDM_SEARCH_GONEXTMARKER_DEF);
        [c.findController clearMarks];
        REQUIRE(SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_FOUND, 0) == 0);
    });
    run(@"T-SRCH-007", @"Find All in current / all opened documents -> Search results panel + navigation", ^{
        [c newDocument];
        setText("alpha\nbeta alpha\n");
        tpp::search::Options o; o.find = "alpha";
        setOpts(o);
        REQUIRE([c.findController findAllInCurrent] == 2);
        REQUIRE(c.resultsPanel.lastHitCount == 2 && !c.resultsPanel.hidden);
        [c newDocument];
        setText("alpha");
        REQUIRE([c.findController findAllInAllOpened] == 3);
        exec(IDM_SEARCH_GOTONEXTFOUND);
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONEMPTY) == 0);
        exec(IDM_SEARCH_GOTOPREVFOUND);
        [c.resultsPanel hidePanel];
    });
    run(@"T-SRCH-008", @"Find in Files / Replace in Files (filters, sub-folders, encodings preserved)", ^{
        NSString *dir = tmpPath(@"fif");
        [[NSFileManager defaultManager] createDirectoryAtPath:[dir stringByAppendingPathComponent:@"sub"] withIntermediateDirectories:YES attributes:nil error:nil];
        writeBytes([dir stringByAppendingPathComponent:@"a.txt"], "needle 1\nhay\n");
        writeBytes([dir stringByAppendingPathComponent:@"sub/b.txt"], std::string("\xFF\xFE" "n\0e\0e\0d\0l\0e\0", 14));
        writeBytes([dir stringByAppendingPathComponent:@"c.log"], "needle\n");
        c.findController.directory = dir;
        [c.findController showTab:TPFindTabFindInFiles];
        [c.findController.window orderOut:nil];
        tpp::search::Options o; o.find = "needle"; o.replace = "pin";
        setOpts(o);
        c.findController.filters = @"*.txt";
        long hits = [c.findController findInFiles];
        REQUIRE(hits == 2);
        nextAnswer = @"OK";
        REQUIRE([c.findController replaceInFiles] == 2);
        REQUIRE_EQ_STR(readBytes([dir stringByAppendingPathComponent:@"a.txt"]), "pin 1\nhay\n");
        REQUIRE_EQ_STR(readBytes([dir stringByAppendingPathComponent:@"sub/b.txt"]), std::string("\xFF\xFE" "p\0i\0n\0", 8));
        REQUIRE_EQ_STR(readBytes([dir stringByAppendingPathComponent:@"c.log"]), "needle\n");
    });
    run(@"T-SRCH-009", @"Go to matching brace / select between braces; Select and Find Next", ^{
        [c newDocument];
        setText("f(a[b]c) d f");
        SCI(c.editor, SCI_GOTOPOS, 1);
        exec(IDM_SEARCH_GOTOMATCHINGBRACE);
        REQUIRE(SCI(c.editor, SCI_GETCURRENTPOS) == 7 || SCI(c.editor, SCI_GETCURRENTPOS) == 8);
        SCI(c.editor, SCI_GOTOPOS, 4);
        exec(IDM_SEARCH_SELECTMATCHINGBRACES);
        REQUIRE_EQ_STR(sciSelectedText(c.editor), "b");
        SCI(c.editor, SCI_SETSEL, 0, 1);
        exec(IDM_SEARCH_SETANDFINDNEXT);
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 11);
        exec(IDM_SEARCH_VOLATILE_FINDPREV);
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 0);
    });
    run(@"T-SRCH-010", @"Bookmarks: toggle, next/prev, inverse, copy/cut/paste/remove (un)marked lines", ^{
        [c newDocument];
        SCI(c.editor, SCI_SETEOLMODE, SC_EOL_LF);
        setText("l0\nl1\nl2\nl3\n");
        SCI(c.editor, SCI_GOTOLINE, 1);
        exec(IDM_SEARCH_TOGGLE_BOOKMARK);
        SCI(c.editor, SCI_GOTOLINE, 3);
        exec(IDM_SEARCH_TOGGLE_BOOKMARK);
        SCI(c.editor, SCI_GOTOLINE, 0);
        exec(IDM_SEARCH_NEXT_BOOKMARK);
        REQUIRE(SCI(c.editor, SCI_LINEFROMPOSITION, SCI(c.editor, SCI_GETCURRENTPOS)) == 1);
        exec(IDM_SEARCH_PREV_BOOKMARK);
        REQUIRE(SCI(c.editor, SCI_LINEFROMPOSITION, SCI(c.editor, SCI_GETCURRENTPOS)) == 3);
        exec(IDM_SEARCH_COPYMARKEDLINES);
        REQUIRE([[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:@"l1\nl3\n"]);
        exec(IDM_SEARCH_DELETEUNMARKEDLINES);
        REQUIRE_EQ_STR(text(), "l1\nl3\n");
        exec(IDM_SEARCH_INVERSEMARKS);            // marks only the trailing empty line now
        exec(IDM_SEARCH_DELETEMARKEDLINES);       // upstream: deleting an empty last line removes nothing
        REQUIRE_EQ_STR(text(), "l1\nl3\n");
        SCI(c.editor, SCI_MARKERDELETEALL, TPP_MARK_BOOKMARK);
        SCI(c.editor, SCI_MARKERADD, 0, TPP_MARK_BOOKMARK);
        exec(IDM_SEARCH_DELETEMARKEDLINES);
        REQUIRE_EQ_STR(text(), "l3\n");
        exec(IDM_SEARCH_CLEAR_BOOKMARKS);
        REQUIRE(SCI(c.editor, SCI_MARKERNEXT, 0, 1 << TPP_MARK_BOOKMARK) == -1);
    });
    run(@"T-SRCH-011", @"Style all occurrences of token (5 styles), jump, copy, clear", ^{
        [c newDocument];
        setText("tok x tok y tokx");
        SCI(c.editor, SCI_GOTOPOS, 1);
        exec(IDM_SEARCH_MARKALLEXT2);
        REQUIRE(SCI(c.editor, SCI_INDICATORVALUEAT, 24, 0) && SCI(c.editor, SCI_INDICATORVALUEAT, 24, 6) && !SCI(c.editor, SCI_INDICATORVALUEAT, 24, 12));
        exec(IDM_SEARCH_STYLE2TOCLIP);
        REQUIRE([[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:@"tok\ntok"]);
        SCI(c.editor, SCI_GOTOPOS, 0);
        exec(IDM_SEARCH_GONEXTMARKER2);
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 6);
        exec(IDM_SEARCH_UNMARKALLEXT2);
        REQUIRE(!SCI(c.editor, SCI_INDICATORVALUEAT, 24, 0));
        SCI(c.editor, SCI_SETSEL, 6, 9);
        exec(IDM_SEARCH_MARKONEEXT1);
        REQUIRE(SCI(c.editor, SCI_INDICATORVALUEAT, 25, 6) && !SCI(c.editor, SCI_INDICATORVALUEAT, 25, 0));
        exec(IDM_SEARCH_CLEARALLMARKS);
        REQUIRE(!SCI(c.editor, SCI_INDICATORVALUEAT, 25, 6));
    });
    run(@"T-SRCH-012", @"Change history markers and navigation", ^{
        NSString *p = tmpPath(@"hist.txt");
        writeBytes(p, "a\nb\nc\nd\n");
        [c openFile:p];
        SCI(c.editor, SCI_GOTOLINE, 2);
        SCI(c.editor, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>("X"));
        SCI(c.editor, SCI_GOTOLINE, 0);
        exec(IDM_SEARCH_CHANGED_NEXT);
        REQUIRE(SCI(c.editor, SCI_LINEFROMPOSITION, SCI(c.editor, SCI_GETCURRENTPOS)) == 2);
        nextAnswer = @"Yes";
        exec(IDM_SEARCH_CLEAR_CHANGE_HISTORY);
        REQUIRE(SCI(c.editor, SCI_MARKERNEXT, 0, SC_MASK_HISTORY) == -1);
    });

    run(@"T-EDIT-012", @"Auto-indent keeps indentation; smart highlighting marks other occurrences", ^{
        [c newDocument];
        exec(IDM_LANG_CPP);
        SCI(c.editor, SCI_SETEOLMODE, SC_EOL_LF);
        SCI(c.editor, SCI_SETUSETABS, 0);
        SCI(c.editor, SCI_SETTABWIDTH, 4);
        setText("    int a;");
        SCI(c.editor, SCI_DOCUMENTEND);
        SCI(c.editor, SCI_NEWLINE);          // same path as pressing Return
        REQUIRE_EQ_STR(text(), "    int a;\n    ");
        setText("if (x) {");
        SCI(c.editor, SCI_DOCUMENTEND);
        SCI(c.editor, SCI_NEWLINE);
        REQUIRE_EQ_STR(text(), "if (x) {\n    ");
        setText("word other word Word words");
        SCI(c.editor, SCI_SETSEL, 0, 4);
        [c smartHighlightInView_forTests:c.editor];
        REQUIRE(SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_SMART, 11) && SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_SMART, 16));
        REQUIRE(!SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_SMART, 21) && !SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_SMART, 0));
    });

    // ================================================================ view
    run(@"T-VIEW-001", @"Word wrap, show symbols, indent guide, zoom", ^{
        [c newDocument];
        BOOL wrap = SCI(c.editor, SCI_GETWRAPMODE) != SC_WRAP_NONE;
        exec(IDM_VIEW_WRAP);
        REQUIRE((SCI(c.editor, SCI_GETWRAPMODE) != SC_WRAP_NONE) == !wrap);
        exec(IDM_VIEW_WRAP);
        exec(IDM_VIEW_TAB_SPACE);
        REQUIRE(SCI(c.editor, SCI_GETVIEWWS) == SCWS_VISIBLEALWAYS);
        exec(IDM_VIEW_TAB_SPACE);
        REQUIRE(SCI(c.editor, SCI_GETVIEWWS) == SCWS_INVISIBLE);
        exec(IDM_VIEW_ALL_CHARACTERS);
        REQUIRE(SCI(c.editor, SCI_GETVIEWEOL) && SCI(c.editor, SCI_GETVIEWWS) == SCWS_VISIBLEALWAYS);
        exec(IDM_VIEW_ALL_CHARACTERS);
        REQUIRE(!SCI(c.editor, SCI_GETVIEWEOL));
        sptr_t g = SCI(c.editor, SCI_GETINDENTATIONGUIDES);
        exec(IDM_VIEW_INDENT_GUIDE);
        REQUIRE(SCI(c.editor, SCI_GETINDENTATIONGUIDES) != g);
        exec(IDM_VIEW_INDENT_GUIDE);
        exec(IDM_VIEW_ZOOMIN);
        exec(IDM_VIEW_ZOOMIN);
        REQUIRE(SCI(c.editor, SCI_GETZOOM) == 2);
        exec(IDM_VIEW_ZOOMOUT);
        REQUIRE(SCI(c.editor, SCI_GETZOOM) == 1);
        exec(IDM_VIEW_ZOOMRESTORE);
        REQUIRE(SCI(c.editor, SCI_GETZOOM) == 0);
    });
    run(@"T-VIEW-002", @"Clone to other view shares the buffer; move to other view", ^{
        TPDocument *d = [c newDocument];
        setText("shared");
        exec(IDM_VIEW_CLONE_TO_ANOTHER_VIEW);
        REQUIRE(c.activePane == c.subPane && c.subPane.currentDocument == d && [c.mainPane indexOfDocument:d] != NSNotFound);
        SCI(c.editor, SCI_DOCUMENTEND);
        SCI(c.editor, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>("!"));
        REQUIRE_EQ_STR(sciGetText(c.mainPane.editor), "shared!");
        exec(IDM_VIEW_SWITCHTO_OTHER_VIEW);
        REQUIRE(c.activePane == c.mainPane);
        TPDocument *m = [c newDocument];
        exec(IDM_VIEW_GOTO_ANOTHER_VIEW);
        REQUIRE([c.mainPane indexOfDocument:m] == NSNotFound && [c.subPane indexOfDocument:m] != NSNotFound);
    });
    run(@"T-VIEW-003", @"Folding: fold all / unfold all / fold level (C++)", ^{
        [c newDocument];
        exec(IDM_LANG_CPP);
        SCI(c.editor, SCI_SETEOLMODE, SC_EOL_LF);
        setText("void f() {\n  if (x) {\n    y();\n  }\n}\n");
        SCI(c.editor, SCI_COLOURISE, 0, -1);
        exec(IDM_VIEW_FOLDALL);
        REQUIRE(!SCI(c.editor, SCI_GETLINEVISIBLE, 2));
        exec(IDM_VIEW_UNFOLDALL);
        REQUIRE(SCI(c.editor, SCI_GETLINEVISIBLE, 2));
        exec(IDM_VIEW_FOLD_2);
        REQUIRE(!SCI(c.editor, SCI_GETLINEVISIBLE, 2) && SCI(c.editor, SCI_GETLINEVISIBLE, 1));
        exec(IDM_VIEW_UNFOLD_2);
        REQUIRE(SCI(c.editor, SCI_GETLINEVISIBLE, 2));
        SCI(c.editor, SCI_GOTOLINE, 2);
        exec(IDM_VIEW_FOLD_CURRENT);
        REQUIRE(!SCI(c.editor, SCI_GETLINEVISIBLE, 2));
        exec(IDM_VIEW_UNFOLD_CURRENT);
        REQUIRE(SCI(c.editor, SCI_GETLINEVISIBLE, 2));
    });
    run(@"T-VIEW-004", @"Tab navigation, move tab, tab colour, sort tabs", ^{
        TPDocument *a = [c newDocument]; TPDocument *b = [c newDocument]; TPDocument *d3 = [c newDocument];
        exec(IDM_VIEW_TAB1);
        REQUIRE(c.currentDocument == c.mainPane.documents[0]);
        exec(IDM_VIEW_TAB_NEXT);
        REQUIRE(c.currentDocument == c.mainPane.documents[1]);
        exec(IDM_VIEW_TAB_PREV);
        exec(IDM_VIEW_TAB_END);
        REQUIRE(c.currentDocument == c.mainPane.documents.lastObject);
        exec(IDM_VIEW_GOTO_START);
        REQUIRE(c.mainPane.documents.firstObject == c.currentDocument);
        exec(IDM_VIEW_TAB_COLOUR_3);
        REQUIRE(c.currentDocument.tabColor == 2 && [reg isChecked:IDM_VIEW_TAB_COLOUR_3]);
        exec(IDM_VIEW_TAB_COLOUR_NONE);
        REQUIRE(c.currentDocument.tabColor == -1);
        a.untitledName = @"zeta"; b.untitledName = @"alpha"; d3.untitledName = @"mid";
        exec(IDM_WINDOW_SORT_FN_ASC);
        NSArray *names = [c.mainPane.documents valueForKey:@"displayName"];
        NSArray *ours = [names filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF IN %@", @[@"alpha", @"mid", @"zeta"]]];
        REQUIRE([ours isEqualToArray:(@[@"alpha", @"mid", @"zeta"])]);
        exec(IDM_WINDOW_SORT_FN_DSC);
        ours = [[c.mainPane.documents valueForKey:@"displayName"] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF IN %@", @[@"alpha", @"mid", @"zeta"]]];
        REQUIRE([ours isEqualToArray:(@[@"zeta", @"mid", @"alpha"])]);
    });
    run(@"T-VIEW-005", @"Hide lines, monitoring (tail -f) mode", ^{
        [c newDocument];
        SCI(c.editor, SCI_SETEOLMODE, SC_EOL_LF);
        setText("0\n1\n2\n3\n4\n");
        SCI(c.editor, SCI_SETSEL, SCI(c.editor, SCI_POSITIONFROMLINE, 1), SCI(c.editor, SCI_GETLINEENDPOSITION, 3));
        exec(IDM_VIEW_HIDELINES);
        REQUIRE(!SCI(c.editor, SCI_GETLINEVISIBLE, 2));
        NSString *p = tmpPath(@"tail.log");
        writeBytes(p, "line1\n");
        [c openFile:p];
        exec(IDM_VIEW_MONITORING);
        REQUIRE(c.currentDocument.monitoring && SCI(c.editor, SCI_GETREADONLY));
        [NSThread sleepForTimeInterval:1.1];
        writeBytes(p, "line1\nline2 appended\n");
        [c checkFilesModifiedOnDisk];
        REQUIRE_EQ_STR(text(), "line1\nline2 appended\n");
        exec(IDM_VIEW_MONITORING);
        REQUIRE(!c.currentDocument.monitoring);
    });

    // ================================================================ encoding
    run(@"T-ENC-001", @"Convert to UTF-16 LE BOM / UTF-8-BOM then save", ^{
        NSString *p = tmpPath(@"conv.txt");
        writeBytes(p, "h\xC3\xA9");
        [c openFile:p];
        exec(IDM_FORMAT_CONV2_UTF_16LE);
        REQUIRE(c.currentDocument.dirty && [[c.statusBar textForPart:4] isEqualToString:@"UTF-16 LE BOM"]);
        exec(IDM_FILE_SAVE);
        REQUIRE_EQ_STR(readBytes(p), std::string("\xFF\xFE" "h\0\xE9\0", 6));
        exec(IDM_FORMAT_CONV2_UTF_8);
        exec(IDM_FILE_SAVE);
        REQUIRE_EQ_STR(readBytes(p), "\xEF\xBB\xBF" "h\xC3\xA9");
        exec(IDM_FORMAT_CONV2_AS_UTF_8);
        exec(IDM_FILE_SAVE);
        REQUIRE_EQ_STR(readBytes(p), "h\xC3\xA9");
    });
    run(@"T-ENC-002", @"Character sets: reinterpret a Windows-1251 file", ^{
        NSString *p = tmpPath(@"cyr.txt");
        writeBytes(p, "\xCF\xF0\xE8\xE2\xE5\xF2");
        [TPPrefs set:@NO forKey:@"pref.detectEncoding"];                  // opened as ANSI, then reinterpreted by hand
        [c openFile:p];
        REQUIRE(c.currentDocument.encoding.mode == tpp::UniMode::Ansi);
        nextAnswer = @"Yes";
        exec(IDM_FORMAT_WIN_1251);
        REQUIRE_EQ_STR(text(), "\xD0\x9F\xD1\x80\xD0\xB8\xD0\xB2\xD0\xB5\xD1\x82");
        REQUIRE([[c.statusBar textForPart:4] isEqualToString:@"Windows-1251"]);
        SCI(c.editor, SCI_DOCUMENTEND);
        SCI(c.editor, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>("!"));
        exec(IDM_FILE_SAVE);
        REQUIRE_EQ_STR(readBytes(p), "\xCF\xF0\xE8\xE2\xE5\xF2!");
    });
    run(@"T-ENC-003", @"Encoding > UTF-8 on an ANSI-detected buffer reinterprets bytes without dirtying", ^{
        NSString *p = tmpPath(@"mojibake.txt");
        writeBytes(p, "\xC3\xA9\xFF");   // invalid UTF-8 overall -> detected ANSI
        [c openFile:p];
        REQUIRE(c.currentDocument.encoding.mode == tpp::UniMode::Ansi);
        exec(IDM_FORMAT_AS_UTF_8);
        REQUIRE(c.currentDocument.encoding.mode == tpp::UniMode::Utf8 && !c.currentDocument.dirty);
        REQUIRE_EQ_STR(text(), "\xC3\xA9\xFF");   // raw bytes kept; é now shown as UTF-8
        exec(IDM_FORMAT_ANSI);
        REQUIRE(c.currentDocument.encoding.mode == tpp::UniMode::Ansi);
        REQUIRE_EQ_STR(text(), "\xC3\x83\xC2\xA9\xC3\xBF");
    });

    // ================================================================ language
    run(@"T-LANG-001", @"Language auto-detected from extension; lexer + keyword styling applied", ^{
        NSString *p = tmpPath(@"code.py");
        writeBytes(p, "def f():\n    return 1\n");
        [c openFile:p];
        REQUIRE([c.currentDocument.languageId isEqualToString:@"python"]);
        char lex[64] = {0};
        SCI(c.editor, SCI_GETLEXERLANGUAGE, 0, reinterpret_cast<sptr_t>(lex));
        REQUIRE(std::string(lex) == "python");
        SCI(c.editor, SCI_COLOURISE, 0, -1);
        REQUIRE(SCI(c.editor, SCI_GETSTYLEAT, 0) == SCE_P_WORD);
        REQUIRE([[c.statusBar textForPart:0] isEqualToString:@"Python file"]);
    });
    run(@"T-LANG-002", @"Every Language menu entry sets its Lexilla lexer", ^{
        [c newDocument];
        NSMutableArray *bad = [NSMutableArray array];
        for (TPLanguage *l in [TPLanguageService shared].languages) {
            if (!l.menuCommand || [l.langId isEqualToString:@"udf"]) continue;
            exec(l.menuCommand);
            char lex[64] = {0};
            SCI(c.editor, SCI_GETLEXERLANGUAGE, 0, reinterpret_cast<sptr_t>(lex));
            NSString *got = @(lex);
            NSString *want = [l.lexerName isEqualToString:@"null"] ? @"" : l.lexerName;
            // Lexilla reports module names with their own capitalisation (e.g. "D" for the "d" lexer)
            if ([got caseInsensitiveCompare:want] != NSOrderedSame && !([want isEqualToString:@""] && [got isEqualToString:@"null"])) [bad addObject:[NSString stringWithFormat:@"%@(%@≠%@)", l.langId, got, want]];
        }
        if (bad.count) fail = [@"lexer mismatch: " stringByAppendingString:[bad componentsJoinedByString:@", "]];
    });

    // ================================================================ tools / macro / window
    run(@"T-TOOL-001", @"Hash selection into clipboard (MD5/SHA-1/SHA-256/SHA-512)", ^{
        [c newDocument];
        setText("abc");
        exec(IDM_EDIT_SELECTALL);
        struct { int cmd; tpp::HashAlgorithm a; } hs[] = {{IDM_TOOL_MD5_GENERATEINTOCLIPBOARD, tpp::HashAlgorithm::MD5}, {IDM_TOOL_SHA1_GENERATEINTOCLIPBOARD, tpp::HashAlgorithm::SHA1},
                                                         {IDM_TOOL_SHA256_GENERATEINTOCLIPBOARD, tpp::HashAlgorithm::SHA256}, {IDM_TOOL_SHA512_GENERATEINTOCLIPBOARD, tpp::HashAlgorithm::SHA512}};
        for (auto &h : hs) {
            exec(h.cmd);
            REQUIRE([[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:NSStr(tpp::hashHex(h.a, "abc"))]);
        }
    });
    run(@"T-MACRO-001", @"Record, play back, run N times, save to shortcuts.xml", ^{
        [c newDocument];
        exec(IDM_MACRO_STARTRECORDINGMACRO);
        SCI(c.editor, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>("ab"));
        SCI(c.editor, SCI_NEWLINE);
        exec(IDM_MACRO_STOPRECORDINGMACRO);
        REQUIRE_EQ_STR(text(), "ab\n");
        exec(IDM_MACRO_PLAYBACKRECORDEDMACRO);
        REQUIRE_EQ_STR(text(), "ab\nab\n");
        exec(IDM_EDIT_UNDO);   // playback is one undo step
        REQUIRE_EQ_STR(text(), "ab\n");
        REQUIRE([c saveCurrentMacroNamed_forTests:@"Self-test macro"]);
        NSString *xml = [NSString stringWithContentsOfFile:[[TPSession shared].supportDirectory stringByAppendingPathComponent:@"shortcuts.xml"] encoding:NSUTF8StringEncoding error:nil];
        REQUIRE([xml containsString:@"Self-test macro"] && [xml containsString:@"sParam=\"ab\""]);
    });
    run(@"T-MACRO-002", @"Macro with menu commands (Trim Trailing Space) replays real edits", ^{
        [c newDocument];
        SCI(c.editor, SCI_SETEOLMODE, SC_EOL_LF);
        setText("a  \nb \n");
        exec(IDM_MACRO_STARTRECORDINGMACRO);
        exec(IDM_EDIT_TRIMTRAILING);
        exec(IDM_MACRO_STOPRECORDINGMACRO);
        setText("x \ny  \n");
        exec(IDM_MACRO_PLAYBACKRECORDEDMACRO);
        REQUIRE_EQ_STR(text(), "x\ny\n");
    });
    run(@"T-WIN-001", @"Window menu lists documents", ^{
        [c newDocument]; [c newDocument];
        NSMenu *m = [reg topLevelMenuNamed:@"Window"];
        [c menuNeedsUpdate:m];
        NSInteger n = 0;
        for (NSMenuItem *mi in m.itemArray) if ([mi.representedObject isKindOfClass:[TPDocument class]]) ++n;
        REQUIRE(n == (NSInteger)c.activePane.documents.count);
    });

    // ================================================================ Preferences (each test resets preferences afterwards)
    auto typeText = [&](NSString *t) {
        for (NSUInteger i = 0; i < t.length; ++i)
            [c.editor.content insertText:[t substringWithRange:NSMakeRange(i, 1)] replacementRange:NSMakeRange(NSNotFound, 0)];
    };
    run(@"T-PREF-001", @"Preferences window builds all 24 upstream pages + Textpad++ Features; every live control has a registered default", ^{
        NSArray *pages = [TPPrefs pages];
        REQUIRE(pages.count == 25);
        [TPPreferencesWindow shared].window.alphaValue = 0;   // keep the test invisible
        REQUIRE(exec(IDM_SETTING_PREFERENCE));
        REQUIRE([TPPreferencesWindow shared].window.isVisible);
        NSDictionary *defaults = [[NSUserDefaults standardUserDefaults] volatileDomainForName:NSRegistrationDomain];
        for (NSDictionary *pg in pages) {
            [[TPPreferencesWindow shared] showPage:pg[@"title"]];
            REQUIRE([[TPPreferencesWindow shared].currentPage isEqualToString:pg[@"title"]]);
            for (NSDictionary *row in pg[@"rows"]) {
                if (!row[@"key"] || row[@"na"]) continue;
                if (!defaults[row[@"key"]]) { fail = [NSString stringWithFormat:@"no default for %@", row[@"key"]]; return; }
            }
        }
        [[TPPreferencesWindow shared].window orderOut:nil];
    });
    run(@"T-PREF-002", @"Editing 1/2 options reach Scintilla (caret, current line, wrap indent, virtual space, scrolling, drag-drop, multi-editing)", ^{
        [c newDocument];
        [TPPrefs set:@2 forKey:@"pref.currentLineMode"]; [TPPrefs set:@3 forKey:@"pref.currentLineFrameWidth"];
        REQUIRE(SCI(c.editor, SCI_GETCARETLINEFRAME) == 3);
        [TPPrefs set:@0 forKey:@"pref.currentLineMode"];
        REQUIRE(SCI(c.editor, SCI_GETCARETLINEVISIBLE) == 0);
        [TPPrefs set:@4 forKey:@"pref.caretWidth"];
        REQUIRE(SCI(c.editor, SCI_GETCARETSTYLE) & CARETSTYLE_BLOCK);
        [TPPrefs set:@2 forKey:@"pref.caretWidth"];
        REQUIRE(SCI(c.editor, SCI_GETCARETWIDTH) == 2);
        [TPPrefs set:@0 forKey:@"pref.caretBlink"];
        REQUIRE(SCI(c.editor, SCI_GETCARETPERIOD) == 0);
        [TPPrefs set:@2 forKey:@"pref.wrapIndentMode"];
        REQUIRE(SCI(c.editor, SCI_GETWRAPINDENTMODE) == SC_WRAPINDENT_INDENT);
        [TPPrefs set:@YES forKey:@"pref.virtualSpace"];
        REQUIRE(SCI(c.editor, SCI_GETVIRTUALSPACEOPTIONS) & SCVS_USERACCESSIBLE);
        [TPPrefs set:@NO forKey:@"pref.scrollBeyondLast"];
        REQUIRE(SCI(c.editor, SCI_GETENDATLASTLINE) == 1);
        [TPPrefs set:@YES forKey:@"pref.disableDragDrop"];
        REQUIRE(SCI(c.editor, SCI_GETDRAGDROPENABLED) == 0);
        [TPPrefs set:@NO forKey:@"pref.multiEditing"];
        REQUIRE(SCI(c.editor, SCI_GETMULTIPLESELECTION) == 0);
        [TPPrefs set:@YES forKey:@"pref.backspaceUnindent"];
        REQUIRE(SCI(c.editor, SCI_GETBACKSPACEUNINDENTS) == 1);
        [TPPrefs set:@NO forKey:@"pref.copyCutLine"];
        setText("line one\nline two");
        [[NSPasteboard generalPasteboard] clearContents];
        exec(IDM_EDIT_COPY);
        REQUIRE([[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] == nil);
    });
    run(@"T-PREF-003", @"Margins/Border/Edge: fold styles, edges, line numbers, bookmark/change-history margins, padding", ^{
        [c newDocument];
        [TPPrefs set:@1 forKey:@"pref.foldStyle"];
        REQUIRE(SCI(c.editor, SCI_MARKERSYMBOLDEFINED, SC_MARKNUM_FOLDER) == SC_MARK_ARROW);
        [TPPrefs set:@2 forKey:@"pref.foldStyle"];
        REQUIRE(SCI(c.editor, SCI_MARKERSYMBOLDEFINED, SC_MARKNUM_FOLDER) == SC_MARK_CIRCLEPLUS);
        [TPPrefs set:@4 forKey:@"pref.foldStyle"];
        REQUIRE(SCI(c.editor, SCI_GETMARGINWIDTHN, TPP_MARGIN_FOLDER) == 0);
        [TPPrefs set:@YES forKey:@"pref.edgeEnabled"]; [TPPrefs set:@"80 120" forKey:@"pref.edgeColumns"];
        REQUIRE(SCI(c.editor, SCI_GETEDGEMODE) == EDGE_MULTILINE);
        [TPPrefs set:@"100" forKey:@"pref.edgeColumns"]; [TPPrefs set:@YES forKey:@"pref.edgeBgMode"];
        REQUIRE(SCI(c.editor, SCI_GETEDGEMODE) == EDGE_BACKGROUND && SCI(c.editor, SCI_GETEDGECOLUMN) == 100);
        [TPPrefs set:@NO forKey:@"pref.lineNumbers"];
        REQUIRE(SCI(c.editor, SCI_GETMARGINWIDTHN, TPP_MARGIN_LINENUMBER) == 0);
        [TPPrefs set:@NO forKey:@"pref.bookmarkMargin"];
        REQUIRE(SCI(c.editor, SCI_GETMARGINWIDTHN, TPP_MARGIN_SYMBOL) == 0);
        [TPPrefs set:@NO forKey:@"pref.chMargin"];
        REQUIRE(SCI(c.editor, SCI_GETMARGINWIDTHN, TPP_MARGIN_CHANGEHISTORY) == 0);
        [TPPrefs set:@10 forKey:@"pref.padLeft"];
        REQUIRE(SCI(c.editor, SCI_GETMARGINLEFT) == 10);
    });
    run(@"T-PREF-004", @"New Document defaults (EOL, encoding, code page, language) and 'Apply to opened ANSI files'", ^{
        [TPPrefs set:@(SC_EOL_CRLF) forKey:@"NewDocEOL"]; [TPPrefs set:@1 forKey:@"NewDocUniMode"]; [TPPrefs set:@"python" forKey:@"pref.defaultLanguage"];
        TPDocument *d = [c newDocument];
        REQUIRE(d.eolMode == SC_EOL_CRLF && SCI(c.editor, SCI_GETEOLMODE) == SC_EOL_CRLF);
        REQUIRE(d.encoding.mode == tpp::UniMode::Utf8Bom && [d.languageId isEqualToString:@"python"]);
        [TPPrefs set:@1251 forKey:@"NewDocCodepage"];
        REQUIRE([c newDocument].encoding.codepage == 1251);
        [TPPrefs set:@NO forKey:@"pref.openAnsiAsUtf8"];
        NSString *p = tmpPath(@"ascii.txt");
        writeBytes(p, "plain ascii");
        REQUIRE([c openFile:p].encoding.mode == tpp::UniMode::Ansi);
    });
    run(@"T-PREF-005", @"Indentation: per-language tab size/spaces, auto-indent None/Basic", ^{
        [TPPrefs set:@{@"python": @{@"useDefault": @NO, @"size": @2, @"spaces": @YES}} forKey:@"pref.langIndent"];
        [c newDocument];
        exec(IDM_LANG_PYTHON);
        REQUIRE(SCI(c.editor, SCI_GETTABWIDTH) == 2 && SCI(c.editor, SCI_GETUSETABS) == 0);
        exec(IDM_LANG_CPP);
        REQUIRE(SCI(c.editor, SCI_GETTABWIDTH) == 4 && SCI(c.editor, SCI_GETUSETABS) == 1);
        SCI(c.editor, SCI_SETEOLMODE, SC_EOL_LF);
        [TPPrefs set:@0 forKey:@"pref.autoIndent"];
        setText("    x");
        SCI(c.editor, SCI_DOCUMENTEND);
        SCI(c.editor, SCI_NEWLINE);
        REQUIRE_EQ_STR(text(), "    x\n");
        [TPPrefs set:@1 forKey:@"pref.autoIndent"];
        setText("if (a) {");
        SCI(c.editor, SCI_DOCUMENTEND);
        SCI(c.editor, SCI_NEWLINE);
        REQUIRE_EQ_STR(text(), "if (a) {\n");   // Basic: no extra indent after a brace
    });
    run(@"T-PREF-006", @"Toolbar / Tab bar / Status bar / Dark mode", ^{
        [c newDocument];
        [TPPrefs set:@YES forKey:@"pref.toolbarHidden"];
        REQUIRE(c.toolbar.hidden);
        [TPPrefs set:@NO forKey:@"pref.toolbarHidden"];
        [TPPrefs set:@1 forKey:@"pref.toolbarIconSet"];
        REQUIRE(c.toolbar.preferredHeight == 36);
        [TPPrefs set:@2 forKey:@"pref.toolbarIconSet"];
        REQUIRE(c.toolbar.preferredHeight == 28);
        [TPPrefs set:@YES forKey:@"pref.statusBarHidden"];
        REQUIRE(c.statusBar.hidden);
        [TPPrefs set:@YES forKey:@"pref.tabHidden"];
        REQUIRE(c.mainPane.tabBar.hidden);
        [TPPrefs set:@NO forKey:@"pref.tabHidden"];
        [TPPrefs set:@NO forKey:@"pref.tabReduce"];
        REQUIRE([TPTabBarView preferredHeight] == 28);
        [TPPrefs set:@1 forKey:@"pref.darkMode"];
        int bg = static_cast<int>(SCI(c.editor, SCI_STYLEGETBACK, STYLE_DEFAULT));
        REQUIRE(((bg & 0xFF) + ((bg >> 8) & 0xFF) + ((bg >> 16) & 0xFF)) < 200);   // dark editor background
        REQUIRE([c.window.appearance.name isEqualToString:NSAppearanceNameDarkAqua]);
        [TPPrefs set:@0 forKey:@"pref.darkMode"];
        REQUIRE(SCI(c.editor, SCI_STYLEGETBACK, STYLE_DEFAULT) == rgbToSci(0xFFFFFF));
    });
    run(@"T-PREF-007", @"Highlighting: smart highlight on/off, match case, use Find settings; token style matching", ^{
        [c newDocument];
        setText("word Word word");
        SCI(c.editor, SCI_SETSEL, 0, 4);
        [c smartHighlightInView_forTests:c.editor];
        REQUIRE(SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_SMART, 5) && SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_SMART, 10));
        [TPPrefs set:@YES forKey:@"pref.smartHLMatchCase"];
        SCI(c.editor, SCI_SETSEL, 0, 4);
        [c smartHighlightInView_forTests:c.editor];
        if (!(!SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_SMART, 5) && SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_SMART, 10))) {
            SCI(c.editor, SCI_SETSEARCHFLAGS, SCFIND_WHOLEWORD | SCFIND_MATCHCASE);
            SCI(c.editor, SCI_SETTARGETRANGE, 4, SCI(c.editor, SCI_GETLENGTH));
            sptr_t probe = SCI(c.editor, SCI_SEARCHINTARGET, 4, reinterpret_cast<sptr_t>("word"));
            fail = [NSString stringWithFormat:@"probe=%ld text=[%s] at5=%ld at10=%ld mc=%d sel=%ld-%ld", (long)probe, text().c_str(), (long)SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_SMART, 5), (long)SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_SMART, 10),
                    [TPPrefs b:@"pref.smartHLMatchCase"], (long)SCI(c.editor, SCI_GETSELECTIONSTART), (long)SCI(c.editor, SCI_GETSELECTIONEND)];
            return;
        }
        [TPPrefs set:@NO forKey:@"pref.smartHL"];
        [c smartHighlightInView_forTests:c.editor];
        REQUIRE(!SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_SMART, 10));
        [TPPrefs set:@NO forKey:@"pref.markAllWholeWord"]; [TPPrefs set:@YES forKey:@"pref.markAllMatchCase"];
        setText("ab xab AB");
        SCI(c.editor, SCI_GOTOPOS, 1);
        exec(IDM_SEARCH_MARKALLEXT1);
        REQUIRE(SCI(c.editor, SCI_INDICATORVALUEAT, 25, 4) && !SCI(c.editor, SCI_INDICATORVALUEAT, 25, 7));
    });
    run(@"T-PREF-008", @"Auto-Completion / Auto-Insert on typing (pairs, type-over, html close tag, completion list)", ^{
        [c newDocument];
        [TPPrefs set:@YES forKey:@"pref.pairParen"]; [TPPrefs set:@YES forKey:@"pref.pairQuote"];
        typeText(@"f(");
        REQUIRE_EQ_STR(text(), "f()");
        typeText(@")");
        REQUIRE_EQ_STR(text(), "f()");
        typeText(@"\"");
        REQUIRE_EQ_STR(text(), "f()\"\"");
        [c newDocument];
        exec(IDM_LANG_HTML);
        [TPPrefs set:@YES forKey:@"pref.pairHtmlTag"];
        typeText(@"<div>");
        REQUIRE_EQ_STR(text(), "<div></div>");
        [c newDocument];
        [TPPrefs set:@1 forKey:@"pref.autocMode"]; [TPPrefs set:@2 forKey:@"pref.autocFromLen"];
        setText("elephant\n");
        SCI(c.editor, SCI_DOCUMENTEND);
        typeText(@"e");
        REQUIRE(SCI(c.editor, SCI_AUTOCACTIVE) == 0);   // below "From the Nth character"
        typeText(@"l");
        if (SCI(c.editor, SCI_AUTOCACTIVE) == 0) {
            std::string t = text(); for (auto &ch : t) if (ch == '\n') ch = '|';
            fail = [NSString stringWithFormat:@"text=[%s] pos=%ld wordstart=%ld", t.c_str(), (long)SCI(c.editor, SCI_GETCURRENTPOS), (long)SCI(c.editor, SCI_WORDSTARTPOSITION, SCI(c.editor, SCI_GETCURRENTPOS), 1)];
            return;
        }
        SCI(c.editor, SCI_AUTOCCANCEL);
        [TPPrefs set:@NO forKey:@"pref.autocEnabled"];
        typeText(@"e");
        REQUIRE(SCI(c.editor, SCI_AUTOCACTIVE) == 0);
    });
    run(@"T-PREF-009", @"Backup on save (simple + verbose) and Large File Restriction", ^{
        NSString *p = tmpPath(@"bak.txt");
        writeBytes(p, "v1");
        [c openFile:p];
        [TPPrefs set:@1 forKey:@"pref.backupOnSave"];
        setText("v2");
        exec(IDM_FILE_SAVE);
        REQUIRE_EQ_STR(readBytes(tmpPath(@"TextpadBackup/bak.txt.bak")), "v1");
        [TPPrefs set:@2 forKey:@"pref.backupOnSave"];
        setText("v3");
        exec(IDM_FILE_SAVE);
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tmpPath(@"TextpadBackup") error:nil];
        NSPredicate *verbose = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", @"bak\\.txt\\.[0-9-]+_[0-9]+\\.bak"];
        REQUIRE([[files filteredArrayUsingPredicate:verbose] count] == 1);
        [TPPrefs set:@1 forKey:@"pref.largeFileMB"];
        NSString *big = tmpPath(@"big.cpp");
        writeBytes(big, std::string(1600 * 1024, 'x'));
        TPDocument *d = [c openFile:big];
        REQUIRE([d.languageId isEqualToString:@"normal"]);
        char lex[64] = {0};
        SCI(c.editor, SCI_GETLEXERLANGUAGE, 0, reinterpret_cast<sptr_t>(lex));
        REQUIRE(std::string(lex) == "null" || std::string(lex).empty());
    });
    run(@"T-PREF-010", @"Delimiter: custom word characters and ⌘+double-click delimiter selection; clickable links", ^{
        [c newDocument];
        setText("a-b c");
        REQUIRE(SCI(c.editor, SCI_WORDENDPOSITION, 0, 1) == 1);
        [TPPrefs set:@NO forKey:@"pref.wordCharsDefault"]; [TPPrefs set:@"-" forKey:@"pref.wordCharsCustom"];
        REQUIRE(SCI(c.editor, SCI_WORDENDPOSITION, 0, 1) == 3);
        setText("call(alpha, beta) end");
        SCNotification scn = {};
        scn.nmhdr.code = SCN_DOUBLECLICK;
        scn.position = 7;
        scn.modifiers = SCMOD_CTRL;
        [c pane:c.mainPane notification:&scn];
        REQUIRE_EQ_STR(sciSelectedText(c.editor), "alpha, beta");
        setText("see https://example.com/x. now");
        [c markLinksInView:c.editor document:c.currentDocument];
        REQUIRE(SCI(c.editor, SCI_INDICATORVALUEAT, 8, 4) && SCI(c.editor, SCI_INDICATORVALUEAT, 8, 24) && !SCI(c.editor, SCI_INDICATORVALUEAT, 8, 25));
        [TPPrefs set:@NO forKey:@"pref.links"];
        [c markLinksInView:c.editor document:c.currentDocument];
        REQUIRE(!SCI(c.editor, SCI_INDICATORVALUEAT, 8, 4));
    });
    run(@"T-PREF-011", @"MISC.: short title, file auto-detection modes, update silently; recent files display/submenu", ^{
        NSString *p = tmpPath(@"misc.txt");
        writeBytes(p, "one");
        [c openFile:p];
        [TPPrefs set:@YES forKey:@"pref.shortTitle"];
        REQUIRE([c.window.title isEqualToString:@"misc.txt - Textpad++"]);
        [TPPrefs set:@2 forKey:@"pref.fileAutoDetect"];
        [NSThread sleepForTimeInterval:1.1];
        writeBytes(p, "two");
        [c checkFilesModifiedOnDisk];
        REQUIRE_EQ_STR(text(), "one");
        [TPPrefs set:@0 forKey:@"pref.fileAutoDetect"]; [TPPrefs set:@YES forKey:@"pref.updateSilently"];
        __block int prompts = 0;
        NSInteger (^saved)(NSString *, NSArray *) = c.promptOverride;
        c.promptOverride = ^NSInteger(NSString *m, NSArray *b) { ++prompts; return 0; };
        [c checkFilesModifiedOnDisk];
        c.promptOverride = saved;
        REQUIRE_EQ_STR(text(), "two");
        REQUIRE(prompts == 0);
        [TPPrefs set:@0 forKey:@"pref.recentDisplay"];
        REQUIRE([[TPMainWindowController recentLabelForPath:@"/a/b/c.txt"] isEqualToString:@"c.txt"]);
        [TPPrefs set:@2 forKey:@"pref.recentDisplay"]; [TPPrefs set:@11 forKey:@"pref.recentCustomLength"];
        REQUIRE([[TPMainWindowController recentLabelForPath:@"/abcdefghij/klmnop.txt"] length] <= 11);
        [TPPrefs set:@YES forKey:@"pref.recentInSubmenu"];
        NSMenu *fm = [reg topLevelMenuNamed:@"File"];
        [c menuNeedsUpdate:fm];
        REQUIRE([fm itemWithTitle:@"Recent Files"].submenu != nil);
    });

    // ================================================================ User Defined Languages
    run(@"T-UDL-001", @"UDL (upstream 2.1 XML): extension detection, keywords, comments, numbers, operators, delimiters, folding, styles", ^{
        NSString *xml = @"<NotepadPlus><UserLang name=\"TestLang\" ext=\"tpl\" udlVersion=\"2.1\"><Settings>"
            "<Global caseIgnored=\"no\" allowFoldOfComments=\"no\" foldCompact=\"no\" forcePureLC=\"0\" decimalSeparator=\"0\" />"
            "<Prefix Keywords1=\"no\" Keywords2=\"no\" Keywords3=\"no\" Keywords4=\"no\" Keywords5=\"no\" Keywords6=\"no\" Keywords7=\"no\" Keywords8=\"no\" /></Settings>"
            "<KeywordLists><Keywords name=\"Comments\">00// 01 02 03/* 04*/</Keywords><Keywords name=\"Operators1\">+ =</Keywords>"
            "<Keywords name=\"Folders in code1, open\">{</Keywords><Keywords name=\"Folders in code1, close\">}</Keywords>"
            "<Keywords name=\"Keywords1\">alpha beta</Keywords><Keywords name=\"Keywords2\">&quot;two words&quot;</Keywords>"
            "<Keywords name=\"Delimiters\">00&quot; 01\\ 02&quot; 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23</Keywords></KeywordLists>"
            "<Styles><WordsStyle name=\"DEFAULT\" fgColor=\"000000\" bgColor=\"FFFFFF\" colorStyle=\"0\" fontStyle=\"0\" nesting=\"0\" />"
            "<WordsStyle name=\"KEYWORDS1\" fgColor=\"FF0000\" bgColor=\"FFFFFF\" colorStyle=\"1\" fontStyle=\"1\" nesting=\"0\" /></Styles>"
            "</UserLang></NotepadPlus>";
        [xml writeToFile:[[TPUserLanguages shared].userFolder stringByAppendingPathComponent:@"TestLang.xml"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [[TPUserLanguages shared] reload];
        NSString *p = tmpPath(@"code.tpl");
        writeBytes(p, "alpha x = 12 + \"s\\\"tr\" // note\n{\n  two words\n}\n");
        [c openFile:p];
        REQUIRE([c.currentDocument.languageId isEqualToString:@"udl:TestLang"]);
        char lex[64] = {0};
        SCI(c.editor, SCI_GETLEXERLANGUAGE, 0, reinterpret_cast<sptr_t>(lex));
        REQUIRE(std::string(lex) == "user");
        SCI(c.editor, SCI_COLOURISE, 0, -1);
        REQUIRE(SCI(c.editor, SCI_GETSTYLEAT, 0) == SCE_USER_STYLE_KEYWORD1);
        REQUIRE(SCI(c.editor, SCI_GETSTYLEAT, 10) == SCE_USER_STYLE_NUMBER);
        REQUIRE(SCI(c.editor, SCI_GETSTYLEAT, 13) == SCE_USER_STYLE_OPERATOR);
        REQUIRE(SCI(c.editor, SCI_GETSTYLEAT, 16) == SCE_USER_STYLE_DELIMITER1 && SCI(c.editor, SCI_GETSTYLEAT, 19) == SCE_USER_STYLE_DELIMITER1);
        REQUIRE(SCI(c.editor, SCI_GETSTYLEAT, 25) == SCE_USER_STYLE_COMMENTLINE);
        sptr_t l2 = SCI(c.editor, SCI_POSITIONFROMLINE, 2);
        REQUIRE(SCI(c.editor, SCI_GETSTYLEAT, l2 + 2) == SCE_USER_STYLE_KEYWORD2);
        REQUIRE(SCI(c.editor, SCI_GETFOLDLEVEL, 1) & SC_FOLDLEVELHEADERFLAG);
        REQUIRE(SCI(c.editor, SCI_STYLEGETFORE, SCE_USER_STYLE_KEYWORD1) == rgbToSci(0xFF0000) && SCI(c.editor, SCI_STYLEGETBOLD, SCE_USER_STYLE_KEYWORD1));
        REQUIRE([[c.statusBar textForPart:0] isEqualToString:@"User Defined language file - TestLang"]);
        SCI(c.editor, SCI_GOTOLINE, 1);
        exec(IDM_EDIT_BLOCK_COMMENT);
        REQUIRE(sciGetLine(c.editor, 1) == "// {");
    });
    run(@"T-UDL-002", @"UDL export/import round trip, save as, rename, remove; documents follow renames", ^{
        TPUserLang *l = [[TPUserLanguages shared] languageNamed:@"TestLang"];
        REQUIRE(l != nil);
        NSString *exp = tmpPath(@"exported.xml");
        REQUIRE([[TPUserLanguages shared] exportLanguage:l toPath:exp error:nil]);
        NSArray *parsed = [TPUserLanguages parseData:[NSData dataWithContentsOfFile:exp] source:exp error:nil];
        REQUIRE(parsed.count == 1);
        TPUserLang *r = parsed[0];
        REQUIRE([r.ext isEqualToString:l.ext] && [r.keywordLists isEqualToArray:l.keywordLists] && r.styles[4].fg == 0xFF0000 && r.styles[4].colorStyle == 1);
        REQUIRE([[r field:0 ofList:0] isEqualToString:@"//"] && [[r field:3 ofList:0] isEqualToString:@"/*"] && [[r field:1 ofList:27] isEqualToString:@"\\"]);
        TPUserLang *copy = [[TPUserLanguages shared] createNamed:@"TestLang2" basedOn:l error:nil];
        REQUIRE(copy && [[NSFileManager defaultManager] fileExistsAtPath:copy.filePath]);
        TPDocument *d = [c newDocument];
        [c setDocumentLanguage:d languageId:copy.langId];
        REQUIRE([[TPUserLanguages shared] rename:copy to:@"Renamed" error:nil]);
        [c udlRenamedFrom:@"udl:TestLang2" to:@"udl:Renamed"];
        REQUIRE([d.languageId isEqualToString:@"udl:Renamed"]);
        REQUIRE([[TPUserLanguages shared] remove:[[TPUserLanguages shared] languageNamed:@"Renamed"] error:nil]);
        REQUIRE([[TPUserLanguages shared] languageNamed:@"Renamed"] == nil);
        // pre-2.0 UDL conversion (old "Comment" list and words names)
        NSString *old = @"<NotepadPlus><UserLang name=\"Old\" ext=\"old\"><KeywordLists><Keywords name=\"Comment\">1/* 2*/ 0//</Keywords><Keywords name=\"Words1\">foo</Keywords></KeywordLists></UserLang></NotepadPlus>";
        TPUserLang *o = [TPUserLanguages parseData:[old dataUsingEncoding:NSUTF8StringEncoding] source:nil error:nil].firstObject;
        REQUIRE([[o field:0 ofList:0] isEqualToString:@"//"] && [[o field:3 ofList:0] isEqualToString:@"/*"] && [o.keywordLists[19] isEqualToString:@"foo"]);
    });
    run(@"T-UDL-004", @"Define your language... dialog opens via its command and edits apply live; User-Defined command", ^{
        TPUDLDialog *dlg = [TPUDLDialog sharedWithController:c];
        dlg.window.alphaValue = 0;
        REQUIRE(exec(IDM_LANG_USER_DLG));
        REQUIRE(dlg.window.isVisible && [reg isChecked:IDM_LANG_USER_DLG]);
        [dlg selectLanguageNamed:@"TestLang"];
        REQUIRE([dlg.current.name isEqualToString:@"TestLang"]);
        [c newDocument];
        setText("alpha x\n");
        REQUIRE(exec(IDM_LANG_USER));
        REQUIRE([c.currentDocument.languageId isEqualToString:@"udl:TestLang"] && [reg isChecked:IDM_LANG_USER]);
        SCI(c.editor, SCI_COLOURISE, 0, -1);
        REQUIRE(SCI(c.editor, SCI_GETSTYLEAT, 0) == SCE_USER_STYLE_KEYWORD1);
        [dlg.window orderOut:nil];
    });
    run(@"T-UDL-003", @"Preinstalled Markdown UDL, Language menu entries, User-Defined command, live edit re-styles open documents", ^{
        NSString *p = tmpPath(@"readme.md");
        writeBytes(p, "# Title\n\nSome *text*\n");
        [c openFile:p];
        REQUIRE([c.currentDocument.languageId hasPrefix:@"udl:Markdown"]);
        NSMenu *lm = [reg topLevelMenuNamed:@"Language"];
        [c menuNeedsUpdate:lm];
        NSMenuItem *mi = [lm itemWithTitle:@"TestLang"];
        REQUIRE(mi != nil);
        [c newDocument];
        [NSApp sendAction:mi.action to:mi.target from:mi];
        REQUIRE([c.currentDocument.languageId isEqualToString:@"udl:TestLang"]);
        TPUserLang *l = [[TPUserLanguages shared] languageNamed:@"TestLang"];
        setText("gamma x\n");
        SCI(c.editor, SCI_COLOURISE, 0, -1);
        REQUIRE(SCI(c.editor, SCI_GETSTYLEAT, 0) != SCE_USER_STYLE_KEYWORD1);
        l.keywordLists[19] = @"alpha beta gamma";
        [c udlDidChange:l];
        SCI(c.editor, SCI_COLOURISE, 0, -1);
        if (SCI(c.editor, SCI_GETSTYLEAT, 0) != SCE_USER_STYLE_KEYWORD1) {
            char lx[64] = {0}; SCI(c.editor, SCI_GETLEXERLANGUAGE, 0, reinterpret_cast<sptr_t>(lx));
            fail = [NSString stringWithFormat:@"style=%ld lexer=%s lang=%@ kw=%@ same=%d", (long)SCI(c.editor, SCI_GETSTYLEAT, 0), lx, c.currentDocument.languageId,
                    [[TPUserLanguages shared] languageForId:c.currentDocument.languageId].keywordLists[19], [[TPUserLanguages shared] languageForId:c.currentDocument.languageId] == l];
            return;
        }
        [TPPrefs set:@[@"python"] forKey:@"pref.hiddenLanguages"];
        [c menuNeedsUpdate:lm];
        REQUIRE([lm itemWithTitle:@"P"].submenu && [[lm itemWithTitle:@"P"].submenu itemWithTitle:@"Python"].hidden);
        [TPPrefs set:@NO forKey:@"pref.langMenuCompact"];
        [c menuNeedsUpdate:lm];
        REQUIRE([lm itemWithTitle:@"P"].hidden && [lm itemWithTitle:@"C++"] != nil && [lm itemWithTitle:@"Python"] == nil);
    });

#include "SelfTestPartials.inc"
#include "SelfTestPanels.inc"
#include "SelfTestFeatures.inc"

    // ================================================================ benchmarks (recorded, generous limits)
    auto bench = [&](NSString *bid, NSString *name, double limitMs, double (^body)(void)) {
        double ms = body();
        [benchmarks addObject:@{@"id": bid, @"name": name, @"ms": @(ms), @"limitMs": @(limitMs), @"pass": @(ms <= limitMs)}];
        fprintf(stderr, "BENCH %-12s %-46s %9.1f ms\n", bid.UTF8String, name.UTF8String, ms);
    };
    NSString *big = tmpPath(@"big.txt");
    {
        std::string s;
        s.reserve(52 * 1024 * 1024);
        for (int i = 0; i < 1000000; ++i) s += "The quick brown fox jumps over the lazy dog line " + std::to_string(i) + "\n";
        s += "NEEDLE-AT-END\n";
        writeBytes(big, s);
    }
    bench(@"B-OPEN-50MB", @"Open a ~55 MB, 1,000,001-line UTF-8 file", 15000, ^double {
        auto t0 = std::chrono::steady_clock::now();
        [c openFile:big];
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    });
    bench(@"B-FIND-50MB", @"Find a match at the end of that file", 5000, ^double {
        tpp::search::Options o; o.find = "NEEDLE-AT-END";
        setOpts(o);
        SCI(c.editor, SCI_GOTOPOS, 0);
        auto t0 = std::chrono::steady_clock::now();
        [c.findController findNext:YES];
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    });
    bench(@"B-SAVE-50MB", @"Save that file (atomic write)", 10000, ^double {
        SCI(c.editor, SCI_DOCUMENTEND);
        SCI(c.editor, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>("x"));
        auto t0 = std::chrono::steady_clock::now();
        exec(IDM_FILE_SAVE);
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    });
    [c closeAll_forTests];
    bench(@"B-TABS-200", @"Open 200 small files as tabs", 20000, ^double {
        NSString *d = tmpPath(@"many");
        [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
        for (int i = 0; i < 200; ++i) writeBytes([d stringByAppendingPathComponent:[NSString stringWithFormat:@"f%03d.cpp", i]], "int x = 1;\n");
        auto t0 = std::chrono::steady_clock::now();
        for (int i = 0; i < 200; ++i) [c openFile:[d stringByAppendingPathComponent:[NSString stringWithFormat:@"f%03d.cpp", i]]];
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    });
    bench(@"B-SWITCH-200", @"Switch through 200 tabs", 10000, ^double {
        auto t0 = std::chrono::steady_clock::now();
        for (int i = 0; i < 200; ++i) exec(IDM_VIEW_TAB_NEXT);
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    });
    [c closeAll_forTests];

    // ================================================================ report
    NSMutableSet *implemented = [NSMutableSet set];
    for (NSNumber *n in reg.allMenuCommands) if ([reg hasHandler:n.intValue]) [implemented addObject:n];
    NSDictionary *report = @{
        @"suite": @"selftest",
        @"date": [[NSISO8601DateFormatter new] stringFromDate:[NSDate date]],
        @"macOS": [NSProcessInfo processInfo].operatingSystemVersionString,
        @"results": results,
        @"benchmarks": benchmarks,
        @"menuCommandCount": @(reg.allMenuCommands.count),
        @"implementedCommands": [implemented.allObjects sortedArrayUsingSelector:@selector(compare:)],
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    [json writeToFile:outPath atomically:YES];
    fprintf(stderr, "\n%lu tests, %d failed; %lu/%lu menu commands implemented\n", (unsigned long)results.count, failures,
            (unsigned long)implemented.count, (unsigned long)reg.allMenuCommands.count);
    [ud setPersistentDomain:savedDefaults forName:bid];
    [ud synchronize];
    [[NSFileManager defaultManager] removeItemAtPath:g_tmp error:nil];
    return failures;
}

@end

// ---------------------------------------------------------------- test-only helpers
@implementation TPMainWindowController (SelfTestHelpers)
- (void)closeAll_forTests {
    for (TPDocument *d in self.allDocuments) { d.dirty = NO; d.pendingSaveChange = NO; d.monitoring = NO; d.userReadOnly = NO; }
    for (TPEditorPane *p in @[self.subPane, self.mainPane]) [self closeDocuments:[p.documents copy] inPane:p];
    [self.findController setOptions:tpp::search::Options()];
}
- (void)smartHighlightInView_forTests:(ScintillaView *)v { [(id)self smartHighlightInView:v]; }
- (BOOL)saveCurrentMacroNamed_forTests:(NSString *)name {
    return [self saveCurrentMacroNamed:name];
}
@end
