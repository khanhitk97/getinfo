#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Vision/Vision.h>

#pragma mark - DATA & AUTO-SCROLL ENGINE

@interface DriverDataExtractor : NSObject
+ (NSArray<NSString *> *)cleanAndExtractPhones:(NSString *)rawText;
+ (void)expandSheetAndCapture:(void(^)(NSArray<NSString *> *phones, NSString *customerNote, UIImage *croppedOrderImage))completion;
@end

@implementation DriverDataExtractor

+ (NSArray<NSString *> *)cleanAndExtractPhones:(NSString *)rawText {
    if (!rawText || rawText.length < 8) return @[];
    
    NSMutableArray<NSString *> *validPhones = [NSMutableArray array];
    NSString *pattern = @"(?:\\+?84|0)(?:3[2-9]|5[6|8|9]|7[0|6-9]|8[1-9]|9[0-9]|2[0-9]{2})[0-9\\s.-]{6,15}";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern 
                                                                           options:NSRegularExpressionCaseInsensitive 
                                                                             error:nil];
    
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:rawText options:0 range:NSMakeRange(0, rawText.length)];
    
    for (NSTextCheckingResult *m in matches) {
        NSString *matchedStr = [rawText substringWithRange:m.range];
        NSString *digitsOnly = [[matchedStr componentsSeparatedByCharactersInSet:
                                 [[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
        
        if ([digitsOnly hasPrefix:@"84"] && digitsOnly.length >= 11) {
            digitsOnly = [@"0" stringByAppendingString:[digitsOnly substringFromIndex:2]];
        }
        
        NSString *cleanPhone = nil;
        if ([digitsOnly hasPrefix:@"03"] || [digitsOnly hasPrefix:@"05"] || 
            [digitsOnly hasPrefix:@"07"] || [digitsOnly hasPrefix:@"08"] || 
            [digitsOnly hasPrefix:@"09"]) {
            if (digitsOnly.length >= 10) {
                cleanPhone = [digitsOnly substringToIndex:10];
            }
        } else if ([digitsOnly hasPrefix:@"02"]) {
            if (digitsOnly.length >= 11) {
                cleanPhone = [digitsOnly substringToIndex:11];
            }
        }
        
        if (cleanPhone && ![validPhones containsObject:cleanPhone]) {
            [validPhones addObject:cleanPhone];
        }
    }
    return validPhones;
}

+ (void)forceExpandBottomSheetInView:(UIView *)view {
    if (!view) return;
    if ([view isKindOfClass:[UIScrollView class]]) {
        UIScrollView *sv = (UIScrollView *)view;
        if (sv.contentSize.height > sv.bounds.size.height) {
            CGPoint bottomOffset = CGPointMake(0, sv.contentSize.height - sv.bounds.size.height + sv.adjustedContentInset.bottom);
            [sv setContentOffset:bottomOffset animated:NO];
        }
    }
    for (UIView *sub in view.subviews) {
        [self forceExpandBottomSheetInView:sub];
    }
}

+ (UIImage *)cropOrderDetailOnly:(UIImage *)fullImage screenBounds:(CGRect)bounds {
    if (!fullImage) return nil;
    
    CGFloat cropY = bounds.size.height * 0.35;
    CGFloat cropHeight = bounds.size.height * 0.55;
    CGRect cropRect = CGRectMake(0, cropY, bounds.size.width, cropHeight);
    
    CGFloat scale = fullImage.scale;
    CGRect scaledRect = CGRectMake(cropRect.origin.x * scale, 
                                   cropRect.origin.y * scale, 
                                   cropRect.size.width * scale, 
                                   cropRect.size.height * scale);
    
    CGImageRef imageRef = CGImageCreateWithImageInRect(fullImage.CGImage, scaledRect);
    UIImage *cropped = [UIImage imageWithCGImage:imageRef scale:scale orientation:fullImage.imageOrientation];
    CGImageRelease(imageRef);
    return cropped;
}

+ (void)expandSheetAndCapture:(void(^)(NSArray<NSString *> *phones, NSString *customerNote, UIImage *croppedOrderImage))completion {
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

        [self forceExpandBottomSheetInView:mainWin];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIGraphicsBeginImageContextWithOptions(mainWin.bounds.size, NO, 0.0);
            [mainWin drawViewHierarchyInRect:mainWin.bounds afterScreenUpdates:YES];
            UIImage *fullSnapshot = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();

            if (!fullSnapshot || !fullSnapshot.CGImage) {
                if (completion) completion(@[], @"Không chụp được màn hình", nil);
                return;
            }

            UIImage *orderDetailCrop = [self cropOrderDetailOnly:fullSnapshot screenBounds:mainWin.bounds];

            VNRecognizeTextRequest *req = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest * _Nonnull request, NSError * _Nullable error) {
                NSMutableArray<NSString *> *lines = [NSMutableArray array];
                NSMutableSet<NSString *> *foundPhones = [NSMutableSet set];
                NSString *detectedNote = @"Không có ghi chú";

                for (VNRecognizedTextObservation *obs in request.results) {
                    VNRecognizedText *top = [[obs topCandidates:1] firstObject];
                    if (top) {
                        NSString *line = top.string;
                        [lines addObject:line];

                        NSArray *pList = [self cleanAndExtractPhones:line];
                        for (NSString *p in pList) [foundPhones addObject:p];
                    }
                }

                for (NSUInteger i = 0; i < lines.count; i++) {
                    NSString *l = lines[i];
                    NSString *lower = [l lowercaseString];
                    if ([lower containsString:@"ghi chú"] || [lower containsString:@"dặn dò"] || [lower containsString:@"lưu ý"]) {
                        if (i + 1 < lines.count) {
                            detectedNote = lines[i+1];
                        }
                        break;
                    }
                }

                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion([foundPhones allObjects], detectedNote, orderDetailCrop ?: fullSnapshot);
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

#pragma mark - UI BẢNG ĐIỀU KHIỂN GỌN GÀNG (NEO SÁT PHẢI)

@interface DriverControlVC : UIViewController
@property (nonatomic, strong) UIButton *bubbleBtn;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UILabel *noteLabel;
@property (nonatomic, strong) UIStackView *phoneStackView;
@property (nonatomic, strong) UIButton *shareBtn;
@property (nonatomic, strong) UIImage *orderImageToSend;
@end

@implementation DriverControlVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;

    // 1. Bong bóng nổi: Thu nhỏ kích thước và neo cố định ở góc phải
    CGFloat bubbleSize = 50.0;
    self.bubbleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.bubbleBtn.frame = CGRectMake(screenW - bubbleSize - 12, 120, bubbleSize, bubbleSize);
    self.bubbleBtn.backgroundColor = [UIColor colorWithRed:0.95 green:0.38 blue:0.12 alpha:0.96];
    [self.bubbleBtn setTitle:@"🛵 Đơn" forState:UIControlStateNormal];
    [self.bubbleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.bubbleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
    self.bubbleBtn.layer.cornerRadius = bubbleSize / 2.0;
    self.bubbleBtn.layer.borderWidth = 2;
    self.bubbleBtn.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.bubbleBtn addTarget:self action:@selector(openPanel) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *panB = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanBubble:)];
    [self.bubbleBtn addGestureRecognizer:panB];
    [self.view addSubview:self.bubbleBtn];

    // 2. Bảng Panel: Chiều rộng 270pt (chỉ chiếm ~70% màn hình), căn sát lề phải
    CGFloat panelW = 270.0;
    CGFloat panelX = screenW - panelW - 10.0; // Dạt hoàn toàn sang bên phải
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(panelX, 90, panelW, 185)];
    self.panel.backgroundColor = [[UIColor colorWithWhite:0.08 alpha:0.98] colorWithAlphaComponent:0.98];
    self.panel.layer.cornerRadius = 14;
    self.panel.layer.borderWidth = 1.2;
    self.panel.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:1.0].CGColor;
    self.panel.clipsToBounds = YES;
    self.panel.hidden = YES;
    [self.view addSubview:self.panel];

    UIPanGestureRecognizer *panP = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanPanel:)];
    [self.panel addGestureRecognizer:panP];

    // Tiêu đề & Nút đóng
    UILabel *noteTitle = [[UILabel alloc] initWithFrame:CGRectMake(10, 8, self.panel.frame.size.width - 45, 16)];
    noteTitle.text = @"📌 GHI CHÚ KHÁCH:";
    noteTitle.textColor = [UIColor systemOrangeColor];
    noteTitle.font = [UIFont boldSystemFontOfSize:11.0];
    [self.panel addSubview:noteTitle];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(self.panel.frame.size.width - 30, 5, 24, 24);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    closeBtn.layer.cornerRadius = 12;
    [closeBtn addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:closeBtn];

    // Banner Ghi chú gọn
    self.noteLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 26, self.panel.frame.size.width - 16, 40)];
    self.noteLabel.backgroundColor = [UIColor colorWithRed:0.2 green:0.14 blue:0.04 alpha:0.9];
    self.noteLabel.textColor = [UIColor yellowColor];
    self.noteLabel.font = [UIFont boldSystemFontOfSize:11.5];
    self.noteLabel.numberOfLines = 2;
    self.noteLabel.layer.cornerRadius = 6;
    self.noteLabel.layer.borderWidth = 1.0;
    self.noteLabel.layer.borderColor = [UIColor systemOrangeColor].CGColor;
    self.noteLabel.clipsToBounds = YES;
    self.noteLabel.text = @" Đang kéo đơn...";
    [self.panel addSubview:self.noteLabel];

    // Stack SĐT co giãn
    self.phoneStackView = [[UIStackView alloc] initWithFrame:CGRectMake(8, 72, self.panel.frame.size.width - 16, 20)];
    self.phoneStackView.axis = UILayoutConstraintAxisVertical;
    self.phoneStackView.distribution = UIStackViewDistributionFillEqually;
    self.phoneStackView.spacing = 5;
    [self.panel addSubview:self.phoneStackView];

    // Nút Chia sẻ ảnh
    self.shareBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.shareBtn.frame = CGRectMake(8, 98, self.panel.frame.size.width - 16, 38);
    [self.shareBtn setTitle:@"📤 GỬI ẢNH MÓN CHO QUÁN" forState:UIControlStateNormal];
    self.shareBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
    self.shareBtn.tintColor = [UIColor whiteColor];
    self.shareBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
    self.shareBtn.layer.cornerRadius = 7;
    [self.shareBtn addTarget:self action:@selector(shareOrderImage) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.shareBtn];
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
    [self refreshOrderData];
}

