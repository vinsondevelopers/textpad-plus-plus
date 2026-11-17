// Textpad++ — File menu commands (upstream NppCommands.cpp IDM_FILE_* / NppIO.cpp). GPL-3.0-or-later.
#import "app/MainWindowController.h"
#import "app/Session.h"
#import "app/LanguageService.h"
#import "app/Preferences.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

using namespace npp;

static const NSInteger kRecentTag = 900000;
static NSArray<NSNumber *> *_printFFBreaks;   // set by printableTextOfCurrentDocument

static NSString *expandPrintVars(NSString *t, TPDocument *d, NSInteger page) {
    if (!t.length) return @"";
    NSDate *now = [NSDate date];
    NSDateFormatter *sd = [NSDateFormatter new]; sd.dateStyle = NSDateFormatterShortStyle; sd.timeStyle = NSDateFormatterNoStyle;
    NSDateFormatter *ld = [NSDateFormatter new]; ld.dateStyle = NSDateFormatterFullStyle; ld.timeStyle = NSDateFormatterNoStyle;
    NSDateFormatter *tm = [NSDateFormatter new]; tm.dateStyle = NSDateFormatterNoStyle; tm.timeStyle = NSDateFormatterShortStyle;
    NSDictionary *vars = @{@"$(FULL_CURRENT_PATH)": d.path ?: d.displayName, @"$(FILE_NAME)": d.displayName,
                           @"$(SHORT_DATE)": [sd stringFromDate:now], @"$(LONG_DATE)": [ld stringFromDate:now],
                           @"$(TIME)": [tm stringFromDate:now], @"$(CURRENT_PRINTING_PAGE)": [@(page) stringValue]};
    for (NSString *k in vars) t = [t stringByReplacingOccurrencesOfString:k withString:vars[k]];
    return t;
}

