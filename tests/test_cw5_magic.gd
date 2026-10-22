extends "res://tests/test_case.gd"
## CW-5 (#256, design/CANDLEWAKE.md §7): the Candlewake's magic, the Wick and Wax schools, behind their preview. Draw the Warmth
## (a bolt with no self-bleed), Kindle (the new "flame" ritual: one army of yours +1 flame now, never above 3), Bonfire Night (a
## global whose "flame_bonus" warms every battle, battles only), Wax Skin (a shield), Raise the Snuffed (a pack through CW-0's
## summons from data) and Candlemass (a blessing on one army, with Dawn Blessing's morale). Half-Death casts only the Wick,
## Mother Tallow only Wax's rituals. Every number comes from MagicData's PREVIEW_ tables and the rules' constants.

const CROWN := "kingdom"
const CLANS := "beasts"
const WAKE := "candlewake"
## The Oath of the Snuffed and its two ordinary nodes (a legal research order), and the Oath of the Kept's.
const SNUFFED := ["wake_thicker_tallow", "wake_brighter_flare", "wake_oath_snuffed"]
const KEPT := ["wake_thicker_tallow", "wake_sitting_up_early", "wake_oath_kept"]
const WICK := ["draw_the_warmth", "kindle"]
const WAX := ["wax_skin", "raise_the_snuffed"]


# --- helpers ----------------------------------------------------------------------------------------

## A magic game of the Crown and the Candlewake (`ruler` theirs), with `nodes` researched by the Candlewake, 200 gold each. The
## Candlewake's start army is taken off the map, so each test's armies are the only ones of theirs but the ruler's.
func _game(nodes: Array = [], ruler: String = "half_death", flags: Dictionary = {}, crown: Variant = "warrior_king") -> GameState:
	var errors := []
	var f := {"magic": true}
	f.merge(flags)
	var s := GameState.create(23, [CROWN, WAKE], f, {WAKE: {"ruler": ruler, "mandates": []}, CROWN: crown}, errors)
	assert_eq(errors, [], "the magic game starts")
	if not nodes.is_empty():
		s = AscensionRules.with_nodes(s, WAKE, nodes)
		assert_true(s != null, "the nodes apply: %s" % [nodes])
		var bad := []
		assert_true(s.validate(bad), "%s is a legal order: %s" % [nodes, bad])
	for fa in s.factions:
		fa.gold = 200
	for a in s.armies.duplicate():
		if a.owner == WAKE and a.ruler == null:
			s.armies.erase(a)
	return s


## A new army of `fid` at `at` holding units of these type ids at full hp (roster units, mages, or summoned creatures).
func _army(s: GameState, fid: String, at: String, types: Array, flame: int = -2) -> Army:
	var f := s.find_faction(fid)
	var a := Army.new()
	a.id = s.new_army_id(fid)
	a.owner = fid
	a.location = at
	for t in types:
		var ut: UnitType = MagicRules.summon_type(String(t)) if not MagicRules.summon_data(String(t)).is_empty() \
			else TurnResolver.recruitable_type(f, String(t), s)
		assert_true(ut != null, "%s can field %s" % [fid, t])
		var u := Unit.new(ut, fid)
		u.current_hp = RulerRules.unit_max_hp(s, u)
		a.units.append(u)
	WickRules.light(s, a)
	if flame >= -1:
		a.flame = flame
	s.armies.append(a)
	return a


func _capital(s: GameState, fid: String = WAKE) -> String:
	return s.find_faction(fid).capital


func _ruler(s: GameState, fid: String = WAKE) -> Army:
	return RulerRules.ruler_army(s, fid)


## A province `steps` moves from `from`, the lowest id among them.
func _at(s: GameState, from: String, steps: int) -> String:
	var d := MagicRules.distances(s, from)
	var ids: Array = d.keys().filter(func(pid): return int(d[pid]) == steps)
	ids.sort()
	return String(ids[0]) if not ids.is_empty() else ""


func _resolve(s: GameState, orders: Dictionary = {}) -> Dictionary:
	var r := TurnResolver.resolve(s, orders, TurnResolver.seed_for_turn(s))
	assert_true(r.new_state != null, "the turn resolves: %s" % [r.get("errors", [])])
	if r.new_state != null:
		var errors := []
		assert_true(r.new_state.validate(errors), "the state after the turn is valid: %s" % [errors])
	return r


func _of(r: Dictionary, type: String) -> Array:
	return r.events.filter(func(e): return String(e.type) == type)


func _sp(id: String) -> Dictionary:
	return MagicData.PREVIEW_SPELLS[id]


# --- the tables, behind the preview -----------------------------------------------------------------------

