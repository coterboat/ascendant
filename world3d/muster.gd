## The muster yards and war camps (design/3D_DIRECTION.md 6.3), the pure part (no nodes): where every
## block of every army stands in a fortress's yard, which armies overflow into the war camp outside the
## walls, and where queued recruits stand as ghosts. Deterministic: the same armies always stand in the
## same slots, whatever order they come in.
##
## The yard is a fixed grid of block slots (a capital holds 6, as 3 across and 2 deep, or what its
## courtyard fits). A slot holds one block: up to 8 figures of one unit type at drill spacing (fewer of
## a large type; a block too big for one slot takes the next slots), or an army's colour party (its
## ruler or commander and its banner bearer). Armies take their slots in id order, each one whole: the
## first that doesn't fit, and every later one that doesn't, musters in the war camp instead, a grid
## of slots beside the road outside the gate with a tent behind every block. A big muster visibly
## outgrows its fortress: that is the signal of a coming war.
##
## Frames: the yard's frame has its origin at the middle of the slot grid's front edge (the gate side),
## x across, z growing away from the gate; every figure faces the gate (-z). The camp's frame has its
## origin at the camp's wall-side corner nearest the road, x along the wall away from the road, z
## growing away from the wall (its armies face outward, -z... see camp_layout); armies.gd turns both
## into the world.
##
## A description ("desc") is armies.gd's: {"id", "owner", "location", "blocks": [{"type", "n" figures,
## "rank", "sp" spacing}], "leaders": [{"type", "role", "rank", "sp"}]}.
extends RefCounted

const SLOT := Vector2(12.8, 6.8) ## a block slot: 4 figures across and 2 deep at drill spacing
const GAP := Vector2(1.4, 1.2) ## between slots
const DRILL := Vector2(3.2, 3.4) ## the closest a human-sized figure stands to the next in a yard
const DRILL_K := 0.76 ## yard spacing as a share of the field formation's
const YARD_SLOTS := 6 ## a capital's yard holds 6 blocks (design 6.3)
const CAMP_COLS := 3 ## camp slots along the wall before a new row starts further out
const TENT_D := 6.0 ## the depth a camp slot keeps behind its block for the tent
const PARTY := "party" ## the colour party's slot kind


## The yard's slot grid for a courtyard `w` x `d` (world units): Vector2i(cols, rows), at most `cap`
## slots (fewer rows first). Always at least one slot.
static func grid(w: float, d: float, cap: int = YARD_SLOTS) -> Vector2i:
	var cols := maxi(1, int(floor((w + GAP.x) / (SLOT.x + GAP.x) + 0.001)))
	var rows := maxi(1, int(floor((d + GAP.y) / (SLOT.y + GAP.y) + 0.001)))
	while cols * rows > cap and rows > 1:
		rows -= 1
	while cols * rows > cap and cols > 1:
		cols -= 1
	return Vector2i(cols, rows)


## The slot grid's own size (world units): what grid() needs of a courtyard.
static func grid_size(g: Vector2i) -> Vector2:
	return Vector2(g.x * SLOT.x + (g.x - 1) * GAP.x, g.y * SLOT.y + (g.y - 1) * GAP.y)


## The yard spacing of a figure whose field spacing is `sp`.
static func drill(sp: Vector2) -> Vector2:
	return Vector2(maxf(DRILL.x, sp.x * DRILL_K), maxf(DRILL.y, sp.y * DRILL_K))


## How many figures of field spacing `sp` one slot holds: Vector2i(across, deep).
static func slot_fit(sp: Vector2) -> Vector2i:
	var dr := drill(sp)
	return Vector2i(maxi(1, int(floor(SLOT.x / dr.x + 0.001))), maxi(1, int(floor(SLOT.y / dr.y + 0.001))))


## The slots an army needs: [{"kind": "party" or "block", "type", "n", "sp", "leaders"}], the colour
## party first (every army carries a banner), then its blocks in battle-rank order, a big block split
## over as many slots as it fills.
static func army_slots(d: Dictionary) -> Array:
	var out: Array = []
	var party: Array = []
	for ld in d.get("leaders", []):
		party.append({"type": ld["type"], "role": ld["role"], "sp": ld["sp"]})
	party.append({"type": "bearer", "role": "bearer", "sp": Vector2(4.0, 4.0)})
	out.append({"kind": PARTY, "leaders": party})
	for bl in d.get("blocks", []):
		var fit := slot_fit(bl["sp"])
		var cap: int = fit.x * fit.y
		var left: int = int(bl["n"])
		while left > 0:
			var take: int = mini(left, cap)
			out.append({"kind": "block", "type": bl["type"], "n": take, "sp": bl["sp"]})
			left -= take
	return out


