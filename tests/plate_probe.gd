extends SceneTree
## UX-2's plates through the real input paths (run by tests/test_plate_labels.gd as a subprocess, like table_probe.gd: the
## runner calls tests synchronously, before the scene tree has started, so nothing it builds can take the keyboard focus).
## It stands a fog game's 3D board in the tree, lets a few frames pass, and then drives the plates with pushed input events:
##   * Tab moves the keyboard focus onto a plate; the arrow keys do not hop it to another plate; the plate's detail and focus tip open
##   * F1 with the focus on a plate, and a right-click on it, ask for its codex entry; Enter selects its province
##   * the mouse over a plate makes it the hovered control, with its own tooltip (what the engine asks for), and opens its detail
##   * a left click on a plate gives the focus back
## and prints one line: PLATE_REPORT {json}. Dev and test only.

const Kit := preload("res://tests/fog_test_kit.gd")

var asked := []
var vp: SubViewport = null


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _key(code: Key, physical: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e


func _mouse_at(p: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	vp.push_input(m)


func _click(p: Vector2, button: MouseButton) -> void:
	var e := InputEventMouseButton.new()
	e.position = p
	e.global_position = p
	e.button_index = button
	e.pressed = true
	vp.push_input(e)
	var up := e.duplicate() as InputEventMouseButton
	up.pressed = false
	vp.push_input(up)


func _run() -> void:
	var report := {"ok": false}
	var g: Dictionary = Kit.games()[0]
	var t: Dictionary = g.turns.back()
	var view: GameState = t.view_after["kingdom"]
	vp = SubViewport.new() ## the headless window is tiny: the plates live in a viewport of the game's own size
	vp.size = Vector2i(1600, 900)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var map := load("res://ui/map_screen.tscn").instantiate() as MapScreen
	vp.add_child(map)
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.set_fog(t.memory_after["kingdom"], t.intel_after["kingdom"], t.view_before["kingdom"])
	map.set_state(view, "kingdom")
	var b := Board3D.new()
	map.set_board(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.build_now()
	map.codex_requested.connect(func(key: String): asked.append(key))
	await _frames(4)
	var o: Control = b.overlay
	report["plates"] = o._plates.size()
	report["viewport"] = [vp.size.x, vp.size.y]
	# Tab: the first plate takes the focus, and its detail and the focus tip open
	vp.push_input(_key(KEY_TAB))
	await _frames(2)
	var owner_ctl := vp.gui_get_focus_owner()
	var pid := ""
	for id in o._plates:
		if o._plates[id].root == owner_ctl:
			pid = id
	report["tab_focus"] = pid
	if pid.is_empty():
		print("PLATE_REPORT " + JSON.stringify(report))
		quit()
		return
	var plate: Control = o._plates[pid].root
	report["tab_detail"] = o.plate_active(pid) and bool((o._plates[pid].parts.gold as Control).visible)
	report["tab_tip"] = o._focus_tip != null and o._focus_tip.visible and o._focus_label.text == o.plate_tooltip(pid)
	# the arrow keys keep the board panning: the focus does not hop to another plate
	for k in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		vp.push_input(_key(k))
		await _frames(1)
	report["arrows_keep_focus"] = vp.gui_get_focus_owner() == plate
	# F1 with the focus on the plate asks for its codex entry
	asked.clear()
	vp.push_input(_key(KEY_F1))
	await _frames(1)
	report["f1"] = asked.duplicate()
	report["f1_want"] = String(plate.get_meta(CodexLink.META))
	# Enter selects the province
	map.selected_province_id = ""
	vp.push_input(_key(KEY_ENTER))
	await _frames(1)
	report["enter_selected"] = String(map.selected_province_id)
	map.selected_province_id = ""
	# Shift+Tab goes back; focus leaves the plate and the tip goes with it
	plate.release_focus()
	await _frames(1)
	report["released_tip_hidden"] = not o._focus_tip.visible
	# the mouse: a plate on screen and not under something else
	var hit := ""
	for id in o._plates:
		var r: Control = o._plates[id].root
		if not r.visible:
			continue
		var rect: Rect2 = r.get_global_rect()
		var c := rect.get_center()
		if rect.size.x < 4.0 or not Rect2(Vector2.ZERO, Vector2(vp.size)).has_point(c):
			continue
		_mouse_at(c)
		await _frames(1)
		if vp.gui_get_hovered_control() == r:
			hit = id
			break
	report["mouse_plate"] = hit
	if not hit.is_empty():
		var hp: Control = o._plates[hit].root
		var c2 := hp.get_global_rect().get_center()
		report["mouse_tip_is_plates"] = hp.get_tooltip(hp.get_local_mouse_position()) == o.plate_tooltip(hit)
		report["mouse_tip_names_province"] = hp.get_tooltip(Vector2.ZERO).contains(view.find_province(hit).name)
		report["mouse_detail"] = bool((o._plates[hit].parts.gold as Control).visible)
		asked.clear()
		_click(c2, MOUSE_BUTTON_RIGHT)
		await _frames(1)
		report["right_click"] = asked.duplicate()
		report["right_click_want"] = String(hp.get_meta(CodexLink.META))
		# the mouse leaves: the detail closes
		var away := Vector2(8, 8)
		for gy in range(8, 880, 60):
			for gx in range(8, 1580, 60):
				var q := Vector2(gx, gy)
				if b.province_at(q).is_empty() and not hp.get_global_rect().has_point(q):
					away = q
					break
			if away != Vector2(8, 8):
				break
		_mouse_at(away)
		await _frames(2)
		report["mouse_left_closes"] = not bool((o._plates[hit].parts.gold as Control).visible)
		report["dbg_left"] = [o._plate_hover, b.hover_id, String(map.selected_province_id), o._plate_focus, [away.x, away.y], vp.gui_get_hovered_control().name if vp.gui_get_hovered_control() != null else ""]
		# a left click goes through to the board, and the plate does not keep the keyboard focus
		_mouse_at(c2)
		await _frames(1)
		hp.grab_focus()
		_click(c2, MOUSE_BUTTON_LEFT)
		await _frames(3)
		report["left_click_releases_focus"] = vp.gui_get_focus_owner() != hp
	report["ok"] = true
	print("PLATE_REPORT " + JSON.stringify(report))
	map.free()
	quit()
