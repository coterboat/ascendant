extends "res://tests/test_case.gd"
## The computer in games with paths (M4-5, #70; design/M4_ASCENSION.md §8): the research plan per build
## preset, the seeded fork on its own stream, research orders with zero rejections, the transformations'
## new units, Forest Stride, captures with path income, the opened mandate in sacrifice picks, notes that
## never name the private research target, and M1/M2 left untouched.

const Simulator := preload("res://tools/autoplay/simulator.gd")
const Policies := preload("res://tools/autoplay/policies.gd")
const SEED := 4343
const SEATS := ["kingdom", "beasts"]
const HUMAN_RNG := 77


# --- fixtures -------------------------------------------------------------------------------------

## A human-vs-computer game with paths, set up the way the game screen does it: the computer seat's build
## is BuildScreen.computer_build (AIPlayer.choose_build on the seed), the human's is `human_build` or its
## faction's balanced preset; `forced` replaces the computer's rolled preset.
func _session(players: Array, ai_fid: String, game_seed: int = SEED, forced: String = "") -> GameSession:
	var builds := {}
	for i in players.size():
		var fid: String = players[i]
		if fid == ai_fid:
			builds[fid] = RulerRules.preset_build(forced) if not forced.is_empty() else BuildScreen.computer_build(fid, game_seed, i)
		else:
			builds[fid] = RulerRules.preset_build(RulerRules.balanced_preset(fid))
	var state := GameState.with_paths(game_seed, builds, [])
	assert_true(state != null, "the builds are legal with paths")
	return GameSession.new(state, players, game_seed, AutoBattleResolver.new(), {ai_fid: "normal"})


## Plays a scripted human (a policy queueing through the session) against the computer for up to `turns`
## turns. `on_turn` (optional) is called with the session and the AISeat after every resolved turn.
func _play(session: GameSession, turns: int, game_seed: int = SEED, human: String = "greedy", on_turn: Callable = Callable()) -> AISeat:
	var computer := AISeat.new(session, game_seed)
	var person = Policies.make(human)
	var rng := SeededRNG.new(HUMAN_RNG)
	computer.play(session)
	if on_turn.is_valid() and session.turns_played() > 0:
		on_turn.call(session, computer)
	for t in turns:
		if session.is_over():
			break
		var fid := session.current_player()
		assert_false(session.is_computer(fid), "the human is up")
		for o in person.orders(session.state(), fid, rng):
			session.queue_order(o)
		assert_eq(session.end_turn(), "")
		computer.play(session)
		if on_turn.is_valid():
			on_turn.call(session, computer)
	return computer


func _orders_of(session: GameSession, fid: String) -> Array:
	var out := []
	for entry in session.history():
		out.append_array(entry.orders.get(fid, []))
	return out


## The preset id the faction plays in `state` (AIPlayer.preset_for).
func _preset_id(state: GameState, fid: String) -> String:
	return String(AIPlayer.preset_for(state, fid).get("id", ""))


## A state with paths whose armies are replaced by `specs`: [[id, owner, location, [unit ids]]] (the rulers'
## armies stay at their capitals), `owners` {province id: faction id} on top of the capitals, and `nodes`
## {faction id: [node ids]} researched (AscensionRules.with_nodes, as the research phase applies them).
func _paths_state(builds: Dictionary, specs: Array, owners: Dictionary = {}, nodes: Dictionary = {}) -> GameState:
	var s := GameState.with_paths(99, builds, [])
	for fid in nodes:
		s = AscensionRules.with_nodes(s, fid, nodes[fid], 0)
	var rulers := []
	for a in s.armies:
		if a.ruler != null:
			rulers.append(a)
	s.armies.clear()
	s.armies.append_array(rulers)
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
				var u := Unit.new(ut, f.id)
				u.current_hp = RulerRules.unit_max_hp(s, u)
				a.units.append(u)
		s.armies.append(a)
	for pid in owners:
		s.find_province(pid).owner = owners[pid]
	return s


## Every id a note must never show: armies, provinces, factions, unit types (the new units too), rulers,
## mandates (the path mandates too), presets, path nodes and sides, and the underscore that joins ids.
func _ids(s: GameState) -> Array:
	var out := ["_"]
	for a in s.armies:
		out.append(a.id)
	for p in s.provinces:
		out.append(p.id)
	for f in s.factions:
		out.append(f.id)
		for ut in f.unit_types:
			out.append(ut.id)
		out.append(f.commander_type.id)
	for uid in PathData.NEW_UNITS:
		out.append(uid)
	for r in RulerData.RULERS:
		out.append(r.id)
	for m in MandateData.MANDATES + MandateData.PATH_MANDATES:
		out.append(m.id)
	for fid in BuildPresetData.PRESETS:
		for p in BuildPresetData.PRESETS[fid]:
			out.append(p.id)
		for nid in AscensionRules.node_ids(fid):
			out.append(nid)
	for b in PathData.BRANCHES:
		out.append(b)
	return out


