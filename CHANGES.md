# Changes in this fork

Differences from upstream [objcmsgSend/theta](https://github.com/objcmsgSend/theta) 1.0.1. Ported work is credited in the [README](README.md#credits) and in the commit messages.

## Instagram 451 fixes

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

## Sideload fixes

- **Inline-patch crashes.** Theta no longer inline-patches `__TEXT` in sideload builds: the Liquid Glass C-symbol hooks (a launch crash) and the Instants Swift hooks. A patched page no longer matches the app's code signature, and iOS kills the app the first time it runs that code.
- **Reel saving.** Export sessions are guarded against unsupported file types, downloads use precise timing, and the single-reel path refuses to save a raw DASH segment.
- **FFmpeg / AV1.** Instagram ships its own stripped `libavcodec` and `libavutil` with the same install names as Theta's FFmpeg. The sideload build therefore moves Theta's libraries to `ffmpeg.framework/dylibs/<name>.dylib`, rewrites their install names to `@loader_path/<name>.dylib` and ad-hoc signs them, so re-signers sign them and they can't bind to Instagram's copies. When a conversion fails, the toast says why.
- **App-group containers** are probed once per group instead of writing a probe file on every lookup.

## Privacy and data

- **Diagnostic logging only in debug builds.** Notification-extension traces, hook-install misses, the keychain access group and trace logs are compiled in only by `./build.sh sideload debug`. Normal builds don't write them to the device log.
- **Profile Analyzer** fetches your avatar only when you open it, not on every app launch. Its fallback API request sends Instagram's own user agent instead of a hard-coded, outdated one.
- **Media preview downloads** (Save Profile Posts, bulk save) no longer pretend to be Safari.
- **Open Links in External Browser** only opens http/https links. Other schemes inside an `l.instagram.com` redirect are left to Instagram. Redirect targets are no longer percent-decoded twice, which used to break links with encoded characters.
- **Strip Tracking from Links** also removes `gclid`, `ttclid` and `mc_eid`, and unwraps `lm.instagram.com` and `l.facebook.com` redirects.
- **Clear App Cache** clears `Library/Caches` and Theta's own temp files only. It used to delete almost all of `Documents/`, including media saved with Save Method = Folder and, on sideload, Instagram's app-group data.
- **Launch cleanup** deletes only Theta's own leftover temp files. It used to delete every audio and video file in `Documents/`.
- Bulk-save and thumbnail temp files have unique names, so overlapping saves can't overwrite each other.

## Removed

- The "Easter Eggs" setting (random creepy usernames in the feed).
- The unused GIF name overlay. "Copy GIF Name" on a comment GIF still works.
- Suggested-posts hooks that had no setting and could never run.
- Unused hook helpers.

## Tooling

- `scripts/setup-toolchain.sh` sets up Theos, the patched SDK and the toolchain on a Mac with only the command-line tools. It installs Theos at a pinned, tested commit and warns when an existing checkout differs.
- `scripts/compat.py` checks every hook against an unpacked Instagram build (see [Checking a new Instagram version](README.md#checking-a-new-instagram-version)).
- `./build.sh sideload debug` builds with diagnostic logging (`THETA_DEBUG=1`).
- The sideload build stages only the bundled `third_party/CydiaSubstrate.framework` and checks its SHA-256 first. It no longer downloads Substrate over plain HTTP or picks up a copy from `~/Downloads` or `~/Desktop`.
- `scripts/assemble.py` builds the single translation unit in the same order on every machine.
