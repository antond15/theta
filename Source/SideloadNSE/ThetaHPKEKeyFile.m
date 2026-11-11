#import "Source/SideloadNSE/ThetaHPKEKeyFile.h"
#import <stdarg.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <stdio.h>

static ThetaHPKEContainerURLFn gContainerOrig;
static NSURL *gStoreDir;
static BOOL gStoreResolved;

/* Diagnostics only exist in THETA_DEBUG builds (./build.sh sideload debug). */
#if THETA_DEBUG
static void ThetaHPKELog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void ThetaHPKELog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    fprintf(stderr, "[ThetaHPKE] %s\n", msg.UTF8String ?: "");
    fflush(stderr);
    os_log(os_log_create("com.theta.nse", "ThetaHPKE"), "%{public}s", msg.UTF8String ?: "");
}
#else
#define ThetaHPKELog(...) do { } while (0)
#endif

static BOOL ThetaHPKECanWrite(NSURL *url) {
    if (!url.path.length) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    if (![fm createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:&err]) {
        if (![fm fileExistsAtPath:url.path]) return NO;
    }
    NSString *probe = [url.path stringByAppendingPathComponent:@".theta_hpke_probe"];
    BOOL ok = [@"ok" writeToFile:probe atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    if (ok) [fm removeItemAtPath:probe error:NULL];
    return ok;
}

static NSString *ThetaHPKECString(CFDictionaryRef dict, CFStringRef key) {
    if (!dict) return nil;
    CFTypeRef v = CFDictionaryGetValue(dict, key);
    if (!v || CFGetTypeID(v) != CFStringGetTypeID()) return nil;
    return (__bridge NSString *)v;
}

BOOL ThetaHPKEDictIsHPKE(CFDictionaryRef dict) {
    if (!dict || CFGetTypeID(dict) != CFDictionaryGetTypeID()) return NO;
    return [ThetaHPKECString(dict, kSecAttrService) isEqualToString:THETA_HPKE_SERVICE];
}

void ThetaHPKESetContainerOrig(ThetaHPKEContainerURLFn fn) {
    gContainerOrig = fn;
    gStoreDir = nil;
    gStoreResolved = NO;
}

static NSArray<NSString *> *ThetaHPKEEntitledAppGroups(void) {
    typedef struct __SecTask *SecTaskRef;
    SecTaskRef (*create)(CFAllocatorRef) = (SecTaskRef (*)(CFAllocatorRef))dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
    CFTypeRef (*copyEnt)(SecTaskRef, CFStringRef, CFErrorRef *) =
        (CFTypeRef (*)(SecTaskRef, CFStringRef, CFErrorRef *))dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
    if (!create || !copyEnt) return @[];
    SecTaskRef task = create(NULL);
    if (!task) return @[];
    CFTypeRef raw = copyEnt(task, CFSTR("com.apple.security.application-groups"), NULL);
    CFRelease(task);
    NSArray *groups = @[];
    if (raw && CFGetTypeID(raw) == CFArrayGetTypeID())
        groups = [(__bridge NSArray *)raw copy];
    if (raw) CFRelease(raw);
    return groups ?: @[];
}

/* Re-signers rename the app groups (e.g. group.<hash>.1 … .5), so the app and the NSE no longer
   share group.com.burbn.instagram: each gets a private, empty stand-in. IG's NSE reads the
   logged-in accounts from that suite and hides the message text when it finds none. Map each
   official group, by position, onto the sorted sideload groups both binaries are entitled to. */
NSString *ThetaSideloadGroupForOfficial(NSString *gid) {
    static NSArray<NSString *> *official;
    static NSArray<NSString *> *entitled;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        official = @[ @"group.com.burbn.instagram", @"group.com.facebook.family", @"group.com.burbn.family" ];
    });
    if (![gid isKindOfClass:[NSString class]]) return nil;
    NSUInteger i = [official indexOfObject:gid];
    if (i == NSNotFound) return nil;
    NSArray<NSString *> *groups;
    @synchronized (official) {
        // Retried until the entitlement read succeeds rather than cached empty.
        if (!entitled.count)
            entitled = [ThetaHPKEEntitledAppGroups() sortedArrayUsingSelector:@selector(compare:)];
        groups = entitled;
    }
    if ([groups containsObject:gid] || i >= groups.count) return nil;
    return groups[i];
}

static CFStringRef ThetaMapPrefsApp(CFStringRef app) {
    if (!app || CFGetTypeID(app) != CFStringGetTypeID()) return app;
    NSString *mapped = ThetaSideloadGroupForOfficial((__bridge NSString *)app);
    return mapped ? (__bridge CFStringRef)mapped : app;
}

