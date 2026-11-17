// Textpad++ — languages, lexers and styles. GPL-3.0-or-later.
#import "app/LanguageService.h"
#import "app/Session.h"
#import "app/Document.h"
#import "app/Preferences.h"
#import "app/UserDefinedLanguages.h"

struct LangRow { const char* name; const char* shortName; const char* longName; const char* lexer; int idm; };
static const LangRow kLangRows[] = {
#include "NppLangTable.inc"
};

@implementation TPLanguage
@end

static int parseColor(NSString *s) {
    if (s.length != 6) return -1;
    unsigned v = 0;
    if (![[NSScanner scannerWithString:s] scanHexInt:&v]) return -1;
    return static_cast<int>(v);
}

static TPStyleSpec *styleFromElement(NSXMLElement *e) {
    TPStyleSpec *s = [TPStyleSpec new];
    s.name = [[e attributeForName:@"name"] stringValue] ?: @"";
    s.styleID = [[[e attributeForName:@"styleID"] stringValue] intValue];
    NSString *fg = [[e attributeForName:@"fgColor"] stringValue];
    NSString *bg = [[e attributeForName:@"bgColor"] stringValue];
    s.fg = fg ? parseColor(fg) : -1;
    s.bg = bg ? parseColor(bg) : -1;
    NSString *fn = [[e attributeForName:@"fontName"] stringValue];
    s.fontName = fn.length ? fn : nil;
    NSString *fst = [[e attributeForName:@"fontStyle"] stringValue];
    s.fontStyle = fst.length ? fst.intValue : -1;
    NSString *fsz = [[e attributeForName:@"fontSize"] stringValue];
    s.fontSize = fsz.length ? fsz.doubleValue : 0;
    NSString *kc = [[e attributeForName:@"keywordClass"] stringValue];
    s.keywordClass = kc.length ? kc : nil;
    NSString *cs = [[e attributeForName:@"colorStyle"] stringValue];
    s.colorStyle = cs.length ? cs.intValue : 3;
    s.nesting = [[[e attributeForName:@"nesting"] stringValue] intValue];
    s.userKeywords = [e.stringValue ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    s.element = e;
    return s;
}

@implementation TPStyleSpec
- (id)copyWithZone:(NSZone *)zone {
    TPStyleSpec *c = [TPStyleSpec new];
    c.name = _name; c.styleID = _styleID; c.fg = _fg; c.bg = _bg; c.fontName = _fontName; c.fontStyle = _fontStyle;
    c.fontSize = _fontSize; c.keywordClass = _keywordClass; c.colorStyle = _colorStyle; c.nesting = _nesting;
    c.userKeywords = _userKeywords; c.element = _element;
    return c;
}
@end

@implementation TPLexerType
@end

// upstream ScintillaEditView::setStyle: Settings > Style Configurator > Global Styles > Global override
static TPStyleSpec *applyGlobalOverride(TPStyleSpec *in, TPStyleSpec *go) {
    const BOOL fg = [TPPrefs b:@"pref.go.fg"], bg = [TPPrefs b:@"pref.go.bg"], font = [TPPrefs b:@"pref.go.font"],
               size = [TPPrefs b:@"pref.go.fontSize"], bold = [TPPrefs b:@"pref.go.bold"], italic = [TPPrefs b:@"pref.go.italic"],
               underline = [TPPrefs b:@"pref.go.underline"];
    if (!go || !(fg || bg || font || size || bold || italic || underline)) return in;
    TPStyleSpec *s = [in copy];
    if (fg) {
        if ((go.colorStyle & 1) && go.fg >= 0) { s.colorStyle |= 1; s.fg = go.fg; }
        else if (s.styleID == STYLE_DEFAULT) s.colorStyle |= 1;
        else s.colorStyle &= ~1;
    }
    if (bg) {
        if ((go.colorStyle & 2) && go.bg >= 0) { s.colorStyle |= 2; s.bg = go.bg; }
        else if (s.styleID == STYLE_DEFAULT) s.colorStyle |= 2;
        else s.colorStyle &= ~2;
    }
    if (font && go.fontName.length) s.fontName = go.fontName;
    if (size && go.fontSize > 0) s.fontSize = go.fontSize;
    if (go.fontStyle >= 0) {
        int st = s.fontStyle < 0 ? 0 : s.fontStyle;
        if (bold) st = (go.fontStyle & 1) ? (st | 1) : (st & ~1);
        if (italic) st = (go.fontStyle & 2) ? (st | 2) : (st & ~2);
        if (underline) st = (go.fontStyle & 4) ? (st | 4) : (st & ~4);
        if (bold || italic || underline) s.fontStyle = st;
    }
    return s;
}

@implementation TPLanguageService {
    NSMutableArray<TPLanguage *> *_languages;
    NSMutableDictionary<NSString *, TPLanguage *> *_byId;
    NSMutableDictionary<NSNumber *, TPLanguage *> *_byCmd;
    NSMutableDictionary<NSString *, TPLanguage *> *_byExt;
    NSMutableDictionary<NSString *, NSArray<TPStyleSpec *> *> *_lexerStyles;
    NSMutableDictionary<NSString *, TPStyleSpec *> *_globalStyles;
    NSXMLDocument *_themeDoc;
    NSArray<TPLexerType *> *_lexerTypes;
    NSMutableDictionary<NSString *, TPLexerType *> *_lexerTypeByName;
    NSArray<TPStyleSpec *> *_globalStyleList;
    NSMutableDictionary<NSString *, TPLanguage *> *_byUserExt;
}

+ (instancetype)shared {
    static TPLanguageService *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [TPLanguageService new]; });
    return s;
}

