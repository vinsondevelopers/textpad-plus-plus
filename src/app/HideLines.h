// Textpad++ — View > Hide Lines (port of upstream ScintillaEditView::hideLines / hidelineMarkerClicked /
// hideMarkedLines / showHiddenLines / restoreHiddenLines). Hidden sections are delimited by the
// MARK_HIDELINESBEGIN / MARK_HIDELINESEND markers, which live in the document; line visibility lives in
// the view, so a view re-hides the sections when it shows the document again. GPL-3.0-or-later.
#pragma once
#import "app/Sci.h"

namespace tpp::hidelines {

inline void hideMarkedLines(ScintillaView *v, sptr_t searchStart, bool toEndOfDoc) {
    const sptr_t maxLines = SCI(v, SCI_GETLINECOUNT);
    sptr_t startHiding = searchStart;
    bool isInSection = false;
    for (sptr_t i = searchStart; i < maxLines; ++i) {
        const sptr_t state = SCI(v, SCI_MARKERGET, i);
        if (state & (1 << TPP_MARK_HIDELINESEND)) {
            if (isInSection) {
                SCI(v, SCI_HIDELINES, startHiding, i - 1);
                if (!toEndOfDoc) return;
            }
            isInSection = false;
        }
        if (state & (1 << TPP_MARK_HIDELINESBEGIN)) { isInSection = true; startHiding = i + 1; }
    }
}

inline void showHiddenLines(ScintillaView *v, sptr_t searchStart, bool toEndOfDoc, bool doDelete) {
    const sptr_t maxLines = SCI(v, SCI_GETLINECOUNT);
    sptr_t startShowing = searchStart;
    bool isInSection = false;
    for (sptr_t i = searchStart; i < maxLines; ++i) {
        const sptr_t state = SCI(v, SCI_MARKERGET, i);
        if ((state & (1 << TPP_MARK_HIDELINESBEGIN)) && !isInSection) {
            isInSection = true;
            if (doDelete) SCI(v, SCI_MARKERDELETE, i, TPP_MARK_HIDELINESBEGIN);
            else startShowing = i + 1;
        } else if (state & (1 << TPP_MARK_HIDELINESEND)) {
            if (doDelete) {
                SCI(v, SCI_MARKERDELETE, i, TPP_MARK_HIDELINESEND);
                if (!toEndOfDoc) return;
                isInSection = false;
            } else if (isInSection) {
                if (startShowing >= i) {   // fold skipping passed the close marker
                    if (!toEndOfDoc) return;
                    isInSection = false;
                    continue;
                }
                SCI(v, SCI_SHOWLINES, startShowing, i - 1);
                if (!toEndOfDoc) return;
                isInSection = false;
            }
        }
        const sptr_t level = SCI(v, SCI_GETFOLDLEVEL, i);
        if ((level & SC_FOLDLEVELHEADERFLAG) && isInSection && SCI(v, SCI_GETFOLDEXPANDED, i))
            SCI(v, SCI_SHOWLINES, startShowing, i);
    }
}

// Re-apply the hidden sections of the document now shown in the view (upstream restoreHiddenLines).
inline void restoreHiddenLines(ScintillaView *v) {
    sptr_t line = 0;
    while (line != -1) {
        sptr_t lineBegin = SCI(v, SCI_MARKERNEXT, line, 1 << TPP_MARK_HIDELINESBEGIN);
        sptr_t lineEnd = SCI(v, SCI_MARKERNEXT, line, 1 << TPP_MARK_HIDELINESEND);
        if (lineBegin != -1 && lineEnd != -1 && lineBegin != lineEnd) {
            if (lineEnd - lineBegin > 1) SCI(v, SCI_HIDELINES, lineBegin + 1, lineEnd - 1);
            lineBegin = SCI(v, SCI_MARKERNEXT, lineEnd, 1 << TPP_MARK_HIDELINESBEGIN);
            lineEnd = SCI(v, SCI_MARKERNEXT, lineEnd, 1 << TPP_MARK_HIDELINESEND);
            line = lineEnd == -1 ? -1 : lineEnd + ((lineBegin == lineEnd) ? 0 : 1);
        } else if (lineBegin != -1 && lineEnd != -1 && lineBegin == lineEnd) {   // end and begin markers on one line
            lineEnd = SCI(v, SCI_MARKERNEXT, line + 1, 1 << TPP_MARK_HIDELINESEND);
            if (lineEnd != -1 && lineEnd - lineBegin > 1) SCI(v, SCI_HIDELINES, lineBegin + 1, lineEnd - 1);
            line = lineEnd;
        } else {
            line = -1;
        }
    }
}

// Hide the selected lines; returns the begin-marker line (or -1). Adjacent hidden sections merge.
inline sptr_t hideLines(ScintillaView *v) {
    sptr_t startLine = SCI(v, SCI_LINEFROMPOSITION, SCI(v, SCI_GETSELECTIONSTART));
    sptr_t endLine = SCI(v, SCI_LINEFROMPOSITION, SCI(v, SCI_GETSELECTIONEND));
    const sptr_t nbLines = SCI(v, SCI_GETLINECOUNT);
    if (nbLines < 3) return -1;
    if (!startLine) ++startLine;
    if (endLine == nbLines - 1) --endLine;
    if (startLine > endLine) return -1;
    int scope = 0;
    bool recentMarkerWasOpen = false;
    auto removeMarker = [&](sptr_t line, int mask) {
        const sptr_t state = SCI(v, SCI_MARKERGET, line) & mask;
        if (state & (1 << TPP_MARK_HIDELINESEND)) { SCI(v, SCI_MARKERDELETE, line, TPP_MARK_HIDELINESEND); recentMarkerWasOpen = false; --scope; }
        if (state & (1 << TPP_MARK_HIDELINESBEGIN)) { SCI(v, SCI_MARKERDELETE, line, TPP_MARK_HIDELINESBEGIN); recentMarkerWasOpen = true; ++scope; }
    };
    sptr_t startMarker = startLine - 1, endMarker = endLine + 1;
    removeMarker(startMarker, 1 << TPP_MARK_HIDELINESBEGIN);
    for (sptr_t i = startLine; i <= endLine; ++i) removeMarker(i, (1 << TPP_MARK_HIDELINESBEGIN) | (1 << TPP_MARK_HIDELINESEND));
    removeMarker(endMarker, 1 << TPP_MARK_HIDELINESEND);
    if (scope == 0 && recentMarkerWasOpen) {
        while (scope == 0 && startMarker > 0) removeMarker(--startMarker, 1 << TPP_MARK_HIDELINESBEGIN);
        while (scope != 0 && endMarker < nbLines - 1) removeMarker(++endMarker, 1 << TPP_MARK_HIDELINESEND);
    } else {
        while (scope < 0 && startMarker > 0) removeMarker(--startMarker, 1 << TPP_MARK_HIDELINESBEGIN);
        while (scope > 0 && endMarker < nbLines - 1) removeMarker(++endMarker, 1 << TPP_MARK_HIDELINESEND);
    }
    SCI(v, SCI_MARKERADD, startMarker, TPP_MARK_HIDELINESBEGIN);
    SCI(v, SCI_MARKERADD, endMarker, TPP_MARK_HIDELINESEND);
    return startMarker;
}

// Click on a hide-lines marker in the symbol margin: which section to show (begin-marker line), or -1.
inline sptr_t sectionForMarkerClick(ScintillaView *v, sptr_t lineNumber) {
    sptr_t state = SCI(v, SCI_MARKERGET, lineNumber);
    const bool openPresent = state & (1 << TPP_MARK_HIDELINESBEGIN);
    const bool closePresent = state & (1 << TPP_MARK_HIDELINESEND);
    if (!openPresent && !closePresent) return -1;
    if (openPresent) return lineNumber;   // two overlapping markers: open the lower section
    for (sptr_t i = lineNumber - 1; i >= 0; --i)
        if (SCI(v, SCI_MARKERGET, i) & (1 << TPP_MARK_HIDELINESBEGIN)) return i;
    SCI(v, SCI_MARKERDELETE, lineNumber, TPP_MARK_HIDELINESEND);   // close without open: drop it
    return -2;
}

}  // namespace tpp::hidelines
