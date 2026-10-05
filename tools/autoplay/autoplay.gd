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
##                    (GameState.setup_independents), on top of whatever else is chosen
##   --paths          play with paths of ascension (M4; implies --rulers): GameState.with_paths. The computer
##                    (ai, ai_easy) researches along its build's plan and rolls its side of the fork with
##                    AIPlayer.choose_branch for the seed and seat, as an AI seat does; the report adds wins
##                    by side of the fork and by pairing, when transformations land, and path mandates
##   --branches A,B   with --paths, force the side of the fork of seat 1 and seat 2 (celestial_host or
##                    living_iron for the Crown, thorn_wild or blood_pact for the Clans), or "roll"
##   --matrix         the M2 build balance check (#36, design/M2_RULER.md §8.2): plays bands A-H with
##                    AIPlayer in both seats and prints a pass/miss table (tools/autoplay/matrix.gd).
##                    --seed and --turn-cap apply; --games, --p1/--p2, --seat1, --builds and --rulers don't
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
##
## Exit code: 0 when every game ran with no invariant violation, no session error and no script
## error; 1 otherwise; 2 for bad arguments. With --matrix: 0 only when band H (integrity) holds; the
## other bands are reported but don't change the exit code. With --matrix --paths: 0 only when bands P7 (M1
## and M2 not broken) and P8 (integrity) hold.

const Simulator := preload("res://tools/autoplay/simulator.gd")
const Policies := preload("res://tools/autoplay/policies.gd")
const Matrix := preload("res://tools/autoplay/matrix.gd")
const PathMatrix := preload("res://tools/autoplay/path_matrix.gd")
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
	if opts.matrix and opts.paths:
		_run_path_matrix(opts, catcher)
		return
	if opts.matrix:
		_run_matrix(opts, catcher)
		return
	var started := Time.get_ticks_msec()
	# Every engine or script error logged during a game is filed under that game's seed and turn.
	var options := {"rulers": opts.rulers, "builds": opts.builds, "paths": opts.paths, "branches": opts.branches,
		"independents": opts.independents}
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
		extra = " --paths" if opts.paths else " --rulers"
		if opts.builds.any(func(b): return not str(b).is_empty()):
			extra += " --builds %s" % ",".join(opts.builds.map(func(b): return "roll" if str(b).is_empty() else str(b)))
		if opts.branches.any(func(b): return not str(b).is_empty()):
			extra += " --branches %s" % ",".join(opts.branches.map(func(b): return "roll" if str(b).is_empty() else str(b)))
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
	md += "\n- **Run:** `--matrix --seed %d --turn-cap %d --scale %s --jobs %d%s`, %d games, %.1f s." % [opts.seed, opts.turn_cap,
		str(opts.scale), opts.jobs, "" if str(opts.only).is_empty() else " --only " + str(opts.only), results.size(), seconds]
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
	md += "\n- **Run:** `--matrix --paths --seed %d --turn-cap %d --scale %s --jobs %d%s`, %d games, %.1f s." % [opts.seed, opts.turn_cap,
		str(opts.scale), opts.jobs, "" if str(opts.only).is_empty() else " --only " + str(opts.only), results.size(), seconds]
	print(md)
	if not opts.out.is_empty():
		var f := FileAccess.open(opts.out, FileAccess.WRITE)
		if f == null:
			printerr("autoplay: could not write %s (%s)" % [opts.out, error_string(FileAccess.get_open_error())])
		else:
			f.store_string(md + "\n")
			f.close()
	if not j.ok:
		printerr("autoplay: band P7 (M1 and M2 not broken) or P8 (integrity) does not hold")
	quit(0 if j.ok else 1)


## Plays the work items, in this process (--jobs 1) or in up to --jobs headless worker processes, and
## returns their results. Problems with a worker (it could not start, or wrote no results) go to `problems`.
func _play_items(items: Array, cells: Array, opts: Dictionary, catcher: ErrorCatcher, problems: Array) -> Array:
	var out := []
	if opts.jobs <= 1:
		for item in items:
			if opts.paths:
				out.append_array(PathMatrix.play_item(cells, item, opts.turn_cap, catcher.take))
			else:
				out.append_array(Matrix.play_item(cells, item, opts.turn_cap, catcher.take))
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
			if opts.paths:
				args.append("--paths")
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
	if opts.paths:
		var path_cells := PathMatrix.plan(1.0, opts.seed, true, PathMatrix.load_fixture())
		results = PathMatrix.play_item(path_cells, item, opts.turn_cap, catcher.take)
	else:
		results = Matrix.play_item(Matrix.plan(1.0, opts.seed), item, opts.turn_cap, catcher.take)
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
