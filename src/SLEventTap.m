#define __ASSERT_MACROS_DEFINE_VERSIONS_WITHOUT_UNDERSCORES 0
#import "SLEventTap.h"

#include <math.h>
#define __ASSERT_MACROS_DEFINE_VERSIONS_WITHOUT_UNDERSCORES 0
#import <Carbon/Carbon.h>

@interface SLEventTap ()
- (CGEventRef)handleEvent:(CGEventRef)event type:(CGEventType)type;
@end

static NSString *SLTranslateKey(CGKeyCode key, BOOL shift) {
    TISInputSourceRef source = TISCopyCurrentKeyboardInputSource();
    if (!source) return nil;
    CFDataRef data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData);
    if (!data) {
        CFRelease(source);
        return nil;
    }
    const UCKeyboardLayout *layout = (const UCKeyboardLayout *)CFDataGetBytePtr(data);
    UInt32 modifiers = shift ? ((UInt32)shiftKey >> 8) : 0;
    UInt32 dead = 0;
    UniChar chars[8];
    UniCharCount length = 0;
    OSStatus status = UCKeyTranslate(layout, (UInt16)key, kUCKeyActionDown, modifiers,
                                     LMGetKbdType(), kUCKeyTranslateNoDeadKeysBit,
                                     &dead, 8, &length, chars);
    CFRelease(source);
    if (status != noErr || length == 0) return nil;
    return [NSString stringWithCharacters:chars length:length];
}

// Used when the active input source has no Unicode layout data (US ANSI keys).
static NSString *SLANSICharacter(CGKeyCode key, BOOL shift) {
    static const struct {
        unsigned short code;
        char lower;
        char upper;
    } map[] = {
        {0x00, 'a', 'A'}, {0x01, 's', 'S'}, {0x02, 'd', 'D'}, {0x03, 'f', 'F'},
        {0x04, 'h', 'H'}, {0x05, 'g', 'G'}, {0x06, 'z', 'Z'}, {0x07, 'x', 'X'},
        {0x08, 'c', 'C'}, {0x09, 'v', 'V'}, {0x0B, 'b', 'B'}, {0x0C, 'q', 'Q'},
        {0x0D, 'w', 'W'}, {0x0E, 'e', 'E'}, {0x0F, 'r', 'R'}, {0x10, 'y', 'Y'},
        {0x11, 't', 'T'}, {0x12, '1', '!'}, {0x13, '2', '@'}, {0x14, '3', '#'},
        {0x15, '4', '$'}, {0x16, '6', '^'}, {0x17, '5', '%'}, {0x19, '9', '('},
        {0x1A, '7', '&'}, {0x1C, '8', '*'}, {0x1D, '0', ')'}, {0x1F, 'o', 'O'},
        {0x20, 'u', 'U'}, {0x22, 'i', 'I'}, {0x23, 'p', 'P'}, {0x25, 'l', 'L'},
        {0x26, 'j', 'J'}, {0x28, 'k', 'K'}, {0x2D, 'n', 'N'}, {0x2E, 'm', 'M'},
        {0x31, ' ', ' '},
    };
    for (size_t i = 0; i < sizeof(map) / sizeof(map[0]); i++) {
        if (map[i].code == key) {
            char character = shift ? map[i].upper : map[i].lower;
            return [NSString stringWithFormat:@"%c", character];
        }
    }
    return nil;
}

static NSString *SLCharacterForKey(CGKeyCode key, BOOL shift) {
    NSString *translated = SLTranslateKey(key, shift);
    if (translated.length > 0) return translated;
    return SLANSICharacter(key, shift);
}

static BOOL SLIsTypingCharacter(NSString *text) {
    if (text.length == 0 || text.length > 4) return NO;
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar character = [text characterAtIndex:i];
        if (character == ' ') continue;
        if (character < 32 || character == 127) return NO;
        if ([letters characterIsMember:character] || [digits characterIsMember:character]) continue;
        return NO;
    }
    return YES;
}

static BOOL SLIsQKey(CGKeyCode key) {
    NSString *base = SLCharacterForKey(key, NO);
    if (base.length != 1) return NO;
    return [[base lowercaseString] characterAtIndex:0] == 'q';
}

// Quartz events are top-left of the menu-bar display. AppKit frames are bottom-left.
static NSPoint SLCocoaPoint(CGEventRef event) {
    CGPoint quartz = CGEventGetLocation(event);
    CGFloat height = NSHeight([NSScreen screens].firstObject.frame);
    return NSMakePoint(quartz.x, height - quartz.y);
}

static BOOL SLOptionIsPhysicallyDown(void) {
    CGEventFlags flags = CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState);
    return (flags & kCGEventFlagMaskAlternate) != 0;
}

static CGEventRef SLTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *userInfo) {
    (void)proxy;
    SLEventTap *tap = (__bridge SLEventTap *)userInfo;
    @autoreleasepool {
        return [tap handleEvent:event type:type];
    }
}

@implementation SLEventTap {
    CFMachPortRef _port;
    CFRunLoopSourceRef _source;
    BOOL _optionDown;
    BOOL _ateMouseDown;
    BOOL _loggedFailure;
}

