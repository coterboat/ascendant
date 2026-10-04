extends SceneTree
## Writes tests/fixtures/main_records.json: recorded AI-vs-AI games (M1, and M2 with rulers) with a
## digest of every turn's state and events and the final state, as the engine on `main` plays them.
##   godot --headless --path . -s tools/replay_fixture.gd [-- --note "why it was re-recorded"]
## M4-1 (#66) made the file on `main` at f98c8b5 (after the M3 battle log), before paths existed. tests/test_paths_off.gd replays
## each record with the current engine and checks every turn is byte-identical, so a later change that
## alters an M1 or M2 game (paths off) fails a test. Re-run this only when such a change is intended.
##
## The file holds AI games, so a change to the computer (ai/) may shift them while the rules stay the same
## (#94 did). Before writing, this replays every record already in the file with the current engine from its
## stored orders: if all of them still match turn by turn, the rules are unchanged and only the computer's
## choices are re-recorded; if one doesn't, the rules changed too and nothing is written (`-- --force` writes
## anyway). `-- --note TEXT` adds why the games were re-recorded to the file's note.
##
## M5-0 (#111, design/M5_MAGIC_FOG.md §1.3, §18): `-- --m5` writes tests/fixtures/m5_base_records.json instead,
## from M5_GAMES: M1, M2 and M4 (paths) games, each with the spec it was played from, so a test can rerun the AI
## policy loop (play) and compare the computer's orders turn by turn. tests/test_m5_fields.gd, and later
## test_fog_off.gd and test_magic_off.gd, replay it. Record it on `main`, before the change it guards, with
## FIXTURE_COMMIT set to main's commit so the note names it:
##   FIXTURE_COMMIT=04a130a godot --headless --path . -s tools/replay_fixture.gd -- --m5
## An AI change outside M5 (such as #94) re-records it in a commit of its own, with `-- --m5 --note TEXT`.

const Policies := preload("res://tools/autoplay/policies.gd")
const OUT := "res://tests/fixtures/main_records.json"
const M5_OUT := "res://tests/fixtures/m5_base_records.json"
const TURN_CAP := 30

## {name, seed, rulers, policies, builds (optional preset ids, kingdom first)}: two seats, kingdom first.
const GAMES := [
	{"name": "m1_ai_vs_ai", "seed": 404, "rulers": false, "policies": ["ai", "ai"]},
	{"name": "m1_greedy_vs_ai", "seed": 77, "rulers": false, "policies": ["greedy", "ai"]},
	{"name": "m2_ai_vs_ai_rulers", "seed": 2026, "rulers": true, "policies": ["ai", "ai"]},
	{"name": "m2_ai_vs_ai_rulers_b", "seed": 31, "rulers": true, "policies": ["ai", "ai"]},
	{"name": "m2_keep_presets_sacrifice", "seed": 9, "rulers": true, "policies": ["ai", "ai"],
		"builds": ["warrior_king", "beast_god_unbound"]},
]

## The M5 base games (`-- --m5`), as GAMES plus, for M4, `paths` true and `branches` (each seat's forced side of
## the fork, "" to roll it). A paths game is set up as tools/autoplay/simulator.gd sets one up: with_paths, each
## seat's build the first draw of its RNG (unless `builds` names presets), and each policy configured with the
## seed, its seat and its side. Seeds differ from the other fixtures so these are new games.
const M5_GAMES := [
	{"name": "m1_ai_vs_ai", "seed": 1201, "rulers": false, "policies": ["ai", "ai"]},
	{"name": "m1_greedy_vs_ai", "seed": 88, "rulers": false, "policies": ["greedy", "ai"]},
	{"name": "m2_ai_vs_ai_rulers", "seed": 1707, "rulers": true, "policies": ["ai", "ai"]},
	{"name": "m2_regents_court_vs_blood_of_the_fang", "seed": 64, "rulers": true, "policies": ["ai", "ai"],
		"builds": ["regents_court", "blood_of_the_fang"]},
	{"name": "m2_keep_presets_sacrifice", "seed": 12, "rulers": true, "policies": ["ai", "ai"],
		"builds": ["warrior_king", "beast_god_unbound"]},
	{"name": "m4_ai_vs_ai_rolled", "seed": 606, "rulers": true, "paths": true, "policies": ["ai", "ai"],
		"branches": ["", ""]},
	{"name": "m4_celestial_host_vs_thorn_wild", "seed": 1111, "rulers": true, "paths": true, "policies": ["ai", "ai"],
		"branches": ["celestial_host", "thorn_wild"]},
	{"name": "m4_living_iron_vs_blood_pact", "seed": 47, "rulers": true, "paths": true, "policies": ["ai", "ai"],
		"branches": ["living_iron", "blood_pact"], "builds": ["regents_court", "blood_of_the_fang"]},
]


