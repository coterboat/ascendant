extends "res://tests/test_case.gd"
## M3-1 (#56): the battle event log (design/M3_BATTLES.md §2). Recording changes nothing (500 seeded
## battles with and without it: report, winner, armies after the losses and RNG state; the M1 battle and
## its odds unchanged), the schema, the fixtures (current, and every check passes on each), the size and
## time budgets, a lowered cap, verify_draws catching tampering, regenerate rebuilding every battle of
## AI-vs-AI games with rulers byte for byte, logs never in the game record, the timeline, and the JSON
## round trip.

const Balance := preload("res://tools/balance/balance.gd")
const Scenarios := preload("res://tools/battle_log/scenarios.gd")
const Games := preload("res://tools/battle_log/games.gd")
const RulerBattles := preload("res://tests/test_ruler_battles.gd")

const CROWN := "kingdom"
const CLANS := "beasts"
## The AI-vs-AI games with rulers whose every battle is checked (seeds 1-20, the seat order alternating:
## tools/battle_log/games.gd's seats_for, as tools/battle_log.gd --check 20 plays them).
const AUTOPLAY_GAMES := 20
const SIZE_BUDGET := 400 * 1000  # bytes of JSON for the biggest fixture (§2.4)
const TIME_BUDGET := 1.25  # recording may add at most 25% to the biggest fixture's resolve time

## The exact keys of every part of a version-1 log (§2.2), so playback code can rely on them.
const TOP_KEYS := ["v", "id", "turn", "index", "kind", "provinces", "terrain", "fort", "defender", "round_cap", "rng", "sides",
	"fighters", "events", "truncated"]
const SIDE_KEYS := ["index", "faction", "name", "defender", "armies", "fighters", "hp_start", "base_morale", "start_morale",
	"base_hit", "frenzy", "iron", "feast", "dread", "mandates"]
const FIGHTER_KEYS := ["id", "side", "army", "role", "type", "name", "trait", "tier", "hp", "max_hp", "hp_parts", "attack",
	"defense", "morale", "cost", "ruler"]
const EVENT_KEYS := {
	"round": ["t", "n", "reach"],
	"attack": ["t", "n", "by", "to", "pool", "pick", "chance", "roll", "hit", "damage", "bonus", "base_hit", "attack", "defense",
		"reach", "screened", "expected"],
	"wound": ["t", "n", "f", "from", "to", "by"],
	"death": ["t", "n", "f", "by"],
	"morale": ["t", "n", "side", "morale", "base", "parts", "break_pct", "lost_pct", "hp", "result", "held_by", "decisive",
		"iron_last_round"],
	"rout": ["t", "n", "side", "fled"],
	"destroyed": ["t", "n", "side"],
	"round_end": ["t", "n", "hp", "attacks", "hits", "dealt", "expected", "impact"],
	"end": ["t", "rounds", "winner", "how", "tie_break", "roll", "tied", "impact"],
	"feast": ["t", "side", "healed"],
	"aftermath": ["t", "destroyed_armies", "lost", "fallen_rulers", "text"],
}


# --- helpers ------------------------------------------------------------------------------------------

## The M1 battle test_ruler_battles.gd pins (seed 4242): {"result", "battle", "before"}.
func _m1_turn() -> Dictionary:
	var s := GameState.new(99)
	s.armies.clear()
	for spec in [["kingdom-1", CROWN, "thornvale", ["spearmen", "spearmen", "crossbowmen", "knights", "knight_captain"]],
			["beasts-2", CLANS, "wildmoor", ["tuskers", "tuskers", "fangthrowers", "war_bear", "warchief"]]]:
		var a := Army.new()
		a.id = spec[0]
		a.owner = spec[1]
		a.location = spec[2]
		var f := s.find_faction(a.owner)
		for type_id in spec[3]:
			var ut := TurnResolver.recruitable_type(f, type_id)
			if ut.is_commander:
				a.commander = Unit.new(ut, f.id)
			else:
				a.units.append(Unit.new(ut, f.id))
		s.armies.append(a)
	var before := s.deep_copy()
	var r := TurnResolver.resolve(s, {CLANS: [MoveOrder.new("beasts-2", "thornvale")]}, 4242, AutoBattleResolver.new())
	return {"result": r, "battle": r.events.filter(func(e): return e.type == "battle")[0], "before": before}


