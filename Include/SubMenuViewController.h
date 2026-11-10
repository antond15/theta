#import <UIKit/UIKit.h>

#define IOTA_PINK [UIColor colorWithRed:1.0 green:0.412 blue:0.706 alpha:1.0]

@class THSettingDefinition;

@interface SubMenuViewController : UITableViewController
@property (nonatomic, strong) NSArray<THSettingDefinition *> *settings;
@end

/** View controller a list or page setting opens; nil for other types. */
FOUNDATION_EXPORT UIViewController *THViewControllerForSetting(THSettingDefinition *setting);
/** Shows the "App Restart Required" banner when the setting needs it. */
FOUNDATION_EXPORT void THShowRestartToastIfNeeded(THSettingDefinition *setting);
/** Resets every color setting to its default. */
FOUNDATION_EXPORT void THResetColorSettings(void);
