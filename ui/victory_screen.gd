class_name VictoryScreen
extends Control
## End-of-game screen (#8): who won (or that it is a draw), the plain-language summary, and the game in
## numbers: turns played, battles fought, provinces each faction holds and the capitals captured.
## Shows GameSession.victory() (VictoryCheck.summary) and never changes rules state. Every number has
## a tooltip; explanations come from RulesCodex ("victory", "simultaneous_capture", "capture"), and each
## tooltip ends with its codex entry: right-click (or F1) emits codex_requested(key) for the host.
## Seat colours come from UiPalette.seat_color: Player 1 Vermilion, Player 2 Cobalt, whatever faction.
## Builds its children in code, so it works before it is in the tree (headless tests).
##
## API:
##   show_for(session) -> bool    shows session.victory(); false (and hidden) while the game runs
##   show_victory(victory, state = null, players = [])
##       victory  GameSession.victory() / VictoryCheck.summary()
##       state    the final GameState: display names, and the provinces listed in the tooltips.
##                Without it, names come from the faction and map data.
##       players  faction ids in seat order: row order and seat colours. Without it, the order of
##                victory.provinces_held (which VictoryCheck fills in seat order).
##   signal new_game_requested   the "New game" button
##   signal title_requested      the "Back to title" button
##   signal codex_requested(key) a linked number or line was right-clicked (or F1)
##   add_action(name, text, tooltip) -> Button   a smaller button in a row above New game, for the
##                               host's own actions (the game screen's "Final turn report", "View the map")

signal new_game_requested
signal title_requested
signal codex_requested(key: String)

const BACKGROUND := Color("#14131F")  # a shade under UiPalette.PANEL_BG, so the screen reads as a full page

var victory := {}
var caption_label: Label
var headline_label: Label
var seat_label: Label
var summary_label: Label
var turns_label: Label
var battles_label: Label
var provinces_box: VBoxContainer
var captures_box: VBoxContainer
var captures_heading: Label
var new_game_button: Button
var title_button: Button
var actions_row: HBoxContainer  # add_action() buttons; hidden while empty
var _province_labels: Array[Label] = []
var _capture_labels: Array[Label] = []


func _init() -> void:
	name = "VictoryScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


## Shows the session's victory summary. Returns false, and stays hidden, while the game is running.
func show_for(session: GameSession) -> bool:
	if session == null or not session.is_over():
		visible = false
		return false
	show_victory(session.victory(), session.state(), session.players())
	return true