@interface TPPrintTextView : NSTextView
@property (nonatomic, strong) TPDocument *doc;
@property (nonatomic) CGFloat pageHeight;                       // printable height per page
@property (nonatomic, copy) NSArray<NSNumber *> *formFeedBreaks;  // character indexes where a removed FF forces a new page
@end
@implementation TPPrintTextView {
    NSMutableArray<NSValue *> *_pages;
}
// Preferences > Print > "Print formfeed as page break" (upstream Printer::doPrint): the page stops just before the
// FF and the next page starts after it. Without FF breaks AppKit's automatic pagination is used.
- (void)computePages {
    NSLayoutManager *lm = self.layoutManager;
    [lm ensureLayoutForTextContainer:self.textContainer];
    [self sizeToFit];
    const CGFloat H = _pageHeight > 20 ? _pageHeight : 700, W = self.bounds.size.width, oy = self.textContainerOrigin.y;
    NSMutableIndexSet *breaks = [NSMutableIndexSet indexSet];
    for (NSNumber *b in _formFeedBreaks) [breaks addIndex:b.unsignedIntegerValue];
    _pages = [NSMutableArray array];
    CGFloat top = 0, bottom = 0;
    auto closePage = [&](CGFloat y) { if (y > top) { [_pages addObject:[NSValue valueWithRect:NSMakeRect(0, top, W, y - top)]]; top = y; } };
    for (NSUInteger g = 0, n = lm.numberOfGlyphs; g < n;) {
        NSRange gr;
        NSRect r = [lm lineFragmentRectForGlyphAtIndex:g effectiveRange:&gr];
        NSRange cr = [lm characterRangeForGlyphRange:gr actualGlyphRange:NULL];
        r.origin.y += oy;
        BOOL before = cr.location > 0 && [breaks containsIndex:cr.location];
        BOOL after = cr.length > 1 && [breaks intersectsIndexesInRange:NSMakeRange(cr.location + 1, cr.length - 1)];
        if (before || (NSMaxY(r) - top > H && NSMinY(r) > top)) closePage(NSMinY(r));
        if (after) closePage(NSMaxY(r));
        bottom = NSMaxY(r);
        g = NSMaxRange(gr);
    }
    if (!NSIsEmptyRect(lm.extraLineFragmentRect)) bottom = MAX(bottom, NSMaxY(lm.extraLineFragmentRect) + oy);
    closePage(MAX(bottom, top + 1));
    // a trailing FF leaves nothing after it: no blank last page (upstream stops when everything is printed)
}
- (BOOL)knowsPageRange:(NSRangePointer)range {
    if (!_formFeedBreaks.count) return [super knowsPageRange:range];
    [self computePages];
    *range = NSMakeRange(1, _pages.count);
    return YES;
}
- (NSRect)rectForPage:(NSInteger)page {
    if (!_formFeedBreaks.count || page < 1 || page > (NSInteger)_pages.count) return [super rectForPage:page];
    return _pages[page - 1].rectValue;
}
- (NSAttributedString *)hf:(NSString *)prefix page:(NSInteger)page {
    NSString *l = expandPrintVars([TPPrefs s:[prefix stringByAppendingString:@"Left"]], _doc, page);
    NSString *m = expandPrintVars([TPPrefs s:[prefix stringByAppendingString:@"Middle"]], _doc, page);
    NSString *r = expandPrintVars([TPPrefs s:[prefix stringByAppendingString:@"Right"]], _doc, page);
    if (!l.length && !m.length && !r.length) return nil;
    BOOL header = [prefix hasSuffix:@"Header"];
    NSFontTraitMask traits = 0;
    if ([TPPrefs b:header ? @"pref.printHeaderBold" : @"pref.printFooterBold"]) traits |= NSBoldFontMask;
    if ([TPPrefs b:header ? @"pref.printHeaderItalic" : @"pref.printFooterItalic"]) traits |= NSItalicFontMask;
    NSFont *f = [NSFont systemFontOfSize:MAX(6, [TPPrefs i:@"pref.printHFSize"])];
    if (traits) f = [[NSFontManager sharedFontManager] convertFont:f toHaveTrait:traits];
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    CGFloat w = NSPrintOperation.currentOperation.printInfo.paperSize.width - 72;
    ps.tabStops = @[[[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentCenter location:w / 2 options:@{}],
                    [[NSTextTab alloc] initWithTextAlignment:NSTextAlignmentRight location:w options:@{}]];
    return [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\t%@\t%@", l, m, r]
                                           attributes:@{NSFontAttributeName: f, NSParagraphStyleAttributeName: ps}];
}
- (NSAttributedString *)pageHeader { return [self hf:@"pref.printHeader" page:NSPrintOperation.currentOperation.currentPage] ?: [super pageHeader]; }
- (NSAttributedString *)pageFooter { return [self hf:@"pref.printFooter" page:NSPrintOperation.currentOperation.currentPage] ?: [super pageFooter]; }
@end

@implementation TPMainWindowController (FileCommands)

- (void)registerFileCommands:(TPCommandRegistry *)reg {
    __weak TPMainWindowController *ws = self;
    TPCommandPredicate hasDoc = ^BOOL(int c) { return ws.currentDocument != nil; };
    TPCommandPredicate hasPath = ^BOOL(int c) { return ws.currentDocument.path != nil; };

    [reg registerCommand:IDM_FILE_NEW handler:^(int c) { [ws newDocument]; }];
    [reg registerCommand:IDM_FILE_OPEN handler:^(int c) { [ws openWithPanel]; }];
    [reg registerCommand:IDM_FILE_OPEN_FOLDER handler:^(int c) {
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:ws.currentDocument.path]]];
    } enabled:hasPath checked:nil];
    [reg registerCommand:IDM_FILE_OPEN_CMD handler:^(int c) {
        NSURL *term = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"com.apple.Terminal"];
        NSURL *dir = [NSURL fileURLWithPath:ws.currentDocument.path.stringByDeletingLastPathComponent];
        if (term) [[NSWorkspace sharedWorkspace] openURLs:@[dir] withApplicationAtURL:term configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];
    } enabled:hasPath checked:nil];
    [reg registerCommand:IDM_FILE_OPEN_DEFAULT_VIEWER handler:^(int c) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:ws.currentDocument.path]];
    } enabled:hasPath checked:nil];
    [reg registerCommand:IDM_FILE_RELOAD handler:^(int c) {
        TPDocument *d = ws.currentDocument;
        if (d.dirty) {
            NSInteger r = [ws prompt:@"Are you sure you want to reload the current file and lose the changes made in Textpad++?" informative:nil buttons:@[@"Yes", @"No"]];
            if (r != 0) return;
        }
        [ws reloadDocument:d encoding:nullptr];
    } enabled:hasPath checked:nil];
    [reg registerCommand:IDM_FILE_SAVE handler:^(int c) { [ws saveDocument:ws.currentDocument]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_FILE_SAVEAS handler:^(int c) { [ws saveDocumentAs:ws.currentDocument copy:NO]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_FILE_SAVECOPYAS handler:^(int c) { [ws saveDocumentAs:ws.currentDocument copy:YES]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_FILE_SAVEALL handler:^(int c) {
        if ([TPPrefs b:@"pref.saveAllConfirm"]) {
            NSInteger r = [ws prompt:@"Save All" informative:@"Are you sure you want to save all modified documents?" buttons:@[@"Yes", @"No"]];
            if (r != 0) return;
        }
        for (TPDocument *d in ws.allDocuments) if (d.dirty && [ws saveDocument:d] == TPSaveCancelled) break;
    } enabled:^BOOL(int c) { for (TPDocument *d in ws.allDocuments) if (d.dirty) return YES; return NO; } checked:nil];
    [reg registerCommand:IDM_FILE_RENAME handler:^(int c) { [ws renameCurrent]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_FILE_CLOSE handler:^(int c) { [ws closeDocument:ws.currentDocument inPane:ws.activePane]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_FILE_CLOSEALL handler:^(int c) { [ws closeAll]; }];
    [reg registerCommand:IDM_FILE_CLOSEALL_BUT_CURRENT handler:^(int c) {
        NSMutableArray *a = [ws.activePane.documents mutableCopy];
        [a removeObjectIdenticalTo:ws.currentDocument];
        [ws closeDocuments:a inPane:ws.activePane];
    } enabled:^BOOL(int c) { return ws.activePane.documents.count > 1; } checked:nil];
    [reg registerCommand:IDM_FILE_CLOSEALL_BUT_PINNED handler:^(int c) {
        for (TPEditorPane *p in @[ws.mainPane, ws.subPane]) {
            NSArray *a = [p.documents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"pinned == NO"]];
            if (![ws closeDocuments:a inPane:p]) return;
        }
    }];
    [reg registerCommand:IDM_FILE_CLOSEALL_TOLEFT handler:^(int c) {
        NSInteger i = [ws.activePane indexOfDocument:ws.currentDocument];
        [ws closeDocuments:[ws.activePane.documents subarrayWithRange:NSMakeRange(0, i)] inPane:ws.activePane];
    } enabled:^BOOL(int c) { return [ws.activePane indexOfDocument:ws.currentDocument] > 0; } checked:nil];
    [reg registerCommand:IDM_FILE_CLOSEALL_TORIGHT handler:^(int c) {
        NSInteger i = [ws.activePane indexOfDocument:ws.currentDocument];
        NSArray *docs = ws.activePane.documents;
        [ws closeDocuments:[docs subarrayWithRange:NSMakeRange(i + 1, docs.count - i - 1)] inPane:ws.activePane];
    } enabled:^BOOL(int c) { return [ws.activePane indexOfDocument:ws.currentDocument] < (NSInteger)ws.activePane.documents.count - 1; } checked:nil];
    [reg registerCommand:IDM_FILE_CLOSEALL_UNCHANGED handler:^(int c) {
        for (TPEditorPane *p in @[ws.mainPane, ws.subPane])
            [ws closeDocuments:[p.documents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"dirty == NO"]] inPane:p];
    }];
    [reg registerCommand:IDM_FILE_DELETE handler:^(int c) {
        TPDocument *d = ws.currentDocument;
        NSInteger r = [ws prompt:[NSString stringWithFormat:@"Are you sure you want to move \"%@\" to the Trash?", d.path] informative:nil buttons:@[@"Yes", @"No"]];
        if (r != 0) return;
        NSError *err = nil;
        if (![[NSFileManager defaultManager] trashItemAtURL:[NSURL fileURLWithPath:d.path] resultingItemURL:nil error:&err]) {
            [ws showMessage:@"Cannot move the file to the Trash." informative:err.localizedDescription];
            return;
        }
        d.dirty = NO;
        for (TPEditorPane *p in @[ws.mainPane, ws.subPane]) if ([p indexOfDocument:d] != NSNotFound) [ws closeDocument:d inPane:p];
    } enabled:hasPath checked:nil];
    [reg registerCommand:IDM_FILE_LOADSESSION handler:^(int c) {
        NSOpenPanel *op = [NSOpenPanel openPanel];
        op.allowedContentTypes = @[UTTypeXML, UTTypeData];
        if ([op runModal] != NSModalResponseOK) return;
        // Preferences > Multi-Instance: "Open session in a new instance (and save session on exit)"
        if ([TPPrefs i:@"pref.multiInstance"] == 1) { [ws launchNewInstanceWithArguments:@[@"-multiInst", @"-openSession", op.URL.path]]; return; }
        if (![[TPSession shared] loadSessionFromPath:op.URL.path controller:ws])
            [ws showMessage:@"Cannot load the session file." informative:op.URL.path];
    }];
    [reg registerCommand:IDM_FILE_SAVESESSION handler:^(int c) {
        NSSavePanel *sp = [NSSavePanel savePanel];
        NSString *ext = [TPPrefs s:@"pref.sessionFileExt"];
        sp.nameFieldStringValue = ext.length ? [@"session." stringByAppendingString:[ext stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"."]]] : @"session.xml";
        if ([sp runModal] == NSModalResponseOK) [[TPSession shared] saveSessionToPath:sp.URL.path controller:ws includeBackups:NO];
    }];
    [reg registerCommand:IDM_FILE_PRINT handler:^(int c) { [ws printCurrent:YES]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_FILE_PRINTNOW handler:^(int c) { [ws printCurrent:NO]; } enabled:hasDoc checked:nil];
    [reg registerCommand:IDM_FILE_EXIT handler:^(int c) { [NSApp terminate:nil]; }];
    [reg registerCommand:IDM_FILE_RESTORELASTCLOSEDFILE handler:^(int c) {
        NSString *p = ws.closedFiles.lastObject;
        if (!p) return;
        [ws.closedFiles removeLastObject];
        [ws openFile:p];
    } enabled:^BOOL(int c) { return ws.closedFiles.count > 0; } checked:nil];
    [reg registerCommand:IDM_OPEN_ALL_RECENT_FILE handler:^(int c) {
        for (NSString *p in [ws.recentFiles copy]) [ws openFile:p activate:YES error:nil];
    } enabled:^BOOL(int c) { return ws.recentFiles.count > 0; } checked:nil];
    [reg registerCommand:IDM_CLEAN_RECENT_FILE_LIST handler:^(int c) {
        [ws.recentFiles removeAllObjects];
        [[NSUserDefaults standardUserDefaults] setObject:@[] forKey:@"RecentFiles"];
    } enabled:^BOOL(int c) { return ws.recentFiles.count > 0; } checked:nil];
}

- (void)openWithPanel {
    NSOpenPanel *op = [NSOpenPanel openPanel];
    op.allowsMultipleSelection = YES;
    op.canChooseDirectories = NO;
    op.showsHiddenFiles = YES;
    NSURL *dir = [self defaultDirectoryURL];
    if (dir) op.directoryURL = dir;
    if ([op runModal] != NSModalResponseOK) return;
    [self rememberDirectory:op.URLs.firstObject.path.stringByDeletingLastPathComponent];
    for (NSURL *u in op.URLs) [self openFile:u.path];
}

- (void)closeAll {
    // upstream closes the sub view first, then the main view
    if (![self closeDocuments:self.subPane.documents inPane:self.subPane]) return;
    [self closeDocuments:self.mainPane.documents inPane:self.mainPane];
}

- (void)renameCurrent {
    TPDocument *d = self.currentDocument;
    if (d.isUntitled) {
        NSAlert *a = [NSAlert new];
        a.messageText = @"Rename Current Document";
        a.informativeText = @"New name:";
        NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
        tf.stringValue = d.untitledName;
        a.accessoryView = tf;
        [a addButtonWithTitle:@"OK"];
        [a addButtonWithTitle:@"Cancel"];
        if ([a runModal] != NSAlertFirstButtonReturn) return;
        NSString *name = [tf.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (!name.length) return;
        d.untitledName = name;
        TPLanguage *l = [[TPLanguageService shared] languageForFileName:name];
        if ([d.languageId isEqualToString:@"normal"] && ![l.langId isEqualToString:@"normal"]) [self setDocumentLanguage:d languageId:l.langId];
        [self refreshUI];
        return;
    }
    NSSavePanel *sp = [NSSavePanel savePanel];
    sp.title = @"Rename";
    sp.directoryURL = [NSURL fileURLWithPath:d.path.stringByDeletingLastPathComponent];
    sp.nameFieldStringValue = d.path.lastPathComponent;
    if ([sp runModal] != NSModalResponseOK) return;
    NSString *dest = sp.URL.path;
    if ([dest isEqualToString:d.path]) return;
    NSError *err = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:dest]) {
        [self showMessage:@"Cannot rename: a file with this name already exists." informative:dest];
        return;
    }
    if (![[NSFileManager defaultManager] moveItemAtPath:d.path toPath:dest error:&err]) {
        [self showMessage:@"Cannot rename the file." informative:err.localizedDescription];
        return;
    }
    d.path = dest;
    TPLanguage *l = [[TPLanguageService shared] languageForFileName:dest.lastPathComponent];
    [self setDocumentLanguage:d languageId:l.langId];
    [self addRecentFile:dest];
    [self refreshUI];
}

// Printing (Preferences > Print): WYSIWYG / invert / black-on-white / no background, optional line
// numbers, margins in mm and header/footer with upstream variables.
- (NSMutableAttributedString *)printableTextOfCurrentDocument {
    ScintillaView *v = self.editor;
    std::string text = sciGetText(v);
    NSInteger colorMode = [TPPrefs i:@"pref.printColorMode"];   // 0 WYSIWYG, 1 invert, 2 black on white, 3 no background
    BOOL lineNumbers = [TPPrefs b:@"pref.printLineNumbers"];
    NSMutableAttributedString *as = [NSMutableAttributedString new];
    sptr_t len = static_cast<sptr_t>(text.size());
    NSMutableDictionary<NSNumber *, NSDictionary *> *attrCache = [NSMutableDictionary dictionary];
    auto sciColor = [](sptr_t c) { return [NSColor colorWithSRGBRed:(c & 0xFF) / 255.0 green:((c >> 8) & 0xFF) / 255.0 blue:((c >> 16) & 0xFF) / 255.0 alpha:1]; };
    auto attrsFor = [&](int style) -> NSDictionary * {
        NSDictionary *a = attrCache[@(style)];
        if (a) return a;
        char fontName[256] = {0};
        SCI(v, SCI_STYLEGETFONT, style, reinterpret_cast<sptr_t>(fontName));
        double size = SCI(v, SCI_STYLEGETSIZEFRACTIONAL, style) / static_cast<double>(SC_FONT_SIZE_MULTIPLIER);
        NSFont *f = [NSFont fontWithName:@(fontName) size:size * 0.75] ?: [NSFont userFixedPitchFontOfSize:size * 0.75];
        NSFontTraitMask traits = 0;
        if (SCI(v, SCI_STYLEGETBOLD, style)) traits |= NSBoldFontMask;
        if (SCI(v, SCI_STYLEGETITALIC, style)) traits |= NSItalicFontMask;
        if (traits) f = [[NSFontManager sharedFontManager] convertFont:f toHaveTrait:traits];
        NSColor *fg = sciColor(SCI(v, SCI_STYLEGETFORE, style)), *bg = sciColor(SCI(v, SCI_STYLEGETBACK, style));
        NSMutableDictionary *d = [@{NSFontAttributeName: f} mutableCopy];
        if (colorMode == 1) {   // invert
            NSColor *s = [fg colorUsingColorSpace:NSColorSpace.sRGBColorSpace], *b = [bg colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            d[NSForegroundColorAttributeName] = [NSColor colorWithSRGBRed:1 - s.redComponent green:1 - s.greenComponent blue:1 - s.blueComponent alpha:1];
            d[NSBackgroundColorAttributeName] = [NSColor colorWithSRGBRed:1 - b.redComponent green:1 - b.greenComponent blue:1 - b.blueComponent alpha:1];
        } else if (colorMode == 2) {
            d[NSForegroundColorAttributeName] = NSColor.blackColor;
        } else {
            d[NSForegroundColorAttributeName] = fg;
            if (colorMode == 0 && ![bg isEqual:sciColor(SCI(v, SCI_STYLEGETBACK, STYLE_DEFAULT))]) d[NSBackgroundColorAttributeName] = bg;
        }
        a = d;
        attrCache[@(style)] = a;
        return a;
    };
    SCI(v, SCI_COLOURISE, 0, -1);
    sptr_t lines = SCI(v, SCI_GETLINECOUNT);
    int digits = static_cast<int>(std::to_string(static_cast<long long>(lines)).size());
    NSDictionary *lnAttrs = @{NSFontAttributeName: [NSFont userFixedPitchFontOfSize:8], NSForegroundColorAttributeName: NSColor.grayColor};
    sptr_t i = 0, line = 0;
    if (lineNumbers && len >= 0) [as appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%*ld  ", digits, (long)1] attributes:lnAttrs]];
    while (i < len) {
        int style = static_cast<int>(SCI(v, SCI_GETSTYLEINDEXAT, i));
        sptr_t j = i + 1;
        while (j < len && SCI(v, SCI_GETSTYLEINDEXAT, j) == style && text[j - 1] != '\n') ++j;
        NSString *chunk = NSStr(text.substr(static_cast<size_t>(i), static_cast<size_t>(j - i)));
        [as appendAttributedString:[[NSAttributedString alloc] initWithString:chunk attributes:attrsFor(style)]];
        if (lineNumbers && text[j - 1] == '\n' && j < len) {
            ++line;
            [as appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%*ld  ", digits, (long)line + 1] attributes:lnAttrs]];
        }
        i = j;
    }
    // Form feeds: page breaks (Preferences > Print) or shown as an inverted "FF" blob like Scintilla draws them
    BOOL ffBreak = [TPPrefs b:@"pref.printFormfeed"];
    NSMutableArray<NSNumber *> *ffBreaks = [NSMutableArray array];
    for (NSUInteger k = 0;;) {
        NSRange r = [as.mutableString rangeOfString:@"\f" options:NSLiteralSearch range:NSMakeRange(k, as.length - k)];
        if (r.location == NSNotFound) break;
        if (ffBreak) {
            [as deleteCharactersInRange:r];
            [ffBreaks addObject:@(r.location)];
            k = r.location;
        } else {
            NSMutableDictionary *a = [[as attributesAtIndex:r.location effectiveRange:NULL] mutableCopy];
            a[NSForegroundColorAttributeName] = NSColor.whiteColor;
            a[NSBackgroundColorAttributeName] = NSColor.blackColor;
            [as replaceCharactersInRange:r withAttributedString:[[NSAttributedString alloc] initWithString:@"FF" attributes:a]];
            k = r.location + 2;
        }
    }
    _printFFBreaks = ffBreaks;
    return as;
}

- (NSPrintInfo *)printInfoFromPreferences {
    NSPrintInfo *pi = [[NSPrintInfo sharedPrintInfo] copy];
    pi.horizontalPagination = NSPrintingPaginationModeFit;
    pi.verticallyCentered = NO;
    const CGFloat mm = 72.0 / 25.4;
    if ([TPPrefs i:@"pref.printMarginTop"] > 0) pi.topMargin = [TPPrefs i:@"pref.printMarginTop"] * mm;
    if ([TPPrefs i:@"pref.printMarginLeft"] > 0) pi.leftMargin = [TPPrefs i:@"pref.printMarginLeft"] * mm;
    if ([TPPrefs i:@"pref.printMarginRight"] > 0) pi.rightMargin = [TPPrefs i:@"pref.printMarginRight"] * mm;
    if ([TPPrefs i:@"pref.printMarginBottom"] > 0) pi.bottomMargin = [TPPrefs i:@"pref.printMarginBottom"] * mm;
    BOOL hf = NO;
    for (NSString *k in @[@"pref.printHeaderLeft", @"pref.printHeaderMiddle", @"pref.printHeaderRight", @"pref.printFooterLeft", @"pref.printFooterMiddle", @"pref.printFooterRight"])
        if ([TPPrefs s:k].length) hf = YES;
    pi.dictionary[NSPrintHeaderAndFooter] = @(hf);
    return pi;
}

- (NSView *)printViewWithInfo:(NSPrintInfo *)pi {
    NSAttributedString *as = [self printableTextOfCurrentDocument];
    TPPrintTextView *tv = [[TPPrintTextView alloc] initWithFrame:NSMakeRect(0, 0, pi.paperSize.width - pi.leftMargin - pi.rightMargin, 100)];
    tv.verticallyResizable = YES;
    tv.maxSize = NSMakeSize(tv.frame.size.width, CGFLOAT_MAX);
    tv.doc = self.currentDocument;
    if ([TPPrefs i:@"pref.printColorMode"] == 1) tv.backgroundColor = NSColor.blackColor;
    [tv.textStorage setAttributedString:as];
    tv.formFeedBreaks = _printFFBreaks;
    tv.pageHeight = pi.paperSize.height - pi.topMargin - pi.bottomMargin;
    return tv;
}

- (void)printCurrent:(BOOL)withDialog {
    NSPrintInfo *pi = [self printInfoFromPreferences];
    NSView *tv = [self printViewWithInfo:pi];
    NSPrintOperation *op = [NSPrintOperation printOperationWithView:tv printInfo:pi];
    op.jobTitle = self.currentDocument.displayName;
    op.showsPrintPanel = withDialog;
    op.showsProgressPanel = withDialog;
    if (self.selfTestMode) {   // tests never reach a real printer: the job is saved as a PDF instead
        pi.jobDisposition = NSPrintSaveJob;
        pi.dictionary[NSPrintJobSavingURL] = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"textpad-test-print.pdf"]];
        op.showsPrintPanel = NO;
        op.showsProgressPanel = NO;
    }
    [op runOperation];
}

// ---------------------------------------------------------------- dynamic menus
- (void)menuNeedsUpdate:(NSMenu *)menu {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    if (menu == [reg topLevelMenuNamed:@"File"]) {
        for (NSMenuItem *mi in [menu.itemArray copy]) if (mi.tag >= kRecentTag && mi.tag < kRecentTag + 1000) [menu removeItem:mi];
        for (NSMenuItem *mi in [menu.itemArray copy]) if ([mi.representedObject isEqual:@"recent-extra"]) [menu removeItem:mi];
        NSInteger exitIdx = [menu indexOfItemWithTag:IDM_FILE_EXIT];
        if (exitIdx < 0) return;
        NSMutableArray *items = [NSMutableArray array];
        if (self.recentFiles.count) {
            NSMenuItem *sep = [NSMenuItem separatorItem];
            sep.representedObject = @"recent-extra";
            [items addObject:sep];
            NSInteger n = 1;
            NSMutableArray *recentItems = [NSMutableArray array];
            NSInteger max = [TPPrefs i:@"RecentFilesMax"];
            for (NSString *p in self.recentFiles) {
                if (n > max) break;
                NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%ld: %@", (long)n, [TPMainWindowController recentLabelForPath:p]] action:@selector(openRecent:) keyEquivalent:@""];
                mi.target = self;
                mi.tag = kRecentTag + n;
                mi.representedObject = p;
                mi.toolTip = p;
                [recentItems addObject:mi];
                ++n;
            }
            if ([TPPrefs b:@"pref.recentInSubmenu"] && recentItems.count) {
                NSMenuItem *sub = [[NSMenuItem alloc] initWithTitle:@"Recent Files" action:nil keyEquivalent:@""];
                sub.representedObject = @"recent-extra";
                NSMenu *sm = [[NSMenu alloc] initWithTitle:@"Recent Files"];
                for (NSMenuItem *mi in recentItems) [sm addItem:mi];
                sub.submenu = sm;
                [items addObject:sub];
            } else {
                [items addObjectsFromArray:recentItems];
            }
        }
        NSMenuItem *sep2 = [NSMenuItem separatorItem];
        sep2.representedObject = @"recent-extra";
        [items addObject:sep2];
        for (NSNumber *cmd in @[@(IDM_FILE_RESTORELASTCLOSEDFILE), @(IDM_OPEN_ALL_RECENT_FILE), @(IDM_CLEAN_RECENT_FILE_LIST)]) {
            NSMenuItem *mi = [reg makeItemForCommand:cmd.intValue];
            if (cmd.intValue == IDM_FILE_RESTORELASTCLOSEDFILE) mi.title = @"Restore Recent Closed File";
            if (cmd.intValue == IDM_OPEN_ALL_RECENT_FILE) mi.title = @"Open All Recent Files";
            if (cmd.intValue == IDM_CLEAN_RECENT_FILE_LIST) mi.title = @"Empty Recent Files List";
            TPKeyBinding *kb = [reg primaryBindingForCommand:cmd.intValue];
            if (kb) { mi.keyEquivalent = kb.keyEquivalent; mi.keyEquivalentModifierMask = kb.modifiers; }
            mi.representedObject = @"recent-extra";
            [items addObject:mi];
        }
        NSMenuItem *sep3 = [NSMenuItem separatorItem];
        sep3.representedObject = @"recent-extra";
        [items addObject:sep3];
        // insert before the separator that precedes Exit
        NSInteger at = [menu indexOfItemWithTag:IDM_FILE_EXIT];
        if (at > 0 && [menu itemAtIndex:at - 1].isSeparatorItem) at -= 1;
        for (NSMenuItem *mi in items) [menu insertItem:mi atIndex:at++];
    } else if (menu == [reg topLevelMenuNamed:@"Window"]) {
        [self updateWindowMenu:menu];
    } else if (menu == [reg topLevelMenuNamed:@"Macro"]) {
        [self updateMacroMenu:menu];
    } else if (menu == [reg topLevelMenuNamed:@"Run"]) {
        [self updateRunMenu:menu];
    } else if (menu == [reg topLevelMenuNamed:@"Language"]) {
        [self rebuildLanguageMenu:menu];
    }
}

- (void)openRecent:(NSMenuItem *)mi {
    NSString *p = mi.representedObject;
    if (![[NSFileManager defaultManager] fileExistsAtPath:p]) {
        NSInteger r = [self prompt:[NSString stringWithFormat:@"\"%@\" doesn't exist anymore.", p] informative:@"Remove it from the recent files list?" buttons:@[@"Yes", @"No"]];
        if (r == 0) { [self.recentFiles removeObject:p]; [[NSUserDefaults standardUserDefaults] setObject:self.recentFiles forKey:@"RecentFiles"]; }
        return;
    }
    [self openFile:p];
}

@end
