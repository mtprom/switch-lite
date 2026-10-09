#import "SLWindow.h"

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

static BOOL SLIsSkippedOwner(NSString *owner) {
    if (owner.length == 0) return NO;
    NSString *name = owner.lowercaseString;
    // CursorUIViewService owns the small chrome windows. The editor process is "Cursor".
    if ([name isEqualToString:@"cursoruiviewservice"] || [name hasSuffix:@"uiviewservice"]) return YES;
    return [name isEqualToString:@"dock"]
        || [name isEqualToString:@"window server"]
        || [name isEqualToString:@"windowserver"]
        || [name isEqualToString:@"systemuiserver"]
        || [name isEqualToString:@"control center"]
        || [name isEqualToString:@"controlcenter"];
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

    id ownerValue = info[(id)kCGWindowOwnerName];
    NSString *owner = [ownerValue isKindOfClass:[NSString class]] ? ownerValue : nil;
    if (SLIsSkippedOwner(owner)) return NO;

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

    SLWindow *window = [SLWindow new];
    window.windowID = windowID;
    window.pid = pid;
    window.title = title ?: @"";
    window.ownerName = owner.length ? owner : @"Window";
    window.bundleID = app.bundleIdentifier ?: @"";
    window.iconKey = window.bundleID.length ? window.bundleID : [NSString stringWithFormat:@"pid:%d", pid];
    window.bounds = bounds;
    window.onScreen = onScreen;
    window.zOrder = zOrder;
    return window;
}

NSArray<SLWindow *> *SLCollectWindows(void) {
    CFArrayRef raw = CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID);
    if (!raw) return @[];
    NSArray *list = CFBridgingRelease(raw);
    NSMutableArray<SLWindow *> *windows = [NSMutableArray array];
    NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
    NSMutableDictionary<NSNumber *, NSRunningApplication *> *apps = [NSMutableDictionary dictionary];
    NSInteger index = 0;
    for (NSDictionary *info in list) {
        NSInteger zOrder = index++;
        if (![info isKindOfClass:[NSDictionary class]]) continue;
        SLWindow *window = SLWindowFromInfo(info, zOrder, apps);
        if (!window) continue;
        NSNumber *key = @(window.windowID);
        if ([seen containsObject:key]) continue;
        [seen addObject:key];
        [windows addObject:window];
    }
    return windows;
}

CGWindowID SLFrontmostWindowID(void) {
    CFArrayRef raw = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
    if (!raw) return 0;
    NSArray *list = CFBridgingRelease(raw);
    for (NSDictionary *info in list) {
        if (![info isKindOfClass:[NSDictionary class]]) continue;
        if (!SLReadWindow(info, NULL, NULL)) continue;
        CGWindowID windowID = (CGWindowID)[info[(id)kCGWindowNumber] unsignedIntValue];
        if (windowID != 0) return windowID;
    }
    return 0;
}
