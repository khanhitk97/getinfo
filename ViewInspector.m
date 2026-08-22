#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - 1. OVERLAY UI & VALUE INSPECTOR

@interface DriverOverlayVC : UIViewController
@property (nonatomic, strong) UIView *orangeBar;
@property (nonatomic, strong) UILabel *feeLabel;
@property (nonatomic, strong) UILabel *noteLabel;
@property (nonatomic, strong) UITextView *inspectorBox;
@property (nonatomic, strong) UIButton *closeBtn;

- (void)showWithShip:(NSString *)ship bonus:(NSString *)bonus note:(NSString *)note;
- (void)hideOverlay;
- (void)logFieldInfo:(NSString *)info;
@end

static DriverOverlayVC *gOverlayVC = nil;

@implementation DriverOverlayVC

- (void)viewDidLoad {
    [super viewDidLoad];
    gOverlayVC = self;
    self.view.backgroundColor = [UIColor clearColor];
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;

    // Thanh cam 96pt
    self.orangeBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, sw, 96)];
    self.orangeBar.backgroundColor = [UIColor colorWithRed:0.96 green:0.35 blue:0.15 alpha:1.0];
    self.orangeBar.layer.shadowColor = [UIColor blackColor].CGColor;
    self.orangeBar.layer.shadowOpacity = 0.25;
    self.orangeBar.layer.shadowOffset = CGSizeMake(0, 2);
    self.orangeBar.layer.shadowRadius = 3.0;
    self.orangeBar.hidden = YES;
    [self.view addSubview:self.orangeBar];

    // Nút Đóng (✕)
    self.closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeBtn.frame = CGRectMake(sw - 40, 44, 30, 30);
    [self.closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [self.closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16.0];
    [self.closeBtn addTarget:self action:@selector(hideOverlay) forControlEvents:UIControlEventTouchUpInside];
    [self.orangeBar addSubview:self.closeBtn];

    // Dòng thông tin
    self.feeLabel = [[UILabel alloc] initWithFrame:CGRectMake(65, 44, sw - 115, 22)];
    self.feeLabel.textColor = [UIColor whiteColor];
    self.feeLabel.font = [UIFont boldSystemFontOfSize:12.5];
    self.feeLabel.text = @"🛵 Ship: -- | 🎁 Khích lệ: --";
    [self.orangeBar addSubview:self.feeLabel];

    self.noteLabel = [[UILabel alloc] initWithFrame:CGRectMake(65, 68, sw - 115, 24)];
    self.noteLabel.textColor = [UIColor yellowColor];
    self.noteLabel.font = [UIFont boldSystemFontOfSize:11.0];
    self.noteLabel.text = @"📌 Ghi chú: --";
    [self.orangeBar addSubview:self.noteLabel];

    // Bảng soi dữ liệu ở góc dưới
    self.inspectorBox = [[UITextView alloc] initWithFrame:CGRectMake(8, sh - 140, sw - 16, 85)];
    self.inspectorBox.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.9];
    self.inspectorBox.textColor = [UIColor greenColor];
    self.inspectorBox.font = [UIFont fontWithName:@"Courier-Bold" size:10.5] ?: [UIFont boldSystemFontOfSize:10.5];
    self.inspectorBox.editable = NO;
    self.inspectorBox.layer.cornerRadius = 6;
    self.inspectorBox.layer.borderWidth = 1;
    self.inspectorBox.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.3].CGColor;
    self.inspectorBox.text = @"[BẮT DỮ LIỆU ĐƠN HÀNG]\nMở đơn và bấm thẳng vào dòng 'Phí khích lệ' hoặc 'Phí ship'...";
    [self.view addSubview:self.inspectorBox];
}

- (void)logFieldInfo:(NSString *)info {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.inspectorBox.text = info;
        [UIPasteboard generalPasteboard].string = info;
    });
}

- (void)showWithShip:(NSString *)ship bonus:(NSString *)bonus note:(NSString *)note {
    self.feeLabel.text = [NSString stringWithFormat:@"🛵 Ship: %@ | 🎁 Khích lệ: %@", ship ?: @"--", bonus ?: @"0đ"];
    self.noteLabel.text = [NSString stringWithFormat:@"📌 Ghi chú: %@", note ?: @"--"];
    self.orangeBar.hidden = NO;
}

- (void)hideOverlay {
    self.orangeBar.hidden = YES;
}

@end

#pragma mark - 2. TRÍCH XUẤT DỮ LIỆU TỪ VIEW CHẠM

