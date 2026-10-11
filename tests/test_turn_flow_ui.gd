extends "res://tests/test_case.gd"
## Tests for the hotseat UI pieces of #7: the handoff screen and the turn report panel, driven by a
## real GameSession. Components build their children in code, so they are tested outside the tree.

const HANDOFF_SCENE := "res://ui/handoff_screen.tscn"
const REPORT_SCENE := "res://ui/turn_report_panel.tscn"
const RAW_IDS := ["kingdom", "beasts", "crownkeep", "fangridge", "westwatch", "ebonpeak", "stonegate",
	"blackwood", "deepwood", "wildmoor", "knight_captain", "warchief", "spearmen", "tuskers", "-1", "-2"]


# --- fixtures -------------------------------------------------------------------------------------

func _session(game_seed: int = 7) -> GameSession:
	var session := GameSession.new(GameState.new(game_seed), ["kingdom", "beasts"], game_seed, StubBattleResolver.new())
	assert_eq(session.setup_errors(), [], "session starts")
	return session


func _handoff() -> HandoffScreen:
	var screen := load(HANDOFF_SCENE).instantiate() as HandoffScreen
	assert_true(screen != null, "handoff scene instantiates as HandoffScreen")
	return screen


func _panel() -> TurnReportPanel:
	var panel := load(REPORT_SCENE).instantiate() as TurnReportPanel
	assert_true(panel != null, "report scene instantiates as TurnReportPanel")
	return panel


## Plays one full turn: seat 1 queues `first`, ends, the handoff screen is acknowledged with Ready,
## seat 2 queues `second` and ends. Each order is [army id, province] for a move or [unit type] to recruit.
func _play_turn_through_ui(session: GameSession, screen: HandoffScreen, first: Array, second: Array) -> void:
	_queue_all(session, first)
	assert_eq(session.end_turn(), "")
	assert_true(screen.show_for(session), "handoff screen opens between seats")
	screen.ready_button.pressed.emit()
	assert_eq(session.phase(), GameSession.Phase.ORDERS, "Ready starts the next player's orders")
	_queue_all(session, second)
	assert_eq(session.end_turn(), "")


func _queue_all(session: GameSession, orders: Array) -> void:
	for o in orders:
		var why: String = session.queue_move(o[0], o[1]) if o.size() == 2 else session.queue_recruit(o[0])
		assert_eq(why, "", "order %s accepted" % [o])


func _visible_text(node: Node) -> String:
	var out := PackedStringArray()
	_collect_text(node, out)
	return "\n".join(out)


func _collect_text(node: Node, out: PackedStringArray) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	if node is Control and not (node as Control).tooltip_text.is_empty():
		out.append((node as Control).tooltip_text)
	for c in node.get_children():
		_collect_text(c, out)


func _assert_no_raw_ids(text: String, what: String) -> void:
	assert_false(text.is_empty(), "%s has text" % what)
	for id in RAW_IDS:
		assert_false(text.contains(id), "%s shows no raw id '%s': %s" % [what, id, text])


# --- handoff screen -------------------------------------------------------------------------------

