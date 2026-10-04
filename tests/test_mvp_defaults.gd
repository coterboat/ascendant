extends "res://tests/test_case.gd"
## MVP defaults: the new game screen starts as Player 1 Human vs Player 2 Computer (Normal) with the
## "Rulers" box ticked, hotseat is one click away, Quick start goes straight into the same kind of game
## with a random faction and seed (the person's ruler on its balanced preset), and a rematch keeps the
## last game's choices. The title screen is a real front door: every button is there and explains
## itself, the map preview is only a small dev link, and nothing on it shows a raw id.

const TITLE_SCENE := "res://ui/title_screen.tscn"
const RAW_IDS := ["kingdom", "beasts", "crownkeep", "fangridge", "codex:", "regents_court", "blood_of_the_fang",
	"ever_regent", "fang_chieftain", "beasts-", "kingdom-"]

var _folder := ""


## A title screen with its own empty save folder.
func _title() -> TitleScreen:
	_folder = "user://test_defaults_%d_%d" % [Time.get_ticks_usec(), randi()]
	var title := load(TITLE_SCENE).instantiate() as TitleScreen
	title.store = SaveStore.new(_folder)
	title._bind()
	return title


func _cleanup() -> void:
	if not _folder.is_empty():
		SaveStore.new(_folder).clear()
		DirAccess.remove_absolute(_folder)


func _visible_text(node: Node) -> String:
	var out := PackedStringArray()
	_collect(node, out)
	return "\n".join(out)


func _collect(node: Node, out: PackedStringArray) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	for c in node.get_children():
		_collect(c, out)


## Every visible text and tooltip, the pickers' items included.
func _all_text(node: Node) -> String:
	var out := PackedStringArray()
	_collect_all(node, out)
	return "\n".join(out)


func _collect_all(node: Node, out: PackedStringArray) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is Label or node is Button:
		out.append(node.text)
	if node is OptionButton:
		for i in (node as OptionButton).item_count:
			out.append((node as OptionButton).get_item_text(i))
			out.append((node as OptionButton).get_popup().get_item_tooltip(i))
	if node is Control and not (node as Control).tooltip_text.is_empty():
		out.append((node as Control).tooltip_text)
	for c in node.get_children():
		_collect_all(c, out)


# --- the new game screen --------------------------------------------------------------------------

func test_new_game_defaults_to_you_against_the_computer_with_rulers() -> void:
	var screen := NewGameScreen.new()
	assert_eq(screen.seat_kind(1), "human", "Player 1 is you")
	assert_eq(screen.seat_kind(2), "computer", "Player 2 is the computer")
	assert_eq(screen.seat_level(2), "normal", "at Normal")
	assert_true(screen.level_pickers[1].visible, "its level picker shows")
	assert_true(screen.rulers_on(), "rulers are on")
	assert_eq(screen.rulers_toggle.text, "Rulers", "the box is just Rulers now")
	assert_false(screen.rulers_toggle.tooltip_text.contains("still being built"), "no preview wording")
	assert_true(screen.rulers_toggle.tooltip_text.contains("Untick it"), "and it says it can be switched off")
	var cfg := screen.config()
	assert_eq(cfg.players, ["kingdom", "beasts"])
	assert_eq(cfg.ai, {"beasts": "normal"})
	assert_eq(cfg.rulers, true)
	assert_true(screen.computer_label.visible, "the computer's explanation shows instead of the hotseat one")
	assert_false(screen.hotseat_label.visible)
	assert_eq(screen.start_button.text, "Choose builds", "with rulers, Start goes to the build screen first")
	for t in _all_text(screen).split("\n"):
		assert_false(t.contains("_") or t.contains("codex:"), "no ids on the default screen, tooltips included: %s" % t)
	# The rulers box stays switchable.
	screen.rulers_toggle.button_pressed = false
	assert_false(screen.config().has("rulers"))
	assert_eq(screen.start_button.text, "Start")
	screen.free()


func test_hotseat_is_one_click_away() -> void:
	var screen := NewGameScreen.new()
	screen.kind_pickers[1].select(NewGameScreen.KINDS.find("human"))
	screen.kind_pickers[1].item_selected.emit(NewGameScreen.KINDS.find("human"))
	assert_eq(screen.seat_kind(2), "human")
	assert_false(screen.config().has("ai"), "two people: no computer seat")
	assert_true(screen.hotseat_label.visible, "the hotseat explanation is back")
	assert_eq(screen.config().rulers, true, "rulers stay as they were")
	screen.free()


func test_start_with_the_defaults_builds_for_you_only_then_starts() -> void:
	var title := _title()
	title.open_new_game()
	var setup := title.new_game_screen
	setup.set_seed(77)
	setup.start_button.pressed.emit()
	assert_true(setup.build_screen_open(), "with rulers on, Start opens the build screen")
	assert_eq(setup.build_screen.human_seats(), [0], "only you pick a build")
	setup.build_screen.lock_in()
	var game := title.next_scene as GameScreen
	assert_true(game != null, "locking in your build starts the game")
	if game:
		assert_eq(game.config.ai, {"beasts": "normal"})
		assert_true(RulerRules.has_rulers(game.session.state()), "with rulers")
		assert_eq(game.session.current_player(), "kingdom", "you give orders first")
		assert_false(game.handoff.visible, "no handoff against the computer")
		game.free()
	title.free()
	_cleanup()


