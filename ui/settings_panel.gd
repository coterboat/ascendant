class_name SettingsPanel
extends Control
## The Settings overlay (title screen, the game menu and the battle screen): window mode, interface size,
## the board (the 3D world or the 2D map, M3a.1) and how fast a turn plays out on it, and the sound:
## Master, Music, Effects and Ambiance volumes and a mute switch. M3-5 (#60, design/M3_BATTLES.md §6) adds a
## Battles column: watching your battles at the start of each turn (GameSettings.auto_watch_battles), the
## battle view (Simple, or 3D on the land once it is in the game), the speed battles start at, reduced
## motion and screen shake (the [battle] section, BattleFx.settings / save_settings).
## Every change is saved to the settings file (GameSettings) and put into effect at once
## (volumes even before the panel is in the tree, since the buses are global); Close (or Esc) hides the
## panel and emits `closed`.
## Builds its children in code, so it works before it is in the tree (headless tests).
##
## API:
##   open(settings = null)        shows the panel for `settings` (default: GameSettings.load_from())
##   set_window_mode(mode) -> bool, set_ui_scale(percent) -> bool, set_auto_watch(on)
##   set_volume(key, percent) -> bool   key: a GameSettings.VOLUME_BUSES key ("music_volume", ...)
##   set_muted(on)
##   M3-5, the Battles column (saved in the same file's [battle] section):
##   battle_view_picker, battle_speed_picker, reduced_motion_toggle, screen_shake_toggle, battle_view_note
##   set_battle_view(view) -> bool ("simple" / "3d"), set_battle_speed(speed) -> bool (1, 2, 4),
##   set_reduced_motion(on), set_screen_shake(on)
##   window_picker, scale_picker, watch_picker   the three pickers
##   board_picker, speed_picker   M3a.1: the map as the 3D world or the 2D map, and the 3D playback speed
##   set_board(value) -> bool, set_playback_speed(value) -> bool
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
var watch_picker: OptionButton  # "Off" / "On": watch my battles at the start of each turn (M3-5)
var board_picker: OptionButton  # "3D world" / "2D map" (M3a.1)
var speed_picker: OptionButton  # 1x / 2x / 4x: a turn's playback on the 3D board
var volume_sliders := {}  # GameSettings volume key -> HSlider (0 to 100)
var volume_labels := {}  # GameSettings volume key -> Label showing the percent
var mute_toggle: CheckBox
var battle_view_picker: OptionButton  # M3-5: "Simple" / "3D on the land"
var battle_view_note: Label  # M3-5: shown while 3D is chosen but the 3D stage isn't in the game yet
var battle_speed_picker: OptionButton  # M3-5: 1x / 2x / 4x, the speed battles start at
var reduced_motion_toggle: CheckBox  # M3-5
var screen_shake_toggle: CheckBox  # M3-5
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
	for key in volume_sliders:
		_show_volume(key)
	mute_toggle.set_pressed_no_signal(settings.muted)
	_show_battle_settings()
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


## M3-5: the battle view. "3d" plays in the Simple view until the 3D stage is in the game (the note says so).
func set_battle_view(view: String) -> bool:
	if settings == null or not BattleFx.VIEWS.has(view):
		return false
	_save_battle({"view": view})
	return true


func set_battle_speed(speed: int) -> bool:
	if settings == null or not BattlePlayer.SPEEDS.has(speed):
		return false
	_save_battle({"speed": speed})
	return true


func set_reduced_motion(on: bool) -> void:
	if settings != null:
		_save_battle({"reduced_motion": on})


func set_screen_shake(on: bool) -> void:
	if settings != null:
		_save_battle({"screen_shake": on})


func _save_battle(changes: Dictionary) -> void:
	var why := BattleFx.save_settings(changes, settings.path)
	error_label.text = why
	error_label.visible = not why.is_empty()
	_show_battle_settings()


