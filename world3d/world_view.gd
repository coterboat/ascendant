## The 3D world map (spike): the ground raised from terrain3d.gd's heights, the sea, the sun, sky
## and haze, woods, cottages, a fortress at every capital and a fort where the rules put one, and the
## camera rig. Two looks share every mesh and swap only shaders and the environment (set_look):
##   "cel"     Look A, Bright Cel: stepped light, ink outlines (inverted hull), keylined borders
##   "painted" Look B, CONCURRENT-like lit painted: soft light, SSAO, glossy sea
## World units are MapLayout design units: x east, z south, y up.
extends Node3D

const Terrain3D := preload("res://world3d/terrain3d.gd")
const Kit := preload("res://world3d/kit.gd")
const SH_GROUND_CEL := preload("res://world3d/shaders/ground_cel.gdshader")
const SH_GROUND_LIT := preload("res://world3d/shaders/ground_lit.gdshader")
const SH_MODEL_CEL := preload("res://world3d/shaders/model_cel.gdshader")
const SH_MODEL_LIT := preload("res://world3d/shaders/model_lit.gdshader")
const SH_OUTLINE := preload("res://world3d/shaders/outline.gdshader")
const SH_WATER := preload("res://world3d/shaders/water.gdshader")
const SH_BANNER := preload("res://world3d/shaders/banner.gdshader")
const LUDO_FORTRESS := "res://assets/models/probe/crownkeep.glb"
const FORTRESS_SIDE := 76.0

var terrain: RefCounted
var look := "cel"
var fortress_style := "ludo" ## "ludo" (the probe's Crownkeep model) or "primitive"
var ground: MeshInstance3D
var water: MeshInstance3D
var sun: DirectionalLight3D
var env: Environment
var cam: Camera3D
var gmat: ShaderMaterial
var wmat: ShaderMaterial
var outline_mat: ShaderMaterial
var owner_img: Image
var owner_tex: ImageTexture
var props: Node3D
var buildings: Node3D
var fortresses := {} ## province id -> {"node": Node3D, "gate_dir": Vector2, "yaw": float, "mat": ShaderMaterial, "court": Rect2 (local), "frame": Transform3D}
var _model_mats: Array = [] ## every model ShaderMaterial, so a look change swaps their shader
var _banner_mats: Array = []
var _ludo_fortress: Dictionary = {} ## {"mesh", "tex", "aabb"} once loaded
var quality := 0
var fog_k := 1.0

## the camera rig: looks at `target` from `pitch` degrees above the horizon, from `yaw` degrees
## round from the south, framing `span` world units top to bottom
var rig := {"target": Vector3(500, 0, 300), "pitch": 58.0, "yaw": 0.0, "fov": 30.0, "span": 560.0}


func setup(p_terrain: RefCounted, p_look: String = "cel") -> void:
	terrain = p_terrain
	look = p_look
	_build_ground()
	_build_water()
	_build_light()
	cam = Camera3D.new()
	cam.current = true
	add_child(cam)
	outline_mat = ShaderMaterial.new()
	outline_mat.shader = SH_OUTLINE
	props = Node3D.new()
	props.name = "Props"
	add_child(props)
	buildings = Node3D.new()
	buildings.name = "Buildings"
	add_child(buildings)
	_grow_props()
	_build_settlements()
	set_look(look)
	apply_rig()


# ------------------------------------------------------------------ the ground and the sea

