class_name AIPlayer
extends RefCounted
## Computer opponent (pre-M2 "AI player brain"). Pure code: no nodes, no scenes.
##
##   var ai := AIPlayer.new()
##   var orders: Array = ai.plan_orders(state, "beasts", SeededRNG.new(seed), "normal")
##   var why: Array = ai.last_plan_notes()   # plain-language reasons, for a "what is the AI doing" tooltip
##
## plan_orders reads the start-of-turn state (it never changes it) and returns MoveOrder and
## RecruitOrder objects for `faction_id`. Every move is pre-checked with TurnResolver.check_move and
## every recruit with TurnResolver.price_recruits, so the rules accept each order it returns.
## Determinism: the same state, rng state and difficulty always give the same orders. Armies,
## provinces and factions are walked in sorted id order, and every random choice (tie-breaks, and the
## easy level's skipped moves and recruits) comes from `rng`.
##
## Strategy, in priority order each turn:
##   1. Capital first. Enemy armies next to the capital can attack it this turn: the armies in the
##      capital hold, and armies next door are recalled until Forecast.battle_odds, run from the
##      enemy's side so the garrison defends with terrain and fort, calls the capital a likely win as
##      defender (or nobody is left to recall). The capital is never left open: the only exception
##      is a sally, when every adjacent enemy army stands in one province and the garrison alone
##      crushes it (SALLY_WIN); that army can then only get in by beating the garrison on the
##      border. Enemy armies two or three moves away keep the garrison home when this turn's
##      recruits alone would not hold the capital against them.
##   2. Enemy capital. An undefended enemy capital next to a free army is walked into (it wins the
##      game). A defended one is attacked once the odds are at least even.
##   3. Battles. Free armies next to an enemy army attack it together when the odds are a likely win,
##      or merely close when that enemy army stands next to a capital we might not hold. The odds
##      count the enemy armies next to the target as if they move in and join the defense. Targets
##      are taken in order of the enemy strength we expect to destroy; stragglers are not worth a step
##      away from the enemy capital.
##   4. Field moves. Armies next to a stronger enemy pull back. Others take safe, undefended
##      provinces for income. The strongest free army pushes toward the enemy capital while the road
##      is safe and it has most of our nearby strength with it (MASS_SHARE); otherwise it waits and
##      every other free army marches to join it, so attacks are made by massed armies.
##   5. Recruits. All gold is spent at the capital (recruits double as the garrison), on the mix that
##      most raises the rough odds of the army that will stand there against the enemy's armies, with
##      a commander first when the capital is threatened and nobody there has one.
## Unit strengths are never hardcoded. The rough strength guess (_power_units) uses only unit stats
## from the state, and only ranks options and skips forecasts that cannot change a decision. Every
## decision that risks an army or the capital is checked with Forecast.battle_odds, which fights the
## real battle rules; calls are capped per plan (ODDS_BUDGET, MAX_ODDS_CALLS) and cached within a plan.

const DIFFICULTIES := ["easy", "normal"]

## Win rates the AI acts on (Forecast.battle_odds labels LIKELY_WIN or more "likely win").
const LIKELY_WIN := 0.65
## Attacking an enemy army that stands next to our capital: "close" is good enough.
const URGENT_WIN := 0.45
## Attacking the enemy capital, which wins the game: at least even odds.
const CAPITAL_WIN := 0.5
## Capital defense: our win rate as defender we want before we stop recalling armies.
const HOLD_TARGET := {"easy": 0.5, "normal": 0.65}
## Forecast budget per plan, in rough milliseconds: each Forecast.battle_odds call fights the real
## battle many times, costing about ODDS_BASE + ODDS_PER_FIGHTER x f + ODDS_PER_FIGHTER_SQ x f^2 for
## f fighters (long, even battles between big armies cost the most). A capital defense check may
## overdraw the budget by up to ESSENTIAL_OVERDRAFT; past that the rough guess decides.
const ODDS_BUDGET := {"easy": 35.0, "normal": 60.0}
const ODDS_BASE := 6.0
const ODDS_PER_FIGHTER := 0.8
const ODDS_PER_FIGHTER_SQ := 0.035
const ESSENTIAL_OVERDRAFT := 40.0
const MAX_ODDS_CALLS := {"easy": 4, "normal": 6}
## Rough-guess power ratios (ours / theirs, see _ratio). Power is hp x damage, so a ratio of 2 is
## about 1.4 times the numbers.
const SURE_RATIO := 4.0  # this lopsided either way: no need to ask the forecast
const HOPELESS_RATIO := 0.3
const RETREAT_RATIO := 0.9  # pull back when the enemy next door is stronger than this
const SAFE_RATIO := 1.2  # step into a province only if we would be this much stronger there
const MASS_SHARE := 0.6  # the main army pushes on only with this share of our free field strength
const MASS_REACH := 3  # ...counting the armies at most this many moves from it
const STRAGGLER_SHARE := 0.15  # enemy armies this small are not worth a step away from the objective
const GARRISON_RATIO := 1.3  # recruits alone must be this strong for the garrison to leave
const SURPLUS_RATIO := 2.5  # extra armies in a threatened capital may leave if the rest are this strong
const WALK_IN_RATIO := 0.8  # walk into an undefended enemy capital unless rescuers are stronger
## Sally: the garrison may attack the enemy army next to the capital when it wins this surely. That
## army can then only reach the capital by fighting the garrison on the border (RulesCodex "swap").
const SALLY_WIN := 0.9
## Rough value of holding ground for the guess (the forecast uses the real terrain and fort rules).
const HOLD_BONUS := 1.15
const FORT_BONUS := 1.25
## Easy level: chance to let a good attack or capture pass.
const EASY_SKIP := 0.3
## Random spread (in gold per turn) added to capture and road choices, so the AI is not perfectly
## predictable and games on different seeds differ. Drawn from the plan's rng, so still deterministic.
const JITTER := {"easy": 4.0, "normal": 3.0}
const MAX_NOTES := 12

