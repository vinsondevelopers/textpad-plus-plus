// Textpad++ — User Defined Languages. GPL-3.0-or-later.
// Ported from Notepad++ (C) Don Ho and contributors: Parameters.cpp feedUserSettings /
// feedUserKeywordList / feedUserStyles / insertUserLang2Tree, ScintillaEditView::setUserLexer.
#import "app/UserDefinedLanguages.h"
#import "app/LanguageService.h"
#import "app/Session.h"
#import "app/MainWindowController.h"
#import "app/Preferences.h"

NSNotificationName const TPUserLanguagesChangedNotification = @"TPUserLanguagesChangedNotification";

// Keyword list names written by upstream (keywordNameMapper), index == SCE_USER_KWLIST_*
static NSArray<NSString *> *kwListNames() {
    return @[@"Comments", @"Numbers, prefix1", @"Numbers, prefix2", @"Numbers, extras1", @"Numbers, extras2",
             @"Numbers, suffix1", @"Numbers, suffix2", @"Numbers, range", @"Operators1", @"Operators2",
             @"Folders in code1, open", @"Folders in code1, middle", @"Folders in code1, close",
             @"Folders in code2, open", @"Folders in code2, middle", @"Folders in code2, close",
             @"Folders in comment, open", @"Folders in comment, middle", @"Folders in comment, close",
             @"Keywords1", @"Keywords2", @"Keywords3", @"Keywords4", @"Keywords5", @"Keywords6", @"Keywords7", @"Keywords8",
             @"Delimiters"];
}

// Accepted on read (keywordIdMapper incl. pre-2.0 names)
static NSDictionary<NSString *, NSNumber *> *kwListIds() {
    static NSDictionary *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        NSArray *n = kwListNames();
        for (NSUInteger i = 0; i < n.count; ++i) m[n[i]] = @(i);
        [m addEntriesFromDictionary:@{@"Operators": @8, @"Folder+": @10, @"Folder-": @12, @"Words1": @19, @"Words2": @20,
                                      @"Words3": @21, @"Words4": @22, @"Numbers, additional": @7, @"Numbers, prefixes": @2,
                                      @"Numbers, extras with prefixes": @4, @"Numbers, suffixes": @6}];
        d = m;
    });
    return d;
}

// Style names written by upstream (styleNameMapper), index == SCE_USER_STYLE_* (0..23)
static NSArray<NSString *> *styleNames() {
    return @[@"DEFAULT", @"COMMENTS", @"LINE COMMENTS", @"NUMBERS", @"KEYWORDS1", @"KEYWORDS2", @"KEYWORDS3", @"KEYWORDS4",
             @"KEYWORDS5", @"KEYWORDS6", @"KEYWORDS7", @"KEYWORDS8", @"OPERATORS", @"FOLDER IN CODE1", @"FOLDER IN CODE2",
             @"FOLDER IN COMMENT", @"DELIMITERS1", @"DELIMITERS2", @"DELIMITERS3", @"DELIMITERS4", @"DELIMITERS5",
             @"DELIMITERS6", @"DELIMITERS7", @"DELIMITERS8"];
}

static NSDictionary<NSString *, NSNumber *> *styleIds() {
    static NSDictionary *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        NSArray *n = styleNames();
        for (NSUInteger i = 0; i < n.count; ++i) m[n[i]] = @(i);
        [m addEntriesFromDictionary:@{@"FOLDEROPEN": @13, @"FOLDERCLOSE": @13, @"KEYWORD1": @4, @"KEYWORD2": @5, @"KEYWORD3": @6,
                                      @"KEYWORD4": @7, @"COMMENT": @1, @"COMMENT LINE": @2, @"NUMBER": @3, @"OPERATOR": @12,
                                      @"DELIMINER1": @16, @"DELIMINER2": @17, @"DELIMINER3": @18}];
        d = m;
    });
    return d;
}

