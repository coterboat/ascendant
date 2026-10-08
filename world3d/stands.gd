## The far-zoom army stands (#125; design/3D_DIRECTION.md 6.1, STYLE_BIBLE.md 8.1): at the strategic zoom, where
## even piece scale leaves a man-sized figure under STAND_IN_PX on screen, every army collapses to a stand that
## reads from there: a base plate in its owner's colour (an ink rim; a ruler's army adds the gilt ring), its
## banner in the owner's colour with the seat emblem, and one figure for each of its three most numerous types.
## The army's count stays its 2D plate, which then rides over the stand. The switch has hysteresis (on under
## STAND_IN_PX, off over STAND_OUT_PX), so a pan never flickers it, and the two blend over BLEND_TIME: the
## figures shrink away as the stands grow in, and back as the camera closes in.
##
## The board drives it (Board3D._camera): step(delta, man_px, px_per_unit, armies) once a frame returns the
## figures' share (armies.gd set_blend). Stands are sized in screen pixels (STYLE_BIBLE.md 8.1: a 28 px base, a
## 32 px banner), so they read at any far zoom. Everything stands where the army's own figures stand (their
## middle), so a stand follows a marching column. Pure reads of armies.gd's entries; it never changes them.
##
## Draw cost: one MultiMesh for the plates, one for the ruler armies' plates, one per figure type, and a banner
## per army; the figures' MultiMeshes are hidden while the stands are full (measured in #125's PR).
extends Node3D

const Models := preload("res://world3d/models.gd")
const Kit := preload("res://world3d/kit.gd")

const STAND_IN_PX := 23.0 ## a man-sized figure shorter than this on screen: the armies become stands
const STAND_OUT_PX := 27.0 ## taller than this: back to the figures
const BLEND_TIME := 0.35 ## seconds of the cross-blend
const PLATE_PX := 16.0 ## the plate's radius on screen (a 32 px base: bible 8.1 asks at least 28)
const BANNER_PX := 38.0 ## the banner's height on screen (bible 8.1: at least 32)
const FIG_PX := 22.0 ## a man-sized stand figure's height on screen; wide or long figures fit the plate instead
const FIG_FIT := 0.78 ## the share of the plate's width a stand figure may take
const MAX_TYPES := 3
const EXTRAS := ["bearer", "musician"]
const MEMORY_COLOUR := Color(0.34, 0.38, 0.47) ## M5-3: a remembered army's stand is grey (and has no banner), as its ghosts are

var wv: Node3D ## world_view.gd
var k := 0.0 ## 0 the figures, 1 the stands
var on := false ## the hysteresis switch
var enabled := true ## false keeps the figures at every zoom (a probe's A/B)
var unit_px := 1.0 ## screen pixels per world unit at the camera's distance now
var stands := {} ## army id -> {"pos": Vector3, "yaw", "types": [type ids], "colour", "emblem", "ruler", "count"}
var _plates: MultiMeshInstance3D
var _ruler_plates: MultiMeshInstance3D
var _figs := {} ## type id -> MultiMeshInstance3D
var _banners := {} ## army id -> Node3D
var _mats := {}
var _sig := "" ## what the stands were last drawn for (step re-reads them only when it changes)


func _init() -> void:
	name = "Stands"
	visible = false


## The switch's next state for a man-sized figure `man_px` tall on screen (pure, with hysteresis).
static func wants_stands(man_px: float, now_on: bool) -> bool:
	return man_px < (STAND_OUT_PX if now_on else STAND_IN_PX)


