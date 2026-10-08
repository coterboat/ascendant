extends RefCounted
## The M3c siege balance check (S-7, #105, design/M3C_SIEGES.md §11): AIPlayer plays both seats with forts and sieges and
## rulers on, and the same seeds are played again with sieges off as the baseline. autoplay.gd --matrix --sieges runs it and
## prints a pass/miss table for bands S1-S10 and the report sections (siege counts, storms against breaches, forts built,
## recruits by fort, siege lengths, the cap share against the sieges-off baseline). It exits 0 only when S8 (sieges off is
## byte-identical) and S9 (integrity) hold. Every other band is a target range we tune toward and not a hard cap (Alex,
## 10-8): it is reported pass or miss with the diagnostic behind a miss.
##
##   godot --headless --path . -s tools/autoplay/autoplay.gd -- --matrix --sieges --independents --jobs 4
##
## The balance contract config is --independents (Alex, 10-5): Free Holds garrisons in every neutral province, in the siege
## games, the baseline and the turtle games alike. A plain run is report-only for the balance bands.
##
## What is played (cells: one build per seat, one seat order, paths on or off, a run of seeds):
##   S   every Crown preset x every Clans preset (9 pairings) x both seat orders x paths off and on (the side of the fork
##       rolled, as an AI seat rolls it), CELL_GAMES each: 900 games. A pairing with fewer than MIN_DECISIVE decisive games
##       plays its games again on the next seeds, once.
##   S0  the same cells and seeds with sieges off: the baseline for bands S1 and S6 (doubled with its pairing).
##   S7  TURTLE_GAMES games of each of four cells: the `turtle` policy (Policies.Turtle) in either seat, either faction,
##       against `ai`, sieges on, rulers on, builds rolled. S7b is the same four cells with sieges off (report).
##   S8  M2_PER_CELL games of every cell of the M2 matrix with sieges, paths and independents off, on the seeds and turn cap
##       of the fixture M2_FIXTURE: each game record's md5 must equal the one recorded on main (as band P7). The games of
##       tests/fixtures/main_records.json and m4_path_records.json are replayed turn by turn too (replay_off_fixtures).
##
## The bands (§11.2): S1 length, S2 sieges happen, S3 storm or wait, S4 forts built and not spammed, S5 recruiting at forts
## matters, S6 nothing new dominates, S7 turtling loses, S8 off is identical, S9 integrity, S10 defence works (report).
##
## Every game is seeded exactly as in autoplay.gd, so any game can be replayed alone:
## `--games 1 --seed S --p1 ai --p2 ai --seat1 F --rulers --sieges --builds A,B` (add --paths, --independents as the cell has).

const Simulator := preload("res://tools/autoplay/simulator.gd")
const Matrix := preload("res://tools/autoplay/matrix.gd")
const PathMatrix := preload("res://tools/autoplay/path_matrix.gd")

const FACTIONS := ["kingdom", "beasts"]
const POLICY := "ai"
## Games per cell (one preset pairing, one seat order, paths on or off), before --scale.
const CELL_GAMES := 25
## A preset pairing with fewer decisive siege games than this (scaled) is played again on the next seeds, once.
const MIN_DECISIVE := 60
const REPLAY_EVERY := 10
## Band S7: games per cell (four cells: the turtle as either faction, in either seat), before --scale.
const TURTLE_GAMES := 25
## Band S8: games per M2 matrix cell, compared with the fixture's record digests.
const M2_PER_CELL := PathMatrix.M2_PER_CELL
const M2_FIXTURE := PathMatrix.M2_FIXTURE
const MAIN_RECORDS := "res://tests/fixtures/main_records.json"
const PATH_RECORDS := "res://tests/fixtures/m4_path_records.json"

## The targets of §11.2, so the table and the tests read the same numbers.
const S1_BAND := [12.0, 22.0]
const S1_CAP_MAX := 0.05
const S2_SHARE := 0.60
const S2_BY_TURN := 12
const S3_BAND := [0.15, 0.60]
const S3_WIN_BAND := [0.55, 0.85]
const S4_BAND := [1.0, 3.0]
const S4_P95_MAX := 5
const S5_BAND := [0.10, 0.50]
const S6_MAX := 0.65
const S7_WIN_MAX := 0.10
const S7_CAP_MAX := 0.10
const S10_SHARE := 0.10


# --- the games --------------------------------------------------------------------------------------

static func other(faction_id: String) -> String:
	return FACTIONS[1] if faction_id == FACTIONS[0] else FACTIONS[0]


## The games to play: [{"id", "band" ("S" | "S0" | "S7" | "S7b" | "S8"), "pairing", "seats", "policies", "builds", "paths",
## "sieges", "games", "seed", "turn_cap" (S8 only)}]. Cell ids are stable, so a parallel worker finds its cell by id.
## `fixture` is the S8 fixture (PathMatrix.load_fixture), whose seed and turn cap S8 uses; `m2` false leaves S8 out.
static func plan(scale: float = 1.0, base_seed: int = 1, fixture: Dictionary = {}, m2: bool = true) -> Array:
	var cells := []
	var n := maxi(1, roundi(CELL_GAMES * scale))
	var crown: Array = RulerRules.presets_for("kingdom").map(func(p): return str(p.id))
	var clans: Array = RulerRules.presets_for("beasts").map(func(p): return str(p.id))
	for with_paths in [false, true]:
		var mode := "paths" if with_paths else "plain"
		for c in crown:
			for k in clans:
				var pairing := "%s|%s" % [c, k]
				for crown_first in [true, false]:
					var seats := ["kingdom", "beasts"] if crown_first else ["beasts", "kingdom"]
					var builds := [c, k] if crown_first else [k, c]
					var tail := "%s:%s+%s" % [mode, builds[0], builds[1]]
					for sieges in [true, false]:
						cells.append({"id": ("S:" if sieges else "S0:") + tail + (":kb" if crown_first else ":bk"),
							"band": "S" if sieges else "S0", "pairing": pairing, "seats": seats.duplicate(), "policies": [POLICY, POLICY],
							"builds": builds.duplicate(), "paths": with_paths, "sieges": sieges, "games": n, "seed": base_seed})
	var t := maxi(1, roundi(TURTLE_GAMES * scale))
	for sieges in [true, false]:
		for turtle_faction in FACTIONS:
			for turtle_first in [true, false]:
				var seats: Array = [turtle_faction, other(turtle_faction)]
				var policies := ["turtle", POLICY]
				if not turtle_first:
					seats = [other(turtle_faction), turtle_faction]
					policies = [POLICY, "turtle"]
				cells.append({"id": "%s:turtle_%s_seat%d" % ["S7" if sieges else "S7b", turtle_faction, 1 if turtle_first else 2],
					"band": "S7" if sieges else "S7b", "pairing": "S7", "seats": seats, "policies": policies, "builds": ["", ""],
					"paths": false, "sieges": sieges, "games": t, "seed": base_seed})
	if m2:
		var m2_seed := int(fixture.get("seed", 1))
		var m2_cap := int(fixture.get("turn_cap", Simulator.TURN_CAP))
		for c in Matrix.plan(1.0, m2_seed):
			cells.append({"id": "S8:" + str(c.id), "band": "S8", "pairing": "S8", "seats": c.seats.duplicate(), "policies": [POLICY, POLICY],
				"builds": c.builds.duplicate(), "paths": false, "sieges": false, "games": M2_PER_CELL, "seed": m2_seed, "turn_cap": m2_cap})
	return cells


