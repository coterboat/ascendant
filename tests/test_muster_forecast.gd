extends "res://tests/test_case.gd"
## ARM-1 (design/ARM1_SPLIT_MERGE.md §7): MusterForecast, pure. For each army a candidate muster touches: units, commander, engines,
## strength, sight and name, before and after; the orders it would drop, with reasons; where this turn's recruits would join (a
## conditional answer, ids sorted as text); the battle note when one part holds and another marches; the blessing note. The order
## book's refusal reasons are the same function's. The forecast equals what the resolver then does.

const Kit := preload("res://tests/muster_test_kit.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const FORGE := ["crown_drillyard", "crown_charters", "crown_oath_forge", "shield_of_law", "sanctum_ward", "bastion", "sunlance", "dawn_blessing"]


# --- before and after ---------------------------------------------------------------------------------------------

func test_a_split_lists_both_armies_before_and_after() -> void:
	var s := Kit.game()
	var a := Kit.crown(s)
	var f := MusterForecast.of(s, CROWN, MusterOrder.transfer(a.id, "", [0, 2]), [])
	assert_true(f.ok, "the split is allowed")
	assert_eq(f.armies.size(), 2)
	var src: Dictionary = f.armies[0]
	var fresh: Dictionary = f.armies[1]
	assert_eq([src.id, src.new, src.gone], ["kingdom-1", false, false])
	assert_eq([fresh.id, fresh.new, fresh.gone], ["kingdom-2", true, false])
	assert_eq(src.name, "the Crown's 1st")
	assert_eq(fresh.name, "the Crown's 2nd")
	assert_eq(src.before.units, ["spearmen", "crossbowmen", "knights"])
	assert_eq(src.before.commander, "knight_captain")
	assert_eq(src.after.units, ["crossbowmen"])
	assert_eq(src.after.commander, "knight_captain", "the commander stayed")
	assert_eq(fresh.before, {}, "the new army is not there yet")
	assert_eq(fresh.after.units, ["spearmen", "knights"])
	assert_eq(fresh.after.commander, "")
	assert_eq(src.before.strength, StubBattleResolver.army_strength(a), "strength is the card's own number")
	assert_eq(src.after.strength + fresh.after.strength, src.before.strength, "and the two halves add up to it")
	assert_eq(src.before.sight, 2, "a commander sees 2 provinces")
	assert_eq(src.after.sight, 2)
	assert_eq(fresh.after.sight, 2, "Knights are scouts: they see 2 too")
	assert_eq(s.armies.size(), 2, "nothing in the real state changed")
	assert_true(String(f.text).begins_with("Split Spearmen and Knights from the Crown's 1st into a new army, the Crown's 2nd, at Crownkeep."), f.text)
	assert_eq(f.lines.size(), 2)
	assert_true(String(f.lines[1]).contains("not there yet"), f.lines[1])


func test_a_merge_swap_and_two_commander_merge() -> void:
	var s := Kit.game()
	var a := Kit.crown(s)
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen"], "knight_captain")
	b.engines = 0
	var merge := MusterForecast.of(s, CROWN, MusterOrder.merge(a.id, b.id), [])
	assert_true(merge.ok)
	assert_true(merge.armies[0].gone == false and merge.armies[0].after.units.is_empty() and merge.armies[0].after.commander == "knight_captain",
		"both had a commander: the source stays as its commander alone")
	assert_eq(merge.armies[1].after.units.size(), 4)
	assert_true(String(merge.text).contains("stays behind as an army of its own"), merge.text)
	var swap := MusterForecast.of(s, CROWN, MusterOrder.swap(a.id, b.id), [])
	assert_true(swap.ok)
	assert_eq(swap.armies[0].after.units, swap.armies[0].before.units, "no unit moves in a swap")
	b.commander = null
	var full := MusterForecast.of(s, CROWN, MusterOrder.merge(a.id, b.id), [])
	assert_true(full.armies[0].gone, "with no commander in the target, everything moves and the source is gone")
	assert_eq(full.armies[1].after.commander, "knight_captain")
	assert_eq(full.armies[0].after, {})


func test_engines_show_before_and_after() -> void:
	var s := Kit.game("sieges")
	var a := Kit.crown(s)
	a.engines = 2
	var f := MusterForecast.of(s, CROWN, MusterOrder.transfer(a.id, "", [0], false, 1), [])
	assert_true(f.ok)
	assert_eq([f.armies[0].before.engines, f.armies[0].after.engines, f.armies[1].after.engines], [2, 1, 1])
	assert_true(String(f.text).contains("Siege Ram") or String(f.text).contains("engine"), f.text)


# --- refusals ---------------------------------------------------------------------------------------------------------

func test_the_order_books_reasons_are_the_forecasts() -> void:
	var s := Kit.game()
	var bad := [MusterOrder.transfer("kingdom-1", "", []), MusterOrder.transfer("kingdom-1", "", [9]), MusterOrder.transfer("beasts-1", "", [0]),
		MusterOrder.swap("kingdom-1", "kingdom-1"), MusterOrder.transfer("kingdom-1", "kingdom-9", [0])]
	for o in bad:
		var f := MusterForecast.of(s, CROWN, o, [])
		assert_false(f.ok)
		var book := OrderBook.new()
		assert_eq(book.submit(s, CROWN, o), f.reason, "the same words in the plan and in the forecast")
		assert_eq(f.text, f.reason)
		assert_eq(f.armies, [])
	assert_eq(MusterForecast.refusal(s, CROWN, bad[0]).code, "empty_transfer")


# --- what it would drop -----------------------------------------------------------------------------------------------

func test_the_forecast_names_the_orders_the_muster_would_drop() -> void:
	var s := Kit.game()
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen"])
	var plan := [MoveOrder.new(b.id, "westwatch"), MoveOrder.new("kingdom-1", "highcrag")]
	var f := MusterForecast.of(s, CROWN, MusterOrder.merge(b.id, "kingdom-1"), plan)
	assert_true(f.ok)
	assert_eq(f.dropped.size(), 1, "the army that is merged away loses its move")
	assert_true(f.dropped[0].order is MoveOrder and f.dropped[0].order.army_id == b.id)
	assert_true(String(f.dropped[0].reason).contains("not there after your musters"), f.dropped[0].reason)
	assert_true(String(f.text).contains("Move to Westwatch removed"), f.text)
	# A muster that touches neither drops nothing.
	var other := MusterForecast.of(s, CROWN, MusterOrder.transfer("kingdom-1", "", [0]), [plan[0]])
	assert_eq(other.dropped, [])
	# An order that was already going to be dropped is not blamed on the candidate.
	var stale := MusterForecast.of(s, CROWN, MusterOrder.transfer("kingdom-1", "", [0]), [MoveOrder.new("kingdom-77", "westwatch")])
	assert_eq(stale.dropped, [])


# --- recruits ---------------------------------------------------------------------------------------------------------

func test_a_recruit_joins_the_first_army_by_text_id_and_the_forecast_says_so() -> void:
	var s := Kit.game()
	var a := Kit.crown(s)
	a.id = "kingdom-2"
	s.next_army_ids[CROWN] = 11
	var ten := Kit.army(s, CROWN, "crownkeep", ["spearmen"])
	ten.id = "kingdom-10"
	var plan := [RecruitOrder.new("spearmen")]
	var f := MusterForecast.of(s, CROWN, MusterOrder.transfer("kingdom-2", "", [0]), plan)
	assert_true(f.ok)
	assert_eq(f.recruits.size(), 1)
	assert_eq(f.recruits[0].army, "kingdom-10", "kingdom-10 comes before kingdom-2 as text")
	assert_eq(f.recruits[0].name, "the Crown's 10th")
	assert_eq(f.recruits[0].text, "joins the Crown's 10th if it is still at Crownkeep")
	assert_false(f.recruits[0].new)
	# And that is what the turn does.
	var r := Kit.resolve(s, {CROWN: [MusterOrder.transfer("kingdom-2", "", [0]), plan[0]]})
	assert_eq(Kit.events(r, "recruited")[0].armies, ["kingdom-10"], "the resolver agrees")


func test_a_muster_that_changes_where_a_recruit_joins_says_so() -> void:
	var s := Kit.game()
	var a := Kit.crown(s)
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen"])
	var plan := [RecruitOrder.new("spearmen")]
	# Without a muster the recruit joins the Crown's 1st.
	var none := MusterForecast.recruit_destinations(s, CROWN, plan, s, s)
	assert_eq(none[0].army, a.id)
	# Merging the 1st into the 2nd takes the 1st away: the recruit joins the 2nd.
	var f := MusterForecast.of(s, CROWN, MusterOrder.merge(a.id, b.id), plan)
	assert_eq(f.recruits[0].army, b.id)
	assert_eq(f.recruits[0].was, a.id, "it would have joined the 1st without the muster")
	assert_true(String(f.text).contains("Your new Spearmen joins the Crown's 2nd if it is still at Crownkeep"), f.text)
	assert_eq(Kit.events(Kit.resolve(s, {CROWN: [MusterOrder.merge(a.id, b.id), plan[0]]}), "recruited")[0].armies, [b.id])
	# If every army marched away, the recruit forms a new one.
	var away := MusterForecast.of(s, CROWN, MusterOrder.transfer(a.id, "", [0]), [MoveOrder.new(a.id, "westwatch"), MoveOrder.new(b.id, "highcrag"),
		MoveOrder.new("kingdom-3", "rivermarch"), plan[0]])
	assert_true(away.ok)
	var new_row: Dictionary = away.recruits[0]
	assert_true(new_row.new and String(new_row.text).begins_with("forms a new army, the Crown's "), new_row.text)


func test_a_commander_recruit_joins_the_first_army_without_a_commander() -> void:
	var s := Kit.game()
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen"])
	var rows := MusterForecast.recruit_destinations(s, CROWN, [RecruitOrder.new("knight_captain")], s, s)
	assert_eq(rows[0].army, b.id, "the first army has its commander, so the new one leads the second")


func test_a_recruit_into_a_blessed_army_is_outside_its_blessing() -> void:
	var s := Kit.game("magic")
	Kit.bless(s, CROWN, "crownkeep")
	var rows := MusterForecast.recruit_destinations(s, CROWN, [RecruitOrder.new("spearmen")], s, s)
	assert_eq(rows[0].outside, "Dawn Blessing")
	assert_true(String(rows[0].text).ends_with("outside its Dawn Blessing"), rows[0].text)


# --- the blessing note --------------------------------------------------------------------------------------------------

func test_fighters_joining_a_blessed_army_are_told_they_are_outside_it() -> void:
	var s := Kit.game("magic")
	var a := Kit.crown(s)
	Kit.bless(s, CROWN, "crownkeep")
	var plain := Kit.army(s, CROWN, "crownkeep", ["knights", "knights"])
	var f := MusterForecast.of(s, CROWN, MusterOrder.transfer(plain.id, a.id, [0, 1]), [])
	assert_true(f.ok)
	assert_eq(f.outside.size(), 1)
	assert_eq(f.outside[0].text, "2 fighters join the Crown's 1st; its Dawn Blessing won't cover them")
	assert_true(String(f.text).contains("2 fighters join the Crown's 1st; its Dawn Blessing won't cover them."), f.text)
	assert_eq(f.armies[1].after.outside, 2, "the card can show 2 outside")
	assert_eq(f.armies[1].after.covered, 4)


# --- the battle note -----------------------------------------------------------------------------------------------------

func test_the_battle_note_says_who_holds_and_who_marches() -> void:
	var s := Kit.game()
	var rival := Kit.army(s, CLANS, "westwatch", ["tuskers"])
	assert_eq(rival.location, "westwatch")
	var split := MusterOrder.transfer("kingdom-1", "", [0, 1])
	var f := MusterForecast.of(s, CROWN, split, [])
	assert_eq(f.battle, "", "nobody marches: no note")
	# The new army's move is ordered after the split, so ask about a second muster with the first one and the move in the plan.
	var book := OrderBook.new()
	assert_eq(book.submit(s, CROWN, split), "")
	assert_eq(book.submit(s, CROWN, MoveOrder.new("kingdom-2", "westwatch")), "")
	var again := MusterForecast.of(s, CROWN, MusterOrder.transfer("kingdom-1", "", [0]), book.orders_for(CROWN))
	assert_true(again.ok)
	assert_true(String(again.battle).contains("The part that stays (the Crown's 1st and the Crown's 3rd) defends Crownkeep"), again.battle)
	assert_true(String(again.battle).contains("the part that marches (the Crown's 2nd) goes to Westwatch and meets the Thornmane Clans there as an army of its own"), again.battle)
	assert_true(String(again.text).contains(again.battle), "the note is part of the forecast's text")


# --- the forecast equals the turn ---------------------------------------------------------------------------------------

func test_the_forecast_equals_what_the_turn_does() -> void:
	var s := Kit.game("sieges")
	var a := Kit.crown(s)
	a.engines = 2
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen", "spearmen"], "knight_captain", 1)
	for order in [MusterOrder.transfer(a.id, "", [0, 1], true, 1), MusterOrder.merge(b.id, a.id), MusterOrder.swap(a.id, b.id),
			MusterOrder.transfer(b.id, a.id, [1], false, 1)]:
		var f := MusterForecast.of(s, CROWN, order, [])
		assert_true(f.ok, order.describe())
		var r := Kit.resolve(s, {CROWN: [order]})
		assert_eq(Kit.events(r, "order_rejected"), [])
		for row in f.armies:
			var real: Army = r.new_state.find_army(row.id)
			if bool(row.gone):
				assert_eq(real, null, "%s is gone, as forecast" % row.id)
				continue
			assert_eq(Kit.types(real), row.after.units, "%s: the units forecast are the units after the turn (%s)" % [row.id, order.describe()])
			assert_eq(real.commander.type.id if real.commander != null else "", row.after.commander)
			assert_eq(real.engines, row.after.engines)
			assert_eq(StubBattleResolver.army_strength(real), row.after.strength)
