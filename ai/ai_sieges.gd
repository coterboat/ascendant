class_name AISieges
extends RefCounted
## M3c S-6 (#104): how the computer plays forts and sieges (design/M3C_SIEGES.md §8). It covers besieging and
## storming, the stay rule with its 2-move relief horizon, holding, sallies, relief with a sally, leaving a
## hopeless fort, garrisons, engines, recruiting across forts, and Fortify.
##
## AIPlayer calls these functions behind one `state.sieges` check each. None of this runs in a game without
## sieges, so M1, M2 and M4 games play out exactly as before.
##
## Everything is read from the state at the start of the turn. There is no memory between turns (#94's rule),
## and another faction's orders are never read. #184: an aggressive computer (AIPlayer's temperament) storms, besieges,
## stays, fights through a breach, sallies and relieves at AIPlayer.RISK_DISCOUNT worse odds (ai._risk); a steady one at
## the numbers below, exactly as before. Every decision that risks an army uses Forecast's siege odds
## (storm_odds, sally_odds, relief_odds and breach_odds), which fight the real battle rules through
## SiegeRules.next_battle. The rough strength guess stands in only when a fight is lopsided or the plan's
## forecast budget is spent.

# --- §8.1 ------------------------------------------------------------------------------------------
# S-7 (#105) tuned these within §11.3's ±0.1 and ±1; the first values were STORM_WIN 0.65, CAPITAL_STORM_WIN 0.5, RACE_STORM_WIN
# 0.45, SIEGE_START_WIN 0.55, STANDOFF_START_WIN 0.5, SIEGE_STAY_WIN 0.45, SIEGE_SALLY_WIN 0.65, RELIEF_WIN 0.65,
# CAPITAL_RELIEF_WIN 0.5 and REACH 2 (design/M3C_SIEGES.md §11.4 has the runs).
const STORM_WIN := 0.75  # storm a fort when the storm odds are at least this
const CAPITAL_STORM_WIN := 0.6  # ...the enemy capital (taking it wins the game)
const RACE_STORM_WIN := 0.55  # ...when an enemy relief army can reach the fort this turn
const SIEGE_START_WIN := 0.45  # start a siege at these odds in the open, counting every enemy army within REACH
const STANDOFF_START_WIN := 0.4  # ...in a #94 stand-off
const SIEGE_STAY_WIN := 0.35  # stay at these odds; on the turn before the breach, only at the start odds
const SIEGE_SALLY_WIN := 0.55  # our garrison armies sally at these odds
const RELIEF_WIN := 0.55  # send relief, with a sally, at these combined odds
const CAPITAL_RELIEF_WIN := 0.4  # ...for the capital
const ABANDON_ODDS := 0.35  # leave a fort that isn't the capital before its breach below these odds in the open
const ENGINES_PER_SIEGE := 2  # engines the computer brings to a siege...
const ENGINES_AT_KEEP := 3  # ...3 when it besieges a keep, where the third saves a turn
const FORTIFY_TURN := 6  # the first turn the computer builds a fort
const MUSTER_WEIGHT := 0.25  # what a fort's recruit limit adds to its capture value (x the cheapest troop's price)
const REACH := 1  # moves: the horizon of the start, stay and abandon rules ("within 1 move"; it was 2)
## The rough guess's strength bonus for each point of defense the walls give in a storm, and for each point of
## cover (only when the forecast is skipped). Taken from §4.2's measurements: walls +4 take about 1.25-1.5 times
## the gold to storm and +6 about 1.5 times (about 2 and 2.5 times the strength), while +2 cover counts only near
## parity.
const WALLS_ROUGH := 0.25
const COVER_ROUGH := 0.05
## The siege forecasts' own budget per plan, in AIPlayer's rough milliseconds (ODDS_BASE...), on top of
## AIPlayer.ODDS_BUDGET. Storms, sieges and sallies risk whole armies, so a decision may overdraw it by
## AIPlayer.ESSENTIAL_OVERDRAFT. That covers a battle of about 55 fighters; past it the rough guess decides.
const ODDS_BUDGET := {"easy": 50.0, "normal": 90.0}
## Siege forecasts a plan may run at most.
const ODDS_CALLS := {"easy": 5, "normal": 8}

var ai = null  # the AIPlayer planning this turn (untyped: the two classes refer to each other)
## The plan's state, faction id and faction, read through the AIPlayer, so a Sacrifice's rebase is seen too.
var state: GameState:
	get:
		return ai._state if ai != null else null
var fid: String:
	get:
		return String(ai._fid) if ai != null else ""
var me: Faction:
	get:
		return ai._me if ai != null else null
## The main army's fort objective at the start of the plan (target_from), or "".
var target := ""
var calls := 0
var budget := 0.0
var _main_loc := ""
var _main: Array = []  # the armies of our strongest group at the start of the plan
var _cache := {}
var _scratch: GameState = null
var _kept := {}  # enemy fort id -> true where our armies stay in the siege this turn
var _goal := {}  # the siege engines go to (_engine_goal)
var _storms: Array = []  # fort ids we storm this turn, in order
var _sallies: Array = []  # [{"army", "with"}], in order
var _abandon := {}  # our fort id -> where its garrison goes
var _engines := {}  # {"at", "count", "fort", "carrier"}, or {}
var _fortify := ""
var _reserved := 0  # gold set aside for Fortify and engines before the troops are planned


## Called by AIPlayer._begin on every plan of a game with sieges: it resets this plan's siege state. The
## guesses (ground_bonus, defense_rate) work from here on, before the stand-off is read.
func attach(p_ai) -> void:
	ai = p_ai
	calls = 0
	budget = float(ODDS_BUDGET[ai._level])
	_cache = {}
	_scratch = null
	_kept = {}
	_goal = {}
	_storms = []
	_sallies = []
	_abandon = {}
	_engines = {}
	_fortify = ""
	_reserved = 0
	_main_loc = ""
	_main = []
	target = ""


## Called by AIPlayer._plan_standoff on every plan: picks the main army's fort objective. In a stand-off,
## #94's "siege" action becomes this real siege.
func begin() -> void:
	var groups: Array = ai._free_groups()
	_main_loc = String(groups[0].loc) if not groups.is_empty() else ""
	_main = groups[0].armies.duplicate() if not groups.is_empty() else []
	target = target_from(_main_loc, "", _main) if not _main_loc.is_empty() else ""


## Lets go of the plan's state (AIPlayer calls it when the plan is done).
func end() -> void:
	ai = null
	_scratch = null
	_cache = {}
	_main = []


## §8.2 targets: the nearest enemy fort with a garrison on a shortest road from `loc` to `objective`, an enemy
## capital (the nearest one when `objective` is ""), that `armies` could take by the rough guess (feasible).
## Returns the capital itself when no such fort stands on the road, so a fort the enemy's whole army holds
## sends the army around it (route_step) rather than to wait at its walls. An empty fort is not a target,
## because the army walks into it on the way (_best_capture).
func target_from(loc: String, objective: String, armies: Array = []) -> String:
	var cap := objective if not objective.is_empty() else String(ai._objective_for(loc))
	if cap.is_empty():
		return objective
	var full: int = ai._d(loc, cap)
	var best := cap
	var best_d := full
	for p in ai._sorted_provinces():
		if p.fort_level <= 0 or p.owner.is_empty() or p.owner == fid or p.id == cap:
			continue
		if SiegeRules.garrison(state, p.id).is_empty():
			continue
		var d: int = ai._d(loc, p.id)
		if d < best_d and d + int(ai._d(p.id, cap)) == full and (armies.is_empty() or feasible(p.id, armies)):
			best = p.id
			best_d = d
	return best


