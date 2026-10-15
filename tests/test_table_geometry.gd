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
##   * the states themselves: the card, the guide, a notice, the forecast, the playback bar and its caption and the
##     fortress chip each show where they should, and the 2D map fits the framing area.

const PROBE := "res://tests/table_probe.gd"
const SCRATCH := "user://table_probe"
const BOARDS := ["3d", "2d"]
## The spec's three sizes: key -> the logical size the game lays out for.
const SIZES := {"1600x900": Vector2(1600, 900), "1600x900@125": Vector2(1280, 720), "1280x720": Vector2(1600, 900)}
const SCENARIOS := ["rest", "dismissed", "notice", "forecast", "army", "recruit", "march", "army_notice", "notices", "chronicle"]
const FLOATING := ["card", "notice", "guide", "hover", "playback", "caption", "closeup"]
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
			assert_false(_shown(m, "notice") or _shown(m, "hover"), "%s: no notice or forecast" % where)
		"dismissed":
			assert_false(_shown(m, "card"), "%s: the closed card is gone" % where)
			assert_true(_shown(m, "guide"), "%s: the guide stays" % where)
		"notice":
			assert_true(_shown(m, "notice") and _shown(m, "guide") and _shown(m, "card"), "%s: the notice, the guide and the card together" % where)
		"forecast":
			assert_true(_shown(m, "card"), "%s: the army's card" % where)
			var fc: Array = m.card_parts.get("forecast", [])
			assert_true(fc.size() == 5 and bool(fc[4]), "%s: the hovered destination's forecast shows (in the card's forecast slot, not over the board)" % where)
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
		"notices":
			assert_true(_shown(m, "notices"), "%s: the medallion stack is lit with the turn's news" % where)
			assert_false(_shown(m, "chronicle"), "%s: the column is shut" % where)
		"chronicle":
			assert_true(_shown(m, "chronicle") and _shown(m, "notices"), "%s: the column is open beside the medallions" % where)
			assert_true(_shown(m, "card") and _shown(m, "guide"), "%s: and the card and the guide give way, they do not vanish" % where)


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
## UI-FIT (#237): on the 3D board, the selected province itself ends in the framing area (the camera glides it there), never under the card.
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
				if row.size() > 7:  # UI-FIT (#237): on the 3D board the selected province ends in the framing area, never under the card
					var framing := Rect2(m.framing[0], m.framing[1], m.framing[2], m.framing[3])
					var at := Vector2(row[7][0], row[7][1])
					assert_true(framing.grow(1.0).has_point(at), "%s: the province is in view in the framing area (%s in %s)" % [what, at, framing])
					assert_false(r.has_point(at), "%s: and not under the card" % what)
				counted.n += 1)
	var expected: int = SIZES.size() * 3 * 16  # three sizes; the 3D board's two zooms and the 2D map's one; at least 16 selections each
	assert_true(counted.n >= expected, "cards were measured for every province and army (%d of at least %d)" % [counted.n, expected])


# --- the Chronicle's pieces (UX-6, design/UX_WAR_TABLE.md §1.3, §5) -----------------------------------------