var _notes: Array = []
var _stats := {}
var _state: GameState = null
var _fid := ""
var _me: Faction = null
var _rng: SeededRNG = null
var _level := "normal"
var _budget := 0.0
var _cache := {}
var _nbrs := {}  # province id -> sorted neighbor ids
var _dist := {}  # province id -> {province id: steps}
var _mine: Array = []  # our armies, sorted by id
var _foes: Array = []  # every other faction's armies, sorted by id
var _moves := {}  # army id -> destination
var _busy := {}  # army id -> true once it has a job this turn (holding or moving)
var _scratch: GameState = null
var _capital_short := false
var _home_rate := 1.0  # our win rate as defender of the capital this turn (1.0: nothing can attack it)
var _recruit_plan: Array = []  # UnitType, in recruit order


## Orders for `faction_id` this turn. See the class comment. Unknown difficulties play as "normal".
func plan_orders(state: GameState, faction_id: String, rng: SeededRNG, difficulty: String = "normal") -> Array:
	var started := Time.get_ticks_usec()
	_begin(state, faction_id, rng, difficulty)
	if _me == null:
		return []
	_recruit_plan = _plan_recruits([])  # a fresh army, for judging next turn's garrison
	_defend_capital()
	_strike_capitals()
	_attack_armies()
	_field_moves()
	if _level != "easy":
		_recruit_plan = _plan_recruits(_armies_ending_at(_me.capital))
	var out := _checked_moves()
	out.append_array(_checked_recruits())
	_stats["usec"] = Time.get_ticks_usec() - started  # reporting only; never feeds a decision
	# Let go of this turn's state; only the notes and counters are kept.
	_state = null
	_me = null
	_scratch = null
	_cache = {}
	_mine = []
	_foes = []
	return out


## Plain-language reasons for the last plan, most important first. Names only, never ids.
func last_plan_notes() -> Array:
	return _notes.duplicate()


## Counters for the last plan: {"odds_calls", "odds_cached", "odds_skipped", "attacks", "held_back",
## "captures", "recalls", "retreats", "recruits", "dropped_invalid", "usec"}, plus "odds_usec" and
## "odds_fighters_max" when a forecast ran. The timings are for reports only and never steer a plan.
func last_plan_stats() -> Dictionary:
	return _stats.duplicate()


# --- setup ----------------------------------------------------------------------------------------

func _begin(state: GameState, faction_id: String, rng: SeededRNG, difficulty: String) -> void:
	_state = state
	_fid = faction_id
	_rng = rng if rng != null else SeededRNG.new(0)
	_level = difficulty if DIFFICULTIES.has(difficulty) else "normal"
	_notes = []
	_stats = {"odds_calls": 0, "odds_cached": 0, "odds_skipped": 0, "attacks": 0, "held_back": 0,
		"captures": 0, "recalls": 0, "retreats": 0, "recruits": 0, "dropped_invalid": 0, "usec": 0}
	_budget = ODDS_BUDGET[_level]
	_cache = {}
	_moves = {}
	_busy = {}
	_scratch = null
	_capital_short = false
	_home_rate = 1.0
	_recruit_plan = []
	_mine = []
	_foes = []
	_me = state.find_faction(faction_id) if state != null else null
	if _me == null:
		return
	_nbrs = {}
	for p in state.provinces:
		var n: Array = p.neighbors.duplicate()
		n.sort()
		_nbrs[p.id] = n
	_dist = {}
	for p in state.provinces:
		_dist[p.id] = _bfs(p.id)
	for a in state.armies:
		if a.owner == faction_id:
			_mine.append(a)
		else:
			_foes.append(a)
	_mine.sort_custom(func(x, y): return x.id < y.id)
	_foes.sort_custom(func(x, y): return x.id < y.id)


func _bfs(from_id: String) -> Dictionary:
	var dist := {from_id: 0}
	var queue: Array = [from_id]
	var i := 0
	while i < queue.size():
		var pid: String = queue[i]
		i += 1
		for n in _nbrs.get(pid, []):
			if not dist.has(n):
				dist[n] = int(dist[pid]) + 1
				queue.append(n)
	return dist


# --- 1. the capital -------------------------------------------------------------------------------

