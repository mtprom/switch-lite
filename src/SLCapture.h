#import <Foundation/Foundation.h>
@class SLWindow;

@interface SLCapture : NSObject
- (void)beginWithWindows:(NSArray<SLWindow *> *)windows
               preferred:(SLWindow *)preferred
                onUpdate:(void (^)(SLWindow *window))onUpdate;
- (void)invalidate;
@end
