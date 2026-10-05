extends "res://tests/test_case.gd"
## IND-1 (#142): independents, the Free Holds. Every neutral province starts with a garrison you must beat to take
## it; garrisons never move, recruit, heal, earn or take a province; Sworn Vassals sends a garrison home; garrisons
## are public under fog; the AI attacks a garrison only at its odds; everything saves, loads and replays; and a game
## without independents is untouched (the byte-identical replays of every older game live in test_sieges_off and
## friends, which run with independents off). Expected numbers come from IndependentData, never from this file.

const CROWN := "kingdom"
const CLANS := "beasts"
const HOLDS := IndependentData.FACTION_ID


func _game(seed_value: int = 11) -> GameState:
	var s := GameState.new(seed_value)
	var errors := []
	assert_true(s.setup_independents(errors), "independents set up: %s" % [errors])
	return s


func _start_army(s: GameState, fid: String) -> Army:
	for a in s.armies:
		if a.owner == fid:
			return a
	return null


func _orders(fid: String, list: Array) -> Dictionary:
	return {fid: list}


# --- setup ----------------------------------------------------------------------------------------

func test_every_neutral_province_gets_the_garrison_its_land_and_income_call_for() -> void:
	var s := _game()
	var holds := s.find_faction(HOLDS)
	var garrisons := 0
	for p in s.provinces:
		var g := s.garrison_at(p.id)
		if p.is_capital or not p.owner.is_empty():
			assert_eq(g, null, "%s is no neutral province, so it has no garrison" % p.id)
			continue
		garrisons += 1
		assert_true(g != null, "%s has a garrison" % p.id)
		assert_eq(g.id, IndependentData.army_id(p.id))
		assert_eq(g.owner, HOLDS)
		assert_eq(g.units.map(func(u): return u.type.id), IndependentData.garrison_units(p.terrain, p.income), "%s's units" % p.id)
		assert_eq(g.units.size(), IndependentData.garrison_size(p.income))
		assert_eq(g.commander != null, IndependentData.has_captain(p.income), "%s: a Hold Captain from %d gold" % [p.id, IndependentData.CAPTAIN_FROM])
		if g.commander != null:
			assert_eq(g.commander.type, holds.commander_type)
		for u in g.units:
			assert_eq(u.current_hp, u.type.hp, "a garrison starts unhurt")
			assert_eq(u.owner, HOLDS)
	assert_true(garrisons > 0)
	assert_eq(s.armies.size(), s.factions.size() + garrisons, "one starting army per faction, one garrison per neutral province")


func test_the_garrison_table_grows_with_income_and_follows_the_land() -> void:
	assert_eq(IndependentData.garrison_size(IndependentData.MID_FROM - 1), IndependentData.BASE_SIZE)
	assert_eq(IndependentData.garrison_size(IndependentData.MID_FROM), IndependentData.BASE_SIZE + 1)
	assert_eq(IndependentData.garrison_size(IndependentData.RICH_FROM), IndependentData.BASE_SIZE + 2)
	for terrain in IndependentData.GARRISONS:
		var row: Dictionary = IndependentData.GARRISONS[terrain]
		assert_true(row.units.size() >= IndependentData.BASE_SIZE + 2, "%s has a unit for the richest hold" % terrain)
	assert_eq(IndependentData.garrison_kind("hills"), "Hillguard")
	assert_eq(IndependentData.garrison_units("forest", 6)[0], "wildkin", "the forests raise Wildkin")


func test_independents_are_chosen_before_the_game_starts_and_are_off_by_default() -> void:
	var plain := GameState.new(11)
	assert_false(plain.independents)
	assert_eq(plain.garrison_at("westwatch"), null)
	assert_false(plain.to_dict().has("independents"), "a game without them saves no key")
	assert_eq(plain.find_faction(HOLDS), null, "without independents there are no Free Holds")
	plain.current_turn = 1
	var errors := []
	assert_false(plain.setup_independents(errors))
	assert_eq(errors, ["Independents are chosen before the game starts."])


