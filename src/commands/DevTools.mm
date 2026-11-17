// Textpad++ — built-in developer tools under the Plugins menu: XML Tools, Encode / Decode, Text Tools, Convert and
// Insert, plus the extra JSON Tools (sort keys, string escape, JWT). Each one works on the selection, or on the whole
// document when nothing is selected, as one undo step; conversions to another format open a new tab.
// GPL-3.0-or-later.
#import "app/MainWindowController.h"
#import "app/Document.h"
#import "app/Sci.h"
#import "app/Preferences.h"
#import "app/UserDefinedLanguages.h"
#import "commands/DevTools.h"
#include "core/Json.h"
#include "core/Csv.h"
#include "core/CodeFormat.h"
#include <Security/Security.h>

NSString *TPDevToolsTestInput = nil;   // the self-tests answer the XPath prompt with this

// ---------------------------------------------------------------- pure text functions (also used by the self-tests)
static NSArray<NSString *> *TPWords(NSString *s) {
    NSMutableArray *words = [NSMutableArray array];
    NSMutableString *cur = [NSMutableString string];
    NSCharacterSet *alnum = NSCharacterSet.alphanumericCharacterSet, *upper = NSCharacterSet.uppercaseLetterCharacterSet,
                   *lower = NSCharacterSet.lowercaseLetterCharacterSet, *digit = NSCharacterSet.decimalDigitCharacterSet;
    const NSUInteger n = s.length;
    for (NSUInteger i = 0; i < n; ++i) {
        const unichar c = [s characterAtIndex:i];
        if (![alnum characterIsMember:c]) { if (cur.length) { [words addObject:[cur copy]]; [cur setString:@""]; } continue; }
        if (cur.length && [upper characterIsMember:c]) {
            const unichar p = [cur characterAtIndex:cur.length - 1];
            const BOOL nextLower = i + 1 < n && [lower characterIsMember:[s characterAtIndex:i + 1]];
            // fooBar | foo2Bar | HTMLParser -> HTML Parser
            if ([lower characterIsMember:p] || [digit characterIsMember:p] || ([upper characterIsMember:p] && nextLower)) { [words addObject:[cur copy]]; [cur setString:@""]; }
        }
        [cur appendFormat:@"%C", c];
    }
    if (cur.length) [words addObject:cur];
    return words;
}

NSString *TPConvertCase(NSString *text, TPCaseStyle style) {
    NSMutableArray *outLines = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSString *body = [line hasSuffix:@"\r"] ? [line substringToIndex:line.length - 1] : line;
        NSString *cr = body.length < line.length ? @"\r" : @"";
        NSRange lead = [body rangeOfString:@"^\\s*" options:NSRegularExpressionSearch];
        NSRange trail = [body rangeOfString:@"\\s*$" options:NSRegularExpressionSearch];
        NSArray *words = TPWords(body);
        if (!words.count) { [outLines addObject:line]; continue; }
        NSMutableArray *parts = [NSMutableArray array];
        [words enumerateObjectsUsingBlock:^(NSString *w, NSUInteger i, BOOL *stop) {
            NSString *lw = w.lowercaseString;
            switch (style) {
                case TPCaseCamel: [parts addObject:i == 0 ? lw : lw.capitalizedString]; break;
                case TPCasePascal: [parts addObject:lw.capitalizedString]; break;
                case TPCaseConstant: [parts addObject:w.uppercaseString]; break;
                default: [parts addObject:lw];
            }
        }];
        NSString *sep = style == TPCaseSnake || style == TPCaseConstant ? @"_" : style == TPCaseKebab ? @"-" : style == TPCaseDot ? @"." : @"";
        [outLines addObject:[NSString stringWithFormat:@"%@%@%@%@", [body substringWithRange:lead], [parts componentsJoinedByString:sep],
                             trail.location > lead.length ? [body substringFromIndex:trail.location] : @"", cr]];
    }
    return [outLines componentsJoinedByString:@"\n"];
}

static NSString *TPUTF8(NSData *d) { return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil; }

static NSData *TPBase64Data(NSString *s) {
    NSMutableString *t = [[[s componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsJoinedByString:@""] mutableCopy];
    [t replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, t.length)];   // base64url too
    [t replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, t.length)];
    while (t.length % 4) [t appendString:@"="];
    return [[NSData alloc] initWithBase64EncodedString:t options:0];
}

static NSDictionary<NSString *, NSString *> *TPEntities(void) {
    static NSDictionary *d = @{@"amp": @"&", @"lt": @"<", @"gt": @">", @"quot": @"\"", @"apos": @"'", @"nbsp": @" ", @"copy": @"©",
        @"reg": @"®", @"trade": @"™", @"euro": @"€", @"pound": @"£", @"yen": @"¥", @"cent": @"¢", @"sect": @"§",
        @"deg": @"°", @"plusmn": @"±", @"times": @"×", @"divide": @"÷", @"middot": @"·", @"para": @"¶",
        @"hellip": @"…", @"mdash": @"—", @"ndash": @"–", @"lsquo": @"‘", @"rsquo": @"’", @"ldquo": @"“",
        @"rdquo": @"”", @"laquo": @"«", @"raquo": @"»", @"bull": @"•", @"larr": @"←", @"rarr": @"→",
        @"uarr": @"↑", @"darr": @"↓", @"hearts": @"♥", @"check": @"✓", @"shy": @"­", @"iexcl": @"¡", @"iquest": @"¿"};
    return d;
}

