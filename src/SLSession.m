#import "SLSession.h"
#import "SLCapture.h"
#import "SLFocus.h"
#import "SLIconCache.h"
#import "SLMRU.h"
#import "SLPanel.h"
#import "SLWindow.h"

#include <unistd.h>

static NSInteger SLInitialSelection(NSInteger count, BOOL forward) {
    if (count <= 1) return 0;
    return forward ? 1 : count - 1;
}

@implementation SLSession {
    SLMRU *_mru;
    SLIconCache *_icons;
    SLPanel *_panel;
    SLCapture *_capture;
    NSMutableArray<SLWindow *> *_all;
    NSArray<SLWindow *> *_filtered;
    NSString *_query;
    NSInteger _selected;
    BOOL _open;
    BOOL _opening;
    BOOL _actionBusy;
    BOOL _didRequestCapture;
}

- (instancetype)initWithMRU:(SLMRU *)mru {
    self = [super init];
    if (self) {
        _mru = mru;
        _icons = [SLIconCache new];
        _panel = [[SLPanel alloc] initWithIconCache:_icons];
        _capture = [SLCapture new];
        _query = @"";
        _selected = -1;
    }
    return self;
}

- (BOOL)switcherIsOpen {
    return _open;
}

- (BOOL)switcherQueryIsEmpty {
    return _query.length == 0;
}

- (NSArray<SLWindow *> *)sortedWindows:(NSArray<SLWindow *> *)windows {
    NSDictionary<NSNumber *, NSNumber *> *ranks = [_mru ranks];
    NSInteger missingBase = (NSInteger)ranks.count + 1000;
    return [windows sortedArrayUsingComparator:^NSComparisonResult(SLWindow *a, SLWindow *b) {
        NSNumber *rankA = ranks[@(a.windowID)];
        NSNumber *rankB = ranks[@(b.windowID)];
        NSInteger indexA = rankA ? rankA.integerValue : missingBase + a.zOrder;
        NSInteger indexB = rankB ? rankB.integerValue : missingBase + b.zOrder;
        if (indexA < indexB) return NSOrderedAscending;
        if (indexA > indexB) return NSOrderedDescending;
        if (a.zOrder < b.zOrder) return NSOrderedAscending;
        if (a.zOrder > b.zOrder) return NSOrderedDescending;
        return NSOrderedSame;
    }];
}

- (NSArray<SLWindow *> *)windowsForFrontApplication:(NSArray<SLWindow *> *)sorted {
    pid_t pid = [NSWorkspace sharedWorkspace].frontmostApplication.processIdentifier;
    if (pid == getpid() || pid <= 0) pid = sorted.firstObject.pid;
    NSMutableArray<SLWindow *> *mine = [NSMutableArray array];
    for (SLWindow *window in sorted) {
        if (window.pid == pid) [mine addObject:window];
    }
    return mine;
}

- (NSArray<SLWindow *> *)matching:(NSArray<SLWindow *> *)windows {
    if (_query.length == 0) return [windows copy];
    NSString *query = _query.lowercaseString;
    NSMutableArray<SLWindow *> *matched = [NSMutableArray array];
    for (SLWindow *window in windows) {
        NSString *title = window.title.lowercaseString ?: @"";
        NSString *owner = window.ownerName.lowercaseString ?: @"";
        NSString *display = window.displayTitle.lowercaseString ?: @"";
        if ([title containsString:query] || [owner containsString:query] || [display containsString:query]) {
            [matched addObject:window];
        }
    }
    return matched;
}

- (SLWindow *)selectedWindow {
    if (_selected < 0 || _selected >= (NSInteger)_filtered.count) return nil;
    return _filtered[_selected];
}

- (void)refreshPanel {
    [_panel presentWindows:_filtered selected:_selected query:_query];
}

