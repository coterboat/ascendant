## The 3D battle stage's ground plan, the pure part (no nodes): where on the land a battle stands and where
## every fighter of its log stands in it (M3b; design/3D_DIRECTION.md 7.2, design/M3_BATTLES.md 3.2).
## It reads only the battle log, the baked land (terrain3d.gd) and, optionally, where the world put its
## fortresses and forts; it never touches the game or draws a random number, so the same log on the same
## land always stands the same way (tests).
##
##   var plan := BattleFormation.plan(log, terrain, world, aspect)
##
## Where the battle stands (geography decides facing, not M3's left and right):
##   * a province battle with a defender: the defender holds the province's stage, facing the border its
##     enemy crossed; the attacker forms up toward that border's road. Which border: the first step of the
##     shortest road from the province to the attacker's capital (the log keeps no route, and this is where
##     an army of that side most likely came from).
##   * at a fortress (a capital): the defender's ranks form before their own gate, the walls behind them.
##   * a fort battle: the fort stands behind the defender's back line (the world's fort, or, when the log
##     has a fort the world doesn't draw there, one the stage puts up behind the defender).
##   * nobody defending (both arrived): each side takes the end nearer its own home.
##   * a border battle: on the crossing of the two provinces, each side on the side of its own home.
##   The orientation turns (up to 60 degrees either way) until no fighter stands in the sea.
##
## The formation (M3 3.2, read for 3D): each side's fighters stand in lines facing the enemy, front rank
## (tier 0) nearest the centre, then the second rank (tier 1), then the back line (tier 2, commanders);
## within a rank grouped by unit type in faction roster order, then log order, a new line for each type so
## blocks read as blocks. A ruler stands in the middle of its rank's front line; a commander in the middle
## of the back line, with the side's standard bearer and musician beside it (cosmetic: they never count).
## Every fighter is its own figure, 1:1. Each type takes the room its model needs (wide and long figures
## like knights and war bears get wider files and deeper lines). The number of files is the one that
## lets the camera frame the whole battle biggest in a band of the given aspect (width / height).
##
## Returns {"site": Vector2, "axis": Vector2 (unit: from the near side toward the far side), "near": side
## index standing on the -axis half, "far", "where": "stage" | "gate" | "fort" | "border", "files": int,
## "slots": [by fighter id: {"pos": Vector2, "y", "yaw", "side", "tier", "line", "file", "width", "depth"}],
## "extras": [{"type": "bearer" | "musician", "side", "pos", "y", "yaw"}], "back": [by side: Vector2 the
## point its routed fighters run to], "footprint": PackedVector2Array (the corners of the ground the
## battle needs clear), "fort": {} or {"pos": Vector2, "yaw", "faction", "world": bool (the world's own
## fort)}, "depths": [by side: its formation's depth], "width": the widest line}.
extends RefCounted

const Models := preload("res://world3d/models.gd")
const Kit := preload("res://world3d/kit.gd")

const FILE_PITCH := 4.6 ## between files across a line (world units; a man is Kit.FIG = 6)
const LINE_PITCH := 5.0 ## between the lines of a block, for man-sized figures
const ROOM := 1.4 ## room around a model's own footprint
const TIER_GAP := 2.4 ## extra between two ranks
const FRONT_GAP := 12.0 ## between the two front lines' edges
const GATE_MARGIN := 4.0 ## the defender's back line stands this far out of the gate
const ROUT_RUN := 34.0 ## routed fighters run this far past their back line before they are gone
const CLEAR_MARGIN := 9.0 ## the ground cleared round the battle
const PITCH := 40.0 ## the camera pitch the file count is chosen for
const MAX_FILES := 36
const FORT_R := 13.0 ## a fort's half-size when its row gives none


