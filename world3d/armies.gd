## The armies on the 3D board. The figures ARE the army markers (design/3D_DIRECTION.md 6.1): every army
## stands as a formation of miniatures, a block per unit type (Models.block_size figures, front rank
## first, Volley behind, the commander and the banner bearer at the back), every base painted in the
## owner's colour, the banner in the owner's colour with the seat's emblem.
##
## Where they stand (arrange()):
##   * at a capital: mustered in the fortress's courtyard, facing the gate; rows that don't fit stand
##     ready outside the gate;
##   * elsewhere: on the province's stage, facing its roads.
## Queued recruits stand in the yard as translucent ghosts while their player plans (show_ghosts()).
##
## Turn playback (play()): the beats of world3d/playback.gd. Every march files out of the gate (or off
## the stage) in a column two abreast, marches the roads over the borders (a King's Roads move through
## its middle province), and comes to its new place. A battle shows a clash marker at its site (the
## overlay draws it) and the losers topple. Captured land changes colour as the columns arrive. Then
## every army re-forms in its place of the state after the turn, and new recruits fade in. It reads
## the states and events only and never changes them; at the end the board stands exactly as built
## from the state after (tests/test_board3d.gd).
##
## Figures are drawn with one MultiMesh per army and unit type (one draw, plus its outline in Look A).
## Cosmetic variety (the step's phase) comes from a hash of ids, never from a random number generator.
extends Node3D

const Kit := preload("res://world3d/kit.gd")
const Models := preload("res://world3d/models.gd")
const Playback := preload("res://world3d/playback.gd")
const SH_GHOST := preload("res://world3d/shaders/ghost.gdshader")
const SPEED := 21.0 ## march speed, world units a second at 1x
const GAP := 4.4 ## between pairs in a column
const LANE := 1.7 ## half the column's width
const CLASH := 1.8 ## how long a battle's clash marker shows (seconds at 1x)
const REFORM := 2.0 ## the re-form at the end of the turn
const TAIL := 0.5

## The land changed hands: the board repaints the province's wash and its fortress.
signal captured(province_id: String, owner_id: String)
## The whole turn has played (or was skipped); the board now shows the state after.
signal playback_finished

var wv: Node3D ## world_view.gd
var prefer_models := true ## false: every figure as its primitive (the preview's P key)
var state: GameState
var seats: Array = []
var armies := {} ## army id -> {"owner", "colour", "emblem", "figs", "mms", "banner", "province", "units", "ruler"}
var ghost_root: Node3D
var _ghost_key := ""
var _play: Dictionary = {}
var clock := 0.0
var fig_scale := 1.0 ## toy scale: figures stand taller when the camera is far, so the army reads
var speed := 1.0 ## playback speed (1, 2, 4)
var snap_at_end := true ## rebuild from the state after when the playback ends (tests turn it off to compare)


func _init() -> void:
	ghost_root = Node3D.new()
	ghost_root.name = "Ghosts"
	add_child(ghost_root)


## Sets the toy scale (the board eases it with the zoom) and restands every figure.
func set_fig_scale(v: float) -> void:
	if absf(v - fig_scale) < 0.01:
		return
	fig_scale = v
	for e in armies.values():
		_sync(e)
	for g in _ghosts():
		_sync(g)


# ------------------------------------------------------------------ standing armies

## Stands every army of `s` in its place (no animation). Clears any playback.
func show_state(s: GameState, p_seats: Array) -> void:
	state = s
	seats = p_seats
	_play = {}
	for id in armies.keys():
		_free_army(armies[id])
	armies.clear()
	var places: Dictionary = arrange(s)
	for a in s.armies:
		armies[a.id] = _make_entry(_desc_of(a), places.get(a.id, []))


func playing() -> bool:
	return not _play.is_empty()


## The board's description of an army: its blocks and leaders, as arrange() and the formation need.
func _desc_of(a: Army) -> Dictionary:
	var counts := {}
	var order: Array = []
	for u in a.units:
		var t: String = u.type.id
		if not counts.has(t):
			counts[t] = 0
			order.append(t)
		counts[t] += 1
	var blocks: Array = []
	for t in order:
		blocks.append({"type": t, "n": Models.block_size(counts[t]), "rank": Models.rank_of(t), "sp": _spacing(t)})
	blocks.sort_custom(func(x, y): return x["rank"] < y["rank"] or (x["rank"] == y["rank"] and x["type"] < y["type"]))
	var leaders: Array = []
	if a.ruler != null:
		var rt: String = a.ruler.type.id
		leaders.append({"type": rt, "role": "ruler", "rank": Models.rank_of(rt), "sp": _spacing(rt)})
	if a.commander != null:
		var ct: String = a.commander.type.id
		leaders.append({"type": ct, "role": "commander", "rank": 2, "sp": _spacing(ct)})
	return {"id": a.id, "owner": a.owner, "location": a.location, "blocks": blocks, "leaders": leaders,
		"units": a.units.size(), "ruler": a.ruler != null}


