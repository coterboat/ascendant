class_name VictoryScreen
extends Control
## End-of-game screen (#8): who won (or that it is a draw), the plain-language summary, and the game in
## numbers: turns played, battles fought, provinces each faction holds and the capitals captured.
## Shows GameSession.victory() (VictoryCheck.summary) and never changes rules state. Every number has
## a tooltip; explanations come from RulesCodex ("victory", "simultaneous_capture", "capture"), and each
## tooltip ends with its codex entry: right-click (or F1) emits codex_requested(key) for the host.
## Seat colours come from UiPalette.seat_color: Player 1 Vermilion, Player 2 Cobalt, whatever faction.
## Builds its children in code, so it works before it is in the tree (headless tests).
## Art (#10): the winner's banner hangs large beside the headline (both banners, smaller, on a draw),
## and each faction's row in "Provinces held" flies its banner by its seat emblem.
##
## M3c S-3 (#101): in a game with forts and sieges, a "Forts and sieges" block gives each faction's forts built,
## sieges won and storms fought, from `siege_stats` (SiegeChronicle.stats(), which the game screen sets), each
## line explained on hover and linked to the codex.
##
## API:
##   show_for(session) -> bool    shows session.victory(); false (and hidden) while the game runs
##   show_victory(victory, state = null, players = [], computer_seats = {})
##       victory  GameSession.victory() / VictoryCheck.summary()
##       state    the final GameState: display names, and the provinces listed in the tooltips.
##                Without it, names come from the faction and map data.
##       players  faction ids in seat order: row order and seat colours. Without it, the order of
##                victory.provinces_held (which VictoryCheck fills in seat order).
##       computer_seats  GameSession.computer_seats() ({faction id: level}): each computer faction's
##                row gets its "Computer (Normal)" tag (#35), and the seat line says who won in
##                human-vs-computer terms.
##   computer_tag(faction_name, level, open_codex) -> Label   the tag itself, shared with the game
##                               screen's top bar and the turn report header
##   signal new_game_requested   the "New game" button
##   signal title_requested      the "Back to title" button
##   signal codex_requested(key) a linked number or line was right-clicked (or F1)
##   add_action(name, text, tooltip) -> Button   a smaller button in a row above New game, for the
##                               host's own actions (the game screen's "Final turn report", "View the map")

signal new_game_requested
signal title_requested
signal codex_requested(key: String)

const BACKGROUND := Color("#14131F")  # a shade under UiPalette.PANEL_BG, so the screen reads as a full page
## The winner's banner (STYLE_BIBLE.md 2.1: 192 px tall in panels), and each banner on a draw.
const WINNER_BANNER_HEIGHT := 210.0
const DRAW_BANNER_HEIGHT := 150.0
const ROW_BANNER_HEIGHT := 40.0

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
var banner_box: HBoxContainer  # the winner's banner (both on a draw), left of the headline
var _province_labels: Array[Label] = []
var _capture_labels: Array[Label] = []
var paths_heading: Label  # M4-4: "Paths taken", only in a game with paths
var paths_box: VBoxContainer
var _path_labels: Array[Label] = []
## M3c S-3: {faction id: {"forts_built", "sieges_won", "storms"}} (SiegeChronicle.stats()); the host sets it.
var siege_stats := {}
var sieges_heading: Label
var sieges_box: VBoxContainer
var _siege_labels: Array[Label] = []


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
	show_victory(session.victory(), session.state(), session.players(), session.computer_seats())
	return true


