extends "res://tests/test_case.gd"
## M2-8 (#36): the build balance check (design/M2_RULER.md §8.2). The matrix plan and how its bands are
## judged (tools/autoplay/matrix.gd), the simulator's new report data (explicit builds, ruler deaths and
## successions, sacrifices, the replay check), and fast, small-sample checks that the tuned numbers keep:
## Royal Armories and Iron Discipline inside #41's battle bands, and keep and spend both winning games
## of a short fixed-seed autoplay batch.
## The full check is `autoplay.gd -- --matrix --jobs 8`; its report is in the PR.

const Simulator := preload("res://tools/autoplay/simulator.gd")
const Matrix := preload("res://tools/autoplay/matrix.gd")
const Balance := preload("res://tools/balance/balance.gd")


# --- the matrix plan --------------------------------------------------------------------------------

func test_the_matrix_plans_band_b_and_a2() -> void:
	var cells := Matrix.plan(1.0, 1)
	var ids := {}
	for c in cells:
		assert_false(ids.has(c.id), "cell ids are unique: %s" % c.id)
		ids[c.id] = true
	var b := cells.filter(func(c): return c.band == "B")
	assert_eq(b.size(), 18, "9 Crown x Clans pairings, each in both seat orders")
	var pairings := {}
	for c in b:
		assert_eq(int(c.games), Matrix.PAIR_GAMES / 2, "half of a pairing's games per seat order")
		pairings[c.pairing] = int(pairings.get(c.pairing, 0)) + int(c.games)
		assert_eq(RulerRules.preset_data(str(c.builds[0])).faction, c.seats[0], "seat 1 plays one of its own presets")
		assert_eq(RulerRules.preset_data(str(c.builds[1])).faction, c.seats[1], "seat 2 plays one of its own presets")
	assert_eq(pairings.size(), 9, "every preset pairing")
	for p in pairings:
		assert_eq(pairings[p], Matrix.PAIR_GAMES, "%s: %d games" % [p, Matrix.PAIR_GAMES])
	# A2: the Regent keeping 10 and spending 10, and the Fang keeping 10, are explicit builds; the Fang
	# spending 10 is exactly a preset, so its band B games count and it is not played again.
	var a2 := Matrix.a2_builds()
	assert_eq(a2.size(), 2, "the Ever-Regent and the Ninth Fang")
	for entry in a2:
		var keep: String = entry.keep
		assert_eq(Simulator.parse_build(keep, entry.faction).get("mandates", ["?"]), [], "%s keeps all 10" % keep)
		var spend := Simulator.parse_build(str(entry.spend), entry.faction)
		assert_eq(RulerRules.kept_after(spend), 0, "%s spends all 10" % entry.spend)
		assert_eq(spend.ruler, entry.ruler, "the same ruler")
		for bid in [entry.keep, entry.spend]:
			var played := cells.filter(func(c): return c.band == "A2" and c.pairing == bid)
			if RulerRules.preset_data(str(bid)).is_empty():
				assert_eq(played.size(), 6, "%s plays all 3 opposing presets in both seat orders" % bid)
			else:
				assert_eq(played.size(), 0, "%s is a preset: band B covers it" % bid)
	# Work items cover every game exactly once, in chunks.
	var items := Matrix.work_items(cells)
	var total := 0
	for it in items:
		assert_true(int(it.count) >= 1 and int(it.count) <= Matrix.CHUNK, "a chunk of 1-%d games" % Matrix.CHUNK)
		total += int(it.count)
	var planned := 0
	for c in cells:
		planned += int(c.games)
	assert_eq(total, planned, "every planned game is in exactly one work item")
	# --scale shrinks every band.
	var small := Matrix.plan(0.1, 1).filter(func(c): return c.band == "B")
	assert_eq(int(small[0].games), 5, "a tenth of 50")