func _spacing(t: String) -> Vector2:
	if Kit.SPACING.has(t):
		return Kit.SPACING[t]
	var row := Models.figure_row(t)
	var fb := String(row.get("fallback", ""))
	var s := float(row.get("scale", 1.0))
	return (Kit.SPACING.get(fb, Vector2(4.2, 4.4)) as Vector2) * s


## Where every army's figures stand in `s`: army id -> [{"type", "role", "pos": Vector2, "yaw", "y"}].
## `extra` adds descriptions (queued recruits' ghosts) after the province's own armies.
func arrange(s: GameState, extra: Array = []) -> Dictionary:
	var descs: Array = []
	for a in s.armies:
		descs.append(_desc_of(a))
	return arrange_descs(descs, extra)


func arrange_descs(descs: Array, extra: Array = []) -> Dictionary:
	var out := {}
	var by_prov := {}
	for d in descs:
		if not by_prov.has(d["location"]):
			by_prov[d["location"]] = []
		by_prov[d["location"]].append(d)
	for pid in by_prov.keys():
		(by_prov[pid] as Array).sort_custom(func(x, y): return x["id"] < y["id"])
	for d in extra:
		## queued recruits stand right after the province's first army: in the yard, beside the army
		## they will most likely join (the rules put a recruit in the first army there, or a new one)
		if not by_prov.has(d["location"]):
			by_prov[d["location"]] = []
		var list: Array = by_prov[d["location"]]
		list.insert(mini(1, list.size()), d)
	var t = wv.terrain
	for pid in by_prov.keys():
		var list: Array = by_prov[pid]
		if t.index_of(pid) < 0:
			continue
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
		for d in list:
			var slots: Array = Kit.formation_blocks(d["blocks"], d["leaders"], max_w)
			var dd: float = Kit.formation_depth(slots)
			var basis := Basis.looking_at(Vector3(facing.x, 0, facing.y), Vector3.UP)
			var placed: Array = []
			var spill := 0.0
			for sl in slots:
				var lp: Vector2 = sl["pos"]
				var z: float = depth + lp.y
				var p: Vector2
				var y: float
				if in_fort and (full or z > room):
					var g: Array = wv.gate_points(pid)
					var zo: float = lp.y if full else z - room
					var w3o: Vector3 = basis * Vector3(lp.x, 0, -zo)
					p = (g[1] as Vector2) + facing * (6.0 + out_depth) + Vector2(w3o.x, w3o.z)
					y = maxf(t.height_at(p), 0.0)
					spill = maxf(spill, zo)
				else:
					var w3: Vector3 = basis * Vector3(lp.x, 0, z)
					p = origin + Vector2(w3.x, w3.z)
					y = (floor_y + 0.25) if in_fort else maxf(t.height_at(p), 0.0)
				placed.append({"type": sl["type"], "role": sl["role"], "pos": p, "yaw": atan2(-facing.x, -facing.y), "y": y})
			depth += dd + 2.0
			if spill > 0.0:
				out_depth += spill + 3.0
				full = true
			out[d["id"]] = placed
	return out


func _make_entry(d: Dictionary, placed: Array, ghost: bool = false) -> Dictionary:
	var seat: int = UiPalette.seat_index(state, d["owner"], seats)
	var col: Color = UiPalette.seat_color(seat)
	var e := {"id": d["id"], "owner": d["owner"], "colour": col, "emblem": maxi(seat, 0), "figs": [], "mms": {},
		"province": d["location"], "units": d.get("units", 0), "ruler": d.get("ruler", false), "ghost": ghost}
	_fill_entry(e, placed, ghost)
	return e


