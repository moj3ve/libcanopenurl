#import <UIKit/UIKit.h>
#import <HBLog.h>
#import "LCCanOpenURL.h"
#define ROCKETBOOTSTRAP_LOAD_DYNAMIC
#import "../LightMessaging/LightMessaging.h"

// LightMessaging define {{{
static LMConnection connection = {
    MACH_PORT_NULL,
    "libcanopenurl.datasource"
};
enum {
    LCCanOpenURLMessage,
    LCBatchCanOpenURLMessage
};
// }}}
// LightMessaging functions. {{{
static void processMessage(SInt32 messageId, mach_port_t replyPort, CFDataRef data)
{
    switch (messageId) {
        case LCCanOpenURLMessage: {
            HBLogDebug(@"LCcanOpenURL, App -> SpringBoard return NSNumber.");
            if (!data)
                break;
            NSString *URLString = [NSPropertyListSerialization propertyListWithData:(NSData * _Nonnull)data options:0 format:NULL error:NULL];
            if (![URLString isKindOfClass:[NSString class]])
                break;
            NSURL *URL = [NSURL URLWithString:URLString];
            BOOL result = [[UIApplication sharedApplication] canOpenURL:URL];
            LMSendPropertyListReply(replyPort, result ? @YES : @NO);
            return;
        }
        case LCBatchCanOpenURLMessage: {
            HBLogDebug(@"LCBatchCanOpenURLMessage, App -> SpringBoard return [NSNumber].");
            if (!data)
                break;
            NSArray<NSString *> *URLStrings = [NSPropertyListSerialization propertyListWithData:(NSData * _Nonnull)data options:0 format:NULL error:NULL];
            if (![URLStrings isKindOfClass:[NSArray class]])
                break;
            NSMutableArray *results = [[@[] mutableCopy] autorelease];
            for (NSString *url in URLStrings) {
                if (![url isKindOfClass:[NSString class]])
                    break;
                NSURL *URL = [NSURL URLWithString:url];
                BOOL result = [[UIApplication sharedApplication] canOpenURL:URL];
                [results addObject:[NSNumber numberWithBool:result]];
            }
            LMSendPropertyListReply(replyPort, results);
            return;
        }
    }
    LMSendReply(replyPort, NULL, 0);
}

static void machPortCallback(CFMachPortRef port, void *bytes, CFIndex size, void *info)
{
    LMMessage *request = (LMMessage *)bytes;
    if (size < sizeof(LMMessage)) {
        LMSendReply(request->head.msgh_remote_port, NULL, 0);
        LMResponseBufferFree((LMResponseBuffer *)bytes);
        return;
    }
    // Send Response
    const void *data = LMMessageGetData(request);
    size_t length = LMMessageGetDataLength(request);
    mach_port_t replyPort = request->head.msgh_remote_port;
    CFDataRef cfdata = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, (const UInt8 *)data ?: (const UInt8 *)&data, length, kCFAllocatorNull);
    processMessage(request->head.msgh_id, replyPort, cfdata);
    if (cfdata)
        CFRelease(cfdata);
    LMResponseBufferFree((LMResponseBuffer *)bytes);
}
// }}}
@implementation LCCanOpenURL  // {{{
static LCCanOpenURL *sharedInstance;
+ (LCCanOpenURL *)sharedInstance
{
    return sharedInstance;
}

// for Apps init.
+ (void)initialize
{
    if (self == [LCCanOpenURL class] && !%c(SBIconModel)) {
        sharedInstance = [[self alloc] init];
    }
}

// for SpringBoard init.
- (id)init
{
    if ((self = [super init])) {
        if (sharedInstance) {
            [self release];
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Only one instance of sharedInstance is permitted at a time! Use [LCCanOpenURL sharedInstance] instead." userInfo:nil];
        }
    }
    return self;
}

static BOOL CanOpenURL(id URL)
{
    HBLogDebug(@"URL = %@", URL);
    if ([URL isKindOfClass:[NSURL class]]) {
        URL = ((NSURL *)URL).absoluteString;
    }
    if (kCFCoreFoundationVersionNumber < 1200 || %c(SBIconModel)) {
        return [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:URL]];
    }
    LMResponseBuffer buffer;
    if (LMConnectionSendTwoWayPropertyList(&connection, LCCanOpenURLMessage, URL, &buffer)) {
        return NO;
    }
    id result = LMResponseConsumePropertyList(&buffer);
    return [result isKindOfClass:[NSNumber class]] ? [result boolValue] : NO;
}
static NSArray<NSNumber *> * _Nonnull BatchCanOpenURL(NSArray *URLs)
{
    if (![URLs isKindOfClass:[NSArray class]]) {
        return @[];
    }
    if (kCFCoreFoundationVersionNumber < 1200 || %c(SBIconModel)) {
        NSMutableArray *results = [[@[] mutableCopy] autorelease];
        for (NSString *url in URLs) {
            NSURL *URL = [NSURL URLWithString:url];
            BOOL result = [[UIApplication sharedApplication] canOpenURL:URL];
            [results addObject:[NSNumber numberWithBool:result]];
        }
        return results;
    }
    LMResponseBuffer buffer;
    if (LMConnectionSendTwoWayPropertyList(&connection, LCBatchCanOpenURLMessage, URLs, &buffer)) {
        return @[];
    }
    id result = LMResponseConsumePropertyList(&buffer);
    return result;
}

- (BOOL)canOpenURL:(NSURL * _Nonnull)URL
{
    return CanOpenURL(URL);
}

- (BOOL)canOpenURLString:(NSString * _Nonnull)URLString
{
    return CanOpenURL(URLString);
}
- (NSArray<NSNumber *> * _Nonnull)batchCanOpenURL:(NSArray<NSString *>*  _Nonnull)URLs
{
    return BatchCanOpenURL(URLs);
}
@end  // }}}
@interface LCCanOpenURLImpl : LCCanOpenURL  // {{{
@end
@implementation LCCanOpenURLImpl
- (id)init
{
    if ((self = [super init])) {
        kern_return_t err = LMStartService(connection.serverName, CFRunLoopGetCurrent(), machPortCallback);
        if (err) {
            NSLog(@"libcanopenurl: Unable to register mach server with error %x", err);
        }
    }
    return self;
}
@end  // }}}

%ctor {
    @autoreleasepool {
        //NSString *bundleIdentifier = [NSBundle mainBundle].bundleIdentifier;
        if (kCFCoreFoundationVersionNumber >= 1200 && %c(SBIconModel)) {
            sharedInstance = [[LCCanOpenURLImpl alloc] init];
        }
    }
}
