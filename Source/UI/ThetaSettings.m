#import "Include/ThetaSettings.h"
#import "Include/ThetaSettingsRegistry.h"
#import "Include/ThetaDebug.h"
#import <os/lock.h>
#import <stdatomic.h>

#define THETA_DEFINE_SETTING_KEY(name, key) NSString *const name = @key;
THETA_SETTING_KEYS(THETA_DEFINE_SETTING_KEY)
#undef THETA_DEFINE_SETTING_KEY

NSString *ThetaSettingStorageKey(NSString *key) {
    return [@"theta." stringByAppendingString:key ?: @""];
}

static THSettingDefinition *THDefinition(NSString *key, THSettingType type) {
    THSettingDefinition *def = [THSettingDefinition definitionForKey:key];
#if THETA_DEBUG
    if (!def) THDebugLog(@"Theta settings: unknown key %@", key);
    else if (def.type != type) THDebugLog(@"Theta settings: %@ read as type %ld, defined as %ld", key, (long)type, (long)def.type);
#endif
    return (def && def.type == type) ? def : nil;
}

#pragma mark - Migration

static NSString *const kSettingsVersionKey = @"theta.settings_version";
static const NSInteger kSettingsVersion = 2;

/* Version 1 stored "<title>_Enabled", "<title>_SegmentIndex" and "<title>_Color".
   This table is history: never edit an entry, only add. Choices list the option ids in the
   order their segment indexes used. Several titles may map to one key; the first one wins. */
