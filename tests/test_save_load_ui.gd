extends "res://tests/test_case.gd"
## Saving and loading through the real screens, headless, each test with its own temporary save folder
## (never the real user://saves): the start-of-turn autosave and its rotation (the last three), Menu >
## Save game with a name or the timestamped default, the load screen with its header info and delete
## with a question first, Continue only when there is a save, a loaded game that plays on exactly like
## the original, a loaded hotseat game that opens on the handoff cover, damaged saves explained in plain
## words, and no raw ids on any of these screens.

const TITLE_SCENE := "res://ui/title_screen.tscn"
const GAME_SCENE := "res://ui/game_screen.tscn"
const RAW_IDS := ["kingdom", "beasts", "crownkeep", "fangridge", "westwatch", "ebonpeak", "stonegate",
	"blackwood", "highcrag", "ironspike", "rivermarch", "bloodfen", "thornvale", "wildmoor", "greenglade",
	"deepwood", "knight_captain", "warchief", "war_bear", "spearmen", "tuskers", "codex:", "battle_", "trait_",
	"beasts-", "kingdom-", "regents_court", "clan_moot", "ever_regent", "fang_chieftain", "auto_", "save_0", ".json"]
const JARGON := ["Dictionary", "Array", "String", "Nil", "null", "Variant", "Invalid", "SCRIPT", "JSON"]

var _folders: Array = []


## A fresh, empty save folder for this test (removed again by _cleanup).
func _store() -> SaveStore:
	var folder := "user://test_saves_%d_%d" % [Time.get_ticks_usec(), randi()]
	_folders.append(folder)
	return SaveStore.new(folder)


func _cleanup() -> void:
	for folder in _folders:
		SaveStore.new(folder).clear()
		DirAccess.remove_absolute(folder)
	_folders = []


## A game screen running `config`, saving to `store`.
func _game(config: Dictionary, store: SaveStore) -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.save_store = store
	game.start_game(config)
	return game


## A title screen using `store` for its saves, set up the way the engine would show it.
func _title(store: SaveStore) -> TitleScreen:
	var title := load(TITLE_SCENE).instantiate() as TitleScreen
	title.store = store
	title._bind()
	return title


## End turn for whoever is at the controls, pressing Ready on the handoff cover when it comes up,
## until the turn resolves.
func _end_turn(game: GameScreen) -> void:
	var start := game.session.turns_played()
	for guard in 6:
		if game.session.turns_played() > start or game.session.is_over():
			return
		if game.handoff.visible:
			game.handoff.ready_button.pressed.emit()
		else:
			game.end_turn()


## The person at the controls recruits once at the capital if they can.
func _recruit(game: GameScreen) -> void:
	var f := game.session.state().find_faction(game.session.current_player())
	for ut in f.unit_types:
		if game.session.queue_recruit(ut.id).is_empty():
			return


func _visible_text(node: Node) -> String:
	var out := PackedStringArray()
	_collect_text(node, out)
	return "\n".join(out)


func _collect_text(node: Node, out: PackedStringArray) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	elif node is LineEdit:
		out.append((node as LineEdit).text + " " + (node as LineEdit).placeholder_text)
	for c in node.get_children():
		_collect_text(c, out)


func _assert_no_raw_ids(text: String, what: String) -> void:
	assert_false(text.is_empty(), "%s has text" % what)
	for id in RAW_IDS:
		assert_false(text.contains(id), "%s shows no raw id '%s'" % [what, id])


func _assert_plain(text: String, what: String) -> void:
	assert_true(text.length() > 20 and text.ends_with("."), "%s: a sentence: %s" % [what, text])
	for word in JARGON:
		assert_false(text.contains(word), "%s: no '%s' in: %s" % [what, word, text])


# --- autosave -------------------------------------------------------------------------------------

