extends "res://tests/test_case.gd"
## Victory screen (#8): the winner or draw headline, the summary text, and the numbers from
## GameSession.victory() (turns played, battles, provinces held, captures), every number explained on
## hover, no raw ids, and the "New game" / "Back to title" signals. Games are real GameSessions.

const SCENE := "res://ui/victory_screen.tscn"
const RAW_IDS := ["kingdom", "beasts", "crownkeep", "fangridge", "ebonpeak", "westwatch", "deepwood", "bloodfen",
	"blackwood", "codex:", "_"]


# --- fixtures -------------------------------------------------------------------------------------

func _screen() -> VictoryScreen:
	var screen := load(SCENE).instantiate() as VictoryScreen
	assert_true(screen != null, "scene instantiates as VictoryScreen")
	return screen


## A fresh state with the starting armies replaced by `specs`: [[id, owner, location, [unit ids]], ...].
func _state(specs: Array, owners: Dictionary = {}) -> GameState:
	var s := GameState.new(99)
	s.armies.clear()
	for spec in specs:
		var a := Army.new()
		a.id = spec[0]
		a.owner = spec[1]
		a.location = spec[2]
		var f := s.find_faction(a.owner)
		for type_id in spec[3]:
			var ut := TurnResolver.recruitable_type(f, type_id)
			if ut.is_commander:
				a.commander = Unit.new(ut, f.id)
			else:
				a.units.append(Unit.new(ut, f.id))
		s.armies.append(a)
	for pid in owners:
		s.find_province(pid).owner = owners[pid]
	return s


func _session(start: GameState) -> GameSession:
	var session := GameSession.new(start, ["kingdom", "beasts"], 7, StubBattleResolver.new())
	assert_eq(session.setup_errors(), [], "session starts")
	return session


## One full turn: kingdom (seat 1) orders, handoff, beasts (seat 2) orders.
func _play_turn(session: GameSession, kingdom_orders: Array, beasts_orders: Array) -> void:
	for o in kingdom_orders:
		assert_eq(session.queue_order(o), "")
	assert_eq(session.end_turn(), "")
	assert_eq(session.acknowledge_handoff(), "")
	for o in beasts_orders:
		assert_eq(session.queue_order(o), "")
	assert_eq(session.end_turn(), "")


## The Aurel Crown walks into an undefended Fangridge on turn 1 and wins.
func _won_session() -> GameSession:
	var session := _session(_state([
		["kingdom-1", "kingdom", "ebonpeak", ["knights", "knight_captain"]],
		["beasts-2", "beasts", "deepwood", ["tuskers"]],
	], {"ebonpeak": "kingdom", "deepwood": "beasts"}))
	_play_turn(session, [MoveOrder.new("kingdom-1", "fangridge")], [MoveOrder.new("beasts-2", "bloodfen")])
	assert_true(session.is_over())
	return session


## Both capitals fall on turn 1: a draw.
func _draw_session() -> GameSession:
	var session := _session(_state([
		["kingdom-1", "kingdom", "ebonpeak", ["knights"]],
		["beasts-2", "beasts", "westwatch", ["tuskers"]],
	], {"ebonpeak": "kingdom", "westwatch": "beasts"}))
	_play_turn(session, [MoveOrder.new("kingdom-1", "fangridge")], [MoveOrder.new("beasts-2", "crownkeep")])
	assert_true(session.is_over())
	return session


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
	return "\n".join(out)


func _has_digit(text: String) -> bool:
	for ch in text:
		if ch >= "0" and ch <= "9":
			return true
	return false


