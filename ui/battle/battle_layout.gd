class_name BattleLayout
extends RefCounted
## Where every fighter's card stands in the Simple view's field (M3-3, #58; design/M3_BATTLES.md §3.2, §3.4).
## Pure: it reads only the battle log and the field's size, so tests check it without a screen.
##
##   var lay := BattleLayout.build(log, Vector2(1600, 600))
##   lay.slots[fid].rect      the card's rect in field coordinates (the hp bar goes under it, or on top in a crowd)
##   lay.left / lay.right     the side index drawn on each half
##
## Rules (§3.2, read for cards instead of figures):
## - The defender stands on the right. With no defender (both arrived, or a border battle), side 0 is on the
##   left. Each side faces the centre.
## - Each side's ranks are column groups, front rank (tier 0) nearest the centre, then the second rank
##   (tier 1), then the back line (tier 2, commanders). The two front ranks are 120*s apart, ranks 24*s apart,
##   and the side margins 32 px.
## - Within a rank, fighters are grouped by unit type in faction roster order, then by log order, filling
##   columns top to bottom from the frontmost; each column is centred in the ground band, so commanders
##   stand in the middle of the back line. A ruler stands in the middle row of its rank's frontmost column.
## - Cards are 72 x 96 px at scale s = 1. The layout picks the largest s in SCALES at which both sides fit
##   without cards overlapping. Past that, at the smallest scale, rows close up until everything fits
##   (a "crowd": cards overlap upward, lower rows in front, and the hp bar moves to the card's top so it
##   stays visible). Every fixture fits, the biggest (149 a side) as a crowd.
##
## Returns {"scale", "card" (Vector2), "crowd" (bool), "bar_on_top" (bool), "bar_h", "pitch" (Vector2: column
## and row pitch), "left", "right", "slots": [{"rect", "side", "tier", "col", "row", "dir" (+1 faces right,
## -1 faces left), "back_x" (the x of its side's back edge, where routed cards run to)}] by fighter id}.

const SCALES := [1.0, 0.875, 0.75, 0.625]
const CARD := Vector2(72, 96)
## The ground band the cards stand in, in field coordinates at the 600 px field height (scaled with it).
const AREA_TOP := 112.0
const AREA_BOTTOM_MARGIN := 10.0
const SIDE_MARGIN := 32.0
const FRONT_GAP := 120.0
const RANK_GAP := 24.0


static func build(battle_log: Dictionary, field: Vector2) -> Dictionary:
	var sides: Array = battle_log.get("sides", [])
	var left := 0
	var right := 1 if sides.size() > 1 else 0
	for s in sides:
		if s.get("defender", false):
			right = int(s.index)
			left = 1 - right if sides.size() > 1 else 0
	var tiers := {}  # side -> [[fids of tier 0], [tier 1], [tier 2]]
	for si in sides.size():
		tiers[si] = _ordered_tiers(battle_log, si)
	var area_top := AREA_TOP * field.y / 600.0
	var area_h := field.y - area_top - AREA_BOTTOM_MARGIN
	var pick := {}
	for s in SCALES:
		var g := _geometry(s, area_h)
		var fits := true
		for si in sides.size():
			if _width(tiers[si], int(g.rows), g) > _available(field, s):
				fits = false
		if fits:
			pick = g
			break
	if pick.is_empty():
		# A crowd: the smallest scale, rows closing up until both sides fit.
		pick = _geometry(SCALES[-1], area_h)
		var rows := int(pick.rows)
		var limit := 400
		while limit > 0:
			var ok := true
			for si in sides.size():
				if _width(tiers[si], rows, pick) > _available(field, float(pick.scale)):
					ok = false
			if ok:
				break
			rows += 1
			limit -= 1
		pick.rows = rows
		pick.crowd = true
		var block: float = pick.card.y
		pick.pitch_y = maxf(8.0, (area_h - block) / maxf(1.0, rows - 1))
	var slots := []
	slots.resize(battle_log.get("fighters", []).size())
	for si in sides.size():
		var on_left := sides.size() == 1 or si == left
		_place(battle_log, slots, si, on_left, tiers[si], pick, field, area_top, area_h)
	return {"scale": pick.scale, "card": pick.card, "crowd": pick.crowd, "bar_on_top": pick.crowd, "bar_h": pick.bar_h,
		"pitch": Vector2(pick.cell_w, pick.pitch_y), "left": left, "right": right, "slots": slots}


