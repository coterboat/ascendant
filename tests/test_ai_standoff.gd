extends "res://tests/test_case.gd"
## The computer breaks capital stand-offs (#94). A stand-off is read from the state alone
## (AIPlayer.standoff_info): what piles up while nobody fights, every unit a faction fields and its treasury
## at recruit prices, against its income. Once it is reached, the computer picks by position: hunt the enemy
## army that keeps its garrison home (the garrison marches out), strike at even odds, besiege the enemy capital
## though stronger armies guard the road, or raid undefended provinces when it is the weaker side. Positions are
## built on the M1 map; every number a test needs (the pile, the odds) comes from the data and the AI's own
## guesses, never typed in.

const Simulator := preload("res://tools/autoplay/simulator.gd")
const SEATS := ["kingdom", "beasts"]


# --- fixtures -------------------------------------------------------------------------------------

## A fresh M1 state with the starting armies replaced by `specs` ([[id, owner, location, [unit ids]], ...]),
## `owners` {province id: faction id} on top of the capitals, and every faction's gold set to 0.
func _state(specs: Array, owners: Dictionary = {}) -> GameState:
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
	for f in s.factions:
		f.gold = 0
	return s


## `n` copies of `type_id`.
func _many(type_id: String, n: int) -> Array:
	var out := []
	for i in n:
		out.append(type_id)
	return out


## What standoff_info counts for `fid`: its units at their recruit price (rulers left out).
func _army_value(s: GameState, fid: String) -> int:
	var total := 0
	for a in s.armies:
		if a.owner != fid:
			continue
		for u in a.units:
			total += RulerRules.recruit_price(s, fid, u.type)
		if a.commander != null:
			total += RulerRules.recruit_price(s, fid, a.commander.type)
	return total


func _income(s: GameState, fid: String) -> int:
	return int(TurnResolver.income_of(s, fid).total)


## Gives `fid` just enough gold that its pile reaches a stand-off (or exactly one gold short of it).
func _set_pile(s: GameState, fid: String, reached: bool) -> void:
	var need := ceili(AIPlayer.STANDOFF_TURNS * _income(s, fid)) - _army_value(s, fid)
	assert_true(need > 1, "the armies alone are short of a stand-off, so the gold decides it (%d)" % need)
	s.find_faction(fid).gold = need if reached else need - 1


func _moves(orders: Array) -> Dictionary:
	var out := {}
	for o in orders:
		if o is MoveOrder:
			out[o.army_id] = o.to
	return out


func _plan(s: GameState, fid: String, seed_value: int = 1) -> Dictionary:
	var ai := AIPlayer.new()
	var orders := ai.plan_orders(s, fid, SeededRNG.new(seed_value))
	var book := OrderBook.new()
	for o in orders:
		assert_eq(book.submit(s, fid, o), "", "%s is accepted" % o.describe())
	return {"orders": orders, "moves": _moves(orders), "notes": ai.last_plan_notes(), "stats": ai.last_plan_stats()}


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
		out.append(f.commander_type.id)
	return out


## The Crown and the Clans split the map along its middle, as most capped games did: the Crown holds the
## western seven provinces, the Clans the eastern seven.
const WEST := ["crownkeep", "westwatch", "highcrag", "rivermarch", "greenglade", "stonegate", "thornvale"]
const EAST := ["fangridge", "ebonpeak", "ironspike", "bloodfen", "deepwood", "wildmoor", "blackwood"]


func _split_owners() -> Dictionary:
	var out := {}
	for p in WEST:
		out[p] = "kingdom"
	for p in EAST:
		out[p] = "beasts"
	return out


# --- reading a stand-off from the state ------------------------------------------------------------

