extends "res://tests/test_case.gd"
## Computer seats (#35) through the real screens, headless: the new game screen's Human / Computer and
## Easy / Normal choices and their config, a scripted human against the computer through GameScreen
## (no handoff, the computer's orders resolve, the report shows its notes only after resolution), the
## computer in seat 1, the "Computer (Normal)" tag in the top bar, the report header and the victory
## screen, the rematch keeping the seat kinds, watch mode, and no raw ids anywhere.

const GAME_SCENE := "res://ui/game_screen.tscn"
const NEW_GAME_SCENE := "res://ui/new_game_screen.tscn"
const SEED := 4242
const VS_COMPUTER := {"players": ["kingdom", "beasts"], "seed": SEED, "ai": {"beasts": "normal"}}
const RAW_IDS := ["kingdom", "beasts", "crownkeep", "fangridge", "westwatch", "ebonpeak", "stonegate",
	"blackwood", "highcrag", "ironspike", "rivermarch", "bloodfen", "thornvale", "wildmoor", "greenglade",
	"deepwood", "knight_captain", "warchief", "war_bear", "spearmen", "tuskers", "codex:", "computer_opponent"]
const WINDOW_WIDTH := 1600.0


func _game(config: Dictionary) -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.start_game(config)
	return game


## The human gives `orders` through the map: [army id, province id] is a two-click move, [unit type id]
## presses the capital's recruit button. Orders the rules refuse are skipped, like a player would.
func _order(game: GameScreen, orders: Array) -> void:
	for o in orders:
		if o.size() == 2:
			if game.map.state.find_army(o[0]) == null:
				continue
			game.map.select_army(o[0])
			game.map.select_province(o[1])
		else:
			game.map.selected_army_id = ""
			var f := game.map.state.find_faction(game.session.current_player())
			game.map.select_province(f.capital)
			for b in game.map.details.find_children("Recruit_%s" % o[0], "Button", true, false):
				if not (b as Button).disabled:
					(b as Button).pressed.emit()


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
	if node is OptionButton:
		for i in (node as OptionButton).item_count:
			out.append((node as OptionButton).get_item_text(i))
			out.append((node as OptionButton).get_popup().get_item_tooltip(i))
	if node is Control and not (node as Control).tooltip_text.is_empty():
		out.append((node as Control).tooltip_text)
	for c in node.get_children():
		_collect_text(c, out)


func _assert_no_raw_ids(text: String, what: String) -> void:
	assert_false(text.is_empty(), "%s has text" % what)
	for id in RAW_IDS:
		assert_false(text.contains(id), "%s shows no raw id '%s'" % [what, id])


# --- the new game screen --------------------------------------------------------------------------

