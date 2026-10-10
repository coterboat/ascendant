extends "res://tests/test_case.gd"
## ARM-1 (design/ARM1_SPLIT_MERGE.md §3): musters in the plan. RulerRules.state_after_orders applies a faction's musters
## FIRST, hoisted before every non-muster order and sequentially among themselves, on a copy; new ids come from the same
## counter the resolution will use; every non-muster order is checked against the result; adding, changing or cancelling a
## muster re-checks everything and drops dependants with plain reasons; a refused muster allocates nothing.

const Kit := preload("res://tests/muster_test_kit.gd")
const F := preload("res://tests/siege_fixtures.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const FORGE := ["crown_drillyard", "crown_charters", "crown_oath_forge", "shield_of_law", "sanctum_ward", "bastion", "sunlance", "dawn_blessing"]


func _magic_game() -> GameState:
	var s := Kit.game("magic")
	s = AscensionRules.with_nodes(s, CROWN, FORGE)
	for f in s.factions:
		f.gold = 200
	return s


# --- hoisting -----------------------------------------------------------------------------------------

func test_musters_apply_first_wherever_they_stand_in_the_list() -> void:
	var s := Kit.game()
	var split := MusterOrder.transfer("kingdom-1", "", [0, 1])
	var move_new := MoveOrder.new("kingdom-2", "westwatch")
	var after_listed_first := RulerRules.state_after_orders(s, CROWN, [move_new, split])
	var after_listed_last := RulerRules.state_after_orders(s, CROWN, [split, move_new])
	assert_true(after_listed_first.find_army("kingdom-2") != null, "the new army exists on the board even when its move is listed before the split")
	assert_eq(JSON.stringify(after_listed_first.to_dict()), JSON.stringify(after_listed_last.to_dict()), "the list's order of non-musters and musters does not change the board")
	assert_eq(s.armies.size(), 2, "the real state is untouched")
	# recheck keeps the move that came before the muster it depends on.
	var r := OrderBook.recheck(s, CROWN, [move_new, split])
	assert_eq(r.dropped, [], "nothing is dropped: the move is checked against the board after the muster")
	assert_eq(r.kept.size(), 2)
	# Without the muster the same move is dropped, with a reason about the muster.
	var r2 := OrderBook.recheck(s, CROWN, [move_new])
	assert_eq(r2.dropped.size(), 1)
	assert_true(String(r2.dropped[0].reason).contains("muster"), "its reason names the muster: %s" % r2.dropped[0].reason)
	assert_false(String(r2.dropped[0].reason).contains("kingdom-2"), "and the army by its name: %s" % r2.dropped[0].reason)


func test_musters_run_in_the_order_given_among_themselves() -> void:
	var s := Kit.game()
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen"])
	var first := MusterOrder.transfer("kingdom-1", b.id, [0])
	var second := MusterOrder.transfer(b.id, "", [1])  # B's second unit exists only once the first muster has run
	var board := RulerRules.state_after_orders(s, CROWN, [second, first])
	# [second, first] in the list: still first, then second, as ordered by position among musters (second is listed first)
	assert_true(board.find_army("kingdom-3") == null, "the second, listed first, ran first: B had one unit, so unit 2 did not exist and the muster was skipped")
	var board2 := RulerRules.state_after_orders(s, CROWN, [first, second])
	assert_true(board2.find_army("kingdom-3") != null, "listed in the other order it runs after the first and splits B's second unit off")


func test_the_projection_includes_a_sacrifice_applied_before_the_musters() -> void:
	var s := Kit.game("rulers")
	var a := Kit.crown(s)
	var before_power := s.find_faction(CROWN).kept_power
	var mandates := RulerRules.available_mandates(CROWN, s)
	var mid := ""
	for m in mandates:
		if RulerRules.sacrifice_check(s, CROWN, String(m)).is_empty():
			mid = String(m)
			break
	if mid.is_empty():
		return
	var board := RulerRules.state_after_orders(s, CROWN, [MusterOrder.transfer(a.id, "", [0]), SacrificeOrder.new(mid)])
	assert_true(board.find_faction(CROWN).kept_power < before_power, "the sacrifice is applied on the projected board")
	assert_true(board.armies.size() == s.armies.size() + 1, "and so is the muster")
	assert_eq(s.find_faction(CROWN).kept_power, before_power, "the real state is untouched")


# --- the order book -----------------------------------------------------------------------------------

func test_the_book_takes_a_muster_and_then_a_move_for_the_army_it_forms() -> void:
	var s := Kit.game()
	var book := OrderBook.new()
	assert_eq(book.submit(s, CROWN, MoveOrder.new("kingdom-2", "westwatch")), "There is no such army on the map. It may have been destroyed, or the order names an army this game never had.",
		"before the split there is no kingdom-2 to move (the legacy reason, untouched)")
	assert_eq(book.submit(s, CROWN, MusterOrder.transfer("kingdom-1", "", [0, 2])), "", "the split is accepted")
	assert_eq(book.submit(s, CROWN, MoveOrder.new("kingdom-2", "westwatch")), "", "and the new army can be given a move the same turn")
	assert_eq(book.submit(s, CROWN, MoveOrder.new("kingdom-2", "highcrag")), "The Crown's 2nd already has a move order this turn. Each army moves once per turn.")
	assert_eq(book.submit(s, CROWN, MoveOrder.new("kingdom-1", "highcrag")), "", "the source can march elsewhere with what is left")
	assert_eq(book.orders_for(CROWN).size(), 3)
	assert_eq(s.armies.size(), 2, "the real state never changed")


func test_a_refused_muster_is_not_queued_and_allocates_nothing() -> void:
	var s := Kit.game()
	var book := OrderBook.new()
	var why := book.submit(s, CROWN, MusterOrder.transfer("kingdom-1", "", [5]))
	assert_true(why.contains("no unit number 6"), why)
	assert_eq(book.orders_for(CROWN), [])
	assert_eq(book.submit(s, CROWN, MusterOrder.transfer("kingdom-1", "", [0])), "")
	assert_eq(book.submit(s, CROWN, MoveOrder.new("kingdom-2", "westwatch")), "", "the first accepted split was kingdom-2: the refused one took no id")
	var board := RulerRules.state_after_orders(s, CROWN, book.orders_for(CROWN))
	assert_eq(int(board.next_army_ids[CROWN]), 3)


func test_cancelling_a_muster_drops_what_relied_on_it_with_a_reason() -> void:
	var s := Kit.game()
	var book := OrderBook.new()
	assert_eq(book.submit(s, CROWN, MusterOrder.transfer("kingdom-1", "", [0, 2])), "")
	assert_eq(book.submit(s, CROWN, MoveOrder.new("kingdom-2", "westwatch")), "")
	assert_eq(book.submit(s, CROWN, MoveOrder.new("kingdom-1", "highcrag")), "")
	var dropped := book.cancel(s, CROWN, 0)
	assert_eq(dropped.size(), 1, "the new army's move goes with its split")
	assert_true(String(dropped[0].text).begins_with("Move to Westwatch removed:"), dropped[0].text)
	assert_true(String(dropped[0].text).contains("muster"), "and says why: %s" % dropped[0].text)
	assert_eq(book.orders_for(CROWN).size(), 1, "the source's own move stays")
	assert_eq(book.last_dropped().size(), 1)


func test_removing_a_muster_rechecks_the_rest_like_cancelling() -> void:
	var s := Kit.game()
	var book := OrderBook.new()
	book.submit(s, CROWN, MusterOrder.transfer("kingdom-1", "", [0, 2]))
	book.submit(s, CROWN, MoveOrder.new("kingdom-2", "westwatch"))
	book.remove(CROWN, 0, s)
	assert_eq(book.orders_for(CROWN), [], "remove() drops the dependent move too")
	assert_eq(book.last_dropped().size(), 1)


func test_changing_a_muster_rebuilds_the_plan() -> void:
	var s := Kit.game()
	var book := OrderBook.new()
	book.submit(s, CROWN, MusterOrder.transfer("kingdom-1", "", [0]))
	book.submit(s, CROWN, MoveOrder.new("kingdom-2", "westwatch"))
	# Change: cancel the split and give another one; the move for the new army needs re-ordering, and the new army's id is the same.
	var dropped := book.cancel(s, CROWN, 0)
	assert_eq(dropped.size(), 1)
	assert_eq(book.submit(s, CROWN, MusterOrder.transfer("kingdom-1", "", [1, 2], true)), "")
	assert_eq(book.submit(s, CROWN, MoveOrder.new("kingdom-2", "westwatch")), "", "the army the new split forms is the Crown's 2nd again")
	var board := RulerRules.state_after_orders(s, CROWN, book.orders_for(CROWN))
	assert_eq(Kit.types(board.find_army("kingdom-2")), ["crossbowmen", "knights"], "built from the new split's units")
	assert_true(board.find_army("kingdom-2").commander != null, "and its commander")


func test_a_later_muster_that_relied_on_an_earlier_one_goes_with_it() -> void:
	var s := Kit.game()
	var book := OrderBook.new()
	book.submit(s, CROWN, MusterOrder.transfer("kingdom-1", "", [0, 1]))
	assert_eq(book.submit(s, CROWN, MusterOrder.transfer("kingdom-2", "", [1])), "", "a second muster splits the first one's new army again (multi-hop)")
	assert_eq(book.submit(s, CROWN, MoveOrder.new("kingdom-3", "westwatch")), "")
	var dropped := book.cancel(s, CROWN, 0)
	assert_eq(dropped.size(), 2, "the second muster and the move both went: neither army exists now")
	assert_eq(book.orders_for(CROWN), [])
	var texts := dropped.map(func(d): return String(d.text))
	assert_true(texts.any(func(t): return t.begins_with("Split ")), "a dropped muster reads as a muster: %s" % [texts])


func test_a_muster_that_empties_an_army_drops_its_move_with_a_plain_reason() -> void:
	var s := Kit.game()
	var book := OrderBook.new()
	assert_eq(book.submit(s, CROWN, MoveOrder.new("kingdom-1", "westwatch")), "")
	assert_eq(book.submit(s, CROWN, RecruitOrder.new("spearmen")), "")
	assert_eq(book.submit(s, CROWN, MusterOrder.transfer("kingdom-1", "", [0, 1, 2], true)), "", "everything in the army goes to a new one")
	assert_eq(book.last_dropped().size(), 1, "the move for the emptied, disbanded army is dropped")
	var text := String(book.last_dropped()[0].text)
	assert_true(text.contains("not there after your musters"), text)
	assert_eq(book.orders_for(CROWN).size(), 2, "the recruit stays")


func test_every_refusal_reason_comes_through_the_book() -> void:
	var s := Kit.game()
	var book := OrderBook.new()
	assert_true(book.submit(s, CROWN, MusterOrder.transfer("kingdom-1", "", [])).contains("moves no one"))
	assert_true(book.submit(s, CROWN, MusterOrder.transfer("beasts-1", "", [0])).contains("belongs to"))
	assert_true(book.submit(s, CROWN, MusterOrder.swap("kingdom-1", "kingdom-1")).contains("with itself"))


# --- dependencies: casts, pins, mages ---------------------------------------------------------------------

func test_a_cast_from_a_new_army_and_a_mage_moved_out_of_a_casting_army() -> void:
	var s := _magic_game()
	var a := Kit.crown(s)
	a.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(CROWN), "adepts", s), CROWN))  # the mage is unit index 3
	var book := OrderBook.new()
	var cast := CastOrder.new("sanctum_ward", a.id, "crownkeep")
	assert_eq(book.submit(s, CROWN, cast), "", "the army with the mage can cast")
	# Moving the mage out of the casting army: the cast has no caster any more, and goes, with its reason.
	assert_eq(book.submit(s, CROWN, MusterOrder.transfer(a.id, "", [3])), "")
	assert_eq(book.last_dropped().size(), 1, "the cast is dropped")
	assert_true(String(book.last_dropped()[0].text).begins_with("Cast Sanctum Ward"), book.last_dropped()[0].text)
	assert_eq(book.orders_for(CROWN).size(), 1)
	# The new army, which holds the mage, can cast it instead.
	assert_eq(book.submit(s, CROWN, CastOrder.new("sanctum_ward", "kingdom-2", "crownkeep")), "", "a new army casts the same turn")