static func _geometry(s: float, area_h: float) -> Dictionary:
	var card := (CARD * s).round()
	var bar_h := maxf(4.0, roundf(6.0 * s))
	var gap_x := roundf(8.0 * s)
	var gap_y := roundf(8.0 * s)
	var cell_h := card.y + 2.0 + bar_h + gap_y
	var rows := maxi(1, int(floor((area_h + gap_y) / cell_h)))
	return {"scale": s, "card": card, "bar_h": bar_h, "cell_w": card.x + gap_x, "gap_x": gap_x, "cell_h": cell_h, "pitch_y": cell_h,
		"rows": rows, "crowd": false}


static func _available(field: Vector2, s: float) -> float:
	return field.x / 2.0 - SIDE_MARGIN - FRONT_GAP * s / 2.0


static func _width(side_tiers: Array, rows: int, g: Dictionary) -> float:
	var w := 0.0
	var used := 0
	for t in side_tiers:
		if t.is_empty():
			continue
		w += ceili(float(t.size()) / rows) * float(g.cell_w)
		used += 1
	return w + maxi(0, used - 1) * RANK_GAP * float(g.scale)


## Side `si`'s fighters by tier, each tier grouped by unit type in roster order, then log order, with a
## ruler moved to the middle of its tier's frontmost column (fixed up in _place once rows are known).
static func _ordered_tiers(battle_log: Dictionary, si: int) -> Array:
	var side: Dictionary = battle_log.sides[si]
	var roster := _roster(String(side.faction))
	var out := [[], [], []]
	for fid in side.fighters:
		var f: Dictionary = battle_log.fighters[int(fid)]
		out[clampi(int(f.tier), 0, 2)].append(int(fid))
	for t in out:
		t.sort_custom(func(a, b):
			var fa: Dictionary = battle_log.fighters[a]
			var fb: Dictionary = battle_log.fighters[b]
			var ra := _rank_in_roster(roster, fa)
			var rb := _rank_in_roster(roster, fb)
			return ra < rb if ra != rb else a < b)
	return out


static func _roster(faction_id: String) -> Array:
	for f in FactionData.FACTIONS:
		if f.id == faction_id:
			var ids := []
			for u in f.unit_types:
				ids.append(String(u.id))
			ids.append(String(f.commander.id))
			return ids
	return []


static func _rank_in_roster(roster: Array, f: Dictionary) -> int:
	if f.role == "ruler":
		return 1000
	var k := roster.find(String(f.type))
	return k if k >= 0 else 500


static func _place(battle_log: Dictionary, slots: Array, si: int, on_left: bool, side_tiers: Array, g: Dictionary, field: Vector2,
		area_top: float, area_h: float) -> void:
	var s: float = g.scale
	var dir := 1 if on_left else -1
	var cursor := field.x / 2.0 - dir * FRONT_GAP * s / 2.0
	var rows := int(g.rows)
	var card: Vector2 = g.card
	var block_h := card.y if g.crowd else card.y + 2.0 + float(g.bar_h)
	var back_x := -card.x - 8.0 if on_left else field.x + 8.0
	for tier in 3:
		var ids: Array = side_tiers[tier].duplicate()
		if ids.is_empty():
			continue
		var cols := ceili(float(ids.size()) / rows)
		var per_col := ceili(float(ids.size()) / cols)
		# A ruler goes to the middle row of the frontmost column.
		for k in ids.size():
			if battle_log.fighters[ids[k]].role == "ruler":
				var rid: int = ids[k]
				ids.remove_at(k)
				var first_col := mini(per_col, ids.size() + 1)
				ids.insert(clampi((first_col - 1) / 2, 0, ids.size()), rid)
				break
		for k in ids.size():
			var col := k / per_col
			var row := k % per_col
			var in_col := mini(per_col, ids.size() - col * per_col)
			var col_h := (in_col - 1) * float(g.pitch_y) + block_h
			var y0 := area_top + (area_h - col_h) / 2.0
			var x := 0.0
			if on_left:
				x = cursor - (col + 1) * float(g.cell_w) + float(g.gap_x) / 2.0
			else:
				x = cursor + col * float(g.cell_w) + float(g.gap_x) / 2.0
			var y := y0 + row * float(g.pitch_y)
			slots[ids[k]] = {"rect": Rect2(Vector2(roundf(x), roundf(y)), card), "side": si, "tier": tier, "col": col, "row": row,
				"dir": dir, "back_x": back_x}
		cursor -= dir * (cols * float(g.cell_w) + RANK_GAP * s)