## The medallion stack stays in its 80 px slot at every size, shows at most six medallions below 1600 logical and "+N" for the rest, and
## sits clear of the card, the guide and the plaques; the open column takes its band on the right (420 px, 360 px below 1600 logical) and
## the plaques, the tray and the seal keep to the board's side of it; the markers are on the board where their cards' provinces are.
func test_the_medallion_stack_stays_in_its_slot_and_shows_at_most_six_below_1600() -> void:
	var checked := [0]
	_each(func(board: String, key: String, scenario: String, m: Dictionary):
		if scenario != "notices" and scenario != "chronicle":
			return
		var where := _where(board, key, scenario)
		var vp := _viewport(m)
		var slot := _rect(m, "stack")
		var stack := _rect(m, "notices")
		assert_true(slot.grow(0.5).encloses(stack), "%s: the stack is inside its 80 px slot (%s in %s)" % [where, stack, slot])
		var parts: Dictionary = m.chronicle
		assert_true(int(parts.total) > 6, "%s: the turn had more news than six (%d)" % [where, parts.total])
		var shown: int = (parts.medallions as Array).size()
		assert_true(shown >= 1, "%s: medallions are drawn" % where)
		if vp.x < TableLayout.WIDE_FROM:
			assert_true(shown <= NoticeStack.MAX_COMPACT, "%s: at most six below 1600 logical (%d)" % [where, shown])
			assert_eq(shown, 6, "%s: and six fit" % where)
		for r in parts.medallions:
			var rect := Rect2(r[0], r[1], r[2], r[3])
			assert_true(stack.grow(0.5).encloses(rect), "%s: a medallion is inside the stack" % where)
			assert_true(rect.size.x <= NoticeMedallion.SIZE_STACK + 0.5, "%s: no wider than its slot allows" % where)
		var more: Array = parts.more
		assert_eq(bool(more[4]), int(parts.total) > shown, "%s: '+N' shows exactly when some medallions did not fit" % where)
		if _shown(m, "card"):
			assert_false(TableLayout.overlaps(stack, _rect(m, "card")), "%s: the stack never covers the selection card" % where)
		checked[0] += 1)
	assert_true(checked[0] >= 12, "the stack was measured in both states, at three sizes, on both boards (%d)" % checked[0])


func test_the_open_chronicle_has_its_band_and_everything_gives_way() -> void:
	var checked := [0]
	_each(func(board: String, key: String, scenario: String, m: Dictionary):
		if scenario != "chronicle":
			return
		var where := _where(board, key, scenario)
		var vp := _viewport(m)
		var band: Rect2 = TableLayout.bands(vp, true)["chronicle"]
		var column := _rect(m, "chronicle")
		assert_eq(column.size.x, TableLayout.chronicle_width(vp), "%s: 420 px wide, 360 below 1600 logical" % where)
		assert_true(is_equal_approx(column.position.x, band.position.x) and column.size.y == vp.y, "%s: it takes its whole band (%s)" % [where, column])
		var safe := Rect2(m.safe[0], m.safe[1], m.safe[2], m.safe[3])
		assert_eq(safe, TableLayout.safe_area(vp, true), "%s: the safe area narrowed to make room" % where)
		for name in m.pieces.keys():
			if name == "chronicle" or not _shown(m, name):
				continue
			assert_false(TableLayout.overlaps(_rect(m, name), column), "%s: %s gives way to the column (%s against %s)" % [where, name, _rect(m, name), column])
		for name in FLOATING:
			if _shown(m, name):
				assert_true(safe.grow(0.5).encloses(_rect(m, name)), "%s: %s is inside the narrowed safe area" % [where, name])
		var parts: Dictionary = m.chronicle
		assert_true(int(parts.cards) >= 5, "%s: the column lists the turn's cards (%d)" % [where, parts.cards])
		# A marker for each card with a province, numbered 1, 2, 3 ..., on the board and under none of the HUD's pieces.
		var numbers := []
		for id in parts.markers:
			var r: Array = parts.markers[id]
			numbers.append(int(r[0]))
			if bool(r[5]):
				var rect := Rect2(r[1], r[2], r[3], r[4])
				assert_true(Rect2(Vector2.ZERO, vp).grow(0.5).encloses(rect), "%s: a marker is on the screen" % where)
		numbers.sort()
		assert_true(numbers.size() >= 3, "%s: markers on the board (%d)" % [where, numbers.size()])
		assert_eq(numbers, range(1, numbers.size() + 1), "%s: numbered 1, 2, 3 like the cards" % where)
		checked[0] += 1)
	assert_true(checked[0] >= 6, "the open column was measured at three sizes on both boards (%d)" % checked[0])


