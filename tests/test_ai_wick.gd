extends "res://tests/test_case.gd"
## CW-6 (#257, design/CANDLEWAKE.md §8): the computer plays Wick (ai/ai_wick.gd). A cold army feeds its flame on a fight next door;
## one with no fight in reach goes home to a harbour in time and never ends a turn at flame 0 outside one it could reach; recruits
## never cool a hot army (they name a new army, or one at the start flame); the rough guess counts a known flame; and against a hot
## Candlewake army the other side denies a battle it would likely lose. In a Crown–Clans game none of it runs. Positions are found
## from the map and every number comes from WickRules and the AI's own constants.

const Simulator := preload("res://tools/autoplay/simulator.gd")
const CROWN := "kingdom"
const WAKE := "candlewake"
const SEED := 23
const CANDLEWAKE_ID := "candlewake"


func _game(flags: Dictionary = {}) -> GameState:
	var errors := []
	var s := GameState.create(SEED, [CROWN, WAKE], flags, {}, errors)
	assert_eq(errors, [], "the game builds")
	return s


## The state with every player army gone (Free Holds garrisons stay).
func _cleared(s: GameState) -> GameState:
	for a in s.armies.duplicate():
		if a.owner != IndependentData.FACTION_ID:
			s.armies.erase(a)
	return s


func _army(s: GameState, owner: String, at: String, types: Array, flame: int = -1) -> Army:
	var f := s.find_faction(owner)
	var a := Army.new()
	a.id = s.new_army_id(owner)
	a.owner = owner
	a.location = at
	for type_id in types:
		var ut := TurnResolver.recruitable_type(f, String(type_id))
		if ut.is_commander:
			a.commander = Unit.new(ut, owner)
		else:
			a.units.append(Unit.new(ut, owner))
	if WickRules.carries_flame(a):
		a.flame = flame if flame >= 0 else WickRules.start_flame(s, owner)
	s.armies.append(a)
	return a


func _plan(s: GameState, fid: String) -> Dictionary:
	var ai := AIPlayer.new()
	ai.configure(SEED, 0 if fid == CROWN else 1)
	var orders := ai.plan_orders(s, fid, SeededRNG.new(SEED), "normal")
	var moves := {}
	for o in orders:
		if o is MoveOrder:
			moves[o.army_id] = o.to
	return {"orders": orders, "moves": moves, "notes": ai.last_plan_notes(), "stats": ai.last_plan_stats()}


func _has_note(notes: Array, start: String) -> bool:
	return notes.any(func(n): return String(n).begins_with(start))


func _home(s: GameState) -> String:
	return s.find_faction(WAKE).capital


func _many(type_id: String, n: int) -> Array:
	var out := []
	for i in n:
		out.append(type_id)
	return out


# --- §8.1: fuel ------------------------------------------------------------------------------------

func test_a_cold_army_attacks_a_free_hold_next_door_to_feed_its_flame() -> void:
	var s := _cleared(_game({"independents": true}))
	var caps := [_home(s), s.find_faction(CROWN).capital]
	# A Free Holds province next to neither capital: its garrison goes, and our cold army stands there, next to the others.
	var holds := {}
	for a in s.armies:
		holds[a.location] = a
	var ids: Array = holds.keys()
	ids.sort()
	var at := ""
	for pid in ids:
		var nbrs: Array = s.find_province(String(pid)).neighbors
		if at.is_empty() and not nbrs.any(func(n): return caps.has(n)) and nbrs.any(func(n): return holds.has(n)):
			at = String(pid)
	assert_true(not at.is_empty(), "a Free Holds province away from both capitals")
	s.armies.erase(holds[at])
	s.find_province(at).owner = ""
	var cold := _army(s, WAKE, at, _many("wickwardens", 12), AIWick.COLD)
	_army(s, CROWN, caps[1], _many("spearmen", 4))
	var plan := _plan(s, WAKE)
	var to := String(plan.moves.get(cold.id, at))
	assert_true(holds.has(to) and to != at, "the cold army attacks a Free Holds garrison next door (went to %s)" % to)
	assert_true(_has_note(plan.notes, "Feeding the flame") or _has_note(plan.notes, "Attacking the"), "a note says why: %s" % [plan.notes])


# --- §8.2: home in time ----------------------------------------------------------------------------

