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
const SH_GHOST := preload("res://world3d/shaders/ghost.gdshader")
const SH_SMOKE := preload("res://world3d/shaders/smoke.gdshader")
const SH_DUST := preload("res://world3d/shaders/dust.gdshader")
const SiegeBoard := preload("res://world3d/siege_board.gd")
const Vision := preload("res://world3d/vision.gd")
const FORTRESS_SIDE := 76.0
const SWEEP_TIME := 1.2 ## a capture's colour sweep, seconds at 1x
const SWEEP_REACH := 170.0 ## how far the sweep's front runs from the arriving column
const BUILDING_GRADE := 1.0 ## pale stone pulled to a warm grey on every building (a row's "grade" overrides)
const FOG_STILL_RUNG := 3 ## M5-3: from this quality rung the mist over glimpsed land stands still (UX-2)

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
## The province textures (UX-7, design/UX_WAR_TABLE.md §4.0): one column per province index, Vision.WIDTH wide, the one width every
## texture is built with and the ground shader divides by (prov_u reads it from the texture). A map with more provinces than that is
## rejected in setup, before any texture is built (width_error).
var owner_img: Image ## WIDTH x 1 RGBA8: rgb the owner's colour, a owned
var owner_tex: ImageTexture
var mark_img: Image ## WIDTH x 1 RGBA8: r a King's Roads destination, g a legal move target, b a focus flash, a a forest the rules grew
var mark_tex: ImageTexture
var vision_img: Image ## M5-3, WIDTH x 1 R8 beside the owner wash: 0 never seen, 85 remembered, 170 glimpsed, 255 in clear sight (Vision)
var vision_tex: ImageTexture
var lens_img: Image ## UX-7, WIDTH x 2 RGBA8: the active map lens (MapLens.texels): row 0 its tint and strength, row 1 its mark and flag
var lens_tex: ImageTexture
var lens_id := "" ## UX-7: the lens the ground and the props draw ("" none: lens_mode 0, nothing drawn)
var rejected := "" ## why setup built nothing ("" when it built the world)
var prop_fog_on := false ## MVP-3 (#177): the woods, rocks and cottages take the ground's veil (set_vision)
var fog_on := false ## M5-3: the ground shader veils what the vision texture says (a fog game only; otherwise the ground is untouched)
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
## M3c S-4 (#102): forts and sieges drawn from the state (show_forts; design/M3C_SIEGES.md §10.1)
var fort_rows := {} ## province id -> the SiegeBoard.board_table row drawn now (a game with sieges)
var _raised := {} ## M5-9: province id -> true for a fort Bastion raised in a game without sieges (set_raised_forts)
var fort_draw := {} ## province id -> {"root" (a fort's own frame node, null at a capital), "dress", "mats", "h", "hs", "frame", "colour"}
var _sieges_drawn := false ## the map's forts were taken over by show_forts (a game with sieges)
var _ghost_scaffolds := {} ## province id -> Node3D: the viewer's own queued Fortify orders (set_fortify_ghosts)
var _fx: Array = [] ## one-shot dust bursts: [{"node", "mat", "t", "life"}]
var _kits := {} ## map_kits()
var _geom := {} ## "pid|kind|kit" -> a fort's yard (fort_geom)
var _village_at := {} ## province id -> [{"mm", "k", "xf", "pos", "r"}]: its village and landmark instances
var _dmg_cut := {} ## province id -> [Vector4 plane, float y]: a capital's damage look (the close-up restores it)

## the camera rig: looks at `target` from `pitch` degrees above the horizon, from `yaw` degrees
## round from the south, framing `span` world units top to bottom
var rig := {"target": Vector3(500, 0, 300), "pitch": 58.0, "yaw": 0.0, "fov": 30.0, "span": 560.0}


func setup(p_terrain: RefCounted, p_look: String = "cel") -> void:
	terrain = p_terrain
	look = p_look
	rejected = width_error(terrain.ids.size())
	if not rejected.is_empty():
		printerr(rejected)  ## not built: every province texture is one column per province, Vision.WIDTH wide
		return
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
	_wire_prop_fog()
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
	owner_img = Image.create(Vision.WIDTH, 1, false, Image.FORMAT_RGBA8)
	owner_tex = ImageTexture.create_from_image(owner_img)
	gmat.set_shader_parameter("owner_tex", owner_tex)
	mark_img = Image.create(Vision.WIDTH, 1, false, Image.FORMAT_RGBA8)
	mark_tex = ImageTexture.create_from_image(mark_img)
	gmat.set_shader_parameter("mark_tex", mark_tex)
	vision_img = Image.create_from_data(Vision.WIDTH, 1, false, Image.FORMAT_R8, Vision.texels({}, []))
	vision_tex = ImageTexture.create_from_image(vision_img)
	gmat.set_shader_parameter("vision_tex", vision_tex)
	lens_img = Image.create_from_data(Vision.WIDTH, 2, false, Image.FORMAT_RGBA8, MapLens.no_texels())
	lens_tex = ImageTexture.create_from_image(lens_img)
	gmat.set_shader_parameter("lens_tex", lens_tex)
	gmat.set_shader_parameter("lens_mode", 0)
	gmat.set_shader_parameter("fog_on", 0.0)
	gmat.set_shader_parameter("fog_drift", 1.0 if quality < FOG_STILL_RUNG else 0.0)
	var looks: Dictionary = Vision.look_arrays() ## UX-2: the four looks of the ground, one per sight level
	for k in looks:
		gmat.set_shader_parameter(k, looks[k])
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
	if gmat != null:
		gmat.set_shader_parameter("fog_drift", 1.0 if quality < FOG_STILL_RUNG else 0.0) ## M5-3: the mist stands still from rung 3
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


