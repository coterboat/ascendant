extends "res://tests/test_case.gd"
## Tests for issue #3: order collection, deterministic turn resolver, forecasts, load validation,
## JSON round-trips and map fairness.
##
## Unit strengths used below (attack + defense, see StubBattleResolver):
##   kingdom: spearmen 11, crossbowmen 12, knights 20, knight_captain 26
##   beasts:  tuskers 17, fangthrowers 12, war_bear 25, warchief 26


# --- fixtures -------------------------------------------------------------------------------------

## A fresh state with the starting armies replaced by `specs`: [[id, owner, location, [unit ids]], ...].
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
	return s


func _resolve(s: GameState, orders: Dictionary, turn_seed: int = 1) -> Dictionary:
	var result := TurnResolver.resolve(s, orders, turn_seed)
	assert_true(result.new_state != null, "resolve produced a state")
	return result


func _events_of(events: Array, type: String) -> Array:
	return events.filter(func(e): return e.type == type)


func _gold(s: GameState, fid: String) -> int:
	return s.find_faction(fid).gold


func _assert_event_shape(events: Array) -> void:
	for e in events:
		for key in ["type", "phase", "provinces", "factions", "armies", "cause", "numbers", "text", "codex"]:
			assert_true(e.has(key), "event %s has %s" % [e.get("type", "?"), key])
		assert_true(TurnResolver.PHASES.has(e.phase), "event phase %s is a known phase" % e.phase)
		assert_false(String(e.text).is_empty(), "event %s has text" % e.type)
		assert_false(RulesCodex.text(e.codex).is_empty(), "event %s links codex entry %s" % [e.type, e.codex])


## The scripted two-player turn used by the replay tests: moves, a border swap, a same-province
## battle, a capture, recruits (one too expensive) and an invalid order.
func _scripted_state() -> GameState:
	return _state([
		["kingdom-1", "kingdom", "crownkeep", ["spearmen", "knight_captain"]],
		["kingdom-2", "kingdom", "thornvale", ["crossbowmen"]],
		["kingdom-3", "kingdom", "stonegate", ["knights"]],
		["beasts-4", "beasts", "wildmoor", ["fangthrowers"]],
		["beasts-5", "beasts", "ebonpeak", ["tuskers"]],
		["beasts-6", "beasts", "deepwood", ["war_bear"]],
	], {"thornvale": "kingdom", "wildmoor": "beasts", "stonegate": "kingdom", "ebonpeak": "beasts", "deepwood": "beasts"})


func _scripted_orders() -> Dictionary:
	return {
		"kingdom": [
			MoveOrder.new("kingdom-2", "wildmoor"),    # swaps with beasts-4: border battle (12 v 12, roll)
			MoveOrder.new("kingdom-3", "blackwood"),   # meets beasts-5 arriving too: battle, no defender
			MoveOrder.new("kingdom-1", "rivermarch"),  # plain move, captures neutral Rivermarch
			RecruitOrder.new("knights"),
			RecruitOrder.new("knights"),
			RecruitOrder.new("knights"),               # 3rd one: not enough gold
		],
		"beasts": [
			MoveOrder.new("beasts-4", "thornvale"),
			MoveOrder.new("beasts-5", "blackwood"),
			MoveOrder.new("beasts-6", "crownkeep"),    # not adjacent: rejected
			RecruitOrder.new("tuskers"),
		],
	}


# --- movement cases -------------------------------------------------------------------------------

func test_plain_move_arrives_and_leaves_input_untouched() -> void:
	var s := _state([["kingdom-1", "kingdom", "crownkeep", ["spearmen"]]])
	var before := var_to_str(s.to_dict())
	var r := _resolve(s, {"kingdom": [MoveOrder.new("kingdom-1", "westwatch")]})
	var ns: GameState = r.new_state
	assert_eq(ns.find_army("kingdom-1").location, "westwatch")
	var moved := _events_of(r.events, "army_moved")
	assert_eq(moved.size(), 1)
	assert_eq(moved[0].provinces, ["crownkeep", "westwatch"])
	assert_eq(moved[0].phase, "movement")
	assert_true(moved[0].text.contains("Crownkeep") and moved[0].text.contains("Westwatch"), moved[0].text)
	assert_eq(_events_of(r.events, "battle").size(), 0)
	assert_eq(ns.current_turn, s.current_turn + 1)
	assert_eq(var_to_str(s.to_dict()), before, "resolve does not modify the input state")
	_assert_event_shape(r.events)


