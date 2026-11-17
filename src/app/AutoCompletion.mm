// Textpad++ — port of Notepad++ v8.9.9.1 AutoCompletion.cpp (API/word/path completion) and
// FunctionCallTip.cpp (function parameter hints). GPL-3.0-or-later.
#import "app/AutoCompletion.h"
#import "app/Sci.h"
#import "app/Preferences.h"
#import "app/Session.h"
#import <objc/runtime.h>

#include <algorithm>
#include <map>
#include <memory>
#include <unordered_set>
#include <vector>

#include "generated/NppAutoCompleteXpm.inc"

namespace {

struct Overload {
    std::string retVal, descr;
    std::vector<std::string> params;
};
struct ApiKeyword {
    std::string name;
    bool func = false;
    std::vector<Overload> overloads;
};

// One parsed autoCompletion/<name>.xml (shared by all views; upstream re-parses per view, the result is the same).
struct ApiDatabase {
    bool ignoreCase = true;
    char start = '(', stop = ')', param = ',', terminal = ';';
    std::string additionalWordChar;
    std::vector<ApiKeyword> keywords;          // file order (upstream searches the XML in file order)
    std::vector<std::string> keyWordArray;     // "name\x1E<imageId>", sorted
    std::string keyWords;                      // keyWordArray joined by ' ' (trailing space, as upstream)
    size_t keyWordMaxLen = 0;
};

bool lessNoCase(const std::string &a, const std::string &b) {
    return std::lexicographical_compare(a.begin(), a.end(), b.begin(), b.end(),
        [](unsigned char x, unsigned char y) { return std::tolower(x) < std::tolower(y); });
}

bool equalNoCase(const std::string &a, const std::string &b) {
    return a.size() == b.size() && std::equal(a.begin(), a.end(), b.begin(),
        [](unsigned char x, unsigned char y) { return std::tolower(x) == std::tolower(y); });
}

std::string attr(NSXMLElement *e, NSString *name) {
    NSString *v = [e attributeForName:name].stringValue;
    return v ? std::string(v.UTF8String) : std::string();
}
bool hasAttr(NSXMLElement *e, NSString *name) { return [e attributeForName:name] != nil; }

std::shared_ptr<ApiDatabase> loadApiFile(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nullptr;
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithData:data options:NSXMLNodePreserveWhitespace error:nil];
    NSXMLElement *root = doc.rootElement;
    if (![root.name isEqualToString:@"NotepadPlus"]) return nullptr;
    NSXMLElement *autoNode = [root elementsForName:@"AutoComplete"].firstObject;
    if (!autoNode || ![autoNode elementsForName:@"KeyWord"].count) return nullptr;
    auto db = std::make_shared<ApiDatabase>();
    if (NSXMLElement *env = [autoNode elementsForName:@"Environment"].firstObject) {
        if (attr(env, @"ignoreCase") == "no") db->ignoreCase = false;
        std::string v;
        if (!(v = attr(env, @"startFunc")).empty()) db->start = v[0];
        if (!(v = attr(env, @"stopFunc")).empty()) db->stop = v[0];
        if (!(v = attr(env, @"paramSeparator")).empty()) db->param = v[0];
        if (!(v = attr(env, @"terminal")).empty()) db->terminal = v[0];
        db->additionalWordChar = attr(env, @"additionalWordChar");
    }
    for (NSXMLElement *k in [autoNode elementsForName:@"KeyWord"]) {
        if (!hasAttr(k, @"name")) continue;
        ApiKeyword kw;
        kw.name = attr(k, @"name");
        kw.func = attr(k, @"func") == "yes";
        for (NSXMLElement *o in [k elementsForName:@"Overload"]) {
            if (!hasAttr(o, @"retVal")) continue;   // malformed node (upstream skips it)
            Overload ov;
            ov.retVal = attr(o, @"retVal");
            ov.descr = attr(o, @"descr");
            for (NSXMLElement *p in [o elementsForName:@"Param"])
                if (hasAttr(p, @"name")) ov.params.push_back(attr(p, @"name"));
            kw.overloads.push_back(std::move(ov));
        }
        if (!kw.name.empty()) {
            db->keyWordArray.push_back(kw.name + "\x1E" + std::to_string(kw.func ? FUNC_IMG_ID : BOX_IMG_ID));
            db->keyWordMaxLen = std::max(db->keyWordMaxLen, kw.name.size());
        }
        db->keywords.push_back(std::move(kw));
    }
    if (db->ignoreCase) std::stable_sort(db->keyWordArray.begin(), db->keyWordArray.end(), lessNoCase);
    else std::sort(db->keyWordArray.begin(), db->keyWordArray.end());
    for (const auto &w : db->keyWordArray) { db->keyWords += w; db->keyWords += ' '; }
    return db;
}

