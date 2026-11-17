// Textpad++ sample plugin: commands, a docking panel and a toolbar button; also used by the self-test (T-PLUG-*).
// Build: make sample-plugin  (build/plugins/SamplePlugin.tpplugin). Objective-C because panels are Cocoa views;
// a plugin without a panel can be plain C. GPL-3.0-or-later.
#import <Cocoa/Cocoa.h>
#include "TextpadPlusPlusPlugin.h"
#include <string.h>

static NppData npp;
static FuncItem funcs[5];
static NSView *panel;
static ShortcutKey helloKey = {true, true, true, 'H'};   // Ctrl+Alt+Shift+H (⌘⌥⇧H in the Mac scheme)
static int notifications[64];
static int charsAdded;
static char lastPath[1024];
static long lastMessage;

static void *currentScintilla(void) {
    int which = 0;
    npp.sendMessage(npp._nppHandle, NPPM_GETCURRENTSCINTILLA, 0, (intptr_t)&which);
    return which == 0 ? npp._scintillaMainHandle : npp._scintillaSecondHandle;
}

static void insertHello(void) {
    npp.sendMessage(currentScintilla(), SCI_REPLACESEL, 0, (intptr_t)"Hello from a plugin");
}

static void toggleCheck(void) {
    static bool on = true;   // starts checked (_init2Check)
    on = !on;
    npp.sendMessage(npp._nppHandle, NPPM_SETMENUITEMCHECK, (uintptr_t)funcs[2]._cmdID, on);
}

static void reportPath(void) {
    lastPath[0] = 0;
    npp.sendMessage(npp._nppHandle, NPPM_GETFULLCURRENTPATH, sizeof lastPath, (intptr_t)lastPath);
}

static void showPanel(void) {
    if (!panel) {
        panel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 120)];
        NSTextField *t = [NSTextField labelWithString:@"Hello from the sample plugin's panel"];
        t.frame = NSMakeRect(10, 50, 220, 20);
        [panel addSubview:t];
        static tTbData data;
        data.hClient = (__bridge void *)panel;
        data.pszName = "Sample Panel";
        data.dlgID = 4;
        data.uMask = DWS_DF_CONT_RIGHT;
        data.pszModuleName = "SamplePlugin.tpplugin";
        npp.sendMessage(npp._nppHandle, NPPM_DMMREGASDCKDLG, 0, (intptr_t)&data);
    } else {
        npp.sendMessage(npp._nppHandle, NPPM_DMMSHOW, 0, (intptr_t)(__bridge void *)panel);
    }
}

void setInfo(NppData data) {
    npp = data;
    strcpy(funcs[0]._itemName, "Insert Hello");
    funcs[0]._pFunc = insertHello;
    funcs[0]._pShKey = &helloKey;
    funcs[1]._pFunc = NULL;                                   // separator
    strcpy(funcs[2]._itemName, "Toggle Check");
    funcs[2]._pFunc = toggleCheck;
    funcs[2]._init2Check = true;
    strcpy(funcs[3]._itemName, "Report Path");
    funcs[3]._pFunc = reportPath;
    strcpy(funcs[4]._itemName, "Show Panel");
    funcs[4]._pFunc = showPanel;
}

const char *getName(void) { return "Sample Plugin"; }
FuncItem *getFuncsArray(int *count) { *count = 5; return funcs; }
int tppPluginAPIVersion(void) { return TPP_PLUGIN_API_VERSION; }

void beNotified(SCNotification *n) {
    if (n->nmhdr.hwndFrom == npp._nppHandle && n->nmhdr.code == NPPN_TBMODIFICATION) {   // our toolbar button
        static toolbarIconsWithDarkMode icons;
        static NSImage *img;
        img = [NSImage imageWithSystemSymbolName:@"hand.wave.fill" accessibilityDescription:@"Insert Hello"];
        icons.hToolbarIcon = (__bridge void *)img;
        icons.hToolbarIconDarkMode = (__bridge void *)img;
        icons.hToolbarBmp = (__bridge void *)img;
        npp.sendMessage(npp._nppHandle, NPPM_ADDTOOLBARICON_FORDARKMODE, (uintptr_t)funcs[0]._cmdID, (intptr_t)&icons);
    }
    if (n->nmhdr.hwndFrom == npp._nppHandle && n->nmhdr.code >= NPPN_FIRST && n->nmhdr.code < NPPN_FIRST + 64)
        notifications[n->nmhdr.code - NPPN_FIRST]++;
    else if ((n->nmhdr.hwndFrom == npp._scintillaMainHandle || n->nmhdr.hwndFrom == npp._scintillaSecondHandle) && n->nmhdr.code == SCN_CHARADDED)
        charsAdded++;
}

intptr_t messageProc(uint32_t message, uintptr_t wParam, intptr_t lParam) {
    if (message == NPPM_MSGTOPLUGIN && lParam) lastMessage = ((CommunicationInfo *)lParam)->internalMsg;
    return 1;
}

// read by the self-test through CFBundleGetFunctionPointerForName
int sample_notificationCount(unsigned code) { return code >= NPPN_FIRST && code < NPPN_FIRST + 64 ? notifications[code - NPPN_FIRST] : 0; }
int sample_charsAdded(void) { return charsAdded; }
const char *sample_lastPath(void) { return lastPath; }
long sample_lastMessage(void) { return lastMessage; }
void *sample_panelView(void) { return (__bridge void *)panel; }
