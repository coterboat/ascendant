class_name SettingsPanel
extends Control
## The Settings overlay (title screen and the game menu): window mode, interface size, for later
## whether battles play by themselves, and the sound: Master, Music, Effects and Ambiance volumes and a
## mute switch. Every change is saved to the settings file (GameSettings) and put into effect at once
## (volumes even before the panel is in the tree, since the buses are global); Close (or Esc) hides the
## panel and emits `closed`.
## Builds its children in code, so it works before it is in the tree (headless tests).
##
## API:
##   open(settings = null)        shows the panel for `settings` (default: GameSettings.load_from())
##   set_window_mode(mode) -> bool, set_ui_scale(percent) -> bool, set_auto_watch(on)
##   set_volume(key, percent) -> bool   key: a GameSettings.VOLUME_BUSES key ("music_volume", ...)
##   set_muted(on)
##   window_picker, scale_picker, watch_picker   the three pickers
##   volume_sliders               {volume key: HSlider}, volume_labels {volume key: Label} ("80%")
##   mute_toggle                  the "Mute all sound" CheckBox (like the new game screen's toggles)
##   close()
##   settings                     the GameSettings being edited

signal closed

## What each volume covers, for its tooltip.
const VOLUME_HELP := {
	"master_volume": "Everything the game plays: music, effects and ambiance together.",
	"music_volume": "The title, map and battle themes, and the victory and defeat stings.",
	"sfx_volume": "Clicks, orders, End turn, the new turn, recruits, captures, rulers' deaths and crownings, sacrifices.",
	"ambiance_volume": "The quiet beds under the map (wind and birdsong) and under a battle.",
}

var settings: GameSettings = null
var window_picker: OptionButton
var scale_picker: OptionButton
var watch_picker: OptionButton  # "Off" / "On": battles play by themselves (milestone 3)
var volume_sliders := {}  # GameSettings volume key -> HSlider (0 to 100)
var volume_labels := {}  # GameSettings volume key -> Label showing the percent
var mute_toggle: CheckBox
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
	for key in volume_sliders:
		_show_volume(key)
	mute_toggle.set_pressed_no_signal(settings.muted)
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


func set_volume(key: String, percent: int) -> bool:
	if settings == null or not settings.set_volume(key, percent):
		return false
	_show_volume(key)
	_audio_changed()
	return true


func set_muted(on: bool) -> void:
	if settings == null:
		return
	settings.muted = on
	mute_toggle.set_pressed_no_signal(on)
	_audio_changed()


func _show_volume(key: String) -> void:
	var percent := settings.volume(key)
	(volume_sliders[key] as HSlider).set_value_no_signal(percent)
	(volume_labels[key] as Label).text = "%d%%" % percent


## A volume or the mute changed: saved, and put on the buses at once.
func _audio_changed() -> void:
	_save()
	settings.apply_audio()


func _changed() -> void:
	_save()
	if is_inside_tree():
		settings.apply(get_tree())


func _save() -> void:
	var why := settings.save()
	error_label.text = why
	error_label.visible = not why.is_empty()


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
	box.add_theme_constant_override("separation", 12)
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

	box.add_child(_label("SoundLabel", "Sound", 26, UiPalette.GILT))
	for key in GameSettings.VOLUME_BUSES:
		_volume_row(box, String(key))
	mute_toggle = CheckBox.new()
	mute_toggle.name = "MuteToggle"
	mute_toggle.text = "Mute all sound"
	mute_toggle.add_theme_font_size_override("font_size", 20)
	mute_toggle.tooltip_text = "Silence the whole game without losing your volume levels."
	mute_toggle.toggled.connect(set_muted)
	box.add_child(mute_toggle)

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


## One volume: its name, a 0 to 100 slider in steps of 5, and the percent.
func _volume_row(box: VBoxContainer, key: String) -> void:
	var row := HBoxContainer.new()
	row.name = key.to_pascal_case() + "Row"
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var help: String = VOLUME_HELP.get(key, "")
	var label := _label("Label", String(GameSettings.VOLUME_NAMES[key]), 20, UiPalette.TEXT_PRIMARY)
	label.custom_minimum_size = Vector2(200, 0)
	label.tooltip_text = help
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = key.to_pascal_case() + "Slider"
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = 100
	slider.custom_minimum_size = Vector2(300, 30)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.tooltip_text = help
	slider.value_changed.connect(func(v: float): set_volume(key, int(v)))
	if key == "sfx_volume":
		slider.drag_ended.connect(func(_moved: bool): GameAudio.sfx("order_queued"))  # hear the new level
	row.add_child(slider)
	var value := _label("Value", "100%", 20, UiPalette.TEXT_SECONDARY)
	value.custom_minimum_size = Vector2(64, 0)
	row.add_child(value)
	volume_sliders[key] = slider
	volume_labels[key] = value


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