func test_new_game_screen_offers_human_or_computer_per_seat() -> void:
	var screen := load(NEW_GAME_SCENE).instantiate() as NewGameScreen
	assert_eq(screen.kind_pickers.size(), 2)
	assert_eq(screen.seat_kind(1), "human", "both seats start human, so the hotseat default is unchanged")
	assert_eq(screen.seat_kind(2), "human")
	assert_false(screen.config().has("ai"), "an all-human config is exactly {players, seed}")
	assert_false(screen.level_pickers[1].visible, "no level for a human seat")
	assert_false(screen.computer_label.visible)

	# Through the dropdown, as a player would.
	screen.kind_pickers[1].select(1)
	screen.kind_pickers[1].item_selected.emit(1)
	assert_eq(screen.seat_kind(2), "computer")
	assert_true(screen.level_pickers[1].visible, "the level shows for a computer seat")
	assert_eq(screen.seat_level(2), "normal", "Normal by default")
	assert_eq(screen.config().ai, {"beasts": "normal"})
	assert_true(screen.computer_label.visible, "the screen explains how the computer plays")
	assert_true(screen.computer_title.visible)
	assert_false(screen.hotseat_label.visible, "in place of the hotseat explanation, which doesn't apply")
	assert_true(screen.faction_labels[1].text.ends_with("The computer plays this seat at the Normal level."), screen.faction_labels[1].text)
	assert_true(screen.faction_labels[0].text.begins_with("Plays in Vermilion"), "seat 1's line is unchanged")
	screen.level_pickers[1].select(0)
	screen.level_pickers[1].item_selected.emit(0)
	assert_eq(screen.config().ai, {"beasts": "easy"})
	assert_true(screen.is_valid())
	_assert_no_raw_ids(_visible_text(screen), "new game screen with a computer seat")
	for t in _visible_text(screen).split("\n"):
		assert_false(t.contains("_"), "no underscores on screen: %s" % t)

	# Swap seats: the factions trade places, each seat keeps its player.
	screen.swap_seats()
	assert_eq(screen.seat_kind(2), "computer", "seat 2 is still the computer")
	assert_eq(screen.config().players, ["beasts", "kingdom"])
	assert_eq(screen.config().ai, {"kingdom": "easy"}, "now playing the other faction")

	# Every seat the computer: watch mode is allowed and explained.
	assert_true(screen.set_seat_kind(1, "computer"))
	assert_true(screen.is_valid(), "the computer may play every seat (watch mode)")
	assert_true(screen.computer_label.text.contains("you will watch"), screen.computer_label.text)
	assert_eq(screen.config().ai, {"beasts": "normal", "kingdom": "easy"})
	assert_false(screen.set_seat_kind(3, "computer"), "no third seat")
	assert_false(screen.set_seat_kind(1, "robot"), "no such kind")
	assert_false(screen.set_seat_level(1, "hard"), "no such level")

	# Start hands the config on, and the session accepts it.
	var started := []
	screen.start_requested.connect(func(c: Dictionary): started.append(c))
	assert_true(screen.set_seat_kind(1, "human"))
	assert_true(screen.start())
	assert_eq(started.size(), 1)
	var cfg: Dictionary = started[0]
	assert_eq(cfg.ai, {"kingdom": "easy"})
	var session := GameSession.new(GameState.new(cfg.seed), cfg.players, cfg.seed, null, cfg.ai)
	assert_eq(session.setup_errors(), [], "GameSession accepts the config")
	screen.free()


func test_prefill_restores_seat_kinds_and_levels() -> void:
	var screen := load(NEW_GAME_SCENE).instantiate() as NewGameScreen
	screen.prefill({"players": ["beasts", "kingdom"], "seed": 5, "ai": {"kingdom": "easy"}})
	assert_true(screen.rematch_label.visible)
	assert_eq(screen.seat_kind(1), "human")
	assert_eq(screen.seat_kind(2), "computer")
	assert_eq(screen.seat_level(2), "easy")
	assert_eq(screen.config().players, ["beasts", "kingdom"])
	assert_eq(screen.config().ai, {"kingdom": "easy"})
	assert_ne(screen.config().seed, 5, "a new seed")
	# A hotseat rematch turns every seat back to human.
	screen.prefill({"players": ["kingdom", "beasts"], "seed": 6})
	assert_eq(screen.seat_kind(2), "human")
	assert_false(screen.config().has("ai"))
	screen.free()


# --- human against the computer -------------------------------------------------------------------

