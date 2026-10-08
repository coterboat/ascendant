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
##   --builds A,B     with --rulers, force the build of seat 1 and seat 2: a preset id from
##                    data/build_presets.gd (e.g. warrior_king,clan_moot), an explicit build RULER or
##                    RULER+MANDATE+... (e.g. ever_regent keeps all 10 power,
##                    ever_regent+royal_armories+heavy_tithes+veteran_levies spends all 10), or "roll" to
##                    keep that seat's roll
##   --independents   play with independents (IND-1, #142): Free Holds garrisons in every neutral province
##                    (GameState.setup_independents), on top of whatever else is chosen. With --matrix, every
##                    game has them; with --matrix --paths, band P's games do (P7's M2 games never do)
##   --paths          play with paths of ascension (M4; implies --rulers): GameState.with_paths. The computer
##                    (ai, ai_easy) researches along its build's plan and rolls its side of the fork with
##                    AIPlayer.choose_branch for the seed and seat, as an AI seat does; the report adds wins
##                    by side of the fork and by pairing, when transformations land, and path mandates
##   --branches A,B   with --paths, force the side of the fork of seat 1 and seat 2 (celestial_host or
##                    living_iron for the Crown, thorn_wild or blood_pact for the Clans), or "roll"
##   --sieges         play with forts and sieges (M3c, design/M3C_SIEGES.md; GameState.setup_sieges), on top of whatever else is
##                    chosen, and the report adds the siege sections. With --matrix it is the siege balance check (S-7, #105,
##                    tools/autoplay/siege_matrix.gd): bands S1-S10 of §11.2, with the sieges-off baseline beside them
##   --magic          play with magic (M5; implies --paths): GameState.with_magic. The computer researches the arcana, buys
##                    mages and casts rituals (AIMagic); the report adds the rituals cast, the spells cast in battle, the
##                    ritual forecast check and the hit point ledger
##   --fog            play with fog of war (M5): the policies are handed their seat's view, as a computer seat in a real game
##                    is; every 10th turn the snapshot test runs on the live game (tools/autoplay/fog_probe.gd)
##   --tithe [MODE]   with --magic, give the Thornmane Clans Tithe of Blood: MODE tithe (default), null (a test-only mandate
##                    of the same price that does nothing: the control of band G9) or bleed (Tithe of Blood played by the
##                    scripted "ai_bleed" policy, which pays every ritual it can in blood). Tithe of Blood costs 3 power: a
##                    Clans build with less left loses its last mandates until it fits (Simulator.tithe_build)
##   --matrix         the M2 build balance check (#36, design/M2_RULER.md §8.2): plays bands A-H with
##                    AIPlayer in both seats and prints a pass/miss table (tools/autoplay/matrix.gd).
##                    --seed and --turn-cap apply; --games, --p1/--p2, --seat1, --builds and --rulers don't
##   --matrix --sieges the M3c balance check for forts and sieges (#105, design/M3C_SIEGES.md §11.2): 900 siege games (9 preset pairings x
##                    both seat orders x paths off and on x 25), the same seeds with sieges off, 100 games of the turtle against
##                    the computer, and the sieges-off games of band S8 (tools/autoplay/siege_matrix.gd). Prints a pass/miss
##                    table for bands S1-S10. Use it with --independents, the balance contract (Alex, 10-5). It plays rulers and
##                    paths itself: leave --paths, --rulers, --magic and --fog out
##   --matrix --magic the M5 balance check for magic and fog (#122, design/M5_MAGIC_FOG.md §13.2): bands G1-G14 over the main
##                    matrix (1,800 games, fog off), the fog matrix (720) with its no-fog control, the Tithe pairs (720) with the
##                    null mandate and a scripted bleeding build, the magic-off path matrix as the control, and the M2 games
##                    of band G12 (tools/autoplay/magic_matrix.gd). Exit code 0 only when G12 and G13 hold
##   --matrix --paths the M4 path balance check (#71, design/M4_ASCENSION.md §10.2): every Crown side x Clans
##                    side x preset pairing x seat order with paths on, plus band P7's M2 games, and a
##                    pass/miss table for bands P1-P8 (tools/autoplay/path_matrix.gd). --branches doesn't apply
##   --record-m2 PATH with --matrix --paths, play only band P7's M2 games (paths off) and write their record
##                    digests to PATH: the fixture P7 compares against (tests/fixtures/m2_matrix_digests.json).
##                    Run it on main only, and only when an M2 change is intended: a rules change, or (#94) an
##                    AI change that shifts the computer's M2 games, re-recorded in a commit of its own
##   --note TEXT      with --record-m2, why the digests were re-recorded, added to the fixture's note
##   --jobs N         with --matrix, games run in N headless Godot processes at once (default: the
##                    processor count, at most 8). The results are the same for any N
##   --scale F        with --matrix, play F times the games of every band (default 1; 0.25 for a quick look)
##   --only TEXT      with --matrix, play only the cells whose id contains TEXT (e.g. blood_of_the_fang);
##                    the bands are then judged on those games alone
##   --work-dir PATH  with --matrix and --jobs above 1, where the worker processes write their results
##                    (default user://autoplay_matrix); the files are removed afterwards
##   --save-results PATH  with --matrix --magic or --sieges, also write the games' raw results to PATH, so a run can be chunked
##                    (--only G:, --only GF:, --only GT:, --only GB:, --only P, and with & for both: --only "G:&+iron_crown";
##                    for sieges --only "S:&beast_god", S0:, S7, S8) and judged later with --merge
##   --merge A,B,...  with --matrix --magic or --sieges, play nothing: judge the results saved by earlier runs
##   --records        with --matrix --magic or --sieges, also replay the earlier fixture records for band G12 or S8 (the default
##                    unless --only or --merge is given); --no-records leaves them out
##
## Exit code: 0 when every game ran with no invariant violation, no session error and no script
## error; 1 otherwise; 2 for bad arguments. With --matrix --sieges: 0 only when bands S8 (sieges off is byte-identical) and S9
## (integrity) hold; the other bands are target ranges, reported pass or miss (Alex, 10-8). With --matrix --magic: 0 only when bands G12 and G13 hold. With --matrix: 0 only when band H (integrity) holds; the
## other bands are reported but don't change the exit code. With --matrix --paths --independents (the balance
## contract since Alex's 10-5 call on #131): 0 only when bands P7 (M1 and M2 not broken) and P8 (integrity) hold.
## A plain --matrix --paths run gates on integrity only (P8 and P7's M1/M2 digests); P7's F band is report-only.

