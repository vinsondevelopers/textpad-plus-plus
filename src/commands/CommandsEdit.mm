// Textpad++ — Edit menu commands (upstream NppCommands.cpp IDM_EDIT_*, IDM_FORMAT_TO*).
// GPL-3.0-or-later.
#import "app/MainWindowController.h"
#import "app/LanguageService.h"
#import "app/Preferences.h"
#import "app/AutoCompletion.h"
#include "core/TextOps.h"
#include <random>

using namespace npp;
namespace to = tpp::textops;

static NSString *const kBinaryPasteboardType = @"com.textpadplusplus.binary";

// Begin/End Select state (upstream keeps it per view)
static sptr_t g_beginSelectPos[2] = {-1, -1};
static BOOL g_beginSelectColumn[2] = {NO, NO};

@implementation TPMainWindowController (EditCommands)

- (BOOL)editable { return self.currentDocument && !self.currentDocument.userReadOnly && !self.currentDocument.monitoring; }

- (void)registerEditCommands:(TPCommandRegistry *)reg {
    __weak TPMainWindowController *ws = self;
    TPCommandPredicate editable = ^BOOL(int c) { return [ws editable]; };
    TPCommandPredicate hasSel = ^BOOL(int c) { return ws.currentDocument && SCI(ws.editor, SCI_GETSELECTIONEMPTY) == 0; };
    TPCommandPredicate editableSel = ^BOOL(int c) { return [ws editable] && SCI(ws.editor, SCI_GETSELECTIONEMPTY) == 0; };

    [reg registerCommand:IDM_EDIT_UNDO handler:^(int c) { SCI(ws.editor, SCI_UNDO); } enabled:^BOOL(int c) { return SCI(ws.editor, SCI_CANUNDO) != 0; } checked:nil];
    [reg registerCommand:IDM_EDIT_REDO handler:^(int c) { SCI(ws.editor, SCI_REDO); } enabled:^BOOL(int c) { return SCI(ws.editor, SCI_CANREDO) != 0; } checked:nil];
    [reg registerCommand:IDM_EDIT_CUT handler:^(int c) { [ws cutOrCopy:YES]; } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_COPY handler:^(int c) { [ws cutOrCopy:NO]; } enabled:^BOOL(int c) { return ws.currentDocument != nil; } checked:nil];
    [reg registerCommand:IDM_EDIT_PASTE handler:^(int c) { SCI(ws.editor, SCI_PASTE); } enabled:^BOOL(int c) { return [ws editable] && SCI(ws.editor, SCI_CANPASTE) != 0; } checked:nil];
    [reg registerCommand:IDM_EDIT_DELETE handler:^(int c) { SCI(ws.editor, SCI_CLEAR); } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_SELECTALL handler:^(int c) { SCI(ws.editor, SCI_SELECTALL); }];
    [reg registerCommand:IDM_EDIT_BEGINENDSELECT handler:^(int c) { [ws beginEndSelect:NO]; } enabled:nil checked:^BOOL(int c) { return g_beginSelectPos[ws.activePane.viewIndex] >= 0 && !g_beginSelectColumn[ws.activePane.viewIndex]; }];
    [reg registerCommand:IDM_EDIT_BEGINENDSELECT_COLUMNMODE handler:^(int c) { [ws beginEndSelect:YES]; } enabled:nil checked:^BOOL(int c) { return g_beginSelectPos[ws.activePane.viewIndex] >= 0 && g_beginSelectColumn[ws.activePane.viewIndex]; }];

    // Insert date/time (upstream: TIME + " " + DATE in user locale, short/long)
    [reg registerCommandsFrom:IDM_EDIT_INSERT_DATETIME_SHORT to:IDM_EDIT_INSERT_DATETIME_SHORT handler:^(int c) { [ws insertDateTime:c]; } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_INSERT_DATETIME_LONG handler:^(int c) { [ws insertDateTime:c]; } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_INSERT_DATETIME_CUSTOMIZED handler:^(int c) { [ws insertDateTime:c]; } enabled:editable checked:nil];

    // Copy to clipboard
    TPCommandPredicate hasPath = ^BOOL(int c) { return ws.currentDocument != nil; };
    [reg registerCommand:IDM_EDIT_FULLPATHTOCLIP handler:^(int c) { [ws copyString:ws.currentDocument.path ?: ws.currentDocument.displayName]; } enabled:hasPath checked:nil];
    [reg registerCommand:IDM_EDIT_FILENAMETOCLIP handler:^(int c) { [ws copyString:ws.currentDocument.displayName]; } enabled:hasPath checked:nil];
    [reg registerCommand:IDM_EDIT_CURRENTDIRTOCLIP handler:^(int c) { [ws copyString:ws.currentDocument.path.stringByDeletingLastPathComponent ?: @""]; } enabled:^BOOL(int c) { return ws.currentDocument.path != nil; } checked:nil];
    [reg registerCommand:IDM_EDIT_COPY_ALL_NAMES handler:^(int c) {
        NSMutableArray *a = [NSMutableArray array];
        for (TPDocument *d in ws.allDocuments) [a addObject:d.displayName];
        [ws copyString:[a componentsJoinedByString:@"\n"]];
    }];
    [reg registerCommand:IDM_EDIT_COPY_ALL_PATHS handler:^(int c) {
        NSMutableArray *a = [NSMutableArray array];
        for (TPDocument *d in ws.allDocuments) [a addObject:d.path ?: d.displayName];
        [ws copyString:[a componentsJoinedByString:@"\n"]];
    }];

    // Indent
    [reg registerCommand:IDM_EDIT_INS_TAB handler:^(int c) { SCI(ws.editor, SCI_TAB); } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_RMV_TAB handler:^(int c) { SCI(ws.editor, SCI_BACKTAB); } enabled:editable checked:nil];

    // Convert case
    struct { int cmd; to::Case k; } cases[] = {
        {IDM_EDIT_UPPERCASE, to::Case::Upper}, {IDM_EDIT_LOWERCASE, to::Case::Lower},
        {IDM_EDIT_PROPERCASE_FORCE, to::Case::ProperForce}, {IDM_EDIT_PROPERCASE_BLEND, to::Case::ProperBlend},
        {IDM_EDIT_SENTENCECASE_FORCE, to::Case::SentenceForce}, {IDM_EDIT_SENTENCECASE_BLEND, to::Case::SentenceBlend},
        {IDM_EDIT_INVERTCASE, to::Case::Invert}, {IDM_EDIT_RANDOMCASE, to::Case::Random}};
    for (auto &cs : cases) {
        to::Case k = cs.k;
        [reg registerCommand:cs.cmd handler:^(int c) { [ws convertCase:k]; } enabled:editableSel checked:nil];
    }

    // Line operations
    [reg registerCommand:IDM_EDIT_DUP_LINE handler:^(int c) { SCI(ws.editor, SCI_LINEDUPLICATE); } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_REMOVE_ANY_DUP_LINES handler:^(int c) { [ws transformLines:^(std::vector<std::string> &l) { to::removeDuplicateLines(l); }]; } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_REMOVE_CONSECUTIVE_DUP_LINES handler:^(int c) { [ws transformLines:^(std::vector<std::string> &l) { to::removeConsecutiveDuplicateLines(l); }]; } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_SPLIT_LINES handler:^(int c) { [ws splitLines]; } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_JOIN_LINES handler:^(int c) { [ws joinLines]; } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_LINE_UP handler:^(int c) { SCI(ws.editor, SCI_MOVESELECTEDLINESUP); } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_LINE_DOWN handler:^(int c) { SCI(ws.editor, SCI_MOVESELECTEDLINESDOWN); } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_REMOVEEMPTYLINES handler:^(int c) { [ws transformLines:^(std::vector<std::string> &l) { to::removeEmptyLines(l, false); }]; } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_REMOVEEMPTYLINESWITHBLANK handler:^(int c) { [ws transformLines:^(std::vector<std::string> &l) { to::removeEmptyLines(l, true); }]; } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_BLANKLINEABOVECURRENT handler:^(int c) { [ws insertBlankLine:YES]; } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_BLANKLINEBELOWCURRENT handler:^(int c) { [ws insertBlankLine:NO]; } enabled:editable checked:nil];
    struct { int cmd; to::SortMode m; bool desc; } sorts[] = {
        {IDM_EDIT_SORTLINES_REVERSE_ORDER, to::SortMode::Reverse, false},
        {IDM_EDIT_SORTLINES_RANDOMLY, to::SortMode::Random, false},
        {IDM_EDIT_SORTLINES_LEXICOGRAPHIC_ASCENDING, to::SortMode::Lexicographic, false},
        {IDM_EDIT_SORTLINES_LEXICO_CASE_INSENS_ASCENDING, to::SortMode::LexicographicIgnoreCase, false},
        {IDM_EDIT_SORTLINES_LOCALE_ASCENDING, to::SortMode::Locale, false},
        {IDM_EDIT_SORTLINES_INTEGER_ASCENDING, to::SortMode::Integer, false},
        {IDM_EDIT_SORTLINES_DECIMALCOMMA_ASCENDING, to::SortMode::DecimalComma, false},
        {IDM_EDIT_SORTLINES_DECIMALDOT_ASCENDING, to::SortMode::DecimalDot, false},
        {IDM_EDIT_SORTLINES_LENGTH_ASCENDING, to::SortMode::Length, false},
        {IDM_EDIT_SORTLINES_LEXICOGRAPHIC_DESCENDING, to::SortMode::Lexicographic, true},
        {IDM_EDIT_SORTLINES_LEXICO_CASE_INSENS_DESCENDING, to::SortMode::LexicographicIgnoreCase, true},
        {IDM_EDIT_SORTLINES_LOCALE_DESCENDING, to::SortMode::Locale, true},
        {IDM_EDIT_SORTLINES_INTEGER_DESCENDING, to::SortMode::Integer, true},
        {IDM_EDIT_SORTLINES_DECIMALCOMMA_DESCENDING, to::SortMode::DecimalComma, true},
        {IDM_EDIT_SORTLINES_DECIMALDOT_DESCENDING, to::SortMode::DecimalDot, true},
        {IDM_EDIT_SORTLINES_LENGTH_DESCENDING, to::SortMode::Length, true}};
    for (auto &s : sorts) {
        to::SortMode m = s.m;
        bool desc = s.desc;
        [reg registerCommand:s.cmd handler:^(int c) { [ws sortLines:m descending:desc]; } enabled:editable checked:nil];
    }

    // Comment / uncomment
    TPCommandPredicate hasLineComment = ^BOOL(int c) { return [ws editable] && [[TPLanguageService shared] languageForId:ws.currentDocument.languageId].commentLine.length > 0; };
    TPCommandPredicate hasStreamComment = ^BOOL(int c) { TPLanguage *l = [[TPLanguageService shared] languageForId:ws.currentDocument.languageId]; return [ws editable] && l.commentStart.length && l.commentEnd.length; };
    [reg registerCommand:IDM_EDIT_BLOCK_COMMENT handler:^(int c) { [ws lineComment:0]; } enabled:hasLineComment checked:nil];
    [reg registerCommand:IDM_EDIT_BLOCK_COMMENT_SET handler:^(int c) { [ws lineComment:1]; } enabled:hasLineComment checked:nil];
    [reg registerCommand:IDM_EDIT_BLOCK_UNCOMMENT handler:^(int c) { [ws lineComment:2]; } enabled:hasLineComment checked:nil];
    [reg registerCommand:IDM_EDIT_STREAM_COMMENT handler:^(int c) { [ws streamComment:YES]; } enabled:hasStreamComment checked:nil];
    [reg registerCommand:IDM_EDIT_STREAM_UNCOMMENT handler:^(int c) { [ws streamComment:NO]; } enabled:hasStreamComment checked:nil];

    // Auto-completion
    // Auto-Completion (upstream NppCommands: showApiComplete / showWordComplete(true) / showFunctionComplete /
    // showFunctionNextHint / showPathCompletion), driven by the autoCompletion/<language>.xml API files
    [reg registerCommand:IDM_EDIT_AUTOCOMPLETE_CURRENTFILE handler:^(int c) { [[ws autoCompletionForEditor] showWordComplete:YES]; } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_AUTOCOMPLETE handler:^(int c) { [[ws autoCompletionForEditor] showApiComplete]; } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_AUTOCOMPLETE_PATH handler:^(int c) { [[ws autoCompletionForEditor] showPathCompletion]; } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_FUNCCALLTIP handler:^(int c) { [[ws autoCompletionForEditor] showFunctionComplete]; } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_FUNCCALLTIP_PREVIOUS handler:^(int c) { [[ws autoCompletionForEditor] showPreviousOverload]; } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_FUNCCALLTIP_NEXT handler:^(int c) { [[ws autoCompletionForEditor] showNextOverload]; } enabled:editable checked:nil];

    // EOL conversion
    struct { int cmd; int eol; } eols[] = {{IDM_FORMAT_TODOS, SC_EOL_CRLF}, {IDM_FORMAT_TOUNIX, SC_EOL_LF}, {IDM_FORMAT_TOMAC, SC_EOL_CR}};
    for (auto &e : eols) {
        int eol = e.eol;
        [reg registerCommand:e.cmd handler:^(int c) {
            SCI(ws.editor, SCI_CONVERTEOLS, eol);
            SCI(ws.editor, SCI_SETEOLMODE, eol);
            ws.currentDocument.eolMode = eol;
            [ws refreshUI];
        } enabled:editable checked:^BOOL(int c) { return ws.currentDocument && SCI(ws.editor, SCI_GETEOLMODE) == eol; }];
    }

    // Blank operations
    [reg registerCommand:IDM_EDIT_TRIMTRAILING handler:^(int c) { [ws mapLines:^std::string(const std::string &l) { return to::trimTrailing(l); }]; } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_TRIMLINEHEAD handler:^(int c) { [ws mapLines:^std::string(const std::string &l) { return to::trimLeading(l); }]; } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_TRIM_BOTH handler:^(int c) { [ws mapLines:^std::string(const std::string &l) { return to::trimLeading(to::trimTrailing(l)); }]; } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_EOL2WS handler:^(int c) { [ws eolToSpace:NO]; } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_TRIMALL handler:^(int c) { [ws eolToSpace:YES]; } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_TAB2SW handler:^(int c) {
        int tw = static_cast<int>(SCI(ws.editor, SCI_GETTABWIDTH));
        [ws mapLines:^std::string(const std::string &l) { return to::tabsToSpaces(l, tw); }];
    } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_SW2TAB_ALL handler:^(int c) {
        int tw = static_cast<int>(SCI(ws.editor, SCI_GETTABWIDTH));
        [ws mapLines:^std::string(const std::string &l) { return to::spacesToTabs(l, tw, false); }];
    } enabled:editable checked:nil];
    [reg registerCommand:IDM_EDIT_SW2TAB_LEADING handler:^(int c) {
        int tw = static_cast<int>(SCI(ws.editor, SCI_GETTABWIDTH));
        [ws mapLines:^std::string(const std::string &l) { return to::spacesToTabs(l, tw, true); }];
    } enabled:editable checked:nil];

    // Paste special
    [reg registerCommand:IDM_EDIT_PASTE_AS_HTML handler:^(int c) { [ws pasteType:NSPasteboardTypeHTML]; } enabled:^BOOL(int c) { return [ws editable] && [[NSPasteboard generalPasteboard] dataForType:NSPasteboardTypeHTML] != nil; } checked:nil];
    [reg registerCommand:IDM_EDIT_PASTE_AS_RTF handler:^(int c) { [ws pasteType:NSPasteboardTypeRTF]; } enabled:^BOOL(int c) { return [ws editable] && [[NSPasteboard generalPasteboard] dataForType:NSPasteboardTypeRTF] != nil; } checked:nil];
    [reg registerCommand:IDM_EDIT_COPY_BINARY handler:^(int c) { [ws copyBinary:NO]; } enabled:hasSel checked:nil];
    [reg registerCommand:IDM_EDIT_CUT_BINARY handler:^(int c) { [ws copyBinary:YES]; } enabled:editableSel checked:nil];
    [reg registerCommand:IDM_EDIT_PASTE_BINARY handler:^(int c) { [ws pasteBinary]; } enabled:^BOOL(int c) {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        return [ws editable] && ([pb dataForType:kBinaryPasteboardType] || [pb stringForType:NSPasteboardTypeString]);
    } checked:nil];

    // On selection
    [reg registerCommand:IDM_EDIT_OPENSELECTEDFILETOEDIT handler:^(int c) { [ws openSelectedPath:NO]; } enabled:hasSel checked:nil];
    [reg registerCommand:IDM_EDIT_OPENSELECTEDFILEFOLDERINEXPLORER handler:^(int c) { [ws openSelectedPath:YES]; } enabled:hasSel checked:nil];
    [reg registerCommand:IDM_EDIT_REDACT_SELECTION handler:^(int c) { [ws redactSelection]; } enabled:editableSel checked:nil];
    [reg registerCommand:IDM_EDIT_SEARCHONINTERNET handler:^(int c) {
        NSString *q = NSStr(sciSelectedText(ws.editor));
        NSArray *engines = @[@"https://duckduckgo.com/?q=$(CURRENT_WORD)", @"https://www.google.com/search?q=$(CURRENT_WORD)",
                             @"https://search.yahoo.com/search?q=$(CURRENT_WORD)", @"https://stackoverflow.com/search?q=$(CURRENT_WORD)"];
        NSInteger choice = [TPPrefs i:@"pref.searchEngine"];
        NSString *engine = choice >= 0 && choice < (NSInteger)engines.count ? engines[choice] : [TPPrefs s:@"pref.searchEngineCustom"];
        if (![engine containsString:@"$(CURRENT_WORD)"]) engine = [engine stringByAppendingString:@"$(CURRENT_WORD)"];
        NSMutableCharacterSet *allowed = [NSCharacterSet.URLQueryAllowedCharacterSet mutableCopy];
        [allowed removeCharactersInString:@"&+=?#"];
        NSString *enc = [q stringByAddingPercentEncodingWithAllowedCharacters:allowed];
        NSURL *u = [NSURL URLWithString:[engine stringByReplacingOccurrencesOfString:@"$(CURRENT_WORD)" withString:enc ?: @""]];
        if (u) [[NSWorkspace sharedWorkspace] openURL:u];
    } enabled:hasSel checked:nil];
    // upstream: command(IDM_SETTING_PREFERENCE) + _preference.showDialogByName(L"SearchEngine")
    [reg registerCommand:IDM_EDIT_CHANGESEARCHENGINE handler:^(int c) { [[TPPreferencesWindow shared] showPage:@"Search Engine"]; }];

    // Multi-select (Scintilla uses the target search flags for these)
    struct { int cmd; int flags; bool all; } multi[] = {
        {IDM_EDIT_MULTISELECTALL, SCFIND_WHOLEWORD, true}, {IDM_EDIT_MULTISELECTALLMATCHCASE, SCFIND_MATCHCASE, true},
        {IDM_EDIT_MULTISELECTALLWHOLEWORD, SCFIND_WHOLEWORD, true}, {IDM_EDIT_MULTISELECTALLMATCHCASEWHOLEWORD, SCFIND_MATCHCASE | SCFIND_WHOLEWORD, true},
        {IDM_EDIT_MULTISELECTNEXT, SCFIND_WHOLEWORD, false}, {IDM_EDIT_MULTISELECTNEXTMATCHCASE, SCFIND_MATCHCASE, false},
        {IDM_EDIT_MULTISELECTNEXTWHOLEWORD, SCFIND_WHOLEWORD, false}, {IDM_EDIT_MULTISELECTNEXTMATCHCASEWHOLEWORD, SCFIND_MATCHCASE | SCFIND_WHOLEWORD, false}};
    for (auto &m : multi) {
        int flags = m.flags;
        bool all = m.all;
        [reg registerCommand:m.cmd handler:^(int c) {
            ScintillaView *v = ws.editor;
            if (SCI(v, SCI_GETSELECTIONEMPTY)) {
                sptr_t pos = SCI(v, SCI_GETCURRENTPOS);
                SCI(v, SCI_SETSEL, SCI(v, SCI_WORDSTARTPOSITION, pos, 1), SCI(v, SCI_WORDENDPOSITION, pos, 1));
                if (SCI(v, SCI_GETSELECTIONEMPTY)) return;
                if (!all) return;
            }
            SCI(v, SCI_TARGETWHOLEDOCUMENT);
            SCI(v, SCI_SETSEARCHFLAGS, flags);
            SCI(v, all ? SCI_MULTIPLESELECTADDEACH : SCI_MULTIPLESELECTADDNEXT);
            SCI(v, SCI_SCROLLCARET);
        }];
    }
    [reg registerCommand:IDM_EDIT_MULTISELECTUNDO handler:^(int c) {
        ScintillaView *v = ws.editor;
        sptr_t n = SCI(v, SCI_GETSELECTIONS);
        if (n > 1) SCI(v, SCI_DROPSELECTIONN, SCI(v, SCI_GETMAINSELECTION));
    } enabled:^BOOL(int c) { return SCI(ws.editor, SCI_GETSELECTIONS) > 1; } checked:nil];
    [reg registerCommand:IDM_EDIT_MULTISELECTSSKIP handler:^(int c) {
        ScintillaView *v = ws.editor;
        sptr_t main = SCI(v, SCI_GETMAINSELECTION);
        SCI(v, SCI_TARGETWHOLEDOCUMENT);
        SCI(v, SCI_SETSEARCHFLAGS, SCFIND_MATCHCASE);
        SCI(v, SCI_MULTIPLESELECTADDNEXT);
        if (SCI(v, SCI_GETSELECTIONS) > 1) SCI(v, SCI_DROPSELECTIONN, main);
        SCI(v, SCI_SCROLLCARET);
    } enabled:^BOOL(int c) { return SCI(ws.editor, SCI_GETSELECTIONEMPTY) == 0; } checked:nil];

    [reg registerCommand:IDM_EDIT_COLUMNMODETIP handler:^(int c) {
        [ws showMessage:@"Column Mode"
            informative:@"Column (rectangular) selection:\n• Option + mouse drag\n• Option + Shift + arrow keys\n\nMultiple carets: Command + click (when multi-editing is enabled).\n\nUse Edit > Column Editor… to insert text or numbers in every selected line."];
    }];
    [reg registerCommand:IDM_EDIT_COLUMNMODE handler:^(int c) { [ws columnEditor]; } enabled:editable checked:nil];

    // Read-only
    [reg registerCommand:IDM_EDIT_TOGGLEREADONLY handler:^(int c) {
        TPDocument *d = ws.currentDocument;
        d.userReadOnly = !d.userReadOnly;
        SCI(ws.editor, SCI_SETREADONLY, d.userReadOnly || d.monitoring);
        [ws refreshUI];
    } enabled:^BOOL(int c) { return ws.currentDocument != nil && !ws.savingForbidden; } checked:^BOOL(int c) { return ws.currentDocument.userReadOnly; }];
    [reg registerCommand:IDM_EDIT_SETREADONLYFORALLDOCS handler:^(int c) {
        for (TPDocument *d in ws.allDocuments) d.userReadOnly = YES;
        for (TPEditorPane *p in @[ws.mainPane, ws.subPane]) if (p.currentDocument) SCI(p.editor, SCI_SETREADONLY, 1);
        [ws refreshUI];
    }];
    [reg registerCommand:IDM_EDIT_CLEARREADONLYFORALLDOCS handler:^(int c) {
        for (TPDocument *d in ws.allDocuments) d.userReadOnly = NO;
        for (TPEditorPane *p in @[ws.mainPane, ws.subPane]) if (p.currentDocument) SCI(p.editor, SCI_SETREADONLY, p.currentDocument.monitoring);
        [ws refreshUI];
    } enabled:^BOOL(int c) { return !ws.savingForbidden; } checked:nil];
    [reg registerCommand:IDM_EDIT_TOGGLESYSTEMREADONLY handler:^(int c) {
        TPDocument *d = ws.currentDocument;
        NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:d.path error:nil];
        NSUInteger perm = [a filePosixPermissions];
        NSUInteger np = (perm & 0200) ? (perm & ~0222u) : (perm | 0200);
        NSError *err = nil;
        if (![[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(np)} ofItemAtPath:d.path error:&err])
            [ws showMessage:@"Cannot change the file attribute." informative:err.localizedDescription];
        d.diskReadOnly = !(np & 0200);
        [ws refreshUI];
    } enabled:^BOOL(int c) { return ws.currentDocument.path != nil; } checked:^BOOL(int c) { return ws.currentDocument.diskReadOnly; }];
}

