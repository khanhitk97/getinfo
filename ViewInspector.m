#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <Vision/Vision.h>

#pragma mark - DEEP RUNTIME & HIDDEN DATA ENGINE

@interface DeepHiddenDataExtractor : NSObject
+ (NSString *)performDeepSystemScan;
@end

@implementation DeepHiddenDataExtractor

// Duyệt đệ quy object bất kỳ trong bộ nhớ (Dictionary, Array, Model, String)
+ (void)dumpObject:(id)obj depth:(int)depth keyName:(NSString *)keyName buffer:(NSMutableString *)buffer visited:(NSMutableSet *)visited {
    if (!obj || depth > 5) return;
    
    // Chống lặp vô tận do vòng lặp tham chiếu
    NSValue *ptrVal = [NSValue valueWithNonretainedObject:obj];
    if ([visited containsObject:ptrVal]) return;
    [visited addObject:ptrVal];

    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@"  " startingAtIndex:0];

    @try {
        if ([obj isKindOfClass:[NSString class]]) {
            NSString *str = (NSString *)obj;
            if (str.length > 0) {
                [buffer appendFormat:@"%@• [%@] \"%@\"\n", indent, keyName ?: @"Str", str];
            }
        } else if ([obj isKindOfClass:[NSNumber class]]) {
            [buffer appendFormat:@"%@• [%@] %@\n", indent, keyName ?: @"Num", obj];
        } else if ([obj isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)obj;
            [buffer appendFormat:@"%@📂 [%@] Dict (%lu items):\n", indent, keyName ?: @"Data", (unsigned long)dict.count];
            for (id key in dict) {
                [self dumpObject:dict[key] depth:depth + 1 keyName:[key description] buffer:buffer visited:visited];
            }
        } else if ([obj isKindOfClass:[NSArray class]]) {
            NSArray *arr = (NSArray *)obj;
            if (arr.count > 0 && arr.count <= 20) {
                [buffer appendFormat:@"%@📑 [%@] Array (%lu items):\n", indent, keyName ?: @"List", (unsigned long)arr.count];
                for (NSUInteger i = 0; i < arr.count; i++) {
                    [self dumpObject:arr[i] depth:depth + 1 keyName:[NSString stringWithFormat:@"%lu", (unsigned long)i] buffer:buffer visited:visited];
                }
            }
        } else {
            // Quét Ivars của Custom Class (Model, Controller, Cell)
            Class cls = [obj class];
            NSString *className = NSStringFromClass(cls);
            if ([className hasPrefix:@"UI"] && ![className containsString:@"Cell"] && ![className containsString:@"Controller"]) {
                return;
            }

            unsigned int ivarCount = 0;
            Ivar *ivars = class_copyIvarList(cls, &ivarCount);
            if (ivars) {
                for (unsigned int i = 0; i < ivarCount; i++) {
                    const char *type = ivar_getTypeEncoding(ivars[i]);
                    const char *name = ivar_getName(ivars[i]);
                    if (type && type[0] == '@' && name) {
                        @try {
                            id val = object_getIvar(obj, ivars[i]);
                            if (val && ![val isKindOfClass:[UIView class]] && ![val isKindOfClass:[UIViewController class]]) {
                                NSString *ivarName = [NSString stringWithUTF8String:name];
                                [self dumpObject:val depth:depth + 1 keyName:ivarName buffer:buffer visited:visited];
                            }
                        } @catch (__unused NSException *e) {}
                    }
                }
                free(ivars);
            }
        }
    } @catch (__unused NSException *e) {}
}