const Simulator := preload("res://tools/autoplay/simulator.gd")
const Policies := preload("res://tools/autoplay/policies.gd")
const Matrix := preload("res://tools/autoplay/matrix.gd")
const PathMatrix := preload("res://tools/autoplay/path_matrix.gd")
const MagicMatrix := preload("res://tools/autoplay/magic_matrix.gd")
const SiegeMatrix := preload("res://tools/autoplay/siege_matrix.gd")
const FACTIONS := ["kingdom", "beasts"]
const MAX_JOBS := 8


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
	if opts.worker:
		_run_worker(opts, catcher)
		return
	if opts.matrix and opts.sieges:
		_run_siege_matrix(opts, catcher)
		return
	if opts.matrix and opts.magic:
		_run_magic_matrix(opts, catcher)
		return
	if opts.matrix and opts.paths:
		_run_path_matrix(opts, catcher)
		return
	if opts.matrix:
		_run_matrix(opts, catcher)
		return
	var started := Time.get_ticks_msec()
	# Every engine or script error logged during a game is filed under that game's seed and turn.
	var options := {"rulers": opts.rulers, "builds": opts.builds, "paths": opts.paths, "branches": opts.branches,
		"independents": opts.independents, "magic": opts.magic, "fog": opts.fog, "tithe": opts.tithe, "sieges": opts.sieges}
	var results := Simulator.run_batch(opts.games, opts.seed, opts.seats, opts.policies, opts.turn_cap, catcher.take, options)
	var summary := Simulator.summarize(results)
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	var stray_errors := catcher.take()
	OS.remove_logger(catcher)

	var md := Simulator.to_markdown(summary)
	if opts.sieges:
		md += "\n\n" + "\n".join(SiegeMatrix.sections(results))  # M3c S-7: siege counts, storms, forts, recruits, lengths
	if not stray_errors.is_empty():
		md += "\n- **Script errors outside games:** %d. First: %s" % [stray_errors.size(), stray_errors[0]]
	for key in ["violations", "script_errors"]:
		var repro: Dictionary = summary[key].get("repro", {})
		if not repro.is_empty():
			md += "\n- **Repro (%s):** seed %d, turn %d: %s Orders that turn: `%s`." % [key.replace("_", " "), repro.seed,
				repro.turn, repro.what, JSON.stringify(repro.orders)]
	var extra := ""
	if opts.rulers:
		extra = " --paths" if opts.paths else " --rulers"
		if opts.builds.any(func(b): return not str(b).is_empty()):
			extra += " --builds %s" % ",".join(opts.builds.map(func(b): return "roll" if str(b).is_empty() else str(b)))
		if opts.branches.any(func(b): return not str(b).is_empty()):
			extra += " --branches %s" % ",".join(opts.branches.map(func(b): return "roll" if str(b).is_empty() else str(b)))
	if opts.independents:
		extra += " --independents"
	if opts.magic:
		extra = extra.replace(" --paths", "") + " --magic"
	if opts.fog:
		extra += " --fog"
	if opts.sieges:
		extra += " --sieges"
	if not str(opts.tithe).is_empty():
		extra += " --tithe " + str(opts.tithe)
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
		"turn_cap": Simulator.TURN_CAP, "out": "", "list": false, "rulers": false, "builds": ["", ""], "paths": false, "independents": false, "branches": ["", ""],
		"magic": false, "fog": false, "tithe": "", "save_results": "", "merge": "", "records": false, "no_records": false, "sieges": false,
		"matrix": false, "jobs": clampi(OS.get_processor_count(), 1, MAX_JOBS), "scale": 1.0, "work_dir": "user://autoplay_matrix",
		"worker": false, "cell": "", "from": 0, "count": 0, "only": "", "record_m2": "", "note": ""}
	var builds_arg := ""
	var branches_arg := ""
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
		if key == "--independents":
			opts.independents = true
			i += 1
			continue
		if key == "--paths":
			opts.paths = true
			opts.rulers = true  # paths need rulers
			i += 1
			continue
		if key == "--magic":
			opts.magic = true
			opts.paths = true  # magic needs paths, and paths need rulers
			opts.rulers = true
			i += 1
			continue
		if key == "--fog":
			opts.fog = true
			i += 1
			continue
		if key == "--sieges":
			opts.sieges = true
			i += 1
			continue
		if key == "--records":
			opts.records = true
			i += 1
			continue
		if key == "--no-records":
			opts.no_records = true
			i += 1
			continue
		if key == "--tithe":
			opts.tithe = "tithe"
			i += 1
			if i < args.size() and ["tithe", "null", "bleed"].has(args[i]):
				opts.tithe = args[i]
				i += 1
			continue
		if key == "--matrix" or key == "--matrix-worker":
			opts.matrix = true
			opts.worker = key == "--matrix-worker"
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
			"--save-results":
				opts.save_results = value
			"--merge":
				opts.merge = value
			"--builds":
				builds_arg = value
			"--branches":
				branches_arg = value
			"--jobs":
				if not value.is_valid_int() or value.to_int() < 1:
					return {"error": "--jobs must be a positive whole number"}
				opts.jobs = value.to_int()
			"--scale":
				if not value.is_valid_float() or value.to_float() <= 0.0:
					return {"error": "--scale must be a number above 0, like 0.25"}
				opts.scale = value.to_float()
			"--work-dir":
				opts.work_dir = value
			"--only":
				opts.only = value
			"--record-m2":
				opts.record_m2 = value
			"--note":
				opts.note = value
			"--cell":  # worker processes only
				opts.cell = value
			"--from":
				opts.from = value.to_int()
			"--count":
				opts.count = value.to_int()
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
			var parsed := Simulator.parse_build(pid, opts.seats[seat])
			if parsed.has("error"):
				var ids := RulerRules.presets_for(opts.seats[seat]).map(func(p): return str(p.id))
				return {"error": "seat %d (%s): %s Its presets: %s; or an explicit build like %s+...; or roll" % [seat + 1,
					opts.seats[seat], parsed.error, ", ".join(ids), RulerRules.rulers_for(opts.seats[seat])[0]]}
			opts.builds[seat] = pid
	if not str(opts.tithe).is_empty() and not opts.magic:
		return {"error": "--tithe needs --magic"}
	if (not str(opts.save_results).is_empty() or not str(opts.merge).is_empty()) and not (opts.matrix and (opts.magic or opts.sieges)):
		return {"error": "--save-results and --merge need --matrix --magic or --matrix --sieges"}
	if opts.matrix and opts.sieges and (opts.paths or opts.rulers or opts.magic or opts.fog):
		return {"error": "--matrix --sieges plays rulers, and paths on and off, itself: leave --paths, --rulers, --magic and --fog out"}
	if not str(opts.record_m2).is_empty() and not (opts.matrix and opts.paths):
		return {"error": "--record-m2 needs --matrix --paths"}
	if not str(opts.note).is_empty() and str(opts.record_m2).is_empty():
		return {"error": "--note needs --record-m2"}
	if not branches_arg.is_empty():
		if not opts.paths:
			return {"error": "--branches needs --paths"}
		var sides := branches_arg.split(",")
		if sides.size() != 2:
			return {"error": "--branches takes two sides of the fork, seat 1's and seat 2's, separated by a comma (\"roll\" keeps a seat's roll)"}
		for seat in 2:
			var side := sides[seat].strip_edges()
			if side == "roll" or side.is_empty():
				continue
			if String(AscensionRules.branch_data(side).get("faction", "")) != opts.seats[seat]:
				var ok := []
				for b in PathData.BRANCHES:
					if String(PathData.BRANCHES[b].faction) == opts.seats[seat]:
						ok.append(b)
				return {"error": "seat %d (%s): '%s' is not one of its sides of the fork (%s, or roll)" % [seat + 1, opts.seats[seat], side, ", ".join(ok)]}
			opts.branches[seat] = side
	if opts.tithe == "bleed" and not opts.matrix:  # the scripted build plays the Clans seat with the bleeding policy
		var clans_seat: int = opts.seats.find("beasts")
		if opts.policies[clans_seat] == "ai":
			opts.policies[clans_seat] = "ai_bleed"
	return opts