// ---------------------------------------------------------------- helpers
- (void)copyString:(NSString *)s {
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:s ?: @"" forType:NSPasteboardTypeString];
}

- (void)cutOrCopy:(BOOL)cut {
    ScintillaView *v = self.editor;
    // upstream: with no selection, Copy/Cut act on the whole current line (SCI_COPYALLOWLINE / SCI_CUTALLOWLINE)
    if (SCI(v, SCI_GETSELECTIONEMPTY)) {
        if (![TPPrefs b:@"pref.copyCutLine"]) return;   // Preferences > Editing 1 > Copy/Cut Line without selection
        SCI(v, cut ? SCI_LINECUT : SCI_COPYALLOWLINE);
    } else SCI(v, cut ? SCI_CUT : SCI_COPY);
}

- (void)beginEndSelect:(BOOL)column {
    ScintillaView *v = self.editor;
    int vi = self.activePane.viewIndex;
    if (g_beginSelectPos[vi] < 0) {
        g_beginSelectPos[vi] = SCI(v, SCI_GETCURRENTPOS);
        g_beginSelectColumn[vi] = column;
    } else {
        sptr_t start = g_beginSelectPos[vi], end = SCI(v, SCI_GETCURRENTPOS);
        if (g_beginSelectColumn[vi]) {
            SCI(v, SCI_SETSELECTIONMODE, SC_SEL_RECTANGLE);
            SCI(v, SCI_SETRECTANGULARSELECTIONANCHOR, start);
            SCI(v, SCI_SETRECTANGULARSELECTIONCARET, end);
        } else {
            SCI(v, SCI_SETSEL, start, end);
        }
        g_beginSelectPos[vi] = -1;
    }
}

