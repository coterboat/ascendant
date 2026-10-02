extends "res://tests/test_case.gd"
## The main game screen (#6, #7): a whole hotseat game driven headless through GameScreen's API and
## its child nodes (the map's two-click moves and recruit buttons, End turn, the handoff's Ready, the
## turn report). Like the other screens it builds its nodes lazily, so it works outside the tree.

const GAME_SCENE := "res://ui/game_screen.tscn"
const CONFIG := {"players": ["kingdom", "beasts"], "seed": 4242}
const RAW_IDS := ["kingdom", "beasts", "crownkeep", "fangridge", "westwatch", "ebonpeak", "stonegate",
	"blackwood", "highcrag", "ironspike", "rivermarch", "bloodfen", "thornvale", "wildmoor", "greenglade",
	"deepwood", "knight_captain", "warchief", "war_bear", "spearmen", "tuskers"]


# --- fixtures -------------------------------------------------------------------------------------

func _game(config: Dictionary = CONFIG) -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	assert_true(game != null, "the game scene instantiates as GameScreen")
	game.start_game(config)
	return game


## The player at the controls gives `orders` through the map, as a player would:
## [army id, province id] selects the army, then clicks the province (two-click move);
## [unit type id] selects their capital, then presses its recruit button.
func _order_through_map(game: GameScreen, orders: Array) -> void:
	for o in orders:
		var before := game.session.current_orders().size()
		if o.size() == 2:
			game.map.select_army(o[0])
			game.map.select_province(o[1])
		else:
			game.map.selected_army_id = ""  # with an army selected, clicking the capital would order a move
			var f := game.map.state.find_faction(game.session.current_player())
			game.map.select_province(f.capital)
			var button := _recruit_button(game, o[0])
			assert_true(button != null, "the capital has a recruit button for %s" % o[0])
			if button:
				button.pressed.emit()
		assert_eq(game.session.current_orders().size(), before + 1, "order %s queued (%s)" % [o, game.map.status_text])


func _recruit_button(game: GameScreen, unit_type_id: String) -> Button:
	for n in game.map.details.find_children("Recruit_%s" % unit_type_id, "Button", true, false):
		return n
	return null


func _order_rows(game: GameScreen) -> Array:
	return game.map.details.find_children("Order_*", "", true, false)


## After End turn: the cover is up and the map hidden. Ready hands the computer over.
func _ready_up(game: GameScreen) -> void:
	assert_true(game.handoff.visible, "the handoff covers the screen")
	assert_false(game.map.visible, "the map is hidden during the handoff")
	game.handoff.ready_button.pressed.emit()
	assert_false(game.handoff.visible, "Ready removes the cover")
	assert_true(game.map.visible, "and shows the map")


## One whole turn: seat 1 orders, End turn, handoff, Ready, seat 2 orders, End turn (it resolves).
func _play_turn(game: GameScreen, first: Array, second: Array) -> void:
	assert_eq(game.session.current_player(), "kingdom", "seat 1 starts the turn")
	_order_through_map(game, first)
	game.end_turn_button.pressed.emit()
	_ready_up(game)
	assert_eq(game.session.current_player(), "beasts")
	game.close_turn_report()
	_order_through_map(game, second)
	game.end_turn_button.pressed.emit()


## After a resolved turn: seat 1 takes the computer and closes the report.
func _next_turn(game: GameScreen) -> void:
	_ready_up(game)
	assert_true(game.report_overlay.visible, "the new turn starts with the report")
	game.close_turn_report()


func _assert_report_matches_session(game: GameScreen) -> void:
	var report := game.session.turn_report()
	var events: Array = report.events.filter(func(e): return e.type != "game_over")
	var rows := game.report_panel.event_rows()
	assert_eq(game.report_panel.header_label.text, report.header)
	assert_eq(rows.size(), events.size(), "one report row per session event")
	for i in mini(rows.size(), events.size()):
		assert_eq(rows[i].text, events[i].text, "row %d is the session's event" % i)


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
	if node is Control and not (node as Control).tooltip_text.is_empty():
		out.append((node as Control).tooltip_text)
	for c in node.get_children():
		_collect_text(c, out)


func _assert_no_raw_ids(text: String, what: String) -> void:
	assert_false(text.is_empty(), "%s has text" % what)
	for id in RAW_IDS:
		assert_false(text.contains(id), "%s shows no raw id '%s'" % [what, id])