func _build_ground() -> void:
	gmat = ShaderMaterial.new()
	gmat.shader = SH_GROUND_CEL
	gmat.set_shader_parameter("height_tex", ImageTexture.create_from_image(terrain.height_image))
	gmat.set_shader_parameter("ground_tex", ImageTexture.create_from_image(terrain.ground_image))
	gmat.set_shader_parameter("weights_tex", ImageTexture.create_from_image(terrain.weights_image))
	var dtex := ImageTexture.create_from_image(terrain.data_image)
	gmat.set_shader_parameter("data_n", dtex)
	gmat.set_shader_parameter("data_l", dtex)
	owner_img = Image.create(16, 1, false, Image.FORMAT_RGBA8)
	owner_tex = ImageTexture.create_from_image(owner_img)
	gmat.set_shader_parameter("owner_tex", owner_tex)
	for t in ["plains", "forest", "hills"]:
		var tex: Texture2D = load("res://assets/terrain/%s.webp" % t)
		gmat.set_shader_parameter("tile_" + t, tex)
		if t != "forest":
			gmat.set_shader_parameter("mean_" + t, _mean_colour(tex))
	gmat.set_shader_parameter("grain_tex", _grain())
	gmat.set_shader_parameter("origin", Terrain3D.ORIGIN)
	gmat.set_shader_parameter("extent", Terrain3D.EXTENT)
	gmat.set_shader_parameter("cell", terrain.cell)
	var pm := PlaneMesh.new()
	pm.size = Terrain3D.EXTENT
	pm.subdivide_width = terrain.w - 1
	pm.subdivide_depth = terrain.h - 1
	ground = MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = pm
	ground.material_override = gmat
	var c: Vector2 = Terrain3D.ORIGIN + Terrain3D.EXTENT * 0.5
	ground.position = Vector3(c.x, 0.0, c.y)
	## the ground doesn't shadow itself: the light ramp's bands model the hills (and a vertex-raised
	## plane in its own shadow map acnes into a dark, dull land); it still receives every shadow
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.custom_aabb = AABB(Vector3(-Terrain3D.EXTENT.x * 0.5, terrain.lo - 2.0, -Terrain3D.EXTENT.y * 0.5),
		Vector3(Terrain3D.EXTENT.x, terrain.hi - terrain.lo + 4.0, Terrain3D.EXTENT.y))
	add_child(ground)


func _build_water() -> void:
	wmat = ShaderMaterial.new()
	wmat.shader = SH_WATER
	wmat.set_shader_parameter("height_tex", gmat.get_shader_parameter("height_tex"))
	wmat.set_shader_parameter("data_l", gmat.get_shader_parameter("data_l"))
	wmat.set_shader_parameter("wave_a", _waves(11))
	wmat.set_shader_parameter("wave_b", _waves(23))
	wmat.set_shader_parameter("origin", Terrain3D.ORIGIN)
	wmat.set_shader_parameter("extent", Terrain3D.EXTENT)
	var wm := PlaneMesh.new()
	wm.size = Vector2(12000, 12000)
	water = MeshInstance3D.new()
	water.name = "Sea"
	water.mesh = wm
	water.material_override = wmat
	water.position = Vector3(500, 0.0, 300)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


func _build_light() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.0
	## a warm afternoon sun from the south-west, behind the camera's left shoulder, high
	sun.basis = Basis.looking_at(-Vector3(-0.55, 0.78, 0.42).normalized(), Vector3.UP)
	add_child(sun)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.36, 0.56, 0.84)
	psm.sky_horizon_color = Color(0.86, 0.86, 0.80)
	psm.ground_horizon_color = Color(0.80, 0.80, 0.74)
	psm.ground_bottom_color = Color(0.30, 0.42, 0.50)
	psm.sun_angle_max = 18.0
	sky.sky_material = psm
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.80, 0.84, 0.88)
	env.fog_sky_affect = 0.25
	env.fog_aerial_perspective = 0.35
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.1
	we.environment = env
	add_child(we)


