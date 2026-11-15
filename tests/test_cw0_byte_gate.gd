extends "res://tests/test_case.gd"
## CW-0's gate (#251, design/CANDLEWAKE.md §1.1): every Crown–Clans game stays byte-identical now that the engine takes a third
## faction. tests/fixtures/cw0_legacy_digests.json was recorded by tools/cw0_gate.gd on `next` before the change: for every old
## feature combination (no system, rulers, rulers and paths, or rulers, paths and magic, each with and without forts and
## sieges, independents and fog of war, in both seat orders, with computer, balanced, preset-id and Tithe of Blood builds), the
## md5 of its starting state's raw JSON and of a game the computer plays from it, turn by turn, with its dice.
##
## Every starting state is rebuilt four ways and must give the recorded bytes: GameScreen.starting_state (which now goes
## through GameState.create), GameState.create itself, the frozen legacy constructors, and GameState.create_seated, the
## generic path a game with the Candlewake takes, here seating the Crown and the Clans. Every game is played again from
## GameScreen.starting_state for PLAYED_TURNS turns and each turn's state, events and computer's dice must match the
## fixture's; the tool (`godot --headless --path . -s tools/cw0_gate.gd`) plays the fixture's whole 12 turns.

const Gate := preload("res://tools/cw0_gate.gd")
## Turns of each game the suite plays again (the fixture holds 12; the tool checks them all).
const PLAYED_TURNS := 3

var _fixture := {}


func _games() -> Dictionary:
	if _fixture.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(Gate.OUT))
		_fixture = data if data is Dictionary else {}
	return _fixture.get("games", {})


func test_the_fixture_was_recorded_for_every_old_combination() -> void:
	var games := _games()
	var configs := Gate.configs()
	assert_eq(games.size(), configs.size(), "one recorded game per configuration")
	var chains := {}
	for c in configs:
		var want: Dictionary = games.get(String(c.name), {})
		assert_false(want.is_empty(), "%s is in the fixture" % c.name)
		assert_eq(int(want.get("refused", -1)), 0, "%s: the computer's orders were all accepted when it was recorded" % c.name)
		chains[Gate.flags_of(c).hash()] = true
	# 4 rulers steps x sieges x independents x fog, each seen at least once.
	assert_eq(chains.size(), 32, "all 32 combinations of the six systems that can be played are covered")


func test_every_starting_state_is_the_recorded_bytes_four_ways() -> void:
	var games := _games()
	for c in Gate.configs():
		var want := String(games.get(String(c.name), {}).get("start", ""))
		var flags := Gate.flags_of(c)
		var builds: Dictionary = c.get("builds", {})
		var errors := []
		assert_eq(Gate.state_digest(GameScreen.starting_state(c)), want, "%s: GameScreen.starting_state" % c.name)
		assert_eq(Gate.state_digest(GameState.create(int(c.seed), c.players, flags, builds, errors)), want, "%s: GameState.create" % c.name)
		assert_eq(errors, [], "%s: GameState.create reports nothing" % c.name)
		assert_eq(Gate.state_digest(Gate.legacy_state(c)), want, "%s: the legacy constructors" % c.name)
		assert_eq(Gate.state_digest(GameState.create_seated(int(c.seed), c.players, flags, builds, errors)), want,
			"%s: the generic seating path, on the Crown and the Clans" % c.name)
		assert_eq(errors, [], "%s: create_seated reports nothing" % c.name)


func test_odd_configs_build_what_they_built_before() -> void:
	# Configs the fixture doesn't hold: builds with no "rulers" key (builds have always asked for rulers, even none), and
	# systems named without the ones they need. Gate.legacy_state is the frozen copy of how starting_state chose before CW-0.
	var cases := [
		{"seed": 41, "builds": {}},
		{"seed": 42, "builds": {"kingdom": "regents_court"}},
		{"seed": 43, "paths": true},
		{"seed": 44, "magic": true},
		{"seed": 45, "magic": true, "sieges": true, "independents": true},
		{"seed": 46, "sieges": true, "builds": {}},
		{"seed": 47, "sieges": true, "paths": true, "fog": true},
		{"seed": 48, "rulers": true, "fog": true, "players": ["beasts", "kingdom"]},
		{"seed": 49, "rulers": false, "paths": false, "magic": false, "sieges": false},
	]
	for c in cases:
		var got := GameScreen.starting_state(c)
		assert_true(got != null, "%s builds" % [c])
		assert_eq(Gate.state_digest(got), Gate.state_digest(Gate.legacy_state(c)), "%s: the same bytes as before" % [c])


func test_every_played_game_is_the_recorded_game_turn_by_turn() -> void:
	var games := _games()
	for c in Gate.configs():
		var want: Array = games.get(String(c.name), {}).get("turns", [])
		var got: Dictionary = Gate.play(GameScreen.starting_state(c), c, PLAYED_TURNS)
		assert_eq(int(got.refused), 0, "%s: no order refused" % c.name)
		assert_eq(String(got.dice), String(games.get(String(c.name), {}).get("dice", "")), "%s: the computer's dice before turn 1 (the build draws)" % c.name)
		var n := mini(PLAYED_TURNS, want.size())
		assert_eq(got.turns.size(), n, "%s: %d turns played" % [c.name, n])
		for t in mini(n, got.turns.size()):
			assert_eq(JSON.stringify(got.turns[t]), JSON.stringify(want[t]), "%s: turn %d's state, events and dice" % [c.name, t + 1])


func test_a_re_record_names_the_entries_it_moved() -> void:
	# #183: a change meant to move some old games re-records the fixture and lists what moved. The fixture read back from
	# JSON (its counts come back as floats) against the same games moves nothing; a changed digest or a new entry moves.
	var games := _games()
	assert_eq(Gate.moved_entries(games, games), [], "the fixture against itself")
	var name := String(Gate.configs()[0].name)
	var now := games.duplicate(true)
	now[name]["record"] = "0".repeat(32)
	now["a_new_config"] = games[name].duplicate(true)
	var turned := games.duplicate(true)
	turned[name]["turns"][0]["dice"] = "0".repeat(32)
	var both := [name, "a_new_config"]
	both.sort()
	assert_eq(Gate.moved_entries(games, now), both, "a changed record and a new entry, sorted")
	assert_eq(Gate.moved_entries(games, turned), [name], "a changed turn")
	var counted := games.duplicate(true)
	counted[name]["refused"] = int(games[name].get("refused", 0))
	assert_eq(Gate.moved_entries(games, counted), [], "a count written as an int is the float read back")


func test_the_fixtures_from_before_still_replay() -> void:
	# The older fixtures guard their own games (test_paths_off, test_m5_fields, test_magic_off, test_sieges_off); here one
	# whole record of each is replayed from its stored orders, as a quick tripwire next to the CW-0 gate.
	for path in ["res://tests/fixtures/main_records.json", "res://tests/fixtures/m4_path_records.json", "res://tests/fixtures/m5_base_records.json"]:
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		var game: Dictionary = data.games[0]
		var replayed := GameSession.replay(game.record, AutoBattleResolver.new())
		assert_eq(replayed.errors, [], "%s replays" % path)
		if game.has("final_state") and replayed.state != null:
			assert_eq(JSON.stringify(replayed.state.to_dict()), String(game.final_state), "%s: %s's final state" % [path, game.name])
