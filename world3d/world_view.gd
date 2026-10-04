## The 3D world map (spike): the ground raised from terrain3d.gd's heights, the sea, the sun, sky
## and haze, woods, cottages, a fortress at every capital and a fort where the rules put one, and the
## camera rig. Two looks share every mesh and swap only shaders and the environment (set_look):
##   "cel"     Look A, Bright Cel: stepped light, ink outlines (inverted hull), keylined borders
##   "painted" Look B, CONCURRENT-like lit painted: soft light, SSAO, glossy sea
## World units are MapLayout design units: x east, z south, y up.
extends Node3D

const Terrain3D := preload("res://world3d/terrain3d.gd")
const Kit := preload("res://world3d/kit.gd")
const Models := preload("res://world3d/models.gd")
const SH_GROUND_CEL := preload("res://world3d/shaders/ground_cel.gdshader")
const SH_GROUND_LIT := preload("res://world3d/shaders/ground_lit.gdshader")
const SH_MODEL_CEL := preload("res://world3d/shaders/model_cel.gdshader")
const SH_MODEL_LIT := preload("res://world3d/shaders/model_lit.gdshader")
const SH_OUTLINE := preload("res://world3d/shaders/outline.gdshader")
const SH_WATER := preload("res://world3d/shaders/water.gdshader")
const SH_BANNER := preload("res://world3d/shaders/banner.gdshader")
const FORTRESS_SIDE := 76.0
const SWEEP_TIME := 1.2 ## a capture's colour sweep, seconds at 1x
const SWEEP_REACH := 170.0 ## how far the sweep's front runs from the arriving column
const BUILDING_GRADE := 1.0 ## pale stone pulled to a warm grey on every building (a row's "grade" overrides)

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
var mark_img: Image ## 16 x 1: r a King's Roads destination, g a legal move target, b a focus flash
var mark_tex: ImageTexture
var capital_of := {} ## province id -> the faction whose capital it is in the map data (picks the fortress kit)
var _banner_n := 0
var props: Node3D
var buildings: Node3D
var fortresses := {} ## province id -> {"node": Node3D, "gate_dir": Vector2, "yaw": float, "mat": ShaderMaterial, "court": Rect2 (local), "frame": Transform3D}
var _model_mats: Array = [] ## every model ShaderMaterial, so a look change swaps their shader
var _prop_mats: Array = [] ## the woods', rocks' and cottages' materials: their ink outline only close in
var _own_outline := {} ## material -> its own outline material (a fortress's, which the close-up cuts away)
var _outlines: Array = [] ## every outline material (the camera keeps their screen size)
var prop_outlines := true
var _banner_mats: Array = []
var quality := 0
var fog_k := 1.0
var view_size := Vector2(1600, 900) ## the size of the viewport the camera draws into (Board3D keeps it)
var cam_xform := Transform3D() ## the camera's transform, as apply_rig() set it
var sweeps: Array = [] ## M3a.2: captures sweeping in: [{"i": province index, "from": Vector2, "t": seconds, "old": Color}]
var forts := {} ## M3a.2: province id -> {"node", "mat"}: the fort models (their roofs take the owner's colour)
var prop_models := false ## M3a.2: the woods and rocks drawn with the model table's GLBs (close in), else primitives
var _prop_prims: Array = [] ## the primitive woods' and rocks' MultiMeshes (one each, the whole map)
var _prop_chunks: Array = [] ## the model woods' and rocks' MultiMeshes, in chunks the camera culls
const PROP_CHUNK := 200.0 ## world units a side of a model-props chunk

## the camera rig: looks at `target` from `pitch` degrees above the horizon, from `yaw` degrees
## round from the south, framing `span` world units top to bottom
var rig := {"target": Vector3(500, 0, 300), "pitch": 58.0, "yaw": 0.0, "fov": 30.0, "span": 560.0}


