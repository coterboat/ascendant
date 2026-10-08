extends RefCounted
## The M4 path balance check (#71, design/M4_ASCENSION.md §10.2): AIPlayer plays both seats with paths on,
## and each seat's side of the fork is forced. autoplay.gd --matrix --paths runs it, prints a pass/miss table
## for bands P1-P8 and exits 0 only when P7 (M1 and M2 not broken) and P8 (integrity) hold; the other bands
## are reported.
##
##   godot --headless --path . -s tools/autoplay/autoplay.gd -- --matrix --paths --jobs 8
##
## What is played (cells: one build and one side of the fork per seat, one seat order, a run of seeds):
##   P   every Crown side x every Clans side (4 branch pairings) x every Crown preset x every Clans preset
##       (9 preset pairings) x both seat orders, CELL_GAMES each: 1,800 games. A branch pairing with fewer
##       than MIN_DECISIVE decisive games plays its games again on the next seeds, once.
##   P7  M2_PER_CELL games of every cell of the M2 matrix (matrix.gd, paths off), on the seeds and turn cap of
##       the fixture M2_FIXTURE. Each game record's md5 must equal the one recorded on main.
##
## The bands (§10.2):
##   P1  per faction, side A vs side B: the Bradley-Terry head-to-head from their records against the other
##       faction's two sides (pooled over presets and seat orders), as M2's band A. Each 40-60%.
##   P1d each Crown side against each Clans side, pooled (report).
##   P2  each side against each opposing side, pooled over presets: no more than 65% of decisive games.
##   P3  median decisive game 12-25 turns, and at most 10% of games at the turn cap.
##   P4  median turn a faction transforms 7-11, and in 80%+ of games reaching turn 14 both have transformed.
##   P5  (report) games where a battle's "why" names a path effect (target 30%+), nodes researched by the end,
##       rush (2 ordinary nodes before the Oath) vs round out (3 or more).
##   P6  (report) Crown / Clans 40-60%; a miss goes to Alex with #25 item 4, not tuned silently.
##   P7  the M2 games are identical to main (fixture), and with paths on M2's band F (the AI sacrifices in
##       15-50% of games) still passes; M2's D and E are reported on the paths games.
##   P8  0 invariant violations, session errors and script errors; every 10th game replays to an identical
##       final state; 0 research forecast mismatches (Simulator.check_research).
##
## Every game is seeded exactly as in autoplay.gd, so any game can be replayed alone:
## `--games 1 --seed S --p1 ai --p2 ai --seat1 F --paths --builds A,B --branches X,Y`.

const Simulator := preload("res://tools/autoplay/simulator.gd")
const Matrix := preload("res://tools/autoplay/matrix.gd")

const FACTIONS := ["kingdom", "beasts"]
const POLICY := "ai"
## Games per cell (one branch pairing, one preset pairing, one seat order), before --scale.
const CELL_GAMES := 25
## A branch pairing with fewer decisive games than this (scaled) is played again on the next seeds, once.
const MIN_DECISIVE := 120
const REPLAY_EVERY := 10
## Band P7: games per M2 matrix cell, compared with the fixture's record digests.
const M2_PER_CELL := 2
const M2_FIXTURE := "res://tests/fixtures/m2_matrix_digests.json"

## The targets of §10.2, so the table and the tests read the same numbers.
const P1_BAND := [0.40, 0.60]
const P2_MAX := 0.65
const P3_BAND := [12.0, 25.0]
const P3_CAP_MAX := 0.10
const P4_BAND := [7.0, 11.0]
const P4_BY_TURN := 14
const P4_SHARE := 0.80
const P5_WHY_SHARE := 0.30
const P6_BAND := [0.40, 0.60]
## "why" factor ids that name a path effect besides "path_<node>" and "morale_path_<node>".
const PATH_FACTORS := ["Wings", "Iron Hide", "Rooted", "Lifedrinker", "dread_lands"]