- (void)insertDateTime:(int)cmd {
    NSDate *now = [NSDate date];
    NSString *s;
    if (cmd == IDM_EDIT_INSERT_DATETIME_CUSTOMIZED) {
        NSDateFormatter *f = [NSDateFormatter new];
        f.dateFormat = [[NSUserDefaults standardUserDefaults] stringForKey:@"DateTimeCustomFormat"] ?: @"yyyy-MM-dd HH:mm:ss";
        s = [f stringFromDate:now];
    } else {
        NSDateFormatter *t = [NSDateFormatter new]; t.timeStyle = NSDateFormatterShortStyle; t.dateStyle = NSDateFormatterNoStyle;
        NSDateFormatter *d = [NSDateFormatter new]; d.timeStyle = NSDateFormatterNoStyle;
        d.dateStyle = cmd == IDM_EDIT_INSERT_DATETIME_SHORT ? NSDateFormatterShortStyle : NSDateFormatterFullStyle;
        BOOL reverse = [[NSUserDefaults standardUserDefaults] boolForKey:@"DateTimeReverseOrder"];
        s = reverse ? [NSString stringWithFormat:@"%@ %@", [d stringFromDate:now], [t stringFromDate:now]]
                    : [NSString stringWithFormat:@"%@ %@", [t stringFromDate:now], [d stringFromDate:now]];
    }
    SCI(self.editor, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>(s.UTF8String));
}

