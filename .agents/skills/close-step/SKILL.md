---
name: close-step
description: End a Theta session. Run the checks, commit, update the backlog and the device-test list, summarize, write the next prompt, then ask in one dialog what comes next (launch the next thread, build the IPA, release). Use at the end of every session or thread, whatever its kind (build step, review, diagnosis, fix, planner handoff, version bump, a question answered with changes), not only when a step is done.
---

# Close a session

Every session ends here, not only finished build steps. Command names (check, build, ipa,
baseline) refer to the Commands table in AGENTS.md. Steps 1–4 apply when the session changed
something; skip them otherwise.

1. **Verify.** Run `check` (`./scripts/pre-push.sh`): it must report no new `compat.py` misses
   and compile. Compare the warnings with the six known ones (`docs/DEVELOPMENT.md#building`); a
   new warning is a failure to fix. A failure caused by an unrelated existing issue is reported,
   not hidden. Update the compat baseline only when the user agreed a new miss is fine or the
   Instagram version changed.
2. **Commit** every change with a Conventional Commit subject, `type(scope): lowercase summary`,
   usually without a body (AGENTS.md rule 4). Docs changes go in the related commit. Never mention
   device-test status in a commit. Leave no uncommitted or untracked files.
3. **Backlog** (`docs/backlog.md`, local, never committed): update it for any state change, tick
   off finished items, remove the step's handoff from "In progress", and add every change not yet
   tried on the phone to "Awaiting device test": the commit, what to try, and what "works" looks
   like (including the off state of a toggle).
4. **Do not push or build the IPA yet.** Both are questions of step 7, unless the user already
   asked for the IPA in this session.
5. **Summarize** what changed, the decisions made, the verification performed, what awaits a
   device test, any gaps, and what's next.
6. **Next prompt.** Write the prompt for the next session and always show it in a fenced block,
   so it survives a "no". A new feature starts with a planner session that runs the
   `decision-round` skill; a builder prompt is only for a step whose handoff already holds all its
   decisions. When a builder session touched high-risk code (AGENTS.md rule 9), the next session
   is a planner review: `/code-review medium` on the step's commits, fixing what it confirms,
   before the next step. When nothing obvious comes next, say so and write no prompt.
7. **End-of-session dialog.** Always, as the last thing in the session: one AskUserQuestion call
   holding each question below whose condition holds, each standing on its own (the dialog may
   hide the message). Never ask any of them as a plain-text question. Note the head as `<sha>`
   (`git rev-parse HEAD`) before asking. For each question left out, say in one line which and
   why (e.g. "No release question: `dev` is level with `origin/dev`"); when none holds, say so
   and stop.
   - **Launch**, when step 6 wrote a prompt and the host has the T3 tools: "Launch the next
     session (<what it does>, <model>, <effort>) as a new thread on `dev`?" Options:
     **Launch it (Recommended):** `t3_thread_launch` with the prompt as its `message`, the model
     and effort the handoff names (Opus for a decision round, diagnosis or review; Sonnet at
     medium effort for a build), workspace strategy `root` (the backlog is local to this
     checkout), on `dev`; the new session never pushes unasked; mention the thread by its
     `link`. **No:** the user starts it from the fenced prompt.
   - **IPA**, when this session committed changes that ship in the dylibs (`Source/`,
     `Include/`, `Makefile`, `build.sh`, `vendor/`) and that wait in "Awaiting device test":
     "Build the IPA to device-test <what>?" Options: **Build it (Recommended):** `ipa`, then give
     the path `output/Instagram_patched.ipa`; **Debug build:** `./build.sh debug`
     (`THETA_DEBUG=1` logging); **Not now:** the changes wait in the backlog for the next batch.
   - **Release**, when `dev` is ahead of `origin/dev` (`git rev-list --count origin/dev..dev`),
     whoever made the commits: "Release the <n> unpushed commits on `dev`?" Options in step 8.
   Act on the answers in this order: IPA, release, launch, so a new thread never builds or
   commits in this checkout while the IPA builds or the push runs.
8. **Release** options, as answered in step 7:
   - **Push dev and fast-forward main (Recommended):** `git push origin dev`; the pre-push hook
     runs the check. If the hook is not installed (`.git/hooks/pre-push`), run
     `./scripts/pre-push.sh` first.
     - **Passed** (the push went through): fast-forward `main` to `<sha>` without leaving `dev`:
       `git fetch . <sha>:main` (git refuses anything but a fast-forward), then
       `git push origin main`. Never `git switch main` and never fast-forward to the current
       `dev`: a launched session may share this checkout and may have committed since.
     - **Failed** (the hook rejected the push): don't touch `main`. Summarize the cause from the
       hook output, then ask with a second AskUserQuestion: "The pre-push check failed. What
       now?" Options: **Fix it (Recommended):** fix the cause, commit only the fix's files by path
       (`git commit <paths>`), and ask the release question again; **Accept the new misses:**
       only when every new entry is a dead fallback or a judged-fine miss: run `baseline`, then
       push again; **Leave it:** record the failure in the backlog and push nothing. Never use
       `--no-verify` unless the user asks for it.
   - **Push dev only:** push `dev` (the hook still runs); `main` stays.
   - **Not now:** push nothing.
   The answer covers this one release, not later pushes. Then stop.