# --- the build balance matrix (M2-8, #36) ----------------------------------------------------------

func _run_matrix(opts: Dictionary, catcher: ErrorCatcher) -> void:
	var started := Time.get_ticks_msec()
	var cells := Matrix.plan(opts.scale, opts.seed)
	if not str(opts.only).is_empty():
		cells = cells.filter(func(c): return str(c.id).contains(opts.only))
	var results := []
	var problems := []
	results.append_array(_play_items(Matrix.work_items(cells), cells, opts, catcher, problems))
	# A pairing with too few decisive games plays its games again on the next seeds, once (§8.2).
	var short := Matrix.short_pairings(results, opts.scale)
	var again := cells.filter(func(c): return short.has(c.pairing))
	var doubled: Array = short.keys()
	if not again.is_empty():
		var offsets := {}
		for c in again:
			offsets[c.id] = int(c.games)
		results.append_array(_play_items(Matrix.work_items(again, offsets), cells, opts, catcher, problems))
	var stray := catcher.take()
	OS.remove_logger(catcher)
	var j := Matrix.judge(results, stray.size() + problems.size())
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	var md := Matrix.to_markdown(j)
	if not doubled.is_empty():
		doubled.sort()
		md += "\n- **Doubled** (fewer than %d decisive games): %s." % [ceili(Matrix.MIN_DECISIVE * opts.scale),
			", ".join(doubled.map(func(p): return " vs ".join(Array(str(p).split("|")).map(func(b): return Simulator.build_name(str(b))))))]
	for e in problems:
		md += "\n- **Worker problem:** %s" % e
	if not stray.is_empty():
		md += "\n- **Script errors outside games:** %d. First: %s" % [stray.size(), stray[0]]
	md += "\n- **Run:** `--matrix%s --seed %d --turn-cap %d --scale %s --jobs %d%s`, %d games, %.1f s." % [" --independents" if opts.independents else "",
		opts.seed, opts.turn_cap, str(opts.scale), opts.jobs, "" if str(opts.only).is_empty() else " --only " + str(opts.only), results.size(), seconds]
	print(md)
	if not opts.out.is_empty():
		var f := FileAccess.open(opts.out, FileAccess.WRITE)
		if f == null:
			printerr("autoplay: could not write %s (%s)" % [opts.out, error_string(FileAccess.get_open_error())])
		else:
			f.store_string(md + "\n")
			f.close()
	if not j.h_ok:
		printerr("autoplay: band H (integrity) does not hold")
	quit(0 if j.h_ok else 1)


