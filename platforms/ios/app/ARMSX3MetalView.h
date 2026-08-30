#import <UIKit/UIKit.h>

@class CAMetalLayer;

@interface ARMSX3MetalView : UIView

@property(nonatomic, readonly) CAMetalLayer* metalLayer;

@end
