extends "res://tests/test_case.gd"
## CW-11 (#262) tooling, tests/test_cw11_bands.gd: the Candlewake matrix's cells (tools/autoplay/candlewake_matrix.gd) and its W
## bands judged at their edges, every edge read from the matrix's own constants; and WickLog (tools/autoplay/wick_log.gd) on a
## real Crown–Candlewake turn.

const CM := preload("res://tools/autoplay/candlewake_matrix.gd")
const WickLog := preload("res://tools/autoplay/wick_log.gd")
const CROWN := "kingdom"
const WAKE := "candlewake"
const ALL := {"magic": true, "sieges": true, "independents": true, "fog": true}


func test_the_plan_crosses_every_preset_of_each_pair_in_both_seat_orders() -> void:
	var cells := CM.plan(1.0, 1)
	var want := 0
	for pair in CM.PAIRS:
		want += RulerRules.presets_for(pair[0]).size() * RulerRules.presets_for(pair[1]).size() * 2
		var key := "%s|%s" % pair
		var mine := cells.filter(func(c): return c.pair == key)
		assert_eq(mine.size(), RulerRules.presets_for(pair[0]).size() * RulerRules.presets_for(pair[1]).size() * 2, "%s: every preset pairing, both orders" % key)
		assert_eq(GameState.seating_problems(mine[0].seats, ALL), [], "%s seats with every system on" % key)
	assert_eq(cells.size(), want)
	var ids := {}
	for c in cells:
		assert_false(ids.has(c.id), "cell ids are unique: %s" % c.id)
		ids[c.id] = true
		assert_eq(int(c.games), CM.CELL_GAMES)


## A decisive result of the pair Crown–Candlewake won by `winner` in `turns`, with a WickLog entry `wick`.
func _r(winner: String, turns: int, wick: Dictionary = {}, branch: String = "", recruits: Dictionary = {}) -> Dictionary:
	return {"pair": "%s|%s" % [CROWN, WAKE], "finished": true, "draw": false, "winner": winner, "turns": turns,
		"wick": {WAKE: wick}, "paths": {WAKE: {"branch": branch}}, "recruits": {WAKE: recruits}}


func _status(rows: Array, band: String) -> String:
	for row in rows:
		if row.band == band and str(row.pair) == "%s|%s" % [CROWN, WAKE]:
			return str(row.status)
	return "absent"


func test_w1_and_w5_judge_medians_at_their_edges() -> void:
	var lo := float(CM.W1_BAND[0])
	assert_eq(CM.w1([_r(CROWN, 12, {"battle_flames": [floori(lo), ceili(lo), ceili(lo)]})]).status, "pass", "a median at %d" % ceili(lo))
	assert_eq(CM.w1([_r(CROWN, 12, {"battle_flames": [0, 0, 1]})]).status, "miss" if lo > 0.0 else "pass")
	var games := []
	for t in [int(CM.W5_BAND[0]), int(CM.W5_BAND[1]), int(CM.W5_BAND[1])]:
		games.append(_r(WAKE, t))
	assert_eq(CM.w5(games).status, "pass")
	for i in 3:
		games.append(_r(WAKE, int(CM.W5_BAND[1]) + 5))
	assert_eq(CM.w5(games).status, "miss", "the median moves past the band")


func test_w2_counts_guttering_games_and_the_longest_stay_at_the_cap() -> void:
	var n := 10
	var gutter := ceili(CM.W2_GUTTER[0] * n)
	var games := []
	for i in n:
		games.append(_r(CROWN, 12, {"guttered": 1 if i < gutter else 0, "army_turns": {"candlewake-1": [CM.MIN_ARMY_TURNS, 0]}}))
	assert_eq(CM.w2(games).status, "pass", "%d of %d games guttered" % [gutter, n])
	games[0].wick[WAKE].army_turns["candlewake-2"] = [CM.MIN_ARMY_TURNS, CM.MIN_ARMY_TURNS]
	assert_eq(CM.w2(games).status, "miss", "an army always at its cap")
	games[0].wick[WAKE].army_turns["candlewake-2"] = [CM.MIN_ARMY_TURNS - 1, CM.MIN_ARMY_TURNS - 1]
	assert_eq(CM.w2(games).status, "pass", "an army seen fewer than MIN_ARMY_TURNS turns is not judged")


