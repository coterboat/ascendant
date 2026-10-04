## The game the 3D preview shows, from the real rules (pure: no nodes). The default M1 start, or a
## game autoplayed by the real AIPlayer for both factions through the real TurnResolver, so the map
## has several armies and a real turn to play back.
##
##   var turns := Scenario.autoplay(seed, n)   # [{"before": GameState, "orders", "events", "after"}]
##   var moves := Scenario.moves_of(turn)      # the army_moved events as {"army", "from", "to", "faction"}
extends RefCounted


static func start(game_seed: int = 12345) -> GameState:
	return GameState.new(game_seed)


## Plays `n` turns with an AIPlayer ordering for every faction. Each entry holds the state before
## the turn, the orders, the turn's events and the state after it. Deterministic from the seed.
static func autoplay(game_seed: int, n: int) -> Array:
	var out: Array = []
	var state := GameState.new(game_seed)
	for t in n:
		var orders := {}
		var ai := AIPlayer.new()
		var seat := 0
		for f in state.factions:
			var rng := SeededRNG.new(game_seed * 7919 + (seat + 1) * 104729 + t * 31)
			orders[f.id] = ai.plan_orders(state, f.id, rng, "normal")
			seat += 1
		var res: Dictionary = TurnResolver.resolve(state, orders, TurnResolver.seed_for_turn(state))
		var after: GameState = res.get("new_state")
		if after == null:
			break
		out.append({"before": state, "orders": orders, "events": res["events"], "after": after})
		state = after
		if _over(after):
			break
	return out


static func _over(s: GameState) -> bool:
	for f in s.factions:
		var cap := s.find_province(f.capital)
		if cap == null or cap.owner != f.id:
			return true
	return false


## The moves of a turn, as the 3D map plays them: every army_moved event (a road move goes by its
## `via`), and whether the army still stands at the end of the turn (or fell in a battle there).
static func moves_of(turn: Dictionary) -> Array:
	var after: GameState = turn["after"]
	var out: Array = []
	for e in turn["events"]:
		if e["type"] != "army_moved":
			continue
		var provs: Array = e["provinces"]
		out.append({"army": e["armies"][0], "faction": e["factions"][0], "from": provs[0], "to": provs[provs.size() - 1],
			"via": provs.slice(1, provs.size() - 1), "survived": after.find_army(e["armies"][0]) != null})
	return out


## The battles of a turn: [{"province", "kind", "text"}].
static func battles_of(turn: Dictionary) -> Array:
	var out: Array = []
	for e in turn["events"]:
		if e["type"] in ["battle", "border_battle"]:
			out.append({"provinces": e["provinces"], "kind": e["type"], "text": e["text"]})
	return out


## The turn (index into `turns`) whose playback shows the most: the latest with an army leaving a
## capital, else the latest with any move.
static func best_turn(turns: Array) -> int:
	var best := -1
	for i in turns.size():
		var s: GameState = turns[i]["before"]
		for m in moves_of(turns[i]):
			var p := s.find_province(m["from"])
			if p != null and p.is_capital:
				best = i
	if best >= 0:
		return best
	for i in range(turns.size() - 1, -1, -1):
		if not moves_of(turns[i]).is_empty():
			return i
	return 0


## Unit type ids of an army, one per unit (the commander and a ruler separately).
static func unit_types(a: Army) -> Array:
	var out: Array = []
	for u in a.units:
		out.append(u.type.id)
	return out


static func commander_type(a: Army) -> String:
	if a.commander != null:
		return a.commander.type.id
	if a.ruler != null:
		return "knight_captain" if a.owner == "kingdom" else "warchief"
	return ""