static func find_cell(cells: Array, cell_id: String) -> Dictionary:
	for c in cells:
		if str(c.id) == cell_id:
			return c
	return {}


## Whether a cell id matches --only: it contains every text of `only`, which joins several with "&" ("S:&beast_god").
static func matches(cell_id: String, only: String) -> bool:
	for part in only.split("&", false):
		if not cell_id.contains(part):
			return false
	return true


## Whether a cell's games are played again with its pairing when the pairing is short of decisive games: the siege games
## and their baseline, so both keep the same seeds.
static func doubles(cell: Dictionary) -> bool:
	return str(cell.band) == "S" or str(cell.band) == "S0"


## Plays one work item ({"cell", "from", "count"}) and returns its results (play_game results without "final_state",
## each with "cell", "band", "pairing", "paths" and "sieges" added). `independents` (--independents, the balance contract) plays
## every game with Free Holds garrisons but band S8's, which are compared with M2 records made without them; the cell decides
## whether sieges are on.
static func play_item(cells: Array, item: Dictionary, turn_cap: int, probe: Callable = Callable(), independents := false) -> Array:
	var cell := find_cell(cells, str(item.cell))
	var out := []
	if cell.is_empty():
		return out
	for i in int(item.count):
		var game_seed: int = int(item.from) + i
		var options := {"rulers": true, "builds": cell.builds.duplicate(), "paths": bool(cell.paths), "branches": [],
			"replay_check": str(cell.band) == "S" and (game_seed - int(cell.seed)) % REPLAY_EVERY == 0, "record_digest": str(cell.band) == "S8"}
		options["independents"] = independents and str(cell.band) != "S8"
		options["sieges"] = bool(cell.sieges)
		var r := Simulator.play_game(game_seed, cell.seats, cell.policies, int(cell.get("turn_cap", turn_cap)), probe, options)
		r.erase("final_state")
		r["cell"] = str(cell.id)
		r["band"] = str(cell.band)
		r["pairing"] = str(cell.pairing)
		r["with_paths"] = bool(cell.paths)
		r["with_sieges"] = bool(cell.sieges)
		out.append(r)
	return out


## Which preset pairings need their games doubled: {pairing: true} for those with fewer than the scaled MIN_DECISIVE
## decisive siege games.
static func short_pairings(results: Array, scale: float) -> Dictionary:
	var dec := {}
	var seen := {}
	for r in results:
		if str(r.band) != "S":
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


## Band S8's turn-by-turn replays: every record in main_records.json (M1 and M2 games) and m4_path_records.json (M4 games)
## is replayed with the current engine and must match the digest of every turn's state and events, and the final state,
## byte for byte (as tests/test_sieges_off.gd does). Returns {"games", "identical", "first" (what differed, in words)}.
static func replay_off_fixtures() -> Dictionary:
	var out := {"games": 0, "identical": 0, "first": ""}
	for path in [MAIN_RECORDS, PATH_RECORDS]:
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (data is Dictionary):
			out.first = "%s did not load" % path
			continue
		for g in data.get("games", []):
			out.games += 1
			var why := _replay_one(g)
			if why.is_empty():
				out.identical += 1
			elif str(out.first).is_empty():
				out.first = "%s: %s" % [g.get("name", "?"), why]
	return out


static func _replay_one(g: Dictionary) -> String:
	var rec: Dictionary = g.record
	var errors := []
	var state := GameState.from_dict(rec.start_state, errors)
	if state == null:
		return "the start state did not load (%s)" % ", ".join(errors)
	if state.sieges:
		return "the record has sieges on"
	var Fixture = load("res://tools/replay_fixture.gd")
	for i in rec.history.size():
		var entry: Dictionary = rec.history[i]
		var orders := OrderBook.orders_from_dict(entry.orders, errors)
		var result := TurnResolver.resolve(state, orders, Serial.to_int(entry.seed), AutoBattleResolver.new())
		state = result.new_state
		var d: Dictionary = Fixture.digest(state, result.events)
		if d.state != g.turns[i].state:
			return "turn %d: the state is not the one main reached" % (i + 1)
		if d.events != g.turns[i].events:
			return "turn %d: the events are not the ones main made" % (i + 1)
	if JSON.stringify(state.to_dict()) != str(g.final_state):
		return "the final state is not the one main reached"
	return ""


# --- helpers ----------------------------------------------------------------------------------------

static func _in(v: float, band: Array) -> bool:
	return v >= float(band[0]) - 0.000001 and v <= float(band[1]) + 0.000001


static func _pct(v: float) -> String:
	return "%d%%" % roundi(100.0 * v)


static func _ratio(n, d) -> float:
	return 0.0 if int(d) == 0 else float(n) / float(d)


## The q-th percentile (0..1) of `values`, nearest rank; 0 for an empty list.
static func percentile(values: Array, q: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[clampi(ceili(q * sorted.size()) - 1, 0, sorted.size() - 1)])


static func _of_band(results: Array, band: String) -> Array:
	return results.filter(func(r): return str(r.band) == band)


static func _decisive_lengths(results: Array) -> Array:
	var out := []
	for r in results:
		if Matrix.decisive(r):
			out.append(int(r.turns))
	return out


