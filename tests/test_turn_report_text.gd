extends "res://tests/test_case.gd"
## #55: the turn report's wording (TurnReportText). The resolver's event text is unchanged (the recorded
## games' digests hold it); the report writes its lines from the events' structured fields at display time.
## The scripted turn is test_turn_resolver.gd's: seed 2026, a border swap, a battle in Blackwood, captures,
## three Knights orders with gold for two, and a War Bear ordered somewhere it can't reach.
## Expected numbers come from the data (unit stats, prices, incomes, the events' own numbers).

const NO_YOU := "\\b[Yy]ou(r)?\\b"
const Policies := preload("res://tools/autoplay/policies.gd")


# --- fixtures -------------------------------------------------------------------------------------

func _state(specs: Array, owners: Dictionary = {}) -> GameState:
	var s := GameState.new(99)
	s.armies.clear()
	for spec in specs:
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
	for pid in owners:
		s.find_province(pid).owner = owners[pid]
	return s


func _scripted_state() -> GameState:
	return _state([
		["kingdom-1", "kingdom", "crownkeep", ["spearmen", "knight_captain"]],
		["kingdom-2", "kingdom", "thornvale", ["crossbowmen"]],
		["kingdom-3", "kingdom", "stonegate", ["knights"]],
		["beasts-4", "beasts", "wildmoor", ["fangthrowers"]],
		["beasts-5", "beasts", "ebonpeak", ["tuskers"]],
		["beasts-6", "beasts", "deepwood", ["war_bear"]],
	], {"thornvale": "kingdom", "wildmoor": "beasts", "stonegate": "kingdom", "ebonpeak": "beasts", "deepwood": "beasts"})


func _scripted_orders() -> Dictionary:
	return {
		"kingdom": [MoveOrder.new("kingdom-2", "wildmoor"), MoveOrder.new("kingdom-3", "blackwood"), MoveOrder.new("kingdom-1", "rivermarch"),
			RecruitOrder.new("knights"), RecruitOrder.new("knights"), RecruitOrder.new("knights")],
		"beasts": [MoveOrder.new("beasts-4", "thornvale"), MoveOrder.new("beasts-5", "blackwood"), MoveOrder.new("beasts-6", "crownkeep"),
			RecruitOrder.new("tuskers")],
	}


func _texts(rows: Array) -> Array:
	return rows.map(func(r): return String(r.text))


func _of(rows: Array, type: String) -> Array:
	return rows.filter(func(r): return String(r.event.type) == type)


func _assert_reads_cleanly(texts: Array, what: String) -> void:
	var no_you := RegEx.create_from_string(NO_YOU)
	var army_ids := RegEx.create_from_string("\\b(kingdom|beasts)-\\d+\\b")
	var bare_ids := RegEx.create_from_string("\\b(kingdom|beasts)\\b")
	var pids := []
	for p in MapData.PROVINCES:
		pids.append(p.id)
	var province_ids := RegEx.create_from_string("\\b(%s)\\b" % "|".join(pids))
	for t in texts:
		assert_false(String(t).is_empty(), "%s: no empty line" % what)
		assert_false(t.contains("seeded roll"), "%s: no 'seeded roll': %s" % [what, t])
		assert_false(t.contains("swapped places"), "%s: 'tried to swap places': %s" % [what, t])
		assert_false(RegEx.create_from_string("\\(strength \\d+\\)").search(t) != null, "%s: no bare '(strength N)': %s" % [what, t])
		assert_false(RegEx.create_from_string("\\(\\d+ fighters?\\)").search(t) != null, "%s: no bare '(N fighters)': %s" % [what, t])
		assert_true(no_you.search(t) == null, "%s: no lone 'you': %s" % [what, t])
		assert_true(army_ids.search(t) == null, "%s: no army id: %s" % [what, t])
		assert_true(bare_ids.search(t) == null, "%s: no faction id: %s" % [what, t])
		assert_true(province_ids.search(t) == null, "%s: no province id: %s" % [what, t])
		assert_false(t.contains(" army at "), "%s: armies are named, not placed: %s" % [what, t])


# --- the scripted turn (the done-when of #55) ------------------------------------------------------

