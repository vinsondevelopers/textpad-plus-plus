// Textpad++ — text transformation primitives. GPL-3.0-or-later.
// Portions ported from Notepad++ (C) Don Ho and Notepad++ contributors, GPL-3.0-or-later.
#include "core/TextOps.h"

#include <xlocale.h>
#include <wctype.h>
#include <algorithm>
#include <cstdlib>
#include <random>
#include <unordered_set>

namespace tpp::textops {

namespace {

locale_t utf8Locale() {
    static locale_t loc = [] {
        locale_t l = newlocale(LC_CTYPE_MASK, "en_US.UTF-8", nullptr);
        if (!l) l = newlocale(LC_CTYPE_MASK, "UTF-8", nullptr);
        return l;
    }();
    return loc;
}

std::u32string toU32(const std::string& s) {
    std::u32string out;
    out.reserve(s.size());
    size_t i = 0;
    while (i < s.size()) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        char32_t cp = 0xFFFD;
        int len = 1;
        if (c < 0x80) cp = c;
        else if ((c >> 5) == 6 && i + 1 < s.size()) { cp = ((c & 0x1F) << 6) | (s[i + 1] & 0x3F); len = 2; }
        else if ((c >> 4) == 14 && i + 2 < s.size()) { cp = ((c & 0x0F) << 12) | ((s[i + 1] & 0x3F) << 6) | (s[i + 2] & 0x3F); len = 3; }
        else if ((c >> 3) == 30 && i + 3 < s.size()) { cp = ((c & 0x07) << 18) | ((s[i + 1] & 0x3F) << 12) | ((s[i + 2] & 0x3F) << 6) | (s[i + 3] & 0x3F); len = 4; }
        else { cp = 0xDC00 | c; }  // lone byte: keep it recoverable (lone-surrogate marker)
        out.push_back(cp);
        i += static_cast<size_t>(len);
    }
    return out;
}

void putUtf8(std::string& out, char32_t cp) {
    if (cp >= 0xDC80 && cp <= 0xDCFF) { out.push_back(static_cast<char>(cp & 0xFF)); return; }  // restore raw byte
    if (cp < 0x80) out.push_back(static_cast<char>(cp));
    else if (cp < 0x800) { out.push_back(static_cast<char>(0xC0 | (cp >> 6))); out.push_back(static_cast<char>(0x80 | (cp & 0x3F))); }
    else if (cp < 0x10000) { out.push_back(static_cast<char>(0xE0 | (cp >> 12))); out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F))); out.push_back(static_cast<char>(0x80 | (cp & 0x3F))); }
    else { out.push_back(static_cast<char>(0xF0 | (cp >> 18))); out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F))); out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F))); out.push_back(static_cast<char>(0x80 | (cp & 0x3F))); }
}

std::string fromU32(const std::u32string& s) {
    std::string out;
    out.reserve(s.size());
    for (char32_t c : s) putUtf8(out, c);
    return out;
}

inline bool isAlpha(char32_t c) { return iswalpha_l(static_cast<wint_t>(c), utf8Locale()); }
inline bool isAlnum(char32_t c) { return iswalnum_l(static_cast<wint_t>(c), utf8Locale()); }
inline bool isLower(char32_t c) { return iswlower_l(static_cast<wint_t>(c), utf8Locale()); }
inline bool isSpace(char32_t c) { return iswspace_l(static_cast<wint_t>(c), utf8Locale()); }
inline char32_t up(char32_t c) { return static_cast<char32_t>(towupper_l(static_cast<wint_t>(c), utf8Locale())); }
inline char32_t lo(char32_t c) { return static_cast<char32_t>(towlower_l(static_cast<wint_t>(c), utf8Locale())); }
inline bool isSingleQuote(char32_t c) { return c == U'\'' || c == U'’' || c == U'‘'; }

} // namespace

