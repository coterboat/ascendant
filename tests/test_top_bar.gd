extends "res://tests/test_case.gd"
## The map's top bar fits the 1600x900 window (project.godot's viewport) with nothing clipped: every
## label and button gets at least its minimum width, and the hint wraps into at most its two visible
## lines in the width that is left. After game over the gold label is hidden, so no gap is left.
##
## Headless tests run outside the tree, where containers don't lay out and theme overrides don't reach
## the controls' theme caches. So each control's theme is refreshed (NOTIFICATION_THEME_CHANGED) and
## the row is measured the way its HBoxContainer lays it out: the minimum widths of the visible
## children plus the separations, and whatever is left goes to the hint, which expands.

const GAME_SCENE := "res://ui/game_screen.tscn"
const WINDOW_WIDTH := 1600.0  # project.godot display/window/size/viewport_width


func test_top_bar_fits_at_1600_during_orders() -> void:
	# The Thornmane Clans have the longer name; try both seatings, with orders queued.
	for seats in [["beasts", "kingdom"], ["kingdom", "beasts"]]:
		var game := _game(seats)
		game.map.select_province(game.map.state.find_faction(seats[0]).capital)
		for i in 2:
			(game.map.details.find_children("Recruit_*", "Button", true, false)[0] as Button).pressed.emit()
		assert_true(game.end_turn_button.text.contains("2 orders"), game.end_turn_button.text)
		_assert_fits(game.map, "%s, orders" % [seats])
		# A rich late game: four-digit gold makes the gold label wider.
		var s := game.session.state()
		s.find_faction(seats[0]).gold = 9999
		game.map.set_state(s, seats[0])
		assert_true(game.map.gold_label.text.begins_with("Gold 9999"), game.map.gold_label.text)
		_assert_fits(game.map, "%s, 9999 gold" % [seats])
		game.free()


func test_hint_keeps_the_whole_help_in_its_tooltip() -> void:
	var game := _game(["beasts", "kingdom"])
	var hint := game.map.hint_label
	assert_eq(hint.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART, "the hint wraps instead of cutting off")
	assert_eq(hint.text_overrun_behavior, TextServer.OVERRUN_NO_TRIMMING, "no ellipsis")
	assert_eq(hint.max_lines_visible, 2)
	assert_ne(hint.mouse_filter, Control.MOUSE_FILTER_IGNORE, "it takes the mouse, so its tooltip shows")
	assert_true(hint.text.begins_with("Player 1 of 2: select an army"), hint.text)
	var tip := hint.tooltip_text.replace("\n", " ")
	for part in ["Player 1 of 2: Thornmane Clans gives orders", "neighboring province", "recruit", "F1", "End turn"]:
		assert_true(tip.contains(part), "the tooltip says '%s': %s" % [part, tip])
	game.free()


func test_after_game_over_the_bar_has_no_gap_where_gold_was() -> void:
	var game := _game(["kingdom", "beasts"])
	var map := game.map
	assert_true(map.gold_label.visible, "gold shows while a player gives orders")
	# The Aurel Crown marches up the northern road to Fangridge while the Thornmane army goes south.
	for step in [["westwatch", "bloodfen"], ["stonegate", "deepwood"], ["blackwood", "greenglade"], ["ebonpeak", "rivermarch"], ["fangridge", ""]]:
		assert_eq(game.session.queue_move("kingdom-1", step[0]), "")
		game.end_turn()
		game.handoff.ready_button.pressed.emit()
		if not String(step[1]).is_empty():
			assert_eq(game.session.queue_move("beasts-2", step[1]), "")
		game.end_turn()
		if game.session.is_over():
			break
		game.handoff.ready_button.pressed.emit()
	assert_true(game.session.is_over(), "Fangridge fell")
	assert_eq(map.faction_label.text, "Game over")
	assert_false(map.gold_label.visible, "no gold label (and no empty slot) once nobody is playing")
	assert_false(map.faction_emblem.visible, "and no player's emblem")
	assert_true(game.results_button.visible)
	var row := map.back_button.get_parent()
	for c in row.get_children():
		if c is Label and (c as Label).visible:
			assert_false((c as Label).text.strip_edges().is_empty(), "no visible empty label in the bar: %s" % c.name)
	assert_true(map.hint_label.text.begins_with("The game is over."), map.hint_label.text)
	_assert_fits(map, "game over")
	game.free()


