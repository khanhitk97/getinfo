#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Vision/Vision.h>

#pragma mark - DATA EXTRACTION & SANITIZATION ENGINE

@interface DriverDataExtractor : NSObject
+ (NSArray<NSString *> *)cleanAndExtractPhones:(NSString *)rawText;
+ (void)scanScreenAndExtract:(void(^)(NSArray<NSString *> *phones, NSString *customerNote, NSString *address, UIImage *snapshot))completion;
@end

@implementation DriverDataExtractor

// Chuẩn hóa và cắt số điện thoại bị chèn thêm số phía sau
+ (NSArray<NSString *> *)cleanAndExtractPhones:(NSString *)rawText {
    if (!rawText || rawText.length < 8) return @[];
    
    NSMutableArray<NSString *> *validPhones = [NSMutableArray array];
    
    // Regex tìm chuỗi có khả năng là số điện thoại
    NSString *pattern = @"(?:\\+?84|0)(?:3[2-9]|5[6|8|9]|7[0|6-9]|8[1-9]|9[0-9]|2[0-9]{2})[0-9\\s.-]{6,15}";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern 
                                                                           options:NSRegularExpressionCaseInsensitive 
                                                                             error:nil];
    
    NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:rawText options:0 range:NSMakeRange(0, rawText.length)];
    
    for (NSTextCheckingResult *m in matches) {
        NSString *matchedStr = [rawText substringWithRange:m.range];
        
        // Loại bỏ toàn bộ ký tự không phải số
        NSString *digitsOnly = [[matchedStr componentsSeparatedByCharactersInSet:
                                 [[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
        
        // Chuyển 84 thành đầu 0
        if ([digitsOnly hasPrefix:@"84"] && digitsOnly.length >= 11) {
            digitsOnly = [@"0" stringByAppendingString:[digitsOnly substringFromIndex:2]];
        }
        
        NSString *cleanPhone = nil;
        
        // 1. Số di động Việt Nam (03, 05, 07, 08, 09): Cắt đúng 10 số, bỏ đuôi rác phía sau
        if ([digitsOnly hasPrefix:@"03"] || [digitsOnly hasPrefix:@"05"] || 
            [digitsOnly hasPrefix:@"07"] || [digitsOnly hasPrefix:@"08"] || 
            [digitsOnly hasPrefix:@"09"]) {
            if (digitsOnly.length >= 10) {
                cleanPhone = [digitsOnly substringToIndex:10];
            }
        } 
        // 2. Số cố định bàn (02x): Cắt đúng 11 số
        else if ([digitsOnly hasPrefix:@"02"]) {
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

+ (void)scanScreenAndExtract:(void(^)(NSArray<NSString *> *phones, NSString *customerNote, NSString *address, UIImage *snapshot))completion {
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

        UIGraphicsBeginImageContextWithOptions(mainWin.bounds.size, NO, 0.0);
        [mainWin drawViewHierarchyInRect:mainWin.bounds afterScreenUpdates:NO];
        UIImage *snapshot = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        if (!snapshot || !snapshot.CGImage) {
            if (completion) completion(@[], @"Không chụp được màn hình", @"", nil);
            return;
        }

        VNRecognizeTextRequest *req = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest * _Nonnull request, NSError * _Nullable error) {
            NSMutableArray<NSString *> *lines = [NSMutableArray array];
            NSMutableSet<NSString *> *foundPhones = [NSMutableSet set];
            NSString *detectedNote = @"(Không có ghi chú đặc biệt)";
            NSString *detectedAddress = @"";

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
                if ([lower containsString:@"ghi chú"] || [lower containsString:@"lưu ý"] || [lower containsString:@"lời nhắn"] || [lower containsString:@"dặn"]) {
                    if (i + 1 < lines.count) {
                        detectedNote = [NSString stringWithFormat:@"%@: %@", l, lines[i+1]];
                    } else {
                        detectedNote = l;
                    }
                    break;
                }
            }

            for (NSString *l in lines) {
                NSString *lower = [l lowercaseString];
                if ([lower containsString:@"đường"] || [lower containsString:@"phường"] || [lower containsString:@"quận"] || [lower containsString:@"hẻm"] || [lower containsString:@"nhà"]) {
                    detectedAddress = l;
                    break;
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion([foundPhones allObjects], detectedNote, detectedAddress, snapshot);
            });
        }];

        req.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        req.usesLanguageCorrection = NO;

        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:snapshot.CGImage options:@{}];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [handler performRequests:@[req] error:nil];
        });
    }
}

@end

#pragma mark - UI BẢNG ĐIỀU KHIỂN DÀNH CHO TÀI XẾ

@interface DriverControlVC : UIViewController
@property (nonatomic, strong) UIButton *bubbleBtn;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UILabel *noteLabel;
@property (nonatomic, strong) UIStackView *phoneStackView;
@property (nonatomic, strong) UIImage *lastSnapshot;
@property (nonatomic, strong) NSString *lastAddress;
@end

