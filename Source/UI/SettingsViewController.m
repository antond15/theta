#import "Include/SettingsViewController.h"
#import "Include/AudioNotesViewController.h"
#import "Include/SubMenuViewController.h"
#import "Include/THSettingCell.h"
#import "Include/ThetaHelper.h"
#import "Include/ThetaSettings.h"
#import "Include/ThetaSettingsRegistry.h"
#import <AVFoundation/AVFoundation.h>
#import <zlib.h>

static NSString *const kPageCellId = @"PageCell";
static NSString *const kLinkCellId = @"LinkCell";
static NSString *const kRepositoryURL = @"https://github.com/antond15/theta";

/** A search hit: the setting and where it lives, "Page › Section". */
@interface THSearchResult : NSObject
@property (nonatomic, strong) THSettingDefinition *setting;
@property (nonatomic, copy) NSString *location;
@end

@implementation THSearchResult
@end

@interface SettingsViewController () <UISearchResultsUpdating, AVCaptureMetadataOutputObjectsDelegate, UINavigationControllerDelegate, UIImagePickerControllerDelegate>
@property (nonatomic, copy) NSArray<NSArray<THSettingsPage *> *> *pageGroups;
@property (nonatomic, copy) NSArray<THSearchResult *> *searchResults;  // nil when not searching
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) AVCaptureSession *qrSession;
@property (nonatomic, strong) UIViewController *qrScanVC;
@end

#pragma mark - Settings data

/* Settings as they travel between devices: JSON for the clipboard, base64 of zlib-compressed JSON in QR codes. */

static NSData *THSettingsJSON(void) {
    return [NSJSONSerialization dataWithJSONObject:[THSettingsTransfer exportDictionary] options:NSJSONWritingPrettyPrinted error:nil];
}

static NSData *THDeflate(NSData *data) {
    uLong length = compressBound((uLong)data.length);
    NSMutableData *out = [NSMutableData dataWithLength:length];
    if (compress(out.mutableBytes, &length, data.bytes, (uLong)data.length) != Z_OK) return nil;
    out.length = length;
    return out;
}

static NSData *THInflate(NSData *data) {
    if (!data.length) return nil;
    z_stream strm = {0};
    strm.avail_in = (uInt)data.length;
    strm.next_in = (Bytef *)data.bytes;
    if (inflateInit(&strm) != Z_OK) return nil;

    NSMutableData *out = [NSMutableData dataWithLength:data.length * 4];
    int status;
    do {
        if (strm.total_out >= out.length) [out increaseLengthBy:MAX(data.length / 2, 1024u)];
        strm.next_out = (Bytef *)out.mutableBytes + strm.total_out;
        strm.avail_out = (uInt)(out.length - strm.total_out);
        status = inflate(&strm, Z_SYNC_FLUSH);
        if (status == Z_STREAM_ERROR || status == Z_DATA_ERROR || status == Z_MEM_ERROR || status == Z_NEED_DICT ||
            (status == Z_BUF_ERROR && strm.avail_in == 0)) {
            inflateEnd(&strm);
            return nil;
        }
    } while (status != Z_STREAM_END);
    inflateEnd(&strm);
    out.length = strm.total_out;
    return out;
}

