extends "res://tests/test_case.gd"
## ARM-1 (design/ARM1_SPLIT_MERGE.md §4): the muster pass in the resolver. It runs FIRST in the existing orders phase,
## before MagicRules.pinned_armies and before any check_move, check_cast or check_siege_order; no phase was added (the phase
## arrays and the codex's phase order are pinned here); the five structured events with their sentences; determinism;
## a muster that fails there; battles after a split (who holds, several roads, a border swap).

const Kit := preload("res://tests/muster_test_kit.gd")
const F := preload("res://tests/siege_fixtures.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const FORGE := ["crown_drillyard", "crown_charters", "crown_oath_forge", "shield_of_law", "sanctum_ward", "bastion", "sunlance", "dawn_blessing"]
## The codex sentence ARM-1 adds to the phase-order entry, and the hash of the entry as it was before it (pinned byte for byte).
const PHASE_SENTENCE := " Inside step 2, a faction's muster orders (splitting its armies, merging them, swapping commanders) apply first, before any other order is checked, so an army you split off can be given a move the same turn: see Splitting and merging armies."
const PHASE_ORDER_HASH_BEFORE_ARM1 := "4fcc972baab40a12da9b85634e31012f9636dfb7855e2587ca334d3b6396d434"


func _magic_game() -> GameState:
	var s := AscensionRules.with_nodes(Kit.game("magic"), CROWN, FORGE)
	for f in s.factions:
		f.gold = 200
	return s


# --- no new phase ---------------------------------------------------------------------------------------

func test_the_phase_lists_and_the_codex_phase_order_are_unchanged() -> void:
	assert_eq(TurnResolver.PHASES, ["sacrifice", "orders", "movement", "battles", "capture", "recruitment", "income", "rulers"])
	assert_eq(TurnResolver.PATH_PHASES, ["sacrifice", "orders", "movement", "battles", "capture", "recruitment", "income", "research", "rulers"])
	assert_eq(TurnResolver.MAGIC_PHASES, ["sacrifice", "orders", "rituals", "movement", "battles", "capture", "recruitment", "income", "research",
		"rulers", "enchantments"])
	assert_eq(TurnResolver.phases(GameState.new(7)), TurnResolver.PHASES)
	assert_false(TurnResolver.phases(Kit.game("magic_sieges")).has("muster"), "no muster phase in any game")
	assert_false(TurnResolver.PHASES.has("muster") or TurnResolver.PATH_PHASES.has("muster") or TurnResolver.MAGIC_PHASES.has("muster"))
	var text := RulesCodex.text("phase_order")
	assert_true(text.contains(PHASE_SENTENCE), "the codex gains its one sentence")
	assert_eq(text.replace(PHASE_SENTENCE, "").sha256_text(), PHASE_ORDER_HASH_BEFORE_ARM1, "and everything else in the entry is byte for byte what it was")
	# Every muster event says it happened in the orders phase.
	var s := Kit.game()
	var r := Kit.resolve(s, {CROWN: [MusterOrder.transfer("kingdom-1", "", [0]), MusterOrder.swap("kingdom-1", "kingdom-2")]})
	for e in r.events:
		if MusterRules.EVENT_TYPES.has(String(e.type)):
			assert_eq(e.phase, "orders")


func test_the_codex_explains_splitting_and_merging() -> void:
	var entry := RulesCodex.entry("muster")
	assert_eq(entry.title, "Splitting and merging armies")
	var text := String(entry.text)
	for part in ["split", "merge", "swap", "ruler travels alone", "at most one commander", "disbanded", "Blessings", "defends the province"]:
		assert_true(text.contains(part), "the entry says '%s'" % part)
	assert_true(text.contains("at most %d" % FortData.ARMY_ENGINES_MAX), "and the engine cap, from the data")
	assert_true(RulesCodex.text("phase_order").contains("Splitting and merging armies"), "the phase order points at it")
	assert_true(RulesCodex.text("blessing").contains("fighter by fighter"), "and the blessing's entry says what a muster does to it")
	for t in MusterRules.EVENT_TYPES:
		assert_true(RulesCodex.ENTRIES.has(MusterRules.CODEX), "the events' codex entry exists")
	assert_true(RulesCodex.ENTRIES.has(UnitStatus.codex_id(UnitStatus.OUTSIDE_BLESSING)))


func test_a_game_where_nobody_musters_resolves_as_before() -> void:
	var s := Kit.game()
	var orders := {CROWN: [MoveOrder.new("kingdom-1", "westwatch"), RecruitOrder.new("spearmen")], CLANS: [MoveOrder.new("beasts-1", "ebonpeak")]}
	var r := Kit.resolve(s, orders)
	for e in r.events:
		assert_false(MusterRules.EVENT_TYPES.has(String(e.type)), "no muster event: %s" % e.type)
	assert_eq(r.new_state.next_army_ids, {CROWN: 3, CLANS: 2}, "the counters are as before: the Crown's recruit formed a new army because the first marched out")


# --- the pass comes first ----------------------------------------------------------------------------------

func test_the_pass_runs_before_the_checks_so_a_new_army_can_move() -> void:
	var s := Kit.game()
	var orders := {CROWN: [MusterOrder.transfer("kingdom-1", "", [0, 2]), MoveOrder.new("kingdom-2", "westwatch")]}
	var r := Kit.resolve(s, orders)
	assert_eq(Kit.events(r, "order_rejected"), [], "the move for the army the split forms is not rejected: %s" % [r.events.map(func(e): return e.text)])
	var moved := Kit.events(r, "army_moved")
	assert_eq(moved.size(), 1)
	assert_eq(moved[0].armies, ["kingdom-2"])
	assert_eq(r.new_state.find_army("kingdom-2").location, "westwatch")
	assert_eq(r.new_state.find_army("kingdom-1").location, "crownkeep", "the rest stayed")
	assert_eq(Kit.types(r.new_state.find_army("kingdom-2")), ["spearmen", "knights"])


func test_the_pass_runs_before_the_pins_so_a_cast_pins_the_new_army() -> void:
	var s := _magic_game()
	var a := Kit.crown(s)
	a.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(CROWN), "adepts", s), CROWN))
	# The mage is split into the Crown's 3rd (the ruler's army is the 2nd); it casts; a move for it is rejected as pinned.
	var split := MusterOrder.transfer(a.id, "", [3])
	var orders := {CROWN: [split, CastOrder.new("sanctum_ward", "kingdom-3", "crownkeep"), MoveOrder.new("kingdom-3", "westwatch")]}
	assert_true(s.find_army("kingdom-3") == null, "the new army does not exist before the turn")
	var r := Kit.resolve(s, orders)
	var rejected := Kit.events(r, "order_rejected")
	assert_eq(rejected.size(), 1, "exactly one rejection: %s" % [rejected.map(func(e): return e.text)])
	assert_eq(rejected[0].cause, "pinned", "the move of the casting new army is pinned")
	assert_eq(Kit.events(r, "ritual_cast").size(), 1, "and the cast went ahead from the new army")
	assert_eq(r.new_state.find_army("kingdom-3").location, "crownkeep")


