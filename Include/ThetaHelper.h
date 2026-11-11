#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface ThetaHelper : NSObject

+ (NSString *)hexFromColour:(UIColor *)colour;
+ (UIColor *)colourFromHex:(NSString *)hexString;

#pragma mark - Alert Management
+ (void)showCustomAlertWithActions:(NSString *)title description:(NSString *)description actions:(NSArray<NSDictionary *> *)actions;

#pragma mark - Toast Management
+ (void)showToastWithTitle:(NSString *)title subtitle:(NSString *)subtitle icon:(UIImage *)icon autoHide:(int)seconds openURL:(NSURL *)openURL;
+ (void)showLoadToast:(NSString *)title subtitle:(NSString *)subtitle icon:(UIImage *)icon autoHide:(int)seconds openURL:(NSURL *)openURL;

#pragma mark - Haptic Feedback
+ (void)performHapticFeedbackIfEnabled;

#pragma mark - Image Utilities
+ (UIImage *)imageFromEmojiString:(NSString *)emojiString width:(CGFloat)width;

#pragma mark - File Management
+ (void)createDirectoryIfNotExists:(NSURL *)URL;
+ (void)cleanupTemporaryMediaFiles;
/** Clears Library/Caches and Theta's leftover temp files, then shows a summary banner. Never touches saved media. */
+ (void)clearAppCache;

#pragma mark - Download Management
+ (BOOL)tryBeginGlobalDownloadOrNotify;
+ (void)endGlobalDownload;
+ (BOOL)isGlobalDownloadInProgress;

#pragma mark - Utility Functions
+ (UIViewController *)nearestViewController:(UIView *)view;
+ (UIViewController *)topViewController;

#pragma mark - Settings Helpers
// Stores selected index for a segment setting with given title

#pragma mark - Constants
+ (UIColor *)iotaPinkColor;
+ (NSTimeInterval)cooldownPeriod;

@end 