#import "Include/THSettingCell.h"
#import "Include/ThetaHelper.h"
#import "Include/ThetaSettings.h"
#import "Include/ThetaSettingsRegistry.h"
#import "Include/ThetaSwitch.h"
#import "Include/ThetaUserListEditorViewController.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import <objc/runtime.h>

static const void *kTHMenuButtonWidthKey = &kTHMenuButtonWidthKey;

static BOOL THBiometricsOrPasscodeSet(void) {
    LAContext *context = [LAContext new];
    return [context canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:nil];
}

BOOL THSettingIsUsable(THSettingDefinition *setting) {
    if (!setting.availableOnThisVersion) return NO;
    if (setting.requiresBiometrics && !THBiometricsOrPasscodeSet()) return NO;
    return YES;
}

void THSettingsDisableUnavailableLock(void) {
    if (ENABLED(THAppLock) && !THBiometricsOrPasscodeSet()) ThetaSettingSetEnabled(THAppLock, NO);
}

static void THShowAlert(NSString *title, NSString *message) {
    [ThetaHelper showCustomAlertWithActions:title description:message actions:@[@{@"title": @"OK", @"handler": ^(id sender) {}}]];
}

static void THShowRestartToastIfNeeded(THSettingDefinition *setting) {
    if (!setting.restartRequired) return;
    [ThetaHelper showLoadToast:@"Restart Required" subtitle:@"Restart Instagram to apply this change."
                          icon:[ThetaHelper imageFromEmojiString:@"⚠️" width:300] autoHide:4 openURL:nil];
}

static void THPerformAction(THSettingDefinition *setting, UITableViewController *host) {
    if ([setting.key isEqualToString:THAppClearCache]) {
        [ThetaHelper clearAppCache];
    } else if ([setting.key isEqualToString:THUIResetColors]) {
        for (THSettingDefinition *def in [THSettingDefinition allDefinitions]) {
            if (def.type == THSettingTypeColor) ThetaSettingReset(def.key);
        }
        [host.tableView reloadData];
        [ThetaHelper showToastWithTitle:@"Colors Reset" subtitle:@"The default colors are back."
                                   icon:[UIImage systemImageNamed:@"checkmark.circle.fill"] autoHide:3 openURL:nil];
    }
}

