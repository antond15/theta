#import "Include.h"
#import "Include/ThetaTweakCommon.h"
#import <objc/runtime.h>
#import <objc/message.h>

/* Drops seen receipts at the network layer: story `/media/seen/` (Mark Seen on This Device Only) and the
   Instants seen mutation (Instants Ghost). Only requests to Instagram/Facebook hosts on these exact paths or
   GraphQL names are touched. The feature hooks in StorySeenLocalOnly.m and SaveInstants.m stop most receipts
   earlier; this is the backstop. Installed from the constructor. */

BOOL THStorySeenReceiptsBlocked(void);
BOOL THInstantsSeenBlocked(void);

typedef NS_ENUM(NSInteger, THSeenKind) {
    THSeenKindNone = 0,
    THSeenKindStory,
    THSeenKindInstant,
};

static const NSUInteger kTHSeenBodyScanLimit = 16u * 1024u;
static NSString *const kTHInstantSeenFriendlyName = @"IGQuickSnapUpdateSeenStateMutation";
static NSString *const kTHInstantSeenRootField = @"xdt_mark_quick_snap_seen";

static BOOL THSeenHostIsMeta(NSURL *url) {
    NSString *scheme = url.scheme.lowercaseString;
    if (scheme.length && ![scheme isEqualToString:@"https"] && ![scheme isEqualToString:@"http"]) return NO;
    NSString *host = url.host.lowercaseString;
    // A relative URL is resolved against Instagram's API base.
    if (!host.length) return YES;
    return [host isEqualToString:@"instagram.com"] || [host hasSuffix:@".instagram.com"]
        || [host isEqualToString:@"facebook.com"] || [host hasSuffix:@".facebook.com"];
}

static BOOL THSeenPathIsGraphQL(NSString *lowerPath) {
    return [lowerPath hasSuffix:@"/graphql/query"] || [lowerPath hasSuffix:@"/graphql_www"];
}

static BOOL THSeenHeaderNamesInstant(NSString *value) {
    if (![value isKindOfClass:[NSString class]] || !value.length) return NO;
    return [value rangeOfString:kTHInstantSeenFriendlyName options:NSCaseInsensitiveSearch].location != NSNotFound
        || [value rangeOfString:kTHInstantSeenRootField options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static id THSeenHeader(NSDictionary *headers, NSString *name) {
    if (![headers isKindOfClass:[NSDictionary class]]) return nil;
    id v = headers[name];
    if (v) return v;
    for (id key in headers) {
        if ([key isKindOfClass:[NSString class]] && [(NSString *)key caseInsensitiveCompare:name] == NSOrderedSame)
            return headers[key];
    }
    return nil;
}

static BOOL THSeenBodyNamesInstant(NSData *body) {
    if (![body isKindOfClass:[NSData class]] || !body.length || body.length > kTHSeenBodyScanLimit) return NO;
    for (NSString *needle in @[ kTHInstantSeenFriendlyName, kTHInstantSeenRootField ]) {
        NSData *n = [needle dataUsingEncoding:NSUTF8StringEncoding];
        if ([body rangeOfData:n options:0 range:NSMakeRange(0, body.length)].location != NSNotFound) return YES;
    }
    return NO;
}

#if THETA_DEBUG
/* Debug builds: Instagram-host requests that mention "seen" but match nothing, so a new seen path on a
   later build shows up in the log. Digits are masked; the query is never logged. */
static NSString *THSeenMaskDigits(NSString *s) {
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ re = [NSRegularExpression regularExpressionWithPattern:@"[0-9]+" options:0 error:nil]; });
    return [re stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"#"];
}

static void THSeenLogNearMiss(NSString *layer, NSURL *url, NSString *lowerPath, NSDictionary *headers) {
    NSString *friendly = THSeenHeader(headers, @"X-FB-Friendly-Name");
    NSString *root = THSeenHeader(headers, @"X-Root-Field-Name");
    BOOL namedSeen = ([friendly isKindOfClass:[NSString class]] && [friendly rangeOfString:@"seen" options:NSCaseInsensitiveSearch].location != NSNotFound)
        || ([root isKindOfClass:[NSString class]] && [root rangeOfString:@"seen" options:NSCaseInsensitiveSearch].location != NSNotFound);
    if (!namedSeen && [lowerPath rangeOfString:@"seen"].location == NSNotFound) return;
    THDebugLog(@"[Theta] seen near-miss: %@ %@%@ name=%@ root=%@", layer, url.host ?: @"", THSeenMaskDigits(url.path ?: @""),
               [friendly isKindOfClass:[NSString class]] ? friendly : @"-", [root isKindOfClass:[NSString class]] ? root : @"-");
}
#endif

/* `body` is read only on the GraphQL endpoints, and only up to kTHSeenBodyScanLimit. Pass nil where the
   body isn't available as data (Tigon). */
