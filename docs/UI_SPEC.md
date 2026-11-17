# Textpad++ UI Specification

Values marked **(src)** come from the Notepad++ v8.9.9.1 source; **(est.)** are estimates made in this increment and still need measurement against Windows screenshots at 100 % / 150 % / 200 % scaling.

## Units
Windows layout px at 96 dpi = macOS points at 1×. Font sizes: Windows *points* are converted with ×96/72 (Courier New 10 pt → 13.33 pt on macOS) so text has the same pixel height **(src: stylers default 10 pt; conversion is ours)**.

## Main window (top to bottom)
| Region | Spec | Source |
|---|---|---|
| Title | `*<full path or "new N"> - Textpad++` (`*` when modified) | upstream title format (src), app name changed |
| Menu bar | macOS menu bar, upstream order: File, Edit, Search, View, Encoding, Language, Settings, Tools, Macro, Run, Plugins, Window, ?. Optional in-window strip (height 22) with the same menus and ＋ ▼ ✕ at the right | `IDR_M30_MENU` (src) |
| Toolbar | height 28; 16×16 "Standard icons: small" bitmaps, 24-pt pitch, separators 8 pt; RGB(192,192,192) is transparent; toggles show a light-blue pressed state | icons + order: `toolBarIcons[]`, `LR_LOADTRANSPARENT` (src); pitch (est.) |
| Tab bar | height 22 (+3 pt indicator), min width 45, 16×16 state icon, 11×11 close button, 5-pt padding | `NppConstants.h` g_TabHeight/g_TabWidth/g_TabCloseBtnSize/g_TabIconSize (src) |
| Active tab | white, top indicator `FAAA3C` focused / `FFCAB0` unfocused, text `000000` | stylers "Active tab …" (src) |
| Inactive tab | text `808080`, background grey; tab colours 1–5 `F3F0CB DBF3CB CBDBF3 F3DBCB F3CBEE` | stylers (src) |
| Editor | Scintilla; margins: line numbers (dynamic width, `808080` on `E4E4E4`), symbol 16 pt (`E0E0E0`), fold 14 pt box tree (`808080`/`F3F3F3`, active `FF0000`), change history 9 pt | stylers + `_SC_MARGE_*` (src); widths (est.) |
| Current line | background `E8E8FF`; caret `8000FF`, width 1 | stylers (src) |
| Selection | `C0C0C0` | stylers (src) |
| Status bar | height 22; parts: doc type (rest) / 220 / 260 / 110 / 120 / 45 | `Notepad_plus.cpp` setPartWidth (src) |
| Status texts | `length : N    lines : N`, `Ln : N    Col : N    Pos : N` (or `Sel : chars \| lines`), `Windows (CR LF)`/`Unix (LF)`/`Macintosh (CR)`, encoding menu name, `INS`/`OVR` | (src; upstream's current English strings use "length: " without the space before the colon in some builds — to be confirmed against a v8.9.9.1 screenshot) |
| Search results | bottom panel, header "Search results - (N hits)", searchResult lexer styles | (src styles; layout est.) |

## Indicators (Scintilla indicator ids = upstream style ids)
Find Mark 31 (`FF0000`), Smart highlight 29 (`00FF00`), incremental/Find-dialog 28/30 (`0080FF`), tag match 27, tag attribute 26, Mark styles 1–5 = 25…21 (`00FFFF FF8000 FFFF00 8000FF 008000`); `INDIC_ROUNDBOX`, alpha 100, drawn under text (src).

## Dialogs
Find dialog: segmented tabs Find / Replace / Find in Files / Mark, controls and labels as upstream ("Find what :", "Replace with :", "Backward direction", "Match whole word only", "Match case", "Wrap around", "Search Mode", ". matches newline", "In selection", "Bookmark line", "Purge for each search", "Filters :", "Directory :", "Follow current doc.", "In all sub-folders", "In hidden folders"), status line coloured red/blue/green per stylers "Find status" (src). Layout pixel positions (est.).

## Visual verification
`Textpad++ --snapshot out.png file…` renders the content view (toolbar, tabs, editor, status bar) to PNG without screen-recording permission. Stage 8 will compare these against Windows reference screenshots per region; the macOS title bar and menu bar are system-drawn and excluded from pixel comparisons.

## Known visual deviations (see KNOWN_DIFFERENCES.md)
macOS title bar and global menu bar (the in-window strip is optional); system font for tabs/status bar (Segoe UI on Windows). Dark chrome follows Preferences > Dark Mode (Follow macOS / Light / Dark) with upstream dark tab-bar and Fluent toolbar icons.

## Preferences window
Left page list with the 24 upstream pages in upstream order (General … MISC.); the right side shows the selected page's groups, check boxes, radio groups, pop-ups, numeric fields, sliders and path fields with upstream labels. Changes apply immediately (no OK/Apply), as upstream does. Options that cannot work on macOS or depend on unbuilt features are disabled, with the reason in grey after the label. Rendered for review with `TEXTPAD_SNAPSHOT_PANEL=prefs:<page> Textpad++ --snapshot out.png`.

## User Defined Language dialog
A floating panel (upstream can also dock it). Top row: User language pop-up, Create new… / Save as… / Rename / Remove / Import… / Export…; Ext. field, Ignore case, Apply to current document. Four tabs with upstream labels and fields: Folder & Default, Keywords Lists (8 groups with Prefix mode and Styler), Comment & Number, Operators & Delimiters. Each Styler opens font name/size, bold/italic/underline, foreground/background colours with "transparent" switches and the nesting check boxes.

## Style Configurator
Upstream WordStyleDlg layout: Select theme; left box with Language (Global Styles + every lexer), Style list, Default ext. + User ext.; right box with the style name, Colour Style (foreground / background), Font Style (name, size, bold, italic, underline), Default keywords + User-defined keywords for keyword styles, and the seven "Force … for all styles" check boxes for Global override; "Go to settings" for styles that have a Preferences page; Save & Close / Cancel. Changes preview immediately; Cancel restores the theme.

## Shortcut Mapper
Five tabs (Main menu, Macros, Run commands, Plugin commands, Scintilla commands), Name / Shortcut / Category columns, conflicts in red, the conflict line under the grid ("No shortcut conflicts for this item." / "CONFLICT FOUND! …"), Filter, Modify / Clear / Delete / Close. Modify opens the shortcut editor: Name (macros and Run commands), Ctrl / Alt / Shift (+ Control in the macOS scheme) and the key list.

## Panels
Docked left or right of the editors (default sides as upstream: Document List, Function List, Folder as Workspace and Project Panels left; Document Map, Character Panel and Clipboard History right). Each dock has a header with the panel title and a close button, and a tab strip when it holds several panels. Function List: search field, sort toggle, reload, tree with the file as root. Folder as Workspace: Unfold all / Fold all / Locate current file buttons. Project Panels: Workspace and Edit pull-down menus.

## Incremental Search
A bar above the status bar (or below the toolbar): ✕, top/bottom toggle, "Find:", < >, Match case, Highlight all, Count, and the status text ("Phrase not found", "Reached end of page, continued from top", "n/total").

## Document Peeker
A borderless view of the hovered tab's document at zoom −10, below the tab, sized to the editor's proportions (upstream `DocumentPeeker`).

## Find Characters in Range
Upstream findCharsInRange.rc: Non-ASCII (128–255) / ASCII (0–127) / Custom range with two fields, Direction (Up / Down, default Down), Wrap around (off), Find and Close.

