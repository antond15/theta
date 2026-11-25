#import "Include.h"
#import "Include/InstagramHeaders.h"
#import "Include/ThetaTweakCommon.h"
#import <objc/runtime.h>

@interface IGDiscoveryGridItem : NSObject
@property (nonatomic, readonly) id model;
@end

/* Feed list filtering; toggles use Theta wording. */

static NSArray *theta_removeAdsFromList(NSArray *list);

static BOOL theta_shouldRemoveSuggestedPosts(void) {
    return ENABLED(THFeedHideSuggestedPosts);
}
static BOOL theta_shouldRemoveSuggestedReelsCarousel(void) {
    return ENABLED(THFeedHideSuggestedReels);
}
static BOOL theta_shouldRemoveSuggestedAccounts(void) {
    return ENABLED(THFeedHideSuggestedPeople);
}
static BOOL theta_shouldRemoveThreadsCarousel(void) {
    return ENABLED(THFeedHideThreadsCarousel);
}
static BOOL theta_shouldHideStoriesTrayRow(void) {
    return ENABLED(THFeedHideStoriesTray);
}
static BOOL theta_shouldBlankHomeFeed(void) {
    return ENABLED(THFeedHideAllPosts);
}

NSArray *ThetaApplyHideFeedFiltering(NSArray *list, BOOL isMainFeed) {
    if (![list isKindOfClass:[NSArray class]] || list.count == 0)
        return list;

    NSArray *filtered = list;

    NSMutableArray *out = [NSMutableArray arrayWithCapacity:filtered.count];
    for (id obj in filtered) {
        @autoreleasepool {
            if (!obj) continue;

            if (isMainFeed && theta_shouldRemoveSuggestedPosts()) {
                NSString *grpTitle = nil;
                if ([obj isKindOfClass:%c(IGFeedGroupHeaderViewModel)] && [obj respondsToSelector:@selector(title)])
                    grpTitle = ((NSString *(*)(id, SEL))objc_msgSend)(obj, @selector(title));
                BOOL isExploreInFeed = NO;
                if ([obj isKindOfClass:%c(IGMedia)] && [obj respondsToSelector:@selector(explorePostInFeed)])
                    isExploreInFeed = [@YES isEqual:((id (*)(id, SEL))objc_msgSend)(obj, @selector(explorePostInFeed))];
                if (isExploreInFeed
                    || (grpTitle.length && [[grpTitle lowercaseString] isEqualToString:@"suggested posts"])) {
                    continue;
                }
                if ([obj isKindOfClass:%c(IGInFeedStoriesTrayModel)])
                    continue;
            }

            if (isMainFeed && theta_shouldRemoveSuggestedReelsCarousel()) {
                if ([obj isKindOfClass:%c(IGFeedScrollableClipsModel)])
                    continue;
            }

            if (theta_shouldRemoveSuggestedAccounts()) {
                if (isMainFeed && [obj isKindOfClass:%c(IGHScrollAYMFModel)])
                    continue;
                if ([obj isKindOfClass:%c(IGSuggestedUserInReelsModel)])
                    continue;
            }

            if (theta_shouldRemoveThreadsCarousel()) {
                if (isMainFeed) {
                    Class threadsCls = objc_getClass("IGThreadsInFeedModels.IGThreadsInFeedModel");
                    if ([obj isKindOfClass:%c(IGBloksFeedUnitModel)] || (threadsCls && [obj isKindOfClass:threadsCls]))
                        continue;
                }
                if ([obj isKindOfClass:%c(IGSundialNetegoItem)])
                    continue;
            }

            if (isMainFeed && theta_shouldHideStoriesTrayRow()) {
                if ([obj isKindOfClass:%c(IGStoryDataController)])
                    continue;
            }

            if (isMainFeed && theta_shouldBlankHomeFeed()) {
                if ([obj isKindOfClass:%c(IGPostCreationManager)]
                    || [obj isKindOfClass:%c(IGMedia)]
                    || [obj isKindOfClass:%c(IGEndOfFeedDemarcatorModel)]
                    || [obj isKindOfClass:%c(IGSpinnerLabelViewModel)]) {
                    continue;
                }
            }

            [out addObject:obj];
        }
    }

    NSUInteger n = out.count;
    if (isMainFeed && n <= 5) {
        NSMutableArray *noSpinner = [NSMutableArray array];
        for (id obj in out) {
            if (![obj isKindOfClass:[%c(IGSpinnerLabelViewModel) class]])
                [noSpinner addObject:obj];
        }
        out = noSpinner;
    }

    return [out copy];
}

static NSArray *theta_removeAdsFromList(NSArray *list) {
    if (!ENABLED(THFeedHideAds) || ![list isKindOfClass:[NSArray class]])
        return list;
    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:list.count];
    for (id obj in list) {
        if (!obj) continue;
        BOOL isAd = NO;
        if ([obj isKindOfClass:%c(IGFeedItem)] && ([obj performSelector:@selector(isSponsored)] || [obj performSelector:@selector(isSponsoredApp)]))
            isAd = YES;
        if ([obj isKindOfClass:%c(IGDiscoveryGridItem)] && [(IGDiscoveryGridItem *)obj respondsToSelector:@selector(model)]) {
            id model = [(IGDiscoveryGridItem *)obj model];
            if ([model isKindOfClass:%c(IGAdItem)]) isAd = YES;
        }
        if ([obj isKindOfClass:%c(IGAdItem)])
            isAd = YES;
        if (!isAd)
            [filteredObjs addObject:obj];
    }
    return [filteredObjs copy];
}

