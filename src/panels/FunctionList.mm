// Textpad++ — View > Function List (port of upstream WinControls/FunctionList: functionParser.cpp, the parser
// rules in functionList/*.xml + overrideMap.xml, and functionListPanel.cpp). GPL-3.0-or-later.
#import "panels/Panels.h"
#import "app/MainWindowController.h"
#import "app/EditorPane.h"
#import "app/Document.h"
#import "app/LanguageService.h"
#import "app/Preferences.h"
#import "app/Session.h"
#import "app/Sci.h"

#include "BoostRegexSearch.h"
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace {

using Zones = std::vector<std::pair<sptr_t, sptr_t>>;

struct FoundInfo {
    std::string data, data2;
    sptr_t pos = -1, pos2 = -1;
};

constexpr int kFlags = SCFIND_REGEXP | SCFIND_POSIX | SCFIND_REGEXP_DOTMATCHESNL;

sptr_t searchInTarget(ScintillaView *v, const std::string &expr, sptr_t begin, sptr_t end) {
    SCI(v, SCI_SETTARGETRANGE, begin, end);
    return SCI(v, SCI_SEARCHINTARGET, expr.size(), reinterpret_cast<sptr_t>(expr.c_str()));
}

std::string textOf(ScintillaView *v, sptr_t a, sptr_t b) {
    if (b - a > 1023) b = a + 1023;   // upstream getGenericText into a 1024-char buffer
    std::string s = sciGetRange(v, a, b);
    size_t nul = s.find('\0');
    return nul == std::string::npos ? s : s.substr(0, nul);
}

bool isInZones(sptr_t pos, const Zones &zones) {
    if (pos < 0) return false;
    for (const auto &z : zones) if (pos >= z.first && pos < z.second) return true;
    return false;
}

// upstream FunctionParser and subclasses (unit / zone / mix)
struct FunctionParser {
    std::string id, displayName, commentExpr, functionExpr;
    std::vector<std::string> functionNameExprs, classNameExprs;
    virtual ~FunctionParser() = default;
    virtual void parse(std::vector<FoundInfo> &out, sptr_t begin, sptr_t end, ScintillaView *v, const std::string &cls) = 0;

    std::string parseSubLevel(sptr_t begin, sptr_t end, std::vector<std::string> exprs, sptr_t &foundPos, ScintillaView *v) {
        if (begin >= end) { foundPos = -1; return ""; }
        if (exprs.empty()) return "";
        SCI(v, SCI_SETSEARCHFLAGS, kFlags);
        sptr_t ts = searchInTarget(v, exprs[0], begin, end);
        if (ts < 0) { foundPos = -1; return ""; }
        sptr_t te = SCI(v, SCI_GETTARGETEND);
        if (exprs.size() >= 2) { exprs.erase(exprs.begin()); return parseSubLevel(ts, te, exprs, foundPos, v); }
        foundPos = ts;
        return textOf(v, ts, te);
    }

    void funcParse(std::vector<FoundInfo> &out, sptr_t begin, sptr_t end, ScintillaView *v, const std::string &cls, const Zones *commentZones) {
        if (begin >= end || functionExpr.empty()) return;
        SCI(v, SCI_SETSEARCHFLAGS, kFlags);
        sptr_t ts = searchInTarget(v, functionExpr, begin, end);
        while (ts >= 0) {
            ts = SCI(v, SCI_GETTARGETSTART);
            sptr_t te = SCI(v, SCI_GETTARGETEND);
            if (te > end) break;
            sptr_t len = te - ts;
            if (ts + len == end) break;
            FoundInfo fi;
            if (functionNameExprs.empty() && classNameExprs.empty()) {
                fi.data = textOf(v, ts, te);
                fi.pos = ts;
            } else {
                sptr_t fp = -1;
                if (!functionNameExprs.empty()) { fi.data = parseSubLevel(ts, te, functionNameExprs, fp, v); fi.pos = fp; }
                if (!cls.empty()) { fi.data2 = cls; fi.pos2 = -1; }
                else if (!classNameExprs.empty()) { fi.data2 = parseSubLevel(ts, te, classNameExprs, fp, v); fi.pos2 = fp; }
            }
            if (fi.pos != -1 || fi.pos2 != -1) {
                if (!commentZones || (!isInZones(fi.pos, *commentZones) && !isInZones(fi.pos2, *commentZones))) out.push_back(fi);
            }
            begin = ts + len;
            if (len == 0) ++begin;   // guard against empty matches
            SCI(v, SCI_SETSEARCHFLAGS, kFlags);
            ts = begin < end ? searchInTarget(v, functionExpr, begin, end) : -1;
        }
    }

    void getCommentZones(Zones &zones, sptr_t begin, sptr_t end, ScintillaView *v) {
        if (begin >= end || commentExpr.empty()) return;
        SCI(v, SCI_SETSEARCHFLAGS, kFlags);
        sptr_t ts = searchInTarget(v, commentExpr, begin, end);
        while (ts >= 0) {
            ts = SCI(v, SCI_GETTARGETSTART);
            sptr_t te = SCI(v, SCI_GETTARGETEND);
            if (te > end) break;
            zones.emplace_back(ts, te);
            sptr_t len = te - ts;
            if (ts + len == end) break;
            begin = ts + MAX(len, (sptr_t)1);
            ts = searchInTarget(v, commentExpr, begin, end);
        }
    }

    static void getInvertZones(Zones &dest, const Zones &src, sptr_t begin, sptr_t end) {
        if (src.empty()) { dest.emplace_back(begin, end); return; }
        if (begin < src[0].first) dest.emplace_back(begin, src[0].first - 1);
        size_t i = 0;
        for (; i + 1 < src.size(); ++i) {
            sptr_t nb = src[i].second + 1, ne = src[i + 1].first - 1;
            if (nb < ne) dest.emplace_back(nb, ne);
        }
        sptr_t lb = src[i].second + 1;
        if (lb < end) dest.emplace_back(lb, end);
    }
};

struct FunctionUnitParser : FunctionParser {
    void parse(std::vector<FoundInfo> &out, sptr_t begin, sptr_t end, ScintillaView *v, const std::string &cls) override {
        Zones comments, nonComments;
        getCommentZones(comments, begin, end, v);
        getInvertZones(nonComments, comments, begin, end);
        for (const auto &z : nonComments) funcParse(out, z.first, z.second, v, cls, nullptr);
    }
};

struct FunctionZoneParser : FunctionParser {
    std::string rangeExpr, openSymbole, closeSymbole;

    sptr_t getBodyClosePos(sptr_t begin, const Zones &comments, ScintillaView *v) {
        sptr_t cntOpen = 1;
        const sptr_t docLen = SCI(v, SCI_GETLENGTH);
        if (begin >= docLen) return docLen;
        std::string expr = "(" + openSymbole + "|" + closeSymbole + ")";
        SCI(v, SCI_SETSEARCHFLAGS, kFlags);
        sptr_t ts = searchInTarget(v, expr, begin, docLen);
        sptr_t te = 0;
        int guard = 0;
        do {
            if (ts >= 0) {
                te = SCI(v, SCI_GETTARGETEND);
                if (!isInZones(ts, comments)) {
                    if (searchInTarget(v, openSymbole, ts, te) >= 0) ++cntOpen;
                    else --cntOpen;
                }
            } else {
                cntOpen = 0;
                te = begin;
            }
            ts = searchInTarget(v, expr, MAX(te, ts + 1), docLen);
        } while (cntOpen && ++guard < 1000000);
        return te;
    }

    void classParse(std::vector<FoundInfo> &out, Zones &scanned, const Zones &comments, sptr_t begin, sptr_t end, ScintillaView *v) {
        if (begin >= end) return;
        SCI(v, SCI_SETSEARCHFLAGS, kFlags);
        sptr_t ts = searchInTarget(v, rangeExpr, begin, end);
        while (ts >= 0) {
            sptr_t te = SCI(v, SCI_GETTARGETEND);
            sptr_t fp = 0;
            std::string cls = parseSubLevel(ts, te, classNameExprs2, fp, v);
            if (!openSymbole.empty() && !closeSymbole.empty()) te = getBodyClosePos(te, comments, v);
            if (te > end) break;
            scanned.emplace_back(ts, te);
            sptr_t len = te - ts;
            if (ts + len == end) break;
            if (!isInZones(ts, comments)) funcParse(out, ts, te, v, cls, &comments);
            begin = ts + MAX(len, (sptr_t)1);
            SCI(v, SCI_SETSEARCHFLAGS, kFlags);
            ts = searchInTarget(v, rangeExpr, begin, end);
        }
    }
    std::vector<std::string> classNameExprs2;   // <classRange><className><nameExpr>

    void parse(std::vector<FoundInfo> &out, sptr_t begin, sptr_t end, ScintillaView *v, const std::string &) override {
        Zones classes, comments, nonComments;
        getCommentZones(comments, begin, end, v);
        getInvertZones(nonComments, comments, begin, end);
        for (const auto &z : nonComments) classParse(out, classes, comments, z.first, z.second, v);
    }
};

struct FunctionMixParser : FunctionZoneParser {
    std::unique_ptr<FunctionUnitParser> unit;
    void parse(std::vector<FoundInfo> &out, sptr_t begin, sptr_t end, ScintillaView *v, const std::string &cls) override {
        Zones comments, scanned, nonScanned;
        getCommentZones(comments, begin, end, v);
        classParse(out, scanned, comments, begin, end, v);
        for (const auto &z : scanned) { Zones tmp; classParse(out, tmp, comments, z.first, z.second, v); }
        getInvertZones(nonScanned, scanned, begin, end);
        if (unit) for (const auto &z : nonScanned) unit->funcParse(out, z.first, z.second, v, cls, &comments);
    }
};

std::string attr(NSXMLElement *e, NSString *n) { NSString *s = [e attributeForName:n].stringValue; return s ? std::string(s.UTF8String) : std::string(); }
std::vector<std::string> exprs(NSXMLElement *parent, NSString *container, NSString *item) {
    std::vector<std::string> r;
    NSXMLElement *c = [parent elementsForName:container].firstObject;
    for (NSXMLElement *x in [c elementsForName:item]) { std::string s = attr(x, @"expr"); if (!s.empty()) r.push_back(s); }
    return r;
}

// Parser rules are multi-line (?x) regexes with # comments inside attribute values. XML attribute-value
// normalisation would turn their line breaks into spaces (and a comment would then swallow the rest), so line
// breaks and tabs inside attribute values become character references first (upstream: NppXml::loadFileFunctionParser).
NSData *protectAttributeWhitespace(NSData *in) {
    std::string s(static_cast<const char *>(in.bytes), in.length), out;
    out.reserve(s.size() + 1024);
    bool inTag = false;
    char quote = 0;
    for (size_t i = 0; i < s.size(); ++i) {
        char ch = s[i];
        if (!inTag && s.compare(i, 4, "<!--") == 0) { size_t e = s.find("-->", i + 4); e = e == std::string::npos ? s.size() : e + 3; out.append(s, i, e - i); i = e - 1; continue; }
        if (!inTag && s.compare(i, 9, "<![CDATA[") == 0) { size_t e = s.find("]]>", i + 9); e = e == std::string::npos ? s.size() : e + 3; out.append(s, i, e - i); i = e - 1; continue; }
        if (!inTag) { if (ch == '<') inTag = true; out += ch; continue; }
        if (quote) {
            if (ch == quote) quote = 0;
            if (quote && ch == '\n') { out += "&#10;"; continue; }
            if (quote && ch == '\r') { out += "&#13;"; continue; }
            if (quote && ch == '\t') { out += "&#9;"; continue; }
            out += ch;
            continue;
        }
        if (ch == '"' || ch == '\'') quote = ch;
        else if (ch == '>') inTag = false;
        out += ch;
    }
    return [NSData dataWithBytes:out.data() length:out.size()];
}

std::shared_ptr<FunctionParser> loadParser(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nullptr;
    data = protectAttributeWhitespace(data);
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:nil];
    NSXMLElement *root = doc.rootElement;
    NSXMLElement *fl = [root elementsForName:@"functionList"].firstObject;
    NSXMLElement *p = [fl elementsForName:@"parser"].firstObject;
    if (!p || attr(p, @"id").empty()) return nullptr;
    NSXMLElement *cr = [p elementsForName:@"classRange"].firstObject, *fn = [p elementsForName:@"function"].firstObject;
    auto fillCommon = [&](FunctionParser &fp) {
        fp.id = attr(p, @"id");
        fp.displayName = attr(p, @"displayName").empty() ? fp.id : attr(p, @"displayName");
        fp.commentExpr = attr(p, @"commentExpr");
    };
    auto fillZone = [&](FunctionZoneParser &z) {
        z.rangeExpr = attr(cr, @"mainExpr");
        z.openSymbole = attr(cr, @"openSymbole");
        z.closeSymbole = attr(cr, @"closeSymbole");
        z.classNameExprs2 = exprs(cr, @"className", @"nameExpr");
        z.classNameExprs = z.classNameExprs2;   // upstream: one _classNameExprArray for the zone parser
        NSXMLElement *cf = [cr elementsForName:@"function"].firstObject;
        z.functionExpr = attr(cf, @"mainExpr");
        z.functionNameExprs = exprs(cf, @"functionName", @"funcNameExpr");
    };
    if (cr && fn) {
        auto m = std::make_shared<FunctionMixParser>();
        fillCommon(*m); fillZone(*m);
        m->unit = std::make_unique<FunctionUnitParser>();
        fillCommon(*m->unit);
        m->unit->functionExpr = attr(fn, @"mainExpr");
        m->unit->functionNameExprs = exprs(fn, @"functionName", @"nameExpr");
        m->unit->classNameExprs = exprs(fn, @"className", @"nameExpr");
        return m;
    }
    if (cr) { auto z = std::make_shared<FunctionZoneParser>(); fillCommon(*z); fillZone(*z); return z; }
    if (fn) {
        auto u = std::make_shared<FunctionUnitParser>();
        fillCommon(*u);
        u->functionExpr = attr(fn, @"mainExpr");
        u->functionNameExprs = exprs(fn, @"functionName", @"nameExpr");
        u->classNameExprs = exprs(fn, @"className", @"nameExpr");
        return u;
    }
    return nullptr;
}

