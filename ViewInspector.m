#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - ENGINE TRÍCH XUẤT THEO TỪNG CỬA SỔ

@interface WindowInspectorEngine : NSObject
+ (NSArray<UIWindow *> *)getAllAllWindows;
+ (NSString *)inspectSpecificWindow:(UIWindow *)window;
+ (NSArray<NSString *> *)extractPhonesFromWindow:(UIWindow *)window;
@end

@implementation WindowInspectorEngine

+ (NSArray<UIWindow *> *)getAllAllWindows {
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

    // Lọc bỏ chính Window của Inspector ra khỏi danh sách
    NSMutableArray<UIWindow *> *filtered = [NSMutableArray array];
    for (UIWindow *w in windows) {
        if (![NSStringFromClass([w class]) containsString:@"InspectorOverlayWindow"]) {
            [filtered addObject:w];
        }
    }
    return filtered;
}

// Regex bắt SĐT
+ (NSArray<NSString *> *)findPhoneNumbers:(NSString *)text {
    if (!text || text.length < 8) return @[];
    NSMutableArray<NSString *> *results = [NSMutableArray array];
    NSArray *patterns = @[
        @"(?:\\+84|0)[3|5|7|8|9][0-9\\s.-]{7,11}[0-9]",
        @"(?:\\+84|0)[3|5|7|8|9][0-9*\\s.-]{6,12}[0-9]",
        @"tel(?:prompt)?:\\/?\\/?([0-9+*]+)"
    ];

    for (NSString *pat in patterns) {
        NSError *err = nil;
        NSRegularExpression *reg = [NSRegularExpression regularExpressionWithPattern:pat options:NSRegularExpressionCaseInsensitive error:&err];
        if (!err) {
            NSArray<NSTextCheckingResult *> *matches = [reg matchesInString:text options:0 range:NSMakeRange(0, text.length)];
            for (NSTextCheckingResult *m in matches) {
                NSRange r = (m.numberOfRanges > 1 && [pat containsString:@"tel"]) ? [m rangeAtIndex:1] : m.range;
                NSString *matchStr = [text substringWithRange:r];
                NSString *clean = [[matchStr stringByReplacingOccurrencesOfString:@" " withString:@""]
                                   stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (clean.length >= 9 && ![results containsObject:clean]) {
                    [results addObject:clean];
                }
            }
        }
    }
    return results;
}

// Quét toàn bộ Text & Ivar đệ quy trong 1 Window cụ thể
+ (void)recursiveScanView:(UIView *)view level:(int)level textList:(NSMutableArray<NSString *> *)textList detailsBuffer:(NSMutableString *)detailsBuffer {
    if (!view) return;

    NSString *indent = [@"" stringByPaddingToLength:level * 2 withString:@"  " startingAtIndex:0];
    NSString *ptrStr = [NSString stringWithFormat:@"%p", view];
    NSMutableString *viewTexts = [NSMutableString string];

    @try {
        if ([view isKindOfClass:[UILabel class]]) {
            UILabel *lbl = (UILabel *)view;
            if (lbl.text) [viewTexts appendFormat:@"[Label: \"%@\"] ", lbl.text];
            if (lbl.attributedText.string) [viewTexts appendFormat:@"[Attr: \"%@\"] ", lbl.attributedText.string];
        } else if ([view isKindOfClass:[UITextField class]]) {
            UITextField *tf = (UITextField *)view;
            if (tf.text) [viewTexts appendFormat:@"[TF: \"%@\" | Sec: %d] ", tf.text, tf.isSecureTextEntry];
            if (tf.placeholder) [viewTexts appendFormat:@"[Holder: \"%@\"] ", tf.placeholder];
        } else if ([view isKindOfClass:[UITextView class]]) {
            UITextView *tv = (UITextView *)view;
            if (tv.text) [viewTexts appendFormat:@"[TV: \"%@\"] ", tv.text];
        } else if ([view isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)view;
            NSString *t = [btn titleForState:UIControlStateNormal];
            if (t) [viewTexts appendFormat:@"[Btn: \"%@\"] ", t];
        }

        if (view.accessibilityLabel.length) [viewTexts appendFormat:@"[A11y: \"%@\"] ", view.accessibilityLabel];
        if (view.accessibilityValue.length) [viewTexts appendFormat:@"[A11yVal: \"%@\"] ", view.accessibilityValue];

        // Quét Ivars của chính View
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList([view class], &count);
        if (ivars) {
            for (unsigned int i = 0; i < count; i++) {
                const char *type = ivar_getTypeEncoding(ivars[i]);
                if (type && type[0] == '@') {
                    @try {
                        id val = object_getIvar(view, ivars[i]);
                        if ([val isKindOfClass:[NSString class]] && [(NSString *)val length] > 0 && [(NSString *)val length] < 120) {
                            [viewTexts appendFormat:@"[Ivar_%s: \"%@\"] ", ivar_getName(ivars[i]), val];
                        }
                    } @catch (__unused NSException *e) {}
                }
            }
            free(ivars);
        }

        if (viewTexts.length > 0) {
            [textList addObject:viewTexts];
            [detailsBuffer appendFormat:@"%@• <%@: %@> | F: %@ | Hide: %d -> %@\n", 
                indent, NSStringFromClass([view class]), ptrStr, NSStringFromCGRect(view.frame), view.isHidden, viewTexts];
        }

        for (UIView *sub in view.subviews) {
            [self recursiveScanView:sub level:level + 1 textList:textList detailsBuffer:detailsBuffer];
        }
    } @catch (__unused NSException *e) {}
}

+ (NSString *)inspectSpecificWindow:(UIWindow *)window {
    if (!window) return @"Không tìm thấy cửa sổ này.";

    NSMutableString *buf = [NSMutableString string];
    [buf appendFormat:@"=== CHI TIẾT CỬA SỔ ĐANG CHỌN ===\n"];
    [buf appendFormat:@"• Class: %@\n", NSStringFromClass([window class])];
    [buf appendFormat:@"• Mã địa chỉ (Pointer): %p\n", window];
    [buf appendFormat:@"• Level Window: %.1f\n", window.windowLevel];
    [buf appendFormat:@"• Kích thước: %@\n", NSStringFromCGRect(window.frame)];
    [buf appendFormat:@"• Root VC: <%@: %p>\n", NSStringFromClass([window.rootViewController class]), window.rootViewController];
    [buf appendString:@"-------------------------------------------\n\n"];

    NSMutableArray<NSString *> *textList = [NSMutableArray array];
    NSMutableString *details = [NSMutableString string];
    [self recursiveScanView:window level:0 textList:textList detailsBuffer:details];

    // Trích xuất SĐT tìm được riêng trong window này
    NSMutableSet<NSString *> *phones = [NSMutableSet set];
    for (NSString *str in textList) {
        for (NSString *p in [self findPhoneNumbers:str]) {
            [phones addObject:p];
        }
    }

    [buf appendFormat:@"📱 SỐ ĐIỆN THOẠI TÌM THẤY TRONG CỬA SỔ NÀY (%lu):\n", (unsigned long)phones.count];
    if (phones.count > 0) {
        for (NSString *p in phones) {
            [buf appendFormat:@"  👉 %@\n", p];
        }
    } else {
        [buf appendString:@"  (Không có SĐT trong cửa sổ này)\n"];
    }
    [buf appendString:@"\n--- CÂY DỮ LIỆU VIEW & IVAR ---\n"];
    [buf appendString:details.length > 0 ? details : @"(Cửa sổ này trống hoặc không có text)"];

    return buf;
}

+ (NSArray<NSString *> *)extractPhonesFromWindow:(UIWindow *)window {
    if (!window) return @[];
    NSMutableArray<NSString *> *textList = [NSMutableArray array];
    NSMutableString *dump = [NSMutableString string];
    [self recursiveScanView:window level:0 textList:textList detailsBuffer:dump];
    
    NSMutableSet<NSString *> *phones = [NSMutableSet set];
    for (NSString *str in textList) {
        for (NSString *p in [self findPhoneNumbers:str]) {
            [phones addObject:p];
        }
    }
    return [phones allObjects];
}

@end

#pragma mark - UI BẢNG ĐIỀU KHIỂN & CHỌN CỬA SỔ

@interface WindowInspectorVC : UIViewController
@property (nonatomic, strong) UIButton *bubbleBtn;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UILabel *windowInfoLabel;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) NSArray<UIWindow *> *windowList;
@property (nonatomic, assign) NSInteger currentWindowIndex;
@property (nonatomic, strong) UIView *highlightBorder;
@end