func _defend_capital() -> void:
	var cap := _state.find_province(_me.capital)
	if cap == null or cap.owner != _fid:
		return
	var home := _mine_at(cap.id)
	var threats := _foes_next_to(cap.id)
	if threats.is_empty():
		_size_garrison(cap, home)
		return
	var where := _places_text(threats)
	var recallable := []
	for n in _nbrs[cap.id]:
		for a in _mine_at(n):
			recallable.append(a)
	recallable.sort_custom(func(x, y): return _army_power(x) > _army_power(y) or (_army_power(x) == _army_power(y) and x.id < y.id))

	if home.is_empty():
		# Nobody holds the capital, so recalled armies arrive together with any attacker and nobody
		# gets the fort. Bring back everyone who can make it.
		for a in recallable:
			_move(a, cap.id)
			_stats.recalls += 1
		_home_rate = 0.0
		if recallable.is_empty():
			_note("%s is open: an enemy army at %s could walk in next turn, and none of our armies can get there in time." % [cap.name, where])
		else:
			var rate := _defense_rate(cap.id, recallable, threats)
			_home_rate = rate
			_note("Rushing %s back to %s: it is empty and an enemy army at %s could attack next turn (odds: %s; nobody holds the fort)." % [
				_count_text(recallable), cap.name, where, _odds_words(rate)])
		return

	# Keep the smallest set of home armies that holds; any extra armies may leave.
	var keep := _keepers(cap.id, home, threats)
	for a in keep:
		_hold(a)
	var defenders: Array = keep.duplicate()
	var recalled := []
	var rate := _defense_rate(cap.id, defenders, threats)
	while rate < HOLD_TARGET[_level] and not recallable.is_empty():
		var a: Army = recallable.pop_front()
		recalled.append(a)
		defenders.append(a)
		rate = _defense_rate(cap.id, defenders, threats)
	for a in recalled:
		_move(a, cap.id)
		_stats.recalls += 1
	_home_rate = rate
	if recalled.is_empty() and _sally(cap, home, threats):
		return
	if recalled.is_empty():
		_note("Holding %s: an enemy army at %s could attack next turn (odds as defender: %s)." % [cap.name, where, _odds_words(rate)])
	else:
		_note("Recalling %s to %s: an enemy army at %s could attack next turn (odds as defender with them: %s)." % [
			_count_text(recalled), cap.name, where, _odds_words(rate)])
	if keep.size() < home.size():
		_note("%s is safe without %s, so %s free to act." % [cap.name, _count_text(home.size() - keep.size()),
			"it is" if home.size() - keep.size() == 1 else "they are"])


## Every enemy army next to the capital stands in one province and the whole garrison would crush
## it: attack it instead of waiting. Moving in, it would have to fight the garrison on the border
## first, and nobody else can reach the capital this turn; this turn's recruits regroup there.
## Returns true when the garrison sallies.
func _sally(cap: Province, home: Array, threats: Array) -> bool:
	var at: String = threats[0].location
	for e in threats:
		if e.location != at:
			return false
	# Judged with the garrison alone: on the border it meets that army without the armies joining
	# from elsewhere (and without terrain, which only makes this estimate safer).
	var odds := _attack_rate(home, at)
	if odds.rate < SALLY_WIN:
		return false
	var attackers: Array = home.duplicate()
	for a in _free_next_to(at):
		if not attackers.has(a):
			attackers.append(a)
	for a in attackers:
		_move(a, at)
	_stats.attacks += 1
	_home_rate = odds.rate
	_note("Sallying out of %s to destroy the enemy army at %s (odds: %s): it cannot slip into %s without fighting us on the way." % [
		cap.name, _province_name(at), _odds_words(odds.rate, odds.label), cap.name])
	return true


## Home armies that must stay: all of them, unless the strongest few are already lopsidedly enough.
func _keepers(pid: String, home: Array, threats: Array) -> Array:
	if home.size() < 2:
		return home.duplicate()
	var by_power := home.duplicate()
	by_power.sort_custom(func(x, y): return _army_power(x) > _army_power(y) or (_army_power(x) == _army_power(y) and x.id < y.id))
	var keep := []
	for a in by_power:
		keep.append(a)
		if _ratio(keep, threats, _ground_bonus(pid), 1.0) >= SURPLUS_RATIO:
			break
	return keep


## Our win rate holding `pid` with `defenders` against `threats` attacking it together: the worst
## case over the attacking factions. Forecast.battle_odds is run from the attacker's side on a scratch
## copy of the state where the defenders stand in `pid`.
func _defense_rate(pid: String, defenders: Array, threats: Array) -> float:
	if defenders.is_empty():
		return 0.0
	var ratio := _ratio(defenders, threats, _ground_bonus(pid), 1.0)
	if ratio >= SURE_RATIO:
		return 0.95
	if ratio <= HOPELESS_RATIO:
		return 0.05
	var st := _scratch_with(defenders, pid)
	var by_faction := {}
	for e in threats:
		if not by_faction.has(e.owner):
			by_faction[e.owner] = []
		by_faction[e.owner].append(e.id)
	var fids: Array = by_faction.keys()
	fids.sort()
	var worst := 1.0
	for fid in fids:
		var r: Dictionary = _odds(st, fid, by_faction[fid], pid, true) if st != null else {}
		var their: float = float(r.win_rate) if r.has("win_rate") else _rate_from_ratio(1.0 / maxf(ratio, 0.001))
		worst = minf(worst, 1.0 - their)
	return worst


## With no enemy next door, enemy armies two or three moves away may still need a garrison: the home
## armies stay unless this turn's recruits alone would hold the capital against them.
func _size_garrison(cap: Province, home: Array) -> void:
	var near := []
	var far := []
	for e in _foes:
		var d := _d(e.location, cap.id)
		if d == 2:
			near.append(e)
		elif d == 3:
			far.append(e)
	if near.is_empty() and far.is_empty():
		return
	var threat: Array = near + far
	var recruits := _recruit_units()
	var need := GARRISON_RATIO if not near.is_empty() else GARRISON_RATIO * 0.6
	var bonus := _ground_bonus(cap.id)
	if _ratio_units(recruits, _units(threat), bonus, 1.0) >= need:
		return
	if home.is_empty():
		if not near.is_empty():
			_capital_short = _ratio_units(recruits, _units(threat), bonus, 1.0) < 1.0
		return
	for a in home:
		_hold(a)
	var garrison: Array = recruits + _units(home)
	if not near.is_empty() and _ratio_units(garrison, _units(threat), bonus, 1.0) < 1.0:
		_capital_short = true
	var where := _places_text(near if not near.is_empty() else far)
	_note("Keeping the garrison in %s: an enemy army at %s is %s moves away." % [cap.name, where, "two" if not near.is_empty() else "three"])


# --- 2. the enemy capital -------------------------------------------------------------------------

