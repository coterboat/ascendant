extends "res://tests/test_case.gd"
## UX-1 (#194; design/UX_WAR_TABLE.md §1): the Table. The top bar, the hint row and the side panel are gone; the board fills the
## screen and the TableHud sits over it. Headless, through the real screens (the live layout pass is tests/table_probe.gd's,
## checked in test_table_geometry.gd and test_screens_fit.gd). What each test pins:
##   the Table fits a logical 1600x900 and a 1280x720 window with nothing clipped (the old top bar's fit test, moved);
##   after game over the plaque has no gap where gold was, and Results takes the seal's place;
##   the input contract (§1.2): the HUD's root and every empty area ignore the mouse, only the pieces take it;
##   the realm plaque keeps every breakdown tooltip and codex link the top bar had, and a ruler line with its own;
##   the system row opens today's panels as they are; the Chronicle and Lenses are placeholders for later tickets;
##   the ? lists every key and mouse binding (checked against the board's own code) and today's hint text in full;
##   the seal shows End turn and the order count, and pulses for a new player once an order is queued;
##   the tray's Orders button brings the temporary details card back, so no order is ever out of reach;
##   the opponent plaque: banner, name, tag, the codex link, the fog's "last seen" line; rebuilt per viewer in a hotseat game;
##   the temporary details card is today's side panel: shown on a selection, closable, closed for good until a click;
##   the four host seams (SelectionHost, ReportHost, LensHost, UiCancel) and what each does with a stand-in;
##   hotseat: the handoff rebuilds the HUD for the next player and nothing of the last is left.
## Numbers and words come from the data and the rules, never from this file.

const GAME_SCENE := "res://ui/game_screen.tscn"
const MAP_SCENE := "res://ui/map_screen.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"
const VS_COMPUTER := {"players": [CROWN, CLANS], "seed": 4242, "ai": {CLANS: "normal"}}
const ALL := {"rulers": true, "paths": true, "sieges": true, "fog": true, "magic": true, "independents": true}
const WIDE := Vector2(1600, 900)
const NARROW := Vector2(1280, 720)


# --- fixtures -------------------------------------------------------------------------------------

func _game(config: Dictionary = VS_COMPUTER) -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.start_game(config)
	return game


func _all_on() -> Dictionary:
	var config := VS_COMPUTER.duplicate()
	config.merge(ALL)
	return config


func _hotseat(extra: Dictionary = {}) -> GameScreen:
	var config := {"players": [CROWN, CLANS], "seed": 77}
	config.merge(extra)
	return _game(config)


## Every visible text of `node`: labels, buttons, rich text.
func _texts(node: Node) -> String:
	var out := PackedStringArray()
	_collect(node, out)
	return "\n".join(out)


func _collect(node: Node, out: PackedStringArray) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is RichTextLabel:
		out.append((node as RichTextLabel).get_parsed_text())
	elif node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	for c in node.get_children():
		_collect(c, out)


func _unseen() -> void:
	GameSettings.reset_hint(GameSettings.HINT_FIRST_GAME)
	GameSettings.reset_hint("fog")
	for h in GameScreen.SEAL_HINTS:
		GameSettings.reset_hint(h)


# --- fit: the old top bar's tests, for the Table ---------------------------------------------------

func test_the_table_fits_at_both_logical_sizes_during_orders() -> void:
	# The Thornmane Clans have the longer name; try both seatings, with orders queued.
	for seats in [["beasts", "kingdom"], ["kingdom", "beasts"]]:
		var game := _game({"players": seats, "seed": 77})
		game.map.select_province(game.map.state.find_faction(seats[0]).capital)
		for i in 2:
			(game.map.details.find_children("Recruit_*", "Button", true, false)[0] as Button).pressed.emit()
		assert_true(game.end_turn_button.text.contains("2 orders"), game.end_turn_button.text)
		_assert_fits(game.map, "%s, orders" % [seats])
		# A rich late game: four-digit gold makes the gold label wider.
		var s := game.session.state()
		s.find_faction(seats[0]).gold = 9999
		game.map.set_state(s, seats[0])
		assert_true(game.map.gold_label.text.begins_with("Gold 9999"), game.map.gold_label.text)
		_assert_fits(game.map, "%s, 9999 gold" % [seats])
		game.free()


func test_the_table_fits_with_every_system_on_and_with_the_opponent_plaque() -> void:
	for config in [_all_on(), VS_COMPUTER, {"players": [CLANS, CROWN], "seed": 4242, "ai": {CROWN: "normal"}},
			{"players": [CROWN, CLANS], "seed": 4242, "ai": {CROWN: "normal", CLANS: "normal"}}]:
		var game := _game(config)
		_assert_fits(game.map, "%s" % [config.keys()])
		game.free()


func test_after_game_over_the_plaque_has_no_gap_where_gold_was_and_results_takes_the_seal() -> void:
	var game := _hotseat()
	var map := game.map
	assert_true(map.gold_label.visible, "gold shows while a player gives orders")
	# The Aurel Crown marches up the northern road to Fangridge while the Thornmane army goes south.
	for step in [["westwatch", "bloodfen"], ["stonegate", "deepwood"], ["blackwood", "greenglade"], ["ebonpeak", "rivermarch"], ["fangridge", ""]]:
		assert_eq(game.session.queue_move("kingdom-1", step[0]), "")
		game.end_turn()
		game.handoff.ready_button.pressed.emit()
		if not String(step[1]).is_empty():
			assert_eq(game.session.queue_move("beasts-1", step[1]), "")
		game.end_turn()
		if game.session.is_over():
			break
		game.handoff.ready_button.pressed.emit()
	assert_true(game.session.is_over(), "Fangridge fell")
	assert_eq(map.faction_label.text, "Game over")
	assert_false(map.gold_label.visible, "no gold label (and no empty slot) once nobody is playing")
	assert_false(map.faction_emblem.visible, "and no player's emblem")
	assert_true(game.results_button.visible)
	assert_false(game.end_turn_button.visible, "Results takes the seal's place")
	assert_eq(game.results_button.get_parent(), game.end_turn_button.get_parent(), "in the same slot")
	assert_false(game.map.table().opponent_panel.visible, "no rivals to show once the game is over")
	assert_false(game.map.table().seal_pulsing())
	for c in map.table().plaque_row.find_children("*", "Label", true, false):
		if (c as Label).visible:
			assert_false((c as Label).text.strip_edges().is_empty(), "no visible empty label in the plaque: %s" % c.name)
	assert_true(map.hint_label.text.begins_with("The game is over."), map.hint_label.text)
	_assert_fits(map, "game over")
	game.free()


