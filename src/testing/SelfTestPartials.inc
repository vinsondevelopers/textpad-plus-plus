// Textpad++ — acceptance tests for the "complete the partial features" stage.
// Included inside +[TPSelfTest runWithController:output:] (shares run/exec/text/setText and REQUIRE).
// GPL-3.0-or-later.

    run(@"T-REG-001", @"Regression: link marking on an empty document while switching documents (crash 14 Nov 2026)", ^{
        [TPPrefs set:@YES forKey:@"pref.links"];
        [c newDocument];                                  // empty buffer: Scintilla's gap buffer has no storage yet
        REQUIRE(sciGetRange(c.editor, -1, 0).empty());    // the crashing call: start -1 on an empty document
        REQUIRE(sciGetRange(c.editor, -5, 3).empty());
        REQUIRE(sciGetRange(c.editor, 4, 2).empty());
        [c newDocument];
        setText("see https://example.com/a and more\n");
        REQUIRE(sciGetRange(c.editor, -3, 3) == "see");
        REQUIRE(sciGetRange(c.editor, 30, 999) == "more\n");
        for (int i = 0; i < 5; i++) [c newDocument];      // several empty documents
        [c closeAll_forTests];                            // SetDocPointer -> UPDATEUI -> markLinksInView on each switch
        REQUIRE(c.currentDocument != nil);
    });

    run(@"T-PRINT-001", @"Print: form feed as page break (upstream Printer), FF blob otherwise, line numbers, upstream defaults", ^{
        REQUIRE([TPPrefs b:@"pref.printLineNumbers"] && [TPPrefs i:@"pref.printColorMode"] == 3 && ![TPPrefs b:@"pref.printFormfeed"]);
        [c newDocument];
        setText("page one\n\fpage two\nmore\f\npage three\n");
        NSPrintInfo *pi = [c printInfoFromPreferences];
        NSTextView *tv = (NSTextView *)[c printViewWithInfo:pi];
        REQUIRE([tv.string containsString:@"FF"] && ![tv.string containsString:@"\f"]);
        REQUIRE([tv.string hasPrefix:@"1  page one"]);                  // line numbers on by default (upstream)
        NSRange r = NSMakeRange(0, 0);
        REQUIRE([[tv valueForKey:@"formFeedBreaks"] count] == 0);         // no FF breaks: AppKit pagination (only valid inside a print job)
        [TPPrefs set:@YES forKey:@"pref.printFormfeed"];
        [TPPrefs set:@NO forKey:@"pref.printLineNumbers"];
        tv = (NSTextView *)[c printViewWithInfo:pi];
        REQUIRE(![tv.string containsString:@"FF"] && ![tv.string containsString:@"\f"]);
        REQUIRE([tv knowsPageRange:&r] && r.location == 1 && r.length == 3);
        NSRect p1 = [tv rectForPage:1], p2 = [tv rectForPage:2], p3 = [tv rectForPage:3];
        REQUIRE(NSMaxY(p1) <= NSMinY(p2) + 0.5 && NSMaxY(p2) <= NSMinY(p3) + 0.5 && p1.size.height > 0);
        // a long document without FF still splits by page height
        std::string big;
        for (int i = 0; i < 400; i++) big += "line " + std::to_string(i) + "\n";
        setText(big + "\ftail\n");
        tv = (NSTextView *)[c printViewWithInfo:pi];
        REQUIRE([tv knowsPageRange:&r] && r.length >= 3);
        REQUIRE(NSHeight([tv rectForPage:1]) <= pi.paperSize.height - pi.topMargin - pi.bottomMargin + 0.5);
    });
    run(@"T-EDIT-SE-001", @"Edit > On Selection > Change Search Engine... opens Preferences on the Search Engine page", ^{
        [TPPreferencesWindow shared].window.alphaValue = 0;
        REQUIRE(exec(IDM_EDIT_CHANGESEARCHENGINE));
        REQUIRE([[TPPreferencesWindow shared].currentPage isEqualToString:@"Search Engine"]);
        [[TPPreferencesWindow shared].window orderOut:nil];
    });

    run(@"T-AUTOC-001", @"Function Completion from upstream API files (autoCompletion/*.xml) with function/keyword images", ^{
        [c newDocument];
        exec(IDM_LANG_PYTHON);
        TPAutoCompletion *ac = [c autoCompletionForEditor];
        REQUIRE(ac.funcCompletionActive && [ac.apiFilePath hasSuffix:@"autoCompletion/python.xml"]);
        setText("pri");
        SCI(c.editor, SCI_DOCUMENTEND);
        REQUIRE(exec(IDM_EDIT_AUTOCOMPLETE));
        REQUIRE(SCI(c.editor, SCI_AUTOCACTIVE));
        char cur[128] = {0};
        SCI(c.editor, SCI_AUTOCGETCURRENTTEXT, 0, reinterpret_cast<sptr_t>(cur));
        REQUIRE(std::string(cur).rfind("pri", 0) == 0);                   // list positioned on a "pri…" API keyword
        SCI(c.editor, SCI_AUTOCCANCEL);
        exec(IDM_LANG_JS);
        REQUIRE([[c autoCompletionForEditor].apiFilePath hasSuffix:@"javascript.xml"]);   // upstream maps javascript.js -> javascript
        [c newDocument];                                                  // Normal text: no API file, nothing shown (upstream)
        REQUIRE(![c autoCompletionForEditor].funcCompletionActive);
        setText("pri");
        SCI(c.editor, SCI_DOCUMENTEND);
        exec(IDM_EDIT_AUTOCOMPLETE);
        REQUIRE(SCI(c.editor, SCI_AUTOCACTIVE) == 0);
    });
    run(@"T-AUTOC-002", @"Word Completion auto-inserts a single match; typing shows function+word list (Preferences mode both)", ^{
        [c newDocument];
        setText("elephant\nel");
        SCI(c.editor, SCI_DOCUMENTEND);
        REQUIRE(exec(IDM_EDIT_AUTOCOMPLETE_CURRENTFILE));
        REQUIRE_EQ_STR(text(), "elephant\nelephant");
        REQUIRE(SCI(c.editor, SCI_AUTOCACTIVE) == 0);
        setText("element\nelephant\nel");
        SCI(c.editor, SCI_DOCUMENTEND);
        exec(IDM_EDIT_AUTOCOMPLETE_CURRENTFILE);
        REQUIRE(SCI(c.editor, SCI_AUTOCACTIVE) != 0);                   // two matches: list, no insertion
        SCI(c.editor, SCI_AUTOCCANCEL);
        exec(IDM_LANG_C);
        setText("int strcount;\n");
        SCI(c.editor, SCI_DOCUMENTEND);
        typeText(@"strc");                                                // both: API keywords (strcpy, strcat…) + document words
        REQUIRE(SCI(c.editor, SCI_AUTOCACTIVE) != 0);
        SCI(c.editor, SCI_AUTOCCANCEL);
    });
    run(@"T-AUTOC-003", @"Function parameters hint: on '(' and ',', current parameter highlighted, overload cycling, closes after ')'", ^{
        [c newDocument];
        exec(IDM_LANG_C);
        TPAutoCompletion *ac = [c autoCompletionForEditor];
        typeText(@"strcpy(");
        REQUIRE(ac.callTipVisible && [ac.lastCallTipText isEqualToString:@"char * strcpy (char *s1, const char *s2)"]);
        REQUIRE(SCI(c.editor, SCI_CALLTIPPOSSTART) == 7);
        typeText(@"dst,");
        REQUIRE(ac.callTipVisible);
        typeText(@" src)");
        REQUIRE(!ac.callTipVisible);
        // overloads (perl.xml "abs" has two): \001 n of m \002 arrows, Alt+Down / Up equivalents
        [c newDocument];
        exec(IDM_LANG_PERL);
        ac = [c autoCompletionForEditor];
        typeText(@"abs(");
        REQUIRE(ac.callTipVisible && [ac.lastCallTipText hasPrefix:@"\0011 of 2\002"]);
        REQUIRE(exec(IDM_EDIT_FUNCCALLTIP_NEXT) && [ac.lastCallTipText hasPrefix:@"\0012 of 2\002"]);
        REQUIRE(exec(IDM_EDIT_FUNCCALLTIP_PREVIOUS) && [ac.lastCallTipText hasPrefix:@"\0011 of 2\002"]);
        [ac callTipClick:2];                                              // click on the down arrow
        REQUIRE([ac.lastCallTipText hasPrefix:@"\0012 of 2\002"]);
        SCI(c.editor, SCI_CALLTIPCANCEL);
        REQUIRE(exec(IDM_EDIT_FUNCCALLTIP) && ac.callTipVisible);        // Ctrl+Shift+Space equivalent re-shows it
        SCI(c.editor, SCI_CALLTIPCANCEL);
        [TPPrefs set:@NO forKey:@"pref.funcParamHint"];                  // Preferences: hint on input off
        [c newDocument];
        exec(IDM_LANG_C);
        typeText(@"strcpy(");
        REQUIRE(![c autoCompletionForEditor].callTipVisible);
    });
    run(@"T-AUTOC-004", @"Path Completion lists the folder with full paths, folders get '/', ~ is kept as typed", ^{
        NSString *dir = tmpPath(@"pathc");
        [[NSFileManager defaultManager] createDirectoryAtPath:[dir stringByAppendingPathComponent:@"Beta"] withIntermediateDirectories:YES attributes:nil error:nil];
        writeBytes([dir stringByAppendingPathComponent:@"alpha.txt"], "x");
        [c newDocument];
        setText("cat " + StdStr(dir) + "/al");
        SCI(c.editor, SCI_DOCUMENTEND);
        REQUIRE(exec(IDM_EDIT_AUTOCOMPLETE_PATH));
        REQUIRE(SCI(c.editor, SCI_AUTOCACTIVE));
        char cur[1024] = {0};
        SCI(c.editor, SCI_AUTOCGETCURRENTTEXT, 0, reinterpret_cast<sptr_t>(cur));
        REQUIRE(std::string(cur) == StdStr(dir) + "/alpha.txt");
        SCI(c.editor, SCI_AUTOCCOMPLETE);
        REQUIRE_EQ_STR(text(), "cat " + StdStr(dir) + "/alpha.txt");
        setText("open " + StdStr(dir) + "/b");                            // case-insensitive, folder gets a trailing slash
        SCI(c.editor, SCI_DOCUMENTEND);
        exec(IDM_EDIT_AUTOCOMPLETE_PATH);
        SCI(c.editor, SCI_AUTOCGETCURRENTTEXT, 0, reinterpret_cast<sptr_t>(cur));
        REQUIRE(std::string(cur) == StdStr(dir) + "/Beta/");
        SCI(c.editor, SCI_AUTOCCANCEL);
        setText("ls ~/");
        SCI(c.editor, SCI_DOCUMENTEND);
        exec(IDM_EDIT_AUTOCOMPLETE_PATH);
        SCI(c.editor, SCI_AUTOCGETCURRENTTEXT, 0, reinterpret_cast<sptr_t>(cur));
        REQUIRE(SCI(c.editor, SCI_AUTOCACTIVE) && std::string(cur).rfind("~/", 0) == 0);
        SCI(c.editor, SCI_AUTOCCANCEL);
        setText("cat " + StdStr(dir) + "/alpha.txt");                     // already a complete file name: nothing
        SCI(c.editor, SCI_DOCUMENTEND);
        exec(IDM_EDIT_AUTOCOMPLETE_PATH);
        REQUIRE(SCI(c.editor, SCI_AUTOCACTIVE) == 0);
    });

    run(@"T-SRCH-FCR-001", @"Find Characters in Range dialog: non-ASCII/ASCII/custom ranges, Up/Down, Wrap around, range error", ^{
        TPFindCharsInRangeDialog *d = [TPFindCharsInRangeDialog sharedWithController:c];
        d.window.alphaValue = 0;
        [c newDocument];
        setText("ab\xC3\xA9" "cd\x7F" "ef");                               // é is 2 bytes in UTF-8
        SCI(c.editor, SCI_GOTOPOS, 0);
        REQUIRE(exec(IDM_SEARCH_FINDCHARINRANGE) && d.window.isVisible);
        REQUIRE(d.rangeMode == 0 && d.directionDown && !d.wrapAround);    // upstream defaults
        [d findNext:nil];
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 2 && SCI(c.editor, SCI_GETSELECTIONEND) == 4);
        [d findNext:nil];                                                 // no further match, no wrap: selection kept
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 2);
        SCI(c.editor, SCI_GOTOPOS, 6);
        [d findNext:nil];
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 6 && SCI(c.editor, SCI_GETSELECTIONEND) == 6);
        d.wrapAround = YES;
        [d findNext:nil];                                                 // wraps to the start
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 2 && SCI(c.editor, SCI_GETSELECTIONEND) == 4);
        d.rangeMode = 2; d.rangeStart = @"127"; d.rangeEnd = @"127";
        [d findNext:nil];
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 6 && SCI(c.editor, SCI_GETSELECTIONEND) == 7);
        d.rangeMode = 1; d.directionDown = NO;                            // ASCII, searching up from the end
        SCI(c.editor, SCI_DOCUMENTEND);
        [d findNext:nil];
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 8 && SCI(c.editor, SCI_GETCURRENTPOS) == 8);
        [d findNext:nil];
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 7);
        g_lastPrompt = nil;
        d.rangeMode = 2; d.rangeStart = @"300"; d.rangeEnd = @"10";
        [d findNext:nil];
        REQUIRE([g_lastPrompt isEqualToString:@"Range Value problem"]);
        d.rangeStart = @"20"; g_lastPrompt = nil;                         // start > end is rejected too (upstream)
        [d findNext:nil];
        REQUIRE(g_lastPrompt != nil);
        d.rangeMode = 0; d.directionDown = YES; d.wrapAround = NO;
        [d.window orderOut:nil];
    });

    run(@"T-VIEW-HL-001", @"Hide Lines (upstream): markers around the section, merging, click on a marker shows the lines, survives document switches", ^{
        [c newDocument];
        SCI(c.editor, SCI_SETEOLMODE, SC_EOL_LF);
        setText("0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n");
        auto selLines = [&](sptr_t a, sptr_t b) { SCI(c.editor, SCI_SETSEL, SCI(c.editor, SCI_POSITIONFROMLINE, a), SCI(c.editor, SCI_GETLINEENDPOSITION, b)); };
        auto marks = [&](sptr_t l) { return SCI(c.editor, SCI_MARKERGET, l) & ((1 << TPP_MARK_HIDELINESBEGIN) | (1 << TPP_MARK_HIDELINESEND)); };
        selLines(2, 3);
        REQUIRE(exec(IDM_VIEW_HIDELINES));
        REQUIRE(!SCI(c.editor, SCI_GETLINEVISIBLE, 2) && !SCI(c.editor, SCI_GETLINEVISIBLE, 3) && SCI(c.editor, SCI_GETLINEVISIBLE, 4));
        REQUIRE(marks(1) == (1 << TPP_MARK_HIDELINESBEGIN) && marks(4) == (1 << TPP_MARK_HIDELINESEND));
        selLines(4, 5);                                                   // selection includes the end-marker line: merged into 2..5
        exec(IDM_VIEW_HIDELINES);
        REQUIRE(marks(4) == 0 && marks(1) == (1 << TPP_MARK_HIDELINESBEGIN) && marks(6) == (1 << TPP_MARK_HIDELINESEND));
        REQUIRE(!SCI(c.editor, SCI_GETLINEVISIBLE, 4) && !SCI(c.editor, SCI_GETLINEVISIBLE, 5) && SCI(c.editor, SCI_GETLINEVISIBLE, 6));
        selLines(7, 7);                                                   // touching section below: its begin marker shares line 6
        exec(IDM_VIEW_HIDELINES);
        REQUIRE(marks(6) == ((1 << TPP_MARK_HIDELINESBEGIN) | (1 << TPP_MARK_HIDELINESEND)) && !SCI(c.editor, SCI_GETLINEVISIBLE, 7));
        TPDocument *d = c.currentDocument;
        [c newDocument];                                                  // switch away and back: the view re-hides both sections
        [c activateDocument:d inPane:c.mainPane];
        REQUIRE(!SCI(c.editor, SCI_GETLINEVISIBLE, 5) && SCI(c.editor, SCI_GETLINEVISIBLE, 6) && !SCI(c.editor, SCI_GETLINEVISIBLE, 7));
        // click on line 6 (end + begin markers): upstream opens the lower section first
        SCNotification n = {};
        n.nmhdr.code = SCN_MARGINCLICK;
        n.margin = TPP_MARGIN_SYMBOL;
        n.position = SCI(c.editor, SCI_POSITIONFROMLINE, 6);
        [c pane:c.mainPane notification:&n];
        REQUIRE(SCI(c.editor, SCI_GETLINEVISIBLE, 7) && !SCI(c.editor, SCI_GETLINEVISIBLE, 5) && marks(6) == (1 << TPP_MARK_HIDELINESEND) && marks(8) == 0);
        [c pane:c.mainPane notification:&n];                              // now the end marker: shows 2..5
        REQUIRE(SCI(c.editor, SCI_GETLINEVISIBLE, 2) && SCI(c.editor, SCI_GETLINEVISIBLE, 5));
        REQUIRE(marks(1) == 0 && marks(6) == 0);
        REQUIRE(!(SCI(c.editor, SCI_MARKERGET, 6) & (1 << TPP_MARK_BOOKMARK)));   // marker clicks did not toggle a bookmark
        [c pane:c.mainPane notification:&n];                              // a plain line: bookmark toggles
        REQUIRE(SCI(c.editor, SCI_MARKERGET, 6) & (1 << TPP_MARK_BOOKMARK));
        selLines(0, 0);                                                   // first line alone cannot be hidden (upstream range check)
        exec(IDM_VIEW_HIDELINES);
        REQUIRE(SCI(c.editor, SCI_GETLINEVISIBLE, 0) && SCI(c.editor, SCI_MARKERNEXT, 0, 1 << TPP_MARK_HIDELINESBEGIN) == -1);
    });
    run(@"T-VIEW-PI-001", @"Post-it hides toolbar, tabs, status bar and the title bar; Distraction Free side padding = width / N (3–9)", ^{
        [c newDocument];
        REQUIRE(exec(IDM_VIEW_POSTIT) && [reg isChecked:IDM_VIEW_POSTIT]);
        REQUIRE(c.window.titlebarAppearsTransparent && c.window.titleVisibility == NSWindowTitleHidden && c.window.movableByWindowBackground);
        REQUIRE([c.window standardWindowButton:NSWindowCloseButton].hidden && (c.window.styleMask & NSWindowStyleMaskFullSizeContentView));
        REQUIRE(c.chromeForcedHidden);
        exec(IDM_VIEW_POSTIT);
        REQUIRE(!c.window.titlebarAppearsTransparent && ![c.window standardWindowButton:NSWindowCloseButton].hidden && !c.chromeForcedHidden);
        REQUIRE([TPPrefs i:@"pref.distractionFreeWidth"] == 4 && [c distractionFreePaddingForWidth:800] == 200);
        [TPPrefs set:@8 forKey:@"pref.distractionFreeWidth"];
        REQUIRE(exec(IDM_VIEW_DISTRACTIONFREE) && c.distractionFreeActive);   // full-screen switch is skipped in the self-test
        REQUIRE(SCI(c.editor, SCI_GETMARGINLEFT) == static_cast<sptr_t>(NSWidth(c.editor.bounds) / 8));
        exec(IDM_VIEW_DISTRACTIONFREE);
        REQUIRE(!c.distractionFreeActive && SCI(c.editor, SCI_GETMARGINLEFT) == 1);
    });

    run(@"T-STYLE-001", @"Style Configurator: per-style colour/font edits preview live, user keywords, user ext., Save & Close writes stylers.xml", ^{
        TPStyleConfigurator *sc = [TPStyleConfigurator sharedWithController:c];
        sc.window.alphaValue = 0;
        TPLanguageService *ls = [TPLanguageService shared];
        NSString *stylersUser = [[TPSession shared].supportDirectory stringByAppendingPathComponent:@"stylers.xml"];
        [[NSFileManager defaultManager] removeItemAtPath:stylersUser error:nil];
        [ls loadTheme:[TPLanguageService defaultThemePath] error:nil];
        [c newDocument];
        exec(IDM_LANG_CPP);
        REQUIRE(exec(IDM_LANGSTYLE_CONFIG_DLG) && sc.window.isVisible);
        REQUIRE(sc.themeNames.count >= 20 && [sc.themeNames containsObject:@"Monokai"]);   // upstream themes are bundled
        [sc selectLanguageNamed:@"cpp"];
        [sc selectStyleNamed:@"INSTRUCTION WORD"];
        REQUIRE([sc.currentStyle.name isEqualToString:@"INSTRUCTION WORD"] && sc.boldCheck.state == NSControlStateValueOn);
        REQUIRE([sc.defaultKeywordsView.string containsString:@"while"] && !sc.userKeywordsView.enclosingScrollView.superview.hidden);
        sc.boldCheck.state = NSControlStateValueOff; sc.italicCheck.state = NSControlStateValueOn;
        [sc controlChanged:sc.italicCheck];
        REQUIRE(SCI(c.editor, SCI_STYLEGETITALIC, SCE_C_WORD) == 1 && SCI(c.editor, SCI_STYLEGETBOLD, SCE_C_WORD) == 0);
        sc.foregroundWell.color = [NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1];
        [sc controlChanged:sc.foregroundWell];
        REQUIRE(SCI(c.editor, SCI_STYLEGETFORE, SCE_C_WORD) == rgbToSci(0xFF0000));
        [sc.fontSizePopup selectItemWithTitle:@"14"];
        [sc controlChanged:sc.fontSizePopup];
        REQUIRE(SCI(c.editor, SCI_STYLEGETSIZEFRACTIONAL, SCE_C_WORD) == static_cast<sptr_t>([TPLanguageService macPointsFromWindowsPoints:14] * SC_FONT_SIZE_MULTIPLIER + 0.5));
        // user-defined keywords become part of keyword class instre1 (upstream getCompleteKeywordList)
        sc.userKeywordsView.string = @"zorkword";
        [[NSNotificationCenter defaultCenter] postNotificationName:NSTextDidChangeNotification object:sc.userKeywordsView];
        setText("zorkword x;\n");
        SCI(c.editor, SCI_COLOURISE, 0, -1);
        REQUIRE(SCI(c.editor, SCI_GETSTYLEAT, 0) == SCE_C_WORD);
        // user extension maps to the language
        sc.userExtField.stringValue = @"tpx";
        [[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidChangeNotification object:sc.userExtField];
        REQUIRE([[ls languageForFileName:@"demo.tpx"].langId isEqualToString:@"cpp"]);
        REQUIRE(ls.themeModified);
        [sc saveAndClose:nil];
        REQUIRE(!sc.window.isVisible && !ls.themeModified && [ls.themePath isEqualToString:stylersUser]);
        REQUIRE([[TPPrefs s:@"ThemePath"] isEqualToString:stylersUser]);
        NSString *saved = [NSString stringWithContentsOfFile:stylersUser encoding:NSUTF8StringEncoding error:nil];
        REQUIRE([saved containsString:@"zorkword"] && [saved containsString:@"ext=\"tpx\""]);
        [ls loadTheme:stylersUser error:nil];                             // reload from disk: the edits persisted
        TPStyleSpec *iw = nil;
        for (TPStyleSpec *s in [ls stylesForLexerType:@"cpp"]) if ([s.name isEqualToString:@"INSTRUCTION WORD"]) iw = s;
        REQUIRE(iw.fg == 0xFF0000 && iw.fontStyle == 2 && iw.fontSize == 14 && [iw.userKeywords isEqualToString:@"zorkword"]);
        REQUIRE([[TPLanguageService defaultThemePath] isEqualToString:stylersUser]);
    });
    run(@"T-STYLE-002", @"Style Configurator: Global override, Cancel restores the theme, theme preview, Go to settings", ^{
        TPStyleConfigurator *sc = [TPStyleConfigurator sharedWithController:c];
        sc.window.alphaValue = 0;
        TPLanguageService *ls = [TPLanguageService shared];
        [c newDocument];
        exec(IDM_LANG_CPP);
        exec(IDM_LANGSTYLE_CONFIG_DLG);
        NSString *before = ls.themePath;
        [sc selectLanguageNamed:@"Global Styles"];
        [sc selectStyleNamed:@"Global override"];
        REQUIRE(!sc.globalOverrideChecks.firstObject.superview.hidden);
        sc.globalOverrideChecks[0].state = NSControlStateValueOn;         // Force foreground color for all styles
        [sc controlChanged:sc.globalOverrideChecks[0]];
        REQUIRE([TPPrefs b:@"pref.go.fg"]);
        TPStyleSpec *go = [ls globalStyle:@"Global override"];
        REQUIRE(SCI(c.editor, SCI_STYLEGETFORE, SCE_C_WORD) == rgbToSci(go.fg) && SCI(c.editor, SCI_STYLEGETFORE, STYLE_DEFAULT) == rgbToSci(go.fg));
        [sc selectStyleNamed:@"Edge colour"];
        REQUIRE(!sc.goToSettingsButton.hidden);
        [TPPreferencesWindow shared].window.alphaValue = 0;
        [sc goToSettings:nil];
        REQUIRE([[TPPreferencesWindow shared].currentPage isEqualToString:@"Margins/Border/Edge"]);
        [[TPPreferencesWindow shared].window orderOut:nil];
        [sc selectThemeNamed:@"Monokai"];                                 // preview another theme
        REQUIRE([ls.themePath.lastPathComponent isEqualToString:@"Monokai.xml"]);
        [sc cancel:nil];                                                  // Cancel: previous theme and override flags
        REQUIRE([ls.themePath isEqualToString:before] && ![TPPrefs b:@"pref.go.fg"]);
        REQUIRE(SCI(c.editor, SCI_STYLEGETFORE, SCE_C_WORD) != rgbToSci(go.fg));
        // clean up the user stylers.xml written by T-STYLE-001
        [[NSFileManager defaultManager] removeItemAtPath:[[TPSession shared].supportDirectory stringByAppendingPathComponent:@"stylers.xml"] error:nil];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"ThemePath"];
        [ls loadTheme:[TPLanguageService defaultThemePath] error:nil];
        for (TPDocument *d in c.allDocuments) d.appliedLexerLanguage = nil;
    });
    run(@"T-STYLE-003", @"Style Configurator in dark mode: a chosen theme survives Save & Close; light and dark mode keep their own theme", ^{
        TPStyleConfigurator *sc = [TPStyleConfigurator sharedWithController:c];
        sc.window.alphaValue = 0;
        TPLanguageService *ls = [TPLanguageService shared];
        [TPPrefs set:@1 forKey:@"pref.darkMode"];                          // Dark
        [c applyAllPreferences];
        REQUIRE([ls.themePath.lastPathComponent isEqualToString:@"macOS Dark.xml"]);   // Modern Look's dark theme (DarkModeDefault without it)
        [c newDocument];
        exec(IDM_LANG_CPP);
        REQUIRE(exec(IDM_LANGSTYLE_CONFIG_DLG));
        [sc selectThemeNamed:@"Monokai"];
        [sc saveAndClose:nil];
        [c applyAllPreferences];
        REQUIRE([ls.themePath.lastPathComponent isEqualToString:@"Monokai.xml"]);   // was replaced by DarkModeDefault before the fix
        const int monokaiBg = rgbToSci([ls globalStyle:@"Default Style"].bg);
        REQUIRE(SCI(c.editor, SCI_STYLEGETBACK, STYLE_DEFAULT) == monokaiBg);
        [TPPrefs set:@0 forKey:@"pref.darkMode"];                          // Light: its own theme (the default)
        [c applyAllPreferences];
        REQUIRE(![ls.themePath.lastPathComponent isEqualToString:@"Monokai.xml"]);
        [TPPrefs set:@1 forKey:@"pref.darkMode"];                          // back to Dark: Monokai again
        [c applyAllPreferences];
        REQUIRE([ls.themePath.lastPathComponent isEqualToString:@"Monokai.xml"]);
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"ThemePathDark"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"ThemePath"];
        [TPPrefs set:@0 forKey:@"pref.darkMode"];
        [c applyAllPreferences];
    });

    run(@"T-KEYS-001", @"Shortcut Mapper (main menu): modify, conflict report, clear, filter; menu key equivalents and shortcuts.xml follow", ^{
        TPShortcutMapper *m = [TPShortcutMapper sharedWithController:c];
        m.window.alphaValue = 0;
        TPCommandRegistry *r = [TPCommandRegistry shared];
        REQUIRE(exec(IDM_SETTING_SHORTCUT_MAPPER) && m.window.isVisible && m.tab == TPMapperTabMainMenu && m.rowCount > 300);
        REQUIRE([m selectCommand:IDM_FILE_NEW]);
        REQUIRE([m.conflictText isEqualToString:@"No shortcut conflicts for this item."]);
        TPKeyBinding *b = [TPKeyBinding bindingWithKey:@"n" modifiers:NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagShift command:IDM_FILE_NEW];
        [m assignBinding:b name:nil];
        NSMenuItem *mi = [r menuItemForCommand:IDM_FILE_NEW];
        REQUIRE([mi.keyEquivalent isEqualToString:@"n"] && mi.keyEquivalentModifierMask == (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagShift));
        REQUIRE([[r primaryBindingForCommand:IDM_FILE_NEW].macDescription isEqualToString:@"⌥⇧⌘N"]);
        // give File > Open the same keys: both rows report the conflict (upstream "CONFLICT FOUND!")
        [m selectCommand:IDM_FILE_OPEN];
        [m assignBinding:[TPKeyBinding bindingWithKey:@"n" modifiers:b.modifiers command:IDM_FILE_OPEN] name:nil];
        REQUIRE([m.conflictText hasPrefix:@"CONFLICT FOUND!"] && [m.conflictText containsString:@"New"]);
        [m clearSelected:nil];                                            // Clear: no shortcut at all
        REQUIRE([r menuItemForCommand:IDM_FILE_OPEN].keyEquivalent.length == 0 && [r userBindingForCommand:IDM_FILE_OPEN].isEmpty);
        NSString *xml = [NSString stringWithContentsOfFile:[[TPSession shared].supportDirectory stringByAppendingPathComponent:@"shortcuts.xml"] encoding:NSUTF8StringEncoding error:nil];
        REQUIRE([xml containsString:@"<Shortcut id=\"41001\" Ctrl=\"yes\" Alt=\"yes\" Shift=\"yes\" Key=\"78\""]);   // upstream format
        REQUIRE([xml containsString:@"<Shortcut id=\"41002\" Ctrl=\"no\" Alt=\"no\" Shift=\"no\" Key=\"0\""]);
        m.filter = @"⌥⇧⌘N";                                              // filter matches shortcuts too
        REQUIRE(m.rowCount == 1 && [[m nameAtRow:0] isEqualToString:@"New"]);
        m.filter = @"";
        // back to defaults (shortcuts.xml without InternalCommands overrides)
        [r setUserBinding:nil forCommand:IDM_FILE_NEW];
        [r setUserBinding:nil forCommand:IDM_FILE_OPEN];
        [c shortcutsDidChange];
        REQUIRE([[r primaryBindingForCommand:IDM_FILE_OPEN].macDescription isEqualToString:@"⌘O"]);
        [m.window orderOut:nil];
    });
    run(@"T-KEYS-002", @"Macros and Run commands: upstream defaults with shortcuts, menus, save macro with a shortcut, rename/delete in the mapper, URL commands", ^{
        TPCommandRegistry *r = [TPCommandRegistry shared];
        NSArray *macros = [c macroNames];
        NSUInteger trim = [macros indexOfObject:@"Trim Trailing Space and Save"];
        REQUIRE(trim != NSNotFound);
        REQUIRE([[r primaryBindingForCommand:TP_ID_MACRO + (int)trim].macDescription isEqualToString:@"⌥⇧S"]);   // upstream Alt+Shift+S
        NSArray *runs = [c runCommandNames];
        REQUIRE([runs isEqualToArray:(@[@"Get PHP help", @"Wikipedia Search", @"Open selected file path in new instance"])]);
        REQUIRE([[r primaryBindingForCommand:TP_ID_USER_CMD + 1].macDescription isEqualToString:@"⌥F3"]);
        NSMenu *runMenu = [r topLevelMenuNamed:@"Run"];
        [c menuNeedsUpdate:runMenu];
        NSMenuItem *wiki = [runMenu itemWithTitle:@"Wikipedia Search"];
        REQUIRE(wiki && wiki.keyEquivalentModifierMask == NSEventModifierFlagOption && [runMenu itemWithTitle:@"Modify Shortcut/Delete Command..."]);
        [c newDocument];
        setText("Textpad");
        SCI(c.editor, SCI_SETSEL, 0, 7);
        REQUIRE(exec(TP_ID_USER_CMD + 1));                               // URL commands open the browser (not run in the self-test)
        REQUIRE([c.lastRunURL.absoluteString isEqualToString:@"https://en.wikipedia.org/wiki/Special:Search?search=Textpad"]);
        // record a macro and save it with a shortcut (Save Current Recorded Macro dialog)
        exec(IDM_MACRO_STARTRECORDINGMACRO);
        exec(IDM_EDIT_SELECTALL);
        exec(IDM_EDIT_UPPERCASE);
        exec(IDM_MACRO_STOPRECORDINGMACRO);
        REQUIRE([c saveCurrentMacroNamed:@"Upper all" shortcut:[TPKeyBinding bindingWithKey:@"u" modifiers:NSEventModifierFlagControl | NSEventModifierFlagOption command:0]]);
        NSInteger idx = (NSInteger)[[c macroNames] indexOfObject:@"Upper all"];
        REQUIRE(idx >= 0);
        const int mcmd = TP_ID_MACRO + (int)idx;
        REQUIRE([[r primaryBindingForCommand:mcmd].macDescription isEqualToString:@"⌃⌥U"]);
        NSMenu *macroMenu = [r topLevelMenuNamed:@"Macro"];
        [c menuNeedsUpdate:macroMenu];
        REQUIRE([macroMenu itemWithTitle:@"Upper all"].keyEquivalentModifierMask == (NSEventModifierFlagControl | NSEventModifierFlagOption));
        setText("abc");
        REQUIRE(exec(mcmd));
        REQUIRE_EQ_STR(text(), "ABC");
        // rename and delete through the Shortcut Mapper (Macros tab)
        TPShortcutMapper *m = [TPShortcutMapper sharedWithController:c];
        m.window.alphaValue = 0;
        REQUIRE(exec(IDM_SETTING_SHORTCUT_MAPPER_MACRO) && m.tab == TPMapperTabMacros);
        REQUIRE([m selectCommand:mcmd]);
        [m assignBinding:[TPKeyBinding bindingWithKey:@"y" modifiers:NSEventModifierFlagControl | NSEventModifierFlagOption command:mcmd] name:@"Upper everything"];
        REQUIRE([[c macroNames] containsObject:@"Upper everything"] && [[r labelForCommand:mcmd] isEqualToString:@"Upper everything"]);
        NSString *xml = [NSString stringWithContentsOfFile:[[TPSession shared].supportDirectory stringByAppendingPathComponent:@"shortcuts.xml"] encoding:NSUTF8StringEncoding error:nil];
        REQUIRE([xml containsString:@"name=\"Upper everything\" Ctrl=\"no\" Alt=\"yes\" Shift=\"no\" Key=\"89\" Control=\"yes\""]);
        [m deleteSelected:nil];
        REQUIRE(![[c macroNames] containsObject:@"Upper everything"]);
        [m.window orderOut:nil];
    });
    run(@"T-KEYS-003", @"Scintilla commands: user keys reach the editor (real key events), Windows scheme uses upstream keys, scheme switch keeps custom keys", ^{
        TPCommandRegistry *r = [TPCommandRegistry shared];
        TPScintillaKeys *sk = [TPScintillaKeys shared];
        auto press = [&](NSString *chars, NSEventModifierFlags mods, unsigned short code) {
            NSEvent *e = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:mods timestamp:0 windowNumber:c.window.windowNumber
                                           context:nil characters:chars charactersIgnoringModifiers:chars isARepeat:NO keyCode:code];
            [c.editor.content keyDown:e];
        };
        [c newDocument];
        SCI(c.editor, SCI_SETEOLMODE, SC_EOL_LF);
        setText("one\ntwo\nthree\n");
        SCI(c.editor, SCI_GOTOLINE, 1);
        TPShortcutMapper *m = [TPShortcutMapper sharedWithController:c];
        m.window.alphaValue = 0;
        [m openOnTab:TPMapperTabScintilla];
        REQUIRE(m.rowCount >= 60 && [m selectScintillaMessage:SCI_LINEDELETE]);
        [m assignBinding:[TPKeyBinding bindingWithKey:@"k" modifiers:NSEventModifierFlagControl | NSEventModifierFlagShift command:SCI_LINEDELETE] name:nil];
        press(@"K", NSEventModifierFlagControl | NSEventModifierFlagShift, 40);   // ⌃⇧K
        REQUIRE_EQ_STR(text(), "one\nthree\n");
        NSString *xml = [NSString stringWithContentsOfFile:[[TPSession shared].supportDirectory stringByAppendingPathComponent:@"shortcuts.xml"] encoding:NSUTF8StringEncoding error:nil];
        REQUIRE([xml containsString:@"<ScintKey ScintID=\"2338\" menuCmdID=\"0\" Ctrl=\"no\" Alt=\"no\" Shift=\"yes\" Key=\"75\" Control=\"yes\""]);
        // Windows scheme: upstream Ctrl+Right = word right (Control key); the custom key keeps its upstream meaning
        r.scheme = TPShortcutSchemeWindows;
        REQUIRE([[sk bindingsForMessage:SCI_WORDRIGHT].firstObject.windowsDescription isEqualToString:@"Ctrl+→"]);
        SCI(c.editor, SCI_GOTOPOS, 0);
        press([NSString stringWithFormat:@"%C", (unichar)NSRightArrowFunctionKey], NSEventModifierFlagControl | NSEventModifierFlagFunction | NSEventModifierFlagNumericPad, 124);
        REQUIRE(SCI(c.editor, SCI_GETCURRENTPOS) == 3);                  // word right stops at the line end (Scintilla NextWordStart)
        r.scheme = TPShortcutSchemeMac;
        REQUIRE([sk bindingsForMessage:SCI_WORDRIGHT].count == 0);       // macOS scheme: Scintilla's native macOS keys
        TPKeyBinding *ld = [sk userBindingForMessage:SCI_LINEDELETE];
        REQUIRE(ld && (ld.modifiers & NSEventModifierFlagControl) && (ld.modifiers & NSEventModifierFlagShift));
        [sk setUserBinding:nil forMessage:SCI_LINEDELETE];
        [c shortcutsDidChange];
        setText("a\nb\n");
        SCI(c.editor, SCI_GOTOPOS, 0);
        press(@"K", NSEventModifierFlagControl | NSEventModifierFlagShift, 40);   // back to default: nothing bound
        REQUIRE_EQ_STR(text(), "a\nb\n");
        [m.window orderOut:nil];
    });

    run(@"T-CMD-001", @"Command line parsing (upstream winmain.cpp options): flags, numbers, quoted values, wildcards, -r, --help output", ^{
        NSString *dir = tmpPath(@"cmdline");
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:[dir stringByAppendingPathComponent:@"sub"] withIntermediateDirectories:YES attributes:nil error:nil];
        writeBytes([dir stringByAppendingPathComponent:@"a.txt"], "a");
        writeBytes([dir stringByAppendingPathComponent:@"b.log"], "b");
        writeBytes([dir stringByAppendingPathComponent:@"sub/c.txt"], "c");
        TPCommandLine *cl = [TPCommandLine parseArguments:@[@"-n12", @"-c5", @"-lpython", @"-udl=\"My UDL\"", @"-ro", @"-nosession", @"-notabbar",
                                                            @"-alwaysOnTop", @"-titleAdd=\"Build 7\"", @"-x40", @"-y60", @"-qSpeed3", @"-qt=hello",
                                                            @"-multiInst", @"-pref.darkMode", @"1", @"*.txt"] currentDirectory:dir];
        REQUIRE(cl.line == 12 && cl.column == 5 && cl.position == -1 && [cl.language isEqualToString:@"python"] && [cl.udl isEqualToString:@"My UDL"]);
        REQUIRE(cl.readOnly && cl.noSession && cl.noTabBar && cl.alwaysOnTop && cl.multiInst && [cl.titleAdd isEqualToString:@"Build 7"]);
        REQUIRE(cl.hasX && cl.x == 40 && cl.hasY && cl.y == 60 && cl.ghostSpeed == 3 && [cl.ghostText isEqualToString:@"hello"]);
        NSArray *expected = @[[dir stringByAppendingPathComponent:@"a.txt"].stringByStandardizingPath];
        REQUIRE([cl.files isEqualToArray:expected]);                      // wildcard, non-recursive; "-key value" skipped
        cl = [TPCommandLine parseArguments:@[@"-r", @"*.txt", @"-p7", @"rel.md"] currentDirectory:dir];
        REQUIRE(cl.recursive && cl.position == 7 && cl.files.count == 3 && [cl.files.lastObject hasSuffix:@"/rel.md"]);  // -r: sub/c.txt too
        REQUIRE([[TPCommandLine commandLineFromPropertyList:cl.propertyList].files isEqualToArray:cl.files]);   // forwarding round trip
        // the real binary: --help prints the usage and exits without starting the UI
        NSTask *t = [NSTask new];
        t.executableURL = [NSBundle mainBundle].executableURL;
        t.arguments = @[@"--help"];
        NSPipe *pipe = [NSPipe pipe];
        t.standardOutput = pipe;
        REQUIRE([t launchAndReturnError:nil]);
        NSData *out = [pipe.fileHandleForReading readDataToEndOfFile];
        [t waitUntilExit];
        NSString *help = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding];
        REQUIRE(t.terminationStatus == 0 && [help hasPrefix:@"Usage:"] && [help containsString:@"-openSession"]);
        REQUIRE(exec(IDM_CMDLINEARGUMENTS) && [g_lastPrompt isEqualToString:@"Command Line Arguments"]);
    });
    run(@"T-CMD-002", @"Command line options applied: -n/-c/-p, -l, -ro, -monitor, -titleAdd, -notabbar, -alwaysOnTop, -x/-y, folders, -openSession, -fullReadOnly*", ^{
        NSString *dir = tmpPath(@"cmdapply");
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *f1 = [dir stringByAppendingPathComponent:@"script.txt"];
        writeBytes(f1, "line1\nline2\n    line3 here\nline4\n");
        TPCommandLine *cl = [TPCommandLine parseArguments:@[@"-n3", @"-c5", @"-lpython", @"-ro", @"-titleAdd=CI", @"-notabbar", @"-alwaysOnTop", f1]
                                         currentDirectory:dir];
        NSArray *opened = [c applyCommandLine:cl];
        REQUIRE(opened.count == 1 && c.currentDocument == opened[0]);
        TPDocument *d = opened[0];
        REQUIRE([d.languageId isEqualToString:@"python"] && d.userReadOnly && SCI(c.editor, SCI_GETREADONLY));
        sptr_t pos = SCI(c.editor, SCI_GETCURRENTPOS);
        REQUIRE(SCI(c.editor, SCI_LINEFROMPOSITION, pos) == 2 && SCI(c.editor, SCI_GETCOLUMN, pos) == 4);
        REQUIRE([c.window.title hasSuffix:@" - Textpad++ - CI"] && c.mainPane.tabBar.hidden && c.window.level == NSFloatingWindowLevel);
        c.titleAddition = nil; c.tabBarForcedHidden = NO; c.window.level = NSNormalWindowLevel;
        // -p (0-based position), folder argument (its files), -monitor
        NSString *sub = [dir stringByAppendingPathComponent:@"folder"];
        [fm createDirectoryAtPath:sub withIntermediateDirectories:YES attributes:nil error:nil];
        writeBytes([sub stringByAppendingPathComponent:@"x1.txt"], "x1");
        writeBytes([sub stringByAppendingPathComponent:@"x2.txt"], "x2");
        opened = [c applyCommandLine:[TPCommandLine parseArguments:@[@"-p3", @"-monitor", sub] currentDirectory:dir]];
        REQUIRE(opened.count == 2 && ((TPDocument *)opened[1]).monitoring && SCI(c.editor, SCI_GETCURRENTPOS) == 2);   // clamped to the length
        for (TPDocument *x in opened) x.monitoring = NO;
        // -openSession
        NSString *sess = [dir stringByAppendingPathComponent:@"s.xml"];
        REQUIRE([[TPSession shared] saveSessionToPath:sess controller:c includeBackups:NO]);
        NSArray *sessArgs = @[@"-openSession", sess];
        REQUIRE([c applyCommandLine:[TPCommandLine parseArguments:sessArgs currentDirectory:dir]].count == 0);
        // -fullReadOnlySavingForbidden: every new file read-only, R/O toggle and saving disabled
        [c applyCommandLine:[TPCommandLine parseArguments:@[@"-fullReadOnlySavingForbidden"] currentDirectory:dir]];
        NSString *f2 = [dir stringByAppendingPathComponent:@"other.txt"];
        writeBytes(f2, "x");
        TPDocument *o = [c openFile:f2];
        REQUIRE(o.userReadOnly && ![reg isEnabled:IDM_EDIT_TOGGLEREADONLY] && ![reg isEnabled:IDM_EDIT_CLEARREADONLYFORALLDOCS]);
        REQUIRE([c saveDocument:o] == TPSaveFailed);
        c.forceReadOnly = NO; c.savingForbidden = NO;
        o.userReadOnly = NO; d.userReadOnly = NO;
    });
    run(@"T-CMD-003", @"Ghost typing (-qt, -qSpeed3, -l), new-instance commands, multi-instance preference, -nosession keeps session.xml", ^{
        __block BOOL finished = NO;
        TPCommandLine *cl = [TPCommandLine parseArguments:@[@"-qt=def f(x):\n    return x", @"-qSpeed3", @"-lpython"] currentDirectory:NSTemporaryDirectory()];
        cl.ghostText = nil;                                               // type through ghostType to wait for completion
        [c applyCommandLine:cl];
        [c newDocument];
        exec(IDM_LANG_PYTHON);
        [c ghostType:@"def f(x):\n    return x" speed:3 completion:^{ finished = YES; }];
        NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:5];
        while (!finished && [limit timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        REQUIRE(finished);
        REQUIRE_EQ_STR(text(), "def f(x):\n    return x");
        REQUIRE([c.currentDocument.languageId isEqualToString:@"python"]);
        // View > Move/Clone > Open in New Instance: a second process with -multiInst -nosession <file>
        NSString *f = tmpPath(@"inst.txt");
        writeBytes(f, "x");
        [c openFile:f];
        REQUIRE(exec(IDM_VIEW_LOAD_IN_NEW_INSTANCE));
        REQUIRE([c.lastNewInstanceArguments isEqualToArray:(@[@"-multiInst", @"-nosession", f])]);
        REQUIRE(exec(IDM_VIEW_GOTO_NEW_INSTANCE) && ![c documentForPath:f]);   // moved: closed here
        REQUIRE([TPPrefs i:@"pref.multiInstance"] == 0);                 // upstream default: mono-instance
        // -nosession: nothing restored, session.xml untouched on quit
        TPSession *s = [TPSession shared];
        NSString *before = [NSString stringWithContentsOfFile:s.sessionPath encoding:NSUTF8StringEncoding error:nil];
        s.disabled = YES;
        REQUIRE(![s restoreIntoController:c]);
        [s writeSnapshotForController:c];
        NSString *after = [NSString stringWithContentsOfFile:s.sessionPath encoding:NSUTF8StringEncoding error:nil];
        REQUIRE((before == nil && after == nil) || [before isEqualToString:after]);
        s.disabled = NO;
    });

    run(@"T-DARK-001", @"Dark Mode tones (upstream offsets) and Customized tone colours in the chrome palette", ^{
        auto hex = [](NSColor *c) {
            NSColor *s = [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            return (int)lround(s.redComponent * 255) << 16 | (int)lround(s.greenComponent * 255) << 8 | (int)lround(s.blueComponent * 255);
        };
        [TPPrefs set:@1 forKey:@"pref.darkMode"];
        REQUIRE([TPPrefs i:@"pref.darkTone"] == 0 && hex([TPChrome barBackground]) == 0x202020);
        [TPPrefs set:@1 forKey:@"pref.darkTone"];                           // red: +0x100000, edges +0x1C1C1C too
        REQUIRE(hex([TPChrome barBackground]) == 0x302020 && hex([TPChrome border]) == 0x404040 + 0x1C1C1C + 0x100000);
        [TPPrefs set:@3 forKey:@"pref.darkTone"];                           // blue: +0x000020
        REQUIRE(hex([TPChrome barBackground]) == 0x202040);
        [TPPrefs set:@7 forKey:@"pref.darkTone"];                           // customized
        [TPPrefs set:@"123456" forKey:@"pref.darkCustom.background"];
        [TPPrefs set:@"ABCDEF" forKey:@"pref.darkCustom.text"];
        REQUIRE(hex([TPChrome barBackground]) == 0x123456 && hex([TPChrome statusText]) == 0xABCDEF);
        [TPPrefs set:@0 forKey:@"pref.darkMode"];
        REQUIRE(hex([TPChrome barBackground]) == 0xF5F5F5);                  // light mode ignores tones
    });
    run(@"T-CLOUD-001", @"Settings on cloud: the folder is seeded, preferences.plist exported/imported, shortcuts.xml written there", ^{
        TPSession *s = [TPSession shared];
        NSString *cloud = tmpPath(@"cloud-drive");
        [[NSFileManager defaultManager] createDirectoryAtPath:cloud withIntermediateDirectories:YES attributes:nil error:nil];
        REQUIRE(!s.cloudActive && [s.settingsDirectory isEqualToString:s.supportDirectory]);
        [TPPrefs set:cloud forKey:@"pref.cloudPath"];                      // seeds <cloud>/Textpad++ with the current settings
        NSString *dir = [cloud stringByAppendingPathComponent:@"Textpad++"];
        REQUIRE([[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingPathComponent:@"shortcuts.xml"]]);
        REQUIRE([[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingPathComponent:@"preferences.plist"]]);
        [s reloadSettingsDirectory];                                       // what the next launch does
        REQUIRE(s.cloudActive && [s.settingsDirectory isEqualToString:dir]);
        [TPPrefs set:@6 forKey:@"pref.tabSizeDefault"];                    // any change is exported
        NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:@"preferences.plist"]];
        REQUIRE([plist[@"pref.tabSizeDefault"] intValue] == 6 && !plist[@"pref.cloudPath"]);
        NSMutableDictionary *edited = [plist mutableCopy];                 // another Mac changed it
        edited[@"pref.autocFromLen"] = @4;
        [edited writeToFile:[dir stringByAppendingPathComponent:@"preferences.plist"] atomically:YES];
        REQUIRE([s importPreferencesFromCloud] && [TPPrefs i:@"pref.autocFromLen"] == 4);
        [[NSFileManager defaultManager] removeItemAtPath:[dir stringByAppendingPathComponent:@"shortcuts.xml"] error:nil];
        [c shortcutsDidChange];                                            // settings files go to the cloud folder
        REQUIRE([[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingPathComponent:@"shortcuts.xml"]]);
        REQUIRE([[NSFileManager defaultManager] fileExistsAtPath:[s.supportDirectory stringByAppendingPathComponent:@"session.xml"]] ||
                ![[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingPathComponent:@"session.xml"]]);   // session stays local
        [TPPrefs set:@"" forKey:@"pref.cloudPath"];
        [s reloadSettingsDirectory];
        REQUIRE(!s.cloudActive && [s.settingsDirectory isEqualToString:s.supportDirectory]);
    });

    run(@"T-ACC-001", @"Accessibility: tab bar is a tab group of tabs (select / Close actions), labelled toolbar buttons, status bar texts", ^{
        [c closeAll_forTests];
        [c newDocument];
        [c newDocument];
        TPTabBarView *tb = c.mainPane.tabBar;
        NSArray *tabs = tb.accessibilityChildren;
        REQUIRE(tb.isAccessibilityElement && [tb.accessibilityRole isEqualToString:NSAccessibilityTabGroupRole]);
        REQUIRE(tabs.count == c.mainPane.documents.count && tabs.count >= 2);
        NSAccessibilityElement *first = tabs.firstObject;
        REQUIRE([first.accessibilityRole isEqualToString:NSAccessibilityRadioButtonRole] && [first.accessibilitySubrole isEqualToString:NSAccessibilityTabButtonSubrole]);
        REQUIRE([first.accessibilityLabel isEqualToString:c.mainPane.documents.firstObject.tabLabel]);
        REQUIRE([first accessibilityPerformPress] && c.currentDocument == c.mainPane.documents.firstObject);   // VoiceOver "press" selects
        REQUIRE([[tb.accessibilityChildren.firstObject accessibilityValue] isEqual:@1]);
        NSUInteger before = c.mainPane.documents.count;
        NSAccessibilityCustomAction *close = [tb.accessibilityChildren.lastObject accessibilityCustomActions].firstObject;
        REQUIRE([close.name isEqualToString:@"Close"] && close.handler() && c.mainPane.documents.count == before - 1);
        NSView *toolbar = (NSView *)c.toolbar;
        REQUIRE([toolbar.accessibilityRole isEqualToString:NSAccessibilityToolbarRole]);
        NSUInteger labelled = 0;
        for (NSView *b in toolbar.subviews) if ([b isKindOfClass:[NSButton class]] && b.accessibilityLabel.length) ++labelled;
        NSUInteger buttons = 0;
        for (NSView *b in toolbar.subviews) if ([b isKindOfClass:[NSButton class]]) ++buttons;
        REQUIRE(labelled >= 20 && labelled == buttons);
        [c refreshUI];
        NSArray *parts = c.statusBar.accessibilityChildren;
        REQUIRE(parts.count == 6 && [[parts[4] accessibilityValue] isEqualToString:[c.statusBar textForPart:4]] && [[parts[2] accessibilityLabel] isEqualToString:@"Position"]);
    });
    run(@"T-SESS-KILL-001", @"Crash recovery: a separate Textpad++ process is killed with SIGKILL; the next launch restores unsaved text and edits", ^{
        NSString *dir = tmpPath(@"killtest");
        [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        writeBytes([dir stringByAppendingPathComponent:@"edited.txt"], "original\n");
        auto launch = [&](NSString *phase) {
            NSTask *t = [NSTask new];
            t.executableURL = [NSBundle mainBundle].executableURL;
            // argument domain: snapshot + session on for the child without touching saved settings
            t.arguments = @[phase, dir, @"-SessionSnapshot", @"YES", @"-RememberSession", @"YES"];
            t.standardOutput = [NSFileHandle fileHandleWithNullDevice];
            t.standardError = [NSFileHandle fileHandleWithNullDevice];
            return [t launchAndReturnError:nil] ? t : nil;
        };
        NSTask *p1 = launch(@"--crash-phase1");
        REQUIRE(p1 != nil);
        NSString *ready = [dir stringByAppendingPathComponent:@"ready"];
        for (int i = 0; i < 300 && ![[NSFileManager defaultManager] fileExistsAtPath:ready]; ++i) [NSThread sleepForTimeInterval:0.1];
        REQUIRE([[NSFileManager defaultManager] fileExistsAtPath:ready]);
        kill(p1.processIdentifier, SIGKILL);                                  // no chance to save or clean up
        [p1 waitUntilExit];
        REQUIRE(p1.terminationReason == NSTaskTerminationReasonUncaughtSignal && p1.terminationStatus == SIGKILL);
        NSTask *p2 = launch(@"--crash-phase2");
        REQUIRE(p2 != nil);
        for (int i = 0; i < 300 && p2.isRunning; ++i) [NSThread sleepForTimeInterval:0.1];
        if (p2.isRunning) { [p2 terminate]; fail = @"phase 2 did not finish"; return; }
        NSString *result = [NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:@"result.txt"] encoding:NSUTF8StringEncoding error:nil];
        if (![result isEqualToString:@"OK"]) { fail = result ?: @"no result"; return; }
    });