func test_the_candlewakes_magic_is_in_the_preview_tables_and_reads_through_the_rules() -> void:
	for id in MagicData.PREVIEW_SPELLS:
		assert_false(MagicData.SPELLS.has(id), "%s is not in the shipped spells" % id)
		assert_eq(MagicRules.spell_data(id), MagicData.PREVIEW_SPELLS[id], "%s reads from the preview" % id)
	for id in MagicData.PREVIEW_SCHOOLS:
		assert_false(MagicData.SCHOOLS.has(id), "%s is not a shipped school" % id)
	for table in [MagicData.SUMMONS, MagicData.MAGES, MagicData.RULER_MAGIC, MagicData.SPELLBOOK, MagicData.ARCANA]:
		for id in table:
			assert_false(String(id) in ["snuffed", WAKE, "half_death", "mother_tallow"], "%s stays out of the shipped tables" % id)
	assert_eq(MagicRules.schools(WAKE), ["wick", "wax"])
	assert_eq(MagicRules.schools(CROWN), MagicData.FACTION_SCHOOLS[CROWN], "the Crown's schools are as they were")
	assert_eq(MagicRules.arcana_ids(WAKE), MagicData.PREVIEW_ARCANA[WAKE].map(func(n): return String(n.id)))
	assert_eq(MagicRules.default_spellbook(WAKE), ["draw_the_warmth", "wax_skin"], "§7: Draw the Warmth, then Wax Skin")
	assert_eq(String(MagicRules.mage_data(WAKE).id), "chandlers_apprentices")
	assert_eq(String(MagicRules.summon_data("snuffed").faction), WAKE)
	var snuffed := MagicRules.summon_type("snuffed")
	assert_eq([snuffed.hp, snuffed.attack, snuffed.defense, snuffed.morale, snuffed.trait_id], [7, 9, 8, 8, AutoBattleResolver.PALL], "§7: 7/9/8/8, Pall")
	assert_true(snuffed.summoned)
	# Tier III needs the aligned Oath, and nothing else from the path (§7).
	for n in MagicData.PREVIEW_ARCANA[WAKE]:
		if String(n.tier) == "III":
			var school: Dictionary = MagicData.PREVIEW_SCHOOLS[String(n.school)]
			assert_eq(String(n.oath_branch), String(school.aligned_branch), "%s opens with its school's side" % n.id)
			var oath := "wake_oath_snuffed" if String(school.aligned_branch) == "red_wake" else "wake_oath_kept"
			assert_true(Array(n.requires).has(oath), "%s needs %s" % [n.id, oath])
	# Greater workings never scale (M5 §8): Bonfire Night and Candlemass have no per_bonus.
	assert_eq(_sp("bonfire_night").per_bonus, {})
	assert_eq(_sp("candlemass").per_bonus, {})


func test_magic_opens_for_the_candlewake_seat() -> void:
	assert_eq(GameState.system_problems(WAKE, {"magic": true}), [], "the Candlewake can play with magic")
	var s := _game()
	assert_true(s.magic)
	var roster: Array = s.find_faction(WAKE).unit_types.map(func(ut): return ut.id)
	assert_true(roster.has("chandlers_apprentices"), "the mage is on the roster from turn 1")
	var mage := MagicRules.mage_type(WAKE)
	assert_false(MagicRules.mage_gate_reason(s, WAKE, mage).is_empty(), "but can't be recruited before a spell is known")
	assert_true(MagicRules.battle_spells(s, WAKE, MagicRules.RULER).has("draw_the_warmth"), "Half-Death's own spell from turn 1")
	assert_false(MagicRules.knows_a_spell(s, WAKE), "Half-Death's own Draw the Warmth doesn't count")


# --- casters: Half-Death the Wick, Mother Tallow Wax --------------------------------------------------------

func test_half_death_casts_only_the_wick_and_mother_tallow_only_waxs_rituals() -> void:
	var s := _game(WICK + WAX)
	assert_eq(MagicRules.battle_spells(s, WAKE, MagicRules.RULER), ["draw_the_warmth"], "never Wax Skin, though it is known")
	assert_eq(MagicRules.battle_spells(s, WAKE, MagicRules.MAGE), ["draw_the_warmth", "wax_skin"], "a mage casts both")
	var ruler := _ruler(s)
	assert_eq(String(MagicRules.caster_for(s, WAKE, ruler, "kindle").get("kind", "")), MagicRules.RULER)
	assert_true(MagicRules.caster_for(s, WAKE, ruler, "raise_the_snuffed").is_empty(), "Half-Death raises no Snuffed")
	assert_eq(MagicRules.ruler_line("half_death", s.find_faction(WAKE).kept_power).contains("every Wick spell"), true,
		"its line names its school, not the Candlewake's: %s" % MagicRules.ruler_line("half_death", s.find_faction(WAKE).kept_power))
	var t := _game(WICK + WAX, "mother_tallow")
	var her := _ruler(t)
	assert_eq(MagicRules.battle_spells(t, WAKE, MagicRules.RULER), [], "Mother Tallow never casts in battle")
	assert_eq(String(MagicRules.caster_for(t, WAKE, her, "raise_the_snuffed").get("kind", "")), MagicRules.RULER)
	assert_true(MagicRules.caster_for(t, WAKE, her, "kindle").is_empty(), "nor the Wick's rituals")
	var line := MagicRules.ruler_line("mother_tallow", t.find_faction(WAKE).kept_power)
	var n := MagicRules.spell_numbers("raise_the_snuffed", RulerRules.ability_rank(t.find_faction(WAKE).kept_power) - 1)
	assert_eq(line, "Magic: casts Wax rituals, up to %d Snuffed (%d gold) once you research Raise the Snuffed." % [int(n.count),
		int(n.count) * int(_sp("raise_the_snuffed").cost)])