## Whole-word containment, so "Iron Knights" never counts as an id like "knights" and "Thornthrowers"
## never as a node name.
func _has_word(text: String, word: String) -> bool:
	var at := text.find(word)
	while at >= 0:
		var before := text.substr(at - 1, 1) if at > 0 else " "
		var after := text.substr(at + word.length(), 1)
		var letter := RegEx.create_from_string("[A-Za-z0-9]")
		if letter.search(before) == null and (after.is_empty() or letter.search(after) == null):
			return true
		at = text.find(word, at + 1)
	return false


# --- the plan and the fork (§8.1) -----------------------------------------------------------------

func test_every_build_preset_has_a_research_plan_on_its_own_path() -> void:
	for fid in BuildPresetData.PRESETS:
		for p in BuildPresetData.PRESETS[fid]:
			var plan := AIPaths.plan_for(String(p.id), fid)
			assert_true(AIPaths.AI_PATHS.has(p.id), "%s has an ai_path" % p.name)
			assert_eq(plan.faction, fid)
			var sides := []
			for w in plan.weights:
				sides.append(String(w[0]))
				assert_eq(AscensionRules.branch_data(String(w[0])).faction, fid, "%s: a side of its own fork" % p.name)
				assert_true(int(w[1]) > 0)
			assert_eq(sides.size(), 2, "%s: both sides of the fork can come up" % p.name)
			# Before the fork: ordinary nodes of its own path, each legal once the ones before it are done.
			var done := []
			for nid in plan.before:
				assert_true(AscensionRules.is_ordinary(nid), "%s: %s is an ordinary node" % [p.name, nid])
				assert_eq(String(AscensionRules.node_data(nid).faction), fid)
				for r in AscensionRules.node_data(nid).requires:
					assert_true(done.has(r), "%s: %s comes after %s" % [p.name, nid, r])
				done.append(nid)
			assert_true(plan.before.size() >= 2, "%s: at least the Oath's two ordinary nodes before the fork" % p.name)
			for side in sides:
				var seq := AIPaths.sequence(fid, String(p.id), side)
				var bd := AscensionRules.branch_data(side)
				var expected: Array = plan.before.duplicate()
				expected.append_array([bd.oath, bd.transformation])
				for nid in AscensionRules.node_ids(fid):
					if AscensionRules.is_ordinary(nid) and not expected.has(nid):
						expected.append(nid)
				assert_eq(seq, expected, "%s on %s: listed nodes, Oath, transformation, the rest in data order" % [p.name, side])
	# A custom build gets a stand-in: the tier I nodes, even odds.
	var custom := AIPaths.plan_for("", "beasts")
	assert_eq(custom.before, AscensionRules.node_ids("beasts").filter(func(n): return AscensionRules.node_kind(n) == PathData.TIER1))
	assert_eq(custom.weights.size(), 2)


func test_choose_branch_is_the_salted_first_draw_and_leaves_the_seat_rng_alone() -> void:
	assert_eq(AIPaths.BRANCH_SALT, 7, "§8.1: BRANCH_SALT = 7")
	for fid in BuildPresetData.PRESETS:
		for p in BuildPresetData.PRESETS[fid]:
			var seen := {}
			var weights: Array = AIPaths.plan_for(String(p.id), fid).weights
			var total := 0
			for w in weights:
				total += int(w[1])
			for s in range(1, 41):
				for seat in 2:
					var roll := SeededRNG.new(AISeat.seat_seed(s, seat) + AIPaths.BRANCH_SALT).randi_range(0, total - 1)
					var expected := ""
					for w in weights:
						roll -= int(w[1])
						if roll < 0 and expected.is_empty():
							expected = String(w[0])
					var side := AIPlayer.choose_branch(s, seat, String(p.id))
					assert_eq(side, expected, "%s seed %d seat %d" % [p.name, s, seat])
					assert_eq(AIPlayer.choose_branch(s, seat, String(p.id)), side, "a pure function")
					seen[side] = true
			assert_eq(seen.size(), 2, "%s: both sides come up over 40 seeds" % p.name)
	# The seat's RNG makes the same draws in a game with paths as with rulers alone: one, the build.
	for fid in SEATS:
		var players := ["kingdom", "beasts"]
		var with_paths := _session(players, fid)
		var b := {}
		for f in players:
			b[f] = with_paths.state().find_faction(f)
		var rulers_only := GameSession.new(GameState.with_rulers(SEED, {"kingdom": RulerRules.preset_build(_preset_id(with_paths.state(), "kingdom")),
			"beasts": RulerRules.preset_build(_preset_id(with_paths.state(), "beasts"))}, []), players, SEED, AutoBattleResolver.new(), {fid: "normal"})
		assert_eq(AISeat.new(with_paths, SEED).rng_state(), AISeat.new(rulers_only, SEED).rng_state(), "%s: no extra draw on the seat RNG" % fid)


