extends SceneTree
## The live half of tests/test_selection_cards.gd (UX-3, #206). Not a test file (no "test_" prefix): the test runs it in a child Godot
## process, because the runner's tests run before the scene tree is live, so no Control gets a layout pass there and no mouse or key
## event is routed (the same reason as tests/table_probe.gd). This is a real (headless) main loop with the real root window and a whole
## game screen on the 3D board, and it drives the selection cards with real events pushed through the viewport:
##   * a click on the Recruit button opens its section, and a click on a recruit button queues the order;
##   * a click on March folds the card into a slim strip; Esc ends the pick and brings the card back;
##   * March again, then a click on a neighbouring province on the board orders the march (the board's own picking);
##   * a click on Cancel order withdraws it; the tray's Orders button shows the list and Esc goes back to the card.
## It prints one PASS or FAIL line a check and a last line, "CLICK_PROBE OK" or "CLICK_PROBE FAILED n". Never touches the player's
## settings or saves (they go to a scratch folder under user://).
##
##   godot --headless --path . --script res://tests/card_click_probe.gd

const SCRATCH := "user://card_click_probe"
var game: GameScreen
var results := []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	GameSettings.default_path = SCRATCH.path_join("settings.cfg")
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _motion(p: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	root.push_input(m, true)


func _click(p: Vector2) -> void:
	_motion(p)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = p
	press.global_position = p
	root.push_input(press, true)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release, true)
	await _frames(3)


func _key(code: Key) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = true
	Input.parse_input_event(k)
	await _frames(2)
	var up := k.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)


func _centre(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _check(ok: bool, what: String) -> void:
	results.append("%s %s" % ["PASS" if ok else "FAIL", what])
	print(results.back())


func _run() -> void:
	await process_frame
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
	root.add_child(game)
	await process_frame
	var board: Board3D = game.map.board
	var t0 := Time.get_ticks_msec()
	while not board.prepared and float(Time.get_ticks_msec() - t0) / 1000.0 < 120.0:
		await create_timer(0.1).timeout
	await _frames(8)
	var map := game.map
	var cards := map.cards
	# the capital card at game start; click Recruit with the mouse
	_check(cards.visible and cards.mode == "province", "the capital's card is up at the start")
	var recruit: Button = cards.pinned.find_child("RecruitButton", true, false)
	await _click(_centre(recruit))
	_check(cards.section_open("recruit"), "a real click on Recruit opens its section")
	var buy: Button = cards.details.find_child("Recruit_*", true, false)
	await _frames(4)
	_check(buy != null and buy.is_visible_in_tree(), "the recruit buttons show")
	await _click(_centre(buy))
	_check(game.session.current_orders().size() == 1, "a real click on a recruit button queues the order")
	# the army card, March, Esc
	map.select_army("kingdom-1")
	await _frames(6)
	var march: Button = cards.pinned.find_child("MarchButton", true, false)
	_check(march != null and march.is_visible_in_tree(), "March is on screen")
	await _click(_centre(march))
	_check(cards.marching, "a real click on March starts the pick")
	await _frames(6)
	_check(cards.strip.is_visible_in_tree() and cards.get_global_rect().size.y < 100.0, "the strip is slim: %s" % [cards.get_global_rect()])
	await _key(KEY_ESCAPE)
	_check(not cards.marching and cards.visible, "Esc ends the pick and keeps the card")
	# March, then a real click on Westwatch on the board
	await _frames(4)
	march = cards.pinned.find_child("MarchButton", true, false)
	await _click(_centre(march))
	_check(cards.marching, "March again")
	await _frames(6)
	# find a point on the board over Westwatch that no HUD piece covers
	var target := ""
	var here: Province = map.state.find_province(map.state.find_army("kingdom-1").location)
	var at := Vector2.ZERO
	if target.is_empty():
		var y := 130.0
		while y < 780.0 and target.is_empty():
			var x := 520.0
			while x < 1500.0 and target.is_empty():
				var id := String(board.province_at(Vector2(x, y) - board.global_position))
				if here.neighbors.has(id):
					target = id
					at = Vector2(x, y)
				x += 20.0
			y += 20.0
	await _click(at)
	var orders := game.session.current_orders()
	var moves := orders.filter(func(o): return o is MoveOrder)
	_check(moves.size() == 1 and moves[0].to == target, "a real click on %s orders the march (%s)" % [target, str(moves.size())])
	_check(not cards.marching and cards.visible, "the card is back, showing the order")
	var cancel: Button = cards.pinned.find_child("CancelButton", true, false)
	_check(cancel != null, "Cancel order is on the card")
	await _click(_centre(cancel))
	_check(game.session.current_orders().filter(func(o): return o is MoveOrder).is_empty(), "a real click on Cancel order withdraws it")
	# the tray's Orders button
	await _click(_centre(map.table().orders_button))
	_check(cards.mode == "orders", "the tray's Orders button shows the list")
	await _key(KEY_ESCAPE)
	_check(cards.mode == "army" or cards.mode == "province", "Esc goes back to the card under it: %s" % cards.mode)
	var failed := results.filter(func(r): return String(r).begins_with("FAIL"))
	print("CLICK_PROBE ", "OK" if failed.is_empty() else "FAILED %d" % failed.size())
	game.queue_free()
	await process_frame
	quit()
