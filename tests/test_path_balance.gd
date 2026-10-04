extends "res://tests/test_case.gd"
## M4-6 (#71): the path balance check (design/M4_ASCENSION.md §10.2). The matrix plan and how its bands are
## judged (tools/autoplay/path_matrix.gd), the simulator's research forecast check (band P8) and record
## digests (band P7), and fast, small-sample checks that the tuned numbers keep: every side of every fork
## wins games of a short fixed-seed autoplay batch, transformations land mid-game, and the new units are
## worth their price at equal gold.
## The full check is `autoplay.gd -- --matrix --paths --jobs 8`; its report is in the PR.

const Simulator := preload("res://tools/autoplay/simulator.gd")
const Matrix := preload("res://tools/autoplay/matrix.gd")
const PathMatrix := preload("res://tools/autoplay/path_matrix.gd")
const Balance := preload("res://tools/balance/balance.gd")


# --- the matrix plan --------------------------------------------------------------------------------

func test_the_path_matrix_plans_every_side_preset_and_seat_order() -> void:
	var fixture := PathMatrix.load_fixture()
	var cells := PathMatrix.plan(1.0, 1, true, fixture)
	var ids := {}
	for c in cells:
		assert_false(ids.has(c.id), "cell ids are unique: %s" % c.id)
		ids[c.id] = true
	var p := cells.filter(func(c): return c.band == "P")
	var crown := RulerRules.presets_for("kingdom").size()
	var clans := RulerRules.presets_for("beasts").size()
	assert_eq(p.size(), 4 * crown * clans * 2, "4 side pairings x every preset pairing x both seat orders")
	var games := 0
	var per_pairing := {}
	for c in p:
		games += int(c.games)
		assert_eq(int(c.games), PathMatrix.CELL_GAMES, "%d games per cell" % PathMatrix.CELL_GAMES)
		assert_true(bool(c.paths), "paths on")
		for seat in 2:
			assert_eq(PathMatrix.faction_of_side(str(c.branches[seat])), c.seats[seat], "seat %d plays one of its own sides" % (seat + 1))
			assert_eq(RulerRules.preset_data(str(c.builds[seat])).faction, c.seats[seat], "seat %d plays one of its own presets" % (seat + 1))
		per_pairing[c.pairing] = int(per_pairing.get(c.pairing, 0)) + int(c.games)
	assert_eq(games, 1800, "§10.2: 1,800 games")
	assert_eq(per_pairing.size(), 4, "every Crown side against every Clans side")
	for pr in per_pairing:
		assert_eq(per_pairing[pr], 450, "%s: 450 games" % pr)
	# Band P7 plays the M2 matrix's cells with paths off, on the fixture's seeds and turn cap.
	var m2 := cells.filter(func(c): return c.band == "P7")
	assert_eq(m2.size(), Matrix.plan(1.0, 1).size(), "one P7 cell per M2 matrix cell")
	for c in m2:
		assert_false(bool(c.paths), "paths off")
		assert_eq(int(c.games), PathMatrix.M2_PER_CELL)
		assert_eq(int(c.turn_cap), int(fixture.turn_cap), "the fixture's turn cap")
	# The fixture holds a digest for every P7 game.
	assert_eq(fixture.digests.size(), m2.size() * PathMatrix.M2_PER_CELL, "a digest per P7 game")
	# --scale shrinks the P band, never P7; work items cover every game once.
	var small := PathMatrix.plan(0.2, 1, true, fixture)
	assert_eq(small.filter(func(c): return c.band == "P")[0].games, 5)
	assert_eq(small.filter(func(c): return c.band == "P7")[0].games, PathMatrix.M2_PER_CELL)
	var total := 0
	for it in Matrix.work_items(cells):
		total += int(it.count)
	var planned := 0
	for c in cells:
		planned += int(c.games)
	assert_eq(total, planned, "every planned game is in exactly one work item")


# --- judging the bands ------------------------------------------------------------------------------

