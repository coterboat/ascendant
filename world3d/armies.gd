## The armies on the 3D map (spike). The figures ARE the army markers: every army stands as a
## formation of miniatures (a company block of figures per unit, its commander and a banner bearer
## in front, every base painted in the owner's colour, the banner in the owner's colour and emblem).
##
## Where they stand (arrange()):
##   * at a capital: mustered in the fortress's courtyard, facing the gate; armies that don't fit
##     stand ready outside the gate, facing out along the roads;
##   * elsewhere: on the province's stage, facing its roads.
## Turn playback (play_turn()): every army_moved event of a real TurnResolver turn files out (out of
## the gate in a column two abreast, a toy's hop in the step), marches the road over the border, and
## re-forms in its new place; armies that fell in battle topple; armies that stay re-form.
##
## Figures are drawn with one MultiMesh per army and unit type (one draw, plus its outline).
extends Node3D

const Kit := preload("res://world3d/kit.gd")
const Scenario := preload("res://world3d/scenario.gd")
const SPEED := 16.0 ## march speed, world units a second
const GAP := 4.4 ## between pairs in a column
const LANE := 1.7 ## half the column's width
const PROBE := {"spearmen": ["res://assets/models/probe/spearman.glb", 7.8], "tuskers": ["res://assets/models/probe/tusker.glb", 7.4]}

signal playback_done

var wv: Node3D ## world_view.gd
var use_probe := false ## the Ludo probe's spearman and tusker instead of the primitive figures
var state: GameState
var seats: Array = []
var armies := {} ## army id -> {"owner", "colour", "emblem", "slots", "figs": [{"type","mm","i","pos","yaw","y"}], "banner", "province"}
var _meshes := {} ## type id -> Mesh
var _probe_tex := {} ## type id -> Texture2D
var _play: Dictionary = {} ## the playback under way
var clock := 0.0
var fig_scale := 1.0 ## toy scale: figures stand taller when the camera is far, so the army reads


## Sets the toy scale (the preview eases it with the zoom) and restands every figure.
func set_fig_scale(v: float) -> void:
	if absf(v - fig_scale) < 0.01:
		return
	fig_scale = v
	for e in armies.values():
		_sync(e)


func _ready() -> void:
	set_process(true)


# ------------------------------------------------------------------ standing armies

## Stands every army of `s` in its place (no animation).
func show_state(s: GameState, p_seats: Array) -> void:
	state = s
	seats = p_seats
	_play = {}
	for id in armies.keys():
		_free_army(id)
	armies.clear()
	var places: Dictionary = arrange(s)
	for a in s.armies:
		_make_army(a, places[a.id])


## Where every army's figures stand in `s`: army id -> [{"type", "role", "pos": Vector2, "yaw": float, "y": float}].
func arrange(s: GameState) -> Dictionary:
	var out := {}
	var by_prov := {}
	for a in s.armies:
		if not by_prov.has(a.location):
			by_prov[a.location] = []
		by_prov[a.location].append(a)
	for pid in by_prov.keys():
		var list: Array = by_prov[pid]
		list.sort_custom(func(x, y): return x.id < y.id)
		var t = wv.terrain
		var c: Vector2 = t.centre_of(pid)
		var in_fort: bool = wv.fortresses.has(pid)
		var facing: Vector2 = wv.gate_dir(pid)
		var origin: Vector2
		var max_w := 44.0
		var room := 1.0e9
		var floor_y: float = t.stage_h[t.index_of(pid)]
		if in_fort:
			floor_y += float(wv.fortresses[pid]["floor"]) - 0.25
			var ct: Array = wv.courtyard(pid)
			origin = ct[0]
			facing = ct[1]
			max_w = ct[2]
			room = ct[3]
		else:
			## stand a little back from the centre so the front faces the roads with room before it
			origin = c + facing * 10.0
		var depth := 0.0
		var out_depth := 0.0
		var full := false ## the courtyard is full: later armies stand outside the gate
		for a in list:
			var slots: Array = Kit.formation(Scenario.unit_types(a), Scenario.commander_type(a), max_w)
			var d: float = Kit.formation_depth(slots)
			var basis := Basis.looking_at(Vector3(facing.x, 0, facing.y), Vector3.UP)
			var placed: Array = []
			var spill := 0.0
			for sl in slots:
				var lp: Vector2 = sl["pos"]
				var z: float = depth + lp.y
				var p: Vector2
				var y: float
				if in_fort and (full or z > room):
					## no room left in the courtyard: these rows stand ready outside the gate
					var g: Array = wv.gate_points(pid)
					var zo: float = lp.y if full else z - room
					var w3o: Vector3 = basis * Vector3(lp.x, 0, -zo)
					p = (g[1] as Vector2) + facing * (6.0 + out_depth) + Vector2(w3o.x, w3o.z)
					y = t.height_at(p)
					spill = maxf(spill, zo)
				else:
					var w3: Vector3 = basis * Vector3(lp.x, 0, z)
					p = origin + Vector2(w3.x, w3.z)
					y = (floor_y + 0.25) if in_fort else t.height_at(p)
				placed.append({"type": sl["type"], "role": sl["role"], "pos": p, "yaw": atan2(-facing.x, -facing.y), "y": y})
			depth += d + 2.0
			if spill > 0.0:
				out_depth += spill + 3.0
				full = true
			out[a.id] = placed
	return out


