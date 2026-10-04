extends "res://tests/test_case.gd"
## Settings (GameSettings, SettingsPanel): window mode, interface size and the auto-watch switch for
## milestone 3 survive a save and a load; a missing or garbled file gives the defaults; the panel saves
## every change at once; the title screen and the game menu both open it. Each test uses its own
## temporary file, never the real user://settings.cfg.

const GAME_SCENE := "res://ui/game_screen.tscn"


func _path() -> String:
	return "user://test_settings_%d_%d.cfg" % [Time.get_ticks_usec(), randi()]


func test_the_defaults() -> void:
	var s := GameSettings.load_from(_path())
	assert_eq(s.window_mode, "windowed")
	assert_eq(s.ui_scale, 100)
	assert_eq(s.auto_watch_battles, false, "battles are not watched automatically by default")


func test_settings_round_trip() -> void:
	var path := _path()
	var s := GameSettings.new(path)
	assert_true(s.set_window_mode("fullscreen"))
	assert_true(s.set_ui_scale(125))
	s.auto_watch_battles = true
	assert_eq(s.save(), "")
	var back := GameSettings.load_from(path)
	assert_eq(back.window_mode, "fullscreen")
	assert_eq(back.ui_scale, 125)
	assert_eq(back.auto_watch_battles, true)
	assert_false(s.set_window_mode("borderless"), "only the modes the game has")
	assert_false(s.set_ui_scale(150), "only 100% and 125%")
	assert_eq(s.window_mode, "fullscreen", "a refused value changes nothing")
	DirAccess.remove_absolute(path)


func test_a_garbled_file_gives_the_defaults() -> void:
	var path := _path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[settings]\nwindow_mode=\"sideways\"\nui_scale=300\nauto_watch_battles=\"yes\"\n")
	f.close()
	var s := GameSettings.load_from(path)
	assert_eq(s.window_mode, "windowed")
	assert_eq(s.ui_scale, 100)
	assert_eq(s.auto_watch_battles, false)
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("this is not a settings file {{{")
	f.close()
	assert_eq(GameSettings.load_from(path).ui_scale, 100)
	DirAccess.remove_absolute(path)


func test_the_panel_saves_every_change() -> void:
	var path := _path()
	var panel := SettingsPanel.new()
	panel.open(GameSettings.load_from(path))
	assert_true(panel.visible)
	assert_eq(panel.window_picker.selected, 0)
	assert_eq(panel.scale_picker.selected, 0)
	assert_eq(panel.watch_picker.selected, 0, "watching battles is off")
	panel.scale_picker.select(1)
	panel.scale_picker.item_selected.emit(1)
	panel.watch_picker.item_selected.emit(1)
	panel.window_picker.item_selected.emit(1)
	var back := GameSettings.load_from(path)
	assert_eq(back.ui_scale, 125, "the size is saved at once")
	assert_eq(back.auto_watch_battles, true)
	assert_eq(back.window_mode, "fullscreen")
	assert_true(panel.watch_picker.tooltip_text.contains("milestone 3"), "the auto-watch switch explains that it is for later")
	panel.close_button.pressed.emit()
	assert_false(panel.visible)
	panel.free()
	DirAccess.remove_absolute(path)


func test_the_game_menu_opens_settings() -> void:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.start_game({"players": ["kingdom", "beasts"], "seed": 3, "ai": {"beasts": "normal"}})
	game.open_menu()
	(game.menu_overlay.find_child("SettingsButton", true, false) as Button).pressed.emit()
	assert_true(game.settings_panel.visible, "Menu > Settings opens the settings")
	assert_true(game.settings_panel.get_index() > game.menu_overlay.get_index(), "above the menu")
	game.free()