func test_builds_can_be_presets_or_explicit() -> void:
	var p := Simulator.parse_build("iron_crown", "kingdom")
	assert_eq([p.id, p.preset, p.ruler], ["iron_crown", "iron_crown", "aurel_king"], "a preset id")
	var keep := Simulator.parse_build("ever_regent", "kingdom")
	assert_eq([keep.id, keep.preset, keep.ruler, keep.mandates], ["ever_regent", "", "ever_regent", []], "a ruler alone keeps 10")
	var spend := Simulator.parse_build("fang_chieftain+iron_discipline+blood_frenzy", "beasts")
	assert_eq(spend.mandates, ["iron_discipline", "blood_frenzy"], "a ruler and its mandates")
	assert_eq(Simulator.build_name("ever_regent"), "the Ever-Regent, keeps 10")
	assert_true(Simulator.build_name(spend.id).begins_with("the Ninth Fang: Iron Discipline, Blood Frenzy, keeps "), Simulator.build_name(spend.id))
	assert_eq(Simulator.build_name("iron_crown"), "Iron Crown")
	for bad in ["thornmane_avatar", "aurel_king+blood_frenzy", "nobody", "iron_crown"]:
		var r := Simulator.parse_build(bad, "beasts" if bad != "aurel_king+blood_frenzy" else "kingdom")
		if bad == "iron_crown":
			assert_true(r.has("error"), "a Crown preset is not a Clans build")
			continue
		assert_true(r.has("error") == (bad != "thornmane_avatar"), "%s: %s" % [bad, r])
	var over := Simulator.parse_build("aurel_king+royal_armories+heavy_tithes+muster_grounds", "kingdom")
	assert_true(over.has("error") and str(over.error).contains("power pool"), "over the pool: %s" % over)


# --- judging the bands ------------------------------------------------------------------------------

## A fake band B game: `a` (Crown preset) against `b` (Clans preset), won by `winner` ("kingdom",
## "beasts", "" for unfinished, "draw"), lasting `turns`, with these deaths and sacrifices.
func _game(a: String, b: String, winner: String, turns: int, deaths: Array = [], sacrifices: Array = [], replay := "") -> Dictionary:
	return {"band": "B", "cell": "B:%s:%s" % [a, b], "pairing": "%s|%s" % [a, b], "seed": 1, "builds": {"kingdom": a, "beasts": b},
		"finished": winner != "", "draw": winner == "draw", "winner": winner if winner != "draw" else "", "turns": turns,
		"ruler_log": {"deaths": deaths, "arrivals": [], "sacrifices": sacrifices, "mandates": {}}, "successors_due": 0,
		"violations": [], "errors": [], "script_errors": [], "replay": replay}


func _band(j: Dictionary, name: String) -> Dictionary:
	for b in j.bands:
		if b.band == name:
			return b
	return {}


func test_bands_are_judged_from_the_games() -> void:
	var games := []
	var crown: Array = RulerRules.presets_for("kingdom").map(func(p): return str(p.id))
	var clans: Array = RulerRules.presets_for("beasts").map(func(p): return str(p.id))
	# Every pairing split 5-5 over 12-turn games, one in two with a sacrifice and one in three with a
	# mid-game death; the first game of each is replayed.
	var n := 0
	for a in crown:
		for b in clans:
			for i in 10:
				var deaths := [{"faction": "kingdom", "turn": 6, "due": 8}] if n % 3 == 0 else []
				var sacs := [{"faction": "beasts", "mandate": "blood_frenzy", "turn": 9}] if n % 2 == 0 else []
				games.append(_game(a, b, "kingdom" if i < 5 else "beasts", 12, deaths, sacs, "identical" if i == 0 else ""))
				n += 1
	var j := Matrix.judge(games)
	for name in ["A", "B", "D", "E", "F", "H"]:
		assert_eq(_band(j, name).status, "pass", "%s: %s" % [name, _band(j, name).result])
	assert_eq(_band(j, "C").status, "report", "C is report only")
	# One preset winning 7 of 10 against another misses band B; H misses on one replay that differs.
	games[5].winner = "kingdom"
	games[6].winner = "kingdom"
	games[1].replay = "differs: the replayed final state is not the one the game reached"
	var j2 := Matrix.judge(games)
	assert_eq(_band(j2, "B").status, "miss", _band(j2, "B").result)
	assert_eq(_band(j2, "H").status, "miss", _band(j2, "H").result)
	assert_false(j2.h_ok, "the exit code follows band H")
	# A ruler lost in the turn its capital fell is not a mid-game death (band D), but is reported.
	var late := games.map(func(g):
		var c: Dictionary = g.duplicate(true)
		c.ruler_log.deaths = [{"faction": "beasts", "turn": 12, "due": 14}]
		return c)
	var d := _band(Matrix.judge(late), "D")
	assert_eq(d.status, "miss", d.result)
	assert_true(str(d.result).begins_with("0% (0 of 90; 100% counting"), d.result)
	# The head-to-head estimate is symmetric and even for equal records.
	var even := {"wins": 30, "losses": 30}
	assert_eq(Matrix.head_to_head(even, even), 0.5)
	var strong := {"wins": 45, "losses": 15}
	assert_true(absf(Matrix.head_to_head(strong, even) + Matrix.head_to_head(even, strong) - 1.0) < 0.000001, "symmetric")
	assert_true(Matrix.head_to_head(strong, even) > 0.7, "3:1 odds against 1:1")


