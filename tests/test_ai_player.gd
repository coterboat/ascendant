extends "res://tests/test_case.gd"
## Tests for the computer opponent (ai/ai_player.gd): valid and deterministic orders, capital defense,
## attack choices, plain-language notes, and a whole game against the random policy. Games here use
## short turn caps so the file runs in a couple of seconds.

const Simulator := preload("res://tools/autoplay/simulator.gd")
const Policies := preload("res://tools/autoplay/policies.gd")
const SEATS := ["kingdom", "beasts"]


# --- fixtures -------------------------------------------------------------------------------------

## A fresh state with the starting armies replaced by `specs`: [[id, owner, location, [unit ids]], ...].
func _state(specs: Array) -> GameState:
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
	return s


## The state after `turns` turns of the AI (Aurel Crown) against `opponent` on `game_seed`.
func _midgame(game_seed: int, opponent: String, turns: int) -> GameState:
	var r := Simulator.play_game(game_seed, SEATS, ["ai", opponent], turns)
	return GameState.from_dict(r.final_state)


func _moves(orders: Array) -> Dictionary:
	var out := {}
	for o in orders:
		if o is MoveOrder:
			out[o.army_id] = o.to
	return out


func _dicts(orders: Array) -> Array:
	return orders.map(func(o): return o.to_dict())


## Every order passes the same checks GameSession's OrderBook runs, in order.
func _assert_valid(s: GameState, fid: String, orders: Array, where: String) -> void:
	var book := OrderBook.new()
	for o in orders:
		assert_true(o is MoveOrder or o is RecruitOrder, "%s: only moves and recruits" % where)
		assert_eq(book.submit(s, fid, o), "", "%s: %s is accepted" % [where, o.describe()])


## Every id in the state (armies, provinces, factions, unit types): none may appear in a note.
func _ids(s: GameState) -> Array:
	var out := []
	for a in s.armies:
		out.append(a.id)
	for p in s.provinces:
		out.append(p.id)
	for f in s.factions:
		out.append(f.id)
		for ut in f.unit_types:
			out.append(ut.id)
		if f.commander_type:
			out.append(f.commander_type.id)
	return out


# --- orders are valid and deterministic -----------------------------------------------------------

func test_only_valid_orders_are_returned() -> void:
	var states := [GameState.new(1), _midgame(3, "random", 6), _midgame(4, "greedy", 4), _midgame(5, "turtle", 8)]
	for i in states.size():
		var s: GameState = states[i]
		for fid in SEATS:
			for level in AIPlayer.DIFFICULTIES:
				var ai := AIPlayer.new()
				var orders: Array = ai.plan_orders(s, fid, SeededRNG.new(10 + i), level)
				_assert_valid(s, fid, orders, "state %d, %s, %s" % [i, fid, level])
				assert_eq(int(ai.last_plan_stats().get("dropped_invalid", -1)), 0, "nothing had to be dropped")
	var start := GameState.new(1)
	assert_false(_dicts(AIPlayer.new().plan_orders(start, "kingdom", SeededRNG.new(1))).is_empty(),
		"the first turn has orders: an expansion move and recruits")


func test_the_state_is_never_changed() -> void:
	var s := _midgame(3, "random", 6)
	var before := JSON.stringify(s.to_dict())
	AIPlayer.new().plan_orders(s, "kingdom", SeededRNG.new(2))
	AIPlayer.new().plan_orders(s, "beasts", SeededRNG.new(2))
	assert_eq(JSON.stringify(s.to_dict()), before)


func test_same_seed_gives_same_orders() -> void:
	for s in [GameState.new(1), _midgame(6, "greedy", 5)]:
		for fid in SEATS:
			for level in AIPlayer.DIFFICULTIES:
				var a: Array = _dicts(AIPlayer.new().plan_orders(s, fid, SeededRNG.new(42), level))
				var b: Array = _dicts(AIPlayer.new().plan_orders(s, fid, SeededRNG.new(42), level))
				assert_eq(a, b, "%s %s" % [fid, level])
	# The same AIPlayer gives the same plan again too (nothing carries over between plans).
	var ai := AIPlayer.new()
	var s2 := _midgame(7, "random", 5)
	var first: Array = _dicts(ai.plan_orders(s2, "kingdom", SeededRNG.new(9)))
	var notes: Array = ai.last_plan_notes()
	assert_eq(_dicts(ai.plan_orders(s2, "kingdom", SeededRNG.new(9))), first)
	assert_eq(ai.last_plan_notes(), notes)