# --- the path balance matrix (M4-6, #71) -----------------------------------------------------------

func _run_path_matrix(opts: Dictionary, catcher: ErrorCatcher) -> void:
	var started := Time.get_ticks_msec()
	var fixture := PathMatrix.load_fixture()
	var recording := not str(opts.record_m2).is_empty()
	var cells := PathMatrix.plan(opts.scale, opts.seed, true, fixture)
	if recording:
		cells = cells.filter(func(c): return str(c.band) == "P7")
	if not str(opts.only).is_empty():
		cells = cells.filter(func(c): return str(c.id).contains(opts.only))
	var results := []
	var problems := []
	results.append_array(_play_items(Matrix.work_items(cells), cells, opts, catcher, problems))
	if recording:
		var stray_rec := catcher.take()
		OS.remove_logger(catcher)
		var note := "Record digests of M2 matrix games (paths off), %d per cell, written by autoplay.gd --matrix --paths --record-m2 for band P7 (#71)." % PathMatrix.M2_PER_CELL
		if not str(opts.note).is_empty():
			note += " Re-recorded: %s" % opts.note
		var data := PathMatrix.fixture_from(results, int(fixture.get("seed", 1)), int(fixture.get("turn_cap", Simulator.TURN_CAP)),
			note + " Do not edit by hand.")
		var f := FileAccess.open(opts.record_m2, FileAccess.WRITE)
		if f == null:
			printerr("autoplay: could not write %s" % opts.record_m2)
			quit(1)
			return
		f.store_string(JSON.stringify(data, "\t") + "\n")
		f.close()
		var bad := problems.size() + stray_rec.size()
		for r in results:
			bad += r.violations.size() + r.errors.size() + r.script_errors.size()
		print("autoplay: wrote %d M2 record digests to %s (%d problems)" % [data.digests.size(), opts.record_m2, bad])
		quit(0 if bad == 0 else 1)
		return
	# A branch pairing with too few decisive games plays its games again on the next seeds, once (§10.2).
	var short := PathMatrix.short_pairings(results, opts.scale)
	var again := cells.filter(func(c): return short.has(c.pairing))
	var doubled: Array = short.keys()
	if not again.is_empty():
		var offsets := {}
		for c in again:
			offsets[c.id] = int(c.games)
		results.append_array(_play_items(Matrix.work_items(again, offsets), cells, opts, catcher, problems))
	var stray := catcher.take()
	OS.remove_logger(catcher)
	var j := PathMatrix.judge(results, stray.size() + problems.size(), fixture)
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	var md := PathMatrix.to_markdown(j)
	if not doubled.is_empty():
		doubled.sort()
		md += "\n- **Doubled** (fewer than %d decisive games): %s." % [ceili(PathMatrix.MIN_DECISIVE * opts.scale),
			", ".join(doubled.map(func(p): return " vs ".join(Array(str(p).split("|")).map(func(b): return Simulator.side_name(str(b))))))]
	for e in problems:
		md += "\n- **Worker problem:** %s" % e
	if not stray.is_empty():
		md += "\n- **Script errors outside games:** %d. First: %s" % [stray.size(), stray[0]]
	md += "\n- **Run:** `--matrix --paths%s --seed %d --turn-cap %d --scale %s --jobs %d%s`, %d games, %.1f s." % [" --independents" if opts.independents else "",
		opts.seed, opts.turn_cap, str(opts.scale), opts.jobs, "" if str(opts.only).is_empty() else " --only " + str(opts.only), results.size(), seconds]
	print(md)
	if not opts.out.is_empty():
		var f := FileAccess.open(opts.out, FileAccess.WRITE)
		if f == null:
			printerr("autoplay: could not write %s (%s)" % [opts.out, error_string(FileAccess.get_open_error())])
		else:
			f.store_string(md + "\n")
			f.close()
	# Alex 10-5 (#131): the contract is the MVP config, --independents. A plain run gates on integrity only.
	var gate_ok: bool = j.ok if opts.independents else bool(j.get("integrity_ok", j.ok))
	if not gate_ok:
		printerr("autoplay: band P7 (M1 and M2 not broken) or P8 (integrity) does not hold")
	elif not j.ok:
		print("autoplay: plain run (no --independents): P7's F band is report-only; the balance contract is --independents")
	quit(0 if gate_ok else 1)


