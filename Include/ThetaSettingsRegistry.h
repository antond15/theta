/**
 * The list of every Theta setting (definitions) and where each is shown (pages).
 * Definitions describe a setting; pages only arrange keys. Rearranging the settings screen
 * means editing the pages, never the definitions or the stored values.
 */
#import <UIKit/UIKit.h>
#import "Include/ThetaSettings.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, THSettingType) {
    THSettingTypeToggle,
    THSettingTypeChoice,
    THSettingTypeColor,
    THSettingTypeList,    // usernames, edited in ThetaUserListEditorViewController
    THSettingTypeAction,  // a button; no stored value
    THSettingTypePage,    // opens a view controller; no stored value
};

@interface THSettingOption : NSObject
@property (nonatomic, copy, readonly) NSString *identifier;  // stored value
@property (nonatomic, copy, readonly) NSString *title;       // shown to the user
@end

@interface THSettingDefinition : NSObject
@property (nonatomic, copy, readonly) NSString *key;
@property (nonatomic, readonly) THSettingType type;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly, nullable) NSString *detail;
@property (nonatomic, copy, readonly, nullable) NSString *info;
/** NSNumber (toggle), NSString option id (choice), UIColor (color), NSArray (list), or nil. */
@property (nonatomic, strong, readonly, nullable) id defaultValue;
@property (nonatomic, copy, readonly, nullable) NSArray<THSettingOption *> *options;
/** Changing it shows a "restart required" banner. */
@property (nonatomic, readonly) BOOL restartRequired;
/** Disabled unless Face ID, Touch ID or a passcode is set up. */
@property (nonatomic, readonly) BOOL requiresBiometrics;
/** Disabled (and reset) on older Instagram versions. */
@property (nonatomic, copy, readonly, nullable) NSString *minimumInstagramVersion;
/** THSettingTypePage: view controller class to push. */
@property (nonatomic, copy, readonly, nullable) NSString *viewControllerClassName;

@property (nonatomic, readonly) BOOL storesValue;
@property (nonatomic, copy, readonly) NSArray<NSString *> *optionTitles;
- (NSInteger)indexOfOption:(NSString *)identifier;  // NSNotFound if unknown
/** NO when the running Instagram is older than minimumInstagramVersion. */
@property (nonatomic, readonly) BOOL availableOnThisVersion;

+ (nullable THSettingDefinition *)definitionForKey:(NSString *)key;
+ (NSArray<THSettingDefinition *> *)allDefinitions;
@end

@interface THSettingsPage : NSObject
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *detail;
@property (nonatomic, copy, readonly) NSString *iconName;
@property (nonatomic, copy, readonly) NSArray<THSettingDefinition *> *settings;
+ (NSArray<THSettingsPage *> *)allPages;
@end

/** Version 1 (title-based) names, for migration and for importing old exports. */
FOUNDATION_EXPORT NSString * _Nullable ThetaSettingKeyForLegacyTitle(NSString *title);
FOUNDATION_EXPORT NSString * _Nullable ThetaSettingOptionForLegacyIndex(NSString *title, NSInteger index);

@interface THSettingsTransfer : NSObject
/** Every stored setting as {"format": "theta-settings", "version": 2, "settings": {key: value}}. */
+ (NSDictionary *)exportDictionary;
/** Accepts exportDictionary output and the older title-based export. Returns how many values were applied. */
+ (NSUInteger)importDictionary:(NSDictionary *)dictionary;
/** Clears every stored setting value. */
+ (void)resetAll;
@end

NS_ASSUME_NONNULL_END
