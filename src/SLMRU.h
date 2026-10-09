#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Recent window ids only. Index 0 is the most recently focused window.
@interface SLMRU : NSObject
- (void)refreshFrontWindow;
- (void)rememberFocusedWindow:(CGWindowID)windowID;
- (NSDictionary<NSNumber *, NSNumber *> *)ranks;
@end
