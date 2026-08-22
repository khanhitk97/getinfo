#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#pragma mark - 1. DATA EXTRACTOR & CROP LOGIC TỪ RAM

@interface DriverDataExtractor : NSObject
+ (BOOL)hasOrderDetailKeywords;
+ (void)extractDataDirectlyFromRAM:(void(^)(NSString *shipFee, NSString *bonusFee, NSString *note, NSString *secondPhone))completion;
+ (void)captureOrderDetailSection:(void(^)(UIImage *croppedImage))completion;
@end

@implementation DriverDataExtractor

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

+ (BOOL)scanForOrderKeywordsInView:(UIView *)v {
    if (!v || v.hidden || v.alpha < 0.05) return NO;

    NSString *acc = v.accessibilityLabel.lowercaseString;
    if ([acc containsString:@"vuốt để nhận"] || 
        [acc containsString:@"thông tin đơn trước khi nhận"] || 
        [acc containsString:@"phí giao hàng"] ||
        [acc containsString:@"chi tiết đơn"]) {
        return YES;
    }

    @try {
        id t = [v valueForKey:@"text"];
        if ([t isKindOfClass:[NSString class]]) {
            NSString *str = [(NSString *)t lowercaseString];
            if ([str containsString:@"vuốt để nhận"] || 
                [str containsString:@"thông tin đơn trước khi nhận"] || 
                [str containsString:@"phí giao hàng"]) {
                return YES;
            }
        }
    } @catch (NSException *e) {}

    for (UIView *sub in v.subviews) {
        if (![NSStringFromClass([sub class]) containsString:@"Driver"]) {
            if ([self scanForOrderKeywordsInView:sub]) return YES;
        }
    }
    return NO;
}

+ (BOOL)hasOrderDetailKeywords {
    UIWindow *win = [self getMainAppWindow];
    return [self scanForOrderKeywordsInView:win];
}

+ (void)collectRCTTexts:(UIView *)v list:(NSMutableArray<NSString *> *)list {
    if (!v || v.hidden || v.alpha < 0.05) return;

    NSString *vClass = NSStringFromClass([v class]);
    if ([vClass containsString:@"RCTTextView"] || [vClass containsString:@"RCTParagraphComponentView"]) {
        NSString *acc = v.accessibilityLabel;
        if (acc.length > 0) {
            [list addObject:acc];
        } else {
            @try {
                id t = [v valueForKey:@"text"];
                if ([t isKindOfClass:[NSString class]] && [(NSString *)t length] > 0) {
                    [list addObject:(NSString *)t];
                }
            } @catch (NSException *e) {}
        }
    }

    for (UIView *sub in v.subviews) {
        if (![NSStringFromClass([sub class]) containsString:@"Driver"]) {
            [self collectRCTTexts:sub list:list];
        }
    }
}

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

