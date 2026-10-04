extends "res://tests/test_case.gd"
## The 3D model batch asc-3d-factions (assets/models/README.md): assets/models/models.json describes
## every installed model, and every row's GLB loads as one textured mesh of the size it claims. Which
## models must exist comes from the data: every unit type and commander of every faction in
## data/factions.gd in all four poses, every ruler in data/rulers.gd, and a fortress and a fort for
## every faction (data/map.gd's capitals and forts stand in them).

const DESCRIPTOR := "res://assets/models/models.json"
const POSES := ["ready", "march", "strike", "fallen"]
const RULER_POSES := ["ready", "march", "strike", "fallen", "cheer"]
const KINDS := {"units": "unit", "rulers": "ruler", "extras": "extra", "buildings": "building", "props": "prop"}
const AXES := ["height", "length", "width"]

static var _models: Dictionary = {}


func _desc() -> Dictionary:
	if _models.is_empty():
		var text := FileAccess.get_file_as_string(DESCRIPTOR)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_models = parsed
	return _models


## Every row: [group, id, pose or variant, row].
func _rows() -> Array:
	var out := []
	var d := _desc()
	for group in KINDS:
		var g: Dictionary = d.get(group, {})
		for id in g:
			for key in g[id]:
				out.append([group, id, key, g[id][key]])
	return out


func test_descriptor_parses_and_every_row_is_well_formed() -> void:
	var d := _desc()
	assert_false(d.is_empty(), "models.json parses as a dictionary")
	assert_eq(int(d.get("format", 0)), 1, "format 1")
	var rows := _rows()
	assert_true(rows.size() > 0, "it lists models")
	for r in rows:
		var e: Dictionary = r[3]
		var where := "%s/%s/%s" % [r[0], r[1], r[2]]
		assert_eq(String(e.get("id", "")), String(r[1]), "%s: id matches its key" % where)
		assert_eq(String(e.get("kind", "")), KINDS[r[0]], "%s: kind" % where)
		var path := String(e.get("path", ""))
		assert_true(path.begins_with("res://assets/models/") and path.ends_with(".glb"), "%s: a GLB under assets/models/" % where)
		assert_true(ResourceLoader.exists(path), "%s: %s is imported" % [where, path])
		var size: Dictionary = e.get("size", {})
		assert_true(AXES.has(String(size.get("axis", ""))), "%s: size axis is one of %s" % [where, AXES])
		assert_true(float(size.get("men", 0.0)) > 0.0, "%s: size in men is positive" % where)
		assert_true(is_finite(float(e.get("yaw", NAN))), "%s: yaw is a number" % where)
		assert_true(int(e.get("faces", 0)) >= 1000, "%s: faces recorded" % where)
		for k in e.get("hue_keys", []):
			assert_true(float(k["hue"]) >= 0.0 and float(k["hue"]) <= 1.0, "%s: hue key in 0..1" % where)
			assert_true(float(k["width"]) > 0.0 and float(k["width"]) <= 0.06, "%s: hue key width in (0, 0.06]" % where)
			assert_false(String(k.get("part", "")).is_empty(), "%s: hue key names its part" % where)
		if r[0] in ["units", "rulers", "extras"]:
			if r[0] != "extras":
				assert_eq(String(e.get("pose", "")), String(r[2]), "%s: pose matches its key" % where)
				assert_true((POSES if r[0] == "units" else RULER_POSES).has(String(r[2])), "%s: a known pose" % where)
			assert_true(float(e.get("body_men", 0.0)) > 0.0, "%s: body height in men" % where)
			assert_true(float(e.get("body_share", 0.0)) > 0.3 and float(e.get("body_share", 0.0)) <= 1.0, "%s: body share in (0.3, 1]" % where)
			assert_eq(String(size["axis"]), "length" if String(r[2]) == "fallen" else "height", "%s: a fallen figure is sized by its length" % where)


func test_every_unit_type_and_commander_has_all_four_poses() -> void:
	var units: Dictionary = _desc().get("units", {})
	var count := 0
	for f in FactionData.FACTIONS:
		var ids := []
		for u in f.unit_types:
			ids.append(String(u.id))
		ids.append(String(f.commander.id))
		for id in ids:
			count += 1
			assert_true(units.has(id), "%s has models" % id)
			if not units.has(id):
				continue
			var body := -1.0
			for pose in POSES:
				assert_true(units[id].has(pose), "%s has a %s pose" % [id, pose])
				if not units[id].has(pose):
					continue
				var e: Dictionary = units[id][pose]
				assert_eq(String(e["faction"]), String(f.id), "%s %s belongs to %s" % [id, pose, f.id])
				assert_eq(String(e["path"]), "res://assets/models/units/%s/%s_%s.glb" % [f.id, id, pose], "%s %s path" % [id, pose])
				if body < 0.0:
					body = float(e["body_men"])
				assert_eq(float(e["body_men"]), body, "%s: every pose has the same body height" % id)
	assert_eq(count, units.size(), "no models for unit types the data doesn't have")


func test_every_faction_has_its_army_extras() -> void:
	var extras: Dictionary = _desc().get("extras", {})
	if extras.is_empty():
		return
	for id in ["standard_bearer", "musician"]:
		for f in FactionData.FACTIONS:
			assert_true(extras.has(id) and extras[id].has(String(f.id)), "%s has a %s" % [f.id, id])
			if extras.has(id) and extras[id].has(String(f.id)):
				assert_eq(String(extras[id][String(f.id)]["path"]), "res://assets/models/units/%s/%s.glb" % [f.id, id])