func setup(p_terrain: RefCounted, p_look: String = "cel") -> void:
	terrain = p_terrain
	look = p_look
	for f in FactionData.FACTIONS:
		capital_of[String(f.capital)] = String(f.id)
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
	mark_img = Image.create(16, 1, false, Image.FORMAT_RGBA8)
	mark_tex = ImageTexture.create_from_image(mark_img)
	gmat.set_shader_parameter("mark_tex", mark_tex)
	for t in ["plains", "forest", "hills"]:
		var tex: Texture2D = load("res://assets/terrain/%s.webp" % t)
		gmat.set_shader_parameter("tile_" + t, tex)
		if t != "forest":
			gmat.set_shader_parameter("mean_" + t, _mean_colour(tex))
	gmat.set_shader_parameter("grain_tex", ImageTexture.create_from_image(plan_of(terrain)["grain"]))
	gmat.set_shader_parameter("origin", Terrain3D.ORIGIN)
	gmat.set_shader_parameter("extent", Terrain3D.EXTENT)
	gmat.set_shader_parameter("cell", terrain.cell)
	_push_sweeps()
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
		(m as ShaderMaterial).next_pass = _own_outline.get(m, outline_mat) if cel and (prop_outlines or not _prop_mats.has(m)) else null
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
		if mi is GeometryInstance3D and not mi.has_meta("chunk"):
			(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0 if quality < 3 else 0.75
	apply_rig()


## The woods', rocks' and cottages' ink outlines (Look A): the board keeps them only close in, where
## they read; far out they are the dearest pass for the least (the spike's measurement, README).
func set_prop_outlines(on: bool) -> void:
	if on == prop_outlines:
		return
	prop_outlines = on
	for m in _prop_mats:
		(m as ShaderMaterial).next_pass = outline_mat if on and look == "cel" else null


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
func model_mat(team: Color, tex: Texture2D = null, key_hue := -1.0, instanced := false, tint := 1.0, stone := Color.WHITE, grade := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SH_MODEL_CEL if look == "cel" else SH_MODEL_LIT
	m.next_pass = outline_mat if look == "cel" else null
	m.set_shader_parameter("team", team)
	m.set_shader_parameter("instanced_team", instanced)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("stone_tint", stone)
	m.set_shader_parameter("stone_grade", grade)
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
	_banner_n += 1
	m.set_shader_parameter("phase", _h01(_banner_n, 7) * TAU) ## cosmetic: a hash, never the game's dice
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


## Repaints one province's owner wash (a capture during the turn's playback).
func paint_owner(province_id: String, colour: Color, owned: bool = true) -> void:
	var i: int = terrain.index_of(province_id)
	if i < 0:
		return
	var c := colour
	c.a = 1.0 if owned else 0.0
	owner_img.set_pixel(i, 0, c if owned else Color(0, 0, 0, 0))
	owner_tex.update(owner_img)


## The owner wash as {province id: Color (alpha 0: nobody)}, for comparing two boards.
func owners_painted() -> Dictionary:
	var out := {}
	for i in terrain.ids.size():
		var c: Color = owner_img.get_pixel(i, 0)
		out[terrain.ids[i]] = c if c.a > 0.5 else Color(0, 0, 0, 0)
	return out


## The ground's highlights: the selected and hovered province (drawn in the ground shader), and per
## province marks: road targets (a dashed gilt band), legal move targets (a gilt glow at the edge),
## a focus flash (0..1), and `grown`: provinces the rules have turned to forest since the land was
## baked (the Wild Spreads, M4-2), painted with the forest's canopy so the land shows the rule.
func set_highlights(select_id: String, hover_id: String) -> void:
	gmat.set_shader_parameter("select_id", terrain.index_of(select_id) if not select_id.is_empty() else -1)
	gmat.set_shader_parameter("hover_id", terrain.index_of(hover_id) if not hover_id.is_empty() else -1)


func set_marks(road: Dictionary, move: Dictionary, flash: Dictionary, grown: Dictionary = {}) -> void:
	for i in terrain.ids.size():
		var id: String = terrain.ids[i]
		mark_img.set_pixel(i, 0, Color(1.0 if road.has(id) else 0.0, 1.0 if move.has(id) else 0.0,
			clampf(float(flash.get(id, 0.0)), 0.0, 1.0), 1.0 if grown.has(id) else 0.0))
	mark_tex.update(mark_img)


func set_fortress_colour(province_id: String, team: Color) -> void:
	if fortresses.has(province_id):
		(fortresses[province_id]["mat"] as ShaderMaterial).set_shader_parameter("team", team)
		for bm in fortresses[province_id].get("banners", []):
			(bm as ShaderMaterial).set_shader_parameter("colour", team)


# ------------------------------------------------------------------ capture sweeps (M3a.2)

## A capture's sweep: the province's new owner colour (already painted, set_owners/paint_owner) runs out
## from `from` (the arriving column) over SWEEP_TIME, over its `old` colour (alpha 0: nobody's), with a
## gilt front. At most 4 at once (the oldest gives way).
func start_sweep(province_id: String, from: Vector2, old: Color) -> void:
	var i: int = terrain.index_of(province_id)
	if i < 0:
		return
	for sw in sweeps:
		if int(sw["i"]) == i:
			sweeps.erase(sw)
			break
	if sweeps.size() >= 4:
		sweeps.pop_front()
	sweeps.append({"i": i, "from": from, "t": 0.0, "old": old})
	_push_sweeps()


## Advances the sweeps by `delta` seconds (the board steps them at the playback's speed).
func step_sweeps(delta: float) -> void:
	if sweeps.is_empty():
		return
	for sw in sweeps.duplicate():
		sw["t"] = float(sw["t"]) + delta
		if float(sw["t"]) >= SWEEP_TIME:
			sweeps.erase(sw)
	_push_sweeps()


func clear_sweeps() -> void:
	sweeps.clear()
	_push_sweeps()


## The old owner colour of the province index's sweep (for tests: what a province shows outside a front).
func old_owner_colour(province_id: String) -> Color:
	return owner_img.get_pixel(terrain.index_of(province_id), 0)


func _push_sweeps() -> void:
	var a := PackedVector4Array()
	var o := PackedVector4Array()
	for k in 4:
		if k < sweeps.size():
			var sw: Dictionary = sweeps[k]
			var r: float = SWEEP_REACH * smoothstep(0.0, 1.0, clampf(float(sw["t"]) / SWEEP_TIME, 0.0, 1.0))
			var from: Vector2 = sw["from"]
			var c: Color = sw["old"]
			a.append(Vector4(from.x, from.y, r, float(sw["i"])))
			o.append(Vector4(c.r, c.g, c.b, c.a))
		else:
			a.append(Vector4(0, 0, 0, -1))
			o.append(Vector4(0, 0, 0, 0))
	gmat.set_shader_parameter("sweep_a", a)
	gmat.set_shader_parameter("sweep_old", o)


# ------------------------------------------------------------------ woods, rocks, cottages

func _grow_props() -> void:
	var pl: Dictionary = plan_of(terrain)
	_prop_prims = [
		_multi(Models.building_primitive("tree_broadleaf"), pl["broad"], "Broadleaf"),
		_multi(Models.building_primitive("tree_pine"), pl["pine"], "Pines"),
		_multi(Models.building_primitive("rock"), pl["rocks"], "Rocks")]
	_build_prop_models(pl)


## M3a.2: the model table's tree and rock GLBs over the same placement, each normalised to its
## primitive's size (a one-for-one swap, so a wood never grows tall enough to hide a column), in chunks
## of PROP_CHUNK so the camera culls what it doesn't see. Shown close in (set_prop_models); the
## primitives stay the far LOD and the low quality rungs' fallback.
func _build_prop_models(pl: Dictionary) -> void:
	for spec in [["tree_broadleaf", "broad", "y"], ["tree_pine", "pine", "y"], ["rock", "rocks", "xz"]]:
		var glb: Dictionary = Models.building_model(spec[0])
		if glb.is_empty():
			continue
		var row: Dictionary = Models.building_row(spec[0])
		var prim: AABB = Models.building_primitive(spec[0]).get_aabb()
		var a: AABB = glb["aabb"]
		var s: float = (prim.size.y / maxf(a.size.y, 0.001)) if spec[2] == "y" else (maxf(prim.size.x, prim.size.z) / maxf(maxf(a.size.x, a.size.z), 0.001))
		var yaw := deg_to_rad(float(row.get("yaw", 180.0)))
		var c: Vector3 = a.get_center()
		var base := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3.ZERO) * Transform3D(Basis(), Vector3(-c.x, -a.position.y, -c.z))
		var chunks := {}
		for xf in pl[spec[1]]:
			var o: Vector3 = (xf as Transform3D).origin
			var key := Vector2i(int(floor(o.x / PROP_CHUNK)), int(floor(o.z / PROP_CHUNK)))
			if not chunks.has(key):
				chunks[key] = []
			chunks[key].append((xf as Transform3D) * base)
		var mat := model_mat(Color.WHITE, glb["tex"], -1.0, true)
		_prop_mats.append(mat)
		for key in chunks.keys():
			var list: Array = chunks[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = glb["mesh"]
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i])
				mm.set_instance_custom_data(i, Color(1, 1, 1, 1))
			var mi := MultiMeshInstance3D.new()
			mi.name = "%s_%d_%d" % [spec[0], key.x, key.y]
			mi.multimesh = mm
			mi.material_override = mat
			mi.visible = false
			mi.set_meta("chunk", true)
			## close-in woods cast no shadow: the four shadow splits over every tree model were the
			## board's dearest pass (measured); the canopy tile under them and the cel ramp keep the depth
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			props.add_child(mi)
			_prop_chunks.append(mi)


