#import "ARMSX3AppDelegate.h"

#import "ARMSX3ViewController.h"

@implementation ARMSX3AppDelegate

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
    (void)application;
    (void)launchOptions;

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[ARMSX3ViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