static CFPropertyListRef (*real_CFPreferencesCopyAppValue)(CFStringRef, CFStringRef);
static void (*real_CFPreferencesSetAppValue)(CFStringRef, CFPropertyListRef, CFStringRef);
static Boolean (*real_CFPreferencesGetAppBooleanValue)(CFStringRef, CFStringRef, Boolean *);
static CFIndex (*real_CFPreferencesGetAppIntegerValue)(CFStringRef, CFStringRef, Boolean *);
static CFDictionaryRef (*real_CFPreferencesCopyMultiple)(CFArrayRef, CFStringRef, CFStringRef, CFStringRef);
static void (*real_CFPreferencesSetMultiple)(CFDictionaryRef, CFArrayRef, CFStringRef, CFStringRef, CFStringRef);
static CFPropertyListRef (*real_CFPreferencesCopyValue)(CFStringRef, CFStringRef, CFStringRef, CFStringRef);
static void (*real_CFPreferencesSetValue)(CFStringRef, CFPropertyListRef, CFStringRef, CFStringRef, CFStringRef);
static Boolean (*real_CFPreferencesAppSynchronize)(CFStringRef);
static Boolean (*real_CFPreferencesSynchronize)(CFStringRef, CFStringRef, CFStringRef);
static CFArrayRef (*real_CFPreferencesCopyKeyList)(CFStringRef, CFStringRef, CFStringRef);

static CFPropertyListRef ThetaPrefsCopyAppValue(CFStringRef key, CFStringRef app) {
    return real_CFPreferencesCopyAppValue(key, ThetaMapPrefsApp(app));
}
static void ThetaPrefsSetAppValue(CFStringRef key, CFPropertyListRef value, CFStringRef app) {
    real_CFPreferencesSetAppValue(key, value, ThetaMapPrefsApp(app));
}
static Boolean ThetaPrefsGetAppBooleanValue(CFStringRef key, CFStringRef app, Boolean *valid) {
    return real_CFPreferencesGetAppBooleanValue(key, ThetaMapPrefsApp(app), valid);
}
static CFIndex ThetaPrefsGetAppIntegerValue(CFStringRef key, CFStringRef app, Boolean *valid) {
    return real_CFPreferencesGetAppIntegerValue(key, ThetaMapPrefsApp(app), valid);
}
static CFDictionaryRef ThetaPrefsCopyMultiple(CFArrayRef keys, CFStringRef app, CFStringRef user, CFStringRef host) {
    CFStringRef mapped = ThetaMapPrefsApp(app);
    CFDictionaryRef d = real_CFPreferencesCopyMultiple(keys, mapped, user, host);
    if (mapped != app)
        ThetaHPKELog(@"CFPreferencesCopyMultiple %@ -> %@ got=%ld", app, mapped, d ? (long)CFDictionaryGetCount(d) : 0L);
    return d;
}
static void ThetaPrefsSetMultiple(CFDictionaryRef set, CFArrayRef remove, CFStringRef app, CFStringRef user, CFStringRef host) {
    real_CFPreferencesSetMultiple(set, remove, ThetaMapPrefsApp(app), user, host);
}
static CFPropertyListRef ThetaPrefsCopyValue(CFStringRef key, CFStringRef app, CFStringRef user, CFStringRef host) {
    return real_CFPreferencesCopyValue(key, ThetaMapPrefsApp(app), user, host);
}
static void ThetaPrefsSetValue(CFStringRef key, CFPropertyListRef value, CFStringRef app, CFStringRef user, CFStringRef host) {
    real_CFPreferencesSetValue(key, value, ThetaMapPrefsApp(app), user, host);
}
static Boolean ThetaPrefsAppSynchronize(CFStringRef app) {
    return real_CFPreferencesAppSynchronize(ThetaMapPrefsApp(app));
}
static Boolean ThetaPrefsSynchronize(CFStringRef app, CFStringRef user, CFStringRef host) {
    return real_CFPreferencesSynchronize(ThetaMapPrefsApp(app), user, host);
}
static CFArrayRef ThetaPrefsCopyKeyList(CFStringRef app, CFStringRef user, CFStringRef host) {
    return real_CFPreferencesCopyKeyList(ThetaMapPrefsApp(app), user, host);
}