func test_the_scripted_turn_reads_cleanly_under_the_new_rules() -> void:
	var s := _scripted_state()
	var r := TurnResolver.resolve(s, _scripted_orders(), 2026, StubBattleResolver.new())
	var ns: GameState = r.new_state
	var rows := TurnReportText.rows(r.events, ns, "", s)
	var texts := _texts(rows)
	assert_eq(r.events.size(), 16, "the scripted turn has 16 events")
	assert_eq(rows.size(), r.events.size() - 1, "one line per event, except that the Crown's two recruits at Crownkeep are one line (MVP-3, #177)")
	_assert_reads_cleanly(texts, "scripted turn")

	# Rule 6: the War Bear's rejected move says where it stays.
	var bear_reason: String = TurnResolver.check_move(s, "beasts", MoveOrder.new("beasts-6", "crownkeep")).reason
	assert_eq(texts[0], "The order to move the Clans' 6th (War Bear) to Crownkeep was rejected: %s The War Bear stays at Deepwood." % bear_reason)

	# Rule 7: the two moves into Blackwood sit together (before the move into Rivermarch).
	var moves := rows.filter(func(x): return String(x.event.type) == "army_moved" and String(x.event.phase) == "movement")
	assert_eq(moves.map(func(x): return String(Array(x.event.provinces).back())), ["blackwood", "blackwood", "rivermarch"])
	assert_eq(moves[0].text, "The Clans' 5th (Tuskers) moved from Ebonpeak to Blackwood.")
	assert_eq(moves[1].text, "The Crown's 3rd (Knights) moved from Stonegate to Blackwood.")
	assert_eq(moves[2].text, "The Crown's 1st (Spearmen and Knight Captain) moved from Crownkeep to Rivermarch.")

	# Rules 2 and 3: the swap names the units, their strength and the outcome.
	var border: Dictionary = _of(rows, "border_battle")[0]
	var crossbows := StubBattleResolver.army_strength(s.find_army("kingdom-2"))
	var fangs := StubBattleResolver.army_strength(s.find_army("beasts-4"))
	assert_true(crossbows > fangs, "the Crossbowmen are stronger with the test rules")
	assert_eq(border.text, "On the border between Thornvale and Wildmoor, where they tried to swap places, Aurel Crown's Crossbowmen (%d) beat Thornmane Clans' Fangthrowers (%d): %s. The Fangthrowers (the Clans' 4th) were destroyed; the Crossbowmen (the Crown's 2nd) took no losses." % [
		crossbows, fangs, border.event.numbers.why])
	var after_border: Dictionary = rows[rows.find(border) + 1]
	assert_eq(after_border.text, "The Crown's 2nd won the border battle and went on to Wildmoor.")

	# Rule 2: the Blackwood battle.
	var battle: Dictionary = _of(rows, "battle")[0]
	var knights := StubBattleResolver.army_strength(s.find_army("kingdom-3"))
	var tuskers := StubBattleResolver.army_strength(s.find_army("beasts-5"))
	assert_eq(battle.text, "In Blackwood, where both arrived at the same time, Aurel Crown's Knights (%d) beat Thornmane Clans' Tuskers (%d): %s. The Tuskers (the Clans' 5th) were destroyed; the Knights (the Crown's 3rd) took no losses." % [
		knights, tuskers, battle.event.numbers.why])

	# Rule 5: Wildmoor's defenders marched out and died on the border: not "unopposed".
	var captures := _of(rows, "captured")
	var wildmoor: Dictionary = captures.filter(func(x): return Array(x.event.provinces) == ["wildmoor"])[0]
	assert_eq(wildmoor.text, "Wildmoor fell to Aurel Crown: its defenders (the Clans' 4th) marched out and died on the Thornvale border, and the Crown's 2nd marched in. It now pays Aurel Crown %d gold per turn instead of Thornmane Clans." % ns.find_province("wildmoor").income)
	var blackwood: Dictionary = captures.filter(func(x): return Array(x.event.provinces) == ["blackwood"])[0]
	assert_eq(blackwood.text, "Blackwood fell to Aurel Crown: the Crown's 3rd won the battle there. It now pays Aurel Crown %d gold per turn." % ns.find_province("blackwood").income)
	var rivermarch: Dictionary = captures.filter(func(x): return Array(x.event.provinces) == ["rivermarch"])[0]
	assert_eq(rivermarch.text, "Rivermarch fell to Aurel Crown: the Crown's 1st marched in unopposed (it was neutral). It now pays Aurel Crown %d gold per turn." % ns.find_province("rivermarch").income)

	# Recruits name the army they form or join.
	var recruits := _of(rows, "recruited")
	var tusker_cost := TurnResolver.recruit_cost(s, "beasts", "tuskers")
	var knight_cost := TurnResolver.recruit_cost(s, "kingdom", "knights")
	var crown_gold := s.find_faction("kingdom").gold
	var new_beasts := String(recruits[0].event.armies[0])
	var new_crown := String(recruits[1].event.armies[0])
	assert_eq(recruits[0].text, "Thornmane Clans recruited Tuskers at Fangridge for %d gold (%d gold left). They formed a new army, %s." % [
		tusker_cost, s.find_faction("beasts").gold - tusker_cost, TurnReportText.army_name(ns, new_beasts)])
	assert_eq(recruits.size(), 2, "the Crown's two orders for Knights at Crownkeep, into one army, are one line")
	assert_eq(recruits[1].text, "Aurel Crown recruited 2 Knights at Crownkeep for %d gold (%d gold left). They formed a new army, %s." % [
		2 * knight_cost, crown_gold - 2 * knight_cost, TurnReportText.army_name(ns, new_crown)])
	# The events themselves are as the resolver made them: one per unit, the second joining the first's army.
	var knight_events: Array = r.events.filter(func(e): return e.type == "recruited" and e.factions == ["kingdom"])
	assert_eq(knight_events.size(), 2)
	assert_true(String(knight_events[1].text).contains("They joined"), "the record is unchanged: %s" % knight_events[1].text)

	# Rule 6: the third Knights order says what they cost, what the Crown had, and that income came too late.
	var had := crown_gold - 2 * knight_cost
	var income: int = TurnResolver.income_of(ns, "kingdom").total
	assert_true(had < knight_cost and had + income >= knight_cost, "the scenario: short now, covered by this turn's income")
	var rejected := rows.filter(func(x): return String(x.event.type) == "order_rejected" and String(x.event.phase) == "recruitment")
	assert_eq(rejected.size(), 1)
	assert_eq(rejected[0].text, "Aurel Crown's third Knights order was rejected: Knights cost %d gold, and Aurel Crown had %d gold left. Recruits are paid before income: this turn's income of %d gold would have covered them, but it came after." % [
		knight_cost, had, income])

	# Income lines are already plain; they stay as the resolver wrote them.
	for x in _of(rows, "income"):
		assert_eq(x.text, x.event.text)
	# The resolver's own text is untouched (the recorded games' digests hold it).
	assert_true(String(border.event.text).contains("met as they swapped places"), "the event's own text is unchanged")


