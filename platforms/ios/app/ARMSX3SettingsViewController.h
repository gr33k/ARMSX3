#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSString* const ARMSX3ShowDebugLog;
FOUNDATION_EXPORT NSString* const ARMSX3ShowRuntimeOverlay;
FOUNDATION_EXPORT NSString* const ARMSX3ShowInputDiagnostics;
FOUNDATION_EXPORT NSString* const ARMSX3ShowTouchControls;
FOUNDATION_EXPORT NSString* const ARMSX3KeepScreenAwake;

@interface ARMSX3SettingsViewController : UITableViewController

@property(nonatomic, copy) void (^settingsChanged)(void);
@property(nonatomic, copy) void (^rebuildGraphicsCaches)(void);

+ (void)registerDefaults;

@end
