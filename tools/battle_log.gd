extends SceneTree
## Battle log dev tool (M3-1, #56; design/M3_BATTLES.md §2.4, §11): dumps a battle's event log next to
## its report, round by round, rebuilds the fixture set, and checks and measures the logs of AI-vs-AI
## games. Developer-facing: the dumps use the log's ids.
##
##   godot --headless --path . -s tools/battle_log.gd -- <mode> [options]
##
## Modes:
##   --record PATH --turn T --battle I   dump battle I (0-based, resolution order) of turn T (1-based) of a
##                                       game record (GameSession.record() as JSON), rebuilt with
##                                       BattleLog.regenerate
##   --record PATH --list                list every battle of the record (turn, index, place, winner)
##   --scenario NAME [--seed S]          dump a fixture scenario (tools/battle_log/scenarios.gd), on its
##                                       fixture's seed unless --seed is given
##   --fixture NAME                      dump the stored fixture tests/fixtures/battles/NAME.json
##   --fixtures                          rewrite the fixture set: each scenario on the first seed where it
##                                       shows what it is for ("biggest" from the stored record of its
##                                       game, which is played again only when that file is missing)
##   --play SEED [--save PATH]           play an AI-vs-AI game with rulers (as autoplay --rulers --p1 ai
##                                       --p2 ai) and save its record (default user://battle_log_game.json)
##                                       for --record; lists its battles
##   --check N [--seed S]                play N AI-vs-AI games with rulers from seed S (default 1): every
##                                       battle's log must pass validate, verify_draws and the report
##                                       cross-checks, and regenerate must rebuild it byte for byte; prints
##                                       the size and time measurements
##   --overhead [--runs N]               time the biggest fixture's battle with recording off and on
## Options:
##   --json        dump {"log", "report"} as JSON instead of text
##   --turn-cap T  turns before a played game stops (default 60)
##   --out PATH    also write the output to PATH
## Exit code: 0 when everything ran and every check passed, 1 when a check failed, 2 for bad arguments.

const Scenarios := preload("res://tools/battle_log/scenarios.gd")
const Dump := preload("res://tools/battle_log/dump.gd")
const Games := preload("res://tools/battle_log/games.gd")


func _initialize() -> void:
	var o := _parse(OS.get_cmdline_user_args())
	if o.has("error"):
		printerr("battle_log: %s" % o.error)
		printerr("usage: godot --headless --path . -s tools/battle_log.gd -- (--record PATH (--turn T --battle I | --list) | --scenario NAME [--seed S] | --fixture NAME | --fixtures | --play SEED [--save PATH] | --check N [--seed S] | --overhead) [--json] [--out PATH]")
		quit(2)
		return
	var out := {"text": "", "code": 0}
	match o.mode:
		"record":
			_record(o, out)
		"scenario":
			_scenario(o, out)
		"fixture":
			_fixture(o, out)
		"fixtures":
			_fixtures(out)
		"play":
			_play(o, out)
		"check":
			_check(o, out)
		"overhead":
			_overhead(o, out)
	print(out.text)
	if not String(o.get("out", "")).is_empty():
		var f := FileAccess.open(o.out, FileAccess.WRITE)
		if f == null:
			printerr("battle_log: could not write %s" % o.out)
		else:
			f.store_string(out.text + "\n")
			f.close()
	quit(out.code)


# --- modes --------------------------------------------------------------------------------------------

func _record(o: Dictionary, out: Dictionary) -> void:
	var rec = _read_json(o.record)
	if not (rec is Dictionary):
		out.text = "Could not read a game record from %s." % o.record
		out.code = 1
		return
	if o.list:
		out.text = _list_battles(rec)
		return
	var r := BattleLog.regenerate(rec, o.turn, o.battle)
	if r.log.is_empty():
		out.text = "\n".join(r.errors)
		out.code = 1
		return
	_emit(o, out, r.log, r.report)