## Switches every material, the sea and the environment between the two looks.
func set_look(p_look: String) -> void:
	look = p_look
	var cel := look == "cel"
	gmat.shader = SH_GROUND_CEL if cel else SH_GROUND_LIT
	gmat.set_shader_parameter("tile_k", 0.32 if cel else 0.6)
	gmat.set_shader_parameter("wash", 0.36 if cel else 0.3)
	wmat.set_shader_parameter("toon", 1.0 if cel else 0.0)
	for m in _model_mats:
		(m as ShaderMaterial).shader = SH_MODEL_CEL if cel else SH_MODEL_LIT
		(m as ShaderMaterial).next_pass = outline_mat if cel else null
	for m in _banner_mats:
		(m as ShaderMaterial).set_shader_parameter("cel", 1.0 if cel else 0.0)
	if cel:
		## flat bright colour: the shaders' light ramps hold the shadow tone, a little cool ambient,
		## and a linear tonemap so the saturated colours stay as painted
		sun.light_color = Color(1.0, 0.96, 0.88)
		sun.light_energy = 1.12
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.80, 0.86, 1.0)
		env.ambient_light_energy = 0.24
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.tonemap_exposure = 1.0
	else:
		sun.light_color = Color(1.0, 0.93, 0.80)
		sun.light_energy = 1.7
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.7
		env.ambient_light_sky_contribution = 1.0
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_white = 5.0
		env.tonemap_exposure = 1.0
	set_quality(quality)


## The quality ladder: 0 everything; 1 SSAO off; 2 shadows reduced (2 splits, shorter, the woods
## cast none); 3 the 3D drawn at 0.75 scale. A slow machine steps down on its own (world_preview.gd).
func set_quality(q: int) -> void:
	quality = clampi(q, 0, 3)
	env.ssao_enabled = quality < 1 and look == "painted"
	env.ssao_radius = 4.0
	env.ssao_intensity = 1.4
	env.ssil_enabled = false
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if quality < 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	for mi in props.get_children():
		if mi is GeometryInstance3D:
			(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0 if quality < 3 else 0.75
	apply_rig()


## Effects on/off for the performance probe: SSAO, glow, fog, shadows, MSAA/FXAA together.
func set_effects(on: bool) -> void:
	env.ssao_enabled = on and look == "painted" and quality < 1
	env.glow_enabled = on
	env.fog_enabled = on
	sun.shadow_enabled = on
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = Viewport.MSAA_2X if on else Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if on else Viewport.SCREEN_SPACE_AA_DISABLED


# ------------------------------------------------------------------ materials

## A model material in the current look. `team` is the player's colour for team parts; `tex` an
## albedo map (a probe GLB's); `key_hue` repaints that hue of the map in the team colour.
func model_mat(team: Color, tex: Texture2D = null, key_hue := -1.0, instanced := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SH_MODEL_CEL if look == "cel" else SH_MODEL_LIT
	m.next_pass = outline_mat if look == "cel" else null
	m.set_shader_parameter("team", team)
	m.set_shader_parameter("instanced_team", instanced)
	if tex != null:
		m.set_shader_parameter("albedo_tex", tex)
		m.set_shader_parameter("use_tex", true)
		m.set_shader_parameter("key_hue", key_hue)
	_model_mats.append(m)
	return m


func banner_mat(team: Color, emblem: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SH_BANNER
	m.set_shader_parameter("colour", team)
	m.set_shader_parameter("emblem", emblem)
	m.set_shader_parameter("cel", 1.0 if look == "cel" else 0.0)
	m.set_shader_parameter("phase", randf() * TAU)
	_banner_mats.append(m)
	return m


## A banner on a staff: a Node3D whose origin is the staff's foot, cloth to +X.
func make_banner(team: Color, emblem: int, height := 9.0, cloth := Vector2(4.2, 2.8)) -> Node3D:
	var root := Node3D.new()
	var staff := MeshInstance3D.new()
	staff.material_override = model_mat(team)
	var b := Kit.Builder.new()
	b.cyl(0.14, 0.17, height, Vector3(0, height * 0.5, 0), Kit.WOOD, 6)
	b.cyl(0.0, 0.32, 0.8, Vector3(0, height + 0.4, 0), Kit.GOLD, 6)
	staff.mesh = b.mesh()
	root.add_child(staff)
	var flag := MeshInstance3D.new()
	var qm := PlaneMesh.new()
	qm.size = cloth
	qm.subdivide_width = 10
	qm.subdivide_depth = 1
	qm.orientation = PlaneMesh.FACE_Z
	flag.mesh = qm
	flag.position = Vector3(cloth.x * 0.5 + 0.12, height - cloth.y * 0.5 - 0.25, 0)
	flag.material_override = banner_mat(team, emblem)
	root.add_child(flag)
	return root


# ------------------------------------------------------------------ owners

## Paints each province's owner colour into the ground's wash (rgb; a = owned).
func set_owners(colours: Dictionary) -> void:
	for i in terrain.ids.size():
		var id: String = terrain.ids[i]
		if colours.has(id):
			var c: Color = colours[id]
			c.a = 1.0
			owner_img.set_pixel(i, 0, c)
		else:
			owner_img.set_pixel(i, 0, Color(0, 0, 0, 0))
	owner_tex.update(owner_img)


func set_fortress_colour(province_id: String, team: Color) -> void:
	if fortresses.has(province_id):
		(fortresses[province_id]["mat"] as ShaderMaterial).set_shader_parameter("team", team)
		for bm in fortresses[province_id].get("banners", []):
			(bm as ShaderMaterial).set_shader_parameter("colour", team)


# ------------------------------------------------------------------ woods, rocks, cottages

func _grow_props() -> void:
	var t = terrain
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var broad: Array = []
	var pine: Array = []
	var rocks: Array = []
	var step := 4.6
	var y := Terrain3D.ORIGIN.y + step * 0.5
	while y < Terrain3D.ORIGIN.y + Terrain3D.EXTENT.y:
		var x := Terrain3D.ORIGIN.x + step * 0.5
		while x < Terrain3D.ORIGIN.x + Terrain3D.EXTENT.x:
			var p := Vector2(x + rng.randf_range(-0.45, 0.45) * step, y + rng.randf_range(-0.45, 0.45) * step)
			x += step
			var c: float = t.coast_at(p)
			if c < 4.0:
				continue
			if _near_stage(p, 1.15) or t.road_at(p) < 7.0:
				continue
			var hv: float = t.height_at(p)
			var n: Vector3 = t.normal_at(p)
			var wd: float = t.woods_at(p)
			var r := rng.randf()
			var steep: float = 1.0 - n.y
			if steep > 0.3:
				if r < 0.05:
					rocks.append(_xf(p, hv, rng, rng.randf_range(1.2, 2.4)))
				continue
			if wd > 0.25 and r < wd * 0.42:
				var tall: bool = hv > 18.0 or rng.randf() < 0.3
				(pine if tall else broad).append(_xf(p, hv, rng, rng.randf_range(1.1, 1.6)))
			elif r < 0.006:
				broad.append(_xf(p, hv, rng, rng.randf_range(0.8, 1.1)))
			elif hv > 16.0 and r < 0.03:
				(pine if rng.randf() < 0.6 else rocks).append(_xf(p, hv, rng, rng.randf_range(0.8, 1.6)))
		y += step
	_multi(Kit.broadleaf(), broad, "Broadleaf")
	_multi(Kit.pine(), pine, "Pines")
	_multi(Kit.rock(), rocks, "Rocks")


func _near_stage(p: Vector2, k: float) -> bool:
	for i in terrain.ids.size():
		if p.distance_to(terrain.centres[i]) < terrain.stage_r[i] * k + 6.0:
			return true
	return false


func _xf(p: Vector2, hv: float, rng: RandomNumberGenerator, s: float) -> Transform3D:
	var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.2), s))
	return Transform3D(b, Vector3(p.x, hv - 0.3, p.y))


