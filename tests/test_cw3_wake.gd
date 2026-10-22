extends "res://tests/test_case.gd"
## CW-3 (#254, design/CANDLEWAKE.md §3): the Wake. A province the Candlewake hold wakes through Sitting Up, the Wake-Line and
## Deep Wake on the end clock E; a lost mark lingers as a cold wake (a scar) 2 turns a stage, then fades; retaking a cold wake
## relights it at once; the Wake-Line and Deep Wake are harbours for Wick and pay their owner 1 gold less; Deep Wake raises a
## Wickwarden every 4 turns. Every number comes from MarkData's row. The turn numbers are the state's current_turn, as §3.3's
## worked example counts them (E = current_turn + 1; the screens show each turn as current_turn + 1 too).

const F := preload("res://tests/siege_fixtures.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const WAKE := "candlewake"


func _game(flags: Dictionary = {}, game_seed: int = 23) -> GameState:
	var errors := []
	var s := GameState.create(game_seed, [CROWN, WAKE], flags, {}, errors)
	assert_eq(errors, [])
	return s


func _copy(s: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))


## The wake step of turn `turn` (E = turn + 1), with `owners` {province id: owner} changed during it. Its events.
func _wake(s: GameState, turn: int, owners: Dictionary = {}) -> Array:
	s.current_turn = turn
	var start := _copy(s)
	for pid in owners:
		s.find_province(pid).owner = String(owners[pid])
	var events := []
	MarkRules.wake_step(s, events, start)
	return events


func _types(events: Array) -> Array:
	return events.map(func(e): return String(e.type))


func _row() -> Dictionary:
	return MarkData.row(WAKE)


func _held(stage: int) -> int:
	return int(MarkData.stage(WAKE, stage).held)


## The Wake's income part at `pid` (0 when it has none).
func _wake_gold(s: GameState, pid: String) -> int:
	var gold := 0
	for m in RulerRules.province_income_parts(s, pid).mods:
		if String(m.key) == MarkRules.INCOME_KEY:
			gold += int(m.value)
	return gold


## Puts `entry` at `pid`, and gives `pid` to `owner` unless it is "".
func _put(s: GameState, pid: String, owner: String, entry: Dictionary) -> void:
	if not owner.is_empty():
		s.find_province(pid).owner = owner
	s.marks[pid] = entry


## A regular Candlewake army `id` at `pid` with one Wickwarden, at `flame`.
func _army(s: GameState, id: String, pid: String, flame: int) -> Army:
	var a := Army.new()
	a.id = id
	a.owner = WAKE
	a.location = pid
	a.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(WAKE), "wickwardens"), WAKE))
	a.flame = flame
	s.armies.append(a)
	return a


## The first turn at whose end a mark held since `since` raises the dead (§3.6: held = Deep Wake's threshold + every).
func _first_rising(since: int) -> int:
	return since + MarkData.risen_threshold(WAKE) + int(_row().risen.every) - 1


# --- the capital, and the clock (§3.1, §3.3) ---------------------------------------------------------

func test_the_capital_is_deep_wake_from_the_start_and_crown_clans_games_have_no_marks() -> void:
	for flags in [{}, {"sieges": true, "fog": true, "independents": true}]:
		var s := _game(flags)
		var cap := s.find_faction(WAKE).capital
		assert_eq(s.marks, {cap: {"mark": {"faction": WAKE, "since_turn": int(_row().capital)}}}, "%s" % [flags])
		assert_eq(MarkRules.stage_now(s, cap), MarkData.stage_count(WAKE), "Deep Wake from the start")
		assert_true(MarkRules.harbour(s, WAKE, cap))
	var legacy := GameState.create(23, [CROWN, CLANS], {}, {}, [])
	assert_true(legacy.marks.is_empty() and not legacy.to_dict().has("marks"), "a Crown–Clans game saves as before")


