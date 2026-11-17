// Textpad++ — "Search results" panel. GPL-3.0-or-later.
#import "search/SearchResultsPanel.h"
#import "app/MainWindowController.h"
#import "app/LanguageService.h"
#import "app/Preferences.h"

#include <map>

@interface TPPanelHeader : NSView
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) void (^onClose)(void);
@property (nonatomic, copy) void (^onMenu)(NSEvent *e, NSView *v);
@end
@implementation TPPanelHeader
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)r {
    [[NSColor colorWithSRGBRed:0.90 green:0.90 blue:0.90 alpha:1] setFill];
    NSRectFill(self.bounds);
    [self.title drawAtPoint:NSMakePoint(6, 3) withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:11.5]}];
    NSString *x = @"✕";
    [x drawAtPoint:NSMakePoint(NSWidth(self.bounds) - 18, 2) withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:11]}];
    [@"⌄" drawAtPoint:NSMakePoint(NSWidth(self.bounds) - 38, 0) withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:12]}];
}
- (void)mouseDown:(NSEvent *)e {
    NSPoint p = [self convertPoint:e.locationInWindow fromView:nil];
    if (p.x > NSWidth(self.bounds) - 22 && self.onClose) self.onClose();
    else if (p.x > NSWidth(self.bounds) - 42 && self.onMenu) self.onMenu(e, self);
}
- (void)rightMouseDown:(NSEvent *)e { if (self.onMenu) self.onMenu(e, self); }
@end

@implementation TPSearchResultsPanel {
    __weak TPMainWindowController *_controller;
    ScintillaView *_view;
    TPPanelHeader *_header;
    std::map<sptr_t, TPResultHit> _lineToHit;           // results-view line -> hit
    std::vector<SearchResultMarkingLine> _markingLines;  // per results-view line, for the lexer
    SearchResultMarkings _markings;
    std::string _text;
    sptr_t _currentLine;
    NSInteger _lastHitCount;
    NSPanel *_floatWindow;
    __weak NSSplitView *_dockSplit;
}

- (instancetype)initWithController:(TPMainWindowController *)c {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 800, 180)])) {
        _controller = c;
        _currentLine = -1;
        _header = [[TPPanelHeader alloc] initWithFrame:NSMakeRect(0, 0, 800, 20)];
        _header.title = @"Search results";
        __weak TPSearchResultsPanel *ws = self;
        _header.onClose = ^{ [ws hidePanel]; };
        _header.onMenu = ^(NSEvent *e, NSView *v) {
            NSMenu *m = [[NSMenu alloc] initWithTitle:@"Dock"];
            NSMenuItem *a = [m addItemWithTitle:@"Docked at the Bottom" action:@selector(dockAtBottom:) keyEquivalent:@""];
            NSMenuItem *b = [m addItemWithTitle:@"Floating" action:@selector(makeFloating:) keyEquivalent:@""];
            a.target = b.target = ws;
            a.state = ws.floating ? NSControlStateValueOff : NSControlStateValueOn;
            b.state = ws.floating ? NSControlStateValueOn : NSControlStateValueOff;
            [NSMenu popUpContextMenu:m withEvent:e forView:v];
        };
        _view = [[ScintillaView alloc] initWithFrame:NSMakeRect(0, 20, 800, 160)];
        _view.delegate = self;
        [self addSubview:_view];
        [self addSubview:_header];
        SCI(_view, SCI_SETCODEPAGE, SC_CP_UTF8);
        SCI(_view, SCI_USEPOPUP, SC_POPUP_NEVER);
        SCI(_view, SCI_SETMARGINWIDTHN, 0, 0);
        SCI(_view, SCI_SETMARGINWIDTHN, 1, 0);
        SCI(_view, SCI_SETMARGINTYPEN, 2, SC_MARGIN_SYMBOL);
        SCI(_view, SCI_SETMARGINMASKN, 2, SC_MASK_FOLDERS);
        SCI(_view, SCI_SETMARGINWIDTHN, 2, 14);
        SCI(_view, SCI_SETMARGINSENSITIVEN, 2, 1);
        SCI(_view, SCI_MARKERDEFINE, SC_MARKNUM_FOLDEROPEN, SC_MARK_BOXMINUS);
        SCI(_view, SCI_MARKERDEFINE, SC_MARKNUM_FOLDER, SC_MARK_BOXPLUS);
        SCI(_view, SCI_MARKERDEFINE, SC_MARKNUM_FOLDERSUB, SC_MARK_VLINE);
        SCI(_view, SCI_MARKERDEFINE, SC_MARKNUM_FOLDERTAIL, SC_MARK_LCORNER);
        SCI(_view, SCI_MARKERDEFINE, SC_MARKNUM_FOLDEREND, SC_MARK_BOXPLUSCONNECTED);
        SCI(_view, SCI_MARKERDEFINE, SC_MARKNUM_FOLDEROPENMID, SC_MARK_BOXMINUSCONNECTED);
        SCI(_view, SCI_MARKERDEFINE, SC_MARKNUM_FOLDERMIDTAIL, SC_MARK_TCORNER);
        SCI(_view, SCI_SETAUTOMATICFOLD, SC_AUTOMATICFOLD_CLICK | SC_AUTOMATICFOLD_SHOW);
        Scintilla::ILexer5 *lexer = CreateLexer("searchResult");
        SCI(_view, SCI_SETILEXER, 0, reinterpret_cast<sptr_t>(lexer));
        SCI(_view, SCI_SETPROPERTY, reinterpret_cast<uptr_t>("fold"), reinterpret_cast<sptr_t>("1"));
        [self applyStyles];
        SCI(_view, SCI_SETREADONLY, 1);
        SCI(_view, SCI_SETCARETLINEVISIBLE, 1);
        _markings._length = 0;
        _markings._markings = nullptr;
    }
    return self;
}