func test_handoff_screen_hides_orders_names_next_player_and_ready_advances() -> void:
	var session := _session()
	var screen := _handoff()
	assert_false(screen.visible, "hidden until a handoff")
	assert_false(screen.show_for(session), "no handoff during seat 1's orders")
	assert_false(screen.visible)

	_queue_all(session, [["kingdom-1", "westwatch"], ["spearmen"]])
	var kingdom_orders: Array = session.current_order_texts()
	assert_eq(kingdom_orders.size(), 2)
	assert_eq(session.end_turn(), "")
	assert_eq(session.phase(), GameSession.Phase.HANDOFF)

	assert_true(screen.show_for(session))
	assert_true(screen.visible)
	# An opaque, full-screen cover that swallows input.
	var background := screen.get_node("Background") as ColorRect
	assert_eq(background.color.a, 1.0, "the cover is opaque")
	assert_eq([screen.anchor_left, screen.anchor_top, screen.anchor_right, screen.anchor_bottom], [0.0, 0.0, 1.0, 1.0])
	assert_eq(screen.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_eq(background.mouse_filter, Control.MOUSE_FILTER_STOP)

	var text := _visible_text(screen)
	var next_name := session.current_player_name()
	assert_eq(screen.title_label.text, "Pass to %s" % next_name)
	assert_true(text.contains(session.handoff_text()), "shows the session's handoff text")
	assert_true(screen.turn_label.text.contains("Turn 1"), screen.turn_label.text)
	for order_text in kingdom_orders:
		assert_false(text.contains(order_text), "the previous player's orders are hidden: %s" % order_text)
	_assert_no_raw_ids(text, "handoff screen")

	var heard := [0]
	screen.acknowledged.connect(func(): heard[0] += 1)
	screen.ready_button.pressed.emit()
	assert_eq(heard[0], 1, "acknowledged is emitted once")
	assert_eq(session.phase(), GameSession.Phase.ORDERS)
	assert_eq(session.current_player(), "beasts")
	assert_false(screen.visible, "the cover goes away after Ready")
	assert_false(screen.show_for(session), "no second handoff for the same seat")
	screen.free()


# --- turn report panel ----------------------------------------------------------------------------

func test_full_turn_through_ui_then_report_lists_every_event_and_focuses_provinces() -> void:
	var session := _session()
	var screen := _handoff()
	var panel := _panel()
	_play_turn_through_ui(session, screen,
		[["kingdom-1", "westwatch"], ["spearmen"]], [["beasts-1", "ebonpeak"], ["tuskers"]])

	# Back to seat 1, with the results waiting behind the cover.
	assert_eq(session.phase(), GameSession.Phase.HANDOFF)
	assert_true(screen.show_for(session))
	assert_true(screen.body_label.text.contains("Turn 1 is resolved"), screen.body_label.text)
	screen.ready_button.pressed.emit()
	assert_eq(session.current_player(), "kingdom")

	panel.show_report(session)
	var report := session.turn_report()
	var events: Array = report.events
	assert_true(events.size() >= 4, "turn 1 has moves, captures, recruits and income")
	assert_eq(panel.header_label.text, report.header)
	var rows := panel.event_rows()
	assert_eq(rows.size(), events.size(), "one row per event")
	# #55: each row reads as TurnReportText writes its event, in its display order (moves grouped by destination).
	var lines := TurnReportText.rows(events, session.state(), session.current_player())
	events = lines.map(func(r): return r.event)
	for i in events.size():
		assert_eq(rows[i].text, lines[i].text, "row %d is its event's line" % i)
		assert_eq(rows[i].get_meta("event"), events[i], "row %d carries its event" % i)
	var text := _visible_text(panel)
	for i in events.size():
		assert_true(text.contains(lines[i].text), "report shows: %s" % lines[i].text)
		assert_true(text.contains(TurnReportPanel.phase_title(events[i].phase)), "has a heading for %s" % events[i].phase)
	_assert_no_raw_ids(text, "turn report")

	# Headings group the rows: each heading comes right before the first event of its phase.
	var seen_phases := []
	for child in panel.rows_box.get_children():
		if child is Label:
			seen_phases.append(child.text)
	var expected_phases := []
	for e in events:
		var title := TurnReportPanel.phase_title(e.phase)
		if expected_phases.is_empty() or expected_phases.back() != title:
			expected_phases.append(title)
	assert_eq(seen_phases, expected_phases)

	# Clicking a row asks the map to focus that event's first province.
	var focused := []
	panel.province_focus_requested.connect(func(id: String): focused.append(id))
	var clicked := 0
	for i in events.size():
		if not events[i].provinces.is_empty():
			rows[i].pressed.emit()
			assert_eq(focused.back(), events[i].provinces[0], "focus for: %s" % events[i].text)
			clicked += 1
	assert_true(clicked > 0, "some events point at provinces")
	assert_eq(focused.size(), clicked)

	# No battles on turn 1, so no battle report buttons.
	assert_eq(session.battle_events(), [])
	assert_eq(panel.battle_buttons().size(), 0)
	assert_false(panel.victory_box.visible)
	screen.free()
	panel.free()


func test_only_battle_events_get_a_battle_report_button() -> void:
	var session := _session()
	var screen := _handoff()
	_play_turn_through_ui(session, screen, [["kingdom-1", "westwatch"]], [["beasts-1", "ebonpeak"]])
	assert_eq(session.acknowledge_handoff(), "")
	_play_turn_through_ui(session, screen, [["kingdom-1", "stonegate"]], [["beasts-1", "blackwood"]])
	assert_eq(session.acknowledge_handoff(), "")
	# Kingdom attacks Blackwood, where the beasts army holds.
	_play_turn_through_ui(session, screen, [["kingdom-1", "blackwood"]], [])

	var battles := session.battle_events()
	assert_eq(battles.size(), 1, "one battle at Blackwood")
	var panel := _panel()
	panel.show_report(session)
	assert_eq(panel.battle_buttons().size(), battles.size())

	var events: Array = session.turn_report().events
	var rows := panel.event_rows()
	for i in events.size():
		var is_battle: bool = GameSession.BATTLE_TYPES.has(events[i].type)
		assert_eq(rows[i].get_parent().get_child_count(), 3 if is_battle else 1,
			"Watch and Battle report only on battle rows: %s" % events[i].text)
	# M3-5: the stub resolver writes no log, so Watch is there but says why it can't play.
	assert_eq(panel.watch_buttons().size(), battles.size(), "every battle row has Watch")
	assert_true(panel.watch_buttons()[0].disabled, "a battle fought with the test rules can't be watched")
	assert_true(panel.watch_buttons()[0].tooltip_text.replace("\n", " ").contains(BattleHost.NO_LOG), panel.watch_buttons()[0].tooltip_text)

	var requested := []
	panel.battle_report_requested.connect(func(e: Dictionary): requested.append(e))
	panel.battle_buttons()[0].pressed.emit()
	assert_eq(requested.size(), 1)
	assert_eq(requested[0].text, battles[0].text)
	assert_eq(requested[0].provinces, battles[0].provinces)
	assert_true(_visible_text(panel).contains("Battle report"))
	_assert_no_raw_ids(_visible_text(panel), "turn report with a battle")
	screen.free()
	panel.free()


func test_game_over_event_is_shown_on_top_and_highlighted() -> void:
	var panel := _panel()
	var report := {"turn": 9, "header": "Turn 9 results", "events": [
		{"type": "army_moved", "phase": "movement", "text": "The Kingdom army marches to Westwatch.",
			"provinces": ["westwatch"], "codex": "", "numbers": {}},
		{"type": "game_over", "phase": "victory", "text": "The Thornmane Clans take the last capital and win.",
			"provinces": ["crownkeep"], "codex": "victory", "numbers": {}},
	]}
	panel.show_report_data(report)
	assert_true(panel.victory_box.visible, "the game-over banner is shown")
	assert_eq(panel.victory_label.text, "The Thornmane Clans take the last capital and win.")
	var box := panel.victory_box.get_parent()
	assert_true(box.get_children().find(panel.victory_box) < box.get_children().find(panel.scroll),
		"the banner sits above the event list")
	assert_eq(panel.event_rows().size(), 1, "the game-over event is not repeated in the list")
	assert_eq(panel.battle_buttons().size(), 0)

	panel.show_report_data({"turn": 0, "header": "No turns have been resolved yet.", "events": []})
	assert_false(panel.victory_box.visible, "re-showing clears the banner")
	assert_eq(panel.event_rows().size(), 0)
	assert_eq(panel.header_label.text, "No turns have been resolved yet.")
	panel.free()


# --- the turn flow through the Table (UX-1, #194) ---------------------------------------------------

## The whole turn through the real game screen: orders on the card, the seal, the handoff, the report through the ReportHost, and a
## report line that focuses its province on the card and closes the report.
func test_a_whole_turn_through_the_table_report_lines_focus_provinces_on_the_card() -> void:
	var game := load("res://ui/game_screen.tscn").instantiate() as GameScreen
	game.autosave_enabled = false
	game.start_game({"players": ["kingdom", "beasts"], "seed": 7})
	var opened := []
	var closed := []
	game.report_host.report_opened.connect(func(t: int): opened.append(t))
	game.report_host.report_closed.connect(func(t: int): closed.append(t))
	assert_true(game.report_button.disabled, "nothing to report yet")
	assert_eq(game.map.table().seal.is_ancestor_of(game.end_turn_button), true, "the seal holds End turn")
	game.map.select_army("kingdom-1")
	game.map.select_province("westwatch")
	game.end_turn_button.pressed.emit()
	assert_true(game.handoff.visible, "the cover is up between the players")
	game.handoff.ready_button.pressed.emit()
	game.session.queue_move("beasts-1", "ebonpeak")
	game.end_turn_button.pressed.emit()
	game.handoff.ready_button.pressed.emit()
	assert_eq(opened, [1], "the report opened once, through the host")
	assert_true(game.report_overlay.visible and game.report_host.is_open())
	var rows := game.report_panel.event_rows()
	var row: Button = null
	for r in rows:
		var event: Dictionary = r.get_meta("event")
		if not event.provinces.is_empty():
			row = r
			break
	assert_true(row != null, "a line that points at a province")
	var pid: String = (row.get_meta("event") as Dictionary).provinces[0]
	row.pressed.emit()
	assert_false(game.report_overlay.visible, "a line closes the report")
	assert_eq(closed, [1], "and the host heard it close")
	assert_eq(game.map.selected_province_id, pid, "it shows the province")
	assert_true(game.map.cards.visible, "on the card")
	var name_label := game.map.details.find_child("ProvinceName", true, false) as Label
	assert_true(name_label != null and name_label.text == game.map.state.find_province(pid).name, "with its name")
	game.report_button.pressed.emit()
	assert_eq(opened, [1, 1], "Turn report opens it again")
	game.free()
