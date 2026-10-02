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


func test_swap_winner_then_fights_the_holder_of_its_destination() -> void:
	# Kingdom knights + Knight Captain (46) Thornvale -> Wildmoor swap with beasts fangthrowers (12)
	# Wildmoor -> Thornvale, while a beasts war bear (25) holds Wildmoor. Border battle first, then the
	# winner meets the holder in Wildmoor, and the holder defends.
	var s := _state([
		["kingdom-1", "kingdom", "thornvale", ["knights", "knight_captain"]],
		["beasts-2", "beasts", "wildmoor", ["fangthrowers"]],
		["beasts-3", "beasts", "wildmoor", ["war_bear"]],
	], {"thornvale": "kingdom", "wildmoor": "beasts"})
	var r := _resolve(s, {"kingdom": [MoveOrder.new("kingdom-1", "wildmoor")], "beasts": [MoveOrder.new("beasts-2", "thornvale")]})
	var ns: GameState = r.new_state
	var types: Array = r.events.map(func(e): return e.type)
	assert_eq(types, ["border_battle", "army_moved", "battle", "captured", "income", "income"])
	var border: Dictionary = r.events[0]
	assert_eq(border.provinces, ["thornvale", "wildmoor"])
	assert_eq(border.armies, ["beasts-2", "kingdom-1"], "only the swapping armies fight on the border")
	assert_eq(border.numbers.defender, "")
	assert_eq(border.numbers.winner, "kingdom")
	assert_eq(border.numbers.strengths, {"beasts": 12, "kingdom": 46})
	assert_eq(border.numbers.destroyed, ["beasts-2"])
	assert_eq(r.events[1].cause, "won_border_battle")
	var b: Dictionary = r.events[2]
	assert_eq(b.provinces, ["wildmoor"])
	assert_eq(b.cause, "held_vs_arrival")
	assert_eq(b.numbers.defender, "beasts", "the war bear held Wildmoor")
	assert_eq(b.armies, ["beasts-3", "kingdom-1"])
	assert_eq(b.numbers.strengths, {"beasts": 25, "kingdom": 46})
	assert_eq(b.numbers.winner, "kingdom")
	assert_eq(b.numbers.destroyed, ["beasts-3"])
	assert_true(b.text.contains("In Wildmoor, Thornmane Clans held against Aurel Crown"), b.text)
	assert_eq(r.events[3].provinces, ["wildmoor"])
	assert_eq(r.events[3].cause, "battle_victory")
	assert_eq(ns.armies.size(), 1)
	assert_eq(ns.find_army("kingdom-1").location, "wildmoor")
	assert_eq(ns.find_province("wildmoor").owner, "kingdom")
	assert_eq(ns.find_province("thornvale").owner, "kingdom", "the swap loser never reached Thornvale")
	_assert_event_shape(r.events)


func test_same_faction_armies_swapping_do_not_fight() -> void:
	var s := _state([
		["kingdom-1", "kingdom", "thornvale", ["spearmen"]],
		["kingdom-2", "kingdom", "highcrag", ["knights"]],
	], {"thornvale": "kingdom", "highcrag": "kingdom"})
	var r := _resolve(s, {"kingdom": [MoveOrder.new("kingdom-1", "highcrag"), MoveOrder.new("kingdom-2", "thornvale")]})
	var ns: GameState = r.new_state
	assert_eq(_events_of(r.events, "border_battle").size(), 0, "no border battle between friends")
	assert_eq(_events_of(r.events, "battle").size(), 0)
	var moved := _events_of(r.events, "army_moved")
	assert_eq(moved.size(), 2)
	for m in moved:
		assert_eq(m.cause, "order")
		assert_eq(m.phase, "movement")
	assert_eq(ns.armies.size(), 2, "nobody is destroyed")
	assert_eq(ns.find_army("kingdom-1").location, "highcrag")
	assert_eq(ns.find_army("kingdom-2").location, "thornvale")
	assert_eq(ns.find_army("kingdom-1").units.size(), 1)
	assert_eq(ns.find_army("kingdom-2").units.size(), 1)


