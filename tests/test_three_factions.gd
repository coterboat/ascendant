extends "res://tests/test_case.gd"
## CW-0 (#251, design/CANDLEWAKE.md §1): three factions in the engine, two seats in a game. A game holds the factions its
## players chose (GameState.create); the Crown and the Clans keep their capitals and the Candlewake take the free one, shown as
## "the Long Vigil"; configs pick exactly two; a session seats exactly two; and all six ordered pairings play, save, load and
## rematch. The byte gate for the Crown and the Clans is tests/test_cw0_byte_gate.gd.
##
## The Candlewake ship behind their preview box (CW-7, design/CANDLEWAKE.md §12): FactionData.FACTIONS keeps the two shipped factions and
## the Candlewake are FactionData.PREVIEW_FACTIONS. CW-2 gave them rulers; until CW-4 and CW-5 they have no path or mage, so they
## play games without paths and magic.

const CROWN := "kingdom"
const CLANS := "beasts"
const WAKE := "candlewake"
const PAIRINGS := [[CROWN, CLANS], [CLANS, CROWN], [CROWN, WAKE], [WAKE, CROWN], [CLANS, WAKE], [WAKE, CLANS]]
## The systems the Candlewake play with: none, forts with independents and fog, and (CW-2) rulers, (CW-4) paths, (CW-5) magic.
const SYSTEM_SETS := [{}, {"sieges": true, "independents": true, "fog": true}, {"rulers": true, "sieges": true, "independents": true},
	{"paths": true, "fog": true}, {"magic": true, "independents": true}]
const PLAY_TURNS := 5


# --- helpers --------------------------------------------------------------------------------------

func _create(seats: Array, flags: Dictionary = {}, game_seed: int = 31) -> GameState:
	var errors := []
	var s := GameState.create(game_seed, seats, flags, {}, errors)
	assert_eq(errors, [], "%s with %s builds" % [seats, flags.keys()])
	return s


func _json(s: GameState) -> String:
	return JSON.stringify(s.to_dict()) if s != null else ""


## The computer plays both seats of a session started from `start` for `turns` turns. Returns the session and the computer.
func _play(start: GameState, seats: Array, game_seed: int, turns: int) -> Dictionary:
	var ai := {}
	for fid in seats:
		ai[fid] = "normal"
	var session := GameSession.new(start, seats, game_seed, AutoBattleResolver.new(), ai)
	assert_eq(session.setup_errors(), [], "%s: the session starts" % [seats])
	var computer := AISeat.new(session, game_seed)
	var events := []
	while not session.is_over() and session.turns_played() < turns:
		var before := session.turns_played()
		computer.play(session)
		if session.turns_played() == before:
			fail("%s: a turn did not resolve" % [seats])
			break
		events.append_array(session.turn_report().get("events", []))
		var errors := []
		assert_true(session.state().validate(errors), "%s turn %d validates: %s" % [seats, session.turns_played(), errors])
	return {"session": session, "computer": computer, "events": events}


# --- the faction row (§1.3) -----------------------------------------------------------------------

