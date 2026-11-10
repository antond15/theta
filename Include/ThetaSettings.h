/**
 * Theta settings: key constants and typed accessors.
 *
 * Every setting is declared once in ThetaSettingsRegistry.m (type, default, title, flags).
 * Code refers to a setting only through the constants below, so a misspelled key fails to compile.
 * Values live in the standard defaults under "theta.<key>" (see ThetaSettingStorageKey).
 *
 * Key format: "<area>.<name>", snake_case. The area names the part of Instagram the setting
 * affects, not the settings page it is shown on, so pages can be reorganised freely.
 * Never change a key once shipped: add a migration in ThetaSettings.m instead.
 */
#ifndef ThetaSettings_h
#define ThetaSettings_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define THETA_SETTING_KEYS(X) \
    /* Theta itself */ \
    X(THAppShowBanners,                  "app.show_banners") \
    X(THAppLoadBanner,                   "app.load_banner") \
    X(THAppHaptics,                      "app.haptics") \
    X(THAppLock,                         "app.lock") \
    X(THAppShakeToOpen,                  "app.shake_to_open") \
    X(THAppClearCache,                   "app.clear_cache") \
    /* Tab bar and launch */ \
    X(THNavTabOrder,                     "nav.tab_order") \
    X(THNavSwipeBetweenTabs,             "nav.swipe_between_tabs") \
    X(THNavLaunchTab,                    "nav.launch_tab") \
    X(THNavHideFeedTab,                  "nav.hide_feed_tab") \
    X(THNavHideExploreTab,               "nav.hide_explore_tab") \
    X(THNavHideReelsTab,                 "nav.hide_reels_tab") \
    X(THNavHideMessagesTab,              "nav.hide_messages_tab") \
    X(THNavHideCreateTab,                "nav.hide_create_tab") \
    X(THNavMessengerMode,                "nav.messenger_mode") \
    /* Home feed */ \
    X(THFeedHideAds,                     "feed.hide_ads") \
    X(THFeedHideSuggestedPosts,          "feed.hide_suggested_posts") \
    X(THFeedHideSuggestedReels,          "feed.hide_suggested_reels") \
    X(THFeedHideSuggestedPeople,         "feed.hide_suggested_people") \
    X(THFeedHideThreadsCarousel,         "feed.hide_threads_carousel") \
    X(THFeedHideStoriesTray,             "feed.hide_stories_tray") \
    X(THFeedHideAllPosts,                "feed.hide_all_posts") \
    X(THFeedHideEndFooter,               "feed.hide_end_footer") \
    X(THFeedHideRepostButton,            "feed.hide_repost_button") \
    /* Explore and search */ \
    X(THExploreHideGrid,                 "explore.hide_grid") \
    X(THExploreHideRecentSearches,       "explore.hide_recent_searches") \
    /* Direct messages */ \
    X(THDMKeepDeleted,                   "dm.keep_deleted") \
    X(THDMDeletedColor,                  "dm.deleted_color") \
    X(THDMSeenButton,                    "dm.seen_button") \
    X(THDMAutoSeenUsers,                 "dm.auto_seen_users") \
    X(THDMSeenOnTyping,                  "dm.seen_on_typing") \
    X(THDMSeenOnReact,                   "dm.seen_on_react") \
    X(THDMSeenOnSend,                    "dm.seen_on_send") \
    X(THDMPrivateMediaGhost,             "dm.private_media_ghost") \
    X(THDMHideTypingIndicator,           "dm.hide_typing_indicator") \
    X(THDMBypassCharLimit,               "dm.bypass_char_limit") \
    X(THDMSaveAudioMessages,             "dm.save_audio_messages") \
    X(THDMUploadAudioMessages,           "dm.upload_audio_messages") \
    X(THDMSendFiles,                     "dm.send_files") \
    X(THDMHideSharedReelThumbnails,      "dm.hide_shared_reel_thumbnails") \
    X(THDMHideSharedPostThumbnails,      "dm.hide_shared_post_thumbnails") \
    X(THDMMuteSharedReelNotifications,   "dm.mute_shared_reel_notifications") \
    X(THDMHideCreateGroupButton,         "dm.hide_create_group_button") \
    X(THDMHideBlendButton,               "dm.hide_blend_button") \
    X(THDMHideCallButtons,               "dm.hide_call_buttons") \
    X(THDMFullLastActive,                "dm.full_last_active") \
    /* Stories */ \
    X(THStoryGhost,                      "story.ghost") \
    X(THStoryGhostUsers,                 "story.ghost_users") \
    X(THStorySeenOnReply,                "story.seen_on_reply") \
    X(THStorySeenLocalOnly,              "story.seen_local_only") \
    X(THStorySkipOnSeen,                 "story.skip_on_seen") \
    X(THStoryMentionsButton,             "story.mentions_button") \
    X(THStoryDisableAutoAdvance,         "story.disable_auto_advance") \
    /* Reels */ \
    X(THReelsTapAction,                  "reels.tap_action") \
    X(THReelsAlwaysShowScrubber,         "reels.always_show_scrubber") \
    X(THReelsDisableScrolling,           "reels.disable_scrolling") \
    X(THReelsBypassPassword,             "reels.bypass_password") \
    /* Instants */ \
    X(THInstantsSaveButton,              "instants.save_button") \
    X(THInstantsGhost,                   "instants.ghost") \
    /* Live */ \
    X(THLiveNoViewerPolling,             "live.no_viewer_polling") \
    X(THLiveCommentsToggle,              "live.comments_toggle") \
    /* Saving media */ \
    X(THSaveMethod,                      "save.method") \
    X(THSaveMediaButton,                 "save.media_button") \
    X(THSaveProfilePictures,             "save.profile_pictures") \
    X(THSaveProfilePosts,                "save.profile_posts") \
    X(THSaveAudioNotes,                  "save.audio_notes") \
    /* Viewing media */ \
    X(THMediaFullscreenPosts,            "media.fullscreen_posts") \
    X(THMediaFullscreenProfilePictures,  "media.fullscreen_profile_pictures") \
    /* Profiles */ \
    X(THProfileFollowStatusIndicator,    "profile.follow_status_indicator") \
    X(THProfileAnalyzerPage,             "profile.analyzer") \
    /* Comments */ \
    X(THCommentsOptionsButton,           "comments.options_button") \
    /* Links */ \
    X(THLinksOpenExternally,             "links.open_externally") \
    X(THLinksStripTracking,              "links.strip_tracking") \
    /* Confirmations before an action */ \
    X(THConfirmLike,                     "confirm.like") \
    X(THConfirmFollow,                   "confirm.follow") \
    X(THConfirmCall,                     "confirm.call") \
    X(THConfirmExploreRefresh,           "confirm.explore_refresh") \
    X(THConfirmCreateGroup,              "confirm.create_group") \
    X(THConfirmVanishMode,               "confirm.vanish_mode") \
    /* Privacy */ \
    X(THPrivacySuppressScreenshotAlerts, "privacy.suppress_screenshot_alerts") \
    X(THPrivacyHideThetaInScreenshots,   "privacy.hide_theta_in_screenshots") \
    /* Appearance */ \
    X(THUIDateFormat,                    "ui.date_format") \
    X(THUILiquidGlassButtons,            "ui.liquid_glass_buttons") \
    X(THUILiquidGlassSurfaces,           "ui.liquid_glass_surfaces") \
    X(THUISaveButtonColor,               "ui.save_button_color") \
    X(THUISeenButtonColor,               "ui.seen_button_color") \
    X(THUIMentionsButtonColor,           "ui.mentions_button_color") \
    X(THUIResetColors,                   "ui.reset_colors")

