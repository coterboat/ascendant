extends "res://tests/test_case.gd"
## M3-5 (#60; design/M3_BATTLES.md §6): the entry points for watching battles, headless in the M1 style, on
## a real recorded game whose turn 5 has two battles (a border battle, then a province battle): every battle
## row of the turn report and the battle report viewer's header have Watch (or the reason they can't);
## "Watch your battles (N)" plays the viewer's battles in report order and comes back to the report; the
## computer's battles are watchable; auto-watch starts after the handoff and after the turn's playback on
## the board, never before, once per player and turn, and never in watch mode; nothing is watched behind
## the handoff cover; and session.record(), session.turn_report() and the game state are deep-equal before
## and after watching.

const GAME_SCENE := "res://ui/game_screen.tscn"
const RECORDS := "res://tests/fixtures/main_records.json"
const GAME := "m1_greedy_vs_ai"
const BATTLE_TURN := 5
const BOARD_SIZE := Vector2(1200, 836)
const STEP := 1.0 / 60.0
const RAW_IDS := ["kingdom", "beasts", "crownkeep", "fangridge", "westwatch", "ebonpeak", "stonegate",
	"blackwood", "highcrag", "ironspike", "rivermarch", "bloodfen", "thornvale", "wildmoor", "greenglade",
	"deepwood", "knight_captain", "warchief", "war_bear", "spearmen", "tuskers"]


# --- fixtures -------------------------------------------------------------------------------------

static func _full_record() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(RECORDS))
	for g in data.games:
		if String(g.name) == GAME:
			return g.record.duplicate(true)
	return {}


static func _record(turns: int, ai: Dictionary = {}) -> Dictionary:
	var rec := _full_record()
	rec.history = rec.history.slice(0, turns)
	if not ai.is_empty():
		rec["ai"] = ai.duplicate()
	return rec


func _session(turns: int = BATTLE_TURN, ai: Dictionary = {}) -> GameSession:
	var loaded := GameSession.from_record(_record(turns, ai))
	assert_eq(loaded.errors, [], "the recorded game loads")
	return loaded.session


## A game screen playing on from the recorded game after `turns` turns (a hotseat game opens on the
## handoff cover). `ai` gives seats to the computer.
func _game(turns: int, ai: Dictionary = {}) -> GameScreen:
	var session := _session(turns, ai)
	var computer := {}
	if not ai.is_empty():
		computer = SaveGame.computer_snapshot(AISeat.new(session, Serial.to_int(_full_record().game_seed)), session)
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	assert_eq(game.load_game(SaveGame.make(session, computer, SaveGame.MANUAL, "Test", 0)), "", "the game loads")
	return game


## The current player gives the orders the recorded game gave on `turn`, then ends the turn.
func _play_recorded(game: GameScreen, turn: int) -> void:
	var orders := OrderBook.orders_from_dict(_full_record().history[turn - 1].orders)
	for o in orders.get(game.session.current_player(), []):
		assert_eq(game.session.queue_order(o), "", "the recorded order is accepted")
	assert_eq(game.end_turn(), "")


func _set_auto_watch(on: bool) -> void:
	var s := GameSettings.load_from()
	s.auto_watch_battles = on
	assert_eq(s.save(), "")


func _snapshot(session: GameSession) -> Array:
	return [var_to_str(session.record()), var_to_str(session.turn_report()), var_to_str(session.state().to_dict())]


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
	var word := RegEx.create_from_string("[A-Za-z0-9_-]+")
	var words := {}
	for m in word.search_all(text):
		words[m.get_string()] = true
	for id in RAW_IDS:
		assert_false(words.has(id), "%s shows no raw id '%s'" % [what, id])


func _texts(events: Array) -> Array:
	return events.map(func(e): return String(e.text))


# --- the turn report and the viewer ---------------------------------------------------------------