func test_research_orders_follow_the_plan_and_only_when_the_target_is_off_it() -> void:
	var builds := {"kingdom": RulerRules.preset_build("warrior_king"), "beasts": RulerRules.preset_build("clan_moot")}
	var s := GameState.with_paths(5, builds, [])
	var ai := AIPlayer.new()
	ai.configure(5, 0)
	var side := AIPlayer.choose_branch(5, 0, "warrior_king")
	var seq := AIPaths.sequence("kingdom", "warrior_king", side)
	var orders := ai.plan_orders(s, "kingdom", SeededRNG.new(1))
	var research := orders.filter(func(o): return o is ResearchOrder)
	assert_eq(research.size(), 1, "turn 1: the target is empty, so one research order")
	assert_eq(research[0].node_id, seq[0], "the plan's first node")
	assert_true(AscensionRules.check_research(s, "kingdom", research[0].node_id).is_empty(), "legal")
	# Once that is the target, no order; done, the next one.
	AscensionRules.set_target(s, "kingdom", seq[0])
	assert_true(ai.plan_orders(s, "kingdom", SeededRNG.new(1)).filter(func(o): return o is ResearchOrder).is_empty(), "on plan: no order")
	var t := AscensionRules.with_nodes(s, "kingdom", [seq[0]], 1)
	t.current_turn = 1
	var next := ai.plan_orders(t, "kingdom", SeededRNG.new(1)).filter(func(o): return o is ResearchOrder)
	assert_eq(next.size(), 1)
	assert_eq(next[0].node_id, seq[1])
	# An off-plan target is put back on the plan; after the Oath its transformation is the target already.
	AscensionRules.set_target(t, "kingdom", "crown_stables" if seq[1] != "crown_stables" else "crown_arbalests")
	assert_eq(ai.plan_orders(t, "kingdom", SeededRNG.new(1)).filter(func(o): return o is ResearchOrder)[0].node_id, seq[1])
	var sworn := AscensionRules.with_nodes(s, "kingdom", seq.slice(0, 3), 4)
	sworn.current_turn = 4
	var bd := AscensionRules.branch_data(side)
	AscensionRules.set_target(sworn, "kingdom", bd.transformation)
	assert_true(ai.plan_orders(sworn, "kingdom", SeededRNG.new(1)).filter(func(o): return o is ResearchOrder).is_empty(),
		"after the Oath the transformation is already the target")
	# The sworn side wins over the roll: a faction that swore the other side plans for it.
	var other := AscensionRules.other_branch("kingdom", side)
	var swapped := AscensionRules.with_nodes(s, "kingdom", seq.slice(0, 2) + [AscensionRules.branch_data(other).oath], 4)
	swapped.current_turn = 4
	var o2 := ai.plan_orders(swapped, "kingdom", SeededRNG.new(1)).filter(func(o): return o is ResearchOrder)
	assert_eq(o2[0].node_id, AscensionRules.branch_data(other).transformation)
	# Without paths: never a research order.
	var m2 := GameState.with_rulers(5, builds, [])
	assert_true(ai.plan_orders(m2, "kingdom", SeededRNG.new(1)).filter(func(o): return o is ResearchOrder).is_empty())


# --- whole games ----------------------------------------------------------------------------------

func test_thirty_turns_with_paths_and_no_rejected_computer_orders() -> void:
	var used := {"research": 0, "stride": 0, "new_units": 0, "transformed": 0}
	for fid in SEATS:
		var human_fid: String = "beasts" if fid == "kingdom" else "kingdom"
		for p in RulerRules.presets_for(fid):
			for script in ["greedy", "ai"]:
				var players := [human_fid, fid] if script == "greedy" else [fid, human_fid]
				var session := _session(players, fid, SEED, String(p.id))
				var computer := _play(session, 30, SEED, script)
				var what := "%s as the computer against the %s script" % [p.name, script]
				assert_true(session.turns_played() >= 5, "%s: the game ran (%d turns)" % [what, session.turns_played()])
				assert_true(session.is_over() or session.turns_played() == 30, "%s: 30 turns or a finished game" % what)
				assert_eq(computer.rejections(), [], "%s: the session refused none of the computer's orders" % what)
				var orders := _orders_of(session, fid)
				var state := session.state()
				used.research += orders.filter(func(o): return o.type == "research").size()
				assert_true(orders.any(func(o): return o.type == "research"), "%s: the computer researched" % what)
				if not AscensionRules.transformation(state, fid).is_empty():
					used.transformed += 1
				elif session.turns_played() >= 14:
					fail("%s: no transformation in %d turns" % [what, session.turns_played()])
				for o in orders:
					if o.type == "recruit" and PathData.NEW_UNITS.has(String(o.unit_type)):
						used.new_units += 1
					if o.type == "move" and o.has("via") and fid == "beasts":
						used.stride += 1  # the Clans have no King's Roads: every road move of theirs is Forest Stride
	assert_true(used.transformed >= 6, "the computer transformed in most of the 12 games: %s" % used)
	assert_true(used.new_units > 0, "the computer recruited the transformations' new units: %s" % used)