func test_the_free_holds_are_never_a_player() -> void:
	var s := _game()
	assert_false(s.factions.any(func(f): return f.id == HOLDS), "never in the faction list")
	var holds := s.find_faction(HOLDS)
	assert_eq(holds.faction_name, IndependentData.FACTION_NAME, "found for names and unit types")
	var session := GameSession.new(s, [CROWN, CLANS], 11)
	assert_eq(session.players(), [CROWN, CLANS])
	assert_eq(session.phase(), GameSession.Phase.ORDERS)


func test_garrison_unit_stats_follow_the_breakpoint_rules() -> void:
	# FactionData's rules: odd attack; defense, counting Shield Wall, at a multiple of 4 or one more.
	var holds := IndependentData.faction()
	for ut in holds.unit_types + [holds.commander_type]:
		assert_eq(ut.attack % 2, 1, "%s has an odd attack" % ut.id)
		var d: int = ut.defense + (AutoBattleResolver.SHIELD_WALL_DEFENSE if ut.trait_id == AutoBattleResolver.SHIELD_WALL else 0)
		assert_true(d % 4 <= 1, "%s's defense %d sits on a breakpoint" % [ut.id, d])
		assert_eq(ut.cost, 0, "nobody recruits them")
		assert_ne(ut.trait_description, "", "%s's trait explains itself" % ut.id)


# --- turns ----------------------------------------------------------------------------------------

func test_taking_a_neutral_province_means_beating_its_garrison() -> void:
	var s := _game()
	var army := _start_army(s, CROWN)
	var target := "westwatch"
	var garrison_id := IndependentData.army_id(target)
	var result := TurnResolver.resolve(s, _orders(CROWN, [MoveOrder.new(army.id, target)]), 5, StubBattleResolver.new())
	var after: GameState = result.new_state
	var battle: Array = result.events.filter(func(e): return e.type == "battle" and e.provinces.has(target))
	assert_eq(battle.size(), 1, "moving in starts a battle with the garrison")
	assert_eq(String(battle[0].get("numbers", {}).get("defender", HOLDS)), HOLDS, "the garrison holds the ground")
	assert_eq(after.find_army(garrison_id), null, "the beaten garrison is gone")
	assert_eq(after.find_province(target).owner, CROWN)
	var captured: Array = result.events.filter(func(e): return e.type == "captured" and e.provinces.has(target))
	assert_eq(captured.size(), 1)
	assert_eq(captured[0].cause, "battle_victory", "taken after winning the battle, not unopposed")


func test_a_lost_attack_leaves_the_province_neutral_and_the_garrison_wounded() -> void:
	var s := _game()
	var army := _start_army(s, CROWN)
	var target := "rivermarch"  # the richest hold next to the capital, with a Hold Captain
	var g_before := s.garrison_at(target)
	var hp_before := 0
	for u in g_before.units:
		hp_before += u.current_hp
	# A lone spearman against a rich hold loses.
	var lone := Army.new()
	lone.id = s.new_army_id(CROWN)
	lone.owner = CROWN
	lone.location = "crownkeep"
	lone.units.append(Unit.new(s.find_faction(CROWN).unit_types[0], CROWN))
	s.armies.append(lone)
	var result := TurnResolver.resolve(s, _orders(CROWN, [MoveOrder.new(lone.id, target)]), 9, AutoBattleResolver.new())
	var after: GameState = result.new_state
	assert_eq(after.find_army(lone.id), null, "the loser is destroyed")
	assert_eq(after.find_province(target).owner, "", "the province stays neutral")
	var g := after.garrison_at(target)
	assert_true(g != null, "the garrison holds")
	assert_true(after.validate(), "a garrison that held is a valid state")
	var hp_after := 0
	for u in g.units:
		hp_after += u.current_hp
	assert_true(hp_after <= hp_before, "it keeps whatever wounds it took")
	# Garrisons never heal: another quiet turn changes nothing about it.
	var quiet := TurnResolver.resolve(after, {}, 10, AutoBattleResolver.new())
	var g2: Army = quiet.new_state.garrison_at(target)
	assert_eq(JSON.stringify(g2.to_dict()), JSON.stringify(g.to_dict()), "no healing, no moving, no recruiting")
	assert_true(army != null)