std::u16string toU16(const std::string& utf8) {
    std::u16string out;
    out.reserve(utf8.size());
    for (char32_t cp : toU32(utf8)) {
        if (cp >= 0x10000) {
            cp -= 0x10000;
            out.push_back(static_cast<char16_t>(0xD800 + (cp >> 10)));
            out.push_back(static_cast<char16_t>(0xDC00 + (cp & 0x3FF)));
        } else {
            out.push_back(static_cast<char16_t>(cp));
        }
    }
    return out;
}

std::string fromU16(const std::u16string& u) {
    std::u32string s;
    s.reserve(u.size());
    for (size_t i = 0; i < u.size(); ++i) {
        char16_t c = u[i];
        if (c >= 0xD800 && c <= 0xDBFF && i + 1 < u.size() && u[i + 1] >= 0xDC00 && u[i + 1] <= 0xDFFF) {
            s.push_back(0x10000 + ((c - 0xD800) << 10) + (u[i + 1] - 0xDC00));
            ++i;
        } else {
            s.push_back(c);
        }
    }
    return fromU32(s);
}

size_t utf16Length(const std::string& utf8) {
    size_t n = 0;
    for (char32_t cp : toU32(utf8)) n += cp >= 0x10000 ? 2 : 1;
    return n;
}

std::string changeCase(const std::string& utf8, Case kase, unsigned seed) {
    std::u32string s = toU32(utf8);
    const size_t n = s.size();
    switch (kase) {
        case Case::Upper:
            for (auto& c : s) c = up(c);
            break;
        case Case::Lower:
            for (auto& c : s) c = lo(c);
            break;
        case Case::ProperForce:
        case Case::ProperBlend:
            for (size_t i = 0; i < n; ++i) {
                if (!isAlpha(s[i])) continue;
                if (i >= 2 && isSingleQuote(s[i - 1]) && isAlnum(s[i - 2])) {
                    if (kase == Case::ProperForce) s[i] = lo(s[i]);
                } else if (i < 1 || !isAlnum(s[i - 1])) {
                    s[i] = up(s[i]);
                } else if (kase == Case::ProperForce) {
                    s[i] = lo(s[i]);
                }
            }
            break;
        case Case::SentenceForce:
        case Case::SentenceBlend: {
            bool isNewSentence = true, wasEolR = false, wasEolN = false;
            for (size_t i = 0; i < n; ++i) {
                if (isAlpha(s[i])) {
                    if (isNewSentence) { s[i] = up(s[i]); isNewSentence = false; }
                    else if (kase == Case::SentenceForce) s[i] = lo(s[i]);
                    wasEolR = wasEolN = false;
                    if (s[i] == U'i' && (i >= 1 && (isSpace(s[i - 1]) || s[i - 1] == U'(' || s[i - 1] == U'"')) &&
                        (i + 1 < n && (isSpace(s[i + 1]) || s[i + 1] == U'\'')))
                        s[i] = U'I';
                } else if (s[i] == U'.' || s[i] == U'!' || s[i] == U'?') {
                    isNewSentence = !((i + 1 == n) ? true : isAlnum(s[i + 1]));
                } else if (s[i] == U'\r') {
                    if (wasEolR) isNewSentence = true; else wasEolR = true;
                } else if (s[i] == U'\n') {
                    if (wasEolN) isNewSentence = true; else wasEolN = true;
                }
            }
            break;
        }
        case Case::Invert:
            for (auto& c : s) c = isLower(c) ? up(c) : lo(c);
            break;
        case Case::Random: {
            std::mt19937 rng(seed ? seed : std::random_device{}());
            for (auto& c : s) if (isAlpha(c)) c = (rng() & 1) ? up(c) : lo(c);
            break;
        }
    }
    return fromU32(s);
}