static func _capped(results: Array) -> int:
	return results.filter(func(r): return not bool(r.finished)).size()


static func _wins(results: Array, faction_id: String) -> int:
	return results.filter(func(r): return Matrix.decisive(r) and str(r.winner) == faction_id).size()


static func _decisive_count(results: Array) -> int:
	return results.filter(func(r): return Matrix.decisive(r)).size()


## "median 18 (4-60); 21 of 900 at the cap (2%)".
static func _length_text(results: Array) -> String:
	var ls := Simulator.stats_of(_decisive_lengths(results))
	var capped := _capped(results)
	return "median %s (%d-%d); %d of %d at the cap (%s)" % [Simulator._num(ls.median), ls.min, ls.max, capped, results.size(),
		_pct(_ratio(capped, results.size()))]


## The battles at forts of all `results`' games (siege log entries), each with its game's seed.
static func _siege_battles(results: Array) -> Array:
	var out := []
	for r in results:
		for b in r.get("sieges", {}).get("battles", []):
			out.append(b)
	return out


## The pairing label "Warrior King vs Beast-God Unbound" for a "crown|clans" key.
static func pairing_name(key: String) -> String:
	return " vs ".join(Array(key.split("|")).map(func(b): return Simulator.build_name(str(b))))


# --- judging the bands -------------------------------------------------------------------------------

## Per faction-game (both factions of every siege game): forts built. A fort is a place, so it is a palisade finished where
## there was none; a keep made of a palisade is the same fort one level up (§2.4's "four or five palisades, or two keeps"),
## and `upgrades` counts those instead.
static func forts_built_counts(s_res: Array, upgrades := false) -> Array:
	var out := []
	for r in s_res:
		var built: Dictionary = r.get("sieges", {}).get("built", {})
		for fid in r.seats:
			out.append(int(built.get(fid, {}).get("keep" if upgrades else "palisade", 0)))
	return out


## Recruits by place over `results`: {"capital", "palisade", "keep", "ruler", "engines"} summed.
static func recruit_totals(results: Array) -> Dictionary:
	var out := {"capital": 0, "palisade": 0, "keep": 0, "ruler": 0, "engines": 0}
	for r in results:
		var rec: Dictionary = r.get("sieges", {}).get("recruits", {})
		for fid in rec:
			for key in out:
				out[key] += int(rec[fid].get(key, 0))
	return out


## Storms among the battles at forts (excluding arrivals at empty forts): {"battles", "storms", "storms_won" (the stormers
## won), "by_why": {why: n}}.
static func storm_counts(s_res: Array) -> Dictionary:
	var out := {"battles": 0, "storms": 0, "storms_won": 0, "by_why": {}}
	for b in _siege_battles(s_res):
		out.battles += 1
		out.by_why[b.why] = int(out.by_why.get(b.why, 0)) + 1
		if str(b.kind) == "storm":
			out.storms += 1
			if bool(b.attacker_won):
				out.storms_won += 1
	return out


## How the games' capitals fell: {"storm", "breach", "open", "walked_in"} over decisive games that have a record.
static func capital_counts(s_res: Array) -> Dictionary:
	var out := {"storm": 0, "breach": 0, "open": 0, "walked_in": 0, "total": 0}
	for r in s_res:
		var ct: Dictionary = r.get("sieges", {}).get("capital_taken", {})
		if not Matrix.decisive(r) or ct.is_empty():
			continue
		out.total += 1
		out[str(ct.how)] = int(out.get(str(ct.how), 0)) + 1
	return out


## Sieges that ended, by how: {"started", "ended", "by": {label: n}, "defence" (ended by a sally or a relief that won)}.
## A lifted siege "by" sally, gate, relief or relief_sally means the garrison's side won in the open.
static func ending_counts(s_res: Array) -> Dictionary:
	var out := {"started": 0, "ended": 0, "by": {}, "defence": 0, "lengths": []}
	for r in s_res:
		var sg: Dictionary = r.get("sieges", {})
		out.started += sg.get("started", []).size()
		for en in sg.get("ended", []):
			out.ended += 1
			out.lengths.append(int(en.length))
			var label := ending_label(en)
			out.by[label] = int(out.by.get(label, 0)) + 1
			if str(en.kind) == "lifted" and ["sally", "gate", "relief", "relief_sally"].has(str(en.by)):
				out.defence += 1
	return out


## A siege's end in words: "stormed" / "breached" / "fell in the open" (fallen after a battle), "garrison left"
## (fallen with no battle), "beaten by a sally or relief" / "besiegers left" (lifted).
static func ending_label(en: Dictionary) -> String:
	if str(en.kind) == "fallen":
		match str(en.by):
			"storm":
				return "fort stormed"
			"breach":
				return "fort fell at the breach"
			"":
				return "garrison left, fort walked into"
			_:
				return "fort fell in the open (%s)" % str(en.by)
	if str(en.why) == "beaten":
		return "siege beaten by a sally or relief" if ["sally", "gate", "relief", "relief_sally"].has(str(en.by)) else "siege beaten (%s)" % str(en.by)
	return "besiegers left"


