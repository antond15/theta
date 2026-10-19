#import "Include/ThetaSettings.h"
#import <os/lock.h>

/* ENABLED() runs in hot hooks (layoutSubviews, cell configuration), and DBB swizzles
   -[NSUserDefaults boolForKey:] process-wide, so every uncached read builds a key and goes
   through that hook. NSUserDefaultsDidChangeNotification is posted synchronously on the writing
   thread by every set/remove (including Theta's own toggles), so a toggle is seen on the next read.
   No NSUserDefaults call is made while the lock is held, so the swizzle can't deadlock against it. */

static os_unfair_lock sThetaSettingsLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, NSNumber *> *sThetaSettingsCache;
static uint64_t sThetaSettingsGeneration;

static void ThetaSettingsObserveChanges(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sThetaSettingsCache = [NSMutableDictionary dictionary];
        [[NSNotificationCenter defaultCenter] addObserverForName:NSUserDefaultsDidChangeNotification
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(__unused NSNotification *note) {
            os_unfair_lock_lock(&sThetaSettingsLock);
            sThetaSettingsGeneration++;
            [sThetaSettingsCache removeAllObjects];
            os_unfair_lock_unlock(&sThetaSettingsLock);
        }];
    });
}

BOOL ThetaSettingEnabled(NSString *setting) {
    NSString *key = [setting isKindOfClass:[NSString class]] ? setting : nil;
    if (!key) {
        return [[NSUserDefaults standardUserDefaults] boolForKey:[NSString stringWithFormat:@"%@_Enabled", setting]];
    }
    ThetaSettingsObserveChanges();

    os_unfair_lock_lock(&sThetaSettingsLock);
    NSNumber *cached = sThetaSettingsCache[key];
    uint64_t generation = sThetaSettingsGeneration;
    os_unfair_lock_unlock(&sThetaSettingsLock);
    if (cached) return cached.boolValue;

    BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:[NSString stringWithFormat:@"%@_Enabled", key]];

    // Don't cache a value read while a write was landing; the next call reads it again.
    os_unfair_lock_lock(&sThetaSettingsLock);
    if (generation == sThetaSettingsGeneration) sThetaSettingsCache[key] = @(enabled);
    os_unfair_lock_unlock(&sThetaSettingsLock);
    return enabled;
}
