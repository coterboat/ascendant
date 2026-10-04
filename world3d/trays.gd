## The forest trays (#125): every army standing in a forest province stands on movement trays, one under each
## block and one under its command group, in its owner's colour on an ink rim (a ruler's army adds the gilt
## ring, as its stand does). Woods-green figures, the Thorn Wild's Briarwardens and Thornthrowers above all,
## read as small trees on canopy-green ground: a hue problem that a brighter texture only washes out (#129).
## A tray puts the owner's colour round every block and its rim draws the block's edge, whatever the figures
## wear. Off the woods the ground is not the figures' green, so the board stays as it was.
##
## The board drives it (Board3D._camera): step(armies) once a frame rebuilds only when the armies change
## (a new state, a plan, the end of a playback, a quality rung's musicians). The trays stand aside while a
## turn plays (the figures march off their places) and once the far-zoom stands (stands.gd) have most of
## the blend.
## Pure reads of armies.gd's entries; it never changes them. Draw cost: one mesh for every tray on the board.
extends Node3D

const Kit := preload("res://world3d/kit.gd")

const TERRAINS := ["forest"] ## where the trays go
const MARGIN := 0.45 ## the tray reaches this far past its outer figures' slots (blocks stand 2 apart, ranks 1)
const RIM := 0.6 ## the ink rim's width
const GILT := 0.3 ## a ruler's army's gilt ring, inside the rim
const CORNER := 1.0 ## the corners' radius
const TOP := 0.16 ## the tray's top above its figures' feet (the bases stand 0.38 tall), clear of the ground
const STEP := 0.03 ## the rim and the gilt ring step down this much each from the top
const DEPTH := 0.8 ## it reaches this far under the feet, so a slope never shows under it
const SHOW_AT := 0.5 ## the figures' share (armies.gd blend) under which the stands have the board
const LINK_GAP := 2.5 ## figures of a group this much farther apart than their spacing stand on separate trays
const SHADE := 0.3 ## the tray's top is the owner's colour this much darker, so each figure's own base still pops
const INK := Color("#1A1612")

var wv: Node3D ## world_view.gd
var enabled := true
var trays := {} ## army id -> [{"centre": Vector2, "size": Vector2, "yaw", "y", "colour", "ruler", "types"}]
var _mi: MeshInstance3D
var _mat: Material
var _sig := ""


func _init() -> void:
	name = "Trays"
	visible = false


## One frame: rebuilds the trays when the armies changed, and hides them while a turn plays or the stands
## have the board.
func step(armies: Node3D) -> void:
	var show: bool = enabled and armies.state != null and armies.blend > SHOW_AT and not armies.playing()
	var sig := "%s|%d|%s|%d|%d" % [show, armies.state.get_instance_id() if armies.state != null else 0, armies._plan_key,
		armies.armies.size(), armies.figure_count()]
	if sig == _sig:
		return
	_sig = sig
	visible = show
	if show:
		rebuild(armies)


## Every forest army's trays, from where its figures stand now, into one mesh.
func rebuild(armies: Node3D) -> void:
	trays = {}
	var st: GameState = armies.state
	for id in armies.armies.keys():
		var e: Dictionary = armies.armies[id]
		if bool(e.get("ghost", false)) or not in_woods(st, String(e["province"])):
			continue
		var list := trays_of(e, func(t: String) -> Vector2: return armies._spacing(t) * 0.5)
		if not list.is_empty():
			trays[id] = list
	_draw_trays()


func tray_count() -> int:
	var n := 0
	for list in trays.values():
		n += (list as Array).size()
	return n


static func in_woods(st: GameState, province_id: String) -> bool:
	var p: Province = st.find_province(province_id) if st != null else null
	return p != null and TERRAINS.has(p.terrain)


## An army entry's trays (pure): its figures grouped by block (a unit type's figures; the commander, ruler,
## bearer and musician together), each group split where its figures stand apart (a front-rank ruler, a
## column's pairs), and a rounded box round each, in the figures' own frame. `reach` gives a type's slot,
## half its spacing either way (a block is its slots: Kit.formation_blocks), so one army's trays stand apart,
## as a tabletop's movement trays do. (A figure wider than its slot, a Briarwarden's canopy, overhangs its
## tray as a miniature does; growing the tray to it would merge the blocks' trays, and gains a unit or so.)
static func trays_of(e: Dictionary, reach: Callable) -> Array:
	var groups := {}
	var order: Array = []
	for f in e["figs"]:
		if float(f["scale"]) < 0.05 or float(f["fall"]) > 0.5:
			continue
		var key := "u:" + String(f["type"]) if String(f["role"]) == "unit" else "command"
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		groups[key].append(f)
	var out: Array = []
	for key in order:
		for cluster in _clusters(groups[key], reach):
			out.append(_tray_round(cluster, reach, e))
	return out


