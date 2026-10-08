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
##           only attacks adjacent enemy armies that Forecast.battle_odds calls a "likely win". In a game with
##           sieges (M3c S-7, #105) it claims the safest neighbor of its capital once, builds a palisade and then a
##           keep there, recruits there too, keeps armies standing in its forts, and never besieges or storms a fort.
##   ai      the computer opponent, AIPlayer (ai/ai_player.gd) at "normal": guards its capital against
##           anything that can reach it, masses armies, attacks on good odds, expands when it is safe.
##   ai_easy AIPlayer at "easy": sometimes lets good moves pass and recruits at random.
##   ai_bleed (M5-11, #122) AIPlayer at "normal" playing Tithe of Blood the way a person who loves it might: every ritual a
##           Shaman's army can pay in blood is paid in blood, down to the last hit point each soldier can give
##           (the computer itself keeps two thirds of its hit points). The scripted build of band G9.
## In a game with rulers (autoplay --rulers) every policy plays the build the simulator gave its seat;
## only ai and ai_easy know what a ruler, a road move or a sacrifice is (AIPlayer, M2-7). The others
## move the ruler's army like any other army. In a game with paths (--paths) only ai and ai_easy research
## (AIPlayer, M4-5); configure() tells them their seed and seat, so they roll the fork as an AI seat does.
##
##   var policy = Policies.make("greedy")
##   var orders: Array = policy.orders(state, "kingdom", SeededRNG.new(7))

const NAMES := ["greedy", "random", "turtle", "ai", "ai_easy", "ai_bleed"]


## A new policy by name, or null for an unknown name.
static func make(policy_name: String) -> Base:
	match policy_name:
		"greedy":
			return Greedy.new()
		"random":
			return RandomPolicy.new()
		"turtle":
			return Turtle.new()
		"ai":
			return AIPolicy.new("ai", "normal")
		"ai_easy":
			return AIPolicy.new("ai_easy", "easy")
		"ai_bleed":
			return AIPolicy.new("ai_bleed", "normal", true)
	return null


