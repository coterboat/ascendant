## The siege scenery of a battle at walls on the 3D stage (M3c S-5, #103; design/M3C_SIEGES.md 10.3): the ladders leaning on
## the gate-side wall (the Crown's storm) or the trunk lying before the gate (the Clans'), and the besiegers' camp beside their
## lines: a tent to an army with a fire by it, the siege works, and the engines the besiegers carry. None of it fights, takes a hit
## or changes a result: it is drawn from BattleWalls.plan's "scenery" and nothing else.
##
## Every piece is the model table's when it has one on disk (camp.<faction>, siege_works.<faction>, siege_engine.<faction>), else
## the code primitive of world3d/kit.gd, in one MultiMesh to a kind with the besiegers' colour on its team parts. `counts` says
## what is drawn now (tests): {"ladders", "trunk", "tents", "fires", "engines", "works"}.
extends Node3D

const Models := preload("res://world3d/models.gd")
const Kit := preload("res://world3d/kit.gd")
const SPAN := 2.0 ## a ladder's width
const TENT := 12.8 ## a camp model's width

var wv: Node3D ## the world's WorldView (its model material)
var counts := {}


## Takes the pieces of the last battle down.
func clear() -> void:
	for ch in get_children():
		ch.queue_free()
		remove_child(ch)
	counts = {}


## Draws `scenery` (BattleWalls.plan's walls.scenery) with `colour` (sRGB) on the team parts of the besiegers' pieces.
func build(scenery: Dictionary, colour: Color) -> void:
	clear()
	counts = {"ladders": 0, "trunk": 0, "tents": 0, "fires": 0, "engines": 0, "works": 0}
	if scenery.is_empty() or wv == null:
		return
	var style := String(scenery.get("style", ""))
	_ladders(scenery.get("ladders", []))
	if not (scenery.get("trunk", {}) as Dictionary).is_empty():
		var tr: Dictionary = scenery["trunk"]
		_pieces("siege_engine", style, [{"pos": tr["pos"], "yaw": tr["yaw"], "y": tr["y"]}], colour, 1.5)
		counts["trunk"] = 1
	_tents(scenery.get("tents", []), style, colour)
	_fires(scenery.get("fires", []))
	_pieces("siege_works", style, scenery.get("works", []), colour)
	counts["works"] = (scenery.get("works", []) as Array).size()
	_pieces("siege_engine", style, scenery.get("engines", []), colour)
	counts["engines"] = (scenery.get("engines", []) as Array).size()


## A ladder: two rails and rungs, standing on y with its length along +Y (built once; each is leant against the wall).
static func ladder_mesh(length: float) -> ArrayMesh:
	var b := Kit.Builder.new()
	for sx in [-0.5, 0.5]:
		b.box(Vector3(0.4, length, 0.4), Vector3(sx * SPAN, length * 0.5, 0.0), Kit.WOOD)
	var rungs := int(length / 0.9)
	for k in rungs:
		b.box(Vector3(SPAN, 0.28, 0.32), Vector3(0.0, 0.7 + float(k) * 0.9, 0.0), Kit.LEATHER)
	return b.mesh()


func _ladders(list: Array) -> void:
	if list.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = ladder_mesh(float(list[0]["len"]))
	mm.instance_count = list.size()
	for i in list.size():
		var l: Dictionary = list[i]
		var foot: Vector2 = l["foot"]
		var f3 := Vector3(foot.x, float(l["y"]), foot.y)
		var top: Vector3 = l["top"]
		var d := top - f3
		var up := d.normalized()
		## across the ladder: horizontal, square to its lean
		var side := Vector3(-d.z, 0.0, d.x).normalized()
		var fwd := side.cross(up)
		var sc: float = d.length() / float(l["len"])
		mm.set_instance_transform(i, Transform3D(Basis(side, up * sc, fwd), f3 - Vector3(0, 0.1, 0)))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Ladders"
	mi.multimesh = mm
	mi.material_override = wv.model_mat(Color.WHITE, null, -1.0, false, 0.92, Color.WHITE, 1.0)
	add_child(mi)
	counts["ladders"] = list.size()