## The ground plan of `battle_log` on the land `t`. `world` (optional): {"fortresses": {province id:
## {"gate_outer": Vector2, "gate_dir": Vector2, "half": float}}, "forts": {province id: [Vector2, radius]}}.
## `aspect`: the band's width over its height.
static func plan(battle_log: Dictionary, t, world: Dictionary = {}, aspect: float = 2.6) -> Dictionary:
	var sides: Array = battle_log.get("sides", [])
	var nsides := sides.size()
	var lines := [] ## by side: the lines of that side (front first)
	var files := _pick_files(battle_log, aspect)
	for si in nsides:
		lines.append(side_lines(battle_log, si, files))
	var depths := []
	var widest := 0.0
	for si in nsides:
		depths.append(_depth(lines[si]))
		for ln in lines[si]:
			widest = maxf(widest, float(ln["width"]))
	var geo := _site(battle_log, t, world, depths)
	var site: Vector2 = geo["site"]
	var axis: Vector2 = geo["axis"]
	var near: int = geo["near"]
	var far: int = 1 - near if nsides > 1 else near
	## turn until no one stands in the sea (and never into a fortress)
	var best := {}
	var best_wet := 1 << 30
	var turns := [0.0] if String(geo["where"]) == "gate" else [0.0, 10.0, -10.0, 20.0, -20.0, 30.0, -30.0, 45.0, -45.0, 60.0, -60.0]
	for deg in turns:
		var ax: Vector2 = axis.rotated(deg_to_rad(deg))
		var st: Vector2 = site
		if String(geo["where"]) == "fort" and geo.has("pivot"):
			var pv: Vector2 = geo["pivot"]
			st = pv + (site - pv).rotated(deg_to_rad(deg))
		var placed := _place(battle_log, t, lines, depths, st, ax, near, far)
		var wet := _wet(t, placed, world, battle_log)
		if wet < best_wet:
			best_wet = wet
			best = placed
			best["axis"] = ax
			best["site"] = st
			if wet == 0:
				break
	var out := best
	out["near"] = near
	out["far"] = far
	out["where"] = geo["where"]
	out["files"] = files
	out["depths"] = depths
	out["width"] = widest
	out["fort"] = {}
	if geo.has("fort"):
		var fd: Dictionary = (geo["fort"] as Dictionary).duplicate()
		if not bool(fd.get("world", false)):
			## the stage's own fort stands behind the near side's back line, gate toward the battle
			var ax2: Vector2 = out["axis"]
			var r: float = fort_radius(String(fd.get("faction", "")))
			fd["pos"] = (out["site"] as Vector2) - ax2 * (FRONT_GAP * 0.5 + float(depths[near]) + 3.0 + r)
			fd["yaw"] = atan2(-ax2.x, -ax2.y)
		out["fort"] = fd
	out["footprint"] = _footprint(out["site"], out["axis"], depths, near, far, widest, nsides)
	return out


## The lines of side `si` with `files` files: [{"fids": [ids in file order], "pitches": [each one's room
## across], "width", "depth", "tier"}], front line first.
static func side_lines(battle_log: Dictionary, si: int, files: int) -> Array:
	var out := []
	var tiers := ordered_tiers(battle_log, si)
	for tier in 3:
		var ids: Array = tiers[tier]
		if ids.is_empty():
			continue
		## the tier's fighters in type order, packed into lines of `files` files (a wide or long figure takes
		## its own room); a type continues on the next line, so blocks of one type stand together
		var ruler := -1
		var order := []
		for fid in ids:
			if battle_log.fighters[int(fid)].role == "ruler":
				ruler = int(fid)
			else:
				order.append(int(fid))
		var tier_lines := []
		var cap := files * FILE_PITCH + 0.01
		var cur := {}
		for fid in order:
			var fp := footprint_of(String(battle_log.fighters[fid].type))
			var pitch: float = maxf(FILE_PITCH, fp.x + ROOM)
			var depth: float = maxf(LINE_PITCH, fp.y + ROOM)
			if cur.is_empty() or float(cur["used"]) + pitch > cap:
				cur = {"fids": [], "pitches": [], "used": 0.0, "depth": 0.0, "tier": tier}
				tier_lines.append(cur)
			cur["fids"].append(fid)
			cur["pitches"].append(pitch)
			cur["used"] = float(cur["used"]) + pitch
			cur["depth"] = maxf(float(cur["depth"]), depth)
		if ruler >= 0:
			var rfp := footprint_of(String(battle_log.fighters[ruler].type))
			var rp: float = maxf(FILE_PITCH, rfp.x + ROOM)
			if tier_lines.is_empty():
				tier_lines.append({"fids": [], "pitches": [], "used": 0.0, "depth": 0.0, "tier": tier})
			var first: Dictionary = tier_lines[0]
			var at: int = (first["fids"] as Array).size() / 2
			first["fids"].insert(at, ruler)
			first["pitches"].insert(at, rp)
			first["used"] = float(first["used"]) + rp
			first["depth"] = maxf(float(first["depth"]), maxf(LINE_PITCH, rfp.y + ROOM))
		for ln in tier_lines:
			ln["width"] = float(ln["used"])
			out.append(ln)
	return out


