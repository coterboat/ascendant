extends "res://tests/test_case.gd"
## M5-1 (#112) acceptance, "with fog off" (design/M5_MAGIC_FOG.md §1.3, §18): M1, M2 and M4 games are byte-identical
## to `main`. tests/fixtures/m5_base_records.json (recorded on main by M5-0) is replayed turn by turn through a
## GameSession, and every per-viewer door is a no-op there: state_for(viewer) is state(), turn_report_for(viewer) is
## turn_report(), view_before is the true state before the turn, memory and intel are empty, and nothing saves a fog
## key. The AI policy loop of tools/replay_fixture.gd is rerun with each seat reading state_for(its faction) instead of
## state(), and gives main's orders turn by turn.

const FIXTURE := "res://tests/fixtures/m5_base_records.json"
const Fixture := preload("res://tools/replay_fixture.gd")
const Policies := preload("res://tools/autoplay/policies.gd")


func _games() -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_true(data is Dictionary, "the fixture loads")
	return data.get("games", []) if data is Dictionary else []


func test_fixture_records_replay_byte_identically_and_the_doors_are_no_ops() -> void:
	var games := _games()
	assert_eq(games.size(), Fixture.M5_GAMES.size())
	for g in games:
		var rec: Dictionary = g.record
		var start := GameState.from_dict(rec.start_state, [])
		assert_false(start.fog, "%s: no fog" % g.name)
		var seats: Array = rec.players
		var session := GameSession.new(start, seats, Serial.to_int(rec.game_seed), AutoBattleResolver.new())
		for i in rec.history.size():
			var before := session.state()
			var orders := OrderBook.orders_from_dict(rec.history[i].orders, [])
			var given := {}
			var recorded := {}
			for fid in seats:
				given[fid] = orders.get(fid, [])
				recorded[fid] = given[fid].map(func(o): return o.to_dict())
			assert_eq(session._resolve_orders(given, recorded), "", "%s turn %d resolves" % [g.name, i + 1])
			var d := Fixture.digest(session.state(), session.turn_report().events)
			assert_eq(d.state, g.turns[i].state, "%s turn %d: the state is byte-identical to main" % [g.name, i + 1])
			assert_eq(d.events, g.turns[i].events, "%s turn %d: the events are byte-identical to main" % [g.name, i + 1])
			var truth := JSON.stringify(session.state().to_dict())
			assert_false(truth.contains("\"fog\"") or truth.contains("\"view_of\""), "%s turn %d: no fog key" % [g.name, i + 1])
			for v in seats + [FogRules.OBSERVER]:
				assert_eq(JSON.stringify(session.state_for(v).to_dict()), truth, "%s turn %d, %s: state_for is state()" % [g.name, i + 1, v])
				assert_eq(JSON.stringify(session.turn_report_for(v)), JSON.stringify(session.turn_report()), "%s turn %d, %s: turn_report_for is turn_report()" % [g.name, i + 1, v])
				assert_eq(JSON.stringify(session.view_before(v).to_dict()), JSON.stringify(before.to_dict()), "view_before is the state before the turn")
				assert_eq([session.memory(v), session.intel(v)], [{}, {}], "no memory or intel without fog")
		assert_eq(JSON.stringify(session.state().to_dict()), g.final_state, "%s: the final state" % g.name)
		assert_eq(JSON.stringify(JSON.parse_string(JSON.stringify(session.record()))), JSON.stringify(rec), "%s: the record saves as main's" % g.name)


func test_the_computer_reading_state_for_gives_mains_orders() -> void:
	for g in _games():
		var again := _play_through_state_for(g.spec)
		var want: Array = g.record.history
		assert_eq(again.history.size(), want.size(), "%s: as many turns" % g.name)
		for t in mini(again.history.size(), want.size()):
			assert_eq(JSON.stringify(JSON.parse_string(JSON.stringify(again.history[t].orders))), JSON.stringify(want[t].orders),
				"%s turn %d: the computer gives main's orders" % [g.name, t + 1])
		assert_eq(again.final_state, g.final_state, "%s: the same final state" % g.name)


## tools/replay_fixture.gd's play(), with every seat reading session.state_for(its faction) (fog off: state()).
func _play_through_state_for(g: Dictionary) -> Dictionary:
	var seats := ["kingdom", "beasts"]
	var seed_value := int(g.seed)
	var with_paths := bool(g.get("paths", false))
	var policies := []
	var rngs := []
	for i in seats.size():
		var policy = Policies.make(String(g.policies[i]))
		if with_paths:
			policy.configure(seed_value, i, String(g.branches[i]))
		policies.append(policy)
		rngs.append(SeededRNG.new(seed_value * 7919 + (i + 1) * 104729))
	var start := GameState.new(seed_value)
	if g.rulers or with_paths:
		var builds := {}
		for i in seats.size():
			builds[seats[i]] = AIPlayer.choose_build(null, seats[i], rngs[i])
			if g.has("builds"):
				builds[seats[i]] = String(g.builds[i])
		start = GameState.with_paths(seed_value, builds, []) if with_paths else GameState.with_rulers(seed_value, builds, [])
	var session := GameSession.new(start, seats, seed_value, AutoBattleResolver.new())
	while not session.is_over() and session.turns_played() < Fixture.TURN_CAP:
		for seat in seats.size():
			if session.phase() == GameSession.Phase.HANDOFF:
				session.acknowledge_handoff()
			for o in policies[seat].orders(session.state_for(seats[seat]), seats[seat], rngs[seat]):
				session.queue_order(o)
			session.end_turn()
	return {"history": session.record().history, "final_state": JSON.stringify(session.state().to_dict())}
