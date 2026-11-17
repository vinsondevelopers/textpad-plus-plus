// Textpad++ — JSON formatting. GPL-3.0-or-later.
#include "core/Json.h"
#include <cctype>
#include <cstring>
#include <algorithm>
#include <cstdio>
#include <vector>

namespace tpp::json {
namespace {

enum class Mode { Pretty, Compact, Check };

struct Writer {
    const std::string& s;
    Mode mode;
    std::string indentUnit, eol;
    std::string out;
    size_t i = 0;
    std::string error;
    size_t errorAt = 0;
    int depth = 0;

    bool fail(const char* msg) { if (error.empty()) { error = msg; errorAt = i; } return false; }
    void ws() { while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) ++i; }
    void put(const std::string& t) { if (mode != Mode::Check) out += t; }
    void put(char c) { if (mode != Mode::Check) out += c; }
    void newline(int level) {
        if (mode != Mode::Pretty) return;
        out += eol;
        for (int k = 0; k < level; ++k) out += indentUnit;
    }

    bool string() {
        const size_t start = i;
        ++i;   // the opening quote
        while (i < s.size()) {
            const unsigned char c = static_cast<unsigned char>(s[i]);
            if (c == '"') { ++i; put(s.substr(start, i - start)); return true; }
            if (c < 0x20) return fail("Control character in a string (escape it)");
            if (c == '\\') {
                if (i + 1 >= s.size()) break;
                const char e = s[i + 1];
                if (e == 'u') {
                    for (int k = 2; k < 6; ++k)
                        if (i + k >= s.size() || !isxdigit(static_cast<unsigned char>(s[i + k]))) { i += 1; return fail("Invalid \\u escape (four hex digits expected)"); }
                    i += 6;
                    continue;
                }
                if (!strchr("\"\\/bfnrt", e)) { ++i; return fail("Invalid escape in a string"); }
                i += 2;
                continue;
            }
            ++i;
        }
        i = start;
        return fail("Unterminated string");
    }

    bool number() {
        const size_t start = i;
        if (s[i] == '-') ++i;
        if (i >= s.size()) return fail("Invalid number");
        if (s[i] == '0') ++i;
        else if (s[i] >= '1' && s[i] <= '9') while (i < s.size() && isdigit(static_cast<unsigned char>(s[i]))) ++i;
        else return fail("Invalid number");
        if (i < s.size() && s[i] == '.') {
            ++i;
            if (i >= s.size() || !isdigit(static_cast<unsigned char>(s[i]))) return fail("Digits expected after the decimal point");
            while (i < s.size() && isdigit(static_cast<unsigned char>(s[i]))) ++i;
        }
        if (i < s.size() && (s[i] == 'e' || s[i] == 'E')) {
            ++i;
            if (i < s.size() && (s[i] == '+' || s[i] == '-')) ++i;
            if (i >= s.size() || !isdigit(static_cast<unsigned char>(s[i]))) return fail("Digits expected in the exponent");
            while (i < s.size() && isdigit(static_cast<unsigned char>(s[i]))) ++i;
        }
        put(s.substr(start, i - start));
        return true;
    }

    bool literal(const char* word) {
        const size_t n = strlen(word);
        if (s.compare(i, n, word) != 0) return fail("Unexpected character");
        put(word);
        i += n;
        return true;
    }

    bool value() {
        ws();
        if (i >= s.size()) return fail("A value was expected");
        const char c = s[i];
        if (c == '{' || c == '[') {
            if (++depth > 4000) return fail("Nested too deeply");
            const bool obj = c == '{';
            const char close = obj ? '}' : ']';
            put(c);
            ++i;
            ws();
            if (i < s.size() && s[i] == close) { put(close); ++i; --depth; return true; }   // {} and [] stay on one line
            for (bool first = true;; first = false) {
                if (!first) {
                    ws();
                    if (i < s.size() && s[i] == ',') { put(','); ++i; }
                    else if (i < s.size() && s[i] == close) break;
                    else return fail(obj ? "Expected ',' or '}'" : "Expected ',' or ']'");
                }
                newline(depth);
                ws();
                if (obj) {
                    if (i >= s.size() || s[i] != '"') return fail("A member name (a string in double quotes) was expected");
                    if (!string()) return false;
                    ws();
                    if (i >= s.size() || s[i] != ':') return fail("Expected ':' after the member name");
                    ++i;
                    put(mode == Mode::Pretty ? ": " : ":");
                }
                if (!value()) return false;
            }
            --depth;
            newline(depth);
            put(close);
            ++i;
            return true;
        }
        if (c == '"') return string();
        if (c == '-' || (c >= '0' && c <= '9')) return number();
        if (c == 't') return literal("true");
        if (c == 'f') return literal("false");
        if (c == 'n') return literal("null");
        return fail("Unexpected character");
    }