func test_the_computer_transforms_mid_game_in_20_seeded_games() -> void:
	var turns := []
	for i in 20:
		var seats: Array = SEATS if i % 2 == 0 else [SEATS[1], SEATS[0]]
		var r := Simulator.play_game(100 + i, seats, ["ai", "ai"], 16, Callable(), {"paths": true})
		assert_eq(r.violations, [], "seed %d: no invariant violations" % (100 + i))
		assert_eq(r.rejections, {}, "seed %d: no orders refused" % (100 + i))
		assert_eq(r.errors, [], "seed %d" % (100 + i))
		for fid in r.paths:
			var e: Dictionary = r.paths[fid]
			var t := int(e.transform_turn)
			if t > 0:
				turns.append(t)
			# Every faction still playing on turn 14 has transformed by then (a game can end sooner).
			if int(r.turns) >= 14:
				assert_true(t > 0 and t <= 14, "seed %d: %s transformed by turn 14 (turn %d)" % [100 + i, fid, t])
			assert_false(String(e.branch).is_empty() and int(r.turns) >= 10, "seed %d: %s swore an Oath by turn 10" % [100 + i, fid])
	turns.sort()
	var median: int = turns[turns.size() / 2]
	assert_true(median >= 7 and median <= 12, "transformations land mid-game: median turn %d (%s)" % [median, turns])


func test_the_same_seed_gives_the_same_side_orders_and_game() -> void:
	for fid in SEATS:
		var players := ["kingdom", "beasts"]
		var a := _session(players, fid)
		var b := _session(players, fid)
		var ca := _play(a, 14)
		var cb := _play(b, 14)
		assert_eq(JSON.stringify(a.record()), JSON.stringify(b.record()), "%s: the same record" % fid)
		assert_eq(ca.rng_state(), cb.rng_state())
		var seat := players.find(fid)
		var side := AscensionRules.branch(a.state(), fid)
		assert_false(side.is_empty(), "%s swore an Oath in 14 turns" % fid)
		assert_eq(side, AIPlayer.choose_branch(SEED, seat, _preset_id(a.state(), fid)), "%s: the side is the seat's roll" % fid)
		# The record replays without the computer.
		var replayed := GameSession.replay(JSON.parse_string(JSON.stringify(a.record())), AutoBattleResolver.new())
		assert_eq(JSON.stringify(replayed.state.to_dict()), JSON.stringify(a.state().to_dict()), "%s: the record replays" % fid)


func test_autoplay_paths_mode_forces_sides_and_reports_them() -> void:
	var r := Simulator.play_game(7, SEATS, ["ai", "ai"], 14, Callable(), {"paths": true, "branches": ["living_iron", "blood_pact"]})
	assert_eq(r.violations, [])
	assert_eq(r.rejections, {})
	for fid in r.paths:
		assert_eq(r.paths[fid].branch, "living_iron" if fid == "kingdom" else "blood_pact", "the forced side")
	var md := Simulator.to_markdown(Simulator.summarize([r]))
	assert_true(md.contains("Paths, by side of the fork"), md)
	assert_true(md.contains("Living Iron") and md.contains("Blood Pact"))
	# Without paths: no path section, and the M2 game is the one main plays.
	var m2 := Simulator.play_game(7, SEATS, ["ai", "ai"], 6, Callable(), {"rulers": true})
	assert_eq(m2.paths, {})
	assert_false(Simulator.to_markdown(Simulator.summarize([m2])).contains("Paths, by"))


