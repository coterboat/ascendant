extends "res://tests/test_case.gd"
## ARM-1 (design/ARM1_SPLIT_MERGE.md §8; design/UX_WAR_TABLE.md §3.5): the army card's Armies here. Drag fighters and the commander
## between your armies in the province, or to New army; Split, Merge all and Swap commanders; the forecast (MusterForecast) updating as
## the pointer crosses a row, before anything is ordered; the engines stepper; an army that can't muster greyed, with its reason; the
## order in the orders list with its sentence; and an army a muster formed selected, marched and cancelled like any other.
## Drops are driven as Godot drives them: the payload a chip's drag starts with is offered to the row (_can_drop_data), then dropped.

const Kit := preload("res://tests/muster_test_kit.gd")
const FortTest := preload("res://tests/test_fort_panel.gd")
const MAP_SCENE := "res://ui/map_screen.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"


# --- fixtures ---------------------------------------------------------------------------------------------------

func _map(s: GameState, viewer: String = CROWN) -> MapScreen:
	var map: MapScreen = load(MAP_SCENE).instantiate()
	map.set_state(s, viewer)
	return map


## The Crown's first army at Crownkeep, a second one beside it, and the card of the first open.
func _two_armies(kind: String = "m1") -> Dictionary:
	var s := Kit.game(kind)
	var a := Kit.crown(s)
	var b := Kit.army(s, CROWN, "crownkeep", ["crossbowmen", "crossbowmen"])
	var map := _map(s)
	map.select_army(a.id)
	return {"state": s, "map": map, "a": a, "b": b}


func _board(map: MapScreen) -> MusterBoard:
	var found := map.details.find_children("ArmiesHere", "", true, false)
	return found[0] as MusterBoard if not found.is_empty() else null


func _card(map: MapScreen) -> ArmyCard:
	return map.cards.holder.get_child(0) as ArmyCard


func _node(root: Node, node_name: String) -> Node:
	var found := root.find_children(node_name, "", true, false)
	if found.is_empty():
		fail("found %s under %s" % [node_name, root.name])
		return null
	return found[0]


func _texts(node: Node, out: Array = []) -> Array:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return out
	if node is Label or node is Button:
		out.append(node.text)
	for c in node.get_children():
		_texts(c, out)
	return out


## The payload a drag of the chip starts with (what Godot hands the drop target).
func _grab(chip: UnitStrip.Chip) -> Variant:
	return chip.drag_data.call(chip)


func _click(chip: UnitStrip.Chip) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	chip._gui_input(e)


# --- the card ------------------------------------------------------------------------------------------------------

func test_the_card_lays_out_your_armies_with_split_merge_and_swap() -> void:
	var f := _two_armies()
	var map: MapScreen = f.map
	var board := _board(map)
	assert_true(board != null, "Armies here is on the card")
	assert_true(_card(map).muster_board == board)
	for name in ["SplitButton", "MergeAllButton", "SwapCommandersButton", "NewArmyZone", "MusterForecast"]:
		assert_true(board.find_child(name, true, false) != null, "%s is there" % name)
	assert_eq(board.rows.keys(), [f.b.id], "the other army has its row; this army's portraits are the card's own")
	var row := board.rows[f.b.id] as MusterBoard.Row
	assert_eq(String(row.name), "ArmyRow_%s" % f.b.id.validate_node_name(), "named as UX-3's rows are")
	assert_eq((row.find_child("UnitStrip", true, false) as UnitStrip).chips().size(), 2)
	assert_true(board.find_child("ForecastHint", true, false) != null, "until you drag, the box says how")
	assert_true(String((board.find_child("ForecastHint", true, false) as Label).text).begins_with("Drag fighters between your armies"))
	map.free()


func test_a_lone_army_of_one_fighter_has_no_armies_here_to_manage() -> void:
	var s := Kit.game()
	Kit.crown(s).units.clear()
	Kit.crown(s).commander = null
	var one := Kit.army(s, CROWN, "westwatch", ["spearmen"])
	var map := _map(s)
	map.select_army(one.id)
	assert_true(_board(map) == null, "nothing to split and nobody to merge with")
	map.free()


