extends SceneTree
## The live half of tests/test_chronicle_live.gd (UX-6, #214). Not a test file (no "test_" prefix): the test runs it in a child Godot
## process, because the test runner's tests run before the scene tree is live, so no Control ever gets a layout pass and no mouse event is
## routed. This script runs a real (headless) main loop with the real root window, puts a whole GameScreen in it (fog, magic, paths, a
## computer opponent), and drives the Chronicle with REAL mouse and key events pushed through the viewport, as a player's hands would:
##   * it ends turn 1 with a recruit queued, waits for the turn's report to be ready (the report host), and finds the Chronicle lit with that
##     real turn's news: medallions down the left edge and an unread badge on the Chronicle button;
##   * it moves the mouse over a medallion (the viewport's hovered control IS that medallion), LEFT-CLICKS it (the Chronicle opens at that
##     card), clicks the card's Pin (the pin is in the sidecar store, not the game), clicks its place chip (the board selects the province),
##     RIGHT-CLICKS the medallion (dismissed: its card and medallion go), clicks Restore (they come back), presses Esc (the Chronicle closes),
##     clicks the Chronicle button (it opens), clicks its close button (it closes), and clicks Hide and Notices on the stack;
##   * it does the same on the 2D map and at each size the spec supports (1600x900 at 100%, the same window at 125%, 1280x720 at 100%), with
##     the news of a resolved turn put in the Chronicle (a real report's announcements) so that every size and board has medallions;
##   * after every drive, nothing of the game changed: the turn, the orders and the record are the same as before the mouse moved.
## It prints one line,
##   CHRONICLE_REPORT {"real": {...}, "3d": {"1600x900": {...}, ...}, "2d": {...}}
## and never touches the player's settings or saves (they go to a scratch folder under user://).
##
##   godot --headless --path . --script res://tests/chronicle_probe.gd

const SCRATCH := "user://chronicle_probe"
const WAIT_BOARD_S := 120.0
const SIZES := [["1600x900", Vector2i(1600, 900), 1.0], ["1600x900@125", Vector2i(1600, 900), 1.25], ["1280x720", Vector2i(1280, 720), 1.0]]

var report := {}
var game: GameScreen
var kind := "3d"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	GameSettings.default_path = SCRATCH.path_join("settings.cfg")
	ChronicleSettings.default_auto_open = "never"
	_run()


func _run() -> void:
	await process_frame
	await _start()
	report["real"] = await _real_turn()
	for k in ["3d", "2d"]:
		kind = k
		report[kind] = {}
		if kind == "2d":
			game.use_board("2d")
			await _frames(6)
		for entry in SIZES:
			await _resize(entry)
			_news()
			report[kind][String(entry[0])] = await _drive("%s %s" % [kind, entry[0]])
	print("CHRONICLE_REPORT " + JSON.stringify(report))
	game.queue_free()
	await process_frame
	quit()


func _start() -> void:
	var gs := GameSettings.new(SCRATCH.path_join("settings.cfg"))
	gs.set_board("3d")
	gs.save()
	game = load("res://ui/game_screen.tscn").instantiate()
	game.autosave_enabled = false
	game.save_store = SaveStore.new(SCRATCH.path_join("saves"))
	game.start_game({"players": ["kingdom", "beasts"], "seed": 777, "rulers": true, "paths": true, "sieges": true, "fog": true, "magic": true,
		"independents": true, "ai": {"beasts": "normal"},
		"builds": {"kingdom": RulerRules.preset_build(RulerRules.balanced_preset("kingdom")), "beasts": BuildScreen.computer_build("beasts", 777, 1)}})
	root.size = Vector2i(1600, 900)
	root.content_scale_factor = 1.0
	root.add_child(game)
	await process_frame
	var board: Board3D = game.map.board
	var t0 := Time.get_ticks_msec()
	while not board.prepared and float(Time.get_ticks_msec() - t0) / 1000.0 < WAIT_BOARD_S:
		await create_timer(0.1).timeout
	print("PROBE board ready: ", board.prepared)
	await _frames(6)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _resize(entry: Array) -> void:
	root.content_scale_factor = float(entry[2])
	root.size = entry[1]
	await _frames(8)


# --- input -----------------------------------------------------------------------------------------