## Judges every band. `results` are all games played; `stray_errors` script errors logged outside games; `fixture` the S8
## fixture; `off` replay_off_fixtures()'s answer ({} when it wasn't run). Returns {"bands": [{"band", "what", "target",
## "result", "status" ("pass" | "miss" | "report"), "detail"}], "ok": bool (S8 and S9 hold), "pairings", "turtle", "s_results"
## and the other lists to_markdown prints}.
static func judge(results: Array, stray_errors: int = 0, fixture: Dictionary = {}, off: Dictionary = {}) -> Dictionary:
	var s_res := _of_band(results, "S")
	var b_res := _of_band(results, "S0")
	var t_res := _of_band(results, "S7")
	var tb_res := _of_band(results, "S7b")
	var m2_res := _of_band(results, "S8")
	var bands := []

	# S1: length.
	var lengths := _decisive_lengths(s_res)
	var ls := Simulator.stats_of(lengths)
	var capped := _capped(s_res)
	var cap_share := _ratio(capped, s_res.size())
	var base_ls := Simulator.stats_of(_decisive_lengths(b_res))
	var s1_ok := not s_res.is_empty() and _in(float(ls.median), S1_BAND) and cap_share <= S1_CAP_MAX + 0.000001
	bands.append({"band": "S1", "what": "length", "target": "median decisive game 12-22 turns; at most 5% at the turn cap",
		"result": "%s. Sieges off, same seeds: %s" % [_length_text(s_res), _length_text(b_res)], "status": "pass" if s1_ok else "miss",
		"detail": _cap_detail(s_res) if capped > 0 and not s1_ok else ""})

	# S2: sieges happen.
	var reached := 0
	var with_siege := 0
	for r in s_res:
		if int(r.turns) >= S2_BY_TURN:
			reached += 1
			if not r.get("sieges", {}).get("started", []).is_empty():
				with_siege += 1
	var s2_share := _ratio(with_siege, reached)
	var caps := capital_counts(s_res)
	bands.append({"band": "S2", "what": "sieges happen", "target": "a siege starts in 60%+ of games reaching turn 12; report the share of capitals taken by storm or through a breach",
		"result": "a siege in %d of %d games reaching turn 12 (%s); capitals taken by storm %d, through a breach %d, in an open battle %d, walked into %d (of %d decisive games: %s by storm or breach)" % [
			with_siege, reached, _pct(s2_share), caps.storm, caps.breach, caps.open, caps.walked_in, caps.total,
			_pct(_ratio(int(caps.storm) + int(caps.breach), caps.total))],
		"status": "pass" if reached > 0 and s2_share >= S2_SHARE - 0.000001 else "miss", "detail": ""})

	# S3: storm or wait.
	var sc := storm_counts(s_res)
	var storm_share := _ratio(sc.storms, sc.battles)
	var win_share := _ratio(sc.storms_won, sc.storms)
	var whys := []
	var why_keys: Array = sc.by_why.keys()
	why_keys.sort()
	for k in why_keys:
		whys.append("%s %d" % [k, sc.by_why[k]])
	bands.append({"band": "S3", "what": "storm or wait", "target": "storms are 15-60% of the battles at a fort with a siege; the AI's storm win rate 55-85% (expected)",
		"result": "%d storms in %d battles (%s); stormers won %d of %d (%s). By kind: %s" % [sc.storms, sc.battles, _pct(storm_share), sc.storms_won,
			sc.storms, _pct(win_share), ", ".join(whys)],
		"status": "pass" if sc.battles > 0 and _in(storm_share, S3_BAND) else "miss",
		"detail": "" if sc.storms == 0 or _in(win_share, S3_WIN_BAND) else "the storm win rate %s is outside the expected 55-85%%" % _pct(win_share)})

	# S4: forts built, not spammed.
	var built := forts_built_counts(s_res)
	var bs := Simulator.stats_of(built)
	var p95 := percentile(built, 0.95)
	var s4_ok := not built.is_empty() and _in(float(bs.median), S4_BAND) and p95 <= S4_P95_MAX + 0.000001
	var pal := 0
	var keeps := 0
	for r in s_res:
		for fid in r.get("sieges", {}).get("built", {}):
			pal += int(r.sieges.built[fid].get("palisade", 0))
			keeps += int(r.sieges.built[fid].get("keep", 0))
	var every_level := forts_built_counts(s_res)
	var ups := forts_built_counts(s_res, true)
	for i in every_level.size():
		every_level[i] = int(every_level[i]) + int(ups[i])
	bands.append({"band": "S4", "what": "forts built, not spammed", "target": "median forts built per faction per game 1-3; 95th percentile 5 or fewer (a fort is a place: a keep made of a palisade is the same fort)",
		"result": "median %s, mean %.1f, 95th percentile %s, most %d (%d palisades finished in %d faction-games, %d of them made keeps; counting every level finished, the 95th percentile is %s and the most %d)" % [
			Simulator._num(bs.median), bs.mean, Simulator._num(p95), bs.max, pal, built.size(), keeps, Simulator._num(percentile(every_level, 0.95)),
			Simulator.stats_of(every_level).max],
		"status": "pass" if s4_ok else "miss", "detail": ""})

	# S5: recruiting at forts matters.
	var rt := recruit_totals(s_res)
	var at_forts := int(rt.capital) + int(rt.palisade) + int(rt.keep)
	var outside := int(rt.palisade) + int(rt.keep)
	var out_share := _ratio(outside, at_forts)
	var with_muster := _ratio(outside + int(rt.ruler), at_forts + int(rt.ruler))
	bands.append({"band": "S5", "what": "recruiting at forts matters", "target": "10-50% of recruits made outside the capital",
		"result": "%s of recruits at forts were made outside the capital (%d palisade, %d keep, %d capital; %s counting the %d Warband Muster recruits); %d engines" % [
			_pct(out_share), rt.palisade, rt.keep, rt.capital, _pct(with_muster), rt.ruler, rt.engines],
		"status": "pass" if at_forts > 0 and _in(out_share, S5_BAND) else "miss", "detail": ""})

	# S6: nothing new dominates.
	var pairings := pairing_table(s_res, b_res)
	var new_dominant := []
	var worst := {"share": 0.0, "text": ""}
	for pr in pairings:
		if int(pr.decisive) > 0 and float(pr.worst) > float(worst.share):
			worst = {"share": float(pr.worst), "text": "%s %s" % [pairing_name(str(pr.pairing)), _pct(float(pr.worst))]}
		if bool(pr.new_dominant):
			new_dominant.append("%s: %s (%s)" % [pairing_name(str(pr.pairing)), _pct(float(pr.worst)), _dominance_text(pr)])
	var crown_w := _wins(s_res, "kingdom")
	var dec := _decisive_count(s_res)
	var base_crown := _wins(b_res, "kingdom")
	var base_dec := _decisive_count(b_res)
	bands.append({"band": "S6", "what": "nothing new dominates", "target": "no pairing above 65% that was at or below 65% with sieges off on the same seeds; Crown / Clans reported",
		"result": "worst pairing: %s; %d of %d pairings newly above 65%%. Crown / Clans %s / %s (sieges off %s / %s)" % [
			worst.text, new_dominant.size(), pairings.size(), _pct(_ratio(crown_w, dec)), _pct(1.0 - _ratio(crown_w, dec)),
			_pct(_ratio(base_crown, base_dec)), _pct(1.0 - _ratio(base_crown, base_dec))],
		"status": "pass" if not pairings.is_empty() and new_dominant.is_empty() else "miss",
		"detail": "" if new_dominant.is_empty() else "newly above 65%%: %s. A miss goes to Alex rather than being tuned silently." % "; ".join(new_dominant)})

	# S7: turtling loses.
	var tw := t_res.filter(func(r): return Matrix.decisive(r) and str(r.policies[int(r.winner_seat) - 1]) == "turtle").size()
	var td := _decisive_count(t_res)
	var tcap := _capped(t_res)
	var tb_w := tb_res.filter(func(r): return Matrix.decisive(r) and str(r.policies[int(r.winner_seat) - 1]) == "turtle").size()
	var tb_d := _decisive_count(tb_res)
	var s7_ok := td > 0 and _ratio(tw, td) <= S7_WIN_MAX + 0.000001 and _ratio(tcap, t_res.size()) <= S7_CAP_MAX + 0.000001
	bands.append({"band": "S7", "what": "turtling loses", "target": "the turtle wins 10% or fewer of decisive games, and at most 10% reach the cap",
		"result": "the turtle won %d of %d decisive games (%s); %d of %d at the cap (%s). Sieges off: won %d of %d (%s), %d of %d at the cap" % [
			tw, td, _pct(_ratio(tw, td)), tcap, t_res.size(), _pct(_ratio(tcap, t_res.size())), tb_w, tb_d, _pct(_ratio(tb_w, tb_d)),
			_capped(tb_res), tb_res.size()],
		"status": "pass" if s7_ok else "miss", "detail": _turtle_detail(t_res) if not s7_ok else ""})

	# S8: off is identical.
	var digests: Dictionary = fixture.get("digests", {})
	var same := 0
	var differ := []
	var missing := 0
	for r in m2_res:
		var key := "%s|%d" % [str(r.cell).trim_prefix("S8:"), int(r.seed)]
		if not digests.has(key):
			missing += 1
		elif str(digests[key]) == str(r.get("record_md5", "")):
			same += 1
		else:
			differ.append(key)
	var ran_off := not off.is_empty()
	var off_ok := ran_off and int(off.games) > 0 and int(off.identical) == int(off.games)
	var s8_ok := off_ok and not m2_res.is_empty() and same == m2_res.size()
	var s8_detail := ""
	if not ran_off:
		s8_detail = "the fixture replays were not run (--only)"
	elif not m2_res.is_empty() and not differ.is_empty():
		s8_detail = "first differing M2 game: %s" % differ[0]
	elif not str(off.get("first", "")).is_empty():
		s8_detail = str(off.first)
	elif digests.is_empty():
		s8_detail = "the fixture %s is missing" % M2_FIXTURE
	elif missing > 0:
		s8_detail = "%d M2 games are not in the fixture" % missing
	bands.append({"band": "S8", "what": "off is identical", "target": "sieges off: main_records.json, m4_path_records.json and the M2 matrix games replay byte-identically",
		"result": "%d of %d fixture games replay turn by turn identically to main; %d of %d M2 matrix game records identical" % [
			int(off.get("identical", 0)), int(off.get("games", 0)), same, m2_res.size()],
		"status": "pass" if s8_ok else ("miss" if ran_off or not m2_res.is_empty() else "report"), "detail": s8_detail})

	# S9: integrity, every game.
	var viol := 0
	var errs := 0
	var scr := stray_errors
	var replays := 0
	var replay_bad := []
	var checks := 0
	var mismatches := 0
	var first := ""
	var by_check := {}
	for r in results:
		viol += r.violations.size()
		errs += r.errors.size()
		scr += r.script_errors.size()
		for v in r.violations:
			by_check[v.check] = int(by_check.get(v.check, 0)) + 1
		if first.is_empty():
			for key in ["violations", "errors", "script_errors"]:
				if not r[key].is_empty() and first.is_empty():
					first = "seed %d (%s): %s" % [r.seed, r.cell, r[key][0].get("detail", r[key][0].get("check", ""))]
		if not str(r.replay).is_empty():
			replays += 1
			if str(r.replay) != "identical":
				replay_bad.append("seed %d (%s): %s" % [r.seed, r.cell, r.replay])
		var fc: Dictionary = r.get("sieges", {}).get("forecast", {})
		checks += int(fc.get("checks", 0))
		mismatches += int(fc.get("mismatches", 0))
		if first.is_empty() and not str(fc.get("first", "")).is_empty():
			first = "seed %d (%s): %s" % [r.seed, r.cell, fc.first]
	var s9_ok := viol == 0 and errs == 0 and scr == 0 and replay_bad.is_empty() and replays > 0 and mismatches == 0
	var s9_detail := first
	if not replay_bad.is_empty():
		s9_detail = ("%s; " % first if not first.is_empty() else "") + replay_bad[0]
	if viol > 0:
		var parts := []
		for k in by_check:
			parts.append("%s %d" % [k, by_check[k]])
		parts.sort()
		s9_detail = ("%s; " % ", ".join(parts)) + s9_detail
	bands.append({"band": "S9", "what": "integrity, every game", "target": "0 invariant violations, session errors, script errors and siege forecast mismatches; every 10th siege game replays identically",
		"result": "%d violations, %d session errors, %d script errors; %d of %d replays identical (%d games); siege forecasts: %d mismatches in %d checks" % [
			viol, errs, scr, replays - replay_bad.size(), replays, results.size(), mismatches, checks],
		"status": "pass" if s9_ok else "miss", "detail": s9_detail})

	# S10: defence works (report).
	var ec := ending_counts(s_res)
	var relief_chances := 0
	var relief_taken := 0
	for r in s_res:
		var rl: Dictionary = r.get("sieges", {}).get("relief", {})
		relief_chances += int(rl.get("chances", 0))
		relief_taken += int(rl.get("taken", 0))
	var def_share := _ratio(ec.defence, ec.started)
	var storm_orders := 0
	var sally_orders := 0
	for r in s_res:
		storm_orders += int(r.get("sieges", {}).get("orders", {}).get("storm", 0))
		sally_orders += int(r.get("sieges", {}).get("orders", {}).get("sally", 0))
	bands.append({"band": "S10", "what": "defence works (report)", "target": "report (10%+ of sieges ended by a sally or relief)",
		"result": "%s of sieges ended by a sally or relief (%d of %d started); relief chances taken %d of %d (%s); %d storm orders and %d sally orders" % [
			_pct(def_share), ec.defence, ec.started, relief_taken, relief_chances, _pct(_ratio(relief_taken, relief_chances)),
			storm_orders, sally_orders], "status": "report", "detail": "under 10%" if def_share < S10_SHARE else ""})
	return {"bands": bands, "ok": s8_ok and s9_ok if ran_off or not m2_res.is_empty() else s9_ok, "s8_ok": s8_ok, "s9_ok": s9_ok,
		"pairings": pairings, "s_results": s_res, "b_results": b_res, "t_results": t_res, "tb_results": tb_res, "ended": ec, "captured": caps}