## (Re)builds an entry's MultiMeshes and figures for `placed` slots ({"from_*"} keys give a figure a
## start for the re-form). One MultiMesh per unit type.
func _fill_entry(e: Dictionary, placed: Array, ghost: bool = false) -> void:
	for t in e["mms"].keys():
		(e["mms"][t]["mi"] as Node).queue_free()
	e["mms"] = {}
	e["figs"] = []
	var count := {}
	for sl in placed:
		count[sl["type"]] = int(count.get(sl["type"], 0)) + 1
	var col: Color = e["colour"]
	var parent: Node = ghost_root if ghost else self
	for t in count.keys():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		var fm: Dictionary = Models.figure_mesh(t, prefer_models)
		mm.mesh = fm["mesh"]
		mm.instance_count = count[t]
		var mi := MultiMeshInstance3D.new()
		mi.name = "%s_%s" % [str(e["id"]).validate_node_name(), t]
		mi.multimesh = mm
		if ghost:
			var gm := ShaderMaterial.new()
			gm.shader = SH_GHOST
			gm.set_shader_parameter("team", col)
			mi.material_override = gm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mi.material_override = wv.model_mat(col, fm["tex"], -1.0, true)
		parent.add_child(mi)
		e["mms"][t] = {"mi": mi, "next": 0}
	var lin: Color = col.srgb_to_linear()
	var k := 0
	for sl in placed:
		var slot: Dictionary = e["mms"][sl["type"]]
		var i: int = slot["next"]
		slot["next"] = i + 1
		(slot["mi"].multimesh as MultiMesh).set_instance_custom_data(i, lin)
		var f := {"type": sl["type"], "role": sl["role"], "mm": slot["mi"].multimesh, "i": i,
			"pos": sl.get("from_pos", sl["pos"]), "yaw": sl.get("from_yaw", sl["yaw"]), "y": sl.get("from_y", sl["y"]),
			"hop": 0.0, "tilt": 0.0, "fall": 0.0, "scale": float(sl.get("from_scale", 1.0)),
			"from_pos": sl.get("from_pos", sl["pos"]), "from_yaw": sl.get("from_yaw", sl["yaw"]), "from_y": sl.get("from_y", sl["y"]),
			"from_scale": float(sl.get("from_scale", 1.0)), "from_fall": 0.0,
			"to_pos": sl["pos"], "to_yaw": sl["yaw"], "to_y": sl["y"], "to_scale": float(sl.get("to_scale", 1.0)),
			"phase": _phase(str(e["id"]), k)}
		e["figs"].append(f)
		k += 1
	if not e.has("banner") or e["banner"] == null:
		if not ghost:
			var bn: Node3D = wv.make_banner(col, e["emblem"], 11.0, Vector2(5.2, 3.4))
			add_child(bn)
			e["banner"] = bn
		else:
			e["banner"] = null
	_sync(e)


func _free_army(e: Dictionary) -> void:
	for t in e["mms"].keys():
		(e["mms"][t]["mi"] as Node).queue_free()
	if e.get("banner") != null:
		(e["banner"] as Node).queue_free()


static func _phase(id: String, k: int) -> float:
	return float(absi(hash(id + ":" + str(k))) % 6283) / 1000.0


## Writes every figure's state into its MultiMesh, and the banner onto the bearer.
func _sync(e: Dictionary) -> void:
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
		if f["role"] == "bearer" and e.get("banner") != null:
			var bn: Node3D = e["banner"]
			bn.transform = Transform3D(Basis(Vector3.UP, float(f["yaw"]) + PI * 0.5).scaled(Vector3.ONE * fig_scale), xf * Vector3(0.95, 1.2, 0.0))
			bn.visible = sc > 0.05 and float(f["fall"]) < 0.5


## The middle of an army's standing figures and the height of its plate's foot (for its count plate),
## or Vector3(-99999, ...) when nothing of it stands.
func army_anchor(id: String) -> Vector3:
	if not armies.has(id):
		return Vector3(-99999, 0, 0)
	var e: Dictionary = armies[id]
	var sum := Vector3.ZERO
	var n := 0
	var top := -1.0e9
	for f in e["figs"]:
		if float(f["scale"]) < 0.05 or float(f["fall"]) > 0.5:
			continue
		var p: Vector2 = f["pos"]
		sum += Vector3(p.x, float(f["y"]), p.y)
		top = maxf(top, float(f["y"]))
		n += 1
	if n == 0:
		return Vector3(-99999, 0, 0)
	var mid: Vector3 = sum / float(n)
	return Vector3(mid.x, top + 13.0 * fig_scale, mid.z)


