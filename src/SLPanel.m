#import "SLPanel.h"
#import "SLIconCache.h"
#import "SLImage.h"
#import "SLWindow.h"

#include <math.h>

// Frames are set in code. Do not add constraints.
static const CGFloat SLOuterPad = 16;
static const CGFloat SLCellGap = 12;
static const CGFloat SLThumbW = 200;
static const CGFloat SLThumbH = 124;
static const CGFloat SLCellPadX = 8;
static const CGFloat SLCellPadTop = 8;
static const CGFloat SLTitleH = 16;
static const CGFloat SLAppH = 14;
static const CGFloat SLCellW = 216;
static const CGFloat SLCellH = 178;
static const CGFloat SLCorner = 16;
static const NSInteger SLMaxCols = 5;

static NSInteger SLColumnCount(CGFloat maxInner, NSInteger count) {
    if (count < 1) count = 1;
    CGFloat unit = SLCellW + SLCellGap;
    NSInteger fit = (NSInteger)floor((maxInner + SLCellGap) / unit);
    if (fit < 1) fit = 1;
    if (fit > SLMaxCols) fit = SLMaxCols;
    if (fit > count) fit = count;
    return fit;
}

static NSInteger SLRowCount(NSInteger count, NSInteger cols) {
    if (cols < 1) cols = 1;
    if (count < 1) return 1;
    return (count + cols - 1) / cols;
}

static CGFloat SLGridWidth(NSInteger cols) {
    if (cols < 1) cols = 1;
    return cols * SLCellW + (cols - 1) * SLCellGap;
}

static CGFloat SLGridHeight(NSInteger rows) {
    if (rows < 1) rows = 1;
    return rows * SLCellH + (rows - 1) * SLCellGap;
}

static NSRect SLCellRect(NSInteger index, NSInteger cols, CGFloat containerH) {
    if (cols < 1) cols = 1;
    NSInteger row = index / cols;
    NSInteger col = index % cols;
    CGFloat x = col * (SLCellW + SLCellGap);
    CGFloat y = containerH - SLCellH - row * (SLCellH + SLCellGap);
    return NSMakeRect(x, y, SLCellW, SLCellH);
}

static NSRect SLThumbRect(NSRect cell) {
    return NSMakeRect(NSMinX(cell) + SLCellPadX,
                      NSMaxY(cell) - SLCellPadTop - SLThumbH,
                      SLThumbW,
                      SLThumbH);
}

static NSRect SLTitleRect(NSRect cell) {
    NSRect thumb = SLThumbRect(cell);
    return NSMakeRect(NSMinX(thumb), NSMinY(thumb) - 6 - SLTitleH, SLThumbW, SLTitleH);
}

static NSRect SLSubtitleRect(NSRect cell) {
    NSRect title = SLTitleRect(cell);
    return NSMakeRect(NSMinX(title), NSMinY(title) - 2 - SLAppH, SLThumbW, SLAppH);
}

static NSRect SLAspectFit(CGFloat imageW, CGFloat imageH, NSRect box) {
    if (imageW < 1 || imageH < 1) return box;
    CGFloat scale = MIN(NSWidth(box) / imageW, NSHeight(box) / imageH);
    CGFloat width = imageW * scale;
    CGFloat height = imageH * scale;
    return NSMakeRect(NSMidX(box) - width / 2, NSMidY(box) - height / 2, width, height);
}

static void SLDrawImage(CGImageRef image, NSRect dest) {
    if (!image) return;
    CGContextRef context = [[NSGraphicsContext currentContext] CGContext];
    if (!context) return;
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, dest.origin.x, dest.origin.y + dest.size.height);
    CGContextScaleCTM(context, 1, -1);
    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    CGContextDrawImage(context, CGRectMake(0, 0, dest.size.width, dest.size.height), image);
    CGContextRestoreGState(context);
}

static NSScreen *SLScreenUnderMouse(void) {
    NSPoint mouse = [NSEvent mouseLocation];
    for (NSScreen *screen in [NSScreen screens]) {
        if (NSPointInRect(mouse, screen.frame)) return screen;
    }
    return [NSScreen mainScreen] ?: [NSScreen screens].firstObject;
}

@interface SLPanelWindow : NSPanel
@end

@implementation SLPanelWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface SLQueryView : NSView
@property (nonatomic, copy) NSString *text;
@end

