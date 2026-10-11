extends "res://tests/test_case.gd"
## ARM-1 step 2 (design/ARM1_SPLIT_MERGE.md §1): the MusterOrder, its three kinds, its serialization and its STRICT
## parser (OrderBook.order_from_dict), and the rule that a malformed muster in a record fails the record's load with a
## plain reason instead of being skipped (OrderBook.orders_from_dict keeps it; GameSession.replay and from_record stop).

const CROWN := "kingdom"
const CLANS := "beasts"


func _json(d: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(d))


func _transfer() -> Dictionary:
	return {"type": "muster", "kind": "transfer", "from": "kingdom-1", "to": "", "units": [0, 2], "commander": false, "engines": 0}


# --- the order and its saved form -------------------------------------------------------------------

func test_each_kind_saves_its_own_keys() -> void:
	var t := MusterOrder.transfer("kingdom-1", "", [0, 2], true, 1)
	assert_eq(t.to_dict(), {"type": "muster", "kind": "transfer", "from": "kingdom-1", "to": "", "units": [0, 2], "commander": true, "engines": 1})
	assert_eq(t.to_dict().keys(), ["type", "kind", "from", "to", "units", "commander", "engines"], "the keys are saved in a fixed order")
	assert_true(t.is_transfer() and t.is_new_army(), "a transfer to '' is a split")
	var m := MusterOrder.merge("kingdom-2", "kingdom-1")
	assert_eq(m.to_dict(), {"type": "muster", "kind": "merge", "from": "kingdom-2", "to": "kingdom-1"})
	assert_false(m.is_transfer() or m.is_new_army())
	var w := MusterOrder.swap("kingdom-1", "kingdom-2")
	assert_eq(w.to_dict(), {"type": "muster", "kind": "swap", "from": "kingdom-1", "to": "kingdom-2"})
	for o in [t, m, w]:
		assert_false(o.describe().is_empty(), "every order describes itself")
		assert_eq(o.copy().to_dict(), o.to_dict(), "a copy is the same order")
	t.units.append(5)
	assert_eq(MusterOrder.transfer("kingdom-1", "", [0, 2], true, 1).units, [0, 2], "an order never shares its list with the caller")


func test_an_order_survives_a_json_round_trip() -> void:
	for o in [MusterOrder.transfer("kingdom-1", "kingdom-3", [1, 0, 4], false, 2), MusterOrder.transfer("kingdom-1", "", [], true),
			MusterOrder.merge("kingdom-2", "kingdom-1"), MusterOrder.swap("kingdom-1", "kingdom-2")]:
		var back = OrderBook.order_from_dict(_json(o.to_dict()))
		assert_true(back is MusterOrder, "a muster loads as a MusterOrder")
		assert_eq(back.malformed, "", "and is well formed")
		assert_eq(JSON.stringify(back.to_dict()), JSON.stringify(o.to_dict()), "it saves the same bytes after a round trip: %s" % o.describe())
		assert_eq(typeof(back.engines), TYPE_INT, "engines are an int again, not the float JSON gave")
		for i in back.units:
			assert_eq(typeof(i), TYPE_INT, "so are the unit places")


func test_orders_by_faction_round_trip_keeps_the_order_given() -> void:
	var list := [MoveOrder.new("kingdom-1", "westwatch"), MusterOrder.swap("kingdom-1", "kingdom-2"), RecruitOrder.new("spearmen"),
		MusterOrder.transfer("kingdom-1", "", [0], false)]
	var book := {CROWN: list}
	var data := {CROWN: list.map(func(o): return o.to_dict())}
	var back := OrderBook.orders_from_dict(_json(data))
	assert_eq(back[CROWN].size(), 4)
	assert_true(back[CROWN][1] is MusterOrder and back[CROWN][3] is MusterOrder and back[CROWN][0] is MoveOrder)
	assert_eq(book.size(), 1)


# --- the strict parser ------------------------------------------------------------------------------