## M5-3: the viewer's sight into the ground's vision texture (Vision.texels: 0 never seen, 85 remembered, 170 glimpsed,
## 255 in clear sight), and the veil on. One 16-byte texture update; the shader looks it up with the province index it
## already reads, one fetch and one mix. `levels` is Vision.levels' {province id: level}.
func set_vision(levels: Dictionary) -> void:
	vision_img = Image.create_from_data(Vision.WIDTH, 1, false, Image.FORMAT_R8, Vision.texels(levels, terrain.ids))
	vision_tex.update(vision_img)
	fog_on = true
	gmat.set_shader_parameter("fog_on", 1.0)
	_set_prop_fog(1.0)


## M5-3: no fog (a game without it, the observer, the 2D map's standing in): the ground is untouched.
func clear_vision() -> void:
	if not fog_on and vision_img != null and vision_img.get_data() == Vision.texels({}, []):
		return
	vision_img = Image.create_from_data(Vision.WIDTH, 1, false, Image.FORMAT_R8, Vision.texels({}, []))
	vision_tex.update(vision_img)
	fog_on = false
	gmat.set_shader_parameter("fog_on", 0.0)
	_set_prop_fog(0.0)


## MVP-3 (#177): the woods, rocks and cottages read the ground's sight (model_common.gdshaderinc, fog_prop): its province
## texture and its vision texture, from the start; the veil itself goes on and off with the ground's (set_vision).
func _wire_prop_fog() -> void:
	var looks: Dictionary = Vision.look_arrays()
	for m in _prop_mats:
		var pm := m as ShaderMaterial
		pm.set_shader_parameter("prop_data_n", gmat.get_shader_parameter("data_n"))
		pm.set_shader_parameter("prop_vision", vision_tex)
		pm.set_shader_parameter("prop_origin", Terrain3D.ORIGIN)
		pm.set_shader_parameter("prop_extent", Terrain3D.EXTENT)
		pm.set_shader_parameter("prop_look_tone", looks["look_tone"]) ## UX-2: the props wear the ground's looks
		pm.set_shader_parameter("prop_look_lift", looks["look_lift"])
		pm.set_shader_parameter("prop_lens", lens_tex) ## UX-7: and its lens
	_set_prop_fog(1.0 if fog_on else 0.0)


## The woods' veil on (1) or off (0), with the ground's.
func _set_prop_fog(on: float) -> void:
	prop_fog_on = on > 0.5
	for m in _prop_mats:
		(m as ShaderMaterial).set_shader_parameter("prop_fog", on)


## The vision texture's bytes as the ground reads them (tests, and comparing two boards).
func vision_bytes() -> PackedByteArray:
	return vision_img.get_data()


## UX-7 (design/UX_WAR_TABLE.md §4.0): the map lens `id` ("" none) over the ground and the props, from MapLens.build's entries
## ({province id: entry}): one texture update (MapLens.texels, Vision.WIDTH x 2) and the lens's mode and mood. The ground shader
## composes it in §4.0's order, so the veil still reads under it; the woods, rocks and cottages are muted with the ground.
func set_lens(id: String, entries: Dictionary) -> void:
	if gmat == null:
		return
	lens_id = id if MapLens.mode_of(id) > 0 else ""
	lens_img = Image.create_from_data(Vision.WIDTH, 2, false, Image.FORMAT_RGBA8, MapLens.texels(entries if not lens_id.is_empty() else {}, terrain.ids))
	lens_tex.update(lens_img)
	var mode := MapLens.mode_of(lens_id)
	var md := MapLens.mood(lens_id)
	var tone: Color = md.tone
	gmat.set_shader_parameter("lens_mode", mode)
	gmat.set_shader_parameter("lens_mood", md.mood)
	gmat.set_shader_parameter("lens_tone", Vector3(tone.r, tone.g, tone.b))
	for m in _prop_mats:
		var pm := m as ShaderMaterial
		pm.set_shader_parameter("prop_lens_mode", mode)
		pm.set_shader_parameter("prop_lens_mood", md.mood)
		pm.set_shader_parameter("prop_lens_tone", Vector3(tone.r, tone.g, tone.b))


func clear_lens() -> void:
	set_lens("", {})


## The shader's lens_mode now (0 none).
func lens_mode() -> int:
	return int(gmat.get_shader_parameter("lens_mode")) if gmat != null else 0


## The four province textures' bytes as the ground reads them (tests: their exact bytes and order).
func owner_bytes() -> PackedByteArray:
	return owner_img.get_data()


func mark_bytes() -> PackedByteArray:
	return mark_img.get_data()


func lens_bytes() -> PackedByteArray:
	return lens_img.get_data()


## Why a map of `count` provinces can't be drawn ("" when it can): every province texture has one column per province, Vision.WIDTH
## wide, so a map with more is turned away before any texture is built.
static func width_error(count: int) -> String:
	if count <= Vision.WIDTH:
		return ""
	return "The 3D board draws at most %d provinces (one column of each province texture per province, Vision.WIDTH), and this map has %d." % [Vision.WIDTH, count]


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