func test_the_worked_example() -> void:
	# §3.3: the Candlewake take Thornvale during turn 4 (E = 5): since_turn 5, Sitting Up, then the Wake-Line at the end of
	# turn 7 (a harbour, 1 gold less) and Deep Wake at the end of turn 10.
	var s := _game()
	var pid := "thornvale"
	var base := s.find_province(pid).income
	assert_eq(_wake(s, 4, {pid: WAKE}), [], "a fresh mark sits up without a word: the capture line says it")
	assert_eq(s.marks[pid], {"mark": {"faction": WAKE, "since_turn": 5}})
	for row in [[4, 1, false], [5, 1, false], [6, 1, false], [7, 2, true], [10, 3, true]]:
		s.current_turn = int(row[0])
		var stage := int(row[1])
		assert_eq(MarkRules.stage_at(s, pid, MarkRules.end_clock(s)), stage, "end of turn %d: the stage" % row[0])
		assert_eq(MarkRules.harbour(s, WAKE, pid), bool(row[2]), "end of turn %d: a harbour in this Wick step" % row[0])
		var gold := int(MarkData.stage(WAKE, stage).gold)
		assert_eq(_wake_gold(s, pid), gold, "end of turn %d: the Wake's gold" % row[0])
		assert_eq(int(TurnResolver.income_of(s, WAKE).by_province[pid]), base + gold, "end of turn %d: what it pays" % row[0])
	# The Crown take it during turn 8 (E = 9): a cold wake at the Wake-Line until 13, a harbour at E 9 to 12, gone at 13.
	var events := _wake(s, 8, {pid: CROWN})
	assert_eq(_types(events), ["scar_formed"])
	assert_eq(s.marks[pid], {"scar": {"faction": WAKE, "stage": 2, "until_turn": 13}})
	assert_eq(_wake_gold(s, pid), 0, "the Crown pay no Wake")
	for turn in [8, 9, 10, 11]:
		s.current_turn = turn
		assert_true(MarkRules.harbour(s, WAKE, pid), "end of turn %d: the cold wake shelters" % turn)
	s.current_turn = 12
	assert_false(MarkRules.harbour(s, WAKE, pid), "end of turn 12: it has faded")
	assert_eq(_wake(s, 12), [])
	assert_false(s.marks.has(pid), "the wake step of turn 12 (E = 13) removes it")


# --- the cold wake (§3.3) ----------------------------------------------------------------------------

func test_a_lost_mark_scars_at_the_stage_it_had_at_the_last_wake_step() -> void:
	# Lost on the turn it would have grown, the scar keeps the stage it had, not the one it would have reached.
	for stage in range(1, MarkData.stage_count(WAKE)):
		var s := _game()
		var e := 9
		s.find_province("thornvale").owner = WAKE
		s.marks["thornvale"] = {"mark": {"faction": WAKE, "since_turn": e - _held(stage + 1)}}
		_wake(s, e - 1, {"thornvale": CROWN})
		assert_eq(int(s.marks.thornvale.scar.stage), stage, "held %d at the last wake step" % (_held(stage + 1) - 1))
		assert_eq(int(s.marks.thornvale.scar.until_turn), e + int(_row().scar_turns) * stage)


func test_retaking_a_cold_wake_relights_it_at_once_without_refreshing_its_time() -> void:
	var s := _game()
	s.find_province("thornvale").owner = CROWN
	s.marks["thornvale"] = {"scar": {"faction": WAKE, "stage": 2, "until_turn": 13}}
	var events := _wake(s, 10, {"thornvale": WAKE})
	assert_eq(_types(events), ["scar_consumed"], "it relights, and says nothing else")
	assert_eq(s.marks.thornvale, {"mark": {"faction": WAKE, "since_turn": 11 - _held(2)}})
	assert_eq(MarkRules.stage_at(s, "thornvale", 11), 2, "the Wake-Line at once")
	assert_true(MarkRules.harbour(s, WAKE, "thornvale"), "a harbour that same Wick step")


func test_a_cold_wake_fades_before_it_could_be_retaken() -> void:
	# A wake step with E >= until_turn removes the scar first: retaken at that very step, the mark starts fresh.
	var s := _game()
	s.find_province("thornvale").owner = CROWN
	s.marks["thornvale"] = {"scar": {"faction": WAKE, "stage": 2, "until_turn": 13}}
	assert_eq(_wake(s, 12, {"thornvale": WAKE}), [])
	assert_eq(s.marks.thornvale, {"mark": {"faction": WAKE, "since_turn": 13}})


func test_the_capital_falls_to_a_deep_scar_and_relights_deep() -> void:
	var s := _game()
	var cap := s.find_faction(WAKE).capital
	var deep := MarkData.stage_count(WAKE)
	_wake(s, 5, {cap: CROWN})
	assert_eq(s.marks[cap], {"scar": {"faction": WAKE, "stage": deep, "until_turn": 6 + int(_row().scar_turns) * deep}})
	_wake(s, 7, {cap: WAKE})
	assert_eq(MarkRules.stage_at(s, cap, 8), deep, "Deep Wake again at once")
	_wake(s, 8, {cap: CROWN})
	_wake(s, 9 + int(_row().scar_turns) * deep - 1)
	assert_false(s.marks.has(cap), "and the second scar fades in its own time")


