static char kThetaPaintedBubbleKey;
static char kThetaOriginalShapeColorsKey;

static UIView *thetaFindMessageBubble(UIView *root) {
	if (!root) return nil;
	Class bubbleClass = NSClassFromString(@"IGDirectMessageBubbleView");
	if (bubbleClass && [root isKindOfClass:bubbleClass]) return root;
	// Heuristic: look for any subview class name that contains "BubbleView"
	for (UIView *sub in root.subviews) {
		NSString *className = NSStringFromClass([sub class]);
		if ([className containsString:@"BubbleView"]) return sub;
	}
	for (UIView *sub in root.subviews) {
		UIView *found = thetaFindMessageBubble(sub);
		if (found) return found;
	}
	return nil;
}

static UIView *thetaFindFirstSubviewOfClass(UIView *root, Class cls) {
	if (!root || !cls) return nil;
	for (UIView *sub in root.subviews) {
		if ([sub isKindOfClass:cls]) return sub;
	}
	for (UIView *sub in root.subviews) {
		UIView *found = thetaFindFirstSubviewOfClass(sub, cls);
		if (found) return found;
	}
	return nil;
}

// Find: IGDirectMessageBubbleView (outer) -> IGDirectTextMessageBubbleView -> IGDirectMessageBubbleView (inner target)
static UIView *thetaFindInnerTextMessageBubble(UIView *root) {
	if (!root) return nil;
	Class outerBubble = NSClassFromString(@"IGDirectMessageBubbleView");
	Class textBubble = NSClassFromString(@"IGDirectTextMessageBubbleView");
	Class innerBubble = NSClassFromString(@"IGDirectMessageBubbleView");

	UIView *outer = thetaFindFirstSubviewOfClass(root, outerBubble) ?: root;
	UIView *text = thetaFindFirstSubviewOfClass(outer, textBubble);
	if (!text) {
		// Sometimes the text bubble may be deeper under root
		text = thetaFindFirstSubviewOfClass(root, textBubble);
	}
	if (!text) return nil;
	UIView *inner = thetaFindFirstSubviewOfClass(text, innerBubble);
	return inner ?: nil;
}

static id ThetaNullable(id value) { return value ?: [NSNull null]; }
static id ThetaUnNull(id value) { return value == [NSNull null] ? nil : value; }