func test_every_battle_row_has_watch_and_the_report_has_watch_your_battles() -> void:
	var session := _session()
	var battles := session.battle_events()
	assert_eq(battles.size(), 2, "turn 5 had two battles")
	assert_eq(battles[0].type, "border_battle", "a border battle first")
	var panel := TurnReportPanel.new()
	# Behind the handoff nobody in particular reads the report: "Watch the battles".
	panel.show_report(session)
	assert_true(panel.watch_battles_button.visible)
	assert_eq(panel.watch_battles_button.text, "Watch the battles (2)")
	assert_eq(session.acknowledge_handoff(), "")
	panel.show_report(session)
	assert_eq(panel.watch_battles_button.text, "Watch your battles (2)", "with two factions every battle is yours")
	assert_false(panel.watch_battles_button.disabled)
	assert_true(_flat(panel.watch_battles_button.tooltip_text).contains("in the order this report lists them"), panel.watch_battles_button.tooltip_text)
	assert_eq(panel.watch_buttons().size(), battles.size(), "every battle row has Watch")
	for w in panel.watch_buttons():
		assert_false(w.disabled, "a battle with a log can be watched")
		assert_true(_flat(w.tooltip_text).contains("The playback shows exactly what the report describes"), w.tooltip_text)
		assert_true(GameSession.BATTLE_TYPES.has(String(w.get_meta("event").type)))
		assert_true(w.get_parent().get_child_count() == 3, "Watch sits beside Battle report on the battle's row")
	var asked := []
	var queued := []
	panel.watch_requested.connect(func(e: Dictionary): asked.append(e))
	panel.watch_battles_requested.connect(func(events: Array): queued.append(events))
	panel.watch_buttons()[1].pressed.emit()
	assert_eq(asked.size(), 1)
	assert_eq(String(asked[0].text), String(battles[1].text), "a row's Watch asks for its own battle")
	panel.watch_battles_button.pressed.emit()
	assert_eq(_texts(queued[0]), _texts(battles), "Watch your battles asks for them in report order")
	_assert_no_raw_ids(_visible_text(panel), "the turn report with Watch buttons")
	# A battle that can't be played back keeps its Watch, disabled with the reason.
	var report := session.turn_report()
	for e in report.events:
		if e.type == "battle":
			e.numbers.log.truncated = true
		elif e.type == "border_battle":
			e.numbers.erase("log")
	panel.show_report_data(report, "kingdom")
	assert_true(panel.watch_buttons()[0].disabled, "a log that isn't kept, with no record to rebuild from")
	assert_true(_flat(panel.watch_buttons()[0].tooltip_text).contains(BattleHost.NOT_KEPT))
	assert_true(panel.watch_buttons()[1].disabled, "a log cut short")
	assert_true(_flat(panel.watch_buttons()[1].tooltip_text).contains("too big to play back"))
	assert_true(panel.watch_battles_button.disabled, "nothing to watch: Watch your battles says why")
	assert_eq(panel.watch_battles_button.text, "Watch your battles (0)")
	panel.free()


func test_the_computers_battles_are_watchable() -> void:
	var session := _session(BATTLE_TURN, {"beasts": "normal"})
	assert_eq(session.computer_seats(), {"beasts": "normal"})
	var panel := TurnReportPanel.new()
	panel.show_report(session)
	for w in panel.watch_buttons():
		assert_true(Array(w.get_meta("event").factions).has("beasts"), "the computer fought this battle")
		assert_false(w.disabled, "and it can be watched like any other")
	assert_eq(panel.watch_battles_button.text, "Watch your battles (2)")
	panel.free()


func test_the_battle_report_viewer_has_watch_in_its_header() -> void:
	var session := _session()
	var battle: Dictionary = session.battle_events()[1]
	var viewer := BattleReportViewer.new()
	viewer.show_event(battle, session.state(), session.players())
	assert_true(viewer.watch_button.visible and not viewer.watch_button.disabled, "Watch beside Close")
	assert_eq(viewer.watch_button.get_parent(), viewer.close_button.get_parent(), "in the header")
	assert_true(_flat(viewer.watch_button.tooltip_text).contains("The playback shows exactly what the report describes"))
	var asked := []
	viewer.watch_requested.connect(func(e: Dictionary): asked.append(e))
	viewer.watch_button.pressed.emit()
	assert_eq(String(asked[0].text), String(battle.text))
	viewer.show_event({"type": "battle", "text": "A battle.", "numbers": {}})
	assert_true(viewer.watch_button.visible and viewer.watch_button.disabled, "no log: disabled")
	assert_true(_flat(viewer.watch_button.tooltip_text).contains(BattleHost.NO_LOG))
	viewer.show_report(battle.numbers.report)
	assert_false(viewer.watch_button.visible, "a bare report has no battle to watch")
	viewer.free()


# --- the game screen ------------------------------------------------------------------------------

