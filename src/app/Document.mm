// Textpad++ — document (buffer) model. GPL-3.0-or-later.
#import "app/Document.h"

@implementation TPDocument {
    TPViewPosition _pos[2];
}

static NSUInteger g_nextUid = 1;

- (instancetype)initUntitled:(NSString *)name {
    if ((self = [super init])) {
        _uid = g_nextUid++;
        _untitledName = [name copy];
        _languageId = @"normal";
        _encoding = tpp::TextEncoding{tpp::UniMode::Utf8, -1};
        _eolMode = SC_EOL_LF;
        _tabColor = -1;
    }
    return self;
}

- (instancetype)initWithPath:(NSString *)path {
    if ((self = [self initUntitled:@""])) {
        _path = [path copy];
    }
    return self;
}

- (BOOL)isUntitled { return _path == nil; }

- (NSString *)displayName {
    return _path ? _path.lastPathComponent : _untitledName;
}

- (NSString *)tabLabel {
    return (_path == nil && _contentTitle.length) ? _contentTitle : self.displayName;
}

- (TPViewPosition)positionForView:(int)viewIndex {
    return _pos[viewIndex == 1 ? 1 : 0];
}

- (void)setPosition:(TPViewPosition)pos forView:(int)viewIndex {
    _pos[viewIndex == 1 ? 1 : 0] = pos;
}

@end
