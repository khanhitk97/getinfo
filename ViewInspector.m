#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - PHONE EXTRACTOR ENGINE

@interface PhoneInspectorEngine : NSObject
+ (NSArray<NSString *> *)extractPhoneNumbersFromTopMost;
+ (NSString *)scanTopMostViewHierarchy;
+ (void)forceRevealTopMost;
+ (UIViewController *)getTopMostViewController;
@end

@implementation PhoneInspectorEngine

// Regex nhận diện số điện thoại (bao gồm cả số thường và số bị mask dạng 090***1234)
+ (NSArray<NSString *> *)findPhonePatternsInString:(NSString *)text {
    if (!text || text.length < 8) return @[];
    
    NSMutableArray<NSString *> *results = [NSMutableArray array];
    
    // Pattern 1: Số điện thoại chuẩn VN/Quốc tế (+84|0)(3|5|7|8|9)[0-9\s.-]{7,12}
    // Pattern 2: Số điện thoại bị ẩn sao (VD: 090****123, 09*****888, +849****789)
    NSArray *patterns = @[
        @"(?:\\+84|0)[3|5|7|8|9][0-9\\s.-]{7,11}[0-9]",
        @"(?:\\+84|0)[3|5|7|8|9][0-9*\\s.-]{6,12}[0-9]"
    ];

    for (NSString *pattern in patterns) {
        NSError *error = nil;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                               options:NSRegularExpressionCaseInsensitive
                                                                                 error:&error];
        if (!error) {
            NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:text
                                                                      options:0
                                                                        range:NSMakeRange(0, text.length)];
            for (NSTextCheckingResult *match in matches) {
                NSString *matchStr = [text substringWithRange:match.range];
                // Loại bỏ khoảng trắng thừa
                NSString *cleanStr = [matchStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (cleanStr.length >= 9 && ![results containsObject:cleanStr]) {
                    [results addObject:cleanStr];
                }
            }
        }
    }
    
    return results;
}

// Bóc tách toàn bộ chuỗi text từ một View
+ (void)collectAllTextsFromView:(UIView *)view intoArray:(NSMutableArray<NSString *> *)textList {
    if (!view) return;
    
    @try {
        if ([view isKindOfClass:[UILabel class]]) {
            NSString *t = [(UILabel *)view text];
            if (t.length) [textList addObject:t];
        } else if ([view isKindOfClass:[UITextField class]]) {
            UITextField *tf = (UITextField *)view;
            if (tf.text.length) [textList addObject:tf.text];
            if (tf.placeholder.length) [textList addObject:tf.placeholder];
        } else if ([view isKindOfClass:[UITextView class]]) {
            NSString *t = [(UITextView *)view text];
            if (t.length) [textList addObject:t];
        } else if ([view isKindOfClass:[UIButton class]]) {
            NSString *t = [(UIButton *)view titleForState:UIControlStateNormal];
            if (t.length) [textList addObject:t];
        }
        
        // Bóc tách cả accessibilityLabel / accessibilityValue nếu dev giấu text vào đây
        if (view.accessibilityLabel.length) [textList addObject:view.accessibilityLabel];
        if (view.accessibilityValue.length) [textList addObject:view.accessibilityValue];
        
        for (UIView *sub in view.subviews) {
            [self collectAllTextsFromView:sub intoArray:textList];
        }
    } @catch (__unused NSException *e) {}
}

+ (NSArray<UIWindow *> *)getAllAppWindows {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
            }
        }
    }
    if (windows.count == 0) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [windows addObjectsFromArray:[UIApplication sharedApplication].windows];
        #pragma clang diagnostic pop
    }
    return windows;
}

+ (UIViewController *)topViewControllerFromRoot:(UIViewController *)root {
    if ([root isKindOfClass:[UINavigationController class]]) {
        return [self topViewControllerFromRoot:[(UINavigationController *)root visibleViewController]];
    }
    if ([root isKindOfClass:[UITabBarController class]]) {
        return [self topViewControllerFromRoot:[(UITabBarController *)root selectedViewController]];
    }
    if (root.presentedViewController) {
        return [self topViewControllerFromRoot:root.presentedViewController];
    }
    return root;
}