## Whether `armies` could take the enemy fort `pid` by the rough guess (no forecast): storm it at the storm
## threshold, or besiege it at the start threshold against its garrison plus every enemy army within REACH.
func feasible(pid: String, armies: Array) -> bool:
	var p := state.find_province(pid)
	var held := SiegeRules.garrison(state, pid)
	if held.is_empty() or p.walls <= 0:
		return true
	if _rough_rate(ai._ratio(armies, held, 1.0, _walls_factor(p.walls))) >= _storm_need(pid, []):
		return true
	var extra: Array = ai._foes.filter(func(e): return e.location != pid and int(ai._d(e.location, pid)) <= REACH and not _pinned(e))
	return _rough_rate(ai._ratio(armies, ai._foes_at(pid) + extra, 1.0, _cover_factor())) >= _start_win()


## AIPlayer._advance in a game with sieges, 3 or more moves from the objective: a step along the shortest route
## through provinces these armies could stand in safely this turn (no enemy army in them, and safe from the
## enemy armies that could reach them, counting the friends that will be there; the objective's own garrison is
## left to the approach). So an army goes around an enemy army it can't fight. The last steps are
## approach_step's and attack_forts'. "" when no such route leads there.
func route_step(here: String, objective: String, armies: Array) -> String:
	if objective.is_empty() or int(ai._d(here, objective)) < 3:
		return ""
	var dist := {objective: 0}
	var queue: Array = [objective]
	var i := 0
	while i < queue.size():
		var at: String = queue[i]
		i += 1
		for n in ai._nbrs[at]:
			if dist.has(n) or (n != here and not _passable(n, objective, armies)):
				continue
			dist[n] = int(dist[at]) + 1
			queue.append(n)
	if not dist.has(here):
		return ""
	var options := []
	for n in ai._nbrs[here]:
		if dist.has(n) and n != objective and int(dist[n]) == int(dist[here]) - 1 and int(dist[n]) >= 1:
			options.append(n)
	if options.is_empty():
		return ""
	return ai._pick_step(options)


func _passable(pid: String, objective: String, armies: Array) -> bool:
	if not ai._foes_at(pid).is_empty():
		return false
	var threats: Array = ai._threats_to(pid).filter(func(e): return e.location != objective and not _pinned(e))
	if threats.is_empty():
		return true
	var friends: Array = armies + ai._friends_ending_at(pid, armies)
	return ai._ratio(friends, threats, ai._ground_bonus(pid), 1.0) >= AIPlayer.SAFE_RATIO


# --- §8.3 defending forts ------------------------------------------------------------------------

## True when our capital is besieged, so AIPlayer._defend_capital leaves it to defend_forts.
func capital_besieged() -> bool:
	var cap := state.find_province(me.capital)
	return cap != null and cap.owner == fid and not ai._foes_at(cap.id).is_empty() \
		and (not ai._mine_at(cap.id).is_empty() or _ruler_at(cap.id))


## Our forts with enemy armies in them, after the capital's own rule. For each one, in this order: relief with a
## sally, sallies on their own, leaving before the breach, or holding.
func defend_forts() -> void:
	for p in ai._sorted_provinces():
		if p.owner != fid or p.fort_level <= 0:
			continue
		var foes: Array = ai._foes_at(p.id)
		if foes.is_empty():
			continue
		var inside := _free(ai._mine_at(p.id))
		if inside.is_empty() and not _ruler_at(p.id):
			continue
		_under_siege(p, inside, foes)


func _under_siege(p: Province, inside: Array, foes: Array) -> void:
	var cap: bool = p.id == me.capital
	var dmg := int(SiegeRules.siege_damage_at(state, p.id).total)
	var falls: bool = p.walls <= dmg
	# Relief with a sally: every free army next to the fort marches in and every garrison army but the ruler's
	# sallies with it. Through a breach there is no sally: the relief fights beside the garrison there.
	var relief: Array = ai._free_next_to(p.id)
	if not relief.is_empty():
		var need: float = ai._risk(CAPITAL_RELIEF_WIN if cap else RELIEF_WIN)  # #184: less for the aggressive temperament
		var sally: Array = inside if p.walls > 0 else []
		var odds := _relief_odds(p.id, relief, sally)
		if float(odds.rate) >= need:
			for a in relief:
				ai._move(a, p.id)
			for a in inside:
				ai._hold(a)
			for a in sally:
				_sallies.append({"army": a.id, "with": relief[0].id})
			_bump("reliefs")
			if cap:
				ai._home_rate = float(odds.rate)
			var how := "Sallying out of %s with the relief from %s" % [p.name, ai._places_text(relief)] if not sally.is_empty() \
				else "Marching %s to relieve %s" % [ai._army_names(relief), p.name]
			ai._note("%s (odds: %s)." % [how, _odds_text(odds)])
			return
	# Sallies on their own: the strongest garrison armies that win at SIEGE_SALLY_WIN go out, and the rest stay.
	if p.walls > 0 and not inside.is_empty():
		var out := _sally_set(inside, foes)
		if not out.is_empty():
			var odds: Dictionary = out.back()
			out.pop_back()
			for a in inside:
				ai._hold(a)
			for a in out:
				_sallies.append({"army": a.id, "with": ""})
			_bump("sallies")
			if cap:
				ai._home_rate = float(odds.rate)
			var rest := inside.size() - out.size()
			ai._note("Sallying out of %s with %s against the besiegers (odds: %s)%s." % [p.name, ai._army_names(out), _odds_text(odds),
				"" if rest == 0 else "; %s %s inside" % [AIPlayer._count_text(rest), "stays" if rest == 1 else "stay"]])
			return
	# Leaving a fort that isn't the capital the turn before its breach: hopeless in the open, no relief within
	# REACH, and a safe neighbor to go to.
	if not cap and falls and not inside.is_empty() and not _relief_within(p.id):
		var open := _breach_now(p.id)
		if float(open.rate) < ABANDON_ODDS:
			var to := _step_out(p.id, inside, true)
			if not to.is_empty():
				for a in inside:
					ai._move(a, to)
				_abandon[p.id] = to
				_bump("abandons")
				ai._note("Leaving %s for %s: its walls fall %s, in the open %s, and no relief can come within %d turns." % [
					p.name, ai._province_name(to), "this turn" if p.walls > 0 else "now", _open_words(open), REACH])
				return
	for a in inside:
		ai._hold(a)
	if cap:
		ai._home_rate = _rough_rate(ai._ratio(inside + ai._home_guard(), foes, _walls_factor(p.walls), 1.0))
	if p.walls > 0:
		ai._note("Holding %s against the siege: its walls (%d) drop to 0 %s." % [p.name, p.walls,
			_in_turns(SiegeRules.turns_to_breach(p.walls, dmg))])
	else:
		ai._note("Holding the breach at %s: the battle there comes this turn, and the garrison keeps its cover inside." % p.name)
	_march_relief(p)


