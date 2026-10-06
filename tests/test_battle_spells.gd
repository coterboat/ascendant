extends "res://tests/test_case.gd"
## M5-7 (#118), design/M5_MAGIC_FOG.md §3.2, §5.1-§5.4: battle spells. Fixed-seed battles pin each spell: the
## Mage trait and its rank, the cast step (highest bonus, ruler first, fighter id, spreading out over the
## spellbook, on and off, the Regent's locked row), Sunlance's and Bloodbolt's targets (never overkill, rulers
## last), spell resistance, Shield of Law's field rule, Briar Snare's forest count, the bleed, the Blood Moon,
## Dawn Blessing's morale, the curse's healing skips, mastery, and "a battle with no caster draws exactly what
## it drew before". Every expected number comes from data/magic.gd and the resolver's constants.

const MB := preload("res://tests/magic_battle_fixtures.gd")
const Scenarios := preload("res://tools/battle_log/scenarios.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const LANCE := "spell_sunlance"
const SHIELD := "spell_shield_of_law"
const SNARE := "spell_briar_snare"
const BURST := "spell_sunburst"
const BOLT := "spell_bloodbolt"
const PACT := ["beasts_boar_hide", "beasts_raiding", "beasts_oath_blood", "beasts_blood_pact"]


func _checks(lg: Dictionary, report: Dictionary, what: String) -> void:
	assert_eq(BattleLog.validate(lg), [], "%s: validate" % what)
	assert_eq(BattleLog.verify_draws(lg), [], "%s: verify_draws" % what)
	assert_eq(BattleLog.cross_check(lg, report), [], "%s: cross_check" % what)


## Round `n`'s casts: [[caster id, spell]].
func _casts(lg: Dictionary, n: int) -> Array:
	return MB.events(lg, "cast", n).map(func(e): return [int(e.by), String(e.spell)])


func _spells(lg: Dictionary, n: int) -> Array:
	return MB.events(lg, "cast", n).map(func(e): return String(e.spell))


func _value(spell: String, key: String) -> int:
	return int(MagicData.SPELLS[spell][key])


# --- the Mage trait ------------------------------------------------------------------------------------

func test_the_mage_trait_fights_from_the_second_rank_and_says_so() -> void:
	var t := AutoBattleResolver.MAGE
	assert_eq(t, MagicData.MAGE_TRAIT, "the trait's name is the data's")
	assert_true(AutoBattleResolver.TRAIT_TEXT.has(t) and AutoBattleResolver.TRAIT_SHORT.has(t), "the Mage trait has its rule text and summary")
	assert_true(RulesCodex.text("trait_mage").begins_with(AutoBattleResolver.TRAIT_TEXT[t]), "the codex starts with the rule's text")
	assert_eq(MagicRules.mage_type(CROWN).get_trait_desc(), AutoBattleResolver.TRAIT_TEXT[t], "the mage card reads the rule")
	assert_false(AutoBattleResolver.TRAIT_TEXT[t].contains("ordinary soldiers"), "no longer promises mages fight in the front rank")
	var s := MB.with_nodes(MB.game(), CROWN, ["sunlance"])
	var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "adepts"])
	var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers"])
	var r := MB.fight(s, [a, b], "rivermarch", "", 3)
	var adept: int = MB.fighters_of(r.log, "adepts")[0]
	assert_eq(int(r.log.fighters[adept].tier), 1, "an Adept stands in the second rank")
	assert_eq(r.log.sides[0 if r.log.sides[0].faction == CROWN else 1].casters, [adept], "the side lists its caster")
	assert_eq(r.log.fighters[adept].get("mastery", {}), {"sun": 0, "law": 0}, "a mage's mastery is +0 in each school")
	assert_true(r.log.get("magic", false), "a magic game's log says so")
	_checks(r.log, r.result.report, "one Adept")


# --- the cast step --------------------------------------------------------------------------------------

func _crown_field(order: Array = [], off: Array = []) -> Dictionary:
	var s := MB.with_nodes(MB.game(), CROWN, ["sunlance", "shield_of_law"])
	if not order.is_empty():
		MB.spellbook(s, CROWN, order, off)
	var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "spearmen",
		"knights", "knights", "adepts", "adepts", "adepts"])
	var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers", "tuskers", "tuskers", "war_bear", "war_bear"])
	return MB.fight(s, [a, b], "rivermarch", "", 5)