func test_same_province_collision_fights_with_no_defender() -> void:
	# Kingdom knights (20) and beasts fangthrowers (12) both move into Thornvale.
	var s := _state([
		["kingdom-1", "kingdom", "highcrag", ["knights"]],
		["beasts-2", "beasts", "wildmoor", ["fangthrowers"]],
	])
	var r := _resolve(s, {"kingdom": [MoveOrder.new("kingdom-1", "thornvale")], "beasts": [MoveOrder.new("beasts-2", "thornvale")]})
	var ns: GameState = r.new_state
	var battles := _events_of(r.events, "battle")
	assert_eq(battles.size(), 1)
	var b: Dictionary = battles[0]
	assert_eq(b.provinces, ["thornvale"])
	assert_eq(b.factions, ["beasts", "kingdom"])
	assert_eq(b.cause, "arrived_together")
	assert_eq(b.numbers.defender, "")
	assert_eq(b.numbers.winner, "kingdom")
	assert_eq(b.numbers.strengths, {"beasts": 12, "kingdom": 20})
	assert_eq(b.numbers.units_lost, 1)
	assert_eq(ns.find_army("beasts-2"), null, "loser destroyed")
	assert_eq(ns.find_army("kingdom-1").location, "thornvale")
	assert_eq(ns.find_province("thornvale").owner, "kingdom", "winner captures")
	var cap := _events_of(r.events, "captured")
	assert_eq(cap[0].cause, "battle_victory")
	_assert_event_shape(r.events)


func test_same_province_tie_with_no_defender_uses_seeded_roll() -> void:
	# Crossbowmen (12) vs fangthrowers (12), both arriving: the seeded roll decides.
	var s := _state([
		["kingdom-1", "kingdom", "highcrag", ["crossbowmen"]],
		["beasts-2", "beasts", "wildmoor", ["fangthrowers"]],
	])
	var orders := {"kingdom": [MoveOrder.new("kingdom-1", "thornvale")], "beasts": [MoveOrder.new("beasts-2", "thornvale")]}
	var winners := {}
	for turn_seed in range(1, 40):
		var b: Dictionary = _events_of(_resolve(s, orders, turn_seed).events, "battle")[0]
		assert_eq(b.numbers.tie_break, "roll")
		assert_eq(b.numbers.winner, ["beasts", "kingdom"][b.numbers.roll], "roll indexes the tied factions sorted by id")
		assert_eq(_events_of(_resolve(s, orders, turn_seed).events, "battle")[0].numbers.winner, b.numbers.winner, "same seed, same winner")
		winners[b.numbers.winner] = true
	assert_eq(winners.size(), 2, "different seeds can pick either side")


func test_swap_fights_on_the_border() -> void:
	# Kingdom spearmen (11) Thornvale -> Wildmoor while beasts war bear (25) Wildmoor -> Thornvale.
	var s := _state([
		["kingdom-1", "kingdom", "thornvale", ["spearmen"]],
		["beasts-2", "beasts", "wildmoor", ["war_bear"]],
	], {"thornvale": "kingdom", "wildmoor": "beasts"})
	var r := _resolve(s, {"kingdom": [MoveOrder.new("kingdom-1", "wildmoor")], "beasts": [MoveOrder.new("beasts-2", "thornvale")]})
	var ns: GameState = r.new_state
	var border := _events_of(r.events, "border_battle")
	assert_eq(border.size(), 1)
	assert_eq(border[0].provinces, ["thornvale", "wildmoor"])
	assert_eq(border[0].cause, "swap")
	assert_eq(border[0].numbers.defender, "", "nobody defends a border")
	assert_eq(border[0].numbers.winner, "beasts")
	assert_eq(_events_of(r.events, "battle").size(), 0, "no second battle in a province")
	assert_eq(ns.find_army("kingdom-1"), null, "loser never arrives")
	assert_eq(ns.find_army("beasts-2").location, "thornvale", "winner completes its move")
	assert_eq(ns.find_province("thornvale").owner, "beasts")
	assert_eq(ns.find_province("wildmoor").owner, "beasts")
	var moved := _events_of(r.events, "army_moved")
	assert_eq(moved.size(), 1)
	assert_eq(moved[0].cause, "won_border_battle")
	assert_true(border[0].text.contains("border between Thornvale and Wildmoor"), border[0].text)
	_assert_event_shape(r.events)