void THSettingDidSelect(THSettingDefinition *setting, UITableViewController *host) {
    if (setting.requiresBiometrics && !THBiometricsOrPasscodeSet()) {
        THShowAlert(@"Set Up a Passcode", @"Lock Instagram needs Face ID, Touch ID or a passcode. Set one up in the Settings app.");
        return;
    }
    switch (setting.type) {
        case THSettingTypeList: {
            ThetaUserListEditorViewController *editor = [[ThetaUserListEditorViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
            editor.settingKey = setting.key;
            [host.navigationController pushViewController:editor animated:YES];
            break;
        }
        case THSettingTypePage: {
            Class cls = NSClassFromString(setting.viewControllerClassName ?: @"");
            if (cls) [host.navigationController pushViewController:[cls new] animated:YES];
            break;
        }
        case THSettingTypeAction:
            THPerformAction(setting, host);
            break;
        default:
            break;
    }
}

#pragma mark - Cell

@implementation THSettingCell

+ (NSString *)reuseIdentifier {
    return @"THSettingCell";
}

- (void)configureWithSetting:(THSettingDefinition *)setting location:(NSString *)location indented:(BOOL)indented {
    _setting = setting;
    BOOL usable = THSettingIsUsable(setting);
    BOOL opensScreen = setting.type == THSettingTypeList || setting.type == THSettingTypePage;

    // A toggle that needs a newer Instagram can't stay on.
    if (!setting.availableOnThisVersion && setting.type == THSettingTypeToggle && ENABLED(setting.key)) {
        ThetaSettingReset(setting.key);
    }

    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = setting.title;
    content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    content.textProperties.numberOfLines = 0;
    if (!usable) {
        content.textProperties.color = [UIColor secondaryLabelColor];
    } else if (setting.type == THSettingTypeAction) {
        content.textProperties.color = [ThetaHelper iotaPinkColor];
    }
    content.secondaryAttributedText = [self secondaryTextForSetting:setting location:location];
    content.secondaryTextProperties.numberOfLines = 0;
    content.textToSecondaryTextVerticalPadding = 3;
    if (indented) {
        NSDirectionalEdgeInsets margins = content.directionalLayoutMargins;
        margins.leading += 20;
        content.directionalLayoutMargins = margins;
    }
    self.contentConfiguration = content;

    self.accessoryType = opensScreen ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    self.selectionStyle = (opensScreen || setting.type == THSettingTypeAction) ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    self.accessoryView = opensScreen ? nil : [self accessoryForSetting:setting enabled:usable];
}

- (NSAttributedString *)secondaryTextForSetting:(THSettingDefinition *)setting location:(NSString *)location {
    UIFont *small = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    UIColor *grey = [UIColor secondaryLabelColor];
    NSMutableArray<NSAttributedString *> *lines = [NSMutableArray array];

    if (location.length) {
        UIFont *bold = [UIFont fontWithDescriptor:[small.fontDescriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold] size:0];
        [lines addObject:[[NSAttributedString alloc] initWithString:location attributes:@{NSFontAttributeName: bold, NSForegroundColorAttributeName: grey}]];
    }
    if (setting.detail.length) {
        [lines addObject:[[NSAttributedString alloc] initWithString:setting.detail attributes:@{NSFontAttributeName: small, NSForegroundColorAttributeName: grey}]];
    }
    if (setting.restartRequired) {
        [lines addObject:[self line:@"Restart required" symbol:@"arrow.clockwise" font:small color:grey]];
    }
    if (!setting.availableOnThisVersion) {
        NSString *text = [NSString stringWithFormat:@"Requires Instagram %@ or later.", setting.minimumInstagramVersion];
        [lines addObject:[self line:text symbol:@"exclamationmark.circle" font:small color:[UIColor systemOrangeColor]]];
    }

    NSMutableAttributedString *text = [NSMutableAttributedString new];
    for (NSAttributedString *line in lines) {
        if (text.length) [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:@{NSFontAttributeName: small}]];
        [text appendAttributedString:line];
    }
    return text;
}

- (NSAttributedString *)line:(NSString *)string symbol:(NSString *)symbol font:(UIFont *)font color:(UIColor *)color {
    NSMutableAttributedString *line = [NSMutableAttributedString new];
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithFont:font scale:UIImageSymbolScaleSmall];
    UIImage *image = [[UIImage systemImageNamed:symbol withConfiguration:config] imageWithTintColor:color renderingMode:UIImageRenderingModeAlwaysOriginal];
    if (image) {
        NSTextAttachment *attachment = [NSTextAttachment new];
        attachment.image = image;
        [line appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
        [line appendAttributedString:[[NSAttributedString alloc] initWithString:@" "]];
    }
    [line appendAttributedString:[[NSAttributedString alloc] initWithString:string]];
    [line addAttributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: color} range:NSMakeRange(0, line.length)];
    return line;
}

#pragma mark Accessories

- (UIView *)accessoryForSetting:(THSettingDefinition *)setting enabled:(BOOL)enabled {
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    if (setting.info.length) [views addObject:[self infoButton]];

    UIControl *control = nil;
    switch (setting.type) {
        case THSettingTypeToggle: control = [self switchForSetting:setting]; break;
        case THSettingTypeChoice: control = [self menuButtonForSetting:setting]; break;
        case THSettingTypeColor: control = [self colorWellForSetting:setting]; break;
        default: break;
    }
    if (control) {
        control.enabled = enabled;
        control.userInteractionEnabled = enabled;
        control.alpha = enabled ? 1 : 0.5;
        [views addObject:control];
    }
    if (!views.count) return nil;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:views];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 12;
    CGSize size = [stack systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    stack.frame = CGRectMake(0, 0, ceil(size.width), ceil(size.height));
    return stack;
}

