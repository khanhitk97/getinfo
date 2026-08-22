#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - 1. OVERLAY UI & DEEP INSPECTOR

@interface DriverOverlayVC : UIViewController
@property (nonatomic, strong) UIView *orangeBar;
@property (nonatomic, strong) UILabel *infoLabel;
@property (nonatomic, strong) UILabel *noteLabel;
@property (nonatomic, strong) UIButton *zaloBtn;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) UITextView *inspectorBox;
@property (nonatomic, strong) NSString *currentPhone;
@property (nonatomic, assign) BOOL isShowing;

- (void)showWithShipFee:(NSString *)ship bonus:(NSString *)bonus note:(NSString *)note phone:(NSString *)phone;
- (void)hideOverlay;
- (void)displayLog:(NSString *)log;
@end

static DriverOverlayVC *gOverlayVC = nil;

@implementation DriverOverlayVC

- (void)viewDidLoad {
    [super viewDidLoad];
    gOverlayVC = self;
    self.view.backgroundColor = [UIColor clearColor];
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;

    // Thanh Header cam 96pt
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

    // Bảng Inspector nổi ở đáy màn hình (Hiển thị 4 dòng chi tiết)
    self.inspectorBox = [[UITextView alloc] initWithFrame:CGRectMake(8, sh - 135, sw - 16, 75)];
    self.inspectorBox.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.88];
    self.inspectorBox.textColor = [UIColor cyanColor];
    self.inspectorBox.font = [UIFont fontWithName:@"Courier-Bold" size:10.0] ?: [UIFont boldSystemFontOfSize:10.0];
    self.inspectorBox.editable = NO;
    self.inspectorBox.layer.cornerRadius = 6;
    self.inspectorBox.layer.borderWidth = 1;
    self.inspectorBox.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.3].CGColor;
    self.inspectorBox.text = @"[DEEP INSPECTOR READY]\nChạm vào bất kỳ nút/đơn hàng nào để lấy toàn bộ mã...";
    [self.view addSubview:self.inspectorBox];
}

- (void)displayLog:(NSString *)log {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.inspectorBox.text = log;
        [UIPasteboard generalPasteboard].string = log; // Tự động copy toàn bộ log chi tiết vào Clipboard
    });
}

- (void)showWithShipFee:(NSString *)ship bonus:(NSString *)bonus note:(NSString *)note phone:(NSString *)phone {
    self.isShowing = YES;
    self.currentPhone = phone;
    self.infoLabel.text = [NSString stringWithFormat:@"🛵 Ship: %@ | 🎁 Khích lệ: %@", ship ?: @"--", bonus ?: @"0đ"];
    self.noteLabel.text = [NSString stringWithFormat:@"📌 Ghi chú: %@", note ?: @"Không có ghi chú"];
    self.orangeBar.hidden = NO;
}

- (void)hideOverlay {
    self.isShowing = NO;
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

#pragma mark - 2. BỘ PHÂN TÍCH VÙNG NHỚ VÀ VIEW REACT NATIVE

@interface DriverDataHandler : NSObject
+ (void)inspectTouch:(UIView *)touchedView point:(CGPoint)pt;
+ (BOOL)isHomeScreenActive;
@end

@implementation DriverDataHandler

+ (UIWindow *)getMainAppWindow {
    UIWindow *mainWin = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)s).windows) {
                    if (!w.isHidden && ![NSStringFromClass([w class]) containsString:@"DriverOverlayWindow"]) {
                        mainWin = w;
                        break;
                    }
                }
            }
        }
    }
    if (!mainWin) mainWin = [UIApplication sharedApplication].windows.firstObject;
    return mainWin;
}

+ (void)extractSubstringsFromView:(UIView *)v list:(NSMutableArray<NSString *> *)list {
    if (!v) return;
    if (v.accessibilityLabel.length > 0) [list addObject:v.accessibilityLabel];
    @try {
        id t = [v valueForKey:@"text"];
        if ([t isKindOfClass:[NSString class]] && [(NSString *)t length] > 0) [list addObject:(NSString *)t];
    } @catch (NSException *e) {}

    for (UIView *sub in v.subviews) {
        [self extractSubstringsFromView:sub list:list];
    }
}