// user functionList folder first, then the bundled rules (upstream: user path, then installed path)
NSArray<NSString *> *ruleDirs() {
    return @[[[TPSession shared].settingsDirectory stringByAppendingPathComponent:@"functionList"],
             [[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:@"data/functionList"]];
}

// overrideMap.xml: langID / userDefinedLangName -> rule file
NSString *overrideFor(NSString *languageId) {
    static NSDictionary<NSString *, NSString *> *udl;
    if (!udl) {
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        for (NSString *dir in ruleDirs().reverseObjectEnumerator) {
            NSData *d = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"overrideMap.xml"]];
            NSXMLDocument *doc = d ? [[NSXMLDocument alloc] initWithData:d options:0 error:nil] : nil;
            for (NSXMLElement *a in [doc nodesForXPath:@"//associationMap/association" error:nil]) {
                NSString *idv = [a attributeForName:@"id"].stringValue, *u = [a attributeForName:@"userDefinedLangName"].stringValue;
                if (idv.length && u.length) m[[@"udl:" stringByAppendingString:u]] = idv;
            }
        }
        udl = m;
    }
    return udl[languageId];
}

}  // namespace

// ================================================================ panel
@interface TPFuncNode : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) sptr_t pos;      // -1 for the root and class nodes
@property (nonatomic, strong) NSMutableArray<TPFuncNode *> *children;
@property (nonatomic) BOOL isClass;
@end
@implementation TPFuncNode
@end

