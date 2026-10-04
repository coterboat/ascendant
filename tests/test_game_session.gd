extends "res://tests/test_case.gd"
## Tests for the hotseat game flow (#7) and the win condition (#8): GameSession and VictoryCheck.
##
## Unit strengths used below (attack + defense, see StubBattleResolver):
##   kingdom: spearmen 11, crossbowmen 12, knights 20, knight_captain 26  (starting army 69)
##   beasts:  tuskers 17, fangthrowers 12, war_bear 25, warchief 26      (starting army 80)

const RAW_IDS := ["kingdom", "beasts", "crownkeep", "fangridge", "westwatch", "ebonpeak", "stonegate",
	"blackwood", "deepwood", "wildmoor", "knight_captain", "warchief", "-1", "-2", "-3", "-4"]


# --- fixtures -------------------------------------------------------------------------------------

func _session(state: GameState = null, game_seed: int = 7) -> GameSession:
	var s: GameState = state if state != null else GameState.new(game_seed)
	var session := GameSession.new(s, ["kingdom", "beasts"], game_seed, StubBattleResolver.new())
	assert_eq(session.setup_errors(), [], "session starts")
	return session


## A fresh state with the starting armies replaced by `specs`: [[id, owner, location, [unit ids]], ...].
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


## Plays one full turn through the flow: kingdom (seat 1) orders, handoff, beasts (seat 2) orders.
func _play_turn(session: GameSession, kingdom_orders: Array, beasts_orders: Array) -> void:
	assert_eq(session.phase(), GameSession.Phase.ORDERS)
	assert_eq(session.current_player(), "kingdom")
	for o in kingdom_orders:
		assert_eq(session.queue_order(o), "", "kingdom order accepted")
	assert_eq(session.end_turn(), "")
	assert_eq(session.phase(), GameSession.Phase.HANDOFF)
	assert_eq(session.current_player(), "beasts")
	assert_eq(session.current_orders(), [], "nothing is shown during the handoff")
	assert_eq(session.acknowledge_handoff(), "")
	assert_eq(session.phase(), GameSession.Phase.ORDERS)
	for o in beasts_orders:
		assert_eq(session.queue_order(o), "", "beasts order accepted")
	assert_eq(session.end_turn(), "")


func _army_at(s: GameState, owner: String, location: String) -> Army:
	for a in s.armies:
		if a.owner == owner and a.location == location:
			return a
	return null


func _gold(session: GameSession, fid: String) -> int:
	return session.state().find_faction(fid).gold


func _types(events: Array) -> Array:
	return events.map(func(e): return e.type)


func _assert_no_raw_ids(text: String, what: String) -> void:
	assert_false(text.is_empty(), "%s has text" % what)
	for id in RAW_IDS:
		assert_false(text.contains(id), "%s shows no raw id '%s': %s" % [what, id, text])


func _assert_report_shape(report: Dictionary) -> void:
	for e in report.events:
		for key in ["type", "phase", "provinces", "factions", "armies", "cause", "numbers", "text", "codex"]:
			assert_true(e.has(key), "event %s has %s" % [e.get("type", "?"), key])
		assert_true(GameSession.REPORT_PHASES.has(e.phase), "event phase %s is a report phase" % e.phase)
		assert_false(RulesCodex.text(e.codex).is_empty(), "event %s links codex entry %s" % [e.type, e.codex])


# --- the hotseat flow -----------------------------------------------------------------------------