## The sides of the fork of `faction_id`, in PathData.BRANCHES order.
static func sides_of(faction_id: String) -> Array:
	var out := []
	for b in PathData.BRANCHES:
		if String(PathData.BRANCHES[b].faction) == faction_id:
			out.append(String(b))
	return out


static func faction_of_side(side: String) -> String:
	return String(PathData.BRANCHES.get(side, {}).get("faction", ""))


static func other(faction_id: String) -> String:
	return FACTIONS[1] if faction_id == FACTIONS[0] else FACTIONS[0]


## The games to play: [{"id", "band" ("P" | "P7"), "pairing", "seats", "builds", "branches", "paths", "games",
## "seed", "turn_cap" (P7 only)}]. Cell ids are stable, so a parallel worker finds its cell by id. `m2` false
## leaves out band P7's cells; `fixture` is the P7 fixture (load_fixture), whose seed and turn cap P7 uses.
static func plan(scale: float = 1.0, base_seed: int = 1, m2: bool = true, fixture: Dictionary = {}) -> Array:
	var cells := []
	var n := maxi(1, roundi(CELL_GAMES * scale))
	var crown: Array = RulerRules.presets_for("kingdom").map(func(p): return str(p.id))
	var clans: Array = RulerRules.presets_for("beasts").map(func(p): return str(p.id))
	for cs in sides_of("kingdom"):
		for ks in sides_of("beasts"):
			var pairing := "%s|%s" % [cs, ks]
			for c in crown:
				for k in clans:
					cells.append({"id": "P:%s+%s:%s+%s" % [cs, c, ks, k], "band": "P", "pairing": pairing, "seats": ["kingdom", "beasts"],
						"builds": [c, k], "branches": [cs, ks], "paths": true, "games": n, "seed": base_seed})
					cells.append({"id": "P:%s+%s:%s+%s" % [ks, k, cs, c], "band": "P", "pairing": pairing, "seats": ["beasts", "kingdom"],
						"builds": [k, c], "branches": [ks, cs], "paths": true, "games": n, "seed": base_seed})
	if m2:
		var m2_seed := int(fixture.get("seed", 1))
		var m2_cap := int(fixture.get("turn_cap", Simulator.TURN_CAP))
		for c in Matrix.plan(1.0, m2_seed):
			cells.append({"id": "P7:" + str(c.id), "band": "P7", "pairing": "P7", "seats": c.seats.duplicate(), "builds": c.builds.duplicate(),
				"branches": [], "paths": false, "games": M2_PER_CELL, "seed": m2_seed, "turn_cap": m2_cap})
	return cells


static func find_cell(cells: Array, cell_id: String) -> Dictionary:
	for c in cells:
		if str(c.id) == cell_id:
			return c
	return {}


## The P7 fixture: {"note", "seed", "turn_cap", "digests": {"<M2 cell id>|<seed>": md5}}, or {} if missing.
static func load_fixture(path: String = M2_FIXTURE) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


## The P7 fixture made from P7 results (each with "record_md5").
static func fixture_from(results: Array, base_seed: int, turn_cap: int, note: String) -> Dictionary:
	var digests := {}
	for r in results:
		if str(r.band) == "P7":
			digests["%s|%d" % [str(r.cell).trim_prefix("P7:"), int(r.seed)]] = str(r.get("record_md5", ""))
	var keys: Array = digests.keys()
	keys.sort()
	var sorted := {}
	for k in keys:
		sorted[k] = digests[k]
	return {"note": note, "seed": base_seed, "turn_cap": turn_cap, "digests": sorted}


