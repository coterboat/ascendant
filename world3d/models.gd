## The 3D board's model table: which mesh stands for each unit type and each building kind. The rows
## live in world3d/models.json (format: world3d/README.md, "The model table"), so a new model drops in
## by adding its GLB under assets/models/ and filling in its row, without code changes. A row whose GLB
## is missing (or empty) draws its primitive piece from world3d/kit.gd instead, so the board never
## waits for art.
##
## Lookup order for a figure: the row's "model" if that file exists; then the bible's path convention
## assets/models/<faction>/<unit>/<unit>_ready.glb (STYLE_BIBLE.md 8.10) if that exists; then the row's
## primitive "fallback" (a Kit.figure id) at the row's "scale". A unit type with no row at all stands as
## Kit's generic figure, so a new unit never breaks the board.
##
## Pure lookups (no nodes); the meshes are built once and cached per run.
extends RefCounted

const Kit := preload("res://world3d/kit.gd")
const TABLE_PATH := "res://world3d/models.json"

static var _table: Dictionary = {}
static var _meshes: Dictionary = {} ## cache key -> {"mesh": Mesh, "tex": Texture2D or null, "source": "model"/"primitive"}


## The whole table (read once).
static func table() -> Dictionary:
	if _table.is_empty():
		var f := FileAccess.open(TABLE_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_table = parsed
		if _table.is_empty():
			push_warning("The 3D model table %s could not be read; every piece is drawn from primitives." % TABLE_PATH)
			_table = {"figures": {}, "buildings": {}, "block": {"per_unit": 0.5, "max": 8, "min": 1}}
	return _table


## A unit type's row ({} when it has none: the generic figure stands in).
static func figure_row(type_id: String) -> Dictionary:
	return (table().get("figures", {}) as Dictionary).get(type_id, {})


## A building kind's row; `variant` (a faction id) picks "<kind>.<variant>" when the table has it.
static func building_row(kind: String, variant: String = "") -> Dictionary:
	var rows: Dictionary = table().get("buildings", {})
	if not variant.is_empty() and rows.has(kind + "." + variant):
		return rows[kind + "." + variant]
	return rows.get(kind, {})


## The battle rank a type's block stands in: 0 front, 1 second (Volley), 2 back (commanders, the bearer).
static func rank_of(type_id: String) -> int:
	return int(figure_row(type_id).get("rank", 0))


static func is_large(type_id: String) -> bool:
	return bool(figure_row(type_id).get("large", false))


static func is_ruler(type_id: String) -> bool:
	return bool(figure_row(type_id).get("ruler", false))


## How many figures stand for `count` units of one type: ceil(count x per_unit) between the table's min
## and max (design/3D_DIRECTION.md 6.1 proposes ceil(count / 2), at most 8; the table ships one figure
## per unit, at least 2 and at most 8, so an early army of 3 units still reads as an army, and the
## blocks' sizes stay honest up to 8 units of a type).
static func block_size(count: int) -> int:
	if count <= 0:
		return 0
	var b: Dictionary = table().get("block", {})
	var n: int = int(ceil(float(count) * float(b.get("per_unit", 0.5))))
	return clampi(n, int(b.get("min", 1)), int(b.get("max", 8)))


## The block rule in words, for tooltips and the legend: "one figure per unit, at least 2 and at most 8".
static func block_rule_text() -> String:
	var b: Dictionary = table().get("block", {})
	var per := float(b.get("per_unit", 0.5))
	var lo := int(b.get("min", 1))
	var hi := int(b.get("max", 8))
	var each := "one figure per unit" if is_equal_approx(per, 1.0) else ("one figure for every %d units" % int(round(1.0 / per)) if per < 1.0 else "%d figures per unit" % int(per))
	return "%s, at least %d and at most %d" % [each, lo, hi]


## The GLB a figure row would load, or "" when it draws its primitive (nothing found on disk).
static func figure_model_path(type_id: String) -> String:
	var row := figure_row(type_id)
	var p := String(row.get("model", ""))
	if not p.is_empty() and ResourceLoader.exists(p):
		return p
	var faction := String(row.get("faction", ""))
	if not faction.is_empty():
		var conv := "res://assets/models/%s/%s/%s_ready.glb" % [faction, type_id, type_id]
		if ResourceLoader.exists(conv):
			return conv
	return ""


## The mesh a figure of `type_id` is drawn with: feet at y = 0, facing -Z, Kit.FIG units to a man, with
## a base whose team part takes the player's colour (and a gilt ring for a ruler). `prefer_model` false
## always gives the primitive. Returns {"mesh", "tex", "source"}.
static func figure_mesh(type_id: String, prefer_model: bool = true) -> Dictionary:
	var key := "fig:%s:%s" % [type_id, prefer_model]
	if _meshes.has(key):
		return _meshes[key]
	var row := figure_row(type_id)
	var out := {}
	var path := figure_model_path(type_id) if prefer_model else ""
	if not path.is_empty():
		out = _glb_figure(path, type_id, row)
	if out.is_empty():
		var fb := String(row.get("fallback", type_id))
		var s := float(row.get("scale", 1.0))
		var m: ArrayMesh = Kit.figure(fb, s, bool(row.get("ruler", false)))
		out = {"mesh": m, "tex": null, "source": "primitive"}
	_meshes[key] = out
	return out


## A building kind's primitive mesh (no textures): the fallback piece from Kit.
static func building_primitive(kind: String, variant: String = "") -> Mesh:
	var key := "bld:%s:%s" % [kind, variant]
	if _meshes.has(key):
		return _meshes[key]["mesh"]
	var row := building_row(kind, variant)
	var fb := String(row.get("fallback", kind))
	var m: Mesh
	match fb:
		"fortress":
			m = Kit.fortress(float(row.get("side", 76.0)))
		"fort":
			m = Kit.fort()
		"broadleaf":
			m = Kit.broadleaf()
		"pine":
			m = Kit.pine()
		"rock":
			m = Kit.rock()
		_:
			m = Kit.cottage(0)
	_meshes[key] = {"mesh": m, "tex": null, "source": "primitive"}
	return m


## A building kind's GLB as {"mesh" (vertex colours white, so the model shader reads its texture),
## "tex", "aabb"}, or {} when the row has no model on disk.
static func building_model(kind: String, variant: String = "") -> Dictionary:
	var row := building_row(kind, variant)
	var p := String(row.get("model", ""))
	if p.is_empty() or not ResourceLoader.exists(p):
		return {}
	var key := "bldm:" + p
	if _meshes.has(key):
		return _meshes[key]
	var src := _load_first_mesh(p)
	if src.is_empty():
		return {}
	var out := {"mesh": _vertex_white(src["mesh"]), "tex": src["tex"], "aabb": (src["mesh"] as Mesh).get_aabb()}
	_meshes[key] = out
	return out


## Every row's problems, in plain words (tests: a row's fallback must exist and its model, when named,
## must be on disk or be marked missing on purpose with "").
static func problems() -> Array:
	var out: Array = []
	var figs: Dictionary = table().get("figures", {})
	for id in figs.keys():
		var row: Dictionary = figs[id]
		if not Kit.has_figure(String(row.get("fallback", ""))):
			out.append("figure %s: its fallback '%s' is not a Kit figure" % [id, row.get("fallback", "")])
		var p := String(row.get("model", ""))
		if not p.is_empty() and not ResourceLoader.exists(p):
			out.append("figure %s: its model %s is missing" % [id, p])
		if float(row.get("height", 1.0)) <= 0.0:
			out.append("figure %s: its height must be above 0" % id)
	var blds: Dictionary = table().get("buildings", {})
	for id in blds.keys():
		var row: Dictionary = blds[id]
		if not ["fortress", "fort", "cottage", "broadleaf", "pine", "rock"].has(String(row.get("fallback", ""))):
			out.append("building %s: its fallback '%s' is not a Kit piece" % [id, row.get("fallback", "")])
		var p := String(row.get("model", ""))
		if not p.is_empty() and not ResourceLoader.exists(p):
			out.append("building %s: its model %s is missing" % [id, p])
	return out


## Clears the cached meshes (a test that swaps the table).
static func clear_cache() -> void:
	_meshes.clear()
	_table = {}


# ------------------------------------------------------------------ GLB normalising

static func _glb_figure(path: String, type_id: String, row: Dictionary) -> Dictionary:
	var src := _load_first_mesh(path)
	if src.is_empty():
		return {}
	var mesh: Mesh = src["mesh"]
	var aabb: AABB = mesh.get_aabb()
	if aabb.size.y <= 0.0001:
		return {}
	## scaled from its AABB to the row's height in men, feet on y = 0, turned by the row's yaw so it
	## faces -Z (glTF faces +Z: yaw 180), on a base in the player's colour
	var s: float = float(row.get("height", 1.0)) * Kit.FIG / aabb.size.y
	var c: Vector3 = aabb.get_center()
	var yaw := deg_to_rad(float(row.get("yaw", 180.0)))
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3.ZERO) * Transform3D(Basis(), Vector3(-c.x, -aabb.position.y, -c.z))
	xf.origin += Vector3(0, 0.36, 0)
	var arr: Array = mesh.surface_get_arrays(0)
	var b := Kit.Builder.new()
	var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var puv = arr[Mesh.ARRAY_TEX_UV]
	var pi = arr[Mesh.ARRAY_INDEX]
	for k in pv.size():
		b.v.append(xf * pv[k])
		b.n.append((xf.basis * pn[k]).normalized() if k < pn.size() else Vector3.UP)
		b.c.append(Color(1, 1, 1, 1))
		b.uv.append(puv[k] if puv != null and k < (puv as PackedVector2Array).size() else Vector2.ZERO)
	if pi != null and (pi as PackedInt32Array).size() > 0:
		for k in pi:
			b.idx.append(k)
	else:
		for k in pv.size():
			b.idx.append(k)
	Kit._base(b, String(row.get("fallback", type_id)), bool(row.get("ruler", false)))
	return {"mesh": b.mesh(), "tex": src["tex"], "source": "model"}


static func _load_first_mesh(path: String) -> Dictionary:
	var res: Resource = load(path)
	if not (res is PackedScene):
		return {}
	var inst: Node = (res as PackedScene).instantiate()
	var mi := _first_mesh(inst)
	if mi == null or mi.mesh == null:
		inst.free()
		return {}
	var mesh: Mesh = mi.mesh
	var tex: Texture2D = null
	var sm := mesh.surface_get_material(0)
	if sm == null:
		sm = mi.get_surface_override_material(0)
	if sm is BaseMaterial3D:
		tex = (sm as BaseMaterial3D).albedo_texture
	inst.free()
	return {"mesh": mesh, "tex": tex}


static func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for ch in n.get_children():
		var m := _first_mesh(ch)
		if m != null:
			return m
	return null


## A copy of an imported mesh with white vertex colours, so the model shaders read its texture.
static func _vertex_white(mesh: Mesh) -> ArrayMesh:
	var arr: Array = mesh.surface_get_arrays(0)
	var nv: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var cols := PackedColorArray()
	cols.resize(nv)
	cols.fill(Color(1, 1, 1, 1))
	arr[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am
