#!/usr/bin/env bash
# QA-1 (#250): runs tools/qa/monkey.gd as a child Godot (windowed, --always-on-top, under nice) and says how it ended:
#   CLEAN   the monkey stopped by itself (turns, minutes, the game over, the replay done) and Godot logged no error line
#   ERRORS  it stopped by itself, but Godot logged ERROR / SCRIPT ERROR lines: each distinct one is printed with the gesture before it
#   CRASH   Godot died on a signal: its backtrace (from the run's --log-file), the seed, the last 30 events and the replay command
#   HANG    no new event for --hang seconds (default 60; 300 while the game is still loading; longer, up to 300, while the Mac's
#           1-minute load is above its core count, since a niced Godot then gets frames of tens of seconds): Godot gets SIGSEGV, the
#           one signal its macOS crash handler prints the main thread's stack for, then it is killed
#   STUCK   the monkey tried 40 times to end a turn and the turn never ended (its own verdict, exit 4)
#   EXITED  Godot quit before the monkey's end, with no signal (something closed the game under the hand)
# Usage (from anywhere):
#   tools/qa/run_monkey.sh --seed=7 [--resolution=1280x720] [--ui-scale=125] [--focus=muster] [--turns=N] [--minutes=M] [--fog=off]
#   tools/qa/run_monkey.sh --seeds=1-10 ...        one run per seed, one after another (or --seeds=3,8,21)
#   tools/qa/run_monkey.sh --replay=DIR/events.log  send a run's events again (its seed, window and interface size come from the log)
# Options of its own: --seed(s), --resolution (the window, default 1600x900), --hang=S, --out=BASE (each run gets a folder of its own
# under BASE, default /tmp/ascendant-qa). Every other option goes to the monkey (tools/qa/monkey.gd's header lists them).
# Godot runs under `nice -n 10` (pipeline/LANES.md: the Mac's other work keeps the CPU), with its log in the run's folder
# (--log-file DIR/godot.log), never in the user data folder. One harness window at a time; monkey runs never take the slot.
# Exit: 0 clean, 1 errors, 2 crash, 3 hang, 4 stuck, 5 exited (a batch exits with its worst run).
set -u

GODOT="${GODOT:-/Users/coterboat/Downloads/Godot.app/Contents/MacOS/Godot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BASE="/tmp/ascendant-qa"
RES=""
HANG=60
LOAD_HANG=300
SEEDS=""
REPLAY=""
PASS=()

for a in "$@"; do
	case "$a" in
		--seed=*) SEEDS="${a#*=}" ;;
		--seeds=*)
			r="${a#*=}"
			if [[ "$r" == *-* ]]; then SEEDS="$(seq "${r%-*}" "${r#*-}" | tr '\n' ' ')"; else SEEDS="${r//,/ }"; fi
			;;
		--resolution=*) RES="${a#*=}" ;;
		--hang=*) HANG="${a#*=}" ;;
		--out=*) BASE="${a#*=}" ;;
		--replay=*) REPLAY="${a#*=}"; PASS+=("$a") ;;
		-h|--help) sed -n '2,22p' "$0"; exit 0 ;;
		*) PASS+=("$a") ;;
	esac
done
if [ -n "$REPLAY" ]; then
	if [ ! -f "$REPLAY" ]; then echo "run_monkey: no such log: $REPLAY" >&2; exit 64; fi
	opts="$(grep -m1 -E '^# (f=-?[0-9]+ )?options \{' "$REPLAY")"
	SEEDS="$(printf '%s' "$opts" | sed -nE 's/.*"seed":(-?[0-9]+).*/\1/p')"
	[ -z "$RES" ] && RES="$(printf '%s' "$opts" | sed -nE 's/.*"window":\[([0-9]+),([0-9]+)\].*/\1x\2/p')"
fi
RES="${RES:-1600x900}"
SEEDS="${SEEDS:-1}"
BUILD="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null)@$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)"
git -C "$ROOT" diff --quiet HEAD 2>/dev/null || BUILD="${BUILD}+uncommitted"
if pgrep -f "res://tools/qa/monkey.gd" >/dev/null 2>&1; then
	echo "run_monkey: another monkey is running on this Mac (one harness window at a time): this run goes on anyway" >&2
fi

