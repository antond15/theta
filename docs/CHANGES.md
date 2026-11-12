# Changes in this fork

Differences from upstream [objcmsgSend/theta](https://github.com/objcmsgSend/theta) 1.0.1. Ported work is credited in the [README](../README.md#credits) and in the commit messages. How the less obvious parts work is in [DEVELOPMENT.md](DEVELOPMENT.md#how-it-works).

## Instagram 451 and sideload compatibility

- **Tabs.** Tab order, swipe between tabs, launch tab, hidden tabs and Messenger Mode work on 451, including the iOS 26 system tab bar.
- **Hide Create Button** works on the new profile header.
- **Liquid Glass.** No longer crashes a sideloaded app at launch. The toggles no longer switch on Instagram's All / Friends / Following home feed, and "Enable Liquid Glass Buttons" has a visible effect again.
- **Follow Confirmation** works on 451.
- **DBB** blocks the forced-logout push on 451.
- **Profile pictures.** The save / fullscreen menu opens on a long press of the large avatar in a profile header only; avatars elsewhere behave normally.
- **AV1 reels** convert on a sideload: Theta's FFmpeg no longer clashes with the stripped copy Instagram ships. A failed conversion says why.
- **Background launches.** Seen-receipt and Instants seen blocking, Keep Deleted Messages and the forced-logout block are active even when iOS starts Instagram in the background. Settings read before the first unlock after a reboot are re-read once the phone is unlocked.

## Stories and Instants

- **Story seen receipts stay on the phone** on 451. The eye button (one story, or Mark All Seen) still marks the stories you pick as seen. Receipts queued while the setting is on are never sent, even after you turn it off.
- **Only seen calls are blocked**, for stories and Instants alike. The old match dropped any request containing words like `story_seen`, including a DM with that text.
- **Disappearing Media Ghost** marks the current photo or video as seen, not the next one, and works for videos. "Marked as seen!" appears only when something was sent. Ordinary story photos load normally with the setting on.
- **Disable Auto-Advance** works on 451, for photos and videos: a story stays on screen when it ends.
- **Always Mark Seen** no longer skips past those accounts' stories when Skip After Marking Seen is on.

## Messages and notifications

- **Keep Deleted Messages** no longer drops new messages or leaves threads loading; it used to swallow every update batch that contained an unsend.
- **Deleted Message Color** works on text messages again (not on photos, videos or shared posts).
- **DMs opened from a notification** on a cold launch no longer stay on "Loading...".
- **Notification banners decrypt reliably.** Theta keeps a copy of Instagram's notification keys, and only those, in the shared app group, so the notification extension can show the message when it can't read the keychain, also while the phone is locked. The extension no longer crashes on some keys and falls back to a generic banner.
- **Saving a voice message** asks each time the message plays to the end, also after it was saved once.

## Downloads and saving

- **Save To is respected** by every reel and video save, and Saved Media files never overwrite each other. With Photos access off, a save shows one toast that opens Settings and downloads nothing. "Add Photos Only" access is enough.
- **Results are honest.** "Saved" appears only when the file was saved, and the picker counts failures ("2 saved, 1 failed"). Progress and failures always show, even with Show Banners off; a failure while Instagram is in the background shows when you come back.
- **No broken files.** An expired link (HTTP 403), a missing audio track or an interrupted conversion fails the save instead of saving an error page, a silent video or a truncated one. Photos are saved once, with their original bytes, and a view-once video saves without its cover photo.
- **Saves don't collide.** Single and bulk saves share one lock, so one can't delete another's files or start twice, and Clear App Cache waits until they finish.
- **The reel download menu saves the reel on screen**, not the first reel it was opened on. A reels carousel opens one picker instead of two.
- **Bulk save** always finishes: a video that fails before downloading no longer leaves the toast spinning, and each video's bar fills when it is done.
- **Faster.** The picker loads small previews in parallel and opens without downloading every original, bulk saves run three videos at a time, and reel audio that is already AAC is merged without re-encoding.

## Links and privacy

- **Open Links in External Browser** only opens http/https links and no longer breaks links with encoded characters.
- **Strip Tracking from Links** also removes `gclid`, `ttclid` and `mc_eid`, unwraps `lm.instagram.com` and `l.facebook.com` redirects, and leaves the rest of a link untouched. In the in-app browser the link is cleaned before the page loads.
- **Clear App Cache** clears only caches and Theta's temp files. It used to delete almost all of `Documents/`, including media saved to a folder and, on sideload, Instagram's app-group data. The launch cleanup likewise deletes only Theta's own leftovers, not every audio and video file in `Documents/`.
- **No fake user agents.** Profile Analyzer and media previews send Instagram's own user agent instead of an outdated one or Safari's. Profile Analyzer fetches your avatar only when you open it.
- **No device logging.** Diagnostic logs are compiled in only by `./build.sh debug`.

## Settings

- **Fixed setting keys.** Settings used to be stored under their on-screen title, so rewording a title reset them. Each now has a fixed key (`theta.story.ghost`); existing values move over on first launch.
- **Choices are stored by name**, so reordering options can't change what was picked.
- **Export and import** use one versioned format that includes choices, colors and user lists. Older exports still import, "Import from Clipboard" accepts what "Export to Clipboard" copies, and a QR import restores choices too.
- **Reset Settings** also resets choices; user lists are kept.
- **New layout.** Pages follow the part of Instagram a setting affects (Feed & Explore, Stories, Reels, Messages, Profiles, then Downloads, Privacy, Confirmations, Navigation, Appearance, Theta), with sections and indented sub-options.
- **Rewritten text** for every title, description, banner and alert, with wrong descriptions corrected.
- Restart-required settings say so on their row, choices use a pop-up menu, and Clear Cache and Reset Colors ask first.
- Opening an auto-mark list from search shows the list instead of an empty editor.
- The links section points to this fork's repository.

## New settings

- **Hide Shared Reel Thumbnails** (Messages) replaces the preview image, keeping the play button, account details and tap action.
- **Hide Shared Post Thumbnails** (Messages) replaces shared-post previews and hides their captions, keeping account details and tap action.
- **Mute Shared Reel Notifications** (Messages) delivers a DM that shares a reel silently, removes it from Notification Center and keeps it off the badge. A sideload can't drop a push outright; that needs Apple's notification-filtering entitlement.

## Removed

- **Jailbreak builds** (rootful and rootless `.deb`) and their code, including Cydia Substrate: `./build.sh` builds the sideload IPA.
- The "Easter Eggs" setting (random creepy usernames in the feed).
- The unused GIF name overlay; "Copy GIF Name" on a comment GIF still works.
- The settings gear on the home feed header, which never appeared on 451. Theta opens with a long press on the home tab, or a shake with Shake to Open on.
- Hooks with no setting (suggested posts, the hidden long-press sort on profile grids), hooks for classes gone in 451, and unused helpers.

## Tooling

- `scripts/setup-toolchain.sh` sets up Theos at a pinned commit, the patched SDK and the toolchain on a Mac with only the command-line tools.
- `scripts/compat.py` checks every hook against an unpacked Instagram build (see [Checking a new Instagram version](DEVELOPMENT.md#checking-a-new-instagram-version)).
- `scripts/pre-push.sh` is the release gate: it fails a push on new `compat.py` misses or a compile error (see [Pre-push check](DEVELOPMENT.md#pre-push-check)).
- `./build.sh debug` builds with diagnostic logging (`THETA_DEBUG=1`).
- `scripts/assemble.py` builds the single translation unit in the same order on every machine.
