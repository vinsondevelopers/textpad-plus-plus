// Textpad++ — matching tags highlighting for HTML / XML / PHP / ASP / JSP (port of upstream
// ScintillaComponent/xmlMatchedTagsHighlighter.cpp). GPL-3.0-or-later.
#pragma once
#import "app/Sci.h"
#include <string>
#include <utility>
#include <vector>

namespace tpp::tagmatch {

struct FindResult { sptr_t start = 0, end = 0; bool success = false; };
struct TagsPos { sptr_t tagOpenStart = -1, tagNameEnd = -1, tagOpenEnd = -1, tagCloseStart = -1, tagCloseEnd = -1; };

class Highlighter {
public:
    Highlighter(ScintillaView *v, bool matchCase) : _v(v), _matchCase(matchCase) {}

    // upstream tagMatch(doHiliteAttr); returns YES when a tag pair was highlighted
    bool tagMatch(bool hiliteAttr, bool isPhpAspJsp, const char *codeBegin, const char *codeEnd, bool indentGuides) {
        clear(TPP_INDIC_TAGMATCH);
        clear(TPP_INDIC_TAGATTR);
        if (isPhpAspJsp) {
            const sptr_t caret = 1 + SCI(_v, SCI_GETCURRENTPOS);
            FindResult s = findText(codeBegin, caret, 0), e = findText(codeEnd, caret, 0);
            if (s.success && (!e.success || e.start <= s.end)) return false;   // inside a code zone
        }
        const sptr_t ts = SCI(_v, SCI_GETTARGETSTART), te = SCI(_v, SCI_GETTARGETEND), fl = SCI(_v, SCI_GETSEARCHFLAGS);
        TagsPos t;
        bool found = getMatchedTagsPos(t);
        if (found) {
            SCI(_v, SCI_SETINDICATORCURRENT, TPP_INDIC_TAGMATCH);
            sptr_t tailLen = 2;
            if (t.tagCloseStart != -1 && t.tagCloseEnd != -1) {
                SCI(_v, SCI_INDICATORFILLRANGE, t.tagCloseStart, t.tagCloseEnd - t.tagCloseStart);
                tailLen = 1;
            }
            SCI(_v, SCI_INDICATORFILLRANGE, t.tagOpenStart, t.tagNameEnd - t.tagOpenStart);
            SCI(_v, SCI_INDICATORFILLRANGE, t.tagOpenEnd - tailLen, tailLen);
            if (hiliteAttr) {
                SCI(_v, SCI_SETINDICATORCURRENT, TPP_INDIC_TAGATTR);
                for (auto &a : attributesPos(t.tagNameEnd, t.tagOpenEnd - tailLen)) SCI(_v, SCI_INDICATORFILLRANGE, a.first, a.second - a.first);
            }
            if (indentGuides && t.tagCloseStart != -1) {
                sptr_t c1 = SCI(_v, SCI_GETCOLUMN, t.tagOpenStart), c2 = SCI(_v, SCI_GETCOLUMN, t.tagCloseStart);
                if (SCI(_v, SCI_LINEFROMPOSITION, t.tagOpenStart) != SCI(_v, SCI_LINEFROMPOSITION, t.tagCloseStart)) {
                    SCI(_v, SCI_BRACEHIGHLIGHT, t.tagOpenStart, t.tagCloseEnd - 1);
                    SCI(_v, SCI_SETHIGHLIGHTGUIDE, MIN(c1, c2));
                }
            }
        }
        SCI(_v, SCI_SETTARGETRANGE, ts, te);
        SCI(_v, SCI_SETSEARCHFLAGS, fl);
        return found;
    }

private:
    ScintillaView *_v;
    bool _matchCase;

    void clear(int indic) { SCI(_v, SCI_SETINDICATORCURRENT, indic); SCI(_v, SCI_INDICATORCLEARRANGE, 0, SCI(_v, SCI_GETLENGTH)); }
    static bool isWhitespace(sptr_t c) { return c == ' ' || c == '\t' || c == '\r' || c == '\n'; }
    sptr_t charAt(sptr_t p) { return SCI(_v, SCI_GETCHARAT, p); }
    sptr_t styleAt(sptr_t p) { return SCI(_v, SCI_GETSTYLEAT, p); }
    bool quotedOrComment(sptr_t s) { return s == SCE_H_DOUBLESTRING || s == SCE_H_SINGLESTRING || s == SCE_H_COMMENT; }

