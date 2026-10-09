#define __ASSERT_MACROS_DEFINE_VERSIONS_WITHOUT_UNDERSCORES 0
#import "SLFocus.h"
#import "SLWindow.h"

#include <unistd.h>
#import <dlfcn.h>

#define __ASSERT_MACROS_DEFINE_VERSIONS_WITHOUT_UNDERSCORES 0
#import <Carbon/Carbon.h>

// User-generated front-process mode. Loaded from SkyLight at runtime.
static const UInt32 kSLPSModeUserGenerated = 0x200;

typedef OSStatus (*SLPSSetFrontFunction)(ProcessSerialNumber *psn, UInt32 windowID, UInt32 mode);

static SLPSSetFrontFunction SLLoadSetFront(void) {
    static SLPSSetFrontFunction function = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
        if (!library) {
            library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_LAZY);
        }
        if (library) {
            function = (SLPSSetFrontFunction)dlsym(library, "_SLPSSetFrontProcessWithOptions");
        }
        if (!function) {
            NSLog(@"Switch Lite: _SLPSSetFrontProcessWithOptions is unavailable");
        }
    });
    return function;
}

static NSString *SLAXString(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, attribute, &value) != kAXErrorSuccess || !value) return nil;
    NSString *result = nil;
    if (CFGetTypeID(value) == CFStringGetTypeID()) {
        result = [(__bridge NSString *)value copy];
    }
    CFRelease(value);
    return result;
}

static BOOL SLAXGeometry(AXUIElementRef element, CFStringRef attribute, AXValueType type, void *out) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, attribute, &value) != kAXErrorSuccess || !value) return NO;
    BOOL ok = NO;
    if (CFGetTypeID(value) == AXValueGetTypeID()) {
        ok = AXValueGetValue((AXValueRef)value, type, out);
    }
    CFRelease(value);
    return ok;
}

static AXUIElementRef SLCopyAXWindow(SLWindow *window) {
    if (!window || window.pid <= 0) return NULL;
    AXUIElementRef application = AXUIElementCreateApplication(window.pid);
    if (!application) return NULL;
    AXUIElementSetMessagingTimeout(application, 0.4);

    CFTypeRef raw = NULL;
    AXError error = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute, &raw);
    if (error != kAXErrorSuccess || !raw) {
        CFRelease(application);
        return NULL;
    }
    id bridged = CFBridgingRelease(raw);
    if (![bridged isKindOfClass:[NSArray class]]) {
        CFRelease(application);
        return NULL;
    }

    NSString *wanted = window.title ?: @"";
    AXUIElementRef best = NULL;
    CGFloat bestScore = 1e300;
    BOOL strongFrame = NO;

    for (id item in (NSArray *)bridged) {
        AXUIElementRef candidate = (__bridge AXUIElementRef)item;
        AXUIElementSetMessagingTimeout(candidate, 0.2);
        NSString *title = SLAXString(candidate, kAXTitleAttribute);
        CGPoint position = CGPointZero;
        CGSize size = CGSizeZero;
        BOOL havePosition = SLAXGeometry(candidate, kAXPositionAttribute, kAXValueCGPointType, &position);
        BOOL haveSize = SLAXGeometry(candidate, kAXSizeAttribute, kAXValueCGSizeType, &size);
        BOOL titleMatch = wanted.length > 0 && [title isEqualToString:wanted];

        CGFloat score = 1e300;
        if (havePosition) {
            CGFloat dx = position.x - window.bounds.origin.x;
            CGFloat dy = position.y - window.bounds.origin.y;
            score = dx * dx + dy * dy;
            if (haveSize) {
                CGFloat dw = size.width - window.bounds.size.width;
                CGFloat dh = size.height - window.bounds.size.height;
                score += dw * dw + dh * dh;
            }
        }
        BOOL strong = score < (12.0 * 12.0);
        if (strong && score < bestScore) {
            best = candidate;
            bestScore = score;
            strongFrame = YES;
        } else if (!strongFrame && titleMatch && (!best || score < bestScore)) {
            best = candidate;
            bestScore = score;
        }
    }

    if (best) CFRetain(best);
    CFRelease(application);
    return best;
}

static BOOL SLUnminimize(AXUIElementRef window) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute, &value) != kAXErrorSuccess || !value) return NO;
    BOOL minimized = CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)value);
    CFRelease(value);
    if (!minimized) return NO;
    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute, kCFBooleanFalse);
    return YES;
}

static void SLRaise(AXUIElementRef window) {
    if (!window) return;
    AXUIElementSetAttributeValue(window, kAXMainAttribute, kCFBooleanTrue);
    AXUIElementPerformAction(window, kAXRaiseAction);
    AXUIElementSetAttributeValue(window, kAXFocusedAttribute, kCFBooleanTrue);
}

static void SLBringToFront(SLWindow *window) {
    SLPSSetFrontFunction function = SLLoadSetFront();
    ProcessSerialNumber psn = {0, 0};
    OSStatus pidStatus = -1;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    pidStatus = GetProcessForPID(window.pid, &psn);
#pragma clang diagnostic pop

    BOOL brought = NO;
    if (function && pidStatus == noErr) {
        OSStatus status = function(&psn, (UInt32)window.windowID, kSLPSModeUserGenerated);
        brought = status == noErr;
        if (!brought) {
            NSLog(@"Switch Lite: focus failed (%d) for window %u", (int)status, window.windowID);
        }
    }
    if (!brought) {
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:window.pid];
        [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    }
}

static BOOL SLOwnProcess(SLWindow *window) {
    return !window || window.pid <= 0 || window.pid == getpid();
}

@implementation SLFocus

+ (void)focusWindow:(SLWindow *)window {
    if (SLOwnProcess(window)) return;
    AXUIElementRef axWindow = SLCopyAXWindow(window);
    BOOL wasMinimized = NO;
    if (axWindow) wasMinimized = SLUnminimize(axWindow);
    SLBringToFront(window);
    if (!axWindow) return;
    if (wasMinimized) {
        AXUIElementRef kept = CFRetain(axWindow);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            SLRaise(kept);
            CFRelease(kept);
        });
    } else {
        SLRaise(axWindow);
    }
    CFRelease(axWindow);
}

+ (BOOL)closeWindow:(SLWindow *)window {
    if (SLOwnProcess(window)) return NO;
    AXUIElementRef axWindow = SLCopyAXWindow(window);
    if (!axWindow) return NO;
    BOOL ok = NO;
    CFTypeRef button = NULL;
    if (AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute, &button) == kAXErrorSuccess && button) {
        ok = AXUIElementPerformAction((AXUIElementRef)button, kAXPressAction) == kAXErrorSuccess;
        CFRelease(button);
    }
    CFRelease(axWindow);
    return ok;
}

+ (BOOL)minimizeWindow:(SLWindow *)window {
    if (SLOwnProcess(window)) return NO;
    AXUIElementRef axWindow = SLCopyAXWindow(window);
    if (!axWindow) return NO;
    AXError error = AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute, kCFBooleanTrue);
    CFRelease(axWindow);
    return error == kAXErrorSuccess;
}

+ (BOOL)hideApplicationForWindow:(SLWindow *)window {
    if (SLOwnProcess(window)) return NO;
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:window.pid];
    if (!app) return NO;
    [app hide];
    return YES;
}

+ (BOOL)quitApplicationForWindow:(SLWindow *)window {
    if (SLOwnProcess(window)) return NO;
    NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:window.pid];
    if (!app) return NO;
    return [app terminate];
}

@end
