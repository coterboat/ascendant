extends RefCounted
## Order policies for the headless autoplay simulator (tools/autoplay/autoplay.gd, the M1 play-script).
##
## A policy plays one seat. orders(state, faction_id, rng) reads the start-of-turn state, takes every
## random choice from `rng`, walks armies and provinces in sorted id order, and returns the
## MoveOrder / RecruitOrder objects to queue. It never changes `state`. Every move is checked with
## TurnResolver.check_move and every recruit with TurnResolver.price_recruits (the checks GameSession's
## OrderBook runs), so a policy only returns orders the rules accept. `stats` counts what the policy
## did (odds calls, attacks held back, ...) for the simulator's report.
##
##   greedy  recruits the best affordable mix every turn (see best_recruits), keeps one army home when
##           an enemy army stands next to its capital, and marches every other army one step along the
##           shortest path to the enemy capital. Armies in the same province move together, and
##           followers take the road their most advanced army is on. A step into a province holding
##           enemy armies is skipped (the armies hold) when Forecast.battle_odds calls it a
##           "likely loss", unless that province is the enemy capital, which greedy always attacks.
##   random  every army holds or moves to a random neighbor; recruits random affordable units.
##   turtle  recruits like greedy, keeps its strongest army in the capital, walks the others home, and
##           only attacks adjacent enemy armies that Forecast.battle_odds calls a "likely win".
##
##   var policy = Policies.make("greedy")
##   var orders: Array = policy.orders(state, "kingdom", SeededRNG.new(7))

const NAMES := ["greedy", "random", "turtle"]


## A new policy by name, or null for an unknown name.
static func make(policy_name: String) -> Base:
	match policy_name:
		"greedy":
			return Greedy.new()
		"random":
			return RandomPolicy.new()
		"turtle":
			return Turtle.new()
	return null