func test_a_pin_follows_the_army_the_cast_names_on_the_projected_board() -> void:
	var s := _magic_game()
	var a := Kit.crown(s)
	a.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(CROWN), "adepts", s), CROWN))
	var book := OrderBook.new()
	assert_eq(book.submit(s, CROWN, MusterOrder.transfer(a.id, "", [3])), "")
	assert_eq(book.submit(s, CROWN, CastOrder.new("sanctum_ward", "kingdom-2", "crownkeep")), "")
	assert_true(book.submit(s, CROWN, MoveOrder.new("kingdom-2", "westwatch")).contains("can't move this turn"), "the casting army is pinned")
	assert_eq(book.submit(s, CROWN, MoveOrder.new("kingdom-1", "westwatch")), "", "the army it was split from is free to march")


# --- dependencies: sieges -------------------------------------------------------------------------------------

func _besieged() -> GameState:
	var s := F.state([
		["kingdom-1", CROWN, "stonegate", F.units("spearmen", 3) + ["knight_captain"]],
		["kingdom-2", CROWN, "stonegate", ["crossbowmen"]],
		["kingdom-3", CROWN, "westwatch", F.units("knights", 2)],
		["beasts-4", CLANS, "stonegate", F.units("tuskers", 4), 1],
	], {"stonegate": CROWN, "westwatch": CROWN})
	s.current_turn = 5
	var p := s.find_province("stonegate")
	p.siege_since = 4
	p.walls = 3
	p.owned_since = 2
	p.lost = {"faction": CLANS, "owned_since": 1, "turn": 2}
	return s


