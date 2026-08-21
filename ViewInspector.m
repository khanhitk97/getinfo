#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - DATA DUMP ENGINE (SAFE & ROBUST)

@interface SafeInspectorEngine : NSObject
+ (NSString *)performDeepInspection;
+ (void)forceRevealAll;
@end

@implementation SafeInspectorEngine

// Trích xuất text an toàn tuyệt đối
+ (NSString *)safeExtractText:(UIView *)view {
    if (!view) return @"";
    NSMutableString *outStr = [NSMutableString string];
    
    @try {
        if ([view isKindOfClass:[UILabel class]]) {
            NSString *t = [(UILabel *)view text];
            if (t.length) [outStr appendFormat:@"[Label: \"%@\"] ", t];
        } else if ([view isKindOfClass:[UITextField class]]) {
            UITextField *tf = (UITextField *)view;
            if (tf.text.length) [outStr appendFormat:@"[TF: \"%@\" | Secure: %d] ", tf.text, tf.isSecureTextEntry];
        } else if ([view isKindOfClass:[UITextView class]]) {
            NSString *t = [(UITextView *)view text];
            if (t.length) [outStr appendFormat:@"[TV: \"%@\"] ", t];
        } else if ([view isKindOfClass:[UIButton class]]) {
            NSString *t = [(UIButton *)view titleForState:UIControlStateNormal];
            if (t.length) [outStr appendFormat:@"[Btn: \"%@\"] ", t];
        } else {
            // Check accessibility label an toàn
            NSString *acc = view.accessibilityLabel;
            if (acc.length) {
                [outStr appendFormat:@"[A11y: \"%@\"] ", acc];
            }
        }
    } @catch (__unused NSException *e) {}
    
    return outStr;
}

// Quét View Hierarchy trên Main Thread an toàn
+ (void)recursiveInspectView:(UIView *)view level:(int)level buffer:(NSMutableString *)buffer filterWindow:(UIWindow *)inspectorWin {
    if (!view || view == inspectorWin || [view isDescendantOfView:inspectorWin]) return;

    NSString *indent = [@"" stringByPaddingToLength:level * 2 withString:@"  " startingAtIndex:0];
    
    @try {
        BOOL isHidden = view.isHidden;
        BOOL isAlphaZero = view.alpha < 0.05;
        BOOL isLayerHidden = view.layer.hidden || view.layer.opacity < 0.05;
        NSString *textContent = [self safeExtractText:view];
        
        UIResponder *responder = view.nextResponder;
        NSString *vcInfo = @"";
        if ([responder isKindOfClass:[UIViewController class]]) {
            vcInfo = [NSString stringWithFormat:@" -> [VC: %@]", NSStringFromClass([responder class])];
        }

        if (isHidden || isAlphaZero || isLayerHidden || textContent.length > 0) {
            [buffer appendFormat:@"%@• %@%@ | F:(%.0f,%.0f,%.0f,%.0f) | α:%.2f | Hide:[V:%d, L:%d] %@\n",
                indent,
                NSStringFromClass([view class]),
                vcInfo,
                view.frame.origin.x, view.frame.origin.y, view.frame.size.width, view.frame.size.height,
                view.alpha,
                isHidden, isLayerHidden,
                textContent];
        }

        for (UIView *sub in view.subviews) {
            [self recursiveInspectView:sub level:level + 1 buffer:buffer filterWindow:inspectorWin];
        }
    } @catch (__unused NSException *e) {}
}

+ (NSArray<UIWindow *> *)getAllAppWindows {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
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

+ (NSString *)performDeepInspection {
    NSMutableString *buffer = [NSMutableString stringWithCapacity:8192];
    [buffer appendString:@"====== INSPECTION REPORT ======\n\n"];
    
    NSArray<UIWindow *> *windows = [self getAllAppWindows];
    for (UIWindow *w in windows) {
        if (![w isKindOfClass:[UIWindow class]]) continue;
        [buffer appendFormat:@"\n[WINDOW: %@ | Frame: %@]\n", NSStringFromClass([w class]), NSStringFromCGRect(w.frame)];
        [self recursiveInspectView:w level:0 buffer:buffer filterWindow:nil];
    }

    return buffer;
}

+ (void)forceUnhideView:(UIView *)view {
    if (!view) return;
    @try {
        view.hidden = NO;
        view.alpha = 1.0;
        view.layer.hidden = NO;
        view.layer.opacity = 1.0;
        view.clipsToBounds = NO;
        
        if ([view isKindOfClass:[UITextField class]]) {
            ((UITextField *)view).secureTextEntry = NO;
        }
        
        for (UIView *sub in view.subviews) {
            [self forceUnhideView:sub];
        }
    } @catch (__unused NSException *e) {}
}

+ (void)forceRevealAll {
    for (UIWindow *w in [self getAllAppWindows]) {
        [self forceUnhideView:w];
    }
}

@end

#pragma mark - UI OVERLAY CONTROLLER

@interface SafeInspectorVC : UIViewController <UISearchBarDelegate>
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, copy) NSString *fullLog;
@end