## Side `si`'s fighters by tier ([[tier 0], [tier 1], [tier 2]]), each tier grouped by unit type in
## faction roster order, then log order (rulers last; side_lines moves them to the middle of the front).
static func ordered_tiers(battle_log: Dictionary, si: int) -> Array:
	var side: Dictionary = battle_log.sides[si]
	var roster := _roster(String(side.faction))
	var out := [[], [], []]
	for fid in side.fighters:
		var f: Dictionary = battle_log.fighters[int(fid)]
		out[clampi(int(f.tier), 0, 2)].append(int(fid))
	for tl in out:
		tl.sort_custom(func(a, b):
			var ra := _rank_in(roster, battle_log.fighters[a])
			var rb := _rank_in(roster, battle_log.fighters[b])
			return ra < rb if ra != rb else a < b)
	return out


## A type's footprint on the ground: Vector2(width across, length along its facing), world units, from
## its ready model (feet at the origin, facing -Z).
static func footprint_of(type_id: String) -> Vector2:
	var fm: Dictionary = Models.figure_mesh(type_id, true, "ready")
	var m: Mesh = fm.get("mesh")
	if m == null:
		return Vector2(3.0, 3.0)
	var a: AABB = m.get_aabb()
	return Vector2(a.size.x, a.size.z)


## A type's standing height, world units (its ready model's).
static func height_of(type_id: String, faction: String = "") -> float:
	var fm: Dictionary = Models.figure_mesh(type_id, true, "ready", faction)
	var m: Mesh = fm.get("mesh")
	return m.get_aabb().end.y if m != null else Kit.FIG


## The half-size of a faction's fort (its row's side, or the primitive's).
static func fort_radius(faction: String) -> float:
	var row: Dictionary = Models.building_row("fort", faction)
	if String(row.get("model", "")).is_empty():
		return FORT_R
	return float(row.get("side", 26.0)) * 0.5


## The first step of the shortest road from province `pid` to faction `faction`'s capital, as a unit
## vector from the province's centre toward that border's crossing (ZERO at the capital or with no road).
static func home_dir(t, pid: String, faction: String) -> Vector2:
	var i: int = t.index_of(pid)
	var cap := ""
	for f in FactionData.FACTIONS:
		if String(f.id) == faction:
			cap = String(f.capital)
	var goal: int = t.index_of(cap)
	if i < 0 or goal < 0 or goal == i:
		return Vector2.ZERO
	## breadth first from the capital, so each province knows its distance home
	var dist := {goal: 0}
	var queue := [goal]
	while not queue.is_empty():
		var k: int = queue.pop_front()
		for j in t.neighbours[k]:
			if not dist.has(j):
				dist[j] = int(dist[k]) + 1
				queue.append(j)
	if not dist.has(i):
		return Vector2.ZERO
	var best := -1
	for j in t.neighbours[i]:
		if dist.has(j) and int(dist[j]) == int(dist[i]) - 1 and (best < 0 or j < best):
			best = j
	if best < 0:
		return Vector2.ZERO
	var c: Vector2 = t.centres[i]
	var x: Variant = t.crossing(pid, t.ids[best])
	var to: Vector2 = (x as Vector2) if x != null else t.centres[best]
	return (to - c).normalized()


## How many roads it is from province `pid` to faction `faction`'s capital (1 << 20 when there is none).
static func roads_home(t, pid: String, faction: String) -> int:
	var cap := ""
	for f in FactionData.FACTIONS:
		if String(f.id) == faction:
			cap = String(f.capital)
	var goal: int = t.index_of(cap)
	var i: int = t.index_of(pid)
	if goal < 0 or i < 0:
		return 1 << 20
	var dist := {goal: 0}
	var queue := [goal]
	while not queue.is_empty():
		var k: int = queue.pop_front()
		if k == i:
			return int(dist[k])
		for j in t.neighbours[k]:
			if not dist.has(j):
				dist[j] = int(dist[k]) + 1
				queue.append(j)
	return 1 << 20


# --- internals ----------------------------------------------------------------------------------------