func _make_army(a: Army, placed: Array) -> void:
	var seat: int = UiPalette.seat_index(state, a.owner, seats)
	var col: Color = UiPalette.seat_color(seat)
	var e := {"owner": a.owner, "colour": col, "emblem": maxi(seat, 0), "figs": [], "mms": {}, "province": a.location,
		"units": a.units.size(), "has_commander": a.commander != null or a.ruler != null}
	## count figures per type, then fill one MultiMesh per type
	var count := {}
	for sl in placed:
		count[sl["type"]] = int(count.get(sl["type"], 0)) + 1
	for t in count.keys():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _mesh(t)
		mm.instance_count = count[t]
		var mi := MultiMeshInstance3D.new()
		mi.name = "%s_%s" % [a.id, t]
		mi.multimesh = mm
		var tex: Texture2D = _probe_tex.get(t) if use_probe else null
		mi.material_override = wv.model_mat(col, tex, -1.0, true)
		add_child(mi)
		e["mms"][t] = {"mi": mi, "next": 0}
	var lin: Color = col.srgb_to_linear()
	for sl in placed:
		var slot: Dictionary = e["mms"][sl["type"]]
		var i: int = slot["next"]
		slot["next"] = i + 1
		(slot["mi"].multimesh as MultiMesh).set_instance_custom_data(i, lin)
		e["figs"].append({"type": sl["type"], "role": sl["role"], "mm": slot["mi"].multimesh, "i": i,
			"pos": sl["pos"], "yaw": sl["yaw"], "y": sl["y"], "hop": 0.0, "tilt": 0.0, "fall": 0.0, "scale": 1.0})
	## the banner, carried by the bearer
	var bn: Node3D = wv.make_banner(col, maxi(seat, 0), 11.0, Vector2(5.2, 3.4))
	add_child(bn)
	e["banner"] = bn
	armies[a.id] = e
	_sync(e)


func _free_army(id: String) -> void:
	var e: Dictionary = armies[id]
	for t in e["mms"].keys():
		(e["mms"][t]["mi"] as Node).queue_free()
	(e["banner"] as Node).queue_free()


func _mesh(t: String) -> Mesh:
	var key: String = t + ("_probe" if use_probe and PROBE.has(t) else "")
	if _meshes.has(key):
		return _meshes[key]
	var m: Mesh = null
	if use_probe and PROBE.has(t):
		m = _probe_mesh(t)
	if m == null:
		m = Kit.figure(t)
	_meshes[key] = m
	return m


