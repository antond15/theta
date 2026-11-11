#import <UIKit/UIKit.h>
#import "Include/ThetaDebug.h"
#import <Photos/Photos.h>
#import "Include/MediaSelectionViewController.h"
#import "Include/CustomToastView.h"
#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <AVFoundation/AVFoundation.h>
#import <dlfcn.h>
#import "Include/ThetaHelper.h"
#import "Include/AV1Transcoder.h"
#import "Include/ThetaDashManifest.h"

static void showCompletionToast(CustomToastView *progressToast, BOOL success, NSString *title, NSString *subtitle, UIImage *icon, NSURL *url) {
    if (progressToast) {
        [progressToast completeProgressWithTitle:title subtitle:subtitle icon:icon url:url];
        if (success) {
            // Haptic feedback for success
            UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [generator impactOccurred];
        }
    } else {
        // Fallback to regular toast if no progress toast
        // You might need to implement this based on your existing toast system
    }
}


#import "Include/ThetaSettings.h"



@implementation MediaSelectionViewController {
    BOOL hasShownToast;
    CAGradientLayer *gradientLayer;
    CAEmitterLayer *emitterLayer;
}

- (instancetype)initWithMediaItems:(NSArray<NSDictionary *> *)mediaItems withCount:(NSInteger)count {
    return [self initWithMediaItems:mediaItems hdVideos:nil withCount:count];
}

- (instancetype)initWithMediaItems:(NSArray<NSDictionary *> *)mediaItems hdVideos:(NSArray<IGVideo *> *)hdVideos withCount:(NSInteger)count {
    self = [super init];
    if (self) {
        _mediaItems = mediaItems ?: @[];
        _hdVideos = hdVideos ?: @[];
        _count = count;
        _selectedIndexes = [NSMutableSet set];
        _selectedVideoIndexes = [NSMutableSet set];
        hasShownToast = NO;
        _previewCache = [self.class sharedPreviewCache]; // Use shared cache
        _videoPlayersCache = [[NSMutableDictionary alloc] init];
        _fetchQueue = [[NSOperationQueue alloc] init];
        _fetchQueue.maxConcurrentOperationCount = 12;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    if (![self isInternetAvailable]) {
        [self showToastWithTitle:@"No internet connection" subtitle:@"Please connect to the internet." icon:[UIImage systemImageNamed:@"wifi.slash"] seconds:4 openURL:nil];
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    } else {
        if (ENABLED(THAppShowBanners)) {
            UIImage *fetchedImage = [UIImage systemImageNamed:@"checkmark.circle.fill"];
            [self showToastWithTitle:@"Fetched!" subtitle:@"Thanks for waiting." icon:fetchedImage seconds:2 openURL:nil];
        }
    }
    
    // Force update instruction label after view loads
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateInstructionLabel];
    });

    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    UIVisualEffectView *blurEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurEffectView.frame = self.view.bounds;
    blurEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:blurEffectView];

    gradientLayer = [CAGradientLayer layer];
    gradientLayer.frame = self.view.bounds;
    [self.view.layer insertSublayer:gradientLayer atIndex:0];

    [self calculateAverageColorFromMediaItemsAsync:^(UIColor *averageColor) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setupGradientWithColor:averageColor];
            [self setupEmitterWithColor:averageColor];
        });
    }];

    self.selectAllButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 100, 30)];
    [self.selectAllButton setTitle:@"Select All" forState:UIControlStateNormal];
    self.selectAllButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    	self.selectAllButton.tintColor = [ThetaHelper iotaPinkColor];
    [self updateSelectAllButtonColor];
    [self.selectAllButton addTarget:self action:@selector(selectAllButtonTapped) forControlEvents:UIControlEventTouchUpInside];

    self.navigationItem.leftBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"] style:UIBarButtonItemStylePlain target:self action:@selector(dismissView)],
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(selectAllButtonTapped)]
    ];
    	self.navigationController.navigationBar.tintColor = [ThetaHelper iotaPinkColor];
    // Use iOS 16+ SF Symbol with fallback for older versions
    UIImage *downloadImage;
    if (@available(iOS 16.0, *)) {
        downloadImage = [UIImage systemImageNamed:@"arrow.down.to.line"];
    } else {
        // Fallback for iOS 15 - use a different symbol
        downloadImage = [UIImage systemImageNamed:@"arrow.down"];
    }
    self.downloadButton = [[UIBarButtonItem alloc] initWithImage:downloadImage style:UIBarButtonItemStyleDone target:self action:@selector(downloadSelectedItems)];
    self.downloadButton.enabled = NO;
    self.navigationItem.rightBarButtonItem = self.downloadButton;

    self.instructionLabel = [[UILabel alloc] init];
    self.instructionLabel.textColor = [UIColor lightGrayColor];
    self.instructionLabel.textAlignment = NSTextAlignmentCenter;
    self.instructionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.instructionLabel];
    
    [self updateInstructionLabel];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
    layout.itemSize = CGSizeMake(200, 350);
    layout.minimumLineSpacing = 20;
    layout.sectionInset = UIEdgeInsetsMake(80, 20, 80, 20);

    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.collectionView.backgroundColor = [UIColor clearColor];
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    self.collectionView.prefetchDataSource = self;
    self.collectionView.prefetchingEnabled = YES;
    self.collectionView.showsHorizontalScrollIndicator = NO;
    [self.collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"MediaCell"];
    [self.view addSubview:self.collectionView];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        [self.instructionLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.instructionLabel.bottomAnchor constraintEqualToAnchor:self.collectionView.topAnchor constant:-50],
        [self.collectionView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.collectionView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-20],
        [self.collectionView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor],
        [self.collectionView.heightAnchor constraintEqualToConstant:370]
    ]];

    self.collectionView.alpha = 0.0;
    [UIView animateWithDuration:0.5 animations:^{
        self.collectionView.alpha = 1.0;
    }];

    for (NSDictionary *mediaItem in self.mediaItems) {
        NSString *urlString = mediaItem[@"url"];
        if ([urlString.pathExtension.lowercaseString isEqualToString:@"mp4"]) {
            AVPlayer *player = [[AVPlayer alloc] initWithURL:[NSURL URLWithString:urlString]];
            self.videoPlayersCache[urlString] = player;
        }
    }
}

- (BOOL)isInternetAvailable {
    SCNetworkReachabilityFlags flags;
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(NULL, "www.google.com");
    if (!reachability) return NO;
    Boolean success = SCNetworkReachabilityGetFlags(reachability, &flags);
    CFRelease(reachability);
    if (!success || (flags & kSCNetworkFlagsReachable) == 0 || (flags & kSCNetworkFlagsConnectionRequired) != 0) {
        return NO;
    }
    return YES;
}

- (void)showToastWithTitle:(NSString *)title subtitle:(NSString *)subtitle icon:(UIImage *)icon seconds:(int)seconds openURL:(NSURL *)openURL {
    CustomToastView *toast = [[CustomToastView alloc] initWithTitle:title subtitle:subtitle icon:icon autoHide:seconds openURL:openURL];
    [toast presentToast];
    [self hapticIfNeeded];
}

- (void)hapticIfNeeded {
    if (ENABLED(THAppHaptics)) {
        AudioServicesPlaySystemSound(1519);
    }
}

- (void)setupGradientWithColor:(UIColor *)averageColor {
    gradientLayer.colors = @[(id)averageColor.CGColor, (id)[UIColor clearColor].CGColor];
    gradientLayer.startPoint = CGPointMake(0.0, 0.5);
    gradientLayer.endPoint = CGPointMake(1.0, 0.5);
}

- (void)setupEmitterWithColor:(UIColor *)color {
    emitterLayer = [CAEmitterLayer layer];
    emitterLayer.frame = self.view.bounds;
    emitterLayer.renderMode = kCAEmitterLayerAdditive;
    emitterLayer.emitterPosition = CGPointMake(self.view.bounds.size.width / 2.0, self.view.bounds.size.height / 2.0);
    emitterLayer.emitterSize = CGSizeMake(self.view.bounds.size.width, self.view.bounds.size.height);
    emitterLayer.emitterShape = kCAEmitterLayerRectangle;
    emitterLayer.emitterMode = kCAEmitterLayerSurface;
    emitterLayer.emitterCells = [self createEmitterCellsWithColor:color];
    [self.view.layer insertSublayer:emitterLayer atIndex:1];
}

- (NSArray<CAEmitterCell *> *)createEmitterCellsWithColor:(UIColor *)color {
    CAEmitterCell *cell = [CAEmitterCell emitterCell];
    cell.birthRate = 5.0;
    cell.lifetime = 2.0;
    cell.lifetimeRange = 1.0;
    cell.velocity = 50.0;
    cell.velocityRange = 50.0;
    cell.emissionLongitude = M_PI;
    cell.emissionRange = M_PI_4;
    cell.spin = M_PI_4;
    cell.spinRange = M_PI_4;
    cell.scale = 0.1;
    cell.scaleRange = 0.1;
    cell.scaleSpeed = -0.05;
    cell.alphaSpeed = -0.1;
    cell.color = color.CGColor;
    cell.contents = (id)[UIImage imageNamed:@"spark"].CGImage;

    CAEmitterCell *foldCell = [CAEmitterCell emitterCell];
    foldCell.birthRate = 2.0;
    foldCell.lifetime = 3.0;
    foldCell.lifetimeRange = 2.0;
    foldCell.velocity = 20.0;
    foldCell.velocityRange = 10.0;
    foldCell.emissionLongitude = M_PI;
    foldCell.emissionRange = M_PI_2;
    foldCell.spin = M_PI_2;
    foldCell.spinRange = M_PI_2;
    foldCell.scale = 0.2;
    foldCell.scaleRange = 0.1;
    foldCell.scaleSpeed = -0.05;
    foldCell.alphaSpeed = -0.1;
    foldCell.color = color.CGColor;
    foldCell.contents = (id)[UIImage imageNamed:@"fold"].CGImage;

    return @[cell, foldCell];
}

