extends "res://tests/test_case.gd"
## M3c S-1b (#99) acceptance, tests/test_siege_battles.gd: every crossing of orders at a fort (design/M3C_SIEGES.md
## §3.9's 18 rows) through SiegeRules.next_battle and the battle loop, the walls and cover parts (§4.1), open and
## breach battles with no defender and no terrain, no fighterless side and no engine in a battle, and determinism.
## Outcomes are steered with StubBattleResolver (the stronger side wins and loses nothing); the parts are read
## from the real AutoBattleResolver's log. Expected numbers come from FortData.

const F := preload("res://tests/siege_fixtures.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const WILDS := "wilds"


## Turn 6 is being ordered. The Crown holds Stonegate (a keep, on hills) with kingdom-1 and kingdom-2 inside, and
## a relief, kingdom-3, at Westwatch. `besieged`: the Clans' beasts-4 has besieged it since turn 4; otherwise
## beasts-4 waits at Blackwood. `walls` -1 keeps them full. `strong` names the armies that get a big force.
func _state(besieged: bool, walls: int = -1, strong: Array = [], extra: Array = []) -> GameState:
	var specs := [
		["kingdom-1", CROWN, "stonegate", F.units("spearmen", 6) if strong.has("kingdom-1") else ["spearmen"]],
		["kingdom-2", CROWN, "stonegate", F.units("knights", 6) if strong.has("kingdom-2") else ["crossbowmen"]],
		["kingdom-3", CROWN, "westwatch", F.units("knights", 6) if strong.has("kingdom-3") else ["spearmen"]],
		["beasts-4", CLANS, "stonegate" if besieged else "blackwood",
			F.units("war_bear", 6) if strong.has("beasts-4") else F.units("tuskers", 2), 1],
	]
	specs.append_array(extra)
	var s := F.state(specs, {"stonegate": CROWN, "westwatch": CROWN, "blackwood": CLANS})
	s.current_turn = 5
	var p := s.find_province("stonegate")
	if besieged:
		p.siege_since = 4
	if walls >= 0:
		p.walls = walls
	return s


## Adds a third faction, the Wilds, with its capital at Deepwood (row 12 needs a second enemy).
func _with_wilds(s: GameState, specs: Array) -> GameState:
	var d := s.find_faction(CLANS).to_dict()
	d["id"] = WILDS
	d["name"] = "Wild Host"
	d["capital"] = "deepwood"
	var f := Faction.from_dict(d)
	f.gold = 45
	s.factions.append(f)
	var deep := s.find_province("deepwood")
	deep.is_capital = true
	deep.owner = WILDS
	s.find_province("thornvale").owner = WILDS
	for spec in specs:
		var a := Army.new()
		a.id = spec[0]
		a.owner = WILDS
		a.location = spec[1]
		for i in int(spec[2]):
			a.units.append(Unit.new(f.unit_types[2], WILDS))  # War Bears
		s.armies.append(a)
	return s


func _battles(events: Array) -> Array:
	return events.filter(func(e): return e.type == "battle")


## Checks the battles fought at Stonegate against `expected`: [[kind, why, defender, from_inside, armies], ...].
func _check_battles(row: String, events: Array, expected: Array) -> void:
	var battles := _battles(events).filter(func(e): return e.provinces == ["stonegate"])
	assert_eq(battles.size(), expected.size(), "row %s: %d battles" % [row, expected.size()])
	for i in mini(battles.size(), expected.size()):
		var b: Dictionary = battles[i]
		var want: Array = expected[i]
		var siege: Dictionary = b.numbers.get("siege", {})
		assert_eq(String(siege.get("kind", "")), want[0], "row %s, battle %d: kind" % [row, i + 1])
		assert_eq(String(siege.get("why", "")), want[1], "row %s, battle %d: why" % [row, i + 1])
		assert_eq(String(b.numbers.defender), want[2], "row %s, battle %d: defender" % [row, i + 1])
		assert_eq(Array(siege.get("from_inside", [])), want[3], "row %s, battle %d: from inside" % [row, i + 1])
		var armies: Array = Array(b.armies).duplicate()
		armies.sort()
		var wanted: Array = Array(want[4]).duplicate()
		wanted.sort()
		assert_eq(armies, wanted, "row %s, battle %d: who fought" % [row, i + 1])
		var fids := []
		for id in wanted:
			var fid := String(id).split("-")[0]
			if not fids.has(fid):
				fids.append(fid)
		fids.sort()
		assert_eq(Array(b.factions), fids, "row %s, battle %d: the sides" % [row, i + 1])
		assert_eq(int(siege.get("garrison", -2)), fids.find(CROWN), "row %s, battle %d: the garrison's side index" % [row, i + 1])
		assert_eq(String(siege.get("fort", "")), "keep", "row %s: the fort" % row)


func _resolve(s: GameState, orders: Dictionary) -> Dictionary:
	var r := F.resolve(s, orders)
	assert_true(r.new_state != null, ", ".join(r.get("errors", [])))
	return r


func _types(events: Array) -> Array:
	return events.map(func(e): return e.type)


func test_every_row_of_the_crossing_table() -> void:
	var storm := SiegeOrder.storm("stonegate")
	var relief := MoveOrder.new("kingdom-3", "stonegate")
	var arrive := MoveOrder.new("beasts-4", "stonegate")
	var r: Dictionary
	# 1. besiegers wait, garrison holds: no battle, the siege goes on.
	r = _resolve(_state(true), {})
	_check_battles("1", r.events, [])
	assert_true(_types(r.events).has("walls_damaged"))
	# 2. besiegers storm, garrison holds: a storm, the garrison defends with walls and terrain.
	r = _resolve(_state(true), {CLANS: [storm]})
	_check_battles("2", r.events, [["storm", "storm", CROWN, ["kingdom-1", "kingdom-2"], ["kingdom-1", "kingdom-2", "beasts-4"]]])
	# 3. besiegers wait, a garrison army sallies: open, the sallying army against every besieger; the other stays in.
	r = _resolve(_state(true), {CROWN: [SiegeOrder.sally("kingdom-1")]})
	_check_battles("3", r.events, [["open", "sally", "", ["kingdom-1"], ["kingdom-1", "beasts-4"]]])
	# 4. besiegers storm, a garrison army sallies: at the gate first; the sally loses, so the storm follows on the
	#    armies that stayed inside. With a winning sally, no storm.
	r = _resolve(_state(true, -1, ["beasts-4"]), {CLANS: [storm], CROWN: [SiegeOrder.sally("kingdom-1")]})
	_check_battles("4", r.events, [["open", "gate", "", ["kingdom-1"], ["kingdom-1", "beasts-4"]],
		["storm", "storm", CROWN, ["kingdom-2"], ["kingdom-2", "beasts-4"]]])
	r = _resolve(_state(true, -1, ["kingdom-1"]), {CLANS: [storm], CROWN: [SiegeOrder.sally("kingdom-1")]})
	_check_battles("4 (the sally wins)", r.events, [["open", "gate", "", ["kingdom-1"], ["kingdom-1", "beasts-4"]]])
	# 5. a relief arrives, garrison holds, besiegers wait: open, relief against besiegers; the garrison stays in.
	r = _resolve(_state(true), {CROWN: [relief]})
	_check_battles("5", r.events, [["open", "relief", "", [], ["kingdom-3", "beasts-4"]]])
	# 6. a relief arrives and a garrison army sallies with it: one open battle together.
	r = _resolve(_state(true), {CROWN: [relief, SiegeOrder.sally("kingdom-1", "kingdom-3")]})
	_check_battles("6", r.events, [["open", "relief_sally", "", ["kingdom-1"], ["kingdom-1", "kingdom-3", "beasts-4"]]])
	# 7. a relief arrives, besiegers storm, garrison holds: open (relief against besiegers); it loses, so the storm
	#    follows, and the besiegers fight twice.
	r = _resolve(_state(true, -1, ["beasts-4"]), {CROWN: [relief], CLANS: [storm]})
	_check_battles("7", r.events, [["open", "relief", "", [], ["kingdom-3", "beasts-4"]],
		["storm", "storm", CROWN, ["kingdom-1", "kingdom-2"], ["kingdom-1", "kingdom-2", "beasts-4"]]])
	# 8. relief, sally and storm: one open battle (relief and sally), then the storm on those who stayed inside.
	r = _resolve(_state(true, -1, ["beasts-4"]), {CROWN: [relief, SiegeOrder.sally("kingdom-1", "kingdom-3")], CLANS: [storm]})
	_check_battles("8", r.events, [["open", "relief_sally", "", ["kingdom-1"], ["kingdom-1", "kingdom-3", "beasts-4"]],
		["storm", "storm", CROWN, ["kingdom-2"], ["kingdom-2", "beasts-4"]]])
	# 9. besiegers leave, the garrison sallies: no battle, the siege lines were empty, the siege is lifted.
	r = _resolve(_state(true), {CLANS: [MoveOrder.new("beasts-4", "blackwood")], CROWN: [SiegeOrder.sally("kingdom-1")]})
	_check_battles("9", r.events, [])
	assert_true(_types(r.events).has("sally_found_nothing"), "row 9 says the siege lines were empty")
	assert_true(_types(r.events).has("siege_lifted"))
	# 10. besiegers leave, a relief arrives: no battle, the siege is lifted, the relief goes in.
	r = _resolve(_state(true), {CLANS: [MoveOrder.new("beasts-4", "blackwood")], CROWN: [relief]})
	_check_battles("10", r.events, [])
	assert_true(_types(r.events).has("siege_lifted"))
	assert_eq(r.new_state.find_army("kingdom-3").location, "stonegate")
	# 11. the garrison leaves, besiegers wait: no battle, the fort is empty and the besiegers take it.
	r = _resolve(_state(true), {CROWN: [MoveOrder.new("kingdom-1", "westwatch"), MoveOrder.new("kingdom-2", "westwatch")]})
	_check_battles("11", r.events, [])
	assert_eq(r.new_state.find_province("stonegate").owner, CLANS)
	# 12. a second enemy faction arrives at a besieged fort: one open battle between everyone outside (and the
	#     sallying armies as a third side); the survivor besieges, and storms only if it ordered it and won.
	var rivals := _with_wilds(_state(true), [["wilds-9", "thornvale", 6]])
	r = _resolve(rivals, {WILDS: [MoveOrder.new("wilds-9", "stonegate"), storm]})
	_check_battles("12", r.events, [["open", "rivals", "", [], ["beasts-4", "wilds-9"]],
		["storm", "storm", CROWN, ["kingdom-1", "kingdom-2"], ["kingdom-1", "kingdom-2", "wilds-9"]]])
	rivals = _with_wilds(_state(true), [["wilds-9", "thornvale", 6]])
	r = _resolve(rivals, {WILDS: [MoveOrder.new("wilds-9", "stonegate")], CROWN: [SiegeOrder.sally("kingdom-1")]})
	_check_battles("12 (with a sally)", r.events, [["open", "rivals", "", ["kingdom-1"], ["kingdom-1", "beasts-4", "wilds-9"]]])
	assert_true(SiegeRules.is_besieged(r.new_state, "stonegate"), "the survivor besieges")
	# 13. an enemy arrives with a storm order where there was no siege: a storm at the walls as they stand.
	r = _resolve(_state(false), {CLANS: [arrive, storm]})
	_check_battles("13", r.events, [["storm", "storm", CROWN, ["kingdom-1", "kingdom-2"], ["kingdom-1", "kingdom-2", "beasts-4"]]])
	# 14. an enemy arrives without a storm order: no battle, a siege starts.
	r = _resolve(_state(false), {CLANS: [arrive]})
	_check_battles("14", r.events, [])
	assert_true(_types(r.events).has("siege_started"))
	# 15. the owner's army and an enemy arrive together: at the empty fort the winner holds it; at a garrisoned
	#     fort with no siege the arrivals meet in the open and the garrison stays inside.
	var empty := _state(false)
	empty.armies = empty.armies.filter(func(a): return not ["kingdom-1", "kingdom-2"].has(a.id))
	r = _resolve(empty, {CLANS: [arrive], CROWN: [relief]})
	_check_battles("15 (empty)", r.events, [["open", "empty", "", [], ["kingdom-3", "beasts-4"]]])
	r = _resolve(_state(false), {CLANS: [arrive], CROWN: [relief]})
	_check_battles("15 (garrisoned)", r.events, [["open", "relief", "", [], ["kingdom-3", "beasts-4"]]])
	# 16. walls at 0 at the start of the turn, garrison and enemy there: the battle through the breach, on its own,
	#     in the open; a relief arriving fights beside the garrison, without cover.
	r = _resolve(_state(true, 0), {})
	_check_battles("16", r.events, [["breach", "breach", "", ["kingdom-1", "kingdom-2"], ["kingdom-1", "kingdom-2", "beasts-4"]]])
	r = _resolve(_state(true, 0), {CROWN: [relief]})
	_check_battles("16 (with a relief)", r.events, [["breach", "breach", "", ["kingdom-1", "kingdom-2"],
		["kingdom-1", "kingdom-2", "kingdom-3", "beasts-4"]]])
	# 17. an enemy arrives at a fort whose walls are 0 and which has a garrison: the same battle at once, no siege.
	r = _resolve(_state(false, 0), {CLANS: [arrive]})
	_check_battles("17", r.events, [["breach", "breach", "", ["kingdom-1", "kingdom-2"], ["kingdom-1", "kingdom-2", "beasts-4"]]])
	assert_false(_types(r.events).has("siege_started"))
	# 18. a sally tied to a relief that dies on the way (a border battle): the sally is called off and the garrison
	#     stays inside; the besiegers wait, so there is no battle at Stonegate.
	var ambush := _state(true, -1, [], [["beasts-5", CLANS, "stonegate", F.units("war_bear", 6)]])
	r = _resolve(ambush, {CROWN: [relief, SiegeOrder.sally("kingdom-1", "kingdom-3")], CLANS: [MoveOrder.new("beasts-5", "westwatch")]})
	assert_eq(r.events.filter(func(e): return e.type == "border_battle").size(), 1, "the relief met the Clans on the border")
	assert_eq(r.new_state.find_army("kingdom-3"), null, "and was destroyed")
	_check_battles("18", r.events, [])
	var off: Array = r.events.filter(func(e): return e.type == "sally_called_off")
	assert_eq(off.size(), 1)
	assert_eq(off[0].phase, "battles")
	assert_eq(off[0].codex, "sally")
	assert_true(String(off[0].text).contains("The garrison of Stonegate stayed inside: the relief from Westwatch never arrived."), off[0].text)
	assert_eq(r.new_state.find_army("kingdom-1").location, "stonegate", "kingdom-1 is still inside")


func test_storms_are_called_off_with_a_line_and_at_no_cost() -> void:
	# The stormers died on the march: a border battle with a Crown army coming the other way.
	var s := _state(false, -1, [], [["kingdom-5", CROWN, "blackwood", F.units("knights", 6)]])
	s.find_province("blackwood").owner = CLANS
	s.find_army("kingdom-5").location = "stonegate"
	var r := _resolve(s, {CLANS: [MoveOrder.new("beasts-4", "stonegate"), SiegeOrder.storm("stonegate")],
		CROWN: [MoveOrder.new("kingdom-5", "blackwood")]})
	var off: Array = r.events.filter(func(e): return e.type == "storm_called_off")
	assert_eq(off.size(), 1, "the storm is called off")
	assert_eq(off[0].codex, "storm")
	assert_true(String(off[0].text).contains("called off"), off[0].text)
	_check_battles("called off", r.events, [])
	# The garrison is gone: nobody to storm.
	r = _resolve(_state(true), {CLANS: [SiegeOrder.storm("stonegate")],
		CROWN: [MoveOrder.new("kingdom-1", "westwatch"), MoveOrder.new("kingdom-2", "westwatch")]})
	assert_eq(r.events.filter(func(e): return e.type == "storm_called_off").size(), 1)
	_check_battles("garrison gone", r.events, [])


## Every attack on a fighter in the log, with that fighter's army id.
func _attacks(log: Dictionary) -> Array:
	var army_of := {}
	for f in log.fighters:
		army_of[int(f.id)] = String(f.army)
	var out := []
	for e in log.events:
		if String(e.t) == "attack":
			out.append({"army": army_of[int(e.to)], "parts": e.defense.parts, "attack_parts": e.attack.parts})
	return out


func _logs_at(events: Array, pid: String) -> Array:
	return _battles(events).filter(func(e): return e.provinces == [pid]).map(func(e): return e.numbers.log)


func test_the_walls_part_at_every_wall_strength_and_only_in_storms() -> void:
	var forts := [["westwatch", 1, "stonegate"], ["stonegate", 2, "blackwood"], ["crownkeep", 3, "westwatch"]]
	var checked := 0
	for fort in forts:
		var level: int = fort[1]
		for w in range(1, SiegeRules.walls_max(level) + 1):
			var owners := {fort[2]: CLANS}
			if fort[0] != "crownkeep":
				owners[fort[0]] = CROWN
			var s := F.state([
				["kingdom-1", CROWN, fort[0], F.units("spearmen", 2)],
				["beasts-2", CLANS, fort[2], F.units("war_bear", 3)],
			], owners)
			F.set_fort(s, fort[0], level, w)
			var r := F.resolve(s, {CLANS: [MoveOrder.new("beasts-2", fort[0]), SiegeOrder.storm(fort[0])]}, true)
			var logs := _logs_at(r.events, fort[0])
			assert_eq(logs.size(), 1, "%s at %d walls: one storm" % [fort[0], w])
			var expected := FortData.WALLS_DEFENSE_PER_STEP * ceili(float(w) / FortData.WALL_STEP)
			var b: Dictionary = _battles(r.events)[0]
			assert_eq(int(b.numbers.siege.walls_defense), expected)
			assert_eq(int(b.numbers.siege.walls), w)
			assert_eq(int(b.numbers.siege.cover_defense), 0, "no cover in a storm")
			for a in _attacks(logs[0]):
				if a.army == "kingdom-1":
					assert_eq(int(a.parts.get("walls", 0)), expected, "%s, walls %d: +%d for the garrison" % [fort[0], w, expected])
				else:
					assert_false(a.parts.has("walls"), "the stormers get no walls")
				assert_false(a.parts.has("cover"), "no cover in a storm")
				assert_false(a.parts.has("fort"), "the walls replace the old fort bonus")
			checked += 1
	assert_eq(checked, 3 + 6 + 9, "every wall strength of every level")


func test_cover_only_on_fighters_from_inside_in_sallies_and_breaches_and_no_terrain_in_the_open() -> void:
	var cases := [
		# [what, besieged, walls, orders, from inside (cover), not from inside]
		["a sally", true, -1, {CROWN: [SiegeOrder.sally("kingdom-1")]}, ["kingdom-1"], ["beasts-4"]],
		["a relief", true, -1, {CROWN: [MoveOrder.new("kingdom-3", "stonegate")]}, [], ["kingdom-3", "beasts-4"]],
		["a relief and a sally", true, -1, {CROWN: [MoveOrder.new("kingdom-3", "stonegate"), SiegeOrder.sally("kingdom-1", "kingdom-3")]},
			["kingdom-1"], ["kingdom-3", "beasts-4"]],
		["the breach", true, 0, {}, ["kingdom-1", "kingdom-2"], ["beasts-4"]],
	]
	for c in cases:
		var r := F.resolve(_state(c[1], c[2]), c[3], true)
		var logs := _logs_at(r.events, "stonegate")
		assert_eq(logs.size(), 1, c[0])
		var b: Dictionary = _battles(r.events).filter(func(e): return e.provinces == ["stonegate"])[0]
		assert_eq(String(b.numbers.defender), "", "%s: nobody defends" % c[0])
		assert_eq(int(b.numbers.siege.walls_defense), 0, "%s: no walls" % c[0])
		assert_eq(int(b.numbers.siege.cover_defense), FortData.COVER_DEFENSE if not Array(c[4]).is_empty() else 0, c[0])
		var covered := 0
		for a in _attacks(logs[0]):
			assert_false(a.parts.has("walls"), "%s: no walls part" % c[0])
			assert_false(a.parts.has("terrain") or a.attack_parts.has("terrain"), "%s: nobody gets the hills" % c[0])
			assert_false(a.parts.has("fort"), "%s: no fort part" % c[0])
			if Array(c[4]).has(a.army):
				assert_eq(int(a.parts.get("cover", 0)), FortData.COVER_DEFENSE, "%s: %s fights from inside with cover" % [c[0], a.army])
				covered += 1
			else:
				assert_true(Array(c[5]).has(a.army), "%s: %s was in the battle" % [c[0], a.army])
				assert_false(a.parts.has("cover"), "%s: %s gets no cover" % [c[0], a.army])
		assert_eq(covered > 0, not Array(c[4]).is_empty(), "%s: the fighters from inside were attacked with their cover" % c[0])
	# A storm has a defender, and the garrison gets its terrain on top of the walls.
	var r := F.resolve(_state(true), {CLANS: [SiegeOrder.storm("stonegate")]}, true)
	var b: Dictionary = _battles(r.events)[0]
	assert_eq(String(b.numbers.defender), CROWN)
	var terrain := false
	for a in _attacks(b.numbers.log):
		if a.army.begins_with(CROWN):
			terrain = terrain or a.parts.has("terrain")
	assert_true(terrain, "the stormed garrison stands on its hills")
	# Without sieges the old fort bonus is still there.
	var m1 := GameState.new(3)
	m1.armies.clear()
	m1.armies.append(F.army(m1, ["kingdom-1", CROWN, "stonegate", F.units("spearmen", 2)]))
	m1.armies.append(F.army(m1, ["beasts-2", CLANS, "blackwood", F.units("war_bear", 3)]))
	m1.find_province("stonegate").owner = CROWN
	r = TurnResolver.resolve(m1, {CLANS: [MoveOrder.new("beasts-2", "stonegate")]}, 7)
	b = _battles(r.events)[0]
	assert_false(b.numbers.has("siege"), "no siege block without sieges")
	var fort := false
	for a in _attacks(b.numbers.log):
		if a.army == "kingdom-1":
			fort = fort or int(a.parts.get("fort", 0)) == AutoBattleResolver.FORT_DEFENSE
	assert_true(fort, "M1's +2 fort part")


func test_no_side_is_without_a_fighter_and_engines_never_fight() -> void:
	var s := _state(true, -1, [], [["beasts-5", CLANS, "stonegate", F.units("tuskers", 5), FortData.ARMY_ENGINES_MAX]])
	var r := F.resolve(s, {CLANS: [SiegeOrder.storm("stonegate")], CROWN: [SiegeOrder.sally("kingdom-1")]}, true)
	var battles := _battles(r.events)
	assert_true(battles.size() >= 1)
	for b in battles:
		var report: Dictionary = b.numbers.report
		for side in report.sides:
			assert_true(int(side.fighters_start) > 0, "%s fights with a fighter" % side.faction)
		var units := 0
		for id in b.armies:
			var a := s.find_army(String(id))
			units += a.units.size() + (1 if a.commander else 0) + (1 if a.ruler else 0)
		var fighters := 0
		for side in report.sides:
			fighters += int(side.fighters_start)
		assert_eq(fighters, units, "every fighter is a unit, commander or ruler: engines never fight")
		assert_eq(b.numbers.log.fighters.size(), units, "and the log has no engine in it")
	# A plan never puts a side without a fighter into a battle.
	for row in [{}, {CLANS: [SiegeOrder.storm("stonegate")]}, {CROWN: [SiegeOrder.sally("kingdom-1")]}]:
		var plan := SiegeRules.next_battle(_state(true), "stonegate", {}, _orders_of(_state(true), row), [])
		for fid in plan.get("sides", {}):
			var n := 0
			for a in plan.sides[fid]:
				n += a.units.size() + (1 if a.commander else 0) + (1 if a.ruler else 0)
			assert_true(n > 0, "a side with a fighter")


## The siege orders `orders` would record (as TurnResolver._collect_orders does), for calling next_battle directly.
func _orders_of(s: GameState, orders: Dictionary) -> Dictionary:
	var out := {"storms": {}, "sallies": {}}
	for fid in orders:
		for o in orders[fid]:
			if o is SiegeOrder and o.is_storm():
				out.storms[o.province] = {fid: true}
			elif o is SiegeOrder:
				out.sallies[o.army_id] = {"faction": fid, "with": o.with_army, "from": ""}
	return out


func test_the_same_seed_gives_the_same_result() -> void:
	var orders := {CROWN: [MoveOrder.new("kingdom-3", "stonegate"), SiegeOrder.sally("kingdom-1", "kingdom-3")],
		CLANS: [SiegeOrder.storm("stonegate")]}
	var a := TurnResolver.resolve(_state(true, -1, ["beasts-4"]), orders, 77, AutoBattleResolver.new())
	var b := TurnResolver.resolve(_state(true, -1, ["beasts-4"]), orders, 77, AutoBattleResolver.new())
	assert_eq(JSON.stringify(a.new_state.to_dict()), JSON.stringify(b.new_state.to_dict()))
	assert_eq(JSON.stringify(a.events), JSON.stringify(b.events))
	assert_true(_battles(a.events).size() >= 1)
	# Battle ids count battles in the order they are fought, so two battles at one fort take consecutive indices.
	var ids := _battles(a.events).map(func(e): return String(e.numbers.log.id))
	for i in ids.size():
		assert_eq(ids[i], "t6b%d" % i, "battle %d of the turn" % i)
