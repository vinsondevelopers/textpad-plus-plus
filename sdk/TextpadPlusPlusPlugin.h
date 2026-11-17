// Textpad++ plugin SDK for macOS — TextpadPlusPlusPlugin.h. GPL-3.0-or-later.
//
// A plugin is a macOS loadable bundle "<Name>.tpplugin" installed as
//   ~/Library/Application Support/Textpad++/plugins/<Name>/<Name>.tpplugin
// (Settings > Import > Import plugin(s)... copies it there). It exports the same five C functions as a
// Windows editor plugin DLL of the same family (PluginInterface.h): setInfo, getName, getFuncsArray, beNotified, messageProc.
//
// Differences from the Windows plugin interface (API level 8.9.9.1), because Win32 does not exist here:
//   * strings are UTF-8 (char), never wchar_t: FuncItem._itemName, getName(), and every NPPM_* string parameter;
//   * handles are opaque pointers; send messages with NppData.sendMessage(handle, msg, wParam, lParam)
//     instead of ::SendMessage(HWND, ...): the editor handle (_nppHandle) takes NPPM_* messages, the two Scintilla
//     handles take SCI_* messages (Scintilla 5.6, same numbers as on Windows);
//   * ShortcutKey._isCtrl is the Command key (⌘) unless the user chose the Windows shortcut scheme;
//     _key is a Windows virtual-key code as upstream ('A'–'Z', '0'–'9', VK_F1 = 0x70 ...);
//   * docking dialogs (NPPM_DMMREGASDCKDLG ...) take an NSView * in tTbData.hClient, toolbar icons
//     (NPPM_ADDTOOLBARICON_FORDARKMODE) NSImage * in toolbarIconsWithDarkMode;
//   * Win32-only messages (NPPM_MODELESSDIALOG, NPPM_GETMENUHANDLE, NPPM_CREATESCINTILLAHANDLE ...) return 0.
// The messages answered by Textpad++ are listed in docs/PLUGINS.md.
#pragma once
#include <stdint.h>
#include <stdbool.h>
#include "Scintilla.h"