CHILD=""
cleanup() {
	if [ -n "$CHILD" ] && kill -0 "$CHILD" 2>/dev/null; then kill -9 "$CHILD" 2>/dev/null; fi
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }
NCPU="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 8)"
load1() {
	local l
	l="$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}')"
	[ -z "$l" ] && l="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
	echo "${l:-0}"
}
# The hang limit for base limit $1 at the Mac's load now: x load/cores while the load is above the core count, at most $2 s.
limit_for() {
	awk -v h="$1" -v c="$2" -v l="$(load1)" -v n="$NCPU" 'BEGIN { x = h; if (l > n) x = h * l / n; if (x > c) x = c; if (x < h) x = h; printf "%d", x }'
}
signal_name() {
	case "$1" in 4) echo SIGILL ;; 6) echo SIGABRT ;; 8) echo SIGFPE ;; 9) echo SIGKILL ;; 10) echo SIGBUS ;; 11) echo SIGSEGV ;; 15) echo SIGTERM ;; *) echo "signal $1" ;; esac
}

worst_code=0
worst_sev=-1
code_of() { case "$1" in CLEAN) echo 0 ;; ERRORS) echo 1 ;; CRASH) echo 2 ;; HANG) echo 3 ;; STUCK) echo 4 ;; EXITED) echo 5 ;; esac; }
sev_of() { case "$1" in CLEAN) echo 0 ;; ERRORS) echo 1 ;; EXITED) echo 2 ;; STUCK) echo 3 ;; HANG) echo 4 ;; CRASH) echo 5 ;; esac; }
RESULTS=()

# Godot's crash handler output from a clean log: the signal, the first 24 frames of the C++ backtrace and the GDScript backtrace.
backtrace_of() {
	awk '
		/Program crashed with signal/ { c = 1; print; next }
		c == 1 && /^\[[0-9]+\]/ { n++; if (n <= 24) print; else if (n == 25) print "  ... (the rest of the C++ backtrace in the log)"; next }
		c == 1 && /END OF C\+\+ BACKTRACE/ { print; c = 2; next }
		c == 2 && /GDScript backtrace/ { g = 1 }
		g { print }
		g && /END OF GDSCRIPT BACKTRACE/ { exit }
	' "$1"
}

