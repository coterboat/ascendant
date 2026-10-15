class_name OrderSpots
extends RefCounted
## UX-4 (design/UX_WAR_TABLE.md §3.4, issue #213): where an order's token may stand on a board. Both boards place their tokens the same way:
## each token has a list of candidate rects, best first (the middle of a march's arrow, or a ring of spots round its province), and takes the
## first that lies on screen and clear of every rect in `taken` (the province plates, the army plates, the 2D map's labels, the Table's pieces and
## the tokens placed before it), so a number never sits on a plate's label. Pure geometry on rects, except hud_rects, which reads the Table.

## The angles round a province, in degrees (0 is east, screen y down), best first: the sides of the stage first (the plates stand below it and the
## armies' plates above), then the corners. Each is tried at every ring.
const ANGLES := [0.0, -32.0, 32.0, 180.0, 212.0, 148.0, -64.0, 64.0, 244.0, 116.0, -96.0, 96.0]
const RINGS := [1.0, 1.35, 1.7, 2.1]


## Candidate rects of `sz` round `centre`, on an ellipse with radii `rx` and `ry`, each ring a bit further out. The token's near edge stands
## on the ellipse, so a wide token is not centred on it.
static func ring_spots(centre: Vector2, rx: float, ry: float, sz: Vector2) -> Array:
	var out := []
	for ring in RINGS:
		for deg in ANGLES:
			var a := deg_to_rad(float(deg))
			var c := centre + Vector2(cos(a) * (rx * float(ring) + sz.x * 0.5 * absf(cos(a))), sin(a) * (ry * float(ring) + sz.y * 0.5 * absf(sin(a))))
			out.append(Rect2(c - sz * 0.5, sz))
	return out


## How far along a march's arrow its number may stand (the middle first), and how far off the arrow, to either side, when the arrow's own
## stretch is taken by plates.
const PATH_FRACTIONS := [0.5, 0.42, 0.58, 0.34, 0.66, 0.26, 0.74, 0.18, 0.82]
const PATH_OFFSETS := [0.0, 22.0, -22.0, 40.0, -40.0]


## Candidate rects of `sz` along the polyline `pts` (an arrow's screen points): the number on the arrow first, at each of PATH_FRACTIONS, then
## the same stretches pushed off it to one side and the other.
static func path_spots(pts: PackedVector2Array, sz: Vector2) -> Array:
	var out := []
	if pts.size() < 2:
		return out
	var lens := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		lens.append(lens[i - 1] + pts[i - 1].distance_to(pts[i]))
	var total: float = lens[lens.size() - 1]
	if total <= 0.0:
		return out
	for off in PATH_OFFSETS:
		for f in PATH_FRACTIONS:
			var at := _along(pts, lens, total * float(f))
			var ahead := _along(pts, lens, minf(total * float(f) + 4.0, total))
			var behind := _along(pts, lens, maxf(total * float(f) - 4.0, 0.0))
			var tangent := (ahead - behind).normalized()
			var centre := at + Vector2(-tangent.y, tangent.x) * float(off)
			out.append(Rect2(centre - sz * 0.5, sz))
	return out


static func _along(pts: PackedVector2Array, lens: PackedFloat32Array, d: float) -> Vector2:
	for i in range(1, pts.size()):
		if d <= lens[i]:
			var seg: float = maxf(lens[i] - lens[i - 1], 0.001)
			return pts[i - 1].lerp(pts[i], (d - lens[i - 1]) / seg)
	return pts[pts.size() - 1]


## The first of `spots` that lies inside `bounds` (moved in if it only just pokes out) and clear of every rect in `taken`; failing that (unless
## `strict`) the one that overlaps them least, where a rect in `heavy` (the Table's pieces, which hide what is under them) counts four times. An
## empty Rect2 when there is no spot at all, or none that is free and `strict`.
static func free_spot(spots: Array, taken: Array, bounds: Rect2, strict: bool = false, heavy: Array = []) -> Rect2:
	var best := Rect2()
	var best_area := INF
	for spot in spots:
		var r: Rect2 = spot
		if r.end.x < bounds.position.x or r.position.x > bounds.end.x or r.end.y < bounds.position.y or r.position.y > bounds.end.y:
			continue
		r.position = r.position.clamp(bounds.position, (bounds.end - r.size).max(bounds.position))
		var area := 0.0
		for o in taken:
			var hit: Rect2 = (o as Rect2).intersection(r)
			area += hit.size.x * hit.size.y
		for h in heavy:
			var hit2: Rect2 = (h as Rect2).intersection(r)
			area += 4.0 * hit2.size.x * hit2.size.y
		if area <= 0.0:
			return r
		if area < best_area and not strict:
			best_area = area
			best = r
	return best


## The Table's pieces on screen, in the coordinates of a control whose global position is `origin`: the card, the guide and the notice, the
## plaques, the system row, the tray and the seal, a little grown. Nothing the board draws for an order should hide under one. Empty until the
## Table has a layout (a headless test) or when `map` has none.
static func hud_rects(map: Control, origin: Vector2) -> Array:
	var out := []
	if map == null or not map.has_method("table"):
		return out
	var hud: Control = map.table()
	if hud == null or not hud.has_method("has_layout") or not hud.has_layout():
		return out
	for c in hud.pieces():
		var ctl := c as Control
		if ctl is NumberBadge:
			continue  # UI-CLUTTER: the Chronicle's markers ride on the board and go round the order marks, not the other way
		if ctl != null and ctl.is_visible_in_tree() and ctl.size.x > 0.0:
			out.append(Rect2(ctl.global_position - origin, ctl.size).grow(4.0))
	var placed: Dictionary = hud.placed()
	for kind in ["guide", "notice"]:  # pieces that hang elsewhere in the tree are placed by the Table all the same
		if placed.has(kind):
			var r: Rect2 = placed[kind]
			out.append(Rect2(r.position + hud.global_position - origin, r.size).grow(4.0))
	return out
