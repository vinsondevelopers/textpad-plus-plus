// Textpad++ — snippets. GPL-3.0-or-later.
#import "app/Snippets.h"
#import "app/Document.h"
#import "app/Preferences.h"
#import "app/Session.h"
#import "app/Sci.h"

@implementation TPSnippetExpansion
@end

// ------------------------------------------------------------ built-in snippets
static NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *TPBuiltInSnippets(void) {
    static NSDictionary *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSDictionary *cLike = @{
            @"for": @"for (int ${1:i} = 0; ${1:i} < ${2:count}; ${1:i}++) {\n\t$0\n}",
            @"if": @"if (${1:condition}) {\n\t$0\n}",
            @"ife": @"if (${1:condition}) {\n\t${2}\n} else {\n\t$0\n}",
            @"while": @"while (${1:condition}) {\n\t$0\n}",
            @"switch": @"switch (${1:value}) {\ncase ${2:1}:\n\t$0\n\tbreak;\ndefault:\n\tbreak;\n}",
        };
        NSMutableDictionary *c = [cLike mutableCopy];
        [c addEntriesFromDictionary:@{@"main": @"int main(int argc, char *argv[]) {\n\t$0\n\treturn 0;\n}", @"inc": @"#include <${1:stdio.h}>",
                                      @"struct": @"typedef struct {\n\t$0\n} ${1:Name};"}];
        NSMutableDictionary *cpp = [cLike mutableCopy];
        [cpp addEntriesFromDictionary:@{@"main": @"int main(int argc, char *argv[]) {\n\t$0\n\treturn 0;\n}", @"inc": @"#include <${1:iostream}>",
                                        @"class": @"class ${1:Name} {\npublic:\n\t${1:Name}();\n\t$0\n};", @"forr": @"for (const auto &${1:item} : ${2:items}) {\n\t$0\n}",
                                        @"cout": @"std::cout << ${1:value} << std::endl;"}];
        NSMutableDictionary *java = [cLike mutableCopy];
        [java addEntriesFromDictionary:@{@"main": @"public static void main(String[] args) {\n\t$0\n}", @"psvm": @"public static void main(String[] args) {\n\t$0\n}",
                                         @"class": @"public class ${1:Name} {\n\t$0\n}", @"sout": @"System.out.println(${1});",
                                         @"try": @"try {\n\t$0\n} catch (${1:Exception} e) {\n\te.printStackTrace();\n}", @"fore": @"for (${1:String} ${2:item} : ${3:items}) {\n\t$0\n}"}];
        NSMutableDictionary *cs = [cLike mutableCopy];
        [cs addEntriesFromDictionary:@{@"class": @"public class ${1:Name}\n{\n\t$0\n}", @"cw": @"Console.WriteLine(${1});", @"foreach": @"foreach (var ${1:item} in ${2:items})\n{\n\t$0\n}",
                                       @"prop": @"public ${1:string} ${2:Name} { get; set; }", @"try": @"try\n{\n\t$0\n}\ncatch (${1:Exception} e)\n{\n}"}];
        NSDictionary *js = @{
            @"fn": @"function ${1:name}(${2}) {\n\t$0\n}", @"afn": @"(${1}) => {\n\t$0\n}", @"for": @"for (let ${1:i} = 0; ${1:i} < ${2:array}.length; ${1:i}++) {\n\t$0\n}",
            @"forof": @"for (const ${1:item} of ${2:items}) {\n\t$0\n}", @"if": @"if (${1:condition}) {\n\t$0\n}", @"log": @"console.log(${1});",
            @"class": @"class ${1:Name} {\n\tconstructor(${2}) {\n\t\t$0\n\t}\n}", @"try": @"try {\n\t$0\n} catch (${1:error}) {\n\tconsole.error(${1:error});\n}",
            @"imp": @"import ${2:name} from '${1:module}';", @"afetch": @"const ${1:response} = await fetch(${2:url});\nconst ${3:data} = await ${1:response}.json();$0"};
        NSDictionary *py = @{
            @"def": @"def ${1:name}(${2}):\n\t${3:pass}$0", @"class": @"class ${1:Name}:\n\tdef __init__(self${2}):\n\t\t${3:pass}$0",
            @"for": @"for ${1:item} in ${2:items}:\n\t${3:pass}$0", @"if": @"if ${1:condition}:\n\t${2:pass}$0", @"ifmain": @"if __name__ == \"__main__\":\n\t${1:main()}$0",
            @"with": @"with open(${1:path}) as ${2:f}:\n\t${3:pass}$0", @"try": @"try:\n\t${1:pass}\nexcept ${2:Exception} as e:\n\t${3:raise}$0",
            @"pr": @"print(${1})", @"lc": @"[${1:x} for ${1:x} in ${2:items}]"};
        NSDictionary *html = @{
            @"html5": @"<!DOCTYPE html>\n<html lang=\"${1:en}\">\n<head>\n\t<meta charset=\"utf-8\">\n\t<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n\t<title>${2:Title}</title>\n</head>\n<body>\n\t$0\n</body>\n</html>",
            @"div": @"<div class=\"${1}\">$0</div>", @"a": @"<a href=\"${1:#}\">${2:text}</a>$0", @"img": @"<img src=\"${1}\" alt=\"${2}\">$0",
            @"link": @"<link rel=\"stylesheet\" href=\"${1:style.css}\">$0", @"script": @"<script src=\"${1}\"></script>$0", @"ul": @"<ul>\n\t<li>${1}</li>$0\n</ul>",
            @"table": @"<table>\n\t<tr>\n\t\t<th>${1}</th>\n\t</tr>\n\t<tr>\n\t\t<td>${2}</td>\n\t</tr>\n</table>$0"};
        NSDictionary *css = @{@"media": @"@media (max-width: ${1:600px}) {\n\t$0\n}", @"flex": @"display: flex;\njustify-content: ${1:center};\nalign-items: ${2:center};$0",
                              @"grid": @"display: grid;\ngrid-template-columns: ${1:repeat(3, 1fr)};\ngap: ${2:16px};$0"};
        NSDictionary *md = @{@"table": @"| ${1:Column} | ${2:Column} |\n| --- | --- |\n| ${3} | ${4} |$0", @"code": @"```${1:language}\n$0\n```",
                             @"link": @"[${1:text}](${2:url})$0", @"img": @"![${1:alt}](${2:path})$0", @"task": @"- [ ] ${1:task}$0"};
        NSDictionary *sql = @{@"sel": @"SELECT ${1:*}\nFROM ${2:table}\nWHERE ${3:condition};$0", @"ins": @"INSERT INTO ${1:table} (${2:columns})\nVALUES (${3:values});$0",
                              @"upd": @"UPDATE ${1:table}\nSET ${2:column} = ${3:value}\nWHERE ${4:condition};$0", @"ct": @"CREATE TABLE ${1:name} (\n\tid INTEGER PRIMARY KEY,\n\t$0\n);"};
        NSDictionary *sh = @{@"sb": @"#!/bin/${1:bash}\nset -euo pipefail\n$0", @"if": @"if [ ${1:condition} ]; then\n\t$0\nfi", @"for": @"for ${1:f} in ${2:*}; do\n\t$0\ndone",
                             @"fn": @"${1:name}() {\n\t$0\n}"};
        NSDictionary *swift = @{@"func": @"func ${1:name}(${2}) ${3:-> Void }{\n\t$0\n}", @"if": @"if ${1:condition} {\n\t$0\n}", @"guard": @"guard ${1:condition} else {\n\treturn$0\n}",
                                @"for": @"for ${1:item} in ${2:items} {\n\t$0\n}", @"struct": @"struct ${1:Name} {\n\t$0\n}"};
        NSDictionary *go = @{@"func": @"func ${1:name}(${2}) ${3}{\n\t$0\n}", @"iferr": @"if err != nil {\n\treturn ${1:err}\n}$0", @"for": @"for ${1:i} := 0; ${1:i} < ${2:n}; ${1:i}++ {\n\t$0\n}",
                             @"main": @"package main\n\nfunc main() {\n\t$0\n}"};
        NSDictionary *rust = @{@"fn": @"fn ${1:name}(${2}) ${3}{\n\t$0\n}", @"match": @"match ${1:value} {\n\t${2:_} => ${3},\n}$0", @"for": @"for ${1:item} in ${2:items} {\n\t$0\n}",
                               @"test": @"#[test]\nfn ${1:it_works}() {\n\t$0\n}"};
        NSDictionary *php = @{@"php": @"<?php\n$0\n?>", @"fn": @"function ${1:name}(${2}) {\n\t$0\n}", @"foreach": @"foreach (${1:$items} as ${2:$item}) {\n\t$0\n}",
                              @"if": @"if (${1:condition}) {\n\t$0\n}"};
        NSDictionary *all = @{@"todo": @"TODO(${1:me}): ${2}$0", @"lorem": @"Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."};
        d = @{@"*": all, @"c": c, @"cpp": cpp, @"objc": c, @"java": java, @"cs": cs, @"javascript.js": js, @"javascript": js, @"typescript": js,
              @"python": py, @"html": html, @"php": [php mutableCopy], @"css": css, @"markdown": md, @"sql": sql, @"bash": sh, @"swift": swift, @"go": go, @"rust": rust};
    });
    return d;
}