## What one pairing's tilt rests on, for the S6 note: the leading side's wins of the decisive siege games with a 95% range
## (Wilson), the same with sieges off, and how many standard errors apart the two are. A tilt of a few points over 100 games is
## noise; one of 15 points or more over 200 games is not.
static func _dominance_text(pr: Dictionary) -> String:
	var crown_leads := _ratio(pr.crown_wins, pr.decisive) >= 0.5
	var wins := int(pr.crown_wins) if crown_leads else int(pr.decisive) - int(pr.crown_wins)
	var base_wins := int(pr.base_crown_wins) if crown_leads else int(pr.base_decisive) - int(pr.base_crown_wins)
	var lo_hi := wilson(wins, int(pr.decisive))
	var p1 := _ratio(wins, pr.decisive)
	var p2 := _ratio(base_wins, pr.base_decisive)
	var se := sqrt(p1 * (1.0 - p1) / maxf(1.0, float(pr.decisive)) + p2 * (1.0 - p2) / maxf(1.0, float(pr.base_decisive)))
	return "%s side: %d of %d decisive, 95%% range %s-%s; sieges off %d of %d (%s); %.1f standard errors apart" % [
		"Crown" if crown_leads else "Clans", wins, pr.decisive, _pct(lo_hi[0]), _pct(lo_hi[1]), base_wins, pr.base_decisive, _pct(p2),
		(p1 - p2) / se if se > 0.0 else 0.0]