## One battle of the harness, fought on fresh armies with recording on or off, then the winner's losses
## applied: what must not depend on recording.
func _harness_battle(state: GameState, crown_ids: Array, clans_ids: Array, g: Dictionary, sd: int, ruler_fids: Array, record: bool) -> Dictionary:
	var crown := Balance.army(state, CROWN, crown_ids, "kingdom-1")
	var clans := Balance.army(state, CLANS, clans_ids, "beasts-2")
	var province := state.find_province(g.province)
	crown.location = province.id
	clans.location = province.id
	var sides := [{"faction": CLANS, "armies": [clans]}, {"faction": CROWN, "armies": [crown]}]
	for side in sides:
		if ruler_fids.has(side.faction):
			var ra := Balance.ruler_army(state, side.faction, side.faction + "-9")
			ra.location = province.id
			side.armies.append(ra)
	var ctx := {"kind": "province", "defender": g.defender, "province": province, "province_ids": [province.id], "state": state}
	var rng := SeededRNG.new(sd)
	var r := AutoBattleResolver.fight(sides, ctx, rng, record)
	var feast := AutoBattleResolver._apply_losses(r.sides, r.result.winner)
	var armies := []
	for side in sides:
		for a in side.armies:
			armies.append(a.to_dict())
	return {"result": r.result, "feast": feast, "armies": armies, "rng": rng.get_state(), "log": r.get("log", {})}


func _fixture(name: String) -> Dictionary:
	var path := Scenarios.fixture_path(name)
	assert_true(FileAccess.file_exists(path), "the fixture %s exists" % path)
	var fx = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(fx is Dictionary, "the fixture %s is JSON" % name)
	return fx if fx is Dictionary else {}


## `v` as JSON after a JSON round trip, so values read from a file and values just made compare alike.
func _canon(v) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(v)))


func _attacks(battle_log: Dictionary) -> Array:
	return battle_log.events.filter(func(e): return e.t == "attack")


func _assert_checks(battle_log: Dictionary, report: Dictionary, what: String) -> void:
	assert_eq(BattleLog.validate(battle_log), [], "%s: validate" % what)
	assert_eq(BattleLog.verify_draws(battle_log), [], "%s: verify_draws" % what)
	assert_eq(BattleLog.cross_check(battle_log, report), [], "%s: cross_check" % what)


# --- recording changes nothing ------------------------------------------------------------------------

func test_recording_changes_nothing_in_500_seeded_battles() -> void:
	var cases := []  # [state, crown ids, clans ids, ground, ruler factions]
	var plain := Balance.new_state()
	for m in Balance.matchups(plain):
		for g in Balance.GROUNDS:
			cases.append([plain, m.crown, m.clans, g, []])
	# The M2 builds: every preset pair with both rulers in the field, and the battle mandates no preset
	# takes (Feast of Victory, Drilled Ranks with Iron Discipline on the Crown).
	var states := []
	for cp in ["warrior_king", "iron_crown", "regents_court"]:
		for bp in ["beast_god_unbound", "clan_moot", "blood_of_the_fang"]:
			states.append(Balance.new_state_presets({CROWN: cp, CLANS: bp}))
	states.append(Balance.new_state_with({CROWN: ["drilled_ranks", "iron_discipline"], CLANS: ["blood_frenzy", "feast_of_victory"]},
		{CROWN: ["aurel_king", 5], CLANS: ["thornmane_avatar", 4]}))
	states.append(Balance.new_state_with({CROWN: ["veteran_levies", "royal_armories"], CLANS: ["feast_of_victory", "iron_discipline"]},
		{CROWN: ["ever_regent", 4], CLANS: ["fang_chieftain", 4]}))
	for st in states:
		assert_true(st != null, "the ruler state sets up")
		if st == null:
			return
		var start: Dictionary = Balance.matchups(st)[0]
		var big: Dictionary = Balance.matchups(st).filter(func(m): return m.name == "Commander + mixed, 125 gold")[0]
		for g in [Balance.ground("open"), Balance.ground("forest_crown"), Balance.ground("fort_clans"), Balance.ground("hills_crown")]:
			cases.append([st, start.crown, start.clans, g, [CROWN, CLANS]])
			cases.append([st, big.crown, big.clans, g, [CROWN, CLANS]])
	var fought := 0
	var logged_feasts := 0
	var held := 0
	var sd := 0
	while fought < 500:
		for c in cases:
			sd += 1
			var off := _harness_battle(c[0], c[1], c[2], c[3], sd, c[4], false)
			var on := _harness_battle(c[0], c[1], c[2], c[3], sd, c[4], true)
			var what := "battle %d (%s vs %s, %s)" % [sd, str(c[1]), str(c[2]), c[3].key]
			assert_true(off.log.is_empty() and not on.log.is_empty(), "%s: only the recorded battle has a log" % what)
			assert_true(on.result.report == off.result.report, "%s: the same report" % what)
			assert_eq(on.result.winner, off.result.winner, "%s: the same winner" % what)
			assert_true(on.armies == off.armies, "%s: the same armies after the losses" % what)
			assert_true(on.feast == off.feast, "%s: the same feast" % what)
			assert_eq(Serial.int64_to_str(on.rng), Serial.int64_to_str(off.rng), "%s: the same RNG state after the battle" % what)
			for k in ["strengths", "tie_break", "roll", "why"]:
				assert_true(on.result[k] == off.result[k], "%s: the same %s" % [what, k])
			if not off.feast.is_empty():
				logged_feasts += 1
			if on.log.events.any(func(e): return e.t == "morale" and e.result == "held"):
				held += 1
			fought += 1
			if not get_failures().is_empty() or fought >= 500:
				break
		if not get_failures().is_empty():
			break
	assert_true(fought >= 500, "500 battles fought (%d)" % fought)
	assert_true(held > 0, "some of them had Iron Discipline holding (%d)" % held)