func test_the_scripted_turn_with_the_real_battle_rules() -> void:
	var s := _scripted_state()
	var r := TurnResolver.resolve(s, _scripted_orders(), 2026, AutoBattleResolver.new())
	var ns: GameState = r.new_state
	var rows := TurnReportText.rows(r.events, ns)  # as the game shows it: no start-of-turn state
	_assert_reads_cleanly(_texts(rows), "real battles")
	for x in _of(rows, "border_battle") + _of(rows, "battle"):
		var e: Dictionary = x.event
		var rep: Dictionary = e.numbers.report
		var sides := {}
		for sr in rep.sides:
			sides[sr.faction] = sr
		var w: Dictionary = sides[e.numbers.winner]
		var l: Dictionary = sides["beasts" if e.numbers.winner == "kingdom" else "kingdom"]
		var n := int(rep.rounds_fought)
		var head := "Aurel Crown's %s (%d hp) beat Thornmane Clans' %s (%d hp) after %d %s: %s." % [w.roster.units[0].name, w.hp_start,
			l.roster.units[0].name, l.hp_start, n, "round" if n == 1 else "rounds", rep.why]
		assert_true(e.numbers.winner == "kingdom", "the Crown wins both, as the review's turn has it")
		assert_true(x.text.contains(head), "%s\n  wants: %s" % [x.text, head])
		var how := "wiped out" if l.destroyed else ("broke and fled" if l.routed else "destroyed")
		assert_true(x.text.contains(how), "says how the loser lost: %s" % x.text)
		assert_true(x.text.contains("lost no fighters") if int(w.fighters_lost) == 0 else x.text.contains("lost %d of" % int(w.fighters_lost)), x.text)
	var border: Dictionary = _of(rows, "border_battle")[0]
	assert_true(border.text.begins_with("On the border between Thornvale and Wildmoor, where they tried to swap places, "), border.text)
	assert_true(border.text.contains("(the Clans' 4th)") and border.text.contains("(the Crown's 2nd)"), border.text)
	var wildmoor: Dictionary = _of(rows, "captured").filter(func(x): return Array(x.event.provinces) == ["wildmoor"])[0]
	assert_true(wildmoor.text.begins_with("Wildmoor fell to Aurel Crown: its defenders (the Clans' 4th) marched out and died on the Thornvale border"), wildmoor.text)
	# The War Bear's line is the same as with the test rules: it reads the army from the state after the turn.
	assert_true(String(rows[0].text).ends_with("The War Bear stays at Deepwood."), rows[0].text)
	assert_true(String(rows[1].text).begins_with("The Clans' 5th (Tuskers) moved"), "units come from the battle log: %s" % rows[1].text)