func test_each_stage_is_said_once_when_it_is_reached() -> void:
	var s := _game()
	_wake(s, 4, {"thornvale": WAKE})
	var said := []
	for turn in range(5, 12):
		for e in _wake(s, turn):
			if String(e.type) == "mark_stage" and String(e.numbers.province) == "thornvale":
				said.append([turn, int(e.numbers.stage), String(e.text)])
	assert_eq(said.map(func(x): return [x[0], x[1]]), [[7, 2], [10, 3]])
	assert_eq(String(said[0][2]), "Thornvale wakes: the Wake-Line.")


func test_ownership_changes_from_the_capture_phase_mark_the_land() -> void:
	# Through the turn: a Candlewake army that takes a free province marks it at E; an army that leaves its own land keeps it.
	var s := _game()
	var cap := s.find_faction(WAKE).capital
	var target: String = s.find_province(cap).neighbors.filter(func(pid): return s.find_province(pid).owner.is_empty())[0]
	var r := TurnResolver.resolve(s, {WAKE: [MoveOrder.new("candlewake-1", target)]}, 1, StubBattleResolver.new())
	var after: GameState = r.new_state
	assert_eq(after.find_province(target).owner, WAKE)
	assert_eq(after.marks[target], {"mark": {"faction": WAKE, "since_turn": MarkRules.end_clock(s)}})
	assert_true(after.marks.has(cap), "the capital keeps its mark")
	assert_true(after.validate([]), "and the game validates")


# --- the Risen (§3.6) -------------------------------------------------------------------------------------

func test_the_capital_raises_a_wickwarden_at_the_ends_of_turns_3_7_and_11() -> void:
	var s := _game()
	var risen := []
	for turn in range(0, 13):
		for e in _wake(s, turn):
			if String(e.type) == "risen":
				risen.append(turn)
	var first := _first_rising(int(_row().capital))
	var every := int(_row().risen.every)
	assert_eq(risen, [first, first + every, first + 2 * every])
	assert_eq(risen, [3, 7, 11], "§3.6's turns")


func test_the_risen_join_the_lowest_numbered_army_there_at_its_flame() -> void:
	# Armies 2 and 10 stand at the capital (by number: as text, "candlewake-10" sorts before "candlewake-2").
	var s := _game()
	var cap := s.find_faction(WAKE).capital
	for a in s.armies.filter(func(x): return x.owner == WAKE):
		a.location = "ebonpeak"
	var ten := _army(s, WAKE + "-10", cap, 1)
	var two := _army(s, WAKE + "-2", cap, 3)
	var events := _wake(s, _first_rising(int(_row().capital)))
	var risen: Array = events.filter(func(x): return String(x.type) == "risen")
	assert_eq(risen.size(), 1)
	assert_eq(String(risen[0].numbers.army), two.id, "the 2nd, the lowest number")
	assert_eq(two.units.size(), 1 + int(_row().risen.count), "the dead rose into it")
	assert_eq(two.flame, 3, "they rose in the wax: no cooling")
	assert_eq(ten.units.size(), 1)
	assert_true(String(risen[0].text).begins_with("At the Long Vigil the dead rose: one Wickwarden."), risen[0].text)
	assert_true(String(risen[0].text).contains("joined the Candlewake's 2nd"), risen[0].text)


func test_with_no_army_there_the_risen_form_one_lit_at_the_start_flame() -> void:
	for kindled in [false, true]:
		var builds := {WAKE: {"ruler": "half_death", "mandates": ["kindling"]}} if kindled else {}
		var errors := []
		var s := GameState.create(23, [CROWN, WAKE], {}, builds, errors)
		assert_eq(errors, [])
		var cap := s.find_faction(WAKE).capital
		for a in s.armies.filter(func(x): return x.owner == WAKE and x.ruler == null):
			a.location = "ebonpeak"
		var ruler := RulerRules.ruler_army(s, WAKE)
		if ruler != null:
			ruler.location = "ebonpeak"
		s.current_turn = _first_rising(int(_row().capital))
		var next := String(s.peek_army_ids(WAKE, 1)[0])
		var r := TurnResolver.resolve(s, {}, 1, StubBattleResolver.new())
		var raised: Army = r.new_state.find_army(next)
		assert_true(raised != null and raised.location == cap, "a new army at the capital")
		assert_eq(raised.units.map(func(u): return String(u.type.id)), [String(_row().risen.unit)])
		assert_eq(raised.flame, WickRules.start_flame(s, WAKE), "lit at the start flame (Deep Wake is a harbour: no idle loss)")
		var e: Dictionary = r.events.filter(func(x): return String(x.type) == "risen")[0]
		assert_true(String(e.text).contains("They form a new army: the Candlewake's"), e.text)
		assert_eq(String(e.text).contains("Kindling"), kindled, "the words say where a hotter start comes from: %s" % e.text)


