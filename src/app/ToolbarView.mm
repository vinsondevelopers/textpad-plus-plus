// Textpad++ — toolbar and status bar. GPL-3.0-or-later.
// Button order: upstream Notepad_plus.cpp toolBarIcons[]. Status bar part widths: upstream
// Notepad_plus.cpp (220, 260, 110, 120, 45 px at 96 dpi).
#import "app/ToolbarView.h"
#import "commands/CommandRegistry.h"
#import "app/Preferences.h"

using namespace npp;

struct ToolButton { int cmd; const char *icon; };
static const ToolButton kButtons[] = {
    {IDM_FILE_NEW, "newFile"}, {IDM_FILE_OPEN, "openFile"}, {IDM_FILE_SAVE, "saveFile"}, {IDM_FILE_SAVEALL, "saveAll"},
    {IDM_FILE_CLOSE, "closeFile"}, {IDM_FILE_CLOSEALL, "closeAll"}, {IDM_FILE_PRINT, "print"}, {0, nullptr},
    {IDM_EDIT_CUT, "cut"}, {IDM_EDIT_COPY, "copy"}, {IDM_EDIT_PASTE, "paste"}, {0, nullptr},
    {IDM_EDIT_UNDO, "undo"}, {IDM_EDIT_REDO, "redo"}, {0, nullptr},
    {IDM_SEARCH_FIND, "find"}, {IDM_SEARCH_REPLACE, "findReplace"}, {0, nullptr},
    {IDM_VIEW_ZOOMIN, "zoomIn"}, {IDM_VIEW_ZOOMOUT, "zoomOut"}, {0, nullptr},
    {IDM_VIEW_SYNSCROLLV, "syncV"}, {IDM_VIEW_SYNSCROLLH, "syncH"}, {0, nullptr},
    {IDM_VIEW_WRAP, "wrap"}, {IDM_VIEW_ALL_CHARACTERS, "allChars"}, {IDM_VIEW_INDENT_GUIDE, "indentGuide"}, {0, nullptr},
    {IDM_LANG_USER_DLG, "udl"}, {IDM_VIEW_DOC_MAP, "docMap"}, {IDM_VIEW_DOCLIST, "docList"}, {IDM_VIEW_FUNC_LIST, "funcList"},
    {IDM_VIEW_FILEBROWSER, "fileBrowser"}, {0, nullptr}, {IDM_VIEW_MONITORING, "monitoring"}, {0, nullptr},
    {IDM_MACRO_STARTRECORDINGMACRO, "startRecord"}, {IDM_MACRO_STOPRECORDINGMACRO, "stopRecord"},
    {IDM_MACRO_PLAYBACKRECORDEDMACRO, "playRecord"}, {IDM_MACRO_RUNMULTIMACRODLG, "playRecord_m"},
    {IDM_MACRO_SAVECURRENTMACRO, "saveRecord"},
};

