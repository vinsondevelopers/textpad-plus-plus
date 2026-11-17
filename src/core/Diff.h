// Textpad++ — line and character differences (Myers' O(ND) algorithm, linear space, with the common prefix and
// suffix taken off first) for View > Compare and the Git change markers. GPL-3.0-or-later.
#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace tpp::diff {

// a run of the old text [aStart, aStart + aCount) replaced by [bStart, bStart + bCount) of the new one
struct Hunk { size_t aStart, aCount, bStart, bCount; };

std::vector<Hunk> diffSequences(const std::vector<uint64_t>& a, const std::vector<uint64_t>& b);
std::vector<std::string> splitLines(const std::string& text);              // "\r\n", "\r" or "\n"; no line ends kept
std::vector<Hunk> diffLines(const std::string& a, const std::string& b, bool ignoreWhitespace = false);
std::vector<Hunk> diffChars(const std::string& a, const std::string& b);   // by UTF-8 character (byte offsets)

} // namespace tpp::diff
