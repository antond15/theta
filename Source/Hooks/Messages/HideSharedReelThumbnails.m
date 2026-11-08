/* Replace only the image; Instagram owns the surrounding controls and decoration. */
static char THSharedThumbnailHiddenKey;
static char THSharedThumbnailOriginalKey;

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
    if (image != THSharedThumbnailPlaceholder())
        objc_setAssociatedObject(view, &THSharedThumbnailOriginalKey, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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

static BOOL THSharedPreviewURL(id value) {
    NSString *string = [value isKindOfClass:NSURL.class] ? [value absoluteString] : value;
    if (![string isKindOfClass:NSString.class]) return NO;
    NSURLComponents *url = [NSURLComponents componentsWithString:string];
    if ([url.scheme.lowercaseString isEqualToString:@"instagram"])
        return [@[@"clips", @"reel", @"reels"] containsObject:url.host.lowercaseString];
    NSString *host = url.host.lowercaseString;
    return ([host isEqualToString:@"instagram.com"] || [host hasSuffix:@".instagram.com"])
        && ([url.path hasPrefix:@"/reel/"] || [url.path hasPrefix:@"/reels/"]);
}

/* XMA payloads vary by server experiment. Inspect only known media/navigation fields,
   never captions (which can mention reels on an ordinary post). */
static BOOL THSharedPreviewModel(id model, NSUInteger depth) {
    if (!model || depth > 3) return NO;
    id productType = ThetaValueForKey(model, @"productType");
    if ([productType isKindOfClass:NSString.class] && [productType isEqualToString:@"clips"]) return YES;
    for (NSString *key in @[@"actionURL", @"url", @"tapURL"])
        if (THSharedPreviewURL(ThetaValueForKey(model, key))) return YES;
    for (NSString *key in @[@"media", @"imageTapInfo", @"navigationInfo", @"mediaResolverContext", @"message", @"messageCellViewModel"])
        if (THSharedPreviewModel(ThetaValueForKey(model, key), depth + 1)) return YES;
    return NO;
}

static void THUpdateSharedThumbnail(UIView *cell, NSString *modelKey, NSString *previewKey) {
    BOOL hideReels = ENABLED(@"Hide Shared Reel Thumbnails");
    id model = hideReels ? ThetaValueForKey(cell, modelKey) : nil;
    id cellModel = ThetaValueForKey(model, @"messageCellViewModel");
    id outgoing = ThetaValueForKey(cellModel, @"isOutgoing");
    if (!outgoing) outgoing = ThetaValueForKey(ThetaValueForKey(cellModel, @"sortingInfo"), @"isOutgoing");
    BOOL hide = ![outgoing boolValue] && hideReels && THSharedPreviewModel(model, 0);
    id preview = ThetaValueForKey(cell, previewKey);
    id imageView = [preview isKindOfClass:[UIImageView class]] ? preview : ThetaValueForKey(preview, @"photoImageView");
    if ([imageView isKindOfClass:[UIImageView class]]) {
        BOOL wasHidden = [objc_getAssociatedObject(imageView, &THSharedThumbnailHiddenKey) boolValue];
        if (hide && !wasHidden) {
            objc_setAssociatedObject(imageView, &THSharedThumbnailOriginalKey, [imageView image], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(imageView, &THSharedThumbnailHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [imageView setImage:THSharedThumbnailPlaceholder()];
        } else if (!hide && wasHidden) {
            UIImage *original = objc_getAssociatedObject(imageView, &THSharedThumbnailOriginalKey);
            objc_setAssociatedObject(imageView, &THSharedThumbnailHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [imageView setImage:original];
            objc_setAssociatedObject(imageView, &THSharedThumbnailOriginalKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
