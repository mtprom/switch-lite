#import "SLAppDelegate.h"
#import "SLEventTap.h"
#import "SLMRU.h"
#import "SLSession.h"

@implementation SLAppDelegate {
    SLMRU *_mru;
    SLSession *_session;
    SLEventTap *_tap;
    NSTimer *_timer;
    NSUInteger _ticks;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);

    _mru = [SLMRU new];
    [_mru refreshFrontWindow];
    _session = [[SLSession alloc] initWithMRU:_mru];
    _tap = [SLEventTap new];
    _tap.handler = _session;
    [_tap start];

    _timer = [NSTimer timerWithTimeInterval:0.5
                                     target:self
                                   selector:@selector(tick:)
                                   userInfo:nil
                                    repeats:YES];
    _timer.tolerance = 0.15;
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)tick:(NSTimer *)timer {
    (void)timer;
    @autoreleasepool {
        // Ids only. Skip the poll while a session is showing so capture has the window server.
        if (![_session switcherIsOpen]) [_mru refreshFrontWindow];
        _ticks += 1;
        if (_ticks % 4 == 0) [_tap ensureEnabled];
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [_timer invalidate];
    _timer = nil;
    [_session cancel];
    [_tap stop];
}

@end
