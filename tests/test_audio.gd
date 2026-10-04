extends "res://tests/test_case.gd"
## Sound (GameAudio, the Audio autoload, and the volume settings): audio.json loads and every file it
## names is there (loops flagged as loops); an unknown event or a missing file warns once and plays
## nothing; pitch jitter depends only on the event and its index, never on an RNG; cooldowns hold;
## the volumes and the mute survive a save and land on the buses; the settings panel has the sound
## controls; the turn report and the end of a game pick the right cues; every event the screens name is
## in audio.json; and whole games played through GameScreen with sound on end in exactly the same state
## as with sound off, while the right cues fire.
## Outside the tree GameAudio keeps its books (history, counters) but starts no players, so all of this
## runs headless. Each test that attaches an audio node as GameAudio.current detaches it again.

const MANIFEST := "res://assets/audio/audio.json"
const LAYOUT := "res://default_bus_layout.tres"
const GAME_SCENE := "res://ui/game_screen.tscn"
const TITLE_SCENE := "res://ui/title_screen.tscn"
const HOTSEAT := {"players": ["kingdom", "beasts"], "seed": 4242}
const SWAPPED := {"players": ["beasts", "kingdom"], "seed": 4242}
const VS_COMPUTER := {"players": ["kingdom", "beasts"], "seed": 4242, "ai": {"beasts": "normal"}}


func _manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))


func _audio(quiet: bool = false) -> GameAudio:
	var a := GameAudio.new()
	a.quiet = quiet
	return a


func _path(ext: String) -> String:
	return "user://test_audio_%d_%d.%s" % [Time.get_ticks_usec(), randi(), ext]


func _bus_db(bus_name: String) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus_name))


## Back to the default levels (every bus at 0 dB, nothing muted) for the tests after this one.
func _reset_buses() -> void:
	GameSettings.new(_path("cfg")).apply_audio()


# --- the manifest and the files -------------------------------------------------------------------

func test_the_manifest_loads_and_every_file_exists() -> void:
	var data := _manifest()
	var a := _audio()
	assert_true(a.load_manifest(), "audio.json loads")
	assert_eq(a.events.size(), (data.events as Dictionary).size(), "every event in audio.json is known")
	assert_true(a.events.size() > 0)
	for bus in a.bus_names:
		assert_true(GameAudio.BUS_NAMES.has(bus), "bus %s is one GameAudio knows" % bus)
	for event_name in a.events:
		var e: Dictionary = a.events[event_name]
		var path := String(e.path)
		assert_true(ResourceLoader.exists(path), "%s: %s exists" % [event_name, path])
		var stream := load(path) as AudioStream
		assert_true(stream != null, "%s loads as an AudioStream" % event_name)
		assert_true(AudioServer.get_bus_index(String(e.bus)) != -1, "%s: its bus %s is in the bus layout" % [event_name, e.bus])
		if stream != null and bool(e.get("loop", false)):
			assert_true(bool(stream.get("loop")), "%s loops (loop=true in its .import)" % event_name)
	assert_eq(a.warnings, PackedStringArray(), "no warnings")
	a.free()


func test_the_bus_layout_has_every_bus() -> void:
	var layout := load(LAYOUT) as AudioBusLayout
	assert_true(layout != null, "default_bus_layout.tres loads")
	var names := []
	for i in range(1, 8):
		var n = layout.get("bus/%d/name" % i)
		if n != null:
			names.append(String(n))
			assert_eq(String(layout.get("bus/%d/send" % i)), "Master", "%s sends to Master" % n)
	for bus in GameAudio.BUS_NAMES:
		assert_true(names.has(bus), "the layout has the %s bus" % bus)
		assert_true(AudioServer.get_bus_index(bus) != -1, "and the running game has it")
	for bus in (_manifest().buses as Dictionary):
		assert_true(names.has(bus), "audio.json's %s bus is in the layout" % bus)


