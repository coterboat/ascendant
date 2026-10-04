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


# --- the tuned numbers: text follows the data ----------------------------------------------------------

## The base stat of a regular unit type from data/factions.gd.
func _base(type_id: String, stat: String) -> int:
	for f in FactionData.FACTIONS:
		for u in f.unit_types:
			if String(u.id) == type_id:
				return int(u[stat])
	return 0


func test_codex_and_cards_state_the_tuned_numbers_from_the_data() -> void:
	for side in PathData.BRANCHES:
		var nid := String(PathData.BRANCHES[side].transformation)
		var fx := AscensionRules.node_effects(nid)
		var text := RulesCodex.text("node_" + nid)
		# The new unit's numbers, as the codex states them.
		var nu: Dictionary = PathData.NEW_UNITS[String(fx.new_unit)]
		var stats := "%d hit points, attack %d, defense %d, morale %d, %d gold" % [nu.hp, nu.attack, nu.defense, nu.morale, nu.cost]
		assert_true(text.contains(stats), "%s states %s: %s" % [nid, stats, text])
		# The changed unit's numbers before and after.
		for type_id in fx.unit:
			for stat in fx.unit[type_id]:
				var before := _base(type_id, String(stat))
				var after := before + int(fx.unit[type_id][stat])
				assert_true(text.contains("(%d to %d)" % [before, after]), "%s states %s %s %d to %d: %s" % [nid, type_id, stat, before, after, text])
		# The province rule's value, where it is a number of hit points.
		var rule: Dictionary = fx.province_rule
		if String(rule.id) == "hallowed_land":
			assert_true(text.contains("heals %d hit points" % int(rule.value)), "%s states Hallowed Land's heal" % nid)
			assert_true(RulesCodex.text("hallowed_land").contains("heals %d hit points" % int(rule.value)))
	# The Oaths' economy rules.
	var dawn := AscensionRules.node_effects("crown_oath_dawn")
	assert_true(RulesCodex.text("tithe_of_light").contains("earns %d more gold for every province" % int(dawn.tithe_per_province)))
	var forge: Dictionary = AscensionRules.node_effects("crown_oath_forge").income_terrain
	for key in ["deep_mines", "node_crown_oath_forge"]:
		assert_true(RulesCodex.text(key).contains("every hills province you own earns %d more gold" % int(forge.hills)), key)
	var grove: Dictionary = AscensionRules.node_effects("beasts_oath_grove").income_terrain
	for key in ["bounty_of_the_wild", "node_beasts_oath_grove"]:
		assert_true(RulesCodex.text(key).contains("every forest province you own earns %d more gold" % int(grove.forest)), key)
	var charters: Dictionary = AscensionRules.node_effects("crown_charters").income_terrain
	assert_true(RulesCodex.text("node_crown_charters").contains("every plains province you own earns %d more gold" % int(charters.plains)))
	var raid := int(AscensionRules.node_effects("beasts_raiding").capture_gold)
	var times: String = {1: "equal to its base income", 2: "equal to twice its base income", 3: "equal to three times its base income"}[raid]
	assert_true(RulesCodex.text("node_beasts_raiding").contains(times), "Raiding Parties states %s" % times)
	# Blood Levy: its share and the worked example (Tuskers' price and arriving hit points).
	var levy := int(AscensionRules.node_effects("beasts_oath_blood").blood_levy)
	var word := AscensionRules._fraction_word(levy)
	for key in ["blood_levy", "node_beasts_oath_blood"]:
		assert_true(RulesCodex.text(key).contains("%s less" % word), "%s states %s off" % [key, word])
	var tusk_cost := _base("tuskers", "cost")
	var tusk_hp := _base("tuskers", "hp")
	var example := "Tuskers %d gold instead of %d" % [tusk_cost - floori(float(tusk_cost) / levy), tusk_cost]
	assert_true(RulesCodex.text("blood_levy").contains(example), "blood_levy: %s" % example)
	var arrive := "Tuskers %d of %d" % [tusk_hp - floori(float(tusk_hp) / levy), tusk_hp]
	assert_true(RulesCodex.text("blood_levy").contains(arrive), "blood_levy: %s" % arrive)
	# Every node's one-line card text names its numbers too.
	for fid in ["kingdom", "beasts"]:
		for nid in AscensionRules.node_ids(fid):
			var card := String(AscensionRules.node_data(nid).text)
			var nfx := AscensionRules.node_effects(nid)
			for type_id in nfx.get("unit", {}):
				for stat in nfx.unit[type_id]:
					var v := int(nfx.unit[type_id][stat])
					assert_true(card.contains("%d" % absi(v)), "%s's card states %d: %s" % [nid, absi(v), card])
			for terrain in nfx.get("income_terrain", {}):
				assert_true(card.contains("%d" % absi(int(nfx.income_terrain[terrain]))), "%s's card states its gold: %s" % [nid, card])
			if nfx.has("blood_levy"):
				assert_true(card.contains("%s less" % word), "%s's card states %s: %s" % [nid, word, card])