@implementation WindowInspectorVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    // 1. Bong bóng mở panel
    self.bubbleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.bubbleBtn.frame = CGRectMake(15, 120, 62, 62);
    self.bubbleBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:0.92];
    [self.bubbleBtn setTitle:@"🪟 Win" forState:UIControlStateNormal];
    [self.bubbleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.bubbleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.bubbleBtn.layer.cornerRadius = 31;
    self.bubbleBtn.layer.borderWidth = 2.0;
    self.bubbleBtn.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.bubbleBtn addTarget:self action:@selector(openPanel) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *panB = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanBubble:)];
    [self.bubbleBtn addGestureRecognizer:panB];
    [self.view addSubview:self.bubbleBtn];

    // 2. Bảng điều khiển chính
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(10, 70, screenW - 20, 430)];
    self.panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.96];
    self.panel.layer.cornerRadius = 14;
    self.panel.layer.borderWidth = 1.2;
    self.panel.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:1.0].CGColor;
    self.panel.clipsToBounds = YES;
    self.panel.hidden = YES;
    [self.view addSubview:self.panel];

    UIPanGestureRecognizer *panP = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanPanel:)];
    [self.panel addGestureRecognizer:panP];

    // Hàng 1: Nút chuyển Cửa sổ (< Prev, Next >) và Đóng
    UIButton *prevBtn = [self makeBtn:@"◀ Cửa sổ trước" color:[UIColor colorWithWhite:0.25 alpha:1.0] frame:CGRectMake(8, 8, 105, 30) action:@selector(prevWindow)];
    UIButton *nextBtn = [self makeBtn:@"Cửa sổ sau ▶" color:[UIColor colorWithWhite:0.25 alpha:1.0] frame:CGRectMake(118, 8, 105, 30) action:@selector(nextWindow)];
    UIButton *closeBtn = [self makeBtn:@"✕" color:[UIColor systemRedColor] frame:CGRectMake(self.panel.frame.size.width - 42, 8, 34, 30) action:@selector(closePanel)];

    [self.panel addSubview:prevBtn];
    [self.panel addSubview:nextBtn];
    [self.panel addSubview:closeBtn];

    // Khung hiển thị thông tin & Mã của Cửa sổ đang chọn
    self.windowInfoLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 44, self.panel.frame.size.width - 16, 44)];
    self.windowInfoLabel.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    self.windowInfoLabel.textColor = [UIColor yellowColor];
    self.windowInfoLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:10.5];
    self.windowInfoLabel.numberOfLines = 2;
    self.windowInfoLabel.layer.cornerRadius = 5;
    self.windowInfoLabel.clipsToBounds = YES;
    [self.panel addSubview:self.windowInfoLabel];

    // Hàng 2: Nút thao tác trực tiếp trên Cửa sổ đang chọn
    UIButton *scanCurrentBtn = [self makeBtn:@"⚡ Quét Cửa Sổ Này" color:[UIColor systemGreenColor] frame:CGRectMake(8, 94, 130, 30) action:@selector(scanCurrentWindow)];
    UIButton *highlightBtn = [self makeBtn:@"Viền Đỏ" color:[UIColor systemPurpleColor] frame:CGRectMake(144, 94, 75, 30) action:@selector(highlightCurrentWindow)];
    UIButton *copyBtn = [self makeBtn:@"Copy" color:[UIColor systemIndigoColor] frame:CGRectMake(225, 94, 55, 30) action:@selector(copyLog)];

    [self.panel addSubview:scanCurrentBtn];
    [self.panel addSubview:highlightBtn];
    [self.panel addSubview:copyBtn];

    // Log chi tiết
    self.textView = [[UITextView alloc] initWithFrame:CGRectMake(8, 130, self.panel.frame.size.width - 16, 290)];
    self.textView.backgroundColor = [UIColor colorWithWhite:0.03 alpha:1.0];
    self.textView.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:1.0];
    self.textView.font = [UIFont fontWithName:@"Menlo" size:10.5];
    self.textView.editable = NO;
    self.textView.layer.cornerRadius = 6;
    [self.panel addSubview:self.textView];
}

