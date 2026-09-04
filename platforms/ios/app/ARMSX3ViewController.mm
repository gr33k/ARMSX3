#import "ARMSX3ViewController.h"

#import "ARMSX3CoreSession.h"
#import "ARMSX3MetalView.h"
#import "ARMSX3SettingsViewController.h"

#import <GameController/GameController.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "RPCS3IOS.h"
#include <cmath>

typedef void (^ARMSX3StickHandler)(float x, float y);

@interface ARMSX3ArtworkButton : UIButton

@property(nonatomic) BOOL circularHitArea;

@end


@implementation ARMSX3ArtworkButton

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent*)event
{
    if (![super pointInside:point withEvent:event])
        return NO;
    if (self.circularHitArea)
    {
        const CGFloat radius_x = MAX(1.0, self.bounds.size.width * 0.5);
        const CGFloat radius_y = MAX(1.0, self.bounds.size.height * 0.5);
        const CGFloat x = (point.x - CGRectGetMidX(self.bounds)) / radius_x;
        const CGFloat y = (point.y - CGRectGetMidY(self.bounds)) / radius_y;
        return x * x + y * y <= 1.0;
    }
    UIBezierPath* path = [UIBezierPath bezierPathWithRoundedRect:self.bounds
        cornerRadius:self.layer.cornerRadius];
    return [path containsPoint:point];
}

@end


@interface ARMSX3DPadSectorButton : UIButton

@property(nonatomic) CGFloat directionAngle;

@end


@implementation ARMSX3DPadSectorButton

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent*)event
{
    if (![super pointInside:point withEvent:event])
        return NO;

    const CGFloat radius_x = MAX(1.0, self.bounds.size.width * 0.5);
    const CGFloat radius_y = MAX(1.0, self.bounds.size.height * 0.5);
    const CGFloat x = (point.x - CGRectGetMidX(self.bounds)) / radius_x;
    const CGFloat y = (point.y - CGRectGetMidY(self.bounds)) / radius_y;
    const CGFloat radius = hypot(x, y);
    if (radius < 0.18 || radius > 1.0)
        return NO;

    const CGFloat angle = atan2(y, x);
    const CGFloat delta = atan2(sin(angle - self.directionAngle), cos(angle - self.directionAngle));
    return fabs(delta) <= M_PI_4 * 0.5 + 0.001;
}

@end


@interface ARMSX3VirtualStick : UIView

@property(nonatomic, copy) ARMSX3StickHandler valueHandler;

@end


@implementation ARMSX3VirtualStick
{
    UIView* _touchIndicator;
    __weak UITouch* _trackingTouch;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent*)event
{
    if (![super pointInside:point withEvent:event])
        return NO;
    const CGFloat radius_x = MAX(1.0, self.bounds.size.width * 0.5);
    const CGFloat radius_y = MAX(1.0, self.bounds.size.height * 0.5);
    const CGFloat x = (point.x - CGRectGetMidX(self.bounds)) / radius_x;
    const CGFloat y = (point.y - CGRectGetMidY(self.bounds)) / radius_y;
    return x * x + y * y <= 1.0;
}

- (instancetype)init
{
    self = [super initWithFrame:CGRectZero];
    if (self)
    {
        self.userInteractionEnabled = YES;
        self.multipleTouchEnabled = NO;
        _touchIndicator = [[UIView alloc] init];
        _touchIndicator.userInteractionEnabled = NO;
        _touchIndicator.hidden = YES;
        _touchIndicator.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.13];
        _touchIndicator.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.52].CGColor;
        _touchIndicator.layer.borderWidth = 1.0;
        [self addSubview:_touchIndicator];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    const CGFloat size = MIN(38.0, MIN(self.bounds.size.width, self.bounds.size.height) * 0.28);
    _touchIndicator.bounds = CGRectMake(0, 0, size, size);
    _touchIndicator.layer.cornerRadius = size * 0.5;
    if (_touchIndicator.hidden)
        _touchIndicator.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
}

- (void)updateWithTouch:(UITouch*)touch
{
    const CGPoint point = [touch locationInView:self];
    const CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    const CGFloat radius = MAX(1.0, MIN(self.bounds.size.width, self.bounds.size.height) * 0.46);
    float x = (float)((point.x - center.x) / radius);
    float y = (float)((center.y - point.y) / radius);
    const float magnitude = hypotf(x, y);
    if (magnitude > 1.0f)
    {
        x /= magnitude;
        y /= magnitude;
    }
    else if (magnitude < 0.07f)
    {
        x = 0.0f;
        y = 0.0f;
    }
    else
    {
        const float scaled = (magnitude - 0.07f) / (0.93f * magnitude);
        x *= scaled;
        y *= scaled;
    }

    _touchIndicator.hidden = NO;
    _touchIndicator.center = CGPointMake(
        center.x + x * radius * 0.30,
        center.y - y * radius * 0.30);
    self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.035];
    if (self.valueHandler)
        self.valueHandler(x, y);
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
    (void)event;
    if (_trackingTouch)
        return;
    _trackingTouch = touches.anyObject;
    if (_trackingTouch)
        [self updateWithTouch:_trackingTouch];
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
    (void)event;
    if (_trackingTouch && [touches containsObject:_trackingTouch])
        [self updateWithTouch:_trackingTouch];
}

- (void)resetTracking
{
    _touchIndicator.hidden = YES;
    self.backgroundColor = UIColor.clearColor;
    _trackingTouch = nil;
    if (self.valueHandler)
        self.valueHandler(0.0f, 0.0f);
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
    (void)event;
    if (_trackingTouch && [touches containsObject:_trackingTouch])
        [self resetTracking];
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
    (void)event;
    if (_trackingTouch && [touches containsObject:_trackingTouch])
        [self resetTracking];
}

@end


static CGRect normalized_rect(CGRect container, CGFloat x, CGFloat y, CGFloat width, CGFloat height)
{
    return CGRectMake(
        container.origin.x + x * container.size.width,
        container.origin.y + y * container.size.height,
        width * container.size.width,
        height * container.size.height);
}

@interface ARMSX3ViewController () <UIDocumentPickerDelegate, UITableViewDataSource, UITableViewDelegate>

