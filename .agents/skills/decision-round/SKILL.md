---
name: decision-round
description: Ask the user for a decision before changing anything not already decided. Use before any decision, major change, or whenever unsure; as the planner model, before handing a feature step to the builder model, to ask every core decision of the step first.
---

# Decision round

Never decide silently, even on small things the backlog doesn't cover.

1. **Explain in the message** in plain language: what the thing is in Theta or Instagram, a
   concrete example, the effect with and without it, and the cost or risk (launch crash, privacy
   leak, lost settings). Concise pros and cons per option.
2. **Ask with the interactive question tool** (AskUserQuestion). Put the recommended option first,
   labelled "(Recommended)". Keep the long explanation in the message, but make each question
   stand on its own, since the dialog may hide the message. Up to four questions per call, as many
   calls as needed.
3. **Wait** for the answers. If the user asks a clarifying question inside an answer, answer it
   fully in chat and re-ask only that question. Read answers typed into "Other" literally; they
   often change the option.

## When running as the planner

Features (a new setting, a port from another fork, a change across several files) are planned by
the planner (Opus) and built by the builder (Sonnet) in a fresh session (AGENTS.md rule 9). The
builder should meet only the small questions that appear while writing code. A builder session
that opens with a list of core questions means the planner's round failed.

### Before asking: walk the build

Walk through the build as the builder will, in order, and write down every choice it meets.
Cover at least:

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
- **Process.** High-risk areas touched (AGENTS.md rule 9), new files and where they go, docs to
  update (`docs/CHANGES.md`, `docs/DEVELOPMENT.md`, `README.md`), credit for ported code, what
  the user must try on the device.

Then draft the first reply a builder session would send after reading the handoff. Every question
in that draft must be answered before the handoff.

### Asking

- Ask the user about each choice with a visible effect, a privacy or data consequence or a real
  trade-off. Many questions are better than a builder session discovering them.
- Settle purely technical internals yourself and write each in the handoff with a one-line
  reason, so the user can object there.
- When a choice depends on input that isn't available yet (a newer Instagram build in `input/`,
  a device log, a crash report), the step is not ready. Record what is missing in the backlog and
  stop. Never hand an input-dependent decision to the builder.
- Never write "ask before deciding X" or "especially X" in a handoff or prompt: a question you
  can name is a question to ask now.

### Handing off

After the answers, stop building:

1. Write the handoff in `docs/backlog.md` under "In progress" (the template is in the comment
   there): what the step changes, decisions asked, decisions settled by the planner (each with its
   reason), and what the step must not do. "Open questions" must be empty. The backlog is
   gitignored: do not commit it.
2. Write the prompt for a fresh builder session: the step, the docs and sections to read, what to
   do, and when to stop. It states that the core decisions are in the "In progress" handoff in
   `docs/backlog.md`. The builder may ask the user small questions that only appear while coding;
   a new question about which hook to use, privacy, stored settings or a visible behaviour means
   the planner missed it: the builder stops, records it under "In progress" and tells the user to
   take it to a planner session. Always show the prompt in a fenced block, so it survives a "no".
3. When the host has the T3 tools, ask with AskUserQuestion: "Launch the builder session for
   <step> (Sonnet, medium effort) as a new thread on `dev`?" Options: **Launch it
   (Recommended):** `t3_thread_launch` with the prompt as its `message`, Sonnet at medium effort,
   workspace strategy `root` (the backlog is local, so the thread must use this checkout), on
   `dev`; the new session never pushes unasked; mention the thread by its `link`. **No:** the user
   starts it from the fenced prompt. Without T3 tools, skip the dialog.
   Then stop, even if the user's prompt listed build steps.

**Tiny steps:** when the decided work turns out tiny (a one-line fix plus a check), say how small
it is and offer to build it in this session instead of handing off.

When a builder's question comes back to the planner, answer it in a decision round and add the
missed area to the walk above if it is not covered.

High-risk code (AGENTS.md rule 9) stays with the planner: do not hand it off.