func test_move_into_undefended_enemy_province_captures_it() -> void:
	var s := _state([["kingdom-1", "kingdom", "wildmoor", ["spearmen"]]], {"ironspike": "beasts", "wildmoor": "kingdom"})
	var r := _resolve(s, {"kingdom": [MoveOrder.new("kingdom-1", "ironspike")]})
	var ns: GameState = r.new_state
	assert_eq(ns.find_province("ironspike").owner, "kingdom")
	var cap := _events_of(r.events, "captured")
	assert_eq(cap.size(), 1)
	assert_eq(cap[0].cause, "undefended_enemy")
	assert_eq(cap[0].factions, ["kingdom", "beasts"])
	assert_eq(cap[0].numbers.income, 8)
	assert_eq(_events_of(r.events, "battle").size(), 0)
	assert_true(cap[0].text.contains("Thornmane Clans lost it"), cap[0].text)


func test_move_into_undefended_neutral_province_captures_it() -> void:
	var s := _state([["kingdom-1", "kingdom", "crownkeep", ["spearmen"]]])
	var r := _resolve(s, {"kingdom": [MoveOrder.new("kingdom-1", "highcrag")]})
	assert_eq(r.new_state.find_province("highcrag").owner, "kingdom")
	assert_eq(_events_of(r.events, "captured")[0].cause, "undefended_neutral")


func test_move_into_defended_province_holder_defends() -> void:
	# Beasts war bear (25) holds Wildmoor; kingdom spearmen (11) move in and lose.
	var s := _state([
		["kingdom-1", "kingdom", "thornvale", ["spearmen"]],
		["beasts-2", "beasts", "wildmoor", ["war_bear"]],
	], {"wildmoor": "beasts"})
	var r := _resolve(s, {"kingdom": [MoveOrder.new("kingdom-1", "wildmoor")]})
	var ns: GameState = r.new_state
	var b: Dictionary = _events_of(r.events, "battle")[0]
	assert_eq(b.cause, "held_vs_arrival")
	assert_eq(b.numbers.defender, "beasts")
	assert_eq(b.numbers.winner, "beasts")
	assert_eq(b.numbers.tie_break, "none")
	assert_eq(ns.find_army("kingdom-1"), null)
	assert_eq(ns.find_army("beasts-2").location, "wildmoor")
	assert_eq(ns.find_province("wildmoor").owner, "beasts")
	assert_eq(_events_of(r.events, "captured").size(), 0)


func test_holding_army_wins_ties() -> void:
	# Kingdom crossbowmen (12) hold Thornvale; beasts fangthrowers (12) move in. Tie goes to the holder.
	var s := _state([
		["kingdom-1", "kingdom", "thornvale", ["crossbowmen"]],
		["beasts-2", "beasts", "wildmoor", ["fangthrowers"]],
	], {"thornvale": "kingdom"})
	for turn_seed in [1, 2, 3, 4, 5]:
		var r := _resolve(s, {"beasts": [MoveOrder.new("beasts-2", "thornvale")]}, turn_seed)
		var b: Dictionary = _events_of(r.events, "battle")[0]
		assert_eq(b.numbers.defender, "kingdom")
		assert_eq(b.numbers.tie_break, "defender")
		assert_eq(b.numbers.winner, "kingdom")
		assert_eq(r.new_state.find_army("beasts-2"), null)


func test_moving_into_a_province_the_enemy_just_left_is_not_a_battle() -> void:
	var s := _state([
		["kingdom-1", "kingdom", "thornvale", ["spearmen"]],
		["beasts-2", "beasts", "wildmoor", ["war_bear"]],
	], {"thornvale": "kingdom"})
	var r := _resolve(s, {"kingdom": [MoveOrder.new("kingdom-1", "highcrag")], "beasts": [MoveOrder.new("beasts-2", "thornvale")]})
	assert_eq(_events_of(r.events, "battle").size() + _events_of(r.events, "border_battle").size(), 0)
	assert_eq(r.new_state.find_province("thornvale").owner, "beasts")
	assert_eq(r.new_state.find_army("kingdom-1").location, "highcrag")


# --- recruitment and income -----------------------------------------------------------------------