- (ScintillaView *)view { return _view; }
- (NSInteger)lastHitCount { return _lastHitCount; }
- (BOOL)isFlipped { return YES; }

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    _header.frame = NSMakeRect(0, 0, NSWidth(self.bounds), 20);
    _view.frame = NSMakeRect(0, 20, NSWidth(self.bounds), MAX(0, NSHeight(self.bounds) - 20));
}

- (void)applyStyles {
    TPLanguageService *ls = [TPLanguageService shared];
    TPStyleSpec *def = [ls globalStyle:@"Default Style"];
    SCIS(_view, SCI_STYLESETFONT, STYLE_DEFAULT, (def.fontName ?: @"Courier New").UTF8String);
    SCI(_view, SCI_STYLESETSIZEFRACTIONAL, STYLE_DEFAULT, static_cast<sptr_t>([TPLanguageService macPointsFromWindowsPoints:10] * SC_FONT_SIZE_MULTIPLIER));
    SCI(_view, SCI_STYLECLEARALL);
    for (TPStyleSpec *s in [ls stylesForLexerType:@"searchResult"]) {
        if (s.fg >= 0) SCI(_view, SCI_STYLESETFORE, s.styleID, rgbToSci(s.fg));
        if (s.bg >= 0) SCI(_view, SCI_STYLESETBACK, s.styleID, rgbToSci(s.bg));
        if (s.fontStyle >= 0) SCI(_view, SCI_STYLESETBOLD, s.styleID, (s.fontStyle & 1) ? 1 : 0);
        if (s.styleID == SCE_SEARCHRESULT_SEARCH_HEADER || s.styleID == SCE_SEARCHRESULT_FILE_HEADER) SCI(_view, SCI_STYLESETEOLFILLED, s.styleID, 1);
    }
}

// upstream: the Finder is a docking panel; here it is docked under the editors or floats in its own window
- (BOOL)floating { return [[NSUserDefaults standardUserDefaults] boolForKey:@"searchResults.floating"]; }

- (void)showPanel {
    if (self.floating) {
        if (!_floatWindow) {
            _floatWindow = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 760, 260)
                                                      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow
                                                        backing:NSBackingStoreBuffered defer:YES];
            _floatWindow.releasedWhenClosed = NO;
            _floatWindow.identifier = @"TPPanelWindow";   // Escape leaves it open
            _floatWindow.hidesOnDeactivate = NO;
            _floatWindow.becomesKeyOnlyIfNeeded = YES;
            _floatWindow.frameAutosaveName = @"searchResults.floatFrame";
            if (![_floatWindow setFrameUsingName:_floatWindow.frameAutosaveName]) [_floatWindow center];
            __weak TPSearchResultsPanel *ws = self;
            [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification object:_floatWindow queue:nil
                                                          usingBlock:^(NSNotification *n) { ws.hidden = YES; }];
        }
        if (self.superview != _floatWindow.contentView) {
            NSSplitView *old = [self.superview isKindOfClass:NSSplitView.class] ? (NSSplitView *)self.superview : nil;
            [self removeFromSuperview];
            [old adjustSubviews];
            self.frame = _floatWindow.contentView.bounds;
            self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            [_floatWindow.contentView addSubview:self];
        }
        self.hidden = NO;
        _floatWindow.title = _header.title;
        [_floatWindow orderFront:nil];
        return;
    }
    if (self.superview != _dockSplit && _dockSplit) {
        [self removeFromSuperview];
        [_floatWindow orderOut:nil];
        self.autoresizingMask = NSViewNotSizable;
        [_dockSplit addSubview:self];
        self.hidden = YES;
    }
    if (!self.hidden) return;
    self.hidden = NO;
    NSSplitView *sv = (NSSplitView *)self.superview;
    [sv adjustSubviews];
    [sv setPosition:NSHeight(sv.bounds) - 200 ofDividerAtIndex:0];
}

