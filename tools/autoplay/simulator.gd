extends RefCounted
## Headless autoplay simulator for M1 (the studio's play-script). Pure: no nodes, no scenes.
## It answers "did every turn resolve, did anything break, how long do games run". It does not judge fun.
##
##   var result := Simulator.play_game(seed, ["kingdom", "beasts"], ["greedy", "random"])
##   var summary := Simulator.summarize(Simulator.run_batch(50, 1, seats, policies))
##   print(Simulator.to_markdown(summary))
##
## play_game drives a real GameSession with the real AutoBattleResolver, through the same hotseat calls
## the UI makes, in seat order: for each seat, acknowledge_handoff (when handed off), read state(), ask
## that seat's policy (tools/autoplay/policies.gd) for orders, queue_order each one, end_turn. The last
## seat's end_turn resolves the turn. A game ends at a capital capture (GameSession.is_over) or at the
## turn cap, which counts as "unfinished".
##
## After every resolved turn, check_invariants inspects the new state and the turn report. Everything it
## finds is recorded with the game seed and turn, so any problem can be replayed exactly.
##
## Determinism: the game seed fixes the starting state (GameState.new(seed)), the turn seeds
## (GameSession.turn_seed) and each seat's policy RNG (policy_seed), so the same seed, seats and policies
## always give the same game.

const Policies := preload("res://tools/autoplay/policies.gd")

const TURN_CAP := 60
## Every event type the M1 turn report may hold. Anything else is reported as an error.
const EVENT_TYPES := ["order_rejected", "army_moved", "battle", "border_battle", "captured", "recruited", "income", "game_over"]
const BATTLE_TYPES := ["battle", "border_battle"]
## AutoBattleResolver report "end" values, in display order.
const BATTLE_ENDS := ["rout", "destroyed", "round_cap", "mutual"]
const END_NAMES := {"rout": "rout (a side broke and fled)", "destroyed": "destroyed (nobody left standing)",
	"round_cap": "round cap", "mutual": "mutual rout"}
## Keys summarize() always returns.
const SUMMARY_KEYS := ["games", "matchup", "seats", "policies", "seeds", "turn_cap", "finished", "unfinished",
	"draws", "wins_by_faction", "wins_by_seat", "length", "length_decisive", "length_all", "length_buckets", "battles",
	"why_factors", "final_gold", "mean_gold", "provinces_held", "orders", "rejections",
	"resolution_rejections", "violations", "errors", "script_errors", "policy_stats", "patterns"]
## Trait names as they appear as "why" factor ids (data/factions.gd), for the trait line of the report.
const TRAITS := ["Shield Wall", "Volley", "Charge", "Inspire", "Berserk", "Skirmish", "Fury", "Pack Leader"]
const LENGTH_BUCKETS := [[1, 9, "under 10"], [10, 15, "10-15"], [16, 20, "16-20"], [21, 30, "21-30"], [31, 100000, "31+"]]


## Seed of the policy RNG for `seat` (0-based) in the game played on `game_seed`.
static func policy_seed(game_seed: int, seat: int) -> int:
	return game_seed * 7919 + (seat + 1) * 104729


## Plays `games` games on seeds base_seed, base_seed + 1, ... and returns their play_game results.
## `probe` (optional) is passed to every play_game call.
static func run_batch(games: int, base_seed: int, seat_factions: Array, policy_names: Array, turn_cap: int = TURN_CAP, probe: Callable = Callable()) -> Array:
	var results := []
	for i in games:
		results.append(play_game(base_seed + i, seat_factions, policy_names, turn_cap, probe))
	return results


