# Theta

Instagram tweak for jailbreak and sideload. Open Theta from the settings gear on the home feed, or by long-pressing the home tab.

Tested against Instagram **441.0.0**.

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
```

Equivalent Make invocations (use GNU make; `THEOS` must be exported):

```sh
gmake package
gmake package ROOTLESS=1
gmake package SIDELOAD=1
```

FFmpeg headers and frameworks live at `layout/Library/Application Support/ffmpeg.framework`. Sideload builds copy that framework into the app when it is present. Reel save still works without FFmpeg via a native AVFoundation fallback.

## Install

### Jailbreak (rootful / rootless)

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
```