static ThetaCFPrefsHook gCFPrefsHooks[] = {
    { "CFPreferencesCopyAppValue", NULL, (void *)ThetaPrefsCopyAppValue },
    { "CFPreferencesSetAppValue", NULL, (void *)ThetaPrefsSetAppValue },
    { "CFPreferencesGetAppBooleanValue", NULL, (void *)ThetaPrefsGetAppBooleanValue },
    { "CFPreferencesGetAppIntegerValue", NULL, (void *)ThetaPrefsGetAppIntegerValue },
    { "CFPreferencesCopyMultiple", NULL, (void *)ThetaPrefsCopyMultiple },
    { "CFPreferencesSetMultiple", NULL, (void *)ThetaPrefsSetMultiple },
    { "CFPreferencesCopyValue", NULL, (void *)ThetaPrefsCopyValue },
    { "CFPreferencesSetValue", NULL, (void *)ThetaPrefsSetValue },
    { "CFPreferencesAppSynchronize", NULL, (void *)ThetaPrefsAppSynchronize },
    { "CFPreferencesSynchronize", NULL, (void *)ThetaPrefsSynchronize },
    { "CFPreferencesCopyKeyList", NULL, (void *)ThetaPrefsCopyKeyList },
};

void ThetaCFPrefsResolveReal(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void **reals[] = {
            (void **)&real_CFPreferencesCopyAppValue, (void **)&real_CFPreferencesSetAppValue,
            (void **)&real_CFPreferencesGetAppBooleanValue, (void **)&real_CFPreferencesGetAppIntegerValue,
            (void **)&real_CFPreferencesCopyMultiple, (void **)&real_CFPreferencesSetMultiple,
            (void **)&real_CFPreferencesCopyValue, (void **)&real_CFPreferencesSetValue,
            (void **)&real_CFPreferencesAppSynchronize, (void **)&real_CFPreferencesSynchronize,
            (void **)&real_CFPreferencesCopyKeyList,
        };
        for (size_t i = 0; i < sizeof(gCFPrefsHooks) / sizeof(gCFPrefsHooks[0]); i++) {
            gCFPrefsHooks[i].real = dlsym(RTLD_DEFAULT, gCFPrefsHooks[i].name);
            *reals[i] = gCFPrefsHooks[i].real;
        }
    });
}

const ThetaCFPrefsHook *ThetaCFPrefsHooks(size_t *count) {
    ThetaCFPrefsResolveReal();
    if (count) *count = sizeof(gCFPrefsHooks) / sizeof(gCFPrefsHooks[0]);
    return gCFPrefsHooks;
}

static id (*gOrigInitWithSuiteName)(id, SEL, NSString *);

static id ThetaHookInitWithSuiteName(id self, SEL _cmd, NSString *suite) {
    NSString *mapped = ThetaSideloadGroupForOfficial(suite);
    if (mapped) ThetaHPKELog(@"suite %@ -> %@", suite, mapped);
    return gOrigInitWithSuiteName(self, _cmd, mapped ?: suite);
}

void ThetaInstallSuiteRemap(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method m = class_getInstanceMethod([NSUserDefaults class], @selector(initWithSuiteName:));
        if (!m) return;
        // Save the original before publishing the hook so a concurrent init never sees NULL.
        gOrigInitWithSuiteName = (id (*)(id, SEL, NSString *))method_getImplementation(m);
        method_setImplementation(m, (IMP)ThetaHookInitWithSuiteName);
        ThetaHPKELog(@"suite remap group.com.burbn.instagram -> %@",
                     ThetaSideloadGroupForOfficial(@"group.com.burbn.instagram") ?: @"(none)");
    });
}

static NSURL *ThetaHPKETryGroup(id fm, SEL sel, NSString *gid) {
    if (!gid.length) return nil;
    NSURL *root = nil;
    if (gContainerOrig) {
        root = gContainerOrig(fm, sel, gid);
    } else {
        root = [fm containerURLForSecurityApplicationGroupIdentifier:gid];
    }
    if (!root) return nil;
    NSURL *dir = [root URLByAppendingPathComponent:@"Library/Application Support/ThetaHPKE" isDirectory:YES];
    if (!ThetaHPKECanWrite(dir)) {
        ThetaHPKELog(@"group %@ not writable %@", gid, dir.path);
        return nil;
    }
    return dir;
}

/* Not cached while no container is writable (before the first unlock), so a long-lived NSE
   process finds it once the phone is unlocked. */
