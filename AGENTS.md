# Theta

Sideload-only Instagram tweak: a fork of objcmsgSend/theta, built with Theos into `Theta.dylib`
and `ThetaNSE.dylib`, injected into a decrypted Instagram IPA by `build.sh` and installed with a
re-signer (Sideloadly, AltStore, SideStore, TrollStore). There is no jailbreak build.

- [`README.md`](README.md): what the fork is, requirements, build, install.
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md): toolchain, building, checking a new Instagram
  version, the pre-push check, settings, source layout.
- [`docs/CHANGES.md`](docs/CHANGES.md): everything this fork changes from upstream 1.0.1.
- [`docs/technical-plan.md`](docs/technical-plan.md): overview and where each part is documented.
- [`docs/deployment.md`](docs/deployment.md): from a `dev` commit to an IPA on the phone.
- `docs/backlog.md`: work that is decided but not done, the open step's handoff and changes
  awaiting a device test. **Gitignored and local only**; it may not exist in a fresh clone.

<!-- kit:begin -->
<!-- Managed by ai-workflow-kit: `install.sh --update` replaces everything between these markers. -->
## Working rules

1. **Decisions.** Ask the user when a choice has a visible effect, a data consequence or a real
   trade-off; settle technical internals yourself and write a one-line reason. Explain in plain
   language (what it is here, an example, effect with and without, cost, pros and cons), then
   use AskUserQuestion: up to four questions per call, recommended option first and labelled
   "(Recommended)", each standing on its own because the dialog may hide the message. Answer a
   clarifying question in chat and re-ask only that. If the dialog tool is missing or the call
   is denied, ask in chat. A planner follows `decision-round`. A
   builder that meets a core question (data model, math, input mapping, security, a visible
   flow) stops, records it under "In progress" and tells the user to take it to a planner.
2. **Branches and commits.** Work on `dev`. Commit as work lands with a Conventional Commit
   subject, `type(scope): lowercase summary`, e.g. `feat(auth): add totp enrollment`. Docs
   changes go in the related commit. Push and move `main` only inside `close-step`, after the
   user approves: an unasked push was rejected before.
3. **CI.** When the project has CI (`.github/workflows/ci.yml`), read it with `gh`, never poll;
   it runs on every push except to `main`. On a failure read only
   `gh run view <id> --log-failed`.
4. **Packages.** Use the package manager and commands named in Tech stack and Commands; commit
   the lockfile. Runtime packages go in `dependencies`, tooling and tests in `devDependencies`.
   Check whether the stack already provides a thing before adding a dependency.
5. **Deployment.** Follow the Deployment section below and `docs/deployment.md`.
6. **Docs.** Docs live in `docs/`; only `README.md` and `AGENTS.md` stay at the root (a UI
   project also has `PRODUCT.md` and `DESIGN.md` there). Procedures go in `.agents/skills/`. Do
   not create a `CLAUDE.md`: Claude Code reads `AGENTS.md` itself, and a `CLAUDE.md` in the
   project or a parent disables that.
7. **Backlog.** Update `docs/backlog.md` when state changes; remove an item once done. A step's
   handoff lives under "In progress": read only that section (grep the heading, read the range).
   If `docs/backlog.md` is not tracked by git, still update it but skip every backlog commit
   (handoff commit, ci-failure note).
8. **Sessions.** The planner runs the decision round, writes the handoff and stops; a builder
   builds a fully decided step in a fresh session. High-risk code (auth, encryption, keys, money
   math, migrations) stays with the planner, who also reviews builder work that touched it.

## When a fix fails

After two fixes that share one assumption have failed, write that assumption down and test it
directly before a third fix. If the test does not settle it, stop and report.

## Session start

Run `git status -sb` once and note changes that are not yours. When the project has CI, check
the last `dev` CI run once (`gh run list --branch dev --limit 1`); read the backlog's "In
progress" section. In Claude Code the hooks in `.claude/hooks/` print these and block every
`git push` except a plain push to `dev`; other agents have no hooks, so do it and follow the
rule yourself.

## Models

