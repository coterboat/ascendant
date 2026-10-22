extends "res://tests/test_case.gd"
## CW-5's hand-off to the cast dialog (#256): a ritual that lands on one army (Kindle, Candlemass) gets an army row under its
## target. "As the rules pick" names the army CastOrder.target_army left empty would land on; each army of yours there is a
## button, greyed with the rules' reason where the ritual can't land on it; the forecast follows the choice, and Cast queues the
## order with the army named. Every other ritual's dialog is as before.

const CROWN := "kingdom"
const WAKE := "candlewake"
const GAME_SCENE := "res://ui/game_screen.tscn"


func _state(nodes: Array, ruler: String = "half_death") -> GameState:
	var errors := []
	var s := GameState.create(23, [CROWN, WAKE], {"magic": true}, {WAKE: {"ruler": ruler, "mandates": []}, CROWN: "warrior_king"}, errors)
	assert_eq(errors, [], "the magic game starts")
	s = AscensionRules.with_nodes(s, WAKE, nodes)
	for f in s.factions:
		f.gold = 200
	return s


func _army(s: GameState, at: String, types: Array, flame: int) -> Army:
	var a := Army.new()
	a.id = s.new_army_id(WAKE)
	a.owner = WAKE
	a.location = at
	for t in types:
		a.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(WAKE), String(t), s), WAKE))
	a.flame = flame
	s.armies.append(a)
	return a


func _screen(s: GameState) -> GameScreen:
	var session := GameSession.new(s, [WAKE, CROWN], 9, AutoBattleResolver.new())
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	assert_eq(game.load_game(SaveGame.make(session, {}, SaveGame.MANUAL, "Army picker", 0)), "")
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
	return game


func test_kindle_lists_the_armies_there_and_queues_the_one_picked() -> void:
	var s := _state(["draw_the_warmth", "kindle"])
	var cap := s.find_faction(WAKE).capital
	var start: Army = s.armies.filter(func(a): return a.owner == WAKE and a.ruler == null and a.location == cap)[0]
	start.flame = 1
	var hot := _army(s, cap, ["wickwardens"], WickRules.base_cap(WAKE))
	var warm := _army(s, cap, ["wickwardens", "gleaners"], 1)
	var game := _screen(s)
	var ruler := RulerRules.ruler_army(game.session.state(), WAKE)
	game.map.open_cast_dialog(ruler.id)
	var dialog := game.map.cast_dialog
	dialog.select_ritual("kindle")
	dialog.select_target(cap)
	var view := game.map.orders.view_state()
	# The rules' pick, named; then every army of yours there in number order, the ruler's own greyed (it carries no flame).
	var mine := TurnReportText.sort_ids(view.armies.filter(func(a): return a.owner == WAKE and a.location == cap).map(func(a): return a.id))
	assert_eq(dialog.army_buttons.keys(), [""] + mine, "the rules' pick, then each army there")
	var pick := String(MagicRules.one_army(view, WAKE, "kindle", cap, "").army)
	assert_eq(pick, start.id, "the rules pick the lowest-numbered army there that Kindle can warm")
	assert_true(String(dialog.army_buttons[""].text).contains(TurnReportText.army_name(view, pick, WAKE)), dialog.army_buttons[""].text)
	assert_true(dialog.army_buttons[""].button_pressed, "the rules' pick is chosen to begin with")
	assert_true(dialog.army_buttons[hot.id].disabled, "an army at flame 3 can't take it")
	assert_true(String(dialog.army_buttons[hot.id].tooltip_text).replace("\n", " ").contains("never raises a flame above"),
		dialog.army_buttons[hot.id].tooltip_text)
	assert_true(dialog.army_buttons[ruler.id].disabled, "nor the ruler's own army")
	assert_false(dialog.army_buttons[warm.id].disabled)
	# Pick the third army: the forecast follows, and Cast queues it by name.
	dialog.army_buttons[warm.id].pressed.emit()
	assert_eq(dialog.target_army, warm.id)
	assert_eq(String(dialog.forecast.effect.kindled.army), warm.id, "the forecast lands on the army picked")
	assert_true(dialog.shown_forecast().contains(TurnReportText.army_name(view, warm.id, WAKE)), dialog.shown_forecast())
	dialog.confirm()
	var queued: Array = game.session.current_orders().filter(func(o): return o is CastOrder)
	assert_eq(queued.size(), 1, "the cast is queued")
	assert_eq(String(queued[0].target_army), warm.id, "with the army named")
	game.free()


func test_the_rules_pick_queues_no_army_and_a_new_target_starts_from_it() -> void:
	var s := _state(["draw_the_warmth", "kindle"])
	var cap := s.find_faction(WAKE).capital
	var game := _screen(s)
	var ruler := RulerRules.ruler_army(game.session.state(), WAKE)
	game.map.open_cast_dialog(ruler.id)
	var dialog := game.map.cast_dialog
	dialog.select_ritual("kindle")
	dialog.select_target(cap)
	var other: Array = dialog.army_buttons.keys().filter(func(k): return not String(k).is_empty() and not dialog.army_buttons[k].disabled)
	assert_false(other.is_empty(), "an army to pick")
	dialog.select_army(String(other[0]))
	dialog.select_target(cap)
	assert_eq(dialog.target_army, "", "choosing the target again starts from the rules' pick")
	dialog.confirm()
	var queued: Array = game.session.current_orders().filter(func(o): return o is CastOrder)
	assert_eq(String(queued[0].target_army), "", "the rules' pick names no army")
	assert_false(queued[0].to_dict().has("target_army"), "and saves as every other cast does")
	game.free()


func test_candlemass_gets_the_row_and_every_other_ritual_does_not() -> void:
	var s := _state(["wake_thicker_tallow", "wake_sitting_up_early", "wake_oath_kept", "wax_skin", "raise_the_snuffed", "candlemass"],
		"mother_tallow")
	var cap := s.find_faction(WAKE).capital
	_army(s, cap, ["wickwardens"], 1)
	var game := _screen(s)
	var her := RulerRules.ruler_army(game.session.state(), WAKE)
	game.map.open_cast_dialog(her.id)
	var dialog := game.map.cast_dialog
	dialog.select_ritual("candlemass")
	dialog.select_target(cap)
	assert_false(dialog.army_buttons.is_empty(), "Candlemass lands on one army: the row is there")
	assert_false(dialog.army_buttons[her.id].disabled, "Candlemass may bless the ruler's own army, if picked")
	var pick := String(MagicRules.one_army(game.map.orders.view_state(), WAKE, "candlemass", cap, "").army)
	assert_ne(pick, her.id, "but the rules pick a soldiers' army first")
	dialog.select_ritual("raise_the_snuffed")
	assert_true(dialog.army_buttons.is_empty(), "a summon has no army row")
	assert_eq(dialog.choice_box.find_children("Armies", "", true, false).size(), 0)
	game.free()
