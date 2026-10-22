extends "res://tests/test_case.gd"
## CW-1 (#252, design/CANDLEWAKE.md §1, §2.2, §3.1): the Candlewake scaffold. Every army of a faction that keeps a flame burns at
## one (Army.flame, WickRules) and every game where a faction marks its land carries `marks` (MarkRules), both left out of every
## other game; they save and load; the exact flame shows only in clear sight while the marks are public; the wake step and the
## Wick step have their places in the turn; and the six events have their contracts. The steps' rules are CW-2 and CW-3, so
## nothing changes a flame or a mark yet. The Crown–Clans byte gate is tests/test_cw0_byte_gate.gd.

const CROWN := "kingdom"
const CLANS := "beasts"
const WAKE := "candlewake"


func _create(seats: Array, flags: Dictionary = {}, game_seed: int = 17) -> GameState:
	var errors := []
	var s := GameState.create(game_seed, seats, flags, {}, errors)
	assert_eq(errors, [], "%s builds" % [seats])
	return s


func _json(s: GameState) -> String:
	return JSON.stringify(s.to_dict()) if s != null else ""


func _wake_army(s: GameState, pid: String, flame: int) -> Army:
	var f := s.find_faction(WAKE)
	var a := Army.new()
	a.id = s.new_army_id(WAKE)
	a.owner = WAKE
	a.location = pid
	a.units.append(Unit.new(f.unit_types[0], WAKE))
	a.flame = flame
	s.armies.append(a)
	return a


# --- the fields -------------------------------------------------------------------------------------

func test_crown_clans_games_carry_no_flame_and_no_marks() -> void:
	for s in [GameState.new(3), _create([CLANS, CROWN], {"sieges": true, "fog": true, "independents": true}),
			GameState.with_magic(3), GameState.with_paths(5)]:
		var d: Dictionary = s.to_dict()
		assert_false(d.has("marks"), "no marks key")
		for a in d.armies:
			assert_false(a.has("flame"), "%s has no flame key" % a.id)
		assert_false(TurnResolver.phases(s).has("wake") or TurnResolver.phases(s).has("wick"), "no wake or Wick step")
		assert_false(WickRules.in_play(s) or MarkRules.in_play(s))
	assert_eq(TurnResolver.phases(GameState.new(1)), TurnResolver.PHASES, "the M1 phases, unchanged")


func test_candlewake_armies_burn_at_their_start_flame_and_the_game_carries_marks() -> void:
	for seats in [[CROWN, WAKE], [WAKE, CLANS]]:
		var s := _create(seats)
		var wake := s.find_army("candlewake-1")
		assert_eq(wake.flame, int(FactionData.row(WAKE).wick.start), "the start army burns at the row's start flame")
		assert_eq(WickRules.start_flame(s, WAKE), int(FactionData.row(WAKE).wick.start))
		assert_eq(WickRules.cap(s, WAKE), int(FactionData.row(WAKE).wick.cap))
		var other: String = seats[0] if seats[1] == WAKE else seats[1]
		assert_eq(s.find_army("%s-1" % other).flame, -1, "the other faction keeps no flame")
		var d := s.to_dict()
		assert_eq(d.get("marks"), {}, "the game carries marks, none yet")
		for a in d.armies:
			assert_eq(a.has("flame"), String(a.owner) == WAKE, "%s saves a flame only if it is the Candlewake's" % a.id)
		assert_true(WickRules.in_play(s) and MarkRules.in_play(s))


func test_flames_and_marks_save_and_load() -> void:
	var s := _create([CROWN, WAKE], {"fog": true})
	s.find_army("candlewake-1").flame = 3
	var p := s.find_province("thornvale")
	s.marks = {"thornvale": {"mark": {"faction": WAKE, "since_turn": 5}},
		"rivermarch": {"scar": {"faction": WAKE, "stage": 2, "until_turn": 13}},
		"stonegate": {"mark": {"faction": WAKE, "since_turn": 2}, "scar": {"faction": WAKE, "stage": 3, "until_turn": 9}}}
	var errors := []
	assert_true(s.validate(errors), "valid: %s" % [errors])
	assert_true(p != null)
	var copy := s.deep_copy()
	assert_eq(_json(copy), _json(s), "a deep copy is the same game")
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())), errors)
	assert_eq(errors, [], "it loads after a JSON round trip")
	assert_eq(_json(loaded), _json(s), "the same game after a JSON round trip")
	assert_eq(loaded.find_army("candlewake-1").flame, 3)
	assert_eq(loaded.marks.stonegate.scar.until_turn, 9)
	assert_true(loaded.marks.stonegate.scar.until_turn is int, "numbers come back whole")
	# An empty entry is never saved.
	s.marks["westwatch"] = {}
	assert_false(s.to_dict().marks.has("westwatch"), "only non-empty entries are saved")


