// Textpad++ — snippets: type a trigger (e.g. "for", "def", "html5") and press Tab to insert a template; Tab and ⇧Tab
// move between its fields ${1:name}, ${2}, … and $0 ends. Built-in snippets for common languages, plus your own in
// snippets.json (Settings > Edit Snippets...). GPL-3.0-or-later.
#pragma once
#import "app/MainWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@interface TPSnippetExpansion : NSObject
@property (nonatomic, copy) NSString *text;                         // placeholders replaced by their defaults
@property (nonatomic, copy) NSArray<NSValue *> *stops;              // character ranges in `text`, in Tab order ($0 last)
@end

// `body` with ${n:default} / ${n} / $n / $0 fields; every line after the first gets `indent`, a tab in the body becomes `indentUnit`
TPSnippetExpansion *TPExpandSnippet(NSString *body, NSString *indent, NSString *indentUnit);
// the snippets for a language id ("python", "javascript.js", ...): trigger -> body; the "*" ones apply everywhere
NSDictionary<NSString *, NSString *> *TPSnippetsForLanguage(NSString *languageId);
NSString *TPSnippetsFilePath(void);

@interface TPMainWindowController (Snippets)
- (BOOL)handleSnippetKey:(NSEvent *)event inEditor:(ScintillaView *)editor;   // Tab / ⇧Tab; YES when used
- (BOOL)expandSnippetInEditor:(ScintillaView *)editor;                        // the trigger before the caret
- (BOOL)snippetNextField:(BOOL)forward inEditor:(ScintillaView *)editor;
@property (nonatomic, readonly) BOOL snippetActive;
- (void)editSnippetsFile;
@end

NS_ASSUME_NONNULL_END
