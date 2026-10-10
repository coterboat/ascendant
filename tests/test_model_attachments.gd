extends "res://tests/test_case.gd"
## Attachments on the 3D figures (ART-PIPE 3, #196): a unit row of world3d/models.json may carry "attachments", fixtures (a thin blade,
## a wing, a held weapon) that are models of their own, drawn on a pose model at a per-pose position, rotation and scale; the loader in
## world3d/models.gd bakes them into the pose's mesh and stacks their colour maps under the body's. Nothing here reads an attachment
## from the installed table (no row has one): the body and the attachments are two installed models picked from the table by pose,
## and every expectation is computed from their own data.

const Models := preload("res://world3d/models.gd")
const Kit := preload("res://world3d/kit.gd")


func _body() -> String:
	return Models.pose_model_path("spearmen", "strike")


func _part() -> String:
	return Models.pose_model_path("crossbowmen", "ready")


## The unit row the figures are built from: the spearmen's, with whatever `extra` sets over it.
func _row(extra: Dictionary = {}) -> Dictionary:
	var row: Dictionary = Models.figure_row("spearmen").duplicate(true)
	row.erase("variants")
	for k in extra.keys():
		row[k] = extra[k]
	return row


func _entry(pivot: Array, poses: Dictionary, mesh: String = "") -> Dictionary:
	return {"mesh": mesh if not mesh.is_empty() else _part(), "pivot": pivot, "poses": poses}


func _arrays(path: String) -> Array:
	return (Models._load_first_mesh(path)["mesh"] as Mesh).surface_get_arrays(0)


## What models.gd does to a body (the documented sizing): the pose's size in men from its AABB, centred, feet on the floor, turned by yaw.
func _norm(row: Dictionary, pose: String, aabb: AABB) -> Transform3D:
	var size := Models.pose_size(row, pose)
	var along := aabb.size.y
	if String(size["axis"]) == "length":
		along = maxf(aabb.size.x, aabb.size.z)
	elif String(size["axis"]) == "width":
		along = minf(aabb.size.x, aabb.size.z)
	var s: float = float(size["men"]) * Kit.FIG / along
	var c: Vector3 = aabb.get_center()
	var yaw := deg_to_rad(float(row.get("yaw", 180.0)))
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3.ZERO) * Transform3D(Basis(), Vector3(-c.x, -aabb.position.y, -c.z))
	xf.origin += Vector3(0, 0.36, 0)
	return xf


func _built(row: Dictionary, pose: String) -> Dictionary:
	return Models._glb_figure(_body(), "spearmen", row, pose)


func _same_arrays(a: Mesh, b: Mesh) -> bool:
	var x: Array = a.surface_get_arrays(0)
	var y: Array = b.surface_get_arrays(0)
	for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
		if x[k] != y[k]:
			return false
	return true


func _near(a: Vector3, b: Vector3, tol: float = 0.0005) -> bool:
	return a.distance_to(b) <= tol


# --- rows without attachments build exactly as before ---------------------------------------------------