@interface DriverDataHandler : NSObject
+ (void)inspectDataOnTouch:(UIView *)v point:(CGPoint)pt;
@end

@implementation DriverDataHandler

+ (void)getAllTextsFromView:(UIView *)v list:(NSMutableArray<NSString *> *)list {
    if (!v) return;
    if (v.accessibilityLabel.length > 0) [list addObject:v.accessibilityLabel];
    
    @try {
        id t = [v valueForKey:@"text"];
        if ([t isKindOfClass:[NSString class]] && [(NSString *)t length] > 0) [list addObject:(NSString *)t];
    } @catch (NSException *e) {}

    @try {
        id at = [v valueForKey:@"attributedText"];
        if ([at isKindOfClass:[NSAttributedString class]] && [(NSAttributedString *)at string].length > 0) {
            [list addObject:[(NSAttributedString *)at string]];
        }
    } @catch (NSException *e) {}

    for (UIView *sub in v.subviews) {
        [self getAllTextsFromView:sub list:list];
    }
}

+ (void)inspectDataOnTouch:(UIView *)touchedView point:(CGPoint)pt {
    if (!touchedView) return;

    // 1. Nút Trở về (<) góc trái
    if (pt.x <= 75.0 && pt.y <= 95.0) {
        [gOverlayVC hideOverlay];
        return;
    }

    // 2. Thu thập text của chính View đó và View cha (Parent)
    NSMutableArray<NSString *> *selfTexts = [NSMutableArray array];
    [self getAllTextsFromView:touchedView list:selfTexts];

    NSMutableArray<NSString *> *parentTexts = [NSMutableArray array];
    if (touchedView.superview) {
        [self getAllTextsFromView:touchedView.superview list:parentTexts];
    }

    NSString *vClass = NSStringFromClass([touchedView class]);
    NSString *pClass = touchedView.superview ? NSStringFromClass([touchedView.superview class]) : @"nil";

    NSString *log = [NSString stringWithFormat:@"[CHẠM VIEW]: %@ | Cha: %@\n- Chữ tại View: %@\n- Chữ tại cụm Cha: %@",
                     vClass, pClass,
                     selfTexts.count > 0 ? [selfTexts componentsJoinedByString:@" ~ "] : @"(none)",
                     parentTexts.count > 0 ? [parentTexts componentsJoinedByString:@" ~ "] : @"(none)"];

    [gOverlayVC logFieldInfo:log];
}

@end

#pragma mark - 3. HOOK SEND EVENT

static void (*orig_sendEvent)(id, SEL, UIEvent *);
static void custom_sendEvent(UIApplication *self, SEL _cmd, UIEvent *event) {
    orig_sendEvent(self, _cmd, event);
    if (event.type == UIEventTypeTouches) {
        for (UITouch *t in event.allTouches) {
            if (t.phase == UITouchPhaseEnded) {
                CGPoint pt = [t locationInView:nil];
                [DriverDataHandler inspectDataOnTouch:t.view point:pt];
                break;
            }
        }
    }
}

@interface DriverOverlayWindow : UIWindow
@end

@implementation DriverOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self.rootViewController.view) return nil;

    if (point.x <= 75.0 && point.y <= 95.0) {
        [gOverlayVC hideOverlay];
        return nil;
    }
    return hitView;
}
@end

static DriverOverlayWindow *gDriverWindow = nil;

__attribute__((constructor))
static void dylib_start(void) {
    Class appClass = [UIApplication class];
    Method mSend = class_getInstanceMethod(appClass, @selector(sendEvent:));
    orig_sendEvent = (void(*)(id, SEL, UIEvent *))method_getImplementation(mSend);
    method_setImplementation(mSend, (IMP)custom_sendEvent);

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIWindowScene *scene = nil;
                if (@available(iOS 13.0, *)) {
                    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
                        if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) {
                            scene = (UIWindowScene *)s;
                            break;
                        }
                    }
                    if (scene) gDriverWindow = [[DriverOverlayWindow alloc] initWithWindowScene:scene];
                }
                if (!gDriverWindow) gDriverWindow = [[DriverOverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

                gDriverWindow.windowLevel = UIWindowLevelAlert + 1000.0;
                gDriverWindow.backgroundColor = [UIColor clearColor];
                DriverOverlayVC *vc = [[DriverOverlayVC alloc] init];
                gDriverWindow.rootViewController = vc;
                gDriverWindow.hidden = NO;
            });
        });
    }];
}
