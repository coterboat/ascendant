extends "res://tests/test_case.gd"
## The computer in games with rulers (M2-7, #35; design/M2_RULER.md §6): the seeded build pick and its
## single source, AI seats with rulers in GameSession (no handoff with one human, simultaneity, same seed
## same build and orders), the M2 behaviours of AIPlayer (ruler play, sacrifices, King's Roads, Warband
## Muster) and trait-aware recruiting, and plain-language notes without raw ids.

const Simulator := preload("res://tools/autoplay/simulator.gd")
const Policies := preload("res://tools/autoplay/policies.gd")
const SEED := 4242
const SEATS := ["kingdom", "beasts"]
const HUMAN_RNG := 99


# --- fixtures -------------------------------------------------------------------------------------

## The real flow: the build screen rolls each computer seat's build (BuildScreen.computer_build, which
## is AIPlayer.choose_build), the game starts with every build (as GameScreen.starting_state does), and
## AISeat plays the computer seats. `forced` replaces a computer seat's rolled build (to test a preset).
func _session(players: Array, ai: Dictionary, human_builds: Dictionary = {}, game_seed: int = SEED, forced: Dictionary = {}) -> GameSession:
	var builds := human_builds.duplicate(true)
	for i in players.size():
		var fid: String = players[i]
		if ai.has(fid):
			builds[fid] = forced.get(fid, BuildScreen.computer_build(fid, game_seed, i))
	var state := GameState.with_rulers(game_seed, builds, [])
	assert_true(state != null, "the builds are legal")
	return GameSession.new(state, players, game_seed, AutoBattleResolver.new(), ai)


## Plays a scripted human (a deterministic policy queueing through the session, like a person) against
## the computer seats for up to `turns` turns. Returns the AISeat.
func _play(session: GameSession, turns: int, game_seed: int = SEED, human: String = "greedy") -> AISeat:
	var computer := AISeat.new(session, game_seed)
	var person = Policies.make(human)
	var rng := SeededRNG.new(HUMAN_RNG)
	computer.play(session)
	for t in turns:
		if session.is_over():
			break
		assert_ne(session.phase(), GameSession.Phase.HANDOFF, "no handoff with one human (turn %d)" % session.turn_number())
		var fid := session.current_player()
		assert_false(session.is_computer(fid), "the human is up")
		for o in person.orders(session.state(), fid, rng):
			session.queue_order(o)
		assert_eq(session.end_turn(), "")
		computer.play(session)
	return computer


## A state with rulers and the starting armies replaced by `specs`: [[id, owner, location, [unit ids]]];
## the ruler armies stay where `ruler_at` ({faction id: province id}) puts them.
func _state(builds: Dictionary, specs: Array, ruler_at: Dictionary = {}) -> GameState:
	var s := GameState.with_rulers(99, builds, [])
	var rulers := {}
	for a in s.armies:
		if a.ruler != null:
			rulers[a.owner] = a
	s.armies.clear()
	for fid in rulers:
		var ra: Army = rulers[fid]
		ra.location = ruler_at.get(fid, ra.location)
		s.armies.append(ra)
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
	return s


func _own(s: GameState, fid: String, pids: Array) -> void:
	for pid in pids:
		s.find_province(pid).owner = fid


## Every order passes OrderBook in the order given, as GameSession would take them.
func _assert_valid(s: GameState, fid: String, orders: Array, where: String) -> void:
	var book := OrderBook.new()
	for o in orders:
		assert_eq(book.submit(s, fid, o), "", "%s: %s is accepted" % [where, o.describe()])


## Every id a note must never show: the state's armies, provinces, factions and unit types, plus every
## ruler, mandate and preset id, and the underscore that joins ids.
func _ids(s: GameState) -> Array:
	var out := ["_"]
	for a in s.armies:
		out.append(a.id)
	for p in s.provinces:
		out.append(p.id)
	for f in s.factions:
		out.append(f.id)
		for ut in f.unit_types:
			out.append(ut.id)
		out.append(f.commander_type.id)
	for r in RulerData.RULERS:
		out.append(r.id)
	for m in MandateData.MANDATES:
		out.append(m.id)
	for fid in BuildPresetData.PRESETS:
		for p in BuildPresetData.PRESETS[fid]:
			out.append(p.id)
	return out


func _orders_of(session: GameSession, fid: String) -> Array:
	var out := []
	for entry in session.history():
		out.append_array(entry.orders.get(fid, []))
	return out


# --- the build pick (§6.1) ------------------------------------------------------------------------

