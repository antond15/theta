#import "Include/ThetaSettingsRegistry.h"

@implementation THSettingOption
- (instancetype)initWithIdentifier:(NSString *)identifier title:(NSString *)title {
    if ((self = [super init])) {
        _identifier = [identifier copy];
        _title = [title copy];
    }
    return self;
}
@end

@interface THSettingDefinition ()
- (instancetype)initWithType:(THSettingType)type key:(NSString *)key title:(NSString *)title detail:(NSString *)detail extra:(NSDictionary *)extra;
@end

/* Keys of `extra` in the definitions below. */
static NSString *const kInfo = @"info";            // NSString: text behind the info button
static NSString *const kDefault = @"default";      // default value (see THSettingDefinition.defaultValue)
static NSString *const kOptions = @"options";      // choice: @[@[id, title], …]; default is the first
static NSString *const kRestart = @"restart";      // @YES: needs an app restart
static NSString *const kBiometrics = @"biometrics";// @YES: needs Face ID / Touch ID / passcode
static NSString *const kMinIG = @"minIG";          // NSString: lowest supported Instagram version
static NSString *const kViewController = @"vc";    // page: view controller class name

static NSComparisonResult THCompareVersions(NSString *a, NSString *b) {
    NSArray<NSString *> *pa = [a componentsSeparatedByString:@"."], *pb = [b componentsSeparatedByString:@"."];
    for (NSUInteger i = 0; i < MAX(pa.count, pb.count); i++) {
        NSInteger x = i < pa.count ? pa[i].integerValue : 0, y = i < pb.count ? pb[i].integerValue : 0;
        if (x != y) return x < y ? NSOrderedAscending : NSOrderedDescending;
    }
    return NSOrderedSame;
}

@implementation THSettingDefinition

- (instancetype)initWithType:(THSettingType)type key:(NSString *)key title:(NSString *)title detail:(NSString *)detail extra:(NSDictionary *)extra {
    if ((self = [super init])) {
        _type = type;
        _key = [key copy];
        _title = [title copy];
        _detail = [detail copy];
        _info = [extra[kInfo] copy];
        _restartRequired = [extra[kRestart] boolValue];
        _requiresBiometrics = [extra[kBiometrics] boolValue];
        _minimumInstagramVersion = [extra[kMinIG] copy];
        _viewControllerClassName = [extra[kViewController] copy];

        NSMutableArray *options = [NSMutableArray array];
        for (NSArray *pair in extra[kOptions]) {
            [options addObject:[[THSettingOption alloc] initWithIdentifier:pair[0] title:pair[1]]];
        }
        _options = options.count ? options : nil;

        id def = extra[kDefault];
        if (!def && type == THSettingTypeToggle) def = @NO;
        if (!def && type == THSettingTypeChoice) def = [_options.firstObject identifier];
        if (!def && type == THSettingTypeList) def = @[];
        _defaultValue = def;
    }
    return self;
}

- (BOOL)storesValue {
    return _type != THSettingTypeAction && _type != THSettingTypePage;
}

- (NSArray<NSString *> *)optionTitles {
    return [_options valueForKey:@"title"] ?: @[];
}

- (NSInteger)indexOfOption:(NSString *)identifier {
    if (![identifier isKindOfClass:[NSString class]]) return NSNotFound;
    for (NSUInteger i = 0; i < _options.count; i++) {
        if ([_options[i].identifier isEqualToString:identifier]) return (NSInteger)i;
    }
    return NSNotFound;
}

- (BOOL)availableOnThisVersion {
    if (!_minimumInstagramVersion.length) return YES;
    NSString *running = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (!running.length) return YES;
    return THCompareVersions(running, _minimumInstagramVersion) != NSOrderedAscending;
}