func _multi(mesh: Mesh, xfs: Array, nm: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_custom_data(i, Color(1, 1, 1, 1))
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = model_mat(Color.WHITE, null, -1.0, true)
	props.add_child(mi)
	return mi


func prop_count() -> int:
	var n := 0
	for mi in props.get_children():
		if mi is MultiMeshInstance3D:
			n += (mi as MultiMeshInstance3D).multimesh.instance_count
	return n


# ------------------------------------------------------------------ fortresses, forts, villages

func _build_settlements() -> void:
	var t = terrain
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var houses: Array = [[], [], []]
	for i in t.ids.size():
		var id: String = t.ids[i]
		var c: Vector2 = t.centres[i]
		var gate := gate_dir(id)
		if t.is_capital[i]:
			_place_fortress(id, c, gate)
		elif t.has_fort[i]:
			var f := MeshInstance3D.new()
			f.name = "Fort_" + id
			f.mesh = Kit.fort()
			f.material_override = model_mat(Color.WHITE)
			## beside the stage, on the side away from the roads
			var at: Vector2 = c - gate * 30.0
			f.position = t.ground_at(at) - Vector3(0, 0.3, 0)
			f.rotation.y = atan2(gate.x, gate.y)
			buildings.add_child(f)
		## a hamlet of cottages round the stage, off the roads
		var placed := 0
		var tries := 0
		var n_house: int = 3 if t.is_capital[i] else 5
		while placed < n_house and tries < 60:
			tries += 1
			var a: float = rng.randf() * TAU
			var r: float = t.stage_r[i] + rng.randf_range(8.0, 26.0)
			var p: Vector2 = c + Vector2(cos(a), sin(a)) * r
			if t.province_at(p) != id or t.road_at(p) < 9.0 or t.woods_at(p) > 0.2 or t.border_at(p) < 12.0:
				continue
			if t.has_fort[i] and p.distance_to(c - gate * 30.0) < 20.0:
				continue
			if (1.0 - t.normal_at(p).y) > 0.18:
				continue
			var v: int = rng.randi() % 3
			var to_c: Vector2 = (c - p).normalized()
			var b := Basis(Vector3.UP, atan2(to_c.x, to_c.y) + PI).scaled(Vector3.ONE * rng.randf_range(0.85, 1.1))
			houses[v].append(Transform3D(b, t.ground_at(p) - Vector3(0, 0.2, 0)))
			placed += 1
	for v in 3:
		var mi := _multi(Kit.cottage(v), houses[v], "Cottages%d" % v)
		props.remove_child(mi)
		buildings.add_child(mi)


## The way a province's gate faces: toward the mean of its roads.
func gate_dir(id: String) -> Vector2:
	var t = terrain
	var i: int = t.index_of(id)
	var c: Vector2 = t.centres[i]
	var sum := Vector2.ZERO
	for j in t.neighbours[i]:
		var x: Variant = t.crossing(id, t.ids[j])
		var to: Vector2 = (x as Vector2) if x != null else t.centres[j]
		sum += (to - c).normalized()
	return sum.normalized() if sum.length() > 0.01 else Vector2(1, 0)


func _place_fortress(id: String, c: Vector2, gate: Vector2) -> void:
	var t = terrain
	var i: int = t.index_of(id)
	var root := Node3D.new()
	root.name = "Fortress_" + id
	## the fortress frame: gate on local -Z turned to face `gate`
	var yaw: float = atan2(-gate.x, -gate.y)
	root.position = Vector3(c.x, t.stage_h[i] - 0.15, c.y)
	root.rotation.y = yaw
	buildings.add_child(root)
	var mat: ShaderMaterial
	var court: Rect2 = Kit.courtyard_rect(FORTRESS_SIDE)
	var gate_z := Vector2(-FORTRESS_SIDE * 0.5 + 8.0, -FORTRESS_SIDE * 0.5 - 8.0) ## inner, outer (local z)
	var banner_at := Vector2(8.5, 13.0) ## gate towers: x either side, height
	var banners: Array = []
	if fortress_style == "ludo" and _load_ludo_fortress():
		var mi := MeshInstance3D.new()
		mi.mesh = _ludo_fortress["mesh"]
		mat = model_mat(Color.WHITE, _ludo_fortress["tex"], 0.62)
		mi.material_override = mat
		var aabb: AABB = _ludo_fortress["aabb"]
		var s: float = FORTRESS_SIDE / maxf(aabb.size.x, aabb.size.z)
		mi.scale = Vector3.ONE * s
		## the model's own frame (measured off its top view): gate on +X, keep at the back
		mi.rotation.y = _ludo_fortress["yaw"]
		var centre: Vector3 = aabb.get_center()
		mi.position = (Basis(Vector3.UP, mi.rotation.y) * Vector3(-centre.x, -aabb.position.y, -centre.z)) * s
		mi.position.y -= float(_ludo_fortress["sink"]) ## its grass slab's top flush with the stage
		root.add_child(mi)
		court = _ludo_fortress["court"]
		gate_z = _ludo_fortress["gate_z"]
		banner_at = _ludo_fortress["banner_at"]
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = Kit.fortress(FORTRESS_SIDE)
		mat = model_mat(Color.WHITE)
		mi.material_override = mat
		root.add_child(mi)
	## banners on the gate towers, in the owner's colour
	for gx in [-1.0, 1.0]:
		var bn := make_banner(Color.WHITE, 0, 8.0, Vector2(4.0, 2.6))
		bn.position = Vector3(gx * banner_at.x, banner_at.y, gate_z.x - 8.0 if fortress_style == "ludo" else -FORTRESS_SIDE * 0.5 + 1.0)
		root.add_child(bn)
		banners.append(bn.get_child(1).material_override)
	fortresses[id] = {"node": root, "gate_dir": gate, "yaw": yaw, "mat": mat, "court": court,
		"frame": root.transform, "banners": banners, "gate_z": gate_z,
		"floor": 0.25 if fortress_style == "ludo" else 1.45} ## the courtyard's floor over the stage


func _load_ludo_fortress() -> bool:
	if not _ludo_fortress.is_empty():
		return true
	if not ResourceLoader.exists(LUDO_FORTRESS):
		return false
	var scene: PackedScene = load(LUDO_FORTRESS)
	if scene == null:
		return false
	var inst := scene.instantiate()
	var mi := _first_mesh(inst)
	if mi == null:
		inst.free()
		return false
	var mesh: Mesh = mi.mesh
	var tex: Texture2D = null
	var sm := mesh.surface_get_material(0)
	if sm is BaseMaterial3D:
		tex = (sm as BaseMaterial3D).albedo_texture
	var aabb: AABB = mesh.get_aabb()
	inst.free()
	## measured off the model's vertices (world3d/README.md): glTF front, the gate in the +Z wall, the
	## keep at the back; turned PI so the gate is on the fortress frame's -Z. The clear courtyard is
	## between the front wall's inner face (local z -17.8) and the keep (z 0), x within +-22.7; its
	## grass slab is the bottom 2 units.
	_ludo_fortress = {"mesh": _vertex_white(mesh), "tex": tex, "aabb": aabb, "yaw": PI,
		"court": Rect2(Vector2(-21.0, -16.8), Vector2(42.0, 16.0)), "gate_z": Vector2(-13.0, -36.0),
		"sink": 2.0, "banner_at": Vector2(9.0, 20.0)}
	return true


## A copy of an imported mesh with white vertex colours, so the model shaders read its texture.
func _vertex_white(mesh: Mesh) -> ArrayMesh:
	var arr: Array = mesh.surface_get_arrays(0)
	var nv: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var cols := PackedColorArray()
	cols.resize(nv)
	cols.fill(Color(1, 1, 1, 1))
	arr[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


static func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for ch in n.get_children():
		var m := _first_mesh(ch)
		if m != null:
			return m
	return null


## A capital's courtyard muster point and facing, in the world: [centre Vector2, facing Vector2,
## width, depth]. The army faces the gate.
func courtyard(id: String) -> Array:
	var f: Dictionary = fortresses[id]
	var r: Rect2 = f["court"]
	var yaw: float = f["yaw"]
	var root: Node3D = f["node"]
	var local_front := Vector3(r.get_center().x, 0, r.position.y)
	var p: Vector3 = root.transform * local_front
	var facing: Vector2 = f["gate_dir"]
	return [Vector2(p.x, p.z), facing, r.size.x, r.size.y, yaw]


## The gate's inner and outer points (world), for an army filing out.
func gate_points(id: String) -> Array:
	var f: Dictionary = fortresses[id]
	var root: Node3D = f["node"]
	var gz: Vector2 = f["gate_z"]
	var inner: Vector3 = root.transform * Vector3(0, 0, gz.x)
	var outer: Vector3 = root.transform * Vector3(0, 0, gz.y)
	return [Vector2(inner.x, inner.z), Vector2(outer.x, outer.z)]


# ------------------------------------------------------------------ the camera

func rig_eye(r: Dictionary) -> Vector3:
	var d: float = float(r["span"]) / (2.0 * tan(deg_to_rad(r["fov"]) * 0.5))
	var pitch: float = deg_to_rad(r["pitch"])
	var yaw: float = deg_to_rad(r["yaw"])
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	return (r["target"] as Vector3) + (back * cos(pitch) + Vector3.UP * sin(pitch)).normalized() * d


func apply_rig() -> void:
	if cam == null:
		return
	if outline_mat != null and get_viewport() != null:
		outline_mat.set_shader_parameter("screen", get_viewport().get_visible_rect().size)
	var fov: float = rig["fov"]
	var d: float = float(rig["span"]) / (2.0 * tan(deg_to_rad(fov) * 0.5))
	var pitch: float = deg_to_rad(rig["pitch"])
	var yaw: float = deg_to_rad(rig["yaw"])
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	var t: Vector3 = rig["target"]
	var z: Vector3 = (back * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
	var x: Vector3 = Vector3.UP.cross(back).normalized()
	var y: Vector3 = z.cross(x)
	cam.transform = Transform3D(Basis(x, y, z), t + z * d)
	cam.fov = fov
	cam.near = maxf(0.5, d * 0.02)
	cam.far = d * 6.0 + 4000.0
	if sun:
		sun.directional_shadow_max_distance = clampf(d * (2.2 if quality < 2 else 1.4), 200.0, 2600.0)
	if env:
		env.fog_density = fog_k * 0.07 / maxf(d, 1.0)


## A map point on the land, to screen pixels (Vector2(-99999) when behind the camera).
func project(p: Vector2, lift: float = 0.0) -> Vector2:
	var v := Vector3(p.x, maxf(terrain.height_at(p), 0.0) + lift, p.y)
	if cam.is_position_behind(v):
		return Vector2(-99999, -99999)
	return cam.unproject_position(v)


func project3(v: Vector3) -> Vector2:
	if cam.is_position_behind(v):
		return Vector2(-99999, -99999)
	return cam.unproject_position(v)


## A screen point onto the ground: a ray from the eye, refined over the hills.
func unproject(s: Vector2) -> Vector2:
	var o: Vector3 = cam.project_ray_origin(s)
	var d: Vector3 = cam.project_ray_normal(s)
	if absf(d.y) < 0.0001:
		return Vector2(o.x, o.z)
	var hgt := 0.0
	var q := Vector3.ZERO
	for i in 6:
		q = o + d * ((hgt - o.y) / d.y)
		hgt = maxf(terrain.height_at(Vector2(q.x, q.z)), 0.0)
	return Vector2(q.x, q.z)


# ------------------------------------------------------------------ helpers

static func _mean_colour(tex: Texture2D) -> Vector3:
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	var c: Color = img.get_pixel(0, 0)
	return Vector3(c.r, c.g, c.b)


func _grain() -> ImageTexture:
	var imgs := []
	for k in 3:
		var nz := FastNoiseLite.new()
		nz.seed = 77 + k * 31
		nz.frequency = 0.02 + 0.015 * k
		nz.fractal_octaves = 4
		imgs.append(nz.get_seamless_image(256, 256))
	var out := Image.create(256, 256, false, Image.FORMAT_RGB8)
	for y in 256:
		for x in 256:
			out.set_pixel(x, y, Color(imgs[0].get_pixel(x, y).r, imgs[1].get_pixel(x, y).r, imgs[2].get_pixel(x, y).r))
	out.generate_mipmaps()
	return ImageTexture.create_from_image(out)


func _waves(sd: int) -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	var nz := FastNoiseLite.new()
	nz.seed = sd
	nz.frequency = 0.03
	nz.fractal_octaves = 3
	nt.noise = nz
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 6.0
	nt.width = 256
	nt.height = 256
	nt.generate_mipmaps = true
	return nt
