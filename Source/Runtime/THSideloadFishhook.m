/* Sideload fishhook rebindings (strlen / SecItem*) */
#import "Source/SideloadNSE/ThetaHPKEKeyFile.h"

// Keychain hook via fishhook (file scope)
static OSStatus (*original_SecItemCopyMatching)(CFDictionaryRef query, CFTypeRef *result);
static OSStatus (*original_SecItemAdd)(CFDictionaryRef attributes, CFTypeRef *result);
static OSStatus (*original_SecItemUpdate)(CFDictionaryRef query, CFDictionaryRef attributesToUpdate);
static OSStatus (*original_SecItemDelete)(CFDictionaryRef query);
#define kErrSecItemNotFoundKeychain ((OSStatus)-25300)

// Real SecItem* resolved once before we rebind (dlsym after rebind would return our hook).
static OSStatus (*real_SecItemCopyMatching)(CFDictionaryRef query, CFTypeRef *result) = NULL;
static OSStatus (*real_SecItemAdd)(CFDictionaryRef attributes, CFTypeRef *result) = NULL;
static OSStatus (*real_SecItemUpdate)(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) = NULL;
static OSStatus (*real_SecItemDelete)(CFDictionaryRef query) = NULL;

// Instagram writes tokens with Meta's team-id access group. Sideload signing
// uses a different team, so those writes used to fail; faking success left
// the next cold launch with no session. Rewrite onto the sideload group.
static BOOL SideloadShouldSkipAccessGroup(CFStringRef group) {
    if (!group || CFGetTypeID(group) != CFStringGetTypeID()) return YES;
    if (CFStringHasPrefix(group, CFSTR("com.apple."))) return YES;
    if (keychainAccessGroup.length &&
        CFStringCompare(group, (__bridge CFStringRef)keychainAccessGroup, 0) == kCFCompareEqualTo) {
        return YES;
    }
    return NO;
}

// Returns a +1 copy the caller must CFRelease, or NULL to use `dict` unchanged.
static CFDictionaryRef SideloadSecItemDictCopy(CFDictionaryRef dict, BOOL isQuery) {
    if (!dict || CFGetTypeID(dict) != CFDictionaryGetTypeID()) return NULL;
    if (!keychainAccessGroup.length) return NULL;

    CFTypeRef ag = CFDictionaryGetValue(dict, kSecAttrAccessGroup);
    BOOL rewriteGroup = (ag != NULL) && !SideloadShouldSkipAccessGroup((CFStringRef)ag);
    BOOL hasSync = CFDictionaryContainsKey(dict, kSecAttrSynchronizable);
    if (!rewriteGroup && !hasSync) return NULL;

    CFMutableDictionaryRef copy = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, dict);
    if (!copy) return NULL;
    if (rewriteGroup) {
        CFDictionarySetValue(copy, kSecAttrAccessGroup, (__bridge CFStringRef)keychainAccessGroup);
    }
    if (hasSync) {
        if (isQuery) {
            CFDictionarySetValue(copy, kSecAttrSynchronizable, kSecAttrSynchronizableAny);
        } else {
            CFDictionarySetValue(copy, kSecAttrSynchronizable, kCFBooleanFalse);
        }
    }
    return copy;
}

static OSStatus hooked_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    if (!real_SecItemCopyMatching) {
        if (result) *result = NULL;
        return kErrSecItemNotFoundKeychain;
    }
    CFDictionaryRef rewritten = SideloadSecItemDictCopy(query, YES);
    OSStatus status = real_SecItemCopyMatching(rewritten ? rewritten : query, result);
    if (rewritten) CFRelease(rewritten);
    if (status == errSecSuccess && result && *result && ThetaHPKEDictIsHPKE(query)) {
        if (CFGetTypeID(*result) == CFDataGetTypeID()) {
            NSMutableDictionary *attrs = [NSMutableDictionary dictionaryWithDictionary:(__bridge NSDictionary *)query];
            attrs[(__bridge id)kSecValueData] = (__bridge NSData *)*result;
            ThetaHPKESave((__bridge CFDictionaryRef)attrs);
        } else if (CFGetTypeID(*result) == CFDictionaryGetTypeID()) {
            ThetaHPKESaveFromQueryAndAttrs(query, (CFDictionaryRef)*result);
        }
        return status;
    }
    if (status != errSecSuccess && ThetaHPKEDictIsHPKE(query)) {
        OSStatus fileSt = ThetaHPKECopyMatching(query, result);
        if (fileSt == errSecSuccess) return fileSt;
    }
    return status;
}

// Guard strlen(NULL) in IGDeviceReportWithEssentialInfo on sideload.
// Never rebind both strlen and _platform_strlen into the same orig pointer — fishhook
// can overwrite orig with our hook and recurse until the stack blows.
static size_t (*original_strlen_fn)(const char *) = NULL;
static size_t safe_strlen_impl(const char *s) {
    if (!s) return 0;
    size_t (*fn)(const char *) = original_strlen_fn;
    if (fn && fn != safe_strlen_impl) return fn(s);
    const char *p = s;
    while (*p) p++;
    return (size_t)(p - s);
}