## The file count that frames the whole battle biggest: the smallest needed screen height, the battle's
## depth across the band's width or its width up the band's height (seen from the flank at PITCH).
static func _pick_files(battle_log: Dictionary, aspect: float) -> int:
	var sides: Array = battle_log.get("sides", [])
	var most := 1
	for si in sides.size():
		most = maxi(most, (sides[si].fighters as Array).size())
	## lines, not queues: at least about the square root of twice a side's size (a side of 4 stands 3
	## abreast, the biggest 17)
	var least := mini(most, maxi(1, int(ceil(sqrt(2.0 * most)))))
	var best := least
	var best_need := INF
	var sp := sin(deg_to_rad(PITCH))
	var cp := cos(deg_to_rad(PITCH))
	for w in range(least, maxi(least, mini(MAX_FILES, most)) + 1):
		var deep := FRONT_GAP
		var wide := 0.0
		for si in sides.size():
			var ls := side_lines(battle_log, si, w)
			deep += _depth(ls)
			for ln in ls:
				wide = maxf(wide, float(ln["width"]))
		var need := maxf(deep / maxf(aspect, 0.1), wide * sp + Kit.FIG * 1.6 * cp)
		if need < best_need - 0.01:
			best_need = need
			best = w
	return best


static func _depth(ls: Array) -> float:
	var d := 0.0
	var last_tier := -1
	for ln in ls:
		if last_tier >= 0 and int(ln["tier"]) != last_tier:
			d += TIER_GAP
		d += float(ln["depth"])
		last_tier = int(ln["tier"])
	return d


## Where the battle stands and which way it faces, before the sea check.
static func _site(battle_log: Dictionary, t, world: Dictionary, depths: Array) -> Dictionary:
	var sides: Array = battle_log.get("sides", [])
	var pids: Array = battle_log.get("provinces", [])
	var pid := String(pids[0]) if not pids.is_empty() else ""
	var i: int = t.index_of(pid) if pid != "" else -1
	var defender := String(battle_log.get("defender", ""))
	var dsi := -1
	for s in sides:
		if s.get("defender", false):
			dsi = int(s.index)
	if dsi < 0 and defender != "":
		for s in sides:
			if String(s.faction) == defender:
				dsi = int(s.index)
	var out := {}
	if String(battle_log.get("kind", "province")) == "border" and pids.size() >= 2 and t.index_of(String(pids[1])) >= 0 and i >= 0:
		var a := String(pids[0])
		var b := String(pids[1])
		var ca: Vector2 = t.centre_of(a)
		var cb: Vector2 = t.centre_of(b)
		var x: Variant = t.crossing(a, b)
		var site: Vector2 = (x as Vector2) if x != null else (ca + cb) * 0.5
		var axis: Vector2 = (cb - ca).normalized()
		## the side whose home is nearer province a stands on a's half
		var near := 0
		if sides.size() > 1:
			var d0 := roads_home(t, a, String(sides[0].faction)) - roads_home(t, b, String(sides[0].faction))
			var d1 := roads_home(t, a, String(sides[1].faction)) - roads_home(t, b, String(sides[1].faction))
			near = 1 if d1 < d0 else 0
		out = {"site": site, "axis": axis, "near": near, "where": "border"}
		out["site"] = _centred(out["site"], axis, depths, near)
		return out
	if i < 0:
		return {"site": Vector2(500, 300), "axis": Vector2(1, 0), "near": 0, "where": "stage"}
	var c: Vector2 = t.centres[i]
	var fortresses: Dictionary = world.get("fortresses", {})
	var forts: Dictionary = world.get("forts", {})
	if dsi >= 0 and sides.size() > 1:
		var asi := 1 - dsi
		var a_dir := home_dir(t, pid, String(sides[asi].faction))
		if a_dir == Vector2.ZERO:
			a_dir = -home_dir(t, pid, String(sides[dsi].faction))
		if a_dir == Vector2.ZERO:
			a_dir = _gate_dir(t, pid)
		if fortresses.has(pid):
			var fz: Dictionary = fortresses[pid]
			var gdir: Vector2 = fz["gate_dir"]
			var gout: Vector2 = fz["gate_outer"]
			var site: Vector2 = gout + gdir * (GATE_MARGIN + float(depths[dsi]) + FRONT_GAP * 0.5)
			return {"site": site, "axis": gdir, "near": dsi, "where": "gate"}
		if battle_log.get("fort", false):
			var fac := String(sides[dsi].faction)
			if forts.has(pid):
				var fs: Array = forts[pid]
				var fpos: Vector2 = fs[0]
				var fr: float = float(fs[1])
				var toward: Vector2 = c + a_dir * float(t.stage_r[i]) - fpos
				var axis: Vector2 = toward.normalized() if toward.length() > 0.01 else a_dir
				var site: Vector2 = fpos + axis * (fr + 3.0 + float(depths[dsi]) + FRONT_GAP * 0.5)
				return {"site": site, "axis": axis, "near": dsi, "where": "fort", "pivot": fpos,
					"fort": {"pos": fpos, "yaw": atan2(-axis.x, -axis.y), "faction": fac, "world": true}}
			## a fort the world doesn't draw here (a test battle): the stage puts one behind the defender
			var r := fort_radius(fac)
			var back: Vector2 = c - a_dir * float(t.stage_r[i]) * 0.5
			var site2: Vector2 = back + a_dir * (r + 3.0 + float(depths[dsi]) + FRONT_GAP * 0.5)
			return {"site": site2, "axis": a_dir, "near": dsi, "where": "fort", "pivot": back,
				"fort": {"faction": fac, "world": false}}
		return {"site": c, "axis": a_dir, "near": dsi, "where": "stage"}
	## nobody defends: each side takes the end nearer its home
	var h0 := home_dir(t, pid, String(sides[0].faction)) if sides.size() > 0 else Vector2.ZERO
	var h1 := home_dir(t, pid, String(sides[1].faction)) if sides.size() > 1 else Vector2.ZERO
	var axis2 := h1 - h0
	if axis2.length() < 0.2:
		axis2 = -h0 if h0 != Vector2.ZERO else (h1 if h1 != Vector2.ZERO else _gate_dir(t, pid))
	axis2 = axis2.normalized()
	if fortresses.has(pid):
		var fz2: Dictionary = fortresses[pid]
		var gdir2: Vector2 = fz2["gate_dir"]
		var gout2: Vector2 = fz2["gate_outer"]
		## both stand outside the gate, along it; side 0 nearer the gate unless its home is the far way
		var near2 := 0 if axis2.dot(gdir2) >= 0.0 else 1
		var dn := float(depths[near2]) if near2 < depths.size() else 0.0
		return {"site": gout2 + gdir2 * (GATE_MARGIN + dn + FRONT_GAP * 0.5), "axis": gdir2, "near": near2, "where": "gate"}
	return {"site": c, "axis": axis2, "near": 0, "where": "stage"}


