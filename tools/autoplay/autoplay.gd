extends SceneTree
## Headless autoplay runner (the M1 play-script): plays complete games with scripted policies and
## prints a markdown balance and length report. Logic lives in simulator.gd and policies.gd.
##
##   godot --headless --path . -s tools/autoplay/autoplay.gd -- --games 50 --seed 1 --p1 greedy --p2 greedy
##
## Options (all optional):
##   --games N        games to play (default 50), on seeds S, S+1, ... S+N-1
##   --seed S         first game seed (default 1)
##   --p1 / --p2      policy of seat 1 / seat 2: greedy, random, turtle, ai or ai_easy (default greedy)
##   --seat1 FACTION  faction in seat 1: kingdom (Aurel Crown, default) or beasts (Thornmane Clans);
##                    seat 2 gets the other one
##   --turn-cap T     turns before a game counts as unfinished (default 60)
##   --out PATH       also write the markdown report to PATH
##   --list           also print one table row per game (seed, result, turns, battles, ...)
##   --rulers         play with rulers (M2): each seat rolls its build preset with AIPlayer.choose_build,
##                    the first draw of its policy RNG, as an AI seat does in a real game
##   --builds A,B     with --rulers, force the build preset of seat 1 and seat 2 (preset ids from
##                    data/build_presets.gd, e.g. warrior_king,clan_moot; "roll" keeps that seat's roll)
##
## Exit code: 0 when every game ran with no invariant violation, no session error and no script
## error; 1 otherwise; 2 for bad arguments.

const Simulator := preload("res://tools/autoplay/simulator.gd")
const Policies := preload("res://tools/autoplay/policies.gd")
const FACTIONS := ["kingdom", "beasts"]


class ErrorCatcher extends Logger:
	var _mutex := Mutex.new()
	var _errors: PackedStringArray = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var text := rationale if not rationale.is_empty() else code
		_mutex.lock()
		_errors.append("%s (%s:%d in %s)" % [text, file, line, function])
		_mutex.unlock()

	func take() -> PackedStringArray:
		_mutex.lock()
		var out := _errors
		_errors = PackedStringArray()
		_mutex.unlock()
		return out


func _initialize() -> void:
	var opts := _parse(OS.get_cmdline_user_args())
	if opts.has("error"):
		printerr("autoplay: %s" % opts.error)
		printerr("usage: godot --headless --path . -s tools/autoplay/autoplay.gd -- --games 50 --seed 1 --p1 greedy --p2 greedy [--seat1 kingdom|beasts] [--turn-cap 60] [--out report.md] [--list] [--rulers [--builds PRESET1,PRESET2]]")
		quit(2)
		return
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	var started := Time.get_ticks_msec()
	# Every engine or script error logged during a game is filed under that game's seed and turn.
	var options := {"rulers": opts.rulers, "builds": opts.builds}
	var results := Simulator.run_batch(opts.games, opts.seed, opts.seats, opts.policies, opts.turn_cap, catcher.take, options)
	var summary := Simulator.summarize(results)
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	var stray_errors := catcher.take()
	OS.remove_logger(catcher)

	var md := Simulator.to_markdown(summary)
	if not stray_errors.is_empty():
		md += "\n- **Script errors outside games:** %d. First: %s" % [stray_errors.size(), stray_errors[0]]
	for key in ["violations", "script_errors"]:
		var repro: Dictionary = summary[key].get("repro", {})
		if not repro.is_empty():
			md += "\n- **Repro (%s):** seed %d, turn %d: %s Orders that turn: `%s`." % [key.replace("_", " "), repro.seed,
				repro.turn, repro.what, JSON.stringify(repro.orders)]
	var extra := ""
	if opts.rulers:
		extra = " --rulers"
		if opts.builds.any(func(b): return not str(b).is_empty()):
			extra += " --builds %s" % ",".join(opts.builds.map(func(b): return "roll" if str(b).is_empty() else str(b)))
	md += "\n- **Run:** `--games %d --seed %d --p1 %s --p2 %s --seat1 %s --turn-cap %d%s`, %.1f s." % [opts.games, opts.seed,
		opts.policies[0], opts.policies[1], opts.seats[0], opts.turn_cap, extra, seconds]
	if opts.list:
		md += "\n\n" + Simulator.game_lines(results)
	print(md)
	if not opts.out.is_empty():
		var f := FileAccess.open(opts.out, FileAccess.WRITE)
		if f == null:
			printerr("autoplay: could not write %s (%s)" % [opts.out, error_string(FileAccess.get_open_error())])
		else:
			f.store_string(md + "\n")
			f.close()

	var script_errors: int = summary.script_errors.count + stray_errors.size()
	var failed: bool = summary.violations.count > 0 or summary.errors.count > 0 or script_errors > 0
	if failed:
		printerr("autoplay: FAIL (%d invariant violations, %d session errors, %d script errors)" % [
			summary.violations.count, summary.errors.count, script_errors])
	quit(1 if failed else 0)


func _parse(args: PackedStringArray) -> Dictionary:
	var opts := {"games": 50, "seed": 1, "policies": ["greedy", "greedy"], "seats": FACTIONS.duplicate(),
		"turn_cap": Simulator.TURN_CAP, "out": "", "list": false, "rulers": false, "builds": ["", ""]}
	var builds_arg := ""
	var i := 0
	while i < args.size():
		var key := args[i]
		if key == "--list":
			opts.list = true
			i += 1
			continue
		if key == "--rulers":
			opts.rulers = true
			i += 1
			continue
		if i + 1 >= args.size():
			return {"error": "%s needs a value" % key}
		var value := args[i + 1]
		i += 2
		match key:
			"--games":
				if not value.is_valid_int() or value.to_int() < 1:
					return {"error": "--games must be a positive whole number"}
				opts.games = value.to_int()
			"--seed":
				if not value.is_valid_int():
					return {"error": "--seed must be a whole number"}
				opts.seed = value.to_int()
			"--p1", "--p2":
				if not Policies.NAMES.has(value):
					return {"error": "%s must be one of %s" % [key, ", ".join(Policies.NAMES)]}
				opts.policies[0 if key == "--p1" else 1] = value
			"--seat1":
				if not FACTIONS.has(value):
					return {"error": "--seat1 must be kingdom or beasts"}
				opts.seats = [value, FACTIONS[1] if value == FACTIONS[0] else FACTIONS[0]]
			"--turn-cap":
				if not value.is_valid_int() or value.to_int() < 1:
					return {"error": "--turn-cap must be a positive whole number"}
				opts.turn_cap = value.to_int()
			"--out":
				opts.out = value
			"--builds":
				builds_arg = value
			_:
				return {"error": "unknown option %s" % key}
	if not builds_arg.is_empty():
		if not opts.rulers:
			return {"error": "--builds needs --rulers"}
		var parts := builds_arg.split(",")
		if parts.size() != 2:
			return {"error": "--builds takes two presets, seat 1's and seat 2's, separated by a comma (\"roll\" keeps a seat's roll)"}
		for seat in 2:
			var pid := parts[seat].strip_edges()
			if pid == "roll" or pid.is_empty():
				continue
			if str(RulerRules.preset_data(pid).get("faction", "")) != opts.seats[seat]:
				var ids := RulerRules.presets_for(opts.seats[seat]).map(func(p): return str(p.id))
				return {"error": "seat %d (%s) can play only these presets: %s, or roll" % [seat + 1, opts.seats[seat], ", ".join(ids)]}
			opts.builds[seat] = pid
	return opts
