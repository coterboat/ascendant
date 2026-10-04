extends "res://tests/test_case.gd"
## Follow-up to #55: the map, the orders list, the forecasts, the tooltips, the ruler panel and the order
## checks call armies by the names the turn report uses (TurnReportText.army_name), never by their place
## ("the Aurel Crown army at Crownkeep") or by id. Numbers are read from each army's id in the state, never
## assumed: the game may hand out ids in any order.

const MAP_SCENE := "res://ui/map_screen.tscn"
const Policies := preload("res://tools/autoplay/policies.gd")


func _state(specs: Array, owners: Dictionary = {}) -> GameState:
	var s := GameState.new(99)
	s.armies.clear()
	for spec in specs:
		var a := Army.new()
		a.id = spec[0]
		a.owner = spec[1]
		a.location = spec[2]
		var f := s.find_faction(a.owner)
		for type_id in spec[3]:
			var ut := TurnResolver.recruitable_type(f, type_id)
			if ut.is_commander:
				a.commander = Unit.new(ut, f.id)
			else:
				a.units.append(Unit.new(ut, f.id))
		s.armies.append(a)
	for pid in owners:
		s.find_province(pid).owner = owners[pid]
	return s


## The name the turn report gives `army`, read from the state.
func _name(s: GameState, army: Army) -> String:
	return TurnReportText.army_name(s, army.id)


func _crown_army(s: GameState) -> Army:
	return s.armies.filter(func(a): return a.owner == "kingdom" and a.ruler == null)[0]


func _open(state: GameState, faction_id: String = "kingdom") -> MapScreen:
	var screen: MapScreen = load(MAP_SCENE).instantiate()
	screen.set_state(state, faction_id)
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	return screen


func _close(screen: MapScreen) -> void:
	screen.get_parent().remove_child(screen)
	screen.free()


## Every text and tooltip under `node`.
func _texts(node: Node, out: Array = []) -> Array:
	if node is Label or node is Button:
		out.append(node.text)
	if node is Control and not String(node.tooltip_text).is_empty():
		out.append(node.tooltip_text)
	if node is RichTextLabel:
		out.append(node.text)
	for c in node.get_children():
		_texts(c, out)
	return out


func _assert_no_place_names_or_ids(texts: Array, what: String) -> void:
	var army_ids := RegEx.create_from_string("\\b(kingdom|beasts)-\\d+\\b")
	var by_place := RegEx.create_from_string("(Aurel Crown|Thornmane Clans) (army|ruler [^.]+?) at ")
	for t in texts:
		assert_true(army_ids.search(String(t)) == null, "%s: no army id in: %s" % [what, t])
		assert_true(by_place.search(String(t)) == null, "%s: no army named by its place in: %s" % [what, t])
		assert_false(String(t).contains("no longer exists"), "%s: %s" % [what, t])


# --- the title the map and the orders use -----------------------------------------------------------

func test_an_army_title_is_its_report_name_its_fighters_and_its_place() -> void:
	var s := GameState.with_rulers(3)
	var crown := _crown_army(s)
	var units := TurnReportText.units_phrase(TurnReportText._army_entries(crown))
	assert_eq(TurnReportText.army_title(s, crown), "%s (%s) at Crownkeep" % [_name(s, crown), units])
	assert_eq(TurnReportText.army_title(s, crown, false), "%s (%s)" % [_name(s, crown), units])
	assert_true(_name(s, crown).begins_with("the Crown's "), _name(s, crown))
	var king := RulerRules.ruler_army(s, "kingdom")
	assert_eq(TurnReportText.army_title(s, king), "%s (ruler of the Aurel Crown) at Crownkeep" % RulerRules.current_name(s, "kingdom"))
	assert_eq(_name(s, king), RulerRules.current_name(s, "kingdom"), "a ruler's army goes by its ruler, as in the report")
	assert_eq(crown.get_description(s), TurnReportText.army_title(s, crown), "Army.get_description() says the same")


# --- the map's army panel -------------------------------------------------------------------------