func test_ruler_mastery_counts_only_its_own_school_and_caps() -> void:
	var s := _game(SNUFFED + ["wake_red_wake"] + WICK + ["wick_mastery"] + WAX)
	var f := s.find_faction(WAKE)
	for kept in [0, 4, 9, 20]:
		f.kept_power = kept
		var rank := RulerRules.ability_rank(kept)
		var wick := MagicRules.mastery_bonus(s, WAKE, "wick", MagicRules.RULER)
		var raw := rank - 1 + int(MagicData.MASTERY.transformation) + int(MagicData.MASTERY.node)
		assert_eq(int(wick.value), mini(raw, int(MagicData.MASTERY.cap)), "kept %d: rank, the Red Wake and Wick Mastery, capped" % kept)
		assert_eq(int(MagicRules.mastery_bonus(s, WAKE, "wax", MagicRules.RULER).value), 0, "kept %d: no Wax from Half-Death's rank" % kept)
	var mage := MagicRules.mastery_bonus(s, WAKE, "wick", MagicRules.MAGE)
	assert_eq(int(mage.value), int(MagicData.MASTERY.mage) + int(MagicData.MASTERY.transformation) + int(MagicData.MASTERY.node))
	assert_eq(int(MagicRules.spell_numbers("draw_the_warmth", int(mage.value)).value),
		int(_sp("draw_the_warmth").value) + int(mage.value) * int(_sp("draw_the_warmth").per_bonus.value))
	assert_eq(int(MagicRules.mastery_bonus(s, WAKE, "wax", MagicRules.MAGE).value), int(MagicData.MASTERY.mage), "the Red Wake adds nothing to Wax")


func test_the_aligned_oath_opens_each_greater_working_and_the_other_closes_it() -> void:
	var red := _game(SNUFFED + WICK + WAX)
	assert_eq(String(AscensionRules.node_state(red, WAKE, "bonfire_night").state), AscensionRules.AVAILABLE, "the Oath alone opens it")
	assert_eq(String(AscensionRules.node_state(red, WAKE, "candlemass").state), AscensionRules.CLOSED, "the other Oath closes it")
	var gold := _game(KEPT + WICK + WAX)
	assert_eq(String(AscensionRules.node_state(gold, WAKE, "candlemass").state), AscensionRules.AVAILABLE)
	assert_eq(String(AscensionRules.node_state(gold, WAKE, "bonfire_night").state), AscensionRules.CLOSED)


func test_the_spellbook_defaults_saves_and_round_trips() -> void:
	var s := _game(WICK + WAX)
	var f := s.find_faction(WAKE)
	assert_eq(f.spellbook, {}, "the data default is stored as {}")
	assert_eq(MagicRules.spellbook(s, WAKE).order, ["draw_the_warmth", "wax_skin"])
	assert_eq(MagicRules.check_spellbook(s, WAKE, SpellbookOrder.new(["wax_skin", "draw_the_warmth"], ["draw_the_warmth"])), {})
	MagicRules.set_spellbook(s, WAKE, SpellbookOrder.new(["wax_skin", "draw_the_warmth"], ["draw_the_warmth"]))
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(MagicRules.spellbook(back, WAKE).order, ["wax_skin", "draw_the_warmth"])
	assert_eq(MagicRules.spellbook(back, WAKE).off, ["draw_the_warmth"])
	MagicRules.set_spellbook(s, WAKE, SpellbookOrder.new(["draw_the_warmth", "wax_skin"], []))
	assert_eq(f.spellbook, {}, "back to the default stores {}")


# --- Kindle ---------------------------------------------------------------------------------------------------

func test_kindle_warms_one_army_now_and_the_wick_step_says_so() -> void:
	var s := _game(WICK)
	var home := _capital(s)
	assert_true(WickRules.harbour(s, WAKE, home), "the capital is a harbour (its fort and its Deep Wake)")
	var cold := _army(s, WAKE, home, ["wickwardens", "wickwardens"], 1)
	var r := _resolve(s, {WAKE: [CastOrder.new("kindle", _ruler(s).id, home)]})
	var cast := _of(r, "ritual_cast")
	assert_eq(cast.size(), 1)
	var k: Dictionary = cast[0].numbers.kindled
	assert_eq(k, {"army": cold.id, "from": 1, "to": 1 + int(_sp("kindle").value)}, "+1 flame now")
	assert_true(Array(cast[0].armies).has(cold.id), "the event names the army it warmed")
	assert_true(String(cast[0].text).contains("burned at flame 2, from 1"), cast[0].text)
	var after: Army = r.new_state.find_army(cold.id)
	assert_eq(after.flame, WickRules.next_flame(s, WAKE, 2, false, false, true, false), "it keeps it in a harbour")
	var lines := _of(r, "flame_changed").filter(func(e): return String(e.numbers.army) == cold.id)
	assert_eq(lines.size(), 1)
	assert_eq(String(lines[0].numbers.why), "kindled", "the Wick step's line says why it moved")
	assert_eq(int(_of(r, "ritual_cast")[0].numbers.gold), int(_sp("kindle").cost), "Kindle costs its price")


