# Theta — Technical Plan

<!-- Decisions stated as facts; open items go in "Open questions". -->

## Overview

A sideload-only Instagram tweak for iOS, forked from objcmsgSend/theta 1.0.1. It adds privacy, download and interface
options to a decrypted Instagram IPA that is re-signed and sideloaded; there is no jailbreak build and no server.

## Architecture

Two dylibs built with Theos: `Theta.dylib` (hooks, settings UI, media) in the app and
`ThetaNSE.dylib` in the notification extension. Hooks are ObjC method hooks or fishhook
rebinds, never inline patches. The invariants are in `AGENTS.md#architecture`; the source layout
is in `docs/DEVELOPMENT.md#layout`.

## Security

The decrypted IPA, `input/`, `output/` and anything read from them never leave this machine.
Privacy hooks (seen receipts, Tigon request dropping, Instants seen, tracking strip), the
sideload runtime and the notification extension are high-risk code (`AGENTS.md`, Theta rules).

## Features

Everything the fork changes from upstream is listed in `docs/CHANGES.md`.

## Testing

`scripts/pre-push.sh`: `compat.py` hook coverage against the local Instagram build, then a
compile. Behaviour is tested on a real device by the user, in batches.

## Roadmap

Decided work, the open step and changes awaiting a device test live in the local
`docs/backlog.md`.

## Open questions

None.
