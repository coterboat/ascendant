extends "res://tests/test_case.gd"
## Saved games, the pure part (SaveGame, GameSession.from_record, AISeat.restore): a save taken at the
## start of a turn and loaded again (through a JSON round trip, as on disk) gives the identical state,
## history, report and phase, the computer's dice exactly where they were, and the same next turns,
## with computer seats (in either seat, and in watch mode), with rulers and without, at several turns.
## A loaded hotseat game starts behind the handoff cover. A save that is not a save, comes from a newer
## version or is damaged gives plain-language reasons and no game, never a script error.

## Words a plain-language load error never uses.
const JARGON := ["Dictionary", "Array", "String", "Nil", "null", "Variant", "Invalid", "SCRIPT", "JSON"]
const SAVED_AT := 1790000000  # a fixed save time, so saves are the same on every run


# --- driving a game -------------------------------------------------------------------------------

## A session and its AISeat for `config` (GameScreen's contract: "players", "seed", "ai", "rulers",
## "builds"), with the real battle rules, exactly as GameScreen.start_game sets them up.
func _game(config: Dictionary) -> Array:
	var ai: Dictionary = config.get("ai", {})
	var session := GameSession.new(GameScreen.starting_state(config), config.players, config.seed, AutoBattleResolver.new(), ai)
	assert_eq(session.setup_errors(), [], "the game starts")
	return [session, AISeat.new(session, config.seed)]