func test_three_scripted_turns_through_the_flow() -> void:
	var session := _session()
	assert_eq(session.turn_number(), 1)
	assert_eq(session.turn_report().events, [])

	# Turn 1: both armies march out of their capitals; both sides recruit a unit at home.
	_play_turn(session,
		[MoveOrder.new("kingdom-1", "westwatch"), RecruitOrder.new("spearmen")],
		[MoveOrder.new("beasts-2", "ebonpeak"), RecruitOrder.new("tuskers")])
	assert_eq(session.phase(), GameSession.Phase.HANDOFF)
	assert_eq(session.current_player(), "kingdom", "back to seat 1 for the next turn")
	assert_eq(session.turn_number(), 2)
	var s := session.state()
	assert_eq(s.find_army("kingdom-1").location, "westwatch")
	assert_eq(s.find_army("beasts-2").location, "ebonpeak")
	assert_eq(s.find_province("westwatch").owner, "kingdom")
	assert_eq(s.find_province("ebonpeak").owner, "beasts")
	assert_true(_army_at(s, "kingdom", "crownkeep") != null, "kingdom recruit formed an army at home")
	assert_true(_army_at(s, "beasts", "fangridge") != null, "beasts recruit formed an army at home")
	assert_eq(_gold(session, "kingdom"), 45 - 8 + 12 + 6)  # 55
	assert_eq(_gold(session, "beasts"), 45 - 11 + 12 + 6)  # 52 (both start with 45 gold; Tuskers cost 11)
	var r1 := session.turn_report()
	assert_eq(r1.header, "Turn 1 results")
	assert_eq(r1.turn, 1)
	var t1 := _types(r1.events)
	for type in ["army_moved", "captured", "recruited", "income"]:
		assert_true(t1.has(type), "turn 1 report has %s" % type)
	assert_eq(session.battle_events(), [])
	_assert_report_shape(r1)
	assert_true(session.handoff_text().contains("Turn 1 is resolved"), session.handoff_text())
	assert_eq(session.acknowledge_handoff(), "")

	# Turn 2: both armies push on to the hill forts on the northern road.
	_play_turn(session, [MoveOrder.new("kingdom-1", "stonegate")], [MoveOrder.new("beasts-2", "blackwood")])
	assert_eq(session.turn_number(), 3)
	s = session.state()
	assert_eq(s.find_army("kingdom-1").location, "stonegate")
	assert_eq(s.find_army("beasts-2").location, "blackwood")
	assert_eq(_gold(session, "kingdom"), 55 + 12 + 6 + 8)  # 81
	assert_eq(_gold(session, "beasts"), 52 + 12 + 6 + 8)  # 78
	assert_eq(session.turn_report().header, "Turn 2 results")
	assert_eq(_types(session.turn_report().events).count("captured"), 2)
	assert_eq(session.acknowledge_handoff(), "")

	# Turn 3: kingdom attacks Blackwood, where the beasts army holds; beasts recruit. The stub battle
	# compares attack + defense totals: since the #4 balance pass the kingdom's starting army has 82 and
	# the beasts' 76, so the attacker wins and the holder is destroyed.
	_play_turn(session, [MoveOrder.new("kingdom-1", "blackwood")], [RecruitOrder.new("war_bear")])
	assert_eq(session.phase(), GameSession.Phase.HANDOFF)
	assert_eq(session.turn_number(), 4)
	s = session.state()
	assert_eq(s.find_army("beasts-2"), null, "the holding army was destroyed")
	assert_eq(s.find_army("kingdom-1").location, "blackwood")
	assert_eq(s.find_province("blackwood").owner, "kingdom", "the winner captures Blackwood")
	assert_eq(_gold(session, "kingdom"), 81 + 12 + 6 + 8 + 8)  # 115, with Blackwood's income
	assert_eq(_gold(session, "beasts"), 78 - 22 + 12 + 6)  # 74: War Bear costs 22, Blackwood is lost
	var battles := session.battle_events()
	assert_eq(battles.size(), 1)
	assert_eq(battles[0].provinces, ["blackwood"])
	assert_eq(battles[0].numbers.winner, "kingdom")
	assert_eq(session.turn_report().header, "Turn 3 results")
	_assert_report_shape(session.turn_report())
	assert_eq(session.turns_played(), 3)
	assert_eq(session.battles_fought(), 1)
	assert_false(session.is_over())
	assert_eq(session.history().size(), 3)


func test_same_seed_and_orders_give_identical_games_and_replay_matches() -> void:
	var a := _session(null, 4242)
	var b := _session(null, 4242)
	for session in [a, b]:
		_play_turn(session, [MoveOrder.new("kingdom-1", "highcrag")], [MoveOrder.new("beasts-2", "ironspike")])
		session.acknowledge_handoff()
		_play_turn(session, [MoveOrder.new("kingdom-1", "thornvale")], [MoveOrder.new("beasts-2", "wildmoor")])
		session.acknowledge_handoff()
		# They swap Thornvale <-> Wildmoor: a border battle the kingdom army wins (82 beats 76).
		_play_turn(session, [MoveOrder.new("kingdom-1", "wildmoor")], [MoveOrder.new("beasts-2", "thornvale")])
	assert_eq(var_to_str(a.state().to_dict()), var_to_str(b.state().to_dict()))
	assert_eq(a.turn_report().events.map(func(e): return e.text), b.turn_report().events.map(func(e): return e.text))
	assert_eq(a.battle_events().size(), 1, "the swap was a border battle")
	assert_eq(a.history(), b.history())

	# Replay from the record, also after a JSON round-trip, rebuilds the live state exactly.
	var replayed := GameSession.replay(a.record(), StubBattleResolver.new())
	assert_eq(replayed.errors, [])
	assert_eq(var_to_str(replayed.state.to_dict()), var_to_str(a.state().to_dict()))
	var json_record = JSON.parse_string(JSON.stringify(a.record()))
	var replayed_json := GameSession.replay(json_record, StubBattleResolver.new())
	assert_eq(replayed_json.errors, [])
	assert_eq(var_to_str(replayed_json.state.to_dict()), var_to_str(a.state().to_dict()))
	assert_eq(replayed_json.events.map(func(e): return e.text),
		a.turn_report().events.map(func(e): return e.text))


