extends "res://tests/test_case.gd"
## New game screen (#8): seats pick distinct factions, the seed is random by default and must be a
## whole number, problems are explained and disable Start, Swap works, and Start emits exactly
## {"players": [faction ids in seat order], "seed": int}, the config GameScreen.start_game takes.

const SCENE := "res://ui/new_game_screen.tscn"
const RAW_IDS := ["kingdom", "beasts", "crownkeep", "fangridge", "knight_captain", "warchief", "spearmen",
	"tuskers", "war_bear", "codex:", "_"]


## The screen set up for the M1 hotseat game these tests are about: both seats human, no system box ticked. (The
## MVP default, you against the computer with every system, is tested in tests/test_mvp_defaults.gd and
## tests/test_defaults_flip.gd.)
func _screen() -> NewGameScreen:
	var screen := load(SCENE).instantiate() as NewGameScreen
	assert_true(screen != null, "scene instantiates as NewGameScreen")
	if screen:
		assert_true(screen.set_seat_kind(2, "human"))
		screen.set_all_systems(false)
	return screen


func _type_seed(screen: NewGameScreen, text: String) -> void:
	screen.seed_edit.text = text
	screen.seed_edit.text_changed.emit(text)


func _visible_controls(node: Node, out: Array) -> Array:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return out
	if node is Control:
		out.append(node)
	for c in node.get_children():
		_visible_controls(c, out)
	return out


func _visible_text(node: Node) -> String:
	var out := PackedStringArray()
	for c in _visible_controls(node, []):
		if c is Label or c is Button:
			out.append(c.text)
		if not c.tooltip_text.is_empty():
			out.append(c.tooltip_text)
		if c is OptionButton:
			for i in c.item_count:
				out.append(c.get_item_text(i))
				out.append(c.get_popup().get_item_tooltip(i))
	return "\n".join(out)


func _has_digit(text: String) -> bool:
	for ch in text:
		if ch >= "0" and ch <= "9":
			return true
	return false


func _assert_no_raw_ids(text: String, where: String) -> void:
	assert_false(text.is_empty(), "%s has text" % where)
	for id in RAW_IDS:
		assert_false(text.contains(id), "%s shows no raw id '%s'" % [where, id])


# --- tests ----------------------------------------------------------------------------------------

func test_hotseat_config_is_valid_with_distinct_factions_and_an_int_seed() -> void:
	var screen := _screen()
	var cfg := screen.config()
	var keys := cfg.keys()
	keys.sort()
	assert_eq(keys, ["players", "seed"], "exactly the two keys GameScreen.start_game reads")
	assert_eq(cfg.players.size(), 2)
	assert_ne(cfg.players[0], cfg.players[1], "two different factions")
	var known := FactionData.FACTIONS.map(func(f): return f.id)
	for fid in cfg.players:
		assert_true(known.has(fid), "%s is a faction from the data" % fid)
	assert_eq(cfg.players, ["kingdom", "beasts"], "Player 1 takes the first faction by default")
	assert_eq(typeof(cfg.seed), TYPE_INT, "the seed is an int")
	assert_true(cfg.seed >= 1 and cfg.seed <= NewGameScreen.MAX_RANDOM_SEED, "a random seed: %d" % cfg.seed)
	assert_eq(screen.seed_edit.text, str(cfg.seed), "the field shows the seed")
	assert_true(screen.is_valid())
	assert_eq(screen.error_text(), "")
	assert_false(screen.start_button.disabled)
	assert_false(screen.error_label.visible)
	assert_eq(screen.faction_ids(), ["kingdom", "beasts"])
	assert_eq(screen.seat_faction(1), "kingdom")
	assert_eq(screen.seat_faction(2), "beasts")
	assert_eq(screen.seat_faction(3), "")
	# The config starts a real game.
	var session := GameSession.new(GameState.new(cfg.seed), cfg.players, cfg.seed)
	assert_eq(session.setup_errors(), [], "GameSession accepts the config")
	screen.free()