## Plays one complete game. `seat_factions` are faction ids in seat order, `policy_names` the policy of
## each seat. Returns:
##   {"seed", "seats", "policies", "turn_cap", "finished", "winner", "winner_seat" (1-based, 0 for none), "draw",
##    "turns", "battles": [{"turn", "kind", "end", "rounds", "winner", "defender", "factors"}],
##    "captures", "final_gold": {fid: int}, "mean_gold": {fid: float}, "provinces_held": {fid: int},
##    "orders", "rejections": {code: n} (orders GameSession refused), "resolution_rejections":
##    {code: n} (order_rejected events in turn reports), "violations": [{"seed", "turn", "check",
##    "detail"}], "errors": [{"seed", "turn", "detail"}] (session problems), "script_errors": [{"seed",
##    "turn", "detail"}], "repro": {} or {"seed", "turn", "what", "orders"} for the first problem turn,
##    "policy_stats": [per seat], "first_battle_turn", "quiet_streak", "final_state": dict}
## `probe` (optional) is called after every turn and returns the engine/script errors logged since its
## last call (a PackedStringArray or Array of strings), so each one is filed under this seed and turn.
static func play_game(game_seed: int, seat_factions: Array, policy_names: Array, turn_cap: int = TURN_CAP, probe: Callable = Callable()) -> Dictionary:
	var result := {
		"seed": game_seed, "seats": seat_factions.duplicate(), "policies": policy_names.duplicate(),
		"turn_cap": turn_cap, "finished": false, "winner": "", "winner_seat": 0, "draw": false, "turns": 0, "battles": [],
		"captures": 0, "final_gold": {}, "mean_gold": {}, "provinces_held": {}, "orders": 0,
		"rejections": {}, "resolution_rejections": {}, "violations": [], "errors": [], "script_errors": [], "repro": {},
		"policy_stats": [], "first_battle_turn": 0, "quiet_streak": 0, "final_state": {},
	}
	if seat_factions.size() != policy_names.size():
		_error(result, 0, "There are %d seats but %d policies." % [seat_factions.size(), policy_names.size()])
		return result
	var policies := []
	var rngs := []
	for i in seat_factions.size():
		var policy = Policies.make(str(policy_names[i]))
		if policy == null:
			_error(result, 0, "Seat %d has an unknown policy '%s'. Policies: %s." % [i + 1, policy_names[i], ", ".join(Policies.NAMES)])
			return result
		policies.append(policy)
		rngs.append(SeededRNG.new(policy_seed(game_seed, i)))

	var session := GameSession.new(GameState.new(game_seed), seat_factions, game_seed, AutoBattleResolver.new())
	for e in session.setup_errors():
		_error(result, 0, "setup: %s" % e)
	if session.phase() == GameSession.Phase.INVALID:
		return result

	var gold_sum := {}
	var quiet := 0
	var prev := session.state()
	while not session.is_over() and session.turns_played() < turn_cap:
		var turn := session.turn_number()
		var played_before := session.turns_played()
		for seat in seat_factions.size():
			var fid := str(seat_factions[seat])
			if session.phase() == GameSession.Phase.HANDOFF:
				var why := session.acknowledge_handoff()
				if not why.is_empty():
					_error(result, turn, "acknowledge_handoff for seat %d: %s" % [seat + 1, why])
			if session.current_player() != fid:
				_error(result, turn, "Seat %d should be ordering as %s, but the session says it is %s's turn." % [
					seat + 1, fid, session.current_player()])
			var view := session.state()
			var orders: Array = policies[seat].orders(view, fid, rngs[seat])
			_queue(session, view, fid, orders, result)
			var ended := session.end_turn()
			if not ended.is_empty():
				_error(result, turn, "end_turn for seat %d: %s" % [seat + 1, ended])
		if session.turns_played() != played_before + 1:
			_error(result, turn, "The turn did not resolve after every seat ended its turn.")
			break
		var state := session.state()
		var events: Array = session.turn_report().get("events", [])
		var found := check_invariants(prev, state, events)
		for v in found:
			result.violations.append({"seed": game_seed, "turn": turn, "check": v.check, "detail": v.detail})
		var logged: Array = Array(probe.call()) if probe.is_valid() else []
		for text in logged:
			result.script_errors.append({"seed": game_seed, "turn": turn, "detail": str(text)})
		if result.repro.is_empty() and not (found.is_empty() and logged.is_empty()):
			var what: String = str(logged[0]) if not logged.is_empty() else "%s: %s" % [found[0].check, found[0].detail]
			result.repro = {"seed": game_seed, "turn": turn, "what": what,
				"orders": session.history().back().get("orders", {})}
		var fought := false
		for e in events:
			var type := str(e.get("type", ""))
			if BATTLE_TYPES.has(type):
				fought = true
				result.battles.append(_battle_record(turn, e))
			elif type == "captured":
				result.captures += 1
			elif type == "order_rejected":
				_bump(result.resolution_rejections, str(e.get("cause", "unknown")))
		if fought and result.first_battle_turn == 0:
			result.first_battle_turn = turn
		quiet = 0 if fought else quiet + 1
		result.quiet_streak = maxi(result.quiet_streak, quiet)
		for f in state.factions:
			gold_sum[f.id] = int(gold_sum.get(f.id, 0)) + f.gold
		prev = state

	var final_state := session.state()
	result.turns = session.turns_played()
	result.finished = session.is_over()
	if result.finished:
		var v := session.victory()
		result.winner = str(v.get("winner", ""))
		result.draw = bool(v.get("draw", false))
		result.winner_seat = seat_factions.find(result.winner) + 1
	for f in final_state.factions:
		result.final_gold[f.id] = f.gold
		result.mean_gold[f.id] = float(gold_sum.get(f.id, 0)) / maxi(1, result.turns)
		var held := 0
		for p in final_state.provinces:
			if p.owner == f.id:
				held += 1
		result.provinces_held[f.id] = held
	for p in policies:
		result.policy_stats.append(p.stats.duplicate())
	result.final_state = final_state.to_dict()
	return result


