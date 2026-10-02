class_name NewGameScreen
extends Control
## New game setup (#8): which seat (Player 1, Player 2) plays which faction, and the game seed,
## random by default. Start emits start_requested(config) with
##   {"players": [faction ids in seat order], "seed": int}
## which is what GameScreen.start_game(config) takes. Factions come from data/factions.gd through the
## rules model (GameState builds the Faction objects); the hotseat explanation is RulesCodex
## "hotseat". The same faction can't be picked twice and the seed must be a whole number: either
## problem is explained in plain words and disables Start. Never changes rules state.
## Player colours follow the seat (UiPalette.seat_color): Player 1 is Vermilion, Player 2 Cobalt, so the
## faction picked for a seat is shown in that seat's colour and swapping seats swaps the colours.
## Builds its children in code, so it works before it is in the tree (headless tests).
##
## API:
##   config() -> Dictionary          {"players", "seed"}; only meaningful when is_valid()
##   is_valid() -> bool
##   error_text() -> String          every problem in plain words, "" when valid
##   set_seed(value: int)            new_seed(avoid) -> int picks a random one (the "New seed" button),
##                                   never `avoid`
##   swap_seats()                    Player 1 and Player 2 trade factions (the "Swap seats" button)
##   select_faction(seat, faction_id) -> bool   seat is 1-based; false for an unknown seat or faction
##   set_seats(players) -> bool      every seat at once: faction ids in seat order
##   prefill(last_game)              a rematch of last_game ({"players", "seed"}): the same seating and
##                                   a new seed (the victory screen's New game)
##   seat_faction(seat) -> String, faction_ids() -> Array[String]
##   start() -> bool                 emits start_requested when valid (the Start button, Enter in the seed)
##   back()                          emits back_requested (the Back button, Esc)

signal start_requested(config: Dictionary)
signal back_requested

const SEAT_COUNT := 2
const MAX_SEED_DIGITS := 18  # any 18-digit number fits in a 64-bit int
const MAX_RANDOM_SEED := 999999999
const BACKGROUND := Color("#14131F")
const NEGATIVE := UiPalette.NEGATIVE  # design/STYLE_BIBLE.md 1.3 "negative"

var seat_pickers: Array[OptionButton] = []
var seat_labels: Array[Label] = []
var faction_labels: Array[Label] = []
var hotseat_label: Label
var rematch_label: Label  # shown after prefill(): why the seats are already set
var seed_edit: LineEdit
var new_seed_button: Button
var swap_button: Button
var error_label: Label
var start_button: Button
var back_button: Button
var _model: GameState
var _rng := RandomNumberGenerator.new()
var _digits := RegEx.create_from_string("^[0-9]+$")


func _init() -> void:
	name = "NewGameScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_model = GameState.new()
	_rng.randomize()
	_build()
	for i in SEAT_COUNT:
		seat_pickers[i].select(i % _model.factions.size())
	new_seed()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		back()


# --- API ------------------------------------------------------------------------------------------

func config() -> Dictionary:
	return {"players": _seat_ids(), "seed": _seed_value()}


func is_valid() -> bool:
	return _problems().is_empty()


func error_text() -> String:
	return "\n".join(_problems())


func set_seed(value: int) -> void:
	seed_edit.text = str(value)
	_refresh()


## Picks a new random seed, never `avoid` (the last game's seed, for a rematch), shows it and returns it.
func new_seed(avoid: int = -1) -> int:
	var value := _rng.randi_range(1, MAX_RANDOM_SEED)
	while value == avoid:
		value = _rng.randi_range(1, MAX_RANDOM_SEED)
	set_seed(value)
	return value


## Seats every player at once: `players` holds faction ids in seat order. Returns false, changing
## nothing, unless there is one known faction per seat.
func set_seats(players: Array) -> bool:
	if players.size() != seat_pickers.size():
		return false
	var ids := faction_ids()
	for fid in players:
		if not ids.has(String(fid)):
			return false
	for i in seat_pickers.size():
		seat_pickers[i].select(ids.find(String(players[i])))
	_refresh()
	return true


