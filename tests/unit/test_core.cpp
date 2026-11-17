// Textpad++ unit tests for the pure-C++ core (encoding, text operations, hashing).
// Run: make unit   (writes build/unit-results.json)
#include "core/Encoding.h"
#include "core/Hashing.h"
#include "core/TextOps.h"
#include "core/Json.h"
#include "core/Csv.h"
#include "core/Diff.h"
#include "core/CodeFormat.h"

#include <cstdio>
#include <fstream>
#include <functional>
#include <random>
#include <string>
#include <vector>

using namespace tpp;
namespace to = tpp::textops;

struct TestCase { std::string id; std::string name; std::function<std::string()> fn; };  // returns "" on pass
static std::vector<TestCase>& registry() { static std::vector<TestCase> r; return r; }
struct Reg { Reg(const char* id, const char* n, std::function<std::string()> f) { registry().push_back({id, n, std::move(f)}); } };
#define TEST(id, name) static std::string test_##id(); static Reg reg_##id(#id, name, test_##id); static std::string test_##id()
#define EXPECT(cond) do { if (!(cond)) return std::string("line ") + std::to_string(__LINE__) + ": " #cond; } while (0)
#define EXPECT_EQ(a, b) do { auto _a = (a); auto _b = (b); if (!(_a == _b)) return std::string("line ") + std::to_string(__LINE__) + ": " #a " != " #b; } while (0)

static std::string bytes(std::initializer_list<int> l) { std::string s; for (int c : l) s.push_back(static_cast<char>(c)); return s; }