- (void)convertCase:(to::Case)k {
    ScintillaView *v = self.editor;
    sptr_t n = SCI(v, SCI_GETSELECTIONS);
    SCI(v, SCI_BEGINUNDOACTION);
    for (sptr_t i = 0; i < n; ++i) {
        sptr_t s = SCI(v, SCI_GETSELECTIONNSTART, i), e = SCI(v, SCI_GETSELECTIONNEND, i);
        if (s >= e) continue;
        std::string in = sciGetRange(v, s, e);
        std::string out = to::changeCase(in, k);
        if (in == out) continue;
        sptr_t anchor = SCI(v, SCI_GETSELECTIONNANCHOR, i), caret = SCI(v, SCI_GETSELECTIONNCARET, i);
        sciReplaceRange(v, s, e, out);
        sptr_t delta = static_cast<sptr_t>(out.size()) - (e - s);
        // keep each selection covering its converted text
        if (anchor <= caret) { SCI(v, SCI_SETSELECTIONNANCHOR, i, s); SCI(v, SCI_SETSELECTIONNCARET, i, e + delta); }
        else { SCI(v, SCI_SETSELECTIONNANCHOR, i, e + delta); SCI(v, SCI_SETSELECTIONNCARET, i, s); }
    }
    SCI(v, SCI_ENDUNDOACTION);
}

