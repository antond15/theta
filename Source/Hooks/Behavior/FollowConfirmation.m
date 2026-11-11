#import "Include/ThetaHelper.h"

// Instagram 451 moved the controller into the IGFollowing Swift module and replaced
// `_didPressFollowButton` with two button actions: `didPressFollowButtonFromControlEvent`
// (registered with addTarget:action:forControlEvents:) and `didPressFollowButtonWith:`. Both are
// dispatched by UIKit, so both are hooked. The old selector stays as the fallback for older builds.

static BOOL sThetaFollowConfirmActive;

// YES only when the profile is known and not followed yet (IGUser followStatus 2). An unknown
// user passes through unprompted, so an unfollow is never asked about.
static BOOL ThetaFollowNeedsConfirmation(id controller) {
    if (!ENABLED(THConfirmFollow) || sThetaFollowConfirmActive) return NO;
    @try {
        // 451: no `user` getter, only the `_user` ivar. Older builds: the `user` property.
        Ivar ivar = class_getInstanceVariable(object_getClass(controller), "_user");
        id user = ivar ? object_getIvar(controller, ivar) : [controller valueForKey:@"user"];
        Class userClass = NSClassFromString(@"IGUser");
        if (!userClass || ![user isKindOfClass:userClass] || ![user respondsToSelector:@selector(followStatus)]) {
            THDebugLog(@"[Theta] follow confirmation: no readable user on %@, not asking", NSStringFromClass([controller class]));
            return NO;
        }
        return [(IGUser *)user followStatus] == 2;
    } @catch (NSException *e) {
        THDebugLog(@"[Theta] follow confirmation: %@", e);
        return NO;
    }
}

static void ThetaAskThenFollow(void (^follow)(void)) {
    [ThetaHelper showCustomAlertWithActions:@"✋ Woah! Hold up!" description:@"Are you sure you want to follow this user?" actions:@[
        @{
            @"title": @"Yes, follow them!",
            @"handler": ^(id sender) {
                sThetaFollowConfirmActive = YES;
                follow();
                sThetaFollowConfirmActive = NO;
            }
        },
        @{
            @"title": @"No, I'm good.",
            @"handler": ^(id sender) {
                // Do nothing, just cancel
            }
        }
    ]];
}

static void (*orig_followControlEvent)(id self, SEL _cmd);
static void hook_followControlEvent(id self, SEL _cmd) {
    if (!ThetaFollowNeedsConfirmation(self)) {
        orig_followControlEvent(self, _cmd);
        return;
    }
    ThetaAskThenFollow(^{ orig_followControlEvent(self, _cmd); });
}

static void (*orig_followWith)(id self, SEL _cmd, id sender);
static void hook_followWith(id self, SEL _cmd, id sender) {
    if (!ThetaFollowNeedsConfirmation(self)) {
        orig_followWith(self, _cmd, sender);
        return;
    }
    ThetaAskThenFollow(^{ orig_followWith(self, _cmd, sender); });
}

static void (*orig_followLegacy)(id self, SEL _cmd);
static void hook_followLegacy(id self, SEL _cmd) {
    if (!ThetaFollowNeedsConfirmation(self)) {
        orig_followLegacy(self, _cmd);
        return;
    }
    ThetaAskThenFollow(^{ orig_followLegacy(self, _cmd); });
}

void THRegisterFollowConfirmationHooks(void) {
    Class controller = ThetaFirstClass(@[
        @"_TtC11IGFollowing18IGFollowController",
        @"IGFollowController"
    ]);
    NullHookMessageIfPresent(controller, @selector(didPressFollowButtonFromControlEvent), (void *)hook_followControlEvent, &orig_followControlEvent);
    NullHookMessageIfPresent(controller, @selector(didPressFollowButtonWith:), (void *)hook_followWith, &orig_followWith);
    NullHookMessageIfPresent(controller, @selector(_didPressFollowButton), (void *)hook_followLegacy, &orig_followLegacy);
}
