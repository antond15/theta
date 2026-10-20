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
void ThetaHPKEMirrorKeychain(NSString *preferredGroup, NSString *wildcardGroup);
BOOL ThetaHPKEDictIsHPKE(CFDictionaryRef dict);
void ThetaHPKESave(CFDictionaryRef attributes);
void ThetaHPKESaveFromQueryAndAttrs(CFDictionaryRef query, CFDictionaryRef attrs);
OSStatus ThetaHPKECopyMatching(CFDictionaryRef query, CFTypeRef *result);

/* Sideload group standing in for one of Instagram's official app groups, or nil if `gid` is not
   official or this process is entitled to it. Same answer in the app and the NSE. */
NSString *ThetaSideloadGroupForOfficial(NSString *gid);
/* Remap NSUserDefaults suites named after official app groups onto their sideload groups. */
void ThetaInstallSuiteRemap(void);

#ifdef __cplusplus
}
#endif

#endif
