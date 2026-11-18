/* The map bubble in the DM inbox's notes tray is its own IGListKit section. An empty
   section with no inset takes no space. Read once per launch: IGListKit keeps the section
   controller, and a count that changes without an update would fail its next batch update. */
static BOOL THHideFriendMap(void) {
    static BOOL hide;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ hide = ENABLED(THDMHideFriendMap); });
    return hide;
}

static NSInteger (*orig_THFriendMapNumberOfItems)(id, SEL);
static NSInteger hook_THFriendMapNumberOfItems(id self, SEL _cmd) {
    return THHideFriendMap() ? 0 : orig_THFriendMapNumberOfItems(self, _cmd);
}

static UIEdgeInsets (*orig_THFriendMapInset)(id, SEL);
static UIEdgeInsets hook_THFriendMapInset(id self, SEL _cmd) {
    return THHideFriendMap() ? UIEdgeInsetsZero : orig_THFriendMapInset(self, _cmd);
}

void THRegisterHideFriendMapHooks(void) {
    Class section = ThetaFirstClass(@[
        @"_TtC24IGDirectNotesTrayUISwift43IGDirectNotesTrayFriendMapSectionController",
        @"IGDirectNotesTrayUISwift.IGDirectNotesTrayFriendMapSectionController"
    ]);
    NullHookMessageIfPresent(section, @selector(numberOfItems), (void *)hook_THFriendMapNumberOfItems, &orig_THFriendMapNumberOfItems);
    NullHookMessageIfPresent(section, @selector(inset), (void *)hook_THFriendMapInset, &orig_THFriendMapInset);
}
