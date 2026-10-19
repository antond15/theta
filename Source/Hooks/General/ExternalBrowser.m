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

    if (!ENABLED(@"Strip Tracking from Links")) {
        NSURL *result = [NSURL URLWithString:urlStr];
        return result ?: url;
    }

    NSURLComponents *comps = [NSURLComponents componentsWithString:urlStr];
    if (comps.queryItems.count) {
        NSSet *tracking = THTrackingParamSet();
        NSMutableArray *clean = [NSMutableArray array];
        for (NSURLQueryItem *q in comps.queryItems) {
            if (![tracking containsObject:q.name]) [clean addObject:q];
        }
        comps.queryItems = clean.count ? clean : nil;
    }

    NSURL *result = comps.URL;
    return result ?: url;
}

static BOOL THIsWebURL(NSURL *url) {
    NSString *scheme = url.scheme.lowercaseString;
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

static void (*orig_viewWillAppear_Browser)(id self, SEL _cmd, BOOL animated);
static void hook_viewWillAppear_Browser(id self, SEL _cmd, BOOL animated) {
    @try {
        id session = ((id(*)(id,SEL))objc_msgSend)(self, @selector(browserSession));
        Ivar urlIvar = session ? class_getInstanceVariable([session class], "_urlRequest") : nil;
        NSURLRequest *req = urlIvar ? object_getIvar(session, urlIvar) : nil;
        NSURL *url = req.URL;

        // Only web links leave the app; anything else stays with Instagram's own handling.
        if (url && ENABLED(@"Open Links in External Browser")) {
            NSURL *cleaned = THCleanBrowserURL(url);
            if (THIsWebURL(cleaned)) {
                [[UIApplication sharedApplication] openURL:cleaned options:@{} completionHandler:nil];
                [(UIViewController *)self dismissViewControllerAnimated:NO completion:nil];
                return;
            }
        }

        // Strip tracking params in the in-app browser too
        if (url && ENABLED(@"Strip Tracking from Links") && urlIvar) {
            NSURL *cleaned = THCleanBrowserURL(url);
            if (THIsWebURL(cleaned) && ![cleaned isEqual:url]) {
                NSURLRequest *cleanReq = [NSURLRequest requestWithURL:cleaned];
                object_setIvar(session, urlIvar, cleanReq);
            }
        }
    } @catch (__unused NSException *e) {}

    orig_viewWillAppear_Browser(self, _cmd, animated);
}

void THRegisterExternalBrowserHooks(void) {
    Class cls = objc_getClass("IGBrowserNavigationController");
    NullHookMessageEx(cls, @selector(viewWillAppear:), (void *)hook_viewWillAppear_Browser, &orig_viewWillAppear_Browser);
}
