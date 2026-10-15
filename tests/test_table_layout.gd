extends "res://tests/test_case.gd"
## UX-1 (#194; design/UX_WAR_TABLE.md §1.3): the Table's geometry, as numbers (ui/table_layout.gd is pure: no nodes). The bands the
## fixed pieces reserve, the board's safe area, and the give-way order of the pieces that float inside it, at the sizes the spec
## supports: a 1600x900 window at 100% (1600x900 logical), at 125% (1280x720 logical) and a 1280x720 window at 100% (the project
## stretches the 1600x900 layout, so 1600x900 logical again). The spec's own numbers (80, 112, 72, 120, 420, 360 px) are pinned
## here; every other number comes from the layout's constants.

const SIZES := [Vector2(1600, 900), Vector2(1280, 720)]
## The biggest each floating piece ever asks for: a tall card (every section open), the guide with its fog line, a notice that
## wraps to four lines, the vision legend, the move forecast, the playback bar and its caption, the close-up chip.
const BIGGEST := {"card": Vector2(400, 900), "legend": Vector2(TableLayout.LEGEND_W, 210), "notice": Vector2(400, 130), "guide": Vector2(350, 170),
	"hover": Vector2(760, 110), "playback": Vector2(830, 62), "caption": Vector2(420, 84), "closeup": Vector2(520, 48)}
## What is on screen together: the table at rest (with the vision legend, a notice and the guide), a turn playing out (the guide
## lingers over it) and the fortress close-up. The playback bar and the close-up chip never show at once.
const SCENES := {
	"at rest": ["card", "legend", "notice", "guide", "hover"],
	"playing": ["card", "playback", "caption", "guide"],
	"close-up": ["card", "closeup", "guide", "hover"],
}


func test_the_bands_are_the_specs_numbers() -> void:
	assert_eq(TableLayout.STACK_W, 80.0, "the notification stack: 80 px on the left")
	assert_eq(TableLayout.TOP_LEFT_H, 112.0, "the plaques and the system row: 112 px along the top on the left")
	assert_eq(TableLayout.TOP_RIGHT_H, 72.0, "72 px on the right")
	assert_eq(TableLayout.BOTTOM_H, 120.0, "tray and seal: 120 px along the bottom")
	assert_eq(TableLayout.CHRONICLE_W, 420.0, "the Chronicle: 420 px")
	assert_eq(TableLayout.CHRONICLE_W_NARROW, 360.0, "360 px below 1600 logical")
	assert_eq(TableLayout.chronicle_width(Vector2(1600, 900)), 420.0)
	assert_eq(TableLayout.chronicle_width(Vector2(1280, 720)), 360.0)
	assert_false(TableLayout.is_narrow(Vector2(1600, 900)))
	assert_true(TableLayout.is_narrow(Vector2(1599, 900)), "compact below 1600 logical")
	assert_true(TableLayout.is_narrow(Vector2(1280, 720)))


func test_the_safe_area_is_the_window_less_the_bands() -> void:
	for viewport: Vector2 in SIZES:
		var safe := TableLayout.safe_area(viewport)
		assert_eq(safe.position, Vector2(TableLayout.STACK_W, TableLayout.TOP_LEFT_H), "it starts right of the stack and under the plaques at %s" % viewport)
		assert_eq(safe.end, Vector2(viewport.x, viewport.y - TableLayout.BOTTOM_H), "and ends at the window's right edge and over the tray at %s" % viewport)
		var open := TableLayout.safe_area(viewport, true)
		assert_eq(open.end.x, viewport.x - TableLayout.chronicle_width(viewport), "the Chronicle, open, takes its column on the right at %s" % viewport)
		assert_eq(open.position, safe.position)
		var bands := TableLayout.bands(viewport)
		for name in ["stack", "top_left", "top_right", "bottom"]:
			assert_true(bands.has(name), "the band %s" % name)
			assert_false(TableLayout.overlaps(bands[name], safe), "the %s band is outside the safe area at %s" % [name, viewport])
		assert_false(TableLayout.overlaps(bands["stack"], bands["top_left"]), "the stack starts where the top band ends")
		assert_false(TableLayout.overlaps(bands["stack"], bands["bottom"]), "and stops where the bottom band starts")
		assert_false(bands.has("chronicle"), "no Chronicle band while it is closed")
		assert_true(TableLayout.bands(viewport, true).has("chronicle"))
		assert_false(TableLayout.overlaps(TableLayout.bands(viewport, true)["chronicle"], TableLayout.safe_area(viewport, true)), "and the open Chronicle is outside the safe area")