// Upstream loads these 16x16 8-bit bitmaps with LR_LOADTRANSPARENT and masks the 3D-face grey
// (RGB 192,192,192); the same key colour is made transparent here.
static NSImage *loadToolbarBitmap(NSString *name, BOOL disabled) {
    NSString *p = [[NSBundle mainBundle] pathForResource:name ofType:@"bmp" inDirectory:@"icons/toolbar"];
    if (!p) return nil;
    NSBitmapImageRep *src = [NSBitmapImageRep imageRepWithData:[NSData dataWithContentsOfFile:p]];
    if (!src) return nil;
    NSInteger w = src.pixelsWide, h = src.pixelsHigh;
    NSBitmapImageRep *dst = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:w pixelsHigh:h bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:w * 4 bitsPerPixel:32];
    for (NSInteger y = 0; y < h; ++y) {
        for (NSInteger x = 0; x < w; ++x) {
            NSColor *c = [[src colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
            int r = (int)lround(c.redComponent * 255), g = (int)lround(c.greenComponent * 255), b = (int)lround(c.blueComponent * 255);
            unsigned char *px = dst.bitmapData + y * dst.bytesPerRow + x * 4;
            if (r == 192 && g == 192 && b == 192) { px[0] = px[1] = px[2] = px[3] = 0; continue; }
            if (disabled) {  // greyed like a Win32 disabled toolbar button
                int gray = (r * 30 + g * 59 + b * 11) / 100;
                gray = 128 + gray / 2;
                r = g = b = gray;
            }
            px[0] = (unsigned char)r; px[1] = (unsigned char)g; px[2] = (unsigned char)b; px[3] = 255;
        }
    }
    NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
    [img addRepresentation:dst];
    return img;
}

// "Colourful" icon set: flat two-tone icons from SF Symbols with a fixed palette per button
// {SF Symbol name, colour of the inner mark (white on filled shapes), colour of the shape}
static NSColor *hexColor(uint32_t c) { return [NSColor colorWithSRGBRed:((c >> 16) & 0xFF) / 255.0 green:((c >> 8) & 0xFF) / 255.0 blue:(c & 0xFF) / 255.0 alpha:1]; }
static NSArray *colourfulSpec(NSString *std) {
    static NSDictionary *m;
    if (!m) m = @{
        @"newFile": @[@"doc.fill.badge.plus", @0x2F80ED, @0x27AE60], @"openFile": @[@"folder.fill", @0xF2B01E, @0xF2B01E],
        @"saveFile": @[@"arrow.down.doc.fill", @0xFFFFFF, @0x2F80ED], @"saveAll": @[@"tray.and.arrow.down.fill", @0x8E44AD, @0x8E44AD],
        @"closeFile": @[@"xmark.square.fill", @0xFFFFFF, @0xE74C3C], @"closeAll": @[@"xmark.circle.fill", @0xFFFFFF, @0xE67E22],
        @"print": @[@"printer.fill", @0x34495E, @0x5D6D7E], @"cut": @[@"scissors", @0xE74C3C, @0xE74C3C],
        @"copy": @[@"doc.on.doc.fill", @0x2F80ED, @0x2F80ED], @"paste": @[@"doc.on.clipboard.fill", @0xB9770E, @0xB9770E],
        @"undo": @[@"arrow.uturn.backward.circle.fill", @0xFFFFFF, @0x16A085], @"redo": @[@"arrow.uturn.forward.circle.fill", @0xFFFFFF, @0x16A085],
        @"find": @[@"magnifyingglass.circle.fill", @0xFFFFFF, @0x2F80ED], @"findReplace": @[@"arrow.triangle.2.circlepath.circle.fill", @0xFFFFFF, @0xE67E22],
        @"zoomIn": @[@"plus.magnifyingglass", @0x27AE60, @0x27AE60], @"zoomOut": @[@"minus.magnifyingglass", @0xE74C3C, @0xE74C3C],
        @"syncV": @[@"arrow.up.and.down.square.fill", @0xFFFFFF, @0x5B5FC7], @"syncH": @[@"arrow.left.and.right.square.fill", @0xFFFFFF, @0x5B5FC7],
        @"wrap": @[@"arrow.turn.down.left", @0x16A085, @0x16A085], @"allChars": @[@"paragraphsign", @0x8E44AD, @0x8E44AD],
        @"indentGuide": @[@"increase.indent", @0x2F80ED, @0x7F8C8D], @"udl": @[@"chevron.left.forwardslash.chevron.right", @0xD35485, @0xD35485],
        @"docMap": @[@"map.fill", @0x27AE60, @0x27AE60], @"docList": @[@"list.bullet.rectangle.fill", @0xFFFFFF, @0x2F80ED],
        @"funcList": @[@"function", @0x8E44AD, @0x8E44AD], @"fileBrowser": @[@"folder.fill.badge.gearshape", @0xF2B01E, @0x7F8C8D],
        @"monitoring": @[@"eye.fill", @0xE67E22, @0xE67E22], @"startRecord": @[@"record.circle.fill", @0xFFFFFF, @0xE74C3C],
        @"stopRecord": @[@"stop.circle.fill", @0xFFFFFF, @0x7F8C8D], @"playRecord": @[@"play.circle.fill", @0xFFFFFF, @0x27AE60],
        @"playRecord_m": @[@"forward.circle.fill", @0xFFFFFF, @0x27AE60], @"saveRecord": @[@"square.and.arrow.down.fill", @0x2F80ED, @0x2F80ED],
    };
    return m[std];
}

// what each button does, for its tooltip (name and shortcut come from the command)
static NSString *buttonDescription(NSString *std) {
    static NSDictionary *d = @{
        @"newFile": @"Creates a new, empty document in a new tab.",
        @"openFile": @"Opens one or more files from disk.",
        @"saveFile": @"Saves the current document (Save As for a new one).",
        @"saveAll": @"Saves every modified document.",
        @"closeFile": @"Closes the current document (asks to save changes).",
        @"closeAll": @"Closes every open document (asks to save changes).",
        @"print": @"Prints the current document.",
        @"cut": @"Cuts the selection to the clipboard (the whole line when nothing is selected).",
        @"copy": @"Copies the selection to the clipboard (the whole line when nothing is selected).",
        @"paste": @"Pastes the clipboard at the caret.",
        @"undo": @"Undoes the last change.",
        @"redo": @"Redoes the last undone change.",
        @"find": @"Opens the Find dialog to search the document, all open documents or files.",
        @"findReplace": @"Opens the Replace dialog to find and replace text.",
        @"zoomIn": @"Makes the text larger in this view.",
        @"zoomOut": @"Makes the text smaller in this view.",
        @"syncV": @"Scrolls both views up and down together.",
        @"syncH": @"Scrolls both views left and right together.",
        @"wrap": @"Wraps long lines at the window edge instead of scrolling sideways.",
        @"allChars": @"Shows spaces, tabs and line endings as visible symbols.",
        @"indentGuide": @"Shows vertical guide lines at each indentation level.",
        @"udl": @"Opens the editor for your own syntax-highlighting languages (User Defined Language).",
        @"docMap": @"Shows the Document Map: a miniature of the whole document to navigate with.",
        @"docList": @"Shows the Document List: every open document in a sortable list.",
        @"funcList": @"Shows the Function List: the functions and classes of the current file.",
        @"fileBrowser": @"Shows Folder as Workspace: browse and open the files of a folder.",
        @"monitoring": @"Follows the file as it grows on disk (tail -f), for log files.",
        @"startRecord": @"Starts recording a macro of your edits.",
        @"stopRecord": @"Stops recording the macro.",
        @"playRecord": @"Plays back the recorded macro once.",
        @"playRecord_m": @"Plays back a macro several times or until the end of the file.",
        @"saveRecord": @"Saves the recorded macro under a name, with an optional shortcut.",
    };
    return d[std];
}

static NSImage *loadColourfulIcon(NSString *std, CGFloat size, BOOL disabled) {
    NSArray *spec = colourfulSpec(std);
    if (!spec) return nil;
    NSImage *sym = [NSImage imageWithSystemSymbolName:spec[0] accessibilityDescription:nil];
    if (!sym) return nil;
    NSColor *a = disabled ? ([spec[1] unsignedIntValue] == 0xFFFFFF ? [NSColor colorWithWhite:1 alpha:0.6] : [NSColor colorWithWhite:0.55 alpha:0.45])
                          : hexColor([spec[1] unsignedIntValue]);
    NSColor *b = disabled ? [NSColor colorWithWhite:0.55 alpha:0.45] : hexColor([spec[2] unsignedIntValue]);
    NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:size * 0.86 weight:NSFontWeightMedium];
    cfg = [cfg configurationByApplyingConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[a, b]]];
    NSImage *glyph = [sym imageWithSymbolConfiguration:cfg];
    // a square canvas so every button has the same size, the glyph centred and scaled to fit
    return [NSImage imageWithSize:NSMakeSize(size, size) flipped:NO drawingHandler:^BOOL(NSRect r) {
        NSSize g = glyph.size;
        const CGFloat k = MIN(1.0, MIN(size / g.width, size / g.height));
        NSRect dst = NSMakeRect((size - g.width * k) / 2, (size - g.height * k) / 2, g.width * k, g.height * k);
        [glyph drawInRect:dst fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
        return YES;
    }];
}