- (UIButton *)infoButton {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeInfoLight];
    button.tintColor = [ThetaHelper iotaPinkColor];
    button.accessibilityLabel = [NSString stringWithFormat:@"About %@", self.setting.title];
    [button addTarget:self action:@selector(infoTapped) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)infoTapped {
    THShowAlert(self.setting.title, self.setting.info);
}

- (UIControl *)switchForSetting:(THSettingDefinition *)setting {
    ThetaSwitch *control = [[ThetaSwitch alloc] initWithFrame:CGRectZero];
    [control setOn:ENABLED(setting.key) animated:NO];
    control.accessibilityLabel = setting.title;
    [control addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [control.widthAnchor constraintEqualToConstant:control.intrinsicContentSize.width].active = YES;
    [control.heightAnchor constraintEqualToConstant:control.intrinsicContentSize.height].active = YES;
    return control;
}

- (void)switchChanged:(ThetaSwitch *)sender {
    ThetaSettingSetEnabled(self.setting.key, sender.isOn);
    THShowRestartToastIfNeeded(self.setting);
}

- (UIControl *)menuButtonForSetting:(THSettingDefinition *)setting {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tintColor = [ThetaHelper iotaPinkColor];
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithTextStyle:UIFontTextStyleFootnote scale:UIImageSymbolScaleSmall];
    [button setImage:[UIImage systemImageNamed:@"chevron.up.chevron.down" withConfiguration:config] forState:UIControlStateNormal];
    button.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
    button.showsMenuAsPrimaryAction = YES;
    [self updateMenuButton:button forSetting:setting];
    return button;
}

- (void)updateMenuButton:(UIButton *)button forSetting:(THSettingDefinition *)setting {
    NSString *selected = ThetaSettingChoice(setting.key);
    NSInteger index = [setting indexOfOption:selected];
    NSString *title = (index == NSNotFound ? setting.options.firstObject : setting.options[index]).title;
    [button setTitle:[title stringByAppendingString:@" "] forState:UIControlStateNormal];  // gap before the chevron
    button.accessibilityLabel = setting.title;

    NSMutableArray<UIAction *> *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    __weak UIButton *weakButton = button;
    for (THSettingOption *option in setting.options) {
        UIAction *action = [UIAction actionWithTitle:option.title image:nil identifier:nil handler:^(UIAction *a) {
            ThetaSettingSetChoice(setting.key, option.identifier);
            if (weakButton) [weakSelf updateMenuButton:weakButton forSetting:setting];
            THShowRestartToastIfNeeded(setting);
        }];
        action.state = [option.identifier isEqualToString:selected] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    button.menu = [UIMenu menuWithTitle:setting.title children:actions];

    // Long option titles (dates) must not squeeze the setting's own title to nothing.
    NSLayoutConstraint *width = objc_getAssociatedObject(button, kTHMenuButtonWidthKey);
    if (!width) {
        width = [button.widthAnchor constraintEqualToConstant:0];
        width.active = YES;
        objc_setAssociatedObject(button, kTHMenuButtonWidthKey, width, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    width.constant = MIN(ceil(button.intrinsicContentSize.width), 170);
    UIView *stack = button.superview;
    if (stack) {
        CGSize size = [stack systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
        stack.frame = CGRectMake(0, 0, ceil(size.width), ceil(size.height));
        [self setNeedsLayout];
    }
}

- (UIControl *)colorWellForSetting:(THSettingDefinition *)setting {
    UIColorWell *well = [UIColorWell new];
    well.supportsAlpha = NO;
    well.title = setting.title;
    well.selectedColor = ThetaSettingColor(setting.key);
    [well addTarget:self action:@selector(colorChanged:) forControlEvents:UIControlEventValueChanged];
    [well.widthAnchor constraintEqualToConstant:30].active = YES;
    [well.heightAnchor constraintEqualToConstant:30].active = YES;
    return well;
}

- (void)colorChanged:(UIColorWell *)sender {
    if (sender.selectedColor) ThetaSettingSetColor(self.setting.key, sender.selectedColor);
}

@end