func test_map_preview_table_fits() -> void:
	var map: MapScreen = load(MAP_SCENE).instantiate()
	map._ready()
	assert_true(map.gold_label.visible and map.faction_emblem.visible, "the preview is Player 1's view")
	assert_eq(map.back_button.text, "Back to title", "the Menu button leads back to the title in the preview")
	assert_false(map.table().seal.visible, "no seal without a game")
	_assert_fits(map, "map preview")
	map.free()


# --- the input contract ----------------------------------------------------------------------------

func test_the_hud_root_and_every_empty_area_ignore_the_mouse() -> void:
	for config in [VS_COMPUTER, _all_on()]:
		var game := _game(config)
		game.map.select_province(game.map.state.find_faction(CROWN).capital)
		var hud := game.map.table()
		assert_eq(hud.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the root ignores the mouse")
		var pieces := hud.pieces()
		var bad := []
		_walk_filters(hud, pieces, bad)
		assert_eq(bad, [], "every control outside a piece ignores the mouse (a piece is on TableHud.pieces)")
		for p in pieces:
			assert_ne((p as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s is a piece: it eats its own clicks" % p.name)
		for empty in [hud.left_column, hud.system_row, hud.right_column, hud.bottom_row, hud.plaque_row, hud.plaque_trail, hud.notification_stack,
				hud.tray_tokens, hud.opponent_slot, hud.seal_slot]:
			assert_eq((empty as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s is an empty area" % empty.name)
		assert_eq(game.map.hover_panel.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the move forecast never takes a click")
		game.free()


## Every control under `node` that is not inside a piece must ignore the mouse.
func _walk_filters(node: Node, pieces: Array, bad: Array) -> void:
	for c in node.get_children():
		var control := c as Control
		if control == null:
			continue
		if pieces.has(control):
			continue  # a piece (and what is inside it) may take the mouse
		if control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			bad.append("%s (%s)" % [control.name, control.get_class()])
		_walk_filters(control, pieces, bad)


func test_the_table_sits_over_the_map_view_under_the_overlays() -> void:
	var game := _game()
	var map := game.map
	assert_true(map.hud.get_parent() == map and map.hud.get_index() > map.map_view.get_index(), "over the map view")
	assert_true(game.overlays is CanvasLayer and game.overlays.layer > 0, "and under the Overlays layer, which is a higher canvas layer")
	assert_eq(map.map_view.anchor_right, 1.0, "the map view fills the screen")
	assert_eq(map.map_view.anchor_bottom, 1.0)
	assert_true(map.get_node_or_null("Layout") == null, "no top bar, hint row or side panel: no Layout")
	game.free()


# --- the realm plaque ------------------------------------------------------------------------------

func test_the_realm_plaque_keeps_every_breakdown_and_codex_link() -> void:
	var game := _game(VS_COMPUTER)
	var map := game.map
	var hud := map.table()
	var f := map.state.find_faction(CROWN)
	var gold := Breakdown.gold(map.state, CROWN)
	assert_eq(map.gold_label.text, "Gold %d   (+%d per turn)" % [f.gold, int(gold.total) - f.gold], "gold with its income")
	assert_true(map.gold_label.tooltip_text.begins_with(TooltipText.from_breakdown(gold)), "the gold's breakdown tooltip, as the top bar had")
	assert_eq(CodexLink.key_at(map.gold_label), "gold", "linked to its entry")
	var turn := Breakdown.turn(map.state)
	assert_true(game.map.turn_label.tooltip_text.contains("Game seed"), "the turn's tooltip names the seed")
	assert_eq(CodexLink.key_at(map.turn_label), TooltipText.codex_for("turn"), "the turn is linked")
	assert_eq(map.turn_label.text, "Turn %d" % game.session.turn_number(), "(%s)" % String(turn.title))
	assert_true(map.faction_label.tooltip_text.contains("You are playing"), "the name says whose map it is")
	assert_eq(CodexLink.key_at(map.faction_label), TooltipText.codex_for("faction"))
	for label in [map.faction_label, map.gold_label, map.turn_label]:
		assert_true(hud.plaque.is_ancestor_of(label), "%s is in the realm plaque" % label.name)
		assert_ne(label.mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s keeps its tooltip" % label.name)
	assert_false(map.ruler_line.visible, "no ruler line in a game without rulers")
	game.free()


func test_the_ruler_line_shows_the_ruler_and_kept_power_and_opens_the_ruler_panel() -> void:
	var game := _game({"players": [CROWN, CLANS], "seed": 77, "rulers": true})
	var map := game.map
	var line := map.ruler_line
	assert_true(line.visible, "a game with rulers shows the ruler")
	assert_true(map.table().plaque.is_ancestor_of(line), "in the realm plaque")
	assert_true(line.text.contains(RulerRules.current_name(map.state, CROWN)), line.text)
	assert_true(line.text.contains(str(RulerRules.kept_power(map.state, CROWN))), "with its kept power: %s" % line.text)
	assert_true(line.tooltip_text.begins_with(TooltipText.from_breakdown(Breakdown.kept_power(map.state, CROWN))), "the kept power's breakdown")
	assert_eq(CodexLink.key_at(line), "ruler", "linked to the ruler's entry")
	line.pressed.emit()
	assert_true(map.ruler_panel != null and map.ruler_panel.visible, "a click opens the Ruler panel")
	game.free()


# --- the system row --------------------------------------------------------------------------------

func test_the_system_row_opens_todays_panels_as_they_are() -> void:
	var game := _game(_all_on())
	game.close_turn_report()
	var hud := game.map.table()
	for id in ["research", "magic", "ruler", "chronicle", "report", "lenses", "codex", "help"]:
		assert_true(hud.system_button(id) != null, "the system row has %s" % id)
		assert_true(hud.system_row.is_ancestor_of(hud.system_button(id)), "%s is in the row" % id)
		assert_false(hud.system_button(id).tooltip_text.is_empty(), "%s has a tooltip that names it" % id)
	# Research and Magic: the research panel, the second on its Magic tab; modal, as today.
	hud.system_button("research").pressed.emit()
	assert_true(game.research_hud.panel != null and game.research_hud.panel.visible, "Research opens the research panel")
	assert_eq(game.research_hud.panel.get_parent(), game.overlays, "on the overlays, with its dimmer")
	game.research_hud.close_all()
	hud.system_button("magic").pressed.emit()
	assert_true(game.research_hud.panel.visible, "Magic opens it")
	assert_true(_texts(game.research_hud.panel).contains("Magic (the arcana)"), "on the Magic tab")
	game.research_hud.close_all()
	# Ruler, Codex and ?.
	hud.system_button("ruler").pressed.emit()
	assert_true(game.map.ruler_panel != null and game.map.ruler_panel.visible, "Ruler opens the ruler panel")
	game.map.close_ruler_panel()
	hud.system_button("codex").pressed.emit()
	assert_true(game.codex.visible, "Codex opens the codex")
	game.codex.close()
	hud.system_button("help").pressed.emit()
	assert_true(game.help_overlay.visible, "? opens the list of keys")
	game.help_overlay.visible = false
	# The Chronicle and Lenses are placeholders that later tickets fill: there, disabled, and they say so.
	for id in ["chronicle", "lenses"]:
		assert_true(hud.system_button(id).disabled, "%s is a placeholder" % id)
		assert_true(hud.system_button(id).tooltip_text.contains("later update"), "and says it is coming")
	game.free()


func test_the_turn_report_button_opens_todays_modal_report_through_the_report_host() -> void:
	var game := _hotseat()
	var hud := game.map.table()
	var report := hud.system_button("report")
	assert_eq(report, game.report_button)
	assert_true(report.disabled, "nothing to report before a turn resolves")
	game.end_turn()
	game.handoff.ready_button.pressed.emit()
	game.end_turn()
	game.handoff.ready_button.pressed.emit()
	game.close_turn_report()
	assert_false(report.disabled)
	report.pressed.emit()
	assert_true(game.report_overlay.visible, "the modal report")
	assert_true(game.report_host.is_open(), "and the host knows it is open")
	game.free()


## Every control the top bar had keeps its tooltip and its codex link where it moved to (the plaque's labels are
## test_the_realm_plaque_keeps_every_breakdown_and_codex_link's).
func test_every_moved_control_keeps_its_tooltip_and_codex_link() -> void:
	var game := _game(_all_on())
	game.close_turn_report()
	var map := game.map
	var hud := map.table()
	# Research and Magic: the breakdown first, then what a click does, and the codex entry the chip names.
	var research := game.research_hud.chip
	assert_true(research.tooltip_text.begins_with(TooltipText.from_breakdown(Breakdown.research_progress(map.state, CROWN, game.session.current_orders()))), "the research chip's breakdown")
	assert_true(research.tooltip_text.replace("\n", " ").contains("research panel"), "and what a click does")
	assert_eq(String(research.get_meta(CodexLink.META)), String(PathView.chip(map.state, CROWN, game.session.current_orders()).codex))
	var magic := game.research_hud.magic_chip
	var mc := MagicView.chip(map.state, CROWN, game.session.current_orders())
	assert_true(magic.tooltip_text.begins_with(TooltipText.from_breakdown(mc.breakdown)), "the magic chip's breakdown")
	assert_eq(String(magic.get_meta(CodexLink.META)), String(mc.codex))
	assert_eq(CodexLink.key_at(game.ruler_button), "ruler", "the Ruler button's codex entry")
	assert_true(game.ruler_button.tooltip_text.contains("every number"), game.ruler_button.tooltip_text)
	assert_true(game.report_button.tooltip_text.contains("Turn report"), "the Turn report button's tooltip")
	assert_true(game.codex_button.tooltip_text.contains("Every rule of the game"), "the Codex button's tooltip")
	assert_true(game.end_turn_button.tooltip_text.contains("End turn"), "the seal's tooltip is today's end-turn tooltip")
	assert_true(game.end_turn_button.tooltip_text.contains("never seeing yours"))
	assert_true(map.back_button.tooltip_text.contains("Save the game"), "Menu's tooltip")
	assert_true(map.back_button.tooltip_text.contains("Esc"))
	assert_true(map.find_child("VisionButton", true, false) == null and hud.system_button("vision") == null, "UX-2 retired the Vision map mode: no Vision button in the system row")
	assert_true(hud.orders_button.tooltip_text.replace("\n", " ").contains("cancel button"), "the tray's Orders button explains itself")
	assert_true(hud.hint_label.tooltip_text.replace("\n", " ").contains("F1"), "the tray's line keeps the whole how-to")
	assert_true(game.help_button.tooltip_text.contains("key and mouse"), "the ? names itself")
	game.free()


# --- the ? ---------------------------------------------------------------------------------------------

## The keys the board's own code reacts to, read from its source: every KEY_ constant in `_unhandled_key_input` and in the camera's
## pan keys, as the name a player reads.
func _board_keys() -> Array:
	var src := FileAccess.get_file_as_string("res://world3d/board3d.gd")
	var names := {}
	var re := RegEx.create_from_string("KEY_([A-Z_]+)")
	for m in re.search_all(src):
		names[m.get_string(1)] = true
	return names.keys()


## What a key is called on the screen.
const KEY_WORDS := {"ESCAPE": "Esc", "SPACE": "Space", "C": "C", "HOME": "Home", "F": "F", "L": "L", "EQUAL": "+", "KP_ADD": "+",
	"MINUS": "-", "KP_SUBTRACT": "-", "W": "W", "A": "A", "S": "S", "D": "D", "UP": "arrow", "DOWN": "arrow", "LEFT": "arrow", "RIGHT": "arrow"}


func test_the_help_lists_every_key_and_mouse_binding() -> void:
	var game := _game(VS_COMPUTER)
	game.open_controls_help()
	var text := _texts(game.help_overlay)
	var keys := _board_keys()
	assert_true(keys.size() >= 10, "the scan of the board's keys found them (%s)" % [keys])
	for k in keys:
		assert_true(KEY_WORDS.has(k), "the test knows the key %s the board uses" % k)
		if KEY_WORDS.has(k):
			assert_true(text.contains(String(KEY_WORDS[k])), "the ? lists the board's %s key" % k)
	for binding in ["Drag", "Mouse wheel", "Double-click", "Right-click", "F1", "Esc", "End turn"]:
		assert_true(text.contains(binding), "the ? lists %s" % binding)
	# Today's hint text, in full: the how-to the top bar's hint tooltip had.
	assert_eq(ControlsHelp.QUICK, "Move: select an army, then a neighbor. Recruit: select your capital.")
	for part in ["select one of your armies", "neighboring province", "forecast and the battle odds", "Select your capital to recruit", "cancel button"]:
		assert_true(text.to_lower().contains(part.to_lower()), "the ? has '%s'" % part)
	var tip := game.map.hint_label.tooltip_text.replace("\n", " ")
	for part in ["neighboring province", "forecast and battle odds", "capital to recruit", "F1", "End turn"]:
		assert_true(tip.contains(part), "the tray hint's tooltip keeps '%s'" % part)
	# A lens key registered with the host shows up by itself.
	game.map.lens_host.register("owner", "Owner", KEY_1)
	game.open_controls_help()
	assert_true(_texts(game.help_overlay).contains("Owner lens"), "UX-7's lenses are listed from the LensHost")
	game.free()


func test_the_help_opens_on_the_overlays_and_esc_closes_it() -> void:
	var game := _game()
	game.open_controls_help()
	assert_eq(game.help_overlay.get_parent(), game.overlays)
	assert_eq(game._top_overlay(), game.help_overlay, "it is the topmost overlay")
	assert_eq(game.map.ui_cancel.cancel(), "modal")
	assert_false(game.help_overlay.visible)
	game.free()


# --- the seal ---------------------------------------------------------------------------------------

func test_the_seal_shows_end_turn_and_the_order_count() -> void:
	var game := _game()
	var hud := game.map.table()
	assert_true(hud.seal.visible and hud.seal.is_ancestor_of(game.end_turn_button), "the seal holds End turn")
	assert_eq(game.end_turn_button.text, "End turn\nno orders")
	game.map.select_province(game.map.state.find_faction(CROWN).capital)
	(game.map.details.find_children("Recruit_*", "Button", true, false)[0] as Button).pressed.emit()
	assert_eq(game.end_turn_button.text, "End turn\n1 order")
	assert_eq(hud.orders_button.text, "Orders (1)")
	assert_true(game.end_turn_button.tooltip_text.contains("never seeing yours"), "it runs today's end-turn flow, with today's tooltip")
	game.end_turn_button.pressed.emit()
	assert_eq(game.session.turns_played(), 1, "a press ends the turn, as before")
	game.free()


func test_the_seal_pulses_for_a_new_player_once_an_order_is_queued_until_two_turns_are_ended() -> void:
	_unseen()
	var game := _game()
	var hud := game.map.table()
	assert_false(game.seal_nudging(), "nothing to press yet: no pulse")
	game.map.select_province(game.map.state.find_faction(CROWN).capital)
	(game.map.details.find_children("Recruit_*", "Button", true, false)[0] as Button).pressed.emit()
	assert_true(game.seal_nudging(), "an order is queued and the player is new: the seal pulses")
	assert_true(hud.seal_pulsing())
	game.map.cancel_order(0)
	assert_false(game.seal_nudging(), "no orders again: it rests")
	# The first two turns the person ends teach them; the pulse is remembered in the settings, not per game.
	for turn in 2:
		game.map.select_province(game.map.state.find_faction(CROWN).capital)
		(game.map.details.find_children("Recruit_*", "Button", true, false)[0] as Button).pressed.emit()
		assert_true(game.seal_nudging(), "turn %d: new, with an order" % (turn + 1))
		game.end_turn()
		game.close_turn_report()
	game.map.select_province(game.map.state.find_faction(CROWN).capital)
	(game.map.details.find_children("Recruit_*", "Button", true, false)[0] as Button).pressed.emit()
	assert_false(game.seal_nudging(), "after two turns it no longer pulses")
	game.free()
	var again := _game()
	again.map.select_province(again.map.state.find_faction(CROWN).capital)
	(again.map.details.find_children("Recruit_*", "Button", true, false)[0] as Button).pressed.emit()
	assert_false(again.seal_nudging(), "and a new game of the same player does not bring it back")
	again.free()
	_unseen()


func test_the_seal_does_not_pulse_for_the_computer_or_a_watched_game() -> void:
	_unseen()
	var game := _game({"players": [CROWN, CLANS], "seed": 4242, "ai": {CROWN: "normal", CLANS: "normal"}})
	assert_true(game.is_watching())
	assert_false(game.seal_nudging(), "in watch mode there is nobody to teach")
	assert_eq(game.end_turn_button.text, "Next turn")
	game.free()
	_unseen()


# --- the tray ---------------------------------------------------------------------------------------

func test_the_trays_orders_button_brings_the_card_back() -> void:
	var game := _game()
	var map := game.map
	var hud := map.table()
	var card := map.details_card
	assert_true(card.visible, "the capital is selected: its card is up")
	card.dismiss()
	assert_false(card.visible)
	hud.orders_button.pressed.emit()
	assert_true(card.visible, "the Orders button shows the card again")
	assert_true(_texts(card).contains("Your orders this turn"), "with the orders list")
	map.selected_province_id = ""
	map.selected_army_id = ""
	map.set_state(map.state, CROWN)
	assert_true(card.visible, "an opened card stays while nothing is selected")
	assert_true(_texts(card).contains("No province selected"), "saying so, and listing the orders")
	assert_ne(hud.hint_label.text, "", "the tray's line says what to do now")
	assert_true(hud.tray_slot() != null and hud.tray.is_ancestor_of(hud.tray_slot()), "and its slot is there for the order tokens (UX-4)")
	game.free()


func test_the_notification_stack_has_an_empty_slot_on_the_left_edge() -> void:
	var game := _game()
	var hud := game.map.table()
	var slot := hud.notification_slot()
	assert_eq(slot, hud.notification_stack)
	assert_eq(slot.get_child_count(), 0, "empty: UX-6 fills it")
	assert_eq(slot.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq([slot.offset_left, slot.offset_right], [0.0, TableLayout.STACK_W], "80 px on the left")
	assert_eq(slot.offset_top, TableLayout.TOP_LEFT_H, "under the system row")
	assert_eq(slot.offset_bottom, -TableLayout.BOTTOM_H, "above the tray")
	game.free()


# --- the opponent plaque ----------------------------------------------------------------------------

func test_the_opponent_plaque_shows_the_computer_with_its_banner_tag_and_codex_link() -> void:
	var game := _game()
	var hud := game.map.table()
	assert_true(game.opponent_box.visible and hud.opponent_panel.visible, "a rival to show")
	assert_true(hud.opponent_slot.is_ancestor_of(game.opponent_box), "in the opponent plaque, top right")
	assert_true(hud.right_column.is_ancestor_of(hud.opponent_panel) and hud.right_column.is_ancestor_of(hud.menu_button), "beside Menu")
	assert_eq(hud.menu_button, game.map.back_button)
	assert_eq(hud.menu_button.text, "Menu")
	var banner := game.opponent_box.find_child("RivalBanner", true, false) as Art.BannerCard
	assert_true(banner != null and banner.texture == Art.banner(CLANS), "the rival's banner")
	var name_label := game.opponent_box.find_child("OpponentName", true, false) as Label
	assert_eq(name_label.text, game.map.state.find_faction(CLANS).faction_name)
	var tags := game.opponent_box.find_children("ComputerTag", "Label", true, false)
	assert_eq(tags.size(), 1)
	assert_eq((tags[0] as Label).text, AISeat.tag_text("normal"))
	assert_eq(CodexLink.key_at(hud.opponent_panel), "computer_opponent", "the plaque's own link: its codex entry")
	assert_eq(CodexLink.key_at(name_label), "computer_opponent")
	assert_true(hud.opponent_panel.mouse_filter != Control.MOUSE_FILTER_IGNORE, "a piece")
	assert_eq(game.opponent_box.find_children("LastSeen", "Label", true, false)[0].text, "", "no 'last seen' line without fog")
	game.free()


func test_a_hotseat_rival_is_a_player_and_the_plaque_follows_the_viewer() -> void:
	var game := _hotseat()
	var hud := game.map.table()
	assert_true(hud.opponent_panel.visible, "a hotseat game shows the other seat too")
	var tags := game.opponent_box.find_children("PlayerTag", "Label", true, false)
	assert_eq(tags.size(), 1)
	assert_eq((tags[0] as Label).text, "Player 2", "Player 1 sees Player 2")
	assert_eq((game.opponent_box.find_child("OpponentName", true, false) as Label).text, game.map.state.find_faction(CLANS).faction_name)
	assert_eq(CodexLink.key_at(hud.opponent_panel), "hotseat")
	game.end_turn()
	game.handoff.ready_button.pressed.emit()
	tags = game.opponent_box.find_children("PlayerTag", "Label", true, false)
	assert_eq((tags[0] as Label).text, "Player 1", "and Player 2 sees Player 1")
	assert_eq((game.opponent_box.find_child("OpponentName", true, false) as Label).text, game.map.state.find_faction(CROWN).faction_name)
	game.free()


func test_under_fog_the_plaque_says_when_the_rival_was_last_seen_and_moves_it_to_the_tooltip_when_narrow() -> void:
	var game := _game({"players": [CROWN, CLANS], "seed": 4242, "ai": {CLANS: "normal"}, "fog": true})
	var hud := game.map.table()
	var seen := game.opponent_box.find_children("LastSeen", "Label", true, false)[0] as Label
	var line := GameScreen.last_seen_text(game.map.state, CROWN, CLANS, game.map.fog_memory)
	assert_false(line.is_empty(), "a fog game has the line")
	assert_eq(seen.text, line)
	assert_true(["in sight now", "not seen yet"].has(line) or line.begins_with("last seen turn "), line)
	var name_label := game.opponent_box.find_child("OpponentName", true, false) as Label
	assert_true(name_label.tooltip_text.contains(line), "the tooltip has it too")
	assert_true(seen.visible, "wide: under the name")
	hud.viewport_override = NARROW
	hud.relayout()
	assert_false(seen.visible, "below 1600 logical it moves to the tooltip")
	assert_true(name_label.tooltip_text.contains(line))
	hud.viewport_override = WIDE
	hud.relayout()
	assert_true(seen.visible)
	assert_eq(GameScreen.last_seen_text(game.map.state, CROWN, CLANS, game.map.fog_memory), line, "the helper is a pure function of the view and its memory")
	assert_eq(GameScreen.last_seen_text(GameState.new(1), CROWN, CLANS, {}), "", "and says nothing without fog")
	game.free()


func test_last_seen_reads_the_viewers_view_and_never_the_truth() -> void:
	var src := FileAccess.get_file_as_string("res://ui/game_screen.gd")
	var at := src.find("static func last_seen_text")
	assert_true(at >= 0)
	var body := src.substr(at, src.find("\n\n\n", at) - at)
	for forbidden in ["state_for(FogRules.OBSERVER)", "turn_report()", "session.state()", "truth"]:
		assert_false(body.contains(forbidden), "last_seen_text never touches %s" % forbidden)


# --- the temporary details card ---------------------------------------------------------------------

func test_the_details_card_is_todays_side_panel_docked_bottom_left_and_closable() -> void:
	var game := _game(VS_COMPUTER)
	var map := game.map
	var card := map.details_card
	assert_eq(map.details, card.details, "map.details is the card's content: today's builders fill it")
	assert_true(card.visible, "a selection (the capital) shows the card")
	assert_true(map.table().pieces().has(card) and card.get_parent() == map.table(), "a piece of the Table, which places it")
	var text := _texts(card)
	for part in ["Crownkeep", "Owner:", "Terrain:", "Income:", "Armies here", "Your orders this turn"]:
		assert_true(text.contains(part), "the card has %s, as the side panel had" % part)
	assert_true(card.details.find_child("ProvinceHeader", true, false) != null)
	assert_true(card.details.find_children("Recruit_*", "Button", true, false).size() > 0, "and the recruit buttons")
	# Closable: the close button, and the dismissed card stays closed through every refresh until a click.
	assert_eq(card.close_button.tooltip_text.contains("Esc"), true)
	card.close_button.pressed.emit()
	assert_false(card.visible)
	assert_true(card.dismissed)
	assert_eq(map.selected_province_id, "crownkeep", "the province stays selected (the close-up depends on it)")
	map.set_state(map.state, CROWN)
	assert_false(card.visible, "a new state does not bring it back")
	map.select_province("crownkeep")
	assert_true(card.visible, "a click on the land does")
	assert_false(card.dismissed)
	game.free()


func test_closing_the_card_puts_the_army_back_so_a_click_cannot_order_from_a_card_that_is_not_there() -> void:
	var game := _game(VS_COMPUTER)
	var map := game.map
	map.select_army("kingdom-1")
	assert_eq(map.selected_army_id, "kingdom-1")
	assert_eq(map.selection_host.kind(), "army", "the host has an army")
	map.dismiss_selection_card()
	assert_eq(map.selected_army_id, "", "no army selected")
	assert_eq(map.selected_province_id, "crownkeep")
	map.select_province("westwatch")
	assert_eq(game.session.current_orders().size(), 0, "a click on a neighbour orders nothing")
	assert_eq(map.selected_province_id, "westwatch", "it just selects it")
	game.free()


func test_orders_with_cancel_buttons_and_recruiting_are_on_the_card() -> void:
	var game := _game(VS_COMPUTER)
	var map := game.map
	map.select_army("kingdom-1")
	map.select_province("westwatch")
	map.select_province("crownkeep")
	(map.details.find_children("Recruit_*", "Button", true, false)[0] as Button).pressed.emit()
	var rows := map.details.find_children("Order_*", "", true, false)
	assert_eq(rows.size(), 2, "both orders are listed on the card")
	assert_true(map.details.find_children("CancelButton", "Button", true, false).size() == 2, "each with its cancel button")
	(map.details.find_children("CancelButton", "Button", true, false)[0] as Button).pressed.emit()
	assert_eq(game.session.current_orders().size(), 1, "cancelling works from the card")
	game.free()


# --- the host seams ---------------------------------------------------------------------------------

class SpyPresenter extends RefCounted:
	var log: Array = []

	func show_province(id: String) -> void:
		log.append(["province", id])

	func show_army(id: String, province: String) -> void:
		log.append(["army", id, province])

	func clear_selection() -> void:
		log.append(["clear"])

	func refresh_selection() -> void:
		log.append(["refresh"])


func test_the_selection_host_tells_its_presenter_what_is_selected() -> void:
	var host := SelectionHost.new()
	var spy := SpyPresenter.new()
	host.set_presenter(spy)
	var changes := []
	host.changed.connect(func(kind: String, id: String): changes.append([kind, id]))
	host.show_province("crownkeep")
	host.show_army("kingdom-1", "crownkeep")
	host.refresh()
	host.clear()
	assert_eq(spy.log.slice(spy.log.size() - 4), [["province", "crownkeep"], ["army", "kingdom-1", "crownkeep"], ["refresh"], ["clear"]])
	assert_eq(changes, [["province", "crownkeep"], ["army", "kingdom-1"], ["", ""]], "changed names each new selection, not refreshes")
	assert_eq([host.kind(), host.id()], ["", ""])
	# The map screen drives it: the details card is its presenter until UX-3's cards replace it.
	var game := _game()
	var map := game.map
	assert_eq(map.selection_host.presenter(), map.details_card)
	var spy2 := SpyPresenter.new()
	map.selection_host.set_presenter(spy2)
	map.select_army("kingdom-1")
	map.select_province("westwatch")
	assert_true(spy2.log.any(func(e): return e[0] == "army" and e[1] == "kingdom-1" and e[2] == "crownkeep"), "an army click reaches the new presenter")
	assert_true(spy2.log.any(func(e): return e[0] == "province"), "so does a province click: %s" % [spy2.log])
	map.selected_province_id = ""
	map.selected_army_id = ""
	map.set_state(map.state, CROWN)
	assert_eq(spy2.log.back(), ["clear"], "and a cleared selection")
	game.free()


func test_the_report_host_hears_every_step_of_a_reports_life() -> void:
	var game := _hotseat()
	var host := game.report_host
	assert_eq(host.presenter(), game, "the modal report is the default presenter")
	var log := []
	host.turn_resolved.connect(func(t: int): log.append(["resolved", t]))
	host.report_ready.connect(func(t: int): log.append(["ready", t]))
	host.report_opened.connect(func(t: int): log.append(["opened", t]))
	host.report_closed.connect(func(t: int): log.append(["closed", t]))
	game.end_turn()
	game.handoff.ready_button.pressed.emit()
	game.end_turn()
	assert_true(log.has(["resolved", 1]), "a turn resolved: %s" % [log])
	game.handoff.ready_button.pressed.emit()
	assert_true(log.has(["ready", 1]), "its report is ready for the next player: %s" % [log])
	assert_true(log.has(["opened", 1]) and host.is_open() and game.report_overlay.visible, "the modal opened: %s" % [log])
	game.close_turn_report()
	assert_true(log.has(["closed", 1]) and not host.is_open(), "and closed: %s" % [log])
	assert_eq(host.last_resolved, 1)
	assert_eq(host.last_opened, 1)
	# The Turn report button reopens it, through the host.
	game.report_button.pressed.emit()
	assert_true(host.is_open())
	game.free()


func test_a_presenter_registered_with_the_report_host_takes_over_the_report() -> void:
	var game := _hotseat()
	var chronicle := SpyReport.new()
	game.report_host.set_presenter(chronicle)
	game.end_turn()
	game.handoff.ready_button.pressed.emit()
	game.end_turn()
	game.handoff.ready_button.pressed.emit()
	assert_eq(chronicle.ready, [1], "UX-6's Chronicle hears the report is ready")
	assert_false(game.report_overlay.visible, "and today's modal does not open on its own")
	game.open_turn_report()
	assert_eq(chronicle.opened, 1, "the Turn report button goes to the presenter")
	assert_false(game.report_overlay.visible)
	game.free()


class SpyReport extends RefCounted:
	var ready: Array = []
	var opened := 0

	func on_report_ready(turn: int, _context: Dictionary) -> void:
		ready.append(turn)

	func open_report() -> bool:
		opened += 1
		return true


func test_the_lens_host_has_no_lens_yet_and_feeds_the_board_the_active_one() -> void:
	var game := _game()
	var host := game.map.lens_host
	assert_eq(host.ids(), [], "no lens yet")
	assert_eq(host.active_id(), "", "none active")
	assert_eq(host.id_for_key(KEY_1), "")
	var fed := []
	host.register("owner", "Owner", KEY_1, func(board): fed.append(board))
	host.register("income", "Income", KEY_2)
	assert_eq(host.ids(), ["owner", "income"])
	assert_eq(host.key_of("income"), KEY_2)
	assert_eq(host.id_for_key(KEY_2), "income")
	host.feed_board(game.map)
	assert_eq(fed, [], "nothing is fed while no lens is on")
	var changes := []
	host.active_changed.connect(func(id: String): changes.append(id))
	assert_true(host.toggle("owner"))
	assert_eq(host.active_id(), "owner")
	host.feed_board(game.map)
	assert_eq(fed, [game.map], "the active lens feeds the board")
	assert_true(host.toggle("owner"), "its key again brings the art back")
	assert_eq(host.active_id(), "")
	assert_false(host.activate("nope"))
	assert_eq(changes, ["owner", ""])
	# A key press toggles it on the map screen, unless a modal is open.
	var key := InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	game.map._unhandled_key_input(key)
	assert_eq(host.active_id(), "owner")
	game.free()


# --- hotseat: the HUD rebuilds for the next player -----------------------------------------------------

func test_the_handoff_rebuilds_the_hud_for_the_next_player_and_leaves_nothing_of_the_last() -> void:
	_unseen()
	var game := _hotseat(ALL)
	var map := game.map
	var hud := map.table()
	assert_eq(map.viewing_faction_id, CROWN)
	# Player 1 gives orders, opens a panel, has a hover forecast and the card up.
	map.select_province(map.state.find_faction(CROWN).capital)
	(map.details.find_children("Recruit_*", "Button", true, false)[0] as Button).pressed.emit()
	map.select_army("kingdom-1")
	map.preview_move("westwatch")
	assert_true(game.end_turn_button.text.contains("1 order"))
	assert_true(_texts(map.details).contains("Aurel Crown"))
	var crown_text := _texts(hud)
	game.end_turn()
	assert_true(game.handoff.visible and not map.visible, "the cover is up and the table is hidden behind it")
	game.handoff.ready_button.pressed.emit()
	assert_eq(map.viewing_faction_id, CLANS, "player 2 has the table")
	assert_eq(game.handoff_log.back().faction, CLANS)
	assert_true(game.handoff_log.back().covered, "rebuilt while the cover was still up")
	# Nothing of player 1 is left anywhere on it.
	assert_eq(game.end_turn_button.text, "End turn\nno orders", "an empty seal")
	assert_eq(hud.orders_button.text, "Orders")
	assert_eq(map.selected_army_id, "")
	assert_false(map.hover_panel.visible, "no forecast of player 1's")
	assert_false(_texts(map.details).contains("Aurel Crown"), "the card is player 2's own")
	assert_true(_texts(map.details).contains("Fangridge"), "it shows their capital")
	assert_eq(map.faction_label.text, map.state.find_faction(CLANS).faction_name, "the plaque is theirs")
	assert_eq(map.gold_label.tooltip_text.begins_with(TooltipText.from_breakdown(Breakdown.gold(map.state, CLANS))), true)
	assert_eq(map.ruler_line.text.contains(RulerRules.current_name(map.state, CLANS)), true, "their ruler")
	assert_false(map.ruler_line.text.contains(RulerRules.current_name(map.state, CROWN)))
	var tags := game.opponent_box.find_children("PlayerTag", "Label", true, false)
	assert_eq((tags[0] as Label).text, "Player 1", "their rival is Player 1")
	assert_false(hud.seal_pulsing(), "no nudge: they have queued nothing")
	var clans_text := _texts(hud)
	assert_false(clans_text.contains(RulerRules.current_name(map.state, CROWN)), "no trace of player 1's ruler")
	assert_ne(clans_text, crown_text)
	# Their research chip is their own (paths on): it follows the seat.
	assert_true(game.research_hud.chip.visible)
	assert_true(game.research_hud.chip.text.contains(PathView.chip(map.state, CLANS, []).text.split("\n")[0]), game.research_hud.chip.text)
	game.free()
	_unseen()


func test_the_handoff_closes_every_panel_of_the_last_player() -> void:
	var game := _hotseat(ALL)
	game.research_hud.open_panel()
	game.open_controls_help()
	game.open_menu()
	game.map.open_ruler_panel()
	game.end_turn()
	game.handoff.ready_button.pressed.emit()
	assert_false(game.research_hud.panel.visible)
	assert_false(game.menu_overlay.visible)
	assert_false(game.help_overlay.visible)
	assert_false(game.map.ruler_panel.visible, "the ruler panel follows the seat: closed")
	game.free()


# --- measuring --------------------------------------------------------------------------------------

## Lays the Table out for `viewport` logical pixels and checks every piece fits it with nothing clipped: the two top-left rows
## (the realm plaque and the system row) and the top-right cluster (the opponent plaque and Menu) stay in their bands and leave
## room between them, the tray and the seal fit the bottom band, and no label is trimmed. (The live layout, with every
## piece's real rect, is tests/table_probe.gd; headless, containers do not lay out, so the minimum sizes stand in for it.)
func _assert_fits(map: MapScreen, where: String, viewports: Array = [WIDE, NARROW]) -> void:
	var hud := map.table()
	for viewport: Vector2 in viewports:
		hud.viewport_override = viewport
		hud.relayout()
		_refresh_theme(hud)
		var tag := "%s at %dx%d" % [where, viewport.x, viewport.y]
		var left := hud.left_column.get_combined_minimum_size()
		var right := hud.right_column.get_combined_minimum_size()
		assert_true(left.x + right.x + 3.0 * TableLayout.GAP <= viewport.x, "%s: the plaque with its system row (%d px) and the opponent plaque with Menu (%d px) fit side by side" % [tag, left.x, right.x])
		assert_true(left.y + TableHud.PLAQUE_MARGIN.y <= TableLayout.TOP_LEFT_H + 0.5, "%s: the realm plaque and the system row fit the 112 px band (%d px)" % [tag, left.y + TableHud.PLAQUE_MARGIN.y])
		assert_true(right.y + TableHud.PLAQUE_MARGIN.y <= TableLayout.TOP_RIGHT_H + 0.5 or not hud.opponent_panel.visible,
			"%s: the opponent plaque and Menu fit the 72 px band (%d px)" % [tag, right.y + TableHud.PLAQUE_MARGIN.y])
		var bottom := hud.bottom_row.get_combined_minimum_size()
		assert_true(bottom.x <= viewport.x - 2.0 * TableHud.PLAQUE_MARGIN.x, "%s: the tray and the seal fit the width (%d px)" % [tag, bottom.x])
		assert_true(bottom.y + TableHud.PLAQUE_MARGIN.x <= TableLayout.BOTTOM_H + 0.5, "%s: and the 120 px band (%d px)" % [tag, bottom.y + TableHud.PLAQUE_MARGIN.x])
		# Labels that don't wrap must get their whole text: their minimum width is the text's width.
		for label: Label in [map.faction_label, map.gold_label, map.turn_label]:
			if label.visible:
				var font: Font = label.get_theme_font("font")
				var text_width: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
				assert_true(label.get_minimum_size().x >= text_width - 0.5, "%s: '%s' asks for its whole text" % [tag, label.text])
				assert_eq(label.text_overrun_behavior, TextServer.OVERRUN_NO_TRIMMING, "%s: '%s' is never trimmed" % [tag, label.text])
	hud.viewport_override = Vector2.ZERO
	hud.relayout()


func _refresh_theme(n: Node) -> void:
	if n is Control:
		n.notification(Control.NOTIFICATION_THEME_CHANGED)
	for c in n.get_children():
		_refresh_theme(c)