# --- rule 1: names ---------------------------------------------------------------------------------

func test_army_names_come_from_the_id_and_sort_as_numbers() -> void:
	var s := GameState.new(5)
	for pair in [[1, "1st"], [2, "2nd"], [3, "3rd"], [4, "4th"], [10, "10th"], [11, "11th"], [12, "12th"], [13, "13th"],
			[21, "21st"], [22, "22nd"], [23, "23rd"], [101, "101st"], [111, "111th"], [112, "112th"]]:
		assert_eq(TurnReportText.ordinal(pair[0]), pair[1])
	assert_eq(TurnReportText.army_name(s, "kingdom-3"), "the Crown's 3rd")
	assert_eq(TurnReportText.army_name(s, "beasts-12"), "the Clans' 12th")
	assert_eq(TurnReportText.sort_ids(["kingdom-10", "kingdom-9", "kingdom-2"]), ["kingdom-2", "kingdom-9", "kingdom-10"], "9 before 10")
	# A name depends on nothing but the army: other armies dying, moving or being raised leave it alone.
	var a := _state([["kingdom-1", "kingdom", "crownkeep", ["spearmen"]], ["kingdom-7", "kingdom", "westwatch", ["knights"]]])
	var b := _state([["kingdom-7", "kingdom", "stonegate", ["knights"]], ["kingdom-8", "kingdom", "crownkeep", ["spearmen"]]])
	assert_eq(TurnReportText.army_name(a, "kingdom-7"), TurnReportText.army_name(b, "kingdom-7"))
	assert_eq(TurnReportText.army_name(null, "kingdom-7"), "the Crown's 7th", "an army that is gone keeps its name")


func test_an_army_keeps_its_name_across_turns_while_others_die() -> void:
	# Turn 1 is the scripted turn: the Clans' 4th and 5th die. Turn 2: the Crown's 3rd moves on from Blackwood.
	var s := _scripted_state()
	var r1 := TurnResolver.resolve(s, _scripted_orders(), 2026, StubBattleResolver.new())
	var s2: GameState = r1.new_state
	var r2 := TurnResolver.resolve(s2, {"kingdom": [MoveOrder.new("kingdom-3", "ebonpeak")]}, 7, StubBattleResolver.new())
	var line1 := _texts(TurnReportText.rows(r1.events, s2)).filter(func(t): return t.begins_with("The Crown's 3rd"))
	var line2 := _texts(TurnReportText.rows(r2.events, r2.new_state)).filter(func(t): return t.begins_with("The Crown's 3rd"))
	assert_eq(line1, ["The Crown's 3rd (Knights) moved from Stonegate to Blackwood."])
	assert_eq(line2, ["The Crown's 3rd (Knights) moved from Blackwood to Ebonpeak."])


func test_a_rulers_army_is_named_after_its_ruler() -> void:
	var s := GameState.with_rulers(11)
	var king := RulerRules.ruler_army(s, "kingdom")
	assert_eq(TurnReportText.army_name(s, king.id), RulerRules.current_name(s, "kingdom"))
	var r := TurnResolver.resolve(s, {"kingdom": [MoveOrder.new(king.id, "westwatch")]}, 3)
	var moved := _of(TurnReportText.rows(r.events, r.new_state), "army_moved")
	assert_eq(moved[0].text, "%s moved from Crownkeep to Westwatch." % RulerRules._cap(RulerRules.current_name(s, "kingdom")))


# --- rule 6: results of rejected orders -------------------------------------------------------------

func test_a_recruit_short_of_gold_says_when_income_would_not_have_covered_it() -> void:
	var s := _state([["kingdom-1", "kingdom", "crownkeep", ["spearmen"]]])
	var cost := TurnResolver.recruit_cost(s, "kingdom", "knights")
	s.find_faction("kingdom").gold = 2
	var income: int = TurnResolver.income_of(s, "kingdom").total
	assert_true(2 + income < cost, "the scenario: even this turn's income is not enough")
	var r := TurnResolver.resolve(s, {"kingdom": [RecruitOrder.new("knights")]}, 1, StubBattleResolver.new())
	var rejected := _of(TurnReportText.rows(r.events, r.new_state), "order_rejected")
	assert_eq(rejected[0].text, "Aurel Crown's Knights order was rejected: Knights cost %d gold, and Aurel Crown had 2 gold left. Recruits are paid before income, and even this turn's income of %d gold would not have covered them." % [cost, income])


