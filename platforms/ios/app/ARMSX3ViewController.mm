#import "ARMSX3ViewController.h"

#import "ARMSX3CoreSession.h"
#import "ARMSX3MetalView.h"

#import <GameController/GameController.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "RPCS3IOS.h"

@interface ARMSX3ViewController () <UIDocumentPickerDelegate, UITableViewDataSource, UITableViewDelegate>

@property(nonatomic, strong) ARMSX3CoreSession* core;
@property(nonatomic, strong) ARMSX3MetalView* metalView;
@property(nonatomic, strong) UILabel* stateLabel;
@property(nonatomic, strong) UIProgressView* progressView;
@property(nonatomic, strong) UITableView* gameTable;
@property(nonatomic, strong) UITextView* logView;
@property(nonatomic, strong) NSTimer* statusTimer;
@property(nonatomic, copy) NSArray<NSDictionary<NSString*, id>*>* games;
@property(nonatomic) BOOL pickingFirmware;
@property(nonatomic) uint64_t touchButtons;
@property(nonatomic, strong) NSMutableArray<UIButton*>* touchControls;

@end

@implementation ARMSX3ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.018 green:0.027 blue:0.045 alpha:1.0];
    self.games = @[];
    self.touchControls = [NSMutableArray array];

    __weak ARMSX3ViewController* weak_self = self;
    self.core = [[ARMSX3CoreSession alloc] initWithLogHandler:^(NSString* line) {
        [weak_self appendLog:line];
    }];

    UIScrollView* scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.delaysContentTouches = NO;
    scroll.canCancelContentTouches = NO;
    [self.view addSubview:scroll];

    UIStackView* stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 9.0;
    [scroll addSubview:stack];

    UILabel* title = [[UILabel alloc] init];
    title.text = @"ARMSX3 iOS Core Test";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightBlack];
    [stack addArrangedSubview:title];

    self.stateLabel = [[UILabel alloc] init];
    self.stateLabel.text = @"Initializing real RPCS3 core...";
    self.stateLabel.numberOfLines = 2;
    self.stateLabel.textColor = [UIColor colorWithRed:0.98 green:0.72 blue:0.25 alpha:1.0];
    self.stateLabel.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightSemibold];
    [stack addArrangedSubview:self.stateLabel];

    self.metalView = [[ARMSX3MetalView alloc] initWithFrame:CGRectZero];
    self.metalView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.metalView.heightAnchor constraintEqualToAnchor:self.metalView.widthAnchor multiplier:9.0 / 16.0].active = YES;
    [stack addArrangedSubview:self.metalView];
    [self installTouchControls];

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.progressTintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.66 alpha:1.0];
    self.progressView.trackTintColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    [stack addArrangedSubview:self.progressView];

    UIStackView* first_row = [self buttonRow:@[
        [self button:@"Install Firmware" action:@selector(pickFirmware)],
        [self button:@"Import Game" action:@selector(pickGame)],
    ]];
    [stack addArrangedSubview:first_row];

    UIStackView* second_row = [self buttonRow:@[
        [self button:@"Refresh" action:@selector(refreshGames)],
        [self button:@"JIT Test" action:@selector(runJITTest)],
        [self button:@"Open XMB" action:@selector(openXMB)],
    ]];
    [stack addArrangedSubview:second_row];

    UIStackView* third_row = [self buttonRow:@[
        [self button:@"Stop Emulation" action:@selector(stopGame)],
    ]];
    [stack addArrangedSubview:third_row];

    UILabel* library_label = [[UILabel alloc] init];
    library_label.text = @"Installed titles (tap to boot)";
    library_label.textColor = [UIColor colorWithWhite:0.82 alpha:1.0];
    library_label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold];
    [stack addArrangedSubview:library_label];

    self.gameTable = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.gameTable.dataSource = self;
    self.gameTable.delegate = self;
    self.gameTable.rowHeight = 48.0;
    self.gameTable.backgroundColor = [UIColor colorWithRed:0.045 green:0.065 blue:0.095 alpha:1.0];
    self.gameTable.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    self.gameTable.layer.cornerRadius = 10.0;
    [self.gameTable.heightAnchor constraintEqualToConstant:150.0].active = YES;
    [stack addArrangedSubview:self.gameTable];

    self.logView = [[UITextView alloc] init];
    self.logView.editable = NO;
    self.logView.selectable = YES;
    self.logView.backgroundColor = [UIColor colorWithRed:0.035 green:0.050 blue:0.075 alpha:1.0];
    self.logView.textColor = [UIColor colorWithWhite:0.78 alpha:1.0];
    self.logView.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
    self.logView.layer.cornerRadius = 10.0;
    self.logView.textContainerInset = UIEdgeInsetsMake(10.0, 8.0, 10.0, 8.0);
    [self.logView.heightAnchor constraintEqualToConstant:150.0].active = YES;
    [stack addArrangedSubview:self.logView];

    UILayoutGuide* safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:12.0],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:12.0],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-12.0],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-16.0],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-24.0],
    ]];

    [self startControllerSupport];
    self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                       target:self
                                                     selector:@selector(updateRuntimeStatus)
                                                     userInfo:nil
                                                      repeats:YES];
    [self.core initializeWithCompletion:^(BOOL succeeded, NSString* message) {
        weak_self.stateLabel.text = message;
        weak_self.stateLabel.textColor = succeeded
            ? [UIColor colorWithRed:0.25 green:0.88 blue:0.68 alpha:1.0]
            : [UIColor colorWithRed:1.0 green:0.30 blue:0.28 alpha:1.0];
        [weak_self appendLog:message];
        if (succeeded)
        {
            [weak_self attachDisplay];
            [weak_self refreshGames];
        }
    }];
}

