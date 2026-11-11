# Deployment

Theta never runs on a server. A release is a `dev` commit that passed the pre-push check, with
`main` fast-forwarded to it; the user turns it into an IPA and sideloads it. Nothing is published
or uploaded: the decrypted IPA and everything built from it stay on this machine.

## First-time setup

Toolchain (`./scripts/setup-toolchain.sh`), the patched SDK and a decrypted Instagram IPA in
`input/`: see `README.md#requirements` and `docs/DEVELOPMENT.md#toolchain`. Install the pre-push
hook: `ln -s ../../scripts/pre-push.sh .git/hooks/pre-push`.

## Deploy flow

1. Work lands on `dev`. Pushing it runs the pre-push hook (`scripts/pre-push.sh`): no new
   `compat.py` misses against the local baseline and a clean compile.
2. close-step's release moves `main` to that exact commit without CI
   (`.agents/skills/close-step/release.sh --skip-ci <sha>`); there is no `ci.yml` on purpose.
3. `./build.sh` (or `./build.sh debug`) builds `Theta.dylib` and `ThetaNSE.dylib`, injects them
   into the decrypted IPA and writes `output/Instagram_patched.ipa`.
4. The user installs it with Sideloadly, AltStore, SideStore or TrollStore (`README.md#install`)
   and device-tests the batch listed under "Awaiting device test" in `docs/backlog.md`.

## Migrations

Settings stored on the device are migrated in `Source/UI/ThetaSettings.m` on launch, gated by
`kSettingsVersion` (`docs/DEVELOPMENT.md#settings`).

## Logs

Release builds log nothing. A `./build.sh debug` build logs through `THDebugLog`; read it from the
phone over USB with the installed libimobiledevice tools (`idevicesyslog`, crash reports).

## Rollback

Reinstall an IPA built from an earlier commit; settings migrations only move forward, so check
`kSettingsVersion` before going back past one.