@interface TPFunctionListPanel () <NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate>
@end

@implementation TPFunctionListPanel {
    __weak TPMainWindowController *_c;
    NSView *_box;
    NSSearchField *_search;
    NSButton *_sortButton, *_reloadButton;
    NSScrollView *_scroll;
    TPFuncNode *_root;
    __weak TPDocument *_parsedDoc;
    NSString *_parsedLang;
    BOOL _parsedDirty;
    std::vector<FoundInfo> _found;
}

- (instancetype)initWithController:(TPMainWindowController *)c {
    if ((self = [super init])) {
        _c = c;
        _box = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, 400)];
        _search = [[NSSearchField alloc] initWithFrame:NSMakeRect(4, 4, 200, 24)];
        _search.placeholderString = @"Search";
        _search.delegate = self;
        _search.autoresizingMask = NSViewWidthSizable;
        _sortButton = [NSButton buttonWithTitle:@"A↓Z" target:self action:@selector(toggleSort:)];
        _sortButton.buttonType = NSButtonTypePushOnPushOff;
        _sortButton.toolTip = @"Sort";
        _reloadButton = [NSButton buttonWithTitle:@"↻" target:self action:@selector(reloadClicked:)];
        _reloadButton.toolTip = @"Reload";
        for (NSButton *b in @[_sortButton, _reloadButton]) { b.bezelStyle = NSBezelStyleTexturedRounded; b.autoresizingMask = NSViewMinXMargin; }
        _scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        _scroll.hasVerticalScroller = YES;
        _scroll.autohidesScrollers = YES;
        _outline = [[NSOutlineView alloc] initWithFrame:NSZeroRect];
        NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
        col.resizingMask = NSTableColumnAutoresizingMask;
        [_outline addTableColumn:col];
        _outline.outlineTableColumn = col;
        _outline.headerView = nil;
        _outline.dataSource = self;
        _outline.delegate = self;
        _outline.target = self;
        _outline.doubleAction = @selector(openSelection:);
        _outline.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
        _scroll.documentView = _outline;
        for (NSView *v in @[_search, _sortButton, _reloadButton, _scroll]) [_box addSubview:v];
        _sortButton.state = [[NSUserDefaults standardUserDefaults] boolForKey:@"funclist.sort"] ? NSControlStateValueOn : NSControlStateValueOff;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(layout) name:NSViewFrameDidChangeNotification object:_box];
        _box.postsFrameChangedNotifications = YES;
        [self layout];
    }
    return self;
}