# --- the hotseat flow -----------------------------------------------------------------------------

func test_three_scripted_turns_through_the_game_screen() -> void:
	var game := _game()
	var session := game.session
	assert_eq(session.turn_number(), 1)
	assert_eq(session.players(), ["kingdom", "beasts"])
	assert_eq(game.map.viewing_faction_id, "kingdom", "seat 1 has the computer first")
	assert_eq(game.map.selected_province_id, "crownkeep", "their capital is selected, ready to recruit")
	assert_eq(game.map.turn_label.text, "Turn 1", "the top bar shows the session's turn")
	assert_true(game.map.turn_label.tooltip_text.contains("Game seed 4242"), "the seed is shown so the game can be replayed")
	assert_true(game.report_button.disabled, "no report before the first turn")
	assert_eq(game.end_turn_button.text, "End turn (no orders)")

	# Turn 1, seat 1: a two-click move and a recruit from the capital's recruit button.
	_order_through_map(game, [["kingdom-1", "westwatch"], ["spearmen"]])
	assert_eq(game.end_turn_button.text, "End turn (2 orders)", "End turn counts the queued orders")
	assert_true(game.end_turn_button.tooltip_text.contains("player 2 (Thornmane Clans)"), "and says who plays next")
	assert_eq(game.map.orders.orders(), session.current_orders(), "the map shows the session's orders")
	assert_eq(_order_rows(game).size(), 2)
	game.end_turn_button.pressed.emit()
	assert_eq(session.phase(), GameSession.Phase.HANDOFF)
	assert_eq(game.handoff.title_label.text, "Pass to Thornmane Clans")
	_ready_up(game)
	assert_eq(game.map.viewing_faction_id, "beasts")
	assert_false(game.report_overlay.visible, "nothing to report on turn 1")
	assert_true(game.end_turn_button.tooltip_text.contains("last player"), "seat 2 is told the turn resolves")

	# Seat 2 orders and ends the turn: it resolves, and the computer goes back to seat 1.
	_order_through_map(game, [["beasts-2", "ebonpeak"], ["tuskers"]])
	game.end_turn_button.pressed.emit()
	assert_eq(session.phase(), GameSession.Phase.HANDOFF)
	assert_eq(session.current_player(), "kingdom")
	assert_true(game.handoff.body_label.text.contains("Turn 1 is resolved"), game.handoff.body_label.text)
	assert_false(game.report_overlay.visible, "the report waits until seat 1 is ready")
	_ready_up(game)

	# Seat 1 reads the turn 1 report.
	assert_true(game.report_overlay.visible, "the report opens after the handoff")
	_assert_report_matches_session(game)
	assert_eq(session.turn_number(), 2)
	assert_eq(game.map.turn_label.text, "Turn 2")
	var s := session.state()
	assert_eq(s.find_army("kingdom-1").location, "westwatch")
	assert_eq(s.find_army("beasts-2").location, "ebonpeak")
	assert_eq(s.find_faction("kingdom").gold, 50 - 8 + 12 + 6)  # 60
	assert_eq(s.find_faction("beasts").gold, 40 - 11 + 12 + 6)  # 47 (Tuskers cost 11)
	assert_true(game.map.gold_label.text.begins_with("Gold 60"), game.map.gold_label.text)
	assert_eq(_order_rows(game).size(), 0, "the new turn starts with no orders")
	# Clicking a report line closes the report and shows its province on the map.
	var events: Array = session.turn_report().events
	var row := -1
	for i in events.size():
		if row < 0 and not events[i].provinces.is_empty():
			row = i
	assert_true(row >= 0, "some event points at a province")
	game.report_panel.event_rows()[row].pressed.emit()
	assert_false(game.report_overlay.visible)
	assert_eq(game.map.selected_province_id, events[row].provinces[0])
	assert_eq(session.current_orders().size(), 0, "focusing a province orders nothing")
	assert_false(game.report_button.disabled)
	game.report_button.pressed.emit()
	assert_true(game.report_overlay.visible, "Turn report reopens it")
	game.close_turn_report()

	# Turn 2: both push on to the hill forts of the northern road. Seat 2 reads the report too.
	_order_through_map(game, [["kingdom-1", "stonegate"]])
	game.end_turn_button.pressed.emit()
	_ready_up(game)
	assert_true(game.report_overlay.visible, "seat 2 reads last turn's report after their handoff")
	_assert_report_matches_session(game)
	game.close_turn_report()
	_order_through_map(game, [["beasts-2", "blackwood"]])
	game.end_turn_button.pressed.emit()
	_next_turn(game)
	assert_eq(session.turn_number(), 3)
	s = session.state()
	assert_eq(s.find_army("kingdom-1").location, "stonegate")
	assert_eq(s.find_army("beasts-2").location, "blackwood")
	assert_eq(s.find_faction("kingdom").gold, 60 + 12 + 6 + 8)  # 86
	assert_eq(s.find_faction("beasts").gold, 47 + 12 + 6 + 8)  # 73

	# Turn 3: Aurel Crown attacks Blackwood, which the Thornmane army holds; Thornmane recruits.
	_play_turn(game, [["kingdom-1", "blackwood"]], [["war_bear"]])
	_ready_up(game)
	assert_eq(session.turn_number(), 4)
	assert_eq(session.turns_played(), 3)
	assert_false(session.is_over())
	var battles := session.battle_events()
	assert_eq(battles.size(), 1, "one battle at Blackwood")
	assert_true(game.report_overlay.visible)
	_assert_report_matches_session(game)
	assert_eq(game.report_panel.battle_buttons().size(), 1, "the battle row has a battle report button")
	_assert_no_raw_ids(_visible_text(game), "turn report")

	# The battle report: the why on top, then every line of the full report from the battle rules.
	game.report_panel.battle_buttons()[0].pressed.emit()
	assert_true(game.battle_overlay.visible)
	var report: Dictionary = battles[0].numbers.report
	assert_false(report.is_empty(), "the real battle rules made a full report")
	assert_eq(game.battle_title.text, "Battle %s" % report.place)
	for clause in str(battles[0].numbers.why).split(";", false):
		assert_true(game.battle_why.text.to_lower().contains(clause.strip_edges().to_lower()), "why: %s" % clause)
	for line in report.lines:
		assert_true(game.battle_lines.text.contains(line), "report line: %s" % line)
	_assert_no_raw_ids(_visible_text(game), "battle report")
	game.free()