func test_the_army_panel_names_armies_as_the_turn_report_does() -> void:
	var s := GameState.with_rulers(5)
	var screen := _open(s)
	screen.select_province("crownkeep")
	var headers := []
	for a in s.armies.filter(func(x): return x.location == "crownkeep"):
		var panel := screen.details.find_child("Army_%s" % a.id.validate_node_name(), true, false)
		assert_true(panel != null, "the army is listed")
		var header := panel.find_child("ArmyHeader", true, false) as Button
		assert_eq(header.text, RulerRules._cap(TurnReportText.army_title(s, a)))
		assert_true(header.text.to_lower().begins_with(_name(s, a).to_lower()), "the header starts with the report's name: %s" % header.text)
		headers.append(header.text)
	assert_eq(headers.size(), 2, "the starting army and the ruler's army")
	_assert_no_place_names_or_ids(_texts(screen.details), "the side panel")
	_close(screen)


func test_tooltips_that_name_an_army_use_its_name() -> void:
	var s := GameState.new(5)
	var crown := _crown_army(s)
	assert_eq(String(Breakdown.army_units(s, crown.id).title), "Units in %s" % _name(s, crown))
	assert_eq(String(Breakdown.army_strength(s, crown.id).title), "Strength of %s" % _name(s, crown))
	var rulers := GameState.with_rulers(5)
	var king := RulerRules.ruler_army(rulers, "kingdom")
	assert_true(RulerPanel.summary(rulers, king).begins_with(RulerRules._cap(TurnReportText.army_title(rulers, king))), RulerPanel.summary(rulers, king))
	# The province badges' tooltips.
	var screen := _open(rulers)
	var texts := []
	for pid in ["crownkeep", "fangridge"]:
		texts.append_array(_texts(screen.regions[pid].army_box))
	assert_true(texts.size() >= 4, "both capitals show their armies")
	_assert_no_place_names_or_ids(texts, "the badges")
	_close(screen)


# --- the orders list, forecasts and order checks --------------------------------------------------

func test_the_orders_list_and_forecasts_name_the_army() -> void:
	var s := GameState.new(5)
	var crown := _crown_army(s)
	var title := RulerRules._cap(TurnReportText.army_title(s, crown, false))
	var f := Forecast.move(s, "kingdom", MoveOrder.new(crown.id, "westwatch"))
	assert_true(f.text.begins_with("%s moves from Crownkeep to Westwatch and is there at the start of turn %d." % [title, s.current_turn + 2]), f.text)
	var session := GameSession.new(s, ["kingdom", "beasts"], 5, StubBattleResolver.new())
	assert_eq(session.describe_order("kingdom", MoveOrder.new(crown.id, "westwatch")), "Move %s from Crownkeep to Westwatch." % TurnReportText.army_title(s, crown, false))
	# An order for an army that isn't there says so the way the order check does.
	var gone := session.describe_order("kingdom", MoveOrder.new("kingdom-999", "westwatch"))
	assert_eq(gone, "Move an army that is not on the map to Westwatch.")
	# The map's orders list shows the forecast for each queued move.
	var screen := _open(s)
	screen.select_army(crown.id)
	assert_eq(screen.queue_move(crown.id, "westwatch"), "")
	var line := screen.details.find_child("OrderLine", true, false) as Label
	assert_true(line != null and line.text.begins_with(title), line.text if line else "no order line")
	_assert_no_place_names_or_ids(_texts(screen.details) + [screen.preview_move("highcrag")], "orders and preview")
	_close(screen)


func test_road_moves_name_the_army_too() -> void:
	var s := GameState.with_rulers(3, {"kingdom": "regents_court"})  # King's Roads
	var crown := _crown_army(s)
	s.find_province("westwatch").owner = "kingdom"
	s.find_province("stonegate").owner = "kingdom"
	var road := MoveOrder.new(crown.id, "stonegate", "westwatch")
	var f := Forecast.move(s, "kingdom", road)
	assert_true(f.ok, f.get("reason", ""))
	assert_true(f.text.begins_with("%s moves by the King's Roads through Westwatch and is at Stonegate" % RulerRules._cap(TurnReportText.army_title(s, crown, false))), f.text)
	var session := GameSession.new(s, ["kingdom", "beasts"], 3, StubBattleResolver.new())
	assert_eq(session.describe_order("kingdom", road), "Move %s from Crownkeep to Stonegate by the King's Roads through Westwatch." % TurnReportText.army_title(s, crown, false))