run_one() {
	local seed="$1"
	local tag="s${seed}_${RES}"
	for a in "${PASS[@]+"${PASS[@]}"}"; do
		case "$a" in
			--ui-scale=*) tag="${tag}_ui${a#*=}" ;;
			--focus=*) tag="${tag}_${a#*=}" ;;
			--fog=off) tag="${tag}_nofog" ;;
			--replay=*) tag="${tag}_replay" ;;
		esac
	done
	local out
	out="$BASE/$(date '+%m%d-%H%M%S')_${tag//,/+}"
	mkdir -p "$out"
	echo "run_monkey: seed $seed, window $RES, build $BUILD, out $out"
	nice -n 10 "$GODOT" --path "$ROOT" --always-on-top --audio-driver Dummy --fixed-fps 60 --resolution "$RES" \
		--log-file "$out/godot.log" -s res://tools/qa/monkey.gd -- --seed="$seed" --out="$out" --build="$BUILD" \
		"${PASS[@]+"${PASS[@]}"}" > "$out/stdout.log" 2>&1 &
	CHILD=$!
	echo "run_monkey: Godot pid $CHILD"
	local verdict="" teardown=0 ready=0 ended=0 started now last limit
	started=$(date +%s)
	while kill -0 "$CHILD" 2>/dev/null; do
		sleep 2
		now=$(date +%s)
		last=$started
		[ -f "$out/events.log" ] && last=$(mtime "$out/events.log")
		[ "$ready" -eq 0 ] && grep -qE '^# f=-?[0-9]+ ready:' "$out/events.log" 2>/dev/null && ready=1
		[ "$ended" -eq 0 ] && tail -c 4000 "$out/events.log" 2>/dev/null | grep -q "MONKEY END" && ended=1
		if [ "$ended" -eq 1 ]; then
			# the monkey has finished but Godot has not exited (seen on macOS, closing its window): not the game's hang
			if [ $((now - last)) -gt 20 ]; then
				echo "run_monkey: the monkey ended but Godot did not exit in 20 s (a teardown hang); killing $CHILD" >&2
				kill -9 "$CHILD" 2>/dev/null
				teardown=1
				break
			fi
			continue
		fi
		[ $((now - last)) -le "$HANG" ] && continue
		limit=$(limit_for "$HANG" 300)
		[ "$ready" -eq 0 ] && limit=$(limit_for "$LOAD_HANG" 600)
		if [ $((now - last)) -gt "$limit" ]; then
			verdict="HANG"
			echo "run_monkey: no new event for $((now - last)) s (limit $limit s; the 1-minute load is $(load1) on $NCPU cores): SIGSEGV for Godot's own backtrace, then the kill" >&2
			kill -SEGV "$CHILD" 2>/dev/null
			for _ in 1 2 3 4 5; do
				sleep 2
				kill -0 "$CHILD" 2>/dev/null || break
			done
			kill -9 "$CHILD" 2>/dev/null
			break
		fi
	done
	wait "$CHILD" 2>/dev/null
	local code=$?
	CHILD=""
	local log="$out/godot.log"
	[ -s "$log" ] || log="$out/stdout.log"
	local clean="$out/godot.clean.log"
	sed $'s/\x1b\\[[0-9;]*m//g' "$log" > "$clean"
	local said
	said=$(sed -nE 's/^# f=-?[0-9]+ MONKEY END ([a-z_]+):.*/\1/p' "$out/events.log" 2>/dev/null | tail -1)
	if [ -z "$verdict" ]; then
		if grep -q "Program crashed with signal" "$clean"; then verdict="CRASH"
		elif [ -z "$said" ] && [ "$teardown" -eq 0 ] && [ "$code" -gt 128 ]; then verdict="CRASH"
		elif [ -z "$said" ] && [ "$teardown" -eq 0 ]; then verdict="EXITED"
		elif [ "$said" = "stuck" ]; then verdict="STUCK"
		elif grep -qE '^(SCRIPT |USER )?ERROR' "$clean"; then verdict="ERRORS"
		else verdict="CLEAN"
		fi
	fi
	echo "run_monkey: $verdict (exit $code$([ "$teardown" -eq 1 ] && echo ", killed after a teardown hang")), seed $seed, monkey said: ${said:-nothing}"
	case "$verdict" in
		CRASH|HANG)
			backtrace_of "$clean"
			if [ "$verdict" = "CRASH" ] && [ -z "$(backtrace_of "$clean")" ]; then
				echo "Godot died on $(signal_name $((code - 128))) with no backtrace in $log: Godot 4.5.1's macOS crash handler doesn't catch it (it does SIGSEGV, SIGILL, SIGFPE and SIGTRAP, not SIGBUS)"
			fi
			echo "--- the last 30 events (seed $seed, $out/events.log):"
			grep -v '^#' "$out/events.log" | tail -30
			echo "--- the last notes (a HOVER-FREED note names #249's class):"
			grep '^#' "$out/events.log" | grep -v ' shot ' | tail -6
			echo "--- replay: tools/qa/run_monkey.sh --replay=$out/events.log"
			;;
		STUCK)
			grep -E '^# f=-?[0-9]+ STUCK' "$out/events.log"
			grep -v '^#' "$out/events.log" | tail -15
			ls "$out/shots" | tail -2 | sed "s|^|shot: $out/shots/|"
			;;
		ERRORS)
			echo "--- the errors (each distinct one once), with the gesture before it, from events.log:"
			grep -E '^# f=-?[0-9]+ (SCRIPT ERROR|ERROR|USER ERROR|SHADER ERROR)' "$out/events.log" | sed -E 's/^# f=-?[0-9]+ //' \
				| awk -F '  \\[after ' '!seen[$1]++' | head -12
			echo "--- in $log:"
			grep -E -A2 '^(SCRIPT |USER )?ERROR' "$clean" | head -24
			;;
		EXITED)
			echo "--- the last 30 events:"
			grep -v '^#' "$out/events.log" | tail -30
			tail -5 "$clean"
			;;
	esac
	[ -f "$out/summary.json" ] && tr -d '\n' < "$out/summary.json" | sed 's/  */ /g' | cut -c1-500 && echo
	echo "RESULT seed=$seed verdict=$verdict window=$RES dir=$out"
	RESULTS+=("$verdict seed=$seed $out")
	if [ "$(sev_of "$verdict")" -gt "$worst_sev" ]; then
		worst_sev=$(sev_of "$verdict")
		worst_code=$(code_of "$verdict")
	fi
	return 0
}

for s in $SEEDS; do
	run_one "$s"
done
if [ "${#RESULTS[@]}" -gt 1 ]; then
	echo "=== ${#RESULTS[@]} runs:"
	printf '  %s\n' "${RESULTS[@]}"
fi
exit "$worst_code"