func test_the_pass_runs_before_the_siege_checks_so_a_new_army_can_sally() -> void:
	var s := F.state([
		["kingdom-1", CROWN, "stonegate", F.units("spearmen", 3) + ["knight_captain"]],
		["beasts-4", CLANS, "stonegate", F.units("tuskers", 4), 1],
	], {"stonegate": CROWN})
	s.current_turn = 5
	var p := s.find_province("stonegate")
	p.siege_since = 4
	p.walls = 3
	p.owned_since = 2
	p.lost = {"faction": CLANS, "owned_since": 1, "turn": 2}
	var r := F.resolve(s, {CROWN: [MusterOrder.transfer("kingdom-1", "", [0, 1]), SiegeOrder.sally("kingdom-2")]})
	assert_eq(F.events_of(r.events, "order_rejected"), [], "the sally by the new army passes its check: %s" % [r.events.map(func(e): return e.text)])
	assert_eq(F.events_of(r.events, "sally_called_off").size(), 0)
	assert_true(r.events.any(func(e): return String(e.type) == "battle"), "the new army sallied and fought")


# --- the plan and the resolution agree ------------------------------------------------------------------------

func test_the_ids_the_plan_showed_are_the_ids_the_turn_hands_out() -> void:
	var s := Kit.game()
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen", "spearmen"])
	var orders := [MusterOrder.transfer("kingdom-1", "", [0]), MusterOrder.transfer(b.id, "", [1]), MusterOrder.transfer("kingdom-1", "", [0])]
	var planned := RulerRules.state_after_orders(s, CROWN, orders)
	var r := Kit.resolve(s, {CROWN: orders})
	var plan_ids := planned.armies.map(func(a): return a.id)
	var real_ids: Array = r.new_state.armies.map(func(a): return a.id)
	plan_ids.sort()
	real_ids.sort()
	assert_eq(real_ids, plan_ids, "the same armies, the same ids")
	for id in plan_ids:
		var a_plan := planned.find_army(id)
		var a_real: Army = r.new_state.find_army(id)
		assert_eq(Kit.types(a_real), Kit.types(a_plan), "%s holds the same units in the plan and in the turn" % id)
		assert_eq(a_real.commander != null, a_plan.commander != null, "%s has the same commander status" % id)
	assert_eq(r.new_state.next_army_ids, planned.next_army_ids, "and the counters agree")


