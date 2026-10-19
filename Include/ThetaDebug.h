/**
 * Diagnostic logging, compiled in only by `./build.sh sideload debug` (THETA_DEBUG=1).
 * Release builds contain none of these calls, so their arguments are never evaluated.
 */
#ifndef ThetaDebug_h
#define ThetaDebug_h

#import <Foundation/Foundation.h>

#if THETA_DEBUG
#define THDebugLog(...) NSLog(__VA_ARGS__)
#else
#define THDebugLog(...) do { } while (0)
#endif

#endif
