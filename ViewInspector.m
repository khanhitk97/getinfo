#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface InspectorViewController : UIViewController
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UIView *panelContainer;
@property (nonatomic, assign) BOOL isMinimized;
@end

@implementation InspectorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    
    // Panel chính
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    self.panelContainer = [[UIView alloc] initWithFrame:CGRectMake(15, 60, screenW - 30, 360)];
    self.panelContainer.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.92];
    self.panelContainer.layer.cornerRadius = 14;
    self.panelContainer.layer.borderWidth = 1.0;
    self.panelContainer.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:1.0].CGColor;
    self.panelContainer.clipsToBounds = YES;
    [self.view addSubview:self.panelContainer];
    
    // Kéo thả Panel (Pan Gesture)
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.panelContainer addGestureRecognizer:pan];

    // Nút Scan Views
    UIButton *scanBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    scanBtn.frame = CGRectMake(10, 12, 90, 32);
    [scanBtn setTitle:@"Scan Views" forState:UIControlStateNormal];
    scanBtn.backgroundColor = [UIColor systemBlueColor];
    scanBtn.tintColor = [UIColor whiteColor];
    scanBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    scanBtn.layer.cornerRadius = 6;
    [scanBtn addTarget:self action:@selector(scanHiddenElements) forControlEvents:UIControlEventTouchUpInside];
    [self.panelContainer addSubview:scanBtn];

    // Nút Unhide All
    UIButton *unhideBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    unhideBtn.frame = CGRectMake(110, 12, 90, 32);
    [unhideBtn setTitle:@"Unhide All" forState:UIControlStateNormal];
    unhideBtn.backgroundColor = [UIColor systemOrangeColor];
    unhideBtn.tintColor = [UIColor whiteColor];
    unhideBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    unhideBtn.layer.cornerRadius = 6;
    [unhideBtn addTarget:self action:@selector(unhideAllHiddenElements) forControlEvents:UIControlEventTouchUpInside];
    [self.panelContainer addSubview:unhideBtn];

    // Nút Thu nhỏ / Phóng to
    UIButton *toggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    toggleBtn.frame = CGRectMake(self.panelContainer.frame.size.width - 75, 12, 65, 32);
    [toggleBtn setTitle:@"Ẩn/Hiện" forState:UIControlStateNormal];
    toggleBtn.backgroundColor = [UIColor systemRedColor];
    toggleBtn.tintColor = [UIColor whiteColor];
    toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    toggleBtn.layer.cornerRadius = 6;
    [toggleBtn addTarget:self action:@selector(toggleMinimize) forControlEvents:UIControlEventTouchUpInside];
    [self.panelContainer addSubview:toggleBtn];

    // Text View log kết quả
    self.textView = [[UITextView alloc] initWithFrame:CGRectMake(10, 55, self.panelContainer.frame.size.width - 20, 295)];
    self.textView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    self.textView.textColor = [UIColor greenColor];
    self.textView.font = [UIFont fontWithName:@"Menlo" size:10.5];
    self.textView.editable = NO;
    self.textView.layer.cornerRadius = 8;
    [self.panelContainer addSubview:self.textView];
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.view];
    UIView *target = self.panelContainer;
    target.center = CGPointMake(target.center.x + translation.x, target.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self.view];
}

- (void)toggleMinimize {
    self.isMinimized = !self.isMinimized;
    [UIView animateWithDuration:0.25 animations:^{
        if (self.isMinimized) {
            self.panelContainer.frame = CGRectMake(self.panelContainer.frame.origin.x, self.panelContainer.frame.origin.y, 200, 55);
            self.textView.hidden = YES;
        } else {
            CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
            self.panelContainer.frame = CGRectMake(15, self.panelContainer.frame.origin.y, screenW - 30, 360);
            self.textView.hidden = NO;
        }
    }];
}

