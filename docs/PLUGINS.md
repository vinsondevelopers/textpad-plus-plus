# Writing Textpad++ plugins (macOS)

Textpad++ loads native macOS plugins. They use the same five C entry points as a Windows plugin DLL for the editor it derives from, the same
`NPPM_*` / `NPPN_*` message numbers (API level 8.9.9.1) and the same Scintilla `SCI_*` / `SCN_*` messages. A Windows
DLL cannot load on macOS, but most plugin source code ports with small changes.

## The bundle

A plugin is a loadable bundle named `<Name>.tpplugin`:

```
SamplePlugin.tpplugin/
  Contents/
    Info.plist          CFBundleExecutable, CFBundleIdentifier, CFBundlePackageType BNDL, CFBundleShortVersionString
    MacOS/SamplePlugin  Mach-O bundle (build it for arm64 and x86_64 so it loads on every Mac)
```

It is installed as `~/Library/Application Support/Textpad++/plugins/<Name>/<Name>.tpplugin`, the same layout as
`plugins\<Name>\<Name>.dll` on Windows. **Settings > Import > Import plugin(s)...** copies a bundle there and loads it
at once. **Plugins > Open Plugins Folder...** shows the folder. Plugins load at launch in folder-name order, unless
Textpad++ is started with `-noPlugin`.

Build the sample (the SDK is in `Textpad++.app/Contents/Resources/sdk`):

```bash
clang -bundle -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 -I sdk SamplePlugin.c -o SamplePlugin.tpplugin/Contents/MacOS/SamplePlugin
codesign --force --sign - SamplePlugin.tpplugin
```

Apple silicon only runs signed code; an ad-hoc signature (`--sign -`) is enough for a plugin you build yourself.
A Developer ID build of Textpad++ carries the `com.apple.security.cs.disable-library-validation` entitlement, so it
can load plugins signed by someone else.

## Entry points

```c
#include "TextpadPlusPlusPlugin.h"
void setInfo(NppData data);                      // first call: keep the handles and data.sendMessage
const char *getName(void);                        // the Plugins sub-menu name (UTF-8)
FuncItem *getFuncsArray(int *count);              // the commands; a NULL _pFunc is a separator
void beNotified(SCNotification *notification);    // NPPN_* and every Scintilla notification of both views
intptr_t messageProc(uint32_t msg, uintptr_t wParam, intptr_t lParam);   // NPPM_MSGTOPLUGIN from other plugins
int tppPluginAPIVersion(void);                    // optional; must return TPP_PLUGIN_API_VERSION
```

All five of `setInfo`, `getName`, `getFuncsArray`, `beNotified` and `messageProc` are required, as on Windows. A
bundle that lacks one, or cannot load (wrong architecture, not signed), shows under **Plugins > Plugins Admin... >
Incompatible** with the reason.

## Differences from the Windows interface

| Windows (PluginInterface.h) | Textpad++ (TextpadPlusPlusPlugin.h) |
|---|---|
| `::SendMessage(HWND, msg, wParam, lParam)` | `data.sendMessage(handle, msg, wParam, lParam)` with `data._nppHandle`, `data._scintillaMainHandle`, `data._scintillaSecondHandle` |
| `wchar_t` strings (`_itemName`, `getName()`, NPPM string parameters) | UTF-8 `char` strings |
| `ShortcutKey._isCtrl` = Ctrl | Command (⌘) in the default Mac shortcut scheme, Control in the Windows scheme; `_key` is still a Windows virtual-key code |
| Docking dialogs: `tTbData.hClient` is an `HWND` | `tTbData.hClient` is an `NSView *` (`NPPM_DMMREGASDCKDLG`, `NPPM_DMMSHOW`, `NPPM_DMMHIDE`, `NPPM_DMMUPDATEDISPINFO`, `NPPM_DMMGETPLUGINHWNDBYNAME`); `DWS_DF_CONT_*` / `DWS_DF_FLOATING` choose the side |
| Toolbar icons: `HBITMAP` / `HICON` | `NSImage *` in `toolbarIconsWithDarkMode` (`NPPM_ADDTOOLBARICON_FORDARKMODE`, sent while handling `NPPN_TBMODIFICATION`) |
| `NPPM_MODELESSDIALOG`, `NPPM_GETMENUHANDLE`, `NPPM_CREATESCINTILLAHANDLE` | Not available (return 0) |
| SEH: a crashing plugin shows an alert | C++ exceptions show an alert; a crash (bad memory access) ends Textpad++ |