- (void)transformLines:(void (^)(std::vector<std::string> &lines))fn {
    sptr_t from, to;
    BOOL whole;
    [self getLineRangeForLineOperation:&from to:&to wholeDocument:&whole];
    std::vector<std::string> lines;
    for (sptr_t l = from; l <= to; ++l) lines.push_back(sciGetLine(self.editor, l));
    fn(lines);
    [self replaceLinesFrom:from to:to withLines:lines];
}

- (void)mapLines:(std::string (^)(const std::string &line))fn {
    [self transformLines:^(std::vector<std::string> &lines) { for (auto &l : lines) l = fn(l); }];
}

- (void)sortLines:(to::SortMode)mode descending:(bool)desc {
    ScintillaView *v = self.editor;
    size_t fromCol = 0, toCol = 0;
    sptr_t from, to;
    BOOL whole;
    if (SCI(v, SCI_GETSELECTIONMODE) == SC_SEL_RECTANGLE || SCI(v, SCI_GETSELECTIONMODE) == SC_SEL_THIN) {
        // column-mode sort key (upstream: columns of the rectangular selection)
        sptr_t a = SCI(v, SCI_GETRECTANGULARSELECTIONANCHOR), c = SCI(v, SCI_GETRECTANGULARSELECTIONCARET);
        sptr_t ca = SCI(v, SCI_GETCOLUMN, a) + SCI(v, SCI_GETRECTANGULARSELECTIONANCHORVIRTUALSPACE);
        sptr_t cc = SCI(v, SCI_GETCOLUMN, c) + SCI(v, SCI_GETRECTANGULARSELECTIONCARETVIRTUALSPACE);
        fromCol = static_cast<size_t>(MIN(ca, cc));
        toCol = static_cast<size_t>(MAX(ca, cc));
        from = MIN(SCI(v, SCI_LINEFROMPOSITION, a), SCI(v, SCI_LINEFROMPOSITION, c));
        to = MAX(SCI(v, SCI_LINEFROMPOSITION, a), SCI(v, SCI_LINEFROMPOSITION, c));
        if (fromCol == toCol) toCol = 0;
    } else {
        [self getLineRangeForLineOperation:&from to:&to wholeDocument:&whole];
    }
    std::vector<std::string> lines;
    for (sptr_t l = from; l <= to; ++l) lines.push_back(sciGetLine(v, l));
    to::SortResult r = to::sortLines(lines, mode, desc, fromCol, toCol);
    if (!r.ok) {
        [self showMessage:@"Sorting Error" informative:[NSString stringWithFormat:@"Unable to perform numeric sorting due to line %ld.", (long)(from + r.failedLineIndex + 1)]];
        return;
    }
    [self replaceLinesFrom:from to:to withLines:lines];
}

