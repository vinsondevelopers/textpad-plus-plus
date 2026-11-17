// Textpad++ — acceptance tests for the panels and the remaining features (stage 4).
// Included inside +[TPSelfTest runWithController:output:]. GPL-3.0-or-later.

    run(@"T-PANEL-001", @"Document List: lists both views, click activates, Ext./Path columns, context menu commands, View menu toggle", ^{
        [c closeAll_forTests];
        NSString *a = tmpPath(@"alpha.cpp"), *b = tmpPath(@"beta.txt");
        writeBytes(a, "int a;\n"); writeBytes(b, "b\n");
        [c openFile:a]; [c openFile:b];
        REQUIRE(exec(IDM_VIEW_DOCLIST) && [reg isChecked:IDM_VIEW_DOCLIST] && [c.docks isPanelVisible:@"doclist"]);
        TPDocumentListPanel *dl = c.documentListPanel;
        REQUIRE(!dl.panelView.superview.hidden && c.docks.leftDock.hidden == NO);
        NSArray *names = [dl.rows valueForKey:@"displayName"];
        REQUIRE([names containsObject:@"alpha.cpp"] && [names containsObject:@"beta.txt"]);
        NSInteger ai = (NSInteger)[names indexOfObject:@"alpha.cpp"];
        REQUIRE([[dl.table viewAtColumn:0 row:ai makeIfNecessary:YES] textField].stringValue.length);   // "alpha" (+ ".cpp" in Ext.)
        [dl.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)ai] byExtendingSelection:NO];
        [dl activateRow:ai];                                              // what a click on the row does
        REQUIRE([c.currentDocument.displayName isEqualToString:@"alpha.cpp"]);
        [c refreshUI];                                                    // the list follows the current document
        REQUIRE(dl.table.selectedRow == (NSInteger)[dl.rows indexOfObject:c.currentDocument]);
        REQUIRE(exec(IDM_DOCLIST_COPYNAMES));
        REQUIRE([[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:@"alpha.cpp"]);
        REQUIRE(exec(IDM_DOCLIST_COPYPATHS) && [[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqualToString:a]);
        [TPPrefs set:@YES forKey:@"pref.docListPath"];
        [dl reload];
        REQUIRE(![dl.table tableColumnWithIdentifier:@"path"].hidden);
        REQUIRE(exec(IDM_DOCLIST_FILESCLOSE) && ![c documentForPath:a] && [c documentForPath:b]);
        REQUIRE(exec(IDM_VIEW_DOCLIST) && ![c.docks isPanelVisible:@"doclist"] && c.docks.leftDock.hidden);
    });
    run(@"T-PANEL-002", @"Document Map: shares the current document at zoom -10, the zone follows scrolling, a click centres the editor", ^{
        [c newDocument];
        std::string big;
        for (int i = 0; i < 600; i++) big += "line " + std::to_string(i) + " some text\n";
        setText(big);
        c.window.alphaValue = 0;
        REQUIRE(exec(IDM_VIEW_DOC_MAP) && [reg isChecked:IDM_VIEW_DOC_MAP]);
        TPDocumentMapPanel *m = c.documentMapPanel;
        REQUIRE(SCI(m.mapView, SCI_GETDOCPOINTER) == c.currentDocument.sciDoc && SCI(m.mapView, SCI_GETZOOM) == -10);
        SCI(c.editor, SCI_SETFIRSTVISIBLELINE, 0);
        [m sync];
        NSRect z0 = m.visibleZone;
        REQUIRE(!NSIsEmptyRect(z0));
        SCI(c.editor, SCI_SETFIRSTVISIBLELINE, 400);
        [m sync];
        REQUIRE(SCI(m.mapView, SCI_GETFIRSTVISIBLELINE) > 0 || m.visibleZone.origin.y > z0.origin.y);
        SCI(c.editor, SCI_SETFIRSTVISIBLELINE, 0);
        [m sync];
        [m scrollEditorToMapPoint:NSMakePoint(10, NSHeight(m.mapView.bounds) - 5)];   // near the bottom of the map
        REQUIRE(SCI(c.editor, SCI_GETFIRSTVISIBLELINE) > 50);
        TPDocument *d = c.currentDocument;
        [c newDocument];                                                  // follows the active document
        [c refreshUI];
        REQUIRE(SCI(m.mapView, SCI_GETDOCPOINTER) == c.currentDocument.sciDoc);
        (void)d;
        exec(IDM_VIEW_DOC_MAP);
        REQUIRE(![c.docks isPanelVisible:@"docmap"] && SCI(m.mapView, SCI_GETDOCPOINTER) != c.currentDocument.sciDoc);   // reference dropped
    });
    run(@"T-PANEL-003", @"Function List: upstream parsers (C++ class ranges + functions, Python), comments skipped, sort, filter, navigation, caret marking", ^{
        NSString *cpp = tmpPath(@"shapes.cpp");
        writeBytes(cpp, "// int notAFunction(int x) { return x; }\n"
                        "int add(int a, int b)\n{\n    return a + b;\n}\n\n"
                        "class Shape\n{\npublic:\n    double area() const\n    {\n        return 0;\n    }\n    void draw()\n    {\n    }\n};\n\n"
                        "void Shape::move(int dx)\n{\n}\n\n"
                        "static int helper(void)\n{\n    return 1;\n}\n");
        [c openFile:cpp];
        REQUIRE(exec(IDM_VIEW_FUNC_LIST) && [reg isChecked:IDM_VIEW_FUNC_LIST]);
        TPFunctionListPanel *fl = c.functionListPanel;
        fl.sorted = NO; fl.filter = @"";
        [fl reload];
        NSArray *names = fl.leafNames;
        NSString *all = [names componentsJoinedByString:@", "];
        if (![names containsObject:@"add"] || ![names containsObject:@"helper"] || ![all containsString:@"Shape::"] || [all containsString:@"notAFunction"]) {
            fail = [@"C++ entries: " stringByAppendingString:all]; return;
        }
        fl.sorted = YES;                                                  // A↓Z
        NSArray *sortedNames = fl.leafNames;
        REQUIRE([sortedNames.firstObject compare:sortedNames.lastObject options:NSCaseInsensitiveSearch] != NSOrderedDescending);
        fl.filter = @"help";                                              // search box: matching entries only
        REQUIRE([fl.leafNames isEqualToArray:@[@"helper"]]);
        fl.filter = @"";
        SCI(c.editor, SCI_GOTOPOS, 0);
        REQUIRE([fl openEntryNamed:@"helper"]);                           // double-click: the caret goes to the function
        std::string caretLine = sciGetLine(c.editor, SCI(c.editor, SCI_LINEFROMPOSITION, SCI(c.editor, SCI_GETCURRENTPOS)));
        REQUIRE(caretLine.find("helper") != std::string::npos);
        SCI(c.editor, SCI_GOTOLINE, 3);                                   // inside add()
        [fl editorViewChanged];
        REQUIRE([fl.markedEntryName isEqualToString:@"add"]);
        NSString *py = tmpPath(@"mod.py");
        writeBytes(py, "def top(x):\n    return x\n\nclass Foo:\n    def method(self):\n        pass\n");
        [c openFile:py];
        [c refreshUI];                                                    // another document: re-parsed
        all = [fl.leafNames componentsJoinedByString:@", "];
        if (![all containsString:@"top"] || ![all containsString:@"method"]) { fail = [@"Python entries: " stringByAppendingString:all]; return; }
        [c newDocument];                                                  // Normal text: no parser, empty tree
        [c refreshUI];
        REQUIRE(fl.leafNames.count == 0);
        exec(IDM_VIEW_FUNC_LIST);
        REQUIRE(![c.docks isPanelVisible:@"funclist"]);
        fl.sorted = NO;
    });
    run(@"T-PANEL-004", @"Folder as Workspace: roots, folders first, open on double-click, locate current file, live folder updates, context commands", ^{
        NSString *root = tmpPath(@"fawroot");
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:root error:nil];
        [fm createDirectoryAtPath:[root stringByAppendingPathComponent:@"src/deep"] withIntermediateDirectories:YES attributes:nil error:nil];
        writeBytes([root stringByAppendingPathComponent:@"b.txt"], "b");
        writeBytes([root stringByAppendingPathComponent:@"a.md"], "a");
        writeBytes([root stringByAppendingPathComponent:@".hidden"], "h");
        writeBytes([root stringByAppendingPathComponent:@"src/deep/main.c"], "int main(void){return 0;}\n");
        TPFolderAsWorkspacePanel *faw = c.folderAsWorkspacePanel;
        [faw removeAllRoots];
        [c openFile:[root stringByAppendingPathComponent:@"src/deep/main.c"]];
        REQUIRE(exec(IDM_FILE_CONTAININGFOLDERASWORKSPACE));              // Open Containing Folder > Folder as Workspace
        REQUIRE([c.docks isPanelVisible:@"faw"] && [reg isChecked:IDM_VIEW_FILEBROWSER]);
        REQUIRE([faw.rootPaths containsObject:[root stringByAppendingPathComponent:@"src/deep"].stringByStandardizingPath]);
        REQUIRE([faw.selectedNode.name isEqualToString:@"main.c"]);
        [faw removeAllRoots];
        [faw addRootFolder:root];
        [faw expandAll];
        NSMutableArray *names = [NSMutableArray array];
        for (NSInteger r = 0; r < faw.outline.numberOfRows; ++r) [names addObject:[[faw.outline itemAtRow:r] name]];
        NSArray *expectedNames = @[@"fawroot", @"src", @"deep", @"main.c", @"a.md", @"b.txt"];
        REQUIRE([names isEqualToArray:expectedNames]);                    // folders first, hidden files skipped
        [faw collapseAll];
        [c openFile:[root stringByAppendingPathComponent:@"b.txt"]];
        [faw locateCurrentFile];
        REQUIRE([faw.selectedNode.name isEqualToString:@"b.txt"]);
        [c closeAll_forTests];
        REQUIRE([faw openNode:faw.selectedNode] && [c.currentDocument.displayName isEqualToString:@"b.txt"]);
        writeBytes([root stringByAppendingPathComponent:@"c.log"], "c");   // a new file appears (FSEvents -> refreshFolder)
        [faw refreshFolder:root];
        BOOL found = NO;
        for (NSInteger r = 0; r < faw.outline.numberOfRows; ++r) if ([[[faw.outline itemAtRow:r] name] isEqualToString:@"c.log"]) found = YES;
        REQUIRE(found);
        NSMenu *menu = faw.outline.menu;
        [menu.delegate menuNeedsUpdate:menu];                             // empty-area menu
        REQUIRE([menu itemWithTitle:@"Add"] && [menu itemWithTitle:@"Remove All"]);
        REQUIRE([[[NSUserDefaults standardUserDefaults] stringArrayForKey:@"faw.roots"] containsObject:root.stringByStandardizingPath]);
        [faw removeRoot:root];
        REQUIRE(faw.rootPaths.count == 0);
        exec(IDM_VIEW_FILEBROWSER);
        REQUIRE(![c.docks isPanelVisible:@"faw"]);
    });
    run(@"T-PANEL-005", @"Project Panels: projects, folders, files, upstream workspace XML with relative paths, reopen, move/remove, Find in Projects", ^{
        NSString *dir = tmpPath(@"wsproj");
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:dir error:nil];
        [fm createDirectoryAtPath:[dir stringByAppendingPathComponent:@"lib"] withIntermediateDirectories:YES attributes:nil error:nil];
        writeBytes([dir stringByAppendingPathComponent:@"main.c"], "needle in main\n");
        writeBytes([dir stringByAppendingPathComponent:@"lib/util.c"], "no match\nneedle twice needle\n");
        TPProjectPanel *pp = [c projectPanel:1];
        nextAnswer = @"No";
        [pp newWorkspace];
        REQUIRE(exec(IDM_VIEW_PROJECT_PANEL_1) && [c.docks isPanelVisible:@"project1"]);
        TPProjNode *proj = [pp addProjectNamed:@"Demo"];
        [pp addFiles:@[[dir stringByAppendingPathComponent:@"main.c"]] to:proj];
        TPProjNode *folder = [pp addFolderNamed:@"Sources" to:proj];
        [pp addFilesFromDirectory:[dir stringByAppendingPathComponent:@"lib"] to:folder];
        REQUIRE(pp.dirty && pp.allFilePaths.count == 2);
        NSString *ws = [dir stringByAppendingPathComponent:@"demo.workspace"];
        REQUIRE([pp saveWorkspaceTo:ws asCopy:NO] && !pp.dirty);
        NSString *xml = [NSString stringWithContentsOfFile:ws encoding:NSUTF8StringEncoding error:nil];
        REQUIRE([xml containsString:@"<Project name=\"Demo\">"] && [xml containsString:@"<File name=\"main.c\""] && [xml containsString:@"<File name=\"lib/util.c\""]);
        [pp moveNode:[pp nodeNamed:@"Sources"] by:-1];                     // Move Up
        REQUIRE([proj.children.firstObject.name isEqualToString:@"Sources"] && pp.dirty);
        REQUIRE([pp openWorkspace:ws]);                                    // re-read from disk (the move was not saved)
        REQUIRE([[pp nodeNamed:@"Demo"].children.firstObject.name isEqualToString:@"main.c"] && pp.allFilePaths.count == 2);
        REQUIRE([pp openNode:[pp nodeNamed:@"util.c"]] && [c.currentDocument.displayName isEqualToString:@"util.c"]);
        // Find in Projects: the files of the checked Project Panels
        [c showFindInProjectsForPanel:1];
        TPFindReplaceController *f = c.findController;
        f.window.alphaValue = 0;
        REQUIRE(f.currentTab == TPFindTabFindInProjects && f.project1 && !f.project2);
        [f setFindText:@"needle"];
        tpp::search::Options o; o.find = "needle"; o.mode = tpp::search::Mode::Normal;
        [f setOptions:o];
        REQUIRE([f findInFiles] == 3);
        [pp removeNode:[pp nodeNamed:@"Sources"]];
        REQUIRE(pp.allFilePaths.count == 1 && pp.dirty);
        nextAnswer = @"No";
        [pp newWorkspace];                                                 // dirty -> asked, "No" discards
        REQUIRE(pp.root.children.count == 0 && !pp.dirty);
        [f showTab:TPFindTabFind];
        [f.window orderOut:nil];
        exec(IDM_VIEW_PROJECT_PANEL_1);
    });
    run(@"T-PANEL-006", @"Character Panel (upstream tables) inserts characters / HTML codes; Clipboard History keeps copies newest first and pastes them", ^{
        [c newDocument];
        REQUIRE(exec(IDM_EDIT_CHAR_PANEL) && [c.docks isPanelVisible:@"charpanel"] && [reg isChecked:IDM_EDIT_CHAR_PANEL]);
        TPCharacterPanel *cp = c.characterPanel;
        REQUIRE([[cp textForColumn:2 row:9] isEqualToString:@"TAB"] && [[cp textForColumn:2 row:233] isEqualToString:@"é"]);
        REQUIRE([[cp textForColumn:3 row:233] isEqualToString:@"&eacute;"] && [[cp textForColumn:4 row:233] isEqualToString:@"&#233;"]);
        REQUIRE([[cp textForColumn:5 row:128] isEqualToString:@"&#x20ac;"] && [[cp textForColumn:1 row:255] isEqualToString:@"FF"]);
        [cp insertCharacter:233];
        [cp insertCharacter:'A'];
        [cp insertText:[cp textForColumn:3 row:38]];                      // &amp;
        REQUIRE_EQ_STR(text(), "\xC3\xA9" "A&amp;");                      // é stored as UTF-8 in a Unicode document
        exec(IDM_EDIT_CHAR_PANEL);
        REQUIRE(![c.docks isPanelVisible:@"charpanel"]);
        REQUIRE(exec(IDM_EDIT_CLIPBOARDHISTORY_PANEL) && [c.docks isPanelVisible:@"cliphistory"]);
        TPClipboardHistoryPanel *ch = c.clipboardHistoryPanel;
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents]; [pb setString:@"first copy" forType:NSPasteboardTypeString]; [ch checkPasteboard];
        [pb clearContents]; [pb setString:@"second copy" forType:NSPasteboardTypeString]; [ch checkPasteboard];
        [pb clearContents]; [pb setString:@"first copy" forType:NSPasteboardTypeString]; [ch checkPasteboard];   // moves to the top
        REQUIRE(ch.entries.count >= 2 && [ch.entries[0] isEqualToString:@"first copy"] && [ch.entries[1] isEqualToString:@"second copy"]);
        setText("");
        REQUIRE([ch pasteEntryAtIndex:1]);
        REQUIRE_EQ_STR(text(), "second copy");
        exec(IDM_EDIT_CLIPBOARDHISTORY_PANEL);
    });
    run(@"T-SRCH-INC-001", @"Incremental Search bar: grows from the selection start, Enter/Shift+Enter, wrap messages, not found, Highlight all, Count", ^{
        [c newDocument];
        setText("alpha beta alphabet ALPHA end");
        SCI(c.editor, SCI_GOTOPOS, 0);
        TPIncrementalSearchBar *bar = c.incrementalSearchBar;
        REQUIRE(exec(IDM_SEARCH_FINDINCREMENT) && !bar.hidden);
        bar.matchCaseCheck.state = NSControlStateValueOff; bar.countCheck.state = NSControlStateValueOn; bar.highlightAllCheck.state = NSControlStateValueOn;
        bar.field.stringValue = @"al"; [bar textChanged];
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 0 && SCI(c.editor, SCI_GETSELECTIONEND) == 2);
        bar.field.stringValue = @"alpha"; [bar textChanged];             // same start, longer match
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 0 && SCI(c.editor, SCI_GETSELECTIONEND) == 5);
        REQUIRE([bar.statusText isEqualToString:@"1/3"]);                 // Count: alpha, alpha(bet), ALPHA
        SCI(c.editor, SCI_SETINDICATORCURRENT, TPP_INDIC_INC);
        REQUIRE(SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_INC, 20) == 1);   // Highlight all (case-insensitive)
        [bar findNext:YES];
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 11);
        [bar findNext:YES]; [bar findNext:YES];                           // ALPHA, then wraps to the first
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 0 && [bar.statusText containsString:@"Reached end of page, continued from top"]);
        [bar findNext:NO];
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 20 && [bar.statusText containsString:@"Reached top of page"]);
        bar.matchCaseCheck.state = NSControlStateValueOn;
        bar.field.stringValue = @"zzz"; [bar textChanged];
        REQUIRE([bar.statusText isEqualToString:@"Phrase not found"]);
        [bar close];
        REQUIRE(bar.hidden && SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_INC, 20) == 0);
    });
    run(@"T-SRCH-HL-001", @"Find dialog: live highlighting of 'Find what' matches while open (follows options and closes cleanly); transparency modes", ^{
        [c newDocument];
        setText("one two one TWO one\n");
        TPFindReplaceController *f = c.findController;
        f.window.alphaValue = 0;
        f.highlightMatches = YES;
        [f showTab:TPFindTabFind];
        tpp::search::Options o; o.find = "one"; o.mode = tpp::search::Mode::Normal;
        [f setOptions:o];
        [f updateMatchHighlighting];
        REQUIRE(SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_FINDDLG, 0) == 1 && SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_FINDDLG, 8) == 1);
        REQUIRE(SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_FINDDLG, 4) == 0);
        o.find = "two"; o.matchCase = true; [f setOptions:o]; [f updateMatchHighlighting];
        REQUIRE(SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_FINDDLG, 4) == 1 && SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_FINDDLG, 12) == 0);
        [f showTab:TPFindTabMark];                                        // only Find / Replace tabs highlight
        REQUIRE(SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_FINDDLG, 4) == 0);
        f.highlightMatches = NO;
        [f.window orderOut:nil];
        // transparency: "Always" makes the dialog translucent, none restores it
        f.window.alphaValue = 1;
        f.transparencyMode = 2;
        REQUIRE(f.window.alphaValue < 1 && [[NSUserDefaults standardUserDefaults] integerForKey:@"find.transparencyMode"] == 2);
        f.transparencyMode = 1;
        [f applyTransparencyActive:YES];
        REQUIRE(f.window.alphaValue == 1);
        [f applyTransparencyActive:NO];
        REQUIRE(f.window.alphaValue < 1);
        f.transparencyMode = 0;
        REQUIRE(f.window.alphaValue == 1);
        f.window.alphaValue = 0;
        [f showTab:TPFindTabFind];
        [f.window orderOut:nil];
    });
    run(@"T-EDIT-TAG-001", @"Matching tags (upstream XmlMatchedTagsHighlighter): open/close pair, nesting, attributes, self-closing, off in other languages", ^{
        [c newDocument];
        exec(IDM_LANG_HTML);
        setText("<div class=\"a\" id='b'><p>x</p><div>in</div></div>");
        SCI(c.editor, SCI_COLOURISE, 0, -1);
        auto tag = [&](sptr_t p) { return SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_TAGMATCH, p); };
        auto attr = [&](sptr_t p) { return SCI(c.editor, SCI_INDICATORVALUEAT, TPP_INDIC_TAGATTR, p); };
        SCI(c.editor, SCI_GOTOPOS, 2);                                    // inside the outer "<div"
        [c tagMatchInView:c.editor document:c.currentDocument];
        sptr_t outerClose = (sptr_t)std::string("<div class=\"a\" id='b'><p>x</p><div>in</div>").size();
        REQUIRE(tag(0) && tag(3) && tag(outerClose) && tag(outerClose + 4));   // "<div" + matching "</div>"
        REQUIRE(!tag(28));                                                 // the inner <div> is not the match
        REQUIRE(attr(5) && attr(16));                                      // class="a", id='b'
        [TPPrefs set:@NO forKey:@"pref.tagAttrs"];
        [c tagMatchInView:c.editor document:c.currentDocument];
        REQUIRE(!attr(5) && tag(0));
        setText("<br/><img src=\"x\" />");
        SCI(c.editor, SCI_COLOURISE, 0, -1);
        SCI(c.editor, SCI_GOTOPOS, 7);
        [c tagMatchInView:c.editor document:c.currentDocument];
        REQUIRE(tag(5) && !tag(0));                                        // self-closed <img .../>
        [TPPrefs set:@NO forKey:@"pref.tagMatch"];
        [c tagMatchInView:c.editor document:c.currentDocument];
        REQUIRE(!tag(5));
        [TPPrefs set:@YES forKey:@"pref.tagMatch"];
        exec(IDM_LANG_C);
        [c tagMatchInView:c.editor document:c.currentDocument];
        REQUIRE(!tag(5));
    });
    run(@"T-UI-CTX-001", @"Context menu from contextMenu.xml (upstream default), Edit Popup ContextMenu opens the user copy, edits apply on the next popup", ^{
        NSString *user = [[TPSession shared].settingsDirectory stringByAppendingPathComponent:@"contextMenu.xml"];
        [[NSFileManager defaultManager] removeItemAtPath:user error:nil];
        NSMenu *m = c.editor.menu;
        [m.delegate menuNeedsUpdate:m];
        REQUIRE([[m itemAtIndex:0].title isEqualToString:@"Cut"] && [m itemWithTitle:@"Style all occurrences of token"].submenu.numberOfItems == 5);
        REQUIRE([m itemWithTitle:@"Hide Lines"] != nil && [m itemWithTitle:@"Plugin commands"] == nil);   // plugin items absent: skipped
        REQUIRE(exec(IDM_SETTING_EDITCONTEXTMENU) && [c.currentDocument.path isEqualToString:user]);
        writeBytes(user, "<NotepadPlus><ScintillaContextMenu><Item MenuEntryName=\"Edit\" MenuItemName=\"Copy\" ItemNameAs=\"Copy it\"/>"
                         "<Item id=\"0\"/><Item FolderName=\"Case\" id=\"42016\"/><Item id=\"999999\"/></ScintillaContextMenu></NotepadPlus>");
        NSDate *later = [NSDate dateWithTimeIntervalSinceNow:5];
        [[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate: later} ofItemAtPath:user error:nil];
        [m.delegate menuNeedsUpdate:m];
        REQUIRE(m.numberOfItems == 3 && [[m itemAtIndex:0].title isEqualToString:@"Copy it"] && [m itemAtIndex:1].isSeparatorItem);
        REQUIRE([m itemWithTitle:@"Case"].submenu.numberOfItems == 1);   // unknown id 999999 skipped
        [[NSFileManager defaultManager] removeItemAtPath:user error:nil];
        [c closeAll_forTests];
    });
    run(@"T-UI-DND-001", @"Drag and drop: files open, a folder becomes a workspace (or its files open), a tab dropped on the other view moves / clones", ^{
        NSString *dir = tmpPath(@"dropdir");
        [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        writeBytes([dir stringByAppendingPathComponent:@"d1.txt"], "1");
        writeBytes([dir stringByAppendingPathComponent:@"d2.txt"], "2");
        NSString *single = tmpPath(@"dropped.txt");
        writeBytes(single, "x");
        REQUIRE([c openDroppedURLs:@[[NSURL fileURLWithPath:single]]] && [c.currentDocument.displayName isEqualToString:@"dropped.txt"]);
        [c.folderAsWorkspacePanel removeAllRoots];
        [c openDroppedURLs:@[[NSURL fileURLWithPath:dir]]];               // default: Folder as Workspace
        REQUIRE([c.folderAsWorkspacePanel.rootPaths containsObject:dir.stringByStandardizingPath] && ![c documentForPath:[dir stringByAppendingPathComponent:@"d1.txt"]]);
        [TPPrefs set:@YES forKey:@"pref.dropFolderOpenFiles"];
        [c openDroppedURLs:@[[NSURL fileURLWithPath:dir]]];
        REQUIRE([c documentForPath:[dir stringByAppendingPathComponent:@"d1.txt"]] && [c documentForPath:[dir stringByAppendingPathComponent:@"d2.txt"]]);
        [c.folderAsWorkspacePanel removeAllRoots];
        exec(IDM_VIEW_FILEBROWSER);
        // a tab dropped on the right half (second view hidden) / on the other view
        TPDocument *d = [c documentForPath:single];
        [c activateDocument:d inPane:c.mainPane];
        NSInteger idx = [c.mainPane indexOfDocument:d];
        NSPoint rightHalf = [c.mainPane convertPoint:NSMakePoint(NSWidth(c.mainPane.bounds) * 0.75, NSHeight(c.mainPane.bounds) / 2) toView:nil];
        [c tabBar:c.mainPane.tabBar didDropIndex:idx atWindowPoint:rightHalf copy:NO];
        REQUIRE([c.subPane indexOfDocument:d] != NSNotFound && [c.mainPane indexOfDocument:d] == NSNotFound && !c.subPane.hidden);
        NSPoint mainCentre = [c.mainPane convertPoint:NSMakePoint(NSWidth(c.mainPane.bounds) / 2, NSHeight(c.mainPane.bounds) / 2) toView:nil];
        [c tabBar:c.subPane.tabBar didDropIndex:[c.subPane indexOfDocument:d] atWindowPoint:mainCentre copy:YES];   // ⌥: clone
        REQUIRE([c.subPane indexOfDocument:d] != NSNotFound && [c.mainPane indexOfDocument:d] != NSNotFound);
        [c closeAll_forTests];
    });
    run(@"T-UI-TABS-001", @"Tab bar: multi-line rows grow the bar, vertical bar on the left edge, hit-testing through the rotation", ^{
        [c closeAll_forTests];
        for (int i = 0; i < 14; i++) { [c newDocument]; }
        TPTabBarView *tb = c.mainPane.tabBar;
        CGFloat oneRow = [tb heightForWidth:100000];
        [TPPrefs set:@YES forKey:@"pref.tabMultiline"];
        [c.mainPane reloadTabs];
        REQUIRE(tb.rowCount > 1 && NSHeight(tb.frame) > oneRow + 10);
        REQUIRE(NSMaxY(c.mainPane.editor.frame) <= NSMinY(tb.frame) + 0.5);   // the editor starts below the rows
        [TPPrefs set:@NO forKey:@"pref.tabMultiline"];
        [TPPrefs set:@YES forKey:@"pref.tabVertical"];
        [c.mainPane reloadTabs];
        REQUIRE(tb.frameCenterRotation == 90 && NSMinX(c.mainPane.editor.frame) >= oneRow - 1 && NSMinX(c.mainPane.editor.frame) < 60);
        NSRect r0 = [tb rectForTabAtIndex:0];
        NSPoint inWindow = [tb convertPoint:NSMakePoint(NSMidX(r0), NSMidY(r0)) toView:nil];
        REQUIRE([tb indexAtPoint:[tb convertPoint:inWindow fromView:nil]] == 0);
        NSPoint inPane = [c.mainPane convertPoint:inWindow fromView:nil];
        REQUIRE(inPane.x < NSMinX(c.mainPane.editor.frame));               // tab 0 lies in the left strip
        [TPPrefs set:@NO forKey:@"pref.tabVertical"];
        [c.mainPane reloadTabs];
        REQUIRE(tb.frameCenterRotation == 0);
        [c closeAll_forTests];
    });
    // ================================================================ remaining Preferences options (stage 4)
    run(@"T-PREF-C0-001", @"Editing 2 > Prevent control character (C0 code) typing: typed C0 / DEL dropped, other text kept; off types them", ^{
        [c newDocument];
        REQUIRE([TPPrefs b:@"pref.npcNoInputC0"]);                        // upstream default: on
        [c.editor.content insertText:@"a\u0001b\u001B\u007Fc" replacementRange:NSMakeRange(NSNotFound, 0)];
        [c.editor.content insertText:@"\u0007" replacementRange:NSMakeRange(NSNotFound, 0)];
        REQUIRE(text() == "abc");
        [TPPrefs set:@NO forKey:@"pref.npcNoInputC0"];
        [c.editor.content insertText:@"\u0001" replacementRange:NSMakeRange(NSNotFound, 0)];
        REQUIRE(text() == "abc\x01");
    });
    run(@"T-PREF-COLMULTI-001", @"Editing 2 > Column Selection to Multi-Editing: arrows turn a column selection into carets, Esc keeps one, ⌥⇧ extends", ^{
        [c newDocument];
        setText("abcd\nabcd\nabcd\n");
        auto key = [&](unsigned short code, NSString *chars, NSEventModifierFlags mods) {
            return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:mods timestamp:0 windowNumber:c.window.windowNumber
                                     context:nil characters:chars charactersIgnoringModifiers:chars isARepeat:NO keyCode:code];
        };
        auto rect = [&]() {
            SCI(c.editor, SCI_SETRECTANGULARSELECTIONANCHOR, 1);
            SCI(c.editor, SCI_SETRECTANGULARSELECTIONCARET, 12);           // line 2, column 2
        };
        rect();
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONMODE) == SC_SEL_RECTANGLE && SCI(c.editor, SCI_GETSELECTIONS) == 3);
        NSEvent *right = key(kVK_RightArrow, @"", NSEventModifierFlagNumericPad | NSEventModifierFlagFunction);
        REQUIRE(![c editor:c.editor prepareColumnSelectionForKey:key(kVK_RightArrow, @"", NSEventModifierFlagOption | NSEventModifierFlagShift)]);
        REQUIRE([c editor:c.editor prepareColumnSelectionForKey:right]);
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONMODE) == SC_SEL_STREAM && SCI(c.editor, SCI_GETSELECTIONS) == 3);
        [c.editor.content keyDown:right];                                  // Scintilla: one caret per line, at the right edge
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONS) == 3 && SCI(c.editor, SCI_GETSELECTIONEMPTY));
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONNCARET, 0) == 2 && SCI(c.editor, SCI_GETSELECTIONNCARET, 1) == 7 && SCI(c.editor, SCI_GETSELECTIONNCARET, 2) == 12);
        [c.editor.content keyDown:right];
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONNCARET, 0) == 3 && SCI(c.editor, SCI_GETSELECTIONNCARET, 2) == 13);
        rect();
        REQUIRE([c editor:c.editor prepareColumnSelectionForKey:key(kVK_Escape, @"\u001B", 0)]);
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONS) == 1 && SCI(c.editor, SCI_GETSELECTIONEMPTY) && SCI(c.editor, SCI_GETCURRENTPOS) == 12);
        [TPPrefs set:@NO forKey:@"pref.column2Multi"];
        rect();
        REQUIRE(![c editor:c.editor prepareColumnSelectionForKey:right] && SCI(c.editor, SCI_GETSELECTIONMODE) == SC_SEL_RECTANGLE);
    });
    run(@"T-PREF-RCLICK-001", @"Editing 1 > Keep selection on right-click: off moves the caret to a click outside the selection, on keeps it", ^{
        [c newDocument];
        setText("hello world\nsecond line\n");
        [c.editor layoutSubtreeIfNeeded];
        auto windowPointOf = [&](sptr_t pos) {
            CGFloat x = SCI(c.editor, SCI_POINTXFROMPOSITION, 0, pos) + 2, y = SCI(c.editor, SCI_POINTYFROMPOSITION, 0, pos) + SCI(c.editor, SCI_TEXTHEIGHT, 0) / 2;
            NSPoint o = c.editor.scrollView.contentView.bounds.origin;
            return [c.editor.content convertPoint:NSMakePoint(x + o.x, y + o.y) toView:nil];
        };
        SCI(c.editor, SCI_SETSEL, 0, 5);
        [c editor:c.editor rightClickAtWindowPoint:windowPointOf(2)];      // inside "hello": kept
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 0 && SCI(c.editor, SCI_GETSELECTIONEND) == 5);
        [c editor:c.editor rightClickAtWindowPoint:windowPointOf(14)];     // in "second": caret moves
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONEMPTY) && llabs(SCI(c.editor, SCI_GETCURRENTPOS) - 14) <= 1);
        [TPPrefs set:@YES forKey:@"pref.rightClickKeepsSel"];
        SCI(c.editor, SCI_SETSEL, 0, 5);
        [c editor:c.editor rightClickAtWindowPoint:windowPointOf(14)];
        REQUIRE(SCI(c.editor, SCI_GETSELECTIONSTART) == 0 && SCI(c.editor, SCI_GETSELECTIONEND) == 5);
    });
    run(@"T-PREF-2GB-001", @"Performance > 2GB+ warning: asks before opening (No cancels), Suppress opens without asking", ^{
        g_lastPrompt = nil;
        REQUIRE([c confirmOpeningFileOfSize:1000000] && g_lastPrompt == nil);
        nextAnswer = @"No";
        REQUIRE(![c confirmOpeningFileOfSize:2147483000ull] && [g_lastPrompt containsString:@"2GB+"]);   // + room for editing > INT_MAX
        NSString *huge = tmpPath(@"huge.bin");
        writeBytes(huge, "");
        REQUIRE(truncate(huge.fileSystemRepresentation, 2200000000LL) == 0);   // sparse: no disk space used
        g_lastPrompt = nil;
        REQUIRE([c openFile:huge] == nil && [g_lastPrompt containsString:@"huge file"]);
        [[NSFileManager defaultManager] removeItemAtPath:huge error:nil];
        [TPPrefs set:@YES forKey:@"pref.suppress2GB"];
        g_lastPrompt = nil;
        REQUIRE([c confirmOpeningFileOfSize:3000000000ull] && g_lastPrompt == nil);
    });
    run(@"T-PREF-TBCOLOR-001", @"Toolbar > Colorization of Fluent icons: Complete paints all, Partial only the accent blue, Default leaves them", ^{
        [TPPrefs set:@0 forKey:@"pref.darkMode"];
        [TPPrefs set:@0 forKey:@"pref.toolbarIconSet"];                    // Fluent UI: small
        auto count = [&](uint32_t rgb, NSInteger *opaque) {
            NSInteger hit = 0, all = 0;
            for (int cmd : {IDM_FILE_NEW, IDM_FILE_OPEN, IDM_FILE_SAVE, IDM_FILE_SAVEALL, IDM_EDIT_CUT, IDM_EDIT_PASTE, IDM_SEARCH_FIND, IDM_VIEW_WRAP, IDM_VIEW_DOC_MAP, IDM_VIEW_FUNC_LIST}) {
                NSImage *img = [c.toolbar imageForCommand:cmd];
                for (NSImageRep *r in img.representations) {
                    NSBitmapImageRep *b = [r isKindOfClass:NSBitmapImageRep.class] ? (NSBitmapImageRep *)r : nil;
                    if (!b || b.bitsPerSample != 8) continue;
                    const BOOL af = (b.bitmapFormat & NSBitmapFormatAlphaFirst) != 0;
                    for (NSInteger y = 0; y < b.pixelsHigh; ++y) for (NSInteger x = 0; x < b.pixelsWide; ++x) {
                        const unsigned char *p = b.bitmapData + y * b.bytesPerRow + x * (b.bitsPerPixel / 8);
                        int a = b.hasAlpha ? p[af ? 0 : b.samplesPerPixel - 1] : 255;
                        if (a != 255) continue;                            // fully opaque pixels only
                        const unsigned char *q = p + (b.hasAlpha && af ? 1 : 0);
                        ++all;
                        if (abs(q[0] - int((rgb >> 16) & 0xFF)) <= 3 && abs(q[1] - int((rgb >> 8) & 0xFF)) <= 3 && abs(q[2] - int(rgb & 0xFF)) <= 3) ++hit;
                    }
                    break;                                                 // first bitmap per icon
                }
            }
            if (opaque) *opaque = all;
            return hit;
        };
        [c applyAllPreferences];                                           // Default + Partial (upstream defaults)
        NSInteger all = 0;
        const NSInteger blue = count(0x0078D4, &all), red0 = count(0xE81123, nullptr);
        REQUIRE(all > 100 && blue > 10 && red0 == 0);
        [TPPrefs set:@0 forKey:@"pref.toolbarColor"];                      // Red, Partial
        [c applyAllPreferences];
        const NSInteger redPartial = count(0xE81123, &all);
        REQUIRE(redPartial >= blue && redPartial < all && count(0x0078D4, nullptr) == 0);
        [TPPrefs set:@0 forKey:@"pref.toolbarColorMode"];                  // Red, Complete
        [c applyAllPreferences];
        REQUIRE(count(0xE81123, &all) == all);
        [TPPrefs set:@9 forKey:@"pref.toolbarColor"];                      // Custom
        [TPPrefs set:@"123456" forKey:@"pref.toolbarCustomColor"];
        [c applyAllPreferences];
        REQUIRE(count(0x123456, &all) == all);
        [TPPrefs set:@4 forKey:@"pref.toolbarIconSet"];                    // Standard icons: not colorized
        [c applyAllPreferences];
        REQUIRE(count(0x123456, nullptr) == 0);
    });
    run(@"T-PREF-PEEK-001", @"MISC. > Document Peeker: hovering another tab peeks at it below the tab and/or in the Document Map", ^{
        [c closeAll_forTests];
        TPDocument *d1 = [c newDocument];
        setText("first document\n");
        TPDocument *d2 = [c newDocument];
        setText("second document\n");
        [c activateDocument:d1 inPane:c.mainPane];
        TPTabBarView *tb = c.mainPane.tabBar;
        const NSInteger i2 = [c.mainPane indexOfDocument:d2], i1 = [c.mainPane indexOfDocument:d1];
        [c tabBar:tb didHoverIndex:i2];
        REQUIRE(c.documentPeeker.document == nil);                         // off by default (upstream)
        [TPPrefs set:@YES forKey:@"pref.docPeekOnTab"];
        [c tabBar:tb didHoverIndex:i2];
        REQUIRE(c.documentPeeker.document == d2 && c.documentPeeker.window.isVisible);
        REQUIRE(SCI(c.documentPeeker.peekView, SCI_GETDOCPOINTER) == d2.sciDoc && SCI(c.documentPeeker.peekView, SCI_GETZOOM) == -10);
        NSRect tab = [tb.window convertRectToScreen:[tb convertRect:[tb rectForTabAtIndex:i2] toView:nil]];
        REQUIRE(NSMaxY(c.documentPeeker.window.frame) <= NSMinY(tab) && fabs(NSMinX(c.documentPeeker.window.frame) - NSMinX(tab)) < 1);
        [c tabBar:tb didHoverIndex:i1];                                     // the current document: no peek
        REQUIRE(c.documentPeeker.document == nil && !c.documentPeeker.window.isVisible);
        [c tabBar:tb didHoverIndex:i2];
        [c tabBar:tb didHoverIndex:-1];                                     // mouse left the tabs
        REQUIRE(c.documentPeeker.document == nil);
        [TPPrefs set:@NO forKey:@"pref.docPeekOnTab"];
        [TPPrefs set:@YES forKey:@"pref.docPeekOnMap"];
        exec(IDM_VIEW_DOC_MAP);
        REQUIRE(c.documentMapPanel.shownDocument == d1);
        [c tabBar:tb didHoverIndex:i2];
        REQUIRE(c.documentMapPanel.shownDocument == d2 && NSIsEmptyRect(c.documentMapPanel.visibleZone));
        [c tabBar:tb didHoverIndex:-1];
        REQUIRE(c.documentMapPanel.shownDocument == d1 && !NSIsEmptyRect(c.documentMapPanel.visibleZone));
        exec(IDM_VIEW_DOC_MAP);
    });
    run(@"T-UI-MENUBAR-001", @"General > Menu: in-window menu bar with the same menus, ＋ ▼ ✕, Hide toggled by F10 / ⌥ alone", ^{
        [c closeAll_forTests];
        [c newDocument]; [c newDocument];
        TPMenuBarView *bar = c.inWindowMenuBar;
        REQUIRE(bar && bar.hidden);                                        // off by default: menus in the macOS menu bar only
        [TPPrefs set:@YES forKey:@"pref.inWindowMenu"];
        [c applyAllPreferences];
        NSArray *titles = [bar.menuButtons valueForKey:@"title"];
        NSArray *expected = @[@"File", @"Edit", @"Search", @"View", @"Encoding", @"Language", @"Settings", @"Tools", @"Macro", @"Run", @"Plugins", @"Window", @"Help"];
        REQUIRE(!bar.hidden && [titles isEqualToArray:expected] && NSMinY(c.toolbar.frame) >= NSMaxY(bar.frame) - 0.5);
        NSMenu *file = [bar menuForButton:bar.menuButtons[0]];
        REQUIRE([file itemWithTag:IDM_FILE_NEW] && [file itemWithTag:IDM_FILE_NEW].target == (id)reg && file.supermenu == nil);
        NSMenu *win = [bar menuForButton:bar.menuButtons[11]];
        NSInteger docItems = 0;
        for (NSMenuItem *mi in win.itemArray) if ([mi.representedObject isKindOfClass:TPDocument.class]) ++docItems;
        REQUIRE(docItems == (NSInteger)c.activePane.documents.count);      // dynamic Window list refreshed before the copy
        NSMenu *drop = [bar tabDropListMenu];
        REQUIRE(drop.numberOfItems == (NSInteger)c.activePane.documents.count);
        NSInteger checked = -1;
        for (NSInteger i = 0; i < drop.numberOfItems; ++i) if ([drop itemAtIndex:i].state == NSControlStateValueOn) checked = i;
        REQUIRE(checked == [c.activePane indexOfDocument:c.currentDocument]);
        NSUInteger before = c.activePane.documents.count;
        [bar.shortcutButtons[0] performClick:nil];                         // ＋
        REQUIRE(c.activePane.documents.count == before + 1);
        [bar.shortcutButtons[2] performClick:nil];                         // ✕
        REQUIRE(c.activePane.documents.count == before);
        [TPPrefs set:@YES forKey:@"pref.hideRightShortcuts"];
        [c applyAllPreferences];
        REQUIRE(bar.shortcutButtons[0].hidden && bar.shortcutButtons[2].hidden);
        [TPPrefs set:@YES forKey:@"pref.menuHidden"];
        [c applyAllPreferences];
        REQUIRE(bar.hidden);
        auto flags = [&](NSEventModifierFlags m) {
            return [NSEvent keyEventWithType:NSEventTypeFlagsChanged location:NSZeroPoint modifierFlags:m timestamp:0 windowNumber:c.window.windowNumber
                                     context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:kVK_Option];
        };
        NSEvent *f10 = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:c.window.windowNumber
                                         context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:kVK_F10];
        REQUIRE([c handleMenuBarToggleEvent:f10] && !bar.hidden);
        REQUIRE([c handleMenuBarToggleEvent:f10] && bar.hidden);
        REQUIRE(![c handleMenuBarToggleEvent:flags(NSEventModifierFlagOption)] && [c handleMenuBarToggleEvent:flags(0)] && !bar.hidden);
        [c handleMenuBarToggleEvent:flags(NSEventModifierFlagOption)];
        [c handleMenuBarToggleEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagOption timestamp:0
                                                windowNumber:c.window.windowNumber context:nil characters:@"å" charactersIgnoringModifiers:@"a" isARepeat:NO keyCode:kVK_ANSI_A]];
        REQUIRE(![c handleMenuBarToggleEvent:flags(0)] && !bar.hidden);    // ⌥A typed: not a toggle
        // keyboard menu mode: ←/→ move, a mnemonic opens its menu, Esc leaves
        bar.keyboardIndex = -1;
        c.inWindowMenuTemporarilyShown = NO;
        [c applyAllPreferences];
        auto key = [&](unsigned short code, NSString *ch) {
            return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:c.window.windowNumber
                                     context:nil characters:ch charactersIgnoringModifiers:ch isARepeat:NO keyCode:code];
        };
        REQUIRE([c handleMenuBarToggleEvent:f10] && !bar.hidden && bar.keyboardIndex == 0);
        REQUIRE([c handleMenuBarToggleEvent:key(kVK_RightArrow, @"\uF703")] && bar.keyboardIndex == 1);
        REQUIRE([c handleMenuBarToggleEvent:key(kVK_LeftArrow, @"\uF702")] && bar.keyboardIndex == 0);
        REQUIRE([c handleMenuBarToggleEvent:key(kVK_ANSI_N, @"n")] && [bar.lastKeyboardOpened isEqualToString:@"Encoding"] && bar.keyboardIndex == -1);
        REQUIRE(bar.hidden);                                                // Hide: gone again once the menu closed
        REQUIRE([c handleMenuBarToggleEvent:f10] && [c handleMenuBarToggleEvent:key(kVK_Escape, @"\u001B")] && bar.keyboardIndex == -1 && bar.hidden);
        c.inWindowMenuTemporarilyShown = NO;
    });
    run(@"T-ENC-DETECT-001", @"MISC. > Autodetect character encoding (uchardet): a Windows-1251 file opens as Windows-1251; off opens it as ANSI", ^{
        std::string ru = tpp::encode("В начале было Слово, и Слово было у Бога, и Слово было Бог. Оно было в начале у Бога. "
                                     "Все через Него начало быть, и без Него ничто не начало быть, что начало быть. В Нем была жизнь, "
                                     "и жизнь была свет человеков. И свет во тьме светит, и тьма не объяла его.", {tpp::UniMode::Utf8, 1251}).bytes;
        NSString *f = tmpPath(@"russian.txt");
        writeBytes(f, ru);
        REQUIRE([TPPrefs b:@"pref.detectEncoding"]);                      // upstream default: on
        TPDocument *d = [c openFile:f];
        [c refreshUI];
        REQUIRE(d.encoding.codepage == 1251 && [reg isChecked:IDM_FORMAT_WIN_1251] && [[c.statusBar textForPart:4] isEqualToString:@"Windows-1251"]);
        REQUIRE(text().rfind("\xD0\x92 \xD0\xBD\xD0\xB0", 0) == 0);      // "В на"
        [c closeAll_forTests];
        [TPPrefs set:@NO forKey:@"pref.detectEncoding"];
        d = [c openFile:f];
        REQUIRE(d.encoding.codepage == -1 && d.encoding.mode == tpp::UniMode::Ansi);
    });
    run(@"T-ENC-720-001", @"Encoding > Character sets > Arabic > OEM 720 (built-in table): enabled, reinterprets, saves the same bytes", ^{
        NSString *f = tmpPath(@"arabic720.txt");
        writeBytes(f, "\x98\xE5 A");
        [TPPrefs set:@NO forKey:@"pref.detectEncoding"];
        [c openFile:f];
        nextAnswer = @"Yes";
        REQUIRE([reg isEnabled:IDM_FORMAT_DOS_720] && exec(IDM_FORMAT_DOS_720));
        REQUIRE(c.currentDocument.encoding.codepage == 720 && text() == "\xD8\xA1\xD9\x81 A" && [reg isChecked:IDM_FORMAT_DOS_720]);
        SCI(c.editor, SCI_DOCUMENTEND);
        SCI(c.editor, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>("\xD8\xB7"));   // ط = 0xE1
        REQUIRE(exec(IDM_FILE_SAVE));
        NSData *saved = [NSData dataWithContentsOfFile:f];
        REQUIRE(saved.length == 5 && memcmp(saved.bytes, "\x98\xE5 A\xE1", 5) == 0);
    });
    // ================================================================ plugins (native .tpplugin bundles)
    // message numbers from sdk/TextpadPlusPlusPlugin.h (upstream Notepad_plus_msgs.h), not included here
    constexpr uint32_t NPPM_GETCURRENTLANGTYPE_ = 2029;
    constexpr uint32_t NPPM_GETCURRENTSCINTILLA_ = 2028;
    constexpr uint32_t NPPM_GETNPPVERSION_ = 2074;
    constexpr uint32_t NPPM_GETNBOPENFILES_ = 2031;
    constexpr uint32_t NPPM_GETCURRENTBUFFERID_ = 2084;
    constexpr uint32_t NPPM_GETFULLCURRENTPATH_ = 4025;
    constexpr uint32_t NPPM_GETFILENAME_ = 4027;
    constexpr uint32_t NPPM_MENUCOMMAND_ = 2072;
    constexpr uint32_t NPPM_MSGTOPLUGIN_ = 2071;
    struct CommunicationInfo_ { long internalMsg; const char *srcModuleName; void *info; };
    constexpr uint32_t NPPM_DMMHIDE_ = 2024 + 31;
    run(@"T-PLUG-001", @"Import plugin(s): copied to plugins/<Name>/, loaded, Plugins menu, commands, check marks, default shortcut, NPPM messages, notifications", ^{
        TPPluginHost *h = [TPPluginHost shared];
        NSString *sample = [NSBundle.mainBundle.bundlePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"plugins/SamplePlugin.tpplugin"];
        REQUIRE([[NSFileManager defaultManager] fileExistsAtPath:sample]);   // make sample-plugin
        NSArray *copied = [h importPluginsFromPaths:@[sample]];
        NSString *dest = [[h.pluginsDirectory stringByAppendingPathComponent:@"SamplePlugin"] stringByAppendingPathComponent:@"SamplePlugin.tpplugin"];
        REQUIRE([copied isEqualToArray:@[dest]] && [[NSFileManager defaultManager] fileExistsAtPath:dest]);
        TPPlugin *p = h.plugins.lastObject;
        REQUIRE(p && [p.displayName isEqualToString:@"Sample Plugin"] && [p.moduleName isEqualToString:@"SamplePlugin.tpplugin"] && [p.version isEqualToString:@"1.0"]);
        REQUIRE(p.commands.count == 5 && p.commands[1].intValue == 0 && p.commands[0].intValue >= TP_ID_PLUGINS_CMD);
        // NPPN_TBMODIFICATION -> NPPM_ADDTOOLBARICON_FORDARKMODE: a button after the built-in ones
        REQUIRE([c.toolbar.pluginButtonCommands containsObject:p.commands[0]] && YES);
        // NPPM_DMMREGASDCKDLG: the plugin's NSView becomes a docking panel (right side), NPPM_DMMHIDE / DMMSHOW
        auto panelView = reinterpret_cast<void *(*)(void)>([p functionNamed:@"sample_panelView"]);
        REQUIRE(exec(p.commands[4].intValue) && panelView && panelView());
        REQUIRE([c.docks isPanelVisible:@"plugin.SamplePlugin.tpplugin.4"] && [c.docks sideOfPanel:@"plugin.SamplePlugin.tpplugin.4"] == TPDockRight);
        REQUIRE([h sendNppMessage:NPPM_DMMHIDE_ wParam:0 lParam:(intptr_t)panelView()] == 1 && ![c.docks isPanelVisible:@"plugin.SamplePlugin.tpplugin.4"]);
        REQUIRE(exec(p.commands[4].intValue) && [c.docks isPanelVisible:@"plugin.SamplePlugin.tpplugin.4"]);
        [c.docks hidePanel:@"plugin.SamplePlugin.tpplugin.4"];
        const int hello = p.commands[0].intValue, toggle = p.commands[2].intValue, report = p.commands[3].intValue;
        auto count = reinterpret_cast<int (*)(unsigned)>([p functionNamed:@"sample_notificationCount"]);
        auto chars = reinterpret_cast<int (*)(void)>([p functionNamed:@"sample_charsAdded"]);
        auto lastPath = reinterpret_cast<const char *(*)(void)>([p functionNamed:@"sample_lastPath"]);
        auto lastMsg = reinterpret_cast<long (*)(void)>([p functionNamed:@"sample_lastMessage"]);
        REQUIRE(count && chars && lastPath && lastMsg && count(NPPN_READY_CODE) == 1);
        // upstream PluginsManager::initMenu order
        NSMenu *pm = [reg topLevelMenuNamed:@"Plugins"];
        NSMenu *sub = [pm itemWithTitle:@"Sample Plugin"].submenu;
        REQUIRE(sub.numberOfItems == 5 && [[sub itemAtIndex:0].title isEqualToString:@"Insert Hello"] && [sub itemAtIndex:1].isSeparatorItem);
        NSInteger ai = [pm indexOfItemWithTag:IDM_SETTING_PLUGINADM];
        REQUIRE([pm indexOfItemWithSubmenu:sub] < ai && [pm itemAtIndex:ai - 1].isSeparatorItem && [pm itemAtIndex:ai + 1].isSeparatorItem && [pm indexOfItemWithTag:IDM_SETTING_OPENPLUGINSDIR] == ai + 2);
        TPKeyBinding *kb = [reg userBindingForCommand:hello];               // plugin ShortcutKey Ctrl+Alt+Shift+H
        REQUIRE(kb && [kb.keyEquivalent.lowercaseString isEqualToString:@"h"] && (kb.modifiers & NSEventModifierFlagShift) && (kb.modifiers & NSEventModifierFlagOption));
        [c newDocument];
        REQUIRE(exec(hello) && text() == "Hello from a plugin");
        REQUIRE([reg isChecked:toggle] && exec(toggle) && ![reg isChecked:toggle] && exec(toggle) && [reg isChecked:toggle]);
        // notifications
        NSString *f = tmpPath(@"plugin-notify.txt");
        writeBytes(f, "abc\n");
        const int opened = count(NPPN_FILEOPENED_CODE), activated = count(NPPN_BUFFERACTIVATED_CODE);
        TPDocument *d = [c openFile:f];
        REQUIRE(count(NPPN_FILEOPENED_CODE) == opened + 1 && count(NPPN_BUFFERACTIVATED_CODE) > activated);
        REQUIRE(exec(report) && strcmp(lastPath(), f.fileSystemRepresentation) == 0);
        const int typed = chars();
        [c.editor.content insertText:@"x" replacementRange:NSMakeRange(NSNotFound, 0)];
        REQUIRE(chars() == typed + 1);                                     // Scintilla notifications are forwarded
        const int saving = count(NPPN_FILEBEFORESAVE_CODE), saved = count(NPPN_FILESAVED_CODE), lang = count(NPPN_LANGCHANGED_CODE);
        REQUIRE(exec(IDM_FILE_SAVE) && count(NPPN_FILEBEFORESAVE_CODE) == saving + 1 && count(NPPN_FILESAVED_CODE) == saved + 1);
        exec(IDM_LANG_C);
        REQUIRE(count(NPPN_LANGCHANGED_CODE) == lang + 1);
        // NPPM_* as a plugin sends them
        int langType = -1, view = -1;
        [h sendNppMessage:NPPM_GETCURRENTLANGTYPE_ wParam:0 lParam:(intptr_t)&langType];
        [h sendNppMessage:NPPM_GETCURRENTSCINTILLA_ wParam:0 lParam:(intptr_t)&view];
        REQUIRE(langType == 2 && view == 0);                               // L_C, main view
        REQUIRE([h sendNppMessage:NPPM_GETNPPVERSION_ wParam:0 lParam:0] == ((8 << 16) | 991));
        REQUIRE([h sendNppMessage:NPPM_GETNBOPENFILES_ wParam:0 lParam:0] == (intptr_t)(c.mainPane.documents.count + c.subPane.documents.count));
        REQUIRE([h sendNppMessage:NPPM_GETCURRENTBUFFERID_ wParam:0 lParam:0] == (intptr_t)d.uid);
        char tiny[4];
        REQUIRE([h sendNppMessage:NPPM_GETFULLCURRENTPATH_ wParam:sizeof tiny lParam:(intptr_t)tiny] == 0);   // too small: FALSE
        char name[64];
        REQUIRE([h sendNppMessage:NPPM_GETFILENAME_ wParam:sizeof name lParam:(intptr_t)name] == 1 && strcmp(name, "plugin-notify.txt") == 0);
        REQUIRE([h sendNppMessage:NPPM_MENUCOMMAND_ wParam:0 lParam:IDM_EDIT_SELECTALL] && SCI(c.editor, SCI_GETSELECTIONEND) == SCI(c.editor, SCI_GETLENGTH));
        CommunicationInfo_ ci{42, "Other.tpplugin", nullptr};
        REQUIRE([h sendNppMessage:NPPM_MSGTOPLUGIN_ wParam:(uintptr_t)"SamplePlugin.tpplugin" lParam:(intptr_t)&ci] == 1 && lastMsg() == 42);
        const int closing = count(NPPN_FILEBEFORECLOSE_CODE), closed = count(NPPN_FILECLOSED_CODE);
        exec(IDM_FILE_CLOSE);
        REQUIRE(count(NPPN_FILEBEFORECLOSE_CODE) == closing + 1 && count(NPPN_FILECLOSED_CODE) == closed + 1);
        // contextMenu.xml PluginEntryName / PluginCommandItemName
        REQUIRE([h commandForPluginNamed:@"Sample Plugin" item:@"insert hello"] == hello && [h commandForPluginNamed:@"SamplePlugin" item:@"Report Path"] == report);
        // importing it again while it runs: copied, restart needed (upstream says so for every import)
        g_lastPrompt = nil;
        [h importPluginsFromPaths:@[sample]];
        REQUIRE([g_lastPrompt containsString:@"restart"] && h.plugins.count == 8);   // + the 7 built-in tool menus
    });
    run(@"T-PLUG-002", @"Plugin commands in the Shortcut Mapper and shortcuts.xml <PluginCommands> (module name + internal id); broken bundles are Incompatible", ^{
        TPPluginHost *h = [TPPluginHost shared];
        TPPlugin *p = h.plugins.lastObject;
        REQUIRE(p);
        NSMutableArray *rows = [NSMutableArray array];
        for (NSArray *r in h.shortcutRows) if ([r[2] isEqualToString:@"SamplePlugin.tpplugin"]) [rows addObject:r];
        REQUIRE(rows.count == 4 && [rows[0][1] isEqualToString:@"Insert Hello"]);
        const int report = p.commands[3].intValue;
        [reg setUserBinding:[TPKeyBinding bindingWithKey:@"j" modifiers:NSEventModifierFlagCommand | NSEventModifierFlagShift command:report] forCommand:report];
        [c shortcutsDidChange];
        NSString *xml = [NSString stringWithContentsOfFile:[[TPSession shared].supportDirectory stringByAppendingPathComponent:@"shortcuts.xml"] encoding:NSUTF8StringEncoding error:nil];
        REQUIRE([xml containsString:@"<PluginCommand moduleName=\"SamplePlugin.tpplugin\" internalID=\"3\""] && ![xml containsString:@"internalID=\"0\""]);
        NSMenuItem *reportItem = [[[reg topLevelMenuNamed:@"Plugins"] itemWithTitle:@"Sample Plugin"].submenu itemWithTag:report];
        REQUIRE([reportItem.keyEquivalent.lowercaseString isEqualToString:@"j"] && (reportItem.keyEquivalentModifierMask & NSEventModifierFlagCommand));
        NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:@"<NotepadPlus><PluginCommands><PluginCommand moduleName=\"SamplePlugin.tpplugin\" internalID=\"0\" Ctrl=\"no\" Alt=\"no\" Shift=\"no\" Key=\"0\"/></PluginCommands></NotepadPlus>" options:0 error:nil];
        [h applyShortcutsFrom:doc];                                        // Key 0: the default Ctrl+Alt+Shift+H removed
        REQUIRE([reg userBindingForCommand:p.commands[0].intValue].isEmpty && [reg userBindingForCommand:report] == nil);
        [h applyShortcutsFrom:[[NSXMLDocument alloc] initWithXMLString:@"<NotepadPlus/>" options:0 error:nil]];
        REQUIRE(![reg userBindingForCommand:p.commands[0].intValue].isEmpty);   // back to the plugin's own
        // a bundle that is not a loadable plugin
        NSString *broken = tmpPath(@"Broken.tpplugin");
        [[NSFileManager defaultManager] removeItemAtPath:broken error:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:[broken stringByAppendingPathComponent:@"Contents/MacOS"] withIntermediateDirectories:YES attributes:nil error:nil];
        writeBytes([broken stringByAppendingPathComponent:@"Contents/MacOS/Broken"], "not a Mach-O file");
        writeBytes([broken stringByAppendingPathComponent:@"Contents/Info.plist"], "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleExecutable</key><string>Broken</string><key>CFBundlePackageType</key><string>BNDL</string></dict></plist>");
        NSString *err = nil;
        REQUIRE([h loadPluginAtPath:broken error:&err] == nil && err.length && [[h.incompatible valueForKey:@"path"] containsObject:broken]);
        REQUIRE(h.plugins.count == 8);
    });
    run(@"T-PLUG-003", @"Plugins Admin: Installed / Incompatible / Available tabs, Remove takes the plugin out of the menu and its commands", ^{
        TPPluginHost *h = [TPPluginHost shared];
        TPPlugin *p = h.plugins.lastObject;
        REQUIRE(p && exec(IDM_SETTING_PLUGINADM));
        TPPluginsAdmin *pa = [TPPluginsAdmin shared];
        pa.tab = TPPluginsAdminInstalled;
        REQUIRE(pa.rows.count == 1 && [pa.rows[0][0] isEqualToString:@"Sample Plugin"] && [pa.rows[0][1] isEqualToString:@"1.0"] && pa.removeButton.enabled);
        pa.tab = TPPluginsAdminIncompatible;
        REQUIRE(pa.rows.count >= 1 && [pa.rows[0][0] isEqualToString:@"Broken.tpplugin"]);
        pa.tab = TPPluginsAdminAvailable;
        REQUIRE(pa.rows.count == 0 && [pa.note.stringValue containsString:@"Import plugin(s)"] && !pa.removeButton.enabled);
        pa.tab = TPPluginsAdminInstalled;
        [pa.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        nextAnswer = @"Remove";
        const int hello = p.commands[0].intValue;
        REQUIRE([pa removeSelected] && p.removed && ![[NSFileManager defaultManager] fileExistsAtPath:p.path]);
        REQUIRE([[reg topLevelMenuNamed:@"Plugins"] itemWithTitle:@"Sample Plugin"] == nil && ![reg isEnabled:hello] && pa.rows.count == 0);
        REQUIRE(![c.toolbar.pluginButtonCommands containsObject:@(hello)]);   // its toolbar button went too
        REQUIRE([[[reg topLevelMenuNamed:@"Plugins"] itemAtIndex:0].title isEqualToString:@"JSON Tools"]);
        [pa close];
    });
    // ================================================================ updater, Window list
    run(@"T-UPD-001", @"? > Update Textpad++: GUP feed, version compare, download to Downloads; no address in this build; ? > Set Updater Proxy", ^{
        TPUpdater *u = [TPUpdater shared];
        REQUIRE([TPUpdater compareVersion:@"0.10.0" with:@"0.9.9"] == NSOrderedDescending && [TPUpdater compareVersion:@"1.0" with:@"1.0.0"] == NSOrderedSame);
        g_lastPrompt = nil;
        REQUIRE(u.feedURL == nil && exec(IDM_UPDATE_NPP) && [g_lastPrompt containsString:@"no update address"]);   // built without UPDATE_URL
        NSString *dir = tmpPath(@"updates");
        [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:[dir stringByAppendingPathComponent:@"dl"] withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *dmg = [dir stringByAppendingPathComponent:@"Textpad++.dmg"], *feed = [dir stringByAppendingPathComponent:@"update.xml"];
        writeBytes(dmg, "fake disk image");
        auto writeFeed = [&](NSString *version) {
            writeBytes(feed, StdStr([NSString stringWithFormat:@"<?xml version=\"1.0\"?>\n<GUP>\n\t<NeedToBeUpdated>yes</NeedToBeUpdated>\n\t<Version>%@</Version>\n\t<Location>%@</Location>\n</GUP>\n",
                                     version, [NSURL fileURLWithPath:dmg].absoluteString]));
        };
        writeFeed(@"99.0");
        [TPPrefs set:[NSURL fileURLWithPath:feed].absoluteString forKey:@"pref.updateFeedURL"];
        NSString *err = nil;
        TPUpdateInfo *info = [u fetchFeed:u.feedURL error:&err];
        REQUIRE(info && [info.version isEqualToString:@"99.0"] && info.needToBeUpdated && [u isNewer:info] && !err);
        u.downloadDirectoryOverride = [dir stringByAppendingPathComponent:@"dl"];
        nextAnswer = @"No";
        [u handleUpdate:info error:nil interactive:YES];
        REQUIRE([g_lastPrompt containsString:@"do you want to install it"] && [[NSFileManager defaultManager] contentsOfDirectoryAtPath:u.downloadDirectoryOverride error:nil].count == 0);
        [u downloadForManualInstall:info];                                 // the fallback when the app cannot replace itself
        NSString *got = [u.downloadDirectoryOverride stringByAppendingPathComponent:@"Textpad++.dmg"];
        REQUIRE([g_lastPrompt containsString:@"was downloaded"] && [[NSString stringWithContentsOfFile:got encoding:NSUTF8StringEncoding error:nil] isEqualToString:@"fake disk image"]);
        writeFeed(u.currentVersion);
        info = [u fetchFeed:u.feedURL error:nil];
        g_lastPrompt = nil;
        [u handleUpdate:info error:nil interactive:NO];                    // auto-updater: silent when up to date
        REQUIRE(![u isNewer:info] && g_lastPrompt == nil);
        [u handleUpdate:info error:nil interactive:YES];
        REQUIRE([g_lastPrompt isEqualToString:@"No update is available."]);
        writeBytes(feed, "<html>not found</html>");
        REQUIRE([u fetchFeed:u.feedURL error:&err] == nil && [err containsString:@"GUP"]);
        // Preferences > MISC. > auto-updater: at most every 15 days
        [[NSUserDefaults standardUserDefaults] setObject:[NSDate dateWithTimeIntervalSinceNow:-16 * 24 * 3600] forKey:@"updater.lastCheck"];
        [u checkAtLaunch];
        REQUIRE(-[[[NSUserDefaults standardUserDefaults] objectForKey:@"updater.lastCheck"] timeIntervalSinceNow] < 60);
        [TPPrefs set:@NO forKey:@"pref.autoUpdater"];
        [[NSUserDefaults standardUserDefaults] setObject:[NSDate distantPast] forKey:@"updater.lastCheck"];
        [u checkAtLaunch];
        REQUIRE([[[NSUserDefaults standardUserDefaults] objectForKey:@"updater.lastCheck"] isEqualToDate:[NSDate distantPast]]);
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"updater.lastCheck"];
        // proxy (GUP "Proxy settings")
        [u setProxyHost:@"proxy.example.com" port:8080];
        NSDictionary *proxy = u.sessionConfiguration.connectionProxyDictionary;
        REQUIRE([proxy[(NSString *)kCFNetworkProxiesHTTPProxy] isEqualToString:@"proxy.example.com"] && [proxy[(NSString *)kCFNetworkProxiesHTTPPort] intValue] == 8080);
        [u setProxyHost:@"" port:0];
        REQUIRE(u.sessionConfiguration.connectionProxyDictionary == nil);
        u.downloadDirectoryOverride = nil;
    });
    run(@"T-WIN-002", @"Window menu: the documents are IDM_WINDOW_MRU_FIRST + i commands (\"1: path\", \"*\" when modified, current checked)", ^{
        [c closeAll_forTests];
        TPDocument *a = [c newDocument];
        TPDocument *b = [c newDocument];
        setText("changed");
        [c newDocument];
        NSMenu *m = [reg topLevelMenuNamed:@"Window"];
        [c menuNeedsUpdate:m];
        const int ia = (int)[c.activePane indexOfDocument:a], ib = (int)[c.activePane indexOfDocument:b], n = (int)c.activePane.documents.count;
        NSMenuItem *first = [m itemWithTag:IDM_WINDOW_MRU_FIRST], *ma = [m itemWithTag:IDM_WINDOW_MRU_FIRST + ia], *mb = [m itemWithTag:IDM_WINDOW_MRU_FIRST + ib];
        REQUIRE(first && !first.hidden && [first.title hasPrefix:@"1: "] && first.representedObject == c.activePane.documents[0]);
        NSString *bPrefix = [NSString stringWithFormat:@"%d: ", ib + 1];
        REQUIRE(ma.representedObject == a && [mb.title hasPrefix:bPrefix] && [mb.title hasSuffix:@"*"] && b.dirty);
        REQUIRE(exec(IDM_WINDOW_MRU_FIRST + ib) && c.currentDocument == b && [reg isChecked:IDM_WINDOW_MRU_FIRST + ib] && ![reg isChecked:IDM_WINDOW_MRU_FIRST + ia]);
        REQUIRE(![reg isEnabled:IDM_WINDOW_MRU_FIRST + n]);                 // past the last document
        NSString *longPath = [@"/Users/someone/" stringByAppendingString:[@"" stringByPaddingToLength:80 withString:@"deep/" startingAtIndex:0]];
        longPath = [longPath stringByAppendingString:@"file.txt"];
        extern NSString *TPMenuFileName(NSString *path, NSUInteger pos, BOOL ordinal);
        NSString *shortName = TPMenuFileName(longPath, 9, YES);
        REQUIRE([shortName hasPrefix:@"10: "] && [shortName hasSuffix:@".../file.txt"] && shortName.length <= 64);
    });
    run(@"T-PREF-TRAY-001", @"MISC. > Minimize / Close to system tray: the window goes to a menu bar extra with upstream's tray menu; Activate, New and Paste, Close Tray Icon", ^{
        [c minimizeClicked:nil];                                            // "No action on": a normal minimize
        REQUIRE(c.trayItem == nil);
        if (c.window.isMiniaturized) [c.window deminiaturize:nil];
        [c.window orderFront:nil];
        [TPPrefs set:@1 forKey:@"pref.systray"];                           // Minimize to
        REQUIRE(![c hideToTrayIfWantedFor:TPTrayClose] && c.trayItem == nil);
        [c minimizeClicked:nil];
        REQUIRE(c.trayItem && !c.window.isVisible && !c.window.isMiniaturized);
        NSArray *titles = [c.trayItem.menu.itemArray valueForKey:@"title"];
        NSArray *expected = @[@"Activate", @"", @"New", @"New and Paste", @"Open...", @"Find in Files...", @"", @"Close Tray Icon"];
        REQUIRE([titles isEqualToArray:expected]);
        REQUIRE(exec(IDM_SYSTRAYPOPUP_ACTIVATE) && c.window.isVisible && c.trayItem == nil);
        [TPPrefs set:@2 forKey:@"pref.systray"];                           // Close to: the close button hides instead of quitting
        REQUIRE(![c windowShouldClose:c.window] && c.trayItem && !c.window.isVisible);
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        NSString *saved = [pb stringForType:NSPasteboardTypeString];
        [pb clearContents];
        [pb setString:@"pasted from the tray" forType:NSPasteboardTypeString];
        [c newDocument];
        setText("not empty");
        const NSUInteger before = c.activePane.documents.count;
        REQUIRE(exec(IDM_SYSTRAYPOPUP_NEW_AND_PASTE) && c.window.isVisible && c.activePane.documents.count == before + 1 && text() == "pasted from the tray");
        [pb clearContents];
        if (saved) [pb setString:saved forType:NSPasteboardTypeString];
        [TPPrefs set:@3 forKey:@"pref.systray"];
        REQUIRE([c hideToTrayIfWantedFor:TPTrayMinimize] && c.trayItem);
        REQUIRE(exec(IDM_SYSTRAYPOPUP_CLOSE) && c.trayItem == nil && c.window.isVisible);   // the self-test reopens instead of quitting
    });
    // ================================================================ very large files
    run(@"T-BIG-001", @"Large files load in the background (ILoader): 40 MB UTF-8 and UTF-16 open byte-exact, save in chunks, a growing log appends", ^{
        std::string block;
        for (int i = 0; i < 1000; ++i) block += "2026-11-14 10:00:00 INFO request id=" + std::to_string(i) + " path=/π/ü/日本 status=200\n";
        std::string big;
        while (big.size() < (TPStreamedFileBytes + (2u << 20))) big += block;
        big += "LAST LINE\n";
        NSString *f = tmpPath(@"big-utf8.log");
        writeBytes(f, big);
        TPDocument *d = [c openFile:f];
        REQUIRE(d && d.encoding.mode == tpp::UniMode::Utf8 && SCI(c.editor, SCI_GETLENGTH) == (sptr_t)big.size());
        REQUIRE(sciGetLine(c.editor, SCI(c.editor, SCI_GETLINECOUNT) - 2) == "LAST LINE");
        NSString *copy = tmpPath(@"big-copy.log");
        REQUIRE([c writeDocument:d toPath:copy updateDocument:NO error:nil] && readBytes(copy) == big);   // byte-exact, chunked
        SCI(c.editor, SCI_DOCUMENTEND);
        SCI(c.editor, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>("typed\n"));
        REQUIRE(exec(IDM_FILE_SAVE) && readBytes(f) == big + "typed\n");
        // the file grows (a server log): Reload appends only the new bytes
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:f];
        [h seekToEndOfFile];
        [h writeData:[@"appended later\n" dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
        REQUIRE([c reloadDocument:d encoding:nullptr] && sciGetText(c.editor) == big + "typed\nappended later\n" && !d.dirty);
        [c closeAll_forTests];
        // UTF-16 LE with a BOM, converted chunk by chunk (surrogate pairs across chunk ends)
        std::string u8;
        while (u8.size() < (TPStreamedFileBytes / 2 + (1u << 20))) u8 += "line 😀 é 日本語 text\n";
        std::string u16 = tpp::encode(u8, {tpp::UniMode::Utf16LE, -1}).bytes;
        NSString *g = tmpPath(@"big-utf16.txt");
        writeBytes(g, u16);
        d = [c openFile:g];
        REQUIRE(d && d.encoding.mode == tpp::UniMode::Utf16LE && sciGetText(c.editor) == u8);
        NSString *copy16 = tmpPath(@"big-utf16-copy.txt");
        REQUIRE([c writeDocument:d toPath:copy16 updateDocument:NO error:nil] && readBytes(copy16) == u16);
        [c closeAll_forTests];
        for (NSString *p in @[f, copy, g, copy16]) [[NSFileManager defaultManager] removeItemAtPath:p error:nil];
    });
    if (NSString *bigPath = [NSProcessInfo processInfo].environment[@"TEXTPAD_BIGFILE"]) run(@"T-BIG-BENCH", @"Benchmark: a multi-GB log (TEXTPAD_BIGFILE)", ^{
        auto now = [] { return std::chrono::steady_clock::now(); };
        auto ms = [](auto a, auto b) { return std::chrono::duration<double, std::milli>(b - a).count(); };
        auto rss = [] { mach_task_basic_info info; mach_msg_type_number_t n = MACH_TASK_BASIC_INFO_COUNT;
                        task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &n); return info.resident_size / 1048576.0; };
        const unsigned long long size = [[NSFileManager defaultManager] attributesOfItemAtPath:bigPath error:nil].fileSize;
        const double rss0 = rss();
        auto t0 = now();
        TPDocument *d = [c openFile:bigPath];
        auto t1 = now();
        REQUIRE(d);
        fprintf(stderr, "BENCH big file: %.2f GB, %ld lines\n", size / 1073741824.0, (long)SCI(c.editor, SCI_GETLINECOUNT));
        fprintf(stderr, "BENCH open           %8.0f ms   memory +%.0f MB\n", ms(t0, t1), rss() - rss0);
        auto t2 = now(); SCI(c.editor, SCI_DOCUMENTEND); [c refreshUI]; auto t3 = now();
        fprintf(stderr, "BENCH go to end      %8.0f ms\n", ms(t2, t3));
        SCI(c.editor, SCI_SETTARGETRANGE, 0, SCI(c.editor, SCI_GETLENGTH));
        SCI(c.editor, SCI_SETSEARCHFLAGS, 0);
        auto t4 = now();
        const sptr_t hit = SCI(c.editor, SCI_SEARCHINTARGET, strlen("UNIQUE-END-MARKER"), reinterpret_cast<sptr_t>("UNIQUE-END-MARKER"));
        auto t5 = now();
        fprintf(stderr, "BENCH find (whole)   %8.0f ms   found at %ld\n", ms(t4, t5), (long)hit);
        REQUIRE(hit > 0);
        SCI(c.editor, SCI_DOCUMENTEND);
        SCI(c.editor, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>("edited by the benchmark\n"));
        auto t6 = now(); REQUIRE(exec(IDM_FILE_SAVE)); auto t7 = now();
        fprintf(stderr, "BENCH save           %8.0f ms\n", ms(t6, t7));
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:bigPath];
        [h seekToEndOfFile]; [h writeData:[@"one more log line\n" dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile];
        auto t8 = now(); REQUIRE([c reloadDocument:d encoding:nullptr]); auto t9 = now();
        fprintf(stderr, "BENCH log grew, reload %6.0f ms\n", ms(t8, t9));
        auto ta = now(); [c closeAll_forTests]; auto tb = now();
        fprintf(stderr, "BENCH close          %8.0f ms   memory after close +%.0f MB\n", ms(ta, tb), rss() - rss0);
    });
    run(@"T-PLUG-004", @"Plugins Admin > Available / Updates from an online list: download, SHA-256 check, unpack, install; a wrong checksum is refused", ^{
        TPPluginHost *h = [TPPluginHost shared];
        TPPluginsAdmin *pa = [TPPluginsAdmin shared];
        NSString *dir = tmpPath(@"pluginlist");
        [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *sample = [NSBundle.mainBundle.bundlePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"plugins/SamplePlugin.tpplugin"];
        NSString *zip = [dir stringByAppendingPathComponent:@"SamplePlugin.zip"];
        NSTask *t = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/ditto" arguments:@[@"-c", @"-k", @"--keepParent", sample, zip]];
        [t waitUntilExit];
        std::string hex;
        std::string err;
        REQUIRE(tpp::hashFileHex(tpp::HashAlgorithm::SHA256, zip.fileSystemRepresentation, hex, err));
        auto writeList = [&](NSString *sha, NSString *version) {
            NSDictionary *j = @{@"plugins": @[@{@"folder-name": @"SamplePlugin", @"display-name": @"Sample Plugin", @"version": version, @"id": sha,
                                                @"repository": [NSURL fileURLWithPath:zip].absoluteString, @"description": @"The SDK sample"}]};
            [[NSJSONSerialization dataWithJSONObject:j options:0 error:nil] writeToFile:[dir stringByAppendingPathComponent:@"pluginList.json"] atomically:YES];
        };
        REQUIRE(pa.listURL == nil);                                        // built without UPDATE_URL
        [TPPrefs set:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"pluginList.json"]].absoluteString forKey:@"pref.pluginListURL"];
        writeList(@"0000", @"1.0");                                        // a wrong checksum first
        pa.tab = TPPluginsAdminAvailable;
        [pa refreshList];
        REQUIRE(pa.rows.count == 1 && [pa.rows[0][0] isEqualToString:@"Sample Plugin"] && pa.installButton.enabled);   // removed by T-PLUG-003
        [pa.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        g_lastPrompt = nil;
        REQUIRE(![pa installSelected] && [g_lastPrompt containsString:@"not installed"]);
        writeList(@(hex.c_str()), @"1.0");
        [pa refreshList];
        [pa.table selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        REQUIRE([pa installSelected]);
        TPPlugin *p = nil;
        for (TPPlugin *x in h.plugins) if (!x.removed && [x.moduleName isEqualToString:@"SamplePlugin.tpplugin"]) p = x;
        REQUIRE(p && [[reg topLevelMenuNamed:@"Plugins"] itemWithTitle:@"Sample Plugin"] != nil && pa.rows.count == 0);   // no longer "available"
        writeList(@(hex.c_str()), @"2.0");                                 // a newer version in the list: Updates
        pa.tab = TPPluginsAdminUpdates;
        [pa refreshList];
        REQUIRE(pa.rows.count == 1 && [pa.rows[0][1] isEqualToString:@"2.0"] && [pa.installButton.title isEqualToString:@"Update"]);
        [pa close];
    });
    run(@"T-L10N-001", @"General > Localization: the upstream language files translate menus, sub-menus and command labels live; English restores", ^{
        TPLocalization *l = [TPLocalization shared];
        REQUIRE(l.languageNames.count > 80 && [l.languageNames.firstObject isEqualToString:@"English"] && [l.languageNames containsObject:@"Français"]);
        NSMenuItem *fileTop = NSApp.mainMenu.itemArray[1];
        NSMenuItem *copyTo = [[reg topLevelMenuNamed:@"Edit"] itemAtIndex:12];   // upstream position {1, 12}: edit-copyToClipboard
        NSString *copyToEnglish = copyTo.title;
        REQUIRE(copyTo.submenu && [fileTop.title isEqualToString:@"File"]);
        [TPPrefs set:@"french.xml" forKey:@"pref.localization"];
        [c applyAllPreferences];
        REQUIRE([fileTop.title isEqualToString:@"Fichier"] && [[reg menuItemForCommand:IDM_FILE_NEW].title isEqualToString:@"Nouveau"]);
        REQUIRE([[reg labelForCommand:IDM_FILE_NEW] isEqualToString:@"Nouveau"] && ![copyTo.title isEqualToString:copyToEnglish]);
        for (NSMenuItem *top in NSApp.mainMenu.itemArray) REQUIRE(![top.title.lowercaseString containsString:[@"note" stringByAppendingString:@"pad"]]);
        [TPPrefs set:@"" forKey:@"pref.localization"];
        [c applyAllPreferences];
        REQUIRE([fileTop.title isEqualToString:@"File"] && [copyTo.title isEqualToString:copyToEnglish] && [[reg labelForCommand:IDM_FILE_NEW] isEqualToString:@"New"]);
    });
    run(@"T-CMD-QN-001", @"-qn=\"Quoter\": upstream's quotes by named people are typed into a new document; random works; unknown names do nothing", ^{
        NSString *q = TPQuoteNamed(@"Seymour Cray");
        REQUIRE([q containsString:@"The trouble with programmers"] && [q hasSuffix:@"- Seymour Cray"]);
        REQUIRE(TPQuoteNamed(@"random").length > 10 && TPQuoteNamed(@"No Such Person") == nil);
        REQUIRE(![TPQuoteNamed(@"random").lowercaseString containsString:[@"note" stringByAppendingString:@"pad"]]);
    });
    run(@"T-UI-LAYOUT-002", @"Panels dock on all four sides or float; Search results float; the UDL dialog docks; views rotate; border width; dialog font", ^{
        TPDockManager *dm = c.docks;
        exec(IDM_VIEW_DOCLIST);
        REQUIRE([dm sideOfPanel:@"doclist"] == TPDockLeft && !dm.leftDock.hidden);
        [dm movePanel:@"doclist" toSide:TPDockBottom];
        REQUIRE(!dm.bottomDock.hidden && dm.leftDock.hidden && [dm.bottomDock.panels.firstObject.panelIdentifier isEqualToString:@"doclist"]);
        [dm movePanel:@"doclist" toSide:TPDockTop];
        REQUIRE(!dm.topDock.hidden && dm.bottomDock.hidden && NSMaxY(dm.topDock.frame) <= NSMinY(c.mainPane.superview.superview.frame) + 1);
        [dm movePanel:@"doclist" toSide:TPDockFloating];
        NSWindow *fw = [dm floatingWindowOfPanel:@"doclist"];
        REQUIRE(fw && fw.isVisible && [fw.title isEqualToString:@"Document List"] && dm.topDock.hidden && [dm isPanelVisible:@"doclist"]);
        [fw close];                                                         // closing the window hides the panel
        REQUIRE(![dm isPanelVisible:@"doclist"]);
        [dm movePanel:@"doclist" toSide:TPDockLeft];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"dock.side.doclist"];
        // Search results: docked under the editors or in its own window
        c.resultsPanel.floating = YES;
        [c.resultsPanel showPanel];
        REQUIRE(c.resultsPanel.window != c.window && c.resultsPanel.window.isVisible && !c.resultsPanel.hidden);
        c.resultsPanel.floating = NO;
        [c.resultsPanel showPanel];
        REQUIRE(c.resultsPanel.window == c.window && !c.resultsPanel.hidden);
        [c.resultsPanel hidePanel];
        // the UDL dialog docks (bottom by default) and undocks
        TPUDLDialog *u = [TPUDLDialog sharedWithController:c];
        u.window.alphaValue = 0;
        [u toggleDock:nil];
        REQUIRE(u.docked && [dm isPanelVisible:@"udl"] && !u.window.isVisible && [dm sideOfPanel:@"udl"] == TPDockBottom && [reg isChecked:IDM_LANG_USER_DLG]);
        [u toggleDock:nil];
        REQUIRE(!u.docked && ![dm isPanelVisible:@"udl"] && u.window.isVisible);
        [u hideDialog];
        // the two views stacked (splitter "Rotate to right / left")
        exec(IDM_VIEW_CLONE_TO_ANOTHER_VIEW);
        REQUIRE(c.viewSplitter.vertical);
        [c rotateViews];
        REQUIRE(!c.viewSplitter.vertical && NSMinY(c.subPane.frame) >= NSMaxY(c.mainPane.frame) - 1);
        [c rotateViews];
        REQUIRE(c.viewSplitter.vertical);
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"views.stacked"];
        // border width and edge (upstream default 2 + edge)
        REQUIRE(NSMinX(c.mainPane.editor.frame) >= 3 - 0.5);
        [TPPrefs set:@0 forKey:@"pref.borderWidth"];
        [TPPrefs set:@NO forKey:@"pref.borderEdge"];
        [c applyAllPreferences];
        REQUIRE(NSMinX(c.mainPane.editor.frame) < 0.5);
        // custom dialog font
        [TPPrefs set:@YES forKey:@"pref.dialogFont"];
        [TPPrefs set:@"Menlo" forKey:@"pref.dialogFontName"];
        [TPPrefs set:@13 forKey:@"pref.dialogFontSize"];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 200, 80) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
        NSTextField *label = [NSTextField labelWithString:@"x"];
        [w.contentView addSubview:label];
        TPApplyDialogFont(w);
        REQUIRE([label.font.fontName hasPrefix:@"Menlo"] && label.font.pointSize == 13);
    });
    run(@"T-JSON-001", @"Plugins > JSON Tools: Format / Compress / Validate on the document or the selection, one undo step, errors point at the problem", ^{
        TPPluginHost *h = [TPPluginHost shared];
        int fmt = [h commandForPluginNamed:@"JSON Tools" item:@"Format JSON"], cmp = [h commandForPluginNamed:@"JSON Tools" item:@"Compress JSON"];
        int val = [h commandForPluginNamed:@"JSON Tools" item:@"Validate JSON"];
        NSInteger jsonItems = [[reg topLevelMenuNamed:@"Plugins"] itemWithTitle:@"JSON Tools"].submenu.numberOfItems;
        REQUIRE(fmt && cmp && val && jsonItems == 11);
        for (int cmd : {fmt, cmp, val}) {                                  // default shortcuts clash with nothing
            TPKeyBinding *kb = [reg userBindingForCommand:cmd];
            REQUIRE(kb && !kb.isEmpty && [reg commandsBoundToKey:kb.keyEquivalent modifiers:kb.modifiers].count == 1);
        }
        [c newDocument];
        SCI(c.editor, SCI_SETUSETABS, 0);
        SCI(c.editor, SCI_SETINDENT, 2);
        SCI(c.editor, SCI_SETEOLMODE, SC_EOL_LF);
        setText("{\"z\":1,\"a\":{\"b\":[true,null]}}");
        REQUIRE(exec(fmt) && text() == "{\n  \"z\": 1,\n  \"a\": {\n    \"b\": [\n      true,\n      null\n    ]\n  }\n}");
        REQUIRE([c.currentDocument.languageId isEqualToString:@"json"]);   // highlighted as JSON afterwards
        SCI(c.editor, SCI_UNDO);
        REQUIRE(text() == "{\"z\":1,\"a\":{\"b\":[true,null]}}");          // one undo step
        exec(fmt);
        REQUIRE(exec(cmp) && text() == "{\"z\":1,\"a\":{\"b\":[true,null]}}");
        SCI(c.editor, SCI_SETUSETABS, 0);                                  // JSON's own indent settings applied above
        SCI(c.editor, SCI_SETINDENT, 2);
        setText("x = [1, 2] ;");
        SCI(c.editor, SCI_SETSEL, 4, 10);                                  // only the selection
        REQUIRE(exec(fmt) && text() == "x = [\n  1,\n  2\n] ;");
        setText("{\n  \"a\": 1,\n  \"b\" 2\n}");
        SCI(c.editor, SCI_SETSEL, 0, 0);
        g_lastPrompt = nil;
        REQUIRE(exec(val) && [g_lastPrompt isEqualToString:@"Invalid JSON"] && SCI(c.editor, SCI_LINEFROMPOSITION, SCI(c.editor, SCI_GETCURRENTPOS)) == 2);
        REQUIRE(exec(fmt) && text() == "{\n  \"a\": 1,\n  \"b\" 2\n}");      // invalid: left untouched
        setText("[]");
        REQUIRE(exec(val) && [g_lastPrompt isEqualToString:@"The JSON is valid."]);
    });
    run(@"T-DEV-001", @"Developer tools, text functions: case styles, Base64 / URL / HTML / Unicode / hex, JWT, Unix time, numbers, align, XML, XPath, inserts", ^{
        NSString *err = nil;
        REQUIRE([TPConvertCase(@"hello world\n  HTMLParser_v2 x\r\nfoo-bar", TPCaseCamel) isEqualToString:@"helloWorld\n  htmlParserV2X\r\nfooBar"]);
        NSString *id1 = @"myHTTPServer2Go";
        REQUIRE([TPConvertCase(id1, TPCaseSnake) isEqualToString:@"my_http_server2_go"] && [TPConvertCase(id1, TPCaseConstant) isEqualToString:@"MY_HTTP_SERVER2_GO"]);
        REQUIRE([TPConvertCase(id1, TPCaseKebab) isEqualToString:@"my-http-server2-go"] && [TPConvertCase(id1, TPCasePascal) isEqualToString:@"MyHttpServer2Go"]);
        REQUIRE([TPConvertCase(id1, TPCaseDot) isEqualToString:@"my.http.server2.go"] && [TPConvertCase(@"a b  ", TPCaseSnake) isEqualToString:@"a_b  "]);
        REQUIRE([TPEncodeText(@"héllo", TPCodecBase64, YES, &err) isEqualToString:@"aMOpbGxv"]);
        REQUIRE([TPEncodeText(@"aMOpbGxv", TPCodecBase64, NO, &err) isEqualToString:@"héllo"]);
        REQUIRE(TPEncodeText(@"!!!", TPCodecBase64, NO, &err) == nil && err.length);
        REQUIRE([TPEncodeText(@"a b&c=é", TPCodecURL, YES, &err) isEqualToString:@"a%20b%26c%3D%C3%A9"]);
        REQUIRE([TPEncodeText(@"a%20b%26c%3D%C3%A9", TPCodecURL, NO, &err) isEqualToString:@"a b&c=é"]);
        REQUIRE([TPEncodeText(@"<a href=\"x\">'&'</a>", TPCodecHTML, YES, &err) isEqualToString:@"&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;"]);
        REQUIRE([TPEncodeText(@"&lt;&#233;&#xE9;&euro;&bogus;", TPCodecHTML, NO, &err) isEqualToString:@"<éé€&bogus;"]);
        NSString *emoji = @"é\U0001F600";
        REQUIRE([TPEncodeText(emoji, TPCodecUnicode, YES, &err) isEqualToString:@"\\u00E9\\uD83D\\uDE00"]);
        REQUIRE([TPEncodeText(@"\\u00E9\\uD83D\\uDE00 \\u{1F600}", TPCodecUnicode, NO, &err) isEqualToString:@"é\U0001F600 \U0001F600"]);
        REQUIRE([TPEncodeText(@"Hi", TPCodecHex, YES, &err) isEqualToString:@"48 69"] && [TPEncodeText(@"0x48,0x69", TPCodecHex, NO, &err) isEqualToString:@"Hi"]);
        REQUIRE(TPEncodeText(@"4", TPCodecHex, NO, &err) == nil);
        NSString *jwt = TPDecodeJWT(@"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxIiwiZXhwIjoxfQ.sig", &err);
        REQUIRE([jwt containsString:@"\"alg\": \"HS256\""] && [jwt containsString:@"(expired)"] && [jwt containsString:@"\"signature\": \"sig\""]);
        REQUIRE(TPDecodeJWT(@"not a token", &err) == nil);
        NSString *iso = TPConvertTimestamp(@"1794614400", &err);
        REQUIRE(iso.length && [TPConvertTimestamp(iso, &err) isEqualToString:@"1794614400"]);
        REQUIRE([TPConvertTimestamp(@"1794614400000", &err) isEqualToString:iso] && [TPConvertTimestamp(@"2026-11-14T00:00:00Z", &err) isEqualToString:@"1794614400"]);
        REQUIRE(TPConvertTimestamp(@"no date here", &err) == nil);
        REQUIRE([TPConvertNumbers(@"a 255 b -16 x1 1.5", YES) isEqualToString:@"a 0xFF b -0x10 x1 1.5"] && [TPConvertNumbers(@"0xff,0X10", NO) isEqualToString:@"255,16"]);
        REQUIRE([TPAlignOn(@"a = 1\nlong_name=2\nx == y\n  b=3", @"=") isEqualToString:@"a         = 1\nlong_name = 2\nx == y\n  b       = 3"]);
        REQUIRE([TPAlignOn(@"a: 1\nlonger: 2", @":") isEqualToString:@"a:      1\nlonger: 2"]);
        REQUIRE([TPSortLinesByLength(@"ccc\na\nbb\n") isEqualToString:@"a\nbb\nccc\n"] && [TPEscapeRegex(@"a.b*c") isEqualToString:@"a\\.b\\*c"]);
        NSString *xml = @"<a><b x=\"1\">t</b><!-- note --><c/></a>";
        NSString *pretty = TPFormatXML(xml, YES, &err), *flat = TPFormatXML(pretty ?: @"", NO, &err);
        REQUIRE([pretty containsString:@"\n    <b x=\"1\">t</b>"] && [pretty containsString:@"<!-- note -->"] && ![pretty hasPrefix:@"<?xml"]);
        REQUIRE([flat isEqualToString:TPFormatXML(xml, NO, &err)] && ![flat containsString:@"\n"]);
        NSInteger line = 0, col = 0;
        REQUIRE(TPCheckXML(xml, &err, &line, &col) && !TPCheckXML(@"<a>\n<b></a>", &err, &line, &col) && line == 2);
        NSString *xp = TPRunXPath(@"<r><i id=\"1\"/><i id=\"2\"/></r>", @"//i/@id", &err);
        REQUIRE([xp containsString:@"2 matches"] && [xp hasSuffix:@"\n1\n2\n"] && TPRunXPath(@"<r/>", @"//[", &err) == nil);
        NSString *uuid = TPInsertText(TPInsertUUID), *pw = TPInsertText(TPInsertPassword);
        REQUIRE([uuid rangeOfString:@"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$" options:NSRegularExpressionSearch].location == 0);
        REQUIRE(pw.length == 20 && ![pw isEqualToString:TPInsertText(TPInsertPassword)]);
    });
    run(@"T-DEV-002", @"Developer tool menus under Plugins: commands run on the selection or document, conversions open a new tab, shortcuts clash with nothing", ^{
        TPPluginHost *h = [TPPluginHost shared];
        NSMenu *plugins = [reg topLevelMenuNamed:@"Plugins"];
        for (NSString *m in @[@"JSON Tools", @"XML Tools", @"Encode - Decode", @"Text Tools", @"Convert", @"Insert"]) REQUIRE([plugins itemWithTitle:m].submenu.numberOfItems > 3);
        int pretty = [h commandForPluginNamed:@"XML Tools" item:@"Pretty Print XML"], uuid = [h commandForPluginNamed:@"Insert" item:@"UUID"];
        for (int cmd : {pretty, uuid}) {
            TPKeyBinding *kb = [reg userBindingForCommand:cmd];
            REQUIRE(kb && !kb.isEmpty && [reg commandsBoundToKey:kb.keyEquivalent modifiers:kb.modifiers].count == 1);
        }
        [c newDocument];
        setText("x = aGk= ;");
        SCI(c.editor, SCI_SETSEL, 4, 8);
        REQUIRE(exec([h commandForPluginNamed:@"Encode - Decode" item:@"Base64 Decode"]) && text() == "x = hi ;");
        SCI(c.editor, SCI_UNDO);
        REQUIRE(text() == "x = aGk= ;");
        setText("a = 1\nlong_name = 2\n");
        SCI(c.editor, SCI_SETSEL, 2, 9);                                      // partial lines grow to whole lines
        REQUIRE(exec([h commandForPluginNamed:@"Text Tools" item:@"Align on ="]) && text() == "a         = 1\nlong_name = 2\n");
        setText("name,age\nAnn,30\n");
        SCI(c.editor, SCI_SETSEL, 0, 0);
        TPDocument *src = c.currentDocument;
        REQUIRE(exec([h commandForPluginNamed:@"Convert" item:@"CSV to JSON (New Tab)"]) && c.currentDocument != src);
        REQUIRE([c.currentDocument.languageId isEqualToString:@"json"] && text().find("\"age\": 30") != std::string::npos);
        setText("<r><i id=\"7\"/></r>");
        TPDevToolsTestInput = @"//i/@id";
        TPDocument *xmlDoc = c.currentDocument;
        BOOL ranXPath = exec([h commandForPluginNamed:@"XML Tools" item:@"XPath Query..."]);
        TPDevToolsTestInput = nil;
        REQUIRE(ranXPath && c.currentDocument != xmlDoc && text().find("1 match -->\n7\n") != std::string::npos);
        setText("bad");
        g_lastPrompt = nil;
        REQUIRE(exec([h commandForPluginNamed:@"Encode - Decode" item:@"Hex Bytes to Text"]) && [g_lastPrompt isEqualToString:@"Decode"] && text() == "bad");
        setText("");
        REQUIRE(exec(uuid) && text().size() == 36);
    });
    run(@"T-UI-ALERT-001", @"Long pop-up texts (command line help, debug info) scroll inside a box that fits a 13-inch screen", ^{
        NSAlert *a = [NSAlert new];
        a.messageText = @"Command Line Arguments";
        TPSetAlertText(a, [TPCommandLine helpText]);
        [a addButtonWithTitle:@"OK"];
        [a layout];
        REQUIRE([a.accessoryView isKindOfClass:NSScrollView.class] && a.window.frame.size.height < 820 && a.window.frame.size.width < 900);
        NSAlert *b = [NSAlert new];
        TPSetAlertText(b, @"A short message.");
        REQUIRE(b.accessoryView == nil && [b.informativeText isEqualToString:@"A short message."]);
        REQUIRE(TPAlertTextIsLong([TPCommandLine helpText]) && !TPAlertTextIsLong(@"one\ntwo"));
    });
    run(@"T-UI-TIPS-001", @"Toolbar tooltips: name, shortcut and what the button does; they follow the interface language", ^{
        NSString *tip = [c.toolbar tooltipForCommand:IDM_FILE_SAVE];
        REQUIRE([tip hasPrefix:@"Save ("] && [tip containsString:@"Saves the current document"]);
        REQUIRE([[c.toolbar tooltipForCommand:IDM_VIEW_DOC_MAP] containsString:@"miniature of the whole document"]);
        for (int cmd : {IDM_FILE_NEW, IDM_EDIT_CUT, IDM_SEARCH_FIND, IDM_VIEW_WRAP, IDM_VIEW_MONITORING, IDM_MACRO_STARTRECORDINGMACRO})
            REQUIRE([[c.toolbar tooltipForCommand:cmd] containsString:@"\n"]);   // every button has a description line
        [TPPrefs set:@"french.xml" forKey:@"pref.localization"];
        [c applyAllPreferences];
        REQUIRE([[c.toolbar tooltipForCommand:IDM_FILE_NEW] hasPrefix:@"Nouveau"]);
        [TPPrefs set:@"" forKey:@"pref.localization"];
        [c applyAllPreferences];
    });
    run(@"T-UPD-002", @"Over-the-air update: signed archive verified (SHA-256 + ECDSA), unpacked, checked, swapped in after the app quits; tampering refused", ^{
        TPUpdater *u = [TPUpdater shared];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = tmpPath(@"ota");
        [fm removeItemAtPath:dir error:nil];
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        auto tool = [](NSString *path, NSArray *args) { NSTask *t = [NSTask launchedTaskWithLaunchPath:path arguments:args]; [t waitUntilExit]; return t.terminationStatus; };
        // the publisher's key pair (make dmg creates it once; here a fresh one)
        NSDictionary *kp = @{(id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom, (id)kSecAttrKeySizeInBits: @256};
        SecKeyRef priv = SecKeyCreateRandomKey((__bridge CFDictionaryRef)kp, nullptr);
        SecKeyRef pub = SecKeyCopyPublicKey(priv);
        NSData *pubData = CFBridgingRelease(SecKeyCopyExternalRepresentation(pub, nullptr));
        [TPPrefs set:[pubData base64EncodedStringWithOptions:0] forKey:@"pref.updatePublicKey"];
        // the installed app (a copy of this one) and version 99.0 of it, re-signed and zipped
        NSString *installed = [dir stringByAppendingPathComponent:@"Applications/Textpad++.app"], *next = [dir stringByAppendingPathComponent:@"build/Textpad++.app"];
        REQUIRE(tool(@"/usr/bin/ditto", @[NSBundle.mainBundle.bundlePath, installed]) == 0 && tool(@"/usr/bin/ditto", @[NSBundle.mainBundle.bundlePath, next]) == 0);
        REQUIRE(tool(@"/usr/bin/plutil", @[@"-replace", @"CFBundleShortVersionString", @"-string", @"99.0", [next stringByAppendingPathComponent:@"Contents/Info.plist"]]) == 0);
        REQUIRE(tool(@"/usr/bin/codesign", @[@"--force", @"--deep", @"--sign", @"-", next]) == 0);
        NSString *zip = [dir stringByAppendingPathComponent:@"Textpad++-99.0.zip"];
        REQUIRE(tool(@"/usr/bin/ditto", @[@"-c", @"-k", @"--keepParent", next, zip]) == 0);
        NSData *zipData = [NSData dataWithContentsOfFile:zip];
        NSData *sig = CFBridgingRelease(SecKeyCreateSignature(priv, kSecKeyAlgorithmECDSASignatureMessageX962SHA256, (__bridge CFDataRef)zipData, nullptr));
        std::string hex = tpp::hashHex(tpp::HashAlgorithm::SHA256, std::string(static_cast<const char *>(zipData.bytes), zipData.length));
        TPUpdateInfo *info = [TPUpdateInfo new];
        info.version = @"99.0";
        info.needToBeUpdated = YES;
        info.location = [NSURL fileURLWithPath:zip];
        info.sha256 = @(hex.c_str());
        info.signature = [sig base64EncodedStringWithOptions:0];
        // tampering: a signature of something else, a wrong checksum
        NSString *err = nil;
        TPUpdateInfo *bad = [TPUpdateInfo new];
        bad.version = info.version; bad.location = info.location; bad.sha256 = info.sha256;
        bad.signature = [CFBridgingRelease(SecKeyCreateSignature(priv, kSecKeyAlgorithmECDSASignatureMessageX962SHA256, (__bridge CFDataRef)[@"other" dataUsingEncoding:NSUTF8StringEncoding], nullptr)) base64EncodedStringWithOptions:0];
        REQUIRE([u prepareUpdate:bad error:&err] == nil && [err containsString:@"signature"]);
        bad.signature = info.signature; bad.sha256 = @"00";
        REQUIRE([u prepareUpdate:bad error:&err] == nil && [err containsString:@"SHA-256"]);
        bad.sha256 = info.sha256; bad.version = @"98.0";
        REQUIRE([u prepareUpdate:bad error:&err] == nil && [err containsString:@"version"]);
        // the real one
        NSString *app = [u prepareUpdate:info error:&err];
        REQUIRE(app && [fm fileExistsAtPath:app]);
        NSTask *gone = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/true" arguments:@[]];
        [gone waitUntilExit];                                              // stands for the Textpad++ that has quit
        REQUIRE([u installApp:app over:installed afterProcess:gone.processIdentifier relaunch:NO wait:YES error:&err]);
        NSDictionary *now = [NSDictionary dictionaryWithContentsOfFile:[installed stringByAppendingPathComponent:@"Contents/Info.plist"]];
        REQUIRE([now[@"CFBundleShortVersionString"] isEqualToString:@"99.0"] && tool(@"/usr/bin/codesign", @[@"--verify", @"--deep", @"--strict", installed]) == 0);
        NSArray *left = [fm contentsOfDirectoryAtPath:installed.stringByDeletingLastPathComponent error:nil];
        REQUIRE(left.count == 1);                                          // no backup left behind
        // a folder the user cannot write to: no in-place update (the DMG fallback is used instead)
        chmod(installed.stringByDeletingLastPathComponent.fileSystemRepresentation, 0555);
        REQUIRE(![u canReplaceAppAt:installed]);
        chmod(installed.stringByDeletingLastPathComponent.fileSystemRepresentation, 0755);
        CFRelease(pub); CFRelease(priv);
        [fm removeItemAtPath:dir error:nil];
    });