static func _gate_dir(t, pid: String) -> Vector2:
	var i: int = t.index_of(pid)
	if i < 0:
		return Vector2(1, 0)
	var c: Vector2 = t.centres[i]
	var sum := Vector2.ZERO
	for j in t.neighbours[i]:
		var x: Variant = t.crossing(pid, t.ids[j])
		var to: Vector2 = (x as Vector2) if x != null else t.centres[j]
		sum += (to - c).normalized()
	return sum.normalized() if sum.length() > 0.01 else Vector2(1, 0)


## Shifts a border site so the battle's middle (between the front lines) sits on it.
static func _centred(site: Vector2, _axis: Vector2, _depths: Array, _near: int) -> Vector2:
	return site


## Every fighter's place for the battle standing at `site`, facing along `axis`.
static func _place(battle_log: Dictionary, t, lines: Array, depths: Array, site: Vector2, axis: Vector2, near: int, far: int) -> Dictionary:
	var slots := []
	slots.resize((battle_log.get("fighters", []) as Array).size())
	var extras := []
	var back := []
	var lat := Vector2(-axis.y, axis.x)
	var sides: Array = battle_log.get("sides", [])
	back.resize(sides.size())
	for si in sides.size():
		var dir := -1.0 if si == near else 1.0 ## which half: the near side stands at -axis
		if sides.size() == 1:
			dir = -1.0
		var facing: Vector2 = -axis * dir
		var yaw := atan2(-facing.x, -facing.y)
		var d := FRONT_GAP * 0.5
		var last_tier := -1
		var line_no := 0
		var commander_at := Vector2.INF
		var back_d := d
		for ln in lines[si]:
			if last_tier >= 0 and int(ln["tier"]) != last_tier:
				d += TIER_GAP
			last_tier = int(ln["tier"])
			var depth: float = ln["depth"]
			var centre_d: float = d + depth * 0.5
			var fids: Array = ln["fids"]
			var pitches: Array = ln["pitches"]
			var w: float = ln["width"]
			var run := -w * 0.5
			for k in fids.size():
				var pitch: float = pitches[k]
				var off: float = run + pitch * 0.5
				run += pitch
				var p: Vector2 = site + axis * (dir * centre_d) + lat * off
				var fid := int(fids[k])
				slots[fid] = {"pos": p, "y": maxf(t.height_at(p), 0.0), "yaw": yaw, "side": si, "tier": int(ln["tier"]), "line": line_no,
					"file": k, "width": pitch, "depth": depth}
				if battle_log.fighters[fid].role == "commander" and commander_at == Vector2.INF:
					commander_at = p
			d += depth
			back_d = d
			line_no += 1
		## the colour party: the standard bearer and the musician beside the commander, or behind the lines
		var party_d := back_d + LINE_PITCH * 0.5
		var base: Vector2 = commander_at if commander_at != Vector2.INF else site + axis * (dir * party_d)
		var spread := FILE_PITCH * 1.4 if commander_at != Vector2.INF else FILE_PITCH * 0.7
		for k in 2:
			var p2: Vector2 = base + lat * (spread * (1.0 if k == 0 else -1.0) * dir)
			extras.append({"type": "bearer" if k == 0 else "musician", "side": si, "pos": p2, "y": maxf(t.height_at(p2), 0.0), "yaw": yaw})
		back[si] = site + axis * (dir * (back_d + ROUT_RUN))
	return {"slots": slots, "extras": extras, "back": back}


