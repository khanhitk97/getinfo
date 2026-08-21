#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <Vision/Vision.h>
#import <Security/Security.h>

#pragma mark - 1. FILE LOGGER UTILITY

@interface FileLogger : NSObject
+ (void)appendLog:(NSString *)text;
+ (NSString *)getLogFilePath;
+ (void)clearLogFile;
@end

@implementation FileLogger

+ (NSString *)getLogFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docsDir = [paths firstObject];
    return [docsDir stringByAppendingPathComponent:@"pentest_logs.txt"];
}

+ (void)appendLog:(NSString *)text {
    if (!text || text.length == 0) return;
    
    NSString *filePath = [self getLogFilePath];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    
    NSString *entry = [NSString stringWithFormat:@"\n[%@] ================================\n%@\n", timestamp, text];
    
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    if (!handle) {
        [[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil];
        handle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    }
    
    if (handle) {
        [handle seekToEndOfFile];
        [handle writeData:[entry dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    }
}

+ (void)clearLogFile {
    NSString *filePath = [self getLogFilePath];
    [@"" writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

@end

#pragma mark - 2. UNIVERSAL NETWORK & SOCKET HOOK

@interface UniversalNetworkLogger : NSObject
+ (void)startLogging;
+ (NSArray<NSString *> *)getLogs;
+ (void)clear;
+ (void)logRawData:(NSData *)data source:(NSString *)src;
+ (void)logString:(NSString *)str source:(NSString *)src;
@end

static NSMutableArray<NSString *> *gNetLogs = nil;

@implementation UniversalNetworkLogger

+ (void)startLogging {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gNetLogs = [NSMutableArray array];

        // 1. Swizzle NSURLSession init để ép qua URLProtocol hoặc hook delegate
        Class connClass = NSClassFromString(@"__NSCFURLSessionConnection");
        if (!connClass) connClass = NSClassFromString(@"NSURLSessionConnection");
        if (connClass) {
            SEL origSel = NSSelectorFromString(@"_didReceiveData:");
            SEL swizSel = @selector(hook_didReceiveData:);
            Method origM = class_getInstanceMethod(connClass, origSel);
            Method swizM = class_getInstanceMethod([self class], swizSel);
            if (origM && swizM) method_exchangeImplementations(origM, swizM);
        }

        // 2. Hook WebSocket Delegate (SRWebSocket, Starscream, NSURLSessionWebSocketTask)
        Class wsTaskClass = NSClassFromString(@"__NSCFURLSessionWebSocketTask");
        if (wsTaskClass) {
            SEL wsSendSel = NSSelectorFromString(@"sendMessage:completionHandler:");
            SEL wsHookSel = @selector(hook_sendMessage:completionHandler:);
            Method origWS = class_getInstanceMethod(wsTaskClass, wsSendSel);
            Method swizWS = class_getInstanceMethod([self class], wsHookSel);
            if (origWS && swizWS) method_exchangeImplementations(origWS, swizWS);
        }

        // 3. Hook NSNotificationCenter cho các sự kiện push nội bộ
        [[NSNotificationCenter defaultCenter] addObserverForName:nil object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
            NSString *name = note.name;
            if ([name containsString:@"Order"] || [name containsString:@"order"] || [name containsString:@"Push"] || [name containsString:@"Socket"] || [name containsString:@"Message"]) {
                NSString *log = [NSString stringWithFormat:@"[INTERNAL NOTIFICATION: %@] %@", name, note.userInfo ?: @"no-info"];
                [UniversalNetworkLogger logString:log source:@"Notification"];
            }
        }];
    });
}

+ (void)logRawData:(NSData *)data source:(NSString *)src {
    if (!data || data.length == 0) return;

    // Thử parse JSON
    NSError *err = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    NSString *content = nil;
    if (json) {
        content = [NSString stringWithFormat:@"[%@ JSON] %@", src, json];
    } else {
        // Fallback sang plain string (hỗ trợ cả text protobuf/custom stream)
        NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (str && str.length > 0) {
            content = [NSString stringWithFormat:@"[%@ RAW STRING] %@", src, str];
        } else {
            content = [NSString stringWithFormat:@"[%@ RAW HEX (%lu bytes)] %@", src, (unsigned long)data.length, [data description]];
        }
    }

    [self logString:content source:src];
}

+ (void)logString:(NSString *)str source:(NSString *)src {
    if (!str || str.length == 0) return;
    @synchronized (gNetLogs) {
        if (gNetLogs.count > 100) [gNetLogs removeObjectAtIndex:0];
        [gNetLogs addObject:str];
    }
    [FileLogger appendLog:str];
}

- (void)hook_didReceiveData:(NSData *)data {
    [UniversalNetworkLogger logRawData:data source:@"HTTP/REST"];
    [self hook_didReceiveData:data];
}

- (void)hook_sendMessage:(id)msg completionHandler:(id)handler {
    [UniversalNetworkLogger logString:[NSString stringWithFormat:@"[WS OUTGOING] %@", [msg description]] source:@"WebSocket"];
    [self hook_sendMessage:msg completionHandler:handler];
}

+ (NSArray<NSString *> *)getLogs {
    @synchronized (gNetLogs) {
        return [gNetLogs copy];
    }
}

+ (void)clear {
    @synchronized (gNetLogs) {
        [gNetLogs removeAllObjects];
    }
}

@end

#pragma mark - 3. OCR & RUNTIME MEMORY DUMP ENGINE

@interface AdvancedInspectionEngine : NSObject
+ (void)performScreenOCR:(void(^)(NSString *ocrResult))completion;
+ (NSString *)performDeepRuntimeDump;
@end

@implementation AdvancedInspectionEngine

+ (void)dumpObject:(id)obj depth:(int)depth keyName:(NSString *)keyName buffer:(NSMutableString *)buffer visited:(NSMutableSet *)visited {
    if (!obj || depth > 5) return;
    NSValue *ptrVal = [NSValue valueWithNonretainedObject:obj];
    if ([visited containsObject:ptrVal]) return;
    [visited addObject:ptrVal];

    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@"  " startingAtIndex:0];

    @try {
        if ([obj isKindOfClass:[NSString class]]) {
            [buffer appendFormat:@"%@• [%@] \"%@\"\n", indent, keyName ?: @"Str", obj];
        } else if ([obj isKindOfClass:[NSNumber class]]) {
            [buffer appendFormat:@"%@• [%@] %@\n", indent, keyName ?: @"Num", obj];
        } else if ([obj isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)obj;
            [buffer appendFormat:@"%@📂 [%@] Dict (%lu):\n", indent, keyName ?: @"Data", (unsigned long)dict.count];
            for (id k in dict) {
                [self dumpObject:dict[k] depth:depth + 1 keyName:[k description] buffer:buffer visited:visited];
            }
        } else if ([obj isKindOfClass:[NSArray class]]) {
            NSArray *arr = (NSArray *)obj;
            if (arr.count > 0 && arr.count <= 20) {
                [buffer appendFormat:@"%@📑 [%@] List (%lu):\n", indent, keyName ?: @"Arr", (unsigned long)arr.count];
                for (NSUInteger i = 0; i < arr.count; i++) {
                    [self dumpObject:arr[i] depth:depth + 1 keyName:[NSString stringWithFormat:@"%lu", (unsigned long)i] buffer:buffer visited:visited];
                }
            }
        } else {
            Class cls = [obj class];
            NSString *clsName = NSStringFromClass(cls);
            if ([clsName hasPrefix:@"UI"] && ![clsName containsString:@"Cell"] && ![clsName containsString:@"Controller"]) return;

            unsigned int count = 0;
            Ivar *ivars = class_copyIvarList(cls, &count);
            if (ivars) {
                for (unsigned int i = 0; i < count; i++) {
                    const char *type = ivar_getTypeEncoding(ivars[i]);
                    const char *name = ivar_getName(ivars[i]);
                    if (type && type[0] == '@' && name) {
                        @try {
                            id val = object_getIvar(obj, ivars[i]);
                            if (val && ![val isKindOfClass:[UIView class]] && ![val isKindOfClass:[UIViewController class]]) {
                                [self dumpObject:val depth:depth + 1 keyName:[NSString stringWithUTF8String:name] buffer:buffer visited:visited];
                            }
                        } @catch (__unused NSException *e) {}
                    }
                }
                free(ivars);
            }
        }
    } @catch (__unused NSException *e) {}
}

+ (void)performScreenOCR:(void(^)(NSString *ocrResult))completion {
    if (@available(iOS 13.0, *)) {
        UIWindow *keyWin = [UIApplication sharedApplication].windows.firstObject;
        for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)s).windows) {
                    if (!w.isHidden && ![NSStringFromClass([w class]) containsString:@"InspectorOverlayWindow"]) {
                        keyWin = w;
                        break;
                    }
                }
            }
        }

        if (!keyWin) {
            if (completion) completion(@"Không tìm thấy cửa sổ để chụp.");
            return;
        }

        UIGraphicsBeginImageContextWithOptions(keyWin.bounds.size, NO, 0.0);
        [keyWin drawViewHierarchyInRect:keyWin.bounds afterScreenUpdates:NO];
        UIImage *snapshot = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        if (!snapshot.CGImage) {
            if (completion) completion(@"Lỗi chụp màn hình.");
            return;
        }

        VNRecognizeTextRequest *req = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest * _Nonnull request, NSError * _Nullable error) {
            NSMutableString *allText = [NSMutableString string];
            for (VNRecognizedTextObservation *obs in request.results) {
                VNRecognizedText *top = [[obs topCandidates:1] firstObject];
                if (top) [allText appendFormat:@"%@\n", top.string];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [FileLogger appendLog:[NSString stringWithFormat:@"[OCR SCREEN DUMP]\n%@", allText]];
                if (completion) completion(allText);
            });
        }];
        req.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        req.usesLanguageCorrection = NO;

        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:snapshot.CGImage options:@{}];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [handler performRequests:@[req] error:nil];
        });
    } else {
        if (completion) completion(@"Cần iOS 13+ để chạy OCR.");
    }
}