func test_same_faction_twice_is_rejected_with_a_reason() -> void:
	var screen := _screen()
	var started := []
	screen.start_requested.connect(func(c: Dictionary): started.append(c))
	assert_true(screen.select_faction(2, "kingdom"))
	assert_false(screen.is_valid())
	assert_eq(screen.error_text(), "Player 1 and Player 2 both picked Aurel Crown. Each player needs a different faction.")
	assert_true(screen.error_label.visible)
	assert_eq(screen.error_label.text, screen.error_text())
	assert_true(screen.start_button.disabled, "Start is disabled")
	assert_true(screen.start_button.tooltip_text.contains("different faction"), "the disabled Start says why")
	assert_false(screen.start())
	screen.start_button.pressed.emit()
	assert_eq(started, [], "nothing starts with the same faction twice")
	_assert_no_raw_ids(_visible_text(screen), "same-faction error")

	# Picking through the dropdown works the same way.
	assert_true(screen.select_faction(2, "beasts"))
	assert_true(screen.is_valid())
	screen.seat_pickers[0].select(1)
	screen.seat_pickers[0].item_selected.emit(1)
	assert_false(screen.is_valid())
	assert_true(screen.error_text().contains("Thornmane Clans"), screen.error_text())
	screen.seat_pickers[0].select(0)
	screen.seat_pickers[0].item_selected.emit(0)
	assert_true(screen.is_valid())
	assert_false(screen.start_button.disabled)

	assert_false(screen.select_faction(3, "kingdom"), "no third seat")
	assert_false(screen.select_faction(1, "no_such_faction"), "unknown faction")
	assert_eq(screen.config().players, ["kingdom", "beasts"], "rejected calls change nothing")
	screen.free()


func test_invalid_seed_is_rejected_with_a_reason() -> void:
	var screen := _screen()
	for bad in ["", "   ", "abc", "12.5", "-4", "1e9", "42 7", "1234567890123456789"]:
		_type_seed(screen, bad)
		assert_false(screen.is_valid(), "'%s' is not a valid seed" % bad)
		assert_false(screen.error_text().is_empty(), "'%s' is explained" % bad)
		assert_true(screen.start_button.disabled, "'%s' disables Start" % bad)
		assert_true(screen.error_label.visible)
		assert_false(screen.start(), "'%s' does not start" % bad)
	_type_seed(screen, "")
	assert_eq(screen.error_text(), "Enter a seed, or press New seed for a random one.")
	_type_seed(screen, "abc")
	assert_eq(screen.error_text(), "The seed must be a whole number made of digits only, like 482913.")
	_type_seed(screen, "1234567890123456789")
	assert_eq(screen.error_text(), "The seed can have at most 18 digits.")

	_type_seed(screen, " 42 ")
	assert_true(screen.is_valid(), "spaces around the number are fine")
	assert_eq(screen.config().seed, 42)
	_type_seed(screen, "123456789012345678")
	assert_true(screen.is_valid(), "18 digits fit")
	assert_eq(screen.config().seed, 123456789012345678)
	screen.set_seed(7)
	assert_eq(screen.seed_edit.text, "7")
	assert_eq(screen.config().seed, 7)
	assert_false(screen.start_button.disabled)
	assert_false(screen.error_label.visible)

	# Both problems at once are both listed.
	_type_seed(screen, "x")
	screen.select_faction(1, "beasts")
	assert_eq(screen.error_text().split("\n").size(), 2, screen.error_text())
	screen.free()


func test_swap_seats() -> void:
	var screen := _screen()
	screen.set_seed(99)
	assert_eq(screen.config().players, ["kingdom", "beasts"])
	screen.swap_seats()
	assert_eq(screen.config().players, ["beasts", "kingdom"])
	assert_eq(screen.seat_pickers[0].get_item_text(screen.seat_pickers[0].selected), "Thornmane Clans", "the dropdown follows")
	assert_true(screen.faction_labels[0].text.contains("Fangridge"), "seat 1's summary follows: %s" % screen.faction_labels[0].text)
	screen.swap_button.pressed.emit()
	assert_eq(screen.config().players, ["kingdom", "beasts"])
	assert_eq(screen.config().seed, 99, "swapping keeps the seed")
	screen.free()


func test_start_payload_is_exact() -> void:
	var screen := _screen()
	var started := []
	screen.start_requested.connect(func(c: Dictionary): started.append(c))
	screen.set_seed(12345)
	screen.start_button.pressed.emit()
	assert_eq(started.size(), 1, "Start emits once")
	assert_eq(started[0], {"players": ["kingdom", "beasts"], "seed": 12345})
	assert_eq(typeof(started[0].seed), TYPE_INT)
	screen.swap_seats()
	assert_true(screen.start())
	assert_eq(started[1], {"players": ["beasts", "kingdom"], "seed": 12345})
	# Enter in the seed field starts too.
	screen.seed_edit.text_submitted.emit("12345")
	assert_eq(started.size(), 3)
	assert_eq(started[2], screen.config())
	screen.free()


func test_new_seed_button_picks_a_valid_random_seed() -> void:
	var screen := _screen()
	var seen := {}
	for i in 6:
		screen.new_seed_button.pressed.emit()
		var cfg := screen.config()
		assert_true(screen.is_valid())
		assert_eq(typeof(cfg.seed), TYPE_INT)
		assert_eq(screen.seed_edit.text, str(cfg.seed))
		seen[cfg.seed] = true
	assert_true(seen.size() >= 2, "new seeds differ")
	assert_eq(typeof(screen.new_seed()), TYPE_INT)
	screen.free()


