# Theta

Instagram tweak. Open Theta from the settings gear on the home feed, or by long-pressing the home tab.

This is [antond15/theta](https://github.com/antond15/theta), a fork of [objcmsgSend/theta](https://github.com/objcmsgSend/theta) based on upstream 1.0.1. It is maintained as often as my own casual Instagram use shows me that something is broken or missing, so expect fixes in bursts rather than on a schedule.

Tested as a **sideload** build against Instagram **451.0.0** on iOS 26.

> **Jailbreak builds were not tested and will not be.** The rootful and rootless targets still exist, but nothing in this fork has been checked on a jailbroken device, and jailbreak support is planned for removal. Known gaps are listed under [Jailbreak caveats](#jailbreak-caveats).

## What this fork changes

The full list is in [CHANGES.md](CHANGES.md). In short:

- **Instagram 451 support:** hooks for classes Instagram moved into Swift, plus working navigation, story seen-receipt blocking, Hide Create Button and Liquid Glass on 451 and iOS 26.
- **Sideload stability:** no inline code patches that crash a re-signed app, safer reel saving, and an FFmpeg build that can't collide with Instagram's own libraries.
- **Privacy and data:** diagnostic logging only in debug builds, fewer and more honest network requests, safer link handling, and a Clear App Cache that no longer deletes saved media.
- **Tooling:** one-time toolchain setup, a pinned Theos, a checksummed Substrate, and `compat.py` for checking hooks against a new Instagram build.

## Credits

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

It installs `make` and `ldid` with Homebrew, clones Theos into `$THEOS` (default `~/theos`) at the commit this fork is tested with, and unpacks the patched SDK into `$THEOS/sdks`. An existing Theos checkout is left alone; the script prints a warning and the checkout command if it is at a different commit. It also patches two things the SDK and Makefile expect but current macOS no longer provides:

- **Toolchain link.** The Makefile uses `$THEOS/toolchain/Xcode14.xctoolchain/usr/bin/`. Xcode 14 does not install on current macOS, so the script links that path to the selected Xcode or command-line tools toolchain. A real Xcode 14 toolchain already there is left alone.
- **libc++ headers.** The patched 14.5 SDK has no C++ headers, and clang 15 and later fail with `'cmath' file not found` from `simd/math.h`. The script copies libc++ headers into `$THEOS/sdks/iPhoneOS14.5.sdk/usr/include/c++`. Re-unpacking the SDK removes them, so re-run the script after that.

If you put Theos somewhere other than `~/theos`, export `THEOS` in your shell profile before running the script and building.

## Build

Use `./build.sh` from the repo root. Sideload is the tested target.

```sh
./build.sh              # rootful .deb → packages/
./build.sh rootless     # rootless .deb → packages/
./build.sh sideload     # inject into input/Payload → output/Instagram_patched.ipa
./build.sh sideload debug   # same, with diagnostic logging compiled in
```

Diagnostic logging (hook-install misses, keychain and notification-extension traces, `THDebugLog`) only exists in `debug` builds. Normal builds contain none of it. `debug` also works after `rootful` and `rootless`.

Equivalent Make invocations (use GNU make; `THEOS` must be exported). These only compile and package; the IPA injection is done by `build.sh`. Do not set `SIDELOAD` and `ROOTLESS` at the same time.

```sh
gmake package
gmake package ROOTLESS=1
gmake package SIDELOAD=1
gmake package SIDELOAD=1 THETA_DEBUG=1
```

FFmpeg headers and frameworks live at `layout/Library/Application Support/ffmpeg.framework`. Sideload builds copy that framework into the app when it is present, then run `scripts/isolate-ffmpeg-dylibs.py` and ad-hoc sign the result (see [Sideload fixes](CHANGES.md#sideload-fixes)). Reel save still works without FFmpeg via a native AVFoundation fallback, but AV1 reels need FFmpeg.

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

4. Open Instagram, then open Theta from the settings gear on the home feed or by long-pressing the home tab.

The bundled Substrate is `third_party/CydiaSubstrate.framework`, the binary from Saurik's `mobilesubstrate_0.9.6301` package. `build.sh` checks its SHA-256 before staging it. To use a different build, set `SUBSTRATE_FRAMEWORK_PATH` to a `CydiaSubstrate.framework` directory; that copy is not verified.

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
Include/            Public headers (ThetaDebug.h: THDebugLog, debug builds only)
third_party/        CydiaSubstrate.framework bundled into sideload builds (checksummed by build.sh)
scripts/assemble.py Builds TweakCOMPILE.xm (single TU for static hooks)
scripts/compat.py   Checks Theta's hooks against an Instagram build
scripts/objcdump.py Mach-O / ObjC metadata parser used by compat.py
scripts/isolate-ffmpeg-dylibs.py  Gives the bundled FFmpeg its own install names (sideload)
scripts/setup-toolchain.sh        One-time Theos / SDK / toolchain setup
```