static THSettingDefinition *Toggle(NSString *key, NSString *title, NSString *detail, NSDictionary *extra) {
    return [[THSettingDefinition alloc] initWithType:THSettingTypeToggle key:key title:title detail:detail extra:extra];
}
static THSettingDefinition *Choice(NSString *key, NSString *title, NSString *detail, NSDictionary *extra) {
    return [[THSettingDefinition alloc] initWithType:THSettingTypeChoice key:key title:title detail:detail extra:extra];
}
static THSettingDefinition *Color(NSString *key, NSString *title, NSString *detail, NSDictionary *extra) {
    return [[THSettingDefinition alloc] initWithType:THSettingTypeColor key:key title:title detail:detail extra:extra];
}
static THSettingDefinition *List(NSString *key, NSString *title, NSString *detail, NSDictionary *extra) {
    return [[THSettingDefinition alloc] initWithType:THSettingTypeList key:key title:title detail:detail extra:extra];
}
static THSettingDefinition *Action(NSString *key, NSString *title, NSString *detail) {
    return [[THSettingDefinition alloc] initWithType:THSettingTypeAction key:key title:title detail:detail extra:nil];
}
static THSettingDefinition *Page(NSString *key, NSString *title, NSString *detail, NSDictionary *extra) {
    return [[THSettingDefinition alloc] initWithType:THSettingTypePage key:key title:title detail:detail extra:extra];
}

static NSString *const kRestartInfo = @"Requires an app restart to take effect.";

