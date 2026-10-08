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
##
## Rulers (M2-7, #35): play_game's `options` {"rulers": true, "builds": [preset id or "" per seat]} start
## the game with rulers (GameState.with_rulers). Each seat's build is rolled with AIPlayer.choose_build
## as the first draw of its policy RNG, exactly as an AI seat in a real game (AISeat) rolls it; a preset
## id in "builds" overrides that seat's roll (the draw is still made, so the orders after it stay the
## same). Results then carry "builds" ({faction id: preset id}) and "ruler" counts, and summarize() adds
## the wins by build and the ruler counts (sacrifices, deaths, successors).
##
## Paths (M4-5, #70): `options` {"paths": true} starts the game with paths (GameState.with_paths: the rulers
## game plus a path for every faction; it implies rulers), and {"branches": [branch id or "" per seat]} forces
## a seat's side of the fork (otherwise it is AIPlayer.choose_branch's roll for that seed and seat). Every
## policy is told its seed and seat (configure), as AISeat tells a real computer seat. Results then carry
## "paths" ({faction id: {"branch", "oath_turn", "transform_turn", "nodes", "ordinary_before_oath"}}), and
## summarize() adds the wins by side of the fork and by pairing, when transformations land and the path
## mandates bought by sacrifice. The M4 balance bands are tools/autoplay/path_matrix.gd (--matrix --paths, M4-6).
##
## Research forecasts (M4-6, #71, band P8): in a game with paths, every seat's Forecast.research for the orders it
## queued is checked against what the research phase did. Results carry "research": {"turn_checks",
## "turn_mismatches" (a turn the faction's provinces didn't change, so its rate held: the forecast said whether
## the target is done this turn and what the pool holds after it), "target_checks", "target_mismatches" (a target
## whose provinces held from the turn it was set until it was done must be done on the forecast's done_turn),
## "first" (the first mismatch, in words)}. {"record_digest": true} adds "record_md5", the md5 of the game
## record's JSON (band P7 compares M2 games with a fixture recorded on main). Paths games also carry "recruits":
## {faction id: {unit type id: recruit orders accepted}}, so the report can say how often the new units are bought.

## Magic and fog (M5-11, #122): `options` {"magic": true} starts the game with magic (GameState.with_magic: the paths game plus
## each faction's mage and the rituals; it implies paths), and the result then carries "magic" (MagicLog: the research, every
## ritual cast, the healing and draining, the battle spells, the ritual forecast check and the hit point ledger) and the
## battle records carry the spells they cite. {"fog": true} plays the game with fog of war (GameState.setup_fog): the policies are
## handed their seat's VIEW (GameSession.view_state), as AISeat hands it to the computer, and the invariants keep the true
## state; on every FogProbe.PROBE_EVERY-th turn the snapshot test runs on the live game (result "fog"; {"fog_probe": false} leaves
## it out). {"tithe": mode} gives the
## Thornmane Clans seat Tithe of Blood ("tithe"), a test-only mandate of the same price that does nothing ("null", the control
## of band G9), or Tithe of Blood for the scripted bleeding build ("bleed", played by the "ai_bleed" policy); see tithe_build.
const Policies := preload("res://tools/autoplay/policies.gd")
const MagicLog := preload("res://tools/autoplay/magic_log.gd")
const FogProbe := preload("res://tools/autoplay/fog_probe.gd")

const TURN_CAP := 60
## The mandate a Tithe pair's control run buys with the same power (MandateData.TEST_MANDATES): it does nothing.
const NULL_MANDATE := "null_mandate"
## Every event type the M1 turn report may hold. Anything else is reported as an error.
const EVENT_TYPES := ["order_rejected", "army_moved", "battle", "border_battle", "captured", "recruited", "income", "game_over"]
## Event types a game with rulers adds: ruler deaths, the rulers phase's healing, successors (M2-3, #31),
## Sworn Vassals in the capture phase (M2-4, #32) and sacrifices (M2-6, #34).
const RULER_EVENT_TYPES := ["ruler_died", "mending", "ruler_healed", "ruler_arrived", "succession_waiting", "vassal_joined", "vassal_contested",
	"sacrificed"]
## Event types a game with paths adds (M4): the research phase's events (M4-1, #66), and the transformations'
## on the map (M4-2, #67): Raiding Parties in capture, the transformed event, the Wild Spreads and the heals.
const PATH_EVENT_TYPES := ["research_gained", "research_done", "oath_sworn", "transformed", "wild_spread", "path_healed", "raided"]
## Event types a game with forts and sieges adds (M3c S-1a, #98): the sieges phase's events, construction, and (S-1b)
## the storms and sallies called off in the battles phase.
const SIEGE_EVENT_TYPES := ["siege_started", "walls_damaged", "walls_breached", "siege_lifted", "siege_ended", "walls_repaired",
	"construction_started", "construction_halted", "fort_built", "construction_razed", "storm_called_off", "sally_called_off",
	"sally_found_nothing"]
## Event types a game with magic adds (M5, design/M5_MAGIC_FOG.md §4, §6.3): research sold (M5-5), the rituals phase's
## and the enchantments phase's (M5-6).
const MAGIC_EVENT_TYPES := ["research_sold", "ritual_cast", "ritual_turned_aside", "blood_paid", "enchantment_began", "summoned",
	"fort_raised", "far_sight_reading", "ritual_fell", "blessing_healed", "curse_bit", "enchantment_ended", "summon_faded"]
const BATTLE_TYPES := ["battle", "border_battle"]
## AutoBattleResolver report "end" values, in display order.
const BATTLE_ENDS := ["rout", "destroyed", "round_cap", "mutual"]
const END_NAMES := {"rout": "rout (a side broke and fled)", "destroyed": "destroyed (nobody left standing)",
	"round_cap": "round cap", "mutual": "mutual rout"}
## Keys summarize() always returns.
const SUMMARY_KEYS := ["games", "matchup", "seats", "policies", "seeds", "turn_cap", "finished", "unfinished",
	"draws", "wins_by_faction", "wins_by_seat", "length", "length_decisive", "length_all", "length_buckets", "battles",
	"why_factors", "final_gold", "mean_gold", "provinces_held", "orders", "rejections",
	"resolution_rejections", "violations", "errors", "script_errors", "policy_stats", "patterns", "builds", "rulers", "paths", "magic"]
## Trait names as they appear as "why" factor ids (data/factions.gd), for the trait line of the report.
const TRAITS := ["Shield Wall", "Volley", "Charge", "Inspire", "Berserk", "Skirmish", "Fury", "Pack Leader"]
const LENGTH_BUCKETS := [[1, 9, "under 10"], [10, 15, "10-15"], [16, 20, "16-20"], [21, 30, "21-30"], [31, 100000, "31+"]]


## Seed of the policy RNG for `seat` (0-based) in the game played on `game_seed`.
static func policy_seed(game_seed: int, seat: int) -> int:
	return game_seed * 7919 + (seat + 1) * 104729