- (void)calculateAverageColorFromMediaItemsAsync:(void (^)(UIColor *averageColor))completion {
    NSArray *imageItems = [self.mediaItems filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *mediaItem, NSDictionary *bindings) {
        NSString *urlString = mediaItem[@"url"];
        return ![urlString.pathExtension.lowercaseString isEqualToString:@"mp4"];
    }]];
    NSUInteger count = MIN(8, imageItems.count);
    if (count == 0) {
        completion([UIColor whiteColor]);
        return;
    }

    __block uint64_t totalRed = 0, totalGreen = 0, totalBlue = 0, pixelCount = 0;
    dispatch_group_t group = dispatch_group_create();

    for (NSUInteger i = 0; i < count; i++) {
        NSDictionary *mediaItem = imageItems[i];
        NSString *urlString = mediaItem[@"url"];
        NSURL *url = ThetaPreviewURLForItem(mediaItem);
        dispatch_group_enter(group);
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (data) {
                UIImage *image = [UIImage imageWithData:data];
                if (image) {
                    UIColor *avg = [self averageColorFromImage:image];
                    CGFloat r, g, b, a;
                    [avg getRed:&r green:&g blue:&b alpha:&a];
                    totalRed += r * 255;
                    totalGreen += g * 255;
                    totalBlue += b * 255;
                    pixelCount++;
                }
            }
            dispatch_group_leave(group);
        }];
        [task resume];
    }

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (pixelCount == 0) {
            completion([UIColor whiteColor]);
        } else {
            CGFloat averageRed = totalRed / pixelCount / 255.0;
            CGFloat averageGreen = totalGreen / pixelCount / 255.0;
            CGFloat averageBlue = totalBlue / pixelCount / 255.0;
            completion([UIColor colorWithRed:averageRed green:averageGreen blue:averageBlue alpha:1.0]);
        }
    });
}

- (UIColor *)averageColorFromImage:(UIImage *)image {
    CGImageRef cgImage = image.CGImage;
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    if (width == 0 || height == 0) return [UIColor whiteColor];
    size_t dataSize = width * height * 4;
    uint8_t *rawData = malloc(dataSize);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    NSUInteger bytesPerPixel = 4;
    NSUInteger bytesPerRow = bytesPerPixel * width;
    NSUInteger bitsPerComponent = 8;
    CGContextRef context = CGBitmapContextCreate(rawData, width, height, bitsPerComponent, bytesPerRow, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
    CGContextRelease(context);

    uint64_t totalRed = 0, totalGreen = 0, totalBlue = 0;
    uint64_t pixelCount = width * height;

    for (NSUInteger i = 0; i < pixelCount; i++) {
        uint8_t *pixel = rawData + i * 4;
        totalRed += pixel[0];
        totalGreen += pixel[1];
        totalBlue += pixel[2];
    }

    free(rawData);

    CGFloat averageRed = totalRed / pixelCount / 255.0;
    CGFloat averageGreen = totalGreen / pixelCount / 255.0;
    CGFloat averageBlue = totalBlue / pixelCount / 255.0;

    return [UIColor colorWithRed:averageRed green:averageGreen blue:averageBlue alpha:1.0];
}

/** The picker previews the smallest image version when the item has one; the original is downloaded only on save. */
static NSURL *ThetaPreviewURLForItem(NSDictionary *mediaItem) {
    NSString *preview = mediaItem[@"previewURL"];
    NSString *urlString = preview.length ? preview : mediaItem[@"url"];
    return urlString.length ? [NSURL URLWithString:urlString] : nil;
}

static BOOL ThetaPreviewImageIsPlaceholder(UIImage *image) {
    if (!image) return YES;
    if (@available(iOS 13.0, *)) {
        if (image.isSymbolImage) return YES;
    }
    // Tiny SF-symbol-sized bitmaps sometimes get rasterized; treat very small images as placeholders.
    if (image.size.width <= 44.0 && image.size.height <= 44.0) return YES;
    return NO;
}

// Async preview generation using NSURLSession
- (void)generatePreviewForMediaItem:(NSDictionary *)mediaItem completion:(void (^)(UIImage *preview))completion {
    if (!completion) return;
    NSString *urlString = mediaItem[@"url"];
    if (!urlString.length) {
        completion(nil);
        return;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        completion(nil);
        return;
    }

    NSString *ext = url.pathExtension.lowercaseString;
    // Strip query-less path ext; CDN URLs often embed ".mp4" before query.
    NSString *path = url.path.lowercaseString ?: @"";
    BOOL looksVideo = [ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"] || [path containsString:@".mp4"] || [mediaItem[@"isVideo"] boolValue];
    if (looksVideo) {
        completion(nil);
        return;
    }

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 12.0;
    config.HTTPAdditionalHeaders = @{ @"Accept": @"image/*,*/*;q=0.8" };
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    NSURLSessionDataTask *task = [session dataTaskWithURL:ThetaPreviewURLForItem(mediaItem) ?: url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [session finishTasksAndInvalidate];
        if (!data || error) {
            completion(nil);
            return;
        }
        UIImage *image = [UIImage imageWithData:data];
        completion(ThetaPreviewImageIsPlaceholder(image) ? nil : image);
    }];
    [task resume];
}

// Prefetching previews using NSOperationQueue and NSURLSession
- (void)startLoadingMediaItemAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.item < 0 || indexPath.item >= (NSInteger)self.mediaItems.count) return;
    NSDictionary *mediaItem = self.mediaItems[indexPath.item];
    NSString *urlString = mediaItem[@"url"];
    if (!urlString.length) return;

    UIImage *existing = [self.previewCache objectForKey:urlString];
    if ([existing isKindOfClass:[UIImage class]] && !ThetaPreviewImageIsPlaceholder(existing)) {
        return;
    }

    [self.fetchQueue addOperationWithBlock:^{
        [self generatePreviewForMediaItem:mediaItem completion:^(UIImage *preview) {
            if (!preview) return;
            [self.previewCache setObject:preview forKey:urlString];
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                if (indexPath.item < (NSInteger)self.mediaItems.count) {
                    [self.collectionView reloadItemsAtIndexPaths:@[indexPath]];
                }
            }];
        }];
    }];
}

- (void)cancelLoadingMediaItemAtIndexPath:(NSIndexPath *)indexPath {
    for (NSOperation *operation in self.fetchQueue.operations) {
        if (!operation.isFinished && !operation.isCancelled) {
            [operation cancel];
        }
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateSelectAllButtonColor];
}

- (void)updateSelectAllButtonColor {
    if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
        [self.selectAllButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    } else {
        [self.selectAllButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateInstructionLabel];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.previewCache removeAllObjects];
    [self.videoPlayersCache removeAllObjects];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.mediaItems.count + self.hdVideos.count;
}

static void * const playerKey = &playerKey;

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    AVPlayer *player = objc_getAssociatedObject(cell, playerKey);
    if (player) {
        [player play];
    }
    // Prefetch alone is unreliable for the first visible page — always kick preview loads here.
    if (indexPath.item < (NSInteger)self.mediaItems.count) {
        [self startLoadingMediaItemAtIndexPath:indexPath];
    }
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"MediaCell" forIndexPath:indexPath];
    
    // Always configure the cell for the correct item
    // Remove any existing content first
    for (UIView *subview in cell.contentView.subviews) {
        [subview removeFromSuperview];
    }

    UIView *cardView = [[UIView alloc] initWithFrame:cell.contentView.bounds];
    cardView.frame = CGRectInset(cardView.frame, 5, 5);
    cardView.backgroundColor = [UIColor whiteColor];
    cardView.layer.cornerRadius = 20;

    if (self.traitCollection.userInterfaceStyle != UIUserInterfaceStyleDark) {
        cardView.layer.shadowColor = [UIColor blackColor].CGColor;
        cardView.layer.shadowOpacity = 0.5;
        cardView.layer.shadowOffset = CGSizeMake(0, 0);
        cardView.layer.shadowRadius = 5;
    }

    [cell.contentView addSubview:cardView];

    // Determine if this is a regular media item or HD video
    BOOL isHDVideo = indexPath.item >= self.mediaItems.count;
    NSInteger videoIndex = indexPath.item - self.mediaItems.count;
    
    if (isHDVideo) {
        // For HD videos, create the complete cell layout once
        [self setupHDVideoCell:cardView atIndex:videoIndex];
    } else {
        // For regular media items
        [self setupRegularMediaCell:cardView atIndex:indexPath.item];
    }

    CAShapeLayer *borderLayer = [CAShapeLayer layer];
    borderLayer.path = [UIBezierPath bezierPathWithRoundedRect:cardView.bounds cornerRadius:20].CGPath;
    borderLayer.lineWidth = 3.0;
    borderLayer.strokeColor = [ThetaHelper iotaPinkColor].CGColor;
    borderLayer.fillColor = [UIColor clearColor].CGColor;
    borderLayer.frame = cardView.bounds;

    BOOL isSelected = NO;
    if (isHDVideo) {
        isSelected = [self.selectedVideoIndexes containsObject:@(videoIndex)];
    } else {
        isSelected = [self.selectedIndexes containsObject:@(indexPath.item)];
    }
    
    if (isSelected) {
        [cardView.layer addSublayer:borderLayer];
        NSInteger totalSelected = self.selectedIndexes.count + self.selectedVideoIndexes.count;
        self.instructionLabel.text = [NSString stringWithFormat:@"Select which items to download. (%ld/%ld)", totalSelected, self.count];
    } else {
        [borderLayer removeFromSuperlayer];
        NSInteger totalSelected = self.selectedIndexes.count + self.selectedVideoIndexes.count;
        self.instructionLabel.text = [NSString stringWithFormat:@"Select which items to download. (%ld/%ld)", totalSelected, self.count];
    }

    return cell;
}

/** The one end point of a picker save: shows the result and releases ThetaHelper's download lock. */
- (void)showCompletionToast:(CustomToastView *)progressToast completed:(NSInteger)completed total:(NSInteger)total failed:(NSInteger)failed toPhotos:(BOOL)toPhotos {
    NSInteger saved = MAX(completed - failed, 0);
    if (progressToast) {
        NSString *title = @"Download Complete!";
        NSString *subtitle = [NSString stringWithFormat:@"%ld items saved to %@", (long)saved, toPhotos ? @"camera roll" : @"Saved Media"];
        UIImage *icon = [UIImage systemImageNamed:@"checkmark.circle.fill"];
        
        if (failed > 0) {
            title = saved > 0 ? @"Download Finished" : @"Save failed";
            subtitle = [NSString stringWithFormat:@"%ld saved, %ld failed", (long)saved, (long)failed];
            icon = [UIImage systemImageNamed:@"exclamationmark.triangle"];
        }
        
        NSURL *url = (toPhotos && saved > 0) ? [NSURL URLWithString:@"photos-redirect://"] : nil;
        [ThetaHelper finishProgressToast:progressToast success:failed == 0 title:title subtitle:subtitle icon:icon url:url];
    }

    // Allow new downloads after completion
    [ThetaHelper endGlobalDownload];
}



