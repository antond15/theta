#import <UIKit/UIKit.h>

@class THSettingsPage;

/** One settings page: its sections, with headers and footers, from ThetaSettingsRegistry.m. */
@interface SubMenuViewController : UITableViewController
- (instancetype)initWithPage:(THSettingsPage *)page;
@end