    Result run() {
        Result r;
        if (s.size() >= 3 && s.compare(0, 3, "\xEF\xBB\xBF") == 0) i = 3;
        bool ok = value();
        if (ok) { ws(); if (i < s.size()) ok = fail("Unexpected text after the end of the JSON value"); }
        r.ok = ok;
        if (ok) r.text = std::move(out);
        else { r.error = error; r.errorOffset = errorAt; }
        return r;
    }
};

} // namespace

Result format(const std::string& in, const std::string& indentUnit, const std::string& eol) {
    Writer w{in, Mode::Pretty, indentUnit, eol};
    return w.run();
}
Result compress(const std::string& in) { Writer w{in, Mode::Compact, "", ""}; return w.run(); }
Result validate(const std::string& in) { Writer w{in, Mode::Check, "", ""}; return w.run(); }


// ---------------------------------------------------------------- a small tree, for sorting and CSV (input already validated)
namespace {

struct Node {
    char kind = 0;   // '{' '[' '"' or 'v' (number / true / false / null)
    std::string raw; // strings with their quotes, numbers and literals as written
    std::vector<std::pair<std::string, Node>> members;   // raw keys (with quotes)
    std::vector<Node> items;
};

struct Parser {
    const std::string& s;
    size_t i = 0;
    void ws() { while (i < s.size() && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) ++i; }
    std::string str() {
        const size_t start = i++;
        while (i < s.size() && s[i] != '"') i += s[i] == '\\' ? 2 : 1;
        ++i;
        return s.substr(start, i - start);
    }
    Node value() {
        ws();
        Node n;
        const char c = s[i];
        if (c == '{' || c == '[') {
            n.kind = c;
            const char close = c == '{' ? '}' : ']';
            ++i;
            for (;;) {
                ws();
                if (s[i] == close) { ++i; break; }
                if (s[i] == ',') { ++i; continue; }
                if (c == '{') {
                    std::string k = str();
                    ws(); ++i;   // ':'
                    n.members.emplace_back(std::move(k), value());
                } else n.items.push_back(value());
            }
        } else if (c == '"') { n.kind = '"'; n.raw = str(); }
        else {
            n.kind = 'v';
            const size_t start = i;
            while (i < s.size() && !strchr(",]} \t\r\n", s[i])) ++i;
            n.raw = s.substr(start, i - start);
        }
        return n;
    }
};

void appendUtf8(std::string& out, unsigned cp) {
    if (cp < 0x80) out += static_cast<char>(cp);
    else if (cp < 0x800) { out += static_cast<char>(0xC0 | (cp >> 6)); out += static_cast<char>(0x80 | (cp & 0x3F)); }
    else if (cp < 0x10000) { out += static_cast<char>(0xE0 | (cp >> 12)); out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F)); out += static_cast<char>(0x80 | (cp & 0x3F)); }
    else { out += static_cast<char>(0xF0 | (cp >> 18)); out += static_cast<char>(0x80 | ((cp >> 12) & 0x3F)); out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F)); out += static_cast<char>(0x80 | (cp & 0x3F)); }
}

// the text of a validated string literal (with its quotes)
std::string decode(const std::string& raw) {
    std::string out;
    for (size_t i = 1; i + 1 < raw.size(); ++i) {
        if (raw[i] != '\\') { out += raw[i]; continue; }
        const char e = raw[++i];
        switch (e) {
            case 'b': out += '\b'; break;
            case 'f': out += '\f'; break;
            case 'n': out += '\n'; break;
            case 'r': out += '\r'; break;
            case 't': out += '\t'; break;
            case 'u': {
                unsigned cp = static_cast<unsigned>(std::stoul(raw.substr(i + 1, 4), nullptr, 16));
                i += 4;
                if (cp >= 0xD800 && cp < 0xDC00 && i + 6 < raw.size() && raw[i + 1] == '\\' && raw[i + 2] == 'u') {
                    const unsigned lo = static_cast<unsigned>(std::stoul(raw.substr(i + 3, 4), nullptr, 16));
                    if (lo >= 0xDC00 && lo < 0xE000) { cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00); i += 6; }
                }
                appendUtf8(out, cp);
                break;
            }
            default: out += e;
        }
    }
    return out;
}