func _strike_capitals() -> void:
	for f in _sorted_factions():
		if f.id == _fid:
			continue
		var ec := _state.find_province(f.capital)
		if ec == null or ec.owner == _fid:
			continue
		var attackers := _free_next_to(ec.id)
		if attackers.is_empty():
			continue
		var held := _foes_at(ec.id)
		if held.is_empty():
			var rescuers := _foes_next_to(ec.id)
			if rescuers.is_empty() or _ratio(attackers, rescuers, 1.0, 1.0) >= WALK_IN_RATIO:
				for a in attackers:
					_move(a, ec.id)
				_stats.attacks += 1
				_note("Marching into %s: the %s capital is undefended, and taking it wins the game." % [ec.name, f.faction_name])
			else:
				_note("Not walking into %s yet: the %s armies next to it could rush back and win." % [ec.name, f.faction_name])
			continue
		var odds := _attack_rate(attackers, ec.id)
		if odds.rate >= CAPITAL_WIN:
			for a in attackers:
				_move(a, ec.id)
			_stats.attacks += 1
			_note("Attacking %s, the %s capital, with %s (odds: %s%s)." % [ec.name, f.faction_name, _count_text(attackers), _odds_words(odds.rate, odds.label), _joiners_text(odds)])
		else:
			_stats.held_back += 1
			_note("Not attacking %s yet (odds: %s%s); massing more armies next to it." % [ec.name, _odds_words(odds.rate, odds.label), _joiners_text(odds)])


# --- 3. battles -----------------------------------------------------------------------------------

func _attack_armies() -> void:
	var near_home: Array = _nbrs.get(_me.capital, [])
	var cands := []
	for p in _sorted_provinces():
		if _is_enemy_capital(p.id):
			continue
		var held := _foes_at(p.id)
		if held.is_empty():
			continue
		var att := _free_next_to(p.id)
		if att.is_empty():
			continue
		var urgent: bool = near_home.has(p.id) and _home_rate < HOLD_TARGET[_level]
		# Worth: the enemy strength we expect to destroy, more next to our capital.
		var ratio := _ratio(att, held, 1.0, _ground_bonus(p.id))
		var worth := _power_units(_units(held), _units(att)) * _rate_from_ratio(ratio) * (1.5 if near_home.has(p.id) else 1.0)
		cands.append({"pid": p.id, "urgent": urgent, "worth": worth})
	cands.sort_custom(func(x, y):
		if x.urgent != y.urgent:
			return x.urgent
		if x.worth != y.worth:
			return x.worth > y.worth
		return x.pid < y.pid)
	for c in cands:
		var att := _attackers_for(c.pid, c.urgent)
		if att.is_empty():
			continue
		var p := _state.find_province(c.pid)
		var odds := _attack_rate(att, c.pid)
		var need := URGENT_WIN if c.urgent else LIKELY_WIN
		if odds.rate < need:
			_stats.held_back += 1
			if odds.rate > HOPELESS_RATIO or c.urgent:
				_note("Not attacking the enemy at %s (odds: %s%s)." % [p.name, _odds_words(odds.rate, odds.label), _joiners_text(odds)])
			continue
		if _skips():
			_note("Letting a chance to attack %s pass." % p.name)
			continue
		for a in att:
			_move(a, c.pid)
		_stats.attacks += 1
		var why := " before it reaches %s" % _province_name(_me.capital) if c.urgent else ""
		_note("Attacking the enemy at %s with %s%s (odds: %s%s)." % [p.name, _count_text(att), why, _odds_words(odds.rate, odds.label), _joiners_text(odds)])


## Free armies next to `pid` that should attack it. A small enemy army (a straggler) is not worth a
## step away from the enemy capital, unless it threatens our capital: those armies stay on course.
func _attackers_for(pid: String, urgent: bool) -> Array:
	var att := _free_next_to(pid)
	if urgent or att.is_empty():
		return att
	var held := _foes_at(pid)
	if _power_units(_units(held), _units(att)) >= STRAGGLER_SHARE * _power_units(_units(att), _units(held)):
		return att
	return att.filter(func(a):
		var obj := _objective_for(a.location)
		return obj.is_empty() or _d(pid, obj) <= _d(a.location, obj))


## {"rate", "label", "helpers"} for our `attackers` attacking `pid` now. Enemy armies next to `pid`
## could move in and join the defense in the same turn, so they are counted as if they do ("helpers":
## how many). The rough guess decides when it is lopsided or the forecast budget is spent, otherwise
## Forecast.battle_odds, on a scratch copy of the state with those armies moved in.
func _attack_rate(attackers: Array, pid: String) -> Dictionary:
	var helpers := _foes_next_to(pid)
	var foes: Array = _foes_at(pid) + helpers
	var ratio := _ratio(attackers, foes, 1.0, _ground_bonus(pid))
	if ratio >= SURE_RATIO:
		return {"rate": 0.95, "label": "likely win", "helpers": helpers.size()}
	if ratio <= HOPELESS_RATIO:
		return {"rate": 0.05, "label": "likely loss", "helpers": helpers.size()}
	var ids := []
	for a in attackers:
		ids.append(a.id)
	var st: GameState = _state if helpers.is_empty() else _scratch_with(helpers, pid)
	var r: Dictionary = _odds(st, _fid, ids, pid, false) if st != null else {}
	if r.has("win_rate"):
		return {"rate": float(r.win_rate), "label": str(r.get("label", "")), "helpers": helpers.size()}
	var rate := _rate_from_ratio(ratio)
	return {"rate": rate, "label": _label_for(rate), "helpers": helpers.size()}


# --- 4. field moves -------------------------------------------------------------------------------

