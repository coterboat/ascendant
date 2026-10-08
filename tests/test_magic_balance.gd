extends "res://tests/test_case.gd"
## M5-11 (#122): the autoplay balance check for magic and fog (design/M5_MAGIC_FOG.md §13.2). The matrix plan and how its
## bands G1-G14 are judged (tools/autoplay/magic_matrix.gd), the simulator's magic log, ritual forecast check, hit point ledger
## and fog snapshot probe (magic_log.gd, fog_probe.gd), the Tithe pairs' builds, the scripted bleeding policy, and the
## `--magic`, `--fog` and `--tithe` flags of autoplay.gd. The full check is
## `autoplay.gd -- --matrix --magic --independents --jobs 4`; its report is in the PR.
## Numbers in the expected values come from the data and the targets, never typed here.

const Simulator := preload("res://tools/autoplay/simulator.gd")
const Matrix := preload("res://tools/autoplay/matrix.gd")
const PathMatrix := preload("res://tools/autoplay/path_matrix.gd")
const MagicMatrix := preload("res://tools/autoplay/magic_matrix.gd")
const MagicLog := preload("res://tools/autoplay/magic_log.gd")
const FogProbe := preload("res://tools/autoplay/fog_probe.gd")
const Policies := preload("res://tools/autoplay/policies.gd")

const CROWN := "kingdom"
const CLANS := "beasts"
const SEATS := ["kingdom", "beasts"]


# --- the matrix plan ----------------------------------------------------------------------------------

func test_the_magic_matrix_plans_every_cell_of_section_13_2() -> void:
	var fixture := PathMatrix.load_fixture()
	var cells := MagicMatrix.plan(1.0, 1, fixture)
	var ids := {}
	for c in cells:
		assert_false(ids.has(c.id), "cell ids are unique: %s" % c.id)
		ids[c.id] = true
	var crown := RulerRules.presets_for(CROWN).size()
	var clans := RulerRules.presets_for(CLANS).size()
	var by_band := {}
	var games := {}
	for c in cells:
		by_band[c.band] = int(by_band.get(c.band, 0)) + 1
		games[c.band] = int(games.get(c.band, 0)) + int(c.games)
	assert_eq(by_band.G, 4 * crown * clans * 2, "4 side pairings x every preset pairing x both seat orders")
	assert_eq(games.G, 1800, "§13.2: the main matrix is 1,800 games")
	assert_eq(games.GF, 720, "§13.2: the fog matrix is 720 games")
	assert_eq(games.GT, 720, "§13.2: the Tithe pairs are 720 games (360 with Tithe, 360 with the null mandate)")
	assert_eq(games.P, 1800, "§13.2: the control is the 1,800-game path matrix")
	assert_eq(by_band.GB, crown * clans * 2, "the scripted bleeding build plays the pairs' cells once")
	assert_eq(games.GB, crown * clans * 2 * MagicMatrix.BLEED_GAMES)
	for c in cells:
		match c.band:
			"G", "GF":
				assert_true(bool(c.magic) and bool(c.paths), "magic and paths on")
				assert_eq(bool(c.fog), c.band == "GF", "fog only in the fog matrix")
				for seat in 2:
					assert_eq(PathMatrix.faction_of_side(str(c.branches[seat])), c.seats[seat], "seat %d plays one of its own sides" % (seat + 1))
					assert_eq(RulerRules.preset_data(str(c.builds[seat])).faction, c.seats[seat], "seat %d plays one of its own presets" % (seat + 1))
			"GT", "GB":
				assert_false(bool(c.fog))
				assert_eq(c.branches, ["", ""], "the Tithe pairs roll their sides of the fork by seed, the same in both runs")
				assert_true(["tithe", "null", "bleed"].has(str(c.tithe)))
				assert_eq(c.policies[c.seats.find(CLANS)], MagicMatrix.BLEED_POLICY if c.tithe == "bleed" else MagicMatrix.POLICY)
			"P7":
				assert_false(bool(c.get("magic", false)), "band G12's M2 games play without magic")
	# Every fog cell has a main cell with the same tail (so its control is the first games of that cell).
	for c in cells:
		if c.band == "GF":
			assert_true(ids.has("G:" + str(c.id).trim_prefix("GF:")), "%s has a no-fog control cell" % c.id)
			assert_true(int(c.games) <= MagicMatrix.CELL_GAMES, "its games are the first of that cell's")
	# A Tithe pair is the same cell twice, once with each mandate.
	for c in cells:
		if c.band == "GT" and c.tithe == "tithe":
			assert_true(ids.has("GT:null:" + str(c.id).trim_prefix("GT:tithe:")), "%s has a null-mandate twin" % c.id)
	# --scale shrinks the magic cells, never P7; work items cover every game once.
	var small := MagicMatrix.plan(0.2, 1, fixture)
	assert_eq(small.filter(func(c): return c.band == "G")[0].games, 5)
	assert_eq(small.filter(func(c): return c.band == "GF")[0].games, 2)
	assert_eq(small.filter(func(c): return c.band == "P7")[0].games, PathMatrix.M2_PER_CELL)
	var total := 0
	var planned := 0
	for it in Matrix.work_items(cells):
		total += int(it.count)
	for c in cells:
		planned += int(c.games)
	assert_eq(total, planned, "every planned game is in exactly one work item")
	assert_eq(MagicMatrix.find_cell(cells, cells[3].id).id, cells[3].id)


func test_a_pairing_with_too_few_decisive_games_is_doubled() -> void:
	var games := []
	for i in 130:
		games.append({"band": "G", "pairing": "a|b", "finished": true, "draw": false, "winner": "kingdom"})
	for i in 100:
		games.append({"band": "G", "pairing": "c|d", "finished": i % 2 == 0, "draw": false, "winner": "beasts"})
	var short := MagicMatrix.short_pairings(games, 1.0)
	assert_false(short.has("a|b"), "130 decisive games are enough")
	assert_true(short.has("c|d"), "50 decisive games are not")
	assert_true(MagicMatrix.short_pairings(games, 0.4).is_empty(), "the bar scales")


# --- judging the bands --------------------------------------------------------------------------------

