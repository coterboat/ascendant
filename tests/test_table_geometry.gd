extends "res://tests/test_case.gd"
## UX-1 (#194; design/UX_WAR_TABLE.md §1.2, §1.3, §1.5): the Table's live geometry and input, at the three sizes the spec supports
## (a 1600x900 window at 100%, the same window at 125%, which lays out as 1280x720, and a 1280x720 window at 100%, which the
## project's stretch lays out as the 1600x900 layout scaled down), on both boards (the 3D world and the 2D map).
## The headless runner's tests run before the scene tree is live, so no Control gets a layout pass and no mouse event is routed here.
## tests/table_probe.gd is a real (headless) main loop in a child Godot process: it sets the real window's size and content scale
## factor, puts a whole game screen in it, puts the Table in each state it has, reports every piece's rect as drawn, sweeps the window
## with real mouse motion asking the viewport what the mouse is over, and clicks. One probe run serves the whole file. What is pinned:
##   * pairwise overlap: no two visible HUD pieces overlap, in any state, at any size, on either board (the guide and the notices count);
##   * the bands: the plaque and the system row stay in the 112 px band, the opponent plaque and Menu in the 72 px band, the tray and the
##     seal in the 120 px band, the notification slot in its 80 px column, and every floating piece inside the board's safe area;
##   * the input contract: the sweep finds no empty HUD area that takes the mouse, and no piece that lets it through;
##   * a click on empty HUD space over land picks the province under it (both boards); each piece eats a click on its own padding
##     and the board never sees it (the selection, the army and the turn are unchanged);
##   * the states themselves: the card, the guide, a notice, the forecast, the Vision legend, the playback bar and its caption and the
##     fortress chip each show where they should, and the 2D map fits the framing area.

const PROBE := "res://tests/table_probe.gd"
const SCRATCH := "user://table_probe"
const BOARDS := ["3d", "2d"]
## The spec's three sizes: key -> the logical size the game lays out for.
const SIZES := {"1600x900": Vector2(1600, 900), "1600x900@125": Vector2(1280, 720), "1280x720": Vector2(1600, 900)}
const SCENARIOS := ["rest", "dismissed", "notice", "forecast", "vision", "army", "recruit", "march", "army_notice"]
const FLOATING := ["card", "legend", "notice", "guide", "hover", "playback", "caption", "closeup"]
## The march strip with its three forecast lines grows upward a little, and no more than this: it is a strip, not a card.
const MARCH_STRIP_MAX_H := 170.0

static var _report := {}


# --- the probe --------------------------------------------------------------------------------------

func _probe() -> Dictionary:
	if not _report.is_empty():
		return _report
	var cmd := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", PROBE]
	var output := []
	var code := OS.execute(OS.get_executable_path(), cmd, output, true)
	_remove_tree(SCRATCH)
	var text := "\n".join(output)
	var parsed = {}
	for line in text.split("\n"):
		if line.begins_with("TABLE_REPORT "):
			parsed = JSON.parse_string(line.trim_prefix("TABLE_REPORT "))
	assert_true(parsed is Dictionary and not parsed.is_empty(), "the probe reported (exit code %d): %s" % [code, text.right(800)])
	_report = parsed if parsed is Dictionary else {}
	return _report


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func _scenarios(board: String) -> Array:
	var out := SCENARIOS.duplicate()
	if board == "3d":
		out.append_array(["playback", "closeup"])
	return out


## Runs `check(board, size_key, scenario, measurement)` for every board, size and state.
func _each(check: Callable) -> void:
	var report := _probe()
	for board in BOARDS:
		assert_true(report.has(board), "the probe measured the %s board" % board)
		for key in SIZES:
			assert_true(report.get(board, {}).has(key), "%s board at %s was measured" % [board, key])
			for scenario in _scenarios(board):
				var m: Dictionary = report.get(board, {}).get(key, {}).get(scenario, {})
				assert_false(m.is_empty(), "%s board at %s: %s was measured" % [board, key, scenario])
				if not m.is_empty():
					check.call(board, key, scenario, m)


