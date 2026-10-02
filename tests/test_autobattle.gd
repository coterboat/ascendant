extends "res://tests/test_case.gd"
## Tests for issue #4: AutoBattleResolver rules, the battle report and its "why" summary, the odds
## estimate, and the TurnResolver integration.


# --- fixtures -------------------------------------------------------------------------------------

## A fresh state with the starting armies replaced by `specs`: [[id, owner, location, [unit ids]], ...].
func _state(specs: Array) -> GameState:
	var s := GameState.new(99)
	s.armies.clear()
	for spec in specs:
		var a := Army.new()
		a.id = spec[0]
		a.owner = spec[1]
		a.location = spec[2]
		var f := s.find_faction(a.owner)
		for type_id in spec[3]:
			var ut := TurnResolver.recruitable_type(f, type_id)
			if ut.is_commander:
				a.commander = Unit.new(ut, f.id)
			else:
				a.units.append(Unit.new(ut, f.id))
		s.armies.append(a)
	return s


## Fights `att_units` (beasts by default) attacking `def_units` (kingdom by default) in `province_id`.
func _battle(def_units: Array, att_units: Array, province_id: String, rng_seed: int, def_fid := "kingdom", att_fid := "beasts") -> Dictionary:
	var s := _state([["d-1", def_fid, province_id, def_units], ["a-1", att_fid, province_id, att_units]])
	return AutoBattleResolver.resolve(s.find_army("a-1"), s.find_army("d-1"), s.find_province(province_id), SeededRNG.new(rng_seed), s)


func _odds(def_units: Array, att_units: Array, province_id: String, perspective := "beasts") -> Dictionary:
	var s := _state([["d-1", "kingdom", province_id, def_units], ["a-1", "beasts", province_id, att_units]])
	var sides := [{"faction": "beasts", "armies": [s.find_army("a-1")]}, {"faction": "kingdom", "armies": [s.find_army("d-1")]}]
	var ctx := {"kind": "province", "defender": "kingdom", "province": s.find_province(province_id),
		"province_ids": [province_id], "state": s}
	return AutoBattleResolver.estimate(sides, ctx, perspective)


func _side(report: Dictionary, fid: String) -> Dictionary:
	for sr in report.sides:
		if sr.faction == fid:
			return sr
	return {}


func _custom_type(id: String, hp: int, attack: int, defense: int, morale: int, trait_id := "") -> UnitType:
	var ut := UnitType.new()
	ut.id = id
	ut.name = id.capitalize()
	ut.hp = hp
	ut.attack = attack
	ut.defense = defense
	ut.morale = morale
	ut.trait_id = trait_id
	return ut


func _custom_army(id: String, owner: String, types: Array) -> Army:
	var a := Army.new()
	a.id = id
	a.owner = owner
	a.location = "rivermarch"
	for ut in types:
		a.units.append(Unit.new(ut, owner))
	return a


const RAW_IDS := ["kingdom", "beasts", "d-1", "a-1", "kingdom-1", "beasts-2", "crownkeep", "thornvale", "greenglade",
	"rivermarch", "highcrag", "wildmoor", "spearmen", "crossbowmen", "knights", "knight_captain", "tuskers",
	"fangthrowers", "war_bear", "warchief"]


func _assert_no_raw_ids(text: String) -> void:
	for id in RAW_IDS:
		assert_false(text.contains(id), "raw id '%s' in player text: %s" % [id, text])


func _all_text(report: Dictionary) -> String:
	var parts: Array = report.lines.duplicate()
	parts.append(report.why)
	parts.append(report.summary)
	for f in report.factors:
		parts.append(f.text)
	return "\n".join(parts)


# --- rules ----------------------------------------------------------------------------------------

func test_hit_chance_and_damage_formulas() -> void:
	assert_eq(AutoBattleResolver.hit_chance(6, 6), 60)
	assert_eq(AutoBattleResolver.hit_chance(10, 7), 72)
	assert_eq(AutoBattleResolver.hit_chance(1, 20), 30, "never below 30%")
	assert_eq(AutoBattleResolver.hit_chance(30, 1), 90, "never above 90%")
	assert_eq(AutoBattleResolver.damage(10, 7), 4)
	assert_eq(AutoBattleResolver.damage(15, 5), 7)
	assert_eq(AutoBattleResolver.damage(1, 12), 1, "at least 1 damage")
	assert_eq(AutoBattleResolver.break_pct(10), 70)
	assert_eq(AutoBattleResolver.break_pct(0), 25)
	assert_eq(AutoBattleResolver.break_pct(40), 95)


