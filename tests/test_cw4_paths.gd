extends "res://tests/test_case.gd"
## CW-4 (#255, design/CANDLEWAKE.md §6): the Candlewake's path, the Pouring (the director's provisional name). Four ordinary
## nodes, then the fork. As in M4, each Oath brings its side's economy rule whole and at once (the director, Q CW-4): the Oath
## of the Kept Meadow Wake (the Wake pays +1 gold where it cost 1, and the Wake-Line comes a turn sooner), the Oath of the
## Snuffed Pyre Roads (a win in your own Wake gives +2 flame, never above the cap). The transformation brings the rest and its
## forswear: the Golden Wake (Combwardens, Amber Saints, the Long Sleep) or the Red Wake (Red Gleaners, Pyre-Walkers, the
## flame to 4 with its burn-down, the Swelling). Every number comes from the data and the rules' constants.

const CROWN := "kingdom"
const CLANS := "beasts"
const WAKE := "candlewake"
const ORDINARY := ["wake_thicker_tallow", "wake_sitting_up_early"]
const GOLDEN := ["wake_thicker_tallow", "wake_sitting_up_early", "wake_oath_kept", "wake_golden_wake"]
## The Red side without Sitting Up Early, so the Wake-Line stays at its row's threshold.
const RED := ["wake_thicker_tallow", "wake_brighter_flare", "wake_oath_snuffed", "wake_red_wake"]


func _game(flags: Dictionary = {}, game_seed: int = 23) -> GameState:
	var errors := []
	var f := {"paths": true}
	f.merge(flags)
	var s := GameState.create(game_seed, [CROWN, WAKE], f, {WAKE: {"ruler": "half_death", "mandates": []}, CROWN: "warrior_king"},
		errors)
	assert_eq(errors, [])
	return s


func _with(s: GameState, ids: Array) -> GameState:
	var out := AscensionRules.with_nodes(s, WAKE, ids)
	assert_true(out != null, "the nodes apply: %s" % [ids])
	var errors := []
	assert_true(out.validate(errors), "%s is a legal order: %s" % [ids, errors])
	return out


func _fx(node_id: String) -> Dictionary:
	return AscensionRules.node_effects(node_id)


func _row_held(stage: int) -> int:
	return int(MarkData.stage(WAKE, stage).held)


func _army(s: GameState, owner: String, at: String, types: Array, flame: int = -1) -> Army:
	var f := s.find_faction(owner)
	var a := Army.new()
	a.id = s.new_army_id(owner)
	a.owner = owner
	a.location = at
	for type_id in types:
		var ut := TurnResolver.recruitable_type(f, String(type_id))
		if ut.is_commander:
			a.commander = Unit.new(ut, owner)
		else:
			var u := Unit.new(ut, owner)
			u.current_hp = RulerRules.unit_max_hp(s, u)
			a.units.append(u)
	a.flame = flame
	s.armies.append(a)
	return a


## A province next to the Candlewake's capital that nobody holds.
func _field(s: GameState) -> String:
	for pid in s.find_province(s.find_faction(WAKE).capital).neighbors:
		if s.find_province(pid).owner.is_empty() and s.garrison_at(pid) == null:
			return pid
	return ""


# --- the path, behind the preview ---------------------------------------------------------------------------

func test_the_pouring_is_the_candlewakes_alone_and_the_shipped_tables_are_as_they_were() -> void:
	var path := AscensionRules.path_data(WAKE)
	assert_eq(String(path.name), "the Pouring")
	var kinds: Array = path.nodes.map(func(n): return String(n.kind))
	kinds.sort()
	assert_eq(kinds, ["oath", "oath", "tier1", "tier1", "tier2", "tier2", "transformation", "transformation"])
	assert_eq(AscensionRules.branches_for(WAKE), ["golden_wake", "red_wake"])
	assert_eq(AscensionRules.branches_for(CROWN), ["celestial_host", "living_iron"], "the Crown's sides, in their order")
	assert_eq(PathData.PATHS.keys(), [CROWN, CLANS], "the shipped paths are untouched")
	for key in PathData.BRANCHES:
		assert_ne(String(PathData.BRANCHES[key].faction), WAKE)
	for nid in AscensionRules.node_ids(WAKE):
		assert_true(RulesCodex.ENTRIES.has(String(AscensionRules.node_data(nid).codex)), "%s's codex entry" % nid)
		assert_eq(String(AscensionRules.node_data(nid).faction), WAKE)
	for key in [String(path.codex), "meadow_wake", "pyre_roads", "the_long_sleep"]:
		assert_true(RulesCodex.ENTRIES.has(key), "the codex has %s" % key)
	for unit_id in PathData.PREVIEW_NEW_UNITS:
		assert_true(AutoBattleResolver.TRAIT_TEXT.has(String(PathData.PREVIEW_NEW_UNITS[unit_id].trait)), "%s's trait is a real one" % unit_id)


