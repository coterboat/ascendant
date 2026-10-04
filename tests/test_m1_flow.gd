extends "res://tests/test_case.gd"
## M1 end to end (#7, #8), headless through the real screens: the title screen's New game, the new game
## screen with the seats swapped and a custom seed, scripted hotseat turns with handoffs and reports, a
## battle and its report in the viewer with its "why", the codex from a report "?" and from a
## right-click on a number, a capital capture, the victory screen with the right numbers, and "New game"
## back to the new game screen. Plus: the same seed and orders give the same game, no raw ids anywhere,
## and the colours follow the seats. Screens build their nodes lazily, so nothing needs the tree; where
## the engine would call _ready on a scene change, the test calls it.

const TITLE_SCENE := "res://ui/title_screen.tscn"
const SEED := 4242
const SWAPPED := ["beasts", "kingdom"]
const RAW_IDS := ["kingdom", "beasts", "crownkeep", "fangridge", "westwatch", "ebonpeak", "stonegate",
	"blackwood", "highcrag", "ironspike", "rivermarch", "bloodfen", "thornvale", "wildmoor", "greenglade",
	"deepwood", "knight_captain", "warchief", "war_bear", "spearmen", "tuskers", "codex:", "battle_", "trait_",
	"beasts-", "kingdom-"]


# --- the flow -------------------------------------------------------------------------------------

## Title -> New game -> Swap seats, type the seed -> Start. Returns the game screen Start switched to.
func _start_from_title(game_seed: int) -> GameScreen:
	var title := load(TITLE_SCENE).instantiate() as TitleScreen
	assert_true(title != null, "the title scene instantiates as TitleScreen")
	title._ready()  # what the engine does when the title becomes the current scene
	title.new_game_button.pressed.emit()
	var setup := title.new_game_screen
	assert_true(setup != null and setup.visible, "New game opens the new game screen")
	assert_eq(setup.get_index(), title.get_child_count() - 1, "on top of the title")
	# The M1 hotseat game: Player 2 to Human and rulers off (the default is the computer, with rulers).
	setup.kind_pickers[1].select(NewGameScreen.KINDS.find("human"))
	setup.kind_pickers[1].item_selected.emit(NewGameScreen.KINDS.find("human"))
	setup.rulers_toggle.button_pressed = false
	setup.swap_button.pressed.emit()
	setup.seed_edit.text = str(game_seed)
	setup.seed_edit.text_changed.emit(setup.seed_edit.text)
	assert_true(setup.is_valid(), setup.error_text())
	assert_true(setup.faction_labels[0].text.begins_with("Plays in Vermilion"), "seat 1 plays in Vermilion: %s" % setup.faction_labels[0].text)
	assert_true(setup.faction_labels[0].text.contains("Fangridge"), "and seat 1 is now the Thornmane Clans")
	_assert_no_raw_ids(_visible_text(title), "new game screen")
	setup.start_button.pressed.emit()
	var game := title.next_scene as GameScreen
	assert_true(game != null, "Start switches to the game screen")
	if game:
		assert_eq(game.config, {"players": SWAPPED, "seed": game_seed}, "with exactly the new game screen's config")
		assert_eq(game.session.players(), SWAPPED)
	title.free()
	return game


## The player at the controls gives `orders` through the map: [army id, province id] selects the army
## and clicks the province (two-click move); [unit type id] selects the capital and presses its recruit
## button.
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
			var button := _find(game.map.details, "Recruit_%s" % o[0]) as Button
			assert_true(button != null, "the capital has a recruit button for %s" % o[0])
			if button:
				button.pressed.emit()
		assert_eq(game.session.current_orders().size(), before + 1, "order %s queued (%s)" % [o, game.map.status_text])


## The cover is up and the map hidden; Ready hands the computer over.
func _ready_up(game: GameScreen) -> void:
	assert_true(game.handoff.visible, "the handoff covers the screen")
	assert_false(game.map.visible, "the map is hidden during the handoff")
	_assert_no_raw_ids(_visible_text(game), "handoff")
	game.handoff.ready_button.pressed.emit()
	assert_false(game.handoff.visible, "Ready removes the cover")
	assert_true(game.map.visible, "and shows the map")


