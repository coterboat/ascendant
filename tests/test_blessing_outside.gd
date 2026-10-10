extends "res://tests/test_case.gd"
## ARM-1 (design/ARM1_SPLIT_MERGE.md §2.1): a blessing stays with its army, fighter by fighter. A fighter that joins a blessed
## army after the casting (a muster, a commander moved in, a recruit) is marked outside the blessing (UnitStatus
## OUTSIDE_BLESSING) and the blessing skips it: healing (the same budget to the rest), the half-blessed morale, the battle
## log and report, and the words; the marker clears when its unit leaves, when the blessing ends or restarts, and on a re-cast.

const Kit := preload("res://tests/muster_test_kit.gd")
const MB := preload("res://tests/magic_battle_fixtures.gd")
const FORGE := ["crown_drillyard", "crown_charters", "crown_oath_forge", "shield_of_law", "sanctum_ward", "bastion", "sunlance", "dawn_blessing"]
const CROWN := "kingdom"
const CLANS := "beasts"
const OUT := UnitStatus.OUTSIDE_BLESSING


func _magic_game() -> GameState:
	var s := AscensionRules.with_nodes(Kit.game("magic"), CROWN, FORGE)
	for f in s.factions:
		f.gold = 200
	return s


func _budget(s: GameState, bonus: int = 0) -> int:
	return int(MagicRules.spell_numbers("dawn_blessing", bonus).value)


func _valid(s: GameState, what: String) -> void:
	var errors := []
	assert_true(s.validate(errors), "%s: the state is valid: %s" % [what, errors])


# --- the marker goes on at every join ----------------------------------------------------------------------

func test_units_that_join_a_blessed_army_by_a_muster_are_marked_outside_it() -> void:
	var s := Kit.game("magic")
	var a := Kit.crown(s)
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen", "spearmen"], "knight_captain")
	var e1 := Kit.bless(s, CROWN, "crownkeep")  # the blessing lists kingdom-1, the ruler's army and b
	var plain := Kit.army(s, CROWN, "crownkeep", ["knights"])  # raised after the casting: not listed
	var r := MusterRules.apply(s, CROWN, MusterOrder.transfer(plain.id, a.id, [0]))
	assert_true(r.ok)
	assert_true(a.units.back().has_status(OUT, e1), "a unit that joined the blessed army is outside its blessing")
	assert_eq(r.info.outside, [{"army": a.id, "blessing": e1, "count": 1, "types": ["knights"]}])
	# A commander moved in by a transfer or a swap is marked too.
	var r2 := MusterRules.apply(s, CROWN, MusterOrder.swap(a.id, b.id))
	assert_true(r2.ok)
	assert_true(a.commander.has_status(OUT, e1) and b.commander.has_status(OUT, e1), "both commanders joined a blessed army")
	assert_eq(r2.info.outside.size(), 2)
	_valid(s, "after the musters")


func test_units_that_leave_a_blessed_army_lose_its_blessing_and_a_new_army_has_none() -> void:
	var s := Kit.game("magic")
	var a := Kit.crown(s)
	var e1 := Kit.bless(s, CROWN, "crownkeep")
	var r := MusterRules.apply(s, CROWN, MusterOrder.transfer(a.id, "", [0, 1]))
	assert_true(r.ok)
	var split := s.find_army(r.info.to)
	assert_true(MagicRules.blessing_of(s, split.id).is_empty(), "the new army is not in the blessing's list")
	assert_eq(r.info.outside, [], "and nothing in it is marked: it is not under any blessing")
	for u in split.units:
		assert_eq(u.statuses, [], "they simply have no blessing now")
	assert_true(MagicRules.covers(MagicRules._enchantment(s, e1), a.id, a.units[0]), "what stayed is still covered")
	_valid(s, "after the split")