func _rect(m: Dictionary, name: String) -> Rect2:
	var r: Array = m.pieces.get(name, [])
	return Rect2(r[0], r[1], r[2], r[3]) if r.size() == 5 else Rect2()


func _shown(m: Dictionary, name: String) -> bool:
	var r: Array = m.pieces.get(name, [])
	return r.size() == 5 and bool(r[4])


func _viewport(m: Dictionary) -> Vector2:
	return Vector2(m.viewport[0], m.viewport[1])


func _where(board: String, key: String, scenario: String) -> String:
	return "%s board, %s, %s" % [board, key, scenario]


# --- the sizes --------------------------------------------------------------------------------------

func test_the_probe_measured_every_state_on_both_boards_at_the_three_sizes() -> void:
	var seen := {}
	_each(func(board: String, key: String, scenario: String, m: Dictionary):
		assert_eq(_viewport(m), SIZES[key], "%s lays out for %s logical" % [_where(board, key, scenario), SIZES[key]])
		assert_eq(bool(m.compact), SIZES[key].x < TableLayout.WIDE_FROM, "%s: the compact Table is below 1600 logical width" % _where(board, key, scenario))
		assert_eq(Vector2(m.hud[2], m.hud[3]), SIZES[key], "%s: the Table fills the window (the map view is full-bleed under it)" % _where(board, key, scenario))
		seen[key] = true)
	assert_eq(seen.keys().size(), 3, "all three sizes")


func test_the_states_show_what_they_should() -> void:
	_each(_check_state)


func _check_state(board: String, key: String, scenario: String, m: Dictionary) -> void:
	var where := _where(board, key, scenario)
	for always in ["plaque", "menu", "opponent", "stack", "tray", "seal", "sys_research", "sys_magic", "sys_ruler", "sys_chronicle", "sys_report", "sys_lenses", "sys_codex", "sys_help"]:
		assert_true(_shown(m, always), "%s: %s is on screen" % [where, always])
	match scenario:
		"rest":
			assert_true(_shown(m, "card") and _shown(m, "guide"), "%s: the card and the guide are up" % where)
			assert_false(_shown(m, "notice") or _shown(m, "legend") or _shown(m, "hover"), "%s: no notice, legend or forecast" % where)
		"dismissed":
			assert_false(_shown(m, "card"), "%s: the closed card is gone" % where)
			assert_true(_shown(m, "guide"), "%s: the guide stays" % where)
		"notice":
			assert_true(_shown(m, "notice") and _shown(m, "guide") and _shown(m, "card"), "%s: the notice, the guide and the card together" % where)
		"forecast":
			assert_true(_shown(m, "card"), "%s: the army's card" % where)
			var fc: Array = m.card_parts.get("forecast", [])
			assert_true(fc.size() == 5 and bool(fc[4]), "%s: the hovered destination's forecast shows (in the card's forecast slot, not over the board)" % where)
		"vision":
			assert_true(_shown(m, "legend"), "%s: the Vision legend" % where)
		"army", "recruit", "army_notice":
			assert_true(_shown(m, "card") and _shown(m, "guide"), "%s: the card and the guide are up" % where)
			assert_eq(m.card_parts.mode, "province" if scenario == "recruit" else "army", "%s: the card of what is selected" % where)
			assert_true(m.card_parts.has("first_action"), "%s: the card has its actions" % where)
			if scenario == "army_notice":
				assert_true(_shown(m, "notice"), "%s: with the notice above it" % where)
		"march":
			assert_true(_shown(m, "card"), "%s: the strip is up" % where)
			assert_true(bool(m.card_parts.marching), "%s: it is the march strip" % where)
			assert_true(_rect(m, "card").size.y < MARCH_STRIP_MAX_H, "%s: slim (%f px tall)" % [where, _rect(m, "card").size.y])
		"playback":
			assert_true(_shown(m, "playback") and _shown(m, "caption"), "%s: the playback bar and its caption" % where)
		"closeup":
			assert_true(_shown(m, "closeup"), "%s: the fortress chip" % where)


# --- the selection cards (UX-3, design/UX_WAR_TABLE.md §3.3) ---------------------------------------------