+ (UIViewController *)topVC:(UIViewController *)root {
    if ([root isKindOfClass:[UINavigationController class]]) return [self topVC:[(UINavigationController *)root visibleViewController]];
    if ([root isKindOfClass:[UITabBarController class]]) return [self topVC:[(UITabBarController *)root selectedViewController]];
    if (root.presentedViewController) return [self topVC:root.presentedViewController];
    return root;
}

+ (NSString *)performDeepRuntimeDump {
    NSMutableString *buf = [NSMutableString stringWithCapacity:8192];
    UIWindow *mainWin = [UIApplication sharedApplication].windows.firstObject;
    UIViewController *top = [self topVC:mainWin.rootViewController];

    [buf appendFormat:@"=== RUNTIME MEMORY DUMP: %@ ===\n\n", NSStringFromClass([top class])];
    if (top) {
        NSMutableSet *visited = [NSMutableSet set];
        [self dumpObject:top depth:0 keyName:@"RootVC" buffer:buf visited:visited];
    }
    [FileLogger appendLog:buf];
    return buf;
}

@end

#pragma mark - 4. UI CONTROLLER

@interface MultiToolInspectorVC : UIViewController <UISearchBarDelegate>
@property (nonatomic, strong) UIButton *bubbleBtn;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, copy) NSString *cachedLog;
@end