- (UIButton*)button:(NSString*)title action:(SEL)action
{
    UIButton* button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = [UIColor colorWithRed:0.10 green:0.32 blue:0.72 alpha:1.0];
    button.layer.cornerRadius = 9.0;
    button.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:42.0].active = YES;
    return button;
}

- (UIStackView*)buttonRow:(NSArray<UIButton*>*)buttons
{
    UIStackView* row = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8.0;
    row.distribution = UIStackViewDistributionFillEqually;
    return row;
}

- (void)appendLog:(NSString*)line
{
    if (!line.length)
        return;
    NSString* current = self.logView.text ?: @"";
    if (current.length > 24000)
        current = [current substringFromIndex:current.length - 18000];
    self.logView.text = [current stringByAppendingFormat:@"%@\n", line];
    [self.logView scrollRangeToVisible:NSMakeRange(self.logView.text.length, 0)];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self layoutTouchControls];
    [self attachDisplay];
}

- (void)attachDisplay
{
    if (!self.core.isReady || self.metalView.bounds.size.width < 1.0)
        return;
    const float refresh = (float)(self.view.window.screen.maximumFramesPerSecond ?: 60);
    [self.core updateDisplayLayer:self.metalView.metalLayer refreshRate:refresh];
}

- (void)pickFirmware
{
    self.pickingFirmware = YES;
    [self presentPickerWithTypes:@[UTTypeData]];
}

- (void)pickGame
{
    self.pickingFirmware = NO;
    [self presentPickerWithTypes:@[UTTypeData, UTTypeArchive, UTTypeFolder]];
}

