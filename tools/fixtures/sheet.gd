extends SceneTree
## Draws pose models with their attachments for placing and judging fixtures (ART-PIPE 3, #196). Dev tool only: it never runs in the
## game or the tests. Windowed only (headless has no renderer); always pass --always-on-top, an occluded window never draws.
##
##   $GODOT --path . --always-on-top --resolution 640x640 -s res://tools/fixtures/sheet.gd -- --plan=/abs/plan.json --out=/abs/dir
##
## The plan is a JSON list of shots, one PNG each (named by "file"; `python3 tools/ludo/asc_3d_fixtures.py sheet` lays them out):
##
##   {"file": "front.png", "title": "front", "mode": "raw", "view": "front", "extent": 0.7, "center": [0, 0.5, 0],
##    "markers": [[0.3, 0.4, 0.1]],
##    "items": [{"label": "...", "path": "res://assets/models/units/beasts/bloodsworn_strike.glb", "pose": "strike",
##               "row": {"attachments": [{"mesh": "res://...blade.glb", "pivot": [0, -0.5, 0],
##                                        "poses": {"strike": {"pos": [0.3, 0.4, 0.1], "rot": [0, 0, 45], "scale": 0.5}}}]}}]}
##
##   mode "raw"    the first item's pose model with its attachments baked in (Models.baked_model), in the model's OWN space, plain lit,
##                 seen from "view" ("front", "back", "left", "right", "top": orthographic, with a graph-paper scale of 0.1 along
##                 both edges in the model's coordinates, the numbers a row's "pos" takes) or from "yaw" / "pitch" degrees
##                 (perspective). "center" and "extent" (half the view's height) frame it; left out, the model's own box does.
##                 "markers" are small red crosses at those points of the model's space (where a pivot lands, for instance).
##   mode "board"  every item as the board draws a figure (Models._glb_figure: sized, turned, on its team base, Look A's cel shader
##                 and ink outline, a man six world units tall), side by side, at the board's near camera pitch (or "pitch"); "yaw"
##                 turns the figures away from the camera (22 by default, 180 shows their backs). An item's "type" and "faction"
##                 name its table row's look (the base), its "row" the row it is built from.
##
## Items' "row" is the figure row (world3d/models.json) as it would be: the shot never reads or changes the installed table.

const Models := preload("res://world3d/models.gd")
const Kit := preload("res://world3d/kit.gd")
const SH_MODEL := preload("res://world3d/shaders/model_cel.gdshader")
const SH_OUTLINE := preload("res://world3d/shaders/outline.gdshader")

const FOV := 30.0
const TEAM := {"kingdom": Color(0.2, 0.36, 0.85), "beasts": Color(0.85, 0.27, 0.17)}
const VIEWS := {"front": [0.0, 0.0], "right": [90.0, 0.0], "back": [180.0, 0.0], "left": [270.0, 0.0], "top": [0.0, 90.0]}


## The scale along the view's two edges: lines every 0.1 of the model's space, numbered every 0.2.
class Scale extends Control:
	var lines: Array = [] ## [{"a": Vector2, "b": Vector2, "major": bool}]
	var labels: Array = [] ## [{"p": Vector2, "t": String}]
	var markers: Array = [] ## [Vector2]

	func _draw() -> void:
		for l in lines:
			draw_line(l["a"], l["b"], Color(0.1, 0.1, 0.4, 0.34 if l["major"] else 0.14), 1.0)
		var font := ThemeDB.fallback_font
		for t in labels:
			draw_string(font, t["p"], t["t"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.05, 0.05, 0.3))
		for m in markers:
			draw_line(m + Vector2(-9, 0), m + Vector2(9, 0), Color(0.9, 0.0, 0.0), 2.0)
			draw_line(m + Vector2(0, -9), m + Vector2(0, 9), Color(0.9, 0.0, 0.0), 2.0)


var out := ""
var plan: Array = []
var root3: Node3D
var cam: Camera3D
var holder: Node3D
var title: Label
var tags: Array = []
var scale_ctl: Scale
var outline_mat: ShaderMaterial
var vp := Vector2(640, 640)
var sun: DirectionalLight3D
var env: Environment
var ground: MeshInstance3D
var grid: Node3D


func _initialize() -> void:
	var plan_path := ""
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"out": out = kv[1]
			"plan": plan_path = kv[1]
	if out.is_empty() or plan_path.is_empty():
		push_error("fixtures/sheet: --plan=FILE.json and --out=DIR are required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	if not (parsed is Array):
		push_error("fixtures/sheet: %s is not a JSON list" % plan_path)
		quit(2)
		return
	plan = parsed
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.gui_disable_input = true
	_run.call_deferred()


func _build_scene() -> void:
	vp = Vector2(root.size)
	root3 = Node3D.new()
	root.add_child(root3)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.80, 0.86, 1.0)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	root3.add_child(we)
	sun = DirectionalLight3D.new()
	root3.add_child(sun)
	ground = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 300)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.47, 0.64, 0.33)
	gm.roughness = 1.0
	ground.material_override = gm
	root3.add_child(ground)
	grid = Node3D.new()
	root3.add_child(grid)
	for k in range(-30, 31):
		_line(Vector3(k * Kit.FIG, 0.02, -90), Vector3(k * Kit.FIG, 0.02, 90))
	for k in range(-15, 16):
		_line(Vector3(-180, 0.02, k * Kit.FIG), Vector3(180, 0.02, k * Kit.FIG))
	holder = Node3D.new()
	root3.add_child(holder)
	cam = Camera3D.new()
	cam.current = true
	root3.add_child(cam)
	outline_mat = ShaderMaterial.new()
	outline_mat.shader = SH_OUTLINE
	outline_mat.set_shader_parameter("screen", vp)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	scale_ctl = Scale.new()
	scale_ctl.size = vp
	scale_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(scale_ctl)
	title = _label(layer, 22, Vector2(0, 6), vp.x, HORIZONTAL_ALIGNMENT_CENTER)


