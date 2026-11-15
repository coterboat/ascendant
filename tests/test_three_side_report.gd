extends "res://tests/test_case.gd"
## #322 (QA): a three-sided battle's full report read as a two-sided one. Its result said "the enemy broke and fled", its Why
## named one break when two sides broke, and an army of a side the game state doesn't name came out as "an army of an unknown
## faction" (the Free Holds' garrison) or "the faction's 9th" (the Wild Host's bears). The launcher shows the report with no game
## state at all. Each side's break and each army's name now come from the battle's own sides.
## Pinned on the three-sided fixtures (tests/three_side_fixtures.gd, battles fought by the rules), against their own logs:
##   * the result names each side that left the field and the round it left, in the order they left, and never "the enemy";
##   * the Why names every side that broke;
##   * every army is named for its own side, with the game state or without it; the Free Holds' is their garrison;
## and, on sides built in the test, the endings the fixtures don't reach (a side destroyed, a mutual break, the round cap).

const T := preload("res://tests/three_side_fixtures.gd")


## The battle's sides that left the field, in the order they left, from its log:
## [{"name", "left": "broke" or "was destroyed", "round"}]. The winner is not among them.
func _exits(b: Dictionary) -> Array:
	var winner := -1
	for side in b.log.sides:
		if String(side.faction) == String(b.report.winner):
			winner = int(side.index)
	var out := []
	for ev in b.log.events:
		if String(ev.t) in ["rout", "destroyed"] and int(ev.side) != winner:
			out.append({"name": String(b.log.sides[int(ev.side)].name), "left": "broke" if String(ev.t) == "rout" else "was destroyed",
				"round": int(ev.n)})
	return out


func _result(b: Dictionary) -> String:
	for line in b.report.lines:
		if String(line).begins_with("Result: "):
			return String(line)
	return ""


func test_the_result_names_each_side_that_left_and_when() -> void:
	var seen := 0
	for name in T.NAMES:
		var b: Dictionary = T.battle(name)
		if b.is_empty():
			continue
		seen += 1
		var result := _result(b)
		var exits := _exits(b)
		assert_eq(exits.size(), b.log.sides.size() - 1, "%s: every side but the winner left the field" % name)
		assert_false(result.contains("the enemy"), "%s: no single enemy: \"%s\"" % [name, result])
		var at := -1
		for e in exits:
			var said := "%s %s in round %d" % [e.name, e.left, e.round]
			var i := result.find(said)
			assert_true(i > at, "%s: the result says \"%s\", in the order they left: \"%s\"" % [name, said, result])
			at = i
	assert_eq(seen, T.NAMES.size(), "every fixture fought its battle")


func test_the_why_names_every_side_that_broke() -> void:
	for name in T.NAMES:
		var b: Dictionary = T.battle(name)
		if b.is_empty():
			continue
		var broke := _exits(b).filter(func(e): return e.left == "broke")
		assert_false(broke.is_empty(), "%s: a side broke" % name)
		for e in broke:
			assert_true(String(b.report.why).contains("%s broke after losing" % e.name), "%s: the Why names %s's break: \"%s\"" % [name, e.name, b.report.why])


func test_every_army_is_named_for_its_own_side_with_or_without_a_state() -> void:
	var seen := 0
	for name in T.NAMES:
		var b: Dictionary = T.battle(name)
		if b.is_empty():
			continue
		for side in b.log.sides:
			for state in [null, b.state]:
				var where := "%s, %s, %s" % [name, side.name, "with the game state" if state != null else "with no game state"]
				var armies := TurnReportText.log_armies(b.log, String(side.faction), state)
				assert_false(armies.is_empty(), "%s: its armies" % where)
				for a in armies:
					seen += 1
					var title := String(a.title)
					assert_false(title.contains("unknown faction") or title.begins_with("the faction's"), "%s: \"%s\"" % [where, title])
	assert_true(seen > 0, "armies were named")
	var holds: Dictionary = T.battle("holds")
	var garrison := TurnReportText.log_armies(holds.log, IndependentData.FACTION_ID, null)
	assert_eq(garrison.size(), 1, "the garrison")
	assert_true(String(garrison[0].title).begins_with("the %s garrison (" % RulerRules._possessive(IndependentData.FACTION_NAME)),
		"with no game state, the Free Holds' army is their garrison: \"%s\"" % String(garrison[0].title))


## The endings the fixtures don't reach, on sides built here (AutoBattleResolver._how_sides_left): sides that left in the same round
## (by their order in the battle) and a side destroyed, a mutual break (the sides still there all broke in the last round, and the
## winner kept the field), and the round cap with a side gone and with none (the two-sided wording, `how`, stays).
func test_every_ending_names_the_sides_that_left() -> void:
	var clans := {"name": "Thornmane Clans", "routed": true, "destroyed": false, "out_round": 5}
	var holds := {"name": "Free Holds", "routed": false, "destroyed": true, "out_round": 2}
	var crown := {"name": "Aurel Crown", "routed": false, "destroyed": false, "out_round": 0}
	var host := {"name": "Wild Host", "routed": true, "destroyed": false, "out_round": 2}
	var how := "the two-sided wording"
	assert_eq(AutoBattleResolver._how_sides_left([clans, holds, crown, host], 2, "rout", how),
		"%s was destroyed in round %d, %s broke in round %d and %s broke in round %d" % [holds.name, holds.out_round, host.name, host.out_round,
		clans.name, clans.out_round], "four sides: in the order they left, the same round by their order in the battle")
	var kept := crown.duplicate()
	kept.out_round = clans.out_round  # a mutual end: the winner broke in the last round too, and kept the field
	assert_eq(AutoBattleResolver._how_sides_left([clans, holds, kept], 2, "mutual", how),
		"%s was destroyed in round %d and %s broke in round %d; %s broke in round %d too, but had more of its strength left" % [holds.name,
		holds.out_round, clans.name, clans.out_round, kept.name, kept.out_round], "a mutual break")
	var stayed := clans.duplicate()
	stayed.routed = false
	stayed.out_round = 0
	assert_eq(AutoBattleResolver._how_sides_left([stayed, holds, crown], 2, "round_cap", how),
		"%s was destroyed in round %d; then %s" % [holds.name, holds.out_round, how], "the round cap, a side gone")
	var all_there := holds.duplicate()
	all_there.destroyed = false
	all_there.out_round = 0
	assert_eq(AutoBattleResolver._how_sides_left([stayed, all_there, crown], 2, "round_cap", how), how, "the round cap, every side still there")