func test_same_seed_same_report_and_seeds_can_differ() -> void:
	var units_d := ["spearmen", "spearmen", "crossbowmen", "knight_captain"]
	var units_a := ["tuskers", "tuskers", "fangthrowers"]
	var a := _battle(units_d, units_a, "thornvale", 7)
	var b := _battle(units_d, units_a, "thornvale", 7)
	assert_eq(var_to_str(a.report), var_to_str(b.report), "same seed, same report")
	assert_eq(a.result.winner, b.result.winner)
	var differs := false
	for i in range(1, 20):
		if var_to_str(_battle(units_d, units_a, "thornvale", 7 + i).report) != var_to_str(a.report):
			differs = true
	assert_true(differs, "other seeds give other battles")


func test_resolve_does_not_change_the_armies() -> void:
	var s := _state([["d-1", "kingdom", "thornvale", ["spearmen", "spearmen"]], ["a-1", "beasts", "thornvale", ["war_bear"]]])
	var before := var_to_str(s.to_dict())
	AutoBattleResolver.resolve(s.find_army("a-1"), s.find_army("d-1"), s.find_province("thornvale"), SeededRNG.new(3), s)
	assert_eq(var_to_str(s.to_dict()), before, "resolve() is pure")


func test_forest_helps_the_defender() -> void:
	var def_units := ["spearmen", "spearmen", "spearmen"]
	var att_units := ["tuskers", "tuskers"]
	var plains := _odds(def_units, att_units, "rivermarch", "kingdom")
	var forest := _odds(def_units, att_units, "greenglade", "kingdom")
	assert_true(forest.win_rate > plains.win_rate, "forest %s vs plains %s" % [forest.win_rate, plains.win_rate])
	var r := _battle(def_units, att_units, "greenglade", 5)
	assert_true(_side(r.report, "kingdom").triggers.get("terrain", 0) > 0, "the forest bonus was used")
	var p := _battle(def_units, att_units, "rivermarch", 5)
	assert_eq(_side(p.report, "kingdom").triggers.get("terrain", 0), 0, "no bonus on plains")


