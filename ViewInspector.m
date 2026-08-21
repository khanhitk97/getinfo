#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - DATA STRUCTURE & EXTRACTION

@interface InspectionEngine : NSObject
+ (NSString *)performDeepInspection;
+ (void)forceRevealAll;
@end

@implementation InspectionEngine

// 1. Trích xuất Ivars & Properties ẩn qua Objective-C Runtime
+ (NSString *)dumpRuntimeDetailsForObject:(id)obj {
    if (!obj) return @"";
    NSMutableString *details = [NSMutableString string];
    Class cls = [obj class];
    
    // Dump Ivars (Biến thành viên private)
    unsigned int ivarCount = 0;
    Ivar *ivars = class_copyIvarList(cls, &ivarCount);
    if (ivars) {
        for (unsigned int i = 0; i < ivarCount; i++) {
            const char *name = ivar_getName(ivars[i]);
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (!name) continue;
            
            NSString *ivarName = [NSString stringWithUTF8String:name];
            // Lọc các ivar tiềm năng chứa dữ liệu (text, token, balance, user, auth, secret)
            NSString *lower = [ivarName lowercaseString];
            if ([lower containsString:@"text"] || [lower containsString:@"token"] || 
                [lower containsString:@"pass"] || [lower containsString:@"data"] || 
                [lower containsString:@"user"] || [lower containsString:@"info"] ||
                [lower containsString:@"value"] || [lower containsString:@"title"]) {
                
                @try {
                    id val = object_getIvar(obj, ivars[i]);
                    if (val && [val respondsToSelector:@selector(description)]) {
                        NSString *desc = [val description];
                        if (desc.length > 0 && desc.length < 150) {
                            [details appendFormat:@"\n      [Ivar: %s = %@] ", name, desc];
                        }
                    }
                } @catch (__unused NSException *e) {}
            }
        }
        free(ivars);
    }
    return details;
}

// 2. Trích xuất text từ mọi cơ chế hiển thị (UILabel, UITextField, Web, Flutter/SwiftUI Container)
+ (NSString *)extractTextFromView:(UIView *)view {
    NSMutableString *outStr = [NSMutableString string];
    
    // Check UITextField / UITextView / UILabel
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
    }

    // Dynamic extraction qua KVC nếu app bọc custom view
    if (outStr.length == 0) {
        NSArray *possibleKeys = @[@"text", @"title", @"accessibilityLabel", @"stringValue", @"attributedText.string"];
        for (NSString *key in possibleKeys) {
            @try {
                id val = [view valueForKeyPath:key];
                if ([val isKindOfClass:[NSString class]] && [(NSString *)val length] > 0) {
                    [outStr appendFormat:@"[%@: \"%@\"] ", key, val];
                    break;
                }
            } @catch (__unused NSException *e) {}
        }
    }
    return outStr;
}

