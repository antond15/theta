#import "Include/SettingsViewController.h"
#import "Include/ThetaDebug.h"
#import "Include/SubMenuViewController.h"
#import "Include/AudioNotesViewController.h"
#import "Include/CustomSwitchCell.h"
#import "Include/CustomToastView.h"
#import "Include/ThetaHelper.h"
#import <AudioToolbox/AudioToolbox.h>
#import "Include/InstagramHeaders.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import <zlib.h>
#import <AVFoundation/AVFoundation.h>

#import "Include/ThetaSettings.h"
#import "Include/ThetaSettingsRegistry.h"

@interface SettingSearchResult : NSObject
@property (nonatomic, strong) THSettingDefinition *setting;
@property (nonatomic, copy) NSString *settingKey;
@property (nonatomic, copy) NSString *settingTitle;
@property (nonatomic, copy) NSString *settingDetail;
@property (nonatomic, copy) NSString *parentSubMenuTitle;
@property (nonatomic, copy) NSString *settingType; // "switch" (default) or "color"
@property (nonatomic, strong, nullable) NSArray<NSString *> *segmentOptions; // for type == "segment"
@end

@interface LinkItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *linkDetail;
@property (nonatomic, copy) NSString *urlString;
@end

@implementation LinkItem
@end

@implementation SettingSearchResult
@end

@interface SettingsViewController () <UITableViewDelegate, UITableViewDataSource, UISearchResultsUpdating, UISearchBarDelegate, UIScrollViewDelegate, AVCaptureMetadataOutputObjectsDelegate>
@property (nonatomic, strong) NSArray<THSettingsPage *> *filteredSubMenus;
@property (nonatomic, strong) NSArray<SettingSearchResult *> *filteredSettings;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSArray<THSettingsPage *> *subMenus;
@property (nonatomic, strong) NSArray<LinkItem *> *linkItems;
@property (nonatomic, strong) UIImageView *bannerImageView;
@property (nonatomic, assign) BOOL isSearchingSettings;
@property (nonatomic, strong) UIImageView *chevronImageView;
@property (nonatomic, strong) AVCaptureSession *qrSession;
@property (nonatomic, strong) UIViewController *qrScanVC;
@property (nonatomic, strong) NSString *instagramVersion;
@property (nonatomic, strong) NSString *thetaVersion;
@end

// Image generation moved to ThetaHelper

// Top view controller utility moved to ThetaHelper

// Haptic feedback moved to ThetaHelper

// Toast functionality moved to ThetaHelper

// Toast functionality moved to ThetaHelper

/* Cell layout used for a setting in search results. */
static NSString *THSearchCellKind(THSettingDefinition *setting) {
    switch (setting.type) {
        case THSettingTypeToggle: return @"switch";
        case THSettingTypeChoice: return @"segment";
        case THSettingTypeColor: return @"color";
        case THSettingTypeAction: return @"action";
        case THSettingTypeList:
        case THSettingTypePage: return @"view";
    }
    return @"switch";
}