static NSString *TPCodePoint(UInt32 cp) {
    if (cp > 0x10FFFF || (cp >= 0xD800 && cp < 0xE000)) return nil;
    UInt32 be = CFSwapInt32HostToBig(cp);
    return [[NSString alloc] initWithBytes:&be length:4 encoding:NSUTF32BigEndianStringEncoding];
}

NSString *TPEncodeText(NSString *in, TPCodec codec, BOOL encode, NSString **error) {
    switch (codec) {
        case TPCodecBase64: {
            if (encode) return [[in dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
            NSData *d = TPBase64Data(in);
            if (!d) { *error = @"This is not valid Base64."; return nil; }
            NSString *s = TPUTF8(d);
            if (!s) *error = @"The decoded data is not UTF-8 text.";
            return s;
        }
        case TPCodecURL: {
            if (encode) {
                NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
                return [in stringByAddingPercentEncodingWithAllowedCharacters:ok];
            }
            NSString *s = in.stringByRemovingPercentEncoding;
            if (!s) *error = @"The text has an invalid %-escape, or the decoded bytes are not UTF-8.";
            return s;
        }
        case TPCodecHTML: {
            if (encode) {
                NSMutableString *o = [NSMutableString stringWithCapacity:in.length + 16];
                for (NSUInteger i = 0; i < in.length; ++i) {
                    const unichar c = [in characterAtIndex:i];
                    switch (c) {
                        case '&': [o appendString:@"&amp;"]; break;
                        case '<': [o appendString:@"&lt;"]; break;
                        case '>': [o appendString:@"&gt;"]; break;
                        case '"': [o appendString:@"&quot;"]; break;
                        case '\'': [o appendString:@"&#39;"]; break;
                        default: [o appendFormat:@"%C", c];
                    }
                }
                return o;
            }
            NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"&(#[0-9]{1,7}|#[xX][0-9A-Fa-f]{1,6}|[A-Za-z][A-Za-z0-9]{1,15});" options:0 error:nil];
            NSMutableString *o = [NSMutableString string];
            __block NSUInteger last = 0;
            [re enumerateMatchesInString:in options:0 range:NSMakeRange(0, in.length) usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
                NSString *name = [in substringWithRange:[m rangeAtIndex:1]], *rep = nil;
                if ([name hasPrefix:@"#x"] || [name hasPrefix:@"#X"]) rep = TPCodePoint((UInt32)strtoul([name substringFromIndex:2].UTF8String, NULL, 16));
                else if ([name hasPrefix:@"#"]) rep = TPCodePoint((UInt32)strtoul([name substringFromIndex:1].UTF8String, NULL, 10));
                else rep = TPEntities()[name];
                [o appendString:[in substringWithRange:NSMakeRange(last, m.range.location - last)]];
                [o appendString:rep ?: [in substringWithRange:m.range]];
                last = NSMaxRange(m.range);
            }];
            [o appendString:[in substringFromIndex:last]];
            return o;
        }
        case TPCodecUnicode: {
            NSMutableString *o = [NSMutableString string];
            if (encode) {
                for (NSUInteger i = 0; i < in.length; ++i) {
                    const unichar c = [in characterAtIndex:i];
                    if (c >= 0x20 && c < 0x7F) [o appendFormat:@"%C", c];
                    else if (c == '\n' || c == '\r' || c == '\t') [o appendFormat:@"%C", c];
                    else [o appendFormat:@"\\u%04X", c];
                }
                return o;
            }
            NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\\\u\\{([0-9A-Fa-f]{1,6})\\}|\\\\U([0-9A-Fa-f]{8})|\\\\u([0-9A-Fa-f]{4})|\\\\x([0-9A-Fa-f]{2})" options:0 error:nil];
            __block NSUInteger last = 0;
            NSMutableData *units = [NSMutableData data];   // 😀 pairs join up as UTF-16
            void (^flush)(void) = ^{ if (units.length) { [o appendString:[[NSString alloc] initWithData:units encoding:NSUTF16LittleEndianStringEncoding] ?: @"�"]; units.length = 0; } };
            [re enumerateMatchesInString:in options:0 range:NSMakeRange(0, in.length) usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
                if (m.range.location != last) { flush(); [o appendString:[in substringWithRange:NSMakeRange(last, m.range.location - last)]]; }
                for (NSUInteger g = 1; g <= 4; ++g) {
                    NSRange r = [m rangeAtIndex:g];
                    if (r.location == NSNotFound) continue;
                    UInt32 v = (UInt32)strtoul([in substringWithRange:r].UTF8String, NULL, 16);
                    if (g == 3) { uint16_t u = CFSwapInt16HostToLittle((uint16_t)v); [units appendBytes:&u length:2]; }
                    else { flush(); [o appendString:TPCodePoint(v) ?: [in substringWithRange:m.range]]; }
                }
                last = NSMaxRange(m.range);
            }];
            flush();
            [o appendString:[in substringFromIndex:last]];
            return o;
        }
        case TPCodecHex: {
            if (encode) {
                NSData *d = [in dataUsingEncoding:NSUTF8StringEncoding];
                NSMutableArray *bytes = [NSMutableArray arrayWithCapacity:d.length];
                const uint8_t *p = (const uint8_t *)d.bytes;
                for (NSUInteger i = 0; i < d.length; ++i) [bytes addObject:[NSString stringWithFormat:@"%02X", p[i]]];
                return [bytes componentsJoinedByString:@" "];
            }
            NSString *t = [in stringByReplacingOccurrencesOfString:@"0x" withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, in.length)];
            NSMutableData *d = [NSMutableData data];
            int half = -1;
            for (NSUInteger i = 0; i < t.length; ++i) {
                const unichar c = [t characterAtIndex:i];
                if (c == ' ' || c == ',' || c == '\n' || c == '\r' || c == '\t' || c == ':' || c == '-') continue;
                int v = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
                if (v < 0) { *error = [NSString stringWithFormat:@"'%C' is not a hex digit.", c]; return nil; }
                if (half < 0) half = v;
                else { uint8_t b = (uint8_t)(half << 4 | v); [d appendBytes:&b length:1]; half = -1; }
            }
            if (half >= 0) { *error = @"An odd number of hex digits."; return nil; }
            NSString *s = TPUTF8(d);
            if (!s) *error = @"The decoded bytes are not UTF-8 text.";
            return s;
        }
    }
    return nil;
}

