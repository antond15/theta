# Development

Notes for working on Theta. Building and installing are covered in the [README](README.md).

## Toolchain

`scripts/setup-toolchain.sh` does the one-time setup and is safe to re-run:

- Installs `make` (GNU make, run as `gmake`; macOS ships make 3.81) and `ldid` with Homebrew.
- Clones Theos into `$THEOS` (default `~/theos`) at a pinned commit, `THEOS_COMMIT` in the script. This is the commit the fork is built and tested with; bump it on purpose. An existing Theos checkout is left alone, and the script prints a warning and the checkout command if it is at a different commit.
- Unpacks the patched iPhoneOS 14.5 SDK from `sdks/` into `$THEOS/sdks`. A stock Xcode SDK will not work: Theta is built with `SDKVERSION = 14.5` and needs Theos-patched private-framework stubs.

It also patches two things the SDK and Makefile expect but current macOS no longer provides:

- **Toolchain link.** The Makefile uses `$THEOS/toolchain/Xcode14.xctoolchain/usr/bin/`. Xcode 14 does not install on current macOS, so the script links that path to the selected Xcode or command-line tools toolchain. A real Xcode 14 toolchain already there is left alone.
- **libc++ headers.** The patched 14.5 SDK has no C++ headers, and clang 15 and later fail with `'cmath' file not found` from `simd/math.h`. The script copies libc++ headers into `$THEOS/sdks/iPhoneOS14.5.sdk/usr/include/c++`. Re-unpacking the SDK removes them, so re-run the script after that.

## Building

`./build.sh` compiles, injects and zips. To only compile (GNU make, with `THEOS` exported):

```sh
gmake clean && gmake                  # .theos/obj/Theta.dylib and ThetaNSE.dylib
gmake clean && gmake THETA_DEBUG=1    # same, with diagnostic logging
```

The Makefile runs `scripts/assemble.py` first, which joins `Source/Runtime/` and every file under `Source/Hooks/` into one translation unit, `TweakCOMPILE.xm`, so hook implementations can stay `static`. `Source/UI`, `Source/Media` and `Source/ProfileAnalyzer` are compiled separately. The notification-extension helper `ThetaNSE` is a second library built from `Source/SideloadNSE`.

A clean build currently prints six warnings: `-multiply_defined is obsolete` (twice), the duplicate `BlockTarget` category on `UIButton` and on `UIGestureRecognizer`, `performSelector may cause a leak`, and the `_ThetaNSEInit` static initializer. Don't add new ones. The first build after changing compiler flags can also print `The selected platform is no longer supported by libc++` while clang rebuilds its module cache; that goes away on the next build.

The version number is `THETA_VERSION_NUMBER` in the Makefile.

### Debug build

```sh
./build.sh debug
```

This compiles in diagnostic logging (`THETA_DEBUG=1`): hook-install misses, keychain and notification-extension traces, and every `THDebugLog` call (`Include/ThetaDebug.h`). Normal builds contain none of it. `THDebugLog` uses `NSLog`, so the output shows up in Console.app; filter on `Theta`.

### FFmpeg

FFmpeg headers and frameworks live in `vendor/ffmpeg.framework`. The Makefile compiles against its headers. Theta loads the libraries at runtime with `dlopen`. `build.sh` copies the framework into the app, then runs `scripts/isolate-ffmpeg-dylibs.py` and ad-hoc signs the result (see [Sideload fixes](CHANGES.md#sideload-fixes)). Reel save still works without FFmpeg through a native AVFoundation fallback, but AV1 reels need FFmpeg.

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
  Runtime/          Hook helpers, keychain/strlen rebinds, sideload shims, entrypoint
  Hooks/
    Behavior/       Ads, stories, confirmations, privacy, live, …
    General/        Date format, external browser, liquid glass
    Media/          Reel tap controls
    Messages/       DM features
    Save/           Media / profile / audio saves
    UI/             Tabs, navigation, settings entry points
    Sideload/       Keychain / app-group fakes, TestFlight nag
  SideloadNSE/      Notification-extension helper (ThetaNSE; `keychain-sharing.plist` is optional)
  UI/               Settings, toasts, helpers, lock screen
  Media/            Download UI, AV1 transcoder, DASH
  ProfileAnalyzer/  Follower analytics
Include/            Public headers (ThetaDebug.h: THDebugLog, debug builds only)
vendor/ffmpeg.framework  FFmpeg headers and libraries, embedded into the app by build.sh
ThetaResources.bundle    Images, copied into the app by build.sh
tools/insert_dylib.c     Adds the load commands for Theta and ThetaNSE (compiled by build.sh)
scripts/assemble.py      Builds TweakCOMPILE.xm (single TU for static hooks)
scripts/compat.py        Checks Theta's hooks against an Instagram build
scripts/objcdump.py      Mach-O / ObjC metadata parser used by compat.py
scripts/isolate-ffmpeg-dylibs.py  Gives the bundled FFmpeg its own install names
scripts/setup-toolchain.sh        One-time Theos / SDK / toolchain setup
```