- (void)presentPickerWithTypes:(NSArray<UTType*>*)types
{
    UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:types asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls
{
    (void)controller;
    NSURL* url = urls.firstObject;
    if (!url)
        return;
    self.stateLabel.text = [NSString stringWithFormat:@"Opening %@", url.lastPathComponent];
    self.progressView.progress = 0.0f;
    __weak ARMSX3ViewController* weak_self = self;
    [self.core installURL:url asFirmware:self.pickingFirmware progress:^(double fraction, NSString* stage) {
        weak_self.stateLabel.text = stage.length ? stage : @"Installing content";
        if (fraction >= 0.0)
        {
            weak_self.progressView.progress = (float)fraction;
            weak_self.progressView.hidden = NO;
        }
    } completion:^(BOOL succeeded, NSString* message) {
        weak_self.stateLabel.text = message;
        weak_self.stateLabel.textColor = succeeded
            ? [UIColor colorWithRed:0.25 green:0.88 blue:0.68 alpha:1.0]
            : [UIColor colorWithRed:1.0 green:0.30 blue:0.28 alpha:1.0];
        [weak_self appendLog:message];
        if (succeeded && !weak_self.pickingFirmware)
            [weak_self refreshGames];
    }];
}

- (void)refreshGames
{
    __weak ARMSX3ViewController* weak_self = self;
    [self.core refreshGamesWithCompletion:^(BOOL succeeded, NSString* message) {
        [weak_self appendLog:message];
        if (!succeeded)
            return;
        weak_self.games = weak_self.core.games;
        [weak_self.gameTable reloadData];
    }];
}

- (void)runJITTest
{
    __weak ARMSX3ViewController* weak_self = self;
    [self.core runJITSelfTestWithCompletion:^(BOOL succeeded, NSString* message) {
        weak_self.stateLabel.text = message;
        [weak_self appendLog:message];
    }];
}

- (void)openXMB
{
    self.stateLabel.text = @"Booting the PS3 XMB...";
    [self attachDisplay];
    __weak ARMSX3ViewController* weak_self = self;
    [self.core bootXMBWithCompletion:^(BOOL succeeded, NSString* message) {
        weak_self.stateLabel.text = message;
        [weak_self appendLog:message];
    }];
}

- (void)stopGame
{
    __weak ARMSX3ViewController* weak_self = self;
    self.stateLabel.text = @"Stopping emulation...";
    [self.core stopWithCompletion:^(BOOL succeeded, NSString* message) {
        weak_self.stateLabel.text = message;
        [weak_self appendLog:message];
    }];
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
    (void)tableView;
    (void)section;
    return self.games.count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
    static NSString* identifier = @"Game";
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    NSDictionary* game = self.games[(NSUInteger)indexPath.row];
    cell.textLabel.text = game[@"title"];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ | %@", game[@"titleID"], game[@"version"]];
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.62 alpha:1.0];
    cell.backgroundColor = UIColor.clearColor;
    return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary* game = self.games[(NSUInteger)indexPath.row];
    NSString* title_id = game[@"titleID"];
    self.stateLabel.text = [NSString stringWithFormat:@"Booting %@...", game[@"title"]];
    [self attachDisplay];
    __weak ARMSX3ViewController* weak_self = self;
    [self.core bootTitleID:title_id completion:^(BOOL succeeded, NSString* message) {
        weak_self.stateLabel.text = message;
        [weak_self appendLog:message];
    }];
}

- (void)updateRuntimeStatus
{
    if (self.core.isReady)
        self.stateLabel.text = [self.core runtimeStatus];
}

- (void)startControllerSupport
{
    NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(controllerConnected:) name:GCControllerDidConnectNotification object:nil];
    [center addObserver:self selector:@selector(controllerDisconnected:) name:GCControllerDidDisconnectNotification object:nil];
    for (GCController* controller in GCController.controllers)
        [self configureController:controller];
    [GCController startWirelessControllerDiscoveryWithCompletionHandler:nil];
}

- (void)controllerConnected:(NSNotification*)notification
{
    [self configureController:(GCController*)notification.object];
}

- (void)controllerDisconnected:(NSNotification*)notification
{
    (void)notification;
    [self.core updatePadConnected:NO buttons:0 leftX:0 leftY:0 rightX:0 rightY:0 leftTrigger:0 rightTrigger:0];
    [self appendLog:@"External controller disconnected; touch controls remain active"];
}