func test_every_trait_has_an_effect() -> void:
	# Shield Wall: only with company.
	var pair := _battle(["spearmen", "spearmen"], ["tuskers"], "rivermarch", 1)
	assert_true(_side(pair.report, "kingdom").triggers.get("Shield Wall", 0) > 0, "Shield Wall with a friend")
	var alone := _battle(["spearmen"], ["tuskers"], "rivermarch", 1)
	assert_eq(_side(alone.report, "kingdom").triggers.get("Shield Wall", 0), 0, "no Shield Wall alone")
	# Volley: crossbowmen are untouched while their front rank is at least as big (Tuskers, which have no
	# Skirmish, attack them; Fangthrowers could reach them on purpose).
	var volley := _battle(["spearmen", "spearmen", "spearmen", "crossbowmen"], ["tuskers"], "rivermarch", 2)
	var first: Dictionary = volley.report.rounds[0]
	assert_true(first.highlights.filter(func(h): return h.contains("Crossbowmen fell")).is_empty(), "crossbowmen screened in round 1")
	var vs := _side(volley.report, "kingdom")
	assert_false(vs.lost.has("Crossbowmen") and vs.lost.size() < 4, "crossbowmen never fall before the spearmen")
	# Charge: bonus damage in round 1 only, less in a forest.
	var charge := _battle(["knights", "knights"], ["tuskers", "tuskers", "tuskers"], "rivermarch", 3, "kingdom", "beasts")
	var charged := false
	for sd in range(1, 12):
		var c := _battle(["knights", "knights"], ["tuskers", "tuskers", "tuskers"], "rivermarch", sd)
		if String(c.report.rounds[0].line).contains("charged home"):
			charged = true
		for r in c.report.rounds.slice(1):
			assert_false(String(r.line).contains("charged home"), "charge only in round 1")
	assert_true(charged, "knights charged")
	assert_true(charge.report.lines.size() > 0)
	# Berserk: wounded tuskers get +3 attack.
	var s := _state([["d-1", "kingdom", "rivermarch", ["spearmen", "spearmen"]], ["a-1", "beasts", "rivermarch", ["tuskers"]]])
	s.find_army("a-1").units[0].current_hp = 7
	var berserk := AutoBattleResolver.resolve(s.find_army("a-1"), s.find_army("d-1"), s.find_province("rivermarch"), SeededRNG.new(4), s)
	assert_true(_side(berserk.report, "beasts").triggers.get("Berserk", 0) > 0, "a wounded tusker is berserk")
	var fresh := AutoBattleResolver.fight([{"faction": "beasts", "armies": [_custom_army("x", "beasts", [s.find_faction("beasts").unit_types[0]])]},
		{"faction": "kingdom", "armies": [_custom_army("y", "kingdom", [_custom_type("wall", 50, 1, 30, 20)])]}], {"kind": "province", "defender": ""}, SeededRNG.new(1))
	assert_false(String(fresh.result.report.rounds[0].line).contains("berserk"), "an unhurt tusker is not berserk in round 1")
	assert_true(String(berserk.report.rounds[0].line).contains("berserk"), "a wounded one is, from the first round")
	# Skirmish: fangthrowers reach the crossbowmen behind a full front rank; tuskers never do.
	var reached := 0
	for sd in range(1, 12):
		var skirm := _battle(["spearmen", "spearmen", "spearmen", "crossbowmen"], ["fangthrowers", "fangthrowers", "fangthrowers"], "rivermarch", sd)
		var k := _side(skirm.report, "kingdom")
		if k.lost.has("Crossbowmen") and k.lost.size() < 4:
			reached += 1
		var tusk := _battle(["spearmen", "spearmen", "spearmen", "crossbowmen"], ["tuskers", "tuskers", "tuskers"], "rivermarch", sd)
		var t := _side(tusk.report, "kingdom")
		assert_false(t.lost.has("Crossbowmen") and t.lost.size() < 4, "tuskers can't reach screened crossbowmen")
	assert_true(reached > 0, "fangthrowers kill screened crossbowmen before the front falls")
	# Terrain counts against Fangthrowers like anyone else now.
	var forest := _battle(["spearmen"], ["fangthrowers"], "greenglade", 5)
	assert_true(_side(forest.report, "kingdom").triggers.get("terrain", 0) > 0, "forest cover counts against fangthrowers")
	# Fury and Inspire: morale parts.
	var fury := _battle(["spearmen", "spearmen", "knight_captain"], ["war_bear"], "rivermarch", 6)
	var log0: Dictionary = _side(fury.report, "kingdom").morale_log[0]
	assert_eq(log0.parts.get("Fury", 0), -2, "the bear roars")
	assert_eq(log0.parts.get("Inspire", 0), 2, "the captain inspires")
	assert_eq(log0.parts.get("commander", 0), 2, "a commander steadies the line")
	# Pack Leader: units get +1 attack while the Warchief stands.
	var pack := _battle(["spearmen", "spearmen"], ["tuskers", "warchief"], "rivermarch", 7)
	assert_true(_side(pack.report, "beasts").triggers.get("Pack Leader", 0) > 0, "the warchief leads the pack")
	var nopack := _battle(["spearmen", "spearmen"], ["tuskers"], "rivermarch", 7)
	assert_eq(_side(nopack.report, "beasts").triggers.get("Pack Leader", 0), 0, "no warchief, no pack bonus")


func test_rout_when_morale_breaks() -> void:
	var routed := 0
	for sd in range(1, 10):
		var r := _battle(["crossbowmen", "crossbowmen", "crossbowmen"], ["war_bear", "warchief"], "rivermarch", sd)
		var k := _side(r.report, "kingdom")
		assert_eq(r.result.winner, "beasts")
		if k.routed:
			routed += 1
			assert_true(k.hp_end > 0, "a routed side still had strength left")
			assert_eq(r.report.end, "rout")
			assert_true(_all_text(r.report).contains("broke"), "the report says they broke")
	assert_true(routed > 0, "low-morale crossbowmen against a war bear break")


func test_round_cap_ends_the_battle() -> void:
	var wall := _custom_type("wall", 200, 1, 10, 20)
	var sides := [{"faction": "beasts", "armies": [_custom_army("b", "beasts", [wall])]},
		{"faction": "kingdom", "armies": [_custom_army("k", "kingdom", [wall])]}]
	var held: Dictionary = AutoBattleResolver.fight(sides, {"kind": "province", "defender": "kingdom"}, SeededRNG.new(1)).result
	assert_eq(held.report.rounds_fought, AutoBattleResolver.ROUND_CAP)
	assert_eq(held.report.end, "round_cap")
	assert_eq(held.winner, "kingdom", "the defender holds at the cap")
	assert_eq(held.tie_break, "defender")
	assert_eq(held.report.factors[0].id, "round_cap", "the cap is named as the deciding factor")
	var open_field: Dictionary = AutoBattleResolver.fight(sides, {"kind": "border", "defender": ""}, SeededRNG.new(1)).result
	assert_eq(open_field.report.end, "round_cap")
	assert_true(["kingdom", "beasts"].has(open_field.winner))