## Problems with the state after a turn, as [{"check", "detail"}]. Empty when everything holds.
## `prev` is the state the turn started from (or null), `events` the turn report's events.
## Checks: GameState.validate(); gold >= 0; every army is in a known province, belongs to a known faction
## and has a unit or a commander; every unit has 1..max hp and its army's owner; every province owner is
## a known faction or neutral; no province holds armies of two factions; a province held by one
## faction's armies belongs to that faction; armies a battle destroyed are gone; event types and phases
## are known; battle reports have a known end, 1..ROUND_CAP rounds and no negative hp; the turn counter
## went up by one; gold = gold before - recruits paid + income.
static func check_invariants(prev: GameState, state: GameState, events: Array) -> Array:
	var out := []
	if state == null:
		out.append({"check": "state_missing", "detail": "The session returned no state."})
		return out
	var errors := []
	if not state.validate(errors):
		for e in errors:
			out.append({"check": "validate", "detail": str(e)})
	var faction_ids := {}
	for f in state.factions:
		faction_ids[f.id] = true
		if f.gold < 0:
			out.append({"check": "gold_negative", "detail": "%s has %d gold." % [f.id, f.gold]})
	var provinces := {}
	for p in state.provinces:
		provinces[p.id] = p
		if not p.owner.is_empty() and not faction_ids.has(p.owner):
			out.append({"check": "owner_unknown", "detail": "%s is owned by unknown faction '%s'." % [p.id, p.owner]})
	var owners_at := {}
	for a in state.armies:
		if not provinces.has(a.location):
			out.append({"check": "army_location_unknown", "detail": "Army %s is at unknown province '%s'." % [a.id, a.location]})
		if not faction_ids.has(a.owner):
			out.append({"check": "army_owner_unknown", "detail": "Army %s belongs to unknown faction '%s'." % [a.id, a.owner]})
		if a.units.is_empty() and a.commander == null:
			out.append({"check": "army_empty", "detail": "Army %s at %s has no units and no commander." % [a.id, a.location]})
		var members: Array = a.units.duplicate()
		if a.commander != null:
			members.append(a.commander)
		for u in members:
			if u.current_hp <= 0:
				out.append({"check": "unit_hp_not_positive", "detail": "A %s in army %s has %d hp." % [u.type.id, a.id, u.current_hp]})
			elif u.current_hp > u.type.hp:
				out.append({"check": "unit_hp_above_max", "detail": "A %s in army %s has %d of %d hp." % [u.type.id, a.id, u.current_hp, u.type.hp]})
			if u.owner != a.owner:
				out.append({"check": "unit_owner_mismatch", "detail": "A %s owned by %s is in army %s of %s." % [u.type.id, u.owner, a.id, a.owner]})
		if not owners_at.has(a.location):
			owners_at[a.location] = {}
		owners_at[a.location][a.owner] = true
	var occupied: Array = owners_at.keys()
	occupied.sort()
	for pid in occupied:
		var owners: Array = owners_at[pid].keys()
		owners.sort()
		if owners.size() > 1:
			out.append({"check": "hostile_armies_share_province", "detail": "%s holds armies of %s after the turn." % [pid, ", ".join(owners)]})
		elif provinces.has(pid) and provinces[pid].owner != owners[0]:
			out.append({"check": "occupied_not_captured", "detail": "%s holds only %s armies but belongs to '%s'." % [pid, owners[0], provinces[pid].owner]})
	var spent := {}
	var income := {}
	for e in events:
		var type := str(e.get("type", ""))
		if not EVENT_TYPES.has(type):
			out.append({"check": "event_type_unknown", "detail": "The turn report has an event of unexpected type '%s'." % type})
		if not GameSession.REPORT_PHASES.has(str(e.get("phase", ""))):
			out.append({"check": "event_phase_unknown", "detail": "A %s event has unexpected phase '%s'." % [type, e.get("phase", "")]})
		var numbers: Dictionary = e.get("numbers", {})
		var fids: Array = e.get("factions", [])
		if BATTLE_TYPES.has(type):
			for id in numbers.get("destroyed", []):
				if state.find_army(str(id)) != null:
					out.append({"check": "destroyed_army_present", "detail": "Army %s was destroyed in a battle but is still on the map." % id})
			out.append_array(_check_battle_report(numbers.get("report", {})))
		elif type == "recruited" and not fids.is_empty():
			spent[fids[0]] = int(spent.get(fids[0], 0)) + int(numbers.get("cost", 0))
		elif type == "income" and not fids.is_empty():
			income[fids[0]] = int(income.get(fids[0], 0)) + int(numbers.get("income", 0))
	if prev != null:
		if state.current_turn != prev.current_turn + 1:
			out.append({"check": "turn_counter", "detail": "The turn counter went from %d to %d." % [prev.current_turn, state.current_turn]})
		for f in state.factions:
			var before := prev.find_faction(f.id)
			if before == null:
				continue
			var expected: int = before.gold - int(spent.get(f.id, 0)) + int(income.get(f.id, 0))
			if f.gold != expected:
				out.append({"check": "gold_accounting", "detail": "%s has %d gold, expected %d (%d - %d recruits + %d income)." % [
					f.id, f.gold, expected, before.gold, spent.get(f.id, 0), income.get(f.id, 0)]})
	return out