- (UIButton *)makeBtn:(NSString *)title color:(UIColor *)color frame:(CGRect)frame action:(SEL)action {
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

- (void)onPanBubble:(UIPanGestureRecognizer *)p {
    CGPoint t = [p translationInView:self.view];
    self.bubbleBtn.center = CGPointMake(self.bubbleBtn.center.x + t.x, self.bubbleBtn.center.y + t.y);
    [p setTranslation:CGPointZero inView:self.view];
}

- (void)onPanPanel:(UIPanGestureRecognizer *)p {
    CGPoint t = [p translationInView:self.view];
    self.panel.center = CGPointMake(self.panel.center.x + t.x, self.panel.center.y + t.y);
    [p setTranslation:CGPointZero inView:self.view];
}

- (void)reloadWindows {
    self.windowList = [WindowInspectorEngine getAllAllWindows];
    if (self.currentWindowIndex >= self.windowList.count) {
        self.currentWindowIndex = 0;
    }
    [self updateWindowHeader];
}

- (void)updateWindowHeader {
    if (self.windowList.count == 0) {
        self.windowInfoLabel.text = @" Không tìm thấy cửa sổ nào.";
        return;
    }
    UIWindow *w = self.windowList[self.currentWindowIndex];
    self.windowInfoLabel.text = [NSString stringWithFormat:@" [%ld/%lu] %@\n Mã (Pointer): %p | RootVC: %@", 
        (long)(self.currentWindowIndex + 1),
        (unsigned long)self.windowList.count,
        NSStringFromClass([w class]),
        w,
        NSStringFromClass([w.rootViewController class]) ?: @"None"];
}

- (void)openPanel {
    self.bubbleBtn.hidden = YES;
    self.panel.hidden = NO;
    [self reloadWindows];
    [self scanCurrentWindow];
}

- (void)closePanel {
    [self removeHighlight];
    self.panel.hidden = YES;
    self.bubbleBtn.hidden = NO;
}

- (void)prevWindow {
    [self reloadWindows];
    if (self.windowList.count == 0) return;
    self.currentWindowIndex = (self.currentWindowIndex - 1 + self.windowList.count) % self.windowList.count;
    [self updateWindowHeader];
    [self scanCurrentWindow];
}

- (void)nextWindow {
    [self reloadWindows];
    if (self.windowList.count == 0) return;
    self.currentWindowIndex = (self.currentWindowIndex + 1) % self.windowList.count;
    [self updateWindowHeader];
    [self scanCurrentWindow];
}

- (void)scanCurrentWindow {
    [self reloadWindows];
    if (self.windowList.count == 0) return;
    UIWindow *targetWindow = self.windowList[self.currentWindowIndex];
    self.textView.text = [WindowInspectorEngine inspectSpecificWindow:targetWindow];
}

// Đánh dấu viền đỏ quanh cửa sổ được chọn để trực quan hóa
- (void)highlightCurrentWindow {
    [self removeHighlight];
    if (self.windowList.count == 0) return;
    UIWindow *w = self.windowList[self.currentWindowIndex];
    
    self.highlightBorder = [[UIView alloc] initWithFrame:w.bounds];
    self.highlightBorder.layer.borderColor = [UIColor redColor].CGColor;
    self.highlightBorder.layer.borderWidth = 4.0;
    self.highlightBorder.userInteractionEnabled = NO;
    [w addSubview:self.highlightBorder];

    // Tự biến mất sau 3 giây
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self removeHighlight];
    });
}

