/**
 * Cached reads of Theta's "<title>_Enabled" toggles.
 */
#ifndef ThetaSettings_h
#define ThetaSettings_h

#import <Foundation/Foundation.h>

/** Same result as -[NSUserDefaults boolForKey:@"<setting>_Enabled"] on the standard defaults (missing key = NO).
    Cached per setting; the whole cache is dropped on every NSUserDefaultsDidChangeNotification. Thread-safe. */
FOUNDATION_EXPORT BOOL ThetaSettingEnabled(NSString *setting);

#define ENABLED(setting) ThetaSettingEnabled(setting)

#endif