# --- the ordinary nodes (§6.1) --------------------------------------------------------------------------------

func test_the_ordinary_nodes() -> void:
	var s := _game()
	var t := _with(s, ["wake_thicker_tallow", "wake_sitting_up_early", "wake_brighter_flare", "wake_hungry_gleaners"])
	var ww := TurnResolver.recruitable_type(s.find_faction(WAKE), "wickwardens")
	assert_eq(int(RulerRules.unit_stats(t, WAKE, "wickwardens").hp), ww.hp + int(_fx("wake_thicker_tallow").unit.wickwardens.hp))
	var gl := TurnResolver.recruitable_type(s.find_faction(WAKE), "gleaners")
	assert_eq(int(RulerRules.unit_stats(t, WAKE, "gleaners").attack), gl.attack + int(_fx("wake_hungry_gleaners").unit.gleaners.attack))
	# Sitting Up Early moves only the Wake-Line.
	assert_eq(MarkRules.threshold(t, WAKE, 2), _row_held(2) - int(_fx("wake_sitting_up_early").wake_sooner))
	assert_eq(MarkRules.threshold(t, WAKE, 3), _row_held(3), "Deep Wake stays put")
	assert_eq(MarkRules.threshold(s, WAKE, 2), _row_held(2), "without it, the row's")
	assert_eq(WickRules.flare_damage(t, WAKE), AutoBattleResolver.FLARE_DAMAGE + int(_fx("wake_brighter_flare").flare_damage))


func test_brighter_flare_burns_hotter_in_battle() -> void:
	var s := _with(_game(), ["wake_thicker_tallow", "wake_brighter_flare"])
	var flares := 0
	for game_seed in 16:
		var wake := _army(s, WAKE, "thornvale", ["hundred_wick"], 1)
		var foe := _army(s, CROWN, "thornvale", ["knights", "knights", "spearmen", "spearmen", "spearmen", "knight_captain"])
		var r := AutoBattleResolver.resolve(wake, foe, s.find_province("thornvale"), SeededRNG.new(700 + game_seed), s, true)
		assert_eq(BattleLog.validate(r.log), [], "the log validates")
		assert_eq(BattleLog.cross_check(r.log, r.report), [], "and agrees with the report")
		for e in r.log.events:
			if String(e.t) == "flare":
				flares += 1
				assert_eq(int(e.damage), WickRules.flare_damage(s, WAKE), "the path's Flare")
		s.armies.erase(wake)
		s.armies.erase(foe)
	assert_true(flares > 0, "a Hundred-Wick fell and flared")


# --- the Golden Wake (§6.2) -------------------------------------------------------------------------------------

func test_the_oath_of_the_kept_brings_meadow_wake_whole() -> void:
	var s := _game()
	var oath := _with(s, ["wake_thicker_tallow", "wake_brighter_flare", "wake_oath_kept"])
	assert_eq(AscensionRules.economy_rule_name("wake_oath_kept"), "Meadow Wake")
	assert_eq(MarkRules.threshold(oath, WAKE, 2), _row_held(2) - 1, "the Wake-Line a turn sooner")
	oath.current_turn = 6
	oath.find_province("thornvale").owner = WAKE
	oath.marks["thornvale"] = {"mark": {"faction": WAKE, "since_turn": MarkRules.end_clock(oath) - _row_held(2)}}
	var parts: Array = RulerRules.province_income_parts(oath, "thornvale").mods.filter(func(m): return String(m.key) == MarkRules.INCOME_KEY)
	assert_eq(parts.size(), 1)
	assert_eq(int(parts[0].value), int(_fx("wake_oath_kept").wake_gold), "the Wake pays where it cost")
	assert_eq(String(parts[0].name), "Meadow Wake")
	assert_true(" ".join(MarkRules.province_text(oath, "thornvale")).contains("+1 gold"), " ".join(MarkRules.province_text(oath, "thornvale")))
	# With Sitting Up Early too, the Wake-Line comes after 1 turn held, never sooner.
	var both := _with(s, ["wake_thicker_tallow", "wake_sitting_up_early", "wake_oath_kept"])
	assert_eq(MarkRules.threshold(both, WAKE, 2), maxi(1, _row_held(2) - 2))
	# Nothing of the transformation yet.
	assert_eq(AscensionRules.transformation(oath, WAKE), "")
	assert_eq(RulerRules.sacrifice_check(oath, WAKE, "muster_grounds").get("code", ""), "", "Muster Grounds is forsworn only with the transformation")


