# Textpad++ Test Plan

## Principles
- A feature is **Verified** only when an automated test that exercises it through the real command path passes (`FEATURE_MATRIX.md` is generated from the results; nobody edits statuses by hand).
- Tests run against real Scintilla views and real files; no mocks of the editing engine.
- File-integrity failures are release blockers.

## Suites
| Suite | What | How to run | Where |
|---|---|---|---|
| Unit | Pure C++ core: encoding detection/decoding/encoding, EOL, case conversion, all sorters, line/blank operations, extended escapes, hashing | `make unit` | `tests/unit/test_core.cpp` → `build/unit-results.json` |
| In-app acceptance | Launches `Textpad++.app --self-test`, invisible window, isolated settings folder; every test runs commands via `TPCommandRegistry` (same path as menus/shortcuts) and records which command ids it executed | `make selftest` | `src/testing/SelfTest.mm` → `build/selftest-results.json` |
| Benchmarks | 55 MB / 1M-line open, find at end, save; 200 tabs open + switch | part of `make selftest` | same JSON (`benchmarks`) |
| Command audit | Every menu command once, changes recorded, dialogs / launches / printing intercepted | `TEXTPAD_AUDIT=1 build/Textpad++.app/Contents/MacOS/Textpad++ --self-test out.jsonl` | JSON lines per command |
| Large-file benchmark | Open / find / save / grow / close a multi-GB log | `TEXTPAD_BIGFILE=<file> … --self-test out.json` | stderr `BENCH` lines |
| Visual snapshot | Renders the main window, or a dialog, to PNG | `Textpad++ --snapshot out.png files…`; dialogs with `TEXTPAD_SNAPSHOT_PANEL=prefs:<page>` or `udl[:<tab>]` | Stage 8 adds reference comparison |
| Intel slice | Same acceptance suite on x86_64 | On an Intel Mac: `make ARCHS="arm64 x86_64" selftest`. On Apple silicon: `arch -x86_64 build/Textpad++.app/Contents/MacOS/Textpad++ --self-test out.json` (Rosetta) | Running under Rosetta makes macOS show an "App Update Required" notice about Intel-only apps; it refers to the test process, not to the universal app, which runs natively on Apple silicon |

After any run: `python3 -I scripts/gen_feature_matrix.py .` regenerates `FEATURE_MATRIX.md` and `TEST_RESULTS.md`.