## The garrison armies that sally, strongest first, up to the first set whose sally odds reach SIEGE_SALLY_WIN (#184: less
## AIPlayer.RISK_DISCOUNT for the aggressive temperament), with those odds last. [] when even the whole garrison doesn't reach them.
func _sally_set(inside: Array, foes: Array) -> Array:
	var by_power := inside.duplicate()
	by_power.sort_custom(func(x, y): return ai._army_power(x) > ai._army_power(y) or (ai._army_power(x) == ai._army_power(y) and x.id < y.id))
	var all := _sally_odds(by_power, foes)
	var need: float = ai._risk(SIEGE_SALLY_WIN)
	if float(all.rate) < need:
		return []
	for n in range(1, by_power.size()):
		var some := by_power.slice(0, n)
		var odds := _sally_odds(some, foes)
		if float(odds.rate) >= need:
			return some + [odds]
	return by_power + [all]


## Our free armies 2 moves from a besieged fort of ours (MASS_REACH moves from the capital) take a safe step
## toward it, so a relief can come next turn.
func _march_relief(p: Province) -> void:
	var reach: int = AIPlayer.MASS_REACH if p.id == me.capital else REACH
	for g in ai._free_groups():
		var d: int = ai._d(g.loc, p.id)
		if d < 2 or d > reach:
			continue
		var step: String = ai._step_toward(String(g.loc), p.id, g.armies)
		if step.is_empty():
			continue
		for a in g.armies:
			ai._move(a, step)
		ai._note("Marching %s to %s, to relieve %s." % [ai._army_names(g.armies), ai._province_name(step), p.name])


## True when an army of ours outside the fort stands within REACH moves of it.
func _relief_within(pid: String) -> bool:
	for a in ai._mine:
		if a.location != pid and int(ai._d(a.location, pid)) <= REACH:
			return true
	return false


## §8.3 garrisons: at least one army stays in each keep or citadel of ours that an enemy army could reach this
## turn, and in a palisade when two or more of our armies stand there. The weakest one stays. The capital has
## its own rule (AIPlayer._defend_capital). It runs twice. Before the attacks (`spare_only`) it holds an army
## only where another stays free to attack. After the attacks, before the field moves, it holds the last one
## too, so marching armies never leave a fort open to a raider.
func keep_garrisons(spare_only: bool = false) -> void:
	for p in ai._sorted_provinces():
		if p.owner != fid or p.fort_level <= 0 or p.id == me.capital or not ai._foes_at(p.id).is_empty():
			continue
		var all: Array = ai._mine_at(p.id)
		if all.any(func(a): return ai._busy.has(a.id) and String(ai._moves.get(a.id, a.location)) == p.id):
			continue  # one already stays
		var inside := _free(all)
		if inside.is_empty() or (p.fort_level < 2 and all.size() < 2) or (spare_only and inside.size() < 2):
			continue
		var threats := _unpinned_threats(p.id)
		if threats.is_empty():
			continue
		inside.sort_custom(func(x, y): return ai._army_power(x) < ai._army_power(y) or (ai._army_power(x) == ai._army_power(y) and x.id < y.id))
		ai._hold(inside[0])
		_bump("garrisons")
		ai._note("Keeping %s in %s: an enemy army at %s could reach this %s this turn, and anyone takes an empty fort by walking in." % [
			ai._army_names([inside[0]]), p.name, ai._places_text(threats), SiegeRules.level_word(p.fort_level)])


## Enemy armies that could reach `pid` this turn, except garrisons that we besiege: they can't come out without
## leaving their own fort.
func _unpinned_threats(pid: String) -> Array:
	return ai._threats_to(pid).filter(func(e): return not _pinned(e))


func _pinned(e: Army) -> bool:
	var p := state.find_province(e.location)
	return p != null and p.fort_level > 0 and p.owner == e.owner and not ai._mine_at(p.id).is_empty()


## Our ruler stays inside a besieged fort of ours, and leaves only with a garrison that abandons it. True when
## that decides the ruler's move (AIPlayer._ruler_moves stops there).
func keeps_ruler() -> bool:
	var r: Army = ai._ruler
	if r == null:
		return false
	var p := state.find_province(r.location)
	if p == null or p.owner != fid or p.fort_level <= 0 or ai._foes_at(p.id).is_empty():
		return false
	var who := RulerRules._cap(RulerRules.current_name(state, fid))
	if _abandon.has(p.id) and TurnResolver.check_move(state, fid, MoveOrder.new(r.id, String(_abandon[p.id]))).is_empty():
		ai._move(r, String(_abandon[p.id]))
		ai._note_top("%s leaves %s with its garrison." % [who, p.name])
		return true
	ai._hold(r)
	ai._note_top("%s stays inside the walls of %s while it is besieged: a ruler never sallies." % [who, p.name])
	return true


# --- §8.2 besieging and storming ------------------------------------------------------------------

## Replaces AIPlayer._strike_capitals in a game with sieges. It runs our sieges under way (storm, wait or
## leave), plans and marches the engines, then handles enemy forts next to our free armies: walk into an empty
## capital, attack through a breach, storm from the march, start a siege, or join one of ours.
func attack_forts() -> void:
	for p in ai._sorted_provinces():
		if p.fort_level <= 0 or p.owner.is_empty() or p.owner == fid:
			continue
		var ours := _free(ai._mine_at(p.id))
		if ours.is_empty() or SiegeRules.garrison(state, p.id).is_empty():
			continue
		_siege_turn(p, ours)
	_goal = _engine_goal()
	_plan_engines()  # before the armies next door move: the carrier waits at its fort
	keep_garrisons(true)
	for p in _fort_order():
		_fort_next_door(p)
	_march_engines()


## One turn of a siege of ours: storm at the threshold; otherwise stay while the stay rule allows; otherwise leave.
func _siege_turn(p: Province, ours: Array) -> void:
	var relief := _relief_for(p.id)
	if p.walls > 0:
		var storm := _storm_odds(p.id, ours, [], relief)
		if float(storm.rate) >= _storm_need(p.id, relief):
			_storm(p, ours, [], storm, relief)
			return
	var dmg := int(SiegeRules.siege_damage_at(state, p.id).total)
	var last: bool = p.walls <= dmg
	var need := _start_win() if last else float(ai._risk(SIEGE_STAY_WIN))
	var open := _open_odds(p.id, ours, true)
	if float(open.rate) >= need:
		for a in ours:
			ai._hold(a)
		_kept[p.id] = true
		if p.walls > 0:
			ai._note("Besieging %s: its walls (%d) drop to 0 %s, and in the open %s." % [p.name, p.walls,
				_in_turns(SiegeRules.turns_to_breach(p.walls, dmg)), _open_words(open)])
		else:
			ai._note("Fighting through the breach at %s: in the open %s." % [p.name, _open_words(open)])
		return
	var to := _step_out(p.id, ours, false)
	if to.is_empty():
		for a in ours:
			ai._hold(a)
		_kept[p.id] = true
		ai._note("Staying in the siege of %s: in the open %s, but there is nowhere safe to go." % [p.name, _open_words(open)])
		return
	for a in ours:
		ai._move(a, to)
	_bump("sieges_left")
	ai._note("Leaving the siege of %s for %s: in the open %s, counting the enemy armies within %d moves%s." % [p.name,
		ai._province_name(to), _open_words(open), REACH, " (the walls fall this turn)" if last and p.walls > 0 else ""])