## Close in, the woods and rocks are the model table's GLBs (culled by chunk); far out, and on the
## quality ladder's lower rungs, the cheap primitives.
func set_prop_models(on: bool) -> void:
	on = on and not _prop_chunks.is_empty()
	if on == prop_models:
		return
	prop_models = on
	for mi in _prop_prims:
		(mi as Node3D).visible = not on
	for mi in _prop_chunks:
		(mi as Node3D).visible = on


## Villages, landmarks and forts cast shadows only from the default zoom in (the board calls this with
## the figures'): far out they are a few pixels across and their shadow splits cost the most.
func set_building_shadows(on: bool) -> void:
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for n in buildings.get_children():
		if n is MultiMeshInstance3D and String(n.name).begins_with("Village"):
			(n as GeometryInstance3D).cast_shadow = mode
	for id in forts.keys():
		for ch in (forts[id]["node"] as Node).get_children():
			if ch is GeometryInstance3D:
				(ch as GeometryInstance3D).cast_shadow = mode


## The yard's light in the fortress close-up: a little more ambient, so the walls' shade never darkens
## a block (design 8.3, "a fill light keeps the yard bright").
func set_yard_light(on: bool) -> void:
	if look == "cel":
		env.ambient_light_energy = 0.24 + (0.2 if on else 0.0)
	else:
		env.ambient_light_energy = 0.7 + (0.25 if on else 0.0)


