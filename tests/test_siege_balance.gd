extends "res://tests/test_case.gd"
## M3c S-7 (#105): the siege balance check (design/M3C_SIEGES.md §11). The matrix plan and how its bands are judged
## (tools/autoplay/siege_matrix.gd), the simulator's siege log and breach forecast check (band S9), the turtle's Fortify
## (band S7), the --sieges flag, and fast small-sample checks that the tuned siege numbers keep. Every number a test
## expects comes from FortData and the bands' constants in siege_matrix.gd, never from this file.
## The full check is `autoplay.gd -- --matrix --sieges --independents --jobs 4`; its report is in the PR.

const Simulator := preload("res://tools/autoplay/simulator.gd")
const Matrix := preload("res://tools/autoplay/matrix.gd")
const PathMatrix := preload("res://tools/autoplay/path_matrix.gd")
const SiegeMatrix := preload("res://tools/autoplay/siege_matrix.gd")
const Policies := preload("res://tools/autoplay/policies.gd")
const CROWN := "kingdom"
const CLANS := "beasts"


# --- the matrix plan --------------------------------------------------------------------------------

func test_the_siege_matrix_plans_every_preset_pairing_seat_order_and_mode_with_a_baseline() -> void:
	var fixture := PathMatrix.load_fixture()
	var cells := SiegeMatrix.plan(1.0, 1, fixture)
	var ids := {}
	for c in cells:
		assert_false(ids.has(c.id), "cell ids are unique: %s" % c.id)
		ids[c.id] = true
	var crown := RulerRules.presets_for(CROWN).size()
	var clans := RulerRules.presets_for(CLANS).size()
	var s := cells.filter(func(c): return c.band == "S")
	var base := cells.filter(func(c): return c.band == "S0")
	assert_eq(s.size(), crown * clans * 2 * 2, "every preset pairing x both seat orders x paths off and on")
	assert_eq(base.size(), s.size(), "a baseline cell for every siege cell")
	var games := 0
	var per_pairing := {}
	for c in s:
		games += int(c.games)
		assert_eq(int(c.games), SiegeMatrix.CELL_GAMES, "%d games per cell" % SiegeMatrix.CELL_GAMES)
		assert_true(bool(c.sieges), "sieges on")
		for seat in 2:
			assert_eq(RulerRules.preset_data(str(c.builds[seat])).faction, c.seats[seat], "seat %d plays one of its own presets" % (seat + 1))
		per_pairing[c.pairing] = int(per_pairing.get(c.pairing, 0)) + int(c.games)
		# The baseline cell has the same seats, builds, mode and seeds with sieges off.
		var twin := SiegeMatrix.find_cell(cells, "S0" + str(c.id).trim_prefix("S"))
		assert_false(twin.is_empty(), "%s has a baseline" % c.id)
		assert_false(bool(twin.sieges), "the baseline has sieges off")
		assert_eq([twin.seats, twin.builds, twin.paths, twin.seed, twin.games, twin.pairing], [c.seats, c.builds, c.paths, c.seed, c.games, c.pairing])
	assert_eq(games, crown * clans * 2 * 2 * SiegeMatrix.CELL_GAMES, "§11.2: 900 siege games")
	assert_eq(per_pairing.size(), crown * clans, "every Crown preset against every Clans preset")
	assert_eq(s.filter(func(c): return c.paths).size(), s.size() / 2, "half of the cells have paths on (sides of the fork rolled)")
	# Band S7: the turtle in either seat of either faction against ai, with sieges on and off.
	var turtles := cells.filter(func(c): return c.band == "S7")
	assert_eq(turtles.size(), 4)
	var total_turtle := 0
	for c in turtles:
		total_turtle += int(c.games)
		assert_true(bool(c.sieges))
		assert_true(c.policies.has("turtle") and c.policies.has(SiegeMatrix.POLICY))
	assert_eq(total_turtle, 4 * SiegeMatrix.TURTLE_GAMES, "100 games of the turtle against ai")
	assert_eq(cells.filter(func(c): return c.band == "S7b").size(), 4, "and the same four with sieges off")
	# Band S8 plays the M2 matrix's cells with everything off, on the fixture's seeds and turn cap.
	var m2 := cells.filter(func(c): return c.band == "S8")
	assert_eq(m2.size(), Matrix.plan(1.0, 1).size(), "one S8 cell per M2 matrix cell")
	for c in m2:
		assert_false(bool(c.sieges) or bool(c.paths), "sieges and paths off")
		assert_eq(int(c.games), SiegeMatrix.M2_PER_CELL)
		assert_eq(int(c.turn_cap), int(fixture.turn_cap), "the fixture's turn cap")
	assert_eq(fixture.digests.size(), m2.size() * SiegeMatrix.M2_PER_CELL, "a digest for every S8 game")
	# --scale shrinks the S bands, never S8; every planned game is in exactly one work item.
	var small := SiegeMatrix.plan(0.2, 1, fixture)
	assert_eq(small.filter(func(c): return c.band == "S")[0].games, 5)
	assert_eq(small.filter(func(c): return c.band == "S8")[0].games, SiegeMatrix.M2_PER_CELL)
	var work := 0
	for it in Matrix.work_items(cells):
		work += int(it.count)
	var planned := 0
	for c in cells:
		planned += int(c.games)
	assert_eq(work, planned, "every planned game is in exactly one work item")
	# A short pairing doubles its siege games and its baseline's, nobody else's.
	assert_true(SiegeMatrix.doubles(s[0]) and SiegeMatrix.doubles(base[0]))
	assert_false(SiegeMatrix.doubles(turtles[0]) or SiegeMatrix.doubles(m2[0]))


