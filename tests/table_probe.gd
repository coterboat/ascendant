extends SceneTree
## The live half of tests/test_table_geometry.gd (UX-1, #194). Not a test file (no "test_" prefix): the test runs it in a child Godot
## process, because the test runner's tests run before the scene tree is live, so no Control ever gets a layout pass there and no
## mouse event is routed. This script runs a real (headless) main loop with the real root window: it sets the window's size and its
## content scale factor like Settings does, puts a whole GameScreen in it (every system on, a computer opponent), and for each of the
## three sizes the spec names (a 1600x900 window at 100%, the same window at 125%, which lays out as 1280x720, and a 1280x720 window
## at 100%, which the project's stretch lays out as 1600x900 scaled down) and on each board (the 3D world and the 2D map) it
##   * puts the Table in each state it has (at rest with the first-game guide up, a notice, a move forecast, the Vision legend, the
##     playback bar and its caption, the fortress close-up) and reports the rect of every HUD piece, as drawn;
##   * sweeps the window on a grid with real mouse motion, asks the viewport which control the mouse is over, and reports every
##     point where an empty HUD area took the mouse, or a piece did not (the input contract, design/UX_WAR_TABLE.md 1.2);
##   * clicks empty HUD space over land and checks the province under it is picked, and clicks the padding of each piece over land
##     and checks the board never saw the click.
## It prints one line,
##   TABLE_REPORT {"3d": {"1600x900": {"rest": {"pieces": {name: [x, y, w, h, visible]}, "safe": [...], ...}, ...}, ...}, "2d": {...}}
## and never touches the player's settings or saves (they go to a scratch folder under user://).
##
##   godot --headless --path . --script res://tests/table_probe.gd

const SCRATCH := "user://table_probe"
const WAIT_BOARD_S := 120.0
## [key, window, content scale factor]: the logical size is the window over the factor, or the project's 1600x900 stretched.
const SIZES := [["1600x900", Vector2i(1600, 900), 1.0], ["1600x900@125", Vector2i(1600, 900), 1.25], ["1280x720", Vector2i(1280, 720), 1.0]]
const SWEEP_STEP := 40.0
const EDGE := 4.0  # a point this close to a piece's edge is not judged (the edge pixel belongs to either)

var report := {}
var game: GameScreen
var kind := "3d"
var _owners := {}  # Node -> piece name, for the sweep


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	GameSettings.default_path = SCRATCH.path_join("settings.cfg")
	_run()


func _run() -> void:
	await process_frame
	# One game for both boards (the second is the 2D map: Settings' choice, switched in place).
	for k in ["3d", "2d"]:
		kind = k
		report[kind] = {}
		if kind == "3d":
			await _start()
		else:
			game.use_board("2d")
			await _frames(6)
		for entry in SIZES:
			await _resize(entry)
			var sized := {}
			for scenario in _scenarios():
				sized[scenario] = await _measure(scenario)
			report[kind][String(entry[0])] = sized
	game.queue_free()
	await process_frame
	print("TABLE_REPORT " + JSON.stringify(report))
	quit()


func _scenarios() -> Array:
	var out := ["rest", "dismissed", "notice", "forecast", "vision", "army", "recruit", "march", "army_notice"]
	if kind == "3d":
		out.append_array(["playback", "closeup"])
	return out


func _start() -> void:
	var gs := GameSettings.new(SCRATCH.path_join("settings.cfg"))
	gs.set_board(kind)
	gs.save()
	GameSettings.reset_hint(GameSettings.HINT_FIRST_GAME)  # the guide shows
	GameSettings.reset_hint("fog")
	for h in GameScreen.SEAL_HINTS:
		GameSettings.reset_hint(h)
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
	if kind == "3d":
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


# --- the states ------------------------------------------------------------------------------------

## Back to the table at rest: nothing open, the capital selected with two recruits ordered (a tall card), the guide up.
func _rest() -> void:
	var map := game.map
	game._close_overlays()
	game.notice_panel.visible = false
	map.set_map_mode("")
	map.clear_preview()
	while not game.session.current_orders().is_empty():
		map.cancel_order(0)
	if map.board != null and String(map.board.closeup) != "":
		map.board.exit_closeup(true)
	if kind == "3d":
		_hide_playback()
	map.selected_army_id = ""
	var capital: String = map.state.find_faction("kingdom").capital
	map.select_province(capital)
	for i in 2:
		var types := map.orders.recruitable_types()
		if not types.is_empty():
			map.queue_recruit(String(types[0].id))
	game.first_game_guide.sync(game.session, map.state)


