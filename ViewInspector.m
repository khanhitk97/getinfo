#import <UIKit/UIKit.h>
#import <Vision/Vision.h>

#pragma mark - DATA EXTRACTION ENGINE

@interface DriverDataExtractor : NSObject
+ (void)expandSheetAndExtract:(void(^)(NSString *shipFee, NSString *bonusFee, NSString *note, NSString *randomSecondPhone, UIImage *croppedOrderImage))completion;
@end

@implementation DriverDataExtractor

+ (NSArray<NSString *> *)extractPhonesFromText:(NSString *)text {
    if (!text || text.length < 8) return @[];
    NSMutableArray<NSString *> *validPhones = [NSMutableArray array];
    NSString *pattern = @"(?:\\+?84|0)(?:3[2-9]|5[6|8|9]|7[0|6-9]|8[1-9]|9[0-9]|2[0-9]{2})[0-9\\s.-]{6,15}";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:text options:0 range:NSMakeRange(0, text.length)];

    for (NSTextCheckingResult *m in matches) {
        NSString *matchedStr = [text substringWithRange:m.range];
        NSString *digitsOnly = [[matchedStr componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
        if ([digitsOnly hasPrefix:@"84"] && digitsOnly.length >= 11) {
            digitsOnly = [@"0" stringByAppendingString:[digitsOnly substringFromIndex:2]];
        }
        NSString *clean = nil;
        if (digitsOnly.length >= 10 && ([digitsOnly hasPrefix:@"03"] || [digitsOnly hasPrefix:@"05"] || [digitsOnly hasPrefix:@"07"] || [digitsOnly hasPrefix:@"08"] || [digitsOnly hasPrefix:@"09"])) {
            clean = [digitsOnly substringToIndex:10];
        } else if (digitsOnly.length >= 11 && [digitsOnly hasPrefix:@"02"]) {
            clean = [digitsOnly substringToIndex:11];
        }
        if (clean && ![validPhones containsObject:clean]) {
            [validPhones addObject:clean];
        }
    }
    return validPhones;
}

+ (void)forceScrollDown:(UIView *)view {
    if (!view) return;
    if ([view isKindOfClass:[UIScrollView class]]) {
        UIScrollView *sv = (UIScrollView *)view;
        if (sv.contentSize.height > sv.bounds.size.height) {
            CGPoint bottomOffset = CGPointMake(0, sv.contentSize.height - sv.bounds.size.height + sv.adjustedContentInset.bottom);
            [sv setContentOffset:bottomOffset animated:NO];
        }
    }
    for (UIView *sub in view.subviews) {
        [self forceScrollDown:sub];
    }
}

+ (void)expandSheetAndExtract:(void(^)(NSString *shipFee, NSString *bonusFee, NSString *note, NSString *randomSecondPhone, UIImage *croppedOrderImage))completion {
    if (@available(iOS 13.0, *)) {
        UIWindow *mainWin = nil;
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
        if (!mainWin) mainWin = [UIApplication sharedApplication].windows.firstObject;

        [self forceScrollDown:mainWin];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIGraphicsBeginImageContextWithOptions(mainWin.bounds.size, NO, 0.0);
            [mainWin drawViewHierarchyInRect:mainWin.bounds afterScreenUpdates:YES];
            UIImage *fullSnapshot = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();

            if (!fullSnapshot || !fullSnapshot.CGImage) {
                if (completion) completion(@"--", @"0đ", @"(Lỗi chụp)", nil, nil);
                return;
            }

            CGFloat scale = fullSnapshot.scale;
            CGFloat cropY = mainWin.bounds.size.height * 0.35;
            CGFloat cropH = mainWin.bounds.size.height * 0.55;
            CGRect scaledRect = CGRectMake(0, cropY * scale, mainWin.bounds.size.width * scale, cropH * scale);
            CGImageRef imgRef = CGImageCreateWithImageInRect(fullSnapshot.CGImage, scaledRect);
            UIImage *croppedOrderImg = [UIImage imageWithCGImage:imgRef scale:scale orientation:fullSnapshot.imageOrientation];
            CGImageRelease(imgRef);

            VNRecognizeTextRequest *req = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest * _Nonnull request, NSError * _Nullable error) {
                NSMutableArray<NSString *> *strings = [NSMutableArray array];
                for (VNRecognizedTextObservation *obs in request.results) {
                    VNRecognizedText *top = [[obs topCandidates:1] firstObject];
                    if (top) [strings addObject:top.string];
                }

                NSString *shipFee = @"--";
                NSString *bonusFee = @"0đ";
                NSString *note = @"Không có ghi chú";
                NSMutableArray<NSString *> *shopPhones = [NSMutableArray array];
                NSRegularExpression *moneyRegex = [NSRegularExpression regularExpressionWithPattern:@"[0-9]{1,3}(?:\\.[0-9]{3})+" options:0 error:nil];

                for (NSUInteger i = 0; i < strings.count; i++) {
                    NSString *l = strings[i];
                    NSString *lower = [l lowercaseString];

                    if ([lower containsString:@"mua hàng tại"] || [lower containsString:@"quán"] || [lower containsString:@"sâm"] || [lower containsString:@"bún"] || [lower containsString:@"cơm"]) {
                        NSArray *pList = [self extractPhonesFromText:l];
                        for (NSString *p in pList) {
                            if (![shopPhones containsObject:p]) [shopPhones addObject:p];
                        }
                    }

                    if ([lower containsString:@"phí giao hàng"] || [lower containsString:@"giao hàng"]) {
                        NSTextCheckingResult *match = [moneyRegex firstMatchInString:l options:0 range:NSMakeRange(0, l.length)];
                        if (match) {
                            shipFee = [[l substringWithRange:match.range] stringByAppendingString:@"đ"];
                        } else if (i + 1 < strings.count) {
                            NSString *next = strings[i+1];
                            NSTextCheckingResult *nextMatch = [moneyRegex firstMatchInString:next options:0 range:NSMakeRange(0, next.length)];
                            if (nextMatch) {
                                shipFee = [[next substringWithRange:nextMatch.range] stringByAppendingString:@"đ"];
                            } else {
                                NSString *digits = [[next componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
                                if (digits.length >= 4) shipFee = [digits stringByAppendingString:@"đ"];
                            }
                        }
                    }

                    if ([lower containsString:@"khích lệ"]) {
                        if (i + 1 < strings.count) {
                            NSString *next = strings[i+1];
                            NSTextCheckingResult *bonusMatch = [moneyRegex firstMatchInString:next options:0 range:NSMakeRange(0, next.length)];
                            if (bonusMatch) {
                                bonusFee = [[next substringWithRange:bonusMatch.range] stringByAppendingString:@"đ"];
                            } else if ([next containsString:@"0"]) {
                                bonusFee = @"0đ";
                            }
                        }
                    }

                    if ([lower containsString:@"ghi chú thêm"] || [lower containsString:@"dặn dò"]) {
                        if (i + 1 < strings.count) {
                            NSString *nextStr = strings[i+1];
                            if (![nextStr.lowercaseString containsString:@"tài xế vui lòng"]) {
                                note = nextStr;
                            }
                        }
                    }
                }

                NSString *secondPhone = nil;
                if (shopPhones.count >= 2) {
                    secondPhone = shopPhones[1];
                }

                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(shipFee, bonusFee, note, secondPhone, croppedOrderImg ?: fullSnapshot);
                });
            }];

            req.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
            req.usesLanguageCorrection = NO;
            VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:fullSnapshot.CGImage options:@{}];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                [handler performRequests:@[req] error:nil];
            });
        });
    }
}