// Upstream getApiFileName: the langs.model.xml name, JavaScript uses "javascript", a UDL uses its own name.
NSArray<NSString *> *apiFileNames(NSString *languageId) {
    if ([languageId hasPrefix:@"udl:"]) return @[[languageId substringFromIndex:4]];
    if ([languageId isEqualToString:@"javascript.js"]) return @[@"javascript"];
    NSMutableArray *names = [NSMutableArray arrayWithObject:languageId];
    NSRange dot = [languageId rangeOfString:@"."];
    if (dot.location != NSNotFound) [names addObject:[languageId substringToIndex:dot.location]];
    return names;
}

NSString *findApiFile(NSString *languageId) {
    if (!languageId.length) return nil;
    NSArray *dirs = @[[[TPSession shared].settingsDirectory stringByAppendingPathComponent:@"autoCompletion"],
                      [[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:@"data/autoCompletion"]];
    for (NSString *name in apiFileNames(languageId))
        for (NSString *dir in dirs) {
            NSString *p = [dir stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"xml"]];
            if ([[NSFileManager defaultManager] fileExistsAtPath:p]) return p;
        }
    return nil;
}

std::shared_ptr<ApiDatabase> databaseForPath(NSString *path) {
    static NSMutableDictionary<NSString *, NSDate *> *stamps = [NSMutableDictionary dictionary];
    static std::map<std::string, std::shared_ptr<ApiDatabase>> cache;
    if (!path) return nullptr;
    NSDate *mod = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil].fileModificationDate ?: [NSDate distantPast];
    std::string key = path.UTF8String;
    auto it = cache.find(key);
    if (it != cache.end() && [stamps[path] isEqualToDate:mod]) return it->second;
    auto db = loadApiFile(path);
    cache[key] = db;
    stamps[path] = mod;
    return db;
}

}  // namespace

@implementation TPAutoCompletion {
    __weak ScintillaView *_view;
    NSString *_languageId;
    std::shared_ptr<ApiDatabase> _db;
    // FunctionCallTip state
    std::string _funcName;
    bool _haveFuncName;
    const ApiKeyword *_curFunction;
    size_t _currentOverload, _currentNbOverloads, _currentParam;
    sptr_t _curPos, _startPos;
    BOOL _selfActivated;
    BOOL _imagesDark, _imagesRegistered;
}