func test_a_rejected_move_says_what_the_army_did_instead() -> void:
	var s := _state([["kingdom-1", "kingdom", "crownkeep", ["spearmen", "knight_captain"]], ["beasts-2", "beasts", "wildmoor", ["fangthrowers"]],
		["kingdom-3", "kingdom", "thornvale", ["knights"]]], {"thornvale": "kingdom", "wildmoor": "beasts"})
	var r := TurnResolver.resolve(s, {
		"kingdom": [MoveOrder.new("kingdom-1", "westwatch"), MoveOrder.new("kingdom-1", "highcrag"), MoveOrder.new("kingdom-3", "fangridge"),
			MoveOrder.new("kingdom-3", "wildmoor"), MoveOrder.new("kingdom-9", "westwatch")],
		"beasts": [MoveOrder.new("beasts-2", "crownkeep")],
	}, 1, StubBattleResolver.new())
	# The test battle rules leave no battle log, so the start of the turn names the Fangthrowers that died.
	var texts := _texts(_of(TurnReportText.rows(r.events, r.new_state, "", s), "order_rejected"))
	_assert_reads_cleanly(texts, "rejected moves")
	assert_true(texts.has("The order to move the Crown's 1st (Spearmen and Knight Captain) to Highcrag was rejected: Each army moves once per turn, and the Crown's 1st already had a move order. It followed its first order, to Westwatch."), "\n".join(texts))
	assert_true(texts.any(func(t): return t.begins_with("The order to move the Crown's 3rd (Knights) to Fangridge was rejected: ") and t.ends_with("It moved to Wildmoor on its other order instead.")), "\n".join(texts))
	assert_true(texts.any(func(t): return t.begins_with("The order to move the Clans' 2nd (Fangthrowers) to Crownkeep was rejected: ") and t.ends_with("The Fangthrowers stayed at Wildmoor and were destroyed in the battle there.")), "\n".join(texts))
	var unknown: String = TurnResolver.check_move(s, "kingdom", MoveOrder.new("kingdom-9", "westwatch")).reason
	assert_true(texts.has("Aurel Crown's order to move an army that is not on the map to Westwatch was rejected: %s" % unknown), "\n".join(texts))
	# A road move without King's Roads: the rules' reason names the army by its place; the report by its name.
	var road := TurnResolver.resolve(s, {"kingdom": [MoveOrder.new("kingdom-1", "stonegate", "westwatch")]}, 1, StubBattleResolver.new())
	var road_line: String = _texts(_of(TurnReportText.rows(road.events, road.new_state), "order_rejected"))[0]
	assert_true(road_line.contains("so the Crown's 1st can't go through Westwatch to Stonegate."), road_line)
	assert_true(road_line.ends_with("The Spearmen and Knight Captain stay at Crownkeep."), road_line)
	assert_true(TurnReportText.third_person("Drillyard costs 10 research; you have 0 and gain 5 a turn.", "Aurel Crown").ends_with("Aurel Crown has 0 and gains 5 a turn."))


func test_reasons_are_told_about_the_faction_not_to_you() -> void:
	var no_you := RegEx.create_from_string(NO_YOU)
	var reasons := []
	var s := _state([["beasts-1", "beasts", "crownkeep", ["tuskers"]]], {"crownkeep": "beasts"})
	reasons.append(TurnResolver.check_recruit(s, "kingdom", RecruitOrder.new("spearmen"), 50).reason)  # capital not held
	var home := GameState.new(3)
	reasons.append(TurnResolver.check_recruit(home, "kingdom", RecruitOrder.new("dragon"), 50).reason)
	reasons.append(TurnResolver.check_recruit(home, "kingdom", RecruitOrder.new("knights"), 3).reason)
	var odd := RecruitOrder.new("spearmen")
	odd.at = "somewhere"
	reasons.append(TurnResolver.check_recruit(home, "kingdom", odd, 50).reason)
	# King's Roads (the Regent's Court preset has them): a move too far, and a road through land not owned.
	var roads := GameState.with_rulers(3, {"kingdom": "regents_court"})
	var crown: Army = roads.armies.filter(func(a): return a.owner == "kingdom" and a.ruler == null)[0]
	reasons.append(TurnResolver.check_move(roads, "kingdom", MoveOrder.new(crown.id, "thornvale")).reason)
	reasons.append(TurnResolver.check_move(roads, "kingdom", MoveOrder.new(crown.id, "stonegate", "westwatch")).reason)
	reasons.append(RulerRules.sacrifice_check(roads, "kingdom", "drilled_ranks", "veteran_levies").get("reason", ""))
	var paths := GameState.with_paths(3)
	reasons.append(TurnResolver._check_research_order(paths, "kingdom", ResearchOrder.new("crown_drillyard"), "crown_charters").get("reason", ""))
	for node in ["crown_arbalests", "crown_celestial_host"]:
		reasons.append(AscensionRules.check_research(paths, "kingdom", node).get("reason", ""))
	var some_you := 0
	for reason in reasons:
		assert_false(String(reason).is_empty(), "every case gives a reason")
		if no_you.search(reason) != null:
			some_you += 1
		var told := TurnReportText.third_person(reason, "Aurel Crown")
		assert_true(no_you.search(told) == null, "no 'you' left in: %s\n  (was: %s)" % [told, reason])
	assert_true(some_you >= 6, "the cases do speak to 'you' before (%d)" % some_you)
	assert_eq(TurnReportText.third_person(reasons[0], "Aurel Crown"), "Aurel Crown does not hold its capital, Crownkeep, so it can't recruit until it retakes it.")


