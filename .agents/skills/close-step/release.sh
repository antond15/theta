# Release a dev commit: push dev, wait for its CI run, move main to that exact commit when green.
#   release.sh [--dev-only | --skip-ci] <sha>
# <sha> is the commit captured BEFORE the push (git rev-parse HEAD). Commits made on dev after
# that (e.g. by a launched session) are neither pushed nor released.
# Only the run of the one workflow named in CI_WORKFLOW gates main; other workflows are ignored.
# --skip-ci moves main to <sha> without a CI result: only when the user ordered it in this
# session, and also the only way to release a project that has no CI workflow file.
# The last line says what happened: `release: ci.yml run <id> <passed|failed> for <sha>; main
# moved to <sha>` or `main not moved` (the progress frames of `gh run watch` are hidden).
# Run it once as a background command and wait for it; it blocks until the CI result is known.
# Exit: 0 released (or dev pushed with --dev-only), 1 CI failed, 2 bad usage or precondition,
#       3 a push was rejected (local pre-push hook or remote), 4 no CI run appeared for <sha> in time.
set -euo pipefail

CI_WORKFLOW=ci.yml
WAIT_TRIES="${WAIT_TRIES:-60}"   # wait for the run to appear: tries x seconds (default 5 min)
WAIT_SECONDS="${WAIT_SECONDS:-5}"

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

sha="$(git rev-parse --verify "$sha^{commit}")" || { echo "release.sh: unknown commit" >&2; exit 2; }
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
if ((dev_only)); then echo "dev only: main not moved"; exit 0; fi

move_main() {
  git push origin "$sha:refs/heads/main" || { echo "release.sh: push of main failed (not a fast-forward?)" >&2; exit 3; }
  echo "main is now ${sha:0:12}"
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
if gh run watch "$run_id" --exit-status >/dev/null 2>&1; then
  echo "CI passed (run $run_id)"
  move_main
  echo "release: $CI_WORKFLOW run $run_id passed for ${sha:0:12}; main moved to ${sha:0:12}"
else
  echo "CI failed or was cancelled (run $run_id); main not moved" >&2
  gh run view "$run_id" --log-failed 2>&1 | tail -n 60 >&2 || true
  echo "release: $CI_WORKFLOW run $run_id failed for ${sha:0:12}; main not moved"
  exit 1
fi