func test_a_human_plays_the_computer_through_the_game_screen_with_no_handoff() -> void:
	var game := _game(VS_COMPUTER)
	var session := game.session
	assert_eq(game.config, VS_COMPUTER, "the config is kept as given")
	assert_eq(session.computer_seats(), {"beasts": "normal"})
	assert_false(game.handoff.visible, "no handoff to start")
	assert_true(game.map.visible)
	assert_eq(game.map.viewing_faction_id, "kingdom", "the human has the map")
	assert_false(game.report_overlay.visible, "no report before the first turn")
	assert_true(game.report_button.disabled)

	# The top bar names the computer faction with its tag, linked to the codex.
	assert_true(game.opponent_box.visible, "the top bar shows the opponent")
	assert_eq(game.opponent_box.get_parent(), game.map.faction_label.get_parent(), "in the player's own name group")
	assert_eq(game.opponent_box.get_index(), game.map.faction_label.get_index() + 1, "right after the player's own name")
	var bar_text := _visible_text(game.opponent_box)
	assert_true(bar_text.contains("Thornmane Clans"), bar_text)
	var tags := game.opponent_box.find_children("ComputerTag", "Label", true, false)
	assert_eq(tags.size(), 1)
	assert_eq((tags[0] as Label).text, "Computer (Normal)")
	assert_true((tags[0] as Label).tooltip_text.contains("Codex: Playing against the computer (right-click or F1 to open)"), (tags[0] as Label).tooltip_text)
	(tags[0] as Label).gui_input.emit(CodexLink.right_click())
	assert_true(game.codex.visible, "right-clicking the tag opens the codex")
	assert_eq(game.codex.current_key(), "computer_opponent")
	game.codex.close()
	assert_true(game.end_turn_button.tooltip_text.contains("never seeing yours"), game.end_turn_button.tooltip_text)
	assert_true(game.map.hint_label.text.begins_with("Move: select an army"), game.map.hint_label.text)
	assert_true(game.map.hint_label.tooltip_text.contains("You give orders as Aurel Crown"), game.map.hint_label.tooltip_text)
	_assert_no_raw_ids(_visible_text(game), "the first orders phase")

	var script := [
		[["kingdom-1", "westwatch"], ["spearmen"], ["spearmen"]],
		[["kingdom-1", "stonegate"], ["crossbowmen"]],
		[["spearmen"], ["spearmen"]],
		[["kingdom-1", "westwatch"], ["knights"]],
	]
	for t in script.size():
		if session.is_over():
			break
		assert_eq(session.current_player(), "kingdom", "turn %d: the human's turn" % session.turn_number())
		_order(game, script[t])
		var queued := session.current_orders().size()
		game.end_turn_button.pressed.emit()
		assert_false(game.handoff.visible, "turn %d: no handoff, ever" % (t + 1))
		if session.is_over():
			break
		assert_eq(session.turns_played(), t + 1, "the computer played at once and the turn resolved")
		assert_eq(session.phase(), GameSession.Phase.ORDERS)
		assert_eq(session.current_player(), "kingdom", "straight back to the human")
		var last: Dictionary = session.history().back()
		assert_eq(last.orders.get("kingdom", []).size(), queued, "the human's orders resolved")
		assert_false(last.orders.get("beasts", []).is_empty(), "and so did the computer's")
		assert_eq(game.computer.rejections(), [], "the session refused none of the computer's orders")

		# The report opens by itself, names the seats with the tag, and ends with the computer's notes.
		assert_true(game.report_overlay.visible, "turn %d: the report opens" % (t + 1))
		var panel := game.report_panel
		assert_eq(panel.header_label.text, "Turn %d results" % (t + 1))
		assert_true(panel.seats_box.visible, "the report header names the seats")
		var header_tags := panel.seats_box.find_children("ComputerTag", "Label", true, false)
		assert_eq(header_tags.size(), 1)
		assert_eq((header_tags[0] as Label).text, "Computer (Normal)")
		assert_true(_visible_text(panel.seats_box).contains("Aurel Crown (you)"), _visible_text(panel.seats_box))
		var expected: Array = game.computer.report_notes(session)
		assert_eq(expected.size(), 1)
		var shown := panel.computer_note_labels().map(func(l): return l.text)
		assert_eq(shown, expected[0].notes.map(func(n): return "•  %s" % n), "the notes of the turn that just resolved")
		assert_true(panel.notes_toggle.text.begins_with("What the computer was thinking"), panel.notes_toggle.text)
		_assert_no_raw_ids(_visible_text(game), "turn %d report" % (t + 1))
		game.close_turn_report()

	# During the human's orders nothing about the computer's coming orders is on screen, and reopening the
	# report shows the resolved turn's notes again, not a new plan.
	var notes_before: Array = game.computer.report_notes(session)
	game.open_turn_report()
	assert_eq(game.report_panel.computer_note_labels().size(), notes_before[0].notes.size())
	game.close_turn_report()
	game.free()


func test_the_notes_section_folds_and_remembers() -> void:
	var game := _game(VS_COMPUTER)
	game.end_turn_button.pressed.emit()
	var panel := game.report_panel
	assert_true(panel.notes_section.visible, "the section is there")
	assert_eq(panel.notes_section.get_parent(), panel.scroll.get_parent(), "pinned beside the events, not scrolled away with them")
	assert_true(panel.notes_section.get_index() > panel.scroll.get_index(), "under the events")
	assert_true(panel.notes_scroll.visible, "open the first time")
	assert_true(panel.notes_scroll.custom_minimum_size.y > 0 and panel.notes_scroll.custom_minimum_size.y <= TurnReportPanel.NOTES_MAX_HEIGHT)
	panel.notes_toggle.pressed.emit()
	assert_false(panel.notes_scroll.visible, "a click folds it")
	assert_true(panel.notes_toggle.text.ends_with("click to show"), panel.notes_toggle.text)
	game.close_turn_report()
	game.end_turn_button.pressed.emit()
	assert_false(game.report_panel.notes_scroll.visible, "and it stays folded next turn")
	assert_true(game.report_panel.notes_toggle.tooltip_text.contains("Codex: Playing against the computer"), game.report_panel.notes_toggle.tooltip_text)
	game.free()