static NSDictionary<NSString *, NSArray *> *THLegacyTitles(void) {
    static NSDictionary *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            @"Show Banners": @[THAppShowBanners],
            @"Load Banner": @[THAppLoadBanner],
            @"Haptic Feedback": @[THAppHaptics],
            @"Lock Instagram": @[THAppLock],
            @"Shake To Open": @[THAppShakeToOpen],
            @"Tab Icon Order": @[THNavTabOrder, @[@"default", @"classic", @"standard", @"alternate"]],
            @"Swipe Between Tabs": @[THNavSwipeBetweenTabs, @[@"default", @"enabled", @"disabled"]],
            @"Launch Tab": @[THNavLaunchTab, @[@"default", @"home", @"explore", @"reels", @"messages", @"profile"]],
            @"Hide Feed Tab": @[THNavHideFeedTab],
            @"Hide Explore Tab": @[THNavHideExploreTab],
            @"Hide Reels Tab": @[THNavHideReelsTab],
            @"Hide Messages Tab": @[THNavHideMessagesTab],
            @"Hide Create Tab/Button": @[THNavHideCreateTab],
            @"Messenger Mode": @[THNavMessengerMode],
            @"Disable Ads": @[THFeedHideAds],
            @"Hide Suggested Posts": @[THFeedHideSuggestedPosts],
            @"Hide Suggested Reels": @[THFeedHideSuggestedReels],
            @"Hide People You May Know": @[THFeedHideSuggestedPeople],
            @"Hide Threads Carousel": @[THFeedHideThreadsCarousel],
            @"Hide Home Stories": @[THFeedHideStoriesTray],
            @"Mute Entire Home Feed": @[THFeedHideAllPosts],
            @"Hide End-of-Feed Footer": @[THFeedHideEndFooter],
            @"Hide Repost Button": @[THFeedHideRepostButton],
            @"Hide Explore Grid": @[THExploreHideGrid],
            @"Hide Recent Searches": @[THExploreHideRecentSearches],
            @"Keep Deleted Messages": @[THDMKeepDeleted],
            @"Deleted Message Color": @[THDMDeletedColor],
            @"Mark As Seen": @[THDMSeenButton],
            @"Seen On Typing": @[THDMSeenOnTyping],
            @"Seen On React": @[THDMSeenOnReact],
            @"Seen On Send": @[THDMSeenOnSend],
            @"Private Media Ghost": @[THDMPrivateMediaGhost],
            @"Hide Typing Indicator": @[THDMHideTypingIndicator],
            @"Bypass Character Limit": @[THDMBypassCharLimit],
            @"Save Audio Messages": @[THDMSaveAudioMessages],
            @"Upload Audio Messages": @[THDMUploadAudioMessages],
            @"Send Files": @[THDMSendFiles],
            @"Hide Shared Reel Thumbnails": @[THDMHideSharedReelThumbnails],
            @"Hide Shared Post Thumbnails": @[THDMHideSharedPostThumbnails],
            @"Mute Shared Reel Notifications": @[THDMMuteSharedReelNotifications],
            @"Hide \"Create Group\" Button": @[THDMHideCreateGroupButton],
            @"Hide Blend Button": @[THDMHideBlendButton],
            @"Hide Call Buttons": @[THDMHideCallButtons],
            @"Full Last Active Date": @[THDMFullLastActive],
            @"Story Ghost": @[THStoryGhost],
            @"Story Seen On Reply": @[THStorySeenOnReply],
            @"Seen Receipts Stay Local": @[THStorySeenLocalOnly],
            @"Skip On Seen": @[THStorySkipOnSeen],
            @"See Story Mentions": @[THStoryMentionsButton],
            @"Disable Auto Advance": @[THStoryDisableAutoAdvance],
            @"Tap Controls": @[THReelsTapAction, @[@"default", @"pause_play", @"mute"]],
            @"Always Show Scrubber": @[THReelsAlwaysShowScrubber],
            @"Disable Scrolling Reels": @[THReelsDisableScrolling],
            @"Bypass Reel Password": @[THReelsBypassPassword],
            @"Save Instants": @[THInstantsSaveButton],
            @"Instant Ghost": @[THInstantsGhost],
            @"Live Without Viewer List": @[THLiveNoViewerPolling],
            @"Live Comments Sheet Toggle": @[THLiveCommentsToggle],
            @"Save Method": @[THSaveMethod, @[@"camera_roll", @"folder"]],
            @"Save Media": @[THSaveMediaButton],
            @"Save Profile Pictures": @[THSaveProfilePictures],
            @"Save Profile Posts": @[THSaveProfilePosts],
            @"Save Audio Notes": @[THSaveAudioNotes],
            @"Fullscreen Posts": @[THMediaFullscreenPosts],
            @"Fullscreen Profile Pictures": @[THMediaFullscreenProfilePictures],
            @"Follow Status Indicator": @[THProfileFollowStatusIndicator],
            @"Comment Options": @[THCommentsOptionsButton],
            @"Open Links in External Browser": @[THLinksOpenExternally],
            @"Strip Tracking from Links": @[THLinksStripTracking],
            @"Like Confirmation": @[THConfirmLike],
            @"Follow Confirmation": @[THConfirmFollow],
            @"Call Confirmation": @[THConfirmCall],
            @"Explore Refresh Confirmation": @[THConfirmExploreRefresh],
            @"Create Group Confirmation": @[THConfirmCreateGroup],
            @"Disappearing DM Confirmation": @[THConfirmVanishMode],
            @"Screenshot Suppression": @[THPrivacySuppressScreenshotAlerts],
            @"Hide Theta From Screenshots": @[THPrivacyHideThetaInScreenshots],
            @"Date Format": @[THUIDateFormat, @[@"default", @"short", @"medium", @"12h", @"24h", @"iso", @"iso_time"]],
            @"Enable Liquid Glass Buttons": @[THUILiquidGlassButtons],
            @"Enable Liquid Glass Surfaces": @[THUILiquidGlassSurfaces],
            @"Save Button Color": @[THUISaveButtonColor],
            @"Seen Button Color": @[THUISeenButtonColor],
            @"Mentions Button Color": @[THUIMentionsButtonColor],
            // Titles of even older builds, migrated to "Hide …" titles in HideFeedFiltering.m.
            @"Strip Inline Suggested Posts": @[THFeedHideSuggestedPosts],
            @"Strip Suggested Reels Strip": @[THFeedHideSuggestedReels],
            @"Strip People You Might Like": @[THFeedHideSuggestedPeople],
            @"Strip Threads Carousel In Feed": @[THFeedHideThreadsCarousel],
            @"Strip Home Stories Row": @[THFeedHideStoriesTray],
            @"Strip End of Feed Suggestion Footer": @[THFeedHideEndFooter],
        };
    });
    return table;
}

static NSArray<NSString *> *THLegacyOlderTitles(void) {
    return @[@"Strip Inline Suggested Posts", @"Strip Suggested Reels Strip", @"Strip People You Might Like",
             @"Strip Threads Carousel In Feed", @"Strip Home Stories Row", @"Strip End of Feed Suggestion Footer"];
}

/* Version 1 user lists, stored under their own keys. */
static NSDictionary<NSString *, NSString *> *THLegacyListKeys(void) {
    return @{
        @"Theta_MarkAsSeen_AutoMarkUserIds": THDMAutoSeenUsers,
        @"Theta_StoryGhost_AutoMarkUserIds": THStoryGhostUsers,
    };
}

NSString *ThetaSettingKeyForLegacyTitle(NSString *title) {
    NSArray *entry = [title isKindOfClass:[NSString class]] ? THLegacyTitles()[title] : nil;
    return entry.firstObject;
}