// ---------------- encoding ----------------
TEST(ENC_001, "Empty file is UTF-8 and round-trips") {
    auto d = detectAndDecode("");
    EXPECT(d.encoding.mode == UniMode::Utf8);
    EXPECT(encode(d.utf8, d.encoding).bytes.empty());
    return "";
}
TEST(ENC_002, "UTF-8 BOM detected, preserved on save") {
    std::string in = "\xEF\xBB\xBF" "caf\xC3\xA9\r\n";
    auto d = detectAndDecode(in);
    EXPECT(d.encoding.mode == UniMode::Utf8Bom);
    EXPECT_EQ(d.utf8, std::string("caf\xC3\xA9\r\n"));
    EXPECT_EQ(encode(d.utf8, d.encoding).bytes, in);
    return "";
}
TEST(ENC_003, "UTF-16 LE BOM round-trip incl. surrogate pair") {
    std::string in = bytes({0xFF, 0xFE, 'A', 0, 0x3D, 0xD8, 0x00, 0xDE, '\n', 0});  // A 😀 \n
    auto d = detectAndDecode(in);
    EXPECT(d.encoding.mode == UniMode::Utf16LE);
    EXPECT_EQ(d.utf8, std::string("A\xF0\x9F\x98\x80\n"));
    EXPECT(!d.lossy);
    EXPECT_EQ(encode(d.utf8, d.encoding).bytes, in);
    return "";
}
TEST(ENC_004, "UTF-16 BE BOM round-trip") {
    std::string in = bytes({0xFE, 0xFF, 0, 'h', 0, 'i', 0x04, 0x10});
    auto d = detectAndDecode(in);
    EXPECT(d.encoding.mode == UniMode::Utf16BE);
    EXPECT_EQ(encode(d.utf8, d.encoding).bytes, in);
    return "";
}
TEST(ENC_005, "UTF-8 without BOM detected") {
    std::string in = "\xE0\xA4\xA8\xE0\xA4\xAE\xE0\xA4\xB8\xE0\xA5\x8D\xE0\xA4\xA4\xE0\xA5\x87";  // नमस्ते
    auto d = detectAndDecode(in);
    EXPECT(d.encoding.mode == UniMode::Utf8);
    EXPECT_EQ(encode(d.utf8, d.encoding).bytes, in);
    return "";
}
TEST(ENC_006, "Invalid UTF-8 falls back to ANSI and round-trips byte-exact") {
    std::string in = "abc\xE9\x80\xFF\n";
    auto d = detectAndDecode(in);
    EXPECT(d.encoding.mode == UniMode::Ansi);
    EXPECT(!d.lossy);
    EXPECT_EQ(encode(d.utf8, d.encoding).bytes, in);
    return "";
}
TEST(ENC_007, "All 256 byte values round-trip through ANSI (binary safety)") {
    std::string in;
    for (int i = 0; i < 256; ++i) in.push_back(static_cast<char>(i));
    auto d = decodeAs(in, {UniMode::Ansi, -1});
    EXPECT(d.containsNul);
    EXPECT(!d.lossy);
    EXPECT_EQ(encode(d.utf8, d.encoding).bytes, in);
    return "";
}
TEST(ENC_008, "Random binary blobs round-trip via auto-detection") {
    std::mt19937 rng(1234);
    for (int k = 0; k < 200; ++k) {
        std::string in(static_cast<size_t>(rng() % 4096), '\0');
        for (auto& c : in) c = static_cast<char>(rng() & 0xFF);
        auto d = detectAndDecode(in);
        if (d.encoding.mode == UniMode::Utf16LE || d.encoding.mode == UniMode::Utf16BE) continue;  // BOM-led blob may be odd-length
        auto e = encode(d.utf8, d.encoding);
        if (e.bytes != in) return "blob " + std::to_string(k) + " did not round-trip";
    }
    return "";
}
TEST(ENC_009, "Convert UTF-8 -> ANSI reports unrepresentable characters") {
    auto e = encode("A\xE2\x82\xAC\xE4\xB8\xAD", {UniMode::Ansi, -1});  // A € 中
    EXPECT(e.lossy);
    EXPECT_EQ(e.lossyCount, size_t(1));
    EXPECT_EQ(e.bytes, std::string("A\x80?"));
    return "";
}
TEST(ENC_010, "Windows-1251 reinterpretation") {
    std::string in = bytes({0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2});  // Привет
    auto d = decodeAs(in, {UniMode::Utf8, 1251});
    EXPECT(d.ok);
    EXPECT_EQ(d.utf8, std::string("\xD0\x9F\xD1\x80\xD0\xB8\xD0\xB2\xD0\xB5\xD1\x82"));
    EXPECT_EQ(encode(d.utf8, d.encoding).bytes, in);
    return "";
}
TEST(ENC_011, "Shift-JIS reinterpretation round-trip") {
    std::string in = bytes({0x82, 0xB1, 0x82, 0xF1, 0x82, 0xC9, 0x82, 0xBF, 0x82, 0xCD});  // こんにちは
    auto d = decodeAs(in, {UniMode::Utf8, 932});
    EXPECT(d.ok);
    EXPECT(!d.lossy);
    EXPECT_EQ(encode(d.utf8, d.encoding).bytes, in);
    return "";
}
TEST(ENC_012, "Every Character-sets codepage has a converter (OEM 720 built in)") {
    std::string missing;
    for (auto& c : codepageTable()) if (!converterAvailable(c.codepage)) missing += std::string(c.menuName) + "; ";
    if (!missing.empty()) return "no converter: " + missing;
    return "";
}
TEST(ENC_014, "OEM 720: Windows table (0x82 é, 0x98 ء, 0xE5 ف), all 256 bytes round-trip, unmappable reported") {
    EXPECT(converterAvailable(720));
    auto d = decodeAs(bytes({0x82, 0x98, 0xE5, 0x41}), {UniMode::Utf8, 720});
    EXPECT(d.ok && !d.lossy);
    EXPECT_EQ(d.utf8, std::string("\xC3\xA9\xD8\xA1\xD9\x81" "A"));
    std::string all;
    for (int i = 0; i < 256; ++i) all.push_back(static_cast<char>(i));
    auto r = decodeAs(all, {UniMode::Utf8, 720});
    auto e = encode(r.utf8, r.encoding);
    EXPECT(!e.lossy);
    EXPECT_EQ(e.bytes, all);
    auto bad = encode("\xE2\x82\xAC", {UniMode::Utf8, 720});           // € is not in OEM 720
    EXPECT(bad.lossy && bad.bytes == "?");
    return "";
}
TEST(ENC_015, "uchardet: UTF-8, Windows-1251, Shift-JIS, ASCII; autodetect opens them as upstream does") {
    std::string utf8 = "Ceci est un texte français : déjà, où, très, élève, naïve, cœur, Noël, garçon, hôtel, forêt. "
                       "Les élèves étudient l'été à l'école près de la forêt.";
    EXPECT_EQ(detectCodepage(utf8), 65001);
    std::string ru = encode("В начале было Слово, и Слово было у Бога, и Слово было Бог. Оно было в начале у Бога. "
                            "Все через Него начало быть, и без Него ничто не начало быть, что начало быть. В Нем была жизнь, "
                            "и жизнь была свет человеков. И свет во тьме светит, и тьма не объяла его. Москва является "
                            "столицей Российской Федерации и крупнейшим городом страны.", {UniMode::Utf8, 1251}).bytes;
    EXPECT_EQ(detectCodepage(ru), 1251);
    std::string el = encode("Η Ελλάδα είναι χώρα της νοτιοανατολικής Ευρώπης. Η πρωτεύουσα της χώρας είναι η Αθήνα, "
                            "η οποία είναι και η μεγαλύτερη πόλη.", {UniMode::Utf8, 1253}).bytes;
    EXPECT_EQ(detectCodepage(el), 28597);                                 // uchardet answers ISO-8859-7
    std::string jp = encode("こんにちは、世界。これは日本語の文字コード判定のテストです。今日はいい天気ですね。", {UniMode::Utf8, 932}).bytes;
    EXPECT_EQ(detectCodepage(jp), 932);
    EXPECT_EQ(detectCodepage("plain ascii text"), -1);
    auto on = detectAndDecode(ru, true, true);
    EXPECT(on.encoding.codepage == 1251 && on.utf8.find("\xD0\x92 \xD0\xBD\xD0\xB0") == 0);   // "В на"
    auto off = detectAndDecode(ru, true, false);
    EXPECT(off.encoding.mode == UniMode::Ansi && off.encoding.codepage == -1);
    auto u = detectAndDecode(utf8, true, true);
    EXPECT(u.encoding.mode == UniMode::Utf8 && u.encoding.codepage == -1);
    auto bom = detectAndDecode("\xEF\xBB\xBF" + ru, true, true);           // a BOM wins over detection
    EXPECT(bom.encoding.mode == UniMode::Utf8Bom);
    return "";
}
TEST(ENC_013, "Display names match upstream status bar") {
    EXPECT_EQ(encodingDisplayName({UniMode::Utf8Bom, -1}), std::string("UTF-8-BOM"));
    EXPECT_EQ(encodingDisplayName({UniMode::Utf16LE, -1}), std::string("UTF-16 LE BOM"));
    EXPECT_EQ(encodingDisplayName({UniMode::Utf8, 1251}), std::string("Windows-1251"));
    return "";
}
TEST(EOL_001, "EOL detection uses the first line ending") {
    EXPECT(detectEol("a\r\nb\nc", Eol::LF) == Eol::CRLF);
    EXPECT(detectEol("a\nb\r\n", Eol::CRLF) == Eol::LF);
    EXPECT(detectEol("a\rb", Eol::LF) == Eol::CR);
    EXPECT(detectEol("abc", Eol::CRLF) == Eol::CRLF);
    EXPECT(hasMixedEol("a\r\nb\n"));
    EXPECT(!hasMixedEol("a\nb\n"));
    return "";
}
// ---------------- text operations ----------------
TEST(CASE_001, "UPPERCASE / lowercase incl. non-ASCII") {
    EXPECT_EQ(to::changeCase("Caf\xC3\xA9 d\xC3\xA9j\xC3\xA0", to::Case::Upper), std::string("CAF\xC3\x89 D\xC3\x89J\xC3\x80"));
    EXPECT_EQ(to::changeCase("\xD0\x9F\xD0\xA0\xD0\x98", to::Case::Lower), std::string("\xD0\xBF\xD1\x80\xD0\xB8"));
    return "";
}
TEST(CASE_002, "Proper Case force vs blend (upstream rules incl. apostrophe)") {
    EXPECT_EQ(to::changeCase("hELLO wORLD don't", to::Case::ProperForce), std::string("Hello World Don't"));
    EXPECT_EQ(to::changeCase("hELLO wORLD", to::Case::ProperBlend), std::string("HELLO WORLD"));
    return "";
}
TEST(CASE_003, "Sentence case force/blend and lone i") {
    EXPECT_EQ(to::changeCase("hello WORLD. so i think. ok", to::Case::SentenceForce), std::string("Hello world. So I think. Ok"));
    EXPECT_EQ(to::changeCase("this is i. ok", to::Case::SentenceForce), std::string("This is i. Ok"));  // upstream: lone i only before space/quote
    EXPECT_EQ(to::changeCase("hello WORLD. x", to::Case::SentenceBlend), std::string("Hello WORLD. X"));
    return "";
}
TEST(CASE_004, "iNVERT cASE") {
    EXPECT_EQ(to::changeCase("Hello", to::Case::Invert), std::string("hELLO"));
    return "";
}
TEST(SORT_001, "Lexicographic ascending/descending") {
    std::vector<std::string> l{"b", "a", "C", "c"};
    to::sortLines(l, to::SortMode::Lexicographic, false);
    EXPECT((l == std::vector<std::string>{"C", "a", "b", "c"}));
    to::sortLines(l, to::SortMode::Lexicographic, true);
    EXPECT((l == std::vector<std::string>{"c", "b", "a", "C"}));
    return "";
}
TEST(SORT_002, "Ignore-case sort") {
    std::vector<std::string> l{"b", "A", "a", "C"};
    to::sortLines(l, to::SortMode::LexicographicIgnoreCase, false);
    EXPECT((l == std::vector<std::string>{"A", "a", "b", "C"}));
    return "";
}
TEST(SORT_003, "Integer sort is natural (upstream comparator)") {
    std::vector<std::string> l{"10", "9", "-3", "100", "x2", "x10"};
    to::sortLines(l, to::SortMode::Integer, false);
    EXPECT((l == std::vector<std::string>{"-3", "9", "10", "100", "x2", "x10"}));
    return "";
}
TEST(SORT_004, "Decimal dot / comma sort; empties first ascending") {
    std::vector<std::string> l{"2.5", "", "-1.25", "10"};
    auto r = to::sortLines(l, to::SortMode::DecimalDot, false);
    EXPECT(r.ok);
    EXPECT((l == std::vector<std::string>{"", "-1.25", "2.5", "10"}));
    std::vector<std::string> c{"2,5", "1,25"};
    to::sortLines(c, to::SortMode::DecimalComma, false);
    EXPECT((c == std::vector<std::string>{"1,25", "2,5"}));
    std::vector<std::string> bad{"1.0", "-"};  // "abc" has no admissible prefix -> treated as empty upstream
    auto rb = to::sortLines(bad, to::SortMode::DecimalDot, false);
    EXPECT(!rb.ok && rb.failedLineIndex == 1);
    return "";
}
TEST(SORT_005, "Length sort and reverse") {
    std::vector<std::string> l{"ccc", "a", "bb"};
    to::sortLines(l, to::SortMode::Length, false);
    EXPECT((l == std::vector<std::string>{"a", "bb", "ccc"}));
    to::sortLines(l, to::SortMode::Reverse, false);
    EXPECT((l == std::vector<std::string>{"ccc", "bb", "a"}));
    return "";
}
TEST(SORT_006, "Column-range sort key") {
    std::vector<std::string> l{"x 3", "y 1", "z 2"};
    to::sortLines(l, to::SortMode::Lexicographic, false, 2, 3);
    EXPECT((l == std::vector<std::string>{"y 1", "z 2", "x 3"}));
    return "";
}
TEST(LINE_001, "Remove duplicate / consecutive duplicate / empty lines") {
    std::vector<std::string> l{"a", "b", "a", "b", "b", "", "  "};
    auto d = l; to::removeDuplicateLines(d);
    EXPECT((d == std::vector<std::string>{"a", "b", "", "  "}));
    auto c = l; to::removeConsecutiveDuplicateLines(c);
    EXPECT((c == std::vector<std::string>{"a", "b", "a", "b", "", "  "}));
    auto e = l; to::removeEmptyLines(e, false);
    EXPECT_EQ(e.size(), size_t(6));
    auto e2 = l; to::removeEmptyLines(e2, true);
    EXPECT_EQ(e2.size(), size_t(5));
    return "";
}
TEST(LINE_002, "Trim leading/trailing") {
    EXPECT_EQ(to::trimTrailing(" a \t"), std::string(" a"));
    EXPECT_EQ(to::trimLeading(" \ta "), std::string("a "));
    return "";
}
TEST(LINE_003, "TAB to Space / Space to TAB (upstream algorithm)") {
    EXPECT_EQ(to::tabsToSpaces("a\tb", 4), std::string("a   b"));
    EXPECT_EQ(to::tabsToSpaces("\t\xC3\xA9\tx", 4), std::string("    \xC3\xA9   x"));
    EXPECT_EQ(to::spacesToTabs("        x", 4, true), std::string("\t\tx"));
    EXPECT_EQ(to::spacesToTabs("a   b", 4, false), std::string("a\tb"));
    EXPECT_EQ(to::spacesToTabs("    a    b", 4, true), std::string("\ta    b"));
    return "";
}
TEST(LINE_004, "splitLines / joinLines keep trailing EOL info") {
    bool eol = false;
    auto l = to::splitLines("a\r\nb\nc\n", &eol);
    EXPECT_EQ(l.size(), size_t(3));
    EXPECT(eol);
    auto l2 = to::splitLines("a\n\nb", &eol);
    EXPECT_EQ(l2.size(), size_t(3));
    EXPECT(!eol);
    EXPECT_EQ(to::joinLines({"a", "b"}, "\r\n"), std::string("a\r\nb"));
    return "";
}
TEST(EXT_001, "Extended search escapes") {
    EXPECT_EQ(*to::convertExtended("a\\tb\\r\\n\\x41\\u00e9\\d065\\o101\\b01000010\\\\"),
              std::string("a\tb\r\nA\xC3\xA9" "AAB\\"));
    EXPECT(!to::convertExtended("\\xZZ").has_value());
    return "";
}
// ---------------- hashing ----------------
TEST(HASH_001, "MD5/SHA-1/SHA-256/SHA-512 known vectors") {
    EXPECT_EQ(hashHex(HashAlgorithm::MD5, "abc"), std::string("900150983cd24fb0d6963f7d28e17f72"));
    EXPECT_EQ(hashHex(HashAlgorithm::SHA1, "abc"), std::string("a9993e364706816aba3e25717850c26c9cd0d89d"));
    EXPECT_EQ(hashHex(HashAlgorithm::SHA256, "abc"), std::string("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"));
    EXPECT_EQ(hashHex(HashAlgorithm::SHA512, "abc").substr(0, 16), std::string("ddaf35a193617aba"));
    return "";
}