## Splits `figs` into runs of figures standing near each other (a figure joins a run when it stands within
## its own and its neighbour's reach, plus LINK_GAP).
static func _clusters(figs: Array, reach: Callable) -> Array:
	var seen := {}
	var out: Array = []
	for i in figs.size():
		if seen.has(i):
			continue
		seen[i] = true
		var run: Array = [figs[i]]
		var q: Array = [i]
		while not q.is_empty():
			var a: int = q.pop_back()
			var pa: Vector2 = figs[a]["pos"]
			var sa: Vector2 = (reach.call(String(figs[a]["type"])) as Vector2) * 2.0
			for j in figs.size():
				if seen.has(j):
					continue
				var sb: Vector2 = (reach.call(String(figs[j]["type"])) as Vector2) * 2.0
				if pa.distance_to(figs[j]["pos"]) <= 0.5 * (maxf(sa.x, sa.y) + maxf(sb.x, sb.y)) + LINK_GAP:
					seen[j] = true
					run.append(figs[j])
					q.append(j)
		out.append(run)
	return out


static func _tray_round(figs: Array, reach: Callable, e: Dictionary) -> Dictionary:
	var yaw: float = figs[0]["yaw"]
	var u := Vector2(cos(yaw), -sin(yaw))
	var v := Vector2(sin(yaw), cos(yaw))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var y := INF
	for f in figs:
		var p: Vector2 = f["pos"]
		var half: Vector2 = reach.call(String(f["type"]))
		var q := Vector2(p.dot(u), p.dot(v))
		lo = Vector2(minf(lo.x, q.x - half.x), minf(lo.y, q.y - half.y))
		hi = Vector2(maxf(hi.x, q.x + half.x), maxf(hi.y, q.y + half.y))
		y = minf(y, float(f["y"]))
	var mid := (lo + hi) * 0.5
	var types: Array = []
	for f in figs:
		if not types.has(f["type"]):
			types.append(f["type"])
	return {"centre": u * mid.x + v * mid.y, "size": hi - lo + Vector2.ONE * MARGIN * 2.0, "yaw": yaw, "y": y,
		"colour": e["colour"], "ruler": bool(e.get("ruler", false)), "types": types}


func _draw_trays() -> void:
	if _mi == null:
		_mi = MeshInstance3D.new()
		_mi.name = "TrayMesh"
		_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mi)
	if tray_count() == 0:
		_mi.mesh = null
		return
	var b := Kit.Builder.new()
	for list in trays.values():
		for t in list:
			_add_tray(b, t)
	_mi.mesh = b.mesh()
	if _mat == null:
		_mat = wv.model_mat(Color.WHITE) if wv != null else StandardMaterial3D.new()
	_mi.material_override = _mat


## A tray into `b`: its ink rim, a ruler's gilt ring, its top in the owner's colour (SHADE darker), each a rounded box.
static func _add_tray(b: Kit.Builder, t: Dictionary) -> void:
	var size: Vector2 = t["size"]
	var c: Vector2 = t["centre"]
	var xf := Transform3D(Basis(Vector3.UP, float(t["yaw"])), Vector3(c.x, float(t["y"]), c.y))
	var bottom := -DEPTH
	_rounded(b, xf, size, CORNER, bottom, TOP - STEP * 2.0, INK)
	var inset := RIM
	if bool(t["ruler"]):
		_rounded(b, xf, size - Vector2.ONE * RIM * 2.0, CORNER - RIM, bottom, TOP - STEP, Kit.GOLD)
		inset += GILT
	_rounded(b, xf, size - Vector2.ONE * inset * 2.0, CORNER - inset, bottom, TOP, (t["colour"] as Color).darkened(SHADE))


## A rounded box `size` across (x) and deep (z) between heights `y0` and `y1`, its corners `r` round, placed
## by `xf`: two crossed boxes and four corner cylinders.
static func _rounded(b: Kit.Builder, xf: Transform3D, size: Vector2, r: float, y0: float, y1: float, col: Color) -> void:
	r = clampf(r, 0.05, minf(size.x, size.y) * 0.5 - 0.01)
	var h := y1 - y0
	var ym := (y0 + y1) * 0.5
	var bx := BoxMesh.new()
	bx.size = Vector3(size.x - r * 2.0, h, size.y)
	b.add(bx, xf * Transform3D(Basis(), Vector3(0, ym, 0)), col)
	var bz := BoxMesh.new()
	bz.size = Vector3(size.x, h, size.y - r * 2.0)
	b.add(bz, xf * Transform3D(Basis(), Vector3(0, ym, 0)), col)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var cy := CylinderMesh.new()
			cy.top_radius = r
			cy.bottom_radius = r
			cy.height = h
			cy.radial_segments = 8
			cy.rings = 1
			b.add(cy, xf * Transform3D(Basis(), Vector3(sx * (size.x * 0.5 - r), ym, sz * (size.y * 0.5 - r))), col)