- (void)rebuildFilterPreservingSelection:(BOOL)preserve {
    SLWindow *keep = preserve ? [self selectedWindow] : nil;
    _filtered = [self matching:_all];
    if (_filtered.count == 0) {
        _selected = -1;
        return;
    }
    if (keep) {
        NSUInteger index = [_filtered indexOfObject:keep];
        _selected = index == NSNotFound ? 0 : (NSInteger)index;
    } else if (_selected < 0 || _selected >= (NSInteger)_filtered.count) {
        _selected = 0;
    }
}

- (void)openScopedToFrontApp:(BOOL)frontApp forward:(BOOL)forward {
    if (_open) {
        [self cycleForward:forward];
        return;
    }
    // The Screen Recording prompt runs a nested loop. Ignore a re-entrant Option-Tab.
    if (_opening) return;
    if ([NSScreen screens].count == 0) {
        NSBeep();
        return;
    }

    _opening = YES;
    // Ask before the panel exists so the system dialog is not swallowed by the click handler.
    BOOL captureAllowed = [self requestCaptureAccessOnce];
    [_mru refreshFrontWindow];
    NSArray<SLWindow *> *windows = [self sortedWindows:SLCollectWindows()];
    if (frontApp) windows = [self windowsForFrontApplication:windows];
    if (windows.count == 0) {
        _opening = NO;
        NSBeep();
        return;
    }

    _all = [windows mutableCopy];
    _query = @"";
    _filtered = [_all copy];
    _selected = SLInitialSelection((NSInteger)_filtered.count, forward);
    _open = YES;
    _actionBusy = NO;
    for (SLWindow *window in _all) {
        [_icons prepareForKey:window.iconKey pid:window.pid];
    }
    [self refreshPanel];
    _opening = NO;

    if (!captureAllowed) return;
    __weak SLSession *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf startCaptureIfStillOpen];
    });
}

- (void)openAllWindowsForward:(BOOL)forward {
    [self openScopedToFrontApp:NO forward:forward];
}

- (void)openFrontAppWindowsForward:(BOOL)forward {
    [self openScopedToFrontApp:YES forward:forward];
}

- (BOOL)requestCaptureAccessOnce {
    if (CGPreflightScreenCaptureAccess()) return YES;
    if (!_didRequestCapture) {
        _didRequestCapture = YES;
        CGRequestScreenCaptureAccess();
    }
    return CGPreflightScreenCaptureAccess();
}

- (void)startCaptureIfStillOpen {
    if (!_open || !CGPreflightScreenCaptureAccess()) return;
    SLWindow *preferred = [self selectedWindow];
    __weak SLSession *weakSelf = self;
    [_capture beginWithWindows:_all preferred:preferred onUpdate:^(SLWindow *window) {
        SLSession *self_ = weakSelf;
        if (!self_ || !self_->_open) return;
        [self_->_panel noteThumbnailForWindow:window];
    }];
}

- (void)endSession {
    if (!_open) return;
    _open = NO;
    [_capture invalidate];
    for (SLWindow *window in _all) {
        window.thumbnail = nil;
        window.captureFinished = YES;
    }
    [_panel hide];
    _all = nil;
    _filtered = nil;
    _query = @"";
    _selected = -1;
    _actionBusy = NO;
}

- (void)focusLater:(SLWindow *)window {
    if (!window || window.retired) return;
    [_mru rememberFocusedWindow:window.windowID];
    dispatch_async(dispatch_get_main_queue(), ^{
        [SLFocus focusWindow:window];
    });
}

- (void)commit {
    if (!_open) return;
    SLWindow *window = [self selectedWindow];
    [self endSession];
    if (window) [self focusLater:window];
}

- (void)cancel {
    [self endSession];
}

- (void)quit {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSApp terminate:nil];
    });
}

- (void)moveBy:(NSInteger)delta {
    if (!_open || _filtered.count == 0 || delta == 0) return;
    NSInteger count = (NSInteger)_filtered.count;
    NSInteger index = _selected < 0 ? 0 : _selected;
    index += delta;
    index %= count;
    if (index < 0) index += count;
    _selected = index;
    [self refreshPanel];
}