@property(nonatomic, strong) ARMSX3CoreSession* core;
@property(nonatomic, strong) UIScrollView* rootScroll;
@property(nonatomic, strong) UIStackView* contentStack;
@property(nonatomic, strong) NSLayoutConstraint* stackTopConstraint;
@property(nonatomic, strong) NSLayoutConstraint* stackLeadingConstraint;
@property(nonatomic, strong) NSLayoutConstraint* stackTrailingConstraint;
@property(nonatomic, strong) NSLayoutConstraint* stackBottomConstraint;
@property(nonatomic, strong) NSLayoutConstraint* stackWidthConstraint;
@property(nonatomic, strong) UIView* playerStage;
@property(nonatomic, strong) NSLayoutConstraint* playerStageHeightConstraint;
@property(nonatomic, strong) ARMSX3MetalView* metalView;
@property(nonatomic, strong) UIImageView* leftControllerSkin;
@property(nonatomic, strong) UIImageView* rightControllerSkin;
@property(nonatomic, strong) UILabel* stateLabel;
@property(nonatomic, strong) UIProgressView* progressView;
@property(nonatomic, strong) UITableView* gameTable;
@property(nonatomic, strong) UITextView* logView;
@property(nonatomic, strong) UITextField* netISOHostField;
@property(nonatomic, strong) UITextField* netISOPortField;
@property(nonatomic, strong) NSTimer* statusTimer;
@property(nonatomic, copy) NSArray<NSDictionary<NSString*, id>*>* games;
@property(nonatomic) BOOL pickingFirmware;
@property(nonatomic) uint64_t touchButtons;
@property(nonatomic, strong) NSMutableArray<UIButton*>* touchControls;
@property(nonatomic, strong) NSMutableArray<UIView*>* landscapeControls;
@property(nonatomic, strong) NSMutableArray<UIButton*>* landscapeButtons;
@property(nonatomic, strong) NSMutableArray<ARMSX3DPadSectorButton*>* landscapeDPadButtons;
@property(nonatomic, strong) ARMSX3VirtualStick* leftVirtualStick;
@property(nonatomic, strong) ARMSX3VirtualStick* rightVirtualStick;
@property(nonatomic, strong) UIButton* landscapeMenuButton;
@property(nonatomic, strong) UILabel* landscapeRuntimeLabel;
@property(nonatomic, strong) UILabel* inputTelemetryLabel;
@property(nonatomic, copy) NSArray<UIView*>* debugChromeViews;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, NSNumber*>* touchPressStarted;
@property(nonatomic, strong) NSMutableDictionary<NSNumber*, NSNumber*>* touchReleaseTokens;
@property(nonatomic) NSUInteger touchEventSequence;
@property(nonatomic) float touchLeftX;
@property(nonatomic) float touchLeftY;
@property(nonatomic) float touchRightX;
@property(nonatomic) float touchRightY;
@property(nonatomic) BOOL landscapeLayout;
@property(nonatomic) BOOL displayUpdateScheduled;
@property(nonatomic) CGSize lastDisplaySize;
@property(nonatomic) float lastDisplayRefreshRate;
@property(nonatomic, copy) NSString* lastCoreLog;
@property(nonatomic, copy) NSString* lastOperationMessage;
@property(nonatomic) NSUInteger telemetryHideToken;
@property(nonatomic) BOOL appInactive;
@property(nonatomic) BOOL fatalCoreError;

@end

@implementation ARMSX3ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [ARMSX3SettingsViewController registerDefaults];
    self.view.backgroundColor = [UIColor colorWithRed:0.018 green:0.027 blue:0.045 alpha:1.0];
    self.games = @[];
    self.touchControls = [NSMutableArray array];
    self.landscapeControls = [NSMutableArray array];
    self.landscapeButtons = [NSMutableArray array];
    self.landscapeDPadButtons = [NSMutableArray array];
    self.touchPressStarted = [NSMutableDictionary dictionary];
    self.touchReleaseTokens = [NSMutableDictionary dictionary];

    __weak ARMSX3ViewController* weak_self = self;
    self.core = [[ARMSX3CoreSession alloc] initWithLogHandler:^(NSString* line) {
        [weak_self handleCoreLog:line];
    }];

    UIScrollView* scroll = [[UIScrollView alloc] init];
    self.rootScroll = scroll;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.delaysContentTouches = NO;
    scroll.canCancelContentTouches = NO;
    [self.view addSubview:scroll];

    UIStackView* stack = [[UIStackView alloc] init];
    self.contentStack = stack;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 9.0;
    [scroll addSubview:stack];

    UILabel* title = [[UILabel alloc] init];
    NSString* app_version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (![app_version isKindOfClass:NSString.class] || app_version.length == 0)
    {
        app_version = @"unknown";
    }
    title.text = [NSString stringWithFormat:@"ARMSX3 · Pre-Alpha %@", app_version];
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightBlack];
    [stack addArrangedSubview:title];

    self.stateLabel = [[UILabel alloc] init];
    self.stateLabel.text = @"Initializing real RPCS3 core...";
    self.stateLabel.numberOfLines = 3;
    self.stateLabel.textColor = [UIColor colorWithRed:0.98 green:0.72 blue:0.25 alpha:1.0];
    self.stateLabel.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightSemibold];
    [stack addArrangedSubview:self.stateLabel];

    self.playerStage = [[UIView alloc] init];
    self.playerStage.backgroundColor = UIColor.blackColor;
    self.playerStage.clipsToBounds = YES;
    self.playerStage.multipleTouchEnabled = YES;
    self.playerStage.layer.cornerRadius = 12.0;
    self.playerStageHeightConstraint = [self.playerStage.heightAnchor constraintEqualToConstant:180.0];
    self.playerStageHeightConstraint.active = YES;
    [stack addArrangedSubview:self.playerStage];

    self.leftControllerSkin = [[UIImageView alloc] initWithImage:
        [UIImage imageNamed:@"controller-ps3-landscape-left"]];
    self.rightControllerSkin = [[UIImageView alloc] initWithImage:
        [UIImage imageNamed:@"controller-ps3-landscape-right"]];
    for (UIImageView* skin in @[self.leftControllerSkin, self.rightControllerSkin])
    {
        skin.contentMode = UIViewContentModeScaleAspectFit;
        skin.userInteractionEnabled = NO;
        skin.hidden = YES;
        skin.layer.minificationFilter = kCAFilterTrilinear;
        skin.layer.magnificationFilter = kCAFilterLinear;
        [self.playerStage addSubview:skin];
    }

    self.metalView = [[ARMSX3MetalView alloc] initWithFrame:CGRectZero];
    [self.playerStage addSubview:self.metalView];
    [self installTouchControls];
    [self installLandscapeControls];

    self.landscapeRuntimeLabel = [[UILabel alloc] init];
    self.landscapeRuntimeLabel.hidden = YES;
    self.landscapeRuntimeLabel.userInteractionEnabled = NO;
    self.landscapeRuntimeLabel.numberOfLines = 4;
    self.landscapeRuntimeLabel.textAlignment = NSTextAlignmentCenter;
    self.landscapeRuntimeLabel.textColor = UIColor.whiteColor;
    self.landscapeRuntimeLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.66];
    self.landscapeRuntimeLabel.font = [UIFont monospacedSystemFontOfSize:9.0 weight:UIFontWeightSemibold];
    self.landscapeRuntimeLabel.layer.cornerRadius = 7.0;
    self.landscapeRuntimeLabel.clipsToBounds = YES;
    [self.playerStage addSubview:self.landscapeRuntimeLabel];

    self.inputTelemetryLabel = [[UILabel alloc] init];
    self.inputTelemetryLabel.hidden = YES;
    self.inputTelemetryLabel.userInteractionEnabled = NO;
    self.inputTelemetryLabel.textAlignment = NSTextAlignmentCenter;
    self.inputTelemetryLabel.textColor = [UIColor colorWithRed:0.38 green:0.96 blue:0.82 alpha:1.0];
    self.inputTelemetryLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.72];
    self.inputTelemetryLabel.font = [UIFont monospacedSystemFontOfSize:9.0 weight:UIFontWeightBold];
    self.inputTelemetryLabel.layer.cornerRadius = 7.0;
    self.inputTelemetryLabel.clipsToBounds = YES;
    [self.playerStage addSubview:self.inputTelemetryLabel];

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.progressTintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.66 alpha:1.0];
    self.progressView.trackTintColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    [stack addArrangedSubview:self.progressView];

    UIStackView* first_row = [self buttonRow:@[
        [self button:@"Install Firmware" action:@selector(pickFirmware)],
        [self button:@"Import Local Copy" action:@selector(pickGame)],
    ]];
    [stack addArrangedSubview:first_row];

    UIStackView* second_row = [self buttonRow:@[
        [self button:@"Refresh" action:@selector(refreshGames)],
        [self button:@"Open XMB" action:@selector(openXMB)],
        [self button:@"Settings" action:@selector(showSettings)],
    ]];
    [stack addArrangedSubview:second_row];

    UIStackView* third_row = [self buttonRow:@[
        [self button:@"Stop Emulation" action:@selector(stopGame)],
    ]];
    [stack addArrangedSubview:third_row];

    UILabel* netiso_label = [[UILabel alloc] init];
    netiso_label.text = @"NETISO streaming (standard ps3netsrv)";
    netiso_label.textColor = [UIColor colorWithWhite:0.82 alpha:1.0];
    netiso_label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold];
    [stack addArrangedSubview:netiso_label];

    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    self.netISOHostField = [self textFieldWithPlaceholder:@"Server host or IP"];
    self.netISOHostField.text = [defaults stringForKey:@"ARMSX3NetISOHost"] ?: @"";
    self.netISOHostField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    self.netISOPortField = [self textFieldWithPlaceholder:@"Port"];
    NSInteger saved_port = [defaults integerForKey:@"ARMSX3NetISOPort"];
    self.netISOPortField.text = [NSString stringWithFormat:@"%ld", (long)(saved_port ?: 38008)];
    self.netISOPortField.keyboardType = UIKeyboardTypeNumberPad;
    UIButton* connect_netiso = [self button:@"Connect + Scan NAS" action:@selector(connectNetISO)];
    UIStackView* netiso_row = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.netISOHostField, self.netISOPortField, connect_netiso,
    ]];
    netiso_row.axis = UILayoutConstraintAxisHorizontal;
    netiso_row.spacing = 8.0;
    [self.netISOPortField.widthAnchor constraintEqualToConstant:74.0].active = YES;
    [connect_netiso.widthAnchor constraintEqualToConstant:142.0].active = YES;
    [stack addArrangedSubview:netiso_row];

    UILabel* library_label = [[UILabel alloc] init];
    library_label.text = @"[NAS] titles stream directly; Import Local Copy uses iPhone storage";
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

    self.debugChromeViews = @[
        title,
        self.stateLabel,
        self.progressView,
        first_row,
        second_row,
        third_row,
        netiso_label,
        netiso_row,
        library_label,
        self.gameTable,
        self.logView,
    ];

    self.stackTopConstraint = [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:12.0];
    self.stackLeadingConstraint = [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:12.0];
    self.stackTrailingConstraint = [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-12.0];
    self.stackBottomConstraint = [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-16.0];
    self.stackWidthConstraint = [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-24.0];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        self.stackTopConstraint,
        self.stackLeadingConstraint,
        self.stackTrailingConstraint,
        self.stackBottomConstraint,
        self.stackWidthConstraint,
    ]];

    [self startControllerSupport];
    self.statusTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                       target:self
                                                     selector:@selector(updateRuntimeStatus)
                                                     userInfo:nil
                                                      repeats:YES];
    [self.core initializeWithCompletion:^(BOOL succeeded, NSString* message) {
        weak_self.lastOperationMessage = message;
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

- (UITextField*)textFieldWithPlaceholder:(NSString*)placeholder
{
    UITextField* field = [[UITextField alloc] init];
    field.backgroundColor = [UIColor colorWithRed:0.055 green:0.085 blue:0.13 alpha:1.0];
    field.textColor = UIColor.whiteColor;
    field.tintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.66 alpha:1.0];
    field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder
        attributes:@{ NSForegroundColorAttributeName: [UIColor colorWithWhite:0.52 alpha:1.0] }];
    field.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightMedium];
    field.layer.cornerRadius = 9.0;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.spellCheckingType = UITextSpellCheckingTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 1)];
    field.leftViewMode = UITextFieldViewModeAlways;
    [field.heightAnchor constraintEqualToConstant:42.0].active = YES;
    return field;
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
    NSTextStorage* storage = self.logView.textStorage;
    NSDictionary* attributes = @{
        NSFontAttributeName: self.logView.font,
        NSForegroundColorAttributeName: self.logView.textColor,
    };
    [storage beginEditing];
    [storage appendAttributedString:[[NSAttributedString alloc]
        initWithString:[line stringByAppendingString:@"\n"] attributes:attributes]];
    if (storage.length > 24000)
        [storage deleteCharactersInRange:NSMakeRange(0, storage.length - 18000)];
    [storage endEditing];
    if (!self.logView.hidden && self.logView.window)
        [self.logView scrollRangeToVisible:NSMakeRange(storage.length, 0)];
}

