## Draws the spell and ritual effects (M5-9, design/M5_MAGIC_FOG.md §12.2, §15.3): the placeholder marks (rings, beams, billboards and
## motes, all in code until the VFX sheets come) that world3d/spell_plan.gd plans, in three MultiMeshes (the ground decals, the
## sprites, the beams) so a whole battle's spells cost three draw calls. It serves the 3D battle stage and the 3D board alike.
##
## Rules it keeps (the spec's, and the tests'):
##   * effects never change anything: this node reads plans and draws; it touches no game state, rolls no dice, and a mote's place is
##     a hash of its index (SpellPlan.h01)
##   * a pool of at most SpellPlan.POOL_CAP effects alive; a full pool SKIPS a new effect (it is not queued), the caption and the bars
##     carry the facts (BattleFx.Pool's rule)
##   * the flash limiter (BattleFx.FlashLimiter) counts an effect that asks (a bolt, Sunburst): when it says no, the effect plays
##     without bright frames (its bright marks never rise above 80%); a bright mark rises above 80% for at most BRIGHT_FRAMES real
##     frames. Reduced motion asks for nothing and plays every effect as a still mark.
##   * standing decals (an enchantment's, kept while it lasts) are outside the pool: the state keeps them, not a cast
##
##   play(plan, real_now)           pools a plan (SpellPlan.battle / board): the plan, or {"skipped": true} when the pool was full
##   step(dt)                       ages the pool by `dt` playback seconds (the node steps itself in real time when auto_step is set)
##   set_standing(key, elements)    keeps these elements on the map until clear_standing(key)
##   clear()                        empties the pool (a seek, a new battle); stats() counts what is alive and what was skipped
extends Node3D

const SpellPlan := preload("res://world3d/spell_plan.gd")
const SH_GROUND := preload("res://world3d/shaders/spell_fx_ground.gdshader")
const SH_TOP := preload("res://world3d/shaders/spell_fx_top.gdshader")

const GRID := 12 ## a ground decal is a GRID x GRID quad grid, laid on the land by the shader
const MAX_GROUND := 320
const MAX_SPRITES := 768
const MAX_BEAMS := 64
## Bible §2.5: a bright mark stays above 80% opacity for at most 2 frames (BattleFx.BRIGHT_FRAMES), and never when the limiter said no.
const BRIGHT_CAP := 0.8
## The shaders' pipelines are built on first use: for this many frames after the node is made, each layer draws one invisible mark (alpha 0), so
## the first Sunburst does not hitch a battle (3D_DIRECTION §3.5: no frame above 50 ms outside loading).
const WARM_FRAMES := 3

var rung := 0
var reduced_motion := false
var flash: BattleFx.FlashLimiter = null
var pool := BattleFx.Pool.new(SpellPlan.POOL_CAP)
var auto_step := false ## true: the node ages its pool itself in real time (the board); false: the owner calls step() with playback time
var time_scale := 1.0
var spawned := 0
var skipped := 0
var flashes_asked := 0
var flashes_refused := 0
var drawn := {"ground": 0, "sprites": 0, "beams": 0} ## instances written by the last render (the draw-call test)
var _standing := {}
var _dirty := false
var _warm := WARM_FRAMES
var _ground: MultiMeshInstance3D
var _sprites: MultiMeshInstance3D
var _beams: MultiMeshInstance3D
var _layers: Array = []


func _init() -> void:
	name = "SpellFx"
	_ground = _layer("Ground", _grid(GRID), SH_GROUND, MAX_GROUND)
	_sprites = _layer("Sprites", _quad(), SH_TOP, MAX_SPRITES)
	_beams = _layer("Beams", _beam_mesh(), SH_TOP, MAX_BEAMS)
	_layers = [_ground, _sprites, _beams]


func _process(delta: float) -> void:
	if _warm > 0:
		_warm_up()
	if auto_step and not pool.items.is_empty():
		step(delta * time_scale)


