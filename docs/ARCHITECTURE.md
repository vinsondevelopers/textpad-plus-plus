# Textpad++ Architecture

## 1. Reference architecture (Notepad++ v8.9.9.1, verified from source)

Audited from the shallow clone of tag `v8.9.9.1` (commit `066c93ac`, 12 Nov 2026) in `../reference/` (not shipped).

| Upstream component | Source | Role | Textpad++ counterpart |
|---|---|---|---|
| `Notepad_plus` / `Notepad_plus_Window` | `PowerEditor/src/Notepad_plus*.cpp`, `NppBigSwitch.cpp` | Main window, owns two views, docking manager, dialogs; `WM_COMMAND` dispatch | `TPMainWindowController` |
| `NppCommands.cpp` | `Notepad_plus::command(int id)` | One giant switch over `IDM_*` | `TPCommandRegistry` + `src/commands/*.mm` (one handler per id) |
| `Notepad_plus.rc` (`IDR_M30_MENU`), `menuCmdID.h` | resources | Menu hierarchy, labels, numeric ids | `scripts/gen_reference_tables.py` → `src/generated/*.inc` |
| `Parameters.cpp` (`winKeyDefs`, `scintKeyDefs`) | settings | Default shortcuts | generated `NppShortcutTable.inc`, `NppScintKeyTable.inc` |
| `ScintillaEditView` | `ScintillaComponent/` | Win32 Scintilla wrapper: lexer/style setup, line ops, case conversion | `TPEditorPane` + `TPLanguageService` + `core/TextOps` |
| `Buffer`, `FileManager` | `ScintillaComponent/Buffer.cpp` | Documents: `UniMode` + codepage, EOL, dirty state, load/save | `TPDocument` + `core/Encoding` + controller I/O |
| `Utf8_16`, `EncodingMapper` | `Utf8_16.cpp`, `EncodingMapper.cpp` | BOM/UTF-8 detection, codepage table | `core/Encoding` |
| `FindReplaceDlg` (+ `Finder`) | `ScintillaComponent/FindReplaceDlg.cpp` | Find/Replace/FiF/Mark, results panel | `TPFindReplaceController`, `search/SearchEngine`, `TPSearchResultsPanel` |
| `BoostRegexSearch` | `boostregex/` | Scintilla `SCI_OWNREGEX` regex engine (Boost.Regex) | **same code**, compiled into Textpad++'s Scintilla |
| `LexUser`, `LexSearchResult` | `lexilla/lexers/` | UDL lexer, search-results lexer | same lexers; UDL loader in `UserDefinedLanguages` |
| `NppParameters` | `Parameters.cpp` | config.xml, langs.xml, stylers.xml, session.xml, shortcuts.xml | `NSUserDefaults` + the **same** `langs.model.xml` / `stylers.model.xml` + `TPSession` (session.xml) + `shortcuts.xml` |
| `PluginsManager`, `Notepad_plus_msgs.h` | `MISC/PluginsManager/` | Win32 DLL plugin host (`NPPM_*` messages) | `TPPluginHost` (native `.tpplugin` bundles, §5) |
| `DockingManager`, panels | `WinControls/` | Function List, Doc Map, FaW, Project Panels… | `TPDockManager` + `src/panels/*` (docked left / right) |
| `functionParser`, `xmlMatchedTagsHighlighter`, `uchardet` | `WinControls/FunctionList`, `ScintillaComponent`, `uchardet/` | Function List parsing, tag matching, encoding detection | ports in `panels/FunctionList.mm`, `app/TagMatch.h`; uchardet itself in `third_party/uchardet` |
| WinGUP (`gup.exe`) | separate project | updater | `TPUpdater` (GUP XML feed) |

Key upstream behaviours preserved: two `ScintillaEditView`s (main/sub) that switch **document pointers** on tab change (clone = same document in both views); per-view caret/scroll position saved per buffer; Scintilla holds the text and its undo history; menu ids are the macro/shortcut identity.

## 2. Technology decision