## A main-matrix game in the shape play_item gives, with the numbers the bands read.
func _game(crown_side: String, clans_side: String, crown_seat: bool, winner: String, turns: int, i: int = 0, transform := 9) -> Dictionary:
	var seats := SEATS if crown_seat else ["beasts", "kingdom"]
	var sides := [crown_side, clans_side] if crown_seat else [clans_side, crown_side]
	var paths := {}
	for fid in SEATS:
		paths[fid] = {"branch": crown_side if fid == CROWN else clans_side, "oath_turn": transform - 3, "transform_turn": transform, "nodes": [],
			"ordinary_before_oath": 2}
	var crown_preset: String = ["warrior_king", "iron_crown", "regents_court"][i % 3]
	var arcana := {}
	for fid in SEATS:
		arcana[fid] = {}
		for school in MagicData.FACTION_SCHOOLS[fid]:
			arcana[fid][str(MagicData.SCHOOLS[school].nodes[0])] = 4
			arcana[fid][str(MagicData.SCHOOLS[school].nodes[1])] = 10
	var casts := []
	for fid in SEATS:
		for school in MagicData.FACTION_SCHOOLS[fid]:
			var ritual := str(MagicData.SCHOOLS[school].nodes[1])
			casts.append({"faction": fid, "ritual": ritual, "turn": 8, "outcome": "cast", "pay": "gold", "gold": 10, "hp": 0, "price": 10,
				"caster": "mage", "kind": "x", "target": "", "army": "a", "size": 0, "read": "", "blocked": ""})
	var spells := {CROWN: {"sunlance": 3, "shield_of_law": 2}, CLANS: {"briar_snare": 3, "bloodbolt": 2}}
	var battle := {"factors": [{"id": "numbers", "faction": "kingdom", "favors_winner": true}, {"id": "spell_sunlance", "faction": "kingdom", "favors_winner": true}],
		"winner": winner, "magic": {"top": "numbers", "spells": {}, "casters": {CROWN: 1, CLANS: 1}, "moon": {}, "worth": {CROWN: 3.0, CLANS: 1.0}}}
	return {"band": "G", "cell": "G:test", "pairing": "%s|%s" % [crown_side, clans_side], "seed": i, "seats": seats, "branches": sides,
		"builds": {"kingdom": crown_preset, "beasts": "clan_moot"}, "finished": winner != "", "draw": false, "winner": winner, "turns": turns,
		"paths": paths, "battles": [battle], "violations": [], "errors": [], "script_errors": [], "replay": "identical" if i == 0 else "",
		"ruler_log": {"deaths": [], "arrivals": [], "sacrifices": [{"faction": "beasts", "mandate": "blood_frenzy", "turn": 9}] if i % 4 == 0 else [], "mandates": {}},
		"recruits": {CROWN: {"spearmen": 80, "adepts": 10}, CLANS: {"tuskers": 80, "shamans": 10}}, "policy_stats": [{}, {}], "tithe": "",
		"magic": {"arcana": arcana, "casts": casts, "healed": {"dawn_blessing": 100}, "drained": {"bloodrot": 100}, "moon": 20, "spells": spells, "sold": {},
			"forecast": {"checks": 4, "mismatches": 0, "turned_aside": 0, "unseen": 0, "first": ""}, "hp": {"checks": 50, "mismatches": 0, "first": ""}},
		"fog": {}}


func _band(j: Dictionary, name: String) -> Dictionary:
	for b in j.bands:
		if b.band == name:
			return b
	return {}


## The main games of every side pairing, split evenly in both seat orders over 16- and 17-turn games.
func _main_games() -> Array:
	var games := []
	var n := 0
	for cs in PathMatrix.sides_of(CROWN):
		for ks in PathMatrix.sides_of(CLANS):
			for i in 12:
				games.append(_game(cs, ks, i % 2 == 0, "kingdom" if i < 6 else "beasts", 16 + i % 2, n))
				n += 1
	return games


func _m2_games(fixture: Dictionary) -> Array:
	var out := []
	for key in fixture.digests:
		var parts := str(key).split("|")
		out.append({"band": "P7", "cell": "P7:" + parts[0], "pairing": "P7", "seed": int(parts[1]), "record_md5": fixture.digests[key],
			"finished": true, "draw": false, "winner": "kingdom", "turns": 20, "violations": [], "errors": [], "script_errors": [], "replay": "",
			"ruler_log": {"deaths": [], "arrivals": [], "sacrifices": [], "mandates": {}}, "research": {}})
	return out