static NSURL *ThetaHPKESharedDirectory(void) {
    if (gStoreResolved) return gStoreDir;
    id fm = [NSFileManager defaultManager];
    SEL sel = @selector(containerURLForSecurityApplicationGroupIdentifier:);

    NSArray<NSString *> *official = @[
        @"group.com.burbn.instagram",
        @"group.com.burbn.family",
        @"group.com.facebook.family",
    ];
    for (NSString *gid in official) {
        NSURL *dir = ThetaHPKETryGroup(fm, sel, gid);
        if (dir) {
            gStoreDir = dir;
            gStoreResolved = YES;
            ThetaHPKELog(@"shared store %@", dir.path);
            return gStoreDir;
        }
    }

    NSArray<NSString *> *entitled = [[ThetaHPKEEntitledAppGroups() sortedArrayUsingSelector:@selector(compare:)] copy];
    ThetaHPKELog(@"official app-groups nil; entitled (%lu): %@", (unsigned long)entitled.count, entitled);
    for (NSString *gid in entitled) {
        if (![gid isKindOfClass:[NSString class]]) continue;
        NSURL *dir = ThetaHPKETryGroup(fm, sel, gid);
        if (dir) {
            gStoreDir = dir;
            gStoreResolved = YES;
            ThetaHPKELog(@"shared store %@ (sideload group %@)", dir.path, gid);
            return gStoreDir;
        }
    }
    ThetaHPKELog(@"no writable app-group container — HPKE file fallback unavailable");
    return nil;
}

/* keys.plist: { <account, or "" without one> : { "data": NSData, "generic": NSData (optional) } }
   for THETA_HPKE_SERVICE. Up to 2026-11 every key had a hash-named file plus a service-named
   alias; ThetaHPKEMigrateLegacyFiles folds those in once. */
static NSString *const kThetaHPKEStoreFile = @"keys.plist";
/* settings.plist, next to keys.plist: the Theta settings the NSE needs, written by the app. On 451
   the NSE always read the shared NSUserDefaults suite as off although the app mirrored the toggle
   there; this directory already carries the HPKE keys from the app to the NSE. */
static NSString *const kThetaSharedSettingsFile = @"settings.plist";

static NSObject *ThetaHPKELock(void) {
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    return lock;
}

static NSData *ThetaHPKECData(CFDictionaryRef dict, CFStringRef key) {
    if (!dict) return nil;
    CFTypeRef v = CFDictionaryGetValue(dict, key);
    if (!v || CFGetTypeID(v) != CFDataGetTypeID()) return nil;
    return (__bridge NSData *)v;
}

static NSDictionary *ThetaHPKEItem(NSData *data, NSData *generic) {
    if (![data isKindOfClass:[NSData class]]) return nil;
    if (![generic isKindOfClass:[NSData class]]) return @{ @"data" : data };
    return @{ @"data" : data, @"generic" : generic };
}

static BOOL ThetaHPKEIsMissingFile(NSError *err) {
    return [err.domain isEqualToString:NSCocoaErrorDomain] && err.code == NSFileReadNoSuchFileError;
}

/* The items in the file, empty if there is none, or nil if it exists but can't be read (before
   the first unlock), so a write never replaces keys it couldn't see. */
static NSMutableDictionary *ThetaHPKELoadItems(NSURL *dir) {
    NSError *err = nil;
    NSData *raw = [NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:kThetaHPKEStoreFile]
                                        options:0
                                          error:&err];
    if (!raw) {
        if (ThetaHPKEIsMissingFile(err)) return [NSMutableDictionary dictionary];
        ThetaHPKELog(@"key file unreadable: %@", err);
        return nil;
    }
    id plist = [NSPropertyListSerialization propertyListWithData:raw
                                                          options:NSPropertyListImmutable
                                                           format:NULL
                                                            error:NULL];
    NSMutableDictionary *items = [NSMutableDictionary dictionary];
    if (![plist isKindOfClass:[NSDictionary class]]) return items;
    [(NSDictionary *)plist enumerateKeysAndObjectsUsingBlock:^(id account, id item, __unused BOOL *stop) {
        if (![account isKindOfClass:[NSString class]] || ![item isKindOfClass:[NSDictionary class]]) return;
        NSDictionary *clean = ThetaHPKEItem(item[@"data"], item[@"generic"]);
        if (clean) items[account] = clean;
    }];
    return items;
}