## M5-9 (#120): the forts Bastion raised in a game without sieges (the baked map has none there; with sieges every fort is a
## show_forts row): exactly `want` (province ids) stand, placed as the map's forts are, their villages cleared from under them.
func set_raised_forts(want: Array) -> void:
	for pid in _raised.keys():
		if not want.has(pid):
			if forts.has(pid) and is_instance_valid(forts[pid]["node"]):
				(forts[pid]["node"] as Node).queue_free()
			forts.erase(pid)
			_raised.erase(pid)
			_show_villages(pid, true)
	for pid in want:
		var i: int = terrain.index_of(pid)
		if _raised.has(pid) or i < 0 or terrain.has_fort[i] or forts.has(pid) or _sieges_drawn:
			continue
		_place_fort(pid, i, gate_dir(pid))
		_show_villages(pid, false)
		_raised[pid] = true


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
			var xf := Transform3D(b, at) * Transform3D(Basis(), Vector3(-c.x, -aabb.position.y, -c.z))
			mm.set_instance_transform(k, xf)
			mm.set_instance_custom_data(k, Color(1, 1, 1, 1))
			## M3c S-4: kept per province, so a fort built over it can clear it away (_clear_villages)
			if not _village_at.has(v["province"]):
				_village_at[v["province"]] = []
			_village_at[v["province"]].append({"mm": mm, "k": k, "xf": xf, "pos": v["pos"], "r": v["r"]})
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
	var model_h := 24.0
	for ch in root.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
			model_h = maxf((ch as MeshInstance3D).mesh.get_aabb().size.y * (ch as MeshInstance3D).scale.y, 6.0)
			break
	fortresses[id] = {"node": root, "gate_dir": gate, "yaw": yaw, "mat": mat, "court": court,
		"frame": root.transform, "banners": banners, "gate_z": gate_z, "pal_mat": pal_mat,
		"floor": floor_y, "side": side, "h": model_h} ## the courtyard's floor over the stage


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
	if not on and _dmg_cut.has(province_id):
		## M3c S-4: off, a damaged capital's walls go back to their damage look
		plane = _dmg_cut[province_id][0]
		y = _dmg_cut[province_id][1]
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


# ------------------------------------------------------------------ M3c S-4: forts and sieges from the state

## The kit each province's fort wears when nobody built it (SiegeBoard.board_table's `map_kits`): a capital its own
## faction's, any other the nearest capital's (a fort on the map; captured, it keeps its look).
func map_kits() -> Dictionary:
	if _kits.is_empty():
		for i in terrain.ids.size():
			var id: String = terrain.ids[i]
			_kits[id] = String(capital_of.get(id, "")) if terrain.is_capital[i] else nearest_capital_faction(terrain, i)
	return _kits


## What the board should draw of `s`'s forts (SiegeBoard.board_table; {} without sieges).
func table_of(s: GameState) -> Dictionary:
	return SiegeBoard.board_table(SiegeBoard.model_of(s), map_kits())


## What the board draws now: the board_table rows show_forts drew (tests compare it with table_of(the state)).
func fort_table() -> Dictionary:
	return fort_rows.duplicate(true)


## How many chevron banners stand round the walls at `province_id` (0 with no siege).
func chevrons_at(province_id: String) -> int:
	var d: Dictionary = fort_draw.get(province_id, {})
	var mi: Variant = d.get("chev")
	return (mi as MultiMeshInstance3D).multimesh.instance_count if mi != null and is_instance_valid(mi) else 0


## Draws the forts of a game with sieges (§10.1) from a board_table: each fort in the kit of its level (palisade,
## keep, citadel) and of its builder (else the map's), its damage look (the look's model when the table has one,
## else the code fallback: the corner or the gate side of the walls cut away as a dither, rubble at the foot, smoke
## and fire when battered), construction scaffolding round a site with the next level rising by a cut plane, and
## the besieger's chevron banners round a besieged fort's walls. `colours`: faction id -> its player colour (the
## chevrons and a rising level's roofs). An empty table (a game without sieges) puts the map's forts back.
func show_forts(table: Dictionary, colours: Dictionary = {}) -> void:
	if table.is_empty():
		if _sieges_drawn:
			_restore_map_forts()
		return
	var ids := {}
	for k in fort_rows.keys():
		ids[k] = true
	for k in table.keys():
		ids[k] = true
	if not _sieges_drawn:
		_sieges_drawn = true
		for k in forts.keys():
			ids[k] = true
	var keys: Array = ids.keys()
	keys.sort()
	for pid in keys:
		var row: Dictionary = table.get(pid, {})
		var col: Color = colours.get(String(row.get("besieger", "")), colours.get(String((row.get("scaffold", {}) as Dictionary).get("faction", "")), Color.WHITE))
		var old: Dictionary = fort_rows.get(pid, {})
		var d: Dictionary = fort_draw.get(pid, {})
		if old == row and not d.is_empty() and (d.get("colour", Color.WHITE) as Color).is_equal_approx(col):
			continue
		_draw_fort(pid, row, old, col)
		if row.is_empty():
			fort_rows.erase(pid)
		else:
			fort_rows[pid] = row.duplicate(true)