+ (UIViewController *)getTopMostViewController {
    NSArray<UIWindow *> *windows = [self getAllAppWindows];
    for (NSInteger i = windows.count - 1; i >= 0; i--) {
        UIWindow *w = windows[i];
        if (w.rootViewController && !w.isHidden && w.alpha > 0.05) {
            return [self topViewControllerFromRoot:w.rootViewController];
        }
    }
    return nil;
}

// 1. CHỨC NĂNG LẤY TRỰC TIẾP SỐ ĐIỆN THOẠI TẦNG CAO NHẤT
+ (NSArray<NSString *> *)extractPhoneNumbersFromTopMost {
    UIViewController *topVC = [self getTopMostViewController];
    if (!topVC) return @[];
    
    NSMutableArray<NSString *> *allTexts = [NSMutableArray array];
    [self collectAllTextsFromView:topVC.view intoArray:allTexts];
    
    NSMutableArray<NSString *> *foundPhones = [NSMutableArray array];
    for (NSString *str in allTexts) {
        NSArray<NSString *> *matches = [self findPhonePatternsInString:str];
        for (NSString *phone in matches) {
            if (![foundPhones containsObject:phone]) {
                [foundPhones addObject:phone];
            }
        }
    }
    return foundPhones;
}

// 2. Quét chi tiết cây UI phục vụ debug
+ (void)recursiveInspectView:(UIView *)view level:(int)level buffer:(NSMutableString *)buffer filterWindow:(UIWindow *)inspectorWin {
    if (!view || view == inspectorWin || [view isDescendantOfView:inspectorWin]) return;

    NSString *indent = [@"" stringByPaddingToLength:level * 2 withString:@"  " startingAtIndex:0];
    @try {
        BOOL isHidden = view.isHidden;
        BOOL isAlphaZero = view.alpha < 0.05;
        BOOL isLayerHidden = view.layer.hidden || view.layer.opacity < 0.05;
        
        NSMutableArray<NSString *> *texts = [NSMutableArray array];
        [self collectAllTextsFromView:view intoArray:texts];
        NSString *joinedText = [texts componentsJoinedByString:@" | "];

        if (isHidden || isAlphaZero || isLayerHidden || joinedText.length > 0) {
            [buffer appendFormat:@"%@• %@ | F:(%.0f,%.0f,%.0f,%.0f) | α:%.2f | Hide:[V:%d, L:%d] -> [%@]\n",
                indent,
                NSStringFromClass([view class]),
                view.frame.origin.x, view.frame.origin.y, view.frame.size.width, view.frame.size.height,
                view.alpha,
                isHidden, isLayerHidden,
                joinedText];
        }

        for (UIView *sub in view.subviews) {
            [self recursiveInspectView:sub level:level + 1 buffer:buffer filterWindow:inspectorWin];
        }
    } @catch (__unused NSException *e) {}
}

+ (NSString *)scanTopMostViewHierarchy {
    NSMutableString *buf = [NSMutableString stringWithCapacity:4096];
    UIViewController *topVC = [self getTopMostViewController];
    if (topVC) {
        [buf appendFormat:@"=== CHI TIẾT GIAO DIỆN CAO NHẤT ===\n"];
        [buf appendFormat:@"[VC: %@ | Title: \"%@\"]\n\n", NSStringFromClass([topVC class]), topVC.title ?: @"None"];
        [self recursiveInspectView:topVC.view level:0 buffer:buf filterWindow:nil];
    } else {
        [buf appendString:@"Không tìm thấy ViewController nào đang active."];
    }
    return buf;
}

+ (void)forceUnhideRecursive:(UIView *)view {
    if (!view) return;
    @try {
        view.hidden = NO;
        view.alpha = 1.0;
        view.layer.hidden = NO;
        view.layer.opacity = 1.0;
        view.clipsToBounds = NO;
        if ([view isKindOfClass:[UITextField class]]) {
            ((UITextField *)view).secureTextEntry = NO;
        }
        for (UIView *sub in view.subviews) {
            [self forceUnhideRecursive:sub];
        }
    } @catch (__unused NSException *e) {}
}

+ (void)forceRevealTopMost {
    UIViewController *topVC = [self getTopMostViewController];
    if (topVC) {
        [self forceUnhideRecursive:topVC.view];
    }
}

