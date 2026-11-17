// Textpad++ — self-tests for the features beyond the Windows editor (included by SelfTest.mm). GPL-3.0-or-later.

    run(@"T-ESC-001", @"Escape closes pop-ups and dialogs: Cancel / Close / OK / the only button; tool windows close; the editor window keeps Escape", ^{
        NSAlert *a = [NSAlert new];
        [a addButtonWithTitle:@"Save"];
        [a addButtonWithTitle:@"Don't Save"];
        [a addButtonWithTitle:@"Cancel"];
        [a layout];
        NSButton *esc1 = TPEscapeButtonInWindow(a.window);
        REQUIRE([esc1.title isEqualToString:@"Cancel"]);
        NSAlert *b = [NSAlert new];
        [b addButtonWithTitle:@"OK"];
        [b addButtonWithTitle:@"Copy debug info into clipboard"];
        [b layout];
        NSButton *esc2 = TPEscapeButtonInWindow(b.window);
        REQUIRE([esc2.title isEqualToString:@"OK"]);
        NSAlert *one = [NSAlert new];
        [one addButtonWithTitle:@"Got it"];
        [one layout];
        NSButton *esc3 = TPEscapeButtonInWindow(one.window);
        REQUIRE([esc3.title isEqualToString:@"Got it"]);
        NSPanel *tool = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:YES];
        tool.releasedWhenClosed = NO;
        tool.alphaValue = 0;
        [tool orderFront:nil];
        REQUIRE(TPHandleEscapeInWindow(tool, c.window) && !tool.isVisible);
        REQUIRE(!TPHandleEscapeInWindow(c.window, c.window));   // the editor's own Escape (auto-completion, multi-selection...)
    });

    run(@"T-MD-001", @"Opening a Markdown file asks: Live Preview or text only; the answer can be remembered; the panel follows the document", ^{
        NSString *md = tmpPath(@"readme.md");
        [@"# Title\n\nSome *text*.\n\n- [ ] task\n" writeToFile:md atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [c showLivePreview:NO];   // an earlier test may have opened one
        g_lastPrompt = nil;
        nextAnswer = @"Open with Live Preview";
        [c openFile:md];
        REQUIRE([g_lastPrompt containsString:@"readme.md"]);
        REQUIRE([c.docks isPanelVisible:@"preview"]);
        REQUIRE(c.previewPanel.mode == TPPreviewMarkdown && [TPPreviewPanel isMarkdownPath:md] && ![TPPreviewPanel isMarkdownPath:@"a.txt"]);
        [c showLivePreview:NO];
        [c closeAll_forTests];
        nextAnswer = @"Text Only";
        g_lastPrompt = nil;
        [c openFile:md];
        REQUIRE(g_lastPrompt != nil && ![c.docks isPanelVisible:@"preview"]);
        [c closeAll_forTests];
        [TPPrefs set:@2 forKey:@"pref.markdownOpen"];   // remembered: text only, no question
        g_lastPrompt = nil;
        [c openFile:md];
        REQUIRE(g_lastPrompt == nil && ![c.docks isPanelVisible:@"preview"]);
        [c closeAll_forTests];
        [TPPrefs set:@1 forKey:@"pref.markdownOpen"];
        [c openFile:md];
        REQUIRE(g_lastPrompt == nil && [c.docks isPanelVisible:@"preview"]);
        REQUIRE(exec(IDM_TP_LIVE_PREVIEW) && ![c.docks isPanelVisible:@"preview"]);   // View > Live Preview toggles it
        nextAnswer = nil;
    });

    run(@"T-MD-002", @"Live Preview edits come back as Markdown: a block's lines are replaced as one undo step; task boxes toggle [ ] / [x]; HTML files preview as pages", ^{
        [c newDocument];
        setText("# Title\n\npara one\npara two\n\n- [ ] task\n\ntail\n");
        TPPreviewPanel *pp = c.previewPanel;
        [c.docks showPanel:@"preview"];
        [pp documentsChanged];
        // the page would send these; the panel only accepts them for the document it shows
        [pp handleMessage:@{@"type": @"edit", @"start": @2, @"end": @4, @"text": @"para **one**\nline\nthree"}];
        REQUIRE(text() == "# Title\n\npara **one**\nline\nthree\n\n- [ ] task\n\ntail\n");
        SCI(c.editor, SCI_UNDO);
        REQUIRE(text() == "# Title\n\npara one\npara two\n\n- [ ] task\n\ntail\n");
        [pp handleMessage:@{@"type": @"task", @"line": @5, @"checked": @YES}];
        REQUIRE(text() == "# Title\n\npara one\npara two\n\n- [x] task\n\ntail\n");
        [pp handleMessage:@{@"type": @"edit", @"start": @7, @"end": @8, @"text": @"last"}];
        REQUIRE(text() == "# Title\n\npara one\npara two\n\n- [x] task\n\nlast\n");
        NSString *html = tmpPath(@"page.html");
        [@"<html><body><h1>Hi</h1></body></html>" writeToFile:html atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [c openFile:html];
        [pp documentsChanged];
        REQUIRE(pp.mode == TPPreviewHTML);
        [c.docks hidePanel:@"preview"];
    });

    run(@"T-CMP-001", @"View > Compare: lines changed / added / deleted marked on both sides, blank space keeps them level, next / previous difference, Clear", ^{
        [c newDocument];
        setText("alpha\nbeta\ngamma\ndelta\nepsilon\n");
        TPDocument *left = c.currentDocument;
        [c newDocument];
        setText("alpha\nBETA\ngamma\nepsilon\nzeta\n");
        TPDocument *right = c.currentDocument;
        [c activateDocument:left inPane:c.activePane];
        NSMutableArray *others = [c.allDocuments mutableCopy];
        [others removeObject:left];
        TPComparePickOverride = (NSInteger)[others indexOfObject:right];
        REQUIRE(exec(IDM_TP_COMPARE));
        TPComparePickOverride = -1;
        REQUIRE(c.isComparing && !c.subPane.hidden && c.mainPane.currentDocument == left && c.subPane.currentDocument == right);
        TPCompareSummary sum = c.compareSummary;
        REQUIRE(sum.changed == 1 && sum.deleted == 1 && sum.added == 1);
        ScintillaView *L = c.mainPane.editor, *R = c.subPane.editor;
        REQUIRE((SCI(L, SCI_MARKERGET, 1) & 1) && (SCI(R, SCI_MARKERGET, 1) & 1));            // beta / BETA changed
        REQUIRE((SCI(L, SCI_MARKERGET, 3) & (1 << 17)) && (SCI(R, SCI_MARKERGET, 4) & (1 << 16)));   // delta deleted, zeta added
        REQUIRE(SCI(R, SCI_ANNOTATIONGETLINES, 2) == 1 && SCI(L, SCI_ANNOTATIONGETLINES, 4) == 1);   // gaps keep the sides level
        SCI(L, SCI_SETINDICATORCURRENT, 20);
        REQUIRE(SCI(L, SCI_INDICATORVALUEAT, 20, SCI(L, SCI_POSITIONFROMLINE, 1)) != 0);       // the changed characters
        [c activatePane:c.mainPane];
        SCI(L, SCI_GOTOPOS, 0);
        REQUIRE(exec(IDM_TP_COMPARE_NEXT) && SCI(L, SCI_LINEFROMPOSITION, SCI(L, SCI_GETCURRENTPOS)) == 1);
        REQUIRE(exec(IDM_TP_COMPARE_NEXT) && SCI(L, SCI_LINEFROMPOSITION, SCI(L, SCI_GETCURRENTPOS)) == 3);
        REQUIRE(exec(IDM_TP_COMPARE_PREV) && SCI(L, SCI_LINEFROMPOSITION, SCI(L, SCI_GETCURRENTPOS)) == 1);
        SCI(R, SCI_SETTEXT, 0, reinterpret_cast<sptr_t>("alpha\nbeta\ngamma\ndelta\nepsilon\n"));
        [c compareRun];
        REQUIRE(c.compareSummary.hunks == 0);
        REQUIRE(exec(IDM_TP_COMPARE_CLEAR) && !c.isComparing && (SCI(L, SCI_MARKERGET, 1) & ((1 << 0) | (1 << 16) | (1 << 17))) == 0);   // change history keeps its own
    });

    run(@"T-PAL-001", @"Command Palette: every menu command (plugins and tools too) found by a few letters, with its path and shortcut; Return runs it", ^{
        TPCommandPalette *p = [TPCommandPalette shared];
        NSArray<TPPaletteEntry *> *r = [p entriesForQuery:@"save as"];
        REQUIRE(r.count && r[0].command == IDM_FILE_SAVEAS && [r[0].path isEqualToString:@"File"] && r[0].shortcut.length);
        r = [p entriesForQuery:@"json format"];
        BOOL json = NO;
        for (TPPaletteEntry *e in r) if ([e.title isEqualToString:@"Format JSON"] && [e.path containsString:@"JSON Tools"]) json = YES;
        REQUIRE(json);
        REQUIRE([TPCommandPalette scoreOf:@"wrp" in:@"Word wrap"] > 0 && [TPCommandPalette scoreOf:@"xyz" in:@"Word wrap"] == 0);
        REQUIRE([TPCommandPalette scoreOf:@"wrap" in:@"Word wrap"] > [TPCommandPalette scoreOf:@"wrap" in:@"Show Wrap Symbol"] - 200);
        r = [p entriesForQuery:@"compare side"];
        REQUIRE(r.count && r[0].command == IDM_TP_COMPARE);
        [c newDocument];
        const BOOL wrapped = [reg isChecked:IDM_VIEW_WRAP];
        TPPaletteEntry *w = nil;
        for (TPPaletteEntry *e in [p entriesForQuery:@"word wrap"]) if (e.command == IDM_VIEW_WRAP) { w = e; break; }
        REQUIRE(w != nil);
        [p runEntry:w];
        REQUIRE([reg isChecked:IDM_VIEW_WRAP] != wrapped);
        [p runEntry:w];
    });

    run(@"T-UI-MODERN-001", @"View > Modern Look: rounded tabs, title bar in the toolbar's colour, macOS Light / Dark themes by default; off gives the classic look", ^{
        REQUIRE([TPPrefs b:@"pref.modernLook"] && c.window.titlebarAppearsTransparent);
        REQUIRE([[TPLanguageService shared].themePath.lastPathComponent isEqualToString:@"macOS Light.xml"]);
        REQUIRE(SCI(c.editor, SCI_STYLEGETBACK, STYLE_DEFAULT) == rgbToSci(0xFFFFFF));
        [TPPrefs set:@1 forKey:@"pref.darkMode"];
        REQUIRE([[TPLanguageService shared].themePath.lastPathComponent isEqualToString:@"macOS Dark.xml"]);
        [TPPrefs set:@0 forKey:@"pref.darkMode"];
        REQUIRE(exec(IDM_TP_MODERN_UI) && ![TPPrefs b:@"pref.modernLook"] && !c.window.titlebarAppearsTransparent);
        REQUIRE(![[TPLanguageService shared].themePath.lastPathComponent isEqualToString:@"macOS Light.xml"]);
        exec(IDM_TP_MODERN_UI);
        REQUIRE([TPPrefs b:@"pref.modernLook"]);
    });

    run(@"T-GIT-001", @"Git change markers: lines added / changed / deleted since the last commit, next / previous change; not shown outside a repository", ^{
        NSString *git = TPGitExecutable();
        NSString *repo = tmpPath(@"repo"), *file = [repo stringByAppendingPathComponent:@"code.txt"];
        [[NSFileManager defaultManager] createDirectoryAtPath:repo withIntermediateDirectories:YES attributes:nil error:nil];
        [@"one\ntwo\nthree\nfour\n" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
        REQUIRE(TPGitRepositoryRoot(file) == nil && TPGitHeadText(file) == nil);
        if (!git) return;   // no git on this Mac: nothing more to check
        auto gitRun = [&](NSArray *args) {
            NSTask *t = [NSTask new];
            t.executableURL = [NSURL fileURLWithPath:git];
            t.arguments = [@[@"-C", repo, @"-c", @"user.name=Test", @"-c", @"user.email=test@example.invalid"] arrayByAddingObjectsFromArray:args];
            t.standardOutput = t.standardError = [NSFileHandle fileHandleWithNullDevice];
            [t launchAndReturnError:nil];
            [t waitUntilExit];
            return t.terminationStatus;
        };
        REQUIRE(gitRun(@[@"init", @"-q"]) == 0 && gitRun(@[@"add", @"code.txt"]) == 0 && gitRun(@[@"commit", @"-q", @"-m", @"one"]) == 0);
        NSString *head = TPGitHeadText(file);
        REQUIRE([TPGitRepositoryRoot(file) isEqualToString:repo] && [head isEqualToString:@"one\ntwo\nthree\nfour\n"]);
        [c openFile:file];
        setText("one\nTWO\nthree\nnew\n");
        [c gitApplyHead:head toEditor:c.editor];
        ScintillaView *v = c.editor;
        REQUIRE((SCI(v, SCI_MARKERGET, 1) & (1 << 14)) && (SCI(v, SCI_MARKERGET, 0) & (7 << 13)) == 0);     // changed
        REQUIRE(SCI(v, SCI_MARKERGET, 3) & (1 << 14));                                        // four -> new
        REQUIRE(SCI(v, SCI_GETMARGINWIDTHN, 4) > 0);
        setText("one\ntwo\nthree\nfour\nfive\n");
        [c gitApplyHead:head toEditor:v];
        REQUIRE(SCI(v, SCI_MARKERGET, 4) & (1 << 13));                                        // added
        setText("one\nthree\nfour\n");
        [c gitApplyHead:head toEditor:v];
        REQUIRE(SCI(v, SCI_MARKERGET, 1) & (1 << 15));                                        // "two" deleted above "three"
        setText("one\nX\nthree\nfour\nY\n");
        [c gitApplyHead:head toEditor:v];
        SCI(v, SCI_GOTOPOS, 0);
        REQUIRE(exec(IDM_TP_GIT_NEXT) && SCI(v, SCI_LINEFROMPOSITION, SCI(v, SCI_GETCURRENTPOS)) == 1);
        REQUIRE(exec(IDM_TP_GIT_NEXT) && SCI(v, SCI_LINEFROMPOSITION, SCI(v, SCI_GETCURRENTPOS)) == 4);
        REQUIRE(exec(IDM_TP_GIT_PREV) && SCI(v, SCI_LINEFROMPOSITION, SCI(v, SCI_GETCURRENTPOS)) == 1);
    });

    run(@"T-CSV-001", @"CSV: each column its own colour (lines on screen only), Align / Shrink Columns keep quoted fields; other files are left alone", ^{
        NSString *f = tmpPath(@"data.csv");
        [@"id,name,city\n1,\"Smith, J\",Paris\n22,Al,Rome\n" writeToFile:f atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [c openFile:f];
        REQUIRE([c.currentDocument.languageId isEqualToString:@"normal"] && TPIsCsvPath(f) && !TPIsCsvPath(@"a.txt"));
        ScintillaView *v = c.editor;
        [c csvRainbowStyleLines:0 to:2 inView:v];
        const sptr_t l1 = SCI(v, SCI_POSITIONFROMLINE, 1);
        REQUIRE(SCI(v, SCI_GETSTYLEAT, 0) == 1 && SCI(v, SCI_GETSTYLEAT, 2) != 1 && SCI(v, SCI_GETSTYLEAT, 3) == 2);       // id | , | name
        REQUIRE(SCI(v, SCI_GETSTYLEAT, l1 + 4) == 2 && SCI(v, SCI_GETSTYLEAT, l1 + 12) == 0 && SCI(v, SCI_GETSTYLEAT, l1 + 13) == 3);                              // inside the quotes, then Paris
        REQUIRE(exec(IDM_TP_CSV_ALIGN) && text() == "id, name      , city\n1 , \"Smith, J\", Paris\n22, Al        , Rome\n");
        SCI(v, SCI_UNDO);
        REQUIRE(text() == "id,name,city\n1,\"Smith, J\",Paris\n22,Al,Rome\n");
        exec(IDM_TP_CSV_ALIGN);
        REQUIRE(exec(IDM_TP_CSV_SHRINK) && text() == "id,name,city\n1,\"Smith, J\",Paris\n22,Al,Rome\n");
    });

    run(@"T-SNIP-001", @"Snippets: trigger + Tab inserts the template with the line's indent; Tab / ⇧Tab move through the fields; $0 ends; your own snippets.json", ^{
        TPSnippetExpansion *x = TPExpandSnippet(@"for (${1:i}; ${2:n}) {\n\t$0\n}", @"  ", @"    ");
        REQUIRE([x.text isEqualToString:@"for (i; n) {\n      \n  }"] && x.stops.count == 3);
        REQUIRE(NSEqualRanges(x.stops[0].rangeValue, NSMakeRange(5, 1)) && NSEqualRanges(x.stops[1].rangeValue, NSMakeRange(8, 1)));
        REQUIRE(NSEqualRanges(x.stops[2].rangeValue, NSMakeRange(19, 0)));
        REQUIRE(TPSnippetsForLanguage(@"python")[@"def"] && TPSnippetsForLanguage(@"python")[@"todo"] && !TPSnippetsForLanguage(@"python")[@"html5"]);
        [c newDocument];
        [c setDocumentLanguage:c.currentDocument languageId:@"python"];
        ScintillaView *v = c.editor;
        SCI(v, SCI_SETUSETABS, 0);
        SCI(v, SCI_SETINDENT, 4);
        setText("    def");
        SCI(v, SCI_GOTOPOS, 7);
        NSEvent *tab = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil
                                      characters:@"\t" charactersIgnoringModifiers:@"\t" isARepeat:NO keyCode:48];
        REQUIRE([c handleSnippetKey:tab inEditor:v] && text() == "    def name():\n        pass" && c.snippetActive);
        REQUIRE(NSStr(sciGetRange(v, SCI(v, SCI_GETSELECTIONSTART), SCI(v, SCI_GETSELECTIONEND))).length == 4);   // "name" selected
        SCI(v, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>("greet"));
        REQUIRE([c handleSnippetKey:tab inEditor:v] && SCI(v, SCI_GETCURRENTPOS) == 14);   // the empty argument field, after the rename
        SCI(v, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>("who"));
        REQUIRE([c handleSnippetKey:tab inEditor:v]);                                        // "pass" selected
        REQUIRE(NSStr(sciGetRange(v, SCI(v, SCI_GETSELECTIONSTART), SCI(v, SCI_GETSELECTIONEND))).length == 4 && text() == "    def greet(who):\n        pass");
        setText("nothing");
        SCI(v, SCI_GOTOPOS, 7);
        REQUIRE(![c handleSnippetKey:tab inEditor:v]);                                       // not a trigger: Tab stays a tab
        NSData *own = [NSData dataWithContentsOfFile:TPSnippetsFilePath()];   // the user's own snippets survive the test
        [@"{\"*\": {\"zz\": \"custom ${1:x}$0\"}}" writeToFile:TPSnippetsFilePath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSString *zz = TPSnippetsForLanguage(@"normal")[@"zz"];
        if (own) [own writeToFile:TPSnippetsFilePath() atomically:YES];
        else [[NSFileManager defaultManager] removeItemAtPath:TPSnippetsFilePath() error:nil];
        REQUIRE([zz isEqualToString:@"custom ${1:x}$0"]);
    });

    run(@"T-FMT-002", @"Plugins > Code Formatter: Format Document picks SQL / HTML / CSS / JSON / XML by the file; Minify CSS", ^{
        TPPluginHost *h = [TPPluginHost shared];
        int fmtAuto = [h commandForPluginNamed:@"Code Formatter" item:@"Format Document (by language)"], minify = [h commandForPluginNamed:@"Code Formatter" item:@"Minify CSS"];
        REQUIRE(fmtAuto && minify);
        NSString *f = tmpPath(@"q.sql");
        [@"select a,b from t where x=1" writeToFile:f atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [c openFile:f];
        SCI(c.editor, SCI_SETUSETABS, 0);
        SCI(c.editor, SCI_SETINDENT, 2);
        REQUIRE(exec(fmtAuto) && text() == "SELECT\n  a,\n  b\nFROM\n  t\nWHERE\n  x = 1");
        [c newDocument];
        setText("a { color : red ; }");
        REQUIRE(exec(minify) && text() == "a{color:red}");
        [c newDocument];
        setText("plain words");
        g_lastPrompt = nil;
        REQUIRE(exec(fmtAuto) && [g_lastPrompt isEqualToString:@"Format Document"] && text() == "plain words");
    });

    run(@"T-L10N-002", @"Dialogs follow the interface language: buttons, labels and titles found in the language file through english.xml; back to English", ^{
        TPLocalization *l = [TPLocalization shared];
        REQUIRE([l applyLanguageFile:@"french.xml"]);
        NSString *mc = [l translateDialogString:@"Match &case"], *cancel = [l translateDialogString:@"Cancel"];
        REQUIRE([mc isEqualToString:@"Respecter la casse"] && [cancel isEqualToString:@"Annuler"]);
        REQUIRE([[l translateDialogString:@"Find what :"] hasSuffix:@":"] && [l translateDialogString:@"Some text no file has"] == nil);
        NSPanel *w = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 300, 100) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
        NSButton *b = [NSButton buttonWithTitle:@"Cancel" target:nil action:nil];
        NSButton *box = [NSButton checkboxWithTitle:@"Match case" target:nil action:nil];
        [w.contentView addSubview:b];
        [w.contentView addSubview:box];
        [l translateWindow:w];
        REQUIRE([b.title isEqualToString:@"Annuler"] && [box.title isEqualToString:@"Respecter la casse"]);
        [l applyLanguageFile:@""];
        [l translateWindow:w];
        REQUIRE([b.title isEqualToString:@"Cancel"] && [box.title isEqualToString:@"Match case"]);
    });

    run(@"T-FEAT-001", @"Textpad++'s own commands: in the menus with a handler, default shortcuts clash with nothing, Settings page", ^{
        NSArray<NSNumber *> *extras = reg.extraCommands;
        REQUIRE(extras.count >= 15);
        for (NSNumber *n in extras) {
            REQUIRE([reg hasHandler:n.intValue] && [reg menuItemForCommand:n.intValue] != nil && [reg menuPathForCommand:n.intValue].count >= 2);
            TPKeyBinding *kb = [reg primaryBindingForCommand:n.intValue];
            if (kb && !kb.isEmpty) REQUIRE([reg commandsBoundToKey:kb.keyEquivalent modifiers:kb.modifiers].count == 1);
        }
        REQUIRE([[reg menuPathForCommand:IDM_TP_COMPARE] isEqualToArray:(@[@"View", @"Compare", @"Compare Side by Side"])]);
        BOOL page = NO;
        for (NSDictionary *pg in [TPPrefs pages]) if ([pg[@"title"] isEqualToString:@"Textpad++ Features"]) page = YES;
        REQUIRE(page);
    });