- (void)setupVideoPlayerLayer:(UIView *)cardView withPlayer:(AVPlayer *)player {
    // Remove any existing video player layers
    for (CALayer *layer in cardView.layer.sublayers) {
        if ([layer isKindOfClass:[AVPlayerLayer class]]) {
            [layer removeFromSuperlayer];
        }
    }
    
    // Create player layer
    AVPlayerLayer *playerLayer = [AVPlayerLayer playerLayerWithPlayer:player];
    playerLayer.frame = cardView.bounds;
    playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    playerLayer.cornerRadius = 8.0;
    playerLayer.masksToBounds = YES;
    
    // Add player layer to card view
    [cardView.layer addSublayer:playerLayer];
    
    // Ensure player is muted and set up for looping
    player.muted = YES;
    player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    
    // Remove any existing observers for this player
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:player.currentItem];
    
    // Set up looping with a unique observer
    __weak typeof(self) weakSelf = self;
    __weak typeof(player) weakPlayer = player;
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                                    object:player.currentItem
                                                                     queue:[NSOperationQueue mainQueue]
                                                                usingBlock:^(NSNotification *notification) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakPlayer && weakPlayer.currentItem) {
                [weakPlayer seekToTime:kCMTimeZero completionHandler:^(BOOL finished) {
                    if (finished) {
                        [weakPlayer play];
                    }
                }];
            }
        });
    }];
    
    // Store the observer reference to avoid memory leaks
    objc_setAssociatedObject(player, "loopObserver", observer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // Start playing
    [player play];
}

- (void)cleanupVideoPlayer:(AVPlayer *)player {
    if (player) {
        // Remove the loop observer
        id observer = objc_getAssociatedObject(player, "loopObserver");
        if (observer) {
            [[NSNotificationCenter defaultCenter] removeObserver:observer];
            objc_setAssociatedObject(player, "loopObserver", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        
        // Stop the player
        [player pause];
    }
}

- (void)setupHDVideoCell:(UIView *)cardView atIndex:(NSInteger)videoIndex {
    // Check if we have a cached video player for this index
    NSString *playerKey = [NSString stringWithFormat:@"video_player_%ld", (long)videoIndex];
    AVPlayer *cachedPlayer = [self.previewCache objectForKey:playerKey];
    
    // Create image view for HD video
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:cardView.bounds];
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.clipsToBounds = YES;
    imageView.layer.cornerRadius = 20;
    [cardView addSubview:imageView];
    
    // Show placeholder with gradient background
    imageView.image = [UIImage systemImageNamed:@"play.circle.fill"];
    imageView.tintColor = [UIColor whiteColor];
    
    // Create gradient background
    CAGradientLayer *videoGradientLayer = [CAGradientLayer layer];
    videoGradientLayer.frame = imageView.bounds;
    videoGradientLayer.colors = @[
        (id)[UIColor colorWithRed:0.15 green:0.15 blue:0.25 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.05 green:0.05 blue:0.15 alpha:1.0].CGColor
    ];
    videoGradientLayer.startPoint = CGPointMake(0, 0);
    videoGradientLayer.endPoint = CGPointMake(1, 1);
    [imageView.layer insertSublayer:videoGradientLayer atIndex:0];
    
    // Add "HD VIDEO" text
    UILabel *hdLabel = [[UILabel alloc] init];
    hdLabel.text = @"HD VIDEO";
    hdLabel.font = [UIFont boldSystemFontOfSize:12];
    hdLabel.textColor = [UIColor whiteColor];
    hdLabel.textAlignment = NSTextAlignmentCenter;
    hdLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [cardView addSubview:hdLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [hdLabel.centerXAnchor constraintEqualToAnchor:cardView.centerXAnchor],
        [hdLabel.bottomAnchor constraintEqualToAnchor:cardView.bottomAnchor constant:-8]
    ]];
    
    // Set up video player for playback (use cached player if available)
    if (cachedPlayer) {
        [self setupVideoPlayerLayer:cardView withPlayer:cachedPlayer];
    } else {
        [self setupVideoPlayerForCell:cardView atIndex:videoIndex];
    }
}

- (void)setupRegularMediaCell:(UIView *)cardView atIndex:(NSInteger)mediaIndex {
    NSDictionary *mediaItem = self.mediaItems[mediaIndex];
    NSString *urlString = mediaItem[@"url"];
    NSURL *url = [NSURL URLWithString:urlString];
    
    // Create image view
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:cardView.bounds];
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.clipsToBounds = YES;
    imageView.layer.cornerRadius = 20;
    imageView.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    [cardView addSubview:imageView];
    
    // Prefer a real cached bitmap. Never permanently cache SF Symbol placeholders —
    // that blocked async preview downloads and left the carousel looking empty.
    UIImage *cachedImage = urlString.length ? [self.previewCache objectForKey:urlString] : nil;
    UIImage *dictPreview = mediaItem[@"preview"];
    if ([cachedImage isKindOfClass:[UIImage class]] && !ThetaPreviewImageIsPlaceholder(cachedImage)) {
        imageView.image = cachedImage;
    } else if ([dictPreview isKindOfClass:[UIImage class]] && !ThetaPreviewImageIsPlaceholder(dictPreview)) {
        imageView.image = dictPreview;
        if (urlString.length) [self.previewCache setObject:dictPreview forKey:urlString];
    } else {
        imageView.image = ThetaPreviewImageIsPlaceholder(dictPreview) ? dictPreview : [UIImage systemImageNamed:@"photo"];
        imageView.tintColor = [UIColor colorWithWhite:1 alpha:0.35];
        imageView.contentMode = UIViewContentModeCenter;
        if (urlString.length) {
            [self startLoadingMediaItemAtIndexPath:[NSIndexPath indexPathForItem:mediaIndex inSection:0]];
        }
    }
    
    // Set up video player if it's a video
    NSString *path = url.path.lowercaseString ?: @"";
    BOOL looksVideo = [url.pathExtension.lowercaseString isEqualToString:@"mp4"]
        || [url.pathExtension.lowercaseString isEqualToString:@"mov"]
        || [path containsString:@".mp4"]
        || [mediaItem[@"isVideo"] boolValue];
    if (looksVideo && url) {
        imageView.contentMode = UIViewContentModeScaleAspectFill;
        AVPlayer *player = self.videoPlayersCache[urlString];
        if (!player) {
            player = [[AVPlayer alloc] initWithURL:url];
            self.videoPlayersCache[urlString] = player;
        }

        AVPlayerLayer *playerLayer = [AVPlayerLayer playerLayerWithPlayer:player];
        playerLayer.frame = cardView.bounds;
        playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        playerLayer.cornerRadius = 20;
        playerLayer.masksToBounds = YES;
        player.volume = 0;
        [cardView.layer addSublayer:playerLayer];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemDidReachEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:player.currentItem];

        [player play];
    }
}

- (void)collectionView:(UICollectionView *)collectionView prefetchItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths {
    for (NSIndexPath *indexPath in indexPaths) {
        [self startLoadingMediaItemAtIndexPath:indexPath];
    }
}

- (void)collectionView:(UICollectionView *)collectionView cancelPrefetchingForItemsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths {
    for (NSIndexPath *indexPath in indexPaths) {
        [self cancelLoadingMediaItemAtIndexPath:indexPath];
    }
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
    AVPlayerItem *playerItem = [notification object];
    NSArray *visibleCells = [self.collectionView visibleCells];
    for (UICollectionViewCell *cell in visibleCells) {
        AVPlayer *player = objc_getAssociatedObject(cell, playerKey);
        if (player && player.currentItem == playerItem) {
            [player seekToTime:kCMTimeZero completionHandler:^(BOOL finished) {
                if (finished) {
                    [player play];
                }
            }];
            break;
        }
    }
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    BOOL isHDVideo = indexPath.item >= self.mediaItems.count;
    NSInteger videoIndex = indexPath.item - self.mediaItems.count;
    
    THDebugLog(@"Selection changed - item: %ld, isHDVideo: %@, videoIndex: %ld", (long)indexPath.item, isHDVideo ? @"YES" : @"NO", (long)videoIndex);
    
    if (isHDVideo) {
        NSNumber *index = @(videoIndex);
        if ([self.selectedVideoIndexes containsObject:index]) {
            [self.selectedVideoIndexes removeObject:index];
            THDebugLog(@"Deselected HD video %ld", (long)videoIndex);
        } else {
            [self.selectedVideoIndexes addObject:index];
            THDebugLog(@"Selected HD video %ld", (long)videoIndex);
        }
    } else {
        NSNumber *index = @(indexPath.item);
        if ([self.selectedIndexes containsObject:index]) {
            [self.selectedIndexes removeObject:index];
            THDebugLog(@"Deselected regular media %ld", (long)indexPath.item);
        } else {
            [self.selectedIndexes addObject:index];
            THDebugLog(@"Selected regular media %ld", (long)indexPath.item);
        }
    }
    
    NSInteger totalSelected = self.selectedIndexes.count + self.selectedVideoIndexes.count;
    THDebugLog(@"Total selected: %ld (regular: %ld, videos: %ld)", (long)totalSelected, (long)self.selectedIndexes.count, (long)self.selectedVideoIndexes.count);
    
    self.downloadButton.enabled = totalSelected > 0;
    [self updateSelectAllButtonTitle];

    UICollectionViewCell *cell = [collectionView cellForItemAtIndexPath:indexPath];
    [self updateBorderLayerForCell:cell atIndexPath:indexPath];
    
    [self updateInstructionLabel];
}

- (void)updateSelectAllButtonTitle {
    NSInteger totalItems = self.mediaItems.count + self.hdVideos.count;
    NSInteger totalSelected = self.selectedIndexes.count + self.selectedVideoIndexes.count;
    
    UIBarButtonItem *selectAllBarButton = self.navigationItem.leftBarButtonItems[1];
    if (totalSelected == totalItems) {
        selectAllBarButton.image = [UIImage systemImageNamed:@"checkmark.circle.fill"];
    } else {
        selectAllBarButton.image = [UIImage systemImageNamed:@"checkmark.circle"];
    }
    
    [self updateInstructionLabel];
}