## One frame: the switch, the blend, and (while any stand shows) where each stands. Returns the figures'
## share, 1 - k, for armies.gd set_blend.
func step(delta: float, man_px: float, px_per_unit: float, armies: Node3D) -> float:
	on = enabled and wants_stands(man_px, on)
	k = move_toward(k, 1.0 if on else 0.0, delta / BLEND_TIME if delta > 0.0 else 1.0)
	unit_px = maxf(px_per_unit, 0.0001)
	visible = k > 0.001
	if visible:
		## re-read only when something changed: the blend, the zoom, the camera's turn, the armies (a new state, a
		## plan) or a playback moving them; an idle whole map costs nothing here
		var sig := "%.4f|%.5f|%.2f|%d|%d|%s|%s" % [k, unit_px, float(wv.rig.get("yaw", 0.0)) if wv != null else 0.0, armies.armies.size(),
			armies.state.get_instance_id() if armies.state != null else 0, armies._plan_key, armies.playing()]
		if sig != _sig or armies.playing():
			_sig = sig
			sync(armies)
	return 1.0 - k


## Snaps the blend (no animation): stands fully on or off.
func snap(stands_on: bool, px_per_unit: float, armies: Node3D) -> float:
	on = stands_on
	k = 1.0 if stands_on else 0.0
	unit_px = maxf(px_per_unit, 0.0001)
	visible = stands_on
	if stands_on:
		sync(armies)
	return 1.0 - k


## Reads every army of `armies` (armies.gd) into its stand and draws them at the current blend.
func sync(armies: Node3D) -> void:
	stands = plan_of(armies)
	_draw_stands()


## Each army's stand, read off armies.gd's entries: army id -> {"pos" (the middle of its standing figures, on
## the ground), "yaw" (its figures' facing), "types" (its most numerous types, at most MAX_TYPES, the extras
## left out; a ruler's army its ruler), "colour", "emblem", "ruler", "count" (its standing figures)}.
static func plan_of(armies: Node3D) -> Dictionary:
	var out := {}
	for id in armies.armies.keys():
		if String(id).begins_with("~"):
			continue
		var e: Dictionary = armies.armies[id]
		var sum := Vector3.ZERO
		var dir := Vector2.ZERO
		var n := 0
		var counts := {}
		var order: Array = []
		for f in e["figs"]:
			if float(f["scale"]) < 0.05 or float(f["fall"]) > 0.5:
				continue
			var p: Vector2 = f["pos"]
			sum += Vector3(p.x, float(f["y"]), p.y)
			dir += Vector2(-sin(float(f["yaw"])), -cos(float(f["yaw"])))
			n += 1
			var t := String(f["type"])
			if EXTRAS.has(t):
				continue
			if not counts.has(t):
				counts[t] = 0
				order.append(t)
			counts[t] = int(counts[t]) + 1
		if n == 0:
			continue
		var first := {}
		for j in order.size():
			first[order[j]] = j
		order.sort_custom(func(a, b): return int(counts[a]) > int(counts[b]) or (int(counts[a]) == int(counts[b]) and int(first[a]) < int(first[b])))
		var facing := dir.normalized() if dir.length() > 0.01 else Vector2(0, -1)
		var memory: bool = bool(e.get("memory", false))
		out[id] = {"pos": sum / float(n), "yaw": atan2(-facing.x, -facing.y), "types": order.slice(0, MAX_TYPES),
			"colour": MEMORY_COLOUR if memory else e["colour"],
			"emblem": int(e["emblem"]), "ruler": bool(e.get("ruler", false)), "count": n, "memory": memory,
			"transformation": String(e.get("transformation", ""))}
	return out


## The world units a stand's plate spans across, and its banner's height, at the current zoom (both in world
## units at k = 1).
func plate_radius() -> float:
	return PLATE_PX / unit_px


func banner_height() -> float:
	return BANNER_PX / unit_px


## Where army `id`'s count plate rides: over its stand's banner (Vector3(-99999) when it has none).
func anchor(id: String) -> Vector3:
	if not stands.has(id):
		return Vector3(-99999, 0, 0)
	var s: Dictionary = stands[id]
	return (s["pos"] as Vector3) + Vector3.UP * ((banner_height() + 8.0 / unit_px) * k)