    FindResult findText(const char *text, sptr_t start, sptr_t end, int flags = 0) {
        Sci_TextToFindFull f{};
        f.lpstrText = text;
        f.chrg.cpMin = start;
        f.chrg.cpMax = end;
        if (_matchCase) flags |= SCFIND_MATCHCASE;
        FindResult r;
        if (SCI(_v, SCI_FINDTEXTFULL, static_cast<uptr_t>(flags), reinterpret_cast<sptr_t>(&f)) != -1) {
            r.success = true;
            r.start = f.chrgText.cpMin;
            r.end = f.chrgText.cpMax;
        }
        return r;
    }

    std::vector<std::pair<sptr_t, sptr_t>> attributesPos(sptr_t start, sptr_t end) {
        std::vector<std::pair<sptr_t, sptr_t>> attrs;
        std::string buf = sciGetRange(_v, start, end + 1);
        enum { invalid, key, preAssign, assign, string, singleQuotString, value, valid } state = invalid;
        int startPos = -1, oneMoreChar = 1, i = 0;
        const int bufLen = static_cast<int>(buf.size());
        for (; i < bufLen; ++i) {
            switch (buf[static_cast<size_t>(i)]) {
                case ' ': case '\t': case '\n': case '\r':
                    if (state == key) state = preAssign;
                    else if (state == value) { state = valid; oneMoreChar = 0; }
                    break;
                case '=':
                    if (state == key || state == preAssign) state = assign;
                    else if (state == assign || state == value) state = invalid;
                    break;
                case '"':
                    if (state == string) { state = valid; oneMoreChar = 1; }
                    else if (state == key || state == preAssign || state == value) state = invalid;
                    else if (state == assign) state = string;
                    break;
                case '\'':
                    if (state == singleQuotString) { state = valid; oneMoreChar = 1; }
                    else if (state == key || state == preAssign || state == value) state = invalid;
                    else if (state == assign) state = singleQuotString;
                    break;
                default:
                    if (state == invalid) { state = key; startPos = i; }
                    else if (state == preAssign) state = invalid;
                    else if (state == assign) state = value;
            }
            if (state == valid) { attrs.emplace_back(start + startPos, start + i + oneMoreChar); state = invalid; }
        }
        if (state == value) attrs.emplace_back(start + startPos, start + i - 1);
        return attrs;
    }

    sptr_t findCloseAngle(sptr_t a, sptr_t b) {
        if (a > b) std::swap(a, b);
        FindResult r;
        do {
            r = findText(">", a, b);
            if (r.success) {
                if (!quotedOrComment(styleAt(r.start))) return r.start;
                a = r.end;
            }
        } while (r.success);
        return -1;
    }

    FindResult findOpenTag(const std::string &name, sptr_t start, sptr_t end) {
        std::string search = "<" + name;
        FindResult found, r;
        sptr_t s = start;
        const bool forward = start < end;
        do {
            r = findText(search.c_str(), s, end);
            if (r.success) {
                sptr_t next = charAt(r.end), st = styleAt(r.start);
                if (st != SCE_H_CDATA && !quotedOrComment(st)) {
                    if (next == '>') { found.end = r.end; found.success = true; }
                    else if (isWhitespace(next)) {
                        sptr_t ca = findCloseAngle(r.end, forward ? end : start);
                        if (ca != -1 && charAt(ca - 1) != '/') { found.end = ca; found.success = true; }
                    }
                }
            }
            s = forward ? r.end + 1 : r.start - 1;
        } while (r.success && !found.success);
        found.start = r.start;
        return found;
    }

    FindResult findCloseTag(const std::string &name, sptr_t start, sptr_t end) {
        std::string search = "</" + name;
        FindResult found, r;
        sptr_t s = start;
        const bool forward = start < end;
        bool valid;
        do {
            valid = false;
            r = findText(search.c_str(), s, end);
            if (r.success) {
                sptr_t next = charAt(r.end), st = styleAt(r.start);
                s = forward ? r.end + 1 : r.start - 1;
                if (st != SCE_H_CDATA && !quotedOrComment(st)) {
                    if (next == '>') { valid = true; found.start = r.start; found.end = r.end; found.success = true; }
                    else if (isWhitespace(next)) {
                        sptr_t w = r.end;
                        do { ++w; next = charAt(w); } while (isWhitespace(next));
                        if (next == '>') { valid = true; found.start = r.start; found.end = w; found.success = true; }
                    }
                }
            }
        } while (r.success && !valid);
        return found;
    }

