extends "res://tests/test_case.gd"
## M3c S-1a (#98) acceptance, "with sieges off" (design/M3C_SIEGES.md §1.3): M1, M2 and M4 games are byte-identical to
## `main`. tests/fixtures/main_records.json holds M1 and M2 AI games recorded on main before paths existed
## (tools/replay_fixture.gd), and tests/fixtures/m4_path_records.json M4 path games recorded on main before forts and
## sieges existed (tools/replay_fixture_paths.gd; its note names the commit). Each is replayed with the current
## engine and must match turn by turn. Without sieges no siege key, phase, event or engine appears, PHASES and
## PATH_PHASES stay as they were, and a recruit naming the capital's id is still rejected.

const MAIN := "res://tests/fixtures/main_records.json"
const PATHS := "res://tests/fixtures/m4_path_records.json"
const Fixture := preload("res://tools/replay_fixture.gd")
const CROWN := "kingdom"


func _games(path: String) -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(data is Dictionary, "%s loads" % path)
	return data.get("games", []) if data is Dictionary else []


## Replays every record in `path` turn by turn; returns how many games had paths.
func _replay_all(path: String) -> int:
	var with_paths := 0
	for g in _games(path):
		var rec: Dictionary = g.record
		var errors := []
		var state := GameState.from_dict(rec.start_state, errors)
		assert_true(state != null, "%s: the start state loads: %s" % [g.name, ", ".join(errors)])
		if state == null:
			continue
		assert_false(state.sieges, "%s has no sieges" % g.name)
		if state.paths:
			with_paths += 1
		for i in rec.history.size():
			var entry: Dictionary = rec.history[i]
			var orders := OrderBook.orders_from_dict(entry.orders, errors)
			var result := TurnResolver.resolve(state, orders, Serial.to_int(entry.seed), AutoBattleResolver.new())
			state = result.new_state
			var d := Fixture.digest(state, result.events)
			assert_eq(d.state, g.turns[i].state, "%s turn %d: the state is byte-identical to main" % [g.name, i + 1])
			assert_eq(d.events, g.turns[i].events, "%s turn %d: the events are byte-identical to main" % [g.name, i + 1])
			for e in result.events:
				assert_true(TurnResolver.phases(state).has(e.phase), "%s: a phase of its game" % e.type)
		assert_eq(JSON.stringify(state.to_dict()), g.final_state, "%s: the final state" % g.name)
		var replayed := GameSession.replay(JSON.parse_string(JSON.stringify(rec)), AutoBattleResolver.new())
		assert_eq(replayed.errors, [], "%s: GameSession.replay reads the record" % g.name)
		assert_eq(JSON.stringify(replayed.state.to_dict()), g.final_state, "%s: GameSession.replay agrees" % g.name)
	return with_paths


func test_main_records_replay_byte_identically_turn_by_turn() -> void:
	var games := _games(MAIN)
	assert_eq(games.size(), 5, "two M1 games and three M2 games")
	assert_eq(_replay_all(MAIN), 0)


func test_the_m4_path_fixture_replays_byte_identically_turn_by_turn() -> void:
	var games := _games(PATHS)
	assert_true(games.size() >= 4, "the M4 path games")
	assert_eq(_replay_all(PATHS), games.size(), "every one has paths")
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATHS))
	assert_true(String(data.get("note", "")).contains("main"), "the note says it was recorded on main: %s" % data.get("note", ""))