func test_the_computer_in_seat_one_plays_first_from_the_start_of_turn_state() -> void:
	var config := {"players": ["kingdom", "beasts"], "seed": SEED, "ai": {"kingdom": "easy"}}
	var game := _game(config)
	var session := game.session
	assert_eq(session.current_player(), "beasts", "the computer already gave its turn 1 orders")
	assert_eq(session.turn_number(), 1)
	assert_false(game.handoff.visible)
	assert_eq(game.map.viewing_faction_id, "beasts")
	assert_eq(session.current_orders(), [], "the human sees only their own (empty) orders")
	assert_false(game.report_overlay.visible, "nothing has resolved, so no report and no notes")
	var tags := game.opponent_box.find_children("ComputerTag", "Label", true, false)
	assert_eq((tags[0] as Label).text, "Computer (Easy)")

	var start := GameState.new(SEED)
	var expected := AIPlayer.new()
	expected.plan_orders(start, "kingdom", SeededRNG.new(AISeat.seat_seed(SEED, 0)), "easy")
	game.end_turn_button.pressed.emit()
	assert_eq(session.turns_played(), 1)
	assert_eq(session.current_player(), "beasts", "turn 2: the computer has planned again, the human is up")
	assert_true(game.report_overlay.visible)
	assert_eq(game.report_panel.computer_note_labels().map(func(l): return l.text),
		expected.last_plan_notes().map(func(n): return "•  %s" % n), "the turn 1 notes, never the plan for turn 2")
	game.free()


func test_same_seed_and_human_orders_give_the_same_game() -> void:
	var a := _game(VS_COMPUTER)
	var b := _game(VS_COMPUTER)
	for game in [a, b]:
		for orders in [[["kingdom-1", "westwatch"], ["spearmen"]], [["kingdom-1", "stonegate"]], [["knights"]]]:
			_order(game, orders)
			game.end_turn_button.pressed.emit()
			game.close_turn_report()
	assert_eq(a.session.turns_played(), 3)
	assert_eq(var_to_str(a.session.state().to_dict()), var_to_str(b.session.state().to_dict()), "same final state")
	assert_eq(a.session.history(), b.session.history(), "same orders, the computer's included")
	var replayed := GameSession.replay(a.session.record(), AutoBattleResolver.new())
	assert_eq(replayed.errors, [])
	assert_eq(var_to_str(replayed.state.to_dict()), var_to_str(a.session.state().to_dict()), "the replay matches")
	a.free()
	b.free()


func test_rematch_keeps_the_seat_kinds_and_levels() -> void:
	var config := {"players": ["beasts", "kingdom"], "seed": SEED, "ai": {"kingdom": "easy"}}
	var game := _game(config)
	game.victory_screen.new_game_button.pressed.emit()  # what the victory screen's New game does
	var title := game.next_scene as TitleScreen
	assert_true(title != null and title.new_game_screen != null and title.new_game_screen.visible)
	if title and title.new_game_screen:
		var setup := title.new_game_screen
		assert_eq(setup.config().players, ["beasts", "kingdom"], "the same seats")
		assert_eq(setup.config().ai, {"kingdom": "easy"}, "the same computer seat at the same level")
		assert_eq(setup.seat_kind(1), "human")
		assert_eq(setup.seat_kind(2), "computer")
		assert_eq(setup.seat_level(2), "easy")
		assert_ne(setup.config().seed, SEED, "a new seed")
		title.free()
	game.free()


func test_a_hotseat_game_has_no_computer_anything() -> void:
	var game := _game({"players": ["kingdom", "beasts"], "seed": SEED})
	assert_eq(game.config, {"players": ["kingdom", "beasts"], "seed": SEED}, "no ai key")
	assert_eq(game.computer.factions(), [])
	assert_false(game.opponent_box.visible, "no opponent tag in the top bar")
	game.end_turn_button.pressed.emit()
	assert_true(game.handoff.visible, "two humans still hand off")
	game.handoff.ready_button.pressed.emit()
	game.end_turn_button.pressed.emit()
	game.handoff.ready_button.pressed.emit()
	assert_true(game.report_overlay.visible)
	assert_false(game.report_panel.seats_box.visible, "the report header is unchanged")
	assert_false(game.report_panel.notes_section.visible, "and there is no notes section")
	assert_eq(game.report_panel.notes_toggle, null)
	game.free()