## Quick start's config with fixed dice: a random faction against the computer, rulers on.
func _vs_computer(dice_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = dice_seed
	return NewGameScreen.quick_start_config(rng)


## The person's orders: recruit what the capital can afford, then march the first army one step
## toward the first neighbor it may enter. Refused orders are simply not queued.
func _human_orders(session: GameSession) -> void:
	var state := session.state()
	var fid := session.current_player()
	var f := state.find_faction(fid)
	for ut in f.unit_types:
		session.queue_recruit(ut.id)
	for a in state.armies:
		if a.owner == fid:
			var p := state.find_province(a.location)
			for n in p.neighbors:
				if session.queue_move(a.id, n).is_empty():
					return


## Plays one whole turn from its start: every seat in order, computers through AISeat, people with
## _human_orders, until the turn resolves.
func _play_turn(session: GameSession, computer: AISeat) -> void:
	var start := session.turns_played()
	for guard in 8:
		if session.turns_played() > start or session.is_over():
			return
		if session.phase() == GameSession.Phase.HANDOFF:
			session.acknowledge_handoff()
		elif session.is_computer_turn():
			computer.play(session)
		else:
			_human_orders(session)
			session.end_turn()


## Plays `turns` whole turns and returns the save taken at the start of the next one, after a JSON
## round trip (what a file on disk gives back).
func _play_and_save(session: GameSession, computer: AISeat, turns: int) -> Dictionary:
	for i in turns:
		_play_turn(session, computer)
	var save := SaveGame.make(session, SaveGame.computer_snapshot(computer, session), SaveGame.MANUAL, "Test save", SAVED_AT)
	return JSON.parse_string(JSON.stringify(save))


func _assert_same_game(a: GameSession, b: GameSession, what: String) -> void:
	assert_eq(var_to_str(b.state().to_dict()), var_to_str(a.state().to_dict()), "%s: the same state" % what)
	assert_eq(b.history(), a.history(), "%s: the same orders and turn seeds" % what)
	assert_eq(b.turn_report().events.map(func(e): return e.text), a.turn_report().events.map(func(e): return e.text),
		"%s: the same turn report" % what)
	assert_eq(b.phase(), a.phase(), "%s: the same phase" % what)
	assert_eq(b.current_player(), a.current_player(), "%s: the same seat to act" % what)
	assert_eq(b.turn_number(), a.turn_number(), "%s: the same turn" % what)
	assert_eq(b.battles_fought(), a.battles_fought(), "%s: the same battles" % what)
	assert_eq(b.victory(), a.victory(), "%s: the same result" % what)


## Saves `config`'s game after `turns` turns, loads it, checks it is the same game with the computer's
## dice where they were, then plays two more turns on both and checks they stay the same.
func _assert_round_trip(config: Dictionary, turns: int, what: String) -> void:
	var g := _game(config)
	var a: GameSession = g[0]
	var computer_a: AISeat = g[1]
	var save := _play_and_save(a, computer_a, turns)
	var loaded := SaveGame.restore(save, AutoBattleResolver.new())
	assert_eq(loaded.errors, [], "%s loads" % what)
	if loaded.session == null:
		return
	var b: GameSession = loaded.session
	var computer_b: AISeat = loaded.computer
	if a.human_seats() < 2:
		_assert_same_game(a, b, what)
	else:
		assert_eq(b.phase(), GameSession.Phase.HANDOFF, "%s: two people, so it opens on the handoff cover" % what)
		assert_eq(var_to_str(b.state().to_dict()), var_to_str(a.state().to_dict()), "%s: the same state" % what)
		assert_eq(b.history(), a.history(), "%s: the same history" % what)
	assert_eq(computer_b.rng_state(), computer_a.rng_state(), "%s: the computer's dice are where they were" % what)
	assert_eq(computer_b.report_notes(b), computer_a.report_notes(a), "%s: the computer's notes for the last turn" % what)
	for i in 2:
		_play_turn(a, computer_a)
		_play_turn(b, computer_b)
	assert_eq(var_to_str(b.state().to_dict()), var_to_str(a.state().to_dict()), "%s: two turns later, still the same state" % what)
	assert_eq(b.history(), a.history(), "%s: and the same orders, the computer's included" % what)
	assert_eq(computer_b.rng_state(), computer_a.rng_state(), "%s: and the same dice" % what)
	assert_eq(computer_b.rejections(), [], "%s: the computer's orders all pass" % what)


func _assert_plain(errors: Array, what: String) -> void:
	assert_false(errors.is_empty(), "%s: says why" % what)
	for e in errors:
		var text := String(e)
		assert_true(text.length() > 20 and text.ends_with(".") and text.substr(0, 1) == text.substr(0, 1).to_upper(),
			"%s: a sentence: %s" % [what, text])
		for word in JARGON:
			assert_false(text.contains(word), "%s: no '%s' in: %s" % [what, word, text])


## A save of a vs-computer game with rulers after three turns (JSON round trip).
func _sample_save() -> Dictionary:
	var g := _game(_vs_computer(11))
	return _play_and_save(g[0], g[1], 3)


# --- round trips ----------------------------------------------------------------------------------

func test_vs_computer_with_rulers_round_trips_at_several_turns() -> void:
	for turns in [0, 1, 4]:
		_assert_round_trip(_vs_computer(7), turns, "against the computer with rulers after %d turns" % turns)


func test_computer_in_seat_one_round_trips() -> void:
	# The computer plans before the person each turn, so its dice must come from the start of the turn.
	var config := _vs_computer(3)
	var players: Array = config.players.duplicate()
	players.reverse()
	config.players = players
	config.builds[players[0]] = BuildScreen.computer_build(players[0], config.seed, 0)
	config.builds[players[1]] = RulerRules.preset_build(RulerRules.balanced_preset(players[1]))
	for turns in [0, 3]:
		_assert_round_trip(config, turns, "the computer in seat 1 after %d turns" % turns)


func test_without_rulers_and_in_watch_mode_round_trips() -> void:
	_assert_round_trip({"players": ["kingdom", "beasts"], "seed": 55, "ai": {"beasts": "easy"}}, 3, "no rulers, Easy computer")
	_assert_round_trip({"players": ["beasts", "kingdom"], "seed": 56, "ai": {"beasts": "normal", "kingdom": "normal"}}, 3, "watch mode")


func test_hotseat_round_trips_behind_the_handoff_cover() -> void:
	for turns in [0, 2]:
		_assert_round_trip({"players": ["kingdom", "beasts"], "seed": 99}, turns, "hotseat after %d turns" % turns)
	var g := _game({"players": ["kingdom", "beasts"], "seed": 99})
	var loaded := SaveGame.restore(_play_and_save(g[0], g[1], 1), null)
	var session: GameSession = loaded.session
	assert_eq(session.phase(), GameSession.Phase.HANDOFF)
	assert_eq(session.current_seat(), 1, "player 1 takes the computer first")
	assert_eq(session.current_orders(), [], "nobody's orders are on show")
	assert_true(session.handoff_text().begins_with("Turn 1 is resolved. Pass the computer to player 1"), session.handoff_text())


func test_a_save_made_mid_turn_comes_back_at_the_start_of_that_turn() -> void:
	var g := _game({"players": ["kingdom", "beasts"], "seed": 5})
	var session: GameSession = g[0]
	_play_turn(session, g[1])
	session.acknowledge_handoff()
	_human_orders(session)
	assert_false(session.current_orders().is_empty(), "player 1 has queued orders")
	var save := SaveGame.make(session, {}, SaveGame.MANUAL, "", SAVED_AT)
	var loaded := SaveGame.restore(save, null)
	assert_eq(loaded.errors, [])
	assert_eq(loaded.session.turn_number(), 2, "the turn the save was made in")
	loaded.session.acknowledge_handoff()
	assert_eq(loaded.session.current_orders(), [], "orders queued during the turn are not saved")


func test_a_finished_game_round_trips_to_its_result() -> void:
	# The Aurel Crown marches on Fangridge while the Thornmane army walks away (as in test_top_bar).
	var session := GameSession.new(GameState.new(1), ["kingdom", "beasts"], 1, StubBattleResolver.new())
	for step in [["westwatch", "bloodfen"], ["stonegate", "deepwood"], ["blackwood", "greenglade"], ["ebonpeak", "rivermarch"], ["fangridge", ""]]:
		session.queue_move("kingdom-1", step[0])
		session.end_turn()
		session.acknowledge_handoff()
		if not String(step[1]).is_empty():
			session.queue_move("beasts-2", step[1])
		session.end_turn()
		if session.is_over():
			break
		session.acknowledge_handoff()
	assert_true(session.is_over())
	var loaded := SaveGame.restore(JSON.parse_string(JSON.stringify(SaveGame.make(session, {}, SaveGame.MANUAL, "End", SAVED_AT))), StubBattleResolver.new())
	assert_eq(loaded.errors, [])
	_assert_same_game(session, loaded.session, "a finished game")
	assert_eq(SaveGame.summary_line(loaded.session), "Game over on turn %d: Aurel Crown won." % session.turn_number())


# --- the header -----------------------------------------------------------------------------------

func test_the_header_describes_the_game() -> void:
	var config := _vs_computer(21)
	var g := _game(config)
	var save := _play_and_save(g[0], g[1], 2)
	var h: Dictionary = save.header
	var session: GameSession = g[0]
	var state := session.state()
	assert_eq(int(h.version), SaveGame.VERSION)
	assert_eq(h.kind, SaveGame.MANUAL)
	assert_eq(h.name, "Test save")
	assert_eq(int(h.saved_at), SAVED_AT)
	assert_eq(int(h.turn), 3, "saved at the start of turn 3")
	assert_eq(h.seed, str(config.seed))
	assert_eq(h.rulers, true)
	assert_eq(h.over, false)
	var names := []
	for i in 2:
		var fid: String = config.players[i]
		names.append(state.find_faction(fid).faction_name)
		assert_eq(h.seats[i].faction, fid)
		assert_eq(h.seats[i].faction_name, names[i])
		assert_eq(h.seats[i].kind, "human" if i == 0 else "computer")
		assert_eq(h.seats[i].level, "" if i == 0 else "normal")
	assert_eq(h.factions, names)
	assert_eq(SaveGame.seats_text(h), "%s (you) vs %s (Computer, Normal)" % names)
	var held := [0, 0]
	for p in state.provinces:
		for i in 2:
			if p.owner == config.players[i]:
				held[i] += 1
	assert_eq(h.summary, "Turn 3: %s holds %s, %s %d." % [names[0], "1 province" if held[0] == 1 else "%d provinces" % held[0], names[1], held[1]])
	assert_eq(SaveGame.seats_text({"seats": [{"faction_name": "Aurel Crown", "kind": "human"}, {"faction_name": "Thornmane Clans", "kind": "human"}]}),
		"Aurel Crown vs Thornmane Clans, 2 players at one computer")


func test_default_names() -> void:
	assert_eq(SaveGame.default_name(SaveGame.AUTO, SAVED_AT), "Autosave")
	var manual := SaveGame.default_name(SaveGame.MANUAL, SAVED_AT)
	assert_true(manual.begins_with("Saved ") and manual.contains("2026"), manual)
	assert_eq(SaveGame.make(GameSession.new(GameState.new(1), ["kingdom", "beasts"], 1), {}, SaveGame.MANUAL, "  ", SAVED_AT).header.name, manual,
		"a blank name gets the timestamped default")


func test_the_config_of_a_loaded_game_sets_up_the_same_rematch() -> void:
	var config := _vs_computer(31)
	var g := _game(config)
	var loaded := SaveGame.restore(_play_and_save(g[0], g[1], 1), null)
	var cfg: Dictionary = loaded.config
	assert_eq(cfg.players, config.players)
	assert_eq(cfg.seed, config.seed)
	assert_eq(cfg.ai, config.ai)
	assert_eq(cfg.rulers, true)
	for fid in config.players:
		assert_eq(cfg.builds[fid].ruler, config.builds[fid].ruler, "%s's ruler" % fid)
		assert_eq(cfg.builds[fid].mandates, config.builds[fid].mandates, "%s's mandates" % fid)
	var hotseat := SaveGame.restore(SaveGame.make(GameSession.new(GameState.new(4), ["beasts", "kingdom"], 4), {}, SaveGame.AUTO, "", SAVED_AT), null)
	assert_eq(hotseat.config, {"players": ["beasts", "kingdom"], "seed": 4}, "a hotseat game without rulers stays exactly that")


# --- saves that can't be loaded -------------------------------------------------------------------

func test_not_a_save_or_a_newer_version_is_explained() -> void:
	var save := _sample_save()
	var cases := {
		"text": "hello",
		"a list": [1, 2],
		"another file": {"format": "something-else", "version": 1},
		"no version": {"format": SaveGame.FORMAT, "record": save.record},
	}
	for what in cases:
		var got := SaveGame.restore(cases[what], null)
		assert_eq(got.session, null, "%s gives no game" % what)
		_assert_plain(got.errors, what)
	var newer := save.duplicate(true)
	newer.version = SaveGame.VERSION + 1
	var got := SaveGame.restore(newer, null)
	assert_eq(got.session, null)
	_assert_plain(got.errors, "a newer save")
	assert_true(String(got.errors[0]).contains("newer version of Ascendant"), got.errors[0])
	assert_eq(SaveGame.check(cases["text"]), [SaveGame.NOT_A_SAVE])


func test_a_damaged_save_is_explained() -> void:
	var save := _sample_save()
	var damage := {
		"no game in it": func(s): s.erase("record"),
		"no starting map": func(s): s.record.erase("start_state"),
		"a starting map that is text": func(s): s.record.start_state = "x",
		"players that are not a list": func(s): s.record.players = "kingdom",
		"a turn with a changed seed": func(s): s.record.history[1].seed = "12345",
		"an order of an unknown kind": func(s): s.record.history[0].orders[s.record.players[0]] = [{"type": "teleport"}],
		"orders for a faction with no seat": func(s): s.record.history[0].orders["dragons"] = [],
		"a turn that is not a group": func(s): s.record.history[2] = 7,
		"the computer's dice missing": func(s): s.computer = {},
		"turns copied from earlier in the game": func(s): s.record.history.append_array(s.record.history.duplicate(true)),
	}
	for what in damage:
		var broken: Dictionary = save.duplicate(true)
		damage[what].call(broken)
		var got := SaveGame.restore(broken, AutoBattleResolver.new())
		assert_eq(got.session, null, "%s gives no game" % what)
		_assert_plain(got.errors, what)
		assert_false(SaveGame.error_text(got.errors).is_empty())
	var dice := save.duplicate(true)
	dice.computer = {}
	assert_true(String(SaveGame.restore(dice, null).errors[1]).contains("computer's dice"))
	var seed_changed := save.duplicate(true)
	seed_changed.record.history[1].seed = "12345"
	assert_true(String(SaveGame.restore(seed_changed, null).errors[1]).contains("Turn 2"))


func test_from_record_rebuilds_what_replay_rebuilds() -> void:
	var g := _game(_vs_computer(41))
	var session: GameSession = g[0]
	for i in 3:
		_play_turn(session, g[1])
	var record: Dictionary = JSON.parse_string(JSON.stringify(session.record()))
	var replayed := GameSession.replay(record, AutoBattleResolver.new())
	var rebuilt := GameSession.from_record(record, AutoBattleResolver.new())
	assert_eq(rebuilt.errors, [])
	assert_eq(var_to_str(rebuilt.session.state().to_dict()), var_to_str(replayed.state.to_dict()))
	assert_eq(rebuilt.session.record(), session.record(), "the rebuilt session records the same game")
