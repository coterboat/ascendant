class_name SettingsPanel
extends Control
## The Settings overlay (title screen and the game menu): window mode, interface size and, for later,
## whether battles play by themselves. Every change is saved to the settings file (GameSettings) and put
## into effect at once; Close (or Esc) hides the panel and emits `closed`.
## Builds its children in code, so it works before it is in the tree (headless tests).
##
## API:
##   open(settings = null)        shows the panel for `settings` (default: GameSettings.load_from())
##   set_window_mode(mode) -> bool, set_ui_scale(percent) -> bool, set_auto_watch(on)
##   window_picker, scale_picker, watch_picker   the three pickers
##   board_picker, speed_picker   M3a.1: the map as the 3D world or the 2D map, and the 3D playback speed
##   set_board(value) -> bool, set_playback_speed(value) -> bool
##   close()
##   settings                     the GameSettings being edited

signal closed

var settings: GameSettings = null
var window_picker: OptionButton
var scale_picker: OptionButton
var watch_picker: OptionButton  # "Off" / "On": battles play by themselves (milestone 3)
var board_picker: OptionButton  # "3D world" / "2D map" (M3a.1)
var speed_picker: OptionButton  # 1x / 2x / 4x: a turn's playback on the 3D board
var error_label: Label
var close_button: Button


func _init() -> void:
	name = "SettingsPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		close()


func open(game_settings: GameSettings = null) -> void:
	settings = game_settings if game_settings != null else GameSettings.load_from()
	window_picker.select(GameSettings.WINDOW_MODES.find(settings.window_mode))
	scale_picker.select(GameSettings.UI_SCALES.find(settings.ui_scale))
	watch_picker.select(1 if settings.auto_watch_battles else 0)
	board_picker.select(GameSettings.BOARDS.find(settings.board))
	speed_picker.select(GameSettings.PLAYBACK_SPEEDS.find(settings.playback_speed))
	error_label.visible = false
	visible = true
	if is_inside_tree():
		close_button.grab_focus.call_deferred()


func close() -> void:
	visible = false
	closed.emit()


func set_window_mode(mode: String) -> bool:
	if settings == null or not settings.set_window_mode(mode):
		return false
	window_picker.select(GameSettings.WINDOW_MODES.find(mode))
	_changed()
	return true


func set_ui_scale(percent: int) -> bool:
	if settings == null or not settings.set_ui_scale(percent):
		return false
	scale_picker.select(GameSettings.UI_SCALES.find(percent))
	_changed()
	return true


func set_auto_watch(on: bool) -> void:
	if settings == null:
		return
	settings.auto_watch_battles = on
	watch_picker.select(1 if on else 0)
	_changed()


func set_board(value: String) -> bool:
	if settings == null or not settings.set_board(value):
		return false
	board_picker.select(GameSettings.BOARDS.find(value))
	_changed()
	return true


func set_playback_speed(value: int) -> bool:
	if settings == null or not settings.set_playback_speed(value):
		return false
	speed_picker.select(GameSettings.PLAYBACK_SPEEDS.find(value))
	_changed()
	return true


func _changed() -> void:
	var why := settings.save()
	error_label.text = why
	error_label.visible = not why.is_empty()
	if is_inside_tree():
		settings.apply(get_tree())


# --- nodes ----------------------------------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(640, 0)
	panel.add_theme_stylebox_override("panel", UiPalette.panel_style(32))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	box.add_child(_label("TitleLabel", "Settings", 36, UiPalette.GILT))

	window_picker = _picker("WindowPicker", GameSettings.WINDOW_MODE_NAMES)
	window_picker.item_selected.connect(func(i: int): set_window_mode(GameSettings.WINDOW_MODES[i]))
	_row(box, "Window", window_picker, "Play in a window, or fill the whole screen.")

	var scale_names: Array = GameSettings.UI_SCALES.map(func(p): return "%d%%" % p)
	scale_picker = _picker("ScalePicker", scale_names)
	scale_picker.item_selected.connect(func(i: int): set_ui_scale(GameSettings.UI_SCALES[i]))
	_row(box, "Interface size", scale_picker, "125% draws all text, buttons and the map a quarter bigger, for big or far-away screens.")

	watch_picker = _picker("AutoWatchPicker", ["Off", "On"])
	watch_picker.item_selected.connect(func(i: int): set_auto_watch(i == 1))
	_row(box, "Watch battles", watch_picker, TooltipText.plain("Watch battles automatically",
		"When battles play out on screen (coming in milestone 3), each battle of the turn will play by itself as the turn report opens. For now battles are read in the battle report, so this changes nothing yet."))
	var watch_note := _label("AutoWatchNote", "Takes effect when animated battles arrive. Until then, open any battle from the turn report.", 16, UiPalette.TEXT_SECONDARY)
	watch_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(watch_note)

	board_picker = _picker("BoardPicker", GameSettings.BOARD_NAMES)
	board_picker.item_selected.connect(func(i: int): set_board(GameSettings.BOARDS[i]))
	_row(box, "Board", board_picker, TooltipText.plain("Board: the 3D world or the 2D map",
		"The 3D world shows the map as land with fortresses and armies of miniatures, and plays each turn out on it. The 2D map is the flat board, for a slower computer. Both give the same orders, numbers and tooltips; a game in progress switches when you close the settings."))
	var speed_names: Array = GameSettings.PLAYBACK_SPEEDS.map(func(v): return "%d×" % v)
	speed_picker = _picker("PlaybackSpeedPicker", speed_names)
	speed_picker.item_selected.connect(func(i: int): set_playback_speed(GameSettings.PLAYBACK_SPEEDS[i]))
	_row(box, "Turn playback", speed_picker, TooltipText.plain("Turn playback speed",
		"How fast each resolved turn plays out on the 3D board before the turn report opens. Space or a click skips it at any speed."))

	error_label = _label("ErrorLabel", "", 18, UiPalette.NEGATIVE)
	error_label.visible = false
	box.add_child(error_label)

	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)
	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(150, 44)
	close_button.add_theme_font_size_override("font_size", 20)
	close_button.tooltip_text = "Close the settings (Esc). Changes are already saved."
	close_button.pressed.connect(close)
	row.add_child(close_button)


func _row(box: VBoxContainer, title: String, picker: OptionButton, help: String) -> void:
	var row := HBoxContainer.new()
	row.name = title.replace(" ", "") + "Row"
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var label := _label("Label", title, 22, UiPalette.TEXT_PRIMARY)
	label.custom_minimum_size = Vector2(200, 0)
	label.tooltip_text = help
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	picker.tooltip_text = help
	row.add_child(picker)


func _picker(node_name: String, items: Array) -> OptionButton:
	var picker := OptionButton.new()
	picker.name = node_name
	picker.custom_minimum_size = Vector2(220, 44)
	picker.add_theme_font_size_override("font_size", 20)
	for item in items:
		picker.add_item(String(item))
	return picker


func _label(node_name: String, text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
