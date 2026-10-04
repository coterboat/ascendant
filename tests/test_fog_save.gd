extends "res://tests/test_case.gd"
## M5-1 (#112) acceptance, the save story (design/M5_MAGIC_FOG.md §2.1, §2.5, §2.11, §18):
## - memory and intel are rebuilt identically after load (they are never saved: the replay loading already runs
##   rebuilds them), and so are each seat's view, view before and report;
## - a record replayed with "fog" stripped (and the per-faction army numbers, #94's next_army_ids, kept) gives the
##   same states and events: the resolver never reads fog;
## - a fog game's save holds the truth and no new key but "fog";
## - the resolver never reads GameState.fog (a static scan of rules/);
## - memory's cost on load (§2.5's budget: 0.2 s for a 60-turn game on the build box; a wall-clock check, so it runs
##   with -- --perf only).

const Kit := preload("res://tests/fog_test_kit.gd")


func _json(v) -> String:
	return JSON.stringify(v.to_dict() if v is GameState else v)


func test_memory_and_intel_are_rebuilt_identically_after_load() -> void:
	for gi in [0, 1, 2, 3, 5, 7]:
		var g: Dictionary = Kit.games()[gi]
		var session: GameSession = g.session
		var save := SaveGame.make(session, {}, SaveGame.MANUAL, "fog", 1000)
		var text := JSON.stringify(save)
		var restored := SaveGame.restore(JSON.parse_string(text), AutoBattleResolver.new())
		assert_eq(restored.errors, [], "%s: the save loads" % g.name)
		var loaded: GameSession = restored.session
		if loaded == null:
			continue
		for v in Kit.SEATS:
			assert_eq(JSON.stringify(loaded.memory(v)), JSON.stringify(session.memory(v)), "%s, %s: memory rebuilt" % [g.name, v])
			assert_eq(JSON.stringify(loaded.intel(v)), JSON.stringify(session.intel(v)), "%s, %s: intel rebuilt" % [g.name, v])
			assert_eq(_json(loaded.state_for(v)), _json(session.state_for(v)), "%s, %s: the same view" % [g.name, v])
			assert_eq(_json(loaded.view_before(v)), _json(session.view_before(v)), "%s, %s: the same view before" % [g.name, v])
			assert_eq(JSON.stringify(loaded.turn_report_for(v)), JSON.stringify(session.turn_report_for(v)), "%s, %s: the same report" % [g.name, v])
			assert_false(session.memory(v).is_empty() or session.intel(v).is_empty(), "%s: there was something to rebuild" % g.name)


func test_a_fog_save_holds_the_truth_and_no_new_key() -> void:
	var g: Dictionary = Kit.games()[2]
	var session: GameSession = g.session
	var rec := session.record()
	assert_eq(rec.keys(), ["start_state", "players", "game_seed", "history", "builds"], "the record's parts, as any game's")
	assert_eq(rec.start_state.get("fog"), true, "the start state says fog")
	var plain: Dictionary = rec.start_state.duplicate(true)
	plain.erase("fog")
	var again := GameState.from_dict(plain, [])
	assert_false(again.fog, "without the key, the same game without fog")
	again.fog = true
	assert_eq(JSON.stringify(JSON.parse_string(JSON.stringify(again.to_dict()))), JSON.stringify(JSON.parse_string(JSON.stringify(rec.start_state))),
		"fog is the only new key")
	var header := SaveGame.header(session, SaveGame.AUTO, "", 1000)
	assert_false(JSON.stringify(header).contains("seen-") or JSON.stringify(header).contains("gold"), "the header is fog-safe")