// Standard bitmap name -> upstream Fluent icon base name (icons/<light|dark>/toolbar/<regular|filled>/<base>_off.ico)
static NSString *fluentName(NSString *std) {
    static NSDictionary *m;
    if (!m) m = @{@"newFile": @"new", @"openFile": @"open", @"saveFile": @"save", @"saveAll": @"saveall", @"closeFile": @"close",
                  @"closeAll": @"closeall", @"print": @"print", @"cut": @"cut", @"copy": @"copy", @"paste": @"paste", @"undo": @"undo",
                  @"redo": @"redo", @"find": @"find", @"findReplace": @"findrep", @"zoomIn": @"zoomIn", @"zoomOut": @"zoomOut",
                  @"syncV": @"syncV", @"syncH": @"syncH", @"wrap": @"wrap", @"allChars": @"allChars", @"indentGuide": @"indentGuide",
                  @"udl": @"udl", @"docMap": @"docMap", @"docList": @"docList", @"funcList": @"funcList", @"fileBrowser": @"fileBrowser",
                  @"monitoring": @"monitoring", @"startRecord": @"startrecord", @"stopRecord": @"stoprecord", @"playRecord": @"playrecord",
                  @"playRecord_m": @"playrecord_m", @"saveRecord": @"saverecord"};
    return m[std];
}

