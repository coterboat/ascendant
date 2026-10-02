extends "res://tests/test_case.gd"
## Computer seats (#35) on the rules side, headless: GameSession's computer seats (validation, record,
## no handoff with one human) and AISeat, which plays a computer seat through the session API. Covers
## the issue's acceptance: a long human-vs-computer session with zero rejected computer orders, the
## computer's orders identical whatever the human queued, and the same seed giving the same game.

const Simulator := preload("res://tools/autoplay/simulator.gd")
const SEED := 4242
const RAW_IDS := ["kingdom", "beasts", "crownkeep", "fangridge", "westwatch", "ebonpeak", "stonegate",
	"blackwood", "highcrag", "ironspike", "rivermarch", "bloodfen", "thornvale", "wildmoor", "greenglade",
	"deepwood", "knight_captain", "warchief", "war_bear", "spearmen", "tuskers", "codex:", "_"]


func _session(players: Array, ai: Dictionary, game_seed: int = SEED) -> GameSession:
	return GameSession.new(GameState.new(game_seed), players, game_seed, AutoBattleResolver.new(), ai)


## The scripted human: on turn t it gives orders[t] (MoveOrder / RecruitOrder), skipping any the rules
## refuse (an army that died, gold that ran out), so every run sees exactly the same human.
func _human_orders(session: GameSession, orders: Array) -> void:
	for o in orders:
		session.queue_order(o)


## The human's orders for turn `turn` (1-based) as the Aurel Crown: march the first army up the northern
## road and recruit Spearmen every turn.
func _crown_script(turn: int) -> Array:
	var road := ["westwatch", "stonegate", "blackwood", "ebonpeak", "fangridge"]
	var out: Array = [RecruitOrder.new("spearmen"), RecruitOrder.new("spearmen")]
	if turn <= road.size():
		out.append(MoveOrder.new("kingdom-1", road[turn - 1]))
	return out


## Plays human seat + computer seat for up to `turns` turns. Returns the AISeat.
func _play(session: GameSession, turns: int) -> AISeat:
	var computer := AISeat.new(session, SEED)
	computer.play(session)  # a computer in seat 1 plays first
	for t in turns:
		if session.is_over():
			break
		assert_ne(session.phase(), GameSession.Phase.HANDOFF, "no handoff with one human (turn %d)" % session.turn_number())
		assert_false(session.is_computer_turn(), "the human is up")
		_human_orders(session, _crown_script(session.turn_number()) if session.current_player() == "kingdom" else [])
		assert_eq(session.end_turn(), "")
		computer.play(session)
	return computer


# --- setup ----------------------------------------------------------------------------------------

func test_levels_match_the_ai_player() -> void:
	assert_eq(GameSession.COMPUTER_LEVELS, AIPlayer.DIFFICULTIES, "the session accepts exactly the brain's levels")
	assert_eq(NewGameScreen.LEVELS, AIPlayer.DIFFICULTIES, "and the new game screen offers them")
	assert_eq(AISeat.tag_text("normal"), "Computer (Normal)")
	assert_eq(AISeat.tag_text("easy"), "Computer (Easy)")


func test_computer_seats_are_checked_in_plain_language() -> void:
	var s := _session(["kingdom", "beasts"], {"elves": "normal"})
	assert_eq(s.phase(), GameSession.Phase.INVALID, "a computer seat for a faction nobody plays")
	assert_true(" ".join(s.setup_errors()).contains("no seat in this game"), str(s.setup_errors()))
	s = _session(["kingdom", "beasts"], {"beasts": "hard"})
	assert_eq(s.phase(), GameSession.Phase.INVALID, "an unknown level")
	assert_true(" ".join(s.setup_errors()).contains("Player 2"), str(s.setup_errors()))
	assert_true(" ".join(s.setup_errors()).contains("Easy and Normal"), str(s.setup_errors()))
	for e in s.setup_errors():
		for id in RAW_IDS:
			assert_false(String(e).contains(id), "no raw id '%s' in: %s" % [id, e])

	s = _session(["kingdom", "beasts"], {"beasts": "easy"})
	assert_eq(s.setup_errors(), [])
	assert_eq(s.computer_seats(), {"beasts": "easy"})
	assert_true(s.is_computer("beasts"))
	assert_false(s.is_computer("kingdom"))
	assert_eq(s.computer_level("beasts"), "easy")
	assert_eq(s.computer_level("kingdom"), "")
	assert_eq(s.human_seats(), 1)
	assert_eq(s.record().get("ai"), {"beasts": "easy"}, "the record says who the computer played")
	assert_eq(JSON.parse_string(JSON.stringify(s.record())).get("ai"), {"beasts": "easy"}, "JSON-safe")

	var hotseat := _session(["kingdom", "beasts"], {})
	assert_eq(hotseat.computer_seats(), {})
	assert_eq(hotseat.human_seats(), 2)
	assert_false(hotseat.record().has("ai"), "a hotseat record is unchanged")