/** Parses exported settings: plain JSON, or a QR code's base64 zlib JSON. nil if it isn't either. */
static NSDictionary *THSettingsFromString(NSString *string) {
    NSString *trimmed = [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSData *json = nil;
    if ([trimmed hasPrefix:@"{"]) {
        json = [trimmed dataUsingEncoding:NSUTF8StringEncoding];
    } else {
        NSData *compressed = [[NSData alloc] initWithBase64EncodedString:trimmed options:0];
        json = THInflate(compressed);
    }
    if (!json) return nil;
    id object = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
    return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

static UIImage *THSettingsQRCode(void) {
    NSData *json = THSettingsJSON();
    NSData *compressed = json ? THDeflate(json) : nil;
    NSData *payload = [[compressed base64EncodedStringWithOptions:0] dataUsingEncoding:NSUTF8StringEncoding];
    if (!payload.length) return nil;

    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setValue:payload forKey:@"inputMessage"];
    CIImage *image = [filter.outputImage imageByApplyingTransform:CGAffineTransformMakeScale(10, 10)];
    if (!image) return nil;
    CGImageRef cgImage = [[CIContext contextWithOptions:nil] createCGImage:image fromRect:image.extent];
    if (!cgImage) return nil;
    UIImage *result = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    return result;
}

static void THShowFailure(NSString *title, NSString *subtitle) {
    [ThetaHelper showToastWithTitle:title subtitle:subtitle icon:[UIImage systemImageNamed:@"exclamationmark.triangle"] autoHide:3 openURL:nil];
}

static void THShowImportFailure(NSString *subtitle) {
    THShowFailure(@"Couldn't Import Settings", subtitle);
}

static void THShowExportFailure(NSString *subtitle) {
    THShowFailure(@"Couldn't Export Settings", subtitle);
}

/* Instagram reads most settings once, so these close it. A local notification tells the user why. */
static void THCloseInstagram(NSString *notificationTitle, NSString *notificationBody, NSTimeInterval delay) {
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (notificationTitle) {
        UILocalNotification *notification = [UILocalNotification new];
        notification.fireDate = [NSDate dateWithTimeIntervalSinceNow:0.5];
        notification.alertTitle = notificationTitle;
        notification.alertBody = notificationBody;
        notification.soundName = UILocalNotificationDefaultSoundName;
        [[UIApplication sharedApplication] scheduleLocalNotification:notification];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] performSelector:@selector(suspend)];
        exit(0);
    });
}

static NSString *THImportedText(NSUInteger count) {
    return [NSString stringWithFormat:@"Imported %lu setting%@.", (unsigned long)count, count == 1 ? @"" : @"s"];
}

@implementation SettingsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.pageGroups = [THSettingsPage pageGroups];

    [self.tableView registerClass:[THSettingCell class] forCellReuseIdentifier:THSettingCell.reuseIdentifier];
    self.tableView.showsVerticalScrollIndicator = NO;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"Search";
    self.searchController.searchBar.tintColor = [ThetaHelper iotaPinkColor];
    self.navigationItem.searchController = self.searchController;
    self.definesPresentationContext = YES;

    UIColor *pink = [ThetaHelper iotaPinkColor];
    self.navigationController.navigationBar.tintColor = pink;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[self barImage:@"chevron.down"] style:UIBarButtonItemStylePlain
                                                                            target:self action:@selector(dismiss)];
    // Plain, not Done: Done becomes a filled tinted chip on iOS 26+ (Liquid Glass), which makes a pink gear invisible on a pink circle.
    UIBarButtonItem *menuButton = [[UIBarButtonItem alloc] initWithImage:[self barImage:@"gearshape"] style:UIBarButtonItemStylePlain target:nil action:nil];
    menuButton.menu = [self settingsMenu];
    UIBarButtonItem *folderButton = [[UIBarButtonItem alloc] initWithImage:[self barImage:@"folder"] style:UIBarButtonItemStylePlain
                                                                    target:self action:@selector(openSavedMedia)];
    folderButton.accessibilityLabel = @"Saved Media";
    self.navigationItem.rightBarButtonItems = @[menuButton, folderButton];

    [self setupAnimatedTitle];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.searchResults) [self.tableView reloadData];
}

