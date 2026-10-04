extends "res://tests/test_case.gd"
## M3c S-2 (#100) acceptance, tests/test_siege_log.gd: the battle event log and report at forts (design/M3C_SIEGES.md
## §4.4, §4.5). validate, verify_draws and cross_check pass on a storm, a sally, a relief, a gate battle and a breach
## battle; the siege block matches §3.9's last column; logs from games without sieges stay byte-identical to main's
## fixtures; recording on and off gives the same outcome. Battles are fought with the real AutoBattleResolver.

const F := preload("res://tests/siege_fixtures.gd")
const Scenarios := preload("res://tools/battle_log/scenarios.gd")
const CROWN := "kingdom"
const CLANS := "beasts"


## Turn 6 is being ordered. The Crown holds Stonegate (a keep, on hills) with kingdom-1 and kingdom-2 inside, a
## relief kingdom-3 at Westwatch; the Clans' beasts-4 (carrying a Wallbreakers) has besieged it since turn 4.
## `strong` armies get a big force; `walls` -1 keeps them full.
func _state(walls: int = -1, strong: Array = []) -> GameState:
	var s := F.state([
		["kingdom-1", CROWN, "stonegate", F.units("knights", 6) if strong.has("kingdom-1") else F.units("spearmen", 2)],
		["kingdom-2", CROWN, "stonegate", F.units("crossbowmen", 2) + ["knight_captain"]],
		["kingdom-3", CROWN, "westwatch", F.units("knights", 2)],
		["beasts-4", CLANS, "stonegate", F.units("war_bear", 5) if strong.has("beasts-4") else F.units("tuskers", 3) + ["warchief"], 1],
	], {"stonegate": CROWN, "westwatch": CROWN, "blackwood": CLANS})
	s.current_turn = 5
	s.find_province("stonegate").siege_since = 4
	if walls >= 0:
		s.find_province("stonegate").walls = walls
	return s


## [name, walls, strong armies, orders, expected battles: [[kind, why], ...]]
func _cases() -> Array:
	var storm := SiegeOrder.storm("stonegate")
	var relief := MoveOrder.new("kingdom-3", "stonegate")
	return [
		["a storm", -1, [], {CLANS: [storm]}, [["storm", "storm"]]],
		["a sally", -1, [], {CROWN: [SiegeOrder.sally("kingdom-1")]}, [["open", "sally"]]],
		["a relief", -1, [], {CROWN: [relief]}, [["open", "relief"]]],
		["a relief and a sally", -1, [], {CROWN: [relief, SiegeOrder.sally("kingdom-1", "kingdom-3")]}, [["open", "relief_sally"]]],
		["a gate battle, then the storm", -1, ["beasts-4"], {CLANS: [storm], CROWN: [SiegeOrder.sally("kingdom-1")]},
			[["open", "gate"], ["storm", "storm"]]],
		["the breach", 0, [], {}, [["breach", "breach"]]],
	]


func _battles_at(events: Array, pid: String) -> Array:
	return events.filter(func(e): return e.type == "battle" and e.provinces == [pid])


