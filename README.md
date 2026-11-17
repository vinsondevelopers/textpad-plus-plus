# Textpad++

A native macOS text and source-code editor that reproduces the Windows **Notepad++** experience — same menus, command ids, shortcuts, toolbar, tabs, status bar, encodings, languages, styles and editing semantics — under its own Textpad++ identity.

Built on the same engine as Notepad++: **Scintilla 5.6.9** (Cocoa platform layer), **Lexilla 5.5.5**, and Notepad++'s **Boost.Regex** search adapter, taken from Notepad++ v8.9.9.1. Textpad++ is GPLv3 and is not an official Notepad++ release.

## Status (1.0.0)
- One universal app for **Intel and Apple silicon Macs** (arm64 + x86_64 in one binary, macOS 12+). It runs natively on both; Rosetta is never needed.
- 482 upstream menu entries inventoried; statuses are generated from test results in [docs/FEATURE_MATRIX.md](docs/FEATURE_MATRIX.md); [docs/FEATURE_STATUS.md](docs/FEATURE_STATUS.md) lists every feature in one table, implemented first. 475 have real handlers, 5 that opened the upstream project's web sites were removed (the upstream name appears nowhere in the app), and only Text Direction RTL / LTR are blocked (Scintilla's bidirectional text exists only on Windows). Every command is exercised by an automated audit (`TEXTPAD_AUDIT=1 … --self-test out.jsonl`).
- Panels (Function List, Document Map, Document List, Folder as Workspace, Project Panels 1–3, Character Panel, Clipboard History), Incremental Search, Find in Projects, tag matching, encoding auto-detection (uchardet) and OEM 720, an optional in-window menu bar with keyboard menu mode, a menu bar extra for "system tray", native plugins with panels, toolbar icons and an online list ([docs/PLUGINS.md](docs/PLUGINS.md)), signed over-the-air updates, built-in developer tools (JSON, XML, encode/decode, case styles, CSV/Markdown conversion, code formatters, inserts), a Markdown / HTML Live Preview you can edit in, side-by-side Compare, a Command Palette (⇧⌘A), Git change markers, rainbow CSV columns, snippets, a modern look with macOS themes, 96 interface languages (menus and dialogs), panels that dock on any side or float, and multi-GB files (a 3.2 GB / 32-million-line log opens in about 14 s in the background, with progress and Cancel).
- Preferences (24 pages, Dark Mode tones, settings on cloud), User Defined Languages, Style Configurator, Shortcut Mapper (incl. macros, Run commands and Scintilla keys), API auto-completion and call tips, the upstream command-line options and multi-instance.
- Tests: unit + in-app acceptance suites, including a real crash (SIGKILL) recovery test; see [docs/TEST_RESULTS.md](docs/TEST_RESULTS.md).

## Build
Requirements: macOS 12+, Xcode **Command Line Tools** (`xcode-select --install`). No Xcode project, CMake or Qt needed.

```sh
make                         # build/Textpad++.app for this Mac's architecture
make ARCHS="arm64 x86_64"    # universal build
make test                    # unit tests + in-app acceptance suite
make dmg                     # universal build + dist/Textpad++.dmg (ad-hoc signed)
make dmg UPDATE_URL=https://example.com/textpad/update.xml   # + the update address built in, and dist/update.xml to upload
make sample-plugin           # build/plugins/SamplePlugin.tpplugin from sdk/samples
make notarize DEVELOPER_ID=… NOTARY_PROFILE=…   # universal, Developer ID signed, notarized + stapled DMG
make run                     # open the app
```

Regenerate tables and docs:
```sh
python3 -I scripts/gen_reference_tables.py ../reference/notepad-plus-plus-8.9.9.1 .   # needs the upstream checkout
python3 -I scripts/gen_feature_matrix.py .                                             # after `make test`
```

## Install
Open `Textpad++.dmg` and drag Textpad++ to Applications. The same DMG works on Intel and Apple silicon Macs.

## Publishing the DMG on a website
A DMG that people download from a website must be **signed with a Developer ID certificate and notarized by Apple**. Otherwise macOS 15 and later block it with "Apple could not verify…", and users have to override that in System Settings. The ad-hoc `make dmg` output is only for your own Mac.

One-time setup (needs a paid Apple Developer Program membership):
1. In Xcode › Settings › Accounts, or at developer.apple.com › Certificates, create a **Developer ID Application** certificate and install it in your login keychain. `security find-identity -v -p codesigning` must list it.
2. Create an app-specific password at appleid.apple.com, then store the notary credentials once:
   ```sh
   xcrun notarytool store-credentials TextpadNotary --apple-id <your Apple ID> --team-id <TEAMID>
   ```

Each release:
```sh
make notarize DEVELOPER_ID="Developer ID Application: <Name> (<TEAMID>)" NOTARY_PROFILE=TextpadNotary
```
This builds the universal app and signs it with the hardened runtime and a secure timestamp. It then builds and signs `dist/Textpad++.dmg`, submits it to Apple and waits for the result. Finally it staples the ticket, checks the DMG with Gatekeeper (`spctl`) and prints its SHA-256 for the download page. `notarytool` and `stapler` ship with the Command Line Tools; Xcode is not required. The signature carries one entitlement, `com.apple.security.cs.disable-library-validation` (`resources/Textpad++.entitlements`), so the hardened runtime still lets Textpad++ load plugins signed by other people.