static BOOL ThetaHPKEWriteItems(NSURL *dir, NSDictionary *items) {
    NSURL *url = [dir URLByAppendingPathComponent:kThetaHPKEStoreFile];
    NSError *err = nil;
    if (!items.count) {
        BOOL ok = [[NSFileManager defaultManager] removeItemAtURL:url error:&err] ||
                  ([err.domain isEqualToString:NSCocoaErrorDomain] && err.code == NSFileNoSuchFileError);
        ThetaHPKELog(@"key file removed ok=%d", ok);
        return ok;
    }
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:items
                                                               format:NSPropertyListBinaryFormat_v1_0
                                                              options:0
                                                                error:&err];
    // The NSE reads the key while the phone is locked, so not NSFileProtectionComplete.
    BOOL ok = plist && [plist writeToURL:url
                                 options:NSDataWritingAtomic | NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication
                                   error:&err];
    ThetaHPKELog(@"key file written items=%lu ok=%d err=%@", (unsigned long)items.count, ok, err);
    return ok;
}

/* Fold the pre-2026-11 per-item and alias files into keys.plist, then delete them (all of them:
   the old "notif" match also stored unrelated items there). Retried until it succeeds. */
static void ThetaHPKEMigrateLegacyFiles(NSURL *dir) {
    static BOOL done;
    if (done) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSURL *> *files = [fm contentsOfDirectoryAtURL:dir
                                includingPropertiesForKeys:nil
                                                   options:NSDirectoryEnumerationSkipsHiddenFiles
                                                     error:NULL];
    NSMutableArray<NSURL *> *legacy = [NSMutableArray array];
    NSMutableDictionary *found = [NSMutableDictionary dictionary];
    for (NSURL *file in files) {
        if (![file.pathExtension isEqualToString:@"plist"] ||
            [file.lastPathComponent isEqualToString:kThetaHPKEStoreFile] ||
            [file.lastPathComponent isEqualToString:kThetaSharedSettingsFile]) continue;
        NSData *raw = [NSData dataWithContentsOfURL:file options:0 error:NULL];
        if (!raw) return; // locked: try again on the next store access
        [legacy addObject:file];
        id stored = [NSPropertyListSerialization propertyListWithData:raw options:NSPropertyListImmutable format:NULL error:NULL];
        if (![stored isKindOfClass:[NSDictionary class]] ||
            ![stored[@"service"] isEqual:THETA_HPKE_SERVICE]) continue;
        NSDictionary *item = ThetaHPKEItem(stored[@"data"], stored[@"generic"]);
        NSString *account = [stored[@"account"] isKindOfClass:[NSString class]] ? stored[@"account"] : @"";
        if (item && !found[account]) found[account] = item;
    }
    if (legacy.count) {
        NSMutableDictionary *items = ThetaHPKELoadItems(dir);
        if (!items) return;
        BOOL changed = NO;
        for (NSString *account in found) {
            if (items[account]) continue;
            items[account] = found[account];
            changed = YES;
        }
        if (changed && !ThetaHPKEWriteItems(dir, items)) return;
        for (NSURL *file in legacy) [fm removeItemAtURL:file error:NULL];
        ThetaHPKELog(@"migrated %lu legacy files, %lu keys", (unsigned long)legacy.count, (unsigned long)found.count);
    }
    done = YES;
}

/* Load the items, apply `change`, and write the file only if they differ. */
static void ThetaHPKEChangeItems(void (^change)(NSMutableDictionary *items)) {
    @synchronized (ThetaHPKELock()) {
        NSURL *dir = ThetaHPKESharedDirectory();
        if (!dir) return;
        ThetaHPKEMigrateLegacyFiles(dir);
        NSMutableDictionary *items = ThetaHPKELoadItems(dir);
        if (!items) return;
        NSDictionary *before = [items copy];
        change(items);
        if (![items isEqualToDictionary:before]) ThetaHPKEWriteItems(dir, items);
    }
}


/* The stored settings, empty if there is no file, or nil if it exists but can't be read. */
static NSDictionary *ThetaSharedSettingsLoad(NSURL *dir) {
    NSError *err = nil;
    NSData *raw = [NSData dataWithContentsOfURL:[dir URLByAppendingPathComponent:kThetaSharedSettingsFile]
                                        options:0
                                          error:&err];
    if (!raw) return ThetaHPKEIsMissingFile(err) ? @{} : nil;
    id plist = [NSPropertyListSerialization propertyListWithData:raw options:NSPropertyListImmutable format:NULL error:NULL];
    return [plist isKindOfClass:[NSDictionary class]] ? plist : @{};
}

