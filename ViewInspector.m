#import <UIKit/UIKit.h>
#import <Vision/Vision.h>
#import <objc/runtime.h>

#pragma mark - DIAGNOSTIC & LOGGING UTILITY

@interface DriverDiagnostic : NSObject
+ (NSString *)dumpCurrentHierarchy;
+ (UIViewController *)topViewController;
@end

@implementation DriverDiagnostic

+ (UIViewController *)topViewControllerWithRoot:(UIViewController *)root {
    if ([root isKindOfClass:[UINavigationController class]]) {
        return [self topViewControllerWithRoot:[(UINavigationController *)root visibleViewController]];
    }
    if ([root isKindOfClass:[UITabBarController class]]) {
        return [self topViewControllerWithRoot:[(UITabBarController *)root selectedViewController]];
    }
    if (root.presentedViewController) {
        return [self topViewControllerWithRoot:root.presentedViewController];
    }
    return root;
}

+ (UIViewController *)topViewController {
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
    return [self topViewControllerWithRoot:mainWin.rootViewController];
}

+ (void)dumpView:(UIView *)view indent:(int)indent output:(NSMutableString *)outStr {
    if (!view) return;
    for (int i = 0; i < indent; i++) [outStr appendString:@"  "];
    [outStr appendFormat:@"[%@] frame=(%.1f, %.1f, %.1f, %.1f)", NSStringFromClass([view class]), view.frame.origin.x, view.frame.origin.y, view.frame.size.width, view.frame.size.height];
    
    if ([view isKindOfClass:[UILabel class]]) {
        [outStr appendFormat:@" text=\"%@\"", [(UILabel *)view text]];
    } else if ([view isKindOfClass:[UIButton class]]) {
        [outStr appendFormat:@" title=\"%@\"", [(UIButton *)view titleForState:UIControlStateNormal]];
    }
    [outStr appendString:@"\n"];

    for (UIView *sub in view.subviews) {
        if (![NSStringFromClass([sub class]) containsString:@"Driver"]) {
            [self dumpView:sub indent:indent + 1 output:outStr];
        }
    }
}

+ (NSString *)dumpCurrentHierarchy {
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

    NSMutableString *outStr = [NSMutableString string];
    UIViewController *topVC = [self topViewController];
    [outStr appendFormat:@"=== TOP VC: %@ ===\n", NSStringFromClass([topVC class])];
    [self dumpView:mainWin indent:0 output:outStr];
    return outStr;
}

@end

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