## Plays `games` games on seeds base_seed, base_seed + 1, ... and returns their play_game results.
## `probe` (optional) is passed to every play_game call.
static func run_batch(games: int, base_seed: int, seat_factions: Array, policy_names: Array, turn_cap: int = TURN_CAP, probe: Callable = Callable(),
		options: Dictionary = {}) -> Array:
	var results := []
	for i in games:
		results.append(play_game(base_seed + i, seat_factions, policy_names, turn_cap, probe, options))
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
##    "policy_stats": [per seat], "first_battle_turn", "quiet_streak", "final_state": dict, "paths": {} (M4-5,
##    see the class comment)}
## `probe` (optional) is called after every turn and returns the engine/script errors logged since its
## last call (a PackedStringArray or Array of strings), so each one is filed under this seed and turn.
## `options` (optional): {"rulers": true, "builds": [...]} for a game with rulers (see the class comment).
static func play_game(game_seed: int, seat_factions: Array, policy_names: Array, turn_cap: int = TURN_CAP, probe: Callable = Callable(),
		options: Dictionary = {}) -> Dictionary:
	var result := {
		"seed": game_seed, "seats": seat_factions.duplicate(), "policies": policy_names.duplicate(),
		"turn_cap": turn_cap, "finished": false, "winner": "", "winner_seat": 0, "draw": false, "turns": 0, "battles": [],
		"captures": 0, "final_gold": {}, "mean_gold": {}, "provinces_held": {}, "orders": 0,
		"rejections": {}, "resolution_rejections": {}, "violations": [], "errors": [], "script_errors": [], "repro": {},
		"policy_stats": [], "first_battle_turn": 0, "quiet_streak": 0, "final_state": {},
		"builds": {}, "ruler": {"sacrifices": {}, "deaths": {}, "arrivals": {}},
		# M2-8: when each ruler died (and when its successor was due), arrived, and what was sacrificed.
		"ruler_log": {"deaths": [], "arrivals": [], "sacrifices": [], "mandates": {}}, "successors_due": 0,
		"replay": "", "paths": {},
		# M4-6: research forecast checks (band P8), and the record digest (band P7).
		"research": {"turn_checks": 0, "turn_mismatches": 0, "target_checks": 0, "target_mismatches": 0, "first": ""},
		# M4-6: recruit orders the session accepted in a game with paths, {faction id: {unit type id: n}}.
		"recruits": {},
		# M5-11: a game with magic carries its log (MagicLog), a game with fog the snapshot probe's (FogProbe).
		"magic": {}, "fog": {},
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
	var magic: bool = options.get("magic", false)
	var fog: bool = options.get("fog", false)
	var tithe_mode := str(options.get("tithe", ""))
	var paths: bool = options.get("paths", false) or magic  # magic needs paths (M5-5), and paths need rulers
	var forced_sides: Array = options.get("branches", [])
	for i in policies.size():
		policies[i].configure(game_seed, i, str(forced_sides[i]) if i < forced_sides.size() and forced_sides[i] != null else "")

	var start := GameState.new(game_seed)
	if options.get("rulers", false) or paths:
		var forced: Array = options.get("builds", [])
		var builds := {}
		for i in seat_factions.size():
			var fid := str(seat_factions[i])
			var rolled := AIPlayer.choose_build(null, fid, rngs[i])  # the seat RNG's first draw, as in AISeat
			var pick = forced[i] if i < forced.size() else ""
			if (pick is String and pick.is_empty()) or pick == null:
				builds[fid] = rolled
				result.builds[fid] = str(rolled.get("preset", ""))
				continue
			var parsed := parse_build(pick, fid)  # a preset id or an explicit build (M2-8)
			if parsed.has("error"):
				_error(result, 0, "setup: seat %d: %s" % [i + 1, parsed.error])
				return result
			builds[fid] = {"preset": parsed.preset, "ruler": parsed.ruler, "mandates": parsed.mandates}
			result.builds[fid] = str(parsed.id)
		if not tithe_mode.is_empty():
			if not magic:
				_error(result, 0, "setup: Tithe of Blood needs a game with magic.")
				return result
			for fid in builds:
				if fid == "beasts":
					builds[fid] = tithe_build(builds[fid], tithe_mode)
		var build_errors := []
		if magic:
			start = GameState.with_magic(game_seed, builds, build_errors)
		else:
			start = GameState.with_paths(game_seed, builds, build_errors) if paths else GameState.with_rulers(game_seed, builds, build_errors)
		if start == null:
			for e in build_errors:
				_error(result, 0, "setup: %s" % e)
			return result
	if options.get("independents", false):
		var ind_errors := []
		if not start.setup_independents(ind_errors):  # IND-1 (#142): Free Holds garrisons in every neutral province
			for e in ind_errors:
				_error(result, 0, "setup: %s" % e)
			return result
	if fog:
		var fog_errors := []
		if not start.setup_fog(fog_errors):  # M5-1: a lens, not a rule: the game resolves as it does without it
			for e in fog_errors:
				_error(result, 0, "setup: %s" % e)
			return result
	var session := GameSession.new(start, seat_factions, game_seed, AutoBattleResolver.new())
	for e in session.setup_errors():
		_error(result, 0, "setup: %s" % e)
	if session.phase() == GameSession.Phase.INVALID:
		return result
	if magic:
		result.magic = MagicLog.new_log()
	if fog:
		result.fog = FogProbe.new_log()
	var probe_fog: bool = fog and options.get("fog_probe", true)

	var gold_sum := {}
	var quiet := 0
	var prev := session.state()
	var pending_research := {}  # M4-6: faction id -> the target being tracked since the turn it was set
	while not session.is_over() and session.turns_played() < turn_cap:
		var turn := session.turn_number()
		var played_before := session.turns_played()
		var forecasts := {}  # M4-6: faction id -> Forecast.research for the orders it queued this turn
		var ritual_forecasts := []  # M5-11: the forecasts of the rituals queued this turn (MagicLog.forecast_orders)
		if probe_fog and FogProbe.due(turn):
			FogProbe.check(session, seat_factions, game_seed, policy_names, forced_sides, rngs, turn, result.fog)
		for seat in seat_factions.size():
			var fid := str(seat_factions[seat])
			if session.phase() == GameSession.Phase.HANDOFF:
				var why := session.acknowledge_handoff()
				if not why.is_empty():
					_error(result, turn, "acknowledge_handoff for seat %d: %s" % [seat + 1, why])
			if session.current_player() != fid:
				_error(result, turn, "Seat %d should be ordering as %s, but the session says it is %s's turn." % [
					seat + 1, fid, session.current_player()])
			# M5-1: in a fog game the seat is handed its view, as AISeat hands it to the computer; the true state stays here
			var view := session.state_for(fid)
			var orders: Array = policies[seat].orders(view, fid, rngs[seat])
			var accepted := _queue(session, view, fid, orders, result)
			if magic:
				var sight := FogRules.sight(session.state(), fid) if fog and accepted.any(func(o): return o is CastOrder) else {}
				ritual_forecasts.append_array(MagicLog.forecast_orders(view, fid, accepted, sight))
			if paths:
				forecasts[fid] = Forecast.research(view, fid, accepted)
				for o in accepted:
					if o is RecruitOrder:
						if not result.recruits.has(fid):
							result.recruits[fid] = {}
						_bump(result.recruits[fid], o.unit_type_id)
			var ended := session.end_turn()
			if not ended.is_empty():
				_error(result, turn, "end_turn for seat %d: %s" % [seat + 1, ended])
		if session.turns_played() != played_before + 1:
			_error(result, turn, "The turn did not resolve after every seat ended its turn.")
			break
		var state := session.state()
		var events: Array = session.turn_report().get("events", [])
		var found := check_invariants(prev, state, events)
		if magic:
			found.append_array(MagicLog.hp_ledger(prev, state, events, result.magic.hp))
			MagicLog.record_turn(result.magic, turn, events)
			MagicLog.check_forecasts(result.magic, ritual_forecasts, events, turn)
		if paths:
			check_research(prev, state, turn, forecasts, pending_research, result.research)
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
			elif type == "sacrificed" or type == "ruler_died" or type == "ruler_arrived":
				var bucket: Dictionary = result.ruler[{"sacrificed": "sacrifices", "ruler_died": "deaths", "ruler_arrived": "arrivals"}[type]]
				for fid in e.get("factions", []):
					_bump(bucket, str(fid))
					if type == "ruler_died":
						var dead := state.find_faction(str(fid))
						result.ruler_log.deaths.append({"faction": str(fid), "turn": turn,
							"due": dead.successor_turn if dead != null else 0})
					elif type == "ruler_arrived":
						result.ruler_log.arrivals.append({"faction": str(fid), "turn": turn})
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
	_log_rulers(result, final_state)
	_log_paths(result, final_state)
	if magic:
		MagicLog.finish(result.magic, final_state)
	if options.get("replay_check", false):
		result.replay = replay_check(session)
	if options.get("record_digest", false):
		result["record_md5"] = JSON.stringify(session.record()).md5_text()
	return result


## M4-6 (band P8, design/M4_ASCENSION.md §2.3 "forecast equals result"): checks this turn's research
## forecasts (`forecasts`: faction id -> Forecast.research made from the start-of-turn state with the orders
## that faction queued) against `state`, the state after the turn. Only factions whose provinces didn't change
## hands this turn are checked, because their research rate held. Per turn: the forecast said whether the
## target is done at the end of this turn, and the pool after it (pool + rate, less the cost if done).
## Per target: one whose faction's provinces held from the turn it was set until it was done must be done on
## the forecast's done_turn. `pending` carries each faction's tracked target from turn to turn; `out` is a
## result's "research" counters.
static func check_research(prev: GameState, state: GameState, turn: int, forecasts: Dictionary, pending: Dictionary, out: Dictionary) -> void:
	var ids: Array = forecasts.keys()
	ids.sort()
	for fid in ids:
		var fc: Dictionary = forecasts[fid]
		var target := String(fc.get("target", ""))
		var steady := _owned(prev, fid) == _owned(state, fid)
		if target.is_empty() or not bool(fc.get("ok", false)) or int(fc.get("eta", 0)) < 1:
			pending.erase(fid)
			continue
		var p: Dictionary = pending.get(fid, {})
		if p.is_empty() or String(p.target) != target:
			p = {"target": target, "done_turn": int(fc.done_turn), "set_turn": turn, "steady": true}
			pending[fid] = p
		if not steady:
			p.steady = false
		var done_at := AscensionRules.researched_turn(state, fid, target)
		if steady:
			out.turn_checks += 1
			var expect_done := int(fc.eta) == 1
			var pool_after := int(fc.pool) + int(fc.rate) - (int(fc.cost) if expect_done else 0)
			var pool_now := AscensionRules.research_points(state, fid)
			if expect_done != (done_at == turn) or pool_now != pool_after:
				out.turn_mismatches += 1
				if String(out.first).is_empty():
					out.first = "turn %d, %s: the forecast said %s would %sbe done with %d research left, but it was %sdone with %d." % [turn, fid,
						target, "" if expect_done else "not ", pool_after, "" if done_at == turn else "not ", pool_now]
		if done_at > 0:
			if bool(p.steady):
				out.target_checks += 1
				if done_at != int(p.done_turn):
					out.target_mismatches += 1
					if String(out.first).is_empty():
						out.first = "%s: %s was set on turn %d with done_turn %d, and done on turn %d with no province changing hands." % [fid,
							target, int(p.set_turn), int(p.done_turn), done_at]
			pending.erase(fid)


## The ids of the provinces `faction_id` owns, sorted ([] for a null state).
static func _owned(state: GameState, faction_id: String) -> Array:
	var out := []
	if state == null:
		return out
	for p in state.provinces:
		if p.owner == faction_id:
			out.append(p.id)
	out.sort()
	return out


## M2-8: the sacrifices and mandates of every faction with a ruler, and how many successors fell due
## while the game ran: a ruler that died with its successor due at the end of turn T counts when the game
## went past turn T, or ended on turn T with the faction still holding its capital (succession waits for
## the capital, M2_RULER.md §5.2). Every one of them must have arrived (band D).
static func _log_rulers(result: Dictionary, final_state: GameState) -> void:
	for f in final_state.factions:
		if not f.has_ruler():
			continue
		result.ruler_log.mandates[f.id] = f.mandates.duplicate()
		for sac in f.sacrifices:
			result.ruler_log.sacrifices.append({"faction": f.id, "mandate": str(sac.get("mandate", "")), "turn": int(sac.get("turn", 0))})
	var due := 0
	for d in result.ruler_log.deaths:
		var t := int(d.due)
		if t <= 0 or t > final_state.current_turn:
			continue
		if t < final_state.current_turn or RulerRules.holds_capital(final_state, str(d.faction)):
			due += 1
	result.successors_due = due


## M4-5: each faction's path at the end of a game with paths: {"branch" (the side it swore, or ""),
## "oath_turn" and "transform_turn" (the turn at whose end each was done, 0 if never), "nodes" (ids in the
## order done) and "ordinary_before_oath" (rush or round out)}.
static func _log_paths(result: Dictionary, final_state: GameState) -> void:
	if not AscensionRules.has_paths(final_state):
		return
	for f in final_state.factions:
		var side := AscensionRules.branch(final_state, f.id)
		var oath := String(AscensionRules.branch_data(side).get("oath", ""))
		var oath_turn := AscensionRules.researched_turn(final_state, f.id, oath) if not oath.is_empty() else 0
		var trans := AscensionRules.transformation(final_state, f.id)
		var before := 0
		for nid in AscensionRules.researched(final_state, f.id):
			if AscensionRules.is_ordinary(nid) and (oath_turn == 0 or AscensionRules.researched_turn(final_state, f.id, nid) < oath_turn):
				before += 1
		result.paths[f.id] = {"branch": side, "oath_turn": oath_turn,
			"transform_turn": AscensionRules.researched_turn(final_state, f.id, trans) if not trans.is_empty() else 0,
			"nodes": AscensionRules.researched(final_state, f.id), "ordinary_before_oath": before}


## Replays the session's record after a JSON round trip (GameSession.replay, which never runs the AI)
## and compares the final state with the one the game reached: "identical", or "differs: <why>".
static func replay_check(session: GameSession) -> String:
	var text := JSON.stringify(session.record())
	var rec = JSON.parse_string(text)
	if not (rec is Dictionary):
		return "differs: the game record did not survive a JSON round trip"
	var replayed := GameSession.replay(rec, AutoBattleResolver.new())
	if replayed.state == null:
		return "differs: the replay failed (%s)" % " ".join(replayed.errors)
	var a := JSON.stringify(session.state().to_dict())
	var b := JSON.stringify(replayed.state.to_dict())
	if a == b:
		return "identical"
	return "differs: the replayed final state is not the one the game reached (%d vs %d characters)" % [b.length(), a.length()]


## What each Clans preset keeps beside the new mandate in a Tithe pair (band G9). Tithe of Blood costs 3 of the 10 power and the
## presets spend 0, 5 and 10, so Blood of the Fang and Clan Moot cannot keep what they have; and a ruler left with LOW_KEPT
## power or less is played at home (AIPlayer.preset_for), which is another game than the preset's. So each keeps the mandate that
## suits Tithe and leaves its ruler at least TITHE_MIN_KEPT power: Clan Moot its Blood Frenzy (blood given is wounds taken, and
## wounds are what Frenzy feeds on), Blood of the Fang its Iron Discipline. Beast-God Unbound spends nothing, so it keeps nothing.
const TITHE_KEEPS := {"beast_god_unbound": [], "clan_moot": ["blood_frenzy"], "blood_of_the_fang": ["iron_discipline"]}
const TITHE_MIN_KEPT := 3

## The Thornmane Clans build `build` ({"preset", "ruler", "mandates"}) with Tithe of Blood (`mode` "tithe" or "bleed") or
## the test-only mandate of the same price (`mode` "null"), for a Tithe pair (band G9). Both cost the same power, so a pair's two
## builds keep the same power. A preset keeps what TITHE_KEEPS says; any other build loses its last mandates until its ruler
## would keep TITHE_MIN_KEPT power with the new one. The preset name stays, so reports still group the games by the preset
## they began as.
static func tithe_build(build: Dictionary, mode: String) -> Dictionary:
	var extra := NULL_MANDATE if mode == "null" else MagicRules.TITHE_OF_BLOOD
	var mandates: Array = build.get("mandates", []).duplicate()
	var cost := RulerRules.mandate_cost(extra)
	if TITHE_KEEPS.has(str(build.get("preset", ""))):
		mandates = TITHE_KEEPS[str(build.preset)].duplicate()
	while not mandates.is_empty() and RulerRules.kept_after({"ruler": build.ruler, "mandates": mandates}) < cost + TITHE_MIN_KEPT:
		mandates.pop_back()
	mandates.append(extra)
	return {"preset": build.get("preset", ""), "ruler": build.ruler, "mandates": mandates}


## A seat's build from an autoplay --builds value or a matrix cell (M2-8): a preset id from
## data/build_presets.gd ("iron_crown"), an explicit build "RULER" or "RULER+MANDATE+MANDATE"
## ("ever_regent" keeps all 10 power; "fang_chieftain+iron_discipline+blood_frenzy+sworn_vassals"), or a
## build Dictionary {"ruler", "mandates"}. Returns {"id", "preset", "ruler", "mandates"} ("id" names the
## build in reports: the preset id, or the explicit text) or {"error": plain-language reason}.
static func parse_build(arg, faction_id: String) -> Dictionary:
	var build := {}
	var id := ""
	if arg is Dictionary:
		build = RulerRules.normalize_build(arg)
		id = "+".join([build.ruler] + build.mandates)
	else:
		var text := str(arg).strip_edges()
		var preset := RulerRules.preset_build(text)
		if not preset.is_empty():
			build = preset
			id = text
		else:
			var parts := Array(text.split("+", false)).map(func(p): return str(p).strip_edges())
			if parts.is_empty() or RulerRules.ruler_data(str(parts[0])).is_empty():
				var presets := RulerRules.presets_for(faction_id).map(func(p): return str(p.id))
				return {"error": "'%s' is neither a preset (%s) nor a ruler id followed by mandate ids, like %s+royal_armories." % [
					text, ", ".join(presets), RulerRules.rulers_for(faction_id)[0] if not RulerRules.rulers_for(faction_id).is_empty() else "ruler"]}
			build = {"preset": "", "ruler": str(parts[0]), "mandates": parts.slice(1)}
			id = "+".join(parts)
	var errors := RulerRules.build_errors(faction_id, build)
	if not errors.is_empty():
		return {"error": " ".join(errors)}
	return {"id": id, "preset": str(build.get("preset", "")), "ruler": str(build.ruler), "mandates": build.mandates.duplicate()}


## Problems with the state after a turn, as [{"check", "detail"}]. Empty when everything holds.
## `prev` is the state the turn started from (or null), `events` the turn report's events.
## Checks: GameState.validate(); gold >= 0; every army is in a known province, belongs to a known faction
## and has a unit, a commander or a ruler; every unit (and ruler) has 1..max hp and its army's owner; every
## province owner is a known faction or neutral; no province holds armies of two factions; a province held
## by one faction's armies belongs to that faction; armies a battle destroyed are gone; event types and
## phases are known; battle reports have a known end, 1..ROUND_CAP rounds and no negative hp; the turn
## counter went up by one; gold = gold before - recruits paid + income. With rulers, _check_rulers too.
## With paths (M4-2): research events are known, gold also counts Raiding Parties' raided gold (Blood Levy's
## lower prices are already in the recruited costs) and Red Harvest's gold, paid to a battle's winner (M4-3,
## the battle event's numbers.red_harvest), and _check_terrain: terrain changes only by the Wild Spreads.
## With sieges (M3c S-1a): two factions may share a province only in a siege, phases follow GameSession.report_phases,
## gold also counts Fortify spending (construction_started's cost), and _check_sieges.
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
		if not faction_ids.has(a.owner) and not (state.independents and a.owner == IndependentData.FACTION_ID):
			out.append({"check": "army_owner_unknown", "detail": "Army %s belongs to unknown faction '%s'." % [a.id, a.owner]})
		if a.units.is_empty() and a.commander == null and a.ruler == null:  # a ruler's army holds only its ruler
			out.append({"check": "army_empty", "detail": "Army %s at %s has no units and no commander." % [a.id, a.location]})
		var members: Array = a.units.duplicate()
		if a.commander != null:
			members.append(a.commander)
		if a.ruler != null:
			members.append(a.ruler)
		for u in members:
			if u.current_hp <= 0:
				out.append({"check": "unit_hp_not_positive", "detail": "A %s in army %s has %d hp." % [u.type.id, a.id, u.current_hp]})
			elif u.current_hp > RulerRules.unit_max_hp(state, u):  # its type's hp, plus Veteran Levies (M2)
				out.append({"check": "unit_hp_above_max", "detail": "A %s in army %s has %d of %d hp." % [u.type.id, a.id, u.current_hp, RulerRules.unit_max_hp(state, u)]})
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
			var p: Province = provinces.get(pid)
			var siege: bool = state.sieges and p != null and p.fort_level > 0 and p.siege_since > 0 and owners.size() == 2 \
				and owners.has(p.owner)
			if not siege:  # M3c: a garrison and its besiegers share their fort's province
				out.append({"check": "hostile_armies_share_province", "detail": "%s holds armies of %s after the turn." % [pid, ", ".join(owners)]})
		elif provinces.has(pid) and provinces[pid].owner != owners[0] \
				and not (owners[0] == IndependentData.FACTION_ID and provinces[pid].owner.is_empty()):  # IND-1: a garrison holds a neutral province
			out.append({"check": "occupied_not_captured", "detail": "%s holds only %s armies but belongs to '%s'." % [pid, owners[0], provinces[pid].owner]})
	var spent := {}
	var income := {}
	var raided := {}
	var harvested := {}  # M4-3: Red Harvest's gold, paid to the winner in the battles phase
	for e in events:
		var type := str(e.get("type", ""))
		if not EVENT_TYPES.has(type) and not RULER_EVENT_TYPES.has(type) and not (state.paths and PATH_EVENT_TYPES.has(type)) \
				and not (state.sieges and SIEGE_EVENT_TYPES.has(type)) and not (state.magic and MAGIC_EVENT_TYPES.has(type)):
			out.append({"check": "event_type_unknown", "detail": "The turn report has an event of unexpected type '%s'." % type})
		var phases: Array = GameSession.report_phases(state)
		if not phases.has(str(e.get("phase", ""))):
			out.append({"check": "event_phase_unknown", "detail": "A %s event has unexpected phase '%s'." % [type, e.get("phase", "")]})
		var numbers: Dictionary = e.get("numbers", {})
		var fids: Array = e.get("factions", [])
		if BATTLE_TYPES.has(type):
			for id in numbers.get("destroyed", []):
				if state.find_army(str(id)) != null:
					out.append({"check": "destroyed_army_present", "detail": "Army %s was destroyed in a battle but is still on the map." % id})
			out.append_array(_check_battle_report(numbers.get("report", {})))
			if numbers.has("red_harvest"):
				var winner := str(numbers.get("winner", ""))
				harvested[winner] = int(harvested.get(winner, 0)) + int(numbers.red_harvest)
		elif (type == "recruited" or type == "construction_started") and not fids.is_empty():
			spent[fids[0]] = int(spent.get(fids[0], 0)) + int(numbers.get("cost", 0))  # M3c: Fortify orders are paid too
		elif type == "income" and not fids.is_empty():
			income[fids[0]] = int(income.get(fids[0], 0)) + int(numbers.get("income", 0))
		elif type == "raided" and not fids.is_empty():  # M4-2: Raiding Parties' gold, taken in the capture phase
			raided[fids[0]] = int(raided.get(fids[0], 0)) + int(numbers.get("gold", 0))
		elif (type == "ritual_cast" or type == "ritual_turned_aside") and not fids.is_empty():  # M5-6: rituals paid in gold
			spent[fids[0]] = int(spent.get(fids[0], 0)) + int(numbers.get("gold", 0))
		elif type == "research_sold" and not fids.is_empty():  # M5-5: research sold for gold
			raided[fids[0]] = int(raided.get(fids[0], 0)) + int(numbers.get("gold", 0))
	if prev != null:
		if state.current_turn != prev.current_turn + 1:
			out.append({"check": "turn_counter", "detail": "The turn counter went from %d to %d." % [prev.current_turn, state.current_turn]})
		for f in state.factions:
			var before := prev.find_faction(f.id)
			if before == null:
				continue
			var expected: int = before.gold - int(spent.get(f.id, 0)) + int(income.get(f.id, 0)) + int(raided.get(f.id, 0)) \
				+ int(harvested.get(f.id, 0))
			if f.gold != expected:
				out.append({"check": "gold_accounting", "detail": "%s has %d gold, expected %d (%d - %d recruits and rituals + %d income + %d raided or sold + %d harvested)." % [
					f.id, f.gold, expected, before.gold, spent.get(f.id, 0), income.get(f.id, 0), raided.get(f.id, 0), harvested.get(f.id, 0)]})
	out.append_array(_check_rulers(prev, state, events))
	out.append_array(_check_terrain(prev, state, events))
	out.append_array(_check_sieges(prev, state, events))
	out.append_array(_check_magic(prev, state, events))
	return out


## Rituals and enchantments (M5-6, #117; design/M5_MAGIC_FOG.md §6), in a game with magic only. GameState.validate
## already holds every enchantment, Bastion entry and summoned unit to its rules (ids, kinds, "through turn" over, the
## cap). On top of that:
##   caster_moved          an army that cast a ritual (or had it turned aside) ended the turn in another province
##   summon_moved          a summoned army ended its first turn away from where it was called
##   summon_overdue        a summoned creature is still on the map after the turn it should have faded
##   fort_without_bastion  a province gained a fort with no fort_raised (or, with sieges, fort_built) event
##   ritual_price_wrong    a ritual paid more than its price, or a turned-aside one other than half of it
##   curse_bit_own         a curse took hit points from its own faction's fighters
##   blessing_healed_rival a blessing healed an army of another faction
static func _check_magic(prev: GameState, state: GameState, events: Array) -> Array:
	var out := []
	if not state.magic or prev == null:
		return out
	var raised := {}
	for e in events:
		var type := str(e.get("type", ""))
		var n: Dictionary = e.get("numbers", {})
		if type == "ritual_cast" or type == "ritual_turned_aside":
			var a := state.find_army(str(n.get("army", "")))
			var was := prev.find_army(str(n.get("army", "")))
			if a != null and was != null and a.location != was.location:
				out.append({"check": "caster_moved", "detail": "Army %s cast %s at %s but ended the turn at %s." % [a.id, n.get("ritual", ""), was.location, a.location]})
			var price := int(n.get("price", 0))
			var paid := int(n.get("gold", 0)) + int(n.get("hp", 0)) / MagicData.BLOOD_PER_GOLD
			var due := price if type == "ritual_cast" else floori(float(price) / MagicData.TURNED_ASIDE)
			if paid != due:
				out.append({"check": "ritual_price_wrong", "detail": "%s paid %d for %s (%s), not %d." % [e.factions[0], paid, n.get("ritual", ""), type, due]})
		elif type == "summoned":
			var pack := state.find_army(str(n.get("army", "")))
			if pack != null and pack.location != str(n.get("province", "")):
				out.append({"check": "summon_moved", "detail": "The summoned army %s ended its first turn at %s, not %s." % [pack.id, pack.location, n.get("province", "")]})
		elif type == "fort_raised" or type == "fort_built":
			for pid in e.get("provinces", []):
				raised[str(pid)] = true
		elif type == "curse_bit" and str(n.get("victim", "")) == str(n.get("faction", "")):
			out.append({"check": "curse_bit_own", "detail": "%s's curse at %s bit its own fighters." % [n.get("faction", ""), n.get("province", "")]})
		elif type == "blessing_healed":
			var blessed := state.find_army(str(n.get("army", "")))
			if blessed != null and blessed.owner != str(n.get("faction", "")):
				out.append({"check": "blessing_healed_rival", "detail": "%s's blessing healed army %s of %s." % [n.get("faction", ""), blessed.id, blessed.owner]})
	for a in state.armies:
		for u in a.units:
			if u.until > 0 and u.until <= state.current_turn:
				out.append({"check": "summon_overdue", "detail": "A %s in army %s should have faded at the end of turn %d." % [u.type.id, a.id, u.until]})
	for p in state.provinces:
		var before := prev.find_province(p.id)
		if before != null and p.has_fort and not before.has_fort and not raised.has(p.id):
			out.append({"check": "fort_without_bastion", "detail": "%s gained a fort without a fort_raised event." % p.id})
	return out


## Forts and sieges (M3c S-1a, #98; design/M3C_SIEGES.md §11.2 band S9), in a game with sieges only. GameState.validate
## already holds walls to 0..max, one site per faction, siege_since to the armies there, and engines to armies with
## a fighter. On top of that:
##   fort_level_changed     a fort's level changed without a fort_built event (capture keeps the level)
##   recruited_at_cut_off   a recruit arrived at a fort that was cut off at the start of the turn
##   recruited_too_soon     a recruit arrived at a fort its faction took last turn or this one (and didn't retake in time)
##   fort_limit_exceeded    a fort took more recruits this turn than its level allows
static func _check_sieges(prev: GameState, state: GameState, events: Array) -> Array:
	var out := []
	if not state.sieges or prev == null:
		return out
	var built := {}
	var per_fort := {}
	for e in events:
		var type := str(e.get("type", ""))
		if type == "fort_built" or type == "fort_raised":  # M5-6: Bastion raises a palisade at once
			for pid in e.get("provinces", []):
				built[str(pid)] = true
		elif type == "recruited" and str(e.get("cause", "")) != "with_ruler":
			var pid := str(e.get("provinces", [""])[0])
			var fid := str(e.get("factions", [""])[0])
			var key := "%s|%s" % [fid, pid]
			per_fort[key] = int(per_fort.get(key, 0)) + 1
			var before := prev.find_province(pid)
			if before == null:
				continue
			if SiegeRules.is_cut_off(prev, pid, prev.current_turn + 1):
				out.append({"check": "recruited_at_cut_off", "detail": "%s recruited at %s, which was cut off at the start of the turn." % [fid, pid]})
			if before.owner != fid or (before.owned_since > 0 and before.owned_since + FortData.CAPTURE_WAIT >= prev.current_turn + 1):
				out.append({"check": "recruited_too_soon", "detail": "%s recruited at %s, which it had not held since the start of the previous turn." % [fid, pid]})
			if int(per_fort[key]) > SiegeRules.recruit_limit(before.fort_level):
				out.append({"check": "fort_limit_exceeded", "detail": "%s recruited %d at %s, a level %d fort." % [fid, per_fort[key], pid, before.fort_level]})
	for p in state.provinces:
		var before := prev.find_province(p.id)
		if before != null and before.fort_level != p.fort_level and not built.has(p.id):
			out.append({"check": "fort_level_changed", "detail": "%s went from fort level %d to %d without being built." % [p.id, before.fort_level, p.fort_level]})
	return out


## Terrain (M4-2, design/M4_ASCENSION.md §11): a province's terrain changes only by the Wild Spreads, so
## every change this turn is to forest, in a game with paths, with a wild_spread event for that province;
## and every wild_spread event's province is forest now.
##   terrain_changed  a province changed terrain without a wild_spread event, or to something else
##   wild_spread_not_forest  a wild_spread event names a province that is not forest
static func _check_terrain(prev: GameState, state: GameState, events: Array) -> Array:
	var out := []
	var grown := {}
	for e in events:
		if str(e.get("type", "")) == "wild_spread":
			for pid in e.get("provinces", []):
				grown[str(pid)] = true
	for pid in grown:
		var p := state.find_province(pid)
		if p == null or p.terrain != AscensionRules.FOREST:
			out.append({"check": "wild_spread_not_forest", "detail": "The Wild Spreads grew %s, but it is %s." % [pid, p.terrain if p else "not on the map"]})
	if prev == null:
		return out
	for p in state.provinces:
		var before := prev.find_province(p.id)
		if before == null or before.terrain == p.terrain:
			continue
		if not state.paths or p.terrain != AscensionRules.FOREST or not grown.has(p.id):
			out.append({"check": "terrain_changed", "detail": "%s went from %s to %s without the Wild Spreads." % [p.id, before.terrain, p.terrain]})
	return out


## Ruler armies and succession (M2-3, #31), for factions with a ruler; nothing in an M1 game:
##   ruler_army_twice        a faction has more than one ruler army
##   ruler_army_not_alone    a ruler army also holds units or a commander
##   ruler_missing           a living ruler has no ruler army on the map
##   dead_ruler_on_map       a dead ruler still has a ruler army
##   successor_missing       a dead ruler has no successor due
##   successor_overdue       a successor was due by this turn and the faction holds its capital, but none arrived
##   ruler_events_mismatch   a ruler died or arrived this turn without its ruler_died / ruler_arrived event
static func _check_rulers(prev: GameState, state: GameState, events: Array) -> Array:
	var out := []
	var ruler_armies := {}
	for a in state.armies:
		if a.ruler == null:
			continue
		if ruler_armies.has(a.owner):
			out.append({"check": "ruler_army_twice", "detail": "%s has two ruler armies: %s and %s." % [a.owner, ruler_armies[a.owner], a.id]})
		else:
			ruler_armies[a.owner] = a.id
		if not a.units.is_empty() or a.commander != null:
			out.append({"check": "ruler_army_not_alone", "detail": "Ruler army %s also holds %d units%s." % [a.id, a.units.size(),
				" and a commander" if a.commander != null else ""]})
	var died := {}
	var arrived := {}
	for e in events:
		var type := str(e.get("type", ""))
		if type != "ruler_died" and type != "ruler_arrived":
			continue
		var counts: Dictionary = died if type == "ruler_died" else arrived
		for fid in e.get("factions", []):
			counts[str(fid)] = int(counts.get(str(fid), 0)) + 1
	for f in state.factions:
		if not f.has_ruler():
			continue
		var on_map := ruler_armies.has(f.id)
		if f.ruler_status == RulerRules.ALIVE and not on_map:
			out.append({"check": "ruler_missing", "detail": "%s's ruler is alive but has no ruler army on the map." % f.id})
		elif f.ruler_status == RulerRules.DEAD:
			if on_map:
				out.append({"check": "dead_ruler_on_map", "detail": "%s's ruler is dead, but ruler army %s is on the map." % [f.id, ruler_armies[f.id]]})
			if f.successor_turn <= 0:
				out.append({"check": "successor_missing", "detail": "%s's ruler is dead with no successor due." % f.id})
			elif f.successor_turn <= state.current_turn and RulerRules.holds_capital(state, f.id):
				out.append({"check": "successor_overdue", "detail": "%s's successor was due at the end of turn %d, and %s holds its capital, but none arrived by turn %d." % [
					f.id, f.successor_turn, f.id, state.current_turn]})
		var before: Faction = prev.find_faction(f.id) if prev != null else null
		if before == null or not before.has_ruler():
			continue
		var n_died := int(died.get(f.id, 0))
		var n_arrived := int(arrived.get(f.id, 0))
		var alive_now := 1 if f.ruler_status == RulerRules.ALIVE else 0
		var alive_before := 1 if before.ruler_status == RulerRules.ALIVE else 0
		if f.ruler_generation - before.ruler_generation != n_arrived or alive_now - alive_before != n_arrived - n_died:
			out.append({"check": "ruler_events_mismatch", "detail": "%s's ruler went from %s (generation %d) to %s (generation %d), but the turn report has %d ruler_died and %d ruler_arrived events." % [
				f.id, before.ruler_status, before.ruler_generation, f.ruler_status, f.ruler_generation, n_died, n_arrived]})
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
	var by_build := {}  # preset id -> {"games", "wins", "decisive", "faction"}
	var rulers := {"games": 0, "sacrifices": 0, "games_with_sacrifice": 0, "deaths": 0, "games_with_death": 0,
		"arrivals": 0, "games_to_turn_8": 0, "deaths_by_turn_8_games": 0, "successors_due": 0,
		"death_turns": [], "pregame_mandates": {}, "sacrificed_mandates": {}, "sacrifice_turns": []}
	for r in results:
		var rb: Dictionary = r.get("builds", {})
		if not rb.is_empty():
			rulers.games += 1
			var rlog: Dictionary = r.get("ruler_log", {})
			rulers.successors_due += int(r.get("successors_due", 0))
			for d in rlog.get("deaths", []):
				rulers.death_turns.append(int(d.turn))
			var bought := {}
			for sac in rlog.get("sacrifices", []):
				_bump(rulers.sacrificed_mandates, str(sac.mandate))
				rulers.sacrifice_turns.append(int(sac.turn))
				bought["%s|%s" % [sac.faction, sac.mandate]] = true
			var held_mandates: Dictionary = rlog.get("mandates", {})
			for fid in held_mandates:
				for mid in held_mandates[fid]:
					if not bought.has("%s|%s" % [fid, mid]):
						_bump(rulers.pregame_mandates, str(mid))
			var decisive: bool = r.finished and not r.draw and not str(r.winner).is_empty()
			for fid in rb:
				var pid := str(rb[fid])
				if not by_build.has(pid):
					by_build[pid] = {"games": 0, "wins": 0, "decisive": 0, "faction": str(fid)}
				by_build[pid].games += 1
				if decisive:
					by_build[pid].decisive += 1
					if str(r.winner) == str(fid):
						by_build[pid].wins += 1
			var rr: Dictionary = r.get("ruler", {})
			var n_sac := 0
			var n_dead := 0
			for fid in rr.get("sacrifices", {}):
				n_sac += int(rr.sacrifices[fid])
			for fid in rr.get("deaths", {}):
				n_dead += int(rr.deaths[fid])
			for fid in rr.get("arrivals", {}):
				rulers.arrivals += int(rr.arrivals[fid])
			rulers.sacrifices += n_sac
			rulers.deaths += n_dead
			if n_sac > 0:
				rulers.games_with_sacrifice += 1
			if n_dead > 0:
				rulers.games_with_death += 1
			if int(r.turns) >= 8:
				rulers.games_to_turn_8 += 1
				if n_dead > 0:
					rulers.deaths_by_turn_8_games += 1
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
	s.builds = by_build
	s.rulers = rulers
	s.paths = _paths_summary(results)
	s.magic = _magic_summary(results)
	return s


## M4-5: the paths part of summarize(): {"games", "by_branch": {branch id ("" = never swore): {"faction",
## "games", "decisive", "wins", "oath_turns", "transform_turns", "never"}}, "pairings": {"<side>|<side>":
## {"games", "decisive", "wins": {faction id: n}}}, "transform_turns", "reached_14", "both_by_14", "nodes",
## "before_oath": {n: games}, "path_mandates": {mandate id: n}, "path_mandate_turns"}. {"games": 0} without paths.
static func _paths_summary(results: Array) -> Dictionary:
	var out := {"games": 0, "by_branch": {}, "pairings": {}, "transform_turns": [], "reached_14": 0, "both_by_14": 0,
		"nodes": [], "before_oath": {}, "path_mandates": {}, "path_mandate_turns": []}
	for r in results:
		var paths: Dictionary = r.get("paths", {})
		if paths.is_empty():
			continue
		out.games += 1
		var decisive: bool = r.finished and not r.draw and not str(r.winner).is_empty()
		var fids: Array = paths.keys()
		fids.sort()
		var sides := []
		var all_by_14 := true
		for fid in fids:
			var e: Dictionary = paths[fid]
			var side := str(e.branch)
			sides.append(side)
			if not out.by_branch.has(side):
				out.by_branch[side] = {"faction": fid, "games": 0, "decisive": 0, "wins": 0, "oath_turns": [], "transform_turns": [], "never": 0}
			var b: Dictionary = out.by_branch[side]
			b.games += 1
			if decisive:
				b.decisive += 1
				if str(r.winner) == fid:
					b.wins += 1
			if int(e.oath_turn) > 0:
				b.oath_turns.append(int(e.oath_turn))
			if int(e.transform_turn) > 0:
				b.transform_turns.append(int(e.transform_turn))
				out.transform_turns.append(int(e.transform_turn))
			else:
				b.never += 1
			if int(e.transform_turn) <= 0 or int(e.transform_turn) > 14:
				all_by_14 = false
			out.nodes.append(e.nodes.size())
			_bump(out.before_oath, str(int(e.ordinary_before_oath)))
		if int(r.turns) >= 14:
			out.reached_14 += 1
			if all_by_14:
				out.both_by_14 += 1
		var key := "|".join(sides)
		if not out.pairings.has(key):
			out.pairings[key] = {"games": 0, "decisive": 0, "wins": {}}
		var pr: Dictionary = out.pairings[key]
		pr.games += 1
		if decisive:
			pr.decisive += 1
			_bump(pr.wins, str(r.winner))
		for sac in r.get("ruler_log", {}).get("sacrifices", []):
			if not AscensionRules.opening_node(str(sac.mandate)).is_empty():
				_bump(out.path_mandates, str(sac.mandate))
				out.path_mandate_turns.append(int(sac.turn))
	return out


## A side of the fork by name ("Celestial Host"), or "no Oath" for "".
static func side_name(branch_id: String) -> String:
	return "no Oath" if branch_id.is_empty() else AscensionRules.branch_name(branch_id)


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


## Display name of a build: a preset id from data/build_presets.gd ("Iron Crown"), or an explicit build
## id from parse_build ("the Ever-Regent, keeps 10" or "the Ever-Regent: Royal Armories, Heavy Tithes,
## Veteran Levies, keeps 0"). The id itself when unknown.
static func build_name(preset_id: String) -> String:
	var p := RulerRules.preset_data(preset_id)
	if not p.is_empty():
		return str(p.get("name", preset_id))
	var parts := preset_id.split("+", false)
	if parts.is_empty() or RulerRules.ruler_data(parts[0]).is_empty():
		return preset_id
	var mandates := Array(parts.slice(1))
	var kept := RulerRules.kept_after({"ruler": parts[0], "mandates": mandates})
	var who := RulerRules.ruler_name(parts[0])
	if mandates.is_empty():
		return "%s, keeps %d" % [who, kept]
	return "%s: %s, keeps %d" % [who, ", ".join(mandates.map(func(m): return RulerRules.mandate_name(str(m)))), kept]


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
	var bl: Dictionary = s.get("builds", {})
	if not bl.is_empty():
		var ids: Array = bl.keys()
		ids.sort_custom(func(a, b): return str(bl[a].faction) + str(a) < str(bl[b].faction) + str(b))
		var parts := []
		for pid in ids:
			var e: Dictionary = bl[pid]
			parts.append("%s %d (won %d of %d decisive, %s)" % [build_name(str(pid)), e.games, e.wins, e.decisive, _pct(e.wins, e.decisive)])
		L.append("- **Builds (games played; wins of decisive games):** %s." % ", ".join(parts))
		var ru: Dictionary = s.rulers
		L.append("- **Rulers:** %d sacrifices in %d of %d games (%s); %d ruler deaths in %d games (%s of the %d games that reached turn 8 had one); %d successors crowned." % [
			ru.sacrifices, ru.games_with_sacrifice, ru.games, _pct(ru.games_with_sacrifice, ru.games), ru.deaths, ru.games_with_death,
			_pct(ru.deaths_by_turn_8_games, ru.games_to_turn_8), ru.games_to_turn_8, ru.arrivals])
		var dt := stats_of(ru.death_turns)
		L.append("- **Deaths and successions:** %d successors fell due while their game ran and %d were crowned%s; deaths on turn %s (median, %d-%d)." % [
			ru.successors_due, ru.arrivals, "" if ru.arrivals >= ru.successors_due else " (**%d missing**)" % (ru.successors_due - ru.arrivals),
			_num(dt.median), dt.min, dt.max])
		var st := stats_of(ru.sacrifice_turns)
		L.append("- **Mandate picks:** before the game %s; by sacrifice %s%s." % [_mandate_counts(ru.pregame_mandates),
			_mandate_counts(ru.sacrificed_mandates), "" if st.n == 0 else " (turn %s median, %d-%d)" % [_num(st.median), st.min, st.max]])
	var pa = s.get("paths", {})
	if pa is Dictionary and int(pa.get("games", 0)) > 0:
		L.append_array(_paths_lines(pa))
	var mg = s.get("magic", {})
	if mg is Dictionary and int(mg.get("games", 0)) > 0:
		L.append_array(_magic_lines(mg))
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


## M5-11: the magic part of summarize(): {"games" (with magic), "fog_games", "casts" ({"<faction id>:<ritual id>": n}), "blood"
## (rituals paid in blood), "blood_hp", "turned_aside", "spells" ({"<faction id>:<spell id>": n} cast in battle), "healed",
## "drained", "moon", "forecast" and "hp" (the checks), "fog" (the snapshot probes), "arcana" ({"<faction id>:<node id>": games
## that researched it})}. {"games": 0} without magic.
static func _magic_summary(results: Array) -> Dictionary:
	var out := {"games": 0, "fog_games": 0, "casts": {}, "blood": 0, "blood_hp": 0, "turned_aside": 0, "spells": {}, "healed": 0, "drained": 0,
		"moon": 0, "forecast": {"checks": 0, "mismatches": 0, "turned_aside": 0, "unseen": 0}, "hp": {"checks": 0, "mismatches": 0},
		"fog": {"probes": 0, "views": 0, "view_mismatches": 0, "plans": 0, "plan_mismatches": 0, "illegal": 0, "skipped": 0}, "arcana": {},
		"mages": {}}
	for r in results:
		var m: Dictionary = r.get("magic", {})
		if m.is_empty():
			continue
		out.games += 1
		for fid in r.get("recruits", {}):  # {faction id: {"mages", "regulars"}}: the mages among the regular recruits (band G8)
			if not out.mages.has(fid):
				out.mages[fid] = {"mages": 0, "regulars": 0}
			for tid in r.recruits[fid]:
				if MagicRules.is_mage_id(str(tid)):
					out.mages[fid].mages += int(r.recruits[fid][tid])
				if not FactionData.FACTIONS.any(func(f): return f.id == fid and f.commander.id == tid):
					out.mages[fid].regulars += int(r.recruits[fid][tid])
		for c in m.casts:
			_bump(out.casts, "%s:%s" % [c.faction, c.ritual])
			if c.outcome == "turned_aside":
				out.turned_aside += 1
			if c.pay == "blood":
				out.blood += 1
				out.blood_hp += int(c.hp)
		for fid in m.spells:
			for sid in m.spells[fid]:
				out.spells["%s:%s" % [fid, sid]] = int(out.spells.get("%s:%s" % [fid, sid], 0)) + int(m.spells[fid][sid])
		for sid in m.healed:
			out.healed += int(m.healed[sid])
		for sid in m.drained:
			out.drained += int(m.drained[sid])
		out.moon += int(m.moon)
		for k in out.forecast:
			out.forecast[k] += int(m.forecast.get(k, 0))
		for k in out.hp:
			out.hp[k] += int(m.hp.get(k, 0))
		for fid in m.arcana:
			for nid in m.arcana[fid]:
				_bump(out.arcana, "%s:%s" % [fid, nid])
		var f: Dictionary = r.get("fog", {})
		if not f.is_empty():
			out.fog_games += 1
			for k in out.fog:
				out.fog[k] += int(f.get(k, 0))
	return out


## The magic lines of to_markdown (M5-11).
static func _magic_lines(mg: Dictionary) -> Array:
	var L := []
	var by_ritual := {}
	for key in mg.casts:
		var parts := str(key).split(":")
		_bump_by(by_ritual, "%s %s" % [faction_name(parts[0]), MagicRules.spell_name(parts[1])], int(mg.casts[key]))
	L.append("- **Magic:** %d games. Rituals cast: %s; %d turned aside by a ward; %d paid in blood (%d hit points). Healed by blessings %d hp, drained by curses %d hp, healed back by the Blood Moon %d hp." % [
		mg.games, _counts(by_ritual), mg.turned_aside, mg.blood, mg.blood_hp, mg.healed, mg.drained, mg.moon])
	var spells := {}
	for key in mg.spells:
		var parts := str(key).split(":")
		_bump_by(spells, "%s %s" % [faction_name(parts[0]), MagicRules.spell_name(parts[1])], int(mg.spells[key]))
	L.append("- **Battle spells cast:** %s." % _counts(spells))
	var mage_parts := []
	for fid in mg.mages:
		mage_parts.append("%s %s (%d of %d)" % [faction_name(fid), _pct(mg.mages[fid].mages, mg.mages[fid].regulars), mg.mages[fid].mages, mg.mages[fid].regulars])
	L.append("- **Mages among regular recruits:** %s." % ", ".join(mage_parts))
	var research := {}
	for key in mg.arcana:
		var parts := str(key).split(":")
		_bump_by(research, "%s %s" % [faction_name(parts[0]), str(MagicRules.arcana_node(parts[1]).get("name", parts[1]))], int(mg.arcana[key]))
	L.append("- **Arcana researched** (games): %s." % _counts(research))
	L.append("- **Ritual forecasts:** %d mismatches in %d checks (%d turned aside, %d out of clear sight). **Hit point ledger:** %d mismatches in %d armies." % [
		mg.forecast.mismatches, mg.forecast.checks, mg.forecast.turned_aside, mg.forecast.unseen, mg.hp.mismatches, mg.hp.checks])
	if int(mg.fog_games) > 0:
		L.append("- **Fog snapshot probes** (%d fog games): %d views and %d computer plans compared, %d view, %d plan and %d legality failures (%d skipped)." % [
			mg.fog_games, mg.fog.views, mg.fog.plans, mg.fog.view_mismatches, mg.fog.plan_mismatches, mg.fog.illegal, mg.fog.skipped])
	return L


static func _bump_by(counts: Dictionary, key: String, by: int) -> void:
	counts[key] = int(counts.get(key, 0)) + by


## The paths lines of to_markdown (M4-5).
static func _paths_lines(pa: Dictionary) -> Array:
	var L := []
	var sides: Array = pa.by_branch.keys()
	sides.sort_custom(func(a, b): return str(pa.by_branch[a].faction) + str(a) < str(pa.by_branch[b].faction) + str(b))
	var parts := []
	for side in sides:
		var b: Dictionary = pa.by_branch[side]
		var tt := stats_of(b.transform_turns)
		var ot := stats_of(b.oath_turns)
		parts.append("%s (%s) %d games, won %d of %d decisive (%s); Oath on turn %s median, transformed on turn %s median (%d-%d)%s" % [
			side_name(str(side)), faction_name(str(b.faction)), b.games, b.wins, b.decisive, _pct(b.wins, b.decisive),
			_num(ot.median), _num(tt.median), tt.min, tt.max, "" if int(b.never) == 0 else ", never transformed in %d" % b.never])
	L.append("- **Paths, by side of the fork:** %s." % "; ".join(parts))
	var keys: Array = pa.pairings.keys()
	keys.sort()
	var prs := []
	for key in keys:
		var pr: Dictionary = pa.pairings[key]
		var wins := []
		for fid in pr.wins:
			wins.append("%s %d" % [faction_name(str(fid)), pr.wins[fid]])
		wins.sort()
		prs.append("%s: %d games, %s" % [" vs ".join(Array(str(key).split("|")).map(func(b): return side_name(str(b)))), pr.games,
			"no decisive game" if wins.is_empty() else "wins " + ", ".join(wins)])
	L.append("- **Paths, by pairing:** %s." % "; ".join(prs))
	var all_t := stats_of(pa.transform_turns)
	L.append("- **Transformations land:** turn %s median (%d-%d, %d transformations in %d games); both factions transformed by turn 14 in %d of the %d games that reached turn 14 (%s)." % [
		_num(all_t.median), all_t.min, all_t.max, all_t.n, pa.games, pa.both_by_14, pa.reached_14, _pct(pa.both_by_14, pa.reached_14)])
	var nodes := stats_of(pa.nodes)
	var bo: Array = pa.before_oath.keys()
	bo.sort()
	L.append("- **Research:** %.1f nodes per faction by the end (max %d); ordinary nodes before the Oath: %s. **Path mandates by sacrifice:** %s%s." % [
		nodes.mean, nodes.max, ", ".join(bo.map(func(k): return "%s: %d" % [k, pa.before_oath[k]])),
		_mandate_counts(pa.path_mandates), "" if pa.path_mandate_turns.is_empty() else " (turn %s median)" % _num(stats_of(pa.path_mandate_turns).median)])
	return L


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
		var row := "| %d | %s | %d | %d | %d | %s | %d |" % [r.seed, outcome, r.turns, r.battles.size(), r.captures, ", ".join(gold), problems]
		if not r.get("builds", {}).is_empty():
			var names := []
			for fid in r.seats:
				names.append(build_name(str(r.builds.get(fid, ""))))
			row += " %s |" % " vs ".join(names)
		L.append(row)
	return "\n".join(L)


# --- internals ------------------------------------------------------------------------------------

## Queues `orders` for `fid` through the session; counts each refusal under its rules code (the code
## OrderBook.check_order gives it against the orders accepted so far, sacrifices included). Returns the
## orders the session accepted.
static func _queue(session: GameSession, view: GameState, fid: String, orders: Array, result: Dictionary) -> Array:
	var accepted := []
	for order in orders:
		result.orders += 1
		var why := session.queue_order(order)
		if why.is_empty():
			accepted.append(order)
			continue
		_bump(result.rejections, str(OrderBook.check_order(view, fid, order, accepted).get("code", "unclassified")))
	return accepted


static func _battle_record(turn: int, e: Dictionary) -> Dictionary:
	var numbers: Dictionary = e.get("numbers", {})
	var report: Dictionary = numbers.get("report", {})
	var factors := []
	for f in report.get("factors", []):
		factors.append({"id": str(f.get("id", "")), "faction": str(f.get("faction", "")), "favors_winner": bool(f.get("favors_winner", false))})
	var record := {"turn": turn, "kind": str(report.get("kind", "border" if e.type == "border_battle" else "province")),
		"end": str(report.get("end", "none")), "rounds": int(report.get("rounds_fought", 0)),
		"winner": str(numbers.get("winner", "")), "defender": str(numbers.get("defender", "")), "factors": factors}
	if report.get("sides", []).any(func(sr): return sr.has("casters")):  # M5-11: a battle of a game with magic says who cast what
		record["magic"] = MagicLog.battle_extras(report)
	return record


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
	var spell := MagicLog.spell_of(id)  # M5-11: a battle spell or a blessing ("spell_sunlance", "morale_spell_dawn_blessing")
	if not spell.is_empty() and not MagicRules.spell_data(spell).is_empty():
		return "%s%s" % [MagicRules.spell_name(spell), " morale" if id.begins_with("morale_") else ""]
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


## "Royal Armories 12, Heavy Tithes 8" (most taken first), or "none".
static func _mandate_counts(counts: Dictionary) -> String:
	if counts.is_empty():
		return "none"
	var keys: Array = counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b] if counts[a] != counts[b] else str(a) < str(b))
	return ", ".join(keys.map(func(k): return "%s %d" % [RulerRules.mandate_name(str(k)), counts[k]]))


static func _counts(counts: Dictionary) -> String:
	if counts.is_empty():
		return "none"
	var keys: Array = counts.keys()
	keys.sort()
	var parts := []
	for k in keys:
		parts.append("%s %d" % [k, counts[k]])
	return ", ".join(parts)