## A game without sieges again (a test reusing the board): the map's forts as the board placed them at the start.
func _restore_map_forts() -> void:
	for pid in fort_draw.keys():
		_clear_dress(pid)
		var d: Dictionary = fort_draw[pid]
		if d.get("root") != null and is_instance_valid(d["root"]):
			(d["root"] as Node).queue_free()
		forts.erase(pid)
		_show_villages(pid, true)
	fort_draw.clear()
	fort_rows.clear()
	for pid in _dmg_cut.keys():
		_cut_mats(_capital_mats(pid), Vector4.ZERO, 0.0)
	_dmg_cut.clear()
	for pid in fortresses.keys():
		_capital_piece(pid, "fortress")
	_sieges_drawn = false
	for i in terrain.ids.size():
		if terrain.has_fort[i] and not terrain.is_capital[i] and not forts.has(terrain.ids[i]):
			_place_fort(terrain.ids[i], i, gate_dir(terrain.ids[i]))


func _draw_fort(pid: String, row: Dictionary, old: Dictionary, col: Color) -> void:
	var capital := fortresses.has(pid)
	var d: Dictionary = fort_draw.get(pid, {})
	var look := String(row.get("look", ""))
	## the damage look's own model when the table has one (S-9's), drawn instead of the intact kit
	var piece := look_piece(String(row.get("kind", "")), String(row.get("kit", "")), int(row.get("level", 0)), look)
	if capital:
		_capital_piece(pid, piece)
	else:
		var kind := String(row.get("kind", ""))
		var kit := String(row.get("kit", ""))
		var same: bool = not d.is_empty() and kind == String(old.get("kind", "")) and kit == String(old.get("kit", "")) and d.get("root") != null \
			and piece == String(d.get("piece", ""))
		if not same:
			if d.get("root") != null and is_instance_valid(d["root"]):
				(d["root"] as Node).queue_free()
			elif forts.has(pid) and is_instance_valid(forts[pid]["node"]):
				(forts[pid]["node"] as Node).queue_free() ## the map's fort, placed at the start
			var team: Color = (forts[pid]["mat"] as ShaderMaterial).get_shader_parameter("team") if forts.has(pid) else NEUTRAL_ROOF
			forts.erase(pid)
			d = {"root": null}
			if not kind.is_empty():
				var built := _build_fort(pid, kind, kit, piece)
				d = built
				(built["mat"] as ShaderMaterial).set_shader_parameter("team", team)
				forts[pid] = {"node": built["root"], "mat": built["mat"]}
		_show_villages(pid, kind.is_empty() and (row.get("scaffold", {}) as Dictionary).is_empty())
	_clear_dress(pid)
	d["colour"] = col
	fort_draw[pid] = d
	var dress := Node3D.new()
	dress.name = "FortDress_" + pid
	buildings.add_child(dress)
	d["dress"] = dress
	var g: Dictionary = _fort_frame(pid, capital, d)
	if g.is_empty():
		return
	var frame: Transform3D = g["frame"]
	var hs: float = g["hs"]
	var h: float = g["h"]
	## the damage look: its model when the table has one, else the code fallback (the cut through the walls)
	var cut: Array = _damage_cut(frame, hs, h, look if piece == String(row.get("kind", "")) else "")
	var mats: Array = _capital_mats(pid) if capital else d.get("mats", [])
	if capital:
		if look.is_empty() or look == "intact":
			_dmg_cut.erase(pid)
		else:
			_dmg_cut[pid] = cut
		if not bool(fortresses[pid].get("cut", false)):
			_cut_mats(mats, cut[0], cut[1])
	else:
		_cut_mats(mats, cut[0], cut[1])
	if look in ["damaged", "battered"]:
		_rubble(dress, frame, [Vector2(0.7 * hs, -0.95 * hs), Vector2(0.92 * hs, -0.72 * hs)], hs / 16.0)
		if look == "battered":
			_smoke(dress, frame * Vector3(0.82 * hs, h * 0.45, -0.82 * hs), 6, 1.2)
			_fire(dress, frame * Vector3(0.7 * hs, h * 0.35, -0.75 * hs), hs / 18.0)
	elif look == "breached":
		_rubble(dress, frame, [Vector2(-0.45 * hs, -0.85 * hs), Vector2(0.1 * hs, -0.95 * hs), Vector2(0.5 * hs, -0.82 * hs)], hs / 13.0)
		_smoke(dress, frame * Vector3(0.0, h * 0.15, -hs), 3, 0.7)
	## construction: scaffolding round the site, the next level rising by a cut plane
	var sc: Dictionary = row.get("scaffold", {})
	if not sc.is_empty():
		_rising(dress, pid, String(sc.get("to_kind", "")), String(sc.get("kit", "")), float(sc.get("rise", 0.0)), col)
	## a siege: the besieger's chevron banners round the walls
	if not String(row.get("besieger", "")).is_empty():
		d["chev"] = _chevrons(dress, frame, hs + 5.0, col)


const NEUTRAL_ROOF := Color(0.6, 0.6, 0.6)


func _clear_dress(pid: String) -> void:
	var d: Dictionary = fort_draw.get(pid, {})
	if d.get("dress") != null and is_instance_valid(d["dress"]):
		(d["dress"] as Node).queue_free()
	d.erase("dress")
	d.erase("chev")


