// Textpad++ — CSV files: View > CSV Rainbow Columns gives every column its own colour (only the lines on screen
// are coloured, so very large files stay fast), Edit > CSV Columns > Align / Shrink pads the fields so the
// delimiters line up, or takes the padding off. GPL-3.0-or-later.
#import "app/CsvColumns.h"
#import "app/Document.h"
#import "app/Preferences.h"
#import "app/Sci.h"
#include "core/Csv.h"
#include <functional>

static NSTimer *g_csvTimer;
static size_t g_csvKey;
static __weak TPDocument *g_csvStyledDoc;

BOOL TPIsCsvPath(NSString *path) {
    return path && [@[@"csv", @"tsv", @"tab", @"psv", @"dsv"] containsObject:path.pathExtension.lowercaseString];
}

// eight colours that read well on light and on dark backgrounds (BGR for Scintilla)
static const int kRainbowLight[8] = {0x1F1FD0, 0x0F6FC0, 0x168E1E, 0xB06A00, 0xA0208C, 0x0090A8, 0x7A4E1E, 0x5A3AE0};
static const int kRainbowDark[8] = {0x6E6EFF, 0x4CB0FF, 0x6AD46A, 0xF0B050, 0xE07AD6, 0x30D0E8, 0xB49A7A, 0x9A80FF};

@implementation TPMainWindowController (CsvColumns)

- (BOOL)csvRainbowAppliesTo:(TPDocument *)d {
    return d && [TPPrefs b:@"pref.csvRainbow"] && TPIsCsvPath(d.path ?: d.displayName) && [d.languageId isEqualToString:@"normal"];
}

- (void)csvStartWatching {
    if (g_csvTimer) return;
    __weak TPMainWindowController *ws = self;
    g_csvTimer = [NSTimer scheduledTimerWithTimeInterval:0.15 repeats:YES block:^(NSTimer *t) { [ws csvRainbowTick]; }];
}

- (char)csvDelimiterOf:(ScintillaView *)v {
    const sptr_t end = SCI(v, SCI_GETLINEENDPOSITION, MIN((sptr_t)5, SCI(v, SCI_GETLINECOUNT) - 1));
    const std::string head = sciGetRange(v, 0, end);
    TPDocument *d = self.currentDocument;
    if ([[d.path ?: d.displayName pathExtension].lowercaseString isEqualToString:@"tsv"]) return '\t';
    return tpp::csv::detectDelimiter(head);
}

- (void)csvRainbowTick {
    TPDocument *d = self.currentDocument;
    ScintillaView *v = self.editor;
    if (!v) return;
    if (![self csvRainbowAppliesTo:d]) {
        if (g_csvStyledDoc && g_csvStyledDoc == d) {   // switched off: plain again
            SCI(v, SCI_STARTSTYLING, 0);
            SCI(v, SCI_SETSTYLING, SCI(v, SCI_GETLENGTH), 0);
            g_csvStyledDoc = nil;
        }
        return;
    }
    const sptr_t first = SCI(v, SCI_DOCLINEFROMVISIBLE, SCI(v, SCI_GETFIRSTVISIBLELINE));
    const sptr_t last = MIN(SCI(v, SCI_GETLINECOUNT) - 1, first + SCI(v, SCI_LINESONSCREEN) + 2);
    const sptr_t a = SCI(v, SCI_POSITIONFROMLINE, first), b = SCI(v, SCI_GETLINEENDPOSITION, last);
    const std::string visible = sciGetRange(v, a, b);
    const size_t key = std::hash<std::string>{}(visible) ^ (size_t)first * 1315423911u ^ (size_t)(__bridge void *)d ^ ([TPChrome dark] ? 7 : 0) ^ (size_t)SCI(v, SCI_STYLEGETFORE, 1) << 20;   // a theme reload resets the colours
    if (key == g_csvKey && g_csvStyledDoc == d) return;
    g_csvKey = key;
    g_csvStyledDoc = d;
    [self csvRainbowStyleLines:first to:last inView:v];
}

- (void)csvRainbowStyleLines:(sptr_t)first to:(sptr_t)last inView:(ScintillaView *)v {
    const int *pal = [TPChrome dark] ? kRainbowDark : kRainbowLight;
    for (int k = 0; k < 8; ++k) SCI(v, SCI_STYLESETFORE, 1 + k, pal[k]);
    const char delim = [self csvDelimiterOf:v];
    for (sptr_t line = first; line <= last; ++line) {
        const sptr_t ls = SCI(v, SCI_POSITIONFROMLINE, line), le = SCI(v, SCI_GETLINEENDPOSITION, line);
        if (le <= ls) continue;
        const std::string text = sciGetRange(v, ls, le);
        SCI(v, SCI_STARTSTYLING, ls);
        size_t at = 0, col = 0;
        for (const auto &f : tpp::csv::fieldsOfLine(text, delim)) {
            if (f.first > at) { SCI(v, SCI_SETSTYLING, f.first - at, 0); }   // the delimiter
            if (f.second > f.first) SCI(v, SCI_SETSTYLING, f.second - f.first, 1 + (col % 8));
            at = f.second;
            ++col;
        }
    }
}

- (void)csvReformat:(BOOL)alignColumns {
    ScintillaView *v = self.editor;
    if (!self.currentDocument || SCI(v, SCI_GETREADONLY)) { NSBeep(); return; }
    sptr_t a = SCI(v, SCI_GETSELECTIONSTART), b = SCI(v, SCI_GETSELECTIONEND);
    if (a == b) { a = 0; b = SCI(v, SCI_GETLENGTH); }
    else { a = SCI(v, SCI_POSITIONFROMLINE, SCI(v, SCI_LINEFROMPOSITION, a)); b = SCI(v, SCI_GETLINEENDPOSITION, SCI(v, SCI_LINEFROMPOSITION, b)); }
    const std::string in = sciGetRange(v, a, b);
    const char d = [self csvDelimiterOf:v];
    const std::string out = alignColumns ? tpp::csv::align(in, d) : tpp::csv::shrink(in, d);
    if (out == in) return;
    SCI(v, SCI_BEGINUNDOACTION);
    SCI(v, SCI_SETTARGETRANGE, a, b);
    SCI(v, SCI_REPLACETARGET, out.size(), reinterpret_cast<sptr_t>(out.data()));
    SCI(v, SCI_ENDUNDOACTION);
    g_csvKey = 0;
}

@end