## Plays one work item ({"cell", "from", "count"}) and returns its results (play_game results without
## "final_state", each with "cell", "band", "pairing" and "branches" (the forced sides, in seat order) added).
## `setup` are autoplay.gd's setup flags: {"independents": true} plays band P's games with Free Holds garrisons (IND-1,
## #142; --matrix --paths --independents). Band P7's games never have any, since they are compared with M2 records made without.
static func play_item(cells: Array, item: Dictionary, turn_cap: int, probe: Callable = Callable(), setup: Dictionary = {}) -> Array:
	var cell := find_cell(cells, str(item.cell))
	var out := []
	if cell.is_empty():
		return out
	for i in int(item.count):
		var game_seed: int = int(item.from) + i
		var options := {"rulers": true, "builds": cell.builds.duplicate(), "paths": bool(cell.paths), "branches": cell.branches.duplicate(),
			"replay_check": (game_seed - int(cell.seed)) % REPLAY_EVERY == 0, "record_digest": str(cell.band) == "P7"}
		if str(cell.band) == "P":
			options.merge(setup)
		var r := Simulator.play_game(game_seed, cell.seats, [POLICY, POLICY], int(cell.get("turn_cap", turn_cap)), probe, options)
		r.erase("final_state")
		r["cell"] = str(cell.id)
		r["band"] = str(cell.band)
		r["pairing"] = str(cell.pairing)
		r["branches"] = cell.branches.duplicate()
		out.append(r)
	return out


## Which branch pairings need their games doubled: {pairing: true} for those with fewer than the scaled
## MIN_DECISIVE decisive games. P7's games never double.
static func short_pairings(results: Array, scale: float) -> Dictionary:
	var dec := {}
	var seen := {}
	for r in results:
		if str(r.band) != "P":
			continue
		seen[r.pairing] = true
		if Matrix.decisive(r):
			dec[r.pairing] = int(dec.get(r.pairing, 0)) + 1
	var need := ceili(MIN_DECISIVE * scale)
	var out := {}
	for p in seen:
		if int(dec.get(p, 0)) < need:
			out[p] = true
	return out


# --- judging the bands -------------------------------------------------------------------------------

## {wins, losses, decisive, games} of the faction that played side `side` in `results`. `opponent_side`
## limits it to games against that side.
static func side_record(results: Array, side: String, opponent_side: String = "") -> Dictionary:
	var rec := {"wins": 0, "losses": 0, "decisive": 0, "games": 0}
	var fid := faction_of_side(side)
	for r in results:
		if _forced_side(r, fid) != side:
			continue
		if not opponent_side.is_empty() and _forced_side(r, other(fid)) != opponent_side:
			continue
		rec.games += 1
		if Matrix.decisive(r):
			rec.decisive += 1
			if str(r.winner) == fid:
				rec.wins += 1
			else:
				rec.losses += 1
	return rec


## The side of the fork `fid` was given in game `r` (the cell's forced side; it is the one it swears).
static func _forced_side(r: Dictionary, fid: String) -> String:
	var seats: Array = r.get("seats", [])
	var sides: Array = r.get("branches", [])
	var i := seats.find(fid)
	return str(sides[i]) if i >= 0 and i < sides.size() else ""


## Whether battle record `b` (Simulator._battle_record) cites a path effect in its "why".
static func cites_path(b: Dictionary) -> bool:
	for f in b.get("factors", []):
		var id := str(f.get("id", ""))
		if id.begins_with("path_") or id.begins_with("morale_path_") or PATH_FACTORS.has(id):
			return true
	return false


static func _in(v: float, band: Array) -> bool:
	return v >= float(band[0]) - 0.000001 and v <= float(band[1]) + 0.000001


static func _pct(v: float) -> String:
	return "%d%%" % roundi(100.0 * v)


static func _ratio(n: int, d: int) -> float:
	return 0.0 if d == 0 else float(n) / float(d)


