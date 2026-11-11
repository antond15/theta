# Theta

Sideload-only Instagram tweak: a fork of objcmsgSend/theta, built with Theos into `Theta.dylib`
and `ThetaNSE.dylib`, injected into a decrypted Instagram IPA by `build.sh` and installed with a
re-signer (Sideloadly, AltStore, SideStore, TrollStore). There is no jailbreak build.

- [`README.md`](README.md): what the fork is, requirements, build, install.
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md): toolchain, building, checking a new Instagram
  version, the pre-push check, settings, source layout.
- [`docs/CHANGES.md`](docs/CHANGES.md): everything this fork changes from upstream 1.0.1.
- `docs/backlog.md`: work that is decided but not done, the open step's handoff and changes
  awaiting a device test. **Gitignored and local only**; it may not exist in a fresh clone.

## Working rules

These rules are non-negotiable.

1. **Ask before deciding.** Ask the user before any decision, major change, or whenever you are
   unsure; never decide silently. Follow the `decision-round` skill.
2. **Branches.** Always work on `dev`. Never commit to `main`. Keep `main` linear: it only
   fast-forwards to a `dev` commit that passed the pre-push check, without switching branches
   (`git fetch . <sha>:main`, `close-step` step 8). No merge commits.
3. **Checks, no CI.** There is no CI, on purpose: the real check needs the decrypted IPA, which
   never leaves this machine. `scripts/pre-push.sh` (installed as `.git/hooks/pre-push`) is the
   gate: no new `compat.py` misses against the local baseline, and a clean compile.
