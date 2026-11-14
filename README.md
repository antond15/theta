# Theta

Theta is an Instagram tweak for iOS that adds useful features to the base app. It can limit reels and other distractions, hide ads or suggested content, keep activity like seen receipts private, and save shared media to the phone. Every feature is optional and has its own switch on Theta's settings page.

This is [antond15/theta](https://github.com/antond15/theta), a fork of [objcmsgSend/theta](https://github.com/objcmsgSend/theta) based on upstream 1.0.1. It is maintained as often as my own casual Instagram use shows me that something is broken or missing, so expect fixes in bursts rather than on a schedule.

Theta supports Instagram **451.0.0** on iOS 26, as a **sideload** build only. There is no jailbreak build. Other Instagram versions may break, and issues about them are not supported.

## What this fork changes

The full list is in [CHANGES.md](docs/CHANGES.md). In short:

- **Instagram 451 support:** hooks follow the classes Instagram moved into Swift, so Theta's features work on 451 and iOS 26.
- **Sideload stability:** no inline code patches that crash a re-signed app, notification banners that decrypt on a sideload, and an FFmpeg build that can't collide with Instagram's own libraries.
- **Privacy:** seen receipts and other blocked requests stay on the phone, fewer and more honest network requests, and diagnostic logging only in debug builds.
- **Settings:** fixed setting keys, one versioned export format and a new layout grouped by the part of Instagram a setting affects.

## Credits

Ported from other forks, credited by author, repo and commit in the commit messages:

- **Tangerie** ([Tangerie/theta](https://github.com/Tangerie/theta)): sideload launch-crash fix (7e8d9b2), reel-save crash (c5ead4d), FFmpeg isolation (5d0a2ef), precise download timing (f88a75b)
- **Nico Jan** ([nicojan/theta](https://github.com/nicojan/theta/tree/local-build-notes)): the basis for `compat.py` and `objcdump.py` (5fb3bd4)

## Requirements

- A macOS device with the Xcode CLI tools (`xcode-select --install`), which include Python 3. Full Xcode also works but is not required.
- [Homebrew](https://brew.sh), for GNU make (`gmake`, since macOS ships make 3.81) and `ldid`
- [Theos](https://theos.dev) and the patched iPhoneOS 14.5 SDK from this repo, both installed by the setup script below
- A **decrypted** Instagram IPA

### Setup

Run once after cloning (safe to re-run):

```sh
./scripts/setup-toolchain.sh
```

It installs GNU make and `ldid` with Homebrew, Theos at a tested commit, and the patched SDK. See [DEVELOPMENT.md](docs/DEVELOPMENT.md#toolchain) for what it changes and why. If you put Theos somewhere other than `~/theos`, export `THEOS` in your shell profile before running the script and building.

## Build

1. Unpack a **decrypted** Instagram IPA into `input/`, so the app binary is at `input/Payload/Instagram.app/Instagram`:

   ```sh
   unzip -q Instagram.ipa -d input
   ```

   Check that the binary is really decrypted (`cryptid 0`). An encrypted binary builds fine but the tweak will not load:

   ```sh
   otool -l input/Payload/Instagram.app/Instagram | grep -A4 LC_ENCRYPTION_INFO
   ```

2. Run `./build.sh`. It compiles `Theta.dylib` and `ThetaNSE`, injects them into Instagram and its notification service extension, embeds FFmpeg, and writes `output/Instagram_patched.ipa`. `./build.sh debug` does the same with diagnostic logging (see [DEVELOPMENT.md](docs/DEVELOPMENT.md#debug-build)).

## Install

1. Install `output/Instagram_patched.ipa` with your re-signing or sideloading tool.
2. Open Instagram, then open Theta by long-pressing the home tab.

To update, build again and install the new IPA over the existing app. Your settings are kept.

If notification banners stop showing message content, see [Notification extension](docs/DEVELOPMENT.md#notification-extension).

## Development

Toolchain details, debug builds, checking hooks against a new Instagram version, and the source layout are in [DEVELOPMENT.md](docs/DEVELOPMENT.md).

## AI use

The maintainer decides what gets built and how it should work, guides the work step by step, and reviews and approves every change before it is committed. Claude Code writes most of the code and helps with code research, such as tracing how Instagram reaches a feature. Every change is tested on a real device before it ships. The rules the agents follow are in [AGENTS.md](AGENTS.md).

## Disclaimer

Theta is not affiliated with or endorsed by Instagram or Meta. Using a modified client may break Instagram's terms of service and can get an account restricted. Use it at your own risk.
