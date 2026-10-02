extends "res://tests/test_case.gd"
## Battle balance (#4): seeded batches of real AutoBattleResolver battles stay inside the bands the
## director set, the "why" summary ranks factors fairly, and every trait's description states the
## numbers its rules use. Armies and batches come from tools/balance/balance.gd, the same code the
## matchup harness (tools/balance/matchups.gd) prints its tables with. Each batch replays exactly.

const Balance := preload("res://tools/balance/balance.gd")
const CROWN := "kingdom"
const CLANS := "beasts"


func _pct(state: GameState, crown: Array, clans: Array, ground_key: String, seeds: int, base_seed := 0) -> float:
	return Balance.batch(state, crown, clans, Balance.ground(ground_key), seeds, base_seed).crown_pct


func _repeat(type_id: String, n: int) -> Array:
	var out := []
	for i in n:
		out.append(type_id)
	return out


# --- the director's band for #4 -------------------------------------------------------------------

func test_starting_armies_are_even_on_open_plains() -> void:
	# Director's note on #4: each side wins 40-60% of seeded battles between the two starting armies in
	# open plains (both arrive together, so nobody defends and nobody gets terrain).
	var s := Balance.new_state()
	var crown := Balance.starting_army(s, CROWN)
	var clans := Balance.starting_army(s, CLANS)
	assert_eq(crown.size(), 4, "one of each unit type and the commander")
	var p := _pct(s, crown, clans, "open", 200)
	assert_true(p >= 40.0 and p <= 60.0, "starting armies on open plains: Aurel Crown won %.1f%%, Thornmane Clans %.1f%%" % [p, 100.0 - p])
	# Holding open plains gives no terrain, so it stays close too (the defender only holds at the round cap).
	for g in ["plains_crown", "plains_clans"]:
		var q := _pct(s, crown, clans, g, 120, 500)
		assert_true(q >= 30.0 and q <= 70.0, "starting armies, %s: Aurel Crown won %.1f%%" % [g, q])


func test_equal_gold_fights_are_inside_their_bands() -> void:
	# No single unit pair outside 20-80% at equal gold on open plains, and mixed armies within 30-70%.
	var s := Balance.new_state()
	for pair in [["spearmen", "tuskers"], ["crossbowmen", "fangthrowers"], ["knights", "war_bear"], ["spearmen", "war_bear"]]:
		var n := Balance.equal_gold(s, pair[0], pair[1], 100)
		var crown := _repeat(pair[0], n[0])
		var clans := _repeat(pair[1], n[1])
		var gold_a := Balance.cost(s, CROWN, crown)
		var gold_b := Balance.cost(s, CLANS, clans)
		assert_true(absf(gold_a - gold_b) <= 0.15 * maxf(gold_a, gold_b), "%s gold %d vs %d is close to equal" % [pair, gold_a, gold_b])
		var p := _pct(s, crown, clans, "open", 200)
		assert_true(p >= 20.0 and p <= 80.0, "%d %s vs %d %s (%d vs %d gold): Aurel Crown won %.1f%%" % [n[0], pair[0], n[1], pair[1], gold_a, gold_b, p])
	var mixed := _pct(s, Balance.mixed(s, CROWN, 100), Balance.mixed(s, CLANS, 100), "open", 120)
	assert_true(mixed >= 30.0 and mixed <= 70.0, "mixed armies at 100 gold: Aurel Crown won %.1f%%" % mixed)


func test_forest_helps_the_defender_but_does_not_decide() -> void:
	# Holding a forest raises the defender's win rate over holding open plains, but not to a sure thing.
	var s := Balance.new_state()
	var crown := Balance.starting_army(s, CROWN)
	var clans := Balance.starting_army(s, CLANS)
	var crown_plains := _pct(s, crown, clans, "plains_crown", 150, 900)
	var crown_forest := _pct(s, crown, clans, "forest_crown", 150, 900)
	assert_true(crown_forest > crown_plains, "Aurel Crown defending: forest %.1f%% vs plains %.1f%%" % [crown_forest, crown_plains])
	assert_true(crown_forest < 95.0, "the forest is not a sure win for Aurel Crown: %.1f%%" % crown_forest)
	var clans_plains := 100.0 - _pct(s, crown, clans, "plains_clans", 150, 900)
	var clans_forest := 100.0 - _pct(s, crown, clans, "forest_clans", 150, 900)
	assert_true(clans_forest > clans_plains, "Thornmane Clans defending: forest %.1f%% vs plains %.1f%%" % [clans_forest, clans_plains])
	assert_true(clans_forest < 95.0, "the forest is not a sure win for Thornmane Clans: %.1f%%" % clans_forest)