func test_a_row_without_attachments_builds_exactly_the_sized_turned_body() -> void:
	assert_true(ResourceLoader.exists(_body()) and ResourceLoader.exists(_part()), "the two models these tests use are installed")
	var row := _row()
	var built := _built(row, "strike")
	assert_eq(built["source"], "model", "it builds from the model")
	var src := Models._load_first_mesh(_body())
	assert_true(built["tex"] == src["tex"], "with the model's own colour map, not a copy")
	var arr: Array = (src["mesh"] as Mesh).surface_get_arrays(0)
	var xf := _norm(row, "strike", (src["mesh"] as Mesh).get_aabb())
	var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bv: PackedVector3Array = (built["mesh"] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_true(bv.size() > pv.size(), "the body's vertices, then the team base's")
	var off := 0.0
	for k in pv.size():
		off = maxf(off, (xf * pv[k]).distance_to(bv[k]))
	assert_true(off < 0.0005, "every body vertex is the model's, sized and turned by the documented rule (worst %.6f)" % off)
	var bu: PackedVector2Array = (built["mesh"] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var pu: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var du := 0.0
	for k in pu.size():
		du = maxf(du, pu[k].distance_to(bu[k]))
	assert_true(du < 0.00001, "and its texture coordinates are untouched (the colour map is the model's own)")


func test_empty_missing_or_other_pose_attachments_change_nothing() -> void:
	var plain := _built(_row(), "strike")
	var transform := {"pos": [0.1, 0.2, 0.3], "rot": [0, 45, 0], "scale": 0.5}
	var cases := {
		"an empty list": [],
		"an entry with a transform for another pose only": [_entry([0, 0, 0], {"march": transform})],
		"an entry whose mesh is not on disk": [_entry([0, 0, 0], {"strike": transform}, "res://assets/models/units/none/no_such_blade.glb")],
		"an entry with no poses": [{"mesh": _part()}],
		"an entry that is no object": ["blade"],
	}
	for name in cases.keys():
		var built := _built(_row({"attachments": cases[name]}), "strike")
		assert_true(_same_arrays(built["mesh"], plain["mesh"]), "%s builds the same mesh" % name)
		assert_true(built["tex"] == plain["tex"], "%s keeps the same colour map" % name)
	var bad := _built(_row({"attachments": "blade"}), "strike")
	assert_true(_same_arrays(bad["mesh"], plain["mesh"]), "attachments that are not a list are ignored too")


func test_installed_rows_name_no_attachment_that_does_not_load() -> void:
	assert_eq(Models.problems(), [], "every row of the installed table is sound, attachments included")
	for id in Models.table().get("figures", {}).keys():
		for pose in Models.POSES:
			for a in Models.figure_attachments(String(id), pose):
				assert_true(ResourceLoader.exists(String(a["mesh"])), "%s %s: an attachment's mesh is on disk" % [id, pose])


# --- a row with an attachment adds it at the given transform, per pose ----------------------------------

func test_an_attachment_is_added_to_the_pose_at_its_position_rotation_and_scale_about_its_pivot() -> void:
	var pose_t := {"pos": [0.30, 0.20, -0.10], "rot": [10.0, 90.0, -20.0], "scale": 0.6}
	var row := _row({"attachments": [_entry([0.05, -0.1, 0.0], {"strike": pose_t})]})
	var atts := Models.attachments_of(row, "strike")
	assert_eq(atts.size(), 1, "the entry counts for the pose it has a transform for")
	assert_eq(Models.attachments_of(row, "march").size(), 0, "and for no other pose")
	var src := Models._load_first_mesh(_body())
	var part := Models._load_first_mesh(_part())
	var body_arr: Array = (src["mesh"] as Mesh).surface_get_arrays(0)
	var part_arr: Array = (part["mesh"] as Mesh).surface_get_arrays(0)
	var merged := Models._with_attachments(body_arr, src["tex"], atts)
	assert_false(merged.is_empty(), "the body takes the attachment")
	var arr: Array = merged["arrays"]
	var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n_body := (body_arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var n_part := (part_arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	assert_eq(pv.size(), n_body + n_part, "one child's vertices after the body's")
	assert_eq((arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), (body_arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() + (part_arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), "and its triangles")
	## the transform: pivot to pos, turned by rot (degrees, Godot's Euler order), scaled, all about the pivot
	var expect := Transform3D(Basis.from_euler(Vector3(10.0, 90.0, -20.0) * (PI / 180.0)) * Basis.from_scale(Vector3.ONE * 0.6), Vector3(0.30, 0.20, -0.10))
	var worst := 0.0
	var av: PackedVector3Array = part_arr[Mesh.ARRAY_VERTEX]
	for k in n_part:
		var want: Vector3 = expect * (av[k] - Vector3(0.05, -0.1, 0.0))
		worst = maxf(worst, want.distance_to(pv[n_body + k]))
	assert_true(worst < 0.0005, "each of its vertices is where the transform puts it (worst %.6f)" % worst)
	assert_true(_near(Models.attachment_transform(pose_t, Vector3(0.05, -0.1, 0.0)) * Vector3(0.05, -0.1, 0.0), Vector3(0.30, 0.20, -0.10)), "the pivot lands on pos")
	assert_true((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).slice(0, n_body) == body_arr[Mesh.ARRAY_VERTEX], "the body's own vertices are untouched")
	## a scale of three numbers stretches one axis
	var flat := Models.attachment_transform({"scale": [2.0, 1.0, 0.5]})
	assert_true(_near(flat * Vector3(1, 1, 1), Vector3(2.0, 1.0, 0.5)), "a scale of [x, y, z] stretches each axis")


func test_the_attachment_stands_on_the_board_figure_in_the_bodys_size_and_turn() -> void:
	var pose_t := {"pos": [0.25, 0.15, 0.05], "rot": [0, 30, 0], "scale": 0.5}
	var row := _row({"attachments": [_entry([0, 0, 0], {"strike": pose_t})]})
	var plain := _built(_row(), "strike")
	var with_att := _built(row, "strike")
	var src := Models._load_first_mesh(_body())
	var xf := _norm(row, "strike", (src["mesh"] as Mesh).get_aabb())
	var part_v: PackedVector3Array = _arrays(_part())[Mesh.ARRAY_VERTEX]
	var attach := Models.attachment_transform(pose_t)
	## the figure is sized from the body alone: the body's box is what it was, and the attachment's vertices are inside the figure's box
	var box: AABB = (with_att["mesh"] as Mesh).get_aabb()
	assert_true(box.encloses((plain["mesh"] as Mesh).get_aabb()), "the figure with the attachment holds the figure without it")
	var worst_out := 0.0
	for k in part_v.size():
		var p: Vector3 = xf * (attach * part_v[k])
		var q := p.clamp(box.position, box.end)
		worst_out = maxf(worst_out, p.distance_to(q))
	assert_true(worst_out < 0.0005, "every attachment vertex is inside the figure's box, at the body's scale and turn (%.6f out)" % worst_out)
	var nv_plain := ((plain["mesh"] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var nv_with := ((with_att["mesh"] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	assert_eq(nv_with - nv_plain, part_v.size(), "the figure has the attachment's vertices more than the plain one")
	assert_ne(with_att["tex"], plain["tex"], "its colour map is the stack of the two")
	assert_eq(with_att["source"], "model", "and it is still a model figure")


func test_each_pose_carries_its_own_transform() -> void:
	var a := {"pos": [0.30, 0.2, 0.0], "rot": [0, 0, 0], "scale": 0.5}
	var b := {"pos": [-0.2, 0.4, 0.1], "rot": [0, 180, 0], "scale": 0.25}
	var entry := _entry([0, 0, 0], {"strike": a, "march": b})
	var row := _row({"attachments": [entry]})
	var xs := Models.attachments_of(row, "strike")
	var xm := Models.attachments_of(row, "march")
	assert_eq(xs.size(), 1, "strike has it")
	assert_eq(xm.size(), 1, "march has it")
	assert_true((xs[0]["xf"] as Transform3D).origin.is_equal_approx(Vector3(0.30, 0.2, 0.0)), "at the strike transform")
	assert_true((xm[0]["xf"] as Transform3D).origin.is_equal_approx(Vector3(-0.2, 0.4, 0.1)), "and the march one")
	assert_eq(Models.attachments_of(row, "fallen").size(), 0, "a pose the entry names no transform for gets none")
	var s := Models._glb_figure(_body(), "spearmen", row, "strike")
	var m := Models._glb_figure(_body(), "spearmen", row, "march")
	assert_ne(((s["mesh"] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array), ((m["mesh"] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array), "the two poses' meshes put it in different places")


func test_the_colour_maps_are_stacked_under_the_bodys_and_the_bodys_pixels_stay() -> void:
	var t := {"pos": [0.2, 0.1, 0.0], "scale": 0.5}
	var src := Models._load_first_mesh(_body())
	var part := Models._load_first_mesh(_part())
	var body_img := Models._rgba_image(src["tex"])
	var part_img := Models._rgba_image(part["tex"])
	var w := body_img.get_width()
	var ph := maxi(1, int(round(float(part_img.get_height()) * float(w) / float(part_img.get_width()))))
	var merged := Models._with_attachments(_arrays(_body()), src["tex"], Models.attachments_of(_row({"attachments": [_entry([0, 0, 0], {"strike": t})]}), "strike"))
	var tex: Texture2D = merged["tex"]
	assert_eq(tex.get_width(), w, "the stack is as wide as the body's colour map")
	assert_eq(tex.get_height(), body_img.get_height() + ph, "and as tall as both, the attachment's scaled to that width")
	var stack := tex.get_image()
	var has_mips := stack.has_mipmaps()
	stack.clear_mipmaps()
	assert_true(stack.get_region(Rect2i(0, 0, w, body_img.get_height())).get_data() == body_img.get_data(), "the body's pixels are as they were")
	var arr: Array = merged["arrays"]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var n_body := (_arrays(_body())[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var split := float(body_img.get_height()) / float(tex.get_height())
	var body_u: PackedVector2Array = _arrays(_body())[Mesh.ARRAY_TEX_UV]
	for k in range(0, n_body, maxi(1, n_body / 200)):
		assert_true(uv[k].y <= split + 0.00001 and is_equal_approx(uv[k].x, body_u[k].x), "body vertex %d reads the stack's top part, at the same u" % k)
	for k in range(n_body, uv.size(), maxi(1, (uv.size() - n_body) / 200)):
		assert_true(uv[k].y >= split - 0.00001 and uv[k].y <= 1.00001, "attachment vertex %d reads the stack's lower part" % k)
	assert_true(has_mips, "and it has its mipmaps, as a far figure is drawn from them")


func test_one_mesh_used_twice_is_loaded_and_stacked_once() -> void:
	var t1 := {"pos": [0.2, 0.1, 0.0], "scale": 0.5}
	var t2 := {"pos": [-0.2, 0.1, 0.0], "rot": [0, 0, 180], "scale": 0.4}
	var once := Models.attachments_of(_row({"attachments": [_entry([0, 0, 0], {"strike": t1})]}), "strike")
	var twice := Models.attachments_of(_row({"attachments": [_entry([0, 0, 0], {"strike": t1}), _entry([0, 0, 0], {"strike": t2})]}), "strike")
	assert_eq(twice.size(), 2, "two entries, two children")
	var src := Models._load_first_mesh(_body())
	var one := Models._with_attachments(_arrays(_body()), src["tex"], once)
	var two := Models._with_attachments(_arrays(_body()), src["tex"], twice)
	var n_part := (_arrays(_part())[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	assert_eq((two["arrays"][Mesh.ARRAY_VERTEX] as PackedVector3Array).size() - (one["arrays"][Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), n_part, "the second child adds its vertices")
	assert_eq((two["tex"] as Texture2D).get_height(), (one["tex"] as Texture2D).get_height(), "but not another copy of its colour map")


func test_the_baked_model_is_the_figures_arrays_in_the_models_own_space() -> void:
	var t := {"pos": [0.2, 0.1, 0.0], "rot": [0, 20, 0], "scale": 0.5}
	var row := _row({"attachments": [_entry([0, 0, 0], {"strike": t})]})
	var plain := Models.baked_model(_body(), row, "march")
	assert_true(((plain["mesh"] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array) == (_arrays(_body())[Mesh.ARRAY_VERTEX] as PackedVector3Array), "a pose with no attachment bakes to the model itself")
	var baked := Models.baked_model(_body(), row, "strike")
	var bv: PackedVector3Array = (baked["mesh"] as Mesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var n_body := (_arrays(_body())[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var part_v: PackedVector3Array = _arrays(_part())[Mesh.ARRAY_VERTEX]
	assert_eq(bv.size(), n_body + part_v.size(), "the model's vertices and the attachment's")
	assert_true(_near(bv[n_body], Models.attachment_transform(t) * part_v[0]), "the attachment's in the model's own coordinates, not the board's")
	assert_eq(Models.baked_model("res://assets/models/units/none/no_such_model.glb", row, "strike"), {}, "a path that is no model bakes to nothing")


# --- the table: a row names them, every place that builds a figure gets them --------------------------

func test_a_table_row_with_attachments_changes_only_its_own_pose() -> void:
	var keep: Dictionary = Models.table().duplicate(true)
	var t := {"pos": [0.2, 0.1, 0.0], "scale": 0.5}
	Models.clear_cache()
	var ready_before: Mesh = Models.figure_mesh("spearmen", true, "ready")["mesh"]
	var strike_before: Mesh = Models.figure_mesh("spearmen", true, "strike")["mesh"]
	var other_before: Mesh = Models.figure_mesh("crossbowmen", true, "strike")["mesh"]
	var table := keep.duplicate(true)
	table["figures"]["spearmen"]["attachments"] = [{"mesh": _part(), "poses": {"strike": t}}]
	Models.clear_cache()
	Models._table = table
	assert_eq(Models.problems(), [], "the row with attachments is sound")
	var strike: Dictionary = Models.figure_mesh("spearmen", true, "strike")
	assert_ne(strike["mesh"].get_aabb(), strike_before.get_aabb(), "the strike pose draws it (its box grew)")
	assert_true(Models.has_pose_model("spearmen", "strike"), "as the pose's own model")
	assert_true(_same_arrays(Models.figure_mesh("spearmen", true, "ready")["mesh"], ready_before), "the ready pose is as it was")
	assert_true(_same_arrays(Models.figure_mesh("crossbowmen", true, "strike")["mesh"], other_before), "and so is every other unit's")
	assert_eq(Models.figure_attachments("spearmen", "strike").size(), 1, "the table lookup finds it")
	assert_eq(Models.figure_attachments("spearmen", "ready").size(), 0, "for its pose only")
	Models.clear_cache()
	assert_true(_same_arrays(Models.figure_mesh("spearmen", true, "strike")["mesh"], strike_before), "put back, the table gives the same figure again")


func test_a_variant_may_carry_its_own_attachments() -> void:
	var keep: Dictionary = Models.table().duplicate(true)
	var t := {"pos": [0.2, 0.1, 0.0], "scale": 0.5}
	var table := keep.duplicate(true)
	var variants: Dictionary = (table["figures"]["spearmen"] as Dictionary).get("variants", {})
	assert_false(variants.is_empty(), "the spearmen have a look (the Sunspears) to give attachments to")
	var vid := String(variants.keys()[0])
	Models.clear_cache()
	var base_strike: Mesh = Models.figure_mesh("spearmen", true, "strike")["mesh"]
	var var_strike_before: Mesh = Models.figure_mesh("spearmen", true, "strike", "", vid)["mesh"]
	(table["figures"]["spearmen"]["variants"][vid] as Dictionary)["attachments"] = [{"mesh": _part(), "poses": {"strike": t}}]
	Models.clear_cache()
	Models._table = table
	assert_eq(Models.problems(), [], "a variant's attachments are checked and sound")
	assert_eq(Models.figure_attachments("spearmen", "strike", vid).size(), 1, "the look wears them")
	assert_eq(Models.figure_attachments("spearmen", "strike").size(), 0, "and the plain row does not")
	assert_ne(Models.figure_mesh("spearmen", true, "strike", "", vid)["mesh"].get_aabb(), var_strike_before.get_aabb(), "the look's strike pose grew")
	assert_true(_same_arrays(Models.figure_mesh("spearmen", true, "strike")["mesh"], base_strike), "the plain unit's strike pose did not")
	## and the other way: a row's attachments are placed on the row's own models, so a look (its own models) does not wear them
	var table2 := keep.duplicate(true)
	table2["figures"]["spearmen"]["attachments"] = [{"mesh": _part(), "poses": {"strike": t}}]
	Models.clear_cache()
	Models._table = table2
	assert_eq(Models.figure_attachments("spearmen", "strike").size(), 1, "the plain row wears its own")
	assert_eq(Models.figure_attachments("spearmen", "strike", vid).size(), 0, "a look with none of its own wears none of the row's")
	Models.clear_cache()


# --- problems() names a bad attachment in plain words ---------------------------------------------------

func test_problems_names_what_is_wrong_with_an_attachment() -> void:
	var good := [{"mesh": _part(), "pivot": [0, 0, 0], "poses": {"strike": {"pos": [0, 0, 0], "rot": [0, 0, 0], "scale": 1.0}}}]
	assert_eq(Models.attachment_problems("row", good), [], "a sound entry has no problems")
	assert_eq(Models.attachment_problems("row", null), [], "no attachments, no problems")
	assert_eq(Models.attachment_problems("row", []), [], "an empty list, no problems")
	var bad := {
		"not a list": "blade",
		"an entry that is no object": ["blade"],
		"a mesh that is missing": [{"mesh": "res://assets/models/units/none/gone.glb", "poses": {"strike": {}}}],
		"no mesh": [{"poses": {"strike": {}}}],
		"no poses": [{"mesh": _part()}],
		"a pose no figure has": [{"mesh": _part(), "poses": {"dance": {}}}],
		"a transform that is no object": [{"mesh": _part(), "poses": {"strike": 3}}],
		"a position of two numbers": [{"mesh": _part(), "poses": {"strike": {"pos": [1, 2]}}}],
		"a rotation that is a word": [{"mesh": _part(), "poses": {"strike": {"rot": "left"}}}],
		"a scale of zero": [{"mesh": _part(), "poses": {"strike": {"scale": 0}}}],
		"a scale of two numbers": [{"mesh": _part(), "poses": {"strike": {"scale": [1, 2]}}}],
		"a pivot of one number": [{"mesh": _part(), "pivot": [1], "poses": {"strike": {}}}],
	}
	for name in bad.keys():
		assert_true(not Models.attachment_problems("row", bad[name]).is_empty(), "%s is reported" % name)
	var text: String = Models.attachment_problems("figure bloodsworn", [{"mesh": _part(), "poses": {"dance": {}}}])[0]
	assert_true(text.begins_with("figure bloodsworn attachment 0: ") and text.contains("dance"), "in words that say which row, which entry and what (%s)" % text)