func _hide_playback() -> void:
	var overlay: Control = game.map.board.overlay
	overlay.play_bar().visible = false
	overlay.caption_panel().visible = false


func _setup(scenario: String) -> void:
	_rest()
	var map := game.map
	match scenario:
		"dismissed":
			map.dismiss_selection_card()
		"notice":
			game.show_notice("Game saved", "Saved as \"Saved 2026-10-10 14:03\". %s" % SaveGame.ORDERS_NOTE)
		"army":  # UX-3: the army card with its order on it
			map.select_army("kingdom-1")
			map.select_province("westwatch")
		"recruit":  # UX-3: the province card with the Recruit section open
			map.cards.open_section("recruit")
		"march":  # UX-3: picking a march destination: the card is a slim strip
			map.select_army("kingdom-1")
			map.cards.begin_march()
		"army_notice":  # UX-3: the crowded left column: a notice and the guide above the army card
			game.show_notice("Game saved", "Saved as \"Saved 2026-10-10 14:03\". %s" % SaveGame.ORDERS_NOTE)
			map.select_army("kingdom-1")
		"forecast":
			map.select_army("kingdom-1")
			map.preview_move("westwatch")
			if not map.hover_panel.visible:
				map.hover_label.text = "March to Westwatch: the forecast of the battle and its odds, long enough to wrap onto a second line of the move forecast bar."
				map.hover_panel.visible = true
		"vision":
			map.set_map_mode("vision")
		"playback":
			var overlay: Control = map.board.overlay
			overlay._play_label.text = "Turn 1 plays out: the armies march, and 1 battle is fought."
			overlay._phase_label.text = "Movement  ›  [Battles]  ›  Recruits"
			overlay._caption_title.text = "Battles"
			overlay._caption_detail.text = "Crossed swords mark a battle: the lines trade blows and the fallen lie where they fell."
			overlay.play_bar().visible = true
			overlay.caption_panel().visible = true
		"closeup":
			map.board.enter_closeup(map.state.find_faction("kingdom").capital, true)
	await _frames(6)


# --- measuring -------------------------------------------------------------------------------------

func _measure(scenario: String) -> Dictionary:
	await _setup(scenario)
	var hud := game.map.table()
	var pieces := _pieces()
	var rects := {}
	for name in pieces:
		rects[name] = _r(pieces[name])
	var out := {"pieces": rects, "safe": _rect_array(hud.safe_area()), "framing": _rect_array(hud.framing_area()),
		"viewport": [root.get_visible_rect().size.x, root.get_visible_rect().size.y], "hud": _r(hud), "compact": hud.compact,
		"overflow": hud.overflowed(), "placed": {}}
	for name in hud.placed():
		out.placed[name] = _rect_array(hud.placed()[name])
	if kind == "2d":
		var canvas := game.map.map_canvas
		out["canvas"] = [canvas.global_position.x, canvas.global_position.y, MapLayout.SIZE.x * canvas.scale.x, MapLayout.SIZE.y * canvas.scale.y, canvas.is_visible_in_tree()]
	out["card_parts"] = _card_parts()
	out["labels"] = _province_labels()
	out["sweep"] = await _sweep(pieces, rects)
	if scenario == "rest":
		out["clicks"] = await _clicks(pieces, rects)
		await _setup("rest")
		out["edges"] = await _edges()
		await _setup("rest")
	return out


## UX-3 (design/UX_WAR_TABLE.md §3.3): the card's rect with each province selected, then each army, at the camera's farthest and nearest
## zoom (the 3D board; the 2D map has one): {zoom key: [[what, id, x, y, w, h, visible], ...]}. The card is docked in the left column, so
## it must not depend on where the selection is on screen.
func _edges() -> Dictionary:
	var map := game.map
	var out := {}
	var zooms: Array = ["flat"]
	if kind == "3d":
		zooms = ["far", "near"]
	var centre := root.get_visible_rect().size * 0.5
	for z in zooms:
		if kind == "3d":
			var board: Board3D = map.board
			board.zoom_at(centre, -1.0 if z == "far" else 1.0)
			board.zoom_at(centre, -1.0 if z == "far" else 1.0)
			await _frames(3)
		var rows := []
		for p in map.state.provinces:
			map.selected_army_id = ""
			map.select_province(p.id)
			await _frames(5)  # the card's size settles over a few frames: its pinned row wraps once it has a width
			rows.append(["province", p.id] + _r(map.cards))
		for a in map.state.armies:
			if a.owner == "kingdom":
				map.select_army(a.id)
				await _frames(5)
				rows.append(["army", a.id] + _r(map.cards))
		out[z] = rows
	if kind == "3d":
		var board2: Board3D = map.board
		board2.zoom_at(centre, -1.0)
		await _frames(3)
	return out


