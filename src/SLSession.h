#import <Foundation/Foundation.h>
#import "SLEventTap.h"
@class SLMRU;

@interface SLSession : NSObject <SLSwitchInput>
- (instancetype)initWithMRU:(SLMRU *)mru;
- (void)cancel;
@end
