// Textpad++ — very large files (server logs of several GB): the file is memory-mapped and streamed into a
// Scintilla document on a background thread through Scintilla's ILoader (as upstream does for big files), with a
// progress window and Cancel; saving and backups write the document in chunks straight from Scintilla's buffer;
// a growing log that is monitored only gets the new bytes appended. GPL-3.0-or-later.
#import "app/LargeFiles.h"
#import "app/EditorPane.h"
#import "app/Document.h"
#import "app/Preferences.h"
#import "app/LanguageService.h"
#import "app/Sci.h"
#include "core/Encoding.h"
#include "ILoader.h"
#include <atomic>
#import <objc/runtime.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>

const unsigned long long TPStreamedFileBytes = 32ull << 20;      // files from 32 MB load in the background
static const size_t kChunk = 16u << 20;                          // 16 MB per loader / writer step

// the encoding from the start of the file: BOM, else (with autodetection) uchardet, else UTF-8 / ANSI —
// upstream decides from its first read block as well
static tpp::TextEncoding encodingForSample(const unsigned char *bytes, size_t n, bool whole) {
    size_t len = n;
    if (!whole) {   // do not cut a character in two: stop after the last line end of the sample
        const void *nl = nullptr;
        for (size_t i = len; i > 0 && !nl; --i) if (bytes[i - 1] == '\n') nl = bytes + i;
        if (nl) len = static_cast<const unsigned char *>(nl) - bytes;
    }
    std::string sample(reinterpret_cast<const char *>(bytes), len);
    tpp::DecodeResult dr = tpp::detectAndDecode(sample, [TPPrefs b:@"pref.openAnsiAsUtf8"], [TPPrefs b:@"pref.detectEncoding"]);
    return dr.encoding;
}

static bool passthrough(const tpp::TextEncoding &e) {
    return !e.isCodepage() && (e.mode == tpp::UniMode::Utf8 || e.mode == tpp::UniMode::Utf8Bom);
}

@implementation TPMainWindowController (LargeFiles)