func test_move_into_undefended_enemy_province_captures_it() -> void:
	var s := _state([["kingdom-1", "kingdom", "wildmoor", ["spearmen"]]], {"ironspike": "beasts", "wildmoor": "kingdom"})
	var r := _resolve(s, {"kingdom": [MoveOrder.new("kingdom-1", "ironspike")]})
	var ns: GameState = r.new_state
	assert_eq(ns.find_province("ironspike").owner, "kingdom")
	var cap := _events_of(r.events, "captured")
	assert_eq(cap.size(), 1)
	assert_eq(cap[0].cause, "undefended_enemy")
	assert_eq(cap[0].factions, ["kingdom", "beasts"])
	assert_eq(cap[0].numbers.income, 5)
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
	assert_eq(rec[0].numbers, {"cost": 20, "gold_after": 30, "new_army": false})
	assert_eq(rec[1].numbers, {"cost": 8, "gold_after": 22, "new_army": false})
	# Both join the army that was already at the capital, and say so.
	assert_eq(rec[0].armies, ["kingdom-1"])
	assert_eq(rec[1].armies, ["kingdom-1"])
	assert_true(rec[0].text.ends_with("They joined the Aurel Crown army at Crownkeep (2 units, no commander)."), rec[0].text)
	assert_true(rec[1].text.ends_with("They joined the Aurel Crown army at Crownkeep (3 units, no commander)."), rec[1].text)
	assert_false(rec[0].text.contains("new army"), rec[0].text)
	assert_eq(ns.armies.size(), 1, "no new army")
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


## Playtest A4: the recruit that forms an army says so, and the next one joins that same army.
func test_recruit_text_forms_then_joins_new_army() -> void:
	var s := GameState.new(1)
	# The kingdom's starting army: "kingdom-1" with the default data, found by owner so the test
	# doesn't depend on the order of factions in data/factions.gd.
	var start_id: String = s.armies.filter(func(a): return a.owner == "kingdom")[0].id
	var r := _resolve(s, {"kingdom": [MoveOrder.new(start_id, "westwatch"), RecruitOrder.new("spearmen"), RecruitOrder.new("spearmen")]}, 1)
	var ns: GameState = r.new_state
	var rec := _events_of(r.events, "recruited")
	assert_eq(rec.size(), 2)
	var new_id: String = rec[0].armies[0] if rec.size() > 0 else ""
	assert_eq(rec[0].armies, [new_id])
	assert_true(new_id.begins_with("kingdom-"), new_id)
	assert_eq(s.find_army(new_id), null, "the army did not exist before the turn")
	assert_eq(rec[0].numbers.new_army, true)
	assert_eq(rec[0].text, "Aurel Crown recruited Spearmen at Crownkeep for 8 gold (42 gold left). They form a new army: the Aurel Crown army at Crownkeep (1 unit, no commander).")
	assert_eq(rec[1].armies, [new_id], "second recruit joins the army the first one formed")
	assert_eq(rec[1].numbers.new_army, false)
	assert_eq(rec[1].text, "Aurel Crown recruited Spearmen at Crownkeep for 8 gold (34 gold left). They joined the Aurel Crown army at Crownkeep (2 units, no commander).")
	var a := ns.find_army(new_id)
	assert_eq(a.location, "crownkeep")
	assert_eq(a.units.size(), 2)
	assert_eq(ns.find_army(start_id).location, "westwatch")
	assert_eq(ns.find_army(start_id).units.size(), 3, "the army that left gets no recruits")


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
	assert_eq(inc[0].numbers.income, 12 + 9 + 5)  # Fangridge, Bloodfen, Ironspike
	assert_eq(inc[1].numbers, {"income": 21, "gold_before": 50, "gold_after": 71, "by_province": {"crownkeep": 12, "rivermarch": 9}})
	assert_eq(_gold(ns, "kingdom"), 71)
	assert_eq(_gold(ns, "beasts"), 66)
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
		[MoveOrder.new("kingdom-9", "westwatch"), "unknown_army", "That army no longer exists"],
		[MoveOrder.new("kingdom-1", "atlantis"), "unknown_province", "not a province on the map"],
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
		[RecruitOrder.new("dragon"), "unknown_unit_type", "not a unit type in this game"],
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


# --- player-facing text ---------------------------------------------------------------------------

## Fails for any internal id in `text`: army ids, bare faction ids, or province ids (case-sensitive,
## so the display name "Crownkeep" is fine but "crownkeep" is not).
func _assert_no_raw_ids(text: String) -> void:
	var army_ids := RegEx.create_from_string("\\b(kingdom|beasts)-\\d+\\b")
	var faction_ids := RegEx.create_from_string("\\b(kingdom|beasts)\\b")
	var pids := []
	for p in MapData.PROVINCES:
		pids.append(p.id)
	var province_ids := RegEx.create_from_string("\\b(%s)\\b" % "|".join(pids))
	assert_true(army_ids.search(text) == null, "no army id in: %s" % text)
	assert_true(faction_ids.search(text) == null, "no faction id in: %s" % text)
	assert_true(province_ids.search(text) == null, "no province id in: %s" % text)


