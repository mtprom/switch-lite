#import "SLAppDelegate.h"
#import "SLEventTap.h"
#import "SLMRU.h"
#import "SLSession.h"
#import "SLSystemHotKey.h"

@implementation SLAppDelegate {
    SLMRU *_mru;
    SLSession *_session;
    SLEventTap *_tap;
    NSTimer *_timer;
    NSUInteger _ticks;
}

- (void)armCommandTabIfTapIsRunning {
    // Take Cmd-Tab only while the tap can actually receive it. Otherwise macOS keeps it.
    if ([_tap isRunning]) SLDisableSystemCommandTab();
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    // A previous crash may have left Cmd-Tab disabled. Give it back before this launch takes it.
    SLRecoverInterruptedCommandTab();

    // Prompt at most once. A later launch of the same signature just checks trust,
    // so quit and reopen does not show the Accessibility dialog again.
    if (!AXIsProcessTrusted()) {
        NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Switch Lite"];
        NSString *asked = [dir stringByAppendingPathComponent:@"accessibility-asked"];
        NSFileManager *files = [NSFileManager defaultManager];
        if (![files fileExistsAtPath:asked]) {
            [files createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
            [[NSData data] writeToFile:asked atomically:YES];
            NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
            AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
        }
    }

    _mru = [SLMRU new];
    [_mru refreshFrontWindow];
    _session = [[SLSession alloc] initWithMRU:_mru];
    _tap = [SLEventTap new];
    _tap.handler = _session;
    [_tap start];
    [self armCommandTabIfTapIsRunning];

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
        if (_ticks % 4 == 0) {
            [_tap ensureEnabled];
            [self armCommandTabIfTapIsRunning];
        }
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [_timer invalidate];
    _timer = nil;
    [_session cancel];
    [_tap stop];
    SLRestoreSystemCommandTab();
}

@end
