#import <UIKit/UIKit.h>
#import <Vision/Vision.h>

@interface DriverHelperVC : UIViewController
@property (nonatomic, strong) UIButton *bubbleBtn;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UILabel *noteLbl;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UIButton *shareBtn;
@property (nonatomic, strong) UIImage *orderImg;
@end

@implementation DriverHelperVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;

    // Bong bóng nổi dạt phải
    self.bubbleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.bubbleBtn.frame = CGRectMake(sw - 60, 130, 50, 50);
    self.bubbleBtn.backgroundColor = [UIColor colorWithRed:0.95 green:0.38 blue:0.12 alpha:0.96];
    [self.bubbleBtn setTitle:@"🛵 Đơn" forState:UIControlStateNormal];
    [self.bubbleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.bubbleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
    self.bubbleBtn.layer.cornerRadius = 25;
    self.bubbleBtn.layer.borderWidth = 2;
    self.bubbleBtn.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.bubbleBtn addTarget:self action:@selector(openPanel) forControlEvents:UIControlEventTouchUpInside];
    [self.bubbleBtn addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanBubble:)]];
    [self.view addSubview:self.bubbleBtn];

    // Panel dạt sát phải (rộng 260pt)
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(sw - 270, 85, 260, 175)];
    self.panel.backgroundColor = [[UIColor colorWithWhite:0.08 alpha:0.98] colorWithAlphaComponent:0.98];
    self.panel.layer.cornerRadius = 12;
    self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:1.0].CGColor;
    self.panel.clipsToBounds = YES;
    self.panel.hidden = YES;
    [self.panel addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanPanel:)]];
    [self.view addSubview:self.panel];

    // Nút đóng
    UIButton *xBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    xBtn.frame = CGRectMake(232, 4, 24, 24);
    [xBtn setTitle:@"✕" forState:UIControlStateNormal];
    [xBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [xBtn addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:xBtn];

    // Banner Ghi chú
    self.noteLbl = [[UILabel alloc] initWithFrame:CGRectMake(8, 22, 244, 38)];
    self.noteLbl.backgroundColor = [UIColor colorWithRed:0.2 green:0.14 blue:0.04 alpha:0.9];
    self.noteLbl.textColor = [UIColor yellowColor];
    self.noteLbl.font = [UIFont boldSystemFontOfSize:11.5];
    self.noteLbl.numberOfLines = 2;
    self.noteLbl.layer.cornerRadius = 6;
    self.noteLbl.clipsToBounds = YES;
    [self.panel addSubview:self.noteLbl];

    // Stack SĐT
    self.stack = [[UIStackView alloc] initWithFrame:CGRectMake(8, 64, 244, 20)];
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 4;
    [self.panel addSubview:self.stack];

    // Nút Gửi ảnh
    self.shareBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.shareBtn.frame = CGRectMake(8, 88, 244, 36);
    [self.shareBtn setTitle:@"📤 GỬI ẢNH ĐƠN CHO QUÁN" forState:UIControlStateNormal];
    self.shareBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
    self.shareBtn.tintColor = [UIColor whiteColor];
    self.shareBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
    self.shareBtn.layer.cornerRadius = 6;
    [self.shareBtn addTarget:self action:@selector(shareOrder) forControlEvents:UIControlEventTouchUpInside];
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
- (void)openPanel { self.bubbleBtn.hidden = YES; self.panel.hidden = NO; [self scanAndRefresh]; }
- (void)closePanel { self.panel.hidden = YES; self.bubbleBtn.hidden = NO; }

// Cuộn app xuống đáy để lấy hết đơn
- (void)scrollDown:(UIView *)v {
    if ([v isKindOfClass:[UIScrollView class]]) {
        UIScrollView *sv = (UIScrollView *)v;
        if (sv.contentSize.height > sv.bounds.size.height)
            [sv setContentOffset:CGPointMake(0, sv.contentSize.height - sv.bounds.size.height) animated:NO];
    }
    for (UIView *s in v.subviews) [self scrollDown:s];
}

- (void)scanAndRefresh {
    self.panel.alpha = 0.0;
    UIWindow *win = [UIApplication sharedApplication].windows.firstObject;
    [self scrollDown:win];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIGraphicsBeginImageContextWithOptions(win.bounds.size, NO, 0.0);
        [win drawViewHierarchyInRect:win.bounds afterScreenUpdates:YES];
        UIImage *full = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        // Cắt khúc đơn hàng (bỏ header)
        CGFloat sc = full.scale, y = win.bounds.size.height * 0.35, h = win.bounds.size.height * 0.55;
        CGImageRef cr = CGImageCreateWithImageInRect(full.CGImage, CGRectMake(0, y * sc, win.bounds.size.width * sc, h * sc));
        self.orderImg = [UIImage imageWithCGImage:cr scale:sc orientation:full.imageOrientation];
        CGImageRelease(cr);

        // Chạy OCR nhận diện
        VNRecognizeTextRequest *req = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *r, NSError *e) {
            NSMutableSet *phones = [NSMutableSet set];
            __block NSString *note = @"(Không có ghi chú)";

            for (VNRecognizedTextObservation *o in r.results) {
                NSString *str = [[o topCandidates:1] firstObject].string;
                if ([str.lowercaseString containsString:@"ghi chú"] || [str.lowercaseString containsString:@"dặn"]) note = str;

                // Lọc & Cắt chuẩn SĐT 10 số (03,05,07,08,09) / 11 số (02)
                NSRegularExpression *reg = [NSRegularExpression regularExpressionWithPattern:@"(?:\\+?84|0)(?:3[2-9]|5[6|8|9]|7[0|6-9]|8[1-9]|9[0-9]|2[0-9]{2})[0-9\\s.-]{6,15}" options:0 error:nil];
                for (NSTextCheckingResult *m in [reg matchesInString:str options:0 range:NSMakeRange(0, str.length)]) {
                    NSString *num = [[[str substringWithRange:m.range] componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
                    if ([num hasPrefix:@"84"]) num = [@"0" stringByAppendingString:[num substringFromIndex:2]];
                    if (num.length >= 10 && ([num hasPrefix:@"03"]||[num hasPrefix:@"05"]||[num hasPrefix:@"07"]||[num hasPrefix:@"08"]||[num hasPrefix:@"09"])) [phones addObject:[num substringToIndex:10]];
                    else if (num.length >= 11 && [num hasPrefix:@"02"]) [phones addObject:[num substringToIndex:11]];
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                self.panel.alpha = 1.0;
                self.noteLbl.text = [NSString stringWithFormat:@" 📌 %@", note];
                for (UIView *v in self.stack.arrangedSubviews) { [self.stack removeArrangedSubview:v]; [v removeFromSuperview]; }

                CGFloat hStack = 0;
                if (phones.count > 0) {
                    for (NSString *p in phones) [self addPhoneBtn:p];
                    hStack = phones.count * 30.0 + (phones.count - 1) * 4.0;
                } else {
                    UILabel *lbl = [UILabel new]; lbl.text = @"(Không tìm thấy SĐT)"; lbl.textColor = [UIColor lightGrayColor]; lbl.font = [UIFont systemFontOfSize:10.5];
                    [self.stack addArrangedSubview:lbl]; hStack = 16.0;
                }

                // Co giãn Panel dạt phải
                CGFloat sw = [UIScreen mainScreen].bounds.size.width;
                self.stack.frame = CGRectMake(8, 64, 244, hStack);
                self.shareBtn.frame = CGRectMake(8, 64 + hStack + 6, 244, 36);
                [UIView animateWithDuration:0.2 animations:^{
                    self.panel.frame = CGRectMake(sw - 270, 85, 260, 64 + hStack + 6 + 36 + 8);
                }];
            });
        }];
        req.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        [[[VNImageRequestHandler alloc] initWithCGImage:full.CGImage options:@{}] performRequests:@[req] error:nil];
    });
}

