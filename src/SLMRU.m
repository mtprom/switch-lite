#import "SLMRU.h"
#import "SLWindow.h"

static const NSUInteger SLMRUCap = 256;

@implementation SLMRU {
    NSMutableArray<NSNumber *> *_ids;
    CFAbsoluteTime _suppressUntil;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _ids = [NSMutableArray array];
        _suppressUntil = 0;
    }
    return self;
}

- (void)insert:(CGWindowID)windowID {
    if (windowID == 0) return;
    NSNumber *number = @(windowID);
    [_ids removeObject:number];
    [_ids insertObject:number atIndex:0];
    if (_ids.count > SLMRUCap) {
        [_ids removeObjectsInRange:NSMakeRange(SLMRUCap, _ids.count - SLMRUCap)];
    }
}

- (void)refreshFrontWindow {
    if (CFAbsoluteTimeGetCurrent() < _suppressUntil) return;
    [self insert:SLFrontmostWindowID()];
}

- (void)rememberFocusedWindow:(CGWindowID)windowID {
    [self insert:windowID];
    // The system front window can lag the focus call. Don't let the idle poll undo it.
    _suppressUntil = CFAbsoluteTimeGetCurrent() + 1.0;
}

- (NSDictionary<NSNumber *, NSNumber *> *)ranks {
    NSMutableDictionary<NSNumber *, NSNumber *> *ranks = [NSMutableDictionary dictionaryWithCapacity:_ids.count];
    [_ids enumerateObjectsUsingBlock:^(NSNumber *number, NSUInteger idx, BOOL *stop) {
        (void)stop;
        ranks[number] = @(idx);
    }];
    return ranks;
}

@end
