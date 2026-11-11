#import "Include.h"
#import "Include/ThetaTweakCommon.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/lock.h>

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

#pragma mark - Pending store (451)

/* IG 451 queues every story seen receipt in the Swift IGStoryPendingSeenStateStore and uploads the
   whole queue later on a timer: the upload closure builds the /media/seen/ request from the queue and
   starts it with the direct (unhookable) -[IGAPIRequest startWithAPIClient:callback:], passing
   [uploader networker]. With Mark Seen on This Device Only on, the networker below is the gate:
   - stories the eye button marked are allowed by media pk for a while (THStorySeenAllowItem);
   - every other receipt in the queue is removed (they are never sent, not even after the setting is
     turned off), and that upload is blocked;
   - an upload whose queue holds only allowed receipts gets the networker, and the network-layer
     backstop (SeenRequestBlock.m) lets one /media/seen/ request through.
   The safety rule: the networker is returned only when the queue was read and held nothing but
   allowed receipts. An unreadable queue blocks (the eye then doesn't send, nothing leaks). */

static __weak id s_thetaPendingSeenStore;
static NSMutableDictionary<NSString *, NSDate *> *s_thetaAllowedSeenMedia; // media pk -> allowed at
static NSDate *s_thetaVerifiedUploadAt;
static os_unfair_lock s_thetaSeenAllowLock = OS_UNFAIR_LOCK_INIT;
static const NSTimeInterval kTHAllowedSeenLifetime = 15 * 60;
static const NSTimeInterval kTHVerifiedUploadWindow = 30;
/* Set while receipts are being discarded; on the first upload after the setting is turned off, the
   queue (filled while it was on) is emptied once more before uploads go through again. */
static NSString *const kTHStorySeenScrubPendingKey = @"Theta_StorySeenScrubPending";

static NSString *THStorySeenMediaPK(id item) {
    for (id obj in @[ ThetaValueForKey(item, @"media") ?: [NSNull null], item ?: [NSNull null] ]) {
        if (obj == [NSNull null]) continue;
        id pk = ThetaValueForKey(obj, @"pk");
        NSString *s = [pk isKindOfClass:[NSString class]] ? pk : ([pk respondsToSelector:@selector(stringValue)] ? [pk stringValue] : nil);
        if (s.length) return s;
    }
    return nil;
}

/* Called by the eye button (StoryGhost.m) before it marks `item`, so its receipt may be uploaded. */
void THStorySeenAllowItem(id item) {
    NSString *pk = THStorySeenMediaPK(item);
    THDebugLog(@"[Theta] seen allow: media %@", pk ?: @"(no pk)");
    if (!pk) return;
    os_unfair_lock_lock(&s_thetaSeenAllowLock);
    if (!s_thetaAllowedSeenMedia) s_thetaAllowedSeenMedia = [NSMutableDictionary dictionary];
    s_thetaAllowedSeenMedia[pk] = [NSDate date];
    os_unfair_lock_unlock(&s_thetaSeenAllowLock);
}

static NSSet<NSString *> *THStorySeenAllowedMedia(void) {
    os_unfair_lock_lock(&s_thetaSeenAllowLock);
    NSDate *now = [NSDate date];
    for (NSString *pk in s_thetaAllowedSeenMedia.allKeys) {
        if ([now timeIntervalSinceDate:s_thetaAllowedSeenMedia[pk]] > kTHAllowedSeenLifetime)
            [s_thetaAllowedSeenMedia removeObjectForKey:pk];
    }
    NSSet *set = [NSSet setWithArray:s_thetaAllowedSeenMedia.allKeys ?: @[]];
    os_unfair_lock_unlock(&s_thetaSeenAllowLock);
    return set;
}

/* A receipt key starts with the media pk ("<media pk>_<owner pk>…"). */
static BOOL THStorySeenKeyAllowed(id key, NSSet<NSString *> *allowed) {
    NSString *s = [key isKindOfClass:[NSString class]] ? key : [key description];
    NSString *first = [s componentsSeparatedByString:@"_"].firstObject;
    return first.length && [allowed containsObject:first];
}

/* Removes the keys that aren't allowed from one IGStorySeenState. NO if a field has an unexpected type. */
static BOOL THStorySeenScrubState(id state, NSSet<NSString *> *allowed, NSUInteger *kept, NSUInteger *removed) {
    static const char *dicts[] = { "_reelSeenDictionary", "_liveSeenDictionary", "_reelSkippedDictionary", "_liveSkippedDictionary" };
    for (size_t i = 0; i < sizeof(dicts) / sizeof(dicts[0]); i++) {
        Ivar iv = class_getInstanceVariable([state class], dicts[i]);
        if (!iv) return NO;
        id d = object_getIvar(state, iv);
        if (!d) continue;
        if (![d isKindOfClass:[NSDictionary class]]) return NO;
        NSMutableDictionary *m = [d isKindOfClass:[NSMutableDictionary class]] ? d : [d mutableCopy];
        for (id key in [m allKeys]) {
            if (THStorySeenKeyAllowed(key, allowed)) { (*kept)++; continue; }
            THDebugLog(@"[Theta] seen discard: %s %@", dicts[i], key);
            [m removeObjectForKey:key];
            (*removed)++;
        }
        if (m != d) object_setIvar(state, iv, m);
    }
    Ivar pogIv = class_getInstanceVariable([state class], "_storyPogSeenSet");
    id pog = pogIv ? object_getIvar(state, pogIv) : nil;
    if (pog) {
        if (![pog isKindOfClass:[NSSet class]]) return NO;
        NSMutableSet *m = [pog isKindOfClass:[NSMutableSet class]] ? pog : [pog mutableCopy];
        for (id key in [m allObjects]) {
            if (THStorySeenKeyAllowed(key, allowed)) { (*kept)++; continue; }
            THDebugLog(@"[Theta] seen discard: pog %@", key);
            [m removeObject:key];
            (*removed)++;
        }
        if (m != pog) object_setIvar(state, pogIv, m);
    }
    Ivar forceIv = class_getInstanceVariable([state class], "_forceSeenIds");
    id force = forceIv ? object_getIvar(state, forceIv) : nil;
    if ([force isKindOfClass:[NSArray class]] && [force count]) {
        NSMutableArray *keep = [NSMutableArray array];
        for (id key in force) {
            if (THStorySeenKeyAllowed(key, allowed)) [keep addObject:key];
            else (*removed)++;
        }
        object_setIvar(state, forceIv, [keep copy]);
    }
    return YES;
}

