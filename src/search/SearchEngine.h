// Textpad++ — search engine (upstream: FindReplaceDlg.cpp processFindNext / processRange /
// processAll). Runs on any ScintillaView (visible or the hidden worker), so Normal, Extended
// and Boost regular-expression modes behave identically everywhere. GPL-3.0-or-later.
#pragma once

#import "app/Sci.h"
#include "BoostRegexSearch.h"
#include <string>
#include <vector>

namespace tpp::search {

enum class Mode { Normal = 0, Extended = 1, Regex = 2 };

struct Options {
    std::string find;          // as typed (UTF-8)
    std::string replace;       // as typed (UTF-8)
    Mode mode = Mode::Normal;
    bool matchCase = false;
    bool wholeWord = false;
    bool wrap = true;
    bool backward = false;
    bool inSelection = false;
    bool dotMatchesNewline = false;
    bool bookmarkLine = false;     // Mark tab
    bool purge = false;            // Mark tab: "Purge for each search"
};

struct Prepared {
    std::string find, replace;
    int flags = 0;
    bool ok = true;
    std::string error;
};

Prepared prepare(const Options& o);

struct FindResult {
    bool found = false;
    sptr_t start = -1, end = -1;
    bool wrapped = false;
    bool regexError = false;
    std::string error;
};

enum class NextType { FindNext, ReplaceNext, FindNextForReplace };

// Search from the current selection, honouring direction and wrap-around; selects the match.
FindResult findNext(ScintillaView* v, const Options& o, NextType type = NextType::FindNext, bool select = true);

struct Match { sptr_t start, end, line; };
// All matches within [from, to) (to = -1 -> document end). Returns false on a regex error.
bool findAll(ScintillaView* v, const Options& o, sptr_t from, sptr_t to, std::vector<Match>& out, std::string* error = nullptr);

// Replace all matches within [from, to) as one undo action. Returns count, -1 on regex error.
long replaceAll(ScintillaView* v, const Options& o, sptr_t from, sptr_t to, std::string* error = nullptr);

// Replace the current selection when it is a match, then find the next one.
struct ReplaceResult { bool replaced = false; FindResult next; };
ReplaceResult replaceOne(ScintillaView* v, const Options& o);

// Mark all (indicator + optional bookmark). Returns count, -1 on error.
long markAll(ScintillaView* v, const Options& o, int indicator, sptr_t from, sptr_t to, std::string* error = nullptr);

std::string regexErrorMessage(ScintillaView* v);

} // namespace tpp::search
