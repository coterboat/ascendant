extends "res://tests/test_case.gd"
## MVP-1 (#141) acceptance, the first-game guide (ui/first_game_guide.gd): headless, through the real GameScreen.
## - the three steps tick from real orders (the map's own queue_move / queue_recruit, then End turn);
## - the card shows once, and Settings' "Show the first-game guide again" brings it back;
## - it never shows for a seat the computer plays, and a watch game has none;
## - hotseat shows a card per seat, behind the handoff cover, from that seat's own orders only;
## - one line per system that is on (rulers, paths, forts, fog, magic, independents), each linked to its codex entry;
## - the link to the new "How to play" codex entry works, and the entry says what the ticket asked;
## - nothing in the card reads a truth accessor (M5-2's static scan, tests/test_fog_ui.gd, run on this file too), and
##   in a hotseat fog game the second seat's card is the same whatever the first seat did.
## Settings go to the runner's temporary file: each test starts with the hint unseen and leaves it unseen.

const FogUi := preload("res://tests/test_fog_ui.gd")
const GAME_SCENE := "res://ui/game_screen.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"
const VS_COMPUTER := {"players": [CROWN, CLANS], "seed": 4242, "ai": {CLANS: "normal"}}
const HOTSEAT := {"players": [CROWN, CLANS], "seed": 4242}


# --- fixtures -------------------------------------------------------------------------------------

func _unseen() -> void:
	assert_eq(GameSettings.reset_hint(GameSettings.HINT_FIRST_GAME), "")
	assert_false(GameSettings.hint_seen(GameSettings.HINT_FIRST_GAME), "the guide has not been seen")


func _game(config: Dictionary) -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.start_game(config)
	return game


## Presses Ready on the handoff cover, when there is one.
func _ready_up(game: GameScreen) -> void:
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()


## A legal move for the faction giving orders: its first army to a neighbor of where it stands. Through the map's own queue.
func _move(game: GameScreen) -> String:
	var s := game.session.state()
	var fid := game.session.current_player()
	for a in s.armies:
		if a.owner == fid:
			var to: String = s.find_province(a.location).neighbors[0]
			return game.map.queue_move(a.id, to)
	return "no army"


## A recruit for the faction giving orders: the first unit type it can pay for. Through the map's own queue.
func _recruit(game: GameScreen) -> String:
	var why := "nothing to recruit"
	for ut in game.map.orders.recruitable_types():
		why = game.map.queue_recruit(ut.id)
		if why.is_empty():
			return ""
	return why


## The text a person reads on the card, joined: labels, ticks, buttons and the system lines.
func _card_text(guide: FirstGameGuide) -> String:
	var out := PackedStringArray()
	_collect(guide, out)
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


# --- the codex entry --------------------------------------------------------------------------------

func test_how_to_play_is_the_codex_entry_after_the_first() -> void:
	var keys := RulesCodex.ENTRIES.keys()
	assert_eq(keys[1], "how_to_play", "directly after the first entry")
	var e := RulesCodex.entry("how_to_play")
	assert_eq(e.title, "How to play")
	var text := String(e.text).to_lower()
	for word in ["read", "plan", "commit", "resolve", "watch"]:
		assert_true(text.contains(word), "the turn loop names %s" % word)
	assert_true(text.contains("same time") and text.contains("together"), "simultaneous orders")
	assert_true(text.contains("hover") and text.contains("right-click"), "where every number explains itself")
	assert_true(text.contains("how a turn resolves"), "and the entry on the resolution order, which the codex links")
	assert_false(String(e.text).contains("_") or String(e.text).contains("["), "plain text: no raw ids, no links")


func test_every_link_the_guide_makes_is_a_codex_entry() -> void:
	assert_true(RulesCodex.ENTRIES.has(FirstGameGuide.HOW_TO_PLAY))
	for step in FirstGameGuide.STEPS:
		assert_true(RulesCodex.ENTRIES.has(String(step.entry)), "step %s links %s" % [step.id, step.entry])
		assert_false(String(step.title).is_empty() or String(step.tip).is_empty(), "step %s says what to do" % step.id)
	for s in FirstGameGuide.SYSTEMS:
		assert_false(String(s.name).is_empty() or String(s.rest).is_empty() or String(s.tip).is_empty(), "system %s has its line and its tooltip" % s.id)
		assert_true(String(s.name).length() + String(s.rest).length() <= 48, "system %s is one short line (%d characters)" % [s.id, String(s.name).length() + String(s.rest).length()])
	for step in FirstGameGuide.STEPS:
		assert_true(String(step.title).length() <= 42, "step %s is one short line (%d characters)" % [step.id, String(step.title).length()])
	assert_eq(FirstGameGuide.STEPS.map(func(s): return s.id), ["move", "recruit", "end_turn"], "three steps, in the ticket's order")
	for s in FirstGameGuide.SYSTEMS:
		assert_true(RulesCodex.ENTRIES.has(String(s.entry)), "%s links %s" % [s.id, s.entry])