func test_rematch_keeps_the_last_games_choices() -> void:
	var screen := NewGameScreen.new()
	screen.prefill({"players": ["beasts", "kingdom"], "seed": 5})
	assert_eq(screen.seat_kind(1), "human")
	assert_eq(screen.seat_kind(2), "human", "a hotseat game rematches as hotseat")
	assert_false(screen.rulers_on(), "and without rulers, as it was")
	assert_ne(screen.config().seed, 5, "with a new seed")
	screen.prefill({"players": ["kingdom", "beasts"], "seed": 6, "ai": {"beasts": "normal"}, "rulers": true,
		"builds": {"kingdom": RulerRules.preset_build("regents_court")}})
	assert_eq(screen.seat_kind(2), "computer")
	assert_eq(screen.seat_level(2), "normal")
	assert_true(screen.rulers_on())
	screen.free()


# --- quick start ----------------------------------------------------------------------------------

func test_quick_start_config_is_you_against_the_computer_with_rulers() -> void:
	var seen := {}
	for dice_seed in range(1, 25):
		var rng := RandomNumberGenerator.new()
		rng.seed = dice_seed
		var cfg := NewGameScreen.quick_start_config(rng)
		var human: String = cfg.players[0]
		var computer: String = cfg.players[1]
		seen[human] = true
		assert_ne(human, computer)
		assert_eq(cfg.ai, {computer: "normal"}, "the computer at Normal in seat 2")
		assert_eq(cfg.rulers, true)
		assert_eq(cfg.builds[human], RulerRules.preset_build(RulerRules.balanced_preset(human)), "your ruler on the balanced preset")
		assert_eq(cfg.builds[computer], BuildScreen.computer_build(computer, cfg.seed, 1), "the computer's build is the one its dice pick")
		assert_true(cfg.seed >= 1 and cfg.seed <= NewGameScreen.MAX_RANDOM_SEED)
	assert_eq(seen.size(), FactionData.FACTIONS.size(), "the faction is random: each one comes up")


func test_quick_start_goes_straight_into_the_game() -> void:
	var title := _title()
	title.quick_start_button.pressed.emit()
	var game := title.next_scene as GameScreen
	assert_true(game != null, "Quick start switches to a game screen")
	assert_true(title.new_game_screen == null, "without the new game screen")
	if game:
		var human: String = game.session.players()[0]
		assert_eq(game.session.phase(), GameSession.Phase.ORDERS, "your orders, right away")
		assert_eq(game.session.current_player(), human)
		assert_eq(game.session.human_seats(), 1)
		assert_eq(game.session.computer_level(game.session.players()[1]), "normal")
		assert_true(RulerRules.has_rulers(game.session.state()), "rulers on")
		var preset := RulerRules.preset_build(RulerRules.balanced_preset(human))
		assert_eq(game.session.builds()[human].ruler, preset.ruler, "your balanced preset's ruler")
		assert_eq(game.session.builds()[human].mandates, preset.mandates, "and its mandates")
		assert_false(game.handoff.visible)
		game.free()
	title.free()
	_cleanup()


# --- the title screen -----------------------------------------------------------------------------

func test_the_title_screen_is_a_front_door() -> void:
	var title := _title()
	assert_eq(title.get_node("Center/Box/Title").text, "ASCENDANT")
	assert_eq(title.get_node("Center/Box/Subtitle").text, TitleScreen.TAGLINE)
	var buttons := [title.new_game_button, title.load_button, title.quick_start_button, title.codex_button, title.settings_button, title.quit_button]
	assert_eq(buttons.map(func(b): return b.text), ["New game", "Load game", "Quick start", "Codex", "Settings", "Quit"])
	for b in buttons + [title.map_preview_button]:
		assert_false(b.tooltip_text.is_empty(), "%s explains itself" % b.text)
	for i in buttons.size() - 1:
		assert_true(buttons[i].get_index() < buttons[i + 1].get_index(), "in order")
	assert_true(title.map_preview_button.flat, "Map preview is a quiet dev link")
	assert_true(title.map_preview_button.get_theme_font_size("font_size") < title.new_game_button.get_theme_font_size("font_size"), "and small")
	assert_true(title.map_preview_button.get_index() > title.quit_button.get_index(), "below the real buttons")
	for banner in ["KingdomBanner", "BeastsBanner"]:
		var rect := title.get_node(banner) as TextureRect
		assert_true(rect.texture != null, "%s shows the faction banner" % banner)
	assert_eq((title.get_node("KingdomBanner") as TextureRect).texture.resource_path, "res://assets/banners/kingdom.webp")
	assert_eq((title.get_node("BeastsBanner") as TextureRect).texture.resource_path, "res://assets/banners/beasts.webp")
	assert_eq(title.get_node("KingdomBanner/KingdomCaption").text, "Aurel Crown")
	assert_eq(title.get_node("BeastsBanner/BeastsCaption").text, "Thornmane Clans")
	var text := _visible_text(title)
	for id in RAW_IDS:
		assert_false(text.contains(id), "the title shows no raw id '%s'" % id)
	title.free()
	_cleanup()


func test_the_title_opens_settings_and_its_overlays_close_again() -> void:
	var title := _title()
	title.settings_button.pressed.emit()
	assert_true(title.settings_panel != null and title.settings_panel.visible, "Settings opens over the title")
	assert_eq(title.settings_panel.get_index(), title.get_child_count() - 1, "on top")
	title.settings_panel.close_button.pressed.emit()
	assert_false(title.settings_panel.visible)
	title.free()
	_cleanup()