func test_the_bands_are_judged_from_the_games() -> void:
	var fixture := PathMatrix.load_fixture()
	var games := _main_games()
	var j := MagicMatrix.judge(games + _m2_games(fixture), 0, fixture, {"ok": true, "text": "identical"})
	for name in ["G1", "G2", "G4", "G5", "G6", "G8", "G10", "G12", "G13"]:
		assert_eq(_band(j, name).status, "pass", "%s: %s %s" % [name, _band(j, name).result, _band(j, name).detail])
	for name in ["G3", "G14"]:
		assert_eq(_band(j, name).status, "report", "%s is report only" % name)
	for name in ["G9", "G11"]:
		assert_eq(_band(j, name).status, "none", "%s was not played" % name)
	assert_true(j.ok, "G12 and G13 hold")
	assert_eq(j.bands.map(func(b): return b.band), MagicMatrix.BANDS, "every band is in the table, in order")
	# G7: the toy games cast on turn 8, so a ritual comes by turn 10 in all of them; one that comes later misses.
	assert_eq(_band(j, "G7").status, "pass", "%s %s" % [_band(j, "G7").result, _band(j, "G7").detail])
	var late := games.duplicate(true)
	for g in late:
		for c in g.magic.casts:
			c.turn = 14
	assert_eq(_band(MagicMatrix.judge(late + _m2_games(fixture), 0, fixture, {"ok": true}), "G7").status, "miss", "no ritual by turn 10")
	# G1: a school that is never researched misses.
	var dull := games.duplicate(true)
	for g in dull:
		g.magic.arcana[CROWN].erase(str(MagicData.SCHOOLS.law.nodes[0]))
	assert_eq(_band(MagicMatrix.judge(dull + _m2_games(fixture), 0, fixture, {"ok": true}), "G1").status, "miss")
	# G2: one spell as the top "why" in a third of the battles, or one ritual as most of a faction's rituals, misses.
	var dominant := games.duplicate(true)
	for i in dominant.size():
		if i % 3 == 0:
			dominant[i].battles[0].magic.top = "spell_sunlance"
	var j2 := MagicMatrix.judge(dominant + _m2_games(fixture), 0, fixture, {"ok": true})
	assert_eq(_band(j2, "G2").status, "miss", _band(j2, "G2").result)
	assert_true(str(_band(j2, "G2").result).contains(MagicData.SPELLS.sunlance.name), "G2 names the spell")
	var one_ritual := games.duplicate(true)
	for g in one_ritual:
		for c in g.magic.casts:
			c.ritual = str(MagicData.SCHOOLS.sun.nodes[1]) if c.faction == CROWN else c.ritual
		g.magic.casts.append({"faction": CROWN, "ritual": MagicData.SCHOOLS.sun.nodes[1], "turn": 9, "outcome": "cast", "pay": "gold", "gold": 12, "hp": 0,
			"price": 12, "caster": "mage", "kind": "x", "target": "", "army": "a", "size": 0, "read": "", "blocked": ""})
	assert_eq(_band(MagicMatrix.judge(one_ritual + _m2_games(fixture), 0, fixture, {"ok": true}), "G2").status, "miss", "one ritual is all the Crown casts")
	# G5: long games, or too many at the cap, miss.
	var long := games.map(func(g):
		var c: Dictionary = g.duplicate(true)
		c.turns = 30
		return c)
	assert_eq(_band(MagicMatrix.judge(long + _m2_games(fixture), 0, fixture, {"ok": true}), "G5").status, "miss")
	var capped := games.duplicate(true)
	for i in capped.size():
		if i % 4 == 0:
			capped[i].finished = false
			capped[i].winner = ""
	assert_eq(_band(MagicMatrix.judge(capped + _m2_games(fixture), 0, fixture, {"ok": true}), "G5").status, "miss", "a quarter at the cap")
	# G6: late transformations miss.
	var slow := games.map(func(g):
		var c: Dictionary = g.duplicate(true)
		for fid in c.paths:
			c.paths[fid].transform_turn = 14
		return c)
	assert_eq(_band(MagicMatrix.judge(slow + _m2_games(fixture), 0, fixture, {"ok": true}), "G6").status, "miss")
	# G8: no mages bought, or too many, miss.
	var none := games.duplicate(true)
	for g in none:
		g.recruits[CROWN].adepts = 0
	assert_eq(_band(MagicMatrix.judge(none + _m2_games(fixture), 0, fixture, {"ok": true}), "G8").status, "miss")
	# G4: every Celestial Host game won and every Living Iron game lost misses the fork.
	var tilt := games.duplicate(true)
	for g in tilt:
		g.winner = "kingdom" if g.paths.kingdom.branch == "celestial_host" else "beasts"
	assert_eq(_band(MagicMatrix.judge(tilt + _m2_games(fixture), 0, fixture, {"ok": true}), "G4").status, "miss")
	# G10: the Regent winning most of its games misses.
	var regent := games.duplicate(true)
	for g in regent:
		if g.builds.kingdom == "regents_court":
			g.winner = "kingdom"
	assert_eq(_band(MagicMatrix.judge(regent + _m2_games(fixture), 0, fixture, {"ok": true}), "G10").status, "miss")


func test_g12_follows_the_records_the_digests_and_f_against_the_control() -> void:
	var fixture := PathMatrix.load_fixture()
	var games := _main_games()
	var m2 := _m2_games(fixture)
	# The fixture records must replay: a record that does not misses G12 and the exit code follows it.
	var broken := MagicMatrix.judge(games + m2, 0, fixture, {"ok": false, "text": "m2 turn 3 no longer replays identically."})
	assert_eq(_band(broken, "G12").status, "miss")
	assert_false(broken.ok, "the exit code follows G12")
	assert_eq(_band(MagicMatrix.judge(games + m2, 0, fixture, {}), "G12").status, "miss", "records not checked is not a pass")
	# An M2 game whose record differs from main misses G12.
	var changed := _m2_games(fixture)
	changed[0].record_md5 = "0"
	assert_eq(_band(MagicMatrix.judge(games + changed, 0, fixture, {"ok": true}), "G12").status, "miss")
	assert_eq(_band(MagicMatrix.judge(games + m2, 0, {}, {"ok": true}), "G12").status, "miss", "no fixture, no pass")
	# Band F: sacrifices in every magic game miss it, unless the control (magic off) is as far out.
	var sacrificing := games.duplicate(true)
	for g in sacrificing:
		g.ruler_log.sacrifices = [{"faction": "beasts", "mandate": "blood_frenzy", "turn": 9}]
	assert_eq(_band(MagicMatrix.judge(sacrificing + m2, 0, fixture, {"ok": true}), "G12").status, "miss", "F at 100% with no control")
	var control := []
	for g in sacrificing:
		var c: Dictionary = g.duplicate(true)
		c.band = "P"
		control.append(c)
	var held := MagicMatrix.judge(sacrificing + control + m2, 0, fixture, {"ok": true})
	assert_eq(_band(held, "G12").status, "pass", "F is as far out with magic off: magic did not move it")
	assert_true(str(_band(held, "G12").detail).contains("literally a miss"), str(_band(held, "G12").detail))
	var worse := control.duplicate(true)
	for i in worse.size():
		if i % 2 == 0:
			worse[i].ruler_log.sacrifices = []
	assert_eq(_band(MagicMatrix.judge(sacrificing + worse + m2, 0, fixture, {"ok": true}), "G12").status, "miss", "magic pushed F well past the control")


func test_g9_compares_the_clans_with_and_without_tithe() -> void:
	var games := []
	for mode in ["tithe", "null"]:
		for k in RulerRules.presets_for(CLANS):
			for i in 20:
				var win := i < 10
				games.append({"band": "GT", "tithe": mode, "cell": "GT:%s:x" % mode, "seed": i, "seats": SEATS, "builds": {"kingdom": "warrior_king", "beasts": str(k.id)},
					"finished": true, "draw": false, "winner": CLANS if win else CROWN, "turns": 20, "violations": [], "errors": [], "script_errors": [], "replay": "",
					"magic": {"casts": [{"faction": CLANS, "ritual": "bloodrot", "pay": "blood" if mode == "tithe" else "gold", "hp": 15 if mode == "tithe" else 0, "outcome": "cast"}]}})
	var even := MagicMatrix.judge(games, 0, {}, {})
	assert_eq(_band(even, "G9").status, "pass", _band(even, "G9").result)
	var tilted := games.duplicate(true)
	for g in tilted:
		if g.tithe == "tithe":
			g.winner = CLANS
	var j := MagicMatrix.judge(tilted, 0, {}, {})
	assert_eq(_band(j, "G9").status, "miss", "Tithe winning every game is not within 5 points: " + str(_band(j, "G9").result))
	assert_true(j.tables.tithe.with_stats.blood > 0 and j.tables.tithe.without_stats.blood == 0, "the blood is counted for the Tithe run only")
	# The scripted build is reported beside them.
	var bleed := games.filter(func(g): return g.tithe == "tithe").map(func(g):
		var c: Dictionary = g.duplicate(true)
		c.band = "GB"
		c.tithe = "bleed"
		return c)
	var with_bleed := MagicMatrix.judge(games + bleed, 0, {}, {})
	assert_true(str(_band(with_bleed, "G9").result).contains("scripted bleeding build"), _band(with_bleed, "G9").result)