## A fort province's frame (gate on local -Z, turned to the stage), its half side and height: {"frame", "hs", "h"}.
func _fort_frame(pid: String, capital: bool, d: Dictionary) -> Dictionary:
	if capital:
		var f: Dictionary = fortresses[pid]
		return {"frame": (f["node"] as Node3D).transform, "hs": float(f.get("side", FORTRESS_SIDE)) * 0.5, "h": float(f.get("h", 24.0))}
	if d.get("root") != null:
		return {"frame": (d["root"] as Node3D).transform, "hs": float(d["hs"]), "h": float(d["h"])}
	## a site with no fort yet: the spot it will stand on
	var i: int = terrain.index_of(pid)
	if i < 0:
		return {}
	var gate := gate_dir(pid)
	var at: Vector2 = fort_spot(terrain, i)[0]
	return {"frame": Transform3D(Basis(Vector3.UP, atan2(-gate.x, -gate.y)), terrain.ground_at(at) - Vector3(0, 0.3, 0)), "hs": 12.0, "h": 8.0}


## Builds a fort of `kind` in `kit` at `pid` (its model, else its primitive), in the fort frame: gate on local -Z,
## facing the stage. {"root", "mat", "mats", "hs", "h"}.
func _build_fort(pid: String, kind: String, kit: String, piece_kind: String = "") -> Dictionary:
	var g := fort_geom(pid, kind, kit)
	var root := Node3D.new()
	root.name = "Fort_" + pid
	root.transform = g["frame"]
	buildings.add_child(root)
	var pk: String = piece_kind if not piece_kind.is_empty() else kind
	var piece := _fort_piece(pk, kit)
	var mi: MeshInstance3D = piece["mi"]
	root.add_child(mi)
	return {"root": root, "mat": piece["mat"], "mats": [piece["mat"]], "hs": float(g["radius"]), "h": float(piece["h"]), "piece": pk}


## The model-table kind a fort is drawn with: the damage look's kind ("fort_damaged", "fortress_breached"; a battered
## fort wears the damaged one) when that row has a model on disk, else the intact kit's `kind` (the code fallback
## then cuts the walls).
static func look_piece(kind: String, kit: String, level: int, look: String) -> String:
	var lk := SiegeBoard.look_kind(level, look)
	if not lk.is_empty() and not Models.building_model(lk, kit).is_empty():
		return lk
	return kind


## Which model-table kind each fort is drawn with now (tests: a damage look's model replaces the code fallback).
func fort_piece(pid: String) -> String:
	if fortresses.has(pid):
		return String(fortresses[pid].get("piece", "fortress"))
	return String((fort_draw.get(pid, {}) as Dictionary).get("piece", ""))


## A capital's fortress in a damage look's model (S-9's), or back in its own: the model swaps in place, normalised to
## the fortress's side as the kit is, so its yard, gate and banners stay where they were.
func _capital_piece(pid: String, piece: String) -> void:
	var f: Dictionary = fortresses[pid]
	if String(f.get("piece", "fortress")) == piece:
		return
	var mi: MeshInstance3D = null
	for ch in (f["node"] as Node3D).get_children():
		if ch is MeshInstance3D:
			mi = ch
			break
	if mi == null:
		return
	if not f.has("own_mesh"):
		f["own_mesh"] = {"mesh": mi.mesh, "scale": mi.scale, "rotation": mi.rotation, "position": mi.position,
			"tex": (f["mat"] as ShaderMaterial).get_shader_parameter("albedo_tex")}
	var kit := String(capital_of.get(pid, ""))
	var glb: Dictionary = Models.building_model(piece, kit) if piece != "fortress" else {}
	if glb.is_empty():
		var own: Dictionary = f["own_mesh"]
		mi.mesh = own["mesh"]
		mi.scale = own["scale"]
		mi.rotation = own["rotation"]
		mi.position = own["position"]
		(f["mat"] as ShaderMaterial).set_shader_parameter("albedo_tex", own["tex"])
		f["piece"] = "fortress"
		return
	var row: Dictionary = Models.building_row(piece, kit)
	var aabb: AABB = glb["aabb"]
	var s: float = float(f.get("side", FORTRESS_SIDE)) / maxf(aabb.size.x, aabb.size.z)
	mi.mesh = glb["mesh"]
	mi.scale = Vector3.ONE * s
	mi.rotation = Vector3(0, deg_to_rad(float(row.get("yaw", 180.0))), 0)
	var centre: Vector3 = aabb.get_center()
	mi.position = (Basis(Vector3.UP, mi.rotation.y) * Vector3(-centre.x, -aabb.position.y, -centre.z)) * s
	(f["mat"] as ShaderMaterial).set_shader_parameter("albedo_tex", glb["tex"])
	(f["mat"] as ShaderMaterial).set_shader_parameter("use_tex", true)
	f["piece"] = piece