## The card sits in the card slot, docked bottom left of the safe area, in every state it has (the army card with an order on it, the
## province card with its Recruit section open, the army card under a notice and the guide, and the slim march strip), at all three
## sizes on both boards; its first action is always inside it, in view, whatever the card was squeezed to ("nothing a click needs ever
## hides"); and while a march destination is picked the card is a slim strip docked in the same place.
func test_the_selection_card_is_placed_with_its_first_action_in_view_in_every_state() -> void:
	var cards_seen := {"n": 0}  # a lambda captures a number by value: a dictionary is shared
	_each(func(board: String, key: String, scenario: String, m: Dictionary):
		if not scenario in ["rest", "army", "recruit", "march", "army_notice", "forecast", "notice"]:
			return
		var where := _where(board, key, scenario)
		var safe := Rect2(m.safe[0], m.safe[1], m.safe[2], m.safe[3])
		var card := _rect(m, "card")
		assert_true(_shown(m, "card"), "%s: the card is up" % where)
		assert_true(safe.grow(0.5).encloses(card), "%s: inside the safe area (%s in %s)" % [where, card, safe])
		assert_eq(card.position.x, safe.position.x + TableLayout.GAP, "%s: in the left column" % where)
		assert_true(is_equal_approx(card.end.y, safe.end.y - TableLayout.GAP), "%s: docked at the bottom" % where)
		assert_true(card.size.x <= TableLayout.CARD_W + 0.5, "%s: no wider than the card slot" % where)
		var framing := Rect2(m.framing[0], m.framing[1], m.framing[2], m.framing[3])
		assert_false(TableLayout.overlaps(card, framing), "%s: the card never overlaps the framing area where the map is framed (%s over %s)" % [where, card, framing])
		var forecast: Array = m.card_parts.get("forecast", [])
		if forecast.size() == 5 and bool(forecast[4]):
			var f_rect := Rect2(forecast[0], forecast[1], forecast[2], forecast[3])
			assert_true(card.grow(0.5).encloses(f_rect), "%s: the hover forecast is inside the card (%s in %s), so it never covers the board" % [where, f_rect, card])
			assert_false(TableLayout.overlaps(f_rect, framing), "%s: and never over the framing area" % where)
		if scenario == "march":
			assert_true(bool(m.card_parts.marching) and card.size.y < MARCH_STRIP_MAX_H, "%s: the strip stays slim (%f px, the forecast lines included)" % [where, card.size.y])
			assert_true(forecast.size() == 5 and bool(forecast[4]), "%s: the strip carries the hovered destination's forecast" % where)
			assert_true((m.card_parts.get("forecast_lines", []) as Array).size() >= 2, "%s: in two or three short lines: %s" % [where, m.card_parts.get("forecast_lines", [])])
			return
		var first: Array = m.card_parts.get("first_action", [])
		assert_eq(first.size(), 5, "%s: the card has a first action" % where)
		if first.size() == 5:
			var rect := Rect2(first[0], first[1], first[2], first[3])
			assert_true(bool(first[4]), "%s: it is visible" % where)
			assert_true(card.grow(0.5).encloses(rect), "%s: and inside the card (%s in %s)" % [where, rect, card])
			var scroll: Array = m.card_parts.scroll
			assert_true(rect.end.y <= scroll[1] + 0.5, "%s: above the scroll, so it never scrolls away (%s over %s)" % [where, rect, scroll])
		cards_seen.n += 1)
	assert_true(cards_seen.n >= 20, "cards were checked in every state at every size on both boards (%d)" % cards_seen.n)