func test_g11_compares_the_fog_games_with_the_first_games_of_the_same_cells() -> void:
	var main := []
	var fog := []
	for i in 10:
		var g := _game("celestial_host", "thorn_wild", true, "kingdom" if i < 5 else "beasts", 16, i)
		g.seed = 100 + i
		g.cell = "G:cell"
		main.append(g)
		var f: Dictionary = g.duplicate(true)
		f.band = "GF"
		f.cell = "GF:cell"
		f.magic.casts.append({"faction": CROWN, "ritual": "far_sight", "turn": 6, "outcome": "cast", "pay": "gold", "gold": 6, "hp": 0, "price": 6, "caster": "ruler",
			"kind": "sight", "target": "x", "army": "a", "size": 0, "read": "", "blocked": ""})
		f.fog = {"probes": 1, "views": 2, "view_mismatches": 0, "plans": 2, "plan_mismatches": 0, "illegal": 0, "skipped": 0, "first": ""}
		f.policy_stats = [{"scouts": 3}, {}]
		fog.append(f)
	var j := MagicMatrix.judge(main + fog, 0, {}, {})
	assert_eq(_band(j, "G11").status, "pass", "%s %s" % [_band(j, "G11").result, _band(j, "G11").detail])
	assert_eq(j.tables.fog.compared, 10, "every fog game finds its control by cell and seed")
	assert_eq(j.tables.fog.changed, 0, "the same winners")
	# Longer fog games miss the length bar; a Far Sight that never works misses the sight bar.
	var slow := fog.duplicate(true)
	for g in slow:
		g.turns = 16 + int(MagicMatrix.G11_LENGTH) + 2
	assert_eq(_band(MagicMatrix.judge(main + slow, 0, {}, {}), "G11").status, "miss")
	var blind := fog.duplicate(true)
	for g in blind:
		g.magic.casts = g.magic.casts.filter(func(c): return c.ritual != "far_sight")
	assert_eq(_band(MagicMatrix.judge(main + blind, 0, {}, {}), "G11").status, "miss")
	# A fog game whose control is a different winner counts as a change.
	var flipped := fog.duplicate(true)
	flipped[0].winner = "beasts" if flipped[0].winner == "kingdom" else "kingdom"
	assert_eq(MagicMatrix.judge(main + flipped, 0, {}, {}).tables.fog.changed, 1)


func test_g13_catches_each_kind_of_failure() -> void:
	var fixture := PathMatrix.load_fixture()
	var games := _main_games()
	var m2 := _m2_games(fixture)
	var ok := {"ok": true}
	assert_eq(_band(MagicMatrix.judge(games + m2, 0, fixture, ok), "G13").status, "pass")
	var cases := {
		"a violation": func(g): g.violations.append({"seed": 1, "turn": 3, "check": "hp_ledger", "detail": "x"}),
		"a session error": func(g): g.errors.append({"seed": 1, "turn": 3, "detail": "x"}),
		"a script error": func(g): g.script_errors.append({"seed": 1, "turn": 3, "detail": "x"}),
		"a replay that differs": func(g): g.replay = "differs: the replayed final state is not the one the game reached",
		"a ritual forecast mismatch": func(g): g.magic.forecast.mismatches = 1,
		"a snapshot view mismatch": func(g): g.fog = {"views": 2, "view_mismatches": 1, "plans": 0, "plan_mismatches": 0, "illegal": 0, "skipped": 0, "probes": 1, "first": "view"},
		"a snapshot plan mismatch": func(g): g.fog = {"views": 2, "view_mismatches": 0, "plans": 2, "plan_mismatches": 1, "illegal": 0, "skipped": 0, "probes": 1, "first": "plan"},
		"an illegal order": func(g): g.fog = {"views": 2, "view_mismatches": 0, "plans": 2, "plan_mismatches": 0, "illegal": 1, "skipped": 0, "probes": 1, "first": "illegal"},
	}
	for name in cases:
		var bad := games.duplicate(true)
		cases[name].call(bad[0])
		var j := MagicMatrix.judge(bad + m2, 0, fixture, ok)
		assert_eq(_band(j, "G13").status, "miss", "%s misses G13" % name)
		assert_false(j.ok, "and the exit code follows it")
	# A forecast set aside (turned aside, or out of clear sight) is not a mismatch.
	var aside := games.duplicate(true)
	aside[0].magic.forecast.turned_aside = 3
	aside[0].magic.forecast.unseen = 2
	assert_eq(_band(MagicMatrix.judge(aside + m2, 0, fixture, ok), "G13").status, "pass")
	assert_eq(_band(MagicMatrix.judge(games + m2, 1, fixture, ok), "G13").status, "miss", "a script error outside the games")
	# Nothing replayed is not a pass.
	var unreplayed := games.duplicate(true)
	for g in unreplayed:
		g.replay = ""
	assert_eq(_band(MagicMatrix.judge(unreplayed + m2, 0, fixture, ok), "G13").status, "miss", "no replays, no pass")


func test_g14_measures_hit_points_moved_per_gold() -> void:
	var games := _main_games()
	var j := MagicMatrix.judge(games, 0, {}, {})
	var rows := {}
	for v in j.tables.value:
		rows[v.ritual] = v
	var blessing: Dictionary = rows.dawn_blessing
	assert_eq(int(blessing.moved), 100 * games.size(), "the healing is summed")
	assert_true(blessing.gold > 0.0)
	assert_eq(snappedf(blessing.value, 0.001), snappedf(float(blessing.moved) / blessing.gold, 0.001))
	assert_eq(int(rows.blood_moon.moved), 20 * games.size(), "the Blood Moon's healing back is summed from the battles")