- (TPDocument *)loadLargeFile:(NSString *)path error:(NSString **)error {
    NSError *e = nil;
    NSData *map = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedAlways error:&e];
    if (!map) { if (error) *error = e.localizedDescription ?: @"Cannot read the file"; return nil; }
    const unsigned char *bytes = static_cast<const unsigned char *>(map.bytes);
    const size_t n = map.length;
    const tpp::TextEncoding enc = encodingForSample(bytes, MIN(n, (size_t)1 << 20), n <= ((size_t)1 << 20));
    size_t start = 0;
    if (enc.mode == tpp::UniMode::Utf8Bom && n >= 3 && bytes[0] == 0xEF) start = 3;
    if ((enc.mode == tpp::UniMode::Utf16LE || enc.mode == tpp::UniMode::Utf16BE) && n >= 2) start = 2;
    const bool raw = passthrough(enc);
    const bool utf16 = !enc.isCodepage() && (enc.mode == tpp::UniMode::Utf16LE || enc.mode == tpp::UniMode::Utf16BE);
    const unsigned long long estimate = utf16 ? n * 3 / 2 : (raw ? n : n * 2);
    const BOOL restricted = [TPPrefs b:@"pref.largeFileEnabled"] && n > (unsigned long long)MAX(1, [TPPrefs i:@"pref.largeFileMB"]) * 1024ull * 1024ull;
    int options = SC_DOCUMENTOPTION_DEFAULT;
    if (estimate > 0x70000000ull) options |= SC_DOCUMENTOPTION_TEXT_LARGE;   // positions past 2 GB
    if (restricted) options |= SC_DOCUMENTOPTION_STYLES_NONE;                 // no lexing: half the memory
    Scintilla::ILoader *loader = reinterpret_cast<Scintilla::ILoader *>(SCI(self.workerView, SCI_CREATELOADER, static_cast<uptr_t>(estimate + 4096), options));
    if (!loader) { if (error) *error = @"Not enough memory to open this file."; return nil; }

    // the loading thread
    auto progress = std::make_shared<std::atomic<size_t>>(0);
    auto cancel = std::make_shared<std::atomic<bool>>(false);
    auto finished = std::make_shared<std::atomic<bool>>(false);
    __block int status = SC_STATUS_OK;
    __block bool lossy = false, nul = false;
    __block std::string head;   // the first decoded bytes, for the line-end style
    const tpp::TextEncoding chunkEnc = enc.mode == tpp::UniMode::Utf8Bom ? tpp::TextEncoding{tpp::UniMode::Utf8, enc.codepage} : enc;
    const bool multibyteCp = enc.isCodepage() && (enc.codepage == 932 || enc.codepage == 936 || enc.codepage == 949 || enc.codepage == 950 || enc.codepage == 51949);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        size_t pos = start;
        while (pos < n && !cancel->load()) {
            size_t len = MIN(kChunk, n - pos);
            if (pos + len < n) {
                if (utf16) {
                    len &= ~(size_t)1;
                    const unsigned char *u = bytes + pos + len - 2;
                    const unsigned unit = enc.mode == tpp::UniMode::Utf16LE ? (u[0] | (u[1] << 8)) : ((u[0] << 8) | u[1]);
                    if (unit >= 0xD800 && unit <= 0xDBFF) len -= 2;   // keep a surrogate pair together
                } else if (multibyteCp || (!raw && !utf16)) {
                    for (size_t k = len; k > 0; --k) if (bytes[pos + k - 1] == '\n') { len = k; break; }   // '\n' is never a trail byte
                }
            }
            if (!nul && memchr(bytes + pos, 0, len)) nul = true;
            if (raw) {
                status = loader->AddData(reinterpret_cast<const char *>(bytes + pos), static_cast<Sci_Position>(len));
                if (head.empty()) head.assign(reinterpret_cast<const char *>(bytes + pos), MIN(len, (size_t)65536));
            } else {
                tpp::DecodeResult r = tpp::decodeAs(std::string(reinterpret_cast<const char *>(bytes + pos), len), chunkEnc);
                lossy = lossy || r.lossy;
                status = loader->AddData(r.utf8.data(), static_cast<Sci_Position>(r.utf8.size()));
                if (head.empty()) head = r.utf8.substr(0, 65536);
            }
            if (status != SC_STATUS_OK) break;
            pos += len;
            progress->store(pos);
        }
        finished->store(true);
    });

    // the main thread stays responsive: a progress window with Cancel (none in the self-test)
    NSPanel *panel = nil;
    NSProgressIndicator *bar = nil;
    NSModalSession session = nullptr;
    NSDate *showAfter = [NSDate dateWithTimeIntervalSinceNow:0.25];
    while (!finished->load()) {
        if (self.selfTestMode) { usleep(2000); continue; }
        if (!panel && [showAfter timeIntervalSinceNow] < 0) {
            panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 420, 110) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
            panel.title = @"Opening a large file";
            NSTextField *label = [NSTextField labelWithString:[NSString stringWithFormat:@"%@ (%@)", path.lastPathComponent,
                                  [NSByteCountFormatter stringFromByteCount:(long long)n countStyle:NSByteCountFormatterCountStyleFile]]];
            label.frame = NSMakeRect(20, 74, 380, 18);
            label.lineBreakMode = NSLineBreakByTruncatingMiddle;
            bar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 48, 380, 20)];
            bar.indeterminate = NO; bar.minValue = 0; bar.maxValue = (double)n;
            NSButton *stop = [NSButton buttonWithTitle:@"Cancel" target:nil action:nil];
            stop.frame = NSMakeRect(310, 10, 90, 28);
            __block std::shared_ptr<std::atomic<bool>> cancelRef = cancel;
            stop.target = [NSBlockOperation blockOperationWithBlock:^{ cancelRef->store(true); }];
            stop.action = @selector(main);
            objc_setAssociatedObject(stop, "op", stop.target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            for (NSView *v in @[label, bar, stop]) [panel.contentView addSubview:v];
            [panel center];
            session = [NSApp beginModalSessionForWindow:panel];
        }
        if (session) { bar.doubleValue = (double)progress->load(); [NSApp runModalSession:session]; }
        usleep(10000);
    }
    if (session) [NSApp endModalSession:session];
    [panel orderOut:nil];
    if (cancel->load() || status != SC_STATUS_OK) {
        loader->Release();
        if (error) *error = cancel->load() ? @"Opening was cancelled." : @"Not enough memory to open this file.";
        return nil;
    }
    const sptr_t sciDoc = reinterpret_cast<sptr_t>(loader->ConvertToDocument());
    TPDocument *doc = [[TPDocument alloc] initWithPath:path];
    doc.encoding = enc;
    doc.lossyDecode = lossy;
    doc.containsNul = nul;
    doc.eolMode = static_cast<int>(tpp::detectEol(head, static_cast<tpp::Eol>([self defaultEol])));
    doc.languageId = restricted ? @"normal" : [[TPLanguageService shared] languageForFileName:path.lastPathComponent].langId;
    doc.sciDoc = [self adoptLoadedDocument:sciDoc eol:doc.eolMode];
    return doc;
}