- (void)layout {
    NSRect b = _box.bounds;
    _search.frame = NSMakeRect(4, NSHeight(b) - 30, NSWidth(b) - 84, 24);
    _sortButton.frame = NSMakeRect(NSWidth(b) - 78, NSHeight(b) - 31, 40, 26);
    _reloadButton.frame = NSMakeRect(NSWidth(b) - 38, NSHeight(b) - 31, 34, 26);
    _scroll.frame = NSMakeRect(0, 0, NSWidth(b), MAX(0, NSHeight(b) - 34));
}

- (NSString *)panelIdentifier { return @"funclist"; }
- (NSString *)panelTitle { return @"Function List"; }
- (NSView *)panelView { return _box; }
- (TPDockSide)defaultSide { return TPDockRight; }
- (void)panelDidShow { [self reload]; }
- (void)focusPanel { [_outline.window makeFirstResponder:_outline]; }

// re-parse when another document is shown, its language changes or it was saved (upstream: on activation / save)
- (void)documentsChanged {
    TPDocument *d = _c.currentDocument;
    BOOL saved = _parsedDirty && !d.dirty;
    if (d != _parsedDoc || ![d.languageId isEqualToString:_parsedLang] || saved) [self reload];
    _parsedDirty = d.dirty;
}
- (void)editorViewChanged { [self markEntry]; }