func test_a_cold_army_with_no_fight_in_reach_goes_into_a_harbour_and_keeps_its_flame() -> void:
	var s := _cleared(_game())
	var home := _home(s)
	# A province next to our capital (a harbour) that is not one, and not the Crown's.
	var at := ""
	for n in s.find_province(home).neighbors:
		if at.is_empty() and not WickRules.harbour(s, WAKE, n) and s.find_province(n).owner != CROWN:
			at = n
	assert_true(not at.is_empty(), "an open province next to the capital")
	assert_true(WickRules.harbour(s, WAKE, home), "the capital is a harbour")
	_army(s, CROWN, s.find_faction(CROWN).capital, _many("spearmen", 4))
	var cold := _army(s, WAKE, at, _many("wickwardens", 2), AIWick.COLD)
	var plan := _plan(s, WAKE)
	assert_true(plan.moves.has(cold.id), "the cold army moves: %s" % [plan.notes])
	assert_true(_has_note(plan.notes, "Heading home in time"), "a note says why: %s" % [plan.notes])
	var r := TurnResolver.resolve(s, {WAKE: plan.orders, CROWN: []}, SEED, StubBattleResolver.new())
	assert_true(r.new_state != null, "the turn resolves")
	var after: Army = r.new_state.find_army(cold.id)
	assert_true(WickRules.harbour(r.new_state, WAKE, after.location), "it ends the turn in a harbour (%s): its own fort, or one it took" % after.location)
	assert_eq(after.flame, AIWick.COLD, "there it keeps its flame")


func test_no_army_ends_a_turn_at_flame_zero_outside_a_harbour_it_could_reach() -> void:
	# Whole games, the Candlewake against each side: every army of ours that ends a turn at flame 0 outside a harbour either
	# fought there, or was sieging, or had no harbour one move away when it planned.
	for seats in [[WAKE, CROWN], [WAKE, "beasts"]]:
		var r := Simulator.play_game(SEED, seats, ["ai", "ai"], 14, Callable(), {"rulers": true, "sieges": true, "independents": true})
		assert_eq(r.errors, [], "%s: no errors" % [seats])
		assert_eq(r.violations, [], "%s: no invariant violations" % [seats])
		var w: Dictionary = r.wick.get(WAKE, {})
		assert_true(int(w.get("army_turns", 0)) > 0, "%s: the Wick log counts the Candlewake's armies" % [seats])
		assert_true(float(w.get("harbour_turns", 0)) / float(w.army_turns) >= 0.5,
			"%s: most army-turns end in a harbour (%d of %d)" % [seats, int(w.harbour_turns), int(w.army_turns)])


# --- §8.3: recruits --------------------------------------------------------------------------------

func test_recruits_form_a_new_army_beside_a_hot_one_and_join_one_at_the_start_flame() -> void:
	var s := _cleared(_game())
	var home := _home(s)
	s.find_faction(WAKE).gold = 200
	_army(s, CROWN, s.find_faction(CROWN).capital, _many("spearmen", 4))
	var hot := _army(s, WAKE, home, _many("wickwardens", 3), AIWick.HOT + 1)
	var plan := _plan(s, WAKE)
	var recruits: Array = plan.orders.filter(func(o): return o is RecruitOrder and not o.is_with_ruler())
	assert_true(not recruits.is_empty(), "it recruits")
	var stays: bool = not plan.moves.has(hot.id) or String(plan.moves[hot.id]) == home
	for o in recruits:
		var ut := TurnResolver.recruitable_type(s.find_faction(WAKE), o.unit_type_id)
		if ut.is_commander or SiegeRules.is_engine(ut):
			continue
		assert_true(o.into != hot.id, "no recruit joins the hot army (%s)" % o.describe())
		if stays:
			assert_eq(o.into, RecruitOrder.NEW_PREFIX + home, "a recruit beside the hot army forms a new army")
	# An army of ours at exactly the start flame, holding there: recruits join it (joining cools nothing).
	var ai := AIPlayer.new()
	ai.configure(SEED, 1)
	var s2 := _cleared(_game())
	var even := _army(s2, WAKE, _home(s2), _many("wickwardens", 2), WickRules.start_flame(s2, WAKE))
	ai._begin(s2, WAKE, SeededRNG.new(SEED), "normal")
	ai._collect_armies()
	assert_eq(ai._wick.into_for(_home(s2), TurnResolver.recruitable_type(s2.find_faction(WAKE), "wickwardens")), even.id,
		"a recruit joins an army at the start flame")
	even.flame = 0
	assert_eq(ai._wick.into_for(_home(s2), TurnResolver.recruitable_type(s2.find_faction(WAKE), "wickwardens")),
		RecruitOrder.NEW_PREFIX + _home(s2), "a recruit never joins a guttering army")


# --- the rough guess -------------------------------------------------------------------------------

func test_the_rough_guess_counts_a_known_flame_and_none_for_mages_or_an_unknown_one() -> void:
	var s := _cleared(_game())
	var hot := _army(s, WAKE, _home(s), _many("wickwardens", 2), 3)
	var cold := _army(s, WAKE, _home(s), _many("wickwardens", 2), 0)
	var crown := _army(s, CROWN, s.find_faction(CROWN).capital, _many("spearmen", 2))
	var ai := AIPlayer.new()
	ai.configure(SEED, 0)
	ai._begin(s, CROWN, SeededRNG.new(SEED), "normal")
	ai._collect_armies()
	assert_true(ai._wick.against and not ai._wick.on, "the Crown plays against a flame and keeps none")
	assert_eq(ai._wick.attack_part(hot.units[0]), WickRules.battle_flame(s, hot) - 1, "flame 3: +2 attack")
	assert_eq(ai._wick.attack_part(cold.units[0]), WickRules.battle_flame(s, cold) - 1, "flame 0: -1 attack")
	assert_eq(ai._wick.attack_part(crown.units[0]), 0, "an army with no flame: none")
	hot.flame = -1  # as a glimpsed army shows under fog: flame unknown
	ai._collect_armies()
	assert_eq(ai._wick.attack_part(hot.units[0]), 0, "an unknown flame counts as none")