func test_the_candlewake_row_sits_behind_the_preview() -> void:
	var row := FactionData.row(WAKE)
	assert_false(row.is_empty(), "the Candlewake have a row")
	assert_eq(String(row.name), "Candlewake", "a bare proper noun, as 'Aurel Crown' and 'Thornmane Clans' (the templates add 'the')")
	assert_eq(String(row.capital), "", "no capital of its own: it takes the free one")
	assert_eq(String(row.capital_name), "the Long Vigil")
	assert_eq(int(row.gold), int(FactionData.row(CROWN).gold), "the same starting gold as the others")
	assert_eq(FactionData.FACTIONS.map(func(f): return String(f.id)), [CROWN, CLANS], "the shipped factions are unchanged")
	assert_eq(FactionData.PREVIEW_FACTIONS.map(func(f): return String(f.id)), [WAKE], "the Candlewake are behind the preview")
	assert_eq(FactionData.ids(), [CROWN, CLANS, WAKE], "every faction in data order")
	assert_eq(FactionData.playable(false), [CROWN, CLANS], "the preview off: the two shipped factions")
	assert_eq(FactionData.playable(true), [CROWN, CLANS, WAKE], "the preview on: all three")
	assert_true(FactionData.is_preview(WAKE) and not FactionData.is_preview(CROWN))
	# The id meets the engine's id rules (§1.3).
	assert_false(WAKE.contains("-"), "army ids are <faction>-<n>")
	assert_ne(WAKE, IndependentData.FACTION_ID)
	assert_false(WAKE.begins_with("free"), "Free Holds army ids begin with 'free'")
	# The §4.1 host, ids from the CW-9 manifest, each with its trait and the trait's words (CW-2).
	assert_eq(row.unit_types.map(func(u): return String(u.id)), ["wickwardens", "gleaners", "hundred_wick"])
	assert_eq(String(row.commander.id), "lamplighter")
	assert_eq((row.unit_types + [row.commander]).map(func(u): return String(u.trait)), AutoBattleResolver.WICK_TRAITS)
	for u in row.unit_types + [row.commander]:
		assert_false(String(AutoBattleResolver.TRAIT_TEXT.get(String(u.trait), "")).is_empty(), "%s's trait has its words" % u.name)
	# The start army: 2 Wickwardens, the Gleaners and the Hundred-Wick, with the Lamplighter. CW-2's prices make it cost more
	# than the others' (§9 moved them); tests/test_cw2_benchmarks.gd holds it to fighting them evenly instead.
	assert_eq(row.start_army, ["wickwardens", "wickwardens", "gleaners", "hundred_wick"])


func test_create_factions_keeps_the_legacy_pair_by_default() -> void:
	var legacy := FactionData.create_factions()
	assert_eq(legacy.map(func(f): return f.id), [CROWN, CLANS], "the frozen default: the Crown and the Clans")
	var chosen := FactionData.create_factions([WAKE, CROWN])
	assert_eq(chosen.map(func(f): return f.id), [CROWN, WAKE], "data order, whatever order they were asked in")
	assert_eq(chosen[1].faction_name, "Candlewake")
	assert_eq(chosen[1].capital, "fangridge", "the free capital in a Crown–Candlewake game")
	assert_eq(chosen[1].commander_type.id, "lamplighter")


# --- capitals, derived (§1.1) ---------------------------------------------------------------------

func test_capitals_are_derived_from_the_seated_factions() -> void:
	var want := {CROWN: "crownkeep", CLANS: "fangridge"}
	for seats in PAIRINGS:
		var caps := FactionData.capitals_for(seats)
		var s := _create(seats)
		var other: String = seats[0] if seats[1] == WAKE else seats[1]
		for fid in seats:
			var expected: String = want.get(fid, "crownkeep" if other == CLANS else "fangridge")
			assert_eq(String(caps[fid]), expected, "%s's capital in %s" % [fid, seats])
			assert_eq(s.find_faction(fid).capital, expected, "the state agrees (%s)" % [seats])
			assert_eq(s.find_province(expected).owner, fid, "%s holds it at the start" % fid)
			var at := s.armies.filter(func(a): return a.owner == fid)
			assert_eq(at.size(), 1, "%s starts with one army" % fid)
			assert_eq(at[0].location, expected, "%s's army stands in its capital" % fid)
			assert_eq(at[0].id, "%s-1" % fid, "its first army id")
		# Province ids never change; only the Candlewake's capital is shown by its capital_name.
		for p in s.provinces:
			var map_row := {}
			for d in MapData.PROVINCES:
				if String(d.id) == p.id:
					map_row = d
			assert_false(map_row.is_empty(), "%s is a map province" % p.id)
			var long_vigil: bool = seats.has(WAKE) and p.id == s.find_faction(WAKE).capital
			assert_eq(p.name, "the Long Vigil" if long_vigil else String(map_row.name), "%s's name in %s" % [p.id, seats])
		assert_eq(s.factions.map(func(f): return f.id), FactionData.ids().filter(func(fid): return seats.has(fid)),
			"the state lists its factions in data order (%s)" % [seats])