    std::string tagNameFrom(sptr_t position) {
        std::string name;
        const sptr_t len = SCI(_v, SCI_GETLENGTH);
        sptr_t c = charAt(position);
        while (position < len && !isWhitespace(c) && c != '/' && c != '>' && c != '"' && c != '\'') {
            name.push_back(static_cast<char>(c));
            c = charAt(++position);
        }
        return name;
    }

    bool getMatchedTagsPos(TagsPos &t) {
        bool tagFound = false;
        const sptr_t caret = SCI(_v, SCI_GETCURRENTPOS), docLength = SCI(_v, SCI_GETLENGTH);
        sptr_t sp = caret, st;
        FindResult openFound;
        do {
            openFound = findText("<", sp, 0);
            st = styleAt(openFound.start);
            sp = openFound.start - 1;
        } while (openFound.success && quotedOrComment(st) && sp > 0);
        if (!openFound.success || st == SCE_H_CDATA) return false;
        FindResult closeFound;
        sp = openFound.start;
        do {
            closeFound = findText(">", sp, caret);
            st = styleAt(closeFound.start);
            sp = closeFound.end;
        } while (closeFound.success && quotedOrComment(st) && sp <= caret);
        if (closeFound.success) return false;   // the caret is not inside a tag
        if (charAt(openFound.start + 1) == '/') {
            t.tagCloseStart = openFound.start;
            FindResult endClose = findText(">", caret, docLength);
            if (endClose.success) t.tagCloseEnd = endClose.end;
            std::string name = tagNameFrom(openFound.start + 2);
            if (name.empty()) return false;
            sptr_t currentEnd = t.tagCloseStart, openRemaining = 1;
            FindResult nextOpen;
            do {
                nextOpen = findOpenTag(name, currentEnd, 0);
                if (nextOpen.success) {
                    --openRemaining;
                    sptr_t cs = nextOpen.end, closesFound = 0;
                    const bool fwd = cs < currentEnd;
                    FindResult between;
                    do {
                        between = findCloseTag(name, cs, currentEnd);
                        if (between.success) { ++closesFound; cs = fwd ? between.end : between.start - 1; }
                    } while (between.success);
                    if (closesFound == 0 && openRemaining == 0) {
                        t.tagOpenStart = nextOpen.start;
                        t.tagOpenEnd = nextOpen.end + 1;
                        t.tagNameEnd = nextOpen.start + static_cast<sptr_t>(name.size()) + 1;
                        tagFound = true;
                    } else {
                        openRemaining += closesFound;
                        currentEnd = nextOpen.start;
                    }
                }
            } while (!tagFound && openRemaining > 0 && nextOpen.success);
        } else {
            t.tagOpenStart = openFound.start;
            std::string name = tagNameFrom(openFound.start + 1);
            if (name.empty()) return false;
            t.tagNameEnd = openFound.start + static_cast<sptr_t>(name.size()) + 1;
            sptr_t ca = findCloseAngle(openFound.start + 1 + static_cast<sptr_t>(name.size()), docLength);
            if (ca == -1) return false;
            t.tagOpenEnd = ca + 1;
            if (charAt(ca - 1) == '/') { t.tagCloseStart = t.tagCloseEnd = -1; return true; }   // self-closed
            sptr_t cs = t.tagOpenEnd, closeRemaining = 1;
            FindResult nextClose;
            do {
                nextClose = findCloseTag(name, cs, docLength);
                if (nextClose.success) {
                    --closeRemaining;
                    sptr_t ce = nextClose.start, opensFound = 0;
                    FindResult between;
                    do {
                        between = findOpenTag(name, cs, ce);
                        if (between.success) { ++opensFound; cs = between.end; }
                    } while (between.success);
                    if (opensFound == 0 && closeRemaining == 0) {
                        t.tagCloseStart = nextClose.start;
                        t.tagCloseEnd = nextClose.end + 1;
                        tagFound = true;
                    } else {
                        closeRemaining += opensFound;
                        cs = nextClose.end;
                    }
                }
            } while (!tagFound && closeRemaining > 0 && nextClose.success);
        }
        return tagFound;
    }
};

}  // namespace tpp::tagmatch