## An enemy fort next to our free armies.
func _fort_next_door(p: Province) -> void:
	if p.fort_level <= 0 or p.owner.is_empty() or p.owner == fid:
		return
	var att: Array = ai._free_next_to(p.id)
	if att.is_empty():
		return
	var capital: bool = ai._is_enemy_capital(p.id)
	if SiegeRules.garrison(state, p.id).is_empty():
		if capital:
			_walk_in(p, att)
		return  # an empty fort that isn't a capital: _best_capture walks in, with its muster value
	if _kept.has(p.id):
		for a in att:
			ai._move(a, p.id)
		ai._note("Joining the siege of %s with %s." % [p.name, ai._army_names(att)])
		return
	var relief := _relief_for(p.id)
	if p.walls <= 0:
		var odds := _breach_odds_with(p.id, att)
		var need: float = ai._risk(AIPlayer.LIKELY_WIN if ai._standoff.is_empty() else AIPlayer.STANDOFF_WIN)
		if float(odds.rate) >= need:
			for a in att:
				ai._move(a, p.id)
			ai._stats.attacks += 1
			ai._note("Attacking through the breach at %s with %s (odds: %s)." % [p.name, AIPlayer._count_text(att), _odds_text(odds)])
		else:
			ai._stats.held_back += 1
			ai._note("Not attacking through the breach at %s yet (odds: %s)." % [p.name, _odds_text(odds)])
		return
	var storm := _storm_odds(p.id, [], att, relief)
	if float(storm.rate) >= _storm_need(p.id, relief):
		_storm(p, [], att, storm, relief)
		return
	var open := _open_odds(p.id, att, true)
	if float(open.rate) >= _start_win():
		for a in att:
			ai._move(a, p.id)
		var dmg := int(SiegeRules.siege_damage(SiegeRules.troops(att), SiegeRules.engines_of(att)).total)
		_bump("fort_sieges")
		var tail := ""  # #184: below the usual odds, either a long stand-off's rule or the aggressive temperament's risk
		if float(open.rate) < SIEGE_START_WIN:
			tail = " After a long stand-off, even odds are worth a siege." if ai._standoff_fight(float(open.rate), STANDOFF_START_WIN) \
				else " It plays aggressively and takes the risk."
		ai._note("Besieging %s: its walls (%d) drop to 0 %s, and in the open %s.%s" % [p.name, p.walls,
			_in_turns(SiegeRules.turns_to_breach(p.walls, dmg)), _open_words(open), tail])
		return
	ai._stats.held_back += 1
	ai._note("Not besieging %s yet: in the open %s, counting the enemy armies within %d moves." % [p.name, _open_words(open), REACH])


## AIPlayer._strike_capitals' walk-in: an enemy capital with nobody inside is taken by walking in, unless the
## armies next to it could rush back and win.
func _walk_in(p: Province, att: Array) -> void:
	var f := state.find_faction(p.owner)
	var rescuers: Array = ai._foes_next_to(p.id)
	if rescuers.is_empty() or ai._ratio(att, rescuers, 1.0, 1.0) >= AIPlayer.WALK_IN_RATIO:
		for a in att:
			ai._move(a, p.id)
		ai._stats.attacks += 1
		ai._note("Marching into %s: the %s capital is undefended, and taking it wins the game." % [p.name, f.faction_name if f else ""])
	else:
		ai._note("Not walking into %s yet: the %s armies next to it could rush back and win." % [p.name, f.faction_name if f else ""])


func _storm(p: Province, staying: Array, moving: Array, odds: Dictionary, relief: Array) -> void:
	for a in staying:
		ai._hold(a)
	for a in moving:
		ai._move(a, p.id)
	_storms.append(p.id)
	_bump("storms")
	ai._stats.attacks += 1
	var why := "its relief army at %s could reach it this turn" % ai._places_text(relief) if not relief.is_empty() \
		else "over walls of %d" % p.walls
	ai._note("Storming %s now: %s (odds: %s)." % [p.name, why, _odds_text(odds)])


## The storm odds a storm of `pid` needs: CAPITAL_STORM_WIN at an enemy capital, RACE_STORM_WIN when a relief
## army can reach the fort this turn, and STORM_WIN otherwise.
## #184: less AIPlayer.RISK_DISCOUNT for the aggressive temperament (AIPlayer._risk), as are _start_win, the stay odds, the
## breach, the sallies and the relief.
func _storm_need(pid: String, relief: Array) -> float:
	if not relief.is_empty():
		return ai._risk(RACE_STORM_WIN)
	return ai._risk(CAPITAL_STORM_WIN if ai._is_enemy_capital(pid) else STORM_WIN)


func _start_win() -> float:
	return ai._risk(SIEGE_START_WIN if ai._standoff.is_empty() else STANDOFF_START_WIN)


## The fort owner's armies, other than its garrison, that could reach `pid` this turn.
func _relief_for(pid: String) -> Array:
	var p := state.find_province(pid)
	return ai._threats_to(pid).filter(func(e): return e.owner == p.owner and e.location != pid)


## Enemy forts in the order they are judged: the main army's target first, then by id.
func _fort_order() -> Array:
	var out := []
	var first := state.find_province(target) if not target.is_empty() else null
	if first != null and first.fort_level > 0:
		out.append(first)
	for p in ai._sorted_provinces():
		if p.fort_level > 0 and p != first:
			out.append(p)
	return out


## Where armies leaving `pid` go: the neighbor without an enemy army where they are safest, judged against the
## enemy armies that could reach it (leaving out those in `pid`). Ties go to the one closer to our capital, then
## to the lower id. With `safe`, only a neighbor where they would be safe (SAFE_RATIO). "" when there is none.
func _step_out(pid: String, armies: Array, safe: bool) -> String:
	var best := ""
	var best_r := -1.0
	for n in ai._nbrs[pid]:
		if not ai._foes_at(n).is_empty():
			continue
		var friends: Array = armies + ai._friends_ending_at(n, armies)
		var threat: Array = ai._threats_to(n).filter(func(e): return e.location != pid)
		var r: float = 99.0 if threat.is_empty() else ai._ratio(friends, threat, ai._ground_bonus(n), 1.0)
		if safe and r < AIPlayer.SAFE_RATIO:
			continue
		var better := r > best_r + 0.0001
		if not better and absf(r - best_r) <= 0.0001:
			var dn: int = ai._d(n, me.capital)
			var db: int = ai._d(best, me.capital)
			better = dn < db or (dn == db and n < best)
		if better:
			best = n
			best_r = r
	return best


## AIPlayer._advance in a game with sieges, when no step toward the objective is safe: the step next to a target
## fort, two moves off. Next to it, the garrison could only come out and fight us in the open, so the step is
## taken when the siege-start odds at the fort allow it and the step is safe from every other enemy army. This
## replaces #94's camp next to the enemy capital. "" when the step isn't on.
func approach_step(here: String, objective: String, armies: Array) -> String:
	var t := state.find_province(objective)
	if t == null or t.fort_level <= 0 or t.owner.is_empty() or t.owner == fid or int(ai._d(here, objective)) != 2:
		return ""
	if SiegeRules.garrison(state, objective).is_empty():
		return ""
	var options := []
	for n in ai._nbrs[here]:
		if int(ai._d(n, objective)) != 1 or not ai._foes_at(n).is_empty():
			continue
		var friends: Array = armies + ai._friends_ending_at(n, armies)
		var others: Array = ai._threats_to(n).filter(func(e): return e.location != objective)
		if others.is_empty() or ai._ratio(friends, others, ai._ground_bonus(n), 1.0) >= AIPlayer.SAFE_RATIO:
			options.append(n)
	if options.is_empty():
		return ""
	var open := _open_odds(objective, armies, false)
	if float(open.rate) < _start_win():
		return ""
	var step: String = ai._pick_step(options)
	_bump("approaches")
	ai._note("Marching on %s from %s to besiege it: if its garrison comes out, in the open %s, counting the enemy armies within %d moves." % [
		t.name, ai._province_name(step), _open_words(open), REACH])
	return step