static TPStyleSpec *defaultStyle(int sid) {
    TPStyleSpec *s = [TPStyleSpec new];
    s.name = sid < (int)styleNames().count ? styleNames()[sid] : @"IDENTIFIER";
    s.styleID = sid;
    s.fg = 0x000000; s.bg = 0xFFFFFF;
    s.fontStyle = 0; s.fontSize = 0;
    s.colorStyle = sid == 0 ? 0 : 1;   // upstream new-UDL defaults: transparent default, foreground elsewhere
    s.nesting = 0;
    return s;
}

@implementation TPUserLang

- (instancetype)initWithName:(NSString *)name {
    if ((self = [super init])) {
        _name = [name copy];
        _ext = @"";
        _udlVersion = @"2.1";
        _keywordLists = [NSMutableArray array];
        for (int i = 0; i < TPUDLKeywordListCount; ++i) [_keywordLists addObject:@""];
        _keywordLists[0] = @"00 01 02 03 04";
        NSMutableString *delims = [NSMutableString string];
        for (int i = 0; i < 24; ++i) [delims appendFormat:@"%s%02d", i ? " " : "", i];
        _keywordLists[27] = delims;
        _isPrefix = [NSMutableArray array];
        for (int i = 0; i < 8; ++i) [_isPrefix addObject:@NO];
        _styles = [NSMutableArray array];
        for (int i = 0; i < 24; ++i) [_styles addObject:defaultStyle(i)];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    TPUserLang *c = [[TPUserLang alloc] initWithName:_name];
    c.ext = _ext; c.udlVersion = _udlVersion;
    c.caseIgnored = _caseIgnored; c.allowFoldOfComments = _allowFoldOfComments; c.foldCompact = _foldCompact;
    c.forcePureLC = _forcePureLC; c.decimalSeparator = _decimalSeparator;
    c.keywordLists = [_keywordLists mutableCopy];
    c.isPrefix = [_isPrefix mutableCopy];
    NSMutableArray *st = [NSMutableArray array];
    for (TPStyleSpec *s in _styles) {
        TPStyleSpec *n = [TPStyleSpec new];
        n.name = s.name; n.styleID = s.styleID; n.fg = s.fg; n.bg = s.bg; n.fontName = s.fontName; n.fontStyle = s.fontStyle;
        n.fontSize = s.fontSize; n.colorStyle = s.colorStyle; n.nesting = s.nesting;
        [st addObject:n];
    }
    c.styles = st;
    return c;
}

- (NSString *)langId { return [@"udl:" stringByAppendingString:_name]; }

- (NSUInteger)numericId {
    NSUInteger h = 5381;
    for (NSUInteger i = 0; i < _name.length; ++i) h = ((h << 5) + h) + [_name characterAtIndex:i];
    return (h & 0x3FFFFFFF) + 1;   // positive int for GetPropertyInt
}

// "00a 00b 01 02c" -> code 0 => "a b"
- (NSString *)field:(int)code ofList:(int)list {
    NSMutableArray *vals = [NSMutableArray array];
    for (NSString *tok in [_keywordLists[list] componentsSeparatedByString:@" "]) {
        if (tok.length < 2) continue;
        int c = [[tok substringToIndex:2] intValue];
        if (c == code && tok.length > 2) [vals addObject:[tok substringFromIndex:2]];
    }
    return [vals componentsJoinedByString:@" "];
}

- (void)setField:(int)code ofList:(int)list value:(NSString *)value {
    int count = list == 0 ? 5 : 24;
    NSMutableArray *out = [NSMutableArray array];
    for (int c = 0; c < count; ++c) {
        NSString *v = c == code ? value : [self field:c ofList:list];
        NSArray *parts = [v componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        BOOL any = NO;
        for (NSString *p in parts) if (p.length) { [out addObject:[NSString stringWithFormat:@"%02d%@", c, p]]; any = YES; }
        if (!any) [out addObject:[NSString stringWithFormat:@"%02d", c]];
    }
    _keywordLists[list] = [out componentsJoinedByString:@" "];
}

- (NSXMLElement *)xmlElement {
    auto yn = [](BOOL b) { return b ? @"yes" : @"no"; };
    NSXMLElement *ul = [NSXMLElement elementWithName:@"UserLang"];
    [ul addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:_name]];
    [ul addAttribute:[NSXMLNode attributeWithName:@"ext" stringValue:_ext ?: @""]];
    [ul addAttribute:[NSXMLNode attributeWithName:@"udlVersion" stringValue:@"2.1"]];
    NSXMLElement *settings = [NSXMLElement elementWithName:@"Settings"];
    NSXMLElement *global = [NSXMLElement elementWithName:@"Global"];
    for (NSArray *kv in @[@[@"caseIgnored", yn(_caseIgnored)], @[@"allowFoldOfComments", yn(_allowFoldOfComments)], @[@"foldCompact", yn(_foldCompact)],
                          @[@"forcePureLC", [@(_forcePureLC) stringValue]], @[@"decimalSeparator", [@(_decimalSeparator) stringValue]]])
        [global addAttribute:[NSXMLNode attributeWithName:kv[0] stringValue:kv[1]]];
    [settings addChild:global];
    NSXMLElement *prefix = [NSXMLElement elementWithName:@"Prefix"];
    for (int i = 0; i < 8; ++i) [prefix addAttribute:[NSXMLNode attributeWithName:[NSString stringWithFormat:@"Keywords%d", i + 1] stringValue:yn([_isPrefix[i] boolValue])]];
    [settings addChild:prefix];
    [ul addChild:settings];
    NSXMLElement *kls = [NSXMLElement elementWithName:@"KeywordLists"];
    NSArray *names = kwListNames();
    for (int i = 0; i < TPUDLKeywordListCount; ++i) {
        NSXMLElement *k = [NSXMLElement elementWithName:@"Keywords" stringValue:_keywordLists[i]];
        [k addAttribute:[NSXMLNode attributeWithName:@"name" stringValue:names[i]]];
        [kls addChild:k];
    }
    [ul addChild:kls];
    NSXMLElement *styles = [NSXMLElement elementWithName:@"Styles"];
    auto hex = [](int c) { return c < 0 ? @"" : [NSString stringWithFormat:@"%06X", c]; };
    for (TPStyleSpec *s in _styles) {
        if (s.styleID >= 24) continue;
        NSXMLElement *w = [NSXMLElement elementWithName:@"WordsStyle"];
        for (NSArray *kv in @[@[@"name", styleNames()[s.styleID]], @[@"fgColor", hex(s.fg)], @[@"bgColor", hex(s.bg)],
                              @[@"colorStyle", [@(s.colorStyle) stringValue]], @[@"fontName", s.fontName ?: @""],
                              @[@"fontStyle", [@(MAX(0, s.fontStyle)) stringValue]], @[@"nesting", [@(s.nesting) stringValue]]])
            [w addAttribute:[NSXMLNode attributeWithName:kv[0] stringValue:kv[1]]];
        if (s.fontSize > 0) [w addAttribute:[NSXMLNode attributeWithName:@"fontSize" stringValue:[@((int)s.fontSize) stringValue]]];
        [styles addChild:w];
    }
    [ul addChild:styles];
    return ul;
}

@end

// ---------------------------------------------------------------- collection
@implementation TPUserLanguages {
    NSMutableArray<TPUserLang *> *_langs;
}

+ (instancetype)shared {
    static TPUserLanguages *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [TPUserLanguages new]; [s reload]; });
    return s;
}