func test_the_golden_wake_brings_combwardens_amber_saints_and_the_long_sleep() -> void:
	var s := _with(_game(), GOLDEN)
	var f := s.find_faction(WAKE)
	var comb := TurnResolver.recruitable_type(f, "wickwardens")
	assert_eq(comb.name, "Combwardens")
	assert_true(TurnResolver.recruitable_type(f, "amber_saints") != null, "Amber Saints join the roster")
	assert_eq(String(TurnResolver.recruitable_type(f, "amber_saints").trait_id), AutoBattleResolver.IRON_HIDE)
	var refused := RulerRules.sacrifice_check(s, WAKE, "muster_grounds")
	assert_eq(String(refused.get("code", "")), "forsworn_mandate")
	assert_true(String(refused.reason).contains("became the Golden Wake"), refused.reason)
	# The Long Sleep: the dead rise from the Wake-Line too, every 3 turns past its (sooner) threshold.
	var sleep: Dictionary = _fx("wake_golden_wake").risen
	var line := MarkRules.threshold(s, WAKE, 2)
	s.find_province("thornvale").owner = WAKE
	s.marks["thornvale"] = {"mark": {"faction": WAKE, "since_turn": 1}}
	var risen := []
	for turn in range(1, 1 + line + 3 * int(sleep.every)):
		s.current_turn = turn
		var start := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
		var events := []
		MarkRules.wake_step(s, events, start)
		for e in events:
			if String(e.type) == "risen" and String(e.numbers.province) == "thornvale":
				risen.append(MarkRules.end_clock(s) - 1)  # held at that wake step
	assert_eq(risen, [line + int(sleep.every), line + 2 * int(sleep.every), line + 3 * int(sleep.every)],
		"every %d turns past the Wake-Line" % int(sleep.every))


# --- the Red Wake (§6.3) ------------------------------------------------------------------------------------------

func test_the_oath_of_the_snuffed_brings_pyre_roads_under_the_old_cap() -> void:
	var s := _with(_game(), ["wake_thicker_tallow", "wake_brighter_flare", "wake_oath_snuffed"])
	assert_eq(AscensionRules.economy_rule_name("wake_oath_snuffed"), "Pyre Roads")
	var cap := WickRules.cap(s, WAKE)
	assert_eq(cap, int(FactionData.row(WAKE).wick.cap), "the cap stays until the transformation")
	assert_eq(WickRules.next_flame(s, WAKE, cap - 1, true, true, false, false), cap, "+2 on Pyre Roads, never above the cap")
	assert_eq(WickRules.next_flame(s, WAKE, cap - 2, true, true, false, false), cap)
	assert_eq(WickRules.next_flame(s, WAKE, cap - 2, true, false, false, false), cap - 1, "+1 elsewhere")


func test_pyre_roads_reads_the_land_as_the_battles_began() -> void:
	var s := _with(_game(), ["wake_thicker_tallow", "wake_brighter_flare", "wake_oath_snuffed"])
	s.current_turn = 8
	var held := _field(s)
	s.find_province(held).owner = WAKE
	s.marks[held] = {"mark": {"faction": WAKE, "since_turn": MarkRules.end_clock(s) - 1 - _row_held(2)}}  # the Wake-Line now
	assert_true(WickRules.pyre_road(s, WAKE, held), "a province of theirs at the Wake-Line when the battles began")
	s.marks[held] = {"mark": {"faction": WAKE, "since_turn": MarkRules.end_clock(s) - 1}}  # Sitting Up
	assert_false(WickRules.pyre_road(s, WAKE, held), "not before the Wake-Line")
	s.find_province(held).owner = CROWN
	s.marks[held] = {"scar": {"faction": WAKE, "stage": 2, "until_turn": MarkRules.end_clock(s) + 2}}
	assert_false(WickRules.pyre_road(s, WAKE, held), "a cold wake someone else held when the battles began")
	var plain := _game()
	plain.find_province(held).owner = WAKE
	plain.marks[held] = {"mark": {"faction": WAKE, "since_turn": -10}}
	assert_false(WickRules.pyre_road(plain, WAKE, held), "no Pyre Roads without the Oath")