func test_a_standoff_is_read_from_the_state_alone() -> void:
	var start := GameState.new(99)
	assert_eq(AIPlayer.standoff_info(start, "kingdom"), {}, "the opening is no stand-off")
	# A pile at home worth STANDOFF_TURNS turns of income or more is one.
	var s := _state([["kingdom-1", "kingdom", "crownkeep", _many("knights", 10)], ["beasts-1", "beasts", "fangridge", ["tuskers"]]], _split_owners())
	_set_pile(s, "kingdom", false)
	assert_eq(AIPlayer.standoff_info(s, "kingdom"), {}, "one gold short")
	_set_pile(s, "kingdom", true)
	var info := AIPlayer.standoff_info(s, "kingdom")
	assert_false(info.is_empty(), "reached")
	assert_eq(int(info.income), _income(s, "kingdom"))
	assert_eq(int(info.value), _army_value(s, "kingdom"))
	assert_eq(int(info.gold), s.find_faction("kingdom").gold)
	assert_eq(int(info.units), 10)
	assert_true(float(info.turns) >= AIPlayer.STANDOFF_TURNS, "worth %.1f turns of income" % float(info.turns))
	# Gold banked counts the same as units: the pile is what nobody has spent in battle.
	var banked := _state([["kingdom-1", "kingdom", "crownkeep", ["spearmen"]], ["beasts-1", "beasts", "fangridge", ["tuskers"]]], _split_owners())
	_set_pile(banked, "kingdom", true)
	assert_false(AIPlayer.standoff_info(banked, "kingdom").is_empty(), "gold banked past the threshold")
	# It is the same after a save and load (nothing outside the state goes in), and for the other side only its own pile counts.
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(AIPlayer.standoff_info(loaded, "kingdom"), info, "the save holds everything it reads")
	assert_eq(AIPlayer.standoff_info(s, "beasts"), {}, "the Clans have nothing piled up")
	assert_eq(AIPlayer.standoff_info(s, "pirates"), {}, "an unknown faction is no stand-off")


func test_the_plan_reads_nothing_but_the_state_and_the_seat_rng() -> void:
	var s := _hunt_position(true)
	var ai := AIPlayer.new()
	var first: Array = ai.plan_orders(s, "kingdom", SeededRNG.new(5)).map(func(o): return o.to_dict())
	var notes := ai.last_plan_notes()
	# The same brain after a plan on another state, and a fresh brain: the same orders and notes.
	ai.plan_orders(_hunt_position(false), "kingdom", SeededRNG.new(5))
	assert_eq(ai.plan_orders(s, "kingdom", SeededRNG.new(5)).map(func(o): return o.to_dict()), first, "nothing carries over between plans")
	assert_eq(ai.last_plan_notes(), notes)
	var fresh := AIPlayer.new()
	assert_eq(fresh.plan_orders(GameState.from_dict(s.to_dict()), "kingdom", SeededRNG.new(5)).map(func(o): return o.to_dict()), first, "a loaded save plays the same")


func test_gold_is_spent_even_when_the_foe_is_overwhelming() -> void:
	# A Clans pile far bigger than anything the Crown has: every recruit adds only a sliver to the Crown's odds,
	# but gold has no other use, so it is spent rather than banked (banked gold is half of a stand-off).
	var s := _state([
		["kingdom-1", "kingdom", "crownkeep", ["spearmen"]],
		["beasts-1", "beasts", "fangridge", _many("war_bear", 150) + _many("tuskers", 150) + ["warchief"]],
	], _split_owners())
	var gold := 0
	for ut in s.find_faction("kingdom").unit_types:
		gold = maxi(gold, 3 * RulerRules.recruit_price(s, "kingdom", ut))
	s.find_faction("kingdom").gold = gold
	var p := _plan(s, "kingdom")
	var spent := 0
	for o in p.orders:
		if o is RecruitOrder:
			spent += RulerRules.recruit_price(s, "kingdom", TurnResolver.recruitable_type(s.find_faction("kingdom"), o.unit_type_id))
	var cheapest := gold
	for ut in s.find_faction("kingdom").unit_types:
		cheapest = mini(cheapest, RulerRules.recruit_price(s, "kingdom", ut))
	assert_true(gold - spent < cheapest, "it spends all it can (%d of %d gold): %s" % [spent, gold, str(p.notes)])


# --- hunt: the garrison marches out against the army that pins it ------------------------------------

## The stand-off most capped games ended in: each side's small forward army faces the other's (Greenglade
## and Deepwood) and neither attacks; each capital keeps everything else home because the enemy's forward
## army is three moves away, so the piles at home grow every turn. The Crown's pile is filled to just short
## of a stand-off with its own units (_fill_pile), and `reached` adds the few gold that tip it over (or one
## gold fewer), so this turn's recruits stay too few to hold Crownkeep alone either way.
func _hunt_position(reached: bool) -> GameState:
	var s := _state([
		["kingdom-1", "kingdom", "crownkeep", ["knight_captain"]],
		["kingdom-2", "kingdom", "greenglade", ["knights", "spearmen", "crossbowmen"]],
		["beasts-1", "beasts", "deepwood", _many("tuskers", 4) + _many("war_bear", 2)],
		["beasts-2", "beasts", "fangridge", _many("tuskers", 12) + _many("war_bear", 6) + ["warchief"]],
	], _split_owners())
	_fill_pile(s, "kingdom-1")
	_set_pile(s, "kingdom", reached)
	return s


