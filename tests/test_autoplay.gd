extends "res://tests/test_case.gd"
## Tests for the headless autoplay simulator (tools/autoplay/): policies, the game loop, the invariant
## checks and the summary. Games here use short turn caps so the whole file runs in a few seconds.

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


func _moves(orders: Array) -> Dictionary:
	var out := {}
	for o in orders:
		if o is MoveOrder:
			out[o.army_id] = o.to
	return out


func _checks(found: Array) -> Array:
	return found.map(func(v): return v.check)


# --- whole games ----------------------------------------------------------------------------------

func test_greedy_games_finish_or_hit_the_cap_without_violations() -> void:
	for game_seed in [1, 2, 3]:
		var r := Simulator.play_game(game_seed, SEATS, ["greedy", "greedy"], 30)
		var where := "seed %d" % game_seed
		assert_eq(r.errors, [], where)
		assert_eq(r.violations, [], where)
		assert_true(r.turns >= 1, where)
		assert_true(r.finished or r.turns == 30, "%s finishes or hits the cap" % where)
		if r.finished:
			assert_true(r.draw or SEATS.has(r.winner), "%s has a winner or is a draw" % where)
			assert_eq(r.winner_seat, SEATS.find(r.winner) + 1, where)
		assert_false(r.battles.is_empty(), "%s: the armies meet at least once" % where)


func test_same_seed_gives_the_same_game() -> void:
	for policies in [["greedy", "greedy"], ["greedy", "random"]]:
		var a := Simulator.play_game(5, SEATS, policies, 25)
		var b := Simulator.play_game(5, SEATS, policies, 25)
		assert_eq(a.winner, b.winner, str(policies))
		assert_eq(a.draw, b.draw, str(policies))
		assert_eq(a.turns, b.turns, str(policies))
		assert_eq(a.battles, b.battles, str(policies))
		assert_eq(a.final_state, b.final_state, "%s final state" % str(policies))


func test_different_seeds_give_different_games() -> void:
	var states := {}
	for game_seed in [1, 2, 3, 4]:
		states[JSON.stringify(Simulator.play_game(game_seed, SEATS, ["random", "random"], 8).final_state)] = true
	assert_true(states.size() > 1, "the seed changes the game")


func test_policies_issue_no_rejected_orders() -> void:
	for policies in [["greedy", "greedy"], ["random", "random"], ["turtle", "greedy"], ["greedy", "turtle"]]:
		var r := Simulator.play_game(11, SEATS, policies, 12)
		assert_true(r.orders > 0, "%s queued orders" % str(policies))
		assert_eq(r.rejections, {}, "%s: GameSession accepted every order" % str(policies))
		assert_eq(r.errors, [], str(policies))
		assert_eq(r.violations, [], str(policies))


func test_seats_can_be_swapped() -> void:
	var r := Simulator.play_game(3, ["beasts", "kingdom"], ["greedy", "greedy"], 20)
	assert_eq(r.errors, [])
	assert_eq(r.violations, [])
	if r.finished and not r.draw:
		assert_eq(r.winner_seat, ["beasts", "kingdom"].find(r.winner) + 1)


func test_unknown_policy_is_an_error_not_a_crash() -> void:
	var r := Simulator.play_game(1, SEATS, ["greedy", "nonsense"], 5)
	assert_eq(r.turns, 0)
	assert_eq(r.errors.size(), 1)
	assert_true(str(r.errors[0].detail).contains("nonsense"))


# --- summary --------------------------------------------------------------------------------------

