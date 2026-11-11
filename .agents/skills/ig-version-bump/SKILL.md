---
name: ig-version-bump
description: Check Theta against a new Instagram version. Diff the hooks old→new with compat.py, sort every miss, record the findings in the backlog and update the baseline. Use when a newer decrypted Instagram build is unpacked into input/, or when the user asks what a new Instagram version breaks.
---

# Instagram version bump

The decrypted app and everything read from it stay on this machine (AGENTS.md rule 5). Command
names refer to the Commands table in AGENTS.md; `compat.py` itself is explained in
`docs/DEVELOPMENT.md#checking-a-new-instagram-version`.

1. **Confirm the inputs.** The new app is at `input/Payload/Instagram.app`. Read its version
   (`CFBundleShortVersionString` in `Info.plist`) and check that the binary is decrypted
   (`otool -l … | grep -A4 LC_ENCRYPTION_INFO` shows `cryptid 0`). Ask the user for the path of
   the previous build to diff against; without one, run `compat` on the new build alone and
   compare with the baseline in `.git/theta-compat-baseline.txt`.
2. **Diff.** Run `ig-diff` (old app, new app). Save the output to the scratchpad, not the repo.
3. **Sort every new miss** into one of these:
   - **Dead fallback:** a missing name whose neighbours in the same file or `?:` /
     `ThetaFirstClass(@[...])` chain still resolve. No action; it stays as an older-build fallback.
   - **Swift rename** ("Now Swift: …"): add the mangled name first and keep the old one as a fallback.
   - **Real break:** the class or selector is gone with no replacement that resolves. Needs
     diagnosis: find the new path in the binary (`scripts/objcdump.py`), and check whether the
     replacement is reached through `objc_msgSend` at all.
   - **Resolves but suspect:** hooks that still resolve but whose callers may have turned
     Swift-direct; flag ones in high-risk areas (AGENTS.md rule 9) for a device test.
4. **Ask before fixing.** Present the sorted list to the user with what each break affects
   (feature, setting key, user-visible effect) and ask with AskUserQuestion which to fix now and
   in what order. Renames are mechanical; real breaks are diagnosis (stay in one session, Opus;
   an Opus subagent is fine for a hard one). Privacy-hook breaks come first: a silent break leaks.
5. **Backlog.** Add a section `## Instagram <version> (<date>)` to `docs/backlog.md` with each
   real break and suspect hook as a `- [ ]` item (file, class, selector, what it affects, what is
   known), and the renames done. Dead fallbacks need no entry.
6. **Fix** as decided. Each fix is its own Conventional Commit, e.g.
   `fix(stories): hook the swift seen-state store on 452`.
7. **Baseline.** Once the remaining misses are all dead fallbacks or agreed as fine, run
   `baseline` so the pre-push check measures against the new version. Say which entries the
   baseline now accepts.
8. **Docs.** Update the tested Instagram version in `README.md` and the section heading in
   `docs/CHANGES.md` only after the user confirms the build works on the device; until then, list
   the version check under "Awaiting device test".
9. Finish with the `close-step` skill, ending on its end-of-session dialog (step 7). A run that
   only recorded findings still ends there.
