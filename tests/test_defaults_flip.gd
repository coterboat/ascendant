extends "res://tests/test_case.gd"
## MVP-2 (#163) acceptance, the defaults flip. Every system box on the new game screen (Rulers, Paths, Forts & sieges,
## Magic, Fog of war, Independents) starts ticked and Quick start turns them all on; the "(M2/M3c/M4/M5 preview)" labels and
## the preview wording are gone, and each box stays a choice that says what it adds. With every box unticked a game is still
## the M1 game byte for byte (the fixtures in tests/fixtures), games saved with other systems load with their own, a rematch
## starts from the last game's boxes, and a settings file from before the flip gets one line saying the defaults changed, once.

const NEW_GAME_SCENE := "res://ui/new_game_screen.tscn"
const TITLE_SCENE := "res://ui/title_screen.tscn"
const FIXTURE := "res://tests/fixtures/main_records.json"
const KEYS := ["rulers", "paths", "sieges", "magic", "fog", "independents"]
const NAMES := {"rulers": "Rulers", "paths": "Paths", "sieges": "Forts & sieges", "magic": "Magic", "fog": "Fog of war",
	"independents": "Independents"}
## The codex entry each box links to.
const ENTRIES := {"rulers": "build_screen", "paths": "path", "sieges": "fort_levels", "magic": "magic", "fog": "fog_of_war",
	"independents": "independents"}
const SAVED_AT := 1790000000
const CROWN := "kingdom"
const CLANS := "beasts"

var _folder := ""
var _files: Array[String] = []


# --- helpers --------------------------------------------------------------------------------------

func _screen() -> NewGameScreen:
	return load(NEW_GAME_SCENE).instantiate() as NewGameScreen


## The checkbox of a system on `screen`.
func _box(screen: NewGameScreen, key: String) -> CheckBox:
	return screen.get(key + "_toggle") as CheckBox


func _ticked(screen: NewGameScreen) -> Array:
	return KEYS.filter(func(k): return _box(screen, k).button_pressed)


## A title screen with its own empty save folder.
func _title() -> TitleScreen:
	_folder = "user://test_defaults_flip_%d_%d" % [Time.get_ticks_usec(), randi()]
	var title := load(TITLE_SCENE).instantiate() as TitleScreen
	title.store = SaveStore.new(_folder)
	title._bind()
	return title


func _cleanup() -> void:
	if not _folder.is_empty():
		SaveStore.new(_folder).clear()
		DirAccess.remove_absolute(_folder)
	for f in _files:
		DirAccess.remove_absolute(f)
	_files.clear()


func _settings_path() -> String:
	var path := "user://test_defaults_flip_%d_%d.cfg" % [Time.get_ticks_usec(), randi()]
	_files.append(path)
	return path


## Which systems a state has.
func _systems_of(state: GameState) -> Dictionary:
	return {"rulers": RulerRules.has_rulers(state), "paths": state.paths, "sieges": state.sieges, "magic": state.magic,
		"fog": state.fog, "independents": state.independents}


func _all(on: bool) -> Dictionary:
	var out := {}
	for k in KEYS:
		out[k] = on
	return out


func _all_text(node: Node) -> String:
	var out := PackedStringArray()
	_collect(node, out)
	return "\n".join(out)


func _collect(node: Node, out: PackedStringArray) -> void:
	if node is Label or node is Button:
		out.append(node.text)
	if node is Control and not (node as Control).tooltip_text.is_empty():
		out.append((node as Control).tooltip_text)
	for c in node.get_children():
		_collect(c, out)


# --- the screen's defaults ------------------------------------------------------------------------