func test_kindle_never_goes_above_three_never_lowers_a_four_and_skips_what_it_cant_warm() -> void:
	var s := _game(WICK)
	var home := _capital(s)
	var ruler := _ruler(s)
	var top := WickRules.base_cap(WAKE)
	assert_eq(MagicRules.check_cast(s, WAKE, CastOrder.new("kindle", ruler.id, home)).get("code", ""), "no_army_fits",
		"Half-Death's own army carries no flame")
	var hot := _army(s, WAKE, home, ["wickwardens"], top)
	var warm := _army(s, WAKE, home, ["wickwardens"], top - 1)
	var snuffed := _army(s, WAKE, home, ["snuffed", "snuffed"], 0)
	# Unnamed: the lowest-numbered army there that it fits (the hot one is skipped).
	var fx := MagicRules.ritual_effect(s.deep_copy([]), WAKE, CastOrder.new("kindle", ruler.id, home))
	assert_eq(fx.kindled, {"army": warm.id, "from": top - 1, "to": top})
	# Named: that army, or a plain refusal.
	var named := MagicRules.check_cast(s, WAKE, CastOrder.new("kindle", ruler.id, home, CastOrder.GOLD, 0, hot.id))
	assert_eq(String(named.get("code", "")), "target_army_unfit")
	assert_true(String(named.reason).contains("never raises a flame above %d" % top), named.reason)
	var summons := MagicRules.check_cast(s, WAKE, CastOrder.new("kindle", ruler.id, home, CastOrder.GOLD, 0, snuffed.id))
	assert_true(String(summons.get("reason", "")).contains("no regulars"), "an army of Snuffed alone has no regulars to warm")
	assert_eq(MagicRules.check_cast(s, WAKE, CastOrder.new("kindle", ruler.id, home, CastOrder.GOLD, 0, warm.id)), {})
	# The Red Wake's flame 4 stays 4: Kindle never lowers a flame.
	var four := Army.new()
	four.owner = WAKE
	four.flame = 4
	assert_eq(MagicRules.kindled_flame("kindle", four), 4)
	var one := Army.new()
	one.owner = WAKE
	one.flame = 0
	assert_eq(MagicRules.kindled_flame("kindle", one), 1)
	# A named army on another ritual is refused.
	var other := MagicRules.check_cast(s, WAKE, CastOrder.new("far_sight", ruler.id, home, CastOrder.GOLD, 0, warm.id))
	assert_eq(String(other.get("code", "")), "no_target_army")


func test_kindle_reaches_two_provinces_on_any_land_and_is_checked_again_when_it_resolves() -> void:
	var s := _game(WICK)
	var home := _capital(s)
	var ruler := _ruler(s)
	var reach := int(_sp("kindle").range)
	var near := _at(s, home, reach)
	var far := _at(s, home, reach + 1)
	var there := _army(s, WAKE, near, ["wickwardens"], 1)
	s.find_province(near).owner = CROWN  # the Crown's land: Kindle lands on the army, not the land
	assert_eq(MagicRules.check_cast(s, WAKE, CastOrder.new("kindle", ruler.id, near)), {})
	_army(s, WAKE, far, ["wickwardens"], 1)
	assert_eq(String(MagicRules.check_cast(s, WAKE, CastOrder.new("kindle", ruler.id, far)).get("code", "")), "out_of_range")
	var order := CastOrder.new("kindle", ruler.id, near, CastOrder.GOLD, 0, there.id)
	var r := _resolve(s, {WAKE: [order]})
	assert_eq(_of(r, "ritual_fell"), [], "the land's owner is told nothing: it fell on no land")
	assert_eq(int(_of(r, "ritual_cast")[0].numbers.kindled.to), 2)
	# Checked again as it resolves: a named army no longer there fails the cast, and nothing is paid.
	var t := s.deep_copy([])
	t.armies.erase(t.find_army(there.id))
	var fx := MagicRules.ritual_effect(t, WAKE, order)
	assert_eq(String(fx.outcome), MagicRules.FAILED)
	assert_eq(String(fx.code), "unknown_target_army")
	assert_eq(int(fx.gold), 0)