## A probe GLB as a figure: scaled from its AABB to a man's height (the spear's tip for a
## spearman), feet on y = 0, turned to face -Z, its texture kept, a base in the owner's colour.
func _probe_mesh(t: String) -> Mesh:
	var path: String = PROBE[t][0]
	if not ResourceLoader.exists(path):
		return null
	var inst: Node = (load(path) as PackedScene).instantiate()
	var mi: MeshInstance3D = wv._first_mesh(inst)
	if mi == null:
		inst.free()
		return null
	var src: Mesh = mi.mesh
	var sm := src.surface_get_material(0)
	if sm is BaseMaterial3D:
		_probe_tex[t] = (sm as BaseMaterial3D).albedo_texture
	inst.free()
	var aabb: AABB = src.get_aabb()
	var s: float = float(PROBE[t][1]) / aabb.size.y
	var c: Vector3 = aabb.get_center()
	var xf := Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * s), Vector3.ZERO) * Transform3D(Basis(), Vector3(-c.x, -aabb.position.y, -c.z))
	xf.origin += Vector3(0, 0.36, 0)
	var arr: Array = src.surface_get_arrays(0)
	var b := Kit.Builder.new()
	var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var puv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var pi: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for k in pv.size():
		b.v.append(xf * pv[k])
		b.n.append((xf.basis * pn[k]).normalized())
		b.c.append(Color(1, 1, 1, 1))
		b.uv.append(puv[k])
	for k in pi:
		b.idx.append(k)
	Kit._base(b, t)
	return b.mesh()


## Writes a figure's state into its MultiMesh, and the banner onto the bearer.
func _sync(e: Dictionary) -> void:
	var t = wv.terrain
	for f in e["figs"]:
		var p: Vector2 = f["pos"]
		var basis := Basis(Vector3.UP, f["yaw"])
		if float(f["tilt"]) != 0.0:
			basis = basis * Basis(Vector3.RIGHT, f["tilt"])
		if float(f["fall"]) > 0.0:
			basis = basis * Basis(Vector3.RIGHT, -float(f["fall"]) * PI * 0.5)
		var sc: float = f["scale"]
		var xf := Transform3D(basis.scaled(Vector3.ONE * maxf(sc * fig_scale, 0.001)), Vector3(p.x, float(f["y"]) + float(f["hop"]) * fig_scale, p.y))
		(f["mm"] as MultiMesh).set_instance_transform(f["i"], xf)
		if f["role"] == "bearer":
			var bn: Node3D = e["banner"]
			bn.transform = Transform3D(Basis(Vector3.UP, float(f["yaw"]) + PI * 0.5).scaled(Vector3.ONE * fig_scale), xf * Vector3(0.95, 1.2, 0.0))
			bn.visible = sc > 0.05 and float(f["fall"]) < 0.5
	if not e["figs"].is_empty():
		pass


## The middle of an army's figures and how tall it stands (for its count plate).
func army_anchor(id: String) -> Vector3:
	var e: Dictionary = armies[id]
	var sum := Vector3.ZERO
	var n := 0
	for f in e["figs"]:
		if float(f["scale"]) < 0.05 or float(f["fall"]) > 0.5:
			continue
		var p: Vector2 = f["pos"]
		sum += Vector3(p.x, float(f["y"]), p.y)
		n += 1
	if n == 0:
		return Vector3(-99999, 0, 0)
	return sum / float(n) + Vector3(0, 13.0 * fig_scale, 0)


func figure_count() -> int:
	var n := 0
	for e in armies.values():
		n += (e["figs"] as Array).size()
	return n


# ------------------------------------------------------------------ turn playback