func test_choose_build_is_the_seeded_preset_roll_and_the_single_source() -> void:
	var seen := {}
	for fid in SEATS:
		for s in range(1, 40):
			var expected: Dictionary = RulerRules.preset_build(RulerRules.presets_for(fid)[SeededRNG.new(s).randi_range(0, 2)].id)
			var build := AIPlayer.choose_build(null, fid, SeededRNG.new(s))
			assert_eq(build, expected, "%s seed %d: presets[faction][rng.randi_range(0, 2)]" % [fid, s])
			assert_eq(AIPlayer.choose_build(GameState.new(1), fid, SeededRNG.new(s)), build, "the state changes nothing")
			seen[build.preset] = true
			for seat in 2:
				var rolled := AIPlayer.choose_build(null, fid, SeededRNG.new(AISeat.seat_seed(s, seat)))
				assert_eq(BuildScreen.computer_build(fid, s, seat), rolled, "the build screen's computer build is the same roll")
				assert_eq(BuildScreen.computer_preset(fid, s, seat), rolled.preset)
	for fid in SEATS:
		for p in RulerRules.presets_for(fid):
			assert_true(seen.has(p.id), "every preset comes up: %s" % p.id)
	# The draw is the RNG's first: exactly one draw is used.
	var rng := SeededRNG.new(5)
	AIPlayer.choose_build(null, "kingdom", rng)
	var twin := SeededRNG.new(5)
	twin.randi_range(0, 2)
	assert_eq(rng.to_dict(), twin.to_dict(), "choose_build makes one draw")
	var untouched := SeededRNG.new(5)
	assert_eq(AIPlayer.choose_build(null, "pirates", untouched), {}, "no presets, no build")
	assert_eq(untouched.to_dict(), SeededRNG.new(5).to_dict(), "and no draw")


func test_preset_for_finds_the_build_played_even_after_sacrifices() -> void:
	for fid in SEATS:
		for p in RulerRules.presets_for(fid):
			var s := GameState.with_rulers(1, {fid: p.id}, [])
			assert_eq(AIPlayer.preset_for(s, fid).id, p.id)
	var s2 := GameState.with_rulers(1, {"kingdom": "warrior_king"}, [])
	RulerRules.apply_sacrifice(s2, "kingdom", "royal_armories", 1)
	assert_eq(AIPlayer.preset_for(s2, "kingdom").id, "warrior_king", "a sacrifice doesn't change the preset played")
	var custom := GameState.with_rulers(1, {"kingdom": {"ruler": "aurel_king", "mandates": ["heavy_tithes", "muster_grounds"]}}, [])
	var stand_in := AIPlayer.preset_for(custom, "kingdom")
	assert_eq(stand_in.id, "", "a custom build has a stand-in")
	assert_eq(stand_in.ai_role, "home", "it keeps 2 power, so the ruler stays home")
	assert_eq(stand_in.ai_sacrifices, ["royal_armories", "veteran_levies"], "with the picks of the first preset with that ruler")
	assert_eq(AIPlayer.preset_for(GameState.new(1), "kingdom"), {}, "no rulers, no preset")


func test_an_ai_seat_rolls_its_build_as_the_first_draw_of_its_rng() -> void:
	for players in [["kingdom", "beasts"], ["beasts", "kingdom"]]:
		var session := _session(players, {"beasts": "normal"}, {"kingdom": "warrior_king"})
		var computer := AISeat.new(session, SEED)
		var seat: int = players.find("beasts")
		var rng := SeededRNG.new(AISeat.seat_seed(SEED, seat))
		var rolled := AIPlayer.choose_build(null, "beasts", rng)
		assert_eq(computer.build("beasts"), rolled, "%s: the seat rolled its build" % [players])
		assert_eq(computer.build("beasts"), BuildScreen.computer_build("beasts", SEED, seat), "the build the build screen gave it")
		assert_eq(RulerRules.build_of(session.state(), "beasts").mandates, rolled.mandates, "and the game started with it")
		assert_eq(computer.rng_state().beasts, rng.to_dict(), "the orders use the draws after it")
		assert_eq(computer.build("kingdom"), {}, "a human seat has no rolled build")
	# A game without rulers makes no draw (tests/test_ai_seat.gd covers its orders).
	var m1 := GameSession.new(GameState.new(SEED), SEATS, SEED, AutoBattleResolver.new(), {"beasts": "normal"})
	var plain := AISeat.new(m1, SEED)
	assert_eq(plain.build("beasts"), {})
	assert_eq(plain.rng_state().beasts, SeededRNG.new(AISeat.seat_seed(SEED, 1)).to_dict())


# --- AI seats with rulers (§6.2) ------------------------------------------------------------------