func test_kindles_forecast_and_the_orders_flame_line_count_it() -> void:
	var s := _game(WICK)
	var home := _capital(s)
	var cold := _army(s, WAKE, home, ["wickwardens"], 1)
	var order := CastOrder.new("kindle", _ruler(s).id, home)
	var fc := MagicRules.forecast_ritual(s, WAKE, order, [order])
	assert_true(bool(fc.ok), fc.get("reason", ""))
	assert_eq(fc.effect.kindled, {"army": cold.id, "from": 1, "to": 2})
	assert_true(String(fc.text).contains("will burn at flame 2, from 1, before this turn's battles"), fc.text)
	assert_true(String(fc.effect_text).contains("to flame 2 (from 1)"), fc.effect_text)
	var line: Dictionary = Forecast.wick(s, WAKE, [order]).filter(func(x): return String(x.army) == cold.id)[0]
	assert_true(String(line.text).contains("flame 1, 2 after Kindle → 3 if it wins"), line.text)
	# The forecast equals the result.
	var r := _resolve(s, {WAKE: [order]})
	assert_eq(_of(r, "ritual_cast")[0].numbers.kindled, fc.effect.kindled)
	# Saved orders keep the named army, and only those carry the key.
	var named := CastOrder.new("kindle", _ruler(s).id, home, CastOrder.GOLD, 0, cold.id)
	assert_false(order.to_dict().has("target_army"))
	assert_eq(String(OrderBook.order_from_dict(named.to_dict()).target_army), cold.id)


func test_kindle_comes_after_blessings_and_before_summons() -> void:
	var kinds := MagicRules.KIND_ORDER
	assert_eq(kinds.find("flame"), kinds.find("blessing") + 1)
	assert_eq(kinds.find("summon"), kinds.find("flame") + 1)
	var queue := MagicRules.ritual_queue({WAKE: [CastOrder.new("raise_the_snuffed", "w-1", "x", CastOrder.GOLD, 3),
		CastOrder.new("kindle", "w-2", "y")], CROWN: [CastOrder.new("dawn_blessing", "k-1", "z"), CastOrder.new("sanctum_ward", "k-2", "z")]})
	assert_eq(queue.map(func(q): return String(q.order.ritual)), ["sanctum_ward", "dawn_blessing", "kindle", "raise_the_snuffed"])


# --- Bonfire Night ----------------------------------------------------------------------------------------------

func test_bonfire_night_warms_every_battle_through_t_plus_2_and_never_moves_a_flame() -> void:
	var s := _game(SNUFFED + WICK + ["bonfire_night"])
	var home := _capital(s)
	var lit := _army(s, WAKE, home, ["wickwardens"], 1)
	var r := _resolve(s, {WAKE: [CastOrder.new("bonfire_night", _ruler(s).id, "")]})
	var turn := s.current_turn + 1
	var t: GameState = r.new_state
	var e := MagicRules.flame_global(t, WAKE)
	assert_false(e.is_empty(), "it is up")
	assert_eq(int(e.until_turn), turn + int(_sp("bonfire_night").duration), "through turn T + 2")
	assert_true(bool(_of(r, "ritual_cast")[0].numbers.global), "a global: announced to everyone")
	var army := t.find_army(lit.id)
	var bonus := int(_sp("bonfire_night").flame_bonus)
	assert_eq(WickRules.battle_flame(t, army), mini(army.flame + bonus, WickRules.cap(t, WAKE)), "battles fight hotter")
	assert_eq(army.flame, WickRules.next_flame(s, WAKE, 1, false, false, true, false), "the flame itself didn't move")
	army.flame = WickRules.base_cap(WAKE)
	assert_eq(WickRules.battle_flame(t, army), WickRules.base_cap(WAKE), "never above the cap")
	# It ends after turn T + 2's battles.
	var state := t
	for _i in int(_sp("bonfire_night").duration):
		state = _resolve(state).new_state
	assert_true(MagicRules.flame_global(state, WAKE).is_empty(), "gone after turn T + 2")
	assert_eq(MagicRules.flame_bonus(state, WAKE), 0)


func test_bonfire_night_reaches_the_red_wakes_four_and_the_battle_says_so() -> void:
	var s := _game(SNUFFED + ["wake_red_wake"] + WICK + ["bonfire_night"])
	MagicRules._begin(s, WAKE, "bonfire_night", "global", "", s.current_turn + 1, s.current_turn + 3, 0, [])
	var field := _at(s, _capital(s), 1)
	var wake := _army(s, WAKE, field, ["wickwardens", "wickwardens", "gleaners"], 3)
	assert_eq(WickRules.battle_flame(s, wake), 4, "3 + 1 reaches the Red Wake's 4")
	var foe := _army(s, CROWN, field, ["spearmen", "spearmen", "crossbowmen"])
	var r := AutoBattleResolver.resolve(wake, foe, s.find_province(field), SeededRNG.new(5), s, true)
	assert_eq(BattleLog.validate(r.log), [], "the log validates")
	var side: Dictionary = r.log.sides.filter(func(x): return String(x.faction) == WAKE)[0]
	var seen := 0
	for e in r.log.events:
		if String(e.t) == "attack" and int(r.log.fighters[int(e.by)].side) == int(side.index) and String(r.log.fighters[int(e.by)].role) == "unit":
			seen += 1
			assert_eq(int(e.attack.parts.get(AutoBattleResolver.FLAME, 0)), 4 - 1, "a regular fights at flame 4's +3")
	assert_true(seen > 0, "the regulars attacked")
	assert_true(Array(side.get("enchantments", [])).any(func(x): return String(x.ritual) == "bonfire_night"), "the log names it")
	var wick: Array = Array(r.report.all_factors).filter(func(f): return String(f.get("id", "")) == AutoBattleResolver.FLAME)
	assert_false(wick.is_empty(), "Wick is a factor")
	assert_true(String(wick[0].text).contains("(with Bonfire Night's +%d)" % int(_sp("bonfire_night").flame_bonus)), wick[0].text)
	assert_true(String(wick[0].brief).contains("Bonfire Night"), wick[0].brief)


