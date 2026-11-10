#import "Include/ThetaTweakCommon.h"
#import <objc/runtime.h>
#import <objc/message.h>

// Tap Controls segment index mapping:
// 0 = Default (no override)
// 1 = Pause/Play
// 2 = Mute toggle

static id (*orig_playbackConfig)(id self, SEL _cmd,
                                 id set,
                                 BOOL tapPauseEnabled,
                                 BOOL controls,
                                 BOOL previewThumbEnabled,
                                 long long minSec,
                                 double seekSec,
                                 double tapSec,
                                 long long duration,
                                 BOOL shortScrubberEnabled);

static id hook_playbackConfig(id self, SEL _cmd,
                               id set,
                               BOOL tapPauseEnabled,
                               BOOL controls,
                               BOOL previewThumbEnabled,
                               long long minSec,
                               double seekSec,
                               double tapSec,
                               long long duration,
                               BOOL shortScrubberEnabled) {
    NSString *tapAction = ThetaSettingChoice(THReelsTapAction);
    if ([tapAction isEqualToString:@"pause_play"]) {
        tapPauseEnabled = YES;
    } else if ([tapAction isEqualToString:@"mute"]) {
        tapPauseEnabled = NO;
    }

    if (ENABLED(THReelsAlwaysShowScrubber)) {
        minSec = 0;
        duration = 0;
        shortScrubberEnabled = YES;
    }

    return orig_playbackConfig(self, _cmd, set, tapPauseEnabled, controls, previewThumbEnabled,
                                minSec, seekSec, tapSec, duration, shortScrubberEnabled);
}

void THRegisterTapControlsHooks(void) {
    Class cls = objc_getClass("IGSundialPlaybackControlsTestConfiguration");
    if (!cls) return;

    SEL sel = @selector(initWithLauncherSet:tapToPauseEnabled:combineSingleTapPlaybackControls:isVideoPreviewThumbnailEnabled:minScrubberDurationSec:seekResumeScrubberCooldownSec:tapResumeScrubberCooldownSec:persistentScrubberMinVideoDuration:isScrubberForShortVideoEnabled:);
    NullHookMessageEx(cls, sel, (void *)hook_playbackConfig, &orig_playbackConfig);
}
