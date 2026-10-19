#import "Include/ThetaTweakCommon.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <stdlib.h>

/** Liquid Glass shipped with iOS 26. IG 444 can still enable the experiment on older OS versions; that path crashes when banners/toasts appear. */
static inline BOOL theta_osSupportsLiquidGlass(void) {
    return [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 26;
}

/** Liquid Glass local experiments: either LG toggle. */
static inline BOOL theta_liquidGlassFloatingBarWanted(void) {
    return theta_osSupportsLiquidGlass() &&
        (ENABLED(@"Enable Liquid Glass Surfaces") || ENABLED(@"Enable Liquid Glass Buttons"));
}

// ── Liquid Glass Buttons (ObjC hooks) ────────────────────────────────────────

static BOOL (*orig_swizzleToggle_isEnabled)(id, SEL) = NULL;
static BOOL hook_swizzleToggle_isEnabled(id self, SEL _cmd) {
    if (!theta_osSupportsLiquidGlass())
        return orig_swizzleToggle_isEnabled ? orig_swizzleToggle_isEnabled(self, _cmd) : NO;
    if (ENABLED(@"Enable Liquid Glass Buttons")) return YES;
    return orig_swizzleToggle_isEnabled ? orig_swizzleToggle_isEnabled(self, _cmd) : NO;
}

static BOOL (*orig_expHelper_isEnabled)(id, SEL) = NULL;
static BOOL hook_expHelper_isEnabled(id self, SEL _cmd) {
    if (!theta_osSupportsLiquidGlass())
        return orig_expHelper_isEnabled ? orig_expHelper_isEnabled(self, _cmd) : NO;
    if (ENABLED(@"Enable Liquid Glass Buttons")) return YES;
    return orig_expHelper_isEnabled ? orig_expHelper_isEnabled(self, _cmd) : NO;
}

static BOOL (*orig_expHelper_isHomeFeed)(id, SEL) = NULL;
static BOOL hook_expHelper_isHomeFeed(id self, SEL _cmd) {
    if (!theta_osSupportsLiquidGlass())
        return orig_expHelper_isHomeFeed ? orig_expHelper_isHomeFeed(self, _cmd) : NO;
    if (ENABLED(@"Enable Liquid Glass Buttons")) return YES;
    return orig_expHelper_isHomeFeed ? orig_expHelper_isHomeFeed(self, _cmd) : NO;
}

// ── Liquid Glass Surfaces (IGDSLauncherConfig) ────────────────────────────────

static BOOL (*orig_lgInAppNotif)(id, SEL) = NULL;
static BOOL hook_lgInAppNotif(id self, SEL _cmd) {
    if (!theta_osSupportsLiquidGlass()) return NO;
    if (ENABLED(@"Enable Liquid Glass Surfaces")) return YES;
    return orig_lgInAppNotif ? orig_lgInAppNotif(self, _cmd) : NO;
}

static BOOL (*orig_lgIconBar)(id, SEL) = NULL;
static BOOL hook_lgIconBar(id self, SEL _cmd) {
    if (!theta_osSupportsLiquidGlass()) return NO;
    if (ENABLED(@"Enable Liquid Glass Surfaces")) return YES;
    return orig_lgIconBar ? orig_lgIconBar(self, _cmd) : NO;
}

// IGFloatingTabBarEnabled and the other IGTabBar* flags are C functions. Hooking them means
// inline-patching __TEXT, which breaks the code signature of a re-signed app (100% launch crash
// on IG 441 / iOS 26.6), so only the ObjC paths below are hooked.

// ── Liquid Glass local experiments ────────────────────────────────────────────
// Homecoming is not forced: on 451 it swaps the home feed for the All/Friends/Following feed.

// Read the experiment name stored in the _experimentName / _experimentGroupName ivar.
static NSString *theta_expName(id obj) {
    if (!obj) return nil;
    const char *ivarNames[] = { "_experimentName", "_experimentGroupName", NULL };
    for (int i = 0; ivarNames[i] != NULL; i++) {
        Ivar iv = class_getInstanceVariable(object_getClass(obj), ivarNames[i]);
        if (!iv) continue;
        @try {
            id v = object_getIvar(obj, iv);
            if ([v isKindOfClass:[NSString class]]) return (NSString *)v;
        } @catch (__unused id e) {}
    }
    return nil;
}

static inline BOOL theta_isGlassExp(NSString *name) {
    if (![name isKindOfClass:[NSString class]] || !name.length) return NO;
    NSString *lower = name.lowercaseString;
    return [lower containsString:@"lucent"] ||
           [lower containsString:@"floating_tab"] ||
           [lower containsString:@"floating_tab_bar"] ||
           [lower containsString:@"floatingtab"] ||
           [lower containsString:@"nav_lucent"] ||
           [lower containsString:@"launcher_nav"] ||
           [lower containsString:@"launcher_set"] ||
           [lower containsString:@"glass_navigation"] ||
           [lower containsString:@"translucent_tab"];
}

static id (*orig_meta_groupName)(id, SEL) = NULL;
static id hook_meta_groupName(id self, SEL _cmd) {
    if (theta_liquidGlassFloatingBarWanted() && theta_isGlassExp(theta_expName(self)))
        return @"test";
    return orig_meta_groupName ? orig_meta_groupName(self, _cmd) : nil;
}

static id (*orig_meta_peekGroupName)(id, SEL) = NULL;
static id hook_meta_peekGroupName(id self, SEL _cmd) {
    if (theta_liquidGlassFloatingBarWanted() && theta_isGlassExp(theta_expName(self)))
        return @"test";
    return orig_meta_peekGroupName ? orig_meta_peekGroupName(self, _cmd) : nil;
}

/* IG 451 reads these flags as Swift stored properties (59 direct calls to
   IGLiquidGlassNavigationExperimentHelper.isEnabled() in the main binary), so the getter swizzles above
   rarely run. Set the stored values through IG's own override setters instead. */
static void theta_applyLiquidGlassOverrides(void) {
    if (!theta_osSupportsLiquidGlass() || !ENABLED(@"Enable Liquid Glass Buttons")) return;
    Class helperCls = ThetaFirstClass(@[
        @"_TtC29IGLiquidGlassExperimentHelper39IGLiquidGlassNavigationExperimentHelper",
        @"IGLiquidGlassExperimentHelper.IGLiquidGlassNavigationExperimentHelper"
    ]);
    id helper = [helperCls respondsToSelector:@selector(shared)] ? ((id (*)(id, SEL))objc_msgSend)(helperCls, @selector(shared)) : nil;
    SEL overrideSel = NSSelectorFromString(@"overrideIsEnabled:");
    if ([helper respondsToSelector:overrideSel])
        ((void (*)(id, SEL, BOOL))objc_msgSend)(helper, overrideSel, YES);

    Class toggleCls = ThetaFirstClass(@[
        @"_TtC20IGLiquidGlassSwizzle26IGLiquidGlassSwizzleToggle",
        @"IGLiquidGlassSwizzle.IGLiquidGlassSwizzleToggle"
    ]);
    id toggle = [toggleCls respondsToSelector:@selector(shared)] ? ((id (*)(id, SEL))objc_msgSend)(toggleCls, @selector(shared)) : nil;
    if ([toggle respondsToSelector:@selector(setIsEnabled:)])
        ((void (*)(id, SEL, BOOL))objc_msgSend)(toggle, @selector(setIsEnabled:), YES);
}

// Install FBShared-framework experiment hooks once each; retry after framework load.
static void theta_tryInstallLiquidGlassExperimentHooksOnce(void) {
    static BOOL metaGroupDone = NO;
    static BOOL metaPeekDone = NO;

    Class metaCls = NSClassFromString(@"MetaLocalExperiment");
    if (metaCls) {
        SEL grp = NSSelectorFromString(@"groupName");
        if (!metaGroupDone && (class_getInstanceMethod(metaCls, grp) || class_getClassMethod(metaCls, grp))) {
            NullHookMessageIfPresent(metaCls, grp, (void *)hook_meta_groupName, &orig_meta_groupName);
            metaGroupDone = YES;
        }
        SEL peek = NSSelectorFromString(@"peekGroupName");
        if (!metaPeekDone && (class_getInstanceMethod(metaCls, peek) || class_getClassMethod(metaCls, peek))) {
            NullHookMessageIfPresent(metaCls, peek, (void *)hook_meta_peekGroupName, &orig_meta_peekGroupName);
            metaPeekDone = YES;
        }
    }
}

// ── Early registration (call from __attribute__((constructor)) load()) ─────────
// IMPORTANT: Pref keys are read inside each hook, not here. The dylib constructor
// runs before prefs may hydrate and before FBSharedFramework exposes MetaLocalExperiment —
// repeat attempts on main + when THRegisterLiquidGlassHooks runs.
void THRegisterLiquidGlassTabBarEarlyHooks(void) {
    theta_tryInstallLiquidGlassExperimentHooksOnce();

    dispatch_async(dispatch_get_main_queue(), ^{
            theta_tryInstallLiquidGlassExperimentHooksOnce();
        theta_applyLiquidGlassOverrides();
        dispatch_async(dispatch_get_main_queue(), ^{
                    theta_tryInstallLiquidGlassExperimentHooksOnce();
        });
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(),
                   ^{
            theta_tryInstallLiquidGlassExperimentHooksOnce();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                    theta_tryInstallLiquidGlassExperimentHooksOnce();
            theta_applyLiquidGlassOverrides();
        });
    });
}

