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
#define THDebugLog(fmt, ...) os_log(OS_LOG_DEFAULT, "%{public}s", [NSString stringWithFormat:(fmt), ##__VA_ARGS__].UTF8String ?: "")
#else
#define THDebugLog(...) do { } while (0)
#endif

#endif