func test_map_preview_top_bar_fits() -> void:
	var map: MapScreen = load("res://ui/map_screen.tscn").instantiate()
	map._ready()
	assert_true(map.gold_label.visible and map.faction_emblem.visible, "the preview is Player 1's view")
	_assert_fits(map, "map preview")
	map.free()


# --- measuring --------------------------------------------------------------------------------------

func _game(seats: Array) -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.start_game({"players": seats, "seed": 77})
	return game


## Lays the top bar out at WINDOW_WIDTH like its HBoxContainer and checks nothing is clipped.
func _assert_fits(map: MapScreen, where: String) -> void:
	_refresh_theme(map)
	var row := map.back_button.get_parent() as HBoxContainer
	var bar := row.get_parent() as PanelContainer
	var style := bar.get_theme_stylebox("panel")
	var available := WINDOW_WIDTH - style.get_margin(SIDE_LEFT) - style.get_margin(SIDE_RIGHT)
	var separation := row.get_theme_constant("separation")
	var used := 0.0
	var shown := 0
	for c in row.get_children():
		var control := c as Control
		if control == null or not control.visible:
			continue
		shown += 1
		if control != map.hint_label:
			used += _min_width(control)
	var hint_width := available - used - separation * (shown - 1)
	var hint := map.hint_label
	var lines := _wrapped_lines(hint, hint_width)
	assert_true(hint_width >= 300.0, "%s: the hint keeps a usable width (%d px)" % [where, hint_width])
	assert_true(lines <= hint.max_lines_visible, "%s: the hint fits in %d lines at %d px, it needs %d: %s" % [
		where, hint.max_lines_visible, hint_width, lines, hint.text])
	# Labels that don't wrap must get their whole text: their minimum width is the text's width.
	for label: Label in [map.faction_label, map.gold_label, map.turn_label]:
		if label.visible:
			var font: Font = label.get_theme_font("font")
			var text_width: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
			assert_true(label.get_minimum_size().x >= text_width - 0.5, "%s: '%s' asks for its whole text" % [where, label.text])
			assert_eq(label.text_overrun_behavior, TextServer.OVERRUN_NO_TRIMMING, "%s: '%s' is never trimmed" % [where, label.text])


## Minimum width an HBoxContainer gives `c`: the larger of its minimum size and custom minimum size;
## for a box, its visible children's widths plus its separations.
func _min_width(c: Control) -> float:
	if c is BoxContainer:
		var total := 0.0
		var n := 0
		for k in c.get_children():
			if k is Control and (k as Control).visible:
				total += _min_width(k)
				n += 1
		return maxf(c.custom_minimum_size.x, total + c.get_theme_constant("separation") * maxi(n - 1, 0))
	return maxf(c.custom_minimum_size.x, c.get_minimum_size().x)


## How many lines `label`'s text wraps to at `width`, the way AUTOWRAP_WORD_SMART breaks it.
func _wrapped_lines(label: Label, width: float) -> int:
	var paragraph := TextParagraph.new()
	paragraph.add_string(label.text, label.get_theme_font("font"), label.get_theme_font_size("font_size"))
	paragraph.width = width
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	return paragraph.get_line_count()


func _refresh_theme(n: Node) -> void:
	if n is Control:
		n.notification(Control.NOTIFICATION_THEME_CHANGED)
	for c in n.get_children():
		_refresh_theme(c)