class Base extends RefCounted:
	var policy_name := "base"
	## What the policy did, summed over the game: {counter name: int}.
	var stats := {}

	func orders(_state: GameState, _faction_id: String, _rng: SeededRNG) -> Array:
		return []

	## Whose seat this policy plays (M4, paths): the game seed, the 0-based seat and a forced side of the
	## fork ("" to roll). Only the computer (ai, ai_easy) researches; the others ignore it.
	func configure(_game_seed: int, _seat: int, _forced_branch: String = "") -> void:
		pass

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
	## M3c: the claim looks no further than this many moves for a rival army, to be safe leaving the capital.
	const CLAIM_SAFE_MOVES := 3

	func _init() -> void:
		policy_name = "turtle"

	func orders(state: GameState, faction_id: String, rng: SeededRNG) -> Array:
		var me := state.find_faction(faction_id)
		if me == null:
			return []
		var armies := armies_of(state, faction_id)
		var claim := _claim(state, faction_id, armies) if state.sieges else {}  # M3c: {army id: province id}
		var staying := _staying_provinces(state, faction_id) if state.sieges else {}
		var keep := ""
		var home := armies.filter(func(a): return a.location == me.capital and not claim.has(a.id))
		if not home.is_empty():
			keep = strongest(home).id
		var to_home := distances(state, me.capital)
		var by_loc := {}
		for a in armies:
			if a.id == keep or claim.has(a.id):
				continue
			if not by_loc.has(a.location):
				by_loc[a.location] = []
			by_loc[a.location].append(a.id)
		var locs: Array = by_loc.keys()
		locs.sort()
		var plan := claim.duplicate()
		var calls := 0
		for loc in locs:
			var ids: Array = by_loc[loc]
			var dest := ""
			for n in sorted_neighbors(state, loc):
				if enemies_at(state, n, faction_id).is_empty():
					continue
				if state.sieges and _is_rival_fort(state, n, faction_id):
					continue  # M3c: a turtle never besieges or storms
				if calls >= odds_cap:
					bump("odds_capped")
					break
				calls += 1
				bump("odds_calls")
				var odds := Forecast.battle_odds(state, faction_id, ids, n)
				if odds.get("ok", false) and odds.get("label", "") == "likely win":
					dest = n
					break
			if dest.is_empty() and loc != me.capital and not staying.has(loc):
				dest = step_toward(state, loc, to_home, {}, rng)  # M3c: an army in one of its forts, or at its site, stays
			if not dest.is_empty():
				for id in ids:
					plan[id] = dest
		var out := checked_moves(state, faction_id, plan)
		if state.sieges:
			out.append_array(_fortify_and_recruit(state, faction_id))
		else:
			out.append_array(best_recruits(state, faction_id))
		return out

	# --- M3c (design/M3C_SIEGES.md §11.2, band S7) -------------------------------------------------------
	# The turtle in a game with sieges owns one province besides its capital (it claims the safest neighbor of the capital
	# once, with its strongest army, if the odds call it a likely win), builds a palisade and then a keep there, one site
	# at a time, and recruits there too (the fort first, the capital for what the fort won't take). The army in that
	# province stays. It never besieges or storms a fort and never sallies: the walls are all it has.

	## {army id: province id}: while the faction owns nothing but its capital and no rival army is within CLAIM_SAFE_MOVES of
	## it, its strongest army at the capital claims the safest neighbor of the capital that is neutral, with no rival army
	## near it and a likely win against any garrison.
	func _claim(state: GameState, faction_id: String, armies: Array) -> Dictionary:
		var me := state.find_faction(faction_id)
		for p in state.provinces:
			if p.owner == faction_id and not p.is_capital:
				return {}
		if _rival_within(state, faction_id, CLAIM_SAFE_MOVES):
			return {}
		var home := armies.filter(func(a): return a.location == me.capital and not a.units.is_empty())
		if home.is_empty():
			return {}
		var army: Army = strongest(home)
		var from_rival := distances(state, _rival_capital(state, faction_id))
		var options := []
		for n in sorted_neighbors(state, me.capital):
			var p := state.find_province(n)
			if p != null and p.owner.is_empty():
				options.append(p)
		options.sort_custom(func(x, y):
			var kx := [-int(from_rival.get(x.id, 0)), x.id]
			var ky := [-int(from_rival.get(y.id, 0)), y.id]
			return _key_less(kx, ky))
		var calls := 0
		for p in options:
			if not enemies_at(state, p.id, faction_id).is_empty():
				if calls >= odds_cap:
					break
				calls += 1
				bump("odds_calls")
				var odds := Forecast.battle_odds(state, faction_id, [army.id], p.id)
				if not (odds.get("ok", false) and odds.get("label", "") == "likely win"):
					continue
			bump("claims")
			return {army.id: p.id}
		return {}

	## The provinces where its armies stay: its forts, and the one it is fortifying (or about to).
	func _staying_provinces(state: GameState, faction_id: String) -> Dictionary:
		var out := {}
		for p in state.provinces:
			if p.owner == faction_id and not p.is_capital and (p.fort_level > 0 or not p.works.is_empty()):
				out[p.id] = true
		var next := _safest_province(state, faction_id)
		if not next.is_empty():
			out[next] = true
		return out

	func _fortify_and_recruit(state: GameState, faction_id: String) -> Array:
		var out := []
		var reserve := 0
		var site := _safest_province(state, faction_id)
		if not site.is_empty():
			var f := FortifyOrder.new(site)
			var priced: Dictionary = TurnResolver.price_recruits(state, faction_id, [f]).results.back()
			if bool(priced.ok):
				out.append(f)
				reserve = int(priced.cost)
				bump("fortify")
			elif not _rival_within(state, faction_id, CLAIM_SAFE_MOVES):
				reserve = SiegeRules.fortify_cost(state, site)  # saves up for it while no rival is close
				bump("saving")
		var forts := _own_forts(state, faction_id)
		for order in best_recruits(state, faction_id, reserve):
			var placed := false
			for place in forts + [""]:
				var trial := out.duplicate()
				var r := RecruitOrder.new(order.unit_type_id, place)
				trial.append(r)
				if bool(TurnResolver.price_recruits(state, faction_id, trial).results.back().ok):
					out.append(r)
					placed = true
					if not place.is_empty():
						bump("fort_recruits")
					break
			if not placed:
				bump("dropped_invalid")
		return out

	## The province to fortify next: a palisade of this faction's still to be made a keep, else the safest province it
	## owns with no fort yet (the farthest from the rival's capital, then the nearest its own), with no rival army in or
	## next to it. "" when it is already building, or nothing qualifies.
	func _safest_province(state: GameState, faction_id: String) -> String:
		if not SiegeRules.site_of(state, faction_id).is_empty():
			return ""
		var me := state.find_faction(faction_id)
		var from_rival := distances(state, _rival_capital(state, faction_id))
		var from_home := distances(state, me.capital)
		var best := ""
		var best_key := []
		for p in state.provinces:
			if p.owner != faction_id or p.is_capital or not SiegeRules.check_fortify(state, faction_id, p.id).is_empty():
				continue
			var danger := _rival_near(state, p.id, faction_id)
			for n in p.neighbors:
				danger = danger or _rival_near(state, n, faction_id)
			if danger:
				continue
			var key := [-p.fort_level, -int(from_rival.get(p.id, 0)), int(from_home.get(p.id, 999)), p.id]
			if best.is_empty() or _key_less(key, best_key):
				best = p.id
				best_key = key
		return best

	## An army of another real faction (not the Free Holds) stands within `moves` of this faction's capital.
	func _rival_within(state: GameState, faction_id: String, moves: int) -> bool:
		var to_home := distances(state, state.find_faction(faction_id).capital)
		for a in state.armies:
			if a.owner != faction_id and not IndependentData.is_independent(a.owner) and int(to_home.get(a.location, 999)) <= moves:
				return true
		return false

	## The capital of the first other real faction (not the Free Holds), "" if none.
	func _rival_capital(state: GameState, faction_id: String) -> String:
		var rival := ""
		for f in state.factions:
			if f.id != faction_id and not IndependentData.is_independent(f.id) and (rival.is_empty() or f.id < rival):
				rival = f.id
		return state.find_faction(rival).capital if not rival.is_empty() else ""

	## The forts of this faction outside its capital, the highest level first (then by id).
	func _own_forts(state: GameState, faction_id: String) -> Array:
		var forts: Array = state.provinces.filter(func(p): return p.owner == faction_id and not p.is_capital and p.fort_level > 0)
		forts.sort_custom(func(a, b): return a.fort_level > b.fort_level if a.fort_level != b.fort_level else a.id < b.id)
		return forts.map(func(p): return p.id)

	## A fort of another faction that has an owner (neutral forts don't count: nobody is inside).
	func _is_rival_fort(state: GameState, province_id: String, faction_id: String) -> bool:
		var p := state.find_province(province_id)
		return p != null and p.fort_level > 0 and not p.owner.is_empty() and p.owner != faction_id

	## An army of another real faction (not the Free Holds) stands in the province.
	func _rival_near(state: GameState, province_id: String, faction_id: String) -> bool:
		for a in enemies_at(state, province_id, faction_id):
			if not IndependentData.is_independent(a.owner):
				return true
		return false

	static func _key_less(a: Array, b: Array) -> bool:
		for i in a.size():
			if a[i] != b[i]:
				return a[i] < b[i]
		return false


