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
## Poses (M3a.2, design/3D_DIRECTION.md 7.3 and 9.3): a row may name a model per pose in "poses"
## ({"ready", "march", "strike", "fallen"}, each a path or {"model": path}), sized by "pose_size"
## ({pose: {"axis": "height" or "length", "men": n}}). figure_mesh(type, prefer, pose) draws that pose's
## model, or, when it has none on disk, the ready model (or the primitive) with procedural motion on top
## (world3d/choreo.gd). A pose with no model of its own shares the ready pose's mesh, so the armies draw
## one MultiMesh per distinct pose mesh only.
##
## Pure lookups (no nodes); the meshes are built once and cached per run.
extends RefCounted

const Kit := preload("res://world3d/kit.gd")
const TABLE_PATH := "res://world3d/models.json"
## The pose models a figure can have (rulers add "cheer"; without a model a pose draws the ready one).
const POSES := ["ready", "march", "strike", "fallen", "cheer"]

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


## An army extra's model for a faction (the standard bearer, the musician: design 6.2): the row's
## "models"[faction] when it is on disk, else "". Its height in men is "model_height"[faction].
static func extra_model_path(type_id: String, faction: String) -> String:
	var models: Dictionary = figure_row(type_id).get("models", {})
	var p := String(models.get(faction, ""))
	return p if not p.is_empty() and ResourceLoader.exists(p) else ""


## True when the table has a row for the army's musician (it then stands in every army's colour party).
static func has_musician() -> bool:
	return not figure_row("musician").is_empty()


## The GLB a row names for `pose` ("" when it names none, or the file is missing): the row's
## "poses"[pose] (a path, or {"model": path}); for "ready" also the row's "model" and the bible's
## convention (figure_model_path); for any other pose the convention <unit>_<pose>.glb.
static func pose_model_path(type_id: String, pose: String) -> String:
	var row := figure_row(type_id)
	var p := _pose_entry_path((row.get("poses", {}) as Dictionary).get(pose, ""))
	if not p.is_empty() and ResourceLoader.exists(p):
		return p
	if pose == "ready":
		return figure_model_path(type_id)
	var faction := String(row.get("faction", ""))
	if not faction.is_empty():
		var conv := "res://assets/models/%s/%s/%s_%s.glb" % [faction, type_id, type_id, pose]
		if ResourceLoader.exists(conv):
			return conv
	return ""


static func _pose_entry_path(entry: Variant) -> String:
	if entry is Dictionary:
		return String((entry as Dictionary).get("model", ""))
	return String(entry) if entry != null else ""


## True when `pose` has a model of its own (otherwise the ready mesh stands in, moved in code).
static func has_pose_model(type_id: String, pose: String, prefer_model: bool = true) -> bool:
	if not prefer_model or pose == "ready":
		return false
	return String((figure_mesh(type_id, prefer_model, pose) as Dictionary).get("pose", "ready")) == pose


## Every pose a type can stand in: pose -> its figure_mesh() dictionary. Poses without a model of their
## own map to the ready pose's dictionary (the same mesh), so callers group by mesh.
static func pose_meshes(type_id: String, prefer_model: bool = true, faction: String = "") -> Dictionary:
	var out := {}
	for pose in POSES:
		out[pose] = figure_mesh(type_id, prefer_model, pose, faction)
	return out


## The mesh a figure of `type_id` is drawn with in `pose`: feet at y = 0, facing -Z, Kit.FIG units to a
## man, with a base whose team part takes the player's colour (and a gilt ring for a ruler).
## `prefer_model` false always gives the primitive. A pose with no model of its own returns the ready
## pose's dictionary (the same mesh). Returns {"mesh", "tex", "source", "pose"}.
static func figure_mesh(type_id: String, prefer_model: bool = true, pose: String = "ready", faction: String = "") -> Dictionary:
	var row := figure_row(type_id)
	## an army extra (bearer, musician) wears its faction's model, in every pose
	var extra := extra_model_path(type_id, faction) if prefer_model and not faction.is_empty() else ""
	if not extra.is_empty():
		var ekey := "fig:%s:%s" % [type_id, faction]
		if not _meshes.has(ekey):
			var erow := row.duplicate()
			erow["height"] = float((row.get("model_height", {}) as Dictionary).get(faction, row.get("height", 1.0)))
			erow.erase("pose_size")
			var got := _glb_figure(extra, type_id, erow, "ready")
			if got.is_empty():
				got = figure_mesh(type_id, false, "ready")
			got["pose"] = "ready"
			_meshes[ekey] = got
		return _meshes[ekey]
	var key := "fig:%s:%s:%s" % [type_id, prefer_model, pose]
	if _meshes.has(key):
		return _meshes[key]
	var out := {}
	if pose != "ready":
		var pp := pose_model_path(type_id, pose) if prefer_model else ""
		if not pp.is_empty() and pp != pose_model_path(type_id, "ready"):
			out = _glb_figure(pp, type_id, row, pose)
		if out.is_empty():
			out = figure_mesh(type_id, prefer_model, "ready")
		else:
			out["pose"] = pose
		_meshes[key] = out
		return out
	var path := pose_model_path(type_id, "ready") if prefer_model else ""
	if not path.is_empty():
		out = _glb_figure(path, type_id, row, "ready")
	if out.is_empty():
		var fb := String(row.get("fallback", type_id))
		var s := float(row.get("scale", 1.0))
		var m: ArrayMesh = Kit.figure(fb, s, bool(row.get("ruler", false)))
		out = {"mesh": m, "tex": null, "source": "primitive"}
	out["pose"] = "ready"
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
	return model_at(String(row.get("model", "")))


