#import "Include/ThetaTweakCommon.h"
#import <objc/runtime.h>
#import <objc/message.h>

// Common tracking parameters used by Instagram and advertising networks
static NSSet *THTrackingParamSet(void) {
    static NSSet *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [NSSet setWithArray:@[
            @"utm_source", @"utm_medium", @"utm_campaign", @"utm_content",
            @"utm_term", @"utm_id", @"fbclid", @"igshid", @"igsh",
            @"ig_rid", @"campaign_id", @"ad_id", @"aem",
            @"gclid", @"ttclid", @"mc_eid"
        ]];
    });
    return s;
}

// Meta link-shim hosts that wrap the real target in ?u=
static BOOL THIsLinkShimHost(NSString *host) {
    static NSSet *hosts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        hosts = [NSSet setWithArray:@[@"l.instagram.com", @"lm.instagram.com", @"l.facebook.com"]];
    });
    return host && [hosts containsObject:host.lowercaseString];
}

// Unwrap link-shim redirects and strip tracking params
static NSURL *THCleanBrowserURL(NSURL *url) {
    if (!url) return url;

    NSString *urlStr = url.absoluteString;

    // Unwrap l.instagram.com/?u=ENCODED_URL redirect
    if (THIsLinkShimHost(url.host)) {
        NSURLComponents *comps = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        for (NSURLQueryItem *q in comps.queryItems) {
            // queryItems values are already percent-decoded.
            if ([q.name isEqualToString:@"u"] && q.value.length) {
                urlStr = q.value;
                break;
            }
        }
    }

    if (!ENABLED(THLinksStripTracking)) {
        NSURL *result = [NSURL URLWithString:urlStr];
        return result ?: url;
    }

    NSURLComponents *comps = [NSURLComponents componentsWithString:urlStr];
    // Work on the encoded items and rebuild only when a parameter was dropped: decoding and re-encoding
    // the query turns %2B into + and rewrites characters such as ; in values Theta doesn't touch.
    NSArray<NSURLQueryItem *> *items = comps.percentEncodedQueryItems;
    if (items.count) {
        NSSet *tracking = THTrackingParamSet();
        NSMutableArray *clean = [NSMutableArray array];
        for (NSURLQueryItem *q in items) {
            if (![tracking containsObject:q.name.stringByRemovingPercentEncoding ?: q.name]) [clean addObject:q];
        }
        if (clean.count != items.count)
            comps.percentEncodedQueryItems = clean.count ? clean : nil;
    }

    NSURL *result = comps.URL;
    return result ?: url;
}

static BOOL THIsWebURL(NSURL *url) {
    NSString *scheme = url.scheme.lowercaseString;
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

// Rewrite an object's URL request ivar to the cleaned URL, keeping the request's other fields.
static void THStripTrackingInRequestIvar(id obj, const char *name) {
    if (!obj || !ENABLED(THLinksStripTracking)) return;
    Ivar ivar = class_getInstanceVariable([obj class], name);
    if (!ivar) return;
    id req = object_getIvar(obj, ivar);
    if (![req isKindOfClass:[NSURLRequest class]]) return;
    NSURL *url = [(NSURLRequest *)req URL];
    NSURL *cleaned = THCleanBrowserURL(url);
    if (!url || !THIsWebURL(cleaned) || [cleaned isEqual:url]) return;
    NSMutableURLRequest *clean = [(NSURLRequest *)req mutableCopy];
    clean.URL = cleaned;
    object_setIvar(obj, ivar, [clean copy]);
    THDebugLog(@"[Theta] links: stripped %s on %@", name, NSStringFromClass([obj class]));
}

// Instagram 451 builds every in-app browser session through IGBrowserSessionBuilder and sends -build
// and -[IGBrowserViewController initWithBrowserSession:] through objc_msgSend. The browser reads the
// request when it is created, so the old swap in -viewWillAppear: came too late.
static id (*orig_browserSessionBuild)(id self, SEL _cmd);
static id hook_browserSessionBuild(id self, SEL _cmd) {
    @try { THStripTrackingInRequestIvar(self, "_urlRequest"); } @catch (__unused NSException *e) {}
    return orig_browserSessionBuild(self, _cmd);
}

static id (*orig_browserVCInitWithSession)(id self, SEL _cmd, id session);
static id hook_browserVCInitWithSession(id self, SEL _cmd, id session) {
    @try { THStripTrackingInRequestIvar(session, "_urlRequest"); } @catch (__unused NSException *e) {}
    return orig_browserVCInitWithSession(self, _cmd, session);
}

static void (*orig_viewWillAppear_Browser)(id self, SEL _cmd, BOOL animated);
static void hook_viewWillAppear_Browser(id self, SEL _cmd, BOOL animated) {
    @try {
        id session = ((id(*)(id,SEL))objc_msgSend)(self, @selector(browserSession));
        Ivar urlIvar = session ? class_getInstanceVariable([session class], "_urlRequest") : nil;
        NSURLRequest *req = urlIvar ? object_getIvar(session, urlIvar) : nil;
        NSURL *url = req.URL;

        // Only web links leave the app; anything else stays with Instagram's own handling.
        if (url && ENABLED(THLinksOpenExternally)) {
            NSURL *cleaned = THCleanBrowserURL(url);
            if (THIsWebURL(cleaned)) {
                [[UIApplication sharedApplication] openURL:cleaned options:@{} completionHandler:nil];
                [(UIViewController *)self dismissViewControllerAnimated:NO completion:nil];
                return;
            }
        }

        // The in-app browser strip runs earlier, at the builder and the browser's init (below).
    } @catch (__unused NSException *e) {}

    orig_viewWillAppear_Browser(self, _cmd, animated);
}

void THRegisterExternalBrowserHooks(void) {
    Class cls = objc_getClass("IGBrowserNavigationController");
    NullHookMessageEx(cls, @selector(viewWillAppear:), (void *)hook_viewWillAppear_Browser, &orig_viewWillAppear_Browser);
    NullHookMessageEx(objc_getClass("IGBrowserSessionBuilder"), @selector(build),
                      (void *)hook_browserSessionBuild, &orig_browserSessionBuild);
    NullHookMessageEx(objc_getClass("IGBrowserViewController"), @selector(initWithBrowserSession:),
                      (void *)hook_browserVCInitWithSession, &orig_browserVCInitWithSession);
}