# --- the siege balance matrix (M3c S-7, #105) ----------------------------------------------------------------

## The siege balance check (design/M3C_SIEGES.md §11.2): tools/autoplay/siege_matrix.gd. Bands S1-S10 as a pass/miss table,
## the sieges-off baseline beside them; exit 0 only when S8 (sieges off is byte-identical) and S9 (integrity) hold.
func _run_siege_matrix(opts: Dictionary, catcher: ErrorCatcher) -> void:
	var started := Time.get_ticks_msec()
	var fixture := PathMatrix.load_fixture()
	var cells := SiegeMatrix.plan(opts.scale, opts.seed, fixture)
	if not str(opts.only).is_empty():
		cells = cells.filter(func(c): return SiegeMatrix.matches(str(c.id), str(opts.only)))
	var results := []
	var problems := []
	var doubled := []
	var off := {}
	var stray := PackedStringArray()
	if not str(opts.merge).is_empty():
		for path in str(opts.merge).split(","):
			var saved = str_to_var(FileAccess.get_file_as_string(path.strip_edges()))
			if not (saved is Dictionary) or not saved.has("results"):
				problems.append("could not read saved results from %s" % path)
				continue
			results.append_array(saved.results)
			problems.append_array(saved.get("problems", []))
			for pairing in saved.get("doubled", []):
				if not doubled.has(pairing):
					doubled.append(pairing)
			if not saved.get("off", {}).is_empty():
				off = saved.off
			stray.append_array(PackedStringArray(saved.get("stray", [])))
		OS.remove_logger(catcher)
	else:
		results.append_array(_play_items(Matrix.work_items(cells), cells, opts, catcher, problems))
		# A preset pairing with too few decisive siege games plays its siege games, and the baseline's, again on the next seeds, once.
		var short := SiegeMatrix.short_pairings(results, opts.scale)
		var again := cells.filter(func(c): return short.has(c.pairing) and SiegeMatrix.doubles(c))
		doubled = short.keys()
		if not again.is_empty():
			var offsets := {}
			for c in again:
				offsets[c.id] = int(c.games)
			results.append_array(_play_items(Matrix.work_items(again, offsets), cells, opts, catcher, problems))
		var want_records: bool = opts.records or (str(opts.only).is_empty() and not opts.no_records)
		off = SiegeMatrix.replay_off_fixtures() if want_records else {}  # S8's turn-by-turn replays
		stray = catcher.take()
		OS.remove_logger(catcher)
		if not str(opts.save_results).is_empty():
			var sf := FileAccess.open(opts.save_results, FileAccess.WRITE)
			if sf == null:
				printerr("autoplay: could not write %s (%s)" % [opts.save_results, error_string(FileAccess.get_open_error())])
			else:
				sf.store_string(var_to_str({"results": results, "problems": problems, "doubled": doubled, "off": off, "stray": Array(stray)}))
				sf.close()
	var j := SiegeMatrix.judge(results, stray.size() + problems.size(), fixture, off)
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	var md := SiegeMatrix.to_markdown(j)
	if not doubled.is_empty():
		doubled.sort()
		md += "\n- **Doubled** (fewer than %d decisive siege games): %s." % [ceili(SiegeMatrix.MIN_DECISIVE * opts.scale),
			", ".join(doubled.map(func(p): return " vs ".join(Array(str(p).split("|")).map(func(b): return Simulator.build_name(str(b))))))]
	for e in problems:
		md += "\n- **Worker problem:** %s" % e
	if not stray.is_empty():
		md += "\n- **Script errors outside games:** %d. First: %s" % [stray.size(), stray[0]]
	md += "\n- **Run:** `--matrix --sieges%s --seed %d --turn-cap %d --scale %s --jobs %d%s%s`, %d games, %.1f s." % [" --independents" if opts.independents else "",
		opts.seed, opts.turn_cap, str(opts.scale), opts.jobs, "" if str(opts.only).is_empty() else " --only " + str(opts.only),
		"" if str(opts.merge).is_empty() else " --merge " + str(opts.merge), results.size(), seconds]
	print(md)
	if not opts.out.is_empty():
		var f := FileAccess.open(opts.out, FileAccess.WRITE)
		if f == null:
			printerr("autoplay: could not write %s (%s)" % [opts.out, error_string(FileAccess.get_open_error())])
		else:
			f.store_string(md + "\n")
			f.close()
	# The exit code is S8 and S9 (§11.2). Every other band is a target range we tune toward, reported pass or miss.
	if not j.ok:
		printerr("autoplay: band S8 (sieges off is byte-identical) or S9 (integrity) does not hold")
	elif not opts.independents:
		print("autoplay: plain run (no --independents): the balance contract is --independents (Alex, 10-5)")
	quit(0 if j.ok else 1)


