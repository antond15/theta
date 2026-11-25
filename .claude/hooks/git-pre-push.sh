#!/usr/bin/env bash
# git pre-push hook for every agent and every host: rejects each update whose remote ref is
# refs/heads/main (a deletion included), on any remote, unless AI_KIT_RELEASE=1 is set.
# close-step's release.sh sets it only on its main push, after CI passed or the user ordered
# --skip-ci. A --mirror or --prune push is rejected too (see below). Everything else passes.
# Agents never pass --no-verify and never set AI_KIT_RELEASE themselves; the user's own
# terminal push to main needs `git push --no-verify`.
# It runs through the shim install.sh puts in $(git rev-parse --git-common-dir)/hooks/pre-push.
# Git gives the remote name and URL as $1 $2 and one line per ref on stdin:
#   <local ref> <local sha> <remote ref> <remote sha>
# Exit 1 rejects the whole push, stderr is the reason.
blocked=0
# shellcheck disable=SC2034  # remote_sha is read only to keep the fields in place
while read -r local_ref local_sha remote_ref remote_sha || [[ -n "${remote_ref:-}" ]]; do
  [[ "${remote_ref:-}" == refs/heads/main ]] || continue
  [[ "${AI_KIT_RELEASE:-}" == 1 ]] && continue
  what="update"; [[ "${local_sha:-}" =~ ^0+$ ]] && what="deletion"
  echo "pre-push: rejected the $what of main on ${1:-the remote} (${local_ref:-?} -> $remote_ref)." >&2
  blocked=1
done
# Git leaves out of stdin the deletions that --mirror and --prune make (they have no local ref),
# so such a push could delete main unseen. Its mode is read from the arguments of the git process
# that runs this hook: the nearest ancestor named git, at most 8 levels up (a hook manager or a
# shell layer may sit between git and this script). The last of --prune/--no-prune and of
# --mirror/--no-mirror wins, as in git, and remote.<name>.mirror counts. When no git ancestor is
# found, or its arguments cannot be read (no /proc and no ps), the push is rejected: the mode is
# unknown. A git alias that expands to a mirror or prune push is not visible in those arguments
# (a known gap).
proc_ppid() { # $1 pid: its parent pid, from /proc or ps
  local s st pp
  if [[ -r "/proc/$1/stat" ]] && s="$(cat "/proc/$1/stat" 2>/dev/null)" && [[ -n "$s" ]]; then
    read -r st pp _ <<<"${s##*) }"   # after "(comm) ": state, then the parent pid
    echo "$pp"
  else ps -o ppid= -p "$1" 2>/dev/null | tr -d ' '; fi
}
proc_comm() { # $1 pid: its command name without a directory
  local s c
  if [[ -r "/proc/$1/stat" ]] && s="$(cat "/proc/$1/stat" 2>/dev/null)" && [[ -n "$s" ]]; then
    s="${s#*(}"; echo "${s%)*}"
  else c="$(ps -o comm= -p "$1" 2>/dev/null)"; c="${c%"${c##*[![:space:]]}"}"; echo "${c##*/}"; fi
}
if [[ "${AI_KIT_RELEASE:-}" != 1 ]]; then
  gitpid="" pid="$PPID" depth=0
  while [[ "$pid" =~ ^[0-9]+$ ]] && ((pid > 1 && depth < 8)); do
    if [[ "$(proc_comm "$pid")" == git ]]; then gitpid="$pid"; break; fi
    pid="$(proc_ppid "$pid")"; depth=$((depth + 1))
  done
  args=""
  if [[ -n "$gitpid" ]]; then
    [[ -r "/proc/$gitpid/cmdline" ]] && args="$(tr '\0' '\n' < "/proc/$gitpid/cmdline" 2>/dev/null)"
    [[ -n "$args" ]] || args="$(ps -ww -o args= -p "$gitpid" 2>/dev/null | tr ' ' '\n')"
  fi
  mirror=0 prune=0 skip=0
  while IFS= read -r a; do
    if ((skip)); then skip=0; continue; fi   # the value of -o / --push-option is not a flag
    case "$a" in
      --) break ;;
      -o|--push-option) skip=1 ;;
      --mirror) mirror=1 ;; --no-mirror) mirror=0 ;;
      --prune) prune=1 ;; --no-prune) prune=0 ;;
    esac
  done <<<"$args"
  [[ "$(git config --bool --get "remote.${1:-}.mirror" 2>/dev/null)" == true ]] && mirror=1
  if [[ -z "$gitpid" ]]; then
    echo "pre-push: rejected: no git process found among this hook's ancestors (8 levels), so a --mirror or --prune push that deletes main cannot be ruled out." >&2
    blocked=1
  elif [[ -z "$args" ]]; then
    echo "pre-push: rejected: cannot read this push's arguments (no /proc, no ps), so a --mirror or --prune push that deletes main cannot be ruled out." >&2
    blocked=1
  elif ((mirror || prune)); then
    echo "pre-push: rejected a --mirror or --prune push to ${1:-the remote}: git hides the deletions it makes from this hook, so it could delete main." >&2
    blocked=1
  fi
fi
if ((blocked)); then
  echo "pre-push: main moves only through close-step's release.sh, after the user approves." >&2
  echo "pre-push: agents never use --no-verify. To push main yourself, from your own terminal: git push --no-verify ..." >&2
fi
exit "$blocked"