## Judges every band. `results` are all games played (P and P7); `stray_errors` script errors logged outside
## games; `fixture` the P7 fixture. Returns {"bands": [{"band", "what", "target", "result", "status" ("pass" |
## "miss" | "report"), "detail"}], "ok": bool (P7 and P8 hold), "pairings", "sides", "presets", "p_results"}.
static func judge(results: Array, stray_errors: int = 0, fixture: Dictionary = {}) -> Dictionary:
	var p_res := results.filter(func(r): return str(r.band) == "P")
	var m2_res := results.filter(func(r): return str(r.band) == "P7")
	var bands := []
	# P1: both sides viable, per faction, from common opponents.
	var p1_ok := true
	var p1_parts := []
	var p1_detail := []
	for fid in FACTIONS:
		var s: Array = sides_of(fid)
		var ra := side_record(p_res, s[0])
		var rb := side_record(p_res, s[1])
		var p := Matrix.head_to_head(ra, rb)
		var ok := _in(p, P1_BAND) and _in(1.0 - p, P1_BAND)
		p1_ok = p1_ok and ok
		p1_parts.append("%s %s / %s %s" % [Simulator.side_name(s[0]), _pct(p), Simulator.side_name(s[1]), _pct(1.0 - p)])
		p1_detail.append("%s won %d of %d decisive games against the %s sides, %s %d of %d" % [Simulator.side_name(s[0]), ra.wins,
			ra.decisive, Simulator.faction_name(other(fid)), Simulator.side_name(s[1]), rb.wins, rb.decisive])
	bands.append({"band": "P1", "what": "both sides viable: side vs side per faction (head-to-head from common opponents)",
		"target": "each 40-60%", "result": "; ".join(p1_parts), "status": "pass" if p1_ok else "miss", "detail": "; ".join(p1_detail) + "."})

	# P1d and P2: every Crown side against every Clans side.
	var pairings := _pairings(p_res)
	var p1d := []
	var worst := {"share": 0.0, "text": ""}
	var p2_ok := true
	var over := 0
	for pr in pairings:
		var cw := _ratio(int(pr.crown_wins), int(pr.decisive))
		p1d.append("%s vs %s %s / %s" % [Simulator.side_name(pr.crown), Simulator.side_name(pr.clans), _pct(cw), _pct(1.0 - cw)])
		for pair in [[cw, pr.crown, pr.clans], [1.0 - cw, pr.clans, pr.crown]]:
			if int(pr.decisive) > 0 and float(pair[0]) > worst.share:
				worst = {"share": float(pair[0]), "text": "%s %s against %s" % [Simulator.side_name(str(pair[1])), _pct(float(pair[0])), Simulator.side_name(str(pair[2]))]}
		if int(pr.decisive) > 0 and maxf(cw, 1.0 - cw) > P2_MAX + 0.000001:
			p2_ok = false
			over += 1
	bands.append({"band": "P1d", "what": "direct: each Crown side vs each Clans side, pooled", "target": "report",
		"result": "; ".join(p1d), "status": "report", "detail": ""})
	bands.append({"band": "P2", "what": "no dominant transformation (4 side pairings, pooled over presets)", "target": "none above 65%",
		"result": "worst: %s; %d of %d pairings over" % [worst.text, over, pairings.size()], "status": "pass" if p2_ok else "miss", "detail": ""})

	# P3: length.
	var lengths := []
	for r in p_res:
		if Matrix.decisive(r):
			lengths.append(int(r.turns))
	var ls := Simulator.stats_of(lengths)
	var capped := p_res.filter(func(r): return not bool(r.finished)).size()
	var cap_share := _ratio(capped, p_res.size())
	var p3_ok := _in(float(ls.median), P3_BAND) and cap_share <= P3_CAP_MAX + 0.000001
	bands.append({"band": "P3", "what": "length", "target": "median decisive game 12-25 turns; at most 10% at the turn cap",
		"result": "median %s (%d-%d); %d of %d at the cap (%s)" % [Simulator._num(ls.median), ls.min, ls.max, capped, p_res.size(), _pct(cap_share)],
		"status": "pass" if p3_ok else "miss", "detail": _cap_detail(p_res) if capped > 0 else ""})

	# P4: it happens.
	var t_turns := []
	var reached := 0
	var both := 0
	for r in p_res:
		var paths: Dictionary = r.get("paths", {})
		var all_by := true
		for fid in paths:
			var t := int(paths[fid].get("transform_turn", 0))
			if t > 0:
				t_turns.append(t)
			if t <= 0 or t > P4_BY_TURN:
				all_by = false
		if int(r.turns) >= P4_BY_TURN:
			reached += 1
			if all_by and paths.size() == FACTIONS.size():
				both += 1
	var ts := Simulator.stats_of(t_turns)
	var both_share := _ratio(both, reached)
	var p4_ok := _in(float(ts.median), P4_BAND) and both_share >= P4_SHARE - 0.000001
	bands.append({"band": "P4", "what": "it happens: transformations land mid-game", "target": "median transformation turn 7-11; both transformed by turn 14 in 80%+ of games reaching it",
		"result": "median turn %s (%d-%d, %d transformations); both by turn 14 in %d of %d (%s)" % [Simulator._num(ts.median), ts.min, ts.max, ts.n,
			both, reached, _pct(both_share)], "status": "pass" if p4_ok else "miss", "detail": ""})

	# P5: paths matter (report).
	var with_why := 0
	var path_battles := 0
	var battles := 0
	var nodes := []
	var rush := {}  # ordinary nodes before the Oath -> {wins, decisive}
	for r in p_res:
		var cited := false
		for b in r.battles:
			battles += 1
			if cites_path(b):
				path_battles += 1
				cited = true
		if cited:
			with_why += 1
		var paths: Dictionary = r.get("paths", {})
		for fid in paths:
			var e: Dictionary = paths[fid]
			var ordinary := 0
			for nid in e.get("nodes", []):
				if AscensionRules.is_ordinary(str(nid)):
					ordinary += 1
			nodes.append(ordinary)
			var k := str(mini(int(e.get("ordinary_before_oath", 0)), 3))
			if not rush.has(k):
				rush[k] = {"wins": 0, "decisive": 0, "factions": 0}
			rush[k].factions += 1
			if Matrix.decisive(r):
				rush[k].decisive += 1
				if str(r.winner) == str(fid):
					rush[k].wins += 1
	var why_share := _ratio(with_why, p_res.size())
	var ns := Simulator.stats_of(nodes)
	var rush_parts := []
	for k in ["0", "1", "2", "3"]:
		if rush.has(k):
			rush_parts.append("%s %s (%d of %d decisive, %d factions)" % [{"0": "none", "1": "1", "2": "rush (2)", "3": "round out (3+)"}[k],
				_pct(_ratio(rush[k].wins, rush[k].decisive)), rush[k].wins, rush[k].decisive, rush[k].factions])
	bands.append({"band": "P5", "what": "paths matter", "target": "report (a path effect in a battle's \"why\" in 30%+ of games)",
		"result": "%s of games (%d of %d; %d of %d battles); ordinary nodes by the end %.1f of 4; wins by ordinary nodes before the Oath: %s" % [
			_pct(why_share), with_why, p_res.size(), path_battles, battles, ns.mean, ", ".join(rush_parts)],
		"status": "report", "detail": "under 30%" if why_share < P5_WHY_SHARE else ""})

	# P6: factions (report).
	var crown_w := 0
	var dec := 0
	for r in p_res:
		if Matrix.decisive(r):
			dec += 1
			if str(r.winner) == "kingdom":
				crown_w += 1
	var cw6 := _ratio(crown_w, dec)
	bands.append({"band": "P6", "what": "factions", "target": "report (each 40-60%)",
		"result": "Aurel Crown %s / Thornmane Clans %s of %d decisive" % [_pct(cw6), _pct(1.0 - cw6), dec], "status": "report",
		"detail": "outside 40-60%: goes to Alex (#25 item 4)" if not _in(cw6, P6_BAND) else ""})

	# P7: M1 and M2 not broken.
	var digests: Dictionary = fixture.get("digests", {})
	var same := 0
	var differ := []
	var missing := 0
	for r in m2_res:
		var key := "%s|%d" % [str(r.cell).trim_prefix("P7:"), int(r.seed)]
		if not digests.has(key):
			missing += 1
		elif str(digests[key]) == str(r.get("record_md5", "")):
			same += 1
		else:
			differ.append(key)
	var with_sac := p_res.filter(func(r): return not r.ruler_log.sacrifices.is_empty()).size()
	var fr := _ratio(with_sac, p_res.size())
	var f_ok := _in(fr, Matrix.F_BAND)
	var to8 := 0
	var died8 := 0
	for r in p_res:
		if int(r.turns) >= 8:
			to8 += 1
			if r.ruler_log.deaths.any(func(d): return Matrix.midgame_death(r, d)):
				died8 += 1
	var p7_ok := not m2_res.is_empty() and same == m2_res.size() and f_ok
	var p7_detail := ""
	if m2_res.is_empty():
		p7_detail = "no M2 games were played"
	elif digests.is_empty():
		p7_detail = "the fixture %s is missing" % M2_FIXTURE
	elif not differ.is_empty():
		p7_detail = "first differing M2 game: %s" % differ[0]
	elif missing > 0:
		p7_detail = "%d M2 games are not in the fixture" % missing
	bands.append({"band": "P7", "what": "M1 and M2 not broken", "target": "M2 games identical to main; with paths, M2's band F (sacrifices in 15-50% of games) passes; D and E reported",
		"result": "%d of %d M2 game records identical to main; F %s (%d of %d games); D %s (a ruler dies before the last turn, %d of %d games reaching turn 8); E median decisive %s" % [
			same, m2_res.size(), _pct(fr), with_sac, p_res.size(), _pct(_ratio(died8, to8)), died8, to8, Simulator._num(ls.median)],
		"status": "pass" if p7_ok else "miss", "detail": p7_detail})

	# P8: integrity, every game.
	var viol := 0
	var errs := 0
	var scr := stray_errors
	var replays := 0
	var replay_bad := []
	var checks := {"turn_checks": 0, "turn_mismatches": 0, "target_checks": 0, "target_mismatches": 0}
	var first := ""
	for r in results:
		viol += r.violations.size()
		errs += r.errors.size()
		scr += r.script_errors.size()
		if first.is_empty():
			for key in ["violations", "errors", "script_errors"]:
				if not r[key].is_empty() and first.is_empty():
					first = "seed %d (%s): %s" % [r.seed, r.cell, r[key][0].get("detail", r[key][0].get("check", ""))]
		if not str(r.replay).is_empty():
			replays += 1
			if str(r.replay) != "identical":
				replay_bad.append("seed %d (%s): %s" % [r.seed, r.cell, r.replay])
		var rc: Dictionary = r.get("research", {})
		for k in checks:
			checks[k] += int(rc.get(k, 0))
		if first.is_empty() and not str(rc.get("first", "")).is_empty():
			first = "seed %d (%s): %s" % [r.seed, r.cell, rc.first]
	var mismatches: int = checks.turn_mismatches + checks.target_mismatches
	var p8_ok := viol == 0 and errs == 0 and scr == 0 and replay_bad.is_empty() and replays > 0 and mismatches == 0
	var p8_detail := first
	if not replay_bad.is_empty():
		p8_detail = ("%s; " % first if not first.is_empty() else "") + replay_bad[0]
	bands.append({"band": "P8", "what": "integrity, every game", "target": "0 violations, session errors, script errors and research forecast mismatches; every 10th game replays identically",
		"result": "%d violations, %d session errors, %d script errors; %d of %d replays identical (%d games); research forecasts: %d mismatches in %d turn checks and %d target checks" % [
			viol, errs, scr, replays - replay_bad.size(), replays, results.size(), mismatches, checks.turn_checks, checks.target_checks],
		"status": "pass" if p8_ok else "miss", "detail": p8_detail})
	# Alex 10-5 (#131): the MVP plays with independents, so a run with --independents is the balance contract.
	# A plain run still gates on integrity (P8, and P7's M1/M2 digests) but reports P7's F band only.
	var integrity_ok := p8_ok and not m2_res.is_empty() and same == m2_res.size()
	return {"bands": bands, "ok": p7_ok and p8_ok, "integrity_ok": integrity_ok, "pairings": pairings, "sides": _sides(p_res), "presets": _presets(p_res),
		"p_results": p_res}


