static void (*orig_hideBrainBot)(IGUnifiedVideoCollectionView *self, SEL _cmd);
static void hook_hideBrainBot(IGUnifiedVideoCollectionView *self, SEL _cmd) {
    orig_hideBrainBot(self, _cmd);
    
    if (ENABLED(THReelsDisableScrolling)) {
        self.scrollEnabled = NO;
    }
}

/* Instagram turns scrolling off while the scrubber is dragged and back on afterwards, which
   would undo the lock above. */
static void (*orig_setScrollEnabled)(IGUnifiedVideoCollectionView *self, SEL _cmd, BOOL enabled);
static void hook_setScrollEnabled(IGUnifiedVideoCollectionView *self, SEL _cmd, BOOL enabled) {
    orig_setScrollEnabled(self, _cmd, enabled && !ENABLED(THReelsDisableScrolling));
}

void THRegisterNoBrainrotHooks(void) {
    NullHookMessageEx(objc_getClass("IGUnifiedVideoCollectionView"), @selector(didMoveToWindow), (void *)hook_hideBrainBot, &orig_hideBrainBot);
    NullHookMessageEx(objc_getClass("IGUnifiedVideoCollectionView"), @selector(setScrollEnabled:), (void *)hook_setScrollEnabled, &orig_setScrollEnabled);
}
