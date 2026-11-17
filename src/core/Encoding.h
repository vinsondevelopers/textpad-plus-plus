// Textpad++ — encoding and line-ending services (pure C++, no AppKit).
// Copyright (C) 2026 Textpad++ contributors. GPL-3.0-or-later.
//
// Model mirrors Notepad++'s Buffer (UniMode + legacy codepage, see upstream
// PowerEditor/src/Utf8_16.h and EncodingMapper.cpp) so behaviour can be compared 1:1.
// Scintilla always holds UTF-8 in Textpad++; bytes are decoded on load and re-encoded
// on save. The "ANSI" decoder is byte-bijective so arbitrary files round-trip exactly.
#pragma once

#include <cstddef>
#include <string>
#include <vector>

namespace tpp {

// Same ordering/meaning as upstream UniMode (uni8Bit, uniUTF8, uni16BE, uni16LE, uniCookie).
enum class UniMode : int { Ansi = 0, Utf8Bom = 1, Utf16BE = 2, Utf16LE = 3, Utf8 = 4 };

// Same values as Scintilla SC_EOL_CRLF / SC_EOL_CR / SC_EOL_LF.
enum class Eol : int { CRLF = 0, CR = 1, LF = 2 };

struct TextEncoding {
    UniMode mode = UniMode::Utf8;
    int codepage = -1;   // > 0 : legacy codepage (Encoding > Character sets); -1 : use mode
    bool isCodepage() const { return codepage > 0; }
    bool operator==(const TextEncoding& o) const { return mode == o.mode && codepage == o.codepage; }
    bool operator!=(const TextEncoding& o) const { return !(*this == o); }
};

struct CodepageInfo {
    int codepage;          // Windows codepage number (as upstream EncodingMapper)
    const char* iconvName; // name used with iconv(3)
    const char* menuName;  // label used in the Encoding > Character sets menu / status bar
    int menuIndex;         // offset from IDM_FORMAT_ENCODE
};

const std::vector<CodepageInfo>& codepageTable();
const CodepageInfo* codepageInfo(int codepage);
const CodepageInfo* codepageInfoByMenuIndex(int menuIndex);

// Codepage used for "ANSI". Windows uses the system ACP; macOS has none, so Textpad++
// defaults to Windows-1252 (documented in KNOWN_DIFFERENCES.md).
int ansiCodepage();
void setAnsiCodepage(int cp);

struct DecodeResult {
    std::string utf8;
    TextEncoding encoding;
    bool lossy = false;          // some input bytes could not be represented
    size_t firstLossyOffset = 0; // byte offset in the input
    bool containsNul = false;    // likely binary content
    bool ok = true;              // false if the converter is unavailable
    std::string error;
};

struct EncodeResult {
    std::string bytes;
    bool lossy = false;          // some characters could not be represented
    size_t firstLossyOffset = 0; // byte offset in the UTF-8 input
    size_t lossyCount = 0;
    bool ok = true;
    std::string error;
};

// Upstream: Utf8_16_Read::determineEncoding + FileManager open logic.
// openAnsiAsUtf8 mirrors Preferences > New Document > "Apply to opened ANSI files".
// BOM, then (autodetect: Preferences > MISC. > Autodetect character encoding) uchardet, then UTF-8 / ANSI
DecodeResult detectAndDecode(const std::string& bytes, bool openAnsiAsUtf8 = true, bool autodetect = false);
int detectCodepage(const std::string& bytes);   // uchardet: 65001, a codepage of codepageTable(), or -1
DecodeResult decodeAs(const std::string& bytes, TextEncoding enc);
EncodeResult encode(const std::string& utf8, TextEncoding enc);
bool converterAvailable(int codepage);

bool isValidUtf8(const std::string& s);
bool isAscii7(const std::string& s);

Eol detectEol(const std::string& text, Eol fallback);
const char* eolDisplayName(Eol e);  // "Windows (CR LF)", "Unix (LF)", "Macintosh (CR)"
bool hasMixedEol(const std::string& text);

std::string encodingDisplayName(TextEncoding enc);  // "UTF-8", "UTF-8-BOM", "ANSI", "Windows-1251", ...

} // namespace tpp