func _centre(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _motion(p: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	root.push_input(m, true)
	await process_frame
	await process_frame


func _click(p: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	await _motion(p)
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.position = p
	press.global_position = p
	root.push_input(press, true)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release, true)
	await process_frame
	await process_frame


func _key(code: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	root.push_input(press, true)
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	root.push_input(release, true)
	await process_frame
	await process_frame


func _hovered_is(c: Control) -> bool:
	var h := root.gui_get_hovered_control()
	return h != null and (h == c or c.is_ancestor_of(h))


# --- the real turn -----------------------------------------------------------------------------------

## Ends turn 1 with a recruit queued and waits for the report: the Chronicle is lit by the game's own flow, then driven by the mouse.
func _real_turn() -> Dictionary:
	var hud := game.chronicle_hud
	var map := game.map
	var capital: String = map.state.find_faction("kingdom").capital
	map.select_province(capital)
	var types := map.orders.recruitable_types()
	if not types.is_empty():
		map.queue_recruit(String(types[0].id))
	var out := {"orders": game.session.current_orders().size(), "turn_before": game.session.turns_played()}
	game.end_turn()
	var t0 := Time.get_ticks_msec()
	while game.report_host.last_ready < game.session.turns_played() and float(Time.get_ticks_msec() - t0) / 1000.0 < 90.0:
		await process_frame
	await _frames(6)
	out["ready"] = game.report_host.last_ready
	out["turns_played"] = game.session.turns_played()
	out["announcements"] = hud.announcements.size()
	out["notable"] = ChronicleModel.notable(hud.items()).size()
	out["modal_open"] = game.report_overlay.visible
	out["auto_opened"] = hud.is_open()
	out["badge"] = hud.unread_count()
	out["drive"] = await _drive("real turn")
	return out


## A resolved turn's news in the Chronicle (a real report's announcements), for the boards and sizes after the real turn: the Chronicle is
## reset (nothing pinned or dismissed), shut, and lit with it.
func _news() -> void:
	var hud := game.chronicle_hud
	hud.close()
	hud.store.forget_seat("kingdom")
	hud._refresh_all()
	if hud.stack.medallions.size() >= 1:
		return  # the real turn's own news is still lit
	var s := GameState.new(8)
	s.armies.clear()
	for pid in ["thornvale", "stonegate", "greenglade", "highcrag", "westwatch"]:
		s.find_province(pid).owner = "kingdom"
	for pid in ["wildmoor", "blackwood", "deepwood", "fangridge", "bloodfen", "ebonpeak", "ironspike"]:
		s.find_province(pid).owner = "beasts"
	for spec in [["kingdom-1", "kingdom", "thornvale", ["knights", "knights", "knights", "knights"]], ["kingdom-3", "kingdom", "greenglade", ["spearmen", "spearmen"]],
			["beasts-1", "beasts", "wildmoor", ["war_bear"]]]:
		var a := Army.new()
		a.id = spec[0]
		a.owner = spec[1]
		a.location = spec[2]
		for t in spec[3]:
			a.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(spec[1]), t), spec[1]))
		s.armies.append(a)
	var r := TurnResolver.resolve(s, {"kingdom": [MoveOrder.new("kingdom-1", "wildmoor"), MoveOrder.new("kingdom-3", "deepwood"), RecruitOrder.new("knights")], "beasts": []}, 1, AutoBattleResolver.new())
	hud.seat = "kingdom"
	hud.turn = 1
	hud.announcements = ChronicleModel.build({"turn": 1, "events": r.events, "header": "Turn 1", "fog": false}, r.new_state, "kingdom")
	hud.summary = ChronicleModel.summary(hud.announcements, {"events": r.events}, r.new_state, "kingdom")
	hud._refresh_all()


# --- the drive ---------------------------------------------------------------------------------------------