// Quét toàn bộ View ẩn
+ (void)scanHiddenViewsOnly:(UIView *)view level:(int)level buffer:(NSMutableString *)buffer {
    if (!view) return;

    NSString *indent = [@"" stringByPaddingToLength:level * 2 withString:@"  " startingAtIndex:0];
    
    @try {
        BOOL isHidden = view.isHidden;
        BOOL isAlphaZero = view.alpha < 0.05;
        BOOL isOffscreen = (view.frame.origin.x < -10 || view.frame.origin.y < -10 || view.frame.size.width <= 1);
        BOOL isLayerHidden = view.layer.hidden || view.layer.opacity < 0.05;

        NSMutableString *textVal = [NSMutableString string];
        if ([view isKindOfClass:[UILabel class]]) {
            NSString *t = [(UILabel *)view text];
            if (t.length) [textVal appendFormat:@"Text: \"%@\"", t];
        } else if ([view isKindOfClass:[UITextField class]]) {
            UITextField *tf = (UITextField *)view;
            if (tf.text.length) [textVal appendFormat:@"TF: \"%@\" (Sec:%d)", tf.text, tf.isSecureTextEntry];
        } else if ([view isKindOfClass:[UITextView class]]) {
            NSString *t = [(UITextView *)view text];
            if (t.length) [textVal appendFormat:@"TV: \"%@\"", t];
        }

        if (view.accessibilityLabel.length) [textVal appendFormat:@" | A11y: \"%@\"", view.accessibilityLabel];
        if (view.accessibilityValue.length) [textVal appendFormat:@" | Val: \"%@\"", view.accessibilityValue];

        if (isHidden || isAlphaZero || isOffscreen || isLayerHidden) {
            [buffer appendFormat:@"%@⛔ [BỊ ẨN] %@ | Frame:%@ | α:%.1f %@\n",
                indent, NSStringFromClass([view class]), NSStringFromCGRect(view.frame), view.alpha, textVal];
        } else if (textVal.length > 0) {
            [buffer appendFormat:@"%@👁️ %@ -> %@\n", indent, NSStringFromClass([view class]), textVal];
        }

        for (UIView *sub in view.subviews) {
            [self scanHiddenViewsOnly:sub level:level + 1 buffer:buffer];
        }
    } @catch (__unused NSException *e) {}
}

+ (UIViewController *)getTopViewController:(UIViewController *)root {
    if ([root isKindOfClass:[UINavigationController class]]) {
        return [self getTopViewController:[(UINavigationController *)root visibleViewController]];
    }
    if ([root isKindOfClass:[UITabBarController class]]) {
        return [self getTopViewController:[(UITabBarController *)root selectedViewController]];
    }
    if (root.presentedViewController) {
        return [self getTopViewController:root.presentedViewController];
    }
    return root;
}

+ (NSString *)performDeepSystemScan {
    NSMutableString *buf = [NSMutableString stringWithCapacity:16384];
    [buf appendString:@"====== KẾT QUẢ QUÉT TẦNG SÂU HỆ THỐNG ======\n\n"];

    UIWindow *mainWin = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)s).windows) {
                    if (!w.isHidden && ![NSStringFromClass([w class]) containsString:@"InspectorOverlayWindow"]) {
                        mainWin = w;
                        break;
                    }
                }
            }
        }
    }
    if (!mainWin) mainWin = [UIApplication sharedApplication].windows.firstObject;

    UIViewController *topVC = [self getTopViewController:mainWin.rootViewController];

    // PHẦN 1: DUMP BỘ NHỚ DATA MODEL & IVARS CỦA VIEWCONTROLLER
    [buf appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    [buf appendFormat:@"🧠 [TẦNG 1] BỘ NHỚ MODEL / IVARS: %@\n", NSStringFromClass([topVC class])];
    [buf appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    
    if (topVC) {
        NSMutableSet *visited = [NSMutableSet set];
        [self dumpObject:topVC depth:0 keyName:@"RootVC" buffer:buf visited:visited];
    } else {
        [buf appendString:@"(Không tìm thấy ViewController)\n"];
    }

    // PHẦN 2: DUMP VIEW BỊ ẨN / ALPHA = 0 / OFF-SCREEN
    [buf appendString:@"\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    [buf appendString:@"👁️ [TẦNG 2] CÂY GIAO DIỆN & VIEW BỊ ẨN\n"];
    [buf appendString:@"━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"];
    
    if (mainWin) {
        [self scanHiddenViewsOnly:mainWin level:0 buffer:buf];
    }

    return buf;
}

@end

#pragma mark - OCR & VISION SCANNER

@interface BruteforcePhoneExtractor : NSObject
+ (void)extractPhonesViaVisionOCR:(void(^)(NSArray<NSString *> *phones, NSString *allText))completion;
@end

@implementation BruteforcePhoneExtractor

+ (NSArray<NSString *> *)filterPhonesFromString:(NSString *)text {
    if (!text || text.length < 8) return @[];
    NSMutableArray<NSString *> *results = [NSMutableArray array];
    NSArray *patterns = @[
        @"(?:\\+84|0)[3|5|7|8|9][0-9\\s.-]{7,11}[0-9]",
        @"(?:\\+84|0)[3|5|7|8|9][0-9*\\s.-]{6,12}[0-9]",
        @"[0-9]{10,11}"
    ];

    for (NSString *pat in patterns) {
        NSError *err = nil;
        NSRegularExpression *reg = [NSRegularExpression regularExpressionWithPattern:pat options:NSRegularExpressionCaseInsensitive error:&err];
        if (!err) {
            NSArray<NSTextCheckingResult *> *matches = [reg matchesInString:text options:0 range:NSMakeRange(0, text.length)];
            for (NSTextCheckingResult *m in matches) {
                NSString *matchStr = [text substringWithRange:m.range];
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

+ (void)extractPhonesViaVisionOCR:(void(^)(NSArray<NSString *> *phones, NSString *allText))completion {
    if (@available(iOS 13.0, *)) {
        UIWindow *keyWin = nil;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)s).windows) {
                    if (!w.isHidden && ![NSStringFromClass([w class]) containsString:@"InspectorOverlayWindow"]) {
                        keyWin = w;
                        break;
                    }
                }
            }
        }
        if (!keyWin) keyWin = [UIApplication sharedApplication].windows.firstObject;

        UIGraphicsBeginImageContextWithOptions(keyWin.bounds.size, NO, 0.0);
        [keyWin drawViewHierarchyInRect:keyWin.bounds afterScreenUpdates:NO];
        UIImage *snapshot = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        if (!snapshot || !snapshot.CGImage) {
            if (completion) completion(@[], @"Không chụp được ảnh màn hình.");
            return;
        }

        VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest * _Nonnull req, NSError * _Nullable error) {
            if (error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(@[], [NSString stringWithFormat:@"Lỗi OCR: %@", error.localizedDescription]);
                });
                return;
            }

            NSMutableString *fullRecognizedText = [NSMutableString string];
            NSMutableSet<NSString *> *foundPhones = [NSMutableSet set];

            for (VNRecognizedTextObservation *obs in req.results) {
                VNRecognizedText *topCandidate = [[obs topCandidates:1] firstObject];
                if (topCandidate) {
                    NSString *str = topCandidate.string;
                    [fullRecognizedText appendFormat:@"%@\n", str];
                    for (NSString *p in [self filterPhonesFromString:str]) {
                        [foundPhones addObject:p];
                    }
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion([foundPhones allObjects], fullRecognizedText);
            });
        }];

        request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        request.usesLanguageCorrection = NO;

        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:snapshot.CGImage options:@{}];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [handler performRequests:@[request] error:nil];
        });
    } else {
        if (completion) completion(@[], @"Yêu cầu iOS 13+.");
    }
}