func _field_moves() -> void:
	var groups := _free_groups()
	if groups.is_empty():
		return
	var main: Dictionary = groups[0]
	var objective := _objective_for(main.loc)
	var claimed := {}
	var main_dest: String = main.loc
	# Mass before pushing: the main army waits while a big share of our strength is still on its way.
	var nearby := 0.0
	var waiting_for := 0
	for g in groups:
		if _d(g.loc, main.loc) <= MASS_REACH:
			nearby += float(g.power)
			if g.loc != main.loc:
				waiting_for += 1
	main["massed"] = float(main.power) >= MASS_SHARE * nearby
	main["waiting_for"] = waiting_for
	for i in groups.size():
		var g: Dictionary = groups[i]
		var dest := _field_move(g, i == 0, objective, main_dest, claimed)
		if i == 0:
			main_dest = dest
		for a in g.armies:
			if dest == g.loc:
				_hold(a)
			else:
				_move(a, dest)


func _field_move(g: Dictionary, is_main: bool, objective: String, main_dest: String, claimed: Dictionary) -> String:
	var here: String = g.loc
	var armies: Array = g.armies
	var here_name := _province_name(here)
	# A clearly stronger enemy next door: pull back.
	var danger := _foes_next_to(here)
	if not danger.is_empty() and _ratio(armies, danger, _ground_bonus(here), 1.0) < RETREAT_RATIO:
		var back := _retreat_step(g)
		if back != here:
			_stats.retreats += 1
			_note("Pulling back from %s to %s: a stronger enemy army is next to it." % [here_name, _province_name(back)])
			return back
	# The capital will be short of defenders soon: armies close to home go back.
	var cap: String = _me.capital
	if _capital_short and here != cap and _d(here, cap) <= 2:
		var step := _step_toward(here, cap, armies)
		if not step.is_empty():
			_note("Sending %s from %s back toward %s: enemy armies are closing in on it." % [_count_text(armies), here_name, _province_name(cap)])
			return step
	# Take a safe, undefended province next door.
	var capture := _best_capture(g, is_main, objective, claimed)
	if not capture.is_empty():
		if _skips():
			return here
		claimed[capture] = true
		_stats.captures += 1
		var p := _state.find_province(capture)
		_note("Taking %s for %d gold per turn%s." % [p.name, p.income, "" if p.owner.is_empty() else " (and %s lose it)" % _faction_name(p.owner)])
		return capture
	if is_main:
		return _advance(g, objective)
	return _join(g, main_dest)


## The neighbor (or `here`) where the group is safest, judged with the friendly armies that will be
## there. Ties: closer to our capital, then sorted id.
func _retreat_step(g: Dictionary) -> String:
	var here: String = g.loc
	var options: Array = [here]
	for n in _nbrs[here]:
		if _foes_at(n).is_empty():
			options.append(n)
	var best := here
	var best_ratio := -1.0
	for pid in options:
		var friends: Array = g.armies + _friends_ending_at(pid, g.armies)
		var threat := _foes_next_to(pid)
		var r := 99.0 if threat.is_empty() else _ratio(friends, threat, _ground_bonus(pid), 1.0)
		var better := r > best_ratio + 0.0001
		if not better and absf(r - best_ratio) <= 0.0001:
			better = _d(pid, _me.capital) < _d(best, _me.capital) or (_d(pid, _me.capital) == _d(best, _me.capital) and pid < best)
		if better:
			best = pid
			best_ratio = r
	return best


func _best_capture(g: Dictionary, is_main: bool, objective: String, claimed: Dictionary) -> String:
	var here: String = g.loc
	var best := ""
	var best_score := 0.0
	for n in _nbrs[here]:
		var p := _state.find_province(n)
		if p == null or p.owner == _fid or claimed.has(n) or not _foes_at(n).is_empty():
			continue
		if is_main and not objective.is_empty() and _d(n, objective) > _d(here, objective):
			continue
		if not _safe_at(g.armies, n):
			continue
		var score: float = float(p.income) * (1.0 if p.owner.is_empty() else 2.0) + _rng.randf() * float(JITTER[_level])
		if not objective.is_empty():
			score -= 0.01 * _d(n, objective)
		if score > best_score:
			best = n
			best_score = score
	return best


## The main army: one step toward the objective while the step is safe, otherwise hold and mass.
func _advance(g: Dictionary, objective: String) -> String:
	var here: String = g.loc
	if objective.is_empty():
		return here
	var d_here := _d(here, objective)
	if d_here <= 1:
		return here  # next to the enemy capital: _strike_capitals decides when to go in
	if not g.get("massed", true):
		_note("Massing at %s: waiting for %s to join before pushing on to %s." % [_province_name(here),
			_count_text(int(g.get("waiting_for", 1))), _province_name(objective)])
		return here
	var options := []
	for n in _nbrs[here]:
		if _d(n, objective) == d_here - 1 and _foes_at(n).is_empty() and _safe_at(g.armies, n):
			options.append(n)
	if options.is_empty():
		_note("Massing at %s before pushing on to %s: the road ahead is guarded by stronger armies." % [_province_name(here), _province_name(objective)])
		return here
	var step := _pick_step(options)
	return step


## Every other free army: one safe step toward where the main army will be.
func _join(g: Dictionary, main_dest: String) -> String:
	var here: String = g.loc
	if here == main_dest:
		return here
	var step := _step_toward(here, main_dest, g.armies)
	return here if step.is_empty() else step