// ---------------------------------------------------------------- sorting
namespace {

struct SortKeyer {
    size_t from, to;
    bool columns() const { return to != 0; }
    std::u16string key(const std::u16string& in) const {
        if (!columns()) return in;
        if (in.length() < from) return u"";
        if (from == to) return in.substr(from);
        return in.substr(from, to - from);
    }
};

int wcsicmp16(const std::u16string& a, const std::u16string& b) {
    // _wcsicmp: compare after lowercasing each code unit
    size_t n = std::min(a.size(), b.size());
    for (size_t i = 0; i < n; ++i) {
        char32_t ca = lo(a[i]), cb = lo(b[i]);
        if (ca != cb) return ca < cb ? -1 : 1;
    }
    if (a.size() == b.size()) return 0;
    return a.size() < b.size() ? -1 : 1;
}

bool isDigit16(char16_t c) { return c >= u'0' && c <= u'9'; }

long long integerCompare(const std::u16string& a, const std::u16string& b) {
    // Port of upstream IntegerSorter comparator (natural numeric ordering).
    long long compareResult = 0;
    size_t ai = 0, bi = 0;
    while (compareResult == 0) {
        if (ai >= a.length() || bi >= b.length()) {
            compareResult = a.compare(std::min(ai, a.length()), std::u16string::npos, b, std::min(bi, b.length()), std::u16string::npos);
            break;
        }
        bool aNum = isDigit16(a[ai]);
        bool bNum = isDigit16(b[bi]);
        int aSign = 1, bSign = 1;
        if (!aNum && ai + 1 < a.length()) { aNum = (a[ai] == u'-' && isDigit16(a[ai + 1])); aSign = -1; }
        if (!bNum && bi + 1 < b.length()) { bNum = (b[bi] == u'-' && isDigit16(b[bi + 1])); bSign = -1; }
        if (aNum != bNum) {
            compareResult = static_cast<long long>(a[ai]) - static_cast<long long>(b[bi]);
            ++ai; ++bi;
        } else if (aNum) {
            if (aSign != bSign) {
                compareResult = aSign == 1 ? 1 : -1;
            } else {
                if (aSign == -1) { ++ai; ++bi; }
                size_t aEnd = a.find_first_not_of(u"1234567890", ai); if (aEnd == std::u16string::npos) aEnd = a.length();
                size_t bEnd = b.find_first_not_of(u"1234567890", bi); if (bEnd == std::u16string::npos) bEnd = b.length();
                int aZero = 0, bZero = 0;
                while (ai < a.length() && a[ai] == u'0') { ++aZero; ++ai; }
                while (bi < b.length() && b[bi] == u'0') { ++bZero; ++bi; }
                size_t aLen = aEnd - ai, bLen = bEnd - bi;
                if (aLen > bLen) compareResult = 1 * aSign;
                else if (aLen < bLen) compareResult = -1 * aSign;
                else {
                    while (compareResult == 0 && ai < a.length() && isDigit16(a[ai]) && bi < b.length() && isDigit16(b[bi])) {
                        compareResult = (static_cast<long long>(a[ai]) - static_cast<long long>(b[bi])) * aSign;
                        ++ai; ++bi;
                    }
                    if (compareResult == 0) compareResult = bZero - aZero;
                }
            }
        } else {
            if (a[ai] == u'-') ++ai;
            if (b[bi] == u'-') ++bi;
            size_t aEnd = a.find_first_of(u"1234567890-", ai);
            size_t bEnd = b.find_first_of(u"1234567890-", bi);
            size_t aCount = aEnd == std::u16string::npos ? std::u16string::npos : aEnd - ai;
            size_t bCount = bEnd == std::u16string::npos ? std::u16string::npos : bEnd - bi;
            compareResult = a.compare(ai, aCount, b, bi, bCount);
            ai = aEnd; bi = bEnd;
        }
    }
    return compareResult;
}

std::u16string takeWhile(const std::u16string& in, const std::u16string& admissible) {
    size_t idx = in.find_first_not_of(admissible);
    return idx == std::u16string::npos ? in : in.substr(0, idx);
}

bool considerEmpty(const std::u16string& s) { return s.find_first_not_of(u" \t\r\n") == std::u16string::npos; }

bool parseDouble(const std::u16string& s, double& out) {
    std::string a;
    for (char16_t c : s) a.push_back(static_cast<char>(c));  // admissible set is ASCII only
    locale_t cloc = newlocale(LC_NUMERIC_MASK, "C", nullptr);
    char* end = nullptr;
    errno = 0;
    out = strtod_l(a.c_str(), &end, cloc);
    freelocale(cloc);
    if (end == a.c_str()) return false;
    if (errno == ERANGE) return false;
    return true;
}

} // namespace