func test_the_plan_equals_the_turn_across_random_musters() -> void:
	var rng := SeededRNG.new(4242)
	for round in 12:
		var s := Kit.game("sieges")
		Kit.army(s, CROWN, "crownkeep", ["spearmen", "knights", "spearmen"], "knight_captain", 1)
		Kit.crown(s).engines = 2
		var orders := []
		var board := s
		for _i in 1 + rng.randi_range(0, 3):
			var mine := board.armies.filter(func(a): return a.owner == CROWN and a.ruler == null and a.location == "crownkeep")
			if mine.is_empty():
				break
			var from: Army = mine[rng.randi_range(0, mine.size() - 1)]
			var order: MusterOrder
			var pick := rng.randi_range(0, 3)
			if pick == 0 and mine.size() > 1:
				var other: Army = mine[(mine.find(from) + 1) % mine.size()]
				order = MusterOrder.swap(from.id, other.id) if rng.randi_range(0, 1) == 0 else MusterOrder.merge(from.id, other.id)
			else:
				var idx := []
				for i in from.units.size():
					if rng.randi_range(0, 1) == 0:
						idx.append(i)
				order = MusterOrder.transfer(from.id, "", idx, rng.randi_range(0, 3) == 0, rng.randi_range(0, mini(from.engines, 1)))
			if MusterRules.check(board, CROWN, order).is_empty():
				orders.append(order)
				board = RulerRules.state_after_orders(s, CROWN, orders)
		var r := Kit.resolve(s, {CROWN: orders})
		assert_eq(Kit.events(r, "order_rejected"), [], "round %d: the plan's musters all pass in the turn" % round)
		for a in board.armies:
			var real: Army = r.new_state.find_army(a.id)
			assert_true(real != null, "round %d: %s exists after the turn" % [round, a.id])
			if real != null:
				assert_eq([Kit.types(real), real.engines, real.commander != null], [Kit.types(a), a.engines, a.commander != null], "round %d: %s" % [round, a.id])
		assert_eq(r.new_state.armies.size(), board.armies.size(), "round %d: no army the plan did not have" % round)


# --- events -----------------------------------------------------------------------------------------------------

