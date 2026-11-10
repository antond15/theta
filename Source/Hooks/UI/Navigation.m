#import "Include/ThetaTweakCommon.h"
#import <objc/runtime.h>
#import <objc/message.h>

// MARK: - Helpers

static NSString *THTabIntentForLabel(NSString *label) {
    if (!label.length) return nil;
    NSString *lower = label.lowercaseString;
    if ([lower containsString:@"feed"] || [lower isEqualToString:@"home"]) return @"FEED";
    if ([lower containsString:@"reels"] || [lower containsString:@"clips"]) return @"CLIPS";
    if ([lower containsString:@"explore"] || [lower containsString:@"search"]) return @"SEARCH";
    if ([lower containsString:@"direct"] || [lower containsString:@"messages"]) return @"DIRECT";
    if ([lower containsString:@"create"]) return @"CREATE";
    return nil;
}

static BOOL THShouldHideTabByIntent(NSString *intent) {
    if (!intent) return NO;
    if ([intent isEqualToString:@"FEED"]   && ENABLED(THNavHideFeedTab))     return YES;
    if ([intent isEqualToString:@"CLIPS"]  && ENABLED(THNavHideReelsTab))    return YES;
    if ([intent isEqualToString:@"SEARCH"] && ENABLED(THNavHideExploreTab))  return YES;
    if ([intent isEqualToString:@"DIRECT"] && ENABLED(THNavHideMessagesTab)) return YES;
    return NO;
}

static BOOL THShouldHideTabForSurface(id surface) {
    if (!surface) return NO;
    NSString *intent = nil;
    @try {
        intent = [surface performSelector:@selector(tabStringFromSurfaceIntent)];
    } @catch (__unused NSException *e) {}
    return THShouldHideTabByIntent(intent);
}

// MARK: - Tab Icon Ordering

static NSInteger (*orig_tabOrdering)(id, SEL) = NULL;
static NSInteger hook_tabOrdering(id self, SEL _cmd) {
    // Instagram's values: 0 = classic, 1 = standard, 2 = alternate
    NSString *order = ThetaSettingChoice(THNavTabOrder);
    if ([order isEqualToString:@"classic"]) return 0;
    if ([order isEqualToString:@"standard"]) return 1;
    if ([order isEqualToString:@"alternate"]) return 2;
    return orig_tabOrdering ? orig_tabOrdering(self, _cmd) : 1;
}

// MARK: - Swipe Between Tabs

static BOOL (*orig_isTabSwipingEnabled)(id, SEL) = NULL;
static BOOL hook_isTabSwipingEnabled(id self, SEL _cmd) {
    NSString *swipe = ThetaSettingChoice(THNavSwipeBetweenTabs);
    if ([swipe isEqualToString:@"enabled"]) return YES;
    if ([swipe isEqualToString:@"disabled"]) return NO;
    return orig_isTabSwipingEnabled ? orig_isTabSwipingEnabled(self, _cmd) : YES;
}

// MARK: - Launch Tab

static void (*orig_viewWillAppear_tabBar)(id, SEL, BOOL) = NULL;
static void hook_viewWillAppear_tabBar(id self, SEL _cmd, BOOL animated) {
    orig_viewWillAppear_tabBar(self, _cmd, animated);

    // Only fire once at launch, and only if Messenger Mode is not active
    if (ENABLED(THNavMessengerMode)) return;

    static BOOL sLaunchFired = NO;
    if (sLaunchFired) return;
    sLaunchFired = YES;

    static NSDictionary<NSString *, NSArray<NSString *> *> *sLaunchTargets;
    static dispatch_once_t sLaunchTargetsOnce;
    dispatch_once(&sLaunchTargetsOnce, ^{
        sLaunchTargets = @{
            @"home":     @[@"_timelineButtonPressed", @"FEED"],
            @"explore":  @[@"_exploreButtonPressed", @"SEARCH"],
            @"reels":    @[@"_discoverVideoButtonPressed", @"CLIPS"],
            @"messages": @[@"_directInboxButtonPressed", @"DIRECT"],
            @"profile":  @[@"_profileButtonPressed", @"PROFILE"],
        };
    });
    NSArray<NSString *> *target = sLaunchTargets[ThetaSettingChoice(THNavLaunchTab)];
    NSString *selName = target[0];
    NSString *intent = target[1];
    // A hidden tab has no view controller to switch to.
    if (THShouldHideTabByIntent(intent)) selName = nil;
    if (selName) {
        SEL sel = NSSelectorFromString(selName);
        if ([self respondsToSelector:sel]) {
            ((void(*)(id, SEL))objc_msgSend)(self, sel);
        }
    }
}

void THRegisterNavigationHooks(void) {
    // Also called from the constructor: IGTabBarController reads these while it builds the tab
    // bar, which happens before InitializeHooks runs.
    static BOOL sNavConfigHooked = NO, sLaunchTabHooked = NO;

    // _TtC18IGNavConfiguration18IGNavConfiguration is the Swift class name
    Class navConfig = objc_getClass("_TtC18IGNavConfiguration18IGNavConfiguration");
    if (navConfig && !sNavConfigHooked) {
        sNavConfigHooked = YES;
        SEL tabOrd = sel_registerName("tabOrdering");
        SEL swipe = sel_registerName("isTabSwipingEnabled");

        if ([navConfig instancesRespondToSelector:tabOrd])
            NullHookMessageEx(navConfig, tabOrd, (void *)hook_tabOrdering, &orig_tabOrdering);
        if ([navConfig instancesRespondToSelector:swipe])
            NullHookMessageEx(navConfig, swipe, (void *)hook_isTabSwipingEnabled, &orig_isTabSwipingEnabled);
    }

    // Launch tab — hooks IGTabBarController viewWillAppear
    Class tbCls = objc_getClass("IGTabBarController");
    if (tbCls && !sLaunchTabHooked) {
        sLaunchTabHooked = YES;
        NullHookMessageEx(tbCls, @selector(viewWillAppear:), (void *)hook_viewWillAppear_tabBar, &orig_viewWillAppear_tabBar);
    }
}