func test_the_risen_are_their_owners_news_and_the_marks_are_everyones() -> void:
	var s := _game({"fog": true})
	var events := _wake(s, _first_rising(int(_row().capital)))
	var risen: Array = events.filter(func(x): return String(x.type) == "risen")
	assert_eq(risen.size(), 1)
	assert_true(FogData.AUDIENCE.has("risen"))
	assert_eq(FogRules.filter_events(risen, WAKE, s, s).size(), 1, "the owner hears it")
	assert_eq(FogRules.filter_events(risen, CROWN, s, s), [], "a rival sees the army only when it sees the province")
	assert_true(MarkRules.EVENT_TYPES.has("risen") and ChronicleModel.EVENT_TYPES.has("risen"))


# --- gold (§3.2) -----------------------------------------------------------------------------------------

func test_a_cut_off_wake_pays_its_owner_nothing_and_the_besiegers_the_base() -> void:
	var s := _game({"sieges": true})
	s.armies.clear()
	var garrison := F.army(s, [WAKE + "-1", WAKE, "stonegate", F.units("wickwardens", 4)])
	garrison.flame = 1
	s.armies.append(garrison)
	s.armies.append(F.army(s, [CROWN + "-1", CROWN, "thornvale", F.units("spearmen", 2)]))
	s.find_province("stonegate").owner = WAKE
	s.marks["stonegate"] = {"mark": {"faction": WAKE, "since_turn": 1 - _held(MarkData.stage_count(WAKE))}}
	var base := s.find_province("stonegate").income
	var r := F.resolve(s, {CROWN: [MoveOrder.new(CROWN + "-1", "stonegate")]})
	var ns: GameState = r.new_state
	assert_true(SiegeRules.is_cut_off(ns, "stonegate"), "cut off from the siege's second turn")
	assert_eq(_wake_gold(ns, "stonegate"), int(MarkData.stage(WAKE, MarkData.stage_count(WAKE)).gold), "the Wake's part is still there")
	assert_eq(int(TurnResolver.income_of(ns, WAKE).by_province.stonegate), 0, "the owner gets nothing from it")
	assert_eq(int(TurnResolver.income_of(ns, CROWN).by_province.stonegate), base, "the besiegers get its base income, Wake or no")


func test_the_breakdown_names_the_wake() -> void:
	var s := _game()
	s.current_turn = 3
	var cap := s.find_faction(WAKE).capital
	assert_false(Breakdown._modifier_rule(MarkRules.INCOME_KEY).is_empty(), "the Wake's part has its rule")
	var parts := RulerRules.province_income_parts(s, cap)
	var wake: Array = parts.mods.filter(func(m): return String(m.key) == MarkRules.INCOME_KEY)
	assert_eq(wake.size(), 1)
	assert_eq(String(wake[0].name), "Deep Wake", "named by its stage")


func test_the_orders_forecast_knows_the_wake_line_this_turn_reaches() -> void:
	# Held one turn short of the Wake-Line: this turn's wake step gets it there before the Wick step, so an army staying there
	# is told it keeps its flame.
	var s := _game()
	s.current_turn = 6
	s.find_province("thornvale").owner = WAKE
	s.marks["thornvale"] = {"mark": {"faction": WAKE, "since_turn": MarkRules.end_clock(s) - _held(2)}}
	assert_eq(MarkRules.stage_now(s, "thornvale"), 1, "Sitting Up as the land looks now")
	var a := s.find_army("candlewake-1")
	a.location = "thornvale"
	a.flame = 2
	var line := String(Forecast.wick(s, WAKE).filter(func(x): return String(x.army) == a.id)[0].text)
	assert_true(line.contains("is a harbour"), line)


# --- validation and saves --------------------------------------------------------------------------------

