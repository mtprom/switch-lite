#import <Cocoa/Cocoa.h>
#import "SLAppDelegate.h"

// The delegate property is weak. This keeps the process alive with no Dock icon.
static SLAppDelegate *gDelegate = nil;

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        gDelegate = [SLAppDelegate new];
        app.delegate = gDelegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [NSWindow setAllowsAutomaticWindowTabbing:NO];
        [app run];
    }
    return 0;
}
