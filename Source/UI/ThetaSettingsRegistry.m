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
static NSString *const kParent = @"parent";        // NSString: key of the parent setting (indentation only)

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
        _parentKey = [extra[kParent] copy];

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

+ (NSArray<THSettingDefinition *> *)allDefinitions {
    static NSArray *all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        all = @[
            // Theta itself
            Toggle(THAppShakeToOpen, @"Shake to Open", @"Shake your phone to open Theta, as well as long-pressing the home tab.", nil),
            Toggle(THAppShowBanners, @"Show Banners", @"Shows a banner to confirm actions such as saving or marking as seen.", nil),
            Toggle(THAppHaptics, @"Haptic Feedback", @"Vibrates briefly when a banner appears.", @{kParent: THAppShowBanners}),
            Toggle(THAppLoadBanner, @"Startup Banner", @"Shows the Theta and Instagram versions when Instagram opens.", nil),
            Action(THAppClearCache, @"Clear Cache", @"Deletes Instagram's cached files and temporary data."),
            Toggle(THAppLock, @"Lock Instagram", @"Asks for Face ID, Touch ID or your passcode when you open Instagram.", @{kBiometrics: @YES}),

            // Tab bar and launch
            Choice(THNavTabOrder, @"Tab Order", @"Arranges the tabs in one of Instagram's layouts.", @{
                kOptions: @[@[@"default", @"Default"], @[@"classic", @"Classic"], @[@"standard", @"Standard"], @[@"alternate", @"Alternate"]],
                kInfo: @"Classic: Home · Explore · Create · Reels · Profile\nStandard: Home · Explore · Reels · Messages · Profile\nAlternate: Home · Reels · Create · Messages · Profile",
                kRestart: @YES}),
            Choice(THNavSwipeBetweenTabs, @"Swipe Between Tabs", @"Switch tabs by swiping left or right.", @{
                kOptions: @[@[@"default", @"Default"], @[@"enabled", @"On"], @[@"disabled", @"Off"]]}),
            Choice(THNavLaunchTab, @"Open To", @"The tab Instagram shows when it opens. Not used in Messenger Mode.", @{
                kOptions: @[@[@"default", @"Default"], @[@"home", @"Home"], @[@"explore", @"Explore"], @[@"reels", @"Reels"], @[@"messages", @"Messages"], @[@"profile", @"Profile"]]}),
            Toggle(THNavHideFeedTab, @"Hide Home Tab", @"Removes Home from the tab bar.", @{kRestart: @YES}),
            Toggle(THNavHideExploreTab, @"Hide Explore Tab", @"Removes Explore from the tab bar.", @{kRestart: @YES}),
            Toggle(THNavHideReelsTab, @"Hide Reels Tab", @"Removes Reels from the tab bar.", @{kRestart: @YES}),
            Toggle(THNavHideMessagesTab, @"Hide Messages Tab", @"Removes Messages from the tab bar.", @{kRestart: @YES}),
            Toggle(THNavHideCreateTab, @"Hide Create Buttons", @"Removes the + buttons for new posts from the home and profile headers.", @{kRestart: @YES}),
            Toggle(THNavMessengerMode, @"Messenger Mode", @"Shows only the Messages and Profile tabs.", @{kRestart: @YES}),

            // Home feed
            Toggle(THFeedHideAds, @"Hide Ads", @"Removes sponsored posts from your feed, Reels and Explore.", nil),
            Toggle(THFeedHideSuggestedPosts, @"Hide Suggested Posts", @"Removes suggested posts from accounts you don't follow.", nil),
            Toggle(THFeedHideSuggestedReels, @"Hide Suggested Reels", @"Removes the row of suggested reels from your feed.", nil),
            Toggle(THFeedHideSuggestedPeople, @"Hide Suggested Accounts", @"Removes \"Suggested for you\" accounts from your feed and Reels.", nil),
            Toggle(THFeedHideThreadsCarousel, @"Hide Threads Posts", @"Removes Threads posts and promotions from your feed and Reels.", nil),
            Toggle(THFeedHideStoriesTray, @"Hide Stories Bar", @"Removes the row of stories at the top of your feed.", nil),
            Toggle(THFeedHideEndFooter, @"Hide \"You're All Caught Up\"", @"Removes the text that marks the end of new posts.", nil),
            Toggle(THFeedHideAllPosts, @"Hide All Posts", @"Leaves your home feed empty. Stories and the top bar stay.", nil),
            Toggle(THFeedHideRepostButton, @"Hide Repost Button", @"Removes the repost button from posts and reels.", nil),

            // Explore and search
            Toggle(THExploreHideGrid, @"Hide Explore Grid", @"Removes the grid of posts from Explore, leaving search.", @{kRestart: @YES}),
            Toggle(THExploreHideRecentSearches, @"Don't Save Recent Searches", @"Accounts you search for aren't added to Recent.", @{
                kInfo: @"Accounts already in Recent stay until you clear them in Instagram."}),

            // Direct messages
            Toggle(THDMSeenButton, @"Mark Seen Manually", @"Opening a chat doesn't mark it as seen. Tap the eye button to mark it.", @{
                kInfo: @"The eye button is at the top of each chat. The + button next to it adds the person to Always Mark Seen."}),
            Toggle(THDMSeenOnTyping, @"Mark Seen When Typing", @"Marks the chat as seen when you start typing.", @{kParent: THDMSeenButton}),
            Toggle(THDMSeenOnReact, @"Mark Seen When Reacting", @"Marks the chat as seen when you react to a message.", @{kParent: THDMSeenButton}),
            Toggle(THDMSeenOnSend, @"Mark Seen When Sending", @"Marks the chat as seen when you send a message.", @{kParent: THDMSeenButton}),
            List(THDMAutoSeenUsers, @"Always Mark Seen", @"Chats with these people are marked as seen as usual.", @{
                kParent: THDMSeenButton,
                kInfo: @"Chats with people on this list are marked as seen when you open them, as Instagram normally does.\n\nTo add someone, tap +, or tap the + button next to the eye in your chat with them."}),
            Toggle(THDMHideTypingIndicator, @"Hide Typing Indicator", @"Others don't see when you're typing.", nil),
            Toggle(THDMPrivateMediaGhost, @"Disappearing Media Ghost", @"Open disappearing photos and videos without marking them as seen.", @{
                kInfo: @"Adds an eye button to the viewer. Tap it to mark the photo or video as seen."}),
            Toggle(THDMKeepDeleted, @"Keep Unsent Messages", @"Messages that get unsent stay in the chat, highlighted.", @{
                kInfo: @"Works for messages unsent by either side. They disappear when Instagram reloads the chat.",
                kMinIG: @"313.0.3"}),
            Color(THDMDeletedColor, @"Highlight Color", @"The color of unsent messages.", @{kDefault: [UIColor systemRedColor], kParent: THDMKeepDeleted}),
            Toggle(THDMFullLastActive, @"Exact Last Active Time", @"Shows when someone was last active, like \"May 13 at 2:45 PM\", instead of \"Active 5m ago\".", nil),
            Toggle(THDMHideCallButtons, @"Hide Call Buttons", @"Removes the audio and video call buttons from the top of chats.", nil),
            Toggle(THDMHideBlendButton, @"Hide Blend Button", @"Removes the Blend button from the top of chats.", nil),
            Toggle(THDMSendFiles, @"Send Files", @"Adds Send File to the + menu in chats, for sending any file.", nil),
            Toggle(THDMUploadAudioMessages, @"Upload Voice Messages", @"Send audio from a video or file as a voice message.", @{
                kInfo: @"Tapping the microphone in a chat asks whether to use audio from a video in your library, from an audio file, or to record as usual."}),
            Toggle(THDMBypassCharLimit, @"Remove Character Limit", @"Lets you send messages longer than Instagram's limit.", nil),
            Toggle(THDMHideSharedReelThumbnails, @"Hide Shared Reel Thumbnails", @"Hides the preview image of reels shared in chats.", @{
                kInfo: @"The play button and account name stay. Tap the message to open the reel."}),
            Toggle(THDMHideSharedPostThumbnails, @"Hide Shared Post Thumbnails", @"Hides the image and caption of posts shared in chats.", @{
                kInfo: @"The account name stays. Tap the message to open the post."}),
            Toggle(THDMMuteSharedReelNotifications, @"Mute Shared Reel Notifications", @"Reels shared with you from the Reels tab arrive without a notification.", @{
                kInfo: @"They still arrive in your inbox. Other messages, including shared posts and stories, notify as usual."}),
            Toggle(THDMHideCreateGroupButton, @"Hide Create Group Button", @"Removes Create Group when you share to several people.", nil),
            Toggle(THDMSaveAudioMessages, @"Save Voice Messages", @"Offers to save a voice message after it finishes playing.", nil),

            // Stories
            Toggle(THStoryGhost, @"Story Ghost", @"Watch stories without marking them as seen.", @{
                kInfo: @"Adds an eye button to stories. Tap it to mark the story as seen. Long-press it to add or remove the account from Always Mark Seen."}),
            List(THStoryGhostUsers, @"Always Mark Seen", @"Stories from these accounts are marked as seen as usual.", @{
                kParent: THStoryGhost,
                kInfo: @"Stories from these accounts are marked as seen when you watch them, even with Story Ghost on.\n\nTo add an account, tap +, or long-press the eye button on one of their stories."}),
            Toggle(THStorySkipOnSeen, @"Skip After Marking Seen", @"Moves to the next story after a story is marked as seen with the eye or phone button.", @{kParent: THStoryGhost}),
            Toggle(THStorySeenLocalOnly, @"Mark Seen on This Device Only", @"Stories you watch clear on this device, but the account isn't told you saw them.", @{
                kInfo: @"Adds a phone button to stories. Tap it to mark the story as seen on this device only. Long-press it to do the same for all of the account's current stories.\n\nWith Story Ghost also on, the eye button still sends a normal seen receipt."}),
            Toggle(THStorySeenOnReply, @"Mark Seen When Replying", @"Marks a story as seen when you reply to it.", nil),
            Toggle(THStoryDisableAutoAdvance, @"Disable Auto-Advance", @"Stays on a story when it ends instead of moving to the next one.", nil),
            Toggle(THStoryMentionsButton, @"Mentions Button", @"Adds a button that lists the accounts mentioned in a story.", nil),

            // Instants
            Toggle(THInstantsGhost, @"Instants Ghost", @"Watch Instants without marking them as seen.", @{
                kInfo: @"Adds an eye button to the Instants viewer. Tap it to mark the Instant you're viewing as seen."}),
            Toggle(THInstantsSaveButton, @"Save Instants", @"Adds a save button to the Instants viewer.", nil),

            // Live
            Toggle(THLiveNoViewerPolling, @"Stop Viewer Count Updates", @"Stops refreshing the viewer count while you watch a live video.", nil),
            Toggle(THLiveCommentsToggle, @"Hide Live Comments", @"Long-press the heart in a live video to hide or show comments.", @{
                kInfo: @"Comments come back when you leave the live video. Only you see the change."}),

            // Reels
            Choice(THReelsTapAction, @"Tap Action", @"What a single tap does on a reel.", @{
                kOptions: @[@[@"default", @"Default"], @[@"pause_play", @"Pause"], @[@"mute", @"Mute"]]}),
            Toggle(THReelsAlwaysShowScrubber, @"Always Show Progress Bar", @"Shows the progress bar on every reel so you can seek, not only on long ones.", nil),
            Toggle(THReelsDisableScrolling, @"Disable Reels Scrolling", @"Stops swiping to the next reel, so only the reel you opened plays.", nil),
            Toggle(THReelsBypassPassword, @"Skip Reel Passwords", @"Adds a Bypass button to reels that ask for a password.", nil),

            // Saving and viewing media
            Choice(THSaveMethod, @"Save To", @"Where downloads go.", @{
                kOptions: @[@[@"camera_roll", @"Photos"], @[@"folder", @"Saved Media"]]}),
            Toggle(THSaveMediaButton, @"Download Button", @"Adds a download button to posts, reels, stories and disappearing photos in chats.", nil),
            Toggle(THMediaFullscreenPosts, @"Fullscreen Posts", @"Adds a button to posts for viewing them full screen.", nil),
            Toggle(THSaveProfilePictures, @"Save Profile Pictures", @"Long-press the picture at the top of a profile to save it.", nil),
            Toggle(THMediaFullscreenProfilePictures, @"Fullscreen Profile Pictures", @"Long-press the picture at the top of a profile to view it full screen.", nil),
            Toggle(THSaveProfilePosts, @"Save Profile Posts", @"Adds a button to profiles that saves all loaded posts.", @{
                kInfo: @"Only posts that have loaded are saved. To save all of them, scroll to the end of the profile first."}),
            Toggle(THSaveAudioNotes, @"Save Music from Stickers", @"Long-press a music sticker to save its audio.", nil),

            // Profiles
            Page(THProfileAnalyzerPage, @"Profile Analyzer", @"See who followed and unfollowed you.", @{kViewController: @"THProfileAnalyzerViewController"}),
            Toggle(THProfileFollowStatusIndicator, @"Show If They Follow You", @"Adds ✅ or ❌ after the name on a profile.", nil),

            // Comments and links
            Toggle(THCommentsOptionsButton, @"Comment Actions", @"Adds a button to comments for copying text or saving media.", @{
                kInfo: @"Comments with only text get a copy button. Comments with a photo or GIF get a menu to save it, copy its link or copy the GIF name."}),
            Toggle(THLinksOpenExternally, @"Open Links in Browser", @"Opens links in your default browser instead of Instagram's.", nil),
            Toggle(THLinksStripTracking, @"Remove Link Tracking", @"Removes tracking parameters such as utm, fbclid and igshid from links you open.", nil),

            // Confirmations
            Toggle(THConfirmLike, @"Confirm Likes", @"Asks before liking a post or reel, including with a double tap.", nil),
            Toggle(THConfirmFollow, @"Confirm Follows", @"Asks before following an account.", nil),
            Toggle(THConfirmCall, @"Confirm Calls", @"Asks before starting an audio or video call.", nil),
            Toggle(THConfirmCreateGroup, @"Confirm New Groups", @"Asks before creating a group when you share to several people.", nil),
            Toggle(THConfirmVanishMode, @"Confirm Disappearing Messages", @"Asks before turning disappearing messages on or off.", nil),
            Toggle(THConfirmExploreRefresh, @"Confirm Explore Refresh", @"Asks before pulling to refresh Explore.", nil),

            // Privacy
            Toggle(THPrivacySuppressScreenshotAlerts, @"Silent Screenshots", @"Others aren't notified of your screenshots or recordings, and protected photos can be captured.", nil),
            Toggle(THPrivacyHideThetaInScreenshots, @"Hide Theta in Screenshots", @"Theta's buttons don't appear in screenshots or screen recordings.", @{kRestart: @YES}),

            // Appearance
            Choice(THUIDateFormat, @"Date Format", @"How dates appear on posts, comments, stories, notes and messages.", @{
                kOptions: @[@[@"default", @"Default"], @[@"short", @"Mar 14"], @[@"medium", @"Mar 14, 2026"], @[@"12h", @"Mar 14 at 2:45 PM"],
                            @[@"24h", @"Mar 14 at 14:45"], @[@"iso", @"2026-03-14"], @[@"iso_time", @"2026-03-14 14:45"]]}),
            Toggle(THUILiquidGlassButtons, @"Liquid Glass Buttons", @"Gives Instagram's buttons the glass look.", @{kRestart: @YES}),
            Toggle(THUILiquidGlassSurfaces, @"Liquid Glass Tab Bar", @"Uses the floating glass tab bar and other glass surfaces.", @{kRestart: @YES}),
            Color(THUISaveButtonColor, @"Download Button Color", @"Used on stories, Instants and disappearing photos.", nil),
            Color(THUISeenButtonColor, @"Seen Button Color", @"Used for the eye and phone buttons on stories, Instants and disappearing photos.", nil),
            Color(THUIMentionsButtonColor, @"Mentions Button Color", @"Used for the mentions button on stories.", nil),
            Action(THUIResetColors, @"Reset Colors", @"Restores the default colors, including the unsent message highlight."),
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

@implementation THSettingsSection

+ (instancetype)sectionWithHeader:(NSString *)header footer:(NSString *)footer keys:(NSArray<NSString *> *)keys {
    THSettingsSection *section = [THSettingsSection new];
    section->_header = [header copy];
    section->_footer = [footer copy];
    NSMutableArray *settings = [NSMutableArray array];
    for (NSString *key in keys) {
        THSettingDefinition *def = [THSettingDefinition definitionForKey:key];
        NSAssert(def, @"Settings section %@ lists unknown key %@", header, key);
        if (def) [settings addObject:def];
    }
    section->_settings = settings;
    return section;
}

@end

static THSettingsSection *Section(NSString *header, NSString *footer, NSArray<NSString *> *keys) {
    return [THSettingsSection sectionWithHeader:header footer:footer keys:keys];
}

@implementation THSettingsPage

+ (instancetype)pageWithTitle:(NSString *)title detail:(NSString *)detail icon:(NSString *)icon sections:(NSArray<THSettingsSection *> *)sections {
    THSettingsPage *page = [THSettingsPage new];
    page->_title = [title copy];
    page->_detail = [detail copy];
    page->_iconName = [icon copy];
    page->_sections = [sections copy];
    NSMutableArray *settings = [NSMutableArray array];
    for (THSettingsSection *section in sections) [settings addObjectsFromArray:section.settings];
    page->_settings = settings;
    return page;
}

- (THSettingsSection *)sectionForSetting:(THSettingDefinition *)setting {
    for (THSettingsSection *section in _sections) {
        if ([section.settings containsObject:setting]) return section;
    }
    return nil;
}

/* Where each setting is shown. Moving a setting between pages never touches its stored value. */
+ (NSArray<NSArray<THSettingsPage *> *> *)pageGroups {
    static NSArray *groups;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        THSettingsPage *feed = [self pageWithTitle:@"Feed & Explore" detail:@"Hide ads, suggestions and clutter." icon:@"house" sections:@[
            Section(nil, nil, @[THFeedHideAds]),
            Section(@"Home Feed", nil, @[THFeedHideSuggestedPosts, THFeedHideSuggestedReels, THFeedHideSuggestedPeople,
                                          THFeedHideThreadsCarousel, THFeedHideStoriesTray, THFeedHideEndFooter, THFeedHideAllPosts]),
            Section(@"Posts and Comments", nil, @[THFeedHideRepostButton, THCommentsOptionsButton]),
            Section(@"Explore and Search", nil, @[THExploreHideGrid, THExploreHideRecentSearches]),
        ]];
        THSettingsPage *stories = [self pageWithTitle:@"Stories" detail:@"Story Ghost, Instants and live videos." icon:@"circle.dashed" sections:@[
            Section(@"Seen Receipts", @"With Story Ghost on, watching a story doesn't tell the account you saw it. Tap the eye button on a story to mark it seen.",
                    @[THStoryGhost, THStoryGhostUsers, THStorySkipOnSeen, THStorySeenLocalOnly, THStorySeenOnReply]),
            Section(@"Viewing", nil, @[THStoryDisableAutoAdvance, THStoryMentionsButton]),
            Section(@"Instants", nil, @[THInstantsGhost]),
            Section(@"Live Videos", nil, @[THLiveNoViewerPolling, THLiveCommentsToggle]),
        ]];
        THSettingsPage *reels = [self pageWithTitle:@"Reels" detail:@"Tap action, progress bar and scrolling." icon:@"play.rectangle" sections:@[
            Section(nil, nil, @[THReelsTapAction, THReelsAlwaysShowScrubber, THReelsDisableScrolling, THReelsBypassPassword]),
        ]];
        THSettingsPage *messages = [self pageWithTitle:@"Messages" detail:@"Read receipts, unsent messages and chat tools." icon:@"message" sections:@[
            Section(@"Read Receipts", @"If any option here is on, opening a chat no longer marks it as seen. Chats with people on your Always Mark Seen list work as usual.",
                    @[THDMSeenButton, THDMSeenOnTyping, THDMSeenOnReact, THDMSeenOnSend, THDMAutoSeenUsers]),
            Section(@"Privacy", nil, @[THDMHideTypingIndicator, THDMPrivateMediaGhost]),
            Section(@"Unsent Messages", nil, @[THDMKeepDeleted, THDMDeletedColor]),
            Section(@"Chat Screen", nil, @[THDMFullLastActive, THDMHideCallButtons, THDMHideBlendButton]),
            Section(@"Sending", nil, @[THDMSendFiles, THDMUploadAudioMessages, THDMBypassCharLimit]),
            Section(@"Shared Posts and Reels", nil, @[THDMHideSharedReelThumbnails, THDMHideSharedPostThumbnails,
                                                       THDMMuteSharedReelNotifications, THDMHideCreateGroupButton]),
        ]];
        THSettingsPage *profiles = [self pageWithTitle:@"Profiles" detail:@"Profile Analyzer and follow status." icon:@"person.crop.circle" sections:@[
            Section(nil, @"Compares your followers and following with your last scan: new followers, unfollowers, mutuals, and who doesn't follow you back. Scans are stored on this device. Instagram may limit scans of very large lists (over 13,000 accounts).",
                    @[THProfileAnalyzerPage]),
            Section(nil, nil, @[THProfileFollowStatusIndicator]),
        ]];
        THSettingsPage *downloads = [self pageWithTitle:@"Downloads" detail:@"Save posts, stories, reels and audio." icon:@"arrow.down.circle" sections:@[
            Section(nil, @"Saved Media is Theta's own folder. Open it with the folder button at the top of Theta settings.", @[THSaveMethod]),
            Section(@"Posts, Reels and Stories", @"Download and Fullscreen share one button next to Share on posts.",
                    @[THSaveMediaButton, THMediaFullscreenPosts, THInstantsSaveButton]),
            Section(@"Profiles", nil, @[THSaveProfilePictures, THMediaFullscreenProfilePictures, THSaveProfilePosts]),
            Section(@"Audio", nil, @[THDMSaveAudioMessages, THSaveAudioNotes]),
        ]];
        THSettingsPage *privacy = [self pageWithTitle:@"Privacy" detail:@"App lock, screenshots and links." icon:@"hand.raised" sections:@[
            Section(nil, nil, @[THAppLock]),
            Section(@"Screenshots", nil, @[THPrivacySuppressScreenshotAlerts, THPrivacyHideThetaInScreenshots]),
            Section(@"Links", nil, @[THLinksOpenExternally, THLinksStripTracking]),
        ]];
        THSettingsPage *confirmations = [self pageWithTitle:@"Confirmations" detail:@"Ask before liking, following, calling and more." icon:@"questionmark.circle" sections:@[
            Section(@"Ask Before", nil, @[THConfirmLike, THConfirmFollow, THConfirmCall, THConfirmCreateGroup, THConfirmVanishMode, THConfirmExploreRefresh]),
        ]];
        THSettingsPage *navigation = [self pageWithTitle:@"Navigation" detail:@"Tabs, launch tab and Messenger Mode." icon:@"dock.rectangle" sections:@[
            Section(@"Tab Bar", nil, @[THNavTabOrder, THNavSwipeBetweenTabs, THNavLaunchTab]),
            Section(@"Hide Tabs", @"Restart Instagram after changing these.",
                    @[THNavHideFeedTab, THNavHideExploreTab, THNavHideReelsTab, THNavHideMessagesTab, THNavHideCreateTab]),
            Section(@"Messenger Mode", @"In Messenger Mode, long-press the Messages tab to open Theta. Long-pressing Home works as it does in Instagram.",
                    @[THNavMessengerMode]),
        ]];
        THSettingsPage *appearance = [self pageWithTitle:@"Appearance" detail:@"Date format, Liquid Glass and button colors." icon:@"paintbrush" sections:@[
            Section(nil, nil, @[THUIDateFormat]),
            Section(@"Liquid Glass", @"Needs iOS 26 and a restart. These turn on Instagram experiments that may not work on every account or version.",
                    @[THUILiquidGlassButtons, THUILiquidGlassSurfaces]),
            Section(@"Button Colors", nil, @[THUISaveButtonColor, THUISeenButtonColor, THUIMentionsButtonColor, THUIResetColors]),
        ]];
        THSettingsPage *theta = [self pageWithTitle:@"Theta" detail:@"Banners, shake to open and cache." icon:@"gearshape" sections:@[
            Section(@"Opening Theta", @"You can always open Theta by long-pressing the Home tab.", @[THAppShakeToOpen]),
            Section(@"Banners", nil, @[THAppShowBanners, THAppHaptics, THAppLoadBanner]),
            Section(@"Storage", nil, @[THAppClearCache]),
        ]];
        groups = @[
            @[feed, stories, reels, messages, profiles],
            @[downloads, privacy, confirmations, navigation, appearance],
            @[theta],
        ];

#if DEBUG || THETA_DEBUG
        // Every setting appears exactly once.
        NSCountedSet *placed = [NSCountedSet set];
        for (NSArray *group in groups) for (THSettingsPage *page in group) [placed addObjectsFromArray:[page.settings valueForKey:@"key"]];
        for (THSettingDefinition *def in [THSettingDefinition allDefinitions]) {
            NSAssert([placed countForObject:def.key] == 1, @"Setting %@ is placed %lu times", def.key, (unsigned long)[placed countForObject:def.key]);
        }
#endif
    });
    return groups;
}

+ (NSArray<THSettingsPage *> *)allPages {
    return [[self pageGroups] valueForKeyPath:@"@unionOfArrays.self"];
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
