// Textpad++ — Encoding and Language menu commands (upstream NppCommands.cpp IDM_FORMAT_*,
// IDM_LANG_*). GPL-3.0-or-later.
//
// Encoding semantics follow upstream exactly:
//  * "ANSI / UTF-8 / UTF-8-BOM / UTF-16 BE BOM / UTF-16 LE BOM" change how the buffer is
//    interpreted. Upstream keeps raw bytes in Scintilla for ANSI and UTF-8 for Unicode modes;
//    Textpad++ always keeps UTF-8, so the "in-memory bytes" are reconstructed first (see memBytes).
//    For a document opened with a legacy codepage they reload the file (after the same warnings).
//  * "Character sets > ..." reload the file from disk with that codepage (warnings first).
//  * "Convert to ..." keep the text and change the encoding used when saving (document becomes dirty).
#import "app/MainWindowController.h"
#import "app/LanguageService.h"
#import "app/Preferences.h"
#import "app/UserDefinedLanguages.h"
#import "dialogs/UDLDialog.h"
#include "core/Encoding.h"

using namespace npp;
using tpp::UniMode;

@implementation TPMainWindowController (FormatCommands)

// Bytes upstream would hold in Scintilla for this document.
- (std::string)memBytesOf:(TPDocument *)d text:(const std::string &)utf8 {
    if (!d.encoding.isCodepage() && d.encoding.mode == UniMode::Ansi) return tpp::encode(utf8, d.encoding).bytes;
    return utf8;
}

- (BOOL)confirmLoseModifications:(TPDocument *)d {
    ScintillaView *v = self.editor;
    if (d.dirty) {
        NSInteger r = [self prompt:@"Save Current Modification" informative:@"You should save the current modification.\nAll the saved modifications cannot be undone.\n\nContinue?" buttons:@[@"Yes", @"No"]];
        if (r != 0) return NO;
        if ([self saveDocument:d] != TPSaveOK) return NO;
        SCI(v, SCI_EMPTYUNDOBUFFER);
    }
    if (SCI(v, SCI_CANUNDO)) {
        NSInteger r = [self prompt:@"Lose Undo Ability Warning" informative:@"You should save the current modification.\nAll the saved modifications cannot be undone.\n\nContinue?" buttons:@[@"Yes", @"No"]];
        if (r != 0) return NO;
    }
    return YES;
}

- (void)setBufferText:(const std::string &)utf8 keepUndo:(BOOL)keepUndo {
    ScintillaView *v = self.editor;
    sptr_t caret = SCI(v, SCI_GETCURRENTPOS), first = SCI(v, SCI_GETFIRSTVISIBLELINE);
    BOOL modified = SCI(v, SCI_GETMODIFY) != 0;
    SCI(v, SCI_SETUNDOCOLLECTION, 0);
    SCI(v, SCI_CLEARALL);
    if (!utf8.empty()) SCI(v, SCI_APPENDTEXT, utf8.size(), reinterpret_cast<sptr_t>(utf8.data()));
    SCI(v, SCI_SETUNDOCOLLECTION, 1);
    if (!keepUndo) SCI(v, SCI_EMPTYUNDOBUFFER);
    if (!modified) SCI(v, SCI_SETSAVEPOINT);
    SCI(v, SCI_GOTOPOS, MIN(caret, SCI(v, SCI_GETLENGTH)));
    SCI(v, SCI_SETFIRSTVISIBLELINE, first);
}

- (void)reinterpretAs:(UniMode)um cmd:(int)cmd {
    TPDocument *d = self.currentDocument;
    if (!d) return;
    UniMode orig = d.encoding.mode;
    if (d.encoding.isCodepage()) {
        if (!d.path) {   // untitled: reinterpret in memory
            std::string bytes = tpp::encode(sciGetText(self.editor), d.encoding).bytes;
            tpp::DecodeResult dr = tpp::decodeAs(bytes, tpp::TextEncoding{um, -1});
            d.encoding = tpp::TextEncoding{um, -1};
            [self setBufferText:dr.utf8 keepUndo:NO];
            [self refreshUI];
            return;
        }
        if (![self confirmLoseModifications:d]) return;
        tpp::TextEncoding enc{um, -1};
        [self reloadDocument:d encoding:&enc];
        return;
    }
    if (orig == um) return;
    BOOL shouldBeDirty = YES;
    if (cmd == IDM_FORMAT_AS_UTF_8) shouldBeDirty = orig != UniMode::Ansi;
    if (cmd == IDM_FORMAT_ANSI) shouldBeDirty = orig != UniMode::Utf8;
    BOOL ansiInvolved = (orig == UniMode::Ansi) != (um == UniMode::Ansi);
    if (ansiInvolved) {
        std::string text = sciGetText(self.editor);
        std::string mem = [self memBytesOf:d text:text];
        std::string newText = um == UniMode::Ansi ? tpp::decodeAs(mem, tpp::TextEncoding{UniMode::Ansi, -1}).utf8 : mem;
        d.encoding = tpp::TextEncoding{um, -1};
        if (newText != text) [self setBufferText:newText keepUndo:NO];
    } else {
        d.encoding = tpp::TextEncoding{um, -1};
    }
    if (shouldBeDirty) {
        d.pendingSaveChange = YES;   // the saved bytes will change; mirror upstream Buffer::setDirty(true)
        d.dirty = YES;
    }
    [self refreshUI];
}