## A rematch of `last_game` ({"players", "seed"}, GameScreen.config): the same factions in the same
## seats, and a new random seed so the dice fall differently. An unusable seating is left as it is.
func prefill(last_game: Dictionary) -> void:
	rematch_label.visible = set_seats(Array(last_game.get("players", [])))
	new_seed(int(last_game.get("seed", -1)))


func swap_seats() -> void:
	var picks := []
	for p in seat_pickers:
		picks.append(p.selected)
	picks.reverse()
	for i in seat_pickers.size():
		seat_pickers[i].select(picks[i])
	_refresh()


## Sets the faction of `seat` (1-based). Returns false, changing nothing, for an unknown seat or faction.
func select_faction(seat: int, faction_id: String) -> bool:
	var index := faction_ids().find(faction_id)
	if seat < 1 or seat > seat_pickers.size() or index < 0:
		return false
	seat_pickers[seat - 1].select(index)
	_refresh()
	return true


## Faction id picked for `seat` (1-based), or "".
func seat_faction(seat: int) -> String:
	if seat < 1 or seat > seat_pickers.size():
		return ""
	return _seat_ids()[seat - 1]


## Every faction that can be picked, in the order the pickers list them.
func faction_ids() -> Array[String]:
	var out: Array[String] = []
	for f in _model.factions:
		out.append(f.id)
	return out


## Emits start_requested(config()) when the setup is valid. Returns whether it did.
func start() -> bool:
	_refresh()
	if not is_valid():
		return false
	start_requested.emit(config())
	return true


func back() -> void:
	back_requested.emit()


# --- checks ---------------------------------------------------------------------------------------

func _seat_ids() -> Array:
	var ids := []
	for p in seat_pickers:
		ids.append(String(p.get_item_metadata(p.selected)) if p.selected >= 0 else "")
	return ids


func _seed_value() -> int:
	var text := seed_edit.text.strip_edges()
	return text.to_int() if _seed_problem(text).is_empty() else 0


func _seed_problem(text: String) -> String:
	var t := text.strip_edges()
	if t.is_empty():
		return "Enter a seed, or press New seed for a random one."
	if _digits.search(t) == null:
		return "The seed must be a whole number made of digits only, like 482913."
	if t.length() > MAX_SEED_DIGITS:
		return "The seed can have at most %d digits." % MAX_SEED_DIGITS
	return ""


func _problems() -> Array[String]:
	var out: Array[String] = []
	var ids := _seat_ids()
	for i in ids.size():
		if String(ids[i]).is_empty():
			out.append("Pick a faction for Player %d." % (i + 1))
		for j in range(i + 1, ids.size()):
			if not String(ids[i]).is_empty() and ids[i] == ids[j]:
				out.append("Player %d and Player %d both picked %s. Each player needs a different faction." % [
					i + 1, j + 1, _faction(ids[i]).faction_name])
	var seed_problem := _seed_problem(seed_edit.text)
	if not seed_problem.is_empty():
		out.append(seed_problem)
	return out


func _refresh() -> void:
	var problems := _problems()
	error_label.text = "\n".join(problems)
	error_label.visible = not problems.is_empty()
	start_button.disabled = not problems.is_empty()
	start_button.tooltip_text = "Start the game with these players and this seed. Player 1 gives orders first." if problems.is_empty() \
		else "You can't start yet:\n%s" % "\n".join(problems)
	var ids := _seat_ids()
	for i in seat_pickers.size():
		var f := _faction(ids[i])
		faction_labels[i].text = "Plays in %s. %s" % [UiPalette.seat_color_name(i), _faction_summary(f)] if f else ""
		faction_labels[i].tooltip_text = _faction_tooltip(f) if f else ""
		seat_pickers[i].tooltip_text = "Player %d plays %s.\n\n%s" % [i + 1, f.faction_name, _faction_tooltip(f)] if f \
			else "Pick the faction Player %d plays." % (i + 1)