func test_watching_from_the_report_plays_the_queue_returns_and_changes_nothing() -> void:
	_set_auto_watch(true)  # a loaded game still doesn't auto-watch the turn it was saved after
	var game := _game(BATTLE_TURN)
	assert_true(game.handoff.visible, "a loaded hotseat game opens on the handoff")
	assert_eq(game.watch_battles(game.session.battle_events()), "Battles can't be watched behind the handoff cover.")
	assert_false(game.battle_host.visible, "nothing is watched behind the cover")
	game.handoff.ready_button.pressed.emit()
	assert_true(game.report_overlay.visible, "the report opens after the handoff")
	assert_false(game.battle_host.visible, "no auto-watch for the turn the game was saved after")
	var before := _snapshot(game.session)
	var battles := game.session.battle_events()
	# Watch your battles: the queue in report order.
	game.report_panel.watch_battles_button.pressed.emit()
	var host := game.battle_host
	assert_true(host.visible, "the battle screen opens")
	assert_eq(game._top_overlay(), host, "over the report")
	assert_eq(_texts(host.queue), _texts(battles), "in report order")
	assert_eq(host.index, 0)
	assert_eq(host.viewer, "kingdom", "the player at the controls is the viewer")
	var v: BattleSimpleView = host.view
	assert_eq(var_to_str(v.player.battle_log()), var_to_str(battles[0].numbers.log), "the first battle plays")
	v.player.set_speed(4)
	v.player.play()
	for k in 240:
		v.tick(STEP)
	v.player.skip_to_end()
	v.tick(STEP)
	v.buttons.next_battle_card.pressed.emit()
	assert_eq(host.index, 1, "Next battle")
	assert_eq(var_to_str(v.player.battle_log()), var_to_str(battles[1].numbers.log))
	# Full report opens the viewer over the battle; its Watch comes back to the battle.
	v.buttons.report.pressed.emit()
	assert_true(game.battle_viewer.visible and game._top_overlay() == game.battle_viewer, "Full report over the battle")
	assert_true(game.battle_viewer.z_index >= BattleHost.OVER_Z, "drawn above the battle's result card and why panel")
	assert_eq(String(game.battle_viewer.title_label.text).is_empty(), false)
	game.battle_viewer.watch_button.pressed.emit()
	assert_false(game.battle_viewer.visible, "Watch closes the report")
	assert_true(host.visible and host.index == 1 and game._top_overlay() == host, "and plays that battle again")
	assert_eq(game.battle_viewer.z_index, 0, "the overlays are level again")
	# The last battle's Next leads back to the report.
	v.player.skip_to_end()
	v.buttons.next_battle_card.pressed.emit()
	assert_false(host.visible, "the queue ends")
	assert_eq(game._top_overlay(), game.report_overlay, "back on the report")
	# A row's Watch plays that battle, with the report's other battles as its queue.
	game.report_panel.watch_buttons()[1].pressed.emit()
	assert_true(host.visible)
	assert_eq(host.index, 1, "the row's own battle")
	assert_eq(host.queue.size(), 2)
	v._unhandled_input(_esc())
	assert_false(host.visible, "Esc goes back to the report")
	assert_true(game.report_overlay.visible)
	assert_eq(_snapshot(game.session), before, "the game record, the turn report and the state are unchanged")
	_assert_no_raw_ids(_visible_text(game.report_overlay), "the report")
	game.free()
	_set_auto_watch(false)


func test_auto_watch_starts_after_the_handoff_never_before() -> void:
	_set_auto_watch(true)
	var game := _game(BATTLE_TURN - 1)
	game.handoff.ready_button.pressed.emit()
	assert_false(game.battle_host.visible, "the turn before had no battles")
	game.close_turn_report()
	_play_recorded(game, BATTLE_TURN)  # the Crown's orders
	assert_true(game.handoff.visible)
	game.handoff.ready_button.pressed.emit()
	assert_false(game.battle_host.visible, "the Clans' turn starts on the old report: nothing to watch")
	game.close_turn_report()
	_play_recorded(game, BATTLE_TURN)  # the Clans' orders: the turn resolves
	assert_eq(game.session.turn_report().turn, BATTLE_TURN)
	assert_eq(game.session.battle_events().size(), 2, "with two battles")
	assert_true(game.handoff.visible, "the Crown's handoff")
	assert_false(game.battle_host.visible, "never before the handoff")
	assert_false(game.report_overlay.visible)
	var before := _snapshot(game.session)
	game.handoff.ready_button.pressed.emit()
	assert_true(game.report_overlay.visible, "the report opens")
	assert_true(game.battle_host.visible, "then the battles start by themselves")
	assert_eq(game._top_overlay(), game.battle_host, "over the report")
	assert_eq(game.battle_host.viewer, "kingdom", "for the player at the controls")
	assert_eq(_texts(game.battle_host.queue), _texts(BattleHost.battles_of(game.session.battle_events(), "kingdom")), "their battles, in report order")
	var v: BattleSimpleView = game.battle_host.view
	v.player.skip_to_end()
	v.buttons.next_battle_card.pressed.emit()
	v.player.skip_to_end()
	v.buttons.next_battle_card.pressed.emit()
	assert_false(game.battle_host.visible, "the queue ends")
	assert_true(game.report_overlay.visible, "on the report")
	game.open_turn_report()
	assert_false(game.battle_host.visible, "once per player and turn")
	assert_eq(_snapshot(game.session), before, "watching changed nothing")
	# The Clans' turn: their own auto-watch, after their own handoff.
	game.close_turn_report()
	assert_eq(game.end_turn(), "")
	assert_true(game.handoff.visible)
	assert_false(game.battle_host.visible, "not behind the Clans' handoff")
	game.handoff.ready_button.pressed.emit()
	assert_true(game.battle_host.visible, "the Clans watch theirs after their handoff")
	assert_eq(game.battle_host.viewer, "beasts")
	# Ending the turn (or any handoff) closes the battle screen.
	game.battle_host.view.close()
	game.close_turn_report()
	game.watch_battles(game.session.battle_events())
	assert_true(game.battle_host.visible)
	assert_eq(game.end_turn(), "")
	assert_false(game.battle_host.visible, "a handoff closes the battle screen")
	assert_true(game.handoff.visible)
	game.free()
	_set_auto_watch(false)


