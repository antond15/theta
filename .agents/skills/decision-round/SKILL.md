---
name: decision-round
description: Planner only. Before handing a step to the builder, walk the build, ask the user every core decision, write the handoff in the backlog and give the builder prompt. Builders never run this; a builder that meets a core question stops and records it.
---

# Decision round (planner)

The planner (see the Models table in AGENTS.md) asks as many of the step's decisions as it can;
the builder builds and should meet only the small questions that appear while writing code. A
builder session that opens with a list of core questions means this round failed. How to ask is
in AGENTS.md, Working rules, Decisions. Terse questions were rejected ("I have no idea what …
means"), so explain fully.

## Walk the build

Walk through the build as the builder will, in order, and write down every choice it meets:

- **Inputs.** Every input the step consumes (files, rows, fields, API responses, formats, units,
  signs, zero and empty values, records the code cannot handle). For an import, the mapping of
  every record type to the data model, including the odd ones.
- **Data model.** Tables, columns, enums, migrations, identity and dedup keys, what is stored
  versus computed, what remembers a choice for next time.
- **Math, units and dates.** The unit or currency of each value, conversions, rounding, time
  zones, how the result must match an external source of truth.
- **Flows.** Where the feature lives (route, navigation), preview, commit, edit, delete, undo,
  and how they interact with existing data and features.
- **States.** Empty, invalid, duplicate, partial and error states; what blocks versus warns.
- **Process.** New dependencies, design flow (new surface or extension), tests, docs to update.

Then draft the first reply a builder would send after reading the handoff. Every question in
that draft is asked now. Ask in as many calls as needed: many questions now beat a builder
discovering them. Do not write "ask before deciding X" in a handoff or prompt: a question you can
name is a question to ask now.

**Missing input** (a sample file, an API response, an account detail): the step is not ready.
Record what is missing and stop; a planner session runs this round once the input exists. Never
pass an input-dependent decision to the builder.

**High-risk code** (auth, encryption, keys, money math, migrations) is not handed off; the
planner builds it. Name the one fact the change is safe because of and prove it with a small
script or test that runs the real code; write "unproven" if it could not be proven.

**Tiny steps** (a one-line fix plus a small check): say how small it is and offer to build it in
this session, since a fresh session would spend more re-reading than building.

When a question comes back from a builder, answer it in a round and add the missed area to the
walk above if it is not covered.

## Handing off

The planner stops after the handoff, even if the user's prompt listed build steps: the planner
answered the questions and then built everything itself before, and the user asked for a
handoff every time (long sessions also resend their whole history).

1. Write the handoff under "In progress" in `docs/backlog.md`, 300 to 600 words:

```markdown
**<Step title>** (decided <date>, base <short sha>, not started). One paragraph: what the step
changes and where.

Next session: <role: builder | planner review>.

Touch points:
- <path:line>: <what to change or read there>

Decisions asked:
- <each answer the user gave, stated as a fact>

Settled by the planner (object here if wrong):
- <technical choice>. Reason: <one line>.
- UI process (UI projects): <new surface | extension>, then `verify-ui`.

Must not: <what the step must not do>.

Done when:
- `<exact command>` <expected result>

Open questions: none.
```

   "Open questions" must be empty. Name the next session by role only; the model comes from the
   Models table.
2. Commit it alone as `docs(backlog): hand off <step>`.
3. Write the prompt for a fresh builder session and show it in a fenced block:

```
Build <step>. Read AGENTS.md and the "In progress" handoff in docs/backlog.md (grep the heading,
read that range only); the core decisions are there. <Docs and sections to read.> <What to do.>
Work on `dev`. For a bug with a cheap local test target, write the failing test first; skip that
when the test would be expensive, flaky or need heavy setup. UI (UI projects): <new surface |
extension>; check it in the in-app browser with the verify-ui skill. If a core question comes up
(data model, math, input mapping, security, a visible flow), stop, record it under
"In progress" and tell me to take it to a planner session. Finish with the close-step skill.
```

4. Finish with the `close-step` skill, with that prompt as the next prompt. Then stop, even if
   the user's prompt listed build steps.
