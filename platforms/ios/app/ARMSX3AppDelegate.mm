#import "ARMSX3AppDelegate.h"

#import "ARMSX3ViewController.h"

@implementation ARMSX3AppDelegate

- (ARMSX3ViewController*)rootViewController
{
    UIViewController* root = self.window.rootViewController;
    return [root isKindOfClass:ARMSX3ViewController.class]
        ? (ARMSX3ViewController*)root
        : nil;
}

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
    (void)application;
    (void)launchOptions;

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[ARMSX3ViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationWillResignActive:(UIApplication*)application
{
    (void)application;
    [self.rootViewController applicationWillResignActive];
}

- (void)applicationDidBecomeActive:(UIApplication*)application
{
    (void)application;
    [self.rootViewController applicationDidBecomeActive];
}

@end