## The centre of slot `i` of a `g` grid, in the yard's frame (row 0 at the gate).
static func slot_centre(g: Vector2i, i: int) -> Vector2:
	var c: int = i % g.x
	var r: int = i / g.x
	return Vector2((c - (g.x - 1) * 0.5) * (SLOT.x + GAP.x), r * (SLOT.y + GAP.y) + SLOT.y * 0.5)


## The order the places across a slot's row fill in: the middle first, so a small block stands centred
## and a queued recruit always takes the next place without moving anyone.
static func fill_order(across: int) -> Array:
	var out: Array = []
	var mid: float = (across - 1) * 0.5
	var idx: Array = range(across)
	idx.sort_custom(func(a, b): return absf(a - mid) < absf(b - mid) or (absf(a - mid) == absf(b - mid) and a < b))
	for i in idx:
		out.append(i)
	return out


## Place `k` (0-based) of a block of figures with field spacing `sp` in a slot centred at `centre`:
## the front row first (nearest the gate), each row from the middle out. Places past the slot's
## capacity go on in rows behind it.
static func place_in_slot(centre: Vector2, sp: Vector2, k: int) -> Vector2:
	var fit := slot_fit(sp)
	var dr := drill(sp)
	var order := fill_order(fit.x)
	var col: int = order[k % fit.x]
	var row: int = k / fit.x
	var rows_shown: int = fit.y
	var x: float = (col - (fit.x - 1) * 0.5) * dr.x
	var z: float = (row - (rows_shown - 1) * 0.5) * dr.y
	return centre + Vector2(x, z)


## The colour party's places in its slot: the leaders across the front, the banner bearer at their right.
static func party_places(centre: Vector2, party: Array) -> Array:
	var out: Array = []
	var n: int = party.size()
	var w := 0.0
	for it in party:
		w += maxf(3.6, (it["sp"] as Vector2).x * 0.8)
	var x: float = -w * 0.5
	for it in party:
		var step: float = maxf(3.6, (it["sp"] as Vector2).x * 0.8)
		out.append({"type": it["type"], "role": it["role"], "pos": centre + Vector2(x + step * 0.5, 0.0)})
		x += step
	return out if n > 0 else []


## The figures of one army's slots at the given slot centres: [{"type", "role", "pos"}], in the same
## order armies.gd builds its figures (party first, then each block's figures).
static func figures_at(slots: Array, centres: Array) -> Array:
	var out: Array = []
	for i in slots.size():
		var sl: Dictionary = slots[i]
		var c: Vector2 = centres[i]
		if sl["kind"] == PARTY:
			out.append_array(party_places(c, sl["leaders"]))
		else:
			for k in int(sl["n"]):
				out.append({"type": sl["type"], "role": "unit", "pos": place_in_slot(c, sl["sp"], k)})
	return out


## The muster of one fortress: `descs` are the armies standing there (any order), `g` its yard grid.
## Only `owner`'s armies may use the yard (an enemy army there stands in the camp). Returns
## {"yard": {army id: [figure places in the yard's frame]}, "camp": {army id: [figure places in the
## camp's frame]}, "slots": {army id: [slot indices]} (yard slots), "used": [bool per yard slot],
## "camp_used": camp slots used, "tents": [camp-frame points, one per camp slot], "fires": [camp-frame
## points, one per army in the camp], "camp_slots": {army id: [camp slot indices]}}.
static func layout(descs: Array, g: Vector2i, owner: String = "") -> Dictionary:
	var sorted: Array = descs.duplicate()
	sorted.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	var total: int = g.x * g.y
	var used: Array = []
	used.resize(total)
	used.fill(false)
	var out := {"yard": {}, "camp": {}, "slots": {}, "used": used, "camp_used": 0, "tents": [], "fires": [],
		"camp_slots": {}, "grid": g}
	var camp_list: Array = []
	for d in sorted:
		var need: Array = army_slots(d)
		var free: Array = []
		if owner.is_empty() or String(d.get("owner", "")) == owner:
			for i in total:
				if not used[i]:
					free.append(i)
		if free.size() >= need.size():
			var mine: Array = free.slice(0, need.size())
			var centres: Array = []
			for i in mine:
				used[i] = true
				centres.append(slot_centre(g, i))
			out["yard"][d["id"]] = figures_at(need, centres)
			out["slots"][d["id"]] = mine
		else:
			camp_list.append(d)
	var k := 0
	for d in camp_list:
		var need2: Array = army_slots(d)
		var centres2: Array = []
		var idxs: Array = []
		for j in need2.size():
			centres2.append(camp_block_centre(k))
			out["tents"].append(camp_tent_point(k))
			idxs.append(k)
			k += 1
		out["camp"][d["id"]] = figures_at(need2, centres2)
		out["camp_slots"][d["id"]] = idxs
		out["fires"].append(camp_fire_point(idxs[0]))
	out["camp_used"] = k
	return out


