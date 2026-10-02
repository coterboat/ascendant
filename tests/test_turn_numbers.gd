extends "res://tests/test_case.gd"
## Player-facing turn numbers are 1-based everywhere, as GameSession.turn_number() is: the move
## forecast's arrival turn and the turn breakdown agree with the session's turn.


func _session() -> GameSession:
	var session := GameSession.new(GameState.new(7), ["kingdom", "beasts"], 7)
	assert_eq(session.setup_errors(), [], "session starts")
	return session


## A valid move for `fid`'s first army: to the first neighbor of its province.
func _first_move(s: GameState, fid: String) -> MoveOrder:
	for a in s.armies:
		if a.owner == fid:
			return MoveOrder.new(a.id, s.find_province(a.location).neighbors[0])
	return null


func _play_empty_turn(session: GameSession) -> void:
	assert_eq(session.end_turn(), "")
	assert_eq(session.acknowledge_handoff(), "")
	assert_eq(session.end_turn(), "")
	assert_eq(session.acknowledge_handoff(), "", "back to player 1 for the next turn")


func test_move_forecast_arrives_the_turn_after_the_one_being_ordered() -> void:
	var session := _session()
	assert_eq(session.turn_number(), 1, "a fresh game is on turn 1")
	var s := session.state()
	var f := Forecast.move(s, "kingdom", _first_move(s, "kingdom"))
	assert_true(f.ok, f.text)
	assert_eq(f.arrival_turn, session.turn_number() + 1, "ordered on turn 1, there at the start of turn 2")
	assert_true(f.text.contains("is there at the start of turn 2."), f.text)
	# Still one ahead of the session's turn after a turn has resolved.
	_play_empty_turn(session)
	assert_eq(session.turn_number(), 2)
	var s2 := session.state()
	var f2 := Forecast.move(s2, "kingdom", _first_move(s2, "kingdom"))
	assert_eq(f2.arrival_turn, session.turn_number() + 1)
	assert_true(f2.text.contains("is there at the start of turn 3."), f2.text)


func test_turn_breakdown_shows_the_sessions_turn() -> void:
	var session := _session()
	var t := Breakdown.turn(session.state())
	assert_eq(t.total, session.turn_number(), "the top bar's turn breakdown matches the session")
	assert_eq(t.title, "Turn 1")
	assert_eq(Breakdown.sum_of_lines(t), t.total, "the lines add up to the turn shown")
	_play_empty_turn(session)
	var t2 := Breakdown.turn(session.state())
	assert_eq(t2.total, session.turn_number())
	assert_eq(t2.title, "Turn 2")
	assert_eq(Breakdown.sum_of_lines(t2), t2.total)