NSString *TPSnippetsFilePath(void) {
    return [[TPSession shared].settingsDirectory stringByAppendingPathComponent:@"snippets.json"];
}

static NSDictionary *TPUserSnippets(void) {
    static NSDictionary *cache;
    static NSDate *cacheDate;
    NSString *p = TPSnippetsFilePath();
    NSDate *m = [NSFileManager.defaultManager attributesOfItemAtPath:p error:nil].fileModificationDate;
    if (!m) return @{};
    if (cache && [cacheDate isEqual:m]) return cache;
    NSData *data = [NSData dataWithContentsOfFile:p];
    id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    cache = [obj isKindOfClass:NSDictionary.class] ? obj : @{};
    cacheDate = m;
    return cache;
}

NSDictionary<NSString *, NSString *> *TPSnippetsForLanguage(NSString *lang) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSString *key = lang.lowercaseString ?: @"";
    if ([key containsString:@"markdown"]) key = @"markdown";
    for (NSDictionary *src in @[TPBuiltInSnippets(), TPUserSnippets()]) {
        for (NSString *k in @[@"*", key]) {
            NSDictionary *set = src[k];
            if (![set isKindOfClass:NSDictionary.class]) continue;
            for (NSString *trigger in set) {
                id body = set[trigger];
                if ([body isKindOfClass:NSDictionary.class]) body = body[@"body"];   // {"body": ..., "description": ...}
                if ([body isKindOfClass:NSArray.class]) body = [body componentsJoinedByString:@"\n"];
                if ([body isKindOfClass:NSString.class]) out[trigger] = body;
            }
        }
    }
    return out;
}

