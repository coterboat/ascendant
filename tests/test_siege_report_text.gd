extends "res://tests/test_case.gd"
## The turn report's siege lines (TurnReportText, design/M3C_SIEGES.md §9.4), from turns resolved with the real rules:
##   - S-1a's fort clauses on recruit and capture lines, composed from the events' numbers;
##   - open and breach battles at a fort named for what they were ("through the breach", "outside the walls, as the
##     garrison sallied"), not "where both arrived at the same time";
##   - every turn word in the reader's terms: the report of turn T is read at the start of turn T + 1, which the top
##     bar shows, so "this turn (T + 1)", "next turn (T + 2)", "in 3 turns (turn T + 3)".
## The events' own text never changes (it is in the recorded games' digests); only the report's line does.

const Fx := preload("res://tests/siege_fixtures.gd")
const CROWN := "kingdom"
const CLANS := "beasts"


## The report line of the first event of `type`, with the state after the turn.
func _line(result: Dictionary, type: String) -> String:
	var found := Fx.events_of(result.events, type)
	if found.is_empty():
		fail("the turn has a %s event" % type)
		return ""
	return TurnReportText.line(found[0], result.events, result.new_state)


func _event(result: Dictionary, type: String) -> Dictionary:
	var found := Fx.events_of(result.events, type)
	return found[0] if not found.is_empty() else {}


## No turn word of the resolver's own convention ("next turn (T + 1)" said in the report of turn T) is left.
func _assert_reader_words(line: String, reported: int, what: String) -> void:
	assert_false(line.contains("next turn (%d)" % (reported + 1)), "%s speaks of turn %d as this turn: %s" % [what, reported + 1, line])


# --- turn words ------------------------------------------------------------------------------------

func test_reader_turn_words() -> void:
	assert_eq(TurnReportText.reader_turn(8, 8), "this turn (8)")
	assert_eq(TurnReportText.reader_turn(9, 8), "next turn (9)")
	assert_eq(TurnReportText.reader_turn(10, 8), "in 3 turns (turn 10)")
	assert_eq(TurnReportText.reader_end(8, 8), "at the end of this turn (8)")
	assert_eq(TurnReportText.reader_end(9, 8), "at the end of next turn (9)")
	assert_eq(TurnReportText.reader_end(10, 8), "in 3 turns (end of turn 10)")
	# #279: after "from", a far turn leads with its number, so the wait is one phrase.
	assert_eq(TurnReportText.reader_from(8, 8), "from this turn (8)")
	assert_eq(TurnReportText.reader_from(9, 8), "from next turn (9)")
	assert_eq(TurnReportText.reader_from(10, 8), "from turn 10 (in 3 turns)")
	assert_eq(TurnReportText.reader_from(12, 8), "from turn 12 (in 5 turns)")


func test_a_siege_start_speaks_in_the_readers_turns() -> void:
	var s := Fx.state([["kingdom-3", CROWN, "stonegate", Fx.units("knights", 12)], ["beasts-5", CLANS, "blackwood", Fx.units("tuskers", 4)]],
		{"stonegate": CROWN, "blackwood": CLANS})
	var result := Fx.resolve(s, {CROWN: [MoveOrder.new("kingdom-3", "blackwood")]})
	var e := _event(result, "siege_started")
	var reported := int(result.new_state.current_turn)
	var now := reported + 1
	var line := _line(result, "siege_started")
	assert_true(String(e.text).contains("From next turn (%d)" % now), "the event's own text is unchanged: %s" % e.text)
	assert_true(line.contains("From this turn (%d) Blackwood is cut off" % int(e.numbers.cut_off_from)), line)
	assert_true(line.contains("The walls reach 0 %s, if the besiegers stay as they are." % TurnReportText.reader_end(int(e.numbers.breach_turn), now)), line)
	_assert_reader_words(line, reported, "the siege start")
	# The rest of the line is the resolver's: the force, the walls' drop and the siege damage.
	assert_true(line.begins_with("The Aurel Crown laid siege to Blackwood with %d troops. Its walls dropped from %d to %d (siege damage %d)." % [
		int(e.numbers.troops), int(e.numbers.walls_before), int(e.numbers.walls), int(e.numbers.damage)]), line)


