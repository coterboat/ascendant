extends "res://tests/test_case.gd"
## Issue #6 orders UI: the OrdersController queues moves and recruits through the OrderBook,
## reports the rules' reasons, cancels, takes every number from Forecast (battle odds included),
## speaks in names (never ids) and never changes the state. Session-backed controllers keep the orders
## in GameSession's books. Plus the map screen's two-click move, cancel button and hover preview.

const MAP_SCENE := "res://ui/map_screen.tscn"


func _state() -> GameState:
	var s := GameState.new()
	if s.armies.is_empty():
		s.place_starting_armies()
	return s


func _own_army(s: GameState, fid: String) -> Army:
	for a in s.armies:
		if a.owner == fid:
			return a
	return null


func _non_neighbor(s: GameState, here: Province) -> String:
	for p in s.provinces:
		if p.id != here.id and not here.neighbors.has(p.id):
			return p.id
	return ""


func test_queue_a_valid_move() -> void:
	var s := _state()
	var fid := s.factions[0].id
	var army := _own_army(s, fid)
	var to: String = s.find_province(army.location).neighbors[0]
	var c := OrdersController.new(s, fid)
	assert_eq(c.queue_move(army.id, to), "", "a move to a neighbor is accepted")
	assert_eq(c.orders().size(), 1, "one order queued")
	assert_true(c.order_texts()[0].contains(s.find_province(to).name), "the order names the destination")
	assert_true(c.order_texts()[0].contains(OrdersController.NO_ENEMY_TEXT), "no enemy army there: a plain line instead of odds")
	assert_false(c.move_odds(army.id, to).enemy_present)
	assert_eq(c.move_forecast(army.id, to).ok, false, "a second move for the same army is forecast as refused")


func test_invalid_move_gives_the_rules_reason() -> void:
	var s := _state()
	var fid := s.factions[0].id
	var army := _own_army(s, fid)
	var far := _non_neighbor(s, s.find_province(army.location))
	var c := OrdersController.new(s, fid)
	var reason := c.queue_move(army.id, far)
	var expected: String = TurnResolver.check_move(s, fid, MoveOrder.new(army.id, far)).reason
	assert_false(reason.is_empty(), "a move to a non-neighbor is refused")
	assert_eq(reason, expected, "with the resolver's own plain-language reason")
	assert_eq(c.orders().size(), 0, "nothing queued")


func test_cancel_removes_the_order() -> void:
	var s := _state()
	var fid := s.factions[0].id
	var army := _own_army(s, fid)
	var c := OrdersController.new(s, fid)
	c.queue_move(army.id, s.find_province(army.location).neighbors[0])
	c.queue_recruit(s.factions[0].unit_types[0].id)
	c.cancel(0)
	assert_eq(c.orders().size(), 1, "one order left")
	assert_true(c.orders()[0] is RecruitOrder, "the move was the one cancelled")


func test_recruit_gold_after_matches_forecast() -> void:
	var s := _state()
	var f := s.factions[0]
	var ut: UnitType = f.unit_types[0]
	var c := OrdersController.new(s, f.id)
	assert_eq(c.queue_recruit(ut.id), "", "a recruit the faction can afford is accepted")
	var expected := Forecast.gold_after_recruits(s, f.id, [RecruitOrder.new(ut.id)])
	assert_eq(c.gold_after_recruits().gold_after, expected.gold_after, "gold after recruits comes from Forecast")
	assert_eq(c.gold_after_recruits().gold_after, f.gold - ut.cost, "and is gold minus the cost")
	assert_eq(c.recruit_cost(ut.id), Forecast.recruit_cost(s, f.id, ut.id), "cost comes from Forecast")
	assert_eq(c.queue_recruit("no_such_unit"), TurnResolver.check_recruit(s, f.id, RecruitOrder.new("no_such_unit"), 999).reason,
		"an unknown unit gets the rules' reason")