# --- the pieces of the log -------------------------------------------------------------------------

func test_a_factor_names_its_spell() -> void:
	assert_eq(MagicLog.spell_of("spell_sunlance"), "sunlance")
	assert_eq(MagicLog.spell_of("morale_spell_dawn_blessing"), "dawn_blessing")
	assert_eq(MagicLog.spell_of("spell_blood_moon"), "blood_moon")
	assert_eq(MagicLog.spell_of("numbers"), "")
	assert_eq(MagicLog.spell_of("mandate_blood_frenzy"), "")
	var report := {"sides": [{"faction": CROWN, "spells_cast": {"sunlance": 3}, "casters": [{"id": "adepts", "count": 2}]},
		{"faction": CLANS, "spells_cast": {}, "casters": [], "moon_healed": 5}],
		"factors": [{"id": "spell_sunlance"}, {"id": "numbers"}],
		"all_factors": [{"id": "spell_sunlance", "faction": CROWN, "impact": 7.5}, {"id": "numbers", "faction": CLANS, "impact": 9.0},
			{"id": "spell_blood_moon", "faction": CLANS, "impact": 2.0}]}
	var x := MagicLog.battle_extras(report)
	assert_eq(x.top, "spell_sunlance")
	assert_eq(x.spells[CROWN], ["sunlance"])
	assert_eq(x.casters[CROWN], 2)
	assert_eq(x.moon[CLANS], 5)
	assert_eq(x.worth[CROWN], 7.5)
	assert_eq(x.worth[CLANS], 2.0, "only spells and blessings count as spell worth")


func test_the_log_records_casts_healing_and_battle_spells() -> void:
	var log := MagicLog.new_log()
	MagicLog.record_turn(log, 7, [
		{"type": "ritual_cast", "factions": [CLANS], "numbers": {"ritual": "call_the_pack", "pay": "blood", "gold": 0, "hp": 15, "price": 15, "caster": "mage", "kind": "summon",
			"target": "fangridge", "army": "beasts-1", "summon": {"count": 3}, "read": "", "blocked": ""}},
		{"type": "ritual_turned_aside", "factions": [CROWN, CLANS], "numbers": {"ritual": "dawn_blessing", "pay": "gold", "gold": 6, "price": 12, "army": "kingdom-1"}},
		{"type": "blessing_healed", "factions": [CROWN], "numbers": {"ritual": "dawn_blessing", "total": 12}},
		{"type": "curse_bit", "factions": [CROWN, CLANS], "numbers": {"ritual": "bloodrot", "total": 9}},
		{"type": "research_sold", "factions": [CROWN], "numbers": {"gold": 4}},
		{"type": "battle", "factions": [CROWN, CLANS], "numbers": {"report": {"sides": [{"faction": CROWN, "spells_cast": {"sunlance": 4}},
			{"faction": CLANS, "spells_cast": {"bloodbolt": 2}, "moon_healed": 8}]}}}])
	assert_eq(log.casts.size(), 2)
	assert_eq([log.casts[0].outcome, log.casts[0].pay, log.casts[0].hp, log.casts[0].size], ["cast", "blood", 15, 3])
	assert_eq(log.casts[1].outcome, "turned_aside")
	assert_eq(log.healed, {"dawn_blessing": 12})
	assert_eq(log.drained, {"bloodrot": 9})
	assert_eq(log.sold, {CROWN: 4})
	assert_eq(log.spells, {CROWN: {"sunlance": 4}, CLANS: {"bloodbolt": 2}})
	assert_eq(log.moon, 8)


func test_the_ritual_forecast_check_compares_numbers_and_sets_aside_what_it_cannot_judge() -> void:
	var numbers := {"ritual": "bloodrot", "gold": 15, "target": "x", "bonus": 1}
	var pending := {"faction": CLANS, "army": "beasts-1", "ritual": "bloodrot", "ok": true, "reason": "", "numbers": numbers.duplicate(), "clear": true}
	var event := {"type": "ritual_cast", "factions": [CLANS], "phase": "rituals", "numbers": numbers.duplicate(true)}
	event.numbers["army"] = "beasts-1"
	pending.numbers["army"] = "beasts-1"
	var log := MagicLog.new_log()
	MagicLog.check_forecasts(log, [pending], [event], 5)
	assert_eq([log.forecast.checks, log.forecast.mismatches], [1, 0], "a true forecast passes")
	var wrong := pending.duplicate(true)
	wrong.numbers.gold = 16
	MagicLog.check_forecasts(log, [wrong], [event], 6)
	assert_eq([log.forecast.checks, log.forecast.mismatches], [2, 1], "a wrong number is a mismatch")
	assert_true(str(log.forecast.first).contains("gold") and str(log.forecast.first).contains("turn 6"), str(log.forecast.first))
	var aside := {"type": "ritual_turned_aside", "factions": [CLANS, CROWN], "phase": "rituals", "numbers": {"ritual": "bloodrot", "army": "beasts-1"}}
	MagicLog.check_forecasts(log, [wrong], [aside], 7)
	assert_eq([log.forecast.checks, log.forecast.turned_aside], [2, 1], "a ritual a ward turned aside is set aside")
	var unseen := pending.duplicate(true)
	unseen.clear = false
	MagicLog.check_forecasts(log, [unseen], [event], 8)
	assert_eq([log.forecast.checks, log.forecast.unseen], [2, 1], "a target out of clear sight is set aside")
	MagicLog.check_forecasts(log, [pending], [], 9)
	assert_eq(log.forecast.mismatches, 2, "a promised ritual that is not cast is a mismatch")
	var refused := pending.duplicate(true)
	refused.ok = false
	refused.reason = "short of gold"
	MagicLog.check_forecasts(log, [refused], [event], 10)
	assert_eq(log.forecast.mismatches, 3, "an order the session took and the forecast refused is a mismatch")