func test_one_human_never_waits_behind_a_handoff_and_two_humans_still_do() -> void:
	for players in [["kingdom", "beasts"], ["beasts", "kingdom"]]:
		var session := _session(players, {"beasts": "normal"})
		var computer := _play(session, 4)
		assert_eq(session.turns_played(), 4, "%s: four turns" % [players])
		assert_eq(computer.rejections(), [])
	# Two humans: exactly as before.
	var hotseat := _session(["kingdom", "beasts"], {})
	assert_eq(hotseat.end_turn(), "")
	assert_eq(hotseat.phase(), GameSession.Phase.HANDOFF, "two humans hand off")
	assert_eq(hotseat.acknowledge_handoff(), "")
	assert_eq(hotseat.end_turn(), "")
	assert_eq(hotseat.phase(), GameSession.Phase.HANDOFF, "and hand back after the resolution")
	var idle := AISeat.new(hotseat, SEED)
	assert_eq(idle.factions(), [], "no computer seats")
	assert_eq(idle.play(hotseat), {"played": [], "resolved": false}, "so it never plays")


func test_take_turn_refuses_a_human_seat() -> void:
	var session := _session(["kingdom", "beasts"], {"beasts": "normal"})
	var computer := AISeat.new(session, SEED)
	assert_false(computer.take_turn(session).is_empty(), "seat 1 is the human's")
	assert_eq(session.current_orders(), [], "and nothing was queued for them")
	assert_eq(computer.play(session), {"played": [], "resolved": false})


# --- simultaneity ---------------------------------------------------------------------------------

## The computer plays seat 2, after the human queued their orders: its orders are the same whatever the
## human queued, because it only ever reads session.state(), the start-of-turn state.
func test_the_computers_orders_do_not_depend_on_what_the_human_queued() -> void:
	var human_options := [
		[],
		[RecruitOrder.new("knights"), MoveOrder.new("kingdom-1", "westwatch")],
		[RecruitOrder.new("spearmen"), RecruitOrder.new("spearmen"), RecruitOrder.new("crossbowmen"), MoveOrder.new("kingdom-1", "rivermarch")],
	]
	var seen_orders := []
	var seen_notes := []
	var seen_states := []
	for orders in human_options:
		var session := _session(["kingdom", "beasts"], {"beasts": "normal"})
		var computer := AISeat.new(session, SEED)
		for o in orders:
			assert_eq(session.queue_order(o), "", "the human's order is accepted")
		assert_eq(session.end_turn(), "")
		assert_true(session.is_computer_turn(), "now the computer's turn, with no handoff")
		seen_states.append(var_to_str(session.state().to_dict()))
		var result := computer.play(session)
		assert_eq(result, {"played": ["beasts"], "resolved": true})
		var recorded: Dictionary = session.history()[0].orders
		assert_eq(recorded.get("kingdom", []).size(), orders.size(), "the human's orders resolved with the computer's")
		seen_orders.append(recorded.get("beasts", []))
		seen_notes.append(computer.report_notes(session)[0].notes)
	for i in range(1, human_options.size()):
		assert_eq(seen_states[i], seen_states[0], "the state the computer reads holds no pending human orders (case %d)" % i)
		assert_eq(seen_orders[i], seen_orders[0], "identical computer orders whatever the human queued (case %d)" % i)
		assert_eq(seen_notes[i], seen_notes[0], "and identical reasons (case %d)" % i)
	assert_false(seen_orders[0].is_empty(), "the computer gave orders")


# --- determinism ----------------------------------------------------------------------------------

func test_same_seed_and_human_orders_give_the_same_game_and_replay_matches() -> void:
	for players in [["kingdom", "beasts"], ["beasts", "kingdom"]]:
		var a := _session(players, {"beasts": "normal"})
		var b := _session(players, {"beasts": "normal"})
		var ca := _play(a, 6)
		var cb := _play(b, 6)
		assert_eq(var_to_str(a.state().to_dict()), var_to_str(b.state().to_dict()), "%s: same final state" % [players])
		assert_eq(a.history(), b.history(), "same orders and turn seeds")
		assert_eq(ca.rng_state(), cb.rng_state(), "the computer's RNG ended in the same state")
		var replayed := GameSession.replay(JSON.parse_string(JSON.stringify(a.record())), AutoBattleResolver.new())
		assert_eq(replayed.errors, [])
		assert_eq(var_to_str(replayed.state.to_dict()), var_to_str(a.state().to_dict()),
			"replaying the record, without running the computer, gives the same state")
	# A different seed plays differently.
	var c := _session(["kingdom", "beasts"], {"beasts": "normal"}, 77)
	var computer := AISeat.new(c, 77)
	assert_eq(computer.rng_state().beasts.seed, Serial.int64_to_str(AISeat.seat_seed(77, 1)))