func test_every_system_box_starts_ticked_with_no_preview_label() -> void:
	var screen := _screen()
	assert_eq(NewGameScreen.SYSTEMS.map(func(s): return s.key), KEYS, "the six boxes, in screen order")
	assert_eq(NewGameScreen.default_systems(), _all(true), "every system defaults on")
	assert_eq(_ticked(screen), KEYS, "all six boxes are ticked")
	assert_eq(screen.systems_ticked(), KEYS)
	var cfg := screen.config()
	for k in KEYS:
		assert_eq(cfg.get(k), true, "config() asks for %s" % k)
		assert_eq(_box(screen, k).text, NAMES[k], "the box is just '%s'" % NAMES[k])
	assert_eq(screen.seat_kind(1), "human", "you")
	assert_eq(screen.seat_kind(2), "computer", "against the computer: the other defaults are as they were")
	assert_eq(screen.start_button.text, "Choose builds", "with rulers on Start goes to the build screen")
	var text := _all_text(screen)
	for old in ["M2 preview", "M3c preview", "M4 preview", "M5 preview", "(preview)", "preview of", "still being built"]:
		assert_false(text.contains(old), "no '%s' anywhere on the screen, tooltips included" % old)
	assert_false(screen.defaults_label.visible, "no settings file, nothing to say about the old defaults")
	screen.free()


func test_each_box_stays_a_choice_and_the_boxes_that_need_each_other_go_together() -> void:
	for key in KEYS:
		var screen := _screen()
		_tick(screen, key, false)
		assert_false(screen.config().has(key), "%s unticked: the game plays without it" % key)
		var gone: Array = [key]
		if key == "rulers":
			gone = ["rulers", "paths", "magic"]  # paths need rulers, magic needs paths
		elif key == "paths":
			gone = ["paths", "magic"]
		var want := KEYS.filter(func(k): return not gone.has(k))
		assert_eq(_ticked(screen), want, "unticking %s leaves exactly what does not need it" % key)
		for k in KEYS:
			assert_eq(screen.config().has(k), want.has(k), "%s: the config follows the boxes (%s)" % [k, key])
		_tick(screen, key, true)
		var needs := {"magic": ["paths", "rulers"], "paths": ["rulers"]}
		var back: Array = want + [key] + needs.get(key, [])
		for k in KEYS:
			assert_eq(_box(screen, k).button_pressed, back.has(k), "ticking %s again ticks it and what it needs, nothing else: %s" % [key, k])
		screen.free()
	# All the way down, and up again: magic pulls paths and rulers with it.
	var s := _screen()
	s.set_all_systems(false)
	assert_eq(_ticked(s), [], "the basic game")
	assert_eq(s.start_button.text, "Start", "without rulers there is no build screen")
	s.set_magic(true)
	assert_eq(_ticked(s), ["rulers", "paths", "magic"], "magic needs paths, which need rulers")
	s.free()


func _tick(screen: NewGameScreen, key: String, on: bool) -> void:
	screen.call("set_" + key, on)


func test_the_line_under_the_boxes_says_which_systems_this_game_plays_with() -> void:
	var screen := _screen()
	assert_true(screen.systems_label.text.begins_with("All six systems are on."), screen.systems_label.text)
	screen.set_fog(false)
	assert_true(screen.systems_label.text.begins_with("Playing without Fog of war."), screen.systems_label.text)
	screen.set_rulers(false)
	assert_true(screen.systems_label.text.begins_with("Playing without Rulers, Paths, Magic and Fog of war."), screen.systems_label.text)
	screen.set_all_systems(false)
	assert_true(screen.systems_label.text.begins_with("Playing the basic game"), screen.systems_label.text)
	assert_true(screen.systems_label.text.contains("Paths need Rulers, and Magic needs Paths."), "the dependencies are on the line")
	assert_true(screen.systems_label.tooltip_text.contains(CodexLink.title("game_systems")), "and the tooltip links the codex")
	screen.free()