- (void)updateInstructionLabel {
    NSInteger totalItems = self.mediaItems.count + self.hdVideos.count;
    NSInteger totalSelected = self.selectedIndexes.count + self.selectedVideoIndexes.count;
    NSString *labelText = [NSString stringWithFormat:@"Select which items to download. (%ld/%ld)", totalSelected, totalItems];
    self.instructionLabel.text = labelText;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    // Update instruction label when scrolling to ensure it stays correct
    [self updateInstructionLabel];
}

- (void)selectAllButtonTapped {
    NSInteger totalItems = self.mediaItems.count + self.hdVideos.count;
    NSInteger totalSelected = self.selectedIndexes.count + self.selectedVideoIndexes.count;
    
    if (totalSelected == totalItems) {
        // Deselect all
        [self.selectedIndexes removeAllObjects];
        [self.selectedVideoIndexes removeAllObjects];
    } else {
        // Select all
        [self.selectedIndexes removeAllObjects];
        [self.selectedVideoIndexes removeAllObjects];
        
        for (NSInteger i = 0; i < self.mediaItems.count; i++) {
            [self.selectedIndexes addObject:@(i)];
        }
        for (NSInteger i = 0; i < self.hdVideos.count; i++) {
            [self.selectedVideoIndexes addObject:@(i)];
        }
    }
    
    NSInteger newTotalSelected = self.selectedIndexes.count + self.selectedVideoIndexes.count;
    self.downloadButton.enabled = newTotalSelected > 0;
    [self updateSelectAllButtonTitle];

    for (NSIndexPath *indexPath in [self.collectionView indexPathsForVisibleItems]) {
        UICollectionViewCell *cell = [self.collectionView cellForItemAtIndexPath:indexPath];
        [self updateBorderLayerForCell:cell atIndexPath:indexPath];
    }
    
    [self updateInstructionLabel];
}

- (void)updateBorderLayerForCell:(UICollectionViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    UIView *cardView = cell.contentView.subviews.firstObject;
    CAShapeLayer *borderLayer = nil;

    for (CALayer *layer in cardView.layer.sublayers) {
        if ([layer isKindOfClass:[CAShapeLayer class]]) {
            borderLayer = (CAShapeLayer *)layer;
            break;
        }
    }

    if (!borderLayer) {
        borderLayer = [CAShapeLayer layer];
        borderLayer.path = [UIBezierPath bezierPathWithRoundedRect:cardView.bounds cornerRadius:20].CGPath;
        borderLayer.lineWidth = 3.0;
        borderLayer.strokeColor = [ThetaHelper iotaPinkColor].CGColor;
        borderLayer.fillColor = [UIColor clearColor].CGColor;
        borderLayer.frame = cardView.bounds;
    }

    BOOL isHDVideo = indexPath.item >= self.mediaItems.count;
    NSInteger videoIndex = indexPath.item - self.mediaItems.count;
    
    BOOL isSelected = NO;
    if (isHDVideo) {
        isSelected = [self.selectedVideoIndexes containsObject:@(videoIndex)];
    } else {
        isSelected = [self.selectedIndexes containsObject:@(indexPath.item)];
    }

    if (isSelected) {
        [cardView.layer addSublayer:borderLayer];
    } else {
        [borderLayer removeFromSuperlayer];
    }
    
    // Don't update the instruction label here - it should only be updated when selections actually change
}

- (void)dismissView {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)downloadSelectedItems {
    NSInteger totalSelected = self.selectedIndexes.count + self.selectedVideoIndexes.count;
    if (totalSelected == 0) {
        [self showToastWithTitle:@"No items selected" subtitle:@"Please select items to download" icon:[UIImage systemImageNamed:@"exclamationmark.triangle"] seconds:3 openURL:nil];
        return;
    }

    // Save To is read once here and passed down: a mid-save toggle can't split one save.
    BOOL toPhotos = ThetaSettingChoiceIs(THSaveMethod, @"camera_roll");
    if (!toPhotos) {
        [self startDownloadingSelectedItemsToPhotos:NO];
        return;
    }
    // Photos access is checked before anything starts: on denial the picker stays open and nothing downloads.
    [ThetaHelper ensurePhotosAccess:^(BOOL granted) {
        if (!granted) {
            [ThetaHelper showSaveFailure:[ThetaHelper saveErrorWithCode:ThetaSaveErrorPhotosAccess message:@"Photos access is off" underlying:nil]];
            return;
        }
        [self startDownloadingSelectedItemsToPhotos:YES];
    }];
}

- (void)startDownloadingSelectedItemsToPhotos:(BOOL)toPhotos {
    // Enforce single active download (ThetaHelper's lock; showCompletionToast is the one place that releases it)
    if (![ThetaHelper tryBeginGlobalDownloadOrNotify]) return;

    // dismiss view controller
    [self dismissViewControllerAnimated:YES completion:nil];
    
    // Show initial progress toast
    CustomToastView *progressToast = [CustomToastView showProgressToastWithTitle:@"Starting download..." subtitle:@"Preparing to download selected items"];
    
    // Separate regular media and video items
    NSArray *selectedRegularItems = [self.selectedIndexes allObjects];
    NSMutableArray<IGVideo *> *selectedHDVideos = [NSMutableArray array];
    for (NSNumber *index in self.selectedVideoIndexes) {
        if (index.intValue < self.hdVideos.count) {
            [selectedHDVideos addObject:self.hdVideos[index.intValue]];
        }
    }
    
    NSInteger totalItems = selectedRegularItems.count + selectedHDVideos.count;
    // Photo results arrive on several queues: the counters are only touched on this serial queue.
    dispatch_queue_t countQueue = dispatch_queue_create("com.theta.photocounts", DISPATCH_QUEUE_SERIAL);
    __block NSInteger completedItems = 0;
    __block NSInteger failedItems = 0;
    
    // Update toast to show we're starting with photos
    if (selectedRegularItems.count > 0) {
        [progressToast updateProgressWithTitle:@"Downloading photos..." subtitle:[NSString stringWithFormat:@"Processing %ld photos first", (long)selectedRegularItems.count]];
    }
    
    // Download regular media items first (photos)
    if (selectedRegularItems.count > 0) {
        dispatch_group_t group = dispatch_group_create();
        NSOperationQueue *queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 15;

        for (NSInteger i = 0; i < selectedRegularItems.count; i++) {
            NSNumber *index = selectedRegularItems[i];
            NSDictionary *media = self.mediaItems[index.intValue];
            NSURL *url = [NSURL URLWithString:media[@"url"]];
            
            dispatch_group_enter(group);
            [queue addOperationWithBlock:^{
                [self performDownloadWithURL:url toPhotos:toPhotos completion:^(NSString *filePath, NSString *fileExtension, NSError *error) {
                    __block NSInteger done = 0;
                    dispatch_sync(countQueue, ^{
                        completedItems++;
                        if (!filePath) failedItems++;
                        done = completedItems;
                    });
                    
                    // Update toast with photo progress
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [progressToast updateProgressWithTitle:@"Downloading photos..." subtitle:[NSString stringWithFormat:@"%ld of %ld photos completed", (long)done, (long)selectedRegularItems.count]];
                    });
                    
                    dispatch_group_leave(group);
                }];
            }];
        }

        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            __block NSInteger completed = 0, failed = 0;
            dispatch_sync(countQueue, ^{
                completed = completedItems;
                failed = failedItems;
            });
            
            // If all photos are done, start videos
            if (selectedHDVideos.count > 0) {
                [progressToast updateProgressWithTitle:@"Downloading videos..." subtitle:[NSString stringWithFormat:@"Processing %ld videos", (long)selectedHDVideos.count]];
                
                // Start downloading videos
                [self downloadHDVideosBulk:selectedHDVideos progressToast:progressToast completed:completed total:totalItems failed:failed toPhotos:toPhotos];
            } else {
                [self showCompletionToast:progressToast completed:completed total:totalItems failed:failed toPhotos:toPhotos];
            }
        });
    } else if (selectedHDVideos.count > 0) {
        // If no photos, start videos immediately
        [progressToast updateProgressWithTitle:@"Downloading videos..." subtitle:[NSString stringWithFormat:@"Processing %ld videos", (long)selectedHDVideos.count]];
        [self downloadHDVideosBulk:selectedHDVideos progressToast:progressToast completed:0 total:totalItems failed:0 toPhotos:toPhotos];
    } else {
        [self showCompletionToast:progressToast completed:0 total:0 failed:0 toPhotos:toPhotos];
    }
}

/** Single download-and-save for feed/reels/story/view-once/profile/Instants photos. Save To is read once, here. */
- (void)downloadMediaToTemp:(NSURL *)url completion:(void(^)(NSString *filePath, NSString *fileExtension, NSError *error))completion {
    BOOL toPhotos = ThetaSettingChoiceIs(THSaveMethod, @"camera_roll");
    if (!toPhotos) {
        [self performDownloadWithURL:url toPhotos:NO completion:completion];
        return;
    }
    [ThetaHelper ensurePhotosAccess:^(BOOL granted) {
        if (!granted) {
            if (completion) completion(nil, nil, [ThetaHelper saveErrorWithCode:ThetaSaveErrorPhotosAccess message:@"Photos access is off" underlying:nil]);
            return;
        }
        [self performDownloadWithURL:url toPhotos:YES completion:completion];
    }];
}

/** File extension for a download: the URL's, else from the MIME type. */
static NSString *ThetaDownloadExtension(NSURL *url, NSURLResponse *response) {
    NSString *fileExtension = [[url pathExtension] lowercaseString];
    if (fileExtension.length > 0) return fileExtension;
    NSString *mime = [[response MIMEType] lowercaseString];
    if ([mime hasPrefix:@"image/"]) {
        if ([mime isEqualToString:@"image/png"]) return @"png";
        if ([mime isEqualToString:@"image/heic"] || [mime isEqualToString:@"image/heif"]) return @"heic";
        if ([mime isEqualToString:@"image/webp"]) return @"webp";
        return @"jpg";
    }
    if ([mime hasPrefix:@"video/"]) {
        return [mime isEqualToString:@"video/quicktime"] ? @"mov" : @"mp4";
    }
    if ([mime hasPrefix:@"audio/"]) {
        if ([mime isEqualToString:@"audio/aac"]) return @"aac";
        if ([mime isEqualToString:@"audio/mpeg"]) return @"mp3";
        return @"m4a";
    }
    return @"mp4";
}

