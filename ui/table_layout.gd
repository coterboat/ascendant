class_name TableLayout
extends RefCounted
## UX-1 (design/UX_WAR_TABLE.md §1.3): the pure geometry of the Table. No nodes, so the rules of the layout are tested
## on plain numbers (tests/test_table_hud.gd) and the live pieces (TableHud) only apply what this works out.
##
## The board fills the window. A few pieces sit on it, each in a band it reserves:
##   notification stack   80 px down the left edge, under the system row
##   realm plaque and system row   112 px along the top, on the left
##   opponent plaque and Menu      72 px along the top, on the right
##   tray and seal                 120 px along the bottom
##   the Chronicle, when open      420 px on the right (360 px below 1600 logical)
## What remains is the board's safe area. The selection card, the guide, the notices and the hover forecast are placed
## only inside it. Who gives way, highest first: modal panels, the Chronicle, the selection card, the guide and
## notices, the tray, the plaques; a lower piece moves before it overlaps a higher one (arrange).
## All sizes are logical pixels: at Settings' 125% interface size a 1600x900 window is 1280x720 logical.

## The gap between pieces, and between a piece and the edge of the window or of the safe area.
const GAP := 8.0
const STACK_W := 80.0
const TOP_LEFT_H := 112.0
const TOP_RIGHT_H := 72.0
const BOTTOM_H := 120.0
const CHRONICLE_W := 420.0
const CHRONICLE_W_NARROW := 360.0
## From this logical width the layout is "wide"; below it the system row is icons only, the notification stack shows at
## most six medallions and the tray tokens and the opponent plaque shorten (§1.3).
const WIDE_FROM := 1600.0
## The widths of the pieces that float inside the safe area.
const CARD_W := 400.0
## The notice is as wide as the card: the guide, the notice and the card share the left column, so the board frames to their right.
const NOTICE_W := CARD_W
## UX-7: the lens legend lives in the left column too, as wide as the card.
const LEGEND_W := CARD_W
const HOVER_MAX_W := 760.0
## The pieces arrange() places, in the order they take their spots (the first never moves). The playback bar, its caption and the
## close-up chip are the board's own transient pieces, hung by the Table so nothing covers their buttons. The notice and the guide
## take the top of the left column before the card, which docks under them and shrinks (it scrolls): the whole left column is the
## card's, the guide's and the notice's, and the board frames the map to the right of it (framing_area), so the guide never covers
## the map (UX-1 review: at 125% it covered Westwatch, the capital's neighbour and turn 1's first move). UX-7: the lens legend takes
## the bottom of the column before the card too (a lens is on only when the player asked for it), and the card docks on top of it,
## shrinking as it does for the guide; only when the column can't hold the legend and a card's least height does it stand beside it.
const FLOATING := ["playback", "closeup", "caption", "notice", "guide", "legend", "card", "hover"]
## The shortest a selection card is squeezed to (it scrolls) when a piece above it needs its room.
const CARD_MIN_H := 120.0


## True below 1600 logical width: the compact Table.
static func is_narrow(viewport: Vector2) -> bool:
	return viewport.x < WIDE_FROM


## The Chronicle's width in a window: 420 px, 360 px below 1600 logical.
static func chronicle_width(viewport: Vector2) -> float:
	return CHRONICLE_W_NARROW if is_narrow(viewport) else CHRONICLE_W


## The band each fixed piece is reserved, by name: "stack", "top_left", "top_right", "bottom" and, when open, "chronicle".
## The top bands run the whole width: a piece in one stays inside its height and keeps to its own side.
static func bands(viewport: Vector2, chronicle_open: bool = false) -> Dictionary:
	var right := chronicle_width(viewport) if chronicle_open else 0.0
	var out := {
		"top_left": Rect2(0, 0, viewport.x - right, TOP_LEFT_H),
		"top_right": Rect2(0, 0, viewport.x - right, TOP_RIGHT_H),
		"stack": Rect2(0, TOP_LEFT_H, STACK_W, maxf(viewport.y - TOP_LEFT_H - BOTTOM_H, 0.0)),
		"bottom": Rect2(0, viewport.y - BOTTOM_H, viewport.x - right, BOTTOM_H),
	}
	if chronicle_open:
		out["chronicle"] = Rect2(viewport.x - right, 0, right, viewport.y)
	return out