func test_report_always_explains_why_without_raw_ids() -> void:
	var matchups := [
		[["spearmen", "spearmen", "crossbowmen", "knight_captain"], ["tuskers", "tuskers", "fangthrowers"], "thornvale"],
		[["spearmen"], ["war_bear", "warchief"], "rivermarch"],
		[["knights", "knights", "spearmen"], ["tuskers", "fangthrowers", "fangthrowers"], "highcrag"],
		[["crossbowmen", "spearmen", "spearmen"], ["war_bear"], "crownkeep"],
		[["knight_captain"], ["warchief"], "greenglade"],
	]
	for m in matchups:
		for sd in range(1, 9):
			var r := _battle(m[0], m[1], m[2], sd)
			var rep: Dictionary = r.report
			assert_false(String(rep.why).is_empty(), "why is never empty")
			assert_true(rep.factors.size() >= 1 and rep.factors.size() <= 3, "1-3 factors, got %d" % rep.factors.size())
			assert_eq(r.result.why, rep.why)
			assert_true(rep.lines.size() >= 4, "who fought, rounds, casualties, result")
			_assert_no_raw_ids(_all_text(rep))
			for sr in rep.sides:
				assert_true(sr.hit_chance_range[0] <= sr.expected_hit_rate and sr.expected_hit_rate <= sr.hit_chance_range[1] or sr.attacks == 0)


func test_why_names_the_real_deciding_factors() -> void:
	# A lone spearman against a war bear and warchief: numbers decide, not luck or terrain.
	var r := _battle(["spearmen"], ["war_bear", "warchief"], "rivermarch", 1)
	assert_eq(r.result.winner, "beasts")
	var ids := []
	for f in r.report.factors:
		ids.append(f.id)
	assert_true(ids.has("numbers") or ids.has("commander") or ids.has("rout"), "decided by strength: %s" % [ids])
	assert_false(ids.has("terrain"), "no terrain on plains")


# --- odds -----------------------------------------------------------------------------------------

func test_odds_agree_with_the_resolver() -> void:
	var strong := _odds(["spearmen"], ["war_bear", "warchief", "tuskers"], "rivermarch", "beasts")
	assert_eq(strong.label, "likely win", strong.text)
	assert_false(strong.reasons.is_empty(), "odds give reasons")
	_assert_no_raw_ids(strong.text)
	var weak := _odds(["spearmen"], ["war_bear", "warchief", "tuskers"], "rivermarch", "kingdom")
	assert_eq(weak.label, "likely loss", weak.text)
	# The estimate is exactly the resolver on the fixed odds seeds.
	var wins := 0
	for i in AutoBattleResolver.ODDS_SAMPLES:
		var s := _state([["d-1", "kingdom", "thornvale", ["spearmen", "spearmen", "knight_captain"]], ["a-1", "beasts", "thornvale", ["tuskers", "tuskers"]]])
		var r := AutoBattleResolver.fight([{"faction": "beasts", "armies": [s.find_army("a-1")]}, {"faction": "kingdom", "armies": [s.find_army("d-1")]}],
			{"kind": "province", "defender": "kingdom", "province": s.find_province("thornvale"), "province_ids": ["thornvale"], "state": s},
			SeededRNG.new(AutoBattleResolver.odds_seed(i)))
		if r.result.winner == "kingdom":
			wins += 1
	var est := _odds(["spearmen", "spearmen", "knight_captain"], ["tuskers", "tuskers"], "thornvale", "kingdom")
	assert_eq(est.wins, wins)


func test_forecast_battle_odds() -> void:
	var s := _state([["kingdom-1", "kingdom", "highcrag", ["knights", "knights", "knight_captain"]], ["beasts-2", "beasts", "thornvale", ["fangthrowers"]]])
	var odds := Forecast.battle_odds(s, "kingdom", ["kingdom-1"], "thornvale")
	assert_true(odds.ok)
	assert_eq(odds.label, "likely win", odds.text)
	_assert_no_raw_ids(odds.text)
	assert_false(Forecast.battle_odds(s, "kingdom", ["kingdom-1"], "westwatch").ok, "nobody to fight")
	assert_false(RulesCodex.text("battle_odds").is_empty())