static NSArray *(*orig_sundialObjs)(id, SEL, id);
static NSArray *hook_sundialObjs(id self, SEL _cmd, id arg1) {
    NSArray *r = orig_sundialObjs ? orig_sundialObjs(self, _cmd, arg1) : nil;
    r = ThetaApplyHideFeedFiltering(r ?: @[], NO);
    if (ENABLED(THFeedHideAds))
        r = theta_removeAdsFromList(r);
    return r;
}

static NSArray *(*orig_ctxObjs)(id, SEL, id);
static NSArray *hook_ctxObjs(id self, SEL _cmd, id arg1) {
    NSArray *r = orig_ctxObjs(self, _cmd, arg1);
    if (!ENABLED(THFeedHideAds)) return r;
    return theta_removeAdsFromList(r);
}

static NSArray *(*orig_videoObjs)(id, SEL, id);
static NSArray *hook_videoObjs(id self, SEL _cmd, id arg1) {
    NSArray *r = orig_videoObjs(self, _cmd, arg1);
    if (!ENABLED(THFeedHideAds)) return r;
    return theta_removeAdsFromList(r);
}

static NSArray *(*orig_chainObjs)(id, SEL, id);
static NSArray *hook_chainObjs(id self, SEL _cmd, id arg1) {
    NSArray *r = orig_chainObjs(self, _cmd, arg1);
    if (!ENABLED(THFeedHideAds)) return r;
    return theta_removeAdsFromList(r);
}

static NSArray *(*orig_exploreObjs)(id, SEL, id);
static NSArray *hook_exploreObjs(id self, SEL _cmd, id arg1) {
    NSArray *r = orig_exploreObjs(self, _cmd, arg1);
    if (!ENABLED(THFeedHideAds)) return r;
    return theta_removeAdsFromList(r);
}

static void (*orig_endFeedCell)(id self, SEL _cmd, id arg1);
static void hook_endFeedCell(id self, SEL _cmd, id arg1) {
    orig_endFeedCell(self, _cmd, arg1);
    if (!ENABLED(THFeedHideEndFooter)) return;
    @try {
        id titleLabel = [self valueForKey:@"_titleLabel"];
        if (titleLabel && [titleLabel respondsToSelector:@selector(setText:)])
            [(id)titleLabel setText:@""];
    } @catch (__unused NSException *e) {}
}

/* Home stories tray: suggested accounts are reels whose owner you don't follow (IGUser followStatus 2).
 * Your own reel (also status 2) and multi-author reels stay; an owner Theta can't read stays. */
static BOOL theta_isSuggestedTrayReel(id vm) {
    if ([vm respondsToSelector:@selector(isCurrentUserReel)] && ((BOOL (*)(id, SEL))objc_msgSend)(vm, @selector(isCurrentUserReel)))
        return NO;
    id owner = ThetaValueForKey(vm, @"reelOwner");
    if ([ThetaValueForKey(owner, @"_subtype") integerValue] != 0) return NO;
    id user = ThetaValueForKey(owner, @"_userReelOwner_user");
    Class userClass = objc_getClass("IGUser");
    if (!userClass || ![user isKindOfClass:userClass] || ![user respondsToSelector:@selector(followStatus)]) return NO;
    return [(IGUser *)user followStatus] == 2;
}

static NSArray *(*orig_traySorted)(id, SEL, id, BOOL, NSInteger);
static NSArray *hook_traySorted(id self, SEL _cmd, id models, BOOL highlightsAtEnd, NSInteger refreshType) {
    NSArray *r = orig_traySorted(self, _cmd, models, highlightsAtEnd, refreshType);
    if (!ENABLED(THFeedHideSuggestedPeople) || ![r isKindOfClass:[NSArray class]]) return r;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:r.count];
    for (id vm in r) {
        if (!theta_isSuggestedTrayReel(vm)) [out addObject:vm];
    }
    return out.count == r.count ? r : [out copy];
}

void THRegisterHideFeedFilteringHooks(void) {
    NullHookMessageIfPresent(objc_getClass("IGStoryTrayModelsListBuilder"), @selector(sortedViewModels:highlightsCanAppearAtEndOfTray:refreshType:), (void *)hook_traySorted, &orig_traySorted);
    NullHookMessageIfPresent(objc_getClass("_TtC23IGSundialFeedDataSource23IGSundialFeedDataSource") ?: objc_getClass("IGSundialFeedDataSource"), @selector(objectsForListAdapter:), (void *)hook_sundialObjs, &orig_sundialObjs);
    NullHookMessageIfPresent(objc_getClass("_TtC30IGContextualFeedViewController30IGContextualFeedViewController") ?: objc_getClass("IGContextualFeedViewController"), @selector(objectsForListAdapter:), (void *)hook_ctxObjs, &orig_ctxObjs);
    NullHookMessageIfPresent(objc_getClass("IGVideoFeedViewController"), @selector(objectsForListAdapter:), (void *)hook_videoObjs, &orig_videoObjs);
    NullHookMessageIfPresent(objc_getClass("_TtC18IGPostChainingFeed28IGChainingFeedViewController") ?: objc_getClass("IGChainingFeedViewController"), @selector(objectsForListAdapter:), (void *)hook_chainObjs, &orig_chainObjs);
    NullHookMessageIfPresent(objc_getClass("_TtC28IGExploreViewControllerSwift26IGExploreListKitDataSource") ?: objc_getClass("IGExploreListKitDataSource"), @selector(objectsForListAdapter:), (void *)hook_exploreObjs, &orig_exploreObjs);
    NullHookMessageIfPresent(objc_getClass("IGEndOfFeedDemarcatorCellTopOfFeed"), @selector(configureWithViewConfig:), (void *)hook_endFeedCell, &orig_endFeedCell);
}