func test_autosave_at_the_start_of_every_turn_keeps_the_last_three() -> void:
	var store := _store()
	var game := _game({"players": ["kingdom", "beasts"], "seed": 8, "ai": {"beasts": "normal"}}, store)
	assert_eq(store.autosaves().size(), 1, "turn 1 is saved as it starts")
	assert_eq(int(store.autosaves()[0].header.turn), 1)
	for i in 5:
		_recruit(game)
		_end_turn(game)
	var autos := store.autosaves()
	assert_eq(autos.size(), SaveStore.AUTOSAVES_KEPT, "only the last three autosaves are kept")
	assert_eq(autos.map(func(e): return int(e.header.turn)), [6, 5, 4], "the newest first: the start of turns 6, 5 and 4")
	for e in autos:
		assert_eq(e.header.kind, SaveGame.AUTO)
		assert_eq(e.header.name, "Autosave")
	# A manual save is never rotated away.
	assert_eq(game.save_game("Keep me"), "")
	for i in 3:
		_end_turn(game)
	assert_eq(store.autosaves().size(), 3)
	assert_eq(store.list().filter(func(e): return e.kind == SaveGame.MANUAL).size(), 1, "the manual save is still there")
	game.free()
	_cleanup()


func test_the_autosave_has_the_computers_dice_from_the_start_of_the_turn() -> void:
	# The computer in seat 1 plans as soon as the turn starts; the autosave is taken just before.
	var store := _store()
	var game := _game({"players": ["beasts", "kingdom"], "seed": 12, "ai": {"beasts": "normal"}}, store)
	var before: Dictionary = game._snapshot.rng  # the start of turn 1, before the computer planned it
	assert_ne(before, game.computer.rng_state(), "the computer has planned turn 1 on screen")
	_end_turn(game)
	var save: Dictionary = store.read(store.latest().path).save
	var loaded := SaveGame.restore(save, AutoBattleResolver.new())
	assert_eq(loaded.errors, [])
	assert_ne(loaded.computer.rng_state(), before, "the dice moved on during turn 1")
	assert_ne(loaded.computer.rng_state(), game.computer.rng_state(), "and the computer has already planned turn 2 on screen")
	# Loading and letting the computer plan turn 2 again gives the dice the game has now.
	loaded.computer.play(loaded.session)
	assert_eq(loaded.computer.rng_state(), game.computer.rng_state(), "the same plan from the same dice")
	game.free()
	_cleanup()


# --- manual save, the menu ------------------------------------------------------------------------

func test_menu_save_with_a_name_or_the_timestamped_default() -> void:
	var store := _store()
	var game := _game({"players": ["kingdom", "beasts"], "seed": 21, "ai": {"beasts": "normal"}, "rulers": true}, store)
	assert_eq(game.map.back_button.text, "Menu")
	game.map.back_button.pressed.emit()
	assert_true(game.menu_overlay.visible, "the top bar's Menu opens the menu")
	assert_eq(game.menu_text.text, "Turn 1. Autosaved when it began.")
	_assert_no_raw_ids(_visible_text(game.menu_overlay), "the menu")
	(game.menu_overlay.find_child("SaveGameButton", true, false) as Button).pressed.emit()
	assert_true(game.save_overlay.visible, "Save game opens the save dialog")
	assert_true(game.save_note.text.contains("not saved"), "it says queued orders are not saved: %s" % game.save_note.text)
	assert_true(game.save_name_edit.placeholder_text.begins_with("Saved "), "a timestamped default: %s" % game.save_name_edit.placeholder_text)
	_assert_no_raw_ids(_visible_text(game.save_overlay), "the save dialog")
	game.save_name_edit.text = "Before the push"
	(game.save_overlay.find_child("ConfirmSaveButton", true, false) as Button).pressed.emit()
	assert_false(game.save_overlay.visible, "the dialog closes")
	assert_false(game.menu_overlay.visible, "and so does the menu")
	assert_true(game.notice_panel.visible and game.notice_label.text.contains("Before the push"), "a notice says it was saved")
	var manual := store.list().filter(func(e): return e.kind == SaveGame.MANUAL)
	assert_eq(manual.size(), 1)
	assert_eq(manual[0].header.name, "Before the push")
	assert_eq(int(manual[0].header.turn), 1)
	# An empty name keeps the default.
	game.open_save_dialog()
	var default_name := game.save_name_edit.placeholder_text
	assert_eq(game.confirm_save(), "")
	var names := store.list().filter(func(e): return e.kind == SaveGame.MANUAL).map(func(e): return e.header.name)
	assert_true(names.has(default_name), "%s in %s" % [default_name, names])
	game.free()
	_cleanup()


