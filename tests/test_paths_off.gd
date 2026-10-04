extends "res://tests/test_case.gd"
## M4-1 (#66) acceptance, "with paths off": M1 and M2 games are byte-identical to `main`. The fixture
## tests/fixtures/main_records.json holds AI games recorded on main (f98c8b5) before paths existed, with a
## digest of every turn's state and events (tools/replay_fixture.gd made it). Each is replayed with the
## current engine and must match turn by turn. Paths add no save keys, phases or events to those games.

const FIXTURE := "res://tests/fixtures/main_records.json"
const Fixture := preload("res://tools/replay_fixture.gd")


func _games() -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_true(data is Dictionary, "the fixture loads")
	return data.get("games", []) if data is Dictionary else []


func test_main_records_replay_byte_identically_turn_by_turn() -> void:
	var games := _games()
	assert_eq(games.size(), 5, "two M1 games and three M2 games")
	var m2 := 0
	for g in games:
		var rec: Dictionary = g.record
		var errors := []
		var state := GameState.from_dict(rec.start_state, errors)
		assert_true(state != null, "%s: the start state loads: %s" % [g.name, ", ".join(errors)])
		if state == null:
			continue
		assert_false(state.paths, "%s has no paths" % g.name)
		if RulerRules.has_rulers(state):
			m2 += 1
		for i in rec.history.size():
			var entry: Dictionary = rec.history[i]
			var orders := OrderBook.orders_from_dict(entry.orders, errors)
			var result := TurnResolver.resolve(state, orders, Serial.to_int(entry.seed), AutoBattleResolver.new())
			state = result.new_state
			var d := Fixture.digest(state, result.events)
			assert_eq(d.state, g.turns[i].state, "%s turn %d: the state is byte-identical to main" % [g.name, i + 1])
			assert_eq(d.events, g.turns[i].events, "%s turn %d: the events are byte-identical to main" % [g.name, i + 1])
		assert_eq(JSON.stringify(state.to_dict()), g.final_state, "%s: the final state" % g.name)
		var replayed := GameSession.replay(JSON.parse_string(JSON.stringify(rec)), AutoBattleResolver.new())
		assert_eq(replayed.errors, [], "%s: GameSession.replay reads the record" % g.name)
		assert_eq(JSON.stringify(replayed.state.to_dict()), g.final_state, "%s: GameSession.replay agrees" % g.name)
	assert_eq(m2, 3, "the M2 records have rulers")


func test_new_m1_and_m2_games_start_exactly_as_on_main() -> void:
	for g in _games():
		var rec: Dictionary = g.record
		var seed_value := Serial.to_int(rec.game_seed)
		var start: GameState
		if rec.has("builds"):
			var builds := {}
			for fid in rec.builds:
				builds[fid] = {"ruler": rec.builds[fid].ruler, "mandates": rec.builds[fid].mandates}
			start = GameState.with_rulers(seed_value, builds)
		else:
			start = GameState.new(seed_value)
		var now := JSON.stringify(JSON.parse_string(JSON.stringify(start.to_dict())))  # numbers as the fixture's JSON holds them
		assert_eq(now, JSON.stringify(rec.start_state), "%s: the starting save is byte-identical" % g.name)


func test_games_without_paths_save_no_path_keys_and_keep_their_phases() -> void:
	for s in [GameState.new(4), GameState.with_rulers(4)]:
		var d: Dictionary = s.to_dict()
		assert_false(d.has("paths"), "no 'paths' key")
		for f in d.factions:
			for key in ["research_points", "research_target", "researched", "path_branch"]:
				assert_false(f.has(key), "no '%s' key" % key)
		var r := TurnResolver.resolve(s, {}, TurnResolver.seed_for_turn(s))
		for e in r.events:
			assert_true(TurnResolver.PHASES.has(e.phase), "%s: an M1/M2 phase" % e.type)
			assert_false(["research_gained", "research_done", "oath_sworn"].has(e.type), "no research events")
	assert_eq(TurnResolver.PHASES, ["sacrifice", "orders", "movement", "battles", "capture", "recruitment", "income", "rulers"])
	assert_eq(TurnResolver.PATH_PHASES, ["sacrifice", "orders", "movement", "battles", "capture", "recruitment", "income", "research", "rulers"])
	assert_eq(GameSession.PATH_REPORT_PHASES.slice(0, TurnResolver.PATH_PHASES.size()), TurnResolver.PATH_PHASES)
	assert_eq(GameSession.PATH_REPORT_PHASES.back(), "victory")
	# A game with paths saves them, and loads back into a game with paths.
	var p := GameState.with_paths(4)
	assert_eq(p.to_dict().paths, true)
	assert_true(GameState.from_dict(p.to_dict()).paths)
