// Textpad++ — code formatters. GPL-3.0-or-later.
#include "core/CodeFormat.h"
#include <algorithm>
#include <cctype>
#include <cstring>
#include <set>
#include <vector>

namespace tpp::format {
namespace {

std::string upper(std::string s) { for (char& c : s) c = (char)toupper((unsigned char)c); return s; }
std::string lower(std::string s) { for (char& c : s) c = (char)tolower((unsigned char)c); return s; }
bool isSpace(char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f'; }
std::string trim(const std::string& s) {
    size_t a = 0, b = s.size();
    while (a < b && isSpace(s[a])) ++a;
    while (b > a && isSpace(s[b - 1])) --b;
    return s.substr(a, b - a);
}
std::string collapse(const std::string& s) {   // runs of white space -> one space
    std::string o;
    bool sp = false;
    for (char c : s) { if (isSpace(c)) sp = true; else { if (sp) o += ' '; sp = false; o += c; } }
    if (sp) o += ' ';
    return o;
}
void rtrim(std::string& s) {   // trailing blanks; a line that is only its indent keeps it
    if (s.find_first_not_of(" \t") == std::string::npos) return;
    while (!s.empty() && (s.back() == ' ' || s.back() == '\t')) s.pop_back();
}

// ================================================================ SQL
struct Tok { enum Kind { Word, Str, Comment, LineComment, Num, Sym, Open, Close, Comma, Semi } kind; std::string text; };

std::vector<Tok> sqlTokens(const std::string& s) {
    std::vector<Tok> t;
    for (size_t i = 0; i < s.size();) {
        const char c = s[i];
        if (isSpace(c)) { ++i; continue; }
        if (c == '-' && i + 1 < s.size() && s[i + 1] == '-') { size_t e = s.find_first_of("\r\n", i); if (e == std::string::npos) e = s.size(); t.push_back({Tok::LineComment, s.substr(i, e - i)}); i = e; continue; }
        if (c == '#' ) { size_t e = s.find_first_of("\r\n", i); if (e == std::string::npos) e = s.size(); t.push_back({Tok::LineComment, s.substr(i, e - i)}); i = e; continue; }
        if (c == '/' && i + 1 < s.size() && s[i + 1] == '*') { size_t e = s.find("*/", i + 2); e = e == std::string::npos ? s.size() : e + 2; t.push_back({Tok::Comment, s.substr(i, e - i)}); i = e; continue; }
        if (c == '\'' || c == '"' || c == '`' || c == '[') {
            const char close = c == '[' ? ']' : c;
            size_t j = i + 1;
            while (j < s.size()) { if (s[j] == close) { if (close != ']' && j + 1 < s.size() && s[j + 1] == close) { j += 2; continue; } break; } if (s[j] == '\\' && c != '[') ++j; ++j; }
            j = std::min(j + 1, s.size());
            t.push_back({Tok::Str, s.substr(i, j - i)});
            i = j;
            continue;
        }
        if (isdigit((unsigned char)c)) { size_t j = i; while (j < s.size() && (isalnum((unsigned char)s[j]) || s[j] == '.')) ++j; t.push_back({Tok::Num, s.substr(i, j - i)}); i = j; continue; }
        if (isalpha((unsigned char)c) || c == '_' || c == '@' || c == '$' || (unsigned char)c >= 0x80) {
            size_t j = i; while (j < s.size() && (isalnum((unsigned char)s[j]) || s[j] == '_' || s[j] == '@' || s[j] == '$' || s[j] == '.' || (unsigned char)s[j] >= 0x80)) ++j;
            t.push_back({Tok::Word, s.substr(i, j - i)}); i = j; continue;
        }
        if (c == '(') { t.push_back({Tok::Open, "("}); ++i; continue; }
        if (c == ')') { t.push_back({Tok::Close, ")"}); ++i; continue; }
        if (c == ',') { t.push_back({Tok::Comma, ","}); ++i; continue; }
        if (c == ';') { t.push_back({Tok::Semi, ";"}); ++i; continue; }
        // operators: <=, >=, <>, !=, ||, ::, :=
        static const char* two[] = {"<=", ">=", "<>", "!=", "||", "::", ":=", "->"};
        bool done = false;
        for (const char* op : two) if (s.compare(i, 2, op) == 0) { t.push_back({Tok::Sym, op}); i += 2; done = true; break; }
        if (!done) { t.push_back({Tok::Sym, std::string(1, c)}); ++i; }
    }
    return t;
}

const std::set<std::string>& sqlKeywords() {
    static const std::set<std::string> k = {"ADD", "ALL", "ALTER", "AND", "ANY", "AS", "ASC", "BEGIN", "BETWEEN", "BY", "CASE", "CAST", "CHECK", "COLUMN",
        "COMMIT", "CONSTRAINT", "CREATE", "CROSS", "DATABASE", "DEFAULT", "DELETE", "DESC", "DISTINCT", "DROP", "ELSE", "END", "EXCEPT", "EXISTS", "FALSE",
        "FOREIGN", "FROM", "FULL", "GROUP", "HAVING", "IF", "IN", "INDEX", "INNER", "INSERT", "INTERSECT", "INTO", "IS", "JOIN", "KEY", "LEFT", "LIKE", "LIMIT",
        "NOT", "NULL", "OFFSET", "ON", "OR", "ORDER", "OUTER", "OVER", "PARTITION", "PRIMARY", "REFERENCES", "RETURNING", "RIGHT", "ROLLBACK", "SELECT", "SET",
        "TABLE", "THEN", "TOP", "TRUE", "TRUNCATE", "UNION", "UNIQUE", "UPDATE", "USING", "VALUES", "VIEW", "WHEN", "WHERE", "WITH", "ILIKE", "RECURSIVE",
        "COUNT", "SUM", "AVG", "MIN", "MAX", "COALESCE", "NULLIF", "INTEGER", "INT", "VARCHAR", "TEXT", "BOOLEAN", "DATE", "TIMESTAMP", "REPLACE", "NATURAL"};
    return k;
}

} // namespace

std::string sql(const std::string& in, const std::string& ind, const std::string& eol, bool up) {
    const auto toks = sqlTokens(in);
    // clauses that start a line at the statement's level; their content is indented one step
    static const std::set<std::string> clause = {"SELECT", "FROM", "WHERE", "GROUP BY", "ORDER BY", "HAVING", "LIMIT", "OFFSET", "UNION", "UNION ALL",
        "INTERSECT", "EXCEPT", "INSERT INTO", "VALUES", "UPDATE", "SET", "DELETE FROM", "DELETE", "WITH", "RETURNING", "PARTITION BY"};
    static const std::set<std::string> joins = {"JOIN", "INNER JOIN", "LEFT JOIN", "RIGHT JOIN", "FULL JOIN", "CROSS JOIN", "LEFT OUTER JOIN",
        "RIGHT OUTER JOIN", "FULL OUTER JOIN", "NATURAL JOIN"};
    std::string out, line;
    struct Level { int base; bool sub; bool inSelect; bool inValues; };
    std::vector<Level> stack{{0, false, false, false}};
    int caseDepth = 0;
    auto pad = [&](int n) { std::string s; for (int k = 0; k < n; ++k) s += ind; return s; };
    auto flush = [&]() { rtrim(line); if (!trim(line).empty()) { out += line; out += eol; } line.clear(); };
    static const std::set<std::string> functions = {"COUNT", "SUM", "AVG", "MIN", "MAX", "COALESCE", "NULLIF", "CAST", "REPLACE", "CONCAT", "LOWER",
        "UPPER", "SUBSTRING", "TRIM", "ROUND", "ABS", "NOW", "DATE", "LENGTH", "IFNULL", "ISNULL", "EXTRACT", "OVER", "ROW_NUMBER", "RANK"};
    auto newLine = [&](int level) { flush(); line = pad(level); };
    auto put = [&](const std::string& w) {
        if (!line.empty() && line.back() != ' ' && line.back() != '(' && !(line.find_first_not_of(" \t") == std::string::npos)) line += ' ';
        line += w;
    };
    for (size_t i = 0; i < toks.size(); ++i) {
        const Tok& t = toks[i];
        Level& L = stack.back();
        if (t.kind == Tok::Word) {
            std::string w = up && sqlKeywords().count(upper(t.text)) ? upper(t.text) : t.text;
            // two- and three-word clauses
            std::string W = upper(t.text), phrase = W;
            size_t used = 0;
            auto nextWord = [&](size_t k) { return k < toks.size() && toks[k].kind == Tok::Word ? upper(toks[k].text) : std::string(); };
            const std::string n1 = nextWord(i + 1), n2 = nextWord(i + 2);
            if ((W == "GROUP" || W == "ORDER" || W == "PARTITION") && n1 == "BY") { phrase = W + " BY"; used = 1; }
            else if (W == "UNION" && n1 == "ALL") { phrase = "UNION ALL"; used = 1; }
            else if (W == "INSERT" && n1 == "INTO") { phrase = "INSERT INTO"; used = 1; }
            else if (W == "DELETE" && n1 == "FROM") { phrase = "DELETE FROM"; used = 1; }
            else if ((W == "LEFT" || W == "RIGHT" || W == "FULL") && n1 == "OUTER" && n2 == "JOIN") { phrase = W + " OUTER JOIN"; used = 2; }
            else if ((W == "LEFT" || W == "RIGHT" || W == "FULL" || W == "INNER" || W == "CROSS" || W == "NATURAL") && n1 == "JOIN") { phrase = W + " JOIN"; used = 1; }
            if (W == "CASE") ++caseDepth;
            if (W == "END" && caseDepth) --caseDepth;
            if (clause.count(phrase) && caseDepth == 0 && !(phrase == "SET" && L.inSelect)) {
                std::string text = phrase;
                if (!up) { text.clear(); for (size_t k = 0; k <= used; ++k) { if (k) text += ' '; text += toks[i + k].text; } }
                newLine(L.base);
                line += text;
                L.inSelect = phrase == "SELECT";
                L.inValues = phrase == "VALUES";
                i += used;
                if (phrase == "UNION" || phrase == "UNION ALL" || phrase == "INTERSECT" || phrase == "EXCEPT") { newLine(L.base); }
                else newLine(L.base + 1);
                continue;
            }
            if (joins.count(phrase)) {
                std::string text = phrase;
                if (!up) { text.clear(); for (size_t k = 0; k <= used; ++k) { if (k) text += ' '; text += toks[i + k].text; } }
                newLine(L.base);
                line += text;
                i += used;
                L.inSelect = false;
                continue;
            }
            if (W == "ON" && caseDepth == 0) { newLine(L.base + 1); line += up ? "ON" : t.text; continue; }
            if ((W == "AND" || W == "OR") && caseDepth == 0 && !L.inSelect) {
                // BETWEEN x AND y stays together
                bool between = false;
                for (size_t k = i; k-- > 0 && k + 4 > i;) if (toks[k].kind == Tok::Word && upper(toks[k].text) == "BETWEEN") between = true;
                if (!between) { newLine(L.base + 1); line += w; continue; }
            }
            put(w);
            continue;
        }
        if (t.kind == Tok::Open) {
            const bool sub = i + 1 < toks.size() && toks[i + 1].kind == Tok::Word && (upper(toks[i + 1].text) == "SELECT" || upper(toks[i + 1].text) == "WITH");
            if (!line.empty() && line.back() != ' ' && line.back() != '(' && (i == 0 || toks[i - 1].kind != Tok::Word ||
                (sqlKeywords().count(upper(toks[i - 1].text)) && !functions.count(upper(toks[i - 1].text))))) {
                if (trim(line).size()) line += ' ';
            }
            line += "(";
            stack.push_back({sub ? L.base + 2 : L.base, sub, false, false});
            continue;
        }
        if (t.kind == Tok::Close) {
            const bool sub = stack.back().sub;
            if (stack.size() > 1) stack.pop_back();
            if (sub) newLine(stack.back().base + 1);
            rtrim(line);
            line += ")";
            continue;
        }
        if (t.kind == Tok::Comma) {
            rtrim(line);
            line += ",";
            if ((L.inSelect || (L.inValues && stack.size() == 1)) && caseDepth == 0) newLine(L.base + 1);
            else line += ' ';
            continue;
        }
        if (t.kind == Tok::Semi) {
            rtrim(line);
            line += ";";
            flush();
            out += eol;
            stack = {{0, false, false, false}};
            continue;
        }
        if (t.kind == Tok::LineComment) { put(t.text); flush(); line = pad(L.base + 1); continue; }
        if (t.kind == Tok::Sym && (t.text == "." || t.text == "::")) { rtrim(line); line += t.text; if (i + 1 < toks.size() && toks[i + 1].kind != Tok::Word) {} continue; }
        if (i > 0 && toks[i - 1].kind == Tok::Sym && (toks[i - 1].text == "." || toks[i - 1].text == "::")) { line += t.text; continue; }
        put(t.text);
    }
    flush();
    while (out.size() >= eol.size() * 2 && out.compare(out.size() - eol.size() * 2, eol.size() * 2, eol + eol) == 0) out.erase(out.size() - eol.size());
    // no line end after the last line, like the input usually has
    if (out.size() >= eol.size()) out.erase(out.size() - eol.size());
    return out;
}

// ================================================================ CSS
namespace {
// the CSS split into: comments, strings, "{", "}", ";" and the text between them
std::vector<std::string> cssPieces(const std::string& s) {
    std::vector<std::string> p;
    std::string cur;
    auto push = [&]() { if (!cur.empty()) { p.push_back(cur); cur.clear(); } };
    for (size_t i = 0; i < s.size(); ++i) {
        const char c = s[i];
        if (c == '/' && i + 1 < s.size() && s[i + 1] == '*') {
            size_t e = s.find("*/", i + 2); e = e == std::string::npos ? s.size() : e + 2;
            push(); p.push_back(s.substr(i, e - i)); i = e - 1; continue;
        }
        if (c == '"' || c == '\'') {
            size_t j = i + 1; while (j < s.size() && s[j] != c) { if (s[j] == '\\') ++j; ++j; }
            cur += s.substr(i, std::min(j + 1, s.size()) - i); i = std::min(j, s.size() - 1); continue;
        }
        if (c == '(') {   // url(...) and other functions: whole, ';' inside a data: URL is not an end
            int depth = 0; size_t j = i;
            for (; j < s.size(); ++j) { if (s[j] == '(') ++depth; else if (s[j] == ')' && --depth == 0) break; else if (s[j] == '"' || s[j] == '\'') { const char q = s[j]; for (++j; j < s.size() && s[j] != q; ++j) if (s[j] == '\\') ++j; } }
            cur += s.substr(i, std::min(j + 1, s.size()) - i); i = std::min(j, s.size() - 1); continue;
        }
        if (c == '{' || c == '}' || c == ';') { push(); p.push_back(std::string(1, c)); continue; }
        cur += c;
    }
    push();
    return p;
}

std::string cssDeclaration(const std::string& d) {
    const std::string t = collapse(trim(d));
    const size_t colon = t.find(':');
    if (colon == std::string::npos || t.compare(0, 1, "@") == 0) return t;
    return trim(t.substr(0, colon)) + ": " + trim(t.substr(colon + 1));
}

std::string cssSelector(const std::string& s) {
    std::string t = collapse(trim(s)), o;
    // "a,b" -> "a, b"
    for (size_t i = 0; i < t.size(); ++i) { o += t[i]; if (t[i] == ',' && i + 1 < t.size() && t[i + 1] != ' ') o += ' '; }
    return o;
}
} // namespace

std::string css(const std::string& in, const std::string& ind, const std::string& eol) {
    const auto pieces = cssPieces(in);
    std::string out;
    int depth = 0;
    auto pad = [&](int n) { std::string s; for (int k = 0; k < n; ++k) s += ind; return s; };
    std::string pending;   // text waiting for its end ({ ; })
    bool lastWasBlockEnd = false;
    for (size_t i = 0; i < pieces.size(); ++i) {
        const std::string& p = pieces[i];
        if (p.compare(0, 2, "/*") == 0) {
            if (!trim(pending).empty()) { out += pad(depth) + cssDeclaration(pending) + eol; pending.clear(); }
            if (depth == 0 && lastWasBlockEnd) out += eol;
            out += pad(depth) + p + eol;
            lastWasBlockEnd = false;
            continue;
        }
        if (p == "{") {
            if (depth == 0 && lastWasBlockEnd) out += eol;
            out += pad(depth) + cssSelector(pending) + " {" + eol;
            pending.clear();
            ++depth;
            lastWasBlockEnd = false;
            continue;
        }
        if (p == ";") {
            const std::string d = trim(pending);
            if (!d.empty()) out += pad(depth) + cssDeclaration(d) + ";" + eol;
            pending.clear();
            continue;
        }
        if (p == "}") {
            if (!trim(pending).empty()) out += pad(depth) + cssDeclaration(pending) + ";" + eol;
            pending.clear();
            depth = std::max(0, depth - 1);
            out += pad(depth) + "}" + eol;
            lastWasBlockEnd = depth == 0;
            if (depth > 0) lastWasBlockEnd = false;
            continue;
        }
        pending += p;
    }
    if (!trim(pending).empty()) out += pad(depth) + collapse(trim(pending)) + eol;
    if (out.size() >= eol.size()) out.erase(out.size() - eol.size());
    return out;
}

std::string cssMinify(const std::string& in) {
    const auto pieces = cssPieces(in);
    std::string out;
    for (const std::string& p : pieces) {
        if (p.compare(0, 2, "/*") == 0) { if (p.compare(0, 3, "/*!") == 0) out += p; continue; }   // licence comments stay
        if (p == "{" || p == "}" || p == ";") {
            if (p == "}" && !out.empty() && out.back() == ';') out.pop_back();
            out += p;
            continue;
        }
        std::string t = collapse(trim(p)), o;
        for (size_t i = 0; i < t.size(); ++i) {
            const char c = t[i];
            if (c == ' ' && i > 0 && i + 1 < t.size() && (strchr(":,>+~", t[i - 1]) || strchr(":,>+~", t[i + 1]))) continue;
            if (c == '"' || c == '\'') { size_t j = i + 1; while (j < t.size() && t[j] != c) { if (t[j] == '\\') ++j; ++j; } o += t.substr(i, std::min(j + 1, t.size()) - i); i = std::min(j, t.size() - 1); continue; }
            o += c;
        }
        out += o;
    }
    return out;
}

// ================================================================ HTML
namespace {
struct Node {
    enum Kind { Element, Text, Comment, Raw } kind;
    std::string name, open, close, text;   // open: the whole start tag as written
    std::vector<Node> children;
};

const std::set<std::string>& voidTags() {
    static const std::set<std::string> v = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"};
    return v;
}
const std::set<std::string>& inlineTags() {
    static const std::set<std::string> v = {"a", "abbr", "b", "bdi", "bdo", "br", "cite", "code", "data", "dfn", "em", "i", "img", "kbd", "label", "mark", "q",
        "s", "samp", "small", "span", "strong", "sub", "sup", "time", "u", "var", "wbr", "del", "ins", "button", "select", "option", "input"};
    return v;
}
bool rawTag(const std::string& n) { return n == "script" || n == "style" || n == "pre" || n == "textarea"; }

std::string tagName(const std::string& tag) {   // "<div class=x>" -> "div"
    size_t i = 1;
    if (i < tag.size() && tag[i] == '/') ++i;
    size_t j = i;
    while (j < tag.size() && (isalnum((unsigned char)tag[j]) || tag[j] == '-' || tag[j] == ':')) ++j;
    return lower(tag.substr(i, j - i));
}

Node parseHtml(const std::string& s) {
    Node root{Node::Element, "#root", "", "", "", {}};
    std::vector<Node*> stack{&root};
    size_t i = 0;
    while (i < s.size()) {
        if (s.compare(i, 4, "<!--") == 0) {
            size_t e = s.find("-->", i + 4); e = e == std::string::npos ? s.size() : e + 3;
            stack.back()->children.push_back({Node::Comment, "", "", "", s.substr(i, e - i), {}});
            i = e; continue;
        }
        if (s[i] == '<' && i + 1 < s.size() && (isalpha((unsigned char)s[i + 1]) || s[i + 1] == '/' || s[i + 1] == '!' || s[i + 1] == '?')) {
            // the end of the tag, quotes respected
            size_t j = i + 1; char q = 0;
            for (; j < s.size(); ++j) { if (q) { if (s[j] == q) q = 0; } else if (s[j] == '"' || s[j] == '\'') q = s[j]; else if (s[j] == '>') break; }
            const std::string tag = s.substr(i, std::min(j + 1, s.size()) - i);
            i = std::min(j + 1, s.size());
            if (tag[1] == '!' || tag[1] == '?') { stack.back()->children.push_back({Node::Comment, "", "", "", tag, {}}); continue; }
            const std::string name = tagName(tag);
            if (tag[1] == '/') {
                for (size_t k = stack.size(); k-- > 1;) if (stack[k]->name == name) { stack[k]->close = tag; stack.resize(k); break; }
                continue;
            }
            Node el{Node::Element, name, tag, "", "", {}};
            const bool selfClosed = tag.size() >= 2 && tag[tag.size() - 2] == '/';
            if (rawTag(name) && !selfClosed) {
                const std::string endTag = "</" + name;
                size_t e = i;
                for (;;) { e = s.find('<', e); if (e == std::string::npos || lower(s.substr(e, endTag.size())) == endTag) break; ++e; }
                if (e == std::string::npos) e = s.size();
                el.children.push_back({Node::Raw, "", "", "", s.substr(i, e - i), {}});
                size_t ce = s.find('>', e);
                el.close = e < s.size() ? s.substr(e, (ce == std::string::npos ? s.size() : ce + 1) - e) : "</" + name + ">";
                i = ce == std::string::npos ? s.size() : ce + 1;
                stack.back()->children.push_back(el);
                continue;
            }
            // <p> and <li> close an open one of their kind (the common implied ends)
            if ((name == "li" || name == "p" || name == "tr" || name == "td" || name == "th" || name == "option") && stack.size() > 1 && stack.back()->name == name && stack.back()->close.empty())
                stack.pop_back();
            stack.back()->children.push_back(el);
            if (!voidTags().count(name) && !selfClosed) stack.push_back(&stack.back()->children.back());
            continue;
        }
        size_t e = s.find('<', i + 1);
        if (e == std::string::npos) e = s.size();
        stack.back()->children.push_back({Node::Text, "", "", "", s.substr(i, e - i), {}});
        i = e;
    }
    return root;
}

std::string closeOf(const Node& n) {
    if (voidTags().count(n.name) || (n.open.size() >= 2 && n.open[n.open.size() - 2] == '/')) return "";
    return n.close.empty() ? "</" + n.name + ">" : n.close;
}

// the node written on one line (inline content)
std::string flat(const Node& n) {
    if (n.kind == Node::Text) return collapse(n.text);
    if (n.kind == Node::Comment || n.kind == Node::Raw) return n.text;
    std::string s = n.open;
    for (const Node& c : n.children) s += flat(c);
    return s + closeOf(n);
}

bool allInline(const Node& n) {
    for (const Node& c : n.children) {
        if (c.kind == Node::Text || c.kind == Node::Comment) continue;
        if (c.kind == Node::Raw) return false;
        if (!inlineTags().count(c.name) || !allInline(c)) return false;
    }
    return true;
}

void writeHtml(const Node& n, int depth, const std::string& ind, const std::string& eol, std::string& out) {
    auto pad = [&](int k) { std::string s; for (int x = 0; x < k; ++x) s += ind; return s; };
    for (size_t i = 0; i < n.children.size(); ++i) {
        const Node& c = n.children[i];
        if (c.kind == Node::Text) { const std::string t = trim(collapse(c.text)); if (!t.empty()) out += pad(depth) + t + eol; continue; }
        if (c.kind == Node::Comment) { out += pad(depth) + trim(c.text) + eol; continue; }
        if (rawTag(c.name)) {   // contents verbatim
            out += pad(depth) + c.open;
            for (const Node& r : c.children) out += r.text;
            out += closeOf(c) + eol;
            continue;
        }
        const std::string one = trim(flat(c));
        if (voidTags().count(c.name) || (allInline(c) && one.size() <= 100)) {
            // keep a run of inline siblings and text together on one line
            if (inlineTags().count(c.name)) {
                std::string run = one;
                while (i + 1 < n.children.size()) {
                    const Node& x = n.children[i + 1];
                    if (x.kind == Node::Text) { run += collapse(x.text); ++i; continue; }
                    if (x.kind == Node::Element && inlineTags().count(x.name) && allInline(x)) { run += flat(x); ++i; continue; }
                    break;
                }
                out += pad(depth) + trim(run) + eol;
            } else out += pad(depth) + one + eol;
            continue;
        }
        out += pad(depth) + c.open + eol;
        writeHtml(c, depth + 1, ind, eol, out);
        const std::string cl = closeOf(c);
        if (!cl.empty()) out += pad(depth) + cl + eol;
    }
}
} // namespace

std::string html(const std::string& in, const std::string& ind, const std::string& eol) {
    const Node root = parseHtml(in);
    std::string out;
    writeHtml(root, 0, ind, eol, out);
    if (out.size() >= eol.size()) out.erase(out.size() - eol.size());
    return out;
}

} // namespace tpp::format