// 3. Quét đệ quy cây View + CALayer + ViewController
+ (void)recursiveInspectView:(UIView *)view level:(int)level buffer:(NSMutableString *)buffer filterWindow:(UIWindow *)inspectorWin {
    if (!view || view == inspectorWin || [view isDescendantOfView:inspectorWin]) return;

    NSString *indent = [@"" stringByPaddingToLength:level * 2 withString:@"  " startingAtIndex:0];
    
    // Kiểm tra trạng thái ẩn chuyên sâu
    BOOL isHidden = view.isHidden;
    BOOL isAlphaZero = view.alpha < 0.05;
    BOOL isOutOfBounds = (view.frame.origin.x < -50 || view.frame.origin.y < -50 || 
                          view.frame.size.width <= 1 || view.frame.size.height <= 1);
    BOOL isLayerHidden = view.layer.hidden || view.layer.opacity < 0.05;
    
    NSString *textContent = [self extractTextFromView:view];
    NSString *runtimeInfo = [self dumpRuntimeDetailsForObject:view];
    
    // Tìm UIViewController quản lý view này (nếu có)
    UIResponder *responder = view.nextResponder;
    NSString *vcInfo = @"";
    if ([responder isKindOfClass:[UIViewController class]]) {
        UIViewController *vc = (UIViewController *)responder;
        vcInfo = [NSString stringWithFormat:@" -> [VC: %@]", NSStringFromClass([vc class])];
        NSString *vcIvars = [self dumpRuntimeDetailsForObject:vc];
        if (vcIvars.length) {
            runtimeInfo = [runtimeInfo stringByAppendingString:vcIvars];
        }
    }

    // Nếu view có text hoặc có dấu hiệu bị ẩn/nằm ngoài bounds
    if (isHidden || isAlphaZero || isOutOfBounds || isLayerHidden || textContent.length > 0 || runtimeInfo.length > 0) {
        [buffer appendFormat:@"%@• %@%@ | F: (%.0f,%.0f,%.0f,%.0f) | α: %.2f | Hidden: [V:%d, L:%d, Clip:%d] %@%@\n",
            indent,
            NSStringFromClass([view class]),
            vcInfo,
            view.frame.origin.x, view.frame.origin.y, view.frame.size.width, view.frame.size.height,
            view.alpha,
            isHidden, isLayerHidden, view.clipsToBounds,
            textContent,
            runtimeInfo];
    }

    for (UIView *sub in view.subviews) {
        [self recursiveInspectView:sub level:level + 1 buffer:buffer filterWindow:inspectorWin];
    }
}

+ (NSString *)performDeepInspection {
    NSMutableString *buffer = [NSMutableString stringWithCapacity:16384];
    [buffer appendString:@"====== DEEP UI & RUNTIME INSPECTION ======\n\n"];
    
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

    for (UIWindow *w in windows) {
        [buffer appendFormat:@"\n[ROOT WINDOW: %@ | Layer: %p | Frame: %@]\n", 
            NSStringFromClass([w class]), w.layer, NSStringFromCGRect(w.frame)];
        [self recursiveInspectView:w level:0 buffer:buffer filterWindow:nil];
    }

    return buffer;
}

+ (void)forceUnhideView:(UIView *)view {
    if (!view) return;
    
    view.hidden = NO;
    view.alpha = 1.0;
    view.layer.hidden = NO;
    view.layer.opacity = 1.0;
    view.clipsToBounds = NO; // Cho phép hiển thị nếu view con vẽ tràn ra ngoài
    
    if ([view isKindOfClass:[UITextField class]]) {
        ((UITextField *)view).secureTextEntry = NO;
    }
    
    // Đưa view bị đẩy ra ngoài tọa độ âm về lại màn hình (nếu có)
    if (view.frame.origin.x < 0 || view.frame.origin.y < 0) {
        CGRect f = view.frame;
        if (f.origin.x < 0) f.origin.x = 0;
        if (f.origin.y < 0) f.origin.y = 0;
        view.frame = f;
    }
    
    for (UIView *sub in view.subviews) {
        [self forceUnhideView:sub];
    }
}

+ (void)forceRevealAll {
    NSArray<UIWindow *> *windows = [UIApplication sharedApplication].windows;
    for (UIWindow *w in windows) {
        [self forceUnhideView:w];
    }
}

@end

#pragma mark - UI OVERLAY (DRAGGABLE & RESIZABLE)

@interface AdvancedInspectorVC : UIViewController <UISearchBarDelegate>
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, copy) NSString *fullLog;
@end