4. **Commits.** Commit every change with a Conventional Commit subject, `type(scope): lowercase
   summary`, e.g. `fix(stories): keep seen receipts local on 451`. Usually no body; when one is
   needed (credit for a port, a fact the subject can't carry) keep it to a line or two. Credit
   ported code by author, repo and commit. Never mention device-test status in a commit; that goes
   in the backlog. Commit freely on `dev`; never push without approval: ask once, at the end of the
   session's work, with a dialog (`close-step` step 8). Leave no uncommitted or untracked files.
5. **Private inputs.** The decrypted IPA, `input/`, `output/` and anything read from them (binary
   dumps, offsets of a specific build) are never uploaded, pasted into external services or
   committed outside the docs.
6. **Tools and the device.** Ask before installing any tool (brew, pip, …) and before looking at
   the phone's live screen (screenshots, mirroring, view-hierarchy dumps). Reading device logs and
   crash reports with the installed libimobiledevice tools is fine. Device testing is done by the
   user, in batches.
7. **Docs.** Docs live in `docs/`. Only `README.md` and `AGENTS.md` stay at the root. Agent
   instructions go in this file; reusable procedures go in `.agents/skills/` (Claude Code reads
   them through the `.claude/skills` symlink). Never create a `CLAUDE.md`. A change and the docs it
   affects (`docs/CHANGES.md`, `docs/DEVELOPMENT.md`, `README.md`) land in the same commit.
8. **Backlog.** Maintain `docs/backlog.md` (local, never committed). Read it at the start of a
   session, update it whenever state changes, and remove an item once it has landed and been
   device-tested. Every change committed without a device test is listed under "Awaiting device
   test".
9. **Sessions and models.** Features (a new setting, a port, a change across several files) use
   the planner/builder split: a planner (Opus) runs the decision round, writes the handoff under
   "In progress" and stops; a builder (Sonnet, medium effort) builds it in a fresh session.
   Diagnosing an Instagram break and small fixes stay in one session; hard diagnosis may use an
   Opus subagent. High-risk code stays with the planner, and builder work that touched it gets a
   planner `/code-review medium` before the next step. High-risk code here:
   - the sideload runtime: keychain and app-group fakes, `strlen`/fishhook rebinds, the entrypoint
     and constructor hook install (`Source/Runtime/`, `Source/Hooks/Sideload/`);
   - privacy hooks: seen receipts, Tigon request dropping, Instants seen, tracking strip;
   - settings migrations: `kSettingsVersion` and key migrations in `Source/UI/ThetaSettings.m`;
   - the notification extension: `Source/SideloadNSE/`, the HPKE key files, decrypted banners.
10. **Settings.** Declare a setting once in `THETA_SETTING_KEYS` (`Include/ThetaSettings.h`),
    define it in `+allDefinitions` and place it once in `+pageGroups`
    (`Source/UI/ThetaSettingsRegistry.m`), read it through its constant (`ENABLED(…)`,
    `ThetaSettingChoice(…)`, …), never a string. Keys and choice option ids are stored on devices
    and in exports: never rename one; add a migration and bump `kSettingsVersion`. Settings UI is
    drawn by `THSettingCell`; adding a setting needs no UI code. See
    `docs/DEVELOPMENT.md#settings`.
11. **Instagram versions.** When a new Instagram build is unpacked into `input/`, follow the
    `ig-version-bump` skill.

## Commands

Skills refer to these by name. Run with `THEOS` exported (default `~/theos`).

| Name | Command | Notes |
|---|---|---|
| setup | `./scripts/setup-toolchain.sh` | one-time; ask before running, it installs tools |
| build | `gmake clean && gmake` | dylibs in `.theos/obj/`; `THETA_DEBUG=1` adds diagnostic logging |
| check | `./scripts/pre-push.sh` | `compat.py` vs baseline + compile; the pre-push hook |
| baseline | `./scripts/pre-push.sh --update-baseline` | accept the current misses (new IG version, or a miss judged fine) |
| compat | `./scripts/compat.py input/Payload/Instagram.app` | hooks that won't install on this build |
| ig-diff | `./scripts/compat.py <old.app> input/Payload/Instagram.app` | what broke since an older build |
| ipa | `./build.sh` / `./build.sh debug` | `output/Instagram_patched.ipa`; only when the user will device-test |

## Tech stack

- Theos at the commit pinned in `scripts/setup-toolchain.sh`, GNU make (`gmake`), `ldid`
- Patched iPhoneOS 14.5 SDK from `sdks/` (`SDKVERSION = 14.5`); CLT clang, no full Xcode needed
- Objective-C / Logos (`.xm`, `.x`, `.m`), fishhook for C symbol rebinding; no Cydia Substrate
- FFmpeg from `vendor/ffmpeg.framework`, loaded at runtime with `dlopen`
- Python 3 for `scripts/` (assembly, compat checking, FFmpeg isolation)

## Repository layout

See `docs/DEVELOPMENT.md#layout`. In short: `Source/Runtime` (hook helpers, rebinds, entrypoint),
`Source/Hooks/<area>` (all hooks, assembled into one translation unit), `Source/UI` (settings,
toasts, lock screen), `Source/Media`, `Source/ProfileAnalyzer`, `Source/SideloadNSE` (ThetaNSE),
`Include/`, `scripts/`, `tools/insert_dylib.c`, `docs/`.

## Architecture

- **One translation unit.** `scripts/assemble.py` joins `Source/Runtime/` and every file under
  `Source/Hooks/` into `TweakCOMPILE.xm`, so hook implementations stay `static`. A new hook file
  goes under `Source/Hooks/<area>/`.
- **No inline patches.** Never use `MSHookFunction`-style inline code patches: they crash a
  re-signed app. Hook ObjC methods, or rebind C symbols with fishhook in the one image that needs it.
- **Class lookups.** Look up the Swift mangled class name first and keep the old ObjC name as a
  fallback for older builds. A class moved into a Swift module is not found by its plain name.
- **Swift-direct calls are unhookable.** A selector that resolves can still never fire when its
  callers are Swift-direct or `objc_direct`. Find an `objc_msgSend` call on the path (as with
  `-[IGStorySeenStateUploader networker]`) before relying on a hook.
- **Network blocking** goes through `-[IGTigonNetworkLayer startRequest:policy:callbacks:]` and
  fails a request the way Tigon fails one it won't start.
- **Hook install timing.** The normal hook pass waits for the foreground. Surfaces built before it
  (the tab bar) and the privacy and protection hooks (seen receipts, Instants seen, Keep Deleted
  Messages, DBB), which must hold on a background launch, install from the constructor. A hook
  registered there must not also be registered in `InitializeHooks`.
- **Warnings.** A clean build prints six known warnings (`docs/DEVELOPMENT.md#building`). Don't
  add new ones.
- **Debug logging** only through `THDebugLog` (`Include/ThetaDebug.h`), compiled in only with
  `THETA_DEBUG=1`. Release builds log nothing.
- **Exports.** `AVAssetExportSession` file types go through `ThetaExportSessionSetFileType()`.

## Code style

- Follow the style of the surrounding file; no reformatting of unrelated code.
- Prefer simple, readable implementations over premature abstractions.
- Do not make unrelated refactors.

## Verification

Before a step is complete, follow the `close-step` skill: the `check` command, the IPA only when
the user will device-test, commits, the backlog (including "Awaiting device test"), summary, the
launch dialog and the release dialog, then stop.