@implementation SLQueryView
- (BOOL)isOpaque { return NO; }
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    if (self.text.length == 0) return;
    NSRect pill = NSInsetRect(self.bounds, 0, 2);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:pill xRadius:8 yRadius:8];
    [[NSColor colorWithWhite:0 alpha:0.18] setFill];
    [path fill];

    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13],
        NSForegroundColorAttributeName: [NSColor labelColor],
        NSParagraphStyleAttributeName: style,
    };
    NSRect text = NSInsetRect(pill, 10, 0);
    text.origin.y = NSMidY(pill) - 8;
    text.size.height = 16;
    [self.text drawInRect:text withAttributes:attributes];
}
@end

@interface SLKnobView : NSView
@end

@implementation SLKnobView
- (BOOL)isOpaque { return NO; }
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor colorWithWhite:1 alpha:0.55] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:2 yRadius:2] fill];
}
@end

@interface SLGridView : NSView
@property (nonatomic, copy) NSArray<SLWindow *> *windows;
@property (nonatomic) NSInteger selectedIndex;
@property (nonatomic) NSInteger columns;
@property (nonatomic, weak) SLIconCache *iconCache;
- (NSRect)rectForIndex:(NSInteger)index;
- (NSInteger)indexAtPoint:(NSPoint)point;
@end

@implementation SLGridView

- (BOOL)isOpaque { return NO; }

- (NSRect)rectForIndex:(NSInteger)index {
    NSInteger cols = self.columns > 0 ? self.columns : 1;
    return SLCellRect(index, cols, NSHeight(self.bounds));
}

- (NSInteger)indexAtPoint:(NSPoint)point {
    NSInteger count = (NSInteger)self.windows.count;
    for (NSInteger i = 0; i < count; i++) {
        if (NSPointInRect(point, [self rectForIndex:i])) return i;
    }
    return NSNotFound;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    if (self.windows.count == 0) {
        NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
        style.alignment = NSTextAlignmentCenter;
        NSDictionary *attributes = @{
            NSFontAttributeName: [NSFont systemFontOfSize:13],
            NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
            NSParagraphStyleAttributeName: style,
        };
        NSRect line = self.bounds;
        line.origin.y = NSMidY(self.bounds) - 9;
        line.size.height = 18;
        [@"No matching windows" drawInRect:line withAttributes:attributes];
        return;
    }

    NSMutableParagraphStyle *truncating = [NSMutableParagraphStyle new];
    truncating.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *titleAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor labelColor],
        NSParagraphStyleAttributeName: truncating,
    };
    NSDictionary *ownerAttributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor],
        NSParagraphStyleAttributeName: truncating,
    };

    NSInteger index = 0;
    for (SLWindow *window in self.windows) {
        NSRect cell = [self rectForIndex:index];
        BOOL selected = index == self.selectedIndex;
        NSRect ring = NSInsetRect(cell, 2, 2);
        NSBezierPath *ringPath = [NSBezierPath bezierPathWithRoundedRect:ring xRadius:10 yRadius:10];
        if (selected) {
            [[NSColor.controlAccentColor colorWithAlphaComponent:0.20] setFill];
            [ringPath fill];
        }

        NSRect thumb = SLThumbRect(cell);
        NSBezierPath *well = [NSBezierPath bezierPathWithRoundedRect:thumb xRadius:6 yRadius:6];
        [[NSColor colorWithWhite:0 alpha:0.28] setFill];
        [well fill];

        CGImageRef thumbnail = window.thumbnail.image;
        [NSGraphicsContext saveGraphicsState];
        [well addClip];
        if (thumbnail) {
            NSRect fitted = SLAspectFit((CGFloat)CGImageGetWidth(thumbnail),
                                        (CGFloat)CGImageGetHeight(thumbnail),
                                        thumb);
            SLDrawImage(thumbnail, fitted);
        } else {
            CGImageRef icon = [self.iconCache imageForKey:window.iconKey];
            if (icon) {
                NSRect iconRect = NSMakeRect(NSMidX(thumb) - 16, NSMidY(thumb) - 16, 32, 32);
                SLDrawImage(icon, iconRect);
            }
        }
        [NSGraphicsContext restoreGraphicsState];

        [window.displayTitle drawInRect:SLTitleRect(cell) withAttributes:titleAttributes];
        NSString *subtitle = window.displaySubtitle;
        if (subtitle.length > 0) {
            [subtitle drawInRect:SLSubtitleRect(cell) withAttributes:ownerAttributes];
        }

        if (selected) {
            [NSColor.controlAccentColor setStroke];
            ringPath.lineWidth = 3;
        } else {
            [[NSColor.separatorColor colorWithAlphaComponent:0.85] setStroke];
            ringPath.lineWidth = 1;
        }
        [ringPath stroke];
        index += 1;
    }
}