func test_a_no_rulers_m1_battle_is_unchanged_and_logged() -> void:
	var m1 := _m1_turn()
	var battle: Dictionary = m1.battle
	assert_eq(battle.text, RulerBattles.M1_EVENT_TEXT, "the M1 battle line")
	assert_eq(battle.numbers.report.lines, RulerBattles.M1_LINES, "every M1 report line")
	var factors := ""
	for f in battle.numbers.report.all_factors:
		factors += "%s|%s|%s;" % [f.id, f.faction, str(f.impact)]
	assert_eq(factors, RulerBattles.M1_FACTORS, "every M1 factor and its worth")
	assert_eq(JSON.stringify(m1.result.new_state.to_dict()).sha256_text(), RulerBattles.M1_STATE_SHA, "the M1 state after the turn")
	assert_eq(Forecast.battle_odds(m1.before, CLANS, ["beasts-2"], "thornvale").text, RulerBattles.M1_ODDS, "the M1 odds")
	var lg: Dictionary = battle.numbers.log
	assert_eq([lg.id, lg.turn, lg.index, lg.kind, lg.provinces, lg.terrain, lg.defender], ["t1b0", 1, 0, "province", ["thornvale"], "forest", CROWN])
	_assert_checks(lg, battle.numbers.report, "the M1 battle")
	var aftermath: Dictionary = lg.events.back()
	assert_eq(aftermath.t, "aftermath")
	assert_eq(aftermath.destroyed_armies, ["kingdom-1"])
	assert_eq(aftermath.text, battle.numbers.report.aftermath, "the aftermath sentence is the report's")
	# Aurel Crown routed with its Knight Captain standing: the fighter it lost with its army.
	var standing: Array = aftermath.lost.map(func(fid): return lg.fighters[fid].name)
	assert_eq(standing, ["Knight Captain"], "the fighter lost with the routed army")
	assert_eq(aftermath.fallen_rulers, [])


func test_recording_is_off_unless_asked_and_the_stub_gives_no_log() -> void:
	var s := GameState.new(3)
	var a: Army = s.armies[0]
	var d: Army = s.armies[1]
	assert_false(AutoBattleResolver.resolve(a, d, s.find_province("rivermarch"), SeededRNG.new(1), s).has("log"), "resolve() doesn't record by default")
	var rec := AutoBattleResolver.resolve(a, d, s.find_province("rivermarch"), SeededRNG.new(1), s, true)
	assert_true(rec.has("log") and not rec.log.is_empty(), "resolve(..., true) records")
	var sides := [{"faction": CLANS, "armies": [s.armies[1] if s.armies[1].owner == CLANS else s.armies[0]]},
		{"faction": CROWN, "armies": [s.armies[0] if s.armies[0].owner == CROWN else s.armies[1]]}]
	assert_false(AutoBattleResolver.fight(sides, {"kind": "border", "defender": ""}, SeededRNG.new(2)).has("log"), "fight() doesn't record by default")
	# The test resolver gives no log, so its battle events carry none.
	var m1 := _m1_turn()
	var st: GameState = m1.before
	var stub := TurnResolver.resolve(st, {CLANS: [MoveOrder.new("beasts-2", "thornvale")]}, 4242, StubBattleResolver.new())
	var ev: Dictionary = stub.events.filter(func(e): return e.type == "battle")[0]
	assert_false(ev.numbers.has("log"), "a stub battle has no log")