- (void)handleCoreLog:(NSString*)line
{
    self.lastCoreLog = line;
    [self appendLog:line];
    if ([line containsString:@"Thread terminated due to fatal error"])
    {
        self.fatalCoreError = YES;
        self.lastOperationMessage = line;
        self.stateLabel.text = @"Game stopped: fatal guest error. See the final log line.";
        self.stateLabel.textColor = [UIColor colorWithRed:1.0 green:0.30 blue:0.28 alpha:1.0];
        self.progressView.hidden = YES;
    }
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self updateLayoutMode];
    [self layoutPlayerStage];
    [self layoutTouchControls];
    [self attachDisplay];
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    __weak ARMSX3ViewController* weak_self = self;
    [coordinator animateAlongsideTransition:nil completion:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
        ARMSX3ViewController* strong_self = weak_self;
        if (!strong_self)
            return;
        [strong_self.view setNeedsLayout];
        [strong_self.view layoutIfNeeded];
    }];
}

- (void)attachDisplay
{
    if (self.displayUpdateScheduled)
        return;
    self.displayUpdateScheduled = YES;
    __weak ARMSX3ViewController* weak_self = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        ARMSX3ViewController* strong_self = weak_self;
        if (!strong_self)
            return;
        strong_self.displayUpdateScheduled = NO;
        if (!strong_self.core.isReady || strong_self.metalView.bounds.size.width < 1.0)
            return;
        [strong_self.metalView layoutIfNeeded];
        const CGSize size = strong_self.metalView.metalLayer.drawableSize;
        const float refresh = (float)(strong_self.view.window.screen.maximumFramesPerSecond ?: 60);
        if (fabs(size.width - strong_self.lastDisplaySize.width) < 1.0
            && fabs(size.height - strong_self.lastDisplaySize.height) < 1.0
            && fabsf(refresh - strong_self.lastDisplayRefreshRate) < 0.1f)
        {
            return;
        }
        [strong_self.core updateDisplayLayer:strong_self.metalView.metalLayer refreshRate:refresh];
        strong_self.lastDisplaySize = size;
        strong_self.lastDisplayRefreshRate = refresh;
    });
}

