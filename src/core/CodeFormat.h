// Textpad++ — Plugins > Code Formatter: SQL (keywords upper-cased, one clause per line, select lists and AND/OR
// broken out, sub-queries indented), HTML (block elements indented, short inline content kept on one line,
// <pre>/<script>/<style>/<textarea> untouched), CSS (one declaration per line) and CSS minify. Strings and
// comments are never changed. GPL-3.0-or-later.
#pragma once
#include <string>

namespace tpp::format {

std::string sql(const std::string& in, const std::string& indent = "    ", const std::string& eol = "\n", bool upperKeywords = true);
std::string html(const std::string& in, const std::string& indent = "    ", const std::string& eol = "\n");
std::string css(const std::string& in, const std::string& indent = "    ", const std::string& eol = "\n");
std::string cssMinify(const std::string& in);

} // namespace tpp::format