func test_quit_asks_first_and_says_what_is_saved() -> void:
	var store := _store()
	var game := _game({"players": ["kingdom", "beasts"], "seed": 4, "ai": {"beasts": "normal"}}, store)
	game.open_menu()
	(game.menu_overlay.find_child("QuitToTitleButton", true, false) as Button).pressed.emit()
	assert_true(game.quit_overlay.visible, "Quit to title asks first")
	assert_true(game.quit_text.text.contains("saved itself at the start of turn 1"), game.quit_text.text)
	assert_true(game.quit_text.text.contains("not saved"), game.quit_text.text)
	(game.quit_overlay.find_child("ConfirmQuitButton", true, false) as Button).pressed.emit()
	assert_true(game.next_scene is TitleScreen, "confirming goes to the title")
	if game.next_scene:
		game.next_scene.free()
	game.free()
	_cleanup()


# --- loading --------------------------------------------------------------------------------------

func test_a_loaded_game_plays_on_exactly_like_the_original() -> void:
	var store := _store()
	var config := {"players": ["kingdom", "beasts"], "seed": 33, "ai": {"beasts": "normal"}, "rulers": true,
		"builds": {"kingdom": RulerRules.preset_build(RulerRules.balanced_preset("kingdom")), "beasts": BuildScreen.computer_build("beasts", 33, 1)}}
	var a := _game(config, store)
	for i in 3:
		_recruit(a)
		_end_turn(a)
	var b := load(GAME_SCENE).instantiate() as GameScreen
	b.save_store = _store()
	assert_eq(b.load_game(store.read(store.latest().path).save), "")
	assert_eq(b.session.turn_number(), 4)
	assert_eq(var_to_str(b.session.state().to_dict()), var_to_str(a.session.state().to_dict()), "the same state")
	for key in ["players", "seed", "ai", "rulers"]:
		assert_eq(b.config[key], a.config[key], "the same %s, so a rematch is the same setup" % key)
	for fid in a.config.builds:
		assert_eq(b.config.builds[fid].ruler, a.config.builds[fid].ruler, "the same ruler for the rematch")
		assert_eq(b.config.builds[fid].mandates, a.config.builds[fid].mandates, "and mandates")
	assert_true(b.notice_panel.visible, "a notice says the game was loaded")
	assert_true(b.notice_label.text.contains("start of turn 4") and b.notice_label.text.contains("not saved"), b.notice_label.text)
	assert_true(b.report_overlay.visible, "the last turn's report opens again")
	assert_eq(b.session.current_player(), "kingdom", "the person gives orders")
	assert_false(b.handoff.visible, "one person: no cover")
	for i in 3:
		for game in [a, b]:
			_recruit(game)
			_end_turn(game)
	assert_eq(var_to_str(b.session.state().to_dict()), var_to_str(a.session.state().to_dict()), "three turns later, still the same")
	assert_eq(b.session.history(), a.session.history())
	a.free()
	b.free()
	_cleanup()