## Aggregates play_game results into the numbers the report prints. Returns every key in SUMMARY_KEYS.
static func summarize(results: Array) -> Dictionary:
	var s := {}
	for k in SUMMARY_KEYS:
		s[k] = null
	var first: Dictionary = results[0] if not results.is_empty() else {}
	var seats: Array = first.get("seats", [])
	var policies: Array = first.get("policies", [])
	s.games = results.size()
	s.seats = seats.duplicate()
	s.policies = policies.duplicate()
	var parts := []
	for i in seats.size():
		parts.append("%s (%s, seat %d)" % [policies[i] if i < policies.size() else "?", faction_name(seats[i]), i + 1])
	s.matchup = " vs ".join(parts)
	var seed_list := results.map(func(r): return int(r.seed))
	s.seeds = [seed_list.min(), seed_list.max()] if not seed_list.is_empty() else []
	s.turn_cap = 0

	var wins_by_faction := {}
	var wins_by_seat := {}
	for i in seats.size():
		wins_by_faction[seats[i]] = 0
		wins_by_seat[i + 1] = 0
	var finished_lengths := []
	var decisive_lengths := []
	var all_lengths := []
	var buckets := {}
	for b in LENGTH_BUCKETS:
		buckets[b[2]] = 0
	buckets["unfinished"] = 0
	var draws := 0
	var unfinished := 0
	var battles := []
	var battles_per_game := []
	var gold_end := {}
	var gold_mean := {}
	var held := {}
	var rejections := {}
	var resolution_rejections := {}
	var orders := 0
	var violations := []
	var errors := []
	var script_errors := []
	var policy_stats := {}
	var quiet := []
	var first_battle := []
	var no_battle_games := 0
	for r in results:
		s.turn_cap = maxi(s.turn_cap, int(r.get("turn_cap", 0)))
		all_lengths.append(int(r.turns))
		if r.finished:
			finished_lengths.append(int(r.turns))
			var placed := false
			for b in LENGTH_BUCKETS:
				if not placed and int(r.turns) >= b[0] and int(r.turns) <= b[1]:
					buckets[b[2]] += 1
					placed = true
			if r.draw:
				draws += 1
			elif not str(r.winner).is_empty():
				decisive_lengths.append(int(r.turns))
				wins_by_faction[r.winner] = int(wins_by_faction.get(r.winner, 0)) + 1
				wins_by_seat[r.winner_seat] = int(wins_by_seat.get(r.winner_seat, 0)) + 1
		else:
			unfinished += 1
			buckets["unfinished"] += 1
		battles.append_array(r.battles)
		battles_per_game.append(r.battles.size())
		if r.battles.is_empty():
			no_battle_games += 1
		else:
			first_battle.append(int(r.first_battle_turn))
		quiet.append(int(r.quiet_streak))
		for fid in r.final_gold:
			if not gold_end.has(fid):
				gold_end[fid] = []
				gold_mean[fid] = []
				held[fid] = []
			gold_end[fid].append(int(r.final_gold[fid]))
			gold_mean[fid].append(float(r.mean_gold[fid]))
			held[fid].append(int(r.provinces_held[fid]))
		for code in r.rejections:
			rejections[code] = int(rejections.get(code, 0)) + int(r.rejections[code])
		for code in r.resolution_rejections:
			resolution_rejections[code] = int(resolution_rejections.get(code, 0)) + int(r.resolution_rejections[code])
		orders += int(r.orders)
		violations.append_array(r.violations)
		errors.append_array(r.errors)
		script_errors.append_array(r.get("script_errors", []))
		for i in r.policy_stats.size():
			var key := "seat %d (%s)" % [i + 1, r.policies[i]]
			if not policy_stats.has(key):
				policy_stats[key] = {}
			for counter in r.policy_stats[i]:
				# Counters are summed over games, except "*_max" ones, which keep the largest.
				if str(counter).ends_with("_max"):
					policy_stats[key][counter] = maxi(int(policy_stats[key].get(counter, 0)), int(r.policy_stats[i][counter]))
				else:
					policy_stats[key][counter] = int(policy_stats[key].get(counter, 0)) + int(r.policy_stats[i][counter])

	s.finished = results.size() - unfinished
	s.unfinished = unfinished
	s.draws = draws
	s.wins_by_faction = wins_by_faction
	s.wins_by_seat = wins_by_seat
	s.length = stats_of(finished_lengths)
	s.length_decisive = stats_of(decisive_lengths)
	s.length_all = stats_of(all_lengths)
	s.length_buckets = buckets
	s.battles = _battle_summary(battles, battles_per_game)
	s.why_factors = _why_summary(battles)
	s.final_gold = {}
	s.mean_gold = {}
	s.provinces_held = {}
	for fid in gold_end:
		s.final_gold[fid] = stats_of(gold_end[fid])
		s.mean_gold[fid] = stats_of(gold_mean[fid])
		s.provinces_held[fid] = stats_of(held[fid])
	s.orders = orders
	s.rejections = rejections
	s.resolution_rejections = resolution_rejections
	var by_check := {}
	for v in violations:
		by_check[v.check] = int(by_check.get(v.check, 0)) + 1
	s.violations = {"count": violations.size(), "by_check": by_check, "first": violations.slice(0, 5)}
	var repro := {}
	for r in results:
		if repro.is_empty() and not r.violations.is_empty():
			repro = r.repro
	s.violations["repro"] = repro
	s.errors = {"count": errors.size(), "first": errors.slice(0, 5)}
	var error_seeds := []
	for e in script_errors:
		if not error_seeds.has(e.seed):
			error_seeds.append(e.seed)
	s.script_errors = {"count": script_errors.size(), "games": error_seeds.size(), "seeds": error_seeds,
		"first": script_errors.slice(0, 5), "repro": {}}
	for r in results:
		if s.script_errors.repro.is_empty() and not r.get("script_errors", []).is_empty():
			s.script_errors.repro = r.repro
	s.policy_stats = policy_stats
	s.patterns = {"games_without_battles": no_battle_games, "first_battle_turn": stats_of(first_battle),
		"longest_quiet_streak": stats_of(quiet)}
	return s