+ (void)extractDataDirectlyFromRAM:(void(^)(NSString *shipFee, NSString *bonusFee, NSString *note, NSString *secondPhone))completion {
    UIWindow *mainWin = [self getMainAppWindow];
    if (!mainWin) {
        if (completion) completion(@"--", @"0đ", @"(Lỗi)", nil);
        return;
    }

    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    [self collectRCTTexts:mainWin list:texts];

    __block NSString *shipFee = @"--";
    __block NSString *bonusFee = @"0đ";
    __block NSString *note = @"Không có ghi chú";
    NSMutableArray<NSString *> *shopPhones = [NSMutableArray array];
    NSRegularExpression *moneyRegex = [NSRegularExpression regularExpressionWithPattern:@"[0-9]{1,3}(?:\\.[0-9]{3})+" options:0 error:nil];

    for (NSUInteger i = 0; i < texts.count; i++) {
        NSString *str = texts[i];
        NSString *lower = [str lowercaseString];

        // SĐT quán
        if ([lower containsString:@"mua hàng tại"] || [lower containsString:@"quán"] || [lower containsString:@"bánh mì"] || [lower containsString:@"cơm"]) {
            NSArray *pList = [self extractPhonesFromText:str];
            for (NSString *p in pList) {
                if (![shopPhones containsObject:p]) [shopPhones addObject:p];
            }
        }

        // Phí giao hàng
        if ([lower containsString:@"phí giao hàng"] || [lower containsString:@"giao hàng"]) {
            NSTextCheckingResult *match = [moneyRegex firstMatchInString:str options:0 range:NSMakeRange(0, str.length)];
            if (match) {
                shipFee = [[str substringWithRange:match.range] stringByAppendingString:@"đ"];
            } else if (i + 1 < texts.count) {
                NSString *next = texts[i + 1];
                NSTextCheckingResult *nMatch = [moneyRegex firstMatchInString:next options:0 range:NSMakeRange(0, next.length)];
                if (nMatch) shipFee = [[next substringWithRange:nMatch.range] stringByAppendingString:@"đ"];
            }
        }

        // Phí khích lệ
        if ([lower containsString:@"khích lệ"] || [lower containsString:@"khich le"]) {
            NSTextCheckingResult *match = [moneyRegex firstMatchInString:str options:0 range:NSMakeRange(0, str.length)];
            if (match) {
                bonusFee = [[str substringWithRange:match.range] stringByAppendingString:@"đ"];
            } else if (i + 1 < texts.count) {
                NSString *next = texts[i + 1];
                NSTextCheckingResult *nMatch = [moneyRegex firstMatchInString:next options:0 range:NSMakeRange(0, next.length)];
                if (nMatch) {
                    bonusFee = [[next substringWithRange:nMatch.range] stringByAppendingString:@"đ"];
                } else if ([next isEqualToString:@"0"]) {
                    bonusFee = @"0đ";
                }
            }
        }

        // Ghi chú
        if ([lower containsString:@"ghi chú"] || [lower containsString:@"dặn dò"]) {
            if (i + 1 < texts.count) {
                NSString *next = texts[i + 1];
                NSString *nLower = [next lowercaseString];
                if (![nLower containsString:@"vuốt để nhận"] && ![nLower containsString:@"tài xế"]) {
                    note = next;
                }
            }
        }
    }

    NSString *secondPhone = nil;
    if (shopPhones.count >= 2) {
        secondPhone = shopPhones[1];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (completion) completion(shipFee, bonusFee, note, secondPhone);
    });
}

#pragma mark - LOGIC CUỘN & CẮT ĐÚNG KHỐI CHI TIẾT ĐƠN HÀNG

+ (UIScrollView *)findScrollViewInView:(UIView *)v {
    if ([v isKindOfClass:[UIScrollView class]]) return (UIScrollView *)v;
    for (UIView *sub in v.subviews) {
        UIScrollView *found = [self findScrollViewInView:sub];
        if (found) return found;
    }
    return nil;
}

+ (UIView *)findViewMatchingCondition:(UIView *)v match:(BOOL(^)(NSString *text))matchBlock {
    if (!v || v.hidden) return nil;
    NSString *acc = v.accessibilityLabel;
    if (acc && matchBlock(acc)) return v;

    @try {
        id t = [v valueForKey:@"text"];
        if ([t isKindOfClass:[NSString class]] && matchBlock((NSString *)t)) return v;
    } @catch (NSException *e) {}

    for (UIView *sub in v.subviews) {
        UIView *found = [self findViewMatchingCondition:sub match:matchBlock];
        if (found) return found;
    }
    return nil;
}