# --- §8.2 engines ---------------------------------------------------------------------------------

## The siege engines are bought for: {"fort", "troops", "engines", "lag"}. That is our biggest siege that stays
## this turn with standing walls, otherwise the main army's target while the army is still on its way (2 or more
## moves off) and the target is a fort with a garrison and standing walls. Next to the target, the start rule
## decides first and the engines follow a siege that has begun. "lag" is the turns until our armies besiege it
## (0: they do now). {} when there is none.
func _engine_goal() -> Dictionary:
	var best := {}
	for pid in _kept:
		var p := state.find_province(String(pid))
		if p.walls <= 0:
			continue
		var ours: Array = ai._mine_at(p.id)
		var troops := SiegeRules.troops(ours)
		if best.is_empty() or troops > int(best.troops):
			best = {"fort": p.id, "troops": troops, "engines": SiegeRules.engines_of(ours), "lag": 0}
	if not best.is_empty() or target.is_empty() or _main.is_empty():
		return best
	var t := state.find_province(target)
	if t == null or t.fort_level <= 0 or t.walls <= 0 or SiegeRules.garrison(state, t.id).is_empty() or int(ai._d(_main_loc, t.id)) < 2:
		return {}
	return {"fort": t.id, "troops": SiegeRules.troops(_main), "engines": SiegeRules.engines_of(_main),
		"lag": maxi(0, int(ai._d(_main_loc, t.id)) - 1)}


## Engines for the goal, bought at our keep or citadel nearest it into the army there (or into this turn's first
## recruit there), while the capital's garrison need is met. Never more than the cap (ENGINES_AT_KEEP against a
## keep, ENGINES_PER_SIEGE otherwise), 1 for every 5 troops, the carrier's room or the fort's recruit limit. The
## count is the fewest that make the walls fall soonest once the carrier arrives (the recruit forecast's "turns
## saved"). The carrier holds this turn and marches next turn (_march_engines).
func _plan_engines() -> void:
	if _goal.is_empty() or not _capital_safe():
		return
	var ut: UnitType = SiegeRules.engine_type(fid)
	if ut == null:
		return
	var fort := state.find_province(String(_goal.fort))
	var at := ""
	for p in ai._sorted_provinces():
		if p.owner != fid or p.fort_level < 2 or p.id == fort.id or not ai._foes_at(p.id).is_empty():
			continue
		if not SiegeRules.check_recruit_at(state, fid, p.id, ut, 0).is_empty():
			continue
		if at.is_empty() or int(ai._d(p.id, fort.id)) < int(ai._d(at, fort.id)):
			at = p.id
	if at.is_empty():
		return
	var carrier: Army = null  # never the main army: it marches to the siege itself
	for a in ai._mine:
		if a.location == at and not ai._busy.has(a.id) and not _main.has(a) and SiegeRules.can_carry(a):
			carrier = a
			break
	if carrier == null and not ai._mine_at(at).is_empty():
		return  # this turn's recruits there would join an army that can't carry them (TurnResolver.price_recruits)
	var troops: int = int(_goal.troops) + (carrier.units.size() if carrier != null else 0)
	var have: int = int(_goal.engines)
	for a in ai._mine:
		if a.engines > 0 and a.location != fort.id and not _main.has(a):
			have += a.engines  # already bought, on their way (_march_engines)
	var cap := ENGINES_AT_KEEP if fort.fort_level == 2 else ENGINES_PER_SIEGE
	var room := FortData.ARMY_ENGINES_MAX - (carrier.engines if carrier != null else 0)
	var limit := SiegeRules.recruit_limit(state.find_province(at).fort_level) - (0 if carrier != null else 1)
	var price: int = ai._price(ut)
	var most := mini(mini(cap - have, room), mini(limit, troops / int(FortData.SIEGE.troops_per_engine) - have))
	most = mini(most, (me.gold - _reserved) / maxi(1, price))
	if most <= 0:
		return
	var d_at: int = ai._d(at, fort.id)
	var dmg0 := int(SiegeRules.siege_damage(int(_goal.troops), int(_goal.engines)).total)
	var walls := fort.walls - dmg0 * maxi(0, d_at - int(_goal.lag))
	if walls <= 0:
		return
	var base := SiegeRules.turns_to_breach(walls, int(SiegeRules.siege_damage(troops, have).total))
	var best := 0
	var best_t := base
	for n in range(1, most + 1):
		var t := SiegeRules.turns_to_breach(walls, int(SiegeRules.siege_damage(troops, have + n).total))
		if t < best_t:
			best = n
			best_t = t
	if best == 0:
		return
	_engines = {"at": at, "count": best, "fort": fort.id, "carrier": carrier.id if carrier != null else ""}
	_reserved += best * price
	if carrier != null:
		ai._hold(carrier)
	ai._note("Buying %s at %s for the siege of %s: once they arrive its walls (%d by then) drop to 0 %s instead of %s." % [
		SiegeRules.engines_text(fid, best), ai._province_name(at), fort.name, walls, _in_turns(best_t), _in_turns(base)])


## Our free armies that carry engines march to the goal: into a siege of ours next door, or a safe step closer.
## Next to a siege that hasn't started they wait for the main army.
func _march_engines() -> void:
	if _goal.is_empty():
		return
	var fort := String(_goal.fort)
	for a in ai._mine:
		if ai._busy.has(a.id) or a.engines <= 0 or _main.has(a):
			continue
		var d: int = ai._d(a.location, fort)
		if d == 0:
			continue
		var to := ""
		if d == 1:
			if not _kept.has(fort):
				ai._hold(a)
				continue
			to = fort
		else:
			to = ai._step_toward(a.location, fort, [a])
		if to.is_empty():
			continue
		ai._move(a, to)
		ai._note("Marching %s with %s to the siege of %s." % [ai._army_names([a]), SiegeRules.engines_text(fid, a.engines),
			ai._province_name(fort)])


# --- §8.4 recruiting and building -----------------------------------------------------------------

## After the moves: this turn's Fortify, with its gold (and the engines') set aside before the troops are
## planned (AIPlayer._gold_reserved).
func plan_builds() -> void:
	_fortify = _choose_fortify()
	if not _fortify.is_empty():
		_reserved += SiegeRules.fortify_cost(state, _fortify)
	ai._gold_reserved = _reserved
	if _reserved > 0 and ai._level == "easy":
		ai._recruit_plan = ai._plan_recruits([])