@implementation SettingsViewController
- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"THETA";

    self.tableView.delegate = self;

    // Pages and their settings are defined in ThetaSettingsRegistry.m.
    self.subMenus = [THSettingsPage allPages];
    self.filteredSubMenus = self.subMenus;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;

    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;

    CGFloat spacerHeight = 10.0;
    UIView *spacer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, spacerHeight)];
    spacer.backgroundColor = [UIColor clearColor];

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search Theta Settings";
    self.searchController.searchBar.delegate = self;
    self.searchController.searchBar.tintColor = [ThetaHelper iotaPinkColor];
    self.navigationItem.searchController = self.searchController;
    self.definesPresentationContext = YES;

    self.tableView.tableHeaderView = spacer;

    UIImage *backImage = [UIImage systemImageNamed:@"chevron.down"];
    backImage = [backImage imageWithTintColor:[ThetaHelper iotaPinkColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:backImage
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(dismissViewController)];

    UIImage *applyImage = [UIImage systemImageNamed:@"gearshape"];
    applyImage = [applyImage imageWithTintColor:[ThetaHelper iotaPinkColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
    // Plain matches the folder/chevron buttons. Done becomes a filled tinted chip on
    // iOS 26+ (Liquid Glass), which makes a pink gear invisible on a pink circle.
    UIBarButtonItem *applyButton = [[UIBarButtonItem alloc] initWithImage:applyImage
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self
                                                                   action:nil];

    UIImage *audioNotesImage = [UIImage systemImageNamed:@"folder"];
    audioNotesImage = [audioNotesImage imageWithTintColor:[ThetaHelper iotaPinkColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIBarButtonItem *audioNotesButton = [[UIBarButtonItem alloc] initWithImage:audioNotesImage
                                                                         style:UIBarButtonItemStylePlain
                                                                        target:self
                                                                        action:@selector(openAudioNotes)];

    UIAction *applyAction = [UIAction actionWithTitle:@"Confirm"
                                                image:[UIImage systemImageNamed:@"checkmark"]
                                        identifier:nil
                                            handler:^(UIAction *action) {
        [self applySettings];
    }];

    UIAction *cancelAction = [UIAction actionWithTitle:@"Cancel"
                                                image:[UIImage systemImageNamed:@"xmark"]
                                        identifier:nil
                                            handler:^(UIAction *action) {
                                            
                                        }];

    UIMenu *applyMenu = [UIMenu menuWithTitle:@"Apply Settings" children:@[applyAction, cancelAction]];

    UIAction *resetAction = [UIAction actionWithTitle:@"Confirm"
                                                image:[UIImage systemImageNamed:@"arrow.clockwise"]
                                        identifier:nil
                                            handler:^(UIAction *action) {
        [self resetSettings];
    }];
    UIAction *cancelAction2 = [UIAction actionWithTitle:@"Cancel"
                                                image:[UIImage systemImageNamed:@"xmark"]
                                        identifier:nil
                                            handler:^(UIAction *action) {
                                            
                                        }];
    resetAction.attributes = UIMenuElementAttributesDestructive;
    UIMenu *resetMenu = [UIMenu menuWithTitle:@"Reset Settings" children:@[resetAction, cancelAction2]];

    UIAction *exportSettingsActionQR = [UIAction actionWithTitle:@"Export QR Code"
                                                image:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                        identifier:nil
                                            handler:^(UIAction *action) {
        [self exportSettingsQR];
    }];

    // Rename existing to clarify behavior
    UIAction *exportSettingsAction = [UIAction actionWithTitle:@"Show QR Code"
                                                image:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                        identifier:nil
                                            handler:^(UIAction *action) {
        [self exportSettings];
    }];

    // New: actually copy JSON to clipboard
    UIAction *exportSettingsClipboardJSON = [UIAction actionWithTitle:@"Export to Clipboard"
                                                image:[UIImage systemImageNamed:@"doc.on.doc"]
                                        identifier:nil
                                            handler:^(UIAction *action) {
        [self exportSettingsToClipboard];
    }];

    UIMenu *exportMenu = [UIMenu menuWithTitle:@"Export Settings" children:@[exportSettingsActionQR, exportSettingsAction, exportSettingsClipboardJSON]];

    UIAction *importSettingsActionScan = [UIAction actionWithTitle:@"Scan QR Code"
                                                image:[UIImage systemImageNamed:@"qrcode.viewfinder"]
                                        identifier:nil
                                            handler:^(UIAction *action) {
        [self importSettingsQRScan];
    }];

    UIAction *importSettingsAction = [UIAction actionWithTitle:@"Import QR Code"
                                                image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                        identifier:nil
                                            handler:^(UIAction *action) {
        [self importSettingsQR];
    }];

    UIAction *importSettingsAction2 = [UIAction actionWithTitle:@"Import from Clipboard"
                                                image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                        identifier:nil
                                            handler:^(UIAction *action) {
        [self importSettings];
    }];

    UIMenu *importMenu = [UIMenu menuWithTitle:@"Import Settings" children:@[importSettingsAction, importSettingsActionScan, importSettingsAction2]];

    UIMenu *importExportMenu = [UIMenu menuWithTitle:@"Import/Export Settings" children:@[importMenu, exportMenu]];

    UIMenu *mainMenu = [UIMenu menuWithTitle:@"" children:@[applyMenu, importExportMenu, resetMenu]];
    [applyButton setMenu:mainMenu];
    if (@available(iOS 14.0, *)) {
        SEL sel = NSSelectorFromString(@"setShowsMenuAsPrimaryAction:");
        if ([applyButton respondsToSelector:sel]) {
            ((void (*)(id, SEL, BOOL))[applyButton methodForSelector:sel])(applyButton, sel, YES);
        }
    }

    // Conditionally add audioNotesButton only if "Save Audio Notes" is enabled
    NSMutableArray *rightBarButtonItems = [NSMutableArray arrayWithObject:applyButton];
    [rightBarButtonItems addObject:audioNotesButton];
    self.navigationItem.rightBarButtonItems = rightBarButtonItems;

    self.navigationController.navigationBar.tintColor = [ThetaHelper iotaPinkColor];

    LinkItem *twitter = [LinkItem new];
    twitter.title = @"Follow @objcmsgsend on X";
    twitter.linkDetail = @"Stay updated with the latest news and updates.";
    twitter.urlString = @"https://twitter.com/objcmsgsend";

    LinkItem *discord = [LinkItem new];
    discord.title = @"Join the Discord Server";
    discord.linkDetail = @"Join the community for support and discussions.";
    discord.urlString = @"https://discord.gg/8b36UrNPEw";

    self.linkItems = @[twitter, discord];

    [self setupAnimatedTitle];
    [self setupVersionStrings];
}

- (void)setupAnimatedTitle {
    @try {
        UIView *titleContainer = [[UIView alloc] init];
        titleContainer.translatesAutoresizingMaskIntoConstraints = NO;
        self.navigationItem.titleView = titleContainer;
        
        NSString *titleText = @"THETA";
        UIFont *nativeFont = [UIFont fontWithName:@"HelveticaNeue-Bold" size:24.0];
        
        if (!nativeFont) {
            NSLog(@"[DEBUG] Error: 'AvenirNext-Bold' font not found. Falling back to system font.");
            nativeFont = [UIFont boldSystemFontOfSize:24.0];
        }
        
        UIStackView *stackView = [[UIStackView alloc] init];
        stackView.axis = UILayoutConstraintAxisHorizontal;
        stackView.alignment = UIStackViewAlignmentCenter;
        stackView.spacing = 5.0;
        stackView.translatesAutoresizingMaskIntoConstraints = NO;
        
        [titleContainer addSubview:stackView];
        
        NSMutableArray<UILabel *> *letterLabels = [NSMutableArray array];
        for (NSUInteger i = 0; i < titleText.length; i++) {
            NSString *letter = [titleText substringWithRange:NSMakeRange(i, 1)];
            
            UILabel *letterLabel = [[UILabel alloc] init];
            letterLabel.text = letter;
            letterLabel.font = nativeFont;
            	letterLabel.textColor = [ThetaHelper iotaPinkColor];
            letterLabel.alpha = 0.0;
            letterLabel.translatesAutoresizingMaskIntoConstraints = NO;
            
            [stackView addArrangedSubview:letterLabel];
            [letterLabels addObject:letterLabel];
        }
        
        [NSLayoutConstraint activateConstraints:@[
            [stackView.centerXAnchor constraintEqualToAnchor:titleContainer.centerXAnchor],
            [stackView.centerYAnchor constraintEqualToAnchor:titleContainer.centerYAnchor]
        ]];
        
        CGFloat delayIncrement = 0.08;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            for (NSUInteger i = 0; i < letterLabels.count; i++) {
                UILabel *label = letterLabels[i];
                
                [UIView animateWithDuration:0.5
                                      delay:i * delayIncrement
                                    options:UIViewAnimationOptionCurveEaseInOut
                                 animations:^{
                    label.alpha = 1.0;
                } completion:nil];
            }
        });
    } @catch (NSException *exception) {
        NSLog(@"Error: %@", exception);
    }
}

- (void)setupVersionStrings {
    // Get Instagram app version
    self.instagramVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (!self.instagramVersion) {
        self.instagramVersion = @"Unknown";
    }
    
    // Get Theta build version (THETA_VERSION_NUMBER in the Makefile)
    #ifdef THETA_VERSION
        self.thetaVersion = @THETA_VERSION;
    #else
        self.thetaVersion = @"Unknown";
    #endif
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *searchText = searchController.searchBar.text;
    if (searchText.length == 0) {
        self.isSearchingSettings = NO;
        self.filteredSubMenus = self.subMenus;
        [self.tableView reloadData];
        return;
    }

    NSMutableArray<SettingSearchResult *> *allSettings = [NSMutableArray array];
    for (THSettingsPage *subMenu in self.subMenus) {
        for (THSettingDefinition *setting in subMenu.settings) {
            SettingSearchResult *result = [SettingSearchResult new];
            result.setting = setting;
            result.settingKey = setting.key;
            result.settingTitle = setting.title;
            result.settingDetail = setting.detail;
            result.parentSubMenuTitle = subMenu.title;
            result.settingType = THSearchCellKind(setting);
            result.segmentOptions = setting.optionTitles;
            [allSettings addObject:result];
        }
    }

    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(SettingSearchResult *result, NSDictionary *bindings) {
        return [result.settingTitle localizedCaseInsensitiveContainsString:searchText] ||
               [result.settingDetail localizedCaseInsensitiveContainsString:searchText] ||
               [result.parentSubMenuTitle localizedCaseInsensitiveContainsString:searchText];
    }];
    self.filteredSettings = [allSettings filteredArrayUsingPredicate:predicate];
    self.isSearchingSettings = YES;
    [self.tableView reloadData];
}

- (void)dismissViewController {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showAudioNotesMenu {
    // Deprecated menu flow; replaced by direct open
}

- (void)openAudioNotes {
    AudioNotesViewController *vc = [[AudioNotesViewController alloc] initWithMode:AudioNotesContentModeSavedMedia];
    [self.navigationController pushViewController:vc animated:YES];
}



- (void)applySettings {
    [[NSUserDefaults standardUserDefaults] synchronize];

    dispatch_async(dispatch_get_main_queue(), ^{
        [ThetaHelper showToastWithTitle:@"Settings Applied!" subtitle:@"App will need to be restarted." icon:[ThetaHelper imageFromEmojiString:@"✅" width:300] autoHide:3 openURL:nil];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] performSelector:@selector(suspend)];
            exit(0);
        });
    });
}

- (void)resetSettings {
    [THSettingsTransfer resetAll];
    [[NSUserDefaults standardUserDefaults] synchronize];

    dispatch_async(dispatch_get_main_queue(), ^{
        UILocalNotification *localNotification = [[UILocalNotification alloc] init];
        localNotification.fireDate = [NSDate dateWithTimeIntervalSinceNow:0.5];
        localNotification.alertTitle = @"Settings Reset!";
        localNotification.alertBody = @"Restart the app to see the changes.";
        localNotification.soundName = UILocalNotificationDefaultSoundName;
        [[UIApplication sharedApplication] scheduleLocalNotification:localNotification];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] performSelector:@selector(suspend)];
            exit(0);
        });
    });
}