func test_the_card_may_be_as_tall_as_the_safe_area_less_its_gaps() -> void:
	for viewport: Vector2 in SIZES:
		assert_eq(TableLayout.card_max_height(viewport), TableLayout.safe_area(viewport).size.y - 2.0 * TableLayout.GAP)
	assert_eq(TableLayout.card_max_height(Vector2(10, 10)), 0.0, "never negative in a window with no room")


func test_the_framing_area_is_the_safe_area_right_of_the_docked_card() -> void:
	for viewport: Vector2 in SIZES:
		var safe := TableLayout.safe_area(viewport)
		var frame := TableLayout.framing_area(viewport)
		assert_true(safe.encloses(frame), "inside the safe area at %s" % viewport)
		assert_eq(frame.position.x, safe.position.x + TableLayout.CARD_W + 2.0 * TableLayout.GAP, "right of the left column (the card's width and a gap each side) at %s" % viewport)
		assert_eq(frame.end, safe.end)
		assert_true(frame.size.x >= TableLayout.MAP_MIN_W, "wide enough to frame a map in at %s (%d px)" % [viewport, frame.size.x])
		# UI-FIT (#237): with the Chronicle open too, the framing stays right of the card column at every supported size
		var with_chronicle := TableLayout.framing_area(viewport, true)
		assert_eq(with_chronicle.position.x, frame.position.x, "and with the Chronicle open at %s, clear of the card (%d px of map)" % [viewport, with_chronicle.size.x])
	assert_eq(TableLayout.framing_area(Vector2(700, 500)).size.x, TableLayout.MAP_MIN_W, "a window too small for the card column and a map gives the map MAP_MIN_W")


func test_every_floating_piece_finds_its_place_at_every_size_with_nothing_overlapping() -> void:
	for viewport: Vector2 in SIZES:
		for scene: String in SCENES:
			var pieces := {}
			for name: String in SCENES[scene]:
				pieces[name] = BIGGEST[name]
			var where := "%s, %s" % [viewport, scene]
			var safe := TableLayout.safe_area(viewport)
			var result: Dictionary = TableLayout.arrange(viewport, pieces)
			var rects: Dictionary = result.rects
			assert_eq(rects.keys().size(), pieces.size(), "every piece is placed at %s" % where)
			for a: String in rects:
				assert_true(safe.grow(0.5).encloses(rects[a]), "%s is inside the safe area at %s (%s in %s)" % [a, where, rects[a], safe])
				for b: String in rects:
					if a < b:
						assert_false(TableLayout.overlaps(rects[a], rects[b]), "%s and %s overlap at %s (%s, %s)" % [a, b, where, rects[a], rects[b]])
			assert_eq(result.overflow, [], "nothing found no room at %s" % where)


func test_with_the_chronicle_open_the_pieces_still_fit_a_wide_window() -> void:
	var viewport := Vector2(1600, 900)
	var pieces := {}
	for name: String in SCENES["at rest"]:
		pieces[name] = BIGGEST[name]
	var safe := TableLayout.safe_area(viewport, true)
	var result: Dictionary = TableLayout.arrange(viewport, pieces, true)
	var rects: Dictionary = result.rects
	for a: String in rects:
		assert_true(safe.grow(0.5).encloses(rects[a]), "%s stays left of the Chronicle (%s in %s)" % [a, rects[a], safe])
		for b: String in rects:
			if a < b:
				assert_false(TableLayout.overlaps(rects[a], rects[b]), "%s and %s overlap beside the Chronicle" % [a, b])
	assert_eq(result.overflow, [])


func test_the_card_docks_bottom_left_and_shrinks_only_for_a_piece_above_it() -> void:
	for viewport: Vector2 in SIZES:
		var safe := TableLayout.safe_area(viewport)
		var alone: Rect2 = TableLayout.arrange(viewport, {"card": Vector2(400, 300)}).rects["card"]
		assert_eq(alone.position, Vector2(safe.position.x + TableLayout.GAP, safe.end.y - TableLayout.GAP - 300.0), "bottom left of the safe area at %s" % viewport)
		var tall: Rect2 = TableLayout.arrange(viewport, {"card": Vector2(400, 5000)}).rects["card"]
		assert_eq(tall.size.y, safe.size.y - 2.0 * TableLayout.GAP, "no taller than the safe area less its gaps at %s" % viewport)
		assert_eq(tall.end.y, safe.end.y - TableLayout.GAP, "its bottom stays docked")
		# A playback bar over it takes room from the top of the card, never below the card's minimum.
		var with_bar: Dictionary = TableLayout.arrange(viewport, {"playback": Vector2(830, 62), "card": Vector2(400, 5000)}).rects
		assert_false(TableLayout.overlaps(with_bar["card"], with_bar["playback"]), "the card gives way to the playback bar at %s" % viewport)
		assert_true((with_bar["card"] as Rect2).size.y >= TableLayout.CARD_MIN_H, "but is never squeezed below %d px" % TableLayout.CARD_MIN_H)
		assert_eq((with_bar["card"] as Rect2).end.y, tall.end.y, "its bottom does not move")