func test_event_text_uses_player_facing_names() -> void:
	var texts := []
	# Turn 1: plain move, swap, same-province battle, captures, recruits (one rejected), bad orders.
	var s := _scripted_state()
	var orders := _scripted_orders()
	orders.kingdom.append_array([MoveOrder.new("kingdom-9", "westwatch"), MoveOrder.new("beasts-4", "ebonpeak"),
		MoveOrder.new("kingdom-1", "atlantis"), MoveOrder.new("kingdom-1", "crownkeep"),
		MoveOrder.new("kingdom-1", "highcrag"), "attack!", RecruitOrder.new("dragon"), RecruitOrder.new("tuskers")])
	orders["pirates"] = [MoveOrder.new("kingdom-1", "westwatch")]
	var r := _resolve(s, orders, 2026)
	var events: Array = r.events.duplicate()
	var types := {}
	for e in r.events:
		types[e.type] = true
	for t in ["army_moved", "border_battle", "battle", "captured", "recruited", "order_rejected", "income"]:
		assert_true(types.has(t), "turn 1 has a %s event" % t)
	# Turn 2: every army moves to its first neighbor, and each side recruits (the third knight fails).
	var s2: GameState = r.new_state
	var orders2 := {"kingdom": [RecruitOrder.new("knights"), RecruitOrder.new("knights"), RecruitOrder.new("knights")],
		"beasts": [RecruitOrder.new("warchief")]}
	for a in TurnResolver._sorted_armies(s2):
		orders2[a.owner].append(MoveOrder.new(a.id, s2.find_province(a.location).neighbors[0]))
	var r2 := _resolve(s2, orders2, TurnResolver.seed_for_turn(s2))
	events.append_array(r2.events)
	# Turn 3: the enemy takes the kingdom capital while it recruits (cancelled).
	var s3 := _state([["beasts-1", "beasts", "westwatch", ["tuskers"]]])
	var r3 := _resolve(s3, {"kingdom": [RecruitOrder.new("spearmen")], "beasts": [MoveOrder.new("beasts-1", "crownkeep")]})
	events.append_array(r3.events)
	# Two look-alike armies of one faction in one province get ordinals, never ids.
	var twins := _state([["kingdom-1", "kingdom", "crownkeep", ["spearmen"]], ["kingdom-2", "kingdom", "crownkeep", ["spearmen"]]])
	var r4 := _resolve(twins, {"kingdom": [MoveOrder.new("kingdom-2", "westwatch"), MoveOrder.new("kingdom-2", "highcrag"),
		RecruitOrder.new("spearmen")]})
	events.append_array(r4.events)
	var moved: Dictionary = _events_of(r4.events, "army_moved")[0]
	assert_eq(moved.text, "The second Aurel Crown army at Crownkeep (1 unit, no commander) moved to Westwatch.")
	assert_eq(moved.armies, ["kingdom-2"], "the id stays in the structured field")
	assert_true(_events_of(r4.events, "order_rejected")[0].reason.begins_with("The second Aurel Crown army at Crownkeep"))
	assert_eq(TurnResolver.army_label(twins, twins.find_army("kingdom-1")), "first Aurel Crown army at Crownkeep (1 unit, no commander)")
	assert_eq(TurnResolver.army_label(s, s.find_army("kingdom-1")), "Aurel Crown army at Crownkeep (1 unit, led by Knight Captain)")

	for e in events:
		texts.append(e.text)
		if e.has("reason"):
			texts.append(e.reason)
			assert_true(e.text.contains(e.reason), "the reason is in the event text")
	# Forecasts and OrderBook reasons are shown to players too.
	for order in [MoveOrder.new("kingdom-1", "westwatch"), MoveOrder.new("kingdom-2", "wildmoor"), MoveOrder.new("kingdom-1", "thornvale"),
			MoveOrder.new("beasts-4", "thornvale"), MoveOrder.new("kingdom-9", "westwatch"), MoveOrder.new("kingdom-1", "atlantis")]:
		texts.append(Forecast.move(s, "kingdom", order).text)
		texts.append(OrderBook.new().submit(s, "kingdom", order))
	texts.append(Forecast.gold_after_recruits(s, "kingdom", [RecruitOrder.new("knights"), RecruitOrder.new("tuskers"),
		RecruitOrder.new("dragon"), RecruitOrder.new("knights"), RecruitOrder.new("knights")]).text)
	texts.append(Forecast.gold_after_recruits(s3, "beasts", [RecruitOrder.new("warchief")]).text)
	texts.append(OrderBook.new().submit(s, "pirates", MoveOrder.new("kingdom-1", "westwatch")))

	var all_text := "\n".join(texts)
	for t in texts:
		_assert_no_raw_ids(t)
	for name in ["Aurel Crown", "Thornmane Clans", "Crownkeep", "Wildmoor", "Thornvale", "Blackwood", "Rivermarch"]:
		assert_true(all_text.contains(name), "display name %s appears" % name)
	assert_true(all_text.contains("Aurel Crown army at "), "armies are named by faction and place")


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
	# Both capitals are empty at recruitment: the first recruit forms an army, the next joins it.
	# Factions recruit in id order, so the beasts' tuskers come first.
	var rec := _events_of(r.events, "recruited")
	assert_eq(rec.map(func(e): return e.factions[0]), ["beasts", "kingdom", "kingdom"])
	assert_true(rec[0].text.ends_with("They form a new army: the Thornmane Clans army at Fangridge (1 unit, no commander)."), rec[0].text)
	assert_eq(rec[0].numbers.new_army, true)
	assert_true(rec[1].text.ends_with("They form a new army: the Aurel Crown army at Crownkeep (1 unit, no commander)."), rec[1].text)
	assert_true(rec[2].text.ends_with("They joined the Aurel Crown army at Crownkeep (2 units, no commander)."), rec[2].text)
	assert_eq(rec[2].armies, rec[1].armies, "the second knights join the army the first formed")
	assert_eq([rec[1].numbers.new_army, rec[2].numbers.new_army], [true, false])
	assert_ne(rec[0].armies, rec[1].armies)


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