namespace json = tpp::json;
TEST(JSON_001, "JSON format keeps key order, escapes and numbers; compress; strict errors with position") {
    std::string in = "{\"b\":1,\"a\":[1.50,-2e10,true,null,{}],\"s\":\"x\\\"y\\u00e9\",\"e\":[]}";
    auto f = json::format(in, "  ");
    EXPECT(f.ok);
    EXPECT_EQ(f.text, std::string("{\n  \"b\": 1,\n  \"a\": [\n    1.50,\n    -2e10,\n    true,\n    null,\n    {}\n  ],\n  \"s\": \"x\\\"y\\u00e9\",\n  \"e\": []\n}"));
    auto c = json::compress(f.text);
    EXPECT(c.ok && c.text == in);
    auto bad = json::validate("{\"a\": 1,, \"b\": 2}");
    EXPECT(!bad.ok && bad.errorOffset == 8 && bad.error.find("member name") != std::string::npos);
    EXPECT(!json::validate("[1, 2").ok && !json::validate("{'a': 1}").ok && !json::validate("01").ok && !json::validate("[1] x").ok);
    EXPECT(json::validate("  \"just a string\"  ").ok && json::validate("\xEF\xBB\xBF[]").ok);
    std::string deep(5000, '['); deep += std::string(5000, ']');
    EXPECT(!json::validate(deep).ok);   // no stack overflow
    return "";
}

