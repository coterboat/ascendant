extends "res://tests/test_case.gd"
## CW-2 (#253, design/CANDLEWAKE.md §9): the Candlewake's micro-benchmarks (tools/balance/candlewake.gd) hold the gate. At flame 1
## on open ground every Candlewake unit type wins 20-80% of its battles against every Crown and Clans unit type at equal gold,
## and a mixed army 30-70% against each mixed army. The same seeded battles as the tool's report, fewer of them. The start
## armies, with their commanders, fight the others' as evenly as the Crown's and the Clans' fight each other (tests/test_balance.gd).

const Bench := preload("res://tools/balance/candlewake.gd")
const SEEDS := 40
const START_SEEDS := 200


func test_the_gate_holds_at_flame_1_on_open_ground() -> void:
	var all := Bench.rows(SEEDS, [1], false)
	var lines := Bench.misses(all).map(func(m): return "%s: %.1f%% (band %d-%d%%)" % [m.label, m.pct, m.band[0], m.band[1]])
	assert_eq(lines, [], "\n".join(lines))
	var pairs := 0
	for foe in Bench.FOES:
		var s := Bench.state_for(foe)
		pairs += s.find_faction(Bench.WAKE).unit_types.size() * s.find_faction(foe).unit_types.size()
	assert_eq(all.filter(func(r): return r.kind == "pair").size(), pairs, "every unit type against every unit type")
	assert_eq(all.filter(func(r): return r.kind == "mixed").size(), Bench.FOES.size(), "a mixed army against each foe's")


func test_a_pair_is_equal_gold() -> void:
	for foe in Bench.FOES:
		var s := Bench.state_for(foe)
		for w in s.find_faction(Bench.WAKE).unit_types:
			for t in s.find_faction(foe).unit_types:
				var n := Bench.equal_counts(s, foe, w.id, t.id, Bench.PAIR_GOLD)
				var mine: int = n[0].size() * TurnResolver.recruit_cost(s, Bench.WAKE, w.id)
				var theirs: int = n[1].size() * TurnResolver.recruit_cost(s, foe, t.id)
				for gold in [mine, theirs]:
					assert_true(gold >= Bench.PAIR_GOLD * 0.75 and gold <= Bench.PAIR_GOLD * 1.25, "%s vs %s: %d gold" % [w.id, t.id, gold])
				assert_true(absf(mine - theirs) <= maxf(TurnResolver.recruit_cost(s, Bench.WAKE, w.id), TurnResolver.recruit_cost(s, foe, t.id)),
					"%s vs %s: %d against %d gold" % [w.id, t.id, mine, theirs])


func test_the_flame_moves_the_odds() -> void:
	var s := Bench.state_for("kingdom")
	var n := Bench.equal_counts(s, "kingdom", "wickwardens", "spearmen", Bench.PAIR_GOLD)
	var cold := Bench.win_pct(s, "kingdom", n[0], n[1], 0, Bench.GROUNDS[0], SEEDS)
	var hot := Bench.win_pct(s, "kingdom", n[0], n[1], WickRules.cap(s, Bench.WAKE), Bench.GROUNDS[0], SEEDS)
	assert_true(hot > cold, "a hot wick wins more than a cold one: %.1f%% against %.1f%%" % [hot, cold])


func test_the_start_armies_fight_evenly() -> void:
	for foe in Bench.FOES:
		var s := Bench.state_for(foe)
		var mine := Bench.start_army(s, Bench.WAKE)
		assert_eq(mine.size(), FactionData.row(Bench.WAKE).start_army.size() + 1, "the start army and the Lamplighter")
		var pct := Bench.win_pct(s, foe, mine, Bench.start_army(s, foe), WickRules.start_flame(s, Bench.WAKE), Bench.GROUNDS[0], START_SEEDS)
		assert_true(pct >= Bench.START_BAND[0] and pct <= Bench.START_BAND[1], "the start armies against the %s's: %.1f%%" % [foe, pct])