// Preferences > Toolbar > Colorization (upstream IconList::changeFluentIconColor): "Complete" paints every visible
// pixel, "Partial" only the accent-blue parts of the Fluent icon. Colours: upstream ImageListSet.cpp / NppConstants.h.
static NSImage *colorizeFluentIcon(NSImage *img) {
    const BOOL dark = [TPChrome dark];
    const uint32_t cMain = dark ? 0xDEDEDE : 0x212121, cSecondary = dark ? 0x4CC2FF : 0x0078D4;
    static const uint32_t kChoices[] = {0xE81123, 0x008B00, 0x0078D4, 0xB146C2, 0x00B7C3, 0x498205, 0xFFB900};
    const BOOL mono = [TPPrefs i:@"pref.toolbarColorMode"] == 0;
    const NSInteger choice = [TPPrefs i:@"pref.toolbarColor"];   // 0–6 colours, 7 Default, 8 System Accent, 9 Custom
    unsigned custom = 0;
    [[NSScanner scannerWithString:[TPPrefs s:@"pref.toolbarCustomColor"] ?: @"0"] scanHexInt:&custom];
    int nr, ng, nb;
    auto set = [&](uint32_t c) { nr = (c >> 16) & 0xFF; ng = (c >> 8) & 0xFF; nb = c & 0xFF; };
    if (choice >= 0 && choice <= 6) set(kChoices[choice]);
    else if (choice == 8) {
        NSColor *a = [NSColor.controlAccentColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        set((uint32_t(lround(a.redComponent * 255)) << 16) | (uint32_t(lround(a.greenComponent * 255)) << 8) | uint32_t(lround(a.blueComponent * 255)));
    } else if (choice == 9 && custom) set(custom);
    else if (mono) set(cMain);          // Default + Complete: the main icon colour everywhere
    else return img;                    // Default + Partial: the icon as drawn
    const int orr = (cSecondary >> 16) & 0xFF, og = (cSecondary >> 8) & 0xFF, ob = cSecondary & 0xFF;
    NSImage *out = [[NSImage alloc] initWithSize:img.size];
    for (NSImageRep *r in img.representations) {
        NSBitmapImageRep *src = [r isKindOfClass:NSBitmapImageRep.class] ? (NSBitmapImageRep *)r : nil;
        if (!src || src.bitsPerSample != 8 || src.isPlanar || src.samplesPerPixel < 3) continue;
        const NSInteger w = src.pixelsWide, h = src.pixelsHigh, spp = src.samplesPerPixel;
        const BOOL alphaFirst = (src.bitmapFormat & NSBitmapFormatAlphaFirst) != 0, hasAlpha = src.hasAlpha;
        const BOOL premul = hasAlpha && !(src.bitmapFormat & NSBitmapFormatAlphaNonpremultiplied);
        NSBitmapImageRep *dst = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:w pixelsHigh:h bitsPerSample:8
            samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
            bitmapFormat:NSBitmapFormatAlphaNonpremultiplied bytesPerRow:w * 4 bitsPerPixel:32];
        const unsigned char *in = src.bitmapData;
        unsigned char *o = dst.bitmapData;
        for (NSInteger y = 0; y < h; ++y) for (NSInteger x = 0; x < w; ++x) {
            const unsigned char *px = in + y * src.bytesPerRow + x * (src.bitsPerPixel / 8);
            int a = hasAlpha ? px[alphaFirst ? 0 : spp - 1] : 255;
            const unsigned char *rgb = px + (hasAlpha && alphaFirst ? 1 : 0);
            int cr = rgb[0], cg = rgb[1], cb = rgb[2];
            if (premul && a > 0 && a < 255) { cr = MIN(255, cr * 255 / a); cg = MIN(255, cg * 255 / a); cb = MIN(255, cb * 255 / a); }
            if (a != 0) {   // modify non-transparent pixels
                const int tol = a >= 255 ? 3 : 3 + 128 / a;   // upstream tolerance 3, widened for un-premultiplied edges
                if (mono || (abs(cr - orr) <= tol && abs(cg - og) <= tol && abs(cb - ob) <= tol)) { cr = nr; cg = ng; cb = nb; }
            }
            unsigned char *q = o + y * w * 4 + x * 4;
            q[0] = (unsigned char)cr; q[1] = (unsigned char)cg; q[2] = (unsigned char)cb; q[3] = (unsigned char)a;
        }
        NSBitmapImageRep *tagged = src.colorSpace ? [dst bitmapImageRepByRetaggingWithColorSpace:src.colorSpace] : dst;
        (tagged ?: dst).size = src.size;
        [out addRepresentation:tagged ?: dst];
    }
    return out.representations.count ? out : img;
}