# --- the steps tick from real orders ----------------------------------------------------------------

func test_the_steps_tick_from_real_orders() -> void:
	_unseen()
	var game := _game(VS_COMPUTER)
	var guide := game.first_game_guide
	assert_true(guide.visible, "the card is up on turn 1 of a first game")
	assert_eq(guide.showing(), CROWN)
	assert_eq(guide.steps(), {"move": false, "recruit": false, "end_turn": false}, "nothing done yet")
	assert_eq(guide.progress_label.text, "0 of 3")
	assert_eq(_move(game), "")
	assert_eq(guide.steps(), {"move": true, "recruit": false, "end_turn": false}, "a queued move ticks the first step")
	assert_eq(_recruit(game), "")
	assert_eq(guide.steps(), {"move": true, "recruit": true, "end_turn": false}, "a queued recruit ticks the second")
	assert_eq(guide.progress_label.text, "2 of 3")
	# The ticks follow the orders, not a memory of having clicked: cancel the move and it unticks.
	var at := game.session.current_orders().find_custom(func(o): return o is MoveOrder)
	assert_eq(game.session.cancel_order(at), "")
	game.map.orders_changed.emit()
	assert_eq(guide.steps(), {"move": false, "recruit": true, "end_turn": false}, "a cancelled move unticks")
	assert_eq(_move(game), "")
	assert_eq(game.end_turn(), "")
	assert_eq(guide.steps(), {"move": true, "recruit": true, "end_turn": true}, "End turn ticks the third")
	assert_true(guide.lingering() and guide.closing_label.visible, "the card stays a moment over the playback, all three ticked")
	assert_eq(guide.showing(), "", "and is no longer asking for anything")
	guide.end_linger()
	assert_false(guide.visible, "then it goes")
	game.free()


func test_a_step_is_ticked_by_its_own_kind_of_order_only() -> void:
	var move := MoveOrder.new("a", "b")
	var recruit := RecruitOrder.new("spearmen")
	assert_eq(FirstGameGuide.step_states([], false), {"move": false, "recruit": false, "end_turn": false})
	assert_eq(FirstGameGuide.step_states([move], false), {"move": true, "recruit": false, "end_turn": false})
	assert_eq(FirstGameGuide.step_states([recruit], false), {"move": false, "recruit": true, "end_turn": false})
	assert_eq(FirstGameGuide.step_states([recruit, move], true), {"move": true, "recruit": true, "end_turn": true})
	assert_eq(FirstGameGuide.step_states([ResearchOrder.new("x")], false), {"move": false, "recruit": false, "end_turn": false}, "other orders tick nothing")


func test_each_step_explains_itself_and_links_its_entry() -> void:
	_unseen()
	var game := _game(VS_COMPUTER)
	var guide := game.first_game_guide
	for step in FirstGameGuide.STEPS:
		var check: CheckBox = guide.step_checks[step.id]
		assert_eq(check.text, step.title)
		assert_true(check.tooltip_text.contains(String(step.tip).substr(0, 24)), "%s has its tooltip" % step.id)
		assert_eq(CodexLink.key_at(check), step.entry, "%s: right-click or F1 opens %s" % [step.id, step.entry])
	# UX-1: the steps point at the Table (the card at the bottom left, the seal at the bottom right), not at the old bars.
	assert_true(FirstGameGuide.STEPS[1].title.contains("card") and FirstGameGuide.STEPS[2].title.contains("seal"), "the steps name the card and the seal")
	for step in FirstGameGuide.STEPS:
		assert_false(String(step.title).contains("side panel") or String(step.title).contains("top right"), "%s names a place that is gone" % step.id)
	game.free()


# --- shown once, brought back by the setting --------------------------------------------------------