// ── Main registration (call from InitializeHooks post-auth) ───────────────────
void THRegisterLiquidGlassHooks(void) {
    theta_tryInstallLiquidGlassExperimentHooksOnce();

    // lucent.navigation override follows the buttons toggle
    BOOL lgButtons = ENABLED(@"Enable Liquid Glass Buttons");
    [[NSUserDefaults standardUserDefaults] setValue:@(lgButtons ? YES : NO)
                                             forKey:@"instagram.override.project.lucent.navigation"];

    // Liquid glass buttons ObjC hooks
    Class swizzleToggle = NSClassFromString(@"IGLiquidGlassSwizzle.IGLiquidGlassSwizzleToggle");
    NullHookMessageIfPresent(swizzleToggle, @selector(isEnabled),
                             (void *)hook_swizzleToggle_isEnabled, &orig_swizzleToggle_isEnabled);

    Class expHelper = NSClassFromString(@"IGLiquidGlassExperimentHelper.IGLiquidGlassNavigationExperimentHelper");
    NullHookMessageIfPresent(expHelper, @selector(isEnabled),
                             (void *)hook_expHelper_isEnabled, &orig_expHelper_isEnabled);
    NullHookMessageIfPresent(expHelper, @selector(isHomeFeedHeaderEnabled),
                             (void *)hook_expHelper_isHomeFeed, &orig_expHelper_isHomeFeed);

    // IGDSLauncherConfig hooks for liquid glass surfaces
    Class launcherConfig = NSClassFromString(@"IGDSLauncherConfig");
    if (launcherConfig) {
        SEL lgNotif  = sel_registerName("isLiquidGlassInAppNotificationEnabled");
        SEL lgIcon   = sel_registerName("isLiquidGlassIconBarButtonEnabled");
        NullHookMessageIfPresent(launcherConfig, lgNotif,  (void *)hook_lgInAppNotif,   &orig_lgInAppNotif);
        NullHookMessageIfPresent(launcherConfig, lgIcon,   (void *)hook_lgIconBar,      &orig_lgIconBar);
    }

    theta_tryInstallLiquidGlassExperimentHooksOnce();
    theta_applyLiquidGlassOverrides();
}