## Every standing figure of an army as [foot, head] world points (picking and plates).
func army_points(id: String) -> Array:
	var out: Array = []
	if not armies.has(id):
		return out
	for f in armies[id]["figs"]:
		if float(f["scale"]) < 0.05 or float(f["fall"]) > 0.5:
			continue
		var p: Vector2 = f["pos"]
		var y: float = f["y"]
		out.append([Vector3(p.x, y, p.y), Vector3(p.x, y + Kit.FIG * float(f["scale"]) * fig_scale, p.y)])
	return out


func figure_count() -> int:
	var n := 0
	for e in armies.values():
		n += (e["figs"] as Array).size()
	return n


## What the board shows of the armies, for comparing two boards: army id -> {"owner", "province" (the
## land under its figures' middle), "figs": sorted ["type@x,z"] of every standing figure}.
func snapshot() -> Dictionary:
	var out := {}
	var t = wv.terrain
	for id in armies.keys():
		var e: Dictionary = armies[id]
		var figs: Array = []
		var sum := Vector2.ZERO
		var n := 0
		for f in e["figs"]:
			if float(f["scale"]) < 0.5 or float(f["fall"]) > 0.5:
				continue
			var p: Vector2 = f["pos"]
			figs.append("%s@%.1f,%.1f" % [f["type"], p.x, p.y])
			sum += p
			n += 1
		if n == 0:
			continue
		figs.sort()
		out[id] = {"owner": e["owner"], "province": t.province_at(sum / float(n)), "figs": figs}
	return out


# ------------------------------------------------------------------ ghost recruits (planning)

## Queued recruits as translucent figures in the yard where they will join: `list` is [{"province",
## "owner", "types": [unit type ids]}]. Only the ordering player's view shows them.
func show_ghosts(list: Array) -> void:
	var key := JSON.stringify(list)
	if key == _ghost_key and state != null:
		return
	_ghost_key = key
	for g in _ghosts():
		_free_army(g)
	ghost_root.set_meta("entries", [])
	if list.is_empty() or state == null:
		return
	var extra: Array = []
	var gi := 0
	for g in list:
		var counts := {}
		var order: Array = []
		for t in g["types"]:
			if not counts.has(t):
				counts[t] = 0
				order.append(t)
			counts[t] += 1
		var blocks: Array = []
		var leaders: Array = []
		for t in order:
			var ut_row := Models.figure_row(t)
			if int(ut_row.get("rank", 0)) >= 2 and t != "bearer":
				leaders.append({"type": t, "role": "commander", "rank": 2, "sp": _spacing(t)})
			else:
				## a ghost block shows every queued recruit as its own figure, so each click shows
				blocks.append({"type": t, "n": counts[t], "rank": Models.rank_of(t), "sp": _spacing(t)})
		extra.append({"id": "~ghost%d" % gi, "owner": g["owner"], "location": g["province"], "blocks": blocks, "leaders": leaders, "ghost": true,
			"types": (g["types"] as Array).duplicate()})
		gi += 1
	var places := arrange(state, extra)
	var entries: Array = []
	for d in extra:
		var placed: Array = (places.get(d["id"], []) as Array).filter(func(sl): return sl["role"] != "bearer")
		if placed.is_empty():
			continue
		var ge := _make_entry(d, placed, true)
		ge["types"] = d["types"]
		entries.append(ge)
	ghost_root.set_meta("entries", entries)


func _ghosts() -> Array:
	return ghost_root.get_meta("entries", []) if ghost_root != null else []


## The ghost blocks standing now: [{"province", "owner", "types", "anchor": Vector3 over them}].
func ghost_list() -> Array:
	var out: Array = []
	for g in _ghosts():
		var sum := Vector3.ZERO
		var top := -1.0e9
		var n := 0
		for f in g["figs"]:
			var p: Vector2 = f["pos"]
			sum += Vector3(p.x, float(f["y"]), p.y)
			top = maxf(top, float(f["y"]))
			n += 1
		if n == 0:
			continue
		var mid: Vector3 = sum / float(n)
		out.append({"province": g["province"], "owner": g["owner"], "types": g.get("types", []),
			"anchor": Vector3(mid.x, top + 10.0 * fig_scale, mid.z)})
	return out


func ghost_count() -> int:
	var n := 0
	for g in _ghosts():
		n += (g["figs"] as Array).size()
	return n


# ------------------------------------------------------------------ turn playback