func _assert_numbers_explained(screen: VictoryScreen, where: String) -> int:
	var checked := 0
	for c in _visible_controls(screen, []):
		if (c is Label or c is Button) and _has_digit(c.text):
			checked += 1
			assert_false(c.tooltip_text.strip_edges().is_empty(), "%s: '%s' has a tooltip" % [where, c.text])
			assert_ne(c.mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s: '%s' takes the mouse" % [where, c.text])
	return checked


func _assert_no_raw_ids(text: String, where: String) -> void:
	assert_false(text.is_empty(), "%s has text" % where)
	for id in RAW_IDS:
		assert_false(text.contains(id), "%s shows no raw id '%s'" % [where, id])


# --- tests ----------------------------------------------------------------------------------------

func test_winner_headline_summary_and_stats_match_the_dict() -> void:
	var session := _won_session()
	var v := session.victory()
	var screen := _screen()
	assert_false(screen.visible, "hidden until shown")
	assert_true(screen.show_for(session))
	assert_true(screen.visible)
	assert_eq(screen.headline_label.text, "Aurel Crown wins")
	assert_eq(screen.seat_label.text, "Player 1 wins the game.")
	assert_eq(screen.caption_label.text, "Game over on turn %d" % v.turn)
	assert_eq(screen.summary_label.text, v.text, "the plain summary from VictoryCheck")
	assert_eq(screen.turns_label.text, "Turns played: %d" % v.turns_played)
	assert_eq(screen.battles_label.text, "Battles fought: %d" % v.battles)
	assert_eq(screen.victory, v, "keeps the dictionary it shows")

	var rows := screen.province_labels()
	assert_eq(rows.size(), 2, "one row per player")
	assert_eq(rows[0].text, "Aurel Crown: %d provinces" % v.provinces_held.kingdom, "seat 1 first")
	assert_eq(rows[1].text, "Thornmane Clans: %d provinces" % v.provinces_held.beasts)
	# The breakdown lists the provinces and totals the count from the summary.
	for province_name in ["Crownkeep", "Ebonpeak", "Fangridge"]:
		assert_true(rows[0].tooltip_text.contains(province_name), "Aurel Crown's tooltip lists %s" % province_name)
	assert_true(rows[0].tooltip_text.contains("= Provinces held: 3"), rows[0].tooltip_text)
	assert_true(rows[1].tooltip_text.contains("Deepwood") and rows[1].tooltip_text.contains("Bloodfen"), rows[1].tooltip_text)
	assert_false(rows[1].tooltip_text.contains("Fangridge"), "a lost capital is not listed as held")

	var captures := screen.capture_labels()
	assert_eq(captures.size(), v.captures.size())
	assert_eq(captures[0].text, "Aurel Crown captured Fangridge, the Thornmane Clans capital.")
	assert_true(screen.captures_heading.visible)
	screen.free()


func test_draw_headline_and_both_captures() -> void:
	var session := _draw_session()
	var v := session.victory()
	assert_true(v.draw)
	var screen := _screen()
	assert_true(screen.show_for(session))
	assert_eq(screen.headline_label.text, "It's a draw")
	assert_true(screen.seat_label.text.contains("nobody wins"), screen.seat_label.text)
	assert_eq(screen.summary_label.text, v.text)
	assert_true(screen.headline_label.tooltip_text.contains(RulesCodex.text("simultaneous_capture").substr(0, 30)),
		"the draw headline explains simultaneous captures")
	var texts := screen.capture_labels().map(func(l): return l.text)
	assert_eq(texts.size(), 2)
	assert_true(texts.has("Aurel Crown captured Fangridge, the Thornmane Clans capital."), str(texts))
	assert_true(texts.has("Thornmane Clans captured Crownkeep, the Aurel Crown capital."), str(texts))
	_assert_no_raw_ids(_visible_text(screen), "draw screen")
	screen.free()


func test_stats_follow_a_longer_game_with_a_battle() -> void:
	var session := _session(_state([
		["kingdom-1", "kingdom", "blackwood", ["knights"]],
		["beasts-2", "beasts", "ebonpeak", ["fangthrowers"]],
		["beasts-3", "beasts", "deepwood", ["tuskers"]],
	], {"blackwood": "kingdom", "ebonpeak": "beasts", "deepwood": "beasts"}))
	_play_turn(session, [MoveOrder.new("kingdom-1", "ebonpeak")], [])
	assert_eq(session.acknowledge_handoff(), "")
	_play_turn(session, [MoveOrder.new("kingdom-1", "fangridge")], [])
	var v := session.victory()
	var screen := _screen()
	assert_true(screen.show_for(session))
	assert_eq(screen.turns_label.text, "Turns played: 2")
	assert_eq(screen.battles_label.text, "Battles fought: 1")
	assert_eq(v.turns_played, 2)
	assert_eq(v.battles, 1)
	assert_eq(screen.caption_label.text, "Game over on turn 2")
	screen.free()


func test_numbers_have_tooltips_and_there_are_no_raw_ids() -> void:
	var screen := _screen()
	for session in [_won_session(), _draw_session()]:
		assert_true(screen.show_for(session))
		var checked := _assert_numbers_explained(screen, "victory screen")
		assert_true(checked >= 5, "turn, turns, battles and province counts are checked (%d)" % checked)
		_assert_no_raw_ids(_visible_text(screen), "victory screen")
	screen.free()


func test_buttons_emit_their_signals() -> void:
	var screen := _screen()
	screen.show_for(_won_session())
	var heard := {"new": 0, "title": 0}
	screen.new_game_requested.connect(func(): heard["new"] += 1)
	screen.title_requested.connect(func(): heard["title"] += 1)
	assert_eq(screen.new_game_button.text, "New game")
	assert_eq(screen.title_button.text, "Back to title")
	screen.new_game_button.pressed.emit()
	assert_eq(heard, {"new": 1, "title": 0})
	screen.title_button.pressed.emit()
	assert_eq(heard, {"new": 1, "title": 1})
	assert_false(screen.new_game_button.tooltip_text.is_empty())
	assert_false(screen.title_button.tooltip_text.is_empty())
	screen.free()


func test_show_for_a_running_game_returns_false() -> void:
	var screen := _screen()
	var running := GameSession.new(GameState.new(3), ["kingdom", "beasts"], 3)
	assert_false(screen.show_for(running))
	assert_false(screen.visible)
	assert_false(screen.show_for(null))
	screen.free()


func test_show_victory_uses_seat_order_and_works_without_a_state() -> void:
	var session := _won_session()
	var v := session.victory()
	var screen := _screen()
	# Seat order decides the rows and the "Player N" line.
	screen.show_victory(v, session.state(), ["beasts", "kingdom"])
	assert_true(screen.province_labels()[0].text.begins_with("Thornmane Clans"), "seat 1 first")
	assert_eq(screen.seat_label.text, "Player 2 wins the game.")
	# Without a state, names come from the faction and map data, and tooltips explain in plain words.
	screen.show_victory(v)
	assert_eq(screen.headline_label.text, "Aurel Crown wins")
	assert_eq(screen.province_labels().size(), 2)
	assert_eq(screen.province_labels()[0].text, "Aurel Crown: 3 provinces")
	assert_false(screen.province_labels()[0].tooltip_text.is_empty())
	assert_eq(screen.capture_labels()[0].text, "Aurel Crown captured Fangridge, the Thornmane Clans capital.")
	_assert_no_raw_ids(_visible_text(screen), "victory screen without a state")
	screen.free()
