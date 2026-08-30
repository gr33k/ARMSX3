#import <Foundation/Foundation.h>

typedef void (^ARMSX3ProbeUpdate)(NSString* line);
typedef void (^ARMSX3ProbeCompletion)(BOOL passed);

@interface ARMSX3FeasibilityProbe : NSObject

+ (void)runWithUpdate:(ARMSX3ProbeUpdate)update completion:(ARMSX3ProbeCompletion)completion;

@end