func test_only_matches_cells_by_every_text_joined_with_an_ampersand() -> void:
	assert_true(SiegeMatrix.matches("S:plain:warrior_king+beast_god_unbound:kb", "S:&beast_god"))
	assert_false(SiegeMatrix.matches("S0:plain:warrior_king+beast_god_unbound:kb", "S:&beast_god"), "the baseline's id has no 'S:'")
	assert_false(SiegeMatrix.matches("S:plain:warrior_king+clan_moot:kb", "S:&beast_god"))
	assert_true(SiegeMatrix.matches("S7:turtle_beasts_seat1", "turtle"))
	assert_true(SiegeMatrix.matches("anything", ""), "no text matches every cell")


func test_the_s6_note_says_how_firm_a_tilt_is() -> void:
	var span := SiegeMatrix.wilson(50, 100)
	assert_true(span[0] < 0.5 and span[1] > 0.5 and absf((span[0] + span[1]) / 2.0 - 0.5) < 0.01, "a 50% record is centred on 50%")
	assert_true(span[1] - span[0] > 0.15 and span[1] - span[0] < 0.25, "and about 20 points wide at 100 games")
	assert_eq(SiegeMatrix.wilson(0, 0), [0.0, 1.0], "nothing played says nothing")
	var row := {"crown_wins": 72, "decisive": 100, "base_crown_wins": 44, "base_decisive": 100}
	var text := SiegeMatrix._dominance_text(row)
	assert_true(text.contains("Crown side: 72 of 100") and text.contains("sieges off 44 of 100"), text)
	assert_true(text.contains("standard errors apart"))
	row = {"crown_wins": 30, "decisive": 100, "base_crown_wins": 50, "base_decisive": 100}
	assert_true(SiegeMatrix._dominance_text(row).contains("Clans side: 70 of 100"), "the leading side is named")


func test_the_capture_wait_has_its_words_and_every_text_that_names_it_says_it() -> void:
	assert_true(FortData.CAPTURE_WAIT >= 0 and FortData.CAPTURE_WAIT < FortData.CAPTURE_WAIT_WORDS.size(), "the wait is one of §11.3's 0-2, each with its words")
	var words: String = FortData.CAPTURE_WAIT_WORDS[FortData.CAPTURE_WAIT]
	for id in ["recruit_at_forts", "empty_fort", "capture", "recruit"]:
		assert_true(RulesCodex.text(id).contains(words), "%s says '%s'" % [id, words])
	# The rule itself: a fort taken on turn t takes recruits from turn t + wait + 1, which is what the words and the refusal say.
	var s := GameState.with_sieges(5)
	var p := s.find_province("stonegate")
	p.owner = CROWN
	p.owned_since = 4
	var turn_ok := 4 + FortData.CAPTURE_WAIT + 1
	s.current_turn = turn_ok - 2
	var ut: UnitType = s.find_faction(CROWN).unit_types[0]
	var early := SiegeRules.check_recruit_at(s, CROWN, "stonegate", ut, 0)
	assert_eq(String(early.get("code", "")), "fort_just_taken", "the turn before it is allowed is refused")
	assert_true(String(early.reason).contains("from turn %d" % turn_ok), early.reason)
	s.current_turn = turn_ok - 1
	assert_eq(SiegeRules.check_recruit_at(s, CROWN, "stonegate", ut, 0), {}, "and on turn %d it takes recruits" % turn_ok)


func test_a_pairing_with_too_few_decisive_siege_games_is_short() -> void:
	var results := []
	for i in 5:
		results.append({"band": "S", "pairing": "a|b", "finished": true, "draw": false, "winner": CROWN})
	for i in 3:
		results.append({"band": "S", "pairing": "c|d", "finished": i < 1, "draw": false, "winner": CROWN})
	results.append({"band": "S0", "pairing": "e|f", "finished": false, "draw": false, "winner": ""})  # the baseline never doubles a pairing
	var short := SiegeMatrix.short_pairings(results, 5.0 / SiegeMatrix.MIN_DECISIVE)
	assert_false(short.has("a|b"), "5 decisive games are enough at this scale")
	assert_true(short.has("c|d"))
	assert_false(short.has("e|f"))


# --- judging the bands ------------------------------------------------------------------------------

