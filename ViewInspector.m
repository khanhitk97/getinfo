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

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIGraphicsBeginImageContextWithOptions(mainWin.bounds.size, NO, 0.0);
            [mainWin drawViewHierarchyInRect:mainWin.bounds afterScreenUpdates:YES];
            UIImage *fullSnapshot = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();

            if (!fullSnapshot || !fullSnapshot.CGImage) {
                if (completion) completion(@"--", @"0", @"(Lỗi chụp màn hình)", nil, nil);
                return;
            }

            // Cắt khúc chi tiết món ăn gửi quán
            CGFloat scale = fullSnapshot.scale;
            CGFloat cropY = mainWin.bounds.size.height * 0.35;
            CGFloat cropH = mainWin.bounds.size.height * 0.55;
            CGRect scaledRect = CGRectMake(0, cropY * scale, mainWin.bounds.size.width * scale, cropH * scale);
            CGImageRef imgRef = CGImageCreateWithImageInRect(fullSnapshot.CGImage, scaledRect);
            UIImage *croppedOrderImg = [UIImage imageWithCGImage:imgRef scale:scale orientation:fullSnapshot.imageOrientation];
            CGImageRelease(imgRef);

            VNRecognizeTextRequest *req = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest * _Nonnull request, NSError * _Nullable error) {
                NSMutableArray<NSString *> *lines = [NSMutableArray array];
                for (VNRecognizedTextObservation *obs in request.results) {
                    VNRecognizedText *top = [[obs topCandidates:1] firstObject];
                    if (top) [lines addObject:top.string];
                }

                NSString *shipFee = @"--";
                NSString *bonusFee = @"0đ";
                NSString *note = @"Không có ghi chú";
                NSMutableArray<NSString *> *shopPhones = [NSMutableArray array];
                BOOL isShopSection = NO;

                for (NSUInteger i = 0; i < lines.count; i++) {
                    NSString *l = lines[i];
                    NSString *lower = [l lowercaseString];

                    // 1. Tìm SĐT ở mục "Mua hàng tại"
                    if ([lower containsString:@"mua hàng tại"]) {
                        isShopSection = YES;
                        continue;
                    }
                    if (isShopSection) {
                        if ([lower containsString:@"giao đến"] || [lower containsString:@"chi tiết đơn"]) {
                            isShopSection = NO;
                        } else {
                            NSArray *extracted = [self extractPhonesFromText:l];
                            for (NSString *p in extracted) {
                                if (![shopPhones containsObject:p]) [shopPhones addObject:p];
                            }
                        }
                    }

                    // 2. Bóc tách Phí giao hàng & Phí khích lệ
                    if ([lower containsString:@"phí giao hàng"]) {
                        if (i + 1 < lines.count) shipFee = lines[i+1];
                    }
                    if ([lower containsString:@"phí khích lệ"]) {
                        if (i + 1 < lines.count) bonusFee = lines[i+1];
                    }

                    // 3. Bóc tách Ghi chú
                    if ([lower containsString:@"ghi chú"] || [lower containsString:@"dặn dò"]) {
                        if (i + 1 < lines.count) note = lines[i+1];
                    }
                }

                // Nếu có từ 2 SĐT trở lên, bốc ngẫu nhiên 1 số để hiện nút phụ
                NSString *secondPhone = nil;
                if (shopPhones.count >= 2) {
                    NSUInteger randIdx = arc4random_uniform((uint32_t)shopPhones.count);
                    secondPhone = shopPhones[randIdx];
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

#pragma mark - UI LỚP PHỦ NỀN CAM (IPHONE 12 PRO MAX SAFE AREA)

@interface DriverHelperVC : UIViewController
@property (nonatomic, strong) UIButton *toggleBtn;
@property (nonatomic, strong) UIView *orangeHeaderBar;
@property (nonatomic, strong) UILabel *feeLabel;
@property (nonatomic, strong) UILabel *noteLabel;
@property (nonatomic, strong) UIButton *callSecondBtn;
@property (nonatomic, strong) UIButton *zaloBtn;
@property (nonatomic, strong) UIImage *orderImageToSend;
@property (nonatomic, strong) NSString *currentPhoneForZalo;
@property (nonatomic, assign) BOOL isExpanded;
@end

@implementation DriverHelperVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;

    // 1. Lớp phủ nền màu cam tiệp màu app (Top Safe Area cho 12 Pro Max: 47pt)
    // Chiều cao phủ từ đỉnh tai thỏ đến Y = 142pt (Đủ chứa 2 hàng phí & ghi chú)
    self.orangeHeaderBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, sw, 140)];
    self.orangeHeaderBar.backgroundColor = [UIColor colorWithRed:0.96 green:0.35 blue:0.15 alpha:1.0]; // Mã màu cam app
    self.orangeHeaderBar.layer.shadowColor = [UIColor blackColor].CGColor;
    self.orangeHeaderBar.layer.shadowOpacity = 0.25;
    self.orangeHeaderBar.layer.shadowOffset = CGSizeMake(0, 2);
    self.orangeHeaderBar.layer.shadowRadius = 4;
    self.orangeHeaderBar.hidden = YES;
    [self.view addSubview:self.orangeHeaderBar];

    // Chừa 52pt góc trái cho nút Trở về (<) của app gốc
    CGFloat contentX = 52.0;
    CGFloat contentW = sw - contentX - 10.0;

    // Nút Zalo góc trên bên phải (Y = 48, ngang hàng tiêu đề, tránh tai thỏ)
    self.zaloBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.zaloBtn.frame = CGRectMake(sw - 74, 48, 64, 28);
    self.zaloBtn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.25];
    [self.zaloBtn setTitle:@"💬 Zalo" forState:UIControlStateNormal];
    [self.zaloBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.zaloBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12.0];
    self.zaloBtn.layer.cornerRadius = 14;
    self.zaloBtn.layer.borderWidth = 1.0;
    self.zaloBtn.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.zaloBtn addTarget:self action:@selector(openZaloDirectly) forControlEvents:UIControlEventTouchUpInside];
    [self.orangeHeaderBar addSubview:self.zaloBtn];

    // Hàng 1: Phí giao hàng & Phí khích lệ (Y = 82)
    self.feeLabel = [[UILabel alloc] initWithFrame:CGRectMake(contentX, 82, contentW - 90, 24)];
    self.feeLabel.textColor = [UIColor whiteColor];
    self.feeLabel.font = [UIFont boldSystemFontOfSize:11.5];
    self.feeLabel.text = @"🛵 Ship: --  |  🎁 Khích lệ: --";
    [self.orangeHeaderBar addSubview:self.feeLabel];

    // Nút Gọi phụ (chỉ hiện khi có 2 SĐT, nằm bên phải hàng Phí)
    self.callSecondBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.callSecondBtn.frame = CGRectMake(sw - 88, 80, 78, 26);
    self.callSecondBtn.backgroundColor = [UIColor systemGreenColor];
    [self.callSecondBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.callSecondBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11.0];
    self.callSecondBtn.layer.cornerRadius = 5;
    self.callSecondBtn.hidden = YES;
    [self.callSecondBtn addTarget:self action:@selector(makeCallSecond) forControlEvents:UIControlEventTouchUpInside];
    [self.orangeHeaderBar addSubview:self.callSecondBtn];

    // Hàng 2: Ghi chú dặn dò (Y = 110)
    self.noteLabel = [[UILabel alloc] initWithFrame:CGRectMake(contentX, 110, contentW, 22)];
    self.noteLabel.textColor = [UIColor yellowColor];
    self.noteLabel.font = [UIFont boldSystemFontOfSize:11.0];
    self.noteLabel.text = @"📌 Đang tải đơn...";
    [self.orangeHeaderBar addSubview:self.noteLabel];

    // Nút kích hoạt nổi thu nhỏ ở góc phải thanh cam
    self.toggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleBtn.frame = CGRectMake(sw - 62, 48, 54, 28);
    self.toggleBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.25];
    [self.toggleBtn setTitle:@"🛵 Đơn" forState:UIControlStateNormal];
    [self.toggleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
    self.toggleBtn.layer.cornerRadius = 14;
    self.toggleBtn.layer.borderWidth = 1.0;
    self.toggleBtn.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.toggleBtn addTarget:self action:@selector(toggleOrangeHeader) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.toggleBtn];
}

