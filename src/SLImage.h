#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// One owned CGImage. Releasing the object releases the image.
@interface SLOwnedImage : NSObject
+ (instancetype)imageWithCGImage:(CGImageRef)image;
- (CGImageRef)image CF_RETURNS_NOT_RETAINED;
@end