## The board's safe area: the window less the bands. A card, the guide and the notices sit only inside it.
static func safe_area(viewport: Vector2, chronicle_open: bool = false) -> Rect2:
	var right := chronicle_width(viewport) if chronicle_open else 0.0
	var x := STACK_W
	var y := TOP_LEFT_H
	return Rect2(x, y, maxf(viewport.x - right - x, 0.0), maxf(viewport.y - BOTTOM_H - y, 0.0))


## Where a board frames the whole map at its first look (the 3D board's whole-map camera, the 2D map's fit): the safe area to
## the right of the left column (the notice, the guide and the docked selection card, CARD_W wide, with a gap each side), so the
## map is not drawn under any of them, the plaques or the tray. Until UX-3 puts the selection cards beside their plates the
## column is fixed.
static func framing_area(viewport: Vector2, chronicle_open: bool = false) -> Rect2:
	var safe := safe_area(viewport, chronicle_open)
	var left := minf(CARD_W + 2.0 * GAP, maxf(safe.size.x - 480.0, 0.0))
	return Rect2(safe.position.x + left, safe.position.y, safe.size.x - left, safe.size.y)


## The tallest a selection card may be: the safe area less a gap above and below.
static func card_max_height(viewport: Vector2, chronicle_open: bool = false) -> float:
	return maxf(safe_area(viewport, chronicle_open).size.y - 2.0 * GAP, 0.0)


## True when two rects overlap by more than a hair (rects that only touch do not).
static func overlaps(a: Rect2, b: Rect2) -> bool:
	return a.position.x < b.end.x - 0.5 and b.position.x < a.end.x - 0.5 \
		and a.position.y < b.end.y - 0.5 and b.position.y < a.end.y - 0.5


## Where a piece of `size` goes in `safe`, as close as it can to `preferred` (its top-left), without overlapping any of
## `blockers` (a gap apart). The candidates are the preferred spot and every spot that lines a piece's edge up with a blocker's
## (right of it, left of it, under it, above it, or flush with its top or left), tried nearest the preferred spot first, so a
## piece moves as little as it can. Returns the top-left, or Vector2(INF, INF) when there is no such spot (the caller squeezes it).
static func find_spot(size: Vector2, preferred: Vector2, safe: Rect2, blockers: Array) -> Vector2:
	var xs: Array = [preferred.x]
	var ys: Array = [preferred.y]
	for b: Rect2 in blockers:
		xs.append_array([b.end.x + GAP, b.position.x, b.position.x - GAP - size.x])
		ys.append_array([b.end.y + GAP, b.position.y, b.position.y - GAP - size.y])
	var candidates: Array = []
	for x: float in xs:
		for y: float in ys:
			candidates.append(Vector2(x, y))
	candidates.sort_custom(func(a: Vector2, b: Vector2): return a.distance_squared_to(preferred) < b.distance_squared_to(preferred))
	for c: Vector2 in candidates:
		var r := Rect2(c, size)
		if not safe.grow(0.5).encloses(r):
			continue
		var clear := true
		for b: Rect2 in blockers:
			if overlaps(r, b.grow(GAP)):
				clear = false
				break
		if clear:
			return c
	return Vector2(INF, INF)


