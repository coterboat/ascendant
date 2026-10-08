## Battles at walls on the 3D stage, the pure part (no nodes): where every fighter and every piece of siege
## scenery stands when the battle's log has a `siege` block (M3c S-5, #103; design/M3C_SIEGES.md 4.4, 10.3).
## It reads the battle log, the baked land (terrain3d.gd) and the fort the stage drew (its frame and kit), and never
## touches the game or draws a random number, so the same log on the same land always stands the same way (tests).
## The stage only shows what the rules decided: nothing here changes a result.
##
##   var info := BattleWalls.info_of(frame, kind, kit, look, radius, cut)   # the fort, as the stage drew it
##   var plan := BattleWalls.plan(log, terrain, {"walls": info, "engines": n}, aspect, groups)
##
## The kinds (siege.kind) and where they stand, in the fort's own frame (x across, z toward the back, the gate on -z,
## y up from the frame's origin; BattleWalls.to_world turns it into the land's):
##   storm   the garrison (siege.garrison) holds the walls: its Volley tier and mages along the top of the gate-side
##           wall, its ruler and commander on the gatehouse, the rest along the side walls and in the yard behind the
##           gate; where the kit has nothing to stand on (the Clans' stakes, a palisade) it stands in the yard just
##           behind the stakes. The stormers form up at the foot of the gate-side wall, with ladders leaning on it (the
##           Crown) or the trunk before the gate (the Clans).
##   breach  the gate-side wall is down: the garrison's front rank stands in the gap, its other ranks behind it in the
##           yard (then on the stubs of the side walls); the attackers form up before the gap.
##   open    (a sally, a relief, the gate battle) nobody holds the ground: both lines form up before the gate, the side
##           with fighters coming from inside (siege.from_inside) nearest it, and those fighters march out of the gate
##           (plan.walls.march: each one's path from the yard, through the gate, to its place).
## Engines are not fighters and the log does not carry them: the stage passes how many the besiegers still carry
## (`engines`, from the game it was given), and they stand at the flanks of the besiegers' lines among their tents.
##
## Returns BattleFormation.plan's shape ({"site", "axis" (outward from the walls), "near" (the side at the walls),
## "far", "where": "walls", "files", "slots", "extras", "back", "footprint", "fort": {}, "depths", "width"}), its slots
## with two more keys, "station" ("deck", "gate_top", "yard", "reserve", "line") and "lift" (how high the feet stand
## above the ground there, which a lunge keeps), plus
##   "walls": {"info", "kind", "garrison": side or -1, "besieger": side, "stations": [by fighter id],
##             "march": {fighter id: {"path": [Vector2], "delay", "dur"}}, "scenery", "frame_extra": [Vector3] (what the
##             camera also keeps in view), "plate": Vector3 (where the walls' plate hangs), "turn": degrees, "trunk"}
extends RefCounted

const Formation := preload("res://world3d/battle_formation.gd")
const Models := preload("res://world3d/models.gd")

const STORM_GAP := 5.0 ## from a wall's outer edge to the stormers' front line (the ladders lean in between)
const RAM_GAP := 9.0 ## the same with the trunk before the gate
const GATE_MARGIN := 4.0 ## an open battle's near line: its back edge this far out of the gate (as a capital's gate battle)
const CAMP_GAP := 9.0 ## from the besiegers' line to their tents
const MARCH_TIME := 1.25 ## a sally's march fits the deploy beat (BattlePlayer.DEPLOY is 1.5 s)
const ARRIVAL_ROAD := 30.0 ## a relief army comes in from this far behind its line
const TURNS := [0.0, 10.0, -10.0, 20.0, -20.0, 30.0, -30.0, 45.0, -45.0] ## the outside lines swing about the gate
const LEVEL_OF := {"palisade": 1, "keep": 2, "citadel": 3}
const MAX_ENGINES := 6

