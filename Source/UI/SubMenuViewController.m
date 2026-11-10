#import "Include/SubMenuViewController.h"
#import "Include/ThetaDebug.h"
#import "Include/CustomSwitchCell.h"
#import "Include/CustomToastView.h"
#import "Include/InstagramHeaders.h"
#import <AudioToolbox/AudioToolbox.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import "Include/ThetaHelper.h"

#import "Include/ThetaSettings.h"
#import "Include/ThetaSettingsRegistry.h"
#import "Include/ThetaUserListEditorViewController.h"

/* Cell layout used for a setting: "switch", "segment", "color", "action" or "view". */
static NSString *THCellKind(THSettingDefinition *setting) {
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

@interface SubMenuViewController ()

@end

static inline BOOL isBiometricOrPasscodeSet() {
    LAContext *context = [[LAContext alloc] init];
    NSError *error = nil;
    
    BOOL isBiometricSet = [context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error];
    
    if (!isBiometricSet) {
        isBiometricSet = [context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:&error];
    }

    return isBiometricSet;
}


UIViewController *THViewControllerForSetting(THSettingDefinition *setting) {
    if (setting.type == THSettingTypeList) {
        ThetaUserListEditorViewController *editor = [[ThetaUserListEditorViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        editor.settingKey = setting.key;
        return editor;
    }
    if (setting.type != THSettingTypePage) return nil;
    Class vcClass = NSClassFromString(setting.viewControllerClassName ?: @"");
    return vcClass ? [[vcClass alloc] init] : nil;
}

void THShowRestartToastIfNeeded(THSettingDefinition *setting) {
    if (!setting.restartRequired) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [ThetaHelper showLoadToast:@"App Restart Required" subtitle:@"Restart the app for changes to apply." icon:[ThetaHelper imageFromEmojiString:@"⚠️" width:300] autoHide:4 openURL:nil];
    });
}

void THResetColorSettings(void) {
    for (THSettingDefinition *setting in [THSettingDefinition allDefinitions]) {
        if (setting.type == THSettingTypeColor) ThetaSettingReset(setting.key);
    }
}

@implementation SubMenuViewController
- (void)viewDidLoad {
    [super viewDidLoad];

    CGFloat spacerHeight = 10.0;
    UIView *spacer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, spacerHeight)];
    spacer.backgroundColor = [UIColor clearColor];
    self.tableView.tableHeaderView = spacer;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.showsHorizontalScrollIndicator = NO;

    [self.tableView registerClass:[CustomSwitchCell class] forCellReuseIdentifier:@"SwitchCell"];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.estimatedRowHeight = 80.0;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refreshSettingsOnForeground)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];

    if (!self.settings) self.settings = @[];
}