func test_a_click_on_the_stack_or_the_column_is_eaten_and_never_reaches_the_board() -> void:
	var checked := [0]
	_each(func(board: String, key: String, scenario: String, m: Dictionary):
		if scenario != "notices" and scenario != "chronicle":
			return
		var where := _where(board, key, scenario)
		var clicks: Array = m.chronicle_clicks
		var pieces := clicks.map(func(c): return String(c.piece))
		assert_true(pieces.has("notices"), "%s: the probe clicked the stack" % where)
		if scenario == "chronicle":
			assert_true(pieces.has("chronicle"), "%s: and the column" % where)
		for c in clicks:
			assert_eq(c.selected, c.capital, "%s: a click on the %s (over %s) left the selection alone" % [where, c.piece, c.land])
			assert_eq(c.army, "", "%s: and selected no army" % where)
			assert_eq(int(c.turns), 0, "%s: and ended no turn" % where)
			checked[0] += 1)
	assert_true(checked[0] >= 18, "clicks were eaten at every size on both boards (%d)" % checked[0])


# --- overlap and the bands --------------------------------------------------------------------------

func test_no_two_hud_pieces_overlap_in_any_state_at_any_size_on_either_board() -> void:
	_each(func(board: String, key: String, scenario: String, m: Dictionary):
		var where := _where(board, key, scenario)
		var names: Array = m.pieces.keys().filter(func(n): return _shown(m, n))
		assert_true(names.size() >= 14, "%s: the pieces were found (%d)" % [where, names.size()])
		for i in names.size():
			for j in range(i + 1, names.size()):
				if [names[i], names[j]].has("stack") and [names[i], names[j]].has("notices"):
					continue  # the stack slot is the area the medallions are drawn in (checked inside it below)
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
		assert_eq(safe, TableLayout.safe_area(vp, scenario == "chronicle"), "%s: the safe area is the layout's (narrowed by the open Chronicle)" % where)
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
			var board_side := vp.x - (TableLayout.chronicle_width(vp) if scenario == "chronicle" else 0.0)
			assert_true(_rect(m, name).position.x > board_side * 0.5 and _rect(m, name).end.x <= board_side + 0.5, "%s: and sits on the right of the board's side (%s)" % [where, board_side])
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
				# UI-FIT (#237): with the Chronicle open too (at 125% the framing used to reach 48 px under the card, over the capital)
				assert_true(r.end.x <= framing.position.x, "%s: and ends left of the framing area (%d against %d)" % [where, r.end.x, framing.position.x])
		for i in range(1, column.size()):
			assert_true((column[i] as Rect2).position.y >= (column[i - 1] as Rect2).end.y, "%s: each is under the one above it" % where)
		if _shown(m, "card"):
			assert_true(is_equal_approx(_rect(m, "card").end.y, safe.end.y - TableLayout.GAP), "%s: the card is docked at the bottom" % where)
		if _shown(m, "guide"):
			assert_eq(_rect(m, "guide").position.y, _rect(m, "notice").end.y + TableLayout.GAP if _shown(m, "notice") else safe.position.y + TableLayout.GAP, "%s: the guide hangs under the realm plaque (or the notice)" % where))