+ (void)captureOrderDetailSection:(void(^)(UIImage *croppedImage))completion {
    UIWindow *mainWin = [self getMainAppWindow];
    if (!mainWin) {
        if (completion) completion(nil);
        return;
    }

    UIScrollView *scrollView = [self findScrollViewInView:mainWin];

    // 1. Tìm View bắt đầu: "Chi tiết đơn hàng"
    UIView *startView = [self findViewMatchingCondition:mainWin match:^BOOL(NSString *text) {
        NSString *lower = text.lowercaseString;
        return [lower containsString:@"chi tiết đơn hàng"] || [lower containsString:@"chi tiết đơn"];
    }];

    // 2. Tìm View kết thúc: "Tổng ... món"
    UIView *endView = [self findViewMatchingCondition:mainWin match:^BOOL(NSString *text) {
        NSString *lower = text.lowercaseString;
        return [lower containsString:@"tổng"] && [lower containsString:@"món"];
    }];

    // 3. Tự động cuộn để đưa toàn bộ phần đơn hàng vào khung nhìn
    if (scrollView && startView) {
        CGRect startRectInScroll = [startView convertRect:startView.bounds toView:scrollView];
        CGFloat targetOffsetY = MAX(0, startRectInScroll.origin.y - 10.0);
        [scrollView setContentOffset:CGPointMake(0, targetOffsetY) animated:NO];
    }

    // Đợi 0.1s cho giao diện ổn định sau cuộn rồi crop
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CGRect cropRect = CGRectZero;
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;

        if (startView && endView) {
            CGRect startRect = [startView convertRect:startView.bounds toView:mainWin];
            CGRect endRect = [endView convertRect:endView.bounds toView:mainWin];

            CGFloat topY = MAX(0, startRect.origin.y - 12.0);
            CGFloat bottomY = endRect.origin.y + endRect.size.height + 14.0;
            CGFloat height = MAX(100.0, bottomY - topY);

            cropRect = CGRectMake(12.0, topY, screenWidth - 24.0, height);
        } else {
            // Dự phòng nếu không bắt được mốc
            cropRect = CGRectMake(12.0, 160.0, screenWidth - 24.0, 420.0);
        }

        // Chụp cửa sổ gốc
        UIGraphicsBeginImageContextWithOptions(mainWin.bounds.size, NO, [UIScreen mainScreen].scale);
        [mainWin drawViewHierarchyInRect:mainWin.bounds afterScreenUpdates:YES];
        UIImage *fullScreen = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        if (!fullScreen) {
            if (completion) completion(nil);
            return;
        }

        // Cắt đúng hình chữ nhật chứa danh sách món
        CGFloat scale = fullScreen.scale;
        CGRect scaledCropRect = CGRectMake(cropRect.origin.x * scale,
                                           cropRect.origin.y * scale,
                                           cropRect.size.width * scale,
                                           cropRect.size.height * scale);

        CGImageRef imageRef = CGImageCreateWithImageInRect(fullScreen.CGImage, scaledCropRect);
        UIImage *croppedImage = [UIImage imageWithCGImage:imageRef scale:fullScreen.scale orientation:fullScreen.imageOrientation];
        CGImageRelease(imageRef);

        if (completion) completion(croppedImage);
    });
}

@end

#pragma mark - 2. GIAO DIỆN THANH OVERLAY

@interface DriverHelperVC : UIViewController
@property (nonatomic, strong) UIView *orangeBar;
@property (nonatomic, strong) UILabel *backIconLabel;
@property (nonatomic, strong) UILabel *feeLabel;
@property (nonatomic, strong) UILabel *noteLabel;
@property (nonatomic, strong) UIButton *callSecondBtn;
@property (nonatomic, strong) UIButton *zaloBtn;
@property (nonatomic, assign) BOOL isShowing;

- (void)showAndExtract;
- (void)hideHeader;
- (void)syncUIState;
@end

static DriverHelperVC *gDriverVC = nil;

@implementation DriverHelperVC