func test_each_box_says_what_it_adds_and_links_its_codex_entry() -> void:
	var screen := _screen()
	var seen := {}
	for k in KEYS:
		var box := _box(screen, k)
		assert_false(box.tooltip_text.is_empty(), "%s has a tooltip" % k)
		assert_true(box.tooltip_text.contains(CodexLink.title(ENTRIES[k])), "%s links its codex entry (%s)" % [k, ENTRIES[k]])
		assert_true(RulesCodex.ENTRIES.has(ENTRIES[k]), "and the entry exists")
		var line: String = NewGameScreen.system_line(k)
		assert_false(line.is_empty(), "%s has a line under its box" % k)
		assert_false(seen.has(line), "each line is its own")
		seen[line] = true
		var cell := box.get_parent() as Control
		assert_true(_all_text(cell).contains(line), "the line sits in the box's cell, with the tooltip: %s" % k)
		assert_true(box.tooltip_text.to_lower().contains("untick"), "%s says it can be unticked" % k)
	screen.free()
	# The codex: one entry names every box and what it adds, and says they are all on and each a choice.
	var entry := RulesCodex.entry("game_systems")
	assert_false(entry.is_empty(), "a codex entry for the systems")
	var text := String(entry.text)
	for k in KEYS:
		assert_true(text.contains(NAMES[k] + ":"), "the codex lists %s" % NAMES[k])
	assert_true(text.contains("every one starts ticked") and text.contains("untick"), "it says they start on and can be switched off")
	# And the first-game guide lists one line per system that is on, six in a default game.
	var game := GameScreen.starting_state(NewGameScreen.quick_start_config())
	var ids := FirstGameGuide.systems_on(game).map(func(s): return s.id)
	ids.sort()
	var want := KEYS.duplicate()
	want.sort()
	assert_eq(ids, want, "the guide has a line for each of the six systems")
	assert_eq(FirstGameGuide.systems_on(GameState.new(5)), [], "and none for the basic game")


func test_no_preview_wording_is_left_in_the_game() -> void:
	var label := RegEx.create_from_string("M[0-9]+[a-z]* preview|[A-Za-z&] \\(preview\\)\"|is a preview|are a preview")
	for dir in ["res://ui", "res://rules", "res://ai", "res://data"]:
		for path in _scripts_under(dir):
			var src := FileAccess.get_file_as_string(path)
			assert_true(label.search(src) == null, "%s has no preview label" % path)
	for id in RulesCodex.ENTRIES:
		assert_true(label.search(RulesCodex.text(id)) == null, "codex entry %s has no preview label" % id)
	# The refusals that used to send the player to a "(preview)" box send them to the box by its name.
	var plain := AscensionRules.check_research(GameState.with_rulers(7), CROWN, "crown_drillyard")
	assert_true(String(plain.reason).contains("Tick Paths") and not String(plain.reason).contains("preview"), plain.reason)
	assert_true(MagicRules.NO_MAGIC.contains("Tick Magic") and not MagicRules.NO_MAGIC.contains("preview"), MagicRules.NO_MAGIC)