## A siege game that passes every band when there are enough of them: `winner` wins on turn `turns`, one siege, one storm and two
## battles at the breach, one palisade built by each faction, a third of its fort recruits made outside the capital.
func _game(pairing: String, crown_seat: bool, winner: String, turns: int, with_paths := false, replay := "", band := "S") -> Dictionary:
	var parts := pairing.split("|")
	var seats := [CROWN, CLANS] if crown_seat else [CLANS, CROWN]
	var builds := {CROWN: parts[0], CLANS: parts[1]}
	var recruits := {}
	for fid in seats:
		recruits[fid] = {"capital": 20, "palisade": 5, "keep": 5, "ruler": 0, "engines": 1}
	var log := {"started": [{"turn": 6, "province": "stonegate", "level": 2, "capital": false, "owner": CLANS, "besieger": CROWN, "troops": 14, "engines": 1}],
		"ended": [{"turn": 8, "province": "stonegate", "level": 2, "capital": false, "owner": CLANS, "besieger": CROWN, "kind": "fallen", "why": "battle",
			"length": 3, "by": "breach"}, {"turn": 10, "province": "fangridge", "level": 3, "capital": true, "owner": CLANS, "besieger": CROWN, "kind": "lifted",
			"why": "beaten", "length": 2, "by": "sally"}],
		"battles": [{"turn": 7, "province": "stonegate", "level": 2, "capital": false, "kind": "breach", "why": "breach", "winner": CROWN, "owner": CLANS,
			"attacker_won": true, "turn_of_siege": 3}, {"turn": 9, "province": "fangridge", "level": 3, "capital": true, "kind": "storm", "why": "storm",
			"winner": CROWN, "owner": CLANS, "attacker_won": true, "turn_of_siege": 1}, {"turn": 11, "province": "fangridge", "level": 3, "capital": true,
			"kind": "breach", "why": "breach", "winner": CROWN, "owner": CLANS, "attacker_won": true, "turn_of_siege": 3}],
		"built": {CROWN: {"palisade": 1, "keep": 1}, CLANS: {"palisade": 1, "keep": 0}}, "works": {CROWN: 2, CLANS: 1}, "recruits": recruits,
		"orders": {"storm": 1, "sally": 1}, "relief": {"chances": 2, "taken": 1}, "cut_off": 2,
		"capital_taken": {"turn": turns, "province": "fangridge", "faction": winner, "how": "storm"} if not winner.is_empty() else {},
		"forecast": {"checks": 6, "mismatches": 0, "first": ""}, "last_battle": turns}
	return {"band": band, "cell": "%s:test" % band, "pairing": pairing, "seed": 1, "seats": seats, "policies": ["ai", "ai"], "builds": builds,
		"finished": not winner.is_empty(), "draw": false, "winner": winner, "winner_seat": seats.find(winner) + 1, "turns": turns,
		"with_paths": with_paths, "with_sieges": band == "S", "violations": [], "errors": [], "script_errors": [], "replay": replay, "sieges": log}


func _baseline(g: Dictionary) -> Dictionary:
	var c: Dictionary = g.duplicate(true)
	c.band = "S0"
	c.with_sieges = false
	c.sieges = {}
	return c


## A turtle game: the turtle (seat 1) and ai; the turtle wins when `turtle_wins`.
func _turtle_game(turtle_wins: bool, cap := false, band := "S7") -> Dictionary:
	var g := _game("iron_crown|clan_moot", true, "" if cap else (CROWN if turtle_wins else CLANS), 25, false, "", band)
	g.policies = ["turtle", "ai"]
	g.cell = "%s:turtle_kingdom_seat1" % band
	g.pairing = "S7"
	if cap:
		g.turns = 60
	return g


func _m2_games(fixture: Dictionary) -> Array:
	var out := []
	for key in fixture.digests:
		var parts := str(key).split("|")
		out.append({"band": "S8", "cell": "S8:" + parts[0], "pairing": "S8", "seed": int(parts[1]), "record_md5": fixture.digests[key],
			"finished": true, "draw": false, "winner": CROWN, "turns": 20, "violations": [], "errors": [], "script_errors": [], "replay": ""})
	return out


func _band(j: Dictionary, name: String) -> Dictionary:
	for b in j.bands:
		if b.band == name:
			return b
	return {}


func _all_games() -> Array:
	var games := []
	for p in ["warrior_king|clan_moot", "iron_crown|beast_god_unbound", "regents_court|blood_of_the_fang"]:
		for i in 10:
			# 5-5 in both seat orders, over 16- and 18-turn games; the replays of the first game of each pairing.
			games.append(_game(p, i % 2 == 0, CROWN if i < 5 else CLANS, 16 + 2 * (i % 2), i % 3 == 0, "identical" if i == 0 else ""))
	for i in 10:
		games.append(_turtle_game(i < 1))
	return games


## Judges `games` with a baseline made from `base_from` (the games themselves when it is empty).
func _judge(games: Array, fixture: Dictionary, off := {"games": 9, "identical": 9, "first": ""}, base_from: Array = []) -> Dictionary:
	var all := games.duplicate()
	for g in (games if base_from.is_empty() else base_from):
		if g.band == "S":
			all.append(_baseline(g))
	for g in games:
		if g.band == "S7":
			all.append(_turtle_game(false, false, "S7b"))
	return SiegeMatrix.judge(all + _m2_games(fixture), 0, fixture, off)


func test_the_siege_bands_are_judged_from_the_games() -> void:
	var fixture := PathMatrix.load_fixture()
	var j := _judge(_all_games(), fixture)
	for name in ["S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9"]:
		assert_eq(_band(j, name).status, "pass", "%s: %s %s" % [name, _band(j, name).result, _band(j, name).detail])
	assert_eq(_band(j, "S10").status, "report", "S10 is report only")
	assert_true(j.ok, "S8 and S9 hold")
	assert_eq(j.bands.size(), 10, "S1-S10")