- (void)toggleOrangeHeader {
    self.isExpanded = !self.isExpanded;
    if (self.isExpanded) {
        self.toggleBtn.hidden = YES;
        self.orangeHeaderBar.hidden = NO;
        [self scanAndRefresh];
    } else {
        self.orangeHeaderBar.hidden = YES;
        self.toggleBtn.hidden = NO;
    }
}

- (void)scanAndRefresh {
    self.orangeHeaderBar.alpha = 0.5;
    [DriverDataExtractor expandSheetAndExtract:^(NSString *shipFee, NSString *bonusFee, NSString *note, NSString *randomSecondPhone, UIImage *croppedOrderImage) {
        self.orangeHeaderBar.alpha = 1.0;
        self.orderImageToSend = croppedOrderImage;
        self.currentPhoneForZalo = randomSecondPhone;

        // Cập nhật phí
        self.feeLabel.text = [NSString stringWithFormat:@"🛵 Ship: %@  |  🎁 Khích lệ: %@", shipFee, bonusFee];
        self.noteLabel.text = [NSString stringWithFormat:@"📌 Ghi chú: %@", note];

        // Xử lý nút Gọi: Có 2 số mới hiện nút Gọi random, 1 số thì ẩn
        if (randomSecondPhone.length > 0) {
            self.callSecondBtn.hidden = NO;
            self.callSecondBtn.accessibilityValue = randomSecondPhone;
            [self.callSecondBtn setTitle:[NSString stringWithFormat:@"📞 %@", [randomSecondPhone substringFromIndex:MAX(0, (int)randomSecondPhone.length - 4)]] forState:UIControlStateNormal];
        } else {
            self.callSecondBtn.hidden = YES;
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
    // 1. Cho phép chạm xuyên qua toàn bộ vùng trống phía dưới
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self.rootViewController.view) return nil;

    // 2. ĐỤC LỖ GÓC TRÁI: (X: 0 -> 52pt, Y: 0 -> 100pt) để bấm xuyên vào nút Trở về (<) của app
    if (point.x <= 52.0 && point.y <= 100.0) {
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
