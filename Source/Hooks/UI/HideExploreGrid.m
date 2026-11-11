static void (*orig_hideExploreGrid)(id self, SEL _cmd);
static Class THExploreGridViewControllerClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(@"IGExploreGridViewController"); });
    return cls;
}
static void hook_hideExploreGrid(id self, SEL _cmd) {
    if (ENABLED(THExploreHideGrid)) {
        UIResponder *responder = self;
        while ((responder = [responder nextResponder])) {
            if ([responder isKindOfClass:[UIViewController class]]) {
                break;
            }
        }
        if ([responder isKindOfClass:THExploreGridViewControllerClass()]) {
            [self removeFromSuperview];
            return;
        }
    }
    orig_hideExploreGrid(self, _cmd);
}

void THRegisterHideExploreGridHooks(void) {
    NullHookMessageEx(objc_getClass("IGListCollectionView"), @selector(layoutSubviews), (void *)hook_hideExploreGrid, &orig_hideExploreGrid);
}