func _scenario(o: Dictionary, out: Dictionary) -> void:
	var sd: int = o.seed
	if sd <= 0:
		var fx = _read_json(Scenarios.fixture_path(o.scenario))
		sd = int(fx.seed) if fx is Dictionary and fx.has("seed") else Scenarios.find_seed(o.scenario)
	if sd <= 0:
		out.text = "Scenario %s shows nothing on any seed up to %d." % [o.scenario, Scenarios.MAX_SEED]
		out.code = 1
		return
	var r := Scenarios.run(o.scenario, sd)
	if not r.errors.is_empty():
		out.text = "\n".join(r.errors)
		out.code = 1
		return
	_emit(o, out, r.log, r.report)


func _fixture(o: Dictionary, out: Dictionary) -> void:
	var fx = _read_json(Scenarios.fixture_path(o.fixture))
	if not (fx is Dictionary):
		out.text = "There is no fixture %s." % Scenarios.fixture_path(o.fixture)
		out.code = 1
		return
	var lg := BattleLog.from_json(JSON.stringify(fx.log, "", false))
	_emit(o, out, lg.log, fx.report)


func _fixtures(out: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Scenarios.FIXTURE_DIR))
	var lines := []
	var why := Scenarios.ensure_biggest_record()
	if not why.is_empty():
		lines.append(why)
		out.code = 1
	for name in Scenarios.NAMES:
		var sd := Scenarios.find_seed(name)
		if sd < 0:
			lines.append("%s: no seed up to %d shows it." % [name, Scenarios.MAX_SEED])
			out.code = 1
			continue
		var r := Scenarios.run(name, sd)
		var problems := BattleLog.cross_check(r.log, r.report) + BattleLog.verify_draws(r.log)
		var text := JSON.stringify({"scenario": name, "what": Scenarios.WHAT[name], "seed": sd, "log": r.log, "report": r.report}, "", false)
		var f := FileAccess.open(Scenarios.fixture_path(name), FileAccess.WRITE)
		f.store_string(text + "\n")
		f.close()
		lines.append("%s: seed %d, %d fighters, %d events, %d bytes of log JSON%s" % [name, sd, r.log.fighters.size(), r.log.events.size(),
			BattleLog.to_json(r.log).to_utf8_buffer().size(), "" if problems.is_empty() else ", PROBLEMS: %s" % "; ".join(problems)])
		if not problems.is_empty():
			out.code = 1
	out.text = "\n".join(lines)


func _play(o: Dictionary, out: Dictionary) -> void:
	var g := Games.play(o.play, o.turn_cap)
	if not g.errors.is_empty():
		out.text = "\n".join(g.errors)
		out.code = 1
		return
	var path: String = o.save if not String(o.save).is_empty() else "user://battle_log_game.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		out.text = "Could not write %s." % path
		out.code = 1
		return
	f.store_string(JSON.stringify(g.record) + "\n")
	f.close()
	var lines := ["Game %d: %d turns, %d battles. Record saved to %s (%s)." % [o.play, g.turns, g.battles.size(), path,
		ProjectSettings.globalize_path(path)]]
	for b in g.battles:
		lines.append("  --turn %d --battle %d: %s, %s won (%d fighters, %d events)" % [b.turn, b.index, b.report.get("place", ""),
			b.report.get("winner_name", ""), b.log.fighters.size(), b.log.events.size()])
	out.text = "\n".join(lines)


