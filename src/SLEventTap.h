#import <Cocoa/Cocoa.h>

// Keyboard and click input for the switcher. Implemented by the session.
@protocol SLSwitchInput <NSObject>
- (BOOL)switcherIsOpen;
- (BOOL)switcherQueryIsEmpty;
- (void)openAllWindowsForward:(BOOL)forward;
- (void)openFrontAppWindowsForward:(BOOL)forward;
- (void)cycleForward:(BOOL)forward;
- (void)moveHorizontal:(NSInteger)dx vertical:(NSInteger)dy;
- (void)insertText:(NSString *)text;
- (void)backspace;
- (void)escape;
- (void)performShortcut:(unichar)key;
- (void)commit;
- (void)clickAtScreenPoint:(NSPoint)point;
- (BOOL)handleScroll:(CGFloat)deltaY atScreenPoint:(NSPoint)point;
- (void)quit;
@end

@interface SLEventTap : NSObject
@property (nonatomic, weak) id<SLSwitchInput> handler;
- (void)start;
- (void)stop;
- (void)ensureEnabled;
- (BOOL)isRunning;
@end