TEST(JSON_002, "JSON sort keys, JSON to CSV, string escape and unescape") {
    auto s = json::sortKeys("{\"b\":1,\"a\":{\"z\":[{\"y\":1,\"x\":2}],\"c\":null}}", "  ");
    EXPECT(s.ok);
    EXPECT_EQ(s.text, std::string("{\n  \"a\": {\n    \"c\": null,\n    \"z\": [\n      {\n        \"x\": 2,\n        \"y\": 1\n      }\n    ]\n  },\n  \"b\": 1\n}"));
    auto c = json::toCsv("[{\"name\":\"A, B\",\"n\":1},{\"n\":2.5,\"extra\":true,\"q\":\"say \\\"hi\\\"\",\"o\":{\"k\":[1]}}]");
    EXPECT(c.ok);
    EXPECT_EQ(c.text, std::string("name,n,extra,q,o\n\"A, B\",1,,,\n,2.5,true,\"say \"\"hi\"\"\",\"{\"\"k\"\":[1]}\"\n"));
    EXPECT(!json::toCsv("[1,2]").ok && !json::toCsv("{bad").ok);
    const std::string text = "line1\n\"q\"\t\\ \xC3\xA9";
    const std::string lit = json::escapeString(text);
    EXPECT_EQ(lit, std::string("\"line1\\n\\\"q\\\"\\t\\\\ \xC3\xA9\""));
    auto u = json::unescapeString(lit);
    EXPECT(u.ok && u.text == text);
    auto u2 = json::unescapeString("caf\\u00e9 \\ud83d\\ude00");   // quotes optional, surrogate pair
    EXPECT(u2.ok && u2.text == "caf\xC3\xA9 \xF0\x9F\x98\x80");
    EXPECT(!json::unescapeString("\"bad \\q\"").ok);
    return "";
}