func test_each_band_misses_when_its_target_is_missed() -> void:
	var fixture := PathMatrix.load_fixture()
	var games := _all_games()
	# S1: long games, and games at the cap.
	var long := games.map(func(g):
		var c: Dictionary = g.duplicate(true)
		if c.band == "S":
			c.turns = int(SiegeMatrix.S1_BAND[1]) + 6
		return c)
	assert_eq(_band(_judge(long, fixture), "S1").status, "miss", "a median above 22 turns")
	var capped := games.duplicate(true)
	for i in 4:
		capped[i].finished = false
		capped[i].winner = ""
		capped[i].winner_seat = 0
		capped[i].turns = 60
	assert_eq(_band(_judge(capped, fixture), "S1").status, "miss", "4 of 30 at the cap is above 5%")
	assert_true(str(_band(_judge(capped, fixture), "S1").detail).contains("capped"), "a miss says what the capped games were")
	# S2: no siege starts.
	var quiet := games.duplicate(true)
	for g in quiet:
		if g.band == "S":
			g.sieges.started = []
	assert_eq(_band(_judge(quiet, fixture), "S2").status, "miss")
	# S3: every battle a storm, and none.
	var all_storms := games.duplicate(true)
	for g in all_storms:
		for b in g.get("sieges", {}).get("battles", []):
			b.kind = "storm"
			b.why = "storm"
	assert_eq(_band(_judge(all_storms, fixture), "S3").status, "miss", "storms above 60%")
	var no_storms := games.duplicate(true)
	for g in no_storms:
		for b in g.get("sieges", {}).get("battles", []):
			b.kind = "breach"
			b.why = "breach"
	assert_eq(_band(_judge(no_storms, fixture), "S3").status, "miss", "storms below 15%")
	# S4: no forts, and fort spam.
	var no_forts := games.duplicate(true)
	for g in no_forts:
		if g.band == "S":
			g.sieges.built = {}
	assert_eq(_band(_judge(no_forts, fixture), "S4").status, "miss", "median 0")
	var spam := games.duplicate(true)
	for g in spam:
		if g.band == "S":
			g.sieges.built = {CROWN: {"palisade": int(SiegeMatrix.S4_P95_MAX) + 3, "keep": 1}, CLANS: {"palisade": 2, "keep": 0}}
	assert_eq(_band(_judge(spam, fixture), "S4").status, "miss", "a 95th percentile above 5")
	# S5: everything at the capital, and nothing there.
	for place in [["capital", 30, "keep"], ["keep", 30, "capital"]]:
		var skew := games.duplicate(true)
		for g in skew:
			if g.band == "S":
				for fid in g.sieges.recruits:
					g.sieges.recruits[fid][place[0]] = place[1]
					g.sieges.recruits[fid][place[2]] = 0
					g.sieges.recruits[fid].palisade = 0
		assert_eq(_band(_judge(skew, fixture), "S5").status, "miss", "recruits all at %s" % place[0])
	# S6: a pairing the Crown wins every game of, that was balanced without sieges.
	var tilt := games.duplicate(true)
	for g in tilt:
		if g.band == "S" and g.pairing == "warrior_king|clan_moot":
			g.winner = CROWN
			g.winner_seat = g.seats.find(CROWN) + 1
	var jt := _judge(tilt, fixture, {"games": 9, "identical": 9, "first": ""}, games)
	assert_eq(_band(jt, "S6").status, "miss", "%s %s" % [_band(jt, "S6").result, _band(jt, "S6").detail])
	assert_true(str(_band(jt, "S6").detail).contains("Alex"), "a miss goes to Alex")
	assert_eq(_band(_judge(tilt, fixture), "S6").status, "pass", "a pairing that was just as lopsided without sieges is not new")
	# S7: the turtle wins half its games; or sits at the cap.
	var strong := games.duplicate(true)
	for g in strong:
		if g.band == "S7":
			g.winner = CROWN
			g.winner_seat = 1
	assert_eq(_band(_judge(strong, fixture), "S7").status, "miss", "the turtle wins above 10%")
	var stalled := games.filter(func(g): return g.band != "S7")
	for i in 10:
		stalled.append(_turtle_game(false, i < 2))
	assert_eq(_band(_judge(stalled, fixture), "S7").status, "miss", "2 of 10 at the cap is above 10%")
	# S10 never changes a status: a defence that never works is only reported.
	var no_defence := games.duplicate(true)
	for g in no_defence:
		if g.band == "S":
			g.sieges.ended = [g.sieges.ended[0]]
	var jd := _judge(no_defence, fixture)
	assert_eq(_band(jd, "S10").status, "report")
	assert_eq(_band(jd, "S10").detail, "under 10%")
	assert_true(jd.ok, "a band that is only a target never changes the exit code")


