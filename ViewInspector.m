#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <Vision/Vision.h> // OCR nhận diện chữ trên màn hình

#pragma mark - OCR & DEEP ACCESSIBILITY ENGINE

@interface BruteforcePhoneExtractor : NSObject
+ (void)extractPhonesViaVisionOCR:(void(^)(NSArray<NSString *> *phones, NSString *allText))completion;
+ (NSArray<NSString *> *)scanRawAccessibilityAndLayers;
@end

@implementation BruteforcePhoneExtractor

// Regex lọc số điện thoại
+ (NSArray<NSString *> *)filterPhonesFromString:(NSString *)text {
    if (!text || text.length < 8) return @[];
    
    NSMutableArray<NSString *> *results = [NSMutableArray array];
    NSArray *patterns = @[
        @"(?:\\+84|0)[3|5|7|8|9][0-9\\s.-]{7,11}[0-9]",
        @"(?:\\+84|0)[3|5|7|8|9][0-9*\\s.-]{6,12}[0-9]",
        @"[0-9]{10,11}" // Bắt chuỗi số liền 10-11 ký tự
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

// 1. CHỤP MÀN HÌNH VÀ DÙNG APPLE VISION FRAMEWORK ĐỂ OCR TỪNG CHỮ
+ (void)extractPhonesViaVisionOCR:(void(^)(NSArray<NSString *> *phones, NSString *allText))completion {
    if (@available(iOS 13.0, *)) {
        // Chụp snapshot màn hình chính của ứng dụng
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
        if (!keyWin) keyWin = [UIApplication sharedApplication].keyWindow;

        UIGraphicsBeginImageContextWithOptions(keyWin.bounds.size, NO, 0.0);
        [keyWin drawViewHierarchyInRect:keyWin.bounds afterScreenUpdates:NO];
        UIImage *snapshot = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        if (!snapshot || !snapshot.CGImage) {
            if (completion) completion(@[], @"Không chụp được màn hình.");
            return;
        }

        // Tạo Vision Request nhận diện chữ
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
                    
                    NSArray<NSString *> *phones = [self filterPhonesFromString:str];
                    for (NSString *p in phones) {
                        [foundPhones addObject:p];
                    }
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion([foundPhones allObjects], fullRecognizedText);
            });
        }];

        request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        request.usesLanguageCorrection = NO; // Tắt tự sửa từ để đọc chính xác số

        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:snapshot.CGImage options:@{}];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [handler performRequests:@[request] error:nil];
        });
    } else {
        if (completion) completion(@[], @"Yêu cầu iOS 13+ để chạy Vision OCR.");
    }
}

// 2. QUÉT RAW SEMANTICS & ACCESSIBILITY ELEMENTS (DÀNH CHO FLUTTER / REACT NATIVE)
+ (void)deepScanAccessibilityInObject:(id)obj intoSet:(NSMutableSet<NSString *> *)set {
    if (!obj) return;

    @try {
        if ([obj respondsToSelector:@selector(accessibilityLabel)]) {
            NSString *l = [obj accessibilityLabel];
            if (l.length) [set addObject:l];
        }
        if ([obj respondsToSelector:@selector(accessibilityValue)]) {
            NSString *v = [obj accessibilityValue];
            if (v.length) [set addObject:v];
        }

        // Quét CATextLayer
        if ([obj isKindOfClass:[CALayer class]]) {
            CALayer *layer = (CALayer *)obj;
            if ([layer respondsToSelector:@selector(string)]) {
                id str = [layer valueForKey:@"string"];
                if ([str isKindOfClass:[NSString class]]) [set addObject:(NSString *)str];
            }
            for (CALayer *subL in layer.sublayers) {
                [self deepScanAccessibilityInObject:subL intoSet:set];
            }
        }

        // Quét View subviews & sub-elements
        if ([obj isKindOfClass:[UIView class]]) {
            UIView *v = (UIView *)obj;
            for (id el in v.accessibilityElements) {
                [self deepScanAccessibilityInObject:el intoSet:set];
            }
            for (UIView *sv in v.subviews) {
                [self deepScanAccessibilityInObject:sv intoSet:set];
            }
            [self deepScanAccessibilityInObject:v.layer intoSet:set];
        }
    } @catch (__unused NSException *e) {}
}

+ (NSArray<NSString *> *)scanRawAccessibilityAndLayers {
    NSMutableSet<NSString *> *allRawTexts = [NSMutableSet set];
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (![NSStringFromClass([w class]) containsString:@"InspectorOverlayWindow"]) {
            [self deepScanAccessibilityInObject:w intoSet:allRawTexts];
        }
    }
    
    NSMutableSet<NSString *> *phones = [NSMutableSet set];
    for (NSString *str in allRawTexts) {
        for (NSString *p in [self filterPhonesFromString:str]) {
            [phones addObject:p];
        }
    }
    return [phones allObjects];
}

@end

#pragma mark - GIAO DIỆN ĐIỀU KHIỂN