func test_multi_hop_a_unit_blessed_in_a_loses_it_in_b_and_is_outside_cs() -> void:
	var s := Kit.game("magic")
	var a := Kit.crown(s)
	var e1 := Kit.bless(s, CROWN, "crownkeep")  # a, and the ruler's army
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen"])  # plain: raised after
	# A second blessing on c alone (cast from c's own province then c moved here is a long story: write it by hand).
	var c := Kit.army(s, CROWN, "crownkeep", ["spearmen"])
	var e2 := String(MagicRules._begin(s, CROWN, "dawn_blessing", "blessing", "crownkeep", 1, 6, 0, [c.id]).id)
	var unit_id: String = a.units[2].type.id  # the Knights
	assert_true(MusterRules.apply(s, CROWN, MusterOrder.transfer(a.id, b.id, [2])).ok, "A to B")
	var moved: Unit = b.units.back()
	assert_eq(moved.type.id, unit_id)
	assert_eq(moved.statuses, [], "in plain B it carries no marker: it has no blessing, and loses A's")
	assert_true(MagicRules.blessing_of(s, b.id).is_empty())
	assert_true(MusterRules.apply(s, CROWN, MusterOrder.transfer(b.id, c.id, [1])).ok, "on from B to C")
	var moved_on: Unit = c.units.back()
	assert_eq(moved_on.type.id, unit_id)
	assert_true(moved_on.has_status(OUT, e2) and not moved_on.has_status(OUT, e1), "sent on to blessed C it is outside C's blessing, and only that")
	assert_false(MagicRules.covers(MagicRules._enchantment(s, e2), c.id, moved_on))
	_valid(s, "after both hops")


func test_a_unit_that_moves_between_two_armies_of_one_blessing_is_outside_it() -> void:
	var s := Kit.game("magic")
	var a := Kit.crown(s)
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen"])
	var e1 := Kit.bless(s, CROWN, "crownkeep")  # lists a, b and the ruler's army
	assert_true(MusterRules.apply(s, CROWN, MusterOrder.transfer(a.id, b.id, [0])).ok)
	assert_true(b.units.back().has_status(OUT, e1), "joining B is joining a blessed army: it is outside, though A's blessing covered it")


func test_the_plan_and_the_turn_agree_on_the_markers() -> void:
	var s := Kit.game("magic")
	var a := Kit.crown(s)
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen", "spearmen"])
	Kit.bless(s, CROWN, "crownkeep")
	var plain := Kit.army(s, CROWN, "crownkeep", ["knights"])
	var orders := [MusterOrder.transfer(plain.id, a.id, [0]), MusterOrder.transfer(a.id, b.id, [], true)]
	var planned := RulerRules.state_after_orders(s, CROWN, orders)
	var r := Kit.resolve(s, {CROWN: orders})
	assert_eq(Kit.events(r, "order_rejected"), [])
	for army in planned.armies:
		var real: Army = r.new_state.find_army(army.id)
		if real == null:
			continue
		var want := UnitStatus.army_fighters(army).map(func(u): return u.statuses)
		var got := UnitStatus.army_fighters(real).map(func(u): return u.statuses)
		assert_eq(got, want, "%s: the same markers on the same fighters in the plan and the turn" % army.id)
	_valid(r.new_state, "after the turn")


# --- recruits -----------------------------------------------------------------------------------------------

func test_a_recruit_that_joins_a_blessed_army_is_marked_outside_it() -> void:
	var s := Kit.game("magic")
	var a := Kit.crown(s)
	var e1 := Kit.bless(s, CROWN, "crownkeep")
	var r := Kit.resolve(s, {CROWN: [RecruitOrder.new("spearmen")]})
	var recruited := Kit.events(r, "recruited")
	assert_eq(recruited.size(), 1)
	var joined: Army = r.new_state.find_army(a.id)
	assert_eq(joined.units.size(), a.units.size() + 1, "it joined the first army at the capital, the blessed one")
	assert_true(joined.units.back().has_status(OUT, e1), "and is outside its blessing")
	assert_eq(recruited[0].numbers.outside_blessing, e1)
	assert_true(String(recruited[0].text).contains("aren't under its Dawn Blessing"), recruited[0].text)
	var line := TurnReportText.line(recruited[0], r.events, r.new_state, CROWN)
	assert_true(line.contains("It isn't under its Dawn Blessing") or line.contains("They aren't under its Dawn Blessing"), line)
	_valid(r.new_state, "after the recruit")
	# A commander recruited into a blessed army without one is outside it too.
	var s2 := Kit.game("magic")
	var a2 := Kit.crown(s2)
	a2.commander = null
	var e2 := Kit.bless(s2, CROWN, "crownkeep")
	var r2 := Kit.resolve(s2, {CROWN: [RecruitOrder.new("knight_captain")]})
	assert_true(r2.new_state.find_army(a2.id).commander.has_status(OUT, e2), "a commander who joins a blessed army is outside it")