## Adds the faction's regular units to army `army_id`, dearest first, until its pile is a few gold short of a
## stand-off (less than the cheapest unit's price, and at least 2).
func _fill_pile(s: GameState, army_id: String) -> void:
	var a := s.find_army(army_id)
	var f := s.find_faction(a.owner)
	var types: Array = f.unit_types.duplicate()
	types.sort_custom(func(x, y): return RulerRules.recruit_price(s, f.id, x) > RulerRules.recruit_price(s, f.id, y))
	var target := ceili(AIPlayer.STANDOFF_TURNS * _income(s, f.id)) - 2
	for ut in types:
		var price := RulerRules.recruit_price(s, f.id, ut)
		while _army_value(s, f.id) + price <= target:
			a.units.append(Unit.new(ut, f.id))


func test_without_a_standoff_the_garrison_stays_home() -> void:
	var p := _plan(_hunt_position(false), "kingdom")
	assert_false(p.moves.has("kingdom-1"), "the pile at home holds: %s" % p.moves)
	assert_true(" ".join(p.notes).contains("Keeping the garrison in Crownkeep"), str(p.notes))
	assert_eq(int(p.stats.get("standoff", 0)), 0)


func test_in_a_standoff_the_garrison_hunts_the_army_that_pins_it() -> void:
	var s := _hunt_position(true)
	var p := _plan(s, "kingdom")
	# It marches toward Deepwood, by the shortest road (Crownkeep → Rivermarch → Greenglade → Deepwood).
	assert_eq(p.moves.get("kingdom-1", ""), "rivermarch", "the pile marches on the enemy at Deepwood: %s" % p.moves)
	# The forward army next to the enemy doesn't attack it alone.
	assert_ne(p.moves.get("kingdom-2", ""), "deepwood", "the forward army waits for the pile: %s" % p.moves)
	assert_eq(int(p.stats.standoff), 1)
	assert_eq(int(p.stats.get("hunts", 0)), 1)
	var said: Array = p.notes.filter(func(n): return n.contains("stand-off"))
	assert_eq(said.size(), 1, "one plain note says it: %s" % str(p.notes))
	assert_true(said[0].contains("Crownkeep") and said[0].contains("Deepwood"), said[0])
	# It names the armies as the turn report does (#55): ours marching out, and the one it hunts.
	assert_true(said[0].contains(TurnReportText.army_name(s, "kingdom-1")) and said[0].contains(TurnReportText.army_name(s, "beasts-1")), said[0])
	assert_false(" ".join(p.notes).contains("Keeping the garrison"), str(p.notes))
	var ids := _ids(s)
	for n in p.notes:
		for id in ids:
			assert_false(n.contains(id), "note names '%s' by id: %s" % [id, n])


func test_next_turn_the_massed_army_attacks_the_enemy_it_hunted() -> void:
	# The pile has joined the forward army next to Deepwood: together they crush it.
	var s := _hunt_position(true)
	s.find_army("kingdom-1").location = "greenglade"
	var p := _plan(s, "kingdom")
	assert_eq(p.moves.get("kingdom-1", ""), "deepwood", str(p.moves))
	assert_eq(p.moves.get("kingdom-2", ""), "deepwood", str(p.moves))


func test_a_garrison_never_leaves_the_capital_open_to_an_army_that_can_reach_it_this_turn() -> void:
	# The enemy's forward army stands next to Crownkeep and the garrison can't crush it: it holds,
	# stand-off or not, and no other army is sent away from the capital's defense.
	var s := _state([
		["kingdom-1", "kingdom", "crownkeep", _many("spearmen", 6) + ["knight_captain"]],
		["beasts-1", "beasts", "rivermarch", _many("tuskers", 5) + ["war_bear"]],
		["beasts-2", "beasts", "fangridge", _many("tuskers", 6)],
	], _split_owners())
	s.find_province("rivermarch").owner = "beasts"
	_set_pile(s, "kingdom", true)
	assert_false(AIPlayer.standoff_info(s, "kingdom").is_empty())
	var p := _plan(s, "kingdom")
	assert_false(p.moves.has("kingdom-1"), "the garrison holds: %s %s" % [p.moves, p.notes])