TEST(CSV_001, "CSV parse (quotes, delimiters), to JSON and to a Markdown table") {
    EXPECT(tpp::csv::detectDelimiter("a;b;c\n1;2;3") == ';' && tpp::csv::detectDelimiter("a\tb\n") == '\t' && tpp::csv::detectDelimiter("\"x,y\";z") == ';');
    auto rows = tpp::csv::parse("a,\"b \"\"q\"\"\",\"multi\nline\"\r\n1,2,3\n\n", ',');
    EXPECT(rows.size() == 2 && rows[0][1] == "b \"q\"" && rows[0][2] == "multi\nline" && rows[1][2] == "3");
    EXPECT_EQ(tpp::csv::toJson("name,age,ok,id\nAnn,30,true,007\n", "  "),
              std::string("[\n  {\n    \"name\": \"Ann\",\n    \"age\": 30,\n    \"ok\": true,\n    \"id\": \"007\"\n  }\n]"));
    EXPECT_EQ(tpp::csv::toMarkdown("h1,h2\na|b,c\n"), std::string("| h1 | h2 |\n| --- | --- |\n| a\\|b | c |\n"));
    return "";
}

TEST(DIFF_001, "Line and character differences: insert, delete, change, identical, empty, large") {
    using tpp::diff::Hunk;
    auto h = tpp::diff::diffLines("a\nb\nc\nd\n", "a\nB\nc\nd\ne\n");
    EXPECT(h.size() == 2 && h[0].aStart == 1 && h[0].aCount == 1 && h[0].bStart == 1 && h[0].bCount == 1);
    EXPECT(h[1].aStart == 4 && h[1].aCount == 0 && h[1].bStart == 4 && h[1].bCount == 1);
    EXPECT(tpp::diff::diffLines("same\r\ntext", "same\ntext").empty());                     // line ends do not count
    auto d = tpp::diff::diffLines("x\ny\nz", "x\nz");
    EXPECT(d.size() == 1 && d[0].aStart == 1 && d[0].aCount == 1 && d[0].bCount == 0);
    EXPECT(tpp::diff::diffLines("", "one\ntwo").size() == 1);
    EXPECT(tpp::diff::diffLines("a  b", "a b", true).empty() && !tpp::diff::diffLines("a  b", "a b").empty());
    auto c = tpp::diff::diffChars("caf\xC3\xA9 latte", "caf\xC3\xA8 latte!");
    EXPECT(c.size() == 2 && c[0].aStart == 3 && c[0].aCount == 2 && c[0].bCount == 2 && c[1].bStart == 11 && c[1].bCount == 1);
    // 20,000 lines with scattered edits: every reported hunk really differs and the rest matches
    std::string A, B;
    for (int i = 0; i < 20000; ++i) { A += "line " + std::to_string(i) + "\n"; B += (i % 997 == 0 ? "edited " : "line ") + std::to_string(i) + "\n"; }
    auto big = tpp::diff::diffLines(A, B);
    EXPECT(big.size() == 21);
    for (auto& x : big) EXPECT(x.aCount == 1 && x.bCount == 1 && x.aStart == x.bStart && x.aStart % 997 == 0);
    return "";
}

