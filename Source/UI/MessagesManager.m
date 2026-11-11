#import "Include/MessagesManager.h"
#import "Include/CustomToastView.h"
#import "Include/ThetaHelper.h"

#import "Include/ThetaSettings.h"
#import "Include/ThetaDebug.h"

@implementation MessagesManager

NSString *const plistFileName = @"deleted_messages.plist";

// Image generation moved to ThetaHelper

// Toast functionality moved to ThetaHelper

// Haptic feedback moved to ThetaHelper

+ (instancetype)sharedManager {
    static MessagesManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (NSString *)plistPath {
    NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    return [documentsDirectory stringByAppendingPathComponent:plistFileName];
}

// The ids live in memory; every read and write of them, and the plist write, runs on one serial
// queue, so a cell configure on the main thread never waits for disk and the cache-update thread
// can't race it.
static dispatch_queue_t ThetaMessagesQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.theta.deleted-messages", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

static NSMutableDictionary *sThetaDeletedMessages;   // only touched on ThetaMessagesQueue()

- (NSMutableDictionary *)loadPlistData {
    NSMutableDictionary *data = [NSMutableDictionary dictionaryWithContentsOfFile:[self plistPath]];
    return data ?: [NSMutableDictionary dictionary];
}

- (void)savePlistData:(NSDictionary *)data {
    [data writeToFile:[self plistPath] atomically:YES];
}

// Call on the queue.
- (NSMutableDictionary *)storeLocked {
    if (!sThetaDeletedMessages) sThetaDeletedMessages = [self loadPlistData];
    return sThetaDeletedMessages;
}

- (void)saveDeletedMessageWithID:(NSString *)messageID {
    if (messageID.length == 0) {
        THDebugLog(@"[Theta] deleted messages: empty message id");
        return;
    }

    dispatch_async(ThetaMessagesQueue(), ^{
        NSMutableDictionary *store = [self storeLocked];
        store[messageID] = [[NSDate date] description];
        [self savePlistData:store];
    });

    if (ENABLED(THAppShowBanners)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [ThetaHelper showToastWithTitle:@"Someone deleted a message." subtitle:nil icon:[ThetaHelper imageFromEmojiString:@"🗑️" width:60] autoHide:4 openURL:nil];
        });
    }
}

- (BOOL)messageExistsWithID:(NSString *)messageID {
    return [self dateForDeletedMessageWithID:messageID] != nil;
}

- (NSString *)dateForDeletedMessageWithID:(NSString *)messageID {
    if (messageID.length == 0) return nil;
    __block NSString *date = nil;
    dispatch_sync(ThetaMessagesQueue(), ^{
        date = [self storeLocked][messageID];
    });
    return date;
}
@end