- (UIImage *)barImage:(NSString *)name {
    return [[UIImage systemImageNamed:name] imageWithTintColor:[ThetaHelper iotaPinkColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (void)setupAnimatedTitle {
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 5;
    UIFont *font = [UIFont fontWithName:@"HelveticaNeue-Bold" size:24] ?: [UIFont boldSystemFontOfSize:24];
    NSMutableArray<UILabel *> *letters = [NSMutableArray array];
    for (NSUInteger i = 0; i < @"THETA".length; i++) {
        UILabel *label = [UILabel new];
        label.text = [@"THETA" substringWithRange:NSMakeRange(i, 1)];
        label.font = font;
        label.textColor = [ThetaHelper iotaPinkColor];
        label.alpha = 0;
        [stack addArrangedSubview:label];
        [letters addObject:label];
    }
    self.navigationItem.titleView = stack;
    self.title = @"Theta";

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (NSUInteger i = 0; i < letters.count; i++) {
            [UIView animateWithDuration:0.5 delay:i * 0.08 options:UIViewAnimationOptionCurveEaseInOut
                             animations:^{ letters[i].alpha = 1; } completion:nil];
        }
    });
}

- (void)dismiss {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)openSavedMedia {
    [self.navigationController pushViewController:[[AudioNotesViewController alloc] initWithMode:AudioNotesContentModeSavedMedia] animated:YES];
}

#pragma mark - Menu

- (UIAction *)action:(NSString *)title image:(NSString *)image handler:(void (^)(void))handler {
    return [UIAction actionWithTitle:title image:[UIImage systemImageNamed:image] identifier:nil handler:^(UIAction *a) { handler(); }];
}

/** A submenu whose first item does `title`, plus Cancel. */
- (UIMenu *)confirmMenu:(NSString *)menuTitle button:(NSString *)button image:(NSString *)image destructive:(BOOL)destructive handler:(void (^)(void))handler {
    UIAction *confirm = [self action:button image:image handler:handler];
    if (destructive) confirm.attributes = UIMenuElementAttributesDestructive;
    return [UIMenu menuWithTitle:menuTitle children:@[confirm, [self action:@"Cancel" image:@"xmark" handler:^{}]]];
}

- (UIMenu *)settingsMenu {
    __weak typeof(self) weakSelf = self;
    UIMenu *import = [UIMenu menuWithTitle:@"Import Settings" children:@[
        [self action:@"From QR Code Image" image:@"photo" handler:^{ [weakSelf importFromQRImage]; }],
        [self action:@"Scan QR Code" image:@"qrcode.viewfinder" handler:^{ [weakSelf importByScanning]; }],
        [self action:@"From Clipboard" image:@"doc.on.clipboard" handler:^{ [weakSelf importFromClipboard]; }],
    ]];
    UIMenu *export = [UIMenu menuWithTitle:@"Export Settings" children:@[
        [self action:@"Share QR Code" image:@"square.and.arrow.up" handler:^{ [weakSelf shareQRCode]; }],
        [self action:@"Show QR Code" image:@"qrcode" handler:^{ [weakSelf showQRCode]; }],
        [self action:@"Copy to Clipboard" image:@"doc.on.doc" handler:^{ [weakSelf exportToClipboard]; }],
    ]];
    return [UIMenu menuWithTitle:@"" children:@[
        [self confirmMenu:@"Restart Instagram" button:@"Restart" image:@"arrow.clockwise" destructive:NO handler:^{ [weakSelf restartInstagram]; }],
        [UIMenu menuWithTitle:@"Import & Export" children:@[import, export]],
        [self confirmMenu:@"Reset All Settings" button:@"Reset" image:@"arrow.counterclockwise" destructive:YES handler:^{ [weakSelf resetSettings]; }],
    ]];
}

- (void)restartInstagram {
    [ThetaHelper showToastWithTitle:@"Closing Instagram" subtitle:@"Open it again to apply your changes."
                               icon:[ThetaHelper imageFromEmojiString:@"✅" width:300] autoHide:3 openURL:nil];
    THCloseInstagram(nil, nil, 3);
}

- (void)resetSettings {
    [THSettingsTransfer resetAll];
    THCloseInstagram(@"Settings Reset", @"Open Instagram to continue with the default settings.", 0.2);
}

#pragma mark - Export

- (void)shareQRCode {
    UIImage *qr = THSettingsQRCode();
    if (!qr) return THShowExportFailure(@"The QR code couldn't be created.");
    [[ThetaHelper topViewController] presentViewController:[[UIActivityViewController alloc] initWithActivityItems:@[qr] applicationActivities:nil]
                                                  animated:YES completion:nil];
}

- (void)showQRCode {
    UIImage *qr = THSettingsQRCode();
    if (!qr) return THShowExportFailure(@"The QR code couldn't be created.");

    UIViewController *qrVC = [UIViewController new];
    qrVC.view.backgroundColor = [UIColor whiteColor];
    UIImageView *imageView = [[UIImageView alloc] initWithImage:qr];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    [qrVC.view addSubview:imageView];
    [NSLayoutConstraint activateConstraints:@[
        [imageView.centerXAnchor constraintEqualToAnchor:qrVC.view.centerXAnchor],
        [imageView.centerYAnchor constraintEqualToAnchor:qrVC.view.centerYAnchor],
        [imageView.widthAnchor constraintEqualToConstant:250],
        [imageView.heightAnchor constraintEqualToConstant:250],
    ]];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:qrVC];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [self presentViewController:nav animated:YES completion:nil];
    [ThetaHelper showToastWithTitle:@"QR Code Ready" subtitle:@"On another device, scan it from Import Settings in Theta."
                               icon:[UIImage systemImageNamed:@"checkmark.circle.fill"] autoHide:4 openURL:nil];
}