func _game(crown_side: String, clans_side: String, crown_seat: bool, winner: String, turns: int, transform := 9, replay := "") -> Dictionary:
	var seats := ["kingdom", "beasts"] if crown_seat else ["beasts", "kingdom"]
	var sides := [crown_side, clans_side] if crown_seat else [clans_side, crown_side]
	var paths := {}
	for fid in ["kingdom", "beasts"]:
		var side := crown_side if fid == "kingdom" else clans_side
		paths[fid] = {"branch": side, "oath_turn": transform - 3, "transform_turn": transform, "nodes": [], "ordinary_before_oath": 2}
	return {"band": "P", "cell": "P:test", "pairing": "%s|%s" % [crown_side, clans_side], "seed": 1, "seats": seats, "branches": sides,
		"builds": {"kingdom": "warrior_king", "beasts": "clan_moot"}, "finished": winner != "", "draw": false, "winner": winner,
		"turns": turns, "paths": paths, "battles": [{"factors": [{"id": "path_crown_drillyard", "faction": "kingdom"}]}],
		"ruler_log": {"deaths": [], "arrivals": [], "sacrifices": [{"faction": "beasts", "mandate": "blood_frenzy", "turn": 9}] if turns % 2 == 0 else [],
			"mandates": {}}, "violations": [], "errors": [], "script_errors": [], "replay": replay,
		"research": {"turn_checks": 10, "turn_mismatches": 0, "target_checks": 3, "target_mismatches": 0, "first": ""}, "recruits": {}}


func _m2_games(fixture: Dictionary) -> Array:
	var out := []
	for key in fixture.digests:
		var parts := str(key).split("|")
		out.append({"band": "P7", "cell": "P7:" + parts[0], "pairing": "P7", "seed": int(parts[1]), "record_md5": fixture.digests[key],
			"finished": true, "draw": false, "winner": "kingdom", "turns": 20, "violations": [], "errors": [], "script_errors": [], "replay": "",
			"ruler_log": {"deaths": [], "arrivals": [], "sacrifices": [], "mandates": {}}, "research": {}})
	return out


func _band(j: Dictionary, name: String) -> Dictionary:
	for b in j.bands:
		if b.band == name:
			return b
	return {}


func test_path_bands_are_judged_from_the_games() -> void:
	var fixture := PathMatrix.load_fixture()
	var games := []
	# Every side pairing split 5-5 in both seat orders over 13- and 14-turn games, transforming on turn 9.
	for cs in PathMatrix.sides_of("kingdom"):
		for ks in PathMatrix.sides_of("beasts"):
			for i in 10:
				games.append(_game(cs, ks, i % 2 == 0, "kingdom" if i < 5 else "beasts", 13 + i % 2, 9, "identical" if i == 0 else ""))
	var j := PathMatrix.judge(games + _m2_games(fixture), 0, fixture)
	for name in ["P1", "P2", "P3", "P4", "P7", "P8"]:
		assert_eq(_band(j, name).status, "pass", "%s: %s %s" % [name, _band(j, name).result, _band(j, name).detail])
	for name in ["P1d", "P5", "P6"]:
		assert_eq(_band(j, name).status, "report", "%s is report only" % name)
	assert_true(j.ok, "P7 and P8 hold")
	# One side winning 7 of 10 against another misses P2.
	var lop := games.duplicate(true)
	lop[5].winner = "kingdom"
	lop[6].winner = "kingdom"
	assert_eq(_band(PathMatrix.judge(lop + _m2_games(fixture), 0, fixture), "P2").status, "miss")
	# Every Celestial Host game won and every Living Iron game lost misses P1.
	var tilt := games.duplicate(true)
	for g in tilt:
		g.winner = "kingdom" if g.paths.kingdom.branch == "celestial_host" else "beasts"
	assert_eq(_band(PathMatrix.judge(tilt + _m2_games(fixture), 0, fixture), "P1").status, "miss")
	# Late transformations miss P4; long games miss P3.
	var late := games.map(func(g):
		var c: Dictionary = g.duplicate(true)
		for fid in c.paths:
			c.paths[fid].transform_turn = 13
		return c)
	assert_eq(_band(PathMatrix.judge(late + _m2_games(fixture), 0, fixture), "P4").status, "miss")
	var long := games.map(func(g):
		var c: Dictionary = g.duplicate(true)
		c.turns = 30
		return c)
	assert_eq(_band(PathMatrix.judge(long + _m2_games(fixture), 0, fixture), "P3").status, "miss")
	# A research forecast mismatch misses P8, and the exit code follows it.
	var bad := games.duplicate(true)
	bad[0].research.target_mismatches = 1
	var jb := PathMatrix.judge(bad + _m2_games(fixture), 0, fixture)
	assert_eq(_band(jb, "P8").status, "miss")
	assert_false(jb.ok, "the exit code follows P8")
	# An M2 game whose record differs from main misses P7, and so does a missing fixture.
	var m2 := _m2_games(fixture)
	m2[0].record_md5 = "0"
	var jm := PathMatrix.judge(games + m2, 0, fixture)
	assert_eq(_band(jm, "P7").status, "miss", _band(jm, "P7").detail)
	assert_false(jm.ok, "the exit code follows P7")
	assert_eq(_band(PathMatrix.judge(games + _m2_games(fixture), 0, {}), "P7").status, "miss", "no fixture, no pass")
	# A battle whose "why" names a path effect counts for P5; a mandate's part doesn't.
	assert_true(PathMatrix.cites_path({"factors": [{"id": "Wings"}]}))
	assert_true(PathMatrix.cites_path({"factors": [{"id": "morale_path_crown_celestial_host"}]}))
	assert_true(PathMatrix.cites_path({"factors": [{"id": "dread_lands"}]}))
	assert_false(PathMatrix.cites_path({"factors": [{"id": "mandate_blood_frenzy"}, {"id": "Charge"}]}))