func test_the_turn_report_says_when_the_computer_breaks_a_standoff() -> void:
	# The surface that already shows the computer's intent: AISeat.report_notes, which the turn report panel
	# lists under "What the computer was thinking" once the turn has resolved.
	var s := _hunt_position(true)
	var session := GameSession.new(s, SEATS, 7, AutoBattleResolver.new(), {"kingdom": "normal", "beasts": "normal"})
	var computer := AISeat.new(session, 7)
	assert_eq(computer.report_notes(session), [], "nothing before the turn resolves")
	computer.play(session)
	assert_eq(session.turns_played(), 1)
	var crown: Array = computer.report_notes(session).filter(func(e): return e.faction == "kingdom")
	assert_eq(crown.size(), 1)
	var said: Array = crown[0].notes.filter(func(n): return n.begins_with("Breaking the stand-off"))
	assert_eq(said.size(), 1, str(crown[0].notes))
	# And the army really left: it stands at Rivermarch now.
	assert_eq(session.state().find_army("kingdom-1").location, "rivermarch")


func test_a_note_names_a_few_armies_and_counts_the_rest() -> void:
	var s := _hunt_position(true)
	var ai := AIPlayer.new()
	ai._begin(s, "kingdom", SeededRNG.new(1), "normal")
	var many := []
	for i in AIPlayer.NAMED_ARMIES + 4:
		var a := Army.new()
		a.id = "kingdom-%d" % (20 + i)
		a.owner = "kingdom"
		many.append(a)
	var text := ai._army_names(many)
	assert_true(text.begins_with(TurnReportText.army_name(s, "kingdom-20")), text)
	assert_true(text.ends_with("and %d more armies" % 4), text)
	assert_eq(ai._army_names(many.slice(0, AIPlayer.NAMED_ARMIES + 1)).count("the Crown's"), AIPlayer.NAMED_ARMIES + 1, "one more than the limit is just named")


# --- strike: even odds are worth taking -------------------------------------------------------------

## A Crown army at Thornvale next to a Clans army at Wildmoor, far from both capitals, sized from the data so
## that the AI's own odds for the attack are at least STANDOFF_WIN but under LIKELY_WIN. [] when no size fits.
func _strike_position() -> Array:
	for n in range(1, 9):
		for k in range(0, 5):
			for m in range(2, 13):
				var s := _state([
					["kingdom-1", "kingdom", "thornvale", _many("knights", n) + _many("spearmen", k)],
					["kingdom-2", "kingdom", "crownkeep", ["spearmen"]],
					["beasts-1", "beasts", "wildmoor", _many("tuskers", m)],
					["beasts-2", "beasts", "fangridge", ["fangthrowers"]],
				], _split_owners())
				var probe := AIPlayer.new()
				probe._begin(s, "kingdom", SeededRNG.new(1), "normal")
				var rate: float = probe._attack_rate([s.find_army("kingdom-1")], "wildmoor").rate
				if rate >= AIPlayer.STANDOFF_WIN and rate < AIPlayer.LIKELY_WIN:
					return [s, rate]
	return []


func test_in_a_standoff_an_even_fight_is_taken() -> void:
	var found := _strike_position()
	assert_false(found.is_empty(), "some size gives odds between STANDOFF_WIN and LIKELY_WIN")
	if found.is_empty():
		return
	var s: GameState = found[0]
	var quiet := _plan(s, "kingdom")
	assert_ne(quiet.moves.get("kingdom-1", ""), "wildmoor", "no stand-off: %d%% is not enough (%s)" % [roundi(found[1] * 100), quiet.moves])
	_set_pile(s, "kingdom", true)
	var p := _plan(s, "kingdom")
	assert_eq(p.moves.get("kingdom-1", ""), "wildmoor", "stand-off: it attacks at %d%% (%s)" % [roundi(found[1] * 100), str(p.notes)])
	assert_true(p.notes.any(func(n): return n.contains("Attacking the enemy at Wildmoor") and n.contains("stand-off")), str(p.notes))


# --- siege: march next to the enemy capital though the road is guarded ---------------------------

## The Crown's main army at Blackwood (the Crown holds it and Wildmoor), two moves from Fangridge, where the
## whole Clans army stands. The step to Ebonpeak (next to Fangridge) is guarded: by the AI's own guess the Crown is at least even there
## (STANDOFF_SAFE) but not SAFE_RATIO stronger. [] when no size fits.
func _siege_position() -> Array:
	for n in range(4, 30):
		var owners := _split_owners()
		owners["blackwood"] = "kingdom"
		owners["wildmoor"] = "kingdom"
		var s := _state([
			["kingdom-1", "kingdom", "blackwood", _many("knights", n) + ["knight_captain"]],
			["kingdom-2", "kingdom", "crownkeep", ["spearmen"]],
			["beasts-1", "beasts", "fangridge", _many("tuskers", 14) + ["warchief"]],
		], owners)
		var probe := AIPlayer.new()
		probe._begin(s, "kingdom", SeededRNG.new(1), "normal")
		var r := probe._ratio([s.find_army("kingdom-1")], [s.find_army("beasts-1")], probe._ground_bonus("ebonpeak"), 1.0)
		if r >= AIPlayer.STANDOFF_SAFE and r < AIPlayer.SAFE_RATIO:
			return [s, r]
	return []