@implementation MultiToolInspectorVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    self.bubbleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.bubbleBtn.frame = CGRectMake(15, 120, 60, 60);
    self.bubbleBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.92];
    [self.bubbleBtn setTitle:@"⚡ Tools" forState:UIControlStateNormal];
    [self.bubbleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.bubbleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11.5];
    self.bubbleBtn.layer.cornerRadius = 30;
    self.bubbleBtn.layer.borderWidth = 2.0;
    self.bubbleBtn.layer.borderColor = [UIColor whiteColor].CGColor;
    [self.bubbleBtn addTarget:self action:@selector(openPanel) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *panB = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanBubble:)];
    [self.bubbleBtn addGestureRecognizer:panB];
    [self.view addSubview:self.bubbleBtn];

    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(10, 65, screenW - 20, 450)];
    self.panel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.96];
    self.panel.layer.cornerRadius = 14;
    self.panel.layer.borderWidth = 1.2;
    self.panel.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:1.0].CGColor;
    self.panel.clipsToBounds = YES;
    self.panel.hidden = YES;
    [self.view addSubview:self.panel];

    UIPanGestureRecognizer *panP = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPanPanel:)];
    [self.panel addGestureRecognizer:panP];

    UIButton *apiBtn = [self makeBtn:@"Network" color:[UIColor systemBlueColor] frame:CGRectMake(6, 10, 65, 30) action:@selector(showNetLogs)];
    UIButton *ocrBtn = [self makeBtn:@"OCR UI" color:[UIColor systemGreenColor] frame:CGRectMake(75, 10, 65, 30) action:@selector(runOCR)];
    UIButton *dumpBtn = [self makeBtn:@"Dump RAM" color:[UIColor systemOrangeColor] frame:CGRectMake(144, 10, 75, 30) action:@selector(runDump)];
    UIButton *clrBtn = [self makeBtn:@"Clear" color:[UIColor systemGrayColor] frame:CGRectMake(223, 10, 50, 30) action:@selector(clearLogs)];
    UIButton *closeBtn = [self makeBtn:@"✕" color:[UIColor systemRedColor] frame:CGRectMake(self.panel.frame.size.width - 36, 10, 30, 30) action:@selector(closePanel)];

    [self.panel addSubview:apiBtn];
    [self.panel addSubview:ocrBtn];
    [self.panel addSubview:dumpBtn];
    [self.panel addSubview:clrBtn];
    [self.panel addSubview:closeBtn];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 44, self.panel.frame.size.width, 36)];
    self.searchBar.placeholder = @"Lọc log (order, price, token, data)...";
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.delegate = self;
    self.searchBar.barStyle = UIBarStyleBlack;
    [self.panel addSubview:self.searchBar];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 82, self.panel.frame.size.width - 20, 18)];
    self.statusLabel.textColor = [UIColor yellowColor];
    self.statusLabel.font = [UIFont boldSystemFontOfSize:10.5];
    self.statusLabel.text = @"Universal Logger: REST / WS / Raw Stream ON";
    [self.panel addSubview:self.statusLabel];

    self.textView = [[UITextView alloc] initWithFrame:CGRectMake(8, 104, self.panel.frame.size.width - 16, 336)];
    self.textView.backgroundColor = [UIColor colorWithWhite:0.04 alpha:1.0];
    self.textView.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:1.0];
    self.textView.font = [UIFont fontWithName:@"Menlo" size:10.5];
    self.textView.editable = NO;
    self.textView.layer.cornerRadius = 6;
    [self.panel addSubview:self.textView];
}