func test_a_crown_clans_game_is_the_legacy_game_whatever_the_seat_order() -> void:
	for seats in [[CROWN, CLANS], [CLANS, CROWN]]:
		for game_seed in [1, 4242]:
			assert_eq(_json(_create(seats, {}, game_seed)), _json(GameState.new(game_seed)), "%s, seed %d" % [seats, game_seed])
			assert_eq(_json(_create(seats, {"sieges": true, "fog": true}, game_seed)), _json(_legacy_sieges_fog(game_seed)),
				"%s with sieges and fog, seed %d" % [seats, game_seed])


func _legacy_sieges_fog(game_seed: int) -> GameState:
	var s := GameState.with_sieges(game_seed, {}, {}, [])
	s.setup_fog([])
	return s


func test_the_candlewake_start_army_and_capital_in_a_sieges_game() -> void:
	for seats in [[CROWN, WAKE], [WAKE, CLANS]]:
		var s := _create(seats, {"sieges": true})
		var wake := s.find_faction(WAKE)
		var army := s.find_army("candlewake-1")
		assert_eq(army.units.map(func(u): return u.type.id), FactionData.row(WAKE).start_army, "the start army from the row")
		assert_eq(army.commander.type.id, "lamplighter")
		var cap := s.find_province(wake.capital)
		assert_eq(cap.fort_level, int(FortData.START.capital), "the Long Vigil is a citadel like every capital")
		# CW-2: the Guttering Ram, the Siege Ram's numbers (§5).
		var ram := SiegeRules.engine_type(WAKE)
		assert_eq(ram.id, "guttering_ram")
		assert_eq(ram.cost, int(FortData.ENGINES.kingdom.cost), "the Siege Ram's price")
		assert_eq(TurnResolver.recruitable_type(wake, "guttering_ram", s).id, "guttering_ram")
		assert_eq(TurnResolver.recruitable_type(wake, "siege_ram", s), null, "another faction's engine is never theirs")


func test_a_start_army_that_names_a_unit_the_faction_lacks_is_refused_in_words() -> void:
	var s := _create([CROWN, WAKE])
	var wake := s.find_faction(WAKE)
	var kept: Array[UnitType] = []
	for ut in wake.unit_types:
		if ut.id != "gleaners":
			kept.append(ut)
	wake.unit_types = kept
	var errors := []
	assert_false(s.place_starting_armies(errors), "the start army can't be placed")
	assert_eq(errors.size(), 1, "one reason: %s" % [errors])
	assert_true(String(errors[0]).contains("Candlewake") and String(errors[0]).contains("not one of its unit types"), String(errors[0]))
	var crown := s.find_army("kingdom-1")
	assert_eq(crown.units.size(), FactionData.row(CROWN).unit_types.size(), "a row without a start army still gets one of each")


# --- the factory refuses in plain words (§1.1) ----------------------------------------------------

func test_the_factory_refuses_in_plain_words() -> void:
	var cases := [
		[[CROWN, "nope"], {}, "not a faction"],
		[[CROWN, CROWN], {}, "twice"],
		[[CROWN], {}, "two"],
		[[CROWN, CLANS, WAKE], {}, "two"],
	]
	for c in cases:
		var errors := []
		var s := GameState.create(5, c[0], c[1], {}, errors)
		assert_eq(s, null, "%s with %s: no game" % [c[0], c[1]])
		assert_false(errors.is_empty(), "%s: a reason" % [c[0]])
		var text := " ".join(errors)
		assert_true(text.to_lower().contains(String(c[2])), "%s: the reason says why ('%s'): %s" % [c[0], c[2], text])
		for raw in ["candlewake", "kingdom", "beasts"]:
			assert_false(text.contains(raw), "no raw ids in '%s'" % text)
	# CW-2: rulers are theirs now, by preset or build; a build of the wrong faction is refused in words.
	var errors := []
	assert_true(GameState.create(5, [CROWN, WAKE], {"rulers": true}, {}, errors) != null, "rulers: %s" % [errors])
	assert_true(GameState.create(5, [WAKE, CLANS], {}, {WAKE: "harvest_moot"}, errors) != null, "a Candlewake preset: %s" % [errors])
	assert_true(GameState.create(5, [WAKE, CLANS], {"paths": true}, {}, errors) != null, "CW-4: paths are theirs too: %s" % [errors])
	assert_true(GameState.create(5, [CROWN, WAKE], {"magic": true}, {}, errors) != null, "CW-5: and magic: %s" % [errors])
	assert_eq(GameState.create(5, [CROWN, WAKE], {}, {WAKE: "regents_court"}, errors), null, "the Crown's preset isn't theirs")