## UI-FIT (#237): the province card at the capital (the state at rest: a tall card, the guide up) at every size on both boards. At 125%
## it showed four lines under the whole guide, and at every size the scroll's edge cut its last line with nothing to say there was more.
## The card outranks the guide (§1.3), so the guide folds for it exactly when the card asks for more than the column leaves under the
## whole guide; the card shows its name and its facts down to the fort whole; nothing is cut at the scroll's top; and a line the bottom
## edge cuts has the fade and "More" over it, inside the card.
func test_the_province_card_shows_its_facts_and_never_cuts_a_line_unsaid() -> void:
	var checked := [0]
	_each(func(board: String, key: String, scenario: String, m: Dictionary):
		if scenario != "rest":
			return
		var where := _where(board, key, scenario)
		var parts: Dictionary = m.card_parts
		var safe := Rect2(m.safe[0], m.safe[1], m.safe[2], m.safe[3])
		var gap := TableLayout.GAP
		assert_true(absf(float(parts.guide_unfolded) - float(parts.guide_unfolded_real)) < 0.5, "%s: the folded guide knows its unfolded height (%d, %d)" % [where, parts.guide_unfolded, parts.guide_unfolded_real])
		var wanted := minf(float(parts.desired), safe.size.y - 2.0 * gap)
		var under_whole_guide := safe.size.y - 3.0 * gap - float(parts.guide_unfolded)
		assert_eq(bool(parts.guide_folded), wanted > under_whole_guide + 0.5, "%s: the guide folds only for a card that needs the room (it asks %d, the whole guide leaves %d)" % [where, wanted, under_whole_guide])
		var scroll := Rect2(parts.scroll[0], parts.scroll[1], parts.scroll[2], parts.scroll[3])
		var whole := []
		var cut := []
		for line in parts.lines:
			var r := Rect2(line[1], line[2], line[3], line[4])
			if scroll.grow(0.5).encloses(r):
				whole.append(String(line[0]))
			elif r.position.y < scroll.end.y - 0.5 and r.end.y > scroll.end.y + 0.5:
				cut.append(String(line[0]))
			assert_false(r.position.y < scroll.position.y - 0.5 and r.end.y > scroll.position.y + 0.5, "%s: at rest no line is cut at the top (%s)" % [where, line[0]])
		for name in ["ProvinceName", "OwnerLabel", "TerrainLabel", "IncomeLabel", "CapitalLabel", "FortLabel"]:
			assert_true(whole.has(name), "%s: %s is wholly in view (%s)" % [where, name, whole])
		if not cut.is_empty():
			assert_true(bool(parts.more), "%s: the lines the edge cuts (%s) have the fade and More over them" % [where, cut])
		if bool(parts.more):
			var b: Array = parts.more_button
			var more := Rect2(b[0], b[1], b[2], b[3])
			assert_true(bool(b[4]) and _rect(m, "card").grow(0.5).encloses(more), "%s: More is shown inside the card (%s)" % [where, more])
			assert_true(more.end.y <= scroll.end.y + 0.5 and more.position.y >= scroll.end.y - ScrollMore.FADE_H - 0.5, "%s: at the scroll's bottom edge" % where)
		checked[0] += 1)
	assert_eq(checked[0], BOARDS.size() * SIZES.size(), "both boards at the three sizes")


## UI-FIT (#237): the board's own text at 125%. The plates' names ran into each other ("Blackwo⊙ E 3 eak") with the map framed small (the
## Chronicle open), and the 2D map's text drew at 7 px. In every state at every size on both boards: no two province names that show
## overlap; on the 3D board a plate that had no room is folded to its emblem, its name in its tooltip, and the selected province's never
## is; on the 2D map every text on a plate draws at the 12 px floor or more, in the window's own pixels.
func test_the_board_names_never_overlap_and_the_2d_text_keeps_the_floor() -> void:
	var counts := {"names": 0, "folded": 0, "smallest": 0}
	_each(func(board: String, key: String, scenario: String, m: Dictionary):
		var where := _where(board, key, scenario)
		var text: Dictionary = m.board_text
		var shown := []
		for id in text.names:
			var r: Array = text.names[id]
			if bool(r[4]):
				shown.append([id, Rect2(r[0], r[1], r[2], r[3])])
			if bool(r[5]):
				counts.folded += 1
				assert_true(String(text.tooltips.get(id, "")).contains(_province_name(id)), "%s: folded %s keeps its name in its tooltip" % [where, id])
				assert_ne(id, String(text.selected), "%s: the selected province's plate is never folded" % where)
		for i in shown.size():
			for j in range(i + 1, shown.size()):
				assert_false(TableLayout.overlaps(shown[i][1], shown[j][1]), "%s: %s's name (%s) and %s's (%s) overlap" % [where, shown[i][0], shown[i][1], shown[j][0], shown[j][1]])
		counts.names += shown.size()
		for id in text.smallest:
			var px := float(text.smallest[id])
			if px >= 0.0:
				assert_true(px >= UiPalette.SCREEN_FLOOR_PX - 0.05, "%s: %s's plate text draws at %.1f px, at least the floor" % [where, id, px])
				counts.smallest += 1)
	assert_true(counts.names > 0 and counts.smallest > 0, "names and 2D text were measured (%s)" % counts)


func _province_name(pid: String) -> String:
	var p := GameState.new(1).find_province(pid)
	return p.name if p != null else pid


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
		assert_eq(framing, TableLayout.framing_area(_viewport(m), scenario == "chronicle"), "%s: the framing area is the layout's" % where)
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