- (void)addPhoneBtn:(NSString *)p {
    UIView *r = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 244, 30)];
    r.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    r.layer.cornerRadius = 4;

    UIButton *nb = [UIButton buttonWithType:UIButtonTypeSystem];
    nb.frame = CGRectMake(4, 1, 170, 28);
    [nb setTitle:[NSString stringWithFormat:@"📱 %@", p] forState:UIControlStateNormal];
    [nb setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    nb.titleLabel.font = [UIFont fontWithName:@"Menlo-Bold" size:11.5];
    nb.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    nb.accessibilityValue = p;
    [nb addTarget:self action:@selector(editPhone:) forControlEvents:UIControlEventTouchUpInside];
    [r addSubview:nb];

    UIButton *cb = [UIButton buttonWithType:UIButtonTypeSystem];
    cb.frame = CGRectMake(180, 2, 60, 26);
    [cb setTitle:@"📞 Gọi" forState:UIControlStateNormal];
    cb.backgroundColor = [UIColor systemGreenColor];
    cb.tintColor = [UIColor whiteColor];
    cb.titleLabel.font = [UIFont boldSystemFontOfSize:10.5];
    cb.layer.cornerRadius = 4;
    cb.accessibilityValue = p;
    [cb addTarget:self action:@selector(callPhone:) forControlEvents:UIControlEventTouchUpInside];
    [r addSubview:cb];

    [self.stack addArrangedSubview:r];
}

- (void)callPhone:(UIButton *)b {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[@"tel://" stringByAppendingString:b.accessibilityValue]] options:@{} completionHandler:nil];
}

- (void)editPhone:(UIButton *)b {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Sửa SĐT" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t) { t.text = b.accessibilityValue; t.keyboardType = UIKeyboardTypePhonePad; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Gọi" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[@"tel://" stringByAppendingString:a.textFields.firstObject.text]] options:@{} completionHandler:nil];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)shareOrder {
    if (!self.orderImg) return;
    [self presentViewController:[[UIActivityViewController alloc] initWithActivityItems:@[self.orderImg] applicationActivities:nil] animated:YES completion:nil];
}

@end

#pragma mark - ENTRY POINT

static UIWindow *gWin = nil;
__attribute__((constructor)) static void init_hook(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                gWin = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
                gWin.windowLevel = UIWindowLevelAlert + 1000.0;
                gWin.backgroundColor = [UIColor clearColor];
                gWin.rootViewController = [DriverHelperVC new];
                gWin.hidden = NO;
            });
        });
    }];
}