- (void)registerEncodingCommands:(TPCommandRegistry *)reg {
    __weak TPMainWindowController *ws = self;
    TPCommandPredicate hasDoc = ^BOOL(int c) { return ws.currentDocument != nil; };
    struct { int cmd; UniMode um; } modes[] = {
        {IDM_FORMAT_ANSI, UniMode::Ansi}, {IDM_FORMAT_AS_UTF_8, UniMode::Utf8}, {IDM_FORMAT_UTF_8, UniMode::Utf8Bom},
        {IDM_FORMAT_UTF_16BE, UniMode::Utf16BE}, {IDM_FORMAT_UTF_16LE, UniMode::Utf16LE}};
    for (auto &m : modes) {
        UniMode um = m.um;
        [reg registerCommand:m.cmd handler:^(int c) { [ws reinterpretAs:um cmd:c]; } enabled:hasDoc
                     checked:^BOOL(int c) { TPDocument *d = ws.currentDocument; return d && !d.encoding.isCodepage() && d.encoding.mode == um; }];
    }
    for (const auto &cp : tpp::codepageTable()) {
        int cmdId = IDM_FORMAT_ENCODE + cp.menuIndex;
        int codepage = cp.codepage;
        [reg registerCommand:cmdId handler:^(int c) {
            TPDocument *d = ws.currentDocument;
            tpp::TextEncoding enc{UniMode::Utf8, codepage};
            if (!d.path) {
                std::string bytes = [ws memBytesOf:d text:sciGetText(ws.editor)];
                tpp::DecodeResult dr = tpp::decodeAs(bytes, enc);
                if (!dr.ok) return;
                d.encoding = enc;
                [ws setBufferText:dr.utf8 keepUndo:NO];
                [ws refreshUI];
                return;
            }
            if (![ws confirmLoseModifications:d]) return;
            [ws reloadDocument:d encoding:&enc];
        } enabled:^BOOL(int c) { return ws.currentDocument != nil && tpp::converterAvailable(codepage); }
                     checked:^BOOL(int c) { return ws.currentDocument.encoding.codepage == codepage; }];
    }
    struct { int cmd; UniMode um; } conv[] = {
        {IDM_FORMAT_CONV2_ANSI, UniMode::Ansi}, {IDM_FORMAT_CONV2_AS_UTF_8, UniMode::Utf8}, {IDM_FORMAT_CONV2_UTF_8, UniMode::Utf8Bom},
        {IDM_FORMAT_CONV2_UTF_16BE, UniMode::Utf16BE}, {IDM_FORMAT_CONV2_UTF_16LE, UniMode::Utf16LE}};
    for (auto &m : conv) {
        UniMode um = m.um;
        [reg registerCommand:m.cmd handler:^(int c) {
            TPDocument *d = ws.currentDocument;
            if (d.encoding.isCodepage() && um == UniMode::Ansi) return;   // upstream: no-op
            if (!d.encoding.isCodepage() && d.encoding.mode == um) return;
            d.encoding = tpp::TextEncoding{um, -1};
            d.pendingSaveChange = YES;
            d.dirty = YES;
            [ws refreshUI];
        } enabled:hasDoc checked:nil];
    }
}

- (void)registerLanguageCommands:(TPCommandRegistry *)reg {
    __weak TPMainWindowController *ws = self;
    for (TPLanguage *l in [TPLanguageService shared].languages) {
        if (!l.menuCommand || [l.langId isEqualToString:@"udf"]) continue;
        NSString *lid = l.langId;
        [reg registerCommand:l.menuCommand handler:^(int c) { [ws setDocumentLanguage:ws.currentDocument languageId:lid]; }
                     enabled:^BOOL(int c) { return ws.currentDocument != nil; }
                     checked:^BOOL(int c) { return [ws.currentDocument.languageId isEqualToString:lid]; }];
    }
    [reg registerCommand:IDM_LANG_OPENUDLDIR handler:^(int c) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:[TPUserLanguages shared].userFolder]];
    }];
    [reg registerCommand:IDM_LANG_USER_DLG handler:^(int c) {
        TPUDLDialog *d = [TPUDLDialog sharedWithController:ws];
        TPUserLang *cur = [[TPUserLanguages shared] languageForId:ws.currentDocument.languageId];
        [d reloadLanguages];
        if (cur) [d selectLanguageNamed:cur.name];
        if (d.isShown) [d hideDialog];   // upstream: the menu item toggles the dialog
        else [d present];
    } enabled:nil checked:^BOOL(int c) { return [TPUDLDialog sharedWithController:ws].isShown; }];
    [reg registerCommand:IDM_LANG_USER handler:^(int c) {
        // upstream: applies the language currently selected in the UDL dialog
        TPUserLang *l = [TPUDLDialog sharedWithController:ws].current ?: [TPUserLanguages shared].languages.firstObject;
        if (l) [ws setDocumentLanguage:ws.currentDocument languageId:l.langId];
    } enabled:^BOOL(int c) { return ws.currentDocument && [TPUserLanguages shared].languages.count > 0; }
                 checked:^BOOL(int c) { return [ws.currentDocument.languageId hasPrefix:@"udl:"]; }];
}