class AIPolicy extends Base:
	## The AIPlayer that plans this seat's orders, and the difficulty it plays at.
	var ai := AIPlayer.new()
	var difficulty := "normal"
	## M5-11: pay every ritual that can be paid in blood in blood (the scripted Tithe build, "ai_bleed").
	var bleed := false
	## Slowest single plan of the game, in microseconds (reporting only).
	var slowest_usec := 0

	func _init(p_name: String = "ai", p_difficulty: String = "normal", p_bleed: bool = false) -> void:
		policy_name = p_name
		difficulty = p_difficulty
		bleed = p_bleed

	## M4: the brain's seed and seat, as AISeat gives them (AIPlayer.configure), so its side of the fork is
	## the one an AI seat in a real game on this seed rolls; `forced_branch` replaces the roll (--branches).
	func configure(game_seed: int, seat: int, forced_branch: String = "") -> void:
		ai.configure(game_seed, seat, forced_branch)

	func orders(state: GameState, faction_id: String, rng: SeededRNG) -> Array:
		var planned: Array = ai.plan_orders(state, faction_id, rng, difficulty)
		var st: Dictionary = ai.last_plan_stats()
		for key in ["odds_calls", "odds_cached", "odds_skipped", "attacks", "held_back", "captures", "recalls",
				"retreats", "dropped_invalid", "sacrifices", "road_moves", "field_recruits", "ruler_moves",
				"research_orders", "path_recruits", "standoff", "hunts", "sieges", "raids",
				# M3c S-6 (#104), games with sieges only: what AISieges planned
				"fort_sieges", "storms", "sallies", "reliefs", "abandons", "sieges_left", "approaches", "garrisons",
				"engines_bought", "forts_ordered",
				# M5-10 (#121), games with magic and fog only: the rituals cast (and in blood), the scouts sent
				"rituals", "blood_paid", "scouts"]:
			if int(st.get(key, 0)) > 0:
				bump(key, int(st.get(key, 0)))
		for key in st:
			if str(key).begins_with("cast_") and int(st[key]) > 0:  # cast_<ritual id>: one counter per ritual (M5-11)
				bump(str(key), int(st[key]))
		bump("plans")
		bump("plan_ms_total", int(st.get("usec", 0)) / 1000)
		slowest_usec = maxi(slowest_usec, int(st.get("usec", 0)))
		stats["plan_ms_max"] = slowest_usec / 1000
		if bleed:
			planned = _bleed(state, faction_id, planned)
		# AIPlayer pre-checks every order; check them again, in order, exactly as GameSession's OrderBook
		# will (a Sacrifice first, then moves, road moves included, and recruits, Warband Muster included,
		# against the state with the sacrifice applied).
		var out := []
		for o in planned:
			if OrderBook.check_order(state, faction_id, o, out).is_empty():
				out.append(o)
			else:
				bump("dropped_invalid")
		return out

	## The scripted Tithe build (M5-11): each gold-paid ritual of a Shaman's army is paid in blood instead, when the army
	## can give the whole price (MagicRules.check_cast says so), however wounded that leaves it. The gold the computer set
	## aside for it simply stays in the purse.
	func _bleed(state: GameState, faction_id: String, planned: Array) -> Array:
		if not MagicRules.has_magic(state) or not RulerRules.has_mandate(state, faction_id, MagicRules.TITHE_OF_BLOOD):
			return planned
		var out := []
		for o in planned:
			if o is CastOrder and o.pay == CastOrder.GOLD:
				var blood := CastOrder.new(o.ritual, o.army_id, o.target, CastOrder.BLOOD, o.size)
				if MagicRules.check_cast(state, faction_id, blood, out).is_empty():
					bump("bled")
					out.append(blood)
					continue
			out.append(o)
		return out