func test_an_unknown_event_warns_once_and_plays_nothing() -> void:
	var a := _audio(true)
	assert_false(a.play("no_such_sound"), "an unknown event plays nothing")
	assert_false(a.play("no_such_sound"))
	assert_false(a.play_music("no_such_theme"))
	assert_eq(a.warnings.size(), 2, "one warning per unknown name, not per call: %s" % [a.warnings])
	assert_true(a.warnings[0].contains("no_such_sound"), a.warnings[0])
	assert_eq(a.history, [] as Array[String], "nothing played")
	assert_true(a.play("ui_click"), "known events still play")
	a.free()
	GameAudio.current = null
	GameAudio.sfx("ui_click")  # no audio node: nothing happens, no error
	GameAudio.music("music_map")
	GameAudio.battle(true)
	GameAudio.report([{"type": "recruited"}])


func test_a_missing_file_warns_once() -> void:
	var path := _path("json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "base": "res://assets/audio/", "buses": {"SFX": ""},
		"events": {"ghost": {"file": "sfx/ghost_that_is_not_there.wav", "bus": "SFX", "volume_db": -6},
			"ui_click": {"file": "sfx/ui_click.wav", "bus": "SFX", "volume_db": -12}}}))
	f.close()
	var a := _audio(true)
	a.manifest_path = path
	assert_true(a.load_manifest())
	assert_false(a.play("ghost"), "a missing file plays nothing")
	assert_false(a.play("ghost"))
	assert_eq(a.warnings.size(), 1, "and warns once: %s" % [a.warnings])
	assert_true(a.warnings[0].contains("ghost_that_is_not_there.wav"), a.warnings[0])
	assert_true(a.play("ui_click"), "the other sounds still play")
	a.free()
	DirAccess.remove_absolute(path)

	var none := _audio(true)
	none.manifest_path = "res://assets/audio/not_there.json"
	assert_false(none.load_manifest(), "a missing audio.json")
	assert_eq(none.warnings.size(), 1, "warns once")
	assert_false(none.play("ui_click"), "and the game plays no sound")
	none.free()


# --- determinism ----------------------------------------------------------------------------------

func test_pitch_jitter_is_deterministic_for_the_same_index() -> void:
	var data := _manifest()
	for event_name in ["ui_click", "battle_hit", "unit_fall"]:
		var amount := float(data.events[event_name].pitch_jitter)
		var pitches := {}
		for i in 12:
			var p := GameAudio.jitter_pitch(event_name, i, amount)
			assert_eq(p, GameAudio.jitter_pitch(event_name, i, amount), "%s #%d: the same pitch every time" % [event_name, i])
			assert_true(p >= 1.0 - amount - 0.0001 and p <= 1.0 + amount + 0.0001, "%s #%d: %f is within +/- %f" % [event_name, i, p, amount])
			pitches[snappedf(p, 0.0001)] = true
		assert_true(pitches.size() >= 6, "%s: the pitch varies from play to play (%d values)" % [event_name, pitches.size()])
	assert_eq(GameAudio.jitter_pitch("order_queued", 3, 0.0), 1.0, "no jitter: pitch 1")

	# Two audio nodes playing the same cues give the same pitches, and neither draws from the global RNG.
	seed(20261004)
	var expected := randi()
	seed(20261004)
	var runs := []
	for run in 2:
		var a := _audio()
		var seen := []
		for i in 6:
			a.play("ui_click")
			seen.append(a.last_pitch["ui_click"])
		assert_eq(a.play_count("ui_click"), 6)
		runs.append(seen)
		a.free()
	assert_eq(runs[0], runs[1], "the same pitches in the same order")
	for i in 6:
		assert_eq(runs[0][i], GameAudio.jitter_pitch("ui_click", i, float(data.events.ui_click.pitch_jitter)), "play %d uses index %d" % [i, i])
	assert_eq(randi(), expected, "audio never touched the global RNG")
	randomize()