func test_no_siege_key_phase_event_or_engine_in_m1_m2_or_m4_games() -> void:
	var siege_keys := ["fort_level", "walls", "fort_by", "works", "siege_since", "owned_since", "lost"]
	for s in [GameState.new(4), GameState.with_rulers(4), GameState.with_paths(4)]:
		assert_false(s.sieges)
		var d: Dictionary = s.to_dict()
		assert_false(d.has("sieges"), "no 'sieges' key")
		for p in d.provinces:
			for key in siege_keys:
				assert_false(p.has(key), "no '%s' key" % key)
		for f in s.factions:
			for ut in f.unit_types:
				assert_eq(FortData.engine_by_id(ut.id), {}, "no engine in the roster")
			assert_eq(TurnResolver.recruitable_type(f, String(FortData.engine_for(f.id).id), s), null, "no engine to recruit")
		assert_false(TurnResolver.phases(s).has("sieges"))
		assert_eq(GameSession.report_phases(s), GameSession.PATH_REPORT_PHASES if s.paths else GameSession.REPORT_PHASES)
		var state: GameState = s
		for t in 3:
			var r := TurnResolver.resolve(state, {}, TurnResolver.seed_for_turn(state))
			for e in r.events:
				assert_true(TurnResolver.phases(state).has(e.phase), "%s: one of the game's phases" % e.type)
				assert_false(e.type.begins_with("siege") or e.type.begins_with("walls") or e.type.begins_with("construction") \
					or e.type == "fort_built", "no siege event: %s" % e.type)
			state = r.new_state
			for a in state.to_dict().armies:
				assert_false(a.has("engines"), "no army carries engines")


func test_the_phase_lists_are_unchanged_and_a_capital_id_at_is_still_rejected() -> void:
	assert_eq(TurnResolver.PHASES, ["sacrifice", "orders", "movement", "battles", "capture", "recruitment", "income", "rulers"])
	assert_eq(TurnResolver.PATH_PHASES, ["sacrifice", "orders", "movement", "battles", "capture", "recruitment", "income", "research", "rulers"])
	assert_eq(TurnResolver.phases(GameState.new(4)), TurnResolver.PHASES)
	assert_eq(TurnResolver.phases(GameState.with_paths(4)), TurnResolver.PATH_PHASES)
	# With sieges, "sieges" comes right after "battles", in any game.
	var with_sieges := TurnResolver.phases(GameState.with_sieges(4))
	assert_eq(with_sieges, ["sacrifice", "orders", "movement", "battles", "sieges", "capture", "recruitment", "income", "rulers"])
	assert_eq(TurnResolver.phases(GameState.with_sieges(4, {}, {"paths": true})).find("research"),
		TurnResolver.phases(GameState.with_sieges(4, {}, {"paths": true})).find("income") + 1)
	assert_eq(GameSession.report_phases(GameState.with_sieges(4)).back(), "victory")
	# Without sieges, `at` naming the capital is rejected as before; with sieges it is the capital.
	for s in [GameState.new(4), GameState.with_rulers(4)]:
		var check := TurnResolver.check_recruit(s, CROWN, RecruitOrder.new("spearmen", "crownkeep"), 100)
		assert_eq(String(check.get("code", "")), "unknown_place", "without sieges a recruit names no fort")
		assert_eq(String(check.reason), "Recruits are made at your capital, or with your ruler where it stands if it has Warband Muster.")
		var fortify := OrderBook.check_order(s, CROWN, FortifyOrder.new("westwatch"), [])
		assert_eq(String(fortify.get("code", "")), "no_sieges")
	assert_eq(TurnResolver.check_recruit(GameState.with_sieges(4), CROWN, RecruitOrder.new("spearmen", "crownkeep"), 100), {},
		"with sieges the capital's id is the capital")
	# A turn with siege orders in a game without sieges rejects them and changes nothing else.
	var m1 := GameState.new(4)
	var r := TurnResolver.resolve(m1, {CROWN: [SiegeOrder.storm("fangridge"), FortifyOrder.new("crownkeep")]}, 1)
	var rejected: Array = r.events.filter(func(e): return e.type == "order_rejected")
	assert_eq(rejected.size(), 2)
	for e in rejected:
		assert_eq(e.cause, "no_sieges")
	var plain := TurnResolver.resolve(m1, {}, 1)
	assert_eq(JSON.stringify(r.new_state.to_dict()), JSON.stringify(plain.new_state.to_dict()), "the state is as if they were never given")