## UX-3: where the selection card keeps its pinned actions and its scroll, as drawn: [x, y, w, h, visible] for the card's first action
## (the first button of the first pinned row), the pinned bar and the scroll; only the mode while the card is hidden or is the march strip.
func _card_parts() -> Dictionary:
	var cards: SelectionCards = game.map.cards
	var out := {"marching": cards.marching, "mode": cards.mode}
	if not cards.visible or cards.marching:
		return out
	var first: Control = null
	for c in cards.pinned.get_children():
		if c is Control and c.visible:
			first = c.get_child(0) as Control if c is HFlowContainer and c.get_child_count() > 0 else c as Control
			break
	out["first_action"] = _r(first)
	out["pinned"] = _r(cards.pinned)
	out["scroll"] = _r(cards.scroll)
	return out


## The name labels of the capital and of its neighbours as drawn (the first move of turn 1 is one of these), keyed by province id, with
## the capital's id under "capital": [x, y, w, h, visible] through each label's own transform (the 2D map scales its regions).
func _province_labels() -> Dictionary:
	var map := game.map
	var capital: String = map.state.find_faction("kingdom").capital
	var ids: Array = [capital]
	ids.append_array(map.state.find_province(capital).neighbors)
	var out := {"capital": capital, "rects": {}}
	for id in ids:
		var label: Control = null
		if kind == "3d":
			var plate: Dictionary = map.board.overlay._plates.get(id, {})
			label = plate.get("name", null)
		else:
			label = (map.regions[id] as ProvinceRegion).name_label
		if label != null:
			var r: Rect2 = label.get_global_transform() * Rect2(Vector2.ZERO, label.size)
			out.rects[id] = [r.position.x, r.position.y, r.size.x, r.size.y, label.is_visible_in_tree()]
	return out


## Every HUD piece by name: the Table's own and the three that hang elsewhere (the guide, the notice, the board's playback pieces).
func _pieces() -> Dictionary:
	var hud := game.map.table()
	var out := {"plaque": hud.plaque, "menu": hud.menu_button, "opponent": hud.opponent_panel, "stack": hud.notification_stack, "tray": hud.tray,
		"seal": hud.seal, "card": game.map.cards, "legend": game.map.vision_legend, "hover": game.map.hover_panel,
		"guide": game.first_game_guide, "notice": game.notice_panel}
	for id in hud.system_button_ids():
		out["sys_%s" % id] = hud.system_button(id)
	if kind == "3d":
		var overlay: Control = game.map.board.overlay
		out["playback"] = overlay.play_bar()
		out["caption"] = overlay.caption_panel()
		out["closeup"] = overlay.closeup_chip()
	return out


func _r(c: Control) -> Array:
	if c == null:
		return []
	var r := c.get_global_rect()
	return [r.position.x, r.position.y, r.size.x, r.size.y, c.is_visible_in_tree()]


func _rect_array(r: Rect2) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


# --- the input contract -------------------------------------------------------------------------------

## The pieces that take the mouse by design: everything else in the HUD ignores it. (The empty notification slot and the move forecast
## are pieces of the layout but never take a click.)
func _takes_mouse(name: String) -> bool:
	return name != "stack" and name != "hover"