## A fort's model (or primitive) as a MeshInstance3D in the fort frame, with its own material and outline (the damage
## look and the rising cut go on them): {"mi", "mat", "h"}.
func _fort_piece(kind: String, kit: String) -> Dictionary:
	var row: Dictionary = Models.building_row(kind, kit)
	var glb: Dictionary = Models.building_model(kind, kit)
	var mi := MeshInstance3D.new()
	var mat: ShaderMaterial
	var h := 10.0
	var k := Kit.fort_scale(kind) ## UX-2: the level's size on the board (the geometry, fort_geom, takes the same)
	if not glb.is_empty():
		var aabb: AABB = glb["aabb"]
		var side: float = float(row.get("side", 26.0)) * k
		var s: float = side / maxf(aabb.size.x, aabb.size.z)
		mi.mesh = glb["mesh"]
		mi.scale = Vector3.ONE * s
		## the row's yaw turns the model's gate onto the frame's -Z, toward the stage and its roads (the map's own
		## forts, placed at the start of a game without sieges, keep their M3a turn)
		mi.rotation.y = deg_to_rad(float(row.get("yaw", 180.0)))
		var centre: Vector3 = aabb.get_center()
		mi.position = (Basis(Vector3.UP, mi.rotation.y) * Vector3(-centre.x, -aabb.position.y, -centre.z)) * s
		mi.position.y -= float(row.get("sink", 0.0))
		mat = model_mat(Color.WHITE, glb["tex"], float(row.get("key_hue", -1.0)), false, float(row.get("tint", 0.9)), Color.WHITE, float(row.get("grade", BUILDING_GRADE)))
		h = aabb.size.y * s
	else:
		mi.mesh = Models.building_primitive(kind, kit)
		mi.scale = Vector3.ONE * k
		mat = model_mat(Color.WHITE, null, -1.0, false, 0.9, Color.WHITE, BUILDING_GRADE)
		h = mi.mesh.get_aabb().size.y * k
	_give_own_outline(mat)
	mi.material_override = mat
	return {"mi": mi, "mat": mat, "h": h}


## A fort's yard in the world (pure of nodes, cached): {"pid", "kind", "kit", "capital", "frame" (gate on local -Z),
## "court" (Rect2 in the frame), "gate_z", "gate_dir", "yaw", "floor_y", "centre", "radius", "gate": [inner, outer]}.
func fort_geom(pid: String, kind: String, kit: String) -> Dictionary:
	var key := "%s|%s|%s" % [pid, kind, kit]
	if _geom.has(key):
		return _geom[key]
	var t = terrain
	var i: int = t.index_of(pid)
	var gate := gate_dir(pid)
	var at: Vector2 = fort_spot(t, i)[0]
	var frame := Transform3D(Basis(Vector3.UP, atan2(-gate.x, -gate.y)), t.ground_at(at) - Vector3(0, 0.3, 0))
	var row: Dictionary = Models.building_row(kind, kit)
	var has_model: bool = not Models.building_model(kind, kit).is_empty()
	var prim: Dictionary = Kit.PALISADE_YARD if kind == "palisade" else Kit.FORT_YARD
	var cr: Array = row.get("court", []) if has_model else []
	if cr.size() != 4:
		cr = prim["court"]
	var gz: Array = row.get("gate_z", []) if has_model else []
	if gz.size() != 2:
		gz = prim["gate_z"]
	var side: float = float(row.get("side", prim["side"])) if has_model else float(prim["side"])
	var k := Kit.fort_scale(kind) ## UX-2: a level's size on the board: the yard, the gate and the walls scale with the model
	side *= k
	var out := {"pid": pid, "kind": kind, "kit": kit, "capital": false, "frame": frame,
		"court": Rect2(Vector2(cr[0], cr[1]) * k, Vector2(cr[2], cr[3]) * k), "gate_z": Vector2(gz[0], gz[1]) * k,
		"gate_dir": gate, "yaw": atan2(-gate.x, -gate.y), "floor_y": frame.origin.y + float(row.get("floor", 0.3)),
		"centre": at, "radius": side * 0.5}
	out["gate"] = _gates_in(frame, out["gate_z"])
	_geom[key] = out
	return out


## The yard where `pid`'s owner's armies stand in `s`: a capital's fortress always; in a game with sieges, every fort
## (the kit of its level and builder). {} for a province without one. See fort_geom for the keys.
func yard_of(pid: String, s: GameState) -> Dictionary:
	if fortresses.has(pid):
		## a capital's fortress (not cached: the preview can rebuild it)
		var f: Dictionary = fortresses[pid]
		var frame: Transform3D = (f["node"] as Node3D).transform
		var i: int = terrain.index_of(pid)
		return {"pid": pid, "kind": "fortress", "kit": String(capital_of.get(pid, "")), "capital": true, "frame": frame,
			"court": f["court"], "gate_z": f["gate_z"], "gate_dir": f["gate_dir"], "yaw": f["yaw"],
			"floor_y": terrain.stage_h[i] + float(f["floor"]), "centre": Vector2(frame.origin.x, frame.origin.z),
			"radius": float(f.get("side", FORTRESS_SIDE)) * 0.5, "gate": gate_points(pid)}
	if s == null or not s.sieges:
		return {}
	var p := s.find_province(pid)
	if p == null or p.fort_level <= 0 or terrain.index_of(pid) < 0:
		return {}
	var kit: String = p.fort_by if not p.fort_by.is_empty() else String(map_kits().get(pid, ""))
	return fort_geom(pid, SiegeBoard.kind_of(p.fort_level), kit)


## A yard's muster point and facing in the world, as courtyard() gives a capital's: [centre, facing, width, depth, yaw].
static func court_of(y: Dictionary) -> Array:
	var r: Rect2 = y["court"]
	var frame: Transform3D = y["frame"]
	var p: Vector3 = frame * Vector3(r.get_center().x, 0, r.position.y)
	return [Vector2(p.x, p.z), y["gate_dir"], r.size.x, r.size.y, y["yaw"]]


static func _gates_in(frame: Transform3D, gz: Vector2) -> Array:
	var inner: Vector3 = frame * Vector3(0, 0, gz.x)
	var outer: Vector3 = frame * Vector3(0, 0, gz.y)
	return [Vector2(inner.x, inner.z), Vector2(outer.x, outer.z)]