## The land's pure placement (trees, rocks, cottages) and the ground's grain, computed once per land:
## on the bake's worker thread when the board prebakes (Board3D.prebake), or here on first use.
static func plan_of(t) -> Dictionary:
	if not t.plan.has("broad"):
		t.plan["villages"] = plan_villages(t)
		t.plan.merge(plan_props(t, t.plan["villages"]), true)
		t.plan["houses"] = plan_houses(t, not (t.plan["villages"] as Array).is_empty())
		t.plan["grain"] = make_grain()
	return t.plan


static func plan_props(t, villages: Array = []) -> Dictionary:
	var rng := _Hash.new(4242) ## cosmetic: a hash of the cell and the map seed, never the game's dice
	var keep_clear: Array = [] ## [centre, radius]: villages, landmarks and forts stand in clearings
	for v in villages:
		keep_clear.append([v["pos"], float(v["r"]) + 3.0])
	for i in t.ids.size():
		if t.has_fort[i] and not t.is_capital[i]:
			var fs: Array = fort_spot(t, i)
			keep_clear.append([fs[0], float(fs[1]) + 3.0])
	var broad: Array = []
	var pine: Array = []
	var rocks: Array = []
	var step := 4.6
	var y := Terrain3D.ORIGIN.y + step * 0.5
	while y < Terrain3D.ORIGIN.y + Terrain3D.EXTENT.y:
		var x := Terrain3D.ORIGIN.x + step * 0.5
		while x < Terrain3D.ORIGIN.x + Terrain3D.EXTENT.x:
			var p := Vector2(x + rng.range01(-0.45, 0.45) * step, y + rng.range01(-0.45, 0.45) * step)
			x += step
			var c: float = t.coast_at(p)
			if c < 4.0:
				continue
			if _near_stage(t, p, 1.15) or t.road_at(p) < 7.0:
				continue
			var clear := false
			for kc in keep_clear:
				if p.distance_to(kc[0]) < float(kc[1]):
					clear = true
					break
			if clear:
				continue
			var hv: float = t.height_at(p)
			var n: Vector3 = t.normal_at(p)
			var wd: float = t.woods_at(p)
			var r := rng.next01()
			var steep: float = 1.0 - n.y
			if steep > 0.3:
				if r < 0.05:
					rocks.append(_xf(p, hv, rng, rng.range01(1.2, 2.4)))
				continue
			if wd > 0.25 and r < wd * 0.42:
				var tall: bool = hv > 18.0 or rng.next01() < 0.3
				(pine if tall else broad).append(_xf(p, hv, rng, rng.range01(1.1, 1.6)))
			elif r < 0.006:
				broad.append(_xf(p, hv, rng, rng.range01(0.8, 1.1)))
			elif hv > 16.0 and r < 0.03:
				(pine if rng.next01() < 0.6 else rocks).append(_xf(p, hv, rng, rng.range01(0.8, 1.6)))
		y += step
	return {"broad": broad, "pine": pine, "rocks": rocks}


static func _near_stage(t, p: Vector2, k: float) -> bool:
	for i in t.ids.size():
		if p.distance_to(t.centres[i]) < t.stage_r[i] * k + 6.0:
			return true
	return false


static func _xf(p: Vector2, hv: float, rng: _Hash, s: float) -> Transform3D:
	var b := Basis(Vector3.UP, rng.next01() * TAU).scaled(Vector3(s, s * rng.range01(0.85, 1.2), s))
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
	_prop_mats.append(mi.material_override)
	props.add_child(mi)
	return mi


func prop_count() -> int:
	var n := 0
	for mi in props.get_children():
		if mi is MultiMeshInstance3D and not mi.has_meta("chunk"):
			n += (mi as MultiMeshInstance3D).multimesh.instance_count
	return n


# ------------------------------------------------------------------ fortresses, forts, villages

func _build_settlements() -> void:
	var t = terrain
	for i in t.ids.size():
		var id: String = t.ids[i]
		var c: Vector2 = t.centres[i]
		var gate := gate_dir(id)
		if t.is_capital[i]:
			_place_fortress(id, c, gate)
		elif t.has_fort[i]:
			_place_fort(id, i, gate)
	_place_villages()
	var houses: Array = plan_of(t)["houses"]
	for v in 3:
		var mi := _multi(Kit.cottage(v), houses[v], "Cottages%d" % v)
		## the cottages' pale walls are buildings' stone too: graded, so Look A's sun doesn't blow them out
		(mi.material_override as ShaderMaterial).set_shader_parameter("stone_grade", BUILDING_GRADE)
		props.remove_child(mi)
		buildings.add_child(mi)


