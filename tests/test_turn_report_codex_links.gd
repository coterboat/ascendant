extends "res://tests/test_case.gd"
## Codex links in the turn report (#8): every event row whose "codex" key is a RulesCodex entry gets a
## small "?" button naming that entry, and pressing it emits codex_requested(key). Rows with a missing
## or unknown key get no button. The existing row and battle signals keep working.

const REPORT_SCENE := "res://ui/turn_report_panel.tscn"


func _panel() -> TurnReportPanel:
	var panel := load(REPORT_SCENE).instantiate() as TurnReportPanel
	assert_true(panel != null, "report scene instantiates as TurnReportPanel")
	return panel


func _report() -> Dictionary:
	return {"turn": 4, "header": "Turn 4 results", "events": [
		{"type": "army_moved", "phase": "movement", "text": "The Aurel Crown army moved to Westwatch.",
			"provinces": ["crownkeep", "westwatch"], "codex": "move", "numbers": {}},
		{"type": "battle", "phase": "battles", "text": "In Stonegate, Aurel Crown held against Thornmane Clans.",
			"provinces": ["stonegate"], "codex": "defended", "numbers": {}},
		{"type": "income", "phase": "income", "text": "Aurel Crown earned 12 gold.",
			"provinces": [], "codex": "no_such_entry", "numbers": {}},
		{"type": "income", "phase": "income", "text": "Thornmane Clans earned 12 gold.",
			"provinces": [], "codex": "", "numbers": {}},
		{"type": "game_over", "phase": "victory", "text": "Aurel Crown captured Fangridge and wins.",
			"provinces": ["fangridge"], "codex": "victory", "numbers": {}},
	]}


func _question_button(row_button: Button) -> Button:
	for c in row_button.get_parent().get_parent().get_children():
		if c is Button and c.text == "?":
			return c
	return null


func test_question_buttons_only_for_codex_keys_that_exist() -> void:
	var panel := _panel()
	panel.show_report_data(_report())
	var rows := panel.event_rows()
	assert_eq(rows.size(), 4, "the game-over event stays in the banner")
	var keys := panel.codex_buttons().map(func(b): return String(b.get_meta("codex_key")))
	assert_eq(keys, ["move", "defended"], "only rows with a real codex entry get a ?")
	assert_true(_question_button(rows[0]) != null, "move row has a ?")
	assert_true(_question_button(rows[1]) != null, "battle row has a ?")
	assert_eq(_question_button(rows[2]), null, "unknown key: no ?")
	assert_eq(_question_button(rows[3]), null, "no key: no ?")
	for b in panel.codex_buttons():
		var key := String(b.get_meta("codex_key"))
		assert_eq(b.text, "?")
		assert_true(b.tooltip_text.contains(String(RulesCodex.entry(key).title)), "the tooltip names the entry: %s" % b.tooltip_text)
		assert_false(b.tooltip_text.contains("_"), "the tooltip shows the title, not a raw key")
	# The battle row keeps its "Battle report" button next to the event, with M3-5's Watch beside it.
	assert_eq(rows[1].get_parent().get_child_count(), 3)
	assert_eq(panel.battle_buttons().size(), 1)
	panel.free()


func test_question_button_emits_codex_requested_with_the_event_key() -> void:
	var panel := _panel()
	panel.show_report_data(_report())
	var asked := []
	var focused := []
	var battles := []
	panel.codex_requested.connect(func(key: String): asked.append(key))
	panel.province_focus_requested.connect(func(id: String): focused.append(id))
	panel.battle_report_requested.connect(func(e: Dictionary): battles.append(e))
	for b in panel.codex_buttons():
		b.pressed.emit()
	assert_eq(asked, ["move", "defended"])
	assert_eq(focused, [], "a ? press does not move the map")
	assert_eq(battles, [], "a ? press does not open the battle report")
	# The existing signals still work.
	panel.event_rows()[0].pressed.emit()
	assert_eq(focused, ["crownkeep"])
	panel.battle_buttons()[0].pressed.emit()
	assert_eq(battles.size(), 1)
	assert_eq(asked.size(), 2)
	panel.free()


func test_real_turn_report_links_every_event_to_its_codex_entry() -> void:
	var session := GameSession.new(GameState.new(7), ["kingdom", "beasts"], 7, StubBattleResolver.new())
	assert_eq(session.queue_move("kingdom-1", "westwatch"), "")
	assert_eq(session.queue_recruit("spearmen"), "")
	assert_eq(session.end_turn(), "")
	assert_eq(session.acknowledge_handoff(), "")
	assert_eq(session.queue_move("beasts-1", "ebonpeak"), "")
	assert_eq(session.end_turn(), "")
	var panel := _panel()
	panel.show_report(session)
	var events: Array = session.turn_report().events
	assert_eq(panel.codex_buttons().size(), events.size(), "every resolver event names a codex entry")
	for i in events.size():
		var b := _question_button(panel.event_rows()[i])
		assert_true(b != null, "row %d has a ?" % i)
		if b:
			assert_eq(String(b.get_meta("codex_key")), events[i].codex)
	panel.free()


func test_reshowing_replaces_the_question_buttons() -> void:
	var panel := _panel()
	panel.show_report_data(_report())
	assert_eq(panel.codex_buttons().size(), 2)
	panel.show_report_data({"turn": 0, "header": "No turns have been resolved yet.", "events": []})
	assert_eq(panel.codex_buttons().size(), 0)
	panel.show_report_data(_report())
	assert_eq(panel.codex_buttons().size(), 2, "no buttons left over from the last report")
	panel.free()