## One SeededRNG per computer seat for the whole game, seeded like the autoplay's policies: the seat's
## orders over several turns are exactly what one AIPlayer with one RNG produces turn after turn.
func test_each_computer_seat_keeps_one_rng_seeded_from_the_game_seed_and_seat() -> void:
	for seat in 3:
		assert_eq(AISeat.seat_seed(SEED, seat), Simulator.policy_seed(SEED, seat), "the autoplay's seat formula")
	assert_eq(AISeat.seat_seed(SEED, 1), SEED * 7919 + 2 * 104729)
	var session := _session(["kingdom", "beasts"], {"beasts": "easy"})
	var computer := _play(session, 4)
	var brain := AIPlayer.new()
	var rng := SeededRNG.new(AISeat.seat_seed(SEED, 1))
	var record := session.record()
	var state := GameState.from_dict(record.start_state)
	for entry in record.history:
		var expected := []
		for o in brain.plan_orders(state, "beasts", rng, "easy"):
			expected.append(o.to_dict())
		assert_eq(entry.orders.get("beasts", []), expected, "turn %d: one RNG carried through the game" % entry.turn)
		var orders := OrderBook.orders_from_dict(entry.orders)
		state = TurnResolver.resolve(state, orders, Serial.to_int(entry.seed), AutoBattleResolver.new()).new_state
	assert_eq(computer.rng_state().beasts, rng.to_dict(), "and its RNG is where that one RNG ended")


# --- a long game ----------------------------------------------------------------------------------

## The issue's acceptance: a scripted human against the computer for 30 turns (or until the game ends)
## with zero rejected computer orders, at both levels.
func test_thirty_turns_against_a_scripted_human_with_no_rejected_computer_orders() -> void:
	for level in AIPlayer.DIFFICULTIES:
		var session := _session(["kingdom", "beasts"], {"beasts": level})
		var computer := _play(session, 30)
		assert_true(session.turns_played() >= 5, "%s: the game ran (%d turns)" % [level, session.turns_played()])
		assert_true(session.is_over() or session.turns_played() == 30, "%s: 30 turns or a finished game" % level)
		assert_eq(computer.rejections(), [], "%s: the session refused none of the computer's orders" % level)
		for entry in session.history():
			assert_false(entry.orders.get("beasts", []).is_empty(), "%s: the computer gave orders on turn %d" % [level, entry.turn])


# --- notes ----------------------------------------------------------------------------------------

## A computer in seat 1 has already planned the next turn when the human reads the report: the report's
## notes are the resolved turn's, never the plan for the turn being ordered.
func test_report_notes_are_only_ever_for_the_resolved_turn() -> void:
	var session := _session(["kingdom", "beasts"], {"kingdom": "normal"})
	var computer := AISeat.new(session, SEED)
	var start := session.state()
	assert_eq(computer.play(session), {"played": ["kingdom"], "resolved": false}, "seat 1 plays at once")
	assert_eq(session.current_player(), "beasts")
	assert_eq(computer.report_notes(session), [], "nothing resolved yet, so no notes")
	var expected := AIPlayer.new()
	expected.plan_orders(start, "kingdom", SeededRNG.new(AISeat.seat_seed(SEED, 0)), "normal")
	assert_eq(session.end_turn(), "")
	assert_eq(computer.play(session), {"played": ["kingdom"], "resolved": false}, "turn 2's plan is made at once")
	var notes := computer.report_notes(session)
	assert_eq(notes.size(), 1)
	assert_eq(notes[0].notes, expected.last_plan_notes(), "the report shows the turn 1 notes, not turn 2's plan")
	assert_eq(notes[0].faction_name, "Aurel Crown")
	assert_eq(notes[0].level, "normal")
	assert_eq(notes[0].seat, 0)
	assert_false(notes[0].notes.is_empty())
	for line in notes[0].notes:
		for id in RAW_IDS:
			assert_false(String(line).contains(id), "no raw id '%s' in note: %s" % [id, line])
	for text in [AISeat.tag_text("normal"), AISeat.tag_help("Aurel Crown", "normal"), AISeat.tag_help("Aurel Crown", "easy")]:
		for id in RAW_IDS:
			assert_false(text.contains(id), "no raw id '%s' in: %s" % [id, text])