## The acceptance: a scripted human against the computer, with rulers, for 30 turns (or until the game
## ends) with zero rejected computer orders, for every preset the computer can play, against two scripts
## (the greedy policy, and AIPlayer itself as the human's script, which puts the computer's capital under
## real threat). The computer's sacrifices, road moves and recruits with the Ninth Fang are among those
## orders whenever its build has them.
func test_thirty_turns_with_rulers_and_no_rejected_computer_orders() -> void:
	var used := {"sacrifice": 0, "road": 0, "field": 0}
	for fid in SEATS:
		var human_fid: String = "beasts" if fid == "kingdom" else "kingdom"
		for p in RulerRules.presets_for(fid):
			var orders := []
			for script in ["greedy", "ai"]:
				var players := [human_fid, fid] if script == "greedy" else [fid, human_fid]
				var session := _session(players, {fid: "normal"}, {human_fid: RulerRules.balanced_preset(human_fid)}, SEED, {fid: p.id})
				var computer := _play(session, 30, SEED, script)
				var what := "%s as the computer against the %s script" % [p.name, script]
				assert_true(session.turns_played() >= 5, "%s: the game ran (%d turns)" % [what, session.turns_played()])
				assert_true(session.is_over() or session.turns_played() == 30, "%s: 30 turns or a finished game" % what)
				assert_eq(computer.rejections(), [], "%s: the session refused none of the computer's orders" % what)
				orders.append_array(_orders_of(session, fid))
			for o in orders:
				if o.type == "sacrifice":
					used.sacrifice += 1
				elif o.type == "move" and o.has("via"):
					used.road += 1
				elif o.type == "recruit" and o.get("at", "") == "ruler":
					used.field += 1
			if RulerRules.preset_build(p.id).mandates.has("kings_roads"):
				assert_true(orders.any(func(o): return o.type == "move" and o.has("via")), "%s: the computer used the King's Roads" % p.name)
			if p.ruler == "fang_chieftain":
				assert_true(orders.any(func(o): return o.type == "recruit" and o.get("at", "") == "ruler"),
					"%s: the computer recruited with the Ninth Fang" % p.name)
			if p.style == "spend":
				assert_false(orders.any(func(o): return o.type == "sacrifice"), "%s: nothing left to sacrifice" % p.name)
	assert_true(used.sacrifice > 0, "the computer sacrificed in these games: %s" % used)
	assert_true(used.road > 0 and used.field > 0, str(used))


func test_one_human_never_waits_behind_a_handoff_with_rulers() -> void:
	for players in [["kingdom", "beasts"], ["beasts", "kingdom"]]:
		var session := _session(players, {"beasts": "normal"}, {"kingdom": "iron_crown"})
		assert_ne(session.phase(), GameSession.Phase.HANDOFF)
		var computer := _play(session, 5)
		assert_true(session.turns_played() >= 4, "%s: turns resolved straight through" % [players])
		assert_eq(computer.rejections(), [])
	# Two humans with rulers still hand off.
	var hotseat := GameSession.new(GameState.with_rulers(SEED, {}, []), SEATS, SEED, AutoBattleResolver.new())
	assert_eq(hotseat.end_turn(), "")
	assert_eq(hotseat.phase(), GameSession.Phase.HANDOFF, "two humans hand off")


## The computer reads only the start-of-turn state: its orders and notes are the same whatever the human
## queued first, a sacrifice included.
func test_the_computers_orders_do_not_depend_on_what_the_human_queued() -> void:
	var options := [
		[],
		[SacrificeOrder.new("royal_armories"), RecruitOrder.new("knights"), MoveOrder.new("kingdom-1", "westwatch")],
		[SacrificeOrder.new("veteran_levies"), RecruitOrder.new("spearmen"), RecruitOrder.new("spearmen"), MoveOrder.new("kingdom-2", "rivermarch")],
	]
	var seen := []
	for orders in options:
		var session := _session(SEATS, {"beasts": "normal"}, {"kingdom": "warrior_king"})
		var computer := AISeat.new(session, SEED)
		for o in orders:
			assert_eq(session.queue_order(o), "", "the human's %s is accepted" % o.describe())
		assert_eq(session.end_turn(), "")
		assert_eq(computer.play(session), {"played": ["beasts"], "resolved": true})
		seen.append([session.history()[0].orders.get("beasts", []), computer.report_notes(session)[0].notes])
	for i in range(1, seen.size()):
		assert_eq(seen[i], seen[0], "identical computer orders and notes whatever the human queued (case %d)" % i)
	assert_false(seen[0][0].is_empty())