func test_a_rulers_army_is_greyed_with_its_reason_and_its_card_has_no_board() -> void:
	var s := Kit.game("rulers")
	var ruler := RulerRules.ruler_army(s, CROWN)
	var map := _map(s)
	map.select_army("kingdom-1")
	var board := _board(map)
	assert_true(board != null)
	var row := board.rows[ruler.id] as MusterBoard.Row
	assert_true(row.greyed, "the ruler's army is greyed")
	assert_true(_texts(row).any(func(t): return String(t).contains("A ruler travels alone")), "with its reason")
	assert_false(row._can_drop_data(Vector2.ZERO, {"kind": "muster", "from": "kingdom-1", "units": [0], "commander": false}), "nothing can be dropped on it")
	assert_eq(row.partner_check, null, "and it can't be a partner")
	assert_ne(board.partner_id, ruler.id)
	# Its own card lists the others and says why it has no muster.
	map.select_army(ruler.id)
	assert_true(_board(map) == null)
	assert_true(_node(map.details, "RulerAlone") != null)
	map.free()


# --- dragging ---------------------------------------------------------------------------------------------------------

func test_dragging_fighters_to_new_army_forecasts_then_orders_a_split() -> void:
	var f := _two_armies()
	var map: MapScreen = f.map
	var a: Army = f.a
	var card := _card(map)
	var board := _board(map)
	var chips: Array = card.strip.chips()  # the commander first, then the units
	assert_true(chips[0].is_commander and chips.size() == 4)
	var data = _grab(chips[1])  # the Spearmen
	assert_eq(data, {"kind": "muster", "from": a.id, "units": [0], "commander": false})
	# The pointer over New army: the forecast shows before anything is ordered.
	assert_true(board.new_zone._can_drop_data(Vector2.ZERO, data), "a drop on New army is allowed")
	assert_eq(map.orders.orders(), [], "nothing is ordered yet")
	var lines := _texts(board.forecast_lines)
	assert_true(lines.any(func(t): return String(t).contains("If you order this")), "the forecast is up: %s" % [lines])
	assert_true(lines.any(func(t): return String(t).contains("becomes")), "each army before and after: %s" % [lines])
	assert_true(lines.any(func(t): return String(t).contains("a new army:")), "the new army is new: %s" % [lines])
	# The drop gives the order.
	board.new_zone._drop_data(Vector2.ZERO, data)
	var queued := map.orders.orders()
	assert_eq(queued.size(), 1)
	assert_true(queued[0] is MusterOrder and queued[0].to_army.is_empty() and queued[0].units == [0])
	assert_eq(map.orders.order_text(0), "Split Spearmen from the Crown's 1st into a new army, the Crown's 3rd, at Crownkeep.", "listed with its sentence")
	# The card was rebuilt: the new army is a row, and the old one has one unit fewer.
	var after := _board(map)
	assert_true(after.rows.has("kingdom-3"), "the Crown's 3rd is there with its real id")
	assert_eq(_card(map).strip.chips().size(), 3, "this army's portraits: the commander and two units")
	assert_true(String(map.status_text).begins_with("Split Spearmen from the Crown's 1st"), map.status_text)
	map.free()


func test_a_drop_the_rules_refuse_says_why_in_the_order_books_words() -> void:
	var f := _two_armies()
	var map: MapScreen = f.map
	var b: Army = f.b
	b.commander = Unit.new(f.state.find_faction(CROWN).commander_type, CROWN)  # a second commander
	map.set_state(f.state, CROWN)
	map.select_army(f.a.id)
	var board := _board(map)
	var commander_chip: UnitStrip.Chip = _card(map).strip.chips()[0]
	var data = _grab(commander_chip)
	assert_eq(data.commander, true)
	var row := board.rows[b.id] as MusterBoard.Row
	assert_false(row._can_drop_data(Vector2.ZERO, data), "the Crown's 2nd already has a commander")
	var refusal := _texts(board.forecast_lines)
	var why := String(OrderBook.check_order(f.state, CROWN, MusterOrder.transfer(f.a.id, b.id, [], true), []).get("reason", ""))
	assert_eq(refusal, [why], "the forecast's words are the order book's")
	board.drop(data, b.id)
	assert_eq(map.orders.orders(), [], "and no order was queued")
	assert_eq(map.status_text, why)
	assert_true(board.message.visible and board.message.text == why)
	map.free()