## §8.4 Fortify, from FORTIFY_TURN, one site at a time, on a turn when the capital is safe. First choice is
## raising the palisade nearest the front to a keep when no enemy army is within REACH of it. Otherwise a
## palisade in a province we own, at least 2 moves from our capital, with no enemy army in it or next to it,
## nearest the enemy capital (ties go to income, then id). "" when there is none, or the gold left after the
## engines doesn't cover it.
func _choose_fortify() -> String:
	if state.current_turn + 1 < FORTIFY_TURN or not _capital_safe():
		return ""
	if not SiegeRules.site_of(state, fid).is_empty():
		return ""
	var up := ""
	var site := ""
	for p in ai._sorted_provinces():
		if p.owner != fid or p.is_capital or p.fort_level >= FortData.MAX_BUILT:
			continue
		if not SiegeRules.check_fortify(state, fid, p.id).is_empty():
			continue
		if p.fort_level == 1:
			if not ai._foe_within(p.id, REACH) and (up.is_empty() or _nearer_front(p, up)):
				up = p.id
		elif int(ai._d(p.id, me.capital)) >= 2 and ai._foes_at(p.id).is_empty() and ai._foes_next_to(p.id).is_empty():
			if site.is_empty() or _nearer_front(p, site):
				site = p.id
	var gold := me.gold - _reserved
	for pid in [up, site]:
		if not String(pid).is_empty() and gold >= SiegeRules.fortify_cost(state, pid):
			return pid
	return ""


func _nearer_front(p: Province, other_id: String) -> bool:
	var o := state.find_province(other_id)
	var dp := _to_enemy(p.id)
	var do_ := _to_enemy(o.id)
	if dp != do_:
		return dp < do_
	if p.income != o.income:
		return p.income > o.income
	return p.id < o.id


## Moves from `pid` to the nearest enemy capital.
func _to_enemy(pid: String) -> int:
	var best := 999
	for f in state.factions:
		if f.id == fid:
			continue
		var c := state.find_province(f.capital)
		if c != null and c.owner != fid:
			best = mini(best, int(ai._d(pid, c.id)))
	return best


## A fort's capture value (§8.2): MUSTER_WEIGHT x its recruit limit x the price of our cheapest troop. 0 for a
## province without a fort.
func muster_value(p: Province) -> float:
	if p.fort_level <= 0:
		return 0.0
	var cheapest := 0
	for ut in me.unit_types:
		if ut.cost <= 0 or MarkRules.is_poured(ut):  # CW-12: a candlebeast is poured only in Deep Wake, not at any fort
			continue
		var price: int = ai._price(ut)
		if cheapest == 0 or price < cheapest:
			cheapest = price
	return MUSTER_WEIGHT * SiegeRules.recruit_limit(p.fort_level) * cheapest


## Replaces AIPlayer._checked_recruits in a game with sieges. The order is this turn's Fortify first, then the
## recruit plan spread across our forts (§8.4), then the engines. Warband Muster takes the first regular units as
## before. Each order is checked with TurnResolver.price_recruits, the price and checks the turn uses.
func checked_recruits() -> Array:
	var out := []
	if not _fortify.is_empty():
		var f := FortifyOrder.new(_fortify)
		if bool(TurnResolver.price_recruits(state, fid, [f], null, ai._ritual_gold).results.back().ok):
			out.append(f)
			_bump("forts_ordered")
			var p := state.find_province(_fortify)
			if p.fort_level == 1:
				ai._note_top("Raising the palisade at %s to a keep, to recruit commanders and engines nearer the front." % p.name)
			else:
				ai._note_top("Building a palisade at %s, to recruit nearer the front." % p.name)
	var field: int = ai._field_recruit_count()
	var places := _places()
	var eng_at := String(_engines.get("at", ""))
	var eng_count := int(_engines.get("count", 0))
	var need_carrier: bool = not _engines.is_empty() and String(_engines.carrier).is_empty()
	var counts := {}
	var tallies := {}
	var order_of := []
	for ut in ai._recruit_plan:
		var tries := []
		if field > 0 and not ut.is_commander:
			tries.append(RecruitOrder.AT_RULER)
		if need_carrier:
			tries.append(eng_at)
		tries.append_array(places)
		var placed := ""
		for at in tries:
			if at == eng_at and int(counts.get(at, 0)) >= _limit(at) - eng_count:
				continue
			var order := RecruitOrder.new(ut.id, "" if at == me.capital else at)
			var trial := out.duplicate()
			trial.append(order)
			var r: Dictionary = TurnResolver.price_recruits(state, fid, trial, null, ai._ritual_gold).results.back()
			if not r.ok:
				continue
			out.append(order)
			placed = at
			counts[at] = int(counts.get(at, 0)) + 1
			if not tallies.has(at):
				tallies[at] = {"counts": {}, "names": [], "spent": 0}
				order_of.append(at)
			var tally: Dictionary = tallies[at]
			tally.spent += int(r.cost)
			if not tally.counts.has(ut.name):
				tally.counts[ut.name] = 0
				tally.names.append(ut.name)
			tally.counts[ut.name] += 1
			break
		if placed.is_empty():
			ai._stats.dropped_invalid += 1
			continue
		if placed == eng_at:
			need_carrier = false
		if placed == RecruitOrder.AT_RULER:
			field -= 1
			ai._stats.field_recruits += 1
	if not _engines.is_empty() and not need_carrier:
		var ut: UnitType = SiegeRules.engine_type(fid)
		var bought := 0
		for i in eng_count:
			var o := RecruitOrder.new(ut.id, eng_at)
			var trial := out.duplicate()
			trial.append(o)
			if not bool(TurnResolver.price_recruits(state, fid, trial, null, ai._ritual_gold).results.back().ok):
				break
			out.append(o)
			bought += 1
		if bought > 0:
			_bump("engines_bought", bought)
	ai._stats.recruits = out.filter(func(o): return o is RecruitOrder).size()
	for at in order_of:
		var tally: Dictionary = tallies[at]
		if at == RecruitOrder.AT_RULER:
			var dest: String = ai._ruler.location if ai._ruler != null else ""
			ai._note_top("Recruiting with %s for %d gold: %s, joining our armies at %s at the end of the turn (Warband Muster)." % [
				RulerRules.current_name(state, fid), tally.spent, AIPlayer._tally_text(tally), ai._province_name(dest)])
		else:
			ai._note("Recruiting at %s for %d gold: %s." % [ai._province_name(at), tally.spent, AIPlayer._tally_text(tally)])
	return out


## Where recruits go, best first (§8.4), as province ids. These are our forts that aren't besieged and can take
## recruits this turn. First comes the capital while it is threatened or its garrison need isn't met, then the
## fort nearest the main army's objective (the forward muster), then the capital, then the other forts by
## distance to the objective.
func _places() -> Array:
	var probe: UnitType = null
	for ut in me.unit_types:
		if ut.cost > 0 and not MarkRules.is_poured(ut) and (probe == null or ut.cost < probe.cost):  # CW-12: a troop any fort takes
			probe = ut
	var forts := []
	for p in ai._sorted_provinces():
		if p.owner != fid or p.fort_level <= 0 or not ai._foes_at(p.id).is_empty():
			continue
		if probe != null and not SiegeRules.check_recruit_at(state, fid, p.id, probe, 0).is_empty():
			continue
		forts.append(p.id)
	var cap: String = me.capital
	var obj := target if not target.is_empty() else String(ai._objective_for(cap))
	var out := []
	if forts.has(cap) and not _capital_safe():
		out.append(cap)
	var fwd := ""
	for pid in forts:
		if fwd.is_empty() or int(ai._d(pid, obj)) < int(ai._d(fwd, obj)):
			fwd = pid
	if not fwd.is_empty() and not out.has(fwd):
		out.append(fwd)
	if forts.has(cap) and not out.has(cap):
		out.append(cap)
	var rest := forts.filter(func(pid): return not out.has(pid))
	rest.sort_custom(func(x, y): return int(ai._d(x, obj)) < int(ai._d(y, obj)) or (int(ai._d(x, obj)) == int(ai._d(y, obj)) and x < y))
	out.append_array(rest)
	return out