func test_a_bad_ai_config_is_explained() -> void:
	var game := _game({"players": ["kingdom", "beasts"], "seed": 1, "ai": {"beasts": "hard"}})
	assert_eq(game.session.phase(), GameSession.Phase.INVALID)
	assert_true(game.error_overlay.visible)
	assert_true(game.error_label.text.contains("Easy and Normal"), game.error_label.text)
	game.free()
	game = _game({"players": ["kingdom", "beasts"], "seed": 1, "ai": ["beasts"]})
	assert_true(game.error_overlay.visible, "an ai list instead of faction: level is explained too")
	game.free()


# --- the victory screen ---------------------------------------------------------------------------

## A session on a hand-made map where the Aurel Crown walks into an empty Fangridge on turn 1.
func _won_session(ai: Dictionary) -> GameSession:
	var s := GameState.new(99)
	s.armies.clear()
	var a := Army.new()
	a.id = "kingdom-1"
	a.owner = "kingdom"
	a.location = "ebonpeak"
	a.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction("kingdom"), "knights"), "kingdom"))
	s.armies.append(a)
	s.find_province("ebonpeak").owner = "kingdom"
	var session := GameSession.new(s, ["kingdom", "beasts"], 7, StubBattleResolver.new(), ai)
	assert_eq(session.queue_order(MoveOrder.new("kingdom-1", "fangridge")), "")
	assert_eq(session.end_turn(), "")
	if ai.is_empty():
		assert_eq(session.acknowledge_handoff(), "", "two humans hand off")
	else:
		assert_eq(session.phase(), GameSession.Phase.ORDERS, "no handoff with one human")
	assert_eq(session.end_turn(), "")
	assert_true(session.is_over())
	return session


func test_the_victory_screen_tags_the_computer() -> void:
	var screen := VictoryScreen.new()
	assert_true(screen.show_for(_won_session({"beasts": "normal"})))
	assert_eq(screen.headline_label.text, "Aurel Crown wins")
	assert_eq(screen.seat_label.text, "You beat the computer (Normal).")
	var rows := screen.province_labels()
	assert_eq(rows.size(), 2)
	assert_eq(rows[0].get_parent().find_children("ComputerTag", "", false, false).size(), 0, "no tag for the human")
	var tag := rows[1].get_parent().find_child("ComputerTag", false, false) as Label
	assert_true(tag != null, "the computer's row has the tag")
	if tag:
		assert_eq(tag.text, "Computer (Normal)")
		var asked := []
		screen.codex_requested.connect(func(k: String): asked.append(k))
		tag.gui_input.emit(CodexLink.right_click())
		assert_eq(asked, ["computer_opponent"], "the tag links to the codex")
	_assert_no_raw_ids(_visible_text(screen), "victory screen against the computer")

	assert_true(screen.show_for(_won_session({"kingdom": "easy"})))
	assert_eq(screen.seat_label.text, "Player 1, the computer (Easy), wins the game.")
	assert_true(screen.show_for(_won_session({})))
	assert_eq(screen.seat_label.text, "Player 1 wins the game.", "hotseat wording unchanged")
	assert_eq(screen.find_children("ComputerTag", "", true, false).filter(func(n): return not n.is_queued_for_deletion()).size(), 0)
	screen.free()


# --- watch mode -----------------------------------------------------------------------------------

func test_watch_mode_plays_one_turn_per_next_turn() -> void:
	var game := _game({"players": ["kingdom", "beasts"], "seed": SEED, "ai": {"kingdom": "normal", "beasts": "easy"}})
	var session := game.session
	assert_true(game.is_watching())
	assert_eq(session.turns_played(), 0, "nothing plays until Next turn")
	assert_eq(game.end_turn_button.text, "Next turn")
	assert_false(game.end_turn_button.disabled)
	assert_eq(game.map.faction_label.text, "Watching")
	assert_eq(game.opponent_box.find_children("ComputerTag", "Label", true, false).size(), 2, "both computers tagged in the top bar")
	for t in 3:
		game.end_turn_button.pressed.emit()
		if session.is_over():
			break
		assert_eq(session.turns_played(), t + 1, "one turn per press")
		assert_false(game.handoff.visible)
		assert_true(game.report_overlay.visible)
		assert_eq(game.computer.report_notes(session).size(), 2, "both computers' notes")
		assert_eq(game.report_panel.seats_box.find_children("ComputerTag", "Label", true, false).size(), 2)
		_assert_no_raw_ids(_visible_text(game), "watch mode turn %d" % (t + 1))
		game.close_turn_report()
	game.free()