# --- the schema ---------------------------------------------------------------------------------------

func test_the_log_has_exactly_the_schema_keys() -> void:
	var seen := {}
	for name in Scenarios.NAMES:
		var fx := _fixture(name)
		if fx.is_empty():
			continue
		var lg: Dictionary = BattleLog.from_json(JSON.stringify(fx.log, "", false)).log
		assert_eq(lg.keys(), TOP_KEYS, "%s: the top level" % name)
		assert_eq(lg.rng.keys(), ["seed", "before", "after"], "%s: rng" % name)
		for s in lg.sides:
			assert_eq(s.keys(), SIDE_KEYS, "%s: a side" % name)
			assert_eq(s.start_morale.keys(), ["morale", "parts", "break_pct"], "%s: start_morale" % name)
			for a in s.armies:
				assert_eq(a.keys(), ["id", "label"], "%s: an army" % name)
		for f in lg.fighters:
			assert_eq(f.keys(), FIGHTER_KEYS, "%s: a fighter" % name)
			if f.role == "ruler":
				assert_eq(f.ruler.keys(), ["id", "kept_power", "rank", "dread"], "%s: a ruler fighter" % name)
			else:
				assert_eq(f.ruler, {}, "%s: not a ruler" % name)
		for e in lg.events:
			assert_eq(e.keys(), EVENT_KEYS[e.t], "%s: a %s event" % [name, e.t])
			seen[e.t] = true
			if e.t == "attack":
				assert_eq(e.attack.keys(), ["value", "base", "parts"])
				assert_eq(e.defense.keys(), ["value", "base", "parts"])
	assert_eq(seen.size(), EVENT_KEYS.size(), "the fixtures hold every kind of event: %s" % str(seen.keys()))


# --- the fixtures -------------------------------------------------------------------------------------

func test_every_fixture_is_current_shows_its_point_and_passes_every_check() -> void:
	assert_true(Scenarios.NAMES.size() >= 10, "at least 10 fixtures")
	for name in Scenarios.NAMES:
		var fx := _fixture(name)
		if fx.is_empty():
			continue
		assert_eq(fx.get("what", ""), Scenarios.WHAT[name], "%s: its description" % name)
		var stored := BattleLog.from_json(JSON.stringify(fx.log, "", false))
		assert_eq(stored.errors, [], "%s: the stored log reads back" % name)
		var r := Scenarios.run(name, int(fx.seed))
		assert_eq(r.errors, [], "%s: fights" % name)
		if not r.errors.is_empty():
			continue
		assert_eq(_canon(r.log), _canon(fx.log), "%s: the stored log is the one the scenario fights now (rerun tools/battle_log.gd --fixtures after a rules change)" % name)
		assert_eq(_canon(r.report), _canon(fx.report), "%s: the stored report too" % name)
		assert_true(Scenarios.shows(name, r.log, r.report), "%s: shows what it is for" % name)
		_assert_checks(r.log, r.report, name)
		_assert_checks(stored.log, fx.report, "%s as stored" % name)


func test_the_biggest_fixture_fits_the_size_budget() -> void:
	var fx := _fixture("biggest")
	if fx.is_empty():
		return
	var lg: Dictionary = BattleLog.from_json(JSON.stringify(fx.log, "", false)).log
	var bytes := BattleLog.to_json(lg).to_utf8_buffer().size()
	assert_eq(lg.fighters.size(), 277, "the biggest measured battle's fighters")
	assert_eq(_attacks(lg).size(), 898, "and attacks")
	assert_eq(int(fx.report.rounds_fought), 4, "and rounds")
	assert_true(bytes <= SIZE_BUDGET, "its log is %d bytes of JSON, within %d" % [bytes, SIZE_BUDGET])
	assert_true(lg.events.size() < BattleLog.MAX_EVENTS / 5, "far below the cap")


