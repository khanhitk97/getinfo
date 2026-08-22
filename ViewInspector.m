#import <UIKit/UIKit.h>
#import <Vision/Vision.h>
#import <objc/runtime.h>

#pragma mark - DATA EXTRACTION ENGINE

@interface DriverDataExtractor : NSObject
+ (void)expandSheetAndExtract:(void(^)(NSString *shipFee, NSString *bonusFee, NSString *note, NSString *randomSecondPhone, UIImage *croppedOrderImage))completion;
+ (BOOL)isReactNativeOrderDetailOpen;
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

+ (UIScrollView *)findMainScrollView:(UIView *)view {
    if (!view) return nil;
    if ([view isKindOfClass:[UIScrollView class]]) {
        UIScrollView *sv = (UIScrollView *)view;
        if (sv.contentSize.height > sv.bounds.size.height) {
            return sv;
        }
    }
    for (UIView *sub in view.subviews) {
        UIScrollView *found = [self findMainScrollView:sub];
        if (found) return found;
    }
    return nil;
}

+ (BOOL)findReactNativeKeywordInView:(UIView *)v {
    if (!v || v.hidden || v.alpha < 0.05) return NO;

    NSString *acc = v.accessibilityLabel.lowercaseString;
    if (acc.length > 0) {
        if ([acc containsString:@"vuốt để nhận"] || [acc containsString:@"chi tiết đơn hàng"] || [acc containsString:@"giao đến địa chỉ"] || [acc containsString:@"phí giao hàng"]) {
            return YES;
        }
    }

    @try {
        id textVal = [v valueForKey:@"text"];
        if ([textVal isKindOfClass:[NSString class]]) {
            NSString *t = [(NSString *)textVal lowercaseString];
            if ([t containsString:@"vuốt để nhận"] || [t containsString:@"chi tiết đơn"] || [t containsString:@"phí giao hàng"]) {
                return YES;
            }
        }
    } @catch (NSException *e) {}

    for (UIView *sub in v.subviews) {
        if ([self findReactNativeKeywordInView:sub]) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)isReactNativeOrderDetailOpen {
    UIWindow *win = [self getMainAppWindow];
    return [self findReactNativeKeywordInView:win];
}

// THỰC HIỆN CUỘN XUỐNG ĐÁY LẤY ẢNH -> TRẢ VỀ ĐẦU TRANG NGAY
+ (void)expandSheetAndExtract:(void(^)(NSString *shipFee, NSString *bonusFee, NSString *note, NSString *randomSecondPhone, UIImage *croppedOrderImage))completion {
    UIWindow *mainWin = [self getMainAppWindow];
    if (!mainWin) {
        if (completion) completion(@"--", @"0đ", @"(Lỗi)", nil, nil);
        return;
    }

    UIScrollView *sv = [self findMainScrollView:mainWin];
    __block CGPoint originalOffset = sv ? sv.contentOffset : CGPointZero;

    // 1. Nhảy nhanh xuống đáy để React Native nạp dữ liệu bên dưới
    if (sv && sv.contentSize.height > sv.bounds.size.height) {
        CGPoint bottomOffset = CGPointMake(0, sv.contentSize.height - sv.bounds.size.height + sv.adjustedContentInset.bottom);
        [sv setContentOffset:bottomOffset animated:NO];
    }

    // 2. Chờ 0.06s để khung render xong -> Chụp ảnh -> Đưa về lại vị trí cũ ngay
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIGraphicsBeginImageContextWithOptions(mainWin.bounds.size, NO, 0.0);
        [mainWin drawViewHierarchyInRect:mainWin.bounds afterScreenUpdates:YES];
        UIImage *fullSnapshot = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        // Trả vị trí cuộn về lại ban đầu
        if (sv) {
            [sv setContentOffset:originalOffset animated:NO];
        }

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

                if ([lower containsString:@"khích lệ"] || [lower containsString:@"khich le"]) {
                    NSTextCheckingResult *sameLineMatch = [moneyRegex firstMatchInString:l options:0 range:NSMakeRange(0, l.length)];
                    if (sameLineMatch) {
                        bonusFee = [[l substringWithRange:sameLineMatch.range] stringByAppendingString:@"đ"];
                    } else {
                        CGFloat midY_I = CGRectGetMidY(boxI);
                        CGFloat bestDist = 999.0;
                        NSString *detectedBonus = nil;

                        for (NSUInteger j = 0; j < strings.count; j++) {
                            if (i == j) continue;
                            CGRect boxJ = [convertedBoxes[j] CGRectValue];
                            CGFloat midY_J = CGRectGetMidY(boxJ);

                            if (boxJ.origin.x > boxI.origin.x && fabs(midY_J - midY_I) < 0.025) {
                                NSString *valStr = [strings[j] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                                CGFloat dist = fabs(midY_J - midY_I);
                                if (dist < bestDist) {
                                    bestDist = dist;
                                    detectedBonus = valStr;
                                }
                            }
                        }

                        if (detectedBonus) {
                            NSString *digitsOnly = [[detectedBonus componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
                            NSTextCheckingResult *moneyMatch = [moneyRegex firstMatchInString:detectedBonus options:0 range:NSMakeRange(0, detectedBonus.length)];

                            if (moneyMatch) {
                                bonusFee = [[detectedBonus substringWithRange:moneyMatch.range] stringByAppendingString:@"đ"];
                            } else if (digitsOnly.length > 0 && ![digitsOnly isEqualToString:@"0"]) {
                                bonusFee = [digitsOnly stringByAppendingString:@"đ"];
                            } else {
                                bonusFee = @"0đ";
                            }
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

#pragma mark - UI LỚP PHỦ VÀ ADVANCED HUD LOGGER

@interface DriverHelperVC : UIViewController
@property (nonatomic, strong) UIView *orangeHeaderBar;
@property (nonatomic, strong) UILabel *feeLabel;
@property (nonatomic, strong) UILabel *noteLabel;
@property (nonatomic, strong) UIButton *callSecondBtn;
@property (nonatomic, strong) UIButton *zaloBtn;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) UITextView *hudTextView;
@property (nonatomic, strong) UIImage *orderImageToSend;
@property (nonatomic, strong) NSString *currentPhoneForZalo;
@property (nonatomic, assign) BOOL isShowing;

- (void)checkAndHandleState;
- (void)showAndExtract;
- (void)hideHeader;
- (void)appendLog:(NSString *)text;
@end

static DriverHelperVC *gDriverVC = nil;

@implementation DriverHelperVC

- (void)viewDidLoad {
    [super viewDidLoad];
    gDriverVC = self;
    self.view.backgroundColor = [UIColor clearColor];
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;

    // 1. Thanh cam 96pt
    self.orangeHeaderBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, sw, 96)];
    self.orangeHeaderBar.backgroundColor = [UIColor colorWithRed:0.96 green:0.35 blue:0.15 alpha:1.0];
    self.orangeHeaderBar.layer.shadowColor = [UIColor blackColor].CGColor;
    self.orangeHeaderBar.layer.shadowOpacity = 0.25;
    self.orangeHeaderBar.layer.shadowOffset = CGSizeMake(0, 1.5);
    self.orangeHeaderBar.layer.shadowRadius = 2.5;
    self.orangeHeaderBar.hidden = YES;
    [self.view addSubview:self.orangeHeaderBar];

    // Nút Zalo
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

    // Nút Đóng (✕)
    self.closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeBtn.frame = CGRectMake(sw - 96, 43, 26, 24);
    [self.closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [self.closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14.0];
    [self.closeBtn addTarget:self action:@selector(hideHeader) forControlEvents:UIControlEventTouchUpInside];
    [self.orangeHeaderBar addSubview:self.closeBtn];

    // Dòng Phí Ship
    self.feeLabel = [[UILabel alloc] initWithFrame:CGRectMake(65, 44, sw - 165, 22)];
    self.feeLabel.textColor = [UIColor whiteColor];
    self.feeLabel.font = [UIFont boldSystemFontOfSize:12.5];
    self.feeLabel.text = @"🛵 Ship: Đang tải... | 🎁 0đ";
    [self.orangeHeaderBar addSubview:self.feeLabel];

    // Dòng Ghi chú
    self.noteLabel = [[UILabel alloc] initWithFrame:CGRectMake(65, 67, sw - 145, 26)];
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

    // 2. HUD CONSOLE
    self.hudTextView = [[UITextView alloc] initWithFrame:CGRectMake(10, sh - 115, sw - 20, 48)];
    self.hudTextView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.85];
    self.hudTextView.textColor = [UIColor cyanColor];
    self.hudTextView.font = [UIFont fontWithName:@"Courier" size:10.0] ?: [UIFont systemFontOfSize:10.0];
    self.hudTextView.editable = NO;
    self.hudTextView.layer.cornerRadius = 6;
    self.hudTextView.layer.borderWidth = 1;
    self.hudTextView.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.3].CGColor;
    self.hudTextView.text = @"[SNIFFER READY] Bấm nút < để bắt sự kiện...";
    [self.view addSubview:self.hudTextView];
}

- (void)appendLog:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *newText = [NSString stringWithFormat:@"%@\n> %@", self.hudTextView.text, text];
        NSArray *lines = [newText componentsSeparatedByString:@"\n"];
        if (lines.count > 4) {
            lines = [lines subarrayWithRange:NSMakeRange(lines.count - 4, 4)];
            newText = [lines componentsJoinedByString:@"\n"];
        }
        self.hudTextView.text = newText;
        [UIPasteboard generalPasteboard].string = text;
    });
}

- (void)checkAndHandleState {
    BOOL isDetail = [DriverDataExtractor isReactNativeOrderDetailOpen];
    if (isDetail) {
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
            self.noteLabel.frame = CGRectMake(65, 67, [UIScreen mainScreen].bounds.size.width - 145, 26);
        } else {
            self.callSecondBtn.hidden = YES;
            self.noteLabel.frame = CGRectMake(65, 67, [UIScreen mainScreen].bounds.size.width - 70, 26);
        }
    }];
}