/** Image type from the file's first bytes (a CDN path or MIME type can disagree with them); nil when not an image. */
static NSString *ThetaSniffImageUTI(NSString *path) {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    NSData *head = [handle readDataOfLength:16];
    [handle closeFile];
    if (head.length < 12) return nil;
    const unsigned char *b = head.bytes;
    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return @"public.jpeg";
    if (b[0] == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G') return @"public.png";
    if (!memcmp(b, "GIF8", 4)) return @"com.compuserve.gif";
    if (!memcmp(b, "RIFF", 4) && !memcmp(b + 8, "WEBP", 4)) return @"org.webmproject.webp";
    if (!memcmp(b + 4, "ftyp", 4)) {
        if (!memcmp(b + 8, "heic", 4) || !memcmp(b + 8, "heix", 4) || !memcmp(b + 8, "mif1", 4)) return @"public.heic";
        if (!memcmp(b + 8, "avif", 4)) return @"public.avif";
    }
    return nil;
}

/** Photos from the downloaded file: original bytes and metadata are kept, typed by `uti` when known. If Photos
    rejects the file, it is decoded and saved as an image once more before the save fails. */
static void ThetaImportPhotoFile(NSString *path, NSString *uti, void (^completion)(NSError *error)) {
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    void (^fail)(NSError *) = ^(NSError *error) {
        completion([ThetaHelper saveErrorWithCode:ThetaSaveErrorPhotosWrite message:error.localizedDescription ?: @"Photos couldn't save this photo" underlying:error]);
    };
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
        PHAssetResourceCreationOptions *options = [PHAssetResourceCreationOptions new];
        options.shouldMoveFile = NO;
        if (uti.length) options.uniformTypeIdentifier = uti;
        [request addResourceWithType:PHAssetResourceTypePhoto fileURL:fileURL options:options];
    } completionHandler:^(BOOL success, NSError *error) {
        if (success) {
            completion(nil);
            return;
        }
        UIImage *image = [UIImage imageWithContentsOfFile:path];
        if (!image) {
            fail(error);
            return;
        }
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromImage:image];
        } completionHandler:^(BOOL retryOK, NSError *retryError) {
            if (retryOK) completion(nil);
            else fail(retryError ?: error);
        }];
    }];
}

/** Downloads `url` and saves it (Photos or Saved Media, as `toPhotos`). On failure `filePath` is nil and `error` set.
    In Photos mode the staged file is deleted after the save and `filePath` is its old path. */
- (void)performDownloadWithURL:(NSURL *)url toPhotos:(BOOL)toPhotos completion:(void(^)(NSString *filePath, NSString *fileExtension, NSError *error))completion {
    void (^fail)(NSError *) = ^(NSError *error) {
        THDebugLog(@"media save failed (%@ %ld)", error.domain, (long)error.code);
        if (completion) completion(nil, nil, error);
    };
    @try {
        NSURLSessionDownloadTask *downloadTask = [[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
            NSError *failure = [ThetaHelper downloadFailureForResponse:response error:error];
            if (!failure && !location) failure = [ThetaHelper saveErrorWithCode:ThetaSaveErrorDownload message:@"Download failed" underlying:nil];
            if (failure) {
                fail(failure);
                return;
            }

            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *fileExtension = ThetaDownloadExtension(url, response);
            NSString *stagedPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"media-%@.%@", [[NSUUID UUID] UUIDString], fileExtension]];

            NSError *moveError = nil;
            if (![fm moveItemAtURL:location toURL:[NSURL fileURLWithPath:stagedPath] error:&moveError]) {
                fail([ThetaHelper saveErrorWithCode:ThetaSaveErrorFile message:@"Couldn't save the file" underlying:moveError]);
                return;
            }

            if (toPhotos) {
                void (^finish)(NSError *) = ^(NSError *saveError) {
                    [fm removeItemAtPath:stagedPath error:nil];
                    if (saveError) fail(saveError);
                    else if (completion) completion(stagedPath, fileExtension, nil);
                };
                // The bytes decide photo or video; the extension only when they aren't a known image.
                NSString *imageUTI = ThetaSniffImageUTI(stagedPath);
                BOOL videoExtension = [fileExtension isEqualToString:@"mp4"] || [fileExtension isEqualToString:@"mov"] || [fileExtension isEqualToString:@"m4v"];
                if (!imageUTI && videoExtension) {
                    ThetaPhotoLibraryImportVideoFromURL([NSURL fileURLWithPath:stagedPath], ^(BOOL ok, NSError *importError) {
                        finish(ok ? nil : [ThetaHelper saveErrorWithCode:ThetaSaveErrorPhotosWrite message:importError.localizedDescription ?: @"Photos couldn't import this video" underlying:importError]);
                    });
                } else {
                    ThetaImportPhotoFile(stagedPath, imageUTI, finish);
                }
            } else {
                // Saved Media: one move, under the download's own unique name
                NSError *folderError = nil;
                NSString *destPath = [ThetaHelper moveIntoSavedMedia:stagedPath name:[stagedPath lastPathComponent] error:&folderError];
                if (!destPath) {
                    [fm removeItemAtPath:stagedPath error:nil];
                    fail([ThetaHelper saveErrorWithCode:ThetaSaveErrorFile message:@"Couldn't save to Saved Media" underlying:folderError]);
                    return;
                }
                if (completion) completion(destPath, fileExtension, nil);
            }
        }];
        [downloadTask resume];
    } @catch (NSException *exception) {
        THDebugLog(@"media download raised: %@", exception.name);
        fail([ThetaHelper saveErrorWithCode:ThetaSaveErrorDownload message:@"Download failed" underlying:nil]);
    }
}

// Always download and place the file into Documents/AudioNotes, regardless of Save Method.
- (void)performDownloadToAudioNotesWithURL:(NSURL *)url completion:(void(^)(NSString *filePath, NSString *fileExtension))completion {
    @try {
        NSURLSessionDownloadTask *downloadTask = [[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
            NSError *failure = [ThetaHelper downloadFailureForResponse:response error:error];
            if (failure || !location) {
                THDebugLog(@"audio download failed (%@ %ld)", failure.domain, (long)failure.code);
                if (completion) completion(nil, nil);
                return;
            }

            // Straight into Saved Media: no staged copy in Documents for Clear Cache to find.
            NSString *fileExtension = ThetaDownloadExtension(url, response);
            NSError *moveError = nil;
            NSString *destPath = [ThetaHelper moveIntoSavedMedia:location.path name:[NSString stringWithFormat:@"media-%@.%@", [[NSUUID UUID] UUIDString], fileExtension] error:&moveError];
            if (!destPath) THDebugLog(@"audio move failed: %@", moveError);

            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(destPath, destPath ? fileExtension : nil);
            });
        }];
        [downloadTask resume];
    } @catch (NSException *exception) {
        THDebugLog(@"audio download raised: %@", exception.name);
        if (completion) completion(nil, nil);
    }
}

- (UIButton *)selectAllButton {
    if (!_selectAllButton) {
        _selectAllButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 150, 30)];
        [_selectAllButton setTitle:@"Select All" forState:UIControlStateNormal];
        [_selectAllButton addTarget:self action:@selector(selectAllButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    }
    return _selectAllButton;
}

#pragma mark - HD Video Download Methods

/** Entry point of the bulk video save. The setup in `startHDVideosBulk` runs before any item is in flight, so an
    exception there ends the whole job once (all videos failed, lock released). */
- (void)downloadHDVideosBulk:(NSArray<IGVideo *> *)videos progressToast:(CustomToastView *)progressToast completed:(NSInteger)completedItems total:(NSInteger)totalItems failed:(NSInteger)failedItems toPhotos:(BOOL)toPhotos {
    @try {
        [self startHDVideosBulk:videos progressToast:progressToast completed:completedItems total:totalItems failed:failedItems toPhotos:toPhotos];
    } @catch (NSException *exception) {
        THDebugLog(@"bulk video save raised: %@", exception.name);
        [self showCompletionToast:progressToast completed:totalItems total:totalItems failed:failedItems + (NSInteger)videos.count toPhotos:toPhotos];
    }
}