#ifdef __cplusplus
extern "C" {
#endif

#define TPP_PLUGIN_API_VERSION 1

#ifndef WM_USER
#define WM_USER    0x0400
#endif
#ifndef WM_COMMAND
#define WM_COMMAND 0x0111
#endif

// ---------------------------------------------------------------- message numbers (the Windows plugin interface, API level 8.9.9.1)
enum LangType {L_TEXT, L_PHP , L_C, L_CPP, L_CS, L_OBJC, L_JAVA, L_RC,\
			   L_HTML, L_XML, L_MAKEFILE, L_PASCAL, L_BATCH, L_INI, L_ASCII, L_USER,\
			   // Don't use L_JS_EMBEDDED, use L_JAVASCRIPT instead
			   L_ASP, L_SQL, L_VB, L_JS_EMBEDDED, L_CSS, L_PERL, L_PYTHON, L_LUA, \
			   L_TEX, L_FORTRAN, L_BASH, L_FLASH, L_NSIS, L_TCL, L_LISP, L_SCHEME,\
			   L_ASM, L_DIFF, L_PROPS, L_PS, L_RUBY, L_SMALLTALK, L_VHDL, L_KIX, L_AU3,\
			   L_CAML, L_ADA, L_VERILOG, L_MATLAB, L_HASKELL, L_INNO, L_SEARCHRESULT,\
			   L_CMAKE, L_YAML, L_COBOL, L_GUI4CLI, L_D, L_POWERSHELL, L_R, L_JSP,\
			   L_COFFEESCRIPT, L_JSON, L_JAVASCRIPT, L_FORTRAN_77, L_BAANC, L_SREC,\
			   L_IHEX, L_TEHEX, L_SWIFT,\
			   L_ASN1, L_AVS, L_BLITZBASIC, L_PUREBASIC, L_FREEBASIC, \
			   L_CSOUND, L_ERLANG, L_ESCRIPT, L_FORTH, L_LATEX, \
			   L_MMIXAL, L_NIM, L_NNCRONTAB, L_OSCRIPT, L_REBOL, \
			   L_REGISTRY, L_RUST, L_SPICE, L_TXT2TAGS, L_VISUALPROLOG,\
			   L_TYPESCRIPT, L_JSON5, L_MSSQL, L_GDSCRIPT, L_HOLLYWOOD,\
			   L_GOLANG, L_RAKU, L_TOML, L_SAS, L_ERRORLIST, L_ESCSEQ, L_STTXT,\
			   // The end of enumerated language type, so it should be always at the end
			   L_EXTERNAL};

#define NPPMSG                                           (WM_USER + 1000)
#define NPPM_GETCURRENTSCINTILLA                         (NPPMSG + 4)
#define NPPM_GETCURRENTLANGTYPE                          (NPPMSG + 5)
#define NPPM_SETCURRENTLANGTYPE                          (NPPMSG + 6)
#define NPPM_GETNBOPENFILES                              (NPPMSG + 7)
#define ALL_OPEN_FILES                                   0
#define PRIMARY_VIEW                                     1
#define SECOND_VIEW                                      2
#define NPPM_GETOPENFILENAMES_DEPRECATED                 (NPPMSG + 8)
#define NPPM_MODELESSDIALOG                              (NPPMSG + 12)
#define MODELESSDIALOGADD                                0
#define MODELESSDIALOGREMOVE                             1
#define NPPM_GETNBSESSIONFILES                           (NPPMSG + 13)
#define NPPM_GETSESSIONFILES                             (NPPMSG + 14)
#define NPPM_SAVESESSION                                 (NPPMSG + 15)
#define NPPM_SAVECURRENTSESSION                          (NPPMSG + 16)
#define NPPM_GETOPENFILENAMESPRIMARY_DEPRECATED          (NPPMSG + 17)
#define NPPM_GETOPENFILENAMESSECOND_DEPRECATED           (NPPMSG + 18)
#define NPPM_CREATESCINTILLAHANDLE                       (NPPMSG + 20)
#define NPPM_DESTROYSCINTILLAHANDLE_DEPRECATED           (NPPMSG + 21)
#define NPPM_GETNBUSERLANG                               (NPPMSG + 22)
#define NPPM_GETCURRENTDOCINDEX                          (NPPMSG + 23)
#define MAIN_VIEW                                        0
#define SUB_VIEW                                         1
#define NPPM_SETSTATUSBAR                                (NPPMSG + 24)
#define STATUSBAR_DOC_TYPE                               0
#define STATUSBAR_DOC_SIZE                               1
#define STATUSBAR_CUR_POS                                2
#define STATUSBAR_EOF_FORMAT                             3
#define STATUSBAR_UNICODE_TYPE                           4
#define STATUSBAR_TYPING_MODE                            5
#define NPPM_GETMENUHANDLE                               (NPPMSG + 25)
#define NPPPLUGINMENU                                    0
#define NPPMAINMENU                                      1
#define NPPM_ENCODESCI                                   (NPPMSG + 26)
#define NPPM_DECODESCI                                   (NPPMSG + 27)
#define NPPM_ACTIVATEDOC                                 (NPPMSG + 28)
#define NPPM_LAUNCHFINDINFILESDLG                        (NPPMSG + 29)
#define NPPM_DMMSHOW                                     (NPPMSG + 30)
#define NPPM_DMMHIDE                                     (NPPMSG + 31)
#define NPPM_DMMUPDATEDISPINFO                           (NPPMSG + 32)
#define NPPM_DMMREGASDCKDLG                              (NPPMSG + 33)
#define NPPM_LOADSESSION                                 (NPPMSG + 34)
#define NPPM_DMMVIEWOTHERTAB                             (NPPMSG + 35)
#define NPPM_RELOADFILE                                  (NPPMSG + 36)
#define NPPM_SWITCHTOFILE                                (NPPMSG + 37)
#define NPPM_SAVECURRENTFILE                             (NPPMSG + 38)
#define NPPM_SAVEALLFILES                                (NPPMSG + 39)
#define NPPM_SETMENUITEMCHECK                            (NPPMSG + 40)
#define NPPM_ADDTOOLBARICON_DEPRECATED                   (NPPMSG + 41)
#define NPPM_GETWINDOWSVERSION                           (NPPMSG + 42)
#define NPPM_DMMGETPLUGINHWNDBYNAME                      (NPPMSG + 43)
#define NPPM_MAKECURRENTBUFFERDIRTY                      (NPPMSG + 44)
#define NPPM_GETENABLETHEMETEXTUREFUNC_DEPRECATED        (NPPMSG + 45)
#define NPPM_GETPLUGINSCONFIGDIR                         (NPPMSG + 46)
#define NPPM_MSGTOPLUGIN                                 (NPPMSG + 47)
#define NPPM_MENUCOMMAND                                 (NPPMSG + 48)
#define NPPM_TRIGGERTABBARCONTEXTMENU                    (NPPMSG + 49)
#define NPPM_GETNPPVERSION                               (NPPMSG + 50)
#define NPPM_HIDETABBAR                                  (NPPMSG + 51)
#define NPPM_ISTABBARHIDDEN                              (NPPMSG + 52)
#define NPPM_GETPOSFROMBUFFERID                          (NPPMSG + 57)
#define NPPM_GETFULLPATHFROMBUFFERID                     (NPPMSG + 58)
#define NPPM_GETBUFFERIDFROMPOS                          (NPPMSG + 59)
#define NPPM_GETCURRENTBUFFERID                          (NPPMSG + 60)
#define NPPM_RELOADBUFFERID                              (NPPMSG + 61)
#define NPPM_GETBUFFERLANGTYPE                           (NPPMSG + 64)
#define NPPM_SETBUFFERLANGTYPE                           (NPPMSG + 65)
#define NPPM_GETBUFFERENCODING                           (NPPMSG + 66)
#define NPPM_SETBUFFERENCODING                           (NPPMSG + 67)
#define NPPM_GETBUFFERFORMAT                             (NPPMSG + 68)
#define NPPM_SETBUFFERFORMAT                             (NPPMSG + 69)
#define NPPM_HIDETOOLBAR                                 (NPPMSG + 70)
#define NPPM_ISTOOLBARHIDDEN                             (NPPMSG + 71)
#define NPPM_HIDEMENU                                    (NPPMSG + 72)
#define NPPM_ISMENUHIDDEN                                (NPPMSG + 73)
#define NPPM_HIDESTATUSBAR                               (NPPMSG + 74)
#define NPPM_ISSTATUSBARHIDDEN                           (NPPMSG + 75)
#define NPPM_GETSHORTCUTBYCMDID                          (NPPMSG + 76)
#define NPPM_DOOPEN                                      (NPPMSG + 77)
#define NPPM_SAVECURRENTFILEAS                           (NPPMSG + 78)
#define NPPM_GETCURRENTNATIVELANGENCODING                (NPPMSG + 79)
#define NPPM_ALLOCATESUPPORTED_DEPRECATED                (NPPMSG + 80)
#define NPPM_ALLOCATECMDID                               (NPPMSG + 81)
#define NPPM_ALLOCATEMARKER                              (NPPMSG + 82)
#define NPPM_GETLANGUAGENAME                             (NPPMSG + 83)
#define NPPM_GETLANGUAGEDESC                             (NPPMSG + 84)
#define NPPM_SHOWDOCLIST                                 (NPPMSG + 85)
#define NPPM_ISDOCLISTSHOWN                              (NPPMSG + 86)
#define NPPM_GETAPPDATAPLUGINSALLOWED                    (NPPMSG + 87)
#define NPPM_GETCURRENTVIEW                              (NPPMSG + 88)
#define NPPM_DOCLISTDISABLEEXTCOLUMN                     (NPPMSG + 89)
#define NPPM_DOCLISTDISABLEPATHCOLUMN                    (NPPMSG + 102)
#define NPPM_GETEDITORDEFAULTFOREGROUNDCOLOR             (NPPMSG + 90)
#define NPPM_GETEDITORDEFAULTBACKGROUNDCOLOR             (NPPMSG + 91)
#define NPPM_SETSMOOTHFONT                               (NPPMSG + 92)
#define NPPM_SETEDITORBORDEREDGE                         (NPPMSG + 93)
#define NPPM_SAVEFILE                                    (NPPMSG + 94)
#define NPPM_DISABLEAUTOUPDATE                           (NPPMSG + 95)
#define NPPM_REMOVESHORTCUTBYCMDID                       (NPPMSG + 96)
#define NPPM_GETPLUGINHOMEPATH                           (NPPMSG + 97)
#define NPPM_GETSETTINGSONCLOUDPATH                      (NPPMSG + 98)
#define NPPM_SETLINENUMBERWIDTHMODE                      (NPPMSG + 99)
#define LINENUMWIDTH_DYNAMIC                             0
#define LINENUMWIDTH_CONSTANT                            1
#define NPPM_GETLINENUMBERWIDTHMODE                      (NPPMSG + 100)
#define NPPM_ADDTOOLBARICON_FORDARKMODE                  (NPPMSG + 101)
#define NPPM_GETEXTERNALLEXERAUTOINDENTMODE              (NPPMSG + 103)
#define NPPM_SETEXTERNALLEXERAUTOINDENTMODE              (NPPMSG + 104)
#define NPPM_ISAUTOINDENTON                              (NPPMSG + 105)
#define NPPM_GETCURRENTMACROSTATUS                       (NPPMSG + 106)
#define NPPM_ISDARKMODEENABLED                           (NPPMSG + 107)
#define NPPM_GETDARKMODECOLORS                           (NPPMSG + 108)
#define NPPM_GETCURRENTCMDLINE                           (NPPMSG + 109)
#define NPPM_CREATELEXER                                 (NPPMSG + 110)
#define NPPM_GETBOOKMARKID                               (NPPMSG + 111)
#define NPPM_DARKMODESUBCLASSANDTHEME                    (NPPMSG + 112)
#define NPPM_ALLOCATEINDICATOR                           (NPPMSG + 113)
#define NPPM_GETTABCOLORID                               (NPPMSG + 114)
#define NPPM_SETUNTITLEDNAME                             (NPPMSG + 115)
#define NPPM_GETNATIVELANGFILENAME                       (NPPMSG + 116)
#define NPPM_ADDSCNMODIFIEDFLAGS                         (NPPMSG + 117)
#define NPPM_GETTOOLBARICONSETCHOICE                     (NPPMSG + 118)
#define NPPM_GETNPPSETTINGSDIRPATH                       (NPPMSG + 119)
#define VAR_NOT_RECOGNIZED                               0
#define FULL_CURRENT_PATH                                1
#define CURRENT_DIRECTORY                                2
#define FILE_NAME                                        3
#define NAME_PART                                        4
#define EXT_PART                                         5
#define CURRENT_WORD                                     6
#define NPP_DIRECTORY                                    7
#define CURRENT_LINE                                     8
#define CURRENT_COLUMN                                   9
#define NPP_FULL_FILE_PATH                               10
#define GETFILENAMEATCURSOR                              11
#define CURRENT_LINESTR                                  12
#define RUNCOMMAND_USER                                  (WM_USER + 3000)
#define NPPM_GETFULLCURRENTPATH                          (RUNCOMMAND_USER + FULL_CURRENT_PATH)
#define NPPM_GETCURRENTDIRECTORY                         (RUNCOMMAND_USER + CURRENT_DIRECTORY)
#define NPPM_GETFILENAME                                 (RUNCOMMAND_USER + FILE_NAME)
#define NPPM_GETNAMEPART                                 (RUNCOMMAND_USER + NAME_PART)
#define NPPM_GETEXTPART                                  (RUNCOMMAND_USER + EXT_PART)
#define NPPM_GETCURRENTWORD                              (RUNCOMMAND_USER + CURRENT_WORD)
#define NPPM_GETNPPDIRECTORY                             (RUNCOMMAND_USER + NPP_DIRECTORY)
#define NPPM_GETNPPFULLFILEPATH                          (RUNCOMMAND_USER + NPP_FULL_FILE_PATH)
#define NPPM_GETFILENAMEATCURSOR                         (RUNCOMMAND_USER + GETFILENAMEATCURSOR)
#define NPPM_GETCURRENTLINESTR                           (RUNCOMMAND_USER + CURRENT_LINESTR)
#define NPPM_GETCURRENTLINE                              (RUNCOMMAND_USER + CURRENT_LINE)
#define NPPM_GETCURRENTCOLUMN                            (RUNCOMMAND_USER + CURRENT_COLUMN)
#define NPPN_FIRST                                       1000
#define NPPN_READY                                       (NPPN_FIRST + 1)
#define NPPN_TBMODIFICATION                              (NPPN_FIRST + 2)
#define NPPN_FILEBEFORECLOSE                             (NPPN_FIRST + 3)
#define NPPN_FILEOPENED                                  (NPPN_FIRST + 4)
#define NPPN_FILECLOSED                                  (NPPN_FIRST + 5)
#define NPPN_FILEBEFOREOPEN                              (NPPN_FIRST + 6)
#define NPPN_FILEBEFORESAVE                              (NPPN_FIRST + 7)
#define NPPN_FILESAVED                                   (NPPN_FIRST + 8)
#define NPPN_SHUTDOWN                                    (NPPN_FIRST + 9)
#define NPPN_BUFFERACTIVATED                             (NPPN_FIRST + 10)
#define NPPN_LANGCHANGED                                 (NPPN_FIRST + 11)
#define NPPN_WORDSTYLESUPDATED                           (NPPN_FIRST + 12)
#define NPPN_SHORTCUTREMAPPED                            (NPPN_FIRST + 13)
#define NPPN_FILEBEFORELOAD                              (NPPN_FIRST + 14)
#define NPPN_FILELOADFAILED                              (NPPN_FIRST + 15)
#define NPPN_READONLYCHANGED                             (NPPN_FIRST + 16)
#define DOCSTATUS_READONLY                               1
#define DOCSTATUS_BUFFERDIRTY                            2
#define NPPN_DOCORDERCHANGED                             (NPPN_FIRST + 17)
#define NPPN_SNAPSHOTDIRTYFILELOADED                     (NPPN_FIRST + 18)
#define NPPN_BEFORESHUTDOWN                              (NPPN_FIRST + 19)
#define NPPN_CANCELSHUTDOWN                              (NPPN_FIRST + 20)
#define NPPN_FILEBEFORERENAME                            (NPPN_FIRST + 21)
#define NPPN_FILERENAMECANCEL                            (NPPN_FIRST + 22)
#define NPPN_FILERENAMED                                 (NPPN_FIRST + 23)
#define NPPN_FILEBEFOREDELETE                            (NPPN_FIRST + 24)
#define NPPN_FILEDELETEFAILED                            (NPPN_FIRST + 25)
#define NPPN_FILEDELETED                                 (NPPN_FIRST + 26)
#define NPPN_DARKMODECHANGED                             (NPPN_FIRST + 27)
#define NPPN_CMDLINEPLUGINMSG                            (NPPN_FIRST + 28)
#define NPPN_EXTERNALLEXERBUFFER                         (NPPN_FIRST + 29)
#define NPPN_GLOBALMODIFIED                              (NPPN_FIRST + 30)
#define NPPN_NATIVELANGCHANGED                           (NPPN_FIRST + 31)
#define NPPN_TOOLBARICONSETCHANGED                       (NPPN_FIRST + 32)

// ---------------------------------------------------------------- macOS plugin interface (upstream PluginInterface.h)
typedef intptr_t (*TPPSendMessageFunc)(void *handle, uint32_t message, uintptr_t wParam, intptr_t lParam);

typedef struct NppData {
    void *_nppHandle;                   // NPPM_* messages
    void *_scintillaMainHandle;         // SCI_* messages to the main view
    void *_scintillaSecondHandle;       // SCI_* messages to the second view
    TPPSendMessageFunc sendMessage;     // the stand-in for ::SendMessage
} NppData;

typedef struct ShortcutKey {
    bool _isCtrl;
    bool _isAlt;
    bool _isShift;
    unsigned char _key;
} ShortcutKey;

#define menuItemSize 64

typedef void (*PFUNCPLUGINCMD)(void);

typedef struct FuncItem {
    char _itemName[menuItemSize];       // UTF-8; a NULL _pFunc makes a separator
    PFUNCPLUGINCMD _pFunc;
    int _cmdID;                         // set by Textpad++ (22000 and up, upstream ID_PLUGINS_CMD)
    bool _init2Check;
    ShortcutKey *_pShKey;               // default shortcut, or NULL
} FuncItem;

// docking dialogs (upstream Docking.h): NPPM_DMMREGASDCKDLG(0, tTbData *), NPPM_DMMSHOW / NPPM_DMMHIDE(0, NSView *)
#define CONT_LEFT    0
#define CONT_RIGHT   1
#define CONT_TOP     2
#define CONT_BOTTOM  3
#define DWS_ICONTAB         0x00000001
#define DWS_ICONBAR         0x00000002
#define DWS_ADDINFO         0x00000004
#define DWS_USEOWNDARKMODE  0x00000008
#define DWS_DF_CONT_LEFT    (CONT_LEFT << 28)
#define DWS_DF_CONT_RIGHT   (CONT_RIGHT << 28)
#define DWS_DF_CONT_TOP     (CONT_TOP << 28)
#define DWS_DF_CONT_BOTTOM  (CONT_BOTTOM << 28)
#define DWS_DF_FLOATING     0x80000000

typedef struct tTbData {
    void *hClient;              // NSView * — the panel's content
    const char *pszName;        // caption (UTF-8)
    int dlgID;                  // the FuncItem index that shows it
    unsigned int uMask;         // DWS_DF_CONT_* or DWS_DF_FLOATING, plus DWS_ADDINFO
    void *hIconTab;             // NSImage *, optional
    const char *pszAddInfo;     // shown after the caption with DWS_ADDINFO
    int rcFloat[4];
    int iPrevCont;
    const char *pszModuleName;  // e.g. "MyPlugin.tpplugin"
} tTbData;

// NPPM_ADDTOOLBARICON_FORDARKMODE(int cmdID, toolbarIconsWithDarkMode *): send it while handling NPPN_TBMODIFICATION
typedef struct toolbarIconsWithDarkMode {
    void *hToolbarBmp;            // NSImage *, Standard icons
    void *hToolbarIcon;           // NSImage *, light Fluent / Colourful icons
    void *hToolbarIconDarkMode;   // NSImage *, dark mode (optional)
} toolbarIconsWithDarkMode;

// NPPM_MSGTOPLUGIN(const char *destModuleName, CommunicationInfo *info)
typedef struct CommunicationInfo {
    long internalMsg;
    const char *srcModuleName;          // e.g. "MyPlugin.tpplugin"
    void *info;
} CommunicationInfo;

// The exports Textpad++ looks up (all required; tppPluginAPIVersion is optional and must return
// TPP_PLUGIN_API_VERSION when present).
void setInfo(NppData data);
const char *getName(void);
FuncItem *getFuncsArray(int *count);
void beNotified(SCNotification *notification);
intptr_t messageProc(uint32_t message, uintptr_t wParam, intptr_t lParam);
int tppPluginAPIVersion(void);

#ifdef __cplusplus
}
#endif
