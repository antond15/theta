/**
 * The one cell every settings screen uses for a setting (pages and search), and the row
 * actions they share. The cell reads and writes the setting's value itself, so screens only
 * lay out rows and forward taps to THSettingDidSelect.
 */
#import <UIKit/UIKit.h>

@class THSettingDefinition;

NS_ASSUME_NONNULL_BEGIN

@interface THSettingCell : UITableViewCell
@property (class, nonatomic, readonly) NSString *reuseIdentifier;
@property (nonatomic, strong, readonly, nullable) THSettingDefinition *setting;

/**
 * location: "Page › Section" line shown above the detail (search results), or nil.
 * indented: shown as a sub-option of the row above.
 */
- (void)configureWithSetting:(THSettingDefinition *)setting location:(nullable NSString *)location indented:(BOOL)indented;
@end

/** NO when the setting can't be changed here: too old an Instagram, or no Face ID / passcode. */
FOUNDATION_EXPORT BOOL THSettingIsUsable(THSettingDefinition *setting);
/** Handles a tap on a setting's row: opens lists and pages, runs actions, explains disabled rows. */
FOUNDATION_EXPORT void THSettingDidSelect(THSettingDefinition *setting, UITableViewController *host);
/** Turns off Lock Instagram when Face ID, Touch ID and the passcode have all been removed. */
FOUNDATION_EXPORT void THSettingsDisableUnavailableLock(void);

NS_ASSUME_NONNULL_END