## A safe step from `here` that gets closer to `target`, or "" when there is none. Stepping into
## `target` itself counts the friendly armies that will be there.
func _step_toward(here: String, target: String, armies: Array) -> String:
	var d_here := _d(here, target)
	var options := []
	for n in _nbrs[here]:
		if _d(n, target) != d_here - 1 or not _foes_at(n).is_empty():
			continue
		var friends: Array = armies + _friends_ending_at(n, armies)
		if _safe_at(friends, n):
			options.append(n)
	return "" if options.is_empty() else _pick_step(options)


## Among equally good steps: provinces we don't own first (they get captured on the way), then the
## highest income give or take a little random spread (JITTER), then a roll of the rng.
func _pick_step(options: Array) -> String:
	var best := []
	var best_key := -1.0
	for n in options:
		var p := _state.find_province(n)
		var key: float = float(p.income) + (100.0 if p.owner != _fid else 0.0) + _rng.randf() * float(JITTER[_level])
		if key > best_key + 0.0001:
			best_key = key
			best = [n]
		elif absf(key - best_key) <= 0.0001:
			best.append(n)
	if best.size() == 1:
		return best[0]
	return best[_rng.randi_range(0, best.size() - 1)]


func _safe_at(armies: Array, pid: String) -> bool:
	var threat := _foes_next_to(pid)
	return threat.is_empty() or _ratio(armies, threat, _ground_bonus(pid), 1.0) >= SAFE_RATIO


## The nearest enemy capital from `from_id` (ties: faction id order), or "".
func _objective_for(from_id: String) -> String:
	var best := ""
	var best_d := 1 << 30
	for f in _sorted_factions():
		if f.id == _fid:
			continue
		var p := _state.find_province(f.capital)
		if p == null or p.owner == _fid:
			continue
		var d := _d(from_id, p.id)
		if d < best_d:
			best = p.id
			best_d = d
	return best


# --- 5. recruits ----------------------------------------------------------------------------------

## Units to recruit this turn, in order, for the army that will stand in the capital after this
## turn's moves (`base`, our armies there). Recruits appear there, so they are next turn's garrison.
func _plan_recruits(base: Array) -> Array:
	var cap := _state.find_province(_me.capital)
	if cap == null or cap.owner != _fid:
		return []
	var roster: Array = []
	for ut in _me.unit_types:
		if ut.cost > 0:
			roster.append(ut)
	var cmd: UnitType = _me.commander_type if _me.commander_type != null and _me.commander_type.cost > 0 else null
	var gold := _me.gold
	var out := []
	if _level == "easy":
		# Cruder: random affordable picks until the gold runs out.
		var pool: Array = roster.duplicate()
		if cmd != null:
			pool.append(cmd)
		for _i in 16:
			var affordable := pool.filter(func(ut): return ut.cost <= gold)
			if affordable.is_empty():
				break
			var pick: UnitType = affordable[_rng.randi_range(0, affordable.size() - 1)]
			out.append(pick)
			gold -= pick.cost
		return out
	# Normal: each pick most raises the garrison's rough odds against the enemy's armies per gold,
	# i.e. (hp it can lose x damage it deals) / (damage the enemy deals back against its defense).
	var foe_units := _units(_foes)
	var units: Array = _units(base)
	var has_cmd := false
	for a in base:
		if a.commander != null:
			has_cmd = true
	var threatened := false
	for e in _foes:
		if _d(e.location, cap.id) <= 2:
			threatened = true
	# A threatened capital with no commander gets one first: a commander steadies the whole army.
	if cmd != null and threatened and not has_cmd and cmd.cost <= gold:
		out.append(cmd)
		units.append(Unit.new(cmd, _fid))
		gold -= cmd.cost
	var value := _recruit_value(units, foe_units)
	for _i in 40:
		var best: UnitType = null
		var best_gain := 0.0
		var best_value := value
		for ut in roster:
			if ut.cost > gold:
				continue
			var trial: Array = units.duplicate()
			trial.append(Unit.new(ut, _fid))
			var v := _recruit_value(trial, foe_units)
			var gain := (v - value) / float(ut.cost)
			if gain > best_gain + 0.000001:
				best = ut
				best_gain = gain
				best_value = v
		if best == null:
			break
		out.append(best)
		units.append(Unit.new(best, _fid))
		gold -= best.cost
		value = best_value
	return out


## How well `units` would fight `foe_units` (or the enemy rosters, before any enemy army is seen):
## our power over the damage the foes would deal per attack against our average defense.
func _recruit_value(units: Array, foe_units: Array) -> float:
	if units.is_empty():
		return 0.0
	var foes: Array = foe_units if not foe_units.is_empty() else _roster_units()
	var back := _pressure(roundi(_avg_attack(foes)), _avg_defense(units))
	return _power_units(units, foes) / maxf(back, 0.1)


## One unit of each type the other factions can recruit, as a stand-in enemy.
func _roster_units() -> Array:
	var out := []
	for f in _state.factions:
		if f.id == _fid:
			continue
		for ut in f.unit_types:
			out.append(Unit.new(ut, f.id))
	return out


## The planned recruits as unit objects, for strength guesses about next turn's garrison.
func _recruit_units() -> Array:
	var out := []
	for ut in _recruit_plan:
		out.append(Unit.new(ut, _fid))
	return out


# --- orders ---------------------------------------------------------------------------------------

func _checked_moves() -> Array:
	var ids: Array = _moves.keys()
	ids.sort()
	var ordered := {}
	var out := []
	for id in ids:
		var order := MoveOrder.new(str(id), str(_moves[id]))
		if TurnResolver.check_move(_state, _fid, order, ordered).is_empty():
			ordered[order.army_id] = true
			out.append(order)
		else:
			_stats.dropped_invalid += 1
	return out