func test_the_guide_leads_the_left_column_and_the_card_docks_under_it() -> void:
	for viewport: Vector2 in SIZES:
		var safe := TableLayout.safe_area(viewport)
		var top_left := safe.position + Vector2(TableLayout.GAP, TableLayout.GAP)
		var alone: Dictionary = TableLayout.arrange(viewport, {"guide": Vector2(350, 160)}).rects
		assert_eq((alone["guide"] as Rect2).position, top_left, "the guide hangs under the realm plaque at %s" % viewport)
		var both: Dictionary = TableLayout.arrange(viewport, {"card": Vector2(400, 900), "guide": Vector2(350, 160)}).rects
		var guide := both["guide"] as Rect2
		var card := both["card"] as Rect2
		assert_eq(guide.position, top_left, "with a tall card the guide stays at the top left (the card gives it the room) at %s" % viewport)
		assert_eq(card.position.x, guide.position.x, "the card is in the same column")
		assert_eq(card.position.y, guide.end.y + TableLayout.GAP, "right under the guide")
		assert_eq(card.end.y, safe.end.y - TableLayout.GAP, "still docked at the bottom")
		assert_true(card.size.y >= TableLayout.CARD_MIN_H, "and tall enough to scroll in (%d px)" % card.size.y)
		var short: Dictionary = TableLayout.arrange(viewport, {"card": Vector2(400, 120), "guide": Vector2(350, 160)}).rects
		assert_eq((short["card"] as Rect2).end.y, safe.end.y - TableLayout.GAP, "a short card stays at the bottom, with the room between")
		var with_notice: Dictionary = TableLayout.arrange(viewport, {"notice": Vector2(400, 100), "guide": Vector2(350, 160), "card": Vector2(400, 900)}).rects
		assert_eq((with_notice["notice"] as Rect2).position, top_left, "a notice takes the top left")
		assert_eq((with_notice["guide"] as Rect2).position, Vector2(top_left.x, (with_notice["notice"] as Rect2).end.y + TableLayout.GAP), "the guide hangs under it")
		assert_eq((with_notice["card"] as Rect2).position.y, (with_notice["guide"] as Rect2).end.y + TableLayout.GAP, "and the card under both")
		assert_true(TableLayout.arrange(viewport, {"notice": Vector2(400, 130), "guide": Vector2(350, 170), "card": Vector2(400, 900)}).overflow.is_empty(), "the biggest notice, guide and card share the column at %s" % viewport)


func test_nothing_in_the_left_column_reaches_the_framing_area() -> void:
	for viewport: Vector2 in SIZES:
		var frame := TableLayout.framing_area(viewport)
		var rects: Dictionary = TableLayout.arrange(viewport, {"notice": Vector2(400, 130), "guide": Vector2(350, 280), "card": Vector2(400, 900)}).rects
		for name in ["notice", "guide", "card"]:
			assert_true((rects[name] as Rect2).end.x <= frame.position.x - TableLayout.GAP + 0.01, "%s ends left of the framing area at %s (%d against %d)" % [name, viewport, (rects[name] as Rect2).end.x, frame.position.x])


func test_the_forecast_runs_along_the_bottom_right_of_the_card() -> void:
	for viewport: Vector2 in SIZES:
		var safe := TableLayout.safe_area(viewport)
		var r: Dictionary = TableLayout.arrange(viewport, {"card": Vector2(400, 500), "hover": Vector2(760, 90)}).rects
		var hover := r["hover"] as Rect2
		assert_eq(hover.position.x, (r["card"] as Rect2).end.x + TableLayout.GAP, "right of the card at %s" % viewport)
		assert_eq(hover.end.y, safe.end.y - TableLayout.GAP, "along the bottom of the safe area")
		assert_true(hover.end.x <= safe.end.x - TableLayout.GAP + 0.01, "and inside it")