@implementation DriverControlVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    // Nút tròn nổi
    self.bubbleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.bubbleBtn.frame = CGRectMake(15, 120, 60, 60);
    self.bubbleBtn.backgroundColor = [UIColor colorWithRed:0.95 green:0.40 blue:0.13 alpha:0.95];
    [self.bubbleBtn setTitle:@"🛵 Đơn" forState:UIControlStateNormal];
    [self.bubbleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.bubbleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.bubbleBtn.layer.cornerRadius = 30;
    self.bubbleBtn.layer.borderWidth = 2;
    self.bubbleBtn.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.bubbleBtn addTarget:self action:@selector(openPanel) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *panB = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanBubble:)];
    [self.bubbleBtn addGestureRecognizer:panB];
    [self.view addSubview:self.bubbleBtn];

    // Khung Panel chính
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(12, 70, screenW - 24, 430)];
    self.panel.backgroundColor = [[UIColor colorWithWhite:0.06 alpha:0.97] colorWithAlphaComponent:0.97];
    self.panel.layer.cornerRadius = 16;
    self.panel.layer.borderWidth = 1.2;
    self.panel.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:1.0].CGColor;
    self.panel.clipsToBounds = YES;
    self.panel.hidden = YES;
    [self.view addSubview:self.panel];

    UIPanGestureRecognizer *panP = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanPanel:)];
    [self.panel addGestureRecognizer:panP];

    // 1. BANNER GHI CHÚ
    UILabel *noteTitle = [[UILabel alloc] initWithFrame:CGRectMake(12, 10, self.panel.frame.size.width - 60, 18)];
    noteTitle.text = @"📌 GHI CHÚ CỦA KHÁCH:";
    noteTitle.textColor = [UIColor systemOrangeColor];
    noteTitle.font = [UIFont boldSystemFontOfSize:11.5];
    [self.panel addSubview:noteTitle];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(self.panel.frame.size.width - 38, 8, 28, 28);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeBtn.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    closeBtn.layer.cornerRadius = 14;
    [closeBtn addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:closeBtn];

    self.noteLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 32, self.panel.frame.size.width - 24, 50)];
    self.noteLabel.backgroundColor = [UIColor colorWithRed:0.2 green:0.15 blue:0.05 alpha:0.9];
    self.noteLabel.textColor = [UIColor yellowColor];
    self.noteLabel.font = [UIFont boldSystemFontOfSize:12.5];
    self.noteLabel.numberOfLines = 2;
    self.noteLabel.layer.cornerRadius = 8;
    self.noteLabel.layer.borderWidth = 1.0;
    self.noteLabel.layer.borderColor = [UIColor systemOrangeColor].CGColor;
    self.noteLabel.clipsToBounds = YES;
    self.noteLabel.text = @" Đang nhận diện đơn hàng...";
    [self.panel addSubview:self.noteLabel];

    // 2. KHU VỰC DANH SÁCH SĐT
    UILabel *phoneTitle = [[UILabel alloc] initWithFrame:CGRectMake(12, 90, self.panel.frame.size.width - 24, 18)];
    phoneTitle.text = @"📞 SỐ ĐIỆN THOẠI (Chạm SĐT để sửa nếu cần):";
    phoneTitle.textColor = [UIColor systemGreenColor];
    phoneTitle.font = [UIFont boldSystemFontOfSize:11.0];
    [self.panel addSubview:phoneTitle];

    self.phoneStackView = [[UIStackView alloc] initWithFrame:CGRectMake(12, 112, self.panel.frame.size.width - 24, 165)];
    self.phoneStackView.axis = UILayoutConstraintAxisVertical;
    self.phoneStackView.distribution = UIStackViewDistributionFillEqually;
    self.phoneStackView.spacing = 8;
    [self.panel addSubview:self.phoneStackView];

    // 3. CÁC NÚT THAO TÁC NHANH
    CGFloat btnY = 290;
    CGFloat btnW = (self.panel.frame.size.width - 32) / 2;

    UIButton *shareImgBtn = [self createActionButton:@"📤 Chia Sẻ Cho Quán" color:[UIColor systemBlueColor] frame:CGRectMake(12, btnY, btnW, 40) action:@selector(shareOrderImage)];
    UIButton *saveImgBtn = [self createActionButton:@"💾 Lưu Vào Album" color:[UIColor colorWithRed:0.15 green:0.65 blue:0.35 alpha:1.0] frame:CGRectMake(20 + btnW, btnY, btnW, 40) action:@selector(saveToPhotos)];
    UIButton *mapBtn = [self createActionButton:@"🗺️ Mở Google Maps" color:[UIColor systemIndigoColor] frame:CGRectMake(12, btnY + 48, self.panel.frame.size.width - 24, 38) action:@selector(openGoogleMaps)];

    [self.panel addSubview:shareImgBtn];
    [self.panel addSubview:saveImgBtn];
    [self.panel addSubview:mapBtn];
}