SortResult sortLines(std::vector<std::string>& lines, SortMode mode, bool descending,
                     size_t fromColumn, size_t toColumn, unsigned seed) {
    SortResult result;
    if (mode == SortMode::Reverse) { std::reverse(lines.begin(), lines.end()); return result; }
    if (mode == SortMode::Random) {
        std::shuffle(lines.begin(), lines.end(), std::default_random_engine(seed ? seed : static_cast<unsigned>(time(nullptr))));
        return result;
    }
    SortKeyer k{fromColumn, toColumn};
    std::vector<std::u16string> w;
    w.reserve(lines.size());
    for (const auto& l : lines) w.push_back(toU16(l));
    std::vector<size_t> idx(lines.size());
    for (size_t i = 0; i < idx.size(); ++i) idx[i] = i;

    auto apply = [&](const std::vector<size_t>& order) {
        std::vector<std::string> out;
        out.reserve(order.size());
        for (size_t i : order) out.push_back(lines[i]);
        lines.swap(out);
    };

    switch (mode) {
        case SortMode::Lexicographic:
            std::stable_sort(idx.begin(), idx.end(), [&](size_t a, size_t b) {
                int c = k.key(w[a]).compare(k.key(w[b]));
                return descending ? c > 0 : c < 0;
            });
            break;
        case SortMode::LexicographicIgnoreCase:
            std::stable_sort(idx.begin(), idx.end(), [&](size_t a, size_t b) {
                int c = wcsicmp16(k.key(w[a]), k.key(w[b]));
                return descending ? c > 0 : c < 0;
            });
            break;
        case SortMode::Locale: {
            // Upstream uses CompareStringEx with the user locale; Textpad++ uses the
            // C library collation for the current user locale (see KNOWN_DIFFERENCES).
            locale_t loc = newlocale(LC_COLLATE_MASK, "", nullptr);
            std::vector<std::wstring> keys(lines.size());
            for (size_t i = 0; i < lines.size(); ++i) {
                std::u32string u = toU32(fromU16(k.key(w[i])));
                keys[i].assign(u.begin(), u.end());
            }
            std::stable_sort(idx.begin(), idx.end(), [&](size_t a, size_t b) {
                int c = wcscoll_l(keys[a].c_str(), keys[b].c_str(), loc ? loc : LC_GLOBAL_LOCALE);
                return descending ? c > 0 : c < 0;
            });
            if (loc) freelocale(loc);
            break;
        }
        case SortMode::Integer:
            std::stable_sort(idx.begin(), idx.end(), [&](size_t a, size_t b) {
                long long c = integerCompare(k.key(w[a]), k.key(w[b]));
                return descending ? c > 0 : c < 0;
            });
            break;
        case SortMode::Length:
            std::stable_sort(idx.begin(), idx.end(), [&](size_t a, size_t b) {
                size_t la = k.key(w[a]).length(), lb = k.key(w[b]).length();
                return descending ? la > lb : la < lb;
            });
            break;
        case SortMode::DecimalComma:
        case SortMode::DecimalDot: {
            std::vector<std::pair<size_t, double>> nums;
            std::vector<size_t> empties;
            for (size_t i = 0; i < w.size(); ++i) {
                std::u16string p = mode == SortMode::DecimalComma ? takeWhile(k.key(w[i]), u" \t\r\n0123456789,-")
                                                                   : takeWhile(k.key(w[i]), u" \t\r\n0123456789.-");
                if (mode == SortMode::DecimalComma) std::replace(p.begin(), p.end(), u',', u'.');
                if (considerEmpty(p)) { empties.push_back(i); continue; }
                double d = 0;
                if (!parseDouble(p, d)) { result.ok = false; result.failedLineIndex = i; return result; }
                nums.emplace_back(i, d);
            }
            std::stable_sort(nums.begin(), nums.end(), [&](const auto& a, const auto& b) {
                return descending ? a.second > b.second : a.second < b.second;
            });
            std::vector<size_t> order;
            if (!descending) order.insert(order.end(), empties.begin(), empties.end());
            for (auto& p : nums) order.push_back(p.first);
            if (descending) order.insert(order.end(), empties.begin(), empties.end());
            idx = order;
            break;
        }
        default:
            break;
    }
    apply(idx);
    return result;
}

