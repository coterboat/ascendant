## CW-8 (#259, design/CANDLEWAKE.md §3.5): the Wake's lights on the land, drawn in code: a flame in the windows of every building
## (village, landmark, fort, fortress) of a province at Sitting Up or deeper, and candle-posts along its roads from the Wake-Line on
## (the quality ladder's medium rungs and up), lilac, flickering on the top rungs (WakeLook.ladder). A cold wake is unlit. The windows
## are found on the building's own mesh (windows_of: its walls at window height, one on each side), so a new model lights where its
## walls are. Each flame has a soft glow round it (wake_glow.gdshader), so it reads as a light. One MultiMesh for the flames, one for
## their glows and one for the posts, rebuilt when the Wake changes (WorldView.set_wake). Cosmetic: placed from the map and the
## meshes, never the game's dice.
extends Node3D

const Kit := preload("res://world3d/kit.gd")
const WakeLook := preload("res://world3d/wake_look.gd")
const SH_WICK := preload("res://world3d/shaders/wick_flame.gdshader")
const SH_GLOW := preload("res://world3d/shaders/wake_glow.gdshader")
const LILAC := Color("#B48CF0")
const GLOW := Color(0.71, 0.55, 0.94, 0.65) ## the glow's lilac, and how strong at its middle
const SOOT := Color("#2A2430")
const BRASS := Color("#B98B3A")
const WINDOW_AT := 0.3 ## window height, of the building's own height
const BIG := 40.0 ## a building this wide (world units) has three windows a side
const MIN_PX := 3.5 ## far out the flames grow until a world unit spans this on screen (wick_flame.gdshader)
const POST_GAP := 11.0 ## world units between candle-posts along a road
const POST_SIDE := 4.2 ## how far beside the road they stand

var counts := {"windows": 0, "posts": 0} ## what the last sync drew (tests)
var _flames: MultiMeshInstance3D = null
var _glows: MultiMeshInstance3D = null
var _posts: MultiMeshInstance3D = null
var _mat: ShaderMaterial = null
var _glow_mat: ShaderMaterial = null


## Draws the Wake's lights for `look` (WakeLook.of) on WorldView `wv` as the quality ladder's `lad` (WakeLook.ladder) says.
func sync(wv, look: Dictionary, lad: Dictionary) -> void:
	var flames: Array = []
	var glows: Array = []
	var posts: Array = []
	var t = wv.terrain
	var seats: Array = wv.wake_seats(t)
	var pids: Array = look.keys()
	pids.sort()
	var windows := 0
	for pid in pids:
		var w: Dictionary = look[pid]
		if not bool(w.lit):
			continue
		var melt := float(w.melt) if bool(lad.melt) else 0.0 ## the windows come down with a melting building
		for bld in wv.wake_buildings(String(pid)):
			var mesh: Mesh = bld["mesh"]
			var xf: Transform3D = bld["xf"]
			var box := mesh.get_aabb()
			var pivot := Vector3(box.get_center().x, box.position.y, box.get_center().z)
			## the size the building's height says, upright whatever its turn; a big one (a fortress) has three windows a side
			var k := xf.basis.get_scale().y
			var fs := clampf(box.size.y * k * 0.09, 1.2, 3.0)
			for spot in _spots_of(mesh, 3 if maxf(box.size.x, box.size.z) * k > BIG else 1):
				var m: Vector3 = (spot as Vector3) - pivot ## melted as the building's shader melts it (model_common.gdshaderinc)
				var at := xf * (pivot + Vector3(m.x * (1.0 + melt * 0.07), m.y * (1.0 - melt * 0.22), m.z * (1.0 + melt * 0.07)))
				flames.append(Transform3D(Basis().scaled(Vector3(fs * 0.62, fs, fs * 0.62)), at))
				glows.append(Transform3D(Basis().scaled(Vector3.ONE * fs * 2.4), at + Vector3(0, fs * 0.45, 0)))
				windows += 1
		if bool(w.posts) and bool(lad.posts):
			for road in t.roads:
				if String(road.a) != pid and String(road.b) != pid:
					continue
				_road_posts(t, String(pid), t.road_path(String(road.a), String(road.b)), seats, posts, flames, glows)
	counts = {"windows": windows, "posts": posts.size()}
	_fill(flames, glows, posts, bool(lad.sway))


var _spots := {} ## "mesh id:per side" -> its windows (windows_of), found once while this board stands


func _spots_of(mesh: Mesh, per_side: int) -> Array:
	var key := "%d:%d" % [mesh.get_instance_id(), per_side]
	if not _spots.has(key):
		_spots[key] = windows_of(mesh, per_side)
	return _spots[key]