### Without a Developer ID (ad-hoc DMG)
`make dmg` gives a DMG that works on Intel and Apple silicon Macs but is not notarized. After dragging Textpad++ to Applications, the first launch is blocked; users open it once with right-click (Control-click) > Open, or with System Settings > Privacy & Security > "Open Anyway". Say this on the download page.

### Updates (over the air)
Build with `make dmg UPDATE_URL=https://<your site>/<folder>/update.xml`. That writes four files to `dist/`; upload them all to that folder:

| File | What it is |
|---|---|
| `Textpad++.dmg` | the installer for new users |
| `Textpad++-<version>.zip` | the app itself, used for in-place updates |
| `update.xml` | the feed: version, zip and DMG addresses, the zip's SHA-256 and its signature |
| `pluginList.json` | the Plugins Admin list (written empty once; `{"plugins": [{"folder-name", "display-name", "version", "id" (SHA-256 of the zip), "repository" (zip URL), "description"}]}`) |

Help > Update Textpad++ and the automatic check (every 15 days, Preferences > MISC.) read `update.xml`. When a newer version is listed, Textpad++ downloads the zip, checks its SHA-256 and its ECDSA P-256 signature against the public key built into the app, checks the bundle id, version and code signature, then replaces itself and relaunches ("Install and Relaunch") or swaps at quit ("Install When I Quit"). With "Install updates automatically" on (the default), a found update is installed at the next quit without asking. If the app cannot replace itself (a read-only folder, or it runs from the DMG), it downloads the DMG instead.

**The signing key.** The first `make dmg UPDATE_URL=…` creates `~/.textpad-update-key.pem` (outside the project; set `UPDATE_KEY=` for another place). **Back it up somewhere safe and never share it.** Installed copies accept only updates signed with it: if it is lost, they can no longer update in place (users would download the DMG once by hand); if it leaks, someone else could sign updates. Raise `VERSION` in the Makefile for each release.

**About the "App Update Required / will not open in macOS 28" notice:** macOS shows it for Intel-only (x86_64) processes running under Rosetta. Textpad++ contains a native arm64 slice, so on Apple silicon it never runs under Rosetta and does not trigger the notice. Running the Intel slice on purpose with `arch -x86_64 …` (as the x86_64 test does) does trigger it for that test process.

## Command line
```
Textpad++ [file ...]                     open files
Textpad++ --self-test results.json       run the acceptance suite (isolated settings) and exit
Textpad++ --snapshot out.png [file ...]  render the main window to PNG and exit
Textpad++ -<defaultsKey> <value> ...     override a preference for this launch only (NSUserDefaults argument domain)
Textpad++ --help                         the upstream options: -n -c -p -l -udl= -ro -monitor -nosession -multiInst -openSession -r -qt= ...
```
With `--snapshot`, `TEXTPAD_SNAPSHOT_PANEL=prefs:<page name>` renders a Preferences page, `udl` or `udl:<tab name>` the User Defined Language dialog, `style:<lexer>/<style>` the Style Configurator, `shortcuts:<tab>` the Shortcut Mapper and `fcr` Find Characters in Range.

## Data
`~/Library/Application Support/Textpad++/` — `session.xml` (Notepad++ session layout), `backup/`, `shortcuts.xml` (macros/run commands/plugin commands, Notepad++ format), `themes/`, `userDefineLangs/` (your UDL XML files), `contextMenu.xml` (after Settings > Edit Popup ContextMenu), `plugins/<Name>/<Name>.tpplugin` (+ `plugins/Config`). Preferences live in `NSUserDefaults` (`com.textpadplusplus.app`).

## Layout
```
src/            application (Objective-C++), see docs/ARCHITECTURE.md
src/dialogs/    User Defined Language dialog, Style Configurator, Shortcut Mapper
src/panels/     docking panels
src/plugins/    plugin host, Plugins Admin
sdk/            plugin SDK header and sample plugin
src/core/       pure C++ services (encoding, text operations, hashing)
src/generated/  tables generated from the upstream sources
third_party/    Scintilla (+Cocoa), Lexilla, Boost.Regex adapter, uchardet
resources/      Info.plist, langs/stylers XML, themes, preinstalled UDLs, icons
tests/unit/     unit tests
scripts/        generators, icon renderer, DMG and notarization scripts
docs/           FEATURE_STATUS (one table: implemented / not implemented), FEATURE_MATRIX, UI_SPEC, ARCHITECTURE, IMPLEMENTATION_PLAN, TEST_PLAN, TEST_RESULTS, KNOWN_DIFFERENCES, LICENSES_AND_ATTRIBUTIONS, PLUGINS
```

## License
GPL-3.0-or-later. Contains code and data from Notepad++ (© Don Ho and contributors), Scintilla/Lexilla (© Neil Hodgson), Boost.Regex (BSL-1.0) and uchardet (MPL 1.1 / GPL 2+ / LGPL 2.1+, used under the GPL). See [docs/LICENSES_AND_ATTRIBUTIONS.md](docs/LICENSES_AND_ATTRIBUTIONS.md).