func test_the_red_wake_burns_to_4_and_down_in_order() -> void:
	var s := _with(_game(), RED)
	var cap := WickRules.cap(s, WAKE)
	assert_eq(cap, int(_fx("wake_red_wake").flame_cap))
	var base := int(FactionData.row(WAKE).wick.cap)
	var idle := int(_fx("wake_red_wake").idle_loss)
	# [flame, won, pyre, harbour, raised, vigil, expected]
	var table := [
		[base, true, false, false, false, 0, base + 1],
		[base, true, true, false, false, 0, cap],
		[cap, true, false, false, false, 0, cap],
		[cap, false, false, false, false, 0, cap - idle],
		[cap, false, false, true, false, 0, base],
		[cap, false, false, true, false, 2, base],
		[1, false, false, false, false, 0, 0],
		[2, false, false, false, false, 3, mini(3, WickRules.VIGIL_MAX)],
	]
	for row in table:
		assert_eq(WickRules.next_flame(s, WAKE, int(row[0]), bool(row[1]), bool(row[2]), bool(row[3]), bool(row[4]), int(row[5])), int(row[6]),
			"%s" % [row])
	# Without the Red Wake: the row's cap, idle -1, and a win never above it.
	var plain := _game()
	assert_eq(WickRules.next_flame(plain, WAKE, base, true, false, false, false), base)
	assert_eq(WickRules.next_flame(plain, WAKE, 2, false, false, false, false), 1)


func test_flame_4_saves_validates_and_hides_out_of_sight() -> void:
	var s := _with(_game({"fog": true}), RED)
	var a := s.find_army("candlewake-1")
	a.flame = WickRules.cap(s, WAKE)
	var errors := []
	assert_true(s.validate(errors), "flame 4 is valid with the Red Wake: %s" % [errors])
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())), errors)
	assert_true(back != null and back.find_army(a.id).flame == a.flame, "it saves and loads: %s" % [errors])
	var plain := _game()
	plain.find_army("candlewake-1").flame = WickRules.cap(s, WAKE)
	assert_false(plain.validate([]), "and is refused without it")
	# The Oath and the transformation are public news (oath_sworn, transformed): the Crown has learned them, as a real turn would.
	var intel := FogRules.new_intel(s, CROWN)
	intel[WAKE]["nodes"] = RED.map(func(nid): return {"node": nid, "turn": 0})
	var view := FogRules.view_state(s, CROWN, {}, intel)
	assert_true(view != null, "the Crown's view loads")
	for v in view.armies:
		if v.owner == WAKE and v.location == a.location:
			assert_true(v.flame < 0 or String(FogRules.sight(s, CROWN).get(a.location, "")) == FogRules.CLEAR, "a rival sees the flame only in clear sight")


func test_the_red_wake_changes_the_gleaners_and_brings_pyre_walkers_and_the_swelling() -> void:
	var s := _with(_game(), RED)
	var f := s.find_faction(WAKE)
	var red := TurnResolver.recruitable_type(f, "gleaners")
	assert_eq(red.name, "Red Gleaners")
	assert_eq(String(TurnResolver.recruitable_type(f, "pyre_walkers").trait_id), AutoBattleResolver.BERSERK)
	assert_eq(WickRules.siphon_heal(s, WAKE, "gleaners"), int(_fx("wake_red_wake").siphon_heal.gleaners))
	assert_eq(WickRules.siphon_heal(_game(), WAKE, "gleaners"), AutoBattleResolver.SIPHON_HEAL, "ordinary Gleaners heal the base")
	assert_eq(String(RulerRules.sacrifice_check(s, WAKE, "iron_discipline").get("code", "")), "forsworn_mandate")
	# Red Gleaners drink 2 in battle.
	var drank := 0
	for game_seed in 16:
		var wake := _army(s, WAKE, "thornvale", ["gleaners", "gleaners", "gleaners"], 1)
		var foe := _army(s, CROWN, "thornvale", ["spearmen", "spearmen", "crossbowmen"])
		var r := AutoBattleResolver.resolve(wake, foe, s.find_province("thornvale"), SeededRNG.new(800 + game_seed), s, true)
		assert_eq(BattleLog.validate(r.log), [], "the log validates")
		assert_eq(BattleLog.cross_check(r.log, r.report), [], "and agrees with the report")
		for e in r.log.events:
			if String(e.t) == "heal" and String(e.get("trait", "")) == AutoBattleResolver.SIPHON:
				drank += 1
				var max_hp := int(r.log.fighters[int(e.f)].max_hp)
				assert_eq(int(e.to), mini(max_hp, int(e.from) + WickRules.siphon_heal(s, WAKE, "gleaners")))
		s.armies.erase(wake)
		s.armies.erase(foe)
	assert_true(drank > 0, "the Red Gleaners drank")
	# The Swelling: every Harvest raises one more, against players and Free Holds alike.
	var bonus := int(_fx("wake_red_wake").harvest_bonus)
	assert_eq(WickRules.harvest_count(s, WAKE, true), WickRules.harvest_count(_game(), WAKE, true) + bonus)
	assert_eq(WickRules.harvest_count(s, WAKE, false), int(RulerData.ABILITIES.harvest.free_hold) + bonus)