## Why games hit the cap: the presets in them, most common first.
static func _cap_detail(p_res: Array) -> String:
	var by := {}
	var n := 0
	for r in p_res:
		if bool(r.finished):
			continue
		n += 1
		for fid in r.builds:
			var id := str(r.builds[fid])
			by[id] = int(by.get(id, 0)) + 1
	var keys: Array = by.keys()
	keys.sort_custom(func(a, b): return by[a] > by[b] if by[a] != by[b] else str(a) < str(b))
	return "games at the cap by preset (of %d): %s" % [n, ", ".join(keys.map(func(k): return "%s %d" % [Simulator.build_name(str(k)), by[k]]))]


## Per side pairing: [{"crown", "clans", "games", "decisive", "crown_wins", "clans_wins", "draws", "unfinished",
## "median"}], Crown sides first.
static func _pairings(p_res: Array) -> Array:
	var out := []
	for cs in sides_of("kingdom"):
		for ks in sides_of("beasts"):
			var pr := {"crown": cs, "clans": ks, "games": 0, "decisive": 0, "crown_wins": 0, "clans_wins": 0, "draws": 0, "unfinished": 0}
			var lengths := []
			for r in p_res:
				if str(r.pairing) != "%s|%s" % [cs, ks]:
					continue
				pr.games += 1
				if not bool(r.finished):
					pr.unfinished += 1
				elif bool(r.draw):
					pr.draws += 1
				elif Matrix.decisive(r):
					pr.decisive += 1
					lengths.append(int(r.turns))
					if str(r.winner) == "kingdom":
						pr.crown_wins += 1
					else:
						pr.clans_wins += 1
			pr["median"] = Simulator.stats_of(lengths).median
			out.append(pr)
	return out


