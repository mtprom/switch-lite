#import <Cocoa/Cocoa.h>
#import "SLImage.h"

// One on-screen or off-screen window. Thumbnails are attached only while the
// switcher panel is visible.
@interface SLWindow : NSObject
@property (nonatomic) CGWindowID windowID;
@property (nonatomic) pid_t pid;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *ownerName;
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *iconKey;
@property (nonatomic) CGRect bounds;
@property (nonatomic) BOOL onScreen;
@property (nonatomic) NSInteger zOrder;
@property (nonatomic) BOOL captureFinished;
@property (nonatomic) BOOL retired;
@property (nonatomic, strong) SLOwnedImage *thumbnail;
- (NSString *)displayTitle;
- (NSString *)displaySubtitle;
@end

// Layer 0 windows of regular apps, large enough to be real windows.
// A window is listed only when it is on screen or minimized.
// Agents, services, AutoFill, Siri, and background-activity UI are omitted.
// Each CGWindowID appears once. No images are read here.
NSArray<SLWindow *> *SLCollectWindows(void);
CGWindowID SLFrontmostWindowID(void);