func test_the_five_events_are_structured_and_say_it_in_words() -> void:
	var s := Kit.game()
	var b := Kit.army(s, CROWN, "crownkeep", ["spearmen"], "knight_captain")
	var c := Kit.army(s, CROWN, "crownkeep", ["spearmen", "spearmen"])
	var orders := [
		MusterOrder.transfer("kingdom-1", "", [0, 2]),      # army_split -> kingdom-4
		MusterOrder.transfer("kingdom-1", c.id, [0]),       # units_transferred
		MusterOrder.swap("kingdom-1", b.id),                # commanders_swapped
		MusterOrder.merge(c.id, b.id),                      # armies_merged (c has no commander, b has one)
	]
	var r := Kit.resolve(s, {CROWN: orders})
	var types: Array = r.events.filter(func(e): return MusterRules.EVENT_TYPES.has(String(e.type))).map(func(e): return String(e.type))
	assert_eq(types, ["army_split", "units_transferred", "commanders_swapped", "armies_merged", "army_disbanded"], "in the order the musters ran, the disbanded army last")
	var split: Dictionary = Kit.events(r, "army_split")[0]
	assert_eq(split.numbers, {"from": "kingdom-1", "to": "kingdom-4", "units": ["spearmen", "knights"], "commander": "", "engines": 0})
	assert_eq(split.text, "Spearmen and Knights of the Crown's 1st formed the Crown's 4th at Crownkeep.")
	assert_eq(split.factions, [CROWN])
	assert_eq(split.provinces, ["crownkeep"])
	assert_eq(split.armies, ["kingdom-1", "kingdom-4"])
	assert_eq(split.codex, "muster")
	var swapped: Dictionary = Kit.events(r, "commanders_swapped")[0]
	assert_eq(swapped.numbers, {"a": "kingdom-1", "b": b.id, "a_commander": "knight_captain", "b_commander": "knight_captain"})
	var merged: Dictionary = Kit.events(r, "armies_merged")[0]
	assert_eq(merged.numbers.from, c.id)
	assert_eq(merged.numbers.to, b.id)
	assert_false(merged.numbers.commander_left)
	var gone: Dictionary = Kit.events(r, "army_disbanded")[0]
	assert_eq(gone.numbers, {"army": c.id})
	for e in r.events:
		if MusterRules.EVENT_TYPES.has(String(e.type)):
			assert_false(String(e.text).is_empty())
			assert_false(String(e.text).contains("kingdom-"), "no raw ids in the sentence: %s" % e.text)
			assert_eq(TurnReportText.line(e, r.events, r.new_state, CROWN), e.text, "the report line is the same sentence")


func test_the_sentence_reads_as_the_issue_says() -> void:
	var s := Kit.game()
	Kit.crown(s).units.clear()
	Kit.crown(s).units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(CROWN), "knights", s), CROWN))
	Kit.crown(s).units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(CROWN), "knights", s), CROWN))
	Kit.crown(s).units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(CROWN), "spearmen", s), CROWN))
	Kit.army(s, CROWN, "westwatch", ["spearmen"])  # the Crown's 2nd and 3rd stand elsewhere, so the new army is its 4th
	Kit.army(s, CROWN, "westwatch", ["spearmen"])
	var r := Kit.resolve(s, {CROWN: [MusterOrder.transfer("kingdom-1", "", [0, 1])]})
	var split: Dictionary = Kit.events(r, "army_split")[0]
	assert_eq(split.text, "Two Knights of the Crown's 1st formed the Crown's 4th at Crownkeep.", "the issue's own sentence")


func test_only_the_owner_reads_the_events() -> void:
	var s := Kit.game("fog")
	var a := Kit.crown(s)
	var r := Kit.resolve(s, {CROWN: [MusterOrder.transfer(a.id, "", [0])]})
	var mine := FogRules.filter_events(r.events, CROWN, s, r.new_state)
	var theirs := FogRules.filter_events(r.events, CLANS, s, r.new_state)
	assert_true(mine.any(func(e): return String(e.type) == "army_split"), "the owner is told")
	assert_false(theirs.any(func(e): return MusterRules.EVENT_TYPES.has(String(e.type))), "a rival is told nothing of the order")
	for t in MusterRules.EVENT_TYPES:
		assert_eq(FogData.AUDIENCE.get(t, {}), {"whole": "actor", "others": "none"}, "%s is listed in the audience table as the owner's alone" % t)


# --- determinism ------------------------------------------------------------------------------------------------