func test_casters_spread_over_the_spellbook_in_order() -> void:
	# Defaults (Sunburst, Sunlance, Shield of Law), Sunburst unknown: Sunlance, Shield of Law, then Sunlance again.
	var r := _crown_field()
	var adepts := MB.fighters_of(r.log, "adepts")
	assert_eq(_casts(r.log, 1), [[adepts[0], "sunlance"], [adepts[1], "shield_of_law"], [adepts[2], "sunlance"]],
		"three Adepts spread out: Sunlance, Shield of Law, then the top again")
	_checks(r.log, r.result.report, "defaults")
	# Shield of Law first: it covers the 6 Spearmen, Sunlance is next, and the third Adept starts again from the
	# top, where Shield of Law is still useful for the 2 Knights.
	r = _crown_field(["shield_of_law", "sunlance", "sunburst"])
	assert_eq(_spells(r.log, 1), ["shield_of_law", "sunlance", "shield_of_law"], "the order the player set")
	var shields := MB.events(r.log, "cast", 1).filter(func(e): return e.spell == "shield_of_law")
	assert_eq(shields[0].targets.size(), _value("shield_of_law", "count"), "the first covers 6, the most numerous type")
	assert_true(shields[0].targets.all(func(id): return r.log.fighters[int(id)].type == "spearmen"), "the Spearmen")
	assert_true(shields[1].targets.all(func(id): return r.log.fighters[int(id)].type == "knights") and shields[1].targets.size() == 2,
		"the second covers the 2 Knights, the type with units not yet shielded")
	_checks(r.log, r.result.report, "shield first")
	# Sunlance switched off: two Shields, then nothing is useful, so the third Adept attacks.
	r = _crown_field(["sunburst", "sunlance", "shield_of_law"], ["sunlance"])
	assert_eq(_spells(r.log, 1), ["shield_of_law", "shield_of_law"], "a spell switched off is never cast")
	var third: int = MB.fighters_of(r.log, "adepts")[2]
	assert_true(MB.events(r.log, "attack", 1).any(func(e): return int(e.by) == third), "a caster with nothing useful attacks")
	assert_false(MB.events(r.log, "cast").any(func(e): return e.spell == "sunlance"), "Sunlance is off for the whole battle")
	_checks(r.log, r.result.report, "Sunlance off")


func test_a_caster_that_casts_doesnt_attack_and_a_mage_that_attacks_isnt_volley() -> void:
	var r := _crown_field(["sunburst", "sunlance", "shield_of_law"], ["sunlance"])
	var lg: Dictionary = r.log
	for c in MB.events(lg, "cast"):
		assert_false(MB.events(lg, "attack", int(c.n)).any(func(e): return int(e.by) == int(c.by)),
			"round %d: fighter %d cast, so it didn't attack" % [int(c.n), int(c.by)])
	var third: int = MB.fighters_of(lg, "adepts")[2]
	var its := MB.events(lg, "attack").filter(func(e): return int(e.by) == third)
	assert_false(its.is_empty(), "the third Adept attacked")
	var crown := 0 if lg.sides[0].faction == CROWN else 1
	assert_false(r.sides[crown].impact.has(AutoBattleResolver.VOLLEY), "its attacks from the second rank are not counted as Volley")
	assert_false(r.result.report.all_factors.any(func(f): return f.id == AutoBattleResolver.VOLLEY), "no Volley in the why")


func test_the_regent_casts_his_own_sunlance_and_his_row_can_be_switched_off() -> void:
	var s := MB.game({CROWN: MB.REGENT})
	var reg := MB.ruler_at(s, CROWN, "rivermarch", 3)
	var front := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "spearmen"])
	var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers", "tuskers"])
	var r := MB.fight(s, [reg, front, b], "rivermarch", "", 2)
	var regent: int = r.log.fighters.filter(func(f): return f.role == "ruler")[0].id
	for n in range(1, int(r.result.report.rounds_fought) + 1):
		assert_eq(_casts(r.log, n), [[regent, "sunlance"]], "round %d: the Regent alone casts Sunlance, never researched" % n)
	assert_false(MB.events(r.log, "attack").any(func(e): return int(e.by) == regent), "so he never attacks")
	_checks(r.log, r.result.report, "the Regent")
	# His locked row switched off: he attacks, as in a game without magic.
	MB.spellbook(s, CROWN, MagicData.SPELLBOOK[CROWN], ["sunlance"])
	r = MB.fight(s, [reg, front, b], "rivermarch", "", 2)
	assert_true(MB.events(r.log, "cast").is_empty(), "Sunlance off: no casts")
	assert_true(MB.events(r.log, "attack").any(func(e): return int(e.by) == regent), "he attacks")


func test_ruler_first_among_equals_and_the_field_rule_in_the_examples() -> void:
	# §5.1: the Regent and one Adept, both +0: the Regent (ruler first) casts Sunlance, the Adept Shield of Law.
	var s := MB.with_nodes(MB.game({CROWN: MB.REGENT}), CROWN, ["sunlance", "shield_of_law"])
	var reg := MB.ruler_at(s, CROWN, "rivermarch", 0)
	var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "spearmen", "adepts"])
	var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers", "tuskers"])
	var r := MB.fight(s, [reg, a, b], "rivermarch", "", 4)
	var regent: int = r.log.fighters.filter(func(f): return f.role == "ruler")[0].id
	var adept: int = MB.fighters_of(r.log, "adepts")[0]
	assert_eq(_casts(r.log, 1), [[regent, "sunlance"], [adept, "shield_of_law"]], "ruler first, then they spread")
	_checks(r.log, r.result.report, "Regent and Adept")
	# Higher mastery casts first: at rank 2 the Regent is +1 in the Sun, and still first.
	reg = MB.ruler_at(s, CROWN, "rivermarch", 3)
	r = MB.fight(s, [reg, a, b], "rivermarch", "", 4)
	assert_eq(int(MB.events(r.log, "cast", 1)[0].by), regent, "the highest bonus first")
	# Defending a fort, a forest or hills, Shield of Law is never useful, so the Adept casts Sunlance too.
	for where in ["crownkeep", "thornvale", "highcrag"]:
		var p := s.find_province(where)
		assert_true(p.has_fort or AutoBattleResolver.TERRAIN[p.terrain].defense > 0, "%s gives the defender ground" % where)
		reg.location = where
		a.location = where
		b.location = where
		r = MB.fight(s, [reg, a, b], where, CROWN, 4)
		assert_eq(_spells(r.log, 1), ["sunlance", "sunlance"], "defending %s: Shield of Law is skipped" % where)
		var skip: Array = MB.events(r.log, "cast", 1)[1].get("skipped", [])
		assert_true(skip.any(func(x): return x.spell == "shield_of_law"), "%s: the cast says Shield of Law was skipped, and why" % where)
		_checks(r.log, r.result.report, "defending " + where)