func test_a_ward_that_ends_a_rival_curse_names_it_by_a_view_id_under_fog() -> void:
	# §2.7: a rival's enchantment is "seen-<ritual>-<province>" in a view and "beasts-e3" in the truth. The forecast made from
	# the view and the result agree when they end as many and each is the same or a view id.
	var forecast := {"ritual": "sanctum_ward", "army": "kingdom-1", "ends": ["seen-bloodrot-westwatch"]}
	var pending := {"faction": CROWN, "army": "kingdom-1", "ritual": "sanctum_ward", "ok": true, "reason": "", "numbers": forecast, "clear": true}
	var event := {"type": "ritual_cast", "factions": [CROWN], "phase": "rituals", "numbers": {"ritual": "sanctum_ward", "army": "kingdom-1", "ends": ["beasts-e3"]}}
	var log := MagicLog.new_log()
	MagicLog.check_forecasts(log, [pending], [event], 9)
	assert_eq([log.forecast.checks, log.forecast.mismatches], [1, 0], str(log.forecast.first))
	event.numbers.ends = ["beasts-e3", "beasts-e4"]
	MagicLog.check_forecasts(log, [pending], [event], 10)
	assert_eq(log.forecast.mismatches, 1, "ending more than the forecast said is a mismatch")
	var own := {"ritual": "sanctum_ward", "army": "kingdom-1", "ends": ["beasts-e3"]}
	pending.numbers = own
	event.numbers.ends = ["beasts-e4"]
	MagicLog.check_forecasts(log, [pending], [event], 11)
	assert_eq(log.forecast.mismatches, 2, "a true id that is not the result's is a mismatch")


func _ledger_states() -> Array:
	var prev := GameState.with_magic(11, {}, [])
	var state := prev.deep_copy()
	return [prev, state]


func test_the_hit_point_ledger_explains_blessings_curses_and_blood_and_catches_the_rest() -> void:
	var pair := _ledger_states()
	var prev: GameState = pair[0]
	var state: GameState = pair[1]
	var army: Army = null
	for a in state.armies:
		if a.owner == CROWN and not a.units.is_empty():
			army = a
			break
	assert_true(army != null, "the Crown has an army with units")
	var hurt := prev  # the state the turn started from
	var before_hp := hurt.find_army(army.id).units[0].current_hp
	# A blessing that healed the army explains the rise; the same rise with no event is a violation.
	var tally := {}
	state.find_army(army.id).units[0].current_hp = before_hp + 4
	var blessed := [{"type": "blessing_healed", "factions": [CROWN], "armies": [army.id], "numbers": {"army": army.id, "total": 4, "ritual": "dawn_blessing"}}]
	assert_eq(MagicLog.hp_ledger(hurt, state, blessed, tally), [], "a blessing explains the healing")
	var found := MagicLog.hp_ledger(hurt, state, [], tally)
	assert_eq(found.size(), 1, "the same healing with no event is not explained")
	assert_eq(found[0].check, "hp_ledger")
	assert_true(str(found[0].detail).contains(army.id), str(found[0].detail))
	assert_eq(int(tally.mismatches), 1)
	# Blood paid and a curse's bite explain losses.
	state.find_army(army.id).units[0].current_hp = before_hp - 3
	var paid := [{"type": "blood_paid", "factions": [CROWN], "armies": [army.id], "numbers": {"army": army.id, "hp": 3}}]
	assert_eq(MagicLog.hp_ledger(hurt, state, paid), [])
	var bitten := [{"type": "curse_bit", "factions": [CROWN, CLANS], "armies": [army.id], "numbers": {"taken": [{"army": army.id, "from": before_hp, "to": before_hp - 3}]}}]
	assert_eq(MagicLog.hp_ledger(hurt, state, bitten), [])
	# An army that fought, or whose faction changed its people's hit points, is left to the battle's and the node's own numbers.
	var fought := [{"type": "battle", "factions": [CROWN, CLANS], "armies": [army.id], "numbers": {}}]
	assert_eq(MagicLog.hp_ledger(hurt, state, fought), [])
	var sacrificed := [{"type": "sacrificed", "factions": [CROWN], "armies": [], "numbers": {}}]
	assert_eq(MagicLog.hp_ledger(hurt, state, sacrificed), [])
	var node := [{"type": "research_done", "factions": [CROWN], "armies": [], "numbers": {"hp_total": 9}}]
	assert_eq(MagicLog.hp_ledger(hurt, state, node), [])
	# Without magic the ledger checks nothing.
	assert_eq(MagicLog.hp_ledger(GameState.new(3), GameState.new(3), []), [])


func test_the_fog_probe_hides_what_a_rival_keeps_out_of_sight() -> void:
	var s := GameState.with_magic(5, {}, [])
	s.setup_fog([])
	var rival := s.find_faction(CLANS)
	rival.enchant_counter = 2
	var far := ""
	for p in s.provinces:
		if p.owner.is_empty() and not p.is_capital:
			far = p.id
	s.enchantments = [{"id": "beasts-e1", "ritual": "bloodrot", "faction": CLANS, "kind": "curse", "province": far, "armies": [], "cast_turn": 1,
		"until_turn": 9, "bonus": 0, "ending": false},
		{"id": "kingdom-e1", "ritual": "sanctum_ward", "faction": CROWN, "kind": "ward", "province": far, "armies": [], "cast_turn": 1, "until_turn": 9, "bonus": 0, "ending": false}]
	FogProbe.hide_magic(s, CROWN)
	assert_ne(rival.enchant_counter, 2, "the rival's counter is changed")
	assert_eq(s.enchantments.map(func(e): return str(e.id)).has("beasts-e1"), FogRules.sight(s, CROWN).get(far, FogRules.VEILED) != FogRules.VEILED,
		"a rival curse on a province out of sight is gone")
	assert_true(s.enchantments.map(func(e): return str(e.id)).has("kingdom-e1"), "the viewer's own ward stays")
	assert_true(FogProbe.due(FogProbe.PROBE_EVERY) and not FogProbe.due(1) and not FogProbe.due(0))


# --- the Tithe pairs' builds -----------------------------------------------------------------------------

