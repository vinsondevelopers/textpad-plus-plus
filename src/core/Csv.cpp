// Textpad++ — CSV conversions. GPL-3.0-or-later.
#include "core/Csv.h"
#include "core/Json.h"
#include <algorithm>
#include <cctype>

namespace tpp::csv {

char detectDelimiter(const std::string& in) {
    const std::string line = in.substr(0, in.find('\n'));
    const char cands[] = {',', ';', '\t', '|'};
    char best = ',';
    long most = 0;
    for (char c : cands) {
        long n = 0;
        bool quoted = false;
        for (char ch : line) { if (ch == '"') quoted = !quoted; else if (!quoted && ch == c) ++n; }
        if (n > most) { most = n; best = c; }
    }
    return best;
}

std::vector<std::vector<std::string>> parse(const std::string& in, char d) {
    std::vector<std::vector<std::string>> rows;
    std::vector<std::string> row;
    std::string cell;
    bool quoted = false, any = false;
    size_t i = (in.size() >= 3 && in.compare(0, 3, "\xEF\xBB\xBF") == 0) ? 3 : 0;
    for (; i < in.size(); ++i) {
        const char c = in[i];
        any = true;
        if (quoted) {
            if (c == '"') { if (i + 1 < in.size() && in[i + 1] == '"') { cell += '"'; ++i; } else quoted = false; }
            else cell += c;
        } else if (c == '"') quoted = true;
        else if (c == d) { row.push_back(cell); cell.clear(); }
        else if (c == '\r' || c == '\n') {
            if (c == '\r' && i + 1 < in.size() && in[i + 1] == '\n') ++i;
            row.push_back(cell); cell.clear();
            rows.push_back(row); row.clear();
            any = false;
        } else cell += c;
    }
    if (any) { row.push_back(cell); rows.push_back(row); }
    // blank lines are not rows
    rows.erase(std::remove_if(rows.begin(), rows.end(), [](const std::vector<std::string>& r) { return r.size() == 1 && r[0].empty(); }), rows.end());
    return rows;
}

static bool isJsonLiteral(const std::string& v) {
    if (v == "true" || v == "false" || v == "null") return true;
    if (v.empty()) return false;
    return tpp::json::validate(v).ok && (v[0] == '-' || isdigit(static_cast<unsigned char>(v[0])));
}

std::string toJson(const std::string& in, const std::string& indentUnit, const std::string& eol) {
    auto rows = parse(in, detectDelimiter(in));
    std::string flat = "[";
    if (!rows.empty()) {
        const auto& head = rows[0];
        for (size_t r = 1; r < rows.size(); ++r) {
            if (r > 1) flat += ',';
            flat += '{';
            for (size_t k = 0; k < head.size(); ++k) {
                if (k) flat += ',';
                flat += tpp::json::escapeString(head[k].empty() ? "column" + std::to_string(k + 1) : head[k]);
                flat += ':';
                const std::string v = k < rows[r].size() ? rows[r][k] : "";
                flat += isJsonLiteral(v) ? v : tpp::json::escapeString(v);
            }
            flat += '}';
        }
    }
    flat += ']';
    return tpp::json::format(flat, indentUnit, eol).text;
}

static std::string mdCell(const std::string& v) {
    std::string o;
    for (char c : v) {
        if (c == '|') o += "\\|";
        else if (c == '\r') continue;
        else if (c == '\n') o += "<br>";
        else o += c;
    }
    return o;
}

std::string toMarkdown(const std::string& in, const std::string& eol) {
    auto rows = parse(in, detectDelimiter(in));
    if (rows.empty()) return "";
    size_t cols = 0;
    for (const auto& r : rows) cols = std::max(cols, r.size());
    std::string out;
    for (size_t r = 0; r < rows.size(); ++r) {
        out += '|';
        for (size_t k = 0; k < cols; ++k) { out += ' '; out += mdCell(k < rows[r].size() ? rows[r][k] : ""); out += " |"; }
        out += eol;
        if (r == 0) { out += '|'; for (size_t k = 0; k < cols; ++k) out += " --- |"; out += eol; }
    }
    return out;
}


std::vector<std::pair<size_t, size_t>> fieldsOfLine(const std::string& line, char d) {
    std::vector<std::pair<size_t, size_t>> out;
    size_t start = 0;
    bool quoted = false;
    for (size_t i = 0; i < line.size(); ++i) {
        const char c = line[i];
        if (c == '"') quoted = !quoted;
        else if (c == d && !quoted) { out.push_back({start, i}); start = i + 1; }
    }
    out.push_back({start, line.size()});
    return out;
}

static size_t chars(const std::string& s) { size_t n = 0; for (unsigned char c : s) if ((c & 0xC0) != 0x80) ++n; return n; }
static std::string trimmed(const std::string& s) {
    size_t a = 0, b = s.size();
    while (a < b && (s[a] == ' ' || s[a] == '\t')) ++a;
    while (b > a && (s[b - 1] == ' ' || s[b - 1] == '\t')) --b;
    return s.substr(a, b - a);
}

// lines with their line ends kept apart
static void splitKeepingEols(const std::string& in, std::vector<std::string>& lines, std::vector<std::string>& eols) {
    size_t s = 0;
    for (size_t i = 0; i < in.size(); ++i) {
        if (in[i] == '\n' || in[i] == '\r') {
            lines.push_back(in.substr(s, i - s));
            const size_t n = (in[i] == '\r' && i + 1 < in.size() && in[i + 1] == '\n') ? 2 : 1;
            eols.push_back(in.substr(i, n));
            i += n - 1;
            s = i + 1;
        }
    }
    lines.push_back(in.substr(s));
    eols.push_back("");
}

std::string shrink(const std::string& in, char d) {
    std::vector<std::string> lines, eols;
    splitKeepingEols(in, lines, eols);
    std::string out;
    for (size_t k = 0; k < lines.size(); ++k) {
        const auto f = fieldsOfLine(lines[k], d);
        for (size_t j = 0; j < f.size(); ++j) { if (j) out += d; out += trimmed(lines[k].substr(f[j].first, f[j].second - f[j].first)); }
        out += eols[k];
    }
    return out;
}

std::string align(const std::string& in, char d) {
    const std::string flat = shrink(in, d);
    std::vector<std::string> lines, eols;
    splitKeepingEols(flat, lines, eols);
    std::vector<size_t> width;
    std::vector<std::vector<std::string>> cells(lines.size());
    for (size_t k = 0; k < lines.size(); ++k) {
        for (const auto& f : fieldsOfLine(lines[k], d)) cells[k].push_back(lines[k].substr(f.first, f.second - f.first));
        if (cells[k].size() == 1 && cells[k][0].empty()) continue;   // blank line
        for (size_t j = 0; j < cells[k].size(); ++j) { if (width.size() <= j) width.push_back(0); width[j] = std::max(width[j], chars(cells[k][j])); }
    }
    std::string out;
    for (size_t k = 0; k < lines.size(); ++k) {
        for (size_t j = 0; j < cells[k].size(); ++j) {
            if (j) out += d;
            if (j && d != '\t') out += ' ';
            out += cells[k][j];
            if (j + 1 < cells[k].size()) out.append(width[j] - chars(cells[k][j]), ' ');
        }
        out += eols[k];
    }
    return out;
}

} // namespace tpp::csv
