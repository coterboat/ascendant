## The 3D world map, dev preview (spike, branch spike-3d-world). Run it with
##     godot --path . -- --world3d                (from the title, via world3d/launch.gd)
##     godot --path . res://world3d/world_preview.tscn
## Options after `--`: --look=cel|painted  --start (the turn-0 game instead of a mid-game)
##   --turns=N (turns autoplayed before the shown one)  --primitive (primitive figures, not the model table's GLBs)
##   --primitive-fort  --shots=DIR (the evidence screenshots, then quit)  --perf=FILE (fps, then quit)
##
## It builds the land off the main thread (terrain3d.gd), then the world (world_view.gd), the
## armies of a real GameState (armies.gd; the game is autoplayed by the real AIPlayer through the
## real TurnResolver, scenario.gd) and the 2D overlay (overlay.gd). Space plays the next real turn.
extends Node

const Terrain3D := preload("res://world3d/terrain3d.gd")
const WorldView := preload("res://world3d/world_view.gd")
const Armies := preload("res://world3d/armies.gd")
const Overlay := preload("res://world3d/overlay.gd")
const Scenario := preload("res://world3d/scenario.gd")
const Kit := preload("res://world3d/kit.gd")
const Models := preload("res://world3d/models.gd")
const Playback := preload("res://world3d/playback.gd")

const SPAN_FAR := 600.0
const SPAN_NEAR := 70.0
const PITCH_FAR := 58.0
const PITCH_NEAR := 42.0
const GAME_SEED := 4242
const HELP := "[1] whole map  [2] Crownkeep  [3] Fangridge  [Space] play the turn  [R] reset\n[L] look A/B  [P] probe figures  [F] fortress model  [Q] quality  [E] effects  [O] orbit  [Esc] title\nDrag: pan   Wheel: zoom to cursor   Right-drag (orbit on): turn"

var wv: Node3D
var armies: Node3D
var overlay: Control
var hud: Label
var status: Label
var terrain: RefCounted
var turns: Array = []
var turn_i := 0
var seats: Array = []
var shown: GameState
var zoom := 0.0 ## 0 the whole map, 1 all the way in
var goal := {} ## the rig the camera eases to
var orbit := false
var effects := true
var _task := -1
var _terrain_out: RefCounted
var _drag := false
var _drag_ground := Vector2.ZERO
var _turning := false
var _opts := {}
var _slow := 0.0
var _auto_quality := true
var built := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			_opts[kv[0]] = kv[1]
		elif a.begins_with("--"):
			_opts[a.substr(2)] = true
	var cl := CanvasLayer.new()
	cl.layer = 1
	add_child(cl)
	overlay = Overlay.new()
	cl.add_child(overlay)
	hud = Label.new()
	hud.text = "Building the world..."
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 14)
	hud.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	hud.add_theme_color_override("font_outline_color", UiPalette.KEYLINE_INK)
	hud.add_theme_constant_override("outline_size", 5)
	cl.add_child(hud)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", UiPalette.GILT)
	status.add_theme_color_override("font_outline_color", UiPalette.KEYLINE_INK)
	status.add_theme_constant_override("outline_size", 5)
	status.anchor_top = 1.0
	status.anchor_bottom = 1.0
	status.offset_top = -34
	status.offset_left = 16
	cl.add_child(status)
	_task = WorkerThreadPool.add_task(func(): _terrain_out = Terrain3D.build(), false, "3D land")