func test_a_tithe_pair_buys_the_same_power_and_the_null_mandate_does_nothing() -> void:
	var cost := RulerRules.mandate_cost(MagicRules.TITHE_OF_BLOOD)
	assert_eq(RulerRules.mandate_cost(Simulator.NULL_MANDATE), cost, "the test-only mandate costs what Tithe of Blood costs")
	assert_true(RulerData.POWER_POOL >= cost)
	for k in RulerRules.presets_for(CLANS):
		var build := RulerRules.preset_build(str(k.id))
		var with := Simulator.tithe_build(build, "tithe")
		var without := Simulator.tithe_build(build, "null")
		assert_eq(with.mandates.back(), MagicRules.TITHE_OF_BLOOD)
		assert_eq(without.mandates.back(), Simulator.NULL_MANDATE)
		assert_eq(with.mandates.slice(0, -1), without.mandates.slice(0, -1), "%s: the other mandates are the same in both runs" % k.id)
		assert_eq(RulerRules.kept_after(with), RulerRules.kept_after(without), "%s: the same kept power" % k.id)
		assert_true(RulerRules.build_errors(CLANS, with).is_empty(), str(RulerRules.build_errors(CLANS, with)))
		assert_true(RulerRules.build_errors(CLANS, without).is_empty(), str(RulerRules.build_errors(CLANS, without)))
		assert_true(RulerRules.kept_after(with) >= Simulator.TITHE_MIN_KEPT, "%s: the ruler keeps power enough to stay in the field" % k.id)
		# What a preset keeps is one of its own mandates.
		for mid in with.mandates.slice(0, -1):
			assert_true(build.mandates.has(mid), "%s keeps only its own mandates (%s)" % [k.id, mid])
	# A build of its own (no preset) loses its last mandates until its ruler keeps enough.
	var own := Simulator.tithe_build({"preset": "", "ruler": "fang_chieftain", "mandates": ["iron_discipline", "blood_frenzy", "sworn_vassals"]}, "tithe")
	assert_eq(own.mandates, ["iron_discipline", MagicRules.TITHE_OF_BLOOD])
	assert_true(RulerRules.kept_after(own) >= Simulator.TITHE_MIN_KEPT)
	# Both builds start a game with magic, the null one without any Tithe.
	var game_with := GameState.with_magic(3, {CLANS: Simulator.tithe_build(RulerRules.preset_build("blood_of_the_fang"), "tithe")}, [])
	var game_without := GameState.with_magic(3, {CLANS: Simulator.tithe_build(RulerRules.preset_build("blood_of_the_fang"), "null")}, [])
	assert_true(game_with != null and game_without != null)
	assert_true(RulerRules.has_mandate(game_with, CLANS, MagicRules.TITHE_OF_BLOOD))
	assert_false(RulerRules.has_mandate(game_without, CLANS, MagicRules.TITHE_OF_BLOOD))
	assert_eq(RulerRules.kept_power(game_with, CLANS), RulerRules.kept_power(game_without, CLANS))
	# It does nothing and is on no list a person or the computer picks from.
	var md := RulerRules.mandate_data(Simulator.NULL_MANDATE)
	assert_true(bool(md.get("test_only", false)))
	for fid in SEATS:
		for state in [null, game_with]:
			assert_false(RulerRules.available_mandates(fid, state).has(Simulator.NULL_MANDATE), "not offered to %s" % fid)
	for m in MandateData.MANDATES + MandateData.PATH_MANDATES + MandateData.MAGIC_MANDATES:
		assert_ne(m.id, Simulator.NULL_MANDATE)
	for faction in BuildPresetData.PRESETS:
		for p in BuildPresetData.PRESETS[faction]:
			assert_false(p.mandates.has(Simulator.NULL_MANDATE) or p.ai_sacrifices.has(Simulator.NULL_MANDATE))
	assert_true(md.get("units", {}).is_empty() and not md.has("base_hit") and not md.has("recruit_divisor") and not md.has("wounded_attack"), "no effect")
	# Tithe is for a game with magic only.
	var plain := Simulator.play_game(2, SEATS, ["ai", "ai"], 3, Callable(), {"rulers": true, "paths": true, "tithe": "tithe"})
	assert_eq(plain.errors.size(), 1, "a Tithe pair without magic is refused")


# --- real games ----------------------------------------------------------------------------------------

func test_a_magic_game_is_clean_and_writes_its_log() -> void:
	var r := Simulator.play_game(2, SEATS, ["ai", "ai"], 24, Callable(), {"rulers": true, "builds": ["regents_court", "blood_of_the_fang"], "magic": true,
		"independents": true, "replay_check": true})
	assert_eq(r.errors, [], "no session error")
	assert_eq(r.violations, [], "no violation")
	assert_eq(r.script_errors, [], "no script error")
	assert_eq(r.replay, "identical", "the record replays to the same game")
	var m: Dictionary = r.magic
	assert_false(m.is_empty(), "a game with magic carries its log")
	assert_true(r.fog.is_empty(), "and no probe without fog")
	for fid in SEATS:
		assert_true(m.arcana.has(fid), "%s's research is logged" % fid)
		for nid in m.arcana[fid]:
			assert_true(MagicRules.is_arcana(str(nid)), "%s is a magic node" % nid)
			assert_true(int(m.arcana[fid][nid]) >= 1)
	assert_true(int(m.hp.checks) > 0, "the hit point ledger looked at armies")
	assert_eq(int(m.hp.mismatches), 0, str(m.hp.first))
	assert_eq(int(m.forecast.mismatches), 0, str(m.forecast.first))
	# The mages and the spells are in the numbers the bands read.
	var spells := 0
	for fid in m.spells:
		for sid in m.spells[fid]:
			assert_true(MagicRules.is_battle_spell(str(sid)), "%s is a battle spell" % sid)
			spells += int(m.spells[fid][sid])
	var battle_magic := 0
	for b in r.battles:
		if b.has("magic"):
			battle_magic += 1
			assert_true(b.magic.has("top") and b.magic.has("worth"))
	assert_eq(battle_magic, r.battles.size(), "every battle of a game with magic says who cast what")
	assert_true(spells > 0, "battle spells were cast")
	# Without magic the game carries nothing of it.
	var plain := Simulator.play_game(2, SEATS, ["ai", "ai"], 6, Callable(), {"rulers": true, "paths": true})
	assert_true(plain.magic.is_empty() and plain.fog.is_empty())
	assert_false(plain.battles.any(func(b): return b.has("magic")))