- (BOOL)sorted { return _sortButton.state == NSControlStateValueOn; }
- (void)setSorted:(BOOL)s { _sortButton.state = s; [self toggleSort:nil]; }
- (NSString *)filter { return _search.stringValue ?: @""; }
- (void)setFilter:(NSString *)f { _search.stringValue = f ?: @""; [self rebuildTree]; }
- (void)toggleSort:(id)sender { [[NSUserDefaults standardUserDefaults] setBool:self.sorted forKey:@"funclist.sort"]; [self rebuildTree]; }
- (void)reloadClicked:(id)sender { [self reload]; }
- (void)controlTextDidChange:(NSNotification *)n { [self rebuildTree]; }

- (BOOL)parseDocument:(TPDocument *)d {
    _found.clear();
    if (!d) return NO;
    NSString *lang = d.languageId ?: @"normal";
    NSString *file = overrideFor(lang);
    if (!file) {
        if ([lang hasPrefix:@"udl:"]) return NO;
        file = [([lang isEqualToString:@"javascript"] ? @"javascript.js" : lang) stringByAppendingPathExtension:@"xml"];
    }
    std::shared_ptr<FunctionParser> parser;
    for (NSString *dir in ruleDirs()) {
        NSString *p = [dir stringByAppendingPathComponent:file];
        if ([[NSFileManager defaultManager] fileExistsAtPath:p] && (parser = loadParser(p))) break;
    }
    if (!parser) return NO;
    __block std::vector<FoundInfo> found;
    [_c withDocument:d perform:^(ScintillaView *v) {
        const sptr_t ts = SCI(v, SCI_GETTARGETSTART), te = SCI(v, SCI_GETTARGETEND), fl = SCI(v, SCI_GETSEARCHFLAGS);
        parser->parse(found, 0, SCI(v, SCI_GETLENGTH), v, "");
        SCI(v, SCI_SETSEARCHFLAGS, fl);
        SCI(v, SCI_SETTARGETRANGE, ts, te);
    }];
    _found = found;
    return YES;
}

