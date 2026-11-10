#import "Include/SubMenuViewController.h"
#import "Include/THSettingCell.h"
#import "Include/ThetaSettingsRegistry.h"

@implementation SubMenuViewController {
    THSettingsPage *_page;
}

- (instancetype)initWithPage:(THSettingsPage *)page {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _page = page;
        self.title = page.title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    [self.tableView registerClass:[THSettingCell class] forCellReuseIdentifier:THSettingCell.reuseIdentifier];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterForeground)
                                                 name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];  // lists and other screens may have changed values
}

- (void)willEnterForeground {
    THSettingsDisableUnavailableLock();
    [self.tableView reloadData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _page.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _page.sections[section].settings.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return _page.sections[section].header;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return _page.sections[section].footer;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    THSettingCell *cell = [tableView dequeueReusableCellWithIdentifier:THSettingCell.reuseIdentifier forIndexPath:indexPath];
    THSettingDefinition *setting = _page.sections[indexPath.section].settings[indexPath.row];
    [cell configureWithSetting:setting location:nil indented:setting.parentKey != nil];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    THSettingDidSelect(_page.sections[indexPath.section].settings[indexPath.row], self);
}

@end