func test_clans_examples_one_shaman_snares_two_cast_bloodbolt_or_snare_more() -> void:
	var s := MB.with_nodes(MB.game(), CLANS, ["briar_snare"])
	var crown := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "spearmen",
		"spearmen", "spearmen", "knights", "knights", "knights", "knights"])
	var one := MB.army(s, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers", "tuskers", "shamans"])
	var r := MB.fight(s, [crown, one], "rivermarch", "", 6)
	for n in range(1, int(r.result.report.rounds_fought) + 1):
		var spells := _spells(r.log, n)
		assert_eq(spells, ["briar_snare"], "round %d: one Shaman snares" % n)
	_checks(r.log, r.result.report, "one Shaman")
	# Two Shamans, Bloodbolt unknown: the second snares 6 more of the most numerous type with units not yet snared.
	var two := MB.army(s, CLANS, "beasts-3", "rivermarch", ["tuskers", "tuskers", "tuskers", "shamans", "shamans"])
	r = MB.fight(s, [crown, two], "rivermarch", "", 6)
	var c1: Array = MB.events(r.log, "cast", 1)
	assert_eq(c1.map(func(e): return e.spell), ["briar_snare", "briar_snare"], "both snare")
	var types := []
	for e in c1:
		for id in e.targets:
			types.append(String(r.log.fighters[int(id)].type))
	assert_eq(types.count("spearmen"), 8, "the Spearmen (8 standing, the most numerous) first: 6, then the other 2")
	assert_eq(c1[1].targets.size(), 2, "the second snares only the 2 left: a unit takes a hex once a round")
	# Bloodbolt known: the second casts it.
	s = MB.with_nodes(s, CLANS, ["bloodbolt"])
	crown = s.find_army("kingdom-1")
	two = s.find_army("beasts-3")
	r = MB.fight(s, [crown, two], "rivermarch", "", 6)
	assert_eq(_spells(r.log, 1), ["briar_snare", "bloodbolt"], "Bloodbolt known: the second Shaman casts it")
	_checks(r.log, r.result.report, "two Shamans")


# --- bolts ----------------------------------------------------------------------------------------------

func test_sunlance_focuses_the_biggest_creature_most_hurt_first_never_overkills_and_reaches_rulers_last() -> void:
	var s := MB.with_nodes(MB.game({CLANS: MB.AVATAR}), CROWN, ["sunlance"])
	var lance := _value("sunlance", "value")
	var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "spearmen", "spearmen", "adepts", "adepts", "adepts", "adepts"])
	var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["war_bear", "war_bear", "tuskers", "tuskers"])
	var avatar := MB.ruler_at(s, CLANS, "rivermarch", 3)
	var r := MB.fight(s, [a, avatar, b], "rivermarch", "", 8)
	var bears := MB.fighters_of(r.log, "war_bear")
	var c1: Array = MB.events(r.log, "cast", 1)
	assert_eq(c1.size(), 4, "four Adepts cast")
	assert_true(c1.all(func(e): return e.spell == "sunlance" and e.targets == [bears[0]]),
		"all four lances go into the first War Bear (%d hp, the highest maximum; the Great Thornmane has more but is a ruler)" % int(r.log.fighters[bears[0]].max_hp))
	assert_true(c1.all(func(e): return int(e.damage) == lance), "%d sure damage each" % lance)
	var wound: Array = MB.events(r.log, "wound", 1).filter(func(e): return int(e.f) == bears[0])
	assert_true(not wound.is_empty() and int(wound[0].from) - int(wound[0].to) >= 4 * lance, "the bear took the four lances")
	assert_true(Array(wound[0].by).slice(0, 4) == c1.map(func(e): return int(e.by)), "its wound names the casters first")
	_checks(r.log, r.result.report, "four lances")
	# The first bear hurt down to 2 lances' worth: two lances finish it, then the rest go into the second bear.
	b.units[0].current_hp = 2 * lance
	r = MB.fight(s, [a, avatar, b], "rivermarch", "", 8)
	c1 = MB.events(r.log, "cast", 1)
	assert_eq(c1.map(func(e): return int(e.targets[0])), [bears[0], bears[0], bears[1], bears[1]], "the most hurt first, never overkill")
	# Nothing but the ruler in reach: then the ruler, with his spell resistance.
	var lone := MB.army(s, CLANS, "beasts-4", "rivermarch", [])
	var reg_only := MB.fight(s, [a, avatar, lone], "rivermarch", "", 8)
	var c := MB.events(reg_only.log, "cast", 1)
	var ruler_id: int = reg_only.log.fighters.filter(func(f): return f.role == "ruler")[0].id
	assert_true(c.all(func(e): return e.targets == [ruler_id]), "with nothing else in reach, the ruler")
	var rank := RulerRules.ability_rank(3)
	assert_eq(int(c[0].damage), maxi(1, lance - rank / MagicData.RULER_RESIST), "spell resistance at rank %d" % rank)