func test_in_a_standoff_the_main_army_besieges_the_enemy_capital() -> void:
	var found := _siege_position()
	assert_false(found.is_empty(), "some size is even but not safely stronger next to Fangridge")
	if found.is_empty():
		return
	var s: GameState = found[0]
	var quiet := _plan(s, "kingdom")
	assert_false(quiet.moves.has("kingdom-1"), "no stand-off: it masses at Blackwood (%s)" % quiet.moves)
	assert_true(" ".join(quiet.notes).contains("guarded"), str(quiet.notes))
	_set_pile(s, "kingdom", true)
	var p := _plan(s, "kingdom")
	assert_eq(p.moves.get("kingdom-1", ""), "ebonpeak", "stand-off: it camps next to Fangridge (%s)" % str(p.notes))
	assert_eq(int(p.stats.get("sieges", 0)), 1)
	assert_true(p.notes.any(func(n): return n.contains("stand-off") and n.contains("Fangridge") and n.contains(TurnReportText.army_name(s, "kingdom-1"))), str(p.notes))


# --- raid: the weaker side takes what is left unguarded ---------------------------------------------

## The Crown's field army at Stonegate, on the northern road to Fangridge. The Clans' whole field army
## stands at Ebonpeak, too strong for it to hunt or pass: Blackwood, the road on, is next to it. Wildmoor, two
## moves off through the Crown's Thornvale, is the Clans' and nobody guards it. Crownkeep is four moves
## from Ebonpeak, so no garrison is needed at home.
func _raid_position() -> GameState:
	return _state([
		["kingdom-1", "kingdom", "stonegate", _many("knights", 4)],
		["kingdom-2", "kingdom", "crownkeep", _many("spearmen", 3)],
		["beasts-1", "beasts", "ebonpeak", _many("war_bear", 8) + ["warchief"]],
		["beasts-2", "beasts", "fangridge", _many("tuskers", 3)],
	], _split_owners())


func test_in_a_standoff_the_weaker_side_raids_an_unguarded_province() -> void:
	var s := _raid_position()
	var quiet := _plan(s, "kingdom")
	assert_false(quiet.moves.has("kingdom-1"), "no stand-off: it waits at Stonegate (%s %s)" % [quiet.moves, quiet.notes])
	assert_true(" ".join(quiet.notes).contains("guarded"), str(quiet.notes))
	_set_pile(s, "kingdom", true)
	var p := _plan(s, "kingdom")
	assert_eq(p.moves.get("kingdom-1", ""), "thornvale", "stand-off: it heads for Wildmoor through Thornvale (%s %s)" % [p.moves, p.notes])
	assert_eq(int(p.stats.get("raids", 0)), 1)
	assert_true(p.notes.any(func(n): return n.contains("stand-off") and n.contains("Wildmoor") and n.contains(TurnReportText.army_name(s, "kingdom-1"))), str(p.notes))


# --- whole games -------------------------------------------------------------------------------------

func test_a_game_that_used_to_sit_at_its_capitals_now_ends() -> void:
	# Regent's Court and the Celestial Host against Blood of the Fang and the Blood Pact: before #94 both sides
	# stacked every recruit at home and no battle was fought in 60 turns (seed 1). #131's morale-aware guess
	# settles seed 1 in an early capital attack with no stand-off, so seed 5 keeps a long stand-off that breaks.
	var r := Simulator.play_game(5, SEATS, ["ai", "ai"], Simulator.TURN_CAP, Callable(),
		{"paths": true, "builds": ["regents_court", "blood_of_the_fang"], "branches": ["celestial_host", "blood_pact"]})
	assert_eq(r.violations, [])
	assert_eq(r.errors, [])
	assert_eq(r.rejections, {}, "every order was accepted")
	assert_true(r.finished, "the game ends before the cap (%d turns, %d battles)" % [r.turns, r.battles.size()])
	var standoffs := 0
	for st in r.policy_stats:
		standoffs += int(st.get("standoff", 0))
	assert_true(standoffs > 0, "a seat broke a stand-off on the way")
