extends "res://tests/test_case.gd"
## M3c S-2 (#100) acceptance, tests/test_siege_odds.gd: odds at forts fight SiegeRules.next_battle's plan with the real
## rules (design/M3C_SIEGES.md §9.2). A constructed storm names the walls as its top "why"; for single-battle plans
## Forecast.storm_odds equals AutoBattleResolver.estimate on the same plan; a chained plan's odds come from fighting
## the chain (checked against TurnResolver on the same seeds); the move forecast into an enemy fort says "besiege"
## and doesn't promise the old "+2 fort".

const F := preload("res://tests/siege_fixtures.gd")
const CROWN := "kingdom"
const CLANS := "beasts"


## Turn 6 is being ordered. The Crown holds Stonegate (a keep, hills) with kingdom-1 and kingdom-2; a relief,
## kingdom-3, waits at Westwatch. With `besieged`, the Clans' beasts-4 has besieged it since turn 4; otherwise it
## waits at Blackwood. The Clans' army is `clans` (unit ids).
func _state(besieged: bool, clans: Array, walls: int = -1) -> GameState:
	var s := F.state([
		["kingdom-1", CROWN, "stonegate", F.units("spearmen", 3)],
		["kingdom-2", CROWN, "stonegate", F.units("crossbowmen", 2) + ["knight_captain"]],
		["kingdom-3", CROWN, "westwatch", F.units("knights", 3)],
		["beasts-4", CLANS, "stonegate" if besieged else "blackwood", clans],
	], {"stonegate": CROWN, "westwatch": CROWN, "blackwood": CLANS})
	s.current_turn = 5
	if besieged:
		s.find_province("stonegate").siege_since = 4
	if walls >= 0:
		s.find_province("stonegate").walls = walls
	return s


func _orders_of(fid: String, orders: Array) -> Dictionary:
	var out := {"storms": {}, "sallies": {}}
	for o in orders:
		if o is SiegeOrder and o.is_storm():
			out.storms[o.province] = {fid: true}
		elif o is SiegeOrder:
			out.sallies[o.army_id] = {"faction": fid, "with": o.with_army, "from": ""}
	return out


## AutoBattleResolver.estimate on the first battle next_battle plans for `orders` (given by `fid`) at Stonegate.
func _estimate(s: GameState, fid: String, orders: Array, perspective: String) -> Dictionary:
	var plan := SiegeRules.next_battle(s, "stonegate", {}, _orders_of(fid, orders), [])
	assert_false(plan.is_empty(), "there is a battle to estimate")
	var fids: Array = plan.sides.keys()
	fids.sort()
	var sides := fids.map(func(f): return {"faction": f, "armies": plan.sides[f]})
	var ctx := {"kind": "province", "defender": plan.defender, "province": s.find_province("stonegate"), "province_ids": ["stonegate"],
		"state": s, "siege": plan.siege}
	return AutoBattleResolver.estimate(sides, ctx, perspective)


func test_a_constructed_storm_names_the_walls_as_its_top_why() -> void:
	# A full citadel on plains (no terrain): the walls are the garrison's whole edge.
	var s := F.state([
		["kingdom-1", CROWN, "crownkeep", F.units("spearmen", 6) + F.units("crossbowmen", 2) + ["knight_captain"]],
		["beasts-2", CLANS, "crownkeep", F.units("tuskers", 6) + F.units("fangthrowers", 2) + ["warchief"]],
	])
	s.current_turn = 5
	s.find_province("crownkeep").siege_since = 4
	var r := F.resolve(s, {CLANS: [SiegeOrder.storm("crownkeep")]}, true)
	var b: Dictionary = r.events.filter(func(e): return e.type == "battle")[0]
	var report: Dictionary = b.numbers.report
	var top := SiegeRules.walls_max(3)
	var defense := FortData.WALLS_DEFENSE_PER_STEP * ceili(float(top) / FortData.WALL_STEP)
	assert_eq(int(b.numbers.siege.walls_defense), defense)
	assert_eq(String(report.factors[0].id), "walls", "the walls are the top reason: %s" % report.why)
	assert_true(String(report.why).begins_with("the walls of Crownkeep (%d of %d) gave the defending Aurel Crown +%d defense" % [top, top, defense]), report.why)
	# And the odds say so too: the garrison's top reason for holding is its walls.
	var odds := Forecast.storm_odds(s, CLANS, "crownkeep", [], [], CROWN)
	assert_true(odds.ok, odds.text)
	assert_true(String(odds.reasons[0]).begins_with("the walls of Crownkeep (%d of %d) give the defending Aurel Crown +%d defense" % [top, top, defense]),
		str(odds.reasons))