## Plays a real turn: `before` is standing (show_state), `turn` is a Scenario.autoplay entry.
func play_turn(turn: Dictionary) -> void:
	var before: GameState = turn["before"]
	var after: GameState = turn["after"]
	var moves: Array = Scenario.moves_of(turn)
	var dest: Dictionary = arrange(after)
	var plans := {} ## army id -> per-figure schedules
	var t_end := 0.0
	var moved := {}
	for m in moves:
		moved[m["army"]] = true
		if not armies.has(m["army"]):
			continue
		var e: Dictionary = armies[m["army"]]
		var target: Array = dest.get(m["army"], [])
		if target.is_empty():
			target = _fallen_slots(e, m["to"], m["from"])
		var sched: Array = _march(e, m, target)
		plans[m["army"]] = {"sched": sched, "survived": m["survived"]}
		for s in sched:
			t_end = maxf(t_end, float(s["t_arrive"]))
	## armies that stayed: re-form where the after-state stands them (or fall where they stood)
	var stay := {}
	for id in armies.keys():
		if moved.has(id):
			continue
		var target2: Array = dest.get(id, [])
		stay[id] = {"target": target2, "fell": after.find_army(id) == null}
	_play = {"t": 0.0, "plans": plans, "stay": stay, "t_march": t_end, "t_end": t_end + 2.6, "after": after,
		"owners_done": false}


func playing() -> bool:
	return not _play.is_empty()


func play_progress() -> float:
	return 0.0 if _play.is_empty() else clampf(float(_play["t"]) / float(_play["t_end"]), 0.0, 1.0)


## Each figure's march: out of the gate (or off the stage) in a column, along the road over the
## border, then to its place in the new formation. Returns [{"fig", "pts": PackedVector2Array,
## "lens", "t_dep", "t_arrive", "end_yaw", "end_y"}] in the order they file out.
func _march(e: Dictionary, m: Dictionary, target: Array) -> Array:
	var t = wv.terrain
	var from: String = m["from"]
	var to: String = m["to"]
	var hops: Array = [from] + Array(m["via"]) + [to]
	## the column's shared way: gate (or stage edge), each border crossing, the approach to `to`
	var way := PackedVector2Array()
	if wv.fortresses.has(from) and _in_court(e, from):
		var g: Array = wv.gate_points(from)
		way.append(g[0])
		way.append(g[1])
	else:
		var x0: Variant = t.crossing(hops[0], hops[1])
		var c0: Vector2 = t.centre_of(from)
		var dir0: Vector2 = (((x0 as Vector2) if x0 != null else t.centre_of(hops[1])) - c0).normalized()
		way.append(c0 + dir0 * (t.stage_r[t.index_of(from)] * 0.6))
	for k in range(hops.size() - 1):
		var x: Variant = t.crossing(hops[k], hops[k + 1])
		if x != null:
			way.append(x)
		if k + 1 < hops.size() - 1:
			way.append(t.centre_of(hops[k + 1]))
	var cb: Vector2 = t.centre_of(to)
	var last: Vector2 = way[way.size() - 1]
	way.append(cb + (last - cb).normalized() * (t.stage_r[t.index_of(to)] * 0.9 + 6.0))
	var lens := _lens(way)
	var total: float = lens[lens.size() - 1]
	## who goes first: the figures nearest the way out
	var order: Array = range((e["figs"] as Array).size())
	var start: Vector2 = way[0]
	order.sort_custom(func(a, b): return (e["figs"][a]["pos"] as Vector2).distance_to(start) < (e["figs"][b]["pos"] as Vector2).distance_to(start))
	var sched: Array = []
	var shift := 0.0
	for k in order.size():
		var f: Dictionary = e["figs"][order[k]]
		var lead: float = (f["pos"] as Vector2).distance_to(start) / SPEED
		shift = maxf(shift, lead - float(k / 2) * GAP / SPEED)
	## each figure's destination: the same role and type in the target formation, in order
	var free: Array = target.duplicate()
	for k in order.size():
		var f: Dictionary = e["figs"][order[k]]
		var lane: float = LANE if k % 2 == 0 else -LANE
		var t_enter: float = shift + float(k / 2) * GAP / SPEED
		var lead2: float = (f["pos"] as Vector2).distance_to(start) / SPEED
		var di := -1
		for q in free.size():
			if free[q]["type"] == f["type"]:
				di = q
				break
		var goal: Dictionary = free[di] if di >= 0 else {"pos": cb, "yaw": f["yaw"], "y": t.height_at(cb)}
		if di >= 0:
			free.remove_at(di)
		var end_p: Vector2 = goal["pos"]
		var tail: float = way[way.size() - 1].distance_to(end_p)
		sched.append({"fig": f, "lane": lane, "way": way, "lens": lens, "total": total,
			"t_dep": t_enter - lead2, "t_enter": t_enter, "t_exit": t_enter + total / SPEED,
			"t_arrive": t_enter + total / SPEED + tail / SPEED, "from": f["pos"], "from_y": f["y"], "from_yaw": f["yaw"],
			"to": end_p, "to_yaw": goal["yaw"], "to_y": goal["y"], "phase": randf() * TAU})
	return sched