func test_same_seed_gives_the_same_build_and_orders_and_the_record_replays() -> void:
	for players in [["kingdom", "beasts"], ["beasts", "kingdom"]]:
		var a := _session(players, {"beasts": "normal"}, {"kingdom": "regents_court"})
		var b := _session(players, {"beasts": "normal"}, {"kingdom": "regents_court"})
		var ca := _play(a, 8)
		var cb := _play(b, 8)
		assert_eq(ca.build("beasts"), cb.build("beasts"), "same build")
		assert_eq(a.builds(), b.builds())
		assert_eq(a.history(), b.history(), "%s: same orders and turn seeds" % [players])
		assert_eq(var_to_str(a.state().to_dict()), var_to_str(b.state().to_dict()), "same final state")
		assert_eq(ca.rng_state(), cb.rng_state())
		var replayed := GameSession.replay(JSON.parse_string(JSON.stringify(a.record())), AutoBattleResolver.new())
		assert_eq(replayed.errors, [])
		assert_eq(var_to_str(replayed.state.to_dict()), var_to_str(a.state().to_dict()), "replaying the record needs no AI")
	# Another seed can roll another build.
	var other := SEED + 1
	while BuildScreen.computer_preset("beasts", other, 1) == BuildScreen.computer_preset("beasts", SEED, 1):
		other += 1
	var c := _session(SEATS, {"beasts": "normal"}, {"kingdom": "regents_court"}, other)
	assert_ne(AISeat.new(c, other).build("beasts"), AISeat.new(_session(SEATS, {"beasts": "normal"}, {"kingdom": "regents_court"}), SEED).build("beasts"))


## Through the real screens: one person against the computer with rulers never sees a handoff, the
## computer's orders resolve, and the report shows its build and ruler notes only after resolution.
func test_a_human_plays_the_computer_with_rulers_through_the_game_screen() -> void:
	var config := {"players": SEATS.duplicate(), "seed": SEED, "ai": {"beasts": "normal"}, "rulers": true,
		"builds": {"kingdom": RulerRules.preset_build("warrior_king"), "beasts": BuildScreen.computer_build("beasts", SEED, 1)}}
	var game := load("res://ui/game_screen.tscn").instantiate() as GameScreen
	game.start_game(config)
	assert_false(game.handoff.visible, "no handoff to start")
	assert_true(RulerRules.has_rulers(game.session.state()))
	assert_eq(game.computer.build("beasts"), config.builds.beasts, "the computer plays the build the build screen rolled")
	for t in 3:
		if game.session.is_over():
			break
		game.end_turn_button.pressed.emit()
		assert_false(game.handoff.visible, "turn %d: no handoff" % (t + 1))
		assert_eq(game.computer.rejections(), [])
		assert_true(game.report_overlay.visible)
		var shown: Array = game.report_panel.computer_note_labels().map(func(l): return l.text)
		var expected: Array = game.computer.report_notes(game.session)[0].notes
		assert_eq(shown, expected.map(func(n): return "•  %s" % n), "the notes of the resolved turn")
		if t == 0:
			assert_true(" ".join(expected).contains(RulerRules.preset_data(config.builds.beasts.preset).name),
				"turn 1's notes name the build: %s" % [expected])
		var ids := _ids(game.session.state())
		for line in expected:
			for id in ids:
				assert_false(String(line).contains(id), "no raw id '%s' in note: %s" % [id, line])
		game.close_turn_report()
	game.free()


# --- ruler play (§6.3) ----------------------------------------------------------------------------

func test_a_home_ruler_never_leaves_the_capital() -> void:
	var session := _session(SEATS, {"kingdom": "normal"}, {"beasts": "blood_of_the_fang"}, SEED, {"kingdom": "iron_crown"})
	var ruler_id := RulerRules.ruler_army(session.state(), "kingdom").id
	var computer := _play(session, 20)
	assert_eq(computer.rejections(), [])
	for o in _orders_of(session, "kingdom"):
		assert_false(o.type == "move" and o.army == ruler_id, "the 0-kept King never moves: %s" % o)
	var s := session.state()
	if RulerRules.has_living_ruler(s, "kingdom"):
		assert_eq(RulerRules.ruler_army(s, "kingdom").location, "crownkeep")