func test_cooldowns_hold() -> void:
	var data := _manifest()
	var a := _audio()
	assert_true(int(data.events.ui_hover.cooldown_ms) > 0, "ui_hover has a cooldown in audio.json")
	assert_true(a.play("ui_hover"))
	assert_false(a.play("ui_hover"), "a second hover inside %d ms is dropped" % int(data.events.ui_hover.cooldown_ms))
	assert_eq(a.play_count("ui_hover"), 1)
	assert_true(a.play("order_queued"))
	assert_true(a.play("order_queued"), "an event without a cooldown always plays")
	assert_eq(a.history, ["ui_hover", "order_queued", "order_queued"] as Array[String])
	a.free()


# --- volumes --------------------------------------------------------------------------------------

func test_volume_settings_round_trip_and_apply_to_the_buses() -> void:
	var path := _path("cfg")
	var s := GameSettings.load_from(path)
	for key in GameSettings.VOLUME_BUSES:
		assert_eq(s.volume(key), 100, "%s is 100%% by default" % key)
	assert_false(s.muted, "not muted by default")
	var levels := {"master_volume": 80, "music_volume": 55, "sfx_volume": 0, "ambiance_volume": 35}
	for key in levels:
		assert_true(s.set_volume(key, levels[key]))
	s.muted = true
	assert_false(s.set_volume("cowbell_volume", 50), "only the four volumes")
	assert_eq(s.save(), "")
	var back := GameSettings.load_from(path)
	for key in levels:
		assert_eq(back.volume(key), levels[key], "%s survives a save" % key)
	assert_true(back.muted, "the mute survives a save")
	assert_true(back.set_volume("music_volume", 150))
	assert_eq(back.music_volume, 100, "a volume stays within 0 to 100")
	back.music_volume = 55

	back.apply_audio()
	for key in levels:
		var bus := String(GameSettings.VOLUME_BUSES[key])
		var index := AudioServer.get_bus_index(bus)
		if levels[key] > 0:
			assert_true(is_equal_approx(_bus_db(bus), GameSettings.volume_db(levels[key])), "%s bus at %f dB, expected %f" % [bus, _bus_db(bus), GameSettings.volume_db(levels[key])])
		assert_eq(AudioServer.is_bus_mute(index), levels[key] == 0 or key == "master_volume", "%s bus mute" % bus)
	assert_true(GameSettings.volume_db(50) < -6.0 and GameSettings.volume_db(50) > -18.0, "50%% sounds about half as loud")
	assert_eq(GameSettings.volume_db(100), 0.0)
	assert_true(GameSettings.volume_db(0) <= -80.0)

	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[settings]\nmusic_volume=\"loud\"\nsfx_volume=-5\nambiance_volume=101\nmuted=\"yes\"\n")
	f.close()
	var garbled := GameSettings.load_from(path)
	for key in GameSettings.VOLUME_BUSES:
		assert_eq(garbled.volume(key), 100, "a garbled %s gives the default" % key)
	assert_false(garbled.muted)

	_reset_buses()
	for bus in ["Master"] + GameAudio.BUS_NAMES:
		assert_eq(_bus_db(bus), 0.0, "%s back at 0 dB" % bus)
		assert_false(AudioServer.is_bus_mute(AudioServer.get_bus_index(bus)), "%s unmuted" % bus)
	DirAccess.remove_absolute(path)


