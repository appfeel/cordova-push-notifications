//
//  AppDelegate+notification.m
//  pushtest
//
//  Created by Robert Easterday on 10/26/12.
//
//

#import "AppDelegate+notification.h"
#import "PushPlugin.h"
#import <objc/runtime.h>

static char launchNotificationKey;

@implementation AppDelegate (notification)

- (id) getCommandInstance:(NSString*)className
{
  return [self.viewController getCommandInstance:className];
}

// its dangerous to override a method from within a category.
// Instead we will use method swizzling. we set this up in the load call.
+ (void)load
{
  Method original, swizzled;
  
  original = class_getInstanceMethod(self, @selector(init));
  swizzled = class_getInstanceMethod(self, @selector(swizzled_init));
  method_exchangeImplementations(original, swizzled);
}

- (AppDelegate *)swizzled_init
{
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(createNotificationChecker:)
                                               name:UIApplicationDidFinishLaunchingNotification
                                             object:nil];
  
  [[NSNotificationCenter defaultCenter]addObserver:self
                                          selector:@selector(onApplicationDidBecomeActive:)
                                              name:UIApplicationDidBecomeActiveNotification
                                            object:nil];

  // This actually calls the original init method over in AppDelegate. Equivilent to calling super
  // on an overrided method, this is not recursive, although it appears that way. neat huh?
  return [self swizzled_init];
}

// This code will be called immediately after application:didFinishLaunchingWithOptions:. We need
// to process notifications in cold-start situations
- (void)createNotificationChecker:(NSNotification *)notification
{
  if (notification)
  {
    NSDictionary *launchOptions = [notification userInfo];
    if (launchOptions)
      self.launchNotification = [launchOptions objectForKey: @"UIApplicationLaunchOptionsRemoteNotificationKey"];
  }
}