func test_only_one_global_is_up_at_a_time() -> void:
	var s := _game(SNUFFED + WICK + ["bonfire_night"])
	var ruler := _ruler(s)
	MagicRules._begin(s, CROWN, "blood_moon", "global", "", s.current_turn + 1, s.current_turn + 2, 0, [])
	assert_eq(String(MagicRules.check_target(s, WAKE, "bonfire_night", ruler, "").get("code", "")), "global_up", "the moon blocks the bonfire")
	var gold := s.find_faction(WAKE).gold
	var r := _resolve(s, {WAKE: [CastOrder.new("bonfire_night", ruler.id, "")]})
	assert_eq(_of(r, "ritual_cast"), [], "refused")
	assert_eq(r.new_state.find_faction(WAKE).gold >= gold, true, "and nothing paid for it")
	var t := _game(SNUFFED + WICK + ["bonfire_night"])
	MagicRules._begin(t, WAKE, "bonfire_night", "global", "", t.current_turn + 1, t.current_turn + 2, 0, [])
	var clans := Army.new()
	clans.owner = CLANS
	clans.location = _capital(t, CROWN)
	assert_eq(String(MagicRules.check_target(t, CLANS, "blood_moon", clans, "").get("code", "")), "global_up", "the bonfire blocks the moon")
	assert_eq(MagicRules.check_target(t, WAKE, "bonfire_night", _ruler(t), ""), {}, "and may be cast again, restarting it")


func test_bonfire_nights_words() -> void:
	var s := _game(SNUFFED + WICK + ["bonfire_night"])
	var order := CastOrder.new("bonfire_night", _ruler(s).id, "")
	var fc := MagicRules.forecast_ritual(s, WAKE, order, [order])
	assert_true(String(fc.text).contains("regulars fight every battle as if 1 flame hotter"), fc.text)
	assert_true(String(fc.text).contains("Battles only"), fc.text)
	assert_eq(String(fc.effect_text), "Your regulars fight every battle 1 flame hotter, through turn %d." % (s.current_turn + 3))


# --- Candlemass ---------------------------------------------------------------------------------------------------

func test_candlemass_blesses_one_army_heals_it_and_lifts_morale() -> void:
	var s := _game(KEPT + WAX + ["candlemass"], "mother_tallow")
	var home := _capital(s)
	var first := _army(s, WAKE, home, ["wickwardens", "wickwardens"], 1)
	var second := _army(s, WAKE, home, ["wickwardens"], 1)
	var her := _ruler(s)
	var r := _resolve(s, {WAKE: [CastOrder.new("candlemass", her.id, home)]})
	var began := _of(r, "enchantment_began")
	assert_eq(began.size(), 1)
	assert_eq(Array(began[0].numbers.armies), [first.id], "one army: the lowest-numbered there")
	var e: Dictionary = r.new_state.enchantments.filter(func(x): return String(x.ritual) == "candlemass")[0]
	assert_eq(int(e.until_turn), s.current_turn + 1 + int(_sp("candlemass").duration), "through T + 4")
	# Named: the second army instead.
	var t := _game(KEPT + WAX + ["candlemass"], "mother_tallow")
	_army(t, WAKE, _capital(t), ["wickwardens"], 1)
	var b := _army(t, WAKE, _capital(t), ["wickwardens"], 1)
	var r2 := _resolve(t, {WAKE: [CastOrder.new("candlemass", _ruler(t).id, _capital(t), CastOrder.GOLD, 0, b.id)]})
	assert_eq(Array(_of(r2, "enchantment_began")[0].numbers.armies), [b.id])
	# It heals its value a turn (one hit point at a time), and mastery never changes it.
	var wounded: Army = r.new_state.find_army(first.id)
	for u in wounded.units:
		u.current_hp = 1
	var r3 := _resolve(r.new_state)
	var healed := _of(r3, "blessing_healed").filter(func(x): return String(x.numbers.army) == first.id)
	assert_eq(healed.size(), 1)
	assert_eq(int(healed[0].numbers.budget), int(_sp("candlemass").value))
	assert_eq(int(MagicRules.spell_numbers("candlemass", 3).value), int(_sp("candlemass").value), "a greater working never scales")
	# Battle morale, Dawn Blessing's rule by the spell's own "morale", under its own name.
	var field := _at(r.new_state, home, 1)
	var st: GameState = r.new_state
	var blessed := st.find_army(first.id)
	blessed.location = field
	var foe := _army(st, CROWN, field, ["spearmen", "spearmen", "spearmen", "crossbowmen"])
	var battle := AutoBattleResolver.resolve(blessed, foe, st.find_province(field), SeededRNG.new(9), st, true)
	assert_eq(BattleLog.validate(battle.log), [], "the log validates")
	var side: Dictionary = battle.log.sides.filter(func(x): return String(x.faction) == WAKE)[0]
	var entry: Array = Array(side.get("enchantments", [])).filter(func(x): return String(x.ritual) == "candlemass")
	assert_eq(entry.size(), 1, "the log names Candlemass")
	assert_true(String(entry[0].effect).begins_with("+%d morale" % int(_sp("candlemass").morale)), entry[0].effect)
	var checks: Array = battle.log.events.filter(func(ev): return String(ev.get("t", "")) == "morale" and int(ev.side) == int(side.index))
	assert_false(checks.is_empty(), "the blessed side checks its morale")
	for ev in checks:
		assert_eq(int(Dictionary(ev.parts).get("spell_candlemass", 0)), int(_sp("candlemass").morale), "under Candlemass's own part")
		assert_false(Dictionary(ev.parts).has(AutoBattleResolver.BLESSING), "never Dawn Blessing's")