func test_the_card_shows_once_and_the_setting_brings_it_back() -> void:
	_unseen()
	var first := _game(VS_COMPUTER)
	assert_true(first.first_game_guide.visible, "the first game shows it")
	assert_false(GameSettings.hint_seen(GameSettings.HINT_FIRST_GAME), "showing it is not enough: the person has not finished turn 1")
	assert_eq(_move(first), "")
	assert_eq(first.end_turn(), "")
	assert_true(GameSettings.hint_seen(GameSettings.HINT_FIRST_GAME), "ending the first turn remembers it")
	first.free()
	var second := _game(VS_COMPUTER)
	assert_false(second.first_game_guide.visible, "the second game does not show it")
	assert_eq(second.first_game_guide.showing(), "")
	second.free()
	# Settings' button takes it back.
	var panel := SettingsPanel.new()
	panel.open(GameSettings.new(GameSettings.default_path))
	assert_eq(panel.guide_button.text, "Show the first-game guide again")
	assert_false(panel.guide_button.tooltip_text.is_empty(), "the button explains itself")
	panel.guide_button.pressed.emit()
	assert_false(GameSettings.hint_seen(GameSettings.HINT_FIRST_GAME), "the setting is back")
	assert_true(panel.guide_note.visible and panel.guide_note.text.contains("next game"), "and says when")
	panel.free()
	var third := _game(VS_COMPUTER)
	assert_true(third.first_game_guide.visible, "the next game shows it again")
	third.free()
	_unseen()


func test_hide_closes_the_card_and_remembers_it() -> void:
	_unseen()
	var game := _game(VS_COMPUTER)
	assert_true(game.first_game_guide.visible)
	game.first_game_guide.hide_button.pressed.emit()
	assert_false(game.first_game_guide.visible, "Hide closes the card")
	game.map.orders_changed.emit()
	assert_false(game.first_game_guide.visible, "and it stays closed while the orders change")
	assert_true(GameSettings.hint_seen(GameSettings.HINT_FIRST_GAME), "a person who hid it has seen it")
	game.free()
	_unseen()


func test_the_card_is_for_turn_1_only() -> void:
	_unseen()
	var game := _game(VS_COMPUTER)
	assert_eq(game.end_turn(), "")
	game.first_game_guide.end_linger()
	assert_eq(game.session.turn_number(), 2)
	assert_false(game.first_game_guide.visible, "turn 2 has no card")
	game.map.orders_changed.emit()
	assert_false(game.first_game_guide.visible, "however the orders change")
	assert_eq(game.first_game_guide.showing(), "")
	game.free()
	_unseen()


func test_the_card_never_blocks_the_map() -> void:
	_unseen()
	var game := _game(VS_COMPUTER)
	var guide := game.first_game_guide
	assert_true(guide.get_parent() == game and guide.get_index() > game.map.get_index(), "a small card over the map, under every overlay layer")
	assert_true(guide.get_parent() != game.overlays, "not a modal")
	assert_eq(guide.mouse_filter, Control.MOUSE_FILTER_STOP, "only the card itself takes clicks")
	assert_true(guide.custom_minimum_size.x <= 400.0, "and it is small")
	assert_eq([guide.anchor_left, guide.anchor_top], [0.0, 0.0], "in the top-left corner: clear of the hover forecast along the bottom and of the capital")
	# UX-1: the Table hangs it under the realm plaque, inside the board's safe area (the hang point moved with the top bar).
	var hud := game.map.table()
	hud.relayout()
	assert_true(hud.placed().has("guide"), "the Table places the card")
	assert_true(TableLayout.safe_area(hud.viewport_size()).encloses(hud.placed()["guide"]), "inside the safe area, under the realm plaque and right of the notification stack")
	assert_true((hud.placed()["guide"] as Rect2).end.x <= hud.framing_area().position.x, "and left of the area the map is framed in: it never covers the map")
	assert_eq(guide.offset_top, (hud.placed()["guide"] as Rect2).position.y, "its offsets are the Table's")
	game.free()
	_unseen()


# --- who gets a card --------------------------------------------------------------------------------