func test_bloodbolt_finishes_the_weakest_and_never_overkills() -> void:
	var s := MB.with_nodes(MB.game(), CLANS, ["bloodbolt"])
	MB.spellbook(s, CLANS, MagicData.SPELLBOOK[CLANS], ["briar_snare"])
	var bolt := _value("bloodbolt", "value")
	var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "spearmen", "knights"])
	a.units[1].current_hp = 2
	a.units[2].current_hp = 4
	var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers", "tuskers", "shamans", "shamans", "shamans"])
	var r := MB.fight(s, [a, b], "rivermarch", "", 9)
	var spears := MB.fighters_of(r.log, "spearmen")
	var c1: Array = MB.events(r.log, "cast", 1)
	assert_eq(c1.map(func(e): return e.spell), ["bloodbolt", "bloodbolt", "bloodbolt"], "three Bloodbolts")
	assert_eq(c1.map(func(e): return int(e.targets[0])), [spears[1], spears[2], spears[0]],
		"the fewest hp left first (2, then 4), each skipped once it is going to die, then the next weakest")
	assert_true(c1.all(func(e): return int(e.damage) == bolt and int(e.self) == _value("bloodbolt", "bleed")), "5 damage, 2 bled")
	_checks(r.log, r.result.report, "Bloodbolts")


func test_spell_resistance_by_rank() -> void:
	var lance := _value("sunlance", "value")
	for kept in [0, 3, 6, 9]:
		var rank := RulerRules.ability_rank(kept)
		var want := maxi(1, lance - rank / MagicData.RULER_RESIST)
		assert_eq(AutoBattleResolver.spell_resistance(rank), rank / MagicData.RULER_RESIST, "rank %d resists %d" % [rank, rank / MagicData.RULER_RESIST])
		var s := MB.with_nodes(MB.game({CLANS: MB.AVATAR}), CROWN, ["sunlance"])
		var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "adepts"])
		var avatar := MB.ruler_at(s, CLANS, "rivermarch", kept)
		var r := MB.fight(s, [a, avatar], "rivermarch", "", 1)
		var c: Dictionary = MB.events(r.log, "cast", 1)[0]
		assert_eq(int(c.damage), want, "rank %d: Sunlance %d - %d = %d" % [rank, lance, rank / MagicData.RULER_RESIST, want])
		assert_eq(int(c.get("resist", -1)), lance - want, "rank %d: the cast records the resistance" % rank)
	assert_eq(AutoBattleResolver.spell_resistance(1), 0)
	assert_eq(AutoBattleResolver.spell_resistance(4), 2)


# --- Shield of Law and Briar Snare --------------------------------------------------------------------

func test_shield_of_law_is_a_field_spell_and_keeps_every_defense_on_the_breakpoints() -> void:
	var s := MB.with_nodes(MB.game(), CROWN, ["shield_of_law", "crown_drillyard", "crown_charters", "crown_oath_forge", "crown_living_iron"])
	var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "spearmen", "knights", "knights", "adepts", "adepts"])
	var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers", "tuskers", "tuskers", "fangthrowers"])
	var covered := 0
	for where in ["rivermarch", "crownkeep", "thornvale", "highcrag"]:
		a.location = where
		b.location = where
		for defender in ["", CROWN, CLANS]:
			var r := MB.fight(s, [a, b], where, defender, 3)
			var p := s.find_province(where)
			var ground: bool = defender == CROWN and (p.has_fort or AutoBattleResolver.TERRAIN[p.terrain].defense > 0)
			var shields := MB.events(r.log, "cast").filter(func(e): return e.spell == "shield_of_law")
			assert_eq(shields.is_empty(), ground, "%s, defender '%s': Shield of Law %s" % [where, defender, "skipped" if ground else "cast"])
			for e in MB.events(r.log, "attack"):
				var parts: Dictionary = e.defense.parts
				if not parts.has(SHIELD):
					continue
				covered += 1
				assert_false(parts.has("terrain") or parts.has("fort"), "never on a unit with a terrain or fort bonus")
				assert_eq(int(parts[SHIELD]), _value("shield_of_law", "value"), "+4 defense")
				assert_true(int(e.defense.value) % 4 <= 1, "a covered defense is 4k or 4k+1: %d" % int(e.defense.value))
			_checks(r.log, r.result.report, "%s/%s" % [where, defender])
	assert_true(covered > 0, "some attacks hit covered units")


func test_briar_snare_covers_more_in_a_forest() -> void:
	var s := MB.with_nodes(MB.game(), CLANS, ["briar_snare"])
	var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "spearmen",
		"spearmen", "spearmen", "spearmen", "spearmen"])
	var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers", "tuskers", "tuskers", "shamans"])
	var cases := [["rivermarch", "province", _value("briar_snare", "count")], ["thornvale", "province", _value("briar_snare", "forest_count")],
		["rivermarch|greenglade", "border", _value("briar_snare", "count")]]
	for c in cases:
		a.location = String(c[0]).get_slice("|", 0)
		b.location = a.location
		var r := MB.fight(s, [a, b], c[0], "", 2, c[1])
		var snare: Dictionary = MB.events(r.log, "cast", 1)[0]
		assert_eq(snare.targets.size(), int(c[2]), "%s: Briar Snare covers %d" % [c[0], int(c[2])])
		assert_eq(snare.part, {"stat": "attack", "value": _value("briar_snare", "value")}, "-2 attack")
		for e in MB.events(r.log, "attack", 1):
			assert_eq(e.attack.parts.has(SNARE), Array(snare.targets).has(int(e.by)), "%s: exactly the snared attack with the part" % c[0])
		_checks(r.log, r.result.report, String(c[0]))