## One invisible mark in each layer for a few frames, so the renderer builds each layer's pipeline now, not at the first spell.
func _warm_up() -> void:
	_warm -= 1
	if _warm > 0 and pool.items.is_empty():
		for mi in _layers:
			var mm: MultiMesh = (mi as MultiMeshInstance3D).multimesh
			mm.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3(0.01, 0.01, 0.01)), Vector3.ZERO))
			mm.set_instance_color(0, Color(1, 1, 1, 0))
			mm.set_instance_custom_data(0, Color(float(SpellPlan.KINDS["glow"]) if mi != _beams else float(SpellPlan.BEAM), 1.0, 0.0, 0.0))
			mm.visible_instance_count = 1
			(mi as MultiMeshInstance3D).visible = true
	elif pool.items.is_empty():
		_write(0, 0, 0)


# ------------------------------------------------------------------ the land

## Lays the ground decals on the land: `height_tex` is the ground shaders' own texture (WorldView.gmat's), `origin` and `extent` its
## world rectangle. Without it a decal stays flat at the height its effect gave it.
func bind_ground(height_tex: Texture2D, origin: Vector2, extent: Vector2) -> void:
	var mat := _ground.material_override as ShaderMaterial
	mat.set_shader_parameter("height_tex", height_tex)
	mat.set_shader_parameter("origin", origin)
	mat.set_shader_parameter("extent", extent)
	mat.set_shader_parameter("ground_bound", 1.0 if height_tex != null else 0.0)


# ------------------------------------------------------------------ pooling

## Pools `plan` (a SpellPlan.battle or board plan) at real time `real_now`. Returns the plan, with "bright" (whether its bright marks
## may flash), or {"skipped": true, "effect"} when the pool was full. A plan asking for a flash asks the limiter once.
func play(plan: Dictionary, real_now: float = 0.0) -> Dictionary:
	if (plan["elements"] as Array).is_empty():
		spawned += 1
		plan["bright"] = false
		return plan
	if pool.size() >= pool.cap:
		skipped += 1
		return {"skipped": true, "effect": plan.get("effect", ""), "elements": [], "labels": [], "shake": 0.0, "flash": false}
	var may := false
	if bool(plan.get("flash", false)) and not reduced_motion:
		flashes_asked += 1
		may = flash == null or flash.allow(real_now)
		if not may:
			flashes_refused += 1
	plan["bright"] = may
	var item := {"effect": plan["effect"], "plan": plan, "age": 0.0, "life": float(plan["life"]) + 0.05, "frames": 0, "bright": may}
	pool.add(item)
	spawned += 1
	step(0.0)
	return plan


## Ages the pool and draws it (`dt` playback seconds; 0 while paused: the marks hold, the real frames still count).
func step(dt: float) -> void:
	var had := not pool.items.is_empty()
	if had:
		for it in pool.items:
			it["frames"] = int(it["frames"]) + 1
		pool.age(dt)
	if had or _dirty:
		_render()


func clear() -> void:
	pool.clear()
	_render()


## How many effects are alive, how many marks are drawn by layer, and what the pool and the limiter turned away.
func stats() -> Dictionary:
	return {"alive": pool.size(), "ground": int(drawn["ground"]), "sprites": int(drawn["sprites"]), "beams": int(drawn["beams"]),
		"spawned": spawned, "skipped": skipped, "flashes_asked": flashes_asked, "flashes_refused": flashes_refused, "standing": standing_count()}


# ------------------------------------------------------------------ standing decals

## Keeps `elements` (SpellPlan.standing) on the map until clear_standing(key). They are drawn at their full opacity from the first frame.
func set_standing(key: String, elements: Array) -> void:
	if elements.is_empty():
		_standing.erase(key)
	else:
		_standing[key] = elements
	_render()


func clear_standing(key: String = "") -> void:
	if key.is_empty():
		_standing.clear()
	else:
		_standing.erase(key)
	_render()


func standing_count() -> int:
	var n := 0
	for k in _standing:
		n += (_standing[k] as Array).size()
	return n


func standing_keys() -> Array:
	var out: Array = _standing.keys()
	out.sort()
	return out


# ------------------------------------------------------------------ one mark