## A building mesh's windows, in its own space: on each of its four sides, `per_side` of them spread along it, each on the outermost
## wall facing that way there, at WINDOW_AT of its height and a little out from the wall, read from its vertices (a side with no wall
## there has none); a mesh without vertex data gets its bounding box's sides.
static func windows_of(mesh: Mesh, per_side := 1) -> Array:
	var box := mesh.get_aabb()
	var c := box.get_center()
	var y0 := box.position.y + box.size.y * 0.12
	var y1 := box.position.y + box.size.y * 0.5
	var sides := [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
	var bins: Array = [0.0] if per_side <= 1 else [-0.28, 0.0, 0.28] ## where along a side, of its length
	var half := 0.3 if per_side <= 1 else 0.1
	var best: Array = []
	for k in 4:
		best.append(bins.map(func(_b): return -INF))
	var any := false
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms = arr[Mesh.ARRAY_NORMAL]
		if norms == null or (norms as PackedVector3Array).size() != verts.size():
			continue
		any = true
		for i in verts.size():
			var v: Vector3 = verts[i]
			if v.y < y0 or v.y > y1:
				continue
			var n: Vector3 = norms[i]
			if absf(n.y) > 0.45:
				continue
			for k in 4:
				var d: Vector3 = sides[k]
				if n.dot(d) < 0.6:
					continue
				var across := (v.z - c.z) / maxf(box.size.z, 0.001) if k < 2 else (v.x - c.x) / maxf(box.size.x, 0.001)
				for j in bins.size():
					if absf(across - float(bins[j])) <= half:
						best[k][j] = maxf(best[k][j], v.dot(d))
	var out: Array = []
	var y := box.position.y + box.size.y * WINDOW_AT
	for k in 4:
		var d: Vector3 = sides[k]
		var size_d := absf(box.size.dot(d))
		var lat := Vector3(0, 0, box.size.z) if k < 2 else Vector3(box.size.x, 0, 0) ## along the side
		for j in bins.size():
			var out_at: float = best[k][j] if any else c.dot(d) + size_d * 0.5
			if out_at == -INF:
				continue
			var p := c + d * (out_at - c.dot(d) + size_d * 0.03) + lat * float(bins[j])
			out.append(Vector3(p.x, y, p.z))
	return out


## Candle-posts every POST_GAP along `path`, on `pid`'s side of the border, alternating sides of the road, never inside a building's
## footprint (`seats`, WorldView.wake_seats).
func _road_posts(t, pid: String, path: PackedVector2Array, seats: Array, posts: Array, flames: Array, glows: Array) -> void:
	var walked := 0.0
	var next := POST_GAP * 0.5
	var side := 1.0
	for i in path.size() - 1:
		var p0: Vector2 = path[i]
		var p1: Vector2 = path[i + 1]
		var seg := p0.distance_to(p1)
		if seg < 0.001:
			continue
		var dir := (p1 - p0) / seg
		var nrm := Vector2(-dir.y, dir.x)
		while next <= walked + seg:
			var at := p0 + dir * (next - walked)
			if t.province_at(at) == pid and not seats.any(func(st): return at.distance_to(st[0]) < float(st[1]) + POST_SIDE):
				var g: Vector3 = t.ground_at(at + nrm * POST_SIDE * side)
				posts.append(Transform3D(Basis(), g))
				flames.append(Transform3D(Basis().scaled(Vector3(0.9, 1.15, 0.9)), g + Vector3(0, 3.4, 0)))
				glows.append(Transform3D(Basis().scaled(Vector3.ONE * 3.0), g + Vector3(0, 3.95, 0)))
				side = -side
			next += POST_GAP
		walked += seg


func _fill(flames: Array, glows: Array, posts: Array, sway: bool) -> void:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SH_WICK
		_mat.set_shader_parameter("min_px", MIN_PX)
		_glow_mat = ShaderMaterial.new()
		_glow_mat.shader = SH_GLOW
		_glow_mat.set_shader_parameter("min_px", MIN_PX)
	_mat.set_shader_parameter("flicker", 1.0 if sway else 0.0)
	_flames = _multimesh(_flames, "WakeFlames", Kit.flame_mesh(), flames, _mat, LILAC)
	_glows = _multimesh(_glows, "WakeGlows", _glow_mesh(), glows, _glow_mat, GLOW)
	_posts = _multimesh(_posts, "WakePosts", _post_mesh(), posts, _post_mat(), Color.TRANSPARENT)


## `col` is each instance's custom data (the flame shaders' colour), none when it is transparent.
func _multimesh(mi: MultiMeshInstance3D, nm: String, mesh: Mesh, xfs: Array, mat: Material, col: Color) -> MultiMeshInstance3D:
	if mi == null:
		mi = MultiMeshInstance3D.new()
		mi.name = nm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = col.a > 0.0
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		if col.a > 0.0:
			mm.set_instance_custom_data(i, col)
	mi.multimesh = mm
	mi.material_override = mat
	mi.visible = not xfs.is_empty()
	return mi


static var _post_mesh_c: ArrayMesh = null
static var _post_mat_c: StandardMaterial3D = null
static var _glow_mesh_c: QuadMesh = null


static func _glow_mesh() -> QuadMesh:
	if _glow_mesh_c == null:
		_glow_mesh_c = QuadMesh.new()
		_glow_mesh_c.size = Vector2.ONE
	return _glow_mesh_c


## A candle-post: a soot pole with a brass dish at its top, where its flame sits.
static func _post_mesh() -> ArrayMesh:
	if _post_mesh_c == null:
		var b := Kit.Builder.new()
		b.cyl(0.16, 0.22, 3.0, Vector3(0, 1.5, 0), SOOT, 6)
		b.cyl(0.36, 0.22, 0.18, Vector3(0, 3.08, 0), BRASS, 8)
		b.cyl(0.12, 0.12, 0.3, Vector3(0, 3.3, 0), Color("#D9CAA4"), 6) ## the stub of tallow
		_post_mesh_c = b.mesh()
	return _post_mesh_c


static func _post_mat() -> StandardMaterial3D:
	if _post_mat_c == null:
		_post_mat_c = StandardMaterial3D.new()
		_post_mat_c.vertex_color_use_as_albedo = true
		_post_mat_c.roughness = 1.0
	return _post_mat_c