# --- the top bar ----------------------------------------------------------------------------------

## The opponent tag fits the 1600 px top bar next to everything else, and the hint still wraps into its
## two lines (measured like tests/test_top_bar.gd).
func test_top_bar_fits_with_the_opponent_tag() -> void:
	for config in [VS_COMPUTER, {"players": ["beasts", "kingdom"], "seed": SEED, "ai": {"kingdom": "normal"}},
			{"players": ["kingdom", "beasts"], "seed": SEED, "ai": {"kingdom": "normal", "beasts": "normal"}}]:
		var game := _game(config)
		if not game.is_watching():
			var s := game.session.state()
			s.find_faction(game.session.current_player()).gold = 9999
			game.map.set_state(s, game.session.current_player())
			game.end_turn_button.text = "End turn (12 orders)"
		_refresh_theme(game.map)
		var row := game.map.back_button.get_parent() as HBoxContainer
		var bar := row.get_parent() as PanelContainer
		var style := bar.get_theme_stylebox("panel")
		var available := WINDOW_WIDTH - style.get_margin(SIDE_LEFT) - style.get_margin(SIDE_RIGHT)
		var used := 0.0
		var shown := 0
		for c in row.get_children():
			var control := c as Control
			if control == null or not control.visible:
				continue
			shown += 1
			if control != game.map.hint_label:
				used += _min_width(control)
		var hint_width := available - used - row.get_theme_constant("separation") * (shown - 1)
		var lines := _wrapped_lines(game.map.hint_label, hint_width)
		assert_true(hint_width >= 240.0, "%s: the hint keeps a usable width (%d px)" % [config, hint_width])
		assert_true(lines <= 2, "%s: the hint fits in two lines at %d px, it needs %d: %s" % [config, hint_width, lines, game.map.hint_label.text])
		game.free()


func _min_width(c: Control) -> float:
	if c is BoxContainer:
		var total := 0.0
		var n := 0
		for k in c.get_children():
			if k is Control and (k as Control).visible:
				total += _min_width(k) if not (c is VBoxContainer) else 0.0
				n += 1
		if c is VBoxContainer:
			for k in c.get_children():
				if k is Control and (k as Control).visible:
					total = maxf(total, _min_width(k))
			return maxf(c.custom_minimum_size.x, total)
		return maxf(c.custom_minimum_size.x, total + c.get_theme_constant("separation") * maxi(n - 1, 0))
	return maxf(c.custom_minimum_size.x, c.get_minimum_size().x)


func _wrapped_lines(label: Label, width: float) -> int:
	var paragraph := TextParagraph.new()
	paragraph.add_string(label.text, label.get_theme_font("font"), label.get_theme_font_size("font_size"))
	paragraph.width = width
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	return paragraph.get_line_count()


func _refresh_theme(n: Node) -> void:
	if n is Control:
		n.notification(Control.NOTIFICATION_THEME_CHANGED)
	for c in n.get_children():
		_refresh_theme(c)


# --- the codex ------------------------------------------------------------------------------------

func test_the_codex_explains_the_computer_opponent() -> void:
	var e := RulesCodex.entry("computer_opponent")
	assert_eq(String(e.get("title", "")), "Playing against the computer")
	var text := RulesCodex.text("computer_opponent")
	for part in ["same rules", "same map", "at the same time", "never sees the orders you give", "Easy", "Normal"]:
		assert_true(text.contains(part), "the entry says '%s': %s" % [part, text])
	assert_false(text.contains("[") or text.contains("_"), "plain text, so tooltips can quote it")
	var keys := RulesCodex.ENTRIES.keys()
	assert_eq(keys.find("computer_opponent"), keys.find("unit_traits") + 1, "placed right after the basic terms")
