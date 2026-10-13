extends SceneTree
## The live half of tests/test_order_tray.gd (UX-4, #213). Not a test file (no "test_" prefix): the test runs it in a child Godot process,
## because the runner's tests run before the scene tree is live, so no Control gets a layout pass there and no mouse event is routed (the same
## reason as tests/table_probe.gd and tests/card_click_probe.gd). This is a real (headless) main loop with the real root window and a whole game
## screen. For each board (the 3D world, then the 2D map) and each of the three sizes the spec supports (a 1600x900 window at 100%, the same
## window at 125%, which lays out as 1280x720, and a 1280x720 window at 100%) it stages one turn, a split, a march for the new army, a march
## for the old one, two recruits and a research pick, and
##   * measures the tray: every token is inside the window and the tray, the tray is inside the 120 px bottom band and clear of the seal, the
##     numbers are 1..n in the order given, the realm token follows them and has none, and a number is big enough to read (12 px on screen);
##   * measures the order marks on the board: a token for each placed order (the recruits folded into one), every one inside the window and clear
##     of every plate (a province's, an army's; on the 2D map each region's name, income and badges), of every piece of the Table and of every other token;
##   * pushes real mouse events through the viewport: the mouse over a token hovers that token (nothing covers it); a click on a tray token
##     focuses its place and opens its order's card, Esc brings the card under it back; a right-click on a token cancels its order and the
##     rest renumber; a click on a token's cross cancels it; a click on a board token opens its card and a right-click cancels it; with nine
##     tokens the wheel over the tray scrolls it sideways.
## It prints one PASS or FAIL line a check and a last line, "TRAY_PROBE OK" or "TRAY_PROBE FAILED n". Never touches the player's settings or
## saves (they go to a scratch folder under user://).
##
##   godot --headless --path . --script res://tests/tray_probe.gd

const SCRATCH := "user://tray_probe"
const WAIT_BOARD_S := 120.0
## [key, window, content scale factor]: the logical size is the window over the factor, or the project's 1600x900 stretched.
const SIZES := [["1600x900", Vector2i(1600, 900), 1.0], ["1600x900@125", Vector2i(1600, 900), 1.25], ["1280x720", Vector2i(1280, 720), 1.0]]
## A number must be at least this many pixels tall on the screen to be read.
const MIN_NUMBER_PX := 12.0

var game: GameScreen
var results := []
var kind := "3d"
var tag := ""


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	GameSettings.default_path = SCRATCH.path_join("settings.cfg")
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	results.append("%s [%s] %s" % ["PASS" if ok else "FAIL", tag, what])
	print(results.back())


func _motion(p: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	root.push_input(m, true)


func _button(p: Vector2, button: MouseButton) -> void:
	_motion(p)
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.position = p
	press.global_position = p
	root.push_input(press, true)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release, true)
	await _frames(4)


func _click(p: Vector2) -> void:
	await _button(p, MOUSE_BUTTON_LEFT)


func _right_click(p: Vector2) -> void:
	await _button(p, MOUSE_BUTTON_RIGHT)


func _wheel(p: Vector2, button: MouseButton) -> void:
	_motion(p)
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	e.position = p
	e.global_position = p
	root.push_input(e, true)
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


## Frames until no board token moved for five in a row (the camera glides to a focused place), at most 300.
func _settle_board() -> void:
	var last := []
	var still := 0
	for i in 300:
		await process_frame
		var now: Array = _board_tokens().filter(func(t): return (t as Control).visible).map(func(t): return (t as Control).get_global_rect())
		if now == last:
			still += 1
			if still >= 5:
				return
		else:
			still = 0
		last = now


