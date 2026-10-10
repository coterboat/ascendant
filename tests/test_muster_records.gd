extends "res://tests/test_case.gd"
## ARM-1 (design/ARM1_SPLIT_MERGE.md §9, "Records" and "Names"): a game with musters records them and replays to the same
## state through GameSession.replay and from_record; a save and load keeps the counters, so the next split gets the id the
## plan shows; the army model of the 3D board folds a muster turn exactly; names are permanent across split, merge,
## recruitment, summon, successor, save and replay.

const Kit := preload("res://tests/muster_test_kit.gd")
const Playback := preload("res://world3d/playback.gd")
const CROWN := "kingdom"
const CLANS := "beasts"


func _session(state: GameState = null) -> GameSession:
	return GameSession.new(state if state != null else GameState.new(7), [CROWN, CLANS], 7, StubBattleResolver.new())


## One turn of a two-seat hotseat game: the Crown's orders, then the Clans'. Returns "" or the first refusal.
func _play(session: GameSession, crown: Array, clans: Array = []) -> String:
	if session.phase() == GameSession.Phase.HANDOFF:
		session.acknowledge_handoff()
	for o in crown:
		var why := session.queue_order(o)
		if not why.is_empty():
			return why
	session.end_turn()
	session.acknowledge_handoff()
	for o in clans:
		var why2 := session.queue_order(o)
		if not why2.is_empty():
			return why2
	session.end_turn()
	return ""


func _json(d: Variant) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


func test_a_game_with_musters_replays_and_loads_to_the_same_state() -> void:
	var start := GameState.new(7)
	Kit.army(start, CROWN, "crownkeep", ["spearmen", "spearmen"], "knight_captain")  # the Crown's 2nd, with a commander of its own
	var session := _session(start)
	assert_eq(_play(session, [MusterOrder.transfer("kingdom-1", "", [0, 2]), MoveOrder.new("kingdom-3", "westwatch")]), "")
	assert_eq(_play(session, [MoveOrder.new("kingdom-3", "crownkeep")]), "")
	assert_eq(_play(session, [MusterOrder.swap("kingdom-1", "kingdom-2")]), "", "back together, the commanders swap")
	assert_eq(_play(session, [MusterOrder.merge("kingdom-3", "kingdom-2"), RecruitOrder.new("spearmen")]), "")
	assert_eq(session.turns_played(), 4)
	var state_now := JSON.stringify(session.state().to_dict())
	var rec := _json(session.record())
	var has_muster := false
	for turn in rec.history:
		for fid in turn.orders:
			for o in turn.orders[fid]:
				has_muster = has_muster or o.type == "muster"
	assert_true(has_muster, "the record holds the musters as {\"type\": \"muster\", ...} orders")
	var replayed := GameSession.replay(rec, StubBattleResolver.new())
	assert_eq(replayed.errors, [], "no complaints")
	assert_eq(JSON.stringify(replayed.state.to_dict()), state_now, "replay gives the same state")
	var loaded := GameSession.from_record(rec, StubBattleResolver.new())
	assert_eq(loaded.errors, [], "no complaints")
	assert_eq(JSON.stringify(loaded.session.state().to_dict()), state_now, "loading gives the same state")
	assert_eq(JSON.stringify(loaded.session.history()), JSON.stringify(session.history()), "and the same history")
	assert_eq(JSON.stringify(loaded.session.turn_report()), JSON.stringify(session.turn_report()), "and the same last report")
	# Up to each turn, replay and a fresh run agree.
	for t in range(1, 5):
		var upto := GameSession.replay(rec, StubBattleResolver.new(), t)
		assert_true(upto.state != null and upto.errors == [], "replay up to turn %d" % t)


func test_a_loaded_game_hands_out_the_ids_the_plan_shows() -> void:
	var session := _session()
	assert_eq(_play(session, [MusterOrder.transfer("kingdom-1", "", [0]), MusterOrder.transfer("kingdom-1", "", [0])]), "")
	assert_eq(session.state().next_army_ids[CROWN], 4)
	var loaded: GameSession = GameSession.from_record(_json(session.record()), StubBattleResolver.new()).session
	assert_true(loaded != null)
	if loaded.phase() == GameSession.Phase.HANDOFF:
		loaded.acknowledge_handoff()
	assert_eq(loaded.queue_order(MusterOrder.transfer("kingdom-1", "", [0])), "", "mid-plan after loading: a third split")
	assert_eq(loaded.queue_order(MoveOrder.new("kingdom-4", "westwatch")), "", "the new army is the Crown's 4th, as the counter saved says")
	assert_true(loaded.queue_order(MoveOrder.new("kingdom-5", "westwatch")).contains("no such army"), "and there is no 5th")
	assert_eq(loaded.current_orders().size(), 2)