@end

#pragma mark - UI LỚP PHỦ NỀN CAM CO GỌN (CHIỀU CAO 108pt)

@interface DriverHelperVC : UIViewController
@property (nonatomic, strong) UIButton *bubbleBtn;
@property (nonatomic, strong) UIView *orangeHeaderBar;
@property (nonatomic, strong) UILabel *feeLabel;
@property (nonatomic, strong) UILabel *noteLabel;
@property (nonatomic, strong) UIButton *callSecondBtn;
@property (nonatomic, strong) UIButton *zaloBtn;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) UIImage *orderImageToSend;
@property (nonatomic, strong) NSString *currentPhoneForZalo;
@end

@implementation DriverHelperVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;

    // Bong bóng nhỏ góc phải
    self.bubbleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.bubbleBtn.frame = CGRectMake(sw - 56, 160, 48, 48);
    self.bubbleBtn.backgroundColor = [UIColor colorWithRed:0.96 green:0.35 blue:0.15 alpha:0.98];
    [self.bubbleBtn setTitle:@"🛵 Đơn" forState:UIControlStateNormal];
    [self.bubbleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.bubbleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11.0];
    self.bubbleBtn.layer.cornerRadius = 24;
    self.bubbleBtn.layer.borderWidth = 2;
    self.bubbleBtn.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.bubbleBtn addTarget:self action:@selector(openOrangeHeader) forControlEvents:UIControlEventTouchUpInside];
    [self.bubbleBtn addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanBubble:)]];
    [self.view addSubview:self.bubbleBtn];

    // Lớp phủ nền cam rút gọn chiều cao xuống 108pt (ôm khít thanh tiêu đề)
    self.orangeHeaderBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, sw, 108)];
    self.orangeHeaderBar.backgroundColor = [UIColor colorWithRed:0.96 green:0.35 blue:0.15 alpha:1.0];
    self.orangeHeaderBar.layer.shadowColor = [UIColor blackColor].CGColor;
    self.orangeHeaderBar.layer.shadowOpacity = 0.25;
    self.orangeHeaderBar.layer.shadowOffset = CGSizeMake(0, 2);
    self.orangeHeaderBar.layer.shadowRadius = 3;
    self.orangeHeaderBar.hidden = YES;
    [self.view addSubview:self.orangeHeaderBar];

    // Nút Zalo góc trên phải (Y = 48)
    self.zaloBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.zaloBtn.frame = CGRectMake(sw - 68, 48, 60, 26);
    self.zaloBtn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.25];
    [self.zaloBtn setTitle:@"💬 Zalo" forState:UIControlStateNormal];
    [self.zaloBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.zaloBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
    self.zaloBtn.layer.cornerRadius = 13;
    self.zaloBtn.layer.borderWidth = 0.8;
    self.zaloBtn.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.zaloBtn addTarget:self action:@selector(openZaloDirectly) forControlEvents:UIControlEventTouchUpInside];
    [self.orangeHeaderBar addSubview:self.zaloBtn];

    // Nút Đóng
    self.closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeBtn.frame = CGRectMake(sw - 96, 48, 24, 26);
    [self.closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [self.closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
    [self.closeBtn addTarget:self action:@selector(closeOrangeHeader) forControlEvents:UIControlEventTouchUpInside];
    [self.orangeHeaderBar addSubview:self.closeBtn];

    // Hàng 1: Phí Ship & Khích Lệ đẩy lên Y = 50 (ngang hàng nút Zalo/Back)
    self.feeLabel = [[UILabel alloc] initWithFrame:CGRectMake(50, 50, sw - 150, 22)];
    self.feeLabel.textColor = [UIColor whiteColor];
    self.feeLabel.font = [UIFont boldSystemFontOfSize:12.0];
    self.feeLabel.text = @"🛵 Ship: --  |  🎁 Khích lệ: 0đ";
    [self.orangeHeaderBar addSubview:self.feeLabel];

    // Nút Gọi phụ (chỉ hiện khi 2 SĐT)
    self.callSecondBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.callSecondBtn.frame = CGRectMake(sw - 80, 78, 72, 22);
    self.callSecondBtn.backgroundColor = [UIColor systemGreenColor];
    [self.callSecondBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.callSecondBtn.titleLabel.font = [UIFont boldSystemFontOfSize:10.0];
    self.callSecondBtn.layer.cornerRadius = 4;
    self.callSecondBtn.hidden = YES;
    [self.callSecondBtn addTarget:self action:@selector(makeCallSecond) forControlEvents:UIControlEventTouchUpInside];
    [self.orangeHeaderBar addSubview:self.callSecondBtn];

    // Hàng 2: Ghi chú đẩy lên sát Y = 78
    self.noteLabel = [[UILabel alloc] initWithFrame:CGRectMake(50, 78, sw - 135, 20)];
    self.noteLabel.textColor = [UIColor yellowColor];
    self.noteLabel.font = [UIFont boldSystemFontOfSize:11.0];
    self.noteLabel.text = @"📌 Ghi chú: Không có ghi chú";
    [self.orangeHeaderBar addSubview:self.noteLabel];
}

- (void)onPanBubble:(UIPanGestureRecognizer *)p {
    CGPoint t = [p translationInView:self.view];
    self.bubbleBtn.center = CGPointMake(self.bubbleBtn.center.x + t.x, self.bubbleBtn.center.y + t.y);
    [p setTranslation:CGPointZero inView:self.view];
}

- (void)openOrangeHeader {
    self.bubbleBtn.hidden = YES;
    self.orangeHeaderBar.hidden = NO;
    [self scanAndRefresh];
}

- (void)closeOrangeHeader {
    self.orangeHeaderBar.hidden = YES;
    self.bubbleBtn.hidden = NO;
}

- (void)scanAndRefresh {
    self.orangeHeaderBar.alpha = 0.6;
    [DriverDataExtractor expandSheetAndExtract:^(NSString *shipFee, NSString *bonusFee, NSString *note, NSString *randomSecondPhone, UIImage *croppedOrderImage) {
        self.orangeHeaderBar.alpha = 1.0;
        self.orderImageToSend = croppedOrderImage;
        self.currentPhoneForZalo = randomSecondPhone;

        self.feeLabel.text = [NSString stringWithFormat:@"🛵 Ship: %@  |  🎁 Khích lệ: %@", shipFee, bonusFee];
        self.noteLabel.text = [NSString stringWithFormat:@"📌 Ghi chú: %@", note];

        if (randomSecondPhone.length > 0) {
            self.callSecondBtn.hidden = NO;
            self.callSecondBtn.accessibilityValue = randomSecondPhone;
            [self.callSecondBtn setTitle:[NSString stringWithFormat:@"📞 %@", [randomSecondPhone substringFromIndex:MAX(0, (int)randomSecondPhone.length - 4)]] forState:UIControlStateNormal];
            self.noteLabel.frame = CGRectMake(50, 78, [UIScreen mainScreen].bounds.size.width - 135, 20);
        } else {
            self.callSecondBtn.hidden = YES;
            self.noteLabel.frame = CGRectMake(50, 78, [UIScreen mainScreen].bounds.size.width - 60, 20);
        }
    }];
}

- (void)openZaloDirectly {
    if (self.orderImageToSend) {
        [UIPasteboard generalPasteboard].image = self.orderImageToSend;
    }
    NSURL *zaloURL = nil;
    if (self.currentPhoneForZalo.length >= 10) {
        zaloURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://zalo.me/%@", self.currentPhoneForZalo]];
    } else {
        zaloURL = [NSURL URLWithString:@"zalo://"];
    }
    [[UIApplication sharedApplication] openURL:zaloURL options:@{} completionHandler:nil];
}

- (void)makeCallSecond {
    NSString *phone = self.callSecondBtn.accessibilityValue;
    if (phone.length > 0) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"tel://%@", phone]] options:@{} completionHandler:nil];
    }
}

@end

#pragma mark - ENTRY POINT & HIT-TEST ĐỤC LỖ NÚT BACK

@interface DriverOverlayWindow : UIWindow
@end

@implementation DriverOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self.rootViewController.view) return nil;

    // Đục lỗ góc trái (X: 0 -> 48, Y: 0 -> 80) để bấm xuyên vào nút Trở về (<)
    if (point.x <= 48.0 && point.y <= 80.0) {
        return nil;
    }
    return hitView;
}
@end

static DriverOverlayWindow *gDriverWin = nil;

__attribute__((constructor))
static void dylib_init(void) {
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
                    if (scene) gDriverWin = [[DriverOverlayWindow alloc] initWithWindowScene:scene];
                }
                if (!gDriverWin) gDriverWin = [[DriverOverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

                gDriverWin.windowLevel = UIWindowLevelAlert + 1000.0;
                gDriverWin.backgroundColor = [UIColor clearColor];
                DriverHelperVC *vc = [[DriverHelperVC alloc] init];
                gDriverWin.rootViewController = vc;
                gDriverWin.hidden = NO;
            });
        });
    }];
}