func test_the_settings_panel_has_the_sound_controls() -> void:
	var path := _path("cfg")
	var panel := SettingsPanel.new()
	panel.open(GameSettings.load_from(path))
	assert_eq(panel.volume_sliders.keys(), GameSettings.VOLUME_BUSES.keys(), "a slider per volume")
	for key in panel.volume_sliders:
		var slider := panel.volume_sliders[key] as HSlider
		assert_eq(slider.value, 100.0, "%s starts at the saved 100%%" % key)
		assert_eq((panel.volume_labels[key] as Label).text, "100%")
		assert_false(slider.tooltip_text.is_empty(), "%s says what it covers" % key)
	assert_false(panel.mute_toggle.button_pressed)
	assert_false(panel.mute_toggle.tooltip_text.is_empty())

	(panel.volume_sliders["music_volume"] as HSlider).value_changed.emit(40.0)
	assert_eq((panel.volume_labels["music_volume"] as Label).text, "40%")
	assert_eq(GameSettings.load_from(path).music_volume, 40, "saved at once")
	assert_true(is_equal_approx(_bus_db("Music"), GameSettings.volume_db(40)), "and the Music bus follows")
	panel.mute_toggle.toggled.emit(true)
	assert_true(GameSettings.load_from(path).muted, "the mute is saved")
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "and silences the Master bus")

	# Reopened, the panel shows what was saved.
	panel.close()
	panel.open(GameSettings.load_from(path))
	assert_eq((panel.volume_sliders["music_volume"] as HSlider).value, 40.0)
	assert_true(panel.mute_toggle.button_pressed)
	panel.free()
	_reset_buses()
	DirAccess.remove_absolute(path)


# --- which cue, when ------------------------------------------------------------------------------

func test_the_turn_report_picks_its_headline_cues() -> void:
	var capital := {"type": "captured", "numbers": {"is_capital": true}}
	var plain := {"type": "captured", "numbers": {"is_capital": false}}
	assert_eq(GameAudio.report_cues([]), [] as Array[String], "a quiet turn has no cues")
	assert_eq(GameAudio.report_cues([{"type": "army_moved"}, {"type": "income"}]), ["march"] as Array[String])
	assert_eq(GameAudio.report_cues([plain]), ["march"] as Array[String], "a captured province marches in")
	assert_eq(GameAudio.report_cues([plain, capital]), ["capital_captured", "march"] as Array[String], "a capital gets its fanfare")
	assert_eq(GameAudio.report_cues([{"type": "recruited"}, {"type": "recruited"}, {"type": "army_moved"}]), ["recruit", "march"] as Array[String], "one cue per kind")
	assert_eq(GameAudio.report_cues([{"type": "recruited"}, capital, {"type": "ruler_died"}, {"type": "ruler_arrived"}, {"type": "sacrificed"}]),
		["ruler_death", "capital_captured", "succession_crown"] as Array[String], "the most dramatic first, at most three")
	assert_eq(GameAudio.report_cues([{"type": "sacrificed"}, {"type": "research_done"}]), ["sacrifice", "research_complete"] as Array[String])
	var events := _manifest().events as Dictionary
	for pair in GameAudio.REPORT_CUES:
		assert_true(events.has(pair[1]), "report cue %s is in audio.json" % pair[1])


func test_the_end_of_a_game_picks_its_sting() -> void:
	var players := ["kingdom", "beasts"]
	assert_eq(GameAudio.ending_sting({}, players, {}), "", "no sting while the game runs")
	assert_eq(GameAudio.ending_sting({"winner": "kingdom"}, players, {"beasts": "normal"}), "sting_victory", "you beat the computer")
	assert_eq(GameAudio.ending_sting({"winner": "beasts"}, players, {"beasts": "normal"}), "sting_defeat", "the computer beat you")
	assert_eq(GameAudio.ending_sting({"winner": "beasts"}, players, {}), "sting_victory", "a hotseat game always has a winner at the table")
	assert_eq(GameAudio.ending_sting({"winner": "beasts"}, players, {"kingdom": "easy", "beasts": "normal"}), "sting_victory", "watching the computer")
	assert_eq(GameAudio.ending_sting({"draw": true, "winner": ""}, players, {"beasts": "normal"}), "sting_defeat", "nobody wins a draw")