// IGDeviceReportWithEssentialInfo and everything it calls live in FBSharedFramework (IG 451), so only
// that image's strlen import is rebound, not every loaded image's.
static void theta_rebindStrlenInFBShared(const struct mach_header *header, intptr_t slide) {
    Dl_info info;
    if (!dladdr(header, &info) || !info.dli_fname) return;
    if (!strstr(info.dli_fname, "/FBSharedFramework.framework/FBSharedFramework")) return;
    struct rebinding rebindings[] = {
        { "strlen", (void *)safe_strlen_impl, (void **)&original_strlen_fn },
    };
    if (rebind_symbols_image((void *)header, slide, rebindings, 1) == 0) {
        THDebugLog(@"[Theta] strlen guard installed in %s", info.dli_fname);
    }
}

static OSStatus hooked_SecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    if (!real_SecItemAdd) return -25243; // errSecUnimplemented
    CFDictionaryRef rewritten = SideloadSecItemDictCopy(attributes, NO);
    OSStatus status = real_SecItemAdd(rewritten ? rewritten : attributes, result);
    if (rewritten) CFRelease(rewritten);
    ThetaHPKESave(attributes);
    // Item already in the sideload keychain — that *is* persistence.
    if (status == errSecDuplicateItem) return errSecSuccess;
    if (status != errSecSuccess) {
        fprintf(stderr, "[Theta] SecItemAdd failed status=%d (session may not persist)\n", (int)status);
        fflush(stderr);
    }
    return status;
}

static OSStatus hooked_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    if (!real_SecItemUpdate) return -25243;
    CFDictionaryRef q = SideloadSecItemDictCopy(query, YES);
    CFDictionaryRef a = SideloadSecItemDictCopy(attributesToUpdate, NO);
    OSStatus status = real_SecItemUpdate(q ? q : query, a ? a : attributesToUpdate);
    if (q) CFRelease(q);
    if (a) CFRelease(a);
    ThetaHPKESaveFromQueryAndAttrs(query, attributesToUpdate);
    return status;
}

static OSStatus hooked_SecItemDelete(CFDictionaryRef query) {
    if (!real_SecItemDelete) return -25243;
    CFDictionaryRef rewritten = SideloadSecItemDictCopy(query, YES);
    OSStatus status = real_SecItemDelete(rewritten ? rewritten : query);
    if (rewritten) CFRelease(rewritten);
    return status;
}

// Meta's caching defaults wrapper reads app-group suites through CFPreferences, not NSUserDefaults.
static void theta_rebindPreferenceRemap(void) {
    size_t count = 0;
    const ThetaCFPrefsHook *hooks = ThetaCFPrefsHooks(&count);
    struct rebinding rebindings[16];
    size_t n = 0;
    for (size_t i = 0; i < count && n < 16; i++) {
        if (!hooks[i].real) continue;
        rebindings[n++] = (struct rebinding){ hooks[i].name, hooks[i].replacement, NULL };
    }
    if (n) rebind_symbols(rebindings, n);
}

static void install_fishhook_rebindings(void) {
    // Resolve real implementations before rebinding (after rebind, dlsym would return our hooks).
    void *p = dlsym(RTLD_DEFAULT, "SecItemCopyMatching");
    real_SecItemCopyMatching = (OSStatus (*)(CFDictionaryRef, CFTypeRef *))p;
    p = dlsym(RTLD_DEFAULT, "SecItemAdd");
    real_SecItemAdd = (OSStatus (*)(CFDictionaryRef, CFTypeRef *))p;
    p = dlsym(RTLD_DEFAULT, "SecItemUpdate");
    real_SecItemUpdate = (OSStatus (*)(CFDictionaryRef, CFDictionaryRef))p;
    p = dlsym(RTLD_DEFAULT, "SecItemDelete");
    real_SecItemDelete = (OSStatus (*)(CFDictionaryRef))p;

    struct rebinding rebindings[] = {
        { "SecItemCopyMatching", (void *)hooked_SecItemCopyMatching, (void **)&original_SecItemCopyMatching },
        { "SecItemAdd", (void *)hooked_SecItemAdd, (void **)&original_SecItemAdd },
        { "SecItemUpdate", (void *)hooked_SecItemUpdate, (void **)&original_SecItemUpdate },
        { "SecItemDelete", (void *)hooked_SecItemDelete, (void **)&original_SecItemDelete },
    };
    size_t n = sizeof(rebindings) / sizeof(rebindings[0]);
    if (rebind_symbols(rebindings, n) == 0) {
        THDebugLog(@"[Theta] SecItem* hooks installed (sideload session persist)");
    }

    // Capture real strlen before rebind; only hook one symbol name.
    original_strlen_fn = (size_t (*)(const char *))dlsym(RTLD_DEFAULT, "strlen");
    // Also called for images that are already loaded.
    _dyld_register_func_for_add_image(theta_rebindStrlenInFBShared);
    theta_rebindPreferenceRemap();
}