## Plays a resolved turn: `before` must be standing (show_state), `plan` is Playback.plan(before,
## events, after). Ends standing the state after; emits playback_finished.
func play(plan: Dictionary, before: GameState, after: GameState) -> void:
	show_ghosts([])
	if state != before:
		show_state(before, seats)
	var t = wv.terrain
	var dest: Dictionary = arrange(after)
	var plans := {}
	var t_march := 0.4
	for m in plan.get("marches", []):
		var aid: String = m["army"]
		if not armies.has(aid):
			continue
		var e: Dictionary = armies[aid]
		var hops: Array = m["hops"]
		if hops.size() < 2 or t.index_of(hops[0]) < 0 or t.index_of(hops[hops.size() - 1]) < 0:
			continue
		var way := _way(e, hops, bool(m["to_border"]))
		var site: Vector2 = way[way.size() - 1]
		var target: Array
		if m["survived"]:
			target = dest.get(aid, [])
		else:
			target = _fallen_slots(e, site, (way[way.size() - 1] - way[maxi(0, way.size() - 2)]).normalized())
		var sched: Array = _march(e, way, target)
		var lead := 1.0e9
		for s in sched:
			lead = minf(lead, float(s["t_exit"]))
			t_march = maxf(t_march, float(s["t_arrive"]))
		plans[aid] = {"sched": sched, "survived": m["survived"], "lead": lead, "hops": hops, "fall_at": 1.0e9}
	## battles: each one's clash when every side has reached the site; the losers fall then
	var clashes: Array = []
	var fall_at := {}
	for b in plan.get("battles", []):
		var by_side := {}
		for aid in b["armies"]:
			var owner := ""
			if armies.has(aid):
				owner = armies[aid]["owner"]
			var arr: float = float(plans[aid]["lead"]) if plans.has(aid) else 0.0
			by_side[owner] = minf(float(by_side.get(owner, 1.0e9)), arr)
		var tb := 0.3
		for v in by_side.values():
			tb = maxf(tb, float(v))
		var at: Vector3
		var provs: Array = b["provinces"]
		if b["kind"] == "border_battle" and provs.size() >= 2:
			var x: Variant = t.crossing(provs[0], provs[1])
			var xp: Vector2 = (x as Vector2) if x != null else (t.centre_of(provs[0]) + t.centre_of(provs[1])) * 0.5
			at = t.ground_at(xp)
		else:
			at = t.ground_at(t.centre_of(provs[0]))
		clashes.append({"at": at, "t0": tb, "t1": tb + CLASH, "label": Playback.battle_label(b, before)})
		for aid in b["destroyed"]:
			fall_at[aid] = tb + CLASH * 0.55
		t_march = maxf(t_march, tb + CLASH)
	for aid in plans.keys():
		if fall_at.has(aid):
			plans[aid]["fall_at"] = fall_at[aid]
	## captures: when the battle there ends, or when the new owner's first column arrives
	var caps: Array = []
	for c in plan.get("captures", []):
		var tc := -1.0
		if int(c["battle"]) >= 0 and int(c["battle"]) < clashes.size():
			tc = float(clashes[int(c["battle"])]["t1"])
		else:
			for aid in plans.keys():
				var pl: Dictionary = plans[aid]
				var hops2: Array = pl["hops"]
				if armies.has(aid) and armies[aid]["owner"] == c["owner"] and hops2[hops2.size() - 1] == c["province"] and pl["survived"]:
					tc = float(pl["lead"]) if tc < 0.0 else minf(tc, float(pl["lead"]))
		if tc < 0.0:
			tc = t_march * 0.8
		caps.append({"province": c["province"], "owner": c["owner"], "t": tc, "done": false})
	var t_reform: float = t_march + 0.25
	_play = {"t": 0.0, "plans": plans, "fall_at": fall_at, "clashes": clashes, "caps": caps, "t_march": t_march,
		"t_reform": t_reform, "t_end": t_reform + REFORM + TAIL, "after": after, "dest": dest, "reformed": false,
		"plan": plan}


func play_progress() -> float:
	return 0.0 if _play.is_empty() else clampf(float(_play["t"]) / float(_play["t_end"]), 0.0, 1.0)


func play_time() -> float:
	return 0.0 if _play.is_empty() else float(_play["t"])


func play_length() -> float:
	return 0.0 if _play.is_empty() else float(_play["t_end"])