func test_a_computer_seat_and_a_watch_game_have_no_card() -> void:
	_unseen()
	var seat2 := _game({"players": [CROWN, CLANS], "seed": 4242, "ai": {CROWN: "normal"}})
	assert_true(seat2.first_game_guide.visible, "the person in seat 2 gets theirs once the computer in seat 1 has played")
	assert_eq(seat2.first_game_guide.showing(), CLANS)
	seat2.free()
	var watch := _game({"players": [CROWN, CLANS], "seed": 4242, "ai": {CROWN: "normal", CLANS: "normal"}})
	assert_false(watch.first_game_guide.visible, "a game only the computer plays has none")
	assert_eq(watch.first_game_guide.showing(), "")
	watch.free()
	_unseen()


func test_hotseat_shows_a_card_per_seat_behind_the_cover() -> void:
	_unseen()
	var game := _game(HOTSEAT)
	var guide := game.first_game_guide
	assert_eq(guide.showing(), CROWN, "seat 1 first")
	assert_true(guide.title_label.text.contains("Player 1"), "the card says whose it is")
	assert_eq(_move(game), "")
	assert_eq(_recruit(game), "")
	assert_eq(guide.steps(), {"move": true, "recruit": true, "end_turn": false})
	assert_eq(game.end_turn(), "")
	assert_true(game.handoff.visible, "the cover is up")
	assert_false(guide.visible, "and no card shows behind it: nothing of seat 1's turn is on screen")
	assert_eq(guide.showing(), "")
	assert_false(GameSettings.hint_seen(GameSettings.HINT_FIRST_GAME), "seat 2 has not had their first turn yet")
	_ready_up(game)
	assert_eq(guide.showing(), CLANS, "seat 2 gets theirs when the cover lifts")
	assert_true(guide.title_label.text.contains("Player 2"))
	assert_eq(guide.steps(), {"move": false, "recruit": false, "end_turn": false}, "from seat 2's own orders: seat 1's ticks are not shown to them")
	assert_eq(_move(game), "")
	assert_eq(guide.steps(), {"move": true, "recruit": false, "end_turn": false})
	assert_eq(game.end_turn(), "")
	assert_true(GameSettings.hint_seen(GameSettings.HINT_FIRST_GAME), "remembered once every person has finished")
	_ready_up(game)
	assert_eq(game.session.turn_number(), 2)
	assert_false(guide.visible, "turn 2 has no card, for either seat")
	game.free()
	_unseen()


func test_in_hotseat_hide_is_per_seat() -> void:
	_unseen()
	var game := _game(HOTSEAT)
	var guide := game.first_game_guide
	guide.hide_button.pressed.emit()
	assert_false(guide.visible)
	assert_false(GameSettings.hint_seen(GameSettings.HINT_FIRST_GAME), "seat 2 still has theirs to see")
	assert_eq(game.end_turn(), "")
	_ready_up(game)
	assert_eq(guide.showing(), CLANS, "seat 1 hiding theirs leaves seat 2's")
	game.free()
	_unseen()


# --- the system lines -------------------------------------------------------------------------------

func test_one_line_per_system_that_is_on_each_linked() -> void:
	_unseen()
	var plain := _game(VS_COMPUTER)
	assert_false(plain.first_game_guide.systems_box.visible, "no system is on: no line")
	plain.free()
	var cases := {
		"rulers": {"rulers": true},
		"paths": {"paths": true},
		"sieges": {"sieges": true},
		"fog": {"fog": true},
		"magic": {"magic": true},
		"independents": {"independents": true},
	}
	for id in cases:
		var config := VS_COMPUTER.duplicate()
		config.merge(cases[id])
		var game := _game(config)
		var guide := game.first_game_guide
		var on: Array = []
		for line_id in guide.system_lines:
			if (guide.system_lines[line_id] as Control).visible:
				on.append(line_id)
		# Paths turn rulers on and magic turns paths and rulers on (the new game screen's boxes): the lines follow the game.
		var expect: Array = FirstGameGuide.systems_on(game.map.state).map(func(s): return s.id)
		assert_true(expect.has(id), "%s is on in its game" % id)
		assert_eq(on, expect, "%s: exactly the systems that are on have a line" % id)
		assert_true(guide.systems_box.visible)
		game.free()
	var all := VS_COMPUTER.duplicate()
	all.merge({"rulers": true, "paths": true, "sieges": true, "fog": true, "magic": true, "independents": true})
	var game := _game(all)
	var guide := game.first_game_guide
	var opened := []
	guide.codex_requested.connect(func(key: String): opened.append(key))
	assert_eq(FirstGameGuide.SYSTEMS.map(func(s): return s.id), ["rulers", "paths", "sieges", "fog", "magic", "independents"], "in a fixed order")
	for s in FirstGameGuide.SYSTEMS:
		var line: RichTextLabel = guide.system_lines[s.id]
		assert_true(line.visible, "%s has its line" % s.id)
		assert_true(line.get_parsed_text().begins_with(String(s.name)), "%s: the line starts with its name" % s.id)
		line.meta_clicked.emit(String(s.entry))
		assert_eq(opened.back(), s.entry, "%s: the name opens its codex entry" % s.id)
	game.free()
	_unseen()