func test_dropping_on_a_portrait_of_the_target_row_drops_on_the_row() -> void:
	var f := _two_armies()
	var map: MapScreen = f.map
	var board := _board(map)
	var row := board.rows[f.b.id] as MusterBoard.Row
	var target_chip: UnitStrip.Chip = row.strip.chips()[0]
	var data = _grab(_card(map).strip.chips()[1])
	assert_true(target_chip._can_drop_data(Vector2.ZERO, data), "a portrait hands the drop to its row")
	target_chip._drop_data(Vector2.ZERO, data)
	assert_eq(map.orders.orders().size(), 1)
	assert_eq(map.orders.orders()[0].to_army, f.b.id)
	map.free()


func test_ticked_portraits_move_together() -> void:
	var f := _two_armies()
	var map: MapScreen = f.map
	var chips: Array = _card(map).strip.chips()
	_click(chips[1])
	_click(chips[3])
	assert_true(chips[1].picked and chips[3].picked and not chips[2].picked, "a click ticks a portrait")
	var data = _grab(chips[1])
	assert_eq(data.units, [0, 2], "dragging a ticked portrait takes every ticked one of its army")
	assert_eq(_grab(chips[2]).units, [1], "an unticked portrait drags alone")
	_click(chips[3])
	assert_false(chips[3].picked, "a second click unticks it")
	map.free()


# --- the buttons ----------------------------------------------------------------------------------------------------------

func test_split_splits_the_ticked_fighters_or_the_back_half() -> void:
	var f := _two_armies()
	var map: MapScreen = f.map
	var board := _board(map)
	var order := board.button_order("split")
	assert_true(order is MusterOrder and order.units == [2], "nothing ticked: the back half of three units is one")
	var chips: Array = _card(map).strip.chips()
	_click(chips[1])
	_click(chips[0])
	order = _board(map).button_order("split")
	assert_eq(order.units, [0])
	assert_true(order.commander, "the commander ticked goes too")
	# Hovering the button previews it; pressing it orders it.
	board.split_button.mouse_entered.emit()
	assert_true(_texts(board.forecast_lines).any(func(t): return String(t).contains("If you order this")))
	board.split_button.mouse_exited.emit()
	assert_true(_texts(board.forecast_lines).any(func(t): return String(t).begins_with("Drag fighters")), "the hint comes back")
	board.split_button.pressed.emit()
	var queued := map.orders.orders()
	assert_eq(queued.size(), 1)
	assert_eq(queued[0].units, [0])
	assert_true(queued[0].commander)
	map.free()


func test_merge_all_and_swap_commanders_work_between_this_army_and_its_partner() -> void:
	var f := _two_armies()
	var s: GameState = f.state
	var third := Kit.army(s, CROWN, "crownkeep", ["knights"], "knight_captain")
	var map := _map(s)
	map.select_army(f.a.id)
	var board := _board(map)
	assert_eq(board.partner_id, f.b.id, "the first other army is the partner to begin with")
	assert_true(board.merge_button.text.contains("the Crown's 2nd"), "the buttons name the partner: %s" % board.merge_button.text)
	assert_true(board.swap_button.disabled, "the partner has no commander to swap: %s" % board.swap_button.tooltip_text)
	assert_true(String(board.swap_button.tooltip_text).contains("has no commander"), board.swap_button.tooltip_text)
	board.set_partner(third.id)
	assert_eq(board.partner_id, third.id)
	assert_false(board.swap_button.disabled, "a partner with a commander can swap")
	assert_true((board.rows[third.id] as MusterBoard.Row).partner_check.button_pressed)
	assert_false((board.rows[f.b.id] as MusterBoard.Row).partner_check.button_pressed)
	board.swap_button.pressed.emit()
	assert_true(map.orders.orders()[0] is MusterOrder and map.orders.orders()[0].kind == "swap")
	assert_eq(map.orders.order_text(0), "Swap the commanders of the Crown's 1st and the Crown's 3rd at Crownkeep.")
	map.cancel_order(0)
	var again := _board(map)
	assert_eq(again.partner_id, third.id, "the partner is remembered across the rebuild")
	again.merge_button.pressed.emit()
	assert_eq(map.orders.orders()[0].kind, "merge")
	assert_eq(map.orders.orders()[0].to_army, third.id)
	map.free()


