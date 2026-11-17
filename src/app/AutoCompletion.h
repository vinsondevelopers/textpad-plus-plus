// Textpad++ — auto-completion from upstream API files (autoCompletion/<language>.xml), word completion,
// path completion and function parameter hints (call tips).
// Port of Notepad++ v8.9.9.1 AutoCompletion.cpp / FunctionCallTip.cpp. GPL-3.0-or-later.
#pragma once
#import <Cocoa/Cocoa.h>
#import "ScintillaView.h"

NS_ASSUME_NONNULL_BEGIN

// One view's completion state (upstream keeps one AutoCompletion per edit view, too).
@interface TPAutoCompletion : NSObject
+ (instancetype)forView:(ScintillaView *)view;
// Language of the document shown in the view: a langs.model.xml name ("cpp", "javascript.js", ...) or "udl:<name>".
- (void)setLanguageId:(NSString *)languageId;
@property (nonatomic, readonly) BOOL funcCompletionActive;     // an API file was loaded for the language
@property (nonatomic, readonly, nullable) NSString *apiFilePath;

- (BOOL)showApiComplete;                     // Edit > Auto-Completion > Function Completion
- (BOOL)showWordComplete:(BOOL)autoInsert;   // Word Completion (auto-inserts a single match)
- (BOOL)showApiAndWordComplete;
- (BOOL)showFunctionComplete;                // Function Parameters Hint
- (void)showPathCompletion;                  // Path Completion (absolute or ~ paths)
- (void)showPreviousOverload;                // Function Parameters Previous / Next Hint
- (void)showNextOverload;
- (void)callTipClick:(NSInteger)direction;   // SCN_CALLTIPCLICK: 1 = up arrow, 2 = down arrow
- (void)update:(int)character;               // SCN_CHARADDED (Preferences > Auto-Completion)
@property (nonatomic, readonly) BOOL callTipVisible;
@property (nonatomic, readonly, copy) NSString *lastCallTipText;   // text of the call tip last shown (tests)
@end

NS_ASSUME_NONNULL_END