## What each fort model's walls are (fort frame, world units), measured off the models as the board draws them (the model
## table's `side`): "floor" the yard's height; "outer" how far from the centre the gate side's farthest point stands (the
## lines keep clear of it); "face" the gate-side wall's outer face (the ladders lean there), "wall_h" its height above the
## floor; "gate" half the gate's width; "ladder_xs" where the Crown's ladders lean on the gate-side wall; "decks" and "sides" the lanes a fighter can stand on along the top of the walls,
## [from x, from z, to x, to z, y]; "gate_top" the gatehouse's roof, [x, z, length, y]; "yard" the open floor (rows from z0
## to z1; "x" a half width for a square one, or "x0" and "x1", "r" and "cz" for a round one; "extra" more patches of floor
## to fill when it is full); "reserve" the z of the first row of ground behind the fort; "solids" what a fighter must not stand inside ({"box": [x0, x1, z0, z1]} or {"ring": [r0, r1], "gap":
## half width of the gate gap}, up to "top"); "gate_path" the gate passage's z, inner then outer; "breach_z" the z the breach
## cuts the gate side at. A model table row may carry a "walls" group that overrides any of these (an art pass retunes a
## model without touching this file).
const SPECS := {
	"fort.kingdom": {
		"floor": 1.0, "outer": 17.5, "face": 15.0, "wall_h": 10.0, "gate": 3.5, "gate_path": [-8.5, -17.5], "breach_z": -10.5, "ladder_xs": [-10.5, 10.5],
		"decks": [[-5.3, -11.0, -15.0, -11.0, 10.8], [5.3, -11.0, 15.0, -11.0, 10.8]],
		"gate_top": [0.0, -12.7, 6.0, 14.2],
		"sides": [[-12.5, -7.5, -12.5, 6.5, 10.8], [12.5, -7.5, 12.5, 6.5, 10.8]],
		"yard": {"x": 9.3, "z0": -6.4, "z1": 8.0}, "reserve": 25.0,
		"solids": [{"box": [-16.0, -3.5, -15.2, -9.2], "top": 10.8}, {"box": [3.5, 16.0, -15.2, -9.2], "top": 10.8},
			{"box": [-16.0, -10.2, -15.2, 8.0], "top": 10.8}, {"box": [10.2, 16.0, -15.2, 8.0], "top": 10.8},
			{"box": [-16.0, 16.0, 10.4, 15.0], "top": 10.8}, {"box": [-17.0, -8.0, 7.5, 17.5], "top": 20.0},
			{"box": [8.0, 17.0, 7.5, 17.5], "top": 20.0}],
	},
	"fortress.kingdom": {
		"floor": 1.0, "outer": 36.0, "face": 30.5, "wall_h": 15.0, "gate": 4.0, "gate_path": [-23.0, -36.0], "breach_z": -19.0, "ladder_xs": [-16.0, 16.0],
		"decks": [[-9.6, -25.0, -19.0, -25.0, 16.2], [9.6, -25.0, 19.0, -25.0, 16.2]],
		"gate_top": [0.0, -26.5, 10.0, 16.2],
		"sides": [[-26.0, -18.0, -26.0, 18.0, 16.2], [26.0, -18.0, 26.0, 18.0, 16.2]],
		"yard": {"x": 20.0, "z0": -19.0, "z1": 9.0}, "reserve": 42.0,
		"solids": [{"box": [-31.0, -4.0, -30.6, -22.4], "top": 16.2}, {"box": [4.0, 31.0, -30.6, -22.4], "top": 16.2},
			{"box": [-31.0, -22.0, -30.6, 30.6], "top": 16.2}, {"box": [22.0, 31.0, -30.6, 30.6], "top": 16.2},
			{"box": [-31.0, 31.0, 22.0, 31.0], "top": 16.2}, {"box": [-10.0, 12.0, 11.5, 31.0], "top": 45.0}],
	},
	"fort.beasts": {
		"floor": 1.0, "outer": 19.5, "face": 17.5, "wall_h": 9.0, "gate": 8.0, "gate_path": [-12.5, -19.5], "breach_z": -10.5, "ladder_xs": [-12.5, 12.5],
		"decks": [], "gate_top": [], "sides": [],
		"yard": {"x": 12.8, "z0": -13.0, "z1": 0.5, "extra": [{"x0": -12.8, "x1": 0.8, "z0": 4.0, "z1": 13.0}]}, "reserve": 26.0,
		"solids": [{"box": [-18.0, -8.0, -18.0, -15.2], "top": 10.0}, {"box": [8.0, 18.0, -18.0, -15.2], "top": 10.0},
			{"box": [-18.0, -15.2, -18.0, 18.0], "top": 10.0}, {"box": [15.2, 18.0, -18.0, 18.0], "top": 10.0},
			{"box": [-18.0, 18.0, 15.2, 18.5], "top": 10.0}, {"box": [2.0, 18.0, 2.0, 18.0], "top": 27.0}],
	},
	"fortress.beasts": {
		"floor": 1.0, "outer": 34.0, "face": 30.0, "wall_h": 9.5, "gate": 8.5, "gate_path": [-22.0, -34.0], "breach_z": -19.0, "ladder_xs": [-16.0, 16.0],
		"decks": [], "gate_top": [], "sides": [],
		"yard": {"x": 21.0, "z0": -21.0, "z1": 8.0}, "reserve": 42.0,
		"solids": [{"box": [-35.0, -9.0, -30.6, -27.0], "top": 10.5}, {"box": [9.0, 35.0, -30.6, -27.0], "top": 10.5},
			{"box": [-31.0, -27.0, -30.6, 30.6], "top": 10.5}, {"box": [27.0, 31.0, -30.6, 30.6], "top": 10.5},
			{"box": [-31.0, 31.0, 27.0, 31.0], "top": 10.5}, {"box": [-17.0, 17.0, 12.5, 28.0], "top": 19.0},
			{"box": [-35.0, -22.0, -37.0, -22.5], "top": 28.0}, {"box": [22.0, 35.0, -37.0, -22.5], "top": 28.0},
			{"box": [-35.0, -22.0, 22.5, 37.0], "top": 28.0}, {"box": [22.0, 35.0, 22.5, 37.0], "top": 28.0}],
	},
	## the code palisade (a ring of stakes, open at the gate; both kits), and the stand-in for a fort whose model is missing
	"palisade": {
		"floor": 0.5, "outer": 14.5, "face": 12.5, "wall_h": 4.4, "gate": 2.6, "gate_path": [-8.0, -14.5], "breach_z": -6.0, "ladder_xs": [-6.0, 6.0],
		"decks": [], "gate_top": [], "sides": [],
		"yard": {"r": 10.8, "cz": 0.0, "z0": -7.0, "z1": 7.0}, "reserve": 17.0,
		"solids": [{"ring": [11.6, 13.4], "top": 4.4, "gap": 2.6}],
	},
}


# --- the fort's walls --------------------------------------------------------------------------------------

## The walls spec of a fort `kind` ("palisade", "fort" or "fortress", the model table's kinds) in `kit` (the faction whose
## kit it wears) at `radius` (half its side): SPECS, under the model row's own "walls" group. A fort whose model is not
## on disk (drawn from code) is a round palisade of its size.
static func spec_of(kind: String, kit: String, radius: float = 13.5) -> Dictionary:
	var spec: Dictionary
	if kind == "palisade" or Models.building_model(kind, kit).is_empty():
		spec = (SPECS["palisade"] as Dictionary).duplicate(true)
		if kind != "palisade":
			var s := radius / 13.5
			for key in ["outer", "face", "wall_h", "gate", "breach_z", "reserve"]:
				spec[key] = float(spec[key]) * s
			spec["gate_path"] = [-8.0 * s, -14.5 * s]
			spec["ladder_xs"] = [-6.0 * s, 6.0 * s]
			spec["yard"] = {"r": 10.8 * s, "cz": 0.0, "z0": -7.0 * s, "z1": 7.0 * s}
			spec["solids"] = [{"ring": [11.6 * s, 13.4 * s], "top": 4.4, "gap": 2.6 * s}]
	else:
		spec = (SPECS["%s.%s" % [kind, "beasts" if kit == "beasts" else "kingdom"]] as Dictionary).duplicate(true)
	var over: Variant = Models.building_row(kind, kit).get("walls")
	if over is Dictionary:
		for key in (over as Dictionary).keys():
			spec[key] = (over as Dictionary)[key]
	return spec