func test_a_fog_record_replays_identically_with_fog_stripped() -> void:
	for g in Kit.games():
		var rec: Dictionary = g.session.record()
		var stripped: Dictionary = rec.duplicate(true)
		stripped.start_state.erase("fog")
		var with_fog := GameState.from_dict(rec.start_state, [])
		var without := GameState.from_dict(stripped.start_state, [])
		assert_true(with_fog.fog and not without.fog)
		assert_eq(JSON.stringify(with_fog.next_army_ids), JSON.stringify(without.next_army_ids), "the per-faction army numbers are kept")
		for i in rec.history.size():
			var entry: Dictionary = rec.history[i]
			var orders := OrderBook.orders_from_dict(entry.orders, [])
			var a := TurnResolver.resolve(with_fog, orders, Serial.to_int(entry.seed), AutoBattleResolver.new())
			var b := TurnResolver.resolve(without, OrderBook.orders_from_dict(entry.orders, []), Serial.to_int(entry.seed), AutoBattleResolver.new())
			with_fog = a.new_state
			without = b.new_state
			var da: Dictionary = with_fog.to_dict()
			assert_eq(da.get("fog"), true)
			da.erase("fog")
			assert_eq(JSON.stringify(da), JSON.stringify(without.to_dict()), "%s turn %d: the same state" % [g.name, i + 1])
			assert_eq(JSON.stringify(a.events), JSON.stringify(b.events), "%s turn %d: the same events" % [g.name, i + 1])
		var replayed := GameSession.replay(stripped, AutoBattleResolver.new())
		var final_state: Dictionary = g.session.state().to_dict()
		final_state.erase("fog")
		assert_eq(JSON.stringify(replayed.state.to_dict()), JSON.stringify(final_state), "%s: GameSession.replay agrees" % g.name)


func test_the_resolver_never_reads_fog() -> void:
	# Fog is a lens (§2.1): outside the fog rules, the state's own fields and the session's per-viewer doors, no rules
	# code mentions it.
	var allowed := ["fog_rules.gd", "game_state.gd", "game_session.gd", "rules_codex.gd"]
	var reads := RegEx.create_from_string("\\.fog\\b|has_fog|FogRules\\.|FogData\\.")
	var dir := DirAccess.open("res://rules")
	var scanned := 0
	for file in dir.get_files():
		if not file.ends_with(".gd") or allowed.has(file):
			continue
		var code := PackedStringArray()
		for line in FileAccess.get_file_as_string("res://rules/" + file).split("\n"):
			var hash_at := line.find("#")
			code.append(line if hash_at < 0 else line.substr(0, hash_at))  # comments may name the fog rules
		scanned += 1
		for m in reads.search_all("\n".join(code)):
			fail("rules/%s reads fog: %s" % [file, m.get_string()])
	assert_true(scanned > 20, "the scan saw the rules (%d files)" % scanned)


func test_memory_costs_little_on_load() -> void:
	# A quiet 60-turn fog game: both sides recruit every turn and march their armies back and forth.
	var start := GameState.new(60)
	start.setup_fog([])
	var session := GameSession.new(start, Kit.SEATS, 60, AutoBattleResolver.new())
	while session.turns_played() < 60:
		for fid in Kit.SEATS:
			if session.phase() == GameSession.Phase.HANDOFF:
				session.acknowledge_handoff()
			session.queue_order(RecruitOrder.new(session.state().find_faction(fid).unit_types[0].id))
			session.end_turn()
	var rec := session.record()
	var plain := rec.duplicate(true)
	plain.start_state.erase("fog")
	var with_fog := 0.0
	var without := 0.0
	with_fog = best_ms(func(): GameSession.from_record(rec, AutoBattleResolver.new()), 3)
	without = best_ms(func(): GameSession.from_record(plain, AutoBattleResolver.new()), 3)
	var loaded: GameSession = GameSession.from_record(rec, AutoBattleResolver.new()).session
	assert_eq(JSON.stringify(loaded.memory("kingdom")), JSON.stringify(session.memory("kingdom")), "rebuilt identically")
	assert_perf(with_fog - without <= 200.0, "memory and intel for 60 turns cost %.0f ms on load (%.0f with fog, %.0f without; budget 200)" % [
		with_fog - without, with_fog, without])