# --- §8.8: against the Candlewake ------------------------------------------------------------------

func test_against_a_hot_army_it_would_likely_lose_to_the_crown_denies_the_battle() -> void:
	var s := _cleared(_game())
	var cap := s.find_faction(CROWN).capital
	_army(s, CROWN, cap, _many("spearmen", 3))
	# A Crown province two moves from the capital, with a neighbour further out for the Candlewake's hot army.
	var dist := FogRules.distances(s, cap, 3)
	var here := ""
	var there := ""
	var ids: Array = dist.keys()
	ids.sort()
	for pid in ids:
		if int(dist[pid]) != 2 or not here.is_empty():
			continue
		for n in s.find_province(String(pid)).neighbors:
			if int(dist.get(n, 99)) == 3 and there.is_empty():
				here = String(pid)
				there = n
	assert_true(not here.is_empty(), "a province two moves out with one three moves out next to it")
	s.find_province(here).owner = CROWN
	var small := _army(s, CROWN, here, _many("spearmen", 2))
	var hot := _army(s, WAKE, there, _many("wickwardens", 6), AIWick.HOT + 1)
	var plan := _plan(s, CROWN)
	var to := String(plan.moves.get(small.id, here))
	assert_true(to != here and to != there, "the Crown's army pulls back (went to %s)" % to)
	assert_true(int(plan.stats.get("denials", 0)) >= 1, "it counts a denial: %s" % [plan.stats])
	assert_true(_has_note(plan.notes, "Denying the battle"), "a note says why: %s" % [plan.notes])
	# The same threat at flame 1 is no reason to deny it.
	hot.flame = 1
	plan = _plan(s, CROWN)
	assert_eq(int(plan.stats.get("denials", 0)), 0, "a cool army gets no denial")


# --- Crown–Clans ---------------------------------------------------------------------------------

func test_a_crown_clans_game_runs_none_of_it() -> void:
	var s := GameState.new(SEED)
	var ai := AIPlayer.new()
	ai.configure(SEED, 0)
	ai.plan_orders(s, CROWN, SeededRNG.new(SEED), "normal")
	ai._begin(s, CROWN, SeededRNG.new(SEED), "normal")
	ai._collect_armies()
	assert_true(not ai._wick.on and not ai._wick.against, "no seated faction keeps a flame")
	for a in s.armies:
		for u in a.units:
			assert_eq(ai._wick.attack_part(u), 0, "the rough guess is unchanged")


# --- the autoplay seats the Candlewake --------------------------------------------------------------

func test_the_autoplay_seats_the_candlewake_only_when_both_seats_are_named() -> void:
	var Autoplay := load("res://tools/autoplay/autoplay.gd")
	assert_eq(Autoplay._seats_from(["", ""]).seats, ["kingdom", "beasts"], "no seats named: the Crown and the Clans")
	assert_eq(Autoplay._seats_from(["beasts", ""]).seats, ["beasts", "kingdom"], "--seat1 alone keeps its old meaning")
	assert_eq(Autoplay._seats_from([WAKE, CROWN]).seats, [WAKE, CROWN], "both named: the Candlewake plays")
	assert_true(Autoplay._seats_from([WAKE, ""]).has("error"), "the Candlewake alone needs the other seat named")
	assert_true(Autoplay._seats_from([WAKE, WAKE]).has("error"), "a faction can't sit twice")
	var r := Simulator.play_game(SEED, [CROWN, WAKE], ["ai", "ai"], 3, Callable(), {"rulers": true})
	assert_eq(r.errors, [], "a Crown–Candlewake game plays")
	assert_true(r.wick.has(WAKE) and not r.wick.has(CROWN), "and logs the Candlewake's Wick only")
	var legacy := Simulator.play_game(SEED, [CROWN, "beasts"], ["ai", "ai"], 3)
	assert_eq(legacy.wick, {}, "a Crown–Clans game logs no Wick")


func test_the_codex_says_how_the_computer_plays_wick() -> void:
	var text := RulesCodex.text("computer_wick")
	assert_eq(RulesCodex.entry_faction("computer_wick"), CANDLEWAKE_ID, "it shows only in a game with the Candlewake")
	assert_true(text.contains("Playing the Candlewake"), "the entry covers Wick")
	assert_true(text.contains("flame %d or more" % AIWick.HOT), "with the AI's own threshold")