@end

#pragma mark - GIAO DIỆN ĐIỀU KHIỂN NỔI (FLOATING UI)

@interface VisionInspectorVC : UIViewController <UISearchBarDelegate>
@property (nonatomic, strong) UIButton *bubbleBtn;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, copy) NSString *currentRawLog;
@end

@implementation VisionInspectorVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    // Nút tròn nổi
    self.bubbleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.bubbleBtn.frame = CGRectMake(15, 120, 65, 65);
    self.bubbleBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.55 blue:1.0 alpha:0.92];
    [self.bubbleBtn setTitle:@"🎯 Tools" forState:UIControlStateNormal];
    [self.bubbleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.bubbleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.bubbleBtn.layer.cornerRadius = 32.5;
    self.bubbleBtn.layer.borderWidth = 2.0;
    self.bubbleBtn.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.bubbleBtn addTarget:self action:@selector(openPanel) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *panB = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanBubble:)];
    [self.bubbleBtn addGestureRecognizer:panB];
    [self.view addSubview:self.bubbleBtn];

    // Bảng Panel chính
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(10, 60, screenW - 20, 450)];
    self.panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.96];
    self.panel.layer.cornerRadius = 14;
    self.panel.layer.borderWidth = 1.2;
    self.panel.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:1.0].CGColor;
    self.panel.clipsToBounds = YES;
    self.panel.hidden = YES;
    [self.view addSubview:self.panel];

    UIPanGestureRecognizer *panP = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanPanel:)];
    [self.panel addGestureRecognizer:panP];

    // Hàng nút điều khiển
    UIButton *ocrBtn = [self makeBtn:@"📸 OCR SĐT" color:[UIColor systemBlueColor] frame:CGRectMake(8, 10, 90, 30) action:@selector(runOCRScan)];
    UIButton *deepBtn = [self makeBtn:@"🔬 Quét Ẩn Sâu" color:[UIColor systemOrangeColor] frame:CGRectMake(102, 10, 105, 30) action:@selector(runDeepScan)];
    UIButton *copyBtn = [self makeBtn:@"Copy" color:[UIColor systemGreenColor] frame:CGRectMake(211, 10, 50, 30) action:@selector(copyLog)];
    UIButton *closeBtn = [self makeBtn:@"✕" color:[UIColor systemRedColor] frame:CGRectMake(self.panel.frame.size.width - 42, 10, 34, 30) action:@selector(closePanel)];

    [self.panel addSubview:ocrBtn];
    [self.panel addSubview:deepBtn];
    [self.panel addSubview:copyBtn];
    [self.panel addSubview:closeBtn];

    // Search Bar để lọc nhanh dữ liệu quét sâu (VD: tìm "phone", "note", "price", "token")
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 44, self.panel.frame.size.width, 36)];
    self.searchBar.placeholder = @"Lọc dữ liệu (phone, note, token, address)...";
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.delegate = self;
    self.searchBar.barStyle = UIBarStyleBlack;
    [self.panel addSubview:self.searchBar];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 82, self.panel.frame.size.width - 20, 18)];
    self.statusLabel.textColor = [UIColor yellowColor];
    self.statusLabel.font = [UIFont boldSystemFontOfSize:10.5];
    self.statusLabel.text = @"Sẵn sàng quét hệ thống...";
    [self.panel addSubview:self.statusLabel];

    self.textView = [[UITextView alloc] initWithFrame:CGRectMake(8, 104, self.panel.frame.size.width - 16, 336)];
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

