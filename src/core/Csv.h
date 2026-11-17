// Textpad++ — CSV for Plugins > Convert: RFC 4180 reading (quotes, doubled quotes, line breaks in quoted cells) with
// the delimiter found automatically (comma, semicolon, tab or |), then CSV -> JSON and CSV -> Markdown table.
// GPL-3.0-or-later.
#pragma once
#include <string>
#include <vector>

namespace tpp::csv {

char detectDelimiter(const std::string& in);
std::vector<std::vector<std::string>> parse(const std::string& in, char delimiter);
// the first row names the fields; numbers, true, false and null stay JSON values, the rest become strings
std::string toJson(const std::string& in, const std::string& indentUnit = "    ", const std::string& eol = "\n");
std::string toMarkdown(const std::string& in, const std::string& eol = "\n");
// Edit > CSV Columns: pad every field with spaces so the delimiters line up / take that padding off again
// (quoted fields and line ends are kept; widths count characters)
std::string align(const std::string& in, char delimiter);
std::string shrink(const std::string& in, char delimiter);
// the byte ranges of the fields of one line: [start, end) pairs, quotes respected
std::vector<std::pair<size_t, size_t>> fieldsOfLine(const std::string& line, char delimiter);

} // namespace tpp::csv