func test_the_parser_refuses_every_malformation_with_a_plain_reason() -> void:
	var cases := {
		"a missing key": [func(d): d.erase("units"), "no 'units'"],
		"a missing from": [func(d): d.erase("from"), "no 'from'"],
		"a missing to": [func(d): d.erase("to"), "no 'to'"],
		"a missing commander": [func(d): d.erase("commander"), "no 'commander'"],
		"a missing engines": [func(d): d.erase("engines"), "no 'engines'"],
		"a missing kind": [func(d): d.erase("kind"), "no 'kind'"],
		"an extra key": [func(d): d["extra"] = 1, "holds 'extra'"],
		"an unknown kind": [func(d): d["kind"] = "teleport", "'teleport'"],
		"a kind that is not text": [func(d): d["kind"] = 3, "no 'kind'"],
		"a from that is not text": [func(d): d["from"] = 7, "'from' should be an army id"],
		"a to that is not text": [func(d): d["to"] = null, "'to' should be an army id"],
		"units that are not a list": [func(d): d["units"] = "0,2", "'units' should be a list"],
		"a unit place that is text": [func(d): d["units"] = [0, "2"], "whole numbers"],
		"a unit place with a fraction": [func(d): d["units"] = [0.5], "whole numbers"],
		"a negative unit place": [func(d): d["units"] = [-1], "from 0"],
		"a unit place twice": [func(d): d["units"] = [1, 1], "twice"],
		"a unit place that is a bool": [func(d): d["units"] = [true], "whole numbers"],
		"a commander that is a number": [func(d): d["commander"] = 1, "'commander' should be true or false"],
		"a commander that is text": [func(d): d["commander"] = "yes", "'commander' should be true or false"],
		"engines that are a fraction": [func(d): d["engines"] = 1.5, "'engines' should be a whole number"],
		"negative engines": [func(d): d["engines"] = -1, "from 0"],
		"engines that are text": [func(d): d["engines"] = "1", "'engines' should be a whole number"],
		"engines that are a bool": [func(d): d["engines"] = true, "'engines' should be a whole number"],
	}
	for name in cases:
		var d := _transfer()
		cases[name][0].call(d)
		var errors := []
		var order = OrderBook.order_from_dict(d, errors)
		assert_true(order is MusterOrder and not order.malformed.is_empty(), "%s is malformed" % name)
		assert_eq(errors.size(), 1, "%s is reported once" % name)
		if not errors.is_empty():
			assert_true(String(errors[0]).begins_with("A muster order is malformed:"), "%s: %s" % [name, errors[0]])
			assert_true(String(errors[0]).contains(cases[name][1]), "%s names the fault (%s): %s" % [name, cases[name][1], errors[0]])
		if order is MusterOrder:
			assert_eq(order.to_dict(), d, "%s is handed back as it was read" % name)
	# The same strictness for a merge and a swap: exactly kind, from and to.
	for kind in ["merge", "swap"]:
		var ok := {"type": "muster", "kind": kind, "from": "kingdom-1", "to": "kingdom-2"}
		assert_eq(OrderBook.order_from_dict(ok, []).malformed, "", "a %s with its three keys is well formed" % kind)
		var extra := ok.duplicate()
		extra["units"] = []
		assert_false(OrderBook.order_from_dict(extra, []).malformed.is_empty(), "a %s holding 'units' is malformed" % kind)
		var short := ok.duplicate()
		short.erase("to")
		assert_false(OrderBook.order_from_dict(short, []).malformed.is_empty(), "a %s with no 'to' is malformed" % kind)
		var wrong := ok.duplicate()
		wrong["to"] = 2
		assert_false(OrderBook.order_from_dict(wrong, []).malformed.is_empty(), "a %s with a 'to' that is not text is malformed" % kind)


func test_the_parser_accepts_whole_numbers_as_floats_and_a_new_army() -> void:
	var d := _transfer()
	d["units"] = [0.0, 2.0]
	d["engines"] = 1.0
	var errors := []
	var o = OrderBook.order_from_dict(d, errors)
	assert_eq(errors, [], "JSON's floats are fine when whole")
	assert_eq(o.units, [0, 2])
	assert_eq(o.engines, 1)
	assert_true(o.is_new_army(), "'to' of '' means a new army")
	d["units"] = []
	assert_eq(OrderBook.order_from_dict(d, []).malformed, "", "an empty list parses (the check refuses an empty transfer)")