#define THETA_DECLARE_SETTING_KEY(name, key) FOUNDATION_EXPORT NSString *const name;
THETA_SETTING_KEYS(THETA_DECLARE_SETTING_KEY)
#undef THETA_DECLARE_SETTING_KEY

/** The NSUserDefaults key a setting is stored under: "theta.<key>". */
FOUNDATION_EXPORT NSString *ThetaSettingStorageKey(NSString *key);

/** On/off value (the registry default when unset). Cached; safe in hot hooks and on any thread. */
FOUNDATION_EXPORT BOOL ThetaSettingEnabled(NSString *key);
#define ENABLED(key) ThetaSettingEnabled(key)

/** Selected option id of a choice setting, e.g. @"folder". Never nil for a choice setting. */
FOUNDATION_EXPORT NSString *ThetaSettingChoice(NSString *key);
FOUNDATION_EXPORT BOOL ThetaSettingChoiceIs(NSString *key, NSString *optionId);

/** Color setting: the stored color, else the registry default. */
FOUNDATION_EXPORT UIColor *ThetaSettingColor(NSString *key);

/** List setting (lowercase usernames). Empty array when unset. */
FOUNDATION_EXPORT NSArray<NSString *> *ThetaSettingList(NSString *key);

FOUNDATION_EXPORT void ThetaSettingSetEnabled(NSString *key, BOOL enabled);
FOUNDATION_EXPORT void ThetaSettingSetChoice(NSString *key, NSString *optionId);
FOUNDATION_EXPORT void ThetaSettingSetColor(NSString *key, UIColor *color);
FOUNDATION_EXPORT void ThetaSettingSetList(NSString *key, NSArray<NSString *> *list);

/** Removes the stored value, so the setting reads as its default. */
FOUNDATION_EXPORT void ThetaSettingReset(NSString *key);

/** Runs the one-time migration from title-based keys. Called by every accessor; idempotent. */
FOUNDATION_EXPORT void ThetaSettingsPrepare(void);

#endif
