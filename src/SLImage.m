#import "SLImage.h"

@implementation SLOwnedImage {
    CGImageRef _image;
}

+ (instancetype)imageWithCGImage:(CGImageRef)image {
    if (!image) return nil;
    SLOwnedImage *owned = [[SLOwnedImage alloc] init];
    owned->_image = CGImageRetain(image);
    return owned;
}

- (CGImageRef)image {
    return _image;
}

- (void)dealloc {
    if (_image) {
        CGImageRelease(_image);
        _image = NULL;
    }
}

@end
