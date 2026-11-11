static char kThetaOriginalBackgroundColorKey;
static char kThetaProcessedMessageIdKey;
static char kThetaOverlayViewKey;

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

static void ThetaColorDeletedMessageCell(id self, id viewModel) {
	if (!ENABLED(THDMKeepDeleted)) return;
	if (![viewModel conformsToProtocol:@protocol(IGDirectMessageViewModelProtocol)]) return;

	IGDirectUIMessageMetadata *metadata = [(id<IGDirectMessageViewModelProtocol>)viewModel messageMetadata];
	NSString *serverId = metadata.key.serverId;
	if (serverId.length == 0) return;

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

	UIColor *originalBackgroundColor = objc_getAssociatedObject(bubble, &kThetaOriginalBackgroundColorKey);
	if (!originalBackgroundColor) {
		@try {
			originalBackgroundColor = [bubble valueForKey:@"backgroundColor"];
			if (originalBackgroundColor) {
				objc_setAssociatedObject(bubble, &kThetaOriginalBackgroundColorKey, originalBackgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
			}
		} @catch (__unused NSException *e) {}
	}

	NSString *processedServerId = objc_getAssociatedObject(bubble, &kThetaProcessedMessageIdKey);
	if ([processedServerId isKindOfClass:[NSString class]] && [processedServerId isEqualToString:serverId]) {
		return;
	}

	BOOL exists = [[MessagesManager sharedManager] messageExistsWithID:serverId];
	UIColor *targetColor = nil;
	if (exists) {
		targetColor = ThetaSettingColor(THDMDeletedColor);
	} else if (originalBackgroundColor) {
		targetColor = originalBackgroundColor;
	}

	if (targetColor) {
		@try {
			// 1) Attempt direct background set
			[bubble setValue:targetColor forKey:@"backgroundColor"];
			if ([bubble layer]) {
				bubble.layer.backgroundColor = targetColor.CGColor;
			}
			// 2) Try tinting common shape layers that render the bubble
			CALayer *layer = bubble.layer;
			for (CALayer *sublayer in layer.sublayers ?: @[]) {
				if ([sublayer isKindOfClass:[CAShapeLayer class]]) {
					((CAShapeLayer *)sublayer).fillColor = targetColor.CGColor;
					((CAShapeLayer *)sublayer).backgroundColor = targetColor.CGColor;
				}
			}
			// 3) Ensure a persistent visual using an overlay if needed
			UIView *overlay = objc_getAssociatedObject(bubble, &kThetaOverlayViewKey);
			if (!overlay) {
				overlay = [[UIView alloc] initWithFrame:bubble.bounds];
				overlay.userInteractionEnabled = NO;
				overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
				overlay.layer.cornerRadius = bubble.layer.cornerRadius;
				overlay.layer.masksToBounds = YES;
				objc_setAssociatedObject(bubble, &kThetaOverlayViewKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
				// Put behind content but inside bubble
				[bubble insertSubview:overlay atIndex:0];
			}
			overlay.backgroundColor = targetColor;
		} @catch (__unused NSException *e) {}
	}

	objc_setAssociatedObject(bubble, &kThetaProcessedMessageIdKey, serverId, OBJC_ASSOCIATION_COPY_NONATOMIC);
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