func _motion(p: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	root.push_input(m, true)


## Which piece owns `control` (a piece or something inside one): its name, "hud:<node>" for an HUD node that is not a piece (a violation),
## and "" for anything of the board.
func _owner_of(control: Node, pieces: Dictionary) -> String:
	var hud := game.map.table()
	var n := control
	while n != null:
		for name in pieces:
			if pieces[name] == n:
				return String(name)
		if n == hud:
			return "hud:%s" % control.name
		n = n.get_parent()
	return ""


func _expected(p: Vector2, rects: Dictionary) -> String:
	for name in rects:
		var r: Array = rects[name]
		if r.size() == 5 and bool(r[4]) and _takes_mouse(String(name)) and Rect2(r[0], r[1], r[2], r[3]).has_point(p):
			return String(name)
	return ""


func _near_an_edge(p: Vector2, rects: Dictionary) -> bool:
	for name in rects:
		var r: Array = rects[name]
		if r.size() == 5 and bool(r[4]) and _takes_mouse(String(name)):
			var rect := Rect2(r[0], r[1], r[2], r[3])
			if rect.grow(EDGE).has_point(p) and not rect.grow(-EDGE).has_point(p):
				return true
	return false


func _sweep(pieces: Dictionary, rects: Dictionary) -> Dictionary:
	var size := root.get_visible_rect().size
	var points := 0
	var violations := []
	var over_pieces := {}
	var y := SWEEP_STEP * 0.5
	while y < size.y:
		var x := SWEEP_STEP * 0.5
		while x < size.x:
			var p := Vector2(x, y)
			if not _near_an_edge(p, rects):
				_motion(p)
				var h := root.gui_get_hovered_control()
				var got := _owner_of(h, pieces) if h != null else ""
				var want := _expected(p, rects)
				if got != want:
					# the viewport settles the hover over a frame: look again before calling it a violation
					await process_frame
					_motion(p)
					h = root.gui_get_hovered_control()
					got = _owner_of(h, pieces) if h != null else ""
				points += 1
				if want != "":
					over_pieces[want] = int(over_pieces.get(want, 0)) + 1
				if got != want and violations.size() < 12:
					violations.append({"at": [x, y], "want": want, "got": got, "control": h.get_class() if h != null else ""})
			x += SWEEP_STEP
		y += SWEEP_STEP
	return {"points": points, "violations": violations, "over_pieces": over_pieces}


## The province under `p` on the board, whatever is drawn over it (the HUD's pieces do not matter): the 3D board's own picking, or the
## 2D map's region geometry.
func _land_under(p: Vector2) -> String:
	if kind == "3d":
		return String(game.map.board.province_at(p - game.map.board.global_position))
	for id in game.map.regions:
		var region: ProvinceRegion = game.map.regions[id]
		if region._has_point(region.get_global_transform().affine_inverse() * p):
			return String(id)
	return ""


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
	await process_frame
	await process_frame


func _clicks(pieces: Dictionary, rects: Dictionary) -> Dictionary:
	var map := game.map
	var size := root.get_visible_rect().size
	var capital: String = map.state.find_faction("kingdom").capital
	var picks := []  # empty HUD space over land: the click must pick that province
	var tried := 0
	var y := 60.0
	while y < size.y - 60.0 and picks.size() < 8:
		var x := 60.0
		while x < size.x - 60.0 and picks.size() < 8:
			var p := Vector2(x, y)
			var id := _land_under(p)
			if not id.is_empty() and id != capital and _expected(p, rects).is_empty() and not _near_an_edge(p, rects) and (int(x / 40.0) + int(y / 40.0)) % 5 == 0:
				map.selected_army_id = ""
				map.select_province(capital)
				await _frames(1)
				var before: String = map.selected_province_id
				await _click(p)
				picks.append({"at": [x, y], "want": id, "got": map.selected_province_id, "before": before})
			x += SWEEP_STEP
		y += SWEEP_STEP
		tried += 1
	# Each piece eats its own click: a point in the padding of the piece, over land, leaves the selection as it was.
	var eaten := []
	for name in ["plaque", "opponent", "tray", "seal", "card"]:
		var r: Array = rects.get(name, [])
		if r.size() != 5 or not bool(r[4]):
			continue
		var rect := Rect2(r[0], r[1], r[2], r[3])
		var p := rect.position + Vector2(3, 3)
		var land := _land_under(p)
		map.selected_army_id = ""
		map.select_province(capital)
		await _frames(1)
		var turns_before: int = game.session.turns_played()
		await _click(p)
		eaten.append({"piece": name, "at": [p.x, p.y], "land": land, "selected": map.selected_province_id, "capital": capital,
			"army": map.selected_army_id, "turns": game.session.turns_played() - turns_before})
	return {"picks": picks, "eaten": eaten}
