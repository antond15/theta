# Theta

Instagram tweak. Open Theta from the settings gear on the home feed, or by long-pressing the home tab.

This is [antond15/theta](https://github.com/antond15/theta), a fork of [objcmsgSend/theta](https://github.com/objcmsgSend/theta) based on upstream 1.0.1. It is maintained as often as my own casual Instagram use shows me that something is broken or missing, so expect fixes in bursts rather than on a schedule.

Tested as a **sideload** build against Instagram **451.0.0** on iOS 26. Sideloading (including TrollStore) is the only supported install; this fork has no jailbreak build.

## What this fork changes

The full list is in [CHANGES.md](CHANGES.md). In short:

- **Instagram 451 support:** hooks for classes Instagram moved into Swift, plus working navigation, story seen-receipt blocking, Hide Create Button and Liquid Glass on 451 and iOS 26.
- **Sideload stability:** no inline code patches that crash a re-signed app, safer reel saving, and an FFmpeg build that can't collide with Instagram's own libraries.
- **Privacy and data:** diagnostic logging only in debug builds, fewer and more honest network requests, safer link handling, and a Clear App Cache that no longer deletes saved media.
- **Sideload only:** the jailbreak targets and Cydia Substrate are gone.
- **Tooling:** one-time toolchain setup, a pinned Theos, and `compat.py` for checking hooks against a new Instagram build.

## Credits

Ported from other forks, credited by author, repo and commit in the commit messages:

- **Tangerie** ([Tangerie/theta](https://github.com/Tangerie/theta)): sideload launch-crash fix (7e8d9b2), reel-save crash (c5ead4d), FFmpeg isolation (5d0a2ef), precise download timing (f88a75b)
- **Nico Jan** ([nicojan/theta](https://github.com/nicojan/theta/tree/local-build-notes)): the basis for `compat.py` and `objcdump.py` (5fb3bd4)

## Requirements

- A Mac with the Xcode command-line tools (`xcode-select --install`). Full Xcode also works but is not required.
- [Homebrew](https://brew.sh), for GNU make (`gmake`; macOS ships make 3.81) and `ldid`
- [Theos](https://theos.dev) and the patched iPhoneOS 14.5 SDK from this repo, both installed by the setup script below
- Python 3 (used during the build)
- A **decrypted** Instagram IPA

### Setup

Run once after cloning (safe to re-run):

```sh
./scripts/setup-toolchain.sh
```

It installs GNU make and `ldid` with Homebrew, Theos at a tested commit, and the patched SDK. See [DEVELOPMENT.md](DEVELOPMENT.md#toolchain) for what it changes and why. If you put Theos somewhere other than `~/theos`, export `THEOS` in your shell profile before running the script and building.

## Build

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

2. Run `./build.sh`. It compiles `Theta.dylib` and `ThetaNSE`, injects them into Instagram and its notification service extension, embeds FFmpeg, and writes `output/Instagram_patched.ipa`. `./build.sh debug` does the same with diagnostic logging (see [DEVELOPMENT.md](DEVELOPMENT.md#debug-build)).

## Install

1. Install `output/Instagram_patched.ipa`:
   - **Sideloadly / AltStore / SideStore:** open the IPA and let the tool re-sign it with your Apple ID.
   - **TrollStore:** install the IPA on the device.
2. Open Instagram, then open Theta from the settings gear on the home feed or by long-pressing the home tab.

`ThetaNSE` lets the notification extension decrypt banners. `Source/SideloadNSE/keychain-sharing.plist` is **optional** and is not applied by the build. Skip it unless notifications break because the extension cannot read Instagram’s keychain. In that case, merge those entitlements onto `Instagram.app` and `InstagramNotificationExtension.appex` only (never onto `ThetaNSE` or other dylibs), and replace `TEAMID` with your signing Team ID. Theta already probes wildcard keychain groups at runtime, so most installs do not need this plist.

## Development

Toolchain details, debug builds, checking hooks against a new Instagram version, and the source layout are in [DEVELOPMENT.md](DEVELOPMENT.md).