- (void)updateLayoutMode
{
    const BOOL landscape = self.view.bounds.size.width > self.view.bounds.size.height;
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    const BOOL touch = [defaults boolForKey:ARMSX3ShowTouchControls];
    const BOOL layout_changed = self.landscapeLayout != landscape;
    self.landscapeLayout = landscape;

    // Reapply visibility on every layout pass. Rotation callbacks can arrive
    // while UIKit still reports the previous bounds, so a transition-only
    // toggle can otherwise leave portrait controls hidden behind the display.
    for (UIView* view in self.debugChromeViews)
        view.hidden = landscape;
    self.logView.hidden = landscape || ![defaults boolForKey:ARMSX3ShowDebugLog];
    for (UIButton* button in self.touchControls)
    {
        button.hidden = landscape || !touch;
        if (!landscape)
            [self.playerStage bringSubviewToFront:button];
    }
    for (UIView* control in self.landscapeControls)
        control.hidden = !landscape || !touch;
    self.landscapeMenuButton.hidden = !landscape;
    self.leftControllerSkin.hidden = !landscape || !touch;
    self.rightControllerSkin.hidden = !landscape || !touch;
    self.landscapeRuntimeLabel.hidden = !landscape || ![defaults boolForKey:ARMSX3ShowRuntimeOverlay];
    if (!landscape || ![defaults boolForKey:ARMSX3ShowInputDiagnostics])
        self.inputTelemetryLabel.hidden = YES;
    self.rootScroll.alwaysBounceVertical = !landscape;
    self.rootScroll.scrollEnabled = !landscape;
    self.rootScroll.contentInsetAdjustmentBehavior = landscape
        ? UIScrollViewContentInsetAdjustmentNever
        : UIScrollViewContentInsetAdjustmentAutomatic;
    self.contentStack.spacing = landscape ? 0.0 : 9.0;
    self.stackTopConstraint.constant = landscape ? 0.0 : 12.0;
    self.stackLeadingConstraint.constant = landscape ? 0.0 : 12.0;
    self.stackTrailingConstraint.constant = landscape ? 0.0 : -12.0;
    self.stackBottomConstraint.constant = landscape ? 0.0 : -16.0;
    self.stackWidthConstraint.constant = landscape ? 0.0 : -24.0;
    self.playerStage.layer.cornerRadius = landscape ? 0.0 : 12.0;
    if (layout_changed && landscape)
        self.rootScroll.contentOffset = CGPointZero;

    const CGRect safe_frame = self.view.safeAreaLayoutGuide.layoutFrame;
    const CGFloat portrait_width = self.contentStack.bounds.size.width > 1.0
        ? self.contentStack.bounds.size.width
        : MAX(1.0, safe_frame.size.width - 24.0);
    const CGFloat target_height = landscape
        ? MAX(1.0, self.view.bounds.size.height)
        : floor(portrait_width * 9.0 / 16.0);
    if (fabs(self.playerStageHeightConstraint.constant - target_height) >= 0.5)
        self.playerStageHeightConstraint.constant = target_height;
}

- (UIButton*)landscapeButtonForBit:(uint64_t)bit
{
    for (UIButton* button in self.landscapeButtons)
    {
        if ((uint64_t)button.tag == bit)
            return button;
    }
    return nil;
}

- (void)setLandscapeButton:(uint64_t)bit frame:(CGRect)frame circular:(BOOL)circular
{
    ARMSX3ArtworkButton* button = (ARMSX3ArtworkButton*)[self landscapeButtonForBit:bit];
    button.frame = frame;
    button.circularHitArea = circular;
    button.layer.cornerRadius = circular
        ? MIN(button.bounds.size.width, button.bounds.size.height) * 0.5
        : MIN(12.0, button.bounds.size.height * 0.24);
}

- (void)layoutPlayerStage
{
    const CGRect bounds = self.playerStage.bounds;
    if (bounds.size.width < 1.0 || bounds.size.height < 1.0)
        return;

    if (!self.landscapeLayout)
    {
        self.metalView.frame = bounds;
        return;
    }

    static const CGFloat artwork_aspect = 853.0 / 1844.0;
    const BOOL touch = [NSUserDefaults.standardUserDefaults boolForKey:ARMSX3ShowTouchControls];
    const CGFloat rail_width = touch ? bounds.size.height * artwork_aspect : 0.0;
    const CGRect left_rail = CGRectMake(0, 0, rail_width, bounds.size.height);
    const CGRect right_rail = CGRectMake(bounds.size.width - rail_width, 0, rail_width, bounds.size.height);
    self.leftControllerSkin.frame = left_rail;
    self.rightControllerSkin.frame = right_rail;

    const CGFloat gap = 0.0;
    const CGRect display_slot = CGRectInset(
        CGRectMake(CGRectGetMaxX(left_rail), 0,
            CGRectGetMinX(right_rail) - CGRectGetMaxX(left_rail), bounds.size.height),
        gap, 0);
    CGFloat display_width = display_slot.size.width;
    CGFloat display_height = display_width * 9.0 / 16.0;
    if (display_height > display_slot.size.height)
    {
        display_height = display_slot.size.height;
        display_width = display_height * 16.0 / 9.0;
    }
    self.metalView.frame = CGRectIntegral(CGRectMake(
        CGRectGetMidX(display_slot) - display_width * 0.5,
        CGRectGetMidY(display_slot) - display_height * 0.5,
        display_width,
        display_height));

    // These full-canvas normalized frames are the accepted EmuHub PS2 rail
    // geometry. Keeping them literal prevents artwork/input drift.
    [self setLandscapeButton:RPCS3_IOS_PAD_BUTTON_L2
        frame:normalized_rect(left_rail, 0.1010, 0.0520, 0.3970, 0.0990) circular:NO];
    [self setLandscapeButton:RPCS3_IOS_PAD_BUTTON_L1
        frame:normalized_rect(left_rail, 0.5050, 0.0520, 0.3970, 0.0990) circular:NO];
    const CGRect dpad_frame = normalized_rect(left_rail, 0.2020, 0.2220, 0.5720, 0.2680);
    for (ARMSX3DPadSectorButton* button in self.landscapeDPadButtons)
        button.frame = dpad_frame;
    self.leftVirtualStick.frame = normalized_rect(left_rail, 0.2210, 0.5520, 0.5410, 0.2520);
    self.leftVirtualStick.layer.cornerRadius = MIN(self.leftVirtualStick.bounds.size.width,
        self.leftVirtualStick.bounds.size.height) * 0.5;
    self.landscapeMenuButton.frame = normalized_rect(left_rail, 0.1470, 0.8260, 0.2040, 0.0960);
    self.landscapeMenuButton.layer.cornerRadius = MIN(self.landscapeMenuButton.bounds.size.width,
        self.landscapeMenuButton.bounds.size.height) * 0.5;
    [self setLandscapeButton:RPCS3_IOS_PAD_BUTTON_SELECT
        frame:normalized_rect(left_rail, 0.5170, 0.8490, 0.3050, 0.0760) circular:NO];

    [self setLandscapeButton:RPCS3_IOS_PAD_BUTTON_R1
        frame:normalized_rect(right_rail, 0.1010, 0.0520, 0.3970, 0.0990) circular:NO];
    [self setLandscapeButton:RPCS3_IOS_PAD_BUTTON_R2
        frame:normalized_rect(right_rail, 0.5050, 0.0520, 0.3970, 0.0990) circular:NO];
    [self setLandscapeButton:RPCS3_IOS_PAD_BUTTON_TRIANGLE
        frame:normalized_rect(right_rail, 0.3940, 0.2070, 0.2140, 0.1030) circular:YES];
    [self setLandscapeButton:RPCS3_IOS_PAD_BUTTON_SQUARE
        frame:normalized_rect(right_rail, 0.1780, 0.3080, 0.2210, 0.1030) circular:YES];
    [self setLandscapeButton:RPCS3_IOS_PAD_BUTTON_CIRCLE
        frame:normalized_rect(right_rail, 0.6030, 0.3080, 0.2260, 0.1030) circular:YES];
    [self setLandscapeButton:RPCS3_IOS_PAD_BUTTON_CROSS
        frame:normalized_rect(right_rail, 0.3940, 0.4080, 0.2160, 0.1040) circular:YES];
    self.rightVirtualStick.frame = normalized_rect(right_rail, 0.2240, 0.5520, 0.5480, 0.2520);
    self.rightVirtualStick.layer.cornerRadius = MIN(self.rightVirtualStick.bounds.size.width,
        self.rightVirtualStick.bounds.size.height) * 0.5;
    [self setLandscapeButton:RPCS3_IOS_PAD_BUTTON_START
        frame:normalized_rect(right_rail, 0.1470, 0.8480, 0.2880, 0.0760) circular:NO];

    [self.landscapeMenuButton setTitle:touch ? @"" : @"Menu" forState:UIControlStateNormal];
    self.landscapeMenuButton.backgroundColor = touch ? UIColor.clearColor : [UIColor colorWithWhite:0 alpha:0.65];
    if (!touch)
    {
        self.landscapeMenuButton.frame = CGRectMake(MAX(12.0, self.view.safeAreaInsets.left + 8.0),
            MAX(12.0, self.view.safeAreaInsets.top + 8.0), 64.0, 44.0);
        self.landscapeMenuButton.layer.cornerRadius = 12.0;
    }
    [self.playerStage bringSubviewToFront:self.landscapeMenuButton];

    const CGRect display_inset = CGRectInset(self.metalView.frame, 8.0, 8.0);
    self.landscapeRuntimeLabel.frame = CGRectMake(display_inset.origin.x,
        display_inset.origin.y, display_inset.size.width, 34.0);
    self.inputTelemetryLabel.frame = CGRectMake(display_inset.origin.x,
        CGRectGetMaxY(display_inset) - 28.0, display_inset.size.width, 28.0);
    [self.playerStage bringSubviewToFront:self.landscapeRuntimeLabel];
    [self.playerStage bringSubviewToFront:self.inputTelemetryLabel];
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
        weak_self.lastOperationMessage = message;
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
        weak_self.lastOperationMessage = message;
        [weak_self appendLog:message];
        if (!succeeded)
            return;
        [weak_self reloadDisplayedGames];
    }];
}