# --- rule 5: captures --------------------------------------------------------------------------------

func test_captures_say_what_became_of_the_defenders() -> void:
	# The Clans' 2nd leaves Wildmoor for Ironspike while the Crown's 1st walks in; the Clans' 4th leaves
	# Blackwood and dies attacking Stonegate, where the Crown's 5th holds, while the Crown's 3rd walks into
	# Blackwood from Ebonpeak.
	var s := _state([["kingdom-1", "kingdom", "thornvale", ["knights"]], ["beasts-2", "beasts", "wildmoor", ["fangthrowers"]],
		["kingdom-3", "kingdom", "ebonpeak", ["knights"]], ["beasts-4", "beasts", "blackwood", ["tuskers"]],
		["kingdom-5", "kingdom", "stonegate", ["knights", "knight_captain"]]],
		{"thornvale": "kingdom", "wildmoor": "beasts", "stonegate": "kingdom", "blackwood": "beasts", "ebonpeak": "kingdom"})
	var r := TurnResolver.resolve(s, {
		"kingdom": [MoveOrder.new("kingdom-1", "wildmoor"), MoveOrder.new("kingdom-3", "blackwood")],
		"beasts": [MoveOrder.new("beasts-2", "ironspike"), MoveOrder.new("beasts-4", "stonegate")],
	}, 1, StubBattleResolver.new())
	var ns: GameState = r.new_state
	var texts := _texts(_of(TurnReportText.rows(r.events, ns, "", s), "captured"))
	_assert_reads_cleanly(texts, "captures")
	assert_true(texts.has("Wildmoor fell to Aurel Crown unopposed: its defenders (the Clans' 2nd) marched out to Ironspike, and the Crown's 1st marched in. It now pays Aurel Crown %d gold per turn instead of Thornmane Clans." % ns.find_province("wildmoor").income), "\n".join(texts))
	assert_true(texts.has("Blackwood fell to Aurel Crown: its defenders (the Clans' 4th) marched out and were destroyed in Stonegate, and the Crown's 3rd marched in. It now pays Aurel Crown %d gold per turn instead of Thornmane Clans." % ns.find_province("blackwood").income), "\n".join(texts))
	# Nobody was there at all.
	var empty := _state([["kingdom-1", "kingdom", "blackwood", ["knights"]]], {"blackwood": "kingdom", "ebonpeak": "beasts"})
	var r2 := TurnResolver.resolve(empty, {"kingdom": [MoveOrder.new("kingdom-1", "ebonpeak")]}, 1, StubBattleResolver.new())
	assert_eq(_texts(_of(TurnReportText.rows(r2.events, r2.new_state), "captured")),
		["Ebonpeak fell to Aurel Crown unopposed: no Thornmane Clans army was there when the Crown's 1st marched in. It now pays Aurel Crown %d gold per turn instead of Thornmane Clans." % r2.new_state.find_province("ebonpeak").income])


# --- rule 4: ties --------------------------------------------------------------------------------------