func test_m1_and_m2_computer_games_play_exactly_as_on_main() -> void:
	# The fixture's games (tools/replay_fixture.gd; recorded on main before paths, re-recorded for #94's computer)
	# played again from scratch with today's computer: every order and every turn's digest must be the same. This is
	# the AI half of "M2 AI games (paths off) are identical to main"; test_paths_off replays the recorded orders.
	const Fixture := preload("res://tools/replay_fixture.gd")
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/main_records.json"))
	var specs := {}
	for g in Fixture.GAMES:
		specs[g.name] = g
	for g in data.games:
		var spec: Dictionary = specs[g.name]
		var seats := ["kingdom", "beasts"]
		var seed_value := int(spec.seed)
		var policies := []
		var rngs := []
		for i in seats.size():
			policies.append(Policies.make(String(spec.policies[i])))
			rngs.append(SeededRNG.new(seed_value * 7919 + (i + 1) * 104729))
		var start := GameState.new(seed_value)
		if spec.rulers:
			var builds := {}
			for i in seats.size():
				builds[seats[i]] = AIPlayer.choose_build(null, seats[i], rngs[i])
				if spec.has("builds"):
					builds[seats[i]] = String(spec.builds[i])
			start = GameState.with_rulers(seed_value, builds, [])
		var session := GameSession.new(start, seats, seed_value, AutoBattleResolver.new())
		var t := 0
		while not session.is_over() and session.turns_played() < Fixture.TURN_CAP:
			for seat in seats.size():
				if session.phase() == GameSession.Phase.HANDOFF:
					session.acknowledge_handoff()
				for o in policies[seat].orders(session.state(), seats[seat], rngs[seat]):
					session.queue_order(o)
				session.end_turn()
			var d := Fixture.digest(session.state(), session.turn_report().get("events", []))
			assert_eq(JSON.stringify(session.history()[t].orders), JSON.stringify(g.record.history[t].orders),
				"%s turn %d: the computer gives the orders it gave on main" % [g.name, t + 1])
			assert_eq(d.state, g.turns[t].state, "%s turn %d: the same state" % [g.name, t + 1])
			t += 1
		assert_eq(t, g.turns.size(), "%s: as many turns as on main" % g.name)
		assert_eq(JSON.stringify(session.state().to_dict()), g.final_state, "%s: the same final state" % g.name)


# --- privacy and notes ------------------------------------------------------------------------------

func test_the_computer_never_reads_a_rivals_research_target() -> void:
	var players := ["kingdom", "beasts"]
	for fid in SEATS:
		var rival: String = "beasts" if fid == "kingdom" else "kingdom"
		var session := _session(players, fid)
		_play(session, 6, SEED, "ai")
		var s := session.state()
		# Poison the rival's private target with every legal node it hasn't researched: nothing may change.
		var baseline := AIPlayer.new()
		baseline.configure(SEED, players.find(fid))
		var want := baseline.plan_orders(s, fid, SeededRNG.new(3)).map(func(o): return JSON.stringify(o.to_dict()))
		var want_notes := baseline.last_plan_notes()
		var poisoned_any := false
		for nid in AscensionRules.node_ids(rival):
			if AscensionRules.has_node(s, rival, nid):
				continue
			var p := s.deep_copy([])
			p.find_faction(rival).research_target = nid
			poisoned_any = true
			var ai := AIPlayer.new()
			ai.configure(SEED, players.find(fid))
			var got := ai.plan_orders(p, fid, SeededRNG.new(3)).map(func(o): return JSON.stringify(o.to_dict()))
			assert_eq(got, want, "%s: the rival's target %s changes no order" % [fid, nid])
			assert_eq(ai.last_plan_notes(), want_notes, "%s: nor any note" % fid)
			for line in ai.last_plan_notes():
				assert_false(_has_word(line, AscensionRules.node_name(nid)) and not AscensionRules.has_node(s, rival, nid)
					and not AscensionRules.has_node(s, fid, nid), "%s: no note names the rival's target %s: %s" % [fid, nid, line])
		assert_true(poisoned_any)


func test_notes_never_name_the_research_target_before_it_is_done_and_show_no_ids() -> void:
	var players := ["kingdom", "beasts"]
	var seen := {"research": 0, "oath": 0, "became": 0}
	for fid in SEATS:
		var check := func(session: GameSession, computer: AISeat) -> void:
			var s := session.state()
			var ids := _ids(s)
			var sworn := AscensionRules.branch(s, fid)
			var next := String(AscensionRules.branch_data(sworn).get("transformation", "")) if not sworn.is_empty() else ""
			for entry in computer.report_notes(session):
				for line in entry.notes:
					var text := String(line)
					for id in ids:
						assert_false(_has_word(text, id) if id != "_" else text.contains("_"), "no raw id '%s' in: %s" % [id, text])
					# Only nodes done by now, and the sworn side's transformation (its Oath's report names it), may appear.
					for nid in AscensionRules.node_ids(fid):
						# Public by now: nodes done, the sworn side's transformation, and the closed side.
						if AscensionRules.has_node(s, fid, nid) or nid == next or AscensionRules.node_state(s, fid, nid).state == AscensionRules.CLOSED:
							continue
						assert_false(_has_word(text, AscensionRules.node_name(nid)),
							"turn %d: a note names %s before it is done: %s" % [session.turns_played(), AscensionRules.node_name(nid), text])
					if text.contains("research"):
						seen.research += 1
					if text.begins_with("We swore"):
						seen.oath += 1
						# Plain words for the fork's roll (#55, #94): no "seeded".
						assert_false(text.contains("seeded"), text)
						assert_true(text.contains("we picked our side of the fork by a roll"), text)
					if text.begins_with("We became"):
						seen.became += 1
		var session := _session(players, fid)
		_play(session, 14, SEED, "greedy" if fid == "beasts" else "ai", check)
	assert_true(seen.research > 0 and seen.oath >= 2 and seen.became >= 2, "the notes explain research, Oaths and transformations: %s" % seen)