@end

@implementation SLPanel {
    SLIconCache *_icons;
    SLPanelWindow *_window;
    NSVisualEffectView *_effect;
    SLQueryView *_queryView;
    NSScrollView *_scroll;
    SLGridView *_grid;
    SLKnobView *_knob;
    NSArray<SLWindow *> *_windows;
    NSInteger _selected;
    NSString *_query;
    NSInteger _columns;
    NSScreen *_screen;
    BOOL _visible;
}

- (instancetype)initWithIconCache:(SLIconCache *)icons {
    self = [super init];
    if (self) {
        _icons = icons;
        _windows = @[];
        _query = @"";
        _selected = -1;
    }
    return self;
}

- (BOOL)isVisible {
    return _visible;
}

- (NSInteger)columnCount {
    return _columns > 0 ? _columns : 1;
}

- (void)ensureViews {
    if (!_window) {
        _window = [[SLPanelWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 320)
                                                   styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
        _window.releasedWhenClosed = NO;
        _window.opaque = NO;
        _window.backgroundColor = [NSColor clearColor];
        _window.hasShadow = YES;
        _window.level = NSPopUpMenuWindowLevel;
        _window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
            | NSWindowCollectionBehaviorFullScreenAuxiliary
            | NSWindowCollectionBehaviorIgnoresCycle;
        _window.hidesOnDeactivate = NO;
        _window.animationBehavior = NSWindowAnimationBehaviorNone;
        _window.sharingType = NSWindowSharingNone;
        _window.movable = NO;
        _window.worksWhenModal = YES;
        _window.becomesKeyOnlyIfNeeded = YES;
    }
    if (_effect) return;

    _effect = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 480, 320)];
    _effect.material = NSVisualEffectMaterialMenu;
    _effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _effect.state = NSVisualEffectStateActive;
    _effect.wantsLayer = YES;
    _effect.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _window.contentView = _effect;

    _queryView = [SLQueryView new];
    _queryView.autoresizingMask = NSViewNotSizable;

    _scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _scroll.drawsBackground = NO;
    _scroll.backgroundColor = [NSColor clearColor];
    _scroll.borderType = NSNoBorder;
    _scroll.hasVerticalScroller = NO;
    _scroll.hasHorizontalScroller = NO;
    _scroll.automaticallyAdjustsContentInsets = NO;
    _scroll.contentInsets = NSEdgeInsetsZero;
    _scroll.verticalScrollElasticity = NSScrollElasticityNone;
    _scroll.horizontalScrollElasticity = NSScrollElasticityNone;
    _scroll.autoresizingMask = NSViewNotSizable;
    if (_scroll.contentView) _scroll.contentView.drawsBackground = NO;

    _grid = [SLGridView new];
    _grid.wantsLayer = NO;
    _grid.iconCache = _icons;
    _grid.autoresizingMask = NSViewNotSizable;
    _scroll.documentView = _grid;

    _knob = [SLKnobView new];
    _knob.hidden = YES;
    [_effect addSubview:_queryView];
    [_effect addSubview:_scroll];
    [_effect addSubview:_knob];
}

- (void)clearLayerContents:(NSView *)view {
    if (!view) return;
    if (view.wantsLayer && view.layer) view.layer.contents = nil;
    for (NSView *subview in view.subviews) [self clearLayerContents:subview];
}

- (void)pinToTop {
    NSClipView *clip = _scroll.contentView;
    CGFloat visibleH = NSHeight(clip.bounds);
    if (visibleH < 1) visibleH = NSHeight(_scroll.frame);
    CGFloat maxY = MAX(0, NSHeight(_grid.frame) - visibleH);
    [clip scrollToPoint:NSMakePoint(0, maxY)];
    [_scroll reflectScrolledClipView:clip];
}