func _checked_recruits() -> Array:
	var out := []
	var counts := {}
	var names := []
	var spent := 0
	for ut in _recruit_plan:
		var order := RecruitOrder.new(ut.id)
		var trial := out.duplicate()
		trial.append(order)
		if TurnResolver.price_recruits(_state, _fid, trial).results.back().ok:
			out.append(order)
			spent += ut.cost
			if not counts.has(ut.name):
				counts[ut.name] = 0
				names.append(ut.name)
			counts[ut.name] += 1
		else:
			_stats.dropped_invalid += 1
	_stats.recruits = out.size()
	if not out.is_empty():
		var parts := []
		for n in names:
			parts.append("%s x%d" % [n, counts[n]])
		_note("Recruiting at %s for %d gold: %s." % [_province_name(_me.capital), spent, ", ".join(parts)])
	return out


func _move(a: Army, dest: String) -> void:
	if dest == a.location:
		_hold(a)
		return
	_moves[a.id] = dest
	_busy[a.id] = true


func _hold(a: Army) -> void:
	_moves.erase(a.id)
	_busy[a.id] = true


func _skips() -> bool:
	return _level == "easy" and _rng.randf() < EASY_SKIP


# --- forecasts ------------------------------------------------------------------------------------

## Forecast.battle_odds of `attacker` attacking `pid` with `ids` on `st`, cached within this plan.
## Returns {} when the budget does not allow the call (callers fall back to the rough guess).
func _odds(st: GameState, attacker: String, ids: Array, pid: String, essential: bool) -> Dictionary:
	var sorted_ids := ids.duplicate()
	sorted_ids.sort()
	var fighters := 0
	var sig := []
	for id in sorted_ids:
		var a := st.find_army(str(id))
		if a != null:
			fighters += a.units.size() + (1 if a.commander != null else 0)
	for a in st.armies:
		if a.location == pid and a.owner != attacker:
			fighters += a.units.size() + (1 if a.commander != null else 0)
			sig.append(a.id)
	sig.sort()
	var key := "%s|%s|%s|%s" % [attacker, ",".join(sorted_ids), pid, ",".join(sig)]
	if _cache.has(key):
		_stats.odds_cached += 1
		return _cache[key]
	var cost := ODDS_BASE + ODDS_PER_FIGHTER * fighters + ODDS_PER_FIGHTER_SQ * fighters * fighters
	var allowed: bool = _stats.odds_calls < MAX_ODDS_CALLS[_level] and _budget >= cost
	if essential and _budget + ESSENTIAL_OVERDRAFT >= cost:
		allowed = true
	if not allowed:
		_stats.odds_skipped += 1
		return {}
	_budget -= cost
	_stats.odds_calls += 1
	var t0 := Time.get_ticks_usec()
	var r := Forecast.battle_odds(st, attacker, sorted_ids, pid)
	_stats["odds_usec"] = int(_stats.get("odds_usec", 0)) + Time.get_ticks_usec() - t0  # reporting only
	_stats["odds_cost"] = float(_stats.get("odds_cost", 0.0)) + cost
	_stats["odds_fighters_max"] = maxi(int(_stats.get("odds_fighters_max", 0)), fighters)
	if not r.get("ok", false):
		r = {}
	_cache[key] = r
	return r


## A scratch copy of the state (made once per plan) where `placed` armies stand in `pid`, our other
## armies that really are in `pid` stand next door instead (they are not counted on to stay), and
## every other army is where it really is. The real state is never changed.
func _scratch_with(placed: Array, pid: String) -> GameState:
	if _scratch == null:
		_scratch = _state.deep_copy([])
		if _scratch == null:
			return null
	var ids := {}
	for a in placed:
		ids[a.id] = true
	var aside: String = _nbrs[pid][0] if not _nbrs.get(pid, []).is_empty() else pid
	for a in _scratch.armies:
		var real := _state.find_army(a.id)
		if real == null:
			continue
		if ids.has(a.id):
			a.location = pid
		elif a.owner == _fid and real.location == pid:
			a.location = aside
		else:
			a.location = real.location
	return _scratch


# --- rough strength guess -------------------------------------------------------------------------

## Rough fighting power of `units` against `foe_units` (Lanchester-style): the hp the side can lose
## before it breaks x the damage it deals per round. Only unit stats from the state go in. The damage
## per attack follows the shape of the published battle rules (RulesCodex: hit chance rises with
## attack over defense, damage is about half the attack minus a quarter of the defense) and the
## breaking point rises with morale; the exact numbers, terrain, forts and traits are left to
## Forecast.battle_odds, which decides every battle that matters.
func _power_units(units: Array, foe_units: Array) -> float:
	if units.is_empty():
		return 0.0
	var foe_def := _avg_defense(foe_units)
	var hp := 0.0
	var dmg := 0.0
	var morale := 0.0
	var regulars := 0
	var led := false
	for u in units:
		hp += u.current_hp
		dmg += _pressure(u.type.attack, foe_def)
		if u.type.is_commander:
			led = true
		else:
			morale += u.type.morale
			regulars += 1
	var m := morale / regulars if regulars > 0 else 10.0
	if led:
		m += 2.0
	return hp * clampf(0.2 + 0.05 * m, 0.25, 0.95) * dmg


## Rough expected damage of one attack with `attack` against `foe_def` defense.
static func _pressure(attack: int, foe_def: float) -> float:
	var atk := float(attack)
	var hit := clampf(0.6 + 0.04 * (atk - foe_def), 0.3, 0.9)
	return hit * maxf(1.0, ceilf(atk * 0.5) - floorf(foe_def * 0.25))


static func _avg_defense(units: Array) -> float:
	var hp := 0.0
	var total := 0.0
	for u in units:
		hp += u.current_hp
		total += u.current_hp * u.type.defense
	return total / hp if hp > 0.0 else 0.0


