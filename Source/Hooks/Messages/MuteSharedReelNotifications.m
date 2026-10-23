/* The NSE does the muting (ThetaNSE.m); it can't read the app's defaults, so copy the toggle
   into the shared suite on launch and on every defaults change. */
static void THMirrorMuteSharedReelSetting(void) {
    NSUserDefaults *shared = [[NSUserDefaults alloc] initWithSuiteName:THETA_SHARED_SUITE];
    // Not ENABLED(): its cache may not have seen this change yet.
    BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"Mute Shared Reel Notifications_Enabled"];
    // Only write on a change: the write posts NSUserDefaultsDidChangeNotification again.
    if ([shared boolForKey:THETA_SHARED_MUTE_REEL_SHARES] != enabled)
        [shared setBool:enabled forKey:THETA_SHARED_MUTE_REEL_SHARES];
}

void THRegisterMuteSharedReelNotificationsHooks(void) {
    THMirrorMuteSharedReelSetting();
    [[NSNotificationCenter defaultCenter] addObserverForName:NSUserDefaultsDidChangeNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *note) {
        THMirrorMuteSharedReelSetting();
    }];
}