## What one element looks like `age` seconds into its effect: {} when it is not showing, else {"layer" 0 ground / 1 sprite / 2 beam,
## "kind" (the shader's number), "pos", "to", "r", "alpha", "y", "seed", "w", "yaw", "col"}. `bright` is the effect's permission to
## flash, `frames` the real frames it has been up. Pure (the tests read it).
static func mark(e: Dictionary, age: float, bright: bool, frames: int) -> Dictionary:
	var t := age - float(e["t0"])
	var dur := float(e["dur"])
	if t < 0.0 or t > dur:
		return {}
	var hold: bool = bool(e.get("hold", false))
	var k := 1.0
	if not hold:
		k = minf(t / maxf(float(e["fin"]), 0.0001), maxf(dur - t, 0.0) / maxf(float(e["fout"]), 0.0001))
	k = clampf(k, 0.0, 1.0)
	var col: Color = e["col"]
	var alpha := col.a * (k * k * (3.0 - 2.0 * k))
	if bool(e.get("bright", false)):
		if not bright or frames > BattleFx.BRIGHT_FRAMES:
			alpha = minf(alpha, BRIGHT_CAP)
	var u := clampf(t / maxf(dur, 0.0001), 0.0, 1.0)
	var pos: Vector3 = e["at"]
	if e.has("path"):
		pos = _along(e["path"], u) + Vector3.UP * float(e["up"]) * sin(u * PI)
	else:
		pos += Vector3.UP * float(e["up"]) * (1.0 - pow(1.0 - u, 2.0))
	var r := float(e["r"])
	if e.has("r0"):
		var grow := float(e.get("grow", dur * 0.6))
		var g := clampf(t / maxf(grow, 0.0001), 0.0, 1.0)
		r = lerpf(float(e["r0"]), r, 1.0 - pow(1.0 - g, 2.0))
	var kind: int = int(SpellPlan.KINDS[String(e["k"])])
	var layer := 2 if kind >= SpellPlan.BEAM else (0 if kind <= SpellPlan.GROUND_MAX else 1)
	var y := 1.0 if hold else clampf(t / maxf(float(e["fin"]) * 2.0, 0.15), 0.0, 1.0)
	if layer == 2:
		var head := float(e.get("head", 0.0))
		y = 1.0 if head <= 0.0 else clampf(t / head, 0.0, 1.0)
	var seed_v := float(e.get("seed", 0.0))
	if seed_v == 0.0:
		seed_v = fposmod(float(e.get("yaw", 0.0)), TAU) / TAU
	return {"layer": layer, "kind": kind, "pos": pos, "to": e.get("to", pos), "r": r, "alpha": alpha, "y": y, "seed": seed_v,
		"w": float(e.get("w", 0.0)), "yaw": float(e.get("yaw", 0.0)), "col": col}


## The point `u` (0..1) of the way along a polyline of world points.
static func _along(path: PackedVector3Array, u: float) -> Vector3:
	if path.size() < 2:
		return path[0] if path.size() == 1 else Vector3.ZERO
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	var want := total * clampf(u, 0.0, 1.0)
	for i in range(1, path.size()):
		var seg := path[i - 1].distance_to(path[i])
		if want <= seg or i == path.size() - 1:
			return path[i - 1].lerp(path[i], clampf(want / maxf(seg, 0.0001), 0.0, 1.0))
		want -= seg
	return path[path.size() - 1]


# ------------------------------------------------------------------ drawing

func _render() -> void:
	var n := [0, 0, 0]
	for it in pool.items:
		var plan: Dictionary = it["plan"]
		var bright: bool = bool(it["bright"])
		var frames := int(it["frames"])
		for e in plan["elements"]:
			_put(mark(e, float(it["age"]), bright, frames), n)
	for key in _standing:
		for e in _standing[key]:
			_put(mark(e, float(e["t0"]) + 0.01, false, 99), n)
	_dirty = false
	drawn = {"ground": n[0], "sprites": n[1], "beams": n[2]}
	_write(n[0], n[1], n[2])


