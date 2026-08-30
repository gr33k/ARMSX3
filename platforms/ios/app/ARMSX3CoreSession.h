#import <Foundation/Foundation.h>

@class CAMetalLayer;

typedef void (^ARMSX3CoreLogHandler)(NSString* line);
typedef void (^ARMSX3CoreProgressHandler)(double fraction, NSString* stage);
typedef void (^ARMSX3CoreCompletion)(BOOL succeeded, NSString* message);

@interface ARMSX3CoreSession : NSObject

@property(atomic, readonly, getter=isReady) BOOL ready;
@property(atomic, copy, readonly) NSArray<NSDictionary<NSString*, id>*>* games;

- (instancetype)initWithLogHandler:(ARMSX3CoreLogHandler)logHandler;
- (void)initializeWithCompletion:(ARMSX3CoreCompletion)completion;
- (void)updateDisplayLayer:(CAMetalLayer*)layer refreshRate:(float)refreshRate;
- (void)installURL:(NSURL*)url
       asFirmware:(BOOL)firmware
          progress:(ARMSX3CoreProgressHandler)progress
        completion:(ARMSX3CoreCompletion)completion;
- (void)refreshGamesWithCompletion:(ARMSX3CoreCompletion)completion;
- (void)runJITSelfTestWithCompletion:(ARMSX3CoreCompletion)completion;
- (void)bootXMBWithCompletion:(ARMSX3CoreCompletion)completion;
- (void)bootTitleID:(NSString*)titleID completion:(ARMSX3CoreCompletion)completion;
- (void)stopWithCompletion:(ARMSX3CoreCompletion)completion;
- (void)updatePadConnected:(BOOL)connected
                   buttons:(uint64_t)buttons
                     leftX:(float)leftX
                     leftY:(float)leftY
                    rightX:(float)rightX
                    rightY:(float)rightY
               leftTrigger:(float)leftTrigger
              rightTrigger:(float)rightTrigger;
- (NSString*)runtimeStatus;

@end