func test_the_same_orders_and_seed_resolve_to_the_same_bytes() -> void:
	var orders := {CROWN: [MusterOrder.transfer("kingdom-1", "", [0, 2], true), MoveOrder.new("kingdom-2", "westwatch")],
		CLANS: [MusterOrder.transfer("beasts-1", "", [1]), MoveOrder.new("beasts-2", "bloodfen")]}
	var a := Kit.resolve(Kit.game(), orders)
	var b := Kit.resolve(Kit.game(), orders)
	assert_eq(JSON.stringify(a.new_state.to_dict()), JSON.stringify(b.new_state.to_dict()))
	assert_eq(JSON.stringify(a.events), JSON.stringify(b.events))


func test_factions_muster_in_id_order_whichever_was_given_first() -> void:
	var one := {CROWN: [MusterOrder.transfer("kingdom-1", "", [0])], CLANS: [MusterOrder.transfer("beasts-1", "", [0])]}
	var two := {CLANS: [MusterOrder.transfer("beasts-1", "", [0])], CROWN: [MusterOrder.transfer("kingdom-1", "", [0])]}
	var r1 := Kit.resolve(Kit.game(), one)
	var r2 := Kit.resolve(Kit.game(), two)
	assert_eq(JSON.stringify(r1.events), JSON.stringify(r2.events))
	var who: Array = r1.events.filter(func(e): return String(e.type) == "army_split").map(func(e): return e.factions[0])
	assert_eq(who, [CLANS, CROWN], "beasts before kingdom: faction ids sort as text")


# --- a muster that fails in the pass -------------------------------------------------------------------------------

func test_a_muster_that_fails_is_rejected_and_so_is_everything_that_relied_on_it() -> void:
	var s := Kit.game()
	# A state the plan never saw: the second muster names a unit place that doesn't exist.
	var orders := {CROWN: [MusterOrder.transfer("kingdom-1", "", [9]), MusterOrder.transfer("kingdom-1", "", [0]),
		MoveOrder.new("kingdom-2", "westwatch"), MoveOrder.new("kingdom-3", "highcrag"), MoveOrder.new("kingdom-1", "rivermarch")]}
	var r := Kit.resolve(s, orders)
	var rejected := Kit.events(r, "order_rejected")
	assert_eq(rejected.size(), 5, "the bad muster, the muster after it, and the three moves for the armies they named: %s" % [rejected.map(func(e): return e.text)])
	assert_eq(rejected[0].cause, "bad_unit")
	assert_eq(rejected[1].cause, "muster_refused")
	assert_true(String(rejected[1].reason).contains("earlier muster"), rejected[1].reason)
	assert_eq(rejected[2].cause, "muster_refused")
	assert_true(String(rejected[2].reason).contains("The Crown's 2nd"), "it names the army by its name: %s" % rejected[2].reason)
	assert_eq(Kit.events(r, "army_split"), [], "no muster happened")
	assert_eq(r.new_state.armies.size(), 2, "nothing was formed")
	assert_eq(rejected[4].cause, "muster_refused", "the source's own move too: it was ordered on the board the muster was to leave")
	assert_eq(r.new_state.find_army("kingdom-1").location, "crownkeep", "so it stayed")
	assert_eq(r.new_state.next_army_ids[CROWN], 2, "and no id was handed out")