func test_a_field_ruler_marches_with_the_strongest_army() -> void:
	var s := GameState.with_rulers(7, {"kingdom": "warrior_king", "beasts": "clan_moot"}, [])
	var ai := AIPlayer.new()
	var orders := ai.plan_orders(s, "kingdom", SeededRNG.new(3))
	_assert_valid(s, "kingdom", orders, "turn 1")
	var moves := {}
	for o in orders:
		if o is MoveOrder:
			moves[o.army_id] = o.to
	var ruler := RulerRules.ruler_army(s, "kingdom")
	assert_true(moves.has("kingdom-1"), "the starting army marches out: %s" % moves)
	assert_eq(moves.get(ruler.id, ""), moves["kingdom-1"], "the 10-kept King goes with it")
	var notes := " ".join(ai.last_plan_notes())
	assert_true(notes.contains("Warrior King"), notes)
	assert_true(notes.contains("King Corvane I moves to"), notes)


## Over whole games, our ruler never attacks without our armies beside it, never takes a battle the
## forecast (with it fighting) calls worse than RULER_JOIN_WIN, and never ends a turn alone next to an
## enemy army unless nothing within reach was safer (its note then says so).
func test_the_ruler_is_never_left_alone_next_to_an_enemy() -> void:
	var checked := 0
	for game_seed in [3, 8]:
		for pair in [["warrior_king", "beast_god_unbound"], ["regents_court", "blood_of_the_fang"]]:
			var state := GameState.with_rulers(game_seed, {"kingdom": pair[0], "beasts": pair[1]}, [])
			var session := GameSession.new(state, SEATS, game_seed, AutoBattleResolver.new())
			var brains := {"kingdom": AIPlayer.new(), "beasts": AIPlayer.new()}
			var rngs := {"kingdom": SeededRNG.new(game_seed), "beasts": SeededRNG.new(game_seed + 1)}
			while not session.is_over() and session.turns_played() < 25:
				for fid in SEATS:
					if session.phase() == GameSession.Phase.HANDOFF:
						session.acknowledge_handoff()
					var view := session.state()
					var orders: Array = brains[fid].plan_orders(view, fid, rngs[fid])
					checked += _check_ruler_plan(view, fid, orders, brains[fid].last_plan_notes())
					for o in orders:
						assert_eq(session.queue_order(o), "", "accepted: %s" % o.describe())
					session.end_turn()
	assert_true(checked > 20, "plans with a living ruler were checked (%d)" % checked)


## 1 when `fid` has a living ruler in `view` and its plan was checked, else 0.
func _check_ruler_plan(view: GameState, fid: String, orders: Array, notes: Array) -> int:
	var ruler := RulerRules.ruler_army(view, fid)
	if ruler == null:
		return 0
	var ends := {}
	for a in view.armies:
		if a.owner == fid:
			ends[a.id] = a.location
	for o in orders:
		if o is MoveOrder:
			ends[o.army_id] = o.to
	var at: String = ends[ruler.id]
	var friends := 0
	for id in ends:
		if id != ruler.id and ends[id] == at:
			friends += 1
	var enemy_near := false
	var enemy_in := false
	var p := view.find_province(at)
	for a in view.armies:
		if a.owner == fid:
			continue
		if a.location == at:
			enemy_in = true
		elif p.neighbors.has(a.location):
			enemy_near = true
	var text := " ".join(notes)
	if enemy_in:
		assert_true(friends > 0, "turn %d: the ruler never attacks alone" % (view.current_turn + 1))
	elif enemy_near and friends == 0:
		assert_true(text.contains("nowhere safer"), "turn %d: the ruler is alone next to an enemy only when nothing was safer: %s" % [view.current_turn + 1, text])
	return 1


# --- sacrifices (§2.4, §6.3) ----------------------------------------------------------------------

