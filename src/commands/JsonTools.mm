// Textpad++ — Plugins > JSON Tools: Format JSON, Compress JSON, Validate JSON, on the selection or the whole
// document, as one undo step; an error moves the caret to the problem. GPL-3.0-or-later.
#import "app/MainWindowController.h"
#import "app/Document.h"
#import "app/Sci.h"
#import "app/Preferences.h"
#include "core/Json.h"

@implementation TPMainWindowController (JsonTools)

- (void)runJsonTool:(int)op {
    ScintillaView *v = self.editor;
    TPDocument *d = self.currentDocument;
    if (!d) return;
    sptr_t a = SCI(v, SCI_GETSELECTIONSTART), b = SCI(v, SCI_GETSELECTIONEND);
    const BOOL whole = a == b;
    if (whole) { a = 0; b = SCI(v, SCI_GETLENGTH); }
    const std::string text = sciGetRange(v, a, b);
    std::string indent = SCI(v, SCI_GETUSETABS) ? "\t" : std::string(static_cast<size_t>(MAX((sptr_t)1, SCI(v, SCI_GETINDENT) ?: SCI(v, SCI_GETTABWIDTH))), ' ');
    const sptr_t eolMode = SCI(v, SCI_GETEOLMODE);
    const std::string eol = eolMode == SC_EOL_CRLF ? "\r\n" : eolMode == SC_EOL_CR ? "\r" : "\n";
    tpp::json::Result r = op == 0 ? tpp::json::format(text, indent, eol) : op == 1 ? tpp::json::compress(text) : tpp::json::validate(text);
    if (!r.ok) {
        const sptr_t at = a + static_cast<sptr_t>(r.errorOffset);
        SCI(v, SCI_GOTOPOS, at);
        const sptr_t line = SCI(v, SCI_LINEFROMPOSITION, at), col = SCI(v, SCI_GETCOLUMN, at);
        [self showMessage:@"Invalid JSON" informative:[NSString stringWithFormat:@"%s at line %ld, column %ld.", r.error.c_str(), (long)line + 1, (long)col + 1]];
        return;
    }
    if (op == 2) { [self showMessage:@"The JSON is valid." informative:nil]; return; }
    if (SCI(v, SCI_GETREADONLY)) { TPBeep(); return; }
    SCI(v, SCI_BEGINUNDOACTION);
    SCI(v, SCI_SETTARGETRANGE, a, b);
    SCI(v, SCI_REPLACETARGET, r.text.size(), reinterpret_cast<sptr_t>(r.text.data()));
    SCI(v, SCI_ENDUNDOACTION);
    if (whole) SCI(v, SCI_GOTOPOS, 0);
    else SCI(v, SCI_SETSEL, a, a + static_cast<sptr_t>(r.text.size()));
    if (whole && [d.languageId isEqualToString:@"normal"]) [self setDocumentLanguage:d languageId:@"json"];   // highlight it as JSON
}

@end