func test_summary_has_the_expected_keys() -> void:
	var results := Simulator.run_batch(3, 1, SEATS, ["greedy", "random"], 10)
	var s := Simulator.summarize(results)
	for key in Simulator.SUMMARY_KEYS:
		assert_true(s.has(key), "summary has %s" % key)
	assert_eq(s.games, 3)
	assert_eq(s.seeds, [1, 3])
	assert_eq(s.turn_cap, 10)
	assert_eq(s.finished + s.unfinished, 3)
	var wins := 0
	for fid in s.wins_by_faction:
		wins += s.wins_by_faction[fid]
	assert_eq(wins + s.draws + s.unfinished, 3, "every game is a win, a draw or unfinished")
	for key in ["min", "median", "mean", "max"]:
		assert_true(s.length_all.has(key), "length has %s" % key)
	for key in ["total", "per_game", "avg_rounds", "ends", "kinds"]:
		assert_true(s.battles.has(key), "battles has %s" % key)
	for end in Simulator.BATTLE_ENDS:
		assert_true(s.battles.ends.has(end), "battle ends count %s" % end)
	assert_eq(s.violations.count, 0)
	assert_eq(s.script_errors.count, 0)
	var md := Simulator.to_markdown(s)
	assert_true(md.contains("3 games"), md)
	assert_true(md.contains("How battles ended"), md)
	assert_true(Simulator.game_lines(results).contains("| 1 |"))


func test_stats_of() -> void:
	assert_eq(Simulator.stats_of([5, 1, 3]), {"n": 3, "min": 1, "median": 3.0, "mean": 3.0, "max": 5})
	assert_eq(Simulator.stats_of([4, 1, 3, 2]).median, 2.5)
	assert_eq(Simulator.stats_of([]).n, 0)


# --- invariant checks -----------------------------------------------------------------------------

func test_invariants_hold_for_a_fresh_game() -> void:
	var prev := GameState.new(1)
	var next := GameState.new(1)
	next.current_turn = 1
	assert_eq(Simulator.check_invariants(prev, next, []), [])


func test_invariant_checks_catch_broken_states() -> void:
	var prev := GameState.new(1)
	var bad := GameState.new(1)
	bad.current_turn = 3
	bad.find_faction("kingdom").gold = -5
	bad.find_province("westwatch").owner = "pirates"
	var lost := Army.new()
	lost.id = "kingdom-90"
	lost.owner = "kingdom"
	lost.location = "atlantis"
	lost.units.append(Unit.new(bad.find_faction("kingdom").unit_types[0], "kingdom"))
	bad.armies.append(lost)
	var empty := Army.new()
	empty.id = "kingdom-91"
	empty.owner = "kingdom"
	empty.location = "highcrag"
	bad.armies.append(empty)
	var intruder := Army.new()
	intruder.id = "beasts-92"
	intruder.owner = "beasts"
	intruder.location = "crownkeep"
	var tusker := Unit.new(bad.find_faction("beasts").unit_types[0], "beasts")
	tusker.current_hp = 0
	intruder.units.append(tusker)
	bad.armies.append(intruder)
	var events := [
		{"type": "teleport", "phase": "movement", "factions": [], "numbers": {}},
		{"type": "battle", "phase": "battles", "factions": ["kingdom", "beasts"],
			"numbers": {"destroyed": ["beasts-92"], "report": {"end": "stalemate", "rounds_fought": 0, "sides": []}}},
	]
	var checks := _checks(Simulator.check_invariants(prev, bad, events))
	for expected in ["validate", "gold_negative", "owner_unknown", "army_location_unknown", "army_empty",
			"unit_hp_not_positive", "hostile_armies_share_province", "destroyed_army_present", "event_type_unknown",
			"battle_end_unknown", "battle_rounds", "turn_counter", "gold_accounting"]:
		assert_true(checks.has(expected), "catches %s: %s" % [expected, checks])


func test_occupied_province_must_belong_to_its_occupier() -> void:
	var prev := GameState.new(1)
	var next := GameState.new(1)
	next.current_turn = 1
	next.find_army("kingdom-1").location = "westwatch"
	assert_eq(_checks(Simulator.check_invariants(prev, next, [])), ["occupied_not_captured"])


# --- policies -------------------------------------------------------------------------------------

func test_policy_names() -> void:
	for policy_name in Policies.NAMES:
		var p = Policies.make(policy_name)
		assert_true(p != null, policy_name)
		assert_eq(p.policy_name, policy_name)
	assert_eq(Policies.make("nonsense"), null)


