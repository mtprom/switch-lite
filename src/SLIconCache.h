#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Tiny app icons only (32pt, stored as a 64px bitmap). Full-size icons are not kept.
@interface SLIconCache : NSObject
- (void)prepareForKey:(NSString *)key pid:(pid_t)pid;
- (CGImageRef)imageForKey:(NSString *)key CF_RETURNS_NOT_RETAINED;
@end
