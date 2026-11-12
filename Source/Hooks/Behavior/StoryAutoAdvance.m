// Story auto-advance: the media view (photo timer or video end) reports the end through
// -storyPlayerMediaViewDidPlayToEnd: on the section controller, which then advances with
// navigation action 6. The Swift controller (IGStoryFullscreenSectionControllerSwift, used on
// newer builds) calls its advance code Swift-direct, so the end callback is the hookable point.
static void (*orig_storyDidPlayToEnd)(id self, SEL _cmd, id mediaView);
static void hook_storyDidPlayToEnd(id self, SEL _cmd, id mediaView) {
    if (ENABLED(THStoryDisableAutoAdvance)) {
        return;
    }

    orig_storyDidPlayToEnd(self, _cmd, mediaView);
}

static void (*orig_storySwiftDidPlayToEnd)(id self, SEL _cmd, id mediaView);
static void hook_storySwiftDidPlayToEnd(id self, SEL _cmd, id mediaView) {
    if (ENABLED(THStoryDisableAutoAdvance)) {
        return;
    }

    orig_storySwiftDidPlayToEnd(self, _cmd, mediaView);
}

void THRegisterStoryAutoAdvanceHooks(void) {
    SEL endSel = @selector(storyPlayerMediaViewDidPlayToEnd:);
    NullHookMessageIfPresent(ThetaFirstClass(@[ @"_TtC39IGStoryFullscreenSectionControllerSwift39IGStoryFullscreenSectionControllerSwift" ]), endSel, (void *)hook_storySwiftDidPlayToEnd, &orig_storySwiftDidPlayToEnd);
    NullHookMessageIfPresent(objc_getClass("IGStoryFullscreenSectionController"), endSel, (void *)hook_storyDidPlayToEnd, &orig_storyDidPlayToEnd);
}