func _check(o: Dictionary, out: Dictionary) -> void:
	var lines := []
	var battles := 0
	var failures := 0
	var sizes := []
	var biggest := {}
	var turn_bytes := {}
	var max_turn := 0
	var regen_ms := []
	var play_ms := 0
	var fighters_max := 0
	var attacks_max := 0
	var slowest := {}
	for gi in o.check:
		var sd: int = o.seed + gi
		var g := Games.play(sd, o.turn_cap, Games.seats_for(sd))
		play_ms += int(g.ms)
		if not g.errors.is_empty():
			lines.append("game %d: %s" % [sd, "; ".join(g.errors)])
			failures += 1
			continue
		var round_trip = JSON.parse_string(JSON.stringify(g.record))
		for b in g.battles:
			battles += 1
			var lg: Dictionary = b.log
			var json := BattleLog.to_json(lg)
			var bytes := json.to_utf8_buffer().size()
			sizes.append(bytes)
			var key := "%d|%d" % [sd, b.turn]
			turn_bytes[key] = int(turn_bytes.get(key, 0)) + bytes
			max_turn = maxi(max_turn, int(turn_bytes[key]))
			var attacks: int = lg.events.filter(func(e): return e.t == "attack").size()
			fighters_max = maxi(fighters_max, lg.fighters.size())
			attacks_max = maxi(attacks_max, attacks)
			if biggest.is_empty() or bytes > int(biggest.bytes):
				biggest = {"bytes": bytes, "seed": sd, "turn": b.turn, "index": b.index, "fighters": lg.fighters.size(), "attacks": attacks,
					"events": lg.events.size(), "rounds": int(b.report.rounds_fought)}
			var t0 := Time.get_ticks_usec()
			var regen := BattleLog.regenerate(round_trip, b.turn, b.index)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			regen_ms.append(ms)
			if ms > float(slowest.get("ms", 0.0)):
				slowest = {"ms": snappedf(ms, 1.0), "seed": sd, "turn": b.turn}
			var problems := BattleLog.verify_draws(lg) + BattleLog.cross_check(lg, b.report)
			if BattleLog.to_json(regen.log) != json:
				problems.append("regenerate gave a different log %s" % str(regen.errors))
			if not problems.is_empty():
				failures += 1
				lines.append("game %d turn %d battle %d: %s" % [sd, b.turn, b.index, "; ".join(problems)])
	sizes.sort()
	regen_ms.sort()
	var p := func(a: Array, q: float): return a[mini(a.size() - 1, int(q * a.size()))] if not a.is_empty() else 0
	lines.push_front("Checked %d battles in %d AI-vs-AI games with rulers (seeds %d-%d): %d failed." % [battles, o.check, o.seed,
		o.seed + o.check - 1, failures])
	lines.append("Log JSON per battle: p50 %s, p90 %s, max %s bytes. Biggest: %s." % [str(p.call(sizes, 0.5)), str(p.call(sizes, 0.9)),
		str(sizes.back() if not sizes.is_empty() else 0), str(biggest)])
	lines.append("Most fighters in one battle %d, most attacks %d. One turn's logs, max %d bytes." % [fighters_max, attacks_max, max_turn])
	lines.append("regenerate per battle: p50 %.0f ms, max %.0f ms (%s). Playing the games took %.1f s." % [float(p.call(regen_ms, 0.5)),
		float(regen_ms.back() if not regen_ms.is_empty() else 0.0), str(slowest), play_ms / 1000.0])
	out.text = "\n".join(lines)
	out.code = 1 if failures > 0 else 0


func _overhead(o: Dictionary, out: Dictionary) -> void:
	var t := Scenarios.time_recording("biggest", o.runs)
	var lines := ["Biggest fixture, %d runs each, interleaved: recording off min %.1f ms (median %.1f), on min %.1f ms (median %.1f): %+.1f%% by the minimums, %+.1f%% by the medians." % [
		o.runs, t.off_min, t.off_median, t.on_min, t.on_median, 100.0 * (t.on_min / t.off_min - 1.0), 100.0 * (t.on_median / t.off_median - 1.0)]]
	# What the biggest log and its timeline take in memory, and what copying it costs (turn_report()
	# deep-copies the last turn's events, logs included).
	var m0 := OS.get_static_memory_usage()
	var r := Scenarios.run("biggest", 0)
	var m1 := OS.get_static_memory_usage()
	var tl := BattleTimeline.build(r.log)
	var m2 := OS.get_static_memory_usage()
	var t0 := Time.get_ticks_usec()
	var copy: Dictionary = r.log.duplicate(true)
	var copy_ms := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var state := tl.state_at(r.log.events.size() - 1)
	var seek_ms := (Time.get_ticks_usec() - t0) / 1000.0
	lines.append("In memory: the log and report about %.1f MB (rebuilt with the replay), the timeline %.1f MB more. Deep-copying the log %.1f ms; seeking the timeline to its last event %.1f ms (%d fighters, %d events)." % [
		(m1 - m0) / 1048576.0, (m2 - m1) / 1048576.0, copy_ms, seek_ms, state.fighters.size(), copy.events.size()])
	out.text = "\n".join(lines)