/* Scrubs every state in the pending store's queue. NO if the queue can't be read. */
static BOOL THStorySeenScrubQueue(NSSet<NSString *> *allowed, NSUInteger *kept, NSUInteger *removed) {
    *kept = 0;
    *removed = 0;
    id store = s_thetaPendingSeenStore;
    if (!store || ![store respondsToSelector:@selector(pendingSeenStates)]) {
        THDebugLog(@"[Theta] seen queue: no pending store");
        return NO;
    }
    id states = nil;
    @try { states = ((id (*)(id, SEL))objc_msgSend)(store, @selector(pendingSeenStates)); } @catch (__unused NSException *e) { return NO; }
    NSArray *list = nil;
    if (!states) list = @[];
    else if ([states isKindOfClass:[NSArray class]]) list = states;
    else if ([states isKindOfClass:[NSDictionary class]]) list = [states allValues];
    else if ([states isKindOfClass:[NSSet class]]) list = [states allObjects];
    else list = @[ states ];
    Class stateCls = objc_getClass("IGStorySeenState");
    for (id state in list) {
        if (!stateCls || ![state isKindOfClass:stateCls]) {
            THDebugLog(@"[Theta] seen queue: unreadable entry %@ in %@", NSStringFromClass([state class]), NSStringFromClass([states class]));
            return NO;
        }
        @try {
            if (!THStorySeenScrubState(state, allowed, kept, removed)) return NO;
        } @catch (__unused NSException *e) { return NO; }
    }
    THDebugLog(@"[Theta] seen queue: %lu states, kept %lu, discarded %lu", (unsigned long)list.count, (unsigned long)*kept, (unsigned long)*removed);
    return YES;
}

/* SeenRequestBlock.m: YES once for the /media/seen/ request of an upload the networker let through. */
BOOL THStorySeenConsumeVerifiedUpload(void) {
    os_unfair_lock_lock(&s_thetaSeenAllowLock);
    BOOL ok = s_thetaVerifiedUploadAt && -[s_thetaVerifiedUploadAt timeIntervalSinceNow] < kTHVerifiedUploadWindow;
    s_thetaVerifiedUploadAt = nil;
    os_unfair_lock_unlock(&s_thetaSeenAllowLock);
    return ok;
}

static id (*orig_uploaderNetworker)(id, SEL);
static id hook_uploaderNetworker(id self, SEL _cmd) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    // Not THStorySeenReceiptsBlocked(): the eye's synchronous allow window must not open the queue.
    if (!ENABLED(THStorySeenLocalOnly)) {
        if (![defaults boolForKey:kTHStorySeenScrubPendingKey]) return orig_uploaderNetworker(self, _cmd);
        // First upload after the setting went off: drop what was queued while it was on, once.
        NSUInteger kept = 0, removed = 0;
        BOOL readable = THStorySeenScrubQueue(THStorySeenAllowedMedia(), &kept, &removed);
        if (readable) [defaults removeObjectForKey:kTHStorySeenScrubPendingKey];
        if (!readable || removed) {
            THSeenDropLog(@"uploader networker (queue from while it was on)", @"-");
            return nil;
        }
        return orig_uploaderNetworker(self, _cmd);
    }

    if (![defaults boolForKey:kTHStorySeenScrubPendingKey]) [defaults setBool:YES forKey:kTHStorySeenScrubPendingKey];
    NSUInteger kept = 0, removed = 0;
    BOOL readable = THStorySeenScrubQueue(THStorySeenAllowedMedia(), &kept, &removed);
    if (readable && !removed && kept) {
        os_unfair_lock_lock(&s_thetaSeenAllowLock);
        s_thetaVerifiedUploadAt = [NSDate date];
        os_unfair_lock_unlock(&s_thetaSeenAllowLock);
        THDebugLog(@"[Theta] seen request: uploader networker allowed (%lu eye receipts)", (unsigned long)kept);
        return orig_uploaderNetworker(self, _cmd);
    }
    THSeenDropLog(@"uploader networker", readable ? @"-" : @"(queue unreadable)");
    return nil;
}

/* The viewer's flush reads the store through this getter (objc_msgSend), as does an ad toolbox at
   launch; keep a weak reference so the networker gate can read the queue. */
static id (*orig_reelPendingSeenStateStore)(id, SEL);
static id hook_reelPendingSeenStateStore(id self, SEL _cmd) {
    id store = orig_reelPendingSeenStateStore(self, _cmd);
    if (store && s_thetaPendingSeenStore != store) {
        s_thetaPendingSeenStore = store;
        THDebugLog(@"[Theta] seen queue: pending store %@", NSStringFromClass([store class]));
    }
    return store;
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
    NullHookMessageIfPresent(objc_getClass("IGStoryDataControllerSessionDeps"), @selector(reelPendingSeenStateStore),
                             (void *)hook_reelPendingSeenStateStore, &orig_reelPendingSeenStateStore);
}
