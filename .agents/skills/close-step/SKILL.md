---
name: close-step
description: Finish a step in Theta. Run the checks, commit, update the backlog and the device-test list, summarize, hand off and ask about the release. Use when a step's work is done.
---

# Close a step

Command names (check, build, ipa, baseline) refer to the Commands table in AGENTS.md.

1. **Verify.** Run `check` (`./scripts/pre-push.sh`): it must report no new `compat.py` misses
   and compile. Compare the warnings with the six known ones (`docs/DEVELOPMENT.md#building`); a
   new warning is a failure to fix. A failure caused by an unrelated existing issue is reported,
   not hidden. Update the compat baseline only when the user agreed a new miss is fine or the
   Instagram version changed.
2. **IPA only for a device test.** When the user will test on the phone (ask if unclear), run
   `ipa` and give the path `output/Instagram_patched.ipa`. Otherwise don't build it.
3. **Commit** every change with a Conventional Commit subject, `type(scope): lowercase summary`,
   usually without a body (AGENTS.md rule 4). Docs changes go in the related commit. Never mention
   device-test status in a commit. Leave no uncommitted or untracked files.
4. **Backlog** (`docs/backlog.md`, local, never committed): update it for any state change, tick
   off finished items, remove the step's handoff from "In progress", and add every change not yet
   tried on the phone to "Awaiting device test": the commit, what to try, and what "works" looks
   like (including the off state of a toggle).
5. **Do not push yet.** That is the question of step 8.
6. **Summarize** what changed, the decisions made, the verification performed, what awaits a
   device test, any gaps, and what's next.
7. **Hand off.** Write the prompt for the next session and always show it in a fenced block, so
   it survives a "no". A new feature starts with a planner session that runs the
   `decision-round` skill; a builder prompt is only for a step whose handoff already holds all its
   decisions. When a builder session touched high-risk code (AGENTS.md rule 9), the next session
   is a planner review: `/code-review medium` on the step's commits, fixing what it confirms,
   before the next step. When the host has the T3 tools, ask with AskUserQuestion, separately
   from and before the release question: "Launch the next session (<what it does>, <model>,
   <effort>) as a new thread on `dev`?" Options:
   - **Launch it (Recommended):** `t3_thread_launch` with the prompt as its `message`, the model
     and effort the handoff names (Opus for a decision round, diagnosis or review; Sonnet at
     medium effort for a build), workspace strategy `root` (the backlog is local to this
     checkout), on `dev`. The new session never pushes unasked. Mention the thread by its `link`.
   - **No:** the user starts it from the fenced prompt.
   When nothing obvious comes next, skip this step and say so.
8. **Ask about the release** with AskUserQuestion, once, after the summary and the handoff. It
   stands on its own. Question: "Release the step's commits?" Options:
   - **Push dev and fast-forward main (Recommended):** note the head as `<sha>`
     (`git rev-parse HEAD`), then `git push origin dev`; the pre-push hook runs the check. If the
     hook is not installed (`.git/hooks/pre-push`), run `./scripts/pre-push.sh` first.
     - **Passed** (the push went through): fast-forward `main` to `<sha>` without leaving `dev`:
       `git fetch . <sha>:main` (git refuses anything but a fast-forward), then
       `git push origin main`. Never `git switch main` and never fast-forward to the current
       `dev`: a launched session may share this checkout and may have committed since.
     - **Failed** (the hook rejected the push): don't touch `main`. Summarize the cause from the
       hook output, then ask with a second AskUserQuestion: "The pre-push check failed. What
       now?" Options: **Fix it (Recommended):** fix the cause, commit only the fix's files by path
       (`git commit <paths>`), and ask this release question again; **Accept the new misses:**
       only when every new entry is a dead fallback or a judged-fine miss: run `baseline`, then
       push again; **Leave it:** record the failure in the backlog and push nothing. Never use
       `--no-verify` unless the user asks for it.
   - **Push dev only:** push `dev` (the hook still runs); `main` stays.
   - **Not now:** push nothing.
   The answer covers this one release, not later pushes. Then stop.