## The scale of a stand figure of `type_id` (at k = 1): a man-sized figure FIG_PX tall on screen, a wide or
## long one (a knight, a war bear) no wider than FIG_FIT of the plate.
func figure_scale(type_id: String) -> float:
	var m: Mesh = (Models.figure_mesh(type_id, true, "ready") as Dictionary).get("mesh")
	var s := FIG_PX / (Kit.FIG * unit_px)
	if m != null:
		var a: AABB = m.get_aabb()
		var longest := maxf(a.size.x, a.size.z)
		if longest > 0.01:
			s = minf(s, plate_radius() * 2.0 * FIG_FIT / longest)
	return s


## The screen's right as a ground direction (the camera's yaw), for where a stand's banner stands.
func right_of_view() -> Vector3:
	var yaw := deg_to_rad(float(wv.rig.get("yaw", 0.0))) if wv != null else 0.0
	return Vector3(cos(yaw), 0.0, -sin(yaw))


## Army `id`'s stand as [foot, head] world points (picking: the board takes their screen box).
func points(id: String) -> Array:
	if not stands.has(id) or k < 0.05:
		return []
	var s: Dictionary = stands[id]
	var c: Vector3 = s["pos"]
	var r := plate_radius() * k
	var h := banner_height() * k
	var out := []
	for off in [Vector3(-r, 0, 0), Vector3(r, 0, 0), Vector3(0, 0, -r), Vector3(0, 0, r)]:
		out.append([c + off, c + off + Vector3.UP * h * 0.6])
	out.append([c, c + Vector3.UP * h])
	return out


## How many draw groups the stands use now (the perf readout).
func draw_groups() -> int:
	var n := 0
	for mi in [_plates, _ruler_plates] + _figs.values():
		if mi != null and (mi as Node3D).visible:
			n += 1
	return n + _banners.size() * 2


# --- drawing -------------------------------------------------------------------------------------------

func _draw_stands() -> void:
	if wv == null:
		return
	if _plates == null:
		_plates = _mm("Plates", plate_mesh(false))
		_ruler_plates = _mm("RulerPlates", plate_mesh(true))
	var r := plate_radius() * k
	var plain: Array = []
	var right := right_of_view()
	var rulers: Array = []
	var by_type := {}
	for id in stands.keys():
		var s: Dictionary = stands[id]
		var c: Vector3 = s["pos"]
		var yaw: float = s["yaw"]
		var basis := Basis(Vector3.UP, yaw)
		var lin: Color = (s["colour"] as Color).srgb_to_linear()
		(rulers if bool(s["ruler"]) else plain).append([Transform3D(basis.scaled(Vector3(r, maxf(r * 0.35, 0.01), r)), c + Vector3.UP * 0.05), lin])
		var types: Array = s["types"]
		var spots := figure_spots(types.size())
		for j in types.size():
			var t := "%s|%s" % [String(types[j]), Models.variant_of(String(types[j]), String(s.get("transformation", "")))]
			if not by_type.has(t):
				by_type[t] = []
			var off: Vector2 = spots[j] * (r * 0.62)
			var at: Vector3 = c + basis * Vector3(off.x, 0.0, off.y) + Vector3.UP * (r * 0.35) ## on the plate's top
			by_type[t].append([Transform3D(basis.scaled(Vector3.ONE * maxf(figure_scale(String(types[j])) * k, 0.0001)), at), lin])
		## the banner at the plate's edge on the screen's right, where no figure and no plate hides it (a memory has none)
		if not bool(s.get("memory", false)):
			_banner(String(id), s, c + right * (r * 0.92))
	_fill(_plates, plain)
	_fill(_ruler_plates, rulers)
	for t in by_type.keys():
		if not _figs.has(t):
			var tv := String(t).split("|")
			var fm: Dictionary = Models.figure_mesh(tv[0], true, "ready", "", tv[1] if tv.size() > 1 else "")
			_figs[t] = _mm("Fig_%s" % String(t).validate_node_name(), fm["mesh"], fm.get("tex"))
		_fill(_figs[t], by_type[t])
	for t2 in _figs.keys():
		if not by_type.has(t2):
			_fill(_figs[t2], [])
	for id2 in _banners.keys().duplicate():
		if not stands.has(id2) or bool((stands[id2] as Dictionary).get("memory", false)):
			(_banners[id2] as Node).queue_free()
			_banners.erase(id2)