- (void)hideHeader {
    self.isShowing = NO;
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

#pragma mark - DEEP EVENT HOOKING & SNIFFER

static BOOL (*orig_sendAction)(id, SEL, SEL, id, id, UIEvent *);
static BOOL custom_sendAction(UIControl *self, SEL _cmd, SEL action, id target, id sender, UIEvent *event) {
    NSString *actName = NSStringFromSelector(action);
    NSString *tgtName = NSStringFromClass([target class]);
    [gDriverVC appendLog:[NSString stringWithFormat:@"Action: [%@] on %@", actName, tgtName]];
    
    if ([actName.lowercaseString containsString:@"back"] || [actName.lowercaseString containsString:@"pop"] || [actName.lowercaseString containsString:@"close"] || [actName.lowercaseString containsString:@"dismiss"]) {
        [gDriverVC hideHeader];
    }
    return orig_sendAction(self, _cmd, action, target, sender, event);
}

static void (*orig_willRemoveSubview)(id, SEL, UIView *);
static void custom_willRemoveSubview(UIView *self, SEL _cmd, UIView *subview) {
    orig_willRemoveSubview(self, _cmd, subview);
    if (![NSStringFromClass([subview class]) containsString:@"Driver"]) {
        NSString *sName = NSStringFromClass([subview class]);
        if (subview.bounds.size.height > 400 || [sName containsString:@"Modal"] || [sName containsString:@"Sheet"]) {
            [gDriverVC appendLog:[NSString stringWithFormat:@"Remove Subview: %@", sName]];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [gDriverVC checkAndHandleState];
            });
        }
    }
}