# --- Raise the Snuffed ----------------------------------------------------------------------------------------------

func test_raise_the_snuffed_is_a_pack_of_its_own() -> void:
	var s := _game(WAX, "mother_tallow")
	var her := _ruler(s)
	var sp := _sp("raise_the_snuffed")
	assert_true(MagicRules.is_pack("raise_the_snuffed"))
	assert_eq(MagicRules.price_words("raise_the_snuffed"), "%d gold a Snuffed" % int(sp.cost))
	var bonus := MagicRules.army_bonus(s, WAKE, her, "wax")
	assert_eq(MagicRules.pack_sizes(s, WAKE, her, "raise_the_snuffed"), [int(sp.count), int(sp.count) + bonus * int(sp.per_bonus.count)])
	var r := _resolve(s, {WAKE: [CastOrder.new("raise_the_snuffed", her.id, her.location, CastOrder.GOLD, int(sp.count))]})
	var summoned := _of(r, "summoned")
	assert_eq(summoned.size(), 1)
	var turn := s.current_turn + 1
	assert_eq(int(summoned[0].numbers.until), turn + int(sp.duration), "through T + 4")
	assert_eq(int(_of(r, "ritual_cast")[0].numbers.gold), int(sp.cost) * int(sp.count))
	var band: Army = r.new_state.find_army(String(summoned[0].numbers.army))
	assert_eq(band.units.size(), int(sp.count))
	assert_true(band.units.all(func(u): return u.type.id == "snuffed" and u.type.trait_id == AutoBattleResolver.PALL))
	# One band at a time.
	assert_eq(String(MagicRules.check_target(r.new_state, WAKE, "raise_the_snuffed", r.new_state.find_army(her.id), her.location).get("code", "")),
		"pack_out")
	# They hold through turn T + 4 and fade at its end, as the ritual said.
	var state: GameState = r.new_state
	var faded := []
	for _i in int(sp.duration):
		var next := _resolve(state)
		faded.append_array(_of(next, "summon_faded"))
		state = next.new_state
	assert_eq(faded.size(), 1, "they fade once")
	assert_eq(int(faded[0].numbers.until), turn + int(sp.duration))
	assert_eq(int(faded[0].numbers.count), int(sp.count))
	assert_true(String(faded[0].text).contains("as Raise the Snuffed said"), faded[0].text)
	assert_false(state.armies.any(func(a): return a.units.any(func(u): return u.type.id == "snuffed")), "no Snuffed are left")
	# An army left with only them is gone; one the Risen joined goes on without them (the capital raises Wickwardens).
	assert_eq(state.find_army(band.id) == null, bool(faded[0].numbers.removed))


func test_a_summoned_creature_answers_only_its_own_faction() -> void:
	var s := _game()
	var crown := _army(s, CROWN, _capital(s, CROWN), ["spearmen"])
	var u := Unit.new(MagicRules.summon_type("snuffed"), CROWN)
	u.until = s.current_turn + 2
	crown.units.append(u)
	var errors := []
	assert_false(s.validate(errors), "Snuffed in a Crown army is refused")
	assert_true(errors.any(func(m): return String(m).contains("summoned by")), "%s" % [errors])
	var load_errors := []
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())), load_errors)
	assert_true(back == null and load_errors.any(func(m): return String(m).contains("summoned by")), "and refused on loading: %s" % [load_errors])