NSData *compressData(NSData *uncompressedData) {
	if (!uncompressedData || [uncompressedData length] == 0) return nil;

	z_stream strm;
	strm.zalloc = Z_NULL;
	strm.zfree = Z_NULL;
	strm.opaque = Z_NULL;
	strm.total_out = 0;
	strm.next_in = (Bytef *)[uncompressedData bytes];
	strm.avail_in = (uInt)[uncompressedData length];

	// Compress level can be Z_DEFAULT_COMPRESSION, or between 0 and 9: 1 gives best speed, 9 gives best compression, 0 gives no compression.
	if (deflateInit(&strm, 1) != Z_OK) return nil;

	NSMutableData *compressed = [NSMutableData dataWithLength:16384];

	do {
		if (strm.total_out >= [compressed length])
			[compressed increaseLengthBy: 16384];
		
		strm.next_out = [compressed mutableBytes] + strm.total_out;
		strm.avail_out = (uInt)([compressed length] - strm.total_out);

		deflate(&strm, Z_FINISH);
		
	} while (strm.avail_out == 0);

	deflateEnd(&strm);

	[compressed setLength: strm.total_out];
	return compressed;
}

- (NSData *)decompressData:(NSData *)compressedData {
    if (!compressedData || [compressedData length] == 0) return nil;
    z_stream strm;
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    strm.opaque = Z_NULL;
    strm.avail_in = (uInt)[compressedData length];
    strm.next_in = (Bytef *)[compressedData bytes];

    if (inflateInit(&strm) != Z_OK) return nil;

    NSMutableData *decompressed = [NSMutableData dataWithLength:[compressedData length] * 4];
    int status;
    do {
        if (strm.total_out >= [decompressed length])
            [decompressed increaseLengthBy:[compressedData length] / 2];
        strm.next_out = [decompressed mutableBytes] + strm.total_out;
        strm.avail_out = (uInt)([decompressed length] - strm.total_out);
        status = inflate(&strm, Z_SYNC_FLUSH);
        if (status == Z_STREAM_ERROR || status == Z_DATA_ERROR || status == Z_MEM_ERROR) {
            inflateEnd(&strm);
            return nil;
        }
    } while (status != Z_STREAM_END);
    inflateEnd(&strm);
    [decompressed setLength:strm.total_out];
    return decompressed;
}

- (void)exportSettingsQR {
    NSDictionary *exportedSettings = [THSettingsTransfer exportDictionary];

    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:exportedSettings options:NSJSONWritingPrettyPrinted error:&error];
    if (!jsonData) {
        NSLog(@"Error exporting settings: %@", error);
        return;
    }

    NSData *compressedData = compressData(jsonData);
    NSString *base64EncodedString = [compressedData base64EncodedStringWithOptions:0];

    if (base64EncodedString.length > 0) {
        @try {
            NSData *qrData = [base64EncodedString dataUsingEncoding:NSUTF8StringEncoding];
            CIFilter *qrFilter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
            [qrFilter setValue:qrData forKey:@"inputMessage"];
            CIImage *qrImage = qrFilter.outputImage;

            if (!qrImage) {
                NSLog(@"Error: qrImage is nil");
                [ThetaHelper showToastWithTitle:@"QR Error" subtitle:@"Failed to generate QR code image." icon:[ThetaHelper imageFromEmojiString:@"❌" width:200] autoHide:2 openURL:nil];
                return;
            }

            CGAffineTransform transform = CGAffineTransformMakeScale(10.0, 10.0);
            CIImage *scaledQRImage = [qrImage imageByApplyingTransform:transform];

            if (!scaledQRImage) {
                NSLog(@"Error: scaledQRImage is nil");
                [ThetaHelper showToastWithTitle:@"QR Error" subtitle:@"Failed to scale QR code image." icon:[ThetaHelper imageFromEmojiString:@"❌" width:200] autoHide:2 openURL:nil];
                return;
            }

            CIContext *context = [CIContext contextWithOptions:nil];
            CGImageRef cgImage = [context createCGImage:scaledQRImage fromRect:scaledQRImage.extent];
            if (!cgImage) {
                NSLog(@"Error: cgImage is nil");
                [ThetaHelper showToastWithTitle:@"QR Error" subtitle:@"Failed to create CGImage from QR code." icon:[ThetaHelper imageFromEmojiString:@"❌" width:200] autoHide:2 openURL:nil];
                return;
            }
            UIImage *qrUIImage = [UIImage imageWithCGImage:cgImage];
            CGImageRelease(cgImage);

            if (!qrUIImage) {
                NSLog(@"Error: qrUIImage is nil");
                [ThetaHelper showToastWithTitle:@"QR Error" subtitle:@"Failed to create UIImage from QR code." icon:[ThetaHelper imageFromEmojiString:@"❌" width:200] autoHide:2 openURL:nil];
                return;
            }

            UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[qrUIImage] applicationActivities:nil];
            [[ThetaHelper topViewController] presentViewController:activityViewController animated:YES completion:nil];
        } @catch (NSException *exception) {
            NSLog(@"Error generating QR code: %@", exception);
        }
    } else {
        NSLog(@"Base64 encoded string is empty, cannot generate QR code");
    }
}

- (void)importSettingsQRScan {
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (!input) {
        [ThetaHelper showToastWithTitle:@"Camera Error" subtitle:@"Unable to access camera." icon:[ThetaHelper imageFromEmojiString:@"❌" width:200] autoHide:2 openURL:nil];
        return;
    }
    [session addInput:input];

    AVCaptureMetadataOutput *output = [[AVCaptureMetadataOutput alloc] init];
    [session addOutput:output];

    UIViewController *scanVC = [[UIViewController alloc] init];
    AVCaptureVideoPreviewLayer *previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:session];
    previewLayer.frame = [UIScreen mainScreen].bounds;
    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [scanVC.view.layer addSublayer:previewLayer];

    [output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
    output.metadataObjectTypes = @[AVMetadataObjectTypeQRCode];

    // Store references for delegate
    self.qrSession = session;
    self.qrScanVC = scanVC;

    [self presentViewController:scanVC animated:YES completion:^{
        [session startRunning];
    }];
}