## #131: AI-against-AI games are close to deterministic per pairing, so a band B share can snap to 0% or 100%.
## Each pairing counts its distinct endings (winner and length) and how many games share the most common one.
func test_pairings_count_distinct_endings() -> void:
	var a: String = RulerRules.presets_for("kingdom")[0].id
	var b: String = RulerRules.presets_for("beasts")[0].id
	var games := [_game(a, b, "beasts", 18), _game(a, b, "beasts", 18), _game(a, b, "beasts", 18), _game(a, b, "beasts", 21),
		_game(a, b, "kingdom", 18), _game(a, b, "", 60), _game(a, b, "draw", 30)]
	var prs := Matrix._pairings(games)
	assert_eq(prs.size(), 1)
	var pr: Dictionary = prs[0]
	assert_eq(pr.endings, 5, "Clans on 18, Clans on 21, Crown on 18, the unfinished game and the draw")
	assert_eq(pr.top_ending, 3, "three games end with the Clans winning on turn 18")
	assert_eq(pr.top_label, "%s, turn 18" % Simulator.faction_name("beasts"))
	var md := Matrix.to_markdown({"bands": [], "pairings": prs, "b_results": [], "a2_results": []})
	assert_true(md.contains("| distinct endings |"), "the pairings table has the column")
	assert_true(md.contains("| 5 (3 of 7: %s, turn 18) |" % Simulator.faction_name("beasts")), md)


# --- the simulator's report data ----------------------------------------------------------------------

func test_a_game_logs_rulers_and_replays_identically() -> void:
	var r := Simulator.play_game(3, ["kingdom", "beasts"], ["ai", "ai"], 60, Callable(),
		{"rulers": true, "builds": ["warrior_king", "fang_chieftain+iron_discipline+drilled_ranks"], "replay_check": true})
	assert_eq(r.errors, [], "no session errors")
	assert_eq(r.violations, [], "no invariant violations")
	assert_eq(r.builds, {"kingdom": "warrior_king", "beasts": "fang_chieftain+iron_discipline+drilled_ranks"}, "builds by id")
	assert_eq(r.replay, "identical", "the JSON record replays to the same final state")
	assert_eq(r.ruler_log.deaths.size(), int(r.ruler.deaths.get("kingdom", 0)) + int(r.ruler.deaths.get("beasts", 0)), "every death logged")
	assert_eq(r.ruler_log.arrivals.size(), int(r.ruler.arrivals.get("kingdom", 0)) + int(r.ruler.arrivals.get("beasts", 0)), "every arrival logged")
	assert_true(r.ruler_log.arrivals.size() >= int(r.successors_due), "every successor that fell due arrived")
	for d in r.ruler_log.deaths:
		assert_true(int(d.due) > int(d.turn), "a successor is due after the death")
	assert_eq(r.ruler_log.mandates.beasts.slice(0, 2), ["iron_discipline", "drilled_ranks"], "pre-game mandates first")
	var s := Simulator.summarize([r])
	var md := Simulator.to_markdown(s)
	for section in ["**Builds", "**Rulers:**", "**Deaths and successions:**", "**Mandate picks:**", "**Game length"]:
		assert_true(md.contains(section), "the report has %s" % section)


