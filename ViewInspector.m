#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - 1. OVERLAY UI & LIVE TOUCH INSPECTOR

@interface DriverOverlayVC : UIViewController
@property (nonatomic, strong) UIView *orangeBar;
@property (nonatomic, strong) UILabel *infoLabel;
@property (nonatomic, strong) UILabel *noteLabel;
@property (nonatomic, strong) UIButton *zaloBtn;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) UITextView *inspectorBox; // Bảng hiển thị thông số chạm
@property (nonatomic, strong) NSString *currentPhone;

- (void)showWithShipFee:(NSString *)ship bonus:(NSString *)bonus note:(NSString *)note phone:(NSString *)phone;
- (void)hideOverlay;
- (void)displayTouchInfo:(NSString *)info;
@end

static DriverOverlayVC *gOverlayVC = nil;

@implementation DriverOverlayVC

- (void)viewDidLoad {
    [super viewDidLoad];
    gOverlayVC = self;
    self.view.backgroundColor = [UIColor clearColor];
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;

    // 1. Thanh Header cam 96pt (Mặc định ẩn)
    self.orangeBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, sw, 96)];
    self.orangeBar.backgroundColor = [UIColor colorWithRed:0.96 green:0.35 blue:0.15 alpha:1.0];
    self.orangeBar.layer.shadowColor = [UIColor blackColor].CGColor;
    self.orangeBar.layer.shadowOpacity = 0.25;
    self.orangeBar.layer.shadowOffset = CGSizeMake(0, 2);
    self.orangeBar.layer.shadowRadius = 3.0;
    self.orangeBar.hidden = YES;
    [self.view addSubview:self.orangeBar];

    // Nút Zalo
    self.zaloBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.zaloBtn.frame = CGRectMake(sw - 72, 44, 64, 26);
    self.zaloBtn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.25];
    [self.zaloBtn setTitle:@"💬 Zalo" forState:UIControlStateNormal];
    [self.zaloBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.zaloBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
    self.zaloBtn.layer.cornerRadius = 13;
    self.zaloBtn.layer.borderWidth = 0.8;
    self.zaloBtn.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.zaloBtn addTarget:self action:@selector(openZalo) forControlEvents:UIControlEventTouchUpInside];
    [self.orangeBar addSubview:self.zaloBtn];

    // Nút Đóng (✕)
    self.closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeBtn.frame = CGRectMake(sw - 104, 44, 26, 26);
    [self.closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [self.closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15.0];
    [self.closeBtn addTarget:self action:@selector(hideOverlay) forControlEvents:UIControlEventTouchUpInside];
    [self.orangeBar addSubview:self.closeBtn];

    // Dòng thông tin Phí Ship & Khích Lệ
    self.infoLabel = [[UILabel alloc] initWithFrame:CGRectMake(65, 44, sw - 175, 22)];
    self.infoLabel.textColor = [UIColor whiteColor];
    self.infoLabel.font = [UIFont boldSystemFontOfSize:13.0];
    self.infoLabel.text = @"🛵 Ship: -- | 🎁 0đ";
    [self.orangeBar addSubview:self.infoLabel];

    // Dòng Ghi chú
    self.noteLabel = [[UILabel alloc] initWithFrame:CGRectMake(65, 68, sw - 145, 24)];
    self.noteLabel.textColor = [UIColor yellowColor];
    self.noteLabel.font = [UIFont boldSystemFontOfSize:11.0];
    self.noteLabel.text = @"📌 Ghi chú: --";
    [self.orangeBar addSubview:self.noteLabel];

    // 2. BẢNG HIỂN THỊ THÔNG SỐ CHẠM (Nổi ở đáy màn hình)
    self.inspectorBox = [[UITextView alloc] initWithFrame:CGRectMake(10, sh - 110, sw - 20, 55)];
    self.inspectorBox.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.85];
    self.inspectorBox.textColor = [UIColor cyanColor];
    self.inspectorBox.font = [UIFont fontWithName:@"Courier-Bold" size:10.5] ?: [UIFont boldSystemFontOfSize:10.5];
    self.inspectorBox.editable = NO;
    self.inspectorBox.layer.cornerRadius = 6;
    self.inspectorBox.layer.borderWidth = 1;
    self.inspectorBox.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.3].CGColor;
    self.inspectorBox.text = @"[INSPECTOR] Chạm vào đơn hàng hoặc nút Back để lấy thông số...";
    [self.view addSubview:self.inspectorBox];
}