## Every event name the screens pass to GameAudio is in audio.json (the game uses only those).
func test_every_event_the_screens_name_is_in_audio_json() -> void:
	var events := _manifest().events as Dictionary
	var calls := RegEx.create_from_string("GameAudio\\.(?:sfx|music|ambiance)\\(\"([a-z_]*)\"")
	var follows := RegEx.create_from_string("_order_sound\\(reason, \"([a-z_]*)\"\\)")
	var named := {}
	for file in DirAccess.get_files_at("res://ui"):
		if not file.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string("res://ui".path_join(file))
		for re in [calls, follows]:
			for m in re.search_all(text):
				if not m.get_string(1).is_empty():
					named[m.get_string(1)] = file
	for event_name in named:
		assert_true(events.has(event_name), "%s (in %s) is in audio.json" % [event_name, named[event_name]])
	for wanted in ["music_title", "music_map", "amb_map", "end_turn", "turn_start", "order_queued", "order_cancelled", "march", "recruit", "sacrifice"]:
		assert_true(named.has(wanted), "the screens use %s" % wanted)
	for constant in [GameAudio.BATTLE_MUSIC, GameAudio.BATTLE_AMBIANCE, "ui_click", "ui_hover"]:
		assert_true(events.has(constant), "%s is in audio.json" % constant)


func test_the_title_screen_plays_the_title_theme() -> void:
	var a := _audio()
	GameAudio.current = a
	var title := load(TITLE_SCENE).instantiate() as TitleScreen
	title._ready()
	assert_eq(a.music_name, "music_title")
	assert_eq(a.ambiance_name, "", "no bed under the title")
	assert_eq(a.history, ["music_title"] as Array[String])
	title.free()
	GameAudio.current = null
	a.free()


# --- sound on and off: the same game --------------------------------------------------------------

## The player at the controls gives `orders` through the map: [army, province] is a two-click move,
## [unit type] presses the capital's recruit button.
func _order(game: GameScreen, orders: Array) -> void:
	for o in orders:
		var before := game.session.current_orders().size()
		if o.size() == 2:
			game.map.select_army(o[0])
			game.map.select_province(o[1])
		else:
			game.map.selected_army_id = ""
			var f := game.map.state.find_faction(game.session.current_player())
			game.map.select_province(f.capital)
			for b in game.map.details.find_children("Recruit_%s" % o[0], "Button", true, false):
				(b as Button).pressed.emit()
				break
		assert_eq(game.session.current_orders().size(), before + 1, "order %s queued (%s)" % [o, game.map.status_text])


## A hotseat turn: seat 1's orders, End turn, Ready, seat 2's orders, End turn, and Ready for the next.
func _hotseat_turn(game: GameScreen, first: Array, second: Array) -> void:
	_order(game, first)
	game.end_turn_button.pressed.emit()
	game.handoff.ready_button.pressed.emit()
	game.close_turn_report()
	_order(game, second)
	game.end_turn_button.pressed.emit()
	if not game.session.is_over():
		game.handoff.ready_button.pressed.emit()
		game.close_turn_report()


## Plays `script` through a new game screen with `audio` as the running audio node (null: no sound).
## Returns the screen; the caller frees it.
func _play(config: Dictionary, audio: GameAudio, script: Callable) -> GameScreen:
	GameAudio.current = audio
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.start_game(config)
	script.call(game)
	GameAudio.current = null
	return game


func _assert_same_game(on: GameScreen, off: GameScreen, what: String) -> void:
	assert_eq(var_to_str(on.session.state().to_dict()), var_to_str(off.session.state().to_dict()), "%s: the same state with sound on and off" % what)
	assert_eq(on.session.history(), off.session.history(), "%s: the same orders and turn seeds" % what)
	assert_eq(on.session.turn_report().events.map(func(e): return e.text),
		off.session.turn_report().events.map(func(e): return e.text), "%s: the same report" % what)
	assert_eq(on.session.phase(), off.session.phase())