- (UIButton *)makeBtn:(NSString *)title color:(UIColor *)color frame:(CGRect)frame action:(SEL)action {
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
    [self showNetLogs];
}

- (void)closePanel {
    self.panel.hidden = YES;
    self.bubbleBtn.hidden = NO;
}

- (void)showNetLogs {
    NSArray *logs = [UniversalNetworkLogger getLogs];
    NSMutableString *res = [NSMutableString stringWithFormat:@"=== GÓI TIN BẮT ĐƯỢC (%lu) ===\n\n", (unsigned long)logs.count];
    for (NSString *log in logs) [res appendFormat:@"%@\n---\n", log];
    if (logs.count == 0) [res appendString:@"Chưa có gói tin nào. Đang lắng nghe REST, WS và Notifications..."];
    
    self.cachedLog = res;
    self.textView.text = res;
    self.statusLabel.text = [NSString stringWithFormat:@"Đã bắt %lu gói tin.", (unsigned long)logs.count];
}

- (void)runOCR {
    self.statusLabel.text = @"Đang chụp và quét OCR màn hình...";
    self.panel.alpha = 0.0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [AdvancedInspectionEngine performScreenOCR:^(NSString *ocrResult) {
            self.panel.alpha = 1.0;
            self.cachedLog = ocrResult;
            self.textView.text = ocrResult;
            self.statusLabel.text = @"Đã quét xong OCR.";
        }];
    });
}

- (void)runDump {
    self.statusLabel.text = @"Đang dump bộ nhớ RAM Controller...";
    NSString *dump = [AdvancedInspectionEngine performDeepRuntimeDump];
    self.cachedLog = dump;
    self.textView.text = dump;
    self.statusLabel.text = @"Đã dump RAM và lưu vào file.";
}

- (void)clearLogs {
    [UniversalNetworkLogger clear];
    [FileLogger clearLogFile];
    self.cachedLog = @"";
    self.textView.text = @"Đã xóa toàn bộ logs.";
    self.statusLabel.text = @"Logs cleared.";
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        self.textView.text = self.cachedLog;
        return;
    }
    NSMutableString *filtered = [NSMutableString string];
    for (NSString *line in [self.cachedLog componentsSeparatedByString:@"\n"]) {
        if ([line localizedCaseInsensitiveContainsString:searchText]) {
            [filtered appendFormat:@"%@\n", line];
        }
    }
    self.textView.text = filtered;
}

@end

#pragma mark - 5. ENTRY POINT

@interface InspectorOverlayWindow : UIWindow
@end

@implementation InspectorOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *h = [super hitTest:point withEvent:event];
    if (h == self.rootViewController.view) return nil;
    return h;
}
@end

static InspectorOverlayWindow *gWindow = nil;

__attribute__((constructor))
static void dylib_main(void) {
    [UniversalNetworkLogger startLogging];

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
                    if (scene) gWindow = [[InspectorOverlayWindow alloc] initWithWindowScene:scene];
                }
                if (!gWindow) gWindow = [[InspectorOverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

                gWindow.windowLevel = UIWindowLevelAlert + 1000.0;
                gWindow.backgroundColor = [UIColor clearColor];
                MultiToolInspectorVC *vc = [[MultiToolInspectorVC alloc] init];
                gWindow.rootViewController = vc;
                gWindow.hidden = NO;
            });
        });
    }];
}