// "eyJ...": header and payload as one pretty JSON object; exp / iat / nbf get readable dates
NSString *TPDecodeJWT(NSString *token, NSString **error) {
    NSArray *parts = [[token stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] componentsSeparatedByString:@"."];
    if (parts.count < 2) { *error = @"A JWT has three parts separated by dots (header.payload.signature)."; return nil; }
    NSMutableString *flat = [NSMutableString stringWithString:@"{"];
    NSArray *names = @[@"header", @"payload"];
    for (int k = 0; k < 2; ++k) {
        NSString *json = TPUTF8(TPBase64Data(parts[k]));
        if (!json || !tpp::json::validate(json.UTF8String).ok) { *error = [NSString stringWithFormat:@"The %@ is not Base64URL-encoded JSON.", names[k]]; return nil; }
        [flat appendFormat:@"%@\"%@\":%@", k ? @"," : @"", names[k], json];
    }
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:TPBase64Data(parts[1]) options:0 error:nil];
    if ([payload isKindOfClass:NSDictionary.class]) {
        NSISO8601DateFormatter *f = [NSISO8601DateFormatter new];
        f.timeZone = NSTimeZone.localTimeZone;
        NSMutableArray *dates = [NSMutableArray array];
        for (NSString *k in @[@"iat", @"nbf", @"exp"]) {
            if (![payload[k] isKindOfClass:NSNumber.class]) continue;
            NSDate *d = [NSDate dateWithTimeIntervalSince1970:[payload[k] doubleValue]];
            NSString *v = [f stringFromDate:d];
            if ([k isEqualToString:@"exp"]) v = [v stringByAppendingString:d.timeIntervalSinceNow < 0 ? @" (expired)" : @" (not expired)"];
            [dates addObject:[NSString stringWithFormat:@"%s:%s", tpp::json::escapeString(k.UTF8String).c_str(), tpp::json::escapeString(v.UTF8String).c_str()]];
        }
        if (dates.count) [flat appendFormat:@",\"dates\":{%@}", [dates componentsJoinedByString:@","]];
    }
    if (parts.count > 2) [flat appendFormat:@",\"signature\":%s", tpp::json::escapeString([parts[2] UTF8String]).c_str()];
    [flat appendString:@"}"];
    return @(tpp::json::format(flat.UTF8String, "    ", "\n").text.c_str());
}

// numbers of 9-13 digits are Unix times (seconds, or milliseconds from 12 digits); anything else is read as a date
NSString *TPConvertTimestamp(NSString *in, NSString **error) {
    NSString *t = [in stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSISO8601DateFormatter *iso = [NSISO8601DateFormatter new];
    iso.timeZone = NSTimeZone.localTimeZone;
    if ([t rangeOfString:@"^-?[0-9]{1,13}(\\.[0-9]+)?$" options:NSRegularExpressionSearch].location != NSNotFound) {
        double v = t.doubleValue;
        if ([t componentsSeparatedByString:@"."][0].length >= 12) v /= 1000.0;
        return [iso stringFromDate:[NSDate dateWithTimeIntervalSince1970:v]];
    }
    NSDate *d = [iso dateFromString:t];
    if (!d) {
        iso.formatOptions = NSISO8601DateFormatWithFullDate;
        d = [iso dateFromString:t];
    }
    if (!d) {
        NSDataDetector *det = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeDate error:nil];
        d = [det firstMatchInString:t options:0 range:NSMakeRange(0, t.length)].date;
    }
    if (!d) { *error = @"Select a Unix time (e.g. 1763116800) or a date (e.g. 2026-11-14T10:00:00Z)."; return nil; }
    return [NSString stringWithFormat:@"%lld", (long long)floor(d.timeIntervalSince1970)];
}