func test_a_loaded_hotseat_game_opens_on_the_handoff_cover() -> void:
	var store := _store()
	var game := _game({"players": ["beasts", "kingdom"], "seed": 2}, store)
	assert_false(game.handoff.visible, "a new hotseat game opens on player 1's orders")
	for turns in [0, 2]:
		for i in turns:
			_end_turn(game)
		var loaded := SceneFlow.make_loaded_game(store.read(store.latest().path).save)
		var b: GameScreen = loaded.game
		assert_eq(loaded.error, "")
		if b == null:
			continue
		assert_true(b.handoff.visible, "after %d turns: the handoff cover is up" % turns)
		assert_false(b.map.visible, "and the map is hidden")
		assert_eq(b.session.phase(), GameSession.Phase.HANDOFF)
		assert_eq(b.session.current_orders(), [], "no orders on show")
		assert_eq(b.handoff.title_label.text, "Pass to Thornmane Clans")
		_assert_no_raw_ids(_visible_text(b.handoff), "the handoff cover after loading")
		b.handoff.ready_button.pressed.emit()
		assert_true(b.map.visible, "Ready shows player 1's map")
		assert_eq(b.session.current_player(), "beasts")
		b.free()
	game.free()
	_cleanup()


func test_menu_load_replaces_the_game_in_place() -> void:
	var store := _store()
	var game := _game({"players": ["kingdom", "beasts"], "seed": 9, "ai": {"beasts": "easy"}}, store)
	_end_turn(game)
	_end_turn(game)
	assert_eq(game.session.turn_number(), 3)
	game.open_menu()
	(game.menu_overlay.find_child("LoadGameButton", true, false) as Button).pressed.emit()
	assert_true(game.load_screen.visible, "Load game opens the load screen")
	assert_eq(game.load_screen.entries.size(), 3)
	game.load_screen.load_entry(2)  # the oldest: the start of turn 1
	assert_false(game.load_screen.visible, "loading closes it")
	assert_eq(game.session.turn_number(), 1, "back at turn 1")
	assert_eq(game.session.turns_played(), 0)
	game.free()
	_cleanup()


# --- the load screen ------------------------------------------------------------------------------

func test_the_load_screen_lists_saves_with_their_header_and_deletes_after_asking() -> void:
	var store := _store()
	var game := _game({"players": ["kingdom", "beasts"], "seed": 14, "ai": {"beasts": "normal"}, "rulers": true}, store)
	_end_turn(game)
	assert_eq(game.save_game("My push"), "")
	game.free()
	var title := _title(store)
	title.load_button.pressed.emit()
	var screen := title.load_screen
	assert_true(screen != null and screen.visible, "Load game opens the load screen over the title")
	assert_eq(screen.entries.size(), 3, "two autosaves and the manual save")
	assert_eq(screen.entries[0].header.name, "My push", "newest first")
	var row: Control = screen.rows[0]
	var text := _visible_text(row)
	for part in ["My push", "Turn 2", "Aurel Crown (you)", "Thornmane Clans (Computer, Normal)", "Rulers", "Turn 2: Aurel Crown holds"]:
		assert_true(text.contains(part), "the row shows '%s': %s" % [part, text])
	_assert_no_raw_ids(_visible_text(screen), "the load screen")
	# Delete asks first; Keep it keeps it.
	(row.find_child("DeleteButton", true, false) as Button).pressed.emit()
	assert_true(screen.confirm_overlay.visible, "Delete asks first")
	assert_true(screen.confirm_label.text.contains("My push"), screen.confirm_label.text)
	screen.cancel_delete()
	assert_eq(store.list().size(), 3, "Keep it deletes nothing")
	screen.ask_delete(0)
	(screen.confirm_overlay.find_child("ConfirmDeleteButton", true, false) as Button).pressed.emit()
	assert_eq(store.list().size(), 2, "Delete deletes it")
	assert_eq(screen.entries.size(), 2, "and the list is redrawn")
	assert_false(screen.entries.any(func(e): return e.header.name == "My push"))
	screen.back_button.pressed.emit()
	assert_false(screen.visible)
	title.free()
	_cleanup()


func test_an_empty_load_screen_says_so() -> void:
	var title := _title(_store())
	title.open_load_screen()
	assert_true(title.load_screen.empty_label.visible)
	assert_true(title.load_screen.empty_label.text.begins_with("No saved games yet."))
	title.free()
	_cleanup()