func test_same_config_and_orders_give_identical_games() -> void:
	var a := _game()
	var b := _game()
	for game in [a, b]:
		_play_turn(game, [["kingdom-1", "highcrag"], ["crossbowmen"]], [["beasts-2", "ironspike"]])
		_next_turn(game)
		_play_turn(game, [["kingdom-1", "thornvale"]], [["beasts-2", "wildmoor"]])
		_next_turn(game)
		# They swap Thornvale and Wildmoor: a border battle decided by the seeded battle rules.
		_play_turn(game, [["kingdom-1", "wildmoor"]], [["beasts-2", "thornvale"]])
	assert_eq(var_to_str(a.session.state().to_dict()), var_to_str(b.session.state().to_dict()))
	assert_eq(a.session.turn_report().events.map(func(e): return e.text),
		b.session.turn_report().events.map(func(e): return e.text))
	assert_eq(a.session.battle_events().size(), 1, "the swap was a border battle")
	assert_eq(a.session.history(), b.session.history())
	var replayed := GameSession.replay(a.session.record(), AutoBattleResolver.new())
	assert_eq(replayed.errors, [])
	assert_eq(var_to_str(replayed.state.to_dict()), var_to_str(a.session.state().to_dict()),
		"the screen plays with the real battle rules, so a replay with them matches")
	a.free()
	b.free()