func test_a_tie_is_settled_by_a_50_50_roll_everywhere_players_read() -> void:
	# Spearmen and Fangthrowers have the same strength with the test rules, and both arrive.
	var s := _state([["kingdom-1", "kingdom", "highcrag", ["spearmen"]], ["beasts-2", "beasts", "wildmoor", ["fangthrowers"]]])
	var r := TurnResolver.resolve(s, {"kingdom": [MoveOrder.new("kingdom-1", "thornvale")], "beasts": [MoveOrder.new("beasts-2", "thornvale")]}, 4, StubBattleResolver.new())
	var battle: Dictionary = _of(TurnReportText.rows(r.events, r.new_state, "", s), "battle")[0]
	assert_eq(battle.event.numbers.tie_break, "roll")
	assert_true(battle.text.contains("a 50/50 roll picked the winner"), battle.text)
	assert_eq(TurnReportText.tie_roll(2), "a 50/50 roll")
	assert_eq(TurnReportText.tie_roll(3), "an even roll among the 3 tied sides")
	for key in RulesCodex.ENTRIES:
		assert_false(RulesCodex.text(key).contains("seeded roll"), "codex %s: no 'seeded roll'" % key)
	assert_true(RulesCodex.text("battle_round_cap").contains("a 50/50 roll"), RulesCodex.text("battle_round_cap"))


# --- with and without rulers -----------------------------------------------------------------------

func test_a_game_with_rulers_reads_the_same_way() -> void:
	for rulers in [false, true]:
		var start := GameState.with_rulers(2026) if rulers else GameState.new(2026)
		var session := GameSession.new(start, ["kingdom", "beasts"], 2026, AutoBattleResolver.new())
		var rngs := [SeededRNG.new(1), SeededRNG.new(2)]
		var ai := [Policies.make("ai"), Policies.make("ai")]
		var seen := {}
		for turn in 8:
			for seat in 2:
				if session.phase() == GameSession.Phase.HANDOFF:
					session.acknowledge_handoff()
				var fid := String(session.players()[seat])
				for o in ai[seat].orders(session.state(), fid, rngs[seat]):
					session.queue_order(o)
				session.end_turn()
			if session.is_over():
				break
			var report := session.turn_report()
			var rows := TurnReportText.rows(report.events, session.state())
			_assert_reads_cleanly(_texts(rows).filter(func(t): return not t.is_empty()), "%s turn %d" % ["rulers" if rulers else "M1", report.turn])
			for x in rows:
				seen[String(x.event.type)] = true
		assert_true(seen.has("army_moved") and seen.has("recruited") and seen.has("captured"), "the game moved, recruited and captured: %s" % str(seen.keys()))


# --- Army.get_description() and the unknown_army reason (rule 8) ----------------------------------

func test_army_descriptions_have_no_raw_ids() -> void:
	var s := GameState.with_rulers(4)
	for a in s.armies:
		var with_state := a.get_description(s)
		var without := a.get_description()
		for d in [with_state, without]:
			assert_false(d.contains(a.id) or d.contains(a.location) or RegEx.create_from_string("\\b%s\\b" % a.owner).search(d) != null, "no raw id: %s" % d)
	var crown: Army = s.armies.filter(func(a): return a.owner == "kingdom" and a.ruler == null)[0]
	assert_eq(crown.get_description(s), "the Crown's %s (%s) at Crownkeep" % [TurnReportText.ordinal(TurnReportText.army_number(crown.id)),
		TurnReportText.units_phrase(TurnReportText._army_entries(crown))])
	var king := RulerRules.ruler_army(s, "kingdom")
	assert_eq(king.get_description(s), "%s (ruler of the Aurel Crown) at Crownkeep" % RulerRules.current_name(s, "kingdom"))


func test_the_unknown_army_reason_does_not_assume_it_was_destroyed() -> void:
	var s := GameState.new(4)
	var check := TurnResolver.check_move(s, "kingdom", MoveOrder.new("kingdom-99", "westwatch"))
	assert_eq(check.code, "unknown_army")
	assert_false(check.reason.contains("no longer exists"), check.reason)
	assert_true(check.reason.contains("may have been destroyed") and check.reason.contains("never"), check.reason)


# --- the turn report panel and the battle report viewer --------------------------------------------

func _labels_text(node: Node) -> String:
	var out := []
	if node is Label or node is Button:
		out.append(node.text)
	for c in node.get_children():
		out.append(_labels_text(c))
	return "\n".join(out.filter(func(t): return not String(t).is_empty()))


