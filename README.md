# Theta

Instagram tweak. Open Theta from the settings gear on the home feed, or by long-pressing the home tab.

This is [antond15/theta](https://github.com/antond15/theta), a fork of [objcmsgSend/theta](https://github.com/objcmsgSend/theta) based on upstream 1.0.1. It is maintained as often as my own casual Instagram use shows me that something is broken or missing, so expect fixes in bursts rather than on a schedule.

Tested as a **sideload** build against Instagram **451.0.0** on iOS 26.

> **Jailbreak builds were not tested and will not be.** The rootful and rootless targets still exist and the jailbreak code paths are left in place, but nothing in this fork has been checked on a jailbroken device. Known gaps are listed under [Jailbreak caveats](#jailbreak-caveats).

## Changes in this fork

### Instagram 451 fixes

- **Swift class renames.** Hooks look up the Swift mangled class name first and the old ObjC name after, for the classes Instagram 451 moved into Swift modules.
- **Navigation** (tab order, swipe between tabs, launch tab, hide tabs, Messenger Mode). Tab hooks now also install from the constructor, because Instagram builds the tab bar before Theta's normal hook pass. Hidden tabs are filtered where Instagram builds the tab list, which covers the iOS 26 system tab bar.
- **Story seen receipts stay local.** The 451 Swift pending-seen store sends `/media/seen/` through a direct (unhookable) `IGAPIRequest` call. Theta now hooks the one ObjC call on that path, `-[IGStorySeenStateUploader networker]`, and returns nil while receipts are blocked.
- **Seen-request dropping** for stories and Instants moved to `-[IGTigonNetworkLayer startRequest:policy:callbacks:]`, the bottom of Instagram's network-layer chain. A dropped request fails the same way Tigon fails a request it won't start.
- **Hide Create Button** works on the Swift profile header again. Its `leftButtons` is a Swift array with no getter, so it is read from the ivar directly.
- **DBB:** the forced-logout push hook also looks on `IGPushCoordinator`, where the method moved.
- **Liquid Glass**
  - The toggles no longer force Instagram's "homecoming" experiment, which on 451 replaces the home feed with an All / Friends / Following feed.
  - "Enable Liquid Glass Buttons" now sets Instagram's stored glass flag through its own `overrideIsEnabled:` / `setIsEnabled:` setters. Instagram reads the flag directly from Swift, so swizzling the getter alone had no visible effect.
- **Profile pictures:** the save / fullscreen menu opens on a long press of the large avatar in a profile header only. Avatars elsewhere keep their normal behaviour.
- Removed hooks and fallbacks for classes and selectors that no longer exist in 451 (old reaction, voice-message and cache-update variants, `LSKeychainItemController`, several Liquid Glass experiment switches).

### Sideload fixes

- **Inline-patch crashes.** Theta no longer inline-patches `__TEXT` in sideload builds: the Liquid Glass C-symbol hooks (a launch crash) and the Instants Swift hooks. A patched page no longer matches the app's code signature, and iOS kills the app the first time it runs that code.
- **Reel saving.** Export sessions are guarded against unsupported file types, downloads use precise timing, and the single-reel path refuses to save a raw DASH segment.
- **FFmpeg / AV1.** Instagram ships its own stripped `libavcodec` and `libavutil` with the same install names as Theta's FFmpeg. The sideload build therefore moves Theta's libraries to `ffmpeg.framework/dylibs/<name>.dylib`, rewrites their install names to `@loader_path/<name>.dylib` and ad-hoc signs them, so re-signers sign them and they can't bind to Instagram's copies. When a conversion fails, the toast says why.

### Tooling

- `scripts/setup-toolchain.sh` sets up Theos, the patched SDK and the toolchain on a Mac with only the command-line tools.
- `scripts/compat.py` checks every hook against an unpacked Instagram build (see [Checking a new Instagram version](#checking-a-new-instagram-version)).

### Credits

Ported from other forks, credited by author, repo and commit in the commit messages:

- **Tangerie** ([Tangerie/theta](https://github.com/Tangerie/theta)): sideload launch-crash fix (7e8d9b2), reel-save crash (c5ead4d), FFmpeg isolation (5d0a2ef), precise download timing (f88a75b)
- **Nico Jan** ([nicojan/theta](https://github.com/nicojan/theta/tree/local-build-notes)): the basis for `compat.py` and `objcdump.py` (5fb3bd4)

## Requirements

- A Mac with the Xcode command-line tools (`xcode-select --install`). Full Xcode also works but is not required.
- [Homebrew](https://brew.sh), for GNU make (`gmake`; macOS ships make 3.81) and `ldid`
- [Theos](https://theos.dev), with `THEOS` set (`build.sh` defaults to `~/theos`)
- The **patched iPhoneOS 14.5 SDK** from this repo. A stock Xcode SDK will not work — Theta is built with `SDKVERSION = 14.5` and needs Theos-patched private-framework stubs.
- Python 3 (used by `scripts/assemble.py` during the build)

`dpkg-deb` is not needed; Theos falls back to its bundled `dm.pl` for `.deb` packaging.

Jailbreak packages also need **Cydia Substrate** on the device (`Depends: mobilesubstrate`). Sideload builds bundle Substrate into the IPA.

### Setup

Run once after cloning (safe to re-run):

```sh
./scripts/setup-toolchain.sh
```

It installs `make` and `ldid` with Homebrew, clones Theos into `$THEOS` (default `~/theos`), and unpacks the patched SDK into `$THEOS/sdks`. It also patches two things the SDK and Makefile expect but current macOS no longer provides:

- **Toolchain link.** The Makefile uses `$THEOS/toolchain/Xcode14.xctoolchain/usr/bin/`. Xcode 14 does not install on current macOS, so the script links that path to the selected Xcode or command-line tools toolchain. A real Xcode 14 toolchain already there is left alone.
- **libc++ headers.** The patched 14.5 SDK has no C++ headers, and clang 15 and later fail with `'cmath' file not found` from `simd/math.h`. The script copies libc++ headers into `$THEOS/sdks/iPhoneOS14.5.sdk/usr/include/c++`. Re-unpacking the SDK removes them, so re-run the script after that.

If you put Theos somewhere other than `~/theos`, export `THEOS` in your shell profile before running the script and building.

## Build

Prefer `./build.sh` from the repo root. Do not set `SIDELOAD` and `ROOTLESS` at the same time.

```sh
./build.sh              # rootful .deb → packages/
./build.sh rootless     # rootless .deb → packages/
./build.sh sideload     # inject into input/Payload → output/Instagram_patched.ipa
./build.sh sideload debug   # same, with diagnostic logging compiled in
```

Diagnostic logging (hook-install misses, keychain and notification-extension traces, `THDebugLog`) only exists in `debug` builds (`THETA_DEBUG=1`). Normal builds contain none of it.

Equivalent Make invocations (use GNU make; `THEOS` must be exported):

```sh
gmake package
gmake package ROOTLESS=1
gmake package SIDELOAD=1
```

FFmpeg headers and frameworks live at `layout/Library/Application Support/ffmpeg.framework`. Sideload builds copy that framework into the app when it is present, then run `scripts/isolate-ffmpeg-dylibs.py` and ad-hoc sign the result (see [Sideload fixes](#sideload-fixes)). Reel save still works without FFmpeg via a native AVFoundation fallback, but AV1 reels need FFmpeg.

## Install

### Jailbreak (rootful / rootless)

Untested in this fork; see [Jailbreak caveats](#jailbreak-caveats).

1. Build with `./build.sh` or `./build.sh rootless`.
2. Copy the `.deb` from `packages/` to the device and install it with Sileo, Zebra, or `dpkg -i`.
   - Rootful: `packages/com.theta.tweak_1.0.1_iphoneos-arm.deb`
   - Rootless: `packages/com.theta.tweak_1.0.1_iphoneos-arm64.deb`
3. Respring if the package manager does not, then open Instagram.

If Theos device install is already configured (`THEOS_DEVICE_IP`), `make install` / `make install ROOTLESS=1` will install and reopen Instagram.

### Sideload

1. Get a **decrypted** Instagram IPA and unpack it so the app binary is at:

   ```
   input/Payload/Instagram.app/Instagram
   ```

   Example:

   ```sh
   unzip Instagram.ipa -d /tmp/ig
   mkdir -p input
   cp -R /tmp/ig/Payload input/
   ```

   Check that the binary is really decrypted (`cryptid 0`). An encrypted binary builds fine but the tweak will not load:

   ```sh
   otool -l input/Payload/Instagram.app/Instagram | grep -A4 LC_ENCRYPTION_INFO
   ```

2. Run `./build.sh sideload`. That compiles `Theta.dylib` with `SIDELOAD=1`, injects it into the Instagram binary, stages `CydiaSubstrate.framework`, and writes `output/Instagram_patched.ipa`.

3. Install that IPA:
   - **Sideloadly / AltStore / SideStore** — open `output/Instagram_patched.ipa` and let the tool re-sign it with your Apple ID.
   - **TrollStore** — install the IPA on-device.

4. Open Instagram. Theta settings use the same gear / home-tab long-press as jailbreak.

If Substrate cannot be found automatically, set `SUBSTRATE_FRAMEWORK_PATH` to a `CydiaSubstrate.framework` directory, or place one at `third_party/CydiaSubstrate.framework`.

Sideload also injects `ThetaNSE` into Instagram’s notification service extension so decrypted banners can work. `Source/SideloadNSE/keychain-sharing.plist` is **optional** and is not applied by the build. Skip it unless notifications break because the extension cannot read Instagram’s keychain. In that case, merge those entitlements onto `Instagram.app` and `InstagramNotificationExtension.appex` only (never onto `ThetaNSE` or other dylibs), and replace `TEAMID` with your signing Team ID. Theta already probes wildcard keychain groups at runtime, so most sideload installs do not need this plist.

## Jailbreak caveats

Found by reading the code, never tried on a device:

- The four Instants inline Swift hooks in `SaveInstants.m` still install in jailbreak builds. Their target addresses come from a disassembly of a different Instagram build, so on 451 they would patch unrelated code.
- FFmpeg isolation only runs in `./build.sh sideload`. The `.deb` keeps the original `@rpath` install names, so AV1 conversion can bind to Instagram's stripped libraries and fail.
- With "Enable Liquid Glass Surfaces" on, jailbreak builds still inline-hook `IGTabBarHomecomingWithFloatingTabEnabled`, which may bring back part of the homecoming feed. Two of the other patched functions no longer exist in 451.

## Checking a new Instagram version

`scripts/compat.py` reads the ObjC metadata of every binary in an unpacked Instagram app and checks each hook Theta installs: the class must exist and the selector must be on it, a category or a superclass. Variables passed to the hook helpers are traced back to their assignments and fallback lists.

```sh
./scripts/compat.py input/Payload/Instagram.app                    # hooks that won't install on this build
./scripts/compat.py /path/to/old/Instagram.app input/Payload/Instagram.app   # what broke since the old build
```

A hook marked missing whose neighbours in the same file still resolve is usually a dead fallback. "Now Swift: …" means Instagram moved the class into a Swift module, and the plain name Theta uses no longer finds it. A hook that resolves can still misbehave, so this does not replace testing on a device. The Mach-O parser is `scripts/objcdump.py`; both are based on Nico Jan's scripts in [nicojan/theta](https://github.com/nicojan/theta/tree/local-build-notes).

## Layout

```
Source/
  Runtime/          Hook helpers, Substrate loader, sideload shims, entrypoint
  Hooks/
    Behavior/       Ads, stories, confirmations, privacy, live, …
    General/        Date format, external browser, liquid glass
    Media/          Reel tap controls
    Messages/       DM features
    Save/           Media / profile / audio saves
    UI/             Tabs, navigation, settings entry points
    Sideload/       Keychain / app-group fakes
  SideloadNSE/      Sideload notification-extension helper (`keychain-sharing.plist` is optional)
  UI/               Settings, toasts, helpers, lock screen
  Media/            Download UI, AV1 transcoder, DASH
  ProfileAnalyzer/  Follower analytics
Include/            Public headers
scripts/assemble.py Builds TweakCOMPILE.xm (single TU for static hooks)
scripts/compat.py   Checks Theta's hooks against an Instagram build
scripts/objcdump.py Mach-O / ObjC metadata parser used by compat.py
scripts/isolate-ffmpeg-dylibs.py  Gives the bundled FFmpeg its own install names (sideload)
scripts/setup-toolchain.sh        One-time Theos / SDK / toolchain setup
```
