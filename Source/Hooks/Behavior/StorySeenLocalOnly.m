#import "Include.h"
#import "Include/ThetaTweakCommon.h"
#import <objc/runtime.h>
#import <objc/message.h>

/* Keeps story seen receipts on this device while Mark Seen on This Device Only is on. The 451 path is
   -[IGStorySeenStateUploader networker] below; SeenRequestBlock.m drops /media/seen/ at the network layer
   as a backstop. Also stops the Reels (Sundial) seen-state upload. */

/* The eye button (StoryGhost.m) sets s_thetaAllowStorySeenReceipts around a mark that should be sent. */
BOOL THStorySeenReceiptsBlocked(void) {
    if (s_thetaAllowStorySeenReceipts) return NO;
    return ENABLED(THStorySeenLocalOnly);
}

// Debug builds: which seen path was blocked, and whether the foreground hook pass had run yet
// (a background launch blocks before it).
#define THSeenDropLog(what, path) \
    THDebugLog(@"[Theta] seen blocked: %@ %@ (foreground hooks %s)", what, (path) ?: @"-", hooksInitialized ? "installed" : "pending")

static void (*orig_sundialUploadSeenStateIfNecessary)(id, SEL);
static void hook_sundialUploadSeenStateIfNecessary(id self, SEL _cmd) {
    if (THStorySeenReceiptsBlocked()) {
        THSeenDropLog(@"uploadSeenStateIfNecessary", NSStringFromClass(object_getClass(self)));
        return;
    }
    orig_sundialUploadSeenStateIfNecessary(self, _cmd);
}

static void (*orig_sundialAppendSeenState)(id, SEL, id);
static void hook_sundialAppendSeenState(id self, SEL _cmd, id payload) {
    if (THStorySeenReceiptsBlocked()) return;
    orig_sundialAppendSeenState(self, _cmd, payload);
}

/* IG 451: the Swift pending store builds the /media/seen/ request itself and starts it with
   the direct (unhookable) -[IGAPIRequest startWithAPIClient:callback:], passing [uploader networker]. */
static id (*orig_uploaderNetworker)(id, SEL);
static id hook_uploaderNetworker(id self, SEL _cmd) {
    if (THStorySeenReceiptsBlocked()) {
        THSeenDropLog(@"uploader networker", @"-");
        return nil;
    }
    return orig_uploaderNetworker(self, _cmd);
}

void THRegisterStorySeenLocalOnlyHooks(void) {
    Class sundialMgr = ThetaFirstClass(@[ @"_TtC23IGSundialSeenStateSwift25IGSundialSeenStateManager", @"IGSundialSeenStateManager" ]);
    if (sundialMgr) {
        NullHookMessageIfPresent(sundialMgr, @selector(uploadSeenStateIfNecessary), (void *)hook_sundialUploadSeenStateIfNecessary,
            &orig_sundialUploadSeenStateIfNecessary);
        NullHookMessageIfPresent(sundialMgr, @selector(appendSeenState:), (void *)hook_sundialAppendSeenState, &orig_sundialAppendSeenState);
    }

    Class uploader = objc_getClass("IGStorySeenStateUploader");
    if (uploader)
        NullHookMessageIfPresent(uploader, @selector(networker), (void *)hook_uploaderNetworker, &orig_uploaderNetworker);
}