# --- the bleed ------------------------------------------------------------------------------------------

func test_the_bleed_never_below_1_not_in_the_break_check_and_closed_after_the_battle() -> void:
	var s := MB.with_nodes(MB.game(), CLANS, ["bloodbolt"])
	var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "knights"])
	var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers", "tuskers", "tuskers", "shamans"])
	var bleed := _value("bloodbolt", "bleed")
	var min_hp := _value("bloodbolt", "min_caster_hp")
	var found := false
	for sd in range(1, 30):
		var r := MB.fight(s, [a, b], "rivermarch", "", sd)
		var lg: Dictionary = r.log
		var shaman: int = MB.fighters_of(lg, "shamans")[0]
		var bled := 0
		var hp := int(lg.fighters[shaman].hp)
		for e in lg.events:
			if e.t == "cast" and int(e.by) == shaman:
				assert_true(hp >= min_hp, "Bloodbolt needs %d hp: it had %d" % [min_hp, hp])
			if e.t == "wound" and int(e.f) == shaman:
				bled += int(e.get("bled", 0))
				hp = int(e.to)
				if int(e.get("bled", 0)) > 0:
					assert_true(int(e.to) >= 1, "the bleed never takes it below 1")
					assert_true(Array(e.by).has(shaman), "its wound names the Shaman itself")
			if e.t == "morale" and String(lg.sides[int(e.side)].faction) == CLANS:
				var want := roundi(100.0 * (int(lg.sides[int(e.side)].hp_start) - int(e.hp) - int(e.get("bled", 0))) / int(lg.sides[int(e.side)].hp_start))
				assert_eq(int(e.lost_pct), want, "the break check leaves out the %d hp bled" % int(e.get("bled", 0)))
				assert_eq(int(e.get("bled", 0)), bled, "the morale check records the bleed so far")
		if bled >= 2 * bleed:
			found = true
			_checks(lg, r.result.report, "the bleed, seed %d" % sd)
			break
	assert_true(found, "a battle where the Shaman bled twice")
	# resolve_battle closes the bleed for a winning side's standing caster.
	for sd in range(1, 40):
		var s2 := MB.with_nodes(MB.game(), CLANS, ["bloodbolt"])
		var a2 := MB.army(s2, CROWN, "kingdom-1", "rivermarch", ["spearmen"])
		var b2 := MB.army(s2, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers", "tuskers", "shamans"])
		var res := MB.resolve(s2, [a2, b2], "rivermarch", "", sd)
		var closed := MB.events(res.log, "bleed_closed")
		if res.winner != CLANS or closed.is_empty():
			continue
		var shaman_unit: Unit = b2.units[3]
		var row: Array = closed[0].closed[0]
		assert_eq(int(row[2]), shaman_unit.current_hp, "the Shaman's hp after the battle are the closed wound's")
		assert_true(int(row[2]) > int(row[1]), "the bled hp came back")
		assert_true(res.report.has("bleed_closed"), "the report says so")
		assert_true(res.report.lines.any(func(l): return String(l).contains("bled")), "a report line says so")
		assert_eq(BattleLog.final_hp(res.log)[int(row[0])], int(row[2]), "final_hp applies it")
		_checks(res.log, res.report, "closed, seed %d" % sd)
		return
	fail("no seed closed a bleed")


# --- Blood Moon, blessings and curses ----------------------------------------------------------------

func test_blood_moon_heals_back_a_quarter_the_larger_share_never_above_max_less_1_and_not_in_a_ward() -> void:
	var share := _value("blood_moon", "share")
	var found := 0
	for sd in range(1, 25):
		var s := MB.with_nodes(MB.game(), CLANS, PACT)
		MB.enchant(s, "blood_moon", CLANS)
		var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "spearmen", "knights", "knights"])
		var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers", "bloodsworn", "fangthrowers"])
		var r := MB.fight(s, [a, b], "rivermarch", "", sd)
		var lg: Dictionary = r.log
		var clans := 0 if lg.sides[0].faction == CLANS else 1
		assert_true(lg.sides[clans].enchantments.any(func(e): return e.ritual == "blood_moon"), "the side's enchantments list the moon")
		var dealt := {}
		for e in lg.events:
			if e.t == "round":
				dealt = {}
			elif e.t == "attack" and e.hit:
				dealt[int(e.by)] = int(dealt.get(int(e.by), 0)) + int(e.damage)
			elif e.t == "heal":
				var f: Dictionary = lg.fighters[int(e.f)]
				var d := int(dealt.get(int(e.f), 0))
				assert_eq(int(f.side), clans, "only the moon's side heals back")
				assert_true(int(e.to) <= int(f.max_hp) - 1, "never above maximum - 1: %d of %d" % [int(e.to), int(f.max_hp)])
				if f.trait == AutoBattleResolver.LIFEDRINKER:
					assert_eq(String(e.get("trait", "")), AutoBattleResolver.LIFEDRINKER, "Lifedrinker's share is the larger")
					assert_eq(int(e.to), mini(int(f.max_hp) - 1, int(e.from) + ceili(float(d) / AutoBattleResolver.LIFEDRINK_DIVISOR)), "half, rounded up")
				else:
					assert_eq(String(e.get("spell", "")), "blood_moon", "the moon's share")
					assert_eq(int(e.to), mini(int(f.max_hp) - 1, int(e.from) + d / share), "a quarter, rounded down")
					found += 1
		_checks(lg, r.result.report, "the moon, seed %d" % sd)
		# The same battle in a province the Crown has warded is outside the moon.
		MB.enchant(s, "sanctum_ward", CROWN, "rivermarch")
		var w := MB.fight(s, [a, b], "rivermarch", "", sd)
		assert_false(MB.events(w.log, "heal").any(func(e): return e.get("spell", "") == "blood_moon"), "a rival ward keeps the moon out")
	assert_true(found > 0, "the moon healed someone back")