Handoffs name only the next session's role; a launch reads model and effort from this table.
| Role | Model | Effort |
|---|---|---|
| Planner: decision rounds, first-session architecture, design review, high-risk code and its review | Opus 5.5 (`claude-opus-5-5`) | high |
| Builder | Sonnet 5.5 (`claude-sonnet-5-5`) | medium |
| Mechanical: CI triage, backlog grooming, docs-only edits, dependency bumps | Haiku 5.5 (`claude-haiku-5-5`) | medium |

Fable 5.2 is an occasional opt-in for an unusually hard architecture decision. Re-evaluate this
split on real steps. The project's Codex model, if any, is in its own Codex section.

## Skills

`.agents/skills/decision-round/SKILL.md` (planner), `.agents/skills/close-step/SKILL.md` (session
end, with `release.sh`).

## Verification

A session that changed something or has a next step ends with the `close-step` skill. To decide,
run `git status -sb` once: if the tree is clean, level with `origin/dev`, `main` is level with
`dev` (no release pending) and no next step exists, say so in one line and stop without loading
the skill. Subagents and delegated children
never run `close-step`; they return their report to the parent.
<!-- kit:end -->

## Theta rules

These come on top of the working rules above.

1. **Checks, no CI.** There is no CI, on purpose: the real check needs the decrypted IPA, which
   never leaves this machine. `scripts/pre-push.sh` (installed as `.git/hooks/pre-push`) is the
   gate: no new `compat.py` misses against the local baseline, and a clean compile. `main` only
   fast-forwards to a `dev` commit that passed it; no merge commits.
2. **Commits.** Usually no body; when one is needed (credit for a port, a fact the subject can't
   carry) keep it to a line or two. Credit ported code by author, repo and commit. Never mention
   device-test status in a commit; that goes in the backlog.
3. **Private inputs.** The decrypted IPA, `input/`, `output/` and anything read from them (binary
   dumps, offsets of a specific build) are never uploaded, pasted into external services or
   committed outside the docs.
4. **Tools and the device.** Ask before installing any tool (brew, pip, …) and before looking at
   the phone's live screen (screenshots, mirroring, view-hierarchy dumps). Reading device logs and
   crash reports with the installed libimobiledevice tools is fine. Device testing is done by the
   user, in batches.
5. **Docs.** A change and the docs it affects (`docs/CHANGES.md`, `docs/DEVELOPMENT.md`,
   `README.md`) land in the same commit. Claude Code reads the skills through the per-skill
   links in `.claude/skills/`.
6. **Backlog.** `docs/backlog.md` is gitignored and never committed: wherever a kit skill says to
   commit the backlog (a handoff, a CI-failure note, the final commit), update the file and skip
   that commit. Read its "In progress" section at session start. Every change committed without a
   device test is listed under "Awaiting device test"; an item is removed once it has landed and
   been device-tested.
7. **Sessions.** The planner/builder split is for features (a new setting, a port, a change
   across several files). Diagnosing an Instagram break and small fixes stay in one session; hard
   diagnosis may use an Opus subagent. High-risk code here (stays with the planner; builder work
   that touched it gets a planner `/code-review medium` before the next step):
   - the sideload runtime: keychain and app-group fakes, `strlen`/fishhook rebinds, the entrypoint
     and constructor hook install (`Source/Runtime/`, `Source/Hooks/Sideload/`);
   - privacy hooks: seen receipts, Tigon request dropping, Instants seen, tracking strip;
   - settings migrations: `kSettingsVersion` and key migrations in `Source/UI/ThetaSettings.m`;
   - the notification extension: `Source/SideloadNSE/`, the HPKE key files, decrypted banners.
8. **Settings.** Declare a setting once in `THETA_SETTING_KEYS` (`Include/ThetaSettings.h`),
   define it in `+allDefinitions` and place it once in `+pageGroups`
   (`Source/UI/ThetaSettingsRegistry.m`), read it through its constant (`ENABLED(…)`,
   `ThetaSettingChoice(…)`, …), never a string. Keys and choice option ids are stored on devices
   and in exports: never rename one; add a migration and bump `kSettingsVersion`. Settings UI is
   drawn by `THSettingCell`; adding a setting needs no UI code. See
   `docs/DEVELOPMENT.md#settings`.