# --- helpers ------------------------------------------------------------------------------------------

func _emit(o: Dictionary, out: Dictionary, battle_log: Dictionary, report: Dictionary) -> void:
	if o.json:
		out.text = JSON.stringify({"log": battle_log, "report": report}, "  ", false)
	else:
		out.text = Dump.text(battle_log, report)
	var problems := BattleLog.verify_draws(battle_log) + BattleLog.cross_check(battle_log, report)
	out.code = 0 if problems.is_empty() else 1


## Every battle of a game record: one line each, from one pass over its turns.
func _list_battles(rec: Dictionary) -> String:
	var errors := []
	var state := GameState.from_dict(rec.get("start_state", {}), errors)
	if state == null:
		return "\n".join(errors)
	var lines := []
	var history: Array = rec.get("history", [])
	for i in history.size():
		var entry: Dictionary = history[i]
		var orders := OrderBook.orders_from_dict(entry.get("orders", {}), errors)
		var result := TurnResolver.resolve(state, orders, Serial.to_int(entry.get("seed", 0)))
		if result.new_state == null:
			lines.append("Turn %d could not be resolved." % (i + 1))
			break
		state = result.new_state
		var k := 0
		for e in result.events:
			if GameSession.BATTLE_TYPES.has(e.type):
				var rep: Dictionary = e.numbers.report
				lines.append("--turn %d --battle %d: %s, %s won after %d rounds (%d events)" % [i + 1, k, rep.get("place", ""),
					rep.get("winner_name", ""), int(rep.get("rounds_fought", 0)), e.numbers.get("log", {}).get("events", []).size()])
				k += 1
	if lines.is_empty():
		lines.append("This game had no battles.")
	return "\n".join(lines)


func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _parse(args: PackedStringArray) -> Dictionary:
	var o := {"mode": "", "record": "", "turn": 0, "battle": 0, "list": false, "scenario": "", "seed": 0, "fixture": "", "play": 0,
		"save": "", "check": 0, "runs": 9, "json": false, "turn_cap": 60, "out": ""}
	var i := 0
	while i < args.size():
		var a := args[i]
		var v := args[i + 1] if i + 1 < args.size() else ""
		match a:
			"--record":
				o.mode = "record"
				o.record = v
				i += 1
			"--turn":
				o.turn = v.to_int()
				i += 1
			"--battle":
				o.battle = v.to_int()
				i += 1
			"--list":
				o.list = true
			"--scenario":
				o.mode = "scenario"
				o.scenario = v
				i += 1
			"--seed":
				o.seed = v.to_int()
				i += 1
			"--fixture":
				o.mode = "fixture"
				o.fixture = v
				i += 1
			"--fixtures":
				o.mode = "fixtures"
			"--play":
				o.mode = "play"
				o.play = v.to_int()
				i += 1
			"--save":
				o.save = v
				i += 1
			"--check":
				o.mode = "check"
				o.check = maxi(1, v.to_int())
				i += 1
			"--overhead":
				o.mode = "overhead"
			"--runs":
				o.runs = maxi(1, v.to_int())
				i += 1
			"--json":
				o.json = true
			"--turn-cap":
				o.turn_cap = maxi(1, v.to_int())
				i += 1
			"--out":
				o.out = v
				i += 1
			_:
				return {"error": "unknown option %s" % a}
		i += 1
	if o.mode.is_empty():
		return {"error": "say what to do: --record, --scenario, --fixture, --fixtures, --play, --check or --overhead"}
	if o.mode == "record" and not o.list and o.turn < 1:
		return {"error": "--record needs --turn T (1-based) and --battle I (0-based), or --list"}
	if o.mode == "scenario" and not Scenarios.NAMES.has(o.scenario):
		return {"error": "no scenario '%s'; the scenarios are %s" % [o.scenario, ", ".join(Scenarios.NAMES)]}
	if o.mode == "check" and o.seed <= 0:
		o.seed = 1
	return o
