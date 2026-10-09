extends "res://tests/test_case.gd"
## M3c S-1a (#98) acceptance, tests/test_sieges_model.gd: starting a siege, siege damage, the cut-off and its income
## on both sides, the breach, lifting and falling, empty forts, and forecast equals result (design/M3C_SIEGES.md §3).
## Every expected number is derived from FortData.

const F := preload("res://tests/siege_fixtures.gd")
const CROWN := "kingdom"
const CLANS := "beasts"


## Siege damage from FortData's numbers, written out once here so the rules can be checked against them.
func _expected_damage(troops: int, engines: int) -> int:
	var s := FortData.SIEGE
	var counted := mini(mini(engines, int(s.engines_max)), troops / int(s.troops_per_engine))
	return mini(int(s.max), int(s.camp) + mini(int(s.troops_max), troops / int(s.per_troops)) + counted * int(s.engine))


func test_arriving_at_a_garrisoned_fort_starts_a_siege_with_no_battle() -> void:
	var s := F.state([
		["kingdom-1", CROWN, "stonegate", F.units("spearmen", 3)],
		["beasts-2", CLANS, "blackwood", F.units("tuskers", 4)],
	], {"stonegate": CROWN, "blackwood": CLANS})
	var r := F.resolve(s, {CLANS: [MoveOrder.new("beasts-2", "stonegate")]}, true)
	var ns: GameState = r.new_state
	assert_eq(F.events_of(r.events, "battle").size(), 0, "no battle")
	assert_true(ns.find_army("kingdom-1") != null and ns.find_army("beasts-2") != null, "both armies are still there")
	assert_eq(ns.find_army("beasts-2").location, "stonegate")
	var p := ns.find_province("stonegate")
	assert_eq(p.owner, CROWN, "the province stays its owner's while the siege lasts")
	assert_eq(p.siege_since, 1, "the siege began on turn 1")
	assert_eq(p.walls, SiegeRules.walls_max(2) - _expected_damage(4, 0), "the siege camp already drops the walls")
	var started := F.events_of(r.events, "siege_started")
	assert_eq(started.size(), 1)
	assert_eq(started[0].phase, "sieges")
	assert_eq(started[0].codex, "siege")
	assert_true(String(started[0].text).begins_with("The Thornmane Clans laid siege to Stonegate with 4 troops."), started[0].text)
	assert_true(String(started[0].text).contains("From next turn (2) Stonegate is cut off"), started[0].text)
	assert_eq(TurnResolver.phases(ns).find("sieges"), TurnResolver.phases(ns).find("battles") + 1, "sieges come right after battles")
	# Next turn the siege goes on, with no orders from anyone, and still no battle.
	r = F.resolve(ns, {}, true)
	assert_eq(F.events_of(r.events, "battle").size(), 0)
	var damaged := F.events_of(r.events, "walls_damaged")
	assert_eq(damaged.size(), 1)
	assert_true(String(damaged[0].text).begins_with("The siege of Stonegate, turn 2: the walls dropped from"), damaged[0].text)
	assert_eq(r.new_state.find_province("stonegate").siege_since, 1)