- (void)configureController:(GCController*)controller
{
    GCExtendedGamepad* pad = controller.extendedGamepad;
    if (!pad)
        return;
    [self appendLog:[NSString stringWithFormat:@"External controller: %@", controller.vendorName ?: @"MFi gamepad"]];
    __weak ARMSX3ViewController* weak_self = self;
    pad.valueChangedHandler = ^(GCExtendedGamepad* gamepad, GCControllerElement*) {
        uint64_t buttons = 0;
        if (gamepad.dpad.up.pressed) buttons |= RPCS3_IOS_PAD_BUTTON_DPAD_UP;
        if (gamepad.dpad.down.pressed) buttons |= RPCS3_IOS_PAD_BUTTON_DPAD_DOWN;
        if (gamepad.dpad.left.pressed) buttons |= RPCS3_IOS_PAD_BUTTON_DPAD_LEFT;
        if (gamepad.dpad.right.pressed) buttons |= RPCS3_IOS_PAD_BUTTON_DPAD_RIGHT;
        if (gamepad.buttonA.pressed) buttons |= RPCS3_IOS_PAD_BUTTON_CROSS;
        if (gamepad.buttonB.pressed) buttons |= RPCS3_IOS_PAD_BUTTON_CIRCLE;
        if (gamepad.buttonX.pressed) buttons |= RPCS3_IOS_PAD_BUTTON_SQUARE;
        if (gamepad.buttonY.pressed) buttons |= RPCS3_IOS_PAD_BUTTON_TRIANGLE;
        if (gamepad.leftShoulder.pressed) buttons |= RPCS3_IOS_PAD_BUTTON_L1;
        if (gamepad.rightShoulder.pressed) buttons |= RPCS3_IOS_PAD_BUTTON_R1;
        if (gamepad.leftTrigger.pressed) buttons |= RPCS3_IOS_PAD_BUTTON_L2;
        if (gamepad.rightTrigger.pressed) buttons |= RPCS3_IOS_PAD_BUTTON_R2;
        if (gamepad.leftThumbstickButton.pressed) buttons |= RPCS3_IOS_PAD_BUTTON_L3;
        if (gamepad.rightThumbstickButton.pressed) buttons |= RPCS3_IOS_PAD_BUTTON_R3;
        if (gamepad.buttonMenu.pressed) buttons |= RPCS3_IOS_PAD_BUTTON_START;
        if (gamepad.buttonOptions.pressed) buttons |= RPCS3_IOS_PAD_BUTTON_SELECT;
        [weak_self.core updatePadConnected:YES buttons:buttons
            leftX:gamepad.leftThumbstick.xAxis.value leftY:gamepad.leftThumbstick.yAxis.value
            rightX:gamepad.rightThumbstick.xAxis.value rightY:gamepad.rightThumbstick.yAxis.value
            leftTrigger:gamepad.leftTrigger.value rightTrigger:gamepad.rightTrigger.value];
    };
}