# --- using what it has (§8.2) ---------------------------------------------------------------------

func test_forest_stride_marches_through_our_forest() -> void:
	var builds := {"kingdom": RulerRules.preset_build("warrior_king"), "beasts": RulerRules.preset_build("clan_moot")}
	var owners := {"ironspike": "beasts", "wildmoor": "beasts", "ebonpeak": "beasts", "bloodfen": "beasts", "deepwood": "beasts", "blackwood": "beasts"}
	var s := _paths_state(builds, [["beasts-9", "beasts", "ironspike", ["tuskers", "tuskers", "war_bear"]], ["kingdom-9", "kingdom", "crownkeep", ["spearmen"]]],
		owners, {"beasts": ["beasts_raiding", "beasts_forest_stride"]})
	var ai := AIPlayer.new()
	var orders := ai.plan_orders(s, "beasts", SeededRNG.new(2))
	var stride := orders.filter(func(o): return o is MoveOrder and o.army_id == "beasts-9")
	assert_eq(stride.size(), 1, "the army moves")
	assert_eq(stride[0].via, "wildmoor", "through our forest")
	assert_eq(TurnResolver.road_rule(s, "beasts", stride[0]), "forest_stride")
	assert_true(TurnResolver.check_move(s, "beasts", stride[0]).is_empty(), "legal")
	assert_true(ai.last_plan_notes().any(func(n): return n.begins_with("Using Forest Stride") and n.contains("Wildmoor")), str(ai.last_plan_notes()))
	# Without Forest Stride: one step.
	var plain := _paths_state(builds, [["beasts-9", "beasts", "ironspike", ["tuskers", "tuskers", "war_bear"]], ["kingdom-9", "kingdom", "crownkeep", ["spearmen"]]],
		owners, {"beasts": ["beasts_raiding"]})
	var step := AIPlayer.new().plan_orders(plain, "beasts", SeededRNG.new(2)).filter(func(o): return o is MoveOrder and o.army_id == "beasts-9")
	assert_true(step.is_empty() or step[0].via.is_empty())


func test_road_moves_count_as_threats_with_paths() -> void:
	# A Crown army in a forest two provinces from a Clans army with Forest Stride is not "safe" any more.
	var builds := {"kingdom": RulerRules.preset_build("warrior_king"), "beasts": RulerRules.preset_build("clan_moot")}
	var owners := {"wildmoor": "beasts", "deepwood": "beasts", "ironspike": "beasts", "greenglade": "kingdom", "rivermarch": "kingdom"}
	var specs := [["beasts-9", "beasts", "ironspike", ["tuskers", "tuskers", "tuskers", "war_bear", "war_bear"]],
		["kingdom-9", "kingdom", "rivermarch", ["spearmen"]]]
	var with_stride := _paths_state(builds, specs, owners, {"beasts": ["beasts_raiding", "beasts_forest_stride"]})
	var without := _paths_state(builds, specs, owners, {"beasts": ["beasts_raiding"]})
	var a := AIPlayer.new()
	a._begin(with_stride, "kingdom", SeededRNG.new(1), "normal")
	var threats := a._threats_to("thornvale")
	assert_true(threats.any(func(e): return e.id == "beasts-9"), "Ironspike → Wildmoor → Thornvale by Forest Stride counts")
	var b := AIPlayer.new()
	b._begin(without, "kingdom", SeededRNG.new(1), "normal")
	assert_false(b._threats_to("thornvale").any(func(e): return e.id == "beasts-9"), "no Forest Stride, no threat")
	# Without paths the threat check is exactly "next to it".
	var m2 := GameState.with_rulers(99, builds, [])
	var c := AIPlayer.new()
	c._begin(m2, "kingdom", SeededRNG.new(1), "normal")
	assert_eq(c._threats_to("highcrag"), c._foes_next_to("highcrag"))