## A fort province's fort (M3a.2: the model table's fort of the faction whose capital is nearest, its
## gate turned to the stage; else the primitive), beside the stage on the side away from the roads. Its
## roofs take the owner's colour (set_fort_colour).
func _place_fort(id: String, i: int, gate: Vector2) -> void:
	var t = terrain
	var variant := nearest_capital_faction(t, i)
	var row: Dictionary = Models.building_row("fort", variant)
	var glb: Dictionary = Models.building_model("fort", variant)
	var fs: Array = fort_spot(t, i)
	var at: Vector2 = fs[0]
	var root := Node3D.new()
	root.name = "Fort_" + id
	root.position = t.ground_at(at) - Vector3(0, 0.3, 0)
	root.rotation.y = atan2(-gate.x, -gate.y) + PI ## its gate (local -Z) faces the stage
	buildings.add_child(root)
	var mi := MeshInstance3D.new()
	var mat: ShaderMaterial
	if not glb.is_empty():
		var aabb: AABB = glb["aabb"]
		var side: float = float(row.get("side", 26.0))
		var s: float = side / maxf(aabb.size.x, aabb.size.z)
		mi.mesh = glb["mesh"]
		mi.scale = Vector3.ONE * s
		mi.rotation.y = deg_to_rad(float(row.get("yaw", 180.0)))
		var centre: Vector3 = aabb.get_center()
		mi.position = (Basis(Vector3.UP, mi.rotation.y) * Vector3(-centre.x, -aabb.position.y, -centre.z)) * s
		mi.position.y -= float(row.get("sink", 0.0))
		mat = model_mat(Color.WHITE, glb["tex"], float(row.get("key_hue", -1.0)), false, float(row.get("tint", 0.9)), Color.WHITE, float(row.get("grade", BUILDING_GRADE)))
	else:
		mi.mesh = Models.building_primitive("fort")
		mi.rotation.y = PI
		mat = model_mat(Color.WHITE, null, -1.0, false, 0.9, Color.WHITE, BUILDING_GRADE)
	mi.material_override = mat
	root.add_child(mi)
	forts[id] = {"node": root, "mat": mat}


## Repaints a fort's keyed roofs in its owner's colour.
func set_fort_colour(province_id: String, team: Color) -> void:
	if forts.has(province_id):
		(forts[province_id]["mat"] as ShaderMaterial).set_shader_parameter("team", team)


## The faction whose capital is nearest province index `i` (a fort's builder; captured, it keeps its look).
static func nearest_capital_faction(t, i: int) -> String:
	var best := ""
	var best_d := 1.0e18
	for f in FactionData.FACTIONS:
		var ci: int = t.index_of(String(f.capital))
		if ci < 0:
			continue
		var d: float = (t.centres[ci] as Vector2).distance_squared_to(t.centres[i])
		if d < best_d:
			best_d = d
			best = String(f.id)
	return best


## Where province index `i`'s fort stands: [centre, radius], beside the stage away from the roads,
## pulled in until it stands on its own land.
static func fort_spot(t, i: int) -> Array:
	var id: String = t.ids[i]
	var c: Vector2 = t.centres[i]
	var gate := gate_dir_of(t, id)
	var row: Dictionary = Models.building_row("fort", nearest_capital_faction(t, i))
	var r: float = float(row.get("side", 26.0)) * 0.5 if not String(row.get("model", "")).is_empty() else 13.0
	var d: float = t.stage_r[i] + r - 2.0
	while d > t.stage_r[i] * 0.6 and t.province_at(c - gate * d) != id:
		d -= 3.0
	return [c - gate * d, r]


## Every province's village (M3a.2: the model table's village of its terrain, a variant by a hash of its
## id) and, for some, a landmark (a mill on the plains, a watchtower in the hills, standing stones in the
## woods), off the roads and the stage. Pure: [{"province", "kind", "pos", "yaw", "r"}].
static func plan_villages(t) -> Array:
	var out: Array = []
	var rng := _Hash.new(271)
	var landmark := {"plains": "mill", "hills": "watchtower", "forest": "standing_stones"}
	for i in t.ids.size():
		if t.is_capital[i]:
			continue
		var id: String = t.ids[i]
		var kinds: Array = []
		var vk := "village_" + String(t.terrain_of[i])
		if not Models.building_variants(vk).is_empty():
			kinds.append(vk)
		var lk := String(landmark.get(String(t.terrain_of[i]), ""))
		if not lk.is_empty() and absi(hash("landmark:" + id)) % 3 != 0 and not Models.building_variants(lk).is_empty():
			kinds.append(lk)
		var c: Vector2 = t.centres[i]
		var taken: Array = []
		if t.has_fort[i]:
			taken.append(fort_spot(t, i))
		for kind in kinds:
			var r: float = float(Models.building_row(kind).get("side", 24.0)) * 0.5
			var tries := 0
			while tries < 80:
				tries += 1
				var a: float = rng.next01() * TAU
				var p: Vector2 = c + Vector2(cos(a), sin(a)) * (t.stage_r[i] + r + rng.range01(2.0, 16.0))
				if t.province_at(p) != id or t.road_at(p) < r * 0.75 or t.border_at(p) < r + 3.0 or t.coast_at(p) < r:
					continue
				if (1.0 - t.normal_at(p).y) > 0.16:
					continue
				var clash := false
				for tk in taken:
					if p.distance_to(tk[0]) < float(tk[1]) + r + 2.0:
						clash = true
				if clash:
					continue
				var to_c: Vector2 = (c - p).normalized()
				out.append({"province": id, "kind": kind, "pos": p, "yaw": atan2(to_c.x, to_c.y) + PI, "r": r})
				taken.append([p, r])
				break
	return out