# --- the "why" ranks factors by what they really added ---------------------------------------------

func test_commander_damage_does_not_crowd_out_the_other_reasons() -> void:
	# The commander factor counts only damage beyond what the same gold in ordinary units would have
	# dealt, so it leads a battle's "why" only when it really carried it, and traits get named.
	var s := Balance.new_state()
	var kc := s.find_faction(CROWN).commander_type.id
	var wc := s.find_faction(CLANS).commander_type.id
	var batches := [
		[Balance.starting_army(s, CROWN), Balance.starting_army(s, CLANS), "open"],
		[Balance.starting_army(s, CROWN), Balance.starting_army(s, CLANS), "forest_crown"],
		[Balance.starting_army(s, CROWN), Balance.starting_army(s, CLANS), "hills_clans"],
		[Balance.mixed(s, CROWN, 75, [kc]), Balance.mixed(s, CLANS, 75, [wc]), "open"],
		[Balance.mixed(s, CROWN, 125, [kc]), Balance.mixed(s, CLANS, 125, [wc]), "fort_crown"],
	]
	var battles := 0
	var commander_first := 0
	var traits := {}
	for b in batches:
		var r := Balance.batch(s, b[0], b[1], Balance.ground(b[2]), 40)
		battles += r.n
		for key in r.top:
			if key.begins_with("commander|"):
				commander_first += r.top[key]
		for key in r.cited:
			var id: String = key.split("|")[0]
			if AutoBattleResolver.TRAIT_TEXT.has(id) or id == "morale_Inspire":
				traits[id.trim_prefix("morale_")] = true
	assert_eq(battles, 200)
	assert_true(commander_first * 2 < battles, "commander damage leads the why in %d of %d commander-led battles" % [commander_first, battles])
	assert_true(traits.size() >= 2, "at least two different traits are named as reasons: %s" % [traits.keys()])


func test_commander_factor_is_measured_against_the_same_gold_in_units() -> void:
	# The yardstick: the commander's cost in average units of its side, each attacking the same target,
	# times the share of the side's units still standing.
	var s := Balance.new_state()
	var line := Balance.army(s, CROWN, ["spearmen", "crossbowmen", "knight_captain"])
	var sides := AutoBattleResolver._build_sides([{"faction": CROWN, "armies": [line]}], "", s)
	var side: Dictionary = sides[0]
	var captain: Dictionary = side.fighters[2]
	var per_unit := 0.0
	for u in line.units:
		per_unit += AutoBattleResolver.hit_chance(u.type.attack, 5) / 100.0 * AutoBattleResolver.damage(u.type.attack, 5)
	per_unit /= 2.0
	var cost_in_units: float = captain.type.cost / ((line.units[0].type.cost + line.units[1].type.cost) / 2.0)
	assert_true(absf(AutoBattleResolver._line_baseline(side, captain, 5, 0) - per_unit * cost_in_units) < 0.001, "full line")
	side.fighters[0].alive = false
	assert_true(absf(AutoBattleResolver._line_baseline(side, captain, 5, 0) - per_unit * cost_in_units * 0.5) < 0.001, "half the line left")
	side.fighters[1].alive = false
	assert_eq(AutoBattleResolver._line_baseline(side, captain, 5, 0), 0.0, "no line left: every hit the commander lands counts")
	# In battle: a Knight Captain whose lone Crossbowmen fall early fights on by itself, and that damage
	# is named; the clause never claims more than the commander dealt.
	var kc := s.find_faction(CROWN).commander_type.id
	var named := 0
	var clause := RegEx.create_from_string("dealt about (\\d+) damage, about (\\d+) more than the same gold in ordinary units would have")
	for i in 30:
		var r: Dictionary = Balance.batch(s, ["crossbowmen", kc], ["tuskers", "tuskers"], Balance.ground("open"), 1, i, 1).reports[0]
		for f in r.all_factors:
			if f.id != "commander":
				continue
			named += 1
			assert_true(f.impact > 0.0, "only a positive contribution is a factor")
			var m := clause.search(f.text)
			if f.faction == r.winner:
				assert_true(m != null, f.text)
			if m != null:
				assert_true(int(m.get_string(2)) <= int(m.get_string(1)), "beyond-the-yardstick damage is part of the total: %s" % f.text)
	assert_true(named > 0, "the Knight Captain fighting on alone is named")