// ------------------------------------------------------------ expansion
TPSnippetExpansion *TPExpandSnippet(NSString *body, NSString *indent, NSString *unit) {
    NSMutableString *text = [NSMutableString string];
    NSMutableDictionary<NSNumber *, NSMutableArray<NSValue *> *> *fields = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, NSString *> *defaults = [NSMutableDictionary dictionary];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\$\\{(\\d+)(?::([^}]*))?\\}|\\$(\\d+)" options:0 error:nil];
    NSUInteger last = 0;
    // a later ${1} without a default repeats the first one's default
    for (NSTextCheckingResult *m in [re matchesInString:body options:0 range:NSMakeRange(0, body.length)]) {
        NSRange n = [m rangeAtIndex:1].location != NSNotFound ? [m rangeAtIndex:1] : [m rangeAtIndex:3];
        NSNumber *k = @([body substringWithRange:n].integerValue);
        if ([m rangeAtIndex:2].location != NSNotFound && !defaults[k]) defaults[k] = [body substringWithRange:[m rangeAtIndex:2]];
    }
    for (NSTextCheckingResult *m in [re matchesInString:body options:0 range:NSMakeRange(0, body.length)]) {
        [text appendString:[body substringWithRange:NSMakeRange(last, m.range.location - last)]];
        NSRange n = [m rangeAtIndex:1].location != NSNotFound ? [m rangeAtIndex:1] : [m rangeAtIndex:3];
        NSNumber *k = @([body substringWithRange:n].integerValue);
        NSString *def = defaults[k] ?: @"";
        if (!fields[k]) fields[k] = [NSMutableArray array];
        [fields[k] addObject:[NSValue valueWithRange:NSMakeRange(text.length, def.length)]];
        [text appendString:def];
        last = NSMaxRange(m.range);
    }
    [text appendString:[body substringFromIndex:last]];
    // indentation: the body's tabs become the document's indent; later lines follow the trigger's line
    NSMutableString *out = [NSMutableString string];
    NSMutableArray<NSNumber *> *map = [NSMutableArray arrayWithCapacity:text.length + 1];   // old index -> new index
    for (NSUInteger i = 0; i < text.length; ++i) {
        [map addObject:@(out.length)];
        const unichar ch = [text characterAtIndex:i];
        if (ch == '\t') [out appendString:unit];
        else if (ch == '\n') { [out appendString:@"\n"]; [out appendString:indent]; }
        else [out appendFormat:@"%C", ch];
    }
    [map addObject:@(out.length)];
    NSMutableArray *stops = [NSMutableArray array];
    NSArray *keys = [[fields.allKeys filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"integerValue > 0"]] sortedArrayUsingSelector:@selector(compare:)];
    for (NSNumber *k in [keys arrayByAddingObject:@0]) {
        NSValue *v = fields[k].firstObject;
        if (!v) { if (k.integerValue == 0) [stops addObject:[NSValue valueWithRange:NSMakeRange(out.length, 0)]]; continue; }
        const NSRange r = v.rangeValue;
        const NSUInteger a = [map[r.location] unsignedIntegerValue], b = [map[NSMaxRange(r)] unsignedIntegerValue];
        [stops addObject:[NSValue valueWithRange:NSMakeRange(a, b - a)]];
    }
    TPSnippetExpansion *e = [TPSnippetExpansion new];
    e.text = out;
    e.stops = stops;
    return e;
}

