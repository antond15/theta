#import "Include/ThetaTweakCommon.h"
#import "Include/ThetaSubstrate.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <stdlib.h>

/** Liquid Glass shipped with iOS 26. IG 444 can still enable the experiment on older OS versions; that path crashes when banners/toasts appear. */
static inline BOOL theta_osSupportsLiquidGlass(void) {
    return [[NSProcessInfo processInfo] operatingSystemVersion].majorVersion >= 26;
}

/** Floating tab bar C hooks key off liquid glass surfaces only. */
static inline BOOL theta_liquidGlassSurfacesWanted(void) {
    return theta_osSupportsLiquidGlass() && ENABLED(@"Enable Liquid Glass Surfaces");
}

/** Homecoming experiment bypass: either LG toggle. */
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

// ── Floating glass tab bar: C symbols via MSHookFunction ─
// fishhook rebind_symbols corrupts FBSharedFramework GOT; Substrate hooks the real fn.
//
// IG 444+: these take the launcher set in x0 (IGFloatingTabBarEnabled forwards it to
// IGTabBarStyleForLauncherSet, which objc_retains it). A BOOL(void) hook clobbers x0
// while reading prefs, then tail-calls orig → SIGSEGV in objc_retain. Extra unused x0
// is harmless if an older binary still uses a no-arg signature.

static BOOL (*orig_IGFloatingTabBarEnabled)(id) = NULL;
static BOOL (*orig_IGTabBarDynamicSizingEnabled)(id) = NULL;
static BOOL (*orig_IGTabBarEnhancedDynamicSizingEnabled)(id) = NULL;
static BOOL (*orig_IGTabBarHomecomingWithFloatingTabEnabled)(id) = NULL;
static BOOL (*orig_IGTabBarViewPointFixEnabled)(id) = NULL;
static NSInteger (*orig_IGTabBarStyleForLauncherSet)(id) = NULL;

static BOOL hook_IGFloatingTabBarEnabled(id launcherSet) {
    if (theta_liquidGlassSurfacesWanted()) return YES;
    return orig_IGFloatingTabBarEnabled ? orig_IGFloatingTabBarEnabled(launcherSet) : NO;
}
static BOOL hook_IGTabBarDynamicSizingEnabled(id launcherSet) {
    if (theta_liquidGlassSurfacesWanted()) return YES;
    return orig_IGTabBarDynamicSizingEnabled ? orig_IGTabBarDynamicSizingEnabled(launcherSet) : NO;
}
static BOOL hook_IGTabBarEnhancedDynamicSizingEnabled(id launcherSet) {
    if (theta_liquidGlassSurfacesWanted()) return YES;
    return orig_IGTabBarEnhancedDynamicSizingEnabled ? orig_IGTabBarEnhancedDynamicSizingEnabled(launcherSet) : NO;
}
static BOOL hook_IGTabBarHomecomingWithFloatingTabEnabled(id launcherSet) {
    if (theta_liquidGlassSurfacesWanted()) return YES;
    return orig_IGTabBarHomecomingWithFloatingTabEnabled ? orig_IGTabBarHomecomingWithFloatingTabEnabled(launcherSet) : NO;
}
static BOOL hook_IGTabBarViewPointFixEnabled(id launcherSet) {
    if (theta_liquidGlassSurfacesWanted()) return YES;
    return orig_IGTabBarViewPointFixEnabled ? orig_IGTabBarViewPointFixEnabled(launcherSet) : NO;
}
static NSInteger hook_IGTabBarStyleForLauncherSet(id launcherSet) {
    if (theta_liquidGlassSurfacesWanted()) return 1;
    return orig_IGTabBarStyleForLauncherSet ? orig_IGTabBarStyleForLauncherSet(launcherSet) : 0;
}

