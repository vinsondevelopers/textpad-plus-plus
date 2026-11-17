// Textpad++ — thin helpers over the Scintilla message API (same API Notepad++ uses on Win32).
// GPL-3.0-or-later.
#pragma once

#import <Cocoa/Cocoa.h>
#import "ScintillaView.h"
#include "Scintilla.h"
#include "SciLexer.h"
#include "ILexer.h"
#include "Lexilla.h"

#include <string>

// Indicator / marker numbers shared with upstream (ScintillaEditView.h, stylers.model.xml styleIDs).
enum : int {
    TPP_MARK_BOOKMARK = 20,
    TPP_MARK_HIDELINESBEGIN = 19,
    TPP_MARK_HIDELINESEND = 18,
    TPP_INDIC_FOUND = 31,          // "Find Mark Style"   (SCE_UNIVERSAL_FOUND_STYLE)
    TPP_INDIC_FINDDLG = 30,        // live "Find what" highlight
    TPP_INDIC_SMART = 29,          // "Smart Highlighting"
    TPP_INDIC_INC = 28,            // "Find matches highlight all" (incremental search)
    TPP_INDIC_TAGMATCH = 27,
    TPP_INDIC_TAGATTR = 26,
    TPP_INDIC_EXT1 = 25,           // "Mark Style 1" .. "Mark Style 5" = 25..21
    TPP_INDIC_EXT5 = 21,
    TPP_MARGIN_LINENUMBER = 0,
    TPP_MARGIN_SYMBOL = 1,
    TPP_MARGIN_FOLDER = 2,
    TPP_MARGIN_CHANGEHISTORY = 3,
};

static inline sptr_t SCI(ScintillaView* v, unsigned int msg, uptr_t w = 0, sptr_t l = 0) {
    return [v message:msg wParam:w lParam:l];
}

static inline sptr_t SCIS(ScintillaView* v, unsigned int msg, uptr_t w, const char* s) {
    return [v message:msg wParam:w lParam:reinterpret_cast<sptr_t>(s)];
}

static inline std::string sciGetText(ScintillaView* v) {
    // SCI_GETCHARACTERPOINTER returns the contiguous buffer, embedded NULs included.
    sptr_t len = SCI(v, SCI_GETLENGTH);
    if (len <= 0) return {};
    const char* p = reinterpret_cast<const char*>(SCI(v, SCI_GETCHARACTERPOINTER));
    return p ? std::string(p, static_cast<size_t>(len)) : std::string();
}

static inline std::string sciGetRange(ScintillaView* v, sptr_t start, sptr_t end) {
    const sptr_t len = SCI(v, SCI_GETLENGTH);
    if (start < 0) start = 0;
    if (end > len) end = len;
    if (end <= start) return {};
    std::string s(static_cast<size_t>(end - start), '\0');
    const char* p = reinterpret_cast<const char*>(SCI(v, SCI_GETRANGEPOINTER, static_cast<uptr_t>(start), end - start));
    if (p) { s.assign(p, static_cast<size_t>(end - start)); return s; }
    Sci_TextRangeFull tr;
    tr.chrg.cpMin = start;
    tr.chrg.cpMax = end;
    std::string buf(static_cast<size_t>(end - start) + 1, '\0');
    tr.lpstrText = buf.data();
    SCI(v, SCI_GETTEXTRANGEFULL, 0, reinterpret_cast<sptr_t>(&tr));
    return std::string(buf.data(), static_cast<size_t>(end - start));
}

static inline std::string sciGetLine(ScintillaView* v, sptr_t line) {
    sptr_t s = SCI(v, SCI_POSITIONFROMLINE, static_cast<uptr_t>(line));
    sptr_t e = SCI(v, SCI_GETLINEENDPOSITION, static_cast<uptr_t>(line));
    return sciGetRange(v, s, e);
}

static inline std::string sciSelectedText(ScintillaView* v) {
    sptr_t s = SCI(v, SCI_GETSELECTIONSTART), e = SCI(v, SCI_GETSELECTIONEND);
    return sciGetRange(v, s, e);
}

static inline void sciReplaceRange(ScintillaView* v, sptr_t start, sptr_t end, const std::string& text) {
    SCI(v, SCI_SETTARGETRANGE, static_cast<uptr_t>(start), end);
    SCI(v, SCI_REPLACETARGET, text.size(), reinterpret_cast<sptr_t>(text.data()));
}

static inline std::string sciEolString(ScintillaView* v) {
    switch (SCI(v, SCI_GETEOLMODE)) {
        case SC_EOL_CRLF: return "\r\n";
        case SC_EOL_CR: return "\r";
        default: return "\n";
    }
}

static inline int rgbToSci(unsigned rgb) {  // 0xRRGGBB -> Scintilla 0xBBGGRR
    return static_cast<int>(((rgb & 0xFF) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 0xFF));
}

static inline NSString* NSStr(const std::string& s) {
    NSString* r = [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding];
    return r ?: @"";
}

static inline std::string StdStr(NSString* s) {
    if (!s) return {};
    const char* c = s.UTF8String;
    return c ? std::string(c) : std::string();
}