func test_hotseat_explanation_comes_from_the_codex() -> void:
	var screen := _screen()
	assert_eq(screen.hotseat_label.text, RulesCodex.text("hotseat"))
	assert_true(_visible_text(screen).contains(String(RulesCodex.entry("hotseat").title)))
	screen.free()


## Rematch (M1 polish): prefill() keeps the last game's seating and picks a new seed.
func test_rematch_prefill_keeps_the_seating_with_a_new_seed() -> void:
	var screen := _screen()
	assert_false(screen.rematch_label.visible, "a plain new game says nothing about a rematch")
	screen.prefill({"players": ["beasts", "kingdom"], "seed": 4242})
	assert_eq(screen.seat_faction(1), "beasts", "Player 1 keeps their faction")
	assert_eq(screen.seat_faction(2), "kingdom", "and so does Player 2")
	assert_true(screen.is_valid(), screen.error_text())
	assert_ne(screen.config().seed, 4242, "with a new seed")
	assert_true(screen.rematch_label.visible, "and the screen says why the seats are already set")
	assert_true(screen.faction_labels[0].text.begins_with("Plays in Vermilion. Capital Fangridge"), "colours follow the seats: %s" % screen.faction_labels[0].text)
	_assert_no_raw_ids(_visible_text(screen), "rematch setup")
	for i in 20:
		assert_ne(screen.new_seed(4242), 4242, "a new seed is never the last game's")
	# A seating that can't be used changes nothing.
	assert_false(screen.set_seats(["kingdom"]), "one faction for two seats")
	assert_false(screen.set_seats(["kingdom", "pirates"]), "a faction that isn't in the game")
	assert_eq(screen.config().players, ["beasts", "kingdom"])
	screen.prefill({"players": ["pirates", "kingdom"], "seed": 1})
	assert_false(screen.rematch_label.visible, "no rematch note when the seating could not be used")
	screen.free()


## The victory screen's New game opens the setup as a rematch, and Start plays it.
func test_victory_new_game_is_a_rematch() -> void:
	var game := SceneFlow.make_game({"players": ["beasts", "kingdom"], "seed": 999})
	game.victory_screen.new_game_button.pressed.emit()
	var title := game.next_scene as TitleScreen
	assert_true(title != null and title.new_game_screen != null and title.new_game_screen.visible, "New game opens the setup")
	if title == null or title.new_game_screen == null:
		game.free()
		return
	var setup := title.new_game_screen
	assert_eq(setup.config().players, ["beasts", "kingdom"], "with the last game's seating")
	assert_ne(setup.config().seed, 999, "and a new seed")
	assert_true(setup.rematch_label.visible)
	var rematch_seed: int = setup.config().seed
	setup.start_button.pressed.emit()
	var rematch := title.next_scene as GameScreen
	assert_true(rematch != null, "Start begins the rematch")
	if rematch:
		assert_eq(rematch.session.players(), ["beasts", "kingdom"])
		assert_eq(rematch.config.seed, rematch_seed)
		rematch.free()
	title.free()
	game.free()

	# The title's own New game is a fresh setup: default seats (you against the computer), no rematch note.
	var fresh := SceneFlow.make_title(true)
	assert_eq(fresh.new_game_screen.config().players, ["kingdom", "beasts"])
	assert_eq(fresh.new_game_screen.seat_kind(2), "computer")
	assert_false(fresh.new_game_screen.rematch_label.visible)
	fresh.free()


func test_back_and_escape_emit_back_requested() -> void:
	var screen := _screen()
	var backs := [0]
	screen.back_requested.connect(func(): backs[0] += 1)
	screen.back_button.pressed.emit()
	assert_eq(backs[0], 1)
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	screen._unhandled_input(esc)
	assert_eq(backs[0], 2, "Esc goes back")
	screen.visible = false
	screen._unhandled_input(esc)
	assert_eq(backs[0], 2, "not while hidden")
	screen.free()


func test_numbers_are_explained_and_no_raw_ids() -> void:
	var screen := _screen()
	for setup in [func(): pass, func(): screen.select_faction(2, "kingdom"), func(): _type_seed(screen, "abc")]:
		setup.call()
		var checked := 0
		for c in _visible_controls(screen, []):
			if (c is Label or c is Button) and _has_digit(c.text):
				checked += 1
				assert_false(c.tooltip_text.strip_edges().is_empty(), "'%s' has a tooltip" % c.text)
				assert_ne(c.mouse_filter, Control.MOUSE_FILTER_IGNORE, "'%s' takes the mouse" % c.text)
		assert_true(checked >= 4, "player labels and faction summaries are checked (%d)" % checked)
		assert_false(screen.seed_edit.tooltip_text.is_empty(), "the seed explains itself")
		_assert_no_raw_ids(_visible_text(screen), "new game screen")
	screen.free()
