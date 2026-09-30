#!/usr/bin/env bash
# Headless boot of the main scene that actually fails on errors.
# Godot exits 0 even when a script fails to parse or errors at runtime, so this
# runs the boot, shows its output, and exits non-zero if Godot exits non-zero,
# times out, or prints any ERROR / SCRIPT ERROR / USER ERROR line.
# Usage (from anywhere): tools/boot_check.sh [frames, default 120]
set -u

GODOT="${GODOT:-/home/box/playtester/godot/godot}"
FRAMES="${1:-120}"
TIMEOUT_SECS="${BOOT_TIMEOUT:-60}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

timeout "$TIMEOUT_SECS" "$GODOT" --headless --path "$ROOT" --quit-after "$FRAMES" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

if [ "$status" -eq 124 ]; then
	echo "boot_check: FAIL (Godot timed out after ${TIMEOUT_SECS}s)" >&2
	exit 1
fi
if [ "$status" -ne 0 ]; then
	echo "boot_check: FAIL (Godot exited with status $status)" >&2
	exit 1
fi
# Strip ANSI colour codes before matching, in case Godot colours its output.
errors="$(sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -cE '^[[:space:]]*(SCRIPT |USER )?ERROR' || true)"
if [ "$errors" -ne 0 ]; then
	echo "boot_check: FAIL ($errors error line(s) in Godot output)" >&2
	exit 1
fi
echo "boot_check: OK"