func test_recruitment_pays_in_order_and_joins_capital_army() -> void:
	var s := _state([["kingdom-1", "kingdom", "crownkeep", ["spearmen"]]])  # kingdom has 50 gold
	var r := _resolve(s, {"kingdom": [RecruitOrder.new("knights"), RecruitOrder.new("spearmen")]})
	var ns: GameState = r.new_state
	var rec := _events_of(r.events, "recruited")
	assert_eq(rec.size(), 2)
	assert_eq(rec[0].numbers, {"cost": 20, "gold_after": 30})
	assert_eq(rec[1].numbers, {"cost": 8, "gold_after": 22})
	assert_eq(ns.find_army("kingdom-1").units.size(), 3)
	assert_eq(ns.find_army("kingdom-1").units[1].type.id, "knights")
	# Recruitment comes before income: 50 - 28 + 12 (Crownkeep).
	assert_eq(_gold(ns, "kingdom"), 34)
	var phases: Array = r.events.map(func(e): return e.phase)
	assert_true(phases.find("recruitment") < phases.find("income"), "recruitment before income")


func test_recruit_forms_new_army_when_capital_is_empty() -> void:
	var s := _state([["kingdom-1", "kingdom", "westwatch", ["spearmen"]]], {"westwatch": "kingdom"})
	s.next_army_id = 7
	var r := _resolve(s, {"kingdom": [RecruitOrder.new("spearmen"), RecruitOrder.new("knight_captain")]})
	var ns: GameState = r.new_state
	var a := ns.find_army("kingdom-7")
	assert_true(a != null, "new army created with the next id")
	assert_eq(a.location, "crownkeep")
	assert_eq(a.units.size(), 1)
	assert_eq(a.commander.type.id, "knight_captain", "commander leads the army at the capital")
	# New ids never collide with ids already in use, even when the counter is behind.
	s.next_army_id = 1
	var r2 := _resolve(s, {"kingdom": [RecruitOrder.new("spearmen")]})
	assert_eq(r2.new_state.armies.back().id, "kingdom-2")
	var errs := []
	assert_true(r2.new_state.validate(errs), "ids stay unique: %s" % [errs])


func test_recruit_not_enough_gold_is_rejected() -> void:
	var s := _state([["kingdom-1", "kingdom", "crownkeep", ["spearmen"]]])
	var r := _resolve(s, {"kingdom": [RecruitOrder.new("knights"), RecruitOrder.new("knights"), RecruitOrder.new("knights")]})
	var rej := _events_of(r.events, "order_rejected")
	assert_eq(rej.size(), 1)
	assert_eq(rej[0].cause, "not_enough_gold")
	assert_eq(rej[0].phase, "recruitment")
	assert_eq(rej[0].reason, "Knights cost 20 gold, but you only have 10 gold left.")
	assert_eq(_events_of(r.events, "recruited").size(), 2)
	assert_eq(_gold(r.new_state, "kingdom"), 10 + 12)


func test_recruit_without_holding_capital_is_rejected() -> void:
	var s := _state([["beasts-1", "beasts", "crownkeep", ["tuskers"]]], {"crownkeep": "beasts"})
	var r := _resolve(s, {"kingdom": [RecruitOrder.new("spearmen")]})
	var rej := _events_of(r.events, "order_rejected")
	assert_eq(rej[0].cause, "capital_not_held")
	assert_true(rej[0].reason.contains("Crownkeep"), rej[0].reason)
	assert_eq(_gold(r.new_state, "kingdom"), 50, "no gold spent")


func test_capital_captured_this_turn_cancels_recruits() -> void:
	var s := _state([["beasts-1", "beasts", "westwatch", ["tuskers"]]])
	var r := _resolve(s, {"kingdom": [RecruitOrder.new("spearmen")], "beasts": [MoveOrder.new("beasts-1", "crownkeep")]})
	var ns: GameState = r.new_state
	assert_eq(ns.find_province("crownkeep").owner, "beasts")
	var cap: Dictionary = _events_of(r.events, "captured")[0]
	assert_true(cap.numbers.is_capital)
	assert_true(cap.text.contains("capital"), cap.text)
	assert_eq(_events_of(r.events, "order_rejected")[0].cause, "capital_not_held")
	assert_eq(_gold(ns, "kingdom"), 50, "kept gold, and no income from provinces")


func test_income_from_owned_provinces() -> void:
	var s := _state([], {"rivermarch": "kingdom", "bloodfen": "beasts", "ironspike": "beasts"})
	var r := _resolve(s, {})
	var ns: GameState = r.new_state
	var inc := _events_of(r.events, "income")
	assert_eq(inc.size(), 2)
	assert_eq(inc[0].factions, ["beasts"], "factions in sorted id order")
	assert_eq(inc[0].numbers.income, 7 + 5 + 8)
	assert_eq(inc[1].numbers, {"income": 21, "gold_before": 50, "gold_after": 71, "by_province": {"crownkeep": 12, "rivermarch": 9}})
	assert_eq(_gold(ns, "kingdom"), 71)
	assert_eq(_gold(ns, "beasts"), 60)
	assert_true(inc[1].text.contains("Crownkeep 12") and inc[1].text.contains("50 -> 71"), inc[1].text)