## Shows a victory summary dictionary (see GameSession.victory()).
func show_victory(summary: Dictionary, state: GameState = null, players: Array = []) -> void:
	victory = summary.duplicate(true)
	var is_draw: bool = summary.get("draw", false)
	var winner := String(summary.get("winner", ""))
	var held: Dictionary = summary.get("provinces_held", {})
	var seats: Array = players.duplicate() if not players.is_empty() else held.keys()
	var entry_key := "simultaneous_capture" if is_draw else "victory"
	var rule := RulesCodex.entry(entry_key)
	var rule_tip := TooltipText.plain(String(rule.get("title", "")), String(rule.get("text", "")))
	var turn := int(summary.get("turn", 0))

	var rule_kind := "draw" if is_draw else "game_over"
	caption_label.text = "Game over on turn %d" % turn
	caption_label.tooltip_text = TooltipText.plain("Game over", "The game ended when turn %d finished resolving. %s" % [turn, rule.get("text", "")])
	_link(caption_label, rule_kind)
	var seat := seats.find(winner)
	if is_draw:
		headline_label.text = "It's a draw"
		headline_label.add_theme_color_override("font_color", UiPalette.GILT)
		seat_label.text = "Both capitals fell in the same turn, so nobody wins."
	else:
		headline_label.text = "%s wins" % _faction_name(winner, state)
		headline_label.add_theme_color_override("font_color", seat_color(seat).lightened(0.25))
		seat_label.text = "Player %d wins the game." % (seat + 1) if seat >= 0 else ""
	seat_label.visible = not seat_label.text.is_empty()
	headline_label.tooltip_text = rule_tip
	seat_label.tooltip_text = rule_tip
	summary_label.text = String(summary.get("text", ""))
	summary_label.tooltip_text = TooltipText.plain("How the game ended", String(rule.get("text", "")))
	for l in [headline_label, seat_label, summary_label]:
		_link(l, rule_kind)

	var turns := int(summary.get("turns_played", 0))
	turns_label.text = "Turns played: %d" % turns
	turns_label.tooltip_text = TooltipText.plain("Turns played: %d" % turns,
		"How many turns were resolved in this game, counting the last one. A turn resolves once every player has ended theirs. %s" % RulesCodex.text("hotseat"))
	_link(turns_label, "turns_played")
	var battles := int(summary.get("battles", 0))
	battles_label.text = "Battles fought: %d" % battles
	battles_label.tooltip_text = TooltipText.plain("Battles fought: %d" % battles,
		"Every battle in the whole game, including border battles between armies that swapped places. %s" % RulesCodex.text("battle_rounds"))
	_link(battles_label, "battles")

	_clear(provinces_box, _province_labels)
	for i in seats.size():
		var fid := String(seats[i])
		var count := int(held.get(fid, 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(seat_emblem(i))
		var l := _label("%s: %s" % [_faction_name(fid, state), TooltipText.count(count, "province")], 22,
			seat_color(i).lightened(0.3))
		l.tooltip_text = _provinces_tooltip(fid, count, state)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		_link(l, "provinces_held")
		row.add_child(l)
		provinces_box.add_child(row)
		_province_labels.append(l)

	_clear(captures_box, _capture_labels)
	var capture_tip := TooltipText.plain(String(RulesCodex.entry("capture").get("title", "")), "%s %s" % [RulesCodex.text("capture"), rule.get("text", "")])
	for c in summary.get("captures", []):
		var l := _label("%s captured %s, the %s capital." % [_faction_name(String(c.get("captor", "")), state),
			_province_name(String(c.get("capital", "")), state), _faction_name(String(c.get("of", "")), state)], 20, UiPalette.TEXT_PRIMARY)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.tooltip_text = capture_tip
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		_link(l, "captures")
		captures_box.add_child(l)
		_capture_labels.append(l)
	captures_box.visible = not _capture_labels.is_empty()
	captures_heading.visible = captures_box.visible
	visible = true
	if is_inside_tree():
		new_game_button.grab_focus.call_deferred()


## Adds a smaller button for the host's own action in a row above "New game". Returns it so the host
## can connect `pressed`.
func add_action(node_name: String, text: String, tooltip: String) -> Button:
	var b := _button(node_name, text, tooltip)
	b.custom_minimum_size = Vector2(220, 44)
	b.add_theme_font_size_override("font_size", 20)
	actions_row.add_child(b)
	actions_row.visible = true
	return b


## One label per faction in the provinces-held list, in row order.
func province_labels() -> Array[Label]:
	return _province_labels


## One label per captured capital.
func capture_labels() -> Array[Label]:
	return _capture_labels


## "Provinces held" as a breakdown: one line per province the faction owns in `state`, totalling the
## count from the victory summary. Without a state, a plain explanation.
func _provinces_tooltip(fid: String, count: int, state: GameState) -> String:
	var description := "How many provinces %s owned when the game ended. Provinces change hands by capture. %s" % [
		_faction_name(fid, state), RulesCodex.text("capture")]
	if state == null:
		return TooltipText.plain("Provinces held: %d" % count, description)
	var lines := []
	for p in state.provinces:
		if p.owner == fid:
			lines.append({"label": p.name, "value": 1, "note": "capital" if p.is_capital else ""})
	return TooltipText.from_breakdown({"title": "Provinces held by %s" % _faction_name(fid, state),
		"description": description, "lines": lines, "total_label": "Provinces held", "total": count})


func _on_new_game_pressed() -> void:
	new_game_requested.emit()


func _on_title_pressed() -> void:
	title_requested.emit()


# --- names and colours ----------------------------------------------------------------------------

static func _faction_name(fid: String, state: GameState) -> String:
	if state != null:
		var f := state.find_faction(fid)
		if f != null:
			return f.faction_name
	for f in FactionData.FACTIONS:
		if f.id == fid:
			return f.name
	return "An unknown faction"


static func _province_name(pid: String, state: GameState) -> String:
	if state != null:
		var p := state.find_province(pid)
		if p != null:
			return p.name
	for p in MapData.PROVINCES:
		if p.id == pid:
			return p.name
	return "a province"


## The seat's player colour (UiPalette.seat_color, the one source of player colours).
static func seat_color(seat_index: int) -> Color:
	return UiPalette.seat_color(seat_index)


## The seat's emblem from design/STYLE_BIBLE.md 1.1 (P1 circle, P2 square, P3 triangle, P4 diamond),
## drawn in the seat colour with an ink keyline and a light halo.
static func seat_emblem(seat_index: int) -> Control:
	var c := Control.new()
	c.name = "SeatEmblem"
	c.custom_minimum_size = Vector2(24, 24)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func(): _draw_emblem(c, seat_index))
	return c


static func _draw_emblem(c: Control, seat_index: int) -> void:
	var center := c.size * 0.5
	var r := minf(c.size.x, c.size.y) * 0.5 - 2.0
	var fill := seat_color(seat_index)
	var layers := [[r + 2.0, UiPalette.KEYLINE_HALO], [r + 1.0, UiPalette.KEYLINE_INK], [r, fill]]
	for layer in layers:
		var radius: float = layer[0]
		var color: Color = layer[1]
		match seat_index % 4:
			0:
				c.draw_circle(center, radius, color)
			1:
				c.draw_rect(Rect2(center - Vector2(radius, radius) * 0.85, Vector2(radius, radius) * 1.7), color)
			2:
				c.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius, radius * 0.8),
					center + Vector2(-radius, radius * 0.8)]), color)
			3:
				c.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius, 0),
					center + Vector2(0, radius), center + Vector2(-radius, 0)]), color)