- (void)exportSettings {
    @try {
        NSDictionary *exportedSettings = [THSettingsTransfer exportDictionary];
        
        // Convert to JSON
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:exportedSettings options:NSJSONWritingPrettyPrinted error:&error];
        if (error) {
            NSLog(@"Error exporting settings: %@", error);
            if (ENABLED(THAppShowBanners)) {
                [ThetaHelper showToastWithTitle:@"Export Failed" subtitle:@"Failed to export settings." icon:[UIImage systemImageNamed:@"exclamationmark.triangle"] autoHide:3 openURL:nil];
            }
            return;
        }
        
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        if (!jsonString) {
            NSLog(@"Failed to create JSON string");
            if (ENABLED(THAppShowBanners)) {
                [ThetaHelper showToastWithTitle:@"Export Failed" subtitle:@"Failed to create settings data." icon:[UIImage systemImageNamed:@"exclamationmark.triangle"] autoHide:3 openURL:nil];
            }
            return;
        }
        
        // Compress data
        NSData *data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
        if (!data) {
            NSLog(@"Failed to convert JSON string to data");
            if (ENABLED(THAppShowBanners)) {
                [ThetaHelper showToastWithTitle:@"Export Failed" subtitle:@"Failed to process settings data." icon:[UIImage systemImageNamed:@"exclamationmark.triangle"] autoHide:3 openURL:nil];
            }
            return;
        }
        
        uLong compressedLength = compressBound((uLong)data.length);
        NSMutableData *compressedData = [NSMutableData dataWithLength:compressedLength];
        
        int result = compress(compressedData.mutableBytes, &compressedLength, data.bytes, (uLong)data.length);
        if (result != Z_OK) {
            NSLog(@"Compression failed with error: %d", result);
            if (ENABLED(THAppShowBanners)) {
                [ThetaHelper showToastWithTitle:@"Export Failed" subtitle:@"Failed to compress settings data." icon:[UIImage systemImageNamed:@"exclamationmark.triangle"] autoHide:3 openURL:nil];
            }
            return;
        }
        
        [compressedData setLength:compressedLength];
        
        // Base64 encode
        NSString *base64String = [compressedData base64EncodedStringWithOptions:0];
        if (!base64String) {
            NSLog(@"Failed to base64 encode compressed data");
            if (ENABLED(THAppShowBanners)) {
                [ThetaHelper showToastWithTitle:@"Export Failed" subtitle:@"Failed to encode settings data." icon:[UIImage systemImageNamed:@"exclamationmark.triangle"] autoHide:3 openURL:nil];
            }
            return;
        }
        
        // Create QR code
        CIFilter *qrFilter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
        if (!qrFilter) {
            NSLog(@"QR filter not available");
            if (ENABLED(THAppShowBanners)) {
                [ThetaHelper showToastWithTitle:@"Export Failed" subtitle:@"QR code generation not available." icon:[UIImage systemImageNamed:@"exclamationmark.triangle"] autoHide:3 openURL:nil];
            }
            return;
        }
        
        NSData *qrData = [base64String dataUsingEncoding:NSUTF8StringEncoding];
        if (!qrData) {
            NSLog(@"Error: qrData is nil");
            if (ENABLED(THAppShowBanners)) {
                [ThetaHelper showToastWithTitle:@"Export Failed" subtitle:@"Failed to process QR data." icon:[UIImage systemImageNamed:@"exclamationmark.triangle"] autoHide:3 openURL:nil];
            }
            return;
        }
        
        [qrFilter setValue:qrData forKey:@"inputMessage"];
        
        CIImage *qrImage = qrFilter.outputImage;
        if (!qrImage) {
            NSLog(@"Error: qrImage is nil");
            if (ENABLED(THAppShowBanners)) {
                [ThetaHelper showToastWithTitle:@"Export Failed" subtitle:@"Failed to generate QR image." icon:[UIImage systemImageNamed:@"exclamationmark.triangle"] autoHide:3 openURL:nil];
            }
            return;
        }
        
        // Scale QR code
        CGAffineTransform transform = CGAffineTransformMakeScale(10, 10);
        CIImage *scaledQRImage = [qrImage imageByApplyingTransform:transform];
        if (!scaledQRImage) {
            NSLog(@"Error: scaledQRImage is nil");
            if (ENABLED(THAppShowBanners)) {
                [ThetaHelper showToastWithTitle:@"Export Failed" subtitle:@"Failed to scale QR image." icon:[UIImage systemImageNamed:@"exclamationmark.triangle"] autoHide:3 openURL:nil];
            }
            return;
        }
        
        CIContext *context = [CIContext contextWithOptions:nil];
        CGImageRef cgImage = [context createCGImage:scaledQRImage fromRect:scaledQRImage.extent];
        if (!cgImage) {
            NSLog(@"Error: cgImage is nil");
            if (ENABLED(THAppShowBanners)) {
                [ThetaHelper showToastWithTitle:@"Export Failed" subtitle:@"Failed to create CG image." icon:[UIImage systemImageNamed:@"exclamationmark.triangle"] autoHide:3 openURL:nil];
            }
            return;
        }
        
        UIImage *qrUIImage = [UIImage imageWithCGImage:cgImage];
        CGImageRelease(cgImage);
        
        if (!qrUIImage) {
            NSLog(@"Error: qrUIImage is nil");
            if (ENABLED(THAppShowBanners)) {
                [ThetaHelper showToastWithTitle:@"Export Failed" subtitle:@"Failed to create UIImage." icon:[UIImage systemImageNamed:@"exclamationmark.triangle"] autoHide:3 openURL:nil];
            }
            return;
        }
        
        // Present QR code
        UIViewController *qrVC = [[UIViewController alloc] init];
        qrVC.view.backgroundColor = [UIColor whiteColor];
        
        UIImageView *qrImageView = [[UIImageView alloc] initWithImage:qrUIImage];
        qrImageView.contentMode = UIViewContentModeScaleAspectFit;
        qrImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [qrVC.view addSubview:qrImageView];
        
        [NSLayoutConstraint activateConstraints:@[
            [qrImageView.centerXAnchor constraintEqualToAnchor:qrVC.view.centerXAnchor],
            [qrImageView.centerYAnchor constraintEqualToAnchor:qrVC.view.centerYAnchor],
            [qrImageView.widthAnchor constraintEqualToConstant:250],
            [qrImageView.heightAnchor constraintEqualToConstant:250]
        ]];
        
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:qrVC];
        navController.modalPresentationStyle = UIModalPresentationPageSheet;
        [self presentViewController:navController animated:YES completion:nil];
        
        if (ENABLED(THAppShowBanners)) {
            [ThetaHelper showToastWithTitle:@"Settings Exported!" subtitle:@"Scan the QR code to import settings." icon:[UIImage systemImageNamed:@"checkmark.circle.fill"] autoHide:4 openURL:nil];
        }
        
    } @catch (NSException *exception) {
        NSLog(@"Error generating QR code: %@", exception);
        if (ENABLED(THAppShowBanners)) {
            [ThetaHelper showToastWithTitle:@"Export Failed" subtitle:@"An error occurred while exporting settings." icon:[UIImage systemImageNamed:@"exclamationmark.triangle"] autoHide:3 openURL:nil];
        }
    }
}

- (void)exportSettingsToClipboard {
    @try {
        NSDictionary *exportedSettings = [THSettingsTransfer exportDictionary];

        NSError *error = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:exportedSettings options:NSJSONWritingPrettyPrinted error:&error];
        if (!jsonData) {
            if (ENABLED(THAppShowBanners)) {
                [ThetaHelper showToastWithTitle:@"Export Failed" subtitle:@"Failed to build settings JSON." icon:[UIImage systemImageNamed:@"exclamationmark.triangle"] autoHide:3 openURL:nil];
            }
            return;
        }
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        if (!jsonString) {
            if (ENABLED(THAppShowBanners)) {
                [ThetaHelper showToastWithTitle:@"Export Failed" subtitle:@"Failed to encode JSON string." icon:[UIImage systemImageNamed:@"exclamationmark.triangle"] autoHide:3 openURL:nil];
            }
            return;
        }
        [UIPasteboard generalPasteboard].string = jsonString;
        if (ENABLED(THAppShowBanners)) {
            [ThetaHelper showToastWithTitle:@"Exported" subtitle:@"Settings JSON copied to clipboard." icon:[UIImage systemImageNamed:@"doc.on.doc.fill"] autoHide:3 openURL:nil];
        }
    } @catch (__unused NSException *e) {
        if (ENABLED(THAppShowBanners)) {
            [ThetaHelper showToastWithTitle:@"Export Failed" subtitle:@"Unexpected error." icon:[UIImage systemImageNamed:@"exclamationmark.triangle"] autoHide:3 openURL:nil];
        }
    }
}