func _limit(pid: String) -> int:
	var p := state.find_province(pid)
	return SiegeRules.recruit_limit(p.fort_level) if p != null else 0


## The capital's garrison need is met this turn: we hold it, AIPlayer found it neither short nor below the
## hold target, and no enemy army stands within REACH of it.
func _capital_safe() -> bool:
	var cap := state.find_province(me.capital)
	if cap == null or cap.owner != fid or ai._capital_short:
		return false
	if float(ai._home_rate) < float(AIPlayer.HOLD_TARGET[ai._level]):
		return false
	return not ai._foe_within(me.capital, REACH)


# --- AIPlayer hooks -------------------------------------------------------------------------------

## AIPlayer._attack_armies leaves out battles at forts: an enemy garrison (attack_forts) and a siege of a fort of
## ours (defend_forts).
func skips_battle(pid: String) -> bool:
	var p := state.find_province(pid)
	if p == null or p.fort_level <= 0 or p.owner.is_empty():
		return false
	if p.owner == fid:
		return not ai._mine_at(pid).is_empty() or _ruler_at(pid)
	return not SiegeRules.garrison(state, pid).is_empty()


## AIPlayer._defense_rate at a fort of ours with standing walls: an enemy army next to it can storm it or
## besiege it, no longer simply attack. Our odds are the storm odds seen from inside, from the worst faction.
## The siege that would follow gives us turns to bring relief (defend_forts).
func walls_stand(pid: String) -> bool:
	var p := state.find_province(pid)
	return p != null and p.fort_level > 0 and p.walls > 0 and p.owner == fid


func defense_rate(pid: String, defenders: Array, threats: Array) -> float:
	if defenders.is_empty():
		return 0.0
	var p := state.find_province(pid)
	var ratio: float = ai._ratio(defenders, threats, _walls_factor(p.walls), 1.0)
	if ratio >= AIPlayer.SURE_RATIO:
		return 0.95
	if ratio <= AIPlayer.HOPELESS_RATIO:
		return 0.05
	var by_faction := {}
	for e in threats:
		if not by_faction.has(e.owner):
			by_faction[e.owner] = []
		by_faction[e.owner].append(e)
	var fids: Array = by_faction.keys()
	fids.sort()
	var worst := 1.0
	for f in fids:
		var attackers: Array = by_faction[f]
		var key := "hold|%s|%s|%s" % [pid, _ids(defenders), _ids(attackers)]
		var r := _call(key, _fighters(defenders + attackers), true, func():
			var st: GameState = ai._scratch_with(defenders, pid, true)  # M5-4: a defence is judged at the top of each sighting
			if st == null:
				return {}
			var moves := attackers.map(func(a): return MoveOrder.new(a.id, pid))
			return Forecast.storm_odds(st, String(f), pid, moves, [], fid))
		var ours: float = float(r.win_rate) if r.has("win_rate") else _rough_rate(ai._ratio(defenders, attackers, _walls_factor(p.walls), 1.0))
		worst = minf(worst, ours)
	return worst


## Whether `a` has a siege job this turn (M5-10): a sally, or it stands where we storm or keep a siege. The magic AI casts only
## from armies that hold anyway, and leaves these alone.
func engaged(a: Army) -> bool:
	for s in _sallies:
		if String(s.army) == a.id or String(s.get("with", "")) == a.id:
			return true
	return _storms.has(a.location) or _kept.has(a.location)


## After the moves: the storms and sallies planned this turn, each checked with SiegeRules.check_siege_order
## against the moves that passed (`orders`: the orders so far).
func siege_orders(orders: Array) -> Array:
	var moves := orders.filter(func(o): return o is MoveOrder)
	var out := []
	for pid in _storms:
		var o := SiegeOrder.storm(String(pid))
		if SiegeRules.check_siege_order(state, fid, o, moves, out).is_empty():
			out.append(o)
		else:
			ai._stats.dropped_invalid += 1
	for s in _sallies:
		var o := SiegeOrder.sally(String(s.army), String(s.with))
		if SiegeRules.check_siege_order(state, fid, o, moves, out).is_empty():
			out.append(o)
		else:
			ai._stats.dropped_invalid += 1
	return out


# --- odds -----------------------------------------------------------------------------------------

## {"rate", "label", "wins", "samples"} for `ours` (at `pid` or moving in) in the open against the garrison, with
## its cover, plus every enemy army within REACH moves of the fort, imagined inside too. This is the battle a
## sally or the breach would bring (§8.2's start and stay rules). "wins" is -1 for a rough guess.
func _open_odds(pid: String, ours: Array, essential: bool) -> Dictionary:
	var extra: Array = ai._foes.filter(func(e): return e.location != pid and int(ai._d(e.location, pid)) <= REACH and not _pinned(e))
	var foes: Array = ai._foes_at(pid) + extra
	var ratio: float = ai._ratio(ours, foes, 1.0, _cover_factor())
	if ratio >= AIPlayer.SURE_RATIO:
		return _rough(0.95)
	if ratio <= AIPlayer.HOPELESS_RATIO:
		return _rough(0.05)
	var key := "open|%s|%s|%s" % [pid, _ids(ours), _ids(extra)]
	var r := _call(key, _fighters(ours + foes), essential, func():
		var st := _scratch_at(pid, ours + extra)
		return Forecast.breach_odds(st, fid, pid) if st != null else {})
	return _from(r, ratio)


## The storm odds of `pid` with `staying` there and `moving` marching in, with `relief` (the owner's armies that
## can reach it this turn) imagined marching in too. These are Forecast.storm_odds as the orders screen shows them.
func _storm_odds(pid: String, staying: Array, moving: Array, relief: Array) -> Dictionary:
	var p := state.find_province(pid)
	var foes: Array = SiegeRules.garrison(state, pid) + relief
	var ratio: float = ai._ratio(staying + moving, foes, 1.0, _walls_factor(p.walls))
	if ratio <= AIPlayer.HOPELESS_RATIO:
		return _rough(0.05)
	var key := "storm|%s|%s|%s|%s" % [pid, _ids(staying), _ids(moving), _ids(relief)]
	var r := _call(key, _fighters(staying + moving + foes), true, func():
		var moves := moving.map(func(a): return MoveOrder.new(a.id, pid))
		return Forecast.storm_odds(state, fid, pid, moves, relief.map(func(a): return a.id)))
	return _from(r, ratio)


## Our relief `relief` marching into our besieged fort `pid` with `sally` sallying to join it. Through a breach the
## whole garrison fights beside the relief anyway.
func _relief_odds(pid: String, relief: Array, sally: Array) -> Dictionary:
	var foes: Array = ai._foes_at(pid)
	var with: Array = sally if state.find_province(pid).walls > 0 else ai._mine_at(pid)
	var ratio: float = ai._ratio(relief + with, foes, 1.0, 1.0)
	if ratio <= AIPlayer.HOPELESS_RATIO:
		return _rough(0.05)
	var key := "relief|%s|%s|%s" % [pid, _ids(relief), _ids(sally)]
	var r := _call(key, _fighters(relief + sally + foes), true, func():
		var others := relief.slice(1).map(func(a): return MoveOrder.new(a.id, pid))
		return Forecast.relief_odds(state, fid, MoveOrder.new(relief[0].id, pid), sally.map(func(a): return a.id), others))
	return _from(r, ratio)