# --- Draw the Warmth and Wax Skin in battle ----------------------------------------------------------------------------

func test_draw_the_warmth_and_wax_skin_cast_in_battle() -> void:
	var s := _game(WICK + WAX)
	var field := _at(s, _capital(s), 1)
	var wake := _army(s, WAKE, field, ["wickwardens", "wickwardens", "wickwardens", "chandlers_apprentices", "chandlers_apprentices"], 1)
	var foe := _army(s, CROWN, field, ["spearmen", "spearmen", "crossbowmen"])
	s.find_province(field).terrain = "plains"
	var r := AutoBattleResolver.resolve(wake, foe, s.find_province(field), SeededRNG.new(11), s, true)
	assert_eq(BattleLog.validate(r.log), [], "the log validates")
	var casts: Array = r.log.events.filter(func(e): return String(e.get("t", "")) == "cast")
	var warmth: Array = casts.filter(func(e): return String(e.spell) == "draw_the_warmth")
	var skin: Array = casts.filter(func(e): return String(e.spell) == "wax_skin")
	assert_false(warmth.is_empty(), "the apprentices draw the warmth")
	for e in warmth:
		assert_eq(int(e.damage), int(_sp("draw_the_warmth").value), "3 sure damage")
		assert_eq(int(e.self), 0, "the caster bleeds nothing")
	assert_false(skin.is_empty(), "and cast Wax Skin")
	for e in skin:
		assert_true(Array(e.targets).size() <= int(_sp("wax_skin").count), "on at most 6 units")


# --- saves, words and the codex --------------------------------------------------------------------------------------

func test_a_game_with_the_candlewakes_magic_saves_loads_and_plays_on() -> void:
	var s := _game(SNUFFED + WICK + ["bonfire_night"] + WAX)
	var home := _capital(s)
	var mage := _army(s, WAKE, home, ["chandlers_apprentices", "wickwardens"], 1)
	var r := _resolve(s, {WAKE: [CastOrder.new("bonfire_night", _ruler(s).id, ""),
		CastOrder.new("raise_the_snuffed", mage.id, home, CastOrder.GOLD, int(_sp("raise_the_snuffed").count))]})
	var t: GameState = r.new_state
	assert_false(MagicRules.flame_global(t, WAKE).is_empty())
	assert_true(t.armies.any(func(a): return a.units.any(func(u): return u.type.id == "snuffed")))
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(t.to_dict())))
	assert_true(back != null, "it loads")
	assert_eq(JSON.stringify(back.to_dict()), JSON.stringify(t.to_dict()), "to the same bytes")
	var on := _resolve(back)
	var again := _resolve(t)
	assert_eq(JSON.stringify(on.new_state.to_dict()), JSON.stringify(again.new_state.to_dict()), "and plays on the same")


func test_every_spell_has_its_words_and_the_codex_explains_them() -> void:
	for id in MagicData.PREVIEW_SPELLS:
		var sp: Dictionary = MagicData.PREVIEW_SPELLS[id]
		var entry: Dictionary = RulesCodex.ENTRIES.get(String(sp.codex), {})
		assert_false(entry.is_empty(), "%s has its codex entry" % id)
		assert_eq(String(entry.get("faction", "")), WAKE, "%s's entry is the Candlewake's" % id)
		assert_true(String(entry.text).contains("%d research" % int(MagicRules.arcana_node(id).cost)), "%s: its research" % id)
		if sp.has("cost"):
			assert_true(String(entry.text).contains("%d gold" % int(sp.cost)), "%s: its price" % id)
	for id in ["school_wick", "school_wax", "node_wick_mastery", "node_wax_mastery", "unit_snuffed", "mage_candlewake"]:
		assert_eq(String(RulesCodex.ENTRIES.get(id, {}).get("faction", "")), WAKE, "%s is the Candlewake's" % id)
	assert_eq(String(MagicData.PREVIEW_SUMMONS.snuffed.codex), "unit_snuffed")
	var snuffed := MagicRules.summon_type("snuffed")
	assert_true(String(RulesCodex.ENTRIES.unit_snuffed.text).contains("%d hit points, attack %d, defense %d, morale %d" % [snuffed.hp,
		snuffed.attack, snuffed.defense, snuffed.morale]))
	var mage := MagicRules.mage_type(WAKE)
	assert_true(String(RulesCodex.ENTRIES.mage_candlewake.text).contains("%d hit points, attack %d, defense %d, morale %d, %d gold" % [mage.hp,
		mage.attack, mage.defense, mage.morale, mage.cost]))
	# A Crown–Clans codex lists none of them (#285).
	for id in ["school_wick", "spell_kindle", "unit_snuffed", "mage_candlewake"]:
		assert_false(RulesCodex.shown_for(id, [CROWN, CLANS]))
		assert_true(RulesCodex.shown_for(id, [CROWN, WAKE]))