func test_the_report_panel_shows_the_new_lines_and_keeps_its_links_and_watch_buttons() -> void:
	var s := _scripted_state()
	var r := TurnResolver.resolve(s, _scripted_orders(), 2026, AutoBattleResolver.new())
	var report := {"turn": 1, "header": "Turn 1 results", "events": r.events}
	var panel := load("res://ui/turn_report_panel.tscn").instantiate() as TurnReportPanel
	panel.show_report_data(report, "kingdom", false, r.new_state)
	var lines := TurnReportText.rows(r.events, r.new_state, "kingdom")
	var rows := panel.event_rows()
	assert_eq(rows.map(func(b): return b.text), _texts(lines), "the rows are TurnReportText's lines, in its order")
	# Rule 7 in the panel: the two moves into Blackwood are neighbours.
	var dests := []
	for b in rows:
		var e: Dictionary = b.get_meta("event")
		if e.type == "army_moved" and e.phase == "movement":
			dests.append(String(Array(e.provinces).back()))
	assert_eq(dests, ["blackwood", "blackwood", "rivermarch"])
	# Every row still has its "?" for its event's codex entry, and battle rows keep Watch and Battle report.
	var keys := panel.codex_buttons().map(func(q): return String(q.get_meta("codex_key")))
	var want := []
	for b in rows:
		var key := String(b.get_meta("event").get("codex", ""))
		if RulesCodex.ENTRIES.has(key):
			want.append(key)
	assert_eq(keys, want, "one ? per row, linking its event's entry")
	assert_eq(panel.watch_buttons().size(), 2, "both battles have Watch")
	assert_eq(panel.battle_buttons().size(), 2, "both battles have Battle report")
	assert_eq(panel.watch_queue().map(func(e): return e.type), ["border_battle", "battle"], "Watch your battles keeps report order")
	# A row that names armies says how they are named; it still says it shows the map.
	var move_row: Button = rows.filter(func(b): return b.get_meta("event").type == "army_moved")[0]
	assert_true(move_row.tooltip_text.contains(TurnReportText.NAMES_HINT), move_row.tooltip_text)
	assert_true(move_row.tooltip_text.contains("Click to show this on the map."), move_row.tooltip_text)
	assert_true(RulesCodex.ENTRIES.has("army_names") and RulesCodex.text("army").contains("Army names"), "the codex explains army names")
	_assert_reads_cleanly(rows.map(func(b): return b.text), "the panel")
	panel.free()


func test_the_battle_report_viewer_names_the_armies_and_says_50_50() -> void:
	var s := _scripted_state()
	var r := TurnResolver.resolve(s, _scripted_orders(), 2026, AutoBattleResolver.new())
	var border: Dictionary = r.events.filter(func(e): return e.type == "border_battle")[0]
	var viewer := load("res://ui/battle_report_viewer.tscn").instantiate() as BattleReportViewer
	assert_true(viewer.show_event(border, r.new_state))
	var text := _labels_text(viewer)
	assert_true(text.contains("Army: the Clans' 4th (Fangthrowers), from Wildmoor"), text)
	assert_true(text.contains("Army: the Crown's 2nd (Crossbowmen), from Thornvale"), text)
	# An exact tie at the round cap: the viewer says a 50/50 roll picked the winner.
	var tied := border.duplicate(true)
	tied.numbers.tie_break = "roll"
	tied.numbers.report.end = "round_cap"
	assert_true(viewer.show_event(tied, r.new_state))
	text = _labels_text(viewer)
	assert_true(text.contains("The shares were exactly equal, so a 50/50 roll picked the winner."), text)
	assert_false(text.contains("seeded"), "no 'seeded roll'")
	# A battle fought with the test rules has no report: the viewer shows the turn report's line for it.
	var stub := TurnResolver.resolve(s, _scripted_orders(), 2026, StubBattleResolver.new())
	var plain: Dictionary = stub.events.filter(func(e): return e.type == "battle")[0]
	assert_false(viewer.show_event(plain, stub.new_state))
	assert_true(_labels_text(viewer).contains("Aurel Crown's Knights (%d) beat the Clans' 5th (%d)" % [
		StubBattleResolver.army_strength(s.find_army("kingdom-3")), StubBattleResolver.army_strength(s.find_army("beasts-5"))]), _labels_text(viewer))
	viewer.free()


# --- design/M3_BATTLES.md §7.2: the codex's sentences about watching (left over from #95) ----------

func test_the_codex_says_how_to_watch_a_battle() -> void:
	assert_true(RulesCodex.text("battle_rounds").contains("Watch any battle from the turn report"), RulesCodex.text("battle_rounds"))
	assert_true(RulesCodex.text("battle_morale").contains("the white notch on each side's strength bar marks where it breaks"), RulesCodex.text("battle_morale"))
	assert_true(RulesCodex.text("battle_commanders").contains("When you watch a battle, the commanders stand in that back line"), RulesCodex.text("battle_commanders"))
	# Each points at the entry that says more, so the codex panel links it.
	assert_true(RulesCodex.text("battle_rounds").contains(String(RulesCodex.entry("battle_playback").title)))
	assert_true(RulesCodex.text("battle_morale").contains(String(RulesCodex.entry("battle_strength").title)))