- (void)hidePanel {
    self.hidden = YES;
    if (_floatWindow.isVisible) [_floatWindow orderOut:nil];
    if ([self.superview isKindOfClass:NSSplitView.class]) [(NSSplitView *)self.superview adjustSubviews];
}

- (void)viewDidMoveToSuperview {
    if ([self.superview isKindOfClass:NSSplitView.class]) _dockSplit = (NSSplitView *)self.superview;
}

- (void)dockAtBottom:(id)sender { [self setFloating:NO]; }
- (void)makeFloating:(id)sender { [self setFloating:YES]; }
- (void)setFloating:(BOOL)f {
    const BOOL shown = !self.hidden;
    [self hidePanel];
    [[NSUserDefaults standardUserDefaults] setBool:f forKey:@"searchResults.floating"];
    if (shown) [self showPanel];
}

static std::string commafyStd(long long v) {
    std::string s = std::to_string(v);
    for (int i = static_cast<int>(s.size()) - 3; i > 0; i -= 3) s.insert(static_cast<size_t>(i), ",");
    return s;
}

- (void)addSearch:(NSString *)what hits:(const std::vector<TPResultHit> &)hits filesSearched:(NSInteger)nFiles {
    // Count files with hits
    std::vector<std::string> fileOrder;
    std::map<std::string, std::vector<const TPResultHit *>> byFile;
    for (const auto &h : hits) {
        if (!byFile.count(h.fileLabel)) fileOrder.push_back(h.fileLabel);
        byFile[h.fileLabel].push_back(&h);
    }
    std::string block;
    std::map<sptr_t, TPResultHit> newMap;
    std::vector<SearchResultMarkingLine> newMarks;
    auto pushLine = [&](const std::string &l, const TPResultHit *hit, sptr_t segS, sptr_t segE) {
        sptr_t idx = static_cast<sptr_t>(newMarks.size());
        SearchResultMarkingLine ml;
        if (hit) { ml._segmentPostions.push_back({segS, segE}); newMap[idx] = *hit; }
        newMarks.push_back(ml);
        block += l;
        block += "\n";
    };
    std::string header = "Search \"" + StdStr(what) + "\" (" + commafyStd(static_cast<long long>(hits.size())) +
                         (hits.size() == 1 ? " hit" : " hits") + " in " + commafyStd(static_cast<long long>(fileOrder.size())) +
                         (fileOrder.size() == 1 ? " file" : " files") + " of " + commafyStd(nFiles) + " searched)";
    pushLine(header, nullptr, 0, 0);
    for (const auto &f : fileOrder) {
        const auto &list = byFile[f];
        pushLine("  " + f + " (" + commafyStd(static_cast<long long>(list.size())) + (list.size() == 1 ? " hit)" : " hits)"), nullptr, 0, 0);
        // Preferences > Searching > "show only one entry per found line": merge hits on the same line
        std::vector<std::pair<const TPResultHit *, std::vector<std::pair<sptr_t, sptr_t>>>> entries;
        for (const TPResultHit *h : list) {
            if ([TPPrefs b:@"pref.oneEntryPerLine"] && !entries.empty() && entries.back().first->line == h->line) {
                entries.back().second.push_back({h->start, h->end});
                continue;
            }
            entries.push_back({h, {{h->start, h->end}}});
        }
        for (auto &en : entries) {
            const TPResultHit *h = en.first;
            std::string prefix = "\tLine " + std::to_string(h->line + 1) + ": ";
            std::string text = h->lineText;
            if (text.size() > 1024) text = text.substr(0, 1024);
            // segment relative to the result line (prefix + offset of the match in its line)
            sptr_t segS = static_cast<sptr_t>(prefix.size()) + h->start;
            sptr_t segE = static_cast<sptr_t>(prefix.size()) + h->end;
            pushLine(prefix + text, h, segS, segE);
            for (size_t k = 1; k < en.second.size(); ++k)
                newMarks.back()._segmentPostions.push_back({static_cast<sptr_t>(prefix.size()) + en.second[k].first, static_cast<sptr_t>(prefix.size()) + en.second[k].second});
        }
    }
    // Prepend: new search on top, as upstream
    std::map<sptr_t, TPResultHit> shifted;
    sptr_t added = static_cast<sptr_t>(newMarks.size());
    for (auto &kv : _lineToHit) shifted[kv.first + added] = kv.second;
    for (auto &kv : newMap) shifted[kv.first] = kv.second;
    _lineToHit.swap(shifted);
    newMarks.insert(newMarks.end(), _markingLines.begin(), _markingLines.end());
    _markingLines.swap(newMarks);
    _markings._length = static_cast<intptr_t>(_markingLines.size());
    _markings._markings = _markingLines.data();
    char addr[64];
    snprintf(addr, sizeof(addr), "%p", static_cast<void *>(&_markings));
    SCI(_view, SCI_SETPROPERTY, reinterpret_cast<uptr_t>("@MarkingsStruct"), reinterpret_cast<sptr_t>(addr));

    _text = block + _text;
    SCI(_view, SCI_SETREADONLY, 0);
    SCI(_view, SCI_SETTEXT, 0, reinterpret_cast<sptr_t>(_text.c_str()));
    SCI(_view, SCI_SETREADONLY, 1);
    SCI(_view, SCI_COLOURISE, 0, -1);
    // fold older searches
    for (sptr_t l = added; l < SCI(_view, SCI_GETLINECOUNT); ++l) {
        int lvl = static_cast<int>(SCI(_view, SCI_GETFOLDLEVEL, l));
        if ((lvl & SC_FOLDLEVELHEADERFLAG) && (lvl & SC_FOLDLEVELNUMBERMASK) == SC_FOLDLEVELBASE && SCI(_view, SCI_GETFOLDEXPANDED, l))
            SCI(_view, SCI_FOLDLINE, l, SC_FOLDACTION_CONTRACT);
    }
    SCI(_view, SCI_GOTOLINE, 0);
    _currentLine = 0;
    _lastHitCount = static_cast<NSInteger>(hits.size());
    _header.title = [NSString stringWithFormat:@"Search results - (%ld hits)", (long)hits.size()];
    _header.needsDisplay = YES;
    _floatWindow.title = _header.title;
    [self showPanel];
}

