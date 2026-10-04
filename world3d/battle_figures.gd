## The fighters of the 3D battle stage (M3b; design/3D_DIRECTION.md 7.3): every fighter of the log as its
## own figure, 1:1, in the real models' pose families (world3d/models.gd), with procedural motion over the
## poses, all keyed to the battle player's clock (seconds at 1x), so a pause freezes them, 4x runs them
## faster and a seek snaps them to the state at once.
##
## Drawn with one MultiMesh per unit type (and faction, for the cosmetic extras) and distinct pose mesh,
## plus a desaturated copy for the fallen, compacted every sync so each draws only its own figures. Both
## sides share a MultiMesh: each figure's base takes its side's colour from the instance's custom data
## (identity in code, never in the art), whose alpha carries the 0.15 s red tint of a hit.
##
## Motions (motion kinds, each {"kind", "t0", "dur", ...} on a figure; none draws a random number):
##   deploy  the front rank steps forward into its place, marching
##   lunge   a melee blow: the strike pose and a lunge toward the target (25% of the way, at most LUNGE_MAX)
##           and back; the impact lands at BattlePlayer.MELEE_IMPACT
##   shoot   a ranged release: the strike pose for a moment (the projectile is the stage's)
##   dive    Wings: a leap in an arc onto the target, landing on the impact, then back
##   recoil  a hit: knocked back 0.15 s, tinted red
##   topple  a death: toppling about the feet, then lying in the fallen pose (desaturated 30%)
##   rout    turning and running to the side's back edge at 1.5x, shrinking away at the end
##   fade    shrinking away where it stands (the aftermath's lost; a rout with reduced motion)
##   cheer   the winners' hop (rulers in their cheer pose)
## The hold states ("stand", "fallen", "gone") are set at the beat; a motion animates the change.
extends Node3D

const Models := preload("res://world3d/models.gd")
const Kit := preload("res://world3d/kit.gd")
const Choreo := preload("res://world3d/choreo.gd")

const DEPLOY_STEP := 5.0 ## the front rank's step forward
const LUNGE_SHARE := 0.25
const LUNGE_MAX := 4.5
const LUNGE_OUT := 0.12 ## = BattlePlayer.MELEE_IMPACT
const LUNGE_BACK := 0.26
const STRIKE_HOLD := 0.42
const RECOIL := 0.15
const RECOIL_DIST := 1.1
const TOPPLE := 0.45
const ROUT_SPEED := 1.5
const DIVE_BACK := 0.45
const DIVE_APEX := 0.3 ## of the leap's length
const FADE := 0.6
const CHEER := 1.6
const HOP := 0.6
const STEP_RATE := 9.0
const FALLEN_DESAT := 0.3

var wv: Node3D ## world_view.gd (materials and banners)
var figs: Array = [] ## by index: the log's fighters (index = fighter id), then the extras
var n_fighters := 0
var groups: Dictionary = {} ## key -> {"mi": MultiMeshInstance3D, "n": int (drawn now), "cap": int}
var banners: Array = [] ## by side: the standard bearer's banner node
var reduced_motion := false
var shadows := true
var land: RefCounted = null ## the baked land (the ground under a moving figure)
var _fig_of: Array = [] ## by fighter id: its figure (a file's fighters share one)
var lod_bias := 1.0
## The fighters' own ink (Look A): its width follows the figures' size on screen (set_ink_px), so a crowd of
## 35-pixel figures isn't drawn half in ink, while a close battle keeps the full line.
var ink: ShaderMaterial = null
var _mats := {}
var _dirty := true


