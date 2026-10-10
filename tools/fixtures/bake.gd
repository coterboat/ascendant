extends SceneTree
## Bakes a pose model and its attachments into one GLB (ART-PIPE 3, #196): the figure the board draws from a row's "attachments"
## (world3d/models.gd), written out as a file. One mesh, one colour map (the attachments' maps stacked under the body's), in the
## body's own coordinates, so it loads like any model of the game's (Models._load_first_mesh reads its first mesh and its map) and the
## Review Table's viewer shows it. Dev tool only. Headless is fine (no rendering).
##
##   $GODOT --headless --path . -s res://tools/fixtures/bake.gd -- --body=res://assets/models/.../strike.glb --pose=strike \
##       --row=/abs/row.json --out=/abs/combined.glb
##
## `--row` is a JSON file with the figure row's {"attachments": [...]} (the format is in world3d/models.gd's header); the same file
## is what a row of world3d/models.json would hold. The colour map is written as JPEG (quality 0.9). The GLB's size is not the
## body's: the blades add to its box, so a figure sized from it needs its own "pose_size" men (tools/ludo/asc_3d_fixtures.py
## `bake` measures it).

const Models := preload("res://world3d/models.gd")


func _initialize() -> void:
	var body := ""
	var pose := "ready"
	var row_path := ""
	var out := ""
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"body": body = kv[1]
			"pose": pose = kv[1]
			"row": row_path = kv[1]
			"out": out = kv[1]
	if body.is_empty() or row_path.is_empty() or out.is_empty():
		push_error("fixtures/bake: --body=res://x.glb --row=/abs/row.json --out=/abs/out.glb are required (--pose=ready|march|strike|fallen)")
		quit(2)
		return
	var row: Variant = JSON.parse_string(FileAccess.get_file_as_string(row_path))
	if not (row is Dictionary):
		push_error("fixtures/bake: %s is not a JSON object" % row_path)
		quit(2)
		return
	var problems := Models.attachment_problems("row", (row as Dictionary).get("attachments"))
	if not problems.is_empty():
		for p in problems:
			push_error("fixtures/bake: %s" % p)
		quit(2)
		return
	var baked := Models.baked_model(body, row, pose)
	if baked.is_empty():
		push_error("fixtures/bake: %s is not a model" % body)
		quit(2)
		return
	var root3 := Node3D.new()
	root3.name = "Figure"
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = baked["mesh"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = baked["tex"]
	m.metallic = 0.0
	m.roughness = 1.0
	mi.material_override = m
	root3.add_child(mi)
	var doc := GLTFDocument.new()
	doc.image_format = "JPEG"
	doc.lossy_quality = 0.9
	var state := GLTFState.new()
	var err := doc.append_from_scene(root3, state)
	if err == OK:
		err = doc.write_to_filesystem(state, out)
	root3.free()
	if err != OK:
		push_error("fixtures/bake: could not write %s (%s)" % [out, error_string(err)])
		quit(1)
		return
	var box: AABB = (baked["mesh"] as Mesh).get_aabb()
	var n := 0
	for a in Models.attachments_of(row, pose):
		n += 1
	print("baked %s: %d attachments, box position %s size %s -> %s" % [body, n, box.position, box.size, out])
	quit(0)