func _line(a: Vector3, b: Vector3) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.36, 0.52, 0.26)
	mi.material_override = m
	grid.add_child(mi)


func _label(layer: CanvasLayer, size: int, pos: Vector2, width: float, align: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(width, size + 12)
	l.horizontal_alignment = align as HorizontalAlignment
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.10, 0.09, 0.14))
	l.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	layer.add_child(l)
	return l


func _board_look(on: bool) -> void:
	## the board's look (model_compare.gd): green ground with a one-man grid, a low warm sun; the raw look: a plain grey ground-less void
	ground.visible = on
	grid.visible = on
	env.background_color = Color(0.62, 0.74, 0.88) if on else Color(0.80, 0.80, 0.82)
	env.ambient_light_energy = 0.24 if on else 0.55
	sun.shadow_enabled = on
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.12 if on else 0.9
	if on:
		sun.basis = Basis.looking_at(-Vector3(-0.55, 0.78, 0.42).normalized(), Vector3.UP)
	scale_ctl.visible = not on


func _board_figure(d: Dictionary, faction: String, x: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = d["mesh"]
	var m := ShaderMaterial.new()
	m.shader = SH_MODEL
	m.next_pass = outline_mat
	m.set_shader_parameter("team", TEAM.get(faction, Color(0.8, 0.8, 0.8)))
	m.set_shader_parameter("fig_lift", 1.0)
	if d.get("tex") != null:
		m.set_shader_parameter("albedo_tex", d["tex"])
		m.set_shader_parameter("use_tex", true)
	mi.material_override = m
	mi.position = Vector3(x, 0, 0)
	mi.rotation.y = deg_to_rad(180.0)
	holder.add_child(mi)
	return mi


func _shoot_board(s: Dictionary) -> bool:
	var figs: Array = []
	var tall := 0.0
	var half := 0.0
	for it in s["items"]:
		var d := Models._glb_figure(String(it["path"]), String(it.get("type", "bloodsworn")), it.get("row", {}), String(it.get("pose", "ready")))
		if d.is_empty():
			push_error("fixtures/sheet: %s: %s did not build" % [s["file"], it["path"]])
			return false
		figs.append(d)
		var a: AABB = (d["mesh"] as Mesh).get_aabb()
		tall = maxf(tall, a.size.y)
		half = maxf(half, maxf(a.size.x, a.size.z) * 0.5)
	var gap := maxf(half * 0.95, 7.0)
	var n := figs.size()
	for i in n:
		var x := (float(i) - (n - 1) * 0.5) * 2.0 * gap
		var mi := _board_figure(figs[i], String(s["items"][i].get("faction", "beasts")), x)
		## the figures turn (the camera stays south of them, as the board's does): 0 faces the camera, 180 shows the back
		mi.rotation.y = deg_to_rad(180.0 - float(s.get("yaw", 22.0)))
		var tag := Label.new()
		tag.text = String(s["items"][i].get("label", ""))
		tag.add_theme_font_size_override("font_size", 18)
		tag.add_theme_color_override("font_color", Color(0.10, 0.09, 0.14))
		tag.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.85))
		tag.add_theme_constant_override("outline_size", 5)
		tags.append({"label": tag, "x": x})
	var wide := float(n - 1) * 2.0 * gap + 2.0 * half
	var pitch := deg_to_rad(float(s.get("pitch", 42.0)))
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = FOV
	## frame the row: the tallest figure's projected height fills about 70% of the view and the row fits across with a margin
	var cover := maxf((tall * cos(pitch) + 2.0 * half * sin(pitch)) / 0.7, wide * 1.08 * vp.y / vp.x)
	var d := cover * 0.5 / tan(deg_to_rad(FOV) * 0.5)
	var target := Vector3(0, tall * 0.42, 0)
	var dir := Vector3(0.0, sin(pitch), cos(pitch))
	cam.position = target + dir * d
	cam.look_at(target, Vector3.UP)
	return true