## Per side: [{"side", "faction", "games", "decisive", "wins", "oath", "transform" (median turns), "never",
## "new_unit", "new_bought" (recruit orders for the new unit), "regulars" (recruit orders for regular units)}].
static func _sides(p_res: Array) -> Array:
	var out := []
	for fid in FACTIONS:
		for side in sides_of(fid):
			var rec := side_record(p_res, side)
			var oaths := []
			var trans := []
			var never := 0
			for r in p_res:
				if _forced_side(r, fid) != side:
					continue
				var e: Dictionary = r.get("paths", {}).get(fid, {})
				if int(e.get("oath_turn", 0)) > 0:
					oaths.append(int(e.oath_turn))
				if int(e.get("transform_turn", 0)) > 0:
					trans.append(int(e.transform_turn))
				else:
					never += 1
			var unit := String(AscensionRules.node_data(String(PathData.BRANCHES[side].transformation)).get("effects", {}).get("new_unit", ""))
			var bought := 0
			var regulars := 0
			for r in p_res:
				if _forced_side(r, fid) != side:
					continue
				var rec_units: Dictionary = r.get("recruits", {}).get(fid, {})
				for tid in rec_units:
					if str(tid) == unit:
						bought += int(rec_units[tid])
					if not _is_commander(fid, str(tid)):
						regulars += int(rec_units[tid])
			out.append({"side": side, "faction": fid, "games": rec.games, "decisive": rec.decisive, "wins": rec.wins,
				"oath": Simulator.stats_of(oaths).median, "transform": Simulator.stats_of(trans).median, "never": never,
				"new_unit": unit, "new_bought": bought, "regulars": regulars})
	return out