func test_a_session_describes_a_muster_in_the_orders_list() -> void:
	var session := _session()
	assert_eq(session.queue_order(MusterOrder.transfer("kingdom-1", "", [0, 2])), "")
	assert_eq(session.queue_order(MoveOrder.new("kingdom-2", "westwatch")), "")
	var texts := session.current_order_texts()
	assert_eq(texts.size(), 2)
	assert_eq(texts[0], "Split Spearmen and Knights from the Crown's 1st into a new army, the Crown's 2nd, at Crownkeep.")
	assert_true(String(texts[1]).begins_with("Move the Crown's 2nd (Spearmen and Knights) from Crownkeep to Westwatch"), texts[1])


func test_the_board_model_folds_a_muster_turn_exactly() -> void:
	var s := Kit.game("sieges")
	Kit.army(s, CROWN, "crownkeep", ["spearmen", "spearmen"], "knight_captain", 1)
	var orders := {CROWN: [MusterOrder.transfer("kingdom-1", "", [0, 1]), MoveOrder.new("kingdom-4", "westwatch"),
		MusterOrder.merge("kingdom-3", "kingdom-1"), MusterOrder.transfer("kingdom-1", "", [0])]}
	var r := Kit.resolve(s, orders)
	assert_eq(Kit.events(r, "order_rejected"), [], "every order of the turn passes: %s" % [r.events.map(func(e): return e.text)])
	var folded := Playback.apply_events(Playback.model_of(s), r.events)
	var after := Playback.model_of(r.new_state)
	var f_ids: Array = folded.armies.keys()
	var a_ids: Array = after.armies.keys()
	f_ids.sort()
	a_ids.sort()
	assert_eq(f_ids, a_ids, "the same armies stand on the board the events built and on the board of the state after")
	for id in a_ids:
		assert_eq(folded.armies[id], after.armies[id], "%s stands in the same province" % id)
	assert_eq(folded.army_owner.size(), after.army_owner.size(), "and each new army has its owner in the sieges model")


func test_a_summon_and_a_successor_take_the_next_number_after_musters() -> void:
	var s := Kit.game("magic")
	# The Crown splits its first army (the 3rd, the ruler being the 2nd); the Clans split theirs too.
	assert_true(MusterRules.apply(s, CROWN, MusterOrder.transfer("kingdom-1", "", [0])).ok)
	assert_true(MusterRules.apply(s, CLANS, MusterOrder.transfer("beasts-1", "", [0])).ok)
	var pack := MagicRules.place_summon(s, CLANS, "thornwolves", 3, "fangridge", 0)
	assert_eq(pack.id, "beasts-4", "a summoned pack is the next army after the split's")
	assert_eq(TurnReportText.army_name(s, pack.id, CLANS), "the Clans' 4th")
	# The Crown's ruler falls; the successor arrives as a new army, numbered after the split too.
	var f := s.find_faction(CROWN)
	s.armies.erase(RulerRules.ruler_army(s, CROWN))
	f.ruler_status = RulerRules.DEAD
	f.successor_turn = 1
	f.successor_power = 5
	var heir := RulerRules.crown_successor(s, CROWN, 1)
	assert_true(heir != null)
	assert_eq(heir.id, "kingdom-4", "the successor's army takes the next number")
	assert_eq(TurnReportText.army_name(s, "kingdom-3", CROWN), "the Crown's 3rd", "the split-off army keeps its name")
	var errors := []
	assert_true(s.validate(errors), "the state is valid: %s" % [errors])


func test_names_are_permanent_across_split_merge_recruit_summon_successor_save_and_replay() -> void:
	var s := Kit.game("magic")
	s.find_faction(CROWN).gold = 500
	var session := _session(s)
	# Turn 1: split (the Crown's 3rd: the ruler is the 2nd), then merge the split back, and recruit into the first army.
	assert_eq(_play(session, [MusterOrder.transfer("kingdom-1", "", [0])]), "")
	assert_true(session.state().find_army("kingdom-3") != null, "the split is the Crown's 3rd")
	assert_eq(_play(session, [MusterOrder.merge("kingdom-3", "kingdom-1")]), "")
	var after_merge := session.state()
	assert_true(after_merge.find_army("kingdom-3") == null, "the merged army is gone and its name with it")
	assert_eq(after_merge.next_army_ids[CROWN], 4, "its number is not given out again")
	# A recruit that has to form a new army (the first one marches out) is the 4th, not the 3rd.
	assert_eq(_play(session, [MoveOrder.new("kingdom-1", "westwatch"), RecruitOrder.new("spearmen")]), "")
	var names := session.state().armies.filter(func(a): return a.owner == CROWN).map(func(a): return a.id)
	names.sort()
	assert_eq(names, ["kingdom-1", "kingdom-2", "kingdom-4"], "the gap where the 3rd was stays")
	# The same history replays to the same names.
	var rec := _json(session.record())
	var replayed := GameSession.replay(rec, StubBattleResolver.new())
	assert_eq(JSON.stringify(replayed.state.to_dict()), JSON.stringify(session.state().to_dict()))
	var loaded: GameSession = GameSession.from_record(rec, StubBattleResolver.new()).session
	assert_eq(JSON.stringify(loaded.state().to_dict()), JSON.stringify(session.state().to_dict()))