+ (void)expandSheetAndExtract:(void(^)(NSString *shipFee, NSString *bonusFee, NSString *note, NSString *randomSecondPhone, UIImage *croppedOrderImage))completion {
    UIWindow *mainWin = [self getMainAppWindow];
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
            NSMutableArray<NSValue *> *convertedBoxes = [NSMutableArray array];

            for (VNRecognizedTextObservation *obs in request.results) {
                VNRecognizedText *top = [[obs topCandidates:1] firstObject];
                if (top) {
                    [strings addObject:top.string];
                    CGRect vBox = obs.boundingBox;
                    CGRect uiBox = CGRectMake(vBox.origin.x, 1.0 - vBox.origin.y - vBox.size.height, vBox.size.width, vBox.size.height);
                    [convertedBoxes addObject:[NSValue valueWithCGRect:uiBox]];
                }
            }

            __block NSString *shipFee = @"--";
            __block NSString *bonusFee = @"0đ";
            __block NSString *note = @"Không có ghi chú";
            NSMutableArray<NSString *> *shopPhones = [NSMutableArray array];
            NSRegularExpression *moneyRegex = [NSRegularExpression regularExpressionWithPattern:@"[0-9]{1,3}(?:\\.[0-9]{3})+" options:0 error:nil];

            for (NSUInteger i = 0; i < strings.count; i++) {
                NSString *l = strings[i];
                NSString *lower = [l lowercaseString];
                CGRect boxI = [convertedBoxes[i] CGRectValue];

                if ([lower containsString:@"mua hàng tại"] || [lower containsString:@"bánh mì"] || [lower containsString:@"quán"] || [lower containsString:@"chảo"] || [lower containsString:@"sâm"] || [lower containsString:@"cơm"]) {
                    NSArray *pList = [self extractPhonesFromText:l];
                    for (NSString *p in pList) {
                        if (![shopPhones containsObject:p]) [shopPhones addObject:p];
                    }
                }

                if ([lower containsString:@"phí giao hàng"] || [lower containsString:@"giao hàng"]) {
                    NSTextCheckingResult *sameLineMatch = [moneyRegex firstMatchInString:l options:0 range:NSMakeRange(0, l.length)];
                    if (sameLineMatch) {
                        shipFee = [[l substringWithRange:sameLineMatch.range] stringByAppendingString:@"đ"];
                    } else {
                        CGFloat midY_I = CGRectGetMidY(boxI);
                        CGFloat bestDist = 999.0;
                        NSString *bestVal = nil;

                        for (NSUInteger j = 0; j < strings.count; j++) {
                            if (i == j) continue;
                            CGRect boxJ = [convertedBoxes[j] CGRectValue];
                            CGFloat midY_J = CGRectGetMidY(boxJ);
                            if (boxJ.origin.x > boxI.origin.x && fabs(midY_J - midY_I) < 0.022) {
                                NSString *valStr = strings[j];
                                NSTextCheckingResult *valMatch = [moneyRegex firstMatchInString:valStr options:0 range:NSMakeRange(0, valStr.length)];
                                if (valMatch) {
                                    CGFloat dist = fabs(midY_J - midY_I);
                                    if (dist < bestDist) {
                                        bestDist = dist;
                                        bestVal = [valStr substringWithRange:valMatch.range];
                                    }
                                }
                            }
                        }
                        if (bestVal) {
                            shipFee = [bestVal stringByAppendingString:@"đ"];
                        }
                    }
                }

                if ([lower containsString:@"khích lệ"]) {
                    CGFloat midY_I = CGRectGetMidY(boxI);
                    for (NSUInteger j = 0; j < strings.count; j++) {
                        if (i == j) continue;
                        CGRect boxJ = [convertedBoxes[j] CGRectValue];
                        CGFloat midY_J = CGRectGetMidY(boxJ);
                        if (boxJ.origin.x > boxI.origin.x && fabs(midY_J - midY_I) < 0.022) {
                            NSString *valStr = strings[j];
                            if ([valStr isEqualToString:@"0"] || [valStr containsString:@"0"]) {
                                bonusFee = @"0đ";
                            } else {
                                NSTextCheckingResult *valMatch = [moneyRegex firstMatchInString:valStr options:0 range:NSMakeRange(0, valStr.length)];
                                if (valMatch) bonusFee = [[valStr substringWithRange:valMatch.range] stringByAppendingString:@"đ"];
                                else bonusFee = [valStr stringByAppendingString:@"đ"];
                            }
                            break;
                        }
                    }
                }

                if ([lower containsString:@"ghi chú thêm"] || [lower containsString:@"dặn dò"]) {
                    NSMutableArray<NSString *> *noteLines = [NSMutableArray array];
                    for (NSUInteger k = i + 1; k < strings.count; k++) {
                        NSString *nextCandidate = strings[k];
                        NSString *nextLower = [nextCandidate lowercaseString];
                        if ([nextLower containsString:@"tài xế vui lòng"] || 
                            [nextLower containsString:@"vuốt để nhận"] || 
                            [nextLower containsString:@"tài xế được nhận"]) {
                            break;
                        }
                        if (nextCandidate.length > 0) {
                            [noteLines addObject:nextCandidate];
                        }
                    }
                    if (noteLines.count > 0) {
                        note = [noteLines componentsJoinedByString:@", "];
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

@end

#pragma mark - UI LỚP PHỦ VÀ BỘ DEBUG HUD

@interface DriverHelperVC : UIViewController
@property (nonatomic, strong) UIView *orangeHeaderBar;
@property (nonatomic, strong) UILabel *feeLabel;
@property (nonatomic, strong) UILabel *noteLabel;
@property (nonatomic, strong) UIButton *callSecondBtn;
@property (nonatomic, strong) UIButton *zaloBtn;
@property (nonatomic, strong) UIButton *debugBtn;
@property (nonatomic, strong) UILabel *hudLogLabel;
@property (nonatomic, strong) UIImage *orderImageToSend;
@property (nonatomic, strong) NSString *currentPhoneForZalo;

- (void)showAndExtract;
- (void)hideHeader;
- (void)logEvent:(NSString *)text;
@end

static DriverHelperVC *gDriverVC = nil;

@implementation DriverHelperVC

- (void)viewDidLoad {
    [super viewDidLoad];
    gDriverVC = self;
    self.view.backgroundColor = [UIColor clearColor];
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;

    // 1. Lớp phủ nền cam 96pt
    self.orangeHeaderBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, sw, 96)];
    self.orangeHeaderBar.backgroundColor = [UIColor colorWithRed:0.96 green:0.35 blue:0.15 alpha:1.0];
    self.orangeHeaderBar.layer.shadowColor = [UIColor blackColor].CGColor;
    self.orangeHeaderBar.layer.shadowOpacity = 0.25;
    self.orangeHeaderBar.layer.shadowOffset = CGSizeMake(0, 1.5);
    self.orangeHeaderBar.layer.shadowRadius = 2.5;
    self.orangeHeaderBar.hidden = YES;
    [self.view addSubview:self.orangeHeaderBar];

    // Nút Zalo góc phải
    self.zaloBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.zaloBtn.frame = CGRectMake(sw - 68, 43, 62, 24);
    self.zaloBtn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.25];
    [self.zaloBtn setTitle:@"💬 Zalo" forState:UIControlStateNormal];
    [self.zaloBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.zaloBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
    self.zaloBtn.layer.cornerRadius = 12;
    self.zaloBtn.layer.borderWidth = 0.8;
    self.zaloBtn.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.zaloBtn addTarget:self action:@selector(openZaloDirectly) forControlEvents:UIControlEventTouchUpInside];
    [self.orangeHeaderBar addSubview:self.zaloBtn];

    // Dòng Phí Ship & Khích Lệ (Y = 44)
    self.feeLabel = [[UILabel alloc] initWithFrame:CGRectMake(46, 44, sw - 120, 22)];
    self.feeLabel.textColor = [UIColor whiteColor];
    self.feeLabel.font = [UIFont boldSystemFontOfSize:12.5];
    self.feeLabel.text = @"🛵 Ship: Đang tải... | 🎁 0đ";
    [self.orangeHeaderBar addSubview:self.feeLabel];

    // Hàng 2 (Y = 67): Ghi chú
    self.noteLabel = [[UILabel alloc] initWithFrame:CGRectMake(46, 67, sw - 128, 26)];
    self.noteLabel.textColor = [UIColor yellowColor];
    self.noteLabel.font = [UIFont boldSystemFontOfSize:10.5];
    self.noteLabel.numberOfLines = 2;
    self.noteLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.noteLabel.text = @"📌 Đang phân tích...";
    [self.orangeHeaderBar addSubview:self.noteLabel];

    // Nút Gọi phụ
    self.callSecondBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.callSecondBtn.frame = CGRectMake(sw - 78, 68, 72, 20);
    self.callSecondBtn.backgroundColor = [UIColor systemGreenColor];
    [self.callSecondBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.callSecondBtn.titleLabel.font = [UIFont boldSystemFontOfSize:10.0];
    self.callSecondBtn.layer.cornerRadius = 4;
    self.callSecondBtn.hidden = YES;
    [self.callSecondBtn addTarget:self action:@selector(makeCallSecond) forControlEvents:UIControlEventTouchUpInside];
    [self.orangeHeaderBar addSubview:self.callSecondBtn];

    // 2. NÚT CHẨN ĐOÁN
    self.debugBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.debugBtn.frame = CGRectMake(sw - 85, sh - 140, 78, 30);
    self.debugBtn.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.7];
    [self.debugBtn setTitle:@"🔍 Soi View" forState:UIControlStateNormal];
    [self.debugBtn setTitleColor:[UIColor cyanColor] forState:UIControlStateNormal];
    self.debugBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11.0];
    self.debugBtn.layer.cornerRadius = 15;
    self.debugBtn.layer.borderWidth = 1;
    self.debugBtn.layer.borderColor = [UIColor cyanColor].CGColor;
    [self.debugBtn addTarget:self action:@selector(onInspectTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.debugBtn];

    // 3. HUD LOG
    self.hudLogLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, sh - 110, sw - 20, 20)];
    self.hudLogLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
    self.hudLogLabel.textColor = [UIColor whiteColor];
    self.hudLogLabel.font = [UIFont systemFontOfSize:10.0];
    self.hudLogLabel.text = @" HUD: Dylib Sẵn Sàng...";
    self.hudLogLabel.layer.cornerRadius = 4;
    self.hudLogLabel.clipsToBounds = YES;
    [self.view addSubview:self.hudLogLabel];
}