static func _avg_attack(units: Array) -> float:
	var hp := 0.0
	var total := 0.0
	for u in units:
		hp += u.current_hp
		total += u.current_hp * u.type.attack
	return total / hp if hp > 0.0 else 0.0


func _ratio_units(ours: Array, theirs: Array, our_bonus: float, their_bonus: float) -> float:
	var them := _power_units(theirs, ours) * their_bonus
	if them <= 0.0:
		return 99.0
	return _power_units(ours, theirs) * our_bonus / them


func _ratio(ours: Array, theirs: Array, our_bonus: float, their_bonus: float) -> float:
	return _ratio_units(_units(ours), _units(theirs), our_bonus, their_bonus)


func _army_power(a: Army) -> float:
	return _power_units(_members(a), _units(_foes))


func _ground_bonus(pid: String) -> float:
	var p := _state.find_province(pid)
	if p == null:
		return 1.0
	return HOLD_BONUS * (FORT_BONUS if p.has_fort else 1.0)


## Win chance from a power ratio, for when the forecast budget is spent.
static func _rate_from_ratio(r: float) -> float:
	var r2 := r * r
	return r2 / (1.0 + r2)


static func _label_for(rate: float) -> String:
	if rate >= LIKELY_WIN:
		return "likely win"
	if rate <= 1.0 - LIKELY_WIN:
		return "likely loss"
	return "close"


# --- lookups --------------------------------------------------------------------------------------

func _d(a: String, b: String) -> int:
	return int(_dist.get(a, {}).get(b, 999))


static func _members(a: Army) -> Array:
	var out: Array = a.units.duplicate()
	if a.commander != null:
		out.append(a.commander)
	return out


static func _units(armies: Array) -> Array:
	var out := []
	for a in armies:
		out.append_array(_members(a))
	return out


func _mine_at(pid: String) -> Array:
	return _mine.filter(func(a): return a.location == pid)


func _foes_at(pid: String) -> Array:
	return _foes.filter(func(a): return a.location == pid)


## Enemy armies that could move into `pid` this turn (they stand next to it).
func _foes_next_to(pid: String) -> Array:
	var near: Array = _nbrs.get(pid, [])
	return _foes.filter(func(a): return near.has(a.location))


## Our armies without a job yet that stand next to `pid`, sorted by id.
func _free_next_to(pid: String) -> Array:
	var near: Array = _nbrs.get(pid, [])
	return _mine.filter(func(a): return not _busy.has(a.id) and near.has(a.location))


## Our other armies that will be in `pid` after this turn's moves planned so far (holding there or
## moving in), excluding `exclude`.
func _friends_ending_at(pid: String, exclude: Array) -> Array:
	var out := []
	for a in _mine:
		if exclude.has(a):
			continue
		var dest: String = _moves.get(a.id, a.location)
		if dest == pid and (_busy.has(a.id) or a.location == pid):
			out.append(a)
	return out


## Our armies that will stand in `pid` after the moves planned so far.
func _armies_ending_at(pid: String) -> Array:
	return _mine.filter(func(a): return str(_moves.get(a.id, a.location)) == pid)


## Our free armies grouped by province: [{"loc", "armies", "power"}], strongest first.
func _free_groups() -> Array:
	var by_loc := {}
	for a in _mine:
		if _busy.has(a.id):
			continue
		if not by_loc.has(a.location):
			by_loc[a.location] = []
		by_loc[a.location].append(a)
	var foe_units := _units(_foes)
	var locs: Array = by_loc.keys()
	locs.sort()
	var groups := []
	for loc in locs:
		groups.append({"loc": loc, "armies": by_loc[loc], "power": _power_units(_units(by_loc[loc]), foe_units)})
	groups.sort_custom(func(x, y): return x.power > y.power or (x.power == y.power and x.loc < y.loc))
	return groups


func _is_enemy_capital(pid: String) -> bool:
	for f in _state.factions:
		if f.id != _fid and f.capital == pid:
			return true
	return false


func _sorted_factions() -> Array:
	var out: Array = _state.factions.duplicate()
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


func _sorted_provinces() -> Array:
	var out: Array = _state.provinces.duplicate()
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


# --- plain-language notes -------------------------------------------------------------------------

func _note(text: String) -> void:
	if _notes.size() < MAX_NOTES and not _notes.has(text):
		_notes.append(text)


func _province_name(pid: String) -> String:
	var p := _state.find_province(pid)
	return p.name if p != null else "an unknown place"


func _faction_name(fid: String) -> String:
	var f := _state.find_faction(fid)
	return f.faction_name if f != null else "an unknown faction"


## "Westwatch" or "Westwatch and Highcrag": where these armies stand, by name, sorted.
func _places_text(armies: Array) -> String:
	var names := []
	for a in armies:
		var n := _province_name(a.location)
		if not names.has(n):
			names.append(n)
	names.sort()
	return " and ".join(names)


## "1 army" / "3 armies" for an Array of armies or a count.
static func _count_text(what) -> String:
	var n: int = what.size() if what is Array else int(what)
	return "%d %s" % [n, "army" if n == 1 else "armies"]


## ", even if the enemy army next to it joins in" when an attack's odds count possible reinforcements.
static func _joiners_text(odds: Dictionary) -> String:
	var n := int(odds.get("helpers", 0))
	if n == 0:
		return ""
	return ", even if the enemy %s next to it %s in" % ["army" if n == 1 else "armies", "joins" if n == 1 else "join"]


static func _odds_words(rate: float, label: String = "") -> String:
	var l := label if not label.is_empty() else _label_for(rate)
	return "%s, %d%%" % [l, roundi(rate * 100.0)]