// ------------------------------------------------------------ the active snippet in the editor
@interface TPSnippetSession : NSObject
@property (nonatomic, weak) ScintillaView *editor;
@property (nonatomic) std::vector<std::pair<sptr_t, sptr_t>> stops;   // byte positions (start, length)
@property (nonatomic) NSInteger current;
@property (nonatomic) sptr_t lengthAtStop;
@end
@implementation TPSnippetSession
@end

static TPSnippetSession *g_snippet;

static sptr_t utf8Length(NSString *s) { return (sptr_t)strlen(s.UTF8String ?: ""); }

@implementation TPMainWindowController (Snippets)

- (BOOL)snippetActive { return g_snippet != nil; }

- (BOOL)handleSnippetKey:(NSEvent *)e inEditor:(ScintillaView *)v {
    if (![TPPrefs b:@"pref.snippets"] || !v) return NO;
    const NSEventModifierFlags mods = e.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl | NSEventModifierFlagShift);
    const unichar ch = e.charactersIgnoringModifiers.length ? [e.charactersIgnoringModifiers characterAtIndex:0] : 0;
    const BOOL tab = ch == '\t' || ch == 0x19 /* ⇧Tab */;
    if (!tab || (mods & ~NSEventModifierFlagShift)) return NO;
    if (SCI(v, SCI_AUTOCACTIVE) || SCI(v, SCI_GETSELECTIONS) > 1) return NO;
    const BOOL back = (mods & NSEventModifierFlagShift) != 0;
    if (g_snippet && g_snippet.editor == v) {
        if ([self snippetNextField:!back inEditor:v]) return YES;
    }
    if (back) return NO;
    return [self expandSnippetInEditor:v];
}