func test_unknown_faction_or_difficulty_is_safe() -> void:
	var s := GameState.new(1)
	assert_eq(AIPlayer.new().plan_orders(s, "pirates", SeededRNG.new(1)), [])
	var odd: Array = _dicts(AIPlayer.new().plan_orders(s, "kingdom", SeededRNG.new(1), "nightmare"))
	assert_eq(odd, _dicts(AIPlayer.new().plan_orders(s, "kingdom", SeededRNG.new(1), "normal")), "unknown levels play as normal")


# --- the capital ----------------------------------------------------------------------------------

func test_defends_the_capital_when_an_enemy_is_adjacent_and_the_capital_is_empty() -> void:
	var s := _state([
		["kingdom-1", "kingdom", "highcrag", ["knights", "knights", "crossbowmen", "knight_captain"]],
		["beasts-1", "beasts", "westwatch", ["tuskers", "tuskers"]],
		["beasts-2", "beasts", "fangridge", ["war_bear"]],
	])
	var ai := AIPlayer.new()
	var moves := _moves(ai.plan_orders(s, "kingdom", SeededRNG.new(1)))
	assert_eq(moves.get("kingdom-1", ""), "crownkeep", "the only army comes home: %s" % moves)
	assert_true(" ".join(ai.last_plan_notes()).contains("Crownkeep"), str(ai.last_plan_notes()))


func test_holds_the_capital_instead_of_marching_out() -> void:
	var s := _state([
		["kingdom-1", "kingdom", "crownkeep", ["knights", "knights", "crossbowmen"]],
		["beasts-1", "beasts", "highcrag", ["war_bear", "tuskers", "warchief"]],
		["beasts-2", "beasts", "fangridge", ["war_bear"]],
	])
	var ai := AIPlayer.new()
	var moves := _moves(ai.plan_orders(s, "kingdom", SeededRNG.new(1)))
	assert_false(moves.has("kingdom-1"), "the garrison stays home: %s" % moves)
	var notes := " ".join(ai.last_plan_notes())
	assert_true(notes.contains("Holding Crownkeep") and notes.contains("Highcrag") and notes.contains("odds as defender"), notes)


func test_never_leaves_the_capital_open_to_an_adjacent_enemy() -> void:
	# Two enemy armies next to the capital from different sides: no sally, the garrison holds, even
	# with a weak enemy army it could beat somewhere else.
	var s := _state([
		["kingdom-1", "kingdom", "crownkeep", ["knights", "knights", "knights", "knight_captain"]],
		["beasts-1", "beasts", "westwatch", ["tuskers"]],
		["beasts-2", "beasts", "rivermarch", ["fangthrowers"]],
		["beasts-3", "beasts", "fangridge", ["war_bear"]],
	])
	var moves := _moves(AIPlayer.new().plan_orders(s, "kingdom", SeededRNG.new(1)))
	assert_false(moves.has("kingdom-1"), "the capital is held: %s" % moves)
	# And over real games: whenever an enemy army stands next to the capital, an army stays in or
	# comes back to it, or the whole garrison sallies against the one province those enemies are in
	# (they then have to fight it on the border to get in).
	var checked := 0
	for spec in [[2, "greedy"], [5, "greedy"], [8, "random"]]:
		var session := GameSession.new(GameState.new(spec[0]), SEATS, spec[0], AutoBattleResolver.new())
		var them = Policies.make(spec[1])
		var their_rng := SeededRNG.new(spec[0])
		var ai := AIPlayer.new()
		while not session.is_over() and session.turns_played() < 12:
			var view := session.state()
			var orders: Array = ai.plan_orders(view, "kingdom", SeededRNG.new(session.turns_played()))
			checked += _check_capital_cover(view, orders, "seed %d turn %d" % [spec[0], session.turn_number()])
			for o in orders:
				session.queue_order(o)
			session.end_turn()
			session.acknowledge_handoff()
			for o in them.orders(session.state(), "beasts", their_rng):
				session.queue_order(o)
			session.end_turn()
			if session.phase() == GameSession.Phase.HANDOFF:
				session.acknowledge_handoff()
	assert_true(checked > 0, "the games put an enemy army next to the capital at least once")


## Checks the capital rule for one plan. Returns 1 when the situation came up, else 0.
func _check_capital_cover(s: GameState, orders: Array, where: String) -> int:
	var cap := s.find_province("crownkeep")
	if cap.owner != "kingdom":
		return 0
	var adjacent := []
	var reachable := false
	for a in s.armies:
		if a.owner != "kingdom" and cap.neighbors.has(a.location):
			adjacent.append(a)
		if a.owner == "kingdom" and (a.location == cap.id or cap.neighbors.has(a.location)):
			reachable = true
	if adjacent.is_empty() or not reachable:
		return 0
	var moves := _moves(orders)
	var home := []
	var ends_home := false
	for a in s.armies:
		if a.owner != "kingdom":
			continue
		var dest: String = moves.get(a.id, a.location)
		if dest == cap.id:
			ends_home = true
		if a.location == cap.id:
			home.append(a)
	if ends_home:
		return 1
	var places := {}
	for e in adjacent:
		places[e.location] = true
	assert_eq(places.size(), 1, "%s: a sally only ever goes against one province" % where)
	assert_false(home.is_empty(), "%s: the capital is covered" % where)
	for a in home:
		assert_true(places.has(moves.get(a.id, "")), "%s: the whole garrison sallies at the enemy next door" % where)
	return 1