TEST(CSV_002, "CSV align pads fields so delimiters line up; shrink takes the padding off; quotes and line ends kept") {
    const std::string in = "id,name,city\r\n1,\"Smith, J\",Paris\r\n22,Al,\r\n";
    const std::string a = tpp::csv::align(in, ',');
    EXPECT_EQ(a, std::string("id, name      , city\r\n1 , \"Smith, J\", Paris\r\n22, Al        , \r\n"));
    EXPECT_EQ(tpp::csv::shrink(a, ','), std::string("id,name,city\r\n1,\"Smith, J\",Paris\r\n22,Al,\r\n"));
    auto f = tpp::csv::fieldsOfLine("a,\"b,c\",d", ',');
    EXPECT(f.size() == 3 && f[1].first == 2 && f[1].second == 7);
    EXPECT_EQ(tpp::csv::align("\xC3\xA9,x\nab,y", ','), std::string("\xC3\xA9 , x\nab, y"));   // widths count characters
    return "";
}

TEST(FMT_001, "Code Formatter: SQL clauses and lists, sub-queries, CSS declarations and minify, HTML indentation with raw blocks kept") {
    namespace f = tpp::format;
    EXPECT_EQ(f::sql("select a, count(*) as n from t where x = 'a, b' and y between 1 and 2 order by n desc", "  "),
              std::string("SELECT\n  a,\n  COUNT(*) AS n\nFROM\n  t\nWHERE\n  x = 'a, b'\n  AND y BETWEEN 1 AND 2\nORDER BY\n  n DESC"));
    EXPECT_EQ(f::sql("select * from t where id in (select uid from s)", "  "),
              std::string("SELECT\n  *\nFROM\n  t\nWHERE\n  id IN (\n    SELECT\n      uid\n    FROM\n      s\n  )"));
    EXPECT_EQ(f::sql("SELECT a FROM t -- note\nWHERE b = 1", "  "), std::string("SELECT\n  a\nFROM\n  t -- note\nWHERE\n  b = 1"));
    EXPECT_EQ(f::css("a,b{color:red;background:url(data:x;y)}@media (x){.c{margin:0}}", "  "),
              std::string("a, b {\n  color: red;\n  background: url(data:x;y);\n}\n\n@media (x) {\n  .c {\n    margin: 0;\n  }\n}"));
    EXPECT_EQ(f::cssMinify("a , b { color : red ; }\n/* x */ /*! keep */ .c > d { content: \"a ; b\" }"), std::string("a,b{color:red}/*! keep */.c>d{content:\"a ; b\"}"));
    EXPECT_EQ(f::html("<div><p>Hi <b>you</b> there</p><ul><li>1<li>2</ul><pre> a\n  b</pre></div>", "  "),
              std::string("<div>\n  <p>Hi <b>you</b> there</p>\n  <ul>\n    <li>1</li>\n    <li>2</li>\n  </ul>\n  <pre> a\n  b</pre>\n</div>"));
    return "";
}