+ (NSArray<THSettingDefinition *> *)allDefinitions {
    static NSArray *all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        all = @[
            // Theta itself
            Toggle(THAppLoadBanner, @"Load Banner", @"When Theta loads, see a banner.", nil),
            Toggle(THAppShowBanners, @"Show Banners", @"Upon certain actions, show a banner.", nil),
            Toggle(THAppHaptics, @"Haptic Feedback", @"Enables haptic feedback for certain actions.", nil),
            Toggle(THAppLock, @"Lock Instagram", @"Protect Instagram with Face ID/passcode.", @{kBiometrics: @YES}),
            Toggle(THAppShakeToOpen, @"Shake To Open", @"Open Theta's settings with a shake.", nil),
            Action(THAppClearCache, @"Clear App Cache", @"Clear all cached files and data."),

            // Tab bar and launch
            Choice(THNavTabOrder, @"Tab Icon Order", @"Reorder the tab bar icons.", @{
                kOptions: @[@[@"default", @"Default"], @[@"classic", @"Classic"], @[@"standard", @"Standard"], @[@"alternate", @"Alternate"]],
                kInfo: @"Requires an app restart to take effect.\n\nClassic: Feed · Explore · Create · Reels · Profile\nStandard: Feed · Explore · Reels · Messages · Profile\nAlternate: Feed · Reels · Create · Messages · Profile"}),
            Choice(THNavSwipeBetweenTabs, @"Swipe Between Tabs", @"Control whether you can swipe horizontally to switch between tabs.", @{
                kOptions: @[@[@"default", @"Default"], @[@"enabled", @"Enabled"], @[@"disabled", @"Disabled"]]}),
            Choice(THNavLaunchTab, @"Launch Tab", @"Choose which tab the app opens to on launch.", @{
                kOptions: @[@[@"default", @"Default"], @[@"home", @"Home"], @[@"explore", @"Explore"], @[@"reels", @"Reels"], @[@"messages", @"Messages"], @[@"profile", @"Profile"]]}),
            Toggle(THNavHideFeedTab, @"Hide Feed Tab", @"Removes the Home/Feed tab from the tab bar.", @{kInfo: kRestartInfo, kRestart: @YES}),
            Toggle(THNavHideExploreTab, @"Hide Explore Tab", @"Removes the Explore tab from the tab bar.", @{kInfo: kRestartInfo, kRestart: @YES}),
            Toggle(THNavHideReelsTab, @"Hide Reels Tab", @"GET RID OF THE BRAINROT.", @{kInfo: kRestartInfo, kRestart: @YES}),
            Toggle(THNavHideMessagesTab, @"Hide Messages Tab", @"Removes the Direct Messages tab from the tab bar.", @{kInfo: kRestartInfo, kRestart: @YES}),
            Toggle(THNavHideCreateTab, @"Hide Create Tab/Button", @"Hides the create tab and button.", @{kRestart: @YES}),
            Toggle(THNavMessengerMode, @"Messenger Mode", @"Only Profile and Direct tabs; long-press the messages tab for Theta settings.", @{
                kInfo: @"Hides all other tab bar items and swipe surfaces except Profile and Direct messages. When enabled, open Theta settings with a long press on the Direct messages tab (home tab long press is restored to Instagram's default). Requires an app restart.",
                kRestart: @YES}),

            // Home feed
            Toggle(THFeedHideAds, @"Disable Ads", @"Removes all ads from the app.", nil),
            Toggle(THFeedHideSuggestedPosts, @"Hide Suggested Posts", @"Inline suggested rails and previews.", nil),
            Toggle(THFeedHideSuggestedReels, @"Hide Suggested Reels", @"Reels preview row.", nil),
            Toggle(THFeedHideSuggestedPeople, @"Hide People You May Know", @"Suggested people carousels.", nil),
            Toggle(THFeedHideThreadsCarousel, @"Hide Threads Carousel", @"Threads promos in feed.", nil),
            Toggle(THFeedHideStoriesTray, @"Hide Home Stories", @"Top story tray on home.", nil),
            Toggle(THFeedHideAllPosts, @"Mute Entire Home Feed", @"Blank feed list; keeps chrome.", nil),
            Toggle(THFeedHideEndFooter, @"Hide End-of-Feed Footer", @"Clears end-of-feed suggestion text.", nil),
            Toggle(THFeedHideRepostButton, @"Hide Repost Button", @"Hides the repost button in the feed/reels.", nil),

            // Explore and search
            Toggle(THExploreHideGrid, @"Hide Explore Grid", @"Hides the explore grid view.", @{kRestart: @YES}),
            Toggle(THExploreHideRecentSearches, @"Hide Recent Searches", @"Hide the recent searches in the search tab.", nil),

            // Direct messages
            Toggle(THDMKeepDeleted, @"Keep Deleted Messages", @"Keep messages even after deletion.", @{
                kInfo: @"Whenever messages are deleted (either from yourself or the other person), they will be kept locally as long as you don't refresh your chat feed.\n\nDeleted messages will be colored with the color you choose below.",
                kMinIG: @"313.0.3"}),
            Color(THDMDeletedColor, @"Deleted Message Color", @"Choose the color used for deleted messages.", @{kDefault: [UIColor systemRedColor]}),
            Toggle(THDMSaveAudioMessages, @"Save Audio Messages", @"Save audio messages to device.", @{
                kInfo: @"When enabled, you will be able to download audio messages after they have finished playing."}),
            Toggle(THDMUploadAudioMessages, @"Upload Audio Messages", @"Upload audio messages.", @{
                kInfo: @"When enabled, whenever you press the voice message button, you will get a dialog asking if you want to upload audio from a video that's in your camera roll or record a new one."}),
            Toggle(THDMBypassCharLimit, @"Bypass Character Limit", @"Bypass the character limit in messages.", nil),
            Toggle(THDMHideTypingIndicator, @"Hide Typing Indicator", @"Recipients won't know you're typing.", nil),
            Toggle(THDMHideSharedReelThumbnails, @"Hide Shared Reel Thumbnails", @"Hide reel preview images in DMs.", @{
                kInfo: @"Shared reels keep their play button, account details and icons while the thumbnail image is replaced. Tap the message to open the reel."}),
            Toggle(THDMHideSharedPostThumbnails, @"Hide Shared Post Thumbnails", @"Hide shared post images and caption previews in DMs.", @{
                kInfo: @"Shared posts keep their account details and icons while the thumbnail image and caption preview are hidden. Tap the message to open the post."}),
            Toggle(THDMMuteSharedReelNotifications, @"Mute Shared Reel Notifications", @"No notification when someone sends you a reel.", @{
                kInfo: @"Messages with a reel shared from the Reels tab no longer alert you. They still arrive in your inbox. Other messages, including posts and stories, notify as usual."}),
            Toggle(THDMSeenButton, @"Mark As Seen", @"Mark messages as seen with a button.", nil),
            List(THDMAutoSeenUsers, @"Mark As Seen Auto-Mark List", @"Users in this list: their DMs are marked seen automatically.", @{
                kInfo: @"Users in this list will be auto-marked as seen in DMs.\n\nTo add someone, tap + and enter their username, or use the list toggle button next to the eye icon in a DM thread (Mark As Seen setting must be enabled).\n\nIf the button above doesn't work, you may need a kickstart to this by manually adding the user to this list. Then when you send/receive a message from them, the button should work."}),
            Toggle(THDMSeenOnTyping, @"Seen On Typing", @"Mark messages as seen when typing.", nil),
            Toggle(THDMSeenOnReact, @"Seen On React", @"Mark messages as seen when reacting.", nil),
            Toggle(THDMSeenOnSend, @"Seen On Send", @"Mark messages as seen when sending.", nil),
            Toggle(THDMPrivateMediaGhost, @"Private Media Ghost", @"Manually mark photos/videos in DMs as seen.", nil),
            Toggle(THConfirmVanishMode, @"Disappearing DM Confirmation", @"Confirm disappearing messages.", @{
                kInfo: @"When enabled and swiping up in a DM to toggle disappearing messages, a confirmation will be asked before enabling/disabling disappearing messages."}),
            Toggle(THDMHideCreateGroupButton, @"Hide \"Create Group\" Button", @"Hides the Create Group button.", @{
                kInfo: @"When selecting multiple recipients to send a post/reel to, the Create Group button will be hidden."}),
            Toggle(THConfirmCreateGroup, @"Create Group Confirmation", @"Asks before creating a group.", @{
                kInfo: @"When selecting multiple recipients to send a post/reel to, a confirmation will be asked before creating a group."}),
            Toggle(THDMHideBlendButton, @"Hide Blend Button", @"Hide the 'Blend' button in DMs.", nil),
            Toggle(THDMHideCallButtons, @"Hide Call Buttons", @"Hide the audio and video call buttons in DMs.", nil),
            Toggle(THDMFullLastActive, @"Full Last Active Date", @"Replaces 'Active Xm ago' with the exact date and time in DM conversations.", @{
                kInfo: @"Shows the full timestamp (e.g. 'May 13 at 2:45 PM') instead of the relative 'Active X minutes ago' text in DM conversation headers."}),
            Toggle(THDMSendFiles, @"Send Files", @"Adds a 'Send File' option to the DM plus menu to send any file from your device.", @{
                kInfo: @"When enabled, a 'Send File' button appears in the DM composer plus menu. Tapping it opens a document picker so you can send any file type directly in a DM thread."}),

            // Live
            Toggle(THLiveNoViewerPolling, @"Live Without Viewer List", @"Stop IG from polling viewer counts during live broadcasts (you remain anonymous in the attendee list mechanics).", nil),
            Toggle(THLiveCommentsToggle, @"Live Comments Sheet Toggle", @"While watching a live story, long-press the heart to hide or reveal the floating comment strip for this session only.", @{
                kInfo: @"This only affects layout on your device until you leave the live. Useful if you want a cleaner stage without losing quick access."}),

            // Stories
            Toggle(THStoryGhost, @"Story Ghost", @"Manually mark stories as seen.", nil),
            List(THStoryGhostUsers, @"Story Ghost Auto-Mark List", @"Users in this list: their stories are marked seen when you view.", @{
                kInfo: @"Users in this list will be auto-marked as seen in Story Ghost when you view their stories (unless you enable Skip On Seen).\n\nTo add someone, tap + and enter their username, or long-press the Story Ghost seen button on their story (Story Ghost setting must be enabled)."}),
            Toggle(THStorySeenOnReply, @"Story Seen On Reply", @"Mark stories as seen when replying to a story.", nil),
            Toggle(THStorySeenLocalOnly, @"Seen Receipts Stay Local", @"Keep story rings cleared on this phone but pause server-side seen receipts.", @{
                kInfo: @"Shows a phone icon on the story overlay (with Save / Ghost / mentions). Tap marks the current slide seen only on this device; long-press marks every slide in this reel the same way. Works alongside Story Ghost—the eye is for normal mark-as-seen; the phone icon is always local-only."}),
            Toggle(THStorySkipOnSeen, @"Skip On Seen", @"Skip to the next story when marked as seen.", nil),
            Toggle(THStoryMentionsButton, @"See Story Mentions", @"Use a button to see who is mentioned in a story.", nil),
            Toggle(THStoryDisableAutoAdvance, @"Disable Auto Advance", @"Turn off the annoying auto advance.", nil),

            // Saving media
            Toggle(THSaveMediaButton, @"Save Media", @"Save media to your camera roll.", nil),
            Choice(THSaveMethod, @"Save Method", @"Save media to camera roll or local folder.", @{
                kOptions: @[@[@"camera_roll", @"Camera Roll"], @[@"folder", @"Folder"]]}),
            Toggle(THSaveProfilePictures, @"Save Profile Pictures", @"Save profile pictures to your camera roll.", @{
                kInfo: @"When enabled, you will be able to long press on a profile picture to get an alert asking if you want to save the profile picture."}),
            Toggle(THSaveProfilePosts, @"Save Profile Posts", @"Bulk save profile posts.", @{
                kInfo: @"When enabled, you will see a pink save button on a user's profile page. Tap it and it will gather all loaded posts and will either save them to your camera roll or save them to a local folder.\n\nThe save button will only be able to gather posts that are actively loaded. If you want to save everything, make sure to scroll all the way to the bottom of the user's profile and tap the save button."}),
            Toggle(THSaveAudioNotes, @"Save Audio Notes", @"Save audio notes to your device.", nil),

            // Instants
            Toggle(THInstantsSaveButton, @"Save Instants", @"Save Instants while viewing them.", @{
                kInfo: @"When enabled, a save button appears while viewing an Instant (Quick Snap). Tap it to download the current photo or video using your Save Method (camera roll or local folder)."}),
            Toggle(THInstantsGhost, @"Instant Ghost", @"View Instants without marking them seen.", @{
                kInfo: @"When enabled, opening Instants will not mark them seen. An eye button appears next to Save on the Instant viewer; tap it to mark only the Instant you are currently viewing."}),

            // Viewing media
            Toggle(THMediaFullscreenPosts, @"Fullscreen Posts", @"View posts in fullscreen mode.", nil),
            Toggle(THMediaFullscreenProfilePictures, @"Fullscreen Profile Pictures", @"View profile pictures in fullscreen mode.", @{
                kInfo: @"When enabled, you will be able to long press on a profile picture to get an alert asking if you want to view the profile picture in fullscreen mode."}),

            // Reels
            Choice(THReelsTapAction, @"Tap Controls", @"Choose what a single tap does while watching a reel.", @{
                kOptions: @[@[@"default", @"Default"], @[@"pause_play", @"Pause/Play"], @[@"mute", @"Mute"]]}),
            Toggle(THReelsAlwaysShowScrubber, @"Always Show Scrubber", @"Always show the progress scrubber on reels, regardless of video length.", @{
                kInfo: @"By default Instagram only shows the progress scrubber on longer videos. This forces it to always appear so you can seek in any reel."}),
            Toggle(THReelsBypassPassword, @"Bypass Reel Password", @"Bypass reels that require a password.", @{
                kInfo: @"When enabled and you view a reel that requires a password, you will see a button to bypass the password requirement."}),
            Toggle(THReelsDisableScrolling, @"Disable Scrolling Reels", @"GET RID OF THE BRAINROT 2.", nil),

            // Profiles
            Page(THProfileAnalyzerPage, @"Profile Analyzer", @"Track who follows and unfollows you.", @{
                kViewController: @"THProfileAnalyzerViewController",
                kInfo: @"Scans your current followers and following lists and compares them to the last scan. Results show new followers, unfollowers, who you followed/unfollowed, mutual followers, and who doesn't follow you back. Data is stored locally. Scan history (from the analyzer screen) supports clearing all, swipe-to-delete for a single snapshot, or Compare mode to delete several at once. Requests are paced to reduce Instagram throttling; very large lists (13,000+ total) may still be limited by Instagram."}),
            Toggle(THProfileFollowStatusIndicator, @"Follow Status Indicator", @"Indicates if a user follows you.", @{
                kInfo: @"When enabled, you will see a \"✅\" or \"❌\" next to a user's name on their profile page based on whether they follow you or not."}),

            // Comments and links
            Toggle(THCommentsOptionsButton, @"Comment Options", @"Have some options when viewing a comment.", @{
                kInfo: @"When enabled, you will see a button on comments.\n\nIf there is media attached to the comment, you will see an options button. If there is no media attached to the comment, you will see a copy button."}),
            Toggle(THLinksOpenExternally, @"Open Links in External Browser", @"Opens links from Instagram in your default browser instead of the in-app browser.", nil),
            Toggle(THLinksStripTracking, @"Strip Tracking from Links", @"Removes tracking parameters (UTM, fbclid, igshid, etc.) from links before opening them.", nil),

            // Confirmations
            Toggle(THConfirmLike, @"Like Confirmation", @"Display an alert when you like a post.", nil),
            Toggle(THConfirmFollow, @"Follow Confirmation", @"Display an alert when you follow someone.", nil),
            Toggle(THConfirmCall, @"Call Confirmation", @"Display an alert when you call someone.", nil),
            Toggle(THConfirmExploreRefresh, @"Explore Refresh Confirmation", @"Confirm before refreshing the explore page.", nil),

            // Privacy
            Toggle(THPrivacySuppressScreenshotAlerts, @"Screenshot Suppression", @"Prevents screenshot and screen recording notifications.", nil),
            Toggle(THPrivacyHideThetaInScreenshots, @"Hide Theta From Screenshots", @"Hides Theta buttons from screenshots and screen recordings.", @{
                kInfo: @"When enabled, Theta UI elements (such as Mark as Seen, Save, Story Ghost buttons, etc.) will be invisible in screenshots and screen recordings, but still visible on screen."}),

            // Appearance
            Choice(THUIDateFormat, @"Date Format", @"Custom timestamp format for feed, notes, comments, stories, and DMs.", @{
                kOptions: @[@[@"default", @"Default"], @[@"short", @"Short"], @[@"medium", @"Medium"], @[@"12h", @"12h"], @[@"24h", @"24h"], @[@"iso", @"ISO"], @[@"iso_time", @"ISO+T"]]}),
            Toggle(THUILiquidGlassButtons, @"Enable Liquid Glass Buttons", @"Enables experimental liquid glass-style action buttons throughout the app.", @{
                kInfo: @"Requires an app restart to take effect. This feature relies on hidden Instagram experiments and may not work on all accounts or app versions.", kRestart: @YES}),
            Toggle(THUILiquidGlassSurfaces, @"Enable Liquid Glass Surfaces", @"Enables the floating liquid glass tab bar and other glassmorphic UI surfaces.", @{
                kInfo: @"Requires an app restart to take effect. This enables the floating tab bar and other surfaces powered by Instagram's Homecoming/Lucent navigation experiment.", kRestart: @YES}),
            Color(THUIMentionsButtonColor, @"Mentions Button Color", @"Choose the color used for mentions buttons.", nil),
            Color(THUISaveButtonColor, @"Save Button Color", @"Choose the color used for save buttons.", nil),
            Color(THUISeenButtonColor, @"Seen Button Color", @"Choose the color used for seen buttons.", nil),
            Action(THUIResetColors, @"Reset Colors", @"Reset all colors back to default."),
        ];
    });
    return all;
}