func test_a_button_the_rules_refuse_is_disabled_with_the_reason() -> void:
	var s := Kit.game()
	var a := Kit.crown(s)
	a.units.resize(1)
	a.commander = null
	var map := _map(s)
	map.select_army(a.id)
	var board := _board(map)
	assert_true(board == null, "one fighter and no one beside it: no board")
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen"])
	map.set_state(s, CROWN)
	map.select_army(a.id)
	board = _board(map)
	assert_true(board.split_button.disabled, "a single fighter can't be split")
	assert_true(String(board.split_button.tooltip_text).contains("can't be split"), board.split_button.tooltip_text)
	assert_false(board.merge_button.disabled)
	assert_true(board.swap_button.disabled)
	assert_eq(b.location, "crownkeep")
	map.free()


# --- engines ------------------------------------------------------------------------------------------------------------

func test_the_engines_stepper_sends_engines_with_the_next_split() -> void:
	var s := Kit.game("sieges")
	var a := Kit.crown(s)
	a.engines = 2
	var map := _map(s)
	map.select_army(a.id)
	var board := _board(map)
	assert_true(board.engines_row != null, "an army that carries engines has the stepper")
	assert_true(board.engines_label.text.contains("0 of 2"), board.engines_label.text)
	(_node(board, "EnginesMore") as Button).pressed.emit()
	(_node(board, "EnginesMore") as Button).pressed.emit()
	(_node(board, "EnginesMore") as Button).pressed.emit()
	assert_true(board.engines_label.text.contains("2 of 2"), "never more than the army has: %s" % board.engines_label.text)
	(_node(board, "EnginesLess") as Button).pressed.emit()
	assert_true(board.engines_label.text.contains("1 of 2"))
	assert_eq(board.button_order("split").engines, 1)
	board.split_button.pressed.emit()
	var order: MusterOrder = map.orders.orders()[0]
	assert_eq(order.engines, 1, "the engine goes with the split")
	var plain := _two_armies("m1")
	assert_true(_board(plain.map).engines_row == null, "no stepper where no engines are carried")
	plain.map.free()
	map.free()


## ARM-1 (director's fix round): the stepper can send engines on their own, to the partner army that carries them from then on.
func test_the_engines_stepper_can_send_engines_alone_to_the_partner_army() -> void:
	var s := Kit.game("sieges")
	var a := Kit.crown(s)
	a.engines = 2
	var b := Kit.army(s, CROWN, "crownkeep", ["crossbowmen", "crossbowmen"])
	var map := _map(s)
	map.select_army(a.id)
	var board := _board(map)
	var send := _node(board, "SendEnginesButton") as Button
	assert_true(send.disabled, "at 0 of 2 there is nothing to send")
	assert_true(send.tooltip_text.contains("stepper"), "and the tooltip says what to do: %s" % send.tooltip_text)
	assert_eq(board.button_order("engines"), null)
	(_node(board, "EnginesMore") as Button).pressed.emit()
	assert_false(send.disabled, "one engine on the stepper, a partner to carry it: it can be sent")
	var order: MusterOrder = board.button_order("engines")
	assert_true(order != null and order.units.is_empty() and not order.commander and order.engines == 1 and order.to_army == b.id, "an engines-only transfer to the partner")
	send.mouse_entered.emit()
	var shown := _texts(board.forecast_lines)
	assert_true(shown.any(func(t): return String(t).contains("If you order this")) and shown.any(func(t): return String(t).contains("2 engines") and String(t).contains("1 engine")),
		"the forecast shows the engines on both armies while the pointer is over it: %s" % [shown])
	send.pressed.emit()
	var ordered: Array = map.orders.orders()
	assert_eq(ordered.size(), 1)
	assert_true(ordered[0] is MusterOrder and ordered[0].units.is_empty() and ordered[0].engines == 1, "the order is in the plan")
	var after := map.board_state()
	assert_eq([after.find_army(a.id).engines, after.find_army(b.id).engines], [1, 1], "the projected board has the engine on the partner")
	assert_eq(after.armies.size(), s.armies.size(), "no army was formed")
	# An army with no partner here can send no engines, and says so.
	var alone := Kit.game("sieges")
	Kit.crown(alone).engines = 1
	var map2 := _map(alone)
	map2.select_army("kingdom-1")
	var board2 := _board(map2)
	(_node(board2, "EnginesMore") as Button).pressed.emit()
	var send2 := _node(board2, "SendEnginesButton") as Button
	assert_true(send2.disabled and send2.tooltip_text.contains("no other army"), send2.tooltip_text)
	# An army with no engines has no such button.
	var plain := _two_armies("m1")
	assert_true(_board(plain.map).find_children("SendEnginesButton", "", true, false).is_empty(), "no engines, no button")
	plain.map.free()
	map2.free()
	map.free()