namespace json = tpp::json;
int main(int argc, char** argv) {
    int failed = 0;
    std::string json = "{\"suite\":\"unit\",\"results\":[";
    bool first = true;
    for (auto& t : registry()) {
        std::string err;
        try { err = t.fn(); } catch (const std::exception& e) { err = std::string("exception: ") + e.what(); }
        bool ok = err.empty();
        if (!ok) ++failed;
        std::printf("%s %-10s %s%s%s\n", ok ? "PASS" : "FAIL", t.id.c_str(), t.name.c_str(), ok ? "" : "  -> ", err.c_str());
        auto esc = [](std::string s) { std::string o; for (char c : s) { if (c == '"' || c == '\\') o.push_back('\\'); if (static_cast<unsigned char>(c) >= 0x20) o.push_back(c); } return o; };
        json += std::string(first ? "" : ",") + "{\"id\":\"" + t.id + "\",\"name\":\"" + esc(t.name) + "\",\"pass\":" + (ok ? "true" : "false") + ",\"detail\":\"" + esc(err) + "\"}";
        first = false;
    }
    json += "]}";
    if (argc > 1) { std::ofstream(argv[1]) << json; }
    std::printf("\n%zu tests, %d failed\n", registry().size(), failed);
    return failed ? 1 : 0;
}