# --- every trait description states what the rules do ----------------------------------------------

func test_trait_descriptions_match_the_rules() -> void:
	var s := GameState.new(1)
	var seen := {}
	for f in s.factions:
		var types: Array = f.unit_types.duplicate()
		types.append(f.commander_type)
		for ut in types:
			assert_true(AutoBattleResolver.TRAIT_TEXT.has(ut.trait_id), "%s has a trait the rules know: %s" % [ut.name, ut.trait_id])
			var text: String = AutoBattleResolver.TRAIT_TEXT.get(ut.trait_id, "")
			assert_eq(ut.get_trait_desc(), text, "%s's trait description is the rules' own text" % ut.name)
			var codex := RulesCodex.text(AutoBattleResolver.codex_id_for_trait(ut.trait_id))
			assert_true(codex.begins_with(text), "the codex entry for %s starts with the same text: %s" % [ut.trait_id, codex])
			assert_true(AutoBattleResolver.TRAIT_SHORT.has(ut.trait_id), "%s has a one-line summary" % ut.trait_id)
			seen[ut.trait_id] = true
	assert_eq(seen.size(), 8, "eight traits, one per unit type")
	# The old descriptions promised things the rules never did.
	for text in AutoBattleResolver.TRAIT_TEXT.values():
		for wrong in ["adjacent", "nearby", "mobility", "more units", "without penalty", "first attack of battle"]:
			assert_false(String(text).to_lower().contains(wrong), "trait text claims '%s': %s" % [wrong, text])
	# Every number a description states is the number the rules use (checked against the rules below).
	var t := AutoBattleResolver.TRAIT_TEXT
	assert_true(t["Shield Wall"].contains("+%d defense" % AutoBattleResolver.SHIELD_WALL_DEFENSE))
	assert_true(t["Charge"].contains("+%d damage" % AutoBattleResolver.CHARGE_DAMAGE))
	assert_true(t["Charge"].contains("(+%d in a forest)" % AutoBattleResolver.CHARGE_DAMAGE_FOREST))
	assert_true(t["Inspire"].contains("+%d morale" % AutoBattleResolver.INSPIRE_MORALE))
	assert_true(t["Berserk"].contains("+%d attack" % AutoBattleResolver.BERSERK_ATTACK))
	assert_true(t["Fury"].contains("-%d morale" % AutoBattleResolver.FURY_MORALE) and t["Fury"].contains("-%d in all" % AutoBattleResolver.FURY_MAX))
	assert_true(t["Pack Leader"].contains("+%d attack" % AutoBattleResolver.PACK_LEADER_ATTACK))
	assert_true(t["Skirmish"].contains("second rank") and t["Volley"].contains("Skirmish"), "Volley and Skirmish describe each other's rule")
	assert_false(t["Skirmish"].contains("forest"), "Skirmish no longer touches terrain")


## A fighter record as AutoBattleResolver builds it, for checking one rule at a time.
func _fighter(side: int, type_id: String, owner: String, hp := -1) -> Dictionary:
	var s := Balance.new_state()
	var a := Balance.army(s, owner, [type_id])
	var u: Unit = a.commander if a.commander else a.units[0]
	if hp >= 0:
		u.current_hp = hp
	return AutoBattleResolver._fighter(side, a, u, a.commander != null)


func _side(fighters: Array, defender := false) -> Dictionary:
	return {"fighters": fighters, "is_defender": defender, "triggers": {}}