## Shows a victory summary dictionary (see GameSession.victory()).
func show_victory(summary: Dictionary, state: GameState = null, players: Array = [], computer_seats: Dictionary = {}) -> void:
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
	_clear_banners()
	for fid in (seats if is_draw else [winner]):
		var b := Art.banner_card(String(fid), DRAW_BANNER_HEIGHT if is_draw else WINNER_BANNER_HEIGHT)
		b.name = "Banner_%s" % String(fid).validate_node_name()
		banner_box.add_child(b)
	banner_box.visible = banner_box.get_child_count() > 0
	if is_draw:
		headline_label.text = "It's a draw"
		headline_label.add_theme_color_override("font_color", UiPalette.GILT)
		seat_label.text = "Both capitals fell in the same turn, so nobody wins."
	else:
		headline_label.text = "%s wins" % _faction_name(winner, state)
		headline_label.add_theme_color_override("font_color", seat_color(seat).lightened(0.25))
		seat_label.text = "Player %d wins the game." % (seat + 1) if seat >= 0 else ""
		if seat >= 0 and not computer_seats.is_empty():
			seat_label.text = _computer_game_line(winner, seat, seats, computer_seats)
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
		"Every battle in the whole game, including border battles between armies that tried to swap places. %s" % RulesCodex.text("battle_rounds"))
	_link(battles_label, "battles")

	_clear(provinces_box, _province_labels)
	for i in seats.size():
		var fid := String(seats[i])
		var count := int(held.get(fid, 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var row_banner := Art.banner_card(fid, ROW_BANNER_HEIGHT)
		row_banner.name = "RowBanner"
		row.add_child(row_banner)
		row.add_child(seat_emblem(i))
		var l := _label("%s: %s" % [_faction_name(fid, state), TooltipText.count(count, "province")], 22,
			seat_color(i).lightened(0.3))
		l.tooltip_text = _provinces_tooltip(fid, count, state)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		_link(l, "provinces_held")
		row.add_child(l)
		if computer_seats.has(fid):
			row.add_child(computer_tag(_faction_name(fid, state), String(computer_seats[fid]), codex_requested.emit))
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
	# M4-4 (design/M4_ASCENSION.md §9.1): each faction's path, the nodes in the order taken, with turns.
	_clear(paths_box, _path_labels)
	for line in (PathView.victory_lines(state) if state != null else []):
		var l := _label(String(line.text), 15, UiPalette.TEXT_PRIMARY)
		l.name = "Path_%s" % String(line.faction).validate_node_name()
		l.custom_minimum_size = Vector2(380, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.tooltip_text = String(line.tooltip)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		CodexLink.attach(l, "path", codex_requested.emit)
		paths_box.add_child(l)
		_path_labels.append(l)
	paths_box.visible = not _path_labels.is_empty()
	paths_heading.visible = paths_box.visible
	_show_siege_stats(state, seats)  # M3c S-3
	visible = true
	if is_inside_tree():
		new_game_button.grab_focus.call_deferred()


## M3c S-3: each faction's forts built, sieges won and storms, in a game with sieges.
func _show_siege_stats(state: GameState, seats: Array) -> void:
	_clear(sieges_box, _siege_labels)
	var on := state != null and state.sieges
	sieges_box.visible = on
	sieges_heading.visible = on
	if not on:
		return
	for i in seats.size():
		var fid := String(seats[i])
		var st: Dictionary = siege_stats.get(fid, {})
		var built := int(st.get("forts_built", 0))
		var won := int(st.get("sieges_won", 0))
		var storms := int(st.get("storms", 0))
		var name := _faction_name(fid, state)
		var l := _label("%s: %s, %s, %s" % [name, TooltipText.count(built, "fort built", "forts built"),
			TooltipText.count(won, "siege won", "sieges won"), TooltipText.count(storms, "storm")], 19, seat_color(i).lightened(0.3))
		l.name = "Sieges_%s" % fid.validate_node_name()
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		var b := {"title": "%s: forts and sieges" % name,
			"description": "Forts built counts every fort level the %s finished (a palisade, or a keep). A siege is won by the besiegers when the fort falls to them, and by the fort's owner when the siege lines are destroyed (a sally, a relief, or a storm that failed). Storms count the storms the %s fought. %s" % [
				name, name, RulesCodex.text("siege")],
			"lines": [{"label": "Forts built", "value": built, "note": ""}, {"label": "Sieges won", "value": won, "note": ""},
				{"label": "Storms fought", "value": storms, "note": ""}],
			"total_label": "Siege deeds", "total": built + won + storms}
		l.tooltip_text = TooltipText.from_breakdown(b)
		CodexLink.attach(l, "siege", codex_requested.emit)
		sieges_box.add_child(l)
		_siege_labels.append(l)


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


## The seat line of a game with a computer seat: "You beat the computer (Normal)." when the only person
## won, "The computer (Normal) wins the game." when a computer seat did.
static func _computer_game_line(winner: String, seat: int, seats: Array, computer_seats: Dictionary) -> String:
	if computer_seats.has(winner):
		return "Player %d, the computer (%s), wins the game." % [seat + 1, AISeat.level_name(String(computer_seats[winner]))]
	var humans := seats.filter(func(fid): return not computer_seats.has(fid))
	if humans.size() == 1:
		var levels := []
		for fid in seats:
			if computer_seats.has(fid):
				levels.append(AISeat.level_name(String(computer_seats[fid])))
		return "You beat the computer (%s)." % ", ".join(levels)
	return "Player %d wins the game." % (seat + 1)


## The small "Computer (Normal)" tag shown next to a computer faction (#35): a chip in the panel style.
## Its tooltip says who plays the seat and how, and links to the codex entry "computer_opponent";
## `open_codex` gets the key on a right-click (or F1, through the host).
static func computer_tag(faction_name: String, level: String, open_codex: Callable = Callable()) -> Label:
	var tag := Label.new()
	tag.name = "ComputerTag"
	tag.text = AISeat.tag_text(level)
	tag.add_theme_font_size_override("font_size", 15)
	tag.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var chip := StyleBoxFlat.new()
	chip.bg_color = UiPalette.PANEL_RAISED
	chip.border_color = UiPalette.PANEL_BORDER
	chip.set_border_width_all(1)
	chip.set_corner_radius_all(10)
	chip.content_margin_left = 9
	chip.content_margin_right = 9
	chip.content_margin_top = 2
	chip.content_margin_bottom = 3
	tag.add_theme_stylebox_override("normal", chip)
	tag.mouse_filter = Control.MOUSE_FILTER_PASS
	tag.tooltip_text = TooltipText.plain(tag.text, AISeat.tag_help(faction_name, level))
	if open_codex.is_valid():
		CodexLink.attach(tag, "computer_opponent", open_codex)
	else:
		tag.tooltip_text = CodexLink.with_link(tag.tooltip_text, "computer_opponent")
	return tag


## The seat's player colour (UiPalette.seat_color, the one source of player colours).
static func seat_color(seat_index: int) -> Color:
	return UiPalette.seat_color(seat_index)


## The seat's emblem from design/STYLE_BIBLE.md 1.1 (P1 circle, P2 square, ...) in the seat colour with
## keylines. SeatEmblem draws it, the same mark the map uses.
static func seat_emblem(seat_index: int) -> SeatEmblem:
	return SeatEmblem.new(seat_index)


# --- nodes ----------------------------------------------------------------------------------------

## Links a label to the codex entry for its kind of number (TooltipText.CODEX).
func _link(l: Control, kind: String) -> void:
	CodexLink.attach(l, TooltipText.codex_for(kind), codex_requested.emit)


func _clear_banners() -> void:
	for c in banner_box.get_children():
		banner_box.remove_child(c)
		c.queue_free()


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

	# The hero: the winner's banner, then the caption, the headline and who won.
	var hero := HBoxContainer.new()
	hero.name = "Hero"
	hero.add_theme_constant_override("separation", 28)
	box.add_child(hero)
	banner_box = HBoxContainer.new()
	banner_box.name = "Banners"
	banner_box.add_theme_constant_override("separation", 12)
	banner_box.visible = false
	hero.add_child(banner_box)
	var titles := VBoxContainer.new()
	titles.name = "Titles"
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", 8)
	hero.add_child(titles)
	caption_label = _label("Game over", 22, UiPalette.TEXT_SECONDARY)
	caption_label.name = "CaptionLabel"
	caption_label.mouse_filter = Control.MOUSE_FILTER_PASS
	titles.add_child(caption_label)
	headline_label = _label("", 60, UiPalette.GILT)
	headline_label.name = "HeadlineLabel"
	headline_label.mouse_filter = Control.MOUSE_FILTER_PASS
	headline_label.add_theme_color_override("font_outline_color", UiPalette.KEYLINE_INK)
	headline_label.add_theme_constant_override("outline_size", 6)
	titles.add_child(headline_label)
	seat_label = _label("", 24, UiPalette.TEXT_PRIMARY)
	seat_label.name = "SeatLabel"
	seat_label.mouse_filter = Control.MOUSE_FILTER_PASS
	titles.add_child(seat_label)
	box.add_child(HSeparator.new())
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

	# M4-4: in a game with paths, "Paths taken" stands beside "Provinces held", so the page grows little.
	var standing := HBoxContainer.new()
	standing.name = "Standing"
	standing.add_theme_constant_override("separation", 36)
	box.add_child(standing)
	var held := VBoxContainer.new()
	held.name = "Held"
	held.add_theme_constant_override("separation", 6)
	standing.add_child(held)
	held.add_child(_heading("Provinces held", TooltipText.plain("Provinces held",
		"How many provinces each side owned when the game ended. Hover a line to see which ones.")))
	provinces_box = VBoxContainer.new()
	provinces_box.name = "Provinces"
	provinces_box.add_theme_constant_override("separation", 6)
	held.add_child(provinces_box)
	var paths_col := VBoxContainer.new()
	paths_col.name = "PathsColumn"
	paths_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paths_col.add_theme_constant_override("separation", 4)
	standing.add_child(paths_col)
	paths_heading = _heading("Paths taken", TooltipText.plain(String(RulesCodex.entry("path").get("title", "")), RulesCodex.text("path")))
	paths_heading.name = "PathsHeading"
	paths_heading.visible = false
	paths_col.add_child(paths_heading)
	paths_box = VBoxContainer.new()
	paths_box.name = "Paths"
	paths_box.add_theme_constant_override("separation", 4)
	paths_box.visible = false
	paths_col.add_child(paths_box)

	# M3c S-3: forts and sieges, only in a game with sieges.
	sieges_heading = _heading("Forts and sieges", TooltipText.plain(String(RulesCodex.entry("siege").get("title", "")), RulesCodex.text("siege")))
	sieges_heading.name = "SiegesHeading"
	sieges_heading.visible = false
	box.add_child(sieges_heading)
	sieges_box = VBoxContainer.new()
	sieges_box.name = "Sieges"
	sieges_box.add_theme_constant_override("separation", 4)
	sieges_box.visible = false
	box.add_child(sieges_box)

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