- (void)closePanel {
    self.panel.hidden = YES;
    self.bubbleBtn.hidden = NO;
}

- (void)refreshOrderData {
    self.panel.alpha = 0.0;
    
    [DriverDataExtractor expandSheetAndCapture:^(NSArray<NSString *> *phones, NSString *customerNote, UIImage *croppedOrderImage) {
        self.panel.alpha = 1.0;
        self.orderImageToSend = croppedOrderImage;
        self.noteLabel.text = [NSString stringWithFormat:@"  %@", customerNote];

        for (UIView *v in self.phoneStackView.arrangedSubviews) {
            [self.phoneStackView removeArrangedSubview:v];
            [v removeFromSuperview];
        }

        // TÍNH TOÁN CHIỀU CAO CO GIÃN ĐỘNG
        CGFloat stackHeight = 0;
        if (phones.count > 0) {
            for (NSString *phone in phones) {
                [self addPhoneRowWithNumber:phone];
            }
            stackHeight = phones.count * 32.0 + (phones.count - 1) * 5.0;
        } else {
            UILabel *emptyLbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.phoneStackView.frame.size.width, 18)];
            emptyLbl.text = @"(Không tìm thấy SĐT trong đơn)";
            emptyLbl.textColor = [UIColor lightGrayColor];
            emptyLbl.font = [UIFont italicSystemFontOfSize:10.5];
            [self.phoneStackView addArrangedSubview:emptyLbl];
            stackHeight = 18.0;
        }

        CGFloat startPhoneY = 72.0;
        self.phoneStackView.frame = CGRectMake(8, startPhoneY, self.panel.frame.size.width - 16, stackHeight);
        
        CGFloat newShareY = startPhoneY + stackHeight + 8.0;
        self.shareBtn.frame = CGRectMake(8, newShareY, self.panel.frame.size.width - 16, 38);
        
        CGFloat totalHeight = newShareY + 38.0 + 8.0;
        CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
        
        [UIView animateWithDuration:0.2 animations:^{
            CGRect frame = self.panel.frame;
            frame.origin.x = screenW - frame.size.width - 10.0; // Luôn giữ sát lề phải
            frame.size.height = totalHeight;
            self.panel.frame = frame;
        }];
    }];
}