func test_each_trait_does_exactly_what_its_text_says() -> void:
	var plains := {"terrain": "plains", "fort": false}
	var forest := {"terrain": "forest", "fort": false}
	var tusker := _fighter(1, "tuskers", CLANS)
	# Shield Wall: +N defense while another fighter on its side stands, none alone.
	var spear := _fighter(0, "spearmen", CROWN)
	var friend := _fighter(0, "crossbowmen", CROWN)
	var walled := AutoBattleResolver._defense(spear, _side([spear, friend]), tusker, plains)
	assert_eq(walled.parts.get("Shield Wall", 0), AutoBattleResolver.SHIELD_WALL_DEFENSE)
	assert_eq(walled.value, spear.type.defense + AutoBattleResolver.SHIELD_WALL_DEFENSE)
	friend.alive = false
	assert_false(AutoBattleResolver._defense(spear, _side([spear, friend]), tusker, plains).parts.has("Shield Wall"), "alone, no wall")
	# Berserk: +N attack below full hp, none when unhurt.
	var hurt := _fighter(1, "tuskers", CLANS, 1)
	assert_eq(AutoBattleResolver._attack(hurt, _side([hurt]), plains).parts.get("Berserk", 0), AutoBattleResolver.BERSERK_ATTACK)
	assert_false(AutoBattleResolver._attack(tusker, _side([tusker]), plains).parts.has("Berserk"), "unhurt, not berserk")
	# Pack Leader: +N attack to every unit while the Warchief stands, not to the Warchief itself.
	var chief := _fighter(1, "warchief", CLANS)
	var pack := _side([tusker, chief])
	assert_eq(AutoBattleResolver._attack(tusker, pack, plains).parts.get("Pack Leader", 0), AutoBattleResolver.PACK_LEADER_ATTACK)
	assert_false(AutoBattleResolver._attack(chief, pack, plains).parts.has("Pack Leader"), "commanders don't get it")
	# Terrain and forts count against every attacker, Fangthrowers included (Skirmish is about reach).
	var thrower := _fighter(1, "fangthrowers", CLANS)
	var held := _side([spear], true)
	var vs_thrower := AutoBattleResolver._defense(spear, held, thrower, {"terrain": "forest", "fort": true})
	assert_eq(vs_thrower.parts.get("terrain", 0), AutoBattleResolver.TERRAIN.forest.defense, "forest cover counts")
	assert_eq(vs_thrower.parts.get("fort", 0), AutoBattleResolver.FORT_DEFENSE, "the fort counts")
	# Inspire and the commander: +N morale each while the Knight Captain stands. Fury: -N per War Bear,
	# at most -MAX.
	var captain := _fighter(0, "knight_captain", CROWN)
	var crown := {"fighters": [spear, captain], "base_morale": 8}
	var bears := []
	for i in 3:
		bears.append(_fighter(1, "war_bear", CLANS))
	var one_bear := {"fighters": [bears[0]], "base_morale": 9}
	var m := AutoBattleResolver._morale([crown, one_bear], 0, [0, 1])
	assert_eq(m.parts.get("Inspire", 0), AutoBattleResolver.INSPIRE_MORALE)
	assert_eq(m.parts.get("commander", 0), AutoBattleResolver.COMMANDER_MORALE)
	assert_eq(m.parts.get("Fury", 0), -AutoBattleResolver.FURY_MORALE)
	var three := AutoBattleResolver._morale([crown, {"fighters": bears, "base_morale": 9}], 0, [0, 1])
	assert_eq(three.parts.get("Fury", 0), -mini(AutoBattleResolver.FURY_MAX, 3 * AutoBattleResolver.FURY_MORALE))
	# Volley: the front rank shields the Crossbowmen while at least as many front-rank units stand as
	# Crossbowmen; Skirmish reaches them anyway; commanders are targets only once every unit has fallen.
	var bow := _fighter(0, "crossbowmen", CROWN)
	var front := _fighter(0, "spearmen", CROWN)
	var lord := _fighter(0, "knight_captain", CROWN)
	var sides := [{"fighters": [front, bow, lord]}, {"fighters": [tusker, thrower]}]
	assert_eq(AutoBattleResolver._targets(sides, 1, [0, 1], tusker), [front], "one Spearman shields one Crossbowman")
	assert_eq(AutoBattleResolver._targets(sides, 1, [0, 1], thrower), [front, bow], "Skirmish reaches the second rank")
	var bow2 := _fighter(0, "crossbowmen", CROWN)
	var thin := [{"fighters": [front, bow, bow2, lord]}, {"fighters": [tusker]}]
	assert_eq(AutoBattleResolver._targets(thin, 1, [0, 1], tusker), [front, bow, bow2], "one Spearman can't shield two Crossbowmen")
	front.alive = false
	assert_eq(AutoBattleResolver._targets(sides, 1, [0, 1], tusker), [bow], "then the crossbowmen")
	bow.alive = false
	assert_eq(AutoBattleResolver._targets(sides, 1, [0, 1], thrower), [lord], "the commander last, even for Skirmish")