- (UIButton *)createActionButton:(NSString *)title color:(UIColor *)color frame:(CGRect)frame action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = frame;
    [btn setTitle:title forState:UIControlStateNormal];
    btn.backgroundColor = color;
    btn.tintColor = [UIColor whiteColor];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:12.5];
    btn.layer.cornerRadius = 8;
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
    [self refreshOrderData];
}

- (void)closePanel {
    self.panel.hidden = YES;
    self.bubbleBtn.hidden = NO;
}

- (void)refreshOrderData {
    self.panel.alpha = 0.0;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [DriverDataExtractor scanScreenAndExtract:^(NSArray<NSString *> *phones, NSString *customerNote, NSString *address, UIImage *snapshot) {
            self.panel.alpha = 1.0;
            self.lastSnapshot = snapshot;
            self.lastAddress = address;

            self.noteLabel.text = [NSString stringWithFormat:@"  %@", customerNote];

            for (UIView *v in self.phoneStackView.arrangedSubviews) {
                [self.phoneStackView removeArrangedSubview:v];
                [v removeFromSuperview];
            }

            if (phones.count > 0) {
                for (NSString *phone in phones) {
                    [self addPhoneRowWithNumber:phone];
                }
            } else {
                UILabel *emptyLbl = [[UILabel alloc] init];
                emptyLbl.text = @"Không phát hiện SĐT nào trên màn hình.";
                emptyLbl.textColor = [UIColor lightGrayColor];
                emptyLbl.font = [UIFont italicSystemFontOfSize:11];
                [self.phoneStackView addArrangedSubview:emptyLbl];
            }
        }];
    });
}

- (void)addPhoneRowWithNumber:(NSString *)phoneNumber {
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.phoneStackView.frame.size.width, 36)];
    row.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    row.layer.cornerRadius = 6;

    // Nút SĐT cho phép bấm vào để chỉnh sửa nhanh
    UIButton *numBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    numBtn.frame = CGRectMake(8, 4, row.frame.size.width - 95, 28);
    [numBtn setTitle:[NSString stringWithFormat:@"📱 %@", phoneNumber] forState:UIControlStateNormal];
    [numBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    numBtn.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:13];
    numBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    numBtn.accessibilityValue = phoneNumber;
    [numBtn addTarget:self action:@selector(editPhoneNumberPrompt:) forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:numBtn];

    // Nút Gọi thoại bên phải
    UIButton *callBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    callBtn.frame = CGRectMake(row.frame.size.width - 82, 4, 75, 28);
    [callBtn setTitle:@"📞 Gọi" forState:UIControlStateNormal];
    callBtn.backgroundColor = [UIColor systemGreenColor];
    callBtn.tintColor = [UIColor whiteColor];
    callBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    callBtn.layer.cornerRadius = 6;
    callBtn.accessibilityValue = phoneNumber;
    [callBtn addTarget:self action:@selector(makeDirectPhoneCall:) forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:callBtn];

    [self.phoneStackView addArrangedSubview:row];
}

// Cho phép tài xế sửa SĐT trực tiếp nếu nhận diện thiếu/thừa số
- (void)editPhoneNumberPrompt:(UIButton *)btn {
    NSString *currentPhone = btn.accessibilityValue;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Chỉnh sửa SĐT"
                                                                   message:@"Kiểm tra hoặc sửa lại số trước khi gọi:"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.text = currentPhone;
        textField.keyboardType = UIKeyboardTypePhonePad;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Gọi số này" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
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
    if (!self.lastSnapshot) return;
    UIActivityViewController *act = [[UIActivityViewController alloc] initWithActivityItems:@[self.lastSnapshot] applicationActivities:nil];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        act.popoverPresentationController.sourceView = self.panel;
    }
    [self presentViewController:act animated:YES completion:nil];
}

- (void)saveToPhotos {
    if (!self.lastSnapshot) return;
    UIImageWriteToSavedPhotosAlbum(self.lastSnapshot, self, @selector(image:didFinishSavingWithError:contextInfo:), nil);
}

- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:error ? @"Lỗi" : @"Thành công"
                                                                   message:error ? @"Không thể lưu ảnh." : @"Đã lưu ảnh đơn hàng vào Album!"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openGoogleMaps {
    NSString *query = self.lastAddress.length > 0 ? self.lastAddress : @"";
    NSString *encoded = [query stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSURL *gmapURL = [NSURL URLWithString:[NSString stringWithFormat:@"comgooglemaps://?q=%@", encoded]];
    NSURL *appleURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://maps.apple.com/?q=%@", encoded]];

    if ([[UIApplication sharedApplication] canOpenURL:gmapURL]) {
        [[UIApplication sharedApplication] openURL:gmapURL options:@{} completionHandler:nil];
    } else {
        [[UIApplication sharedApplication] openURL:appleURL options:@{} completionHandler:nil];
    }
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
