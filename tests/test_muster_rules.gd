extends "res://tests/test_case.gd"
## ARM-1 (design/ARM1_SPLIT_MERGE.md §1-§2): the rules of a MusterOrder on one board, MusterRules.check and apply. Every
## refusal of §2 with its plain reason, indices against the sequential board, duplicate claims, multi-hop, merge with one
## or two commanders, swap, disbanding and engines (each carrier rule and the cap).

const Kit := preload("res://tests/muster_test_kit.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
## Ids that must never reach player-facing text.
const RAW_IDS := ["kingdom-", "beasts-", "knight_captain", "crownkeep", "westwatch", "_"]


func _check_ok(s: GameState, order: MusterOrder, what: String) -> void:
	assert_eq(MusterRules.check(s, CROWN, order), {}, "%s is allowed" % what)


## Asserts `order` is refused with `code`, and that its reason is words, not ids.
func _refused(s: GameState, order: MusterOrder, code: String, what: String) -> void:
	var c := MusterRules.check(s, CROWN, order)
	assert_false(c.is_empty(), "%s is refused" % what)
	if c.is_empty():
		return
	assert_eq(c.code, code, "%s: code" % what)
	assert_false(String(c.reason).is_empty(), "%s says why" % what)
	for id in RAW_IDS:
		assert_false(String(c.reason).contains(id), "%s: no raw id '%s' in: %s" % [what, id, c.reason])
	var again := MusterRules.apply(s, CROWN, order)
	assert_false(again.ok, "%s: apply refuses it too" % what)


# --- split --------------------------------------------------------------------------------------------

func test_a_split_forms_a_new_army_with_the_next_real_id() -> void:
	var s := Kit.game()
	var a := Kit.crown(s)
	var expected_id := String(s.peek_army_ids(CROWN, 1)[0])
	var r := MusterRules.apply(s, CROWN, MusterOrder.transfer(a.id, "", [0, 2]))
	assert_true(r.ok, "the split applies")
	assert_eq(r.info.to, expected_id, "the new army has the id the plan would have shown")
	assert_true(r.info.created and r.info.disbanded == [], "a new army, nobody disbanded")
	var b := s.find_army(expected_id)
	assert_true(b != null and b.owner == CROWN and b.location == a.location, "it stands where the source stands, under the same faction")
	assert_eq(Kit.types(b), ["spearmen", "knights"], "it holds the chosen units")
	assert_eq(Kit.types(a), ["crossbowmen"], "the source keeps the rest")
	assert_true(a.commander != null and b.commander == null, "the commander stayed")
	assert_eq(r.info.units, ["spearmen", "knights"])
	assert_eq(r.info.commander, "")
	assert_eq(s.next_army_ids[CROWN], int(expected_id.substr(CROWN.length() + 1)) + 1, "one id was handed out")
	var errors := []
	assert_true(s.validate(errors), "the state is still valid: %s" % [errors])


func test_the_place_in_the_list_does_not_matter_and_hp_goes_with_the_unit() -> void:
	var one := Kit.game()
	var two := Kit.game()
	for s in [one, two]:
		Kit.crown(s).units[2].current_hp = 3
	var r := MusterRules.apply(one, CROWN, MusterOrder.transfer("kingdom-1", "", [0, 2]))
	MusterRules.apply(two, CROWN, MusterOrder.transfer("kingdom-1", "", [2, 0]))
	assert_eq(JSON.stringify(one.to_dict()), JSON.stringify(two.to_dict()), "[0, 2] and [2, 0] are the same split")
	assert_eq(one.find_army(r.info.to).units[1].current_hp, 3, "the wounded Knights took their wounds with them")


func test_a_split_can_take_the_commander_alone() -> void:
	var s := Kit.game()
	var a := Kit.crown(s)
	var r := MusterRules.apply(s, CROWN, MusterOrder.transfer(a.id, "", [], true))
	assert_true(r.ok, "a commander may leave alone, as a commander-only army (today's rules allow one)")
	assert_eq(r.info.commander, "knight_captain")
	assert_true(a.commander == null and a.units.size() == 3, "the three units stay without a leader")
	var b := s.find_army(r.info.to)
	assert_true(b.units.is_empty() and b.commander != null, "the new army is the commander alone")


func test_a_full_transfer_to_a_new_army_disbands_the_source() -> void:
	var s := Kit.game()
	var a := Kit.crown(s)
	var r := MusterRules.apply(s, CROWN, MusterOrder.transfer(a.id, "", [0, 1, 2], true))
	assert_true(r.ok)
	assert_eq(r.info.disbanded, ["kingdom-1"], "the emptied source is gone")
	assert_eq(s.find_army("kingdom-1"), null)
	assert_eq(s.find_army(r.info.to).units.size(), 3)


# --- refusals (§2) ------------------------------------------------------------------------------------

func test_every_refusal_has_a_code_and_a_plain_reason() -> void:
	var s := Kit.game()
	var a := Kit.crown(s)
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen", "spearmen"], "knight_captain")
	var far := Kit.army(s, CROWN, "westwatch", ["spearmen"])
	var rival := Kit.clans(s)
	_refused(s, MusterOrder.transfer(a.id, "", []), "empty_transfer", "an empty transfer")
	_refused(s, MusterOrder.transfer(a.id, "", [1, 1]), "duplicate_unit", "a unit sent twice in one order")
	_refused(s, MusterOrder.transfer(a.id, "", [3]), "bad_unit", "a unit place past the army's end")
	_refused(s, MusterOrder.transfer(a.id, "", [-1]), "bad_unit", "a negative unit place")
	_refused(s, MusterOrder.transfer(a.id, far.id, [0]), "different_province", "a different province")
	_refused(s, MusterOrder.transfer(a.id, rival.id, [0]), "not_your_army", "a rival's army as the target")
	_refused(s, MusterOrder.transfer(rival.id, "", [0]), "not_your_army", "a rival's army as the source")
	_refused(s, MusterOrder.transfer(a.id, b.id, [], true), "two_commanders", "two commanders")
	_refused(s, MusterOrder.transfer(a.id, a.id, [0]), "same_army", "an army with itself")
	_refused(s, MusterOrder.transfer("kingdom-99", "", [0]), "unknown_army", "an army that does not exist")
	_refused(s, MusterOrder.transfer(a.id, "kingdom-99", [0]), "unknown_army", "a target that does not exist")
	b.commander = null
	_refused(s, MusterOrder.transfer(b.id, "", [], true), "no_commander", "a commander that is not there")
	_refused(s, MusterOrder.swap(a.id, b.id), "no_commander", "a swap with an army that has no commander")
	_refused(s, MusterOrder.transfer(a.id, b.id, [0], false, 1), "not_enough_engines", "engines the source does not carry")
	_refused(s, MusterOrder.swap(a.id, far.id), "different_province", "a swap across provinces")
	var malformed := MusterOrder.new()
	malformed.malformed = "it has no units"
	_refused(s, malformed, "malformed_muster", "a malformed order")
	_refused(s, MusterOrder.new("teleport", a.id, b.id), "unknown_muster", "an unknown kind")


func test_a_ruler_travels_alone_on_both_sides() -> void:
	var s := Kit.game("rulers")
	var ruler := RulerRules.ruler_army(s, CROWN)
	var field := Kit.crown(s)
	assert_eq(ruler.location, field.location, "the ruler stands with the field army")
	var other := Kit.army(s, CROWN, field.location, ["spearmen"])
	_refused(s, MusterOrder.transfer(ruler.id, "", [0]), "ruler_army", "a ruler's army as the source")
	_refused(s, MusterOrder.transfer(field.id, ruler.id, [0]), "ruler_army", "a ruler's army as the target")
	_refused(s, MusterOrder.merge(other.id, ruler.id), "ruler_army", "a merge into a ruler's army")
	_refused(s, MusterOrder.merge(ruler.id, other.id), "ruler_army", "a merge of a ruler's army")
	_refused(s, MusterOrder.swap(field.id, ruler.id), "ruler_army", "a swap with a ruler's army")
	var r := MusterRules.apply(s, CROWN, MusterOrder.transfer(field.id, other.id, [0]))
	assert_true(r.ok, "the same province, with the ruler present, is fine between field armies")
	assert_true(ruler.units.is_empty() and ruler.commander == null and ruler.ruler != null, "the ruler's army is untouched")


func test_a_refused_muster_changes_nothing_and_hands_out_no_id() -> void:
	var s := Kit.game()
	var before := JSON.stringify(s.to_dict())
	var r := MusterRules.apply(s, CROWN, MusterOrder.transfer("kingdom-1", "", [9]))
	assert_false(r.ok)
	assert_eq(JSON.stringify(s.to_dict()), before, "the state is byte-identical, next_army_ids included")


# --- merge ----------------------------------------------------------------------------------------------

func test_merge_moves_everything_and_the_commander_when_the_target_has_none() -> void:
	var s := Kit.game()
	var a := Kit.crown(s)
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen", "spearmen"])
	var r := MusterRules.apply(s, CROWN, MusterOrder.merge(a.id, b.id))
	assert_true(r.ok)
	assert_eq(Kit.types(b), ["spearmen", "spearmen", "spearmen", "crossbowmen", "knights"], "the source's units follow the target's")
	assert_true(b.commander != null and b.commander.type.id == "knight_captain", "the commander went with them")
	assert_eq(r.info.disbanded, [a.id], "the emptied source disbands")
	assert_false(r.info.commander_left)
	assert_eq(s.find_army(a.id), null)


func test_merge_all_with_two_commanders_leaves_the_sources_commander_as_its_own_army() -> void:
	var s := Kit.game()
	var a := Kit.crown(s)
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen"], "knight_captain")
	var r := MusterRules.apply(s, CROWN, MusterOrder.merge(a.id, b.id))
	assert_true(r.ok)
	assert_true(r.info.commander_left, "the forecast and the event say so")
	assert_eq(r.info.commander_stays, "knight_captain")
	assert_eq(r.info.disbanded, [], "the source is not disbanded: its commander is still in it")
	assert_true(a.units.is_empty() and a.commander != null, "the source is now its commander alone")
	assert_eq(b.units.size(), 4, "every unit moved")
	assert_true(b.commander != null, "the target kept its own commander")
	assert_eq(s.find_army(a.id), a, "the source keeps its id and its name")


func test_merge_that_would_move_nothing_is_refused() -> void:
	var s := Kit.game()
	var a := Kit.crown(s)
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen"], "knight_captain")
	a.units.clear()
	_refused(s, MusterOrder.merge(a.id, b.id), "nothing_to_merge", "two commanders and no units")
	var c := Kit.army(s, CROWN, "crownkeep", ["spearmen"])
	_check_ok(s, MusterOrder.merge(a.id, c.id), "a commander alone into an army without one")


# --- swap -----------------------------------------------------------------------------------------------

func test_swap_exchanges_the_commanders_in_one_step() -> void:
	var s := Kit.game()
	var a := Kit.crown(s)
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen"], "knight_captain")
	a.commander.current_hp = 5
	var ca := a.commander
	var cb := b.commander
	var r := MusterRules.apply(s, CROWN, MusterOrder.swap(a.id, b.id))
	assert_true(r.ok)
	assert_true(a.commander == cb and b.commander == ca, "each army has the other's commander, wounds and all")
	assert_eq(b.commander.current_hp, 5)
	assert_eq(r.info.disbanded, [])
	assert_eq(Kit.types(a), ["spearmen", "crossbowmen", "knights"], "no unit moved")
	assert_eq(r.info.commander, "knight_captain")


# --- sequential boards and multi-hop ---------------------------------------------------------------------

func test_indices_refer_to_the_board_as_earlier_musters_leave_it() -> void:
	var s := Kit.game()
	var a := Kit.crown(s)
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen"])
	var c := Kit.army(s, CROWN, "crownkeep", ["spearmen"])
	# Sends A's unit 0 (spearmen) to B, so A is now [crossbowmen, knights]: its index 0 is the crossbowmen.
	var first := MusterOrder.transfer(a.id, b.id, [0])
	var second := MusterOrder.transfer(a.id, c.id, [0])
	var results := MusterRules.apply_all(s, CROWN, [first, second])
	assert_true(results[0].ok and results[1].ok)
	assert_eq(Kit.types(b), ["spearmen", "spearmen"])
	assert_eq(Kit.types(c), ["spearmen", "crossbowmen"], "the second order's unit 0 was the crossbowman, the board having moved on")
	assert_eq(Kit.types(a), ["knights"])
	# An index that was fine on the start board is refused once earlier musters took units away.
	var s2 := Kit.game()
	var a2 := Kit.crown(s2)
	var out := MusterRules.apply_all(s2, CROWN, [MusterOrder.transfer(a2.id, "", [0, 1]), MusterOrder.transfer(a2.id, "", [2])])
	assert_true(out[0].ok)
	assert_false(out[1].ok, "A has one unit left: place 3 is gone")
	assert_eq(out[1].code, "bad_unit")
	assert_eq(s2.next_army_ids[CROWN], 3, "the refused muster allocated nothing: one new id in all")


func test_units_sent_on_a_multi_hop_arrive_where_the_plan_says() -> void:
	var s := Kit.game()
	var a := Kit.crown(s)
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen"])
	var c := Kit.army(s, CROWN, "crownkeep", ["spearmen"])
	var out := MusterRules.apply_all(s, CROWN, [MusterOrder.transfer(a.id, b.id, [1, 2]), MusterOrder.transfer(b.id, c.id, [1])])
	assert_true(out[0].ok and out[1].ok, "A to B, then on from B to C")
	assert_eq(Kit.types(a), ["spearmen"])
	assert_eq(Kit.types(b), ["spearmen", "knights"])
	assert_eq(Kit.types(c), ["spearmen", "crossbowmen"])
	# The same orders on a fresh copy, in the same order, give the same bytes (determinism).
	var s2 := Kit.game()
	var a2 := Kit.crown(s2)
	var b2 := Kit.army(s2, CROWN, "crownkeep", ["spearmen"])
	var c2 := Kit.army(s2, CROWN, "crownkeep", ["spearmen"])
	MusterRules.apply_all(s2, CROWN, [MusterOrder.transfer(a2.id, b2.id, [1, 2]), MusterOrder.transfer(b2.id, c2.id, [1])])
	assert_eq(JSON.stringify(s2.to_dict()), JSON.stringify(s.to_dict()))


func test_the_projection_skips_a_muster_that_fails_and_allocates_nothing_for_it() -> void:
	var s := Kit.game()
	var good := MusterOrder.transfer("kingdom-1", "", [0])
	var bad := MusterOrder.transfer("kingdom-1", "", [7])
	var good2 := MusterOrder.transfer("kingdom-1", "", [0])
	var projected := MusterRules.project(s, CROWN, [good, bad, good2])
	assert_true(projected != s, "a projection is a copy")
	assert_eq(projected.armies.size(), s.armies.size() + 2, "two new armies, the refused one made none")
	assert_eq(s.armies.size(), 2, "the real state is untouched")
	assert_eq(int(s.next_army_ids[CROWN]), 2, "and so is its counter")
	assert_eq(MusterRules.project(s, CROWN, [MoveOrder.new("kingdom-1", "westwatch")]), s, "no musters: the state itself")


# --- engines ----------------------------------------------------------------------------------------------

func test_engines_move_only_when_the_order_says_so() -> void:
	var s := Kit.game("sieges")
	var a := Kit.crown(s)
	a.engines = 2
	var r := MusterRules.apply(s, CROWN, MusterOrder.transfer(a.id, "", [0]))
	assert_true(r.ok)
	var b := s.find_army(r.info.to)
	assert_eq(b.engines, 0, "a split with no engines named takes none")
	assert_eq(a.engines, 2)
	var r2 := MusterRules.apply(s, CROWN, MusterOrder.transfer(a.id, "", [0], false, 1))
	assert_true(r2.ok)
	assert_eq(s.find_army(r2.info.to).engines, 1, "engines named go")
	assert_eq(a.engines, 1)
	assert_eq(r2.info.engines, 1)


func test_engines_need_a_fighter_to_carry_them_and_stop_at_the_cap() -> void:
	var s := Kit.game("sieges")
	var a := Kit.crown(s)
	a.engines = FortData.ARMY_ENGINES_MAX
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen"], "", 1)
	_refused(s, MusterOrder.transfer(a.id, b.id, [0], false, FortData.ARMY_ENGINES_MAX), "engine_cap", "engines past the cap")
	_refused(s, MusterOrder.transfer(a.id, b.id, [0], false, FortData.ARMY_ENGINES_MAX + 1), "not_enough_engines", "more engines than it has")
	_check_ok(s, MusterOrder.transfer(a.id, b.id, [0], false, FortData.ARMY_ENGINES_MAX - b.engines), "engines up to the cap")
	# A source left with no fighter can't keep its engines.
	_refused(s, MusterOrder.transfer(a.id, "", [0, 1, 2], true, 1), "engines_stranded", "a source that disbands with engines on it")
	_check_ok(s, MusterOrder.transfer(a.id, "", [0, 1, 2], true, FortData.ARMY_ENGINES_MAX), "the same disbanding when the engines go too")
	# A merge sends the engines along or is refused.
	var c := Kit.army(s, CROWN, "crownkeep", ["spearmen"], "", 1)
	_refused(s, MusterOrder.merge(a.id, c.id), "engine_cap", "a merge the target can't carry the engines of")
	a.engines = 1
	var m := MusterRules.apply(s, CROWN, MusterOrder.merge(a.id, c.id))
	assert_true(m.ok)
	assert_eq(c.engines, 2, "the merge brought its engines")
	assert_eq(m.info.engines, 1)


## ARM-1 (director's fix round): engines may travel on their own between two armies that stand there, as the receiver carries
## them; a new army has no fighter yet, so an engines-only split is refused in words.
func test_engines_alone_go_to_an_army_that_can_carry_them() -> void:
	var s := Kit.game("sieges")
	var a := Kit.crown(s)
	a.engines = 2
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen"])
	var units_before := Kit.types(a)
	var order := MusterOrder.transfer(a.id, b.id, [], false, 1)
	_check_ok(s, order, "one engine alone into an army that fights")
	var r := MusterRules.apply(s, CROWN, order)
	assert_true(r.ok)
	assert_eq([a.engines, b.engines], [1, 1], "the engine moved")
	assert_eq(Kit.types(a), units_before, "no unit moved with it")
	assert_true(a.commander != null and b.commander == null, "nor did the commander")
	assert_eq([r.info.units, r.info.commander, r.info.engines, r.info.created, r.info.disbanded], [[], "", 1, false, []])
	var errors := []
	assert_true(s.validate(errors), "the state is still valid: %s" % [errors])
	# All of them, too: the source keeps its fighters, so it isn't stranded.
	_check_ok(s, MusterOrder.transfer(a.id, b.id, [], false, 1), "the last engine")
	# A receiver that is only a commander carries them, as it does in a merge.
	var c := Kit.army(s, CROWN, "crownkeep", [], "knight_captain")
	_check_ok(s, MusterOrder.transfer(a.id, c.id, [], false, 1), "engines to an army of a commander alone")


func test_engines_alone_never_form_an_army_and_keep_the_other_limits() -> void:
	var s := Kit.game("sieges")
	var a := Kit.crown(s)
	a.engines = 2
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen"])
	var next_id: int = int(s.next_army_ids[CROWN])
	_refused(s, MusterOrder.transfer(a.id, "", [], false, 1), "engines_alone", "engines alone into a new army")
	assert_eq(int(s.next_army_ids[CROWN]), next_id, "the refusal handed out no army id")
	assert_true(String(MusterRules.check(s, CROWN, MusterOrder.transfer(a.id, "", [], false, 1)).reason).contains("ride only with a fighter"), "and says why in words")
	_refused(s, MusterOrder.transfer(a.id, b.id, [], false, 3), "not_enough_engines", "more engines than the source has")
	_refused(s, MusterOrder.transfer(a.id, b.id, [], false, 0), "empty_transfer", "no one and no engines")
	b.engines = FortData.ARMY_ENGINES_MAX
	_refused(s, MusterOrder.transfer(a.id, b.id, [], false, 1), "engine_cap", "engines past the receiver's cap")
	b.engines = 0
	var ruler := Kit.army(s, CROWN, "crownkeep", ["spearmen"])
	ruler.ruler = Unit.new(s.find_faction(CROWN).ruler_unit_type, CROWN)
	_refused(s, MusterOrder.transfer(a.id, ruler.id, [], false, 1), "ruler_army", "engines to a ruler's army")
	var other := Kit.army(s, CROWN, "westwatch", ["spearmen"])
	_refused(s, MusterOrder.transfer(a.id, other.id, [], false, 1), "different_province", "engines to an army elsewhere")


## A merge whose source is a commander and engines, into an army that has a commander: the engines go, the commander stays behind
## as an army of its own (the forecast, the plan and the resolver all say the same).
func test_a_merge_of_a_commander_with_engines_into_a_commanded_army_moves_the_engines() -> void:
	var s := Kit.game("sieges")
	var a := Kit.crown(s)
	var cap := Kit.army(s, CROWN, "crownkeep", [], "knight_captain", 2)
	var target := a  # the Crown's 1st has a commander and fighters
	assert_true(target.commander != null and cap.units.is_empty())
	var merge := MusterOrder.merge(cap.id, target.id)
	_check_ok(s, merge, "the merge")
	var f := MusterForecast.of(s, CROWN, merge, [])
	assert_true(f.ok, "the forecast agrees")
	assert_eq([f.armies[0].after.engines, f.armies[0].after.commander, f.armies[0].gone], [0, "knight_captain", false], "the commander stays as an army of its own")
	assert_eq([f.armies[1].after.engines, f.armies[1].before.engines], [2, 0], "the engines are with the target")
	var plan := OrderBook.new()
	assert_eq(plan.submit(s, CROWN, merge), "", "the plan takes it")
	var r := Kit.resolve(s, {CROWN: [merge]})
	assert_eq(Kit.events(r, "order_rejected"), [])
	var left: Army = r.new_state.find_army(cap.id)
	assert_true(left != null and left.commander != null and left.units.is_empty() and left.engines == 0, "the commander is its own army, with no engines")
	assert_eq(r.new_state.find_army(target.id).engines, 2, "the target carries the engines")
	assert_eq(Kit.events(r, "armies_merged").size(), 1)
	assert_eq(Kit.events(r, "army_disbanded"), [], "no one was disbanded")
	var sentence := MusterRules.event_sentence(r.new_state, Kit.events(r, "armies_merged")[0])
	assert_true(sentence.contains("stays behind"), sentence)
	# The same in the rules, applied: the engines land where the forecast said.
	var applied := MusterRules.apply(s, CROWN, merge)
	assert_true(applied.ok and applied.info.commander_left and applied.info.engines == 2)
	# Without engines it is still nothing to merge.
	cap.engines = 0
	_refused(s, MusterOrder.merge(cap.id, target.id), "nothing_to_merge", "a commander alone into a commanded army")


func test_a_game_without_sieges_has_no_engines_to_move() -> void:
	var s := Kit.game()
	_refused(s, MusterOrder.transfer("kingdom-1", "", [0], false, 1), "not_enough_engines", "an engine in a game without sieges")


# --- the state stays valid ---------------------------------------------------------------------------------

func test_every_applied_muster_leaves_a_valid_state() -> void:
	for kind in ["m1", "rulers", "paths", "sieges", "magic"]:
		var s := Kit.game(kind)
		var a := Kit.crown(s)
		var b := Kit.army(s, CROWN, a.location, ["spearmen"], "knight_captain")
		var errors := []
		for order in [MusterOrder.transfer(a.id, "", [0]), MusterOrder.swap(a.id, b.id), MusterOrder.merge(b.id, a.id)]:
			var r := MusterRules.apply(s, CROWN, order)
			assert_true(r.ok, "%s: %s" % [kind, order.describe()])
			assert_true(s.validate(errors), "%s after %s: %s" % [kind, order.describe(), errors])
			assert_eq(JSON.stringify(s.deep_copy([]).to_dict()), JSON.stringify(s.to_dict()), "%s: a copy of the result is the same bytes" % kind)