NSString *TPConvertNumbers(NSString *in, BOOL toHex) {
    NSString *pattern = toHex ? @"(?<![0-9A-Za-z_.])-?[0-9]+(?![0-9A-Za-z_.])" : @"(?<![0-9A-Za-z_])0[xX][0-9A-Fa-f]+(?![0-9A-Za-z_])";
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSMutableString *o = [in mutableCopy];
    for (NSTextCheckingResult *m in [[re matchesInString:in options:0 range:NSMakeRange(0, in.length)] reverseObjectEnumerator]) {
        NSString *tok = [in substringWithRange:m.range], *rep;
        if (toHex) {
            const long long v = tok.longLongValue;
            rep = v < 0 ? [NSString stringWithFormat:@"-0x%llX", (unsigned long long)(-v)] : [NSString stringWithFormat:@"0x%llX", v];
        } else rep = [NSString stringWithFormat:@"%llu", strtoull([tok substringFromIndex:2].UTF8String, NULL, 16)];
        [o replaceCharactersInRange:m.range withString:rep];
    }
    return o;
}

// the first separator of the line; for "=", not one of == != <= >= =>
static NSRange TPSeparatorIn(NSString *l, NSString *sep) {
    NSRange r = NSMakeRange(0, 0);
    for (NSUInteger from = 0; from < l.length;) {
        r = [l rangeOfString:sep options:0 range:NSMakeRange(from, l.length - from)];
        if (r.location == NSNotFound || ![sep isEqualToString:@"="]) return r;
        const unichar p = r.location ? [l characterAtIndex:r.location - 1] : ' ', n = NSMaxRange(r) < l.length ? [l characterAtIndex:NSMaxRange(r)] : ' ';
        if (!strchr("=!<>+-*/%&|^:", p) && n != '=' && n != '>') return r;
        from = NSMaxRange(r) + 1;
    }
    return NSMakeRange(NSNotFound, 0);
}

// "a = 1" / "long_name = 2" line up their "="; "key: value" lines up the values
NSString *TPAlignOn(NSString *in, NSString *sep) {
    NSArray<NSString *> *lines = [in componentsSeparatedByString:@"\n"];
    NSCharacterSet *ws = NSCharacterSet.whitespaceCharacterSet;
    NSUInteger col = 0;
    NSMutableArray *heads = [NSMutableArray array], *tails = [NSMutableArray array];
    for (NSString *l in lines) {
        NSRange r = TPSeparatorIn(l, sep);
        if (r.location == NSNotFound) { [heads addObject:NSNull.null]; [tails addObject:NSNull.null]; continue; }
        NSRange lead = [l rangeOfString:@"^[ \t]*" options:NSRegularExpressionSearch];
        NSString *before = [[l substringWithRange:NSMakeRange(lead.length, r.location - lead.length)] stringByTrimmingCharactersInSet:ws];
        NSString *head = [[l substringToIndex:lead.length] stringByAppendingString:before];
        NSString *after = [[l substringFromIndex:NSMaxRange(r)] stringByTrimmingCharactersInSet:ws];
        [heads addObject:head];
        [tails addObject:after];
        col = MAX(col, head.length);
    }
    NSMutableArray *outLines = [NSMutableArray array];
    [lines enumerateObjectsUsingBlock:^(NSString *l, NSUInteger i, BOOL *stop) {
        if (heads[i] == NSNull.null) { [outLines addObject:l]; return; }
        NSString *head = heads[i], *after = tails[i];
        NSString *cr = [after hasSuffix:@"\r"] ? @"\r" : @"";
        if (cr.length) after = [after substringToIndex:after.length - 1];
        if ([sep isEqualToString:@":"])
            [outLines addObject:[NSString stringWithFormat:@"%@%@%@", [[head stringByAppendingString:@":"] stringByPaddingToLength:col + 1 withString:@" " startingAtIndex:0],
                                 after.length ? [@" " stringByAppendingString:after] : @"", cr]];
        else
            [outLines addObject:[NSString stringWithFormat:@"%@ %@%@%@", [head stringByPaddingToLength:col withString:@" " startingAtIndex:0], sep,
                                 after.length ? [@" " stringByAppendingString:after] : @"", cr]];
    }];
    return [outLines componentsJoinedByString:@"\n"];
}

NSString *TPSortLinesByLength(NSString *in) {
    NSArray *lines = [in componentsSeparatedByString:@"\n"];
    BOOL endsWithNewline = lines.count > 1 && [lines.lastObject length] == 0;
    if (endsWithNewline) lines = [lines subarrayWithRange:NSMakeRange(0, lines.count - 1)];
    NSArray *sorted = [lines sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return a.length < b.length ? NSOrderedAscending : a.length > b.length ? NSOrderedDescending : NSOrderedSame;
    }];
    NSString *o = [sorted componentsJoinedByString:@"\n"];
    return endsWithNewline ? [o stringByAppendingString:@"\n"] : o;
}