- (void)viewDidLoad {
    [super viewDidLoad];
    gDriverVC = self;
    self.view.backgroundColor = [UIColor clearColor];
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;

    // 1. Thanh Top Bar 96pt
    self.orangeBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, sw, 96)];
    self.orangeBar.backgroundColor = [UIColor colorWithRed:0.96 green:0.35 blue:0.15 alpha:1.0];
    self.orangeBar.layer.shadowColor = [UIColor blackColor].CGColor;
    self.orangeBar.layer.shadowOpacity = 0.25;
    self.orangeBar.layer.shadowOffset = CGSizeMake(0, 2);
    self.orangeBar.layer.shadowRadius = 3.0;
    self.orangeBar.hidden = YES;
    [self.view addSubview:self.orangeBar];

    // 2. Biểu tượng Back trực quan (‹)
    self.backIconLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 39, 36, 44)];
    self.backIconLabel.text = @"‹";
    self.backIconLabel.textColor = [UIColor whiteColor];
    self.backIconLabel.font = [UIFont systemFontOfSize:42.0 weight:UIFontWeightMedium];
    self.backIconLabel.textAlignment = NSTextAlignmentCenter;
    self.backIconLabel.userInteractionEnabled = NO;
    [self.orangeBar addSubview:self.backIconLabel];

    // 3. Nút Zalo (Ngang hàng nút Back: Y = 44, H = 34)
    self.zaloBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.zaloBtn.frame = CGRectMake(sw - 80, 44, 72, 34);
    self.zaloBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.41 blue:1.0 alpha:0.9];
    [self.zaloBtn setTitle:@"💬 Zalo" forState:UIControlStateNormal];
    [self.zaloBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.zaloBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13.0];
    self.zaloBtn.layer.cornerRadius = 8;
    self.zaloBtn.layer.borderWidth = 1.0;
    self.zaloBtn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
    [self.zaloBtn addTarget:self action:@selector(captureAndShareZalo) forControlEvents:UIControlEventTouchUpInside];
    [self.orangeBar addSubview:self.zaloBtn];

    // Dòng Phí Ship & Khích Lệ
    self.feeLabel = [[UILabel alloc] initWithFrame:CGRectMake(50, 44, sw - 136, 22)];
    self.feeLabel.textColor = [UIColor whiteColor];
    self.feeLabel.font = [UIFont boldSystemFontOfSize:12.5];
    self.feeLabel.text = @"🛵 Ship: Đang đọc... | 🎁 --";
    [self.orangeBar addSubview:self.feeLabel];

    // Dòng Ghi Chú
    self.noteLabel = [[UILabel alloc] initWithFrame:CGRectMake(50, 67, sw - 136, 26)];
    self.noteLabel.textColor = [UIColor yellowColor];
    self.noteLabel.font = [UIFont boldSystemFontOfSize:10.5];
    self.noteLabel.numberOfLines = 2;
    self.noteLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.noteLabel.text = @"📌 Đang đọc ghi chú...";
    [self.orangeBar addSubview:self.noteLabel];

    // Nút Gọi Phụ
    self.callSecondBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.callSecondBtn.frame = CGRectMake(sw - 80, 10, 72, 24);
    self.callSecondBtn.backgroundColor = [UIColor systemGreenColor];
    [self.callSecondBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.callSecondBtn.titleLabel.font = [UIFont boldSystemFontOfSize:10.5];
    self.callSecondBtn.layer.cornerRadius = 4;
    self.callSecondBtn.hidden = YES;
    [self.callSecondBtn addTarget:self action:@selector(makeCallSecond) forControlEvents:UIControlEventTouchUpInside];
    [self.orangeBar addSubview:self.callSecondBtn];
}

- (void)syncUIState {
    BOOL hasOrder = [DriverDataExtractor hasOrderDetailKeywords];
    if (hasOrder) {
        if (!self.isShowing) {
            [self showAndExtract];
        }
    } else {
        if (self.isShowing) {
            [self hideHeader];
        }
    }
}