func test_a_recruit_that_forms_a_new_army_or_joins_a_plain_one_is_not_marked() -> void:
	var s := Kit.game("magic")
	var a := Kit.crown(s)
	Kit.bless(s, CROWN, "crownkeep")
	# The blessed army marches out; the recruit forms a new army at the capital, which is under no blessing.
	var r := Kit.resolve(s, {CROWN: [MoveOrder.new(a.id, "westwatch"), RecruitOrder.new("spearmen")]})
	var created: Dictionary = Kit.events(r, "recruited")[0]
	assert_true(created.numbers.new_army)
	assert_false(created.numbers.has("outside_blessing"), "a recruit that formed an army joined nothing")
	for army in r.new_state.armies:
		for u in UnitStatus.army_fighters(army):
			assert_eq(u.statuses, [], "no marker anywhere in %s" % army.id)
	# Without magic nothing changes: the recruit's event is the one it always was.
	var plain := Kit.resolve(Kit.game(), {CROWN: [RecruitOrder.new("spearmen")]})
	assert_false(Kit.events(plain, "recruited")[0].numbers.has("outside_blessing"))


# --- healing ----------------------------------------------------------------------------------------------------

func test_healing_skips_the_outside_fighters_and_the_budget_goes_to_the_rest() -> void:
	var s := Kit.game("magic")
	var a := Kit.crown(s)
	var e1 := Kit.bless(s, CROWN, "crownkeep")
	RulerRules.ruler_army(s, CROWN).location = "rivermarch"  # the ruler stays out of it
	var fighters := UnitStatus.army_fighters(a)
	var max_hp: Array = fighters.map(func(u): return RulerRules.unit_max_hp(s, u))
	for i in fighters.size():
		fighters[i].current_hp = 1
	# The first two units are outside the blessing: they joined after the casting.
	fighters[0].add_status(OUT, e1)
	fighters[1].add_status(OUT, e1)
	var budget := _budget(s)
	var step := MagicRules.enchantment_step(s, 1)
	var row: Dictionary = step.healed.filter(func(h): return h.army == a.id)[0]
	assert_eq(fighters[0].current_hp, 1, "an outside fighter is not healed")
	assert_eq(fighters[1].current_hp, 1, "neither is the other")
	var got := 0
	for i in range(2, fighters.size()):
		got += fighters[i].current_hp - 1
	assert_eq(got, mini(budget, max_hp.slice(2).reduce(func(t, m): return t + m - 1, 0)), "the whole budget went to the covered fighters")
	assert_eq(row.total, got)
	assert_eq(row.outside, 2)
	assert_eq(row.fighters, fighters.size())
	for h in row.healed:
		assert_true(int(h.index) >= 2, "the rows name the fighters' own places (%d)" % int(h.index))
	var text := MagicRules.healed_text(s, row)
	assert_true(text.contains("blesses %d of the army's %d fighters; 2 joined after it was cast" % [fighters.size() - 2, fighters.size()]), text)
	_valid(s, "after the healing")


func test_a_fully_covered_army_heals_exactly_as_before() -> void:
	var one := Kit.game("magic")
	var two := Kit.game("magic")
	for s in [one, two]:
		Kit.bless(s, CROWN, "crownkeep")
		RulerRules.ruler_army(s, CROWN).location = "rivermarch"
		for u in UnitStatus.army_fighters(Kit.crown(s)):
			u.current_hp = 2
	var s1 := MagicRules.enchantment_step(one, 1)
	var s2 := MagicRules.enchantment_step(two, 1)
	assert_eq(JSON.stringify(s1.healed), JSON.stringify(s2.healed))
	assert_false(s1.healed[0].has("outside"), "a row without outside fighters carries no new keys")


# --- battle ---------------------------------------------------------------------------------------------------------

func _blessed_fight(outside: int, with_commander_outside: bool = false) -> Dictionary:
	var s := MB.game()
	var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "knights"])
	var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers", "tuskers", "tuskers"])
	var e := MB.enchant(s, "dawn_blessing", CROWN, "rivermarch", ["kingdom-1"])
	for i in outside:
		a.units[i].add_status(OUT, String(e.id))
	if with_commander_outside:
		a.commander = Unit.new(s.find_faction(CROWN).commander_type, CROWN)
		a.commander.add_status(OUT, String(e.id))
	var r := MB.fight(s, [a, b], "rivermarch", "", 1)
	return r


func _crown_side(r: Dictionary) -> Dictionary:
	for side in r.log.sides:
		if side.faction == CROWN:
			return side
	return {}