func test_every_check_passes_on_each_kind_of_battle_at_a_fort() -> void:
	for c in _cases():
		var r := F.resolve(_state(c[1], c[2]), c[3], true)
		var battles := _battles_at(r.events, "stonegate")
		var expected: Array = c[4]
		assert_eq(battles.size(), expected.size(), "%s: %d battles" % [c[0], expected.size()])
		for i in mini(battles.size(), expected.size()):
			var b: Dictionary = battles[i]
			var lg: Dictionary = b.numbers.log
			var report: Dictionary = b.numbers.report
			var what := "%s, battle %d" % [c[0], i + 1]
			assert_eq(BattleLog.validate(lg), [], "%s: validate" % what)
			assert_eq(BattleLog.verify_draws(lg), [], "%s: verify_draws" % what)
			assert_eq(BattleLog.cross_check(lg, report), [], "%s: cross_check" % what)
			# §3.9's last column, and the same block in the log, the report and the event.
			assert_eq([String(lg.siege.kind), String(lg.siege.why)], expected[i], "%s: kind and why" % what)
			assert_eq(JSON.stringify(report.siege), JSON.stringify(lg.siege), "%s: the report carries the log's block" % what)
			assert_eq(JSON.stringify(b.numbers.siege), JSON.stringify(lg.siege), "%s: and so does the event" % what)
			assert_eq(String(lg.siege.fort), "keep")
			assert_eq(int(lg.siege.walls_max), SiegeRules.walls_max(2))
			assert_eq(int(lg.siege.turn_of_siege), 6 - 4 + 1, "%s: the siege's third turn" % what)
			assert_true(bool(lg.fort), "%s: the board still sees a fort" % what)
			# The JSON round trip is exact with the block in it.
			var back := BattleLog.from_json(BattleLog.to_json(lg))
			assert_eq(back.errors, [], what)
			assert_eq(JSON.stringify(back.log), JSON.stringify(lg), "%s: the round trip" % what)


func test_the_report_names_the_kind_and_the_why_counts_the_walls() -> void:
	var r := F.resolve(_state(), {CLANS: [SiegeOrder.storm("stonegate")]}, true)
	var b: Dictionary = _battles_at(r.events, "stonegate")[0]
	var report: Dictionary = b.numbers.report
	assert_true(String(report.lines[0]).begins_with("The Thornmane Clans stormed the walls of Stonegate (6 of 6: +4 defense) on the third turn of the siege."),
		report.lines[0])
	assert_true(String(report.lines[0]).contains("Aurel Crown (defending the walls)"), report.lines[0])
	assert_true(String(b.text).begins_with("The Thornmane Clans stormed the walls of Stonegate"), b.text)
	var walls: Array = report.all_factors.filter(func(f): return f.id == "walls")
	assert_eq(walls.size(), 1, "the walls are measured as a factor")
	assert_eq(String(walls[0].faction), CROWN)
	assert_true(String(walls[0].text).contains("the walls of Stonegate (6 of 6)"), walls[0].text)
	assert_eq(String(walls[0].get("codex", "")), "battle_walls")
	assert_eq(BattleExplain.factor_entry("walls"), "battle_walls")
	# A sally's cover is a factor too, and the hover names both parts in words.
	r = F.resolve(_state(), {CROWN: [SiegeOrder.sally("kingdom-1")]}, true)
	b = _battles_at(r.events, "stonegate")[0]
	assert_true(String(b.numbers.report.lines[0]).begins_with("At Stonegate, the Aurel Crown's garrison sallied out against the Thornmane Clans' siege lines."),
		b.numbers.report.lines[0])
	assert_eq(b.numbers.report.all_factors.filter(func(f): return f.id == "cover").size(), 1, "the cover is measured")
	var lg: Dictionary = b.numbers.log
	assert_eq(BattleExplain.part_name(lg, "cover"), "cover of the walls")
	var storm_log: Dictionary = _battles_at(F.resolve(_state(), {CLANS: [SiegeOrder.storm("stonegate")]}, true).events, "stonegate")[0].numbers.log
	assert_eq(BattleExplain.part_name(storm_log, "walls"), "walls (6 of 6)")
	assert_false(BattleExplain._part_note(storm_log, "walls").is_empty())
	# A won storm's aftermath says the walls were taken, and engines lost with their army are named.
	r = F.resolve(_state(-1, ["beasts-4"]), {CLANS: [SiegeOrder.storm("stonegate")]}, true)
	b = _battles_at(r.events, "stonegate")[0]
	assert_eq(String(b.numbers.winner), CLANS)
	assert_true(String(b.numbers.report.aftermath).contains("The walls of Stonegate were taken. The Thornmane Clans hold the keep (6 of 6 walls)."),
		b.numbers.report.aftermath)
	r = F.resolve(_state(-1, ["kingdom-1"]), {CROWN: [SiegeOrder.sally("kingdom-1")]}, true)
	b = _battles_at(r.events, "stonegate")[0]
	assert_eq(String(b.numbers.winner), CROWN)
	assert_true(String(b.numbers.report.aftermath).contains("Its Wallbreakers was lost with it."), b.numbers.report.aftermath)