# --- the magic and fog balance matrix (M5-11, #122) ------------------------------------------------------

func _run_magic_matrix(opts: Dictionary, catcher: ErrorCatcher) -> void:
	var started := Time.get_ticks_msec()
	var fixture := PathMatrix.load_fixture()
	var cells := MagicMatrix.plan(opts.scale, opts.seed, fixture)
	if not str(opts.only).is_empty():  # with --matrix --magic, "A&B" keeps the cells whose id contains both (G:&+warrior_king)
		var parts := str(opts.only).split("&", false)
		cells = cells.filter(func(c): return parts.size() > 0 and Array(parts).all(func(part): return str(c.id).contains(part)))
	var results := []
	var problems := []
	var doubled := []
	if not str(opts.merge).is_empty():
		for path in str(opts.merge).split(","):
			var data = str_to_var(FileAccess.get_file_as_string(path.strip_edges()))
			if not (data is Dictionary) or not data.has("results"):
				problems.append("could not read saved results from %s" % path)
				continue
			results.append_array(data.results)
	else:
		results.append_array(_play_items(Matrix.work_items(cells), cells, opts, catcher, problems))
		# A branch pairing with too few decisive games plays its games again on the next seeds, once (§13.2).
		var short := MagicMatrix.short_pairings(results, opts.scale)
		var again := cells.filter(func(c): return str(c.band) == "G" and short.has(c.pairing))
		doubled = short.keys()
		if not again.is_empty():
			var offsets := {}
			for c in again:
				offsets[c.id] = int(c.games)
			results.append_array(_play_items(Matrix.work_items(again, offsets), cells, opts, catcher, problems))
	var stray := catcher.take()
	OS.remove_logger(catcher)
	if not str(opts.save_results).is_empty():
		var sf := FileAccess.open(opts.save_results, FileAccess.WRITE)
		if sf == null:
			printerr("autoplay: could not write %s (%s)" % [opts.save_results, error_string(FileAccess.get_open_error())])
		else:
			sf.store_string(var_to_str({"results": results, "stray": Array(stray), "problems": problems}))
			sf.close()
	var want_records: bool = opts.records or (str(opts.only).is_empty() and str(opts.merge).is_empty() and not opts.no_records)
	var records := MagicMatrix.records_check() if want_records else {}
	var j := MagicMatrix.judge(results, stray.size() + problems.size(), fixture, records)
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	var md := MagicMatrix.to_markdown(j)
	if not doubled.is_empty():
		doubled.sort()
		md += "\n- **Doubled** (fewer than %d decisive games): %s." % [ceili(MagicMatrix.MIN_DECISIVE * opts.scale),
			", ".join(doubled.map(func(p): return " vs ".join(Array(str(p).split("|")).map(func(b): return Simulator.side_name(str(b))))))]
	for e in problems:
		md += "\n- **Worker problem:** %s" % e
	if not stray.is_empty():
		md += "\n- **Script errors outside games:** %d. First: %s" % [stray.size(), stray[0]]
	md += "\n- **Run:** `--matrix --magic%s --seed %d --turn-cap %d --scale %s --jobs %d%s%s`, %d games, %.1f s." % [" --independents" if opts.independents else "",
		opts.seed, opts.turn_cap, str(opts.scale), opts.jobs, "" if str(opts.only).is_empty() else " --only " + str(opts.only),
		"" if str(opts.merge).is_empty() else " --merge " + str(opts.merge), results.size(), seconds]
	print(md)
	if not opts.out.is_empty():
		var f := FileAccess.open(opts.out, FileAccess.WRITE)
		if f == null:
			printerr("autoplay: could not write %s (%s)" % [opts.out, error_string(FileAccess.get_open_error())])
		else:
			f.store_string(md + "\n")
			f.close()
	# Exit code 0 only when G12 (earlier games unbroken) and G13 (integrity) hold.
	if not j.ok:
		printerr("autoplay: band G12 (earlier games unbroken) or G13 (integrity) does not hold")
	quit(0 if j.ok else 1)