NSString *TPEscapeRegex(NSString *in) { return [NSRegularExpression escapedPatternForString:in]; }

static NSUInteger TPXMLOptions(void) {
    return NSXMLNodePreserveCDATA | NSXMLNodePreserveAttributeOrder | NSXMLNodePreserveNamespaceOrder |
           NSXMLNodePreserveEntities | NSXMLNodePreserveQuotes | NSXMLNodePreserveCharacterReferences;
}

// well-formedness; *line / *column (1-based) say where it breaks
BOOL TPCheckXML(NSString *xml, NSString **error, NSInteger *line, NSInteger *column) {
    NSXMLParser *p = [[NSXMLParser alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding]];
    if ([p parse]) return YES;
    *error = p.parserError.localizedDescription ?: @"The XML is not well-formed.";
    *line = MAX((NSInteger)1, p.lineNumber);
    *column = MAX((NSInteger)1, p.columnNumber);
    return NO;
}

NSString *TPFormatXML(NSString *xml, BOOL pretty, NSString **error) {
    NSError *e = nil;
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xml options:TPXMLOptions() error:&e];
    if (!doc) { *error = e.localizedDescription ?: @"The XML is not well-formed."; return nil; }
    // drop the whitespace-only text between elements; it is what the pretty printer re-creates
    NSMutableArray *stack = [NSMutableArray arrayWithObject:doc];
    while (stack.count) {
        NSXMLNode *n = stack.lastObject;
        [stack removeLastObject];
        for (NSXMLNode *c in [n.children copy]) {
            if (c.kind == NSXMLTextKind && [c.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0 && n.childCount > 1)
                [(NSXMLElement *)n removeChildAtIndex:c.index];
            else if (c.kind == NSXMLElementKind) [stack addObject:c];
        }
    }
    NSString *s = [doc XMLStringWithOptions:TPXMLOptions() | (pretty ? NSXMLNodePrettyPrint : 0) | NSXMLNodeCompactEmptyElement];
    const BOOL hadDecl = [[xml stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] hasPrefix:@"<?xml"];
    if (!hadDecl && [s hasPrefix:@"<?xml"]) {   // NSXMLDocument adds a declaration; keep the input's choice
        NSRange end = [s rangeOfString:@"?>"];
        s = [[s substringFromIndex:NSMaxRange(end)] stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
    }
    return s;
}

NSString *TPRunXPath(NSString *xml, NSString *xpath, NSString **error) {
    NSError *e = nil;
    NSXMLDocument *doc = [[NSXMLDocument alloc] initWithXMLString:xml options:TPXMLOptions() error:&e];
    if (!doc) { *error = e.localizedDescription ?: @"The XML is not well-formed."; return nil; }
    NSArray *nodes = [doc nodesForXPath:xpath error:&e];
    if (!nodes) { *error = [NSString stringWithFormat:@"The XPath expression is not valid: %@", e.localizedDescription]; return nil; }
    NSMutableArray *out = [NSMutableArray array];
    for (NSXMLNode *n in nodes) [out addObject:n.kind == NSXMLElementKind ? [n XMLStringWithOptions:NSXMLNodePrettyPrint] : n.stringValue ?: @""];
    return [NSString stringWithFormat:@"<!-- XPath: %@ — %lu match%@ -->\n%@\n", [xpath stringByReplacingOccurrencesOfString:@"--" withString:@"- -"],
            (unsigned long)nodes.count, nodes.count == 1 ? @"" : @"es", [out componentsJoinedByString:@"\n"]];
}

NSString *TPInsertText(TPInsertKind kind) {
    switch (kind) {
        case TPInsertUUID: return NSUUID.UUID.UUIDString.lowercaseString;
        case TPInsertUnixTime: return [NSString stringWithFormat:@"%lld", (long long)NSDate.date.timeIntervalSince1970];
        case TPInsertISODate: { NSISO8601DateFormatter *f = [NSISO8601DateFormatter new]; f.timeZone = NSTimeZone.localTimeZone; return [f stringFromDate:NSDate.date]; }
        case TPInsertLorem:
            return @"Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. "
                    "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. "
                    "Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. "
                    "Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.";
        case TPInsertPassword: {
            static const char set[] = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*-_=+?";
            const size_t n = sizeof set - 1;
            NSMutableString *p = [NSMutableString string];
            while (p.length < 20) {
                uint8_t b;
                if (SecRandomCopyBytes(kSecRandomDefault, 1, &b) != errSecSuccess) continue;
                if (b >= 256 - 256 % n) continue;   // no modulo bias
                [p appendFormat:@"%c", set[b % n]];
            }
            return p;
        }
    }
    return @"";
}

// ---------------------------------------------------------------- running a tool on the editor
@implementation TPMainWindowController (DevTools)

- (std::string)devToolsIndent {
    ScintillaView *v = self.editor;
    return SCI(v, SCI_GETUSETABS) ? "\t" : std::string(static_cast<size_t>(MAX((sptr_t)1, SCI(v, SCI_GETINDENT) ?: SCI(v, SCI_GETTABWIDTH))), ' ');
}

- (std::string)devToolsEol {
    const sptr_t m = SCI(self.editor, SCI_GETEOLMODE);
    return m == SC_EOL_CRLF ? "\r\n" : m == SC_EOL_CR ? "\r" : "\n";
}

// the selection, or the whole document when nothing is selected
- (NSString *)devToolsInput:(sptr_t *)from to:(sptr_t *)to whole:(BOOL *)whole {
    ScintillaView *v = self.editor;
    sptr_t a = SCI(v, SCI_GETSELECTIONSTART), b = SCI(v, SCI_GETSELECTIONEND);
    *whole = a == b;
    if (*whole) { a = 0; b = SCI(v, SCI_GETLENGTH); }
    *from = a;
    *to = b;
    return NSStr(sciGetRange(v, a, b));
}

- (void)devToolsTransform:(NSString *(^)(NSString *in, NSString **error))fn title:(NSString *)title {
    if (!self.currentDocument) return;
    ScintillaView *v = self.editor;
    sptr_t a, b;
    BOOL whole;
    NSString *in = [self devToolsInput:&a to:&b whole:&whole];
    NSString *err = nil;
    NSString *out = fn(in, &err);
    if (!out) { [self showMessage:title informative:err ?: @"The text could not be converted."]; return; }
    if ([out isEqualToString:in]) return;
    if (SCI(v, SCI_GETREADONLY)) { TPBeep(); return; }
    const std::string u = out.UTF8String ?: "";
    SCI(v, SCI_BEGINUNDOACTION);
    SCI(v, SCI_SETTARGETRANGE, a, b);
    SCI(v, SCI_REPLACETARGET, u.size(), reinterpret_cast<sptr_t>(u.data()));
    SCI(v, SCI_ENDUNDOACTION);
    if (whole) SCI(v, SCI_GOTOPOS, 0);
    else SCI(v, SCI_SETSEL, a, a + static_cast<sptr_t>(u.size()));
}

// the result in a new tab, highlighted as `languageId`
- (void)devToolsToNewTab:(NSString *(^)(NSString *in, NSString **error))fn title:(NSString *)title language:(NSString *)languageId {
    if (!self.currentDocument) return;
    sptr_t a, b;
    BOOL whole;
    NSString *in = [self devToolsInput:&a to:&b whole:&whole];
    NSString *err = nil;
    NSString *out = fn(in, &err);
    if (!out) { [self showMessage:title informative:err ?: @"The text could not be converted."]; return; }
    TPDocument *d = [self newDocument];
    if (!d) return;
    const std::string u = out.UTF8String ?: "";
    [self withDocument:d perform:^(ScintillaView *v) {
        SCI(v, SCI_SETTEXT, 0, reinterpret_cast<sptr_t>(u.c_str()));
        SCI(v, SCI_GOTOPOS, 0);
    }];
    if (languageId.length) [self setDocumentLanguage:d languageId:languageId];
}

- (void)devToolsInsert:(TPInsertKind)kind {
    ScintillaView *v = self.editor;
    if (!self.currentDocument) return;
    if (SCI(v, SCI_GETREADONLY)) { TPBeep(); return; }
    const std::string u = TPInsertText(kind).UTF8String;
    SCI(v, SCI_REPLACESEL, 0, reinterpret_cast<sptr_t>(u.c_str()));
}

- (NSString *)askDevToolsText:(NSString *)title label:(NSString *)label value:(NSString *)value {
    if (TPDevToolsTestInput) return TPDevToolsTestInput;
    NSAlert *a = [NSAlert new];
    a.messageText = title;
    a.informativeText = label;
    NSTextField *tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 360, 24)];
    tf.stringValue = value ?: @"";
    a.accessoryView = tf;
    [a addButtonWithTitle:@"OK"];
    [a addButtonWithTitle:@"Cancel"];
    a.window.initialFirstResponder = tf;
    if ([a runModal] != NSAlertFirstButtonReturn) return nil;
    NSString *s = [tf.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (s.length) [[NSUserDefaults standardUserDefaults] setObject:s forKey:@"devtools.lastXPath"];
    return s.length ? s : nil;
}