static THSeenKind THSeenClassify(NSString *layer, NSURL *url, NSDictionary *headers, NSData *body) {
    if (![url isKindOfClass:[NSURL class]] || !THSeenHostIsMeta(url)) return THSeenKindNone;
    NSString *lowerPath = url.path.lowercaseString ?: @"";
    // -[NSURL path] drops the trailing slash of /api/v1/media/seen/.
    if ([lowerPath hasSuffix:@"/media/seen"]) return THSeenKindStory;
    if (THSeenHeaderNamesInstant(THSeenHeader(headers, @"X-FB-Friendly-Name"))
        || THSeenHeaderNamesInstant(THSeenHeader(headers, @"X-Root-Field-Name")))
        return THSeenKindInstant;
    if (THSeenPathIsGraphQL(lowerPath) && THSeenBodyNamesInstant(body)) return THSeenKindInstant;
#if THETA_DEBUG
    THSeenLogNearMiss(layer, url, lowerPath, headers);
#endif
    return THSeenKindNone;
}

/* Classifies the request; for a seen receipt, logs it and says whether it must be dropped now. */
static BOOL THSeenShouldDrop(NSString *layer, NSURL *url, NSDictionary *headers, NSData *body) {
    THSeenKind kind = THSeenClassify(layer, url, headers, body);
    if (kind == THSeenKindNone) return NO;
    BOOL drop = kind == THSeenKindStory ? THStorySeenReceiptsBlocked() : THInstantsSeenBlocked();
    THDebugLog(@"[Theta] seen request: %@ %@ %@%@ %@ (foreground hooks %s)", layer, kind == THSeenKindStory ? @"story" : @"instant",
               url.host ?: @"", url.path ?: @"", drop ? @"dropped" : @"sent", hooksInitialized ? "installed" : "pending");
    return drop;
}

static BOOL THSeenShouldDropURLRequest(NSURLRequest *req, NSData *uploadBody) {
    if (![req isKindOfClass:[NSURLRequest class]]) return NO;
    // Cheap exit before touching headers or body: nothing to block with both settings off.
    if (!THStorySeenReceiptsBlocked() && !THInstantsSeenBlocked()) return NO;
    NSData *body = uploadBody ?: req.HTTPBody;
    return THSeenShouldDrop(@"nsurlsession", req.URL, req.allHTTPHeaderFields, body);
}

#pragma mark - NSURLSession

static NSURLRequest *THSeenDummyRequest(void) {
    return [NSURLRequest requestWithURL:[NSURL URLWithString:@"data:text/plain,"]];
}

static void THSeenFailCompletion(void (^comp)(NSData *, NSURLResponse *, NSError *)) {
    if (!comp) return;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        comp(nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
    });
}

typedef NSURLSessionDataTask *(*THDataTaskCompIMP)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *));
typedef NSURLSessionDataTask *(*THDataTaskIMP)(id, SEL, NSURLRequest *);
typedef NSURLSessionUploadTask *(*THUploadTaskIMP)(id, SEL, NSURLRequest *, NSData *, void (^)(NSData *, NSURLResponse *, NSError *));

static NSURLSessionDataTask *THSeenDataTaskComp(THDataTaskCompIMP orig, id self, SEL _cmd, NSURLRequest *req,
                                                void (^comp)(NSData *, NSURLResponse *, NSError *)) {
    if (THSeenShouldDropURLRequest(req, nil)) {
        THSeenFailCompletion(comp);
        NSURLSessionDataTask *task = orig(self, _cmd, THSeenDummyRequest(), nil);
        [task cancel];
        return task;
    }
    return orig(self, _cmd, req, comp);
}

static NSURLSessionDataTask *THSeenDataTask(THDataTaskIMP orig, id self, SEL _cmd, NSURLRequest *req) {
    if (THSeenShouldDropURLRequest(req, nil)) {
        NSURLSessionDataTask *task = orig(self, _cmd, THSeenDummyRequest());
        [task cancel];
        return task;
    }
    return orig(self, _cmd, req);
}

static NSURLSessionUploadTask *THSeenUploadTask(THUploadTaskIMP orig, id self, SEL _cmd, NSURLRequest *req, NSData *data,
                                                void (^comp)(NSData *, NSURLResponse *, NSError *)) {
    if (THSeenShouldDropURLRequest(req, data)) {
        THSeenFailCompletion(comp);
        NSURLSessionUploadTask *task = orig(self, _cmd, THSeenDummyRequest(), [NSData data], nil);
        [task cancel];
        return task;
    }
    return orig(self, _cmd, req, data, comp);
}

/* One original per class: __NSURLSessionLocal is hooked as well when it implements the method itself. */
static THDataTaskCompIMP orig_seenDataTaskComp, orig_seenDataTaskCompLocal;
static THDataTaskIMP orig_seenDataTask, orig_seenDataTaskLocal;
static THUploadTaskIMP orig_seenUploadTask, orig_seenUploadTaskLocal;