- (void)reload {
    TPDocument *d = _c.currentDocument;
    _parsedDoc = d;
    _parsedLang = d.languageId;
    _parsedDirty = d.dirty;
    BOOL ok = [self parseDocument:d];
    _root = nil;
    if (ok) {
        _root = [TPFuncNode new];
        _root.name = d.displayName;
        _root.pos = -1;
    }
    [self rebuildTree];
}

// upstream addEntry: a leaf under its class node (created on demand) or under the root
- (void)rebuildTree {
    if (!_root) { [_outline reloadData]; return; }
    _root.children = [NSMutableArray array];
    NSString *f = self.filter.lowercaseString;
    NSMutableDictionary<NSString *, TPFuncNode *> *classes = [NSMutableDictionary dictionary];
    for (const FoundInfo &fi : _found) {
        NSString *name = NSStr(fi.data);
        if (f.length && ![name.lowercaseString containsString:f]) continue;   // upstream search shows matching leaves
        TPFuncNode *leaf = [TPFuncNode new];
        leaf.name = name;
        leaf.pos = fi.pos;
        NSString *cls = NSStr(fi.data2);
        if (cls.length && !f.length) {
            TPFuncNode *node = classes[cls];
            if (!node) {
                node = [TPFuncNode new];
                node.name = cls; node.pos = -1; node.isClass = YES; node.children = [NSMutableArray array];
                classes[cls] = node;
                [_root.children addObject:node];
            }
            [node.children addObject:leaf];
        } else {
            [_root.children addObject:leaf];
        }
    }
    if (self.sorted) {
        NSSortDescriptor *sd = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
        [_root.children sortUsingDescriptors:@[sd]];
        for (TPFuncNode *n in _root.children) [n.children sortUsingDescriptors:@[sd]];
    }
    [_outline reloadData];
    [_outline expandItem:_root expandChildren:YES];
    [self markEntry];
}