@end

#pragma mark - FLOATING UI OVERLAY

@interface PhoneInspectorVC : UIViewController
@property (nonatomic, strong) UIButton *bubbleBtn;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation PhoneInspectorVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    // 1. Bong bóng nổi (AssistiveTouch)
    self.bubbleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.bubbleBtn.frame = CGRectMake(15, 120, 62, 62);
    self.bubbleBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:0.90];
    [self.bubbleBtn setTitle:@"📱 Phone" forState:UIControlStateNormal];
    [self.bubbleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.bubbleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    self.bubbleBtn.layer.cornerRadius = 31;
    self.bubbleBtn.layer.borderWidth = 2.0;
    self.bubbleBtn.layer.borderColor = [UIColor whiteColor].CGColor;
    self.bubbleBtn.layer.shadowColor = [UIColor blackColor].CGColor;
    self.bubbleBtn.layer.shadowOpacity = 0.5;
    self.bubbleBtn.layer.shadowOffset = CGSizeMake(0, 3);
    self.bubbleBtn.layer.shadowRadius = 4;
    [self.bubbleBtn addTarget:self action:@selector(openPanel) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *bubblePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleBubblePan:)];
    [self.bubbleBtn addGestureRecognizer:bubblePan];
    [self.view addSubview:self.bubbleBtn];

    // 2. Bảng điều khiển chính
    CGFloat w = [UIScreen mainScreen].bounds.size.width;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(10, 80, w - 20, 380)];
    self.panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.95];
    self.panel.layer.cornerRadius = 14;
    self.panel.layer.borderWidth = 1.2;
    self.panel.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:1.0].CGColor;
    self.panel.clipsToBounds = YES;
    self.panel.hidden = YES;
    [self.view addSubview:self.panel];

    UIPanGestureRecognizer *panelPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanelPan:)];
    [self.panel addGestureRecognizer:panelPan];

    // Nút chức năng
    UIButton *getPhoneBtn = [self createBtn:@"⚡ Lấy SĐT" color:[UIColor systemGreenColor] frame:CGRectMake(8, 10, 85, 32) action:@selector(runGetPhone)];
    UIButton *dumpBtn = [self createBtn:@"Cây UI" color:[UIColor systemBlueColor] frame:CGRectMake(98, 10, 65, 32) action:@selector(runDumpUI)];
    UIButton *unhideBtn = [self createBtn:@"Unhide" color:[UIColor systemOrangeColor] frame:CGRectMake(168, 10, 65, 32) action:@selector(runUnhide)];
    UIButton *copyBtn = [self createBtn:@"Copy" color:[UIColor systemIndigoColor] frame:CGRectMake(238, 10, 50, 32) action:@selector(copyLog)];
    UIButton *closeBtn = [self createBtn:@"✕" color:[UIColor systemRedColor] frame:CGRectMake(self.panel.frame.size.width - 45, 10, 38, 32) action:@selector(closePanel)];

    [self.panel addSubview:getPhoneBtn];
    [self.panel addSubview:dumpBtn];
    [self.panel addSubview:unhideBtn];
    [self.panel addSubview:copyBtn];
    [self.panel addSubview:closeBtn];

    // Thanh trạng thái nhỏ
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 48, self.panel.frame.size.width - 20, 20)];
    self.statusLabel.textColor = [UIColor yellowColor];
    self.statusLabel.font = [UIFont boldSystemFontOfSize:11];
    self.statusLabel.text = @"Sẵn sàng quét số điện thoại...";
    [self.panel addSubview:self.statusLabel];

    // Text View log kết quả
    self.textView = [[UITextView alloc] initWithFrame:CGRectMake(8, 72, self.panel.frame.size.width - 16, 298)];
    self.textView.backgroundColor = [UIColor colorWithWhite:0.04 alpha:1.0];
    self.textView.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:1.0];
    self.textView.font = [UIFont fontWithName:@"Menlo" size:11];
    self.textView.editable = NO;
    self.textView.layer.cornerRadius = 6;
    [self.panel addSubview:self.textView];
}

