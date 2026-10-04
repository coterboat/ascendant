extends "res://tests/test_case.gd"
## M3c S-6 (#104) acceptance, tests/test_ai_sieges.gd: the computer in a game with forts and sieges (design/M3C_SIEGES.md
## §8). A 30-turn human-vs-computer session with no refused computer order; constructed positions for each rule of
## §8.2-§8.4; a stand-off that becomes a siege and then a battle at a fort; determinism, and the computer never reading a
## rival's queued orders. The thresholds come from AISieges, the odds from Forecast (the real battle rules).

const F := preload("res://tests/siege_fixtures.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const SEED := 4242


func _plan(s: GameState, fid: String, rng_seed: int = 7, level: String = "normal") -> Array:
	return AIPlayer.new().plan_orders(s, fid, SeededRNG.new(rng_seed), level)


func _of(orders: Array, kind) -> Array:
	return orders.filter(func(o): return is_instance_of(o, kind))


func _moves_of(orders: Array, army_id: String) -> Array:
	return orders.filter(func(o): return o is MoveOrder and o.army_id == army_id)


func _storms(orders: Array, pid: String) -> Array:
	return orders.filter(func(o): return o is SiegeOrder and o.is_storm() and o.province == pid)


func _sallies(orders: Array) -> Array:
	return orders.filter(func(o): return o is SiegeOrder and o.is_sally())


## Every order is accepted by OrderBook, in the order given.
func _assert_legal(s: GameState, fid: String, orders: Array, what: String) -> void:
	var book := OrderBook.new()
	for o in orders:
		assert_eq(book.submit(s, fid, o), "", "%s: %s is legal" % [what, o.describe()])


# --- a whole session ------------------------------------------------------------------------------

func test_thirty_turns_against_a_scripted_human_with_no_refused_computer_order() -> void:
	for level in AIPlayer.DIFFICULTIES:
		var session := GameSession.new(GameState.with_sieges(SEED), [CROWN, CLANS], SEED, AutoBattleResolver.new(), {CLANS: level})
		var computer := AISeat.new(session, SEED)
		computer.play(session)
		var at_forts := 0  # sieges begun and battles at forts
		for t in 30:
			if session.is_over():
				break
			_human_turn(session)
			assert_eq(session.end_turn(), "")
			computer.play(session)
			for e in session.turn_report().events:
				if e.type == "siege_started" or (e.type == "battle" and e.numbers.has("siege")):
					at_forts += 1
		assert_true(session.turns_played() >= 5, "%s: the game ran (%d turns)" % [level, session.turns_played()])
		assert_eq(computer.rejections(), [], "%s: the session refused none of the computer's orders" % level)
		assert_true(at_forts > 0, "%s: the computer besieged or stormed (%d)" % [level, at_forts])


## The scripted human, as the Crown: its biggest army marches up the northern road to the Clans' capital, and it
## recruits a mix at home every turn. Orders the rules refuse are skipped.
func _human_turn(session: GameSession) -> void:
	var s := session.state()
	var road := ["westwatch", "stonegate", "blackwood", "ebonpeak", "fangridge"]
	for id in ["crossbowmen", "spearmen", "knights", "spearmen"]:
		session.queue_order(RecruitOrder.new(id))
	var t := session.turn_number()
	var lead := ""
	for a in TurnResolver._sorted_armies(s):
		if a.owner == CROWN and a.ruler == null and (lead.is_empty() or a.units.size() > s.find_army(lead).units.size()):
			lead = a.id
	if t <= road.size() and not lead.is_empty():
		session.queue_order(MoveOrder.new(lead, road[t - 1]))


# --- §8.2 besieging and storming ------------------------------------------------------------------

## Turn 6: the Clans (the computer) have besieged the Crown's Stonegate since turn 4 with `clans` units; the Crown's
## other armies are far away.
func _clans_besieging(clans: Array, garrison: Array) -> GameState:
	var s := F.state([
		["kingdom-1", CROWN, "stonegate", garrison],
		["kingdom-2", CROWN, "rivermarch", ["spearmen"]],
		["beasts-1", CLANS, "stonegate", clans],
		["beasts-2", CLANS, "fangridge", F.units("tuskers", 3)],
	], {"stonegate": CROWN, "rivermarch": CROWN, "blackwood": CLANS, "ebonpeak": CLANS})
	s.current_turn = 5
	s.find_province("stonegate").siege_since = 4
	return s


func test_a_storm_at_the_threshold_and_not_below() -> void:
	var seen := {"storm": 0, "wait": 0}
	for clans in [F.units("war_bear", 2), F.units("war_bear", 4), F.units("war_bear", 7), F.units("war_bear", 10)]:
		var s := _clans_besieging(clans, F.units("spearmen", 4) + ["knight_captain"])
		var odds := Forecast.storm_odds(s, CLANS, "stonegate")
		var orders := _plan(s, CLANS)
		var stormed := not _storms(orders, "stonegate").is_empty()
		assert_eq(stormed, float(odds.win_rate) >= AISieges.STORM_WIN,
			"%d War Bears: storm odds %.2f against the threshold %.2f" % [clans.size(), odds.win_rate, AISieges.STORM_WIN])
		seen["storm" if stormed else "wait"] += 1
		_assert_legal(s, CLANS, orders, "%d War Bears" % clans.size())
	assert_true(seen.storm > 0 and seen.wait > 0, "both sides of the threshold were tried: %s" % str(seen))


func test_a_relief_stepping_back_does_not_draw_the_computer_into_a_losing_siege() -> void:
	# The Clans' army at Blackwood could besiege Stonegate: it would lose a storm, but it beats the garrison in the
	# open. A strong Crown army stands 1, 2 or 3 moves away.
	for spot in [["westwatch", false], ["crownkeep", false], ["rivermarch", true]]:
		var s := F.state([
			["kingdom-1", CROWN, "stonegate", F.units("spearmen", 6) + F.units("crossbowmen", 3) + ["knight_captain"]],
			["kingdom-2", CROWN, spot[0], F.units("knights", 8) + ["knight_captain"]],
			["beasts-1", CLANS, "blackwood", F.units("tuskers", 12)],
			["beasts-2", CLANS, "fangridge", F.units("tuskers", 3)],
		], {"stonegate": CROWN, "westwatch": CROWN, "rivermarch": CROWN, "blackwood": CLANS})
		s.current_turn = 5
		assert_true(float(Forecast.storm_odds(s, CLANS, "stonegate", [MoveOrder.new("beasts-1", "stonegate")]).win_rate) < AISieges.STORM_WIN,
			"a storm from the march isn't on")
		var orders := _plan(s, CLANS)
		assert_true(_storms(orders, "stonegate").is_empty())
		var into := _moves_of(orders, "beasts-1").filter(func(o): return o.to == "stonegate")
		assert_eq(not into.is_empty(), spot[1], "a relief army at %s (%d moves away): %s" % [spot[0],
			_dist(s, spot[0], "stonegate"), "besiege" if spot[1] else "don't besiege"])
		_assert_legal(s, CLANS, orders, spot[0])


func _dist(s: GameState, a: String, b: String) -> int:
	var seen := {a: 0}
	var queue := [a]
	while not queue.is_empty():
		var at: String = queue.pop_front()
		for n in s.find_province(at).neighbors:
			if not seen.has(n):
				seen[n] = int(seen[at]) + 1
				queue.append(n)
	return int(seen.get(b, 99))


func test_engines_are_recruited_into_an_army_at_the_forward_keep_and_marched_to_the_siege() -> void:
	var s := F.state([
		["kingdom-1", CROWN, "stonegate", F.units("spearmen", 6) + F.units("crossbowmen", 3) + ["knight_captain"]],
		["kingdom-2", CROWN, "rivermarch", ["spearmen"]],
		["beasts-1", CLANS, "stonegate", F.units("tuskers", 12)],
		["beasts-2", CLANS, "blackwood", F.units("tuskers", 3)],
		["beasts-3", CLANS, "fangridge", F.units("tuskers", 3)],
	], {"stonegate": CROWN, "rivermarch": CROWN, "blackwood": CLANS, "ebonpeak": CLANS})
	s.current_turn = 5
	s.find_province("stonegate").siege_since = 4
	F.rich(s, CLANS, 200)
	var engine := String(FortData.engine_for(CLANS).id)
	var orders := _plan(s, CLANS)
	assert_true(_storms(orders, "stonegate").is_empty(), "not a storm this turn: the engines are for a siege that goes on")
	var bought := orders.filter(func(o): return o is RecruitOrder and o.unit_type_id == engine)
	assert_false(bought.is_empty(), "Wallbreakers are bought")
	for o in bought:
		assert_eq(o.at, "blackwood", "at the forward keep next to the siege")
	var troops := SiegeRules.troops([s.find_army("beasts-1"), s.find_army("beasts-2")])
	assert_true(bought.size() <= troops / int(FortData.SIEGE.troops_per_engine), "never beyond 1 for every 5 troops")
	assert_true(bought.size() <= AISieges.ENGINES_AT_KEEP)
	_assert_legal(s, CLANS, orders, "engines")
	# Resolved, the engines ride with the army at Blackwood, which marches to the siege next turn.
	var r := F.resolve(s, {CLANS: orders}, true)
	var carrier: Army = r.new_state.find_army("beasts-2")
	assert_true(carrier != null and carrier.engines == bought.size(), "the army at Blackwood carries them")
	var next := _plan(r.new_state, CLANS)
	assert_false(_moves_of(next, "beasts-2").filter(func(o): return o.to == "stonegate").is_empty(), "and marches them to the siege")
	_assert_legal(r.new_state, CLANS, next, "the march")


# --- §8.3 defending forts -------------------------------------------------------------------------

func test_relief_and_sally_go_together_and_the_ruler_stays_inside() -> void:
	var s := GameState.with_sieges(SEED, {}, {"rulers": true})
	var king := RulerRules.ruler_army(s, CROWN)
	var beast := RulerRules.ruler_army(s, CLANS)
	s.armies.clear()
	king.location = "stonegate"
	s.armies.append(king)
	s.armies.append(beast)
	s.armies.append(F.army(s, ["kingdom-11", CROWN, "stonegate", F.units("spearmen", 3)]))
	s.armies.append(F.army(s, ["kingdom-12", CROWN, "westwatch", F.units("knights", 6) + ["knight_captain"]]))
	s.armies.append(F.army(s, ["beasts-11", CLANS, "stonegate", F.units("tuskers", 5)]))
	for pid in ["stonegate", "westwatch"]:
		s.find_province(pid).owner = CROWN
	s.current_turn = 5
	s.find_province("stonegate").siege_since = 4
	var garrison := ["kingdom-11"]
	var odds := Forecast.relief_odds(s, CROWN, MoveOrder.new("kingdom-12", "stonegate"), garrison)
	assert_true(float(odds.win_rate) >= AISieges.RELIEF_WIN, "the position is one to relieve: %s" % odds.text)
	var orders := _plan(s, CROWN)
	assert_false(_moves_of(orders, "kingdom-12").filter(func(o): return o.to == "stonegate").is_empty(), "the relief marches in")
	var sallies := _sallies(orders)
	assert_eq(sallies.size(), 1, "one sally")
	assert_eq(sallies[0].army_id, "kingdom-11")
	assert_eq(sallies[0].with_army, "kingdom-12", "tied to the relief")
	assert_true(_moves_of(orders, king.id).is_empty() and sallies.filter(func(o): return o.army_id == king.id).is_empty(),
		"the ruler stays inside")
	_assert_legal(s, CROWN, orders, "relief and sally")


func test_a_hopeless_keep_is_abandoned_the_turn_before_its_breach() -> void:
	# The Crown's other army is at Rivermarch, 3 moves from Stonegate: no relief can come within 2 turns.
	var s := F.state([
		["kingdom-1", CROWN, "stonegate", ["spearmen"]],
		["kingdom-2", CROWN, "rivermarch", ["spearmen"]],
		["beasts-1", CLANS, "stonegate", F.units("tuskers", 20)],
		["beasts-2", CLANS, "fangridge", F.units("tuskers", 3)],
	], {"stonegate": CROWN, "westwatch": CROWN, "rivermarch": CROWN, "blackwood": CLANS})
	s.current_turn = 5
	var p := s.find_province("stonegate")
	p.siege_since = 4
	p.walls = 2  # 20 troops drop them by 3: breached at the end of this turn
	assert_true(Forecast.breach_odds(s, CROWN, "stonegate").win_rate < AISieges.ABANDON_ODDS, "hopeless in the open")
	var orders := _plan(s, CROWN)
	assert_eq(_dist(s, "rivermarch", "stonegate"), AISieges.REACH + 1)
	var out := _moves_of(orders, "kingdom-1")
	assert_eq(out.size(), 1, "the garrison leaves")
	assert_true(_sallies(orders).is_empty())
	_assert_legal(s, CROWN, orders, "abandon")
	# With a relief within two moves (Crownkeep, through Westwatch) it holds instead.
	assert_eq(_dist(s, "crownkeep", "stonegate"), AISieges.REACH)
	s.find_army("kingdom-2").location = "crownkeep"
	orders = _plan(s, CROWN)
	assert_true(_moves_of(orders, "kingdom-1").is_empty(), "a relief could come: hold")


func test_a_garrison_stays_in_a_keep_an_enemy_can_reach() -> void:
	var s := F.state([
		["kingdom-1", CROWN, "stonegate", F.units("knights", 4)],
		["kingdom-2", CROWN, "crownkeep", F.units("spearmen", 6)],
		["beasts-1", CLANS, "blackwood", F.units("tuskers", 3)],
		["beasts-2", CLANS, "blackwood", F.units("tuskers", 3)],
		["beasts-3", CLANS, "fangridge", F.units("war_bear", 6)],
	], {"stonegate": CROWN, "blackwood": CLANS, "ebonpeak": CLANS})
	s.current_turn = 5
	var orders := _plan(s, CLANS)
	var staying := ["beasts-1", "beasts-2"].filter(func(id): return _moves_of(orders, id).is_empty())
	assert_false(staying.is_empty(), "at least one army stays in Blackwood, which the Crown can reach")
	_assert_legal(s, CLANS, orders, "garrison")


# --- §8.4 recruiting and building -----------------------------------------------------------------

func test_the_palisade_site_is_the_one_nearest_the_enemy_capital() -> void:
	var owners := {"westwatch": CROWN, "highcrag": CROWN, "rivermarch": CROWN, "greenglade": CROWN, "thornvale": CROWN}
	var s := F.state([["kingdom-1", CROWN, "crownkeep", F.units("spearmen", 6)], ["beasts-1", CLANS, "fangridge", F.units("tuskers", 6)]], owners)
	F.rich(s, CROWN, 120)
	s.current_turn = AISieges.FORTIFY_TURN - 1
	var orders := _plan(s, CROWN)
	var fortify := _of(orders, FortifyOrder)
	# Greenglade and Thornvale are both two moves from Crownkeep and three from Fangridge: the richer one, Greenglade.
	assert_eq(fortify.size(), 1, "a palisade is ordered from turn %d" % AISieges.FORTIFY_TURN)
	assert_eq(fortify[0].province, "greenglade")
	_assert_legal(s, CROWN, orders, "fortify")
	# An enemy army next to Greenglade: Thornvale instead.
	s.armies.append(F.army(s, ["beasts-2", CLANS, "deepwood", ["tuskers"]]))
	assert_eq(_of(_plan(s, CROWN), FortifyOrder)[0].province, "thornvale")
	# Not before the turn.
	s.current_turn = AISieges.FORTIFY_TURN - 2
	assert_true(_of(_plan(s, CROWN), FortifyOrder).is_empty(), "not before turn %d" % AISieges.FORTIFY_TURN)


func test_recruits_go_to_the_forward_fort_when_the_capital_is_safe() -> void:
	var s := F.state([["kingdom-1", CROWN, "crownkeep", F.units("spearmen", 6)], ["kingdom-2", CROWN, "stonegate", F.units("spearmen", 2)],
		["beasts-1", CLANS, "fangridge", F.units("tuskers", 6)]], {"stonegate": CROWN, "westwatch": CROWN})
	F.rich(s, CROWN, 150)
	s.current_turn = 2
	var orders := _plan(s, CROWN)
	var at_gate := orders.filter(func(o): return o is RecruitOrder and o.at == "stonegate")
	assert_false(at_gate.is_empty(), "the forward keep musters recruits")
	assert_true(at_gate.size() <= SiegeRules.recruit_limit(2), "within its limit")
	_assert_legal(s, CROWN, orders, "recruits at forts")


# --- §8.4 stand-offs ------------------------------------------------------------------------------

func test_a_stand_off_becomes_a_siege_within_6_turns_and_a_battle_at_a_fort_within_12() -> void:
	# Both capitals stacked, as in the games #94 broke up. Each faction's pile is 20 turns of its income or more
	# (the Crown's largely gold, the Clans' in units on a small realm), and the Crown's army is the stronger.
	var s := GameState.with_sieges(SEED)
	s.armies.clear()
	s.armies.append(F.army(s, ["kingdom-1", CROWN, "crownkeep", F.units("spearmen", 14) + F.units("crossbowmen", 10) + F.units("knights", 12) + ["knight_captain"]]))
	s.armies.append(F.army(s, ["beasts-1", CLANS, "fangridge", F.units("tuskers", 10) + F.units("fangthrowers", 10) + F.units("war_bear", 4) + ["warchief"]]))
	for pid in ["westwatch", "stonegate", "highcrag", "rivermarch"]:
		s.find_province(pid).owner = CROWN
	s.find_province("blackwood").owner = CLANS
	s.find_faction(CROWN).gold = 450
	s.find_faction(CLANS).gold = 100
	assert_false(AIPlayer.standoff_info(s, CROWN).is_empty(), "the Crown is in a stand-off")
	assert_false(AIPlayer.standoff_info(s, CLANS).is_empty(), "so are the Clans")
	var session := GameSession.new(s, [CROWN, CLANS], SEED, AutoBattleResolver.new(), {CROWN: "normal", CLANS: "normal"})
	var computer := AISeat.new(session, SEED)
	var first_siege := 0
	var first_battle := 0
	for t in 12:
		if session.is_over():
			break
		computer.play(session)
		for e in session.turn_report().events:
			if e.type == "siege_started" and first_siege == 0:
				first_siege = session.turns_played()
			if e.type == "battle" and e.numbers.has("siege") and first_battle == 0:
				first_battle = session.turns_played()
	assert_eq(computer.rejections(), [])
	assert_true(first_siege > 0 and first_siege <= 6, "a siege by turn 6 (turn %d)" % first_siege)
	assert_true(first_battle > 0 and first_battle <= 12, "a battle at a fort by turn 12 (turn %d)" % first_battle)


# --- determinism and privacy ----------------------------------------------------------------------

func test_the_same_seed_gives_the_same_orders_and_a_rivals_orders_are_never_read() -> void:
	var s := _clans_besieging(F.units("war_bear", 4), F.units("spearmen", 4) + ["knight_captain"])
	var a := _plan(s, CLANS, 11).map(func(o): return o.to_dict())
	var b := _plan(s, CLANS, 11).map(func(o): return o.to_dict())
	assert_eq(a, b, "the same state and seed give the same orders")
	# A session where the human (the Crown, seat 1) queues different orders: the computer's are the same.
	var plans := []
	for human in [[], [SiegeOrder.sally("kingdom-1"), RecruitOrder.new("spearmen")]]:
		var session := GameSession.new(s, [CROWN, CLANS], SEED, AutoBattleResolver.new(), {CLANS: "normal"})
		for o in human:
			session.queue_order(o)
		assert_eq(session.end_turn(), "")
		var computer := AISeat.new(session, SEED)
		computer.play(session)
		plans.append(session.history().back().orders.get(CLANS, []))
	assert_eq(plans[0], plans[1], "the computer's orders don't depend on the human's queued orders")