- (void)startHDVideosBulk:(NSArray<IGVideo *> *)videos progressToast:(CustomToastView *)progressToast completed:(NSInteger)completedItems total:(NSInteger)totalItems failed:(NSInteger)failedItems toPhotos:(BOOL)toPhotos {
    if (!videos || videos.count == 0) {
        // Nothing to run: still end the save (releases the lock).
        [self showCompletionToast:progressToast completed:completedItems total:totalItems failed:failedItems toPhotos:toPhotos];
        return;
    }
    
    if (!progressToast) {
        progressToast = [CustomToastView showProgressToastWithTitle:@"Bulk saving videos!" subtitle:[NSString stringWithFormat:@"Preparing %lu videos...", (unsigned long)videos.count]];
    }
    
    static const NSInteger maxConcurrentDownloads = 3;
    static const NSInteger maxConcurrentTranscoding = 2;
    
    // One slot per video in flight, from its start until finishItem: with the serial feeder below this
    // bounds the threads a bulk save uses, however many videos are selected.
    dispatch_semaphore_t itemSlots = dispatch_semaphore_create(maxConcurrentDownloads);
    dispatch_semaphore_t transcodeSemaphore = dispatch_semaphore_create(maxConcurrentTranscoding);
    
    __block NSInteger completedVideos = completedItems;
    __block NSInteger totalVideos = totalItems;
    __block NSInteger failedVideos = failedItems;
    
    __block NSTimeInterval bulkProcessStartTime = [[NSDate date] timeIntervalSince1970];
    
    dispatch_queue_t statsQueue = dispatch_queue_create("com.theta.bulkstats", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_t processingQueue = dispatch_queue_create("com.theta.bulkdownload", DISPATCH_QUEUE_CONCURRENT);
    dispatch_queue_t feederQueue = dispatch_queue_create("com.theta.bulkfeeder", DISPATCH_QUEUE_SERIAL);
    
    // Track progress for each video
    NSMutableDictionary<NSNumber *, NSMutableDictionary *> *videoProgress = [NSMutableDictionary dictionary];
    for (NSInteger i = 0; i < videos.count; i++) {
        videoProgress[@(i)] = [NSMutableDictionary dictionaryWithDictionary:@{
            @"state": @"pending",  // pending, downloading, transcoding, saving, done
            @"progress": @(0.0),
            @"status": @"Waiting..."
        }];
    }
    
    // Helper to format multi-line progress display
    NSString* (^formatProgressDisplay)(void) = ^NSString*() {
        
        dispatch_sync(statsQueue, ^{
            // Show active videos (not pending or done)
            for (NSInteger i = 0; i < videos.count; i++) {
                NSDictionary *info = videoProgress[@(i)];
                NSString *state = info[@"state"];
                
                if (![state isEqualToString:@"pending"] && ![state isEqualToString:@"done"]) {
                    float vidProgress = [info[@"progress"] floatValue];
                    // Update per-item UIProgressView via CustomToastView helper
                    // Title is ignored (we render a bullet only), so pass nil
                    [progressToast updatePerItemProgressAtIndex:i title:nil progress:vidProgress];
                }
            }
            
            // If nothing active, we can optionally show a simple summary in subtitle
            if (completedVideos >= totalVideos && totalVideos > 0) {
                NSTimeInterval elapsed = [[NSDate date] timeIntervalSince1970] - bulkProcessStartTime;
                NSString *timeStr = @"";
                
                if (completedVideos > 0 && totalVideos > 0 && elapsed > 3.0) {
                    double percentage = (double)completedVideos / (double)totalVideos * 100.0;
                    if (percentage > 0.5) {
                        NSTimeInterval estimatedTotal = elapsed / (percentage / 100.0);
                        NSTimeInterval remaining = estimatedTotal - elapsed;
                        
                        if (remaining > 0) {
                            if (remaining < 60) {
                                timeStr = [NSString stringWithFormat:@" • %ds left", (int)remaining];
                            } else if (remaining < 3600) {
                                int minutes = (int)(remaining / 60);
                                int seconds = (int)fmod(remaining, 60);
                                timeStr = [NSString stringWithFormat:@" • %dm %ds left", minutes, seconds];
                            }
                        }
                    }
                }
                
                NSString *summary = [NSString stringWithFormat:@"Saved %ld/%ld to %@%@", (long)(completedVideos - failedVideos), (long)totalVideos, toPhotos ? @"camera roll" : @"Saved Media", timeStr];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [progressToast updateProgressWithTitle:@"Saved!"
                                                  subtitle:summary];
                });
            }
        });
        
        return @""; // not used as text anymore
    };
    
    // Helper block to calculate time string for individual video progress
    NSString* (^formatTimeString)(NSTimeInterval) = ^NSString*(NSTimeInterval seconds) {
        if (seconds < 60) {
            return [NSString stringWithFormat:@"%ds left", (int)seconds];
        } else if (seconds < 3600) {
            int minutes = (int)(seconds / 60);
            int secs = (int)fmod(seconds, 60);
            return [NSString stringWithFormat:@"%dm %ds left", minutes, secs];
        } else {
            int hours = (int)(seconds / 3600);
            int minutes = (int)(fmod(seconds, 3600) / 60);
            return [NSString stringWithFormat:@"%dh %dm left", hours, minutes];
        }
    };
    
    /* The one way an item ends, on every path (early failures included): counts it, and when it was
       the last one shows the result, which also releases the download lock. */
    void (^finishItem)(BOOL, NSInteger, NSString *) = ^(BOOL failed, NSInteger videoIndex, NSString *status) {
        dispatch_semaphore_signal(itemSlots); // frees the feeder to start the next video
        dispatch_async(statsQueue, ^{
            videoProgress[@(videoIndex)][@"state"] = @"done";
            if (status) videoProgress[@(videoIndex)][@"status"] = status;
            if (failed) failedVideos++;
            completedVideos++;
            NSInteger completedNow = completedVideos, failedNow = failedVideos;
            dispatch_async(dispatch_get_main_queue(), ^{
                [progressToast updateProgressWithTitle:@"Bulk saving videos!" subtitle:formatProgressDisplay()];
                if (completedNow >= totalVideos) {
                    [self showCompletionToast:progressToast completed:completedNow total:totalVideos failed:failedNow toPhotos:toPhotos];
                }
            });
        });
    };
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *stagingPath = NSTemporaryDirectory();
    
    // Configure per-item UIProgressView rows in the toast (one bar per video)
    dispatch_async(dispatch_get_main_queue(), ^{
        [progressToast setupPerItemProgressWithCount:videos.count];
    });
    
    // Serial feeder: one parked thread waits for a free slot, the videos themselves run on the concurrent queue
    dispatch_async(feederQueue, ^{
    // Process each video
    for (NSInteger i = 0; i < videos.count; i++) {
        dispatch_semaphore_wait(itemSlots, DISPATCH_TIME_FOREVER);
        IGVideo *video = videos[i];
        NSInteger videoIndex = i;
        
        dispatch_async(processingQueue, ^{
            @autoreleasepool {
                // Update state to downloading
                dispatch_sync(statsQueue, ^{
                    videoProgress[@(videoIndex)][@"state"] = @"downloading";
                    videoProgress[@(videoIndex)][@"status"] = @"Starting download...";
                });
                formatProgressDisplay(); // Updates toast internally with progress
                
                NSData *videoData = [video valueForKey:@"dashManifestData"];
                if (!videoData) {
                    finishItem(YES, videoIndex, @"Failed");
                    return;
                }
                
                NSString *videoManifest = [[NSString alloc] initWithData:videoData encoding:NSUTF8StringEncoding];
                NSString *videoURLString = IGDashManifestBestCompatibleURL(videoManifest);
                NSString *audioURLString = IGDashManifestBestAudioURL(videoManifest);
                
                if (!videoURLString.length || ![NSURL URLWithString:videoURLString]) {
                    finishItem(YES, videoIndex, @"Failed");
                    return;
                }
                
                NSURL *audioTestURL = audioURLString.length > 0 ? [NSURL URLWithString:audioURLString] : nil;
                __block BOOL hasAudio = (audioURLString.length > 0 && audioTestURL != nil);
                
                // Unique per job so overlapping saves never share a file; theta_ names are swept at launch.
                NSString *jobID = [[NSUUID UUID] UUIDString];
                NSString *videoPath = [stagingPath stringByAppendingPathComponent:[NSString stringWithFormat:@"theta_bulk_video_%ld_%@.mp4", (long)videoIndex, jobID]];
                __block NSString *audioPath = hasAudio ? [stagingPath stringByAppendingPathComponent:[NSString stringWithFormat:@"theta_bulk_audio_%ld_%@.m4a", (long)videoIndex, jobID]] : nil;
                
                // Remove any existing files
                if ([fm fileExistsAtPath:videoPath]) [fm removeItemAtPath:videoPath error:nil];
                if (audioPath && [fm fileExistsAtPath:audioPath]) [fm removeItemAtPath:audioPath error:nil];
                
                NSURLSession *session = [NSURLSession sharedSession];
                dispatch_group_t downloadGroup = dispatch_group_create();
                __block BOOL audioFailed = NO; // a track that exists but didn't download fails the whole save
                
                __block NSTimeInterval downloadStartTime = [[NSDate date] timeIntervalSince1970];
                
                // Download video
                dispatch_group_enter(downloadGroup);
                dispatch_sync(statsQueue, ^{
                    videoProgress[@(videoIndex)][@"status"] = @"Downloading video...";
                });
                formatProgressDisplay(); // Updates toast internally with progress
                
                NSURLSessionDownloadTask *videoTask = [session downloadTaskWithURL:[NSURL URLWithString:videoURLString] completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                    NSError *failure = [ThetaHelper downloadFailureForResponse:response error:error];
                    if (failure || !location) {
                        THDebugLog(@"bulk video %ld download failed (%@ %ld)", (long)videoIndex, failure.domain, (long)failure.code);
                    } else {
                        // Only a 2xx body is moved into place
                        [fm moveItemAtPath:location.path toPath:videoPath error:nil];
                    }
                    dispatch_group_leave(downloadGroup);
                }];
                [videoTask resume];
                
                // Download audio if available
                if (hasAudio) {
                    dispatch_group_enter(downloadGroup);
                    dispatch_sync(statsQueue, ^{
                        videoProgress[@(videoIndex)][@"status"] = @"Downloading audio...";
                    });
                    
                    NSURLSessionDownloadTask *audioTask = [session downloadTaskWithURL:[NSURL URLWithString:audioURLString] completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                        NSError *failure = [ThetaHelper downloadFailureForResponse:response error:error];
                        if (failure || !location) {
                            audioFailed = YES;
                            THDebugLog(@"bulk audio %ld download failed (%@ %ld)", (long)videoIndex, failure.domain, (long)failure.code);
                        } else {
                            [fm moveItemAtPath:location.path toPath:audioPath error:nil];
                        }
                        dispatch_group_leave(downloadGroup);
                    }];
                    [audioTask resume];
                }
                
                // Wait for downloads to complete
                dispatch_group_wait(downloadGroup, DISPATCH_TIME_FOREVER);
                
                // Verify downloads (non-empty video)
                NSDictionary *downloadedVideoAttrs = [fm attributesOfItemAtPath:videoPath error:nil];
                if (audioFailed || ![fm fileExistsAtPath:videoPath] || !downloadedVideoAttrs || [downloadedVideoAttrs fileSize] == 0) {
                    [fm removeItemAtPath:videoPath error:nil];
                    if (audioPath) [fm removeItemAtPath:audioPath error:nil];
                    finishItem(YES, videoIndex, @"Download failed");
                    return;
                }
                if (hasAudio) {
                    NSString *preparedAudio = ThetaPrepareDashAudioForMerge(audioPath);
                    if (preparedAudio.length) {
                        audioPath = preparedAudio;
                    } else {
                        THDebugLog(@"Bulk %ld: audio file missing, empty, or undecodable; video only", (long)videoIndex);
                        hasAudio = NO;
                    }
                }
                
                // Detect video encoding (load tracks first — otherwise formatDescriptions is empty)
                /* Precise timing: a fragmented DASH segment reports duration 0 in its moov. */
                AVAsset *videoAsset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:videoPath] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
                {
                    dispatch_semaphore_t videoKeysSem = dispatch_semaphore_create(0);
                    [videoAsset loadValuesAsynchronouslyForKeys:@[@"tracks", @"duration"] completionHandler:^{
                        dispatch_semaphore_signal(videoKeysSem);
                    }];
                    dispatch_semaphore_wait(videoKeysSem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)));
                }
                BOOL isAV1Video = ThetaAssetVideoNeedsFFmpegTranscode(videoAsset);
                
                // Wait for transcoding slot
                dispatch_semaphore_wait(transcodeSemaphore, DISPATCH_TIME_FOREVER);
                
                dispatch_sync(statsQueue, ^{
                    videoProgress[@(videoIndex)][@"state"] = @"transcoding";
                    videoProgress[@(videoIndex)][@"status"] = @"Processing...";
                });
                formatProgressDisplay(); // Updates toast internally with progress
                
                NSString *outputPath = [stagingPath stringByAppendingPathComponent:[NSString stringWithFormat:@"theta_bulk_output_%ld_%@.mp4", (long)videoIndex, jobID]];
                if ([fm fileExistsAtPath:outputPath]) [fm removeItemAtPath:outputPath error:nil];
                
                __block NSTimeInterval transcodeStartTime = [[NSDate date] timeIntervalSince1970];
                
                if (isAV1Video) {
                    // FFmpeg path for AV1 / VP9 (AVAsset export cannot re-encode these)
                    NSError *transcodeError = nil;
                    BOOL transcodeSuccess = ThetaTranscodeWithAssetReaderWriter(videoPath, audioPath, hasAudio, outputPath);
                    if (!transcodeSuccess) {
                    transcodeSuccess = [AV1Transcoder transcodeAV1ToH264:videoPath
                                                                    outputPath:outputPath
                                                                     audioPath:hasAudio ? audioPath : nil
                                                                         error:&transcodeError
                                                                 progressBlock:^(NSString *status, float progress) {
                        // Update progress for this specific video
                        dispatch_sync(statsQueue, ^{
                            videoProgress[@(videoIndex)][@"progress"] = @(progress);
                            videoProgress[@(videoIndex)][@"status"] = @"Transcoding...";
                        });
                        
                        // Update UI periodically
                        static NSTimeInterval lastUIUpdate = 0;
                        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
                        if (now - lastUIUpdate > 0.5) {
                            lastUIUpdate = now;
                            formatProgressDisplay(); // updates inline bars per item
                        }
                    }];
                    }
                    
                    dispatch_semaphore_signal(transcodeSemaphore);
                    
                    if (!transcodeSuccess) {
                        THDebugLog(@"Transcoding failed for video %ld (%@)", (long)videoIndex, transcodeError);
                        if ([fm fileExistsAtPath:outputPath]) [fm removeItemAtPath:outputPath error:nil];
                        [fm removeItemAtPath:videoPath error:nil];
                        if (audioPath) [fm removeItemAtPath:audioPath error:nil];
                        BOOL interrupted = [transcodeError.domain isEqualToString:@"AV1Transcoder"] && transcodeError.code == -2;
                        finishItem(YES, videoIndex, interrupted ? @"Conversion interrupted" : @"Transcoding failed");
                        return;
                    }
                    
                } else {
                    dispatch_sync(statsQueue, ^{
                        videoProgress[@(videoIndex)][@"status"] = @"Merging...";
                    });
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [progressToast updateProgressWithTitle:@"Bulk saving videos!" subtitle:formatProgressDisplay()];
                    });
                    
                    AVMutableComposition *composition = [AVMutableComposition composition];
                    AVMutableCompositionTrack *compositionVideoTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
                    
                    AVAssetTrack *videoTrackForMerge = [[videoAsset tracksWithMediaType:AVMediaTypeVideo] firstObject];
                    AVAsset *audioAssetForMerge = nil;
                    AVAssetTrack *audioTrackForMerge = nil;
                    if (hasAudio && audioPath && [fm fileExistsAtPath:audioPath]) {
                        audioAssetForMerge = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:audioPath] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];
                        audioTrackForMerge = [[audioAssetForMerge tracksWithMediaType:AVMediaTypeAudio] firstObject];
                    }
                    
                    CMTime videoDur = videoAsset.duration;
                    /* mergeDur is derived from videoDur, so falling back to videoDur cannot rescue a
                       bad value — and insertTimeRange: raises on an invalid range instead of
                       reporting through its error out-param. */
                    BOOL durationUsable = CMTIME_IS_NUMERIC(videoDur) && CMTIME_COMPARE_INLINE(videoDur, >, kCMTimeZero);
                    CMTime mergeDur = videoDur;
                    if (durationUsable && audioTrackForMerge && audioAssetForMerge && CMTIME_IS_NUMERIC(audioAssetForMerge.duration)
                        && CMTIME_COMPARE_INLINE(audioAssetForMerge.duration, >, kCMTimeZero)) {
                        mergeDur = CMTimeMinimum(videoDur, audioAssetForMerge.duration);
                    }
                    if (!CMTIME_IS_NUMERIC(mergeDur) || CMTIME_COMPARE_INLINE(mergeDur, <=, kCMTimeZero)) {
                        mergeDur = videoDur;
                    }
                    CMTimeRange mergeRange = CMTimeRangeMake(kCMTimeZero, mergeDur);
                    
                    NSError *videoInsertError = nil;
                    if (videoTrackForMerge) {
                        if (!durationUsable) {
                            videoInsertError = [NSError errorWithDomain:@"Theta" code:-10
                                                              userInfo:@{NSLocalizedDescriptionKey: @"Unusable video duration"}];
                        } else {
                            [compositionVideoTrack insertTimeRange:mergeRange ofTrack:videoTrackForMerge atTime:kCMTimeZero error:&videoInsertError];
                        }
                        if (videoInsertError) {
                            THDebugLog(@"Error adding video track for video %ld: %@", (long)videoIndex, videoInsertError);
                            dispatch_semaphore_signal(transcodeSemaphore);
                            [fm removeItemAtPath:videoPath error:nil];
                            if (audioPath) [fm removeItemAtPath:audioPath error:nil];
                            
                            finishItem(YES, videoIndex, @"Merge failed");
                            return;
                        }
                    }
                    
                    if (audioTrackForMerge) {
                        AVMutableCompositionTrack *compositionAudioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
                        NSError *audioInsertError = nil;
                        [compositionAudioTrack insertTimeRange:mergeRange ofTrack:audioTrackForMerge atTime:kCMTimeZero error:&audioInsertError];
                        if (audioInsertError) {
                            THDebugLog(@"Error adding audio track for video %ld: %@", (long)videoIndex, audioInsertError);
                        }
                    }
                    
                    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetHighestQuality];
                    exportSession.outputURL = [NSURL fileURLWithPath:outputPath];
                    BOOL canWriteMP4 = ThetaExportSessionSetFileType(exportSession, AVFileTypeMPEG4);
                    if ([exportSession respondsToSelector:@selector(setShouldOptimizeForNetworkUse:)]) {
                        exportSession.shouldOptimizeForNetworkUse = YES;
                    }
                    
                    dispatch_semaphore_t exportSemaphore = dispatch_semaphore_create(0);
                    if (canWriteMP4) {
                        [exportSession exportAsynchronouslyWithCompletionHandler:^{
                            dispatch_semaphore_signal(exportSemaphore);
                        }];
                        dispatch_semaphore_wait(exportSemaphore, DISPATCH_TIME_FOREVER);
                    } else {
                        THDebugLog(@"Bulk %ld: export session cannot write MPEG-4", (long)videoIndex);
                    }
                    
                    dispatch_semaphore_signal(transcodeSemaphore);
                    
                    if (!canWriteMP4 || exportSession.status != AVAssetExportSessionStatusCompleted) {
                        THDebugLog(@"Export failed for video %ld: %@", (long)videoIndex, exportSession.error);
                        if ([fm fileExistsAtPath:outputPath]) [fm removeItemAtPath:outputPath error:nil];
                        NSError *transcodeError = nil;
                        BOOL fallbackOK = [AV1Transcoder transcodeAV1ToH264:videoPath
                                                                outputPath:outputPath
                                                                 audioPath:hasAudio ? audioPath : nil
                                                                     error:&transcodeError
                                                             progressBlock:nil];
                        if (!fallbackOK) {
                            fallbackOK = ThetaExportPhotosCompatibleMP4(videoPath, audioPath, hasAudio, outputPath);
                        }
                        NSDictionary *fallbackAttrs = [fm attributesOfItemAtPath:outputPath error:nil];
                        if (fallbackOK && fallbackAttrs && [fallbackAttrs fileSize] > 0) {
                            // Fall through to the camera-roll / folder save below.
                        } else {
                        THDebugLog(@"Bulk %ld: FFmpeg fallback after export failure failed (%@)", (long)videoIndex, transcodeError);
                        // Cleanup
                        [fm removeItemAtPath:videoPath error:nil];
                        if (audioPath) [fm removeItemAtPath:audioPath error:nil];
                        
                        finishItem(YES, videoIndex, @"Export failed");
                        return;
                        }
                    }
                    
                }
                
                // Save to Photos or Saved Media, as read once when the picker started
                if (toPhotos) {
                    // The same Photos import as a single save, straight from the merged file
                    ThetaPhotoLibraryImportVideoFromURL([NSURL fileURLWithPath:outputPath], ^(BOOL savedOK, NSError *error) {
                        [fm removeItemAtPath:videoPath error:nil];
                        if (audioPath) [fm removeItemAtPath:audioPath error:nil];
                        [fm removeItemAtPath:outputPath error:nil];
                        if (!savedOK) THDebugLog(@"Failed to save video %ld: %@", (long)videoIndex, error);
                        finishItem(!savedOK, videoIndex, nil);
                    });
                } else {
                    // Save to Saved Media
                    NSDateFormatter *formatter = [NSDateFormatter new];
                    [formatter setDateFormat:@"yyyyMMdd-HHmmss"];
                    NSString *destName = [NSString stringWithFormat:@"Video-%@_%ld.mp4", [formatter stringFromDate:[NSDate date]], (long)videoIndex];
                    
                    NSError *moveError = nil;
                    NSString *destPath = [ThetaHelper moveIntoSavedMedia:outputPath name:destName error:&moveError];
                    
                    // Cleanup
                    [fm removeItemAtPath:videoPath error:nil];
                    if (audioPath) [fm removeItemAtPath:audioPath error:nil];
                    if (!destPath) {
                        THDebugLog(@"Failed to move video %ld to Saved Media: %@", (long)videoIndex, moveError);
                        [fm removeItemAtPath:outputPath error:nil];
                    }
                    finishItem(destPath == nil, videoIndex, nil);
                }
            }
        });
    }
    });
}

