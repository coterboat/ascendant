extends SceneTree
## Writes tests/fixtures/m4_path_records.json: recorded AI-vs-AI games with paths (M4), with a digest of every
## turn's state and events and the final state, as the engine on `main` plays them.
##   godot --headless --path . -s tools/replay_fixture_paths.gd
## M3c S-1a (#98, design/M3C_SIEGES.md §1.3) records it on `main` before forts and sieges exist, the way
## tools/replay_fixture.gd recorded the M1 and M2 games for M4-1. tests/test_sieges_off.gd replays each record
## with the current engine and checks every turn is byte-identical, so a later change that alters an M4 game
## (sieges off) fails a test. Re-run this only on `main`, and only when such a change is intended.
## The games are set up exactly as tools/autoplay/simulator.gd sets up a paths game: each seat's build is the
## first draw of its policy RNG (AIPlayer.choose_build), and each policy is told the seed, its seat and the side
## of the fork it is forced to (or "" to roll it).

const Policies := preload("res://tools/autoplay/policies.gd")
const Fixture := preload("res://tools/replay_fixture.gd")
const OUT := "res://tests/fixtures/m4_path_records.json"
const TURN_CAP := 30

## {name, seed, branches: [kingdom's side, beasts' side] ("" rolls it)}: two seats, kingdom first, both AIPlayer.
const GAMES := [
	{"name": "m4_ai_vs_ai_rolled", "seed": 404, "branches": ["", ""]},
	{"name": "m4_celestial_host_vs_thorn_wild", "seed": 2026, "branches": ["celestial_host", "thorn_wild"]},
	{"name": "m4_living_iron_vs_blood_pact", "seed": 31, "branches": ["living_iron", "blood_pact"]},
	{"name": "m4_celestial_host_vs_blood_pact", "seed": 9, "branches": ["celestial_host", "blood_pact"]},
]


func _initialize() -> void:
	var games := []
	for g in GAMES:
		games.append(_play(g))
	var commit := OS.get_environment("FIXTURE_COMMIT")
	var out := {"note": "M4 path games recorded on main%s by tools/replay_fixture_paths.gd for M3c S-1a (#98). Do not edit by hand." % (
		" (%s)" % commit if not commit.is_empty() else ""), "games": games}
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
	var builds := {}
	for i in seats.size():
		var policy = Policies.make("ai")
		policy.configure(seed_value, i, String(g.branches[i]))
		policies.append(policy)
		rngs.append(SeededRNG.new(seed_value * 7919 + (i + 1) * 104729))
		builds[seats[i]] = AIPlayer.choose_build(null, seats[i], rngs[i])  # the seat RNG's first draw, as in AISeat
	var start := GameState.with_paths(seed_value, builds, [])
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
		turns.append(Fixture.digest(session.state(), session.turn_report().get("events", [])))
	return {"name": g.name, "record": session.record(), "turns": turns,
		"final_state": JSON.stringify(session.state().to_dict())}