## The failure cascade, run directly on a FORGED order list (the plan never lets one through, so only the resolver sees it): the first
## muster is refused at resolution, and then every later muster of the faction is refused too (they were planned on the board it was to
## leave), every move, cast and siege order that names an army the refused ones touched or were to form is rejected with a reason that
## names the army, a planned new-army id that never formed can't be moved, and what needs none of them (a recruit, another faction's
## orders) still resolves.
func test_a_refused_muster_cascades_through_a_forged_order_list() -> void:
	var s := AscensionRules.with_nodes(Kit.game("magic_sieges"), CROWN, FORGE)
	for f in s.factions:
		f.gold = 200
	var other := Kit.army(s, CROWN, "crownkeep", ["spearmen", "spearmen"])  # an army the first muster does not name
	var pair := Kit.army(s, CROWN, "crownkeep", ["crossbowmen"])  # the one a later, valid merge names with it
	var fresh := Kit.army(s, CROWN, "crownkeep", ["knights"])  # an army no muster names, to sally with a relief that never formed
	var coming: Array = s.peek_army_ids(CROWN, 2)
	var first_new := String(coming[0])
	var second_new := String(coming[1])
	var fighters_before: int = Kit.crown(s).units.size()
	var counter_before: int = int(s.next_army_ids[CROWN])
	var orders := {
		CROWN: [
			MusterOrder.transfer("kingdom-1", "", [99]),  # 0: refused at resolution: there is no unit 100 (it was to form first_new)
			MusterOrder.transfer("kingdom-1", "", [0]),  # 1: nothing wrong with it alone, planned to form second_new: refused, the plan is gone
			MusterOrder.merge(pair.id, other.id),  # 2: two real armies and nothing wrong with it: refused too
			MoveOrder.new(first_new, "westwatch"),  # 3: an army that never formed
			MoveOrder.new(second_new, "highcrag"),  # 4: nor did this one
			CastOrder.new("sanctum_ward", second_new, "crownkeep"),  # 5: a cast by it
			SiegeOrder.sally(fresh.id, second_new),  # 6: a sally tied to it
			SiegeOrder.sally(first_new),  # 7: a sally by it
			MoveOrder.new("kingdom-1", "rivermarch"),  # 8: the refused muster's own source, ordered on the board the muster was to leave
			MoveOrder.new(other.id, "westwatch"),  # 9: named by the merge that was refused
			RecruitOrder.new("spearmen"),  # 10: names no army: resolves
		],
		CLANS: [MusterOrder.transfer("beasts-1", "", [0]), MoveOrder.new("beasts-2", "ebonpeak")],  # another faction's cascade is its own
	}
	var r := Kit.resolve(s, orders)
	var rejected := Kit.events(r, "order_rejected")
	var mine: Array = rejected.filter(func(e): return Array(e.factions).has(CROWN))
	assert_eq(mine.size(), 10, "all ten of the Crown's orders but the recruit are rejected: %s" % [mine.map(func(e): return "%s: %s" % [e.cause, e.text])])
	assert_eq(mine[0].cause, "bad_unit", "the first muster fails on its own account")
	for i in range(1, mine.size()):
		assert_eq(mine[i].cause, "muster_refused", "order %d falls because of it: %s" % [i, mine[i].text])
		assert_false(String(mine[i].reason).is_empty(), "and says why")
		assert_eq(mine[i].phase, "orders")
	assert_true(String(mine[1].reason).contains("earlier muster"), "a later muster says an earlier one was refused: %s" % mine[1].reason)
	assert_true(String(mine[2].reason).contains("earlier muster"), mine[2].reason)
	# An order that names an army says which, as the map does (never an id).
	var name_first := RulerRules._cap(TurnReportText.army_name(r.new_state, first_new, CROWN))
	var name_second := RulerRules._cap(TurnReportText.army_name(r.new_state, second_new, CROWN))
	assert_true(String(mine[3].reason).contains(name_first), "the move of the first planned army names it: %s" % mine[3].reason)
	assert_true(String(mine[4].reason).contains(name_second), mine[4].reason)
	assert_true(String(mine[5].reason).contains(name_second), "the cast: %s" % mine[5].reason)
	assert_true(String(mine[6].reason).contains(name_second), "the tied sally: %s" % mine[6].reason)
	assert_true(String(mine[7].reason).contains(name_first), "the sally by it: %s" % mine[7].reason)
	assert_true(String(mine[8].reason).contains("The Crown's 1st"), "the source's own move: %s" % mine[8].reason)
	assert_true(String(mine[9].reason).contains(RulerRules._cap(TurnReportText.army_name(r.new_state, other.id, CROWN))), "an army the refused merge named: %s" % mine[9].reason)
	for id in mine.map(func(e): return String(e.reason)):
		for raw in ["kingdom-", "_"]:
			assert_false(String(id).contains(raw), "no raw id '%s' in: %s" % [raw, id])
	# The armies that never formed can't be found, and nothing moved, mustered or was cast.
	for id in [first_new, second_new]:
		assert_eq(r.new_state.find_army(id), null, "%s never formed" % id)
	var crown_events := func(type: String) -> Array: return Kit.events(r, type).filter(func(e): return Array(e.factions).has(CROWN))
	for type in ["army_split", "units_transferred", "armies_merged", "army_disbanded", "army_moved", "ritual_cast"]:
		assert_eq(crown_events.call(type), [], "the Crown has no %s event" % type)
	for id in ["kingdom-1", other.id, pair.id, fresh.id]:
		assert_eq(r.new_state.find_army(id).location, "crownkeep", "%s stayed" % id)
	assert_eq(Kit.types(r.new_state.find_army(pair.id)), ["crossbowmen"], "the refused merge moved no one")
	assert_eq(int(r.new_state.next_army_ids[CROWN]), counter_before, "no army id was handed out")
	# The recruit resolved: a spearman joined the first army there.
	assert_eq(r.new_state.find_army("kingdom-1").units.size(), fighters_before + 1, "the recruit still joined the Crown's 1st")
	assert_eq(crown_events.call("recruited").size(), 1, "and said so")
	# The beasts' own split and the march of the army it formed went ahead: a cascade belongs to one faction.
	assert_eq(rejected.filter(func(e): return Array(e.factions).has(CLANS)), [], "nothing of the beasts' was rejected")
	assert_eq(Kit.events(r, "army_split").filter(func(e): return Array(e.factions).has(CLANS)).size(), 1)
	assert_eq(r.new_state.find_army("beasts-2").location, "ebonpeak")


