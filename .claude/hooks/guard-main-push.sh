#!/usr/bin/env bash
# PreToolUse hook for Bash: allow a `git push` only when it is a plain push to dev. Everything
# else that pushes is denied, because main moves only through close-step's release.sh (which
# the user approved and which waits for CI). Defense in depth: AGENTS.md and close-step carry
# the same rule in prose. Known gap: git aliases and scripts other than release.sh are not
# seen; branch protection on main with required checks is the real wall.
# Allowed forms (optionally with -u or --set-upstream before origin):
#   git push origin dev
#   git push origin <sha-or-HEAD>:dev
#   git push origin <sha-or-HEAD>:refs/heads/dev
# A chain (&&, ||, ;, |) is checked segment by segment; one bad push blocks the command.
# Quoted text is not treated as data: inside a Claude session an inline
# `echo '…git push origin main…' | bash guard` is itself blocked, which also keeps
# `bash -c "git push origin main"` blocked. Test the guard with tests/guard.sh of the kit, or
# pipe a JSON file in: `bash .claude/hooks/guard-main-push.sh < case.json`. Inside a session,
# write that case file with the editor/Write tool, not a shell echo or python (the shell text
# itself would be blocked), then pipe it in.
# Exit 2 blocks, stderr is the reason. Does not need jq or python3: without them it cuts the
# command out of the raw JSON, and a push it cannot read counts as not allowed.
input="$(cat)"

cmd=""
if command -v python3 >/dev/null 2>&1; then
  cmd="$(printf '%s' "$input" | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)" || cmd=""
fi
if [[ -z "$cmd" ]] && command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || cmd=""
fi
if [[ -z "$cmd" ]]; then
  echo "guard-main-push: no python3 or jq, reading the raw hook input" >&2
  cmd="$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -n 1)"
  [[ -n "$cmd" ]] || cmd="$input"
fi

reason="main moves only through close-step's release.sh; other pushes need the user to run them"
ref_ok='^(dev|(HEAD|[0-9a-fA-F]{4,40}):(dev|refs/heads/dev))$'

while IFS= read -r seg; do
  [[ "$seg" =~ (^|[^[:alnum:]_./-])git([[:space:]]+[^[:space:]]+)*[[:space:]]+push([[:space:]]|$) ]] || continue
  seg="${seg//[\"\']/}"
  # Output redirections (2>&1, >/dev/null, > log) change nothing about what is pushed.
  seg="$(printf '%s' "$seg" | sed -E 's/[0-9]*(>>|>)&?[[:space:]]*[^[:space:]]+//g')"
  read -ra tok <<<"$seg"
  # A commit message may mention git push; the commit itself pushes nothing.
  [[ "${tok[0]-}" == git && "${tok[1]-}" == commit ]] && continue
  ok=0
  if [[ "${tok[0]-}" == git && "${tok[1]-}" == push ]]; then
    rest=("${tok[@]:2}")
    if [[ "${rest[0]-}" == -u || "${rest[0]-}" == --set-upstream ]]; then rest=("${rest[@]:1}"); fi
    if [[ ${#rest[@]} -eq 2 && "${rest[0]}" == origin && "${rest[1]}" =~ $ref_ok ]]; then ok=1; fi
    # A remote.origin.push setting can map a plain `dev` push onto main; require <src>:dev then.
    if ((ok)) && [[ "${rest[1]}" == dev ]] && [[ -n "$(git config --get-all remote.origin.push 2>/dev/null)" ]]; then
      echo "Blocked: remote.origin.push is set, so 'git push origin dev' may land elsewhere; use 'git push origin HEAD:refs/heads/dev'." >&2
      exit 2
    fi
  fi
  if ((!ok)); then echo "Blocked: '$(echo "$seg" | head -c 120)'. $reason" >&2; exit 2; fi
done < <(printf '%s\n' "$cmd" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/[;|]/\n/g')

exit 0