void compact(const Node& n, std::string& out) {
    if (n.kind == '{') {
        out += '{';
        for (size_t k = 0; k < n.members.size(); ++k) { if (k) out += ','; out += n.members[k].first; out += ':'; compact(n.members[k].second, out); }
        out += '}';
    } else if (n.kind == '[') {
        out += '[';
        for (size_t k = 0; k < n.items.size(); ++k) { if (k) out += ','; compact(n.items[k], out); }
        out += ']';
    } else out += n.raw;
}

void sortNode(Node& n) {
    for (auto& m : n.members) sortNode(m.second);
    for (auto& it : n.items) sortNode(it);
    std::stable_sort(n.members.begin(), n.members.end(), [](const auto& a, const auto& b) { return decode(a.first) < decode(b.first); });
}

std::string csvCell(const std::string& v) {
    if (v.find_first_of(",\"\r\n") == std::string::npos && (v.empty() || (v.front() != ' ' && v.back() != ' '))) return v;
    std::string q = "\"";
    for (char c : v) { if (c == '"') q += '"'; q += c; }
    return q + "\"";
}

std::string cellText(const Node& n) {
    if (n.kind == '"') return decode(n.raw);
    if (n.kind == 'v') return n.raw == "null" ? std::string() : n.raw;
    std::string out;
    compact(n, out);
    return out;
}

} // namespace

Result sortKeys(const std::string& in, const std::string& indentUnit, const std::string& eol) {
    Result v = validate(in);
    if (!v.ok) return v;
    Parser p{in};
    if (in.size() >= 3 && in.compare(0, 3, "\xEF\xBB\xBF") == 0) p.i = 3;
    Node root = p.value();
    sortNode(root);
    std::string flat;
    compact(root, flat);
    return format(flat, indentUnit, eol);
}

Result toCsv(const std::string& in, const std::string& eol) {
    Result v = validate(in);
    if (!v.ok) return v;
    Parser p{in};
    if (in.size() >= 3 && in.compare(0, 3, "\xEF\xBB\xBF") == 0) p.i = 3;
    Node root = p.value();
    if (root.kind == '{') { Node arr; arr.kind = '['; arr.items.push_back(root); root = arr; }
    Result r;
    if (root.kind != '[') { r.error = "An array of objects (or a single object) was expected"; return r; }
    std::vector<std::string> cols;   // decoded names, first-seen order
    bool objects = false;
    for (const Node& row : root.items) {
        if (row.kind == '{') {
            objects = true;
            for (const auto& m : row.members) { std::string k = decode(m.first); if (std::find(cols.begin(), cols.end(), k) == cols.end()) cols.push_back(k); }
        } else if (row.kind != '[') { r.error = "Every element of the array must be an object or an array"; return r; }
    }
    std::string out;
    if (objects) {
        for (size_t k = 0; k < cols.size(); ++k) { if (k) out += ','; out += csvCell(cols[k]); }
        out += eol;
    }
    for (const Node& row : root.items) {
        if (row.kind == '{') {
            for (size_t k = 0; k < cols.size(); ++k) {
                if (k) out += ',';
                for (const auto& m : row.members) if (decode(m.first) == cols[k]) { out += csvCell(cellText(m.second)); break; }
            }
        } else for (size_t k = 0; k < row.items.size(); ++k) { if (k) out += ','; out += csvCell(cellText(row.items[k])); }
        out += eol;
    }
    r.ok = true;
    r.text = out;
    return r;
}

std::string escapeString(const std::string& text) {
    std::string out = "\"";
    for (unsigned char c : text) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            default:
                if (c < 0x20) { char b[8]; snprintf(b, sizeof b, "\\u%04x", c); out += b; }
                else out += static_cast<char>(c);
        }
    }
    return out + "\"";
}

Result unescapeString(const std::string& literal) {
    std::string t = literal;
    while (!t.empty() && strchr(" \t\r\n", t.back())) t.pop_back();
    size_t a = 0;
    while (a < t.size() && strchr(" \t\r\n", t[a])) ++a;
    t = t.substr(a);
    if (t.size() < 2 || t.front() != '"' || t.back() != '"') t = "\"" + t + "\"";
    Result v = validate(t);
    if (!v.ok) { if (v.errorOffset) --v.errorOffset; return v; }
    Result r;
    r.ok = true;
    r.text = decode(t);
    return r;
}

} // namespace tpp::json