func test_logs_from_games_without_sieges_are_byte_identical_to_mains_fixtures() -> void:
	var checked := 0
	for name in Scenarios.NAMES:
		var path := "%s/%s.json" % [Scenarios.FIXTURE_DIR, name]
		if not FileAccess.file_exists(path):
			continue
		var fx = JSON.parse_string(FileAccess.get_file_as_string(path))
		var r := Scenarios.run(name, int(fx.seed))
		assert_eq(r.errors, [], name)
		var stored: Dictionary = BattleLog.from_json(JSON.stringify(fx.log, "", false)).log
		assert_eq(BattleLog.to_json(r.log), BattleLog.to_json(stored), "%s: the log is byte-identical to main's fixture" % name)
		assert_false(r.log.has("siege"), "%s: no siege block without sieges" % name)
		assert_false(r.report.has("siege"))
		checked += 1
	assert_true(checked >= 10, "the stored fixtures were checked (%d)" % checked)


func test_recording_on_and_off_gives_the_same_outcome() -> void:
	for c in _cases():
		var s := _state(c[1], c[2])
		var siege_orders := {"storms": {}, "sallies": {}}
		var moved := {}
		for fid in c[3]:
			for o in c[3][fid]:
				if o is SiegeOrder and o.is_storm():
					siege_orders.storms["stonegate"] = {fid: true}
				elif o is SiegeOrder:
					siege_orders.sallies[o.army_id] = {"faction": fid, "with": o.with_army, "from": ""}
				elif o is MoveOrder:
					s.find_army(o.army_id).location = o.to
					moved[o.army_id] = true
		var plan := SiegeRules.next_battle(s, "stonegate", moved, siege_orders, [])
		assert_false(plan.is_empty(), c[0])
		var fids: Array = plan.sides.keys()
		fids.sort()
		var sides := fids.map(func(fid): return {"faction": fid, "armies": plan.sides[fid]})
		var ctx := {"kind": "province", "defender": plan.defender, "province": s.find_province("stonegate"),
			"province_ids": ["stonegate"], "state": s, "siege": plan.siege}
		for sd in [3, 11, 29]:
			var off := AutoBattleResolver.fight(sides, ctx, SeededRNG.new(sd), false)
			var on := AutoBattleResolver.fight(sides, ctx, SeededRNG.new(sd), true)
			assert_eq(on.result.winner, off.result.winner, "%s, seed %d: the same winner" % [c[0], sd])
			assert_eq(JSON.stringify(on.result.report), JSON.stringify(off.result.report), "%s, seed %d: the same report" % [c[0], sd])
			assert_true(on.has("log") and not off.has("log"), "only the recorded fight has a log")


func test_regenerate_rebuilds_a_siege_battle_from_the_game_record() -> void:
	var session := GameSession.new(_state(), [CROWN, CLANS], 17, AutoBattleResolver.new())
	assert_eq(session.setup_errors(), [])
	for seat in 2:
		if session.phase() == GameSession.Phase.HANDOFF:
			session.acknowledge_handoff()
		if session.current_player() == CLANS:
			assert_eq(session.queue_storm("stonegate"), "")
		session.end_turn()
	var battles := session.battle_events()
	assert_eq(battles.size(), 1, "the storm was fought")
	var again := BattleLog.regenerate(JSON.parse_string(JSON.stringify(session.record())), 1, 0)
	assert_eq(again.errors, [])
	assert_eq(BattleLog.to_json(again.log), BattleLog.to_json(battles[0].numbers.log), "the record rebuilds the storm's log byte for byte")
	assert_eq(String(again.log.siege.kind), "storm")
	assert_eq(BattleLog.cross_check(again.log, again.report), [])
