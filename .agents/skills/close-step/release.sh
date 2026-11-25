# Release a dev commit: push dev, wait for its CI run, move main to that exact commit when green.
#   release.sh [--dev-only | --skip-ci] <sha>
# <sha> is the commit captured BEFORE the push (git rev-parse HEAD). Commits made on dev after
# that (e.g. by a launched session) are neither pushed nor released.
# Only the run of the one workflow named in CI_WORKFLOW gates main; other workflows are ignored.
# --skip-ci moves main to <sha> without a CI result: only when the user ordered it in this
# session, and also the only way to release a project that has no CI workflow file.
# After origin/main moves, the local main ref follows to <sha>: moved directly when no worktree has
# main checked out, fast-forwarded in that worktree when it has no tracked changes, otherwise left
# alone. A missing local main stays missing; a local main with commits not on <sha> is never moved.
# Each case prints a `local main:` line. Local dev is never moved: <sha> is on it, so it is level
# with origin/dev or ahead of it by the later commits, which a `dev:` line counts.
# The last line says what happened: `release: ci.yml run <id> <passed|failed> for <sha>; main
# moved to <sha>` or `main not moved` (the progress frames of `gh run watch` are hidden).
# Run it once as a background command and wait for it; it blocks until the CI result is known.
# Exit: 0 released (or dev pushed with --dev-only), 1 CI failed, 2 bad usage or precondition,
#       3 a push was rejected (local pre-push hook or remote), 4 no CI run appeared for <sha> in time,
#       or the run had no result in time. main moves only on a run whose conclusion is success: a
#       failing `gh run watch` (e.g. a token that cannot read annotations) is checked against the
#       run's own status before it counts as red.
set -euo pipefail

CI_WORKFLOW=ci.yml
WAIT_TRIES="${WAIT_TRIES:-60}"   # wait for the run to appear: tries x seconds (default 5 min)
WAIT_SECONDS="${WAIT_SECONDS:-5}"
POLL_TRIES="${POLL_TRIES:-120}"  # when gh run watch errors: read the run's state, tries x seconds (30 min)
POLL_SECONDS="${POLL_SECONDS:-15}"

dev_only=0 skip_ci=0 sha=""
for arg in "$@"; do
  case "$arg" in
    --dev-only) dev_only=1 ;;
    --skip-ci) skip_ci=1 ;;
    -*) echo "release.sh: unknown flag $arg" >&2; exit 2 ;;
    *) [[ -z "$sha" ]] || { echo "release.sh: more than one sha" >&2; exit 2; }; sha="$arg" ;;
  esac
done
[[ -n "$sha" ]] || { echo "usage: release.sh [--dev-only | --skip-ci] <sha>" >&2; exit 2; }
((dev_only && skip_ci)) && { echo "release.sh: --dev-only and --skip-ci do not combine" >&2; exit 2; }

given="$sha"
sha="$(git rev-parse --verify "$sha^{commit}" 2>/dev/null)" || {
  echo "release.sh: unknown commit '$given'; pass \"\$(git rev-parse HEAD)\". Latest commits:" >&2
  git log --oneline -3 >&2 2>/dev/null
  exit 2
}
git remote get-url origin >/dev/null 2>&1 || { echo "release.sh: no origin remote" >&2; exit 2; }
git merge-base --is-ancestor "$sha" dev || { echo "release.sh: $sha is not on dev" >&2; exit 2; }

if ((!dev_only && !skip_ci)); then
  if ! git cat-file -e "$sha:.github/workflows/$CI_WORKFLOW" 2>/dev/null; then
    echo "release.sh: no .github/workflows/$CI_WORKFLOW in ${sha:0:12}, so there is no CI result to wait for." >&2
    echo "release.sh: to move main anyway, the user must order it; then run with --skip-ci. Nothing pushed." >&2
    exit 2
  fi
  command -v gh >/dev/null || { echo "release.sh: gh is not installed, cannot read CI; nothing pushed" >&2; exit 2; }
fi

# An explicit refspec pushes exactly <sha>, also when origin/dev does not exist yet.
git push origin "$sha:refs/heads/dev" || { echo "release.sh: push of dev failed" >&2; exit 3; }
echo "dev pushed at ${sha:0:12}"
later="$(git rev-list --count "$sha..dev")"
((later == 0)) || echo "dev: $later later commit(s) stay local, not pushed"
if ((dev_only)); then echo "dev only: main not moved"; exit 0; fi