func test_new_traits_are_valued_with_the_battle_rules_constants() -> void:
	var s := GameState.with_paths(99, {}, [])
	s = AscensionRules.with_nodes(s, "kingdom", ["crown_drillyard", "crown_charters", "crown_oath_dawn", "crown_celestial_host"], 0)
	s = AscensionRules.with_nodes(s, "beasts", ["beasts_boar_hide", "beasts_raiding", "beasts_oath_grove", "beasts_thorn_wild"], 0)
	var crown := s.find_faction("kingdom")
	var clans := s.find_faction("beasts")
	var seraph := Unit.new(TurnResolver.recruitable_type(crown, "seraphs"), "kingdom")
	var knight := Unit.new(TurnResolver.recruitable_type(crown, "knights"), "kingdom")
	var warden := Unit.new(TurnResolver.recruitable_type(clans, "briarwardens"), "beasts")
	var tusker := Unit.new(TurnResolver.recruitable_type(clans, "tuskers"), "beasts")
	var chief := Unit.new(clans.commander_type, "beasts")
	# Wings: the foe's commander bonuses count for less while our Wings stand (WINGS_COMMANDER_THREAT).
	var led := AIPlayer._side_summary([tusker, tusker, chief])
	var with_wings := AIPlayer._side_summary([seraph, knight])
	var no_wings := AIPlayer._side_summary([seraph, knight])
	no_wings.wings = 0
	assert_true(AIPlayer._trait_power(led, with_wings) < AIPlayer._trait_power(led, no_wings), "Wings weaken a commander-led foe")
	var leaderless := AIPlayer._side_summary([tusker, tusker])
	assert_eq(AIPlayer._trait_power(leaderless, with_wings), AIPlayer._trait_power(leaderless, no_wings), "no commander, nothing to dive at")
	# Rooted: its ROOTED_DEFENSE counts by the forest share of the front.
	var forest := AIPlayer._side_summary([warden], {"forest_share": 1.0})
	var open := AIPlayer._side_summary([warden], {"forest_share": 0.0})
	assert_eq(forest.def_hp - open.def_hp, float(warden.current_hp) * AutoBattleResolver.ROOTED_DEFENSE)
	# Iron Hide: IRON_HIDE_DAMAGE off every hit hurts small hits most.
	var hidden := AIPlayer._side_summary([knight, knight])
	var plated := hidden.duplicate(true)
	plated.iron_hide_hp = plated.hp
	var small := AIPlayer._side_summary([tusker])
	var big := AIPlayer._side_summary([Unit.new(TurnResolver.recruitable_type(clans, "war_bear"), "beasts")])
	var small_loss := 1.0 - AIPlayer._trait_power(small, plated) / AIPlayer._trait_power(small, hidden)
	var big_loss := 1.0 - AIPlayer._trait_power(big, plated) / AIPlayer._trait_power(big, hidden)
	assert_true(small_loss > 0.0 and big_loss > 0.0)
	assert_true(small_loss >= big_loss, "small hits lose the most to Iron Hide (%.2f vs %.2f)" % [small_loss, big_loss])
	# Lifedrinker: a Bloodsworn is worth more than the same numbers without it.
	var b := GameState.with_paths(99, {}, [])
	b = AscensionRules.with_nodes(b, "beasts", ["beasts_boar_hide", "beasts_raiding", "beasts_oath_blood", "beasts_blood_pact"], 0)
	var sworn_type := TurnResolver.recruitable_type(b.find_faction("beasts"), "bloodsworn")
	var plain_type := UnitType.new()
	for k in ["id", "name", "hp", "attack", "defense", "morale", "cost", "is_commander"]:
		plain_type.set(k, sworn_type.get(k))
	plain_type.id = "plain"
	var foe := AIPlayer._side_summary([knight, knight])
	assert_true(AIPlayer._trait_power(AIPlayer._side_summary([Unit.new(sworn_type, "beasts")]), foe) >
		AIPlayer._trait_power(AIPlayer._side_summary([Unit.new(plain_type, "beasts")]), foe), "Lifedrinker heals")


func test_captures_read_path_income_and_raiding_parties() -> void:
	var builds := {"kingdom": RulerRules.preset_build("warrior_king"), "beasts": RulerRules.preset_build("clan_moot")}
	var s := _paths_state(builds, [["beasts-9", "beasts", "deepwood", ["tuskers", "tuskers"]], ["kingdom-9", "kingdom", "crownkeep", ["spearmen"]]],
		{"deepwood": "beasts"}, {"beasts": ["beasts_raiding", "beasts_boar_hide", "beasts_oath_grove"]})
	var ai := AIPlayer.new()
	ai._begin(s, "beasts", SeededRNG.new(1), "normal")
	var glade := s.find_province("greenglade")  # forest, neutral
	var fen := s.find_province("bloodfen")  # plains, neutral
	assert_eq(ai._income_if_ours(glade), glade.income + 2, "Bounty of the Wild: a forest earns 2 more")
	assert_eq(ai._income_if_ours(fen), fen.income, "no line for plains")
	assert_eq(ai._raid_gold(glade), float(2 * glade.income), "Raiding Parties: twice its income")
	assert_eq(ai._capture_worth(glade), float(glade.income + 2) + AIPlayer.RAID_WEIGHT * 2 * glade.income)
	# The capture note names both.
	assert_true(ai._capture_note(glade).contains("Bounty of the Wild") and ai._capture_note(glade).contains("Raiding Parties"), ai._capture_note(glade))