- (void)showAndExtract {
    self.isShowing = YES;
    self.orangeBar.hidden = NO;

    [DriverDataExtractor extractDataDirectlyFromRAM:^(NSString *shipFee, NSString *bonusFee, NSString *note, NSString *secondPhone) {
        self.feeLabel.text = [NSString stringWithFormat:@"🛵 Ship: %@ | 🎁 Khích lệ: %@", shipFee, bonusFee];
        self.noteLabel.text = [NSString stringWithFormat:@"📌 Ghi chú: %@", note];

        NSString *digitsBonus = [[bonusFee componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
        long long bonusValue = [digitsBonus longLongValue];

        if (bonusValue >= 10000) {
            self.orangeBar.backgroundColor = [UIColor colorWithRed:0.18 green:0.80 blue:0.44 alpha:1.0];
        } else {
            self.orangeBar.backgroundColor = [UIColor colorWithRed:0.96 green:0.35 blue:0.15 alpha:1.0];
        }

        if (secondPhone.length > 0) {
            self.callSecondBtn.hidden = NO;
            self.callSecondBtn.accessibilityValue = secondPhone;
            [self.callSecondBtn setTitle:[NSString stringWithFormat:@"📞 %@", [secondPhone substringFromIndex:MAX(0, (int)secondPhone.length - 4)]] forState:UIControlStateNormal];
        } else {
            self.callSecondBtn.hidden = YES;
        }
    }];
}

- (void)hideHeader {
    self.isShowing = NO;
    self.orangeBar.hidden = YES;
}

// Bấm Zalo: Cắt đúng phần chi tiết đơn và mở bảng chia sẻ (Không ẩn thanh bar)
- (void)captureAndShareZalo {
    [DriverDataExtractor captureOrderDetailSection:^(UIImage *croppedImage) {
        if (!croppedImage) return;

        UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[croppedImage] applicationActivities:nil];
        
        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
            activityVC.popoverPresentationController.sourceView = self.zaloBtn;
            activityVC.popoverPresentationController.sourceRect = self.zaloBtn.bounds;
        }

        [self presentViewController:activityVC animated:YES completion:nil];
    }];
}

- (void)makeCallSecond {
    NSString *phone = self.callSecondBtn.accessibilityValue;
    if (phone.length > 0) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"tel://%@", phone]] options:@{} completionHandler:nil];
    }
}

@end

#pragma mark - 3. HOOK TOUCH EVENT

static void (*orig_sendEvent)(id, SEL, UIEvent *);
static void custom_sendEvent(UIApplication *self, SEL _cmd, UIEvent *event) {
    orig_sendEvent(self, _cmd, event);
    if (event.type == UIEventTypeTouches) {
        for (UITouch *t in event.allTouches) {
            if (t.phase == UITouchPhaseEnded) {
                CGPoint loc = [t locationInView:nil];
                NSString *acc = t.view.accessibilityLabel ?: @"";

                // 1. Chạm góc trên bên trái (nút Trở về <) -> ĐÓNG NGAY
                if (loc.x <= 75.0 && loc.y <= 100.0) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [gDriverVC hideHeader];
                    });
                    break;
                }

                // 2. Chạm vào thông báo Quay lại danh sách đơn -> ĐÓNG NGAY
                if ([acc containsString:@"Quay lại"] || [acc containsString:@"danh sách đơn"]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [gDriverVC hideHeader];
                    });
                    break;
                }

                // 3. Tự động đồng bộ UI sau 0.3s
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [gDriverVC syncUIState];
                });
                break;
            }
        }
    }
}

#pragma mark - 4. OVERLAY WINDOW HIT TEST

@interface DriverOverlayWindow : UIWindow
@end

@implementation DriverOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    DriverHelperVC *vc = (DriverHelperVC *)self.rootViewController;

    // Vùng nút Back góc trên bên trái: Ẩn thanh cam và xuyên chạm 100% xuống app gốc
    if (point.x <= 75.0 && point.y <= 100.0) {
        [vc hideHeader];
        return nil; 
    }

    UIView *hitView = [super hitTest:point withEvent:event];

    // Bắt chạm trên nút Zalo và Gọi phụ
    if (hitView == vc.zaloBtn || hitView == vc.callSecondBtn) {
        return hitView;
    }
    
    // Mọi điểm khác xuyên chạm thẳng xuống app gốc
    if (hitView == self.rootViewController.view || hitView == vc.orangeBar || hitView == vc.feeLabel || hitView == vc.noteLabel || hitView == vc.backIconLabel) {
        return nil; 
    }
    return hitView;
}
@end

static DriverOverlayWindow *gDriverWin = nil;

__attribute__((constructor))
static void dylib_init(void) {
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