## Camp slot `k`'s block centre in the camp's frame: CAMP_COLS slots along the wall (x), then rows further
## out (z, away from the wall). The block stands in the slot's outer part, its tent behind it.
static func camp_block_centre(k: int) -> Vector2:
	var c: int = k % CAMP_COLS
	var r: int = k / CAMP_COLS
	var pitch: float = SLOT.y + TENT_D + GAP.y
	return Vector2(c * (SLOT.x + GAP.x) + SLOT.x * 0.5, r * pitch + TENT_D + SLOT.y * 0.5)


## Where camp slot `k`'s tent stands (its middle), behind its block toward the wall.
static func camp_tent_point(k: int) -> Vector2:
	var b := camp_block_centre(k)
	return b - Vector2(0.0, SLOT.y * 0.5 + TENT_D * 0.5)


## A camp army's fire: at the road-side end of its first slot's tent line.
static func camp_fire_point(k: int) -> Vector2:
	return camp_tent_point(k) + Vector2(-SLOT.x * 0.5 - GAP.x * 0.5, 0.0)


## Ghost places for queued recruits at one fortress, from the muster `m` (layout()) and the armies'
## slot needs: `ghosts` [{"army": the army they will join ("" a new army), "type", "n", "leader": bool}].
## A recruit joining an army's block of its type takes the next place in that block's slot; anything
## else takes the next free yard slot, or a camp slot after the camp's armies. Returns
## [{"type", "role", "pos", "where": "yard" or "camp"}] in `ghosts` order, `n` places per entry.
static func ghost_places(m: Dictionary, descs: Array, ghosts: Array) -> Array:
	var g: Vector2i = m["grid"]
	var used: Array = (m["used"] as Array).duplicate()
	var by_id := {}
	for d in descs:
		by_id[d["id"]] = d
	var taken := {} ## "army|slot index" -> places taken so far beyond the real figures
	var new_slots := {} ## "army|type" -> [slot index, where, places taken]
	var camp_k: int = int(m["camp_used"])
	var out: Array = []
	for gh in ghosts:
		var aid := String(gh.get("army", ""))
		var t := String(gh["type"])
		var sp: Vector2 = gh.get("sp", Vector2(4.2, 4.4))
		for q in int(gh["n"]):
			var placed := false
			if bool(gh.get("leader", false)):
				## a commander joins its army's colour party (the rules give it to the first army without one)
				if aid != "" and (m["slots"] as Dictionary).has(aid):
					var ps: int = m["slots"][aid][0]
					var pc := slot_centre(g, ps)
					var kk := "%s|party" % aid
					var nth: int = int(taken.get(kk, 0))
					taken[kk] = nth + 1
					out.append({"type": t, "role": "commander", "pos": pc + Vector2(-SLOT.x * 0.5 + 2.2 + nth * 3.6, -DRILL.y * 0.9), "where": "yard"})
					placed = true
			elif aid != "" and (m["slots"] as Dictionary).has(aid) and by_id.has(aid):
				## the army's last slot of this type, while it has room
				var slots: Array = army_slots(by_id[aid])
				var idxs: Array = m["slots"][aid]
				for si in range(slots.size() - 1, -1, -1):
					var sl: Dictionary = slots[si]
					if sl["kind"] != "block" or sl["type"] != t:
						continue
					var fit := slot_fit(sl["sp"])
					var key := "%s|%d" % [aid, si]
					var extra: int = int(taken.get(key, 0))
					if int(sl["n"]) + extra < fit.x * fit.y:
						taken[key] = extra + 1
						out.append({"type": t, "role": "unit", "pos": place_in_slot(slot_centre(g, idxs[si]), sl["sp"], int(sl["n"]) + extra), "where": "yard"})
						placed = true
					break
			if placed:
				continue
			## a block of its own: the slot this army's ghosts of this type already opened, else a new one
			var nk := "%s|%s" % [aid, t]
			if new_slots.has(nk):
				var ns: Array = new_slots[nk]
				var fit2 := slot_fit(sp)
				if int(ns[2]) < fit2.x * fit2.y:
					var c0: Vector2 = slot_centre(g, ns[0]) if ns[1] == "yard" else camp_block_centre(ns[0])
					out.append({"type": t, "role": "unit", "pos": place_in_slot(c0, sp, ns[2]), "where": ns[1]})
					ns[2] = int(ns[2]) + 1
					continue
			var free := used.find(false)
			if free >= 0:
				used[free] = true
				new_slots[nk] = [free, "yard", 1]
				out.append({"type": t, "role": "unit", "pos": place_in_slot(slot_centre(g, free), sp, 0), "where": "yard"})
			else:
				new_slots[nk] = [camp_k, "camp", 1]
				out.append({"type": t, "role": "unit", "pos": place_in_slot(camp_block_centre(camp_k), sp, 0), "where": "camp"})
				camp_k += 1
	return out