func test_dawn_blessing_gives_a_side_with_half_its_fighters_blessed_1_morale() -> void:
	var s := MB.game()
	var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "spearmen", "knights"])
	var c := MB.army(s, CROWN, "kingdom-3", "rivermarch", ["spearmen", "spearmen", "spearmen", "spearmen"])
	var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers", "tuskers", "tuskers"])
	MB.enchant(s, "dawn_blessing", CROWN, "rivermarch", ["kingdom-1"])
	var morale := _value("dawn_blessing", "morale")
	var r := MB.fight(s, [a, c, b], "rivermarch", "", 1)
	var crown := 0 if r.log.sides[0].faction == CROWN else 1
	assert_eq(int(r.log.sides[crown].start_morale.parts.get("spell_dawn_blessing", 0)), morale, "4 of 8 fighters blessed: half, so +1 morale")
	assert_true(MB.events(r.log, "morale").filter(func(e): return int(e.side) == crown).all(func(e): return int(e.parts.get("spell_dawn_blessing", 0)) == morale),
		"for the whole battle")
	_checks(r.log, r.result.report, "blessed")
	var d := MB.army(s, CROWN, "kingdom-4", "rivermarch", ["spearmen"])
	r = MB.fight(s, [a, c, d, b], "rivermarch", "", 1)
	assert_false(r.log.sides[crown].start_morale.parts.has("spell_dawn_blessing"), "4 of 9: under half, no morale")


func test_a_cursed_side_heals_from_nothing_no_feast_no_lifedrinker_no_moon() -> void:
	# Feast of Victory: the Crown wins in a province a Clans curse lies on.
	var checked := false
	for sd in range(1, 30):
		var runs := []
		for cursed in [false, true]:
			var s := MB.game({}, {CROWN: [RulerRules.FEAST_OF_VICTORY]})
			if cursed:
				MB.enchant(s, "bloodrot", CLANS, "rivermarch")
			var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["knights", "knights", "knights", "spearmen", "spearmen"])
			var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["fangthrowers", "fangthrowers"])
			runs.append(MB.resolve(s, [a, b], "rivermarch", "", sd))
		if not runs[0].report.has("feast"):
			continue
		assert_false(runs[1].report.has("feast"), "a cursed winner doesn't feast")
		assert_true(MB.events(runs[1].log, "feast").is_empty(), "no feast event")
		assert_true(runs[1].log.sides.any(func(x): return x.enchantments.any(func(e): return e.ritual == "bloodrot")), "the log says the side is cursed")
		checked = true
		break
	assert_true(checked, "a battle the Crown won and feasted after")
	# Lifedrinker and the moon in a cursed province.
	var s2 := MB.with_nodes(MB.game(), CLANS, PACT)
	MB.enchant(s2, "blood_moon", CLANS)
	MB.enchant(s2, "bloodrot", CROWN, "rivermarch")
	var a2 := MB.army(s2, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "knights"])
	var b2 := MB.army(s2, CLANS, "beasts-2", "rivermarch", ["bloodsworn", "bloodsworn", "tuskers"])
	for sd in range(1, 10):
		var r2 := MB.fight(s2, [a2, b2], "rivermarch", "", sd)
		assert_true(MB.events(r2.log, "heal").is_empty(), "seed %d: cursed fighters heal back nothing" % sd)
	# A border battle is in no province, so nobody in it is cursed.
	assert_true(MagicRules.can_heal(s2, CLANS, ""), "a border battle")


# --- mastery --------------------------------------------------------------------------------------------