- (void)gotoLine:(sptr_t)line {
    auto it = _lineToHit.find(line);
    if (it == _lineToHit.end()) return;
    const TPResultHit &h = it->second;
    TPMainWindowController *c = _controller;
    TPDocument *doc = nil;
    for (TPDocument *d in c.allDocuments) if (d.uid == h.docUid) doc = d;
    if (!doc && !h.path.empty()) doc = [c openFile:NSStr(h.path)];
    if (!doc) return;
    TPEditorPane *pane = [c.activePane indexOfDocument:doc] != NSNotFound ? c.activePane : ([c.otherPane indexOfDocument:doc] != NSNotFound ? c.otherPane : c.activePane);
    [c activateDocument:doc inPane:pane];
    ScintillaView *v = c.editor;
    sptr_t lineStart = SCI(v, SCI_POSITIONFROMLINE, h.line);
    SCI(v, SCI_ENSUREVISIBLE, h.line);
    SCI(v, SCI_SETSEL, lineStart + h.start, lineStart + h.end);
    SCI(v, SCI_SCROLLRANGE, lineStart + h.start, lineStart + h.end);
    _currentLine = line;
    SCI(_view, SCI_GOTOLINE, line);
}

- (void)gotoNext:(BOOL)forward {
    if (_lineToHit.empty()) return;
    auto it = forward ? _lineToHit.upper_bound(_currentLine) : _lineToHit.lower_bound(_currentLine);
    if (forward) {
        if (it == _lineToHit.end()) it = _lineToHit.begin();
    } else {
        if (it == _lineToHit.begin()) it = std::prev(_lineToHit.end());
        else --it;
    }
    [self gotoLine:it->first];
}

- (void)notification:(SCNotification *)scn {
    if (scn->nmhdr.code == SCN_DOUBLECLICK) {
        sptr_t line = SCI(_view, SCI_LINEFROMPOSITION, scn->position);
        if (_lineToHit.count(line)) [self gotoLine:line];
        else {
            int lvl = static_cast<int>(SCI(_view, SCI_GETFOLDLEVEL, line));
            if (lvl & SC_FOLDLEVELHEADERFLAG) SCI(_view, SCI_TOGGLEFOLD, line);
        }
    }
}

@end
