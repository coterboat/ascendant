class_name BattleStage3D
extends BattleSimpleView
## M3b, "battles on the land" (design/3D_DIRECTION.md 7; design/M3_BATTLES.md 3-8 carried to 3D): a battle
## played back in 3D on the province where it happened, driven entirely by the renderer-agnostic
## BattlePlayer. It is the Simple view's screen with its field swapped for the land: the same top bar
## (plaques, strength bars with break notches, chips), caption strip, result card, controls, why panel,
## legend and selection (the M3-3 and M3-4 components, unchanged), so a host shows either with the same
## calls (show_event, show_battle, close; signals closed, codex_requested, report_requested) and the why
## panel works here exactly as in the Simple view.
##
## The land: the board's own baked world (Board3D.terrain_now(), world_view.gd) in a SubViewport drawn
## full-screen under the 2D screen, at the window's physical pixels. The battle stands on the province's
## ground (world3d/battle_formation.gd: the defender holds the stage, before its gate at a fortress, its
## fort behind it; the attacker toward the road it came by; a border battle on the crossing), with the
## woods, rocks and houses where it stands lifted off the table and put back afterwards (clear_for).
##
## The fighters (world3d/battle_figures.gd): every fighter its own figure, the real models in their pose
## families, front rank, second rank and back line, rulers and commanders in their places, a standard
## bearer and a musician per side. Beats drive them: attack_started / attack_landed (a lunge and the strike
## pose, or a release and a 3D projectile: Volley bolts, Skirmish javelins, the Regent's arcane bolt; Wings
## leap onto their target), impacts (camera-facing, drawn by the Simple view's own BattleEffects
## functions at the target's upper body), hit recoils with a red tint, Iron Hide sparks, deaths (a topple,
## then the fallen pose, greyed), heals (a green rise), routs (they turn, run for the back edge and are
## gone), the winners' cheer and the aftermath's lost fading away. Sounds come from BattleFx.sound_of,
## spaced by its SoundGate; the flash limiter, the shake limiter and reduced motion are BattleFx's.
##
## The camera (world3d/battle_camera.gd): framed from the flank so the two sides spread across the screen,
## raised until no hill or wall hides anyone, fitted into the band the 2D screen leaves clear and centred.
## A key-moment jump frames the moment's camera hint (its fighters, or a side) and rises back after it.
## F frames the whole battle again (BattleControls.reframe_requested); a right-drag (or a middle-drag)
## turns the camera, the wheel zooms. Moves take at most MOVE_TIME and are cuts with reduced motion.
##
## The 2D over it (projected every frame, native resolution): hp plates over the fighters (all of them on a
## small side; on a massed side only the hurt, rulers, commanders and whoever is hovered or pinned), ruler
## name plates, status glyphs, ground rings (the pinned fighter, the hovered one, the morale auras),
## floating damage and heal numbers, impacts, dust, sparks and bursts. Hovering a fighter (a ray against
## every figure) shows BattleExplain's words; a click selects it in BattleSelection and pins it.
##
## It reads the log, its report, static data and its settings, and never changes the game: no RNG anywhere
## in world3d (tests scan it), and watching leaves the game state and its record unchanged (tests).
##
## Performance (design/3D_DIRECTION.md 3.5): one MultiMesh per unit type and pose (both sides in one), mesh
## LODs, effects in the 2D overlay's single draw; the quality ladder steps down after LADDER_SECONDS under
## LADDER_FPS (world_view.gd set_quality, then the figures' shadows). `perf_stats()` reports it.

const Terrain3D := preload("res://world3d/terrain3d.gd")
const WorldView := preload("res://world3d/world_view.gd")
const Models := preload("res://world3d/models.gd")
const Kit := preload("res://world3d/kit.gd")
const Formation := preload("res://world3d/battle_formation.gd")
const Cam := preload("res://world3d/battle_camera.gd")
const Figures := preload("res://world3d/battle_figures.gd")

## The field's band the camera frames the battle in (field pixels kept clear at the top for the round banner,
## the moment toast and the morale tags, and at the sides and bottom).
const BAND_TOP := 64.0
const BAND_BOTTOM := 28.0
const BAND_SIDE := 40.0
const MOVE_TIME := 1.0 ## a camera move (3D_DIRECTION 7.4: at most 1.2 s)
const FOCUS_HOLD := 2.8 ## real seconds a key moment's framing holds after the moment, then the camera rises back
const FOCUS_MIN_SPAN := 30.0
const MAX_PX := 2.0
const LADDER_FPS := 40.0
const LADDER_SECONDS := 3.0
const MAX_RUNG := 4
const PROP_CELL := 28.0 ## the woods' cells (world units)
const PROP_LOD_BIAS := 0.4 ## the woods drop detail sooner than the fighters
const WOODS_NEAR := 40.0
const GLYPH_INTERVAL := 0.12
## the woods and rocks: [model kind, plan key, sizing axis, the board's primitive MultiMesh name]
const PROP_SPECS := [["tree_broadleaf", "broad", "y", "Broadleaf"], ["tree_pine", "pine", "y", "Pines"], ["rock", "rocks", "xz", "Rocks"]] ## model trees this far round the battle's ground, primitives beyond
## effects (playback seconds)
const IMPACT_LIFE := 0.22
const RING_LIFE := 0.3
const DUST_LIFE := 0.45
const SPARK_LIFE := 0.35
const HEAL_LIFE := 0.8
const BURST_LIFE := 1.3
const WAVE_LIFE := 0.5
const NUMBER_LIFE := 0.6
const PLATE_W := 28.0
const PLATE_H := 5.0
const MISS_OVERSHOOT := 7.0
const CAMERA_HINT := "F frames the whole battle · drag with the right button to turn · the wheel zooms"

var terrain: RefCounted
var wv: Node3D
var figures: Node3D
var view3d: Control
var overlay: Control
var proj_root: Node3D
var stage_fort: Node3D
var plan := {}
var rig := {} ## the rig the camera stands at now (before the shake)
var goal := {} ## the whole battle's framing
var quality := 0
var auto_quality := true
var built := false

var _vp: SubViewport
var _px := 1.0
var _move := {} ## {"from", "to", "t", "dur"}: a camera move under way (real seconds)
var _focus_left := -1.0
var _focus_pending := {} ## a jump's moment whose framing starts when it fires
var _drag := -1 ## the mouse button turning the camera, or -1
var _drag_from := Vector2.ZERO
var _user_rig := false
var _proj: Array = [] ## projectiles: {"kind", "from", "to", "t0", "life", "arc", "hit", "mi_slot"}
var _proj_mm := {} ## kind -> MultiMeshInstance3D
var _fx: Array = [] ## projected effects: {"kind", "at": Vector3, "age", "life", "r", "big", "bright", "frames", ...}
var _numbers: Array = [] ## {"at": Vector3, "text", "color", "size", "age", "life"}
var _glyph_cache := {} ## fighter id -> glyph kinds
var _auras: Array = [] ## [{"fid", "kind": "aura_up" | "aura_down"}]
var _cleared: Array = [] ## [{"mm", "i", "xf"}]: woods, rocks and houses lifted off the table for this battle
var _shake_cam := {} ## {"t", "amp", "dur", "phase"} (real seconds, px)
var _sky_frames := 0
var _slow := 0.0
var _frame_ms: Array = []
var _last_tick_usec := 0
var _clock_last := 0.0
var _side_colours: Array = []
var _hp_of: Array = [] ## by fighter: its max hp
var _xf := Transform3D()
var _view := Vector2(1600, 900)
var bright_frames_drawn := 0
var shakes_started := 0
var lunges_started := 0
var focus_moves := 0
var _glyphs_dirty_3d := true
var _side_lin: Array = []
var _field_pending := false
var _wood_cells := {} ## Vector2i cell -> {"model": [MultiMeshInstance3D], "prim": [...]}
var _glyph_at := -10.0
var _xfs := {} ## MultiMesh -> [Transform3D]: where each woods, rocks, village and cottage instance stands


func _init() -> void:
	super()
	name = "BattleStage3D"
	tooltip_text = " " ## the real text comes from _get_tooltip (the fighter under the mouse)
	backdrop.visible = false
	cards_layer.visible = false
	view3d = World3DView.new()
	view3d.name = "Land"
	view3d.stage = self
	view3d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view3d.position = Vector2.ZERO
	view3d.size = Vector2(BASE.x, FIELD_H)
	field.add_child(view3d)
	field.move_child(view3d, 0) ## the land is the field: under the stage, the overlay and the banners
	overlay = StageOverlay.new()
	overlay.name = "StageOverlay"
	overlay.stage = self
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.size = field.size
	field.add_child(overlay)
	field.move_child(overlay, 1)
	controls.reframe_key = true
	controls.reframe_requested.connect(reframe)
	legend.set_rows(BattleLegend.overlay_rows() + stage_rows())
	selection.changed.connect(func(_fid): overlay.queue_redraw())


func _ready() -> void:
	super._ready()
	resized.connect(_fit_viewport)
	_fit_viewport()


## Whether this machine can draw the 3D stage (a real renderer; the headless tests compute it all anyway).
static func available() -> bool:
	return DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() != ""


# --- the world -----------------------------------------------------------------------------------------

## Whether the board's land can be had now without waiting on its bake: baked, or never started (then the
## stage bakes it at once, as the headless tests do). While Board3D's worker is baking it (a windowed run
## that just started), the stage waits for it a frame at a time instead (blocking on it could deadlock).
static func land_ready() -> bool:
	if Board3D._terrain != null and Board3D._task < 0:
		return true
	if Board3D._task >= 0:
		return WorkerThreadPool.is_task_completed(Board3D._task)
	return true

## Builds the land at once (the first show does it; tests and the launcher may call it early).
func build_now() -> void:
	if built:
		return
	built = true
	_vp = SubViewport.new()
	_vp.name = "World"
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_2X
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	terrain = Board3D.terrain_now()
	wv = WorldView.new()
	wv.name = "WorldView"
	_vp.add_child(wv)
	wv.setup(terrain, Board3D.look)
	wv.set_effects(true)
	_rechunk_props(PROP_CELL)
	## the woods without their ink: the fighters keep theirs, so they stand out from the trees, and the
	## woods' second pass was the battle's dearest (measured: about 45% of the frame's triangles)
	wv.set_prop_outlines(false)
	figures = Figures.new()
	figures.name = "Fighters"
	figures.wv = wv
	figures.land = terrain
	wv.add_child(figures)
	proj_root = Node3D.new()
	proj_root.name = "Projectiles"
	wv.add_child(proj_root)
	for kind in ["bolt", "javelin", "arcane"]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = projectile_mesh(kind)
		mm.instance_count = BattleFx.MAX_PROJECTILES
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.name = kind.capitalize()
		mi.multimesh = mm
		mi.material_override = _projectile_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		proj_root.add_child(mi)
		_proj_mm[kind] = mi
	_fit_viewport()


## The land renders the field (1600 x 600 at the base viewport, the full width even while the why panel is
## docked over its right side) at the window's physical pixels, at most MAX_PX per screen pixel.
func _fit_viewport() -> void:
	if _vp == null:
		return
	var s := Vector2(BASE.x, FIELD_H)
	var px := 1.0
	if is_inside_tree():
		px = clampf(get_viewport().get_final_transform().get_scale().x, 1.0, MAX_PX)
	_px = px
	_vp.size = Vector2i(maxi(64, int(s.x * px)), maxi(64, int(s.y * px)))
	_view = Vector2(_vp.size)
	if view3d != null:
		view3d.queue_redraw()
	if wv != null:
		wv.view_size = _view
		if not plan.is_empty():
			goal = _frame_all()
			if not _user_rig and _focus_left < 0.0:
				_set_rig(goal)