func _show_battle_settings() -> void:
	if settings == null:
		return
	var st := BattleFx.settings(settings.path)
	battle_view_picker.select(BattleFx.VIEWS.find(String(st.view)))
	battle_view_note.visible = st.view == "3d" and not BattleHost.has_stage_3d()
	battle_speed_picker.select(BattlePlayer.SPEEDS.find(int(st.speed)))
	reduced_motion_toggle.set_pressed_no_signal(bool(st.reduced_motion))
	screen_shake_toggle.set_pressed_no_signal(bool(st.screen_shake))
	screen_shake_toggle.disabled = bool(st.reduced_motion)


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
	var outer := VBoxContainer.new()
	outer.name = "Box"
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)
	outer.add_child(_label("TitleLabel", "Settings", 36, UiPalette.GILT))
	# Two columns (M3-5): the window, the board and the sound on the left, battles on the right.
	var columns := HBoxContainer.new()
	columns.name = "Columns"
	columns.add_theme_constant_override("separation", 48)
	outer.add_child(columns)
	var box := VBoxContainer.new()
	box.name = "General"
	box.custom_minimum_size = Vector2(600, 0)
	box.add_theme_constant_override("separation", 12)
	columns.add_child(box)
	var battles := VBoxContainer.new()
	battles.name = "Battles"
	battles.custom_minimum_size = Vector2(520, 0)
	battles.add_theme_constant_override("separation", 12)
	columns.add_child(battles)

	window_picker = _picker("WindowPicker", GameSettings.WINDOW_MODE_NAMES)
	window_picker.item_selected.connect(func(i: int): set_window_mode(GameSettings.WINDOW_MODES[i]))
	_row(box, "Window", window_picker, "Play in a window, or fill the whole screen.")

	var scale_names: Array = GameSettings.UI_SCALES.map(func(p): return "%d%%" % p)
	scale_picker = _picker("ScalePicker", scale_names)
	scale_picker.item_selected.connect(func(i: int): set_ui_scale(GameSettings.UI_SCALES[i]))
	_row(box, "Interface size", scale_picker, "125% draws all text, buttons and the map a quarter bigger, for big or far-away screens.")

	board_picker = _picker("BoardPicker", GameSettings.BOARD_NAMES)
	board_picker.item_selected.connect(func(i: int): set_board(GameSettings.BOARDS[i]))
	_row(box, "Board", board_picker, TooltipText.plain("Board: the 3D world or the 2D map",
		"The 3D world shows the map as land with fortresses and armies of miniatures, and plays each turn out on it. The 2D map is the flat board, for a slower computer. Both give the same orders, numbers and tooltips; a game in progress switches when you close the settings."))
	var speed_names: Array = GameSettings.PLAYBACK_SPEEDS.map(func(v): return "%d×" % v)
	speed_picker = _picker("PlaybackSpeedPicker", speed_names)
	speed_picker.item_selected.connect(func(i: int): set_playback_speed(GameSettings.PLAYBACK_SPEEDS[i]))
	_row(box, "Turn playback", speed_picker, TooltipText.plain("Turn playback speed",
		"How fast each resolved turn plays out on the 3D board before the turn report opens. Space or a click skips it at any speed."))
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

	# Battles (M3-5).
	battles.add_child(_label("BattlesLabel", "Battles", 26, UiPalette.GILT))
	watch_picker = _picker("AutoWatchPicker", ["Off", "On"])
	watch_picker.item_selected.connect(func(i: int): set_auto_watch(i == 1))
	_row(battles, "Watch my battles", watch_picker, TooltipText.plain("Watch my battles at the start of each turn",
		"When this is on, each of your turns starts by playing your battles from the last turn back, one after another, once the turn has played out on the board and the report has opened (in a game for two at one screen, only after the handoff, and only your own). Esc goes to the report. Off by default: the Watch buttons on the turn report play any battle whenever you like."))
	var watch_note := _label("AutoWatchNote", "At the start of each turn, after the handoff. The Watch buttons on the turn report play any battle.", 16, UiPalette.TEXT_SECONDARY)
	watch_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	watch_note.custom_minimum_size = Vector2(500, 0)
	battles.add_child(watch_note)
	battle_view_picker = _picker("BattleViewPicker", ["Simple", "3D on the land"])
	battle_view_picker.item_selected.connect(func(i: int): set_battle_view(BattleFx.VIEWS[i]))
	_row(battles, "Battle view", battle_view_picker, TooltipText.plain("Battle view",
		"How a battle you watch is drawn. Simple: two armies of portrait cards facing each other, with every number on hover. 3D on the land: the battle fought on the province's own ground, woods and walls. Both play back exactly what the report says, with the same controls, why panel and legend."))
	battle_view_note = _label("BattleViewNote", "3D on the land isn't in the game yet: battles play in the Simple view until it arrives.", 16, UiPalette.TEXT_SECONDARY)
	battle_view_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	battle_view_note.custom_minimum_size = Vector2(500, 0)
	battle_view_note.visible = false
	battles.add_child(battle_view_note)
	var bspeed_names: Array = BattlePlayer.SPEEDS.map(func(v): return "%d×" % v)
	battle_speed_picker = _picker("BattleSpeedPicker", bspeed_names)
	battle_speed_picker.item_selected.connect(func(i: int): set_battle_speed(BattlePlayer.SPEEDS[i]))
	_row(battles, "Battle speed", battle_speed_picker, TooltipText.plain("Battle speed",
		"The speed a battle starts at when you watch it. The 1×, 2× and 4× buttons (keys 1, 2, 3) change it while you watch, and the last one you pick is remembered here."))
	reduced_motion_toggle = _check("ReducedMotionToggle", "Reduced motion", TooltipText.plain("Reduced motion",
		"Battles play without screen shake, lunges, slow motion or aura waves; impacts become a still ring and the routed fade where they stand. Projectiles still fly, since they show who hit whom. Applies from the next battle you open."))
	reduced_motion_toggle.toggled.connect(set_reduced_motion)
	battles.add_child(reduced_motion_toggle)
	screen_shake_toggle = _check("ScreenShakeToggle", "Screen shake", TooltipText.plain("Screen shake",
		"A short shake of the battle screen for a big hit or a fallen ruler. Reduced motion turns it off whatever this says. Applies from the next battle you open."))
	screen_shake_toggle.toggled.connect(set_screen_shake)
	battles.add_child(screen_shake_toggle)

	error_label = _label("ErrorLabel", "", 18, UiPalette.NEGATIVE)
	error_label.visible = false
	outer.add_child(error_label)

	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.alignment = BoxContainer.ALIGNMENT_END
	outer.add_child(row)
	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(150, 44)
	close_button.add_theme_font_size_override("font_size", 20)
	close_button.tooltip_text = "Close the settings (Esc). Changes are already saved."
	close_button.pressed.connect(close)
	row.add_child(close_button)


func _check(node_name: String, text: String, help: String) -> CheckBox:
	var c := CheckBox.new()
	c.name = node_name
	c.text = text
	c.add_theme_font_size_override("font_size", 20)
	c.tooltip_text = help
	return c


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
