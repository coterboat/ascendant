extends "res://tests/test_case.gd"
## M3c S-1a (#98) acceptance, tests/test_siege_orders.gd: round trips for every new field and order, a recorded siege
## game that replays to an identical state, and OrderBook's re-checks of storms and sallies (design/M3C_SIEGES.md §12).

const F := preload("res://tests/siege_fixtures.gd")
const CROWN := "kingdom"
const CLANS := "beasts"


## Turn 6 is being ordered; the Clans have besieged the Crown's Stonegate since turn 4.
func _besieged() -> GameState:
	var s := F.state([
		["kingdom-1", CROWN, "stonegate", F.units("spearmen", 3) + ["knight_captain"]],
		["kingdom-2", CROWN, "stonegate", ["crossbowmen"]],
		["kingdom-3", CROWN, "westwatch", F.units("knights", 2)],
		["beasts-4", CLANS, "stonegate", F.units("tuskers", 4), 1],
		["beasts-5", CLANS, "blackwood", F.units("fangthrowers", 2)],
	], {"stonegate": CROWN, "westwatch": CROWN, "blackwood": CLANS})
	s.current_turn = 5
	var p := s.find_province("stonegate")
	p.siege_since = 4
	p.walls = 3
	p.owned_since = 2
	p.lost = {"faction": CLANS, "owned_since": 1, "turn": 2}
	F.set_fort(s, "westwatch", 1, 2)
	s.find_province("westwatch").fort_by = CROWN
	s.find_province("westwatch").works = {"faction": CROWN, "to": 2, "left": 3, "turn": 5}
	return s


