extends "res://tests/test_case.gd"
## M5-4 (#115) acceptance, the computer under fog of war (design/M5_MAGIC_FOG.md §10.1, §18). The proof that matters: the
## computer is handed its own VIEW and nothing else, so changing anything hidden from it changes nothing it orders.
##   1. test_orders_ignore_hidden_facts: the snapshot and two-turn tests of §2.7 (tests/fog_test_kit.gd), run through the
##      brain: the view is byte-identical, and so is everything the brain says (orders, notes, counters, dice used).
##   2. test_ai_seat_reads_only_the_view: a spy session records what AISeat calls; no truth accessor is called in a fog
##      game, and a static scan of ai/ and the autoplay policies backs it up. The same swap is also made through AISeat.
##   3. test_zero_rejections_under_fog: 30 turns of a person against the computer, and the same seed gives the same orders.
##   4. test_fog_off_*: with fog off, AI games are the games of main (tests/fixtures/m5_base_records.json).
## Then the rules that are new under fog (ai/ai_fog.gd): stale ghosts, the capital check against the top of each total,
## scouting, and #94's stand-off rule on the view. Every number a case needs comes from the data and from the brain's own
## guesses, never typed in.

const Kit := preload("res://tests/fog_test_kit.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const SEATS := ["kingdom", "beasts"]
const FIXTURE := "res://tests/fixtures/m5_base_records.json"
## The code the computer is made of: every script in ai/ (a later one, such as the magic AI, is scanned too) and the autoplay
## policies that wrap the brain.
const POLICIES := "res://tools/autoplay/policies.gd"
## Counters that time the plan rather than describe it.
const TIMING := ["usec", "odds_usec"]


# --- fixtures -----------------------------------------------------------------------------------------

## A fresh fog state with the starting armies replaced by `specs` ([[id, owner, location, [unit type ids]], ...]),
## `owners` {province id: faction id} on top of the capitals, and `turn` turns played.
func _fog_state(specs: Array, owners: Dictionary = {}, turn: int = 0) -> GameState:
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
	assert_true(s.setup_fog([]), "the scenario is a valid fog game")
	s.current_turn = turn
	return s


func _many(type_id: String, n: int) -> Array:
	var out := []
	for i in n:
		out.append(type_id)
	return out


## `viewer`'s view of `s` with its memory and intel as the start of a game gives them (or the ones given).
func _view(s: GameState, viewer: String = CROWN, memory = null, intel = null) -> GameState:
	return FogRules.view_state(s, viewer, memory if memory != null else FogRules.new_memory(s, viewer),
		intel if intel != null else FogRules.new_intel(s, viewer))


## One plan of a fresh brain on `state`, the dice at the seat's seed: {"orders", "notes", "stats", "rng", "json"} where
## json is everything the brain says, as text, for comparing two plans byte for byte.
func _plan(state: GameState, fid: String, game_seed: int = 7, level: String = "normal", configured: bool = true) -> Dictionary:
	var seat := SEATS.find(fid)
	var brain := AIPlayer.new()
	if configured:
		brain.configure(game_seed, seat)
	var rng := SeededRNG.new(AISeat.seat_seed(game_seed, seat))
	var orders: Array = brain.plan_orders(state, fid, rng, level)
	var stats := brain.last_plan_stats()
	for key in TIMING:
		stats.erase(key)
	var notes := brain.last_plan_notes()
	var dicts := orders.map(func(o): return o.to_dict())
	return {"orders": orders, "notes": notes, "stats": stats, "rng": rng.to_dict(), "moves": _moves(orders),
		"json": JSON.stringify({"orders": dicts, "notes": notes, "stats": stats, "rng": rng.to_dict()})}


func _moves(orders: Array) -> Dictionary:
	var out := {}
	for o in orders:
		if o is MoveOrder:
			out[o.army_id] = o.to
	return out


## Every order passes the checks GameSession's OrderBook runs on `state`, in order.
func _assert_legal(state: GameState, fid: String, orders: Array, what: String) -> void:
	var book := OrderBook.new()
	for o in orders:
		assert_eq(book.submit(state, fid, o), "", "%s: %s is accepted" % [what, o.describe()])


func _said(plan: Dictionary) -> String:
	return " ".join(plan.notes)


# --- 1. the orders ignore everything hidden (§10.1, test 1) ---------------------------------------------

func test_orders_ignore_hidden_facts() -> void:
	# Snapshot: every third turn of 20 fog games, both viewers. Everything hidden from the viewer is changed (with its
	# memory and intel held fixed), the view is the same, and so is everything the brain says about it.
	var checks := 0
	var leaks_found := 0  # not vacuous: handed the truth instead, the brain's plan differs in some of these cases
	for g in Kit.games():
		for i in g.turns.size():
			if i % 3 != 2:
				continue
			var t: Dictionary = g.turns[i]
			for v in Kit.SEATS:
				var base_view: GameState = t.view_after[v]
				var base := _plan(base_view, v, int(g.seed))
				_assert_legal(t.after, v, base.orders, "%s turn %d, %s" % [g.name, t.turn, v])
				for k in 2:
					var p := Kit.perturb_hidden(t.after, v, hash([g.seed, t.turn, v, k, "ai"]))
					if p.state == null:
						continue
					var view := FogRules.view_state(p.state, v, t.memory_after[v], t.intel_after[v])
					var what := "%s turn %d, %s, perturbation %d" % [g.name, t.turn, v, k]
					assert_eq(JSON.stringify(view.to_dict()), JSON.stringify(base_view.to_dict()), "%s: the view is byte-identical" % what)
					var got := _plan(view, v, int(g.seed))
					assert_eq(got.json, base.json, "%s: the brain says the same, orders, notes, counters and dice" % what)
					_assert_legal(p.state, v, got.orders, what)
					checks += 1
					if k == 0 and i == 5:
						if _plan(t.after, v, int(g.seed)).json != _plan(p.state, v, int(g.seed)).json:
							leaks_found += 1
					for n in base.notes:
						assert_false(String(n).contains("seen-"), "%s: no view id in a note: %s" % [what, n])
	assert_true(checks >= 20 * 2 * 2 * 3, "three snapshot turns a game or more, both viewers, two perturbations each (%d)" % checks)
	assert_true(leaks_found > 0, "handed the truth, the brain would have said something else in %d of the cases tried" % leaks_found)


func test_orders_ignore_hidden_orders_of_the_rival() -> void:
	# Two-turn: the rival's orders vary in ways the viewer can't see; the viewer's next view is the same (the §2.7 test), and
	# so is everything the brain says about it.
	for g in Kit.games():
		var ran := 0
		for t in g.turns:
			if ran >= 5:
				break
			var base_result := TurnResolver.resolve(t.before, t.orders, int(t.seed), AutoBattleResolver.new())
			for v in Kit.SEATS:
				var rival := Kit.rival_of(v)
				var sight0 := FogRules.sight(t.before, v)
				var sight1 := FogRules.sight(base_result.new_state, v)
				var base := FogRules.turn_for(base_result.events, v, t.before, base_result.new_state, t.memory_before[v], t.intel_before[v])
				var facts := Kit.public_facts(base_result.new_state, base_result.events, v)
				var base_plan := {}
				for variation in Kit.two_turn_variations(t.before, v, t.orders[rival], sight0, sight1, t.intel_before[v]):
					if ran >= 5:
						break
					var orders := {v: t.orders[v], rival: variation.orders}
					var result := TurnResolver.resolve(t.before, orders, int(t.seed), AutoBattleResolver.new())
					if Kit.public_facts(result.new_state, result.events, v) != facts \
							or Kit.to_json(result.new_state) == Kit.to_json(base_result.new_state):
						continue  # not a hidden variation, or no variation at all
					var got := FogRules.turn_for(result.events, v, t.before, result.new_state, t.memory_before[v], t.intel_before[v])
					if base_plan.is_empty():
						base_plan = _plan(base.view_after, v, int(g.seed))
					var what := "%s turn %d, %s, %s" % [g.name, t.turn, v, variation.what]
					assert_eq(JSON.stringify(got.view_after.to_dict()), JSON.stringify(base.view_after.to_dict()), "%s: the next view" % what)
					assert_eq(_plan(got.view_after, v, int(g.seed)).json, base_plan.json, "%s: the brain says the same on the next turn" % what)
					ran += 1
		assert_true(ran >= 5, "%s: at least 5 hidden variations ran (%d)" % [g.name, ran])


# --- 2. the seat reads only the view (§10.1, test 2) ------------------------------------------------

## A GameSession that records which accessors are called from outside it (the session's own calls of one another don't
## count): the truth accessors (state, turn_report, battle_events, builds, record, history, victory) and, for the per-viewer
## ones, the viewer asked about.
class SpySession extends GameSession:
	var truth_calls: Array = []
	var viewer_calls: Array = []  # [accessor, viewer]
	var _inside := 0

	func _init(p_state: GameState = null, p_players: Array = [], p_seed: int = 0, p_resolver: BattleResolver = null,
			p_computer: Dictionary = {}) -> void:
		super._init(p_state, p_players, p_seed, p_resolver, p_computer)

	func _truth(accessor: String) -> void:
		if _inside == 0:
			truth_calls.append(accessor)

	func _viewer(accessor: String, viewer: String) -> void:
		if _inside == 0:
			viewer_calls.append([accessor, viewer])

	func state() -> GameState:
		_truth("state")
		return super.state()

	func turn_report() -> Dictionary:
		_truth("turn_report")
		return super.turn_report()

	func battle_events() -> Array:
		_truth("battle_events")
		return super.battle_events()

	func builds() -> Dictionary:
		_truth("builds")
		return super.builds()

	func record() -> Dictionary:
		_truth("record")
		_inside += 1
		var r := super.record()
		_inside -= 1
		return r

	func history() -> Array:
		_truth("history")
		return super.history()

	func victory() -> Dictionary:
		_truth("victory")
		return super.victory()

	func state_for(viewer: String) -> GameState:
		_viewer("state_for", viewer)
		_inside += 1
		var r := super.state_for(viewer)
		_inside -= 1
		return r

	func view_state(viewer: String) -> GameState:
		_viewer("view_state", viewer)
		_inside += 1
		var r := super.view_state(viewer)
		_inside -= 1
		return r

	func view_before(viewer: String) -> GameState:
		_viewer("view_before", viewer)
		return super.view_before(viewer)

	func turn_report_for(viewer: String) -> Dictionary:
		_viewer("turn_report_for", viewer)
		_inside += 1
		var r := super.turn_report_for(viewer)
		_inside -= 1
		return r

	func memory(viewer: String) -> Dictionary:
		_viewer("memory", viewer)
		return super.memory(viewer)

	func intel(viewer: String) -> Dictionary:
		_viewer("intel", viewer)
		return super.intel(viewer)


## A person who recruits Spearmen with all its gold at the capital and stays at home: it lasts a good while.
func _homebody_orders(session: GameSession) -> void:
	for i in 6:
		if session.queue_recruit("spearmen") != "":
			break


func _fog_game(kind: String, game_seed: int) -> GameState:
	var s: GameState
	match kind:
		"m2":
			s = GameState.with_rulers(game_seed)
		"m4":
			s = GameState.with_paths(game_seed)
		"sieges":
			s = GameState.with_sieges(game_seed, {}, {"rulers": true})
		_:
			s = GameState.new(game_seed)
	assert_true(s.setup_fog([]), "a %s fog game" % kind)
	return s


func test_ai_seat_reads_only_the_view() -> void:
	for kind in ["m1", "m2", "m4", "sieges"]:
		var spy := SpySession.new(_fog_game(kind, 311), SEATS, 311, AutoBattleResolver.new(), {CLANS: "normal"})
		var ai := AISeat.new(spy, 311)
		var turns := 0
		while not spy.is_over() and turns < 12:
			_homebody_orders(spy)
			assert_eq(spy.end_turn(), "")
			ai.play(spy)
			ai.report_notes(spy)
			turns += 1
		assert_true(turns >= 6, "%s: the game ran (%d turns)" % [kind, turns])
		assert_eq(spy.truth_calls, [], "%s: the seat called no truth accessor of the session" % kind)
		assert_true(spy.viewer_calls.size() > turns, "%s: it read its view (%d calls)" % [kind, spy.viewer_calls.size()])
		for call in spy.viewer_calls:
			# the person's seat is not asked about: the computer only ever asks for its own side
			assert_eq(call[1], CLANS, "%s: %s was asked for the computer's own view only" % [kind, call[0]])
		var asked := {}
		for call in spy.viewer_calls:
			asked[call[0]] = true
		assert_true(asked.has("view_state") and asked.has("turn_report_for"), "%s: the plan reads view_state and the notes turn_report_for: %s" % [kind, asked.keys()])
	# The spy does see a truth accessor when one is called (so an empty list means something).
	var probe := SpySession.new(GameState.new(1), SEATS, 1, AutoBattleResolver.new())
	probe.state()
	probe.record()
	assert_eq(probe.truth_calls, ["state", "record"])


func _sources() -> Array:
	var out := [POLICIES]
	for file in DirAccess.get_files_at("res://ai"):
		if file.ends_with(".gd"):
			out.append("res://ai/" + file)
	out.sort()
	return out


## The code of `path` without its comments and without the text inside quotes.
func _code(path: String) -> String:
	var out := []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var kept := ""
		var quote := ""
		for ch in line:
			if quote.is_empty():
				if ch == "#":
					break
				if ch == "\"" or ch == "'":
					quote = ch
				kept += ch
			else:
				if ch == quote:
					quote = ""
					kept += ch
		out.append(kept)
	return "\n".join(out)


func test_the_ai_code_never_reads_the_truth() -> void:
	var forbidden := {
		"a truth accessor of a session": ".state()", "the true turn report": ".turn_report()", "the true battle events": ".battle_events()",
		"the true builds": ".builds()", "the record": ".record()", "the history": ".history()", "the victory": ".victory()",
		"the observer's view": "OBSERVER", "a turn resolved": "TurnResolver.resolve", "a replay": "GameSession.replay",
		"a record loaded": "from_record", "a turn's seed": "turn_seed", "the fog's truth": "FogRules.turn_for",
	}
	var sources := _sources()
	assert_true(sources.size() >= 6 and sources.has("res://ai/ai_fog.gd") and sources.has("res://ai/ai_seat.gd"), "the scan finds the computer's code: %s" % str(sources))
	for path in sources:
		var code := _code(path)
		assert_true(code.length() > 200, "%s was read" % path)
		for what in forbidden:
			assert_false(code.contains(String(forbidden[what])), "%s never uses %s (%s)" % [path, what, forbidden[what]])
	# Scouting and the top of a sighting draw nothing: ai_fog.gd has no dice at all (§10.1: no new draws).
	var fog := _code("res://ai/ai_fog.gd")
	for token in ["_rng", "randi", "randf", "RandomNumberGenerator", "SeededRNG", "shuffle", "pick_random"]:
		assert_false(fog.contains(token), "ai_fog.gd uses no dice (%s)" % token)


func test_the_seat_hands_the_brain_a_view_and_the_state_in_a_game_without_fog() -> void:
	var fog := SpySession.new(_fog_game("m1", 5), SEATS, 5, AutoBattleResolver.new(), {CLANS: "normal"})
	var ai := AISeat.new(fog, 5)
	fog.end_turn()
	ai.play(fog)
	assert_eq(fog.truth_calls, [])
	var plain := SpySession.new(GameState.new(5), SEATS, 5, AutoBattleResolver.new(), {CLANS: "normal"})
	var ai2 := AISeat.new(plain, 5)
	plain.end_turn()
	ai2.play(plain)
	assert_eq(plain.truth_calls, [], "without fog too: it asks state_for, which is state()")
	assert_false(plain.state_for(CLANS).is_view, "a game without fog hands out the state")
	assert_true(fog.state_for(CLANS).is_view, "a fog game hands out the view")


func test_the_build_pick_and_the_notes_come_through_the_view() -> void:
	# The build is the seat's first draw, from the view (_init), as the build screen picks it; the notes of a resolved turn
	# are read through turn_report_for.
	var spy := SpySession.new(_fog_game("m2", 12), SEATS, 12, AutoBattleResolver.new(), {CLANS: "normal"})
	var ai := AISeat.new(spy, 12)
	assert_eq(ai.build(CLANS), AIPlayer.choose_build(null, CLANS, SeededRNG.new(AISeat.seat_seed(12, 1))), "the build screen's roll")
	assert_false(ai.build(CLANS).is_empty())
	assert_eq(spy.truth_calls, [], "and nothing true was read to make it")
	assert_eq(ai.report_notes(spy), [], "no notes before the first turn resolves")
	_homebody_orders(spy)
	spy.end_turn()
	ai.play(spy)
	var notes := ai.report_notes(spy)
	assert_eq(notes.size(), 1, "one computer seat's notes")
	assert_eq(String(notes[0].faction), CLANS)
	assert_eq(String(notes[0].faction_name), spy.state_for(CLANS).find_faction(CLANS).faction_name)
	assert_false(notes[0].notes.is_empty())
	assert_eq(spy.truth_calls, [])


## The orders AISeat gives the viewer on `state` (a mid-game state, as a session's start): the seat plays, the person opposite
## passes. {"orders": the order dictionaries}.
func _seat_orders(state: GameState, game_seed: int, viewer: String) -> Dictionary:
	var session := GameSession.new(state.deep_copy(), SEATS, game_seed, AutoBattleResolver.new(), {viewer: "normal"})
	var ai := AISeat.new(session, game_seed)
	if viewer == SEATS[1]:
		assert_eq(session.end_turn(), "", "the person in seat 1 passes")
	ai.play(session)
	if viewer == SEATS[0]:
		assert_eq(session.end_turn(), "", "the person in seat 2 passes")
	assert_eq(session.turns_played(), 1, "the turn resolved")
	assert_eq(ai.rejections(), [], "no order refused")
	return {"orders": session.history().back().orders.get(viewer, [])}


func test_the_seat_gives_the_same_orders_in_every_world_that_looks_the_same() -> void:
	var checked := 0
	for g in Kit.games():
		if g.kind == "m4":
			continue  # a session started mid-game has not heard the Oaths, which a view needs (the paths games run from turn 1 elsewhere)
		for i in [2, 8]:
			if i >= g.turns.size():
				continue
			var t: Dictionary = g.turns[i]
			for v in Kit.SEATS:
				var base := _seat_orders(t.after, int(g.seed), v)
				var p := Kit.perturb_hidden(t.after, v, hash([g.seed, t.turn, v, "seat"]))
				if p.state == null:
					continue
				var what := "%s turn %d, %s" % [g.name, t.turn, v]
				var got := _seat_orders(p.state, int(g.seed), v)
				assert_eq(JSON.stringify(got.orders), JSON.stringify(base.orders), "%s: the seat gives the same orders" % what)
				checked += 1
	assert_true(checked >= 15 * 2 * 2 - 4, "worlds compared (%d)" % checked)


func test_a_leak_would_show() -> void:
	# A Clans army three moves from the Crown capital, out of its sight: handed the truth, the brain keeps its garrison home
	# for it; handed the view, it knows nothing of it, and the seat plays the same whether or not the army is there.
	var specs := [["kingdom-1", CROWN, "crownkeep", ["spearmen", "spearmen"]], ["kingdom-2", CROWN, "crownkeep", ["crossbowmen"]],
		["beasts-1", CLANS, "fangridge", ["warchief", "tuskers"]]]
	var with_army := _fog_state(specs + [["beasts-2", CLANS, "deepwood", _many("tuskers", 14) + _many("war_bear", 4)]])
	var without := _fog_state(specs)
	assert_eq(String(FogRules.sight(with_army, CROWN).deepwood), FogRules.VEILED, "Deepwood is out of the Crown's sight")
	var truth_plan := _plan(with_army, CROWN)
	assert_true(_said(truth_plan).contains("three moves away"), "handed the truth it plans for the army: %s" % _said(truth_plan))
	var view_plan := _plan(_view(with_army), CROWN)
	assert_false(_said(view_plan).contains("three moves away"), "handed the view it does not: %s" % _said(view_plan))
	assert_eq(view_plan.json, _plan(_view(without), CROWN).json, "the view plan is the plan for a board without the army")
	assert_eq(JSON.stringify(_seat_orders(with_army, 7, CROWN).orders), JSON.stringify(_seat_orders(without, 7, CROWN).orders),
		"and so is the seat's, with the army there or not")
	assert_ne(truth_plan.json, _plan(without, CROWN).json, "while the truth plans differ: a seat that read it would show")


# --- 3. zero rejections under fog (§10.1, test 3) ---------------------------------------------------

func _play_against_a_homebody(kind: String, game_seed: int, level: String, turns: int) -> Dictionary:
	var session := GameSession.new(_fog_game(kind, game_seed), SEATS, game_seed, AutoBattleResolver.new(), {CLANS: level})
	var ai := AISeat.new(session, game_seed)
	var played := 0
	while not session.is_over() and played < turns:
		_homebody_orders(session)
		assert_eq(session.end_turn(), "", "the person ends turn %d" % (played + 1))
		ai.play(session)
		played += 1
	return {"record": JSON.stringify(session.record()), "rejections": ai.rejections(), "turns": session.turns_played(), "over": session.is_over()}


func test_zero_rejections_under_fog() -> void:
	var total := 0
	for kind in ["m1", "m2", "m4", "sieges"]:
		for level in ["normal", "easy"]:
			var a := _play_against_a_homebody(kind, 41, level, 30)
			assert_eq(a.rejections, [], "%s, %s: the computer's orders are never refused" % [kind, level])
			total += int(a.turns)
			var b := _play_against_a_homebody(kind, 41, level, 30)
			assert_eq(b.record, a.record, "%s, %s: the same seed gives the same orders" % [kind, level])
	assert_true(total >= 30, "the games ran %d turns in all" % total)


func test_computer_against_computer_under_fog_is_never_refused_and_fights() -> void:
	var battles := 0
	var finished := 0
	for kind in ["m1", "m2", "m4", "sieges"]:
		for game_seed in [3, 4]:
			var session := GameSession.new(_fog_game(kind, game_seed), SEATS, game_seed, AutoBattleResolver.new(), {CROWN: "normal", CLANS: "normal"})
			var ai := AISeat.new(session, game_seed)
			while not session.is_over() and session.turns_played() < 60:
				if ai.play(session).played.is_empty():
					break
			assert_eq(ai.rejections(), [], "%s %d: no order refused" % [kind, game_seed])
			battles += session.battles_fought()
			finished += 1 if session.is_over() else 0
	assert_eq(finished, 8, "every game was won inside 60 turns, none stalled")
	assert_true(battles >= 8, "and the computers fought (%d battles in 8 games)" % battles)


# --- 4. fog off: main's games (§10.1, test 4) -------------------------------------------------------

func _fixture_games() -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_true(data is Dictionary, "the fixture loads")
	return data.get("games", []) if data is Dictionary else []


func test_fog_off_the_seat_plays_main_games() -> void:
	# The fixture's games with both seats played by AISeat instead of the policy loop: the same orders turn by turn. (The
	# games with a forced side of the fork are left to tests/test_fog_off.gd: AISeat rolls its own.)
	var ran := 0
	for g in _fixture_games():
		var spec: Dictionary = g.spec
		if spec.policies != ["ai", "ai"] or (bool(spec.get("paths", false)) and spec.branches != ["", ""]):
			continue
		var start := GameState.from_dict(g.record.start_state, [])
		assert_false(start.fog, "%s: no fog" % g.name)
		var game_seed := Serial.to_int(g.record.game_seed)
		var session := GameSession.new(start, SEATS, game_seed, AutoBattleResolver.new(), {CROWN: "normal", CLANS: "normal"})
		var ai := AISeat.new(session, game_seed)
		var want: Array = g.record.history
		while not session.is_over() and session.turns_played() < want.size():
			if ai.play(session).played.is_empty():
				break
		assert_eq(session.turns_played(), want.size(), "%s: as many turns" % g.name)
		var got := session.history()
		for t in mini(got.size(), want.size()):
			assert_eq(JSON.stringify(JSON.parse_string(JSON.stringify(got[t].orders))), JSON.stringify(want[t].orders),
				"%s turn %d: the seat gives main's orders" % [g.name, t + 1])
		assert_eq(JSON.stringify(session.state().to_dict()), g.final_state, "%s: the same final state" % g.name)
		ran += 1
	assert_true(ran >= 4, "M1, M2 and M4 games ran (%d)" % ran)


func test_fog_off_nothing_of_fog_runs() -> void:
	var s := GameState.with_rulers(12)
	assert_true(AIFog.top_view(s) == null, "no top of a sighting without a view")
	assert_eq(AIFog.trusted_view(s), s, "and no ghost to drop: the state itself comes back")
	assert_false(AIFog.is_view(s))
	var p := _plan(s, CROWN, 12)
	assert_eq(int(p.stats.get("scouts", 0)), 0)
	assert_false(_said(p).contains("Scouting"))
	# A fog state that is not a view (the truth) is not touched either.
	var fogged := _fog_state([["kingdom-1", CROWN, "crownkeep", ["spearmen"]], ["beasts-1", CLANS, "fangridge", ["tuskers"]]])
	assert_false(AIFog.is_view(fogged))
	assert_eq(AIFog.trusted_view(fogged), fogged)


# --- stale ghosts (§10.1) -------------------------------------------------------------------------------

## A Crown view `age` turns after a scout at Westwatch last saw a Clans army at Blackwood (three moves from Crownkeep, out of
## sight from home). {"view", "truth"}.
func _ghost(age: int, seen: int = 2) -> Dictionary:
	var specs := [["kingdom-1", CROWN, "crownkeep", ["spearmen", "spearmen"]], ["kingdom-2", CROWN, "westwatch", ["knights", "knights"]],
		["beasts-1", CLANS, "blackwood", _many("tuskers", 12) + _many("war_bear", 3)], ["beasts-2", CLANS, "fangridge", ["warchief", "tuskers"]]]
	var then := _fog_state(specs, {}, seen)
	var memory := FogRules.new_memory(then, CROWN)
	var now: GameState = then.deep_copy()
	now.find_army("kingdom-2").location = "crownkeep"
	now.current_turn = seen + age
	return {"view": _view(now, CROWN, memory), "truth": now, "plain": _view(now), "memory": memory}


func test_ghosts_older_than_three_turns_are_dropped_once_before_the_plan() -> void:
	assert_eq(AIFog.MEMORY_TRUST, 3)
	for age in range(0, 7):
		var g := _ghost(age)
		var view: GameState = g.view
		var ghost := view.find_army("seen-beasts-blackwood")
		assert_true(ghost != null, "age %d: the view remembers the army at Blackwood" % age)
		assert_eq(String(ghost.seen.level), "memory")
		assert_eq(AIFog.ghost_age(view, ghost), age)
		var before := JSON.stringify(view.to_dict())
		var trusted := AIFog.trusted_view(view)
		assert_eq(JSON.stringify(view.to_dict()), before, "age %d: the view it was given is not changed" % age)
		if age <= AIFog.MEMORY_TRUST:
			assert_eq(trusted, view, "age %d: a ghost this fresh stays, and the view itself comes back" % age)
			assert_true(trusted.find_army("seen-beasts-blackwood") != null)
		else:
			assert_true(trusted.find_army("seen-beasts-blackwood") == null, "age %d: an old ghost is dropped" % age)
			assert_true(trusted.find_army("kingdom-1") != null, "...and our own armies are not")
			assert_true(trusted.validate([]), "the view without it is still a valid view")
		# The plan: a fresh ghost is a threat three moves away; an old one is forgotten, as if never seen.
		var plan := _plan(view, CROWN)
		var never := _plan(g.plain, CROWN)
		if age <= AIFog.MEMORY_TRUST:
			assert_true(_said(plan).contains("Blackwood") and _said(plan).contains("three moves away"), "age %d: it keeps the garrison for the ghost: %s" % [age, _said(plan)])
			assert_ne(plan.json, never.json, "age %d: the ghost changes the plan" % age)
		else:
			assert_false(_said(plan).contains("Blackwood"), "age %d: the old ghost does not: %s" % [age, _said(plan)])
			assert_eq(plan.json, never.json, "age %d: the plan is the plan of a board never seen at Blackwood" % age)


# --- the top of each sighting (§10.1) -------------------------------------------------------------

## A Crown view of a Clans army of `n` Tuskers at Westwatch (next to its capital: glimpsed), and the truth.
func _glimpse_view(n: int, extra: Array = []) -> Dictionary:
	var specs := [["kingdom-1", CROWN, "crownkeep", ["knight_captain", "spearmen", "spearmen"]], ["beasts-1", CLANS, "westwatch", _many("tuskers", n)],
		["beasts-2", CLANS, "fangridge", ["warchief"]]] + extra
	var truth := _fog_state(specs)
	return {"truth": truth, "view": _view(truth)}


func test_the_top_of_a_sighting_comes_from_the_view_note() -> void:
	for n in [3, 7, 13, 14, 22, 48, 53, 64]:
		var g := _glimpse_view(n)
		var view: GameState = g.view
		var a := view.find_army("seen-beasts-westwatch")
		assert_eq(String(a.seen.level), FogRules.GLIMPSE, "%d: glimpsed" % n)
		var total: Dictionary = a.seen.total
		var top := AIFog.top_view(view)
		var want := int(total.high)
		if want == a.units.size():
			assert_true(top == null, "%d: already at the top of its range" % n)
			continue
		assert_true(top != null, "%d: the sighting has fighters above its shown number" % n)
		var grown := top.find_army("seen-beasts-westwatch")
		assert_eq(grown.units.size(), want, "%d: the top of its total (shown %d, top %d)" % [n, total.shown, total.high])
		for u in grown.units:
			assert_eq(u.current_hp, RulerRules.unit_max_hp(top, u), "%d: the added fighters are whole" % n)
		assert_true(top.validate([]), "%d: the top of the view is a valid view" % n)
		assert_eq(JSON.stringify(view.find_army("seen-beasts-westwatch").to_dict()), JSON.stringify(a.to_dict()), "the view is not changed")
		assert_true(int(total.low) <= n and n <= int(total.high), "%d is inside the sighting's range" % n)
		# Our own armies, the ruler and the commander are exact: nothing is added to them.
		assert_eq(top.find_army("kingdom-1").units.size(), view.find_army("kingdom-1").units.size())
		assert_eq(top.find_army("seen-beasts-fangridge") == null, view.find_army("seen-beasts-fangridge") == null)


func test_clear_sight_has_no_range_to_climb() -> void:
	var g := _glimpse_view(20)
	var truth: GameState = g.truth
	truth.find_army("kingdom-1").location = "westwatch"  # the Crown now stands with the army: it sees it exactly
	var view := _view(truth)
	assert_eq(String(view.find_army("seen-beasts-westwatch").seen.level), FogRules.CLEAR)
	assert_true(AIFog.top_view(view) == null)


## `view` with every sighting's range closed to its shown number (a board seen exactly as shown).
func _closed(view: GameState) -> GameState:
	var d := view.to_dict()
	for ad in d.armies:
		for key in ad.get("seen", {}).get("counts", {}):
			ad.seen.counts[key].low = ad.seen.counts[key].shown
			ad.seen.counts[key].high = ad.seen.counts[key].shown
		if ad.has("seen"):
			ad.seen.total.low = ad.seen.total.shown
			ad.seen.total.high = ad.seen.total.shown
	var out := GameState.from_dict(d, [])
	assert_true(out != null)
	return out


func _at_the_capital(plan: Dictionary, armies: Array) -> int:
	var n := 0
	for id in armies:
		if String(plan.moves.get(id, "crownkeep" if id == "kingdom-1" else "")) == "crownkeep":
			n += 1
	return n


func test_the_capital_is_guarded_against_the_top_and_attacks_are_judged_on_the_shown_numbers() -> void:
	# Capital: a garrison of `n` Spearmen, and two armies next door that can be recalled, against a glimpsed army (shown 15,
	# top 17) at Westwatch. Counting the top can only bring more armies home, never fewer, than the same board seen exactly
	# as shown; and for some garrison it does.
	var armies := ["kingdom-1", "kingdom-2", "kingdom-3"]
	var firmer := 0
	for n in range(2, 31, 2):
		var specs := [["kingdom-1", CROWN, "crownkeep", _many("spearmen", n)], ["kingdom-2", CROWN, "highcrag", _many("spearmen", 6)],
			["kingdom-3", CROWN, "rivermarch", _many("spearmen", 6)], ["beasts-1", CLANS, "westwatch", _many("tuskers", 15)],
			["beasts-2", CLANS, "fangridge", ["warchief"]]]
		var view := _view(_fog_state(specs))
		var note: Dictionary = view.find_army("seen-beasts-westwatch").seen
		assert_true(int(note.total.high) > int(note.total.shown), "a range to climb: shown %d, top %d" % [note.total.shown, note.total.high])
		var ranged := _plan(view, CROWN)
		var exact := _plan(_closed(view), CROWN)
		var home_ranged := _at_the_capital(ranged, armies)
		var home_exact := _at_the_capital(exact, armies)
		assert_true(home_ranged >= home_exact, "n=%d: counting the top never keeps fewer armies at the capital (%d against %d: %s, %s)" % [n, home_ranged, home_exact, ranged.moves, exact.moves])
		if home_ranged > home_exact:
			firmer += 1
	assert_true(firmer > 0, "and for some garrison the top brings more armies home (%d sizes of 15)" % firmer)
	# Attacks: our army next to the glimpsed one, far from our capital: the shown number decides, not the top. The plan on
	# the ranged view is the plan on the one closed to its shown number, whether it attacks or not.
	var attacks := 0
	var holds := 0
	for n in range(20, 60, 5):
		var specs := [["kingdom-1", CROWN, "crownkeep", ["spearmen"]], ["kingdom-2", CROWN, "wildmoor", _many("spearmen", n) + ["knight_captain"]],
			["beasts-1", CLANS, "ironspike", _many("tuskers", 15)], ["beasts-2", CLANS, "fangridge", ["warchief"]]]
		var view := _view(_fog_state(specs, {"wildmoor": CROWN, "thornvale": CROWN, "highcrag": CROWN}))
		var note: Dictionary = view.find_army("seen-beasts-ironspike").seen
		assert_true(int(note.total.high) > int(note.total.shown))
		var ranged := _plan(view, CROWN)
		var exact := _plan(_closed(view), CROWN)
		assert_eq(ranged.json, exact.json, "n=%d: the plan is the same, so the attack is judged on the shown numbers" % n)
		if ranged.moves.get("kingdom-2", "") == "ironspike":
			attacks += 1
		else:
			holds += 1
	assert_true(attacks > 0 and holds > 0, "it attacks when it is strong enough (%d) and not before (%d)" % [attacks, holds])


# --- scouting (§10.1) -------------------------------------------------------------------------------

func _scout_state(extra: Array = [], scout_at: String = "westwatch", scout_units: Array = ["knights", "knights"]) -> GameState:
	var specs := [["kingdom-1", CROWN, "crownkeep", ["spearmen", "spearmen", "crossbowmen"]], ["kingdom-2", CROWN, scout_at, scout_units],
		["beasts-1", CLANS, "fangridge", ["warchief", "tuskers", "tuskers"]]] + extra
	return _fog_state(specs, {"westwatch": CROWN})


func test_a_free_scout_army_looks_toward_an_objective_it_cannot_see() -> void:
	var s := _scout_state()
	assert_eq(String(FogRules.sight(s, CROWN).fangridge), FogRules.VEILED, "the enemy capital is out of sight")
	var p := _plan(_view(s), CROWN)
	assert_eq(p.moves.get("kingdom-2", ""), "stonegate", "the Knights take one step along the road to Fangridge: %s" % p.moves)
	assert_eq(int(p.stats.get("scouts", 0)), 1)
	var said: Array = p.notes.filter(func(n): return n.begins_with("Scouting"))
	assert_eq(said.size(), 1, "one plain note says it: %s" % str(p.notes))
	for part in ["Crown", "2 units", "Stonegate", "Fangridge", "out of our sight"]:
		assert_true(said[0].contains(part), "the note names '%s': %s" % [part, said[0]])
	for id in ["kingdom-2", "stonegate", "fangridge", "seen-"]:
		assert_false(said[0].contains(id), "no id in the note: %s" % said[0])
	_assert_legal(s, CROWN, p.orders, "scouting")
	# The same board on the truth (no view) has no scouting at all.
	assert_eq(int(_plan(s, CROWN).stats.get("scouts", 0)), 0)


func test_scouting_takes_the_nearest_scout_army_and_one_step() -> void:
	var s := _scout_state([["kingdom-3", CROWN, "stonegate", ["knights"]]])
	var p := _plan(_view(s), CROWN)
	assert_eq(int(p.stats.get("scouts", 0)), 1, "one army scouts a turn: %s" % p.moves)
	assert_eq(p.moves.get("kingdom-3", ""), "blackwood", "the one nearest the objective: %s" % p.moves)
	assert_eq(p.notes.filter(func(n): return n.begins_with("Scouting")).size(), 1)


func test_a_fighting_army_is_not_a_scout() -> void:
	for units in [["knights", "spearmen"], ["knights", "knight_captain"]]:
		var p := _plan(_view(_scout_state([], "westwatch", units)), CROWN)
		assert_eq(int(p.stats.get("scouts", 0)), 0, "%s is no scout army" % str(units))
	assert_true(AIFog.is_scout_army(_view(_scout_state()).find_army("kingdom-2")))
	assert_false(AIFog.is_scout_army(_view(_scout_state()).find_army("kingdom-1")))


func test_no_scouting_once_the_objective_is_in_sight() -> void:
	# A scout at Blackwood sees two provinces: Fangridge is glimpsed, so there is nothing to look for.
	var s := _scout_state([], "blackwood")
	assert_eq(String(FogRules.sight(s, CROWN).fangridge), FogRules.GLIMPSE)
	var p := _plan(_view(s), CROWN)
	assert_eq(int(p.stats.get("scouts", 0)), 0)
	assert_false(_said(p).contains("Scouting"))


func test_a_scout_does_not_step_where_the_odds_say_no() -> void:
	# A big Clans army at Blackwood (glimpsed from Westwatch) stands next to Stonegate: the step is not safe.
	var s := _scout_state([["beasts-2", CLANS, "blackwood", _many("tuskers", 20) + _many("war_bear", 6)]])
	assert_eq(String(FogRules.sight(s, CROWN).blackwood), FogRules.GLIMPSE)
	var p := _plan(_view(s), CROWN)
	assert_eq(int(p.stats.get("scouts", 0)), 0, "no scouting into danger: %s" % p.moves)
	assert_ne(p.moves.get("kingdom-2", ""), "stonegate")
	# And not onto an army it can see.
	var blocked := _scout_state([["beasts-2", CLANS, "stonegate", ["tuskers"]]])
	var q := _plan(_view(blocked), CROWN)
	assert_eq(int(q.stats.get("scouts", 0)), 0, "and no scouting onto an army it can see (it attacks it or leaves it): %s" % _said(q))


func test_the_main_army_and_the_capital_come_first() -> void:
	# A scout that the capital needs (it is short of defenders, a Clans army next door) stays: the recall comes before scouting.
	var s := _scout_state([["beasts-2", CLANS, "highcrag", _many("tuskers", 14) + _many("war_bear", 4)]], "rivermarch")
	var p := _plan(_view(s), CROWN)
	assert_eq(int(p.stats.get("scouts", 0)), 0, "the capital's defence comes first: %s %s" % [p.moves, _said(p)])


func test_scouting_reaches_the_enemy_capital_and_then_stops() -> void:
	# Follow the Knights a few turns on a board where nothing moves but them: one step a turn, until Fangridge is glimpsed.
	var s := _scout_state()
	var steps := []
	for turn in 8:
		var view := _view(s)
		var p := _plan(view, CROWN)
		var to: String = p.moves.get("kingdom-2", "")
		if int(p.stats.get("scouts", 0)) == 0:
			break
		steps.append(to)
		s.find_army("kingdom-2").location = to
	assert_eq(steps, ["stonegate", "blackwood"], "two steps to see Fangridge from two provinces off: %s" % str(steps))
	assert_eq(String(FogRules.sight(s, CROWN).fangridge), FogRules.GLIMPSE)


# --- #94 under fog (§10.1) ----------------------------------------------------------------------------

const WEST := ["crownkeep", "westwatch", "highcrag", "rivermarch", "greenglade", "stonegate", "thornvale"]
const EAST := ["fangridge", "ebonpeak", "ironspike", "bloodfen", "deepwood", "wildmoor", "blackwood"]


## The stand-off position of tests/test_ai_standoff.gd (the pile at Crownkeep, the Clans' small army at Deepwood, their
## main army at home) as a fog game.
func _standoff_state() -> GameState:
	var owners := {}
	for p in WEST:
		owners[p] = CROWN
	for p in EAST:
		owners[p] = CLANS
	var s := _fog_state([
		["kingdom-1", CROWN, "crownkeep", ["knight_captain"]],
		["kingdom-2", CROWN, "greenglade", ["knights", "spearmen", "crossbowmen"]],
		["beasts-1", CLANS, "deepwood", _many("tuskers", 4) + _many("war_bear", 2)],
		["beasts-2", CLANS, "fangridge", _many("tuskers", 12) + _many("war_bear", 6) + ["warchief"]],
	], owners)
	for f in s.factions:
		f.gold = 0
	# Fill the Crown's pile (kingdom-1) to just short of a stand-off, then give the gold that reaches it.
	var a := s.find_army("kingdom-1")
	var crown := s.find_faction(CROWN)
	var income := int(TurnResolver.income_of(s, CROWN).total)
	var target := ceili(AIPlayer.STANDOFF_TURNS * income) - 2
	var types: Array = crown.unit_types.duplicate()
	types.sort_custom(func(x, y): return RulerRules.recruit_price(s, CROWN, x) > RulerRules.recruit_price(s, CROWN, y))
	var value := func() -> int:
		var total := 0
		for army in s.armies:
			if army.owner != CROWN:
				continue
			for u in army.units:
				total += RulerRules.recruit_price(s, CROWN, u.type)
			if army.commander != null:
				total += RulerRules.recruit_price(s, CROWN, army.commander.type)
		return total
	for ut in types:
		var price := RulerRules.recruit_price(s, CROWN, ut)
		while int(value.call()) + price <= target:
			a.units.append(Unit.new(ut, CROWN))
	crown.gold = ceili(AIPlayer.STANDOFF_TURNS * income) - int(value.call())
	return s


func test_the_standoff_rule_reads_only_the_view() -> void:
	var s := _standoff_state()
	assert_false(AIPlayer.standoff_info(s, CROWN).is_empty(), "the Crown's pile has reached a stand-off")
	var view := _view(s)
	assert_false(AIPlayer.standoff_info(view, CROWN).is_empty(), "and the view of it says so too: it reads only our own side")
	assert_eq(AIPlayer.standoff_info(view, CROWN), AIPlayer.standoff_info(s, CROWN), "the same pile, income and units")
	assert_eq(String(FogRules.sight(s, CROWN).deepwood), FogRules.GLIMPSE, "the army it hunts is glimpsed")
	var truth_plan := _plan(s, CROWN)
	var plan := _plan(view, CROWN)
	assert_eq(int(plan.stats.get("standoff", 0)), 1)
	assert_eq(int(plan.stats.get("hunts", 0)), 1, "it hunts the army that keeps the garrison home: %s" % _said(plan))
	assert_eq(plan.moves.get("kingdom-1", ""), truth_plan.moves.get("kingdom-1", "x"), "the garrison marches out as it does on the truth")
	assert_eq(plan.moves.get("kingdom-1", ""), "rivermarch")
	var said: Array = plan.notes.filter(func(n): return n.contains("stand-off"))
	assert_eq(said.size(), 1, str(plan.notes))
	assert_true(said[0].contains("Crownkeep") and said[0].contains("Deepwood"), said[0])
	assert_false(said[0].contains("seen-"), "it names no view id: %s" % said[0])
	_assert_legal(s, CROWN, plan.orders, "the hunt")
	# Changing what is hidden from the Crown changes nothing: the Clans' main army at home, their gold, a mandate.
	for k in 4:
		var p := Kit.perturb_hidden(s, CROWN, 900 + k)
		assert_eq(p.errors, [])
		var again := _plan(_view(p.state), CROWN)
		assert_eq(again.json, plan.json, "perturbation %d: the stand-off plan is the same" % k)


func test_the_standoff_hunts_no_army_it_cannot_see() -> void:
	# The army it would hunt has left Deepwood for a province out of the Crown's sight: there is nothing to hunt, and the
	# stand-off falls back to a siege or a raid; it does not march on the army that is no longer there.
	var s := _standoff_state()
	s.find_army("beasts-1").location = "ironspike"
	assert_eq(String(FogRules.sight(s, CROWN).ironspike), FogRules.VEILED)
	var plan := _plan(_view(s), CROWN)
	assert_eq(int(plan.stats.get("hunts", 0)), 0, "no hunt: %s" % _said(plan))
	assert_false(_said(plan).contains("Breaking the stand-off"), "and it does not say it hunts: %s" % _said(plan))


# --- the explanation (approachability) ------------------------------------------------------------------

func test_the_codex_says_how_the_computer_plays_under_fog() -> void:
	var text := RulesCodex.text("computer_opponent")
	for part in ["fog of war", "its own view", "never sees an army you could not see", "top of each estimate", "%d turns" % AIFog.MEMORY_TRUST, "scout"]:
		assert_true(text.contains(part), "the entry says '%s': %s" % [part, text])
	for part in ["same rules", "same map", "never sees the orders you give", "Easy", "Normal"]:
		assert_true(text.contains(part), "and still '%s'" % part)
	assert_false(text.contains("[") or text.contains("_"), "plain text, so tooltips can quote it")