## Any building or prop GLB by path, as building_model() gives it ({} when it isn't on disk).
static func model_at(p: String) -> Dictionary:
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


## A building kind's interchangeable models (a village's "variants", else its one "model"), those on
## disk, in the row's order. Pick one with variant_for().
static func building_variants(kind: String) -> Array:
	var row := building_row(kind)
	var list: Array = row.get("variants", [])
	if list.is_empty() and not String(row.get("model", "")).is_empty():
		list = [row["model"]]
	return list.filter(func(p): return ResourceLoader.exists(String(p)))


## Which of `n` variants a province shows: a hash of its id (the same every game, never the dice).
static func variant_for(province_id: String, n: int) -> int:
	return 0 if n <= 1 else absi(hash("variant:" + province_id)) % n


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
		for fac in (row.get("models", {}) as Dictionary).keys():
			var mp := String(row["models"][fac])
			if not mp.is_empty() and not ResourceLoader.exists(mp):
				out.append("figure %s: its %s model %s is missing" % [id, fac, mp])
		var poses: Variant = row.get("poses", {})
		if not (poses is Dictionary):
			out.append("figure %s: its poses must be an object of pose -> model" % id)
		else:
			for pose in (poses as Dictionary).keys():
				var pp := _pose_entry_path((poses as Dictionary)[pose])
				if not pp.is_empty() and not ResourceLoader.exists(pp):
					out.append("figure %s: its %s pose %s is missing" % [id, pose, pp])
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
		for vp in row.get("variants", []):
			if not ResourceLoader.exists(String(vp)):
				out.append("building %s: its variant %s is missing" % [id, vp])
	return out


## Clears the cached meshes (a test that swaps the table).
static func clear_cache() -> void:
	_meshes.clear()
	_table = {}


# ------------------------------------------------------------------ GLB normalising

## How a pose's model is sized: {"axis": "height" (its AABB's height), "length" (its longest horizontal
## side: a fallen figure lies along it) or "width", "men": that size in men}. The row's "pose_size"[pose]
## when it gives one; else the row's height (for a fallen pose, its length).
static func pose_size(row: Dictionary, pose: String) -> Dictionary:
	var ps: Variant = (row.get("pose_size", {}) as Dictionary).get(pose)
	if ps is Dictionary and float((ps as Dictionary).get("men", 0.0)) > 0.0:
		return {"axis": String((ps as Dictionary).get("axis", "height")), "men": float((ps as Dictionary).get("men"))}
	return {"axis": "length" if pose == "fallen" else "height", "men": float(row.get("height", 1.0))}


static func _glb_figure(path: String, type_id: String, row: Dictionary, pose: String = "ready") -> Dictionary:
	var src := _load_first_mesh(path)
	if src.is_empty():
		return {}
	var mesh: Mesh = src["mesh"]
	var aabb: AABB = mesh.get_aabb()
	if aabb.size.y <= 0.0001:
		return {}
	## scaled from its AABB to the pose's size in men (the ready pose: the row's height), feet on y = 0,
	## turned by the row's yaw so it faces -Z (glTF faces +Z: yaw 180), on a base in the player's colour
	var size := pose_size(row, pose)
	var along: float = aabb.size.y
	match String(size["axis"]):
		"length":
			along = maxf(aabb.size.x, aabb.size.z)
		"width":
			along = minf(aabb.size.x, aabb.size.z)
	if along <= 0.0001:
		return {}
	var s: float = float(size["men"]) * Kit.FIG / along
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
	return {"mesh": with_lods(b.mesh()), "tex": src["tex"], "source": "model"}


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
	return with_lods(am)


## A one-surface mesh with its levels of detail generated again (bible 8.4: about 25% and 6% of LOD0),
## so a far figure, an army's MultiMesh seen from the whole map, or a far building draws a fraction of
## its triangles. A model rebuilt from its arrays loses the import's LODs; this puts them back.
## Meshes too small to need them come back as they are.
static func with_lods(mesh: ArrayMesh) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() != 1:
		return mesh
	var arr: Array = mesh.surface_get_arrays(0)
	var idx = arr[Mesh.ARRAY_INDEX]
	if idx == null or (idx as PackedInt32Array).size() < 3000:
		return mesh
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr)
	im.generate_lods(25.0, 60.0, [])
	var out: ArrayMesh = im.get_mesh()
	return out if out != null and out.get_surface_count() == 1 else mesh