## The planned villages and landmarks, each its model (a MultiMesh per GLB): buildings, graded like stone.
func _place_villages() -> void:
	var t = terrain
	var by_path := {}
	for v in plan_of(t)["villages"]:
		var paths: Array = Models.building_variants(v["kind"])
		if paths.is_empty():
			continue
		var path: String = paths[Models.variant_for(v["province"], paths.size())]
		if not by_path.has(path):
			by_path[path] = {"kind": v["kind"], "list": []}
		by_path[path]["list"].append(v)
	for path in by_path.keys():
		var glb: Dictionary = Models.model_at(path)
		if glb.is_empty():
			continue
		var row: Dictionary = Models.building_row(by_path[path]["kind"])
		var aabb: AABB = glb["aabb"]
		var s: float = float(row.get("side", 24.0)) / maxf(aabb.size.x, aabb.size.z)
		var c: Vector3 = aabb.get_center()
		var yaw0 := deg_to_rad(float(row.get("yaw", 180.0)))
		var list: Array = by_path[path]["list"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = glb["mesh"]
		mm.instance_count = list.size()
		for k in list.size():
			var v: Dictionary = list[k]
			var b := Basis(Vector3.UP, float(v["yaw"]) + yaw0).scaled(Vector3.ONE * s)
			var at: Vector3 = t.ground_at(v["pos"]) - Vector3(0, 0.25, 0)
			mm.set_instance_transform(k, Transform3D(b, at) * Transform3D(Basis(), Vector3(-c.x, -aabb.position.y, -c.z)))
			mm.set_instance_custom_data(k, Color(1, 1, 1, 1))
		var mi := MultiMeshInstance3D.new()
		mi.name = "Village_" + path.get_file().get_basename()
		mi.multimesh = mm
		mi.material_override = model_mat(Color.WHITE, glb["tex"], -1.0, true, float(row.get("tint", 0.92)), Color.WHITE, float(row.get("grade", BUILDING_GRADE)))
		## like the woods, a village's ink outline only close in (the overdraw costs the most far out)
		_prop_mats.append(mi.material_override)
		if not prop_outlines:
			(mi.material_override as ShaderMaterial).next_pass = null
		buildings.add_child(mi)


## A hamlet of cottages round every stage, off the roads (pure): three lists of transforms, one per
## cottage variant. With village models (`villages`), only the capitals keep their cottages.
static func plan_houses(t, villages: bool = false) -> Array:
	var rng := _Hash.new(99)
	var houses: Array = [[], [], []]
	for i in t.ids.size():
		var id: String = t.ids[i]
		var c: Vector2 = t.centres[i]
		var gate := gate_dir_of(t, id)
		var placed := 0
		var tries := 0
		var n_house: int = 3 if t.is_capital[i] else (0 if villages else 5)
		while placed < n_house and tries < 60:
			tries += 1
			var a: float = rng.next01() * TAU
			var r: float = t.stage_r[i] + rng.range01(8.0, 26.0)
			var p: Vector2 = c + Vector2(cos(a), sin(a)) * r
			if t.province_at(p) != id or t.road_at(p) < 9.0 or t.woods_at(p) > 0.2 or t.border_at(p) < 12.0:
				continue
			if t.has_fort[i] and p.distance_to(fort_spot(t, i)[0]) < float(fort_spot(t, i)[1]) + 6.0:
				continue
			if (1.0 - t.normal_at(p).y) > 0.18:
				continue
			var v: int = rng.next_int() % 3
			var to_c: Vector2 = (c - p).normalized()
			var b := Basis(Vector3.UP, atan2(to_c.x, to_c.y) + PI).scaled(Vector3.ONE * rng.range01(0.85, 1.1))
			houses[v].append(Transform3D(b, t.ground_at(p) - Vector3(0, 0.2, 0)))
			placed += 1
	return houses


## The way a province's gate faces: toward the mean of its roads.
func gate_dir(id: String) -> Vector2:
	return gate_dir_of(terrain, id)


static func gate_dir_of(t, id: String) -> Vector2:
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
	## the kit comes from the model table: the faction whose capital this is picks its variant (a
	## captured fortress keeps its look, design/3D_DIRECTION.md 5.3)
	var variant: String = capital_of.get(id, "")
	var row: Dictionary = Models.building_row("fortress", variant)
	var side: float = float(row.get("side", FORTRESS_SIDE))
	var tint: float = float(row.get("tint", 1.0))
	var stone := Color(String(row.get("stone", "#FFFFFF")))
	var mat: ShaderMaterial
	var court: Rect2 = Kit.courtyard_rect(side)
	var gate_z := Vector2(-side * 0.5 + 8.0, -side * 0.5 - 8.0) ## inner, outer (local z)
	var banner_at := Vector2(8.5, 13.0) ## gate towers: x either side, height
	var floor_y := 1.45
	var banners: Array = []
	var glb: Dictionary = Models.building_model("fortress", variant) if fortress_style == "ludo" else {}
	if not glb.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = glb["mesh"]
		mat = model_mat(Color.WHITE, glb["tex"], float(row.get("key_hue", -1.0)), false, tint, stone, float(row.get("grade", BUILDING_GRADE)))
		_give_own_outline(mat)
		mi.material_override = mat
		var aabb: AABB = glb["aabb"]
		var s: float = side / maxf(aabb.size.x, aabb.size.z)
		mi.scale = Vector3.ONE * s
		## the model's own frame (measured off its top view): gate on +Z in glTF, turned by the row's yaw
		mi.rotation.y = deg_to_rad(float(row.get("yaw", 180.0)))
		var centre: Vector3 = aabb.get_center()
		mi.position = (Basis(Vector3.UP, mi.rotation.y) * Vector3(-centre.x, -aabb.position.y, -centre.z)) * s
		mi.position.y -= float(row.get("sink", 0.0)) ## its grass slab's top flush with the stage
		root.add_child(mi)
		var cr: Array = row.get("court", [])
		if cr.size() == 4:
			court = Rect2(Vector2(cr[0], cr[1]), Vector2(cr[2], cr[3]))
		var gz: Array = row.get("gate_z", [])
		if gz.size() == 2:
			gate_z = Vector2(gz[0], gz[1])
		var ba: Array = row.get("banner_at", [])
		if ba.size() == 2:
			banner_at = Vector2(ba[0], ba[1])
		floor_y = float(row.get("floor", 0.25))
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = Models.building_primitive("fortress", variant)
		## the primitive's pale stone is drawn a little darker, so Look A's light doesn't blow it out
		mat = model_mat(Color.WHITE, null, -1.0, false, 0.86 * tint, stone, float(row.get("grade", BUILDING_GRADE)))
		_give_own_outline(mat)
		mi.material_override = mat
		root.add_child(mi)
	var pal_mat: ShaderMaterial = null
	if bool(row.get("palisade", false)):
		## the Clans' kit variant: a ring of sharpened stakes round the walls, open at the gate
		var pal := MeshInstance3D.new()
		pal.mesh = Kit.palisade(side * 0.5 + 7.0)
		pal_mat = model_mat(Color.WHITE)
		_give_own_outline(pal_mat)
		pal.material_override = pal_mat
		root.add_child(pal)
	## banners on the gate towers, in the owner's colour
	for gx in [-1.0, 1.0]:
		var bn := make_banner(Color.WHITE, 0, 8.0, Vector2(4.0, 2.6))
		bn.position = Vector3(gx * banner_at.x, banner_at.y, gate_z.x - 8.0 if not glb.is_empty() else -side * 0.5 + 1.0)
		root.add_child(bn)
		banners.append(bn.get_child(1).material_override)
	fortresses[id] = {"node": root, "gate_dir": gate, "yaw": yaw, "mat": mat, "court": court,
		"frame": root.transform, "banners": banners, "gate_z": gate_z, "pal_mat": pal_mat,
		"floor": floor_y} ## the courtyard's floor over the stage


func _give_own_outline(m: ShaderMaterial) -> void:
	var om := ShaderMaterial.new()
	om.shader = SH_OUTLINE
	om.set_shader_parameter("screen", view_size)
	_own_outline[m] = om
	_outlines.append(om)
	if m.next_pass != null:
		m.next_pass = om


## The fortress close-up's see-through walls (M3a.2): on, the gate side of the fortress at `province_id`
## (its walls, gatehouse and towers in front of the yard, and a Clans palisade) is drawn as a sparse
## dither from `above` units over the yard's floor up, casting no shadow, so the camera sees every block
## of the muster through it; off, it stands solid again. Its gate banners hide meanwhile.
func set_cutaway(province_id: String, on: bool, above: float = 2.6) -> void:
	if not fortresses.has(province_id):
		return
	var f: Dictionary = fortresses[province_id]
	var plane := Vector4.ZERO
	var y := 0.0
	if on:
		var root: Node3D = f["node"]
		var court: Rect2 = f["court"]
		var front: Vector3 = root.transform * Vector3(court.get_center().x, 0.0, court.position.y + 5.0)
		var n: Vector2 = f["gate_dir"]
		plane = Vector4(n.x, 0.0, n.y, n.x * front.x + n.y * front.z)
		y = root.position.y + float(f["floor"]) + above
	for m in [f["mat"], f.get("pal_mat")]:
		if m == null:
			continue
		(m as ShaderMaterial).set_shader_parameter("cut_plane", plane)
		(m as ShaderMaterial).set_shader_parameter("cut_y", y)
		var om: ShaderMaterial = _own_outline.get(m)
		if om != null:
			om.set_shader_parameter("cut_plane", plane)
			om.set_shader_parameter("cut_y", y)
	var root2: Node3D = f["node"]
	for ch in root2.get_children():
		if ch is Node3D and not (ch is MeshInstance3D):
			(ch as Node3D).visible = not on
	f["cut"] = on


static func _first_mesh(n: Node) -> MeshInstance3D:
	return Models._first_mesh(n)


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
	if outline_mat != null:
		outline_mat.set_shader_parameter("screen", view_size)
		for om in _outlines:
			(om as ShaderMaterial).set_shader_parameter("screen", view_size)
	var fov: float = rig["fov"]
	var d: float = float(rig["span"]) / (2.0 * tan(deg_to_rad(fov) * 0.5))
	var pitch: float = deg_to_rad(rig["pitch"])
	var yaw: float = deg_to_rad(rig["yaw"])
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	var t: Vector3 = rig["target"]
	var z: Vector3 = (back * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
	var x: Vector3 = Vector3.UP.cross(back).normalized()
	var y: Vector3 = z.cross(x)
	cam_xform = Transform3D(Basis(x, y, z), t + z * d)
	cam.transform = cam_xform
	cam.fov = fov
	cam.near = maxf(0.5, d * 0.02)
	cam.far = d * 6.0 + 4000.0
	if sun:
		sun.directional_shadow_max_distance = clampf(d * (2.2 if quality < 2 else 1.4), 200.0, 2600.0)
	if env:
		env.fog_density = fog_k * 0.07 / maxf(d, 1.0)


## The camera's projection, computed here rather than asked of the Camera3D node, so picking works the
## same out of the scene tree (headless tests) as in it. The Camera3D keeps its default vertical FOV
## (keep height), and `view_size` is the size of the viewport it draws into (the board keeps them equal).
func project3(v: Vector3) -> Vector2:
	var pv: Vector3 = cam_xform.affine_inverse() * v
	if pv.z > -0.001:
		return Vector2(-99999, -99999)
	var th: float = tan(deg_to_rad(float(rig["fov"])) * 0.5)
	var aspect: float = view_size.x / maxf(view_size.y, 1.0)
	var nx: float = pv.x / (-pv.z * th * aspect)
	var ny: float = pv.y / (-pv.z * th)
	return Vector2((nx * 0.5 + 0.5) * view_size.x, (0.5 - ny * 0.5) * view_size.y)


## A map point on the land, to screen pixels (Vector2(-99999) when behind the camera).
func project(p: Vector2, lift: float = 0.0) -> Vector2:
	return project3(Vector3(p.x, maxf(terrain.height_at(p), 0.0) + lift, p.y))


## The ray from the eye through a screen point: [origin, direction].
func screen_ray(s: Vector2) -> Array:
	var th: float = tan(deg_to_rad(float(rig["fov"])) * 0.5)
	var aspect: float = view_size.x / maxf(view_size.y, 1.0)
	var nx: float = (s.x / maxf(view_size.x, 1.0)) * 2.0 - 1.0
	var ny: float = 1.0 - (s.y / maxf(view_size.y, 1.0)) * 2.0
	var dir: Vector3 = cam_xform.basis * Vector3(nx * th * aspect, ny * th, -1.0)
	return [cam_xform.origin, dir.normalized()]


## A screen point onto the ground: a ray from the eye, refined over the hills.
func unproject(s: Vector2) -> Vector2:
	var ray: Array = screen_ray(s)
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	if absf(d.y) < 0.0001:
		return Vector2(o.x, o.z)
	var hgt := 0.0
	var q := Vector3.ZERO
	for i in 6:
		q = o + d * ((hgt - o.y) / d.y)
		hgt = maxf(terrain.height_at(Vector2(q.x, q.z)), 0.0)
	return Vector2(q.x, q.z)


# ------------------------------------------------------------------ helpers

## Cosmetic variety (tree placement, village spots, a banner's ripple) from a fixed seed and a counter,
## hashed: the world never touches the game's dice (design/3D_DIRECTION.md 2).
class _Hash:
	var _s: int

	func _init(seed_value: int) -> void:
		_s = seed_value * 2654435761 + 1013904223

	func next01() -> float:
		_s = _s * 6364136223846793005 + 1442695040888963407
		return float((_s >> 33) & 0x7FFFFFFF) / 2147483648.0

	func range01(a: float, b: float) -> float:
		return a + (b - a) * next01()

	func next_int() -> int:
		_s = _s * 6364136223846793005 + 1442695040888963407
		return (_s >> 33) & 0x7FFFFFFF


static func _h01(n: int, salt: int) -> float:
	var h := _Hash.new(n * 7919 + salt)
	return h.next01()


static func _mean_colour(tex: Texture2D) -> Vector3:
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	var c: Color = img.get_pixel(0, 0)
	return Vector3(c.r, c.g, c.b)


static func make_grain() -> Image:
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
	return out


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