func _put(m: Dictionary, n: Array) -> void:
	if m.is_empty():
		return
	var layer := int(m["layer"])
	var mi: MultiMeshInstance3D = _layers[layer]
	var i: int = n[layer]
	if i >= mi.multimesh.instance_count:
		return
	var pos: Vector3 = m["pos"]
	var r := float(m["r"])
	var basis := Basis()
	match layer:
		0:
			basis = Basis(Vector3.UP, float(m["yaw"])) * Basis(Vector3.RIGHT, -PI * 0.5) * Basis.from_scale(Vector3(r * 2.0, r * 2.0, 1.0))
		1:
			basis = Basis.from_scale(Vector3(r * 2.0, r * 2.0, 1.0))
		2:
			var d: Vector3 = (m["to"] as Vector3) - pos
			var dn := d.normalized() if d.length() > 0.001 else Vector3.FORWARD
			var side := dn.cross(Vector3.UP)
			side = side.normalized() if side.length() > 0.001 else Vector3.RIGHT
			var up2 := side.cross(dn).normalized()
			basis = Basis(side * r * 2.0, up2 * r * 2.0, d if d.length() > 0.001 else dn * 0.001)
	var mm := mi.multimesh
	mm.set_instance_transform(i, Transform3D(basis, pos))
	var c: Color = (m["col"] as Color).srgb_to_linear()
	mm.set_instance_color(i, Color(c.r, c.g, c.b, float(m["alpha"])))
	mm.set_instance_custom_data(i, Color(float(m["kind"]), float(m["y"]), float(m["seed"]), float(m["w"])))
	n[layer] = i + 1


func _write(g: int, s: int, b: int) -> void:
	_ground.multimesh.visible_instance_count = g
	_ground.visible = g > 0
	_sprites.multimesh.visible_instance_count = s
	_sprites.visible = s > 0
	_beams.multimesh.visible_instance_count = b
	_beams.visible = b > 0


func _layer(label: String, mesh: Mesh, shader: Shader, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var mi := MultiMeshInstance3D.new()
	mi.name = label
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-4000, -600, -4000), Vector3(8000, 2400, 8000))
	mi.visible = false
	add_child(mi)
	return mi


## A 1 x 1 quad facing +Z, UV 0..1 (a sprite, or a ground decal once the transform lays it down).
static func _quad() -> Mesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	return q


## A 1 x 1 quad facing +Z cut into n x n cells, UV 0..1: a ground decal that follows the land's slope (its vertices are raised by the shader).
static func _grid(n: int) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iy in n:
		for ix in n:
			var x0 := float(ix) / float(n)
			var x1 := float(ix + 1) / float(n)
			var y0 := float(iy) / float(n)
			var y1 := float(iy + 1) / float(n)
			var corners := [[x0, y0], [x1, y0], [x1, y1], [x0, y0], [x1, y1], [x0, y1]]
			for c in corners:
				st.set_uv(Vector2(c[0], c[1]))
				st.set_normal(Vector3.BACK)
				st.add_vertex(Vector3(c[0] - 0.5, 0.5 - c[1], 0.0))
	return st.commit()


## The beam: two ribbons crossing along their length (z from 0 to 1, x and y across), so a beam reads from any side. UV.x is across
## a ribbon, UV.y along it.
static func _beam_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in 2:
		var a := Vector3(-0.5, 0.0, 0.0) if axis == 0 else Vector3(0.0, -0.5, 0.0)
		var b := Vector3(0.5, 0.0, 0.0) if axis == 0 else Vector3(0.0, 0.5, 0.0)
		var corners := [[a, Vector2(0, 0)], [b, Vector2(1, 0)], [b + Vector3(0, 0, 1), Vector2(1, 1)], [a, Vector2(0, 0)],
			[b + Vector3(0, 0, 1), Vector2(1, 1)], [a + Vector3(0, 0, 1), Vector2(0, 1)]]
		for c in corners:
			st.set_uv(c[1])
			st.set_normal(Vector3(0, 1, 0) if axis == 0 else Vector3(1, 0, 0))
			st.add_vertex(c[0])
	return st.commit()
