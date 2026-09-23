#!/usr/bin/env bash
# The suite every refactor step must keep green (LIVE_SIM_UNIFICATION_PLAN.md 3.1):
#   1. refresh Godot's import + global class cache (it goes stale and breaks parsing)
#   2. engine lint
#   3. RunAllTests (headless)
#   4. LiveSmoke — headless CombatScene (once debug/tests/LiveSmoke.tscn exists)
# Fails on any lint error, test failure, or `SCRIPT ERROR` in Godot's output.
set -u
cd "$(dirname "$0")/.."

GODOT="${GODOT:-}"
if [ -z "$GODOT" ]; then
	if command -v godot >/dev/null 2>&1; then GODOT="$(command -v godot)"
	elif [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then GODOT=/Applications/Godot.app/Contents/MacOS/Godot
	else echo "run_checks: set GODOT=/path/to/godot" >&2; exit 2; fi
fi

LOG_DIR="$(mktemp -d)"
status=0

"$GODOT" --headless --path . --import >"$LOG_DIR/import.log" 2>&1 || { echo "run_checks: import failed (see $LOG_DIR/import.log)"; status=1; }

python3 tools/lint/lint_engine.py || status=1

run_scene() {  # $1 = label, $2 = scene path
	local log="$LOG_DIR/$1.log"
	"$GODOT" --headless --path . "$2" >"$log" 2>&1
	local rc=$?
	grep -E 'passed, [0-9]+ failed|LiveSmoke:' "$log" | tail -5
	if [ $rc -ne 0 ]; then echo "run_checks: $1 exited $rc (log: $log)"; status=1; fi
	if grep -q 'SCRIPT ERROR' "$log"; then
		echo "run_checks: $1 printed SCRIPT ERROR (log: $log):"
		grep -A2 'SCRIPT ERROR' "$log" | head -20
		status=1
	fi
}

run_scene tests res://debug/tests/RunAllTests.tscn
if [ -f debug/tests/LiveSmoke.tscn ]; then
	run_scene livesmoke res://debug/tests/LiveSmoke.tscn
fi

if [ $status -eq 0 ]; then echo "run_checks: OK"; else echo "run_checks: FAILED"; fi
exit $status