void ThetaSharedSettingSetBool(NSString *key, BOOL value) {
    if (!key.length) return;
    @synchronized (ThetaHPKELock()) {
        NSURL *dir = ThetaHPKESharedDirectory();
        NSDictionary *current = dir ? ThetaSharedSettingsLoad(dir) : nil;
        if (!current) {
            ThetaHPKELog(@"shared setting %@=%d not written (no readable store)", key, value);
            return;
        }
        id stored = current[key];
        if ([stored isKindOfClass:[NSNumber class]] && [stored boolValue] == value) return;
        NSMutableDictionary *next = [current mutableCopy];
        next[key] = @(value);
        NSError *err = nil;
        NSData *plist = [NSPropertyListSerialization dataWithPropertyList:next
                                                                   format:NSPropertyListBinaryFormat_v1_0
                                                                  options:0
                                                                    error:&err];
        // Read while the phone is locked, like the keys.
        BOOL ok = plist && [plist writeToURL:[dir URLByAppendingPathComponent:kThetaSharedSettingsFile]
                                     options:NSDataWritingAtomic | NSDataWritingFileProtectionCompleteUntilFirstUserAuthentication
                                       error:&err];
        ThetaHPKELog(@"shared setting %@=%d written ok=%d err=%@", key, value, ok, err);
        (void)ok;
    }
}

BOOL ThetaSharedSettingBool(NSString *key, BOOL *found) {
    if (found) *found = NO;
    if (!key.length) return NO;
    NSDictionary *settings = nil;
    @synchronized (ThetaHPKELock()) {
        NSURL *dir = ThetaHPKESharedDirectory();
        settings = dir ? ThetaSharedSettingsLoad(dir) : nil;
    }
    id value = settings[key];
    if (![value isKindOfClass:[NSNumber class]]) return NO;
    if (found) *found = YES;
    return [value boolValue];
}

void ThetaHPKEDumpStatus(void) {
    @synchronized (ThetaHPKELock()) {
        gStoreResolved = NO;
        gStoreDir = nil;
        NSURL *dir = ThetaHPKESharedDirectory();
        if (dir) ThetaHPKEMigrateLegacyFiles(dir);
    }
}