void removeDuplicateLines(std::vector<std::string>& lines) {
    std::unordered_set<std::string> seen;
    std::vector<std::string> out;
    out.reserve(lines.size());
    for (auto& l : lines) if (seen.insert(l).second) out.push_back(l);
    lines.swap(out);
}

void removeConsecutiveDuplicateLines(std::vector<std::string>& lines) {
    std::vector<std::string> out;
    out.reserve(lines.size());
    for (auto& l : lines) if (out.empty() || out.back() != l) out.push_back(l);
    lines.swap(out);
}

void removeEmptyLines(std::vector<std::string>& lines, bool alsoBlank) {
    std::vector<std::string> out;
    out.reserve(lines.size());
    for (auto& l : lines) {
        bool empty = alsoBlank ? l.find_first_not_of(" \t") == std::string::npos : l.empty();
        if (!empty) out.push_back(l);
    }
    lines.swap(out);
}

std::string trimTrailing(const std::string& line) {
    size_t e = line.find_last_not_of(" \t");
    return e == std::string::npos ? std::string() : line.substr(0, e + 1);
}

std::string trimLeading(const std::string& line) {
    size_t s = line.find_first_not_of(" \t");
    return s == std::string::npos ? std::string() : line.substr(s);
}

std::string tabsToSpaces(const std::string& line, int tabWidth) {
    // Port of the tab2Space branch of Notepad_plus::wsTabConvert (per line, UTF-8 aware).
    if (tabWidth <= 0) tabWidth = 4;
    std::string out;
    out.reserve(line.size() + 8);
    long column = 0;
    for (unsigned char c : line) {
        if (c == '\t') {
            long insert = tabWidth - (column % tabWidth);
            out.append(static_cast<size_t>(insert), ' ');
            column += insert;
        } else {
            out.push_back(static_cast<char>(c));
            if (c == '\n' || c == '\r') column = 0;
            else if ((c & 0xC0) != 0x80) ++column;
        }
    }
    return out;
}

std::string spacesToTabs(const std::string& line, int tabWidth, bool onlyLeading) {
    // Port of the space2TabAll / space2TabLeading branch of Notepad_plus::wsTabConvert.
    if (tabWidth <= 0) tabWidth = 4;
    std::string src = line;
    src.push_back('\0');  // upstream works on a NUL-terminated buffer
    std::string dest;
    dest.reserve(line.size());
    long column = 0;
    long tabStop = tabWidth - 1;
    bool nextChar = false;
    long counter = 0;
    bool nonSpaceFound = false;
    for (size_t i = 0; src[i] != '\0'; ++i) {
        if (!nonSpaceFound) {
            while (src[i + counter] == ' ') {
                if ((column + counter) == tabStop) {
                    tabStop += tabWidth;
                    if (counter >= 1) {
                        dest.push_back('\t');
                        i += counter;
                        column += counter + 1;
                        counter = 0;
                        nextChar = true;
                        break;
                    } else if (src[i + 1] == ' ' || src[i + 1] == '\t') {
                        dest.push_back('\t');
                        i++;
                        column += 1;
                        counter = 0;
                    } else {
                        dest.push_back(src[i]);
                        column += 1;
                        counter = 0;
                        nextChar = true;
                        break;
                    }
                } else {
                    ++counter;
                }
            }
            if (nextChar) { nextChar = false; continue; }
            if (src[i] == ' ' && src[i + counter] == '\t') {
                dest.push_back('\t');
                i += counter;
                column = tabStop + 1;
                tabStop += tabWidth;
                counter = 0;
                continue;
            }
        }
        if (onlyLeading && !nonSpaceFound) nonSpaceFound = true;
        const unsigned char c = static_cast<unsigned char>(src[i]);
        if (c == '\n' || c == '\r') {
            dest.push_back(src[i]);
            column = 0;
            tabStop = tabWidth - 1;
            nonSpaceFound = false;
        } else if (c == '\t') {
            dest.push_back(src[i]);
            column = tabStop + 1;
            tabStop += tabWidth;
            counter = 0;
        } else {
            dest.push_back(src[i]);
            counter = 0;
            if ((c & 0xC0) != 0x80) {
                ++column;
                if (column > 0 && column % tabWidth == 0) tabStop += tabWidth;
            }
        }
    }
    return dest;
}