## One whole turn: seat 1 orders, End turn, handoff, Ready, seat 2 reads last turn's report and orders,
## End turn (it resolves), and unless the game is over the handoff back to seat 1, who gets the report.
func _play_turn(game: GameScreen, first: Array, second: Array) -> void:
	var session := game.session
	assert_eq(session.current_player(), SWAPPED[0], "seat 1 starts the turn")
	_order(game, first)
	game.end_turn_button.pressed.emit()
	_ready_up(game)
	assert_eq(session.current_player(), SWAPPED[1], "then seat 2")
	assert_eq(game.report_overlay.visible, session.turn_report().turn > 0, "seat 2 reads last turn's report first")
	game.close_turn_report()
	_order(game, second)
	game.end_turn_button.pressed.emit()
	if session.is_over():
		return
	_ready_up(game)
	assert_true(game.report_overlay.visible, "the new turn starts with the report")
	assert_eq(game.report_panel.header_label.text, session.turn_report().header)
	assert_eq(game.report_panel.event_rows().size(), session.turn_report().events.size(), "one row per event")
	_assert_no_raw_ids(_visible_text(game), "turn %d report" % session.turn_report().turn)


# --- tests ----------------------------------------------------------------------------------------

func test_a_whole_game_from_the_title_screen_to_the_victory_screen() -> void:
	var game := _start_from_title(SEED)
	var session := game.session
	assert_eq(game.map.viewing_faction_id, "beasts", "player 1 (Thornmane Clans) has the computer first")
	_assert_seat_colours_on_map(game)
	_assert_no_raw_ids(_visible_text(game), "the first orders phase")

	# Turns 1 and 2: both armies march up the northern road to the hill forts.
	_play_turn(game, [["beasts-2", "ebonpeak"]], [["kingdom-1", "westwatch"]])
	_play_turn(game, [["beasts-2", "blackwood"]], [["kingdom-1", "stonegate"]])
	# Turn 3: the Thornmane army holds Blackwood and the Aurel Crown attacks it.
	_play_turn(game, [], [["kingdom-1", "blackwood"]])
	assert_eq(session.turns_played(), 3)
	var battles := session.battle_events()
	assert_eq(battles.size(), 1, "one battle, at Blackwood")
	if battles.is_empty():
		game.free()
		return

	# The battle row's Battle report button opens the viewer above the report, the "why" first.
	assert_eq(game.report_panel.battle_buttons().size(), 1)
	game.report_panel.battle_buttons()[0].pressed.emit()
	var viewer := game.battle_viewer
	assert_true(viewer.visible, "the battle report viewer opens")
	assert_true(viewer.get_index() > game.report_overlay.get_index(), "above the turn report")
	var report: Dictionary = battles[0].numbers.report
	assert_eq(viewer.title_label.text, "Battle %s" % report.place)
	assert_eq(viewer.section_names()[0], "why", "the why comes first")
	var why := viewer.section("why").find_child("WhyLabel", true, false) as Label
	assert_true(why.text.begins_with("Why: "), why.text)
	assert_true(why.text.to_lower().contains(String(report.why).to_lower()), "the why is the battle's own: %s" % why.text)
	for f in ["beasts", "kingdom"]:
		assert_eq(viewer.side_color(f), UiPalette.seat_color(SWAPPED.find(f)), "%s is drawn in its seat colour" % f)
	_assert_no_raw_ids(_visible_text(game), "battle report")
	viewer.close_button.pressed.emit()
	assert_false(viewer.visible)
	assert_true(game.report_overlay.visible, "closing the battle report returns to the turn report")

	# The codex from a report "?": above the report, at that entry; closing it returns to the report.
	var question: Button = game.report_panel.codex_buttons()[0]
	var key := String(question.get_meta("codex_key"))
	question.pressed.emit()
	assert_true(game.codex.visible, "the ? opens the codex")
	assert_eq(game.codex.current_key(), key, "at the line's entry")
	assert_true(game.codex.get_index() > game.report_overlay.get_index(), "above the report")
	_assert_no_raw_ids(_visible_text(game), "codex over the report")
	game.codex.close()
	assert_true(game.report_overlay.visible, "closing the codex returns to the report")

	# The codex from a right-click on a number: the gold in the top bar.
	game.close_turn_report()
	assert_true(game.map.gold_label.tooltip_text.contains("Codex: Gold (right-click or F1 to open)"), game.map.gold_label.tooltip_text)
	game.map.gold_label.gui_input.emit(CodexLink.right_click())
	assert_true(game.codex.visible, "right-clicking the gold opens the codex")
	assert_eq(game.codex.current_key(), "gold")
	game.codex.close()

	# The battle's winner marches on the enemy capital; the loser has no army left to stop it.
	var s := session.state()
	var mover := "beasts-2" if s.find_army("beasts-2") != null else "kingdom-1"
	var march: Array = ["stonegate", "westwatch", "crownkeep"] if mover == "beasts-2" else ["ebonpeak", "fangridge"]
	var winner := s.find_army(mover).owner if s.find_army(mover) else ""
	assert_false(winner.is_empty(), "one army survived the battle")
	assert_eq(s.armies.size(), 1, "and it is the only army left")
	for step in march:
		if winner == SWAPPED[0]:
			_play_turn(game, [[mover, step]], [])
		else:
			_play_turn(game, [], [[mover, step]])
	assert_true(session.is_over(), "capturing the capital ends the game")
	assert_eq(session.winner(), winner)

	# The victory screen, with the numbers of this game.
	var screen := game.victory_screen
	var v := session.victory()
	var final := session.state()
	assert_true(screen.visible, "the victory screen shows")
	assert_false(game.handoff.visible, "no handoff after the last turn")
	var seat := SWAPPED.find(winner)
	assert_eq(screen.headline_label.text, "%s wins" % final.find_faction(winner).faction_name)
	assert_eq(screen.seat_label.text, "Player %d wins the game." % (seat + 1))
	assert_eq(screen.turns_label.text, "Turns played: %d" % (3 + march.size()))
	assert_eq(screen.battles_label.text, "Battles fought: 1")
	assert_eq(screen.summary_label.text, v.text)
	var rows := screen.province_labels()
	assert_eq(rows.size(), 2, "one row per player, in seat order")
	for i in SWAPPED.size():
		var held := 0
		for p in final.provinces:
			if p.owner == SWAPPED[i]:
				held += 1
		assert_eq(rows[i].text, "%s: %s" % [final.find_faction(SWAPPED[i]).faction_name, TooltipText.count(held, "province")])
		assert_eq(rows[i].get_theme_color("font_color"), UiPalette.seat_color(i).lightened(0.3), "row %d in its seat colour" % i)
	assert_eq(screen.capture_labels().size(), 1)
	_assert_no_raw_ids(_visible_text(game), "victory screen")

	# A victory number opens its codex entry above the victory screen.
	screen.battles_label.gui_input.emit(CodexLink.right_click())
	assert_true(game.codex.visible)
	assert_eq(game.codex.current_key(), "battle_rounds")
	assert_true(game.codex.get_index() > screen.get_index(), "the codex opens above the victory screen")
	game.codex.close()

	# New game goes back to the new game screen.
	screen.new_game_button.pressed.emit()
	var title := game.next_scene as TitleScreen
	assert_true(title != null, "New game switches to the title scene")
	if title:
		assert_true(title.new_game_screen != null and title.new_game_screen.visible, "with the new game screen open")
		if title.new_game_screen:
			assert_eq(title.new_game_screen.config().players, SWAPPED, "set up as a rematch: the same seats")
			assert_ne(title.new_game_screen.config().seed, SEED, "with a new seed")
		title.free()
	game.free()


