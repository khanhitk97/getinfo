#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@interface NetworkLogger : NSObject
+ (void)startLogging;
@end

@implementation NetworkLogger

+ (void)startLogging {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"__NSCFURLSessionConnection");
        if (!cls) cls = NSClassFromString(@"NSURLSessionConnection");
        
        // Swizzle hàm nhận dữ liệu mạng từ Server
        SEL originalSelector = NSSelectorFromString(@"_didReceiveData:");
        SEL swizzledSelector = @selector(custom_didReceiveData:);
        
        Method origMethod = class_getInstanceMethod(cls, originalSelector);
        Method swizMethod = class_getInstanceMethod([self class], swizzledSelector);
        
        if (origMethod && swizMethod) {
            method_exchangeImplementations(origMethod, swizMethod);
        }
    });
}

- (void)custom_didReceiveData:(NSData *)data {
    // In raw payload từ server về log
    if (data.length > 0) {
        NSError *err = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        if (json) {
            NSLog(@"[API Interceptor Response JSON] %@", json);
        }
    }
    
    // Gọi lại hàm gốc để app hoạt động bình thường
    [self custom_didReceiveData:data];
}

@end