- (void)connectNetISO
{
    [self.view endEditing:YES];
    NSString* host = [self.netISOHostField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSInteger port = self.netISOPortField.text.integerValue;
    if (!host.length || port < 1 || port > 65535)
    {
        self.stateLabel.text = @"Enter a NETISO host and valid port";
        return;
    }

    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:host forKey:@"ARMSX3NetISOHost"];
    [defaults setInteger:port forKey:@"ARMSX3NetISOPort"];
    self.stateLabel.text = [NSString stringWithFormat:@"Connecting to NETISO %@:%ld...", host, (long)port];
    __weak ARMSX3ViewController* weak_self = self;
    [self.core connectNetISOHost:host port:(uint16_t)port completion:^(BOOL succeeded, NSString* message) {
        weak_self.lastOperationMessage = message;
        weak_self.stateLabel.text = message;
        weak_self.stateLabel.textColor = succeeded
            ? [UIColor colorWithRed:0.25 green:0.88 blue:0.68 alpha:1.0]
            : [UIColor colorWithRed:1.0 green:0.30 blue:0.28 alpha:1.0];
        [weak_self appendLog:message];
        if (succeeded)
            [weak_self reloadDisplayedGames];
    }];
}

- (void)reloadDisplayedGames
{
    NSMutableArray<NSDictionary<NSString*, id>*>* games = [NSMutableArray arrayWithArray:self.core.games];
    [games addObjectsFromArray:self.core.netISOGames];
    [games sortUsingComparator:^NSComparisonResult(NSDictionary* left, NSDictionary* right) {
        return [left[@"title"] localizedCaseInsensitiveCompare:right[@"title"]];
    }];
    self.games = games;
    [self.gameTable reloadData];
}

- (void)runJITTest
{
    __weak ARMSX3ViewController* weak_self = self;
    [self.core runJITSelfTestWithCompletion:^(BOOL succeeded, NSString* message) {
        weak_self.lastOperationMessage = message;
        weak_self.stateLabel.text = message;
        [weak_self appendLog:message];
    }];
}

- (void)runMetalProbe
{
    self.stateLabel.text = @"Running stopped-core native Metal probe...";
    __weak ARMSX3ViewController* weak_self = self;
    [self.core runMetalProbeWithCompletion:^(BOOL succeeded, NSString* message) {
        weak_self.lastOperationMessage = message;
        weak_self.stateLabel.text = message;
        [weak_self appendLog:message];
    }];
}

- (void)openXMB
{
    self.fatalCoreError = NO;
    self.stateLabel.text = @"Booting the PS3 XMB...";
    [self attachDisplay];
    __weak ARMSX3ViewController* weak_self = self;
    [self.core bootXMBWithCompletion:^(BOOL succeeded, NSString* message) {
        weak_self.lastOperationMessage = message;
        weak_self.stateLabel.text = message;
        [weak_self appendLog:message];
    }];
}

- (void)stopGame
{
    if (self.fatalCoreError || self.core.hasFatalError)
    {
        NSString* message = @"Core renderer failed; unsafe teardown was blocked. Relaunch ARMSX3 to reset without triggering the known stop crash.";
        self.lastOperationMessage = message;
        self.stateLabel.text = message;
        self.stateLabel.textColor = [UIColor colorWithRed:1.0 green:0.48 blue:0.20 alpha:1.0];
        [self appendLog:message];
        return;
    }
    __weak ARMSX3ViewController* weak_self = self;
    self.stateLabel.text = @"Stopping emulation...";
    [self.core stopWithCompletion:^(BOOL succeeded, NSString* message) {
        weak_self.lastOperationMessage = message;
        weak_self.stateLabel.text = message;
        [weak_self appendLog:message];
    }];
}

- (void)confirmRebuildGraphicsCaches
{
    UIAlertController* confirmation = [UIAlertController
        alertControllerWithTitle:@"Rebuild Graphics Caches?"
        message:@"Stop emulation first. This clears PS3 graphics shaders and Vulkan pipelines for every title. Firmware, CPU modules, saves, trophies, and games are preserved."
        preferredStyle:UIAlertControllerStyleAlert];
    [confirmation addAction:[UIAlertAction actionWithTitle:@"Cancel"
        style:UIAlertActionStyleCancel handler:nil]];
    __weak ARMSX3ViewController* weak_self = self;
    [confirmation addAction:[UIAlertAction actionWithTitle:@"Rebuild"
        style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction* action) {
            ARMSX3ViewController* strong_self = weak_self;
            if (!strong_self)
                return;
            strong_self.stateLabel.text = @"Clearing graphics caches...";
            [strong_self.core rebuildGraphicsCachesWithCompletion:^(BOOL succeeded, NSString* message) {
                strong_self.lastOperationMessage = message;
                strong_self.stateLabel.text = message;
                strong_self.stateLabel.textColor = succeeded
                    ? [UIColor colorWithRed:0.25 green:0.88 blue:0.68 alpha:1.0]
                    : [UIColor colorWithRed:1.0 green:0.30 blue:0.28 alpha:1.0];
                [strong_self appendLog:message];
            }];
        }]];
    [self presentViewController:confirmation animated:YES completion:nil];
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
    NSNumber* size = game[@"size"];
    if ([game[@"remote"] boolValue] && size.unsignedLongLongValue)
    {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"[NAS] %@ | %.2f GiB",
            game[@"version"], size.unsignedLongLongValue / (1024.0 * 1024.0 * 1024.0)];
    }
    else
    {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ | %@", game[@"titleID"], game[@"version"]];
    }
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.62 alpha:1.0];
    cell.backgroundColor = UIColor.clearColor;
    return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary* game = self.games[(NSUInteger)indexPath.row];
    self.fatalCoreError = NO;
    NSString* title_id = game[@"titleID"];
    self.stateLabel.text = [NSString stringWithFormat:@"Booting %@...", game[@"title"]];
    [self attachDisplay];
    __weak ARMSX3ViewController* weak_self = self;
    if ([game[@"remote"] boolValue])
    {
        [self.core bootNetISOPath:game[@"path"] completion:^(BOOL succeeded, NSString* message) {
            weak_self.lastOperationMessage = message;
            weak_self.stateLabel.text = message;
            weak_self.stateLabel.textColor = succeeded
                ? [UIColor colorWithRed:0.25 green:0.88 blue:0.68 alpha:1.0]
                : [UIColor colorWithRed:1.0 green:0.30 blue:0.28 alpha:1.0];
            [weak_self appendLog:message];
        }];
    }
    else
    {
        [self.core bootTitleID:title_id completion:^(BOOL succeeded, NSString* message) {
            weak_self.lastOperationMessage = message;
            weak_self.stateLabel.text = message;
            weak_self.stateLabel.textColor = succeeded
                ? [UIColor colorWithRed:0.25 green:0.88 blue:0.68 alpha:1.0]
                : [UIColor colorWithRed:1.0 green:0.30 blue:0.28 alpha:1.0];
            [weak_self appendLog:message];
        }];
    }
}