- (void)setupVideoPlayerForCell:(UIView *)cardView atIndex:(NSInteger)videoIndex {
    // Remove any existing video player
    for (UIView *subview in cardView.subviews) {
        if ([subview isKindOfClass:[AVPlayerLayer class]] || ([subview isKindOfClass:[UIView class]] && subview.tag == 999)) {
            [subview removeFromSuperview];
        }
    }
    
    // Try to get preloaded player first
    NSString *playerKey = [NSString stringWithFormat:@"video_player_%ld", (long)videoIndex];
    AVPlayer *player = [self.previewCache objectForKey:playerKey];
    
    if (!player) {
        // Fallback: create new player if preloaded one not available
        IGVideo *video = self.hdVideos[videoIndex];
        NSSet *videoURLs = [video allVideoURLs];
        if (!videoURLs || videoURLs.count == 0) {
            return;
        }
        
        NSURL *videoURL = [videoURLs anyObject];
        player = [AVPlayer playerWithURL:videoURL];
        
        // Cache the player for future use
        [self.previewCache setObject:player forKey:playerKey];
    }
    
    // Use the helper method to set up the player layer
    [self setupVideoPlayerLayer:cardView withPlayer:player];
    
    // Store player reference for cleanup
    cardView.tag = 999; // Mark as having video player
}