func test_sound_never_changes_a_hotseat_game_to_the_capital() -> void:
	var script := func(game: GameScreen) -> void:
		for step in [["westwatch", "bloodfen"], ["stonegate", "deepwood"], ["blackwood", "greenglade"], ["ebonpeak", "rivermarch"]]:
			_hotseat_turn(game, [["kingdom-1", step[0]]], [["beasts-1", step[1]]])
		_hotseat_turn(game, [["kingdom-1", "fangridge"]], [])
	var a := _audio()
	var on := _play(HOTSEAT, a, script)
	var off := _play(HOTSEAT, null, script)
	assert_true(on.session.is_over(), "the scripted game ends with the capital taken")
	_assert_same_game(on, off, "hotseat to the capital")
	assert_eq(a.warnings, PackedStringArray(), "no sound warnings")
	for cue in ["music_map", "amb_map", "order_queued", "march", "end_turn", "turn_start", "sting_victory"]:
		assert_true(a.history.has(cue), "%s played: %s" % [cue, a.history])
	assert_eq(a.history.count("end_turn"), on.session.turns_played() * 2, "End turn sounded once per player per turn")
	assert_eq(a.history[0], "music_map", "the map theme starts the game")
	assert_eq(a.history[-1], "sting_victory", "and the victory sting ends it")
	assert_eq(a.music_name, "sting_victory")
	on.free()
	off.free()
	a.free()


func test_sound_never_changes_a_game_with_a_battle_and_its_report() -> void:
	var script := func(game: GameScreen) -> void:
		_hotseat_turn(game, [["beasts-1", "ebonpeak"], ["tuskers"]], [["kingdom-1", "westwatch"], ["spearmen"]])
		_hotseat_turn(game, [["beasts-1", "blackwood"]], [["kingdom-1", "stonegate"]])
		_order(game, [])
		game.end_turn_button.pressed.emit()
		game.handoff.ready_button.pressed.emit()
		game.close_turn_report()
		_order(game, [["kingdom-1", "blackwood"]])
		game.end_turn_button.pressed.emit()
		game.handoff.ready_button.pressed.emit()
	var a := _audio()
	var on := _play(SWAPPED, a, script)
	var off := _play(SWAPPED, null, script)
	assert_eq(on.session.battle_events().size(), 1, "the script has a battle")
	_assert_same_game(on, off, "a battle game")
	for cue in ["recruit", "march", "turn_start"]:
		assert_true(a.history.has(cue), "%s played: %s" % [cue, a.history])

	# The battle report: battle music and bed over the ducked map theme, and back when it closes.
	GameAudio.current = a
	assert_true(on.report_overlay.visible, "the report of the battle turn is open")
	on.report_panel.battle_buttons()[0].pressed.emit()
	assert_true(on.battle_viewer.visible)
	assert_eq(a.music_name, "music_battle", "battle music while the report is open")
	assert_eq(a.ambiance_name, "amb_battle")
	assert_true(a.in_mood())
	on.battle_viewer.close_button.pressed.emit()
	assert_eq(a.music_name, "music_map", "the map theme comes back")
	assert_eq(a.ambiance_name, "amb_map")
	assert_false(a.in_mood())
	on.report_panel.battle_buttons()[0].pressed.emit()
	on.end_turn_button.pressed.emit()  # End turn closes the viewer too
	assert_false(on.battle_viewer.visible)
	assert_eq(a.music_name, "music_map", "closing it any way brings the map theme back")
	GameAudio.current = null
	on.free()
	off.free()
	a.free()


func test_sound_never_changes_a_game_against_the_computer() -> void:
	var script := func(game: GameScreen) -> void:
		for orders in [[["kingdom-1", "westwatch"], ["spearmen"]], [["kingdom-1", "stonegate"]], [["knights"]]]:
			_order(game, orders)
			game.end_turn_button.pressed.emit()
			game.close_turn_report()
	var a := _audio()
	var on := _play(VS_COMPUTER, a, script)
	var off := _play(VS_COMPUTER, null, script)
	assert_eq(on.session.turns_played(), 3)
	_assert_same_game(on, off, "against the computer")
	assert_false(a.history.has("sting_victory") or a.history.has("sting_defeat"), "no sting mid-game")
	assert_eq(a.history.count("turn_start"), 4, "turn_start once per turn, turns 1 to 4, with no handoff: %s" % [a.history])
	assert_eq(a.history.count("end_turn"), 3)
	assert_true(a.history.has("recruit"), "recruits sound")
	on.free()
	off.free()
	a.free()