## The Wilson 95% range [low, high] of `wins` out of `n` (0..1).
static func wilson(wins: int, n: int) -> Array:
	if n <= 0:
		return [0.0, 1.0]
	var z := 1.96
	var p := float(wins) / n
	var denom := 1.0 + z * z / n
	var centre := (p + z * z / (2.0 * n)) / denom
	var half := z * sqrt(p * (1.0 - p) / n + z * z / (4.0 * n * n)) / denom
	return [maxf(0.0, centre - half), minf(1.0, centre + half)]


## Why games hit the cap: how many had no siege at all, and the presets in them, most common first.
static func _cap_detail(s_res: Array) -> String:
	var by := {}
	var n := 0
	var no_siege := 0
	var at_keeps := 0
	for r in s_res:
		if bool(r.finished):
			continue
		n += 1
		if r.get("sieges", {}).get("started", []).is_empty():
			no_siege += 1
		for fid in r.builds:
			var id := str(r.builds[fid])
			by[id] = int(by.get(id, 0)) + 1
		var rec: Dictionary = r.get("sieges", {}).get("recruits", {})
		var out_of_capital := 0
		var total := 0
		for fid in rec:
			out_of_capital += int(rec[fid].get("palisade", 0)) + int(rec[fid].get("keep", 0))
			total += int(rec[fid].get("capital", 0)) + int(rec[fid].get("palisade", 0)) + int(rec[fid].get("keep", 0))
		if total > 0 and out_of_capital * 2 > total:
			at_keeps += 1
	var keys: Array = by.keys()
	keys.sort_custom(func(a, b): return by[a] > by[b] if by[a] != by[b] else str(a) < str(b))
	return "%d capped games: %d had no siege at all, %d recruited mostly outside the capital; presets in them (of %d capped games, two per game): %s" % [
		n, no_siege, at_keeps, n, ", ".join(keys.slice(0, 5).map(func(k): return "%s %d" % [Simulator.build_name(str(k)), by[k]]))]


## What the turtle did in its siege games: how its games ended, and how often its capital was besieged.
static func _turtle_detail(t_res: Array) -> String:
	var won := 0
	var by_how := {}
	var capped := 0
	var built := 0
	for r in t_res:
		var turtle_faction := ""
		for i in r.policies.size():
			if str(r.policies[i]) == "turtle":
				turtle_faction = str(r.seats[i])
		var sg: Dictionary = r.get("sieges", {})
		built += int(sg.get("built", {}).get(turtle_faction, {}).get("palisade", 0)) + int(sg.get("built", {}).get(turtle_faction, {}).get("keep", 0))
		if not bool(r.finished):
			capped += 1
			continue
		if str(r.winner) == turtle_faction:
			won += 1
		var how := str(sg.get("capital_taken", {}).get("how", "?"))
		by_how[how] = int(by_how.get(how, 0)) + 1
	var parts := []
	for k in by_how:
		parts.append("%s %d" % [k, by_how[k]])
	parts.sort()
	return "%d games: turtle won %d, %d at the cap; capitals fell by %s; the turtle finished %d forts in all" % [t_res.size(), won, capped,
		", ".join(parts), built]


## Per preset pairing (Crown preset | Clans preset): [{"pairing", "games", "decisive", "crown_wins", "capped", "median",
## "base_games", "base_decisive", "base_crown_wins", "base_capped", "base_median", "worst" (the larger side's share of
## decisive siege games), "base_worst", "new_dominant" (above 65% with sieges, not without)}].
static func pairing_table(s_res: Array, b_res: Array) -> Array:
	var keys := {}
	for r in s_res:
		keys[str(r.pairing)] = true
	var names: Array = keys.keys()
	names.sort()
	var out := []
	for key in names:
		var mine: Array = s_res.filter(func(r): return str(r.pairing) == key)
		var base: Array = b_res.filter(func(r): return str(r.pairing) == key)
		var row := {"pairing": key, "games": mine.size(), "decisive": _decisive_count(mine), "crown_wins": _wins(mine, "kingdom"),
			"capped": _capped(mine), "median": Simulator.stats_of(_decisive_lengths(mine)).median,
			"base_games": base.size(), "base_decisive": _decisive_count(base), "base_crown_wins": _wins(base, "kingdom"),
			"base_capped": _capped(base), "base_median": Simulator.stats_of(_decisive_lengths(base)).median}
		var cw := _ratio(row.crown_wins, row.decisive)
		var bw := _ratio(row.base_crown_wins, row.base_decisive)
		row["worst"] = maxf(cw, 1.0 - cw) if int(row.decisive) > 0 else 0.0
		row["base_worst"] = maxf(bw, 1.0 - bw) if int(row.base_decisive) > 0 else 0.0
		row["new_dominant"] = float(row.worst) > S6_MAX + 0.000001 and float(row.base_worst) <= S6_MAX + 0.000001
		out.append(row)
	return out