func test_bad_flames_and_marks_are_refused_in_plain_words() -> void:
	var cases := [
		["a flame on a Crown army", func(s: GameState): s.find_army("kingdom-1").flame = 1, "keeps no flame"],
		["a Candlewake army with no flame", func(s: GameState): s.find_army("candlewake-1").flame = -1, "has no flame"],
		["a flame above the cap", func(s: GameState): s.find_army("candlewake-1").flame = WickRules.cap(s, WAKE) + 1, "above its cap"],
		["a mark off the map", func(s: GameState): s.marks = {"atlantis": {"mark": {"faction": WAKE, "since_turn": 1}}}, "not on this map"],
		["an empty entry", func(s: GameState): s.marks = {"thornvale": {"other": 1}}, "holds only a mark and a scar"],
		["a mark of a faction that marks nothing", func(s: GameState): s.marks = {"thornvale": {"mark": {"faction": CROWN, "since_turn": 1}}},
			"marks its land"],
		["a scar past the last stage", func(s: GameState): s.marks = {"thornvale": {"scar": {"faction": WAKE, "stage": MarkData.stage_count(WAKE) + 1,
			"until_turn": 4}}}, "stages 1 to"],
		["a mark missing its turn", func(s: GameState): s.marks = {"thornvale": {"mark": {"faction": WAKE}}}, "no 'since_turn'"],
		["a mark with text for a turn", func(s: GameState): s.marks = {"thornvale": {"mark": {"faction": WAKE, "since_turn": "five"}}},
			"not a whole number"],
	]
	for c in cases:
		var s := _create([CROWN, WAKE])
		c[1].call(s)
		var errors := []
		assert_false(s.validate(errors), "%s is refused" % c[0])
		assert_true(" ".join(errors).contains(String(c[2])), "%s: %s" % [c[0], errors])
	var plain := GameState.new(5)
	plain.marks = {"thornvale": {"mark": {"faction": WAKE, "since_turn": 1}}}
	var errors := []
	assert_false(plain.validate(errors), "marks in a game where nobody marks the land")
	assert_true(" ".join(errors).contains("none of its factions marks"), " ".join(errors))


# --- where flames start ------------------------------------------------------------------------------

func test_new_armies_are_lit_and_a_split_keeps_its_flame() -> void:
	var s := _create([CROWN, WAKE])
	var start := WickRules.start_flame(s, WAKE)
	var home := s.find_faction(WAKE).capital
	# Recruits forming a new army: march the start army out, then recruit at the capital.
	var out: String = s.find_province(home).neighbors[0]
	var moved := TurnResolver.resolve(s, {WAKE: [MoveOrder.new("candlewake-1", out)]}, 1, StubBattleResolver.new())
	var s2: GameState = moved.new_state
	s2.find_faction(WAKE).gold = 100
	var recruit := TurnResolver.resolve(s2, {WAKE: [RecruitOrder.new("gleaners")]}, 2, StubBattleResolver.new())
	var s3: GameState = recruit.new_state
	var fresh := s3.armies.filter(func(a): return a.owner == WAKE and a.location == home)
	assert_eq(fresh.size(), 1, "the recruits formed a new army at the capital")
	assert_eq(fresh[0].flame, start, "recruits forming a new army start it at the start flame")
	# A split's new army keeps its source's flame.
	var hot := s3.find_army("candlewake-1")
	hot.flame = 3
	hot.units.append(Unit.new(s3.find_faction(WAKE).unit_types[0], WAKE))
	var split := MusterRules.apply(s3, WAKE, MusterOrder.transfer(hot.id, "", [0], false, 0))
	assert_true(split.ok, String(split.get("reason", "")))
	var formed := s3.find_army(String(split.info.to))
	assert_eq(formed.flame, 3, "a split's new army keeps its source's flame")
	# A summoned army is lit like any new army.
	var summoned := MagicRules.place_summon(s3, WAKE, "thornwolves", 3, home, 0)
	assert_eq(summoned.flame, start)
	s3.armies.erase(summoned)  # a summon needs a game with magic to be valid; the Candlewake's magic is CW-5
	var errors := []
	assert_true(s3.validate(errors), "%s" % [errors])