# --- the words (§6.4) -----------------------------------------------------------------------------------------

func test_the_army_card_and_the_forecast_speak_the_red_wakes_numbers() -> void:
	var s := _with(_game(), RED)
	var a := s.find_army("candlewake-1")
	a.flame = WickRules.cap(s, WAKE)
	var text := WickRules.flame_text(s, a)
	assert_true(text.contains("%d/%d" % [a.flame, a.flame]) and text.contains("drops to %d if it doesn't win" % int(FactionData.row(WAKE).wick.cap)), text)
	a.flame = 2
	a.location = _field(s)
	var line := WickRules.forecast_line(s, a, a.location)
	assert_true(line.contains("→ %d if it fights no battle" % (2 - int(_fx("wake_red_wake").idle_loss))), line)
	# Pyre Roads in the forecast: staying in its own Wake.
	var held := a.location
	s.find_province(held).owner = WAKE
	s.marks[held] = {"mark": {"faction": WAKE, "since_turn": MarkRules.end_clock(s) - 1 - _row_held(2)}}
	var pyre := WickRules.forecast_line(s, a, held)
	assert_true(pyre.contains("→ %d if it wins (Pyre Roads)" % mini(WickRules.cap(s, WAKE), 2 + int(_fx("wake_oath_snuffed").pyre_roads))), pyre)


func test_the_lock_in_preview_states_each_steps_numbers() -> void:
	var s := _with(_game(), ORDINARY)
	var kept := AscensionRules.effect_preview(s, WAKE, "wake_oath_kept")
	assert_true(kept.contains("Meadow Wake") and kept.contains("+1 gold") and kept.contains("the Wake-Line after"), kept)
	var snuffed := AscensionRules.effect_preview(s, WAKE, "wake_oath_snuffed")
	assert_true(snuffed.contains("Pyre Roads") and snuffed.contains("+2 flame"), snuffed)
	var golden := AscensionRules.effect_preview(_with(_game(), ["wake_thicker_tallow", "wake_sitting_up_early", "wake_oath_kept"]), WAKE,
		"wake_golden_wake")
	assert_true(golden.contains("Combwardens") and golden.contains("every 3 turns"), golden)
	var red := AscensionRules.effect_preview(_with(_game(), ["wake_thicker_tallow", "wake_brighter_flare", "wake_oath_snuffed"]), WAKE,
		"wake_red_wake")
	assert_true(red.contains("flame 4") and red.contains("loses 2") and red.contains("heals 2") and red.contains("one more"), red)


func test_the_codex_explains_the_path() -> void:
	assert_true(RulesCodex.text("path_candlewake").contains("the Pouring"))
	assert_true(RulesCodex.text("meadow_wake").contains("+1 gold") or RulesCodex.text("meadow_wake").contains("1 gold"))
	assert_true(RulesCodex.text("pyre_roads").contains("+2 flame") or RulesCodex.text("pyre_roads").contains("2 flame"))
	assert_true(RulesCodex.text("the_long_sleep").contains("every 3 turns"))


# --- the computer, until CW-6 -------------------------------------------------------------------------------------

func test_the_computers_stand_in_plan_reaches_the_candlewakes_fork() -> void:
	var plan := AIPaths.plan_for("", WAKE)
	assert_eq(plan.weights.map(func(w): return String(w[0])), AscensionRules.branches_for(WAKE))
	var side := AIPaths.choose_branch(17, 1, "", WAKE)
	assert_true(AscensionRules.branches_for(WAKE).has(side), "it picks one of their sides")
	var seq := AIPaths.sequence(WAKE, "", side)
	assert_true(seq.has(String(AscensionRules.branch_data(side).oath)) and seq.has(String(AscensionRules.branch_data(side).transformation)), "%s" % [seq])
	assert_eq(AIPaths.plan_for("", CROWN), AIPaths.plan_for("", CROWN), "the Crown's stand-in is as it was")