- (void)updateKnob {
    if (!_knob || !_scroll || !_grid) return;
    NSClipView *clip = _scroll.contentView;
    CGFloat docH = NSHeight(_grid.frame);
    CGFloat visH = NSHeight(clip.bounds);
    if (visH < 1) visH = NSHeight(_scroll.frame);
    if (docH <= visH + 1 || visH < 1) {
        _knob.hidden = YES;
        return;
    }
    NSRect track = NSMakeRect(NSMaxX(_scroll.frame) + 6, NSMinY(_scroll.frame), 4, NSHeight(_scroll.frame));
    track = NSInsetRect(track, 0, 8);
    CGFloat knobH = MAX(28.0, NSHeight(track) * (visH / docH));
    if (knobH > NSHeight(track)) knobH = NSHeight(track);
    CGFloat maxOrigin = MAX(1, docH - visH);
    CGFloat progress = clip.bounds.origin.y / maxOrigin;
    if (progress < 0) progress = 0;
    if (progress > 1) progress = 1;
    CGFloat knobY = NSMinY(track) + (NSHeight(track) - knobH) * progress;
    _knob.hidden = NO;
    _knob.frame = NSMakeRect(NSMinX(track), knobY, 4, knobH);
}

- (void)scrollSelectionIntoView {
    if (_selected < 0 || _selected >= (NSInteger)_grid.windows.count) {
        [self updateKnob];
        return;
    }
    NSRect rect = NSInsetRect([_grid rectForIndex:_selected], -4, -8);
    NSClipView *clip = _scroll.contentView;
    NSRect visible = clip.bounds;
    if (!NSContainsRect(visible, [_grid rectForIndex:_selected])) {
        if (NSMinY(rect) < NSMinY(visible)) visible.origin.y = NSMinY(rect);
        else if (NSMaxY(rect) > NSMaxY(visible)) visible.origin.y = NSMaxY(rect) - NSHeight(visible);
        CGFloat maxY = MAX(0, NSHeight(_grid.frame) - NSHeight(visible));
        if (visible.origin.y < 0) visible.origin.y = 0;
        if (visible.origin.y > maxY) visible.origin.y = maxY;
        [clip scrollToPoint:visible.origin];
        [_scroll reflectScrolledClipView:clip];
    }
    [self updateKnob];
}

- (void)layoutContents {
    NSRect visibleFrame = _screen.visibleFrame;
    NSInteger count = (NSInteger)_windows.count;
    CGFloat maxPanelW = MIN(NSWidth(visibleFrame) - 24.0, 1080.0);
    CGFloat maxInner = MAX(SLCellW, maxPanelW - 2.0 * SLOuterPad);
    NSInteger cols = SLColumnCount(maxInner, MAX(count, (NSInteger)1));
    NSInteger rows = SLRowCount(MAX(count, (NSInteger)1), cols);
    CGFloat gridW = SLGridWidth(cols);
    CGFloat contentH = SLGridHeight(rows);
    BOOL hasQuery = _query.length > 0;
    CGFloat queryH = hasQuery ? 28.0 : 0.0;
    CGFloat queryGap = hasQuery ? 10.0 : 0.0;
    CGFloat maxPanelH = MIN(NSHeight(visibleFrame) - 24.0, 780.0);
    CGFloat chrome = 2.0 * SLOuterPad + queryH + queryGap;
    CGFloat scrollH = contentH;
    if (chrome + scrollH > maxPanelH) scrollH = MAX(SLCellH, maxPanelH - chrome);
    CGFloat panelW = gridW + 2.0 * SLOuterPad;
    CGFloat panelH = chrome + scrollH;

    NSRect frame = NSMakeRect(0, 0, panelW, panelH);
    frame.origin.x = floor(NSMidX(visibleFrame) - panelW / 2.0);
    frame.origin.y = floor(NSMidY(visibleFrame) - panelH / 2.0);
    if (NSMaxX(frame) > NSMaxX(visibleFrame)) frame.origin.x = NSMaxX(visibleFrame) - panelW;
    if (NSMinX(frame) < NSMinX(visibleFrame)) frame.origin.x = NSMinX(visibleFrame);
    if (NSMaxY(frame) > NSMaxY(visibleFrame)) frame.origin.y = NSMaxY(visibleFrame) - panelH;
    if (NSMinY(frame) < NSMinY(visibleFrame)) frame.origin.y = NSMinY(visibleFrame);

    [_window setFrame:frame display:NO];
    _effect.frame = NSMakeRect(0, 0, panelW, panelH);
    _effect.layer.cornerRadius = SLCorner;
    _effect.layer.masksToBounds = YES;
    _effect.layer.borderWidth = 1;
    _effect.layer.borderColor = [[NSColor colorWithWhite:1 alpha:0.16] CGColor];

    _scroll.frame = NSMakeRect(SLOuterPad, SLOuterPad, gridW, scrollH);
    if (hasQuery) {
        _queryView.hidden = NO;
        _queryView.frame = NSMakeRect(SLOuterPad, NSMaxY(_scroll.frame) + queryGap, gridW, queryH);
    } else {
        _queryView.hidden = YES;
    }

    _columns = cols;
    _grid.columns = cols;
    _grid.frame = NSMakeRect(0, 0, gridW, contentH);
    [self pinToTop];
    [self scrollSelectionIntoView];
}