func test_half_blessed_morale_counts_fighters_not_army_ids() -> void:
	var morale := int(MagicData.SPELLS.dawn_blessing.get("morale", 1))
	# 8 fighters: 4 blessed is half (morale), 5 outside leaves 3 (none).
	var half := _blessed_fight(4)
	assert_eq(int(_crown_side(half).start_morale.parts.get("spell_dawn_blessing", 0)), morale, "4 of 8 fighters blessed: half, so +1 morale")
	var under := _blessed_fight(5)
	assert_false(_crown_side(under).start_morale.parts.has("spell_dawn_blessing"), "3 of 8 blessed: under half, no morale")
	var none := _blessed_fight(0)
	assert_eq(int(_crown_side(none).start_morale.parts.get("spell_dawn_blessing", 0)), morale, "all 8: morale")


func test_the_battle_log_and_report_count_the_blessed_fighters() -> void:
	var under := _blessed_fight(5)
	var log_line: String = _crown_side(under).enchantments.filter(func(e): return e.ritual == "dawn_blessing")[0].effect
	assert_true(log_line.contains("only 3 of 8 fighters blessed"), log_line)
	var half := _blessed_fight(4)
	log_line = _crown_side(half).enchantments.filter(func(e): return e.ritual == "dawn_blessing")[0].effect
	assert_true(log_line.contains("4 of 8 fighters blessed"), log_line)
	# A commander outside the blessing is not counted either: 9 fighters, 4 outside regulars + the commander = 5 outside.
	var with_cmd := _blessed_fight(4, true)
	log_line = _crown_side(with_cmd).enchantments.filter(func(e): return e.ritual == "dawn_blessing")[0].effect
	assert_true(log_line.contains("only 4 of 9 fighters blessed"), log_line)
	assert_false(_crown_side(with_cmd).start_morale.parts.has("spell_dawn_blessing"))
	# The report agrees with the log.
	for r in [under, half, with_cmd]:
		assert_eq(BattleLog.validate(r.log), [], "the log is valid")
		assert_eq(BattleLog.cross_check(r.log, r.result.report), [], "and agrees with the report")


func test_a_battle_with_no_outside_fighters_is_what_it_was() -> void:
	var s := MB.game()
	var a := MB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "knights"])
	var b := MB.army(s, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers"])
	MB.enchant(s, "dawn_blessing", CROWN, "rivermarch", ["kingdom-1"])
	var with_listing := MB.fight(s, [a, b], "rivermarch", "", 3)
	s.enchantments.clear()
	var without := MB.fight(s, [a, b], "rivermarch", "", 3)
	assert_ne(JSON.stringify(with_listing.log), JSON.stringify(without.log), "the blessing matters")
	assert_eq(int(_crown_side(with_listing).start_morale.parts.get("spell_dawn_blessing", 0)), int(MagicData.SPELLS.dawn_blessing.morale))


# --- the markers clear --------------------------------------------------------------------------------------------

func test_the_markers_clear_when_the_blessing_runs_out() -> void:
	var s := Kit.game("magic")
	var a := Kit.crown(s)
	var e1 := Kit.bless(s, CROWN, "crownkeep", 3)
	a.units[0].add_status(OUT, e1)
	a.commander.add_status(OUT, e1)
	_valid(s, "marked")
	var step := MagicRules.enchantment_step(s, 3)
	assert_eq(step.ended.size(), 1, "the blessing ends through turn 3")
	assert_eq(step.ended[0].cause, "time")
	assert_eq(a.units[0].statuses, [], "no marker outlives it")
	assert_eq(a.commander.statuses, [])
	_valid(s, "after it ended")


func test_the_markers_clear_when_the_last_army_leaves_the_blessing() -> void:
	var s := Kit.game("magic")
	var a := Kit.crown(s)
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen"])
	var e1 := Kit.bless(s, CROWN, "crownkeep")
	# Both armies merge into the plain army c raised later; the blessing is left with no army to heal.
	var c := Kit.army(s, CROWN, "crownkeep", ["spearmen"])
	RulerRules.ruler_army(s, CROWN).location = "rivermarch"
	MagicRules.forget_army(s, RulerRules.ruler_army(s, CROWN).id)
	assert_true(MusterRules.apply(s, CROWN, MusterOrder.merge(a.id, c.id)).ok)
	assert_true(MusterRules.apply(s, CROWN, MusterOrder.merge(b.id, c.id)).ok)
	assert_true(MagicRules._enchantment(s, e1).armies.is_empty(), "the blessing no longer lists any army")
	_valid(s, "with an empty blessing")
	var step := MagicRules.enchantment_step(s, 1)
	assert_eq(step.ended.map(func(e): return e.cause), ["no_armies"])
	for u in UnitStatus.army_fighters(c):
		assert_eq(u.statuses, [], "nothing of the ended blessing is left on the units")
	_valid(s, "after")


func test_a_cast_that_takes_an_army_off_a_blessing_clears_its_markers() -> void:
	# The Crown's first army is blessed, with a marked recruit; a new army joins the province and a fresh cast covers both: a
	# different set of armies, so a NEW blessing; the old one is left with nothing and ends here, and its markers go with it.
	var s := _magic_game()
	var a := Kit.crown(s)
	a.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(CROWN), "adepts", s), CROWN))
	var e1 := Kit.bless(s, CROWN, "crownkeep")
	RulerRules.ruler_army(s, CROWN).location = "rivermarch"
	MagicRules.forget_army(s, RulerRules.ruler_army(s, CROWN).id)
	a.units[0].add_status(OUT, e1)
	var fresh := Kit.army(s, CROWN, "crownkeep", ["spearmen"])
	var r := Kit.resolve(s, {CROWN: [CastOrder.new("dawn_blessing", a.id, "crownkeep")]})
	assert_eq(Kit.events(r, "order_rejected"), [], "the cast goes ahead: %s" % [r.events.filter(func(e): return e.type == "order_rejected").map(func(e): return e.text)])
	var blessings: Array = r.new_state.enchantments.filter(func(e): return e.kind == "blessing")
	assert_eq(blessings.size(), 1, "one blessing now")
	assert_ne(String(blessings[0].id), e1, "a new one, on the two armies")
	assert_eq(blessings[0].armies, [a.id, fresh.id])
	assert_eq(r.new_state.find_army(a.id).units[0].statuses, [], "the old blessing's marker is gone: the new casting covers everyone")
	_valid(r.new_state, "after the replacement")