## What the planner needs of a fort the stage drew: `frame` its Transform3D (gate on local -Z), `kind` and `kit`, `look`
## the damage look it wears (SiegeRules.damage_look), `radius` half its side, `cut` the code fallback's dither cut for that
## look ([Vector4 plane, y] as WorldView._damage_cut gives it; [] when none).
static func info_of(frame: Transform3D, kind: String, kit: String, look: String, radius: float, cut: Array = []) -> Dictionary:
	var fz: Vector3 = frame.basis * Vector3(0, 0, -1)
	var front := Vector2(fz.x, fz.z).normalized()
	return {"frame": frame, "kind": kind, "kit": kit, "look": look, "radius": radius, "cut": cut, "front": front,
		"lat": Vector2(-front.y, front.x), "centre": Vector2(frame.origin.x, frame.origin.z), "base_y": frame.origin.y,
		"spec": spec_of(kind, kit, radius)}


## Fort-frame (x across, z toward the back) to the land's xz.
static func to_world(info: Dictionary, x: float, z: float) -> Vector2:
	var p: Vector3 = (info["frame"] as Transform3D) * Vector3(x, 0.0, z)
	return Vector2(p.x, p.z)


## The land's xz to fort-frame (x, z).
static func to_local(info: Dictionary, p: Vector2) -> Vector2:
	var fr: Transform3D = info["frame"]
	var q: Vector3 = fr.affine_inverse() * Vector3(p.x, fr.origin.y, p.y)
	return Vector2(q.x, q.z)


## The world height of fort-frame height `y`.
static func world_y(info: Dictionary, y: float) -> float:
	return float(info["base_y"]) + y


## Whether the damage look's dither cut hides the point (`p` xz, `y` world): the shader's own test.
static func hidden(info: Dictionary, p: Vector2, y: float) -> bool:
	var cut: Array = info.get("cut", [])
	if cut.size() < 2:
		return false
	var pl: Vector4 = cut[0]
	if pl.x * pl.x + pl.y * pl.y + pl.z * pl.z <= 0.25:
		return false
	return pl.x * p.x + pl.z * p.y > pl.w and y > float(cut[1])


## Whether a fighter whose feet are at `p` (xz) and `y` (world) stands inside a wall: in a solid (a box, or the stakes'
## ring) and below its top. Standing on the top is not inside.
static func inside_wall(info: Dictionary, p: Vector2, y: float) -> bool:
	var l := to_local(info, p)
	var yl := y - float(info["base_y"])
	for s in (info["spec"] as Dictionary).get("solids", []):
		if yl >= float(s["top"]) - 0.4:
			continue
		if s.has("box"):
			var b: Array = s["box"]
			if l.x > float(b[0]) and l.x < float(b[1]) and l.y > float(b[2]) and l.y < float(b[3]):
				return true
		elif s.has("ring"):
			var r: Array = s["ring"]
			var d := l.length()
			if d > float(r[0]) and d < float(r[1]) and not (l.y < 0.0 and absf(l.x) < float(s.get("gap", 0.0))):
				return true
	return false


## The fort-level of a siege block's `fort` word (0 for none).
static func level_of(siege: Dictionary) -> int:
	return int(LEVEL_OF.get(String(siege.get("fort", "")), 0))


## The words on the plate hung over the walls for the whole battle (every number from the siege block, which has them from
## the rules): "Walls: +6 defense (9 of 9)" in a storm, "Breached: no walls, +2 cover" at the breach, "Outside the walls: +2
## cover from inside" / "...: no cover" in an open battle. "" without a siege block.
static func plate_text(siege: Dictionary) -> String:
	var cover := int(siege.get("cover_defense", 0))
	match String(siege.get("kind", "")):
		"storm":
			return String(FortView.siege_chip(siege).get("text", ""))
		"breach":
			return "Breached: no walls, +%d cover" % cover
		"open":
			return "Outside the walls: +%d cover from inside" % cover if cover > 0 else "Outside the walls: no cover for anyone"
	return ""


## The line under the battle's first caption, before the first blow lands: what the walls (or their lack) mean for the fight
## that is about to be played. `place` is the province's name. "" without a siege block.
static func caption_text(siege: Dictionary, place: String) -> String:
	var walls := int(siege.get("walls", 0))
	var top := int(siege.get("walls_max", 0))
	var cover := int(siege.get("cover_defense", 0))
	match String(siege.get("kind", "")):
		"storm":
			return "The walls of %s (%d of %d standing) give its garrison +%d defense in this storm: every blow at it is weaker." % [
				place, walls, top, int(siege.get("walls_defense", 0))]
		"breach":
			return "The walls of %s are down: nobody holds the ground, and the garrison keeps +%d cover among the ruins." % [place, cover]
		"open":
			if cover > 0:
				return "Outside the walls of %s nobody holds the ground, but those who came out of the gate keep +%d cover." % [place, cover]
			return "Outside the walls of %s nobody holds the ground: no walls, no terrain, no cover for anyone." % place
	return ""


# --- the plan ----------------------------------------------------------------------------------------------