# --- nodes ----------------------------------------------------------------------------------------

## Links a label to the codex entry for its kind of number (TooltipText.CODEX).
func _link(l: Control, kind: String) -> void:
	CodexLink.attach(l, TooltipText.codex_for(kind), codex_requested.emit)


func _clear(box: Container, list: Array[Label]) -> void:
	list.clear()
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _heading(text: String, tooltip: String) -> Label:
	var l := _label(text, 26, UiPalette.GILT)
	l.tooltip_text = tooltip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


func _build() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.color = BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_BG
	style.border_color = UiPalette.GILT
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(36)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.custom_minimum_size = Vector2(860, 0)
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	caption_label = _label("Game over", 22, UiPalette.TEXT_SECONDARY)
	caption_label.name = "CaptionLabel"
	caption_label.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(caption_label)
	headline_label = _label("", 60, UiPalette.GILT)
	headline_label.name = "HeadlineLabel"
	headline_label.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(headline_label)
	seat_label = _label("", 24, UiPalette.TEXT_PRIMARY)
	seat_label.name = "SeatLabel"
	seat_label.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(seat_label)
	summary_label = _label("", 20, UiPalette.TEXT_SECONDARY)
	summary_label.name = "SummaryLabel"
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_label.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(summary_label)

	var stats := HBoxContainer.new()
	stats.name = "Stats"
	stats.add_theme_constant_override("separation", 48)
	box.add_child(stats)
	turns_label = _label("", 26, UiPalette.TEXT_PRIMARY)
	turns_label.name = "TurnsLabel"
	turns_label.mouse_filter = Control.MOUSE_FILTER_PASS
	stats.add_child(turns_label)
	battles_label = _label("", 26, UiPalette.TEXT_PRIMARY)
	battles_label.name = "BattlesLabel"
	battles_label.mouse_filter = Control.MOUSE_FILTER_PASS
	stats.add_child(battles_label)

	box.add_child(_heading("Provinces held", TooltipText.plain("Provinces held",
		"How many provinces each side owned when the game ended. Hover a line to see which ones.")))
	provinces_box = VBoxContainer.new()
	provinces_box.name = "Provinces"
	provinces_box.add_theme_constant_override("separation", 6)
	box.add_child(provinces_box)

	captures_box = VBoxContainer.new()
	captures_box.name = "Captures"
	captures_box.add_theme_constant_override("separation", 6)
	box.add_child(captures_box)
	captures_heading = _heading("Capitals captured", TooltipText.plain(String(RulesCodex.entry("victory").get("title", "")), RulesCodex.text("victory")))
	captures_heading.name = "CapturesHeading"
	box.add_child(captures_heading)
	box.move_child(captures_heading, captures_box.get_index())

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	box.add_child(spacer)
	actions_row = HBoxContainer.new()
	actions_row.name = "Actions"
	actions_row.add_theme_constant_override("separation", 16)
	actions_row.alignment = BoxContainer.ALIGNMENT_CENTER
	actions_row.visible = false
	box.add_child(actions_row)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 20)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	new_game_button = _button("NewGameButton", "New game", "Set up a new game: choose who plays which faction, and a seed.")
	new_game_button.pressed.connect(_on_new_game_pressed)
	buttons.add_child(new_game_button)
	title_button = _button("TitleButton", "Back to title", "Leave this game and go back to the title screen.")
	title_button.pressed.connect(_on_title_pressed)
	buttons.add_child(title_button)


func _button(node_name: String, text: String, tooltip: String) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(240, 56)
	b.add_theme_font_size_override("font_size", 24)
	return b