@implementation SafeInspectorVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    
    CGFloat w = [UIScreen mainScreen].bounds.size.width;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(10, 55, w - 20, 380)];
    self.panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.92];
    self.panel.layer.cornerRadius = 12;
    self.panel.layer.borderWidth = 1.2;
    self.panel.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:1.0].CGColor;
    self.panel.clipsToBounds = YES;
    [self.view addSubview:self.panel];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    [self.panel addGestureRecognizer:pan];
    
    UIButton *scanBtn = [self createBtn:@"Scan Views" color:[UIColor systemBlueColor] frame:CGRectMake(8, 10, 85, 30) action:@selector(runScan)];
    UIButton *unhideBtn = [self createBtn:@"Unhide All" color:[UIColor systemOrangeColor] frame:CGRectMake(98, 10, 85, 30) action:@selector(runUnhide)];
    UIButton *copyBtn = [self createBtn:@"Copy" color:[UIColor systemGreenColor] frame:CGRectMake(188, 10, 50, 30) action:@selector(copyLog)];
    UIButton *minBtn = [self createBtn:@"Min" color:[UIColor systemRedColor] frame:CGRectMake(self.panel.frame.size.width - 48, 10, 40, 30) action:@selector(toggleMin)];
    
    [self.panel addSubview:scanBtn];
    [self.panel addSubview:unhideBtn];
    [self.panel addSubview:copyBtn];
    [self.panel addSubview:minBtn];
    
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 44, self.panel.frame.size.width, 36)];
    self.searchBar.placeholder = @"Search (text, label, class)...";
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.delegate = self;
    self.searchBar.barStyle = UIBarStyleBlack;
    [self.panel addSubview:self.searchBar];

    self.textView = [[UITextView alloc] initWithFrame:CGRectMake(8, 84, self.panel.frame.size.width - 16, 288)];
    self.textView.backgroundColor = [UIColor colorWithWhite:0.04 alpha:1.0];
    self.textView.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:1.0];
    self.textView.font = [UIFont fontWithName:@"Menlo" size:10];
    self.textView.editable = NO;
    self.textView.layer.cornerRadius = 6;
    [self.panel addSubview:self.textView];
}

- (UIButton *)createBtn:(NSString *)title color:(UIColor *)color frame:(CGRect)frame action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = frame;
    [btn setTitle:title forState:UIControlStateNormal];
    btn.backgroundColor = color;
    btn.tintColor = [UIColor whiteColor];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    btn.layer.cornerRadius = 6;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)onPan:(UIPanGestureRecognizer *)p {
    CGPoint trans = [p translationInView:self.view];
    self.panel.center = CGPointMake(self.panel.center.x + trans.x, self.panel.center.y + trans.y);
    [p setTranslation:CGPointZero inView:self.view];
}

- (void)toggleMin {
    [UIView animateWithDuration:0.2 animations:^{
        if (self.panel.frame.size.height > 60) {
            self.panel.frame = CGRectMake(self.panel.frame.origin.x, self.panel.frame.origin.y, 220, 48);
            self.textView.hidden = YES;
            self.searchBar.hidden = YES;
        } else {
            CGFloat w = [UIScreen mainScreen].bounds.size.width;
            self.panel.frame = CGRectMake(10, self.panel.frame.origin.y, w - 20, 380);
            self.textView.hidden = NO;
            self.searchBar.hidden = NO;
        }
    }];
}

- (void)runScan {
    // Quét trực tiếp trên Main Thread để tránh vi phạm UIKit Threading
    self.fullLog = [SafeInspectorEngine performDeepInspection];
    self.textView.text = self.fullLog;
}

- (void)runUnhide {
    [SafeInspectorEngine forceRevealAll];
    [self runScan];
}

- (void)copyLog {
    [UIPasteboard generalPasteboard].string = self.textView.text ?: @"";
    [self.view endEditing:YES];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        self.textView.text = self.fullLog;
        return;
    }
    NSMutableString *filtered = [NSMutableString string];
    NSArray *lines = [self.fullLog componentsSeparatedByString:@"\n"];
    for (NSString *l in lines) {
        if ([l localizedCaseInsensitiveContainsString:searchText]) {
            [filtered appendFormat:@"%@\n", l];
        }
    }
    self.textView.text = filtered;
}

@end

#pragma mark - OVERLAY WINDOW CONTAINER

@interface SafeOverlayWindow : UIWindow
@end

@implementation SafeOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self.rootViewController.view) return nil; // Xuyên chạm xuống app gốc
    return hit;
}
@end

static SafeOverlayWindow *gSafeOverlay = nil;

static void showOverlaySafely(void) {
    if (gSafeOverlay) return;

    UIWindowScene *activeScene = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && scene.activationState == UISceneActivationStateForegroundActive) {
                activeScene = (UIWindowScene *)scene;
                break;
            }
        }
    }

    if (@available(iOS 13.0, *)) {
        if (activeScene) {
            gSafeOverlay = [[SafeOverlayWindow alloc] initWithWindowScene:activeScene];
        } else {
            gSafeOverlay = [[SafeOverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }
    } else {
        gSafeOverlay = [[SafeOverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    }

    gSafeOverlay.windowLevel = UIWindowLevelAlert + 500.0;
    gSafeOverlay.backgroundColor = [UIColor clearColor];
    
    SafeInspectorVC *vc = [[SafeInspectorVC alloc] init];
    gSafeOverlay.rootViewController = vc;
    gSafeOverlay.hidden = NO;
    
    [vc runScan];
}

__attribute__((constructor))
static void dylib_entry(void) {
    // Chờ app hoàn tất khởi chạy và active UI Window
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                showOverlaySafely();
            });
        });
    }];
}