## "Placement for provinces on every edge, at the camera's nearest and farthest zoom, at all three sizes" (§3.3, the UX-3 row of §9): the card
## is docked in the left column, so where the selected province or army is on screen makes no difference. With every province selected, then
## each army of yours, at the 3D camera's farthest and nearest zoom (the 2D map has one zoom), at every size on both boards, the card keeps
## the same left edge and width, stays docked at the bottom of the safe area and inside it, and never covers the tray or the plaques.
func test_the_card_is_docked_the_same_for_every_province_and_army_at_every_zoom_and_size() -> void:
	var counted := {"n": 0}
	_each(func(board: String, key: String, scenario: String, m: Dictionary):
		if scenario != "rest":
			return
		var where := _where(board, key, scenario)
		var safe := Rect2(m.safe[0], m.safe[1], m.safe[2], m.safe[3])
		var edges: Dictionary = m.get("edges", {})
		assert_eq(edges.keys().size(), 2 if board == "3d" else 1, "%s: the zoom extremes were measured (%s)" % [where, edges.keys()])
		for zoom in edges:
			var rows: Array = edges[zoom]
			assert_true(rows.size() >= 16, "%s, %s zoom: every province and army was selected (%d)" % [where, zoom, rows.size()])
			for row in rows:
				var r := Rect2(row[2], row[3], row[4], row[5])
				var what := "%s, %s zoom, %s %s" % [where, zoom, row[0], row[1]]
				assert_true(bool(row[6]), "%s: the card is up" % what)
				assert_eq(r.position.x, safe.position.x + TableLayout.GAP, "%s: in the left column" % what)
				assert_true(r.size.x <= TableLayout.CARD_W + 0.5, "%s: no wider than the card slot" % what)
				assert_true(is_equal_approx(r.end.y, safe.end.y - TableLayout.GAP), "%s: docked at the bottom (%s)" % [what, r])
				assert_true(safe.grow(0.5).encloses(r), "%s: inside the safe area" % what)
				counted.n += 1)
	var expected: int = SIZES.size() * 3 * 16  # three sizes; the 3D board's two zooms and the 2D map's one; at least 16 selections each
	assert_true(counted.n >= expected, "cards were measured for every province and army (%d of at least %d)" % [counted.n, expected])


# --- overlap and the bands --------------------------------------------------------------------------

func test_no_two_hud_pieces_overlap_in_any_state_at_any_size_on_either_board() -> void:
	_each(func(board: String, key: String, scenario: String, m: Dictionary):
		var where := _where(board, key, scenario)
		var names: Array = m.pieces.keys().filter(func(n): return _shown(m, n))
		assert_true(names.size() >= 14, "%s: the pieces were found (%d)" % [where, names.size()])
		for i in names.size():
			for j in range(i + 1, names.size()):
				var a: Rect2 = _rect(m, names[i])
				var b: Rect2 = _rect(m, names[j])
				assert_false(TableLayout.overlaps(a, b), "%s: %s and %s overlap (%s, %s)" % [where, names[i], names[j], a, b])
		assert_eq(m.overflow, [], "%s: every floating piece found a free spot" % where))


func test_every_piece_stays_in_its_band_and_every_floating_piece_in_the_safe_area() -> void:
	_each(func(board: String, key: String, scenario: String, m: Dictionary):
		var where := _where(board, key, scenario)
		var vp := _viewport(m)
		var window := Rect2(Vector2.ZERO, vp)
		var safe := Rect2(m.safe[0], m.safe[1], m.safe[2], m.safe[3])
		assert_eq(safe, TableLayout.safe_area(vp), "%s: the safe area is the layout's" % where)
		for name in m.pieces.keys():
			if _shown(m, name):
				assert_true(window.grow(0.5).encloses(_rect(m, name)), "%s: %s is inside the window (%s)" % [where, name, _rect(m, name)])
		# The realm plaque and the system row: 112 px along the top, on the left.
		for name in ["plaque"] + m.pieces.keys().filter(func(n): return String(n).begins_with("sys_")):
			if _shown(m, name):
				assert_true(_rect(m, name).end.y <= TableLayout.TOP_LEFT_H + 0.5, "%s: %s ends inside the 112 px band (%d)" % [where, name, _rect(m, name).end.y])
		# The opponent plaque and Menu: 72 px along the top, on the right.
		for name in ["opponent", "menu"]:
			assert_true(_rect(m, name).end.y <= TableLayout.TOP_RIGHT_H + 0.5, "%s: %s ends inside the 72 px band (%d)" % [where, name, _rect(m, name).end.y])
			assert_true(_rect(m, name).position.x > vp.x * 0.5, "%s: and sits on the right" % where)
		# The notification slot: 80 px down the left edge, under the system row, over the tray.
		assert_eq(_rect(m, "stack").position, Vector2(0, TableLayout.TOP_LEFT_H), "%s: the stack starts under the system row" % where)
		assert_eq(_rect(m, "stack").size.x, TableLayout.STACK_W, "%s: 80 px wide" % where)
		assert_eq(_rect(m, "stack").end.y, vp.y - TableLayout.BOTTOM_H, "%s: and ends over the bottom band" % where)
		# The tray and the seal: 120 px along the bottom, side by side, the seal at the tray's right.
		for name in ["tray", "seal"]:
			assert_true(_rect(m, name).position.y >= vp.y - TableLayout.BOTTOM_H - 0.5, "%s: %s is inside the 120 px bottom band" % [where, name])
		assert_true(_rect(m, "seal").position.x >= _rect(m, "tray").end.x - 0.5, "%s: the seal is at the tray's right" % where)
		# Everything that floats is inside the board's safe area.
		for name in FLOATING:
			if _shown(m, name):
				assert_true(safe.grow(0.5).encloses(_rect(m, name)), "%s: %s is inside the safe area (%s in %s)" % [where, name, _rect(m, name), safe]))


