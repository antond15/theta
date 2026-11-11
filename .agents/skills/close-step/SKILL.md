---
name: close-step
description: End a session that changed something or has a next step. Run the checks, clean up what the session started, update the backlog, commit, summarize, write the next prompt, then ask in one dialog what comes next (release, launch the next thread). Use at the end of every session, whatever its kind (build step, review, diagnosis, fix, planner handoff). Not for subagents, and not when nothing changed and nothing comes next (AGENTS.md, Verification).
---

# Close a session

This skill owns every session-end and release rule. Command names (format, check, lint, test,
build) refer to the Commands table in AGENTS.md. **Verify**, **Backlog** and **Commit** apply
when the session changed something; **Clean up** whenever it started a server or tab.

1. **Verify.** Run only the commands the Commands table defines: `format` once, then `check`
   and `lint`; the tests when the affected area has tests; a production `build` when changing
   build configuration, routing, server/client boundaries or environment handling. Skip a
   command the table does not define and say which were skipped. When the project has the
   `verify-ui` skill, UI changes also go through it. Report a failure caused by an unrelated
   existing issue instead of hiding it. Keep local dev data: never wipe a dev database volume
   at the end of a step.
2. **Clean up** only what this session started: its dev servers (stop the background command or
   preview) and the browser tabs it opened. Leave other servers and tabs alone; they may belong
   to another session. Database containers keep running.
3. **Backlog.** Update `docs/backlog.md` for every state change and remove finished items. Remove
   the handoff under "In progress" only when its step is implemented, never a handoff this
   session created. Do this before the final commit so the backlog is part of it.
4. **Commit** with Conventional Commit subjects, `type(scope): lowercase summary`. Commit only
   this session's files, by path. Changes that were already in the worktree at session start
   are not yours: leave them and name them in the summary. Leave no leftovers of your own.
5. **Summary.** What changed, the decisions made, the verification performed, gaps, and what
   comes next. Each verification claim states its level: claimed, pointed at `file:line`,
   reasoned through, ran it (command and result) or reproduced in the app. A check this session
   did not run is labelled "claimed" or listed under gaps, never presented as done.
6. **Next prompt.** Write the prompt for the next session and show it in a fenced block, so it
   survives a "no". A new step starts with a planner session running `decision-round`; a builder
   prompt is only for a step whose handoff holds all its decisions. Name the next session by
   role (planner, builder, mechanical); model and effort come from the Models table in
   AGENTS.md. When a builder session touched high-risk code (auth, encryption, keys, money math,
   migrations), the next session is a planner review: `/code-review medium` on the `dev` branch
   while it is ahead of `main`, fixing what it confirms. Name the one fact the change is safe
   because of and prove it with a small script or test that runs the real code; write
   "unproven" if it could not be proven. When nothing obvious comes next, say so
   and write no prompt.
7. **Dialog.** Always last: one `AskUserQuestion` call holding each question below whose
   condition holds, each standing on its own (the dialog may hide the message). For each
   question left out, say in one line which and why (e.g. "No release question: `dev` is level
   with `main`"); when none holds, say so. A project may add its own questions. Never end with
   a plain-text question or with nothing. "Stop" anywhere means stop after this dialog.
   - **Release**, when `dev` has commits that `origin/dev` or `origin/main` lacks
     (`git rev-list --count origin/dev..dev`, `git rev-list --count origin/main..dev`; a missing
     remote branch counts as all of `dev`), whoever made them, also when `dev` is level with
     `origin/dev` but ahead of `main` (e.g. after a clean planner review that followed "push
     dev only"): "Release `dev` (<n> commits not on `origin/dev`, <m> not on `main`)?" Options:
     **Push, watch CI, move main (Recommended):** see **Release**; **Push dev only:** no CI
     watch, `main` stays; **Not now:** push nothing. When this session's builder work touched
     high-risk code, or the backlog names a pending planner review of commits on `dev`,
     recommend **Push dev only** instead and say why: `main` moves at the end of the planner
     review. A project without `.github/workflows/ci.yml` has no CI result to
     wait for: replace the first option with **Push dev, move main without CI**, which is the
     user's explicit order. When the user ordered a move without CI in this session, the
     question reads "Move main to <sha> without CI, as you asked?" Approval covers this one
     release. The user can always push from their own terminal; the agent's push guard only
     covers the agent.
   - **Launch**, when there is a next prompt and the host has the T3 tools: "Launch the next
     session (<what it does>, <model>, <effort>) as a new thread?" Options: **Launch it
     (Recommended):** `t3_thread_launch` with the prompt as its `message`, model and effort from
     the Models table for that role, workspace strategy `root`, and `instanceId` (the provider
     instance that lists the model in `orchestrator_capabilities`, usually `claudeAgent` for
     Claude models; without it the launch fails with "Expected string at
     modelSelection.instanceId"), and mention the thread by its `link`; **No:** the user starts
     it from the fenced prompt. A launch is not given `dev` as a parameter, so the prompt text
     must say "Work on `dev`".
8. **Release.** Act on the answers in this order, then **Launch**; never launch before the
   release result is final, because a launched session may commit to the same checkout.
   - Capture `sha=$(git rev-parse HEAD)` before pushing. Run
     `bash .agents/skills/close-step/release.sh [--dev-only] <sha>` once, as a background
     command, and wait for it (`t3_background_wait` or the host's equivalent; never poll).
     The script pushes `dev`, waits for the CI run of that commit, watches it, and moves `main`
     to exactly that commit only when it passed (no branch switch, no merge commit). It prints
     the failed-log tail on red and a one-line summary at the end. Use `--dev-only` for
     **Push dev only**.
     `--skip-ci` moves `main` to the commit without a CI result; use it only for the explicit
     order described under the Release question, and record it in the summary ("main moved
     without CI, as the user ordered").
   - **Exit 0:** report it. **Exit 2** (a precondition failed, e.g. no `ci.yml`): report the
     script's message and offer the no-CI release only as the Release question describes.
     **Exit 1 (red) or 4 (no run appeared):** do not
     touch `main`; summarize the cause from the script's output and ask with a second dialog,
     "CI failed on `dev`. What now?" Options: **Fix it (Recommended):** fix the cause, commit
     only the fix's files by path, and release again; **Re-run the failed jobs:** for a flaky or
     infrastructure failure, `gh run rerun <id> --failed`, then run `release.sh` again with
     the same commit as one background command (it watches that run, moves `main` on green and
     returns to this dialog on red); **Leave it:** record the failure in
     `docs/backlog.md`, commit only that file as `docs(backlog): note ci failure on <sha>`, and
     do not push. Never move `main` past a failed run, whatever the answer.
     **Exit 3 (a push was rejected by a local pre-push hook or the remote):** `main` stays
     where it was; show the script's message and ask with its own dialog, "The push was
     rejected (hook or remote). What now?" Options: **Fix it (Recommended):** fix the cause
     (the hook's complaint, or the remote's reason) and release again; **Leave it:** record
     the rejection in `docs/backlog.md` (a backlog commit follows the Backlog rule of
     AGENTS.md) and do not push. There is no re-run option.
   - Then, if the user chose to launch, launch: after the release result is final, including a
     re-run or fix that came out of the failure dialog. Then stop.

A commit pushed without approval was rejected before, and so was a question after every commit:
commit freely on `dev` and ask once, here.

If `/code-review` is missing, review the diff yourself. Without T3 tools, show the fenced prompt and stop.