func test_charge_adds_its_damage_in_the_first_round_only() -> void:
	# One Knight against a wall that can't break: a round-1 hit deals the normal damage plus the charge
	# bonus (less in a forest), later hits deal the normal damage.
	var s := Balance.new_state()
	var wall := UnitType.new()
	wall.id = "wall"
	wall.name = "Wall"
	wall.hp = 500
	wall.attack = 1
	wall.defense = 4
	wall.morale = 20
	for terrain in ["rivermarch", "greenglade"]:
		var bonus: int = AutoBattleResolver.CHARGE_DAMAGE_FOREST if terrain == "greenglade" else AutoBattleResolver.CHARGE_DAMAGE
		var checked := [false, false]
		for sd in range(1, 40):
			var knight := Balance.army(s, CROWN, ["knights"], "kingdom-1")
			var foe := Army.new()
			foe.id = "beasts-2"
			foe.owner = CLANS
			foe.units.append(Unit.new(wall, CLANS))
			var ctx := {"kind": "province", "defender": "", "province": s.find_province(terrain), "province_ids": [terrain], "state": s}
			var rep: Dictionary = AutoBattleResolver.fight([{"faction": CLANS, "armies": [foe]}, {"faction": CROWN, "armies": [knight]}], ctx, SeededRNG.new(sd)).result.report
			var plain := AutoBattleResolver.damage(knight.units[0].type.attack, wall.defense)
			for r in rep.rounds.slice(0, 2):
				var dealt: int = r.dealt[1]
				if dealt > 0:
					var first: bool = r.round == 1
					assert_eq(dealt, plain + (bonus if first else 0), "%s round %d hit" % [terrain, r.round])
					checked[0 if first else 1] = true
		assert_true(checked[0] and checked[1], "%s: saw a charging hit and a later hit" % terrain)


func test_skirmish_reaching_the_second_rank_is_named_in_the_why() -> void:
	# A Fangthrower army against Crossbowmen behind a line of Spearmen: when the Fangthrowers' hits on
	# the shielded Crossbowmen carry the battle, the why says so.
	var s := Balance.new_state()
	var crown := Balance.ratio_army(s, CROWN, [["spearmen", 1], ["crossbowmen", 1]], 300)
	var clans := Balance.ratio_army(s, CLANS, [["fangthrowers", 1]], 300)
	var b := Balance.batch(s, crown, clans, Balance.ground("open"), 12, 0, 12)
	var named := 0
	for rep in b.reports:
		for f in rep.factors:
			if f.id == "Skirmish" and f.faction == CLANS and rep.winner == CLANS:
				named += 1
				assert_true(String(f.text).contains("skirmished past the front line and hit the Crossbowmen behind it"), f.text)
	assert_true(named > 0, "Skirmish is named when it carries the battle")


func test_big_armies_have_no_unbeatable_make_up() -> void:
	# At 300 gold a Crown line of Spearmen and Crossbowmen used to beat every Thornmane army style. Now
	# Skirmish and the thinner Volley shield give it a counter: an all-Fangthrower army beats it.
	var s := Balance.new_state()
	var line := Balance.ratio_army(s, CROWN, [["spearmen", 1], ["crossbowmen", 1]], 300)
	var throwers := Balance.ratio_army(s, CLANS, [["fangthrowers", 1]], 300)
	var p := _pct(s, line, throwers, "open", 30)
	assert_true(p < 50.0, "Spearmen + Crossbowmen 1:1 against all Fangthrowers at 300 gold: Aurel Crown won %.1f%%" % p)
