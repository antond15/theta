@class IGVideo;
static void downloadHDVideo(IGVideo *inputVideo);

static void (*orig_visualmsgghostvideo)(id self, SEL _cmd, id arg1);

static BOOL ThetaIsVisualMessageViewer(id object) {
    Class viewer = objc_getClass("IGDirectVisualMessageViewerController");
    return viewer && [object isKindOfClass:viewer];
}

// The view-once viewer configures its media view with itself or an
// IGStoryPlayerMediaViewDelegateInterposer (which holds the viewer in `_delegate`) as the delegate.
// The responder chain is the fallback for a view whose delegate is wired differently.
static BOOL ThetaPhotoViewBelongsToVisualMessageViewer(UIView *photoView) {
    id delegate = [photoView respondsToSelector:@selector(delegate)] ? [(id)photoView delegate] : nil;
    if (ThetaIsVisualMessageViewer(delegate)) return YES;
    Class interposer = objc_getClass("IGStoryPlayerMediaViewDelegateInterposer");
    if (interposer && [delegate isKindOfClass:interposer]) {
        Ivar ivar = class_getInstanceVariable(interposer, "_delegate");
        __unsafe_unretained id inner = ivar ? object_getIvar(delegate, ivar) : nil;
        if (ThetaIsVisualMessageViewer(inner)) return YES;
    }
    for (UIResponder *responder = photoView.nextResponder; responder; responder = responder.nextResponder) {
        if (ThetaIsVisualMessageViewer(responder)) return YES;
    }
    return NO;
}

static BOOL ThetaIsStoryVideoView(UIView *view) {
    Class video = objc_getClass("IGStoryVideoView");                 // 451
    Class modernVideo = objc_getClass("IGStoryModernVideoView");     // older builds
    return (video && [view isKindOfClass:video]) || (modernVideo && [view isKindOfClass:modernVideo]);
}