func _json_round_trip(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


func test_round_trips_for_every_new_field_and_order() -> void:
	var s := _besieged()
	var errors := []
	assert_true(s.validate(errors), ", ".join(errors))
	var d := s.to_dict()
	assert_eq(d.sieges, true, "a game with sieges says so")
	var back := GameState.from_dict(_json_round_trip(d), errors)
	assert_true(back != null, ", ".join(errors))
	assert_eq(JSON.stringify(back.to_dict()), JSON.stringify(d), "the state survives a JSON round trip exactly")
	assert_true(back.sieges)
	var p := back.find_province("stonegate")
	assert_eq([p.fort_level, p.walls, p.siege_since, p.owned_since], [2, 3, 4, 2])
	assert_eq(p.lost, {"faction": CLANS, "owned_since": 1, "turn": 2})
	var w := back.find_province("westwatch")
	assert_eq([w.fort_level, w.walls, w.fort_by, w.has_fort], [1, 2, CROWN, true])
	assert_eq(w.works, {"faction": CROWN, "to": 2, "left": 3, "turn": 5})
	assert_eq(back.find_army("beasts-4").engines, 1)
	assert_false(back.find_army("beasts-5").to_dict().has("engines"), "an army without engines saves no key")
	assert_eq(JSON.stringify(s.deep_copy().to_dict()), JSON.stringify(d), "deep_copy is a save and reload")
	# Every new order, and a recruit at a fort.
	var orders := [FortifyOrder.new("westwatch"), SiegeOrder.storm("stonegate"), SiegeOrder.sally("kingdom-1"),
		SiegeOrder.sally("kingdom-2", "kingdom-3"), RecruitOrder.new("spearmen", "stonegate")]
	var expected := [{"type": "fortify", "province": "westwatch"}, {"type": "siege", "action": "storm", "province": "stonegate"},
		{"type": "siege", "action": "sally", "army": "kingdom-1"}, {"type": "siege", "action": "sally", "army": "kingdom-2", "with": "kingdom-3"},
		{"type": "recruit", "unit_type": "spearmen", "at": "stonegate"}]
	for i in orders.size():
		assert_eq(orders[i].to_dict(), expected[i], "order %d saves as §12 says" % i)
		var again = OrderBook.order_from_dict(_json_round_trip(orders[i].to_dict()))
		assert_true(again != null)
		assert_eq(JSON.stringify(again.to_dict()), JSON.stringify(orders[i].to_dict()), "order %d round-trips" % i)
	var loaded := OrderBook.orders_from_dict(_json_round_trip({CROWN: orders.map(func(o): return o.to_dict())}))
	assert_eq(loaded[CROWN].size(), orders.size(), "a turn's siege orders load from a record")
	assert_true(loaded[CROWN][1] is SiegeOrder and loaded[CROWN][1].is_storm())
	assert_eq(loaded[CROWN][3].with_army, "kingdom-3")
	# A bad engine count or a stray siege field fails to load with a plain reason.
	var bad := s.to_dict()
	bad.armies[3]["engines"] = FortData.ARMY_ENGINES_MAX + 1
	errors = []
	assert_eq(GameState.from_dict(bad, errors), null)
	assert_true(errors.size() > 0 and not String(errors[0]).is_empty(), "a reason")
	var m1 := GameState.new(3).to_dict()
	m1.provinces[0]["walls"] = 4
	errors = []
	assert_eq(GameState.from_dict(m1, errors), null, "fort data in a game without sieges")
	assert_true(String(errors[0]).contains("without forts and sieges"), errors[0])


func test_a_recorded_siege_game_replays_to_an_identical_state() -> void:
	var session := GameSession.new(GameState.with_sieges(11), [CROWN, CLANS], 11, AutoBattleResolver.new())
	# [kingdom's orders, beasts' orders] per turn, written against the state at the start of that turn.
	var script := [
		func(s): return [[MoveOrder.new(_army_at(s, CROWN, "crownkeep"), "westwatch"), RecruitOrder.new("spearmen")],
			[MoveOrder.new(_army_at(s, CLANS, "fangridge"), "ebonpeak"), RecruitOrder.new("tuskers")]],
		func(s): return [[MoveOrder.new(_army_at(s, CROWN, "westwatch"), "stonegate")],
			[MoveOrder.new(_army_at(s, CLANS, "ebonpeak"), "blackwood")]],
		func(s): return [[FortifyOrder.new("westwatch")], [MoveOrder.new(_army_at(s, CLANS, "blackwood"), "stonegate")]],
		func(s): return [[RecruitOrder.new("spearmen")], [SiegeOrder.storm("stonegate")]],
		func(_s): return [[], []],
		func(_s): return [[], []],
	]
	var siege_seen := false
	for step in script:
		var orders: Array = step.call(session.state())
		for seat in 2:
			if session.phase() == GameSession.Phase.HANDOFF:
				session.acknowledge_handoff()
			for o in orders[seat]:
				assert_eq(session.queue_order(o), "", "turn %d, seat %d: %s" % [session.turn_number(), seat + 1, o.describe()])
			session.end_turn()
		for e in session.turn_report().events:
			if e.type == "siege_started":
				siege_seen = true
		if session.is_over():
			break
	assert_true(siege_seen, "a siege started in the recorded game")
	var record := session.record()
	assert_true(record.start_state.get("sieges", false), "the record's start state has sieges")
	var replayed := GameSession.replay(_json_round_trip(record), AutoBattleResolver.new())
	assert_eq(replayed.errors, [])
	assert_eq(JSON.stringify(replayed.state.to_dict()), JSON.stringify(session.state().to_dict()), "the replay ends in the same state")
	var loaded := GameSession.from_record(_json_round_trip(record), AutoBattleResolver.new())
	assert_eq(loaded.errors, [])
	assert_eq(JSON.stringify(loaded.session.state().to_dict()), JSON.stringify(session.state().to_dict()), "a loaded save is the same game")


## The id of `fid`'s first army at `province_id` (ids are not hard-coded: how they are handed out is not this test's business).
func _army_at(s: GameState, fid: String, province_id: String) -> String:
	for a in TurnResolver._sorted_armies(s):
		if a.owner == fid and a.location == province_id and a.ruler == null:
			return a.id
	return ""


func test_orderbook_drops_a_storm_when_its_move_is_removed_and_a_sally_when_its_army_moves() -> void:
	var s := _besieged()
	# A storm from the march needs a move into the fort, wherever it comes in the list.
	var clear := F.state([
		["kingdom-1", CROWN, "stonegate", F.units("spearmen", 3)],
		["beasts-2", CLANS, "blackwood", F.units("tuskers", 4)],
	], {"stonegate": CROWN, "blackwood": CLANS})
	for how in ["remove", "remove_no_state", "cancel"]:
		var book := OrderBook.new()
		var early := book.submit(clear, CLANS, SiegeOrder.storm("stonegate"))
		assert_true(early.contains("no army at Stonegate"), "without a move there is nobody to storm with: %s" % early)
		assert_eq(book.submit(clear, CLANS, MoveOrder.new("beasts-2", "stonegate")), "")
		assert_eq(book.submit(clear, CLANS, SiegeOrder.storm("stonegate")), "", "a storm from the march")
		match how:
			"remove":
				book.remove(CLANS, 0, clear)
			"remove_no_state":
				book.remove(CLANS, 0)  # the state of the last submit
			"cancel":
				var dropped := book.cancel(clear, CLANS, 0)
				assert_eq(dropped.size(), 1, "cancel() returns what it dropped")
		assert_eq(book.orders_for(CLANS).size(), 0, "%s: the storm went with its move" % how)
		var why: Array = book.last_dropped()
		assert_eq(why.size(), 1, how)
		assert_true(why[0].order is SiegeOrder)
		assert_true(String(why[0].text).begins_with("Storm of Stonegate removed:"), why[0].text)
		assert_true(String(why[0].reason).contains("no army at Stonegate"), why[0].reason)
	# Wherever it comes in the list: a storm given before its move passes the re-check.
	var kept := OrderBook.recheck(clear, CLANS, [SiegeOrder.storm("stonegate"), MoveOrder.new("beasts-2", "stonegate")])
	assert_eq(kept.kept.size(), 2)
	assert_eq(kept.dropped, [])
	assert_true(kept.kept[0] is SiegeOrder, "it keeps its place in the list")
	# A sally is dropped when a move for its army is queued after it.
	var book := OrderBook.new()
	assert_eq(book.submit(s, CROWN, SiegeOrder.sally("kingdom-1")), "")
	assert_eq(book.submit(s, CROWN, MoveOrder.new("kingdom-1", "westwatch")), "", "the move is taken")
	assert_eq(book.orders_for(CROWN).size(), 1, "and the sally dropped")
	var dropped: Array = book.last_dropped()
	assert_eq(dropped.size(), 1)
	assert_true(String(dropped[0].text).begins_with("Sally by the "), dropped[0].text)
	assert_true(String(dropped[0].reason).contains("Moving out is leaving the fort, not sallying"), dropped[0].reason)
	assert_true(book.submit(s, CROWN, SiegeOrder.sally("kingdom-1")).contains("has a move order"), "and can't come back")
	# A tied sally goes with its relief's move, by remove() or cancel().
	for how in ["remove", "cancel"]:
		book = OrderBook.new()
		assert_eq(book.submit(s, CROWN, MoveOrder.new("kingdom-3", "stonegate")), "", "the relief from Westwatch")
		assert_eq(book.submit(s, CROWN, SiegeOrder.sally("kingdom-2", "kingdom-3")), "", "the garrison comes out to join it")
		assert_eq(book.submit(s, CROWN, SiegeOrder.sally("kingdom-1")), "", "a sally of its own")
		if how == "remove":
			book.remove(CROWN, 0, s)
		else:
			book.cancel(s, CROWN, 0)
		assert_eq(book.orders_for(CROWN).size(), 1, "%s: only the untied sally is left" % how)
		assert_eq(book.orders_for(CROWN)[0].army_id, "kingdom-1")
		assert_eq(book.last_dropped().size(), 1)
		assert_true(String(book.last_dropped()[0].reason).contains("relief army"), book.last_dropped()[0].reason)
	# With no siege orders, remove() drops nothing and leaves last_dropped() as it was.
	var paths := GameState.with_paths(5)
	var crown_army := RulerRules.ruler_army(paths, CROWN)
	book = OrderBook.new()
	assert_eq(book.submit(paths, CROWN, MoveOrder.new(crown_army.id, "westwatch")), "")
	assert_eq(book.submit(paths, CROWN, ResearchOrder.new(_first_node(paths, CROWN, 0))), "")
	assert_eq(book.submit(paths, CROWN, ResearchOrder.new(_first_node(paths, CROWN, 1))), "")
	var before: Array = book.last_dropped()
	assert_eq(before.size(), 1, "the second research order replaced the first")
	book.remove(CROWN, 0)
	assert_eq(book.orders_for(CROWN).size(), 1, "the move is gone")
	assert_eq(book.last_dropped().size(), before.size(), "remove() left last_dropped() as it was")
	assert_eq(String(book.last_dropped()[0].text), String(before[0].text))


## The id of the `n`th node `fid` could research now.
func _first_node(s: GameState, fid: String, n: int) -> String:
	var found := []
	for id in AscensionRules.node_ids(fid):
		if AscensionRules.check_research(s, fid, String(id)).is_empty():
			found.append(String(id))
	return found[n] if n < found.size() else ""


func test_siege_orders_are_checked_in_the_orders_phase_with_reasons() -> void:
	var s := _besieged()
	var gate := s.find_province("stonegate")
	# Storm: legal for the besiegers; never your own fort, a breached fort or an empty one.
	assert_eq(OrderBook.check_order(s, CLANS, SiegeOrder.storm("stonegate"), []), {})
	assert_eq(String(OrderBook.check_order(s, CROWN, SiegeOrder.storm("stonegate"), []).code), "storm_own_fort")
	assert_eq(String(OrderBook.check_order(s, CLANS, SiegeOrder.storm("blackwood"), []).code), "storm_own_fort")
	assert_eq(String(OrderBook.check_order(s, CLANS, SiegeOrder.storm("thornvale"), []).code), "storm_no_fort")
	assert_eq(String(OrderBook.check_order(s, CLANS, SiegeOrder.storm("stonegate"), [SiegeOrder.storm("stonegate")]).code), "storm_twice")
	var down := s.deep_copy()
	down.find_province("stonegate").walls = 0
	var walls_down := OrderBook.check_order(down, CLANS, SiegeOrder.storm("stonegate"), [])
	assert_eq(String(walls_down.code), "storm_walls_down")
	assert_eq(String(walls_down.reason), "Stonegate's walls are down: the battle there comes on its own.")
	assert_eq(String(OrderBook.check_order(down, CROWN, SiegeOrder.sally("kingdom-1"), []).code), "sally_walls_down")
	# Sally: from your own besieged fort only.
	assert_eq(OrderBook.check_order(s, CROWN, SiegeOrder.sally("kingdom-1"), []), {})
	assert_eq(String(OrderBook.check_order(s, CROWN, SiegeOrder.sally("kingdom-3"), []).code), "sally_not_besieged", "Westwatch is not besieged")
	var afield := s.deep_copy()
	afield.find_army("kingdom-3").location = "highcrag"
	assert_eq(String(OrderBook.check_order(afield, CROWN, SiegeOrder.sally("kingdom-3"), []).code), "sally_not_in_fort")
	assert_eq(String(OrderBook.check_order(s, CLANS, SiegeOrder.sally("kingdom-1"), []).code), "not_your_army")
	assert_eq(String(OrderBook.check_order(s, CROWN, SiegeOrder.sally("kingdom-2", "kingdom-3"), []).code), "sally_relief_missing")
	# Resolved: a rejected siege order is reported in the orders phase, with its codex entry.
	var r := F.resolve(s, {CROWN: [SiegeOrder.storm("stonegate"), SiegeOrder.sally("kingdom-3")]})
	var rejected := F.events_of(r.events, "order_rejected")
	assert_eq(rejected.size(), 2)
	for e in rejected:
		assert_eq(e.phase, "orders")
		assert_true(["storm", "sally"].has(e.codex), e.codex)
		assert_false(String(e.reason).contains("_"), e.reason)
	assert_eq(gate.siege_since, 4)
	# Without sieges, siege orders are refused.
	var m1 := GameState.new(3)
	assert_eq(String(OrderBook.check_order(m1, CROWN, SiegeOrder.storm("fangridge"), []).code), "no_sieges")