- (void)updateRuntimeStatus
{
    UIApplication.sharedApplication.idleTimerDisabled =
        !self.appInactive && self.core.isEmulationActive &&
        [NSUserDefaults.standardUserDefaults boolForKey:ARMSX3KeepScreenAwake];
    if (self.core.isReady)
    {
        NSString* runtime = [self.core runtimeStatus];
        self.stateLabel.text = runtime;
        if (self.landscapeLayout)
        {
            NSString* detail = self.lastOperationMessage.length
                ? self.lastOperationMessage
                : self.lastCoreLog;
            if (detail.length > 180)
                detail = [detail substringToIndex:180];
            self.landscapeRuntimeLabel.text = detail.length
                ? [NSString stringWithFormat:@"%@\n%@", runtime, detail]
                : runtime;
        }
    }
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
        if (weak_self.appInactive)
            return;
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
        @{ @"title": @"▲", @"label": @"D-pad up", @"bit": @(RPCS3_IOS_PAD_BUTTON_DPAD_UP), @"tint": @0 },
        @{ @"title": @"▼", @"label": @"D-pad down", @"bit": @(RPCS3_IOS_PAD_BUTTON_DPAD_DOWN), @"tint": @0 },
        @{ @"title": @"◀", @"label": @"D-pad left", @"bit": @(RPCS3_IOS_PAD_BUTTON_DPAD_LEFT), @"tint": @0 },
        @{ @"title": @"▶", @"label": @"D-pad right", @"bit": @(RPCS3_IOS_PAD_BUTTON_DPAD_RIGHT), @"tint": @0 },
        @{ @"title": @"△", @"label": @"Triangle", @"bit": @(RPCS3_IOS_PAD_BUTTON_TRIANGLE), @"tint": @1 },
        @{ @"title": @"×", @"label": @"Cross", @"bit": @(RPCS3_IOS_PAD_BUTTON_CROSS), @"tint": @2 },
        @{ @"title": @"□", @"label": @"Square", @"bit": @(RPCS3_IOS_PAD_BUTTON_SQUARE), @"tint": @3 },
        @{ @"title": @"○", @"label": @"Circle", @"bit": @(RPCS3_IOS_PAD_BUTTON_CIRCLE), @"tint": @4 },
        @{ @"title": @"SELECT", @"label": @"Select", @"bit": @(RPCS3_IOS_PAD_BUTTON_SELECT), @"tint": @0 },
        @{ @"title": @"START", @"label": @"Start", @"bit": @(RPCS3_IOS_PAD_BUTTON_START), @"tint": @0 },
    ];
    for (NSDictionary* spec in controls)
    {
        ARMSX3ArtworkButton* button = [ARMSX3ArtworkButton buttonWithType:UIButtonTypeCustom];
        button.tag = [spec[@"bit"] unsignedLongLongValue];
        button.circularHitArea = self.touchControls.count < 8;
        button.accessibilityLabel = spec[@"label"];
        button.backgroundColor = [UIColor colorWithRed:0.025 green:0.040 blue:0.070 alpha:0.88];
        NSArray<UIColor*>* colors = @[
            [UIColor colorWithRed:0.76 green:0.82 blue:0.90 alpha:1.0],
            [UIColor colorWithRed:0.30 green:0.92 blue:0.60 alpha:1.0],
            [UIColor colorWithRed:0.38 green:0.72 blue:1.00 alpha:1.0],
            [UIColor colorWithRed:0.96 green:0.46 blue:0.76 alpha:1.0],
            [UIColor colorWithRed:1.00 green:0.48 blue:0.50 alpha:1.0],
        ];
        UIColor* tint = colors[[spec[@"tint"] unsignedIntegerValue]];
        button.layer.borderColor = tint.CGColor;
        button.layer.borderWidth = 1.5;
        button.layer.shadowColor = tint.CGColor;
        button.layer.shadowOpacity = 0.22;
        button.layer.shadowRadius = 4.0;
        button.layer.shadowOffset = CGSizeZero;
        button.layer.cornerRadius = 18.0;
        button.multipleTouchEnabled = YES;
        button.exclusiveTouch = NO;
        button.titleLabel.font = [UIFont systemFontOfSize:self.touchControls.count < 8 ? 19.0 : 10.0
            weight:UIFontWeightBlack];
        [button setTitle:spec[@"title"] forState:UIControlStateNormal];
        [button setTitleColor:tint forState:UIControlStateNormal];
        [button addTarget:self action:@selector(touchDown:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
        [button addTarget:self action:@selector(touchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
        [self.playerStage addSubview:button];
        [self.touchControls addObject:button];
    }
}

- (UIButton*)landscapePadButton:(NSString*)label bit:(uint64_t)bit
{
    ARMSX3ArtworkButton* button = [ARMSX3ArtworkButton buttonWithType:UIButtonTypeCustom];
    button.tag = (NSInteger)bit;
    button.hidden = YES;
    button.exclusiveTouch = NO;
    button.multipleTouchEnabled = YES;
    button.backgroundColor = UIColor.clearColor;
    button.accessibilityLabel = label;
    [button addTarget:self action:@selector(touchDown:)
        forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [button addTarget:self action:@selector(touchUp:)
        forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside
            | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    [self.playerStage addSubview:button];
    [self.landscapeButtons addObject:button];
    [self.landscapeControls addObject:button];
    return button;
}

- (void)addLandscapeDPadSector:(NSString*)label bit:(uint64_t)bit angle:(CGFloat)angle
{
    ARMSX3DPadSectorButton* button = [ARMSX3DPadSectorButton buttonWithType:UIButtonTypeCustom];
    button.tag = (NSInteger)bit;
    button.directionAngle = angle;
    button.hidden = YES;
    button.exclusiveTouch = NO;
    button.multipleTouchEnabled = YES;
    button.backgroundColor = UIColor.clearColor;
    button.accessibilityLabel = label;
    [button addTarget:self action:@selector(touchDown:)
        forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [button addTarget:self action:@selector(touchUp:)
        forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside
            | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    [self.playerStage addSubview:button];
    [self.landscapeDPadButtons addObject:button];
    [self.landscapeControls addObject:button];
}

- (void)installLandscapeControls
{
    [self landscapePadButton:@"L2" bit:RPCS3_IOS_PAD_BUTTON_L2];
    [self landscapePadButton:@"L1" bit:RPCS3_IOS_PAD_BUTTON_L1];
    [self landscapePadButton:@"R1" bit:RPCS3_IOS_PAD_BUTTON_R1];
    [self landscapePadButton:@"R2" bit:RPCS3_IOS_PAD_BUTTON_R2];
    [self landscapePadButton:@"Triangle" bit:RPCS3_IOS_PAD_BUTTON_TRIANGLE];
    [self landscapePadButton:@"Square" bit:RPCS3_IOS_PAD_BUTTON_SQUARE];
    [self landscapePadButton:@"Circle" bit:RPCS3_IOS_PAD_BUTTON_CIRCLE];
    [self landscapePadButton:@"Cross" bit:RPCS3_IOS_PAD_BUTTON_CROSS];
    [self landscapePadButton:@"Select" bit:RPCS3_IOS_PAD_BUTTON_SELECT];
    [self landscapePadButton:@"Start" bit:RPCS3_IOS_PAD_BUTTON_START];

    [self addLandscapeDPadSector:@"D-pad right"
        bit:RPCS3_IOS_PAD_BUTTON_DPAD_RIGHT angle:0.0];
    [self addLandscapeDPadSector:@"D-pad down right"
        bit:RPCS3_IOS_PAD_BUTTON_DPAD_DOWN | RPCS3_IOS_PAD_BUTTON_DPAD_RIGHT angle:M_PI_4];
    [self addLandscapeDPadSector:@"D-pad down"
        bit:RPCS3_IOS_PAD_BUTTON_DPAD_DOWN angle:M_PI_2];
    [self addLandscapeDPadSector:@"D-pad down left"
        bit:RPCS3_IOS_PAD_BUTTON_DPAD_DOWN | RPCS3_IOS_PAD_BUTTON_DPAD_LEFT angle:3.0 * M_PI_4];
    [self addLandscapeDPadSector:@"D-pad left"
        bit:RPCS3_IOS_PAD_BUTTON_DPAD_LEFT angle:M_PI];
    [self addLandscapeDPadSector:@"D-pad up left"
        bit:RPCS3_IOS_PAD_BUTTON_DPAD_UP | RPCS3_IOS_PAD_BUTTON_DPAD_LEFT angle:-3.0 * M_PI_4];
    [self addLandscapeDPadSector:@"D-pad up"
        bit:RPCS3_IOS_PAD_BUTTON_DPAD_UP angle:-M_PI_2];
    [self addLandscapeDPadSector:@"D-pad up right"
        bit:RPCS3_IOS_PAD_BUTTON_DPAD_UP | RPCS3_IOS_PAD_BUTTON_DPAD_RIGHT angle:-M_PI_4];

    __weak ARMSX3ViewController* weak_self = self;
    self.leftVirtualStick = [[ARMSX3VirtualStick alloc] init];
    self.leftVirtualStick.hidden = YES;
    self.leftVirtualStick.accessibilityLabel = @"Left analog stick";
    self.leftVirtualStick.valueHandler = ^(float x, float y) {
        ARMSX3ViewController* strong_self = weak_self;
        if (!strong_self)
            return;
        strong_self.touchLeftX = x;
        strong_self.touchLeftY = y;
        [strong_self pushTouchPad];
    };
    [self.playerStage addSubview:self.leftVirtualStick];
    [self.landscapeControls addObject:self.leftVirtualStick];

    self.rightVirtualStick = [[ARMSX3VirtualStick alloc] init];
    self.rightVirtualStick.hidden = YES;
    self.rightVirtualStick.accessibilityLabel = @"Right analog stick";
    self.rightVirtualStick.valueHandler = ^(float x, float y) {
        ARMSX3ViewController* strong_self = weak_self;
        if (!strong_self)
            return;
        strong_self.touchRightX = x;
        strong_self.touchRightY = y;
        [strong_self pushTouchPad];
    };
    [self.playerStage addSubview:self.rightVirtualStick];
    [self.landscapeControls addObject:self.rightVirtualStick];

    ARMSX3ArtworkButton* menu_button = [ARMSX3ArtworkButton buttonWithType:UIButtonTypeCustom];
    menu_button.circularHitArea = YES;
    self.landscapeMenuButton = menu_button;
    self.landscapeMenuButton.hidden = YES;
    self.landscapeMenuButton.accessibilityLabel = @"EmuHub game menu";
    [self.landscapeMenuButton addTarget:self action:@selector(menuTouchDown:)
        forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [self.landscapeMenuButton addTarget:self action:@selector(showGameMenu:)
        forControlEvents:UIControlEventTouchUpInside];
    [self.landscapeMenuButton addTarget:self action:@selector(menuTouchCancelled:)
        forControlEvents:UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    [self.playerStage addSubview:self.landscapeMenuButton];
    [self.landscapeControls addObject:self.landscapeMenuButton];
}

- (void)layoutTouchControls
{
    if (self.landscapeLayout || self.touchControls.count != 10)
        return;
    const CGFloat width = self.metalView.bounds.size.width;
    const CGFloat height = self.metalView.bounds.size.height;
    if (width < 1.0 || height < 1.0)
        return;
    const CGFloat size = MIN(54.0, MAX(44.0, height * 0.24));
    const CGFloat left_x = MAX(width * 0.15, size * 1.45);
    const CGFloat right_x = MIN(width * 0.85, width - size * 1.45);
    const CGFloat center_y = MIN(height - size * 1.45, MAX(size * 1.45, height * 0.62));
    const CGFloat special_width = size * 1.35;
    const CGFloat special_gap = MAX(8.0, size * 0.18);
    const CGFloat special_offset = (special_width + special_gap) * 0.5;
    NSArray<NSValue*>* centers = @[
        [NSValue valueWithCGPoint:CGPointMake(left_x, center_y - size * 0.90)],
        [NSValue valueWithCGPoint:CGPointMake(left_x, center_y + size * 0.90)],
        [NSValue valueWithCGPoint:CGPointMake(left_x - size * 0.90, center_y)],
        [NSValue valueWithCGPoint:CGPointMake(left_x + size * 0.90, center_y)],
        [NSValue valueWithCGPoint:CGPointMake(right_x, center_y - size * 0.90)],
        [NSValue valueWithCGPoint:CGPointMake(right_x, center_y + size * 0.90)],
        [NSValue valueWithCGPoint:CGPointMake(right_x - size * 0.90, center_y)],
        [NSValue valueWithCGPoint:CGPointMake(right_x + size * 0.90, center_y)],
        [NSValue valueWithCGPoint:CGPointMake(width * 0.5 - special_offset, height - size * 0.55)],
        [NSValue valueWithCGPoint:CGPointMake(width * 0.5 + special_offset, height - size * 0.55)],
    ];
    [self.touchControls enumerateObjectsUsingBlock:^(UIButton* button, NSUInteger index, BOOL*) {
        const CGFloat button_width = index >= 8 ? special_width : size;
        button.bounds = CGRectMake(0, 0, button_width, size);
        CGPoint center = centers[index].CGPointValue;
        center.x += self.metalView.frame.origin.x;
        center.y += self.metalView.frame.origin.y;
        button.center = center;
        button.layer.cornerRadius = size * 0.50;
    }];
}

- (void)touchDown:(UIButton*)sender
{
    NSNumber* key = @((uint64_t)sender.tag);
    self.touchReleaseTokens[key] = @(++self.touchEventSequence);
    self.touchPressStarted[key] = @(CACurrentMediaTime());
    self.touchButtons |= key.unsignedLongLongValue;
    const BOOL dpad_sector = [self.landscapeDPadButtons containsObject:(ARMSX3DPadSectorButton*)sender];
    const BOOL landscape_button = [self.landscapeButtons containsObject:sender] || dpad_sector;
    sender.backgroundColor = landscape_button
        ? [UIColor colorWithWhite:1.0 alpha:dpad_sector ? 0.0 : 0.15]
        : sender.backgroundColor;
    const CGFloat scale = dpad_sector ? 1.0 : (landscape_button ? 0.96 : 0.90);
    sender.transform = CGAffineTransformMakeScale(scale, scale);
    [self pushTouchPad];
}

- (void)touchUp:(UIButton*)sender
{
    // Keep fast taps visible across at least several guest pad polls. Heavy
    // first-run LLVM work can otherwise consume an entire short touch pulse.
    static const CFTimeInterval minimum_press_duration = 0.12;
    NSNumber* key = @((uint64_t)sender.tag);
    const CFTimeInterval started = [self.touchPressStarted[key] doubleValue];
    const CFTimeInterval remaining = MAX(0.0, minimum_press_duration - (CACurrentMediaTime() - started));
    const NSUInteger token = ++self.touchEventSequence;
    self.touchReleaseTokens[key] = @(token);
    __weak ARMSX3ViewController* weak_self = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(remaining * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ARMSX3ViewController* strong_self = weak_self;
        if (!strong_self || [strong_self.touchReleaseTokens[key] unsignedIntegerValue] != token)
            return;
        strong_self.touchButtons &= ~key.unsignedLongLongValue;
        [strong_self.touchPressStarted removeObjectForKey:key];
        sender.transform = CGAffineTransformIdentity;
        if ([strong_self.landscapeButtons containsObject:sender]
            || [strong_self.landscapeDPadButtons containsObject:(ARMSX3DPadSectorButton*)sender])
            sender.backgroundColor = UIColor.clearColor;
        [strong_self pushTouchPad];
    });
}

- (void)menuTouchDown:(UIButton*)sender
{
    sender.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.16];
    sender.transform = CGAffineTransformMakeScale(0.94, 0.94);
}

- (void)menuTouchCancelled:(UIButton*)sender
{
    sender.backgroundColor = UIColor.clearColor;
    sender.transform = CGAffineTransformIdentity;
}

- (void)pulsePadButton:(uint64_t)bit
{
    NSNumber* key = @(bit);
    const NSUInteger token = ++self.touchEventSequence;
    self.touchReleaseTokens[key] = @(token);
    self.touchButtons |= bit;
    [self pushTouchPad];
    __weak ARMSX3ViewController* weak_self = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        ARMSX3ViewController* strong_self = weak_self;
        if (!strong_self || [strong_self.touchReleaseTokens[key] unsignedIntegerValue] != token)
            return;
        strong_self.touchButtons &= ~bit;
        [strong_self pushTouchPad];
    });
}

- (void)showGameMenu:(UIButton*)sender
{
    [self menuTouchCancelled:sender];
    UIAlertController* menu = [UIAlertController alertControllerWithTitle:@"EmuHub"
        message:@"PS3 session controls" preferredStyle:UIAlertControllerStyleAlert];
    __weak ARMSX3ViewController* weak_self = self;
    [menu addAction:[UIAlertAction actionWithTitle:@"Settings"
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction* action) {
            [weak_self showSettings];
        }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Press PS Button"
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction* action) {
            [weak_self pulsePadButton:RPCS3_IOS_PAD_BUTTON_PS];
        }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Show Diagnostics"
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction* action) {
            ARMSX3ViewController* strong_self = weak_self;
            if (!strong_self)
                return;
            NSString* message = [NSString stringWithFormat:@"Runtime: %@\n\nLast operation: %@\n\nLast core line: %@",
                [strong_self.core runtimeStatus],
                strong_self.lastOperationMessage ?: @"None",
                strong_self.lastCoreLog ?: @"None"];
            UIAlertController* diagnostics = [UIAlertController alertControllerWithTitle:@"ARMSX3 Diagnostics"
                message:message preferredStyle:UIAlertControllerStyleAlert];
            [diagnostics addAction:[UIAlertAction actionWithTitle:@"Close"
                style:UIAlertActionStyleCancel handler:nil]];
            [strong_self presentViewController:diagnostics animated:YES completion:nil];
        }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Stop Emulation"
        style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction* action) {
            [weak_self stopGame];
        }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Resume"
        style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:menu animated:YES completion:nil];
}

- (void)pushTouchPad
{
    if (self.appInactive)
        return;
    const BOOL accepted = [self.core updatePadConnected:YES buttons:self.touchButtons
        leftX:self.touchLeftX leftY:self.touchLeftY
        rightX:self.touchRightX rightY:self.touchRightY
        leftTrigger:(self.touchButtons & RPCS3_IOS_PAD_BUTTON_L2) ? 1.0f : 0.0f
        rightTrigger:(self.touchButtons & RPCS3_IOS_PAD_BUTTON_R2) ? 1.0f : 0.0f];
    if (!self.landscapeLayout || ![NSUserDefaults.standardUserDefaults boolForKey:ARMSX3ShowInputDiagnostics])
        return;

    NSMutableString* directions = [NSMutableString string];
    if (self.touchButtons & RPCS3_IOS_PAD_BUTTON_DPAD_UP) [directions appendString:@"U"];
    if (self.touchButtons & RPCS3_IOS_PAD_BUTTON_DPAD_DOWN) [directions appendString:@"D"];
    if (self.touchButtons & RPCS3_IOS_PAD_BUTTON_DPAD_LEFT) [directions appendString:@"L"];
    if (self.touchButtons & RPCS3_IOS_PAD_BUTTON_DPAD_RIGHT) [directions appendString:@"R"];
    if (!directions.length) [directions appendString:@"-"];
    self.inputTelemetryLabel.textColor = accepted
        ? [UIColor colorWithRed:0.38 green:0.96 blue:0.82 alpha:1.0]
        : [UIColor colorWithRed:1.0 green:0.32 blue:0.28 alpha:1.0];
    self.inputTelemetryLabel.text = [NSString stringWithFormat:@"PAD %@ | D:%@ | L %.2f %.2f | R %.2f %.2f",
        accepted ? @"OK" : @"REJECT", directions,
        self.touchLeftX, self.touchLeftY, self.touchRightX, self.touchRightY];
    self.inputTelemetryLabel.hidden = NO;
    const NSUInteger token = ++self.telemetryHideToken;
    __weak ARMSX3ViewController* weak_self = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        ARMSX3ViewController* strong_self = weak_self;
        if (strong_self && strong_self.telemetryHideToken == token)
            strong_self.inputTelemetryLabel.hidden = YES;
    });
}

