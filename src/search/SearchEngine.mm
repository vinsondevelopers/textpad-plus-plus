// Textpad++ — search engine. GPL-3.0-or-later.
// Portions ported from Notepad++ FindReplaceDlg.cpp (C) Don Ho and contributors, GPL-3.0-or-later.
#import "search/SearchEngine.h"
#include "core/TextOps.h"

namespace tpp::search {

Prepared prepare(const Options& o) {
    Prepared p;
    p.find = o.find;
    p.replace = o.replace;
    if (o.mode == Mode::Extended) {
        auto f = tpp::textops::convertExtended(o.find);
        auto r = tpp::textops::convertExtended(o.replace);
        if (!f || !r) { p.ok = false; p.error = "Invalid extended escape sequence"; return p; }
        p.find = *f;
        p.replace = *r;
    }
    // upstream Searching::buildSearchFlags
    p.flags = (o.wholeWord && o.mode != Mode::Regex ? SCFIND_WHOLEWORD : 0) |
              (o.matchCase ? SCFIND_MATCHCASE : 0) |
              (o.mode == Mode::Regex ? SCFIND_REGEXP | SCFIND_POSIX : 0) |
              ((o.mode == Mode::Regex && o.dotMatchesNewline) ? SCFIND_REGEXP_DOTMATCHESNL : 0);
    if (p.find.empty()) { p.ok = false; p.error = ""; }
    return p;
}

std::string regexErrorMessage(ScintillaView* v) {
    char buf[1024] = {0};
    SCI(v, SCI_GETBOOSTREGEXERRMSG, sizeof(buf) - 1, reinterpret_cast<sptr_t>(buf));
    return buf[0] ? std::string(buf) : std::string("Invalid regular expression");
}

static sptr_t searchInTarget(ScintillaView* v, const std::string& text, sptr_t start, sptr_t end) {
    SCI(v, SCI_SETTARGETRANGE, static_cast<uptr_t>(start), end);
    return SCI(v, SCI_SEARCHINTARGET, text.size(), reinterpret_cast<sptr_t>(text.data()));
}

FindResult findNext(ScintillaView* v, const Options& o, NextType type, bool select) {
    FindResult r;
    Prepared p = prepare(o);
    if (!p.ok) { r.error = p.error; return r; }
    const sptr_t docLen = SCI(v, SCI_GETLENGTH);
    sptr_t selStart = SCI(v, SCI_GETSELECTIONSTART), selEnd = SCI(v, SCI_GETSELECTIONEND);
    sptr_t start, end;
    if (!o.backward) { start = type == NextType::FindNextForReplace ? selStart : selEnd; end = docLen; }
    else { start = selStart; end = 0; }
    int flags = p.flags;
    switch (type) {
        case NextType::FindNext: flags |= SCFIND_REGEXP_EMPTYMATCH_ALL | SCFIND_REGEXP_SKIPCRLFASONE; break;
        case NextType::ReplaceNext: flags |= SCFIND_REGEXP_EMPTYMATCH_NOTAFTERMATCH | SCFIND_REGEXP_SKIPCRLFASONE; break;
        case NextType::FindNextForReplace: flags |= SCFIND_REGEXP_EMPTYMATCH_ALL | SCFIND_REGEXP_EMPTYMATCH_ALLOWATSTART | SCFIND_REGEXP_SKIPCRLFASONE; break;
    }
    if (SCI(v, SCI_GETCHARAT, start - 1) == '\r' && SCI(v, SCI_GETCHARAT, start) == '\n')
        flags = (flags & ~SCFIND_REGEXP_EMPTYMATCH_MASK) | SCFIND_REGEXP_EMPTYMATCH_NONE;
    SCI(v, SCI_SETSEARCHFLAGS, flags);
    sptr_t pos = searchInTarget(v, p.find, start, end);
    if (pos == -2) { r.regexError = true; r.error = regexErrorMessage(v); return r; }
    if (pos == -1 && o.wrap) {
        if (!o.backward) { start = 0; end = docLen; }
        else { start = docLen; end = 0; }
        pos = searchInTarget(v, p.find, start, end);
        if (pos == -2) { r.regexError = true; r.error = regexErrorMessage(v); return r; }
        r.wrapped = pos >= 0;
    }
    if (pos < 0) return r;
    r.found = true;
    r.start = SCI(v, SCI_GETTARGETSTART);
    r.end = SCI(v, SCI_GETTARGETEND);
    if (select) {
        sptr_t line = SCI(v, SCI_LINEFROMPOSITION, r.start);
        SCI(v, SCI_ENSUREVISIBLE, line);
        SCI(v, SCI_SETSEL, r.start, r.end);
        SCI(v, SCI_SCROLLRANGE, r.start, r.end);
    }
    return r;
}

bool findAll(ScintillaView* v, const Options& o, sptr_t from, sptr_t to, std::vector<Match>& out, std::string* error) {
    Prepared p = prepare(o);
    if (!p.ok) { if (error) *error = p.error; return p.error.empty(); }
    if (to < 0) to = SCI(v, SCI_GETLENGTH);
    int flags = p.flags | SCFIND_REGEXP_EMPTYMATCH_NOTAFTERMATCH | SCFIND_REGEXP_SKIPCRLFASONE;
    SCI(v, SCI_SETSEARCHFLAGS, flags);
    sptr_t start = from;
    sptr_t lastEnd = -1;
    while (start <= to) {
        sptr_t pos = searchInTarget(v, p.find, start, to);
        if (pos == -2) { if (error) *error = regexErrorMessage(v); return false; }
        if (pos < 0) break;
        sptr_t ts = SCI(v, SCI_GETTARGETSTART), te = SCI(v, SCI_GETTARGETEND);
        if (!(ts == te && ts == lastEnd)) {
            out.push_back({ts, te, SCI(v, SCI_LINEFROMPOSITION, ts)});
        }
        lastEnd = te;
        if (te == ts) {
            if (te >= to) break;
            start = SCI(v, SCI_POSITIONAFTER, te);
        } else {
            start = te;
        }
        if (out.size() > 5000000) break;
    }
    return true;
}

long replaceAll(ScintillaView* v, const Options& o, sptr_t from, sptr_t to, std::string* error) {
    Prepared p = prepare(o);
    if (!p.ok) { if (error) *error = p.error; return 0; }
    if (to < 0) to = SCI(v, SCI_GETLENGTH);
    const bool regex = o.mode == Mode::Regex;
    int flags = p.flags | SCFIND_REGEXP_EMPTYMATCH_NOTAFTERMATCH | SCFIND_REGEXP_SKIPCRLFASONE;
    SCI(v, SCI_SETSEARCHFLAGS, flags);
    long count = 0;
    sptr_t start = from;
    sptr_t end = to;
    sptr_t lastReplacedEnd = -1;
    SCI(v, SCI_BEGINUNDOACTION);
    while (start <= end) {
        sptr_t pos = searchInTarget(v, p.find, start, end);
        if (pos == -2) { if (error) *error = regexErrorMessage(v); SCI(v, SCI_ENDUNDOACTION); return -1; }
        if (pos < 0) break;
        sptr_t ts = SCI(v, SCI_GETTARGETSTART), te = SCI(v, SCI_GETTARGETEND);
        if (ts == te && ts == lastReplacedEnd) {  // empty match right after previous match: skip one char
            if (ts >= end) break;
            start = SCI(v, SCI_POSITIONAFTER, ts);
            continue;
        }
        sptr_t foundLen = te - ts;
        sptr_t replacedLen = regex ? SCI(v, SCI_REPLACETARGETRE, p.replace.size(), reinterpret_cast<sptr_t>(p.replace.data()))
                                   : SCI(v, SCI_REPLACETARGET, p.replace.size(), reinterpret_cast<sptr_t>(p.replace.data()));
        ++count;
        end += replacedLen - foundLen;
        start = ts + replacedLen;
        lastReplacedEnd = start;
        if (foundLen == 0) {
            if (start >= end) break;
            start = SCI(v, SCI_POSITIONAFTER, start);
        }
    }
    SCI(v, SCI_ENDUNDOACTION);
    return count;
}

ReplaceResult replaceOne(ScintillaView* v, const Options& o) {
    ReplaceResult rr;
    Prepared p = prepare(o);
    if (!p.ok) { rr.next.error = p.error; return rr; }
    // Is the current selection a match? (upstream: FINDNEXTTYPE_FINDNEXTFORREPLACE from selection start)
    sptr_t selStart = SCI(v, SCI_GETSELECTIONSTART), selEnd = SCI(v, SCI_GETSELECTIONEND);
    Options fwd = o;
    fwd.backward = false;
    fwd.wrap = false;
    SCI(v, SCI_SETSEL, selStart, selStart);
    FindResult f = findNext(v, fwd, NextType::FindNextForReplace, false);
    if (f.regexError) { rr.next = f; SCI(v, SCI_SETSEL, selStart, selEnd); return rr; }
    if (f.found && f.start == selStart && f.end == selEnd) {
        SCI(v, SCI_SETTARGETRANGE, f.start, f.end);
        sptr_t len = o.mode == Mode::Regex ? SCI(v, SCI_REPLACETARGETRE, p.replace.size(), reinterpret_cast<sptr_t>(p.replace.data()))
                                            : SCI(v, SCI_REPLACETARGET, p.replace.size(), reinterpret_cast<sptr_t>(p.replace.data()));
        rr.replaced = true;
        sptr_t after = f.start + len;
        SCI(v, SCI_SETSEL, o.backward ? f.start : after, o.backward ? f.start : after);
    } else {
        SCI(v, SCI_SETSEL, selStart, selEnd);
    }
    rr.next = findNext(v, o, rr.replaced ? NextType::ReplaceNext : NextType::FindNext, true);
    return rr;
}

long markAll(ScintillaView* v, const Options& o, int indicator, sptr_t from, sptr_t to, std::string* error) {
    std::vector<Match> m;
    if (!findAll(v, o, from, to, m, error)) return -1;
    SCI(v, SCI_SETINDICATORCURRENT, indicator);
    for (const Match& x : m) {
        if (x.end > x.start) SCI(v, SCI_INDICATORFILLRANGE, x.start, x.end - x.start);
        if (o.bookmarkLine) SCI(v, SCI_MARKERADD, x.line, TPP_MARK_BOOKMARK);
    }
    return static_cast<long>(m.size());
}

} // namespace tpp::search