- (void)addPhoneRowWithNumber:(NSString *)phoneNumber {
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.phoneStackView.frame.size.width, 32)];
    row.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    row.layer.cornerRadius = 5;

    // Số điện thoại (Chạm để sửa)
    UIButton *numBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    numBtn.frame = CGRectMake(6, 2, row.frame.size.width - 76, 28);
    [numBtn setTitle:[NSString stringWithFormat:@"📱 %@", phoneNumber] forState:UIControlStateNormal];
    [numBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    numBtn.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:11.5];
    numBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    numBtn.accessibilityValue = phoneNumber;
    [numBtn addTarget:self action:@selector(editPhoneNumberPrompt:) forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:numBtn];

    // Nút Gọi thoại nhỏ gọn bên phải
    UIButton *callBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    callBtn.frame = CGRectMake(row.frame.size.width - 66, 3, 62, 26);
    [callBtn setTitle:@"📞 Gọi" forState:UIControlStateNormal];
    callBtn.backgroundColor = [UIColor systemGreenColor];
    callBtn.tintColor = [UIColor whiteColor];
    callBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11.0];
    callBtn.layer.cornerRadius = 5;
    callBtn.accessibilityValue = phoneNumber;
    [callBtn addTarget:self action:@selector(makeDirectPhoneCall:) forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:callBtn];

    [self.phoneStackView addArrangedSubview:row];
}