func test_the_exit_code_follows_s8_and_s9_only() -> void:
	var fixture := PathMatrix.load_fixture()
	var games := _all_games()
	# A band missed in any way keeps exit 0: S6 here.
	var tilt := games.duplicate(true)
	for g in tilt:
		if g.band == "S":
			g.winner = CROWN
			g.winner_seat = g.seats.find(CROWN) + 1
	var jt := _judge(tilt, fixture, {"games": 9, "identical": 9, "first": ""}, games)
	assert_eq(_band(jt, "S6").status, "miss")
	assert_true(jt.ok, "bands that are target ranges do not gate")
	# A violation, a session error, a script error, a bad replay and a forecast mismatch each miss S9.
	for what in ["violations", "errors", "script_errors", "replay", "forecast"]:
		var bad := games.duplicate(true)
		match what:
			"violations":
				bad[0].violations = [{"seed": 1, "turn": 3, "check": "gold_accounting", "detail": "x"}]
			"errors":
				bad[0].errors = [{"seed": 1, "turn": 3, "detail": "x"}]
			"script_errors":
				bad[0].script_errors = [{"seed": 1, "turn": 3, "detail": "x"}]
			"replay":
				bad[0].replay = "differs: the replayed final state is not the one the game reached"
			"forecast":
				bad[0].sieges.forecast = {"checks": 3, "mismatches": 1, "first": "the walls of stonegate reached 0 on turn 9, but turn 7 forecast turn 8"}
		var jb := _judge(bad, fixture)
		assert_eq(_band(jb, "S9").status, "miss", "S9 misses on %s" % what)
		assert_false(jb.ok, "the exit code follows S9 (%s)" % what)
	# No replay at all is no proof.
	var none := games.map(func(g):
		var c: Dictionary = g.duplicate(true)
		c.replay = ""
		return c)
	assert_eq(_band(_judge(none, fixture), "S9").status, "miss", "no replays, no pass")
	# An M2 game whose record differs from main, a fixture game that doesn't replay, and a missing fixture each miss S8.
	var m2 := _m2_games(fixture)
	m2[0].record_md5 = "0"
	var all := games.duplicate()
	for g in games:
		if g.band == "S":
			all.append(_baseline(g))
	var jm := SiegeMatrix.judge(all + m2, 0, fixture, {"games": 9, "identical": 9, "first": ""})
	assert_eq(_band(jm, "S8").status, "miss", _band(jm, "S8").detail)
	assert_false(jm.ok, "the exit code follows S8")
	var jf := _judge(games, fixture, {"games": 9, "identical": 8, "first": "m1_ai_vs_ai: turn 3: the state is not the one main reached"})
	assert_eq(_band(jf, "S8").status, "miss")
	assert_true(str(_band(jf, "S8").detail).contains("m1_ai_vs_ai"))
	assert_false(jf.ok)
	assert_eq(_band(SiegeMatrix.judge(all + _m2_games(fixture), 0, {}, {"games": 9, "identical": 9, "first": ""}), "S8").status, "miss", "no fixture, no pass")
	# Script errors outside games count too.
	assert_eq(_band(SiegeMatrix.judge(all + _m2_games(fixture), 2, fixture, {"games": 9, "identical": 9, "first": ""}), "S9").status, "miss")


func test_the_report_prints_every_band_and_the_sections() -> void:
	var fixture := PathMatrix.load_fixture()
	var j := _judge(_all_games(), fixture)
	var md := SiegeMatrix.to_markdown(j)
	for name in ["S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S10"]:
		assert_true(md.contains("| %s |" % name), "the table has %s" % name)
	for section in ["Siege counts", "Storms against breaches", "Forts built", "Recruits by fort", "Siege lengths",
			"The cap share against the sieges-off baseline", "The turtle against the computer"]:
		assert_true(md.contains("### " + section), "the report has the section '%s'" % section)
	assert_true(md.contains("**pass**"))
	# The sections alone (what --sieges prints after a single run) hold the counts of the games.
	var s_res := _all_games().filter(func(g): return g.band == "S")
	var lines := "\n".join(SiegeMatrix.sections(s_res))
	assert_true(lines.contains("%d of %d" % [s_res.size(), s_res.size()]), "every game had a siege")
	var counts := SiegeMatrix.storm_counts(s_res)
	assert_eq(counts.storms, s_res.size(), "one storm a game")
	assert_eq(counts.battles, 3 * s_res.size(), "three battles a game")
	assert_eq(SiegeMatrix.ending_counts(s_res).defence, s_res.size(), "one siege a game ended by a sally")
	assert_eq(SiegeMatrix.percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.95), 10.0)
	assert_eq(SiegeMatrix.percentile([], 0.5), 0.0)


# --- the simulator's siege log and breach forecast check ---------------------------------------------

func test_a_real_siege_game_keeps_a_siege_log_and_the_forecasts_hold() -> void:
	var logged := 0
	var checks := 0
	for seed_value in [7, 8, 9]:
		var r := Simulator.play_game(seed_value, [CROWN, CLANS], ["ai", "ai"], 30, Callable(), {"rulers": true, "sieges": true, "independents": true,
			"builds": ["warrior_king", "beast_god_unbound"], "replay_check": seed_value == 7})
		assert_eq(r.errors.size() + r.violations.size() + r.script_errors.size(), 0, "a clean game: %s" % [r.violations.slice(0, 2)])
		var sg: Dictionary = r.sieges
		assert_false(sg.is_empty(), "a game with sieges has a siege log")
		assert_false(sg.has("pending"), "the working notes are not kept")
		assert_eq(sg.forecast.mismatches, 0, "the breach forecasts hold: %s" % sg.forecast.first)
		checks += int(sg.forecast.checks)
		assert_eq(sg.ended.size(), sg.started.size() - _standing(r), "every siege that is over has an end")
		for b in sg.battles:
			assert_true(["storm", "open", "breach"].has(b.kind) and b.why != "empty", "battle kinds: %s/%s" % [b.kind, b.why])
		var rec := 0
		for fid in sg.recruits:
			for k in sg.recruits[fid]:
				rec += int(sg.recruits[fid][k])
		assert_true(rec > 0, "recruits were counted")
		assert_true(sg.final.has(CROWN) and sg.final.has(CLANS), "where the troops stood at the end")
		if seed_value == 7:
			assert_eq(r.replay, "identical", "the game replays from its record")
		logged += sg.started.size() + sg.battles.size()
	assert_true(logged > 0, "at least one siege or battle at a fort in three games")
	# A game without sieges has no log, and nothing in it changed.
	var off := Simulator.play_game(7, [CROWN, CLANS], ["ai", "ai"], 12, Callable(), {"rulers": true})
	assert_eq(off.sieges, {}, "no siege log without sieges")