static func _is_commander(fid: String, type_id: String) -> bool:
	for f in FactionData.FACTIONS:
		if String(f.id) == fid:
			return String(f.commander.id) == type_id
	return false


## Per side and preset: [{"side", "preset", "games", "decisive", "wins"}].
static func _presets(p_res: Array) -> Array:
	var out := []
	for fid in FACTIONS:
		for side in sides_of(fid):
			for p in RulerRules.presets_for(fid):
				var rec := {"side": side, "preset": str(p.id), "games": 0, "decisive": 0, "wins": 0, "capped": 0}
				for r in p_res:
					if _forced_side(r, fid) != side or str(r.builds.get(fid, "")) != str(p.id):
						continue
					rec.games += 1
					if not bool(r.finished):
						rec.capped += 1
					if Matrix.decisive(r):
						rec.decisive += 1
						if str(r.winner) == fid:
							rec.wins += 1
				out.append(rec)
	return out


## The whole report as markdown: the bands table, the side pairings, each side, each side by preset, then the
## autoplay report sections for the paths games.
static func to_markdown(j: Dictionary, header: String = "") -> String:
	var L := []
	L.append("## Path balance check (design/M4_ASCENSION.md §10.2)%s" % ("" if header.is_empty() else ": " + header))
	L.append("")
	L.append("| band | what | target | result | status |")
	L.append("|---|---|---|---|---|")
	for b in j.bands:
		var status: String = {"pass": "**pass**", "miss": "**miss**", "report": "report"}[b.status]
		L.append("| %s | %s | %s | %s | %s |" % [b.band, b.what, b.target, b.result, status])
	var notes: Array = j.bands.filter(func(b): return not str(b.detail).is_empty())
	if not notes.is_empty():
		L.append("")
		for b in notes:
			L.append("- **%s:** %s" % [b.band, b.detail])
	L.append("")
	L.append("### Side pairings (wins of decisive games)")
	L.append("")
	L.append("| Aurel Crown side | Thornmane Clans side | games | decisive | Crown wins | Clans wins | draws | at the cap | median length |")
	L.append("|---|---|---|---|---|---|---|---|---|")
	for pr in j.pairings:
		L.append("| %s | %s | %d | %d | %d (%s) | %d (%s) | %d | %d | %s |" % [Simulator.side_name(pr.crown), Simulator.side_name(pr.clans), pr.games,
			pr.decisive, pr.crown_wins, _pct(_ratio(pr.crown_wins, pr.decisive)), pr.clans_wins, _pct(_ratio(pr.clans_wins, pr.decisive)),
			pr.draws, pr.unfinished, Simulator._num(pr.median)])
	L.append("")
	L.append("### Sides")
	L.append("")
	L.append("| side | faction | games | won (of decisive) | Oath, median turn | transformed, median turn | never transformed | new unit recruited (share of regular recruits) |")
	L.append("|---|---|---|---|---|---|---|---|")
	for s in j.sides:
		L.append("| %s | %s | %d | %d of %d (%s) | %s | %s | %d | %s %d (%s) |" % [Simulator.side_name(s.side), Simulator.faction_name(s.faction), s.games, s.wins,
			s.decisive, _pct(_ratio(s.wins, s.decisive)), Simulator._num(s.oath), Simulator._num(s.transform), s.never,
			String(PathData.NEW_UNITS.get(s.new_unit, {}).get("name", s.new_unit)), s.new_bought, _pct(_ratio(s.new_bought, s.regulars))])
	L.append("")
	L.append("### Sides by preset (wins of decisive games; games at the cap)")
	L.append("")
	L.append("| side | preset | games | won | at the cap |")
	L.append("|---|---|---|---|---|")
	for p in j.presets:
		L.append("| %s | %s | %d | %d of %d (%s) | %d |" % [Simulator.side_name(p.side), Simulator.build_name(p.preset), p.games, p.wins, p.decisive,
			_pct(_ratio(p.wins, p.decisive)), p.capped])
	if not j.p_results.is_empty():
		var s := Simulator.summarize(j.p_results)
		L.append("")
		L.append("### Paths games: %d" % j.p_results.size())
		L.append("")
		for line in Simulator.to_markdown(s).split("\n"):
			if line.begins_with("- **Results") or line.begins_with("- **Game length") or line.begins_with("- **Length buckets") \
					or line.begins_with("- **Battles") or line.begins_with("- **How battles") or line.begins_with("- **Top") \
					or line.begins_with("- **Rulers") or line.begins_with("- **Mandate picks") or line.begins_with("- **Transformations") \
					or line.begins_with("- **Research") or line.begins_with("- **Policy counters") or line.begins_with("- **Rejected") \
					or line.begins_with("- **Orders"):
				L.append(line)
	return "\n".join(L)