## The ground plan of a battle with a `siege` block at the fort `world["walls"]` (info_of's); `world["engines"]` is how many
## siege engines the besiegers carry (default 0). Same arguments and result shape as BattleFormation.plan.
static func plan(battle_log: Dictionary, t, world: Dictionary, aspect: float = 2.6, groups: Dictionary = {}) -> Dictionary:
	var info: Dictionary = world["walls"]
	var spec: Dictionary = info["spec"]
	var siege: Dictionary = battle_log.siege
	var sides: Array = battle_log.sides
	var kind := String(siege.get("kind", "open"))
	var reps: Dictionary = groups.get("reps", {})
	var gi := int(siege.get("garrison", -1))
	## who stands where. The garrison holds the walls in a storm and a breach. In an open battle the side with fighters
	## who came out of the gate stands nearest it; else the besiegers hold the ground at the walls and the relief comes
	## to them. The besieger is the side that is not the fort's owner.
	var out_side := -1
	for si in sides.size():
		for fid in sides[si].fighters:
			if (siege.get("from_inside", []) as Array).has(String(battle_log.fighters[int(fid)].army)):
				out_side = si
	var near := 0
	if kind == "open":
		near = out_side if out_side >= 0 else (1 - gi if gi >= 0 and sides.size() > 1 else 0)
	elif gi >= 0:
		near = gi
	var far := 1 - near if sides.size() > 1 else near
	var besieger := 1 - gi if gi >= 0 and sides.size() > 1 else far
	## the lines: the outside lines as wide as the walls (a storm) or the gap (a breach) are, else as the screen likes
	var files := Formation._pick_files(battle_log, aspect, reps)
	var yard: Dictionary = spec["yard"]
	var garrison_files := zone_files(yard)
	if kind == "storm":
		files = clampi(int(floor((2.0 * float(spec["face"]) + 8.0) / Formation.FILE_PITCH)), 3, files)
	elif kind == "breach":
		garrison_files = mini(garrison_files, maxi(1, int(floor(2.0 * (float(spec["gate"]) * 3.0 + 3.0) / Formation.FILE_PITCH))))
		files = clampi(garrison_files + 2, 3, files)
	var lines := []
	var depths := [0.0, 0.0]
	var widest := 0.0
	for si in sides.size():
		lines.append(Formation.side_lines(battle_log, si, garrison_files if (si == near and kind != "open") else files, reps))
		depths[si] = _depth(lines[si])
		for ln in lines[si]:
			widest = maxf(widest, float(ln["width"]))
	var best := {}
	var best_wet := 1 << 30
	for deg in TURNS:
		var cand := _build(battle_log, t, info, kind, near, far, besieger, lines, depths, reps, deg, int(world.get("engines", 0)))
		if int(cand["wet"]) < best_wet:
			best_wet = int(cand["wet"])
			best = cand
			if best_wet == 0:
				break
	var out := best
	## a file's other fighters share its figure's place (M3 3.4's files)
	if not reps.is_empty():
		var slots: Array = out["slots"]
		var file_of: Array = groups.get("file_of", [])
		var members: Array = groups.get("members", [])
		for fid in slots.size():
			if slots[fid] == null and fid < file_of.size():
				slots[fid] = slots[int(members[int(file_of[fid])][0])]
	out["near"] = near
	out["far"] = far
	out["where"] = "walls"
	out["files"] = files
	out["depths"] = depths
	out["width"] = widest
	out["fort"] = {}
	return out