## Where a stand's figures stand on its plate (plate-local, -Z its front, in plate radii): one in the middle,
## two side by side, three in a wedge with the first (the most numerous type) at the front.
static func figure_spots(n: int) -> Array:
	match n:
		1:
			return [Vector2(0.0, 0.0)]
		2:
			return [Vector2(-0.5, 0.0), Vector2(0.5, 0.0)]
		_:
			return [Vector2(0.0, -0.45), Vector2(-0.6, 0.35), Vector2(0.6, 0.35)].slice(0, n)


func _banner(id: String, s: Dictionary, at: Vector3) -> void:
	if not _banners.has(id):
		var bn: Node3D = wv.make_banner(s["colour"], int(s["emblem"]), 9.0, Vector2(5.2, 3.4))
		bn.name = "Banner_%s" % id.validate_node_name()
		add_child(bn)
		_banners[id] = bn
	var b: Node3D = _banners[id]
	var sc := banner_height() * k / 9.8
	b.transform = Transform3D(Basis(Vector3.UP, float(s["yaw"]) + PI * 0.5).scaled(Vector3.ONE * maxf(sc, 0.0001)), at)
	b.visible = k > 0.02


func _mm(nm: String, mesh: Mesh, tex: Texture2D = null) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	var key := "%d" % (tex.get_instance_id() if tex != null else 0)
	if not _mats.has(key):
		var m: ShaderMaterial = wv.model_mat(Color.WHITE, tex, -1.0, true)
		m.set_shader_parameter("fig_lift", 1.0)
		_mats[key] = m
	mi.material_override = _mats[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF ## far out a stand is a few pixels: its base grounds it
	add_child(mi)
	return mi


func _fill(mi: MultiMeshInstance3D, rows: Array) -> void:
	var mm := mi.multimesh
	if mm.instance_count != rows.size():
		mm.instance_count = rows.size()
	for j in rows.size():
		mm.set_instance_transform(j, rows[j][0])
		mm.set_instance_custom_data(j, rows[j][1])
	mi.visible = rows.size() > 0 and k > 0.001


## A stand's plate (unit radius and height, feet at the origin): a disc in the player's colour (a team part)
## on an ink rim; a ruler's army adds the gilt ring (STYLE_BIBLE.md 2.4) between them.
static func plate_mesh(ruler: bool) -> ArrayMesh:
	var b := Kit.Builder.new()
	var rim := CylinderMesh.new()
	rim.top_radius = 1.08
	rim.bottom_radius = 1.12
	rim.height = 0.7
	rim.radial_segments = 24
	rim.rings = 1
	b.add(rim, Transform3D(Basis(), Vector3(0, 0.35, 0)), Color("#1A1612"))
	if ruler:
		var gilt := CylinderMesh.new()
		gilt.top_radius = 1.0
		gilt.bottom_radius = 1.02
		gilt.height = 0.85
		gilt.radial_segments = 24
		gilt.rings = 1
		b.add(gilt, Transform3D(Basis(), Vector3(0, 0.425, 0)), Kit.GOLD)
	var top := CylinderMesh.new()
	top.top_radius = 0.86 if ruler else 0.96
	top.bottom_radius = 0.9 if ruler else 1.0
	top.height = 1.0
	top.radial_segments = 24
	top.rings = 1
	b.add(top, Transform3D(Basis(), Vector3(0, 0.5, 0)), Kit.TEAM, true)
	return b.mesh()