func test_seat_two_never_sees_seat_one_orders() -> void:
	var game := _game()
	_order_through_map(game, [["kingdom-1", "westwatch"], ["knights"]])
	var mine := game.map.orders.order_texts()
	assert_eq(mine.size(), 2)
	assert_eq(_order_rows(game).size(), 2, "seat 1 sees both orders listed")
	assert_true(_visible_text(game).contains(mine[0]))
	game.end_turn_button.pressed.emit()
	assert_eq(game.map.orders.orders(), [], "nothing to draw while the computer is passed")
	var cover := _visible_text(game)
	for t in mine:
		assert_false(cover.contains(t), "the handoff hides: %s" % t)

	game.handoff.ready_button.pressed.emit()
	assert_eq(game.map.viewing_faction_id, "beasts")
	assert_eq(game.map.orders.orders(), [], "no arrows: seat 2 has no moves queued")
	assert_eq(_order_rows(game).size(), 0, "no order rows")
	assert_eq(game.end_turn_button.text, "End turn (no orders)")
	assert_eq(game.map.selected_army_id, "", "seat 1's selection is not carried over")
	assert_eq(game.map.status_text, "")
	var text := _visible_text(game)
	for t in mine:
		assert_false(text.contains(t), "seat 2 can't see: %s" % t)
	assert_false(game.map.queue_move("kingdom-1", "highcrag").is_empty(), "seat 2 can't order seat 1's army")
	assert_eq(game.session.current_orders(), [], "nothing was queued for seat 2")

	_order_through_map(game, [["beasts-2", "ebonpeak"]])
	game.end_turn_button.pressed.emit()
	var s := game.session.state()
	assert_eq(s.find_army("kingdom-1").location, "westwatch", "seat 1's orders still resolved")
	assert_eq(s.find_army("beasts-2").location, "ebonpeak")
	game.free()


func test_move_into_an_enemy_held_province_shows_forecast_battle_odds() -> void:
	var game := _game()
	_play_turn(game, [["kingdom-1", "westwatch"]], [["beasts-2", "ebonpeak"]])
	_next_turn(game)
	_play_turn(game, [["kingdom-1", "stonegate"]], [["beasts-2", "blackwood"]])
	_next_turn(game)
	var s := game.session.state()
	var odds := Forecast.battle_odds(s, "kingdom", ["kingdom-1"], "blackwood")
	assert_true(odds.ok, "the Thornmane army holds Blackwood, next to Stonegate")
	var verdict := "Battle odds: %s (you won %d of %d test battles)." % [odds.label, odds.wins, odds.samples]

	# Hovering before the click previews the move with its odds.
	game.map.select_army("kingdom-1")
	var preview := game.map.preview_move("blackwood")
	assert_true(game.map.hover_panel.visible)
	assert_true(preview.contains(verdict), preview)
	for r in odds.reasons:
		assert_true(preview.contains(r), "preview reason: %s" % r)
	assert_true(game.map.preview_move("thornvale").contains(OrdersController.NO_ENEMY_TEXT))

	# The click queues it: the order line has the verdict and reasons, its tooltip Forecast's full text.
	game.map.select_province("blackwood")
	assert_eq(game.session.current_orders().size(), 1)
	var rows := _order_rows(game)
	assert_eq(rows.size(), 1)
	var line: Label = rows[0].get_child(0)
	assert_true(line.text.contains(verdict), line.text)
	for r in odds.reasons:
		assert_true(line.text.contains(r), "order line reason: %s" % r)
	assert_true(line.tooltip_text.replace("\n", " ").contains(odds.text), "the tooltip has the full odds text")
	game.free()


func test_capturing_the_enemy_capital_shows_the_game_over_overlay() -> void:
	var game := _game()
	# Aurel Crown marches down the northern road while the Thornmane army wanders off south.
	for step in [["westwatch", "bloodfen"], ["stonegate", "deepwood"], ["blackwood", "greenglade"], ["ebonpeak", "rivermarch"]]:
		_play_turn(game, [["kingdom-1", step[0]]], [["beasts-2", step[1]]])
		_next_turn(game)
	_play_turn(game, [["kingdom-1", "fangridge"]], [])
	var session := game.session
	assert_eq(session.phase(), GameSession.Phase.GAME_OVER)
	assert_eq(session.winner(), "kingdom")
	assert_false(game.handoff.visible, "no handoff after the last turn")
	assert_true(game.victory_overlay.visible, "the game-over overlay shows")
	assert_eq(game.victory_label.text, session.victory().text)
	assert_eq(game.victory_title.text, "Aurel Crown wins")
	assert_true(game.end_turn_button.disabled, "End turn is disabled")
	assert_true(game.end_turn().contains("The game is over"))
	assert_eq(game.map.turn_label.text, "Turn 5")
	_assert_no_raw_ids(_visible_text(game), "game over")

	# The final turn report is one click away, with the victory banner on top.
	(game.victory_overlay.find_child("FinalReportButton", true, false) as Button).pressed.emit()
	assert_true(game.report_overlay.visible)
	assert_true(game.report_panel.victory_box.visible)
	assert_eq(game.report_panel.victory_label.text, session.victory().text)
	_assert_report_matches_session(game)
	game.close_turn_report()
	(game.victory_overlay.find_child("ViewMapButton", true, false) as Button).pressed.emit()
	assert_false(game.victory_overlay.visible, "the final map can be looked at")
	assert_true(game.map.visible)
	game.free()