func test_a_new_army_can_sally_and_a_new_army_can_be_the_relief() -> void:
	var s := _besieged()
	var book := OrderBook.new()
	assert_eq(book.submit(s, CROWN, MusterOrder.transfer("kingdom-1", "", [0, 1])), "", "split the garrison")
	assert_eq(book.submit(s, CROWN, SiegeOrder.sally("kingdom-4")), "", "the new army inside the walls sallies")
	# The relief: a new army split off at Westwatch marches to the fort, and the garrison comes out with it.
	assert_eq(book.submit(s, CROWN, MusterOrder.transfer("kingdom-3", "", [0])), "")
	assert_eq(book.submit(s, CROWN, MoveOrder.new("kingdom-5", "stonegate")), "", "the relief marches")
	assert_eq(book.submit(s, CROWN, SiegeOrder.sally("kingdom-2", "kingdom-5")), "", "a sally tied to the new army's relief")
	# Cancel the sally's split: the sally goes.
	var dropped := book.cancel(s, CROWN, 0)
	assert_true(dropped.any(func(d): return String(d.text).begins_with("Sally by")), "the sally of the army that no longer exists is dropped: %s" % [dropped.map(func(d): return d.text)])


func test_engines_in_the_plan_follow_the_carrier_rules() -> void:
	var s := F.state([["kingdom-1", CROWN, "crownkeep", F.units("spearmen", 3), 2]])
	var book := OrderBook.new()
	assert_true(book.submit(s, CROWN, MusterOrder.transfer("kingdom-1", "", [0, 1, 2], false, 1)).contains("siege engines ride only with a fighter"), "a source left with no fighter keeps no engines")
	assert_eq(book.submit(s, CROWN, MusterOrder.transfer("kingdom-1", "", [0], false, 1)), "")
	assert_eq(RulerRules.state_after_orders(s, CROWN, book.orders_for(CROWN)).find_army("kingdom-2").engines, 1)


# --- recruits see the projected board ------------------------------------------------------------------------

func test_a_recruit_is_priced_and_checked_on_the_projected_board() -> void:
	var s := Kit.game()
	var book := OrderBook.new()
	assert_eq(book.submit(s, CROWN, MusterOrder.transfer("kingdom-1", "", [0])), "")
	assert_eq(book.submit(s, CROWN, RecruitOrder.new("spearmen")), "", "recruiting still works in a plan with musters")
	var board := RulerRules.state_after_orders(s, CROWN, book.orders_for(CROWN))
	assert_eq(board.armies.filter(func(a): return a.owner == CROWN).size(), 2)