- (void)logEvent:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.hudLogLabel.text = [NSString stringWithFormat:@" %@", text];
    });
}

- (void)onInspectTapped {
    NSString *dump = [DriverDiagnostic dumpCurrentHierarchy];
    [UIPasteboard generalPasteboard].string = dump;

    UIViewController *top = [DriverDiagnostic topViewController];
    NSString *topName = NSStringFromClass([top class]);

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Chẩn Đoán View"
                                                                   message:[NSString stringWithFormat:@"Top VC: %@\n(Đã copy toàn bộ cây View vào Clipboard!)", topName]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Bật Test Thanh Cam" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self showAndExtract];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showAndExtract {
    self.orangeHeaderBar.hidden = NO;
    self.orangeHeaderBar.alpha = 0.6;
    self.feeLabel.text = @"🛵 Ship: Đang tải... | 🎁 0đ";
    self.noteLabel.text = @"📌 Đang tải ghi chú...";

    [DriverDataExtractor expandSheetAndExtract:^(NSString *shipFee, NSString *bonusFee, NSString *note, NSString *randomSecondPhone, UIImage *croppedOrderImage) {
        self.orangeHeaderBar.alpha = 1.0;
        self.orderImageToSend = croppedOrderImage;
        self.currentPhoneForZalo = randomSecondPhone;

        self.feeLabel.text = [NSString stringWithFormat:@"🛵 Ship: %@ | 🎁 Khích lệ: %@", shipFee, bonusFee];
        self.noteLabel.text = [NSString stringWithFormat:@"📌 Ghi chú: %@", note];

        if (randomSecondPhone.length > 0) {
            self.callSecondBtn.hidden = NO;
            self.callSecondBtn.accessibilityValue = randomSecondPhone;
            [self.callSecondBtn setTitle:[NSString stringWithFormat:@"📞 %@", [randomSecondPhone substringFromIndex:MAX(0, (int)randomSecondPhone.length - 4)]] forState:UIControlStateNormal];
            self.noteLabel.frame = CGRectMake(46, 67, [UIScreen mainScreen].bounds.size.width - 128, 26);
        } else {
            self.callSecondBtn.hidden = YES;
            self.noteLabel.frame = CGRectMake(46, 67, [UIScreen mainScreen].bounds.size.width - 56, 26);
        }
    }];
}

