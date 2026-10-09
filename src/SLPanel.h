#import <Cocoa/Cocoa.h>
@class SLIconCache;
@class SLWindow;

@interface SLPanel : NSObject
- (instancetype)initWithIconCache:(SLIconCache *)icons;
- (void)presentWindows:(NSArray<SLWindow *> *)windows
              selected:(NSInteger)selected
                 query:(NSString *)query;
- (void)noteThumbnailForWindow:(SLWindow *)window;
- (void)hide;
- (NSInteger)columnCount;
- (NSInteger)cellIndexAtScreenPoint:(NSPoint)point outside:(BOOL *)outside;
- (BOOL)scrollBy:(CGFloat)deltaY atScreenPoint:(NSPoint)point;
@property (nonatomic, readonly, getter=isVisible) BOOL visible;
@end
