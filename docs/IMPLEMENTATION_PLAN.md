# Textpad++ Implementation Plan

Status as of 14 Nov 2026 (fifth increment, 0.2.0: Help menu and name removal, Style Configurator fix, command audit, multi-GB files, Colourful toolbar icons, docking on all sides and floating, interface languages, plugin panels / toolbar icons / online list, -qn). Counts come from `FEATURE_MATRIX.md`: 480 of 482 menu commands have real handlers (275 Verified by tests, 205 Implemented); the two left are Text Direction RTL / LTR (Blocked). All 76 non-menu features are Verified or Implemented; none is Partial or Not started.

| Stage | Scope | Status |
|---|---|---|
| 1. Reference audit | Clone v8.9.9.1, generate menu/shortcut/language tables, feature matrix, UI spec, architecture | **Done** (manual sections still to cross-check) |
| 2. Desktop foundation | App bundle, main window, command registry, menus, toolbar, tabs, status bar, open/edit/save | **Done** |
| 3. Core editor parity | Edit commands, encodings, EOL, languages (all upstream lexers), documents, sessions, backup | **Done** — incl. uchardet detection, OEM 720, tag matching |
| 4. Search & navigation | Find/Replace/Mark/FiF, Boost regex, results panel, bookmarks, token styles, change history | **Done** — incl. incremental search, Find in Projects, live dialog highlighting, transparency |
| 5. UI & preferences | Full Preferences (24 pages), Style Configurator editing, editable Shortcut Mapper, dark UI chrome, in-window menu option | **Done** — incl. in-window menu bar, vertical / multi-line tabs, tab drag between views, file drops, Document Peeker, menu bar extra (system tray) |
| 6. Advanced features | Function List, Document Map, Document List, Folder as Workspace, Project Panels, Character Panel, Clipboard History, printing options, Run menu entries | **Done** (docked panels; floating panels not built) |
| 7. Extension ecosystem | Native plugin API + adapter; port Compare / XML Tools / JSON Viewer / NppExec as separate projects | **Plugin host done** (`.tpplugin` SDK, sample, Plugins Admin, Shortcut Mapper, shortcuts.xml); ports of popular plugins not started |
| 8. Visual parity & regression | Windows reference screenshots, per-region diffs, interaction fixes | Snapshot tool ready; no Windows reference set yet |
| 9. Packaging | Universal app, DMG, signing/notarization, clean-machine install test | Universal app + ad-hoc signed DMG; updater feed (`make dmg UPDATE_URL=…`); `make notarize` ready but needs a Developer ID certificate; clean-machine test pending |

## Next tasks (in order)
1. Clean-machine install test of the DMG on an Intel Mac and an Apple silicon Mac (Gatekeeper override for the unsigned build).
2. Developer ID signing + notarization when an Apple Developer account is available (`make notarize`).
3. Translated dialog texts (map upstream dialog strings onto the macOS dialogs).
4. Windows reference screenshots and per-region comparisons; cross-platform byte-level reference cases.
5. Ports of popular plugins (Compare, XML Tools, JSON Viewer) as separate `.tpplugin` projects; an online plugin list for Plugins Admin.
6. Automated tests for the dialog-driven commands (the audit shows they open; their contents are not yet checked).