- (void)presentWindows:(NSArray<SLWindow *> *)windows
              selected:(NSInteger)selected
                 query:(NSString *)query {
    [self ensureViews];
    if (!_visible || !_screen) _screen = SLScreenUnderMouse();
    if (!_screen) return;

    NSString *nextQuery = query ?: @"";
    BOOL relayout = !_visible || ![windows isEqualToArray:_windows] || ![nextQuery isEqualToString:_query ?: @""];
    _windows = [windows copy] ?: @[];
    _selected = selected;
    _query = [nextQuery copy];
    _grid.iconCache = _icons;
    _grid.windows = _windows;
    _grid.selectedIndex = _selected;
    _queryView.text = _query.length ? [NSString stringWithFormat:@"Search: %@", _query] : @"";
    [_queryView setNeedsDisplay:YES];

    if (relayout) [self layoutContents];
    else {
        [_grid setNeedsDisplay:YES];
        [self scrollSelectionIntoView];
    }
    if (!_visible) {
        [_window orderFrontRegardless];
        _visible = YES;
    }
    [_window display];
}

- (void)noteThumbnailForWindow:(SLWindow *)window {
    if (!_visible || !window || window.retired || !_grid) return;
    NSUInteger index = [_windows indexOfObject:window];
    if (index == NSNotFound) return;
    NSRect rect = [_grid rectForIndex:(NSInteger)index];
    [_grid setNeedsDisplayInRect:NSInsetRect(rect, -4, -4)];
    [_grid displayIfNeeded];
}

- (NSInteger)cellIndexAtScreenPoint:(NSPoint)point outside:(BOOL *)outside {
    if (outside) *outside = NO;
    if (!_visible || !_window) {
        if (outside) *outside = YES;
        return NSNotFound;
    }
    if (!NSPointInRect(point, _window.frame)) {
        if (outside) *outside = YES;
        return NSNotFound;
    }
    if (!_grid) return NSNotFound;
    NSPoint windowPoint = [_window convertRectFromScreen:NSMakeRect(point.x, point.y, 0, 0)].origin;
    NSPoint gridPoint = [_grid convertPoint:windowPoint fromView:nil];
    return [_grid indexAtPoint:gridPoint];
}

- (BOOL)scrollBy:(CGFloat)deltaY atScreenPoint:(NSPoint)point {
    if (!_visible || !_window || !NSPointInRect(point, _window.frame)) return NO;
    NSClipView *clip = _scroll.contentView;
    NSPoint origin = clip.bounds.origin;
    origin.y += deltaY;
    CGFloat visH = NSHeight(clip.bounds);
    CGFloat maxY = MAX(0, NSHeight(_grid.frame) - visH);
    if (origin.y < 0) origin.y = 0;
    if (origin.y > maxY) origin.y = maxY;
    [clip scrollToPoint:origin];
    [_scroll reflectScrolledClipView:clip];
    [self updateKnob];
    return YES;
}

- (void)hide {
    _windows = @[];
    if (_grid) {
        _grid.windows = @[];
        _grid.selectedIndex = -1;
    }
    [_window orderOut:nil];
    // Drop the panel backing store that held the composited thumbnails.
    [_window setFrame:NSMakeRect(0, 0, 1, 1) display:NO];
    [self clearLayerContents:_effect];
    if (_window) _window.contentView = [[NSView alloc] initWithFrame:NSZeroRect];
    _grid = nil;
    _scroll = nil;
    _queryView = nil;
    _knob = nil;
    _effect = nil;
    _visible = NO;
    _screen = nil;
    _query = @"";
    _selected = -1;
    _columns = 0;
}

@end