## One pass of real input at the Chronicle in the window as it is now. Every step reports what it saw; a step that cannot run says why.
func _drive(tag: String) -> Dictionary:
	var hud := game.chronicle_hud
	var map := game.map
	var out := {"tag": tag, "window": [root.get_visible_rect().size.x, root.get_visible_rect().size.y]}
	var record_before := var_to_str(game.session.record())
	var turns_before: int = game.session.turns_played()
	var orders_before: int = game.session.current_orders().size()
	hud.close()
	await _frames(3)
	var seat: String = hud.seat
	out["seat"] = seat
	out["medallions"] = hud.stack.medallions.size()
	if hud.stack.medallions.is_empty():
		out["error"] = "no medallions to drive"
		return out
	# The first medallion whose card has a place (its place chip is then driven too), else the first.
	var m: NoticeMedallion = hud.stack.medallions[0]
	for candidate in hud.stack.medallions:
		var found := hud.items().filter(func(it): return String(it.id) == candidate.id and not String(it.province).is_empty())
		if not found.is_empty():
			m = candidate
			break
	var id := m.id
	out["id"] = id
	out["badge_visible"] = hud.button.get_node("UnreadBadge").visible
	out["unread"] = hud.unread_count()
	# Hover: the viewport says the mouse is over this medallion.
	await _motion(_centre(m))
	out["hover_is_medallion"] = _hovered_is(m)
	# Left-click opens the Chronicle at its card.
	await _click(_centre(m))
	await _frames(3)
	out["opened"] = hud.is_open()
	out["opened_at"] = hud.last_opened_at == id
	out["column_shown"] = hud.column.is_visible_in_tree()
	out["safe_narrowed"] = map.table().chronicle_open
	out["card_present"] = hud.column.card(id) != null
	out["unread_after_open"] = hud.unread_count()
	out["markers"] = hud.markers.marker_ids().size()
	# Pin: a click on the card's pin button; the pin is in the store, the game's record is untouched.
	var card := hud.column.card(id)
	if card != null:
		await _click(_centre(card.pin_button))
		await _frames(2)
		out["pinned"] = hud.store.is_pinned(seat, id)
		out["pin_file"] = FileAccess.file_exists(hud.store.path())
		out["record_same_after_pin"] = var_to_str(game.session.record()) == record_before
	# Place chip: a click focuses the board on the card's province.
	card = hud.column.card(id)
	out["has_place"] = card != null and card.place_button != null
	if card != null and card.place_button != null:
		map.selected_province_id = ""
		await _click(_centre(card.place_button))
		await _frames(2)
		out["focused"] = map.selected_province_id == String(card.item.province)
		out["still_open_after_focus"] = hud.is_open()
	# Right-click the medallion: dismissed, with its card and marker.
	var m2 := hud.stack.medallion(id)
	if m2 != null:
		await _click(_centre(m2), MOUSE_BUTTON_RIGHT)
		await _frames(2)
		out["dismissed"] = hud.store.is_dismissed(seat, id)
		out["card_gone"] = hud.column.card(id) == null
		out["medallion_gone"] = hud.stack.medallion(id) == null
		out["unpinned_with_it"] = not hud.store.is_pinned(seat, id)
	# Restore: a click on the column's Restore button.
	if hud.column.restore_button.visible:
		await _click(_centre(hud.column.restore_button))
		await _frames(2)
		out["restored"] = hud.column.card(id) != null and not hud.store.is_dismissed(seat, id)
	# Esc closes the Chronicle (UiCancel's order: nothing modal is open, so the Chronicle goes first).
	out["selection_before_esc"] = map.selected_province_id
	await _key(KEY_ESCAPE)
	out["esc_closed"] = not hud.is_open()
	out["safe_open_again"] = not map.table().chronicle_open
	# The Chronicle button opens it, its close button shuts it.
	await _click(_centre(hud.button))
	await _frames(2)
	out["button_opened"] = hud.is_open()
	await _click(_centre(hud.column.close_button))
	await _frames(2)
	out["close_button_closed"] = not hud.is_open()
	# Hide and Notices on the stack.
	await _click(_centre(hud.stack.toggle))
	await _frames(2)
	out["folded"] = hud.stack.shown == false and hud.stack.medallions.is_empty()
	await _click(_centre(hud.stack.toggle))
	await _frames(2)
	out["unfolded"] = hud.stack.shown and hud.stack.medallions.size() > 0
	# Nothing of the game moved under the mouse.
	hud.store.unpin(seat, id)
	out["record_same"] = var_to_str(game.session.record()) == record_before
	out["turns_same"] = game.session.turns_played() == turns_before
	out["orders_same"] = game.session.current_orders().size() == orders_before
	out["hover_after"] = root.gui_get_hovered_control() != null
	return out