func test_auto_watch_is_off_by_default() -> void:
	_set_auto_watch(false)
	var game := _game(BATTLE_TURN - 1)
	game.handoff.ready_button.pressed.emit()
	game.close_turn_report()
	_play_recorded(game, BATTLE_TURN)
	game.handoff.ready_button.pressed.emit()
	game.close_turn_report()
	_play_recorded(game, BATTLE_TURN)
	game.handoff.ready_button.pressed.emit()
	assert_true(game.report_overlay.visible, "the report opens")
	assert_false(game.battle_host.visible, "and no battle starts by itself")
	assert_eq(game.report_panel.watch_battles_button.text, "Watch your battles (2)", "the Watch buttons are there instead")
	game.free()


func test_auto_watch_waits_for_the_turn_playback_on_the_board() -> void:
	_set_auto_watch(true)
	var game := _game(BATTLE_TURN - 1)
	game.use_board("3d")
	var b: Board3D = game.map.board
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	b.size = BOARD_SIZE
	b.build_now()
	game.handoff.ready_button.pressed.emit()
	game.close_turn_report()
	_play_recorded(game, BATTLE_TURN)
	game.handoff.ready_button.pressed.emit()
	if b.is_playing():
		b.skip_playback()
	game.close_turn_report()
	_play_recorded(game, BATTLE_TURN)
	game.handoff.ready_button.pressed.emit()
	assert_true(b.is_playing(), "the Crown sees the turn play out on the board")
	assert_false(game.report_overlay.visible, "before the report")
	assert_false(game.battle_host.visible, "and before any battle is watched")
	b.skip_playback()
	assert_true(game.report_overlay.visible, "the report opens when the playback ends")
	assert_true(game.battle_host.visible, "then the battles start")
	assert_eq(game._top_overlay(), game.battle_host)
	game.free()
	_set_auto_watch(false)


func test_auto_watch_with_one_person_and_never_in_watch_mode() -> void:
	_set_auto_watch(true)
	var game := _game(BATTLE_TURN, {"beasts": "normal"})
	assert_false(game.handoff.visible, "one person: no handoff")
	assert_eq(game.watch_viewer(), "kingdom", "the only person is the viewer")
	game.open_turn_report()
	assert_false(game.battle_host.visible, "not for the turn the game was saved after")
	game._auto_watched = {}  # as if this turn had just resolved
	assert_true(game.auto_watch(), "the person's battles start at once")
	assert_true(game.battle_host.visible)
	assert_eq(game.battle_host.queue.size(), 2)
	game.battle_host.close()
	assert_false(game.auto_watch(), "once per turn")
	game.free()
	var watch := _game(BATTLE_TURN, {"kingdom": "normal", "beasts": "normal"})
	assert_true(watch.is_watching(), "the computer plays both seats")
	assert_eq(watch.watch_viewer(), "", "nobody in particular is watching")
	watch._auto_watched = {}
	assert_false(watch.auto_watch(), "no auto-watch in watch mode")
	watch.open_turn_report()
	assert_eq(watch.report_panel.watch_battles_button.text, "Watch the battles (2)", "but every battle can be watched")
	watch.report_panel.watch_battles_button.pressed.emit()
	assert_true(watch.battle_host.visible)
	watch.free()
	_set_auto_watch(false)


## A tooltip's text with its wrapping undone.
func _flat(text: String) -> String:
	return text.replace("\n", " ")


func _esc() -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = KEY_ESCAPE
	k.pressed = true
	return k