func test_a_recast_keeps_the_id_and_clears_the_markers() -> void:
	var s := _magic_game()
	var a := Kit.crown(s)
	a.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(CROWN), "adepts", s), CROWN))
	var ruler := RulerRules.ruler_army(s, CROWN)
	ruler.location = "rivermarch"
	var e1 := Kit.bless(s, CROWN, "crownkeep")  # a alone: the ruler stands elsewhere
	assert_eq(MagicRules._enchantment(s, e1).armies, [a.id])
	a.units[0].add_status(OUT, e1)
	a.units[1].add_status(OUT, e1)
	a.commander.add_status(OUT, e1)
	var r := Kit.resolve(s, {CROWN: [CastOrder.new("dawn_blessing", a.id, "crownkeep")]})
	assert_eq(Kit.events(r, "order_rejected"), [])
	var blessings: Array = r.new_state.enchantments.filter(func(e): return e.kind == "blessing")
	assert_eq(blessings.size(), 1)
	assert_eq(String(blessings[0].id), e1, "a restart keeps the id")
	for u in UnitStatus.army_fighters(r.new_state.find_army(a.id)):
		assert_eq(u.statuses, [], "the new casting covers everyone, so nothing is outside it")
	_valid(r.new_state, "after the re-cast")


func test_a_ruler_and_its_blessed_army_keep_working_as_before() -> void:
	# The ruler's army is listed in a blessing like any other, and never carries a marker.
	var s := Kit.game("magic")
	var e1 := Kit.bless(s, CROWN, "crownkeep")
	var ruler := RulerRules.ruler_army(s, CROWN)
	ruler.ruler.current_hp = 1
	var step := MagicRules.enchantment_step(s, 1)
	assert_true(step.healed.any(func(h): return h.army == ruler.id), "the ruler heals under the blessing")
	assert_eq(ruler.ruler.statuses, [])
	assert_true(MagicRules.covers(MagicRules._enchantment(s, e1), ruler.id, ruler.ruler))


func test_words_give_covered_and_total_counts() -> void:
	var s := Kit.game("magic")
	var a := Kit.crown(s)
	var e1 := Kit.bless(s, CROWN, "crownkeep")
	var cov := MagicRules.blessing_coverage(s, a)
	assert_eq([cov.covered, cov.total, cov.outside], [4, 4, 0])
	assert_eq(MagicRules.coverage_words(cov), "all 4 fighters")
	a.units[0].add_status(OUT, e1)
	a.commander.add_status(OUT, e1)
	cov = MagicRules.blessing_coverage(s, a)
	assert_eq([cov.covered, cov.total, cov.outside], [2, 4, 2])
	assert_eq(MagicRules.coverage_words(cov), "2 of 4 fighters; 2 joined after it was cast")
	var plain := Kit.army(s, CROWN, "westwatch", ["spearmen"])
	assert_eq(MagicRules.coverage_words(MagicRules.blessing_coverage(s, plain)), "", "an army with no blessing has no words")