# --- the simulator's research forecast check and record digest ---------------------------------------

func test_research_forecasts_equal_the_research_phase_in_a_real_game() -> void:
	var r := Simulator.play_game(5, ["kingdom", "beasts"], ["ai", "ai"], 16, Callable(),
		{"paths": true, "builds": ["regents_court", "beast_god_unbound"], "branches": ["living_iron", "thorn_wild"]})
	assert_eq(r.errors.size() + r.violations.size(), 0, "a clean game")
	assert_true(int(r.research.turn_checks) >= 4, "turns checked (no province changed hands): %d" % r.research.turn_checks)
	assert_true(int(r.research.target_checks) >= 2, "targets checked: %d" % r.research.target_checks)
	assert_eq(int(r.research.turn_mismatches) + int(r.research.target_mismatches), 0, str(r.research.first))
	assert_true(r.recruits.has("kingdom") and r.recruits.has("beasts"), "recruit orders are counted per faction")
	# A forecast that is wrong is caught: the pool after the turn is one off.
	var state := GameState.with_paths(5)
	var prev := GameState.from_dict(state.to_dict())
	var fc := Forecast.research(prev, "kingdom", [ResearchOrder.new("crown_drillyard")])
	var after: GameState = TurnResolver.resolve(prev, {"kingdom": [ResearchOrder.new("crown_drillyard")]}, TurnResolver.seed_for_turn(prev)).new_state
	var out := {"turn_checks": 0, "turn_mismatches": 0, "target_checks": 0, "target_mismatches": 0, "first": ""}
	Simulator.check_research(prev, after, 1, {"kingdom": fc}, {}, out)
	assert_eq([out.turn_checks, out.turn_mismatches], [1, 0], "a true forecast passes")
	var wrong := fc.duplicate()
	wrong.pool = int(wrong.pool) + 1
	var out2 := {"turn_checks": 0, "turn_mismatches": 0, "target_checks": 0, "target_mismatches": 0, "first": ""}
	Simulator.check_research(prev, after, 1, {"kingdom": wrong}, {}, out2)
	assert_eq(out2.turn_mismatches, 1, "a wrong forecast is a mismatch")
	assert_true(str(out2.first).contains("crown_drillyard"), str(out2.first))


func test_m2_games_still_match_the_records_from_main() -> void:
	# Band P7 in miniature: the first P7 cell's first game, played now with paths off, has the record digest
	# recorded on main.
	var fixture := PathMatrix.load_fixture()
	var cells := PathMatrix.plan(1.0, 1, true, fixture).filter(func(c): return c.band == "P7")
	var res := PathMatrix.play_item(cells, {"cell": cells[0].id, "from": int(cells[0].seed), "count": 1}, 60)
	assert_eq(res.size(), 1)
	var key := "%s|%d" % [str(cells[0].id).trim_prefix("P7:"), int(cells[0].seed)]
	assert_eq(str(res[0].record_md5), str(fixture.digests[key]), "%s is byte-identical to main" % key)
	assert_true(res[0].paths.is_empty(), "no paths in an M2 game")