- (void)removeHighlight {
    if (self.highlightBorder) {
        [self.highlightBorder removeFromSuperview];
        self.highlightBorder = nil;
    }
}

- (void)copyLog {
    [UIPasteboard generalPasteboard].string = self.textView.text ?: @"";
}

@end

#pragma mark - SYSTEM INJECTION

@interface InspectorOverlayWindow : UIWindow
@end

@implementation InspectorOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *h = [super hitTest:point withEvent:event];
    if (h == self.rootViewController.view) return nil; // Xuyên chạm xuống app
    return h;
}
@end

static InspectorOverlayWindow *gInspectorWin = nil;

__attribute__((constructor))
static void dylib_entry(void) {
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
                }
                
                if (@available(iOS 13.0, *) && scene) {
                    gInspectorWin = [[InspectorOverlayWindow alloc] initWithWindowScene:scene];
                } else {
                    gInspectorWin = [[InspectorOverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
                }
                
                gInspectorWin.windowLevel = UIWindowLevelAlert + 1000.0;
                gInspectorWin.backgroundColor = [UIColor clearColor];
                WindowInspectorVC *vc = [[WindowInspectorVC alloc] init];
                gInspectorWin.rootViewController = vc;
                gInspectorWin.hidden = NO;
            });
        });
    }];
}