## The clash markers showing now: [{"at": Vector3, "k": 0..1 through the clash, "label"}].
func clashes_now() -> Array:
	var out: Array = []
	if _play.is_empty():
		return out
	var now: float = _play["t"]
	for c in _play["clashes"]:
		if now >= float(c["t0"]) and now <= float(c["t1"]) + 0.4:
			out.append({"at": c["at"], "k": clampf((now - float(c["t0"])) / CLASH, 0.0, 1.0), "label": c["label"]})
	return out


## Jumps to the end of the playback: the board stands the state after at once.
func skip() -> void:
	if _play.is_empty():
		return
	step_playback(float(_play["t_end"]) - float(_play["t"]) + 0.01, true)


## The column's way: out of the gate (or off the stage), over each border crossing (a road move goes
## through its middle province's centre), to the approach of the last province; a border battle's
## loser stops at the crossing.
func _way(e: Dictionary, hops: Array, to_border: bool) -> PackedVector2Array:
	var t = wv.terrain
	var from: String = hops[0]
	var to: String = hops[hops.size() - 1]
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
		if to_border:
			return way
		if k + 1 < hops.size() - 1:
			way.append(t.centre_of(hops[k + 1]))
	var cb: Vector2 = t.centre_of(to)
	var last: Vector2 = way[way.size() - 1]
	way.append(cb + (last - cb).normalized() * (t.stage_r[t.index_of(to)] * 0.9 + 6.0))
	return way


## Each figure's march along `way`: nearest the way out first, two abreast, then to its slot in
## `target` (same type, in order). Returns [{"fig", "lane", "way", "lens", "t_dep", "t_enter",
## "t_exit", "t_arrive", "from", "from_y", "from_yaw", "to", "to_yaw", "to_y"}].
func _march(e: Dictionary, way: PackedVector2Array, target: Array) -> Array:
	var t = wv.terrain
	var lens := _lens(way)
	var total: float = lens[lens.size() - 1]
	var order: Array = range((e["figs"] as Array).size())
	var start: Vector2 = way[0]
	order.sort_custom(func(a, b): return (e["figs"][a]["pos"] as Vector2).distance_to(start) < (e["figs"][b]["pos"] as Vector2).distance_to(start))
	var sched: Array = []
	var shift := 0.0
	for k in order.size():
		var f: Dictionary = e["figs"][order[k]]
		var lead: float = (f["pos"] as Vector2).distance_to(start) / SPEED
		shift = maxf(shift, lead - float(k / 2) * GAP / SPEED)
	var free: Array = target.duplicate()
	var end_c: Vector2 = way[way.size() - 1]
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
		if di < 0 and not free.is_empty():
			di = 0
		var goal: Dictionary = free[di] if di >= 0 else {"pos": end_c, "yaw": f["yaw"], "y": t.height_at(end_c)}
		if di >= 0:
			free.remove_at(di)
		var end_p: Vector2 = goal["pos"]
		var tail: float = way[way.size() - 1].distance_to(end_p)
		sched.append({"fig": f, "lane": lane, "way": way, "lens": lens, "total": total,
			"t_dep": t_enter - lead2, "t_enter": t_enter, "t_exit": t_enter + total / SPEED,
			"t_arrive": t_enter + total / SPEED + tail / SPEED, "from": f["pos"], "from_y": f["y"], "from_yaw": f["yaw"],
			"to": end_p, "to_yaw": goal["yaw"], "to_y": goal["y"]})
	return sched


func _in_court(e: Dictionary, pid: String) -> bool:
	if e["figs"].is_empty():
		return false
	var ct: Array = wv.courtyard(pid)
	var g: Array = wv.gate_points(pid)
	var p: Vector2 = e["figs"][0]["pos"]
	return p.distance_to(ct[0]) < (g[1] as Vector2).distance_to(ct[0])


## Slots for an army that marches to its fall: a loose formation just short of the site, facing it.
func _fallen_slots(e: Dictionary, site: Vector2, f: Vector2) -> Array:
	var t = wv.terrain
	if f.length() < 0.01:
		f = Vector2(0, 1)
	var o: Vector2 = site - f * 14.0
	var basis := Basis.looking_at(Vector3(f.x, 0, f.y), Vector3.UP)
	var out: Array = []
	var k := 0
	for fg in e["figs"]:
		var lp := Vector2((k % 6 - 2.5) * 4.2, (k / 6) * 4.4)
		var w3: Vector3 = basis * Vector3(lp.x, 0, lp.y)
		var p: Vector2 = o + Vector2(w3.x, w3.z)
		out.append({"type": fg["type"], "pos": p, "yaw": atan2(-f.x, -f.y), "y": maxf(t.height_at(p), 0.0)})
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
	step_playback(delta * speed)