// the same set-up createSciDocumentWithText: gives a new document
- (sptr_t)adoptLoadedDocument:(sptr_t)doc eol:(int)eol {
    ScintillaView *w = self.workerView;
    const sptr_t scratch = SCI(w, SCI_GETDOCPOINTER);
    SCI(w, SCI_ADDREFDOCUMENT, 0, scratch);
    SCI(w, SCI_SETDOCPOINTER, 0, doc);
    SCI(w, SCI_SETCODEPAGE, SC_CP_UTF8);
    SCI(w, SCI_EMPTYUNDOBUFFER);
    SCI(w, SCI_SETSAVEPOINT);
    SCI(w, SCI_SETEOLMODE, eol);
    SCI(w, SCI_SETCHANGEHISTORY, SC_CHANGE_HISTORY_ENABLED | SC_CHANGE_HISTORY_MARKERS);
    SCI(w, SCI_SETDOCPOINTER, 0, scratch);
    SCI(w, SCI_RELEASEDOCUMENT, 0, scratch);
    return doc;   // the loader's reference (count 1) stays with the TPDocument, as for SCI_CREATEDOCUMENT
}

// the document's text in pieces, without copying it (SCI_GETRANGEPOINTER)
- (BOOL)forEachChunkOfDocument:(TPDocument *)doc perform:(BOOL (^)(const char *data, size_t len))block {
    __block BOOL ok = YES;
    [self withDocument:doc perform:^(ScintillaView *v) {
        const sptr_t total = SCI(v, SCI_GETLENGTH);
        for (sptr_t pos = 0; pos < total && ok; ) {
            sptr_t len = MIN((sptr_t)kChunk, total - pos);
            if (pos + len < total) {   // end on a character boundary
                while (len > 1 && (static_cast<unsigned char>(SCI(v, SCI_GETCHARAT, pos + len)) & 0xC0) == 0x80) --len;
            }
            const char *p = reinterpret_cast<const char *>(SCI(v, SCI_GETRANGEPOINTER, pos, len));
            ok = p && block(p, static_cast<size_t>(len));
            pos += len;
        }
    }];
    return ok;
}