9. **Instagram versions.** When a new Instagram build is unpacked into `input/`, follow the
   `ig-version-bump` skill (`.agents/skills/ig-version-bump/SKILL.md`, theta's own).

## Deployment

Nothing runs on a server. `./build.sh` injects the dylibs into the decrypted IPA and writes
`output/Instagram_patched.ipa`; the user installs it with a re-signer. A release moves `main` to
a checked `dev` commit; nothing is published. See `docs/deployment.md`.

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
| ipa | `./build.sh` / `./build.sh debug` | `output/Instagram_patched.ipa`; only on a yes in the end-of-session dialog, or when asked |

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

## Decision rounds (theta)

`decision-round` applies with these additions. Explain each choice in Theta or Instagram terms,
with the cost or risk (launch crash, privacy leak, lost settings). In the walk, also cover:

- **Targets.** Every class and selector the step hooks or calls: does it exist on the current
  Instagram build (`compat` command), under which Swift mangled name, and which fallback covers
  older builds? Is it reached through `objc_msgSend` at all, or only Swift-direct / `objc_direct`
  (then which ObjC call on the path can be hooked instead)?
- **Install timing.** Is the surface built before the normal hook pass (needs the constructor)?
- **Behaviour.** What Instagram does with and without the hook, what the user sees, what is sent
  over the network, what happens when Instagram changes the path again.
- **Settings.** New keys (`<area>.<name>`), type, default, page and section, parent, restart
  required, minimum Instagram version. Any rename or meaning change of a stored key or choice id
  is a migration and a `kSettingsVersion` bump.
- **States.** Toggle off, toggle changed while the screen is open, missing class on an older
  build, failure (toast or silent).
- **Process.** High-risk areas touched (Theta rules, 7), new files and where they go, docs to
  update (`docs/CHANGES.md`, `docs/DEVELOPMENT.md`, `README.md`), credit for ported code, what
  the user must try on the device.

Missing input here is usually a newer Instagram build in `input/`, a device log or a crash
report. The handoff is written to the backlog and not committed (Theta rules, 6).

## Session end (theta)

`close-step` applies with these additions.

- **Verify.** There is no `format`, `lint` or `test` command: run `check`. It must report no new
  `compat.py` misses and compile with exactly the six known warnings
  (`docs/DEVELOPMENT.md#building`); a new warning is a failure to fix. Run `baseline` only when the
  user agreed a new miss is fine or the Instagram version changed.
- **Backlog.** Add every change not yet tried on the phone to "Awaiting device test": the commit,
  what to try, and what "works" looks like (including the off state of a toggle).
- **IPA question**, added to the dialog when this session committed changes that ship in the
  dylibs (`Source/`, `Include/`, `Makefile`, `build.sh`, `vendor/`) and wait in "Awaiting device
  test": "Build the IPA to device-test <what>?" Options: **Build it (Recommended):** `ipa`, then
  give the path `output/Instagram_patched.ipa`; **Debug build:** `./build.sh debug`
  (`THETA_DEBUG=1` logging); **Not now:** the changes wait in the backlog for the next batch.
  Do not build the IPA before the dialog unless the user asked for it. Act on the answers in the
  order IPA, release, launch.
- **Release without CI.** Theta has no `ci.yml`, so the release question's first option is always
  **Push dev, move main without CI** (`release.sh --skip-ci <sha>`); the pre-push hook runs the
  check on each push. While the backlog names a pending planner review of commits on `dev`,
  recommend **Push dev only** (`release.sh --dev-only <sha>`): `main` moves at the end of that
  review.
- **Pre-push failure.** `release.sh` exits 3 when the hook rejects the push. Do not touch `main`;
  summarize the cause from the hook output and ask instead of the CI-failure dialog: "The
  pre-push check failed. What now?" Options: **Fix it (Recommended):** fix the cause, commit only
  the fix's files by path and ask the release question again; **Accept the new misses:** only
  when every new entry is a dead fallback or a judged-fine miss: run `baseline`, then release
  again; **Leave it:** record the failure in the backlog and push nothing. Never use
  `--no-verify` unless the user asks for it.