## Advances the playback by `delta` seconds of playback time (tests and the shot script step it).
func step_playback(delta: float, skipping: bool = false) -> void:
	if _play.is_empty():
		return
	var t = wv.terrain
	_play["t"] = float(_play["t"]) + delta
	var now: float = _play["t"]
	var step: float = minf(delta, 0.25)
	## the marches
	if now < float(_play["t_reform"]) and not skipping:
		for id in _play["plans"].keys():
			if not armies.has(id):
				continue
			var plan: Dictionary = _play["plans"][id]
			var fall_t: float = plan["fall_at"]
			for s in plan["sched"]:
				_march_step(s, now, step, t, plan["survived"], fall_t)
			_sync(armies[id])
		## the armies that held and fell: they topple when the battle's losers fall
		for id in _play["fall_at"].keys():
			if _play["plans"].has(id) or not armies.has(id):
				continue
			if now >= float(_play["fall_at"][id]):
				for f in armies[id]["figs"]:
					f["fall"] = minf(1.0, float(f["fall"]) + step * 2.2)
					if float(f["fall"]) >= 1.0:
						f["scale"] = maxf(0.0, float(f["scale"]) - step * 0.7)
				_sync(armies[id])
	## the land changes hands as the columns arrive
	for c in _play["caps"]:
		if not c["done"] and (now >= float(c["t"]) or skipping):
			c["done"] = true
			captured.emit(c["province"], c["owner"])
	## the re-form: every army to its place in the state after, new recruits fade in, the fallen go
	if now >= float(_play["t_reform"]) and not _play["reformed"]:
		_play["reformed"] = true
		_begin_reform()
	if _play["reformed"]:
		var k: float = 1.0 if skipping else smoothstep(0.0, 1.0, clampf((now - float(_play["t_reform"])) / REFORM, 0.0, 1.0))
		for e in armies.values():
			for f in e["figs"]:
				f["pos"] = (f["from_pos"] as Vector2).lerp(f["to_pos"], k)
				f["yaw"] = lerp_angle(float(f["from_yaw"]), float(f["to_yaw"]), k)
				f["y"] = lerpf(float(f["from_y"]), float(f["to_y"]), k)
				f["scale"] = lerpf(float(f["from_scale"]), float(f["to_scale"]), k)
				f["fall"] = lerpf(float(f.get("from_fall", 0.0)), 0.0, k) if float(f["to_scale"]) > 0.0 else float(f.get("from_fall", 0.0))
				f["hop"] = 0.0
				f["tilt"] = 0.0
			_sync(e)
	if now >= float(_play["t_end"]) or skipping:
		var after: GameState = _play["after"]
		_play = {}
		if snap_at_end:
			show_state(after, seats)
		else:
			state = after
		playback_finished.emit()