- (void)refreshSettingsOnForeground {
    if (!isBiometricOrPasscodeSet() && ENABLED(THAppLock)) {
        THDebugLog(@"biometrics/passcode not set but Lock Instagram is enabled, disabling it");
        ThetaSettingSetEnabled(THAppLock, NO);
    }

    [self.tableView reloadData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.settings.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	THSettingDefinition *setting = self.settings[indexPath.row];
	NSString *settingTitle = setting.title;
	NSString *settingDetail = setting.detail;
	NSString *settingType = THCellKind(setting);

	// Use section rect width to account for InsetGrouped container width
	CGFloat tableWidth = [tableView rectForSection:indexPath.section].size.width;
	if (tableWidth <= 0.0) tableWidth = tableView.bounds.size.width;
	CGFloat leftPadding = 20.0;
	CGFloat rightPadding = 12.0;
	CGFloat textToControlSpacing = 12.0;
	CGFloat minHeight = 54.0;
	CGFloat topPadding = 12.0;
	CGFloat interLabelSpacing = 2.0;
	CGFloat bottomPadding = 12.0;

	// iOS 19 tweak for switch padding
	NSString *osVersion = [[UIDevice currentDevice] systemVersion];
	CGFloat ios19Extra = (osVersion.floatValue >= 19.0) ? 4.0 : 0.0;

	// Reserve right area based on accessory/control for each type
	CGFloat reservedRight = 0.0;
	if ([settingType isEqualToString:@"switch"]) {
		BOOL hasInfo = NO;
		NSString *infoText = setting.info;
		if ([infoText isKindOfClass:[NSString class]] && infoText.length > 0) {
			hasInfo = YES;
		}
		CGFloat switchWidth = 52.0;
		CGFloat infoSize = 28.0;
		CGFloat interControlSpacing = 8.0;
		reservedRight = rightPadding + switchWidth + ios19Extra + (hasInfo ? (interControlSpacing + infoSize) : 0.0) + textToControlSpacing;
	} else if ([settingType isEqualToString:@"color"]) {
		CGFloat colorWellSize = 30.0;
		reservedRight = rightPadding + colorWellSize + textToControlSpacing;
	} else if ([settingType isEqualToString:@"action"]) {
		CGFloat buttonSize = 30.0;
		reservedRight = rightPadding + buttonSize + textToControlSpacing;
	} else if ([settingType isEqualToString:@"view"]) {
		CGFloat reservedRight = rightPadding + 24.0 + textToControlSpacing; // disclosure
		CGFloat contentWidth = tableWidth - leftPadding - reservedRight;
		if (contentWidth < 60.0) contentWidth = 60.0;
		UIFont *titleFont = [UIFont systemFontOfSize:17.0];
		UIFont *detailFont = [UIFont systemFontOfSize:13.0];
		CGFloat titleHeight = 0.0;
		if ([settingTitle isKindOfClass:[NSString class]]) {
			titleHeight = ceilf([settingTitle boundingRectWithSize:CGSizeMake(contentWidth, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading attributes:@{ NSFontAttributeName: titleFont } context:nil].size.height);
		}
		CGFloat detailHeight = 0.0;
		if ([settingDetail isKindOfClass:[NSString class]] && settingDetail.length > 0) {
			detailHeight = ceilf([settingDetail boundingRectWithSize:CGSizeMake(contentWidth, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading attributes:@{ NSFontAttributeName: detailFont } context:nil].size.height);
		}
		CGFloat total = topPadding + titleHeight;
		if (detailHeight > 0.0) total += interLabelSpacing + detailHeight;
		total += bottomPadding + 2.0;
		return MAX(minHeight, total);
	} else if ([settingType isEqualToString:@"segment"]) {
		NSArray<NSString *> *options = setting.optionTitles;
		NSInteger optCount = [options isKindOfClass:[NSArray class]] ? (NSInteger)options.count : 0;
		if (optCount >= 4) {
			// Stacked layout: segment sits below labels, Auto Layout drives the height
			return UITableViewAutomaticDimension;
		}
		// ≤ 3 options as accessory view: estimate actual scaled width to avoid under-reserving
		CGFloat segWidth = MAX(120.0, optCount * 88.0 * 0.82);
		if (segWidth > tableWidth * 0.52) segWidth = tableWidth * 0.52;
		reservedRight = rightPadding + segWidth + textToControlSpacing;
	} else {
		reservedRight = rightPadding + 60.0; // fallback
	}

	CGFloat contentWidth = tableWidth - leftPadding - reservedRight;
	if (contentWidth < 60.0) contentWidth = 60.0;

	UIFont *titleFont = [UIFont systemFontOfSize:17.0];
	UIFont *detailFont = [UIFont systemFontOfSize:13.0];

	CGFloat titleHeight = 0.0;
	if ([settingTitle isKindOfClass:[NSString class]]) {
		titleHeight = ceilf([settingTitle boundingRectWithSize:CGSizeMake(contentWidth, CGFLOAT_MAX)
													  options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
												   attributes:@{ NSFontAttributeName: titleFont }
													  context:nil].size.height);
	}
	CGFloat detailHeight = 0.0;
	if ([settingDetail isKindOfClass:[NSString class]] && settingDetail.length > 0) {
		detailHeight = ceilf([settingDetail boundingRectWithSize:CGSizeMake(contentWidth, CGFLOAT_MAX)
														options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
													 attributes:@{ NSFontAttributeName: detailFont }
														context:nil].size.height);
	}

	CGFloat total = topPadding + titleHeight;
	if (detailHeight > 0.0) total += interLabelSpacing + detailHeight;
	total += bottomPadding;

	// Add a small fudge factor for rounding differences between CoreText and UILabel layout
	total += 2.0;

	return MAX(minHeight, total);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    THSettingDefinition *setting = self.settings[indexPath.row];
    NSString *settingKey = setting.key;
    NSString *settingTitle = setting.title;
    NSString *settingDetail = setting.detail;
    NSString *settingType = THCellKind(setting);

    if ([settingType isEqualToString:@"color"]) {
        static NSString *colorCellIdentifier = @"ColorCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:colorCellIdentifier];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:colorCellIdentifier];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        cell.textLabel.text = settingTitle;
        cell.detailTextLabel.text = settingDetail;
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.numberOfLines = 0;
        cell.preservesSuperviewLayoutMargins = NO;
        cell.layoutMargins = UIEdgeInsetsMake(0, 20, 0, 0);
        cell.separatorInset = UIEdgeInsetsMake(0, 20, 0, 0);
        cell.contentView.preservesSuperviewLayoutMargins = NO;
        if (@available(iOS 11.0, *)) {
            cell.contentView.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(0, 20, 0, 0);
        }
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.numberOfLines = 0;
        cell.preservesSuperviewLayoutMargins = NO;
        cell.layoutMargins = UIEdgeInsetsMake(0, 20, 0, 0);

        if (@available(iOS 14.0, *)) {
            UIColorWell *colorWell = [[UIColorWell alloc] init];
            colorWell.supportsAlpha = NO;
            colorWell.selectedColor = ThetaSettingColor(settingKey);
            colorWell.tag = indexPath.row;
            colorWell.accessibilityIdentifier = settingKey;
            [colorWell addTarget:self action:@selector(colorWellChanged:) forControlEvents:UIControlEventValueChanged];
            // Ensure proper sizing when used as accessoryView
            CGFloat side = 30.0;
            colorWell.frame = CGRectMake(0, 0, side, side);
            [colorWell sizeToFit];
            cell.accessoryView = colorWell;
        }

        return cell;
    }

    if ([settingType isEqualToString:@"action"]) {
        static NSString *actionCellIdentifier = @"ActionCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:actionCellIdentifier];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:actionCellIdentifier];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        cell.textLabel.text = settingTitle;
        cell.detailTextLabel.text = settingDetail;
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.numberOfLines = 0;
        cell.preservesSuperviewLayoutMargins = NO;
        cell.layoutMargins = UIEdgeInsetsMake(0, 20, 0, 0);

        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        NSString *iconName = @"arrow.clockwise";
        SEL actionSelector = @selector(resetButtonColors);
        NSString *accessibilityLabel = @"Reset Colors";
        
        if ([settingKey isEqualToString:THAppClearCache]) {
            iconName = @"trash";
            actionSelector = @selector(clearAppCache);
            accessibilityLabel = @"Clear App Cache";
        }
        
        UIImage *baseIcon = [UIImage systemImageNamed:iconName];
        UIImage *icon = [baseIcon imageWithTintColor:[ThetaHelper iotaPinkColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
        [button setImage:icon forState:UIControlStateNormal];
        button.tintColor = [ThetaHelper iotaPinkColor];
        button.accessibilityLabel = accessibilityLabel;
        [button addTarget:self action:actionSelector forControlEvents:UIControlEventTouchUpInside];
        [button sizeToFit];
        cell.accessoryView = button;
        return cell;
    }

    if ([settingType isEqualToString:@"segment"]) {
        NSArray<NSString *> *options = setting.optionTitles;
        NSInteger selectedOption = MAX(0, [setting indexOfOption:ThetaSettingChoice(settingKey)]);

        if (options.count >= 4) {
            // Stacked layout: title + detail on top, full-width segment below
            static NSString *stackedSegId = @"StackedSegmentCell";
            UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:stackedSegId];
            if (!cell) {
                cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:stackedSegId];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;

                UILabel *titleLbl = [[UILabel alloc] init];
                titleLbl.tag = 9010;
                titleLbl.font = [UIFont systemFontOfSize:17];
                titleLbl.numberOfLines = 0;
                titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
                [cell.contentView addSubview:titleLbl];

                UILabel *detailLbl = [[UILabel alloc] init];
                detailLbl.tag = 9011;
                detailLbl.font = [UIFont systemFontOfSize:13];
                detailLbl.textColor = [UIColor secondaryLabelColor];
                detailLbl.numberOfLines = 0;
                detailLbl.translatesAutoresizingMaskIntoConstraints = NO;
                [cell.contentView addSubview:detailLbl];

                UISegmentedControl *stackedSeg = [[UISegmentedControl alloc] init];
                stackedSeg.tag = 9012;
                stackedSeg.translatesAutoresizingMaskIntoConstraints = NO;
                [stackedSeg addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
                [cell.contentView addSubview:stackedSeg];

                [NSLayoutConstraint activateConstraints:@[
                    [titleLbl.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
                    [titleLbl.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:20],
                    [titleLbl.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],

                    [detailLbl.topAnchor constraintEqualToAnchor:titleLbl.bottomAnchor constant:2],
                    [detailLbl.leadingAnchor constraintEqualToAnchor:titleLbl.leadingAnchor],
                    [detailLbl.trailingAnchor constraintEqualToAnchor:titleLbl.trailingAnchor],

                    [stackedSeg.topAnchor constraintEqualToAnchor:detailLbl.bottomAnchor constant:10],
                    [stackedSeg.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
                    [stackedSeg.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
                    [stackedSeg.heightAnchor constraintEqualToConstant:32],
                    [stackedSeg.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
                ]];
            }

            UILabel *titleLbl = (UILabel *)[cell.contentView viewWithTag:9010];
            UILabel *detailLbl = (UILabel *)[cell.contentView viewWithTag:9011];
            UISegmentedControl *stackedSeg = (UISegmentedControl *)[cell.contentView viewWithTag:9012];

            titleLbl.text = settingTitle;
            detailLbl.text = settingDetail ?: @"";

            [stackedSeg removeAllSegments];
            [options enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                [stackedSeg insertSegmentWithTitle:obj atIndex:idx animated:NO];
            }];
            stackedSeg.selectedSegmentIndex = selectedOption;
            stackedSeg.accessibilityIdentifier = settingKey;

            return cell;
        }

        // ≤ 3 options: side-by-side accessory view
        static NSString *segmentCellIdentifier = @"SegmentCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:segmentCellIdentifier];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:segmentCellIdentifier];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        cell.textLabel.text = settingTitle;
        cell.detailTextLabel.text = settingDetail;
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.numberOfLines = 0;
        cell.preservesSuperviewLayoutMargins = NO;
        cell.layoutMargins = UIEdgeInsetsMake(0, 20, 0, 0);

        UISegmentedControl *seg = nil;
        if ([cell.accessoryView isKindOfClass:[UISegmentedControl class]]) {
            seg = (UISegmentedControl *)cell.accessoryView;
            [seg removeAllSegments];
        } else {
            seg = [[UISegmentedControl alloc] init];
        }
        [options enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [seg insertSegmentWithTitle:obj atIndex:idx animated:NO];
        }];
        seg.selectedSegmentIndex = selectedOption;
        seg.tag = indexPath.row;
        seg.accessibilityIdentifier = settingKey;
        [seg addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
        [seg sizeToFit];
        seg.transform = CGAffineTransformMakeScale(0.8, 0.8);
        cell.accessoryView = seg;
        return cell;
    }

    if ([settingType isEqualToString:@"view"]) {
        static NSString *viewCellId = @"ViewCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:viewCellId];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:viewCellId];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessoryView = nil;
        cell.textLabel.text = settingTitle;
        cell.detailTextLabel.text = settingDetail;
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
        cell.textLabel.numberOfLines = 0;
        cell.detailTextLabel.numberOfLines = 0;
        cell.preservesSuperviewLayoutMargins = NO;
        cell.layoutMargins = UIEdgeInsetsMake(0, 20, 0, 0);
        return cell;
    }

    CustomSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SwitchCell" forIndexPath:indexPath];

    cell.textLabel.text = settingTitle;
    cell.detailTextLabel.text = settingDetail;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13];

    BOOL isEnabled = ENABLED(settingKey);
    if ([cell.settingSwitch respondsToSelector:@selector(setOn:animated:)]) {
        ((void(*)(id,SEL,BOOL,BOOL))[cell.settingSwitch methodForSelector:@selector(setOn:animated:)])(cell.settingSwitch, @selector(setOn:animated:), isEnabled, NO);
    }

    [cell.settingSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.settingSwitch.tag = indexPath.row;

    // Optional info button
    NSString *infoText = setting.info;
    if ([infoText isKindOfClass:[NSString class]] && infoText.length > 0) {
        cell.infoButton.hidden = NO;
        cell.infoButton.tag = indexPath.row;
        [cell.infoButton removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [cell.infoButton addTarget:self action:@selector(didTapInfo:) forControlEvents:UIControlEventTouchUpInside];
        cell.accessibilityHint = @"HasInfo";
    } else {
        cell.infoButton.hidden = YES;
        cell.accessibilityHint = nil;
    }

    for (UIGestureRecognizer *gr in cell.contentView.gestureRecognizers) {
        [cell.contentView removeGestureRecognizer:gr];
    }

    BOOL requiresBiometrics = setting.requiresBiometrics;
    BOOL isBiometricSet = NO;
    if (requiresBiometrics) {
        isBiometricSet = isBiometricOrPasscodeSet();
    }

    BOOL disableForVersion = !setting.availableOnThisVersion;

    if ((requiresBiometrics && !isBiometricSet) || disableForVersion) {
        cell.settingSwitch.enabled = NO;
        cell.textLabel.enabled = NO;
        cell.detailTextLabel.enabled = NO;
        cell.contentView.alpha = 0.5;
        cell.contentView.userInteractionEnabled = YES;

        if (disableForVersion) {
            cell.textLabel.textColor = [UIColor systemGrayColor];
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n(Requires Instagram %@ or later)", settingDetail ?: @"", setting.minimumInstagramVersion];
            if (isEnabled) ThetaSettingReset(settingKey);
        }

        if (requiresBiometrics && !isBiometricSet) {
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showBiometricDisabledAlert)];
            [cell.contentView addGestureRecognizer:tap];
        }
    } else {
        cell.settingSwitch.enabled = YES;
        cell.textLabel.enabled = YES;
        cell.detailTextLabel.enabled = YES;
        cell.contentView.alpha = 1.0;
        cell.contentView.userInteractionEnabled = YES;
    }

    return cell;
}

- (void)didTapInfo:(UIButton *)sender {
    NSInteger row = sender.tag;
    if (row < 0 || row >= (NSInteger)self.settings.count) return;
    THSettingDefinition *setting = self.settings[row];
    NSString *title = setting.title ?: @"Info";
    NSString *message = setting.info ?: setting.detail ?: @"";
    [ThetaHelper showCustomAlertWithActions:title description:message actions:@[@{ @"title": @"OK", @"handler": ^(id s) {} }]];
}

- (void)showBiometricDisabledAlert {
    [ThetaHelper showCustomAlertWithActions:@"Setting Disabled" description:@"This setting requires Face ID, Touch ID, or a device passcode to be set up. Please enable one in your device settings to use this feature." actions:@[
        @{
            @"title": @"OK",
            @"handler": ^(id sender) {
            }
        }
    ]];
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)self.settings.count) return;
    UIViewController *vc = THViewControllerForSetting(self.settings[indexPath.row]);
    if (!vc) return;
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Switch Action

- (void)switchChanged:(UISwitch *)sender {
    if (sender.tag < 0 || sender.tag >= (NSInteger)self.settings.count) return;
    THSettingDefinition *setting = self.settings[sender.tag];
    ThetaSettingSetEnabled(setting.key, sender.isOn);
    THShowRestartToastIfNeeded(setting);
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    THSettingDefinition *setting = [THSettingDefinition definitionForKey:sender.accessibilityIdentifier];
    NSInteger index = sender.selectedSegmentIndex;
    if (setting && index >= 0 && index < (NSInteger)setting.options.count) {
        ThetaSettingSetChoice(setting.key, setting.options[index].identifier);
    }
}

- (void)colorWellChanged:(id)sender {
    if (@available(iOS 14.0, *)) {
        UIColorWell *colorWell = (UIColorWell *)sender;
        if (colorWell.accessibilityIdentifier.length && colorWell.selectedColor) {
            ThetaSettingSetColor(colorWell.accessibilityIdentifier, colorWell.selectedColor);
        }
    }
}

- (void)resetButtonColors {
    THResetColorSettings();
    [self.tableView reloadData];

    if (ENABLED(THAppShowBanners)) {
        [ThetaHelper showToastWithTitle:@"Colors Reset" subtitle:@"Button colors restored to default." icon:[UIImage systemImageNamed:@"checkmark.circle.fill"] autoHide:3 openURL:nil];
    }
}

- (void)clearAppCache {
    [ThetaHelper clearAppCache];
}

@end