## Coverage by category (current)
- **File integrity**: empty, UTF-8, UTF-8 BOM, UTF-16 LE/BE (incl. surrogates), ANSI with undefined CP1252 bytes, mixed EOL, no final newline, binary with NUL, combining marks/Devanagari, all 256 byte values, 200 random binary blobs; edit+save keeps encoding; permissions and symlinks; lossy-conversion warning.
- **Document lifecycle**: close prompts (Yes/No/Cancel), close variants, reload, external change, deleted file, restore closed, recent list, Trash, Save As / Save a Copy As semantics.
- **Persistence**: session save/load (files, views, bookmarks, language), snapshot backup restore of unsaved text, macros saved to `shortcuts.xml`.
- **Editing**: undo/redo/clipboard, 8 case modes, line ops, 16 sort variants, comments, EOL conversion, blank ops, read-only, date/time, path copying, multi-select, binary clipboard, begin/end select, redact, indent, auto-indent, smart highlight.
- **Search**: Normal/Extended/Boost regex (lookbehind, `$n`, `\U`, `(?i)`, invalid pattern), empty-match rules, replace one/all/in selection/all opened, count, mark + bookmark + copy, Find All panel + F4 navigation, Find in Files / Replace in Files with filters and UTF-16 preservation, braces, bookmarks, token styles, change history.
- **View**: wrap, symbols, indent guide, zoom, clone/move between views, folding, tab navigation/colour/sorting, hide lines, monitoring (tail -f).
- **Preferences** (T-PREF-001…011): all 24 pages build and every live control has a default; options reach Scintilla (caret, current line, wrap, virtual space, scrolling, margins, folds, edges, NPC/EOL appearance); new-document defaults; per-language indentation; toolbar/tab/status bar/dark mode; smart highlighting; auto-insert and auto-completion while typing; backup on save and large-file restriction; delimiters, ⌘+double-click and links; MISC. options. Preferences are reset after each test.
- **User Defined Languages** (T-UDL-001…004): UDL 2.1 parsing and styling (keywords, prefix mode, comments, numbers, operators, delimiters, folding), export/import round trip, rename/remove with open documents, preinstalled Markdown UDL and Language menu entries, the dialog opened through its command with live re-styling.
- **Completing the partial features** (`src/testing/SelfTestPartials.inc`): crash regression (T-REG-001), printing with form feeds (T-PRINT-001), API completion, word/path completion and call tips (T-AUTOC-001…004), Find Characters in Range (T-SRCH-FCR-001), hide lines / Post-it / Distraction Free (T-VIEW-HL-001, T-VIEW-PI-001), Style Configurator (T-STYLE-001/002), Shortcut Mapper, macro / Run command shortcuts and Scintilla keys with real key events (T-KEYS-001…003), command line incl. the real binary's `--help` (T-CMD-001…003), Dark Mode tones (T-DARK-001), settings on cloud (T-CLOUD-001), accessibility (T-ACC-001).
- **Crash recovery (T-SESS-KILL-001)**: the suite starts a separate Textpad++ process (`--crash-phase1 <dir>`), which leaves an unsaved new document and an unsaved edit and writes its snapshot; the suite kills it with SIGKILL, starts `--crash-phase2 <dir>` and checks both are restored as unsaved and the file on disk is untouched. (This test found and fixed restored documents being shown as saved.)
- **Encoding/Language/Tools/Macro/Window**: conversions, Windows-1251 reinterpretation, ANSI↔UTF-8 reinterpretation, language detection + lexer for **every** Language menu entry, hashes, macro record/playback/undo grouping, Window menu.
- **Fourth increment** (`src/testing/SelfTestPanels.inc`): the seven panels (T-PANEL-001…006), Incremental Search and live Find highlighting / transparency (T-SRCH-INC-001, T-SRCH-HL-001), tag matching (T-EDIT-TAG-001), `contextMenu.xml` (T-UI-CTX-001), file and tab drops (T-UI-DND-001), vertical / multi-line tabs (T-UI-TABS-001), the remaining Preferences options (T-PREF-C0-001, -COLMULTI-001, -RCLICK-001, -2GB-001 with a sparse 2.2 GB file, -TBCOLOR-001 pixel checks, -PEEK-001, -TRAY-001), the in-window menu bar (T-UI-MENUBAR-001), uchardet and OEM 720 (unit ENC_014/015, T-ENC-DETECT-001, T-ENC-720-001), the plugin host with the SDK sample plugin built by `make sample-plugin` (T-PLUG-001…003), the updater against a local feed (T-UPD-001) and the Window list commands (T-WIN-002).

## Not yet automated (planned)
1. Dialog-driven commands (Open/Save panels, Go To, Column Editor, Run, Style Configurator, the updater's proxy dialog; Preferences pages that open system services: File Association, Print, Search Engine, Default Directory): drive via XCUITest-equivalent (AXUIElement) or expose non-modal test entry points.
2. The updater against a real HTTPS server (the suite uses a `file:` feed; HTTP status handling and proxies are not exercised).
3. Visual comparison: per-region pixel diff (toolbar, tab bar, status bar, editor) against Windows Notepad++ screenshots at 100/150/200 %.
4. Cross-platform reference cases: the same input + action script run on Windows Notepad++ (via its macro/`shortcuts.xml` and `-qt` command-line) and on Textpad++, comparing output bytes. Requires a Windows machine; not available in this environment.
5. Regex conformance corpus (Boost on macOS vs Boost on Windows) incl. Unicode classes.
6. Keyboard interaction tests for menu key equivalents in both schemes (Scintilla command keys are already driven with real `NSEvent`s).
7. Network-volume / removable-drive saves and very long paths.

## Release gate
`make test` must report 0 failures for both arm64 and x86_64 slices; any file-integrity test failure blocks a release.