## Closed while the land still builds: wait for the worker, which writes into this node.
func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _process(delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_build()
	if not built:
		return
	wv.view_size = get_viewport().get_visible_rect().size
	_camera(delta)
	_toy_scale()
	_watch_speed(delta)
	var fps := Engine.get_frames_per_second()
	status.text = "%s | look %s | quality %d | effects %s | %s figures | %d fps | turn %d%s" % [
		"Look A: Bright Cel" if wv.look == "cel" else "Look B: lit painted", wv.look, wv.quality, "on" if effects else "off",
		armies.figure_count(), fps, shown.current_turn, "  (playing)" if armies.playing() else ""]


func _build() -> void:
	terrain = _terrain_out
	wv = WorldView.new()
	wv.name = "World"
	if _opts.has("primitive-fort"):
		wv.fortress_style = "primitive"
	add_child(wv)
	wv.setup(terrain, str(_opts.get("look", "cel")))
	armies = Armies.new()
	armies.name = "Armies"
	armies.wv = wv
	armies.prefer_models = not _opts.has("primitive")
	wv.add_child(armies)
	armies.captured.connect(func(_p, _o): pass)
	armies.playback_finished.connect(_on_marchers_arrived)
	overlay.wv = wv
	overlay.armies = armies
	overlay.build_labels()
	## the game: a real one, autoplayed by the AI for both factions
	if not _opts.has("start"):
		turns = Scenario.autoplay(GAME_SEED, int(_opts.get("turns", 7)))
		turn_i = Scenario.best_turn(turns)
	_show(turns[turn_i]["before"] if not turns.is_empty() else Scenario.start(GAME_SEED))
	_frame("whole", true)
	hud.text = HELP
	built = true
	print("world3d: land %dx%d cells in %d ms; %d props; %d figures; turn %d (%d turns played)" % [
		terrain.w, terrain.h, terrain.millis, wv.prop_count(), armies.figure_count(), shown.current_turn, turns.size()])
	if _opts.has("shots"):
		_shots.call_deferred(str(_opts["shots"]))
	elif _opts.has("perf"):
		_perf.call_deferred(str(_opts["perf"]))


func _show(s: GameState) -> void:
	shown = s
	seats = UiPalette.seat_order(s)
	armies.show_state(s, seats)
	_paint_owners(s)
	overlay.build_plates(s, seats)


func _paint_owners(s: GameState) -> void:
	var cols := {}
	for p in s.provinces:
		if not p.owner.is_empty():
			cols[p.id] = UiPalette.owner_color(s, p.owner, seats)
	wv.set_owners(cols)
	for id in wv.fortresses.keys():
		var p := s.find_province(id)
		wv.set_fortress_colour(id, UiPalette.owner_color(s, p.owner, seats) if p != null and not p.owner.is_empty() else UiPalette.NEUTRAL)


func play_turn() -> void:
	if armies.playing() or turns.is_empty():
		return
	if shown != turns[turn_i]["before"]:
		_show(turns[turn_i]["before"])
	_play(turns[turn_i])


## Plays a Scenario turn through the board's playback (world3d/playback.gd).
func _play(turn: Dictionary) -> void:
	armies.play(Playback.plan(turn["before"], turn["events"], turn["after"]), turn["before"], turn["after"])


func _on_marchers_arrived() -> void:
	var after: GameState = turns[turn_i]["after"]
	_paint_owners(after)
	shown = after
	overlay.build_plates(after, seats)
	if turn_i + 1 < turns.size():
		turn_i += 1


# ------------------------------------------------------------------ the camera

func rig_for(target: Vector2, z: float, yaw := 0.0) -> Dictionary:
	var span: float = exp(lerpf(log(SPAN_FAR), log(SPAN_NEAR), z))
	var pitch: float = lerpf(PITCH_FAR, PITCH_NEAR, z)
	var h: float = maxf(terrain.height_at(target), 0.0) if z > 0.3 else 0.0
	return {"target": Vector3(target.x, h, target.y), "pitch": pitch, "yaw": yaw, "fov": 30.0, "span": span}


func _frame(what: String, instant := false) -> void:
	match what:
		"whole":
			zoom = 0.0
			goal = rig_for(Vector2(500, 318), 0.0)
		"crownkeep", "fangridge":
			zoom = 0.86
			var c: Vector2 = terrain.centre_of(what)
			var g: Vector2 = wv.gate_dir(what)
			goal = rig_for(c + g * 8.0 + Vector2(0, 4), zoom)
	if instant:
		wv.rig = goal.duplicate()
		wv.apply_rig()


func frame_at(target: Vector2, z: float, yaw := 0.0, instant := true) -> void:
	zoom = z
	goal = rig_for(target, z, yaw)
	if instant:
		wv.rig = goal.duplicate()
		wv.apply_rig()


func _camera(delta: float) -> void:
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan.x += 1
	if pan != Vector2.ZERO:
		var yaw: float = deg_to_rad(goal["yaw"])
		var v: Vector2 = pan.rotated(-yaw) * float(goal["span"]) * 0.9 * delta
		_move_goal(v)
	var k: float = 1.0 - exp(-delta * 9.0)
	var r: Dictionary = wv.rig
	r["target"] = (r["target"] as Vector3).lerp(goal["target"], k)
	r["span"] = exp(lerpf(log(float(r["span"])), log(float(goal["span"])), k))
	r["pitch"] = lerpf(r["pitch"], goal["pitch"], k)
	r["yaw"] = float(r["yaw"]) + wrapf(float(goal["yaw"]) - float(r["yaw"]), -180.0, 180.0) * k
	wv.apply_rig()


## Far out, the figures stand taller (toy scale) so every army reads as a marker over the map.
func _toy_scale() -> void:
	var z: float = clampf((log(float(wv.rig["span"])) - log(SPAN_FAR)) / (log(SPAN_NEAR) - log(SPAN_FAR)), 0.0, 1.0)
	armies.set_fig_scale(lerpf(1.8, 1.0, smoothstep(0.0, 0.8, z)))


func _move_goal(v: Vector2) -> void:
	var t: Vector3 = goal["target"]
	var p := Vector2(clampf(t.x + v.x, -20.0, 1020.0), clampf(t.z + v.y, 0.0, 620.0))
	var h: float = maxf(terrain.height_at(p), 0.0) if zoom > 0.3 else 0.0
	goal["target"] = Vector3(p.x, h, p.y)


func _unhandled_input(ev: InputEvent) -> void:
	if not built:
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_zoom_at(mb.position, 0.07 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -0.07)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = mb.pressed
			if _drag:
				_snap_rig()
				_drag_ground = wv.unproject(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_turning = mb.pressed and orbit
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _drag:
			## the ground under the hand stays under the hand
			_snap_rig()
			var now: Vector2 = wv.unproject(mm.position)
			_move_goal(_drag_ground - now)
			_snap_rig()
		elif _turning:
			goal["yaw"] = float(goal["yaw"]) - mm.relative.x * 0.3
	elif ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo:
		match (ev as InputEventKey).keycode:
			KEY_1:
				_frame("whole")
			KEY_2:
				_frame("crownkeep")
			KEY_3:
				_frame("fangridge")
			KEY_SPACE:
				play_turn()
			KEY_R:
				turn_i = Scenario.best_turn(turns) if not turns.is_empty() else 0
				_show(turns[turn_i]["before"] if not turns.is_empty() else Scenario.start(GAME_SEED))
			KEY_L:
				wv.set_look("painted" if wv.look == "cel" else "cel")
			KEY_P:
				armies.prefer_models = not armies.prefer_models
				armies.show_state(shown, seats)
			KEY_F:
				_rebuild_fortresses()
			KEY_Q:
				_auto_quality = false
				wv.set_quality((wv.quality + 1) % 4)
			KEY_E:
				effects = not effects
				wv.set_effects(effects)
			KEY_O:
				orbit = not orbit
				if not orbit:
					goal["yaw"] = 0.0
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://ui/title_screen.tscn")


func _snap_rig() -> void:
	wv.rig = goal.duplicate()
	wv.apply_rig()


func _zoom_at(screen: Vector2, dz: float) -> void:
	## zoom to the cursor: the ground under it stays under it
	_snap_rig()
	var g0: Vector2 = wv.unproject(screen)
	zoom = clampf(zoom + dz, 0.0, 1.0)
	var t: Vector3 = goal["target"]
	var yaw: float = goal["yaw"]
	goal = rig_for(Vector2(t.x, t.z), zoom, yaw)
	for i in 3:
		_snap_rig()
		var g1: Vector2 = wv.unproject(screen)
		_move_goal(g0 - g1)
	_snap_rig()


func _rebuild_fortresses() -> void:
	wv.fortress_style = "primitive" if wv.fortress_style == "ludo" else "ludo"
	for f in wv.fortresses.values():
		(f["node"] as Node).queue_free()
	wv.fortresses.clear()
	for i in terrain.ids.size():
		if terrain.is_capital[i]:
			wv._place_fortress(terrain.ids[i], terrain.centres[i], wv.gate_dir(terrain.ids[i]))
	_paint_owners(shown)
	armies.show_state(shown, seats)


func _watch_speed(delta: float) -> void:
	## a slower machine sheds the dearest effects a step at a time: under 40 fps for 3 s together
	if not _auto_quality or wv.quality >= 3 or _opts.has("perf") or _opts.has("shots"):
		return
	if delta > 1.0 / 40.0:
		_slow += delta
	else:
		_slow = maxf(0.0, _slow - delta * 0.5)
	if _slow > 3.0:
		_slow = 0.0
		wv.set_quality(wv.quality + 1)
		print("world3d: running slow, quality step %d" % wv.quality)


# ------------------------------------------------------------------ evidence: shots and perf

func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(dir: String, name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
	print("shot ", name, " ", img.get_size())


func _shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var only: String = str(_opts.get("only", ""))
	print("shots: start")
	await _wait(20)
	print("shots: waited")
	for lk in ["cel", "painted"]:
		wv.set_look(lk)
		if only == "" or only.contains("whole"):
			_frame("whole", true)
			await _wait(8)
			await _shot(dir, "01_whole_%s" % lk)
		if only == "" or only.contains("mid"):
			frame_at(Vector2(330, 300), 0.45)
			await _wait(8)
			await _shot(dir, "02_mid_%s" % lk)
		if only == "" or only.contains("close"):
			_frame("crownkeep", true)
			await _wait(8)
			await _shot(dir, "03_crownkeep_close_%s" % lk)
			_frame("fangridge", true)
			await _wait(8)
			await _shot(dir, "04_fangridge_close_%s" % lk)
	wv.set_look(str(_opts.get("look", "cel")))
	if only == "" or only.contains("march"):
		## the march-out: framed on the capital that sends an army, frames through the turn
		var turn: Dictionary = turns[turn_i]
		var src := "crownkeep"
		for m in Scenario.moves_of(turn):
			var p: Province = (turn["before"] as GameState).find_province(m["from"])
			if p != null and p.is_capital:
				src = m["from"]
				break
		var c: Vector2 = terrain.centre_of(src)
		var g: Vector2 = wv.gate_dir(src)
		frame_at(c + g * 30.0, 0.74)
		await _wait(6)
		_play(turn)
		armies.set_process(false)
		var marks := [0.0, 1.2, 2.4, 3.6, 5.0, 7.0, 10.0]
		var tnow := 0.0
		for i in marks.size():
			while tnow < marks[i]:
				armies.step_playback(1.0 / 30.0)
				tnow += 1.0 / 30.0
			await _wait(2)
			await _shot(dir, "05_march_%02d_t%04.1f" % [i, marks[i]])
		## the same turn from higher up: every column of both sides on the move at once
		frame_at(Vector2(500, 300), 0.12)
		var wide_done := false
		while armies.playing() and tnow < 40.0:
			armies.step_playback(1.0 / 30.0)
			tnow += 1.0 / 30.0
			if not wide_done and tnow >= 12.0:
				wide_done = true
				await _wait(2)
				await _shot(dir, "05_march_wide_t12")
		armies.set_process(true)
		await _wait(4)
		await _shot(dir, "05_march_after_wide")
		_show(turns[turn_i]["before"] if turn_i < turns.size() else shown)
	if only == "" or only.contains("probe"):
		armies.prefer_models = true
		armies.show_state(shown, seats)
		_frame("crownkeep", true)
		frame_at(terrain.centre_of("crownkeep") + wv.gate_dir("crownkeep") * 6.0, 0.97)
		await _wait(8)
		await _shot(dir, "06_probe_close_cel")
		wv.set_look("painted")
		await _wait(4)
		await _shot(dir, "06_probe_close_painted")
		wv.set_look("cel")
		_frame("fangridge", true)
		await _wait(8)
		await _shot(dir, "06_probe_fangridge")
		frame_at(Vector2(500, 300), 0.2)
		await _wait(8)
		await _shot(dir, "06_probe_far")
		armies.prefer_models = false
		armies.show_state(shown, seats)
	if only == "" or only.contains("stand"):
		## the probe's models beside the placeholders, on a stand over the sea north of the map
		var stand := _showcase()
		for lk in ["cel", "painted"]:
			wv.set_look(lk)
			wv.rig = {"target": Vector3(500, 5.5, -62), "pitch": 16.0, "yaw": 0.0, "fov": 30.0, "span": 30.0}
			goal = wv.rig.duplicate()
			wv.apply_rig()
			await _wait(8)
			await _shot(dir, "06_stand_%s" % lk)
		wv.set_look("cel")
		stand.queue_free()
	if only == "" or only.contains("overlay"):
		frame_at(Vector2(560, 320), 0.35)
		await _wait(8)
		await _shot(dir, "07_overlay")
	if only.contains("prim"):
		_rebuild_fortresses()
		_frame("crownkeep", true)
		await _wait(8)
		await _shot(dir, "08_primitive_fortress")
	get_tree().quit()


## A stand of figures: each placeholder beside the probe's model of the same unit, facing the camera.
func _showcase() -> Node3D:
	var root := Node3D.new()
	root.name = "Stand"
	wv.add_child(root)
	var at := Vector3(500, 0, -62)
	var b := Kit.Builder.new()
	b.cyl(30.0, 31.0, 6.0, Vector3(0, -3.0, 0), Color("#8DB35E"), 40)
	b.cyl(31.2, 31.2, 0.6, Vector3(0, -0.8, 0), Color("#5E4128"), 40)
	var plinth := MeshInstance3D.new()
	plinth.mesh = b.mesh()
	plinth.material_override = wv.model_mat(Color.WHITE)
	plinth.position = at + Vector3(0, 6.0, 0)
	root.add_child(plinth)
	var row: Array = [["spearmen", false], ["spearmen", true], ["crossbowmen", false], ["knights", false], ["knight_captain", false],
		["tuskers", false], ["tuskers", true], ["fangthrowers", false], ["war_bear", false], ["warchief", false]]
	var x := -20.5
	for e in row:
		var mi := MeshInstance3D.new()
		var fm: Dictionary = Models.figure_mesh(e[0], e[1])
		mi.mesh = fm["mesh"]
		var tex: Texture2D = fm["tex"]
		mi.material_override = wv.model_mat(UiPalette.seat_color(0 if e[0] in ["spearmen", "crossbowmen", "knights", "knight_captain"] else 1), tex)
		var w: float = 9.0 if e[0] == "war_bear" else (5.5 if e[0] in ["knights", "knight_captain", "tuskers", "warchief"] else 4.2)
		x += w * 0.5
		mi.position = at + Vector3(x, 6.0, 4.0 if e[1] else 0.0)
		mi.rotation.y = PI + (0.5 if e[0] in ["knights", "knight_captain", "war_bear"] else 0.25)
		x += w * 0.5
		root.add_child(mi)
	return root


func _perf(path: String) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var vp_rid: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	var results: Array = []
	await _wait(30)
	var views := ["whole", "zoom", "march"]
	var looks: Array = ["cel", "painted"] if not _opts.has("quick") else ["cel"]
	var quals: Array = [0, 3] if not _opts.has("quick") else [0]
	var stress := float(_opts.get("stress", 1.0)) ## render scale > 1 to find the headroom
	get_viewport().scaling_3d_scale = stress
	for lk in looks:
		wv.set_look(lk)
		for q in quals:
			wv.set_quality(q)
			if stress != 1.0:
				get_viewport().scaling_3d_scale = stress * (1.0 if q < 3 else 0.75)
			for fx in [true, false]:
				if q == 3 and not fx:
					continue
				effects = fx
				wv.set_effects(fx)
				for v in views:
					if v == "whole":
						_frame("whole", true)
					elif v == "zoom":
						_frame("crownkeep", true)
					else:
						frame_at(terrain.centre_of("crownkeep") + wv.gate_dir("crownkeep") * 60.0, 0.5)
						_show(turns[turn_i]["before"])
						_play(turns[turn_i])
						armies.step_playback(4.0)
					await _wait(20)
					var frames := 0
					var gpu := 0.0
					var cpu := 0.0
					var t0 := Time.get_ticks_usec()
					while Time.get_ticks_usec() - t0 < 2500000:
						await get_tree().process_frame
						frames += 1
						gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
						cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
					var secs: float = (Time.get_ticks_usec() - t0) / 1.0e6
					var row := {"look": lk, "quality": q, "effects": fx, "view": v, "fps": snappedf(frames / secs, 0.1),
						"gpu_ms": snappedf(gpu / frames, 0.01), "cpu_ms": snappedf(cpu / frames, 0.01),
						"figures": armies.figure_count(), "size": get_viewport().get_texture().get_size()}
					results.append(row)
					print("perf ", row)
	wv.set_quality(0)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"screen_scale": DisplayServer.screen_get_scale(), "window": DisplayServer.window_get_size(),
		"render": get_viewport().get_texture().get_size(), "renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "rows": results}, " "))
	f.close()
	get_tree().quit()