func test_garrisons_never_move_recruit_or_earn() -> void:
	var s := _game(23)
	var session := GameSession.new(s, [CROWN, CLANS], 23, AutoBattleResolver.new(), {CROWN: "normal", CLANS: "normal"})
	var computer := AISeat.new(session, 23)
	var where := {}
	for a in s.armies:
		if a.owner == HOLDS:
			where[a.id] = a.location
	for t in 8:
		computer.play(session)
		if session.is_over():
			break
		var now := session.state()
		for a in now.armies:
			if a.owner != HOLDS:
				continue
			assert_true(where.has(a.id), "no new garrison appears (%s)" % a.id)
			assert_eq(a.location, where[a.id], "a garrison never moves")
			assert_eq(now.find_province(a.location).owner, "", "a garrison only ever holds a neutral province")
		for e in session.turn_report().events:
			assert_false(Array(e.get("factions", [])).has(HOLDS) and String(e.type) in ["recruited", "income", "captured"],
				"the Free Holds never recruit, earn or capture: %s" % e.text)
	assert_eq(computer.rejections(), [], "the computer's orders all pass with garrisons on the map")


func test_sworn_vassals_sends_the_garrison_home() -> void:
	var errors := []
	var s := GameState.with_rulers(7, {CROWN: {"ruler": "aurel_king", "mandates": ["sworn_vassals"]}}, errors)
	assert_true(s != null and s.setup_independents(errors), "%s" % [errors])
	var picks := RulerRules.vassal_picks(s, RulerRules.board_now(s).owners, RulerRules.board_now(s).occupied)
	assert_true(picks.joins.has(CROWN), "a garrison does not keep a vassal out")
	var pid := String(picks.joins[CROWN])
	assert_true(s.garrison_at(pid) != null)
	var result := TurnResolver.resolve(s, {}, 3, AutoBattleResolver.new())
	var after: GameState = result.new_state
	assert_eq(after.find_province(pid).owner, CROWN, "it swears fealty")
	assert_eq(after.garrison_at(pid), null, "its garrison goes home")
	var joined: Array = result.events.filter(func(e): return e.type == "vassal_joined")
	assert_eq(joined.size(), 1)
	assert_true(String(joined[0].text).contains("laid down their arms"), joined[0].text)
	assert_eq(String(joined[0].numbers.garrison), IndependentData.army_id(pid))
	assert_eq(Forecast.vassal(s, CROWN).province, pid, "the forecast agrees")


# --- saves, replays, names, fog, the AI -----------------------------------------------------------

func test_a_game_with_independents_saves_loads_and_replays() -> void:
	var s := _game(31)
	var d := s.to_dict()
	assert_eq(d.get("independents"), true)
	var errors := []
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)), errors)
	assert_true(back != null, "%s" % [errors])
	assert_eq(JSON.stringify(back.to_dict()), JSON.stringify(d), "a JSON round trip is exact")
	var session := GameSession.new(s, [CROWN, CLANS], 31, AutoBattleResolver.new(), {CROWN: "normal", CLANS: "normal"})
	var computer := AISeat.new(session, 31)
	for t in 6:
		computer.play(session)
	var replayed := GameSession.replay(JSON.parse_string(JSON.stringify(session.record())), AutoBattleResolver.new())
	assert_eq(replayed.errors, [])
	assert_eq(JSON.stringify(replayed.state.to_dict()), JSON.stringify(session.state().to_dict()), "the replay agrees")


func test_a_garrison_is_named_for_its_province() -> void:
	var s := _game()
	var p := s.find_province("highcrag")
	assert_eq(TurnReportText.army_name(s, IndependentData.army_id("highcrag")),
		"the %s %s" % [p.name, IndependentData.garrison_kind(p.terrain)])
	assert_eq(TurnReportText.faction_of(IndependentData.army_id("highcrag")), HOLDS)


func test_the_move_forecast_names_the_garrison_and_never_warns_of_a_border_meeting() -> void:
	var s := _game()
	var army := _start_army(s, CROWN)
	var f := Forecast.move(s, CROWN, MoveOrder.new(army.id, "westwatch"))
	var text := String(f.get("text", ""))
	assert_true(text.contains("holds it for the %s" % IndependentData.FACTION_NAME), text)
	assert_true(text.contains(RulerRules._cap(TurnReportText.army_name(s, IndependentData.army_id("westwatch")))), "names the garrison: %s" % text)
	assert_false(text.contains("moves toward you"), "a garrison never moves")
	assert_false(text.contains("is undefended"), "it isn't")