# --- invalid orders -------------------------------------------------------------------------------

func test_invalid_orders_are_rejected_with_reasons() -> void:
	var s := _state([
		["kingdom-1", "kingdom", "crownkeep", ["spearmen"]],
		["beasts-2", "beasts", "fangridge", ["tuskers"]],
	])
	var cases := [
		[MoveOrder.new("kingdom-1", "thornvale"), "not_adjacent", "Thornvale is not next to Crownkeep"],
		[MoveOrder.new("beasts-2", "ebonpeak"), "not_your_army", "belongs to Thornmane Clans"],
		[MoveOrder.new("kingdom-9", "westwatch"), "unknown_army", "no army 'kingdom-9'"],
		[MoveOrder.new("kingdom-1", "atlantis"), "unknown_province", "no province 'atlantis'"],
		[MoveOrder.new("kingdom-1", "crownkeep"), "already_there", "already in Crownkeep"],
	]
	for c in cases:
		var check := TurnResolver.check_move(s, "kingdom", c[0])
		assert_eq(check.get("code", ""), c[1])
		assert_true(check.get("reason", "").contains(c[2]), "%s: %s" % [c[1], check.get("reason", "")])
		var book := OrderBook.new()
		assert_eq(book.submit(s, "kingdom", c[0]), check.reason, "OrderBook gives the same reason")
		assert_eq(book.orders_for("kingdom").size(), 0)
	var recruit_cases := [
		[RecruitOrder.new("dragon"), "unknown_unit_type", "no unit type 'dragon'"],
		[RecruitOrder.new("tuskers"), "not_in_roster", "Tuskers belong to Thornmane Clans"],
	]
	for c in recruit_cases:
		var check := TurnResolver.check_recruit(s, "kingdom", c[0], 50)
		assert_eq(check.get("code", ""), c[1])
		assert_true(check.get("reason", "").contains(c[2]), check.get("reason", ""))

	# Duplicate move: the second order for the same army is rejected.
	var book := OrderBook.new()
	assert_eq(book.submit(s, "kingdom", MoveOrder.new("kingdom-1", "westwatch")), "")
	assert_true(book.submit(s, "kingdom", MoveOrder.new("kingdom-1", "highcrag")).contains("already has a move order"))
	assert_true(book.submit(s, "kingdom", "attack!").contains("not an order"))
	# OrderBook tracks gold across recruits: 50 gold buys two knights, not three.
	assert_eq(book.submit(s, "kingdom", RecruitOrder.new("knights")), "")
	assert_eq(book.submit(s, "kingdom", RecruitOrder.new("knights")), "")
	assert_eq(book.submit(s, "kingdom", RecruitOrder.new("knights")), "Knights cost 20 gold, but you only have 10 gold left.")
	assert_eq(book.orders_for("kingdom").size(), 3)

	# The resolver rejects the same things itself, without engine errors, and ignores them.
	var r := _resolve(s, {
		"kingdom": [MoveOrder.new("kingdom-1", "thornvale"), MoveOrder.new("beasts-2", "ebonpeak"),
			MoveOrder.new("kingdom-1", "westwatch"), MoveOrder.new("kingdom-1", "highcrag"), "attack!",
			RecruitOrder.new("dragon")],
		"pirates": [MoveOrder.new("kingdom-1", "westwatch")],
	})
	var codes: Array = _events_of(r.events, "order_rejected").map(func(e): return e.cause)
	assert_eq(codes, ["unknown_faction", "not_adjacent", "not_your_army", "duplicate_move", "unknown_order", "unknown_unit_type"])
	assert_eq(r.new_state.find_army("kingdom-1").location, "westwatch", "the one valid move happened")
	assert_eq(r.new_state.find_army("beasts-2").location, "fangridge")
	for e in _events_of(r.events, "order_rejected"):
		assert_true(e.text.contains("was rejected") or e.text.contains("ignored"), e.text)
	_assert_event_shape(r.events)


# --- forecasts ------------------------------------------------------------------------------------