func test_every_ruler_has_a_ready_and_a_strike_pose() -> void:
	var rulers: Dictionary = _desc().get("rulers", {})
	for r in RulerData.RULERS:
		var id := String(r.id)
		assert_true(rulers.has(id), "%s has models" % id)
		if not rulers.has(id):
			continue
		for pose in ["ready", "strike"]:
			assert_true(rulers[id].has(pose), "%s has a %s pose" % [id, pose])
		for pose in rulers[id]:
			var e: Dictionary = rulers[id][pose]
			assert_eq(String(e["faction"]), String(r.faction), "%s belongs to %s" % [id, r.faction])
			assert_eq(String(e["path"]), "res://assets/models/rulers/%s_%s.glb" % [id, pose])
	assert_eq(rulers.size(), RulerData.RULERS.size(), "no models for rulers the data doesn't have")


func test_every_faction_has_a_fortress_and_a_fort_with_a_yard_and_a_gate() -> void:
	var b: Dictionary = _desc().get("buildings", {})
	var forts := 0
	for p in MapData.PROVINCES:
		if p.has_fort:
			forts += 1
	assert_true(forts > 0, "the map has forts to stand these in")
	for f in FactionData.FACTIONS:
		for kind in ["fortress", "fort"]:
			var id := "%s_%s" % [kind, f.id]
			assert_true(b.has(id) and b[id].has(String(f.id)), "%s has a %s" % [f.id, kind])
			if not (b.has(id) and b[id].has(String(f.id))):
				continue
			var e: Dictionary = b[id][String(f.id)]
			assert_eq(String(e["size"]["axis"]), "width", "%s is sized by its width" % id)
			var yard: Dictionary = e.get("courtyard", {})
			assert_eq((yard.get("rect", []) as Array).size(), 4, "%s has a measured yard" % id)
			if (yard.get("rect", []) as Array).size() == 4:
				var r: Array = yard["rect"]
				assert_true(float(r[0]) < float(r[2]) and float(r[1]) < float(r[3]), "%s: the yard rect is ordered" % id)
				assert_true(float(r[0]) >= -0.5 and float(r[2]) <= 0.5 and float(r[1]) >= -0.5 and float(r[3]) <= 0.5, "%s: the yard is inside the footprint" % id)
				assert_true((float(r[2]) - float(r[0])) * (float(r[3]) - float(r[1])) >= 0.08, "%s: the yard is big enough to muster in" % id)
			var gate: Array = e.get("gate", [])
			assert_eq(gate.size(), 2, "%s has a gate point" % id)


func test_every_model_loads_as_one_textured_mesh_of_its_recorded_size() -> void:
	for r in _rows():
		var e: Dictionary = r[3]
		var where := "%s/%s/%s" % [r[0], r[1], r[2]]
		var scene: PackedScene = load(String(e["path"]))
		assert_true(scene != null, "%s loads" % where)
		if scene == null:
			continue
		var inst := scene.instantiate()
		var mi := _first_mesh(inst)
		assert_true(mi != null and mi.mesh != null, "%s has a mesh" % where)
		if mi != null and mi.mesh != null:
			var mesh: Mesh = mi.mesh
			assert_eq(mesh.get_surface_count(), 1, "%s: one surface" % where)
			var mat := mesh.surface_get_material(0)
			assert_true(mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null, "%s: an albedo texture" % where)
			if mat is BaseMaterial3D:
				assert_eq((mat as BaseMaterial3D).metallic, 0.0, "%s: matte (glb_slim --albedo-only)" % where)
			var idx: PackedInt32Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
			assert_eq(idx.size() / 3, int(e["faces"]), "%s: the face count matches the descriptor" % where)
			var aabb := mesh.get_aabb()
			var ext: Array = e["extent"]
			assert_true(absf(aabb.size.y - float(ext[1])) < 0.01, "%s: the extent matches the descriptor" % where)
		inst.free()


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for ch in n.get_children():
		var m := _first_mesh(ch)
		if m != null:
			return m
	return null


## The board reads world3d/models.json (world3d/models.gd): every unit type and ruler with models here
## stands on the board as its ready pose, and its row lists every pose GLB this batch installed.
func test_the_board_table_uses_the_ready_pose_and_lists_every_pose() -> void:
	var text := FileAccess.get_file_as_string("res://world3d/models.json")
	var board: Variant = JSON.parse_string(text)
	assert_true(board is Dictionary, "world3d/models.json parses")
	if not (board is Dictionary):
		return
	var figs: Dictionary = board.get("figures", {})
	for group in ["units", "rulers"]:
		var g: Dictionary = _desc().get(group, {})
		for id in g:
			assert_true(figs.has(id), "%s has a board row" % id)
			if not figs.has(id) or not g[id].has("ready"):
				continue
			var row: Dictionary = figs[id]
			assert_eq(String(row.get("model", "")), String(g[id]["ready"]["path"]), "%s stands on the board in its ready pose" % id)
			assert_true(is_equal_approx(float(row.get("height", 0.0)), float(g[id]["ready"]["size"]["men"])), "%s: the board height is the ready pose's height in men" % id)
			var poses: Dictionary = row.get("poses", {})
			for pose in g[id]:
				assert_eq(String(poses.get(pose, "")), String(g[id][pose]["path"]), "%s's board row lists its %s pose" % [id, pose])