+ (double)macPointsFromWindowsPoints:(double)pt {
    return pt * 96.0 / 72.0;
}

- (instancetype)init {
    if ((self = [super init])) {
        _languages = [NSMutableArray array];
        _byId = [NSMutableDictionary dictionary];
        _byCmd = [NSMutableDictionary dictionary];
        _byExt = [NSMutableDictionary dictionary];
        _lexerStyles = [NSMutableDictionary dictionary];
        _globalStyles = [NSMutableDictionary dictionary];
        for (const LangRow &r : kLangRows) {
            TPLanguage *l = [TPLanguage new];
            l.langId = @(r.name);
            l.shortName = @(r.shortName);
            l.longName = @(r.longName);
            l.lexerName = @(r.lexer);
            l.menuCommand = r.idm;
            l.extensions = @[];
            l.keywords = @{};
            [_languages addObject:l];
            _byId[l.langId] = l;
            if (r.idm) _byCmd[@(r.idm)] = l;
        }
        [self loadLangs];
        NSString *stylers = [TPLanguageService defaultThemePath];
        if (stylers) [self loadTheme:stylers error:nil];
    }
    return self;
}

- (NSArray<TPLanguage *> *)languages { return _languages; }

- (void)loadLangs {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"langs.model" ofType:@"xml" inDirectory:@"data"];
    if (!path) return;
    NSError *err = nil;
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] options:0 error:&err];
    for (NSXMLElement *e in [doc nodesForXPath:@"//Languages/Language" error:nil]) {
        NSString *name = [[e attributeForName:@"name"] stringValue];
        TPLanguage *l = _byId[name];
        if (!l) continue;
        NSString *ext = [[e attributeForName:@"ext"] stringValue] ?: @"";
        NSMutableArray *exts = [NSMutableArray array];
        for (NSString *x in [ext componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) {
            if (!x.length) continue;
            [exts addObject:x.lowercaseString];
            if (!_byExt[x.lowercaseString]) _byExt[x.lowercaseString] = l;
        }
        l.extensions = exts;
        NSString *cl = [[e attributeForName:@"commentLine"] stringValue];
        NSString *cs = [[e attributeForName:@"commentStart"] stringValue];
        NSString *ce = [[e attributeForName:@"commentEnd"] stringValue];
        l.commentLine = cl.length ? cl : nil;
        l.commentStart = cs.length ? cs : nil;
        l.commentEnd = ce.length ? ce : nil;
        NSMutableDictionary *kw = [NSMutableDictionary dictionary];
        for (NSXMLElement *k in [e elementsForName:@"Keywords"]) {
            NSString *kn = [[k attributeForName:@"name"] stringValue];
            if (kn) kw[kn] = k.stringValue ?: @"";
        }
        l.keywords = kw;
    }
}

- (BOOL)loadTheme:(NSString *)stylersPath error:(NSString **)error {
    NSError *err = nil;
    NSData *data = [NSData dataWithContentsOfFile:stylersPath];
    NSXMLDocument *doc = data ? [[NSXMLDocument alloc] initWithData:data options:NSXMLNodePreserveWhitespace | NSXMLNodePreserveCDATA error:&err] : nil;
    if (!doc) {
        if (error) *error = err.localizedDescription ?: @"Cannot parse theme";
        return NO;
    }
    NSMutableDictionary *lexers = [NSMutableDictionary dictionary];
    NSMutableArray<TPLexerType *> *types = [NSMutableArray array];
    NSMutableDictionary *typeByName = [NSMutableDictionary dictionary];
    for (NSXMLElement *lt in [doc nodesForXPath:@"//LexerStyles/LexerType" error:nil]) {
        NSString *name = [[lt attributeForName:@"name"] stringValue];
        if (!name) continue;
        NSMutableArray *arr = [NSMutableArray array];
        for (NSXMLElement *ws in [lt elementsForName:@"WordsStyle"]) [arr addObject:styleFromElement(ws)];
        lexers[name] = arr;
        TPLexerType *t = [TPLexerType new];
        t.name = name;
        t.desc = [[lt attributeForName:@"desc"] stringValue] ?: name;
        t.userExt = [[lt attributeForName:@"ext"] stringValue] ?: @"";
        t.styles = arr;
        t.element = lt;
        [types addObject:t];
        typeByName[name] = t;
    }
    NSMutableDictionary *globals = [NSMutableDictionary dictionary];
    NSMutableArray *globalList = [NSMutableArray array];
    for (NSXMLElement *ws in [doc nodesForXPath:@"//GlobalStyles/WidgetStyle" error:nil]) {
        TPStyleSpec *s = styleFromElement(ws);
        globals[s.name] = s;
        [globalList addObject:s];
    }
    _lexerStyles = lexers;
    _globalStyles = globals;
    _globalStyleList = globalList;
    _lexerTypes = types;
    _lexerTypeByName = typeByName;
    _themeDoc = doc;
    _themeModified = NO;
    _themePath = [stylersPath copy];
    [self rebuildUserExtensions];
    return YES;
}