func test_codex_explains_every_battle_rule_and_trait() -> void:
	for id in ["battle_rounds", "battle_round_cap", "battle_hit_chance", "battle_terrain", "battle_morale", "battle_commanders", "battle_odds"]:
		assert_false(RulesCodex.text(id).is_empty(), "codex has %s" % id)
	for f in FactionData.FACTIONS:
		for u in f.unit_types + [f.commander]:
			var id := AutoBattleResolver.codex_id_for_trait(u.trait)
			assert_false(RulesCodex.text(id).is_empty(), "codex explains %s" % u.trait)
			assert_true(AutoBattleResolver.TRAIT_SHORT.has(u.trait), "%s has an effect" % u.trait)


# --- turn resolver integration --------------------------------------------------------------------

func test_turn_resolver_with_the_real_battles() -> void:
	var s := _state([
		["kingdom-1", "kingdom", "thornvale", ["spearmen", "spearmen", "crossbowmen", "knight_captain"]],
		["beasts-2", "beasts", "wildmoor", ["tuskers", "fangthrowers"]],
	])
	var orders := {"beasts": [MoveOrder.new("beasts-2", "thornvale")], "kingdom": []}
	var a := TurnResolver.resolve(s, orders, 11, AutoBattleResolver.new())
	var b := TurnResolver.resolve(s, orders, 11, AutoBattleResolver.new())
	var battles: Array = a.events.filter(func(e): return e.type == "battle")
	assert_eq(battles.size(), 1)
	var e: Dictionary = battles[0]
	assert_false(e.numbers.report.is_empty(), "the full report rides on the event")
	assert_true(e.text.contains(e.numbers.why), "the event text carries the why")
	assert_eq(e.codex, "defended")
	_assert_no_raw_ids(e.text)
	var texts_a: Array = a.events.map(func(x): return x.text)
	var texts_b: Array = b.events.map(func(x): return x.text)
	assert_eq(texts_a, texts_b, "deterministic through the turn resolver")
	var ns: GameState = a.new_state
	var winner: String = e.numbers.winner
	var loser := "beasts" if winner == "kingdom" else "kingdom"
	for army in ns.armies:
		assert_ne(army.owner, loser, "the losing armies are gone")
		assert_true(army.units.size() > 0 or army.commander != null, "no empty armies are left")
	var report: Dictionary = e.numbers.report
	var lost: int = _side(report, winner).fighters_lost
	var left := 0
	for army in ns.armies:
		left += army.units.size() + (1 if army.commander else 0)
	assert_eq(left, _side(report, winner).fighters_start - lost, "the winner's fallen units are removed")
	assert_true(s.find_army("beasts-2") != null, "the input state is untouched")


func test_print_sample_reports() -> void:
	for m in [[["spearmen", "spearmen", "crossbowmen", "knight_captain"], ["tuskers", "tuskers", "fangthrowers"], "thornvale", 3],
			[["spearmen", "spearmen", "spearmen"], ["war_bear", "warchief"], "rivermarch", 2],
			[["knights", "knights", "spearmen"], ["tuskers", "tuskers", "fangthrowers"], "highcrag", 5]]:
		var r := _battle(m[0], m[1], m[2], m[3])
		print("\n".join(r.report.lines))
		print("---")
	print(_odds(["spearmen", "spearmen", "crossbowmen", "knight_captain"], ["tuskers", "tuskers", "fangthrowers"], "thornvale", "beasts").text)


# --- report wording (#4 balance pass) --------------------------------------------------------------

func test_a_commander_alone_is_called_that() -> void:
	var s := _state([["beasts-1", "beasts", "fangridge", ["warchief"]], ["kingdom-2", "kingdom", "fangridge", ["spearmen", "spearmen"]]])
	assert_eq(TurnResolver.army_label(s, s.find_army("beasts-1")), "Thornmane Clans army at Fangridge (Warchief alone)")
	assert_eq(TurnResolver.army_label(s, s.find_army("kingdom-2")), "Aurel Crown army at Fangridge (2 units, no commander)")
	var r := AutoBattleResolver.resolve(s.find_army("beasts-1"), s.find_army("kingdom-2"), s.find_province("fangridge"), SeededRNG.new(1), s)
	var text := _all_text(r.report)
	assert_false(text.contains("0 units"), text)
	assert_true(text.contains("(Warchief alone)"), text)