func test_order_texts_have_no_raw_ids() -> void:
	var s := _state()
	var f := s.factions[0]
	var army := _own_army(s, f.id)
	var to: String = s.find_province(army.location).neighbors[0]
	var ut: UnitType = f.unit_types[0]
	var c := OrdersController.new(s, f.id)
	c.queue_move(army.id, to)
	c.queue_recruit(ut.id)
	var ids := [army.id, to, army.location, f.capital, ut.id]
	for t in c.order_texts():
		for id in ids:
			if id != s.find_province(to).name and id != ut.name:
				assert_false(t.contains(id), "'%s' shows no raw id '%s'" % [t, id])


func test_the_controller_never_changes_the_state() -> void:
	var s := _state()
	var fid := s.factions[0].id
	var army := _own_army(s, fid)
	var before := str(s.to_dict())
	var c := OrdersController.new(s, fid)
	c.queue_move(army.id, s.find_province(army.location).neighbors[0])
	c.queue_recruit(s.factions[0].unit_types[0].id)
	c.order_texts()
	c.gold_after_recruits()
	c.cancel(0)
	assert_eq(str(s.to_dict()), before, "state unchanged")


func test_map_screen_two_click_move_and_cancel() -> void:
	var s := _state()
	var fid := s.factions[0].id
	var army := _own_army(s, fid)
	var here := s.find_province(army.location)
	var screen: MapScreen = load(MAP_SCENE).instantiate()
	screen.set_state(s, fid)
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	screen.select_army(army.id)
	screen.select_province(_non_neighbor(s, here))
	assert_eq(screen.orders.orders().size(), 0, "a click on a far province queues nothing")
	assert_false(screen.status_text.is_empty(), "and the rules' reason is shown")
	screen.select_army(army.id)
	screen.select_province(here.neighbors[0])
	assert_eq(screen.orders.orders().size(), 1, "second click on a neighbor queues the move")
	assert_eq(screen.selected_army_id, army.id, "the army stays selected")
	var cancel: Button = null
	for n in screen.details.find_children("CancelButton", "Button", true, false):
		cancel = n
	assert_true(cancel != null, "the orders list has a cancel button")
	if cancel:
		cancel.pressed.emit()
	assert_eq(screen.orders.orders().size(), 0, "cancel removes it")
	screen.get_parent().remove_child(screen)
	screen.free()


## Kingdom's army at Stonegate, next to the Thornmane army holding Blackwood, plus a second kingdom
## army in Wildmoor (also next to Blackwood).
func _border_state() -> GameState:
	var s := _state()
	s.find_army("kingdom-1").location = "stonegate"
	s.find_army("beasts-2").location = "blackwood"
	s.find_province("stonegate").owner = "kingdom"
	s.find_province("blackwood").owner = "beasts"
	var extra := Army.new()
	extra.id = "kingdom-3"
	extra.owner = "kingdom"
	extra.location = "wildmoor"
	var f := s.find_faction("kingdom")
	extra.units.append(Unit.new(TurnResolver.recruitable_type(f, "knights"), "kingdom"))
	s.armies.append(extra)
	return s