## The model's mesh and scale for a building kind of `style`, or its primitive: {"mesh", "tex", "scale", "lift", "yaw", "key_hue"}.
func _piece(kind: String, style: String, side_default: float) -> Dictionary:
	var glb: Dictionary = Models.building_model(kind, style)
	var row: Dictionary = Models.building_row(kind, style)
	if glb.is_empty():
		return {"mesh": Models.building_primitive(kind, style), "tex": null, "scale": 1.0, "lift": Vector3.ZERO, "yaw": 0.0, "key_hue": -1.0}
	var aabb: AABB = glb["aabb"]
	var sc := float(row.get("side", side_default)) / maxf(maxf(aabb.size.x, aabb.size.z), 0.01)
	return {"mesh": glb["mesh"], "tex": glb["tex"], "scale": sc, "lift": Vector3(-aabb.get_center().x, -aabb.position.y, -aabb.get_center().z) * sc,
		"yaw": deg_to_rad(float(row.get("yaw", 180.0))), "key_hue": float(row.get("key_hue", -1.0))}


## `list` of {"pos": Vector2, "yaw", "y"} as one MultiMesh of building kind `kind` (siege works, engines, the trunk).
func _pieces(kind: String, style: String, list: Array, colour: Color, scale_by: float = 1.0) -> void:
	if list.is_empty():
		return
	var pc := _piece(kind, style, 10.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = pc["mesh"]
	mm.instance_count = list.size()
	for i in list.size():
		var e: Dictionary = list[i]
		var p: Vector2 = e["pos"]
		var yaw: float = float(e["yaw"]) + float(pc["yaw"])
		var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * float(pc["scale"]) * scale_by)
		mm.set_instance_transform(i, Transform3D(b, Vector3(p.x, float(e["y"]) - 0.1, p.y) + Basis(Vector3.UP, yaw) * (pc["lift"] as Vector3) * scale_by))
		mm.set_instance_custom_data(i, colour.srgb_to_linear())
	var mi := MultiMeshInstance3D.new()
	mi.name = "%s_%s" % [kind.capitalize().replace(" ", ""), style]
	mi.multimesh = mm
	mi.material_override = wv.model_mat(Color.WHITE, pc["tex"], float(pc["key_hue"]), true, 0.92, Color.WHITE, 1.0)
	add_child(mi)


## One tent to an army, the model table's camp (else the primitive tent) in the besiegers' colour.
func _tents(list: Array, style: String, colour: Color) -> void:
	if list.is_empty():
		return
	var glb: Dictionary = Models.building_model("camp", style)
	var row: Dictionary = Models.building_row("camp", style)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var sc := 1.0
	var lift := Vector3.ZERO
	var tex: Variant = null
	if not glb.is_empty():
		var aabb: AABB = glb["aabb"]
		mm.mesh = glb["mesh"]
		sc = TENT / maxf(maxf(aabb.size.x, aabb.size.z), 0.01) ## as the board's camps (Muster.SLOT's width)
		lift = Vector3(-aabb.get_center().x, -aabb.position.y, -aabb.get_center().z) * sc
		tex = glb["tex"]
	else:
		mm.mesh = Kit.tent(style)
	mm.instance_count = list.size()
	for i in list.size():
		var tn: Dictionary = list[i]
		var p: Vector2 = tn["pos"]
		var yaw: float = float(tn["yaw"]) + (deg_to_rad(float(row.get("yaw", 180.0))) if not glb.is_empty() else 0.0)
		var b := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc)
		mm.set_instance_transform(i, Transform3D(b, Vector3(p.x, float(tn["y"]) - 0.1, p.y) + Basis(Vector3.UP, yaw) * lift))
		mm.set_instance_custom_data(i, colour.srgb_to_linear())
	var mi := MultiMeshInstance3D.new()
	mi.name = "Tents"
	mi.multimesh = mm
	mi.material_override = wv.model_mat(Color.WHITE, tex, float(row.get("key_hue", -1.0)) if not glb.is_empty() else -1.0, true, 0.9, Color.WHITE, 1.0)
	add_child(mi)
	counts["tents"] = list.size()


func _fires(list: Array) -> void:
	if list.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = Kit.campfire()
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, Transform3D(Basis(), list[i]))
		mm.set_instance_custom_data(i, Color.WHITE)
	var mi := MultiMeshInstance3D.new()
	mi.name = "Fires"
	mi.multimesh = mm
	mi.material_override = wv.model_mat(Color.WHITE, null, -1.0, true)
	add_child(mi)
	counts["fires"] = list.size()