# --- battles --------------------------------------------------------------------------------------

func test_attacks_an_adjacent_clearly_weaker_enemy_army() -> void:
	var s := _state([
		["kingdom-1", "kingdom", "stonegate", ["knights", "knights", "knights", "knight_captain"]],
		["kingdom-2", "kingdom", "crownkeep", ["knights", "knights"]],
		["beasts-1", "beasts", "blackwood", ["fangthrowers"]],
		["beasts-2", "beasts", "fangridge", ["war_bear", "tuskers"]],
	])
	var ai := AIPlayer.new()
	var moves := _moves(ai.plan_orders(s, "kingdom", SeededRNG.new(1)))
	assert_eq(moves.get("kingdom-1", ""), "blackwood", "attacks the lone Fangthrowers: %s" % moves)
	assert_true(" ".join(ai.last_plan_notes()).contains("Attacking the enemy at Blackwood"), str(ai.last_plan_notes()))


func test_does_not_attack_at_likely_loss_odds() -> void:
	var s := _state([
		["kingdom-1", "kingdom", "stonegate", ["spearmen", "crossbowmen"]],
		["kingdom-2", "kingdom", "crownkeep", ["knights", "knights"]],
		["beasts-1", "beasts", "blackwood", ["war_bear", "war_bear", "warchief"]],
		["beasts-2", "beasts", "fangridge", ["war_bear"]],
	])
	var odds := Forecast.battle_odds(s, "kingdom", ["kingdom-1"], "blackwood")
	assert_eq(odds.label, "likely loss", "the setup really is a likely loss")
	for level in AIPlayer.DIFFICULTIES:
		var moves := _moves(AIPlayer.new().plan_orders(s, "kingdom", SeededRNG.new(1), level))
		assert_ne(moves.get("kingdom-1", ""), "blackwood", "%s: no attack into Blackwood: %s" % [level, moves])


func test_walks_into_an_undefended_enemy_capital() -> void:
	var s := _state([
		["kingdom-1", "kingdom", "crownkeep", ["knights", "knights"]],
		["kingdom-2", "kingdom", "ebonpeak", ["knights", "crossbowmen", "knight_captain"]],
		["beasts-1", "beasts", "rivermarch", ["tuskers"]],
	])
	var ai := AIPlayer.new()
	var moves := _moves(ai.plan_orders(s, "kingdom", SeededRNG.new(1)))
	assert_eq(moves.get("kingdom-2", ""), "fangridge", "takes the empty enemy capital: %s" % moves)
	assert_true(" ".join(ai.last_plan_notes()).contains("wins the game"), str(ai.last_plan_notes()))


# --- notes ----------------------------------------------------------------------------------------

func test_last_plan_notes_have_no_raw_ids() -> void:
	var states := [GameState.new(1), _midgame(3, "random", 6), _midgame(4, "greedy", 5), _midgame(9, "turtle", 10),
		_state([["kingdom-1", "kingdom", "highcrag", ["knights"]], ["beasts-1", "beasts", "westwatch", ["tuskers"]],
			["beasts-2", "beasts", "fangridge", ["war_bear"]]])]
	var seen := 0
	for s in states:
		var ids := _ids(s)
		for fid in SEATS:
			for level in AIPlayer.DIFFICULTIES:
				var ai := AIPlayer.new()
				ai.plan_orders(s, fid, SeededRNG.new(5), level)
				for note in ai.last_plan_notes():
					seen += 1
					assert_true(note is String and not note.is_empty(), "a note is a sentence")
					for id in ids:
						assert_false(note.contains(id), "note names '%s' by id: %s" % [id, note])
	assert_true(seen > 10, "plans explain themselves (%d notes)" % seen)


# --- whole games ----------------------------------------------------------------------------------

func test_a_short_ai_vs_random_game_is_won_by_the_ai() -> void:
	var r := Simulator.play_game(1, SEATS, ["ai", "random"], 30)
	assert_eq(r.errors, [])
	assert_eq(r.violations, [])
	assert_eq(r.rejections, {}, "GameSession accepted every AI order")
	assert_true(r.finished, "the game ends before the cap (%d turns)" % r.turns)
	assert_eq(r.winner, "kingdom", "the AI wins")