- (void)openPanel {
    self.bubbleBtn.hidden = YES;
    self.panel.hidden = NO;
    [self runOCRScan];
}

- (void)closePanel {
    self.panel.hidden = YES;
    self.bubbleBtn.hidden = NO;
}

- (void)runOCRScan {
    self.statusLabel.text = @"Đang quét OCR màn hình...";
    self.panel.alpha = 0.0;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [BruteforcePhoneExtractor extractPhonesViaVisionOCR:^(NSArray<NSString *> *phones, NSString *allText) {
            self.panel.alpha = 1.0;
            NSMutableString *res = [NSMutableString string];
            [res appendString:@"=== KẾT QUẢ NHẬN DIỆN MÀN HÌNH (OCR) ===\n\n"];
            if (phones.count > 0) {
                self.statusLabel.text = [NSString stringWithFormat:@"TÌM THẤY %lu SĐT!", (unsigned long)phones.count];
                [res appendString:@"🎯 SỐ ĐIỆN THOẠI HIỂN THỊ:\n"];
                for (NSUInteger i = 0; i < phones.count; i++) {
                    [res appendFormat:@"  👉 [%lu] %@\n", (unsigned long)(i + 1), phones[i]];
                }
            } else {
                self.statusLabel.text = @"Không thấy SĐT rõ trên màn hình.";
            }

            [res appendString:@"\n--- TOÀN BỘ CHỮ TRÊN MÀN HÌNH ---\n"];
            [res appendString:allText];
            self.currentRawLog = res;
            self.textView.text = res;
        }];
    });
}

- (void)runDeepScan {
    self.statusLabel.text = @"Đang dump bộ nhớ RAM & View ẩn...";
    NSString *deepLog = [DeepHiddenDataExtractor performDeepSystemScan];
    self.currentRawLog = deepLog;
    self.textView.text = deepLog;
    self.statusLabel.text = @"Đã hoàn tất quét tầng sâu!";
}

- (void)copyLog {
    [UIPasteboard generalPasteboard].string = self.textView.text ?: @"";
    self.statusLabel.text = @"Đã chép toàn bộ vào Clipboard!";
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        self.textView.text = self.currentRawLog;
        return;
    }
    NSMutableString *filtered = [NSMutableString string];
    NSArray *lines = [self.currentRawLog componentsSeparatedByString:@"\n"];
    for (NSString *l in lines) {
        if ([l localizedCaseInsensitiveContainsString:searchText]) {
            [filtered appendFormat:@"%@\n", l];
        }
    }
    self.textView.text = filtered;
}

@end

#pragma mark - WINDOW INJECTION

@interface InspectorOverlayWindow : UIWindow
@end

@implementation InspectorOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *h = [super hitTest:point withEvent:event];
    if (h == self.rootViewController.view) return nil;
    return h;
}
@end

static InspectorOverlayWindow *gVisionWindow = nil;

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
                    if (scene) {
                        gVisionWindow = [[InspectorOverlayWindow alloc] initWithWindowScene:scene];
                    }
                }
                
                if (!gVisionWindow) {
                    gVisionWindow = [[InspectorOverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
                }
                
                gVisionWindow.windowLevel = UIWindowLevelAlert + 1000.0;
                gVisionWindow.backgroundColor = [UIColor clearColor];
                VisionInspectorVC *vc = [[VisionInspectorVC alloc] init];
                gVisionWindow.rootViewController = vc;
                gVisionWindow.hidden = NO;
            });
        });
    }];
}