func test_best_recruits_spends_on_the_strongest_affordable_mix() -> void:
	var s := GameState.new(1)
	var orders: Array = Policies.Base.best_recruits(s, "kingdom")
	var cost := 0
	var value := 0
	for o in orders:
		var ut := TurnResolver.recruitable_type(s.find_faction("kingdom"), o.unit_type_id)
		cost += ut.cost
		value += ut.hp * ut.attack
	assert_true(cost <= 50, "affordable: %d" % cost)
	# The best hp x attack mix for 50 gold, worked out by hand from the unit data (#4 balance pass):
	# Knights 17 x 11 = 187 for 20 gold, Crossbowmen 8 x 11 = 88 for 10, Spearmen 8 x 9 = 72 for 8.
	assert_eq(value, 462, "2 Knights and 1 Crossbowmen (187 + 187 + 88) is the best mix for 50 gold")
	assert_eq(Policies.Base.best_recruits(s, "kingdom", 50), [], "a reserve of all the gold buys nothing")
	var priced := TurnResolver.price_recruits(s, "kingdom", orders)
	for r in priced.results:
		assert_true(r.ok, "every recruit passes price_recruits")


func test_greedy_marches_toward_the_enemy_capital() -> void:
	var s := GameState.new(1)
	var orders: Array = Policies.make("greedy").orders(s, "kingdom", SeededRNG.new(1))
	var moves := _moves(orders)
	assert_true(moves.has("kingdom-1"), "the starting army marches")
	assert_true(["westwatch", "highcrag", "rivermarch"].has(moves.get("kingdom-1", "")), str(moves))


func test_greedy_keeps_one_army_home_when_an_enemy_is_next_to_the_capital() -> void:
	var s := _state([
		["kingdom-1", "kingdom", "crownkeep", ["knights", "knights", "knight_captain"]],
		["kingdom-2", "kingdom", "crownkeep", ["knights", "crossbowmen", "spearmen"]],
		["beasts-1", "beasts", "westwatch", ["fangthrowers"]],
	])
	s.find_province("crownkeep").owner = "kingdom"
	var moves := _moves(Policies.make("greedy").orders(s, "kingdom", SeededRNG.new(1)))
	assert_false(moves.has("kingdom-1"), "the strongest army at the capital stays home: %s" % moves)
	assert_true(moves.has("kingdom-2"), "the other army marches: %s" % moves)


func test_greedy_holds_back_from_a_likely_loss_but_always_attacks_the_enemy_capital() -> void:
	var s := _state([
		["kingdom-1", "kingdom", "stonegate", ["spearmen"]],
		["beasts-1", "beasts", "blackwood", ["war_bear", "war_bear", "tuskers", "warchief"]],
	])
	var greedy = Policies.make("greedy")
	var moves := _moves(greedy.orders(s, "kingdom", SeededRNG.new(1)))
	assert_false(moves.has("kingdom-1"), "no suicide attack into Blackwood: %s" % moves)
	assert_eq(greedy.stats.get("held_back", 0), 1)

	var s2 := _state([
		["kingdom-1", "kingdom", "ebonpeak", ["spearmen"]],
		["beasts-1", "beasts", "fangridge", ["war_bear", "war_bear", "tuskers", "warchief"]],
	])
	var moves2 := _moves(Policies.make("greedy").orders(s2, "kingdom", SeededRNG.new(1)))
	assert_eq(moves2.get("kingdom-1", ""), "fangridge", "the enemy capital is always attacked")


func test_random_policy_only_gives_valid_orders() -> void:
	var s := GameState.new(1)
	var rng := SeededRNG.new(3)
	var policy = Policies.make("random")
	for i in 20:
		var orders: Array = policy.orders(s, "beasts", rng)
		var book := OrderBook.new()
		for o in orders:
			assert_eq(book.submit(s, "beasts", o), "", "order %d accepted" % i)


func test_turtle_keeps_its_capital_held() -> void:
	var s := GameState.new(1)
	var moves := _moves(Policies.make("turtle").orders(s, "beasts", SeededRNG.new(1)))
	assert_false(moves.has("beasts-1"), "the only army stays in the capital: %s" % moves)