func test_recording_adds_at_most_a_quarter_to_the_biggest_battle() -> void:
	# Wall-clock, so the budget is checked only with --perf (test_case.gd's assert_perf); without it the
	# biggest battle is still fought once each way inside its real turn. The reading is a ratio within one
	# call (off and on interleaved, alternating which goes first) of the fastest run of each, since timing
	# on a shared machine only ever runs slow; the best of up to three tries counts.
	var ratio := INF
	var best := {}
	for attempt in perf_runs(3):
		var t := Scenarios.time_recording("biggest", perf_runs(5))
		assert_true(float(t.off_min) > 0.0 and float(t.on_min) > 0.0, "the battle was fought with recording off and on")
		if float(t.off_min) <= 0.0:
			return
		var r := float(t.on_min) / float(t.off_min)
		if r < ratio:
			ratio = r
			best = t
		if ratio <= TIME_BUDGET:
			break
	assert_perf(ratio <= TIME_BUDGET, "recording adds %.0f%% (off %.1f ms, on %.1f ms; budget +%.0f%%)" % [100.0 * (ratio - 1.0),
		best.off_min, best.on_min, 100.0 * (TIME_BUDGET - 1.0)])


func test_a_lowered_cap_truncates_the_log_and_changes_nothing() -> void:
	var d := Scenarios.direct("dread_feast_frenzy")
	var sd := Scenarios.fixture_seed("dread_feast_frenzy")
	var off_rng := SeededRNG.new(sd)
	var off := AutoBattleResolver.fight(d.sides, d.ctx, off_rng)
	var ctx: Dictionary = d.ctx.duplicate()
	ctx["max_events"] = 20
	var on_rng := SeededRNG.new(sd)
	var on := AutoBattleResolver.fight(d.sides, ctx, on_rng, true)
	assert_true(on.log.truncated, "the log is marked cut short")
	assert_eq(on.log.events.size(), 20, "recording stopped at the cap")
	assert_true(on.result.report == off.result.report, "the report is unchanged")
	assert_eq(on.result.winner, off.result.winner)
	assert_eq(on_rng.get_state(), off_rng.get_state(), "the RNG state is unchanged")
	assert_eq(BattleLog.validate(on.log), [], "a cut-short log is still well formed")
	assert_eq(BattleLog.verify_draws(on.log).size(), 1, "but its rolls can't all be checked")
	assert_true(String(BattleLog.verify_draws(on.log)[0]).contains("cut short"))
	# Through resolve_battle (the feast is past the cap too) and TurnResolver (no aftermath is added).
	var setup := Scenarios._setup("dread_feast_frenzy")
	var full := TurnResolver.resolve(setup.state, setup.orders, sd, AutoBattleResolver.new())
	var capped_resolver := CappedResolver.new()
	var capped := TurnResolver.resolve(setup.state, setup.orders, sd, capped_resolver)
	var a: Dictionary = full.events.filter(func(e): return e.type == "battle")[0]
	var b: Dictionary = capped.events.filter(func(e): return e.type == "battle")[0]
	assert_true(b.numbers.log.truncated and b.numbers.log.events.size() == 20, "the battle event's log is cut short")
	assert_eq(b.text, a.text, "the battle event is otherwise the same")
	assert_eq(JSON.stringify(capped.new_state.to_dict()), JSON.stringify(full.new_state.to_dict()), "and so is the state after the turn")


class CappedResolver extends AutoBattleResolver:
	func resolve_battle(battle: Dictionary, rng: SeededRNG) -> Dictionary:
		var b := battle.duplicate()
		b["max_events"] = 20
		return super.resolve_battle(b, rng)


# --- verify_draws and validate catch tampering --------------------------------------------------------