func test_other_order_types_still_parse_as_they_did() -> void:
	var errors := []
	assert_true(OrderBook.order_from_dict({"type": "move", "army": "kingdom-1", "to": "westwatch", "extra": 1}, errors) is MoveOrder, "the lenient parsers still ignore extra keys")
	assert_eq(errors, [])
	assert_eq(OrderBook.order_from_dict({"type": "pray"}, errors), null, "an unknown type is still null")
	assert_eq(errors.size(), 1)


# --- a malformed muster is never skipped --------------------------------------------------------------

func test_orders_from_dict_keeps_a_malformed_muster_and_says_why() -> void:
	var bad := _transfer()
	bad.erase("commander")
	var data := {CROWN: [{"type": "move", "army": "kingdom-1", "to": "westwatch"}, bad, {"type": "recruit", "unit_type": "spearmen"}]}
	var errors := []
	var orders := OrderBook.orders_from_dict(data, errors)
	assert_eq(orders[CROWN].size(), 3, "all three orders come back: the muster is not dropped")
	assert_true(orders[CROWN][1] is MusterOrder and not orders[CROWN][1].malformed.is_empty(), "the second is the malformed muster")
	assert_eq(errors.size(), 1, "one plain reason: %s" % [errors])
	assert_true(String(errors[0]).contains("no 'commander'"), "it names the fault")
	var listed := OrderBook.malformed_musters(orders)
	assert_eq(listed.size(), 1)
	assert_true(String(listed[0]).contains("Order 2 for 'kingdom'") and String(listed[0]).contains("no 'commander'"), "and where it was: %s" % [listed])
	assert_eq(OrderBook.malformed_musters({CROWN: [MusterOrder.swap("kingdom-1", "kingdom-2")]}), [], "a good muster lists nothing")
	assert_eq(OrderBook.malformed_musters({CROWN: "not a list"}), [], "and a faction's non-list is the other loaders' business")


func _record_with(orders_for_turn_1: Dictionary) -> Dictionary:
	var session := GameSession.new(GameState.new(7), [CROWN, CLANS], 7, StubBattleResolver.new())
	assert_eq(session.phase(), GameSession.Phase.ORDERS)
	assert_eq(session.end_turn(), "", "the first player ends their turn")
	session.acknowledge_handoff()
	assert_eq(session.end_turn(), "", "the second does too")
	var rec: Dictionary = _json(session.record())
	assert_eq(rec.history.size(), 1, "a one-turn record")
	rec.history[0].orders = orders_for_turn_1
	return rec


func test_a_record_with_a_malformed_muster_fails_to_load_and_to_replay() -> void:
	var bad := _transfer()
	bad["units"] = [1, 1]
	var rec := _record_with({CROWN: [bad], CLANS: []})
	var loaded := GameSession.from_record(rec, StubBattleResolver.new())
	assert_eq(loaded.session, null, "from_record refuses it")
	assert_eq(loaded.errors.size(), 1, "with one plain reason: %s" % [loaded.errors])
	assert_true(String(loaded.errors[0]).begins_with("Turn 1: A muster order is malformed:") and String(loaded.errors[0]).contains("twice"), "%s" % [loaded.errors])
	var replayed := GameSession.replay(rec, StubBattleResolver.new())
	assert_eq(replayed.state, null, "replay refuses it too: it does not play on without the order")
	assert_false(replayed.errors.is_empty(), "and says why")
	assert_true(replayed.errors.any(func(e): return String(e).contains("malformed muster")), "%s" % [replayed.errors])
	# Without the muster the same record is fine, so it was the muster that stopped it.
	var clean := _record_with({CROWN: [], CLANS: []})
	assert_true(GameSession.from_record(clean, StubBattleResolver.new()).session != null, "the same record without it loads")
	assert_true(GameSession.replay(clean, StubBattleResolver.new()).state != null, "and replays")