// ---------------------------------------------------------------- Style Configurator support
- (NSArray<TPLexerType *> *)lexerTypes { return _lexerTypes ?: @[]; }
- (NSArray<TPStyleSpec *> *)globalStyleList { return _globalStyleList ?: @[]; }
- (TPLexerType *)lexerTypeNamed:(NSString *)name { return _lexerTypeByName[name]; }

- (void)rebuildUserExtensions {
    _byUserExt = [NSMutableDictionary dictionary];
    for (TPLexerType *t in _lexerTypes) {
        TPLanguage *l = _byId[t.name];
        if (!l) continue;
        for (NSString *x in [t.userExt componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet])
            if (x.length && !_byUserExt[x.lowercaseString]) _byUserExt[x.lowercaseString] = l;
    }
}

static void setAttr(NSXMLElement *e, NSString *name, NSString *_Nullable value) {
    if (!e) return;
    if (!value) { [e removeAttributeForName:name]; return; }
    NSXMLNode *a = [e attributeForName:name];
    if (a) a.stringValue = value;
    else [e addAttribute:[NSXMLNode attributeWithName:name stringValue:value]];
}

- (void)styleDidChange:(TPStyleSpec *)st {
    NSXMLElement *e = st.element;
    setAttr(e, @"fgColor", st.fg >= 0 ? [NSString stringWithFormat:@"%06X", st.fg] : nil);
    setAttr(e, @"bgColor", st.bg >= 0 ? [NSString stringWithFormat:@"%06X", st.bg] : nil);
    setAttr(e, @"fontName", st.fontName ?: @"");
    setAttr(e, @"fontStyle", [NSString stringWithFormat:@"%d", MAX(0, st.fontStyle)]);
    setAttr(e, @"fontSize", st.fontSize > 0 ? [NSString stringWithFormat:@"%g", st.fontSize] : @"");
    setAttr(e, @"colorStyle", st.colorStyle != 3 ? [NSString stringWithFormat:@"%d", st.colorStyle] : nil);
    _themeModified = YES;
}

- (void)setUserExt:(NSString *)ext forLexerType:(TPLexerType *)lt {
    lt.userExt = ext ?: @"";
    setAttr(lt.element, @"ext", lt.userExt);
    [self rebuildUserExtensions];
    _themeModified = YES;
}

- (void)setUserKeywords:(NSString *)words forStyle:(TPStyleSpec *)st {
    st.userKeywords = words ?: @"";
    if (st.element) st.element.stringValue = st.userKeywords;
    _themeModified = YES;
}

- (NSString *)defaultKeywordsForLanguage:(NSString *)langId keywordClass:(NSString *)cls {
    return _byId[langId].keywords[cls] ?: @"";
}

+ (NSString *)defaultThemePath {
    NSString *user = [[TPSession shared].settingsDirectory stringByAppendingPathComponent:@"stylers.xml"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:user]) return user;
    return [[NSBundle mainBundle] pathForResource:@"stylers.model" ofType:@"xml" inDirectory:@"data"];
}