- (void)displayTouchInfo:(NSString *)info {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.inspectorBox.text = info;
        [UIPasteboard generalPasteboard].string = info; // Tự động chép vào Clipboard
    });
}

- (void)showWithShipFee:(NSString *)ship bonus:(NSString *)bonus note:(NSString *)note phone:(NSString *)phone {
    self.currentPhone = phone;
    self.infoLabel.text = [NSString stringWithFormat:@"🛵 Ship: %@ | 🎁 Khích lệ: %@", ship ?: @"--", bonus ?: @"0đ"];
    self.noteLabel.text = [NSString stringWithFormat:@"📌 Ghi chú: %@", note ?: @"Không có ghi chú"];
    self.orangeBar.hidden = NO;
}

- (void)hideOverlay {
    self.orangeBar.hidden = YES;
}

- (void)openZalo {
    if (self.currentPhone.length >= 10) {
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://zalo.me/%@", self.currentPhone]];
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"zalo://"] options:@{} completionHandler:nil];
    }
}

@end

#pragma mark - 2. KHU VỰC BẮT MÃ VIEW VÀ BÓC TÁCH DỮ LIỆU

@interface DriverDataHandler : NSObject
+ (void)processTouchOnView:(UIView *)touchedView atPoint:(CGPoint)pt;
@end

@implementation DriverDataHandler

+ (void)processTouchOnView:(UIView *)touchedView atPoint:(CGPoint)pt {
    NSString *className = NSStringFromClass([touchedView class]);
    NSString *accLabel = touchedView.accessibilityLabel ?: @"(none)";
    
    // Lấy nội dung text nếu có
    NSString *viewText = @"";
    @try {
        id t = [touchedView valueForKey:@"text"];
        if ([t isKindOfClass:[NSString class]]) viewText = (NSString *)t;
    } @catch (NSException *e) {}

    // Tạo chuỗi thông tin hiển thị lên màn hình
    NSString *info = [NSString stringWithFormat:@"Tọa độ: (X:%.0f, Y:%.0f)\nClass: %@\nAccLabel: %@ | Text: %@", 
                      pt.x, pt.y, className, accLabel, viewText.length > 0 ? viewText : @"(none)"];
    
    [gOverlayVC displayTouchInfo:info];

    // =========================================================================
    // ĐIỀU KIỆN 1: BẤM VÀO NÚT BACK (GÓC TRÁI) -> ẨN THANH CAM
    // =========================================================================
    if (pt.x <= 85.0 && pt.y <= 105.0) {
        [gOverlayVC hideOverlay];
        return;
    }

    // =========================================================================
    // ĐIỀU KIỆN 2: KHI BẠN CHẠM VÀO ĐƠN HÀNG
    // Sau khi có Class / AccLabel từ bảng hiển thị, bạn điền vào đây:
    // =========================================================================
    /*
    if ([className containsString:@"..."] || [accLabel containsString:@"..."]) {
        [gOverlayVC showWithShipFee:@"18.000đ" bonus:@"0đ" note:@"Ghi chú mẫu" phone:@"0901234567"];
    }
    */
}

@end

#pragma mark - 3. HOOK SỰ KIỆN TOUCH & OVERLAY WINDOW

static void (*orig_sendEvent)(id, SEL, UIEvent *);
static void custom_sendEvent(UIApplication *self, SEL _cmd, UIEvent *event) {
    orig_sendEvent(self, _cmd, event);
    if (event.type == UIEventTypeTouches) {
        for (UITouch *t in event.allTouches) {
            if (t.phase == UITouchPhaseEnded) {
                CGPoint pt = [t locationInView:nil];
                [DriverDataHandler processTouchOnView:t.view atPoint:pt];
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

    // Đục lỗ góc trái (X: 0 -> 85, Y: 0 -> 105) để bấm Back app gốc
    if (point.x <= 85.0 && point.y <= 105.0) {
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