func _faction(fid: String) -> Faction:
	return _model.find_faction(fid)


## "Capital Crownkeep, 50 gold to start. Spearmen, Crossbowmen and Knights, led by a Knight Captain."
func _faction_summary(f: Faction) -> String:
	var names := []
	for ut in f.unit_types:
		names.append(ut.name)
	var units: String = ", ".join(names)
	if names.size() > 1:
		units = "%s and %s" % [", ".join(names.slice(0, names.size() - 1)), names.back()]
	var capital := _model.find_province(f.capital)
	var text := "Capital %s, %d gold to start. %s" % [capital.name if capital else "unknown", f.gold, units]
	if f.commander_type:
		text += ", led by a %s" % f.commander_type.name
	return text + "."


func _faction_tooltip(f: Faction) -> String:
	var lines := PackedStringArray()
	lines.append(f.faction_name)
	lines.append(TooltipText.wrap_text("Starting gold %d: %s" % [f.gold, Faction.describe("gold")]))
	var capital := _model.find_province(f.capital)
	if capital:
		lines.append(TooltipText.wrap_text("Capital %s: %s" % [capital.name, Province.describe("capital")]))
	lines.append("")
	var types: Array = f.unit_types.duplicate()
	if f.commander_type:
		types.append(f.commander_type)
	for ut in types:
		lines.append(TooltipText.wrap_text("%s%s: %d hit points, attack %d, defense %d, morale %d, costs %d gold. %s: %s." % [
			ut.name, " (commander)" if ut.is_commander else "", ut.hp, ut.attack, ut.defense, ut.morale, ut.cost,
			ut.trait_id, AutoBattleResolver.TRAIT_SHORT.get(ut.trait_id, ut.get_trait_desc())]))
	return "\n".join(lines)


func _on_seed_submitted(_text: String) -> void:
	start()