# --- fast band checks for the tuned numbers ----------------------------------------------------------

func test_the_mandate_fixes_keep_the_m1_battle_bands() -> void:
	# Royal Armories is +1 attack only (M2-8): Crown attack values are odd, so it changes the hit chance and
	# never a damage step, and holding a forest or fort stays an edge, not a sure thing (#41's rule). With
	# the old +1 defense, Spearmen holding a forest or fort against Tuskers won 100%.
	var ra := Balance.new_state_with({"kingdom": ["royal_armories"]})
	var start_crown := Balance.starting_army(ra, "kingdom")
	var start_clans := Balance.starting_army(ra, "beasts")
	var open: float = Balance.batch(ra, start_crown, start_clans, Balance.ground("open"), 120).crown_pct
	assert_true(open >= 40.0 and open <= 65.0, "starting armies with Royal Armories, open ground: Aurel Crown won %.1f%%" % open)
	var n := Balance.equal_gold(ra, "spearmen", "tuskers", 88)
	var spears := []
	var tuskers := []
	for i in n[0]:
		spears.append("spearmen")
	for i in n[1]:
		tuskers.append("tuskers")
	for g in ["forest_crown", "fort_crown"]:
		var held: float = Balance.batch(ra, spears, tuskers, Balance.ground(g), 120).crown_pct
		assert_true(held < 95.0, "Spearmen holding (%s) against Tuskers with Royal Armories: %.1f%%" % [g, held])
	# Iron Discipline holds through every round but the last: defending starting armies no longer stall the
	# attackers until the round cap (Crown 2.5% before; 48.5% without the mandate).
	var iron := Balance.new_state_with({"beasts": ["iron_discipline"]})
	var p: float = Balance.batch(iron, Balance.starting_army(iron, "kingdom"), Balance.starting_army(iron, "beasts"), Balance.ground("plains_clans"), 120).crown_pct
	assert_true(p >= 20.0, "starting armies, the Clans defending plains with Iron Discipline: Aurel Crown won %.1f%%" % p)


func test_keep_and_spend_both_win_a_short_fixed_seed_batch() -> void:
	# Each faction's keep preset against the other faction's spend preset (the Aurel Crown in seat 1),
	# seeds 1-10. The full check (band A, direct) has keep winning most of these; spend must still win some.
	# (#94: seeds 1-6 had one spend win; with each faction counting its own armies, the computer's ties
	# between armies broke differently and it moved to seed 9.)
	var keep_wins := 0
	var spend_wins := 0
	var keep := {Matrix.preset_of("kingdom", "keep"): true, Matrix.preset_of("beasts", "keep"): true}
	for pair in [[Matrix.preset_of("kingdom", "keep"), Matrix.preset_of("beasts", "spend")],
			[Matrix.preset_of("kingdom", "spend"), Matrix.preset_of("beasts", "keep")]]:
		for order in [["kingdom", "beasts"]]:
			var builds: Array = pair if order[0] == "kingdom" else [pair[1], pair[0]]
			for sd in range(1, 11):
				var r := Simulator.play_game(sd, order, ["ai", "ai"], 40, Callable(), {"rulers": true, "builds": builds})
				assert_eq(r.errors.size() + r.violations.size(), 0, "seed %d %s: clean" % [sd, builds])
				if not Matrix.decisive(r):
					continue
				if keep.has(str(r.builds[r.winner])):
					keep_wins += 1
				else:
					spend_wins += 1
	assert_true(keep_wins >= 1, "keep won %d of the decisive games" % keep_wins)
	assert_true(spend_wins >= 1, "spend won %d of the decisive games" % spend_wins)