func test_forecasts_match_resolution() -> void:
	var s := _state([
		["kingdom-1", "kingdom", "crownkeep", ["spearmen"]],
		["beasts-2", "beasts", "thornvale", ["tuskers"]],
	])
	var f := Forecast.move(s, "kingdom", MoveOrder.new("kingdom-1", "westwatch"))
	assert_true(f.ok)
	assert_eq(f.arrival_turn, s.current_turn + 1)
	assert_true(f.would_capture)
	assert_true(f.text.contains("capture it and gain 6 gold"), f.text)
	var bad := Forecast.move(s, "kingdom", MoveOrder.new("kingdom-1", "thornvale"))
	assert_false(bad.ok)
	assert_eq(bad.reason, TurnResolver.check_move(s, "kingdom", MoveOrder.new("kingdom-1", "thornvale")).reason)
	var s2 := _state([["kingdom-1", "kingdom", "highcrag", ["spearmen"]], ["beasts-2", "beasts", "thornvale", ["tuskers"]]])
	var contested := Forecast.move(s2, "kingdom", MoveOrder.new("kingdom-1", "thornvale"))
	assert_true(contested.enemy_present)
	assert_true(contested.text.contains("Thornmane Clans has an army there"), contested.text)
	assert_true(Forecast.move(s, "kingdom", MoveOrder.new("kingdom-1", "highcrag"), [MoveOrder.new("kingdom-1", "westwatch")]).code == "duplicate_move")

	assert_eq(Forecast.recruit_cost(s, "kingdom", "knights"), 20)
	assert_eq(Forecast.recruit_cost(s, "kingdom", "tuskers"), -1)
	assert_eq(Forecast.recruit_cost(s, "beasts", "warchief"), 40)

	var recruits := [RecruitOrder.new("knights"), RecruitOrder.new("crossbowmen"), RecruitOrder.new("knights"), RecruitOrder.new("knights")]
	var g := Forecast.gold_after_recruits(s, "kingdom", recruits)
	assert_eq(g.gold_now, 50)
	assert_eq(g.spent, 50)
	assert_eq(g.gold_after, 0)
	assert_eq(g.income, 12)
	assert_eq(g.gold_next_turn, 12)
	assert_true(g.results[2].ok, "exactly enough gold is enough")
	assert_false(g.results[3].ok)
	assert_true(g.text.contains("Not recruited: Knights cost 20 gold, but you only have 0 gold left."), g.text)
	var r := _resolve(s, {"kingdom": recruits})
	assert_eq(_events_of(r.events, "recruited").back().numbers.gold_after, g.gold_after, "forecast gold matches resolution")
	assert_eq(_gold(r.new_state, "kingdom"), g.gold_next_turn, "forecast next-turn gold matches when nothing changes hands")


# --- determinism and replay -----------------------------------------------------------------------

func test_scripted_turn_reads_sensibly() -> void:
	var r := _resolve(_scripted_state(), _scripted_orders(), 2026)
	_assert_event_shape(r.events)
	var types: Array = r.events.map(func(e): return e.type)
	# Phase order: orders, movement, battles, capture, recruitment, income.
	var last := -1
	for e in r.events:
		var idx := TurnResolver.PHASES.find(e.phase)
		assert_true(idx >= last, "phases in order (%s after %s)" % [e.phase, TurnResolver.PHASES[maxi(last, 0)]])
		last = idx
	assert_eq(types.count("order_rejected"), 2, "non-adjacent move and third knight")
	assert_eq(types.count("border_battle"), 1)
	assert_eq(types.count("battle"), 1)
	assert_true(types.count("captured") >= 2)
	assert_eq(types.count("recruited"), 3)
	assert_eq(types.count("income"), 2)
	var blackwood: Dictionary = _events_of(r.events, "battle")[0]
	assert_eq(blackwood.provinces, ["blackwood"])
	assert_eq(blackwood.numbers.winner, "kingdom", "knights (20) beat tuskers (17)")