| Option | Verdict |
|---|---|
| **B. AppKit + Objective-C++ + Scintilla Cocoa + Lexilla (chosen)** | Scintilla's Cocoa layer is first-party and shipped inside the Notepad++ tree (`scintilla/cocoa`). Its message API (`SCI_*`) is exactly what upstream uses on Win32, so upstream algorithms port line-for-line. Builds with Command Line Tools only (no Xcode/Qt install). Native macOS integration (menus, panels, file dialogs, Finder, Trash, print). Small binary (~5 MB thin). Licensing: Scintilla/Lexilla HPND-style (permissive), Boost.Regex BSL-1.0, Notepad++ GPLv3 → whole app GPLv3. |
| A. Qt 6 + QScintilla | QScintilla has its own API and lexers (not Lexilla), so upstream's `SCI_*` code and Lexilla lexers would need translation; Qt not installed here (~1 GB); QScintilla is GPL/commercial. Windows-look widgets are easier in Qt, but fidelity of *editing semantics* matters more. |
| C. Other (Electron/web editor, custom engine) | Rejected: cannot provide Scintilla semantics (Boost regex, lexers, folding, column mode). |

## 3. Module map (actual code)

```
src/main.mm                     entry point (--self-test, --snapshot, files)
src/app/
  AppDelegate                   ApplicationShell: lifecycle, Finder open events, quit flow
  MainWindowController          DocumentManager + layout + notifications + FileMonitor + safe writes
  EditorPane                    one view (tab bar + ScintillaView), document switching   (Tab/SplitView manager)
  TabBarView                    Notepad++-style tabs (custom drawing, drag, pin, colours)
  ToolbarView                   toolbar + status bar (TPStatusBarView)
  Document                      TPDocument (buffer model)
  LanguageService               LanguageService + SyntaxThemeManager (langs/stylers XML → Lexilla + styles)
  Session                       SessionManager + BackupRecoveryService (session.xml, snapshot, periodic backup)
  Preferences                   TPPrefs (typed NSUserDefaults store, upstream defaults, change notification),
                                TPChrome (light/dark chrome palette), TPPreferencesWindow (24 pages from a declarative spec)
  PreferencesApply              applies every preference to views, chrome, saving, typing (auto-insert, completion), links
  UserDefinedLanguages          UDL 2.1 XML model + loader (user folder, then bundled preinstalled), import/export,
                                LexUser property/style mapping (port of upstream setUserLexer)
  AutoCompletion                API / word / path completion and function call tips (port of upstream AutoCompletion + FunctionCallTip)
  HideLines.h                   upstream hide-lines marker logic (hide, merge, show on marker click, restore per view)
  CommandLine / CommandLineApply  upstream command-line options, mono-instance forwarding, ghost typing
  Accessibility                 accessibility elements for the custom-drawn tab bar and status bar
  Sci.h                         thin Scintilla message helpers, shared marker/indicator ids
src/commands/
  CommandRegistry               CommandRegistry + MenuManager + shortcut schemes + user shortcuts (shortcuts.xml)
  ScintillaKeys                 Scintilla command keys (Windows scheme = upstream keys, user keys, native-map restore)
  CommandsFile/Edit/Search/View/Format/Tools.mm   handlers grouped like the upstream menus
  TagMatch.h                    port of upstream XmlMatchedTagsHighlighter
  ContextMenu                   editor context menu from contextMenu.xml; Settings > Edit Popup ContextMenu
  EditorOptions                 options upstream implements in the Scintilla window procedure (C0 filter,
                                column selection to multi-editing, right-click caret, 2 GB warning)
  MenuBarView                   optional in-window Windows-style menu bar (＋ ▼ ✕, Hide with ⌥ / F10)
  SystemTray                    menu bar extra for Minimize / Close to system tray
  Updater                       Help > Update Textpad++ (GUP XML feed), proxy, auto-updater
  LargeFiles                    files from 32 MB: memory map + Scintilla ILoader on a background thread (progress,
                                Cancel), chunked saves and backups, append-only reload of growing logs
  Localization                  interface languages from nativeLang/*.xml (menus by upstream positions, commands by id)
src/panels/
  DockManager                   docking: [left dock | editors | right dock] split view, tabbed containers, persistence
  DocumentPanels                Document List, Document Map, Document Peeker
  FunctionList                  Function List panel + port of upstream functionParser (functionList/*.xml)
  WorkspacePanels               Folder as Workspace (FSEvents), Project Panels 1–3 (workspace XML)
  ToolPanels                    Character Panel, Clipboard History
  PanelCommands                 the View / Edit / File commands that open them, PowerShell
src/plugins/
  PluginHost                    plugin loading, Plugins menu, NPPM_* answers, NPPN_* / SCN_* forwarding
  PluginsAdmin                  Plugins Admin window
sdk/                            TextpadPlusPlusPlugin.h (generated from Notepad_plus_msgs.h) + SamplePlugin
src/dialogs/
  UDLDialog                     "Define your language..." panel (4 tabs, Styler dialogs), edits apply live and auto-save
  StyleConfigurator             Style Configurator (per-style editing, user ext./keywords, Global override, theme save)
  ShortcutMapper                Shortcut Mapper (5 tabs, Modify/Clear/Delete, conflicts) + shortcut editor
  FindCharsInRangeDialog        Search > Find characters in range
src/search/
  SearchEngine                  find/replace/count/mark/find-all on any Scintilla view (Normal/Extended/Boost regex)
  FindReplaceController         Find / Replace / Find in Files / Mark dialog
  SearchResultsPanel            "Search results" panel (searchResult lexer)
src/core/  (pure C++, unit-tested without AppKit)
  Encoding                      EncodingService: detection, decode/encode, codepages, EOL
  TextOps                       case conversion, sorters, line/blank ops, extended escapes (ported from upstream)
  Hashing                       MD5/SHA-1/SHA-256/SHA-512 via CommonCrypto
src/testing/SelfTest            in-app acceptance suite
src/generated/                  generated from upstream sources (never hand-edited)
third_party/                    scintilla (+cocoa), lexilla, boostregex — copied from the reference tree
```

