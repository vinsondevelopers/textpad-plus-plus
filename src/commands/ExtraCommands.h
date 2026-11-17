// Textpad++ — command ids of features the Windows editor does not have (24000+, clear of upstream IDM_* values,
// plugin commands 22000+ and NPPM_ALLOCATECMDID 23000+). GPL-3.0-or-later.
#pragma once

enum {
    IDM_TP_LIVE_PREVIEW = 24001,      // View > Live Preview (Markdown / HTML)
    IDM_TP_COMPARE = 24010,           // Plugins-free Compare: View > Compare > ...
    IDM_TP_COMPARE_CLEAR = 24011,
    IDM_TP_COMPARE_NEXT = 24012,
    IDM_TP_COMPARE_PREV = 24013,
    IDM_TP_COMMAND_PALETTE = 24020,   // Tools-like: View > Command Palette...
    IDM_TP_GIT_MARKERS = 24040,       // View > Git Change Markers
    IDM_TP_GIT_NEXT = 24041,
    IDM_TP_GIT_PREV = 24042,
    IDM_TP_CSV_RAINBOW = 24050,       // View > CSV Rainbow Columns
    IDM_TP_CSV_ALIGN = 24051,         // Edit > CSV > Align Columns
    IDM_TP_CSV_SHRINK = 24052,        // Edit > CSV > Shrink Columns
    IDM_TP_SNIPPETS = 24060,          // Settings > Snippets: Tab expands
    IDM_TP_SNIPPETS_EDIT = 24061,     // Settings > Edit Snippets...
    IDM_TP_MODERN_UI = 24070,         // View > Modern Look
};