# --- nodes ----------------------------------------------------------------------------------------

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
	style.border_color = UiPalette.PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(36)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.custom_minimum_size = Vector2(900, 0)
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	box.add_child(_label("TitleLabel", "New game", 48, UiPalette.GILT))
	rematch_label = _label("RematchLabel", "Rematch: the same players in the same seats as the last game, with a new seed. Change anything you like.", 18, UiPalette.GILT)
	rematch_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rematch_label.visible = false
	box.add_child(rematch_label)
	var hotseat := RulesCodex.entry("hotseat")
	var hotseat_title := _label("HotseatTitle", String(hotseat.get("title", "")), 22, UiPalette.TEXT_PRIMARY)
	box.add_child(hotseat_title)
	hotseat_label = _label("HotseatLabel", String(hotseat.get("text", "")), 18, UiPalette.TEXT_SECONDARY)
	hotseat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip(hotseat_label, TooltipText.plain(String(RulesCodex.entry("handoff").get("title", "")), RulesCodex.text("handoff")))
	box.add_child(hotseat_label)

	box.add_child(_label("SeatsHeading", "Who plays which faction", 26, UiPalette.GILT))
	for i in SEAT_COUNT:
		var seat_box := VBoxContainer.new()
		seat_box.name = "Seat%d" % (i + 1)
		seat_box.add_theme_constant_override("separation", 4)
		box.add_child(seat_box)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		seat_box.add_child(row)
		row.add_child(VictoryScreen.seat_emblem(i))
		var seat_label := _label("SeatLabel", "Player %d" % (i + 1), 24, UiPalette.seat_color(i).lightened(0.3))
		seat_label.custom_minimum_size = Vector2(130, 0)
		_tooltip(seat_label, TooltipText.plain("Player %d" % (i + 1), "%s Player %d plays in %s on the map, in battle reports and on the victory screen. Colours belong to the seat, so swapping seats swaps the colours too." % [
			RulesCodex.text("hotseat"), i + 1, UiPalette.seat_color_name(i)]))
		row.add_child(seat_label)
		seat_labels.append(seat_label)
		var picker := OptionButton.new()
		picker.name = "FactionPicker"
		picker.custom_minimum_size = Vector2(320, 44)
		picker.add_theme_font_size_override("font_size", 22)
		for f in _model.factions:
			picker.add_item(f.faction_name)
			var idx := picker.item_count - 1
			picker.set_item_metadata(idx, f.id)
			picker.get_popup().set_item_tooltip(idx, _faction_tooltip(f))
		picker.item_selected.connect(func(_index: int): _refresh())
		# The picked faction reads in the seat's colour, the colour it will have in the game.
		for state_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			picker.add_theme_color_override(state_name, UiPalette.seat_color(i).lightened(0.3))
		row.add_child(picker)
		seat_pickers.append(picker)
		var summary := _label("FactionSummary", "", 17, UiPalette.TEXT_SECONDARY)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.mouse_filter = Control.MOUSE_FILTER_PASS
		seat_box.add_child(summary)
		faction_labels.append(summary)

	swap_button = Button.new()
	swap_button.name = "SwapButton"
	swap_button.text = "Swap seats"
	swap_button.custom_minimum_size = Vector2(200, 44)
	swap_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	swap_button.add_theme_font_size_override("font_size", 20)
	swap_button.tooltip_text = "Player 1 and Player 2 trade factions, and with them their colours (colours belong to the seat). Player 1 still gives orders first."
	swap_button.pressed.connect(swap_seats)
	box.add_child(swap_button)

	box.add_child(_label("SeedHeading", "Seed", 26, UiPalette.GILT))
	var seed_row := HBoxContainer.new()
	seed_row.name = "SeedRow"
	seed_row.add_theme_constant_override("separation", 12)
	box.add_child(seed_row)
	seed_edit = LineEdit.new()
	seed_edit.name = "SeedEdit"
	seed_edit.custom_minimum_size = Vector2(320, 44)
	seed_edit.add_theme_font_size_override("font_size", 22)
	seed_edit.placeholder_text = "A whole number"
	seed_edit.max_length = MAX_SEED_DIGITS + 4
	seed_edit.tooltip_text = TooltipText.plain("Seed", "The seed decides every random roll in the game, such as hits in battle. The same seed, factions and orders always play out exactly the same way, so a game can be replayed or shared. It starts random; type your own to replay a game.")
	seed_edit.text_changed.connect(func(_text: String): _refresh())
	seed_edit.text_submitted.connect(_on_seed_submitted)
	seed_row.add_child(seed_edit)
	new_seed_button = Button.new()
	new_seed_button.name = "NewSeedButton"
	new_seed_button.text = "New seed"
	new_seed_button.custom_minimum_size = Vector2(160, 44)
	new_seed_button.add_theme_font_size_override("font_size", 20)
	new_seed_button.tooltip_text = "Pick a new random seed."
	new_seed_button.pressed.connect(new_seed)
	seed_row.add_child(new_seed_button)

	error_label = _label("ErrorLabel", "", 19, NEGATIVE)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.visible = false
	_tooltip(error_label, "Start stays off until this is fixed.")
	box.add_child(error_label)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 20)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(buttons)
	back_button = Button.new()
	back_button.name = "BackButton"
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(160, 56)
	back_button.add_theme_font_size_override("font_size", 22)
	back_button.tooltip_text = "Go back without starting a game (Esc)."
	back_button.pressed.connect(back)
	buttons.add_child(back_button)
	start_button = Button.new()
	start_button.name = "StartButton"
	start_button.text = "Start"
	start_button.custom_minimum_size = Vector2(220, 56)
	start_button.add_theme_font_size_override("font_size", 26)
	for state_name in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiPalette.PANEL_RAISED.lightened(0.08 if state_name == "hover" else 0.0)
		sb.border_color = UiPalette.GILT
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		start_button.add_theme_stylebox_override(state_name, sb)
	start_button.pressed.connect(start)
	buttons.add_child(start_button)


func _label(node_name: String, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _tooltip(l: Label, text: String) -> void:
	l.tooltip_text = text
	l.mouse_filter = Control.MOUSE_FILTER_PASS