func test_turn_seed_matches_turn_resolver_formula() -> void:
	var s := GameState.new(31337)
	assert_eq(GameSession.turn_seed(31337, s.current_turn), TurnResolver.seed_for_turn(s))
	assert_ne(GameSession.turn_seed(31337, 0), GameSession.turn_seed(31337, 1))
	var session := _session(GameState.new(31337), 31337)
	_play_turn(session, [], [])
	assert_eq(session.history()[0].seed, str(TurnResolver.seed_for_turn(s)))


func test_each_player_sees_and_edits_only_their_own_orders() -> void:
	var session := _session()
	assert_eq(session.queue_move("kingdom-1", "westwatch"), "")
	assert_eq(session.queue_recruit("spearmen"), "")
	assert_eq(session.current_orders().size(), 2)
	var lines := session.current_order_texts()
	assert_eq(lines.size(), 2)
	# The army as the map and the turn report name it (TurnReportText.army_title), from where it stands.
	assert_true(lines[0].begins_with("Move %s from Crownkeep to Westwatch" % TurnReportText.army_title(session.state(), session.state().find_army("kingdom-1"), false)), lines[0])
	assert_eq(lines[1], "Recruit Spearmen at Crownkeep for 8 gold.")
	for line in lines:
		_assert_no_raw_ids(line, "order text")
	assert_eq(session.end_turn(), "")
	assert_eq(session.current_orders(), [], "hidden during the handoff")
	assert_eq(session.current_order_texts(), [])
	assert_eq(session.acknowledge_handoff(), "")
	assert_eq(session.current_player(), "beasts")
	assert_eq(session.current_orders(), [], "player 2 can't see player 1's orders")
	assert_ne(session.cancel_order(0), "", "player 2 can't cancel player 1's orders")
	assert_ne(session.queue_move("kingdom-1", "highcrag"), "", "player 2 can't order player 1's army")
	assert_eq(session.end_turn(), "")
	var s := session.state()
	assert_eq(s.find_army("kingdom-1").location, "westwatch", "player 1's orders survived player 2's turn")
	assert_true(_army_at(s, "kingdom", "crownkeep") != null, "player 1's recruit happened")


func test_queue_and_cancel_go_through_order_validation() -> void:
	var session := _session()
	var why := session.queue_move("kingdom-1", "fangridge")
	assert_true(why.contains("not next to"), why)
	assert_true(session.queue_recruit("war_bear").contains("Thornmane Clans"), "not in roster")
	assert_eq(session.queue_recruit("knights"), "")
	assert_eq(session.queue_recruit("knights"), "")
	assert_true(session.queue_recruit("knights").contains("only have 5 gold"), "third knights is too expensive")
	assert_eq(session.current_orders().size(), 2)
	assert_eq(session.cancel_order(1), "")
	assert_eq(session.current_orders().size(), 1)
	assert_true(session.cancel_order(5).contains("no order number 6"), "out of range cancel is explained")
	assert_eq(session.cancel_order(0), "")
	assert_eq(session.current_orders(), [])


func test_wrong_phase_calls_are_rejected_in_plain_language() -> void:
	var session := _session()
	var not_handoff := session.acknowledge_handoff()
	assert_true(not_handoff.contains("already player 1's turn (Aurel Crown)"), not_handoff)
	assert_eq(session.end_turn(), "")
	for why in [session.queue_move("beasts-2", "ebonpeak"), session.cancel_order(0), session.end_turn()]:
		assert_true(why.contains("being passed to player 2 (Thornmane Clans)"), why)
		_assert_no_raw_ids(why, "wrong-phase reason")
	assert_eq(session.phase(), GameSession.Phase.HANDOFF, "rejected calls change nothing")
	assert_eq(session.begin_turn(), "")
	assert_eq(session.phase(), GameSession.Phase.ORDERS)