// Xử lý đệ quy cây View
- (void)dumpViewHierarchy:(UIView *)view level:(int)level buffer:(NSMutableString *)buffer {
    if (!view || view == self.view || view == self.panelContainer) return;

    NSString *indent = [@"" stringByPaddingToLength:level * 2 withString:@"  " startingAtIndex:0];
    BOOL isHidden = view.isHidden || view.alpha < 0.05;
    
    NSString *extraInfo = @"";
    if ([view isKindOfClass:[UILabel class]]) {
        extraInfo = [NSString stringWithFormat:@"[Text: '%@']", [(UILabel *)view text] ?: @""];
    } else if ([view isKindOfClass:[UITextField class]]) {
        UITextField *tf = (UITextField *)view;
        extraInfo = [NSString stringWithFormat:@"[TF: '%@' | Secure: %d]", tf.text ?: @"", tf.isSecureTextEntry];
    } else if ([view isKindOfClass:[UITextView class]]) {
        extraInfo = [NSString stringWithFormat:@"[TV: '%@']", [(UITextView *)view text] ?: @""];
    } else if ([view isKindOfClass:[UIButton class]]) {
        extraInfo = [NSString stringWithFormat:@"[Btn: '%@']", [(UIButton *)view titleForState:UIControlStateNormal] ?: @""];
    }

    if (isHidden || extraInfo.length > 0) {
        [buffer appendFormat:@"%@• %@ (Hidden:%d, α:%.1f) %@\n", 
            indent, 
            NSStringFromClass([view class]), 
            view.isHidden, 
            view.alpha, 
            extraInfo];
    }

    for (UIView *sub in view.subviews) {
        [self dumpViewHierarchy:sub level:level + 1 buffer:buffer];
    }
}

// Tìm toàn bộ UIWindow đang có trên app (hỗ trợ cả iOS 13+ Scene lẫn iOS cũ)
- (NSArray<UIWindow *> *)getAllAppWindows {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                [windows addObjectsFromArray:ws.windows];
            }
        }
    }
    
    if (windows.count == 0) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [windows addObjectsFromArray:[UIApplication sharedApplication].windows];
        #pragma clang diagnostic pop
    }
    return windows;
}

- (void)scanHiddenElements {
    NSMutableString *buf = [NSMutableString stringWithString:@"=== KẾT QUẢ DUMP VIEW & DỮ LIỆU ===\n"];
    NSArray<UIWindow *> *windows = [self getAllAppWindows];
    
    for (UIWindow *w in windows) {
        if (w == self.view.window) continue;
        [buf appendFormat:@"\n[WINDOW: %@ (Hidden:%d)]\n", NSStringFromClass([w class]), w.isHidden];
        [self dumpViewHierarchy:w level:0 buffer:buf];
    }
    self.textView.text = buf;
}

- (void)unhideRecursive:(UIView *)view {
    if (!view || view == self.view || view == self.panelContainer) return;
    
    view.hidden = NO;
    if (view.alpha < 1.0) view.alpha = 1.0;
    
    if ([view isKindOfClass:[UITextField class]]) {
        ((UITextField *)view).secureTextEntry = NO;
    }
    
    for (UIView *sub in view.subviews) {
        [self unhideRecursive:sub];
    }
}

- (void)unhideAllHiddenElements {
    for (UIWindow *w in [self getAllAppWindows]) {
        if (w == self.view.window) continue;
        w.hidden = NO;
        [self unhideRecursive:w];
    }
    [self scanHiddenElements];
}

@end

// Lớp UIWindow tùy biến hỗ trợ xuyên chạm ra ngoài panel
@interface CustomOverlayWindow : UIWindow
@end

@implementation CustomOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    // Nếu chạm vào vùng trống ngoài panel thì nhường tương tác cho app gốc
    if (hitView == self.rootViewController.view) {
        return nil;
    }
    return hitView;
}
@end

static CustomOverlayWindow *gOverlayWindow = nil;

static void setupInspectorWindow(void) {
    UIWindowScene *activeScene = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                activeScene = (UIWindowScene *)scene;
                break;
            }
        }
    }

    if (@available(iOS 13.0, *)) {
        if (activeScene) {
            gOverlayWindow = [[CustomOverlayWindow alloc] initWithWindowScene:activeScene];
        } else {
            gOverlayWindow = [[CustomOverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }
    } else {
        gOverlayWindow = [[CustomOverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }

    gOverlayWindow.windowLevel = UIWindowLevelAlert + 1000.0;
    gOverlayWindow.backgroundColor = [UIColor clearColor];
    
    InspectorViewController *vc = [[InspectorViewController alloc] init];
    gOverlayWindow.rootViewController = vc;
    gOverlayWindow.hidden = NO;
    
    [vc scanHiddenElements];
}

__attribute__((constructor))
static void dylib_entry(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_mainQueue(), ^{
            setupInspectorWindow();
        });
    }];
}