## Builds every figure of `plan` (BattleFormation.plan) for `battle_log`; by side: `colours` (sRGB, the
## banners), `lin` (linear, the bases), `emblems` (seat emblem indices), `factions` (the extras' models).
## `files` (BattleFormation.groups_of, {} for 1:1): a figure per file of fighters instead of per fighter.
func build(battle_log: Dictionary, plan: Dictionary, colours: Array, lin: Array, emblems: Array, factions: Array, files: Dictionary = {}) -> void:
	clear()
	var members: Array = (files.get("members", []) as Array).duplicate()
	if members.is_empty():
		for f in battle_log.fighters:
			members.append([int(f.id)])
	n_fighters = members.size()
	_fig_of = []
	_fig_of.resize((battle_log.get("fighters", []) as Array).size())
	var specs := []
	for i in members.size():
		var f: Dictionary = battle_log.fighters[int(members[i][0])]
		for fid in members[i]:
			_fig_of[int(fid)] = i
		var s: Dictionary = plan["slots"][int(f.id)]
		specs.append({"fid": int(f.id), "type": String(f.type), "faction": "", "side": int(f.side), "role": String(f.role), "slot": s,
			"members": (members[i] as Array).duplicate()})
	for ex in plan["extras"]:
		var si := int(ex["side"])
		specs.append({"fid": -1, "type": String(ex["type"]), "faction": String(factions[si]) if si < factions.size() else "", "side": si,
			"role": String(ex["type"]), "slot": ex})
	## how many figures each (type, faction) has: every one of its pose groups holds that many at most
	var count := {}
	for sp in specs:
		var tk := "%s:%s" % [sp["type"], sp["faction"]]
		count[tk] = int(count.get(tk, 0)) + 1
	for sp in specs:
		var tk := "%s:%s" % [sp["type"], sp["faction"]]
		var pm: Dictionary = Models.pose_meshes(String(sp["type"]), true, String(sp["faction"]))
		var keys := {}
		for pose in Models.POSES:
			if not pm.has(pose):
				continue
			var fm: Dictionary = pm[pose]
			var mesh: Mesh = fm["mesh"]
			for fallen in [false, true]:
				var gk := "%s|%d|%s" % [tk, mesh.get_instance_id(), "f" if fallen else "s"]
				if not groups.has(gk):
					groups[gk] = _group(gk, mesh, fm["tex"], int(count[tk]), fallen)
			keys[pose] = "%s|%d|" % [tk, mesh.get_instance_id()]
		var s: Dictionary = sp["slot"]
		var col: Color = lin[int(sp["side"])] if int(sp["side"]) < lin.size() else Color.WHITE
		var ready_mesh: Mesh = (pm["ready"] as Dictionary)["mesh"]
		var aabb: AABB = ready_mesh.get_aabb()
		var lying := Models.has_pose_model(String(sp["type"]), "fallen", true)
		figs.append({"fid": sp["fid"], "type": sp["type"], "side": int(sp["side"]), "role": sp["role"], "home": s["pos"], "y": float(s["y"]),
			"yaw": float(s["yaw"]), "keys": keys, "lin": col, "h": aabb.end.y, "w": maxf(aabb.size.x, 1.0),
			"len": maxf(aabb.size.z, 1.0), "lying": lying, "hold": "stand", "motions": [], "phase": Choreo.hash_phase("fig", figs.size()),
			"tier": int(s.get("tier", 2)), "back": plan["back"][int(sp["side"])] if int(sp["side"]) < (plan["back"] as Array).size() else s["pos"],
			"members": sp.get("members", [])})
	banners = []
	for si in colours.size():
		var bn: Node3D = wv.make_banner(colours[si], int(emblems[si]) if si < emblems.size() else 0, 11.0, Vector2(5.4, 3.6))
		bn.name = "Banner%d" % si
		add_child(bn)
		banners.append(bn)
	_dirty = true


func clear() -> void:
	_fig_of = []
	for g in groups.values():
		(g["mi"] as Node).queue_free()
	groups.clear()
	for b in banners:
		(b as Node).queue_free()
	banners = []
	figs = []
	n_fighters = 0


func _group(gk: String, mesh: Mesh, tex: Texture2D, cap: int, fallen: bool) -> Dictionary:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = cap
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.name = gk.validate_node_name()
	mi.multimesh = mm
	mi.material_override = _mat(tex, fallen)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.lod_bias = lod_bias
	add_child(mi)
	return {"mi": mi, "n": 0, "cap": cap}


func _mat(tex: Texture2D, fallen: bool) -> ShaderMaterial:
	var key := "%d:%s" % [tex.get_instance_id() if tex != null else 0, fallen]
	if not _mats.has(key):
		var m: ShaderMaterial = wv.model_mat(Color.WHITE, tex, -1.0, true)
		m.set_shader_parameter("fig_lift", 1.0)
		if m.next_pass != null:
			if ink == null:
				ink = ShaderMaterial.new()
				ink.shader = (m.next_pass as ShaderMaterial).shader
				ink.set_shader_parameter("screen", wv.view_size)
			m.next_pass = ink
		if fallen:
			m.set_shader_parameter("desat", FALLEN_DESAT)
			m.set_shader_parameter("tint", 0.92)
		_mats[key] = m
	return _mats[key]


