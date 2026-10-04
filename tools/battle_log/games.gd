extends RefCounted
## AI-vs-AI games with rulers for the battle log's checks and measurements (M3-1, #56). Plays a real
## GameSession exactly as tools/autoplay/simulator.gd does with `--rulers --p1 ai --p2 ai` (the same
## policies, policy seeds and build rolls), and keeps every battle's log as it was recorded during the
## game, before the next turn replaced it, so tests and tools/battle_log.gd can compare it with
## BattleLog.regenerate.
##
##   var g := Games.play(seed)   # {"record", "battles": [{"turn", "index", "log", "report"}], "turns", "ms", "errors"}

const Simulator := preload("res://tools/autoplay/simulator.gd")
const Policies := preload("res://tools/autoplay/policies.gd")
const SEATS := ["kingdom", "beasts"]


## The seat order of game `game_seed` in the checks: Aurel Crown first in odd games, the Clans first in
## even ones, so both seat orders are played.
static func seats_for(game_seed: int) -> Array:
	return SEATS.duplicate() if game_seed % 2 == 1 else [SEATS[1], SEATS[0]]


## Plays one AI-vs-AI game with rulers on `game_seed` (both seats AIPlayer "normal", builds rolled as an
## AI seat rolls them), to a capital capture or `turn_cap` turns. "ms" is the time the game took.
static func play(game_seed: int, turn_cap: int = Simulator.TURN_CAP, seats: Array = SEATS) -> Dictionary:
	var started := Time.get_ticks_msec()
	var out := {"record": {}, "battles": [], "turns": 0, "ms": 0, "errors": []}
	var policies := []
	var rngs := []
	var builds := {}
	for i in seats.size():
		policies.append(Policies.make("ai"))
		rngs.append(SeededRNG.new(Simulator.policy_seed(game_seed, i)))
		builds[seats[i]] = AIPlayer.choose_build(null, seats[i], rngs[i])  # the seat RNG's first draw, as in AISeat
	var errors := []
	var start := GameState.with_rulers(game_seed, builds, errors)
	if start == null:
		out.errors = errors
		return out
	var session := GameSession.new(start, seats, game_seed, AutoBattleResolver.new())
	if session.phase() == GameSession.Phase.INVALID:
		out.errors = session.setup_errors()
		return out
	while not session.is_over() and session.turns_played() < turn_cap:
		var turn := session.turn_number()
		for seat in seats.size():
			if session.phase() == GameSession.Phase.HANDOFF:
				session.acknowledge_handoff()
			var fid: String = seats[seat]
			var view := session.state()
			for order in policies[seat].orders(view, fid, rngs[seat]):
				session.queue_order(order)
			var why := session.end_turn()
			if not why.is_empty():
				out.errors.append("Turn %d, seat %d: %s" % [turn, seat + 1, why])
				out.record = session.record()
				return out
		var battles := session.battle_events()
		for i in battles.size():
			out.battles.append({"turn": turn, "index": i, "log": battles[i].numbers.get("log", {}), "report": battles[i].numbers.report})
	out.record = session.record()
	out.turns = session.turns_played()
	out.ms = Time.get_ticks_msec() - started
	return out
