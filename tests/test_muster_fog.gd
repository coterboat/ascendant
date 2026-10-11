extends "res://tests/test_case.gd"
## ARM-1 (design/ARM1_SPLIT_MERGE.md §5): musters under fog. A rival's view is built from pooled stand-ins per (faction,
## province): a muster that leaves the pooled composition alone changes nothing a rival sees; one that changes it (a
## blessing's partition, the commanders) shows exactly as the same composition reached without a muster would. The snapshot
## probe: a rival's view after a muster equals the view of the same composition built by hand, in clear sight, in a glimpse
## and from memory, including transfers, merges and disbands that move engines. The muster events are the owner's alone.

const Kit := preload("res://tests/muster_test_kit.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const AT := "highcrag"       # where the Crown's armies stand
const NEAR := "thornvale"    # next to it: a scout there glimpses it
const FAR := "ironspike"     # a province the scout sees nothing of the Crown's from


## A fog game with no field armies but the rulers', and the Clans' scout (a lone Tusker: sight 1) far away.
func _base(kind: String) -> GameState:
	var s := Kit.game(kind)
	var keep: Array[Army] = []
	for a in s.armies:
		if a.ruler != null:
			keep.append(a)
	s.armies = keep
	Kit.army(s, CLANS, FAR, ["tuskers"])
	return s


func _scout(s: GameState) -> Army:
	for a in s.armies:
		if a.owner == CLANS and a.ruler == null:
			return a
	return null


## The viewer's view of `s` with its scout at `where`, as a saved dictionary (the whole view, notes and all).
func _dump(s: GameState, where: String, memory: Dictionary = {}) -> String:
	var st := s.deep_copy()
	_scout(st).location = where
	var view := FogRules.view_state(st, CLANS, memory, FogRules.new_intel(st, CLANS))
	assert_true(view != null, "the view builds")
	return JSON.stringify(view.to_dict())


## What the Clans see of `s` in each of the three ways: {"clear", "glimpse", "memory"}.
func _views(s: GameState) -> Dictionary:
	var st := s.deep_copy()
	_scout(st).location = AT
	var seen := FogRules.new_memory(st, CLANS)  # watched from the province itself: remembered exactly
	_scout(st).location = FAR
	var away := FogRules.remember(seen, CLANS, null, st, [])
	return {"clear": _dump(s, AT), "glimpse": _dump(s, NEAR), "memory": _dump(s, FAR, away)}


func _same_views(a: GameState, b: GameState, what: String) -> void:
	var va := _views(a)
	var vb := _views(b)
	for mode in ["clear", "glimpse", "memory"]:
		assert_eq(va[mode], vb[mode], "%s: the same view in %s" % [what, mode])


func _muster(s: GameState, orders: Array) -> GameState:
	var c := s.deep_copy()
	for r in MusterRules.apply_all(c, CROWN, orders):
		assert_true(r.ok, "the muster applies: %s" % r.get("reason", ""))
	return c


func _bless(s: GameState, ids: Array) -> String:
	return String(MagicRules._begin(s, CROWN, "dawn_blessing", "blessing", AT, 1, 6, 0, ids).id)


# --- the pooled view does not depend on how the armies are divided -----------------------------------------------

func test_a_split_a_swap_and_a_two_commander_merge_change_nothing_a_rival_sees() -> void:
	var s := _base("fog_sieges")
	var x := Kit.army(s, CROWN, AT, ["spearmen", "spearmen", "knights"], "knight_captain", 2)
	var y := Kit.army(s, CROWN, AT, ["crossbowmen"], "knight_captain", 1)
	var plan := {
		"a split": [MusterOrder.transfer(x.id, "", [0, 1], false, 1)],
		"a split of the commander alone": [MusterOrder.transfer(x.id, "", [], true)],
		"a swap of commanders": [MusterOrder.swap(x.id, y.id)],
		"a merge with two commanders": [MusterOrder.merge(y.id, x.id)],
		"engines moved on": [MusterOrder.transfer(x.id, y.id, [2], false, 2)],
	}
	for what in plan:
		_same_views(_muster(s, plan[what]), s, what)
	# The views really do see the Crown there (a test that proves nothing would pass on an empty board).
	for mode in ["clear", "glimpse", "memory"]:
		assert_true(String(_views(s)[mode]).contains("seen-kingdom-highcrag"), "%s: the Crown's stand-in is in the view" % mode)


func test_a_transfer_equals_the_same_composition_built_by_hand() -> void:
	var s := _base("fog_sieges")
	var x := Kit.army(s, CROWN, AT, ["spearmen", "spearmen", "knights"], "knight_captain", 2)
	var y := Kit.army(s, CROWN, AT, ["crossbowmen"], "", 0)
	var after := _muster(s, [MusterOrder.transfer(x.id, y.id, [0], true, 1)])
	var ref := _base("fog_sieges")
	Kit.army(ref, CROWN, AT, ["spearmen", "knights"], "", 1)
	Kit.army(ref, CROWN, AT, ["crossbowmen", "spearmen"], "knight_captain", 1)
	_same_views(after, ref, "a transfer of a unit, the commander and an engine")


func test_a_merge_and_a_disband_that_carry_engines_equal_one_army_built_by_hand() -> void:
	var s := _base("fog_sieges")
	var x := Kit.army(s, CROWN, AT, ["spearmen", "spearmen"], "knight_captain", 1)
	var y := Kit.army(s, CROWN, AT, ["knights"], "", 2)
	var after := _muster(s, [MusterOrder.merge(x.id, y.id)])
	assert_eq(after.find_army(x.id), null, "the emptied army is disbanded")
	assert_eq(after.find_army(y.id).engines, 3, "with all its engines in the one that is left")
	var ref := _base("fog_sieges")
	Kit.army(ref, CROWN, AT, ["knights", "spearmen", "spearmen"], "knight_captain", 3)
	_same_views(after, ref, "a merge")
	# A transfer of everything to a new army disbands the source in the same way, and the pooled engines stay.
	var s2 := _base("fog_sieges")
	var z := Kit.army(s2, CROWN, AT, ["spearmen", "knights"], "knight_captain", 2)
	var moved := _muster(s2, [MusterOrder.transfer(z.id, "", [0, 1], true, 2)])
	assert_eq(moved.find_army(z.id), null)
	_same_views(moved, s2, "the whole army moved to a new one")


func test_engines_are_pooled_and_spread_over_the_stand_ins_not_by_their_real_carrier() -> void:
	# Three engines in the Crown's armies at the province: two stand-ins (two commanders) take them 3 then 0 in the view, however
	# the true armies carry them.
	var s := _base("fog_sieges")
	var x := Kit.army(s, CROWN, AT, ["spearmen"], "knight_captain", 1)
	var y := Kit.army(s, CROWN, AT, ["spearmen"], "knight_captain", 2)
	var one := _muster(s, [MusterOrder.transfer(y.id, x.id, [0], false, 2)])
	var two := _muster(s, [MusterOrder.transfer(x.id, y.id, [0], false, 1)])
	_same_views(one, two, "engines carried by one army or the other")
	var clear := FogRules.pool_now(s, CROWN, s.armies.filter(func(a): return a.owner == CROWN and a.ruler == null), FogRules.CLEAR, 1)
	assert_eq(clear.stand_ins.map(func(si): return si.engines), [3, 0], "three engines in the first stand-in, none in the second")
	var glimpse := FogRules.pool_now(s, CROWN, s.armies.filter(func(a): return a.owner == CROWN and a.ruler == null), FogRules.GLIMPSE, 1)
	assert_eq(glimpse.stand_ins.map(func(si): return si.engines), [0, 0], "a glimpse shows no engines")


# --- commanders -----------------------------------------------------------------------------------------------------

func test_commanders_pool_as_they_always_did() -> void:
	var s := _base("fog_sieges")
	var x := Kit.army(s, CROWN, AT, ["spearmen"], "knight_captain")
	var y := Kit.army(s, CROWN, AT, ["knights"], "knight_captain")
	var armies: Array = s.armies.filter(func(a): return a.owner == CROWN and a.ruler == null)
	var pool := FogRules.pool_now(s, CROWN, armies, FogRules.CLEAR, 1)
	assert_eq(pool.stand_ins.map(func(si): return String(si.slot)), ["", "c2"], "one stand-in with the units, one more for the second commander")
	# A merge that leaves the source's commander behind, and one that moves a commander into an army without one, keep the same two.
	var merged := _muster(s, [MusterOrder.merge(x.id, y.id)])
	var pool2 := FogRules.pool_now(merged, CROWN, merged.armies.filter(func(a): return a.owner == CROWN and a.ruler == null), FogRules.CLEAR, 1)
	assert_eq(pool2.stand_ins.map(func(si): return String(si.slot)), ["", "c2"])
	# One commander fewer: a stand-in fewer, which a rival in sight sees as any change of composition.
	var one_less := s.deep_copy()
	one_less.find_army(y.id).commander = null
	var pool3 := FogRules.pool_now(one_less, CROWN, one_less.armies.filter(func(a): return a.owner == CROWN and a.ruler == null), FogRules.CLEAR, 1)
	assert_eq(pool3.stand_ins.size(), 1)


# --- blessings, per fighter ---------------------------------------------------------------------------------------------

func test_the_blessed_and_plain_partition_follows_the_fighter_not_the_army() -> void:
	var s := _base("fog")
	var x := Kit.army(s, CROWN, AT, ["spearmen", "spearmen", "spearmen", "spearmen", "spearmen"], "knight_captain")
	var y := Kit.army(s, CROWN, AT, ["knights", "knights"])
	var e := _bless(s, [x.id])  # only the first army is under the blessing
	# Three Spearmen go from the blessed army to the plain one: they lose the blessing.
	var out := _muster(s, [MusterOrder.transfer(x.id, y.id, [0, 1, 2])])
	var ref := _base("fog")
	var rx := Kit.army(ref, CROWN, AT, ["spearmen", "spearmen"], "knight_captain")
	Kit.army(ref, CROWN, AT, ["knights", "knights", "spearmen", "spearmen", "spearmen"])
	_bless(ref, [rx.id])
	_same_views(out, ref, "three blessed units went to a plain army")
	var pool := FogRules.pool_now(out, CROWN, out.armies.filter(func(a): return a.owner == CROWN and a.ruler == null), FogRules.CLEAR, 1)
	assert_eq(pool.blessed, 2, "a rival in clear sight is told exactly 2 blessed")
	assert_eq(pool.total.shown, 7)
	# Units that join the blessed army from a plain one are outside the blessing: they are plain in the view.
	var back := _muster(out, [MusterOrder.transfer(y.id, x.id, [0, 1])])
	assert_true(back.find_army(x.id).units.back().has_status(UnitStatus.OUTSIDE_BLESSING, e))
	var ref2 := _base("fog")
	var r2x := Kit.army(ref2, CROWN, AT, ["spearmen", "spearmen"], "knight_captain")
	Kit.army(ref2, CROWN, AT, ["knights", "spearmen", "spearmen", "spearmen", "knights"])
	_bless(ref2, [r2x.id])
	_same_views(back, ref2, "two plain units joined the blessed army")
	var pool2 := FogRules.pool_now(back, CROWN, back.armies.filter(func(a): return a.owner == CROWN and a.ruler == null), FogRules.CLEAR, 1)
	assert_eq(pool2.blessed, 2, "still exactly 2: the newcomers add nothing to it")


func test_a_glimpse_counts_blessed_and_plain_by_the_unit() -> void:
	var s := _base("fog")
	var x := Kit.army(s, CROWN, AT, ["spearmen", "spearmen", "spearmen", "spearmen", "spearmen", "spearmen"])
	var e := _bless(s, [x.id])
	var armies: Array = s.armies.filter(func(a): return a.owner == CROWN and a.ruler == null)
	var before := FogRules.pool_now(s, CROWN, armies, FogRules.GLIMPSE, 1)
	for i in 4:
		x.units[i].add_status(UnitStatus.OUTSIDE_BLESSING, e)
	var after := FogRules.pool_now(s, CROWN, armies, FogRules.GLIMPSE, 1)
	assert_eq(before.total, after.total, "the same six units, rounded the same way")
	assert_ne(before.blessed, after.blessed, "but the blessed count follows the units now: six, then two")
	assert_eq(after.stand_ins.map(func(si): return String(si.slot)), ["", "b"], "a plain stand-in and a blessed one")
	var plain_n: int = after.stand_ins[0].units.size()
	var blessed_n: int = after.stand_ins[1].units.size()
	assert_true(plain_n > blessed_n and blessed_n > 0, "four plain, two blessed (each group rounded as a glimpse rounds it): %d and %d" % [plain_n, blessed_n])


# --- what is out of sight stays out of sight ------------------------------------------------------------------------------

func test_a_muster_out_of_sight_changes_nothing_the_viewer_is_shown() -> void:
	var s := _base("fog_sieges")
	# The Crown's armies stand at Rivermarch, far from the Clans' scout and from everything else they have.
	var x := Kit.army(s, CROWN, "rivermarch", ["spearmen", "spearmen", "knights"], "knight_captain", 2)
	var y := Kit.army(s, CROWN, "rivermarch", ["crossbowmen"], "knight_captain")
	var after := _muster(s, [MusterOrder.transfer(x.id, "", [0]), MusterOrder.swap(x.id, y.id), MusterOrder.merge(y.id, x.id)])
	for st in [s, after]:
		_scout(st).location = FAR
	var v0 := FogRules.view_state(s, CLANS, FogRules.new_memory(s, CLANS), FogRules.new_intel(s, CLANS))
	var v1 := FogRules.view_state(after, CLANS, FogRules.new_memory(after, CLANS), FogRules.new_intel(after, CLANS))
	assert_eq(JSON.stringify(v1.to_dict()), JSON.stringify(v0.to_dict()), "the viewer's view is byte for byte the same")
	# And through a real turn: the report of the viewer holds no muster event and no sighting.
	var r := Kit.resolve(s, {CROWN: [MusterOrder.transfer(x.id, "", [0]), MusterOrder.swap(x.id, y.id)]})
	var turn := FogRules.turn_for(r.events, CLANS, s, r.new_state, FogRules.new_memory(s, CLANS), FogRules.new_intel(s, CLANS))
	for e in turn.events:
		assert_false(MusterRules.EVENT_TYPES.has(String(e.type)), "no muster event reaches a rival: %s" % e.type)
		assert_false(bool(e.get("synthetic", false)) and String(e.type) != "sighting_lost", "no sighting changed: %s" % e.type)
	var mine := FogRules.turn_for(r.events, CROWN, s, r.new_state, FogRules.new_memory(s, CROWN), FogRules.new_intel(s, CROWN))
	assert_true(mine.events.any(func(e): return String(e.type) == "army_split"), "the owner is told")


func test_a_muster_in_sight_shows_only_what_changed_to_the_viewer() -> void:
	var s := _base("fog_sieges")
	var x := Kit.army(s, CROWN, AT, ["spearmen", "spearmen", "knights"], "knight_captain", 2)
	s.find_province(AT).owner = CROWN  # theirs already, so the turn captures nothing and the views differ only by what the musters did
	_scout(s).location = NEAR  # the Clans' scout glimpses the province from next door
	s.find_province(NEAR).owner = CLANS  # (and holds it, so the turn captures nothing there either)
	# A split changes no pooled composition: the viewer's report has no sighting at all.
	var r := Kit.resolve(s, {CROWN: [MusterOrder.transfer(x.id, "", [0], false, 1)]})
	var turn := FogRules.turn_for(r.events, CLANS, s, r.new_state, FogRules.new_memory(s, CLANS), FogRules.new_intel(s, CLANS))
	assert_false(turn.events.any(func(e): return String(e.type) in ["sighting_changed", "memory_added"] and String(e.get("owner", "")) == CROWN),
		"nothing changed in what the Clans see of the Crown")
	assert_eq(JSON.stringify(FogRules.view_model(turn.view_before)), JSON.stringify(FogRules.view_model(turn.view_after)), "the armies the viewer sees are the same before and after")
	# Disbanding the commander's army into another with its own commander changes the number of commanders the viewer sees.
	var y := Kit.army(s, CROWN, AT, ["crossbowmen"], "knight_captain")
	var r2 := Kit.resolve(s, {CROWN: [MusterOrder.merge(x.id, y.id)]})
	var turn2 := FogRules.turn_for(r2.events, CLANS, s, r2.new_state, FogRules.new_memory(s, CLANS), FogRules.new_intel(s, CLANS))
	assert_eq(JSON.stringify(FogRules.view_model(turn2.view_before)), JSON.stringify(FogRules.view_model(turn2.view_after)), "a merge that leaves both commanders is invisible too")


# --- the owner's own view and the playback fold ---------------------------------------------------------------------------

func test_the_owner_sees_its_new_armies_with_their_real_ids_and_the_fold_is_exact() -> void:
	var s := _base("fog_sieges")
	var x := Kit.army(s, CROWN, AT, ["spearmen", "spearmen", "knights"], "knight_captain", 1)
	var y := Kit.army(s, CROWN, AT, ["crossbowmen"], "knight_captain")
	var orders := [MusterOrder.transfer(x.id, "", [0, 1], false, 1), MusterOrder.swap(x.id, y.id), MusterOrder.merge(y.id, x.id)]
	var planned_ids := RulerRules.state_after_orders(s, CROWN, orders).armies.map(func(a): return a.id)
	var r := Kit.resolve(s, {CROWN: orders})
	var turn := FogRules.turn_for(r.events, CROWN, s, r.new_state, FogRules.new_memory(s, CROWN), FogRules.new_intel(s, CROWN))
	var view_ids: Array = turn.view_after.armies.filter(func(a): return a.owner == CROWN).map(func(a): return a.id)
	var want: Array = planned_ids.filter(func(id): return id.begins_with("kingdom-"))
	view_ids.sort()
	want.sort()
	assert_eq(view_ids, want, "the owner's view holds the armies with the ids the plan showed")
	var folded := FogRules.apply_view_events(FogRules.view_model(turn.view_before), turn.shown)
	assert_eq(JSON.stringify(folded), JSON.stringify(FogRules.view_model(turn.view_after)), "view_before folded with the report equals view_after")
	assert_false(turn.events.any(func(e): return bool(e.get("synthetic", false)) and String(e.get("owner", "")) == CROWN and String(e.type) == "army_changed"),
		"the fold needs no synthetic line for the owner's own musters: the muster events say it")
