extends SceneTree
## The model the game has now next to its candidate, drawn the way the board draws figures (#162, M4-ART). Dev tool
## only: it never runs in the game or the tests.
##
##   $GODOT --path . --always-on-top --resolution 1600x800 -s res://tools/shots/model_compare.gd -- --plan=/abs/plan.json --out=/abs/dir
##
## The plan (tools/ludo/asc_3d_grok.py `compare` writes it) is a JSON list of shots:
##   {"file": "sunspears_ready.png", "title": "Sunspears · ready", "type": "spearmen", "variant": "crown_celestial_host",
##    "pose": "ready", "faction": "kingdom", "current": {"path": "res://...glb", "row": {the table row as it was}}}
## The right figure is Models.figure_mesh(type, true, pose, faction, variant), what the board draws from the model table
## as it stands now; the left is the same pose built from `current` (a copy of what the game had before), by the same
## Models._glb_figure, so size, yaw and base are the board's. Both wear Look A's model shader (cel, ink outline) under
## its sun, at the board's near camera pitch, a man six world units tall (Kit.FIG). The ground is a flat green with a
## one-man grid (a line every 6 world units).
## Windowed only (headless has no renderer); always pass --always-on-top, an occluded window never draws.

const Models := preload("res://world3d/models.gd")
const Kit := preload("res://world3d/kit.gd")
const SH_MODEL := preload("res://world3d/shaders/model_cel.gdshader")
const SH_OUTLINE := preload("res://world3d/shaders/outline.gdshader")

const PITCH := 42.0 ## the board's near pitch (world_preview.gd PITCH_NEAR)
const FOV := 30.0
const TEAM := {"kingdom": Color(0.2, 0.36, 0.85), "beasts": Color(0.85, 0.27, 0.17)}

var out := ""
var plan: Array = []
var root3: Node3D
var cam: Camera3D
var holder: Node3D
var label_l: Label
var label_r: Label
var label_t: Label
var outline_mat: ShaderMaterial
var vp_size := Vector2(1600, 800)


func _initialize() -> void:
	var plan_path := ""
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"out": out = kv[1]
			"plan": plan_path = kv[1]
	if out.is_empty() or plan_path.is_empty():
		push_error("model_compare: --plan=FILE.json and --out=DIR are required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	if not (parsed is Array):
		push_error("model_compare: %s is not a JSON list" % plan_path)
		quit(2)
		return
	plan = parsed
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.gui_disable_input = true
	_run.call_deferred()


func _build_scene() -> void:
	vp_size = Vector2(root.size)
	root3 = Node3D.new()
	root.add_child(root3)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.74, 0.88)
	## Look A (world_view.gd set_look "cel"): flat bright colour, a little cool ambient, a linear tonemap
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.80, 0.86, 1.0)
	env.ambient_light_energy = 0.24
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	root3.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.basis = Basis.looking_at(-Vector3(-0.55, 0.78, 0.42).normalized(), Vector3.UP)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.12
	root3.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 300)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.47, 0.64, 0.33)
	gm.roughness = 1.0
	ground.material_override = gm
	root3.add_child(ground)
	for k in range(-30, 31):
		_line(Vector3(k * Kit.FIG, 0.02, -90), Vector3(k * Kit.FIG, 0.02, 90))
	for k in range(-15, 16):
		_line(Vector3(-180, 0.02, k * Kit.FIG), Vector3(180, 0.02, k * Kit.FIG))
	holder = Node3D.new()
	root3.add_child(holder)
	cam = Camera3D.new()
	cam.fov = FOV
	cam.current = true
	root3.add_child(cam)
	outline_mat = ShaderMaterial.new()
	outline_mat.shader = SH_OUTLINE
	outline_mat.set_shader_parameter("screen", vp_size)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	label_t = _label(layer, 30, Vector2(0, 8), vp_size.x, HORIZONTAL_ALIGNMENT_CENTER)
	label_l = _label(layer, 24, Vector2(0, vp_size.y - 44), vp_size.x * 0.5, HORIZONTAL_ALIGNMENT_CENTER)
	label_r = _label(layer, 24, Vector2(vp_size.x * 0.5, vp_size.y - 44), vp_size.x * 0.5, HORIZONTAL_ALIGNMENT_CENTER)


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
	root3.add_child(mi)


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


func _figure(d: Dictionary, faction: String, x: float) -> MeshInstance3D:
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
	## the board's figures face -Z (the camera looks from the south): turned to face it, a little to its right
	mi.rotation.y = deg_to_rad(180.0 - 22.0)
	holder.add_child(mi)
	return mi


func _run() -> void:
	await process_frame ## the window has its final size from here on (--resolution)
	await process_frame
	_build_scene()
	var report: Array = []
	for shot in plan:
		var s: Dictionary = shot
		var type_id := String(s["type"])
		var variant := String(s.get("variant", ""))
		var pose := String(s["pose"])
		var faction := String(s.get("faction", ""))
		var cur: Dictionary = s["current"]
		var left := Models._glb_figure(String(cur["path"]), type_id, cur["row"], pose)
		var right := Models.figure_mesh(type_id, true, pose, faction, variant)
		if left.is_empty() or right.is_empty() or String(right.get("source", "")) != "model":
			push_error("model_compare: %s: left %s right %s" % [s["file"], left.is_empty(), right.get("source", "?")])
			report.append({"file": s["file"], "ok": false})
			continue
		for ch in holder.get_children():
			ch.free()
		var la: AABB = (left["mesh"] as Mesh).get_aabb()
		var ra: AABB = (right["mesh"] as Mesh).get_aabb()
		var half := maxf(maxf(la.size.x, la.size.z), maxf(ra.size.x, ra.size.z)) * 0.5
		var gap := maxf(half * 1.15, 7.0)
		_figure(left, faction, -gap)
		_figure(right, faction, gap)
		var tall := maxf(la.size.y, ra.size.y)
		var wide := (gap + half) * 2.0
		var pitch := deg_to_rad(PITCH)
		## frame the pair: the taller figure's projected height (and its footprint's depth) fill about 58% of the
		## view, and the pair fits across with a margin
		var cover := maxf((tall * cos(pitch) + 2.0 * half * sin(pitch)) / 0.58, wide * 1.1 * vp_size.y / vp_size.x)
		var d := cover * 0.5 / tan(deg_to_rad(FOV) * 0.5)
		var target := Vector3(0, tall * 0.40, 0)
		var dir := Vector3(0, sin(pitch), cos(pitch))
		cam.position = target + dir * d
		cam.look_at(target, Vector3.UP)
		label_t.text = String(s["title"])
		label_l.text = "in the game now (%.2f men)" % float(s.get("current_men", 0.0))
		label_r.text = "candidate (%.2f men)" % float(s.get("candidate_men", 0.0))
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
