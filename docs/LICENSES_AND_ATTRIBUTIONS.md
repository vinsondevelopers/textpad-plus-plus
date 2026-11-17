# Licenses and Attributions

## Textpad++
Textpad++ is free software under the **GNU General Public License v3 or later** (`LICENSE`). It adapts code and data from Notepad++, so distributions must ship the complete corresponding source (this repository) and keep all notices.

## Upstream and third-party components
| Component | Used for | License | Location |
|---|---|---|---|
| **Notepad++** v8.9.9.1 — © Don Ho and contributors | Ported algorithms (case conversion, sorters, TAB/space conversion, search flags, change-history navigation, marked-line deletion, extended escapes), menu/shortcut/language tables (generated), `langs.model.xml`, `stylers.model.xml`, `DarkModeDefault.xml`, standard toolbar bitmaps and tab-bar icons, `LexUser`/`LexSearchResult` lexers, Boost regex adapter | GPL v3 (upstream `LICENSE` adds "clarifications and exceptions"; copy in `docs/upstream/Notepad++-LICENSE.txt`) | `src/core`, `src/generated`, `resources/`, `third_party/boostregex/*.cxx` |
| **Scintilla** 5.6.9 (incl. Cocoa platform layer) — © Neil Hodgson | Editing engine | Historical Permission Notice and Disclaimer–style "License for Scintilla and SciTE" (permissive) | `third_party/scintilla` (`License.txt`) |
| **Lexilla** 5.5.5 — © Neil Hodgson | Lexers | same license as Scintilla | `third_party/lexilla` |
| **Boost.Regex** (header-only, standalone) | Regular expressions (same engine as upstream) | Boost Software License 1.0 | `third_party/boostregex/boost`, `LICENSE_1_0.txt` |
| **Markdown-plus-plus** UDLs — © Edditoria | Preinstalled "Markdown (preinstalled)" User Defined Languages (light and dark), copied unmodified from the Notepad++ v8.9.9.1 distribution | MIT (`resources/licenses/markdown-plus-plus-MIT.txt`) | `resources/data/userDefineLangs/` |
| Notepad++ API files (`autoCompletion/*.xml`, from `PowerEditor/installer/APIs`) | Function completion and parameter hints | GPL v3, as part of Notepad++ (some files carry their authors' names) | `resources/data/autoCompletion/` |
| Notepad++ bundled themes (`PowerEditor/installer/themes`) | Style Configurator themes | each file keeps its own header: MIT-style notices (Bespin, Black board, Choco, Mono Industrial, Monokai, Plastic Code Wrap, Twilight, DansLeRuSH-Dark…), GPL (DarkModeDefault), others as stated in their headers | `resources/data/themes/` (unmodified) |
| **uchardet** (Mozilla universal charset detector, the copy bundled in Notepad++ `PowerEditor/src/uchardet`) | Preferences > MISC. > Autodetect character encoding | tri-licensed MPL 1.1 / GPL 2.0 or later / LGPL 2.1 or later; used here under the GPL (`resources/licenses/uchardet-LICENSE.txt`) | `third_party/uchardet` (unmodified) |
| Notepad++ Function List rules (`PowerEditor/installer/functionList/*.xml`, `overrideMap.xml`) | Function List parsers | GPL v3, as part of Notepad++ (files keep their authors' notices) | `resources/data/functionList/` |
| Notepad++ default `contextMenu.xml` (from `CONTEXTMENU_XML_CONTENT`) | Editor context menu | GPL v3 | `resources/data/contextMenu.xml` |
| Notepad++ Character Panel tables (`asciiListView.cpp`) and plugin messages (`Notepad_plus_msgs.h`) | Character Panel names / HTML entities; the plugin SDK header | GPL v3 | `src/generated/NppAsciiTables.inc`, `sdk/TextpadPlusPlusPlugin.h` (generated) |
| Notepad++ interface language files (`PowerEditor/installer/nativeLang/*.xml`) | Preferences > General > Localization | GPL v3; modified: the product name replaced, upstream links removed | `resources/data/nativeLang/` |
| Notepad++ quotes (`Notepad_plus.cpp` `quotes[]`, those by named people) | the `-qn` command-line option | GPL v3 | `src/generated/QuoteTable.inc` |
| Apple SF Symbols | the "Colourful" toolbar icon set, drawn at run time from the system | Apple's SF Symbols licence (use in apps on Apple platforms; not bundled) | — |
| OEM 720 code page table | Encoding > Arabic > OEM 720 | factual mapping data, generated from Python's `cp720` codec (itself generated from Windows' code page data) | `src/core/Encoding.cpp` |
| Apple frameworks (AppKit, CommonCrypto, libiconv) | Platform | system libraries | — |

Local modifications to third-party code (each marked "Textpad++" in the source):
- `third_party/lexilla/lexers/LexUser.cxx` — replaced `<windows.h>` with `<cstring>` and added a portable `_itoa` shim.
- `third_party/scintilla/cocoa/ScintillaView.mm` — a file-drop hook (`TPScintillaFileDropHandler`: files dropped on the editor open as documents) and a typed-text filter (`TPScintillaInsertTextFilter`, for "Prevent control character typing").
- `third_party/scintilla/include/Scintilla.h` — Notepad++'s C++-only `SearchResultMarkings` block is wrapped in `#ifdef __cplusplus`, so C plugins can include the header.

All license texts are copied into `Textpad++.app/Contents/Resources/licenses/` by the build.

## Trademarks and identity
- "Notepad++" and its chameleon logo belong to the Notepad++ project. Textpad++ does not use the logo; the application icon is original artwork (`scripts/make_icon.m`). The name "Notepad++" appears only where the upstream project, its manual, site, forum or UDL collection is referenced (labelled "upstream"), and in attribution.
- Textpad++ is **not** an official Notepad++ release and is not affiliated with or endorsed by the Notepad++ project (stated in About).
- **Risk to review before public distribution:** "TextPad" is the name of an established commercial Windows text editor (Helios Software Solutions). "Textpad++" may be considered confusingly similar. A trademark search/legal review is recommended before publishing under this name.

## Assets
Toolbar bitmaps (`resources/icons/toolbar/*.bmp`) and tab-bar icons (`resources/icons/tabbar/*.ico`) are copied unmodified from the Notepad++ GPL source tree (`PowerEditor/src/icons/standard/`). Fluent UI toolbar icons (`resources/icons/fluent/{light,dark}/…`) and the dark tab-bar icons (`resources/icons/tabbar-dark/`) are copied unmodified from the same tree (`PowerEditor/src/icons/{light,dark}/toolbar/` and `PowerEditor/src/icons/dark/tabbar/`) under its GPL terms.