func test_the_opened_mandate_comes_last_and_a_forsworn_one_is_skipped() -> void:
	# Beast-God Unbound sacrifices for Iron Discipline, then Blood Frenzy; the Thorn Wild forswears Blood
	# Frenzy and opens Deep Roots. With Iron Discipline owned, the next pick is Deep Roots.
	var builds := {"kingdom": RulerRules.preset_build("warrior_king"), "beasts": RulerRules.preset_build("beast_god_unbound")}
	var owners := {}
	for p in ["westwatch", "stonegate", "highcrag", "rivermarch", "greenglade", "thornvale", "wildmoor", "blackwood", "ebonpeak", "ironspike"]:
		owners[p] = "kingdom"
	var s := _paths_state(builds, [["beasts-9", "beasts", "fangridge", ["tuskers", "tuskers"]], ["kingdom-9", "kingdom", "crownkeep", ["spearmen"]]],
		owners, {"beasts": ["beasts_boar_hide", "beasts_raiding", "beasts_oath_grove", "beasts_thorn_wild"]})
	s = RulerRules.with_sacrifice(s, "beasts", "iron_discipline")
	s.current_turn = 9  # from turn 8, falling behind on income is a trigger
	assert_false(RulerRules.sacrifice_check(s, "beasts", "blood_frenzy").is_empty(), "Blood Frenzy is forsworn")
	var ai := AIPlayer.new()
	var orders := ai.plan_orders(s, "beasts", SeededRNG.new(1))
	var sac := orders.filter(func(o): return o is SacrificeOrder)
	assert_eq(sac.size(), 1, "it sacrifices: %s" % str(ai.last_plan_notes()))
	assert_eq(sac[0].mandate_id, "deep_roots", "the opened mandate, after the forsworn pick")
	assert_true(ai.last_plan_notes().any(func(n): return n.contains("Deep Roots") and n.contains("the Thorn Wild opened it")), str(ai.last_plan_notes()))
	_assert_all_accepted(s, "beasts", orders)


func _assert_all_accepted(s: GameState, fid: String, orders: Array) -> void:
	var book := OrderBook.new()
	for o in orders:
		assert_eq(book.submit(s, fid, o), "", "%s is accepted" % o.describe())


func test_the_computer_recruits_new_units_and_says_why() -> void:
	# Celestial Host against Blood of the Fang (Iron Discipline: its sides hold while a commander stands)
	# with two commander-led armies: Seraphs, whose Wings dive at commanders, are in the plan, with a reason.
	var builds := {"kingdom": RulerRules.preset_build("warrior_king"), "beasts": RulerRules.preset_build("blood_of_the_fang")}
	var specs := [["kingdom-9", "kingdom", "crownkeep", ["knight_captain", "spearmen", "spearmen", "knights"]],
		["beasts-9", "beasts", "stonegate", ["warchief", "tuskers", "tuskers", "fangthrowers", "war_bear"]],
		["beasts-10", "beasts", "greenglade", ["warchief", "tuskers", "fangthrowers"]]]
	var s := _paths_state(builds, specs, {"stonegate": "beasts", "greenglade": "beasts"},
		{"kingdom": ["crown_drillyard", "crown_charters", "crown_oath_dawn", "crown_celestial_host"]})
	s.find_faction("kingdom").gold = 300
	var ai := AIPlayer.new()
	var orders := ai.plan_orders(s, "kingdom", SeededRNG.new(1))
	_assert_all_accepted(s, "kingdom", orders)
	var units := orders.filter(func(o): return o is RecruitOrder).map(func(o): return o.unit_type_id)
	assert_true(units.has("seraphs"), "Seraphs against two commanders with Iron Discipline: %s" % str(units))
	assert_true(ai.last_plan_notes().any(func(n): return n.contains("Seraphs") and n.contains("Wings") and n.contains("2 commanders")), str(ai.last_plan_notes()))
	# Trait-aware: the same Seraph is worth more against those commanders than against leaderless armies.
	var probe := AIPlayer.new()
	probe._begin(s, "kingdom", SeededRNG.new(1), "normal")
	var crown := s.find_faction("kingdom")
	var seraph := probe._recruit_unit(TurnResolver.recruitable_type(crown, "seraphs"))
	var home := [probe._recruit_unit(TurnResolver.recruitable_type(crown, "spearmen")), probe._recruit_unit(TurnResolver.recruitable_type(crown, "knights"))]
	var led := probe._units(probe._foes)
	var leaderless := led.filter(func(u): return not u.type.is_commander and not u.type.is_ruler)
	var gain_led := probe._recruit_value(home + [seraph], led) / probe._recruit_value(home, led)
	var gain_free := probe._recruit_value(home + [seraph], leaderless) / probe._recruit_value(home, leaderless)
	assert_true(gain_led > gain_free, "Wings are worth more against commanders (%.3f vs %.3f)" % [gain_led, gain_free])