class Base extends RefCounted:
	var policy_name := "base"
	## What the policy did, summed over the game: {counter name: int}.
	var stats := {}

	func orders(_state: GameState, _faction_id: String, _rng: SeededRNG) -> Array:
		return []

	func bump(key: String, by: int = 1) -> void:
		stats[key] = int(stats.get(key, 0)) + by

	## Moves from `plan` ({army id: destination}) that TurnResolver.check_move accepts, by army id.
	func checked_moves(state: GameState, faction_id: String, plan: Dictionary) -> Array:
		var ids: Array = plan.keys()
		ids.sort()
		var ordered := {}
		var out := []
		for id in ids:
			var order := MoveOrder.new(str(id), str(plan[id]))
			if TurnResolver.check_move(state, faction_id, order, ordered).is_empty():
				ordered[order.army_id] = true
				out.append(order)
			else:
				bump("dropped_invalid")
		return out

	## Recruit orders for the best mix `faction_id` can afford with its gold minus `reserve`: the
	## combination with the largest total unit_value (an unbounded knapsack over the roster), with at
	## most one commander. Each order is checked with TurnResolver.price_recruits, in order.
	static func best_recruits(state: GameState, faction_id: String, reserve: int = 0) -> Array:
		var f := state.find_faction(faction_id)
		if f == null:
			return []
		var budget := f.gold - reserve
		if budget <= 0:
			return []
		var types: Array = []
		for ut in f.unit_types:
			if ut.cost > 0:
				types.append(ut)
		var plan := knapsack(types, budget)
		var cmd := f.commander_type
		if cmd != null and cmd.cost > 0 and cmd.cost <= budget:
			var with_cmd: Array = [cmd]
			with_cmd.append_array(knapsack(types, budget - cmd.cost))
			if total_value(with_cmd) > total_value(plan):
				plan = with_cmd
		var out := []
		for ut in plan:
			var order := RecruitOrder.new(ut.id)
			var trial := out.duplicate()
			trial.append(order)
			if TurnResolver.price_recruits(state, faction_id, trial).results.back().ok:
				out.append(order)
		return out

	## Unit types (repeats allowed) with the largest total unit_value costing at most `budget`.
	## Ties keep the earlier roster entry, so the answer is deterministic.
	static func knapsack(types: Array, budget: int) -> Array:
		if budget <= 0 or types.is_empty():
			return []
		var best := PackedInt64Array()
		best.resize(budget + 1)
		var pick := PackedInt32Array()
		pick.resize(budget + 1)
		pick[0] = -1
		for g in range(1, budget + 1):
			best[g] = best[g - 1]
			pick[g] = -1  # one gold left unspent
			for i in types.size():
				var ut: UnitType = types[i]
				if ut.cost <= g:
					var v: int = best[g - ut.cost] + unit_value(ut)
					if v > best[g]:
						best[g] = v
						pick[g] = i
		var out := []
		var g := budget
		while g > 0:
			if pick[g] < 0:
				g -= 1
			else:
				var ut: UnitType = types[pick[g]]
				out.append(ut)
				g -= ut.cost
		return out

	## Value of one unit for recruiting: hp x attack, the measure behind the battle report's "bigger
	## force" reason (AutoBattleResolver side power = hp x attack).
	static func unit_value(ut: UnitType) -> int:
		return ut.hp * ut.attack

	static func total_value(types: Array) -> int:
		var total := 0
		for ut in types:
			total += unit_value(ut)
		return total

	## `faction_id`'s armies, sorted by id.
	static func armies_of(state: GameState, faction_id: String) -> Array:
		var out := []
		for a in state.armies:
			if a.owner == faction_id:
				out.append(a)
		out.sort_custom(func(x, y): return x.id < y.id)
		return out

	## Armies of other factions in `province_id`.
	static func enemies_at(state: GameState, province_id: String, faction_id: String) -> Array:
		var out := []
		for a in state.armies:
			if a.location == province_id and a.owner != faction_id:
				out.append(a)
		return out

	static func sorted_neighbors(state: GameState, province_id: String) -> Array:
		var p := state.find_province(province_id)
		if p == null:
			return []
		var out: Array = p.neighbors.duplicate()
		out.sort()
		return out

	## Steps from `from_id` to every reachable province (breadth-first over neighbors).
	static func distances(state: GameState, from_id: String) -> Dictionary:
		var dist := {from_id: 0}
		var queue: Array = [from_id]
		var i := 0
		while i < queue.size():
			var pid: String = queue[i]
			i += 1
			for n in sorted_neighbors(state, pid):
				if not dist.has(n):
					dist[n] = int(dist[pid]) + 1
					queue.append(n)
		return dist

	## The capital of the first other faction in sorted id order: where to march.
	static func enemy_capital(state: GameState, faction_id: String) -> String:
		var ids := []
		for f in state.factions:
			if f.id != faction_id:
				ids.append(f.id)
		if ids.is_empty():
			return ""
		ids.sort()
		return state.find_faction(ids[0]).capital

	## Current hp x attack of every unit and the commander.
	static func power(army: Army) -> int:
		var total := 0
		for u in army.units:
			total += u.current_hp * u.type.attack
		if army.commander:
			total += army.commander.current_hp * army.commander.type.attack
		return total

	## The army with the most power (the first by id on a tie), or null.
	static func strongest(armies: Array) -> Army:
		var best: Army = null
		for a in armies:
			if best == null or power(a) > power(best):
				best = a
		return best

	## The neighbor of `from_id` closest to the target of `dist`, or "" when no step gets closer.
	## Ties: closest by `prefer` (steps to another province), then a roll of `rng`.
	static func step_toward(state: GameState, from_id: String, dist: Dictionary, prefer: Dictionary, rng: SeededRNG) -> String:
		var here: int = dist.get(from_id, 999)
		var best: Array = []
		var best_key := 999999
		for n in sorted_neighbors(state, from_id):
			if int(dist.get(n, 999)) >= here:
				continue
			var k: int = prefer.get(n, 999)
			if k < best_key:
				best_key = k
				best = [n]
			elif k == best_key:
				best.append(n)
		if best.is_empty():
			return ""
		if best.size() == 1:
			return best[0]
		return best[rng.randi_range(0, best.size() - 1)]


class Greedy extends Base:
	## Most Forecast.battle_odds calls per turn (each one fights the real battle 24 times). Beyond it,
	## the attack goes ahead and stats["odds_capped"] counts it.
	var odds_cap := 6
	## Gold kept back every turn (0: spend it all).
	var reserve := 0

	func _init() -> void:
		policy_name = "greedy"

	func orders(state: GameState, faction_id: String, rng: SeededRNG) -> Array:
		var me := state.find_faction(faction_id)
		if me == null:
			return []
		var target := enemy_capital(state, faction_id)
		var armies := armies_of(state, faction_id)
		var plan := {}
		if not target.is_empty() and not armies.is_empty():
			plan = _march(state, faction_id, me, target, armies, rng)
		var out := checked_moves(state, faction_id, plan)
		out.append_array(best_recruits(state, faction_id, reserve))
		return out

	func _march(state: GameState, faction_id: String, me: Faction, target: String, armies: Array, rng: SeededRNG) -> Dictionary:
		var to_target := distances(state, target)
		var spear: Army = armies[0]
		for a in armies:
			if int(to_target.get(a.location, 999)) < int(to_target.get(spear.location, 999)):
				spear = a
		var to_spear := distances(state, spear.location)
		var plan := {}
		var holding := {}
		# Home defense: one army stays home (or the strongest one next door comes back) while an
		# enemy army stands next to the capital.
		var near_home := sorted_neighbors(state, me.capital)
		var threatened := false
		for n in near_home:
			if not enemies_at(state, n, faction_id).is_empty():
				threatened = true
		if threatened:
			var home := armies.filter(func(a): return a.location == me.capital)
			if not home.is_empty():
				holding[strongest(home).id] = true
				bump("kept_home")
			else:
				var near := armies.filter(func(a): return near_home.has(a.location))
				if not near.is_empty():
					plan[strongest(near).id] = me.capital
					bump("recalled_home")
		# Everyone else marches. Armies sharing a province share one step.
		var step_from := {}
		for a in armies:
			if holding.has(a.id) or plan.has(a.id):
				continue
			if not step_from.has(a.location):
				step_from[a.location] = step_toward(state, a.location, to_target, to_spear, rng)
			var step: String = step_from[a.location]
			if not step.is_empty():
				plan[a.id] = step
		_hold_back_bad_attacks(state, faction_id, target, plan)
		return plan

	## Drops planned moves into enemy-held provinces that Forecast.battle_odds calls a "likely loss"
	## for all the armies going there together. The enemy capital is always attacked.
	func _hold_back_bad_attacks(state: GameState, faction_id: String, target: String, plan: Dictionary) -> void:
		var groups := {}
		var ids: Array = plan.keys()
		ids.sort()
		for id in ids:
			var dest: String = plan[id]
			if not groups.has(dest):
				groups[dest] = []
			groups[dest].append(id)
		var dests: Array = groups.keys()
		dests.sort()
		var calls := 0
		for dest in dests:
			if dest == target or enemies_at(state, dest, faction_id).is_empty():
				continue
			if calls >= odds_cap:
				bump("odds_capped")
				continue
			calls += 1
			bump("odds_calls")
			var odds := Forecast.battle_odds(state, faction_id, groups[dest], dest)
			if odds.get("ok", false) and odds.get("label", "") == "likely loss":
				for id in groups[dest]:
					plan.erase(id)
					bump("held_back")