+ (NSDictionary<NSString *, THSettingDefinition *> *)definitionsByKey {
    static NSDictionary *byKey;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *map = [NSMutableDictionary dictionary];
        for (THSettingDefinition *def in [self allDefinitions]) {
            NSAssert(!map[def.key], @"Duplicate setting key %@", def.key);
            map[def.key] = def;
        }
        byKey = map;
    });
    return byKey;
}

+ (THSettingDefinition *)definitionForKey:(NSString *)key {
    return [key isKindOfClass:[NSString class]] ? [self definitionsByKey][key] : nil;
}

@end

#pragma mark - Pages

@implementation THSettingsPage

+ (instancetype)pageWithTitle:(NSString *)title detail:(NSString *)detail icon:(NSString *)icon keys:(NSArray<NSString *> *)keys {
    THSettingsPage *page = [THSettingsPage new];
    page->_title = [title copy];
    page->_detail = [detail copy];
    page->_iconName = [icon copy];
    NSMutableArray *settings = [NSMutableArray array];
    for (NSString *key in keys) {
        THSettingDefinition *def = [THSettingDefinition definitionForKey:key];
        NSAssert(def, @"Settings page %@ lists unknown key %@", title, key);
        if (def) [settings addObject:def];
    }
    page->_settings = settings;
    return page;
}