func _centre(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


## The point on a tray token to click: the middle of its number chip (never its cross).
func _body(t: OrderToken) -> Vector2:
	return _centre(t.chip) if t.chip != null else _centre(t.icon)


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
	root.content_scale_factor = 1.0
	root.add_child(game)
	await process_frame
	var board: Board3D = game.map.board
	var t0 := Time.get_ticks_msec()
	while not board.prepared and float(Time.get_ticks_msec() - t0) / 1000.0 < WAIT_BOARD_S:
		await create_timer(0.1).timeout
	await _frames(8)
	for k in ["3d", "2d"]:
		kind = k
		if kind == "2d":
			game.use_board("2d")
			await _frames(6)
		for entry in SIZES:
			tag = "%s %s" % [kind, entry[0]]
			root.content_scale_factor = float(entry[2])
			root.size = entry[1]
			await _frames(10)
			await _stage()
			await _measure_tray()
			await _measure_board_marks()
			await _real_clicks()
	var failed := results.filter(func(r): return String(r).begins_with("FAIL"))
	print("TRAY_PROBE ", "OK" if failed.is_empty() else "FAILED %d" % failed.size())
	game.queue_free()
	await process_frame
	quit()


# --- staging --------------------------------------------------------------------------------------

## One turn with every kind of mark the first turn can have: a split, a march for the new army, a march for the old one, two recruits at the
## capital and a research pick (a realm order). The tray reads 1 Split, 2 and 3 marches, 4 and 5 recruits, then the research token.
func _stage() -> void:
	var map := game.map
	game._close_overlays()
	game.notice_panel.visible = false
	map.clear_preview()
	while not game.session.current_orders().is_empty():
		map.cancel_order(0)
	if kind == "3d" and String(map.board.closeup) != "":
		map.board.exit_closeup(true)
	map.selected_army_id = ""
	var here: String = map.state.find_army("kingdom-1").location
	var nb: Array = map.state.find_province(here).neighbors
	map.select_province(here)
	_check(map.queue_muster(MusterOrder.transfer("kingdom-1", "", [0, 1])).is_empty(), "the split is ordered")
	var new_id: String = map.orders.muster_forms(0)
	_check(map.queue_move(new_id, nb[0]).is_empty(), "the new army (%s) is given a march" % new_id)
	_check(map.queue_move("kingdom-1", nb[1]).is_empty(), "the old army is given a march")
	map.select_province(here)
	for i in 2:
		var types := map.orders.recruitable_types()
		map.queue_recruit(String(types[i % types.size()].id))
	var node := ""
	for n in PathData.PATHS["kingdom"].nodes:
		if AscensionRules.check_research(map.state, "kingdom", String(n.id)).is_empty():
			node = String(n.id)
			break
	game.session.queue_order(ResearchOrder.new(node))
	map._orders_changed()
	map.selected_army_id = ""
	map.select_province(here)
	await _frames(12)


# --- the tray ---------------------------------------------------------------------------------------

func _measure_tray() -> void:
	var hud := game.map.table()
	var tray := hud.tray_slot()
	var tokens: Array = tray.tokens()
	var vp := root.get_visible_rect().size
	_check(tokens.size() == 6, "the tray holds six tokens (5 placed, 1 realm): %d" % tokens.size())
	var chips := tokens.map(func(t): return (t as OrderToken).chip.text if (t as OrderToken).chip != null else "")
	_check(chips == ["1", "2", "3", "4", "5", ""], "numbered 1 to 5 in the order given, the realm token last with none: %s" % [chips])
	_check(not hud.hint_label.visible, "the hint gives way to the tokens")
	var tray_rect := hud.tray.get_global_rect()
	var window := Rect2(Vector2.ZERO, vp)
	_check(window.grow(0.5).encloses(tray_rect), "the tray is inside the window (%s)" % tray_rect)
	_check(tray_rect.position.y >= vp.y - TableLayout.BOTTOM_H - 0.5, "and inside the 120 px bottom band")
	_check(tray_rect.end.x <= hud.seal.get_global_rect().position.x + 0.5, "and left of the seal")
	for t in tokens:
		var r := (t as OrderToken).get_global_rect()
		_check(tray_rect.grow(0.5).encloses(r) and (t as OrderToken).is_visible_in_tree(), "token %s is in the tray and shown" % (t as OrderToken).name)
	var px: float = 15.0 * root.get_final_transform().get_scale().x
	_check(px >= MIN_NUMBER_PX, "a number is %.1f px tall on the screen (at least %d)" % [px, int(MIN_NUMBER_PX)])
	_check(tray.compact == hud.compact, "the tray follows the Table's compact mode (%s)" % tray.compact)
	_check((tokens[0] as OrderToken).label.visible == not hud.compact, "the words show only when the Table is wide")


# --- the order marks on the board ---------------------------------------------------------------------

func _board_tokens() -> Array:
	var map := game.map
	if kind == "3d":
		return map.board.overlay.order_marks()
	return map.order_marks_2d.tokens()


## What a board token must keep clear of, [name, rect] in global coordinates.
func _obstacles() -> Array:
	var map := game.map
	var out := []
	if kind == "3d":
		var overlay: Control = map.board.overlay
		for id in overlay._plates:
			var root_plate: Control = overlay._plates[id]["root"]
			if root_plate.is_visible_in_tree():
				out.append(["plate %s" % id, root_plate.get_global_rect()])
		for id in overlay._army_plates:
			var pc: Control = overlay._army_plates[id]
			if pc.is_visible_in_tree():
				out.append(["army plate %s" % id, pc.get_global_rect()])
	else:
		for id in map.regions:
			var region: ProvinceRegion = map.regions[id]
			for c in [region.name_label, region.income_label, region.army_box]:
				var ctl := c as Control
				if ctl != null and ctl.is_visible_in_tree() and ctl.size.x > 0.0:
					out.append(["%s %s" % [id, ctl.name], ctl.get_global_transform() * Rect2(Vector2.ZERO, ctl.size)])
	var hud := map.table()
	for c in hud.pieces():
		var ctl2 := c as Control
		if ctl2 != null and ctl2.is_visible_in_tree():
			out.append(["Table piece %s" % ctl2.name, ctl2.get_global_rect()])
	var placed := hud.placed()
	for k in ["guide", "notice"]:
		if placed.has(k):
			out.append(["Table %s" % k, Rect2(placed[k].position + hud.global_position, placed[k].size)])
	return out


func _measure_board_marks() -> void:
	var tokens: Array = _board_tokens()
	var vp := root.get_visible_rect().size
	var window := Rect2(Vector2.ZERO, vp)
	var shown: Array = tokens.filter(func(t): return (t as Control).visible)
	var chips := shown.map(func(t): return (t as OrderToken).chip.text)
	_check(chips == ["1", "2", "3", "4, 5"], "the board marks the five placed orders as four tokens, the recruits folded: %s" % [chips])
	var obstacles := _obstacles()
	_check(obstacles.size() >= 10, "the plates and the Table's pieces were found (%d)" % obstacles.size())
	for i in shown.size():
		var t: OrderToken = shown[i]
		var r := t.get_global_rect()
		_check(window.grow(0.5).encloses(r), "board token %s is inside the window (%s)" % [t.name, r])
		var hit := []
		for o in obstacles:
			if TableLayout.overlaps(r, o[1]):
				hit.append(o[0])
		_check(hit.is_empty(), "board token %s sits clear of every plate and piece of the Table (it overlaps %s)" % [t.name, hit])
		for j in range(i + 1, shown.size()):
			_check(not TableLayout.overlaps(r, (shown[j] as OrderToken).get_global_rect()), "board tokens %s and %s do not overlap" % [t.name, (shown[j] as OrderToken).name])
	var px: float = 15.0 * root.get_final_transform().get_scale().x
	_check(px >= MIN_NUMBER_PX, "the numbers on the board are %.1f px tall on the screen" % px)


# --- real mouse events ------------------------------------------------------------------------------

func _real_clicks() -> void:
	var map := game.map
	var cards := map.cards
	var hud := map.table()
	var tray := hud.tray_slot()
	# the mouse over a token hovers it: nothing covers it
	var second: OrderToken = tray.tokens()[1]
	_motion(_body(second))
	await _frames(2)
	_check(root.gui_get_hovered_control() == second, "the mouse over token 2 hovers it (%s)" % [root.gui_get_hovered_control()])
	# a click opens the card of its order, focusing the order's place
	map.selected_army_id = ""
	await _click(_body(second))
	_check(cards.mode == "order" and cards.visible, "a real click on token 2 opens its order's card")
	_check(map.selected_army_id == "", "with no army selected: the click can never be a second click of a march")
	_check(map.selected_province_id == String(second.mark.place), "and its place (%s) is the selected province" % second.mark.place)
	_check(game.session.current_orders().size() == 6, "nothing was ordered or cancelled by it")
	await _key(KEY_ESCAPE)
	_check(cards.mode != "order", "Esc brings the card under it back (%s)" % cards.mode)
	# a click on a board token opens its card too
	await _settle_board()  # the camera glided to the order's place: wait for it to stop
	var board_tokens: Array = _board_tokens().filter(func(t): return (t as Control).visible)
	var bt: OrderToken = board_tokens[0]
	_motion(_centre(bt))
	await _frames(2)
	bt = _board_tokens().filter(func(t): return (t as Control).visible)[0]
	_check(root.gui_get_hovered_control() == bt, "the mouse over a board token hovers it")
	await _click(_centre(bt))
	_check(cards.mode == "order", "a real click on a board token opens its card")
	await _key(KEY_ESCAPE)
	# a right-click on token 2 cancels its order; the rest renumber
	var before: int = game.session.current_orders().size()
	await _right_click(_body(tray.tokens()[1]))
	_check(game.session.current_orders().size() == before - 1, "a real right-click on token 2 cancels its order")
	var chips := tray.tokens().map(func(t): return (t as OrderToken).chip.text if (t as OrderToken).chip != null else "")
	_check(chips == ["1", "2", "3", "4", ""], "and the numbers re-flow in the tray: %s" % [chips])
	var board_chips := _board_tokens().filter(func(t): return (t as Control).visible).map(func(t): return (t as OrderToken).chip.text)
	_check(board_chips.size() >= 3 and board_chips[0] == "1" and board_chips[1] == "2", "and on the board: %s" % [board_chips])
	# a click on the cross of token 1
	var first: OrderToken = tray.tokens()[0]
	before = game.session.current_orders().size()
	await _click(_centre(first.cross))
	_check(game.session.current_orders().size() == before - 1, "a real click on token 1's cross cancels its order")
	chips = tray.tokens().map(func(t): return (t as OrderToken).chip.text if (t as OrderToken).chip != null else "")
	_check(chips == ["1", "2", "3", ""], "and the rest move up: %s" % [chips])
	# a right-click on a board token cancels it
	board_tokens = _board_tokens().filter(func(t): return (t as Control).visible)
	before = game.session.current_orders().size()
	await _right_click(_centre(board_tokens[0]))
	_check(game.session.current_orders().size() == before - 1, "a real right-click on a board token cancels its order")
	# more than seven tokens scroll: two splits, a march for each of the three armies, two recruits and the research pick
	while not game.session.current_orders().is_empty():
		map.cancel_order(0)
	var here: String = map.state.find_army("kingdom-1").location
	var nb: Array = map.state.find_province(here).neighbors
	map.queue_muster(MusterOrder.transfer("kingdom-1", "", [0]))
	map.queue_muster(MusterOrder.transfer("kingdom-1", "", [0]))
	for k in 3:
		map.queue_move(["kingdom-3", "kingdom-4", "kingdom-1"][k], nb[k % nb.size()])
	map.select_province(here)
	for i in 2:
		map.queue_recruit(String(map.orders.recruitable_types()[0].id))
	for n in PathData.PATHS["kingdom"].nodes:
		if AscensionRules.check_research(map.state, "kingdom", String(n.id)).is_empty():
			game.session.queue_order(ResearchOrder.new(String(n.id)))
			break
	map._orders_changed()
	await _frames(8)
	var count: int = tray.tokens().size()
	_check(count > OrderTray.VISIBLE_TOKENS and tray.scrolls(), "with %d tokens the tray scrolls sideways" % count)
	_check(tray.visible_tokens() == OrderTray.VISIBLE_TOKENS, "seven show at once")
	var tray_rect := hud.tray.get_global_rect()
	_check(Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(0.5).encloses(tray_rect) and tray_rect.end.x <= hud.seal.get_global_rect().position.x + 0.5,
		"the long tray still fits the window and clears the seal (%s)" % tray_rect)
	var before_scroll: int = tray.scroll.scroll_horizontal
	await _wheel(_centre(tray.scroll), MOUSE_BUTTON_WHEEL_DOWN)
	await _wheel(_centre(tray.scroll), MOUSE_BUTTON_WHEEL_DOWN)
	_check(tray.scroll.scroll_horizontal != before_scroll or tray.scroll.scroll_horizontal > 0, "the wheel over the tray scrolls it (%d -> %d)" % [before_scroll, tray.scroll.scroll_horizontal])
	while not game.session.current_orders().is_empty():
		map.cancel_order(0)
	await _frames(4)
	_check(tray.tokens().is_empty() and hud.hint_label.visible, "with every order cancelled the tray shows the hint again")