func test_sacrifices_when_the_capital_is_threatened_and_the_odds_are_bad() -> void:
	var s := _state({"kingdom": "warrior_king", "beasts": "clan_moot"}, [
		["kingdom-1", "kingdom", "crownkeep", ["spearmen"]],
		["beasts-1", "beasts", "highcrag", ["war_bear", "war_bear", "war_bear", "tuskers", "tuskers", "warchief"]],
	], {"beasts": "fangridge"})
	_own(s, "beasts", ["highcrag"])
	var ai := AIPlayer.new()
	var orders := ai.plan_orders(s, "kingdom", SeededRNG.new(1))
	assert_true(orders[0] is SacrificeOrder, "the sacrifice comes first: %s" % [orders.map(func(o): return o.describe())])
	assert_eq(orders[0].mandate_id, "royal_armories", "the preset's first pick")
	assert_eq(orders.filter(func(o): return o is SacrificeOrder).size(), 1, "one sacrifice per turn")
	_assert_valid(s, "kingdom", orders, "threatened capital")
	var notes := " ".join(ai.last_plan_notes())
	assert_true(notes.contains("Sacrificing 4 of King Corvane I's power for Royal Armories"), notes)
	assert_true(notes.contains("threatens Crownkeep"), notes)
	assert_eq(int(ai.last_plan_stats().sacrifices), 1)
	# Already owned: the next pick. Not enough power, a dead ruler or a preset with no picks: none.
	var s2 := s.deep_copy()
	RulerRules.apply_sacrifice(s2, "kingdom", "royal_armories", 1)
	var next := ai.plan_orders(s2, "kingdom", SeededRNG.new(1))
	assert_true(next[0] is SacrificeOrder and next[0].mandate_id == "veteran_levies", "then Veteran Levies")
	RulerRules.apply_sacrifice(s2, "kingdom", "veteran_levies", 2)
	assert_false(ai.plan_orders(s2, "kingdom", SeededRNG.new(1)).any(func(o): return o is SacrificeOrder), "2 kept: nothing affordable")
	var dead := s.deep_copy()
	RulerRules.record_death(dead, "kingdom", 1)
	assert_false(ai.plan_orders(dead, "kingdom", SeededRNG.new(1)).any(func(o): return o is SacrificeOrder), "only a living ruler sacrifices")
	assert_true(" ".join(ai.last_plan_notes()).contains("No ruler this turn"), str(ai.last_plan_notes()))
	var spender := _state({"kingdom": "iron_crown", "beasts": "clan_moot"}, [
		["kingdom-1", "kingdom", "crownkeep", ["spearmen"]],
		["beasts-1", "beasts", "highcrag", ["war_bear", "war_bear", "war_bear"]],
	], {"beasts": "fangridge"})
	assert_false(ai.plan_orders(spender, "kingdom", SeededRNG.new(1)).any(func(o): return o is SacrificeOrder), "Iron Crown has no picks")


func test_no_sacrifice_when_the_capital_holds_and_one_from_turn_8_when_falling_behind() -> void:
	var s := _state({"kingdom": "warrior_king", "beasts": "clan_moot"}, [
		["kingdom-1", "kingdom", "crownkeep", ["knights", "knights", "knights", "spearmen", "spearmen", "crossbowmen", "knight_captain"]],
		["beasts-1", "beasts", "fangridge", ["tuskers"]],
	], {"beasts": "fangridge"})
	var ai := AIPlayer.new()
	assert_false(ai.plan_orders(s, "kingdom", SeededRNG.new(1)).any(func(o): return o is SacrificeOrder), "no danger, not behind")
	_own(s, "beasts", ["ebonpeak", "ironspike", "bloodfen", "deepwood", "wildmoor", "blackwood", "thornvale", "greenglade"])
	s.current_turn = 6
	assert_false(ai.plan_orders(s, "kingdom", SeededRNG.new(1)).any(func(o): return o is SacrificeOrder), "behind, but turn 7 is too early")
	s.current_turn = 7
	var orders := ai.plan_orders(s, "kingdom", SeededRNG.new(1))
	assert_true(orders[0] is SacrificeOrder, "turn 8 and behind: it sacrifices")
	_assert_valid(s, "kingdom", orders, "falling behind")
	var income: int = TurnResolver.income_of(s, "kingdom").total
	assert_true(" ".join(ai.last_plan_notes()).contains("our income is %d gold against %d for the Thornmane Clans" % [
		income, TurnResolver.income_of(s, "beasts").total]), str(ai.last_plan_notes()))


# --- what it owns: King's Roads and Warband Muster (§6.3) -----------------------------------------

func test_road_moves_bring_an_army_home_and_shorten_a_march() -> void:
	var s := _state({"kingdom": "regents_court", "beasts": "clan_moot"}, [
		["kingdom-1", "kingdom", "stonegate", ["knights", "knights", "spearmen", "spearmen"]],
		["kingdom-5", "kingdom", "crownkeep", ["spearmen"]],
		["beasts-1", "beasts", "highcrag", ["war_bear", "war_bear", "tuskers", "tuskers"]],
	], {"kingdom": "crownkeep", "beasts": "fangridge"})
	_own(s, "kingdom", ["westwatch", "stonegate"])
	_own(s, "beasts", ["highcrag"])
	var ai := AIPlayer.new()
	var orders := ai.plan_orders(s, "kingdom", SeededRNG.new(1))
	_assert_valid(s, "kingdom", orders, "recall by road")
	var road := orders.filter(func(o): return o is MoveOrder and o.is_road_move())
	assert_false(road.is_empty(), "a road move: %s" % [orders.map(func(o): return o.describe())])
	assert_eq(road[0].army_id, "kingdom-1")
	assert_eq(road[0].to, "crownkeep", "back home in one turn")
	assert_eq(road[0].via, "westwatch")
	assert_true(" ".join(ai.last_plan_notes()).contains("King's Roads"), str(ai.last_plan_notes()))
	assert_true(int(ai.last_plan_stats().road_moves) >= 1)
	# Without King's Roads the same army can only step.
	var plain := _state({"kingdom": "warrior_king", "beasts": "clan_moot"}, [
		["kingdom-1", "kingdom", "stonegate", ["knights", "knights", "spearmen", "spearmen"]],
		["kingdom-5", "kingdom", "crownkeep", ["spearmen"]],
		["beasts-1", "beasts", "highcrag", ["war_bear", "war_bear", "tuskers", "tuskers"]],
	], {"kingdom": "crownkeep", "beasts": "fangridge"})
	_own(plain, "kingdom", ["westwatch", "stonegate"])
	_own(plain, "beasts", ["highcrag"])
	assert_false(ai.plan_orders(plain, "kingdom", SeededRNG.new(1)).any(func(o): return o is MoveOrder and o.is_road_move()))