- (void)applicationWillResignActive
{
    if (self.appInactive)
        return;
    self.appInactive = YES;
    UIApplication.sharedApplication.idleTimerDisabled = NO;
    self.touchButtons = 0;
    self.touchLeftX = 0.0f;
    self.touchLeftY = 0.0f;
    self.touchRightX = 0.0f;
    self.touchRightY = 0.0f;
    [self.leftVirtualStick resetTracking];
    [self.rightVirtualStick resetTracking];
    [self.core pauseForBackground];
}

- (void)applicationDidBecomeActive
{
    if (!self.appInactive)
        return;
    self.appInactive = NO;
    [self.core resumeFromBackground];
    UIApplication.sharedApplication.idleTimerDisabled = self.core.isEmulationActive &&
        [NSUserDefaults.standardUserDefaults boolForKey:ARMSX3KeepScreenAwake];
}

- (void)showSettings
{
    ARMSX3SettingsViewController* settings = [[ARMSX3SettingsViewController alloc] init];
    __weak ARMSX3ViewController* weak_self = self;
    settings.settingsChanged = ^{
        ARMSX3ViewController* strong_self = weak_self;
        if (!strong_self)
            return;
        if (![NSUserDefaults.standardUserDefaults boolForKey:ARMSX3ShowTouchControls])
        {
            [strong_self.touchReleaseTokens removeAllObjects];
            [strong_self.touchPressStarted removeAllObjects];
            strong_self.touchButtons = 0;
            [strong_self.leftVirtualStick resetTracking];
            [strong_self.rightVirtualStick resetTracking];
            [strong_self pushTouchPad];
        }
        [strong_self updateRuntimeStatus];
        [strong_self.view setNeedsLayout];
    };
    settings.rebuildGraphicsCaches = ^{ [weak_self confirmRebuildGraphicsCaches]; };
    UINavigationController* navigation = [[UINavigationController alloc] initWithRootViewController:settings];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    navigation.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [self presentViewController:navigation animated:YES completion:nil];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    rpcs3_ios_notify_memory_warning();
}

- (void)dealloc
{
    UIApplication.sharedApplication.idleTimerDisabled = NO;
    [self.statusTimer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

@end
