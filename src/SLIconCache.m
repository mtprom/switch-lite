#import "SLIconCache.h"
#import "SLImage.h"

static const size_t SLIconPixels = 64; // 32pt at 2x

static CGImageRef SLRasterize(NSImage *icon) {
    if (!icon) return NULL;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    if (!space) return NULL;
    CGContextRef context = CGBitmapContextCreate(NULL, SLIconPixels, SLIconPixels, 8, 0, space,
                                                 kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) return NULL;

    NSGraphicsContext *graphics = [NSGraphicsContext graphicsContextWithCGContext:context flipped:NO];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:graphics];
    [icon drawInRect:NSMakeRect(0, 0, SLIconPixels, SLIconPixels)
            fromRect:NSZeroRect
           operation:NSCompositingOperationSourceOver
            fraction:1];
    [NSGraphicsContext restoreGraphicsState];

    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return image;
}

static CGImageRef SLIconImageForPID(pid_t pid) {
    @autoreleasepool {
        NSImage *icon = nil;
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        icon = app.icon;
        if (!icon && app.bundleURL.path.length > 0) {
            icon = [[NSWorkspace sharedWorkspace] iconForFile:app.bundleURL.path];
        }
        if (!icon) icon = [NSImage imageNamed:NSImageNameApplicationIcon];
        return SLRasterize(icon);
    }
}

@implementation SLIconCache {
    NSMutableDictionary<NSString *, SLOwnedImage *> *_cache;
}

- (instancetype)init {
    self = [super init];
    if (self) _cache = [NSMutableDictionary dictionary];
    return self;
}

- (void)prepareForKey:(NSString *)key pid:(pid_t)pid {
    if (key.length == 0 || _cache[key]) return;
    if (_cache.count > 80) [_cache removeAllObjects];
    CGImageRef image = SLIconImageForPID(pid);
    if (!image) return;
    _cache[key] = [SLOwnedImage imageWithCGImage:image];
    CGImageRelease(image);
}

- (CGImageRef)imageForKey:(NSString *)key {
    if (key.length == 0) return NULL;
    return _cache[key].image;
}

@end
