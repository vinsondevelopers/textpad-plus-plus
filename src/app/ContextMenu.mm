// Textpad++ — the editor's context menu from contextMenu.xml (upstream NppParameters::getContextMenuFromXmlTree)
// and Settings > Edit Popup ContextMenu. GPL-3.0-or-later.
#import "app/MainWindowController.h"
#import "app/Session.h"
#import "commands/CommandRegistry.h"
#import <objc/runtime.h>

using namespace npp;

int (^TPContextMenuPluginResolver)(NSString *pluginName, NSString *commandName) = nil;   // set by the plugin host

static NSString *cleanLabel(NSString *s) {
    s = [s stringByReplacingOccurrencesOfString:@"&" withString:@""];
    NSRange tab = [s rangeOfString:@"\t"];
    if (tab.location != NSNotFound) s = [s substringToIndex:tab.location];
    s = [s stringByReplacingOccurrencesOfString:@"…" withString:@"..."];
    return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].lowercaseString;
}

// upstream: MenuEntryName = top-level menu, MenuItemName = an item anywhere inside it (English names)
static int commandForMenuItem(NSString *entry, NSString *item) {
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    NSString *want = cleanLabel(item);
    for (NSNumber *n in reg.allMenuCommands) {
        NSArray *path = [reg menuPathForCommand:n.intValue];
        if (!path.count || [cleanLabel(path.firstObject) caseInsensitiveCompare:cleanLabel(entry)] != NSOrderedSame) continue;
        if ([cleanLabel([reg labelForCommand:n.intValue]) isEqualToString:want] || [cleanLabel(path.lastObject) isEqualToString:want]) return n.intValue;
    }
    return 0;
}

// fills each menu just before it opens, again whenever contextMenu.xml changes (state kept per menu: the menu is
// first asked for while the window is built, before the main menu that MenuEntryName / MenuItemName resolve against)
@interface TPContextMenuSource : NSObject <NSMenuDelegate>
@end
@implementation TPContextMenuSource
- (void)menuNeedsUpdate:(NSMenu *)menu {
    static char kStamp;
    NSString *path = [TPMainWindowController contextMenuFilePath];
    NSDate *mtime = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil].fileModificationDate ?: [NSDate distantPast];
    BOOL menusBuilt = [TPCommandRegistry shared].hasBuiltMainMenu;
    NSString *stamp = [NSString stringWithFormat:@"%@|%f|%d", path, mtime.timeIntervalSinceReferenceDate, menusBuilt];
    if ([objc_getAssociatedObject(menu, &kStamp) isEqualToString:stamp]) return;
    [TPMainWindowController fillContextMenu:menu fromFile:path];
    objc_setAssociatedObject(menu, &kStamp, stamp, OBJC_ASSOCIATION_COPY_NONATOMIC);
}
@end

@implementation TPMainWindowController (ContextMenuConfig)

// the user's contextMenu.xml (settings folder), else the bundled upstream default
+ (NSString *)contextMenuFilePath {
    NSString *user = [[TPSession shared].settingsDirectory stringByAppendingPathComponent:@"contextMenu.xml"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:user]) return user;
    return [[NSBundle mainBundle] pathForResource:@"contextMenu" ofType:@"xml" inDirectory:@"data"];
}

+ (void)fillContextMenu:(NSMenu *)menu fromFile:(NSString *)path {
    [menu removeAllItems];
    TPCommandRegistry *reg = [TPCommandRegistry shared];
    NSData *d = path ? [NSData dataWithContentsOfFile:path] : nil;
    NSXMLDocument *doc = d ? [[NSXMLDocument alloc] initWithData:d options:0 error:nil] : nil;
    NSMutableDictionary<NSString *, NSMenu *> *folders = [NSMutableDictionary dictionary];
    for (NSXMLElement *e in [doc nodesForXPath:@"//ScintillaContextMenu/Item" error:nil]) {
        NSString *(^attr)(NSString *) = ^NSString *(NSString *n) { return [e attributeForName:n].stringValue; };
        NSString *folder = attr(@"FolderName");
        NSMenu *target = menu;
        if (folder.length) {
            target = folders[folder];
            if (!target) {
                target = [[NSMenu alloc] initWithTitle:folder];
                NSMenuItem *holder = [[NSMenuItem alloc] initWithTitle:folder action:nil keyEquivalent:@""];
                holder.submenu = target;
                [menu addItem:holder];
                folders[folder] = target;
            }
        }
        int cmd = 0;
        if (attr(@"id")) {
            cmd = attr(@"id").intValue;
            if (cmd == 0) { [target addItem:[NSMenuItem separatorItem]]; continue; }
        } else if (attr(@"MenuEntryName") && attr(@"MenuItemName")) {
            cmd = commandForMenuItem(attr(@"MenuEntryName"), attr(@"MenuItemName"));
        } else if (attr(@"PluginEntryName") && attr(@"PluginCommandItemName") && TPContextMenuPluginResolver) {
            cmd = TPContextMenuPluginResolver(attr(@"PluginEntryName"), attr(@"PluginCommandItemName"));
        }
        if (!cmd) continue;   // unknown item (e.g. a plugin that is not installed): skipped, as upstream
        NSMenuItem *mi = [reg makeItemForCommand:cmd];
        if (attr(@"ItemNameAs").length) mi.title = attr(@"ItemNameAs");
        else if (!mi.title.length) continue;
        [target addItem:mi];
    }
    // drop empty sub-menus and doubled / leading / trailing separators
    for (NSMenuItem *mi in [menu.itemArray copy]) if (mi.submenu && mi.submenu.numberOfItems == 0) [menu removeItem:mi];
    for (NSInteger i = menu.numberOfItems - 1; i >= 0; --i) {
        NSMenuItem *mi = [menu itemAtIndex:i];
        if (!mi.isSeparatorItem) continue;
        BOOL edge = i == 0 || i == menu.numberOfItems - 1 || [menu itemAtIndex:i - 1].isSeparatorItem;
        if (edge) [menu removeItemAtIndex:i];
    }
}

- (NSMenu *)editorContextMenu {
    static char kSource;
    TPContextMenuSource *src = objc_getAssociatedObject(self, &kSource);
    if (!src) { src = [TPContextMenuSource new]; objc_setAssociatedObject(self, &kSource, src, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    NSMenu *m = [[NSMenu alloc] initWithTitle:@"Editor"];
    m.delegate = src;   // filled in menuNeedsUpdate: when it opens
    return m;
}

// Settings > Edit Popup ContextMenu: copy the default to the settings folder if needed and open it here
- (void)editContextMenuFile {
    NSString *user = [[TPSession shared].settingsDirectory stringByAppendingPathComponent:@"contextMenu.xml"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:user]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:user.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        [[NSFileManager defaultManager] copyItemAtPath:[[NSBundle mainBundle] pathForResource:@"contextMenu" ofType:@"xml" inDirectory:@"data"] toPath:user error:nil];
    }
    if (!self.selfTestMode)
        [self showMessage:@"Editing contextMenu.xml"
              informative:@"Editing contextMenu.xml allows you to modify the context menu of the editing area. Your changes apply the next time the menu opens after you save the file."];
    [self openFile:user];
}

@end
