#import "SLWindow.h"

#include <dlfcn.h>
#include <unistd.h>

static const CGFloat SLMinimumWindowEdge = 48.0;

@implementation SLWindow

- (NSString *)displayTitle {
    if (self.title.length > 0) return self.title;
    if (self.ownerName.length > 0) return self.ownerName;
    return @"Window";
}

- (NSString *)displaySubtitle {
    if (self.title.length == 0) return @"";
    if ([self.title isEqualToString:self.ownerName]) return @"";
    return self.ownerName ?: @"";
}

- (BOOL)isEqual:(id)object {
    if (object == self) return YES;
    if (![object isKindOfClass:[SLWindow class]]) return NO;
    return ((SLWindow *)object).windowID == self.windowID;
}

- (NSUInteger)hash {
    return (NSUInteger)self.windowID;
}

@end

static BOOL SLTextContains(NSString *text, NSString *needle) {
    if (text.length == 0 || needle.length == 0) return NO;
    return [text.lowercaseString containsString:needle];
}

// Chrome is decided from the process name and bundle, not the window title.
// A Cursor editor titled "Cursor Agents" is a real window. CursorUIViewService is not.
static BOOL SLIsChromeProcess(NSString *owner, NSString *bundleID) {
    NSString *blob = [NSString stringWithFormat:@"%@ %@", owner ?: @"", bundleID ?: @""];
    if (SLTextContains(blob, @"uiviewservice")) return YES;
    if (SLTextContains(blob, @"autofill")) return YES;
    if (SLTextContains(blob, @"siri")) return YES;
    if (SLTextContains(blob, @"agent")) return YES;
    if (SLTextContains(blob, @"service")) return YES;
    if (SLTextContains(blob, @"background activity")
        || SLTextContains(blob, @"background-activity")
        || SLTextContains(blob, @"backgroundactivity")) return YES;
    return NO;
}

// Electron helpers are not Dock apps, but their large windows belong to the host.
// "Cursor Helper (Renderer)" maps to the regular "Cursor" app. CursorUIViewService does not.
static NSRunningApplication *SLRegularHost(NSString *owner, NSRunningApplication *app) {
    if (app.activationPolicy == NSApplicationActivationPolicyRegular) return app;
    NSString *ownerName = owner ?: @"";
    NSRange helper = [ownerName rangeOfString:@" Helper" options:NSCaseInsensitiveSearch];
    NSString *hostName = helper.location == NSNotFound ? nil : [ownerName substringToIndex:helper.location];
    NSString *bundle = app.bundleIdentifier ?: @"";
    NSRange bundleHelper = [bundle rangeOfString:@".helper" options:NSCaseInsensitiveSearch];
    NSString *hostBundle = bundleHelper.location == NSNotFound ? nil : [bundle substringToIndex:bundleHelper.location];
    if (hostName.length == 0 && hostBundle.length == 0) return nil;
    for (NSRunningApplication *candidate in [NSWorkspace sharedWorkspace].runningApplications) {
        if (candidate.activationPolicy != NSApplicationActivationPolicyRegular) continue;
        if (hostName.length && [candidate.localizedName caseInsensitiveCompare:hostName] == NSOrderedSame) return candidate;
        if (hostBundle.length && [candidate.bundleIdentifier isEqualToString:hostBundle]) return candidate;
    }
    return nil;
}

// CGWindow bounds use a top-left origin. Accessibility frames use Cocoa's bottom-left origin.
static CGRect SLCocoaBounds(CGRect quartz) {
    NSScreen *menuBarScreen = [NSScreen screens].firstObject;
    if (!menuBarScreen) return quartz;
    CGRect cocoa = quartz;
    cocoa.origin.y = NSHeight(menuBarScreen.frame) - quartz.origin.y - quartz.size.height;
    return cocoa;
}

static BOOL SLReadWindow(NSDictionary *info, CGRect *boundsOut, BOOL *onScreenOut) {
    NSNumber *layer = info[(id)kCGWindowLayer];
    if (!layer || layer.integerValue != 0) return NO;

    pid_t pid = [info[(id)kCGWindowOwnerPID] intValue];
    if (pid <= 0 || pid == getpid()) return NO;

    NSNumber *alpha = info[(id)kCGWindowAlpha];
    if (alpha && alpha.doubleValue < 0.01) return NO;

    CGRect quartz = CGRectZero;
    CFDictionaryRef bounds = (__bridge CFDictionaryRef)info[(id)kCGWindowBounds];
    if (!bounds || !CGRectMakeWithDictionaryRepresentation(bounds, &quartz)) return NO;
    if (!isfinite(quartz.size.width) || !isfinite(quartz.size.height)) return NO;
    if (quartz.size.width < SLMinimumWindowEdge || quartz.size.height < SLMinimumWindowEdge) return NO;

    if (boundsOut) *boundsOut = SLCocoaBounds(quartz);
    if (onScreenOut) *onScreenOut = [info[(id)kCGWindowIsOnscreen] boolValue];
    return YES;
}