static NSImage *loadFluentIcon(NSString *std, BOOL filled, CGFloat size, BOOL disabled) {
    NSString *dir = [NSString stringWithFormat:@"icons/fluent/%@/%@", [TPChrome dark] ? @"dark" : @"light", filled ? @"filled" : @"regular"];
    NSString *base = fluentName(std);
    if (!base) return nil;
    NSString *p = nil;
    if (disabled) p = [[NSBundle mainBundle] pathForResource:[base stringByAppendingString:@"_dis"] ofType:@"ico" inDirectory:dir];
    if (!p) p = [[NSBundle mainBundle] pathForResource:[base stringByAppendingString:@"_off"] ofType:@"ico" inDirectory:dir];
    NSImage *img = p ? [[NSImage alloc] initWithContentsOfFile:p] : nil;
    if (!img) return nil;
    if (!disabled) img = colorizeFluentIcon(img);
    img.size = NSMakeSize(size, size);
    if (disabled && ![p containsString:@"_dis"]) {
        NSImage *dim = [[NSImage alloc] initWithSize:img.size];
        [dim lockFocus];
        [img drawInRect:NSMakeRect(0, 0, size, size) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:0.35];
        [dim unlockFocus];
        return dim;
    }
    return img;
}

@interface TPToolButton : NSButton
@property (nonatomic) int command;
@property (nonatomic, strong) NSImage *normalImage;
@property (nonatomic, strong) NSImage *disabledImage;
@property (nonatomic, copy) NSString *iconName;
@end
@implementation TPToolButton {
    NSTrackingArea *_hoverArea;
    BOOL _hover;
}
// View > Modern Look: a soft rounded highlight under the pointer
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_hoverArea) [self removeTrackingArea:_hoverArea];
    _hoverArea = [[NSTrackingArea alloc] initWithRect:self.bounds options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_hoverArea];
}
- (void)setHover:(BOOL)h {
    _hover = h;
    const BOOL modern = [TPPrefs b:@"pref.modernLook"];
    self.layer.cornerRadius = modern ? 6 : 2;
    self.layer.backgroundColor = h && modern && self.enabled ? [[NSColor labelColor] colorWithAlphaComponent:[TPChrome dark] ? 0.16 : 0.09].CGColor : NSColor.clearColor.CGColor;
}
- (void)mouseEntered:(NSEvent *)e { [self setHover:YES]; }
- (void)mouseExited:(NSEvent *)e { [self setHover:NO]; }
- (void)mouseDown:(NSEvent *)e { [super mouseDown:e]; [self setHover:NO]; }
@end