static BOOL theta_tryInstallLiquidGlassTabBarCSymbolHooks(void) {
#ifdef SIDELOAD
    /* Never inline-patch __TEXT in a sideloaded build.
     *
     * Substrate implements MSHookFunction by making the target page writable and writing a branch
     * into it. On a jailbroken device that is fine. In a re-signed app it is fatal: the page ends
     * up rw- (non-executable) and dirty, so it no longer matches the code signature, and the first
     * call into it is killed by the kernel — EXC_BAD_ACCESS / KERN_PROTECTION_FAILURE with
     * termination namespace CODESIGNING, indicator "Invalid Page".
     *
     * Seen on IG 441.0.0 / iOS 26.6 as a 100% launch crash: pc landed in a rw- 16K hole inside
     * FBSharedFramework's __TEXT at IGFloatingTabBarEnabled, reached from METARunPreApplicationMain
     * during startup. It only appears once a working Substrate is actually loadable in the bundle,
     * which is why some sideload builds survived.
     *
     * The ObjC swizzles in THRegisterLiquidGlassHooks() only touch runtime dispatch tables, never
     * signed pages, so they stay enabled — Liquid Glass just loses the C-flag overrides.
     */
    static dispatch_once_t sideloadOnce;
    dispatch_once(&sideloadOnce, ^{
        NSLog(@"[Theta] Liquid Glass: skipping C-symbol inline hooks — unsafe in a re-signed app");
    });
    return NO;
#else
    static BOOL floatingDone = NO;
    static BOOL dynamicDone = NO;
    static BOOL enhancedDone = NO;
    static BOOL homecomingDone = NO;
    static BOOL viewpointDone = NO;
    static BOOL styleDone = NO;

    if (!ThetaSubstrateLoad()) return NO;

    /* Don't touch __TEXT at all unless a Liquid Glass toggle is on. The hook bodies already defer
       to the original when disabled, so this is behaviour-neutral — both toggles are documented as
       requiring a restart anyway. */
    if (!ENABLED(@"Enable Liquid Glass Surfaces") && !ENABLED(@"Enable Liquid Glass Buttons")) {
        return NO;
    }

    if (!floatingDone) {
        void *sym = ThetaResolveInstagramExecutableSymbol("IGFloatingTabBarEnabled");
        if (sym) {
            ThetaMSHookFunction(sym, (void *)hook_IGFloatingTabBarEnabled, (void **)&orig_IGFloatingTabBarEnabled);
            floatingDone = YES;
        }
    }
    if (!dynamicDone) {
        void *sym = ThetaResolveInstagramExecutableSymbol("IGTabBarDynamicSizingEnabled");
        if (sym) {
            ThetaMSHookFunction(sym, (void *)hook_IGTabBarDynamicSizingEnabled, (void **)&orig_IGTabBarDynamicSizingEnabled);
            dynamicDone = YES;
        }
    }
    if (!enhancedDone) {
        void *sym = ThetaResolveInstagramExecutableSymbol("IGTabBarEnhancedDynamicSizingEnabled");
        if (sym) {
            ThetaMSHookFunction(sym, (void *)hook_IGTabBarEnhancedDynamicSizingEnabled, (void **)&orig_IGTabBarEnhancedDynamicSizingEnabled);
            enhancedDone = YES;
        }
    }
    if (!homecomingDone) {
        void *sym = ThetaResolveInstagramExecutableSymbol("IGTabBarHomecomingWithFloatingTabEnabled");
        if (sym) {
            ThetaMSHookFunction(sym, (void *)hook_IGTabBarHomecomingWithFloatingTabEnabled, (void **)&orig_IGTabBarHomecomingWithFloatingTabEnabled);
            homecomingDone = YES;
        }
    }
    if (!viewpointDone) {
        void *sym = ThetaResolveInstagramExecutableSymbol("IGTabBarViewPointFixEnabled");
        if (sym) {
            ThetaMSHookFunction(sym, (void *)hook_IGTabBarViewPointFixEnabled, (void **)&orig_IGTabBarViewPointFixEnabled);
            viewpointDone = YES;
        }
    }
    if (!styleDone) {
        void *sym = ThetaResolveInstagramExecutableSymbol("IGTabBarStyleForLauncherSet");
        if (sym) {
            ThetaMSHookFunction(sym, (void *)hook_IGTabBarStyleForLauncherSet, (void **)&orig_IGTabBarStyleForLauncherSet);
            styleDone = YES;
        }
    }

    return floatingDone && styleDone;
#endif
}

// ── Floating glass tab bar: homecoming experiment gate bypass ─────────────────

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

static inline BOOL theta_isHomecomingExp(NSString *name) {
    if (![name isKindOfClass:[NSString class]] || !name.length) return NO;
    NSString *lower = name.lowercaseString;
    return [lower containsString:@"homecoming"] ||
           [lower containsString:@"lucent"] ||
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
    if (theta_liquidGlassFloatingBarWanted() && theta_isHomecomingExp(theta_expName(self)))
        return @"test";
    return orig_meta_groupName ? orig_meta_groupName(self, _cmd) : nil;
}

static id (*orig_meta_peekGroupName)(id, SEL) = NULL;
static id hook_meta_peekGroupName(id self, SEL _cmd) {
    if (theta_liquidGlassFloatingBarWanted() && theta_isHomecomingExp(theta_expName(self)))
        return @"test";
    return orig_meta_peekGroupName ? orig_meta_peekGroupName(self, _cmd) : nil;
}

static Class theta_resolveIGNavConfigurationClass(void) {
    static Class cached = Nil;
    if (cached) return cached;

    NSArray *mangledAttempts = @[
        @"IGNavConfiguration",
        @"_TtC18IGNavConfiguration18IGNavConfiguration",
        @"_TtC19IGNavConfiguration19IGNavConfiguration",
        @"_TtC20IGNavConfiguration20IGNavConfiguration",
        @"_TtC17IGNavConfiguration17IGNavConfiguration",
        @"_TtC21IGNavConfiguration21IGNavConfiguration",
        @"_TtC16IGNavConfiguration16IGNavConfiguration",
    ];
    SEL isHC = NSSelectorFromString(@"isHomecomingEnabled");
    for (NSString *n in mangledAttempts) {
        Class c = NSClassFromString(n);
        if (c && class_getInstanceMethod(c, isHC)) {
            cached = c;
            return cached;
        }
    }
    return Nil;
}