- (TPFuncNode *)rootNode { return _root; }
- (NSArray<NSString *> *)leafNames {
    NSMutableArray *a = [NSMutableArray array];
    for (TPFuncNode *n in _root.children) {
        if (n.isClass) for (TPFuncNode *l in n.children) [a addObject:[NSString stringWithFormat:@"%@::%@", n.name, l.name]];
        else [a addObject:n.name];
    }
    return a;
}

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(TPFuncNode *)item {
    if (!item) return _root ? 1 : 0;
    return (NSInteger)item.children.count;
}
- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)i ofItem:(TPFuncNode *)item { return item ? item.children[(NSUInteger)i] : _root; }
- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(TPFuncNode *)item { return item.children.count > 0; }
- (NSView *)outlineView:(NSOutlineView *)ov viewForTableColumn:(NSTableColumn *)col item:(TPFuncNode *)item {
    NSTextField *t = [ov makeViewWithIdentifier:@"fn" owner:self];
    if (!t) { t = [NSTextField labelWithString:@""]; t.identifier = @"fn"; t.lineBreakMode = NSLineBreakByTruncatingTail; }
    t.stringValue = item.name ?: @"";
    t.font = item == _root || item.isClass ? [NSFont boldSystemFontOfSize:12] : [NSFont systemFontOfSize:12];
    return t;
}

// upstream openSelection: ensure the line is visible and centre the position, then focus the editor
- (BOOL)openItem:(TPFuncNode *)n {
    if (!n || n.pos < 0) return NO;
    ScintillaView *v = _c.editor;
    sptr_t line = SCI(v, SCI_LINEFROMPOSITION, n.pos);
    SCI(v, SCI_ENSUREVISIBLE, line);
    SCI(v, SCI_GOTOPOS, n.pos);
    SCI(v, SCI_SETFIRSTVISIBLELINE, MAX((sptr_t)0, SCI(v, SCI_VISIBLEFROMDOCLINE, line) - SCI(v, SCI_LINESONSCREEN) / 2));
    [v.window makeFirstResponder:v.content];
    return YES;
}
- (void)openSelection:(id)sender {
    TPFuncNode *n = [_outline itemAtRow:_outline.clickedRow >= 0 ? _outline.clickedRow : _outline.selectedRow];
    if (![self openItem:n] && n.children.count) {
        if ([_outline isItemExpanded:n]) [_outline collapseItem:n]; else [_outline expandItem:n];
    }
}
- (BOOL)openEntryNamed:(NSString *)name {
    for (NSInteger r = 0; r < _outline.numberOfRows; ++r) {
        TPFuncNode *n = [_outline itemAtRow:r];
        if ([n.name isEqualToString:name] && n.pos >= 0) { [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)r] byExtendingSelection:NO]; return [self openItem:n]; }
    }
    return NO;
}

// upstream markEntry: select the entry whose line is the last one at or before the caret line
- (void)markEntry {
    if (!_root || !_box.superview) return;
    ScintillaView *v = _c.editor;
    sptr_t caretLine = SCI(v, SCI_LINEFROMPOSITION, SCI(v, SCI_GETCURRENTPOS));
    TPFuncNode *best = nil;
    sptr_t bestLine = -1;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:_root];
    while (stack.count) {
        TPFuncNode *n = stack.lastObject; [stack removeLastObject];
        for (TPFuncNode *c in n.children) [stack addObject:c];
        if (n.pos < 0) continue;
        sptr_t l = SCI(v, SCI_LINEFROMPOSITION, n.pos);
        if (l <= caretLine && l > bestLine) { bestLine = l; best = n; }
    }
    NSInteger row = [_outline rowForItem:best ?: _root];
    if (row >= 0) [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
}
- (NSString *)markedEntryName { TPFuncNode *n = [_outline itemAtRow:_outline.selectedRow]; return n.name; }

@end