## The woods and rocks in cells of `cell` world units, each cell twice: the model table's trees and the
## primitive ones (the board keeps one primitive MultiMesh for the whole map and the models in 200-unit
## chunks). Round the battle a cell draws its model trees; further out its primitives (about a fifteenth of
## the triangles), so the woods never cost more than the fighters (measured: a forest battle went from 6.3
## to about 1.5 million triangles). Each cell also picks its own level of detail from its distance.
func _rechunk_props(cell: float) -> void:
	_wood_cells = {}
	_xfs = {}
	var pl: Dictionary = WorldView.plan_of(terrain)
	## the board's own pieces, to reuse their meshes and materials
	var olds: Array = []
	var prim_mi := {}
	var model_mi := {}
	for n in wv.props.get_children():
		if not (n is MultiMeshInstance3D):
			continue
		olds.append(n)
		var nm := String(n.name)
		for spec in PROP_SPECS:
			if n.has_meta("chunk") and nm.begins_with(String(spec[0])):
				model_mi[spec[1]] = n
			elif not n.has_meta("chunk") and nm == String(spec[3]):
				prim_mi[spec[1]] = n
	var fresh: Array = []
	for spec in PROP_SPECS:
		var list: Array = pl.get(spec[1], [])
		for model in [false, true]:
			var src: MultiMeshInstance3D = (model_mi if model else prim_mi).get(spec[1])
			if src == null:
				continue
			var base := _model_base(String(spec[0]), String(spec[2])) if model else Transform3D()
			var buckets := {}
			for xf in list:
				var o: Vector3 = (xf as Transform3D).origin
				var key := Vector2i(int(floor(o.x / cell)), int(floor(o.z / cell)))
				if not buckets.has(key):
					buckets[key] = []
				buckets[key].append((xf as Transform3D) * base)
			for key in buckets.keys():
				var xfs: Array = buckets[key]
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.use_custom_data = true
				mm.mesh = src.multimesh.mesh
				mm.instance_count = xfs.size()
				for i in xfs.size():
					mm.set_instance_transform(i, xfs[i])
					mm.set_instance_custom_data(i, Color(1, 1, 1, 1))
				var mi := MultiMeshInstance3D.new()
				mi.name = "%s_%s_%d_%d" % [String(spec[1]), "m" if model else "p", key.x, key.y]
				mi.multimesh = mm
				mi.material_override = src.material_override
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if model else src.cast_shadow
				mi.lod_bias = PROP_LOD_BIAS
				mi.visible = false
				if model:
					mi.set_meta("chunk", true)
				fresh.append(mi)
				_xfs[mm] = xfs
				if not _wood_cells.has(key):
					_wood_cells[key] = {"model": [], "prim": []}
				_wood_cells[key]["model" if model else "prim"].append(mi)
	for old in olds:
		wv.props.remove_child(old)
		wv._prop_chunks.erase(old)
		wv._prop_prims.erase(old)
		old.queue_free()
	for mi in fresh:
		wv.props.add_child(mi)
		if mi.has_meta("chunk"):
			wv._prop_chunks.append(mi)
		else:
			wv._prop_prims.append(mi)
	_table_buildings(pl)


## A woods or rocks model's transform onto its primitive's placement (world_view.gd _build_prop_models: the
## model normalised to its primitive's size, a one-for-one swap).
static func _model_base(kind: String, axis: String) -> Transform3D:
	var glb: Dictionary = Models.building_model(kind)
	if glb.is_empty():
		return Transform3D()
	var row: Dictionary = Models.building_row(kind)
	var prim: AABB = Models.building_primitive(kind).get_aabb()
	var a: AABB = glb["aabb"]
	var sc: float = (prim.size.y / maxf(a.size.y, 0.001)) if axis == "y" else (maxf(prim.size.x, prim.size.z) / maxf(maxf(a.size.x, a.size.z), 0.001))
	var yaw := deg_to_rad(float(row.get("yaw", 180.0)))
	var c: Vector3 = a.get_center()
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc), Vector3.ZERO) * Transform3D(Basis(), Vector3(-c.x, -a.position.y, -c.z))


## Where the world's villages, landmarks and cottages stand (each MultiMesh's instances, from the land's plan
## as world_view.gd placed them), so the stage can lift them without reading the renderer back.
func _table_buildings(pl: Dictionary) -> void:
	var by_path := {}
	for v in pl.get("villages", []):
		var paths: Array = Models.building_variants(v["kind"])
		if paths.is_empty():
			continue
		var path: String = paths[Models.variant_for(v["province"], paths.size())]
		if not by_path.has(path):
			by_path[path] = {"kind": v["kind"], "list": []}
		by_path[path]["list"].append(v)
	for n in wv.buildings.get_children():
		if not (n is MultiMeshInstance3D):
			continue
		var nm := String(n.name)
		var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
		if nm.begins_with("Cottages"):
			var v := int(nm.trim_prefix("Cottages"))
			var houses: Array = pl.get("houses", [[], [], []])
			if v >= 0 and v < houses.size() and (houses[v] as Array).size() == mm.instance_count:
				_xfs[mm] = houses[v]
		elif nm.begins_with("Village_"):
			for path in by_path.keys():
				if "Village_" + String(path).get_file().get_basename() != nm:
					continue
				var glb: Dictionary = Models.model_at(path)
				if glb.is_empty():
					continue
				var row: Dictionary = Models.building_row(by_path[path]["kind"])
				var aabb: AABB = glb["aabb"]
				var sc: float = float(row.get("side", 24.0)) / maxf(aabb.size.x, aabb.size.z)
				var c: Vector3 = aabb.get_center()
				var yaw0 := deg_to_rad(float(row.get("yaw", 180.0)))
				var xfs := []
				for vv in by_path[path]["list"]:
					var b := Basis(Vector3.UP, float(vv["yaw"]) + yaw0).scaled(Vector3.ONE * sc)
					var at: Vector3 = terrain.ground_at(vv["pos"]) - Vector3(0, 0.25, 0)
					xfs.append(Transform3D(b, at) * Transform3D(Basis(), Vector3(-c.x, -aabb.position.y, -c.z)))
				if xfs.size() == mm.instance_count:
					_xfs[mm] = xfs


## Model trees within `r` of `site` (when the quality rung allows them), primitives everywhere else.
func _woods_near(site: Vector2, r: float) -> void:
	var models := quality < 2
	for key in _wood_cells.keys():
		var c := (Vector2(key) + Vector2(0.5, 0.5)) * PROP_CELL
		var near := models and c.distance_to(site) < r
		var cellv: Dictionary = _wood_cells[key]
		var has_model: bool = not (cellv["model"] as Array).is_empty()
		for mi in cellv["model"]:
			(mi as Node3D).visible = near
		for mi2 in cellv["prim"]:
			(mi2 as Node3D).visible = not (near and has_model)


## World info the formation needs: the fortresses' gates and the forts.
func _world_info() -> Dictionary:
	var fz := {}
	for pid in wv.fortresses.keys():
		var gp: Array = wv.gate_points(pid)
		fz[pid] = {"gate_outer": gp[1], "gate_dir": wv.fortresses[pid]["gate_dir"], "half": WorldView.FORTRESS_SIDE * 0.5 + 4.0}
	var forts := {}
	for i in terrain.ids.size():
		if terrain.has_fort[i] and not terrain.is_capital[i]:
			forts[terrain.ids[i]] = WorldView.fort_spot(terrain, i)
	return {"fortresses": fz, "forts": forts}


# --- showing a battle (the Simple view's flow, with the land for a field) ----------------------------

func show_battle(battle_log: Dictionary, report: Dictionary = {}, seats: Array = [], event: Dictionary = {}) -> String:
	var st := BattleFx.settings()
	if not _settings_read:
		_settings_read = true
		reduced_motion = reduced_motion or bool(st.reduced_motion)
		screen_shake = screen_shake and bool(st.screen_shake)
	_hint_seen = bool(st.first_hint_seen)
	visible = true
	var problem := BattlePlayer.playback_problem(battle_log)
	if problem.is_empty() and battle_log.get("sides", []).size() != 2:
		problem = "Battles with more than two sides can't be watched yet."
	if not problem.is_empty():
		_show_message(problem)
		return problem
	message_panel.visible = false
	_log = battle_log
	_report = report
	_event = event
	_seats = seats.duplicate()
	var order := _seats if not _seats.is_empty() else UiPalette.seat_order()
	_side_seat = []
	_massed = []
	for s in _log.sides:
		_side_seat.append(order.find(String(s.faction)))
		_massed.append(s.fighters.size() > MASSED)
	_held_by = [-1, -1]
	if player != null:
		_disconnect_player()
	player = BattlePlayer.new(_log, _report)
	player.reduced_motion = reduced_motion
	player.beat.connect(_on_beat)
	player.seeked.connect(_on_seeked)
	controls.bind(player, st)
	_why_docks = true ## the camera frames the battle beside the docked panel at any size
	_why_open = controls.why_open
	_shake.enabled = screen_shake and not reduced_motion
	_flash.reset()
	_shake.reset()
	_sound.reset()
	if not _mood_on:
		_mood_on = true
		GameAudio.battle(true)
	_apply_width()
	_build_field()
	selection.bind(player, _tab_order())
	why_panel.bind(player, selection)
	legend.reduced_motion = reduced_motion
	_set_legend_open(controls.legend_open)
	_fill_top_bar()
	_fill_end_card()
	end_card.visible = false
	_set_caption([])
	_last_time = 0.0
	_on_seeked(player.live_state())
	if _vp != null and not _field_pending:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return ""


func close() -> void:
	super.close()
	if _vp != null:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Builds the battle on the land: its ground plan, the cleared ground, the fort, the fighters, the camera.
## While the board's land is still baking, the battle waits on a "Preparing the land" note (tick finishes it).
func _build_field() -> void:
	_cards = []
	_glyph_cards = []
	effects.clear()
	plan = {}
	if not built and not land_ready():
		_field_pending = true
		_show_message("Preparing the land for this battle...")
		return
	_field_pending = false
	build_now()
	plan = Formation.plan(_log, terrain, _world_info(), _band().size.x / maxf(_band().size.y, 1.0))
	_side_colours = []
	_side_lin = []
	var emblems := []
	var factions := []
	for si in _log.sides.size():
		_side_colours.append(UiPalette.seat_color(_side_seat[si]))
		_side_lin.append(figure_colour(_side_seat[si]))
		emblems.append(maxi(_side_seat[si], 0))
		factions.append(String(_log.sides[si].faction))
	_hp_of = []
	for f in _log.fighters:
		_hp_of.append(int(f.max_hp))
	clear_for(plan["footprint"])
	_woods_near(plan["site"], _footprint_radius() + WOODS_NEAR)
	_place_stage_fort()
	figures.reduced_motion = reduced_motion
	figures.build(_log, plan, _side_colours, _side_lin, emblems, factions)
	view3d.queue_redraw()
	_proj.clear()
	_fx.clear()
	_numbers.clear()
	_glyph_cache = {}
	_user_rig = false
	_focus_left = -1.0
	_focus_pending = {}
	_move = {}
	goal = _frame_all()
	_set_rig(goal)
	var left_near: bool = bool(goal.get("left_near", true))
	var near: int = plan["near"]
	var far: int = plan["far"]
	layout = {"left": near if left_near else far, "right": far if left_near else near, "scale": 1.0, "slots": plan["slots"]}