static void (*orig_sendEvent)(id, SEL, UIEvent *);
static void custom_sendEvent(UIApplication *self, SEL _cmd, UIEvent *event) {
    orig_sendEvent(self, _cmd, event);
    if (event.type == UIEventTypeTouches) {
        for (UITouch *t in event.allTouches) {
            if (t.phase == UITouchPhaseEnded) {
                CGPoint loc = [t locationInView:nil];
                UIView *hitV = t.view;
                NSString *vClass = NSStringFromClass([hitV class]);
                NSString *accLabel = hitV.accessibilityLabel ?: @"";

                [gDriverVC appendLog:[NSString stringWithFormat:@"TOUCH (%.0f, %.0f) | View: %@ | Acc: '%@'", loc.x, loc.y, vClass, accLabel]];

                if (loc.x <= 90.0 && loc.y <= 110.0) {
                    [gDriverVC hideHeader];
                }

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [gDriverVC checkAndHandleState];
                });
                break;
            }
        }
    }
}

#pragma mark - ENTRY POINT & HIT-TEST ĐỤC LỖ NÚT BACK (X: 0 -> 90, Y: 0 -> 110)

@interface DriverOverlayWindow : UIWindow
@end

@implementation DriverOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self.rootViewController.view) return nil;

    if (point.x <= 90.0 && point.y <= 110.0) {
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
    Class ctrlClass = [UIControl class];
    Method mAction = class_getInstanceMethod(ctrlClass, @selector(sendAction:to:forEvent:));
    orig_sendAction = (BOOL(*)(id, SEL, SEL, id, id, UIEvent *))method_getImplementation(mAction);
    method_setImplementation(mAction, (IMP)custom_sendAction);

    Class viewClass = [UIView class];
    Method mRemove = class_getInstanceMethod(viewClass, @selector(willRemoveSubview:));
    orig_willRemoveSubview = (void(*)(id, SEL, UIView *))method_getImplementation(mRemove);
    method_setImplementation(mRemove, (IMP)custom_willRemoveSubview);

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
