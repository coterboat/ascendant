extends "res://tests/test_case.gd"
## #284 (QA-1): every sentence of the turn report starts with a capital, wherever it is built. A sentence that opens with a name
## written for running text ("the Aurel Crown", "the Crown's 3rd", "the Long Vigil", "the Ever-Regent") reads "The ...":
##   - the fog's rebuilt lines (FogRules.text_for, every FogData.TEXT template) and its synthetic ones (FogRules.synthetic_events);
##   - every report row (TurnReportText.rows and line), the resolver's own sentences among them, whose words stay as recorded;
##   - the needs-you lines (FortView.needs_you) and the Chronicle's cards (ChronicleModel).
## Only the first letter of a sentence changes, never a word.

const Fx := preload("res://tests/siege_fixtures.gd")
const Kit := preload("res://tests/fog_test_kit.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const WAKE := "candlewake"
## A sentence that starts with a lower-case letter: at the start of the text, or after ". ", "! " or "? ".
const LOWER_START := "(?:^|[.!?] +)[a-z]"


func _assert_capitals(text: String, where: String) -> void:
	assert_true(RegEx.create_from_string(LOWER_START).search(text) == null, "%s: every sentence starts with a capital: %s" % [where, text])


## A game of the Crown against the Candlewake, with `flags` its systems. The Candlewake's capital is the Long Vigil, a name written for
## running text.
func _wake_game(flags: Dictionary = {}) -> GameState:
	var errors := []
	var s := GameState.create(17, [CROWN, WAKE], flags, {}, errors)
	assert_eq(errors, [], "a Crown–Candlewake game builds")
	assert_true(s.find_province(_vigil(s)).name.begins_with("the "), "the Candlewake's capital is named for running text")
	return s


func _vigil(s: GameState) -> String:
	return s.find_faction(WAKE).capital


## The province's name as a sentence starts with it: "The Long Vigil".
func _start(s: GameState, pid: String) -> String:
	return RulerRules._cap(s.find_province(pid).name)


## A Crown army of `units` at the first neighbour of the Long Vigil, ready to march in.
func _crown_at_the_gates(s: GameState, units: Array) -> String:
	var id := s.new_army_id(CROWN)
	s.armies.append(Fx.army(s, [id, CROWN, String(s.find_province(_vigil(s)).neighbors[0]), units]))
	return id


# --- the helper -----------------------------------------------------------------------------------------

func test_cap_sentences_capitalises_each_sentence_start_and_nothing_else() -> void:
	assert_eq(RulerRules.cap_sentences("the Aurel Crown captured Stonegate. the Free Holds lost it."),
		"The Aurel Crown captured Stonegate. The Free Holds lost it.")
	assert_eq(RulerRules.cap_sentences("Gold: 17 -> 22. the Long Vigil paid nothing: it is cut off."),
		"Gold: 17 -> 22. The Long Vigil paid nothing: it is cut off.")
	for same in ["Stonegate fell to Aurel Crown: its army won the battle there; the Crown's 3rd lost no fighters.",
			"1-2 fighters of the Candlewake (about 5 hp).", ""]:
		assert_eq(RulerRules.cap_sentences(same), same, "a colon, a semicolon or a number starts no sentence")


# --- the fog's lines ------------------------------------------------------------------------------------

## The issue's line: a rival's Oath, rebuilt from public facts under fog, as the other seat's report reads it.
func test_a_rivals_oath_under_fog_starts_with_a_capital() -> void:
	var s := GameState.with_paths(8)
	s.setup_fog([])
	var oath := {"type": "oath_sworn", "phase": "research", "provinces": [], "factions": [CROWN], "armies": [], "cause": "research",
		"numbers": {"node": "crown_oath_dawn", "branch": "celestial_host", "closed": "living_iron", "turn": 6},
		"text": "The resolver's own words.", "codex": "oath"}
	var shown := FogRules.filter_events([oath], CLANS, s, s)
	var rebuilt: Array = shown.filter(func(e): return String(e.type) == "oath_sworn" and bool(e.get("rebuilt", false)))
	assert_eq(rebuilt.size(), 1, "the Clans read the Crown's Oath, rebuilt")
	if rebuilt.is_empty():
		return
	var opens := "The %s swore %s on turn 6: " % [s.find_faction(CROWN).faction_name, AscensionRules.node_ref("crown_oath_dawn")]
	assert_true(String(rebuilt[0].text).begins_with(opens), rebuilt[0].text)
	var lines: Array = TurnReportText.rows(shown, s, CLANS).filter(func(r): return String(r.event.type) == "oath_sworn").map(func(r): return String(r.text))
	assert_eq(lines.size(), 1, "one line in the Clans' report")
	assert_true(not lines.is_empty() and String(lines[0]).begins_with(opens), "the report's line: %s" % [lines])


## Every FogData.TEXT template a rebuilt event fills, with names written for running text: the factions ("the Aurel Crown", "the
## Candlewake"), the province (the Long Vigil) and a ruler (the Ever-Regent). Every sentence starts with a capital, the ones a template
## adds mid-line (" {previous} lost it.") too. A new rebuilt event type needs a sample here.
func test_every_rebuilt_line_starts_each_sentence_with_a_capital() -> void:
	var s := _wake_game({"sieges": true, "fog": true})
	var vigil := _vigil(s)
	var samples := {
		"captured": [[vigil], [CROWN, WAKE], {"income": 12, "is_capital": true, "fort_level": 3, "walls": 4, "recruit_from": 5}],
		"vassal_joined": [[vigil], [CROWN], {"income": 6}],
		"vassal_contested": [[vigil], [CROWN, WAKE], {"income": 6}],
		"ruler_died": [[vigil], [CROWN], {"ruler": "ever_regent", "kind": "undying", "name": "the Ever-Regent", "generation": 1,
			"kept_power": 5, "successor_turn": 9, "successor_power": 5}],
		"ruler_arrived": [[vigil], [CROWN], {"ruler": "ever_regent", "kind": "undying", "name": "the Ever-Regent", "generation": 2,
			"kept_power": 5, "max_hp": 19, "attack": 13, "defense": 8, "ability_rank": 2}],
		"succession_waiting": [[vigil], [WAKE], {"successor_turn": 9, "successor_power": 5, "successor_generation": 2}],
		"oath_sworn": [[], [CROWN], {"node": "crown_oath_dawn", "branch": "celestial_host", "closed": "living_iron", "turn": 6}],
		"transformed": [[], [CROWN], {"node": "crown_celestial_host", "branch": "celestial_host",
			"renamed": {"spearmen": {"from": "Spearmen", "to": "Sunspears"}}, "new_unit": "seraphs", "opens_mandate": "hymn_of_dawn", "turn": 9}],
		"wild_spread": [[vigil], [CROWN], {"province": vigil, "from_terrain": "plains", "terrain": "forest"}],
		"fort_built": [[vigil], [WAKE], {"province": vigil, "level": 1, "walls": 3}],
		"fort_raised": [[vigil], [WAKE], {"province": vigil}],
		"ritual_cast": [[], [WAKE], {"ritual": "blood_moon", "until_turn": 6}],
		"ritual_fell": [[vigil], [WAKE], {"ritual": "bloodrot", "faction": CROWN, "until_turn": 6, "budget": 12}],
		"curse_bit": [[vigil], [WAKE, CROWN], {"ritual": "bloodrot", "until_turn": 6, "budget": 12, "province": vigil}],
		"mark_stage": [[vigil], [WAKE], {"province": vigil, "stage": 2}],
		"scar_formed": [[vigil], [WAKE], {"province": vigil, "stage": 2, "until_turn": 9}],
		"scar_consumed": [[vigil], [WAKE], {"province": vigil, "stage": 2}],
	}
	for t in FogData.SAFE_NUMBERS:
		if t == "move":
			continue  # a seen move: test_fog_report.gd checks its two templates, which open with "An army of"
		assert_true(samples.has(t), "a sample for the rebuilt %s" % t)
		if not samples.has(t):
			continue
		var sample: Array = samples[t]
		var text := FogRules.text_for(t, sample[2], sample[0], sample[1], s)
		assert_false(text.is_empty() or text.contains("{"), "%s: a finished template: %s" % [t, text])
		_assert_capitals(text, t)
	# The templates the issue names open with {faction}: each line now opens "The ...", and a capture's " {previous} lost it." too.
	for t in ["captured", "oath_sworn", "transformed", "fort_built", "fort_raised", "ritual_cast"]:
		var sample: Array = samples[t]
		var text := FogRules.text_for(t, sample[2], sample[0], sample[1], s)
		assert_true(text.begins_with("The "), "%s: %s" % [t, text])
	var captured: Array = samples.captured
	assert_true(FogRules.text_for("captured", captured[2], captured[0], captured[1], s).contains(" The %s lost it." % s.find_faction(WAKE).faction_name),
		"the capture's second sentence")
	# A line that opens with the province: "The Long Vigil swore fealty ...".
	var joined: Array = samples.vassal_joined
	assert_true(FogRules.text_for("vassal_joined", joined[2], joined[0], joined[1], s).begins_with(_start(s, vigil) + " swore fealty"))


## A stand-in for the Candlewake's army at `pid` in the Crown's view `v`, seen at `level` on turn 3 (FogRules' view note).
func _stand_in(v: GameState, pid: String, level: String) -> Army:
	var a := Army.new()
	a.id = FogRules.view_id(WAKE, pid)
	a.owner = WAKE
	a.location = pid
	a.units.append(Unit.new(v.find_faction(WAKE).unit_types[0], WAKE))
	a.seen = {"level": level, "turn": 3, "counts": {}, "total": FogRules.round_count(1), "blessed": 0}
	return a


## A rival's army at the Long Vigil going out of sight: the fog's synthetic line opens with the province, "The Long Vigil is out of
## your sight now: ...", in the event and in the report.
func test_losing_sight_of_the_long_vigil_starts_with_a_capital() -> void:
	var s := _wake_game({"fog": true})
	var vigil := _vigil(s)
	var views := {}
	for level in ["glimpse", FogData.MEMORY]:
		var v := s.deep_copy()
		v.is_view = true  # the Crown's view of the game (FogRules.view_state): only the stand-in at the Long Vigil
		v.view_of = CROWN
		v.armies.clear()
		v.armies.append(_stand_in(v, vigil, level))
		views[level] = v
	var after: GameState = views[FogData.MEMORY]
	var memory: Array = FogRules.synthetic_events(views.glimpse, after, [], CROWN).filter(func(e): return String(e.type) == "memory_added")
	assert_eq(memory.size(), 1, "the army is a memory now")
	if memory.is_empty():
		return
	var opens := "%s is out of your sight now: " % _start(after, vigil)
	assert_true(String(memory[0].text).begins_with(opens), memory[0].text)
	var rows := TurnReportText.rows(memory, after, CROWN)
	assert_true(String(rows[0].text).begins_with(opens), rows[0].text)


## The fog kit's 20 games (tests/fog_test_kit.gd): every row each seat reads starts each sentence with a capital, the rebuilt
## Oaths, transformations and forts among them.
func test_every_row_of_the_fog_games_starts_each_sentence_with_a_capital() -> void:
	var rows := 0
	var rebuilt := 0
	for g in Kit.games():
		for t in g.turns:
			for v in Kit.SEATS:
				for row in TurnReportText.rows(t.report[v], t.view_after[v], v):
					rows += 1
					rebuilt += 1 if bool(row.event.get("rebuilt", false)) else 0
					_assert_capitals(String(row.text), "%s, turn %d, %s's report" % [g.name, int(t.turn), v])
	assert_true(rows > 500 and rebuilt > 20, "rows read: %d, rebuilt: %d" % [rows, rebuilt])


# --- the report's rows ------------------------------------------------------------------------------------

## The report's own capture line opens with the province: "The Long Vigil fell to Aurel Crown unopposed: ...".
func test_the_long_vigil_falling_opens_its_line_with_a_capital() -> void:
	var s := _wake_game()
	var vigil := _vigil(s)
	for a in s.armies.duplicate():
		if a.owner == WAKE:
			s.armies.erase(a)
	var id := _crown_at_the_gates(s, ["spearmen", "spearmen"])
	var r := TurnResolver.resolve(s, {CROWN: [MoveOrder.new(id, vigil)]}, 1, StubBattleResolver.new())
	var after: GameState = r.new_state
	var captured: Array = r.events.filter(func(e): return String(e.type) == "captured")
	assert_eq(captured.size(), 1, "the Crown walks into the empty Long Vigil")
	if captured.is_empty():
		return
	var line := TurnReportText.line(captured[0], r.events, after, CROWN)
	assert_true(line.begins_with("%s fell to %s" % [_start(after, vigil), after.find_faction(CROWN).faction_name]), line)
	_assert_capitals(line, "the capture")


## A sentence the resolver wrote, which the record keeps word for word, that opens with the province (SiegeRules' fallen fort):
## the report's row reads it with a capital.
func test_a_resolver_sentence_that_opens_with_a_name_reads_with_a_capital() -> void:
	var s := _wake_game({"sieges": true})
	var vigil := _vigil(s)
	var said := SiegeRules.step_text(s, {"kind": "fallen", "why": "battle", "province": vigil, "owner": WAKE, "besieger": CROWN}, 3)
	assert_true(said.begins_with(s.find_province(vigil).name + " fell: "), "the resolver's words open with the name: %s" % said)
	var e := {"type": "siege_ended", "phase": "sieges", "provinces": [vigil], "factions": [CROWN, WAKE], "armies": [], "cause": "battle",
		"numbers": {"owner": WAKE, "besieger": CROWN}, "text": said, "codex": "siege"}
	assert_eq(TurnReportText.line(e, [e], s), RulerRules._cap(said), "the same words, with a capital")
	assert_eq(String(e.text), said, "the event keeps its own text")


## A mid-line sentence of the resolver's: the Candlewake's income while the Long Vigil is cut off, "... Gold: 17 -> 22. The Long Vigil
## paid nothing: it is cut off ...".
func test_a_cut_off_long_vigil_starts_its_sentence_in_the_income_line_with_a_capital() -> void:
	var s := _wake_game({"sieges": true})
	var vigil := _vigil(s)
	var id := _crown_at_the_gates(s, Fx.units("knights", 12))
	var t1 := Fx.resolve(s, {CROWN: [MoveOrder.new(id, vigil)]})
	assert_eq(Fx.events_of(t1.events, "siege_started").size(), 1, "the Crown besieges the Long Vigil")
	var t2 := Fx.resolve(t1.new_state, {})
	var income: Array = Fx.events_of(t2.events, "income").filter(func(e): return e.factions.has(WAKE))
	assert_eq(income.size(), 1, "the Candlewake's income")
	if income.is_empty():
		return
	var name := String((t2.new_state as GameState).find_province(vigil).name)
	assert_true(String(income[0].text).contains(". %s paid nothing" % name), "the record's words: %s" % income[0].text)
	var line := TurnReportText.line(income[0], t2.events, t2.new_state, WAKE)
	assert_true(line.contains(". %s paid nothing: it is cut off" % RulerRules._cap(name)), line)
	_assert_capitals(line, "the income line")


# --- needs you and the Chronicle -----------------------------------------------------------------------------

## A siege of the Long Vigil: the garrison's needs-you card and, once the walls are down, both sides' needs-you lines.
func test_a_siege_of_the_long_vigil_opens_its_needs_with_capitals() -> void:
	var s := _wake_game({"sieges": true})
	var vigil := _vigil(s)
	var id := _crown_at_the_gates(s, Fx.units("knights", 12))
	var t1 := Fx.resolve(s, {CROWN: [MoveOrder.new(id, vigil)]})
	var after: GameState = t1.new_state
	assert_eq(Fx.events_of(t1.events, "siege_started").size(), 1, "the Crown besieges the Long Vigil")
	var name := _start(after, vigil)
	var cards := ChronicleModel.need_items(ChronicleModel.needs(after, WAKE, 1), after, 1)
	assert_eq(cards.map(func(c): return String(c.headline)), ["%s is besieged" % name], "the garrison's card")
	for c in cards:
		_assert_capitals(String(c.detail), "the garrison's card")
	after.find_province(vigil).walls = 0
	for fid in [CROWN, WAKE]:
		var lines := FortView.needs_you(after, fid, 1)
		assert_eq(lines.size(), 1, "%s has its breach line" % fid)
		if lines.size() == 1:
			assert_true(String(lines[0].text).begins_with("%s's walls are down. " % name), lines[0].text)


## A battle at the Long Vigil and its capture are one Chronicle card, whose detail joins the capture's sentence: "The Long Vigil is
## yours now." for the winner, "The Long Vigil passes to the Crown." for the loser.
func test_the_battle_and_capture_card_of_the_long_vigil_starts_its_sentences_with_capitals() -> void:
	var s := _wake_game()
	var vigil := _vigil(s)
	var id := _crown_at_the_gates(s, Fx.units("knights", 12))
	var r := TurnResolver.resolve(s, {CROWN: [MoveOrder.new(id, vigil)]}, 1, StubBattleResolver.new())
	var after: GameState = r.new_state
	assert_eq(r.events.filter(func(e): return String(e.type) == "captured").size(), 1, "the Crown wins there and takes it")
	var name := _start(after, vigil)
	var wants := {CROWN: "%s is yours now." % name, WAKE: "%s passes to %s." % [name, TurnReportText.faction_short(after, CROWN)]}
	for fid in [CROWN, WAKE]:
		var cards: Array = ChronicleModel.build({"turn": 1, "events": r.events}, after, fid).filter(func(c): return String(c.type) == "battle")
		assert_eq(cards.size(), 1, "%s: one card for the battle and its capture" % fid)
		if cards.size() == 1:
			assert_true(String(cards[0].detail).contains(String(wants[fid])), cards[0].detail)
			_assert_capitals(String(cards[0].detail), "%s's card" % fid)