## Puts back what the last battle lifted off the table, then lifts the woods, rocks, villages and houses
## standing on `poly` (the battle's footprint, world ground points).
func clear_for(poly: PackedVector2Array) -> void:
	restore_ground()
	if wv == null:
		return
	for mm in _xfs.keys():
		var xfs: Array = _xfs[mm]
		var pad := 10.0 if xfs.size() > 0 and mm.mesh != null and mm.mesh.get_aabb().size.x * (xfs[0] as Transform3D).basis.get_scale().x > 8.0 else 2.5
		for i in xfs.size():
			var xf: Transform3D = xfs[i]
			if Formation.inside(poly, Vector2(xf.origin.x, xf.origin.z), pad):
				_cleared.append({"mm": mm, "i": i, "xf": xf})
				(mm as MultiMesh).set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), xf.origin - Vector3(0, 50, 0)))


func restore_ground() -> void:
	for c in _cleared:
		(c["mm"] as MultiMesh).set_instance_transform(int(c["i"]), c["xf"])
	_cleared = []


## How many woods, rocks and houses still stand on `poly` (tests: none, on the battle's footprint); with
## `all`, how many the land has there, lifted or not.
func props_standing_on(poly: PackedVector2Array, all: bool = false) -> int:
	var gone := {}
	for c in _cleared:
		gone["%d:%d" % [(c["mm"] as Object).get_instance_id(), int(c["i"])]] = true
	var n := 0
	for mm in _xfs.keys():
		var xfs: Array = _xfs[mm]
		for i in xfs.size():
			var o: Vector3 = (xfs[i] as Transform3D).origin
			if Formation.inside(poly, Vector2(o.x, o.z), 0.0) and (all or not gone.has("%d:%d" % [(mm as Object).get_instance_id(), i])):
				n += 1
	return n


func _footprint_radius() -> float:
	var r := 0.0
	var site: Vector2 = plan["site"]
	for p in plan["footprint"]:
		r = maxf(r, (p as Vector2).distance_to(site))
	return r


## How many woods, rocks and houses this battle lifted off the table.
func cleared_count() -> int:
	return _cleared.size()


## A fort the log has where the world draws none (the stage's own, behind the defender), or none.
func _place_stage_fort() -> void:
	if stage_fort != null:
		stage_fort.queue_free()
		stage_fort = null
	var fd: Dictionary = plan.get("fort", {})
	if fd.is_empty() or bool(fd.get("world", false)):
		return
	stage_fort = place_fort(wv, String(fd.get("faction", "")), fd["pos"], float(fd["yaw"]), terrain, _side_colours[int(plan["near"])])
	wv.add_child(stage_fort)


