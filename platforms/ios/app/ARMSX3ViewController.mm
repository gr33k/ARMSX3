#import "ARMSX3ViewController.h"

#import "ARMSX3FeasibilityProbe.h"

@interface ARMSX3ViewController ()

@property(nonatomic, strong) UILabel* stateLabel;
@property(nonatomic, strong) UITextView* logView;
@property(nonatomic, strong) UIButton* runButton;

@end

@implementation ARMSX3ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor colorWithRed:0.025 green:0.035 blue:0.055 alpha:1.0];

    UILabel* title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"ARMSX3 iOS Feasibility";
    title.textColor = [UIColor colorWithRed:0.94 green:0.96 blue:1.0 alpha:1.0];
    title.font = [UIFont systemFontOfSize:25.0 weight:UIFontWeightBold];

    self.stateLabel = [[UILabel alloc] init];
    self.stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.stateLabel.text = @"Preparing probes";
    self.stateLabel.textColor = [UIColor colorWithRed:0.30 green:0.85 blue:0.70 alpha:1.0];
    self.stateLabel.font = [UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightSemibold];

    self.logView = [[UITextView alloc] init];
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    self.logView.editable = NO;
    self.logView.selectable = YES;
    self.logView.backgroundColor = [UIColor colorWithRed:0.055 green:0.075 blue:0.105 alpha:1.0];
    self.logView.textColor = [UIColor colorWithRed:0.82 green:0.88 blue:0.94 alpha:1.0];
    self.logView.font = [UIFont monospacedSystemFontOfSize:12.5 weight:UIFontWeightRegular];
    self.logView.layer.cornerRadius = 14.0;
    self.logView.textContainerInset = UIEdgeInsetsMake(14.0, 12.0, 14.0, 12.0);

    self.runButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.runButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.runButton.backgroundColor = [UIColor colorWithRed:0.14 green:0.39 blue:0.90 alpha:1.0];
    self.runButton.layer.cornerRadius = 12.0;
    self.runButton.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightBold];
    [self.runButton setTitle:@"Run Probes Again" forState:UIControlStateNormal];
    [self.runButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [self.runButton addTarget:self action:@selector(runProbes) forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:title];
    [self.view addSubview:self.stateLabel];
    [self.view addSubview:self.logView];
    [self.view addSubview:self.runButton];

    UILayoutGuide* safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:18.0],
        [title.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:18.0],
        [title.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-18.0],
        [self.stateLabel.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8.0],
        [self.stateLabel.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [self.stateLabel.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [self.logView.topAnchor constraintEqualToAnchor:self.stateLabel.bottomAnchor constant:14.0],
        [self.logView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:14.0],
        [self.logView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-14.0],
        [self.runButton.topAnchor constraintEqualToAnchor:self.logView.bottomAnchor constant:14.0],
        [self.runButton.leadingAnchor constraintEqualToAnchor:self.logView.leadingAnchor],
        [self.runButton.trailingAnchor constraintEqualToAnchor:self.logView.trailingAnchor],
        [self.runButton.heightAnchor constraintEqualToConstant:50.0],
        [self.runButton.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-12.0],
    ]];

    [self runProbes];
}

- (void)runProbes
{
    self.runButton.enabled = NO;
    self.stateLabel.text = @"Running JIT and Metal probes";
    self.stateLabel.textColor = [UIColor colorWithRed:0.96 green:0.71 blue:0.28 alpha:1.0];
    self.logView.text = @"";

    __weak ARMSX3ViewController* weakSelf = self;
    [ARMSX3FeasibilityProbe runWithUpdate:^(NSString* line) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ARMSX3ViewController* strongSelf = weakSelf;
            if (!strongSelf)
                return;
            NSString* existing = strongSelf.logView.text ?: @"";
            strongSelf.logView.text = [existing stringByAppendingFormat:@"%@\n", line];
            NSRange end = NSMakeRange(strongSelf.logView.text.length, 0);
            [strongSelf.logView scrollRangeToVisible:end];
        });
    } completion:^(BOOL passed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ARMSX3ViewController* strongSelf = weakSelf;
            if (!strongSelf)
                return;
            strongSelf.runButton.enabled = YES;
            strongSelf.stateLabel.text = passed ? @"PASS: iOS JIT + Metal/Vulkan" : @"FAIL: inspect probe output";
            strongSelf.stateLabel.textColor = passed
                ? [UIColor colorWithRed:0.30 green:0.85 blue:0.70 alpha:1.0]
                : [UIColor colorWithRed:1.0 green:0.36 blue:0.34 alpha:1.0];
        });
    }];
}

@end