# --- the new army is an army --------------------------------------------------------------------------------------------

func test_a_new_army_can_be_selected_marched_and_cancelled() -> void:
	var f := _two_armies()
	var map: MapScreen = f.map
	var board := _board(map)
	board.new_zone._drop_data(Vector2.ZERO, _grab(_card(map).strip.chips()[1]))
	assert_true(String(map.status_text).contains("Cancel muster"), "the status line names the card's button: %s" % map.status_text)
	var new_id := "kingdom-3"
	(_board(map).rows[new_id] as MusterBoard.Row).name_button.pressed.emit()
	assert_eq(map.selected_army_id, new_id, "the new army is selected by its real id")
	var card := _card(map)
	assert_eq(card.army_id, new_id)
	assert_true(card.march_button != null and not card.march_button.disabled, "it can march this turn")
	map.select_province("westwatch")  # the two-click move
	var orders := map.orders.orders()
	assert_eq(orders.size(), 2, "a split and the new army's move: %s" % [map.status_text])
	assert_true(orders[1] is MoveOrder and orders[1].army_id == new_id)
	assert_true(String(map.orders.order_text(1)).contains("Westwatch"), map.orders.order_text(1))
	# The card of the new army lists the muster that formed it, with a cancel.
	assert_eq(_card(map).order_indexes(map.board_army(new_id)), [0, 1], "its own orders include the split that formed it and its march")
	# The card says which cancel is which: one for the muster, one for the march.
	var cancels: Array = _card(map).cancel_buttons.map(func(b): return String(b.text))
	assert_eq(cancels, ["Cancel muster", "Cancel order"], "two cancels, told apart")
	# Cancelling the split takes the move with it, with the reason on the status line.
	map.cancel_order(0)
	assert_eq(map.orders.orders(), [], "the move of the army that no longer exists went too")
	assert_true(String(map.status_text).contains("Order cancelled"), map.status_text)
	assert_true(String(map.status_text).contains("removed"), map.status_text)
	map.free()


func test_the_orders_list_shows_the_muster_with_its_sentence_and_a_cancel() -> void:
	var f := _two_armies()
	var map: MapScreen = f.map
	_board(map).button_order("split")
	_board(map).split_button.pressed.emit()
	map.show_orders()
	var lines := map.details.find_children("OrderLine", "", true, false)
	assert_eq(lines.size(), 1)
	assert_true(String((lines[0] as Label).text).begins_with("Split "), (lines[0] as Label).text)
	assert_true(String((lines[0] as Label).tooltip_text).contains("becomes"), "the tooltip is the forecast")
	(_node(map.details, "CancelButton") as Button).pressed.emit()
	assert_eq(map.orders.orders(), [])
	map.free()