- (void)cycleForward:(BOOL)forward {
    [self moveBy:forward ? 1 : -1];
}

- (void)moveHorizontal:(NSInteger)dx vertical:(NSInteger)dy {
    NSInteger columns = MAX((NSInteger)1, [_panel columnCount]);
    [self moveBy:dy * columns + dx];
}

- (void)insertText:(NSString *)text {
    if (!_open || text.length == 0 || _query.length >= 64) return;
    if (_query.length == 0) {
        NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) return;
    }
    NSString *next = [_query stringByAppendingString:text];
    if (next.length > 64) next = [next substringToIndex:64];
    _query = next;
    [self rebuildFilterPreservingSelection:YES];
    [self refreshPanel];
}

- (void)backspace {
    if (!_open || _query.length == 0) return;
    NSRange range = [_query rangeOfComposedCharacterSequenceAtIndex:_query.length - 1];
    _query = [_query substringToIndex:range.location];
    [self rebuildFilterPreservingSelection:YES];
    [self refreshPanel];
}

- (void)escape {
    if (!_open) return;
    if (_query.length > 0) {
        _query = @"";
        [self rebuildFilterPreservingSelection:YES];
        [self refreshPanel];
        return;
    }
    [self cancel];
}

- (void)clickAtScreenPoint:(NSPoint)point {
    if (!_open) return;
    BOOL outside = NO;
    NSInteger index = [_panel cellIndexAtScreenPoint:point outside:&outside];
    if (outside) {
        [self cancel];
        return;
    }
    if (index == NSNotFound || index < 0 || index >= (NSInteger)_filtered.count) return;
    SLWindow *window = _filtered[index];
    [self endSession];
    [self focusLater:window];
}

- (BOOL)handleScroll:(CGFloat)deltaY atScreenPoint:(NSPoint)point {
    if (!_open) return NO;
    return [_panel scrollBy:deltaY atScreenPoint:point];
}

- (void)retireWindow:(SLWindow *)window {
    NSInteger previous = _selected;
    window.retired = YES;
    window.captureFinished = YES;
    window.thumbnail = nil;
    [_all removeObject:window];
    _filtered = [self matching:_all];
    if (_filtered.count == 0) {
        [self cancel];
        return;
    }
    _selected = previous;
    if (_selected >= (NSInteger)_filtered.count) _selected = (NSInteger)_filtered.count - 1;
    if (_selected < 0) _selected = 0;
    [self refreshPanel];
}

- (void)retirePID:(pid_t)pid {
    NSInteger previous = _selected;
    NSMutableArray<SLWindow *> *keep = [NSMutableArray array];
    for (SLWindow *window in _all) {
        if (window.pid == pid) {
            window.retired = YES;
            window.captureFinished = YES;
            window.thumbnail = nil;
        } else {
            [keep addObject:window];
        }
    }
    _all = keep;
    _filtered = [self matching:_all];
    if (_filtered.count == 0) {
        [self cancel];
        return;
    }
    _selected = previous;
    if (_selected >= (NSInteger)_filtered.count) _selected = (NSInteger)_filtered.count - 1;
    if (_selected < 0) _selected = 0;
    [self refreshPanel];
}

- (void)applyShortcut:(unichar)key toWindow:(SLWindow *)window {
    if (key == 'w') {
        if ([SLFocus closeWindow:window]) [self retireWindow:window];
    } else if (key == 'm') {
        [SLFocus minimizeWindow:window];
    } else if (key == 'h') {
        [SLFocus hideApplicationForWindow:window];
    } else if (key == 'q') {
        if ([SLFocus quitApplicationForWindow:window]) [self retirePID:window.pid];
    }
}

- (void)performShortcut:(unichar)key {
    if (!_open || _query.length > 0 || _actionBusy) return;
    SLWindow *window = [self selectedWindow];
    if (!window) return;
    _actionBusy = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_open) {
            self->_actionBusy = NO;
            return;
        }
        [self applyShortcut:key toWindow:window];
        self->_actionBusy = NO;
    });
}

@end
