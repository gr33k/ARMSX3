#import "ARMSX3MetalView.h"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

@implementation ARMSX3MetalView

+ (Class)layerClass
{
    return CAMetalLayer.class;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
    {
        self.backgroundColor = UIColor.blackColor;
        self.opaque = YES;
        self.layer.cornerRadius = 12.0;
        self.layer.masksToBounds = YES;
        self.metalLayer.device = MTLCreateSystemDefaultDevice();
        self.metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        self.metalLayer.framebufferOnly = YES;
        self.metalLayer.contentsScale = UIScreen.mainScreen.nativeScale;
    }
    return self;
}

- (CAMetalLayer*)metalLayer
{
    return (CAMetalLayer*)self.layer;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    const CGFloat scale = self.window.screen.nativeScale ?: UIScreen.mainScreen.nativeScale;
    self.metalLayer.contentsScale = scale;
    self.metalLayer.drawableSize = CGSizeMake(
        floor(self.bounds.size.width * scale),
        floor(self.bounds.size.height * scale));
}

@end