func test_the_same_seed_and_orders_give_the_same_game() -> void:
	var a := _start_from_title(SEED)
	var b := _start_from_title(SEED)
	for game in [a, b]:
		_play_turn(game, [["beasts-2", "ebonpeak"], ["tuskers"]], [["kingdom-1", "westwatch"], ["spearmen"]])
		_play_turn(game, [["beasts-2", "blackwood"]], [["kingdom-1", "stonegate"]])
		_play_turn(game, [], [["kingdom-1", "blackwood"]])
	assert_eq(a.session.battle_events().size(), 1, "the scripted turns include a battle")
	assert_eq(var_to_str(a.session.state().to_dict()), var_to_str(b.session.state().to_dict()), "same state")
	assert_eq(a.session.turn_report().events.map(func(e): return e.text),
		b.session.turn_report().events.map(func(e): return e.text), "same report")
	assert_eq(a.session.history(), b.session.history(), "same orders and turn seeds")
	var replayed := GameSession.replay(a.session.record(), AutoBattleResolver.new())
	assert_eq(replayed.errors, [])
	assert_eq(var_to_str(replayed.state.to_dict()), var_to_str(a.session.state().to_dict()),
		"replaying the record with the real battle rules gives the same state")
	a.free()
	b.free()


func test_title_screen_buttons() -> void:
	var title := load(TITLE_SCENE).instantiate() as TitleScreen
	title._ready()
	for b in [title.new_game_button, title.quick_start_button, title.codex_button, title.map_preview_button]:
		assert_false(b.tooltip_text.is_empty(), "%s explains itself" % b.text)
	assert_eq(title.new_game_button.text, "New game")
	assert_true(title.map_preview_button.flat, "Map preview is a quiet developer link")
	assert_true(title.map_preview_button.get_index() > title.codex_button.get_index(), "below the real buttons")

	# New game, then Back: the title again, and no game started.
	title.new_game_button.pressed.emit()
	assert_true(title.new_game_screen.visible)
	title.new_game_screen.back_button.pressed.emit()
	assert_false(title.new_game_screen.visible, "Back closes the new game screen")
	assert_eq(title.next_scene, null, "and starts nothing")

	# Codex: over the title, closing returns to it.
	title.codex_button.pressed.emit()
	assert_true(title.codex != null and title.codex.visible, "Codex opens the codex panel")
	assert_eq(title.codex.get_index(), title.get_child_count() - 1, "on top of the title")
	assert_true(title.codex.listed_keys().size() > 0)
	_assert_no_raw_ids(_visible_text(title), "codex over the title")
	title.codex.close()
	assert_false(title.codex.visible)

	# Quick start: straight into a game against the computer (tests/test_mvp_defaults.gd has the details).
	title.quick_start_button.pressed.emit()
	var game := title.next_scene as GameScreen
	assert_true(game != null, "Quick start switches to a game screen")
	if game:
		assert_eq(game.session.players().size(), GameScreen.default_config().players.size(), "every faction plays")
		assert_eq(game.session.human_seats(), 1, "you against the computer")
		assert_eq(game.session.phase(), GameSession.Phase.ORDERS)
		game.free()
	title.free()