@implementation AdvancedInspectorVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    
    CGFloat w = [UIScreen mainScreen].bounds.size.width;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(10, 60, w - 20, 420)];
    self.panel.backgroundColor = [[UIColor colorWithWhite:0.05 alpha:0.95] colorWithAlphaComponent:0.95];
    self.panel.layer.cornerRadius = 12;
    self.panel.layer.borderWidth = 1;
    self.panel.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
    self.panel.clipsToBounds = YES;
    [self.view addSubview:self.panel];
    
    // Pan gesture di chuyển panel
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    [self.panel addGestureRecognizer:pan];
    
    // Controls Header
    UIButton *scanBtn = [self createButtonWithTitle:@"Deep Scan" color:[UIColor systemBlueColor] frame:CGRectMake(8, 10, 85, 30) action:@selector(runScan)];
    UIButton *unhideBtn = [self createButtonWithTitle:@"Force Reveal" color:[UIColor systemOrangeColor] frame:CGRectMake(98, 10, 95, 30) action:@selector(runUnhide)];
    UIButton *copyBtn = [self createButtonWithTitle:@"Copy" color:[UIColor systemGreenColor] frame:CGRectMake(198, 10, 55, 30) action:@selector(copyLog)];
    UIButton *minBtn = [self createButtonWithTitle:@"Min" color:[UIColor systemRedColor] frame:CGRectMake(self.panel.frame.size.width - 50, 10, 42, 30) action:@selector(toggleMin)];
    
    [self.panel addSubview:scanBtn];
    [self.panel addSubview:unhideBtn];
    [self.panel addSubview:copyBtn];
    [self.panel addSubview:minBtn];
    
    // Search Bar lọc log nhanh
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 45, self.panel.frame.size.width, 36)];
    self.searchBar.placeholder = @"Filter (e.g., token, label, text)...";
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.delegate = self;
    self.searchBar.barStyle = UIBarStyleBlack;
    [self.panel addSubview:self.searchBar];

    // Log View
    self.textView = [[UITextView alloc] initWithFrame:CGRectMake(8, 85, self.panel.frame.size.width - 16, 325)];
    self.textView.backgroundColor = [UIColor blackColor];
    self.textView.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:1.0];
    self.textView.font = [UIFont fontWithName:@"Menlo-Regular" size:10];
    self.textView.editable = NO;
    self.textView.layer.cornerRadius = 6;
    [self.panel addSubview:self.textView];
}

- (UIButton *)createButtonWithTitle:(NSString *)title color:(UIColor *)color frame:(CGRect)frame action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = frame;
    [btn setTitle:title forState:UIControlStateNormal];
    btn.backgroundColor = color;
    btn.tintColor = [UIColor whiteColor];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    btn.layer.cornerRadius = 5;
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
            self.panel.frame = CGRectMake(self.panel.frame.origin.x, self.panel.frame.origin.y, 220, 50);
            self.textView.hidden = YES;
            self.searchBar.hidden = YES;
        } else {
            CGFloat w = [UIScreen mainScreen].bounds.size.width;
            self.panel.frame = CGRectMake(10, self.panel.frame.origin.y, w - 20, 420);
            self.textView.hidden = NO;
            self.searchBar.hidden = NO;
        }
    }];
}

- (void)runScan {
    self.textView.text = @"Scanning...";
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *res = [InspectionEngine performDeepInspection];
        dispatch_async(dispatch_get_mainQueue(), ^{
            self.fullLog = res;
            self.textView.text = res;
        });
    });
}

- (void)runUnhide {
    [InspectionEngine forceRevealAll];
    [self runScan];
}

- (void)copyLog {
    [UIPasteboard generalPasteboard].string = self.textView.text;
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

#pragma mark - WINDOW INJECTION & LIFECYCLE

@interface PassthroughWindow : UIWindow
@end

@implementation PassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self.rootViewController.view) return nil;
    return hit;
}
@end

static PassthroughWindow *gOverlay = nil;

__attribute__((constructor))
static void dylib_init(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_mainQueue(), ^{
            UIWindowScene *scene = nil;
            if (@available(iOS 13.0, *)) {
                for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
                    if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) {
                        scene = (UIWindowScene *)s;
                        break;
                    }
                }
            }
            
            if (scene) {
                gOverlay = [[PassthroughWindow alloc] initWithWindowScene:scene];
            } else {
                gOverlay = [[PassthroughWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
            }
            
            gOverlay.windowLevel = UIWindowLevelAlert + 9999.0;
            gOverlay.backgroundColor = [UIColor clearColor];
            AdvancedInspectorVC *vc = [[AdvancedInspectorVC alloc] init];
            gOverlay.rootViewController = vc;
            gOverlay.hidden = NO;
            [vc runScan];
        });
    }];
}
