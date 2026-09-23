#!/usr/bin/env bash
# The suite every refactor step must keep green (LIVE_SIM_UNIFICATION_PLAN.md 3.1):
#   1. refresh Godot's import + global class cache (it goes stale and breaks parsing)
#   2. engine lint + every script compiles
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

TIMEOUT_S="${RUN_CHECKS_TIMEOUT:-300}"  # per Godot run; a hung suite must not wedge the gate

# Run a command with output to $1, killing it after TIMEOUT_S (macOS has no `timeout`).
run_logged() {  # $1 = log file, rest = command
	local log="$1"; shift
	"$@" >"$log" 2>&1 &
	local pid=$! waited=0
	while kill -0 "$pid" 2>/dev/null; do
		if [ "$waited" -ge "$TIMEOUT_S" ]; then
			kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
			echo "run_checks: TIMEOUT after ${TIMEOUT_S}s: $* (log: $log)"
			return 124
		fi
		sleep 1; waited=$((waited + 1))
	done
	wait "$pid"
}

"$GODOT" --headless --path . --import >"$LOG_DIR/import.log" 2>&1 || { echo "run_checks: import failed (see $LOG_DIR/import.log)"; status=1; }

python3 tools/lint/lint_engine.py || status=1

# Every script must compile — tests only load the scripts they reach.
run_logged "$LOG_DIR/load_all.log" "$GODOT" --headless --path . --script res://tools/lint/load_all_scripts.gd
if [ $? -ne 0 ] || grep -q 'SCRIPT ERROR\|Parse Error' "$LOG_DIR/load_all.log"; then
	echo "run_checks: scripts failed to compile (log: $LOG_DIR/load_all.log):"
	grep -E 'LOADFAIL|Parse Error|Compile Error' "$LOG_DIR/load_all.log" | head -20
	status=1
else
	grep 'load_all:' "$LOG_DIR/load_all.log"
fi

run_scene() {  # $1 = label, $2 = scene path
	local log="$LOG_DIR/$1.log"
	run_logged "$log" "$GODOT" --headless --path . "$2"
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
