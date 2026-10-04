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

const Policies := preload("res://tools/autoplay/policies.gd")
const OUT := "res://tests/fixtures/main_records.json"
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


const FIRST_NOTE := "Recorded on main (f98c8b5) by tools/replay_fixture.gd for M4-1 (#66). Do not edit by hand."


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var note := ""
	var i := args.find("--note")
	if i >= 0 and i + 1 < args.size():
		note = args[i + 1]
	var old := check_existing(OUT)
	print(old.text)
	if not old.ok and not args.has("--force"):
		printerr("replay_fixture: not written. The rules changed, not just the computer's choices (-- --force writes anyway).")
		quit(1)
		return
	var games := []
	for g in GAMES:
		games.append(_play(g))
	var checked: String = old.text if old.ok else "Written with --force: %s" % old.text
	var out := {"note": FIRST_NOTE if note.is_empty() else "%s Re-recorded: %s %s Do not edit by hand." % [
		FIRST_NOTE.trim_suffix(" Do not edit by hand."), note, checked], "games": games}
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(out) + "\n")
	f.close()
	for g in games:
		print("%s: %d turns, final state %s" % [g.name, g.turns.size(), String(g.final_state).md5_text()])
	quit(0)


func _play(g: Dictionary) -> Dictionary:
	var seats := ["kingdom", "beasts"]
	var seed_value := int(g.seed)
	var policies := []
	var rngs := []
	for i in seats.size():
		policies.append(Policies.make(String(g.policies[i])))
		rngs.append(SeededRNG.new(seed_value * 7919 + (i + 1) * 104729))
	var start := GameState.new(seed_value)
	if g.rulers:
		var builds := {}
		for i in seats.size():
			builds[seats[i]] = AIPlayer.choose_build(null, seats[i], rngs[i])  # the seat RNG's first draw, as in AISeat
			if g.has("builds"):
				builds[seats[i]] = String(g.builds[i])
		start = GameState.with_rulers(seed_value, builds, [])
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