- (void)insertBlankLine:(BOOL)above {
    ScintillaView *v = self.editor;
    sptr_t line = SCI(v, SCI_LINEFROMPOSITION, SCI(v, SCI_GETCURRENTPOS));
    std::string eol = sciEolString(v);
    SCI(v, SCI_BEGINUNDOACTION);
    if (above) {
        sptr_t p = SCI(v, SCI_POSITIONFROMLINE, line);
        SCI(v, SCI_INSERTTEXT, p, reinterpret_cast<sptr_t>(eol.c_str()));
        SCI(v, SCI_GOTOPOS, p);
    } else {
        sptr_t p = SCI(v, SCI_GETLINEENDPOSITION, line);
        SCI(v, SCI_INSERTTEXT, p, reinterpret_cast<sptr_t>(eol.c_str()));
        SCI(v, SCI_GOTOPOS, SCI(v, SCI_POSITIONFROMLINE, line + 1));
    }
    SCI(v, SCI_ENDUNDOACTION);
}

- (void)splitLines {
    ScintillaView *v = self.editor;
    sptr_t from, to;
    BOOL whole;
    [self getLineRangeForLineOperation:&from to:&to wholeDocument:&whole];
    if (whole) { from = to = SCI(v, SCI_LINEFROMPOSITION, SCI(v, SCI_GETCURRENTPOS)); }
    SCI(v, SCI_SETSELECTION, SCI(v, SCI_GETLINEENDPOSITION, to), SCI(v, SCI_POSITIONFROMLINE, from));
    SCI(v, SCI_TARGETFROMSELECTION);
    sptr_t width = 0;
    if (SCI(v, SCI_GETEDGEMODE) != EDGE_NONE) width = SCI(v, SCI_TEXTWIDTH, STYLE_DEFAULT, reinterpret_cast<sptr_t>("P")) * SCI(v, SCI_GETEDGECOLUMN);
    SCI(v, SCI_BEGINUNDOACTION);
    SCI(v, SCI_LINESSPLIT, width);
    SCI(v, SCI_ENDUNDOACTION);
}

- (void)joinLines {
    ScintillaView *v = self.editor;
    sptr_t s = SCI(v, SCI_GETSELECTIONSTART), e = SCI(v, SCI_GETSELECTIONEND);
    sptr_t l1 = SCI(v, SCI_LINEFROMPOSITION, s), l2 = SCI(v, SCI_LINEFROMPOSITION, e);
    if (l1 == l2) {
        // upstream: without a multi-line selection, join the current line with the next one
        if (l1 + 1 >= SCI(v, SCI_GETLINECOUNT)) return;
        l2 = l1 + 1;
    }
    SCI(v, SCI_SETSELECTION, SCI(v, SCI_GETLINEENDPOSITION, l2), SCI(v, SCI_POSITIONFROMLINE, l1));
    SCI(v, SCI_TARGETFROMSELECTION);
    SCI(v, SCI_BEGINUNDOACTION);
    SCI(v, SCI_LINESJOIN);
    SCI(v, SCI_ENDUNDOACTION);
}

- (void)eolToSpace:(BOOL)trimToo {
    ScintillaView *v = self.editor;
    sptr_t from, to;
    BOOL whole;
    [self getLineRangeForLineOperation:&from to:&to wholeDocument:&whole];
    std::vector<std::string> lines;
    for (sptr_t l = from; l <= to; ++l) {
        std::string line = sciGetLine(v, l);
        if (trimToo) line = to::trimLeading(to::trimTrailing(line));
        lines.push_back(line);
    }
    std::string joined;
    for (size_t i = 0; i < lines.size(); ++i) {
        if (trimToo && lines[i].empty()) continue;
        if (!joined.empty()) joined += " ";
        joined += lines[i];
    }
    [self replaceLinesFrom:from to:to withLines:{joined}];
}