+ (NSString *)themePathForFileName:(NSString *)fileName {
    NSString *user = [[[TPSession shared].settingsDirectory stringByAppendingPathComponent:@"themes"] stringByAppendingPathComponent:fileName];
    if ([[NSFileManager defaultManager] fileExistsAtPath:user]) return user;
    NSString *bundled = [[[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:@"data/themes"] stringByAppendingPathComponent:fileName];
    return [[NSFileManager defaultManager] fileExistsAtPath:bundled] ? bundled : nil;
}

+ (NSString *)writableThemePathFor:(NSString *)path {
    NSString *support = [TPSession shared].settingsDirectory;
    NSString *bundle = [NSBundle mainBundle].resourcePath;
    if (![path hasPrefix:bundle]) return path;
    if ([path.lastPathComponent isEqualToString:@"stylers.model.xml"]) return [support stringByAppendingPathComponent:@"stylers.xml"];
    return [[support stringByAppendingPathComponent:@"themes"] stringByAppendingPathComponent:path.lastPathComponent];
}

- (NSString *)saveThemeWithError:(NSString **)error {
    if (!_themeDoc || !_themePath) { if (error) *error = @"No theme loaded"; return nil; }
    NSString *dest = [TPLanguageService writableThemePathFor:_themePath];
    [[NSFileManager defaultManager] createDirectoryAtPath:dest.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSError *err = nil;
    if (![[_themeDoc XMLDataWithOptions:NSXMLNodePreserveWhitespace] writeToFile:dest options:NSDataWritingAtomic error:&err]) {
        if (error) *error = err.localizedDescription;
        return nil;
    }
    _themePath = [dest copy];
    _themeModified = NO;
    return dest;
}

- (TPLanguage *)languageForId:(NSString *)langId {
    if ([langId hasPrefix:@"udl:"]) return [[TPUserLanguages shared] languageDescriptorForId:langId];
    return _byId[langId];
}
- (TPLanguage *)languageForMenuCommand:(int)cmd { return _byCmd[@(cmd)]; }
- (TPStyleSpec *)globalStyle:(NSString *)name { return _globalStyles[name]; }
- (NSArray<TPStyleSpec *> *)stylesForLexerType:(NSString *)langId { return _lexerStyles[langId] ?: @[]; }

- (TPLanguage *)languageForFileName:(NSString *)fileName {
    // upstream Buffer::setFileName: User Defined Languages are checked first
    TPUserLang *udl = [[TPUserLanguages shared] languageForFileName:fileName];
    if (udl) return [[TPUserLanguages shared] languageDescriptorForId:udl.langId];
    NSString *lower = fileName.lowercaseString;
    // Name-based rules (upstream: FileManager / Notepad_plus::getLangFromExt special cases)
    if ([lower isEqualToString:@"makefile"] || [lower isEqualToString:@"gnumakefile"]) return _byId[@"makefile"];
    if ([lower isEqualToString:@"cmakelists.txt"]) return _byId[@"cmake"];
    NSString *ext = lower.pathExtension;
    if (ext.length && _byUserExt[ext]) return _byUserExt[ext];   // Style Configurator "User ext."
    if (ext.length) {
        TPLanguage *l = _byExt[ext];
        if (l) return l;
    } else if (_byExt[lower]) {
        return _byExt[lower];
    }
    return _byId[@"normal"];
}

// ---------------------------------------------------------------- applying
static TPStyleSpec *g_globalOverride;   // "Global override" style of the loaded theme

static void setStyle(ScintillaView *v, TPStyleSpec *s, BOOL isDefault) {
    s = applyGlobalOverride(s, g_globalOverride);
    int sid = s.styleID;
    if (s.fg >= 0 && (s.colorStyle & 1)) SCI(v, SCI_STYLESETFORE, sid, rgbToSci(s.fg));
    if (s.bg >= 0 && (s.colorStyle & 2)) SCI(v, SCI_STYLESETBACK, sid, rgbToSci(s.bg));
    if (s.fontName.length) SCIS(v, SCI_STYLESETFONT, sid, s.fontName.UTF8String);
    if (s.fontStyle >= 0) {
        SCI(v, SCI_STYLESETBOLD, sid, (s.fontStyle & 1) ? 1 : 0);
        SCI(v, SCI_STYLESETITALIC, sid, (s.fontStyle & 2) ? 1 : 0);
        SCI(v, SCI_STYLESETUNDERLINE, sid, (s.fontStyle & 4) ? 1 : 0);
    }
    if (s.fontSize > 0) {
        double mac = [TPLanguageService macPointsFromWindowsPoints:s.fontSize];
        SCI(v, SCI_STYLESETSIZEFRACTIONAL, sid, static_cast<sptr_t>(mac * SC_FONT_SIZE_MULTIPLIER + 0.5));
    }
    (void)isDefault;
}

// langs.model.xml keywords + the theme's user-defined keywords of the same class (upstream getCompleteKeywordList)
- (NSDictionary<NSString *, NSString *> *)completeKeywordsOf:(TPLanguage *)lang {
    NSMutableDictionary *kw = [lang.keywords mutableCopy] ?: [NSMutableDictionary dictionary];
    for (TPStyleSpec *st in _lexerTypeByName[lang.langId].styles) {
        if (!st.keywordClass.length || !st.userKeywords.length) continue;
        NSString *base = kw[st.keywordClass] ?: @"";
        kw[st.keywordClass] = base.length ? [base stringByAppendingFormat:@" %@", st.userKeywords] : st.userKeywords;
    }
    return kw;
}

- (void)setKeywordsForLanguage:(TPLanguage *)lang view:(ScintillaView *)v {
    NSString *lex = lang.lexerName;
    NSDictionary *kw = [self completeKeywordsOf:lang];
    auto set = [&](int idx, NSString *words) {
        SCIS(v, SCI_SETKEYWORDS, static_cast<uptr_t>(idx), (words ?: @"").UTF8String);
    };
    if ([lex isEqualToString:@"cpp"] || [lex isEqualToString:@"objc"]) {
        // upstream setCppLexer / setObjCLexer: 0 instre1, 1 type1, 2 type2 (doxygen), 3 instre2 (global classes)
        set(0, kw[@"instre1"]); set(1, kw[@"type1"]); set(2, kw[@"type2"]); set(3, kw[@"instre2"]);
    } else if ([lex isEqualToString:@"hypertext"] || [lex isEqualToString:@"phpscript"]) {
        // upstream setHTMLLexer/setPhpEmbeddedLexer: html, embedded JS, VBScript, Python, PHP
        TPLanguage *html = _byId[@"html"], *js = _byId[@"javascript"], *vb = _byId[@"vb"], *py = _byId[@"python"], *php = _byId[@"php"];
        set(0, [self completeKeywordsOf:html][@"instre1"]); set(1, [self completeKeywordsOf:js][@"instre1"]); set(2, [self completeKeywordsOf:vb][@"instre1"]);
        set(3, [self completeKeywordsOf:py][@"instre1"]); set(4, [self completeKeywordsOf:php][@"instre1"]);
    } else {
        // upstream setLexer(..., LIST_0..LIST_8): set n <- LANG_INDEX n
        NSArray *order = @[@"instre1", @"instre2", @"type1", @"type2", @"type3", @"type4", @"type5", @"type6", @"type7"];
        for (NSUInteger i = 0; i < order.count; ++i) if (kw[order[i]]) set(static_cast<int>(i), kw[order[i]]);
    }
}

- (void)setLexerPropertiesForLanguage:(TPLanguage *)lang view:(ScintillaView *)v {
    auto prop = [&](const char *k, const char *val) { SCI(v, SCI_SETPROPERTY, reinterpret_cast<uptr_t>(k), reinterpret_cast<sptr_t>(val)); };
    prop("fold", "1");
    prop("fold.compact", "0");
    prop("fold.comment", "1");
    prop("fold.preprocessor", "1");
    prop("fold.html", "1");
    prop("fold.hypertext.comment", "1");
    prop("fold.flags", "16");
    prop("fold.quotes.python", "1");
    prop("lexer.cpp.track.preprocessor", "0");
    prop("lexer.cpp.allow.dollars", "1");
    NSString *lid = lang.langId;
    if ([lid isEqualToString:@"javascript.js"] || [lid isEqualToString:@"typescript"] || [lid isEqualToString:@"go"] ||
        [lid isEqualToString:@"javascript"])
        prop("lexer.cpp.backquoted.strings", "1");
    if ([lid isEqualToString:@"xml"]) prop("lexer.xml.allow.scripts", "0");
    if ([lid isEqualToString:@"html"]) prop("html.tags.case.sensitive", "0");
    if ([lid isEqualToString:@"json5"]) prop("lexer.json.allow.comments", "1");
    if ([lid isEqualToString:@"sql"] || [lid isEqualToString:@"mssql"]) prop("sql.backslash.escapes", [TPPrefs b:@"pref.sqlBackslash"] ? "1" : "0");
}

// Preferences > Delimiter > word character list. Note: SCI_SETWORDCHARS(NULL) does NOT restore the
// defaults (it clears the word class); SCI_SETCHARSDEFAULT does.
- (void)applyWordCharsToView:(ScintillaView *)v {
    SCI(v, SCI_SETCHARSDEFAULT);
    if (![TPPrefs b:@"pref.wordCharsDefault"] && [TPPrefs s:@"pref.wordCharsCustom"].length) {
        std::string chars = "_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        for (int c = 0x80; c < 0x100; ++c) chars.push_back(static_cast<char>(c));
        chars += StdStr([TPPrefs s:@"pref.wordCharsCustom"]);
        SCIS(v, SCI_SETWORDCHARS, 0, chars.c_str());
    }
}

- (void)applyIndentationOfDocument:(TPDocument *)doc toView:(ScintillaView *)v {
    SCI(v, SCI_SETTABWIDTH, [TPPrefs tabSizeForLanguage:doc.languageId]);
    SCI(v, SCI_SETUSETABS, [TPPrefs useSpacesForLanguage:doc.languageId] ? 0 : 1);
    SCI(v, SCI_SETINDENT, 0);
}

- (void)applyLanguageOfDocument:(TPDocument *)doc toView:(ScintillaView *)v {
    [self applyIndentationOfDocument:doc toView:v];
    [self applyWordCharsToView:v];
    TPUserLang *udl = [[TPUserLanguages shared] languageForId:doc.languageId];
    if (udl) {
        BOOL setLexer = ![doc.appliedLexerLanguage isEqualToString:doc.languageId];
        [self applyStylesForLanguage:[[TPUserLanguages shared] languageDescriptorForId:udl.langId] toView:v];
        [[TPUserLanguages shared] applyLanguage:udl toView:v bufferId:doc.uid setLexer:setLexer];
        doc.appliedLexerLanguage = doc.languageId;
        return;
    }
    if ([doc.languageId hasPrefix:@"udl:"]) doc.languageId = @"normal";   // the UDL was removed
    TPLanguage *lang = _byId[doc.languageId] ?: _byId[@"normal"];
    if (![doc.appliedLexerLanguage isEqualToString:lang.langId]) {
        Scintilla::ILexer5 *lexer = nullptr;
        if (![lang.lexerName isEqualToString:@"null"]) lexer = CreateLexer(lang.lexerName.UTF8String);
        SCI(v, SCI_SETILEXER, 0, reinterpret_cast<sptr_t>(lexer));
        if (lexer) {
            [self setLexerPropertiesForLanguage:lang view:v];
            [self setKeywordsForLanguage:lang view:v];
        }
        doc.appliedLexerLanguage = lang.langId;
    }
    [self applyStylesForLanguage:lang toView:v];
    SCI(v, SCI_COLOURISE, 0, -1);
}

- (void)applyStylesForLanguage:(TPLanguage *)lang toView:(ScintillaView *)v {
    g_globalOverride = _globalStyles[@"Global override"];
    TPStyleSpec *def = _globalStyles[@"Default Style"];
    if (def) def = applyGlobalOverride(def, g_globalOverride);
    SCI(v, SCI_STYLERESETDEFAULT);
    SCIS(v, SCI_STYLESETFONT, STYLE_DEFAULT, (def.fontName ?: @"Courier New").UTF8String);
    double size = [TPLanguageService macPointsFromWindowsPoints:(def.fontSize > 0 ? def.fontSize : 10)];
    SCI(v, SCI_STYLESETSIZEFRACTIONAL, STYLE_DEFAULT, static_cast<sptr_t>(size * SC_FONT_SIZE_MULTIPLIER + 0.5));
    SCI(v, SCI_STYLESETFORE, STYLE_DEFAULT, rgbToSci(def && def.fg >= 0 ? def.fg : 0x000000));
    SCI(v, SCI_STYLESETBACK, STYLE_DEFAULT, rgbToSci(def && def.bg >= 0 ? def.bg : 0xFFFFFF));
    if (def.fontStyle >= 0) {
        SCI(v, SCI_STYLESETBOLD, STYLE_DEFAULT, (def.fontStyle & 1) ? 1 : 0);
        SCI(v, SCI_STYLESETITALIC, STYLE_DEFAULT, (def.fontStyle & 2) ? 1 : 0);
        SCI(v, SCI_STYLESETUNDERLINE, STYLE_DEFAULT, (def.fontStyle & 4) ? 1 : 0);
    }
    SCI(v, SCI_STYLECLEARALL);

    for (NSString *n in @[@"Line number margin", @"Brace highlight style", @"Bad brace colour", @"Indent guideline style"]) {
        TPStyleSpec *s = _globalStyles[n];
        if (s && s.styleID > 0) setStyle(v, s, NO);
    }

    NSMutableArray<NSString *> *types = [NSMutableArray arrayWithObject:lang.langId];
    if ([lang.lexerName isEqualToString:@"hypertext"] || [lang.lexerName isEqualToString:@"phpscript"]) {
        types = [NSMutableArray arrayWithObjects:@"html", @"javascript", @"php", nil];
        if ([lang.langId isEqualToString:@"asp"]) [types addObject:@"asp"];
    }
    for (NSString *t in types)
        for (TPStyleSpec *s in _lexerStyles[t]) setStyle(v, s, NO);

    auto col = [&](NSString *n, BOOL fg) -> int {
        TPStyleSpec *s = _globalStyles[n];
        int c = s ? (fg ? s.fg : s.bg) : -1;
        return c;
    };
    auto elem = [&](int element, int rgb) {
        if (rgb >= 0) SCI(v, SCI_SETELEMENTCOLOUR, static_cast<uptr_t>(element), static_cast<sptr_t>(rgbToSci(rgb) | 0xFF000000u));
    };
    elem(SC_ELEMENT_CARET, col(@"Caret colour", YES));
    elem(SC_ELEMENT_CARET_ADDITIONAL, col(@"Multi-edit carets color", YES));
    elem(SC_ELEMENT_SELECTION_BACK, col(@"Selected text colour", NO));
    elem(SC_ELEMENT_SELECTION_ADDITIONAL_BACK, col(@"Multi-selected text color", NO));
    elem(SC_ELEMENT_SELECTION_SECONDARY_BACK, col(@"Selected text colour", NO));
    elem(SC_ELEMENT_SELECTION_INACTIVE_BACK, col(@"Selected text colour", NO));
    if ([TPPrefs i:@"pref.currentLineMode"] != 0) elem(SC_ELEMENT_CARET_LINE_BACK, col(@"Current line background colour", NO));
    else SCI(v, SCI_SETCARETLINEVISIBLE, 0);   // Preferences > Editing 1 > Current Line Indicator: None
    elem(SC_ELEMENT_WHITE_SPACE, col(@"White space symbol", YES));
    int edge = col(@"Edge colour", YES);
    if (edge >= 0) SCI(v, SCI_SETEDGECOLOUR, rgbToSci(edge));
    int fmBg = col(@"Fold margin", NO), fmFg = col(@"Fold margin", YES);
    if (fmBg >= 0) SCI(v, SCI_SETFOLDMARGINCOLOUR, 1, rgbToSci(fmBg));
    if (fmFg >= 0) SCI(v, SCI_SETFOLDMARGINHICOLOUR, 1, rgbToSci(fmFg));
    int foldFg = col(@"Fold", YES), foldBg = col(@"Fold", NO), foldActive = col(@"Fold active", YES);
    for (int m = SC_MARKNUM_FOLDEREND; m <= SC_MARKNUM_FOLDEROPEN; ++m) {
        if (foldBg >= 0) SCI(v, SCI_MARKERSETFORE, m, rgbToSci(foldBg));
        if (foldFg >= 0) SCI(v, SCI_MARKERSETBACK, m, rgbToSci(foldFg));
        if (foldActive >= 0) SCI(v, SCI_MARKERSETBACKSELECTED, m, rgbToSci(foldActive));
    }
    int bmBg = col(@"Bookmark margin", NO);
    if (bmBg >= 0) SCI(v, SCI_SETMARGINBACKN, TPP_MARGIN_SYMBOL, rgbToSci(bmBg));
    int chBg = col(@"Change History margin", NO);
    if (chBg >= 0) SCI(v, SCI_SETMARGINBACKN, TPP_MARGIN_CHANGEHISTORY, rgbToSci(chBg));
    struct { NSString *n; int marker; } hist[] = {
        {@"Change History modified", SC_MARKNUM_HISTORY_MODIFIED},
        {@"Change History revert modified", SC_MARKNUM_HISTORY_REVERTED_TO_MODIFIED},
        {@"Change History revert origin", SC_MARKNUM_HISTORY_REVERTED_TO_ORIGIN},
        {@"Change History saved", SC_MARKNUM_HISTORY_SAVED},
    };
    for (auto &h : hist) {
        TPStyleSpec *s = _globalStyles[h.n];
        if (!s) continue;
        if (s.fg >= 0) SCI(v, SCI_MARKERSETFORE, h.marker, rgbToSci(s.fg));
        if (s.bg >= 0) SCI(v, SCI_MARKERSETBACK, h.marker, rgbToSci(s.bg));
    }
    struct { NSString *n; int indic; } inds[] = {
        {@"Find Mark Style", TPP_INDIC_FOUND}, {@"Smart Highlighting", TPP_INDIC_SMART},
        {@"Find matches highlight all", TPP_INDIC_INC}, {@"Find matches highlight all", TPP_INDIC_FINDDLG},
        {@"Tags match highlighting", TPP_INDIC_TAGMATCH}, {@"Tags attribute", TPP_INDIC_TAGATTR},
        {@"Mark Style 1", 25}, {@"Mark Style 2", 24}, {@"Mark Style 3", 23}, {@"Mark Style 4", 22}, {@"Mark Style 5", 21},
    };
    for (auto &i : inds) {
        TPStyleSpec *s = _globalStyles[i.n];
        if (s && s.bg >= 0) SCI(v, SCI_INDICSETFORE, i.indic, rgbToSci(s.bg));
    }
}

- (void)configureView:(ScintillaView *)v {
    SCI(v, SCI_SETCODEPAGE, SC_CP_UTF8);
    SCI(v, SCI_SETTECHNOLOGY, SC_TECHNOLOGY_DEFAULT);
    SCI(v, SCI_USEPOPUP, SC_POPUP_NEVER);          // Textpad++ shows its own context menu
    SCI(v, SCI_SETMOUSEDWELLTIME, 500);
    SCI(v, SCI_SETSCROLLWIDTHTRACKING, 1);
    SCI(v, SCI_SETSCROLLWIDTH, 1);
    SCI(v, SCI_SETMULTIPLESELECTION, 1);            // upstream default: multi-editing enabled
    SCI(v, SCI_SETADDITIONALSELECTIONTYPING, 1);
    SCI(v, SCI_SETMULTIPASTE, SC_MULTIPASTE_EACH);
    SCI(v, SCI_SETVIRTUALSPACEOPTIONS, SCVS_RECTANGULARSELECTION);
    SCI(v, SCI_SETMOUSESELECTIONRECTANGULARSWITCH, 1);
    SCI(v, SCI_SETCARETLINEVISIBLE, 1);
    SCI(v, SCI_SETCARETLINEVISIBLEALWAYS, 1);
    SCI(v, SCI_SETCARETWIDTH, 1);
    SCI(v, SCI_SETCARETPERIOD, 500);
    SCI(v, SCI_SETTABWIDTH, MAX(1, [TPPrefs i:@"TabWidth"]));
    SCI(v, SCI_SETUSETABS, [TPPrefs b:@"UseSpaces"] ? 0 : 1);
    SCI(v, SCI_SETINDENTATIONGUIDES, SC_IV_LOOKBOTH);
    SCI(v, SCI_SETWRAPVISUALFLAGS, SC_WRAPVISUALFLAG_NONE);
    SCI(v, SCI_SETEDGEMODE, EDGE_NONE);
    SCI(v, SCI_SETENDATLASTLINE, 1);
    SCI(v, SCI_SETCHANGEHISTORY, SC_CHANGE_HISTORY_ENABLED | SC_CHANGE_HISTORY_MARKERS);

    // Margins (upstream: 0 line numbers, 1 symbols/bookmarks, 2 folder, 3 change history; Textpad++: 4 Git)
    SCI(v, SCI_SETMARGINS, 5);   // + 4: Git change markers (View > Git Change Markers), sized when a file has changes
    SCI(v, SCI_SETMARGINTYPEN, 4, SC_MARGIN_SYMBOL);
    SCI(v, SCI_SETMARGINMASKN, 4, (1 << 13) | (1 << 14) | (1 << 15));
    SCI(v, SCI_SETMARGINTYPEN, TPP_MARGIN_LINENUMBER, SC_MARGIN_NUMBER);
    SCI(v, SCI_SETMARGINTYPEN, TPP_MARGIN_SYMBOL, SC_MARGIN_COLOUR);
    SCI(v, SCI_SETMARGINMASKN, TPP_MARGIN_SYMBOL, (1 << TPP_MARK_BOOKMARK) | (1 << TPP_MARK_HIDELINESBEGIN) | (1 << TPP_MARK_HIDELINESEND));
    SCI(v, SCI_SETMARGINWIDTHN, TPP_MARGIN_SYMBOL, 16);
    SCI(v, SCI_SETMARGINSENSITIVEN, TPP_MARGIN_SYMBOL, 1);
    SCI(v, SCI_SETMARGINTYPEN, TPP_MARGIN_FOLDER, SC_MARGIN_SYMBOL);
    SCI(v, SCI_SETMARGINMASKN, TPP_MARGIN_FOLDER, SC_MASK_FOLDERS);
    SCI(v, SCI_SETMARGINWIDTHN, TPP_MARGIN_FOLDER, 14);
    SCI(v, SCI_SETMARGINSENSITIVEN, TPP_MARGIN_FOLDER, 1);
    SCI(v, SCI_SETMARGINTYPEN, TPP_MARGIN_CHANGEHISTORY, SC_MARGIN_COLOUR);
    SCI(v, SCI_SETMARGINMASKN, TPP_MARGIN_CHANGEHISTORY, SC_MASK_HISTORY);
    SCI(v, SCI_SETMARGINWIDTHN, TPP_MARGIN_CHANGEHISTORY, 9);
    SCI(v, SCI_SETMARGINMASKN, TPP_MARGIN_LINENUMBER, 0);

    // Box-tree fold markers (upstream default folder style "box tree")
    SCI(v, SCI_MARKERDEFINE, SC_MARKNUM_FOLDEROPEN, SC_MARK_BOXMINUS);
    SCI(v, SCI_MARKERDEFINE, SC_MARKNUM_FOLDER, SC_MARK_BOXPLUS);
    SCI(v, SCI_MARKERDEFINE, SC_MARKNUM_FOLDERSUB, SC_MARK_VLINE);
    SCI(v, SCI_MARKERDEFINE, SC_MARKNUM_FOLDERTAIL, SC_MARK_LCORNER);
    SCI(v, SCI_MARKERDEFINE, SC_MARKNUM_FOLDEREND, SC_MARK_BOXPLUSCONNECTED);
    SCI(v, SCI_MARKERDEFINE, SC_MARKNUM_FOLDEROPENMID, SC_MARK_BOXMINUSCONNECTED);
    SCI(v, SCI_MARKERDEFINE, SC_MARKNUM_FOLDERMIDTAIL, SC_MARK_TCORNER);
    SCI(v, SCI_MARKERENABLEHIGHLIGHT, 1);
    SCI(v, SCI_SETAUTOMATICFOLD, SC_AUTOMATICFOLD_SHOW | SC_AUTOMATICFOLD_CLICK | SC_AUTOMATICFOLD_CHANGE);
    SCI(v, SCI_SETFOLDFLAGS, SC_FOLDFLAG_LINEAFTER_CONTRACTED);

    // Bookmark marker (upstream uses an RGBA image; Textpad++ uses Scintilla's bookmark shape in the same blue)
    SCI(v, SCI_MARKERDEFINE, TPP_MARK_BOOKMARK, SC_MARK_BOOKMARK);
    SCI(v, SCI_MARKERSETFORE, TPP_MARK_BOOKMARK, rgbToSci(0x1E60D0));
    SCI(v, SCI_MARKERSETBACK, TPP_MARK_BOOKMARK, rgbToSci(0x3C8CF0));
    SCI(v, SCI_MARKERDEFINE, TPP_MARK_HIDELINESBEGIN, SC_MARK_ARROW);
    SCI(v, SCI_MARKERDEFINE, TPP_MARK_HIDELINESEND, SC_MARK_ARROWDOWN);

    // Change-history markers
    SCI(v, SCI_MARKERDEFINE, SC_MARKNUM_HISTORY_MODIFIED, SC_MARK_FULLRECT);
    SCI(v, SCI_MARKERDEFINE, SC_MARKNUM_HISTORY_SAVED, SC_MARK_FULLRECT);
    SCI(v, SCI_MARKERDEFINE, SC_MARKNUM_HISTORY_REVERTED_TO_ORIGIN, SC_MARK_FULLRECT);
    SCI(v, SCI_MARKERDEFINE, SC_MARKNUM_HISTORY_REVERTED_TO_MODIFIED, SC_MARK_FULLRECT);

    // Highlight indicators (upstream: INDIC_ROUNDBOX, alpha 100, under text)
    const int indicators[] = {TPP_INDIC_FOUND, TPP_INDIC_SMART, TPP_INDIC_INC, TPP_INDIC_FINDDLG, TPP_INDIC_TAGMATCH, TPP_INDIC_TAGATTR, 25, 24, 23, 22, 21};
    for (int i : indicators) {
        SCI(v, SCI_INDICSETSTYLE, i, INDIC_ROUNDBOX);
        SCI(v, SCI_INDICSETALPHA, i, 100);
        SCI(v, SCI_INDICSETOUTLINEALPHA, i, 150);
        SCI(v, SCI_INDICSETUNDER, i, 1);
    }
    SCI(v, SCI_INDICSETSTYLE, TPP_INDIC_SMART, INDIC_ROUNDBOX);
    SCI(v, SCI_INDICSETALPHA, TPP_INDIC_SMART, 100);
}

@end