## A busy turn for the order-independence test: several moves per faction, a three-army battle in
## Thornvale, captures, recruits at a capital with two armies (kingdom) and at an empty one (beasts).
func _busy_state() -> GameState:
	return _state([
		["kingdom-1", "kingdom", "crownkeep", ["spearmen"]],
		["kingdom-2", "kingdom", "crownkeep", ["crossbowmen"]],
		["kingdom-3", "kingdom", "highcrag", ["knights"]],
		["kingdom-4", "kingdom", "rivermarch", ["spearmen"]],
		["kingdom-5", "kingdom", "westwatch", ["crossbowmen"]],
		["kingdom-8", "kingdom", "stonegate", ["knights"]],
		["beasts-6", "beasts", "wildmoor", ["fangthrowers"]],
		["beasts-7", "beasts", "wildmoor", ["tuskers"]],
		["beasts-9", "beasts", "fangridge", ["tuskers"]],
		["beasts-10", "beasts", "ironspike", ["war_bear"]],
	], {"stonegate": "kingdom", "rivermarch": "kingdom", "westwatch": "kingdom", "highcrag": "kingdom", "ironspike": "beasts"})


## Move orders for _busy_state, listed in `perm` order. Recruits keep their places in the list.
func _busy_orders(kingdom_perm: Array, beasts_perm: Array) -> Dictionary:
	var k := [MoveOrder.new("kingdom-3", "thornvale"), MoveOrder.new("kingdom-4", "greenglade"),
		MoveOrder.new("kingdom-5", "stonegate"), MoveOrder.new("kingdom-8", "thornvale")]
	var b := [MoveOrder.new("beasts-6", "thornvale"), MoveOrder.new("beasts-7", "thornvale"),
		MoveOrder.new("beasts-9", "bloodfen"), MoveOrder.new("beasts-10", "wildmoor")]
	return {
		"kingdom": [k[kingdom_perm[0]], RecruitOrder.new("spearmen"), k[kingdom_perm[1]], k[kingdom_perm[2]],
			RecruitOrder.new("knights"), k[kingdom_perm[3]]],
		"beasts": [RecruitOrder.new("tuskers"), b[beasts_perm[0]], b[beasts_perm[1]], RecruitOrder.new("fangthrowers"),
			b[beasts_perm[2]], b[beasts_perm[3]]],
	}


## to_dict() with armies sorted by id, for comparing states whose army arrays started in another order.
func _canonical(s: GameState) -> String:
	var d := s.to_dict()
	d.armies.sort_custom(func(a, b): return a.id < b.id)
	return var_to_str(d)