func test_the_left_column_holds_the_notice_the_guide_and_the_card_in_that_order() -> void:
	_each(func(board: String, key: String, scenario: String, m: Dictionary):
		var where := _where(board, key, scenario)
		var safe := Rect2(m.safe[0], m.safe[1], m.safe[2], m.safe[3])
		var framing := Rect2(m.framing[0], m.framing[1], m.framing[2], m.framing[3])
		if scenario in ["playback", "closeup"]:
			return  # a board's own transient bar may push the guide down: no order to hold
		var column := []
		for name in ["notice", "guide", "card"]:
			if _shown(m, name):
				var r := _rect(m, name)
				column.append(r)
				assert_eq(r.position.x, safe.position.x + TableLayout.GAP, "%s: the %s is in the left column" % [where, name])
				assert_true(r.end.x <= framing.position.x, "%s: and ends left of the framing area (%d against %d)" % [where, r.end.x, framing.position.x])
		for i in range(1, column.size()):
			assert_true((column[i] as Rect2).position.y >= (column[i - 1] as Rect2).end.y, "%s: each is under the one above it" % where)
		if _shown(m, "card"):
			assert_true(is_equal_approx(_rect(m, "card").end.y, safe.end.y - TableLayout.GAP), "%s: the card is docked at the bottom" % where)
		if _shown(m, "guide"):
			assert_eq(_rect(m, "guide").position.y, _rect(m, "notice").end.y + TableLayout.GAP if _shown(m, "notice") else safe.position.y + TableLayout.GAP, "%s: the guide hangs under the realm plaque (or the notice)" % where))


## The review's regression: at 125% the first-game guide hung over the north of the map and covered Westwatch, the capital's
## neighbour and turn 1's first move. On turn 1 with the guide up, the name labels of the capital and of every neighbour are inside
## the framing area as drawn, and clear of every HUD piece (the guide, the card, the plaques, the system row, the tray and the seal
## counted), at all three sizes and on both boards, with the card open, closed and with a notice up.
func test_the_capital_and_its_neighbours_labels_are_framed_clear_of_every_hud_piece() -> void:
	var checked := [0]  # a lambda captures an int by value: count in an array
	_each(func(board: String, key: String, scenario: String, m: Dictionary):
		if not scenario in ["rest", "dismissed", "notice"]:
			return
		var where := _where(board, key, scenario)
		assert_true(_shown(m, "guide"), "%s: the guide is up (turn 1 of a first game)" % where)
		var framing := Rect2(m.framing[0], m.framing[1], m.framing[2], m.framing[3])
		var labels: Dictionary = m.labels
		var ids: Array = labels.rects.keys()
		assert_true(ids.has(labels.capital) and ids.size() >= 4, "%s: the capital and its neighbours were found (%s)" % [where, ids])
		for id in ids:
			var r: Array = labels.rects[id]
			var rect := Rect2(r[0], r[1], r[2], r[3])
			assert_true(bool(r[4]), "%s: %s's label is showing" % [where, id])
			assert_true(framing.has_point(rect.get_center()), "%s: %s's label projects inside the framing area (%s in %s)" % [where, id, rect.get_center(), framing])
			assert_true(framing.grow(2.0).encloses(rect), "%s: and all of it does (%s in %s)" % [where, rect, framing])
			for name in m.pieces.keys():
				if _shown(m, name):
					assert_false(TableLayout.overlaps(rect, _rect(m, name)), "%s: %s's label (%s) is covered by %s (%s)" % [where, id, rect, name, _rect(m, name)])
			checked[0] += 1)
	assert_true(checked[0] >= 3 * 2 * 3 * 4, "every label at every size, board and state was checked (%d)" % checked[0])