- (void)editPhoneNumberPrompt:(UIButton *)btn {
    NSString *currentPhone = btn.accessibilityValue;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Sửa Số Điện Thoại"
                                                                   message:@"Chỉnh sửa lại số trước khi gọi:"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.text = currentPhone;
        textField.keyboardType = UIKeyboardTypePhonePad;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Gọi ngay" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *editedPhone = alert.textFields.firstObject.text;
        if (editedPhone.length > 0) {
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"tel://%@", editedPhone]];
            if ([[UIApplication sharedApplication] canOpenURL:url]) {
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            }
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)makeDirectPhoneCall:(UIButton *)btn {
    NSString *phone = btn.accessibilityValue;
    if (phone.length > 0) {
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"tel://%@", phone]];
        if ([[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    }
}

- (void)shareOrderImage {
    if (!self.orderImageToSend) return;
    UIActivityViewController *act = [[UIActivityViewController alloc] initWithActivityItems:@[self.orderImageToSend] applicationActivities:nil];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        act.popoverPresentationController.sourceView = self.panel;
    }
    [self presentViewController:act animated:YES completion:nil];
}

@end

#pragma mark - ENTRY POINT

@interface DriverOverlayWindow : UIWindow
@end
@implementation DriverOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *h = [super hitTest:point withEvent:event];
    if (h == self.rootViewController.view) return nil;
    return h;
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
                DriverControlVC *vc = [[DriverControlVC alloc] init];
                gDriverWin.rootViewController = vc;
                gDriverWin.hidden = NO;
            });
        });
    }];
}
