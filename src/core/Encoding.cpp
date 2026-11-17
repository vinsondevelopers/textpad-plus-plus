// Textpad++ — encoding and line-ending services. GPL-3.0-or-later.
#include "core/Encoding.h"
#include "uchardet.h"

#include <iconv.h>
#include <cerrno>
#include <cstring>
#include <mutex>
#include <sstream>
#include <cctype>

namespace tpp {

namespace {

// Windows-1252 with the five undefined bytes mapped to the matching C1 controls,
// exactly as Windows MultiByteToWideChar does. This makes ANSI decoding bijective.
const char16_t kCp1252High[32] = {
    0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
    0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
};

// OEM 720 (Arabic, "Transparent ASMO"): macOS iconv has no converter, so the table is built in. Bytes 0x80–0xFF
// as Windows MultiByteToWideChar decodes them (generated from Python's cp720 codec, itself generated on Windows
// from the system code page data). Every byte maps, so decoding is bijective.
const char16_t kCp720High[128] = {
    0x0080, 0x0081, 0x00E9, 0x00E2, 0x0084, 0x00E0, 0x0086, 0x00E7,
    0x00EA, 0x00EB, 0x00E8, 0x00EF, 0x00EE, 0x008D, 0x008E, 0x008F,
    0x0090, 0x0651, 0x0652, 0x00F4, 0x00A4, 0x0640, 0x00FB, 0x00F9,
    0x0621, 0x0622, 0x0623, 0x0624, 0x00A3, 0x0625, 0x0626, 0x0627,
    0x0628, 0x0629, 0x062A, 0x062B, 0x062C, 0x062D, 0x062E, 0x062F,
    0x0630, 0x0631, 0x0632, 0x0633, 0x0634, 0x0635, 0x00AB, 0x00BB,
    0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556,
    0x2555, 0x2563, 0x2551, 0x2557, 0x255D, 0x255C, 0x255B, 0x2510,
    0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x255E, 0x255F,
    0x255A, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256C, 0x2567,
    0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256B,
    0x256A, 0x2518, 0x250C, 0x2588, 0x2584, 0x258C, 0x2590, 0x2580,
    0x0636, 0x0637, 0x0638, 0x0639, 0x063A, 0x0641, 0x00B5, 0x0642,
    0x0643, 0x0644, 0x0645, 0x0646, 0x0647, 0x0648, 0x0649, 0x064A,
    0x2261, 0x064B, 0x064C, 0x064D, 0x064E, 0x064F, 0x0650, 0x2248,
    0x00B0, 0x2219, 0x00B7, 0x221A, 0x207F, 0x00B2, 0x25A0, 0x00A0,
};

int g_ansiCodepage = 1252;

void appendUtf8(std::string& out, char32_t cp) {
    if (cp < 0x80) {
        out.push_back(static_cast<char>(cp));
    } else if (cp < 0x800) {
        out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else if (cp < 0x10000) {
        out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    } else {
        out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
    }
}

// Decode one UTF-8 sequence starting at i. Returns code point, advances i.
// Invalid sequences yield U+FFFD and advance by one byte; *bad is set.
char32_t nextUtf8(const std::string& s, size_t& i, bool* bad) {
    const unsigned char c = static_cast<unsigned char>(s[i]);
    auto cont = [&](size_t k) { return k < s.size() && (static_cast<unsigned char>(s[k]) & 0xC0) == 0x80; };
    if (c < 0x80) { ++i; return c; }
    if (c >= 0xC2 && c <= 0xDF && cont(i + 1)) {
        char32_t cp = ((c & 0x1F) << 6) | (s[i + 1] & 0x3F);
        i += 2; return cp;
    }
    if (c >= 0xE0 && c <= 0xEF && cont(i + 1) && cont(i + 2)) {
        char32_t cp = ((c & 0x0F) << 12) | ((s[i + 1] & 0x3F) << 6) | (s[i + 2] & 0x3F);
        if (cp >= 0x800 && !(cp >= 0xD800 && cp <= 0xDFFF)) { i += 3; return cp; }
    }
    if (c >= 0xF0 && c <= 0xF4 && cont(i + 1) && cont(i + 2) && cont(i + 3)) {
        char32_t cp = ((c & 0x07) << 18) | ((s[i + 1] & 0x3F) << 12) | ((s[i + 2] & 0x3F) << 6) | (s[i + 3] & 0x3F);
        if (cp >= 0x10000 && cp <= 0x10FFFF) { i += 4; return cp; }
    }
    if (bad) *bad = true;
    ++i;
    return 0xFFFD;
}

DecodeResult decodeUtf16(const std::string& b, size_t start, bool bigEndian) {
    DecodeResult r;
    r.utf8.reserve(b.size());
    size_t i = start;
    auto unit = [&](size_t k) -> char16_t {
        const unsigned char a = static_cast<unsigned char>(b[k]);
        const unsigned char c = static_cast<unsigned char>(b[k + 1]);
        return bigEndian ? static_cast<char16_t>((a << 8) | c) : static_cast<char16_t>((c << 8) | a);
    };
    while (i + 1 < b.size()) {
        char16_t u = unit(i);
        if (u >= 0xD800 && u <= 0xDBFF) {
            if (i + 3 < b.size()) {
                char16_t u2 = unit(i + 2);
                if (u2 >= 0xDC00 && u2 <= 0xDFFF) {
                    char32_t cp = 0x10000 + ((u - 0xD800) << 10) + (u2 - 0xDC00);
                    appendUtf8(r.utf8, cp);
                    i += 4;
                    continue;
                }
            }
            if (!r.lossy) r.firstLossyOffset = i;
            r.lossy = true;
            appendUtf8(r.utf8, 0xFFFD);
            i += 2;
            continue;
        }
        if (u >= 0xDC00 && u <= 0xDFFF) {
            if (!r.lossy) r.firstLossyOffset = i;
            r.lossy = true;
            appendUtf8(r.utf8, 0xFFFD);
            i += 2;
            continue;
        }
        if (u == 0) r.containsNul = true;
        appendUtf8(r.utf8, u);
        i += 2;
    }
    if (i < b.size()) {  // odd trailing byte
        if (!r.lossy) r.firstLossyOffset = i;
        r.lossy = true;
        appendUtf8(r.utf8, 0xFFFD);
    }
    return r;
}

std::string encodeUtf16(const std::string& utf8, bool bigEndian, EncodeResult& er) {
    std::string out;
    out.reserve(utf8.size() * 2 + 2);
    auto put = [&](char16_t u) {
        if (bigEndian) { out.push_back(static_cast<char>(u >> 8)); out.push_back(static_cast<char>(u & 0xFF)); }
        else { out.push_back(static_cast<char>(u & 0xFF)); out.push_back(static_cast<char>(u >> 8)); }
    };
    size_t i = 0;
    while (i < utf8.size()) {
        size_t at = i;
        bool bad = false;
        char32_t cp = nextUtf8(utf8, i, &bad);
        if (bad) {
            if (!er.lossy) er.firstLossyOffset = at;
            er.lossy = true; ++er.lossyCount;
        }
        if (cp >= 0x10000) {
            cp -= 0x10000;
            put(static_cast<char16_t>(0xD800 + (cp >> 10)));
            put(static_cast<char16_t>(0xDC00 + (cp & 0x3FF)));
        } else {
            put(static_cast<char16_t>(cp));
        }
    }
    return out;
}

DecodeResult decodeCp1252(const std::string& b) {
    DecodeResult r;
    r.utf8.reserve(b.size() + b.size() / 8);
    for (unsigned char c : b) {
        if (c == 0) r.containsNul = true;
        if (c < 0x80) r.utf8.push_back(static_cast<char>(c));
        else if (c < 0xA0) appendUtf8(r.utf8, kCp1252High[c - 0x80]);
        else appendUtf8(r.utf8, c);
    }
    return r;
}

DecodeResult decodeTable128(const std::string& b, const char16_t (&high)[128]) {
    DecodeResult r;
    r.utf8.reserve(b.size() + b.size() / 4);
    for (unsigned char c : b) {
        if (c == 0) r.containsNul = true;
        if (c < 0x80) r.utf8.push_back(static_cast<char>(c));
        else appendUtf8(r.utf8, high[c - 0x80]);
    }
    return r;
}

std::string encodeTable128(const std::string& utf8, const char16_t (&high)[128], EncodeResult& er) {
    std::string out;
    out.reserve(utf8.size());
    size_t i = 0;
    while (i < utf8.size()) {
        size_t at = i;
        bool bad = false;
        char32_t cp = nextUtf8(utf8, i, &bad);
        int byte = -1;
        if (!bad) {
            if (cp < 0x80) byte = static_cast<int>(cp);
            else for (int k = 0; k < 128; ++k) if (static_cast<char32_t>(high[k]) == cp) { byte = 0x80 + k; break; }
        }
        if (byte < 0) {
            if (!er.lossy) er.firstLossyOffset = at;
            er.lossy = true; ++er.lossyCount;
            out.push_back('?');
        } else {
            out.push_back(static_cast<char>(byte));
        }
    }
    return out;
}

std::string encodeCp1252(const std::string& utf8, EncodeResult& er) {
    std::string out;
    out.reserve(utf8.size());
    size_t i = 0;
    while (i < utf8.size()) {
        size_t at = i;
        bool bad = false;
        char32_t cp = nextUtf8(utf8, i, &bad);
        int byte = -1;
        if (!bad) {
            if (cp < 0x80 || (cp >= 0xA0 && cp <= 0xFF)) byte = static_cast<int>(cp);
            else for (int k = 0; k < 32; ++k) if (static_cast<char32_t>(kCp1252High[k]) == cp) { byte = 0x80 + k; break; }
        }
        if (byte < 0) {
            if (!er.lossy) er.firstLossyOffset = at;
            er.lossy = true; ++er.lossyCount;
            out.push_back('?');
        } else {
            out.push_back(static_cast<char>(byte));
        }
    }
    return out;
}

std::mutex g_iconvMutex;

// iconv-based conversion with per-character recovery.
bool iconvConvert(const char* from, const char* to, const std::string& in, std::string& out,
                  bool& lossy, size_t& firstBad, size_t& badCount, bool decoding) {
    iconv_t cd = iconv_open(to, from);
    if (cd == reinterpret_cast<iconv_t>(-1)) return false;
    out.clear();
    out.reserve(in.size() * (decoding ? 2 : 1) + 16);
    char buf[16384];
    char* inPtr = const_cast<char*>(in.data());
    size_t inLeft = in.size();
    while (inLeft > 0) {
        char* outPtr = buf;
        size_t outLeft = sizeof(buf);
        size_t rc = iconv(cd, &inPtr, &inLeft, &outPtr, &outLeft);
        out.append(buf, static_cast<size_t>(outPtr - buf));
        if (rc == static_cast<size_t>(-1)) {
            if (errno == E2BIG) continue;
            // EILSEQ or EINVAL: skip offending unit, emit a replacement
            size_t at = static_cast<size_t>(inPtr - in.data());
            if (!lossy) firstBad = at;
            lossy = true;
            ++badCount;
            if (decoding) {
                appendUtf8(out, 0xFFFD);
                ++inPtr; --inLeft;
            } else {
                out.push_back('?');
                size_t j = at;
                bool bad = false;
                nextUtf8(in, j, &bad);
                size_t skip = j - at;
                inPtr += skip; inLeft -= skip;
            }
            iconv(cd, nullptr, nullptr, nullptr, nullptr);
        }
    }
    // flush shift state
    char* outPtr = buf; size_t outLeft = sizeof(buf);
    iconv(cd, nullptr, nullptr, &outPtr, &outLeft);
    out.append(buf, static_cast<size_t>(outPtr - buf));
    iconv_close(cd);
    return true;
}

} // namespace

const std::vector<CodepageInfo>& codepageTable() {
    static const std::vector<CodepageInfo> t = {
        {1250, "WINDOWS-1250", "Windows-1250", 0},  {1251, "WINDOWS-1251", "Windows-1251", 1},
        {1252, "WINDOWS-1252", "Windows-1252", 2},  {1253, "WINDOWS-1253", "Windows-1253", 3},
        {1254, "WINDOWS-1254", "Windows-1254", 4},  {1255, "WINDOWS-1255", "Windows-1255", 5},
        {1256, "WINDOWS-1256", "Windows-1256", 6},  {1257, "WINDOWS-1257", "Windows-1257", 7},
        {1258, "WINDOWS-1258", "Windows-1258", 8},
        {28591, "ISO-8859-1", "ISO 8859-1", 9},     {28592, "ISO-8859-2", "ISO 8859-2", 10},
        {28593, "ISO-8859-3", "ISO 8859-3", 11},    {28594, "ISO-8859-4", "ISO 8859-4", 12},
        {28595, "ISO-8859-5", "ISO 8859-5", 13},    {28596, "ISO-8859-6", "ISO 8859-6", 14},
        {28597, "ISO-8859-7", "ISO 8859-7", 15},    {28598, "ISO-8859-8", "ISO 8859-8", 16},
        {28599, "ISO-8859-9", "ISO 8859-9", 17},    {28603, "ISO-8859-13", "ISO 8859-13", 20},
        {28604, "ISO-8859-14", "ISO 8859-14", 21},  {28605, "ISO-8859-15", "ISO 8859-15", 22},
        {437, "CP437", "OEM-US : CP437", 24},       {720, "CP720", "OEM 720", 25},
        {737, "CP737", "OEM 737", 26},              {775, "CP775", "OEM 775", 27},
        {850, "CP850", "OEM 850", 28},              {852, "CP852", "OEM 852", 29},
        {855, "CP855", "OEM 855", 30},              {857, "CP857", "OEM 857", 31},
        {858, "CP858", "OEM 858", 32},              {860, "CP860", "OEM 860 : Portuguese", 33},
        {861, "CP861", "OEM 861 : Icelandic", 34},  {862, "CP862", "OEM 862", 35},
        {863, "CP863", "OEM 863 : French", 36},     {865, "CP865", "OEM 865 : Nordic", 37},
        {866, "CP866", "OEM 866", 38},              {869, "CP869", "OEM 869", 39},
        {950, "CP950", "Big5 (Traditional)", 40},   {936, "CP936", "GB2312 (Simplified)", 41},
        {932, "CP932", "Shift-JIS", 42},            {949, "CP949", "Windows 949", 43},
        {51949, "EUC-KR", "EUC-KR", 44},            {874, "CP874", "TIS-620", 45},
        {10007, "MACCYRILLIC", "Macintosh", 46},    {21866, "KOI8-U", "KOI8-U", 47},
        {20866, "KOI8-R", "KOI8-R", 48},
    };
    return t;
}

const CodepageInfo* codepageInfo(int cp) {
    for (const auto& c : codepageTable()) if (c.codepage == cp) return &c;
    return nullptr;
}

const CodepageInfo* codepageInfoByMenuIndex(int idx) {
    for (const auto& c : codepageTable()) if (c.menuIndex == idx) return &c;
    return nullptr;
}

int ansiCodepage() { return g_ansiCodepage; }
void setAnsiCodepage(int cp) { g_ansiCodepage = cp; }

bool isAscii7(const std::string& s) {
    for (unsigned char c : s) if (c >= 0x80) return false;
    return true;
}

bool isValidUtf8(const std::string& s) {
    size_t i = 0;
    while (i < s.size()) {
        if (static_cast<unsigned char>(s[i]) < 0x80) { ++i; continue; }
        bool bad = false;
        nextUtf8(s, i, &bad);
        if (bad) return false;
    }
    return true;
}

static DecodeResult decodeCodepage(const std::string& bytes, int cp) {
    if (cp == 1252) return decodeCp1252(bytes);
    if (cp == 720) return decodeTable128(bytes, kCp720High);
    DecodeResult r;
    const CodepageInfo* info = codepageInfo(cp);
    if (!info) { r.ok = false; r.error = "Unknown codepage " + std::to_string(cp); return r; }
    std::lock_guard<std::mutex> lock(g_iconvMutex);
    size_t badCount = 0;
    if (!iconvConvert(info->iconvName, "UTF-8", bytes, r.utf8, r.lossy, r.firstLossyOffset, badCount, true)) {
        r.ok = false;
        r.error = std::string("No converter available for ") + info->menuName;
        return r;
    }
    r.containsNul = bytes.find('\0') != std::string::npos;
    return r;
}

static EncodeResult encodeCodepage(const std::string& utf8, int cp) {
    EncodeResult er;
    if (cp == 1252) { er.bytes = encodeCp1252(utf8, er); return er; }
    if (cp == 720) { er.bytes = encodeTable128(utf8, kCp720High, er); return er; }
    const CodepageInfo* info = codepageInfo(cp);
    if (!info) { er.ok = false; er.error = "Unknown codepage"; return er; }
    std::lock_guard<std::mutex> lock(g_iconvMutex);
    if (!iconvConvert("UTF-8", info->iconvName, utf8, er.bytes, er.lossy, er.firstLossyOffset, er.lossyCount, false)) {
        er.ok = false;
        er.error = std::string("No converter available for ") + info->menuName;
    }
    return er;
}

bool converterAvailable(int cp) {
    if (cp == 1252 || cp == 720) return true;
    const CodepageInfo* info = codepageInfo(cp);
    if (!info) return false;
    iconv_t cd = iconv_open("UTF-8", info->iconvName);
    if (cd == reinterpret_cast<iconv_t>(-1)) return false;
    iconv_close(cd);
    return true;
}

DecodeResult decodeAs(const std::string& bytes, TextEncoding enc) {
    if (enc.isCodepage()) {
        DecodeResult r = decodeCodepage(bytes, enc.codepage);
        r.encoding = enc;
        return r;
    }
    DecodeResult r;
    switch (enc.mode) {
        case UniMode::Utf16LE:
        case UniMode::Utf16BE: {
            const bool be = enc.mode == UniMode::Utf16BE;
            size_t start = 0;
            if (bytes.size() >= 2) {
                const unsigned char a = static_cast<unsigned char>(bytes[0]), b = static_cast<unsigned char>(bytes[1]);
                if ((be && a == 0xFE && b == 0xFF) || (!be && a == 0xFF && b == 0xFE)) start = 2;
            }
            r = decodeUtf16(bytes, start, be);
            break;
        }
        case UniMode::Utf8Bom:
        case UniMode::Utf8: {
            size_t start = (bytes.size() >= 3 && static_cast<unsigned char>(bytes[0]) == 0xEF &&
                            static_cast<unsigned char>(bytes[1]) == 0xBB && static_cast<unsigned char>(bytes[2]) == 0xBF) ? 3 : 0;
            r.utf8.assign(bytes, start, std::string::npos);
            if (!isValidUtf8(r.utf8)) {
                // Keep bytes but report: Scintilla shows invalid bytes as hex blobs.
                size_t i = 0;
                while (i < r.utf8.size()) {
                    size_t at = i; bool bad = false;
                    nextUtf8(r.utf8, i, &bad);
                    if (bad) { r.lossy = true; r.firstLossyOffset = at + start; break; }
                }
                // Invalid bytes are kept verbatim (Scintilla stores raw bytes), so saving is exact.
                r.lossy = false;
            }
            r.containsNul = r.utf8.find('\0') != std::string::npos;
            break;
        }
        case UniMode::Ansi:
        default:
            r = decodeCodepage(bytes, ansiCodepage());
            break;
    }
    r.encoding = enc;
    return r;
}

// upstream FileManager::detectCodepage + EncodingMapper::getEncodingFromString
int detectCodepage(const std::string& bytes) {
    if (bytes.empty()) return -1;
    uchardet_t ud = uchardet_new();
    uchardet_handle_data(ud, bytes.data(), bytes.size());
    uchardet_data_end(ud);
    std::string cs = uchardet_get_charset(ud) ?: "";
    uchardet_delete(ud);
    for (auto& ch : cs) ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
    if (cs.empty() || cs == "tis-620") return -1;   // upstream: uchardet usually reports UTF-8 wrongly as TIS-620
    if (cs == "utf-8" || cs == "utf8") return 65001;
    // upstream EncodingMapper alias lists (lower case)
    static const std::pair<int, const char*> kAliases[] = {
        {1250, "windows-1250"}, {1251, "windows-1251"}, {1252, "windows-1252"}, {1253, "windows-1253"},
        {1254, "windows-1254"}, {1255, "windows-1255"}, {1256, "windows-1256"}, {1257, "windows-1257"},
        {1258, "windows-1258"},
        {28591, "latin1 iso_8859-1 iso-8859-1 cp819 ibm819 csisolatin1 iso-ir-100 l1"},
        {28592, "latin2 iso_8859-2 iso-8859-2 csisolatin2 iso-ir-101 l2"},
        {28593, "latin3 iso_8859-3 iso-8859-3 csisolatin3 iso-ir-109 l3"},
        {28594, "latin4 iso_8859-4 iso-8859-4 csisolatin4 iso-ir-110 l4"},
        {28595, "cyrillic iso_8859-5 iso-8859-5 csisolatincyrillic iso-ir-144"},
        {28596, "arabic iso_8859-6 iso-8859-6 csisolatinarabic iso-ir-127 asmo-708 ecma-114"},
        {28597, "greek iso_8859-7 iso-8859-7 csisolatingreek greek8 iso-ir-126 elot_928 ecma-118"},
        {28598, "hebrew iso_8859-8 iso-8859-8 csisolatinhebrew iso-ir-138"},
        {28599, "latin5 iso_8859-9 iso-8859-9 csisolatin5 iso-ir-148 l5"},
        {28603, "iso_8859-13 iso-8859-13"}, {28604, "iso-celtic latin8 iso_8859-14 iso-8859-14 18 iso-ir-199"},
        {28605, "latin-9 iso_8859-15 iso-8859-15"},
        {437, "ibm437 cp437 437 cspc8codepage437"}, {720, "ibm720 cp720 oem720 720"}, {737, "ibm737 cp737 oem737 737"},
        {775, "ibm775 cp775 oem775 775"}, {850, "ibm850 cp850 oem850 850"}, {852, "ibm852 cp852 oem852 852"},
        {855, "ibm855 cp855 oem855 855 csibm855"}, {857, "ibm857 cp857 oem857 857"}, {858, "ibm858 cp858 oem858 858"},
        {860, "ibm860 cp860 oem860 860"}, {861, "ibm861 cp861 oem861 861"}, {862, "ibm862 cp862 oem862 862"},
        {863, "ibm863 cp863 oem863 863"}, {865, "ibm865 cp865 oem865 865"}, {866, "ibm866 cp866 oem866 866"},
        {869, "ibm869 cp869 oem869 869"}, {950, "big5 csbig5"}, {936, "gb2312 gbk csgb2312 gb18030"},
        {932, "shift_jis ms_kanji csshiftjis cswindows31j"}, {949, "windows-949 korean"}, {51949, "euc-kr cseuckr"},
        {874, "tis-620"}, {10007, "x-mac-cyrillic xmaccyrillic"}, {21866, "koi8_u"}, {20866, "koi8_r cskoi8r"},
    };
    for (const auto& [cp, list] : kAliases) {
        std::istringstream words(list);
        for (std::string w; words >> w;) if (w == cs) return cp;
    }
    return -1;
}

DecodeResult detectAndDecode(const std::string& bytes, bool openAnsiAsUtf8, bool autodetect) {
    const auto* u = reinterpret_cast<const unsigned char*>(bytes.data());
    const size_t n = bytes.size();
    if (n >= 3 && u[0] == 0xEF && u[1] == 0xBB && u[2] == 0xBF)
        return decodeAs(bytes, {UniMode::Utf8Bom, -1});
    if (n >= 2 && u[0] == 0xFE && u[1] == 0xFF)
        return decodeAs(bytes, {UniMode::Utf16BE, -1});
    if (n >= 2 && u[0] == 0xFF && u[1] == 0xFE)
        return decodeAs(bytes, {UniMode::Utf16LE, -1});
    // Preferences > MISC. > Autodetect character encoding (upstream FileManager::loadFileData): no BOM, so ask
    // uchardet; UTF-8 opens as UTF-8, a character set as that character set, anything else falls through
    if (autodetect && !isAscii7(bytes)) {
        const int cp = detectCodepage(bytes);
        if (cp == 65001) return decodeAs(bytes, {UniMode::Utf8, -1});
        if (cp > 0 && converterAvailable(cp)) {
            DecodeResult r = decodeAs(bytes, {UniMode::Utf8, cp});
            if (r.ok) return r;
        }
    }
    if (isAscii7(bytes))
        return decodeAs(bytes, {openAnsiAsUtf8 ? UniMode::Utf8 : UniMode::Ansi, -1});
    if (isValidUtf8(bytes))
        return decodeAs(bytes, {UniMode::Utf8, -1});
    return decodeAs(bytes, {UniMode::Ansi, -1});
}

EncodeResult encode(const std::string& utf8, TextEncoding enc) {
    if (enc.isCodepage()) return encodeCodepage(utf8, enc.codepage);
    EncodeResult er;
    switch (enc.mode) {
        case UniMode::Utf8:
            er.bytes = utf8;
            break;
        case UniMode::Utf8Bom:
            er.bytes.reserve(utf8.size() + 3);
            er.bytes.append("\xEF\xBB\xBF");
            er.bytes.append(utf8);
            break;
        case UniMode::Utf16LE:
            er.bytes = std::string("\xFF\xFE", 2) + encodeUtf16(utf8, false, er);
            break;
        case UniMode::Utf16BE:
            er.bytes = std::string("\xFE\xFF", 2) + encodeUtf16(utf8, true, er);
            break;
        case UniMode::Ansi:
        default:
            return encodeCodepage(utf8, ansiCodepage());
    }
    return er;
}

Eol detectEol(const std::string& t, Eol fallback) {
    // Upstream (FileManager::loadFileData) uses the first EOL found in the file.
    for (size_t i = 0; i < t.size(); ++i) {
        if (t[i] == '\r') return (i + 1 < t.size() && t[i + 1] == '\n') ? Eol::CRLF : Eol::CR;
        if (t[i] == '\n') return Eol::LF;
    }
    return fallback;
}

bool hasMixedEol(const std::string& t) {
    bool crlf = false, cr = false, lf = false;
    for (size_t i = 0; i < t.size(); ++i) {
        if (t[i] == '\r') {
            if (i + 1 < t.size() && t[i + 1] == '\n') { crlf = true; ++i; }
            else cr = true;
        } else if (t[i] == '\n') lf = true;
    }
    return (crlf + cr + lf) > 1;
}

const char* eolDisplayName(Eol e) {
    switch (e) {
        case Eol::CRLF: return "Windows (CR LF)";
        case Eol::CR: return "Macintosh (CR)";
        case Eol::LF: default: return "Unix (LF)";
    }
}

std::string encodingDisplayName(TextEncoding enc) {
    if (enc.isCodepage()) {
        const CodepageInfo* info = codepageInfo(enc.codepage);
        return info ? info->menuName : ("CP" + std::to_string(enc.codepage));
    }
    switch (enc.mode) {
        case UniMode::Ansi: return "ANSI";
        case UniMode::Utf8Bom: return "UTF-8-BOM";
        case UniMode::Utf16BE: return "UTF-16 BE BOM";
        case UniMode::Utf16LE: return "UTF-16 LE BOM";
        case UniMode::Utf8: default: return "UTF-8";
    }
}

} // namespace tpp