- (void)importSettingsQR {
    // Present image picker for QR code selection
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = (id<UINavigationControllerDelegate, UIImagePickerControllerDelegate>)self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)importSettings {
    NSString *encryptedString = [[UIPasteboard generalPasteboard] string];
    THDebugLog(@"Encrypted string: %@", encryptedString);

    if (!encryptedString || encryptedString.length == 0) {
        [ThetaHelper showToastWithTitle:@"Import Error" subtitle:@"No settings string provided." icon:[ThetaHelper imageFromEmojiString:@"❌" width:200] autoHide:2 openURL:nil];
        return;
    }

    // "Export to Clipboard" copies plain JSON; QR codes hold base64 of zlib-compressed JSON.
    NSString *trimmed = [encryptedString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSData *decompressedData = nil;
    if ([trimmed hasPrefix:@"{"]) {
        decompressedData = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
    } else {
        NSData *data = [[NSData alloc] initWithBase64EncodedString:trimmed options:0];
        if (!data) {
            [ThetaHelper showToastWithTitle:@"Import Error" subtitle:@"Invalid base64 string." icon:[ThetaHelper imageFromEmojiString:@"❌" width:200] autoHide:2 openURL:nil];
            return;
        }
        decompressedData = [self decompressData:data];
    }
    THDebugLog(@"Decompressed data: %@", decompressedData);
    if (!decompressedData) {
        [ThetaHelper showToastWithTitle:@"Import Error" subtitle:@"Decompression failed." icon:[ThetaHelper imageFromEmojiString:@"❌" width:200] autoHide:2 openURL:nil];
        return;
    }

    NSError *error = nil;
    NSDictionary *importedSettings = [NSJSONSerialization JSONObjectWithData:decompressedData options:0 error:&error];
    if (!importedSettings || error) {
        [ThetaHelper showToastWithTitle:@"Import Error" subtitle:@"Invalid JSON." icon:[ThetaHelper imageFromEmojiString:@"❌" width:200] autoHide:2 openURL:nil];
        return;
    }

    [THSettingsTransfer importDictionary:importedSettings];

    [[NSUserDefaults standardUserDefaults] synchronize];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UILocalNotification *localNotification = [[UILocalNotification alloc] init];
        localNotification.fireDate = [NSDate dateWithTimeIntervalSinceNow:0.5];
        localNotification.alertTitle = @"Settings Imported!";
        localNotification.alertBody = @"Launching the app will have the new settings.";
        localNotification.soundName = UILocalNotificationDefaultSoundName;
        [[UIApplication sharedApplication] scheduleLocalNotification:localNotification];

        [[UIApplication sharedApplication] performSelector:@selector(suspend)];
        exit(0);
    });
}

