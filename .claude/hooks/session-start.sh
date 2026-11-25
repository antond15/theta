#!/usr/bin/env bash
# SessionStart hook: print the state an agent should know first. Output is added to the context
# (capped at 10,000 characters by Claude Code), so it stays small. Never fails the session.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

# One line when a newer kit is installed locally than the one this project was set up with.
# install.sh records the kit's path under ~/.config; silent when it is unknown or the versions match.
lock=.agents/kit.lock
kitfile="${HOME}/.config/ai-workflow-kit/kit-path"
if [[ -f "$lock" && -f "$kitfile" ]]; then
  kitdir="$(head -n 1 "$kitfile")"
  have="$(awk '$1 == "version" { print $2; exit }' "$lock")"
  want="$(head -n 1 "$kitdir/VERSION" 2>/dev/null)"
  if [[ -n "$have" && -n "$want" ]]; then
    IFS=. read -r a1 a2 a3 <<<"$have"
    IFS=. read -r b1 b2 b3 <<<"$want"
    a=$(( 10#${a1:-0} * 1000000 + 10#${a2:-0} * 1000 + 10#${a3:-0} )) 2>/dev/null || a=0
    b=$(( 10#${b1:-0} * 1000000 + 10#${b2:-0} * 1000 + 10#${b3:-0} )) 2>/dev/null || b=0
    ((a < b)) && echo "kit $have installed, $want available: run install.sh --update"
  fi
fi

# One line when the git pre-push hook that guards main is missing (a fresh clone, or a project
# set up before it existed). Only for the top of a work tree that has the kit's hook script.
if [[ -f .claude/hooks/git-pre-push.sh ]] && top="$(git rev-parse --show-toplevel 2>/dev/null)" &&
   [[ "$(cd "$top" 2>/dev/null && pwd -P)" == "$(pwd -P)" ]]; then
  pp="$(git rev-parse --git-path hooks/pre-push 2>/dev/null)"   # honors core.hooksPath
  if [[ -n "$pp" && ! -e "$pp" ]]; then
    echo "git pre-push hook missing ($pp): pushes to main are not blocked; run install.sh --update on this project"
  elif [[ -n "$pp" && ! -x "$pp" ]]; then
    echo "git pre-push hook not executable ($pp): git skips it, pushes to main are not blocked; chmod +x it"
  fi
fi

echo "== git status -sb"
git status -sb 2>/dev/null | head -n 20

if [[ -f .github/workflows/ci.yml ]] && command -v gh >/dev/null 2>&1; then
  echo "== last dev CI run"
  gh run list --branch dev --limit 1 2>/dev/null | head -n 3
fi

if [[ -f docs/backlog.md ]]; then
  echo "== backlog: In progress"
  # Everything after the "## In progress" heading up to the next "## " heading or the end.
  awk '/^## In progress/ { on = 1; next } on && /^## / { exit } on' docs/backlog.md | head -c 2000
fi
exit 0
