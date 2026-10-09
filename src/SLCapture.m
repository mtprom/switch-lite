#import "SLCapture.h"
#import "SLWindow.h"

#include <math.h>
#include <stdbool.h>
#include <stdlib.h>

// Thumbnails exist only while the panel is open. Each window is captured at
// nominal resolution, copied into our own bitmap (max 400px on the long side),
// and the full frame is released before the next window is captured.

static const size_t SLMaxThumbnailEdge = 400;

static void SLFreeBitmap(void *info, const void *data, size_t size) {
    (void)info;
    (void)size;
    free((void *)data);
}

// Always blit into a private buffer so the window-server image (and any
// IOSurface behind it) can be released immediately.
static CGImageRef SLCreateSmallBitmap(CGImageRef source) {
    size_t width = CGImageGetWidth(source);
    size_t height = CGImageGetHeight(source);
    if (width == 0 || height == 0) return NULL;

    double scale = 1.0;
    size_t longEdge = width > height ? width : height;
    if (longEdge > SLMaxThumbnailEdge) scale = (double)SLMaxThumbnailEdge / (double)longEdge;
    size_t destW = (size_t)llround((double)width * scale);
    size_t destH = (size_t)llround((double)height * scale);
    if (destW < 1) destW = 1;
    if (destH < 1) destH = 1;

    size_t bytesPerRow = (destW * 4u + 15u) & ~(size_t)15u;
    size_t byteCount = bytesPerRow * destH;
    void *buffer = calloc(1, byteCount);
    if (!buffer) return NULL;

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    if (!space) {
        free(buffer);
        return NULL;
    }
    CGContextRef context = CGBitmapContextCreate(buffer, destW, destH, 8, bytesPerRow, space,
                                                 kCGImageAlphaPremultipliedLast);
    if (!context) {
        CGColorSpaceRelease(space);
        free(buffer);
        return NULL;
    }
    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    CGContextDrawImage(context, CGRectMake(0, 0, (CGFloat)destW, (CGFloat)destH), source);
    CGContextRelease(context);

    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, buffer, byteCount, SLFreeBitmap);
    if (!provider) {
        CGColorSpaceRelease(space);
        free(buffer);
        return NULL;
    }
    CGImageRef image = CGImageCreate(destW, destH, 8, 32, bytesPerRow, space,
                                     kCGImageAlphaPremultipliedLast,
                                     provider, NULL, true, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(space);
    return image;
}

static CGImageRef SLCreateNominalThumbnail(CGWindowID windowID) {
    CGImageRef full = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    full = CGWindowListCreateImage(CGRectNull,
                                   kCGWindowListOptionIncludingWindow,
                                   windowID,
                                   kCGWindowImageNominalResolution | kCGWindowImageBoundsIgnoreFraming);
#pragma clang diagnostic pop
    if (!full) return NULL;
    CGImageRef small = SLCreateSmallBitmap(full);
    CGImageRelease(full);
    return small;
}

@implementation SLCapture {
    dispatch_queue_t _queue;
    NSArray<SLWindow *> *_windows;
    SLWindow *_preferred;
    void (^_onUpdate)(SLWindow *window);
    NSUInteger _generation;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("app.switchlite.capture",
                                       dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                                              QOS_CLASS_USER_INITIATED, 0));
    }
    return self;
}

- (void)beginWithWindows:(NSArray<SLWindow *> *)windows
               preferred:(SLWindow *)preferred
                onUpdate:(void (^)(SLWindow *window))onUpdate {
    _generation += 1;
    NSUInteger generation = _generation;
    _windows = [windows copy];
    _preferred = preferred;
    _onUpdate = [onUpdate copy];

    BOOL pending = NO;
    for (SLWindow *window in _windows) {
        window.thumbnail = nil;
        window.captureFinished = !window.onScreen || window.windowID == 0 || window.retired;
        if (!window.captureFinished) pending = YES;
    }
    if (pending) [self captureNext:generation];
}

- (void)invalidate {
    _generation += 1;
    _windows = nil;
    _preferred = nil;
    _onUpdate = nil;
}

- (void)captureNext:(NSUInteger)generation {
    if (generation != _generation) return;

    SLWindow *next = nil;
    if (_preferred && !_preferred.captureFinished && !_preferred.retired && _preferred.onScreen) {
        next = _preferred;
    } else {
        for (SLWindow *window in _windows) {
            if (window.captureFinished || window.retired || !window.onScreen || window.windowID == 0) continue;
            next = window;
            break;
        }
    }
    if (!next) return;

    CGWindowID windowID = next.windowID;
    __weak SLCapture *weakSelf = self;
    dispatch_async(_queue, ^{
        @autoreleasepool {
            // Full frame is released inside SLCreateNominalThumbnail before we hop back.
            CGImageRef small = SLCreateNominalThumbnail(windowID);
            dispatch_async(dispatch_get_main_queue(), ^{
                SLCapture *self_ = weakSelf;
                if (!self_ || generation != self_->_generation || next.retired) {
                    if (small) CGImageRelease(small);
                    return;
                }
                if (small) {
                    next.thumbnail = [SLOwnedImage imageWithCGImage:small];
                    CGImageRelease(small);
                }
                next.captureFinished = YES;
                if (self_->_onUpdate) self_->_onUpdate(next);
                [self_ captureNext:generation];
            });
        }
    });
}

@end