# --- the report -------------------------------------------------------------------------------------

## The report sections for `s_res`, the games played with sieges (also what autoplay.gd --sieges prints after its summary):
## siege counts, storms against breaches, forts built, recruits by fort, siege lengths. As markdown lines.
static func sections(s_res: Array) -> Array:
	var L := []
	var games := s_res.size()
	# Siege counts.
	var per_game := []
	var with_siege := 0
	var by_level := {"capital": 0, "keep": 0, "palisade": 0}
	var first_turns := []
	var started_troops := []
	for r in s_res:
		var started: Array = r.get("sieges", {}).get("started", [])
		per_game.append(started.size())
		if not started.is_empty():
			with_siege += 1
			first_turns.append(int(started[0].turn))
		for s in started:
			var k := "capital" if bool(s.capital) else str(FortData.level(int(s.level)).id)
			by_level[k] = int(by_level.get(k, 0)) + 1
			started_troops.append(int(s.troops))
	var pg := Simulator.stats_of(per_game)
	var cut := 0
	for r in s_res:
		cut += int(r.get("sieges", {}).get("cut_off", 0))
	L.append("### Siege counts")
	L.append("")
	L.append("- **Games with a siege:** %d of %d (%s); sieges started per game: mean %.1f, most %d; first siege on turn %s (median). Of all sieges: %d at a capital, %d at a keep, %d at a palisade; the besiegers' troops at the start: median %s." % [
		with_siege, games, _pct(_ratio(with_siege, games)), pg.mean, pg.max, Simulator._num(Simulator.stats_of(first_turns).median),
		by_level.capital, by_level.keep, by_level.palisade, Simulator._num(Simulator.stats_of(started_troops).median)])
	L.append("- **Fort-turns cut off:** %d (%.1f per game)." % [cut, _ratio(cut, games)])
	# Storms against breaches.
	var sc := storm_counts(s_res)
	var ec := ending_counts(s_res)
	var caps := capital_counts(s_res)
	L.append("")
	L.append("### Storms against breaches")
	L.append("")
	var why_names := {"storm": "storms", "breach": "breach battles (the walls were down)", "sally": "sallies", "gate": "storm met at the gate",
		"relief": "relief armies", "relief_sally": "relief with a sally", "rivals": "rivals met outside"}
	var kinds := []
	for why in why_names:
		if int(sc.by_why.get(why, 0)) > 0:
			kinds.append("%d %s" % [sc.by_why[why], why_names[why]])
	L.append("- **Battles at forts with a siege:** %d: %s." % [sc.battles, ", ".join(kinds) if not kinds.is_empty() else "none"])
	L.append("- **Storms:** %d of %d battles (%s); the stormers won %d (%s)." % [sc.storms, sc.battles, _pct(_ratio(sc.storms, sc.battles)),
		sc.storms_won, _pct(_ratio(sc.storms_won, sc.storms))])
	var orders_storm := 0
	var orders_sally := 0
	for r in s_res:
		orders_storm += int(r.get("sieges", {}).get("orders", {}).get("storm", 0))
		orders_sally += int(r.get("sieges", {}).get("orders", {}).get("sally", 0))
	L.append("- **Siege orders accepted:** %d storms, %d sallies." % [orders_storm, orders_sally])
	var ends := []
	var end_keys: Array = ec.by.keys()
	end_keys.sort_custom(func(a, b): return ec.by[a] > ec.by[b] if ec.by[a] != ec.by[b] else str(a) < str(b))
	for k in end_keys:
		ends.append("%s %d (%s)" % [k, ec.by[k], _pct(_ratio(ec.by[k], ec.ended))])
	L.append("- **How sieges ended** (%d ended, %d started; the rest were still standing when the game did): %s." % [ec.ended, ec.started,
		", ".join(ends) if not ends.is_empty() else "none"])
	L.append("- **How capitals fell** (decisive games, %d): storm %d, breach %d, open battle at the gate or ruins %d, walked into %d." % [
		caps.total, caps.storm, caps.breach, caps.open, caps.walked_in])
	# Forts built.
	var built := forts_built_counts(s_res)
	var bs := Simulator.stats_of(built)
	var works := 0
	var finished := 0
	var hist := {}
	for n in built:
		hist[str(mini(int(n), 6))] = int(hist.get(str(mini(int(n), 6)), 0)) + 1
		finished += int(n)
	for r in s_res:
		for fid in r.get("sieges", {}).get("works", {}):
			works += int(r.sieges.works[fid])
	var hist_parts := []
	for k in ["0", "1", "2", "3", "4", "5", "6"]:
		if hist.has(k):
			hist_parts.append("%s%s: %d" % [k, "+" if k == "6" else "", hist[k]])
	L.append("")
	L.append("### Forts built")
	L.append("")
	L.append("- **Per faction per game:** median %s, mean %.1f, 95th percentile %s, most %d. Histogram (faction-games): %s." % [
		Simulator._num(bs.median), bs.mean, Simulator._num(percentile(built, 0.95)), bs.max, ", ".join(hist_parts)])
	var upgrades := 0
	for n in forts_built_counts(s_res, true):
		upgrades += int(n)
	L.append("- **Sites started** (paid): %d; **finished:** %d new forts (palisades) and %d palisades made keeps (the rest were razed, captured or unfinished when the game ended)." % [works, finished, upgrades])
	# Recruits by fort.
	var rt := recruit_totals(s_res)
	var total := int(rt.capital) + int(rt.palisade) + int(rt.keep) + int(rt.ruler)
	L.append("")
	L.append("### Recruits by fort")
	L.append("")
	L.append("- **All recruits:** %d: capital %d (%s), palisades %d (%s), keeps %d (%s), with the ruler (Warband Muster) %d (%s); %d of them siege engines." % [
		total, rt.capital, _pct(_ratio(rt.capital, total)), rt.palisade, _pct(_ratio(rt.palisade, total)), rt.keep, _pct(_ratio(rt.keep, total)),
		rt.ruler, _pct(_ratio(rt.ruler, total)), rt.engines])
	# Siege lengths.
	var ls := Simulator.stats_of(ec.lengths)
	var buckets := {"1": 0, "2": 0, "3": 0, "4-5": 0, "6+": 0}
	for n in ec.lengths:
		var key := "6+" if int(n) >= 6 else ("4-5" if int(n) >= 4 else str(int(n)))
		buckets[key] = int(buckets.get(key, 0)) + 1
	var by_level_len := {}
	for r in s_res:
		for en in r.get("sieges", {}).get("ended", []):
			var k := "capital" if bool(en.capital) else str(FortData.level(int(en.level)).id)
			if not by_level_len.has(k):
				by_level_len[k] = []
			by_level_len[k].append(int(en.length))
	var level_parts := []
	for k in ["capital", "keep", "palisade"]:
		if by_level_len.has(k):
			level_parts.append("%s median %s (%d sieges)" % [k, Simulator._num(Simulator.stats_of(by_level_len[k]).median), by_level_len[k].size()])
	L.append("")
	L.append("### Siege lengths")
	L.append("")
	L.append("- **Turns a siege stood** (ended sieges, %d): median %s, mean %.1f, longest %d. In turns: %s." % [ls.n, Simulator._num(ls.median), ls.mean,
		ls.max, ", ".join(["1", "2", "3", "4-5", "6+"].map(func(k): return "%s: %d" % [k, buckets[k]]))])
	L.append("- **By fort:** %s." % (", ".join(level_parts) if not level_parts.is_empty() else "none"))
	return L