- (void)lineComment:(int)mode {   // 0 toggle, 1 comment, 2 uncomment
    ScintillaView *v = self.editor;
    TPLanguage *lang = [[TPLanguageService shared] languageForId:self.currentDocument.languageId];
    std::string token = StdStr(lang.commentLine);
    std::string tokenSp = token + " ";
    sptr_t s = SCI(v, SCI_GETSELECTIONSTART), e = SCI(v, SCI_GETSELECTIONEND);
    sptr_t l1 = SCI(v, SCI_LINEFROMPOSITION, s), l2 = SCI(v, SCI_LINEFROMPOSITION, e);
    if (l2 > l1 && e == SCI(v, SCI_POSITIONFROMLINE, l2)) --l2;
    SCI(v, SCI_BEGINUNDOACTION);
    for (sptr_t l = l1; l <= l2; ++l) {
        sptr_t ind = SCI(v, SCI_GETLINEINDENTPOSITION, l);
        sptr_t end = SCI(v, SCI_GETLINEENDPOSITION, l);
        std::string rest = sciGetRange(v, ind, end);
        bool commented = rest.compare(0, token.size(), token) == 0;
        if (rest.empty()) continue;
        if ((mode == 0 && commented) || mode == 2) {
            if (!commented) continue;
            sptr_t len = static_cast<sptr_t>(rest.compare(0, tokenSp.size(), tokenSp) == 0 ? tokenSp.size() : token.size());
            sciReplaceRange(v, ind, ind + len, "");
        } else {
            sciReplaceRange(v, ind, ind, tokenSp);
        }
    }
    SCI(v, SCI_ENDUNDOACTION);
}

- (void)streamComment:(BOOL)add {
    ScintillaView *v = self.editor;
    TPLanguage *lang = [[TPLanguageService shared] languageForId:self.currentDocument.languageId];
    std::string cs = StdStr(lang.commentStart), ce = StdStr(lang.commentEnd);
    sptr_t s = SCI(v, SCI_GETSELECTIONSTART), e = SCI(v, SCI_GETSELECTIONEND);
    if (s == e) {
        sptr_t line = SCI(v, SCI_LINEFROMPOSITION, s);
        s = SCI(v, SCI_GETLINEINDENTPOSITION, line);
        e = SCI(v, SCI_GETLINEENDPOSITION, line);
    }
    std::string text = sciGetRange(v, s, e);
    SCI(v, SCI_BEGINUNDOACTION);
    if (add) {
        std::string out = cs + " " + text + " " + ce;
        sciReplaceRange(v, s, e, out);
        SCI(v, SCI_SETSEL, s, s + out.size());
    } else {
        std::string t = text;
        size_t a = t.find_first_not_of(" \t\r\n");
        size_t b = t.find_last_not_of(" \t\r\n");
        if (a != std::string::npos && t.compare(a, cs.size(), cs) == 0 && b != std::string::npos && b + 1 >= ce.size() &&
            t.compare(b + 1 - ce.size(), ce.size(), ce) == 0 && b + 1 - ce.size() >= a + cs.size()) {
            std::string inner = t.substr(a + cs.size(), b + 1 - ce.size() - (a + cs.size()));
            if (!inner.empty() && inner.front() == ' ') inner.erase(0, 1);
            if (!inner.empty() && inner.back() == ' ') inner.pop_back();
            std::string out = t.substr(0, a) + inner + t.substr(b + 1);
            sciReplaceRange(v, s, e, out);
            SCI(v, SCI_SETSEL, s, s + out.size());
        }
    }
    SCI(v, SCI_ENDUNDOACTION);
}

- (TPAutoCompletion *)autoCompletionForEditor {
    TPAutoCompletion *ac = [TPAutoCompletion forView:self.editor];
    [ac setLanguageId:self.currentDocument.languageId ?: @"normal"];
    return ac;
}

- (void)pasteType:(NSPasteboardType)type {
    NSData *d = [[NSPasteboard generalPasteboard] dataForType:type];
    if (!d) return;
    std::string raw(static_cast<const char *>(d.bytes), d.length);
    SCI(self.editor, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>(raw.c_str()));
}

- (void)copyBinary:(BOOL)cut {
    ScintillaView *v = self.editor;
    std::string sel = sciSelectedText(v);
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb declareTypes:@[kBinaryPasteboardType, NSPasteboardTypeString] owner:nil];
    [pb setData:[NSData dataWithBytes:sel.data() length:sel.size()] forType:kBinaryPasteboardType];
    [pb setString:NSStr(sel) forType:NSPasteboardTypeString];
    if (cut) SCI(v, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>(""));
}

- (void)pasteBinary {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSData *d = [pb dataForType:kBinaryPasteboardType];
    std::string raw = d ? std::string(static_cast<const char *>(d.bytes), d.length) : StdStr([pb stringForType:NSPasteboardTypeString]);
    ScintillaView *v = self.editor;
    // SCI_REPLACESEL stops at NUL; replace the selection with the exact byte count instead
    sptr_t s = SCI(v, SCI_GETSELECTIONSTART), e = SCI(v, SCI_GETSELECTIONEND);
    SCI(v, SCI_BEGINUNDOACTION);
    sciReplaceRange(v, s, e, raw);
    SCI(v, SCI_ENDUNDOACTION);
    SCI(v, SCI_GOTOPOS, s + raw.size());
}

- (void)openSelectedPath:(BOOL)folder {
    NSString *p = [NSStr(sciSelectedText(self.editor)) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    p = p.stringByExpandingTildeInPath;
    if (![p hasPrefix:@"/"] && self.currentDocument.path) p = [self.currentDocument.path.stringByDeletingLastPathComponent stringByAppendingPathComponent:p];
    if (![[NSFileManager defaultManager] fileExistsAtPath:p]) { [self showMessage:@"The selected path doesn't exist." informative:p]; return; }
    if (folder) [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:p]]];
    else [self openFile:p];
}

- (void)redactSelection {
    ScintillaView *v = self.editor;
    BOOL shift = (NSEvent.modifierFlags & NSEventModifierFlagShift) != 0;
    NSString *mark = shift ? @"●" : @"█";
    sptr_t n = SCI(v, SCI_GETSELECTIONS);
    SCI(v, SCI_BEGINUNDOACTION);
    for (sptr_t i = 0; i < n; ++i) {
        sptr_t s = SCI(v, SCI_GETSELECTIONNSTART, i), e = SCI(v, SCI_GETSELECTIONNEND, i);
        std::string in = sciGetRange(v, s, e);
        // one mark per character, keeping line breaks
        NSString *ns = NSStr(in);
        NSMutableString *r = [NSMutableString string];
        [ns enumerateSubstringsInRange:NSMakeRange(0, ns.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *sub, NSRange a, NSRange b, BOOL *stop) {
            if ([sub isEqualToString:@"\r"] || [sub isEqualToString:@"\n"] || [sub isEqualToString:@"\r\n"]) [r appendString:sub];
            else [r appendString:mark];
        }];
        sciReplaceRange(v, s, e, StdStr(r));
    }
    SCI(v, SCI_ENDUNDOACTION);
}