func test_order_checks_name_the_army() -> void:
	var s := _state([["kingdom-4", "kingdom", "crownkeep", ["spearmen"]], ["beasts-7", "beasts", "fangridge", ["tuskers"]]])
	var crown := s.find_army("kingdom-4")
	var clans := s.find_army("beasts-7")
	var book := OrderBook.new()
	assert_eq(book.submit(s, "kingdom", MoveOrder.new(crown.id, "westwatch")), "")
	var reasons := [
		book.submit(s, "kingdom", MoveOrder.new(crown.id, "highcrag")),  # a second move
		TurnResolver.check_move(s, "kingdom", MoveOrder.new(crown.id, "crownkeep")).reason,  # already there
		TurnResolver.check_move(s, "kingdom", MoveOrder.new(clans.id, "ebonpeak")).reason,  # not yours
		TurnResolver.check_move(s, "kingdom", MoveOrder.new(crown.id, "stonegate", "westwatch")).reason,  # no King's Roads
	]
	_assert_no_place_names_or_ids(reasons, "order checks")
	assert_eq(reasons[0], "%s already has a move order this turn. Each army moves once per turn." % RulerRules._cap(_name(s, crown)))
	assert_eq(reasons[1], "%s is already in Crownkeep. To stay put, give it no move order." % RulerRules._cap(_name(s, crown)))
	assert_eq(reasons[2], "%s at Fangridge belongs to Thornmane Clans, not to Aurel Crown." % RulerRules._cap(_name(s, clans)))
	assert_true(reasons[3].contains("so %s can't go through Westwatch to Stonegate." % _name(s, crown)), reasons[3])
	# The turn report still reads them cleanly.
	var r := TurnResolver.resolve(s, {"kingdom": [MoveOrder.new(crown.id, "westwatch"), MoveOrder.new(crown.id, "highcrag")]}, 1, StubBattleResolver.new())
	var rejected: Array = TurnReportText.rows(r.events, r.new_state).filter(func(x): return x.event.type == "order_rejected")
	assert_eq(rejected[0].text, "The order to move %s (Spearmen) to Highcrag was rejected: Each army moves once per turn, and %s already had a move order. It followed its first order, to Westwatch." % [
		_name(s, crown), _name(s, crown)])


# --- the battle report viewer -----------------------------------------------------------------------

func test_the_battle_report_viewer_names_each_army_and_where_it_came_from() -> void:
	var s := _state([["kingdom-1", "kingdom", "thornvale", ["crossbowmen"]], ["beasts-2", "beasts", "wildmoor", ["fangthrowers"]],
		["kingdom-3", "kingdom", "stonegate", ["knights"]], ["beasts-5", "beasts", "ebonpeak", ["tuskers"]]],
		{"thornvale": "kingdom", "wildmoor": "beasts", "stonegate": "kingdom", "ebonpeak": "beasts"})
	var r := TurnResolver.resolve(s, {"kingdom": [MoveOrder.new("kingdom-1", "wildmoor"), MoveOrder.new("kingdom-3", "blackwood")],
		"beasts": [MoveOrder.new("beasts-2", "thornvale"), MoveOrder.new("beasts-5", "blackwood")]}, 2026, AutoBattleResolver.new())
	var viewer := load("res://ui/battle_report_viewer.tscn").instantiate() as BattleReportViewer
	var border: Dictionary = r.events.filter(func(e): return e.type == "border_battle")[0]
	viewer.show_event(border, r.new_state)
	var texts := _texts(viewer)
	assert_true(texts.has("Army: %s (Crossbowmen), from Thornvale" % TurnReportText.army_name(r.new_state, "kingdom-1")), "\n".join(texts))
	assert_true(texts.has("Army: %s (Fangthrowers), from Wildmoor" % TurnReportText.army_name(r.new_state, "beasts-2")), "\n".join(texts))
	var battle: Dictionary = r.events.filter(func(e): return e.type == "battle")[0]
	viewer.show_event(battle, r.new_state)
	texts = _texts(viewer)
	assert_true(texts.has("Army: %s (Knights)" % TurnReportText.army_name(r.new_state, "kingdom-3")), "\n".join(texts))
	_assert_no_place_names_or_ids(texts.filter(func(t): return String(t).begins_with("Army:")), "the viewer's army lines")
	viewer.free()


