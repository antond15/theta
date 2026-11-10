#import "Include/ThetaTweakCommon.h"
#import <objc/runtime.h>

// NSDateFormatter pattern for a THUIDateFormat option; nil keeps Instagram's own format.
static NSString *THDateFormatPattern(NSString *format, BOOL withTime) {
    if ([format isEqualToString:@"short"])    return @"MMM d";
    if ([format isEqualToString:@"medium"])   return @"MMM d, yyyy";
    if ([format isEqualToString:@"12h"])      return withTime ? @"MMM d 'at' h:mm a" : @"MMM d";
    if ([format isEqualToString:@"24h"])      return withTime ? @"MMM d 'at' HH:mm"  : @"MMM d";
    if ([format isEqualToString:@"iso"])      return @"yyyy-MM-dd";
    if ([format isEqualToString:@"iso_time"]) return withTime ? @"yyyy-MM-dd HH:mm"  : @"yyyy-MM-dd";
    return nil;
}

static NSString *THFormattedDate(NSDate *date) {
    NSString *pattern = THDateFormatPattern(ThetaSettingChoice(THUIDateFormat), YES);
    if (!pattern) return nil;
    static NSDateFormatter *df = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ df = [NSDateFormatter new]; });
    df.dateFormat = pattern;
    return [df stringFromDate:date];
}

// Hook: formattedDateInMixedFormat (feed post timestamps)
static NSString *(*orig_mixedFormat)(NSDate *, SEL);
static NSString *hook_mixedFormat(NSDate *self, SEL _cmd) {
    NSString *r = THFormattedDate(self);
    return r ?: orig_mixedFormat(self, _cmd);
}

// Hook: formattedDateRelativeToNow (notes, comments, stories)
static NSString *(*orig_relativeNow)(NSDate *, SEL);
static NSString *hook_relativeNow(NSDate *self, SEL _cmd) {
    NSString *r = THFormattedDate(self);
    return r ?: orig_relativeNow(self, _cmd);
}

// Hook: shortenedFormattedDateRelativeToNow
static NSString *(*orig_shortRelNow)(NSDate *, SEL);
static NSString *hook_shortRelNow(NSDate *self, SEL _cmd) {
    NSString *r = THFormattedDate(self);
    return r ?: orig_shortRelNow(self, _cmd);
}

// Hook: shortenedFormattedDateRelativeToNowHideSeconds: (DMs)
static NSString *(*orig_shortRelHideSeconds)(NSDate *, SEL, NSInteger);
static NSString *hook_shortRelHideSeconds(NSDate *self, SEL _cmd, NSInteger hideSeconds) {
    NSString *r = THFormattedDate(self);
    return r ?: orig_shortRelHideSeconds(self, _cmd, hideSeconds);
}

void THRegisterDateFormatHooks(void) {
    Class cls = [NSDate class];

    SEL mixed = sel_registerName("formattedDateInMixedFormat");
    if ([cls instancesRespondToSelector:mixed]) {
        NullHookMessageEx(cls, mixed, (void *)hook_mixedFormat, &orig_mixedFormat);
    }

    SEL rel = sel_registerName("formattedDateRelativeToNow");
    if ([cls instancesRespondToSelector:rel]) {
        NullHookMessageEx(cls, rel, (void *)hook_relativeNow, &orig_relativeNow);
    }

    SEL shortRel = sel_registerName("shortenedFormattedDateRelativeToNow");
    if ([cls instancesRespondToSelector:shortRel]) {
        NullHookMessageEx(cls, shortRel, (void *)hook_shortRelNow, &orig_shortRelNow);
    }

    SEL shortRelHs = sel_registerName("shortenedFormattedDateRelativeToNowHideSeconds:");
    if ([cls instancesRespondToSelector:shortRelHs]) {
        NullHookMessageEx(cls, shortRelHs, (void *)hook_shortRelHideSeconds, &orig_shortRelHideSeconds);
    }
}
