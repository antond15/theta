#!/usr/bin/env bash
# Local pre-push check: hook coverage against the local Instagram build, then a compile.
#
#   ln -s ../../scripts/pre-push.sh .git/hooks/pre-push   # install as a git hook
#   ./scripts/pre-push.sh                                  # run by hand
#   ./scripts/pre-push.sh --update-baseline                # accept the current compat.py misses
#
# compat.py: needs input/Payload/Instagram.app (skipped with a notice if it is missing). It
# already reports a few misses on a current build, so this compares its MISSING / UNRESOLVED
# entries (file, class, selector; line numbers ignored) against a baseline kept in
# .git/theta-compat-baseline.txt and fails only on new ones. The first run creates the baseline.
#
# Compile: `gmake clean && gmake` of the working tree, the same compile ./build.sh runs. Fails on
# a compile error. The decrypted IPA never leaves this machine.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
cd "$REPO_DIR"

APP="input/Payload/Instagram.app"
BASELINE="$(git rev-parse --git-path theta-compat-baseline.txt)"
EXPECTED_WARNINGS=6

log() { echo "[pre-push] $*"; }

update_baseline=0
[[ "${1:-}" == "--update-baseline" ]] && update_baseline=1

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Prints one line per MISSING / UNRESOLVED entry: "<file>  [<status>]  <class>  <selector>".
compat_misses() {
	awk '
		/^={10,}$/ { next }
		/^(MISSING|UNRESOLVED):/ { section = 1; next }
		/^[A-Z][A-Za-z ,\/-]*:/ || /^Class lookups/ { section = 0; next }
		!section { next }
		/^[^ ]/ { file = $1; next }
		/^  :[0-9]+ \[/ { sub(/^  :[0-9]+ /, ""); gsub(/  +/, "  "); print file "  " $0 }
	' "$1" | sort -u
}

# 1. Hook coverage
if [[ -d "$APP" ]]; then
	log "compat.py against $APP"
	./scripts/compat.py "$APP" > "$tmp/compat.txt" 2>&1
	if ! grep -q "^Hook call sites:" "$tmp/compat.txt"; then
		cat "$tmp/compat.txt"
		log "FAIL: compat.py did not run"
		exit 1
	fi
	grep "^Hook call sites:" "$tmp/compat.txt" | sed 's/^/[pre-push]   /'
	compat_misses "$tmp/compat.txt" > "$tmp/misses.txt"

	if [[ "$update_baseline" -eq 1 || ! -f "$BASELINE" ]]; then
		cp "$tmp/misses.txt" "$BASELINE"
		log "Saved compat baseline ($(wc -l < "$BASELINE" | tr -d ' ') entries) to $BASELINE"
	else
		comm -13 "$BASELINE" "$tmp/misses.txt" > "$tmp/new.txt"
		comm -23 "$BASELINE" "$tmp/misses.txt" > "$tmp/fixed.txt"
		if [[ -s "$tmp/fixed.txt" ]]; then
			log "No longer missing (run with --update-baseline to record):"
			sed 's/^/[pre-push]   /' "$tmp/fixed.txt"
		fi
		if [[ -s "$tmp/new.txt" ]]; then
			log "FAIL: hooks that no longer resolve against $APP:"
			sed 's/^/[pre-push]   /' "$tmp/new.txt"
			log "Fix them, or accept with ./scripts/pre-push.sh --update-baseline"
			exit 1
		fi
	fi
else
	log "Skipping compat.py: no $APP"
fi
[[ "$update_baseline" -eq 1 ]] && exit 0

# 2. Compile
export THEOS="${THEOS:-$HOME/theos}"
make_cmd=make
command -v gmake &>/dev/null && make_cmd=gmake
log "Compiling ($make_cmd clean && $make_cmd)"
$make_cmd clean > /dev/null 2>&1
if ! $make_cmd > "$tmp/build.log" 2>&1; then
	sed 's/\x1b\[[0-9;]*m//g' "$tmp/build.log" | grep -E "error|Error" | head -40
	log "FAIL: compile error"
	exit 1
fi
warnings="$(grep -c "warning:" "$tmp/build.log" || true)"
if [[ "$warnings" -gt "$EXPECTED_WARNINGS" ]]; then
	log "Note: $warnings warnings (a clean build has $EXPECTED_WARNINGS):"
	sed 's/\x1b\[[0-9;]*m//g' "$tmp/build.log" | grep "warning:" | sed 's/^/[pre-push]   /'
fi
log "OK"