- (void)exportToClipboard {
    NSData *json = THSettingsJSON();
    NSString *string = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
    if (!string) return THShowExportFailure(@"The settings couldn't be copied.");
    [UIPasteboard generalPasteboard].string = string;
    [ThetaHelper showToastWithTitle:@"Settings Copied" subtitle:@"On another device, use Import Settings › From Clipboard."
                               icon:[UIImage systemImageNamed:@"doc.on.doc.fill"] autoHide:3 openURL:nil];
}

#pragma mark - Import

- (void)importFromClipboard {
    NSString *string = [UIPasteboard generalPasteboard].string;
    if (!string.length) return THShowImportFailure(@"The clipboard is empty.");
    NSDictionary *settings = THSettingsFromString(string);
    if (!settings) return THShowImportFailure(@"The clipboard doesn't contain Theta settings.");
    NSUInteger count = [THSettingsTransfer importDictionary:settings];
    THCloseInstagram(@"Settings Imported", [THImportedText(count) stringByAppendingString:@" Open Instagram to apply them."], 0.1);
}

- (void)importFromQRImage {
    UIImagePickerController *picker = [UIImagePickerController new];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *, id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{
        if (!image) return THShowImportFailure(@"No image was selected.");
        CIDetector *detector = [CIDetector detectorOfType:CIDetectorTypeQRCode context:nil options:@{CIDetectorAccuracy: CIDetectorAccuracyHigh}];
        NSArray *features = [detector featuresInImage:[[CIImage alloc] initWithImage:image]];
        if (!features.count) return THShowImportFailure(@"No QR code was found in the image.");
        NSString *string = ((CIQRCodeFeature *)features.firstObject).messageString;
        if (!string) return THShowImportFailure(@"The QR code couldn't be read.");
        NSDictionary *settings = THSettingsFromString(string);
        if (!settings) return THShowImportFailure(@"This QR code doesn't contain Theta settings.");
        NSUInteger count = [THSettingsTransfer importDictionary:settings];
        THCloseInstagram(@"Settings Imported", [THImportedText(count) stringByAppendingString:@" Open Instagram to apply them."], 0.1);
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)importByScanning {
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceInput *input = device ? [AVCaptureDeviceInput deviceInputWithDevice:device error:nil] : nil;
    if (!input) {
        THShowFailure(@"Camera Unavailable", @"Allow camera access for Instagram in the Settings app.");
        return;
    }
    AVCaptureSession *session = [AVCaptureSession new];
    [session addInput:input];
    AVCaptureMetadataOutput *output = [AVCaptureMetadataOutput new];
    [session addOutput:output];
    [output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
    output.metadataObjectTypes = @[AVMetadataObjectTypeQRCode];

    UIViewController *scanVC = [UIViewController new];
    AVCaptureVideoPreviewLayer *preview = [AVCaptureVideoPreviewLayer layerWithSession:session];
    preview.frame = [UIScreen mainScreen].bounds;
    preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [scanVC.view.layer addSublayer:preview];

    self.qrSession = session;
    self.qrScanVC = scanVC;
    [self presentViewController:scanVC animated:YES completion:^{ [session startRunning]; }];
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)objects fromConnection:(AVCaptureConnection *)connection {
    AVMetadataMachineReadableCodeObject *code = objects.firstObject;
    if (![code.type isEqualToString:AVMetadataObjectTypeQRCode] || !code.stringValue || !self.qrSession.isRunning) return;
    NSString *string = code.stringValue;
    [self.qrSession stopRunning];
    [self.qrScanVC dismissViewControllerAnimated:YES completion:^{
        NSDictionary *settings = THSettingsFromString(string);
        if (!settings) return THShowImportFailure(@"This QR code doesn't contain Theta settings.");
        NSUInteger count = [THSettingsTransfer importDictionary:settings];
        [ThetaHelper showToastWithTitle:@"Settings Imported" subtitle:[THImportedText(count) stringByAppendingString:@" Instagram will close to apply them."]
                                   icon:[ThetaHelper imageFromEmojiString:@"✅" width:300] autoHide:2 openURL:nil];
        THCloseInstagram(nil, nil, 3);
    }];
}

#pragma mark - Search

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = [searchController.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (!query.length) {
        self.searchResults = nil;
        [self.tableView reloadData];
        return;
    }
    NSMutableArray *results = [NSMutableArray array];
    for (THSettingsPage *page in [THSettingsPage allPages]) {
        for (THSettingsSection *section in page.sections) {
            for (THSettingDefinition *setting in section.settings) {
                BOOL match = [setting.title localizedCaseInsensitiveContainsString:query] ||
                             [setting.detail localizedCaseInsensitiveContainsString:query] ||
                             [page.title localizedCaseInsensitiveContainsString:query] ||
                             [section.header localizedCaseInsensitiveContainsString:query];
                if (!match) continue;
                THSearchResult *result = [THSearchResult new];
                result.setting = setting;
                result.location = section.header ? [NSString stringWithFormat:@"%@ › %@", page.title, section.header] : page.title;
                [results addObject:result];
            }
        }
    }
    self.searchResults = results;
    [self.tableView reloadData];
}

#pragma mark - Table view

/* Not searching: one section per page group, then the link section. */

- (BOOL)isLinkSection:(NSInteger)section {
    return !self.searchResults && section == (NSInteger)self.pageGroups.count;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.searchResults ? 1 : self.pageGroups.count + 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.searchResults) return self.searchResults.count;
    if ([self isLinkSection:section]) return 1;
    return self.pageGroups[section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.searchResults) {
        THSettingCell *cell = [tableView dequeueReusableCellWithIdentifier:THSettingCell.reuseIdentifier forIndexPath:indexPath];
        THSearchResult *result = self.searchResults[indexPath.row];
        [cell configureWithSetting:result.setting location:result.location indented:NO];
        return cell;
    }

    BOOL link = [self isLinkSection:indexPath.section];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:link ? kLinkCellId : kPageCellId];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:link ? kLinkCellId : kPageCellId];
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.imageProperties.tintColor = [ThetaHelper iotaPinkColor];
    content.secondaryTextProperties.color = [UIColor secondaryLabelColor];
    content.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    if (link) {
        content.text = @"Theta on GitHub";
        content.textProperties.color = [ThetaHelper iotaPinkColor];
        content.image = [UIImage systemImageNamed:@"link"];
    } else {
        THSettingsPage *page = self.pageGroups[indexPath.section][indexPath.row];
        content.text = page.title;
        content.secondaryText = page.detail;
        content.image = [UIImage systemImageNamed:page.iconName];
    }
    cell.contentConfiguration = content;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (![self isLinkSection:section]) return nil;
    NSString *instagram = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
#ifdef THETA_VERSION
    NSString *theta = @THETA_VERSION;
#else
    NSString *theta = @"unknown";
#endif
    return [NSString stringWithFormat:@"Theta %@ · Instagram %@\nMade by @objc_msgSend\nMaintained by @antond15", theta, instagram];
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    if (![self isLinkSection:section] || ![view isKindOfClass:[UITableViewHeaderFooterView class]]) return;
    UILabel *label = ((UITableViewHeaderFooterView *)view).textLabel;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (self.searchResults) {
        THSettingDidSelect(self.searchResults[indexPath.row].setting, self);
    } else if ([self isLinkSection:indexPath.section]) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:kRepositoryURL] options:@{} completionHandler:nil];
    } else {
        THSettingsPage *page = self.pageGroups[indexPath.section][indexPath.row];
        [self.navigationController pushViewController:[[SubMenuViewController alloc] initWithPage:page] animated:YES];
    }
}

@end