- (CGEventRef)handleEvent:(CGEventRef)event type:(CGEventType)type {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (_port) CGEventTapEnable(_port, true);
        return event;
    }

    id<SLSwitchInput> handler = self.handler;
    if (!handler) return event;

    CGEventFlags flags = CGEventGetFlags(event);
    BOOL option = (flags & kCGEventFlagMaskAlternate) != 0;
    BOOL shift = (flags & kCGEventFlagMaskShift) != 0;
    BOOL command = (flags & kCGEventFlagMaskCommand) != 0;
    BOOL control = (flags & kCGEventFlagMaskControl) != 0;
    BOOL open = [handler switcherIsOpen];

    if (type == kCGEventFlagsChanged) {
        if (_optionDown && !option && open) [handler commit];
        _optionDown = option;
        return event;
    }
    _optionDown = option;

    if (type == kCGEventLeftMouseDown && open) {
        _ateMouseDown = YES;
        [handler clickAtScreenPoint:SLCocoaPoint(event)];
        return NULL;
    }
    if (type == kCGEventLeftMouseUp && (_ateMouseDown || open)) {
        _ateMouseDown = NO;
        return NULL;
    }
    if (type == kCGEventScrollWheel && open) {
        double delta = CGEventGetDoubleValueField(event, kCGScrollWheelEventPointDeltaAxis1);
        if (fabs(delta) < 0.01) {
            delta = CGEventGetDoubleValueField(event, kCGScrollWheelEventDeltaAxis1) * 48.0;
        }
        if ([handler handleScroll:delta atScreenPoint:SLCocoaPoint(event)]) return NULL;
        return event;
    }

    if (type != kCGEventKeyDown && type != kCGEventKeyUp) return event;

    CGKeyCode key = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    BOOL down = type == kCGEventKeyDown;
    BOOL repeat = CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat) != 0;
    BOOL tabOrGrave = key == kVK_Tab || key == kVK_ANSI_Grave;

    // Option-Shift-Q quits Switch Lite only while the panel is closed.
    if (!open && option && shift && !command && !control && SLIsQKey(key)) {
        if (down && !repeat) [handler quit];
        return NULL;
    }

    if (!open && option && !command && !control && tabOrGrave) {
        if (down) {
            BOOL forward = !shift;
            if (key == kVK_ANSI_Grave) [handler openFrontAppWindowsForward:forward];
            else [handler openAllWindowsForward:forward];
            // The Screen Recording prompt can block this callback, so the tap may miss
            // Option-up. Read the keyboard and confirm if Option is already up.
            _optionDown = SLOptionIsPhysicallyDown();
            if ([handler switcherIsOpen] && !_optionDown) [handler commit];
        }
        return NULL;
    }

    if (!open) return event;

    // Session is open: keep Tab, grave, Esc, arrows, and typing away from the front app.
    if (!down) return NULL;

    if (key == kVK_Escape) {
        [handler escape];
        return NULL;
    }
    if (key == kVK_Delete || key == kVK_ForwardDelete) {
        [handler backspace];
        return NULL;
    }
    if (tabOrGrave) {
        [handler cycleForward:!shift];
        return NULL;
    }
    if (key == kVK_LeftArrow) {
        [handler moveHorizontal:-1 vertical:0];
        return NULL;
    }
    if (key == kVK_RightArrow) {
        [handler moveHorizontal:1 vertical:0];
        return NULL;
    }
    if (key == kVK_UpArrow) {
        [handler moveHorizontal:0 vertical:-1];
        return NULL;
    }
    if (key == kVK_DownArrow) {
        [handler moveHorizontal:0 vertical:1];
        return NULL;
    }
    if (command || control) return NULL;

    NSString *base = SLCharacterForKey(key, NO);
    NSString *typed = SLCharacterForKey(key, shift);
    if (!shift && [handler switcherQueryIsEmpty] && base.length == 1) {
        unichar shortcut = [[base lowercaseString] characterAtIndex:0];
        if (shortcut == 'w' || shortcut == 'm' || shortcut == 'h' || shortcut == 'q') {
            [handler performShortcut:shortcut];
            return NULL;
        }
    }
    if (SLIsTypingCharacter(typed)) [handler insertText:typed];
    return NULL;
}

- (void)start {
    if (_port) return;
    CGEventMask mask =
        CGEventMaskBit(kCGEventKeyDown) |
        CGEventMaskBit(kCGEventKeyUp) |
        CGEventMaskBit(kCGEventFlagsChanged) |
        CGEventMaskBit(kCGEventLeftMouseDown) |
        CGEventMaskBit(kCGEventLeftMouseUp) |
        CGEventMaskBit(kCGEventScrollWheel);
    _port = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
                             mask, SLTapCallback, (__bridge void *)self);
    if (!_port) {
        if (!_loggedFailure) {
            NSLog(@"Switch Lite: event tap unavailable. Enable Accessibility for Switch Lite.");
            _loggedFailure = YES;
        }
        return;
    }
    _loggedFailure = NO;
    _source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _port, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
    CGEventTapEnable(_port, true);
}

- (void)ensureEnabled {
    if (!_port) {
        [self start];
        return;
    }
    if (!CGEventTapIsEnabled(_port)) CGEventTapEnable(_port, true);
}

- (void)stop {
    if (_port) CGEventTapEnable(_port, false);
    if (_source) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
        CFRelease(_source);
        _source = NULL;
    }
    if (_port) {
        CFMachPortInvalidate(_port);
        CFRelease(_port);
        _port = NULL;
    }
}

- (void)dealloc {
    [self stop];
}

@end