func test_no_raw_ids_in_visible_text() -> void:
	var game := _game()
	_order_through_map(game, [["kingdom-1", "westwatch"], ["spearmen"]])
	game.map.select_army("kingdom-1")
	assert_false(game.map.preview_move("highcrag").is_empty())
	_assert_no_raw_ids(_visible_text(game), "orders with the recruit panel, order list and hover preview")
	game.map.back_button.pressed.emit()
	assert_true(game.quit_overlay.visible)
	_assert_no_raw_ids(_visible_text(game), "quit confirmation")
	game.quit_overlay.visible = false
	game.end_turn_button.pressed.emit()
	_assert_no_raw_ids(_visible_text(game), "handoff")
	game.handoff.ready_button.pressed.emit()
	_assert_no_raw_ids(_visible_text(game), "seat 2's orders phase")
	game.free()


# --- HUD, defaults and setup ----------------------------------------------------------------------

func test_quit_asks_first_and_codex_opens_as_an_overlay() -> void:
	var game := _game()
	assert_eq(game.map.back_button.text, "Quit to title")
	game.map.back_button.pressed.emit()
	assert_true(game.quit_overlay.visible, "quitting asks first")
	(game.quit_overlay.find_child("KeepPlayingButton", true, false) as Button).pressed.emit()
	assert_false(game.quit_overlay.visible)
	assert_eq(game.session.phase(), GameSession.Phase.ORDERS, "the game goes on")

	assert_false(game.codex.visible)
	game.codex_button.pressed.emit()
	assert_true(game.codex.visible, "the codex opens over the map")
	assert_true(game.codex.listed_keys().size() > 0)
	game.codex.close()
	assert_false(game.codex.visible)
	game.free()


func test_shown_without_start_game_it_starts_a_default_game() -> void:
	var defaults := GameScreen.default_config()
	var ids := []
	for f in FactionData.FACTIONS:
		ids.append(f.id)
	assert_eq(defaults.players, ids, "every faction, in data order")
	assert_eq(typeof(defaults.seed), TYPE_INT)

	var game := load(GAME_SCENE).instantiate() as GameScreen
	# The runner works before the tree is live, so call _ready the way the engine does on scene change.
	game._ready()
	assert_true(game.session != null, "a default game started")
	assert_eq(game.session.players(), ids)
	assert_eq(game.session.phase(), GameSession.Phase.ORDERS)
	assert_eq(game.map.viewing_faction_id, ids[0])
	assert_true(game.map.turn_label.tooltip_text.contains("Game seed %d" % game.config.seed))
	game.free()

	# A game started before the screen enters the tree is kept.
	var started := _game({"players": ["beasts", "kingdom"], "seed": 5})
	var session := started.session
	started._ready()
	assert_eq(started.session, session, "_ready does not replace a started game")
	assert_eq(started.map.viewing_faction_id, "beasts", "seat order comes from the config")
	started.free()


func test_a_bad_config_is_explained() -> void:
	var game := _game({"players": ["kingdom"], "seed": 1})
	assert_eq(game.session.phase(), GameSession.Phase.INVALID)
	assert_true(game.victory_overlay.visible)
	assert_eq(game.victory_title.text, "This game could not start")
	assert_true(game.victory_label.text.contains("at least two players"), game.victory_label.text)
	assert_true(game.end_turn_button.disabled)
	game.free()


func test_title_screen_has_a_quick_start_button() -> void:
	var title: Control = load("res://ui/title_screen.tscn").instantiate()
	var button := title.get_node_or_null("Center/Box/QuickStartButton") as Button
	assert_true(button != null, "the title screen has a Quick start button")
	if button:
		assert_eq(button.text, "Quick start")
		assert_false(button.tooltip_text.is_empty(), "the button explains itself")
	assert_true(title.get_node_or_null("Center/Box/MapPreviewButton") != null, "Map preview is still there")
	title.free()