func test_w3_and_w6_are_shares_of_the_force_and_the_red_wake_has_its_own_band() -> void:
	var force := 100
	var harvest := roundi(CM.W3_BAND[0] * force)
	var risen := roundi(CM.W6_BAND[0] * force)
	var recruits := {"wickwardens": force - harvest - risen, "lamplighter": 5}  # the commander is not the force
	var g := _r(WAKE, 12, {"harvest": harvest, "risen": risen}, "golden_wake", recruits)
	assert_eq(CM.w3([g]).status, "pass", "Harvest %d of %d" % [harvest, force])
	assert_eq(CM.w6([g]).status, "pass", "the Risen %d of %d" % [risen, force])
	var red := _r(WAKE, 12, {"harvest": harvest, "risen": risen}, CM.RED_WAKE, recruits)
	assert_eq(CM.w3([red]).status, "miss" if harvest < roundi(CM.W3_RED_BAND[0] * force) else "pass", "the Red Wake's band is higher")


func test_w4_c3_and_p1c() -> void:
	var line := {"wake_line_at": {CM.W4_TURN: CM.W4_LINES}, "wake_cost": 1, "income": 100}
	assert_eq(CM.w4([_r(WAKE, 14, line)]).status, "pass")
	line.wake_cost = ceili(CM.W4_COST_MAX * 100.0) + 1
	assert_eq(CM.w4([_r(WAKE, 14, line)]).status, "miss", "the Wake costs too much")
	var games := [_r(CROWN, 12, {}, "golden_wake"), _r(WAKE, 12, {}, "golden_wake"), _r(CROWN, 12, {}, CM.RED_WAKE), _r(WAKE, 12, {}, CM.RED_WAKE)]
	assert_eq(CM.c3(games, "%s|%s" % [CROWN, WAKE]).status, "pass", "even")
	assert_eq(CM.p1c(games).status, "pass", "each side wins half")
	var rows := CM.judge(games)
	for band in ["C3", "W1", "W2", "W3", "W6", "W4", "W5", "P1c"]:
		assert_ne(_status(rows, band), "absent", "judge reports %s for the Candlewake pair" % band)
	assert_true(rows.any(func(r): return r.band == "C3" and r.pair == "kingdom|beasts"), "and C3 for the control pair")
	assert_true(CM.table(rows).contains("| C3 |"))


func test_wick_log_records_a_real_turn() -> void:
	var errors := []
	var start := GameState.create(5, [CROWN, WAKE], {"rulers": true}, {}, errors)
	assert_true(start != null, "a Crown–Candlewake game seats: %s" % [errors])
	if start == null:
		return
	var session := GameSession.new(start, [CROWN, WAKE], 5, AutoBattleResolver.new())
	var before := GameState.from_dict(session.state().to_dict())
	assert_eq(session.end_turn(), "")
	assert_eq(session.begin_turn(), "")
	assert_eq(session.end_turn(), "")
	var log := WickLog.new_log()
	WickLog.record_turn(log, 1, before, session.state(), session.turn_report().get("events", []))
	assert_true(log.has(WAKE), "the Candlewake has an entry")
	assert_false(log.has(CROWN), "the Crown keeps no flame")
	var side: Dictionary = log[WAKE]
	var armies := session.state().armies.filter(func(a): return WickRules.carries_flame(a))
	assert_eq(side.army_turns.size(), armies.size(), "every army with a flame is counted")
	assert_eq(int(side.income), int(TurnResolver.income_of(session.state(), WAKE).total), "its income")
