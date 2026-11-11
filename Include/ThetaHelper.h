#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/** Errors from the media save paths (`downloadMediaToTemp:`, the single reel save). */
FOUNDATION_EXPORT NSString *const ThetaSaveErrorDomain;
typedef NS_ENUM(NSInteger, ThetaSaveErrorCode) {
    ThetaSaveErrorDownload = 1,
    ThetaSaveErrorHTTP,
    ThetaSaveErrorPhotosAccess,
    ThetaSaveErrorPhotosWrite,
    ThetaSaveErrorFile,
};

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

#pragma mark - Save Helpers
/** Authorized or Limited -> YES; asks once when undetermined; otherwise NO. Completion runs on the main queue. */
+ (void)ensurePhotosAccess:(void (^)(BOOL granted))completion;
/** Error in `ThetaSaveErrorDomain`; `underlying` may be nil. */
+ (NSError *)saveErrorWithCode:(ThetaSaveErrorCode)code message:(NSString *)message underlying:(NSError *)underlying;
/** nil when the download is fine; a download error, or an HTTP one for an `NSHTTPURLResponse` outside 200-299. */
+ (NSError *)downloadFailureForResponse:(NSURLResponse *)response error:(NSError *)error;
/** `Documents/AudioNotes` (Saved Media), created if needed. */
+ (NSString *)savedMediaDirectory;
+ (BOOL)isSavedMediaPath:(NSString *)path;
/** Moves `path` into Saved Media as `name`, adding -2, -3... when the name exists. Returns the new path. */
+ (NSString *)moveIntoSavedMedia:(NSString *)path name:(NSString *)name error:(NSError **)error;
/** The one result toast for a finished save: success (Photos or Saved Media, from `path`) or the failure in `error`. */
+ (void)showSaveResultForPath:(NSString *)path error:(NSError *)error;
/** Failure toast for `error`; Photos access off links to Settings. */
+ (void)showSaveFailure:(NSError *)error;

#pragma mark - Utility Functions
+ (UIViewController *)nearestViewController:(UIView *)view;
+ (UIViewController *)topViewController;

#pragma mark - Settings Helpers
// Stores selected index for a segment setting with given title

#pragma mark - Constants
+ (UIColor *)iotaPinkColor;
+ (NSTimeInterval)cooldownPeriod;

@end 