### Preferences flow
`TPPrefs set:forKey:` writes `NSUserDefaults` and posts `TPPrefsChangedNotification`; the main window's `preferencesChanged` calls `applyAllPreferences`, which re-applies chrome visibility, dark mode, editor/margin/fold settings, word characters and language indentation to every open view. The Preferences window is built from a declarative page spec; options that cannot work on macOS or depend on unbuilt features are rows flagged `na` and render disabled with their reason, so no control is fake. Defaults are registered once at launch (`registerDefaults`), so every live control has a default (T-PREF-001).

### User Defined Languages
UDLs keep the upstream 2.1 XML format and folder layout (`userDefineLangs/`). A UDL has the language id `udl:<name>`; `LanguageService` resolves it through `TPUserLanguages` and applies the `user` lexer with the `userDefine.*` properties and the 24 styles (colour-style bits and nesting masks as upstream). Files are matched by extension, UDLs first; when the chrome is dark the "dark mode" variant of a UDL is preferred.

### Shortcuts
`shortcuts.xml` keeps the upstream format: `<InternalCommands>` overrides menu shortcuts, `<Macros>` / `<UserDefinedCommands>` carry the macro and Run command shortcuts and `FolderName` sub-menus, `<ScintillaKeys>` the Scintilla command keys. Saved macros and Run commands become registry commands 20000+ / 21000+ (upstream `ID_MACRO` / `ID_USER_CMD`), so menus, the mapper, key handling and macro recording treat them like any other command.

### Command flow
`NSMenuItem(tag = IDM_*)` / toolbar button / key binding / context menu / macro step / self-test → `TPCommandRegistry execute:` → `willExecute` hook (macro recorder, test tracer) → handler block → Scintilla messages / document manager. `validateMenuItem:` asks the same registry for *enabled* and *checked*, so a command without a handler is always disabled (no fake buttons).