## Places the floating pieces that are showing. `pieces` maps a name from FLOATING to the piece's size; a missing name
## is not showing. Returns {"rects": {name: Rect2}, "overflow": [names that found no free spot]}: an overflowing piece is
## still given a rect (at its preferred spot, squeezed into the safe area) so something is drawn, and the caller reports it.
## The give-way order is FLOATING's: each piece takes its spot first and the later ones go around it.
##   playback, closeup  the board's playback bar and the fortress chip, top centre of the framing area (clamped into the safe area)
##   caption            the playback's phase caption, centred under the bar
##   notice             top left of the safe area, hanging under the realm plaque, as wide as the card
##   guide              under the notice (or at the top left); below a playback bar that is in its way
##   card               docked bottom left of the safe area, as tall as it needs; it shrinks (and scrolls) for the notice, the guide or
##                      a playback bar above it
##   legend             the lens legend (UX-7, §4.0), bottom left of the safe area, in the left column the map is framed beside, under the
##                      notice and the guide; beside the column only when the column can't also hold a card's least height
##   card               (with a legend in the column: docked on top of it)
##   hover              the move forecast, along the bottom of the safe area to the right of the card
static func arrange(viewport: Vector2, pieces: Dictionary, chronicle_open: bool = false) -> Dictionary:
	var safe := safe_area(viewport, chronicle_open)
	var frame := framing_area(viewport, chronicle_open)
	var rects := {}
	var overflow := []
	var blockers: Array = []
	for name: String in FLOATING:
		if not pieces.has(name):
			continue
		var size: Vector2 = pieces[name]
		size = Vector2(minf(size.x, safe.size.x - 2.0 * GAP), minf(size.y, safe.size.y - 2.0 * GAP))
		var preferred := safe.position + Vector2(GAP, GAP)
		match name:
			"playback", "closeup":
				preferred = Vector2(_centred_x(frame.get_center().x, size.x, safe), safe.position.y + GAP)
			"caption":
				var top: float = (rects["playback"] as Rect2).end.y + GAP if rects.has("playback") else safe.position.y + GAP
				var middle: float = (rects["playback"] as Rect2).get_center().x if rects.has("playback") else frame.get_center().x
				preferred = Vector2(_centred_x(middle, size.x, safe), top)
			"card":
				# docked bottom left, on top of the lens legend when it is in the column (UX-7)
				var bottom := safe.end.y - GAP
				if rects.has("legend") and (rects["legend"] as Rect2).position.x < safe.position.x + GAP + CARD_W:
					bottom = (rects["legend"] as Rect2).position.y - GAP
				size.y = maxf(minf(size.y, bottom - safe.position.y - GAP), 0.0)
				preferred = Vector2(safe.position.x + GAP, bottom - size.y)
			"legend":
				# UX-7 (§4.0): bottom left, in the card's column, when the column still leaves a card its least height under the notice and
				# the guide; else beside the column, at the bottom
				var top := safe.position.y + GAP
				for above in ["notice", "guide"]:
					if rects.has(above):
						top = maxf(top, (rects[above] as Rect2).end.y + GAP)
				var floor_y := safe.end.y - GAP
				var in_column := floor_y - size.y - GAP - top >= CARD_MIN_H
				preferred = Vector2(safe.position.x + GAP if in_column else safe.position.x + 2.0 * GAP + CARD_W, floor_y - size.y)
			"guide":
				if rects.has("notice"):
					preferred = Vector2(safe.position.x + GAP, (rects["notice"] as Rect2).end.y + GAP)
			"hover":
				var x: float = (rects["card"] as Rect2).end.x + GAP if rects.has("card") else safe.position.x + GAP
				size.x = minf(size.x, safe.end.x - GAP - x)
				preferred = Vector2(x, safe.end.y - GAP - size.y)
		var at := preferred
		if name == "card":
			var squeezed := _squeeze_card(Rect2(preferred, size), blockers)
			at = squeezed.position
			size = squeezed.size
			for b: Rect2 in blockers:
				if overlaps(squeezed, b):
					overflow.append("card")  # no room even squeezed to CARD_MIN_H: the caller reports it
					break
		elif name not in ["playback", "closeup", "caption"]:
			at = find_spot(size, preferred, safe, blockers)
			if at.x == INF:
				overflow.append(name)
				at = preferred
		var r := Rect2(at, size)
		rects[name] = r
		blockers.append(r)
	return {"rects": rects, "overflow": overflow}


## The left edge of a piece `width` wide centred on `middle`, kept inside the safe area.
static func _centred_x(middle: float, width: float, safe: Rect2) -> float:
	return clampf(middle - width * 0.5, safe.position.x + GAP, maxf(safe.end.x - GAP - width, safe.position.x + GAP))


## A card that would overlap a piece above it gives up height from its top, down to CARD_MIN_H, and scrolls.
static func _squeeze_card(card: Rect2, blockers: Array) -> Rect2:
	var r := card
	for b: Rect2 in blockers:
		if overlaps(r, b.grow(GAP)) and b.end.y + GAP < r.end.y - CARD_MIN_H:
			var top := b.end.y + GAP
			r = Rect2(r.position.x, top, r.size.x, r.end.y - top)
	return r
