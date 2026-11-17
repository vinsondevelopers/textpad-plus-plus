# Known Differences from Windows Notepad++ v8.9.9.1

Each item is either a deliberate macOS adaptation, a platform limitation, or work not done yet (also tracked in FEATURE_MATRIX.md).

## Platform adaptations (deliberate)
| Area | Notepad++ (Windows) | Textpad++ (macOS) | Why |
|---|---|---|---|
| Menus | In-window menu bar | macOS global menu bar with the same hierarchy, labels and ids; extra "Textpad++" app menu. Optional Windows-style menu bar inside the window (Preferences > General > Menu) with the ＋ ▼ ✕ shortcuts; F10 (or ⌥ alone with "Hide") enters menu mode: ←/→, Return, the upstream mnemonic letters, Esc. ⌥ + letter is not used because it types accented characters on macOS. The "?" menu is titled **Help** | macOS convention |
| Shortcuts | Ctrl-based | Default "macOS" scheme maps Ctrl→⌘, Alt→⌥. Combos macOS reserves keep **Control**: Ctrl+Q (toggle comment), Ctrl+Shift+Q, Ctrl+Space (completion), Ctrl+Tab, Ctrl+Shift+3/4/5, Ctrl+` | Spotlight, Quit, screenshots and app switching would swallow them. A "Windows" scheme (Ctrl = ⌃ everywhere) is in Preferences |
| ⌘H, ⌘M | — | Replace and Mark (as Ctrl+H / Ctrl+M upstream); "Hide Textpad++" has no shortcut | keep documented Notepad++ workflow |
| Caret navigation | Ctrl+←/→ word, Home/End | Scintilla Cocoa's macOS bindings (⌥←/→ word, ⌘←/→ line) | native text navigation on macOS |
| New document EOL | Windows (CR LF) | Unix (LF) (Preferences) | macOS convention |
| "ANSI" | System ANSI code page | Windows-1252 by default (Preferences can choose 1250–1258) | macOS has no system ANSI code page |
| Convert to ANSI | Unrepresentable characters replaced immediately | Text kept; a warning listing the count appears at save time and the user may cancel | avoids silent data loss |
| Open Containing Folder | Explorer / cmd / PowerShell | Finder / Terminal / PowerShell for macOS (`pwsh`) in Terminal; the PowerShell item is disabled when `pwsh` is not installed | platform |
| Move to Recycle Bin | Recycle Bin | Trash | platform |
| Read-Only Attribute in Windows | file attribute | POSIX owner-write bit | platform |
| View Current File in IE | Internet Explorer | Safari | platform |
| Run… | `ShellExecute` | `/bin/sh -c` with shell-quoted `$(…)` variables | no cmd.exe on macOS |
| Font sizes | points at 96 dpi | ×96/72 so pixels match | different point definitions |
| Multi-instance | `-multiInst`, "Move/Open in New Instance", mono-instance forwarding | same options: a second Textpad++ process; in mono-instance mode a new launch hands its arguments to the running one (distributed notification). A second instance never reads or writes session.xml / backups | Finder always reuses the running app, so "Always in multi-instance mode" applies to command-line launches |
| Plugins | Win32 DLLs | native `.tpplugin` bundles with the same entry points and NPPM/NPPN numbers, UTF-8 strings and `NppData.sendMessage` instead of `SendMessage` (docs/PLUGINS.md); docking dialogs take an NSView, toolbar icons NSImages; menu-handle messages return 0; Windows DLLs cannot load. Import plugin(s) loads a new plugin at once (upstream asks for a restart). Plugins Admin's Available / Updates tabs read a JSON list from the address built in with UPDATE_URL (no public list of Mac plugins exists yet). A plugin that crashes with a bad memory access ends Textpad++ (upstream catches it with SEH) | binary incompatibility |
| Backup folder | `nppBackup` next to the file | `TextpadBackup` next to the file (same simple `.bak` / verbose `.<date>_<time>.bak` names) | product identity |
| Delimiter selection | Ctrl+double-click | ⌘+double-click | Ctrl+click is the macOS secondary click |
| Clickable links | double-click opens the URL | double-click **or** ⌘-click opens it | ⌘-click is the macOS convention for links in editors |
| Dark Mode | Light / Dark / Follow Windows, with colour tones | Follow macOS / Light / Dark with the same tones (upstream colour offsets) and Customized colours; loads `DarkModeDefault.xml` | Windows' Follow-system becomes Follow macOS |
| File Association | registry entries per extension | sets Textpad++ as the macOS default app for each listed extension (`NSWorkspace`); undone in Finder > Get Info > Open with | no registry; untested automatically because it changes system settings |
| Preferences options that cannot apply | — | shown **disabled** with the reason next to them, never as working controls: rendering mode, touchpad scrolling workaround | platform |
| Product name | "Notepad++" in menus, About, data files | the name appears nowhere in the application (menus, dialogs, bundled themes / language files, the binary); the Help menu's four links to the upstream web sites and the UDL-collection link are removed. The original authors' copyright notice stays in About and in the licence notes, as the GPL requires. Configuration files keep the `<NotepadPlus>` root tag so files from the Windows editor still import | by request |
| Interface languages | menus and dialogs | the 96 upstream language files translate menus, sub-menus and command labels, and dialog controls whose English text matches a string of english.xml (buttons, labels, tabs, titles); Textpad++'s own new dialogs stay English | upstream keys dialog strings by Windows control IDs |
| Large files | read whole into memory | files from 32 MB are memory-mapped and streamed into the editor in the background (progress, Cancel), saved in chunks; a growing log being monitored gets only its new bytes | responsiveness with multi-GB logs |
| Toolbar icons | Fluent UI / Standard | a "Colourful" set (SF Symbols, two-tone) is the default; Fluent and Standard sets remain | requested look |
| System tray | notification-area icon | menu bar extra (status item) with the upstream tray menu (Activate, New, New and Paste, Open..., Find in Files..., Close Tray Icon); clicking the Dock icon also brings the window back | macOS has no tray |
| Tab dragged out of its bar | onto the other view: move (Ctrl: clone); inside the same view: a Move / Clone menu; outside: new instance | onto the other view: move (⌥: clone); onto the right half while the second view is hidden: move there; outside the window: new instance | Ctrl+drag is a secondary click on macOS |
| Panels | docked or floating on any side | the same: left, right, top, bottom or floating (each panel header has a dock menu); the Search results panel and the UDL dialog dock or float too | — |
| Clipboard History | `WM_CLIPBOARDUPDATE` | the clipboard change count is checked every 0.5 s | macOS has no clipboard-change notification |
| Updater | WinGUP downloads and runs the installer | reads a GUP XML feed whose address is built in (`make dmg UPDATE_URL=…`); downloads the app zip, checks its SHA-256 and ECDSA signature (`<SHA256>`, `<Signature>` feed elements, not in upstream), replaces the app in place and relaunches; falls back to the DMG (`<DmgLocation>`) when it cannot replace itself. Without `UPDATE_URL` the build says it has no update address | no installer on macOS; the website is the publisher's |
| Developer tools | separate plugins (JSON Viewer, XML Tools, MIME Tools, Converter...) | built in under Plugins: JSON Tools, XML Tools, Encode - Decode, Text Tools, Convert, Insert (40 commands; selection or whole file, one undo step; conversions open a new tab) | added feature |
| Toolbar tooltips | the command name | the command name, its shortcut and one line on what it does | added feature |
| Prevent C0 typing | drops `WM_CHAR` 0–31 and 127 | drops them from typed text (they reach the editor through Unicode Hex Input or some keyboard layouts) | platform input path |
| Post-it | removes the caption and the menu | removes the title bar (drag by the background); the menu bar stays | the macOS menu bar is global |
| Find Characters in Range | selects the found byte | selects the whole character | a byte inside a UTF-8 character is not a selectable unit |
| Command line | `notepad++.exe` options | same options; `-qn` types upstream's quotes by named people (its own and anonymous ones are left out); `-L` is accepted but the UI is English only; `-systemtray` starts hidden; `-openFoldersAsWorkspace` adds the folders to Folder as Workspace | identity, platform |
| Shortcuts | `shortcuts.xml` Ctrl/Alt/Shift/Key | same file and attributes; `Ctrl` means ⌘ in the macOS scheme and ⌃ in the Windows scheme; an extra `Control="yes"` marks the ⌃ key in the macOS scheme | two shortcut schemes |
| Scintilla keys | upstream `scintKeyDefs` | Windows scheme: the upstream keys; macOS scheme: Scintilla Cocoa's native macOS keys (⌥← word, ⌘← line start…); both editable in the Shortcut Mapper | native text navigation on macOS |
| Run commands | `ShellExecute` | `/bin/sh -c`; URLs (Get PHP help, Wikipedia Search) open in the default browser | no ShellExecute |

## Platform limitations
- **OEM 720 (Arabic DOS)**: macOS iconv has no converter, so Textpad++ has a built-in table generated from Windows' code page data (unit test ENC_014, T-ENC-720-001).
- **Text Direction RTL/LTR**: Scintilla's bidirectional rendering is implemented only for Win32/DirectWrite → disabled.
- Regex character classes for non-ASCII letters use libc++ `wchar_t` traits (Boost on macOS) instead of Win32 traits; ASCII and BMP behaviour verified, locale-sensitive classes may differ — needs a dedicated comparison suite.
- Surrogate pairs are matched as two UTF-16 units in regex (same as upstream on Windows).

## Not implemented (see FEATURE_STATUS.md)
Text Direction RTL / LTR (platform limitation above); Windows .dll plugins; translated dialog texts; ⌥ + letter menu access; the rendering-mode and touchpad Preferences options (Windows-only). Everything else has a real implementation.

### Preference defaults not yet cross-checked against upstream
These defaults were taken from the v8.9.9.1 sources where found and otherwise chosen to match upstream behaviour; they have not been compared against a fresh Windows install: smart highlight in the other view, document switcher MRU order, Save All confirmation, Large File Restriction thresholds and "allow" options, print margins, auto-completion start length, verbose backup naming. Print defaults (line numbers on, "No background colour") and Distraction Free (width / 4) were checked against v8.9.9.1 in this stage and corrected.

## Behaviour verified identical (by automated tests)
Encoding detection and byte-exact round trips; reinterpret vs convert semantics; all 16 sort variants incl. upstream's natural integer comparator; case conversion rules (proper/sentence force/blend, lone "i"); TAB/space conversion algorithm; Boost regex engine (same code as upstream) incl. empty-match rules; bookmark line deletion; change-history navigation; macro recording format (`shortcuts.xml`). User Defined Languages in the upstream 2.1 XML format (keywords, prefix mode, comments, numbers, operators, delimiters, folding, styles; export/import round trip). Hide-lines marker semantics, Find Characters in Range search order, function call tips and API completion (same API files), shortcuts.xml format, and crash recovery after SIGKILL (a real child process). Function List parsing (the upstream `functionList/*.xml` rules and parser algorithm), tag matching (port of `XmlMatchedTagsHighlighter`), the Character Panel tables, project workspace XML, `contextMenu.xml`, and encoding auto-detection with the same uchardet copy and alias table as upstream (so, as upstream, a file uchardet calls "KOI8-R" opens as ANSI, because upstream's alias list spells it `koi8_r`).
| Escape in dialogs | closes most dialogs | closes every pop-up and tool window (presses Cancel / Close / OK) | added behaviour |
| Live Preview | none (plugins: MarkdownViewer++) | View > Live Preview: Markdown rendered beside the text and editable in place, HTML page preview; a .md file asks Preview / Text Only | added feature |
| Compare | Compare plugin | View > Compare: side by side, lines and characters marked, aligned, synchronized | added feature |
| Command Palette, Modern Look | none | ⇧⌘A palette; rounded tabs, unified title bar, macOS Light / Dark themes (View > Modern Look) | added features |
| Git markers, CSV columns, Code Formatter, Snippets | plugins or none | margin markers since the last commit; rainbow CSV columns and Align / Shrink; SQL / HTML / CSS formatting; trigger + Tab snippets | added features |
| Plugin markers / indicators | NPPM_ALLOCATEMARKER 1–15, NPPM_ALLOCATEINDICATOR 9–20 | 1–12 and 9–19: the rest belong to Compare, Git markers and snippets | built-in features |