func _capital_mats(pid: String) -> Array:
	var f: Dictionary = fortresses.get(pid, {})
	return [f.get("mat"), f.get("pal_mat")].filter(func(m): return m != null)


func _cut_mats(mats: Array, plane: Vector4, y: float) -> void:
	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("cut_plane", plane)
		(m as ShaderMaterial).set_shader_parameter("cut_y", y)
		var om: ShaderMaterial = _own_outline.get(m)
		if om != null:
			om.set_shader_parameter("cut_plane", plane)
			om.set_shader_parameter("cut_y", y)


## The code fallback of a damage look (§10.1, §13.3): a dither cut through the walls, in the fort frame (gate on -Z).
## `h` is the model's whole height (its towers' roofs included; the curtain walls stand about half of it). Damaged:
## the gate-side corner knocked down from about half the walls' height; battered: a wider corner, lower; breached:
## the whole gate side down to its footing. [Vector4 plane, float y] (a zero plane for an intact fort).
static func _damage_cut(frame: Transform3D, hs: float, h: float, look: String) -> Array:
	var n_local := Vector3.ZERO
	var d_local := 0.0
	var y_k := 0.0
	match look:
		"damaged":
			n_local = Vector3(0.6, 0, -0.8)
			d_local = 0.86 * hs
			y_k = 0.26
		"battered":
			n_local = Vector3(0.6, 0, -0.8)
			d_local = 0.7 * hs
			y_k = 0.13
		"breached":
			n_local = Vector3(0, 0, -1)
			d_local = 0.5 * hs
			y_k = 0.04
		_:
			return [Vector4.ZERO, 0.0]
	var n: Vector3 = (frame.basis.orthonormalized() * n_local).normalized()
	return [Vector4(n.x, 0.0, n.z, n.dot(frame.origin) + d_local), frame.origin.y + h * y_k]


func _rubble(parent: Node3D, frame: Transform3D, spots: Array, s: float) -> void:
	var glb: Dictionary = Models.building_model("rubble")
	var mesh: Mesh = glb["mesh"] if not glb.is_empty() else Models.building_primitive("rubble")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for k in spots.size():
		var lp: Vector2 = spots[k]
		var w: Vector3 = frame * Vector3(lp.x, 0, lp.y)
		w.y = maxf(terrain.height_at(Vector2(w.x, w.z)), 0.0) - 0.2
		mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, 0.9 * k).scaled(Vector3.ONE * maxf(s, 0.8)), w))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Rubble"
	mi.multimesh = mm
	mi.material_override = model_mat(Color.WHITE, glb.get("tex"), -1.0, false, 0.9, Color.WHITE, BUILDING_GRADE)
	parent.add_child(mi)


func _smoke(parent: Node3D, at: Vector3, puffs: int, k: float) -> void:
	var sm := MultiMesh.new()
	sm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * k
	sm.mesh = quad
	sm.instance_count = puffs
	for i in puffs:
		sm.set_instance_transform(i, Transform3D(Basis(), at))
	var smi := MultiMeshInstance3D.new()
	smi.name = "Smoke"
	smi.multimesh = sm
	var smat := ShaderMaterial.new()
	smat.shader = SH_SMOKE
	smi.material_override = smat
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(smi)


func _fire(parent: Node3D, at: Vector3, s: float) -> void:
	var fmi := MeshInstance3D.new()
	fmi.name = "Fire"
	fmi.mesh = Kit.campfire()
	fmi.transform = Transform3D(Basis().scaled(Vector3.ONE * maxf(s, 1.0)), at)
	fmi.material_override = model_mat(Color.WHITE)
	parent.add_child(fmi)


## The next level rising out of its scaffolding: its model drawn solid up to `rise` of its height and as a faint
## dither above (the part still to come), inside a lattice of timber.
func _rising(parent: Node3D, pid: String, to_kind: String, kit: String, rise: float, col: Color) -> void:
	if to_kind.is_empty() or terrain.index_of(pid) < 0:
		return
	var g := fort_geom(pid, to_kind, kit)
	var frame: Transform3D = g["frame"]
	var piece := _fort_piece(to_kind, kit)
	var holder := Node3D.new()
	holder.name = "Rising"
	holder.transform = frame
	parent.add_child(holder)
	holder.add_child(piece["mi"])
	(piece["mat"] as ShaderMaterial).set_shader_parameter("team", col)
	var top: float = frame.origin.y + float(piece["h"]) * clampf(rise, 0.02, 1.0)
	_cut_mats([piece["mat"]], Vector4(0, 1, 0, top), top)
	var sc_row: Dictionary = Models.building_row("scaffold", kit)
	var sc_glb: Dictionary = Models.building_model("scaffold", kit)
	var lat := MeshInstance3D.new()
	lat.name = "Scaffold"
	lat.mesh = sc_glb["mesh"] if not sc_glb.is_empty() else Kit.scaffold(float(g["radius"]) * 2.0 * 0.86, maxf(float(piece["h"]) * 0.75, 6.0), kit)
	lat.material_override = model_mat(Color.WHITE, sc_glb.get("tex"), float(sc_row.get("key_hue", -1.0)), false, 0.95)
	holder.add_child(lat)