## Sieges still standing in the game's final state (their end was never reported).
func _standing(r: Dictionary) -> int:
	var n := 0
	for p in r.get("final_state", {}).get("provinces", []):
		n += 1 if int(p.get("siege_since", 0)) > 0 else 0
	return n


func test_the_breach_forecast_check_catches_a_wrong_forecast() -> void:
	var log := Simulator.siege_log_new()
	var event := func(type: String, turn: int, walls: int, breach_turn: int, armies: Array, damage := 3) -> Dictionary:
		return {"type": type, "provinces": ["stonegate"], "factions": [CROWN, CLANS], "armies": armies, "numbers": {"walls": walls, "damage": damage,
			"breach_turn": breach_turn, "owner": CLANS, "besieger": CROWN, "turn_of_siege": turn - 4, "troops": 20, "engines": 0}}
	var army := ["kingdom-1"]
	# Walls 6, 3 a turn: started on turn 5 with 3 left, forecast to reach 0 on turn 6, and they do.
	Simulator._forecast_step(log, event.call("siege_started", 5, 3, 6, army), 5)
	Simulator._forecast_step(log, event.call("walls_damaged", 6, 0, 6, army), 6)
	assert_eq([log.forecast.checks, log.forecast.mismatches], [1, 0], "right on time")
	# The forecast was turn 6 but the walls stood after it, with the same armies and damage: a mismatch.
	log = Simulator.siege_log_new()
	Simulator._forecast_step(log, event.call("siege_started", 5, 3, 6, army), 5)
	Simulator._forecast_step(log, event.call("walls_damaged", 6, 1, 7, army), 6)
	assert_eq(log.forecast.mismatches, 1, "walls that stand on the forecast turn are a mismatch")
	assert_true(str(log.forecast.first).contains("stonegate"), "it says where")
	# The breach one turn late (walls_breached on turn 7 against a forecast of 6) is one too.
	log = Simulator.siege_log_new()
	Simulator._forecast_step(log, event.call("siege_started", 5, 3, 6, army), 5)
	Simulator._forecast_step(log, event.call("walls_breached", 7, 0, 6, army), 7)
	assert_eq(log.forecast.mismatches, 1)
	# An army entering the siege starts the forecast over: no check, no mismatch.
	log = Simulator.siege_log_new()
	Simulator._forecast_step(log, event.call("siege_started", 5, 3, 6, army), 5)
	Simulator._forecast_step(log, event.call("walls_damaged", 6, 1, 7, ["kingdom-1", "kingdom-2"], 2), 6)
	assert_eq([log.forecast.checks, log.forecast.mismatches], [0, 0], "armies changed")
	# A forecast that moves with the same armies and damage is a mismatch even before the breach.
	log = Simulator.siege_log_new()
	Simulator._forecast_step(log, event.call("siege_started", 5, 4, 8, army), 5)
	Simulator._forecast_step(log, event.call("walls_damaged", 6, 2, 9, army), 6)
	assert_eq(log.forecast.mismatches, 1, "the forecast turn must not move")


func test_the_simulator_checks_that_no_battle_side_is_without_a_fighter() -> void:
	var s := GameState.with_sieges(3)
	var report := {"end": "rout", "rounds_fought": 2, "sides": [{"faction": CROWN, "hp_end": 3, "fighters_lost": 1, "fighters_start": 4},
		{"faction": CLANS, "hp_end": 0, "fighters_lost": 0, "fighters_start": 0}]}
	var event := {"type": "battle", "phase": "battles", "provinces": ["stonegate"], "factions": [CROWN, CLANS], "numbers": {"report": report, "destroyed": []}}
	var found := Simulator.check_invariants(null, s, [event])
	assert_true(found.any(func(v): return v.check == "battle_side_without_fighter"), "a side with no fighter is a violation: %s" % [found])


# --- the --sieges flag -------------------------------------------------------------------------------

func test_sieges_option_starts_the_game_with_forts_and_walls() -> void:
	var on := Simulator.play_game(3, [CROWN, CLANS], ["greedy", "greedy"], 1, Callable(), {"sieges": true})
	assert_eq(on.errors.size(), 0)
	assert_true(on.final_state.get("sieges", false), "forts and sieges are on")
	var capital := {}
	for p in on.final_state.provinces:
		if p.get("is_capital", false) or p.id == "crownkeep":
			capital = p
	assert_eq(int(capital.get("fort_level", 0)), int(FortData.START.capital), "capitals start as citadels")
	var off := Simulator.play_game(3, [CROWN, CLANS], ["greedy", "greedy"], 1)
	assert_false(off.final_state.has("sieges"), "off by default, with no siege key")
	# Setup flags (independents, sieges) combine with rulers and paths.
	var all := Simulator.play_game(3, [CROWN, CLANS], ["ai", "ai"], 2, Callable(), {"paths": true, "sieges": true, "independents": true})
	assert_eq(all.errors.size() + all.violations.size(), 0, "paths, sieges and independents together: %s" % [all.errors.slice(0, 1)])
	assert_true(all.final_state.get("sieges", false) and all.final_state.get("independents", false) and all.final_state.get("paths", false))