func _march_step(s: Dictionary, now: float, step: float, t, survived: bool, fall_t: float) -> void:
	var f: Dictionary = s["fig"]
	var p: Vector2
	var dir := Vector2.ZERO
	var moving := true
	if now < float(s["t_dep"]):
		p = s["from"]
		f["yaw"] = s["from_yaw"]
		moving = false
		f["y"] = s["from_y"]
	elif now < float(s["t_enter"]):
		var k: float = (now - float(s["t_dep"])) / maxf(float(s["t_enter"]) - float(s["t_dep"]), 0.001)
		var way: PackedVector2Array = s["way"]
		var w0: Vector2 = way[0]
		var w1: Vector2 = way[1] if way.size() > 1 else way[0] + Vector2(0, 1)
		var side: Vector2 = Vector2(-(w1 - w0).normalized().y, (w1 - w0).normalized().x) * float(s["lane"])
		p = (s["from"] as Vector2).lerp(w0 + side, k)
		dir = ((w0 + side) - (s["from"] as Vector2)).normalized()
		f["y"] = lerpf(float(s["from_y"]), maxf(t.height_at(p), 0.0), k * k) if k > 0.85 else float(s["from_y"])
	elif now < float(s["t_exit"]):
		var d: float = (now - float(s["t_enter"])) * SPEED
		var at: Array = _along(s["way"], s["lens"], d)
		dir = at[1]
		p = (at[0] as Vector2) + Vector2(-dir.y, dir.x) * float(s["lane"])
		f["y"] = maxf(t.height_at(p), 0.0)
	elif now < float(s["t_arrive"]):
		var way2: PackedVector2Array = s["way"]
		var way_end: Vector2 = way2[way2.size() - 1]
		var k2: float = (now - float(s["t_exit"])) / maxf(float(s["t_arrive"]) - float(s["t_exit"]), 0.001)
		p = way_end.lerp(s["to"], k2)
		dir = ((s["to"] as Vector2) - way_end).normalized()
		f["y"] = lerpf(maxf(t.height_at(p), 0.0), float(s["to_y"]), smoothstep(0.7, 1.0, k2))
	else:
		p = s["to"]
		moving = false
		f["yaw"] = lerp_angle(float(f["yaw"]), float(s["to_yaw"]), minf(1.0, step * 6.0))
		f["y"] = s["to_y"]
	if not survived and now >= fall_t and now >= float(s["t_arrive"]) - 0.3:
		moving = false
		f["fall"] = minf(1.0, float(f["fall"]) + step * 2.2)
		if float(f["fall"]) >= 1.0:
			f["scale"] = maxf(0.0, float(f["scale"]) - step * 0.7)
	if moving and dir.length() > 0.01:
		f["yaw"] = lerp_angle(float(f["yaw"]), atan2(-dir.x, -dir.y), minf(1.0, step * 10.0))
	var ph: float = now * 9.0 + float(f["phase"])
	f["hop"] = absf(sin(ph)) * 0.75 if moving else 0.0
	f["tilt"] = sin(ph) * 0.08 if moving else 0.0
	f["pos"] = p


## The re-form begins: every army of the state after gets exactly its formation's figures, each one
## starting where a figure of its type stands now (new ones fade in at their slot); the figures left
## over and the fallen armies fade out.
func _begin_reform() -> void:
	var after: GameState = _play["after"]
	var dest: Dictionary = _play["dest"]
	var old := armies
	armies = {}
	var seen := {}
	for a in after.armies:
		var slots: Array = dest.get(a.id, [])
		var placed: Array = []
		var e_old: Dictionary = old.get(a.id, {})
		var pool: Array = (e_old.get("figs", []) as Array).filter(func(f): return float(f["scale"]) > 0.05 and float(f["fall"]) < 0.5)
		for sl in slots:
			var best := -1
			var best_d := 1.0e18
			for q in pool.size():
				if pool[q]["type"] != sl["type"]:
					continue
				var d2: float = (pool[q]["pos"] as Vector2).distance_squared_to(sl["pos"])
				if d2 < best_d:
					best_d = d2
					best = q
			var item: Dictionary = sl.duplicate()
			if best >= 0:
				var f0: Dictionary = pool[best]
				pool.remove_at(best)
				item["from_pos"] = f0["pos"]
				item["from_yaw"] = f0["yaw"]
				item["from_y"] = f0["y"]
				item["from_scale"] = f0["scale"]
			else:
				item["from_scale"] = 0.0
			placed.append(item)
		## the figures left over (losses in a battle it won) shrink where they stand
		for f0 in pool:
			placed.append({"type": f0["type"], "role": "unit", "pos": f0["pos"], "yaw": f0["yaw"], "y": f0["y"],
				"from_scale": f0["scale"], "to_scale": 0.0})
		var e: Dictionary
		if not e_old.is_empty():
			e = e_old
			e["units"] = a.units.size()
			e["province"] = a.location
			_fill_entry(e, placed)
		else:
			e = _make_entry(_desc_of(a), placed)
		armies[a.id] = e
		seen[a.id] = true
	## the fallen: whatever still stands of them fades out
	for id in old.keys():
		if seen.has(id):
			continue
		var e2: Dictionary = old[id]
		for f in e2["figs"]:
			f["from_pos"] = f["pos"]
			f["from_yaw"] = f["yaw"]
			f["from_y"] = f["y"]
			f["from_scale"] = f["scale"]
			f["from_fall"] = f["fall"]
			f["to_pos"] = f["pos"]
			f["to_yaw"] = f["yaw"]
			f["to_y"] = f["y"]
			f["to_scale"] = 0.0
		armies["~fallen~" + id] = e2
	for e3 in armies.values():
		for f in e3["figs"]:
			if not f.has("from_pos"):
				f["from_pos"] = f["pos"]
				f["from_yaw"] = f["yaw"]
				f["from_y"] = f["y"]
			if not f.has("from_fall"):
				f["from_fall"] = 0.0