func test_the_fort_panel_lists_an_army_a_muster_forms_so_it_can_sally() -> void:
	var s := FortTest.besieged_keep()
	var map := _map(s)
	map.select_province("stonegate")
	assert_eq(map.queue_muster(MusterOrder.transfer("kingdom-3", "", [0, 1, 2, 3])), "", "split the garrison")
	var fort := _node(map.details, "FortSection")
	var tick := _node(fort, "SallyTick_kingdom-20") as BaseButton
	assert_true(tick != null, "the new army has its sally tick")
	assert_false(tick.disabled, "and it may sally: %s" % tick.tooltip_text)
	tick.button_pressed = true
	var sallies := map.orders.orders().filter(func(o): return o is SiegeOrder)
	assert_eq(sallies.size(), 1)
	assert_true(sallies[0].is_sally() and sallies[0].army_id == "kingdom-20", "the sally of the Crown's 20th, an army that exists only in the plan")
	assert_true(String(map.orders.order_text(map.orders.orders().size() - 1)).begins_with("Sally out of Stonegate"), map.orders.order_text(map.orders.orders().size() - 1))
	# Cancelling the split takes the sally with it.
	map.cancel_order(0)
	assert_eq(map.orders.orders(), [], "the sally of an army that no longer exists went too")
	map.free()


func test_the_controllers_projected_board_is_rebuilt_on_every_change_of_the_plan() -> void:
	var s := Kit.game("rulers")
	var c := OrdersController.new(s, CROWN)
	assert_eq(c.view_state(), s, "nothing queued: the state itself")
	assert_eq(c.queue_muster(MusterOrder.transfer("kingdom-1", "", [0])), "")
	var one := c.view_state()
	assert_true(one != s and one.find_army("kingdom-3") != null, "a queued muster projects the board")
	assert_eq(c.view_state(), one, "unchanged plan: the same board, not rebuilt")
	assert_eq(c.queue_muster(MusterOrder.transfer("kingdom-1", "", [0])), "")
	var two := c.view_state()
	assert_true(two != one and two.find_army("kingdom-4") != null, "another muster: rebuilt")
	assert_eq(c.queue_move("kingdom-4", "westwatch"), "", "a move for the second new army")
	assert_eq(c.view_state(), two, "a move changes neither the sacrifice nor the musters: the same board")
	c.cancel(0)  # the first muster: the second one's new army is now the 3rd, and its move goes
	var three := c.view_state()
	assert_true(three != two and three.find_army("kingdom-4") == null and three.find_army("kingdom-3") != null, "a cancel: rebuilt")
	assert_true(c.last_removed().any(func(t): return String(t).begins_with("Move to Westwatch removed")), "%s" % [c.last_removed()])
	c.cancel(0)
	assert_eq(c.view_state(), s, "no muster left: the state itself again")
	# A sacrifice projects too, and a muster on top of it.
	var mandate := ""
	for m in RulerRules.available_mandates(CROWN, s):
		if RulerRules.sacrifice_check(s, CROWN, String(m)).is_empty():
			mandate = String(m)
			break
	if not mandate.is_empty():
		assert_eq(c.queue_sacrifice(mandate), "")
		var sac := c.view_state()
		assert_true(sac != s)
		assert_eq(c.queue_muster(MusterOrder.transfer("kingdom-1", "", [0])), "")
		var both := c.view_state()
		assert_true(both != sac and both.find_army("kingdom-3") != null and both.find_faction(CROWN).kept_power == sac.find_faction(CROWN).kept_power)


func test_cards_read_the_board_the_plan_leaves() -> void:
	var f := _two_armies()
	var map: MapScreen = f.map
	assert_eq(map.board_state(), map.state, "no muster: the state itself")
	assert_eq(map.queue_muster(MusterOrder.transfer(f.a.id, "", [0])), "")
	assert_true(map.board_state() != map.state)
	assert_true(map.board_army("kingdom-3") != null and map.state.find_army("kingdom-3") == null)
	map.select_army("kingdom-3")
	assert_eq(map.cards.mode, "army")
	# The province card lists the new army too.
	map.select_province("crownkeep")
	assert_true(map.details.find_children("ArmyRow_kingdom-3", "", true, false).size() >= 1, "the province card shows it")
	map.free()