## Only what relied on the refused muster falls: a muster before it that applied stands, and the army it formed can still be marched.
func test_musters_before_the_refused_one_stand_and_their_armies_can_move() -> void:
	var s := Kit.game()
	var other := Kit.army(s, CROWN, "crownkeep", ["spearmen"])
	var coming: Array = s.peek_army_ids(CROWN, 2)
	var orders := {CROWN: [
		MusterOrder.transfer("kingdom-1", "", [0]),  # applies, forming coming[0]
		MusterOrder.transfer(other.id, "", [7]),  # refused at resolution (coming[1] was to be its new army)
		MoveOrder.new(String(coming[0]), "westwatch"),  # the army the first formed: fine
		MoveOrder.new(String(coming[1]), "highcrag"),  # the one that never formed: rejected
		MoveOrder.new(other.id, "rivermarch"),  # the refused muster's source: rejected
	]}
	var r := Kit.resolve(s, orders)
	assert_eq(Kit.events(r, "army_split").size(), 1, "the first muster applied")
	assert_eq(r.new_state.find_army(String(coming[0])).location, "westwatch", "and the army it formed marched")
	assert_eq(r.new_state.find_army(String(coming[1])), null, "the second never formed")
	var rejected := Kit.events(r, "order_rejected")
	assert_eq(rejected.map(func(e): return e.cause), ["bad_unit", "muster_refused", "muster_refused"], "the muster, the move of the army that never formed, the move of its source: %s" % [rejected.map(func(e): return e.text)])
	assert_eq(r.new_state.find_army(other.id).location, "crownkeep")
	assert_eq(int(r.new_state.next_army_ids[CROWN]), int(s.next_army_ids[CROWN]) + 1, "one id was handed out: the one that formed")


func test_a_ruler_army_muster_is_rejected_in_the_pass() -> void:
	var s := Kit.game("rulers")
	var ruler := RulerRules.ruler_army(s, CROWN)
	var r := Kit.resolve(s, {CROWN: [MusterOrder.transfer(ruler.id, "", [0])]})
	var rejected := Kit.events(r, "order_rejected")
	assert_eq(rejected.size(), 1)
	assert_eq(rejected[0].cause, "ruler_army")
	assert_eq(rejected[0].codex, "muster")
	assert_eq(rejected[0].armies, [ruler.id])


func test_a_malformed_muster_is_rejected_when_it_reaches_the_resolver() -> void:
	var bad := MusterOrder.new()
	bad.malformed = "it has no units"
	var r := Kit.resolve(Kit.game(), {CROWN: [bad]})
	var rejected := Kit.events(r, "order_rejected")
	assert_eq(rejected.size(), 1)
	assert_eq(rejected[0].cause, "malformed_muster")