- (void)onApplicationDidBecomeActive:(NSNotification *)notification
{
  NSLog(@"active");
  
  UIApplication *application = notification.object;

  application.applicationIconBadgeNumber = 0;
  
  if (self.launchNotification) {
    PushPlugin *pushHandler = [self getCommandInstance:@"PushPlugin"];
    
    pushHandler.notificationMessage = self.launchNotification;
    self.launchNotification = nil;
    [pushHandler performSelectorOnMainThread:@selector(notificationReceived) withObject:pushHandler waitUntilDone:NO];
  }
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
  PushPlugin *pushHandler = [self getCommandInstance:@"PushPlugin"];
  [pushHandler didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
  PushPlugin *pushHandler = [self getCommandInstance:@"PushPlugin"];
  [pushHandler didFailToRegisterForRemoteNotificationsWithError:error];
}

// this method is invoked when:
// - a regular notification is tapped
// - an interactive notification is tapped, but not one of its buttons
/*- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
  NSLog(@"didReceiveNotification");
  
  if (application.applicationState == UIApplicationStateActive) {
    PushPlugin *pushHandler = [self getCommandInstance:@"PushPlugin"];
    pushHandler.notificationMessage = userInfo;
    pushHandler.isInline = YES;
    [pushHandler notificationReceived];
  } else {
    //save it for later
    self.launchNotification = userInfo;
  }
}*/

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void(^)(UIBackgroundFetchResult result))completionHandler
{
    NSLog(@"didReceiveRemoteNotification with fetchCompletionHandler");  

    if (application.applicationState == UIApplicationStateActive) {
        PushPlugin *pushHandler = [self getCommandInstance:@"PushPlugin"];
        pushHandler.notificationMessage = userInfo;
        pushHandler.isInline = YES;
        [pushHandler notificationReceived];
        completionHandler(UIBackgroundFetchResultNewData);
    } 
    else {
        long silent = 0;
        id aps = [userInfo objectForKey:@"aps"];
        id contentAvailable = [aps objectForKey:@"content-available"];
        if ([contentAvailable isKindOfClass:[NSString class]] && [contentAvailable isEqualToString:@"1"]) {
            silent = 1;
        } else if ([contentAvailable isKindOfClass:[NSNumber class]]) {
            silent = [contentAvailable integerValue];
        }
        
        if (silent == 1) {
            void (^safeHandler)(UIBackgroundFetchResult) = ^(UIBackgroundFetchResult result){
            dispatch_async(dispatch_get_main_queue(), ^{
                completionHandler(result);
                });
            };

            NSMutableDictionary *mutableNotification = [userInfo mutableCopy];
            NSMutableDictionary* params = [NSMutableDictionary dictionaryWithCapacity:2];
            [params setObject:safeHandler forKey:@"silentNotificationHandler"];
            PushPlugin *pushHandler = [self getCommandInstance:@"PushPlugin"];    
            pushHandler.notificationMessage = mutableNotification;    
            pushHandler.params= params;  
            [pushHandler notificationReceived];
        } else {
            self.launchNotification = userInfo;
            completionHandler(UIBackgroundFetchResultNewData);
        }
    }
    
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000
// this method is invoked when:
// - one of the buttons of an interactive notification is tapped
// see https://developer.apple.com/library/mac/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/Chapters/IPhoneOSClientImp.html#//apple_ref/doc/uid/TP40008194-CH103-SW1
- (void)application:(UIApplication *) application handleActionWithIdentifier: (NSString *) identifier forRemoteNotification: (NSDictionary *) notification withResponseInfo:(NSDictionary *)responseInfo completionHandler: (void (^)()) completionHandler {

  NSMutableDictionary *mutableNotification = [notification mutableCopy];
  [mutableNotification setObject:identifier forKey:@"identifier"];  
    
  if(responseInfo != nil){
    NSString *textInput = [[NSString alloc]initWithFormat:@"%@",[responseInfo objectForKey:@"UIUserNotificationActionResponseTypedTextKey"]];
    [mutableNotification setValue:textInput forKey:@"textInput"];
  }
  
  NSLog(@"handleActionWithIdentifier");
  if (application.applicationState == UIApplicationStateActive) {
    PushPlugin *pushHandler = [self getCommandInstance:@"PushPlugin"];
    pushHandler.notificationMessage = mutableNotification;
    pushHandler.isInline = YES;
    [pushHandler notificationReceived];
  } else {
    void (^safeHandler)() = ^(void){
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler();
        });
    };
    NSMutableDictionary* params = [NSMutableDictionary dictionaryWithCapacity:2];
    [params setObject:safeHandler forKey:@"remoteNotificationHandler"];
    PushPlugin *pushHandler = [self getCommandInstance:@"PushPlugin"];    
    pushHandler.notificationMessage = mutableNotification;    
    pushHandler.params= params;  
    [pushHandler notificationReceived];
  }
}
#elif __IPHONE_OS_VERSION_MAX_ALLOWED >= 80000
// this method is invoked when:
// - one of the buttons of an interactive notification is tapped
// see https://developer.apple.com/library/mac/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/Chapters/IPhoneOSClientImp.html#//apple_ref/doc/uid/TP40008194-CH103-SW1
- (void)application:(UIApplication *) application handleActionWithIdentifier: (NSString *) identifier forRemoteNotification: (NSDictionary *) notification completionHandler: (void (^)()) completionHandler {

  NSMutableDictionary *mutableNotification = [notification mutableCopy];
  [mutableNotification setObject:identifier forKey:@"identifier"];  
    
  NSLog(@"handleActionWithIdentifier");
  if (application.applicationState == UIApplicationStateActive) {
    PushPlugin *pushHandler = [self getCommandInstance:@"PushPlugin"];
    pushHandler.notificationMessage = mutableNotification;
    pushHandler.isInline = YES;
    [pushHandler notificationReceived];
  } else {
    void (^safeHandler)() = ^(void){
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler();
        });
    };
    NSMutableDictionary* params = [NSMutableDictionary dictionaryWithCapacity:2];
    [params setObject:safeHandler forKey:@"remoteNotificationHandler"];
    PushPlugin *pushHandler = [self getCommandInstance:@"PushPlugin"];    
    pushHandler.notificationMessage = mutableNotification;    
    pushHandler.params= params;  
    [pushHandler notificationReceived];
  }
}
#endif


// The accessors use an Associative Reference since you can't define a iVar in a category
// http://developer.apple.com/library/ios/#documentation/cocoa/conceptual/objectivec/Chapters/ocAssociativeReferences.html
- (NSMutableArray *)launchNotification
{
  return objc_getAssociatedObject(self, &launchNotificationKey);
}

- (void)setLaunchNotification:(NSDictionary *)aDictionary
{
  objc_setAssociatedObject(self, &launchNotificationKey, aDictionary, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)dealloc
{
  self.launchNotification = nil; // clear the association and release the object
}

@end