NSString *ThetaSettingOptionForLegacyIndex(NSString *title, NSInteger index) {
    NSArray *entry = [title isKindOfClass:[NSString class]] ? THLegacyTitles()[title] : nil;
    NSArray *ids = entry.count > 1 ? entry[1] : nil;
    return (index >= 0 && index < (NSInteger)ids.count) ? ids[index] : nil;
}

/* Copies one title's values into the new keys. Never overwrites a value that is already there. */
static void THMigrateLegacyTitle(NSUserDefaults *d, NSString *title, NSMutableArray<NSString *> *obsolete) {
    NSString *key = ThetaSettingKeyForLegacyTitle(title);
    THSettingDefinition *def = [THSettingDefinition definitionForKey:key];
    if (!def) return;
    NSString *storage = ThetaSettingStorageKey(key);
    NSString *enabledKey = [title stringByAppendingString:@"_Enabled"];
    NSString *indexKey = [title stringByAppendingString:@"_SegmentIndex"];
    NSString *colorKey = [title stringByAppendingString:@"_Color"];
    BOOL unset = [d objectForKey:storage] == nil;

    switch (def.type) {
        case THSettingTypeToggle:
            if (unset && [d objectForKey:enabledKey]) [d setBool:[d boolForKey:enabledKey] forKey:storage];
            break;
        case THSettingTypeChoice:
            if (unset && [d objectForKey:indexKey]) {
                NSString *option = ThetaSettingOptionForLegacyIndex(title, [d integerForKey:indexKey]);
                if (option) [d setObject:option forKey:storage];
            }
            break;
        case THSettingTypeColor: {
            id data = [d objectForKey:colorKey];
            if (unset && [data isKindOfClass:[NSData class]]) [d setObject:data forKey:storage];
            break;
        }
        default:
            break;
    }
    [obsolete addObjectsFromArray:@[enabledKey, indexKey, colorKey]];
}

static void THMigrateFromVersion1(NSUserDefaults *d) {
    NSMutableArray<NSString *> *obsolete = [NSMutableArray array];
    NSArray<NSString *> *older = THLegacyOlderTitles();
    // Current titles first: they hold the newer value when an older title is also present.
    for (NSString *title in THLegacyTitles()) {
        if (![older containsObject:title]) THMigrateLegacyTitle(d, title, obsolete);
    }
    for (NSString *title in older) THMigrateLegacyTitle(d, title, obsolete);

    [THLegacyListKeys() enumerateKeysAndObjectsUsingBlock:^(NSString *legacy, NSString *key, BOOL *stop) {
        id list = [d objectForKey:legacy];
        NSString *storage = ThetaSettingStorageKey(key);
        if ([list isKindOfClass:[NSArray class]] && ![d objectForKey:storage]) [d setObject:list forKey:storage];
        [obsolete addObject:legacy];
    }];

    for (NSString *legacy in obsolete) {
        if ([d objectForKey:legacy]) [d removeObjectForKey:legacy];
    }
}

#pragma mark - Cache

/* ENABLED() runs in hot hooks (layoutSubviews, cell configuration), and DBB swizzles
   -[NSUserDefaults objectForKey:] process-wide, so every uncached read goes through that hook.
   NSUserDefaultsDidChangeNotification is posted synchronously on the writing thread by every
   set/remove (including Theta's own), so a change is seen on the next read.
   No NSUserDefaults call is made while the lock is held, so the swizzle can't deadlock against it. */

static os_unfair_lock sThetaSettingsLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, NSNumber *> *sThetaSettingsCache;
static uint64_t sThetaSettingsGeneration;

/* 0 = not started, 1 = migrating, 2 = ready. Not dispatch_once: a defaults write during the
   migration can run observers on this thread that read settings again, which would deadlock.
   Reads that land while another thread migrates see defaults for that moment; each migration
   write clears the cache, so they are corrected on the next read. */
static atomic_int sThetaSettingsState;

void ThetaSettingsPrepare(void) {
    if (atomic_load_explicit(&sThetaSettingsState, memory_order_acquire) == 2) return;
    int expected = 0;
    if (!atomic_compare_exchange_strong(&sThetaSettingsState, &expected, 1)) return;

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

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d integerForKey:kSettingsVersionKey] < kSettingsVersion) {
        THMigrateFromVersion1(d);
        [d setInteger:kSettingsVersion forKey:kSettingsVersionKey];
    }
    atomic_store_explicit(&sThetaSettingsState, 2, memory_order_release);
}