func test_damage_equals_siege_damage_for_constructed_armies() -> void:
	# [troops in the first army, engines it carries, troops in a second army, engines it carries]
	var rows := [
		[1, 0, 0, 0], [9, 0, 0, 0],                # a raid
		[10, 0, 0, 0], [19, 0, 0, 0],              # 10 troops
		[20, 0, 0, 0], [25, 0, 0, 0],              # 20 troops
		[7, 3, 0, 0], [12, 3, 0, 0], [5, 1, 0, 0], # engines count only one for every 5 troops
		[20, 1, 0, 0], [20, 2, 0, 0], [20, 3, 0, 0],
		[22, 3, 3, 1],                             # the cap: four engines, at most engines_max count
	]
	for row in rows:
		var troops: int = row[0] + row[2]
		var engines: int = row[1] + row[3]
		var expected := _expected_damage(troops, engines)
		assert_eq(int(SiegeRules.siege_damage(troops, engines).total), expected, "%d troops and %d engines" % [troops, engines])
		var specs := [
			["kingdom-1", CROWN, "crownkeep", ["spearmen"]],
			["beasts-2", CLANS, "westwatch", F.units("tuskers", row[0]), row[1]],
		]
		var orders := [MoveOrder.new("beasts-2", "crownkeep")]
		if row[2] > 0:
			specs.append(["beasts-3", CLANS, "westwatch", F.units("fangthrowers", row[2]), row[3]])
			orders.append(MoveOrder.new("beasts-3", "crownkeep"))
		var s := F.state(specs, {"westwatch": CLANS})
		var r := F.resolve(s, {CLANS: orders})
		assert_eq(r.new_state.find_province("crownkeep").walls, SiegeRules.walls_max(3) - expected,
			"the walls drop by the siege damage (%d troops, %d engines)" % [troops, engines])
		var ev: Dictionary = F.events_of(r.events, "siege_started")[0]
		assert_eq(int(ev.numbers.damage), expected)
		var sum := 0
		for part in ev.numbers.damage_parts:
			sum += int(part.value)
		assert_eq(sum, expected, "the parts add up to the siege damage")
	# Never more than the cap; the most a siege can do is the cap or, when the parts can't reach it, all of them.
	var sd := FortData.SIEGE
	var most := int(sd.camp) + int(sd.troops_max) + int(sd.engines_max) * int(sd.engine)
	var biggest := SiegeRules.siege_damage(1000, int(sd.engines_max) + 1)
	assert_eq(int(biggest.total), mini(most, int(sd.max)), "never more than the cap")
	assert_eq(bool(biggest.capped), most > int(sd.max), "capped only when the parts pass the cap")


func test_the_cut_off_starts_on_the_second_turn_with_half_the_garrison_and_moves_the_income() -> void:
	var s := F.state([
		["kingdom-1", CROWN, "stonegate", F.units("spearmen", 4)],
		["beasts-2", CLANS, "blackwood", F.units("tuskers", 2)],
	], {"stonegate": CROWN, "blackwood": CLANS})
	var base := s.find_province("stonegate").income
	assert_eq(2, ceili(4 / 2.0), "two troops are exactly half of the garrison's four")
	var r := F.resolve(s, {CLANS: [MoveOrder.new("beasts-2", "stonegate")]})
	var ns: GameState = r.new_state
	# Turn 1, the siege's first: nothing is cut off yet.
	var crown_income: Dictionary = F.events_of(r.events, "income").filter(func(e): return e.factions[0] == CROWN)[0]
	assert_eq(int(crown_income.numbers.by_province.stonegate), base, "turn 1: Stonegate still pays its owner")
	# Turn 2: cut off. Its base income goes to the besiegers, and the owner gets nothing from it.
	assert_true(SiegeRules.is_cut_off(ns, "stonegate"), "cut off from the siege's second turn")
	var refused := OrderBook.check_order(ns, CROWN, RecruitOrder.new("spearmen", "stonegate"), [])
	assert_eq(String(refused.get("code", "")), "fort_cut_off")
	var owner_inc := TurnResolver.income_of(ns, CROWN)
	var besieger_inc := TurnResolver.income_of(ns, CLANS)
	assert_eq(int(owner_inc.by_province.stonegate), 0, "the owner gets nothing from it")
	assert_eq(int(besieger_inc.by_province.stonegate), base, "the besiegers get its base income")
	for inc in [owner_inc, besieger_inc]:
		var sum := int(inc.base)
		for key in inc.modifiers:
			sum += int(inc.modifiers[key])
		assert_eq(sum, int(inc.total), "base plus every modifier is the total")
	for fid in [CROWN, CLANS]:
		var b := Breakdown.income(ns, fid)
		assert_eq(Breakdown.sum_of_lines(b), int(b.total), "%s: the income breakdown adds up" % fid)
		assert_eq(int(b.total), int(TurnResolver.income_of(ns, fid).total))
		var g := Breakdown.gold(ns, fid)
		assert_eq(Breakdown.sum_of_lines(g), int(g.total), "%s: the gold breakdown adds up" % fid)
	var pi := Breakdown.province_income(ns, "stonegate")
	assert_eq(int(pi.total), 0)
	assert_eq(Breakdown.sum_of_lines(pi), 0, "base %d minus cut off %d" % [base, base])
	var gold := {CROWN: ns.find_faction(CROWN).gold, CLANS: ns.find_faction(CLANS).gold}
	var expected := {CROWN: int(owner_inc.total), CLANS: int(besieger_inc.total)}
	r = F.resolve(ns, {})
	for fid in [CROWN, CLANS]:
		assert_eq(r.new_state.find_faction(fid).gold, int(gold[fid]) + int(expected[fid]), "%s's gold forecast is what it gets" % fid)
	var texts := {}
	for e in F.events_of(r.events, "income"):
		texts[e.factions[0]] = String(e.text)
	assert_true(texts[CROWN].contains("Stonegate paid nothing: it is cut off, and its %d gold went to the Thornmane Clans." % base), texts[CROWN])
	assert_true(texts[CLANS].contains("and %d from besieged Stonegate" % base), texts[CLANS])
	# Pickets: one troop is fewer than half the garrison's four, so nothing is ever cut off.
	var pickets := F.state([
		["kingdom-1", CROWN, "stonegate", F.units("spearmen", 4)],
		["beasts-2", CLANS, "blackwood", ["tuskers"]],
	], {"stonegate": CROWN, "blackwood": CLANS})
	var p1: GameState = F.resolve(pickets, {CLANS: [MoveOrder.new("beasts-2", "stonegate")]}).new_state
	var p2: GameState = F.resolve(p1, {}).new_state
	for st in [p1, p2]:
		assert_true(SiegeRules.is_besieged(st, "stonegate"))
		assert_false(SiegeRules.is_cut_off(st, "stonegate"), "pickets cut nothing off")
		assert_eq(int(TurnResolver.income_of(st, CROWN).by_province.stonegate), base)
	var cut := Breakdown.cut_off(p2, "stonegate")
	assert_true(String(cut.description).contains("only pickets"), cut.description)