func test_quit_and_back_to_title_go_to_the_title_scene() -> void:
	var game := _start_from_title(SEED)
	game.map.back_button.pressed.emit()
	assert_true(game.menu_overlay.visible, "the top bar's Menu opens the menu")
	(game.menu_overlay.find_child("QuitToTitleButton", true, false) as Button).pressed.emit()
	assert_true(game.quit_overlay.visible, "Quit to title asks first")
	(game.quit_overlay.find_child("ConfirmQuitButton", true, false) as Button).pressed.emit()
	var title := game.next_scene as TitleScreen
	assert_true(title != null, "confirming switches to the title")
	if title:
		assert_true(title.new_game_screen == null or not title.new_game_screen.visible, "the plain title, no new game screen")
		title.free()
	game.free()


# --- colours --------------------------------------------------------------------------------------

## Seats swapped: the Thornmane Clans are player 1 and so Vermilion, the Aurel Crown Cobalt.
func _assert_seat_colours_on_map(game: GameScreen) -> void:
	var vermilion := UiPalette.seat_color(0)
	var cobalt := UiPalette.seat_color(1)
	assert_eq(vermilion, Color("#D8432C"))
	assert_eq(cobalt, Color("#2D5BD1"))
	assert_eq(game.map.regions["fangridge"].ring_color, vermilion, "player 1's capital is ringed in Vermilion")
	assert_eq(game.map.regions["crownkeep"].ring_color, cobalt, "player 2's capital in Cobalt")
	assert_eq(game.map.regions["thornvale"].ring_color, UiPalette.NEUTRAL, "unowned is slate")
	var badge := game.map.regions["fangridge"].army_box.get_child(0) as Button
	assert_eq((badge.get_theme_stylebox("normal") as StyleBoxFlat).bg_color, vermilion, "player 1's army badge is Vermilion")
	assert_eq(game.map.faction_label.get_theme_color("font_color"), vermilion.lightened(0.25), "the top bar names player 1 in Vermilion")


# --- helpers --------------------------------------------------------------------------------------

func _find(root: Node, node_name: String) -> Node:
	for n in root.find_children(node_name, "", true, false):
		return n
	return null


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
	elif node is RichTextLabel:
		out.append((node as RichTextLabel).get_parsed_text())
	elif node is LineEdit:
		out.append((node as LineEdit).text)
	if node is Control and not (node as Control).tooltip_text.is_empty():
		out.append((node as Control).tooltip_text)
	for c in node.get_children():
		_collect_text(c, out)


func _assert_no_raw_ids(text: String, what: String) -> void:
	assert_false(text.is_empty(), "%s has text" % what)
	for id in RAW_IDS:
		assert_false(text.contains(id), "%s shows no raw id '%s'" % [what, id])