+ (instancetype)forView:(ScintillaView *)view {
    static char key;
    TPAutoCompletion *ac = objc_getAssociatedObject(view, &key);
    if (!ac) {
        ac = [TPAutoCompletion new];
        ac->_view = view;
        objc_setAssociatedObject(view, &key, ac, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return ac;
}

- (instancetype)init {
    if ((self = [super init])) { _lastCallTipText = @""; _haveFuncName = false; _curFunction = nullptr; }
    return self;
}

- (void)setLanguageId:(NSString *)languageId {
    NSString *path = findApiFile(languageId);
    auto db = databaseForPath(path);
    if ([languageId isEqualToString:_languageId] && db == _db) return;
    if (self.callTipVisible) [self closeCallTip];
    _languageId = [languageId copy];
    _apiFilePath = db ? path : nil;
    _db = db;
    [self resetCallTip];
    _haveFuncName = false;
}

- (BOOL)funcCompletionActive { return _db != nullptr; }

- (void)registerImages {
    ScintillaView *v = _view;
    BOOL dark = [TPChrome dark];
    if (_imagesRegistered && _imagesDark == dark) return;
    SCI(v, SCI_CLEARREGISTEREDIMAGES);
    SCI(v, SCI_REGISTERIMAGE, FUNC_IMG_ID, reinterpret_cast<sptr_t>(dark ? xpmfnDark : xpmfn));
    SCI(v, SCI_REGISTERIMAGE, BOX_IMG_ID, reinterpret_cast<sptr_t>(dark ? xpmboxDark : xpmbox));
    _imagesRegistered = YES;
    _imagesDark = dark;
}

// ---------------------------------------------------------------- completion lists (upstream showAutoComplete)
typedef NS_ENUM(NSInteger, TPAutocType) { TPAutocWord, TPAutocFunc, TPAutocFuncBrief, TPAutocFuncAndWord };

- (bool)ignoreCase { return _db ? _db->ignoreCase : true; }

- (void)getWordArray:(std::vector<std::string> &)wordArray begin:(const std::string &)beginChars exclude:(const std::string &)excludeChars {
    if ([TPPrefs b:@"pref.autocIgnoreNumbers"] && !beginChars.empty() && beginChars.find_first_not_of("0123456789") == std::string::npos) return;
    ScintillaView *v = _view;
    std::string escaped;
    for (char ch : beginChars) { if (strchr("\\^$.|?*+()[]{}", ch)) escaped += '\\'; escaped += ch; }
    std::string expr = "\\<" + escaped + "[^ \\t\\n\\r.,;:\"(){}=<>'+!?\\[\\]]+";
    int flags = SCFIND_WORDSTART | SCFIND_REGEXP | SCFIND_POSIX;
    if (!self.ignoreCase || (!_db && [_languageId isEqualToString:@"normal"])) flags |= SCFIND_MATCHCASE;
    const sptr_t oldStart = SCI(v, SCI_GETTARGETSTART), oldEnd = SCI(v, SCI_GETTARGETEND), oldFlags = SCI(v, SCI_GETSEARCHFLAGS);
    const sptr_t docLength = SCI(v, SCI_GETLENGTH);
    SCI(v, SCI_SETSEARCHFLAGS, flags);
    std::unordered_set<std::string> seen(wordArray.begin(), wordArray.end());
    std::unordered_set<std::string> boxIds, funcIds;
    if (_db) for (const auto &k : _db->keyWordArray) (k.substr(k.find('\x1E')) == "\x1E" + std::to_string(FUNC_IMG_ID) ? funcIds : boxIds).insert(k);
    const std::string boxId = "\x1E" + std::to_string(BOX_IMG_ID), funcId = "\x1E" + std::to_string(FUNC_IMG_ID);
    sptr_t from = 0;
    int guard = 0;
    while (from <= docLength && guard++ < 100000) {
        SCI(v, SCI_SETTARGETRANGE, from, docLength);
        sptr_t posFind = SCI(v, SCI_SEARCHINTARGET, expr.size(), reinterpret_cast<sptr_t>(expr.c_str()));
        if (posFind < 0) break;
        sptr_t ws = SCI(v, SCI_GETTARGETSTART), we = SCI(v, SCI_GETTARGETEND);
        if (we - ws < 256) {
            std::string w = sciGetRange(v, ws, we);
            if (w != excludeChars) {
                std::string item = w;
                if (_db) {
                    if (boxIds.count(w + boxId)) item = w + boxId;
                    else if (funcIds.count(w + funcId)) item = w + funcId;
                }
                if (seen.insert(item).second) wordArray.push_back(item);
            }
        }
        from = we > posFind ? we : posFind + 1;
    }
    SCI(v, SCI_SETSEARCHFLAGS, oldFlags);
    SCI(v, SCI_SETTARGETRANGE, oldStart, oldEnd);
}

- (BOOL)showAutoComplete:(TPAutocType)type autoInsert:(BOOL)autoInsert {
    if (type == TPAutocFunc && !_db) return NO;
    ScintillaView *v = _view;
    const sptr_t curPos = SCI(v, SCI_GETCURRENTPOS);
    const sptr_t startPos = SCI(v, SCI_WORDSTARTPOSITION, curPos, 1);
    if (curPos == startPos) return NO;
    const size_t len = static_cast<size_t>(curPos - startPos);
    std::string words;
    if (type == TPAutocFunc) {
        if (len >= _db->keyWordMaxLen) return NO;
    } else {
        if (len >= 256) return NO;
        const sptr_t endPos = SCI(v, SCI_WORDENDPOSITION, curPos, 1);
        if (endPos - startPos >= 256) return NO;
        std::string beginChars = sciGetRange(v, startPos, curPos);
        std::vector<std::string> wordArray;
        if (type == TPAutocWord || type == TPAutocFuncAndWord)
            [self getWordArray:wordArray begin:beginChars exclude:sciGetRange(v, startPos, endPos)];
        if ((type == TPAutocFuncBrief || type == TPAutocFuncAndWord) && _db) {
            for (const auto &kw : _db->keyWordArray) {
                std::string head = kw.substr(0, len);
                bool match = self.ignoreCase ? equalNoCase(head, beginChars) : head == beginChars;
                if (match && std::find(wordArray.begin(), wordArray.end(), kw) == wordArray.end()) wordArray.push_back(kw);
            }
        }
        if (wordArray.empty()) return NO;
        if (type == TPAutocWord && wordArray.size() == 1 && autoInsert) {
            std::string w = wordArray[0].substr(0, wordArray[0].find('\x1E'));
            sciReplaceRange(v, startPos, curPos, w);
            SCI(v, SCI_GOTOPOS, startPos + static_cast<sptr_t>(w.size()));
            return YES;
        }
        if (type == TPAutocWord || type == TPAutocFuncAndWord) {
            if (self.ignoreCase) std::stable_sort(wordArray.begin(), wordArray.end(), lessNoCase);
            else std::sort(wordArray.begin(), wordArray.end());
        }
        for (size_t i = 0; i < wordArray.size(); ++i) { words += wordArray[i]; if (i + 1 < wordArray.size()) words += ' '; }
    }
    [self registerImages];
    SCI(v, SCI_AUTOCSETTYPESEPARATOR, 0x1E);
    SCI(v, SCI_AUTOCSETSEPARATOR, ' ');
    SCI(v, SCI_AUTOCSETIGNORECASE, self.ignoreCase);
    SCI(v, SCI_AUTOCSETCASEINSENSITIVEBEHAVIOUR, self.ignoreCase ? SC_CASEINSENSITIVEBEHAVIOUR_IGNORECASE : SC_CASEINSENSITIVEBEHAVIOUR_RESPECTCASE);
    const std::string &list = type == TPAutocFunc ? _db->keyWords : words;
    SCI(v, SCI_AUTOCSHOW, len, reinterpret_cast<sptr_t>(list.c_str()));
    return YES;
}

- (BOOL)showApiComplete { return [self showAutoComplete:TPAutocFunc autoInsert:NO]; }
- (BOOL)showWordComplete:(BOOL)autoInsert { return [self showAutoComplete:TPAutocWord autoInsert:autoInsert]; }
- (BOOL)showApiAndWordComplete { return [self showAutoComplete:TPAutocFuncAndWord autoInsert:NO]; }

// ---------------------------------------------------------------- path completion (upstream showPathCompletion)
// Upstream completes absolute Windows paths ("C:\..."); on macOS the absolute forms are "/..." and "~/...".
static bool allowedBeforePath(char c) { return c == '\'' || c == '"' || c == '(' || c == '<' || c == '=' || isspace(static_cast<unsigned char>(c)); }

- (void)showPathCompletion {
    ScintillaView *v = _view;
    const sptr_t curPos = SCI(v, SCI_GETCURRENTPOS);
    const sptr_t lineStart = SCI(v, SCI_POSITIONFROMLINE, SCI(v, SCI_LINEFROMPOSITION, curPos));
    std::string line = sciGetRange(v, std::max(lineStart, curPos - 1024), curPos);
    size_t start = std::string::npos;
    for (size_t i = 0; i < line.size(); ++i) {
        bool candidate = line[i] == '/' || (line[i] == '~' && (i + 1 == line.size() || line[i + 1] == '/'));
        if (candidate && (i == 0 || allowedBeforePath(line[i - 1]))) start = i;
    }
    if (start == std::string::npos) return;
    std::string raw = line.substr(start);
    NSString *rawPath = NSStr(raw), *expanded = rawPath.stringByExpandingTildeInPath;
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    NSString *trimmed = [expanded hasSuffix:@"/"] && expanded.length > 1 ? [expanded substringToIndex:expanded.length - 1] : expanded;
    if ([fm fileExistsAtPath:trimmed isDirectory:&isDir] && !isDir) return;   // already a complete file name
    NSString *rawToMatch;
    if ([fm fileExistsAtPath:expanded isDirectory:&isDir] && isDir) rawToMatch = rawPath;
    else {
        NSRange slash = [rawPath rangeOfString:@"/" options:NSBackwardsSearch];
        if (slash.location == NSNotFound) return;
        rawToMatch = [rawPath substringToIndex:slash.location];
        if (!rawToMatch.length) rawToMatch = @"/";
    }
    NSString *dir = rawToMatch.stringByExpandingTildeInPath;
    NSArray *items = [fm contentsOfDirectoryAtPath:dir error:nil];
    if (!items) return;
    NSString *prefix = [rawToMatch hasSuffix:@"/"] ? rawToMatch : [rawToMatch stringByAppendingString:@"/"];
    NSMutableArray *entries = [NSMutableArray array];
    for (NSString *name in [items sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
        if (entries.count >= 2000) break;
        BOOL d = NO;
        [fm fileExistsAtPath:[dir stringByAppendingPathComponent:name] isDirectory:&d];
        [entries addObject:[NSString stringWithFormat:@"%@%@%@", prefix, name, d ? @"/" : @""]];
    }
    if (!entries.count) return;
    SCI(v, SCI_AUTOCSETSEPARATOR, '\n');
    SCI(v, SCI_AUTOCSETTYPESEPARATOR, 0x1E);
    SCI(v, SCI_AUTOCSETIGNORECASE, 1);
    SCI(v, SCI_AUTOCSETCASEINSENSITIVEBEHAVIOUR, SC_CASEINSENSITIVEBEHAVIOUR_IGNORECASE);
    SCI(v, SCI_AUTOCSHOW, raw.size(), reinterpret_cast<sptr_t>([entries componentsJoinedByString:@"\n"].UTF8String));
}

// ---------------------------------------------------------------- function call tips (upstream FunctionCallTip)
- (BOOL)callTipVisible { return _view && SCI(_view, SCI_CALLTIPACTIVE) != 0; }

- (void)resetCallTip {
    _currentOverload = 0; _currentParam = 0; _startPos = 0; _currentNbOverloads = 0; _curFunction = nullptr;
}

- (void)closeCallTip {
    if (!self.callTipVisible || !_selfActivated) return;
    SCI(_view, SCI_CALLTIPCANCEL);
    _selfActivated = NO;
    _currentOverload = 0;
}

- (bool)isWordChar:(char)ch {
    return isalnum(static_cast<unsigned char>(ch)) || ch == '_' || (_db && _db->additionalWordChar.find(ch) != std::string::npos && ch != 0);
}

- (BOOL)getCursorFunction {
    ScintillaView *v = _view;
    const sptr_t line = SCI(v, SCI_LINEFROMPOSITION, _curPos);
    const sptr_t startpos = SCI(v, SCI_POSITIONFROMLINE, line), endpos = SCI(v, SCI_GETLINEENDPOSITION, line);
    const sptr_t len = endpos - startpos + 3, offset = _curPos - startpos;
    if (offset < 2 || len >= 256) { [self resetCallTip]; return NO; }
    std::string lineData = sciGetRange(v, startpos, _curPos);
    struct Token { size_t pos, length; bool isIdentifier; };
    std::vector<Token> tokens;
    for (size_t i = 0; i < lineData.size(); ++i) {
        char ch = lineData[i];
        if ([self isWordChar:ch]) {
            size_t b = i;
            while (i < lineData.size() && [self isWordChar:lineData[i]]) ++i;
            tokens.push_back({b, i - b, true});
            --i;
        } else if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
        } else if (ch == '"' || ch == '\'') {
            char quote = ch;
            ++i;
            while (i < lineData.size() && lineData[i] != quote) { if (lineData[i] == '\\' && i + 1 < lineData.size()) ++i; ++i; }
        } else {
            tokens.push_back({i, 1, false});
        }
    }
    struct Values { int lastIdentifier = -1, lastFunctionIdentifier = -1, param = 0, scopeLevel = -1; };
    std::vector<Values> stack;
    Values cur;
    int scopeLevel = 0;
    for (size_t i = 0; i < tokens.size(); ++i) {
        const Token &t = tokens[i];
        if (t.isIdentifier) { cur.lastIdentifier = static_cast<int>(i); continue; }
        char ch = lineData[t.pos];
        if (ch == _db->start) {
            ++scopeLevel;
            stack.push_back(cur);
            cur.scopeLevel = scopeLevel;
            if (i > 0 && cur.lastIdentifier == static_cast<int>(i) - 1) { cur.lastFunctionIdentifier = cur.lastIdentifier; cur.param = 0; }
            else cur.lastFunctionIdentifier = -1;
        } else if (ch == _db->param && cur.lastFunctionIdentifier > -1) {
            ++cur.param;
        } else if (ch == _db->stop) {
            if (scopeLevel) --scopeLevel;
            if (!stack.empty()) { cur = stack.back(); stack.pop_back(); } else cur = Values();
        } else if (ch == _db->terminal) {
            stack.clear();
            cur = Values();
        }
    }
    while (cur.lastFunctionIdentifier == -1 && !stack.empty()) { cur = stack.back(); stack.pop_back(); }
    if (cur.lastFunctionIdentifier < 0) return NO;
    const Token &ft = tokens[static_cast<size_t>(cur.lastFunctionIdentifier)];
    std::string name = lineData.substr(ft.pos, ft.length);
    _currentParam = static_cast<size_t>(cur.param);
    bool same = _haveFuncName && (_db->ignoreCase ? (name.size() >= _funcName.size() && equalNoCase(name.substr(0, _funcName.size()), _funcName))
                                                  : name.compare(0, _funcName.size(), _funcName) == 0);
    if (same && _curFunction) return YES;
    _funcName = name;
    _haveFuncName = true;
    return [self loadFunction];
}

- (BOOL)loadFunction {
    [self resetCallTip];
    for (const auto &k : _db->keywords) {
        bool match = _db->ignoreCase ? equalNoCase(k.name, _funcName) : k.name == _funcName;
        if (!match) continue;
        if (!k.func) return NO;
        _curFunction = &k;
        break;
    }
    if (!_curFunction) return NO;
    _currentNbOverloads = _curFunction->overloads.size();
    return _currentNbOverloads > 0;
}

- (void)showCalltip {
    if (!_currentNbOverloads || !_curFunction) return;
    const auto &overloads = _curFunction->overloads;
    if (_currentParam >= overloads[_currentOverload].params.size() + 1) {
        for (size_t i = 0; i < overloads.size(); ++i)
            if (_currentParam < overloads[i].params.size() + 1) { _currentOverload = i; break; }
    }
    const Overload &ov = overloads[_currentOverload];
    std::string text;
    if (_currentNbOverloads > 1) text += "\001" + std::to_string(_currentOverload + 1) + " of " + std::to_string(_currentNbOverloads) + "\002";
    text += ov.retVal + ' ' + _funcName + ' ' + _db->start;
    size_t hs = 0, he = 0;
    for (size_t i = 0; i < ov.params.size(); ++i) {
        if (i == _currentParam) { hs = text.size(); he = hs + ov.params[i].size(); }
        text += ov.params[i];
        if (i + 1 < ov.params.size()) { text += _db->param; text += ' '; }
    }
    text += _db->stop;
    if (!ov.descr.empty()) text += "\n" + ov.descr;
    ScintillaView *v = _view;
    if (self.callTipVisible) SCI(v, SCI_CALLTIPCANCEL);
    else _startPos = _curPos;
    // upstream AutoCompletion::drawAutocomplete colours
    SCI(v, SCI_CALLTIPSETBACK, rgbToSci(0xFFFFFF));
    SCI(v, SCI_CALLTIPSETFORE, rgbToSci(0x808080));
    SCI(v, SCI_CALLTIPSETFOREHLT, rgbToSci(0x000080));
    SCI(v, SCI_CALLTIPSHOW, _startPos, reinterpret_cast<sptr_t>(text.c_str()));
    _lastCallTipText = NSStr(text);
    _selfActivated = YES;
    if (hs != he) SCI(v, SCI_CALLTIPSETHLT, hs, he);
}

- (BOOL)updateCallTip:(int)ch force:(BOOL)needShown {
    if (!_db) return NO;
    if (!needShown && ch != _db->start && ch != _db->param && !self.callTipVisible) return NO;
    _curPos = SCI(_view, SCI_GETCURRENTPOS);
    if (![self getCursorFunction]) { [self closeCallTip]; return NO; }
    [self showCalltip];
    return YES;
}

- (BOOL)showFunctionComplete { return _db && [self updateCallTip:0 force:YES]; }

- (void)showNextOverload {
    if (!self.callTipVisible || !_currentNbOverloads) return;
    _currentOverload = (_currentOverload + 1) % _currentNbOverloads;
    [self showCalltip];
}
- (void)showPreviousOverload {
    if (!self.callTipVisible || !_currentNbOverloads) return;
    _currentOverload = _currentOverload > 0 ? _currentOverload - 1 : _currentNbOverloads - 1;
    [self showCalltip];
}
- (void)callTipClick:(NSInteger)direction {
    if (!_db) return;
    if (direction == 1) [self showPreviousOverload];
    else if (direction == 2) [self showNextOverload];
}

// ---------------------------------------------------------------- typing (upstream AutoCompletion::update)
- (void)update:(int)character {
    if (!character) return;
    const BOOL enabled = [TPPrefs b:@"pref.autocEnabled"];
    const NSInteger mode = [TPPrefs i:@"pref.autocMode"];   // 0 function, 1 word, 2 both
    if (!_db && enabled && mode == 0) return;
    if ([TPPrefs b:@"pref.funcParamHint"] || self.callTipVisible)
        if ([self updateCallTip:character force:NO]) return;
    if (!enabled) return;
    const BOOL brief = [TPPrefs b:@"pref.autocBrief"];
    if (!brief && SCI(_view, SCI_AUTOCACTIVE)) return;
    const sptr_t pos = SCI(_view, SCI_GETCURRENTPOS);
    std::string word = sciGetRange(_view, SCI(_view, SCI_WORDSTARTPOSITION, pos, 1), pos);
    if (word.empty() || static_cast<NSInteger>(word.size()) < MAX(1, [TPPrefs i:@"pref.autocFromLen"])) return;
    if (mode == 1) [self showWordComplete:NO];
    else if (mode == 0) { if (brief) [self showAutoComplete:TPAutocFuncBrief autoInsert:NO]; else [self showApiComplete]; }
    else [self showApiAndWordComplete];
}

@end