func _sally_odds(armies: Array, foes: Array) -> Dictionary:
	var ratio: float = ai._ratio(armies, foes, _cover_factor(), 1.0)
	if ratio <= AIPlayer.HOPELESS_RATIO:
		return _rough(0.05)
	var key := "sally|%s" % _ids(armies)
	var r := _call(key, _fighters(armies + foes), true, func(): return Forecast.sally_odds(state, fid, armies.map(func(a): return a.id)))
	return _from(r, ratio)


## Our garrison's odds through the breach at `pid` as things stand (the abandon rule's "odds in the open").
func _breach_now(pid: String) -> Dictionary:
	var inside: Array = ai._mine_at(pid)
	var foes: Array = ai._foes_at(pid)
	var ratio: float = ai._ratio(inside, foes, _cover_factor(), 1.0)
	if ratio >= AIPlayer.SURE_RATIO:
		return _rough(0.95)
	if ratio <= AIPlayer.HOPELESS_RATIO:
		return _rough(0.05)
	var r := _call("breach|%s" % pid, _fighters(inside + foes), true, func(): return Forecast.breach_odds(state, fid, pid))
	return _from(r, ratio)


## Our odds attacking the breached fort `pid` with `att` marching in.
func _breach_odds_with(pid: String, att: Array) -> Dictionary:
	var foes: Array = ai._foes_at(pid)
	var ratio: float = ai._ratio(att, foes, 1.0, _cover_factor())
	if ratio >= AIPlayer.SURE_RATIO:
		return _rough(0.95)
	if ratio <= AIPlayer.HOPELESS_RATIO:
		return _rough(0.05)
	var key := "breach_in|%s|%s" % [pid, _ids(att)]
	var r := _call(key, _fighters(att + foes), true, func():
		return Forecast.breach_odds(state, fid, pid, att.map(func(a): return MoveOrder.new(a.id, pid))))
	return _from(r, ratio)


## One siege forecast within this plan's budget (ODDS_BUDGET and ODDS_CALLS), cached by `key`. Returns {} when
## the budget doesn't allow it or the forecast has no battle.
func _call(key: String, fighters: int, essential: bool, run: Callable) -> Dictionary:
	if _cache.has(key):
		ai._stats.odds_cached += 1
		return _cache[key]
	var cost: float = AIPlayer.ODDS_BASE + AIPlayer.ODDS_PER_FIGHTER * fighters + AIPlayer.ODDS_PER_FIGHTER_SQ * fighters * fighters
	var room: bool = calls < int(ODDS_CALLS[ai._level])
	var allowed: bool = room and budget >= cost
	if essential and room and budget + AIPlayer.ESSENTIAL_OVERDRAFT >= cost:
		allowed = true
	if not allowed:
		ai._stats.odds_skipped += 1
		return {}
	budget -= cost
	calls += 1
	ai._stats.odds_calls += 1
	var r: Dictionary = run.call()
	if not r.get("ok", false):
		r = {}
	_cache[key] = r
	return r


func _from(r: Dictionary, ratio: float) -> Dictionary:
	if r.has("win_rate"):
		return {"rate": float(r.win_rate), "label": String(r.get("label", "")), "wins": int(r.get("wins", 0)),
			"samples": int(r.get("samples", 0))}
	return _rough(_rough_rate(ratio))


func _rough(rate: float) -> Dictionary:
	return {"rate": rate, "label": AIPlayer._label_for(rate), "wins": -1, "samples": 0}


func _rough_rate(ratio: float) -> float:
	return minf(0.95, AIPlayer._rate_from_ratio(ratio))


## The rough guess's bonus for a garrison behind walls of `walls` (their defense, SiegeRules.walls_defense).
func _walls_factor(walls: int) -> float:
	return 1.0 + WALLS_ROUGH * SiegeRules.walls_defense(walls)


## ...and for a garrison fighting from inside in the open (its cover, FortData.COVER_DEFENSE).
func _cover_factor() -> float:
	return 1.0 + COVER_ROUGH * FortData.COVER_DEFENSE


## AIPlayer._ground_bonus in a game with sieges. A garrison can only be stormed this turn, so the walls count for
## a fort of ours or one its owner holds. At an empty enemy fort whoever arrives fights in the open. (Without
## sieges the old flat FORT_BONUS stands for the fort's +2.)
func ground_bonus(pid: String) -> float:
	var p := state.find_province(pid)
	if p == null:
		return 1.0
	if p.fort_level > 0 and (p.owner == fid or not SiegeRules.garrison(state, pid).is_empty()):
		return AIPlayer.HOLD_BONUS * _walls_factor(p.walls)
	return AIPlayer.HOLD_BONUS


## A scratch copy of the state (made once per plan) with `placed` standing in `pid` and every other army where
## it really is. A siege is recorded at `pid` when one now stands there, as the state's checks require. The real
## state is never changed.
func _scratch_at(pid: String, placed: Array) -> GameState:
	if _scratch == null:
		_scratch = state.deep_copy([])
		if _scratch == null:
			return null
		_scratch.current_turn = maxi(1, state.current_turn)
	var ids := {}
	for a in placed:
		ids[a.id] = true
	for a in _scratch.armies:
		var real := state.find_army(a.id)
		if real != null:
			a.location = pid if ids.has(a.id) else real.location
	for p in _scratch.provinces:
		p.siege_since = state.find_province(p.id).siege_since
	var sp := _scratch.find_province(pid)
	if SiegeRules.siege_stands(_scratch, pid) and sp.siege_since <= 0:
		sp.siege_since = _scratch.current_turn
	return _scratch


# --- small helpers --------------------------------------------------------------------------------

func _free(armies: Array) -> Array:
	return armies.filter(func(a): return not ai._busy.has(a.id))


func _ruler_at(pid: String) -> bool:
	return ai._ruler != null and ai._ruler.location == pid


func _ids(armies: Array) -> String:
	var ids := armies.map(func(a): return String(a.id))
	ids.sort()
	return ",".join(ids)


func _fighters(armies: Array) -> int:
	var n := 0
	for a in armies:
		n += a.units.size() + (1 if a.commander != null else 0) + (1 if a.ruler != null else 0)
	return n


func _bump(key: String, by: int = 1) -> void:
	ai._stats[key] = int(ai._stats.get(key, 0)) + by


## "likely win, 70%" and, from the forecast, " (17 of 24 test battles)".
func _odds_text(odds: Dictionary) -> String:
	var words: String = AIPlayer._odds_words(float(odds.rate), String(odds.label))
	if int(odds.wins) >= 0:
		words += ", %d of %d test battles" % [int(odds.wins), int(odds.samples)]
	return words


## "we likely win (19 of 24 test battles)", in the plain words of §8.5; "it is close", "we likely lose".
func _open_words(odds: Dictionary) -> String:
	var label := String(odds.label)
	var head := "we likely win" if label == "likely win" else ("we likely lose" if label == "likely loss" else "it is close")
	if int(odds.wins) >= 0:
		return "%s (%d of %d test battles)" % [head, int(odds.wins), int(odds.samples)]
	return "%s (%d%% by a rough guess)" % [head, roundi(float(odds.rate) * 100.0)]


func _in_turns(n: int) -> String:
	if n <= 0:
		return "now"
	return "in %d %s" % [n, "turn" if n == 1 else "turns"]
