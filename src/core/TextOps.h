// Textpad++ — text transformation primitives (pure C++).
// Copyright (C) 2026 Textpad++ contributors. GPL-3.0-or-later.
//
// Behaviour is ported from Notepad++ v8.9.9.1:
//   ScintillaEditView::changeCase           -> changeCase
//   MISC/Common/Sorters.h (all sorters)       -> sortLines
//   FindReplaceDlg::Searching::convertExtendedToString -> convertExtended
// Lines are processed as UTF-16 code units where upstream does (wstring on Windows)
// so ordering and lengths match the Windows build.
#pragma once

#include <cstddef>
#include <optional>
#include <string>
#include <vector>

namespace tpp::textops {

enum class Case { Upper, Lower, ProperForce, ProperBlend, SentenceForce, SentenceBlend, Invert, Random };
std::string changeCase(const std::string& utf8, Case c, unsigned randomSeed = 0);

enum class SortMode {
    Lexicographic, LexicographicIgnoreCase, Locale, Integer, DecimalComma, DecimalDot, Length,
    Reverse, Random
};
struct SortResult {
    bool ok = true;
    size_t failedLineIndex = 0;  // index into the input vector when a numeric sort fails
};
// fromColumn/toColumn are 0-based UTF-16 columns (toColumn == 0 -> whole line), as upstream ISorter.
SortResult sortLines(std::vector<std::string>& lines, SortMode mode, bool descending,
                     size_t fromColumn = 0, size_t toColumn = 0, unsigned randomSeed = 0);

void removeDuplicateLines(std::vector<std::string>& lines);           // keep first occurrence
void removeConsecutiveDuplicateLines(std::vector<std::string>& lines);
void removeEmptyLines(std::vector<std::string>& lines, bool alsoBlankLines);

std::string trimTrailing(const std::string& line);   // spaces and tabs
std::string trimLeading(const std::string& line);
std::string tabsToSpaces(const std::string& line, int tabWidth);
std::string spacesToTabs(const std::string& line, int tabWidth, bool leadingOnly);

// Split text into lines (without EOL). If the text ends with an EOL, the final empty
// line is NOT included and *endsWithEol is set.
std::vector<std::string> splitLines(const std::string& text, bool* endsWithEol = nullptr);
std::string joinLines(const std::vector<std::string>& lines, const std::string& eol);

// Extended search mode: \n \r \t \0 \\ \xhh \uhhhh \bbbbbbbbb \dddd \oooo (upstream semantics).
// Returns std::nullopt for an invalid escape sequence.
std::optional<std::string> convertExtended(const std::string& in);

// Utility conversions (UTF-8 <-> UTF-16 code units).
std::u16string toU16(const std::string& utf8);
std::string fromU16(const std::u16string& u16);
size_t utf16Length(const std::string& utf8);

} // namespace tpp::textops