move_main() {
  # AI_KIT_RELEASE=1 lets this one push past the kit's git pre-push hook (.claude/hooks/git-pre-push.sh).
  # No submodule recursion, so no submodule push inherits it.
  AI_KIT_RELEASE=1 git push --recurse-submodules=no origin "$sha:refs/heads/main" || { echo "release.sh: push of main failed (not a fast-forward?)" >&2; exit 3; }
  echo "main is now ${sha:0:12}"
  sync_local_main
}

# Bring the local main ref to <sha> once origin/main is there. Never drops a local commit and never
# touches a worktree with tracked changes; what it cannot do safely it reports. Never fails the
# release: origin/main has already moved.
sync_local_main() {
  local cur extra wt
  if ! cur="$(git rev-parse --verify -q refs/heads/main)"; then
    echo "local main: none, nothing to update"; return 0
  fi
  if [[ "$cur" == "$sha" ]]; then echo "local main: already at ${sha:0:12}"; return 0; fi
  extra="$(git rev-list --count "$sha..$cur" 2>/dev/null || echo "?")"
  if [[ "$extra" != 0 ]]; then
    echo "local main: has $extra commit(s) not on ${sha:0:12}; left at ${cur:0:12}, not moved" >&2
    return 0
  fi
  wt="$(git worktree list --porcelain | awk '/^worktree /{p=substr($0,10)} $0=="branch refs/heads/main"{print p; exit}')"
  if [[ -z "$wt" ]]; then
    if git branch -f main "$sha" >/dev/null 2>&1; then
      echo "local main: moved from ${cur:0:12} to ${sha:0:12}"
    else
      echo "local main: could not move it (git branch -f refused); left at ${cur:0:12}" >&2
    fi
  elif [[ -n "$(git -C "$wt" status --porcelain --untracked-files=no 2>/dev/null || echo x)" ]]; then
    echo "local main: checked out in $wt with local changes; left at ${cur:0:12}. Later: git -C '$wt' merge --ff-only ${sha:0:12}" >&2
  elif git -C "$wt" merge --ff-only -q "$sha" >/dev/null 2>&1; then
    echo "local main: fast-forwarded to ${sha:0:12} in $wt"
  else
    echo "local main: fast-forward in $wt failed; left at ${cur:0:12}. Later: git -C '$wt' merge --ff-only ${sha:0:12}" >&2
  fi
  return 0
}

if ((skip_ci)); then
  echo "--skip-ci: moving main to ${sha:0:12} without a CI result"
  move_main
  echo "release: CI skipped (user order) for ${sha:0:12}; main moved to ${sha:0:12}"
  exit 0
fi

# Wait (bounded) for the $CI_WORKFLOW push run of this exact commit to be created.
run_id=""
for ((i = 0; i < WAIT_TRIES; i++)); do
  run_id="$(gh run list --workflow "$CI_WORKFLOW" --event push --commit "$sha" --limit 1 --json databaseId --jq '.[0].databaseId // empty' 2>/dev/null || true)"
  [[ -n "$run_id" ]] && break
  sleep "$WAIT_SECONDS"
done
[[ -n "$run_id" ]] || { echo "release.sh: no $CI_WORKFLOW run appeared for ${sha:0:12}; main not moved" >&2; exit 4; }

echo "watching run $run_id"
result=""
if gh run watch "$run_id" --exit-status >/dev/null 2>&1; then
  result=success
else
  # A non-zero watch is not proof of red: gh also exits 1 when a token cannot read check-run
  # annotations (HTTP 403), while the run is still going. Read the run's own state; wait
  # (bounded) while it is not completed.
  for ((i = 0; i < POLL_TRIES; i++)); do
    state="$(gh run view "$run_id" --json status,conclusion --jq '.status + " " + .conclusion' 2>/dev/null || true)"
    if [[ "$state" == "completed "* ]]; then result="${state#completed }"; break; fi
    sleep "$POLL_SECONDS"
  done
fi
if [[ "$result" == success ]]; then
  echo "CI passed (run $run_id)"
  move_main
  echo "release: $CI_WORKFLOW run $run_id passed for ${sha:0:12}; main moved to ${sha:0:12}"
elif [[ -z "$result" ]]; then
  echo "release.sh: run $run_id has no result in time (gh run watch failed and the run is not completed); main not moved" >&2
  echo "release: $CI_WORKFLOW run $run_id has no result for ${sha:0:12}; main not moved"
  exit 4
else
  echo "CI ${result:-failed} (run $run_id); main not moved" >&2
  gh run view "$run_id" --log-failed 2>&1 | tail -n 60 >&2 || true
  echo "release: $CI_WORKFLOW run $run_id failed for ${sha:0:12}; main not moved"
  exit 1
fi