@interface VisionInspectorVC : UIViewController
@property (nonatomic, strong) UIButton *bubbleBtn;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation VisionInspectorVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    // Bong bóng nổi
    self.bubbleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.bubbleBtn.frame = CGRectMake(15, 120, 65, 65);
    self.bubbleBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.55 blue:1.0 alpha:0.92];
    [self.bubbleBtn setTitle:@"🎯 OCR" forState:UIControlStateNormal];
    [self.bubbleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.bubbleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.bubbleBtn.layer.cornerRadius = 32.5;
    self.bubbleBtn.layer.borderWidth = 2.0;
    self.bubbleBtn.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.bubbleBtn addTarget:self action:@selector(openPanel) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *panB = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanBubble:)];
    [self.bubbleBtn addGestureRecognizer:panB];
    [self.view addSubview:self.bubbleBtn];

    // Panel
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(10, 70, screenW - 20, 420)];
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
    UIButton *ocrBtn = [self makeBtn:@"📸 OCR Màn Hình" color:[UIColor systemGreenColor] frame:CGRectMake(8, 10, 115, 32) action:@selector(runOCRScan)];
    UIButton *rawBtn = [self makeBtn:@"Semantics Quét" color:[UIColor systemOrangeColor] frame:CGRectMake(128, 10, 105, 32) action:@selector(runRawScan)];
    UIButton *copyBtn = [self makeBtn:@"Copy" color:[UIColor systemIndigoColor] frame:CGRectMake(238, 10, 50, 32) action:@selector(copyLog)];
    UIButton *closeBtn = [self makeBtn:@"✕" color:[UIColor systemRedColor] frame:CGRectMake(self.panel.frame.size.width - 45, 10, 38, 32) action:@selector(closePanel)];

    [self.panel addSubview:ocrBtn];
    [self.panel addSubview:rawBtn];
    [self.panel addSubview:copyBtn];
    [self.panel addSubview:closeBtn];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 46, self.panel.frame.size.width - 20, 20)];
    self.statusLabel.textColor = [UIColor yellowColor];
    self.statusLabel.font = [UIFont boldSystemFontOfSize:11];
    self.statusLabel.text = @"Sẵn sàng quét ký tự...";
    [self.panel addSubview:self.statusLabel];

    self.textView = [[UITextView alloc] initWithFrame:CGRectMake(8, 70, self.panel.frame.size.width - 16, 340)];
    self.textView.backgroundColor = [UIColor colorWithWhite:0.03 alpha:1.0];
    self.textView.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:1.0];
    self.textView.font = [UIFont fontWithName:@"Menlo-Bold" size:11.5];
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
    self.statusLabel.text = @"Đang phân tích hình ảnh pixel màn hình (Vision OCR)...";
    
    // Tạm ẩn panel đi 0.05s để chụp ảnh giao diện phía sau không bị che
    self.panel.alpha = 0.0;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [BruteforcePhoneExtractor extractPhonesViaVisionOCR:^(NSArray<NSString *> *phones, NSString *allText) {
            self.panel.alpha = 1.0;
            NSMutableString *res = [NSMutableString string];
            [res appendString:@"=== KẾT QUẢ QUÉT VISION OCR TỪNG CHỮ ===\n\n"];
            
            if (phones.count > 0) {
                self.statusLabel.text = [NSString stringWithFormat:@"ĐÃ BẮT ĐƯỢC %lu SỐ ĐIỆN THOẠI!", (unsigned long)phones.count];
                [res appendString:@"🎯 SỐ ĐIỆN THOẠI NHẬN DIỆN ĐƯỢC:\n"];
                for (NSUInteger i = 0; i < phones.count; i++) {
                    [res appendFormat:@"  👉 [%lu]  %@\n", (unsigned long)(i + 1), phones[i]];
                }
            } else {
                self.statusLabel.text = @"Không phát hiện SĐT qua OCR.";
                [res appendString:@"⚠️ Chưa lọc được SĐT dạng chuẩn.\n"];
            }

            [res appendString:@"\n--- TOÀN BỘ CHỮ ĐỌC ĐƯỢC TRÊN MÀN HÌNH ---\n"];
            [res appendString:allText];
            self.textView.text = res;
        }];
    });
}

- (void)runRawScan {
    self.statusLabel.text = @"Đang quét cây Semantics/Layers...";
    NSArray<NSString *> *phones = [BruteforcePhoneExtractor scanRawAccessibilityAndLayers];
    NSMutableString *res = [NSMutableString stringWithString:@"=== KẾT QUẢ QUÉT SEMANTICS & LAYERS ===\n\n"];
    if (phones.count > 0) {
        self.statusLabel.text = [NSString stringWithFormat:@"Tìm thấy %lu số qua Semantics!", (unsigned long)phones.count];
        for (NSString *p in phones) {
            [res appendFormat:@"👉 %@\n", p];
        }
    } else {
        self.statusLabel.text = @"Không có SĐT trong Semantics.";
        [res appendString:@"(Không tìm thấy qua Semantics)"];
    }
    self.textView.text = res;
}

- (void)copyLog {
    [UIPasteboard generalPasteboard].string = self.textView.text ?: @"";
    self.statusLabel.text = @"Đã sao chép vào bộ nhớ tạm!";
}

@end

#pragma mark - OVERLAY INJECTION

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
                }
                
                if (@available(iOS 13.0, *) && scene) {
                    gVisionWindow = [[InspectorOverlayWindow alloc] initWithWindowScene:scene];
                } else {
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