static NSURLSessionDataTask *hook_seenDataTaskComp(id self, SEL _cmd, NSURLRequest *req, void (^comp)(NSData *, NSURLResponse *, NSError *)) {
    return THSeenDataTaskComp(orig_seenDataTaskComp, self, _cmd, req, comp);
}
static NSURLSessionDataTask *hook_seenDataTaskCompLocal(id self, SEL _cmd, NSURLRequest *req, void (^comp)(NSData *, NSURLResponse *, NSError *)) {
    return THSeenDataTaskComp(orig_seenDataTaskCompLocal, self, _cmd, req, comp);
}
static NSURLSessionDataTask *hook_seenDataTask(id self, SEL _cmd, NSURLRequest *req) {
    return THSeenDataTask(orig_seenDataTask, self, _cmd, req);
}
static NSURLSessionDataTask *hook_seenDataTaskLocal(id self, SEL _cmd, NSURLRequest *req) {
    return THSeenDataTask(orig_seenDataTaskLocal, self, _cmd, req);
}
static NSURLSessionUploadTask *hook_seenUploadTask(id self, SEL _cmd, NSURLRequest *req, NSData *data, void (^comp)(NSData *, NSURLResponse *, NSError *)) {
    return THSeenUploadTask(orig_seenUploadTask, self, _cmd, req, data, comp);
}
static NSURLSessionUploadTask *hook_seenUploadTaskLocal(id self, SEL _cmd, NSURLRequest *req, NSData *data, void (^comp)(NSData *, NSURLResponse *, NSError *)) {
    return THSeenUploadTask(orig_seenUploadTaskLocal, self, _cmd, req, data, comp);
}

static BOOL THSeenClassDefinesMethod(Class cls, SEL sel) {
    unsigned count = 0;
    Method *list = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned i = 0; i < count && !found; i++)
        found = method_getName(list[i]) == sel;
    free(list);
    return found;
}

#pragma mark - Tigon

/* IGURLRequest reaches Tigon here; its body is an IGHTTPBody, not data, so only the URL and headers are
   matched. A dropped request fails the way Tigon fails one it won't start. */
static id (*orig_seenTigonStartRequest)(id, SEL, id, id, id);
static id hook_seenTigonStartRequest(id self, SEL _cmd, id req, id policy, id callbacks) {
    if (THStorySeenReceiptsBlocked() || THInstantsSeenBlocked()) {
        NSURL *url = [req respondsToSelector:@selector(URL)] ? ((id (*)(id, SEL))objc_msgSend)(req, @selector(URL)) : nil;
        NSDictionary *headers = [req respondsToSelector:@selector(allHTTPHeaderFields)]
            ? ((id (*)(id, SEL))objc_msgSend)(req, @selector(allHTTPHeaderFields)) : nil;
        if (THSeenShouldDrop(@"tigon", url, headers, nil)) {
            Class summaryCls = objc_getClass("IGNetworkRequestSummary");
            Class taskCls = objc_getClass("IGCompletedRequestTask");
            if (summaryCls && taskCls && [callbacks respondsToSelector:@selector(failure:summary:)]) {
                NSError *err = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil];
                ((void (*)(id, SEL, id, id))objc_msgSend)(callbacks, @selector(failure:summary:), err, [summaryCls new]);
                return [taskCls new];
            }
            THDebugLog(@"[Theta] seen request: tigon could not fail the request, it was sent");
        }
    }
    return orig_seenTigonStartRequest(self, _cmd, req, policy, callbacks);
}

void THRegisterSeenRequestBlockHooks(void) {
    Class session = [NSURLSession class];
    NullHookMessageIfPresent(session, @selector(dataTaskWithRequest:completionHandler:), (void *)hook_seenDataTaskComp, &orig_seenDataTaskComp);
    NullHookMessageIfPresent(session, @selector(dataTaskWithRequest:), (void *)hook_seenDataTask, &orig_seenDataTask);
    NullHookMessageIfPresent(session, @selector(uploadTaskWithRequest:fromData:completionHandler:), (void *)hook_seenUploadTask, &orig_seenUploadTask);

    Class local = objc_getClass("__NSURLSessionLocal");
    if (local && local != session) {
        if (THSeenClassDefinesMethod(local, @selector(dataTaskWithRequest:completionHandler:)))
            NullHookMessageIfPresent(local, @selector(dataTaskWithRequest:completionHandler:), (void *)hook_seenDataTaskCompLocal, &orig_seenDataTaskCompLocal);
        if (THSeenClassDefinesMethod(local, @selector(dataTaskWithRequest:)))
            NullHookMessageIfPresent(local, @selector(dataTaskWithRequest:), (void *)hook_seenDataTaskLocal, &orig_seenDataTaskLocal);
        if (THSeenClassDefinesMethod(local, @selector(uploadTaskWithRequest:fromData:completionHandler:)))
            NullHookMessageIfPresent(local, @selector(uploadTaskWithRequest:fromData:completionHandler:), (void *)hook_seenUploadTaskLocal, &orig_seenUploadTaskLocal);
    }

    NullHookMessageIfPresent(objc_getClass("IGTigonNetworkLayer"), @selector(startRequest:policy:callbacks:),
                             (void *)hook_seenTigonStartRequest, &orig_seenTigonStartRequest);
}