std::vector<std::string> splitLines(const std::string& text, bool* endsWithEol) {
    std::vector<std::string> lines;
    size_t start = 0;
    size_t i = 0;
    bool trailing = false;
    while (i < text.size()) {
        char c = text[i];
        if (c == '\r' || c == '\n') {
            lines.emplace_back(text, start, i - start);
            if (c == '\r' && i + 1 < text.size() && text[i + 1] == '\n') ++i;
            ++i;
            start = i;
            trailing = (i == text.size());
            continue;
        }
        ++i;
    }
    if (start < text.size() || (!trailing && start == text.size()))
        lines.emplace_back(text, start, text.size() - start);
    if (endsWithEol) *endsWithEol = trailing;
    return lines;
}

std::string joinLines(const std::vector<std::string>& lines, const std::string& eol) {
    std::string out;
    size_t total = 0;
    for (auto& l : lines) total += l.size() + eol.size();
    out.reserve(total);
    for (size_t i = 0; i < lines.size(); ++i) {
        if (i) out += eol;
        out += lines[i];
    }
    return out;
}

std::optional<std::string> convertExtended(const std::string& in) {
    // Port of FindReplaceDlg::Searching::convertExtendedToString.
    std::string out;
    out.reserve(in.size());
    auto hexVal = [](char c) -> int {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return -1;
    };
    size_t i = 0;
    while (i < in.size()) {
        if (in[i] != '\\' || i + 1 >= in.size()) { out.push_back(in[i++]); continue; }
        char e = in[i + 1];
        i += 2;
        auto readNum = [&](int base, int digits, unsigned long& v) -> bool {
            if (i + static_cast<size_t>(digits) > in.size()) return false;
            v = 0;
            for (int d = 0; d < digits; ++d) {
                char c = in[i + d];
                int x;
                if (base == 16) x = hexVal(c);
                else if (c >= '0' && c < '0' + base) x = c - '0';
                else x = -1;
                if (x < 0) return false;
                v = v * base + static_cast<unsigned long>(x);
            }
            i += digits;
            return true;
        };
        unsigned long v = 0;
        switch (e) {
            case 'r': out.push_back('\r'); break;
            case 'n': out.push_back('\n'); break;
            case '0': out.push_back('\0'); break;
            case 't': out.push_back('\t'); break;
            case '\\': out.push_back('\\'); break;
            case 'b': if (!readNum(2, 8, v)) return std::nullopt; out.push_back(static_cast<char>(v)); break;
            case 'd': if (!readNum(10, 3, v) || v > 255) return std::nullopt; out.push_back(static_cast<char>(v)); break;
            case 'o': if (!readNum(8, 3, v) || v > 255) return std::nullopt; out.push_back(static_cast<char>(v)); break;
            case 'x': if (!readNum(16, 2, v)) return std::nullopt; out.push_back(static_cast<char>(v)); break;
            case 'u': {
                if (!readNum(16, 4, v)) return std::nullopt;
                putUtf8(out, static_cast<char32_t>(v));
                break;
            }
            default:
                // Upstream keeps unknown escapes literally ("\" followed by the char).
                out.push_back('\\');
                out.push_back(e);
                break;
        }
    }
    return out;
}

} // namespace tpp::textops