func test_single_battle_plans_equal_the_estimate() -> void:
	# A storm by the besiegers.
	var s := _state(true, F.units("war_bear", 3) + ["warchief"])
	var storm := Forecast.storm_odds(s, CLANS, "stonegate")
	var est := _estimate(s, CLANS, [SiegeOrder.storm("stonegate")], CLANS)
	assert_true(storm.ok, storm.text)
	assert_false(storm.chained, "one battle")
	assert_eq(storm.battles, ["storm"])
	for key in ["wins", "samples", "win_rate", "label", "reasons", "text"]:
		assert_eq(storm[key], est[key], "storm odds: %s equals the estimate's" % key)
	# The garrison's side of the same storm.
	var held := Forecast.storm_odds(s, CLANS, "stonegate", [], [], CROWN)
	assert_eq(held.wins, AutoBattleResolver.ODDS_SAMPLES - int(storm.wins), "the garrison holds exactly when the storm fails")
	# A sally.
	var sally := Forecast.sally_odds(s, CROWN, ["kingdom-1", "kingdom-2"])
	est = _estimate(s, CROWN, [SiegeOrder.sally("kingdom-1"), SiegeOrder.sally("kingdom-2")], CROWN)
	assert_eq(sally.battles, ["open"])
	for key in ["wins", "win_rate", "label", "reasons"]:
		assert_eq(sally[key], est[key], "sally odds: %s equals the estimate's" % key)
	# The breach, with the walls taken as 0.
	var breach := Forecast.breach_odds(s, CLANS, "stonegate")
	assert_eq(breach.battles, ["breach"])
	var down := s.deep_copy()
	down.find_province("stonegate").walls = 0
	est = _estimate(down, CLANS, [], CLANS)
	assert_eq(breach.wins, est.wins, "breach odds equal the estimate of the breach battle")
	# battle_odds at a fort fights the same plan: a breached fort's battle comes at once.
	var at_breach := Forecast.battle_odds(down, CLANS, ["beasts-4"], "stonegate")
	assert_true(at_breach.ok, at_breach.text)
	assert_eq(at_breach.wins, est.wins)
	# Where no battle happens, battle_odds says so instead of promising one.
	var waiting := Forecast.battle_odds(s, CLANS, ["beasts-4"], "stonegate")
	assert_false(waiting.ok)
	assert_eq(String(waiting.code), "siege")
	assert_true(String(waiting.text).contains("besiege"), waiting.text)


func test_a_chained_plan_fights_the_chain_on_each_seed() -> void:
	# The relief from Westwatch arrives while the Clans storm: the open battle first, then the storm if they won it.
	var s := _state(true, F.units("war_bear", 4) + ["warchief"])
	var odds := Forecast.storm_odds(s, CLANS, "stonegate", [], ["kingdom-3"])
	assert_true(odds.ok, odds.text)
	assert_eq(odds.battles[0], "open", "the battle outside the walls comes first")
	assert_true(odds.chained, "and in some tests the storm follows")
	var taken := 0
	for i in AutoBattleResolver.ODDS_SAMPLES:
		var r := TurnResolver.resolve(s, {CROWN: [MoveOrder.new("kingdom-3", "stonegate")], CLANS: [SiegeOrder.storm("stonegate")]},
			AutoBattleResolver.odds_seed(i), AutoBattleResolver.new())
		if r.new_state.find_province("stonegate").owner == CLANS:
			taken += 1
	assert_eq(odds.wins, taken, "the odds are what the turn does on the same seeds")
	# A relief with a sally, from the Crown's side, is checked the same way.
	var relief := Forecast.relief_odds(s, CROWN, MoveOrder.new("kingdom-3", "stonegate"), ["kingdom-1"])
	assert_true(relief.ok, relief.text)
	assert_eq(relief.battles, ["open"])
	var lifted := 0
	for i in AutoBattleResolver.ODDS_SAMPLES:
		var r := TurnResolver.resolve(s, {CROWN: [MoveOrder.new("kingdom-3", "stonegate"), SiegeOrder.sally("kingdom-1", "kingdom-3")]},
			AutoBattleResolver.odds_seed(i), AutoBattleResolver.new())
		if SiegeRules.besiegers(r.new_state, "stonegate").is_empty():
			lifted += 1
	assert_eq(relief.wins, lifted)
	# Orders that can't be given have no odds, with the reason.
	assert_false(Forecast.storm_odds(s, CROWN, "stonegate").ok, "nobody storms their own walls")
	assert_false(Forecast.sally_odds(s, CROWN, ["kingdom-3"]).ok, "a sally comes from inside the walls")