func test_the_walls_falling_and_the_breach_speak_in_the_readers_turns() -> void:
	# A force that breaches Blackwood's keep on the siege's second turn, whatever FortData's numbers are.
	var force := Fx.force_to_breach(SiegeRules.walls_max(2), 2, 20, 2)
	assert_false(force.is_empty(), "some force breaches a keep in two turns")
	var s := Fx.state([["kingdom-3", CROWN, "stonegate", Fx.units("knights", force[0]), force[1]], ["beasts-5", CLANS, "blackwood", Fx.units("tuskers", 3)]],
		{"stonegate": CROWN, "blackwood": CLANS})
	var t1 := Fx.resolve(s, {CROWN: [MoveOrder.new("kingdom-3", "blackwood")]})
	var t2 := Fx.resolve(t1.new_state, {}, false, 8)
	var reported := int(t2.new_state.current_turn)
	var breached := _event(t2, "walls_breached")
	assert_false(breached.is_empty(), "the walls fall to 0 on the siege's second turn")
	var line := _line(t2, "walls_breached")
	assert_true(String(breached.text).contains("next turn (%d)" % (reported + 1)), "the event's own text is unchanged")
	assert_eq(line, "The walls of Blackwood are down (breached). If both sides are still there this turn (%d), they fight there in the open, with no order." % int(breached.numbers.battle_turn))
	var damaged := _line(t2, "walls_damaged")
	assert_true(damaged.begins_with("The siege of Blackwood, turn 2: the walls dropped from"), damaged)
	_assert_reader_words(damaged, reported, "the walls' drop")


func test_a_lifted_siege_and_a_finished_fort_speak_in_the_readers_turns() -> void:
	var s := Fx.state([["kingdom-3", CROWN, "stonegate", Fx.units("knights", 2)], ["beasts-5", CLANS, "stonegate", Fx.units("tuskers", 2)]],
		{"stonegate": CROWN, "rivermarch": CROWN})
	s.find_province("stonegate").siege_since = 1
	s.find_province("stonegate").walls = 3
	s.find_province("rivermarch").works = {"faction": CROWN, "to": 1, "left": 1, "turn": 1}
	s.current_turn = 1
	var result := Fx.resolve(s, {CLANS: [MoveOrder.new("beasts-5", "thornvale")]})
	var now := int(result.new_state.current_turn) + 1
	var lifted := _line(result, "siege_lifted")
	assert_true(lifted.ends_with("it takes recruits again from this turn (%d)." % now), lifted)
	var built := _event(result, "fort_built")
	var line := _line(result, "fort_built")
	assert_true(line.contains("It takes recruits from %s, %d a turn." % [TurnReportText.reader_turn(int(built.numbers.recruit_from), now),
		int(built.numbers.recruits)]), line)
	assert_true(line.contains("this turn (%d)" % now), line)


# --- the fort clauses ----------------------------------------------------------------------------------

func test_a_recruit_line_names_its_fort_and_count() -> void:
	var s := Fx.state([["beasts-5", CLANS, "blackwood", Fx.units("tuskers", 2)]], {"blackwood": CLANS})
	Fx.rich(s, CLANS)
	var result := Fx.resolve(s, {CLANS: [RecruitOrder.new("tuskers", "blackwood"), RecruitOrder.new("tuskers", "blackwood")]})
	var lines := Fx.events_of(result.events, "recruited").map(func(e): return TurnReportText.line(e, result.events, result.new_state))
	assert_eq(lines.size(), 2)
	var limit := int(FortData.LEVELS[2].recruits)
	assert_true(lines[0].contains("at Blackwood (%s, 1 of %d this turn) for" % [SiegeRules.level_word(2), limit]), lines[0])
	assert_true(lines[1].contains("at Blackwood (%s, 2 of %d this turn) for" % [SiegeRules.level_word(2), limit]), lines[1])
	assert_true(lines[0].contains("joined the Clans' 5th"), "the rest is the #55 line: %s" % lines[0])


func test_a_capture_says_the_fort_came_with_it() -> void:
	var s := Fx.state([["kingdom-3", CROWN, "westwatch", Fx.units("knights", 2)]], {"westwatch": CROWN})
	var result := Fx.resolve(s, {CROWN: [MoveOrder.new("kingdom-3", "stonegate")]})
	var e := _event(result, "captured")
	var now := int(result.new_state.current_turn) + 1
	var line := _line(result, "captured")
	assert_true(line.begins_with("Stonegate fell to Aurel Crown"), "the #55 line: %s" % line)
	assert_true(line.ends_with(" It came with its keep (walls %d of %d): the Aurel Crown can recruit there %s." % [int(e.numbers.walls),
		int(FortData.LEVELS[2].walls), TurnReportText.reader_from(int(e.numbers.recruit_from), now)]), line)
	assert_eq(int(e.numbers.recruit_from), now + FortData.CAPTURE_WAIT, "a capture waits CAPTURE_WAIT turns")
	assert_true(line.contains(TurnReportText.reader_from(now + FortData.CAPTURE_WAIT, now)), "a capture waits %d turns: %s" % [
		FortData.CAPTURE_WAIT, line])
	# A fort retaken within the window recruits at once.
	var s2 := Fx.state([["kingdom-3", CROWN, "westwatch", Fx.units("knights", 2)]], {"westwatch": CROWN, "stonegate": CLANS})
	s2.current_turn = 2
	s2.find_province("stonegate").owned_since = 2
	s2.find_province("stonegate").lost = {"faction": CROWN, "owned_since": 0, "turn": 2}
	var r2 := Fx.resolve(s2, {CROWN: [MoveOrder.new("kingdom-3", "stonegate")]})
	var line2 := _line(r2, "captured")
	assert_true(line2.contains("can recruit there from this turn (%d), since they retook it within %d turns of losing it." % [
		int(r2.new_state.current_turn) + 1, FortData.RETAKE_TURNS]), line2)