@implementation TPToolbarView {
    NSMutableArray<TPToolButton *> *_buttons;
    NSMutableArray<NSDictionary *> *_pluginButtons;   // {cmd, button, light, dark, standard}
}

- (BOOL)isAccessibilityElement { return YES; }
- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityToolbarRole; }
- (NSString *)accessibilityLabel { return @"Toolbar"; }

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _buttons = [NSMutableArray array];
        CGFloat x = 4;
        TPCommandRegistry *reg = [TPCommandRegistry shared];
        for (const ToolButton &b : kButtons) {
            if (!b.icon) { x += 8; continue; }
            TPToolButton *btn = [[TPToolButton alloc] initWithFrame:NSMakeRect(x, 2, 23, 22)];
            btn.command = b.cmd;
            btn.bordered = NO;
            btn.buttonType = NSButtonTypeMomentaryChange;
            btn.imagePosition = NSImageOnly;
            btn.iconName = @(b.icon);
            NSString *tip = [reg labelForCommand:b.cmd];
            tip = [tip stringByReplacingOccurrencesOfString:@"..." withString:@""];
            TPKeyBinding *kb = [reg primaryBindingForCommand:b.cmd];
            btn.toolTip = kb ? [NSString stringWithFormat:@"%@ (%@)", tip, kb.macDescription] : tip;
            btn.accessibilityLabel = [reg labelForCommand:b.cmd];   // VoiceOver: image-only buttons need a label
            btn.target = self;
            btn.action = @selector(clicked:);
            btn.wantsLayer = YES;
            btn.layer.cornerRadius = 2;
            [self addSubview:btn];
            [_buttons addObject:btn];
            x += 24;
        }
        [self reloadIcons];
    }
    return self;
}

- (NSArray<NSNumber *> *)pluginButtonCommands { return [_pluginButtons valueForKey:@"cmd"] ?: @[]; }

- (void)addPluginButton:(int)cmd image:(NSImage *)light darkImage:(NSImage *)dark standardImage:(NSImage *)standard tooltip:(NSString *)tip {
    if (!_pluginButtons) _pluginButtons = [NSMutableArray array];
    [self removePluginButton:cmd];
    TPToolButton *btn = [[TPToolButton alloc] initWithFrame:NSMakeRect(0, 2, 23, 22)];
    btn.command = cmd;
    btn.bordered = NO;
    btn.buttonType = NSButtonTypeMomentaryChange;
    btn.imagePosition = NSImageOnly;
    btn.imageScaling = NSImageScaleProportionallyUpOrDown;
    btn.toolTip = tip;
    btn.accessibilityLabel = tip;
    btn.target = self;
    btn.action = @selector(clicked:);
    btn.wantsLayer = YES;
    btn.layer.cornerRadius = 2;
    [self addSubview:btn];
    NSMutableDictionary *d = [@{@"cmd": @(cmd), @"button": btn} mutableCopy];
    if (light) d[@"light"] = light;
    if (dark) d[@"dark"] = dark;
    if (standard) d[@"standard"] = standard;
    [_pluginButtons addObject:d];
    [self reloadIcons];
}

- (void)removePluginButton:(int)cmd {
    for (NSDictionary *d in [_pluginButtons copy])
        if ([d[@"cmd"] intValue] == cmd) { [d[@"button"] removeFromSuperview]; [_pluginButtons removeObject:d]; }
}

- (nullable NSImage *)imageForCommand:(int)cmd {
    for (TPToolButton *b in _buttons) if (b.command == cmd) return b.normalImage;
    return nil;
}

- (CGFloat)iconSize {
    NSInteger set = [TPPrefs i:@"pref.toolbarIconSet"];
    return (set == 1 || set == 3 || set == 6) ? 24 : 16;
}

- (CGFloat)preferredHeight { return self.iconSize > 16 ? 36 : 28; }