- (void)runDevTool:(NSInteger)tool {
    __weak TPMainWindowController *ws = self;
    std::string indent = [self devToolsIndent], eol = [self devToolsEol];
    switch (tool) {
        // JSON
        case TPDevToolJsonSortKeys: {
            [self devToolsTransform:^NSString *(NSString *in, NSString **e) {
                tpp::json::Result r = tpp::json::sortKeys(in.UTF8String, indent, eol);
                if (!r.ok) { *e = [NSString stringWithFormat:@"%s (at character %lu).", r.error.c_str(), (unsigned long)r.errorOffset + 1]; return nil; }
                return @(r.text.c_str());
            } title:@"Invalid JSON"];
            if (TPDocument *d = self.currentDocument; [d.languageId isEqualToString:@"normal"] && SCI(self.editor, SCI_GETSELECTIONEMPTY)) [self setDocumentLanguage:d languageId:@"json"];
            break;
        }
        case TPDevToolJsonEscape: {
            [self devToolsTransform:^NSString *(NSString *in, NSString **e) { return @(tpp::json::escapeString(in.UTF8String).c_str()); } title:@"Escape"];
            break;
        }
        case TPDevToolJsonUnescape: {
            [self devToolsTransform:^NSString *(NSString *in, NSString **e) {
                tpp::json::Result r = tpp::json::unescapeString(in.UTF8String);
                if (!r.ok) { *e = [NSString stringWithFormat:@"This is not a valid JSON string: %s.", r.error.c_str()]; return nil; }
                return [[NSString alloc] initWithBytes:r.text.data() length:r.text.size() encoding:NSUTF8StringEncoding];
            } title:@"Unescape"];
            break;
        }
        case TPDevToolJwtDecode: {
            [self devToolsToNewTab:^NSString *(NSString *in, NSString **e) { return TPDecodeJWT(in, e); } title:@"Decode JWT" language:@"json"];
            break;
        }
        // XML
        case TPDevToolXmlPretty:
        case TPDevToolXmlCompress: {
            const BOOL pretty = tool == TPDevToolXmlPretty;
            [self devToolsTransform:^NSString *(NSString *in, NSString **e) { return TPFormatXML(in, pretty, e); } title:@"Invalid XML"];
            if (TPDocument *d = self.currentDocument; [d.languageId isEqualToString:@"normal"]) [self setDocumentLanguage:d languageId:@"xml"];
            break;
        }
        case TPDevToolXmlValidate: {
            sptr_t a, b;
            BOOL whole;
            NSString *in = [self devToolsInput:&a to:&b whole:&whole];
            NSString *err = nil;
            NSInteger line = 0, col = 0;
            if (TPCheckXML(in, &err, &line, &col)) { [self showMessage:@"The XML is well-formed." informative:nil]; break; }
            ScintillaView *v = self.editor;
            const sptr_t baseLine = SCI(v, SCI_LINEFROMPOSITION, a);
            SCI(v, SCI_GOTOPOS, SCI(v, SCI_FINDCOLUMN, baseLine + line - 1, col - 1));
            [self showMessage:@"Invalid XML" informative:[NSString stringWithFormat:@"%@\nLine %ld, column %ld.", err, (long)(baseLine + line), (long)col]];
            break;
        }
        case TPDevToolXPath: {
            NSString *xp = [self askDevToolsText:@"XPath Query" label:@"Expression (for example //item/@id). The matches open in a new tab."
                                           value:[[NSUserDefaults standardUserDefaults] stringForKey:@"devtools.lastXPath"] ?: @"//"];
            if (!xp) break;
            [self devToolsToNewTab:^NSString *(NSString *in, NSString **e) { return TPRunXPath(in, xp, e); } title:@"XPath Query" language:@"xml"];
            break;
        }
        // Encode / Decode
        case TPDevToolBase64Encode: case TPDevToolBase64Decode: case TPDevToolURLEncode: case TPDevToolURLDecode:
        case TPDevToolHTMLEncode: case TPDevToolHTMLDecode: case TPDevToolUnicodeEscape: case TPDevToolUnicodeUnescape:
        case TPDevToolHexEncode: case TPDevToolHexDecode: {
            const int k = tool - TPDevToolBase64Encode;
            const TPCodec codec = static_cast<TPCodec>(k / 2);
            const BOOL encode = k % 2 == 0;
            [self devToolsTransform:^NSString *(NSString *in, NSString **e) { return TPEncodeText(in, codec, encode, e); } title:encode ? @"Encode" : @"Decode"];
            break;
        }
        // Text
        case TPDevToolCamel: case TPDevToolPascal: case TPDevToolSnake: case TPDevToolConstant: case TPDevToolKebab: case TPDevToolDot: {
            const TPCaseStyle st = static_cast<TPCaseStyle>(tool - TPDevToolCamel);
            [self devToolsTransform:^NSString *(NSString *in, NSString **e) { return TPConvertCase(in, st); } title:@"Convert Case"];
            break;
        }
        case TPDevToolSortByLength:
        case TPDevToolAlignEquals:
        case TPDevToolAlignColon: {
            // whole lines: the selection grows to full lines (all lines when nothing is selected)
            ScintillaView *v = self.editor;
            if (!SCI(v, SCI_GETSELECTIONEMPTY)) {
                sptr_t a = SCI(v, SCI_GETSELECTIONSTART), b = SCI(v, SCI_GETSELECTIONEND);
                const sptr_t la = SCI(v, SCI_LINEFROMPOSITION, a), lb = SCI(v, SCI_LINEFROMPOSITION, b);
                const sptr_t endLine = lb > la && SCI(v, SCI_POSITIONFROMLINE, lb) == b ? lb - 1 : lb;
                SCI(v, SCI_SETSEL, SCI(v, SCI_POSITIONFROMLINE, la), SCI(v, SCI_GETLINEENDPOSITION, endLine));
            }
            [self devToolsTransform:^NSString *(NSString *in, NSString **e) {
                if (tool == TPDevToolSortByLength) return TPSortLinesByLength(in);
                return TPAlignOn(in, tool == TPDevToolAlignEquals ? @"=" : @":");
            } title:@"Lines"];
            break;
        }
        case TPDevToolEscapeRegex: {
            [self devToolsTransform:^NSString *(NSString *in, NSString **e) { return TPEscapeRegex(in); } title:@"Escape"];
            break;
        }
        // Convert
        case TPDevToolCsvToJson: {
            [self devToolsToNewTab:^NSString *(NSString *in, NSString **e) {
                if (!in.length) { *e = @"There is no CSV to convert."; return nil; }
                return @(tpp::csv::toJson(in.UTF8String, indent, eol).c_str());
            } title:@"CSV to JSON" language:@"json"];
            break;
        }
        case TPDevToolCsvToMarkdown: {
            [self devToolsToNewTab:^NSString *(NSString *in, NSString **e) {
                if (!in.length) { *e = @"There is no CSV to convert."; return nil; }
                return @(tpp::csv::toMarkdown(in.UTF8String, eol).c_str());
            } title:@"CSV to Markdown" language:[[TPUserLanguages shared] languageNamed:@"Markdown (preinstalled)"] ? @"udl:Markdown (preinstalled)" : @""];
            break;
        }
        case TPDevToolJsonToCsv: {
            [self devToolsToNewTab:^NSString *(NSString *in, NSString **e) {
                tpp::json::Result r = tpp::json::toCsv(in.UTF8String, eol);
                if (!r.ok) { *e = [NSString stringWithFormat:@"%s.", r.error.c_str()]; return nil; }
                return [[NSString alloc] initWithBytes:r.text.data() length:r.text.size() encoding:NSUTF8StringEncoding];
            } title:@"JSON to CSV" language:@""];
            break;
        }
        case TPDevToolTimestamp: {
            [self devToolsTransform:^NSString *(NSString *in, NSString **e) { return TPConvertTimestamp(in, e); } title:@"Unix Time / Date"];
            break;
        }
        case TPDevToolDecToHex:
        case TPDevToolHexToDec: {
            const BOOL toHex = tool == TPDevToolDecToHex;
            [self devToolsTransform:^NSString *(NSString *in, NSString **e) { return TPConvertNumbers(in, toHex); } title:@"Numbers"];
            break;
        }
        // Code Formatter
        case TPDevToolFormatAuto: {
            TPDocument *d = self.currentDocument;
            NSString *lang = d.languageId.lowercaseString ?: @"", *ext = (d.path ?: d.displayName).pathExtension.lowercaseString ?: @"";
            NSInteger t = -1;
            if ([lang isEqualToString:@"sql"] || [ext isEqualToString:@"sql"]) t = TPDevToolFormatSQL;
            else if ([lang isEqualToString:@"html"] || [@[@"html", @"htm", @"xhtml"] containsObject:ext]) t = TPDevToolFormatHTML;
            else if ([lang isEqualToString:@"css"] || [ext isEqualToString:@"css"]) t = TPDevToolFormatCSS;
            else if ([lang isEqualToString:@"json"] || [ext isEqualToString:@"json"]) { [self runJsonTool:0]; break; }
            else if ([lang isEqualToString:@"xml"] || [@[@"xml", @"svg", @"plist", @"xsd", @"xsl"] containsObject:ext]) t = TPDevToolXmlPretty;
            if (t < 0) { [self showMessage:@"Format Document" informative:@"Format Document works on SQL, HTML, CSS, JSON and XML files. Pick a language in the Language menu, or use one of the formatters in this menu."]; break; }
            [self runDevTool:t];
            break;
        }
        case TPDevToolFormatSQL:
        case TPDevToolFormatHTML:
        case TPDevToolFormatCSS:
        case TPDevToolMinifyCSS: {
            [self devToolsTransform:^NSString *(NSString *in, NSString **e) {
                const std::string u = in.UTF8String ?: "";
                std::string r = tool == TPDevToolFormatSQL ? tpp::format::sql(u, indent, eol) : tool == TPDevToolFormatHTML ? tpp::format::html(u, indent, eol)
                              : tool == TPDevToolFormatCSS ? tpp::format::css(u, indent, eol) : tpp::format::cssMinify(u);
                return [[NSString alloc] initWithBytes:r.data() length:r.size() encoding:NSUTF8StringEncoding];
            } title:@"Format"];
            TPDocument *d = self.currentDocument;
            NSString *lang = tool == TPDevToolFormatSQL ? @"sql" : tool == TPDevToolFormatHTML ? @"html" : @"css";
            if ([d.languageId isEqualToString:@"normal"] && SCI(self.editor, SCI_GETSELECTIONEMPTY)) [self setDocumentLanguage:d languageId:lang];
            break;
        }
        // Insert
        case TPDevToolInsertUUID: case TPDevToolInsertUnixTime: case TPDevToolInsertISODate: case TPDevToolInsertLorem: case TPDevToolInsertPassword: {
            [ws devToolsInsert:static_cast<TPInsertKind>(tool - TPDevToolInsertUUID)];
            break;
        }
    }
}

@end