func test_mastery_scales_each_spell() -> void:
	# The Regent's Sunlance at each rank: 4 + (rank - 1), at most +3.
	var lance := _value("sunlance", "value")
	for kept in [0, 3, 6, 9]:
		var s := MB.game({CROWN: MB.REGENT})
		var reg := MB.ruler_at(s, CROWN, "rivermarch", kept)
		var front := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen"])
		var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers"])
		var r := MB.fight(s, [reg, front, b], "rivermarch", "", 1)
		var bonus := mini(RulerRules.ability_rank(kept) - 1, int(MagicData.MASTERY.cap))
		var c: Dictionary = MB.events(r.log, "cast", 1)[0]
		assert_eq(int(c.bonus), bonus, "kept %d: mastery +%d" % [kept, bonus])
		assert_eq(int(c.damage), lance + bonus, "kept %d: Sunlance %d" % [kept, lance + bonus])
		assert_eq(int(c.bonus), int(MagicRules.mastery_bonus(s, CROWN, "sun", MagicRules.RULER).value), "the bonus is MagicRules'")
	# The mastery nodes: Briar Snare +1 unit, Bloodbolt +1 damage, Shield of Law +1 unit.
	var s2 := MB.with_nodes(MB.game(), CLANS, ["briar_snare", "call_the_pack", "wild_mastery", "bloodbolt", "bloodrot", "blood_mastery"])
	var a := MB.army(s2, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "spearmen",
		"spearmen", "spearmen", "spearmen", "spearmen"])
	var b2 := MB.army(s2, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers", "tuskers", "tuskers", "shamans", "shamans"])
	var r2 := MB.fight(s2, [a, b2], "rivermarch", "", 1)
	var casts: Array = MB.events(r2.log, "cast", 1)
	assert_eq(casts[0].targets.size(), _value("briar_snare", "count") + 1, "Wild Mastery: one more unit snared")
	assert_eq(int(casts[1].damage), _value("bloodbolt", "value") + 1, "Blood Mastery: one more damage")
	assert_eq(r2.log.fighters[int(casts[0].by)].mastery, {"wild": 1, "blood": 1}, "the log records each school's mastery")
	var s3 := MB.with_nodes(MB.game(), CROWN, ["shield_of_law", "sanctum_ward", "law_mastery"])
	var a3 := MB.army(s3, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "spearmen",
		"spearmen", "spearmen", "adepts"])
	var b3 := MB.army(s3, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers", "tuskers"])
	var r3 := MB.fight(s3, [a3, b3], "rivermarch", "", 1)
	assert_eq(MB.events(r3.log, "cast", 1)[0].targets.size(), _value("shield_of_law", "count") + 1, "Law Mastery: one more unit shielded")


# --- the hard line: no caster, no change -----------------------------------------------------------------

## The parts of a log that the rolls decide: every attack's target and hit roll, the end, the RNG state after.
func _draws(lg: Dictionary) -> Array:
	var out := [lg.rng.after]
	for e in lg.events:
		if e.t == "attack":
			out.append([int(e.by), int(e.to), int(e.pool), int(e.pick), int(e.roll), e.hit, int(e.damage)])
		elif e.t == "end":
			out.append([int(e.rounds), int(e.winner), String(e.how)])
	return out


func test_a_battle_with_no_caster_draws_exactly_what_it_drew_before() -> void:
	var names := Scenarios.NAMES.filter(func(n): return n != "biggest")
	for name in names:
		var d := Scenarios.direct(name)
		if d.has("error"):
			continue
		var sd := maxi(1, Scenarios.fixture_seed(name))
		var st: GameState = d.ctx.state
		st.magic = false
		var before := AutoBattleResolver.fight(d.sides, d.ctx, SeededRNG.new(sd), true)
		st.magic = true
		var after := AutoBattleResolver.fight(d.sides, d.ctx, SeededRNG.new(sd), true)
		st.magic = false
		assert_eq(_draws(after.log), _draws(before.log), "%s: the same draws with magic on and no caster" % name)
		assert_eq(after.result.report.why, before.result.report.why, "%s: the same why" % name)
		assert_true(after.log.get("magic", false) and not before.log.has("magic"), "%s: only the magic log says magic" % name)
	# A magic game with paths, no caster on the field: the same as the paths game.
	for sd in [1, 2, 3]:
		var s := MB.game()
		var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "crossbowmen", "knights", "knight_captain"])
		var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers", "fangthrowers", "war_bear", "warchief"])
		var on := MB.fight(s, [a, b], "rivermarch", CROWN, sd)
		s.magic = false
		var off := MB.fight(s, [a, b], "rivermarch", CROWN, sd)
		assert_eq(_draws(on.log), _draws(off.log), "seed %d: the same draws" % sd)
		assert_eq(on.result.report.summary, off.result.report.summary, "seed %d: the same summary" % sd)
		assert_true(on.result.report.sides[0].has("spells_cast"), "a magic report carries spells_cast")
		assert_false(off.result.report.sides[0].has("spells_cast"), "a report without magic doesn't")


# --- odds and the why -----------------------------------------------------------------------------------

func test_forecast_battle_odds_changes_when_a_spell_is_researched() -> void:
	var s := MB.game()
	MB.army(s, CROWN, "kingdom-1", "highcrag", ["spearmen", "spearmen", "spearmen", "spearmen", "adepts", "adepts", "adepts"])
	MB.army(s, CLANS, "beasts-2", "thornvale", ["tuskers", "tuskers", "tuskers", "war_bear"])
	var before := Forecast.battle_odds(s, CROWN, ["kingdom-1"], "thornvale")
	var known := MB.with_nodes(s, CROWN, ["sunlance"])
	var after := Forecast.battle_odds(known, CROWN, ["kingdom-1"], "thornvale")
	assert_true(before.ok and after.ok, "both forecast")
	assert_ne(after.text, before.text, "the forecast changes once Sunlance is known")
	assert_true(after.text.contains("Sunlance"), "and names the spell: %s" % after.text)
	assert_false(before.text.contains("Sunlance"), "before, no spell is named")