func _in_court(e: Dictionary, pid: String) -> bool:
	if e["figs"].is_empty():
		return false
	var ct: Array = wv.courtyard(pid)
	var g: Array = wv.gate_points(pid)
	## inside the walls: nearer the courtyard than the outer gate point is
	var p: Vector2 = e["figs"][0]["pos"]
	return p.distance_to(ct[0]) < (g[1] as Vector2).distance_to(ct[0])


## Slots for an army that marches to its death: a formation in front of the place it attacks.
func _fallen_slots(e: Dictionary, to: String, from: String) -> Array:
	var t = wv.terrain
	var cb: Vector2 = t.centre_of(to)
	var ca: Vector2 = t.centre_of(from)
	var f: Vector2 = (cb - ca).normalized()
	var o: Vector2 = cb - f * 20.0
	var basis := Basis.looking_at(Vector3(f.x, 0, f.y), Vector3.UP)
	var out: Array = []
	var types: Array = []
	for fg in e["figs"]:
		types.append(fg["type"])
	var k := 0
	for fg in e["figs"]:
		var lp := Vector2((k % 6 - 2.5) * 4.2, (k / 6) * 4.4)
		var w3: Vector3 = basis * Vector3(lp.x, 0, lp.y)
		var p: Vector2 = o + Vector2(w3.x, w3.z)
		out.append({"type": fg["type"], "pos": p, "yaw": atan2(-f.x, -f.y), "y": t.height_at(p)})
		k += 1
	return out


func _lens(pts: PackedVector2Array) -> PackedFloat32Array:
	var l := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		l.append(l[i - 1] + pts[i - 1].distance_to(pts[i]))
	return l


func _along(pts: PackedVector2Array, lens: PackedFloat32Array, d: float) -> Array:
	d = clampf(d, 0.0, lens[lens.size() - 1])
	for i in range(1, pts.size()):
		if d <= lens[i] or i == pts.size() - 1:
			var seg: float = maxf(lens[i] - lens[i - 1], 0.001)
			var k: float = clampf((d - lens[i - 1]) / seg, 0.0, 1.0)
			return [pts[i - 1].lerp(pts[i], k), (pts[i] - pts[i - 1]).normalized()]
	return [pts[pts.size() - 1], Vector2(0, 1)]


func _process(delta: float) -> void:
	clock += delta
	if _play.is_empty():
		return
	step_playback(delta)


