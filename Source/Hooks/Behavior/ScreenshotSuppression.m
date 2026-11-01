static void (*orig_screenshotSuppression)(id self, SEL _cmd);
static void hook_screenshotSuppression(id self, SEL _cmd) {
    if (!ENABLED(@"Screenshot Suppression")) {
        return orig_screenshotSuppression(self, _cmd);
    }
}

static void (*orig_setIsProtected)(id self, SEL _cmd, BOOL isProtected);
static void hook_setIsProtected(id self, SEL _cmd, BOOL isProtected) {
    orig_setIsProtected(self, _cmd, ENABLED(@"Screenshot Suppression") ? NO : isProtected);
}

/* Separate original from setIsProtected:. They used to share one, so setIsProtected: re-ran this
   initializer on a live provider and replaced its canvas view. */
static id (*orig_initWithIsProtected)(id self, SEL _cmd, BOOL isProtected);
static id hook_initWithIsProtected(id self, SEL _cmd, BOOL isProtected) {
    return orig_initWithIsProtected(self, _cmd, ENABLED(@"Screenshot Suppression") ? NO : isProtected);
}

static void (*orig_screenRecord)(id self, SEL _cmd, id state);
static void hook_screenRecord(id self, SEL _cmd, id state) {
    if (!ENABLED(@"Screenshot Suppression")) {
        return orig_screenRecord(self, _cmd, state);
    }
}

void THRegisterScreenshotProtectionProviderHooks(void) {
    NullHookMessageEx(objc_getClass("IGScreenCaptureProtection.IGScreenCaptureProtectionViewProvider"), @selector(setIsProtected:), (void *)hook_setIsProtected, &orig_setIsProtected);
    NullHookMessageEx(objc_getClass("IGScreenCaptureProtection.IGScreenCaptureProtectionViewProvider"), @selector(initWithIsProtected:), (void *)hook_initWithIsProtected, &orig_initWithIsProtected);
}

void THRegisterScreenshotObserverHook(void) {
    NullHookMessageEx(objc_getClass("IGScreenshotObserver"), @selector(_onTakenScreenshot), (void *)hook_screenshotSuppression, &orig_screenshotSuppression);
    NullHookMessageEx(objc_getClass("IGScreenshotObserver"), @selector(_screenCaptureStateDidChange:), (void *)hook_screenRecord, &orig_screenRecord);
}