func test_bad_marks_are_refused_in_plain_words() -> void:
	var cases := [
		["a mark on land its faction doesn't hold", func(s: GameState): _put(s, "thornvale", "", {"mark": {"faction": WAKE, "since_turn": 1}}),
			"doesn't hold"],
		["a mark from a turn still to come", func(s: GameState): _put(s, "thornvale", WAKE, {"mark": {"faction": WAKE,
			"since_turn": MarkRules.end_clock(s) + 1}}), "still to come"],
		["a cold wake that has faded", func(s: GameState): _put(s, "thornvale", CROWN, {"scar": {"faction": WAKE, "stage": 1,
			"until_turn": MarkRules.end_clock(s) - 1}}), "has already faded"],
		["a mark and a cold wake of one faction", func(s: GameState): _put(s, s.find_faction(WAKE).capital, "", {"mark": {"faction": WAKE,
			"since_turn": int(_row().capital)}, "scar": {"faction": WAKE, "stage": 1, "until_turn": 9}}), "relights"],
	]
	for c in cases:
		var s := _game()
		c[1].call(s)
		var errors := []
		assert_false(s.validate(errors), "%s is refused" % c[0])
		assert_true(" ".join(errors).contains(String(c[2])), "%s: %s" % [c[0], errors])


func test_a_game_saved_between_turns_plays_on_as_if_uninterrupted() -> void:
	# The capital raises the dead, Thornvale grows to the Wake-Line and Deep Wake, and a cold wake at Highcrag fades.
	var s := _game()
	s.find_province("thornvale").owner = WAKE
	s.marks["thornvale"] = {"mark": {"faction": WAKE, "since_turn": 1}}
	s.find_province("highcrag").owner = CROWN
	s.marks["highcrag"] = {"scar": {"faction": WAKE, "stage": 1, "until_turn": 3}}
	assert_true(s.validate([]))
	var straight := s
	var saved := _copy(s)
	var lines_straight := []
	var lines_saved := []
	for turn in 12:
		var a := TurnResolver.resolve(straight, {}, turn + 1, StubBattleResolver.new())
		straight = a.new_state
		lines_straight.append_array(a.events.map(func(e): return "%s|%s" % [e.type, e.text]))
		var b := TurnResolver.resolve(saved, {}, turn + 1, StubBattleResolver.new())
		saved = _copy(b.new_state)
		lines_saved.append_array(b.events.map(func(e): return "%s|%s" % [e.type, e.text]))
	assert_eq(JSON.stringify(saved.to_dict()), JSON.stringify(straight.to_dict()), "the same game")
	assert_eq(lines_saved, lines_straight, "the same report")
	var types := lines_straight.map(func(x): return String(x).split("|")[0])
	for t in ["mark_stage", "risen"]:
		assert_true(types.has(t), "the run saw a %s" % t)
	assert_false(straight.marks.has("highcrag"), "the cold wake faded")


# --- the words (§3.4) ------------------------------------------------------------------------------------

func test_the_province_card_says_what_the_wake_does_and_when() -> void:
	var s := _game()
	s.find_province("thornvale").owner = WAKE
	s.marks["thornvale"] = {"mark": {"faction": WAKE, "since_turn": 1}}
	s.current_turn = 5  # held 4, as the land looks now
	var lines := MarkRules.province_text(s, "thornvale")
	assert_eq(lines.size(), 1)
	assert_eq(String(lines[0]), "The Wake-Line (held 4 turns): Candlewake armies keep their flame here. The living sit up all night: -1 gold. Deep Wake in %d turns." % (_held(3) - 4))
	var cap := s.find_faction(WAKE).capital
	var deep := " ".join(MarkRules.province_text(s, cap))
	assert_true(deep.contains("Deep Wake (held") and deep.contains("the dead rise here. Next Wickwarden in"), deep)
	s.find_province("rivermarch").owner = CROWN
	s.marks["rivermarch"] = {"scar": {"faction": WAKE, "stage": 2, "until_turn": 9}}
	assert_eq(" ".join(MarkRules.province_text(s, "rivermarch")), "A cold wake. The Candlewake held it to the Wake-Line; it fades in %d turns. Their armies still find harbour here, and if they retake it, it relights at once." % (9 - MarkRules.end_clock(s)))
	assert_eq(MarkRules.province_text(s, "westwatch"), [], "unmarked land says nothing")


func test_the_codex_explains_the_wake() -> void:
	for key in [MarkRules.CODEX, "marks_on_the_land"]:
		assert_true(RulesCodex.ENTRIES.has(key), "the codex has %s" % key)
	var text := RulesCodex.text(MarkRules.CODEX)
	for st in _row().stages:
		assert_true(text.contains(String(st.name)), "it names %s" % st.name)
	assert_true(text.contains("cold wake") and text.contains("relights") and text.contains("the dead rise"), text)
	assert_true(RulesCodex.text("marks_on_the_land").contains("other peoples"), "other marks are coming")