// Puts back what ThetaPaintDeletedBubble changed, but only where the value is still our
// paint: anything Instagram set since (a theme, a new message's style) is left alone.
static void ThetaRestoreDeletedBubble(UIView *bubble) {
	NSDictionary *saved = objc_getAssociatedObject(bubble, &kThetaPaintedBubbleKey);
	if (!saved) return;
	CGColorRef painted = (__bridge CGColorRef)saved[@"painted"];

	if (CGColorEqualToColor(bubble.backgroundColor.CGColor, painted)) {
		bubble.backgroundColor = ThetaUnNull(saved[@"viewBackground"]);
	}
	if (CGColorEqualToColor(bubble.layer.backgroundColor, painted)) {
		bubble.layer.backgroundColor = (__bridge CGColorRef)ThetaUnNull(saved[@"layerBackground"]);
	}
	for (CALayer *sublayer in bubble.layer.sublayers ?: @[]) {
		if (![sublayer isKindOfClass:[CAShapeLayer class]]) continue;
		CAShapeLayer *shape = (CAShapeLayer *)sublayer;
		NSDictionary *colors = objc_getAssociatedObject(shape, &kThetaOriginalShapeColorsKey);
		if (!colors) continue;
		if (CGColorEqualToColor(shape.fillColor, painted)) shape.fillColor = (__bridge CGColorRef)ThetaUnNull(colors[@"fill"]);
		if (CGColorEqualToColor(shape.backgroundColor, painted)) shape.backgroundColor = (__bridge CGColorRef)ThetaUnNull(colors[@"background"]);
		objc_setAssociatedObject(shape, &kThetaOriginalShapeColorsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
	[(UIView *)saved[@"overlay"] removeFromSuperview];
	objc_setAssociatedObject(bubble, &kThetaPaintedBubbleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void ThetaPaintDeletedBubble(UIView *bubble, UIColor *color) {
	NSDictionary *saved = objc_getAssociatedObject(bubble, &kThetaPaintedBubbleKey);
	if (saved && CGColorEqualToColor((__bridge CGColorRef)saved[@"painted"], color.CGColor)) return;
	ThetaRestoreDeletedBubble(bubble);

	UIView *overlay = [[UIView alloc] initWithFrame:bubble.bounds];
	overlay.userInteractionEnabled = NO;
	overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	overlay.layer.cornerRadius = bubble.layer.cornerRadius;
	overlay.layer.masksToBounds = YES;
	overlay.backgroundColor = color;

	objc_setAssociatedObject(bubble, &kThetaPaintedBubbleKey, @{
		@"painted": (__bridge id)color.CGColor,
		@"viewBackground": ThetaNullable(bubble.backgroundColor),
		@"layerBackground": ThetaNullable((__bridge id)bubble.layer.backgroundColor),
		@"overlay": overlay,
	}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	bubble.backgroundColor = color;
	bubble.layer.backgroundColor = color.CGColor;
	// Tint the shape layers that draw the bubble
	for (CALayer *sublayer in bubble.layer.sublayers ?: @[]) {
		if (![sublayer isKindOfClass:[CAShapeLayer class]]) continue;
		CAShapeLayer *shape = (CAShapeLayer *)sublayer;
		objc_setAssociatedObject(shape, &kThetaOriginalShapeColorsKey, @{
			@"fill": ThetaNullable((__bridge id)shape.fillColor),
			@"background": ThetaNullable((__bridge id)shape.backgroundColor),
		}, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		shape.fillColor = color.CGColor;
		shape.backgroundColor = color.CGColor;
	}
	// Behind the content but inside the bubble, for bubbles drawn some other way
	[bubble insertSubview:overlay atIndex:0];
}

static void ThetaColorDeletedMessageCell(id self, id viewModel) {
	if (!ENABLED(THDMKeepDeleted)) return;
	if (![viewModel conformsToProtocol:@protocol(IGDirectMessageViewModelProtocol)]) return;

	IGDirectUIMessageMetadata *metadata = [(id<IGDirectMessageViewModelProtocol>)viewModel messageMetadata];
	NSString *serverId = metadata.key.serverId;

	UIView *container = nil;
	if ([self respondsToSelector:@selector(contentViewForVisualMessageViewerPresentation)]) {
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		container = [self performSelector:@selector(contentViewForVisualMessageViewerPresentation)];
		#pragma clang diagnostic pop
	}
	if (!container && [self respondsToSelector:@selector(contentView)]) {
		container = [self valueForKey:@"contentView"];
	}
	if (!container && [self isKindOfClass:[UIView class]]) {
		container = (UIView *)self;
	}
	if (!container) return;

	UIView *bubble = thetaFindInnerTextMessageBubble(container);
	if (!bubble) bubble = thetaFindMessageBubble(container);
	if (!bubble) bubble = container;

	// Cells are reused: paint only deleted messages, and undo the paint when a reused
	// bubble shows a message that isn't deleted (Instagram doesn't reset what we changed).
	if (serverId.length == 0 || ![[MessagesManager sharedManager] messageExistsWithID:serverId]) {
		ThetaRestoreDeletedBubble(bubble);
		return;
	}
	UIColor *color = ThetaSettingColor(THDMDeletedColor);
	if (!color) return;
	ThetaPaintDeletedBubble(bubble, color);
}

// 451 renamed the last argument (launcherSet: -> mobileConfig:); each selector keeps its own original.
static void (*orig_directMessageCell_configure)(id self, SEL _cmd, id viewModel, id specFactory, id config);
static void hook_directMessageCell_configure(id self, SEL _cmd, id viewModel, id specFactory, id config) {
	orig_directMessageCell_configure(self, _cmd, viewModel, specFactory, config);
	ThetaColorDeletedMessageCell(self, viewModel);
}

static void (*orig_directMessageCell_configureLegacy)(id self, SEL _cmd, id viewModel, id specFactory, id launcher);
static void hook_directMessageCell_configureLegacy(id self, SEL _cmd, id viewModel, id specFactory, id launcher) {
	orig_directMessageCell_configureLegacy(self, _cmd, viewModel, specFactory, launcher);
	ThetaColorDeletedMessageCell(self, viewModel);
}

// Strips the server-ID keys out of a removeMessages update and saves them, so the
// deletion becomes a no-op while the rest of the batch still applies. The update is
// a plain FBIvarBasedEqualityObject, so its key list is replaced in place.
static void thetaStripDeletedMessageKeys(id messageUpdate) {
	NSArray *removeKeys = [messageUpdate valueForKey:@"_removeMessages_messageKeys"];
	if (![removeKeys isKindOfClass:[NSArray class]] || removeKeys.count == 0) return;

	Class keyClass = NSClassFromString(@"IGDirectMessageUpdateMessageKey");
	NSMutableArray *remainingKeys = [NSMutableArray array];
	for (id messageKey in removeKeys) {
		id serverId = (keyClass && [messageKey isKindOfClass:keyClass]) ? [messageKey valueForKey:@"_messageServerId"] : nil;
		if (![serverId isKindOfClass:[NSString class]] || [serverId length] == 0) {
			// No server ID (e.g. an unsent local message): nothing to show later, let it go
			[remainingKeys addObject:messageKey];
			continue;
		}
		[[MessagesManager sharedManager] saveDeletedMessageWithID:serverId];
	}
	if (remainingKeys.count == removeKeys.count) return;
	[messageUpdate setValue:[remainingKeys copy] forKey:@"_removeMessages_messageKeys"];
}

static void (*orig_messageCache3)(id self, SEL _cmd, id updates, id completion, id userAccess);
static void hook_messageCache3(id self, SEL _cmd, id updates, id completion, id userAccess) {
	if (ENABLED(THDMKeepDeleted)) {
		// updates: [IGDirectCacheThreadUpdate] -> threadUpdates: [IGDirectThreadUpdate] -> _messageUpdate
		NSArray *cacheThreadUpdates = [updates isKindOfClass:[NSArray class]] ? updates : (updates ? @[updates] : @[]);
		for (id cacheThreadUpdate in cacheThreadUpdates) {
			@try {
				NSArray *threadUpdates = [cacheThreadUpdate valueForKey:@"threadUpdates"];
				if (![threadUpdates isKindOfClass:[NSArray class]]) continue;
				for (id threadUpdate in threadUpdates) {
					id messageUpdate = [threadUpdate valueForKey:@"_messageUpdate"];
					if (messageUpdate) thetaStripDeletedMessageKeys(messageUpdate);
				}
			} @catch (NSException *e) {
				THDebugLog(@"[Theta] keep deleted: error reading IGDirectThreadUpdate: %@", e);
			}
		}
	}

	// Always hand the batch on: Instagram chains cache application and thread loading
	// on the completion, so it has to run exactly once.
	orig_messageCache3(self, _cmd, updates, completion, userAccess);
}

void THRegisterKeepDeletedMessagesHooks(void) {
	Class applicator = objc_getClass("IGDirectCacheUpdatesApplicator");
	NullHookMessageIfPresent(applicator, @selector(_applyThreadUpdates:completion:userAccess:), (void *)hook_messageCache3, &orig_messageCache3);

	Class messageCell = ThetaFirstClass(@[
		@"_TtC19IGDirectMessageCell19IGDirectMessageCell",
		@"IGDirectMessageCell"
	]);
	// Only the base cell is hooked: its text-message subclass inherits the method, but the
	// photo, video, post and other cell subclasses override it and Swift's super call skips this hook.
	NullHookMessageIfPresent(messageCell,
		@selector(configureWithViewModel:ringViewSpecFactory:mobileConfig:),
		(void *)hook_directMessageCell_configure,
		&orig_directMessageCell_configure);
	NullHookMessageIfPresent(messageCell,
		@selector(configureWithViewModel:ringViewSpecFactory:launcherSet:),
		(void *)hook_directMessageCell_configureLegacy,
		&orig_directMessageCell_configureLegacy);
}