## One candidate placement with the outside lines swung `deg` degrees about the gate.
static func _build(battle_log: Dictionary, t, info: Dictionary, kind: String, near: int, far: int, besieger: int, lines: Array,
		depths: Array, reps: Dictionary, deg: float, engines: int) -> Dictionary:
	var spec: Dictionary = info["spec"]
	var sides: Array = battle_log.sides
	var siege: Dictionary = battle_log.siege
	var slots := []
	slots.resize((battle_log.get("fighters", []) as Array).size())
	var extras := []
	var back := []
	back.resize(sides.size())
	var front: Vector2 = info["front"]
	var outer := float(spec["outer"])
	var pivot := to_world(info, 0.0, -outer)
	var rot := deg_to_rad(deg)
	var wides := [0.0, 0.0]
	for si in sides.size():
		for ln in lines[si]:
			wides[si] = maxf(float(wides[si]), float(ln["width"]))
	## --- the side holding the fort (a storm, a breach): on it and in it
	var yard_z := 0.0
	if kind != "open":
		var res := _garrison(battle_log, info, near, kind, reps)
		var face_out := atan2(-front.x, -front.y)
		for fid in res["places"].keys():
			var pl: Dictionary = res["places"][fid]
			var gy := float(pl["y"])
			if is_nan(gy):
				gy = maxf(t.height_at(pl["pos"]), 0.0) ## ground behind the fort
			slots[int(fid)] = {"pos": pl["pos"], "y": gy, "yaw": face_out, "side": near, "tier": int(pl["tier"]), "line": int(pl["line"]),
				"file": int(pl["file"]), "width": float(pl["width"]), "depth": float(pl["depth"]), "station": String(pl["station"]),
				"rail": kind == "storm" or String(pl["station"]) in ["deck", "gate_top"]} ## strikes where it stands: a wall is in the way
		yard_z = float(res["last_z"])
		var hw := float((spec["yard"] as Dictionary).get("x", float((spec["yard"] as Dictionary).get("r", 8.0)) * 0.5)) * 0.55
		for k in 2:
			var pw := to_world(info, hw * (1.0 if k == 0 else -1.0), minf(yard_z + 1.0, float((spec["yard"] as Dictionary)["z1"])))
			extras.append({"type": "bearer" if k == 0 else "musician", "side": near, "pos": pw, "y": world_y(info, float(spec["floor"])), "yaw": face_out})
		back[near] = to_world(info, 0.0, float((spec["yard"] as Dictionary)["z1"])) ## routed fighters run back to the yard's end
	## --- the lines outside: s is how far from the gate-side face a line stands (its centre)
	var trunk := kind == "storm" and String(sides[far].faction) == "beasts"
	var front_edge: float
	if kind == "storm":
		front_edge = RAM_GAP if trunk else STORM_GAP
	elif kind == "breach":
		front_edge = maxf(3.0, absf(float(spec["breach_z"])) + Formation.FRONT_GAP - outer) ## the usual gap between the front lines, off the walls
	else:
		front_edge = GATE_MARGIN + float(depths[near]) + Formation.FRONT_GAP
	var outside: Array = [far] if kind != "open" else [near, far]
	for si in outside:
		var toward_gate: bool = kind == "open" and si == near
		var s_front := (GATE_MARGIN + float(depths[near])) if toward_gate else front_edge
		var look := front if toward_gate else -front ## the way the lines face
		var fv := look.rotated(rot)
		var yaw := atan2(-fv.x, -fv.y)
		var acc := 0.0
		var last_tier := -1
		var line_no := 0
		var commander_at := Vector2.INF
		for ln in lines[si]:
			if last_tier >= 0 and int(ln["tier"]) != last_tier:
				acc += Formation.TIER_GAP
			last_tier = int(ln["tier"])
			var depth: float = ln["depth"]
			var s_mid := (s_front - acc - depth * 0.5) if toward_gate else (s_front + acc + depth * 0.5)
			var w: float = ln["width"]
			var run := -w * 0.5
			var pitches: Array = ln["pitches"]
			var fids: Array = ln["fids"]
			for k in fids.size():
				var pitch: float = pitches[k]
				var off: float = run + pitch * 0.5
				run += pitch
				var pw := pivot + (to_world(info, off, -(outer + s_mid)) - pivot).rotated(rot)
				var fid := int(fids[k])
				slots[fid] = {"pos": pw, "y": maxf(t.height_at(pw), 0.0), "yaw": yaw, "side": si, "tier": int(ln["tier"]), "line": line_no, "file": k,
					"width": pitch, "depth": depth, "station": "line"}
				if battle_log.fighters[fid].role == "commander" and commander_at == Vector2.INF:
					commander_at = pw
			acc += depth
			line_no += 1
		var s_rear := (s_front - acc) if toward_gate else (s_front + acc)
		## the colour party beside the commander, or behind the lines
		var base := commander_at
		var spread := Formation.FILE_PITCH * 1.4
		if commander_at == Vector2.INF:
			var s_party := s_rear - Formation.LINE_PITCH * 0.5 if toward_gate else s_rear + Formation.LINE_PITCH * 0.5
			base = pivot + (to_world(info, 0.0, -(outer + s_party)) - pivot).rotated(rot)
			spread = Formation.FILE_PITCH * 0.7
		var lat := Vector2(-fv.y, fv.x)
		for k in 2:
			var p2: Vector2 = base + lat * (spread * (1.0 if k == 0 else -1.0))
			extras.append({"type": "bearer" if k == 0 else "musician", "side": si, "pos": p2, "y": maxf(t.height_at(p2), 0.0), "yaw": yaw})
		## routed fighters run away from the other side: out, or (the side at the gate) back to the gate
		var run_s := s_rear - 2.0 if toward_gate else s_rear + Formation.ROUT_RUN
		back[si] = pivot + (to_world(info, 0.0, -(outer + maxf(run_s, 0.5))) - pivot).rotated(rot)
	## --- who marches out of the gate
	var march := {}
	if kind == "open":
		march = _march(battle_log, info, slots, near, siege, pivot)
	## --- the wet check, the lift of everyone who stands above the ground
	var wet := 0
	var stations := []
	stations.resize(slots.size())
	for fid in slots.size():
		var sl = slots[fid]
		if sl == null:
			continue
		var station := String(sl["station"])
		stations[fid] = station
		if station == "line" or station == "reserve":
			var p: Vector2 = sl["pos"]
			if t.coast_at(p) < 2.5 or t.province_at(p) == "":
				wet += 1
			if station == "line":
				## a line swung about the gate never lands on the fort's base
				var lp := to_local(info, p)
				var keep := float(info["radius"]) + 1.0
				if absf(lp.x) < keep and absf(lp.y) < keep:
					wet += 1000
		sl["lift"] = float(sl["y"]) - maxf(t.height_at(sl["pos"]), 0.0)
	## --- the scenery, what the camera keeps in view, the ground to clear
	var scenery := _scenery(battle_log, t, info, kind, near, besieger, depths, wides, front_edge, trunk, engines, rot, pivot)
	var frame_extra: Array = (scenery["frame"] as Array).duplicate()
	var face := float(spec["face"])
	for sx in [-1.0, 1.0]:
		for z in [-(face + 4.0), 0.3 * face]: ## the gate-side corners, and the side walls half way back
			var fc := to_world(info, sx * (face + 5.0), z)
			frame_extra.append(Vector3(fc.x, world_y(info, float(spec["floor"])), fc.y))
			frame_extra.append(Vector3(fc.x, world_y(info, float(spec["floor"]) + float(spec["wall_h"]) + 10.0), fc.y))
	var footprint := _footprint(info, kind, depths, wides, front_edge, near, far, pivot, rot)
	var centre := Vector2.ZERO
	for c in footprint:
		centre += c
	centre /= maxf(1.0, float(footprint.size()))
	var plate_at := to_world(info, 0.0, -float(spec["face"]))
	var plate := Vector3(plate_at.x, world_y(info, float(spec["floor"]) + float(spec["wall_h"]) + 6.0), plate_at.y)
	frame_extra.append(plate + Vector3(0, 5.0, 0)) ## the plate's own height stays on screen
	return {"slots": slots, "extras": extras, "back": back, "site": centre, "axis": front, "footprint": footprint, "wet": wet,
		"walls": {"info": info, "kind": kind, "garrison": int(siege.get("garrison", -1)), "besieger": besieger, "stations": stations,
			"march": march, "scenery": scenery, "frame_extra": frame_extra, "plate": plate, "turn": deg, "trunk": trunk}}


# --- the side that holds the fort ---------------------------------------------------------------------------