## CW-5: with their magic the Candlewake play every system, as the Crown and the Clans do.
func test_system_problems_name_what_a_faction_cannot_play_yet() -> void:
	for system in ["sieges", "independents", "fog", "rulers", "paths", "magic"]:
		for fid in [CROWN, CLANS, WAKE]:
			assert_eq(GameState.system_problems(fid, {system: true}), [], "%s plays with %s" % [fid, system])
	assert_eq(GameState.system_problems(WAKE, NewGameScreen.default_systems()), [], "and with every default system at once")


# --- configs pick two (§1.1) ----------------------------------------------------------------------

func test_the_default_config_is_the_crown_and_the_clans() -> void:
	assert_eq(GameScreen.default_config().players, [CROWN, CLANS])


## Quick start before CW-0 (ui/new_game_screen.gd at a40d43e), frozen: the same dice must give the same config.
static func _old_quick_start(dice: RandomNumberGenerator) -> Dictionary:
	var ids := [CROWN, CLANS]
	var human: String = ids[dice.randi_range(0, ids.size() - 1)]
	var others := ids.filter(func(fid): return fid != human)
	var opponent: String = others[dice.randi_range(0, others.size() - 1)]
	var game_seed := dice.randi_range(1, NewGameScreen.MAX_RANDOM_SEED)
	var builds := {human: RulerRules.preset_build(RulerRules.balanced_preset(human)),
		opponent: BuildScreen.computer_build(opponent, game_seed, 1)}
	var out := {"players": [human, opponent], "seed": game_seed, "ai": {opponent: NewGameScreen.DEFAULT_LEVEL}, "builds": builds}
	out.merge(NewGameScreen.default_systems())
	return out


## #184 added the computer's style to Quick start's config ("temperaments", AISeat.temperaments_for: a roll of the seed and
## seat on a stream of its own, so the dice are untouched). Everything else is compared with the frozen copy as it was.
func _without_temperaments(config: Dictionary) -> Dictionary:
	var out := config.duplicate(true)
	assert_eq(out.get("temperaments"), AISeat.temperaments_for(out.players, out.ai, out.seed), "the computer's style is its seat's roll")
	out.erase("temperaments")
	return out


func test_quick_start_picks_two_and_keeps_todays_dice() -> void:
	for n in 40:
		var a := RandomNumberGenerator.new()
		a.seed = 1000 + n
		var b := RandomNumberGenerator.new()
		b.seed = 1000 + n
		assert_eq(_without_temperaments(NewGameScreen.quick_start_config(a)), _old_quick_start(b), "seed %d: the preview off, as before" % n)
	# CW-5: the Candlewake play every default system now, so with the preview on Quick start may seat them; the same dice, the
	# same config, and every config it gives can be seated.
	var seated := 0
	for n in 40:
		var c := RandomNumberGenerator.new()
		c.seed = 1000 + n
		var d := RandomNumberGenerator.new()
		d.seed = 1000 + n
		var config := NewGameScreen.quick_start_config(c, true)
		assert_eq(config, NewGameScreen.quick_start_config(d, true), "seed %d: the same dice give the same config" % n)
		assert_false(_without_temperaments(config).has("temperaments"), "seed %d: the computer's style is its seat's roll" % n)
		var players: Array = config.players
		assert_true(players.size() == 2 and players[0] != players[1] and players.all(func(fid): return [CROWN, CLANS, WAKE].has(fid)),
			"seed %d: two of the three: %s" % [n, players])
		assert_eq(GameState.seating_problems(players, config, config.builds), [], "seed %d: %s can be seated" % [n, players])
		if players.has(WAKE):
			seated += 1
	assert_true(seated > 0, "the preview on seats the Candlewake now and then (%d of 40)" % seated)


