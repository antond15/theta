/* Opening a DM from a notification on a cold launch could stay on "Loading..." forever.
   IGDirectDataLoadingViewController swaps itself for the loaded thread exactly once, from
   viewDidAppear:, with a non-animated -[UINavigationController setViewControllers:]. On a cold launch
   Instagram presents its TestFlight update nudge at the same moment (HideTestFlightNag.m then
   dismisses it), so the swap lands mid-transition and is lost, and nothing retries it. Retry the
   same replacement once the navigation controller has settled. */

static Ivar THThreadOpenIvar(id obj, const char *name) {
    return obj ? class_getInstanceVariable(object_getClass(obj), name) : NULL;
}

static BOOL THThreadOpenBoolIvar(id obj, const char *name) {
    Ivar iv = THThreadOpenIvar(obj, name);
    return iv && *((BOOL *)((char *)(__bridge void *)obj + ivar_getOffset(iv)));
}

static void THThreadOpenRetrySwap(UIViewController *loading, unsigned attempt) {
    if (!loading || attempt > 20) return;
    Ivar swapIvar = THThreadOpenIvar(loading, "_viewControllerToSwapAfterPresentation");
    UIViewController *thread = swapIvar ? object_getIvar(loading, swapIvar) : nil;
    if (![thread isKindOfClass:[UIViewController class]] || !THThreadOpenBoolIvar(loading, "_itemLoaded")
        || THThreadOpenBoolIvar(loading, "_isPresenting"))
        return;

    // Same lookup as Instagram's swap: the navigation controller, or a navigation-controller parent.
    UINavigationController *nav = loading.navigationController;
    if (!nav && [loading.parentViewController isKindOfClass:[UINavigationController class]])
        nav = (UINavigationController *)loading.parentViewController;
    NSUInteger index = [nav.viewControllers indexOfObject:loading];
    // Already swapped (the ivar is never cleared) or popped by the user: nothing to do.
    if (!nav || index == NSNotFound || thread.parentViewController) return;

    if (nav.transitionCoordinator || !loading.view.window
        || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
        __weak UIViewController *weakLoading = loading;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            THThreadOpenRetrySwap(weakLoading, attempt + 1);
        });
        return;
    }

    NSMutableArray *controllers = [nav.viewControllers mutableCopy];
    controllers[index] = thread;
    THDebugLog(@"[Theta] notification thread: retrying the lost loading-screen swap (attempt %u)", attempt);
    [nav setViewControllers:controllers animated:NO];
}

static void (*orig_directLoadingViewDidAppear)(id, SEL, BOOL);
static void hook_directLoadingViewDidAppear(id self, SEL _cmd, BOOL animated) {
    orig_directLoadingViewDidAppear(self, _cmd, animated);
    // Give Instagram's own swap (just run by the original) the first go.
    __weak UIViewController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        THThreadOpenRetrySwap(weakSelf, 0);
    });
}

void THRegisterNotificationThreadOpenHooks(void) {
    NullHookMessageIfPresent(objc_getClass("IGDirectDataLoadingViewController"), @selector(viewDidAppear:),
                             (void *)hook_directLoadingViewDidAppear, (void *)&orig_directLoadingViewDidAppear);
}