func test_the_how_to_play_link_opens_the_entry() -> void:
	_unseen()
	var game := _game(VS_COMPUTER)
	game.first_game_guide.how_button.pressed.emit()
	assert_true(game.codex.visible, "the codex opens over the game")
	assert_eq(game.codex.current_key(), "how_to_play", "at How to play")
	game.free()
	# A right-click on a step opens that step's entry, like any linked number.
	_unseen()
	var again := _game(VS_COMPUTER)
	var check: CheckBox = again.first_game_guide.step_checks["move"]
	check.gui_input.emit(CodexLink.right_click())
	assert_eq(again.codex.current_key(), "move")
	again.free()
	_unseen()


# --- fog: nothing leaks ------------------------------------------------------------------------------

## The card's source holds no truth accessor: M5-2's scan (tests/test_fog_ui.gd) on this one file, with no observer path
## to excuse a hit.
func test_the_guide_reads_no_truth_accessor() -> void:
	var path := "res://ui/first_game_guide.gd"
	var re := RegEx.new()
	re.compile("\\.(%s)\\(\\)|\\bOBSERVER\\b|\\bsession\\._[a-z_]+" % "|".join(FogUi.TRUTH))
	var hits := []
	var lines := FileAccess.get_file_as_string(path).split("\n")
	for i in lines.size():
		var code: String = FogUi._code_part(lines[i])
		if not code.is_empty() and re.search(code) != null:
			hits.append("%d: %s" % [i + 1, lines[i].strip_edges()])
	assert_eq(hits, [], "no truth accessor in the guide")
	assert_true(lines.size() > 100, "the scan read the guide")
	assert_false(FogUi.OBSERVER_PATHS.has(path), "and it is on no observer path")
	# It is also not a way round the scan: it may name only the per-viewer pieces of a session.
	var src := FileAccess.get_file_as_string(path)
	for banned in ["FogRules", "FogView", "state_for(", "turn_report", "battle_events", "history("]:
		assert_false(src.contains(banned), "the guide never touches %s" % banned)


func test_a_hotseat_fog_game_shows_seat_2_the_same_card_whatever_seat_1_did() -> void:
	_unseen()
	var texts := []
	for variant in 2:
		var game := _game({"players": [CROWN, CLANS], "seed": 4242, "fog": true})
		if variant == 0:
			assert_eq(_move(game), "")
			assert_eq(_recruit(game), "")
		assert_eq(game.end_turn(), "")
		assert_true(game.handoff.visible)
		assert_false(game.first_game_guide.visible, "nothing on screen behind the cover")
		_ready_up(game)
		assert_eq(game.first_game_guide.showing(), CLANS)
		texts.append(_card_text(game.first_game_guide))
		game.free()
		_unseen()
	assert_eq(texts[0], texts[1], "seat 2's card does not depend on anything seat 1 ordered")
	assert_true(texts[0].contains("Fog of war"), "a fog game has its line")
	var model := GameState.new()
	for f in model.factions:
		assert_false(texts[0].contains(f.faction_name), "the card names no faction (%s)" % f.faction_name)
	for p in model.provinces:
		assert_false(texts[0].contains(p.name), "the card names no province (%s)" % p.name)
	assert_false(texts[0].contains("gold"), "and no number of the game")


func test_a_fog_game_card_is_the_viewers_own() -> void:
	_unseen()
	var game := _game({"players": [CROWN, CLANS], "seed": 4242, "ai": {CLANS: "normal"}, "fog": true})
	var guide := game.first_game_guide
	assert_true(guide.visible)
	assert_true(guide.system_lines["fog"].visible, "the fog line is there")
	var text := _card_text(guide)
	assert_true(text.contains("Move an army") and text.contains("End your turn"))
	for f in GameState.new().factions:
		assert_false(text.contains(f.faction_name), "no faction is named (%s)" % f.faction_name)
	game.free()
	_unseen()