func _chevrons(parent: Node3D, frame: Transform3D, r: float, col: Color) -> MultiMeshInstance3D:
	var angles: Array = SiegeBoard.chevron_angles()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = Kit.chevron_banner()
	mm.instance_count = angles.size()
	var c: Vector3 = frame.origin
	for k in angles.size():
		var a: float = float(angles[k])
		var dl := Vector3(sin(a), 0, -cos(a))
		var w: Vector3 = frame * (dl * r)
		w.y = maxf(terrain.height_at(Vector2(w.x, w.z)), 0.0)
		var outward := Vector2(w.x - c.x, w.z - c.z).normalized()
		mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, atan2(outward.x, outward.y)).scaled(Vector3.ONE * 1.3), w))
		mm.set_instance_custom_data(k, col.srgb_to_linear())
	var mi := MultiMeshInstance3D.new()
	mi.name = "Chevrons"
	mi.multimesh = mm
	mi.material_override = model_mat(Color.WHITE, null, -1.0, true)
	parent.add_child(mi)
	return mi


## Clears a province's village and landmark from under a fort built there (`show` false), or puts them back.
func _show_villages(pid: String, show: bool) -> void:
	var i: int = terrain.index_of(pid)
	if i < 0 or terrain.has_fort[i]:
		return
	var at: Vector2 = fort_spot(terrain, i)[0]
	for v in _village_at.get(pid, []):
		var near: bool = (v["pos"] as Vector2).distance_to(at) < float(v["r"]) + Kit.PALISADE_R * Kit.fort_scale("palisade") + 12.0
		var xf: Transform3D = v["xf"]
		(v["mm"] as MultiMesh).set_instance_transform(int(v["k"]), xf if (show or not near) else Transform3D(Basis().scaled(Vector3.ONE * 0.001), xf.origin))


## The viewer's own queued Fortify orders (design/M3C_SIEGES.md §10.2, "ghost scaffolding shows only in its owner's
## view"): `sites` province id -> the kind that will rise; each stands as a translucent scaffold in `colour`. The
## board passes only the viewing player's orders, and none while the board is covered (a hotseat handoff).
func set_fortify_ghosts(sites: Dictionary, colour: Color = Color.WHITE) -> void:
	for pid in _ghost_scaffolds.keys():
		if not sites.has(pid):
			(_ghost_scaffolds[pid] as Node).queue_free()
			_ghost_scaffolds.erase(pid)
	for pid in sites.keys():
		if _ghost_scaffolds.has(pid) or terrain.index_of(pid) < 0:
			continue
		var g := fort_geom(pid, String(sites[pid]), String(map_kits().get(pid, "")))
		var mi := MeshInstance3D.new()
		mi.name = "GhostScaffold_" + pid
		mi.mesh = Kit.scaffold(float(g["radius"]) * 2.0 * 0.86, 9.0)
		mi.transform = g["frame"]
		var gm := ShaderMaterial.new()
		gm.shader = SH_GHOST
		gm.set_shader_parameter("team", colour)
		mi.material_override = gm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		buildings.add_child(mi)
		_ghost_scaffolds[pid] = mi


## The provinces with a ghost scaffold now, sorted (tests).
func fortify_ghosts() -> Array:
	var out: Array = _ghost_scaffolds.keys()
	out.sort()
	return out


## A one-shot dust burst at `at` (§10.2's strikes, collapses and masons): `spread` and `size` in world units.
func burst(at: Vector3, spread: float = 6.0, size: float = 3.0, puffs: int = 10, life: float = 1.2, tint: Color = Color(0.80, 0.74, 0.64)) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = puffs
	for i in puffs:
		mm.set_instance_transform(i, Transform3D(Basis(), at))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Dust"
	mi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = SH_DUST
	mat.set_shader_parameter("spread", spread)
	mat.set_shader_parameter("lift", spread * 0.8)
	mat.set_shader_parameter("size", size)
	mat.set_shader_parameter("tint", tint)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	buildings.add_child(mi)
	_fx.append({"node": mi, "mat": mat, "t": 0.0, "life": life})


## Ages the dust bursts by `delta` seconds (the board steps it with the playback's speed) and clears the finished.
func step_fx(delta: float) -> void:
	if _fx.is_empty():
		return
	var keep: Array = []
	for fx in _fx:
		fx["t"] = float(fx["t"]) + delta
		var k: float = float(fx["t"]) / float(fx["life"])
		if k >= 1.0:
			(fx["node"] as Node).queue_free()
			continue
		(fx["mat"] as ShaderMaterial).set_shader_parameter("age", k)
		keep.append(fx)
	_fx = keep


func clear_fx() -> void:
	for fx in _fx:
		(fx["node"] as Node).queue_free()
	_fx.clear()


## Where a beat at a fort plays (the gate side of its walls), and its half side: [Vector3, float]; [] for none.
func wall_point(pid: String, s: GameState = null) -> Array:
	var y := yard_of(pid, s)
	if y.is_empty():
		var d: Dictionary = fort_draw.get(pid, {})
		var g := _fort_frame(pid, false, d) if terrain.index_of(pid) >= 0 else {}
		if g.is_empty():
			return []
		return [(g["frame"] as Transform3D) * Vector3(0, 2.0, 0), float(g["hs"])]
	var frame: Transform3D = y["frame"]
	return [frame * Vector3(0.0, 4.0, -float(y["radius"]) * 0.9), float(y["radius"])]


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