## UX-7 (§4.0): the lens legend sits bottom left, in the left column (as wide as the card), and the card docks on top of it, shrinking as
## it does for the guide; only when the column can't hold the legend, the notice and the guide and a card's least height does the legend
## stand beside the column instead. The framing area (where the map is) stays clear of it either way it can be.
func test_the_lens_legend_sits_bottom_left_and_the_card_docks_on_it() -> void:
	for viewport: Vector2 in SIZES:
		var safe := TableLayout.safe_area(viewport)
		var frame := TableLayout.framing_area(viewport)
		var alone: Rect2 = TableLayout.arrange(viewport, {"legend": Vector2(TableLayout.LEGEND_W, 200)}).rects["legend"]
		assert_eq(alone.position.x, safe.position.x + TableLayout.GAP, "the legend is at the left edge at %s" % viewport)
		assert_eq(alone.end.y, safe.end.y - TableLayout.GAP, "at the bottom")
		assert_true(alone.end.x <= frame.position.x - TableLayout.GAP + 0.01, "in the left column, clear of the map's framing")
		for card_h in [150.0, 900.0]:
			var r: Dictionary = TableLayout.arrange(viewport, {"card": Vector2(400, card_h), "legend": Vector2(TableLayout.LEGEND_W, 200)})
			var legend := r.rects["legend"] as Rect2
			var card := r.rects["card"] as Rect2
			assert_eq(legend, alone, "a card never moves the legend (%d tall)" % card_h)
			assert_eq(card.position.x, legend.position.x, "the card is in the same column")
			assert_eq(card.end.y, legend.position.y - TableLayout.GAP, "docked right on top of the legend")
			assert_true(card.position.y >= safe.position.y + TableLayout.GAP - 0.01, "inside the safe area")
			assert_true(card.size.y >= minf(card_h, TableLayout.CARD_MIN_H), "and at least its least height")
			assert_eq(r.overflow, [])
		# the column full: the notice, the guide and a tall legend leave no card its least height, so the legend stands beside it
		var full: Dictionary = TableLayout.arrange(viewport, {"notice": Vector2(400, 130), "guide": Vector2(350, 170), "legend": Vector2(TableLayout.LEGEND_W, 260),
			"card": Vector2(400, 900)})
		var beside := full.rects["legend"] as Rect2
		assert_eq(beside.position.x, safe.position.x + 2.0 * TableLayout.GAP + TableLayout.CARD_W, "beside the column at %s" % viewport)
		assert_eq(beside.end.y, safe.end.y - TableLayout.GAP, "still at the bottom")
		assert_eq((full.rects["card"] as Rect2).end.y, safe.end.y - TableLayout.GAP, "and the card docks at the bottom of its column again")
		assert_eq(full.overflow, [])


func test_a_piece_placed_earlier_never_moves_for_a_later_one() -> void:
	for viewport: Vector2 in SIZES:
		for scene: String in SCENES:
			var pieces := {}
			for name: String in SCENES[scene]:
				pieces[name] = BIGGEST[name]
			var rects: Dictionary = TableLayout.arrange(viewport, pieces).rects
			var order: Array = TableLayout.FLOATING.filter(func(n): return pieces.has(n))
			for i in order.size():
				var subset := {}
				for name in order.slice(0, i + 1):
					subset[name] = pieces[name]
				var partial: Dictionary = TableLayout.arrange(viewport, subset).rects
				assert_eq(partial[order[i]], rects[order[i]], "%s sits where it does whatever comes after it, at %s (%s)" % [order[i], viewport, scene])


func test_find_spot_goes_around_blockers_and_says_when_there_is_no_room() -> void:
	var safe := Rect2(0, 0, 500, 300)
	var size := Vector2(100, 100)
	assert_eq(TableLayout.find_spot(size, Vector2(8, 8), safe, []), Vector2(8, 8), "the preferred spot when it is free")
	var wall := Rect2(0, 0, 200, 300)
	var spot := TableLayout.find_spot(size, Vector2(8, 8), safe, [wall])
	assert_eq(spot.x, wall.end.x + TableLayout.GAP, "right of a blocker in the way")
	var all := Rect2(0, 0, 500, 300)
	assert_eq(TableLayout.find_spot(size, Vector2(8, 8), safe, [all]).x, INF, "no room: INF, and the caller squeezes it")


func test_overlap_means_more_than_touching() -> void:
	assert_false(TableLayout.overlaps(Rect2(0, 0, 10, 10), Rect2(10, 0, 10, 10)), "sharing an edge is not overlapping")
	assert_true(TableLayout.overlaps(Rect2(0, 0, 10, 10), Rect2(9, 0, 10, 10)))
	assert_false(TableLayout.overlaps(Rect2(0, 0, 10, 10), Rect2(20, 20, 5, 5)))