// Column Editor (upstream ColumnEditorDlg): insert text or a number sequence at the caret column
// of every line in the selection (or from the caret line to the end of the document).
- (void)columnEditor {
    NSAlert *a = [NSAlert new];
    a.messageText = @"Column / Multi-Selection Editor";
    NSView *acc = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 170)];
    NSButton *textRadio = [NSButton radioButtonWithTitle:@"Text to Insert" target:nil action:nil];
    textRadio.frame = NSMakeRect(0, 146, 200, 20); textRadio.state = NSControlStateValueOn;
    NSTextField *text = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 120, 330, 22)];
    NSButton *numRadio = [NSButton radioButtonWithTitle:@"Number to Insert" target:nil action:nil];
    numRadio.frame = NSMakeRect(0, 94, 200, 20);
    textRadio.action = numRadio.action = @selector(self);
    NSArray *labels = @[@"Initial number :", @"Increase by :", @"Repeat :"];
    NSMutableArray<NSTextField *> *fields = [NSMutableArray array];
    for (NSUInteger i = 0; i < 3; ++i) {
        NSTextField *l = [NSTextField labelWithString:labels[i]];
        l.frame = NSMakeRect(20, 68 - i * 26, 110, 20);
        NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(130, 66 - i * 26, 80, 22)];
        f.stringValue = i == 1 ? @"1" : (i == 2 ? @"1" : @"1");
        [acc addSubview:l];
        [acc addSubview:f];
        [fields addObject:f];
    }
    NSPopUpButton *format = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(220, 64, 130, 26)];
    [format addItemsWithTitles:@[@"Dec", @"Hex", @"Oct", @"Bin"]];
    NSPopUpButton *lead = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(220, 38, 130, 26)];
    [lead addItemsWithTitles:@[@"Leading: None", @"Leading: Zeros", @"Leading: Spaces"]];
    for (NSView *x in @[textRadio, text, numRadio, format, lead]) [acc addSubview:x];
    a.accessoryView = acc;
    [a addButtonWithTitle:@"OK"];
    [a addButtonWithTitle:@"Cancel"];
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    ScintillaView *v = self.editor;
    sptr_t s = SCI(v, SCI_GETSELECTIONSTART), e = SCI(v, SCI_GETSELECTIONEND);
    sptr_t l1 = SCI(v, SCI_LINEFROMPOSITION, s), l2 = SCI(v, SCI_LINEFROMPOSITION, e);
    sptr_t col = SCI(v, SCI_GETCOLUMN, s);
    if (SCI(v, SCI_GETSELECTIONMODE) == SC_SEL_RECTANGLE || SCI(v, SCI_GETSELECTIONMODE) == SC_SEL_THIN) {
        sptr_t ra = SCI(v, SCI_GETRECTANGULARSELECTIONANCHOR), rc = SCI(v, SCI_GETRECTANGULARSELECTIONCARET);
        l1 = MIN(SCI(v, SCI_LINEFROMPOSITION, ra), SCI(v, SCI_LINEFROMPOSITION, rc));
        l2 = MAX(SCI(v, SCI_LINEFROMPOSITION, ra), SCI(v, SCI_LINEFROMPOSITION, rc));
        col = MIN(SCI(v, SCI_GETCOLUMN, ra), SCI(v, SCI_GETCOLUMN, rc));
    } else if (l1 == l2) {
        l2 = SCI(v, SCI_GETLINECOUNT) - 1;   // upstream: from caret line to end of document
    }
    BOOL numbers = numRadio.state == NSControlStateValueOn;
    long long initial = fields[0].stringValue.longLongValue, inc = fields[1].stringValue.longLongValue;
    long long repeat = MAX(1LL, fields[2].stringValue.longLongValue);
    int base = format.indexOfSelectedItem == 1 ? 16 : format.indexOfSelectedItem == 2 ? 8 : format.indexOfSelectedItem == 3 ? 2 : 10;
    auto fmt = [&](long long val) {
        std::string out;
        bool neg = val < 0;
        unsigned long long u = static_cast<unsigned long long>(neg ? -val : val);
        do { int d = static_cast<int>(u % base); out.insert(out.begin(), static_cast<char>(d < 10 ? '0' + d : 'A' + d - 10)); u /= base; } while (u);
        if (neg) out.insert(out.begin(), '-');
        return out;
    };
    size_t width = 0;
    if (numbers) {
        long long last = initial + inc * ((l2 - l1) / repeat);
        width = MAX(fmt(initial).size(), fmt(last).size());
    }
    SCI(v, SCI_BEGINUNDOACTION);
    for (sptr_t l = l1; l <= l2; ++l) {
        std::string ins;
        if (numbers) {
            ins = fmt(initial + inc * ((l - l1) / repeat));
            if (lead.indexOfSelectedItem == 1 && ins.size() < width) ins.insert(0, width - ins.size(), '0');
            if (lead.indexOfSelectedItem == 2 && ins.size() < width) ins.insert(0, width - ins.size(), ' ');
        } else {
            ins = StdStr(text.stringValue);
        }
        sptr_t lineEndCol = SCI(v, SCI_GETCOLUMN, SCI(v, SCI_GETLINEENDPOSITION, l));
        sptr_t pos;
        if (lineEndCol < col) {   // pad short lines with spaces (upstream behaviour)
            pos = SCI(v, SCI_GETLINEENDPOSITION, l);
            ins = std::string(static_cast<size_t>(col - lineEndCol), ' ') + ins;
        } else {
            pos = SCI(v, SCI_FINDCOLUMN, l, col);
        }
        SCI(v, SCI_INSERTTEXT, pos, reinterpret_cast<sptr_t>(ins.c_str()));
    }
    SCI(v, SCI_ENDUNDOACTION);
}

@end
