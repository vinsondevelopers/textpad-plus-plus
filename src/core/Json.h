// Textpad++ — JSON formatting for Plugins > JSON Tools: format (pretty print), compress (minify), validate.
// A strict RFC 8259 parser that keeps key order, string escapes and number spelling exactly as written.
// GPL-3.0-or-later.
#pragma once
#include <string>
#include <cstddef>

namespace tpp::json {

struct Result {
    bool ok = false;
    std::string text;           // the formatted text (format / compress)
    size_t errorOffset = 0;     // byte offset of the problem when !ok
    std::string error;          // "Expected ',' or '}'" ...
};

Result format(const std::string& in, const std::string& indentUnit = "    ", const std::string& eol = "\n");
Result compress(const std::string& in);
Result validate(const std::string& in);
Result sortKeys(const std::string& in, const std::string& indentUnit = "    ", const std::string& eol = "\n");   // members sorted A-Z, every level
Result toCsv(const std::string& in, const std::string& eol = "\n");   // an array of objects (or of arrays) -> CSV with a header row
std::string escapeString(const std::string& text);                  // text -> "a JSON string literal"
Result unescapeString(const std::string& literal);                   // "a JSON string literal" (quotes optional) -> text

} // namespace tpp::json