## Where the side holding the fort stands: {"places": {fid: {"pos", "y", "tier", "line", "file", "width", "depth", "station"}},
## "last_z": the back-most row of the yard's z}. A storm: the deck (Volley tier and mages, then the front rank), the gatehouse
## (the ruler, then the commander), the side walls, then the yard in rows from the gate side back, then ground behind the fort. A
## breach: the yard in rows from the breach back, the side walls, then ground behind the fort.
static func _garrison(battle_log: Dictionary, info: Dictionary, si: int, kind: String, reps: Dictionary) -> Dictionary:
	var spec: Dictionary = info["spec"]
	var places := {}
	var rulers := []
	var commanders := []
	var volley := []
	var melee := []
	var tiers: Array = Formation.ordered_tiers(battle_log, si)
	for tier in 3:
		for fid in tiers[tier]:
			if not reps.is_empty() and not reps.has(int(fid)):
				continue
			var role := String(battle_log.fighters[int(fid)].role)
			if role == "ruler":
				rulers.append(int(fid))
			elif role == "commander" or tier == 2:
				commanders.append(int(fid))
			elif tier == 1:
				volley.append(int(fid))
			else:
				melee.append(int(fid))
	if kind == "storm":
		_fill(battle_log, info, places, _lanes(spec["decks"]), [volley, melee], "deck")
		_fill(battle_log, info, places, _top(spec["gate_top"]), [rulers, commanders], "gate_top")
		_fill(battle_log, info, places, _lanes(spec["sides"]), [melee, volley, rulers, commanders], "deck")
	## the yard in rows, rank order (the front rank first), a patch of floor after another
	var pool := _pool([melee, volley, rulers, commanders])
	var line_no := 0
	var last_z := float((spec["yard"] as Dictionary)["z0"])
	var zones := zones_of(spec)
	for zi in zones.size():
		if pool.is_empty():
			break
		var zone: Dictionary = zones[zi]
		var z := float(zone["z0"])
		var files := zone_files(zone)
		if kind == "breach" and zi == 0:
			z = float(spec["breach_z"]) + 2.5
			files = mini(files, maxi(1, int(floor(2.0 * (float(spec["gate"]) * 3.0 + 3.0) / Formation.FILE_PITCH))))
		var cx := zone_centre(zone)
		var rows := Formation.side_lines(battle_log, si, files, pool)
		## the rows close up (down to 60% of their depth) before anyone is left outside
		var tight := 1.0
		var fit := 0
		for k in [1.0, 0.9, 0.8, 0.7, 0.6]:
			var n := _rows_fitting(rows, z, float(zone["z1"]), k)
			if n > fit:
				fit = n
				tight = k
			if n == rows.size():
				break
		var spill := {}
		var last_depth := 0.0
		for ri in rows.size():
			var ln: Dictionary = rows[ri]
			if ri >= fit:
				for fid in ln["fids"]:
					spill[int(fid)] = true
				continue
			var depth: float = ln["depth"]
			z = z if ri == 0 else z + (last_depth + depth) * 0.5 * tight
			last_depth = depth
			_row(places, info, ln, cx, z, line_no, float(spec["floor"]), "yard")
			if zi == 0:
				last_z = z
			line_no += 1
		pool = spill
	## in a breach, what the yard cannot hold stands on the stubs of the side walls
	if kind == "breach" and not pool.is_empty():
		var left := []
		for fid in pool.keys():
			left.append(int(fid))
		left.sort()
		var lists := [left]
		_fill(battle_log, info, places, _lanes(spec["sides"]), lists, "deck")
		pool = _pool(lists)
	## and what is left stands on the ground behind the fort
	if not pool.is_empty():
		var rz := float(spec["reserve"])
		var first2 := true
		var last_d := 0.0
		for ln in Formation.side_lines(battle_log, si, maxi(zone_files(spec["yard"]), 6), pool):
			var d: float = ln["depth"]
			rz = rz if first2 else rz + last_d * 0.5 + d * 0.5
			first2 = false
			last_d = d
			_row(places, info, ln, 0.0, rz, line_no, -1.0, "reserve")
			line_no += 1
	## fighters the lanes took have ranks and sizes too
	for fid in places.keys():
		var pl: Dictionary = places[fid]
		if not pl.has("line"):
			pl["line"] = 0
			pl["file"] = 0
			pl["width"] = Formation.FILE_PITCH
			pl["depth"] = Formation.LINE_PITCH
		pl["tier"] = int(battle_log.fighters[int(fid)].tier)
	return {"places": places, "last_z": last_z}


## How many of `rows` (lines of a side) stand between z `z0` and `z1` when their depths are scaled by `tight`.
static func _rows_fitting(rows: Array, z0: float, z1: float, tight: float) -> int:
	var z := z0
	var last_depth := 0.0
	for ri in rows.size():
		var depth: float = rows[ri]["depth"]
		var zz := z if ri == 0 else z + (last_depth + depth) * 0.5 * tight
		if zz > z1 + 0.01:
			return ri
		z = zz
		last_depth = depth
	return rows.size()


## The open floors of a fort, in the order a garrison fills them: its yard, then any further patches (the yard's "extra").
static func zones_of(spec: Dictionary) -> Array:
	return [spec["yard"]] + ((spec["yard"] as Dictionary).get("extra", []) as Array)


## A floor patch's lateral middle: where its rows are centred.
static func zone_centre(zone: Dictionary) -> float:
	return (float(zone["x0"]) + float(zone["x1"])) * 0.5 if zone.has("x0") else 0.0


## How many files a floor patch's rows hold: its narrowest row's width over the file pitch.
static func zone_files(zone: Dictionary) -> int:
	var width := 2.0 * float(zone.get("x", 0.0))
	if zone.has("x0"):
		width = float(zone["x1"]) - float(zone["x0"])
	elif zone.has("r"):
		width = 1e9
		var cz := float(zone.get("cz", 0.0))
		for zz in [float(zone["z0"]), float(zone["z1"])]:
			width = minf(width, 2.0 * (sqrt(maxf(0.0, float(zone["r"]) * float(zone["r"]) - (zz - cz) * (zz - cz))) - 0.5))
	return maxi(1, int(floor(width / Formation.FILE_PITCH)))


## One row of a floor patch (or of the ground behind the fort, `floor_` < 0), centred on x = cx at z.
static func _row(places: Dictionary, info: Dictionary, ln: Dictionary, cx: float, z: float, line_no: int, floor_: float, station: String) -> void:
	var w: float = ln["width"]
	var run := -w * 0.5
	var pitches: Array = ln["pitches"]
	var fids: Array = ln["fids"]
	for k in fids.size():
		var pitch: float = pitches[k]
		var off: float = run + pitch * 0.5
		run += pitch
		var pw := to_world(info, cx + off, z)
		places[int(fids[k])] = {"pos": pw, "y": world_y(info, floor_) if floor_ >= 0.0 else NAN, "tier": int(ln["tier"]), "line": line_no, "file": k,
			"width": pitch, "depth": float(ln["depth"]), "station": station}


## Fighters of the lists left, as a set.
static func _pool(lists: Array) -> Dictionary:
	var out := {}
	for l in lists:
		for fid in l:
			out[int(fid)] = true
	return out


## The deck's lanes (and the side walls'): {"from", "dir", "len", "y", "used", "list"}.
static func _lanes(defs: Array) -> Array:
	var out := []
	for d in defs:
		var a := Vector2(float(d[0]), float(d[1]))
		var b := Vector2(float(d[2]), float(d[3]))
		out.append({"from": a, "dir": (b - a).normalized(), "len": a.distance_to(b), "y": float(d[4]), "used": 0.0, "list": []})
	return out


## The gatehouse's roof as one lane, its fighters centred on its middle.
static func _top(def: Array) -> Array:
	if def.size() < 4:
		return []
	var len_ := float(def[2])
	return [{"from": Vector2(float(def[0]) - len_ * 0.5, float(def[1])), "dir": Vector2(1, 0), "len": len_, "y": float(def[3]), "used": 0.0, "list": [], "centre": true}]