# --- the title's Continue -------------------------------------------------------------------------

func test_continue_appears_only_when_there_is_a_save() -> void:
	var store := _store()
	var title := _title(store)
	assert_false(title.continue_button.visible, "no save: no Continue")
	title.free()
	var game := _game({"players": ["kingdom", "beasts"], "seed": 17, "ai": {"beasts": "normal"}}, store)
	_end_turn(game)
	game.free()
	title = _title(store)
	assert_true(title.continue_button.visible, "with a save: Continue")
	assert_eq(title.continue_button.get_index(), title.new_game_button.get_index() - 1, "first, above New game")
	assert_true(title.continue_button.tooltip_text.contains("Autosave"), title.continue_button.tooltip_text)
	title.continue_button.pressed.emit()
	var loaded := title.next_scene as GameScreen
	assert_true(loaded != null, "Continue switches to the game")
	if loaded:
		assert_eq(loaded.session.turn_number(), 2, "at the start of the latest saved turn")
		loaded.free()
	title.free()
	# Every save deleted: no Continue again.
	store.clear()
	title = _title(store)
	assert_false(title.continue_button.visible)
	title.free()
	_cleanup()


func test_damaged_and_newer_saves_are_explained_never_a_crash() -> void:
	var store := _store()
	var game := _game({"players": ["kingdom", "beasts"], "seed": 6, "ai": {"beasts": "normal"}}, store)
	game.free()
	var good: Dictionary = store.read(store.latest().path).save
	DirAccess.make_dir_recursive_absolute(store.root)
	# A file cut short, one from a newer version, and one whose game was changed.
	_write(store.root.path_join("save_000101.json"), "{\"format\": \"ascendant-save\", \"vers")
	var newer := good.duplicate(true)
	newer.version = SaveGame.VERSION + 1
	newer.header.saved_at = 1
	_write(store.root.path_join("save_000102.json"), JSON.stringify(newer))
	var changed := good.duplicate(true)
	changed.record.start_state = "x"
	changed.header.name = "Changed"
	changed.header.saved_at = int(good.header.saved_at) + 100
	_write(store.root.path_join("save_000103.json"), JSON.stringify(changed))
	var title := _title(store)
	title.open_load_screen()
	var screen := title.load_screen
	assert_eq(screen.entries.size(), 4)
	var damaged := screen.entries.filter(func(e): return not e.errors.is_empty())
	assert_eq(damaged.size(), 2, "the cut-short file and the newer one can't be read")
	for i in screen.entries.size():
		var e: Dictionary = screen.entries[i]
		var load_button := screen.rows[i].find_child("LoadButton", true, false) as Button
		assert_eq(load_button.visible, e.errors.is_empty(), "a damaged save can only be deleted")
		if not e.errors.is_empty():
			_assert_plain(SaveGame.error_text(e.errors), "a damaged save in the list")
	assert_true(_visible_text(screen).contains("newer version of Ascendant"))
	# The changed save reads, but can't be replayed: the reason shows on the load screen, nothing switches.
	var index := screen.entries.map(func(e): return e.header.get("name", "")).find("Changed")
	assert_true(index >= 0)
	screen.load_entry(index)
	assert_eq(title.next_scene, null, "nothing switches")
	assert_true(screen.error_label.visible)
	_assert_plain(screen.error_label.text, "loading a changed save")
	assert_true(screen.error_label.text.begins_with(SaveGame.DAMAGED), screen.error_label.text)
	# Continue picks the newest save that reads ("Changed"), and explains on the title when it can't load.
	screen.back()
	title.continue_game()
	assert_eq(title.next_scene, null)
	assert_true(title.error_label.visible)
	_assert_plain(title.error_label.text, "Continue on a changed save")
	_assert_no_raw_ids(_visible_text(title), "the title with an error")
	title.free()
	_cleanup()


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