const FIRST_NOTE := "Recorded on main (f98c8b5) by tools/replay_fixture.gd for M4-1 (#66). Do not edit by hand."
const M5_FIRST_NOTE := "Recorded on main (%s) by tools/replay_fixture.gd -- --m5 for M5-0 (#111): M1, M2 and M4 games with the computer's orders, before magic and fog of war. Do not edit by hand."


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var m5 := args.has("--m5")
	var out_path := M5_OUT if m5 else OUT
	var note := ""
	var i := args.find("--note")
	if i >= 0 and i + 1 < args.size():
		note = args[i + 1]
	var old := check_existing(out_path)
	print(old.text)
	if not old.ok and not args.has("--force"):
		printerr("replay_fixture: not written. The rules changed, not just the computer's choices (-- --force writes anyway).")
		quit(1)
		return
	var games := []
	for g in (M5_GAMES if m5 else GAMES):
		var game := play(g)
		if m5:
			game["spec"] = g  # the M5 file says how each game was played, so a test reruns the AI from the file alone
		games.append(game)
	var first := FIRST_NOTE
	if m5:
		var commit := OS.get_environment("FIXTURE_COMMIT")
		first = M5_FIRST_NOTE % (commit if not commit.is_empty() else "commit not given")
	var checked: String = old.text if old.ok else "Written with --force: %s" % old.text
	var out := {"note": first if note.is_empty() else "%s Re-recorded: %s %s Do not edit by hand." % [
		first.trim_suffix(" Do not edit by hand."), note, checked], "games": games}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out) + "\n")
	f.close()
	for g in games:
		print("%s: %d turns, final state %s" % [g.name, g.turns.size(), String(g.final_state).md5_text()])
	quit(0)


## Plays one game of GAMES or M5_GAMES with the AI policy loop, as the engine and the computer play it now:
## {"name", "record" (GameSession.record()), "turns" (a digest per turn), "final_state" (its JSON)}. Pure and
## deterministic: the same spec always gives the same game, so a test can rerun it and compare the orders.
static func play(g: Dictionary) -> Dictionary:
	var seats := ["kingdom", "beasts"]
	var seed_value := int(g.seed)
	var with_paths := bool(g.get("paths", false))
	var policies := []
	var rngs := []
	for i in seats.size():
		var policy = Policies.make(String(g.policies[i]))
		if with_paths:
			policy.configure(seed_value, i, String(g.branches[i]))  # as tools/autoplay/simulator.gd does
		policies.append(policy)
		rngs.append(SeededRNG.new(seed_value * 7919 + (i + 1) * 104729))
	var start := GameState.new(seed_value)
	if g.rulers or with_paths:
		var builds := {}
		for i in seats.size():
			builds[seats[i]] = AIPlayer.choose_build(null, seats[i], rngs[i])  # the seat RNG's first draw, as in AISeat
			if g.has("builds"):
				builds[seats[i]] = String(g.builds[i])
		start = GameState.with_paths(seed_value, builds, []) if with_paths else GameState.with_rulers(seed_value, builds, [])
	var session := GameSession.new(start, seats, seed_value, AutoBattleResolver.new())
	var turns := []
	while not session.is_over() and session.turns_played() < TURN_CAP:
		for seat in seats.size():
			if session.phase() == GameSession.Phase.HANDOFF:
				session.acknowledge_handoff()
			var view := session.state()
			for o in policies[seat].orders(view, seats[seat], rngs[seat]):
				session.queue_order(o)
			session.end_turn()
		turns.append(digest(session.state(), session.turn_report().get("events", [])))
	return {"name": g.name, "record": session.record(), "turns": turns,
		"final_state": JSON.stringify(session.state().to_dict())}


## Replays every record in the fixture at `path` with the current engine from its stored orders, turn by
## turn, as tests/test_paths_off.gd does: {"ok": every turn of every record matches, "text": what was found}.
static func check_existing(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true, "text": "No earlier fixture to check."}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary):
		return {"ok": false, "text": "The earlier fixture does not load."}
	var games: Array = data.get("games", [])
	var turns := 0
	for g in games:
		var state := GameState.from_dict(g.record.start_state, [])
		if state == null:
			return {"ok": false, "text": "%s: its start state no longer loads." % g.name}
		for t in g.record.history.size():
			var entry: Dictionary = g.record.history[t]
			var result := TurnResolver.resolve(state, OrderBook.orders_from_dict(entry.orders, []), Serial.to_int(entry.seed), AutoBattleResolver.new())
			state = result.new_state
			var d := digest(state, result.events)
			if d.state != String(g.turns[t].state) or d.events != String(g.turns[t].events):
				return {"ok": false, "text": "%s turn %d no longer replays identically." % [g.name, t + 1]}
			turns += 1
	return {"ok": true, "text": "The %d earlier records (%d turns) replayed identically from their stored orders, so the rules are unchanged." % [games.size(), turns]}


## What a test compares for one resolved turn: md5 of the state's JSON and of the resolver's events'
## JSON (the turn report without the victory event GameSession adds on the last turn).
static func digest(state: GameState, events: Array) -> Dictionary:
	var resolved := events.filter(func(e): return str(e.get("phase", "")) != "victory")
	return {"state": JSON.stringify(state.to_dict()).md5_text(), "events": JSON.stringify(resolved).md5_text()}
