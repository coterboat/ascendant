extends "res://tests/test_case.gd"
## ARM-1 (design/ARM1_SPLIT_MERGE.md §6): the computer never musters in ARM-1, and a human's musters reach it as ordinary armies.
## It plans from the real state (its view, under fog) every turn, so a human's splits, merges and swaps change which armies it
## sees and nothing else. The audit: every id-keyed cache of the brain is made afresh each plan (ai/ai_player.gd _begin, ai_sieges
## attach, ai_magic attach). The fixtures: a scripted human who splits, marches the halves, merges and swaps commanders every turn
## against the computer, in a plain game, with rulers and paths, under fog with magic, and with sieges: the computer's orders are
## never refused, it orders no muster, and the game replays to the same state.

const Kit := preload("res://tests/muster_test_kit.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const SEED := 4242
const TURNS := 8


func _session(kind: String) -> GameSession:
	var s: GameState
	match kind:
		"m1":
			s = GameState.new(SEED)
		"rulers":
			s = GameState.with_paths(SEED)
		"fog":
			s = GameState.with_magic(SEED, {CROWN: "regents_court", CLANS: "blood_of_the_fang"})
			s.setup_fog([])
		_:
			s = GameState.with_sieges(SEED, {}, {"rulers": true})
	return GameSession.new(s, [CROWN, CLANS], SEED, AutoBattleResolver.new(), {CLANS: "normal"})


## The scripted human, from the true state: split the biggest field army of the Crown in half and march the half; merge the
## smallest two armies sharing a province; swap the commanders of two that have one each. Orders the rules refuse are skipped.
func _human_turn(session: GameSession, turn: int) -> Array:
	var queued := []
	var s := session.state()
	var by_place := {}
	for a in s.armies:
		if a.owner == CROWN and a.ruler == null:
			if not by_place.has(a.location):
				by_place[a.location] = []
			by_place[a.location].append(a)
	var places: Array = by_place.keys()
	places.sort()
	for pid in places:
		var here: Array = by_place[pid]
		here.sort_custom(func(x, y): return x.id < y.id)
		match turn % 4:
			1:
				var big: Army = here.back()
				for a in here:
					if a.units.size() > big.units.size():
						big = a
				if big.units.size() >= 2:
					var half := []
					for i in big.units.size() / 2:
						half.append(i)
					var order := MusterOrder.transfer(big.id, "", half, false)
					if session.queue_order(order).is_empty():
						queued.append(order)
						var p := s.find_province(pid)
						var dest := String(p.neighbors[0])
						var new_id := String(s.peek_army_ids(CROWN, 1)[0])
						var move := MoveOrder.new(new_id, dest)
						if session.queue_order(move).is_empty():
							queued.append(move)
			2:
				if here.size() >= 2:
					var order2 := MusterOrder.merge(here[0].id, here[1].id)
					if session.queue_order(order2).is_empty():
						queued.append(order2)
			3:
				var with_cmd := here.filter(func(a): return a.commander != null)
				if with_cmd.size() >= 2:
					var order3 := MusterOrder.swap(with_cmd[0].id, with_cmd[1].id)
					if session.queue_order(order3).is_empty():
						queued.append(order3)
			_:
				if here.size() >= 1:
					var m := MoveOrder.new(here[0].id, String(s.find_province(pid).neighbors.back()))
					if session.queue_order(m).is_empty():
						queued.append(m)
	var r := RecruitOrder.new(s.find_faction(CROWN).unit_types[0].id)
	if session.queue_order(r).is_empty():
		queued.append(r)
	return queued


## Plays the scripted Crown against the computer's Clans. Returns {"session", "computer", "musters"}: how many musters the human got through.
func _play(kind: String) -> Dictionary:
	var session := _session(kind)
	var computer := AISeat.new(session, SEED)
	computer.play(session)
	var musters := 0
	for t in TURNS:
		if session.is_over():
			break
		if session.phase() == GameSession.Phase.HANDOFF:
			session.acknowledge_handoff()
		for o in _human_turn(session, session.turn_number()):
			if o is MusterOrder:
				musters += 1
		assert_eq(session.end_turn(), "", "the human's turn %d ends" % session.turn_number())
		computer.play(session)
	return {"session": session, "computer": computer, "musters": musters}


# --- the computer never musters -----------------------------------------------------------------------------

func test_the_computer_orders_no_muster_and_none_of_its_orders_is_refused() -> void:
	for kind in ["m1", "rulers", "fog", "sieges"]:
		var run := _play(kind)
		var session: GameSession = run.session
		assert_true(session.turns_played() >= 3, "%s: the game ran" % kind)
		assert_true(run.musters >= 2, "%s: the human mustered %d times" % [kind, run.musters])
		var computer: AISeat = run.computer
		assert_eq(computer.rejections(), [], "%s: the computer's orders are never refused, whatever the human mustered" % kind)
		for turn in session.history():
			for fid in turn.orders:
				for o in turn.orders[fid]:
					if fid == CLANS:
						assert_ne(String(o.type), "muster", "%s: the computer orders no muster" % kind)
		var errors := []
		assert_true(session.state().validate(errors), "%s: the state is valid after the game: %s" % [kind, errors])


func test_a_game_with_a_human_who_musters_replays_to_the_same_state() -> void:
	for kind in ["m1", "fog"]:
		var run := _play(kind)
		var session: GameSession = run.session
		var rec: Dictionary = JSON.parse_string(JSON.stringify(session.record()))
		var replayed := GameSession.replay(rec, AutoBattleResolver.new())
		assert_eq(replayed.errors, [], "%s: replay has no complaints" % kind)
		assert_eq(JSON.stringify(replayed.state.to_dict()), JSON.stringify(session.state().to_dict()), "%s: replay gives the same state" % kind)
		var loaded := GameSession.from_record(rec, AutoBattleResolver.new())
		assert_eq(loaded.errors, [], "%s: loading has no complaints" % kind)
		assert_eq(JSON.stringify(loaded.session.state().to_dict()), JSON.stringify(session.state().to_dict()), "%s: loading gives the same state" % kind)


# --- the audit of the id-keyed caches ------------------------------------------------------------------------

func test_every_id_keyed_cache_of_the_brain_is_made_afresh_each_plan() -> void:
	var s := GameState.with_sieges(SEED, {}, {"rulers": true})
	var a := Kit.army(s, CLANS, "ebonpeak", ["tuskers", "tuskers", "war_bear"], "warchief")
	var brain := AIPlayer.new()
	brain.configure(SEED, 1)
	brain.plan_orders(s, CLANS, SeededRNG.new(1), "normal")
	assert_true(brain._busy.has(a.id), "the first plan gave the army a job")
	# The next turn the Crown splits and merges: ids appear and disappear on the enemy side, and a plan on that state must hold
	# nothing from the plan before.
	var t := s.deep_copy()
	var crown := t.find_army("kingdom-1")
	var shed := MusterRules.apply(t, CROWN, MusterOrder.transfer(crown.id, "", [0, 1]))
	assert_true(shed.ok)
	var gone_id := String(shed.info.to)
	t.current_turn += 1
	brain.plan_orders(t, CLANS, SeededRNG.new(2), "normal")
	var ours := {}
	for army in t.armies:
		ours[army.id] = true
	for cache in [brain._moves, brain._busy, brain._vias, brain._cache, brain._threat_cache, brain._foe_cache, brain._sieges._kept]:
		for key in cache:
			if String(key).begins_with("kingdom-") or String(key).begins_with("beasts-"):
				assert_true(ours.has(key), "a cache entry %s names an army that stands in this plan's state" % key)
	brain._begin(t, CLANS, SeededRNG.new(2), "normal")  # a plan's first step reads the armies afresh
	assert_true(brain._foes.any(func(f): return f.id == gone_id), "the new army is a foe like any other")
	for army in brain._foes:
		assert_true(ours.has(army.id), "the foes are read from this state")
	# And the next turn the fragment merges back: its id is gone from every cache.
	var u := t.deep_copy()
	assert_true(MusterRules.apply(u, CROWN, MusterOrder.merge(gone_id, crown.id)).ok)
	u.current_turn += 1
	brain.plan_orders(u, CLANS, SeededRNG.new(3), "normal")
	for cache in [brain._moves, brain._busy, brain._vias, brain._cache, brain._threat_cache, brain._foe_cache, brain._sieges._kept]:
		assert_false(cache.has(gone_id), "nothing keeps the merged army's id")
	brain._begin(u, CLANS, SeededRNG.new(3), "normal")
	assert_false(brain._foes.any(func(f): return f.id == gone_id), "and the merged army is no foe now")


func test_the_plan_of_a_state_is_the_same_whether_the_brain_planned_something_else_first() -> void:
	# A brain that has seen other armies plans a state exactly as a fresh brain does.
	var s := GameState.with_sieges(SEED, {}, {"rulers": true})
	var t := s.deep_copy()
	MusterRules.apply(t, CROWN, MusterOrder.transfer("kingdom-1", "", [0, 1]))
	var used := AIPlayer.new()
	used.configure(SEED, 1)
	used.plan_orders(s, CLANS, SeededRNG.new(5), "normal")
	var fresh := AIPlayer.new()
	fresh.configure(SEED, 1)
	var a: Array = used.plan_orders(t, CLANS, SeededRNG.new(6), "normal")
	var b: Array = fresh.plan_orders(t, CLANS, SeededRNG.new(6), "normal")
	assert_eq(JSON.stringify(a.map(func(o): return o.to_dict())), JSON.stringify(b.map(func(o): return o.to_dict())), "no cache from the first plan reaches the second")