## A fort model (the faction's, else the primitive) standing at `at` facing `yaw`, roofs in `team`.
static func place_fort(world: Node3D, faction: String, at: Vector2, yaw: float, t, team: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "StageFort"
	root.position = t.ground_at(at) - Vector3(0, 0.3, 0)
	root.rotation.y = yaw + PI
	var row: Dictionary = Models.building_row("fort", faction)
	var glb: Dictionary = Models.building_model("fort", faction)
	var mi := MeshInstance3D.new()
	var mat: ShaderMaterial
	if not glb.is_empty():
		var aabb: AABB = glb["aabb"]
		var s: float = float(row.get("side", 26.0)) / maxf(aabb.size.x, aabb.size.z)
		mi.mesh = glb["mesh"]
		mi.scale = Vector3.ONE * s
		mi.rotation.y = deg_to_rad(float(row.get("yaw", 180.0)))
		var centre: Vector3 = aabb.get_center()
		mi.position = (Basis(Vector3.UP, mi.rotation.y) * Vector3(-centre.x, -aabb.position.y, -centre.z)) * s
		mi.position.y -= float(row.get("sink", 0.0))
		mat = world.model_mat(team, glb["tex"], float(row.get("key_hue", -1.0)), false, float(row.get("tint", 0.9)), Color.WHITE,
			float(row.get("grade", WorldView.BUILDING_GRADE)))
	else:
		mi.mesh = Models.building_primitive("fort")
		mi.rotation.y = PI
		mat = world.model_mat(team, null, -1.0, false, 0.9, Color.WHITE, WorldView.BUILDING_GRADE)
	mi.material_override = mat
	root.add_child(mi)
	return root


# --- the camera ------------------------------------------------------------------------------------------

## The field band the camera fills, in view pixels (the view is the field).
func _band() -> Rect2:
	var fw := field_width()
	var r := Rect2(BAND_SIDE, BAND_TOP, fw - BAND_SIDE * 2.0, FIELD_H - BAND_TOP - BAND_BOTTOM)
	return Rect2(r.position * _px, r.size * _px)


## The points that must stay in view: every fighter's feet and head. With `los`, each one's upper body
## instead (what the camera must see past hills and walls).
func _points(ids: Array = [], los: bool = false) -> Array:
	var pts := []
	var slots: Array = plan.get("slots", [])
	var list := ids if not ids.is_empty() else range(slots.size())
	for fid in list:
		var s = slots[int(fid)]
		if s == null:
			continue
		var p: Vector2 = s["pos"]
		var h: float = Formation.height_of(String(_log.fighters[int(fid)].type))
		if los:
			pts.append(Vector3(p.x, float(s["y"]) + h * 0.7, p.y))
		else:
			pts.append(Vector3(p.x, float(s["y"]), p.y))
			pts.append(Vector3(p.x, float(s["y"]) + h, p.y))
	return pts


func _obstacles() -> Array:
	var out := []
	for pid in wv.fortresses.keys():
		var c: Vector2 = terrain.centre_of(pid)
		out.append({"pos": c, "r": WorldView.FORTRESS_SIDE * 0.5, "top": float(terrain.stage_h[terrain.index_of(pid)]) + 16.0})
	var fd: Dictionary = plan.get("fort", {})
	if not fd.is_empty() and fd.has("pos"):
		var fp: Vector2 = fd["pos"]
		out.append({"pos": fp, "r": Formation.fort_radius(String(fd.get("faction", ""))) * 0.8, "top": terrain.height_at(fp) + 9.0})
	return out


## The framing of the whole battle.
func _frame_all() -> Dictionary:
	if plan.is_empty():
		return {}
	var dr := 0
	var dsi := -1
	for s in _log.sides:
		if s.get("defender", false):
			dsi = int(s.index)
	if dsi >= 0:
		dr = 1 if dsi == int(plan["far"]) else -1
	return Cam.frame(terrain, _points(), _band(), _view, plan["axis"], {"obstacles": _obstacles(), "defender_right": dr,
		"los": _points([], true)})


## Frames the whole battle again (F, or the end of a key moment's framing).
func reframe() -> void:
	_user_rig = false
	_focus_left = -1.0
	_focus_pending = {}
	goal = _frame_all()
	_move_to(goal)


func _set_rig(r: Dictionary) -> void:
	if r.is_empty():
		return
	rig = r.duplicate()
	_apply_rig()


func _move_to(r: Dictionary) -> void:
	if r.is_empty():
		return
	if reduced_motion or rig.is_empty():
		_move = {}
		_set_rig(r)
		return
	_move = {"from": rig.duplicate(), "to": r.duplicate(), "t": 0.0, "dur": MOVE_TIME}


func _apply_rig() -> void:
	if wv == null or rig.is_empty():
		return
	var r := rig.duplicate()
	if not _shake_cam.is_empty():
		var k: float = 1.0 - float(_shake_cam["t"]) / float(_shake_cam["dur"])
		if k > 0.0:
			var off := shake_offset(float(_shake_cam["amp"]) * k, float(_shake_cam["t"]), float(_shake_cam["phase"]))
			var wpp: float = float(r["span"]) / FIELD_H ## world units per screen pixel of the field
			var right := Cam.right_of(float(r["yaw"]))
			r["target"] = (r["target"] as Vector3) + Vector3(right.x, 0.0, right.y) * off.x * wpp + Vector3.UP * off.y * wpp
	wv.rig = r
	wv.apply_rig()
	_xf = Cam.xform_of(r)
	if figures != null:
		## a man's height in view pixels at the battle's middle sets the ink: 2 px on a close battle, under
		## 1 px on a crowd of small figures (Look A's hull would otherwise draw them half in ink)
		var man_px: float = Kit.FIG * _view.y / maxf(float(r["span"]), 1.0)
		var w := clampf(man_px / 40.0, 0.55, 2.0)
		figures.set_ink_px(w, w * 0.75, _view)


## A shake's offset in screen pixels at `t` real seconds in: two thirds across, one third up and down, its
## phase from the event's index (never a random number). `amp` already decays with time.
static func shake_offset(amp: float, t: float, phase: float) -> Vector2:
	var w := t * 55.0 + phase
	return Vector2(sin(w) * amp * 2.0 / 3.0, cos(w * 1.3) * amp / 3.0)


## The shake limiter decided yes: the camera shakes (3D_DIRECTION 7.5, M3 4.5).
func _try_shake(spec: Dictionary, event_index: int) -> void:
	if spec.is_empty() or not player.is_playing() or scrubber.is_dragging():
		return
	if not _shake.allow(_real):
		return
	shakes_started += 1
	_shake_cam = {"t": 0.0, "amp": float(spec.amp), "dur": float(spec.dur), "phase": float(event_index % 7) * 0.9}


func _tick_camera(real_delta: float) -> void:
	var changed := false
	if not _move.is_empty():
		_move["t"] = float(_move["t"]) + real_delta
		var k: float = clampf(float(_move["t"]) / float(_move["dur"]), 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		rig = Cam.lerp_rig(_move["from"], _move["to"], e)
		if k >= 1.0:
			_move = {}
		changed = true
	if _focus_left >= 0.0 and player != null and player.is_playing():
		_focus_left -= real_delta
		if _focus_left < 0.0:
			_move_to(goal)
	if not _shake_cam.is_empty():
		_shake_cam["t"] = float(_shake_cam["t"]) + real_delta
		if float(_shake_cam["t"]) >= float(_shake_cam["dur"]) or player == null or not player.is_playing():
			_shake_cam = {}
		changed = true
	if changed:
		_apply_rig()


## A key moment's camera hint framed (the jump's moment fires): its fighters, or a side, held FOCUS_HOLD.
func focus_moment(m: Dictionary) -> void:
	var cam: Dictionary = m.get("camera", {})
	var ids := []
	match String(cam.get("frame", "battle")):
		"fighters":
			ids = BattleLog._ints(cam.get("fighters", []))
		"side":
			var si := int(cam.get("side", -1))
			if si >= 0 and si < _log.sides.size():
				ids = BattleLog._ints(_log.sides[si].fighters)
	if ids.is_empty():
		_move_to(goal)
		return
	## the subject with its neighbours, so the moment reads in its place
	var subject := int(ids[0])
	var sp: Vector2 = plan["slots"][subject]["pos"]
	var near := []
	for f in _log.fighters:
		var s = plan["slots"][int(f.id)]
		if s != null and (s["pos"] as Vector2).distance_to(sp) < 16.0:
			near.append(int(f.id))
	for fid in ids:
		if not near.has(int(fid)):
			near.append(int(fid))
	var r := Cam.frame(terrain, _points(near), _band(), _view, plan["axis"], {"yaws": [float(goal.get("yaw", 0.0))], "obstacles": _obstacles(),
		"los": _points(near, true),
		"min_span": FOCUS_MIN_SPAN, "pitch": float(goal.get("pitch", Cam.PITCH_MIN))})
	if r.is_empty():
		return
	r["span"] = minf(float(r["span"]), float(goal.get("span", 300.0)))
	focus_moves += 1
	_focus_left = FOCUS_HOLD
	_move_to(r)


# --- the clock ----------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	if player == null:
		return
	if _field_pending:
		if land_ready():
			message_panel.visible = false
			_build_field()
			_fill_top_bar()
			selection.order = _tab_order()
			_on_seeked(player.live_state())
			if _vp != null:
				_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		return
	var before := player.time()
	super.tick(delta)
	var now := player.time()
	var dt := maxf(0.0, now - before)
	if now < before:
		dt = 0.0
	_step_effects(dt, delta)
	if figures != null:
		figures.sync(now)
		if int(now * 4.0) != int(_clock_last * 4.0):
			figures.prune(now)
	_clock_last = now
	_step_projectiles(now)
	_tick_camera(delta)
	## glyphs and auras follow the state at most every GLYPH_INTERVAL of real time while playing (the why
	## panel's rule), at once when paused
	if _glyphs_dirty_3d and (not player.is_playing() or _real - _glyph_at >= GLYPH_INTERVAL):
		_refresh_glyph_cache()
	overlay.queue_redraw()
	_sample_frame(delta)



## The quality ladder (3D_DIRECTION 3.4): after LADDER_SECONDS under LADDER_FPS, one rung down: SSAO and
## shadows (world_view.gd), then the figures' shadows, then the woods as primitives; never back up by itself.
func _sample_frame(delta: float) -> void:
	if not is_inside_tree() or _vp == null or _vp.render_target_update_mode == SubViewport.UPDATE_DISABLED:
		return
	_frame_ms.append(delta * 1000.0)
	if _frame_ms.size() > 600:
		_frame_ms.pop_front()
	if not auto_quality or quality >= MAX_RUNG:
		return
	if delta > 1.0 / LADDER_FPS:
		_slow += delta
		if _slow >= LADDER_SECONDS:
			_slow = 0.0
			set_quality(quality + 1)
	else:
		_slow = maxf(0.0, _slow - delta * 0.5)


func set_quality(q: int) -> void:
	quality = clampi(q, 0, MAX_RUNG)
	if wv == null:
		return
	wv.set_quality(mini(quality, 3) if quality < 4 else 3)
	figures.set_shadows(quality < 3)
	if not plan.is_empty():
		_woods_near(plan["site"], _footprint_radius() + WOODS_NEAR)
	wv.sun.shadow_enabled = quality < 4


## What the stage draws and how fast: {"fps", "p95_ms", "max_ms", "draw_calls", "primitives", "figures",
## "groups", "rung"} (draw calls and primitives are the renderer's whole frame).
func perf_stats() -> Dictionary:
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var p95: float = sorted[int(sorted.size() * 0.95)] if not sorted.is_empty() else 0.0
	var mean := 0.0
	for v in sorted:
		mean += float(v)
	mean = mean / maxf(1.0, float(sorted.size()))
	var ds: Dictionary = figures.draw_stats() if figures != null else {"groups": 0, "figures": 0}
	return {"fps": 1000.0 / maxf(mean, 0.001), "p95_ms": p95, "max_ms": sorted[-1] if not sorted.is_empty() else 0.0,
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"figures": ds["figures"], "groups": ds["groups"], "rung": quality}


func reset_perf() -> void:
	_frame_ms.clear()


# --- beats -----------------------------------------------------------------------------------------------

func _on_beat(b: Dictionary, st: Dictionary) -> void:
	if plan.is_empty():
		return
	_play_sound(b)
	var now := float(b.t)
	match String(b.kind):
		"deploy":
			if not reduced_motion:
				for i in figures.figs.size():
					if int(figures.figs[i]["tier"]) == 0 and int(figures.figs[i]["fid"]) >= 0:
						figures.add_motion(i, {"kind": "deploy", "t0": now, "dur": BattlePlayer.DEPLOY * 0.8})
		"round_start":
			banner_label.text = String(b.data.banner)
			banner_label.visible = true
			banner_label.modulate.a = 1.0
			_banner_t = 0.0
			_update_round_label(st)
			_glyphs_dirty = true
			_glyphs_dirty_3d = true
		"attack_started":
			_attack_started(b)
		"attack_landed":
			_attack_landed(b, st)
		"wound":
			_bars_dirty = true
			_glyphs_dirty_3d = true
		"death":
			var i: int = figures.index_of(int(b.fighter))
			figures.set_hold(i, "fallen")
			figures.add_motion(i, {"kind": "topple", "t0": now, "dur": Figures.TOPPLE})
			var ends: Array = _ends_home(int(b.fighter))
			if not ends.is_empty():
				_add_fx({"kind": "dust", "at": ends[0], "life": DUST_LIFE, "r": 1.0})
			if b.data.ruler:
				if not ends.is_empty():
					_add_fx({"kind": "burst", "at": (ends[0] as Vector3).lerp(ends[1], 0.55), "life": BURST_LIFE, "r": 1.0})
					_add_fx({"kind": "impact", "at": (ends[0] as Vector3).lerp(ends[1], 0.62), "life": RING_LIFE if reduced_motion else IMPACT_LIFE,
						"big": true, "ring": reduced_motion, "bright": not reduced_motion and _flash.allow(_real)})
				_try_shake(b.data.shake, int(b.event))
			_glyphs_dirty = true
			_glyphs_dirty_3d = true
			_bars_dirty = true
		"heal":
			var ends2: Array = _ends_home(int(b.fighter))
			if not ends2.is_empty():
				_add_fx({"kind": "heal", "at": ends2[0], "life": HEAL_LIFE, "r": 1.0})
				_add_number((ends2[1] as Vector3), "+%d hp" % int(b.data.healed), UiPalette.POSITIVE, _number_size(false))
			_bars_dirty = true
			_glyphs_dirty_3d = true
		"harvest":
			var side_name := String(_log.sides[int(b.side)].name)
			toast_label.text = "%s: %s takes %d gold from the %d enemy fighters lost." % [RulerRules.mandate_name(AutoBattleResolver.RED_HARVEST),
				side_name, int(b.data.gold), int(b.data.fighters)]
			toast_label.visible = true
			_toast_t = 0.0
		"morale":
			var si := int(b.side)
			_held_by[si] = int(b.data.held_by) if b.data.result == "held" else -1
			var words := {"holds": "Morale check: holds", "breaks": "Morale check: breaks", "held": "Morale check: held by Iron Discipline"}
			var change: Dictionary = b.data.change
			var text := String(words.get(String(b.data.result), ""))
			if not change.is_empty():
				text = "%s. %s" % [String(change.text), text]
			_show_tag(si, text)
			bars[_slot_of_side(si)].set_strength(player.strength(si), true)
			_glyphs_dirty = true
			_glyphs_dirty_3d = true
			_bars_dirty = true
			## a lowering aura sends a wave out at each morale check (not with reduced motion)
			if not reduced_motion:
				for a in _auras:
					if String(a["kind"]) == "aura_down" and int(_log.fighters[int(a["fid"])].side) != si:
						var e3: Array = _ends_home(int(a["fid"]))
						if not e3.is_empty():
							_add_fx({"kind": "wave", "at": e3[0], "life": WAVE_LIFE, "r": 1.0, "side": int(_log.fighters[int(a["fid"])].side)})
		"caption":
			_set_caption(b.data.lines)
		"rout":
			var dur := BattlePlayer.ROUT
			for fid in b.data.fled:
				var i2: int = figures.index_of(int(fid))
				if i2 < 0:
					continue
				_rout_figure(i2, now, dur)
			for i3 in figures.extras_of(int(b.side)):
				_rout_figure(i3, now, dur)
			_bars_dirty = true
			_glyphs_dirty_3d = true
			_show_tag(int(b.side), "%s broke and fled." % String(_log.sides[int(b.side)].name))
		"destroyed":
			for i4 in figures.extras_of(int(b.side)):
				figures.set_hold(i4, "gone")
				figures.add_motion(i4, {"kind": "fade", "t0": now, "dur": Figures.FADE})
			_bars_dirty = true
			_glyphs_dirty_3d = true
			_show_tag(int(b.side), "No one of %s is left standing." % String(_log.sides[int(b.side)].name))
		"moment":
			toast_label.text = String(b.data.text)
			toast_label.visible = true
			_toast_t = 0.0
			if not _focus_pending.is_empty() and int(_focus_pending.get("event", -2)) == int(b.data.get("event", -1)) \
					and String(_focus_pending.get("kind", "")) == String(b.data.get("kind", "")):
				_focus_pending = {}
		"end":
			_update_round_label(st)
			var w := int(b.data.winner)
			if w >= 0:
				for i5 in figures.figs.size():
					var f: Dictionary = figures.figs[i5]
					if int(f["side"]) != w or String(f["hold"]) != "stand":
						continue
					if int(f["fid"]) >= 0 and not st.fighters[int(f["fid"])].alive:
						continue
					if b.data.how == "mutual":
						## a mutual rout: the winner's fleeing figures stop and come back
						f["motions"] = []
					figures.add_motion(i5, {"kind": "cheer", "t0": now + 0.15, "dur": Figures.CHEER})
				if b.data.how == "mutual":
					for fid2 in _log.sides[w].fighters:
						var fs2: Dictionary = st.fighters[int(fid2)]
						if fs2.alive and not fs2.lost:
							figures.set_hold(figures.index_of(int(fid2)), "stand")
							figures.figs[figures.index_of(int(fid2))]["motions"] = []
					for i7 in figures.extras_of(w):
						figures.set_hold(i7, "stand")
						figures.figs[i7]["motions"] = []
			_bars_dirty = true
			_glyphs_dirty_3d = true
		"feast":
			for h in b.data.healed:
				var e4: Array = _ends_home(int(h[0]))
				if not e4.is_empty():
					_add_fx({"kind": "heal", "at": e4[0], "life": HEAL_LIFE, "r": 1.0})
					_add_number(e4[1], "+%d hp" % (int(h[2]) - int(h[1])), UiPalette.POSITIVE, _number_size(false))
			_bars_dirty = true
			_glyphs_dirty_3d = true
		"aftermath":
			for fid3 in b.data.lost:
				var i6: int = figures.index_of(int(fid3))
				if i6 >= 0 and String(figures.figs[i6]["hold"]) == "stand":
					figures.set_hold(i6, "gone")
					figures.add_motion(i6, {"kind": "fade", "t0": now, "dur": Figures.FADE})
			var loser_out := []
			for si2 in _log.sides.size():
				loser_out.append(int(st.winner) >= 0 and si2 != int(st.winner))
			for si3 in _log.sides.size():
				if loser_out[si3]:
					for i8 in figures.extras_of(si3):
						if String(figures.figs[i8]["hold"]) == "stand":
							figures.set_hold(i8, "gone")
							figures.add_motion(i8, {"kind": "fade", "t0": now, "dur": Figures.FADE})
			_glyphs_dirty_3d = true
		"result":
			_show_end_card()


func _rout_figure(i: int, now: float, dur: float) -> void:
	var f: Dictionary = figures.figs[i]
	if String(f["hold"]) != "stand":
		return
	figures.set_hold(i, "gone")
	if reduced_motion:
		figures.add_motion(i, {"kind": "fade", "t0": now, "dur": Figures.FADE})
	else:
		var home: Vector2 = f["home"]
		var back: Vector2 = f["back"]
		var away: Vector2 = (back - home)
		var axis: Vector2 = plan["axis"]
		## straight back along the battle's axis, from where it stands
		var depth: float = absf(away.dot(axis))
		var to: Vector2 = home + axis * signf(away.dot(axis)) * depth
		figures.add_motion(i, {"kind": "rout", "t0": now, "dur": dur, "from": home, "to": to})


func _attack_started(b: Dictionary) -> void:
	var ia: int = figures.index_of(int(b.fighter))
	var it: int = figures.index_of(int(b.target))
	if ia < 0 or it < 0:
		return
	var now := float(b.t)
	var proj := String(b.data.projectile)
	var to: Vector2 = figures.figs[it]["home"]
	if proj.is_empty():
		figures.add_motion(ia, {"kind": "lunge", "t0": now, "dur": Figures.LUNGE_OUT + Figures.LUNGE_BACK, "to": to})
		if not reduced_motion:
			lunges_started += 1
	elif proj == "dive":
		figures.add_motion(ia, {"kind": "dive", "t0": now, "dur": float(b.data.delay) + Figures.DIVE_BACK, "to": to, "flight": float(b.data.delay),
			"short": maxf(2.5, float(figures.figs[it]["len"]) * 0.5)})
		if not reduced_motion:
			lunges_started += 1
		else:
			## with reduced motion a dive plays in place: a gilt streak carries the attack instead
			_spawn_projectile("arcane", ia, it, now, float(b.data.delay), 0.0, bool(b.data.hit))
	else:
		figures.add_motion(ia, {"kind": "shoot", "t0": now, "dur": Figures.STRIKE_HOLD})
		_spawn_projectile(proj, ia, it, now, float(b.data.delay), 0.0 if reduced_motion else float(b.data.arc), bool(b.data.hit))


func _attack_landed(b: Dictionary, st: Dictionary) -> void:
	var ia: int = figures.index_of(int(b.fighter))
	var it: int = figures.index_of(int(b.target))
	if it < 0:
		return
	var tfid := int(b.target)
	var si := int(_log.fighters[tfid].side)
	var fs: Dictionary = st.fighters[tfid]
	var shown: bool = not _massed[si] or tfid == _hovered or tfid == _selected
	var ends: Array = _ends_home(tfid)
	if ends.is_empty():
		return
	var upper: Vector3 = (ends[0] as Vector3).lerp(ends[1], 0.62)
	var now := float(b.t)
	if b.data.hit:
		var away := Vector2.ZERO
		if ia >= 0:
			away = ((figures.figs[it]["home"] as Vector2) - (figures.figs[ia]["home"] as Vector2)).normalized()
		figures.add_motion(it, {"kind": "recoil", "t0": now, "dur": Figures.RECOIL, "away": away})
		var big: bool = b.data.big
		var kills := int(fs.pending) >= int(fs.hp) and int(fs.pending) - int(b.data.damage) < int(fs.hp)
		var bright: bool = not reduced_motion and _flash.allow(_real)
		_add_fx({"kind": "impact", "at": upper, "life": RING_LIFE if reduced_motion else IMPACT_LIFE, "big": big, "ring": reduced_motion,
			"bright": bright})
		if int(b.data.get("iron_hide", 0)) < 0:
			_add_fx({"kind": "sparks", "at": upper, "life": SPARK_LIFE, "r": 1.0, "seed": int(b.event)})
		if shown or big or kills:
			_add_number(ends[1], str(int(b.data.damage)), UiPalette.TEXT_PRIMARY, _number_size(big))
			if int(b.data.get("iron_hide", 0)) < 0:
				_add_number(ends[1], "%d" % int(b.data.iron_hide), UiPalette.TEXT_SECONDARY, maxi(12, _number_size(false) - 6), Vector2(24, 4))
		_try_shake(b.data.shake, int(b.event))
		_bars_dirty = true
		_glyphs_dirty_3d = true
	elif shown:
		_add_number(ends[1], "miss", UiPalette.TEXT_SECONDARY, maxi(12, int(round(MISS_SIZE * _scale()))))


## A fighter's feet and head where it stands in its place (effects anchor there), world.
func _ends_home(fid: int) -> Array:
	var i: int = figures.index_of(fid)
	if i < 0:
		return []
	var f: Dictionary = figures.figs[i]
	var p: Vector2 = f["home"]
	return [Vector3(p.x, float(f["y"]), p.y), Vector3(p.x, float(f["y"]) + float(f["h"]), p.y)]


func _on_seeked(st: Dictionary) -> void:
	super._on_seeked(st)
	_fx.clear()
	_numbers.clear()
	_proj.clear()
	_shake_cam = {}
	if figures == null or plan.is_empty():
		return
	var out_sides := []
	for si in _log.sides.size():
		var so: Dictionary = st.sides[si]
		out_sides.append(String(so.out) != "" or (int(st.winner) >= 0 and si != int(st.winner) and _aftermath_done(st)))
	figures.snap(st, out_sides)
	figures.sync(player.time(), true)
	_step_projectiles(player.time())
	_glyphs_dirty_3d = true
	_refresh_glyph_cache()
	## a key-moment jump (the playhead now sits just before a moment's beat): frame its camera hint
	var nb := player.next_beat()
	var beats := player.beats()
	var hit := {}
	for k in range(nb, mini(nb + 4000, beats.size())):
		var bk: Dictionary = beats[k]
		if float(bk.t) > player.time() + BattlePlayer.LEAD_IN + 0.01:
			break
		if bk.kind == "moment":
			hit = bk.data
			break
	if not hit.is_empty() and absf(player.moment_time(hit) - BattlePlayer.LEAD_IN - player.time()) < 0.02:
		_focus_pending = {"event": int(hit.get("event", -1)), "kind": String(hit.get("kind", ""))}
		focus_moment(hit)
	elif _focus_left >= 0.0:
		_focus_left = -1.0
		if not _user_rig:
			_move_to(goal)
	overlay.queue_redraw()


func _aftermath_done(st: Dictionary) -> bool:
	return int(st.event) > BattleLog.find_event(_log, "aftermath") and BattleLog.find_event(_log, "aftermath") >= 0


# --- projectiles (3D) ---------------------------------------------------------------------------------

func _spawn_projectile(kind: String, ia: int, it: int, t0: float, life: float, arc: float, hit: bool) -> void:
	if _proj.size() >= BattleFx.MAX_PROJECTILES:
		return
	var ea: Array = _ends_home(int(figures.figs[ia]["fid"]))
	var et: Array = _ends_home(int(figures.figs[it]["fid"]))
	if ea.is_empty() or et.is_empty():
		return
	var from: Vector3 = (ea[0] as Vector3).lerp(ea[1], 0.7)
	var to: Vector3 = (et[0] as Vector3).lerp(et[1], 0.6)
	if not hit:
		var d: Vector3 = (to - from)
		d.y = 0.0
		to = Vector3(to.x, (et[0] as Vector3).y + 0.2, to.z) + d.normalized() * MISS_OVERSHOOT
	_proj.append({"kind": kind, "from": from, "to": to, "t0": t0, "life": maxf(0.05, life), "arc": arc, "hit": hit, "dusted": false})


static func projectile_point(p: Dictionary, u: float) -> Vector3:
	var a: Vector3 = p["from"]
	var b: Vector3 = p["to"]
	var apex: float = float(p["arc"]) * a.distance_to(b)
	return a.lerp(b, u) + Vector3.UP * (4.0 * apex * u * (1.0 - u))


func _step_projectiles(now: float) -> void:
	if _proj_mm.is_empty():
		return
	var counts := {"bolt": 0, "javelin": 0, "arcane": 0}
	var keep := []
	for p in _proj:
		var u: float = (now - float(p["t0"])) / float(p["life"])
		if u >= 1.0:
			if not bool(p["hit"]) and not bool(p["dusted"]):
				p["dusted"] = true
				_add_fx({"kind": "dust", "at": p["to"], "life": DUST_LIFE, "r": 0.7})
			continue
		keep.append(p)
		if u < 0.0:
			continue
		var kind := String(p["kind"])
		var mi: MultiMeshInstance3D = _proj_mm.get(kind)
		if mi == null:
			continue
		var pos := projectile_point(p, u)
		var ahead := projectile_point(p, minf(u + 0.02, 1.0)) - pos
		if ahead.length() < 0.001:
			ahead = (p["to"] as Vector3) - (p["from"] as Vector3)
		var basis := Basis.looking_at(ahead.normalized(), Vector3.UP if absf(ahead.normalized().y) < 0.98 else Vector3.FORWARD)
		var n: int = counts[kind]
		if n < mi.multimesh.instance_count:
			mi.multimesh.set_instance_transform(n, Transform3D(basis, pos))
			counts[kind] = n + 1
	_proj = keep
	for kind in counts.keys():
		var mi2: MultiMeshInstance3D = _proj_mm[kind]
		mi2.multimesh.visible_instance_count = int(counts[kind])
		mi2.visible = int(counts[kind]) > 0


## A projectile's mesh (3D_DIRECTION 7.5: code meshes with trails): a bolt, a javelin or the Regent's arcane
## bolt, its head at the origin, flying toward -Z, with a fading trail behind it (vertex colours, alpha).
static func projectile_mesh(kind: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var head := Color("#2A231C")
	var trail := Color(1.0, 0.98, 0.9, 0.85)
	var length := 2.6
	var thick := 0.16
	var trail_len := 6.0
	match kind:
		"javelin":
			head = Color("#8A6A4C")
			length = 5.2
			thick = 0.2
			trail_len = 5.0
		"arcane":
			head = Color("#F4D47A")
			trail = Color("#E6B84E")
			trail.a = 0.9
			length = 1.4
			thick = 0.7
			trail_len = 7.0
	## the shaft (a thin cross of two quads) and, for the arcane bolt, a glowing diamond
	for rot in [0.0, PI * 0.5]:
		var side := Vector3(cos(rot), sin(rot), 0.0) * thick
		_quad(st, Vector3(0, 0, 0) - side, Vector3(0, 0, 0) + side, Vector3(0, 0, length) + side, Vector3(0, 0, length) - side, head, head)
		## the trail: wide at the head, nothing at its end
		var ts := side * 1.6
		_quad(st, Vector3(0, 0, length * 0.3) - ts, Vector3(0, 0, length * 0.3) + ts, Vector3(0, 0, length + trail_len), Vector3(0, 0, length + trail_len),
			trail, Color(trail, 0.0))
	if kind == "javelin":
		var tip := Color("#C9D2DC")
		for rot2 in [0.0, PI * 0.5]:
			var s2 := Vector3(cos(rot2), sin(rot2), 0.0) * 0.32
			_quad(st, Vector3(0, 0, -0.9), Vector3(0, 0, -0.9), Vector3(0, 0, 0.2) + s2, Vector3(0, 0, 0.2) - s2, tip, tip)
	st.generate_normals()
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, near_col: Color, far_col: Color) -> void:
	for v in [[a, near_col], [b, near_col], [c, far_col], [a, near_col], [c, far_col], [d, far_col]]:
		st.set_color(v[1])
		st.add_vertex(v[0])


func _projectile_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m


# --- the 2D effects and numbers -------------------------------------------------------------------------

func _add_fx(e: Dictionary) -> void:
	if _fx.size() >= BattleFx.MAX_IMPACTS * 2:
		return
	e["age"] = 0.0
	e["frames"] = 0
	_fx.append(e)


func _add_number(at: Vector3, text: String, col: Color, font_size: int, nudge: Vector2 = Vector2.ZERO) -> void:
	if _numbers.size() >= BattleFx.MAX_NUMBERS:
		return
	_numbers.append({"at": at, "text": text, "color": col, "size": font_size, "age": 0.0, "life": NUMBER_LIFE, "nudge": nudge})


func _step_effects(dt: float, _real_dt: float) -> void:
	if _fx.is_empty() and _numbers.is_empty():
		return
	var keep := []
	for e in _fx:
		e["frames"] = int(e["frames"]) + 1
		e["age"] = float(e["age"]) + dt
		if float(e["age"]) < float(e["life"]):
			keep.append(e)
	_fx = keep
	var keep2 := []
	for n in _numbers:
		n["age"] = float(n["age"]) + dt
		if float(n["age"]) < float(n["life"]):
			keep2.append(n)
	_numbers = keep2


# --- glyphs and auras ---------------------------------------------------------------------------------

func _refresh_glyph_cache() -> void:
	_glyphs_dirty_3d = false
	_glyph_at = _real
	if player == null:
		return
	var st := player.live_state()
	_glyph_cache = {}
	_auras = []
	for f in _log.fighters:
		var fid := int(f.id)
		var fs: Dictionary = st.fighters[fid]
		if not fs.alive or fs.fled or fs.lost:
			continue
		## a massed side's units (71 war bears' Fury) would carpet the ground and cost a status each: there
		## only commanders and rulers (and the hovered or pinned fighter) show glyphs and aura rings (M3 3.4)
		if _massed[int(f.side)] and f.role == "unit" and fid != _hovered and fid != _selected:
			continue
		var g := _glyphs_for(fid, st)
		if not g.is_empty():
			_glyph_cache[fid] = g
		## the morale it gives while it stands (BattleTimeline.statuses' auras, read off the log)
		var kind := ""
		if f.role == "commander" or f.role == "ruler":
			kind = "aura_up"
		if String(f.trait) == AutoBattleResolver.FURY or int(f.get("ruler", {}).get("dread", 0)) > 0:
			kind = "aura_down" if kind == "" else kind
		if kind != "":
			_auras.append({"fid": fid, "kind": kind})


# --- tab order, hover, selection -------------------------------------------------------------------------

## Tab order (M3 5.3): the screen's left side first, then the right; each side front rank to back line,
## each line file by file.
func _tab_order() -> Array:
	var ids := []
	for f in _log.fighters:
		ids.append(int(f.id))
	var left := int(layout.get("left", 0))
	var slots: Array = plan.get("slots", [])
	if slots.size() != ids.size():
		return BattleSelection.default_order(_log, left)
	ids.sort_custom(func(a, b):
		var sa: Dictionary = slots[a]
		var sb: Dictionary = slots[b]
		var ka := [0 if int(sa.side) == left else 1, int(sa.tier), int(sa.line), int(sa.file), a]
		var kb := [0 if int(sb.side) == left else 1, int(sb.tier), int(sb.line), int(sb.file), b]
		for k in ka.size():
			if ka[k] != kb[k]:
				return ka[k] < kb[k]
		return false)
	return ids


## The fighter under the screen's point `at` (this Control's own coordinates), or -1: a ray from the eye
## against every figure shown (a standing one as an upright cylinder, a fallen one as a low one).
func pick(at: Vector2) -> int:
	if figures == null or rig.is_empty() or plan.is_empty():
		return -1
	var local := at - frame.position - Vector2(0, TOP_H)
	if local.x < 0.0 or local.y < 0.0 or local.x > field_width() or local.y > FIELD_H:
		return -1
	var r := Cam.ray(wv.rig, _view, local * _px)
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	var now := player.time() if player != null else 0.0
	var best := -1
	var best_t := INF
	for i in figures.n_fighters:
		var e: Array = figures.ends_at(i, now)
		if e.is_empty():
			continue
		var f: Dictionary = figures.figs[i]
		var foot: Vector3 = e[0]
		var top: float = (e[1] as Vector3).y
		var rad: float = maxf(1.6, minf(float(f["w"]), float(f["len"])) * 0.45)
		if String(f["hold"]) == "fallen":
			rad = maxf(2.0, float(f["len"]) * 0.45)
		## the ray's closest approach to the figure's vertical axis
		var dh := Vector2(d.x, d.z)
		var oh := Vector2(o.x - foot.x, o.z - foot.z)
		var a := dh.dot(dh)
		if a < 1e-6:
			continue
		var tc := -oh.dot(dh) / a
		var closest := (oh + dh * tc).length()
		if closest > rad:
			continue
		var y := o.y + d.y * tc
		if y < foot.y - 0.5 or y > top + 0.8:
			## try where the ray crosses the head and the feet levels instead (looking down on it)
			var t1 := (top - o.y) / d.y if absf(d.y) > 1e-5 else INF
			var p1 := Vector2(o.x + d.x * t1 - foot.x, o.z + d.z * t1 - foot.z)
			if p1.length() > rad:
				continue
			tc = t1
		if tc > 0.0 and tc < best_t:
			best_t = tc
			best = int(f["fid"])
	return best


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null:
		if _drag >= 0:
			var dpx: Vector2 = mm.relative
			if rig.is_empty():
				return
			_user_rig = true
			_focus_left = -1.0
			_move = {}
			if _drag == MOUSE_BUTTON_RIGHT:
				rig["yaw"] = float(rig["yaw"]) - dpx.x * 0.3
				rig["pitch"] = clampf(float(rig["pitch"]) + dpx.y * 0.2, 20.0, 82.0)
			else:
				var wpp: float = float(rig["span"]) / FIELD_H
				var right := Cam.right_of(float(rig["yaw"]))
				var fwd := Vector2(-sin(deg_to_rad(float(rig["yaw"]))), -cos(deg_to_rad(float(rig["yaw"]))))
				var sh: Vector2 = right * (-dpx.x * wpp) + fwd * (dpx.y * wpp / maxf(sin(deg_to_rad(float(rig["pitch"]))), 0.3))
				rig["target"] = (rig["target"] as Vector3) + Vector3(sh.x, 0.0, sh.y)
			_apply_rig()
			return
		_set_hover(pick(mm.position))
		return
	var mb := event as InputEventMouseButton
	if mb == null or player == null:
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
		if mb.pressed:
			_drag = mb.button_index
			_drag_from = mb.position
		elif _drag == mb.button_index:
			_drag = -1
		accept_event()
		return
	if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		if rig.is_empty():
			return
		_user_rig = true
		_focus_left = -1.0
		_move = {}
		rig["span"] = clampf(float(rig["span"]) * (0.88 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.88), 18.0, 900.0)
		_apply_rig()
		accept_event()
		return
	if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var fid := pick(mb.position)
		if fid >= 0:
			selection.toggle(fid)
			if selection.selected >= 0 and not _why_open:
				controls.set_why(true, false)
		else:
			var at := mb.position - frame.position
			if Rect2(Vector2(0, TOP_H), Vector2(field_width(), FIELD_H)).has_point(at):
				selection.clear()


func _set_hover(fid: int) -> void:
	if fid == _hovered:
		return
	_hovered = fid
	_glyphs_dirty_3d = true
	overlay.queue_redraw()


func _get_tooltip(at_position: Vector2) -> String:
	var fid := pick(at_position)
	if fid < 0 or player == null:
		return ""
	return fighter_tooltip(fid)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or player == null:
		return
	if CodexLink.is_open_key(event):
		var key := ""
		if _hovered >= 0:
			key = BattleExplain.fighter_codex(_log.fighters[_hovered])
		if key.is_empty() and is_inside_tree():
			key = CodexLink.key_at(get_viewport().gui_get_hovered_control())
		if not key.is_empty():
			codex_requested.emit(key)
			_handled()
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_R:
			if not end_card.visible:
				return
			_watch_again()
		KEY_ESCAPE:
			if legend.visible:
				controls.set_legend(false)
			else:
				close()
		_:
			if not controls.handle_key(event):
				return
	_handled()


# --- the why panel and width -----------------------------------------------------------------------------

func _set_why_open(on: bool) -> void:
	_why_open = on
	_apply_width()
	if on:
		why_panel.refresh()
	if not plan.is_empty():
		goal = _frame_all()
		if not _user_rig and _focus_left < 0.0:
			_move_to(goal)


func _apply_width() -> void:
	super._apply_width()
	if overlay != null:
		overlay.size = Vector2(field_width(), FIELD_H)


# --- texts ------------------------------------------------------------------------------------------------

## Every text on screen or in a tooltip a player can reach now, the fighters' hover texts and the stage's own
## plates included (the no-raw-ids test).
func visible_texts() -> Array:
	var out := super.visible_texts()
	if player != null and not _log.is_empty():
		for f in _log.fighters:
			out.append(fighter_tooltip(int(f.id)))
		out.append_array(overlay_texts())
	return out


## The words the stage draws over the land now: ruler plates, numbers, the camera hint.
func overlay_texts() -> Array:
	var out := [CAMERA_HINT]
	if player == null:
		return out
	var st := player.live_state()
	for f in _log.fighters:
		if f.role == "ruler":
			out.append(_ruler_plate(int(f.id), st))
	for n in _numbers:
		out.append(String(n["text"]))
	return out


func _ruler_plate(fid: int, st: Dictionary) -> String:
	var f: Dictionary = _log.fighters[fid]
	return "%s · %d/%d" % [String(f.name), int(st.fighters[fid].hp), int(f.max_hp)]


# --- the overlay's drawing ------------------------------------------------------------------------------

## View pixels to the overlay's own coordinates (both are the field's).
func _to_overlay(view_px: Vector2) -> Vector2:
	return view_px / _px


func _proj_overlay(p: Vector3) -> Vector2:
	var s := Cam.project(wv.rig, _view, p, _xf)
	if s.x < -90000.0:
		return Vector2(-99999, -99999)
	return _to_overlay(s)


## Screen pixels per world unit at `p` (an effect's size there).
func _px_per_unit(p: Vector3) -> float:
	var a := _proj_overlay(p)
	var b := _proj_overlay(p + Vector3.UP)
	return absf(a.y - b.y) if a.x > -90000.0 and b.x > -90000.0 else 1.0


func _draw_overlay(ci: CanvasItem) -> void:
	if player == null or figures == null or plan.is_empty() or wv == null:
		return
	_xf = Cam.xform_of(wv.rig)
	var st := player.live_state()
	var now := player.time()
	var font := (ci as Control).get_theme_default_font()
	## ground rings: auras, then the hovered and the pinned fighter
	for a in _auras:
		var fid := int(a["fid"])
		var i: int = figures.index_of(fid)
		var e: Array = figures.ends_at(i, now)
		if e.is_empty():
			continue
		var col: Color = _side_colours[int(_log.fighters[fid].side)]
		var big: bool = _log.fighters[fid].role != "unit"
		draw_ring(ci, _ground_ring((e[0] as Vector3), aura_radius(fid)), col, 2.5 if big else 1.5, true)
	for k in [[_hovered, UiPalette.TEXT_PRIMARY, 2.0], [_selected, Color.WHITE, 3.0]]:
		var fid2: int = k[0]
		if fid2 < 0:
			continue
		var e2: Array = figures.ends_at(figures.index_of(fid2), now)
		if e2.is_empty():
			continue
		var rad: float = maxf(2.6, minf(float(figures.figs[fid2]["w"]), float(figures.figs[fid2]["len"])) * 0.6)
		draw_ring(ci, _ground_ring(e2[0], rad), k[1], float(k[2]), true)
	## waves, dust, heals (under the plates)
	for fx in _fx:
		var kind := String(fx["kind"])
		if kind in ["dust", "heal", "wave"]:
			var at := _proj_overlay(fx["at"])
			if at.x < -90000.0:
				continue
			var ppu := _px_per_unit(fx["at"])
			var k2: float = float(fx["age"]) / float(fx["life"])
			match kind:
				"dust":
					BattleEffects.draw_dust(ci, {"pos": at, "s": clampf(ppu * 0.32 * float(fx.get("r", 1.0)), 0.4, 2.2), "age": fx["age"], "life": fx["life"]})
				"heal":
					draw_heal_rise(ci, at, clampf(ppu * 3.0, 10.0, 46.0), k2)
				"wave":
					var col2: Color = _side_colours[int(fx.get("side", 0))]
					draw_ring(ci, _ground_ring(fx["at"], 5.0 + 13.0 * k2), Color(col2, 1.0 - k2), 2.0, true)
	## plates and glyphs
	var plate_list := []
	for f in _log.fighters:
		var fid3 := int(f.id)
		var fs: Dictionary = st.fighters[fid3]
		if not fs.alive or fs.fled or fs.lost:
			continue
		var si := int(f.side)
		var hurt: bool = int(fs.hp) < int(f.max_hp) or int(fs.pending) > 0
		var show: bool = not _massed[si] or hurt or f.role != "unit" or fid3 == _hovered or fid3 == _selected
		if not show:
			continue
		var e3: Array = figures.ends_at(figures.index_of(fid3), now)
		if e3.is_empty():
			continue
		var head := _proj_overlay((e3[1] as Vector3) + Vector3.UP * 1.0)
		if head.x < -90000.0:
			continue
		plate_list.append([head, fid3, f, fs])
	plate_list.sort_custom(func(a, b): return a[0].y < b[0].y)
	for pl in plate_list:
		var head2: Vector2 = pl[0]
		var fid4: int = pl[1]
		var f2: Dictionary = pl[2]
		var fs2: Dictionary = pl[3]
		var bar := Rect2(head2 - Vector2(PLATE_W * 0.5, PLATE_H), Vector2(PLATE_W, PLATE_H))
		BattleCard.draw_hp_bar(ci, bar, int(fs2.hp), int(f2.max_hp), int(fs2.pending))
		if f2.role == "ruler":
			BattleCard.draw_plate(ci, font, Rect2(bar.position - Vector2(60, 28), Vector2(PLATE_W + 120, 24)), _ruler_plate(fid4, st), 1.0, true, -4.0)
		elif f2.role == "commander":
			BattleCard.draw_standard(ci, bar.position + Vector2(-5, PLATE_H), 14.0)
		var gl: Array = _glyph_cache.get(fid4, [])
		for gk in gl.size():
			BattleCard.draw_glyph(ci, String(gl[gk]), bar.end + Vector2(9 + gk * 15, -2), 13.0)
	## impacts, sparks, bursts (over the plates)
	for fx2 in _fx:
		var kind2 := String(fx2["kind"])
		if not (kind2 in ["impact", "sparks", "burst"]):
			continue
		var at2 := _proj_overlay(fx2["at"])
		if at2.x < -90000.0:
			continue
		var ppu2 := _px_per_unit(fx2["at"])
		var k3: float = float(fx2["age"]) / float(fx2["life"])
		match kind2:
			"impact":
				var big: bool = fx2.get("big", false)
				var item := {"pos": at2, "r": clampf(ppu2 * 2.4, 9.0, 40.0) * (1.6 if big else 1.0), "ring": bool(fx2.get("ring", false)),
					"bright": bool(fx2.get("bright", false)), "frames": int(fx2["frames"]), "age": fx2["age"], "life": fx2["life"]}
				if BattleEffects.draw_impact(ci, item):
					bright_frames_drawn += 1
			"sparks":
				draw_sparks(ci, at2, clampf(ppu2 * 2.2, 10.0, 36.0), k3, int(fx2.get("seed", 0)))
			"burst":
				draw_burst(ci, at2, clampf(ppu2 * 5.0, 24.0, 110.0), k3)
	## a Wings dive's gilt streak behind the diving figure
	for i5 in figures.n_fighters:
		var f5: Dictionary = figures.figs[i5]
		for m in f5["motions"]:
			if String(m["kind"]) != "dive" or reduced_motion:
				continue
			var t5: float = now - float(m["t0"])
			if t5 < 0.0 or t5 > float(m["flight"]) + 0.1:
				continue
			var pts := PackedVector2Array()
			for s in 7:
				var tt: float = clampf(t5 - 0.16 + s * 0.026, 0.0, float(m["flight"]))
				var pp: Dictionary = _dive_point(i5, float(m["t0"]) + tt)
				var sp2 := _proj_overlay(Vector3((pp["pos"] as Vector2).x, float(pp["y"]) + float(f5["h"]) * 0.5, (pp["pos"] as Vector2).y))
				if sp2.x > -90000.0:
					pts.append(sp2)
			if pts.size() >= 2:
				draw_streak(ci, pts, UiPalette.GILT)
	## numbers last, on top of everything
	for n in _numbers:
		var at3 := _proj_overlay(n["at"])
		if at3.x < -90000.0:
			continue
		BattleEffects.draw_number(ci, font, {"pos": at3 + Vector2(0, -12) + (n["nudge"] as Vector2), "text": n["text"], "color": n["color"],
			"size": n["size"], "age": n["age"], "life": n["life"]})
	## the camera's keys, bottom right of the field
	draw_camera_hint(ci, font, Vector2((ci as Control).size.x - 12.0, FIELD_H - 10.0), CAMERA_HINT)


func _dive_point(i: int, t: float) -> Dictionary:
	var p: Dictionary = figures.pose_at(i, t)
	var pos: Vector2 = p["pos"]
	return {"pos": pos, "y": maxf(terrain.height_at(pos), 0.0) + float(p["extra_y"])}


## The radius of fighter `fid`'s aura ring: a little wider than the figure.
func aura_radius(fid: int) -> float:
	var f: Dictionary = figures.figs[fid]
	return maxf(3.6, maxf(float(f["w"]), float(f["len"])) * 0.62)


## A ring of `r` world units round `c` on the land, as overlay points (it follows the slope).
func _ground_ring(c: Vector3, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 25:
		var a := TAU * k / 24.0
		var g := Vector2(c.x + cos(a) * r, c.z + sin(a) * r)
		var p := _proj_overlay(Vector3(g.x, maxf(terrain.height_at(g), c.y - 1.0) + 0.25, g.y))
		if p.x < -90000.0:
			return PackedVector2Array()
		pts.append(p)
	return pts


# --- drawing functions (the stage and its legend share them) -----------------------------------------------

## A ground ring through `pts` in `col`, `width` px, with an ink keyline under it (selection, hover, auras).
static func draw_ring(ci: CanvasItem, pts: PackedVector2Array, col: Color, width: float, keyline: bool) -> void:
	if pts.size() < 3:
		return
	if keyline:
		ci.draw_polyline(pts, Color(UiPalette.KEYLINE_INK, col.a * 0.9), width + 2.0, true)
	ci.draw_polyline(pts, col, width, true)


## Iron Hide's sparks: short bright strokes flying out from `pos` (`k` 0..1 through their life); their
## directions come from `seed` (the event's index), never a random number.
static func draw_sparks(ci: CanvasItem, pos: Vector2, r: float, k: float, seed_index: int = 0) -> void:
	var a := 1.0 - k
	for j in 7:
		var ang := TAU * (j / 7.0) + float(seed_index % 5) * 0.37 - PI * 0.5
		var d := Vector2(cos(ang), sin(ang) * 0.8)
		var p0 := pos + d * r * (0.25 + 0.7 * k)
		var p1 := pos + d * r * (0.55 + 0.9 * k)
		ci.draw_line(p0, p1, Color(UiPalette.KEYLINE_INK, a), 4.0)
		ci.draw_line(p0, p1, Color(1.0, 0.82 - 0.2 * (j % 2), 0.42, a), 2.0)


## A heal's green rise: plus signs climbing from the feet and fading.
static func draw_heal_rise(ci: CanvasItem, pos: Vector2, r: float, k: float) -> void:
	var a := 1.0 - k * k
	for j in 4:
		var x := (j - 1.5) * r * 0.42
		var y := -r * (0.2 + 1.3 * fposmod(k + j * 0.23, 1.0))
		var c := pos + Vector2(x, y)
		var s := r * 0.16
		for rect in [Rect2(c - Vector2(s, s * 0.32), Vector2(s * 2.0, s * 0.64)), Rect2(c - Vector2(s * 0.32, s), Vector2(s * 0.64, s * 2.0))]:
			ci.draw_rect((rect as Rect2).grow(1.5), Color(UiPalette.KEYLINE_INK, a * 0.8))
		for rect2 in [Rect2(c - Vector2(s, s * 0.32), Vector2(s * 2.0, s * 0.64)), Rect2(c - Vector2(s * 0.32, s), Vector2(s * 0.64, s * 2.0))]:
			ci.draw_rect(rect2, Color(UiPalette.POSITIVE, a))


## A ruler's fall: a gilt ring bursting out with short rays (no flash: the slow motion carries it).
static func draw_burst(ci: CanvasItem, pos: Vector2, r: float, k: float) -> void:
	var a := 1.0 - k * k
	var rr := r * (0.3 + 0.7 * sqrt(k))
	ci.draw_arc(pos, rr, 0.0, TAU, 40, Color(UiPalette.KEYLINE_INK, a), 8.0, true)
	ci.draw_arc(pos, rr, 0.0, TAU, 40, Color(UiPalette.GILT, a), 4.5, true)
	for j in 12:
		var ang := TAU * j / 12.0
		var d := Vector2(cos(ang), sin(ang))
		ci.draw_line(pos + d * rr * 1.08, pos + d * rr * 1.32, Color(UiPalette.GILT, a), 2.0)


## A Wings dive's gilt streak along `pts` (oldest first), tapering toward its tail.
static func draw_streak(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	for j in range(1, pts.size()):
		var k := float(j) / float(pts.size() - 1)
		ci.draw_line(pts[j - 1], pts[j], Color(UiPalette.KEYLINE_INK, k * 0.8), 2.0 + 6.0 * k)
		ci.draw_line(pts[j - 1], pts[j], Color(col, k), 1.0 + 4.0 * k)


## The camera's keys as a small chip ending at `right_bottom`.
static func draw_camera_hint(ci: CanvasItem, font: Font, right_bottom: Vector2, text: String) -> void:
	var fs := 12
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var box := Rect2(right_bottom - Vector2(w + 34, 20), Vector2(w + 34, 20))
	ci.draw_rect(box, Color(UiPalette.KEYLINE_INK, 0.62))
	## a little camera: a body and a lens
	var c := box.position + Vector2(13, 10)
	ci.draw_rect(Rect2(c - Vector2(8, 5), Vector2(13, 10)), UiPalette.TEXT_SECONDARY)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(5, -3), c + Vector2(10, -6), c + Vector2(10, 6), c + Vector2(5, 3)]), UiPalette.TEXT_SECONDARY)
	ci.draw_string(font, box.position + Vector2(26, 15), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiPalette.TEXT_PRIMARY)


# --- the legend's rows for the stage's own marks ---------------------------------------------------------

## The 3D stage's own legend rows (BattleLegend row format; overlay_rows() covers the shared 2D marks).
static func stage_rows(seat: int = 0) -> Array:
	var col := UiPalette.seat_color(seat)
	var fig := func(ci: CanvasItem, c: Vector2, h: float, colour: Color, lying: bool):
		## a figure sketched as the land shows it: a body on a base in its side's colour
		var base := PackedVector2Array()
		for k in 17:
			var a := TAU * k / 16.0
			base.append(c + Vector2(cos(a) * h * 0.38, sin(a) * h * 0.12))
		ci.draw_colored_polygon(base, colour)
		ci.draw_polyline(base, UiPalette.KEYLINE_INK, 1.0)
		if lying:
			ci.draw_rect(Rect2(c + Vector2(-h * 0.45, -h * 0.2), Vector2(h * 0.9, h * 0.18)), Color(0.55, 0.55, 0.55))
			return
		ci.draw_rect(Rect2(c + Vector2(-h * 0.14, -h * 0.82), Vector2(h * 0.28, h * 0.62)), Color(0.72, 0.74, 0.78))
		ci.draw_circle(c + Vector2(0, -h * 0.9), h * 0.12, Color(0.9, 0.75, 0.6))
	var proj := func(ci: CanvasItem, r: Rect2, kind: String):
		var a := r.position + Vector2(10, r.size.y * 0.65)
		var b := r.end - Vector2(14, r.size.y * 0.35)
		var mid := (a + b) * 0.5 - Vector2(0, 8 if kind == "javelin" else 3)
		var pts := PackedVector2Array([a, a.lerp(mid, 0.5), mid, mid.lerp(b, 0.5), b])
		draw_streak(ci, pts, UiPalette.GILT if kind == "arcane" else UiPalette.TEXT_PRIMARY)
		var hc := Color("#F4D47A") if kind == "arcane" else (Color("#8A6A4C") if kind == "javelin" else Color("#2A231C"))
		var d := (b - mid).normalized()
		ci.draw_line(b - d * (16.0 if kind == "javelin" else 8.0), b, hc, 4.0 if kind == "arcane" else 2.0)
	return [
		BattleLegend._row("figure3d", "A fighter", "Every fighter stands as its own figure, on a base in its side's colour. Hover it to see what it is doing and why; click it to pin that.",
			"battle_formation", "BattleStage3D.figure_colour", func(ci: CanvasItem, r: Rect2): fig.call(ci, r.get_center() + Vector2(0, 14), 30.0, col, false)),
		BattleLegend._row("ruler3d", "A ruler", "A ruler stands in its rank with a gilt ring on its base, under a name plate with its hit points.", "ruler_in_battle",
			"BattleCard.draw_plate", func(ci: CanvasItem, r: Rect2):
				fig.call(ci, r.get_center() + Vector2(0, 16), 30.0, UiPalette.GILT, false)
				BattleCard.draw_plate(ci, BattleLegend._font(ci), Rect2(r.position + Vector2(0, -2), Vector2(r.size.x, 18)), "King · 18/18", 0.9, true, -4.0)),
		BattleLegend._row("commander3d", "Commander and colours", "The commander stands in the middle of the back line with a standard; the banner bearer and musician beside it are for show and never count.",
			"battle_commanders", "BattleCard.draw_standard", func(ci: CanvasItem, r: Rect2):
				fig.call(ci, r.get_center() + Vector2(0, 14), 28.0, col, false)
				BattleCard.draw_standard(ci, r.get_center() + Vector2(-16, 12), 24.0)),
		BattleLegend._row("ranks3d", "Ranks", "Each side's front rank faces the enemy, the second rank (crossbows) stands behind it and the commander at the back. Places within a rank are only for show.",
			"battle_formation", "BattleStage3D.figure_colour", func(ci: CanvasItem, r: Rect2):
				for k in 3:
					fig.call(ci, r.position + Vector2(20 + k * 30, r.size.y - 6), 18.0 + (4.0 if k == 0 else 0.0), col, false)),
		BattleLegend._row("fallen3d", "Fallen", "A fighter that falls topples and lies where it fell, greyed, so losses can be counted.", "battle_playback",
			"BattleStage3D.figure_colour", func(ci: CanvasItem, r: Rect2): fig.call(ci, r.get_center() + Vector2(0, 10), 30.0, Color(0.5, 0.5, 0.5), true),
			"A fighter that falls lies where it fell, greyed. With reduced motion it lies down at once."),
		BattleLegend._row("lunge3d", "Lunge and strike", "A melee attack: the fighter swings in its strike pose and lunges at its target. Every fighter attacks once a round.",
			"battle_rounds", "BattleStage3D.figure_colour", func(ci: CanvasItem, r: Rect2):
				fig.call(ci, r.get_center() + Vector2(-14, 14), 26.0, col, false)
				_arrow(ci, r.get_center() + Vector2(2, 0), r.get_center() + Vector2(30, 0)),
			"A melee attack. With reduced motion the fighter swings where it stands."),
		BattleLegend._row("dive3d", "Wings dive", "Wings: the fighter leaps over the lines onto its target, leaving a gilt streak, then flies back.", "trait_wings",
			"BattleStage3D.draw_streak", func(ci: CanvasItem, r: Rect2):
				draw_streak(ci, PackedVector2Array([r.position + Vector2(10, r.size.y - 6), r.get_center() + Vector2(-6, -12), r.end - Vector2(14, 10)]), UiPalette.GILT),
			"Wings: with reduced motion the fighter stays put and a gilt bolt carries the attack."),
		BattleLegend._row("rout3d", "Fleeing", "A side that broke: its fighters turn and run for the back of the field and are gone.", "battle_morale", "BattleStage3D.figure_colour",
			func(ci: CanvasItem, r: Rect2):
				fig.call(ci, r.get_center() + Vector2(14, 14), 24.0, Color(col, 0.6), false)
				_arrow(ci, r.get_center() + Vector2(-2, 0), r.get_center() + Vector2(-32, 0)),
			"A side that broke: with reduced motion its fighters fade where they stand."),
		BattleLegend._row("bolt3d", "Bolt", "A Crossbowmen shot (Volley): it flies from the second rank.", "trait_volley", "BattleStage3D.projectile_mesh",
			func(ci: CanvasItem, r: Rect2): proj.call(ci, r, "bolt")),
		BattleLegend._row("javelin3d", "Javelin", "A Fangthrowers throw (Skirmish): it arcs high and can reach past the enemy's front.", "trait_skirmish",
			"BattleStage3D.projectile_mesh", func(ci: CanvasItem, r: Rect2): proj.call(ci, r, "javelin")),
		BattleLegend._row("arcane3d", "Arcane bolt", "The Ever-Regent's gilt bolt.", "ruler_ever_regent", "BattleStage3D.projectile_mesh",
			func(ci: CanvasItem, r: Rect2): proj.call(ci, r, "arcane")),
		BattleLegend._row("impact", "Impact", "A hit landing on its target. It never flashes more than three times a second.", "battle_hit_chance", "BattleEffects.draw_impact",
			func(ci: CanvasItem, r: Rect2): BattleEffects.draw_impact(ci, {"pos": r.get_center(), "r": 13.0, "ring": false, "bright": false, "frames": 9, "age": 0.0, "life": 1.0}),
			"A hit landing. With reduced motion, impacts are a still ring."),
		BattleLegend._row("big_impact", "Big impact", "A big hit: 8 damage or more, such as a charge.", "battle_hit_chance", "BattleEffects.draw_impact",
			func(ci: CanvasItem, r: Rect2): BattleEffects.draw_impact(ci, {"pos": r.get_center(), "r": 19.0, "ring": false, "bright": false, "frames": 9, "age": 0.0, "life": 1.0})),
		BattleLegend._row("ring", "Still ring", "An impact with reduced motion on.", "battle_hit_chance", "BattleEffects.draw_impact",
			func(ci: CanvasItem, r: Rect2): BattleEffects.draw_impact(ci, {"pos": r.get_center(), "r": 16.0, "ring": true, "bright": false, "frames": 0, "age": 0.0, "life": 1.0})),
		BattleLegend._row("dust", "Dust", "A fighter falling, or a missed shot landing.", "battle_playback", "BattleEffects.draw_dust",
			func(ci: CanvasItem, r: Rect2): BattleEffects.draw_dust(ci, {"pos": r.get_center() + Vector2(0, 8), "s": 1.0, "age": 0.15, "life": 0.4})),
		BattleLegend._row("sparks", "Sparks", "Iron Hide turned some of the blow (the small grey \"-1\" beside the number).", "trait_iron_hide", "BattleStage3D.draw_sparks",
			func(ci: CanvasItem, r: Rect2): draw_sparks(ci, r.get_center(), 16.0, 0.35, 1)),
		BattleLegend._row("heal_rise", "Green rise", "Hit points healed: Lifedrinker drinking back damage it dealt, or Feast of Victory after the battle.", "trait_lifedrinker",
			"BattleStage3D.draw_heal_rise", func(ci: CanvasItem, r: Rect2): draw_heal_rise(ci, r.get_center() + Vector2(0, 16), 26.0, 0.3)),
		BattleLegend._row("burst", "Gilt burst", "A ruler falls. The battle slows for a moment so you see it.", "ruler_in_battle", "BattleStage3D.draw_burst",
			func(ci: CanvasItem, r: Rect2): draw_burst(ci, r.get_center(), 22.0, 0.4)),
		BattleLegend._row("select_ring", "White ring", "The pinned fighter (click or Tab); a thin cream ring marks the one under the mouse.", "battle_playback", "BattleStage3D.draw_ring",
			func(ci: CanvasItem, r: Rect2): draw_ring(ci, _ellipse_pts(r.get_center(), Vector2(22, 8)), Color.WHITE, 3.0, true)),
		BattleLegend._row("aura_ring", "Ring in a side's colour", "A morale aura on the ground under its source: ▲ raises its own side's morale, ▼ lowers the enemy's. A ▼ aura sends a wave out at each morale check.",
			"battle_auras", "BattleStage3D.draw_ring", func(ci: CanvasItem, r: Rect2):
				draw_ring(ci, _ellipse_pts(r.get_center() + Vector2(0, 6), Vector2(26, 9)), col, 2.5, true)
				BattleCard.draw_glyph(ci, "aura_up", r.get_center() + Vector2(0, -6), 16.0),
			"A morale aura on the ground under its source: ▲ raises its own side's morale, ▼ lowers the enemy's (no waves with reduced motion)."),
		BattleLegend._row("shake3d", "Camera shake", "Only for a big hit or a fallen ruler, never more than once in three quarters of a second.", "battle_playback",
			"BattleStage3D.shake_offset", func(ci: CanvasItem, r: Rect2):
				BattleEffects.draw_impact(ci, {"pos": r.get_center(), "r": 15.0, "ring": false, "bright": false, "frames": 9, "age": 0.0, "life": 1.0})
				ci.draw_line(r.get_center() + Vector2(-26, -8), r.get_center() + Vector2(-26, 8), UiPalette.TEXT_SECONDARY, 2.0)
				ci.draw_line(r.get_center() + Vector2(26, -8), r.get_center() + Vector2(26, 8), UiPalette.TEXT_SECONDARY, 2.0),
			"The camera never shakes with reduced motion (or with screen shake off)."),
		BattleLegend._row("fort3d", "Fort", "A defended fort stands behind its defenders: only a defender gets its +2 defense. An undefended fort stands empty.", "fort",
			"BattleStage3D.place_fort", func(ci: CanvasItem, r: Rect2):
				var w := Rect2(r.position + Vector2(18, 10), Vector2(r.size.x - 36, r.size.y - 14))
				ci.draw_rect(w, Color(0.62, 0.58, 0.52))
				for k in 5:
					ci.draw_rect(Rect2(w.position + Vector2(k * w.size.x / 5.0 + 2, -6), Vector2(w.size.x / 10.0, 6)), Color(0.62, 0.58, 0.52))
				ci.draw_rect(w, UiPalette.KEYLINE_INK, false, 1.0)),
		BattleLegend._row("camera3d", "Camera", "The camera frames the whole battle. F frames it again; drag with the right button to turn it, the wheel zooms. A key-moment jump frames that moment.",
			"battle_playback", "BattleStage3D.draw_camera_hint", func(ci: CanvasItem, r: Rect2):
				draw_camera_hint(ci, BattleLegend._font(ci), r.end - Vector2(2, 10), "F")),
	]


static func _ellipse_pts(c: Vector2, rad: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 25:
		var a := TAU * k / 24.0
		pts.append(c + Vector2(cos(a) * rad.x, sin(a) * rad.y))
	return pts


static func _arrow(ci: CanvasItem, from: Vector2, to: Vector2) -> void:
	BattleLegend._arrow(ci, from, to)


## A side's colour as its figures' bases wear it (the instance's custom data, linear).
static func figure_colour(seat: int) -> Color:
	return UiPalette.seat_color(seat).srgb_to_linear()


# --- the nodes that draw the land and the overlay -----------------------------------------------------------

## Draws the land's SubViewport into the field, under the 2D.
class World3DView extends Control:
	var stage: Control

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var vp: SubViewport = stage._vp
		if vp != null and stage.player != null:
			draw_texture_rect(vp.get_texture(), Rect2(Vector2.ZERO, size), false)


## The 2D over the land (field coordinates): plates, rings, effects and numbers, one _draw.
class StageOverlay extends Control:
	var stage: Control

	func _draw() -> void:
		stage._draw_overlay(self)