func _scripts_under(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			out.append_array(_scripts_under(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	return out


# --- Quick start and Start ------------------------------------------------------------------------

func test_quick_start_turns_every_system_on() -> void:
	for dice_seed in range(1, 9):
		var rng := RandomNumberGenerator.new()
		rng.seed = dice_seed
		var cfg := NewGameScreen.quick_start_config(rng)
		for k in KEYS:
			assert_eq(cfg.get(k), true, "Quick start has %s (dice %d)" % [k, dice_seed])
		var state := GameScreen.starting_state(cfg)
		assert_true(state != null, "the config makes a game")
		if state == null:
			continue
		assert_eq(_systems_of(state), _all(true), "every system is in the game it starts (dice %d)" % dice_seed)
		var session := GameSession.new(state, cfg.players, cfg.seed, AutoBattleResolver.new(), cfg.ai)
		assert_eq(session.setup_errors(), [], "and the builds are legal (dice %d)" % dice_seed)


func test_quick_start_from_the_title_and_start_from_the_screen_play_the_same_systems() -> void:
	var title := _title()
	title.quick_start_button.pressed.emit()
	var game := title.next_scene as GameScreen
	assert_true(game != null, "Quick start switches to a game screen")
	if game:
		assert_eq(_systems_of(game.session.state()), _all(true), "Quick start plays with every system")
		for k in KEYS:
			assert_eq(game.config.get(k), true, "its config has %s, for a rematch" % k)
		game.free()
	title.free()
	var title2 := _title()
	title2.open_new_game()
	var setup := title2.new_game_screen
	setup.set_seed(77)
	setup.start_button.pressed.emit()
	assert_true(setup.build_screen_open(), "the default Start goes to the build screen first")
	setup.build_screen.lock_in()
	var game2 := title2.next_scene as GameScreen
	assert_true(game2 != null, "locking in your build starts the game")
	if game2:
		assert_eq(_systems_of(game2.session.state()), _all(true), "the default Start plays with every system")
		assert_eq(game2.session.setup_errors(), [])
		game2.free()
	title2.free()
	_cleanup()


func test_a_default_game_plays_ten_turns_against_the_computer() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var cfg := NewGameScreen.quick_start_config(rng)
	var session := GameSession.new(GameScreen.starting_state(cfg), cfg.players, cfg.seed, AutoBattleResolver.new(), cfg.ai)
	assert_eq(session.setup_errors(), [])
	var computer := AISeat.new(session, cfg.seed)
	var human: String = cfg.players[0]
	var brain := AIPlayer.new()
	brain.configure(cfg.seed, 0)
	var dice := SeededRNG.new(AISeat.seat_seed(cfg.seed + 1, 0))
	var guard := 0
	while not session.is_over() and session.turns_played() < 10 and guard < 80:
		guard += 1
		if session.phase() == GameSession.Phase.HANDOFF:
			session.acknowledge_handoff()
		elif session.is_computer_turn():
			computer.play(session)
		else:
			for o in brain.plan_orders(session.state_for(human), human, dice, "normal"):
				session.queue_order(o)
			assert_eq(session.end_turn(), "", "the person's turn ends")
	assert_true(session.is_over() or session.turns_played() >= 10, "the game ran %d turns" % session.turns_played())
	assert_eq(_systems_of(session.state()), _all(true), "every system is still in it")
	assert_true(session.state_for(human).fog, "and the person looks through the fog")


# --- with every box unticked: the M1 game, byte for byte ------------------------------------------

func _fixture_games() -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_true(data is Dictionary, "the fixture loads")
	return data.get("games", []) if data is Dictionary else []


func test_every_box_unticked_is_the_m1_game_byte_for_byte() -> void:
	var screen := _screen()
	screen.set_all_systems(false)
	screen.set_seat_kind(2, "human")
	assert_eq(screen.config().keys().size(), 2, "the config is exactly {players, seed}")
	var checked := {"m1": 0, "m2": 0}
	for g in _fixture_games():
		var rec: Dictionary = g.record
		var seed_value := Serial.to_int(rec.game_seed)
		assert_true(screen.set_seats(rec.players), "%s: the screen seats its players" % g.name)
		screen.set_seed(seed_value)
		var cfg := screen.config()
		var kind := "m1"
		if rec.has("builds"):  # an M2 record: the rulers box on its own, and the builds the build screen would hand over
			screen.set_rulers(true)
			cfg = screen.config()
			var builds := {}
			for fid in rec.builds:
				builds[fid] = {"ruler": rec.builds[fid].ruler, "mandates": rec.builds[fid].mandates}
			cfg["builds"] = builds
			screen.set_rulers(false)
			kind = "m2"
		var start := GameScreen.starting_state(cfg)
		var now := JSON.stringify(JSON.parse_string(JSON.stringify(start.to_dict())))
		assert_eq(now, JSON.stringify(rec.start_state), "%s: the starting save is byte-identical to main's" % g.name)
		assert_eq(_systems_of(start), {"rulers": kind == "m2", "paths": false, "sieges": false, "magic": false, "fog": false,
			"independents": false}, "%s: no system but the box that was ticked" % g.name)
		var d: Dictionary = start.to_dict()
		for key in ["paths", "sieges", "magic", "fog", "independents"]:
			assert_false(d.has(key), "%s: no '%s' key is saved" % [g.name, key])
		checked[kind] += 1
	assert_eq(checked, {"m1": 2, "m2": 3}, "the two M1 and three M2 records")
	screen.free()
	# And a game screen given no systems is that game: default_config() asks for none (the editor's Run Current Scene).
	assert_eq(_systems_of(GameScreen.starting_state(GameScreen.default_config())), _all(false), "default_config() is the basic game")


# --- rematches and saved games --------------------------------------------------------------------

func test_a_rematch_starts_from_the_last_games_systems() -> void:
	var screen := _screen()
	var last := {"players": [CROWN, CLANS], "seed": 5}
	screen.prefill(last)
	assert_eq(_ticked(screen), [], "a game with no systems rematches as that game, not with the new defaults")
	last["rulers"] = true
	last["independents"] = true  # what Quick start gave before the flip
	last["builds"] = {CROWN: RulerRules.preset_build(RulerRules.balanced_preset(CROWN))}
	screen.prefill(last)
	assert_eq(_ticked(screen), ["rulers", "independents"], "a pre-flip Quick start game keeps its two")
	last.merge(_all(true))
	screen.prefill(last)
	assert_eq(_ticked(screen), KEYS, "a game with every system rematches with every system")
	screen.prefill({"players": [CROWN, CLANS], "seed": 5, "rulers": true, "paths": true, "sieges": true})
	assert_eq(_ticked(screen), ["rulers", "paths", "sieges"], "and a part of them with that part")
	screen.free()


## The systems a config asks for, as the saved game of it holds them.
func _config_with(systems: Array) -> Dictionary:
	var cfg := {"players": [CROWN, CLANS], "seed": 31, "ai": {CLANS: "normal"}}
	for k in systems:
		cfg[k] = true
	if systems.has("rulers"):
		cfg["builds"] = {CROWN: RulerRules.preset_build(RulerRules.balanced_preset(CROWN)),
			CLANS: BuildScreen.computer_build(CLANS, 31, 1)}
	return cfg


func _human_orders(session: GameSession) -> void:
	var state := session.state()
	var fid := session.current_player()
	for ut in state.find_faction(fid).unit_types:
		session.queue_recruit(ut.id)
	for a in state.armies:
		if a.owner == fid:
			for n in state.find_province(a.location).neighbors:
				if session.queue_move(a.id, n).is_empty():
					return


func _play_turn(session: GameSession, computer: AISeat) -> void:
	var start := session.turns_played()
	for guard in 8:
		if session.turns_played() > start or session.is_over():
			return
		if session.phase() == GameSession.Phase.HANDOFF:
			session.acknowledge_handoff()
		elif session.is_computer_turn():
			computer.play(session)
		else:
			_human_orders(session)
			session.end_turn()


func test_saved_games_load_with_their_own_systems() -> void:
	# The shapes games were saved in before the flip (nothing, the old default's rulers, Quick start's rulers and independents)
	# and after it (everything), each as it was.
	var shapes := [[], ["rulers"], ["rulers", "independents"], ["sieges"], KEYS]
	for systems in shapes:
		var cfg := _config_with(systems)
		var session := GameSession.new(GameScreen.starting_state(cfg), cfg.players, cfg.seed, AutoBattleResolver.new(), cfg.ai)
		assert_eq(session.setup_errors(), [], "%s: the game starts" % [systems])
		var computer := AISeat.new(session, cfg.seed)
		for t in 2:
			_play_turn(session, computer)
		var save: Dictionary = JSON.parse_string(JSON.stringify(SaveGame.make(session, SaveGame.computer_snapshot(computer, session),
			SaveGame.MANUAL, "Test save", SAVED_AT)))
		var restored := SaveGame.restore(save)
		assert_eq(restored.errors, [], "%s: the save loads" % [systems])
		var loaded: GameSession = restored.session
		if loaded == null:
			continue
		var want := _all(false)
		for k in systems:
			want[k] = true
		assert_eq(_systems_of(loaded.state()), want, "%s: it loads with exactly its own systems, whatever the defaults are" % [systems])
		assert_eq(var_to_str(loaded.state().to_dict()), var_to_str(session.state().to_dict()), "%s: the same state" % [systems])
		# Its config, for a rematch, names those systems and no others ...
		for k in ["paths", "sieges", "magic", "fog", "independents"]:
			assert_eq(restored.config.has(k), want[k], "%s: the loaded game's config %s %s" % [systems, "has" if want[k] else "lacks", k])
		assert_eq(restored.config.has("rulers"), want.rulers)
		# ... and the game screen that plays it keeps them.
		var made := SceneFlow.make_loaded_game(save)
		assert_eq(made.error, "", "%s: the game screen loads it" % [systems])
		var game: GameScreen = made.game
		if game:
			assert_eq(_systems_of(game.session.state()), want, "%s: the game screen plays its own systems" % [systems])
			for k in KEYS:
				assert_eq(game.config.get(k, false), want[k], "%s: and its config says so (%s)" % [systems, k])
			# A rematch of it ticks those boxes and no others.
			var screen := _screen()
			screen.prefill(game.config)
			assert_eq(_ticked(screen), KEYS.filter(func(k): return want[k]), "%s: the rematch has the same boxes" % [systems])
			screen.free()
			game.free()


# --- the settings file ----------------------------------------------------------------------------

func _write_old_settings(path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "window_mode", "fullscreen")
	cfg.set_value("settings", "ui_scale", 125)
	cfg.set_value("battle", "speed", 2)
	cfg.set_value("hints", "fog", true)
	assert_eq(cfg.save(path), OK)


func _opened(path: String) -> NewGameScreen:
	var screen := _screen()
	screen.settings_file = path
	screen._ready()  # what the engine does when the screen enters the tree
	return screen


func test_a_settings_file_from_before_the_flip_gets_one_line_once() -> void:
	var path := _settings_path()
	_write_old_settings(path)
	assert_true(GameSettings.defaults_notice_due(path), "a file with no stamp is from before the flip")
	var first := _opened(path)
	assert_true(first.defaults_label.visible, "the first time the screen opens it says so")
	assert_eq(first.defaults_label.text, NewGameScreen.DEFAULTS_NOTICE)
	assert_true(first.defaults_label.text.contains("every system now starts ticked"), first.defaults_label.text)
	assert_eq(String(first.defaults_label.get_parent().name), "TitleRow", "beside the title, so it takes no room from the boxes")
	assert_eq(_ticked(first), KEYS, "and the new defaults are what is ticked: the old ones are not kept")
	assert_false(GameSettings.defaults_notice_due(path), "it is marked as told")
	first.free()
	var second := _opened(path)
	assert_false(second.defaults_label.visible, "the second time it says nothing")
	assert_eq(_ticked(second), KEYS, "the defaults are the same")
	second.free()
	# The rest of the file is as it was.
	var back := GameSettings.load_from(path)
	assert_eq(back.window_mode, "fullscreen")
	assert_eq(back.ui_scale, 125)
	assert_eq(BattleFx.settings(path).speed, 2, "the battle section is kept")
	assert_true(GameSettings.hint_seen("fog", path), "and the hints")
	_cleanup()


func test_a_new_player_and_the_files_this_version_writes_get_no_line() -> void:
	var path := _settings_path()
	assert_false(GameSettings.defaults_notice_due(path), "no file at all: a new player")
	var fresh := _opened(path)
	assert_false(fresh.defaults_label.visible)
	fresh.free()
	assert_false(FileAccess.file_exists(path), "and opening the screen writes nothing")
	# Whatever writes the file first stamps it, so a new player is never told about defaults they never had.
	var by_settings := _settings_path()
	assert_eq(GameSettings.new(by_settings).save(), "")
	assert_false(GameSettings.defaults_notice_due(by_settings), "the settings panel's save")
	var by_hint := _settings_path()
	assert_eq(GameSettings.mark_hint_seen("fog", by_hint), "")
	assert_false(GameSettings.defaults_notice_due(by_hint), "a hint marked first")
	var by_battle := _settings_path()
	assert_eq(BattleFx.save_settings({"speed": 2}, by_battle), "")
	assert_false(GameSettings.defaults_notice_due(by_battle), "the battle screen's settings")
	# A file from before the flip stays due until the player has been told, whatever else writes to it.
	var old := _settings_path()
	_write_old_settings(old)
	assert_eq(GameSettings.new(old).save(), "")
	assert_eq(GameSettings.mark_hint_seen("first_game_guide", old), "")
	assert_eq(BattleFx.save_settings({"speed": 4}, old), "")
	assert_true(GameSettings.defaults_notice_due(old), "saving other settings does not use up the line")
	_cleanup()