func test_result_ignores_order_list_and_army_array_order() -> void:
	var base_state := _busy_state()
	var base := _resolve(base_state, _busy_orders([0, 1, 2, 3], [0, 1, 2, 3]), 404)
	var want_events := var_to_str(base.events)
	var want_state := var_to_str(base.new_state.to_dict())
	# Sanity: the turn has everything the ordering rules touch.
	var types: Array = base.events.map(func(e): return e.type)
	assert_eq(types.count("army_moved"), 8)
	assert_eq(types.count("battle"), 1)
	assert_eq(types.count("recruited"), 4)
	assert_true(types.count("captured") >= 3)
	var battle: Dictionary = _events_of(base.events, "battle")[0]
	assert_eq(battle.armies, ["beasts-6", "beasts-7", "kingdom-3", "kingdom-8"])
	assert_eq(battle.numbers.winner, "kingdom", "knights x2 (40) beat fangthrowers + tuskers (29)")
	var thornvale: Dictionary = _events_of(base.events, "captured").filter(func(e): return e.provinces == ["thornvale"])[0]
	assert_eq(thornvale.armies, ["kingdom-3", "kingdom-8"])
	var rec := _events_of(base.events, "recruited").filter(func(e): return e.factions == ["kingdom"])
	assert_eq(rec[0].armies, ["kingdom-1"], "recruits join the first army (by id) at the capital")
	assert_eq(base.new_state.find_army("kingdom-1").units.size(), 3)
	assert_eq(base.new_state.find_army("kingdom-2").units.size(), 1)

	# (a) Move orders shuffled within each faction (fixed permutations), recruits kept in order.
	for perms in [[[3, 2, 1, 0], [3, 2, 1, 0]], [[1, 3, 0, 2], [2, 0, 3, 1]], [[2, 0, 3, 1], [1, 3, 2, 0]]]:
		var r := _resolve(base_state, _busy_orders(perms[0], perms[1]), 404)
		assert_eq(var_to_str(r.events), want_events, "events with move orders %s" % [perms])
		assert_eq(var_to_str(r.new_state.to_dict()), want_state, "state with move orders %s" % [perms])

	# (b) The same state with its armies array reversed or rotated.
	var want_canonical := _canonical(base.new_state)
	for how in ["reverse", "rotate"]:
		var s := _busy_state()
		if how == "reverse":
			s.armies.reverse()
		else:
			for i in 3:
				s.armies.push_back(s.armies.pop_front())
		var r := _resolve(s, _busy_orders([0, 1, 2, 3], [0, 1, 2, 3]), 404)
		assert_eq(var_to_str(r.events), want_events, "events with armies %sd" % how)
		assert_eq(_canonical(r.new_state), want_canonical, "state with armies %sd" % how)
		# Both at once.
		var both := _resolve(s, _busy_orders([2, 0, 3, 1], [1, 3, 2, 0]), 404)
		assert_eq(var_to_str(both.events), want_events, "events with armies %sd and orders shuffled" % how)
		assert_eq(_canonical(both.new_state), want_canonical)


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


func test_json_roundtrip_keeps_extreme_seeds_exact() -> void:
	# 2^53 + 1 is the first int a double can't hold; INT64_MAX and INT64_MIN are the extremes.
	for seed_value in [9007199254740993, 9223372036854775807, -9223372036854775807 - 1]:
		var s := GameState.new(seed_value)
		var errs := []
		var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())), errs)
		assert_eq(errs, [])
		assert_eq(loaded.seed_value, seed_value, "seed %d survives JSON exactly" % seed_value)
		assert_eq(loaded.seed_value, s.seed_value)
		assert_eq(TurnResolver.seed_for_turn(loaded), TurnResolver.seed_for_turn(s))
		var orders := {"kingdom": [MoveOrder.new("kingdom-1", "westwatch"), RecruitOrder.new("spearmen")],
			"beasts": [MoveOrder.new("beasts-2", "ebonpeak")]}
		var before := _resolve(s, orders, TurnResolver.seed_for_turn(s))
		var after := _resolve(loaded, orders, TurnResolver.seed_for_turn(loaded))
		assert_eq(var_to_str(after.new_state.to_dict()), var_to_str(before.new_state.to_dict()), "same new state for seed %d" % seed_value)
		assert_eq(var_to_str(after.events), var_to_str(before.events), "same events for seed %d" % seed_value)


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


## The entry with this id in a to_dict() list (factions, provinces, armies), whatever the data order.
func _by_id(list: Array, id: String) -> Dictionary:
	for entry in list:
		if entry.id == id:
			return entry
	assert_true(false, "no entry '%s'" % id)
	return {}