static void (*orig_visualmsgghostbuttons)(IGDirectVisualMessageViewerController *self, SEL _cmd);
static void hook_visualmsgghostbuttons(IGDirectVisualMessageViewerController *self, SEL _cmd) {
    orig_visualmsgghostbuttons(self, _cmd);

    UIView *containerView = [self valueForKey:@"view"];
    if (!containerView || ![containerView isKindOfClass:[UIView class]]) {
        THDebugLog(@"[Theta] view-once: no container view");
        return;
    }
    
    UIButton *downloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [downloadButton setTintColor:ThetaSettingColor(THUISaveButtonColor)];
    [downloadButton setImage:[UIImage systemImageNamed:@"arrow.down"] forState:UIControlStateNormal];
    downloadButton.layer.shadowColor = [UIColor blackColor].CGColor;
    downloadButton.layer.shadowOpacity = 0.4;
    downloadButton.layer.shadowOffset = CGSizeMake(-2, 0);
    downloadButton.layer.shadowRadius = 3;
    downloadButton.layer.masksToBounds = NO;
    [downloadButton setTranslatesAutoresizingMaskIntoConstraints:false];

    UIButton *seenButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [seenButton setTintColor:ThetaSettingColor(THUISeenButtonColor)];
    [seenButton setImage:[UIImage systemImageNamed:@"eye"] forState:UIControlStateNormal];
    seenButton.layer.shadowColor = [UIColor blackColor].CGColor;
    seenButton.layer.shadowOpacity = 0.4;
    seenButton.layer.shadowOffset = CGSizeMake(-2, 0);
    seenButton.layer.shadowRadius = 3;
    seenButton.layer.masksToBounds = NO;
    [seenButton setTranslatesAutoresizingMaskIntoConstraints:false];

    BOOL downloadVideos = ENABLED(THSaveMediaButton);
    BOOL hideSeenState = ENABLED(THDMPrivateMediaGhost);

    ThetaSetCaptureHiding(downloadButton);
    ThetaSetCaptureHiding(seenButton);

    @try {
        if (downloadVideos && !hideSeenState) {
            [containerView addSubview:downloadButton];
            [NSLayoutConstraint activateConstraints:@[
                [downloadButton.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor constant:-150],
                [downloadButton.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-8],
                [downloadButton.widthAnchor constraintEqualToConstant:30],
                [downloadButton.heightAnchor constraintEqualToConstant:30]
            ]];
        }

        if (!downloadVideos && hideSeenState) {
            [containerView addSubview:seenButton];
            [NSLayoutConstraint activateConstraints:@[
                [seenButton.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor constant:-150],
                [seenButton.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-8],
                [seenButton.widthAnchor constraintEqualToConstant:30],
                [seenButton.heightAnchor constraintEqualToConstant:30]
            ]];
        }

        if (downloadVideos && hideSeenState) {
            [containerView addSubview:downloadButton];
            [containerView addSubview:seenButton];
            [NSLayoutConstraint activateConstraints:@[
                [downloadButton.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor constant:-150],
                [downloadButton.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-8],
                [downloadButton.widthAnchor constraintEqualToConstant:30],
                [downloadButton.heightAnchor constraintEqualToConstant:30]
            ]];
            [NSLayoutConstraint activateConstraints:@[
                [seenButton.bottomAnchor constraintEqualToAnchor:downloadButton.topAnchor constant:-20],
                [seenButton.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-8],
                [seenButton.widthAnchor constraintEqualToConstant:30],
                [seenButton.heightAnchor constraintEqualToConstant:30]
            ]];
        }

        if (hideSeenState) {
            __weak typeof(self) weakSelf = self;
            [seenButton addAction:[UIAction actionWithHandler:^(UIAction *action) {
                IGDirectVisualMessageViewerController *strongSelf = weakSelf;
                if (!strongSelf) return;
                UIView *containView = [strongSelf valueForKey:@"_viewerContainerView"];
                UIView *medView = [containView valueForKey:@"mediaView"];
                Class photoClass = objc_getClass("IGStoryPhotoView");
                BOOL marked = NO;
                // Call past the ghost hooks directly: the video original, and the viewer's own
                // photo-loaded callback (not hooked), so no state is left for the next media.
                if (ThetaIsStoryVideoView(medView) && orig_visualmsgghostvideo) {
                    orig_visualmsgghostvideo(strongSelf, @selector(storyPlayerMediaViewDidPlay:), medView);
                    marked = YES;
                } else if (photoClass && [medView isKindOfClass:photoClass]) {
                    [strongSelf storyPlayerMediaViewDidLoad:medView loadSource:0 networkRequestSummary:0];
                    marked = YES;
                }
                THDebugLog(@"[Theta] view-once: mark seen media=%@ marked=%d", NSStringFromClass([medView class]), marked);

                if (ENABLED(THAppShowBanners)) {
                    if (marked) {
                        [ThetaHelper showToastWithTitle:@"Marked as seen!" subtitle:@"They know we are here." icon:[ThetaHelper imageFromEmojiString:@"👀" width:60] autoHide:4 openURL:nil];
                    } else {
                        [ThetaHelper showToastWithTitle:@"Couldn't mark as seen" subtitle:@"Unknown media type, nothing was sent." icon:[UIImage systemImageNamed:@"exclamationmark.triangle.fill"] autoHide:4 openURL:nil];
                    }
                }
            }] forControlEvents:UIControlEventTouchUpInside];
        }

        if (downloadVideos) {
            __weak typeof(self) weakSelf = self;
            [downloadButton addAction:[UIAction actionWithHandler:^(UIAction *action) {
                IGDirectVisualMessageViewerController *strongSelf = weakSelf;
                if (!strongSelf) return;
                id initialVisualMessage = [strongSelf valueForKey:@"_initialVisualMessage"];
                id visualMediaInfo = [initialVisualMessage valueForKey:@"_visualMediaInfo"];
                id media = [visualMediaInfo valueForKey:@"media"];
                if ([media valueForKey:@"_video_video"]) {
                    IGVideo *video = [media valueForKey:@"_video_video"];
                    downloadHDVideo(video);
                }

                if ([media valueForKey:@"_photo_photo"]) {
                    IGPhoto *photo = [media valueForKey:@"_photo_photo"];
                    NSArray *originalImageVersions = [photo valueForKey:@"_originalImageVersions"];
                    if (originalImageVersions.count > 1) {
                        id photoURL = [originalImageVersions lastObject];
                        NSURL *url = [photoURL valueForKey:@"url"];
                        MediaSelectionViewController *mediaSelectionViewController = [[MediaSelectionViewController alloc] init];
                        [mediaSelectionViewController downloadMediaToTemp:url completion:^(NSString *filePath, NSString *fileExtension){
                            if (ENABLED(THAppShowBanners)) {
                                BOOL saveToCameraRoll = ThetaSettingChoiceIs(THSaveMethod, @"camera_roll");
                                if (saveToCameraRoll) {
                                    [ThetaHelper showToastWithTitle:@"Saved to camera roll!" subtitle:@"Tap here to go to camera roll." icon:[UIImage systemImageNamed:@"checkmark.circle.fill"] autoHide:4 openURL:[NSURL URLWithString:@"photos-redirect://"]];
                                } else {
                                    [ThetaHelper showToastWithTitle:@"Saved!" subtitle:@"Saved to local folder." icon:[UIImage systemImageNamed:@"checkmark.circle.fill"] autoHide:4 openURL:nil];
                                }
                            }
                        }];
                    }
                }
            }] forControlEvents:UIControlEventTouchUpInside];
        }
    } @catch (NSException *exception) {
        THDebugLog(@"[Theta] view-once: adding buttons failed: %@", exception);
    }
}

static void hook_visualmsgghostvideo(id self, SEL _cmd, id arg1) {
    if (!ENABLED(THDMPrivateMediaGhost)) {
        return orig_visualmsgghostvideo(self, _cmd, arg1);
    }
    THDebugLog(@"[Theta] view-once: video play held back");
}

static void (*orig_visualmsgghostphoto)(id self, SEL _cmd, id arg1, id arg2, id arg3, id arg4);
static void hook_visualmsgghostphoto(id self, SEL _cmd, id arg1, id arg2, id arg3, id arg4) {
    if (!ENABLED(THDMPrivateMediaGhost)) {
        return orig_visualmsgghostphoto(self, _cmd, arg1, arg2, arg3, arg4);
    }

    if (!ThetaPhotoViewBelongsToVisualMessageViewer(self)) {
        THDebugLog(@"[Theta] view-once: photo load passed, owner not the viewer");
        return orig_visualmsgghostphoto(self, _cmd, arg1, arg2, arg3, arg4);
    }
    THDebugLog(@"[Theta] view-once: photo load held back");
}

void THRegisterPrivateVideoGhostHooks(void) {
    NullHookMessageEx(objc_getClass("IGDirectVisualMessageViewerController"), @selector(viewDidLoad), (void *)hook_visualmsgghostbuttons, &orig_visualmsgghostbuttons);
    NullHookMessageEx(objc_getClass("IGDirectVisualMessageViewerController"), @selector(storyPlayerMediaViewDidPlay:), (void *)hook_visualmsgghostvideo, &orig_visualmsgghostvideo);
    NullHookMessageEx(objc_getClass("IGStoryPhotoView"), @selector(progressImageView:didLoadImage:loadSource:networkRequestSummary:), (void *)hook_visualmsgghostphoto, &orig_visualmsgghostphoto);
}