func test_move_into_an_enemy_army_shows_battle_odds_from_forecast() -> void:
	var s := _border_state()
	var c := OrdersController.new(s, "kingdom")
	var odds := Forecast.battle_odds(s, "kingdom", ["kingdom-1"], "blackwood")
	assert_true(odds.ok, "fixture: an enemy army holds Blackwood")
	var expected_line := "Battle odds: %s (you won %d of %d test battles)." % [odds.label, odds.wins, odds.samples]

	var preview := c.move_preview("kingdom-1", "blackwood")
	assert_true(preview.ok)
	assert_true(preview.text.contains(expected_line), "the hover preview has the odds: %s" % preview.text)

	assert_eq(c.queue_move("kingdom-1", "blackwood"), "")
	var line := c.order_texts()[0]
	assert_true(line.contains(expected_line), "the forecast line has the verdict: %s" % line)
	for r in odds.reasons:
		assert_true(line.contains(r), "and the main reason '%s'" % r)
	var desc: String = c.order_breakdown(0).description
	assert_true(desc.contains(odds.text), "the tooltip has Forecast's full odds text")
	assert_true(desc.contains(RulesCodex.text("battle_odds")), "and explains how odds are worked out")
	assert_false(line.contains(OrdersController.NO_ENEMY_TEXT))

	# A second army ordered into the same battle is counted in the odds of both orders.
	assert_eq(c.queue_move("kingdom-3", "blackwood"), "")
	var both := Forecast.battle_odds(s, "kingdom", ["kingdom-1", "kingdom-3"], "blackwood")
	for i in 2:
		assert_true(c.order_breakdown(i).description.contains(both.text), "order %d uses the odds of both armies" % i)
	assert_eq(c.move_odds("kingdom-1", "blackwood").odds.text, both.text)

	# A move with no enemy army in the destination gets the plain line instead.
	var calm := OrdersController.new(s, "kingdom")
	assert_eq(calm.queue_move("kingdom-1", "thornvale"), "")
	assert_true(calm.order_texts()[0].contains(OrdersController.NO_ENEMY_TEXT), calm.order_texts()[0])


func test_session_backed_controller_keeps_orders_in_the_session() -> void:
	var session := GameSession.new(GameState.new(3), ["kingdom", "beasts"], 3, StubBattleResolver.new())
	var c := OrdersController.new(session.state(), "kingdom", session)
	assert_eq(c.queue_move("kingdom-1", "westwatch"), "")
	assert_eq(c.queue_recruit("spearmen"), "")
	assert_eq(session.current_orders().size(), 2, "orders live in the session's books")
	assert_eq(c.orders(), session.current_orders())
	assert_eq(c.queue_move("kingdom-1", "highcrag"), session.queue_move("kingdom-1", "highcrag"),
		"refusals carry the session's reason")
	var rebuilt := OrdersController.new(session.state(), "kingdom", session)
	assert_eq(rebuilt.orders().size(), 2, "a new controller (map rebuild) sees the same orders")
	var other := OrdersController.new(session.state(), "beasts", session)
	assert_eq(other.orders(), [], "another player's controller sees nothing")
	assert_false(other.queue_recruit("tuskers").is_empty(), "and can't order out of turn")
	assert_eq(c.cancel(1), "")
	assert_eq(session.current_orders().size(), 1, "cancel goes through the session")
	assert_false(c.cancel(5).is_empty(), "a bad cancel is explained")
	assert_eq(session.end_turn(), "")
	assert_eq(c.orders(), [], "nothing to show once the computer is being passed")


func test_map_screen_hover_preview_shows_the_move_forecast_before_the_click() -> void:
	var s := _border_state()
	var screen: MapScreen = load(MAP_SCENE).instantiate()
	screen.set_state(s, "kingdom")
	assert_eq(screen.preview_move("blackwood"), "", "no army selected: nothing to preview")
	assert_false(screen.hover_panel.visible)
	screen.select_army("kingdom-1")
	var text := screen.preview_move("blackwood")
	var odds := Forecast.battle_odds(s, "kingdom", ["kingdom-1"], "blackwood")
	assert_true(screen.hover_panel.visible, "the preview bar shows")
	assert_eq(screen.hover_label.text, text)
	assert_true(text.begins_with("Click to order this move."), text)
	assert_true(text.contains(Forecast.move(s, "kingdom", MoveOrder.new("kingdom-1", "blackwood")).text), "arrival forecast")
	assert_true(text.contains("Battle odds: %s" % odds.label), "battle odds")
	assert_true(screen.preview_move("thornvale").contains(OrdersController.NO_ENEMY_TEXT))
	var far := screen.preview_move("fangridge")
	assert_true(far.begins_with("This move can't be ordered:"), "a move the rules refuse says why: %s" % far)
	screen.clear_preview()
	assert_false(screen.hover_panel.visible)
	assert_eq(screen.orders.orders().size(), 0, "hovering orders nothing")
	screen.free()