func test_a_breach_at_zero_a_lift_when_the_besiegers_leave_and_a_fall_that_clears_the_siege() -> void:
	# The breach: twenty troops or more (with engines if FortData needs them) drop a palisade's walls in one turn.
	var force := F.force_to_breach(SiegeRules.walls_max(1), 1, 20)
	assert_false(force.is_empty(), "some force breaches a palisade in one turn")
	var big := F.state([
		["kingdom-1", CROWN, "westwatch", ["spearmen"]],
		["beasts-2", CLANS, "stonegate", F.units("tuskers", force[0]), force[1]],
	], {"westwatch": CROWN, "stonegate": CLANS})
	F.set_fort(big, "westwatch", 1)
	var r := F.resolve(big, {CLANS: [MoveOrder.new("beasts-2", "westwatch")]})
	assert_eq(r.new_state.find_province("westwatch").walls, 0)
	var breached := F.events_of(r.events, "walls_breached")
	assert_eq(breached.size(), 1)
	assert_eq(breached[0].codex, "breach")
	assert_true(String(breached[0].text).contains("The walls of Westwatch are down (breached)"), breached[0].text)
	# The battle comes on its own next turn, with no order.
	r = F.resolve(r.new_state, {})
	assert_eq(F.events_of(r.events, "battle").size(), 1, "the battle through the breach comes on its own")
	# The lift: the besiegers leave; the walls repair from that sieges phase on.
	var s := F.state([
		["kingdom-1", CROWN, "stonegate", F.units("spearmen", 2)],
		["beasts-2", CLANS, "blackwood", F.units("tuskers", 2)],
	], {"stonegate": CROWN, "blackwood": CLANS})
	var ns: GameState = F.resolve(s, {CLANS: [MoveOrder.new("beasts-2", "stonegate")]}).new_state
	var walls := ns.find_province("stonegate").walls
	r = F.resolve(ns, {CLANS: [MoveOrder.new("beasts-2", "blackwood")]})
	ns = r.new_state
	assert_eq(ns.find_province("stonegate").siege_since, 0, "the siege is lifted")
	assert_eq(F.events_of(r.events, "siege_lifted").size(), 1)
	assert_true(String(F.events_of(r.events, "siege_lifted")[0].text).contains("the besiegers left"))
	assert_eq(ns.find_province("stonegate").walls, mini(SiegeRules.walls_max(2), walls + SiegeRules.repair_amount(2)),
		"and the walls repair at once")
	# The fall: the garrison leaves, the besiegers stay; the fort falls and the next turn loads.
	ns = F.resolve(s, {CLANS: [MoveOrder.new("beasts-2", "stonegate")]}).new_state
	r = F.resolve(ns, {CROWN: [MoveOrder.new("kingdom-1", "westwatch")]})
	ns = r.new_state
	assert_true(ns != null, "the turn resolves")
	assert_eq(ns.find_province("stonegate").siege_since, 0, "the fall clears the siege")
	assert_eq(ns.find_province("stonegate").owner, CLANS, "and the capture phase hands the fort over")
	assert_eq(F.events_of(r.events, "siege_ended").size(), 1)
	var errors := []
	assert_true(ns.validate(errors), ", ".join(errors))
	var next := F.resolve(ns, {})
	assert_true(next.new_state != null, "the next turn loads: %s" % ", ".join(next.get("errors", [])))


