/**
 * Diagnostic logging, compiled in only by `./build.sh sideload debug` (THETA_DEBUG=1).
 * Release builds contain none of these calls, so their arguments are never evaluated.
 */
#ifndef ThetaDebug_h
#define ThetaDebug_h

#import <Foundation/Foundation.h>

#if THETA_DEBUG
#import <os/log.h>
// One public string: NSLog would redact every %@ argument as <private> in the device log.
// Format outside os_log: clang 19 flags an argument-less literal format inside its expansion.
#define THDebugLog(fmt, ...) do { \
    NSString *_thDebugMsg = [NSString stringWithFormat:(fmt), ##__VA_ARGS__]; \
    os_log(OS_LOG_DEFAULT, "%{public}s", _thDebugMsg.UTF8String ?: ""); \
} while (0)
#else
#define THDebugLog(...) do { } while (0)
#endif

#endif