- (BOOL)expandSnippetInEditor:(ScintillaView *)v {
    if (SCI(v, SCI_GETSELECTIONEMPTY) == 0 || SCI(v, SCI_GETREADONLY)) return NO;
    const sptr_t pos = SCI(v, SCI_GETCURRENTPOS), line = SCI(v, SCI_LINEFROMPOSITION, pos), ls = SCI(v, SCI_POSITIONFROMLINE, line);
    NSString *before = NSStr(sciGetRange(v, ls, pos));
    NSRange w = [before rangeOfString:@"[A-Za-z0-9_]+$" options:NSRegularExpressionSearch];
    if (w.location == NSNotFound) return NO;
    NSString *trigger = [before substringWithRange:w];
    NSString *body = TPSnippetsForLanguage(self.currentDocument.languageId ?: @"normal")[trigger];
    if (!body) return NO;
    NSString *indent = [before substringWithRange:[before rangeOfString:@"^[ \t]*" options:NSRegularExpressionSearch]];
    NSString *unit = SCI(v, SCI_GETUSETABS) ? @"\t" : [@"" stringByPaddingToLength:(NSUInteger)MAX((sptr_t)1, SCI(v, SCI_GETINDENT) ?: SCI(v, SCI_GETTABWIDTH)) withString:@" " startingAtIndex:0];
    const sptr_t eolMode = SCI(v, SCI_GETEOLMODE);
    TPSnippetExpansion *x = TPExpandSnippet(body, indent, unit);
    NSString *eol = eolMode == SC_EOL_CRLF ? @"\r\n" : eolMode == SC_EOL_CR ? @"\r" : @"\n";
    NSString *text = x.text;
    // stops are in characters of `text` with "\n" line ends: turn them into byte positions with the document's line ends
    std::vector<std::pair<sptr_t, sptr_t>> stops;
    const sptr_t start = pos - utf8Length(trigger);
    for (NSValue *val in x.stops) {
        const NSRange r = val.rangeValue;
        NSString *pre = [[text substringToIndex:r.location] stringByReplacingOccurrencesOfString:@"\n" withString:eol];
        NSString *mid = [[text substringWithRange:r] stringByReplacingOccurrencesOfString:@"\n" withString:eol];
        stops.push_back({start + utf8Length(pre), utf8Length(mid)});
    }
    const std::string u = [text stringByReplacingOccurrencesOfString:@"\n" withString:eol].UTF8String;
    SCI(v, SCI_BEGINUNDOACTION);
    SCI(v, SCI_SETTARGETRANGE, start, pos);
    SCI(v, SCI_REPLACETARGET, u.size(), reinterpret_cast<sptr_t>(u.data()));
    SCI(v, SCI_ENDUNDOACTION);
    g_snippet = nil;
    if (stops.size() > 1) {
        g_snippet = [TPSnippetSession new];
        g_snippet.editor = v;
        g_snippet.stops = stops;
        g_snippet.current = -1;
        [self snippetNextField:YES inEditor:v];
    } else {
        const sptr_t end = stops.empty() ? start + (sptr_t)u.size() : stops[0].first;
        SCI(v, SCI_SETSEL, end, end + (stops.empty() ? 0 : stops[0].second));
    }
    return YES;
}

- (BOOL)snippetNextField:(BOOL)forward inEditor:(ScintillaView *)v {
    TPSnippetSession *s = g_snippet;
    if (!s) return NO;
    auto stops = s.stops;
    const sptr_t len = SCI(v, SCI_GETLENGTH);
    if (s.current >= 0) {
        // what was typed went into the current field: later fields move by the difference
        const sptr_t delta = len - s.lengthAtStop;
        auto &cur = stops[(size_t)s.current];
        const sptr_t caret = SCI(v, SCI_GETCURRENTPOS);
        if (caret < cur.first || caret > cur.first + cur.second + MAX((sptr_t)0, delta)) { g_snippet = nil; return NO; }   // the caret left the snippet
        cur.second += delta;
        for (size_t k = 0; k < stops.size(); ++k) if ((NSInteger)k != s.current && stops[k].first >= cur.first + cur.second - delta) stops[k].first += delta;
    }
    const NSInteger next = s.current + (forward ? 1 : -1);
    if (next < 0) { s.stops = stops; return YES; }
    if (next >= (NSInteger)stops.size()) { g_snippet = nil; return NO; }
    s.current = next;
    s.stops = stops;
    s.lengthAtStop = len;
    const auto &f = stops[(size_t)next];
    SCI(v, SCI_SETSEL, f.first, f.first + f.second);
    SCI(v, SCI_SCROLLCARET);
    if (next == (NSInteger)stops.size() - 1) g_snippet = nil;   // $0: done
    return YES;
}

- (void)editSnippetsFile {
    NSString *p = TPSnippetsFilePath();
    if (![NSFileManager.defaultManager fileExistsAtPath:p]) {
        NSString *example =
            @"{\n"
             "  \"_help\": \"Your snippets. Keys are language ids (python, cpp, javascript.js, html, markdown, sql...) or * for every language. "
             "Type the trigger and press Tab. Fields: ${1:default}, ${2}, $0 = where the caret ends. A tab in the body is one indent.\",\n"
             "  \"*\": {\n"
             "    \"sig\": \"Best regards,\\n${1:Your Name}$0\"\n"
             "  },\n"
             "  \"python\": {\n"
             "    \"dc\": { \"body\": \"@dataclass\\nclass ${1:Name}:\\n\\t${2:field}: ${3:int}$0\", \"description\": \"dataclass\" }\n"
             "  }\n"
             "}\n";
        [NSFileManager.defaultManager createDirectoryAtPath:p.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        [example writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    [self openFile:p];
}

@end