# --- battles after a split -----------------------------------------------------------------------------------------

func test_the_half_that_stays_is_the_holder_and_the_half_that_marches_is_not() -> void:
	var s := Kit.game()
	s.find_province("crownkeep").owner = CROWN
	var raider := Kit.army(s, CLANS, "westwatch", ["tuskers", "tuskers", "tuskers", "war_bear"])
	var orders := {CROWN: [MusterOrder.transfer("kingdom-1", "", [0, 1]), MoveOrder.new("kingdom-2", "highcrag")],
		CLANS: [MoveOrder.new(raider.id, "crownkeep")]}
	var r := Kit.resolve(s, orders)
	var battles := Kit.events(r, "battle")
	assert_eq(battles.size(), 1, "one battle, at Crownkeep")
	assert_eq(battles[0].provinces, ["crownkeep"])
	assert_eq(battles[0].numbers.defender, CROWN, "the half that stayed holds Crownkeep")
	assert_true(battles[0].armies.has("kingdom-1") and not battles[0].armies.has("kingdom-2"), "and the half that marched is not in it")
	assert_eq(r.new_state.find_army("kingdom-2").location, "highcrag", "the half that marched went to Highcrag")


func test_without_a_fragment_staying_nobody_holds() -> void:
	var s := Kit.game()
	s.find_province("crownkeep").owner = CROWN
	var raider := Kit.army(s, CLANS, "westwatch", ["tuskers"])
	var orders := {CROWN: [MusterOrder.transfer("kingdom-1", "", [0, 1]), MoveOrder.new("kingdom-2", "highcrag"), MoveOrder.new("kingdom-1", "rivermarch")],
		CLANS: [MoveOrder.new(raider.id, "crownkeep")]}
	var r := Kit.resolve(s, orders)
	assert_eq(Kit.events(r, "battle"), [], "both fragments marched away: the raider walks into an empty keep")
	assert_eq(r.new_state.find_army("kingdom-2").location, "highcrag")
	assert_eq(r.new_state.find_army("kingdom-1").location, "rivermarch")


func test_fragments_take_different_roads_as_armies_of_their_own() -> void:
	var s := Kit.game()
	var orders := {CROWN: [MusterOrder.transfer("kingdom-1", "", [0]), MusterOrder.transfer("kingdom-1", "", [0]),
		MoveOrder.new("kingdom-2", "westwatch"), MoveOrder.new("kingdom-3", "highcrag"), MoveOrder.new("kingdom-1", "rivermarch")]}
	var r := Kit.resolve(s, orders)
	var where := {}
	for id in ["kingdom-1", "kingdom-2", "kingdom-3"]:
		where[id] = r.new_state.find_army(id).location
	assert_eq(where, {"kingdom-1": "rivermarch", "kingdom-2": "westwatch", "kingdom-3": "highcrag"}, "three armies, three roads")
	assert_eq(Kit.events(r, "army_moved").size(), 3)


func test_a_border_swap_with_a_fragment() -> void:
	var s := Kit.game()
	s.find_province("crownkeep").owner = CROWN
	var raider := Kit.army(s, CLANS, "westwatch", ["tuskers", "tuskers", "tuskers", "tuskers", "war_bear"])
	var orders := {CROWN: [MusterOrder.transfer("kingdom-1", "", [0]), MoveOrder.new("kingdom-2", "westwatch")],
		CLANS: [MoveOrder.new(raider.id, "crownkeep")]}
	var r := Kit.resolve(s, orders)
	var border := Kit.events(r, "border_battle")
	assert_eq(border.size(), 1, "the fragment crossing to Westwatch meets the raider crossing to Crownkeep on the border")
	assert_true(border[0].armies.has("kingdom-2") and border[0].armies.has(raider.id))
	var fights := Kit.events(r, "battle")
	assert_eq(fights.size(), 1, "the winner then meets the half that stayed")
	assert_eq(fights[0].numbers.defender, CROWN, "which holds Crownkeep as the defender")