- (void)installTouchControls
{
    NSArray<NSDictionary*>* controls = @[
        @{ @"title": @"U", @"bit": @(RPCS3_IOS_PAD_BUTTON_DPAD_UP) },
        @{ @"title": @"D", @"bit": @(RPCS3_IOS_PAD_BUTTON_DPAD_DOWN) },
        @{ @"title": @"L", @"bit": @(RPCS3_IOS_PAD_BUTTON_DPAD_LEFT) },
        @{ @"title": @"R", @"bit": @(RPCS3_IOS_PAD_BUTTON_DPAD_RIGHT) },
        @{ @"title": @"T", @"bit": @(RPCS3_IOS_PAD_BUTTON_TRIANGLE) },
        @{ @"title": @"X", @"bit": @(RPCS3_IOS_PAD_BUTTON_CROSS) },
        @{ @"title": @"S", @"bit": @(RPCS3_IOS_PAD_BUTTON_SQUARE) },
        @{ @"title": @"O", @"bit": @(RPCS3_IOS_PAD_BUTTON_CIRCLE) },
        @{ @"title": @"SEL", @"bit": @(RPCS3_IOS_PAD_BUTTON_SELECT) },
        @{ @"title": @"START", @"bit": @(RPCS3_IOS_PAD_BUTTON_START) },
    ];
    for (NSDictionary* spec in controls)
    {
        UIButton* button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = [spec[@"bit"] unsignedLongLongValue];
        button.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.78];
        button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.58].CGColor;
        button.layer.borderWidth = 1.0;
        button.layer.cornerRadius = 18.0;
        button.multipleTouchEnabled = YES;
        button.exclusiveTouch = NO;
        button.titleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightBlack];
        [button setTitle:spec[@"title"] forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [button addTarget:self action:@selector(touchDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
        [button addTarget:self action:@selector(touchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
        [self.metalView addSubview:button];
        [self.touchControls addObject:button];
    }
}

- (void)layoutTouchControls
{
    if (self.touchControls.count != 10)
        return;
    const CGFloat width = self.metalView.bounds.size.width;
    const CGFloat height = self.metalView.bounds.size.height;
    if (width < 1.0 || height < 1.0)
        return;
    const CGFloat size = MIN(54.0, MAX(44.0, height * 0.24));
    const CGFloat left_x = MAX(width * 0.15, size * 1.45);
    const CGFloat right_x = MIN(width * 0.85, width - size * 1.45);
    const CGFloat center_y = MIN(height - size * 1.45, MAX(size * 1.45, height * 0.62));
    NSArray<NSValue*>* centers = @[
        [NSValue valueWithCGPoint:CGPointMake(left_x, center_y - size * 0.90)],
        [NSValue valueWithCGPoint:CGPointMake(left_x, center_y + size * 0.90)],
        [NSValue valueWithCGPoint:CGPointMake(left_x - size * 0.90, center_y)],
        [NSValue valueWithCGPoint:CGPointMake(left_x + size * 0.90, center_y)],
        [NSValue valueWithCGPoint:CGPointMake(right_x, center_y - size * 0.90)],
        [NSValue valueWithCGPoint:CGPointMake(right_x, center_y + size * 0.90)],
        [NSValue valueWithCGPoint:CGPointMake(right_x - size * 0.90, center_y)],
        [NSValue valueWithCGPoint:CGPointMake(right_x + size * 0.90, center_y)],
        [NSValue valueWithCGPoint:CGPointMake(width * 0.45, height - size * 0.55)],
        [NSValue valueWithCGPoint:CGPointMake(width * 0.57, height - size * 0.55)],
    ];
    [self.touchControls enumerateObjectsUsingBlock:^(UIButton* button, NSUInteger index, BOOL*) {
        const CGFloat button_width = index >= 8 ? size * 1.45 : size;
        button.bounds = CGRectMake(0, 0, button_width, size);
        button.center = centers[index].CGPointValue;
        button.layer.cornerRadius = size * 0.50;
    }];
}

- (void)touchDown:(UIButton*)sender
{
    self.touchButtons |= (uint64_t)sender.tag;
    sender.transform = CGAffineTransformMakeScale(0.90, 0.90);
    [self pushTouchPad];
}

- (void)touchUp:(UIButton*)sender
{
    self.touchButtons &= ~((uint64_t)sender.tag);
    sender.transform = CGAffineTransformIdentity;
    [self pushTouchPad];
}

- (void)pushTouchPad
{
    [self.core updatePadConnected:YES buttons:self.touchButtons
        leftX:0 leftY:0 rightX:0 rightY:0 leftTrigger:0 rightTrigger:0];
}

- (void)dealloc
{
    [self.statusTimer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

@end