func test_replay_is_identical_and_independent_of_order_supply() -> void:
	var s := _scripted_state()
	var first := _resolve(s, _scripted_orders(), 2026)
	var want_state := var_to_str(first.new_state.to_dict())
	var want_events := var_to_str(first.events)
	for i in 5:
		var again := _resolve(s, _scripted_orders(), 2026)
		assert_eq(var_to_str(again.new_state.to_dict()), want_state, "run %d state" % i)
		assert_eq(var_to_str(again.events), want_events, "run %d events" % i)
	# Same orders supplied beasts-first.
	var o := _scripted_orders()
	var reversed := {"beasts": o.beasts, "kingdom": o.kingdom}
	var swapped := _resolve(s, reversed, 2026)
	assert_eq(var_to_str(swapped.new_state.to_dict()), want_state, "faction order doesn't matter")
	assert_eq(var_to_str(swapped.events), want_events)
	# The same state with armies stored in a different array order gives the same result.
	var shuffled := s.deep_copy()
	shuffled.armies.reverse()
	shuffled.provinces.reverse()
	var r2 := _resolve(shuffled, _scripted_orders(), 2026)
	assert_eq(var_to_str(r2.events), want_events, "army/province array order doesn't matter")
	# Several turns in a row replay identically too.
	var chain_a := s
	var chain_b := s.deep_copy()
	for t in 4:
		chain_a = _resolve(chain_a, {}, TurnResolver.seed_for_turn(chain_a)).new_state
		chain_b = _resolve(chain_b, {}, TurnResolver.seed_for_turn(chain_b)).new_state
	assert_eq(var_to_str(chain_a.to_dict()), var_to_str(chain_b.to_dict()))


func test_json_replay_gives_same_result() -> void:
	var s := _scripted_state()
	for i in 3:
		s.rng.randi()
	var direct := _resolve(s, _scripted_orders(), 77)
	var book := OrderBook.new()
	var o := _scripted_orders()
	book._orders = o  # includes the invalid orders so they replay too
	var saved := JSON.stringify({"state": s.to_dict(), "orders": book.to_dict(), "seed": Serial.int64_to_str(77)})
	var loaded: Dictionary = JSON.parse_string(saved)
	var errs := []
	var s2 := GameState.from_dict(loaded.state, errs)
	assert_eq(errs, [])
	var orders2 := OrderBook.orders_from_dict(loaded.orders, errs)
	assert_eq(errs, [])
	var replay := _resolve(s2, orders2, Serial.to_int(loaded.seed))
	assert_eq(var_to_str(replay.new_state.to_dict()), var_to_str(direct.new_state.to_dict()))
	assert_eq(var_to_str(replay.events), var_to_str(direct.events))
	# And the new state itself survives JSON for the next turn.
	var next_loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(direct.new_state.to_dict())), errs)
	assert_eq(var_to_str(next_loaded.to_dict()), var_to_str(direct.new_state.to_dict()))


func test_json_roundtrip_keeps_ints_as_ints() -> void:
	var s := GameState.new(-8070450532247928832)  # a full 64-bit seed
	s.current_turn = 3
	s.find_faction("kingdom").gold = 123
	s.armies[0].units[0].current_hp = 4
	for i in 7:
		s.rng.randi()
	var d := s.to_dict()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(d))
	assert_eq(typeof(parsed.current_turn), TYPE_FLOAT, "sanity: JSON alone turns ints into floats")
	var errs := []
	var r := GameState.from_dict(parsed, errs)
	assert_eq(errs, [])
	var rd := r.to_dict()
	assert_eq(var_to_str(rd), var_to_str(d), "exact match, types included")
	assert_eq(typeof(rd.current_turn), TYPE_INT)
	assert_eq(typeof(rd.next_army_id), TYPE_INT)
	assert_eq(typeof(rd.factions[0].gold), TYPE_INT)
	assert_eq(typeof(rd.provinces[0].income), TYPE_INT)
	assert_eq(typeof(rd.armies[0].units[0].current_hp), TYPE_INT)
	assert_eq(typeof(rd.factions[0].unit_types[0].cost), TYPE_INT)
	assert_eq(r.seed_value, s.seed_value)
	assert_eq(r.rng.get_seed(), s.rng.get_seed())
	assert_eq(r.rng.get_state(), s.rng.get_state(), "64-bit RNG state exact")
	for i in 50:
		assert_eq(r.rng.randi(), s.rng.randi(), "RNG continues the same sequence (roll %d)" % i)
	# SeededRNG on its own, over many states (many of them above 2^53 or negative).
	var a := SeededRNG.new(123456789)
	for i in 200:
		a.randi()
		var b := SeededRNG.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
		assert_eq(b.get_state(), a.get_state())


# --- capitals, load validation, map fairness ------------------------------------------------------

