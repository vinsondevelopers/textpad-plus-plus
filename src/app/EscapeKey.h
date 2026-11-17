// Textpad++ — Escape closes pop-ups and dialogs: alerts, sheets, modal windows and tool windows (Preferences, Style
// Configurator, Shortcut Mapper, Find...). The editor window keeps its own Escape (auto-completion, multi-selection,
// Incremental Search). GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
// the button Escape presses in `window`: Cancel / Close / No / Later / Not Now / Skip / Done / OK, or the only button
NSButton *_Nullable TPEscapeButtonInWindow(NSWindow *window);
// closes `window` for Escape; NO when Escape belongs to it (the editor window, a docked panel window, a button that
// already answers Escape)
BOOL TPHandleEscapeInWindow(NSWindow *window, NSWindow *_Nullable editorWindow);
void TPInstallEscapeMonitor(NSWindow *editorWindow);
NS_ASSUME_NONNULL_END
