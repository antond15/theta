#import <UIKit/UIKit.h>

/// Edits a list setting (THSettingTypeList) of lowercase usernames, e.g. the Story Ghost auto-mark list.
/// Set settingKey before presenting; the title and footer come from the setting's definition.
@interface ThetaUserListEditorViewController : UITableViewController
@property (nonatomic, copy) NSString *settingKey;
@end