func test_quick_start_factions_take_the_preview_and_the_systems_into_account() -> void:
	var all_systems := NewGameScreen.default_systems()
	assert_eq(NewGameScreen.quick_start_factions(false, all_systems), [CROWN, CLANS])
	assert_eq(NewGameScreen.quick_start_factions(true, all_systems), [CROWN, CLANS, WAKE], "CW-5: they play every system now")
	var theirs := {"sieges": true, "independents": true, "fog": true}
	assert_eq(NewGameScreen.quick_start_factions(true, theirs), [CROWN, CLANS, WAKE], "with only the systems they play")
	assert_eq(NewGameScreen.quick_start_factions(false, theirs), [CROWN, CLANS], "the preview off hides them")


func test_starting_state_keeps_todays_answer_for_a_player_list_that_cannot_be_seated() -> void:
	var legacy := _json(GameState.new(77))
	var odd := [null, "kingdom", 7, [], [CROWN], [CROWN, CROWN], [CROWN, "nope"], [CROWN, CLANS, WAKE], [CROWN, 5]]
	for players in odd:
		var config := {"seed": 77, "players": players}
		assert_eq(_json(GameScreen.starting_state(config)), legacy, "players %s: the Crown and the Clans, as before" % [players])
	assert_eq(_json(GameScreen.starting_state({"seed": 77})), legacy, "no players at all: as before")
	# The session then says what is wrong, in today's words, and the new two-seat rule for a third player.
	var one := GameSession.new(GameScreen.starting_state({"seed": 77, "players": [CROWN]}), [CROWN], 77)
	assert_true(" ".join(one.setup_errors()).contains("at least two players"), " ".join(one.setup_errors()))
	var dup := GameSession.new(GameScreen.starting_state({"seed": 77, "players": [CROWN, CROWN]}), [CROWN, CROWN], 77)
	assert_true(" ".join(dup.setup_errors()).contains("Two players are set to Aurel Crown"), " ".join(dup.setup_errors()))


func test_a_session_seats_exactly_two() -> void:
	var s := GameState.new(3)
	var three := GameSession.new(s, [CROWN, CLANS, WAKE], 3)
	assert_eq(three.phase(), GameSession.Phase.INVALID)
	var text := " ".join(three.setup_errors())
	assert_true(text.contains("two players"), text)
	assert_eq(GameSession.SEATS, 2)
	var two := GameSession.new(_create([CROWN, WAKE]), [WAKE, CROWN], 3)
	assert_eq(two.setup_errors(), [], "a Crown–Candlewake game seats both, either order")


# --- names ------------------------------------------------------------------------------------------

func test_the_candlewake_are_named_like_the_others() -> void:
	var s := _create([CLANS, WAKE])
	assert_eq(TurnReportText.faction_short(s, WAKE), "the Candlewake")
	assert_eq(TurnReportText.faction_short(s, CLANS), "the Clans", "unchanged")
	assert_eq(TurnReportText.faction_short(GameState.new(1), CROWN), "the Crown", "unchanged")
	assert_eq(TurnReportText.army_name(s, "candlewake-1"), "the Candlewake's 1st")
	assert_eq(RulerRules._faction_display(WAKE), "Candlewake", "found without a state too")
	# Unit names are bare, as "War Bear" and "Knight Captain" are: the templates count them ("2 Wickwardens", "a Hundred-Wick").
	assert_eq(TurnReportText._unit_type_name(null, "hundred_wick"), "Hundred-Wick", "found without a state")
	assert_eq(AscensionRules.base_unit_name(WAKE, "lamplighter"), "Lamplighter")
	# The capital is named by its capital_name wherever the rules name it.
	var caps := FactionData.capitals_for([CLANS, WAKE])
	s.find_province(caps[WAKE]).owner = CLANS
	var check := VictoryCheck.check(s, [CLANS, WAKE])
	assert_true(check.over and check.winner == CLANS, "the Clans took the Long Vigil")
	var text := String(VictoryCheck.summary(s, [CLANS, WAKE], check, 6, 6, 3).text)
	assert_true(text.begins_with("Thornmane Clans captured the Long Vigil, the Candlewake capital, on turn 6."), text)