func test_invalid_setup_is_explained_and_blocks_every_action() -> void:
	var one := GameSession.new(GameState.new(1), ["kingdom"], 1)
	assert_eq(one.phase(), GameSession.Phase.INVALID)
	assert_true(" ".join(one.setup_errors()).contains("at least two players"))
	var dup := GameSession.new(GameState.new(1), ["kingdom", "kingdom"], 1)
	assert_true(" ".join(dup.setup_errors()).contains("Two players are set to Aurel Crown"))
	var unknown := GameSession.new(GameState.new(1), ["kingdom", "elves"], 1)
	assert_true(" ".join(unknown.setup_errors()).contains("Player 2 is set to a faction that is not in this game"))
	var none := GameSession.new(null, ["kingdom", "beasts"], 1)
	assert_false(none.setup_errors().is_empty())
	for session in [one, dup, unknown, none]:
		assert_true(session.queue_recruit("spearmen").contains("could not start"))
		assert_true(session.end_turn().contains("could not start"))
		assert_true(session.acknowledge_handoff().contains("could not start"))


func test_handoff_text_names_the_next_player_without_raw_ids() -> void:
	var session := _session()
	assert_eq(session.handoff_text(), "", "no handoff while ordering")
	session.end_turn()
	var text := session.handoff_text()
	assert_true(text.contains("player 2, who plays Thornmane Clans"), text)
	_assert_no_raw_ids(text, "handoff text")
	var info := session.handoff_info()
	assert_eq(info.seat, 2)
	assert_eq(info.faction_name, "Thornmane Clans")
	assert_false(RulesCodex.text(info.codex).is_empty())
	session.acknowledge_handoff()
	session.end_turn()
	text = session.handoff_text()
	assert_true(text.contains("Turn 1 is resolved") and text.contains("player 1, who plays Aurel Crown"), text)
	_assert_no_raw_ids(text, "new turn handoff text")


# --- the win condition ----------------------------------------------------------------------------

func test_capturing_the_enemy_capital_ends_the_game() -> void:
	# Kingdom army next to an undefended Fangridge; the beasts army is far away in Deepwood.
	var start := _state([
		["kingdom-1", "kingdom", "ebonpeak", ["knights", "knight_captain"]],
		["beasts-2", "beasts", "deepwood", ["tuskers"]],
	], {"ebonpeak": "kingdom", "deepwood": "beasts"})
	var session := _session(start)
	assert_eq(VictoryCheck.check(session.state(), session.players()).over, false, "nobody has won at the start")
	_play_turn(session, [MoveOrder.new("kingdom-1", "fangridge")], [MoveOrder.new("beasts-2", "bloodfen")])
	assert_eq(session.phase(), GameSession.Phase.GAME_OVER)
	assert_true(session.is_over())
	assert_eq(session.winner(), "kingdom")
	var v := session.victory()
	assert_eq(v.winner, "kingdom")
	assert_false(v.draw)
	assert_eq(v.turn, 1)
	assert_eq(v.turns_played, 1)
	assert_eq(v.battles, 0)
	assert_eq(v.provinces_held, {"kingdom": 3, "beasts": 2})  # crownkeep, ebonpeak, fangridge / deepwood, bloodfen
	assert_true(v.text.begins_with("Aurel Crown captured Fangridge, the Thornmane Clans capital, on turn 1."), v.text)
	assert_true(v.text.contains("Aurel Crown wins after 1 turn and 0 battles."), v.text)
	assert_true(v.text.contains("Provinces held: Aurel Crown 3, Thornmane Clans 2."), v.text)
	_assert_no_raw_ids(v.text, "victory summary")

	# The final turn report ends with the victory event.
	var report := session.turn_report()
	var last: Dictionary = report.events.back()
	assert_eq(last.type, "game_over")
	assert_eq(last.phase, "victory")
	assert_eq(last.codex, "victory")
	assert_eq(last.provinces, ["fangridge"])
	assert_eq(last.text, v.text)
	_assert_report_shape(report)
	assert_eq(session.turn_number(), 1, "the turn the game ended on")

	# No more orders or turns once the game is over.
	for why in [session.queue_recruit("spearmen"), session.queue_move("kingdom-1", "ebonpeak"),
			session.cancel_order(0), session.end_turn(), session.acknowledge_handoff()]:
		assert_true(why.contains("The game is over"), why)
	assert_eq(session.current_player(), "")
	assert_eq(session.current_orders(), [])
	assert_eq(session.history().size(), 1)

	# Replaying the record reaches the same final state.
	var replayed := GameSession.replay(session.record(), StubBattleResolver.new())
	assert_eq(var_to_str(replayed.state.to_dict()), var_to_str(session.state().to_dict()))