func test_the_policy_counts_rituals_and_scouts() -> void:
	# Over a few games with fog the computer casts and sends scouts: each shows in the policy counters the report prints, with
	# one 'cast_<ritual>' counter per ritual. (The counters themselves are the brain's; this checks the wiring.)
	var casts := 0
	var rituals := 0
	var scouts := 0
	var per_ritual := false
	for sd in [2, 3, 4, 5]:
		var r := Simulator.play_game(sd, SEATS, ["ai", "ai"], 40, Callable(), {"rulers": true, "builds": ["regents_court", "blood_of_the_fang"], "magic": true,
			"fog": true, "independents": true, "fog_probe": false})
		assert_eq(r.violations.size() + r.errors.size() + r.script_errors.size(), 0, "seed %d is clean" % sd)
		casts += r.magic.casts.size()
		for i in 2:
			var st: Dictionary = r.policy_stats[i]
			rituals += int(st.get("rituals", 0))
			scouts += int(st.get("scouts", 0))
			for key in st:
				if str(key).begins_with("cast_") and int(st[key]) > 0:
					per_ritual = true
	assert_true(casts > 0, "rituals were cast")
	assert_true(rituals > 0, "the counter 'rituals' is kept")
	assert_true(per_ritual, "and one 'cast_<ritual>' counter per ritual")
	assert_true(scouts > 0, "the counter 'scouts' is kept under fog")
	assert_true(Policies.NAMES.has("ai_bleed"))
	assert_eq(Policies.make("ai_bleed").policy_name, "ai_bleed")


func test_the_scripted_bleeding_build_pays_in_blood_what_the_computer_pays_in_gold() -> void:
	var s := GameState.with_magic(7, {CLANS: Simulator.tithe_build(RulerRules.preset_build("beast_god_unbound"), "tithe")}, [])
	s = AscensionRules.with_nodes(s, CLANS, ["bloodbolt", "bloodrot"])
	for f in s.factions:
		f.gold = 300
	var shamans := Army.new()
	shamans.id = "beasts-s"
	shamans.owner = CLANS
	shamans.location = "fangridge"
	var f := s.find_faction(CLANS)
	for t in ["shamans", "tuskers", "tuskers", "tuskers", "tuskers", "tuskers", "tuskers"]:
		shamans.units.append(Unit.new(TurnResolver.recruitable_type(f, t, s), CLANS))
	s.armies.append(shamans)
	var order := CastOrder.new("bloodrot", "beasts-s", "ebonpeak", CastOrder.GOLD)
	var policy = Policies.make("ai_bleed")
	var out: Array = policy._bleed(s, CLANS, [order])
	assert_eq(out.size(), 1)
	if MagicRules.check_cast(s, CLANS, CastOrder.new("bloodrot", "beasts-s", "ebonpeak", CastOrder.BLOOD), []).is_empty():
		assert_eq(out[0].pay, CastOrder.BLOOD, "paid in blood when the army can give it")
		assert_eq(int(policy.stats.get("bled", 0)), 1)
	else:
		assert_eq(out[0].pay, CastOrder.GOLD, "left alone when the target is out of reach")
	# Without Tithe of Blood it changes nothing.
	var plain := GameState.with_magic(7, {}, [])
	assert_eq(Policies.make("ai_bleed")._bleed(plain, CLANS, [order]), [order])


func test_a_fog_game_hands_the_seats_their_views_and_runs_the_snapshot_probe() -> void:
	# The first of a few seeds that reaches a probe turn (a game that ends before turn 10 has none).
	var r := {}
	for sd in [3, 4, 5, 6, 7]:
		r = Simulator.play_game(sd, SEATS, ["ai", "ai"], FogProbe.PROBE_EVERY + 2, Callable(), {"rulers": true, "builds": ["warrior_king", "clan_moot"],
			"magic": true, "fog": true, "independents": true})
		assert_eq(r.errors.size() + r.violations.size() + r.script_errors.size(), 0, "seed %d: a clean fog game" % sd)
		if int(r.turns) >= FogProbe.PROBE_EVERY:
			break
	assert_true(int(r.turns) >= FogProbe.PROBE_EVERY, "a game reached a probe turn (%d)" % int(r.turns))
	assert_eq(int(r.fog.probes), int(r.turns) / FogProbe.PROBE_EVERY, "the probe ran on every %dth turn" % FogProbe.PROBE_EVERY)
	assert_true(int(r.fog.views) + int(r.fog.skipped) >= 2, "both seats' views were compared")
	assert_eq(int(r.fog.view_mismatches), 0, str(r.fog.first))
	assert_eq(int(r.fog.plan_mismatches) + int(r.fog.illegal), 0, str(r.fog.first))
	if int(r.fog.skipped) == 0:
		assert_true(int(r.fog.plans) >= 2, "the computer planned from the real and from the changed view")
	# Without fog there is no probe, and the game carries no view log.
	var open := Simulator.play_game(3, SEATS, ["ai", "ai"], 12, Callable(), {"rulers": true, "builds": ["warrior_king", "clan_moot"], "magic": true, "independents": true})
	assert_eq(open.errors.size() + open.violations.size(), 0)
	assert_true(open.fog.is_empty())
	# fog_probe false leaves the probe out of a fog game.
	var quiet := Simulator.play_game(3, SEATS, ["ai", "ai"], FogProbe.PROBE_EVERY + 2, Callable(), {"rulers": true, "builds": ["warrior_king", "clan_moot"],
		"magic": true, "fog": true, "independents": true, "fog_probe": false})
	assert_eq(int(quiet.fog.probes), 0)


# --- the records part of G12 and the command line --------------------------------------------------------

func test_the_earlier_records_replay_and_the_computer_gives_their_orders() -> void:
	var r := MagicMatrix.records_check()
	assert_true(bool(r.ok), str(r.text))
	assert_true(str(r.text).contains("replayed identically"), str(r.text))
	assert_true(str(r.text).contains("gave the recorded orders"), str(r.text))


func test_the_command_line_plays_magic_fog_and_tithe() -> void:
	var cmd := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/autoplay/autoplay.gd", "--", "--games", "1", "--seed", "2",
		"--p1", "ai", "--p2", "ai", "--magic", "--fog", "--tithe", "--independents", "--turn-cap", "14", "--builds", "regents_court,blood_of_the_fang"]
	var output := []
	var code := OS.execute(OS.get_executable_path(), cmd, output, true)
	var text := "\n".join(output)
	assert_eq(code, 0, text.right(600))
	assert_true(text.contains("**Magic:**"), "the report has its magic lines: " + text.right(600))
	assert_true(text.contains("--magic --fog --tithe tithe"), "and says how it was run")
	assert_true(text.contains("Tithe of Blood"), "the Clans hold Tithe of Blood")
	var bad := []
	assert_eq(OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/autoplay/autoplay.gd", "--", "--tithe"], bad, true), 2,
		"--tithe without --magic is refused")
