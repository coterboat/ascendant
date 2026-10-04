extends RefCounted
## Base class for tests. Extend it in a file named `test_*.gd` under `tests/`
## and add methods named `test_*`. The runner calls each one on a fresh
## instance; any failed assertion or engine/script error fails that test.
##
## Wall-clock checks (a budget in ms, an overhead ratio) are off by default: a busy machine makes them fail
## at random and hides real failures. They run only with `-- --perf` (or ASCENDANT_PERF=1), on a quiet
## machine. Write such a test as: do the work through best_ms(), check its results with the usual asserts
## (those always run), then assert_perf() the time. Without --perf the work still runs once and its
## results are still checked; the time is only reported as "perf skipped".

## The runner's user argument and the environment variable that turn wall-clock checks on.
const PERF_FLAG := "--perf"
const PERF_ENV := "ASCENDANT_PERF"
## The note assert_perf leaves when wall-clock checks are off (the runner prints and counts these).
const PERF_SKIPPED := "perf skipped (run with --perf)"

var _failures: PackedStringArray = []
var _notes: PackedStringArray = []


## True when wall-clock checks are on: `-- --perf` on the command line, or ASCENDANT_PERF set to anything
## but "", "0", "false" or "no".
static func perf_enabled() -> bool:
	if OS.get_cmdline_user_args().has(PERF_FLAG):
		return true
	var env := OS.get_environment(PERF_ENV).strip_edges().to_lower()
	return not ["", "0", "false", "no"].has(env)


## A wall-clock assertion. With perf checks on it fails the test when `condition` is false (and notes
## "perf ok" when it holds, so a --perf run shows its numbers); otherwise it never fails and notes the
## message as "perf skipped". Put the measured numbers and the budget in the message.
func assert_perf(condition: bool, message: String) -> void:
	if not perf_enabled():
		_notes.append("%s: %s" % [PERF_SKIPPED, message])
	elif condition:
		_notes.append("perf ok: " + message)
	else:
		_fail("perf: " + message)


## The fastest of `runs` timed calls of `work`, in ms, after one untimed warm-up call (so first-call loads
## and caches are not timed). Timing on a shared machine only ever runs slow, so the minimum is the least
## noisy reading. With perf checks off, `work` runs once (its results still get checked) and that one
## reading is returned.
func best_ms(work: Callable, runs: int = 5) -> float:
	var count := maxi(1, runs)
	if perf_enabled():
		work.call()
	else:
		count = 1
	var best := INF
	for i in count:
		var t0 := Time.get_ticks_usec()
		work.call()
		best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
	return best


## `runs` with perf checks on, 1 without: for timing loops that best_ms() doesn't fit.
static func perf_runs(runs: int) -> int:
	return maxi(1, runs) if perf_enabled() else 1


func assert_true(condition: bool, message: String = "") -> void:
	if not condition:
		_fail("expected true" + _suffix(message))


func assert_false(condition: bool, message: String = "") -> void:
	if condition:
		_fail("expected false" + _suffix(message))


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if not _same(actual, expected):
		_fail("expected %s, got %s%s" % [var_to_str(expected), var_to_str(actual), _suffix(message)])


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	if _same(actual, unexpected):
		_fail("did not expect %s%s" % [var_to_str(unexpected), _suffix(message)])


func fail(message: String) -> void:
	_fail(message)


func get_failures() -> PackedStringArray:
	return _failures


## Lines the runner prints under the test's result without failing it (e.g. "perf skipped").
func get_notes() -> PackedStringArray:
	return _notes


func _fail(message: String) -> void:
	_failures.append(message)


func _same(a: Variant, b: Variant) -> bool:
	# Loose on int vs float so assert_eq(2, 2.0) passes; strict on everything else.
	if typeof(a) != typeof(b) and not (_is_number(a) and _is_number(b)):
		return false
	return a == b


func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


func _suffix(message: String) -> String:
	return "" if message.is_empty() else " (%s)" % message
