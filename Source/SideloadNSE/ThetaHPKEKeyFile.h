#ifndef THETA_HPKE_KEY_FILE_H
#define THETA_HPKE_KEY_FILE_H

#import <Foundation/Foundation.h>
#import <Security/Security.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef NSURL *(*ThetaHPKEContainerURLFn)(id self, SEL cmd, NSString *groupIdentifier);

void ThetaHPKESetContainerOrig(ThetaHPKEContainerURLFn fn);
void ThetaHPKEDumpStatus(void);
typedef OSStatus (*ThetaSecItemCopyMatchingFn)(CFDictionaryRef query, CFTypeRef *result);
typedef OSStatus (*ThetaSecItemUpdateFn)(CFDictionaryRef query, CFDictionaryRef attributes);

/* Instagram's HPKE notification keys are generic passwords under one service. The app mirrors
   them into ThetaHPKE/keys.plist in the shared app group, so the NSE can still decrypt when its
   keychain read fails. Every write below is meant to follow a successful keychain call. */
#define THETA_HPKE_SERVICE @"com.instagram.notifications.hpke"

/* Replace the file with the keychain's items, read with `copyMatching` (the real function, so
   the file fallback can't answer). Leaves the file alone if any read fails with a real error. */
void ThetaHPKEMirrorKeychain(ThetaSecItemCopyMatchingFn copyMatching, NSString *preferredGroup, NSString *wildcardGroup);
BOOL ThetaHPKEDictIsHPKE(CFDictionaryRef dict);
void ThetaHPKESave(CFDictionaryRef attributes);
void ThetaHPKESaveFromQueryAndAttrs(CFDictionaryRef query, CFDictionaryRef attrs);
void ThetaHPKESaveReadResult(CFDictionaryRef query, CFTypeRef result);
/* After SecItemDelete with `status`: drop the matching entries. */
void ThetaHPKEDelete(CFDictionaryRef query, OSStatus status);
OSStatus ThetaHPKECopyMatching(CFDictionaryRef query, CFTypeRef *result);

/* After SecItemAdd returned errSecDuplicateItem for `attributes` (already remapped): store the new
   value with `update` on the item's primary key and return its status. Returns errSecDuplicateItem
   unchanged for anything but a generic or internet password that carries data. */
OSStatus ThetaSecItemUpdateDuplicate(CFDictionaryRef attributes, ThetaSecItemUpdateFn update);

/* Sideload group standing in for one of Instagram's official app groups, or nil if `gid` is not
   official or this process is entitled to it. Same answer in the app and the NSE. */
NSString *ThetaSideloadGroupForOfficial(NSString *gid);
/* Remap NSUserDefaults suites named after official app groups onto their sideload groups. */
void ThetaInstallSuiteRemap(void);

/* Settings the app mirrors into the shared suite for the NSE, which can't read the app's defaults.
   The suite name is remapped like Instagram's own (ThetaInstallSuiteRemap). */
#define THETA_SHARED_SUITE @"group.com.burbn.instagram"
#define THETA_SHARED_MUTE_REEL_SHARES @"Theta_MuteSharedReelNotifications"

/* CFPreferences* replacements that apply the same group remap to their applicationID, for
   callers (Meta's caching defaults wrapper) that bypass NSUserDefaults. Resolve the real
   functions with ThetaCFPrefsResolveReal() before any slot is rebound to these. */
typedef struct {
    const char *name;
    void *real;
    void *replacement;
} ThetaCFPrefsHook;
void ThetaCFPrefsResolveReal(void);
const ThetaCFPrefsHook *ThetaCFPrefsHooks(size_t *count);

#ifdef __cplusplus
}
#endif

#endif