func test_capitals_come_from_faction_capital_field() -> void:
	var s := GameState.new(5)
	assert_eq(s.find_province("crownkeep").owner, "kingdom")
	assert_eq(s.find_province("fangridge").owner, "beasts")
	assert_eq(s.armies.filter(func(a): return a.owner == "kingdom")[0].location, "crownkeep")
	assert_eq(s.armies.filter(func(a): return a.owner == "beasts")[0].location, "fangridge")
	# Swap the capital fields: map order would still give kingdom Crownkeep, the field must win.
	for p in s.provinces:
		p.owner = ""
	s.find_faction("kingdom").capital = "fangridge"
	s.find_faction("beasts").capital = "crownkeep"
	var errs := []
	assert_true(s.place_starting_armies(errs))
	assert_eq(errs, [])
	assert_eq(s.find_province("fangridge").owner, "kingdom")
	assert_eq(s.find_province("crownkeep").owner, "beasts")
	assert_eq(s.armies.filter(func(a): return a.owner == "kingdom")[0].location, "fangridge")
	# Recruiting uses faction.capital as well.
	var r := _resolve(s, {"kingdom": [RecruitOrder.new("spearmen")]})
	assert_eq(_events_of(r.events, "recruited")[0].provinces, ["fangridge"])


func test_load_validation_rejects_bad_data_in_plain_language() -> void:
	var good := GameState.new(1).to_dict()
	var cases := [
		[func(d): d.provinces[1].owner = "pirates", "owned by 'pirates', which is not a faction"],
		[func(d): d.provinces[1].neighbors.append("atlantis"), "neighbor 'atlantis', which is not a province"],
		[func(d): d.provinces[0].neighbors.append("deepwood"), "'deepwood' does not list 'crownkeep' back"],
		[func(d): d.factions[0].capital = "atlantis", "capital 'atlantis', which is not a province"],
		[func(d): d.factions[0].capital = "westwatch", "not marked as a capital"],
		[func(d): d.factions[0].capital = "", "has no capital"],
		[func(d): d.factions[1].capital = "crownkeep", "both have capital 'crownkeep'"],
		[func(d): d.armies[1].owner = "pirates", "belongs to 'pirates'"],
		[func(d): d.armies[1].id = d.armies[0].id, "share the id"],
	]
	for c in cases:
		var d: Dictionary = good.duplicate(true)
		c[0].call(d)
		var errs := []
		assert_eq(GameState.from_dict(d, errs), null, "rejected: %s" % c[1])
		assert_eq(errs.size(), 1, "one error for %s: %s" % [c[1], errs])
		assert_true(errs.size() > 0 and errs[0].contains(c[1]), "message '%s' in %s" % [c[1], errs])
	var errs := []
	assert_true(GameState.from_dict(good, errs) != null)
	assert_eq(errs, [])
	# The resolver refuses an invalid state the same way, without engine errors.
	var bad := GameState.new(1)
	bad.provinces[1].owner = "pirates"
	var r := TurnResolver.resolve(bad, {}, 1)
	assert_eq(r.new_state, null)
	assert_true(r.errors[0].contains("pirates"))


func test_map_capitals_are_fair() -> void:
	var s := GameState.new(1)
	var crown := s.find_province("crownkeep")
	var fang := s.find_province("fangridge")
	assert_eq(crown.neighbors.size(), 3)
	assert_eq(fang.neighbors.size(), crown.neighbors.size(), "both capitals have the same neighbor count")
	# Mirrored paths: each capital is as far from its center hub and from the enemy capital.
	assert_eq(_distance(s, "crownkeep", "thornvale"), _distance(s, "fangridge", "wildmoor"))
	assert_eq(_distance(s, "crownkeep", "wildmoor"), _distance(s, "fangridge", "thornvale"))
	assert_eq(_distance(s, "crownkeep", "fangridge"), 5)
	var errs := []
	assert_true(s.validate(errs), "default map validates: %s" % [errs])


func _distance(s: GameState, from: String, to: String) -> int:
	var dist := {from: 0}
	var queue := [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == to:
			return dist[cur]
		for n in s.find_province(cur).neighbors:
			if not dist.has(n):
				dist[n] = dist[cur] + 1
				queue.append(n)
	return -1


func test_codex_covers_the_rules() -> void:
	for id in ["phase_order", "orders", "move", "same_province", "swap", "hold", "defended", "undefended", "battle_stub", "capture", "recruit", "income"]:
		assert_false(RulesCodex.text(id).is_empty(), "codex entry %s" % id)
		assert_false(RulesCodex.entry(id).get("title", "").is_empty())
