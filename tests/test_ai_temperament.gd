extends "res://tests/test_case.gd"
## #184 acceptance, tests/test_ai_temperament.gd: the computer's temperament. The roll is a pure function of the seed and
## the seat on a stream of its own; a "normal" brain plays exactly as before; the aggressive one storms, besieges and
## attacks at RISK_DISCOUNT worse odds, reads a stand-off at AGGRESSIVE_STANDOFF of the pile, and goes around a fort it
## won't attack. Every threshold comes from AIPlayer and AISieges, every odds from Forecast (the real battle rules), and
## each position on the edge is found by scanning army sizes, never by a hardcoded number.

const F := preload("res://tests/siege_fixtures.gd")
const Policies := preload("res://tools/autoplay/policies.gd")
const SiegeMatrix := preload("res://tools/autoplay/siege_matrix.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const SEED := 4242


func _brain(temperament: String) -> AIPlayer:
	var ai := AIPlayer.new()
	ai.set_temperament(temperament)
	return ai


func _plan(s: GameState, fid: String, temperament: String, rng_seed: int = 7) -> Array:
	return _brain(temperament).plan_orders(s, fid, SeededRNG.new(rng_seed), "normal")


func _storms(orders: Array, pid: String) -> Array:
	return orders.filter(func(o): return o is SiegeOrder and o.is_storm() and o.province == pid)


func _into(orders: Array, army_id: String, pid: String) -> bool:
	return not orders.filter(func(o): return o is MoveOrder and o.army_id == army_id and o.to == pid).is_empty()


func _assert_legal(s: GameState, fid: String, orders: Array, what: String) -> void:
	var book := OrderBook.new()
	for o in orders:
		assert_eq(book.submit(s, fid, o), "", "%s: %s is legal" % [what, o.describe()])


func _texts(orders: Array) -> Array:
	return orders.map(func(o): return JSON.stringify(o.to_dict()))


# --- the roll ---------------------------------------------------------------------------------------

func test_the_roll_is_a_pure_function_of_the_seed_and_seat_near_its_share() -> void:
	var aggressive := 0
	var n := 0
	for game_seed in range(1, 201):
		for seat in 2:
			var t := AIPlayer.choose_temperament(game_seed, seat)
			assert_true(AIPlayer.TEMPERAMENTS.has(t), "a known temperament: %s" % t)
			assert_eq(AIPlayer.choose_temperament(game_seed, seat), t, "seed %d seat %d rolls the same again" % [game_seed, seat])
			n += 1
			if t == "aggressive":
				aggressive += 1
	var share := float(aggressive) / float(n)
	# 400 rolls: three standard deviations of a fair coin is about 0.075.
	var sd := sqrt(AIPlayer.AGGRESSIVE_SHARE * (1.0 - AIPlayer.AGGRESSIVE_SHARE) / float(n))
	assert_true(absf(share - AIPlayer.AGGRESSIVE_SHARE) <= 3.0 * sd, "aggressive share %.3f near %.2f" % [share, AIPlayer.AGGRESSIVE_SHARE])


func test_the_seat_rolls_its_temperament_without_touching_its_dice() -> void:
	for game_seed in [3, 8, 21, 55]:
		var session := GameSession.new(GameState.new(game_seed), [CROWN, CLANS], game_seed, AutoBattleResolver.new(), {CROWN: "normal", CLANS: "normal"})
		var computer := AISeat.new(session, game_seed)
		var dice := computer.rng_state()
		for seat in 2:
			var fid: String = [CROWN, CLANS][seat]
			assert_eq(computer.temperament(fid), AIPlayer.choose_temperament(game_seed, seat), "seed %d: %s's roll" % [game_seed, fid])
			assert_eq(computer._brains[fid].temperament(), computer.temperament(fid), "its brain plays it")
			# No rulers: the seat RNG has made no draw at all, temperament or not.
			assert_eq(dice[fid], SeededRNG.new(AISeat.seat_seed(game_seed, seat)).to_dict(), "seed %d: %s's dice untouched" % [game_seed, fid])
	var hotseat := GameSession.new(GameState.new(5), [CROWN, CLANS], 5, AutoBattleResolver.new())
	assert_eq(AISeat.new(hotseat, 5).temperament(CROWN), "", "a person's seat has no temperament")


func test_an_unknown_temperament_plays_normal_and_normal_plays_as_before() -> void:
	var ai := AIPlayer.new()
	assert_eq(ai.temperament(), "normal", "the default")
	ai.set_temperament("berserk")
	assert_eq(ai.temperament(), "normal")
	for game_seed in [4, 9]:
		var s := GameState.with_sieges(game_seed)
		for fid in [CROWN, CLANS]:
			var plain := AIPlayer.new().plan_orders(s, fid, SeededRNG.new(game_seed), "normal")
			assert_eq(_texts(_plan(s, fid, "normal", game_seed)), _texts(plain), "seed %d %s: set to normal changes nothing" % [game_seed, fid])


func test_the_names_and_help_read_from_the_numbers() -> void:
	assert_eq(AIPlayer.temperament_name("aggressive"), "Aggressive")
	assert_eq(AIPlayer.temperament_name("normal"), "Steady")
	assert_true(AIPlayer.temperament_help("aggressive").contains("%d points" % roundi(AIPlayer.RISK_DISCOUNT * 100.0)))
	assert_true(AISeat.tag_help("the Crown", "normal", "aggressive").contains("Style: Aggressive."), "the seat's tooltip names it")
	assert_false(AISeat.tag_help("the Crown", "normal").contains("Style"), "and says nothing without one, as before")


# --- the stand-off ----------------------------------------------------------------------------------

func test_the_aggressive_computer_reads_a_stand_off_at_its_share_of_the_pile() -> void:
	for sieges in [false, true]:
		var s := GameState.with_sieges(SEED) if sieges else GameState.new(SEED)
		var crown := s.find_faction(CROWN)
		var income := int(TurnResolver.income_of(s, CROWN).total)
		var need := AIPlayer.SIEGE_STANDOFF_TURNS if sieges else AIPlayer.STANDOFF_TURNS
		s.armies = s.armies.filter(func(a): return a.owner != CROWN)  # the treasury alone is the pile
		# A pile between the aggressive threshold and the steady one.
		crown.gold = ceili(need * AIPlayer.AGGRESSIVE_STANDOFF * income)
		assert_true(float(crown.gold) / float(income) < need, "sieges %s: below the steady threshold" % sieges)
		assert_eq(AIPlayer.standoff_info(s, CROWN), {}, "sieges %s: no stand-off for a steady computer" % sieges)
		assert_false(AIPlayer.standoff_info(s, CROWN, "aggressive").is_empty(), "sieges %s: a stand-off for an aggressive one" % sieges)
		crown.gold -= 1
		assert_eq(AIPlayer.standoff_info(s, CROWN, "aggressive"), {}, "sieges %s: and not below its own threshold" % sieges)


# --- sieges and storms ------------------------------------------------------------------------------

## Turn 6: the Clans have besieged the Crown's Stonegate since turn 4 with `clans`; the Crown's other armies are far away.
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


func test_the_aggressive_computer_storms_at_the_discounted_threshold() -> void:
	var steady := AISieges.STORM_WIN
	var bold := AISieges.STORM_WIN - AIPlayer.RISK_DISCOUNT
	var in_gap := 0
	var checked := 0
	# Garrisons and besiegers of many sizes; every one whose storm odds lie near the two thresholds is planned both ways.
	for m in range(2, 9):
		for bears in range(2, 6):
			for tuskers in range(0, 7, 3):
				var s := _clans_besieging(F.units("war_bear", bears) + F.units("tuskers", tuskers), F.units("spearmen", m) + ["knight_captain"])
				var odds := float(Forecast.storm_odds(s, CLANS, "stonegate").win_rate)
				if odds < bold - 0.1 or odds >= steady + 0.1:
					continue
				var what := "%d Spearmen against %d War Bears and %d Tuskers, odds %.2f" % [m, bears, tuskers, odds]
				var normal := _plan(s, CLANS, "normal")
				var aggressive := _plan(s, CLANS, "aggressive")
				assert_eq(not _storms(normal, "stonegate").is_empty(), odds >= steady, "%s: steady storms at %.2f" % [what, steady])
				assert_eq(not _storms(aggressive, "stonegate").is_empty(), odds >= bold, "%s: aggressive storms at %.2f" % [what, bold])
				_assert_legal(s, CLANS, aggressive, what)
				checked += 1
				if odds >= bold and odds < steady:
					in_gap += 1
	assert_true(checked > 0 and in_gap > 0, "some armies sat between the two thresholds (%d checked, %d between)" % [checked, in_gap])


## Turn 6: the Clans' `clans` stand at Blackwood next to the Crown's Stonegate (a palisade at full walls), whose garrison
## is `garrison`; nobody else is within reach.
func _clans_next_to_a_fort(clans: Array, garrison: Array) -> GameState:
	var s := F.state([
		["kingdom-1", CROWN, "stonegate", garrison],
		["kingdom-2", CROWN, "crownkeep", F.units("spearmen", 6)],
		["beasts-1", CLANS, "blackwood", clans],
		["beasts-2", CLANS, "fangridge", F.units("tuskers", 3)],
	], {"stonegate": CROWN, "blackwood": CLANS, "ebonpeak": CLANS})
	s.current_turn = 5
	return s


func test_the_aggressive_computer_begins_a_siege_at_the_discounted_odds() -> void:
	var garrison := F.units("spearmen", 6) + F.units("crossbowmen", 2) + ["knight_captain"]
	var in_gap := 0
	var seen := 0
	for n in range(2, 18):
		var s := _clans_next_to_a_fort(F.units("tuskers", n), garrison)
		if float(Forecast.storm_odds(s, CLANS, "stonegate", [MoveOrder.new("beasts-1", "stonegate")]).win_rate) >= AISieges.STORM_WIN - AIPlayer.RISK_DISCOUNT:
			continue  # a storm, not a siege: the storm test covers it
		var normal := _plan(s, CLANS, "normal")
		var aggressive := _plan(s, CLANS, "aggressive")
		var n_in := _into(normal, "beasts-1", "stonegate")
		var a_in := _into(aggressive, "beasts-1", "stonegate")
		_assert_legal(s, CLANS, aggressive, "%d Tuskers" % n)
		seen += 1
		assert_true(a_in or not n_in, "%d Tuskers: whatever a steady computer besieges, an aggressive one does too" % n)
		if a_in and not n_in:
			in_gap += 1
	assert_true(seen > 0, "some armies were short of a storm")
	assert_true(in_gap > 0, "some army besieged only when aggressive")


# --- battles in the field ---------------------------------------------------------------------------

func test_the_aggressive_computer_attacks_an_army_at_the_discounted_odds() -> void:
	# No sieges: the Clans' army at Blackwood next to a Crown army at Stonegate, far from either capital, with no gold banked.
	var in_gap := 0
	var checked := 0
	for m in range(3, 9):
		for n in range(3, 12):
			var s := GameState.new(SEED)
			s.armies.clear()
			s.armies.append(F.army(s, ["kingdom-1", CROWN, "stonegate", F.units("spearmen", m) + ["knight_captain"]]))
			s.armies.append(F.army(s, ["kingdom-2", CROWN, "crownkeep", F.units("spearmen", 8)]))
			s.armies.append(F.army(s, ["beasts-1", CLANS, "blackwood", F.units("tuskers", n)]))
			s.armies.append(F.army(s, ["beasts-2", CLANS, "fangridge", F.units("tuskers", 2)]))
			s.find_faction(CLANS).gold = 0
			s.current_turn = 5
			var odds := float(Forecast.battle_odds(s, CLANS, ["beasts-1"], "stonegate").get("win_rate", 0.0))
			# The odds each temperament needs here: its stand-off (AGGRESSIVE_STANDOFF) makes it STANDOFF_WIN, else LIKELY_WIN.
			var need_n := AIPlayer.STANDOFF_WIN if not AIPlayer.standoff_info(s, CLANS).is_empty() else AIPlayer.LIKELY_WIN
			var need_a := (AIPlayer.STANDOFF_WIN if not AIPlayer.standoff_info(s, CLANS, "aggressive").is_empty() else AIPlayer.LIKELY_WIN) - AIPlayer.RISK_DISCOUNT
			if odds < need_a - 0.1 or odds >= need_n + 0.1:
				continue
			var what := "%d Spearmen against %d Tuskers, odds %.2f" % [m, n, odds]
			var n_in := _into(_plan(s, CLANS, "normal"), "beasts-1", "stonegate")
			var aggressive := _plan(s, CLANS, "aggressive")
			var a_in := _into(aggressive, "beasts-1", "stonegate")
			_assert_legal(s, CLANS, aggressive, what)
			assert_eq(n_in, odds >= need_n, "%s: steady attacks at %.2f" % [what, need_n])
			assert_eq(a_in, odds >= need_a, "%s: aggressive attacks at %.2f" % [what, need_a])
			checked += 1
			if a_in and not n_in:
				in_gap += 1
	assert_true(checked > 0 and in_gap > 0, "some fight was taken only when aggressive (%d checked, %d only aggressive)" % [checked, in_gap])


# --- going around -----------------------------------------------------------------------------------

func test_the_aggressive_main_army_goes_around_a_guarded_road() -> void:
	# The Clans hold the map but the Crown's capital and the three provinces around it, which a big garrison guards; Deepwood,
	# off the road, is nobody's. The Clans' army at Thornvale can't step next to Crownkeep safely: a steady computer masses
	# there, an aggressive one goes around toward Deepwood.
	for n in range(4, 20, 4):
		var s := GameState.with_sieges(SEED)
		s.armies = s.armies.filter(func(a): return a.owner == CROWN and a.ruler != null)
		s.armies.append(F.army(s, ["kingdom-1", CROWN, "crownkeep", F.units("spearmen", 14) + F.units("crossbowmen", 6) + ["knight_captain"]]))
		s.armies.append(F.army(s, ["beasts-1", CLANS, "thornvale", F.units("tuskers", n)]))
		s.armies.append(F.army(s, ["beasts-2", CLANS, "fangridge", F.units("tuskers", 3)]))
		for p in s.provinces:
			p.owner = CLANS
		for pid in ["crownkeep", "westwatch", "rivermarch", "highcrag"]:
			s.find_province(pid).owner = CROWN
		s.find_province("deepwood").owner = ""
		s.find_faction(CLANS).gold = 0
		s.current_turn = 5
		var steady := AIPlayer.new()
		var normal := steady.plan_orders(s, CLANS, SeededRNG.new(7), "normal")
		var bold := _brain("aggressive")
		var aggressive := bold.plan_orders(s, CLANS, SeededRNG.new(7), "normal")
		_assert_legal(s, CLANS, aggressive, "%d Tuskers" % n)
		var held := normal.filter(func(o): return o is MoveOrder and o.army_id == "beasts-1")
		var moved := aggressive.filter(func(o): return o is MoveOrder and o.army_id == "beasts-1")
		assert_eq(held, [], "%d Tuskers: a steady computer masses at Thornvale" % n)
		assert_eq(moved.size(), 1, "%d Tuskers: an aggressive one moves" % n)
		if moved.size() == 1:
			var d_before := _dist(s, "thornvale", "deepwood")
			assert_eq(_dist(s, String(moved[0].to), "deepwood"), d_before - 1, "%d Tuskers: one step toward Deepwood (%s)" % [n, moved[0].to])
		assert_false(bold.last_plan_notes().filter(func(l): return String(l).begins_with("Going around Crownkeep")).is_empty(), "%d Tuskers: the note says so" % n)


func _dist(s: GameState, a: String, b: String) -> int:
	var seen := {a: 0}
	var queue := [a]
	while not queue.is_empty():
		var at: String = queue.pop_front()
		for nb in s.find_province(at).neighbors:
			if not seen.has(nb):
				seen[nb] = int(seen[at]) + 1
				queue.append(nb)
	return int(seen.get(b, 99))


# --- notes and the autoplay -------------------------------------------------------------------------

func test_the_aggressive_computer_says_how_it_plays_on_the_first_turn() -> void:
	var s := GameState.with_sieges(SEED)
	var ai := _brain("aggressive")
	ai.plan_orders(s, CLANS, SeededRNG.new(1), "normal")
	var line: Array = ai.last_plan_notes().filter(func(l): return String(l).contains("plays aggressively"))
	assert_eq(line.size(), 1, "one line says so")
	assert_true(String(line[0]).contains("%d points" % roundi(AIPlayer.RISK_DISCOUNT * 100.0)))
	var steady := AIPlayer.new()
	steady.plan_orders(s, CLANS, SeededRNG.new(1), "normal")
	assert_true(steady.last_plan_notes().filter(func(l): return String(l).contains("aggressive")).is_empty(), "a steady one says nothing new")


func test_the_autoplay_plays_each_temperament() -> void:
	assert_eq(SiegeMatrix.temperament_policies(["ai", "ai"], ""), ["ai", "ai"])
	assert_eq(SiegeMatrix.temperament_policies(["ai", "ai"], "aggressive"), ["ai_aggressive", "ai_aggressive"])
	assert_eq(SiegeMatrix.temperament_policies(["ai", "ai"], "mixed"), ["ai_aggressive", "ai"])
	assert_eq(SiegeMatrix.temperament_policies(["turtle", "ai"], "roll"), ["turtle", "ai_roll"])
	assert_eq(Policies.make("ai").ai.temperament(), "normal", "plain ai keeps its games")
	assert_eq(Policies.make("ai_aggressive").ai.temperament(), "aggressive")
	for game_seed in [2, 6]:
		for seat in 2:
			var p = Policies.make("ai_roll")
			p.configure(game_seed, seat)
			assert_eq(p.ai.temperament(), AIPlayer.choose_temperament(game_seed, seat), "ai_roll rolls as an AI seat does")