- (NSArray<TPUserLang *> *)languages { return _langs; }

- (NSString *)userFolder {
    NSString *d = [[TPSession shared].settingsDirectory stringByAppendingPathComponent:@"userDefineLangs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}

static BOOL ynAttr(NSXMLElement *e, NSString *name) {
    NSString *v = [[e attributeForName:name] stringValue];
    return [v caseInsensitiveCompare:@"yes"] == NSOrderedSame || [v isEqualToString:@"1"];
}

+ (NSArray<TPUserLang *> *)parseData:(NSData *)data source:(NSString *)path error:(NSString **)error {
    NSError *err = nil;
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:0 error:&err];
    if (!doc) { if (error) *error = err.localizedDescription ?: @"Invalid XML"; return @[]; }
    NSMutableArray *out = [NSMutableArray array];
    for (NSXMLElement *ul in [doc nodesForXPath:@"//UserLang" error:nil]) {
        NSString *name = [[ul attributeForName:@"name"] stringValue];
        if (!name.length) continue;
        TPUserLang *l = [[TPUserLang alloc] initWithName:name];
        l.ext = [[ul attributeForName:@"ext"] stringValue] ?: @"";
        NSString *ver = [[ul attributeForName:@"udlVersion"] stringValue] ?: @"";
        l.udlVersion = ver;
        l.filePath = path;
        NSXMLElement *settings = [ul elementsForName:@"Settings"].firstObject;
        NSXMLElement *global = [settings elementsForName:@"Global"].firstObject;
        if (global) {
            l.caseIgnored = ynAttr(global, @"caseIgnored");
            l.allowFoldOfComments = ynAttr(global, @"allowFoldOfComments");
            l.foldCompact = ynAttr(global, @"foldCompact");
            l.forcePureLC = [[[global attributeForName:@"forcePureLC"] stringValue] intValue];
            l.decimalSeparator = [[[global attributeForName:@"decimalSeparator"] stringValue] intValue];
        }
        NSXMLElement *prefix = [settings elementsForName:@"Prefix"].firstObject;
        if (prefix) {
            BOOL v2 = [ver isEqualToString:@"2.1"] || [ver isEqualToString:@"2.0"];
            for (int i = 0; i < (v2 ? 8 : 4); ++i)
                l.isPrefix[i] = @(ynAttr(prefix, v2 ? [NSString stringWithFormat:@"Keywords%d", i + 1] : [NSString stringWithFormat:@"words%d", i + 1]));
        }
        NSXMLElement *kls = [ul elementsForName:@"KeywordLists"].firstObject;
        for (NSXMLElement *k in [kls elementsForName:@"Keywords"]) {
            NSString *kn = [[k attributeForName:@"name"] stringValue] ?: @"";
            NSString *val = k.stringValue ?: @"";
            if (!ver.length && [kn isEqualToString:@"Delimiters"] && val.length >= 6) {
                // pre-2.0 delimiters: 6 chars (open1 open2 open3 close1 close2 close3)
                auto ch = [&](NSUInteger i) { unichar c = [val characterAtIndex:i]; return c == '0' ? @"" : [NSString stringWithCharacters:&c length:1]; };
                l.keywordLists[27] = [NSString stringWithFormat:@"00%@ 01 02%@ 03%@ 04 05%@ 06%@ 07 08%@ 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23",
                                      ch(0), ch(3), ch(1), ch(4), ch(2), ch(5)];
            } else if ([kn isEqualToString:@"Comment"]) {
                // pre-2.0 comment list: codes 0 (line), 1 (open), 2 (close) -> 00, 03, 04
                NSMutableString *t = [NSMutableString stringWithFormat:@" %@", val];
                [t replaceOccurrencesOfString:@" 0" withString:@" 00" options:0 range:NSMakeRange(0, t.length)];
                [t replaceOccurrencesOfString:@" 1" withString:@" 03" options:0 range:NSMakeRange(0, t.length)];
                [t replaceOccurrencesOfString:@" 2" withString:@" 04" options:0 range:NSMakeRange(0, t.length)];
                [t appendString:@" 01 02"];
                l.keywordLists[0] = [t stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            } else {
                NSNumber *idx = kwListIds()[kn];
                if (idx) l.keywordLists[idx.integerValue] = val.length < 30720 ? val : @"imported string too long, needs to be < max_char(30720)";
            }
        }
        NSXMLElement *styles = [ul elementsForName:@"Styles"].firstObject;
        for (NSXMLElement *w in [styles elementsForName:@"WordsStyle"]) {
            NSNumber *sid = styleIds()[[[w attributeForName:@"name"] stringValue] ?: @""];
            if (!sid) continue;
            TPStyleSpec *s = l.styles[sid.integerValue];
            NSString *fg = [[w attributeForName:@"fgColor"] stringValue], *bg = [[w attributeForName:@"bgColor"] stringValue];
            unsigned v = 0;
            if (fg.length == 6 && [[NSScanner scannerWithString:fg] scanHexInt:&v]) s.fg = (int)v;
            if (bg.length == 6 && [[NSScanner scannerWithString:bg] scanHexInt:&v]) s.bg = (int)v;
            NSString *cs = [[w attributeForName:@"colorStyle"] stringValue];
            s.colorStyle = cs ? cs.intValue : 3;
            NSString *fn = [[w attributeForName:@"fontName"] stringValue];
            s.fontName = fn.length ? fn : nil;
            NSString *fst = [[w attributeForName:@"fontStyle"] stringValue];
            s.fontStyle = fst.length ? fst.intValue : 0;
            NSString *fsz = [[w attributeForName:@"fontSize"] stringValue];
            s.fontSize = fsz.length ? fsz.doubleValue : 0;
            s.nesting = [[[w attributeForName:@"nesting"] stringValue] intValue];
        }
        [out addObject:l];
    }
    if (!out.count && error) *error = @"No <UserLang> found";
    return out;
}

- (void)reload {
    NSMutableArray *all = [NSMutableArray array];
    NSMutableSet *names = [NSMutableSet set];
    // user files first (a user copy shadows a preinstalled language of the same name)
    NSMutableArray *paths = [NSMutableArray array];
    NSString *legacy = [[TPSession shared].settingsDirectory stringByAppendingPathComponent:@"userDefineLang.xml"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:legacy]) [paths addObject:legacy];
    for (NSString *f in [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.userFolder error:nil] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)])
        if ([f.pathExtension.lowercaseString isEqualToString:@"xml"]) [paths addObject:[self.userFolder stringByAppendingPathComponent:f]];
    for (NSString *p in paths) {
        for (TPUserLang *l in [TPUserLanguages parseData:[NSData dataWithContentsOfFile:p] source:p error:nil]) {
            if ([names containsObject:l.name]) continue;
            [names addObject:l.name];
            [all addObject:l];
        }
    }
    NSString *bundled = [[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:@"data/userDefineLangs"];
    for (NSString *f in [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:bundled error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
        if (![f.pathExtension.lowercaseString isEqualToString:@"xml"]) continue;
        NSString *p = [bundled stringByAppendingPathComponent:f];
        for (TPUserLang *l in [TPUserLanguages parseData:[NSData dataWithContentsOfFile:p] source:p error:nil]) {
            if ([names containsObject:l.name]) continue;
            l.preinstalled = YES;
            [names addObject:l.name];
            [all addObject:l];
        }
    }
    _langs = all;
    [[NSNotificationCenter defaultCenter] postNotificationName:TPUserLanguagesChangedNotification object:self];
}

- (TPUserLang *)languageNamed:(NSString *)name {
    for (TPUserLang *l in _langs) if ([l.name isEqualToString:name]) return l;
    return nil;
}

- (TPUserLang *)languageForId:(NSString *)langId {
    if (![langId hasPrefix:@"udl:"]) return nil;
    return [self languageNamed:[langId substringFromIndex:4]];
}

- (TPUserLang *)languageForFileName:(NSString *)fileName {
    // upstream NppParameters::getUserDefinedLangNameFromExt: extension match, case-insensitive;
    // an entry may also be a full file name
    NSString *ext = fileName.pathExtension.lowercaseString;
    NSString *lower = fileName.lowercaseString;
    // upstream ships light and dark-mode variants of preinstalled UDLs; prefer the one matching the mode
    BOOL dark = [TPChrome dark];
    NSArray *ordered = [_langs sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(TPUserLang *a, TPUserLang *b) {
        BOOL ad = [a.name containsString:@"dark mode"], bd = [b.name containsString:@"dark mode"];
        if (ad == bd) return NSOrderedSame;
        return (ad == dark) ? NSOrderedAscending : NSOrderedDescending;
    }];
    for (TPUserLang *l in ordered) {
        for (NSString *e in [l.ext componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) {
            if (!e.length) continue;
            NSString *le = e.lowercaseString;
            if ((ext.length && [le isEqualToString:ext]) || [le isEqualToString:lower]) return l;
        }
    }
    return nil;
}

- (TPLanguage *)languageDescriptorForId:(NSString *)langId {
    TPUserLang *u = [self languageForId:langId];
    if (!u) return nil;
    TPLanguage *l = [TPLanguage new];
    l.langId = u.langId;
    l.shortName = u.name;
    l.longName = [@"User Defined language file - " stringByAppendingString:u.name];
    l.lexerName = @"user";
    l.menuCommand = 0;
    l.extensions = [u.ext componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSString *lineC = [[u field:0 ofList:0] componentsSeparatedByString:@" "].firstObject;
    NSString *open = [[u field:3 ofList:0] componentsSeparatedByString:@" "].firstObject;
    NSString *close = [[u field:4 ofList:0] componentsSeparatedByString:@" "].firstObject;
    l.commentLine = lineC.length ? lineC : nil;
    l.commentStart = open.length ? open : nil;
    l.commentEnd = close.length ? close : nil;
    NSMutableDictionary *kw = [NSMutableDictionary dictionary];
    for (int i = 0; i < 8; ++i) kw[[NSString stringWithFormat:@"instre%d", i + 1]] = u.keywordLists[19 + i];
    l.keywords = kw;
    return l;
}

- (NSString *)pathForUserCopy:(TPUserLang *)l {
    NSString *safe = [[l.name componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/:\\"]] componentsJoinedByString:@"_"];
    return [self.userFolder stringByAppendingPathComponent:[safe stringByAppendingString:@".xml"]];
}

- (BOOL)writeLanguage:(TPUserLang *)l toPath:(NSString *)path error:(NSString **)error {
    NSXMLElement *root = [NSXMLElement elementWithName:@"NotepadPlus"];
    [root addChild:[l xmlElement]];
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithRootElement:root];
    doc.characterEncoding = @"UTF-8";
    doc.version = @"1.0";
    NSData *d = [doc XMLDataWithOptions:NSXMLNodePrettyPrint];
    std::string bytes(static_cast<const char *>(d.bytes), d.length);
    return TPSafeWriteFile(path, bytes, error);
}

- (BOOL)save:(TPUserLang *)l error:(NSString **)error {
    NSString *path = (l.preinstalled || !l.filePath || [l.filePath.lastPathComponent isEqualToString:@"userDefineLang.xml"]) ? [self pathForUserCopy:l] : l.filePath;
    if (![self writeLanguage:l toPath:path error:error]) return NO;
    l.filePath = path;
    l.preinstalled = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:TPUserLanguagesChangedNotification object:self];
    return YES;
}

- (BOOL)remove:(TPUserLang *)l error:(NSString **)error {
    if (l.preinstalled) { if (error) *error = @"Preinstalled languages cannot be removed."; return NO; }
    if (l.filePath && ![l.filePath.lastPathComponent isEqualToString:@"userDefineLang.xml"])
        [[NSFileManager defaultManager] trashItemAtURL:[NSURL fileURLWithPath:l.filePath] resultingItemURL:nil error:nil];
    [_langs removeObjectIdenticalTo:l];
    [self reload];
    return YES;
}

- (NSArray<TPUserLang *> *)importFile:(NSString *)path error:(NSString **)error {
    NSArray *langs = [TPUserLanguages parseData:[NSData dataWithContentsOfFile:path] source:path error:error];
    for (TPUserLang *l in langs) {
        TPUserLang *existing = [self languageNamed:l.name];
        if (existing && !existing.preinstalled && existing.filePath) l.filePath = existing.filePath;
        else l.filePath = nil;
        l.preinstalled = NO;
        [self save:l error:nil];
    }
    [self reload];
    return langs;
}

- (BOOL)exportLanguage:(TPUserLang *)l toPath:(NSString *)path error:(NSString **)error {
    return [self writeLanguage:l toPath:path error:error];
}

- (TPUserLang *)createNamed:(NSString *)name basedOn:(TPUserLang *)base error:(NSString **)error {
    if (!name.length || [self languageNamed:name]) { if (error) *error = @"This name is used by another language, please give another one."; return nil; }
    TPUserLang *l = base ? [base copy] : [[TPUserLang alloc] initWithName:name];
    l.name = name;
    l.filePath = nil;
    l.preinstalled = NO;
    if (![self save:l error:error]) return nil;
    [self reload];
    return [self languageNamed:name];
}

- (BOOL)rename:(TPUserLang *)l to:(NSString *)newName error:(NSString **)error {
    if (!newName.length || [self languageNamed:newName]) { if (error) *error = @"This name is used by another language, please give another one."; return NO; }
    if (l.preinstalled) { if (error) *error = @"Preinstalled languages cannot be renamed; use Save As."; return NO; }
    NSString *old = l.filePath;
    l.name = newName;
    l.filePath = nil;
    if (![self save:l error:error]) return NO;
    if (old && ![old isEqualToString:l.filePath] && ![old.lastPathComponent isEqualToString:@"userDefineLang.xml"]) [[NSFileManager defaultManager] removeItemAtPath:old error:nil];
    [self reload];
    return YES;
}

// ---------------------------------------------------------------- applying (port of setUserLexer)
- (void)applyLanguage:(TPUserLang *)u toView:(ScintillaView *)v bufferId:(NSUInteger)bufferId setLexer:(BOOL)setLexer {
    auto prop = [&](const char *k, const char *val) { SCI(v, SCI_SETPROPERTY, reinterpret_cast<uptr_t>(k), reinterpret_cast<sptr_t>(val)); };
    if (setLexer) {
        Scintilla::ILexer5 *lexer = CreateLexer("user");
        SCI(v, SCI_SETILEXER, 0, reinterpret_cast<sptr_t>(lexer));
    }
    prop("fold", "1");
    prop("userDefine.isCaseIgnored", u.caseIgnored ? "1" : "0");
    prop("userDefine.allowFoldOfComments", u.allowFoldOfComments ? "1" : "0");
    prop("userDefine.foldCompact", u.foldCompact ? "1" : "0");
    for (int i = 0; i < 8; ++i) {
        char name[40];
        snprintf(name, sizeof(name), "userDefine.prefixKeywords%d", i + 1);
        prop(name, [u.isPrefix[i] boolValue] ? "1" : "0");
    }
    static const std::pair<int, const char *> mapped[] = {
        {0, "userDefine.comments"}, {27, "userDefine.delimiters"}, {8, "userDefine.operators1"},
        {1, "userDefine.numberPrefix1"}, {2, "userDefine.numberPrefix2"}, {3, "userDefine.numberExtras1"}, {4, "userDefine.numberExtras2"},
        {5, "userDefine.numberSuffix1"}, {6, "userDefine.numberSuffix2"}, {7, "userDefine.numberRange"},
        {10, "userDefine.foldersInCode1Open"}, {11, "userDefine.foldersInCode1Middle"}, {12, "userDefine.foldersInCode1Close"}};
    int setKeywordsCounter = 0;
    for (int i = 0; i < TPUDLKeywordListCount; ++i) {
        std::string kw = StdStr(u.keywordLists[i]);
        const char *mappedName = nullptr;
        for (auto &m : mapped) if (m.first == i) mappedName = m.second;
        if (mappedName) { prop(mappedName, kw.c_str()); continue; }
        // OPERATORS2, FOLDERS_IN_CODE2, FOLDERS_IN_COMMENT, KEYWORDS1-8: quoted phrases (upstream loop)
        std::string temp;
        bool inDouble = false, inSingle = false, nonWS = false;
        for (size_t j = 0, len = kw.size(); j < len; ++j) {
            char c = kw[j];
            if (!inSingle && c == '"') { inDouble = !inDouble; continue; }
            if (!inDouble && c == '\'') { inSingle = !inSingle; continue; }
            if (c == '\\' && j + 1 < len && (kw[j + 1] == '"' || kw[j + 1] == '\'' || kw[j + 1] == '\\')) { ++j; temp.push_back(kw[j]); continue; }
            if (inDouble || inSingle) {
                if (static_cast<unsigned char>(c) > ' ') { temp.push_back(c); nonWS = true; }
                else if (nonWS && j > 0 && kw[j - 1] != '"' && j + 1 < len && kw[j + 1] != '"' && static_cast<unsigned char>(kw[j + 1]) > ' ')
                    temp.push_back(inDouble ? '\v' : '\b');
            } else {
                temp.push_back(c);
            }
        }
        SCI(v, SCI_SETKEYWORDS, static_cast<uptr_t>(setKeywordsCounter++), reinterpret_cast<sptr_t>(temp.c_str()));
    }
    char buf[64];
    snprintf(buf, sizeof(buf), "%d", u.forcePureLC); prop("userDefine.forcePureLC", buf);
    snprintf(buf, sizeof(buf), "%d", u.decimalSeparator); prop("userDefine.decimalSeparator", buf);
    snprintf(buf, sizeof(buf), "%lu", (unsigned long)u.numericId); prop("userDefine.udlName", buf);
    snprintf(buf, sizeof(buf), "%lu", (unsigned long)(bufferId & 0x3FFFFFFF)); prop("userDefine.currentBufferID", buf);
    for (TPStyleSpec *s in u.styles) {
        char nest[40];
        snprintf(nest, sizeof(nest), "userDefine.nesting.%02d", s.styleID);
        snprintf(buf, sizeof(buf), "%d", s.nesting);
        prop(nest, buf);
    }
    // styles (upstream setSpecialStyle with colorStyle semantics)
    for (TPStyleSpec *s in u.styles) {
        int sid = s.styleID;
        if (s.colorStyle & 1) SCI(v, SCI_STYLESETFORE, sid, rgbToSci(s.fg));
        if (s.colorStyle & 2) SCI(v, SCI_STYLESETBACK, sid, rgbToSci(s.bg));
        if (s.fontName.length) SCIS(v, SCI_STYLESETFONT, sid, s.fontName.UTF8String);
        if (s.fontStyle >= 0) {
            SCI(v, SCI_STYLESETBOLD, sid, (s.fontStyle & 1) != 0);
            SCI(v, SCI_STYLESETITALIC, sid, (s.fontStyle & 2) != 0);
            SCI(v, SCI_STYLESETUNDERLINE, sid, (s.fontStyle & 4) != 0);
        }
        if (s.fontSize > 0)
            SCI(v, SCI_STYLESETSIZEFRACTIONAL, sid, static_cast<sptr_t>([TPLanguageService macPointsFromWindowsPoints:s.fontSize] * SC_FONT_SIZE_MULTIPLIER + 0.5));
    }
    SCI(v, SCI_COLOURISE, 0, -1);
}

@end