func test_losses_read_naturally() -> void:
	var cases := [
		[1, 0, true, "Thornmane Clans' only fighter fled"],
		[1, 1, false, "Thornmane Clans lost its only fighter"],
		[1, 0, false, "Thornmane Clans lost no fighters"],
		[3, 0, true, "Thornmane Clans lost no fighters, but all 3 fled"],
		[4, 0, false, "Thornmane Clans lost none of its 4 fighters"],
		[3, 1, true, "Thornmane Clans lost 1 of 3 fighters, and the other 2 fled"],
		[3, 2, true, "Thornmane Clans lost 2 of 3 fighters, and the last one fled"],
		[3, 1, false, "Thornmane Clans lost 1 of 3 fighters"],
		[2, 2, false, "Thornmane Clans lost both fighters"],
		[4, 4, false, "Thornmane Clans lost all 4 fighters"],
	]
	for c in cases:
		var lost := []
		for i in c[1]:
			lost.append("Tuskers")
		var side := {"name": "Thornmane Clans", "count_start": c[0], "lost": lost, "routed": c[2]}
		assert_eq(AutoBattleResolver._losses_text(side), c[3])
	# And in real reports: never "lost 0 of" or "the other 1 fled".
	for sd in range(1, 30):
		var r := _battle(["spearmen", "crossbowmen"], ["warchief"], "rivermarch", sd)
		var casualties: String = r.report.lines.filter(func(l): return String(l).begins_with("Casualties: "))[0]
		assert_false(casualties.contains("lost 0 of") or casualties.contains("the other 1 fled"), casualties)


func test_the_bigger_force_has_more_hit_points_and_fighters() -> void:
	# More fighters but fewer hit points is not "the bigger force", and neither is the reverse.
	var many_small := _custom_type("Militia", 6, 6, 4, 8)
	var one_big := _custom_type("Giant", 40, 8, 4, 8)
	var sides := [{"faction": "beasts", "armies": [_custom_army("b", "beasts", [one_big])]},
		{"faction": "kingdom", "armies": [_custom_army("k", "kingdom", [many_small, many_small, many_small])]}]
	for sd in range(1, 15):
		var rep: Dictionary = AutoBattleResolver.fight(sides, {"kind": "province", "defender": ""}, SeededRNG.new(sd)).result.report
		assert_true(rep.all_factors.filter(func(f): return f.id == "numbers").is_empty(), "nobody is the bigger force: %s" % rep.why)
	# More of both is.
	var bigger := [{"faction": "beasts", "armies": [_custom_army("b", "beasts", [one_big])]},
		{"faction": "kingdom", "armies": [_custom_army("k", "kingdom", [one_big, many_small])]}]
	var rep2: Dictionary = AutoBattleResolver.fight(bigger, {"kind": "province", "defender": ""}, SeededRNG.new(1)).result.report
	var numbers: Array = rep2.all_factors.filter(func(f): return f.id == "numbers")
	assert_eq(numbers.size(), 1)
	if numbers.size() == 1:
		assert_eq(numbers[0].faction, "kingdom")
		assert_true(String(numbers[0].text).contains("2 fighters (46 hp) against 1 (40 hp)"), numbers[0].text)


func test_report_lists_each_sides_roster() -> void:
	var r := _battle(["spearmen", "crossbowmen", "spearmen", "knight_captain"], ["tuskers", "tuskers", "war_bear"], "rivermarch", 3)
	var k := _side(r.report, "kingdom")
	var b := _side(r.report, "beasts")
	assert_eq(k.roster.units, [{"id": "spearmen", "name": "Spearmen", "count": 2}, {"id": "crossbowmen", "name": "Crossbowmen", "count": 1}])
	assert_eq(k.roster.commanders, [{"id": "knight_captain", "name": "Knight Captain"}])
	assert_eq(k.roster.text, "Spearmen (2), Crossbowmen, led by Knight Captain")
	assert_eq(b.roster.text, "Tuskers (2), War Bear")
	assert_eq(b.roster.commanders, [])
	_assert_no_raw_ids(k.roster.text + " " + b.roster.text)
	var alone := _battle(["spearmen"], ["warchief"], "rivermarch", 3)
	assert_eq(_side(alone.report, "beasts").roster.text, "Warchief alone")