// Kiểm tra Màn hình chính dựa trên từ khóa dịch vụ
+ (BOOL)checkHomeKeywordsInView:(UIView *)v {
    if (!v || v.hidden || v.alpha < 0.1) return NO;

    NSString *acc = v.accessibilityLabel.lowercaseString;
    if ([acc containsString:@"ăn uống"] || [acc containsString:@"giao hàng"] || [acc containsString:@"xe ôm"] || [acc containsString:@"an uong"] || [acc containsString:@"xe om"]) {
        return YES;
    }

    @try {
        id textVal = [v valueForKey:@"text"];
        if ([textVal isKindOfClass:[NSString class]]) {
            NSString *t = [(NSString *)textVal lowercaseString];
            if ([t containsString:@"ăn uống"] || [t containsString:@"giao hàng"] || [t containsString:@"xe ôm"] || [t containsString:@"an uong"] || [t containsString:@"xe om"]) {
                return YES;
            }
        }
    } @catch (NSException *e) {}

    for (UIView *sub in v.subviews) {
        if (![NSStringFromClass([sub class]) containsString:@"Driver"]) {
            if ([self checkHomeKeywordsInView:sub]) return YES;
        }
    }
    return NO;
}

+ (BOOL)isHomeScreenActive {
    UIWindow *win = [self getMainAppWindow];
    return [self checkHomeKeywordsInView:win];
}

+ (void)inspectTouch:(UIView *)touchedView point:(CGPoint)pt {
    if (!touchedView) return;

    NSString *className = NSStringFromClass([touchedView class]);
    NSString *accLabel = touchedView.accessibilityLabel ?: @"(none)";
    
    // 1. Gom toàn bộ text con nằm trong View vừa chạm
    NSMutableArray<NSString *> *childTexts = [NSMutableArray array];
    [self extractSubstringsFromView:touchedView list:childTexts];
    NSString *joinedTexts = childTexts.count > 0 ? [childTexts componentsJoinedByString:@" | "] : @"(none)";

    // 2. Lấy thông tin lớp cha (Parent View)
    NSString *parentName = touchedView.superview ? NSStringFromClass([touchedView.superview class]) : @"nil";

    // 3. Định dạng log xuất ra màn hình & clipboard
    NSString *fullLog = [NSString stringWithFormat:@"[PT: (%.0f, %.0f)] View: %@\nParent: %@ | Acc: %@\nInner Texts: %@",
                         pt.x, pt.y, className, parentName, accLabel, joinedTexts];
    
    [gOverlayVC displayLog:fullLog];

    // Xử lý góc trái (Nút Back)
    if (pt.x <= 85.0 && pt.y <= 105.0) {
        [gOverlayVC hideOverlay];
        return;
    }

    // Tự động kiểm tra nếu đã quay về màn hình chính
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([self isHomeScreenActive]) {
            [gOverlayVC hideOverlay];
        }
    });

    // =========================================================================
    // KHU VỰC TRUY XUẤT DỮ LIỆU CỐ ĐỊNH (SẼ ĐIỀN SAU KHI CÓ LOG BẠN GỬI)
    // =========================================================================
    /*
    if ([className containsString:@"..."] || [joinedTexts containsString:@"..."]) {
        [gOverlayVC showWithShipFee:@"..." bonus:@"..." note:@"..." phone:@"..."];
    }
    */
}

@end

#pragma mark - 3. HOOK SEND EVENT & OVERLAY WINDOW

static void (*orig_sendEvent)(id, SEL, UIEvent *);
static void custom_sendEvent(UIApplication *self, SEL _cmd, UIEvent *event) {
    orig_sendEvent(self, _cmd, event);
    if (event.type == UIEventTypeTouches) {
        for (UITouch *t in event.allTouches) {
            if (t.phase == UITouchPhaseEnded) {
                CGPoint pt = [t locationInView:nil];
                [DriverDataHandler inspectTouch:t.view point:pt];
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