#pragma mark - AVCaptureMetadataOutputObjectsDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)metadataObjects
       fromConnection:(AVCaptureConnection *)connection
{
    if (metadataObjects.count == 0) return;
    AVMetadataMachineReadableCodeObject *obj = metadataObjects.firstObject;
    if (![obj.type isEqualToString:AVMetadataObjectTypeQRCode]) return;
    NSString *qrString = obj.stringValue;
    if (!qrString) return;

    // Stop scanning and dismiss camera
    [self.qrSession stopRunning];
    [self.qrScanVC dismissViewControllerAnimated:YES completion:^{
        NSData *data = [[NSData alloc] initWithBase64EncodedString:qrString options:0];
        if (!data) {
            [ThetaHelper showToastWithTitle:@"Import Error" subtitle:@"Invalid base64 string." icon:[ThetaHelper imageFromEmojiString:@"❌" width:200] autoHide:2 openURL:nil];
            return;
        }
        NSData *decompressedData = [self decompressData:data];
        if (!decompressedData) {
            [ThetaHelper showToastWithTitle:@"Import Error" subtitle:@"Decompression failed." icon:[ThetaHelper imageFromEmojiString:@"❌" width:200] autoHide:2 openURL:nil];
            return;
        }
        NSError *error = nil;
        NSDictionary *importedSettings = [NSJSONSerialization JSONObjectWithData:decompressedData options:0 error:&error];
        if (!importedSettings || error) {
            [ThetaHelper showToastWithTitle:@"Import Error" subtitle:@"Invalid JSON." icon:[ThetaHelper imageFromEmojiString:@"❌" width:200] autoHide:2 openURL:nil];
            return;
        }
        [THSettingsTransfer importDictionary:importedSettings];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [ThetaHelper showToastWithTitle:@"Settings Imported!" subtitle:@"App will need to be restarted." icon:[ThetaHelper imageFromEmojiString:@"✅" width:300] autoHide:2 openURL:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] performSelector:@selector(suspend)];
            exit(0);
        });
    }];
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    UIImage *selectedImage = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{
        if (!selectedImage) {
            [ThetaHelper showToastWithTitle:@"Import Error" subtitle:@"No image selected." icon:[ThetaHelper imageFromEmojiString:@"❌" width:200] autoHide:2 openURL:nil];
            return;
        }
        // Detect QR code from image
        CIImage *ciImage = [[CIImage alloc] initWithImage:selectedImage];
        CIDetector *detector = [CIDetector detectorOfType:CIDetectorTypeQRCode context:nil options:@{CIDetectorAccuracy:CIDetectorAccuracyHigh}];
        NSArray *features = [detector featuresInImage:ciImage];
        if (features.count == 0) {
            [ThetaHelper showToastWithTitle:@"Import Error" subtitle:@"No QR code found." icon:[ThetaHelper imageFromEmojiString:@"❌" width:200] autoHide:2 openURL:nil];
            return;
        }
        CIQRCodeFeature *qrFeature = features.firstObject;
        NSString *qrString = qrFeature.messageString;
        if (!qrString) {
            [ThetaHelper showToastWithTitle:@"Import Error" subtitle:@"QR code unreadable." icon:[ThetaHelper imageFromEmojiString:@"❌" width:200] autoHide:2 openURL:nil];
            return;
        }
        // Decode base64 and decompress
        NSData *compressedData = [[NSData alloc] initWithBase64EncodedString:qrString options:0];
        if (!compressedData) {
            [ThetaHelper showToastWithTitle:@"Import Error" subtitle:@"Base64 decode failed." icon:[ThetaHelper imageFromEmojiString:@"❌" width:200] autoHide:2 openURL:nil];
            return;
        }
        // Decompress
        NSData *jsonData = [self decompressData:compressedData];
        if (!jsonData) {
            [ThetaHelper showToastWithTitle:@"Import Error" subtitle:@"Decompression failed." icon:[ThetaHelper imageFromEmojiString:@"❌" width:200] autoHide:2 openURL:nil];
            return;
        }
        NSError *error = nil;
        NSDictionary *importedSettings = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
        if (!importedSettings || error) {
            [ThetaHelper showToastWithTitle:@"Import Error" subtitle:@"JSON decode failed." icon:[ThetaHelper imageFromEmojiString:@"❌" width:200] autoHide:2 openURL:nil];
            return;
        }
        [THSettingsTransfer importDictionary:importedSettings];
        [[NSUserDefaults standardUserDefaults] synchronize];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            UILocalNotification *localNotification = [[UILocalNotification alloc] init];
            localNotification.fireDate = [NSDate dateWithTimeIntervalSinceNow:0.5];
            localNotification.alertTitle = @"Settings Imported!";
            localNotification.alertBody = @"Launching the app will have the new settings.";
            localNotification.soundName = UILocalNotificationDefaultSoundName;
            [[UIApplication sharedApplication] scheduleLocalNotification:localNotification];

            [[UIApplication sharedApplication] performSelector:@selector(suspend)];
            exit(0);
        });
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.isSearchingSettings) {
        return 1;
    }
    return 2; // SubMenus + Links
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.isSearchingSettings) {
        return self.filteredSettings.count;
    }
    if (section == 0) {
        return self.filteredSubMenus.count;
    } else if (section == 1) {
        return self.linkItems.count;
    }
    return 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (self.isSearchingSettings) {
		SettingSearchResult *result = self.filteredSettings[indexPath.row];
		NSString *settingType = result.settingType ?: @"switch";

		// Use section rect width for more accurate content width in InsetGrouped style
		CGFloat tableWidth = [tableView rectForSection:indexPath.section].size.width;
		if (tableWidth <= 0.0) tableWidth = tableView.bounds.size.width;
		CGFloat leftPadding = 20.0;
		CGFloat rightPadding = 12.0;
		CGFloat textToControlSpacing = 12.0;
		CGFloat minHeight = 54.0;
		CGFloat topPadding = 12.0;
		CGFloat interLabelSpacing = 2.0;
		CGFloat bottomPadding = 12.0;

		NSString *osVersion = [[UIDevice currentDevice] systemVersion];
		CGFloat ios19Extra = (osVersion.floatValue >= 19.0) ? 4.0 : 0.0;

		CGFloat reservedRight = 0.0;
		if ([settingType isEqualToString:@"color"]) {
			CGFloat colorWellSize = 30.0;
			reservedRight = rightPadding + colorWellSize + textToControlSpacing;
		} else if ([settingType isEqualToString:@"segment"]) {
			CGFloat segWidth = MIN(240.0, tableWidth * 0.45);
			reservedRight = rightPadding + segWidth + textToControlSpacing;
		} else if ([settingType isEqualToString:@"action"]) {
			CGFloat buttonSize = 30.0;
			reservedRight = rightPadding + buttonSize + textToControlSpacing;
		} else {
			// switch (default)
			BOOL hasInfo = NO;
			hasInfo = result.setting.info.length > 0;
			CGFloat switchWidth = 52.0;
			CGFloat infoSize = 28.0;
			CGFloat interControlSpacing = 8.0;
			reservedRight = rightPadding + switchWidth + ios19Extra + (hasInfo ? (interControlSpacing + infoSize) : 0.0) + textToControlSpacing;
		}

		CGFloat contentWidth = tableWidth - leftPadding - reservedRight;
		if (contentWidth < 60.0) contentWidth = 60.0;

		UIFont *titleFont = [UIFont systemFontOfSize:17.0];
		CGFloat subtitleSize = 13.0;
		if (@available(iOS 16.0, *)) { subtitleSize = 12.0; }
		UIFont *detailFont = [UIFont systemFontOfSize:subtitleSize];

		CGFloat titleHeight = ceilf([result.settingTitle boundingRectWithSize:CGSizeMake(contentWidth, CGFLOAT_MAX)
																	 options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
																  attributes:@{ NSFontAttributeName: titleFont }
																	 context:nil].size.height);

		NSString *detailText = [NSString stringWithFormat:@"%@ — %@", result.parentSubMenuTitle, result.settingDetail ?: @""];
		CGFloat detailHeight = ceilf([detailText boundingRectWithSize:CGSizeMake(contentWidth, CGFLOAT_MAX)
															  options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
														   attributes:@{ NSFontAttributeName: detailFont }
															  context:nil].size.height);

		CGFloat total = topPadding + titleHeight + interLabelSpacing + detailHeight + bottomPadding + 2.0; // small fudge for rounding
		return MAX(minHeight, total);
	} else {
		return 54.0;
	}
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
    }

    cell.accessoryView = nil;

    if (self.isSearchingSettings) {
        SettingSearchResult *result = self.filteredSettings[indexPath.row];
        NSString *settingType = result.settingType ?: @"switch";

        if ([settingType isEqualToString:@"color"]) {
            static NSString *colorCellIdentifier = @"SearchColorCell";
            UITableViewCell *colorCell = [tableView dequeueReusableCellWithIdentifier:colorCellIdentifier];
            if (!colorCell) {
                colorCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:colorCellIdentifier];
                colorCell.selectionStyle = UITableViewCellSelectionStyleNone;
            }
            colorCell.textLabel.text = result.settingTitle;
            CGFloat subtitleSize = 13.0;
            if (@available(iOS 16.0, *)) { subtitleSize = 12.0; }
            colorCell.detailTextLabel.font = [UIFont systemFontOfSize:subtitleSize];
            colorCell.detailTextLabel.text = [NSString stringWithFormat:@"%@ — %@", result.parentSubMenuTitle, result.settingDetail ?: @""];
            colorCell.imageView.image = nil;
            colorCell.textLabel.font = [UIFont systemFontOfSize:17];
            colorCell.textLabel.textColor = [UIColor labelColor];
            colorCell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            colorCell.textLabel.numberOfLines = 0;
            colorCell.detailTextLabel.numberOfLines = 0;
            colorCell.preservesSuperviewLayoutMargins = NO;
            colorCell.layoutMargins = UIEdgeInsetsMake(0, 20, 0, 0);
            colorCell.separatorInset = UIEdgeInsetsMake(0, 20, 0, 0);
            colorCell.contentView.preservesSuperviewLayoutMargins = NO;
            if (@available(iOS 11.0, *)) {
                colorCell.contentView.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(0, 20, 0, 0);
            }

            if (@available(iOS 14.0, *)) {
                UIColorWell *colorWell = [[UIColorWell alloc] init];
                colorWell.supportsAlpha = NO;
                colorWell.selectedColor = ThetaSettingColor(result.settingKey);
                colorWell.accessibilityIdentifier = result.settingKey;
                [colorWell addTarget:self action:@selector(searchColorWellChanged:) forControlEvents:UIControlEventValueChanged];
                // Ensure proper sizing when used as accessoryView
                CGFloat side = 30.0;
                colorWell.frame = CGRectMake(0, 0, side, side);
                [colorWell sizeToFit];
                colorCell.accessoryView = colorWell;
            }

            return colorCell;
        } else {
            if ([settingType isEqualToString:@"segment"]) {
                static NSString *segmentCellIdentifier = @"SearchSegmentCell";
                UITableViewCell *segmentCell = [tableView dequeueReusableCellWithIdentifier:segmentCellIdentifier];
                if (!segmentCell) {
                    segmentCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:segmentCellIdentifier];
                    segmentCell.selectionStyle = UITableViewCellSelectionStyleNone;
                }
                segmentCell.textLabel.text = result.settingTitle;
                CGFloat segSubtitleSize = 13.0;
                if (@available(iOS 16.0, *)) { segSubtitleSize = 12.0; }
                segmentCell.detailTextLabel.text = [NSString stringWithFormat:@"%@ — %@", result.parentSubMenuTitle, result.settingDetail ?: @""];
                segmentCell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
                segmentCell.detailTextLabel.font = [UIFont systemFontOfSize:segSubtitleSize];
                segmentCell.textLabel.numberOfLines = 0;
                segmentCell.detailTextLabel.numberOfLines = 0;
                segmentCell.preservesSuperviewLayoutMargins = NO;
                segmentCell.layoutMargins = UIEdgeInsetsMake(0, 20, 0, 0);

                NSArray<NSString *> *options = result.segmentOptions;
                UISegmentedControl *seg = nil;
                if ([segmentCell.accessoryView isKindOfClass:[UISegmentedControl class]]) {
                    seg = (UISegmentedControl *)segmentCell.accessoryView;
                    [seg removeAllSegments];
                } else {
                    seg = [[UISegmentedControl alloc] init];
                }
                [options enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    [seg insertSegmentWithTitle:obj atIndex:idx animated:NO];
                }];
                seg.selectedSegmentIndex = MAX(0, [result.setting indexOfOption:ThetaSettingChoice(result.settingKey)]);
                seg.tag = indexPath.row;
                seg.accessibilityIdentifier = result.settingKey;
                [seg removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
                [seg addTarget:self action:@selector(handleSegmentChange:) forControlEvents:UIControlEventValueChanged];
                [seg sizeToFit];
                seg.transform = CGAffineTransformMakeScale(0.8, 0.8);
                segmentCell.accessoryView = seg;
                return segmentCell;
            }
            if ([settingType isEqualToString:@"action"]) {
                static NSString *actionSearchCellIdentifier = @"ActionSearchCell";
                UITableViewCell *actionCell = [tableView dequeueReusableCellWithIdentifier:actionSearchCellIdentifier];
                if (!actionCell) {
                    actionCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:actionSearchCellIdentifier];
                    actionCell.selectionStyle = UITableViewCellSelectionStyleNone;
                }
                actionCell.textLabel.text = result.settingTitle;
                CGFloat actSubtitleSize = 13.0;
                if (@available(iOS 16.0, *)) { actSubtitleSize = 12.0; }
                actionCell.detailTextLabel.text = [NSString stringWithFormat:@"%@ — %@", result.parentSubMenuTitle, result.settingDetail ?: @""];
                actionCell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
                actionCell.detailTextLabel.font = [UIFont systemFontOfSize:actSubtitleSize];
                actionCell.textLabel.numberOfLines = 0;
                actionCell.detailTextLabel.numberOfLines = 0;
                actionCell.preservesSuperviewLayoutMargins = NO;
                actionCell.layoutMargins = UIEdgeInsetsMake(0, 20, 0, 0);

                UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
                NSString *iconName = @"arrow.clockwise";
                SEL actionSelector = @selector(resetButtonColorsFromSearch);
                NSString *accessibilityLabel = @"Reset Colors";
                
                if ([result.settingKey isEqualToString:THAppClearCache]) {
                    iconName = @"trash";
                    actionSelector = @selector(clearAppCacheFromSearch);
                    accessibilityLabel = @"Clear App Cache";
                }
                
                UIImage *baseIcon = [UIImage systemImageNamed:iconName];
                UIImage *icon = [baseIcon imageWithTintColor:[ThetaHelper iotaPinkColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
                [button setImage:icon forState:UIControlStateNormal];
                button.tintColor = [ThetaHelper iotaPinkColor];
                button.accessibilityLabel = accessibilityLabel;
                [button addTarget:self action:actionSelector forControlEvents:UIControlEventTouchUpInside];
                [button sizeToFit];
                actionCell.accessoryView = button;
                return actionCell;
            }
            static NSString *switchCellIdentifier = @"CustomSwitchCell";
            CustomSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:switchCellIdentifier];
            if (!cell) {
                cell = [[CustomSwitchCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:switchCellIdentifier];
            }

            cell.textLabel.text = result.settingTitle;
            CGFloat swSubtitleSize = 13.0;
            if (@available(iOS 16.0, *)) { swSubtitleSize = 12.0; }
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ — %@", result.parentSubMenuTitle, result.settingDetail ?: @""];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:swSubtitleSize];
            cell.imageView.image = nil;

            BOOL isOn = ENABLED(result.settingKey);
            if ([cell.settingSwitch respondsToSelector:@selector(setOn:animated:)]) {
                ((void(*)(id,SEL,BOOL,BOOL))[cell.settingSwitch methodForSelector:@selector(setOn:animated:)])(cell.settingSwitch, @selector(setOn:animated:), isOn, NO);
            }
            cell.settingSwitch.tag = indexPath.row;
            [cell.settingSwitch removeTarget:nil action:NULL forControlEvents:UIControlEventAllEvents];
            [cell.settingSwitch addTarget:self action:@selector(searchSwitchChanged:) forControlEvents:UIControlEventValueChanged];

            cell.textLabel.font = [UIFont systemFontOfSize:17];
            cell.textLabel.textColor = [UIColor labelColor];
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            cell.textLabel.numberOfLines = 0;
            cell.detailTextLabel.numberOfLines = 0;

            if (result.setting.info.length > 0) {
                cell.infoButton.hidden = NO;
                cell.infoButton.accessibilityIdentifier = result.settingKey;
                [cell.infoButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
                [cell.infoButton addTarget:self action:@selector(didTapInfoFromSearch:) forControlEvents:UIControlEventTouchUpInside];
            } else {
                cell.infoButton.hidden = YES;
            }

            if (!result.setting.availableOnThisVersion) {
                cell.settingSwitch.enabled = NO;
                cell.textLabel.textColor = [UIColor systemGrayColor];
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ — %@ (Requires Instagram %@ or later)", result.parentSubMenuTitle, result.settingDetail ?: @"", result.setting.minimumInstagramVersion];
                if (isOn) ThetaSettingReset(result.settingKey);
            } else {
                cell.settingSwitch.enabled = YES;
            }

            return cell;
        }
    } else {
        if (indexPath.section == 0) {
            // THSettingsPage cell
            static NSString *cellIdentifier = @"Cell";
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier];
            }
            cell.accessoryView = nil;
            THSettingsPage *subMenu = self.filteredSubMenus[indexPath.row];
            cell.textLabel.text = subMenu.title;
            cell.detailTextLabel.text = subMenu.detail;
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            if (subMenu.iconName) {
                UIImage *icon = [UIImage systemImageNamed:subMenu.iconName];
                cell.imageView.image = icon;
                cell.imageView.tintColor = [ThetaHelper iotaPinkColor];
            } else {
                cell.imageView.image = nil;
            }
            cell.textLabel.font = [UIFont systemFontOfSize:17];
            cell.textLabel.textColor = [UIColor labelColor];
            NSString *osVersion = [[UIDevice currentDevice] systemVersion];
            if (osVersion.floatValue >= 19.0) {
                cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
            } else {
                cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
            }
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            return cell;
        } else if (indexPath.section == 1) {
            // Link cell
            static NSString *linkCellIdentifier = @"LinkCell";
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:linkCellIdentifier];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:linkCellIdentifier];
            }
            LinkItem *link = self.linkItems[indexPath.row];
            cell.textLabel.text = link.title;
            cell.detailTextLabel.text = link.linkDetail;
            cell.textLabel.textColor = [ThetaHelper iotaPinkColor];
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            cell.imageView.image = [UIImage systemImageNamed:@"link"];
            cell.imageView.tintColor = [ThetaHelper iotaPinkColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
    }

    // iOS 16+ has larger default toggles; add trailing content inset for alignment
    if (@available(iOS 16.0, *)) {
        cell.separatorInset = UIEdgeInsetsMake(0, 20, 0, 20);
        cell.contentView.layoutMargins = UIEdgeInsetsMake(0, 20, 0, 20);
    }
    cell.textLabel.font = [UIFont systemFontOfSize:17];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];

    return cell;
}