- (UIButton *)createBtn:(NSString *)title color:(UIColor *)color frame:(CGRect)frame action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = frame;
    [btn setTitle:title forState:UIControlStateNormal];
    btn.backgroundColor = color;
    btn.tintColor = [UIColor whiteColor];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    btn.layer.cornerRadius = 6;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)handleBubblePan:(UIPanGestureRecognizer *)p {
    CGPoint trans = [p translationInView:self.view];
    self.bubbleBtn.center = CGPointMake(self.bubbleBtn.center.x + trans.x, self.bubbleBtn.center.y + trans.y);
    [p setTranslation:CGPointZero inView:self.view];
}

- (void)handlePanelPan:(UIPanGestureRecognizer *)p {
    CGPoint trans = [p translationInView:self.view];
    self.panel.center = CGPointMake(self.panel.center.x + trans.x, self.panel.center.y + trans.y);
    [p setTranslation:CGPointZero inView:self.view];
}

- (void)openPanel {
    self.bubbleBtn.hidden = YES;
    self.panel.hidden = NO;
    [self runGetPhone];
}

- (void)closePanel {
    self.panel.hidden = YES;
    self.bubbleBtn.hidden = NO;
}

- (void)runGetPhone {
    NSArray<NSString *> *phones = [PhoneInspectorEngine extractPhoneNumbersFromTopMost];
    UIViewController *topVC = [PhoneInspectorEngine getTopMostViewController];
    
    NSMutableString *res = [NSMutableString stringWithFormat:@"=== SỐ ĐIỆN THOẠI TÌM THẤY TRÊN MÀN HÌNH ===\n"];
    [res appendFormat:@"[Cửa sổ cao nhất: %@]\n\n", NSStringFromClass([topVC class])];
    
    if (phones.count > 0) {
        self.statusLabel.text = [NSString stringWithFormat:@"Tìm thấy %lu số điện thoại!", (unsigned long)phones.count];
        for (NSUInteger i = 0; i < phones.count; i++) {
            [res appendFormat:@"[%lu]  👉 %@\n", (unsigned long)(i + 1), phones[i]];
        }
        [res appendString:@"\n(Bấm nút 'Copy' để sao chép kết quả)"];
    } else {
        self.statusLabel.text = @"Không tìm thấy số điện thoại nào.";
        [res appendString:@"⚠️ Không phát hiện số điện thoại nào trên giao diện hiện tại.\n\nThử bấm 'Unhide' rồi bấm lại '⚡ Lấy SĐT' hoặc bấm 'Cây UI' để xem chi tiết."];
    }
    
    self.textView.text = res;
}

- (void)runDumpUI {
    self.statusLabel.text = @"Đang xem chi tiết cây UI...";
    self.textView.text = [PhoneInspectorEngine scanTopMostViewHierarchy];
}

- (void)runUnhide {
    [PhoneInspectorEngine forceRevealTopMost];
    self.statusLabel.text = @"Đã Unhide toàn bộ view trên màn hình cao nhất.";
    [self runGetPhone];
}

- (void)copyLog {
    [UIPasteboard generalPasteboard].string = self.textView.text ?: @"";
    self.statusLabel.text = @"Đã sao chép vào Clipboard!";
}

@end

#pragma mark - WINDOW INJECTION

@interface SafePhoneWindow : UIWindow
@end

@implementation SafePhoneWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self.rootViewController.view) return nil;
    return hit;
}
@end

static SafePhoneWindow *gPhoneWindow = nil;

static void showPhoneInspector(void) {
    if (gPhoneWindow) return;

    UIWindowScene *activeScene = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) {
                activeScene = (UIWindowScene *)s;
                break;
            }
        }
    }

    if (@available(iOS 13.0, *) && activeScene) {
        gPhoneWindow = [[SafePhoneWindow alloc] initWithWindowScene:activeScene];
    } else {
        gPhoneWindow = [[SafePhoneWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }

    gPhoneWindow.windowLevel = UIWindowLevelAlert + 1000.0;
    gPhoneWindow.backgroundColor = [UIColor clearColor];
    
    PhoneInspectorVC *vc = [[PhoneInspectorVC alloc] init];
    gPhoneWindow.rootViewController = vc;
    gPhoneWindow.hidden = NO;
}

__attribute__((constructor))
static void dylib_main(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                showPhoneInspector();
            });
        });
    }];
}
