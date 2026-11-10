/* Replace only the image; Instagram owns the surrounding controls and decoration. */
static char THSharedThumbnailHiddenKey;
static char THSharedThumbnailOriginalKey;
static char THSharedThumbnailModelKey;
static char THSharedThumbnailFreshKey;
static char THSharedCaptionHiddenKey;

static UIImage *THSharedThumbnailPlaceholder(void) {
    static UIImage *image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), YES, 1);
        [[UIColor colorWithWhite:0.15 alpha:1] setFill];
        UIRectFill(CGRectMake(0, 0, 1, 1));
        image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    return image;
}

static UIImage *THSharedThumbnailImage(UIImageView *view, UIImage *image) {
    if (![objc_getAssociatedObject(view, &THSharedThumbnailHiddenKey) boolValue]) return image;
    if (image != THSharedThumbnailPlaceholder()) {
        objc_setAssociatedObject(view, &THSharedThumbnailOriginalKey, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &THSharedThumbnailFreshKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return THSharedThumbnailPlaceholder();
}

static void (*orig_THSharedSetImage)(UIImageView *, SEL, UIImage *);
static void hook_THSharedSetImage(UIImageView *self, SEL _cmd, UIImage *image) {
    orig_THSharedSetImage(self, _cmd, THSharedThumbnailImage(self, image));
}

/* IGImageView's async loader uses this path, including HDR rendering. */
static void (*orig_THSharedShowImage)(UIImageView *, SEL, UIImage *, NSInteger);
static void hook_THSharedShowImage(UIImageView *self, SEL _cmd, UIImage *image, NSInteger state) {
    orig_THSharedShowImage(self, _cmd, THSharedThumbnailImage(self, image), state);
}

static BOOL THSharedPreviewURL(id value, BOOL reels) {
    NSString *string = [value isKindOfClass:NSURL.class] ? [value absoluteString] : value;
    if (![string isKindOfClass:NSString.class]) return NO;
    NSURLComponents *url = [NSURLComponents componentsWithString:string];
    if ([url.scheme.lowercaseString isEqualToString:@"instagram"])
        return [(reels ? @[@"clips", @"reel", @"reels"] : @[@"media"]) containsObject:url.host.lowercaseString];
    NSString *host = url.host.lowercaseString;
    return ([host isEqualToString:@"instagram.com"] || [host hasSuffix:@".instagram.com"])
        && (reels ? ([url.path hasPrefix:@"/reel/"] || [url.path hasPrefix:@"/reels/"]) : [url.path hasPrefix:@"/p/"]);
}

/* XMA payloads vary by server experiment. Inspect only known media/navigation fields,
   never captions (which can mention reels on an ordinary post). */
static BOOL THSharedPreviewModel(id model, NSUInteger depth, BOOL reels) {
    if (!model || depth > 3) return NO;
    id productType = ThetaValueForKey(model, @"productType");
    if ([productType isKindOfClass:NSString.class] && [(reels ? @[@"clips"] : @[@"feed", @"carousel_container"]) containsObject:productType]) return YES;
    for (NSString *key in @[@"actionURL", @"url", @"tapURL"])
        if (THSharedPreviewURL(ThetaValueForKey(model, key), reels)) return YES;
    for (NSString *key in @[@"media", @"imageTapInfo", @"navigationInfo", @"mediaResolverContext", @"message", @"messageCellViewModel"])
        if (THSharedPreviewModel(ThetaValueForKey(model, key), depth + 1, reels)) return YES;
    return NO;
}

static void THUpdateSharedThumbnail(UIView *cell, NSString *modelKey, NSString *previewKey) {
    BOOL hideReels = ENABLED(@"Hide Shared Reel Thumbnails");
    BOOL hidePosts = ENABLED(@"Hide Shared Post Thumbnails");
    id model = (hideReels || hidePosts) ? ThetaValueForKey(cell, modelKey) : nil;
    id cellModel = ThetaValueForKey(model, @"messageCellViewModel");
    id outgoing = ThetaValueForKey(cellModel, @"isOutgoing");
    if (!outgoing) outgoing = ThetaValueForKey(ThetaValueForKey(cellModel, @"sortingInfo"), @"isOutgoing");
    // A reel can also use the generic instagram://media navigation URL.
    BOOL reel = model && THSharedPreviewModel(model, 0, YES);
    BOOL post = model && !reel && THSharedPreviewModel(model, 0, NO);
    BOOL hidePost = ![outgoing boolValue] && hidePosts && post;
    BOOL hide = hidePost || (![outgoing boolValue] && hideReels && reel);
    id preview = ThetaValueForKey(cell, previewKey);
    id imageView = [preview isKindOfClass:[UIImageView class]] ? preview : ThetaValueForKey(preview, @"photoImageView");
    if ([imageView isKindOfClass:[UIImageView class]]) {
        BOOL wasHidden = [objc_getAssociatedObject(imageView, &THSharedThumbnailHiddenKey) boolValue];
        if (hide) {
            if (!wasHidden) {
                objc_setAssociatedObject(imageView, &THSharedThumbnailOriginalKey, [imageView image], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(imageView, &THSharedThumbnailHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [imageView setImage:THSharedThumbnailPlaceholder()];
            } else if ([imageView image] != THSharedThumbnailPlaceholder()) {
                // The image arrived through a path the hooks don't cover.
                objc_setAssociatedObject(imageView, &THSharedThumbnailOriginalKey, [imageView image], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(imageView, &THSharedThumbnailFreshKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [imageView setImage:THSharedThumbnailPlaceholder()];
            }
            objc_setAssociatedObject(imageView, &THSharedThumbnailModelKey, model, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(imageView, &THSharedThumbnailFreshKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else if (wasHidden) {
            // After cell reuse the stored original belongs to the previous message; let Instagram reload instead.
            BOOL keep = objc_getAssociatedObject(imageView, &THSharedThumbnailModelKey) == model
                || [objc_getAssociatedObject(imageView, &THSharedThumbnailFreshKey) boolValue];
            UIImage *original = keep ? objc_getAssociatedObject(imageView, &THSharedThumbnailOriginalKey) : nil;
            for (char *key : (char *[]){&THSharedThumbnailHiddenKey, &THSharedThumbnailOriginalKey, &THSharedThumbnailModelKey, &THSharedThumbnailFreshKey})
                objc_setAssociatedObject(imageView, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [imageView setImage:original];
        }
    }
    // Keep author/name/icon views visible; these fields contain only caption text.
    for (NSString *key in @[@"_footerCaptionTextLabel", @"commentLabelView", @"_bodyTextLabel", @"_xmaFooterView._bodyLabel"]) {
        id captionValue = cell;
        for (NSString *component in [key componentsSeparatedByString:@"."])
            captionValue = ThetaValueForKey(captionValue, component);
        UIView *caption = captionValue;
        if (![caption isKindOfClass:[UIView class]]) continue;
        if (hidePost) {
            if (!objc_getAssociatedObject(caption, &THSharedCaptionHiddenKey))
                objc_setAssociatedObject(caption, &THSharedCaptionHiddenKey, @(caption.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            caption.hidden = YES;
        } else {
            NSNumber *hidden = objc_getAssociatedObject(caption, &THSharedCaptionHiddenKey);
            if (hidden) {
                caption.hidden = hidden.boolValue;
                objc_setAssociatedObject(caption, &THSharedCaptionHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }
}

static void (*orig_THReelPortraitLayout)(UIView *, SEL);
static void hook_THReelPortraitLayout(UIView *self, SEL _cmd) {
    orig_THReelPortraitLayout(self, _cmd);
    THUpdateSharedThumbnail(self, @"_viewModel", @"imageView");
}
static void (*orig_THReelHscrollLayout)(UIView *, SEL);
static void hook_THReelHscrollLayout(UIView *self, SEL _cmd) {
    orig_THReelHscrollLayout(self, _cmd);
    THUpdateSharedThumbnail(self, @"_itemViewModel", @"previewImageView");
}
static void (*orig_THReelLayeredLayout)(UIView *, SEL);
static void hook_THReelLayeredLayout(UIView *self, SEL _cmd) {
    orig_THReelLayeredLayout(self, _cmd);
    THUpdateSharedThumbnail(self, @"viewModel", @"imageView");
}

void THRegisterHideSharedReelThumbnailsHooks(void) {
    NullHookMessageEx(objc_getClass("IGImageView"), @selector(setImage:), (void *)hook_THSharedSetImage, &orig_THSharedSetImage);
    NullHookMessageEx(objc_getClass("IGImageView"), NSSelectorFromString(@"_showImage:withDisplayState:"), (void *)hook_THSharedShowImage, &orig_THSharedShowImage);
    NullHookMessageEx(objc_getClass("IGDirectPortraitXMAMessageBubbleView"), @selector(layoutSubviews), (void *)hook_THReelPortraitLayout, &orig_THReelPortraitLayout);
    NullHookMessageEx(objc_getClass("IGDirectHscrollXMASingleItemView"), @selector(layoutSubviews), (void *)hook_THReelHscrollLayout, &orig_THReelHscrollLayout);
    NullHookMessageEx(objc_getClass("_TtC27IGDirectLayeredXMAMessageUI35IGDirectLayeredXMAMessageBubbleView"), @selector(layoutSubviews), (void *)hook_THReelLayeredLayout, &orig_THReelLayeredLayout);
}