## The whole report as markdown: the bands table, notes on the bands, then the sections, the baseline comparison per
## pairing, the turtle games, and the autoplay report sections for the siege games.
static func to_markdown(j: Dictionary, header: String = "") -> String:
	var L := []
	L.append("## Siege balance check (design/M3C_SIEGES.md §11.2)%s" % ("" if header.is_empty() else ": " + header))
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
	L.append_array(sections(j.s_results))
	L.append("")
	L.append("### The cap share against the sieges-off baseline, by preset pairing (same seeds)")
	L.append("")
	L.append("| Crown preset vs Clans preset | siege games | decisive | Crown wins | at the cap | median length | sieges off: games | decisive | Crown wins | at the cap | median length |")
	L.append("|---|---|---|---|---|---|---|---|---|---|---|")
	for pr in j.pairings:
		L.append("| %s | %d | %d | %d (%s) | %d | %s | %d | %d | %d (%s) | %d | %s |" % [pairing_name(str(pr.pairing)), pr.games, pr.decisive,
			pr.crown_wins, _pct(_ratio(pr.crown_wins, pr.decisive)), pr.capped, Simulator._num(pr.median), pr.base_games, pr.base_decisive,
			pr.base_crown_wins, _pct(_ratio(pr.base_crown_wins, pr.base_decisive)), pr.base_capped, Simulator._num(pr.base_median)])
	var s_res: Array = j.s_results
	var b_res: Array = j.b_results
	L.append("")
	for mode in [[false, "paths off"], [true, "paths on"]]:
		var mine: Array = s_res.filter(func(r): return bool(r.get("with_paths", false)) == mode[0])
		var base: Array = b_res.filter(func(r): return bool(r.get("with_paths", false)) == mode[0])
		if not mine.is_empty():
			L.append("- **%s:** %d siege games, %s; sieges off: %s." % [str(mode[1]).capitalize(), mine.size(), _length_text(mine), _length_text(base)])
	L.append("")
	L.append("### The turtle against the computer (band S7)")
	L.append("")
	L.append("| cell | games | turtle won | computer won | draws | at the cap | sieges off: turtle won | computer won | draws | at the cap |")
	L.append("|---|---|---|---|---|---|---|---|---|---|")
	var t_ids := {}
	for r in j.t_results:
		t_ids[str(r.cell)] = true
	var ids: Array = t_ids.keys()
	ids.sort()
	for id in ids:
		var mine: Array = j.t_results.filter(func(r): return str(r.cell) == id)
		var base: Array = j.tb_results.filter(func(r): return str(r.cell) == "S7b" + id.trim_prefix("S7"))
		L.append("| %s | %d | %s | %s | %d | %d | %s | %s | %d | %d |" % [id.trim_prefix("S7:"), mine.size(), _turtle_won(mine), _ai_won(mine),
			_draws(mine), _capped(mine), _turtle_won(base), _ai_won(base), _draws(base), _capped(base)])
	if not s_res.is_empty() and s_res[0].has("battles"):
		var summary := Simulator.summarize(s_res)
		L.append("")
		L.append("### Siege games: %d" % s_res.size())
		L.append("")
		for line in Simulator.to_markdown(summary).split("\n"):
			if line.begins_with("- **Results") or line.begins_with("- **Game length") or line.begins_with("- **Length buckets") \
					or line.begins_with("- **Battles") or line.begins_with("- **How battles") or line.begins_with("- **Defended") \
					or line.begins_with("- **Top") or line.begins_with("- **Policy counters") or line.begins_with("- **Rejected") \
					or line.begins_with("- **Orders") or line.begins_with("- **Patterns"):
				L.append(line)
	return "\n".join(L)


static func _turtle_won(results: Array) -> String:
	var d := _decisive_count(results)
	var w := results.filter(func(r): return Matrix.decisive(r) and str(r.policies[int(r.winner_seat) - 1]) == "turtle").size()
	return "%d (%s)" % [w, _pct(_ratio(w, d))]


static func _ai_won(results: Array) -> String:
	var d := _decisive_count(results)
	var w := results.filter(func(r): return Matrix.decisive(r) and str(r.policies[int(r.winner_seat) - 1]) != "turtle").size()
	return "%d (%s)" % [w, _pct(_ratio(w, d))]


static func _draws(results: Array) -> int:
	return results.filter(func(r): return bool(r.finished) and bool(r.draw)).size()