# --- fast band checks for the tuned numbers ----------------------------------------------------------

func test_every_side_wins_and_transforms_mid_game_in_a_short_fixed_seed_batch() -> void:
	# Every Crown side against every Clans side, both seat orders, seeds 1-2, builds rolled by the seed as an
	# AI seat rolls them: 16 games. The full check (P1, P2) has each side winning 40-60% of its games; in this
	# small batch every side must win at least one decisive game and lose at least one (P2's "no dominant
	# side" in miniature), transformations must land mid-game (P4) and the research forecasts must hold (P8).
	var games := []
	for cs in PathMatrix.sides_of("kingdom"):
		for ks in PathMatrix.sides_of("beasts"):
			for seats in [["kingdom", "beasts"], ["beasts", "kingdom"]]:
				var sides: Array = [cs, ks] if seats[0] == "kingdom" else [ks, cs]
				for sd in range(1, 3):
					var r := Simulator.play_game(sd, seats, ["ai", "ai"], 40, Callable(), {"paths": true, "branches": sides})
					assert_eq(r.errors.size() + r.violations.size(), 0, "seed %d %s: clean" % [sd, sides])
					assert_eq(int(r.research.turn_mismatches) + int(r.research.target_mismatches), 0, str(r.research.first))
					r["branches"] = sides
					games.append(r)
	var turns := []
	for r in games:
		for fid in r.paths:
			if int(r.paths[fid].transform_turn) > 0:
				turns.append(int(r.paths[fid].transform_turn))
	var median := float(Simulator.stats_of(turns).median)
	assert_true(median >= PathMatrix.P4_BAND[0] and median <= PathMatrix.P4_BAND[1], "transformations land on turn %s (median)" % median)
	for fid in ["kingdom", "beasts"]:
		for side in PathMatrix.sides_of(fid):
			var rec := PathMatrix.side_record(games, side)
			assert_true(rec.wins >= 1, "%s won %d of %d decisive games" % [side, rec.wins, rec.decisive])
			assert_true(rec.losses >= 1, "%s lost %d of %d decisive games" % [side, rec.losses, rec.decisive])


func test_dread_lands_does_not_stack_with_dread() -> void:
	# M4-6 (§10.3, §15 call 13): on the Blood Pact's own land with the Great Thornmane fighting there, the
	# invader loses the Thornmane's Dread and Dread Lands adds nothing; without him, Dread Lands applies.
	var PB := preload("res://tests/path_battle_fixtures.gd")
	var value := int(AscensionRules.node_effects("beasts_blood_pact").province_rule.value)
	for with_avatar in [true, false]:
		var s := GameState.with_paths(7, {"beasts": {"ruler": "thornmane_avatar", "mandates": []}}, [])
		s = PB.with_nodes(s, "beasts", ["beasts_raiding", "beasts_boar_hide", "beasts_oath_blood", "beasts_blood_pact"])
		var dread := RulerRules.dread_value(s, "beasts")
		assert_true(dread >= value, "the Thornmane keeping all its power has Dread %d" % dread)
		var keep: Array[Army] = []
		for a in s.armies:
			if a.ruler != null and (with_avatar and a.owner == "beasts"):
				a.location = "bloodfen"
				keep.append(a)
		s.armies = keep
		s.find_province("bloodfen").owner = "beasts"
		var crown := PB.army(s, "kingdom", "kingdom-1", "bloodfen", ["spearmen", "spearmen", "crossbowmen", "knights"])
		var clans := PB.army(s, "beasts", "beasts-2", "bloodfen", ["tuskers", "fangthrowers"])
		var armies := [crown, clans]
		if with_avatar:
			armies.append(keep[0])
		var r := PB.fight(s, armies, "bloodfen", "beasts", 3)
		var parts: Dictionary = {}
		for side in r.log.sides:
			if side.faction == "kingdom":
				parts = side.start_morale.parts
		if with_avatar:
			assert_eq(int(parts.get(AutoBattleResolver.DREAD, 0)), -dread, "the Thornmane's Dread")
			assert_eq(int(parts.get(AutoBattleResolver.DREAD_LANDS, 0)), -maxi(0, value - dread), "Dread Lands adds nothing on top of it")
			assert_true(String(r.result.report.lines[1]).contains("not on top of"), String(r.result.report.lines[1]))
		else:
			assert_eq(int(parts.get(AutoBattleResolver.DREAD_LANDS, 0)), -value, "Dread Lands without the Thornmane")
	assert_true(RulesCodex.text("dread_lands").contains("doesn't add to the Great Thornmane's Dread"))