// saving a large document: encode and write chunk by chunk; NO with *lossy set when characters would be lost
- (BOOL)streamDocument:(TPDocument *)doc toPath:(NSString *)path allowLoss:(BOOL)allowLoss lossy:(BOOL *)lossyOut error:(NSString **)error {
    const tpp::TextEncoding enc = doc.encoding;
    if (!passthrough(enc) && !allowLoss) {   // a dry run first: never write half a file and then ask
        __block BOOL lossy = NO;
        __block BOOL first = YES;
        [self forEachChunkOfDocument:doc perform:^BOOL(const char *p, size_t len) {
            tpp::EncodeResult er = tpp::encode(std::string(p, len), first ? enc : enc);
            first = NO;
            if (er.lossy || !er.ok) lossy = YES;
            return !lossy;
        }];
        if (lossy) { if (lossyOut) *lossyOut = YES; return NO; }
    }
    __block BOOL first = YES;
    return TPSafeWriteFileProducer(path, ^BOOL(TPByteSink sink) {
        return [self forEachChunkOfDocument:doc perform:^BOOL(const char *p, size_t len) {
            if (passthrough(enc)) {
                if (first && enc.mode == tpp::UniMode::Utf8Bom && !sink("\xEF\xBB\xBF", 3)) return NO;
                first = NO;
                return sink(p, len);
            }
            tpp::EncodeResult er = tpp::encode(std::string(p, len), enc);
            if (!er.ok) return NO;
            size_t skip = 0;   // the UTF-16 BOM only once
            if (!first && !enc.isCodepage() && (enc.mode == tpp::UniMode::Utf16LE || enc.mode == tpp::UniMode::Utf16BE)) skip = 2;
            first = NO;
            return sink(er.bytes.data() + skip, er.bytes.size() - skip);
        }];
    }, error);
}

// File Status Auto-Detection / Monitoring (tail -f) of a growing file: append only what was added, when the
// document is unmodified and the old end of the file is unchanged
- (BOOL)appendGrowthOfDocument:(TPDocument *)doc {
    if (!doc.path || doc.dirty || !passthrough(doc.encoding)) return NO;
    NSDictionary *a = [[NSFileManager defaultManager] attributesOfItemAtPath:doc.path error:nil];
    const unsigned long long newSize = a.fileSize, oldSize = doc.diskSize;
    if (!a || newSize <= oldSize || oldSize == 0) return NO;
    int fd = open(doc.path.fileSystemRepresentation, O_RDONLY);
    if (fd < 0) return NO;
    const size_t probe = (size_t)MIN(oldSize, 4096ull);
    std::string tail(probe, '\0'), added((size_t)(newSize - oldSize), '\0');
    BOOL ok = pread(fd, tail.data(), probe, (off_t)(oldSize - probe)) == (ssize_t)probe &&
              pread(fd, added.data(), added.size(), (off_t)oldSize) == (ssize_t)added.size();
    close(fd);
    if (!ok) return NO;
    __block BOOL same = NO;
    [self withDocument:doc perform:^(ScintillaView *v) {
        const sptr_t len = SCI(v, SCI_GETLENGTH);
        const size_t bom = doc.encoding.mode == tpp::UniMode::Utf8Bom ? 3 : 0;
        if ((unsigned long long)len + bom != oldSize || (sptr_t)probe > len) return;
        same = sciGetRange(v, len - (sptr_t)probe, len) == tail;
        if (!same) return;
        const BOOL ro = SCI(v, SCI_GETREADONLY) != 0;
        SCI(v, SCI_SETREADONLY, 0);
        SCI(v, SCI_SETUNDOCOLLECTION, 0);
        SCI(v, SCI_APPENDTEXT, added.size(), reinterpret_cast<sptr_t>(added.data()));
        SCI(v, SCI_SETUNDOCOLLECTION, 1);
        SCI(v, SCI_EMPTYUNDOBUFFER);
        SCI(v, SCI_SETSAVEPOINT);
        SCI(v, SCI_SETREADONLY, ro);
        if (doc.monitoring) SCI(v, SCI_DOCUMENTEND);
    }];
    if (!same) return NO;
    doc.dirty = NO;
    [self updateDiskInfo:doc];
    [self refreshUI];
    return YES;
}

@end
