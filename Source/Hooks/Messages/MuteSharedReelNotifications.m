/* The NSE does the muting (ThetaNSE.m); it can't read the app's defaults, so copy the toggle
   into the shared settings file (read first) and the shared suite on launch and on every
   defaults change. */
static void THMirrorMuteSharedReelSetting(void) {
    NSUserDefaults *shared = [[NSUserDefaults alloc] initWithSuiteName:THETA_SHARED_SUITE];
    // Not ENABLED(): its cache may not have seen this change yet.
    ThetaSettingsPrepare();
    BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:ThetaSettingStorageKey(THDMMuteSharedReelNotifications)];
    ThetaSharedSettingSetBool(THETA_SHARED_MUTE_REEL_SHARES, enabled);
    // Only write on a change: the write posts NSUserDefaultsDidChangeNotification again.
    if ([shared boolForKey:THETA_SHARED_MUTE_REEL_SHARES] != enabled) {
        [shared setBool:enabled forKey:THETA_SHARED_MUTE_REEL_SHARES];
        THDebugLog(@"[Theta] mute reel shares: mirrored %d to the shared suite", enabled);
    }
}

void THRegisterMuteSharedReelNotificationsHooks(void) {
    static dispatch_queue_t queue;
    static bool pending;
    queue = dispatch_queue_create("theta.mute-shared-reel-mirror", DISPATCH_QUEUE_SERIAL);
    dispatch_async(queue, ^{ THMirrorMuteSharedReelSetting(); });
    /* queue:nil, not the main queue: with an observer queue, the posting thread blocks until the
       block has run there. Instagram writes defaults from background threads while holding its own
       locks, so a main-queue observer deadlocked the main thread against them (watchdog kills). */
    [[NSNotificationCenter defaultCenter] addObserverForName:NSUserDefaultsDidChangeNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(__unused NSNotification *note) {
        // Coalesce bursts of writes into one mirror pass.
        if (__atomic_exchange_n(&pending, true, __ATOMIC_ACQ_REL)) return;
        dispatch_async(queue, ^{
            __atomic_store_n(&pending, false, __ATOMIC_RELEASE);
            THMirrorMuteSharedReelSetting();
        });
    }];
}