## Puts fighters of `lists` (the first list first) along `lanes`, one to each lane in turn; a spot the damage cut hides stays
## empty. The lists lose who is placed; `places` gets them.
static func _fill(battle_log: Dictionary, info: Dictionary, places: Dictionary, lanes: Array, lists: Array, station: String) -> void:
	var progress := not lanes.is_empty()
	while progress:
		progress = false
		for lane in lanes:
			var fid := _peek(lists)
			if fid < 0:
				break
			var pitch := _pitch(String(battle_log.fighters[fid].type))
			while float(lane["used"]) + pitch <= float(lane["len"]) + 0.01:
				var at: Vector2 = (lane["from"] as Vector2) + (lane["dir"] as Vector2) * (float(lane["used"]) + pitch * 0.5)
				lane["used"] = float(lane["used"]) + pitch
				if hidden(info, to_world(info, at.x, at.y), world_y(info, float(lane["y"]))):
					continue
				(lane["list"] as Array).append({"fid": _pop(lists), "at": at, "pitch": pitch})
				progress = true
				break
	for lane in lanes:
		var shift := 0.0
		var items: Array = lane["list"]
		if lane.has("centre") and not items.is_empty():
			var last: Dictionary = items[-1]
			shift = (float(lane["len"]) - ((last["at"] as Vector2).x + float(last["pitch"]) * 0.5 - (lane["from"] as Vector2).x)) * 0.5
		for k in items.size():
			var e: Dictionary = items[k]
			var at2: Vector2 = (e["at"] as Vector2) + Vector2(shift, 0.0)
			places[int(e["fid"])] = {"pos": to_world(info, at2.x, at2.y), "y": world_y(info, float(lane["y"])), "file": k, "width": float(e["pitch"]),
				"station": station}


static func _peek(lists: Array) -> int:
	for l in lists:
		if not (l as Array).is_empty():
			return int((l as Array)[0])
	return -1


static func _pop(lists: Array) -> int:
	for l in lists:
		if not (l as Array).is_empty():
			return int((l as Array).pop_front())
	return -1


static func _pitch(type_id: String) -> float:
	return maxf(Formation.FILE_PITCH, Formation.footprint_of(type_id).x + Formation.ROOM)


static func _depth(ls: Array) -> float:
	var d := 0.0
	var last_tier := -1
	for ln in ls:
		if last_tier >= 0 and int(ln["tier"]) != last_tier:
			d += Formation.TIER_GAP
		d += float(ln["depth"])
		last_tier = int(ln["tier"])
	return d


# --- the march out of the gate ------------------------------------------------------------------------------

## The fighters who arrive at a battle at walls: a sally's march and a relief's arrival. For each fighter of the armies coming
## from inside (siege.from_inside), the path from the column waiting in the yard, through the gate, to its place, and the delay
## before it sets out (the column's head, the front rank, first); in a relief that stands away from the gate (siege.why "relief"
## or "relief_sally", the garrison's side not the one at the gate), for each of its fighters not from inside, the road in from
## behind its line. {fid: {"path": [Vector2], "delay", "dur",
## "s_in", "s_out" (how far along the path the gate's inner and outer points are: 0 for an arrival), "arrives": bool}}.
static func _march(battle_log: Dictionary, info: Dictionary, slots: Array, si: int, siege: Dictionary, pivot: Vector2) -> Dictionary:
	var spec: Dictionary = info["spec"]
	var ids := []
	for fid in battle_log.sides[si].fighters:
		if (siege.get("from_inside", []) as Array).has(String(battle_log.fighters[int(fid)].army)) and slots[int(fid)] != null:
			ids.append(int(fid))
	var gp: Array = spec["gate_path"]
	var gate_out := to_world(info, 0.0, float(gp[1]))
	ids.sort_custom(func(a, b):
		var da: float = (slots[a]["pos"] as Vector2).distance_to(gate_out)
		var db: float = (slots[b]["pos"] as Vector2).distance_to(gate_out)
		return da > db if absf(da - db) > 0.01 else a < b)
	var out := {}
	var z1 := float((spec["yard"] as Dictionary)["z1"])
	for k in ids.size():
		var fid: int = ids[k]
		var col_z := minf(float(gp[0]) + 1.4 * float(k / 2), z1)
		var path := [to_world(info, 1.4 if k % 2 == 0 else -1.4, col_z), to_world(info, 0.0, float(gp[0]) - 1.0),
			to_world(info, 0.0, float(gp[1]) - 1.5), slots[fid]["pos"]]
		out[fid] = {"path": path, "delay": minf(0.04 * float(k), 0.5), "dur": MARCH_TIME, "s_in": path_length(path, 1), "s_out": path_length(path, 2),
			"arrives": false}
	## a relief comes in along the road: from behind its own line, as the gate opens for the sally
	var why := String(siege.get("why", ""))
	var gi := int(siege.get("garrison", -1))
	if (why == "relief" or why == "relief_sally") and gi >= 0 and gi < battle_log.sides.size() and gi != si:
		for fid in battle_log.sides[gi].fighters:
			var f := int(fid)
			if slots[f] == null or out.has(f) or (siege.get("from_inside", []) as Array).has(String(battle_log.fighters[f].army)):
				continue
			var to: Vector2 = slots[f]["pos"]
			var away := (to - pivot).normalized() if to.distance_to(pivot) > 0.01 else Vector2(info["front"])
			out[f] = {"path": [to + away * ARRIVAL_ROAD, to], "delay": minf(0.02 * float(out.size()), 0.4), "dur": MARCH_TIME, "s_in": 0.0, "s_out": 0.0,
				"arrives": true}
	return out


## The length along `path` (Vector2s) to its point `k`.
static func path_length(path: Array, k: int) -> float:
	var total := 0.0
	for j in range(1, mini(k + 1, path.size())):
		total += (path[j] as Vector2).distance_to(path[j - 1])
	return total


# --- the scenery --------------------------------------------------------------------------------------------