# --- swap wording -----------------------------------------------------------------------------------

func test_border_battles_are_armies_that_tried_to_swap_places() -> void:
	for path in ["res://ui/battle/battle_simple_view.gd", "res://ui/victory_screen.gd", "res://ui/battle_report_viewer.gd",
			"res://rules/turn_report_text.gd", "res://rules/rules_codex.gd"]:
		var source := FileAccess.get_file_as_string(path)
		for old in ["swapped places", "while swapping places", "as they swapped"]:
			assert_false(source.contains(old), "%s still says '%s'" % [path, old])


# --- a whole game: nothing the player reads names an army by place or id ---------------------------

func test_a_played_game_names_armies_the_same_way_everywhere() -> void:
	for rulers in [false, true]:
		var start := GameState.with_rulers(77) if rulers else GameState.new(77)
		var session := GameSession.new(start, ["kingdom", "beasts"], 77, AutoBattleResolver.new())
		var ai := [Policies.make("ai"), Policies.make("ai")]
		var rngs := [SeededRNG.new(3), SeededRNG.new(4)]
		var texts := []
		for turn in 6:
			for seat in 2:
				if session.phase() == GameSession.Phase.HANDOFF:
					session.acknowledge_handoff()
				var fid := String(session.players()[seat])
				for o in ai[seat].orders(session.state(), fid, rngs[seat]):
					session.queue_order(o)
				texts.append_array(session.current_order_texts())
				for o in session.current_orders():
					if o is MoveOrder:
						texts.append(Forecast.move(session.state(), fid, o).text)
				session.end_turn()
			if session.is_over():
				break
			var st := session.state()
			for a in st.armies:
				texts.append(a.get_description(st))
				texts.append(String(Breakdown.army_units(st, a.id).title))
				if a.ruler != null:
					texts.append(RulerPanel.summary(st, a))
		assert_true(texts.size() > 20, "the game gave orders and had armies")
		_assert_no_place_names_or_ids(texts, "rulers" if rulers else "M1")


# --- the battle screen's plaques ------------------------------------------------------------------

func test_the_battle_screen_names_each_sides_armies() -> void:
	var s := _state([["kingdom-1", "kingdom", "thornvale", ["crossbowmen"]], ["beasts-2", "beasts", "wildmoor", ["fangthrowers"]]],
		{"thornvale": "kingdom", "wildmoor": "beasts"})
	var r := TurnResolver.resolve(s, {"kingdom": [MoveOrder.new("kingdom-1", "wildmoor")], "beasts": [MoveOrder.new("beasts-2", "thornvale")]},
		2026, AutoBattleResolver.new())
	var border: Dictionary = r.events.filter(func(e): return e.type == "border_battle")[0]
	var view := BattleSimpleView.new()
	assert_eq(view.play(border.numbers.log, border.numbers.report, r.new_state), "", "the battle plays")
	var tips := view.plaque_labels.map(func(l): return String(l.tooltip_text).replace("\n", " "))
	_assert_no_place_names_or_ids(tips, "the plaques")
	assert_true(tips.any(func(t): return t.contains("as both armies tried to swap places")), "\n".join(tips))
	assert_true(tips.any(func(t): return t.contains("%s (Crossbowmen): 1 fighter," % RulerRules._cap(TurnReportText.army_name(r.new_state, "kingdom-1")))), "\n".join(tips))
	view.free()