#pragma mark - Accessors

BOOL ThetaSettingEnabled(NSString *key) {
    if (![key isKindOfClass:[NSString class]]) return NO;
    ThetaSettingsPrepare();

    os_unfair_lock_lock(&sThetaSettingsLock);
    NSNumber *cached = sThetaSettingsCache[key];
    uint64_t generation = sThetaSettingsGeneration;
    os_unfair_lock_unlock(&sThetaSettingsLock);
    if (cached) return cached.boolValue;

    THSettingDefinition *def = THDefinition(key, THSettingTypeToggle);
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey:ThetaSettingStorageKey(key)];
    BOOL enabled = [stored respondsToSelector:@selector(boolValue)] ? [stored boolValue] : [def.defaultValue boolValue];

    // Don't cache a value read while a write was landing; the next call reads it again.
    os_unfair_lock_lock(&sThetaSettingsLock);
    if (sThetaSettingsCache && generation == sThetaSettingsGeneration) sThetaSettingsCache[key] = @(enabled);
    os_unfair_lock_unlock(&sThetaSettingsLock);
    return enabled;
}

NSString *ThetaSettingChoice(NSString *key) {
    ThetaSettingsPrepare();
    THSettingDefinition *def = THDefinition(key, THSettingTypeChoice);
    if (!def) return @"";
    NSString *stored = [[NSUserDefaults standardUserDefaults] objectForKey:ThetaSettingStorageKey(key)];
    if ([stored isKindOfClass:[NSString class]] && [def indexOfOption:stored] != NSNotFound) return stored;
    return def.defaultValue ?: @"";
}

BOOL ThetaSettingChoiceIs(NSString *key, NSString *optionId) {
    return [ThetaSettingChoice(key) isEqualToString:optionId];
}

static UIColor *THUnarchiveColor(id data) {
    if (![data isKindOfClass:[NSData class]]) return nil;
    UIColor *color = nil;
    @try {
        color = [NSKeyedUnarchiver unarchivedObjectOfClass:[UIColor class] fromData:data error:nil];
    } @catch (__unused NSException *e) {}
    return [color isKindOfClass:[UIColor class]] ? color : nil;
}

UIColor *ThetaSettingColor(NSString *key) {
    ThetaSettingsPrepare();
    THSettingDefinition *def = THDefinition(key, THSettingTypeColor);
    UIColor *stored = THUnarchiveColor([[NSUserDefaults standardUserDefaults] objectForKey:ThetaSettingStorageKey(key)]);
    return stored ?: def.defaultValue ?: [UIColor labelColor];
}

NSArray<NSString *> *ThetaSettingList(NSString *key) {
    ThetaSettingsPrepare();
    THDefinition(key, THSettingTypeList);
    NSArray *stored = [[NSUserDefaults standardUserDefaults] objectForKey:ThetaSettingStorageKey(key)];
    if (![stored isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:stored.count];
    for (id item in stored) {
        if ([item isKindOfClass:[NSString class]] && [item length] > 0) [list addObject:[item lowercaseString]];
    }
    return list;
}

void ThetaSettingSetEnabled(NSString *key, BOOL enabled) {
    ThetaSettingsPrepare();
    if (!THDefinition(key, THSettingTypeToggle)) return;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:ThetaSettingStorageKey(key)];
}

void ThetaSettingSetChoice(NSString *key, NSString *optionId) {
    ThetaSettingsPrepare();
    THSettingDefinition *def = THDefinition(key, THSettingTypeChoice);
    if (!def || [def indexOfOption:optionId] == NSNotFound) return;
    [[NSUserDefaults standardUserDefaults] setObject:optionId forKey:ThetaSettingStorageKey(key)];
}

void ThetaSettingSetColor(NSString *key, UIColor *color) {
    ThetaSettingsPrepare();
    if (!THDefinition(key, THSettingTypeColor)) return;
    if (!color) { ThetaSettingReset(key); return; }
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:color requiringSecureCoding:YES error:nil];
    if (data) [[NSUserDefaults standardUserDefaults] setObject:data forKey:ThetaSettingStorageKey(key)];
}

void ThetaSettingSetList(NSString *key, NSArray<NSString *> *list) {
    ThetaSettingsPrepare();
    if (!THDefinition(key, THSettingTypeList)) return;
    [[NSUserDefaults standardUserDefaults] setObject:list ?: @[] forKey:ThetaSettingStorageKey(key)];
}

void ThetaSettingReset(NSString *key) {
    ThetaSettingsPrepare();
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:ThetaSettingStorageKey(key)];
}
