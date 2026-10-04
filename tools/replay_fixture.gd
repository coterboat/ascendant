extends SceneTree
## Writes tests/fixtures/main_records.json: recorded AI-vs-AI games (M1, and M2 with rulers) with a
## digest of every turn's state and events and the final state, as the engine on `main` plays them.
##   godot --headless --path . -s tools/replay_fixture.gd
## M4-1 (#66) made the file on `main` at f98c8b5 (after the M3 battle log), before paths existed. tests/test_paths_off.gd replays
## each record with the current engine and checks every turn is byte-identical, so a later change that
## alters an M1 or M2 game (paths off) fails a test. Re-run this only when such a change is intended.

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


func _initialize() -> void:
	var games := []
	for g in GAMES:
		games.append(_play(g))
	var out := {"note": "Recorded on main (f98c8b5) by tools/replay_fixture.gd for M4-1 (#66). Do not edit by hand.",
		"games": games}
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


## What a test compares for one resolved turn: md5 of the state's JSON and of the resolver's events'
## JSON (the turn report without the victory event GameSession adds on the last turn).
static func digest(state: GameState, events: Array) -> Dictionary:
	var resolved := events.filter(func(e): return str(e.get("phase", "")) != "victory")
	return {"state": JSON.stringify(state.to_dict()).md5_text(), "events": JSON.stringify(resolved).md5_text()}