# --- the steps' place in the turn ----------------------------------------------------------------------

func test_the_wake_and_wick_steps_run_after_recruitment_and_before_income() -> void:
	for flags in [{}, {"sieges": true, "fog": true, "independents": true}]:
		var s := _create([WAKE, CROWN], flags)
		var phases := TurnResolver.phases(s)
		var i := phases.find("recruitment")
		assert_eq(phases.slice(i, i + 4), ["recruitment", "wake", "wick", "income"], "%s: %s" % [flags.keys(), phases])
		assert_eq(GameSession.report_phases(s).slice(i, i + 4), ["recruitment", "wake", "wick", "income"])


func test_the_steps_change_nothing_yet() -> void:
	var s := _create([CROWN, WAKE], {"independents": true})
	s.find_army("candlewake-1").flame = 2
	var result := TurnResolver.resolve(s, {}, 9, AutoBattleResolver.new())
	var after: GameState = result.new_state
	assert_eq(after.find_army("candlewake-1").flame, 2, "the Wick step changes no flame until CW-2")
	assert_eq(after.marks, {}, "the wake step sets no mark until CW-3")
	for e in result.events:
		assert_false(WickRules.EVENT_TYPES.has(String(e.type)) or MarkRules.EVENT_TYPES.has(String(e.type)), "no Wick or wake events yet")


# --- fog (§2.4, §3.1) --------------------------------------------------------------------------------------

func _levels(s: GameState, viewer: String) -> Dictionary:
	var by_level := {}
	var levels := FogRules.sight(s, viewer)
	var pids := levels.keys()
	pids.sort()
	for pid in pids:
		if not by_level.has(levels[pid]):
			by_level[levels[pid]] = pid
	return by_level


func test_the_exact_flame_shows_in_clear_sight_only() -> void:
	var s := _create([CROWN, WAKE], {"fog": true})
	var where := _levels(s, CROWN)
	var clear := String(where[FogRules.CLEAR])
	var glimpse := String(where[FogRules.GLIMPSE])
	_wake_army(s, clear, 3)
	_wake_army(s, clear, 1)
	_wake_army(s, glimpse, 2)
	var view := FogRules.view_state(s, CROWN)
	var errors := []
	assert_true(view.validate(errors), "the view validates: %s" % [errors])
	var seen_clear := view.armies.filter(func(a): return a.owner == WAKE and a.location == clear)
	var flames: Array = seen_clear.map(func(a): return a.flame)
	flames.sort()
	assert_eq(flames, [1, 3], "in clear sight, a stand-in for each flame")
	var seen_glimpse := view.armies.filter(func(a): return a.owner == WAKE and a.location == glimpse)
	assert_false(seen_glimpse.is_empty(), "the glimpsed army is seen")
	for a in seen_glimpse:
		assert_eq(a.flame, -1, "glimpsed: flame unknown")
	# The Candlewake see their own armies whole, flames and all.
	var own := FogRules.view_state(s, WAKE)
	assert_eq(own.find_army("candlewake-1").flame, s.find_army("candlewake-1").flame)


func test_a_flame_out_of_clear_sight_changes_nothing_a_rival_sees() -> void:
	var s := _create([CROWN, WAKE], {"fog": true})
	var where := _levels(s, CROWN)
	var glimpsed := _wake_army(s, String(where[FogRules.GLIMPSE]), 1)
	var home := s.find_army("candlewake-1")
	assert_ne(String(FogRules.sight(s, CROWN).get(home.location, "")), FogRules.CLEAR, "the Candlewake's capital is out of the Crown's clear sight")
	var before := JSON.stringify(FogRules.view_state(s, CROWN).to_dict())
	glimpsed.flame = 3
	home.flame = 0
	assert_eq(JSON.stringify(FogRules.view_state(s, CROWN).to_dict()), before, "glimpsed and unseen flames change nothing in the Crown's view")
	var clear_army := _wake_army(s, String(where[FogRules.CLEAR]), 1)
	var with_clear := JSON.stringify(FogRules.view_state(s, CROWN).to_dict())
	clear_army.flame = 2
	assert_ne(JSON.stringify(FogRules.view_state(s, CROWN).to_dict()), with_clear, "a flame in clear sight is seen")


