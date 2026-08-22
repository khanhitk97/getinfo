#import <UIKit/UIKit.h>
#import <Vision/Vision.h>

#pragma mark - DATA EXTRACTION ENGINE (FIX CHÍNH XÁC THEO TỌA ĐỘ)

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

            // Cắt chi tiết món ăn
            CGFloat scale = fullSnapshot.scale;
            CGFloat cropY = mainWin.bounds.size.height * 0.35;
            CGFloat cropH = mainWin.bounds.size.height * 0.55;
            CGRect scaledRect = CGRectMake(0, cropY * scale, mainWin.bounds.size.width * scale, cropH * scale);
            CGImageRef imgRef = CGImageCreateWithImageInRect(fullSnapshot.CGImage, scaledRect);
            UIImage *croppedOrderImg = [UIImage imageWithCGImage:imgRef scale:scale orientation:fullSnapshot.imageOrientation];
            CGImageRelease(imgRef);

            VNRecognizeTextRequest *req = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest * _Nonnull request, NSError * _Nullable error) {
                
                struct TextItem {
                    __unsafe_unretained NSString *text;
                    CGRect box;
                };
                
                NSMutableArray<NSValue *> *boxes = [NSMutableArray array];
                NSMutableArray<NSString *> *strings = [NSMutableArray array];

                for (VNRecognizedTextObservation *obs in request.results) {
                    VNRecognizedText *top = [[obs topCandidates:1] firstObject];
                    if (top) {
                        [strings addObject:top.string];
                        [boxes addObject:[NSValue valueWithCGRect:obs.boundingBox]];
                    }
                }

                __block NSString *shipFee = @"--";
                __block NSString *bonusFee = @"0đ";
                __block NSString *note = @"Không có ghi chú";
                NSMutableArray<NSString *> *shopPhones = [NSMutableArray array];

                for (NSUInteger i = 0; i < strings.count; i++) {
                    NSString *l = strings[i];
                    NSString *lower = [l lowercaseString];
                    CGRect box = [boxes[i] CGRectValue];

                    // 1. Lọc SĐT trong phần "Mua hàng tại"
                    if ([lower containsString:@"mua hàng tại"] || [lower containsString:@"bún thịt"] || [lower containsString:@"quán"]) {
                        NSArray *pList = [self extractPhonesFromText:l];
                        for (NSString *p in pList) {
                            if (![shopPhones containsObject:p]) [shopPhones addObject:p];
                        }
                    }

                    // 2. Tìm giá trị cùng hàng ngang với "Phí giao hàng" (Khoảng chênh lệch Y < 0.02)
                    if ([lower containsString:@"phí giao hàng"]) {
                        for (NSUInteger j = 0; j < strings.count; j++) {
                            if (i == j) continue;
                            CGRect valBox = [boxes[j] CGRectValue];
                            if (fabs(valBox.origin.y - box.origin.y) < 0.025 && valBox.origin.x > box.origin.x) {
                                NSString *numOnly = [[strings[j] componentsSeparatedByCharactersInSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789."] invertedSet]] componentsJoinedByString:@""];
                                if (numOnly.length > 0) shipFee = [numOnly stringByAppendingString:@"đ"];
                                break;
                            }
                        }
                    }

                    // 3. Tìm giá trị cùng hàng ngang với "Phí khích lệ"
                    if ([lower containsString:@"phí khích lệ"]) {
                        for (NSUInteger j = 0; j < strings.count; j++) {
                            if (i == j) continue;
                            CGRect valBox = [boxes[j] CGRectValue];
                            if (fabs(valBox.origin.y - box.origin.y) < 0.025 && valBox.origin.x > box.origin.x) {
                                NSString *numOnly = [[strings[j] componentsSeparatedByCharactersInSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789."] invertedSet]] componentsJoinedByString:@""];
                                if (numOnly.length > 0) bonusFee = [numOnly stringByAppendingString:@"đ"];
                                break;
                            }
                        }
                    }

                    // 4. Bóc tách chính xác Ghi chú dặn dò (Bỏ qua câu disclaimer "Tài xế vui lòng đọc kỹ...")
                    if ([lower containsString:@"ghi chú thêm"] || [lower containsString:@"dặn dò shipper"]) {
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
                    secondPhone = shopPhones[1]; // Lấy SĐT thứ 2
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

#pragma mark - UI LỚP PHỦ NỀN CAM CHUẨN IPHONE 12 PRO MAX

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

    // Lớp nền màu cam phủ từ Y = 84 xuống Y = 148 (Chừa trọn vẹn Navigation Header + Tên Quán + Nút < ở trên)
    self.orangeHeaderBar = [[UIView alloc] initWithFrame:CGRectMake(0, 84, sw, 64)];
    self.orangeHeaderBar.backgroundColor = [UIColor colorWithRed:0.96 green:0.35 blue:0.15 alpha:1.0];
    self.orangeHeaderBar.layer.shadowColor = [UIColor blackColor].CGColor;
    self.orangeHeaderBar.layer.shadowOpacity = 0.25;
    self.orangeHeaderBar.layer.shadowOffset = CGSizeMake(0, 2);
    self.orangeHeaderBar.layer.shadowRadius = 4;
    self.orangeHeaderBar.hidden = YES;
    [self.view addSubview:self.orangeHeaderBar];

    // Nút Zalo đặt ở góc phải thanh Nav gốc (Y = 48, ngang hàng tên quán, né tai thỏ)
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
    [self.view addSubview:self.zaloBtn];

    // Hàng 1: Phí Ship & Phí Khích Lệ (Y = 6 trong bảng cam)
    self.feeLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 6, sw - 95, 24)];
    self.feeLabel.textColor = [UIColor whiteColor];
    self.feeLabel.font = [UIFont boldSystemFontOfSize:12.5];
    self.feeLabel.text = @"🛵 Ship: --  |  🎁 Khích lệ: 0đ";
    [self.orangeHeaderBar addSubview:self.feeLabel];

    // Nút Gọi phụ (chỉ hiện khi có 2 SĐT)
    self.callSecondBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.callSecondBtn.frame = CGRectMake(sw - 80, 5, 72, 24);
    self.callSecondBtn.backgroundColor = [UIColor systemGreenColor];
    [self.callSecondBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.callSecondBtn.titleLabel.font = [UIFont boldSystemFontOfSize:10.5];
    self.callSecondBtn.layer.cornerRadius = 5;
    self.callSecondBtn.hidden = YES;
    [self.callSecondBtn addTarget:self action:@selector(makeCallSecond) forControlEvents:UIControlEventTouchUpInside];
    [self.orangeHeaderBar addSubview:self.callSecondBtn];

    // Hàng 2: Ghi chú (Y = 34 trong bảng cam)
    self.noteLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 34, sw - 24, 22)];
    self.noteLabel.textColor = [UIColor yellowColor];
    self.noteLabel.font = [UIFont boldSystemFontOfSize:11.5];
    self.noteLabel.text = @"📌 Ghi chú: Không có ghi chú";
    [self.orangeHeaderBar addSubview:self.noteLabel];

    // Nút kích hoạt nổi
    self.toggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleBtn.frame = CGRectMake(sw - 60, 48, 52, 26);
    self.toggleBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.25];
    [self.toggleBtn setTitle:@"🛵 Đơn" forState:UIControlStateNormal];
    [self.toggleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11.0];
    self.toggleBtn.layer.cornerRadius = 13;
    self.toggleBtn.layer.borderWidth = 0.8;
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

        self.feeLabel.text = [NSString stringWithFormat:@"🛵 Ship: %@  |  🎁 Khích lệ: %@", shipFee, bonusFee];
        self.noteLabel.text = [NSString stringWithFormat:@"📌 Ghi chú: %@", note];

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

#pragma mark - ENTRY POINT & HIT-TEST

@interface DriverOverlayWindow : UIWindow
@end

@implementation DriverOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self.rootViewController.view) return nil;
    // Đục lỗ vùng nút Back (<) của app gốc
    if (point.x <= 55.0 && point.y <= 85.0) return nil;
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