@end

// ---------------------------------------------------------------- User Defined Languages + Language menu
@implementation TPMainWindowController (UDL)

- (void)udlDidChange:(TPUserLang *)lang {
    for (TPDocument *d in self.allDocuments) if ([d.languageId isEqualToString:lang.langId]) d.appliedLexerLanguage = nil;
    for (TPEditorPane *p in @[self.mainPane, self.subPane])
        if ([p.currentDocument.languageId isEqualToString:lang.langId]) [[TPLanguageService shared] applyLanguageOfDocument:p.currentDocument toView:p.editor];
    [self refreshUI];
}

- (void)udlRenamedFrom:(NSString *)oldId to:(NSString *)newId {
    for (TPDocument *d in self.allDocuments) if ([d.languageId isEqualToString:oldId]) [self setDocumentLanguage:d languageId:newId];
}

- (void)selectUDL:(NSMenuItem *)mi {
    if (self.currentDocument) [self setDocumentLanguage:self.currentDocument languageId:mi.representedObject];
}

// Upstream: Preferences > Language (compact menu, removed languages) + UDL names at the end.
- (void)rebuildLanguageMenu:(NSMenu *)menu {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    for (NSMenuItem *mi in [menu.itemArray copy])
        if ([mi.representedObject isKindOfClass:[NSString class]] && ([mi.representedObject hasPrefix:@"udl:"] || [mi.representedObject isEqual:@"flat"] || [mi.representedObject isEqual:@"udl-sep"]))
            [menu removeItem:mi];
    NSArray *hidden = [TPPrefs o:@"pref.hiddenLanguages"] ?: @[];
    BOOL compact = [TPPrefs b:@"pref.langMenuCompact"];
    NSInteger firstSubmenu = -1;
    for (NSInteger i = 0; i < menu.numberOfItems; ++i) {
        NSMenuItem *mi = [menu itemAtIndex:i];
        if (mi.submenu && mi.title.length == 1) {   // letter groups A..Z
            if (firstSubmenu < 0) firstSubmenu = i;
            BOOL any = NO;
            for (NSMenuItem *it in mi.submenu.itemArray) {
                TPLanguage *l = [[TPLanguageService shared] languageForMenuCommand:static_cast<int>(it.tag)];
                it.hidden = l && [hidden containsObject:l.langId];
                if (!it.hidden) any = YES;
            }
            mi.hidden = !compact || !any;
        }
    }
    if (!compact && firstSubmenu >= 0) {
        NSMutableArray *langs = [NSMutableArray array];
        for (TPLanguage *l in [TPLanguageService shared].languages)
            if (l.menuCommand && ![l.langId isEqualToString:@"normal"] && ![l.langId isEqualToString:@"udf"] && ![hidden containsObject:l.langId]) [langs addObject:l];
        [langs sortUsingComparator:^NSComparisonResult(TPLanguage *a, TPLanguage *b) {
            return [[reg labelForCommand:a.menuCommand] caseInsensitiveCompare:[reg labelForCommand:b.menuCommand]];
        }];
        NSInteger at = firstSubmenu;
        for (TPLanguage *l in langs) {
            NSMenuItem *mi = [reg makeItemForCommand:l.menuCommand];
            mi.representedObject = @"flat";
            [menu insertItem:mi atIndex:at++];
        }
    }
    NSArray *udls = [TPUserLanguages shared].languages;
    if (udls.count) {
        NSMenuItem *sep = [NSMenuItem separatorItem];
        sep.representedObject = @"udl-sep";
        [menu addItem:sep];
        for (TPUserLang *u in udls) {
            NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:u.name action:@selector(selectUDL:) keyEquivalent:@""];
            mi.target = self;
            mi.representedObject = u.langId;
            mi.state = [self.currentDocument.languageId isEqualToString:u.langId] ? NSControlStateValueOn : NSControlStateValueOff;
            [menu addItem:mi];
        }
    }
}

@end