func test_victory_summary_counts_battles_across_the_whole_game() -> void:
	# Turn 1: kingdom knights (20) beat beasts fangthrowers (12) holding Ebonpeak. Turn 2: into Fangridge.
	var start := _state([
		["kingdom-1", "kingdom", "blackwood", ["knights"]],
		["beasts-2", "beasts", "ebonpeak", ["fangthrowers"]],
		["beasts-3", "beasts", "deepwood", ["tuskers"]],
	], {"blackwood": "kingdom", "ebonpeak": "beasts", "deepwood": "beasts"})
	var session := _session(start)
	_play_turn(session, [MoveOrder.new("kingdom-1", "ebonpeak")], [])
	assert_eq(session.battle_events().size(), 1)
	assert_false(session.is_over())
	session.acknowledge_handoff()
	_play_turn(session, [MoveOrder.new("kingdom-1", "fangridge")], [])
	assert_true(session.is_over())
	var v := session.victory()
	assert_eq(v.battles, 1, "the turn 1 battle counts in the summary")
	assert_eq(v.turns_played, 2)
	assert_true(v.text.contains("on turn 2.") and v.text.contains("after 2 turns and 1 battle."), v.text)


func test_both_capitals_falling_in_the_same_turn_is_a_draw() -> void:
	var start := _state([
		["kingdom-1", "kingdom", "ebonpeak", ["knights"]],
		["beasts-2", "beasts", "westwatch", ["tuskers"]],
	], {"ebonpeak": "kingdom", "westwatch": "beasts"})
	var session := _session(start)
	_play_turn(session, [MoveOrder.new("kingdom-1", "fangridge")], [MoveOrder.new("beasts-2", "crownkeep")])
	assert_eq(session.phase(), GameSession.Phase.GAME_OVER)
	var v := session.victory()
	assert_true(v.draw)
	assert_eq(v.winner, "")
	assert_eq(session.winner(), "")
	assert_eq(v.captures.size(), 2)
	assert_true(v.text.contains("Thornmane Clans captured Crownkeep, the Aurel Crown capital"), v.text)
	assert_true(v.text.contains("Aurel Crown captured Fangridge, the Thornmane Clans capital"), v.text)
	assert_true(v.text.contains("both on turn 1") and v.text.contains("draw"), v.text)
	_assert_no_raw_ids(v.text, "draw summary")
	var last: Dictionary = session.turn_report().events.back()
	assert_eq(last.codex, "simultaneous_capture")
	assert_eq(last.factions, ["beasts", "kingdom"])


func test_victory_check_ignores_capitals_still_held() -> void:
	var s := GameState.new(5)
	var r := VictoryCheck.check(s, ["kingdom", "beasts"])
	assert_false(r.over)
	assert_eq(r.standing, ["beasts", "kingdom"])
	s.find_province("crownkeep").owner = "beasts"
	r = VictoryCheck.check(s, ["kingdom", "beasts"])
	assert_true(r.over)
	assert_eq(r.winner, "beasts")
	assert_eq(r.fallen, [{"faction": "kingdom", "capital": "crownkeep", "captor": "beasts"}])


# --- codex ----------------------------------------------------------------------------------------

func test_every_codex_entry_the_flow_links_exists() -> void:
	for key in GameSession.CODEX_KEYS:
		var e := RulesCodex.entry(key)
		assert_false(String(e.get("title", "")).is_empty(), "codex %s has a title" % key)
		assert_false(String(e.get("text", "")).is_empty(), "codex %s has text" % key)
	assert_true(RulesCodex.text("simultaneous_capture").contains("draw"))
	assert_true(RulesCodex.text("victory").contains("capital"))


func test_report_phases_follow_the_resolver_phases() -> void:
	# REPORT_PHASES is TurnResolver.PHASES plus the victory event's phase; keep them in sync.
	assert_eq(GameSession.REPORT_PHASES.slice(0, TurnResolver.PHASES.size()), TurnResolver.PHASES)
	assert_eq(GameSession.REPORT_PHASES.back(), "victory")
	assert_eq(GameSession.REPORT_PHASES.size(), TurnResolver.PHASES.size() + 1)