func test_verify_draws_passes_and_catches_tampering() -> void:
	var fx := _fixture("round_cap_defender")
	var lg: Dictionary = BattleLog.from_json(JSON.stringify(fx.log, "", false)).log
	assert_eq(BattleLog.verify_draws(lg), [], "the untouched log")
	var first := BattleLog.find_event(lg, "attack")
	var tampered := []
	var t1: Dictionary = lg.duplicate(true)  # a different hit roll on the same side of the chance
	var e1: Dictionary = t1.events[first]
	e1.roll = int(e1.roll) % 100 + 1 if (int(e1.roll) % 100 + 1 <= int(e1.chance)) == bool(e1.hit) else (int(e1.roll) + 2) % 100 + 1
	e1.hit = int(e1.roll) <= int(e1.chance)
	tampered.append(["a hit roll", t1])
	var t2: Dictionary = lg.duplicate(true)  # a target pick changed (the only target: pool 1 -> 2)
	t2.events[first].pool = 2
	t2.events[first].pick = 1
	tampered.append(["a target roll", t2])
	var t3: Dictionary = lg.duplicate(true)
	t3.rng.before = Serial.int64_to_str(Serial.to_int(t3.rng.before) + 1)
	tampered.append(["the starting state", t3])
	var t4: Dictionary = lg.duplicate(true)
	t4.rng.after = Serial.int64_to_str(Serial.to_int(t4.rng.after) ^ 1)
	tampered.append(["the final state", t4])
	var t5: Dictionary = lg.duplicate(true)
	t5.events.remove_at(first)
	tampered.append(["a missing attack", t5])
	for t in tampered:
		var reasons := BattleLog.verify_draws(t[1])
		assert_eq(reasons.size(), 1, "tampering with %s is caught: %s" % [t[0], str(reasons)])
	# validate catches numbers that don't follow the rules.
	var v1: Dictionary = lg.duplicate(true)
	v1.events[first].damage = int(v1.events[first].damage) + 1
	assert_true(str(BattleLog.validate(v1)).contains("damage"), "a wrong damage")
	var v2: Dictionary = lg.duplicate(true)
	v2.events[first].chance = int(v2.events[first].chance) - 1
	assert_false(BattleLog.validate(v2).is_empty(), "a wrong chance")
	var v3: Dictionary = lg.duplicate(true)
	v3.events[first].to = 99
	assert_true(str(BattleLog.validate(v3)).contains("99"), "a fighter that isn't there")
	# And the report cross-check catches a log that doesn't match its report.
	var c1: Dictionary = lg.duplicate(true)
	var w := BattleLog.find_event(c1, "wound")
	c1.events[w].to = int(c1.events[w].to) + 1
	assert_false(BattleLog.cross_check(c1, fx.report).is_empty(), "a wound that doesn't match the hits")


func test_validate_explains_malformed_logs_in_plain_words() -> void:
	assert_eq(BattleLog.validate("text"), ["This is not a battle log: it should be a group of named values."])
	assert_true(String(BattleLog.validate({"v": 2})[0]).contains("version 2"))
	var reasons := BattleLog.validate({"v": 1})
	assert_false(reasons.is_empty())
	for r in reasons:
		assert_false(String(r).contains("Nil") or String(r).contains("null"), "plain words: %s" % r)
	assert_true(BattleLog.from_json("{nope").errors.size() == 1, "unreadable JSON gives one reason")


# --- regenerate, determinism and the game record ------------------------------------------------------

func test_regenerate_rebuilds_every_battle_of_ai_games_with_rulers() -> void:
	var battles := 0
	var rulers := 0
	for game_seed in range(1, AUTOPLAY_GAMES + 1):
		var g := Games.play(game_seed, 60, Games.seats_for(game_seed))
		assert_eq(g.errors, [], "game %d plays" % game_seed)
		var round_trip = JSON.parse_string(JSON.stringify(g.record))
		var text := JSON.stringify(g.record)
		assert_false(text.contains("\"events\"") or text.contains("\"fighters\"") or text.contains("\"report\""), "game %d: the record holds no logs or reports" % game_seed)
		for entry in g.record.history:
			assert_eq(entry.keys(), ["turn", "seed", "orders"], "game %d: a history entry is only the turn, seed and orders" % game_seed)
		for b in g.battles:
			battles += 1
			if b.log.fighters.any(func(f): return f.role == "ruler"):
				rulers += 1
			var what := "game %d, turn %d, battle %d" % [game_seed, b.turn, b.index]
			assert_eq(b.log.id, "t%db%d" % [b.turn, b.index], "%s: its id" % what)
			_assert_checks(b.log, b.report, what)
			var regen := BattleLog.regenerate(round_trip, b.turn, b.index)
			assert_eq(regen.errors, [], "%s: regenerates" % what)
			assert_eq(BattleLog.to_json(regen.log), BattleLog.to_json(b.log), "%s: byte for byte, from the record after a JSON round trip" % what)
			assert_true(regen.report == b.report, "%s: with the same report" % what)
	assert_true(battles >= 20, "the games had battles (%d)" % battles)
	assert_true(rulers > 0, "rulers fought in some of them (%d)" % rulers)