## What the besiegers bring, as places: {"ladders": [{"foot": Vector2, "top": Vector3, "yaw", "len", "y"}], "trunk": {} or {"pos",
## "yaw", "y"}, "tents": [{"pos", "yaw", "y"}], "fires": [Vector3], "engines": [{"pos", "yaw", "y"}], "works": [{"pos", "yaw", "y"}],
## "style": the besieging faction, "frame": [Vector3]}. The camp stands at the flanks of the besiegers' lines, never inside a
## wall, never on a fighter.
static func _scenery(battle_log: Dictionary, t, info: Dictionary, kind: String, near: int, besieger: int, depths: Array, wides: Array,
		front_edge: float, trunk: bool, engines: int, rot: float, pivot: Vector2) -> Dictionary:
	var spec: Dictionary = info["spec"]
	var sides: Array = battle_log.sides
	var out := {"ladders": [], "trunk": {}, "tents": [], "fires": [], "engines": [], "works": [], "style": "", "frame": []}
	if besieger < 0 or besieger >= sides.size():
		return out
	out["style"] = String(sides[besieger].faction)
	var outer := float(spec["outer"])
	var face := float(spec["face"])
	var front: Vector2 = info["front"]
	var yaw_in := atan2(front.x, front.y)
	## ladders (the Crown) lean on the gate-side wall; the trunk (the Clans) lies before the gate
	if kind == "storm":
		if trunk:
			var p := to_world(info, 0.0, -(face + 5.0))
			out["trunk"] = {"pos": p, "yaw": yaw_in, "y": maxf(t.height_at(p), 0.0)}
		else:
			var wall_h := float(spec["wall_h"])
			for x in spec["ladder_xs"]:
				var fz := face_z(spec, float(x))
				var len_ := wall_h + 2.5
				var foot := to_world(info, float(x), fz - len_ * 0.34)
				var top := to_world(info, float(x), fz + 0.3)
				out["ladders"].append({"foot": foot, "top": Vector3(top.x, world_y(info, float(spec["floor"]) + wall_h), top.y), "yaw": yaw_in, "len": len_,
					"y": maxf(t.height_at(foot), 0.0)})
	## the camp beside the besiegers' lines: a tent to an army, a fire by each, the engines and the works in front
	var at_gate := kind == "open" and besieger == near
	var w_b := float(wides[besieger])
	var d_b := float(depths[besieger])
	var s_mid := (GATE_MARGIN + d_b * 0.5) if at_gate else (front_edge + d_b * 0.5)
	var n_tents := maxi(1, (sides[besieger].armies as Array).size())
	for k in n_tents:
		var sgn := 1.0 if k % 2 == 0 else -1.0
		var x := sgn * (w_b * 0.5 + CAMP_GAP + 8.0 * float(k / 2))
		var z := -(outer + s_mid + (2.5 if (k / 2) % 2 == 1 else 0.0))
		var pw := pivot + (to_world(info, x, z) - pivot).rotated(rot)
		out["tents"].append({"pos": pw, "yaw": yaw_in + rot, "y": maxf(t.height_at(pw), 0.0)})
		var fp := pivot + (to_world(info, x - sgn * 3.8, z + 1.5) - pivot).rotated(rot)
		out["fires"].append(Vector3(fp.x, maxf(t.height_at(fp), 0.0), fp.y))
	var shown := mini(engines, MAX_ENGINES)
	var s_front := (GATE_MARGIN + d_b - 3.0) if at_gate else (front_edge + 2.0)
	for k in shown:
		var sgn2 := 1.0 if k % 2 == 0 else -1.0
		var pe := pivot + (to_world(info, sgn2 * (w_b * 0.5 + 6.0 + 7.5 * float(k / 2)), -(outer + s_front)) - pivot).rotated(rot)
		out["engines"].append({"pos": pe, "yaw": yaw_in + rot, "y": maxf(t.height_at(pe), 0.0)})
	if shown > 0:
		var pwk := pivot + (to_world(info, -(w_b * 0.5 + 6.0 + 7.5 * float((shown + 1) / 2) + 5.0), -(outer + s_front + 2.0)) - pivot).rotated(rot)
		out["works"].append({"pos": pwk, "yaw": yaw_in + rot, "y": maxf(t.height_at(pwk), 0.0)})
	for piece in [["tents", 7.0, 6.5], ["engines", 6.0, 5.0], ["works", 5.0, 6.0]]:
		for e in out[piece[0]]:
			var ep: Vector2 = e["pos"]
			var r := float(piece[2])
			for off in [Vector2(r, r), Vector2(-r, r), Vector2(r, -r), Vector2(-r, -r)]:
				out["frame"].append(Vector3(ep.x + off.x, float(e["y"]), ep.y + off.y))
			out["frame"].append(Vector3(ep.x, float(e["y"]) + float(piece[1]), ep.y))
	return out


## The z of the gate side's outer face at lateral `x`: straight for a wall, round for a ring of stakes.
static func face_z(spec: Dictionary, x: float) -> float:
	var face := float(spec["face"])
	if not (spec["solids"] as Array).is_empty() and (spec["solids"][0] as Dictionary).has("ring"):
		return -sqrt(maxf(face * face - x * x, 0.0))
	return -face


## The ground the battle needs clear: the fort and every line and tent, as the oriented rectangle round them.
static func _footprint(info: Dictionary, kind: String, depths: Array, wides: Array, front_edge: float, near: int, far: int, pivot: Vector2,
		rot: float) -> PackedVector2Array:
	var outer := float((info["spec"] as Dictionary)["outer"])
	var reach := front_edge + float(depths[far]) + Formation.CLEAR_MARGIN + 6.0
	if kind == "open":
		reach = front_edge + float(depths[far]) + Formation.CLEAR_MARGIN + 6.0
	var half_w := maxf(float(wides[near]), float(wides[far])) * 0.5 + CAMP_GAP + 16.0 + Formation.CLEAR_MARGIN
	var back_z := float(info["radius"]) + Formation.CLEAR_MARGIN
	var out := PackedVector2Array()
	for p in [Vector2(-half_w, back_z), Vector2(half_w, back_z), Vector2(half_w, -(outer + reach)), Vector2(-half_w, -(outer + reach))]:
		var pw := to_world(info, p.x, p.y)
		if p.y < -outer:
			pw = pivot + (pw - pivot).rotated(rot)
		out.append(pw)
	return out