class RandomPolicy extends Base:
	## Most recruit orders per turn.
	var max_recruits := 12

	func _init() -> void:
		policy_name = "random"

	func orders(state: GameState, faction_id: String, rng: SeededRNG) -> Array:
		var plan := {}
		for a in armies_of(state, faction_id):
			var options: Array = [""]
			options.append_array(sorted_neighbors(state, a.location))
			var pick: String = options[rng.randi_range(0, options.size() - 1)]
			if not pick.is_empty():
				plan[a.id] = pick
		var out := checked_moves(state, faction_id, plan)
		out.append_array(_random_recruits(state, faction_id, rng))
		return out

	## Picks uniformly among the affordable roster entries plus "stop", until it stops or is broke.
	func _random_recruits(state: GameState, faction_id: String, rng: SeededRNG) -> Array:
		var f := state.find_faction(faction_id)
		if f == null:
			return []
		var roster: Array = f.unit_types.duplicate()
		if f.commander_type:
			roster.append(f.commander_type)
		var out := []
		var gold := f.gold
		for _i in max_recruits:
			var affordable := roster.filter(func(ut): return ut.cost <= gold)
			if affordable.is_empty():
				break
			var pick := rng.randi_range(0, affordable.size())
			if pick == affordable.size():
				break
			var order := RecruitOrder.new(affordable[pick].id)
			var trial := out.duplicate()
			trial.append(order)
			var priced := TurnResolver.price_recruits(state, faction_id, trial)
			if not priced.results.back().ok:
				bump("dropped_invalid")
				break
			out.append(order)
			gold = priced.gold_after
		return out


class Turtle extends Base:
	## Most Forecast.battle_odds calls per turn.
	var odds_cap := 4

	func _init() -> void:
		policy_name = "turtle"

	func orders(state: GameState, faction_id: String, rng: SeededRNG) -> Array:
		var me := state.find_faction(faction_id)
		if me == null:
			return []
		var armies := armies_of(state, faction_id)
		var keep := ""
		var home := armies.filter(func(a): return a.location == me.capital)
		if not home.is_empty():
			keep = strongest(home).id
		var to_home := distances(state, me.capital)
		var by_loc := {}
		for a in armies:
			if a.id == keep:
				continue
			if not by_loc.has(a.location):
				by_loc[a.location] = []
			by_loc[a.location].append(a.id)
		var locs: Array = by_loc.keys()
		locs.sort()
		var plan := {}
		var calls := 0
		for loc in locs:
			var ids: Array = by_loc[loc]
			var dest := ""
			for n in sorted_neighbors(state, loc):
				if enemies_at(state, n, faction_id).is_empty():
					continue
				if calls >= odds_cap:
					bump("odds_capped")
					break
				calls += 1
				bump("odds_calls")
				var odds := Forecast.battle_odds(state, faction_id, ids, n)
				if odds.get("ok", false) and odds.get("label", "") == "likely win":
					dest = n
					break
			if dest.is_empty() and loc != me.capital:
				dest = step_toward(state, loc, to_home, {}, rng)
			if not dest.is_empty():
				for id in ids:
					plan[id] = dest
		var out := checked_moves(state, faction_id, plan)
		out.append_array(best_recruits(state, faction_id))
		return out