func test_the_marks_are_public_in_every_view() -> void:
	var s := _create([WAKE, CLANS], {"fog": true})
	s.marks = {"wildmoor": {"mark": {"faction": WAKE, "since_turn": 3}}, "bloodfen": {"scar": {"faction": WAKE, "stage": 1, "until_turn": 6}}}
	for viewer in [WAKE, CLANS]:
		var view := FogRules.view_state(s, viewer)
		assert_eq(view.marks, s.marks, "%s's view carries the marks whole" % viewer)


# --- the event contracts ------------------------------------------------------------------------------

func test_the_wick_events_are_their_owners_alone() -> void:
	var s := _create([CROWN, WAKE])
	var army := s.find_army("candlewake-1")
	var events := [WickRules.flame_event(s, army, 1, 2, "won"), WickRules.flame_event(s, army, 2, 1, "idle"),
		WickRules.gutter_event(s, army, 3, 6), WickRules.harvest_event(s, army, "wickwardens", 2, true)]
	assert_eq(events[0].text, "The Candlewake's 1st burns hotter: flame 2.")
	assert_eq(events[1].text, "The Candlewake's 1st burns lower: flame 1.")
	assert_eq(events[2].text, "The Candlewake's 1st is guttering: its regulars lost 6 hp.")
	assert_true(String(events[3].text).begins_with("The Harvest raised two Wickwardens at "), events[3].text)
	assert_true(String(events[3].text).ends_with(": they joined the Candlewake's 1st."), events[3].text)
	for e in events:
		assert_true(WickRules.EVENT_TYPES.has(String(e.type)))
		assert_true(FogData.AUDIENCE.has(String(e.type)), "%s has an audience" % e.type)
		assert_eq(e.factions, [WAKE])
		assert_eq(FogRules.filter_events([e], WAKE, s, s).size(), 1, "the owner sees %s" % e.type)
		assert_eq(FogRules.filter_events([e], CROWN, s, s), [], "a rival never sees %s" % e.type)
	assert_eq(events[0].phase, WickRules.PHASE)
	assert_eq(events[3].phase, "battles", "a Harvest follows its battle")


func test_the_marks_events_are_public_with_the_same_words() -> void:
	var s := _create([WAKE, CROWN])
	var pid := "thornvale"
	var events := [MarkRules.stage_event(s, WAKE, pid, 2), MarkRules.scar_event(s, WAKE, pid, 2, 13), MarkRules.relit_event(s, WAKE, pid, 2)]
	var name := s.find_province(pid).name
	assert_eq(events[0].text, "%s wakes: the Wake-Line." % name)
	assert_eq(events[1].text, "A cold wake forms at %s." % name)
	assert_eq(events[2].text, "%s relights." % name)
	for e in events:
		assert_true(MarkRules.EVENT_TYPES.has(String(e.type)))
		assert_eq(e.phase, MarkRules.PHASE)
		var mine := FogRules.filter_events([e], WAKE, s, s)
		assert_eq(mine.size(), 1, "the owner sees %s" % e.type)
		var theirs := FogRules.filter_events([e], CROWN, s, s)
		assert_eq(theirs.size(), 1, "the rival sees %s too" % e.type)
		assert_eq(String(theirs[0].text), String(e.text), "%s: the rival reads the same words" % e.type)
		assert_true(bool(theirs[0].get("rebuilt", false)), "rebuilt from its public numbers")
	assert_eq(MarkRules.stage_of(WAKE, 0), 1, "held 0: the first stage")
	for i in MarkData.stage_count(WAKE):
		var threshold := int(MarkData.stage(WAKE, i + 1).held)
		assert_eq(MarkRules.stage_of(WAKE, threshold), i + 1, "held %d reaches stage %d" % [threshold, i + 1])
	assert_eq(MarkRules.stage_of(WAKE, -1), 0, "not yet held")