func test_recruits_with_the_ninth_fang_where_it_stands_unless_the_capital_needs_them() -> void:
	var s := _state({"kingdom": "iron_crown", "beasts": "blood_of_the_fang"}, [
		["beasts-1", "beasts", "blackwood", ["tuskers", "tuskers", "war_bear"]],
		["beasts-5", "beasts", "fangridge", ["tuskers", "fangthrowers"]],
		["kingdom-1", "kingdom", "crownkeep", ["spearmen"]],
	], {"beasts": "blackwood", "kingdom": "crownkeep"})
	_own(s, "beasts", ["ebonpeak", "blackwood"])
	s.find_faction("beasts").gold = 60
	var ai := AIPlayer.new()
	var orders := ai.plan_orders(s, "beasts", SeededRNG.new(1))
	_assert_valid(s, "beasts", orders, "Warband Muster")
	var field := orders.filter(func(o): return o is RecruitOrder and o.is_with_ruler())
	var home_recruits := orders.filter(func(o): return o is RecruitOrder and not o.is_with_ruler())
	var listed: Array = orders.map(func(o): return o.describe())
	assert_true(field.size() >= 1 and field.size() <= RulerRules.field_recruit_limit(s, "beasts"), "up to the Fang's limit: %s" % [listed])
	var garrison := orders.all(func(o): return not (o is MoveOrder and o.army_id == "beasts-5"))
	if not garrison:
		assert_true(home_recruits.size() >= field.size(), "with nobody left in the capital, at least half stay home: %s" % [listed])
	assert_true(" ".join(ai.last_plan_notes()).contains("Recruiting with the Ninth Fang"), str(ai.last_plan_notes()))
	# A threatened capital keeps every recruit home.
	var t := s.deep_copy()
	for a in t.armies:
		if a.id == "kingdom-1":
			a.location = "ironspike"
			for i in 6:
				a.units.append(Unit.new(TurnResolver.recruitable_type(t.find_faction("kingdom"), "knights"), "kingdom"))
	_own(t, "kingdom", ["ironspike"])
	var home := ai.plan_orders(t, "beasts", SeededRNG.new(1))
	_assert_valid(t, "beasts", home, "threatened capital")
	assert_false(home.any(func(o): return o is RecruitOrder and o.is_with_ruler()), "the capital needs them")


# --- trait-aware recruiting -----------------------------------------------------------------------

func test_recruits_never_outnumber_the_front_rank_with_volley_units() -> void:
	var s := _state({"kingdom": "warrior_king", "beasts": "clan_moot"}, [
		["kingdom-1", "kingdom", "highcrag", ["spearmen"]],
		["beasts-1", "beasts", "fangridge", ["tuskers", "tuskers", "war_bear"]],
	], {"beasts": "fangridge"})
	for gold in [30, 80, 200, 400]:
		s.find_faction("kingdom").gold = gold
		var orders := AIPlayer.new().plan_orders(s, "kingdom", SeededRNG.new(2))
		_assert_valid(s, "kingdom", orders, "%d gold" % gold)
		var volley := 0
		var front := 0
		for o in orders:
			if o is RecruitOrder:
				var ut := TurnResolver.recruitable_type(s.find_faction("kingdom"), o.unit_type_id)
				if ut.is_commander:
					continue
				if ut.trait_id == AutoBattleResolver.VOLLEY:
					volley += 1
				else:
					front += 1
		assert_true(volley <= front, "%d gold: %d Volley units and %d front-rank units" % [gold, volley, front])
		assert_true(volley + front > 0, "%d gold buys units" % gold)