func test_regenerate_says_why_when_there_is_no_such_battle() -> void:
	var g := Games.play(1, 60)
	var rec: Dictionary = g.record
	var turns: int = rec.history.size()
	assert_eq(BattleLog.regenerate(rec, turns + 1, 0).errors, ["This game record has no turn %d. It has %d turns." % [turns + 1, turns]])
	assert_eq(BattleLog.regenerate(rec, 0, 0).errors[0], "This game record has no turn 0. It has %d turns." % turns)
	assert_eq(BattleLog.regenerate(rec, 1, 0).errors, ["Turn 1 had 0 battles, so there is no battle 1."])
	var b: Dictionary = g.battles[0]
	assert_eq(BattleLog.regenerate(rec, b.turn, 5).errors[0].begins_with("Turn %d had " % b.turn), true)
	assert_eq(BattleLog.regenerate({"nope": 1}, 1, 0).errors, ["This is not a game record: it has no list of turns."])


func test_the_same_state_orders_and_seed_give_byte_identical_logs() -> void:
	var setup := Scenarios._setup("king_falls_wins")
	var a := TurnResolver.resolve(setup.state, setup.orders, 77, AutoBattleResolver.new())
	var b := TurnResolver.resolve(setup.state, setup.orders, 77, AutoBattleResolver.new())
	var la: Dictionary = a.events.filter(func(e): return e.type == "battle")[0].numbers.log
	var lb: Dictionary = b.events.filter(func(e): return e.type == "battle")[0].numbers.log
	assert_eq(BattleLog.to_json(la), BattleLog.to_json(lb))
	var c := TurnResolver.resolve(setup.state, setup.orders, 78, AutoBattleResolver.new())
	assert_ne(BattleLog.to_json(c.events.filter(func(e): return e.type == "battle")[0].numbers.log), BattleLog.to_json(la), "another seed, another battle")


func test_logs_ride_with_the_last_turn_only_and_never_in_the_record() -> void:
	var setup := Scenarios._setup("starting_plains")
	var session := GameSession.new(setup.state, [CROWN, CLANS], 5)
	assert_eq(session.end_turn(), "")
	assert_eq(session.acknowledge_handoff(), "")
	assert_eq(session.queue_move("beasts-2", "rivermarch"), "")
	assert_eq(session.end_turn(), "")
	var battles := session.battle_events()
	assert_eq(battles.size(), 1, "the turn had its battle")
	assert_true(battles[0].numbers.has("log") and battles[0].numbers.has("report"), "its log rides beside its report")
	assert_eq(battles[0].numbers.log.id, "t1b0")
	_assert_checks(battles[0].numbers.log, battles[0].numbers.report, "the session's battle")
	var report_events: Array = session.turn_report().events
	assert_true(report_events.any(func(e): return e.get("numbers", {}).has("log")), "the turn report has it")
	assert_false(BattleLog.without_logs(report_events).any(func(e): return e.get("numbers", {}).has("log")), "without_logs takes it out")
	assert_true(session.turn_report().events.any(func(e): return e.get("numbers", {}).has("log")), "without that copy changing the report")
	for text in [JSON.stringify(session.record()), JSON.stringify(session.history())]:
		assert_false(text.contains("\"events\"") or text.contains("\"fighters\"") or text.contains("\"log\""), "no log in the record or history")
	# The next turn's report replaces it: the old log goes with the old report.
	assert_eq(session.acknowledge_handoff(), "")
	assert_eq(session.end_turn(), "")
	assert_eq(session.acknowledge_handoff(), "")
	assert_eq(session.end_turn(), "")
	assert_false(session.turn_report().events.any(func(e): return e.get("numbers", {}).has("log")), "the next turn has no battle and no log")
	# And replay(…, up_to_turn) stops after that turn, with its events.
	var rec := session.record()
	var first := GameSession.replay(rec, null, 1)
	assert_eq(first.state.current_turn, 1, "up_to_turn 1 stops after turn 1")
	assert_eq(first.events.filter(func(e): return e.type == "battle").size(), 1, "with turn 1's battle")
	assert_eq(JSON.stringify(GameSession.replay(rec, null, 2).state.to_dict()), JSON.stringify(GameSession.replay(rec).state.to_dict()),
		"up_to_turn 2 of 2 is the whole game")


# --- the timeline -------------------------------------------------------------------------------------

