extends "res://tests/test_case.gd"
## Issue #6 orders UI: the OrdersController queues moves and recruits through the OrderBook,
## reports the rules' reasons, cancels, takes every number from Forecast, speaks in names (never
## ids) and never changes the state. Plus the map screen's two-click move and cancel button.

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
	assert_true(c.order_texts()[0].contains("odds not available yet"), "battle odds wait for issue #4")
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