func test_load_validation_rejects_bad_data_in_plain_language() -> void:
	var good := GameState.new(1).to_dict()
	var cases := [
		[func(d): _by_id(d.provinces, "westwatch").owner = "pirates", "owned by 'pirates', which is not a faction"],
		[func(d): _by_id(d.provinces, "westwatch").neighbors.append("atlantis"), "neighbor 'atlantis', which is not a province"],
		[func(d): _by_id(d.provinces, "crownkeep").neighbors.append("deepwood"), "'deepwood' does not list 'crownkeep' back"],
		[func(d): _by_id(d.factions, "kingdom").capital = "atlantis", "capital 'atlantis', which is not a province"],
		[func(d): _by_id(d.factions, "kingdom").capital = "westwatch", "not marked as a capital"],
		[func(d): _by_id(d.factions, "kingdom").capital = "", "has no capital"],
		[func(d): _by_id(d.factions, "beasts").capital = "crownkeep", "both have capital 'crownkeep'"],
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
	bad.find_province("westwatch").owner = "pirates"
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


## Both directions of MIRROR: province id -> its mirror's id.
func _mirror_of() -> Dictionary:
	var out := {}
	for pid in MIRROR:
		out[pid] = MIRROR[pid]
		out[MIRROR[pid]] = pid
	return out


func test_map_is_a_full_mirror() -> void:
	var s := GameState.new(1)
	var mirror := _mirror_of()
	# The mapping covers every province exactly once and nothing else.
	assert_eq(mirror.size(), 14, "7 pairs, no province in two pairs")
	assert_eq(mirror.size(), s.provinces.size())
	for p in s.provinces:
		assert_true(mirror.has(p.id), "%s has a mirror" % p.id)
	for pid in MIRROR:
		assert_ne(pid, MIRROR[pid])
	# Every link a-b has the mirrored link mirror(a)-mirror(b), so the neighbor counts match too.
	var links := 0
	for p in s.provinces:
		var m := s.find_province(mirror.get(p.id, ""))
		if m == null:
			continue
		assert_eq(m.neighbors.size(), p.neighbors.size(), "%s and %s have as many neighbors" % [p.id, m.id])
		for n in p.neighbors:
			links += 1
			assert_true(m.neighbors.has(mirror.get(n, "")), "link %s-%s mirrors to %s-%s" % [p.id, n, m.id, mirror.get(n, "?")])
		# Terrain, forts, income and capitals match within each pair.
		assert_eq(m.terrain, p.terrain, "%s and %s have the same terrain" % [p.id, m.id])
		assert_eq(m.has_fort, p.has_fort, "%s and %s both have a fort or neither" % [p.id, m.id])
		assert_eq(m.income, p.income)
		assert_eq(m.is_capital, p.is_capital)
	assert_eq(links, 38, "19 links, each listed from both ends")


## Each kingdom-side province and its mirror on the beasts side (see data/map.gd).
const MIRROR := {
	"crownkeep": "fangridge", "westwatch": "ebonpeak", "highcrag": "ironspike", "rivermarch": "bloodfen",
	"stonegate": "blackwood", "greenglade": "deepwood", "thornvale": "wildmoor",
}


func test_map_income_is_mirrored() -> void:
	var s := GameState.new(1)
	var paired := {}
	var kingdom_half := 0
	var beasts_half := 0
	for pid in MIRROR:
		var p := s.find_province(pid)
		var m := s.find_province(MIRROR[pid])
		assert_true(p != null and m != null, "mirror pair %s / %s exists" % [pid, MIRROR[pid]])
		assert_eq(p.income, m.income, "%s and %s earn the same" % [p.name, m.name])
		assert_eq(p.is_capital, m.is_capital, "%s and %s are both capitals or neither" % [p.name, m.name])
		kingdom_half += p.income
		beasts_half += m.income
		paired[pid] = true
		paired[MIRROR[pid]] = true
	assert_eq(paired.size(), s.provinces.size(), "every province is in exactly one mirror pair")
	assert_eq(kingdom_half, beasts_half, "both halves of the map earn the same per turn")
	# Holding your whole half pays the same whichever faction you are.
	for p in s.provinces:
		p.owner = "kingdom" if MIRROR.has(p.id) else "beasts"
	assert_eq(TurnResolver.income_of(s, "kingdom").total, TurnResolver.income_of(s, "beasts").total)


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