## The ink's width in pixels of the view (`width` near, `far` far), and the view's size.
func set_ink_px(width: float, far: float, view: Vector2) -> void:
	if ink == null:
		return
	ink.set_shader_parameter("width_px", width)
	ink.set_shader_parameter("far_px", far)
	ink.set_shader_parameter("screen", view)


## How soon the figures drop to their lower levels of detail (GeometryInstance3D.lod_bias: 1 the engine's own
## choice, lower sooner): a crowd of small figures needs far fewer triangles than a close fight.
func set_lod_bias(b: float) -> void:
	lod_bias = b
	for g in groups.values():
		(g["mi"] as GeometryInstance3D).lod_bias = b


## Figures cast shadows (or not: the quality ladder's lower rungs).
func set_shadows(on: bool) -> void:
	shadows = on
	for g in groups.values():
		(g["mi"] as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- holding: the state at a seek --------------------------------------------------------------------

## Snaps every figure to `state` (a BattleTimeline state): standing, fallen or gone, no motion.
## `out_sides`: by side, true when the side has left the field (its colour party goes too).
func snap(state: Dictionary, out_sides: Array) -> void:
	for f in figs:
		f["motions"] = []
		var fid: int = f["fid"]
		if fid >= 0:
			f["hold"] = hold_of(f["members"], state)
		else:
			f["hold"] = "gone" if bool(out_sides[int(f["side"])]) else "stand"
	_dirty = true


## A figure's hold for its fighters `members` at `state`: standing while any of them stands; else gone while
## any lives (fled, or lost with its army); else fallen.
static func hold_of(members: Array, state: Dictionary) -> String:
	var lives := false
	for fid in members:
		var fs: Dictionary = state.fighters[int(fid)]
		if fs.alive and not fs.fled and not fs.lost:
			return "stand"
		if fs.alive:
			lives = true
	return "gone" if lives else "fallen"


## The fighters a figure stands for (one, or a file's).
func members_of(i: int) -> Array:
	return figs[i]["members"] if i >= 0 and i < figs.size() else []


func set_hold(i: int, hold: String) -> void:
	if i < 0 or i >= figs.size():
		return
	figs[i]["hold"] = hold
	figs[i]["was_active"] = true


## Adds motion `m` ({"kind", "t0", "dur", ...}) to figure `i`, replacing any of the same kind.
func add_motion(i: int, m: Dictionary) -> void:
	if i < 0 or i >= figs.size():
		return
	var list: Array = figs[i]["motions"]
	for k in range(list.size() - 1, -1, -1):
		if String(list[k]["kind"]) == String(m["kind"]):
			list.remove_at(k)
	list.append(m)
	figs[i]["was_active"] = true


## The figure indices of side `si`'s colour party (standard bearer, musician).
func extras_of(si: int) -> Array:
	var out := []
	for i in range(n_fighters, figs.size()):
		if int(figs[i]["side"]) == si:
			out.append(i)
	return out


# --- where each figure is at a moment ---------------------------------------------------------------

## Figure `i` at clock time `now`: {"pos": Vector2, "y", "yaw", "pose", "fall" (0..1), "scale", "hop", "hurt"
## (0..1), "lying" (drawn in the fallen pose), "shown"}.
func pose_at(i: int, now: float) -> Dictionary:
	var f: Dictionary = figs[i]
	var out := {"pos": f["home"], "y": float(f["y"]), "yaw": float(f["yaw"]), "pose": "ready", "fall": 0.0, "scale": 1.0, "hop": 0.0,
		"hurt": 0.0, "lying": false, "shown": true, "extra_y": 0.0}
	var hold := String(f["hold"])
	if hold == "fallen":
		out["fall"] = 1.0
		out["lying"] = bool(f["lying"])
		out["pose"] = "fallen"
	elif hold == "gone":
		out["shown"] = false
		out["scale"] = 0.0
	var home: Vector2 = f["home"]
	var fwd := Vector2(-sin(float(f["yaw"])), -cos(float(f["yaw"])))
	for m in f["motions"]:
		var t: float = now - float(m["t0"])
		var dur: float = maxf(float(m.get("dur", 0.0)), 0.0001)
		if t < 0.0:
			continue
		match String(m["kind"]):
			"deploy":
				if t < dur and hold == "stand":
					var k := t / dur
					var e := k * k * (3.0 - 2.0 * k)
					out["pos"] = home - fwd * DEPLOY_STEP * (1.0 - e)
					out["pose"] = "march"
					out["hop"] = absf(sin(t * STEP_RATE + float(f["phase"]))) * HOP
			"lunge":
				var to: Vector2 = m["to"]
				var d: Vector2 = to - home
				var reach: float = minf(d.length() * LUNGE_SHARE, LUNGE_MAX)
				var dir: Vector2 = d.normalized() if d.length() > 0.01 else fwd
				var push := 0.0
				if t < LUNGE_OUT:
					push = sin(t / LUNGE_OUT * PI * 0.5)
				elif t < LUNGE_OUT + LUNGE_BACK:
					push = cos((t - LUNGE_OUT) / LUNGE_BACK * PI * 0.5)
				if reduced_motion:
					push = 0.0
				if hold == "stand" or t < LUNGE_OUT + LUNGE_BACK:
					out["pos"] = (out["pos"] as Vector2) + dir * reach * push
					if t < STRIKE_HOLD and String(out["pose"]) != "fallen":
						out["pose"] = "strike"
			"shoot":
				if t < STRIKE_HOLD and String(out["pose"]) != "fallen":
					out["pose"] = "strike"
			"dive":
				var tgt: Vector2 = m["to"]
				var land_at: Vector2 = tgt + (home - tgt).normalized() * float(m.get("short", 3.0))
				var fl: float = float(m.get("flight", 0.25))
				var length: float = home.distance_to(land_at)
				if reduced_motion:
					if t < STRIKE_HOLD:
						out["pose"] = "strike"
				elif t < fl:
					var u := t / fl
					out["pos"] = home.lerp(land_at, u)
					out["extra_y"] = 4.0 * DIVE_APEX * length * u * (1.0 - u)
					out["pose"] = "strike"
				elif t < fl + DIVE_BACK:
					var u2 := (t - fl) / DIVE_BACK
					var e2 := u2 * u2 * (3.0 - 2.0 * u2)
					out["pos"] = land_at.lerp(home, e2)
					out["extra_y"] = 4.0 * 0.12 * length * e2 * (1.0 - e2)
					out["pose"] = "strike" if u2 < 0.35 else "march"
			"recoil":
				if t < RECOIL:
					var r := t / RECOIL
					var away: Vector2 = m.get("away", -fwd)
					if not reduced_motion:
						out["pos"] = (out["pos"] as Vector2) + away * sin(r * PI) * RECOIL_DIST
					out["hurt"] = 1.0 - r
			"topple":
				if hold == "fallen" and t < TOPPLE and not reduced_motion:
					var k2 := t / TOPPLE
					out["fall"] = k2 * k2 * (3.0 - 2.0 * k2)
					out["lying"] = false
					out["pose"] = "ready"
			"rout":
				if hold == "gone":
					var back: Vector2 = m["to"]
					if t < dur:
						var k3 := t / dur
						var start: Vector2 = m.get("from", home)
						out["pos"] = start.lerp(back, k3)
						var away2: Vector2 = (back - start)
						out["yaw"] = atan2(-away2.x, -away2.y)
						out["pose"] = "march"
						out["hop"] = absf(sin(t * STEP_RATE * ROUT_SPEED + float(f["phase"]))) * HOP
						out["scale"] = 1.0 - smoothstep(0.62, 1.0, k3)
						out["shown"] = true
			"fade":
				if (hold == "gone" or hold == "faded") and t < dur:
					out["scale"] = 1.0 - smoothstep(0.0, 1.0, t / dur)
					out["shown"] = true
					if String(out["pose"]) == "fallen":
						out["pose"] = "ready"
			"cheer":
				if hold == "stand" and t < dur and not reduced_motion:
					out["hop"] = absf(sin(t * 7.0 + float(f["phase"]))) * HOP * 1.6
					if String(f["role"]) == "ruler":
						out["pose"] = "cheer"
	return out


## Whether any figure is moving at `now` (the stage skips the sync when nothing is).
func moving(now: float) -> bool:
	for f in figs:
		for m in f["motions"]:
			var t: float = now - float(m["t0"])
			if t >= -0.0001 and t < float(m.get("dur", 0.0)) + 0.6:
				return true
	return false


## Drops motions long finished (keeps the lists short over a long battle).
func prune(now: float) -> void:
	for f in figs:
		var list: Array = f["motions"]
		for k in range(list.size() - 1, -1, -1):
			if now - float(list[k]["t0"]) > float(list[k].get("dur", 0.0)) + 1.0:
				list.remove_at(k)


## Writes the figures at clock time `now` into their groups' MultiMeshes, and the banner onto each bearer.
## Incremental: only a figure with a motion under way (or one that just ended, or changed its hold) is posed
## again, and only its own instance is written (the renderer uploads what changed); a group is rewritten
## (compacted) only when a figure joins or leaves it. `force` poses every figure (a seek, a new battle).
## Each figure keeps where it stands now ("foot", "top": world points; "on": drawn) for the overlay.
func sync(now: float, force: bool = false) -> void:
	var todo: Array = []
	if force or _dirty:
		todo = range(figs.size())
		_dirty = false
	else:
		for i in figs.size():
			var f: Dictionary = figs[i]
			var active := false
			for m in f["motions"]:
				var t: float = now - float(m["t0"])
				if t >= -0.0001 and t < float(m.get("dur", 0.0)) + 0.05:
					active = true
					break
			if active or bool(f.get("was_active", false)):
				todo.append(i)
			f["was_active"] = active
	if todo.is_empty():
		return
	var rebuild := {}
	var moved: Array = []
	for i in todo:
		var f: Dictionary = figs[i]
		var p := pose_at(i, now)
		var shown: bool = bool(p["shown"]) and float(p["scale"]) >= 0.01
		var gk := ""
		if shown:
			var lying: bool = bool(p["lying"])
			var pose := "fallen" if lying else String(p["pose"])
			if pose == "fallen" and not lying:
				pose = "ready"
			var keys: Dictionary = f["keys"]
			var base_key: String = keys.get(pose, keys["ready"])
			gk = base_key + ("f" if String(f["hold"]) == "fallen" and float(p["fall"]) >= 0.999 else "s")
			f["xf"] = _xform(f, p)
			f["tint"] = 1.0 - float(p["hurt"])
			var xf: Transform3D = f["xf"]
			var h: float = float(f["h"]) * float(p["scale"])
			if float(p["fall"]) > 0.5:
				h = minf(h, Kit.FIG * 0.35)
			f["foot"] = xf.origin
			f["top"] = xf.origin + Vector3.UP * h
		elif String(f["role"]) == "bearer" and int(f["side"]) < banners.size():
			(banners[int(f["side"])] as Node3D).visible = false
		f["on"] = shown
		var old := String(f.get("gk", ""))
		if old != gk:
			if old != "":
				rebuild[old] = true
			if gk != "":
				rebuild[gk] = true
			f["gk"] = gk
		elif gk != "":
			moved.append(i)
	for gk2 in rebuild.keys():
		var g2: Dictionary = groups[gk2]
		var mm2: MultiMesh = (g2["mi"] as MultiMeshInstance3D).multimesh
		var n := 0
		for f2 in figs:
			if String(f2.get("gk", "")) != gk2 or n >= int(g2["cap"]):
				continue
			mm2.set_instance_transform(n, f2["xf"])
			mm2.set_instance_custom_data(n, _custom(f2))
			f2["gi"] = n
			n += 1
		g2["n"] = n
		mm2.visible_instance_count = n
		(g2["mi"] as Node3D).visible = n > 0
	for i2 in moved:
		var f3: Dictionary = figs[i2]
		var gk3 := String(f3["gk"])
		if rebuild.has(gk3):
			continue
		var g3: Dictionary = groups[gk3]
		var gi: int = int(f3.get("gi", -1))
		if gi < 0 or gi >= int(g3["n"]):
			continue
		var mm3: MultiMesh = (g3["mi"] as MultiMeshInstance3D).multimesh
		mm3.set_instance_transform(gi, f3["xf"])
		mm3.set_instance_custom_data(gi, _custom(f3))


static func _custom(f: Dictionary) -> Color:
	var lin: Color = f["lin"]
	return Color(lin.r, lin.g, lin.b, float(f.get("tint", 1.0)))


## A figure's transform at pose `p`, and its banner when it is the bearer.
func _xform(f: Dictionary, p: Dictionary) -> Transform3D:
	var lying: bool = bool(p["lying"])
	var yaw: float = p["yaw"]
	var basis := Basis(Vector3.UP, yaw)
	var fall: float = p["fall"]
	if fall > 0.0 and not lying:
		## topple about the feet, backwards (away from the enemy)
		basis = basis * Basis(Vector3.RIGHT, fall * PI * 0.5)
	var sc: float = p["scale"]
	basis = basis.scaled(Vector3.ONE * sc)
	var pos: Vector2 = p["pos"]
	var y: float = float(p["y"]) + float(p["hop"]) + float(p["extra_y"])
	if pos != (f["home"] as Vector2):
		y = maxf(_ground(pos, float(f["y"])), 0.0) + float(p["hop"]) + float(p["extra_y"])
	var xf := Transform3D(basis, Vector3(pos.x, y, pos.y))
	if String(f["role"]) == "bearer" and int(f["side"]) < banners.size():
		var bn: Node3D = banners[int(f["side"])]
		bn.transform = Transform3D(Basis(Vector3.UP, yaw + PI * 0.5).scaled(Vector3.ONE * sc), xf * Vector3(0.95, 1.2, 0.0))
		bn.visible = sc > 0.05 and fall < 0.5
	return xf


func _ground(p: Vector2, fallback: float) -> float:
	return land.height_at(p) if land != null else fallback


# --- reading -------------------------------------------------------------------------------------------

## The figure of fighter `fid` (its own, or its file's), or -1.
func index_of(fid: int) -> int:
	return int(_fig_of[fid]) if fid >= 0 and fid < _fig_of.size() and _fig_of[fid] != null else -1


## Figure `i`'s feet and head as last synced, world (the overlay draws every frame from these), or [] when it
## isn't drawn.
func ends_now(i: int) -> Array:
	if i < 0 or i >= figs.size():
		return []
	var f: Dictionary = figs[i]
	if not bool(f.get("on", false)):
		return []
	return [f["foot"], f["top"]]


## Figure `i`'s feet and head at `now`, world (for plates and picking), or [] when it isn't shown.
func ends_at(i: int, now: float) -> Array:
	var p := pose_at(i, now)
	if not bool(p["shown"]) or float(p["scale"]) < 0.05:
		return []
	var f: Dictionary = figs[i]
	var pos: Vector2 = p["pos"]
	var y: float = float(p["y"]) + float(p["hop"]) + float(p["extra_y"])
	if pos != (f["home"] as Vector2):
		y = maxf(_ground(pos, float(f["y"])), 0.0) + float(p["hop"]) + float(p["extra_y"])
	var h: float = float(f["h"]) * float(p["scale"])
	if float(p["fall"]) > 0.5:
		h = minf(h, Kit.FIG * 0.35)
	return [Vector3(pos.x, y, pos.y), Vector3(pos.x, y + h, pos.y)]


## The figures drawn now, per group (the perf readout): {"groups", "figures"}.
func draw_stats() -> Dictionary:
	var ng := 0
	var nf := 0
	for g in groups.values():
		if int(g["n"]) > 0:
			ng += 1
			nf += int(g["n"])
	return {"groups": ng, "figures": nf}


## Every figure's hold and pose at `now`, sorted lines (tests compare a played stage with a sought one).
func snapshot(now: float) -> Array:
	var out := []
	for i in figs.size():
		var p := pose_at(i, now)
		var f: Dictionary = figs[i]
		var pos: Vector2 = p["pos"]
		out.append("%d %s %s %s %.1f,%.1f %.2f %.2f" % [i, f["type"], f["hold"], "lying" if p["lying"] else String(p["pose"]), pos.x, pos.y,
			float(p["scale"]), float(p["fall"])])
	return out