- (void)hideHeader {
    self.orangeHeaderBar.hidden = YES;
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

#pragma mark - GLOBAL CONTROLLER & TOUCH HOOK CHẨN ĐOÁN

static void (*orig_presentVC)(id, SEL, UIViewController *, BOOL, id);
static void custom_presentVC(UIViewController *self, SEL _cmd, UIViewController *vcToPresent, BOOL flag, id completion) {
    [gDriverVC logEvent:[NSString stringWithFormat:@"Present: %@", NSStringFromClass([vcToPresent class])]];
    orig_presentVC(self, _cmd, vcToPresent, flag, completion);
}

static void (*orig_sendEvent)(id, SEL, UIEvent *);
static void custom_sendEvent(UIApplication *self, SEL _cmd, UIEvent *event) {
    orig_sendEvent(self, _cmd, event);
    if (event.type == UIEventTypeTouches) {
        for (UITouch *t in event.allTouches) {
            if (t.phase == UITouchPhaseEnded) {
                UIViewController *top = [DriverDiagnostic topViewController];
                [gDriverVC logEvent:[NSString stringWithFormat:@"Touch: TopVC = %@", NSStringFromClass([top class])]];
                break;
            }
        }
    }
}

#pragma mark - ENTRY POINT & HIT-TEST

@interface DriverOverlayWindow : UIWindow
@end

@implementation DriverOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self.rootViewController.view) return nil;

    // Đục lỗ góc trái (X: 0 -> 45, Y: 0 -> 75) cho nút Trở về (<)
    if (point.x <= 45.0 && point.y <= 75.0) {
        DriverHelperVC *vc = (DriverHelperVC *)self.rootViewController;
        [vc hideHeader];
        return nil;
    }
    return hitView;
}
@end

static DriverOverlayWindow *gDriverWin = nil;

__attribute__((constructor))
static void dylib_init(void) {
    // 1. Hook presentViewController:animated:completion:
    Class vcClass = [UIViewController class];
    Method mPresent = class_getInstanceMethod(vcClass, @selector(presentViewController:animated:completion:));
    orig_presentVC = (void(*)(id, SEL, UIViewController *, BOOL, id))method_getImplementation(mPresent);
    method_setImplementation(mPresent, (IMP)custom_presentVC);

    // 2. Hook UIApplication sendEvent:
    Class appClass = [UIApplication class];
    Method mSend = class_getInstanceMethod(appClass, @selector(sendEvent:));
    orig_sendEvent = (void(*)(id, SEL, UIEvent *))method_getImplementation(mSend);
    method_setImplementation(mSend, (IMP)custom_sendEvent);

    // 3. Khởi tạo Overlay Window
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