- (void)reloadIcons {
    NSInteger set = [TPPrefs i:@"pref.toolbarIconSet"];   // 0 Fluent small, 1 Fluent large, 2 Filled small, 3 Filled large, 4 Standard, 5/6 Colourful
    CGFloat size = self.iconSize, pitch = size + 8, x = 4;
    NSUInteger bi = 0;
    for (const ToolButton &b : kButtons) {
        if (!b.icon) { x += 8; continue; }
        TPToolButton *btn = _buttons[bi++];
        if (set == 5 || set == 6) {
            btn.normalImage = loadColourfulIcon(btn.iconName, size, NO) ?: loadFluentIcon(btn.iconName, NO, size, NO);
            btn.disabledImage = loadColourfulIcon(btn.iconName, size, YES) ?: loadFluentIcon(btn.iconName, NO, size, YES);
        } else if (set == 4) {
            btn.normalImage = loadToolbarBitmap(btn.iconName, NO);
            btn.disabledImage = loadToolbarBitmap(btn.iconName, YES);
        } else {
            btn.normalImage = loadFluentIcon(btn.iconName, set >= 2, size, NO) ?: loadToolbarBitmap(btn.iconName, NO);
            btn.disabledImage = loadFluentIcon(btn.iconName, set >= 2, size, YES) ?: loadToolbarBitmap(btn.iconName, YES);
        }
        btn.frame = NSMakeRect(x, 2, pitch - 1, size + 6);
        x += pitch;
    }
    if (_pluginButtons.count) x += 8;   // a separator before the plugin buttons
    for (NSDictionary *d in _pluginButtons) {
        TPToolButton *btn = d[@"button"];
        NSImage *img = set == 4 ? (d[@"standard"] ?: d[@"light"]) : (([TPChrome dark] && d[@"dark"]) ? d[@"dark"] : (d[@"light"] ?: d[@"standard"]));
        NSImage *sized = [img copy];
        sized.size = NSMakeSize(size, size);
        btn.normalImage = sized;
        btn.disabledImage = sized;
        btn.frame = NSMakeRect(x, 2, pitch - 1, size + 6);
        x += pitch;
    }
    [self refreshTooltips];
    [self refreshStates];
    self.needsDisplay = YES;
}

// "Name (shortcut)" and what the button does; again after a change of shortcuts or interface language
- (void)refreshTooltips {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    for (TPToolButton *btn in _buttons) {
        NSString *name = [[reg labelForCommand:btn.command] stringByReplacingOccurrencesOfString:@"..." withString:@""];
        TPKeyBinding *kb = [reg primaryBindingForCommand:btn.command];
        NSString *head = kb && !kb.isEmpty ? [NSString stringWithFormat:@"%@ (%@)", name, kb.macDescription] : name;
        NSString *what = buttonDescription(btn.iconName);
        btn.toolTip = what ? [NSString stringWithFormat:@"%@\n%@", head, what] : head;
        btn.accessibilityHelp = what;
    }
}

- (nullable NSString *)tooltipForCommand:(int)cmd {
    for (TPToolButton *b in _buttons) if (b.command == cmd) return b.toolTip;
    for (NSDictionary *d in _pluginButtons) if ([d[@"cmd"] intValue] == cmd) return [d[@"button"] toolTip];
    return nil;
}

- (BOOL)isFlipped { return YES; }

- (void)clicked:(TPToolButton *)sender {
    [[TPCommandRegistry shared] execute:sender.command];
    [self refreshStates];
}