- (void)didTapInfoFromSearch:(UIButton *)sender {
    THSettingDefinition *setting = [THSettingDefinition definitionForKey:sender.accessibilityIdentifier];
    if (!setting) return;
    [ThetaHelper showCustomAlertWithActions:setting.title description:setting.info ?: setting.detail ?: @"" actions:@[@{ @"title": @"OK", @"handler": ^(id s) {} }]];
}

- (void)searchSwitchChanged:(UISwitch *)sender {
    NSInteger row = sender.tag;
    if (row < 0 || row >= (NSInteger)self.filteredSettings.count) return;
    THSettingDefinition *setting = self.filteredSettings[row].setting;
    ThetaSettingSetEnabled(setting.key, sender.isOn);
    THShowRestartToastIfNeeded(setting);
}

- (void)handleSegmentChange:(UISegmentedControl *)sender {
    THSettingDefinition *setting = [THSettingDefinition definitionForKey:sender.accessibilityIdentifier];
    NSInteger index = sender.selectedSegmentIndex;
    if (setting && index >= 0 && index < (NSInteger)setting.options.count) {
        ThetaSettingSetChoice(setting.key, setting.options[index].identifier);
    }
}

- (void)searchColorWellChanged:(id)sender {
    if (@available(iOS 14.0, *)) {
        UIColorWell *colorWell = (UIColorWell *)sender;
        if (colorWell.accessibilityIdentifier.length && colorWell.selectedColor) {
            ThetaSettingSetColor(colorWell.accessibilityIdentifier, colorWell.selectedColor);
        }
    }
}

- (void)resetButtonColorsFromSearch {
    THResetColorSettings();
    [self.tableView reloadData];

    if (ENABLED(THAppShowBanners)) {
        [ThetaHelper showToastWithTitle:@"Colors Reset" subtitle:@"Button colors restored to default." icon:[UIImage systemImageNamed:@"checkmark.circle.fill"] autoHide:3 openURL:nil];
    }
}