## The first seed in 1..60 on which the battle's top "why" is `factor_id` for the winner `winner`.
func _top(make: Callable, factor_id: String, winner: String) -> Dictionary:
	for sd in range(1, 61):
		var r: Dictionary = make.call(sd)
		var factors: Array = r.result.report.factors
		if not factors.is_empty() and factors[0].id == factor_id and r.result.winner == winner:
			r["seed"] = sd
			return r
	return {}


func test_a_constructed_battle_names_each_spell_as_its_top_why() -> void:
	var cases := {
		LANCE: [func(sd):
			var s := MB.with_nodes(MB.game(), CROWN, ["sunlance"])
			var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "spearmen",
				"adepts", "adepts", "adepts", "adepts", "adepts", "adepts"])
			var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["war_bear", "war_bear", "war_bear", "tuskers", "tuskers"])
			return [MB.fight(s, [a, b], "rivermarch", "", sd), CROWN]],
		SHIELD: [func(sd):
			var s := MB.with_nodes(MB.game(), CROWN, ["shield_of_law"])
			var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "spearmen",
				"spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "adepts", "adepts"])
			var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers", "tuskers", "tuskers", "tuskers", "tuskers", "tuskers", "tuskers"])
			return [MB.fight(s, [a, b], "rivermarch", "", sd), CROWN]],
		BURST: [func(sd):
			# A one-round effect: it leads only where little else adds up (a crossbow line behind one Knight, no Shield Wall).
			var s := MB.with_nodes(MB.game(), CROWN, ["crown_drillyard", "crown_charters", "crown_oath_dawn", "sunlance", "dawn_blessing", "sunburst"])
			MB.spellbook(s, CROWN, MagicData.SPELLBOOK[CROWN], ["sunlance"])
			var crown := ["knights", "adepts", "adepts", "adepts"]
			for k in 10:
				crown.append("crossbowmen")
			var clans := []
			for k in 14:
				clans.append("fangthrowers")
			var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", crown)
			var b := MB.army(s, CLANS, "beasts-2", "rivermarch", clans)
			return [MB.fight(s, [a, b], "rivermarch", "", sd), CROWN]],
		SNARE: [func(sd):
			var s := MB.with_nodes(MB.game(), CLANS, ["briar_snare"])
			var a := MB.army(s, CROWN, "kingdom-1", "thornvale", ["knights", "knights", "knights", "knights", "knights"])
			var b := MB.army(s, CLANS, "beasts-2", "thornvale", ["tuskers", "tuskers", "tuskers", "tuskers", "tuskers", "tuskers",
				"shamans", "shamans", "shamans"])
			return [MB.fight(s, [a, b], "thornvale", "", sd), CLANS]],
		BOLT: [func(sd):
			var s := MB.with_nodes(MB.game(), CLANS, ["bloodbolt"])
			MB.spellbook(s, CLANS, MagicData.SPELLBOOK[CLANS], ["briar_snare"])
			var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "spearmen",
				"crossbowmen", "crossbowmen"])
			var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers", "tuskers", "tuskers", "tuskers", "shamans", "shamans",
				"shamans", "shamans", "shamans"])
			return [MB.fight(s, [a, b], "rivermarch", "", sd), CLANS]],
	}
	for id in cases:
		var make: Callable = cases[id][0]
		var r := _top(func(sd): return make.call(sd)[0], id, String(make.call(1)[1]))
		assert_false(r.is_empty(), "a battle whose top why is %s" % id)
		if r.is_empty():
			continue
		var f: Dictionary = r.result.report.factors[0]
		assert_eq(String(f.get("codex", "")), id, "%s links its codex entry" % id)
		assert_true(String(f.text).contains(MagicRules.spell_name(id.trim_prefix("spell_"))), "%s's clause names the spell: %s" % [id, f.text])
		_checks(r.log, r.result.report, id)
	# The Regent's own Sunlance.
	var reg := _top(func(sd):
		var s := MB.game({CROWN: MB.REGENT})
		var rg := MB.ruler_at(s, CROWN, "rivermarch", 9)
		var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "spearmen", "spearmen"])
		var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["war_bear", "war_bear", "fangthrowers"])
		return MB.fight(s, [rg, a, b], "rivermarch", "", sd), LANCE, CROWN)
	assert_false(reg.is_empty(), "the Regent's Sunlance is a battle's top why")
	if not reg.is_empty():
		assert_true(String(reg.result.report.factors[0].text).contains("Ever-Regent"), "and names him: %s" % reg.result.report.factors[0].text)


func test_free_holds_garrisons_fight_spells_like_anyone() -> void:
	var r := Scenarios.run("magic_free_holds", maxi(1, Scenarios.find_seed("magic_free_holds")))
	assert_eq(r.errors, [], "the scenario fights")
	if not r.errors.is_empty():
		return
	var lg: Dictionary = r.log
	var holds := -1
	for sd in lg.sides:
		if String(sd.faction) == IndependentData.FACTION_ID:
			holds = int(sd.index)
	assert_true(holds >= 0, "the Free Holds are a side")
	assert_eq(lg.sides[holds].casters, [], "they have no casters")
	assert_true(MB.events(lg, "cast").any(func(e): return Array(e.targets).any(func(id): return int(lg.fighters[int(id)].side) == holds)),
		"spells land on the garrison")
	_checks(lg, r.report, "the Free Holds")