func test_the_timeline_folds_the_log_into_states() -> void:
	for name in ["starting_plains", "iron_discipline", "king_falls_wins", "dread_feast_frenzy", "border"]:
		var fx := _fixture(name)
		if fx.is_empty():
			continue
		var lg: Dictionary = BattleLog.from_json(JSON.stringify(fx.log, "", false)).log
		var tl := BattleTimeline.build(lg)
		var n: int = lg.events.size()
		assert_eq(tl.size(), n)
		var s0 := tl.state_at(0)
		assert_eq([s0.beat, s0.round, s0.winner], ["deploy", 0, -1], "%s: before the battle" % name)
		# Every state from the keyframes equals the one folded event by event.
		var state := BattleTimeline.initial_state(lg)
		for i in n + 1:
			if not (tl.state_at(i) == state):
				fail("%s: state_at(%d) differs from folding the events one by one" % [name, i])
				break
			if i < n:
				BattleTimeline.apply(lg, state, i)
		var final := tl.final_state()
		assert_eq(final.beat, "end")
		assert_eq(final.winner, lg.events[BattleLog.find_event(lg, "end")].winner)
		var hp := BattleLog.final_hp(lg)
		for fid in hp.size():
			assert_eq(final.fighters[fid].hp, hp[fid], "%s: fighter %d's hp" % [name, fid])
			assert_eq(final.fighters[fid].pending, 0)
		for si in lg.sides.size():
			assert_eq(final.sides[si].pending, 0, "%s: nothing pending at the end" % name)
		# Round starts and the display order: every attack of the round, alternating sides.
		for r in range(1, tl.rounds() + 1):
			var start := tl.round_start(r)
			assert_eq(lg.events[start].t, "round")
			assert_eq(int(lg.events[start].n), r)
			var order := tl.display_order(r)
			var attacks := []
			for i in n:
				if lg.events[i].t == "attack" and int(lg.events[i].n) == r:
					attacks.append(i)
			var sorted := order.duplicate()
			sorted.sort()
			assert_eq(sorted, attacks, "%s round %d: every attack once" % [name, r])
			if order.size() >= 2:
				var s_a := int(lg.fighters[lg.events[order[0]].by].side)
				var s_b := int(lg.fighters[lg.events[order[1]].by].side)
				assert_true(s_a == 0 and (s_b == 1 or attacks.size() == order.size()), "%s round %d: side 0 first, then side 1" % [name, r])
		assert_eq(tl.round_start(99), -1)


func test_statuses_follow_the_hp_and_the_header() -> void:
	var fx := _fixture("dread_feast_frenzy")
	if fx.is_empty():
		return
	var lg: Dictionary = BattleLog.from_json(JSON.stringify(fx.log, "", false)).log
	var tl := BattleTimeline.build(lg)
	var avatar := -1
	var warchief := -1
	var tusker := -1
	for f in lg.fighters:
		if f.role == "ruler" and lg.sides[int(f.side)].faction == CLANS:
			avatar = int(f.id)
		if f.name == "Warchief":
			warchief = int(f.id)
		if f.name == "Tuskers" and tusker < 0:
			tusker = int(f.id)
	var s0 := tl.state_at(0)
	assert_true(tl.statuses(s0, avatar).auras.has("ruler") and tl.statuses(s0, avatar).auras.has("Dread"), "the avatar's auras")
	assert_eq(tl.statuses(s0, warchief).auras, ["commander"], "the Warchief's")
	assert_true(tl.statuses(s0, warchief).shielded, "the Warchief stands behind its units")
	assert_true(tl.statuses(s0, tusker).pack_leader, "the Warchief drives the pack")
	assert_false(tl.statuses(s0, tusker).berserk or tl.statuses(s0, tusker).blood_frenzy, "a Tusker at full hp isn't berserk or frenzied")
	# Once wounded, Berserk and Blood Frenzy are active.
	var wounded := -1
	for i in lg.events.size():
		var e: Dictionary = lg.events[i]
		if e.t == "wound" and int(e.f) == tusker and int(e.to) > 0:
			wounded = i + 1
			break
	if wounded > 0:
		var st := tl.statuses(tl.state_at(wounded), tusker)
		assert_true(st.berserk and st.blood_frenzy, "a wounded Tusker is berserk and frenzied")


# --- JSON ---------------------------------------------------------------------------------------------

func test_the_json_round_trip_is_exact() -> void:
	for name in Scenarios.NAMES:
		var fx := _fixture(name)
		if fx.is_empty():
			continue
		var r := Scenarios.run(name, int(fx.seed))
		var back := BattleLog.from_json(BattleLog.to_json(r.log))
		assert_eq(back.errors, [], name)
		assert_true(back.log == r.log, "%s: from_json(to_json(log)) is the log, value for value and type for type" % name)
		assert_eq(BattleLog.to_json(back.log), BattleLog.to_json(r.log), "%s: and byte for byte" % name)