func test_an_empty_fort_is_captured_with_its_level_and_walls() -> void:
	var s := F.state([
		["kingdom-1", CROWN, "crownkeep", ["spearmen"]],
		["beasts-2", CLANS, "blackwood", ["tuskers"]],
	], {"stonegate": CROWN, "blackwood": CLANS})
	F.set_fort(s, "stonegate", 2, 2)
	var r := F.resolve(s, {CLANS: [MoveOrder.new("beasts-2", "stonegate")]})
	var p: Province = r.new_state.find_province("stonegate")
	assert_eq(F.events_of(r.events, "battle").size(), 0)
	assert_eq(F.events_of(r.events, "siege_started").size(), 0, "nobody inside: no siege")
	assert_eq(p.owner, CLANS)
	assert_eq(p.fort_level, 2, "it keeps its level")
	assert_eq(p.walls, 2, "and its walls")
	var captured: Dictionary = F.events_of(r.events, "captured")[0]
	assert_true(String(captured.text).contains("It came with its keep (walls 2 of %d)" % SiegeRules.walls_max(2)), captured.text)
	assert_eq(int(captured.numbers.fort_level), 2)


func test_forecast_equals_result_for_the_breach_turn_and_the_cut_off() -> void:
	# [fort province, level, the besiegers' starting province]
	var forts := [["westwatch", 1, "stonegate"], ["stonegate", 2, "blackwood"], ["crownkeep", 3, "westwatch"]]
	# The rows of §3.3's table: [troops, engines]
	var rows := [[1, 0], [9, 0], [10, 0], [19, 0], [20, 0], [20, 1], [20, 2], [20, 3], [5, 1], [9, 1]]
	var checked := 0
	for fort in forts:
		for row in rows:
			var owners := {fort[2]: CLANS}
			if fort[0] != "crownkeep":
				owners[fort[0]] = CROWN
			var s := F.state([
				["kingdom-1", CROWN, fort[0], ["spearmen"]],
				["beasts-2", CLANS, fort[2], F.units("tuskers", row[0]), row[1]],
			], owners)
			F.set_fort(s, fort[0], fort[1])
			var move := MoveOrder.new("beasts-2", fort[0])
			var fc := Forecast.siege(s, CLANS, fort[0], [move])
			var what := "%s (level %d), %d troops and %d engines" % [fort[0], fort[1], row[0], row[1]]
			assert_true(fc.ok and fc.besieged and fc.starts, "%s: a siege starts: %s" % [what, fc.text])
			assert_eq(int(fc.damage.total), _expected_damage(row[0], row[1]), what)
			assert_eq(int(fc.cut_off_from), 2, "%s: cut off from the siege's second turn" % what)
			var breach := int(fc.breach_turn)
			var state: GameState = F.resolve(s, {CLANS: [move]}).new_state
			var turn := 1
			while turn < breach:
				assert_true(state.find_province(fort[0]).walls > 0, "%s: standing at the end of turn %d" % [what, turn])
				if turn == 1:
					var g := Forecast.siege(state, CROWN, fort[0])
					assert_eq(int(g.breach_turn), breach, "%s: the garrison's forecast agrees" % what)
				state = F.resolve(state, {}).new_state
				turn += 1
			assert_eq(state.find_province(fort[0]).walls, 0, "%s: breached at the end of turn %d, as forecast" % [what, breach])
			# The cut-off starts on the forecast turn.
			var at_two: GameState = F.resolve(s, {CLANS: [move]}).new_state
			assert_true(SiegeRules.is_cut_off(at_two, fort[0], int(fc.cut_off_from)), "%s: cut off on turn %d" % [what, fc.cut_off_from])
			assert_false(SiegeRules.is_cut_off(at_two, fort[0], int(fc.cut_off_from) - 1), "%s: not before" % what)
			checked += 1
	assert_eq(checked, forts.size() * rows.size(), "every level and every row")