func test_the_2d_map_fits_the_framing_area() -> void:
	_each(func(board: String, key: String, scenario: String, m: Dictionary):
		if board != "2d":
			return
		var where := _where(board, key, scenario)
		var canvas := Rect2(m.canvas[0], m.canvas[1], m.canvas[2], m.canvas[3])
		var framing := Rect2(m.framing[0], m.framing[1], m.framing[2], m.framing[3])
		assert_eq(framing, TableLayout.framing_area(_viewport(m)), "%s: the framing area is the layout's" % where)
		assert_true(framing.grow(1.0).encloses(canvas), "%s: the whole 2D map is inside the framing area (%s in %s)" % [where, canvas, framing])
		assert_true(canvas.size.x >= 0.7 * framing.size.x or canvas.size.y >= 0.7 * framing.size.y, "%s: and fills most of it (%s)" % [where, canvas]))


# --- the input contract -----------------------------------------------------------------------------

func test_no_empty_hud_area_takes_the_mouse_and_every_piece_does() -> void:
	_each(func(board: String, key: String, scenario: String, m: Dictionary):
		var where := _where(board, key, scenario)
		var sweep: Dictionary = m.sweep
		assert_true(int(sweep.points) >= 300, "%s: the sweep covered the window (%d points)" % [where, sweep.points])
		assert_eq(sweep.violations, [], "%s: the mouse is over the board wherever no piece is, and over the piece wherever one is" % where)
		var hit: Dictionary = sweep.over_pieces
		if scenario == "rest":
			for piece in ["plaque", "opponent", "tray", "guide"]:
				assert_true(int(hit.get(piece, 0)) > 0, "%s: the sweep put the mouse over the %s" % [where, piece]))


func test_a_click_on_empty_hud_space_picks_the_province_under_it_on_both_boards() -> void:
	_each(func(board: String, key: String, scenario: String, m: Dictionary):
		if scenario != "rest":
			return
		var where := _where(board, key, scenario)
		var picks: Array = m.clicks.picks
		assert_true(picks.size() >= 4, "%s: the probe clicked empty HUD space over land %d times" % [where, picks.size()])
		for p in picks:
			assert_eq(p.got, p.want, "%s: a click at %s picks %s (it picked %s)" % [where, p.at, p.want, p.got]))


func test_each_piece_eats_its_own_click_and_the_board_never_sees_it() -> void:
	_each(func(board: String, key: String, scenario: String, m: Dictionary):
		if scenario != "rest":
			return
		var where := _where(board, key, scenario)
		var eaten: Array = m.clicks.eaten
		var pieces := eaten.map(func(e): return e.piece)
		for piece in ["plaque", "opponent", "tray", "seal", "card"]:
			assert_true(pieces.has(piece), "%s: the probe clicked the %s" % [where, piece])
		for e in eaten:
			assert_eq(e.selected, e.capital, "%s: a click on the %s (over %s) left the selection alone" % [where, e.piece, e.land])
			assert_eq(e.army, "", "%s: and selected no army" % where)
			assert_eq(int(e.turns), 0, "%s: and ended no turn" % where))