func _shoot_raw(s: Dictionary) -> bool:
	var it: Dictionary = s["items"][0]
	var baked := Models.baked_model(String(it["path"]), it.get("row", {}), String(it.get("pose", "ready")))
	if baked.is_empty():
		push_error("fixtures/sheet: %s: %s did not load" % [s["file"], it["path"]])
		return false
	var mi := MeshInstance3D.new()
	mi.mesh = baked["mesh"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = baked["tex"]
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	holder.add_child(mi)
	var box: AABB = (baked["mesh"] as Mesh).get_aabb()
	print("aabb ", s["file"], " position ", box.position, " size ", box.size)
	var c: Vector3 = box.get_center()
	if s.has("center"):
		c = Vector3(float(s["center"][0]), float(s["center"][1]), float(s["center"][2]))
	var extent := float(s.get("extent", maxf(box.size.y, maxf(box.size.x, box.size.z)) * 0.56))
	var yaw_deg := float(s.get("yaw", 0.0))
	var pitch_deg := float(s.get("pitch", 15.0))
	var ortho := false
	if s.has("view"):
		var v: Array = VIEWS[String(s["view"])]
		yaw_deg = float(v[0])
		pitch_deg = float(v[1])
		ortho = true
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var up := Vector3.UP if pitch_deg < 89.0 else Vector3(0, 0, -1)
	if ortho:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = extent * 2.0
		cam.near = 0.01
		cam.far = 50.0
		cam.position = c + dir * 10.0
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = FOV
		cam.position = c + dir * (extent / tan(deg_to_rad(FOV) * 0.5))
		cam.near = 0.05
		cam.far = 100.0
	cam.look_at(c, up)
	sun.global_basis = cam.global_basis * Basis.from_euler(Vector3(deg_to_rad(-25.0), deg_to_rad(20.0), 0.0))
	if ortho:
		_scale_for(String(s["view"]), c, extent)
	for p in s.get("markers", []):
		_marker_points.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	return true


var _marker_points: Array = [] ## the plan's markers (the model's space), projected once the camera has taken the frame


## Graph paper along the view's two edges, in the model's own coordinates.
func _scale_for(view: String, c: Vector3, extent: float) -> void:
	var ha := 0 ## the world axis along the screen's horizontal: 0 x, 2 z
	var va := 1
	match view:
		"front", "back":
			ha = 0
			va = 1
		"left", "right":
			ha = 2
			va = 1
		"top":
			ha = 0
			va = 2
	var span := extent * 2.0
	var lo_h := c[ha] - span
	var hi_h := c[ha] + span
	var lo_v := c[va] - span
	var hi_v := c[va] + span
	var k0 := int(floor(lo_h * 10.0))
	var k1 := int(ceil(hi_h * 10.0))
	for k in range(k0, k1 + 1):
		var val := k / 10.0
		var p := c
		p[ha] = val
		var sp := cam.unproject_position(p)
		if sp.x < 0.0 or sp.x > vp.x:
			continue
		var major := k % 2 == 0
		scale_ctl.lines.append({"a": Vector2(sp.x, 0), "b": Vector2(sp.x, vp.y), "major": major})
		if major:
			scale_ctl.labels.append({"p": Vector2(sp.x + 2, vp.y - 4), "t": "%.1f" % val})
	k0 = int(floor(lo_v * 10.0))
	k1 = int(ceil(hi_v * 10.0))
	for k in range(k0, k1 + 1):
		var val := k / 10.0
		var p := c
		p[va] = val
		var sp := cam.unproject_position(p)
		if sp.y < 0.0 or sp.y > vp.y:
			continue
		var major := k % 2 == 0
		scale_ctl.lines.append({"a": Vector2(0, sp.y), "b": Vector2(vp.x, sp.y), "major": major})
		if major:
			scale_ctl.labels.append({"p": Vector2(3, sp.y - 2), "t": "%.1f" % val})


func _run() -> void:
	await process_frame ## the window has its final size from here on (--resolution)
	await process_frame
	## the project stretches canvas items to 1600 px; the sheet's screen positions and labels are in the picture's own pixels
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	await process_frame
	_build_scene()
	var report: Array = []
	for shot in plan:
		var s: Dictionary = shot
		for ch in holder.get_children():
			ch.free()
		for t in tags:
			(t["label"] as Label).queue_free()
		tags.clear()
		scale_ctl.lines.clear()
		scale_ctl.labels.clear()
		scale_ctl.markers.clear()
		_marker_points.clear()
		var raw := String(s.get("mode", "board")) == "raw"
		_board_look(not raw)
		var ok := _shoot_raw(s) if raw else _shoot_board(s)
		if not ok:
			report.append({"file": s["file"], "ok": false})
			continue
		title.text = String(s.get("title", ""))
		await process_frame
		for p in _marker_points:
			scale_ctl.markers.append(cam.unproject_position(p))
		for t in tags:
			var l: Label = t["label"]
			l.size = Vector2(vp.x / maxf(1.0, tags.size()), 30)
			var sp := cam.unproject_position(Vector3(float(t["x"]), 0.0, 0.0))
			l.position = Vector2(sp.x - l.size.x * 0.5, vp.y - 40.0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title.get_parent().add_child(l)
		scale_ctl.queue_redraw()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png(out.path_join(String(s["file"])))
		print("shot ", s["file"])
		report.append({"file": s["file"], "ok": true})
	var f := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	quit(0)