static SLWindow *SLWindowFromInfo(NSDictionary *info, NSInteger zOrder, NSMutableDictionary<NSNumber *, NSRunningApplication *> *apps) {
    CGRect bounds = CGRectZero;
    BOOL onScreen = NO;
    if (!SLReadWindow(info, &bounds, &onScreen)) return nil;

    CGWindowID windowID = (CGWindowID)[info[(id)kCGWindowNumber] unsignedIntValue];
    if (windowID == 0) return nil;

    pid_t pid = [info[(id)kCGWindowOwnerPID] intValue];
    NSRunningApplication *app = apps[@(pid)];
    if (!app) {
        app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        if (app) apps[@(pid)] = app;
    }

    id nameValue = info[(id)kCGWindowName];
    id ownerValue = info[(id)kCGWindowOwnerName];
    NSString *title = [nameValue isKindOfClass:[NSString class]] ? nameValue : @"";
    NSString *owner = [ownerValue isKindOfClass:[NSString class]] ? ownerValue : @"";
    if (SLIsChromeProcess(owner, app.bundleIdentifier)) return nil;
    NSRunningApplication *host = SLRegularHost(owner, app);
    if (!host) return nil;

    SLWindow *window = [SLWindow new];
    window.windowID = windowID;
    window.pid = pid;
    window.title = title ?: @"";
    window.ownerName = host.localizedName.length ? host.localizedName : (owner.length ? owner : @"Window");
    window.bundleID = host.bundleIdentifier ?: @"";
    window.iconKey = window.bundleID.length ? window.bundleID : [NSString stringWithFormat:@"pid:%d", pid];
    window.bounds = bounds;
    window.onScreen = onScreen;
    window.zOrder = zOrder;
    return window;
}

static CGWindowID SLAXWindowID(AXUIElementRef element) {
    static AXError (*getWindow)(AXUIElementRef, CGWindowID *) = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        getWindow = dlsym(RTLD_DEFAULT, "_AXUIElementGetWindow");
    });
    if (getWindow) {
        CGWindowID windowID = 0;
        if (getWindow(element, &windowID) == kAXErrorSuccess && windowID != 0) return windowID;
    }
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, CFSTR("AXWindowNumber"), &value) != kAXErrorSuccess || !value) {
        return 0;
    }
    CGWindowID windowID = 0;
    if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        CFNumberGetValue(value, kCFNumberSInt32Type, &windowID);
    }
    CFRelease(value);
    return windowID;
}

// Off-screen windows on another Space are not minimized. Ask Accessibility once per app.
static NSSet<NSNumber *> *SLMinimizedWindowIDs(pid_t pid) {
    AXUIElementRef application = AXUIElementCreateApplication(pid);
    if (!application) return [NSSet set];
    AXUIElementSetMessagingTimeout(application, 0.2);
    CFTypeRef raw = NULL;
    AXError error = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute, &raw);
    CFRelease(application);
    if (error != kAXErrorSuccess || !raw) return [NSSet set];
    id bridged = CFBridgingRelease(raw);
    if (![bridged isKindOfClass:[NSArray class]]) return [NSSet set];

    NSMutableSet<NSNumber *> *ids = [NSMutableSet set];
    for (id item in (NSArray *)bridged) {
        AXUIElementRef element = (__bridge AXUIElementRef)item;
        CFTypeRef minimizedValue = NULL;
        if (AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute, &minimizedValue) != kAXErrorSuccess || !minimizedValue) {
            continue;
        }
        BOOL minimized = CFGetTypeID(minimizedValue) == CFBooleanGetTypeID() && CFBooleanGetValue(minimizedValue);
        CFRelease(minimizedValue);
        if (!minimized) continue;
        CGWindowID windowID = SLAXWindowID(element);
        if (windowID != 0) [ids addObject:@(windowID)];
    }
    return ids;
}

NSArray<SLWindow *> *SLCollectWindows(void) {
    CFArrayRef raw = CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID);
    if (!raw) return @[];
    NSArray *list = CFBridgingRelease(raw);
    NSMutableArray<SLWindow *> *windows = [NSMutableArray array];
    NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
    NSMutableDictionary<NSNumber *, NSRunningApplication *> *apps = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, NSSet<NSNumber *> *> *minimizedByPID = [NSMutableDictionary dictionary];
    NSInteger index = 0;
    for (NSDictionary *info in list) {
        NSInteger zOrder = index++;
        if (![info isKindOfClass:[NSDictionary class]]) continue;
        SLWindow *window = SLWindowFromInfo(info, zOrder, apps);
        if (!window) continue;
        NSNumber *key = @(window.windowID);
        if ([seen containsObject:key]) continue;
        if (!window.onScreen) {
            NSNumber *pidKey = @(window.pid);
            NSSet<NSNumber *> *minimized = minimizedByPID[pidKey];
            if (!minimized) {
                minimized = SLMinimizedWindowIDs(window.pid);
                minimizedByPID[pidKey] = minimized;
            }
            if (![minimized containsObject:key]) continue;
        }
        [seen addObject:key];
        [windows addObject:window];
    }
    return windows;
}

CGWindowID SLFrontmostWindowID(void) {
    CFArrayRef raw = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    if (!raw) return 0;
    NSArray *list = CFBridgingRelease(raw);
    NSMutableDictionary<NSNumber *, NSRunningApplication *> *apps = [NSMutableDictionary dictionary];
    for (NSDictionary *info in list) {
        if (![info isKindOfClass:[NSDictionary class]]) continue;
        if (!SLReadWindow(info, NULL, NULL)) continue;
        pid_t pid = [info[(id)kCGWindowOwnerPID] intValue];
        NSRunningApplication *app = apps[@(pid)];
        if (!app && pid > 0) {
            app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
            if (app) apps[@(pid)] = app;
        }
        id ownerValue = info[(id)kCGWindowOwnerName];
        NSString *owner = [ownerValue isKindOfClass:[NSString class]] ? ownerValue : @"";
        if (SLIsChromeProcess(owner, app.bundleIdentifier)) continue;
        if (!SLRegularHost(owner, app)) continue;
        CGWindowID windowID = (CGWindowID)[info[(id)kCGWindowNumber] unsignedIntValue];
        if (windowID != 0) return windowID;
    }
    return 0;
}