## Advances the playback by `delta` seconds (the shot script drives it frame by frame too).
func step_playback(delta: float) -> void:
	if _play.is_empty():
		return
	var t = wv.terrain
	_play["t"] = float(_play["t"]) + delta
	var now: float = _play["t"]
	for id in _play["plans"].keys():
		if not armies.has(id):
			continue
		var plan: Dictionary = _play["plans"][id]
		for s in plan["sched"]:
			var f: Dictionary = s["fig"]
			var p: Vector2
			var dir: Vector2
			var moving := true
			if now < float(s["t_dep"]):
				p = s["from"]
				f["yaw"] = s["from_yaw"]
				moving = false
				f["y"] = s["from_y"]
			elif now < float(s["t_enter"]):
				var k: float = (now - float(s["t_dep"])) / maxf(float(s["t_enter"]) - float(s["t_dep"]), 0.001)
				var way0: Vector2 = (s["way"] as PackedVector2Array)[0]
				var w1: Vector2 = (s["way"] as PackedVector2Array)[1]
				var side: Vector2 = Vector2(-(w1 - way0).normalized().y, (w1 - way0).normalized().x) * float(s["lane"])
				p = (s["from"] as Vector2).lerp(way0 + side, k)
				dir = ((way0 + side) - (s["from"] as Vector2)).normalized()
				f["y"] = lerpf(float(s["from_y"]), maxf(t.height_at(p), 0.0), k * k) if k > 0.85 else float(s["from_y"])
			elif now < float(s["t_exit"]):
				var d: float = (now - float(s["t_enter"])) * SPEED
				var at: Array = _along(s["way"], s["lens"], d)
				dir = at[1]
				p = (at[0] as Vector2) + Vector2(-dir.y, dir.x) * float(s["lane"])
				f["y"] = t.height_at(p)
			elif now < float(s["t_arrive"]):
				var way_end: Vector2 = (s["way"] as PackedVector2Array)[(s["way"] as PackedVector2Array).size() - 1]
				var k2: float = (now - float(s["t_exit"])) / maxf(float(s["t_arrive"]) - float(s["t_exit"]), 0.001)
				p = way_end.lerp(s["to"], k2)
				dir = ((s["to"] as Vector2) - way_end).normalized()
				f["y"] = lerpf(t.height_at(p), float(s["to_y"]), smoothstep(0.7, 1.0, k2))
			else:
				p = s["to"]
				moving = false
				f["yaw"] = lerp_angle(float(f["yaw"]), float(s["to_yaw"]), minf(1.0, delta * 6.0))
				f["y"] = s["to_y"]
				if not plan["survived"]:
					f["fall"] = minf(1.0, float(f["fall"]) + delta * 2.2)
					if float(f["fall"]) >= 1.0:
						f["scale"] = maxf(0.0, float(f["scale"]) - delta * 0.6)
			if moving and dir.length() > 0.01:
				f["yaw"] = lerp_angle(float(f["yaw"]), atan2(-dir.x, -dir.y), minf(1.0, delta * 10.0))
			var ph: float = now * 9.0 + float(s["phase"])
			f["hop"] = absf(sin(ph)) * 0.75 if moving else 0.0
			f["tilt"] = sin(ph) * 0.08 if moving else 0.0
			f["pos"] = p
		_sync(armies[id])
	## the armies that stayed re-form (or fall when the marchers reach them)
	var k3: float = smoothstep(float(_play["t_march"]) * 0.75, float(_play["t_march"]) + 1.2, now)
	for id in _play["stay"].keys():
		if not armies.has(id):
			continue
		var st: Dictionary = _play["stay"][id]
		var e: Dictionary = armies[id]
		if not st.has("from"):
			var fr: Array = []
			for f in e["figs"]:
				fr.append([f["pos"], f["yaw"], f["y"]])
			st["from"] = fr
		if st["fell"]:
			if k3 > 0.0:
				for f in e["figs"]:
					f["fall"] = minf(1.0, k3 * 1.6)
					f["scale"] = 1.0 - smoothstep(0.7, 1.0, k3)
		elif not (st["target"] as Array).is_empty():
			var free: Array = (st["target"] as Array).duplicate()
			var i := 0
			for f in e["figs"]:
				var di := -1
				for q in free.size():
					if free[q]["type"] == f["type"]:
						di = q
						break
				if di >= 0:
					var goal: Dictionary = free[di]
					free.remove_at(di)
					var fr0: Array = st["from"][i]
					f["pos"] = (fr0[0] as Vector2).lerp(goal["pos"], k3)
					f["yaw"] = lerp_angle(fr0[1], goal["yaw"], k3)
					f["y"] = lerpf(fr0[2], goal["y"], k3)
				i += 1
		_sync(e)
	## the land changes hands when the marchers arrive
	if not _play["owners_done"] and now > float(_play["t_march"]):
		_play["owners_done"] = true
		emit_signal("playback_done")
	if now >= float(_play["t_end"]):
		var after: GameState = _play["after"]
		_play = {}
		show_state(after, seats)