## {"n", "min", "median", "mean", "max"} of a list of numbers (all 0 when it is empty).
static func stats_of(values: Array) -> Dictionary:
	if values.is_empty():
		return {"n": 0, "min": 0, "median": 0, "mean": 0.0, "max": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	var total := 0.0
	for v in sorted:
		total += float(v)
	var median: float = float(sorted[n / 2]) if n % 2 == 1 else (float(sorted[n / 2 - 1]) + float(sorted[n / 2])) / 2.0
	return {"n": n, "min": sorted[0], "median": median, "mean": total / n, "max": sorted[n - 1]}


## Display name of a faction id from data/factions.gd.
static func faction_name(fid: String) -> String:
	for f in FactionData.FACTIONS:
		if f.id == fid:
			return f.name
	return fid


## The summary as a markdown section.
static func to_markdown(s: Dictionary) -> String:
	var L := []
	var seeds: Array = s.get("seeds", [])
	var seed_text := "" if seeds.is_empty() else ", seeds %d-%d" % [seeds[0], seeds[1]]
	L.append("### %s: %d games%s" % [s.matchup, s.games, seed_text])
	L.append("")
	var wf := []
	for fid in s.wins_by_faction:
		wf.append("%s %d (%s)" % [faction_name(fid), s.wins_by_faction[fid], _pct(s.wins_by_faction[fid], s.games)])
	var ws := []
	for seat in s.wins_by_seat:
		ws.append("seat %d %d (%s)" % [seat, s.wins_by_seat[seat], _pct(s.wins_by_seat[seat], s.games)])
	L.append("- **Results:** %d finished, %d unfinished (hit the %d-turn cap), %d draws (both capitals fell the same turn)." % [
		s.finished, s.unfinished, s.turn_cap, s.draws])
	L.append("- **Wins by faction:** %s. **By seat:** %s." % [", ".join(wf), ", ".join(ws)])
	var len_f: Dictionary = s.length
	var len_d: Dictionary = s.length_decisive
	L.append("- **Game length, finished games (turns):** min %d, median %s, mean %.1f, max %d. Decisive games only (no draws, %d): median %s, mean %.1f." % [
		len_f.min, _num(len_f.median), len_f.mean, len_f.max, len_d.n, _num(len_d.median), len_d.mean])
	var bk := []
	for k in s.length_buckets:
		bk.append("%s: %d" % [k, s.length_buckets[k]])
	L.append("- **Length buckets:** %s." % ", ".join(bk))
	var b: Dictionary = s.battles
	L.append("- **Battles:** %d total, %.1f per game (min %d, max %d), %.2f rounds on average; %d province, %d border." % [
		b.total, b.per_game.mean, b.per_game.min, b.per_game.max, b.avg_rounds, b.kinds.get("province", 0), b.kinds.get("border", 0)])
	var ends := []
	for e in BATTLE_ENDS:
		ends.append("%s %d (%s)" % [END_NAMES[e], b.ends.get(e, 0), _pct(b.ends.get(e, 0), b.total)])
	L.append("- **How battles ended:** %s." % ", ".join(ends))
	L.append("- **Defended battles:** %d, defender won %d (%s). Attacker-vs-holder battles are the ones with terrain and fort bonuses." % [
		b.defended, b.defender_wins, _pct(b.defender_wins, b.defended)])
	var why: Array = s.why_factors
	if not why.is_empty():
		var top := []
		for w in why.slice(0, 10):
			top.append("%s %d (%s)" % [w.label, w.count, _pct(w.count, b.total)])
		L.append("- **Top \"why\" factors** (share of battles whose summary cites it): %s." % ", ".join(top))
		var traits := []
		for w in why:
			if TRAITS.has(w.id) or w.id == "morale_Inspire":
				traits.append("%s %d" % [w.label, w.count])
		L.append("- **Traits cited in \"why\":** %s." % ("none" if traits.is_empty() else ", ".join(traits)))
	var gold := []
	for fid in s.final_gold:
		gold.append("%s %.1f (max %d; mean over the game %.1f)" % [faction_name(fid), s.final_gold[fid].mean, s.final_gold[fid].max, s.mean_gold[fid].mean])
	L.append("- **Gold banked at the end (mean):** %s." % ", ".join(gold))
	var held := []
	for fid in s.provinces_held:
		held.append("%s %.1f" % [faction_name(fid), s.provinces_held[fid].mean])
	L.append("- **Provinces held at the end (mean of 14):** %s." % ", ".join(held))
	var p: Dictionary = s.patterns
	L.append("- **Patterns:** %d games with no battle; first battle on turn %s (median); longest run of turns without a battle: median %s, max %d." % [
		p.games_without_battles, _num(p.first_battle_turn.median), _num(p.longest_quiet_streak.median), p.longest_quiet_streak.max])
	L.append("- **Orders queued:** %d. **Rejected by GameSession:** %s. **Rejected at resolution:** %s." % [
		s.orders, _counts(s.rejections), _counts(s.resolution_rejections)])
	var ps := []
	for seat in s.policy_stats:
		ps.append("%s %s" % [seat, _counts(s.policy_stats[seat])])
	if not ps.is_empty():
		L.append("- **Policy counters:** %s." % "; ".join(ps))
	var v: Dictionary = s.violations
	if v.count == 0:
		L.append("- **Invariant violations:** 0.")
	else:
		var first: Dictionary = v.first[0]
		L.append("- **Invariant violations:** %d (%s). First: seed %d, turn %d, %s: %s" % [v.count, _counts(v.by_check),
			first.seed, first.turn, first.check, first.detail])
	var er: Dictionary = s.errors
	if er.count == 0:
		L.append("- **Session errors:** 0.")
	else:
		var fe: Dictionary = er.first[0]
		L.append("- **Session errors:** %d. First: seed %d, turn %d: %s" % [er.count, fe.seed, fe.turn, fe.detail])
	var se: Dictionary = s.script_errors
	if se.count == 0:
		L.append("- **Script errors during games:** 0.")
	else:
		var first_se: Dictionary = se.first[0]
		L.append("- **Script errors during games:** %d in %d games (seeds %s). First: seed %d, turn %d: %s" % [se.count, se.games,
			", ".join(se.seeds.map(func(x): return str(x))), first_se.seed, first_se.turn, first_se.detail])
	return "\n".join(L)


## One markdown table row per game: seed, result, turns, battles, captures, gold left, problems.
static func game_lines(results: Array) -> String:
	var L := ["| seed | result | turns | battles | captures | gold at end | problems |", "|---|---|---|---|---|---|---|"]
	for r in results:
		var outcome := "unfinished"
		if r.finished:
			outcome = "draw" if r.draw else "%s (seat %d)" % [faction_name(r.winner), r.winner_seat]
		var gold := []
		for fid in r.final_gold:
			gold.append("%s %d" % [faction_name(fid), r.final_gold[fid]])
		var problems: int = r.violations.size() + r.errors.size() + r.get("script_errors", []).size()
		L.append("| %d | %s | %d | %d | %d | %s | %d |" % [r.seed, outcome, r.turns, r.battles.size(), r.captures, ", ".join(gold), problems])
	return "\n".join(L)


# --- internals ------------------------------------------------------------------------------------

## Queues `orders` for `fid` through the session; counts each refusal under its rules code.
static func _queue(session: GameSession, view: GameState, fid: String, orders: Array, result: Dictionary) -> void:
	var moved := {}
	var recruits := []
	for order in orders:
		result.orders += 1
		var why := session.queue_order(order)
		if why.is_empty():
			if order is MoveOrder:
				moved[order.army_id] = true
			elif order is RecruitOrder:
				recruits.append(order)
			continue
		var code := "unclassified"
		if order is MoveOrder:
			code = str(TurnResolver.check_move(view, fid, order, moved).get("code", "unclassified"))
		elif order is RecruitOrder:
			var trial := recruits.duplicate()
			trial.append(order)
			code = str(TurnResolver.price_recruits(view, fid, trial).results.back().get("code", "unclassified"))
		else:
			code = "unknown_order"
		_bump(result.rejections, code)


static func _battle_record(turn: int, e: Dictionary) -> Dictionary:
	var numbers: Dictionary = e.get("numbers", {})
	var report: Dictionary = numbers.get("report", {})
	var factors := []
	for f in report.get("factors", []):
		factors.append({"id": str(f.get("id", "")), "faction": str(f.get("faction", "")), "favors_winner": bool(f.get("favors_winner", false))})
	return {"turn": turn, "kind": str(report.get("kind", "border" if e.type == "border_battle" else "province")),
		"end": str(report.get("end", "none")), "rounds": int(report.get("rounds_fought", 0)),
		"winner": str(numbers.get("winner", "")), "defender": str(numbers.get("defender", "")), "factors": factors}


static func _check_battle_report(report: Dictionary) -> Array:
	var out := []
	if report.is_empty():
		out.append({"check": "battle_report_missing", "detail": "A battle has no AutoBattleResolver report."})
		return out
	if not BATTLE_ENDS.has(str(report.get("end", ""))):
		out.append({"check": "battle_end_unknown", "detail": "A battle ended with unexpected end '%s'." % report.get("end", "")})
	var rounds := int(report.get("rounds_fought", 0))
	if rounds < 1 or rounds > AutoBattleResolver.ROUND_CAP:
		out.append({"check": "battle_rounds", "detail": "A battle lasted %d rounds (cap %d)." % [rounds, AutoBattleResolver.ROUND_CAP]})
	for side in report.get("sides", []):
		if int(side.get("hp_end", 0)) < 0:
			out.append({"check": "battle_hp_negative", "detail": "%s ended a battle with %d hp." % [side.get("faction", "?"), side.get("hp_end", 0)]})
		if int(side.get("fighters_lost", 0)) > int(side.get("fighters_start", 0)):
			out.append({"check": "battle_losses", "detail": "%s lost more fighters than it brought." % side.get("faction", "?")})
	return out


static func _battle_summary(battles: Array, per_game: Array) -> Dictionary:
	var ends := {}
	for e in BATTLE_ENDS:
		ends[e] = 0
	var kinds := {"province": 0, "border": 0}
	var rounds := 0
	var defended := 0
	var defender_wins := 0
	for b in battles:
		ends[b.end] = int(ends.get(b.end, 0)) + 1
		kinds[b.kind] = int(kinds.get(b.kind, 0)) + 1
		rounds += int(b.rounds)
		if not str(b.defender).is_empty():
			defended += 1
			if b.winner == b.defender:
				defender_wins += 1
	return {"total": battles.size(), "per_game": stats_of(per_game),
		"avg_rounds": float(rounds) / maxi(1, battles.size()), "ends": ends, "kinds": kinds,
		"defended": defended, "defender_wins": defender_wins}


## Chosen "why" factors (the 1-3 a battle summary cites) counted by factor and faction, most cited first.
static func _why_summary(battles: Array) -> Array:
	var counts := {}
	for b in battles:
		var seen := {}
		for f in b.factors:
			var key := "%s|%s" % [f.id, f.faction]
			if seen.has(key):
				continue
			seen[key] = true
			if not counts.has(key):
				counts[key] = {"id": f.id, "faction": f.faction, "count": 0, "for_winner": 0,
					"label": "%s (%s)" % [_factor_name(f.id), faction_name(f.faction)]}
			counts[key].count += 1
			if f.favors_winner:
				counts[key].for_winner += 1
	var out: Array = counts.values()
	out.sort_custom(func(a, b):
		if a.count != b.count:
			return a.count > b.count
		return a.label < b.label)
	return out


static func _factor_name(id: String) -> String:
	match id:
		"rout":
			return "enemy broke (rout)"
		"numbers":
			return "bigger force"
		"luck":
			return "luck"
		"commander":
			return "commander damage"
		"morale_commander":
			return "commander kept the line"
		"morale_Inspire":
			return "Inspire morale"
		"terrain":
			return "terrain"
		"fort":
			return "fort"
		"round_cap":
			return "round cap"
	return id


static func _error(result: Dictionary, turn: int, detail: String) -> void:
	result.errors.append({"seed": result.seed, "turn": turn, "detail": detail})


static func _bump(counts: Dictionary, key: String) -> void:
	counts[key] = int(counts.get(key, 0)) + 1


static func _pct(n, total) -> String:
	return "0%" if int(total) == 0 else "%d%%" % roundi(100.0 * float(n) / float(total))


static func _num(v) -> String:
	var f := float(v)
	return str(int(f)) if is_equal_approx(f, roundf(f)) else "%.1f" % f


static func _counts(counts: Dictionary) -> String:
	if counts.is_empty():
		return "none"
	var keys: Array = counts.keys()
	keys.sort()
	var parts := []
	for k in keys:
		parts.append("%s %d" % [k, counts[k]])
	return ", ".join(parts)