func test_matrix_play_item_runs_a_cell_with_the_cell_deciding_sieges() -> void:
	var cells := SiegeMatrix.plan(1.0, 1, PathMatrix.load_fixture())
	var on := SiegeMatrix.find_cell(cells, "S:plain:warrior_king+clan_moot:kb")
	var off := SiegeMatrix.find_cell(cells, "S0:plain:warrior_king+clan_moot:kb")
	assert_false(on.is_empty() or off.is_empty())
	# --sieges is in autoplay's setup flags, but the cell decides: a baseline cell stays off.
	var r_on := SiegeMatrix.play_item(cells, {"cell": on.id, "from": 1, "count": 1}, 3, Callable(), {"sieges": true, "independents": true})
	var r_off := SiegeMatrix.play_item(cells, {"cell": off.id, "from": 1, "count": 1}, 3, Callable(), {"sieges": true, "independents": true})
	assert_eq(r_on.size(), 1)
	assert_true(bool(r_on[0].with_sieges) and not r_on[0].sieges.is_empty())
	assert_false(bool(r_off[0].with_sieges))
	assert_true(r_off[0].sieges.is_empty(), "the baseline has no siege log")
	assert_eq(r_on[0].band, "S")
	assert_eq(r_off[0].band, "S0")
	assert_false(r_on[0].has("final_state"), "results leave the final state out")
	assert_eq(r_on[0].replay, "identical", "the first game of a cell is replayed")


func test_the_m2_games_and_the_fixtures_replay_with_sieges_off() -> void:
	var fixture := PathMatrix.load_fixture()
	var cells := SiegeMatrix.plan(1.0, 1, fixture)
	var cell := SiegeMatrix.find_cell(cells, "S8:" + str(Matrix.plan(1.0, int(fixture.seed))[0].id))
	var r := SiegeMatrix.play_item(cells, {"cell": cell.id, "from": int(cell.seed), "count": 1}, int(cell.turn_cap))
	var key := "%s|%d" % [str(cell.id).trim_prefix("S8:"), int(cell.seed)]
	assert_true(fixture.digests.has(key), "the fixture has this game")
	assert_eq(r[0].record_md5, fixture.digests[key], "a sieges-off M2 game is byte-identical to the one recorded on main")
	var off := SiegeMatrix.replay_off_fixtures()
	assert_true(int(off.games) >= 9, "the M1, M2 and M4 games of both fixtures")
	assert_eq(off.identical, off.games, "every fixture game replays turn by turn: %s" % off.first)


# --- the turtle (band S7) ----------------------------------------------------------------------------

func _turtle_state() -> GameState:
	var s := GameState.with_sieges(11)
	s.current_turn = 3
	return s


func test_the_turtle_claims_its_safest_neighbor_then_fortifies_it_and_recruits_there() -> void:
	var s := _turtle_state()
	var me := s.find_faction(CROWN)
	me.gold = FortData.level(2).cost + 20
	var policy = Policies.make("turtle")
	# It owns nothing but its capital: its strongest army claims a neutral neighbor of the capital.
	var first: Array = policy.orders(s, CROWN, SeededRNG.new(1))
	var claims := first.filter(func(o): return o is MoveOrder)
	assert_eq(claims.size(), 1, "one army claims a province")
	var home := s.find_province(me.capital)
	assert_true(home.neighbors.has(claims[0].to), "a neighbor of the capital")
	assert_eq(s.find_province(claims[0].to).owner, "", "a neutral one")
	assert_false(first.any(func(o): return o is FortifyOrder), "nothing to fortify before it owns land")
	# Once it owns a province, it fortifies the safest one (a palisade first), paying for it before it recruits.
	var p := s.find_province(claims[0].to)
	p.owner = CROWN
	p.owned_since = 1
	var second: Array = policy.orders(s, CROWN, SeededRNG.new(1))
	var forts := second.filter(func(o): return o is FortifyOrder)
	assert_eq(forts.size(), 1, "one Fortify order")
	assert_eq(forts[0].province, p.id)
	assert_eq(second.find(forts[0]), second.find(second.filter(func(o): return o is FortifyOrder or o is RecruitOrder)[0]), "the Fortify comes first")
	assert_eq(SiegeRules.check_fortify(s, CROWN, p.id), {}, "a legal order")
	var priced := TurnResolver.price_recruits(s, CROWN, second.filter(func(o): return o is FortifyOrder or o is RecruitOrder))
	for r in priced.results:
		assert_true(r.ok, "every order is accepted: %s" % [r.get("reason", "")])
	assert_true(priced.spent <= me.gold, "within its gold")
	# A palisade it owns is made a keep next; and its armies there stay.
	p.fort_level = 1
	p.has_fort = true
	p.walls = FortData.level(1).walls
	var third: Array = policy.orders(s, CROWN, SeededRNG.new(1))
	assert_eq(third.filter(func(o): return o is FortifyOrder)[0].province, p.id, "the same province becomes a keep")
	# Recruits go to the fort once it can take them (held since last turn), up to its limit, the rest at the capital.
	p.owned_since = 0
	var recruits := third.filter(func(o): return o is RecruitOrder)
	var at_fort := recruits.filter(func(o): return o.at == p.id)
	assert_true(at_fort.size() > 0 and at_fort.size() <= SiegeRules.recruit_limit(p.fort_level), "recruits at its fort, within the limit: %d" % at_fort.size())
	for o in at_fort:
		assert_eq(s.find_faction(CROWN).capital == p.id, false)
	# It saves for a keep it cannot yet pay for while no rival is near (it recruits nothing meanwhile), and recruits again when one is near.
	me.gold = FortData.level(2).cost - 1
	var saving: Array = policy.orders(s, CROWN, SeededRNG.new(1))
	assert_eq(saving.filter(func(o): return o is FortifyOrder or o is RecruitOrder).size(), 0, "saving up")
	var raider := Army.new()
	raider.id = "beasts-9"
	raider.owner = CLANS
	raider.location = "highcrag" if p.id != "highcrag" else "rivermarch"
	raider.units.append(Unit.new(s.find_faction(CLANS).unit_types[0], CLANS))
	s.armies.append(raider)
	var near: Array = policy.orders(s, CROWN, SeededRNG.new(1))
	assert_true(near.any(func(o): return o is RecruitOrder), "with a rival near it recruits")
	s.armies.erase(raider)
	me.gold = FortData.level(2).cost + 20
	# One site at a time.
	p.works = {"faction": CROWN, "to": 2, "left": 2, "turn": 3}
	assert_eq(policy.orders(s, CROWN, SeededRNG.new(1)).filter(func(o): return o is FortifyOrder).size(), 0, "no second site while one is built")