## #279: a captured fort's wait reads as one phrase, its first recruit turn first: "the Aurel Crown can recruit there from turn 4 (in 3
## turns)", never "from in 3 turns (turn 4)". The count is the reader's (the turn they are playing counts as one), from the event's numbers.
func test_a_captured_forts_wait_reads_as_one_phrase() -> void:
	var s := Fx.state([["kingdom-3", CROWN, "westwatch", Fx.units("knights", 2)]], {"westwatch": CROWN})
	var result := Fx.resolve(s, {CROWN: [MoveOrder.new("kingdom-3", "stonegate")]})
	var e := _event(result, "captured")
	var now := int(result.new_state.current_turn) + 1
	var from := int(e.numbers.recruit_from)
	var wait := from - now + 1
	assert_true(wait >= 3, "a capture waits CAPTURE_WAIT (%d) turns, so its first recruit turn is past next turn: %d" % [FortData.CAPTURE_WAIT, wait])
	var line := _line(result, "captured")
	assert_true(line.ends_with(": the Aurel Crown can recruit there from turn %d (in %d turns)." % [from, wait]), line)
	assert_false(line.contains("from in "), line)
	assert_true(String(e.text).ends_with("can recruit there from turn %d." % from), "the event's own text is unchanged: %s" % e.text)


# --- battles at forts ----------------------------------------------------------------------------------

func test_a_breach_battle_is_named_for_the_breach() -> void:
	var s := Fx.state([["kingdom-3", CROWN, "blackwood", Fx.units("knights", 10)], ["beasts-5", CLANS, "blackwood", Fx.units("tuskers", 2)]],
		{"blackwood": CLANS})
	s.find_province("blackwood").walls = 0
	s.find_province("blackwood").siege_since = 1
	s.current_turn = 1
	var result := Fx.resolve(s, {}, true)
	var line := _line(result, "battle")
	assert_true(line.begins_with("In Blackwood, through the breach, "), line)
	assert_false(line.contains("arrived at the same time"), line)


func test_a_sally_and_a_relief_are_named_for_what_they_were() -> void:
	var cases := {
		"sally": ["outside the walls, as the garrison sallied", {CLANS: [SiegeOrder.sally("beasts-5")]}],
		"relief": ["outside the walls, as a relief arrived", {CLANS: [MoveOrder.new("beasts-6", "blackwood")]}],
		"relief_sally": ["outside the walls, as a relief arrived and the garrison sallied to join it",
			{CLANS: [MoveOrder.new("beasts-6", "blackwood"), SiegeOrder.sally("beasts-5", "beasts-6")]}],
	}
	for why in cases:
		var s := Fx.state([["kingdom-3", CROWN, "blackwood", Fx.units("spearmen", 3)], ["beasts-5", CLANS, "blackwood", Fx.units("tuskers", 6)],
			["beasts-6", CLANS, "ebonpeak", Fx.units("tuskers", 4)]], {"blackwood": CLANS, "ebonpeak": CLANS})
		s.find_province("blackwood").siege_since = 1
		s.find_province("blackwood").walls = 4
		s.current_turn = 1
		var result := Fx.resolve(s, cases[why][1], true)
		var e := _event(result, "battle")
		assert_eq(String(e.get("numbers", {}).get("siege", {}).get("why", "")), why, "the battle is a %s" % why)
		var line := _line(result, "battle")
		assert_true(line.begins_with("In Blackwood, %s, " % cases[why][0]), "%s: %s" % [why, line])
		assert_false(line.contains("arrived at the same time"), line)


func test_battles_away_from_forts_read_as_before() -> void:
	var s := Fx.state([["kingdom-3", CROWN, "highcrag", Fx.units("spearmen", 3)], ["beasts-5", CLANS, "wildmoor", Fx.units("tuskers", 3)]],
		{"highcrag": CROWN, "wildmoor": CLANS})
	var result := Fx.resolve(s, {CROWN: [MoveOrder.new("kingdom-3", "thornvale")], CLANS: [MoveOrder.new("beasts-5", "thornvale")]}, true)
	assert_true(_line(result, "battle").begins_with("In Thornvale, where both arrived at the same time, "), _line(result, "battle"))