## Over whole games (with and without rulers, both seat orders), the Crown's AI recruits at least as
## many front-rank units as Crossbowmen, so Volley's shield can hold.
func test_over_whole_games_the_front_rank_keeps_up_with_the_crossbowmen() -> void:
	var front := 0
	var volley := 0
	for options in [{}, {"rulers": true}]:
		for seats in [SEATS, ["beasts", "kingdom"]]:
			for game_seed in [11, 12]:
				var r := Simulator.play_game(game_seed, seats, ["ai", "ai"], 25, Callable(), options)
				assert_eq(r.errors, [])
				assert_eq(r.violations, [])
				assert_eq(r.rejections, {}, "GameSession refused no AI order")
				var st := GameState.from_dict(r.final_state)
				var crown := st.find_faction("kingdom")
				for a in st.armies:
					if a.owner != "kingdom":
						continue
					for u in a.units:
						if u.type.trait_id == AutoBattleResolver.VOLLEY:
							volley += 1
						else:
							front += 1
	assert_true(front >= volley, "front-rank units %d, Crossbowmen %d" % [front, volley])


func test_skirmishers_are_bought_against_volley_units() -> void:
	var counts := []
	for enemy in [["crossbowmen", "crossbowmen", "crossbowmen", "spearmen", "spearmen", "spearmen"], ["knights", "knights", "knights", "knights"]]:
		var s := _state({"kingdom": "warrior_king", "beasts": "clan_moot"}, [
			["kingdom-1", "kingdom", "crownkeep", enemy],
			["beasts-1", "beasts", "bloodfen", ["tuskers"]],
		], {"kingdom": "crownkeep"})
		s.find_faction("beasts").gold = 120
		var orders := AIPlayer.new().plan_orders(s, "beasts", SeededRNG.new(4))
		_assert_valid(s, "beasts", orders, "against %s" % enemy[0])
		counts.append(orders.filter(func(o): return o is RecruitOrder and TurnResolver.recruitable_type(s.find_faction("beasts"), o.unit_type_id).trait_id == AutoBattleResolver.SKIRMISH).size())
	assert_true(counts[0] > counts[1], "more Skirmish units against Crossbowmen (%d) than against Knights (%d)" % [counts[0], counts[1]])


# --- notes ----------------------------------------------------------------------------------------

func test_notes_cover_build_ruler_sacrifice_and_mandates_with_no_raw_ids() -> void:
	var seen := 0
	var text := ""
	for pair in [["warrior_king", "blood_of_the_fang"], ["regents_court", "clan_moot"], ["iron_crown", "beast_god_unbound"]]:
		var state := GameState.with_rulers(5, {"kingdom": pair[0], "beasts": pair[1]}, [])
		var session := GameSession.new(state, SEATS, 5, AutoBattleResolver.new())
		var brains := {"kingdom": AIPlayer.new(), "beasts": AIPlayer.new()}
		var rngs := {"kingdom": SeededRNG.new(1), "beasts": SeededRNG.new(2)}
		while not session.is_over() and session.turns_played() < 20:
			for fid in SEATS:
				if session.phase() == GameSession.Phase.HANDOFF:
					session.acknowledge_handoff()
				var view := session.state()
				var ids := _ids(view)
				for o in brains[fid].plan_orders(view, fid, rngs[fid]):
					session.queue_order(o)
				for note in brains[fid].last_plan_notes():
					seen += 1
					text += " " + note
					for id in ids:
						assert_false(note.contains(id), "a note names '%s' by id: %s" % [id, note])
				assert_true(brains[fid].last_plan_notes().size() <= AIPlayer.MAX_NOTES)
				session.end_turn()
	assert_true(seen > 50, "plans explain themselves (%d notes)" % seen)
	for words in ["plays Warrior King", "plays Iron Crown", "stays in Crownkeep", "with the main army", "King's Roads", "Recruiting with the Ninth Fang"]:
		assert_true(text.contains(words), "a note says '%s'" % words)


func test_the_codex_explains_ai_seats_with_the_numbers_the_ai_uses() -> void:
	var text := RulesCodex.text("ai_seat")
	assert_true(text.contains("first roll"), text)
	assert_true(text.contains("%d or less" % AIPlayer.LOW_KEPT), text)
	assert_true(text.contains("turn %d" % AIPlayer.SACRIFICE_TURN), text)
	assert_true(text.contains("four fifths"), "SACRIFICE_INCOME_SHARE is 0.8")
	assert_eq(AIPlayer.SACRIFICE_INCOME_SHARE, 0.8)
	assert_true(text.contains("King's Roads") and text.contains("Ninth Fang"), text)
	for id in ["_", "kingdom", "beasts"]:
		assert_false(text.contains(id), "no raw id '%s'" % id)