void ThetaHPKEMirrorKeychain(ThetaSecItemCopyMatchingFn copyMatching, NSString *preferredGroup, NSString *wildcardGroup) {
    if (!copyMatching) copyMatching = SecItemCopyMatching;
    NSMutableArray *groups = [NSMutableArray arrayWithObject:[NSNull null]];
    if (preferredGroup.length) [groups addObject:preferredGroup];
    if (wildcardGroup.length && ![wildcardGroup isEqualToString:preferredGroup])
        [groups addObject:wildcardGroup];
    NSMutableDictionary *found = [NSMutableDictionary dictionary];
    BOOL clean = YES;
    for (id group in groups) {
        NSMutableDictionary *query = [@{
            (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService : THETA_HPKE_SERVICE,
            (__bridge id)kSecReturnData : @YES,
            (__bridge id)kSecReturnAttributes : @YES,
            (__bridge id)kSecMatchLimit : (__bridge id)kSecMatchLimitAll,
        } mutableCopy];
        if (group != [NSNull null])
            query[(__bridge id)kSecAttrAccessGroup] = group;
        CFTypeRef result = NULL;
        OSStatus st = copyMatching((__bridge CFDictionaryRef)query, &result);
        if (st == errSecSuccess && result) {
            NSArray *items = CFGetTypeID(result) == CFArrayGetTypeID()
                ? (__bridge NSArray *)result
                : @[ (__bridge id)result ];
            for (NSDictionary *item in items) {
                if (![item isKindOfClass:[NSDictionary class]]) continue;
                NSDictionary *entry = ThetaHPKEItem(item[(__bridge id)kSecValueData], item[(__bridge id)kSecAttrGeneric]);
                id account = item[(__bridge id)kSecAttrAccount];
                NSString *key = [account isKindOfClass:[NSString class]] ? account : @"";
                if (entry && !found[key]) found[key] = entry;
            }
        } else if (st != errSecItemNotFound) {
            clean = NO;
        }
        if (result) CFRelease(result);
        ThetaHPKELog(@"mirror group=%@ st=%d", group == [NSNull null] ? @"(default)" : group, (int)st);
    }
    // With a clean read the keychain is the truth: keys it no longer has leave the file too.
    ThetaHPKEChangeItems(^(NSMutableDictionary *items) {
        if (clean) [items setDictionary:found];
        else [items addEntriesFromDictionary:found];
    });
    ThetaHPKELog(@"mirror done found=%lu clean=%d store=%@", (unsigned long)found.count, clean, gStoreDir.path ?: @"(none)");
}

void ThetaHPKESave(CFDictionaryRef attributes) {
    if (!ThetaHPKEDictIsHPKE(attributes)) return;
    NSDictionary *item = ThetaHPKEItem(ThetaHPKECData(attributes, kSecValueData),
                                       ThetaHPKECData(attributes, kSecAttrGeneric));
    if (!item) return;
    NSString *account = ThetaHPKECString(attributes, kSecAttrAccount) ?: @"";
    ThetaHPKEChangeItems(^(NSMutableDictionary *items) { items[account] = item; });
}

void ThetaHPKESaveFromQueryAndAttrs(CFDictionaryRef query, CFDictionaryRef attrs) {
    if (!ThetaHPKEDictIsHPKE(query) || !attrs) return;
    NSString *account = ThetaHPKECString(query, kSecAttrAccount);
    NSString *renamed = ThetaHPKECString(attrs, kSecAttrAccount);
    NSData *data = ThetaHPKECData(attrs, kSecValueData);
    NSData *generic = ThetaHPKECData(attrs, kSecAttrGeneric);
    if (!data && !generic && !renamed) return;
    ThetaHPKEChangeItems(^(NSMutableDictionary *items) {
        NSArray *matching = account ? (items[account] ? @[ account ] : @[]) : items.allKeys;
        for (NSString *key in matching) {
            NSDictionary *old = items[key];
            NSDictionary *item = ThetaHPKEItem(data ?: old[@"data"], generic ?: old[@"generic"]);
            [items removeObjectForKey:key];
            items[renamed ?: key] = item;
        }
        // Not in the file yet: only an update that carries the key itself creates an entry.
        if (!matching.count && account && data)
            items[renamed ?: account] = ThetaHPKEItem(data, generic);
    });
}

void ThetaHPKESaveReadResult(CFDictionaryRef query, CFTypeRef result) {
    if (!result || !ThetaHPKEDictIsHPKE(query)) return;
    NSString *queried = ThetaHPKECString(query, kSecAttrAccount);
    NSMutableDictionary *full = [NSMutableDictionary dictionary];      // read with attributes
    NSMutableDictionary *dataOnly = [NSMutableDictionary dictionary];  // generic not returned
    NSArray *results = CFGetTypeID(result) == CFArrayGetTypeID()
        ? (__bridge NSArray *)result
        : @[ (__bridge id)result ];
    for (id r in results) {
        if ([r isKindOfClass:[NSData class]]) {
            // A bare value only says which item it is when the query named the account.
            if (queried && results.count == 1) dataOnly[queried] = r;
        } else if ([r isKindOfClass:[NSDictionary class]]) {
            NSDictionary *item = ThetaHPKEItem(r[(__bridge id)kSecValueData], r[(__bridge id)kSecAttrGeneric]);
            id account = r[(__bridge id)kSecAttrAccount] ?: queried;
            if (item) full[[account isKindOfClass:[NSString class]] ? account : @""] = item;
        }
    }
    if (!full.count && !dataOnly.count) return;
    ThetaHPKEChangeItems(^(NSMutableDictionary *items) {
        [items addEntriesFromDictionary:full];
        for (NSString *account in dataOnly)
            items[account] = ThetaHPKEItem(dataOnly[account], items[account][@"generic"]);
    });
}

void ThetaHPKEDelete(CFDictionaryRef query, OSStatus status) {
    if (!ThetaHPKEDictIsHPKE(query)) return;
    NSString *account = ThetaHPKECString(query, kSecAttrAccount);
    // Not found in the keychain means a stale entry, but only an account says which one.
    if (status != errSecSuccess && !(status == errSecItemNotFound && account)) return;
    ThetaHPKEChangeItems(^(NSMutableDictionary *items) {
        if (account) [items removeObjectForKey:account];
        else [items removeAllObjects];
    });
}

static BOOL ThetaHPKEQueryFlag(CFDictionaryRef query, CFStringRef key) {
    CFTypeRef v = CFDictionaryGetValue(query, key);
    if (!v) return NO;
    if (CFGetTypeID(v) == CFBooleanGetTypeID()) return CFBooleanGetValue((CFBooleanRef)v);
    if (CFGetTypeID(v) == CFNumberGetTypeID()) return [(__bridge NSNumber *)v boolValue];
    return NO;
}

/* Answer a query the keychain couldn't, in the shape the keychain would: one item, or an array
   when kSecMatchLimit is kSecMatchLimitAll or a count. */
OSStatus ThetaHPKECopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    if (!ThetaHPKEDictIsHPKE(query)) return errSecItemNotFound;
    NSDictionary *items = nil;
    @synchronized (ThetaHPKELock()) {
        NSURL *dir = ThetaHPKESharedDirectory();
        if (dir) {
            ThetaHPKEMigrateLegacyFiles(dir);
            items = ThetaHPKELoadItems(dir);
        }
    }
    NSString *account = ThetaHPKECString(query, kSecAttrAccount);
    NSArray *keys = account ? (items[account] ? @[ account ] : @[])
                            : [items.allKeys sortedArrayUsingSelector:@selector(compare:)];
    if (!keys.count) return errSecItemNotFound;

    CFTypeRef limit = CFDictionaryGetValue(query, kSecMatchLimit);
    BOOL asArray = NO;
    NSUInteger max = 1;
    if (limit && CFEqual(limit, kSecMatchLimitAll)) {
        asArray = YES;
        max = NSUIntegerMax;
    } else if (limit && CFGetTypeID(limit) == CFNumberGetTypeID()) {
        asArray = YES;
        max = MAX([(__bridge NSNumber *)limit unsignedIntegerValue], (NSUInteger)1);
    }
    BOOL wantData = ThetaHPKEQueryFlag(query, kSecReturnData);
    BOOL wantAttrs = ThetaHPKEQueryFlag(query, kSecReturnAttributes);
    if (!wantData && !wantAttrs) wantData = YES;

    NSMutableArray *out = [NSMutableArray array];
    for (NSString *key in keys) {
        if (out.count >= max) break;
        NSDictionary *item = items[key];
        if (wantData && !wantAttrs) {
            [out addObject:item[@"data"]];
            continue;
        }
        NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
        attrs[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
        attrs[(__bridge id)kSecAttrService] = THETA_HPKE_SERVICE;
        if (key.length) attrs[(__bridge id)kSecAttrAccount] = key;
        if (item[@"generic"]) attrs[(__bridge id)kSecAttrGeneric] = item[@"generic"];
        if (wantData) attrs[(__bridge id)kSecValueData] = item[@"data"];
        [out addObject:attrs];
    }
    if (result) *result = CFBridgingRetain(asArray ? [out copy] : out.firstObject);
    ThetaHPKELog(@"loaded %lu of %lu keys from file", (unsigned long)out.count, (unsigned long)items.count);
    return errSecSuccess;
}

OSStatus ThetaSecItemUpdateDuplicate(CFDictionaryRef attributes, ThetaSecItemUpdateFn update) {
    if (!update || !attributes || CFGetTypeID(attributes) != CFDictionaryGetTypeID()) return errSecDuplicateItem;
    CFTypeRef cls = CFDictionaryGetValue(attributes, kSecClass);
    if (!cls || !(CFEqual(cls, kSecClassGenericPassword) || CFEqual(cls, kSecClassInternetPassword)))
        return errSecDuplicateItem;
    if (!ThetaHPKECData(attributes, kSecValueData)) return errSecDuplicateItem;

    // The password classes' primary key (what made the add a duplicate), and the values to store.
    const CFStringRef queryKeys[] = {
        kSecClass, kSecAttrAccessGroup, kSecAttrSynchronizable, kSecAttrService, kSecAttrAccount,
        kSecAttrServer, kSecAttrProtocol, kSecAttrPort, kSecAttrPath, kSecAttrSecurityDomain,
        kSecAttrAuthenticationType,
    };
    const CFStringRef updateKeys[] = {
        kSecValueData, kSecAttrGeneric, kSecAttrLabel, kSecAttrComment, kSecAttrDescription,
        kSecAttrType, kSecAttrCreator, kSecAttrIsInvisible, kSecAttrIsNegative, kSecAttrAccessible,
    };
    NSDictionary *added = (__bridge NSDictionary *)attributes;
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (size_t i = 0; i < sizeof(queryKeys) / sizeof(queryKeys[0]); i++) {
        id v = added[(__bridge id)queryKeys[i]];
        if (v) query[(__bridge id)queryKeys[i]] = v;
    }
    for (size_t i = 0; i < sizeof(updateKeys) / sizeof(updateKeys[0]); i++) {
        id v = added[(__bridge id)updateKeys[i]];
        if (v) values[(__bridge id)updateKeys[i]] = v;
    }
    OSStatus st = update((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)values);
    ThetaHPKELog(@"duplicate add of %@ updated st=%d", added[(__bridge id)kSecAttrService], (int)st);
    return st;
}