func test_the_turtle_never_besieges_or_storms_and_keeps_its_garrison_in_its_fort() -> void:
	var s := _turtle_state()
	var me := s.find_faction(CROWN)
	var other := s.find_faction(CLANS)
	# An enemy fort next to a province of the turtle's, with a garrison: the turtle's army there does not move in.
	var west := s.find_province("westwatch")
	west.owner = CROWN
	var stone := s.find_province("stonegate")
	stone.owner = CLANS
	var army := Army.new()
	army.id = "kingdom-9"
	army.owner = CROWN
	army.location = "westwatch"
	army.units.append(Unit.new(me.unit_types[0], CROWN))
	s.armies.append(army)
	var guard := Army.new()
	guard.id = "beasts-9"
	guard.owner = CLANS
	guard.location = "stonegate"
	guard.units.append(Unit.new(other.unit_types[0], CLANS))
	s.armies.append(guard)
	var orders: Array = Policies.make("turtle").orders(s, CROWN, SeededRNG.new(2))
	assert_false(orders.any(func(o): return o is MoveOrder and o.to == "stonegate"), "no march into a garrisoned fort")
	assert_false(orders.any(func(o): return o is SiegeOrder), "never a storm or a sally")
	# An army in a fort of its own stays; one outside walks home.
	west.fort_level = 1
	west.has_fort = true
	west.walls = FortData.level(1).walls
	stone.owner = ""
	s.armies.erase(guard)
	var stays: Array = Policies.make("turtle").orders(s, CROWN, SeededRNG.new(2))
	assert_false(stays.any(func(o): return o is MoveOrder and o.army_id == "kingdom-9"), "the army in its own fort stays")
	# An army in a province that is not its fort, and not the one it will fortify, walks home.
	west.fort_level = 0
	west.has_fort = false
	west.walls = 0
	var green := s.find_province("greenglade")
	green.owner = CROWN
	army.location = "greenglade"
	var walks: Array = Policies.make("turtle").orders(s, CROWN, SeededRNG.new(2))
	assert_true(walks.any(func(o): return o is MoveOrder and o.army_id == "kingdom-9" and green.neighbors.has(o.to)), "an army with no fort walks home: %s" % [walks.map(func(o): return o.describe())])


func test_the_turtle_without_sieges_plays_as_before() -> void:
	var s := GameState.new(11)
	var orders: Array = Policies.make("turtle").orders(s, CROWN, SeededRNG.new(1))
	assert_false(orders.any(func(o): return o is FortifyOrder or (o is RecruitOrder and not o.at.is_empty())), "no fort orders in an M1 game")
	for o in orders:
		assert_true(o is RecruitOrder or o is MoveOrder)


func test_a_turtle_game_with_sieges_runs_clean_and_the_turtle_builds() -> void:
	var built := 0
	for seed_value in [21, 22, 23]:
		var r := Simulator.play_game(seed_value, [CROWN, CLANS], ["turtle", "ai"], 40, Callable(), {"rulers": true, "sieges": true})
		assert_eq(r.errors.size() + r.violations.size() + r.script_errors.size(), 0, "a clean game: %s" % [r.violations.slice(0, 2)])
		var b: Dictionary = r.sieges.built.get(CROWN, {})
		built += int(b.get("palisade", 0)) + int(b.get("keep", 0))
		assert_true(int(r.policy_stats[0].get("claims", 0)) + int(r.policy_stats[0].get("fortify", 0)) >= 1, "the turtle claimed or fortified")
	assert_true(built >= 1, "the turtle finished a fort in three games")