## Plays the work items, in this process (--jobs 1) or in up to --jobs headless worker processes, and
## returns their results. Problems with a worker (it could not start, or wrote no results) go to `problems`.
func _play_items(items: Array, cells: Array, opts: Dictionary, catcher: ErrorCatcher, problems: Array) -> Array:
	var out := []
	if opts.jobs <= 1:
		for item in items:
			if opts.sieges:
				out.append_array(SiegeMatrix.play_item(cells, item, opts.turn_cap, catcher.take, opts.independents))
			elif opts.magic:
				out.append_array(MagicMatrix.play_item(cells, item, opts.turn_cap, catcher.take, opts.independents))
			elif opts.paths:
				out.append_array(PathMatrix.play_item(cells, item, opts.turn_cap, catcher.take, opts.independents))
			else:
				out.append_array(Matrix.play_item(cells, item, opts.turn_cap, catcher.take, opts.independents))
		return out
	var dir := ProjectSettings.globalize_path(opts.work_dir) if str(opts.work_dir).begins_with("user://") or str(opts.work_dir).begins_with("res://") else str(opts.work_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var exe := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	var queue := items.duplicate()
	var running := {}
	var n := 0
	while not queue.is_empty() or not running.is_empty():
		while running.size() < opts.jobs and not queue.is_empty():
			var item: Dictionary = queue.pop_front()
			n += 1
			var path := dir.path_join("matrix_%d_%d.txt" % [OS.get_process_id(), n])
			var args := ["--headless", "--quiet", "--path", project, "-s", "res://tools/autoplay/autoplay.gd", "--", "--matrix-worker",
				"--cell", str(item.cell), "--from", str(item.from), "--count", str(item.count), "--seed", str(opts.seed),
				"--turn-cap", str(opts.turn_cap), "--out", path]
			if opts.sieges:
				args.append("--sieges")
			elif opts.magic:
				args.append("--magic")
			elif opts.paths:
				args.append("--paths")
			if opts.independents:
				args.append("--independents")
			var pid := OS.create_process(exe, args)
			if pid <= 0:
				problems.append("could not start a worker for %s, seeds %d-%d" % [item.cell, item.from, item.from + item.count - 1])
				continue
			running[pid] = {"item": item, "path": path}
		OS.delay_msec(40)
		for pid in running.keys():
			if OS.is_process_running(pid):
				continue
			var job: Dictionary = running[pid]
			running.erase(pid)
			var text := FileAccess.get_file_as_string(job.path)
			var data = str_to_var(text) if not text.is_empty() else null
			if not (data is Dictionary) or not data.has("results"):
				problems.append("the worker for %s, seeds %d-%d, wrote no results" % [job.item.cell, job.item.from, job.item.from + job.item.count - 1])
				continue
			out.append_array(data.results)
			for e in data.get("stray", []):
				problems.append("script error in a worker outside its games: %s" % e)
			DirAccess.remove_absolute(job.path)
	return out


## A worker process of a parallel --matrix run: plays one work item and writes its results to --out.
func _run_worker(opts: Dictionary, catcher: ErrorCatcher) -> void:
	var item := {"cell": opts.cell, "from": opts.from, "count": opts.count}
	var results := []
	if opts.sieges:
		var siege_cells := SiegeMatrix.plan(1.0, opts.seed, PathMatrix.load_fixture())
		results = SiegeMatrix.play_item(siege_cells, item, opts.turn_cap, catcher.take, opts.independents)
	elif opts.magic:
		var magic_cells := MagicMatrix.plan(1.0, opts.seed, PathMatrix.load_fixture())
		results = MagicMatrix.play_item(magic_cells, item, opts.turn_cap, catcher.take, opts.independents)
	elif opts.paths:
		var path_cells := PathMatrix.plan(1.0, opts.seed, true, PathMatrix.load_fixture())
		results = PathMatrix.play_item(path_cells, item, opts.turn_cap, catcher.take, opts.independents)
	else:
		results = Matrix.play_item(Matrix.plan(1.0, opts.seed), item, opts.turn_cap, catcher.take, opts.independents)
	var stray := catcher.take()
	OS.remove_logger(catcher)
	var f := FileAccess.open(opts.out, FileAccess.WRITE)
	if f == null:
		printerr("autoplay worker: could not write %s" % opts.out)
		quit(1)
		return
	f.store_string(var_to_str({"results": results, "stray": Array(stray)}))
	f.close()
	quit(0)
