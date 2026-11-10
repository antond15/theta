#import "Include/ThetaUserListEditorViewController.h"
#import "Include/ThetaHelper.h"
#import "Include/ThetaSettingsRegistry.h"

static NSString *const kCellId = @"UserCell";

@implementation ThetaUserListEditorViewController

- (instancetype)initWithStyle:(UITableViewStyle)style {
    if (self = [super initWithStyle:UITableViewStyleInsetGrouped]) {
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [THSettingDefinition definitionForKey:self.settingKey].title ?: @"List";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    UIBarButtonItem *addItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                              target:self
                                                                              action:@selector(addUsername)];
    addItem.tintColor = [ThetaHelper iotaPinkColor];
    self.navigationItem.rightBarButtonItem = addItem;

    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kCellId];
}

- (NSMutableArray<NSString *> *)currentList {
    return self.settingKey.length ? [ThetaSettingList(self.settingKey) mutableCopy] : [NSMutableArray array];
}

- (void)saveList:(NSArray<NSString *> *)list {
    if (self.settingKey.length) ThetaSettingSetList(self.settingKey, list);
}

- (void)addUsername {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add Account"
                                                                   message:@"Enter an Instagram username."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"username";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Add" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *input = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (input.length == 0) return;
        NSString *username = [input lowercaseString];
        if ([username hasPrefix:@"@"]) {
            username = [username substringFromIndex:1];
        }
        NSMutableArray *list = [weakSelf currentList];
        if ([list containsObject:username]) return;
        [list addObject:username];
        [weakSelf saveList:list];
        [weakSelf.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self currentList].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellId forIndexPath:indexPath];
    NSArray *list = [self currentList];
    if (indexPath.row < (NSInteger)list.count) {
        cell.textLabel.text = [NSString stringWithFormat:@"@%@", list[indexPath.row]];
    }
    cell.textLabel.textColor = [UIColor labelColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    NSMutableArray *list = [self currentList];
    if (indexPath.row >= (NSInteger)list.count) return;
    [list removeObjectAtIndex:indexPath.row];
    [self saveList:list];
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return [THSettingDefinition definitionForKey:self.settingKey].info;
}

@end