Command ids are assigned from 22000 (`ID_PLUGINS_CMD`), dynamic ids from 23000 (`NPPM_ALLOCATECMDID`). Custom
shortcuts are saved in `shortcuts.xml` as `<PluginCommands><PluginCommand moduleName="X.tpplugin" internalID="n" …/>`,
keyed by bundle name and function index, as upstream does.

## Messages Textpad++ answers

Views and documents: `NPPM_GETCURRENTSCINTILLA`, `NPPM_GETCURRENTVIEW`, `NPPM_GETNBOPENFILES`,
`NPPM_GETCURRENTDOCINDEX`, `NPPM_ACTIVATEDOC`, `NPPM_GETCURRENTBUFFERID`, `NPPM_GETBUFFERIDFROMPOS`,
`NPPM_GETPOSFROMBUFFERID`, `NPPM_GETFULLPATHFROMBUFFERID`, `NPPM_GETBUFFERLANGTYPE`, `NPPM_SETBUFFERLANGTYPE`,
`NPPM_GETBUFFERENCODING`, `NPPM_GETBUFFERFORMAT`, `NPPM_GETCURRENTLANGTYPE`, `NPPM_SETCURRENTLANGTYPE`,
`NPPM_GETLANGUAGENAME`, `NPPM_GETLANGUAGEDESC`.

Files: `NPPM_DOOPEN`, `NPPM_SWITCHTOFILE`, `NPPM_SAVECURRENTFILE`, `NPPM_SAVEALLFILES`, `NPPM_SAVEFILE`,
`NPPM_SAVECURRENTFILEAS`, `NPPM_MENUCOMMAND`, `NPPM_SETMENUITEMCHECK`.

Paths and the caret (`RUNCOMMAND_USER`): `NPPM_GETFULLCURRENTPATH`, `NPPM_GETCURRENTDIRECTORY`, `NPPM_GETFILENAME`,
`NPPM_GETNAMEPART`, `NPPM_GETEXTPART`, `NPPM_GETCURRENTWORD`, `NPPM_GETNPPDIRECTORY`, `NPPM_GETNPPFULLFILEPATH`,
`NPPM_GETCURRENTLINE`, `NPPM_GETCURRENTCOLUMN`, `NPPM_GETCURRENTLINESTR`, `NPPM_GETPLUGINSCONFIGDIR`,
`NPPM_GETPLUGINHOMEPATH`, `NPPM_GETNPPSETTINGSDIRPATH`. These take the buffer size in `wParam` and return FALSE
when the text does not fit.

Application: `NPPM_GETNPPVERSION` (returns `(8 << 16) | 991`, API level 8.9.9.1),
`NPPM_ISDARKMODEENABLED`, `NPPM_GETEDITORDEFAULTFOREGROUNDCOLOR`, `NPPM_GETEDITORDEFAULTBACKGROUNDCOLOR`,
`NPPM_SETSTATUSBAR`, `NPPM_HIDETABBAR` / `NPPM_ISTABBARHIDDEN`, `NPPM_HIDETOOLBAR` / `NPPM_ISTOOLBARHIDDEN`,
`NPPM_HIDESTATUSBAR` / `NPPM_ISSTATUSBARHIDDEN`, `NPPM_ALLOCATECMDID`, `NPPM_ALLOCATEMARKER` (1–12),
`NPPM_ALLOCATEINDICATOR` (9–19), `NPPM_MSGTOPLUGIN`.

## Notifications sent

`NPPN_READY` (after launch, or right after an import), `NPPN_FILEOPENED`, `NPPN_BUFFERACTIVATED`,
`NPPN_FILEBEFORESAVE`, `NPPN_FILESAVED`, `NPPN_FILEBEFORECLOSE`, `NPPN_FILECLOSED`, `NPPN_LANGCHANGED`,
`NPPN_BEFORESHUTDOWN`, `NPPN_CANCELSHUTDOWN`, `NPPN_SHUTDOWN`. `nmhdr.hwndFrom` is `_nppHandle`; `nmhdr.idFrom` is
the buffer id. Scintilla notifications carry `_scintillaMainHandle` or `_scintillaSecondHandle` in `hwndFrom`.

## Removing a plugin

**Plugins Admin... > Installed > Remove** moves the plugin folder to the Trash and takes its commands out of the
menus at once. Its code stays loaded until Textpad++ quits (a loaded bundle cannot be unloaded safely). There is no
online list of Mac plugins yet: a build made with `make dmg UPDATE_URL=…` reads `pluginList.json` next to `update.xml`, and the Available / Updates tabs install from it (the zip's SHA-256 must match the list's `id`).