// IGNavConfiguration (Swift)  -isHomecomingEnabled
static BOOL (*orig_navCfg_isHomecoming)(id, SEL) = NULL;
static BOOL hook_navCfg_isHomecoming(id self, SEL _cmd) {
    if (theta_liquidGlassFloatingBarWanted()) return YES;
    return orig_navCfg_isHomecoming ? orig_navCfg_isHomecoming(self, _cmd) : NO;
}

// ── Homecoming UI hooks (installed from THRegisterLiquidGlassHooks) ───────────

// IGTabBarViewControllerManager  -_isHomecomingEnabled
static BOOL (*orig_tbvcm_isHomecoming)(id, SEL) = NULL;
static BOOL hook_tbvcm_isHomecoming(id self, SEL _cmd) {
    if (theta_liquidGlassFloatingBarWanted()) return YES;
    return orig_tbvcm_isHomecoming ? orig_tbvcm_isHomecoming(self, _cmd) : NO;
}

// IGMainAppSurfaceIntent  +resolvedHomeAppSurfaceIntentWithIsHomecomingEnabled:
static id (*orig_surfaceIntent_resolved)(id, SEL, BOOL) = NULL;
static id hook_surfaceIntent_resolved(id self, SEL _cmd, BOOL enabled) {
    if (theta_liquidGlassFloatingBarWanted()) enabled = YES;
    return orig_surfaceIntent_resolved ? orig_surfaceIntent_resolved(self, _cmd, enabled) : nil;
}

// Install FBShared-framework experiment hooks once each; retry after framework load.
static void theta_tryInstallLiquidGlassExperimentHooksOnce(void) {
    static BOOL metaGroupDone = NO;
    static BOOL metaPeekDone = NO;
    static BOOL navDone = NO;

    SEL isHC = NSSelectorFromString(@"isHomecomingEnabled");

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

    if (!navDone) {
        Class navCfg = theta_resolveIGNavConfigurationClass();
        if (navCfg && class_getInstanceMethod(navCfg, isHC)) {
            NullHookMessageIfPresent(navCfg, isHC, (void *)hook_navCfg_isHomecoming, &orig_navCfg_isHomecoming);
            navDone = YES;
        }
    }
}

// ── Early registration (call from __attribute__((constructor)) load()) ─────────
// IMPORTANT: Pref keys are read inside each hook, not here. The dylib constructor
// runs before prefs may hydrate and before FBSharedFramework exposes MetaLocalExperiment —
// repeat attempts on main + when THRegisterLiquidGlassHooks runs.
void THRegisterLiquidGlassTabBarEarlyHooks(void) {
    theta_tryInstallLiquidGlassTabBarCSymbolHooks();
    theta_tryInstallLiquidGlassExperimentHooksOnce();

    dispatch_async(dispatch_get_main_queue(), ^{
        theta_tryInstallLiquidGlassTabBarCSymbolHooks();
        theta_tryInstallLiquidGlassExperimentHooksOnce();
        dispatch_async(dispatch_get_main_queue(), ^{
            theta_tryInstallLiquidGlassTabBarCSymbolHooks();
            theta_tryInstallLiquidGlassExperimentHooksOnce();
        });
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(),
                   ^{
        theta_tryInstallLiquidGlassTabBarCSymbolHooks();
        theta_tryInstallLiquidGlassExperimentHooksOnce();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            theta_tryInstallLiquidGlassTabBarCSymbolHooks();
            theta_tryInstallLiquidGlassExperimentHooksOnce();
        });
    });
}

// ── Main registration (call from InitializeHooks post-auth) ───────────────────
void THRegisterLiquidGlassHooks(void) {
    theta_tryInstallLiquidGlassTabBarCSymbolHooks();
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

    // Floating glass tab bar: homecoming UI enablement
    // These classes are loaded post-auth so we hook them here.
    Class tbvcm = NSClassFromString(@"IGTabBarViewControllerManager");
    NullHookMessageIfPresent(tbvcm,
        NSSelectorFromString(@"_isHomecomingEnabled"),
        (void *)hook_tbvcm_isHomecoming, &orig_tbvcm_isHomecoming);

    // Class method — hook via metaclass so class_replaceMethod targets the right dispatch table
    Class surfaceIntentMeta = object_getClass(NSClassFromString(@"IGMainAppSurfaceIntent"));
    NullHookMessageIfPresent(surfaceIntentMeta,
        NSSelectorFromString(@"resolvedHomeAppSurfaceIntentWithIsHomecomingEnabled:"),
        (void *)hook_surfaceIntent_resolved, &orig_surfaceIntent_resolved);

}