/** Calls `done(YES)` on the main queue once the player's item is ready, `done(NO)` if it failed or `deadline` passed. */
static void ThetaPollPlayerReady(AVPlayer *player, NSDate *deadline, void (^done)(BOOL ready)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        AVPlayerItemStatus status = player.currentItem.status;
        if (status == AVPlayerItemStatusReadyToPlay) { done(YES); return; }
        if (status == AVPlayerItemStatusFailed || deadline.timeIntervalSinceNow <= 0) { done(NO); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ThetaPollPlayerReady(player, deadline, done);
        });
    });
}

+ (void)preloadHDVideoThumbnails:(NSArray<IGVideo *> *)hdVideos completion:(void(^)(void))completion {
    if (!hdVideos || hdVideos.count == 0) {
        if (completion) completion();
        return;
    }
    
    THDebugLog(@"Preloading HD video players for %ld videos", (long)hdVideos.count);
    
    dispatch_group_t group = dispatch_group_create();
    NSMutableDictionary *videoPlayers = [[NSMutableDictionary alloc] init];
    
    for (NSInteger i = 0; i < hdVideos.count; i++) {
        dispatch_group_enter(group);
        
        IGVideo *video = hdVideos[i];
        NSSet *videoURLs = [video allVideoURLs];
        
        if (!videoURLs || videoURLs.count == 0) {
            dispatch_group_leave(group);
            continue;
        }
        
        NSURL *videoURL = [videoURLs anyObject];
        
        // Create AVPlayer with muted audio
        AVPlayer *player = [AVPlayer playerWithURL:videoURL];
        player.muted = YES; // Mute the video
        player.actionAtItemEnd = AVPlayerActionAtItemEndNone; // Don't pause at end
        
        // Set up looping with proper observer management
        __weak typeof(player) weakPlayer = player;
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                                        object:player.currentItem
                                                                         queue:[NSOperationQueue mainQueue]
                                                                    usingBlock:^(NSNotification *notification) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (weakPlayer && weakPlayer.currentItem) {
                    [weakPlayer seekToTime:kCMTimeZero completionHandler:^(BOOL finished) {
                        if (finished) {
                            [weakPlayer play];
                        }
                    }];
                }
            });
        }];
        
        // Store the observer reference
        objc_setAssociatedObject(player, "loopObserver", observer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        // Leave the group as soon as the item is ready (or failed), after 3 s at the latest
        NSString *key = [NSString stringWithFormat:@"video_player_%ld", (long)i];
        ThetaPollPlayerReady(player, [NSDate dateWithTimeIntervalSinceNow:3.0], ^(BOOL ready) {
            if (ready) {
                videoPlayers[key] = player;
                THDebugLog(@"Preloaded video player %ld", (long)i);
            } else {
                THDebugLog(@"Failed to preload video player %ld", (long)i);
            }
            dispatch_group_leave(group);
        });
        
        // Start loading the video
        [player play];
        [player pause]; // Pause immediately but keep loaded
    }
    
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        // Store preloaded players in shared cache
        NSCache *sharedCache = [self sharedPreviewCache];
        for (NSString *key in videoPlayers) {
            [sharedCache setObject:videoPlayers[key] forKey:key];
        }
        
        THDebugLog(@"Preloaded %ld HD video players", (long)videoPlayers.count);
        if (completion) completion();
    });
}

+ (NSCache *)sharedPreviewCache {
    static NSCache *sharedCache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedCache = [[NSCache alloc] init];
        sharedCache.countLimit = 100;
    });
    return sharedCache;
}

// Convert a media file to MP3 using FFmpegKit. On success returns output .mp3 path and deletes input.
- (void)convertFileToMP3:(NSString *)inputPath completion:(void(^)(NSString *outputPath, NSError *error))completion {
    if (inputPath.length == 0) {
        if (completion) completion(nil, [NSError errorWithDomain:@"theta" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Empty input path"}]);
        return;
    }

    NSString *dir = [inputPath stringByDeletingLastPathComponent];
    NSString *base = [[inputPath lastPathComponent] stringByDeletingPathExtension];
    NSString *outputPath = [dir stringByAppendingPathComponent:[base stringByAppendingPathExtension:@"mp3"]];

    static dispatch_queue_t mp3ConversionQueue;
    static dispatch_once_t mp3OnceToken;
    dispatch_once(&mp3OnceToken, ^{
        mp3ConversionQueue = dispatch_queue_create("theta.ffmpeg.mp3.queue", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_async(mp3ConversionQueue, ^{
        @autoreleasepool {
            static void *ffmpegkitHandle = NULL;
            static Class FFmpegKitClass = NULL;
            static dispatch_once_t onceToken;
            __block NSString *frameworkPath;

            dispatch_once(&onceToken, ^{
                /* dylibs/ffmpegkit.dylib is where scripts/isolate-ffmpeg-dylibs.py puts it, with its
                   @rpath dependencies rewritten to @loader_path so it binds to our libav* and not
                   to the stripped ones Instagram bundles. The other paths are older layouts. */
                NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
                NSString *frameworksPath = [[NSBundle mainBundle] privateFrameworksPath];
                NSMutableArray *sideloadPaths = [NSMutableArray array];
                for (NSString *dir in @[bundlePath ?: @"", frameworksPath ?: @""]) {
                    if (!dir.length) continue;
                    NSString *root = [dir stringByAppendingPathComponent:@"ffmpeg.framework"];
                    for (NSString *rel in @[@"dylibs/ffmpegkit.dylib", @"ffmpegkit.framework/ffmpegkit", @"ffmpegkit"]) {
                        [sideloadPaths addObject:[root stringByAppendingPathComponent:rel]];
                    }
                }
                for (NSString *path in sideloadPaths) {
                    if (path.length > 0) {
                        frameworkPath = path;
                        ffmpegkitHandle = dlopen([frameworkPath UTF8String], RTLD_NOW);
                        if (ffmpegkitHandle) break;
                    }
                }
                FFmpegKitClass = objc_getClass("FFmpegKit");
            });

            if (!ffmpegkitHandle || !FFmpegKitClass) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(nil, [NSError errorWithDomain:@"theta" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"FFmpegKit not available"}]);
                });
                return;
            }

            NSString *command = [NSString stringWithFormat:@"-y -hide_banner -loglevel error -i '%@' -vn -map a -c:a libmp3lame -q:a 0 '%@'", inputPath, outputPath];
            NSMethodSignature *signature = [FFmpegKitClass methodSignatureForSelector:@selector(execute:)];
            if (!signature) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(nil, [NSError errorWithDomain:@"theta" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"FFmpegKit execute: not found"}]);
                });
                return;
            }
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            [invocation setTarget:FFmpegKitClass];
            [invocation setSelector:@selector(execute:)];
            [invocation setArgument:&command atIndex:2];

            id __unsafe_unretained session = nil;
            @try {
                [invocation invoke];
                [invocation getReturnValue:&session];
            } @catch (NSException *exception) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(nil, [NSError errorWithDomain:@"theta" code:-4 userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"FFmpegKit exception"}]);
                });
                return;
            }

            // Consider conversion successful if output file exists and is non-empty,
            // even if FFmpegKit return code isn't flagged success on this build.
            NSFileManager *fmCheck = [NSFileManager defaultManager];
            NSDictionary *attrs = [fmCheck attributesOfItemAtPath:outputPath error:nil];
            unsigned long long fsize = [[attrs objectForKey:NSFileSize] unsignedLongLongValue];
            BOOL fileOk = (attrs != nil && fsize > 0);
            if (!fileOk) {
                // Fallback to AAC/M4A if MP3 encoder unavailable
                NSString *m4aPath = [[inputPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"m4a"];
                NSString *aacCommand = [NSString stringWithFormat:@"-y -hide_banner -loglevel error -i '%@' -vn -map a -c:a aac -b:a 192k '%@'", inputPath, m4aPath];
                NSMethodSignature *sig2 = [FFmpegKitClass methodSignatureForSelector:@selector(execute:)];
                if (sig2) {
                    NSInvocation *inv2 = [NSInvocation invocationWithMethodSignature:sig2];
                    [inv2 setTarget:FFmpegKitClass];
                    [inv2 setSelector:@selector(execute:)];
                    [inv2 setArgument:&aacCommand atIndex:2];
                    id __unsafe_unretained s2 = nil;
                    @try { [inv2 invoke]; [inv2 getReturnValue:&s2]; } @catch (__unused NSException *e) {}
                    BOOL ok2 = NO;
                    if (s2 && [s2 respondsToSelector:@selector(getReturnCode)]) {
                        @try {
                            id rc2 = [s2 performSelector:@selector(getReturnCode)];
                            if (rc2 && [rc2 respondsToSelector:@selector(isSuccess)]) {
                                ok2 = [rc2 performSelector:@selector(isSuccess)];
                            }
                        } @catch (__unused NSException *e) {}
                    }
                    if (ok2 && [[NSFileManager defaultManager] fileExistsAtPath:m4aPath]) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [[NSFileManager defaultManager] removeItemAtPath:inputPath error:nil];
                            if (completion) completion(m4aPath, nil);
                        });
                        return;
                    }
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) completion(nil, [NSError errorWithDomain:@"theta" code:-5 userInfo:@{NSLocalizedDescriptionKey: @"MP3 conversion failed"}]);
                });
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSFileManager defaultManager] removeItemAtPath:inputPath error:nil];
                if (completion) completion(outputPath, nil);
            });
        }
    });
}

@end

