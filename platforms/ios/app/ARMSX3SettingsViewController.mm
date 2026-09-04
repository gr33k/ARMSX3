#import "ARMSX3SettingsViewController.h"

NSString* const ARMSX3ShowDebugLog = @"ARMSX3ShowDebugLog";
NSString* const ARMSX3ShowRuntimeOverlay = @"ARMSX3ShowRuntimeOverlay";
NSString* const ARMSX3ShowInputDiagnostics = @"ARMSX3ShowInputDiagnostics";
NSString* const ARMSX3ShowTouchControls = @"ARMSX3ShowTouchControls";
NSString* const ARMSX3KeepScreenAwake = @"ARMSX3KeepScreenAwake";

@implementation ARMSX3SettingsViewController

+ (void)registerDefaults
{
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        ARMSX3ShowDebugLog: @NO,
        ARMSX3ShowRuntimeOverlay: @NO,
        ARMSX3ShowInputDiagnostics: @NO,
        ARMSX3ShowTouchControls: @YES,
        ARMSX3KeepScreenAwake: @YES,
    }];
}

- (instancetype)init
{
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Settings";
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.tableView.backgroundColor = [UIColor colorWithRed:0.018 green:0.027 blue:0.045 alpha:1];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeSettings)];
}

- (void)closeSettings
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSArray<NSArray<NSString*>*>*)rowsForSection:(NSInteger)section
{
    if (section == 0)
        return @[
            @[ARMSX3ShowTouchControls, @"Touch controls", @"Turn off for a connected controller. Landscape uses the full display; Menu stays accessible."],
            @[ARMSX3KeepScreenAwake, @"Keep screen awake", @"Prevent Auto-Lock during an active game. Restores normal behavior when leaving the app."],
        ];
    if (section == 1)
        return @[
            @[ARMSX3ShowRuntimeOverlay, @"Performance overlay", @"Show FPS, memory and session details in landscape."],
            @[ARMSX3ShowInputDiagnostics, @"Input diagnostics", @"Briefly show button and stick values in landscape."],
            @[ARMSX3ShowDebugLog, @"Debug log", @"Show the log below the library. Hiding it does not disable diagnostic recording."],
        ];
    return @[];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView
{
    return 3;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 2 ? 1 : [self rowsForSection:section].count;
}

- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section
{
    return @[@"Play", @"Diagnostics", @"Maintenance"][section];
}

- (NSString*)tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section
{
    if (section != 2)
        return nil;
    NSString* version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
    return [NSString stringWithFormat:@"ARMSX3 %@ · Pre-Alpha\nUses the accepted Vulkan/MoltenVK core. Native Metal gameplay remains under development. JIT and session safety checks remain active.", version];
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
    UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [UIColor colorWithRed:0.045 green:0.065 blue:0.095 alpha:1];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.textLabel.numberOfLines = 0;
    if (indexPath.section == 2)
    {
        cell.textLabel.text = @"Rebuild graphics caches";
        cell.detailTextLabel.text = @"Requires a stopped game. Preserves saves and installed game data; shaders compile again on next launch.";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    NSArray<NSString*>* row = [self rowsForSection:indexPath.section][indexPath.row];
    cell.textLabel.text = row[1];
    cell.detailTextLabel.text = row[2];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UISwitch* toggle = [[UISwitch alloc] init];
    toggle.on = [NSUserDefaults.standardUserDefaults boolForKey:row[0]];
    toggle.accessibilityIdentifier = row[0];
    toggle.accessibilityLabel = row[1];
    toggle.onTintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.66 alpha:1];
    [toggle addTarget:self action:@selector(settingChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    return cell;
}

- (void)settingChanged:(UISwitch*)sender
{
    [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:sender.accessibilityIdentifier];
    if (self.settingsChanged)
        self.settingsChanged();
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 2)
        [self dismissViewControllerAnimated:YES completion:self.rebuildGraphicsCaches];
}

@end