/* Where each setting is shown. Moving a setting between pages never touches its stored value. */
+ (NSArray<THSettingsPage *> *)allPages {
    static NSArray *pages;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pages = @[
            [self pageWithTitle:@"General" detail:@"General Theta behavior on Instagram." icon:@"gearshape" keys:@[
                THProfileAnalyzerPage, THPrivacySuppressScreenshotAlerts, THConfirmLike, THConfirmFollow, THConfirmCall,
                THFeedHideAds, THConfirmExploreRefresh, THCommentsOptionsButton, THUIDateFormat, THLinksOpenExternally,
                THLinksStripTracking, THUILiquidGlassButtons, THUILiquidGlassSurfaces]],
            [self pageWithTitle:@"Feed" detail:@"Hide suggested rails and promo rows." icon:@"rectangle.stack" keys:@[
                THFeedHideSuggestedPosts, THFeedHideSuggestedReels, THFeedHideSuggestedPeople, THFeedHideThreadsCarousel,
                THFeedHideStoriesTray, THFeedHideAllPosts, THFeedHideEndFooter]],
            [self pageWithTitle:@"Messages" detail:@"Settings related to Instagram messages." icon:@"message" keys:@[
                THDMKeepDeleted, THDMDeletedColor, THDMSaveAudioMessages, THDMUploadAudioMessages, THDMBypassCharLimit,
                THDMHideTypingIndicator, THDMHideSharedReelThumbnails, THDMHideSharedPostThumbnails,
                THDMMuteSharedReelNotifications, THDMSeenButton, THDMAutoSeenUsers, THDMSeenOnTyping, THDMSeenOnReact,
                THDMSeenOnSend, THDMPrivateMediaGhost, THConfirmVanishMode, THDMHideCreateGroupButton, THConfirmCreateGroup,
                THDMHideBlendButton, THDMHideCallButtons, THDMFullLastActive, THDMSendFiles]],
            [self pageWithTitle:@"Media" detail:@"Various media options for Theta." icon:@"photo" keys:@[
                THLiveNoViewerPolling, THLiveCommentsToggle, THStoryGhost, THStoryGhostUsers, THStorySeenOnReply,
                THStorySeenLocalOnly, THStorySkipOnSeen, THStoryMentionsButton, THSaveMediaButton, THInstantsSaveButton,
                THInstantsGhost, THSaveProfilePictures, THSaveProfilePosts, THSaveMethod, THSaveAudioNotes,
                THMediaFullscreenPosts, THMediaFullscreenProfilePictures, THStoryDisableAutoAdvance, THReelsBypassPassword,
                THReelsDisableScrolling]],
            [self pageWithTitle:@"Reels" detail:@"Tap controls, scrubber, and reel behavior." icon:@"play.rectangle" keys:@[
                THReelsTapAction, THReelsAlwaysShowScrubber]],
            [self pageWithTitle:@"Navigation" detail:@"Tab bar order, visibility, and launch behavior." icon:@"square.grid.2x2" keys:@[
                THNavTabOrder, THNavSwipeBetweenTabs, THNavLaunchTab, THNavHideFeedTab, THNavHideExploreTab,
                THNavHideReelsTab, THNavHideMessagesTab, THNavMessengerMode]],
            [self pageWithTitle:@"Interface" detail:@"Customize the interface of Instagram." icon:@"paintbrush" keys:@[
                THNavHideCreateTab, THExploreHideGrid, THExploreHideRecentSearches, THProfileFollowStatusIndicator,
                THFeedHideRepostButton, THPrivacyHideThetaInScreenshots, THUIMentionsButtonColor, THUISaveButtonColor,
                THUISeenButtonColor, THUIResetColors]],
            [self pageWithTitle:@"Miscellaneous" detail:@"Other settings and options." icon:@"ellipsis" keys:@[
                THAppLoadBanner, THAppShowBanners, THAppHaptics, THAppLock, THAppShakeToOpen, THAppClearCache]],
        ];
    });
    return pages;
}