- (void)clearAppCacheFromSearch {
    [ThetaHelper clearAppCache];
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (self.isSearchingSettings) {
        return nil; // No footer when searching
    }
    
    if (section == 1) { // LinkItems section
        UIView *footerView = [[UIView alloc] init];
        footerView.backgroundColor = [UIColor clearColor];
        
        UILabel *versionLabel = [[UILabel alloc] init];
        versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
        versionLabel.numberOfLines = 2;
        versionLabel.textAlignment = NSTextAlignmentCenter;
        versionLabel.font = [UIFont systemFontOfSize:12];
        
        // Set light grey color regardless of dark mode
        versionLabel.textColor = [UIColor colorWithRed:0.4 green:0.4 blue:0.4 alpha:1.0];
        
        NSString *versionText = [NSString stringWithFormat:@"Made with ❤️ by @objc_msgSend\nInstagram v%@ | Theta %@", 
                                self.instagramVersion, self.thetaVersion];
        versionLabel.text = versionText;
        
        [footerView addSubview:versionLabel];
        
        [NSLayoutConstraint activateConstraints:@[
            [versionLabel.centerXAnchor constraintEqualToAnchor:footerView.centerXAnchor],
            [versionLabel.centerYAnchor constraintEqualToAnchor:footerView.centerYAnchor],
            [versionLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:footerView.leadingAnchor constant:20],
            [versionLabel.trailingAnchor constraintLessThanOrEqualToAnchor:footerView.trailingAnchor constant:-20]
        ]];
        
        return footerView;
    }
    
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    if (self.isSearchingSettings) {
        return 0; // No footer when searching
    }
    
    if (section == 1) { // LinkItems section
        return 60; // Height for the version footer
    }
    
    return UITableViewAutomaticDimension;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (self.isSearchingSettings) {
        if (indexPath.row >= (NSInteger)self.filteredSettings.count) return;
        SettingSearchResult *result = self.filteredSettings[indexPath.row];
        UIViewController *vc = THViewControllerForSetting(result.setting);
        if (vc) [self.navigationController pushViewController:vc animated:YES];
        return;
    }

    if (indexPath.section == 0) {
        // THSettingsPage tap
        THSettingsPage *subMenu = self.filteredSubMenus[indexPath.row];
        SubMenuViewController *subMenuViewController = [[SubMenuViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        subMenuViewController.title = subMenu.title;
        subMenuViewController.settings = subMenu.settings;
        [self.navigationController pushViewController:subMenuViewController animated:YES];
    } else if (indexPath.section == 1) {
        // Link tap
        LinkItem *link = self.linkItems[indexPath.row];
        NSURL *url = [NSURL URLWithString:link.urlString];
        if (url) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    }
}

#pragma mark - Navbar Management

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadNavbarItems {
    // Reload the navbar items based on current "Save Audio Notes" setting
    UIImage *audioNotesImage = [UIImage systemImageNamed:@"folder"];
    audioNotesImage = [audioNotesImage imageWithTintColor:[ThetaHelper iotaPinkColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIBarButtonItem *audioNotesButton = [[UIBarButtonItem alloc] initWithImage:audioNotesImage
                                                                         style:UIBarButtonItemStylePlain
                                                                        target:self
                                                                        action:@selector(openAudioNotes)];
    
    UIImage *applyImage = [UIImage systemImageNamed:@"gearshape"];
    applyImage = [applyImage imageWithTintColor:[ThetaHelper iotaPinkColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
    // Plain matches the folder/chevron buttons. Done becomes a filled tinted chip on
    // iOS 26+ (Liquid Glass), which makes a pink gear invisible on a pink circle.
    UIBarButtonItem *applyButton = [[UIBarButtonItem alloc] initWithImage:applyImage
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self
                                                                   action:nil];
    
    // Recreate the apply menu
    UIAction *applyAction = [UIAction actionWithTitle:@"Confirm"
                                                image:[UIImage systemImageNamed:@"checkmark"]
                                        identifier:nil
                                            handler:^(UIAction *action) {
        [self applySettings];
    }];
    
    UIAction *cancelAction = [UIAction actionWithTitle:@"Cancel"
                                                image:[UIImage systemImageNamed:@"xmark"]
                                        identifier:nil
                                            handler:^(UIAction *action) {
                                            
                                        }];
    
    UIMenu *applyMenu = [UIMenu menuWithTitle:@"Apply Settings" children:@[applyAction, cancelAction]];
    
    UIAction *resetAction = [UIAction actionWithTitle:@"Confirm"
                                                image:[UIImage systemImageNamed:@"arrow.clockwise"]
                                        identifier:nil
                                            handler:^(UIAction *action) {
        [self resetSettings];
    }];
    UIAction *cancelAction2 = [UIAction actionWithTitle:@"Cancel"
                                                image:[UIImage systemImageNamed:@"xmark"]
                                        identifier:nil
                                            handler:^(UIAction *action) {
                                            
                                        }];
    resetAction.attributes = UIMenuElementAttributesDestructive;
    UIMenu *resetMenu = [UIMenu menuWithTitle:@"Reset Settings" children:@[resetAction, cancelAction2]];
    
    UIAction *exportSettingsActionQR = [UIAction actionWithTitle:@"Export QR Code"
                                                image:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                        identifier:nil
                                            handler:^(UIAction *action) {
        [self exportSettingsQR];
    }];
    
    // Rename existing to clarify behavior
    UIAction *exportSettingsAction = [UIAction actionWithTitle:@"Show QR Code"
                                                image:[UIImage systemImageNamed:@"square.and.arrow.up"]
                                        identifier:nil
                                            handler:^(UIAction *action) {
        [self exportSettings];
    }];
    
    // New: actually copy JSON to clipboard
    UIAction *exportSettingsClipboardJSON = [UIAction actionWithTitle:@"Export to Clipboard"
                                                image:[UIImage systemImageNamed:@"doc.on.doc"]
                                        identifier:nil
                                            handler:^(UIAction *action) {
        [self exportSettingsToClipboard];
    }];
    
    UIMenu *exportMenu = [UIMenu menuWithTitle:@"Export Settings" children:@[exportSettingsActionQR, exportSettingsAction, exportSettingsClipboardJSON]];
    
    UIAction *importSettingsActionScan = [UIAction actionWithTitle:@"Scan QR Code"
                                                image:[UIImage systemImageNamed:@"qrcode.viewfinder"]
                                        identifier:nil
                                            handler:^(UIAction *action) {
        [self importSettingsQRScan];
    }];
    
    UIAction *importSettingsAction = [UIAction actionWithTitle:@"Import QR Code"
                                                image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                        identifier:nil
                                            handler:^(UIAction *action) {
        [self importSettingsQR];
    }];
    
    UIAction *importSettingsAction2 = [UIAction actionWithTitle:@"Import from Clipboard"
                                                image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                        identifier:nil
                                            handler:^(UIAction *action) {
        [self importSettings];
    }];
    
    UIMenu *importMenu = [UIMenu menuWithTitle:@"Import Settings" children:@[importSettingsAction, importSettingsActionScan, importSettingsAction2]];
    
    UIMenu *importExportMenu = [UIMenu menuWithTitle:@"Import/Export Settings" children:@[importMenu, exportMenu]];
    
    UIMenu *mainMenu = [UIMenu menuWithTitle:@"" children:@[applyMenu, importExportMenu, resetMenu]];
    [applyButton setMenu:mainMenu];
    if (@available(iOS 14.0, *)) {
        SEL sel = NSSelectorFromString(@"setShowsMenuAsPrimaryAction:");
        if ([applyButton respondsToSelector:sel]) {
            ((void (*)(id, SEL, BOOL))[applyButton methodForSelector:sel])(applyButton, sel, YES);
        }
    }
    
    // Conditionally add audioNotesButton only if "Save Audio Notes" is enabled
    NSMutableArray *rightBarButtonItems = [NSMutableArray arrayWithObject:applyButton];
    if (ENABLED(THSaveAudioNotes)) {
        [rightBarButtonItems addObject:audioNotesButton];
    }
    self.navigationItem.rightBarButtonItems = rightBarButtonItems;
}

@end