### Document model
Each `TPDocument` owns one Scintilla document (`SCI_CREATEDOCUMENT`). A pane shows a document with `SCI_SETDOCPOINTER`; cloning shows the same pointer in the other pane. Background work on documents that are not visible (save, Find in all documents, session backup, Replace in Files) uses a hidden **worker** `ScintillaView`, mirroring upstream's invisible edit view.

### Text and encodings
Scintilla always holds UTF-8. Files are decoded on load (`detectAndDecode`) and encoded on save with the document's `TextEncoding {UniMode, codepage}`. The ANSI decoder is byte-bijective (Windows-1252 with the 5 undefined bytes mapped to C1 controls, like Windows), invalid UTF-8 is kept as raw bytes, so unmodified content always saves byte-identical. Upstream's "reinterpret" vs "convert" semantics are reproduced by reconstructing the bytes upstream would hold in memory (`memBytesOf:`).

### Saving
`TPSafeWriteFile`: resolve symlink → temp file in the same folder → write → `fsync` → copy metadata (`copyfile` SECURITY|XATTR) → `rename`. A failed temp write never touches the original. Read-only folder: in-place write of an existing writable file (same as upstream).

## 4. Data locations
`~/Library/Application Support/Textpad++/` — `session.xml`, `backup/` (always local), `shortcuts.xml` (macros, run commands; upstream format), `themes/`, `userDefineLangs/` (user UDLs; preinstalled ones ship in the app bundle), `plugins/`. Preferences: `NSUserDefaults` (`com.textpadplusplus.app`, keys `pref.*`); file backups go to a `TextpadBackup` folder next to the file. The self-test redirects the folder (`TEXTPAD_SUPPORT_DIR`) and restores user defaults afterwards.

## 5. Plugins
Upstream plugins are Win32 DLLs talking to `HWND`s via `NPPM_*`/`SCI_*` window messages; they cannot run on macOS. Textpad++ loads native `.tpplugin` bundles (CFBundle) that export the same five functions as a Notepad++ plugin (`setInfo`, `getName`, `getFuncsArray`, `beNotified`, `messageProc`). `NppData` carries three opaque handles and a `sendMessage` function: the host routes Notepad++-handle messages to `-[TPPluginHost sendNppMessage:]` (upstream numbers, UTF-8 strings) and Scintilla-handle messages straight to that view. Function items become registry commands from 22000 (upstream `ID_PLUGINS_CMD`), so menus, shortcuts, the Shortcut Mapper, macros and `contextMenu.xml` treat them like built-in commands. `NPPN_*` notifications come from the document lifecycle (open, activate, save, close, language, launch, quit) and every Scintilla notification is forwarded with the view's handle. The SDK and a sample live in `sdk/` and ship in `Contents/Resources/sdk`; see `docs/PLUGINS.md`.

## 6. Command audit
`TEXTPAD_AUDIT=1 Textpad++ --self-test out.jsonl` (`src/testing/Audit.mm`) runs every menu command against a prepared multi-tab document and records what it changed (text, selection, view state, windows, preferences, document properties). Dialogs, file panels, browser / Finder / Terminal launches, processes and printing are intercepted and recorded instead of run. Commands that change nothing are then triaged by hand; this found the dark-mode Style Configurator bug and an endless repaint loop with a document cloned in both views.

## 7. Panels and docking
`TPDockManager` wraps the editors in an `NSSplitView` [left dock | column | right dock], the column being another split view [top dock | editors | bottom dock]; a panel can also float in its own utility window. A dock shows one panel or a tab strip of several; widths, visible panels and per-panel side are saved in `NSUserDefaults`. Panels implement `TPPanel` and get `documentsChanged` / `editorViewChanged` callbacks from `refreshUI` and `SCN_UPDATEUI`. The Document Map and Document Peeker show the real document (`SCI_SETDOCPOINTER`) at zoom −10; Folder as Workspace watches folders with FSEvents on the main run loop.

Settings files (`shortcuts.xml`, `stylers.xml`, `themes/`, `userDefineLangs/`, `autoCompletion/`, `preferences.plist`) move to `<cloud path>/Textpad++` when Preferences > Cloud & Link sets a cloud folder (`TPSession.settingsDirectory`, read at launch).