# --- six pairings play, save, load and rematch ----------------------------------------------------

func test_all_six_pairings_play_save_load_and_rematch() -> void:
	for seats in PAIRINGS:
		for flags in SYSTEM_SETS:
			var game_seed := 600 + PAIRINGS.find(seats) * 10 + SYSTEM_SETS.find(flags)
			var start := _create(seats, flags, game_seed)
			var played := _play(start, seats, game_seed, PLAY_TURNS)
			var session: GameSession = played.session
			var label := "%s %s" % [seats, flags.keys()]
			assert_eq(played.computer.rejections(), [], "%s: the computer's orders were all accepted" % label)
			assert_eq(session.turns_played(), PLAY_TURNS if not session.is_over() else session.turns_played(), label)
			# Both sides really play: each recruits, and each takes ground or marches out of its capital.
			for fid in seats:
				var recruits := 0
				for e in played.events:
					if String(e.type) == "recruited" and Array(e.get("factions", [])).has(fid):
						recruits += 1
				assert_true(recruits > 0, "%s: %s recruits" % [label, fid])
				var final := session.state()
				var held := final.provinces.filter(func(p): return p.owner == fid).size()
				var away := final.armies.filter(func(a): return a.owner == fid and a.location != final.find_faction(fid).capital).size()
				assert_true(held > 1 or away > 0 or session.is_over(), "%s: %s leaves its capital (%d held, %d armies out)" % [label, fid, held, away])
			# Save and load: the record round-trips through JSON into the same game.
			var record := session.record()
			var loaded := GameSession.from_record(JSON.parse_string(JSON.stringify(record)), AutoBattleResolver.new())
			assert_eq(loaded.errors, [], "%s loads" % label)
			if loaded.session != null:
				assert_eq(JSON.stringify(loaded.session.record()), JSON.stringify(record), "%s: the same record after loading" % label)
				assert_eq(_json(loaded.session.state()), _json(session.state()), "%s: the same state after loading" % label)
			var replayed := GameSession.replay(JSON.parse_string(JSON.stringify(record)), AutoBattleResolver.new())
			assert_eq(replayed.errors, [], "%s replays" % label)
			if replayed.state != null:
				assert_eq(_json(replayed.state), _json(session.state()), "%s: the replay ends where the game is" % label)
			# A rematch: the same players with a new seed seat the same factions in the same capitals.
			var config := {"players": seats.duplicate(), "seed": game_seed + 1}
			config.merge(flags)
			var again := GameScreen.starting_state(config)
			assert_eq(again.factions.map(func(f): return [f.id, f.capital]), start.factions.map(func(f): return [f.id, f.capital]),
				"%s: the rematch seats the same factions in the same capitals" % label)


func test_fog_views_of_a_candlewake_game_hold_their_own_side_whole() -> void:
	var s := _create([WAKE, CROWN], {"fog": true, "independents": true})
	var session := GameSession.new(s, [WAKE, CROWN], 9, AutoBattleResolver.new())
	for fid in [WAKE, CROWN]:
		var view := session.state_for(fid)
		assert_true(view != null and view.is_view and view.view_of == fid, "%s has a view" % fid)
		var errors := []
		assert_true(view.validate(errors), "%s's view validates: %s" % [fid, errors])
		assert_eq(view.find_army("%s-1" % fid).units.size(), s.find_army("%s-1" % fid).units.size(), "%s sees its own army whole" % fid)
		assert_eq(view.find_province(view.find_faction(WAKE).capital).name, "the Long Vigil", "a public name")