## How many fighters of a placement stand in the sea, inside a fortress or off the land (fewer is better).
static func _wet(t, placed: Dictionary, world: Dictionary, battle_log: Dictionary) -> int:
	var n := 0
	var fortresses: Dictionary = world.get("fortresses", {})
	for s in placed["slots"]:
		if s == null:
			continue
		var p: Vector2 = s["pos"]
		if t.coast_at(p) < 2.5 or t.province_at(p) == "":
			n += 1
			continue
		for pid in fortresses.keys():
			var c: Vector2 = t.centre_of(pid)
			if p.distance_to(c) < float((fortresses[pid] as Dictionary).get("half", 38.0)):
				n += 1
				break
	return n


static func _footprint(site: Vector2, axis: Vector2, depths: Array, near: int, far: int, widest: float, nsides: int) -> PackedVector2Array:
	var lat := Vector2(-axis.y, axis.x)
	var dn: float = float(depths[near]) if near < depths.size() else 0.0
	var df: float = float(depths[far]) if far < depths.size() and nsides > 1 else 0.0
	var a0 := -(FRONT_GAP * 0.5 + dn + CLEAR_MARGIN + 6.0)
	var a1 := FRONT_GAP * 0.5 + df + CLEAR_MARGIN + 6.0
	var h := widest * 0.5 + CLEAR_MARGIN
	return PackedVector2Array([site + axis * a0 - lat * h, site + axis * a1 - lat * h, site + axis * a1 + lat * h, site + axis * a0 + lat * h])


static func _roster(faction_id: String) -> Array:
	for f in FactionData.FACTIONS:
		if f.id == faction_id:
			var ids := []
			for u in f.unit_types:
				ids.append(String(u.id))
			ids.append(String(f.commander.id))
			return ids
	return []


static func _rank_in(roster: Array, f: Dictionary) -> int:
	if f.role == "ruler":
		return 1000
	var k := roster.find(String(f.type))
	return k if k >= 0 else 500


## Whether `p` is inside the convex polygon `poly` (the footprint), grown by `pad`.
static func inside(poly: PackedVector2Array, p: Vector2, pad: float = 0.0) -> bool:
	var n := poly.size()
	if n < 3:
		return false
	for k in n:
		var a: Vector2 = poly[k]
		var b: Vector2 = poly[(k + 1) % n]
		var e := b - a
		var nrm := Vector2(e.y, -e.x).normalized()
		## outward normal for a counter-clockwise or clockwise polygon: test against the centroid's side
		var cen := Vector2.ZERO
		for q in poly:
			cen += q
		cen /= float(n)
		if nrm.dot(cen - a) > 0.0:
			nrm = -nrm
		if nrm.dot(p - a) > pad:
			return false
	return true