func test_the_move_forecast_into_an_enemy_fort_says_besiege_and_promises_no_fort_bonus() -> void:
	var top := SiegeRules.walls_max(2)
	var s := _state(false, F.units("war_bear", 2))
	var move := MoveOrder.new("beasts-4", "stonegate")
	var fc := Forecast.move(s, CLANS, move)
	assert_true(fc.ok, fc.text)
	assert_eq(fc.siege_row, "besiege")
	assert_true(String(fc.text).contains("besieges Stonegate"), fc.text)
	assert_false(String(fc.text).contains("+2 fort") or String(fc.text).contains("fort gives"), "no old fort bonus: %s" % fc.text)
	assert_false(String(fc.text).contains("you fight a battle"), "no battle promised: %s" % fc.text)
	assert_true(String(fc.text).contains("reach 0 at the end of turn"), "how fast the walls fall: %s" % fc.text)
	# With a storm order queued it says the storm happens, with the walls it meets.
	fc = Forecast.move(s, CLANS, move, [SiegeOrder.storm("stonegate")])
	assert_eq(fc.siege_row, "storm")
	assert_true(String(fc.text).contains("+%d defense" % SiegeRules.walls_defense(top)), fc.text)
	# An empty fort is taken whole; a breached one is fought at once; your own besieged fort gets a relief.
	var empty := _state(false, F.units("war_bear", 2))
	empty.armies = empty.armies.filter(func(a): return not ["kingdom-1", "kingdom-2"].has(a.id))
	fc = Forecast.move(empty, CLANS, move)
	assert_eq(fc.siege_row, "empty")
	assert_true(fc.would_capture)
	assert_true(String(fc.text).contains("you take the keep at Stonegate unopposed (walls %d of %d)" % [top, top]), fc.text)
	fc = Forecast.move(_state(false, F.units("war_bear", 2), 0), CLANS, move)
	assert_eq(fc.siege_row, "breach")
	fc = Forecast.move(_state(true, F.units("war_bear", 2)), CROWN, MoveOrder.new("kingdom-3", "stonegate"))
	assert_eq(fc.siege_row, "relief")
	assert_true(String(fc.text).contains("outside the walls as a relief"), fc.text)
	# The defender's ground at a fort with sieges: its walls, and only in a storm.
	var ground := Forecast.defender_ground(s.find_province("stonegate"))
	assert_true(ground.contains("walls (%d of %d) +%d defense, but only if stormed" % [top, top, SiegeRules.walls_defense(top)]), ground)
	assert_false(ground.contains("fort gives"), ground)
	# Without sieges the old words stay.
	assert_true(Forecast.defender_ground(GameState.new(3).find_province("stonegate")).contains("its fort gives +2 defense"))


func test_the_siege_forecast_gives_both_sides_odds_when_asked() -> void:
	var s := _state(true, F.units("war_bear", 3))
	var besieger := Forecast.siege(s, CLANS, "stonegate", [], true)
	assert_true(besieger.storm_odds.ok and besieger.breach_odds.ok)
	assert_true(String(besieger.text).contains("Storming now: "), besieger.text)
	assert_true(String(besieger.text).contains("as in a sally or at the breach: "), besieger.text)
	assert_true(String(besieger.text).contains("arriving too: "), "the relief that can reach it: %s" % besieger.text)
	var garrison := Forecast.siege(s, CROWN, "stonegate", [], true)
	assert_true(String(garrison.text).contains("If they storm this turn, your odds of holding: "), garrison.text)
	assert_true(String(garrison.text).contains("Sallying now with 2 armies: "), garrison.text)
	assert_true(String(garrison.text).contains("Relief from Westwatch with that sally: "), garrison.text)
	assert_eq(int(garrison.storm_odds.wins), AutoBattleResolver.ODDS_SAMPLES - int(besieger.storm_odds.wins), "both sides read one storm")
	assert_false(Forecast.siege(s, CLANS, "stonegate").has("storm_odds"), "no odds unless asked")