func test_the_codex_states_the_garrison_table() -> void:
	var text := RulesCodex.text("independents")
	assert_true(text.contains("up to %d gold holds %d units" % [IndependentData.MID_FROM - 1, IndependentData.BASE_SIZE]), text)
	assert_true(text.contains("%d to %d gold holds %d" % [IndependentData.MID_FROM, IndependentData.RICH_FROM - 1, IndependentData.BASE_SIZE + 1]))
	assert_true(text.contains("%d or more holds %d" % [IndependentData.RICH_FROM, IndependentData.BASE_SIZE + 2]))
	assert_true(text.contains("from %d gold a Hold Captain" % IndependentData.CAPTAIN_FROM))
	assert_true(text.contains(IndependentData.FACTION_NAME))


func test_garrisons_are_public_under_fog() -> void:
	var s := _game(41)
	s.setup_fog([])
	var view := FogRules.view_state(s, CROWN)
	assert_true(view != null)
	for a in s.armies:
		if a.owner != HOLDS:
			continue
		var seen := view.find_army(a.id)
		assert_true(seen != null, "%s is in the Crown's view" % a.id)
		assert_eq(JSON.stringify(seen.to_dict()), JSON.stringify(a.to_dict()), "exactly as it is")


func test_the_computer_attacks_a_garrison_only_at_its_odds() -> void:
	for seed_value in [3, 17, 29]:
		var s := _game(seed_value)
		for fid in [CROWN, CLANS]:
			var brain := AIPlayer.new()
			var orders := brain.plan_orders(s, fid, SeededRNG.new(seed_value), "normal")
			var into := {}
			for o in orders:
				if o is MoveOrder and s.garrison_at(o.to) != null:
					if not into.has(o.to):
						into[o.to] = []
					into[o.to].append(o.army_id)
			for pid in into:
				var odds := Forecast.battle_odds(s, fid, into[pid], pid)
				assert_true(float(odds.get("win_rate", 0.0)) >= float(AIPlayer.HOLD_ATTACK_RATE.normal) - 0.05,
					"seed %d: %s attacks %s at %s" % [seed_value, fid, pid, odds.get("win_rate")])


func test_a_neutral_fort_garrison_holds_its_ground_in_a_sieges_game() -> void:
	var s := GameState.with_sieges(13, {}, {})
	assert_true(s.setup_independents([]))
	var fort := ""
	for p in s.provinces:
		if p.owner.is_empty() and p.fort_level > 0:
			fort = p.id
			break
	assert_ne(fort, "", "the map has a neutral fort")
	var lone := Army.new()
	lone.id = s.new_army_id(CROWN)
	lone.owner = CROWN
	lone.location = fort
	lone.units.append(Unit.new(s.find_faction(CROWN).unit_types[0], CROWN))
	s.armies.append(lone)
	var plan := SiegeRules.next_battle(s, fort, {lone.id: true}, {"storms": {}, "sallies": {}})
	assert_eq(String(plan.get("defender", "")), HOLDS, "the garrison defends, in the open, with no siege")


# --- the screens ----------------------------------------------------------------------------------

func test_the_new_game_screen_has_an_independents_box_and_quick_start_uses_it() -> void:
	var ng: NewGameScreen = load("res://ui/new_game_screen.tscn").instantiate()
	assert_false(ng.independents_on(), "off by default until the MVP defaults flip, like every other system box")
	assert_false(ng.config().has("independents"), "an M1 config stays exactly as it was")
	ng.set_independents(true)
	assert_eq(ng.config().get("independents"), true)
	assert_eq(NewGameScreen.quick_start_config().get("independents"), true, "Quick start has them")
	assert_true(ng.independents_toggle.tooltip_text.contains(IndependentData.FACTION_NAME))
	ng.free()


func test_a_game_started_with_independents_has_its_garrisons() -> void:
	var state := GameScreen.starting_state({"players": [CROWN, CLANS], "seed": 5, "independents": true})
	assert_true(state.independents)
	assert_true(state.garrison_at("westwatch") != null)
	assert_false(GameScreen.starting_state({"players": [CROWN, CLANS], "seed": 5}).independents, "and only when asked")
