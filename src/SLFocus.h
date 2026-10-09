#import <Foundation/Foundation.h>
@class SLWindow;

@interface SLFocus : NSObject
+ (void)focusWindow:(SLWindow *)window;
+ (BOOL)closeWindow:(SLWindow *)window;
+ (BOOL)minimizeWindow:(SLWindow *)window;
+ (BOOL)hideApplicationForWindow:(SLWindow *)window;
+ (BOOL)quitApplicationForWindow:(SLWindow *)window;
@end