@end

#pragma mark - Export / import

static NSString *THHexFromColor(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        const CGFloat *c = CGColorGetComponents(color.CGColor);
        size_t n = CGColorGetNumberOfComponents(color.CGColor);
        if (c && n >= 3) { r = c[0]; g = c[1]; b = c[2]; }
        else if (c && n >= 1) { r = g = b = c[0]; }
    }
    return [NSString stringWithFormat:@"%02X%02X%02X", (int)lrint(r * 255), (int)lrint(g * 255), (int)lrint(b * 255)];
}

static UIColor *THColorFromHex(NSString *hex) {
    if (![hex isKindOfClass:[NSString class]]) return nil;
    hex = [[hex stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    unsigned int rgb = 0;
    if (hex.length != 6 || ![[NSScanner scannerWithString:hex] scanHexInt:&rgb]) return nil;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

static NSString *const kExportFormat = @"theta-settings";
static const NSInteger kExportVersion = 2;

@implementation THSettingsTransfer

+ (NSDictionary *)exportDictionary {
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    for (THSettingDefinition *def in [THSettingDefinition allDefinitions]) {
        switch (def.type) {
            case THSettingTypeToggle: settings[def.key] = @(ThetaSettingEnabled(def.key)); break;
            case THSettingTypeChoice: settings[def.key] = ThetaSettingChoice(def.key); break;
            case THSettingTypeColor: settings[def.key] = THHexFromColor(ThetaSettingColor(def.key)); break;
            case THSettingTypeList: settings[def.key] = ThetaSettingList(def.key); break;
            default: break;
        }
    }
    return @{@"format": kExportFormat, @"version": @(kExportVersion), @"settings": settings};
}

/* Applies one value; YES when it was valid for the setting. */
static BOOL THApplyValue(THSettingDefinition *def, id value) {
    switch (def.type) {
        case THSettingTypeToggle:
            if (![value isKindOfClass:[NSNumber class]]) return NO;
            ThetaSettingSetEnabled(def.key, [value boolValue]);
            return YES;
        case THSettingTypeChoice:
            if ([def indexOfOption:value] == NSNotFound) return NO;
            ThetaSettingSetChoice(def.key, value);
            return YES;
        case THSettingTypeColor: {
            UIColor *color = THColorFromHex(value);
            if (!color) return NO;
            ThetaSettingSetColor(def.key, color);
            return YES;
        }
        case THSettingTypeList: {
            if (![value isKindOfClass:[NSArray class]]) return NO;
            NSMutableArray *list = [NSMutableArray array];
            for (id item in value) if ([item isKindOfClass:[NSString class]] && [item length]) [list addObject:[item lowercaseString]];
            ThetaSettingSetList(def.key, list);
            return YES;
        }
        default:
            return NO;
    }
}

/* Version 1 export: {"<page title>": [{"title", "enabled", "colorHex"?, "selectedIndex"?}, …]}. */
static NSUInteger THImportLegacy(NSDictionary *pages) {
    NSUInteger applied = 0;
    for (id entries in pages.allValues) {
        if (![entries isKindOfClass:[NSArray class]]) continue;
        for (NSDictionary *entry in entries) {
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            NSString *title = entry[@"title"];
            THSettingDefinition *def = [THSettingDefinition definitionForKey:ThetaSettingKeyForLegacyTitle(title)];
            id value = nil;
            switch (def.type) {
                case THSettingTypeToggle: value = entry[@"enabled"]; break;
                case THSettingTypeColor: value = entry[@"colorHex"]; break;
                case THSettingTypeChoice: {
                    NSNumber *index = entry[@"selectedIndex"];
                    if ([index isKindOfClass:[NSNumber class]]) value = ThetaSettingOptionForLegacyIndex(title, index.integerValue);
                    break;
                }
                default: break;
            }
            if (def && value && THApplyValue(def, value)) applied++;
        }
    }
    return applied;
}

+ (NSUInteger)importDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return 0;
    if (![dictionary[@"format"] isEqual:kExportFormat]) return THImportLegacy(dictionary);

    NSDictionary *settings = dictionary[@"settings"];
    if (![settings isKindOfClass:[NSDictionary class]]) return 0;
    __block NSUInteger applied = 0;
    [settings enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        THSettingDefinition *def = [THSettingDefinition definitionForKey:key];
        if (def && THApplyValue(def, value)) applied++;
    }];
    return applied;
}

/* User lists are kept: they are data the user built up, not preferences. */
+ (void)resetAll {
    for (THSettingDefinition *def in [THSettingDefinition allDefinitions]) {
        if (def.storesValue && def.type != THSettingTypeList) ThetaSettingReset(def.key);
    }
}

@end