- (void)refreshStates {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    NSMutableArray *all = [_buttons mutableCopy];
    for (NSDictionary *d in _pluginButtons) [all addObject:d[@"button"]];
    for (TPToolButton *b in all) {
        BOOL en = [reg isEnabled:b.command];
        BOOL checked = [reg isChecked:b.command];
        b.enabled = en;
        b.image = en ? b.normalImage : b.disabledImage;
        // checked: light blue in light mode; a dark blue in dark mode so the light Fluent icons stay visible
        NSColor *on = [TPChrome dark] ? [NSColor colorWithSRGBRed:0.20 green:0.30 blue:0.44 alpha:1] : [NSColor colorWithSRGBRed:0.80 green:0.89 blue:0.98 alpha:1];
        b.layer.backgroundColor = checked ? on.CGColor : NSColor.clearColor.CGColor;
        b.layer.borderWidth = checked ? 1 : 0;
        b.layer.borderColor = [NSColor colorWithSRGBRed:0.36 green:0.60 blue:0.87 alpha:1].CGColor;
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [[TPChrome barBackground] setFill];
    NSRectFill(self.bounds);
    [[TPChrome border] setFill];
    NSRectFill(NSMakeRect(0, NSMaxY(self.bounds) - 1, NSWidth(self.bounds), 1));
    CGFloat size = self.iconSize, pitch = size + 8, x = 4;
    [[TPChrome separator] setFill];
    for (const ToolButton &b : kButtons) {
        if (!b.icon) { NSRectFill(NSMakeRect(x + 3, 5, 1, size)); x += 8; continue; }
        x += pitch;
    }
    if (_pluginButtons.count) NSRectFill(NSMakeRect(x + 3, 5, 1, size));
}

@end

// ---------------------------------------------------------------- status bar
@implementation TPStatusBarView {
    NSMutableArray<NSString *> *_texts;
}

static const CGFloat kWidths[] = {220, 260, 110, 120, 45};   // parts 1..5; part 0 takes the rest

- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _texts = [NSMutableArray arrayWithArray:@[@"", @"", @"", @"", @"", @""]];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)setText:(NSString *)text forPart:(NSInteger)part {
    if (part < 0 || part > 5) return;
    if ([_texts[part] isEqualToString:text ?: @""]) return;
    _texts[part] = text ?: @"";
    self.needsDisplay = YES;
}

- (NSString *)textForPart:(NSInteger)part { return (part >= 0 && part <= 5) ? _texts[part] : @""; }

// accessibility: the six parts as static texts (they are drawn, not views)
- (BOOL)isAccessibilityElement { return YES; }
- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityGroupRole; }
- (NSString *)accessibilityLabel { return @"Status bar"; }
- (NSArray *)accessibilityChildren {
    static NSArray *names = @[@"Document type", @"Length and lines", @"Position", @"Line ending", @"Encoding", @"Typing mode"];
    CGFloat total = 0;
    for (CGFloat w : kWidths) total += w;
    CGFloat x = 0, w0 = MAX(120, NSWidth(self.bounds) - total);
    NSMutableArray *a = [NSMutableArray array];
    for (NSInteger i = 0; i < 6; ++i) {
        CGFloat w = i == 0 ? w0 : kWidths[i - 1];
        NSRect r = NSMakeRect(x, 0, w, NSHeight(self.bounds));
        // parent space is not flipped for accessibility frames
        NSAccessibilityElement *e = [NSAccessibilityElement accessibilityElementWithRole:NSAccessibilityStaticTextRole frame:NSZeroRect label:names[(NSUInteger)i] parent:self];
        e.accessibilityFrameInParentSpace = NSMakeRect(r.origin.x, 0, r.size.width, NSHeight(self.bounds));
        e.accessibilityValue = _texts[(NSUInteger)i];
        [a addObject:e];
        x += w;
    }
    return a;
}

- (void)drawRect:(NSRect)dirtyRect {
    [[TPChrome barBackground] setFill];
    NSRectFill(self.bounds);
    [[TPChrome border] setFill];
    NSRectFill(NSMakeRect(0, 0, NSWidth(self.bounds), 1));
    CGFloat total = 0;
    for (CGFloat w : kWidths) total += w;
    CGFloat w0 = MAX(120, NSWidth(self.bounds) - total);
    CGFloat x = 0;
    NSDictionary *attrs = @{NSFontAttributeName: [NSFont systemFontOfSize:11.5], NSForegroundColorAttributeName: [TPChrome statusText]};
    for (NSInteger i = 0; i < 6; ++i) {
        CGFloat w = i == 0 ? w0 : kWidths[i - 1];
        NSRect r = NSMakeRect(x + 6, 4, w - 10, NSHeight(self.bounds) - 6);
        NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
        ps.lineBreakMode = NSLineBreakByTruncatingTail;
        NSMutableDictionary *a = [attrs mutableCopy];
        a[NSParagraphStyleAttributeName] = ps;
        [_texts[i] drawInRect:r withAttributes:a];
        x += w;
        if (i < 5) {
            [[TPChrome separator] setFill];
            NSRectFill(NSMakeRect(x - 1, 3, 1, NSHeight(self.bounds) - 6));
        }
    }
}

@end
