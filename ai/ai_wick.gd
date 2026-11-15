class_name AIWick
extends RefCounted
## CW-6 (#257): how the computer plays Wick and the Wake, and how it plays against them (design/CANDLEWAKE.md §2, §3, §8).
##
## Every army of a faction that keeps a flame (WickRules.has_wick) burns at a flame from 0 to its cap: a win feeds it (+1), a turn
## ended without a battle outside a harbour starves it (-1), its regulars fight at flame - 1 attack, and at 0 they gutter (WickRules).
## So each army of ours carries a budget: from a flame of f it can end f - 1 turns away from a fight or a shelter and still keep a
## flame of 1, and a shelter d moves away is reached with f - (d - 1). The rules below spend that budget, in the order of §8:
##
##   * The rough guess counts the flame (attack_part): every regular of an army whose flame is known fights at flame - 1 attack in
##     AIPlayer._power_units, ours and a rival's alike (a rival's only in clear sight under fog: elsewhere its flame is unknown and
##     counts as none). Forecast.battle_odds fights the real battle rules, which count it already.
##   * Fuel (§8.1, cold_moves and AIPlayer._attackers_for): an army at flame COLD or lower needs a fight it wins. A straggler is
##     worth its step, and a Free Holds garrison next door that it beats at the field moves' odds (AIPlayer.HOLD_ATTACK_RATE) is
##     attacked before anything else. A capture that is a fight counts FUEL_WORTH more for a burning army (capture_bonus).
##   * Harbour in time (§8.2, cold_moves, keep_in_time and guard): a cold army with no fight in reach keeps its flame in a shelter
##     (a harbour, WickRules.harbour: a fort of ours, the Wake-Line or Deep Wake, a cold wake of ours; or the province of a ruler of
##     ours with Vigil, whose floor relights it). Away from one it heads for the nearest; in one it stays with the field moves, so it
##     masses with the armies there and marches with them harbour to harbour, or to a fight. No army of ours ends a turn where its
##     flame could no longer reach a shelter before it burns out (in_time) unless a fight is in reach (purposeful: one next door, so a
##     cold army may end one turn cold on its way to a battle), when a place in reach does better (worth_ending, better_end). A fight
##     is always worth it (a win feeds it, a loss destroys it), and so is a siege, a sally and the capital's defence.
##   * Recruit destination (§8.3, into_for): a recruit never cools a hot army. It names the army it joins: one of ours that holds
##     where it is made at exactly the start flame (joining cools nothing), or a new army of its own. A recruit that joined an army
##     at flame 0 would gutter with it, so it never does. Co-located armies fight on one side, each at its own flame (§2.1), so a
##     new army beside a hot one adds the same bodies to the same battle: "unless outnumbered" never needs the cooling.
##   * Harvest (§8.4, harvest_fight): a ruler of ours with Harvest goes where our armies fight this turn, in reach, when the
##     ruler's odds allow (AIPlayer._ruler_spot), a rival's army before a Free Holds garrison.
##   * Vigil (§8.5): Mother Tallow plays her preset's role, home, where the recruits muster; her floor makes the capital a place
##     where a guttering army relights, so the shelter rules send one there.
##   * The Wake (§8.6, capture_bonus): retaking a cold wake of ours relights it at once at the stage it had (MarkRules), so it is
##     worth RELIGHT_WORTH more as a capture; every harbour the Wake makes (the Wake-Line, Deep Wake, a cold wake) is a shelter.
##   * Against the Candlewake (§8.8, deny_step): when a rival's army at flame HOT or more (in sight) can reach a group of ours that
##     would hold under DENY_WIN as defender (the forecast, as the capital's defence is judged), the group denies it the battle: a
##     fort of ours in reach that holds, else the safest neighbour out of every hot army's reach. Waiting starves the flame.
##
## AIPlayer calls these behind `on` (our armies keep a flame) and `against` (a rival's do): in a game where no seated faction keeps
## a flame neither is set, nothing here runs and nothing here draws from the seat's RNG, so every Crown–Clans game plays exactly
## as before. Like AISieges and AIFog, the instance is attached to a brain for one plan. Its notes say what it did, in plain words.

## §8.1, §8.2: an army at this flame or lower is cold: it needs a fight it wins this turn, or a shelter.
const COLD := 1
## §8.3, §8.8: a flame this high is worth keeping (recruits don't cool it) and, on a rival's army, worth denying a battle.
const HOT := 2
## §8.8: below these odds as defender against a hot rival army, a group of ours denies it the battle.
const DENY_WIN := 0.45
## §8.1: what a capture that is also a fight (a Free Holds garrison) is worth to a burning army, in the field moves' units (gold
## a turn): about a province's income, so it settles a choice between neighbours without outweighing the road.
const FUEL_WORTH := 6.0
## §8.6: what retaking a cold wake of ours is worth on top of the province (it is a harbour again at once, at the stage it had).
const RELIGHT_WORTH := 8.0

var ai = null  # the AIPlayer planning this turn (untyped: the two classes refer to each other)
## Our armies keep a flame (the Candlewake's computer), and a rival's armies keep one (the other side's computer, §8.8).
var on := false
var against := false
var _part := {}  # Unit -> the attack its army's flame gives it (flame - 1), for every army whose flame is known
var _shelters := {}  # province id -> true where an army of ours keeps its flame this turn as things stand (harbour, Vigil)
var _dist := {}  # province id -> moves to the nearest shelter (absent: none can be reached)
var _floors := {}  # province id -> the Vigil floor a ruler of ours gives there


## Called by AIPlayer._begin on every plan, before the armies are sorted: who keeps a flame in this game.
func attach(p_ai) -> void:
	ai = p_ai
	on = WickRules.has_wick(String(ai._fid))
	against = false
	for f in ai._state.factions:
		if f.id != String(ai._fid) and WickRules.has_wick(f.id):
			against = true
	_part = {}
	_shelters = {}
	_dist = {}
	_floors = {}


## Called by AIPlayer._collect_armies, on the plan's state and again when a Sacrifice rebases it: the flame parts of the rough
## guess, and (for our armies) the shelters and the moves to the nearest one.
func refresh() -> void:
	_part = {}
	_shelters = {}
	_dist = {}
	_floors = {}
	if ai == null or not (on or against):
		return
	var state: GameState = ai._state
	for a in state.armies:
		if a.flame < 0:
			continue
		var bonus := WickRules.battle_flame(state, a) - 1
		if bonus == 0:
			continue
		for u in a.units:
			if u.type.trait_id != AutoBattleResolver.MAGE and not u.type.summoned:  # the battle rules' own exceptions
				_part[u] = bonus
	if not on:
		return
	var fid := String(ai._fid)
	var floors := WickRules.vigil_floors(state)
	for key in floors:
		var parts := String(key).split("|")
		if parts.size() == 2 and parts[0] == fid and int(floors[key]) > 0:
			_floors[parts[1]] = int(floors[key])
	var queue := []
	for p in ai._sorted_provinces():
		if WickRules.harbour(state, fid, p.id) or _floors.has(p.id):
			_shelters[p.id] = true
			_dist[p.id] = 0
			queue.append(p.id)
	var i := 0
	while i < queue.size():
		var pid: String = queue[i]
		i += 1
		for n in ai._nbrs.get(pid, []):
			if not _dist.has(n):
				_dist[n] = int(_dist[pid]) + 1
				queue.append(n)


## Lets go of the plan's state (AIPlayer calls it when the plan is done).
func end() -> void:
	ai = null
	_part = {}
	_shelters = {}
	_dist = {}
	_floors = {}


# --- the flame in the rough guess ------------------------------------------------------------------

## The attack `u` gets from its army's flame (flame - 1), for the rough guess; 0 for a unit of an army with no known flame, a mage,
## a summoned creature, a commander or a ruler (the battle rules give none of them a flame part).
func attack_part(u: Unit) -> int:
	return int(_part.get(u, 0))


# --- our flame's budget ----------------------------------------------------------------------------

## Whether an army of ours that ends this turn at `pid` without a battle keeps its flame there: a harbour as the land will be at the
## end of the turn. Our own land is a harbour as it is (a fort, the Wake-Line or Deep Wake, WickRules.harbour); land we take this
## turn by ending there is one when it has a fort, or when it holds a cold wake of ours, which relights at the stage it had.
func shelter_at(pid: String) -> bool:
	var state: GameState = ai._state
	var p: Province = state.find_province(pid)
	if p == null:
		return false
	if p.owner == String(ai._fid):
		return WickRules.harbour(state, String(ai._fid), pid)
	if p.has_fort or p.fort_level > 0:
		return true
	var scar := own_scar(pid)
	return not scar.is_empty() and bool(MarkData.stage(String(ai._fid), int(scar.stage)).get("harbour", false))


## Whether `pid` keeps an army of ours from losing flame when it ends the turn there without a battle: a shelter at the end of the
## turn (shelter_at), or the province of a ruler of ours whose Vigil floor holds it.
func keeps_flame(pid: String) -> bool:
	return shelter_at(pid) or _floors.has(pid)


## The flame an army of ours at `flame` has after this turn's Wick step when it ends the turn at `pid` without a battle (§2.2, the
## rules' own transition, WickRules.next_flame): it keeps it in a shelter (shelter_at) and loses the idle loss elsewhere (1; the
## Red Wake's 2), a flame above the row's cap burns down to it, and a Vigil floor there lifts it.
func flame_after(pid: String, flame: int) -> int:
	return WickRules.next_flame(ai._state, String(ai._fid), flame, false, false, shelter_at(pid), false, int(_floors.get(pid, 0)))


## How far an army of ours at `flame` that ends this turn at `pid` without a battle is from running out of time (§8.2): the flame it
## would reach the nearest shelter with, walking on from `pid` (its flame after this turn's Wick step, less the idle loss for each
## turn it still ends outside one on the way), less 1. 0 or more: it keeps a flame of 1 or more and can still reach a shelter with
## one. Below 0: it can't (an army at flame 0 never can, outside Vigil).
func margin(pid: String, flame: int) -> int:
	var after := flame_after(pid, flame)
	var d := 0 if keeps_flame(pid) else int(_dist.get(pid, 99))
	return after - 1 - WickRules.idle_loss(ai._state, String(ai._fid)) * maxi(0, d - 1)


## Whether an army of ours that ends the turn at `pid` fights there: an enemy army stands there (an attack, a siege or a fort we
## storm), or a Free Holds garrison does.
func fights(pid: String) -> bool:
	return not ai._foes_at(pid).is_empty() or ai._holds.has(pid)


## Whether every army of `armies` that keeps a flame of 1 or more is in time at `pid` (margin 0 or more), or fights there. An army
## at flame 0 has nothing left to lose, so it never holds the others back.
func in_time(armies: Array, pid: String) -> bool:
	if not on or fights(pid):
		return true
	for a in armies:
		if a.flame >= 1 and margin(pid, a.flame) < 0:
			return false
	return true


## Whether `armies` ending this turn at `pid`, with no battle there, are where a burning army should be (§8.1, §8.2): `pid` keeps
## their flame (keeps_flame), or brings a fight in reach (purposeful), or is land they take while every one at flame 1 or more stays
## in time (in_time). A step that only burns the flame down, with no fight at its end and nothing taken, is no place to end a turn.
## A fight always is.
func worth_ending(armies: Array, pid: String) -> bool:
	if not on or fights(pid):
		return true
	if not armies.any(func(a): return a.flame >= 1):
		return true
	if keeps_flame(pid) or purposeful(armies, pid):
		return true
	var p: Province = ai._state.find_province(pid)
	return p != null and p.owner != String(ai._fid) and in_time(armies, pid)


## Whether a fight is in reach of `armies` from `pid` (§8.1): one next door to `pid` (they fight it next turn, whatever their flame
## is by then: a win feeds it), or one their coldest army at flame 1 or more still reaches with a flame of 1 or more, losing the idle
## loss for each turn it ends on the way. A fight is a Free Holds garrison or a rival's army that they match by the rough guess (on
## its ground), or a rival's fort or capital (the march's objective: a siege or a storm).
func purposeful(armies: Array, pid: String) -> bool:
	var coldest := 99
	for a in armies:
		if a.flame >= 1:
			coldest = mini(coldest, a.flame)
	if coldest == 99:
		return true
	var after := flame_after(pid, coldest)
	var loss := WickRules.idle_loss(ai._state, String(ai._fid))
	for t in _fights_for(armies):
		var d: int = ai._d(pid, String(t))
		if d == 1 or (d >= 1 and after - loss * (d - 1) >= 1):
			return true
	return false


## Where `armies` could have a fight (purposeful): every province with a Free Holds garrison or a rival's army they match by the rough
## guess on its ground, and every rival fort or capital that has a garrison. By province id.
func _fights_for(armies: Array) -> Array:
	var out := {}
	for pid in ai._holds:
		if float(ai._ratio(armies, [ai._holds[pid]], 1.0, ai._ground_bonus(String(pid)))) >= 1.0:
			out[String(pid)] = true
	for e in ai._foes:
		if out.has(e.location):
			continue
		var p: Province = ai._state.find_province(e.location)
		if p != null and p.owner == e.owner and (p.has_fort or p.fort_level > 0 or p.is_capital):
			out[e.location] = true
		elif float(ai._ratio(armies, ai._foes_at(e.location), 1.0, ai._ground_bonus(e.location))) >= 1.0:
			out[e.location] = true
	for f in ai._state.factions:
		var cap: Province = ai._state.find_province(f.capital) if f.id != String(ai._fid) else null
		if cap != null and cap.owner == f.id:
			out[cap.id] = true  # a rival capital: the war's end, held or not
	var ids: Array = out.keys()
	ids.sort()
	return ids


## How far `armies` ending at `pid` fall short of time, all told (0 when every one is in time): the sum of each negative margin.
func _shortfall(armies: Array, pid: String) -> int:
	var out := 0
	for a in armies:
		if a.flame >= 1:
			out += mini(0, margin(pid, a.flame))
	return out


## A place for `armies` (all standing at `here`) worth ending the turn at, instead of `dest` (where the plan sent them, which isn't):
## holding at `here` or a safe step to a neighbour that is no fight. One worth ending at (worth_ending) comes first, the nearest to
## `dest` (so the plan's intent holds), then `here`, then by id; otherwise the one that falls least short of time (in_time). `dest`
## itself when nothing in reach does better.
func better_end(armies: Array, here: String, dest: String) -> String:
	var best := dest
	var best_worth := false
	var best_short := _shortfall(armies, dest)
	var best_d := 0
	var places: Array = [here]
	places.append_array(ai._nbrs.get(here, []))
	for pid in places:
		if pid == dest:
			continue
		if pid != here and (fights(pid) or not ai._safe_at(armies + ai._friends_ending_at(pid, armies), pid)):
			continue
		var worth := worth_ending(armies, pid)
		var short := _shortfall(armies, pid)
		var d: int = ai._d(pid, dest)
		var better := false
		if worth != best_worth:
			better = worth
		elif worth:
			better = best == dest or d < best_d
		else:
			better = short > best_short
		if better:
			best = pid
			best_worth = worth
			best_short = short
			best_d = d
	return best


## Our cold wake at `pid` while it lasts (MarkRules: {"faction", "stage", "until_turn"}), or {}.
func own_scar(pid: String) -> Dictionary:
	var state: GameState = ai._state
	var scar: Dictionary = Dictionary(state.marks.get(pid, {})).get("scar", {})
	if scar.is_empty() or String(scar.get("faction", "")) != String(ai._fid):
		return {}
	return scar if MarkRules.end_clock(state) < int(scar.get("until_turn", 0)) else {}


# --- §8.1-§8.2: the cold armies ------------------------------------------------------------------------

## Our armies that are cold (flame COLD or lower) and have no job yet, grouped by where they stand: [{"loc", "armies"}], by
## province id.
func _cold_groups() -> Array:
	var by := {}
	for a in ai._mine:
		if ai._busy.has(a.id) or a.flame < 0 or a.flame > COLD:
			continue
		if not by.has(a.location):
			by[a.location] = []
		by[a.location].append(a)
	var locs: Array = by.keys()
	locs.sort()
	var out := []
	for loc in locs:
		out.append({"loc": loc, "armies": by[loc]})
	return out


## Planned after the attacks and before the field moves (§8.1, §8.2): each group of cold armies of ours, by where it stands, feeds
## its flame on a Free Holds garrison next door that it beats at the field moves' odds (the surest first), or keeps it: it holds in
## a shelter or steps along the shelters toward the front, or steps into a shelter next door, or toward the nearest one. A group
## with none of these is left to the field moves, and the guard keeps it in time there.
func cold_moves() -> void:
	if not on:
		return
	var claimed := {}
	for g in _cold_groups():
		var here: String = g.loc
		var armies: Array = g.armies
		var who := "%s (%s)" % [ai._army_names(armies), _flames_text(armies)]
		var fuel := _fuel_for(here, armies, claimed)
		if not fuel.is_empty():
			claimed[fuel.pid] = true
			for a in armies:
				ai._move(a, String(fuel.pid))
			_bump("fuel")
			ai._note("Feeding the flame: %s %s the %s at %s (%d%% to win); a win lifts the flame by 1." % [who,
				"attacks" if armies.size() == 1 else "attack", "Free Holds", ai._province_name(String(fuel.pid)), roundi(float(fuel.rate) * 100.0)])
			continue
		if shelter_at(here) or _floors.has(here):
			continue  # left to the field moves, so it masses with the armies there; keep_in_time keeps its flame
		var home := _home_step(here, armies)
		if home.is_empty():
			continue
		for a in armies:
			ai._move(a, home)
		_bump("home_steps")
		ai._note("Heading home in time: %s %s to %s, %s, with no fight in reach to win." % [who,
			"goes" if armies.size() == 1 else "go", ai._province_name(home),
			"a harbour, to keep the flame" if shelter_at(home) or _floors.has(home) else "toward the nearest harbour"])


## The best fight next door for cold `armies` at `here` (§8.1): a province with a Free Holds garrison that no other group claimed,
## that they beat together at AIPlayer.HOLD_ATTACK_RATE or better (the field moves' odds), with no enemy army in it. The surest
## first, then the richest, then by id. {"pid", "rate"}, or {}.
func _fuel_for(here: String, armies: Array, claimed: Dictionary) -> Dictionary:
	var best := {}
	for n in ai._nbrs.get(here, []):
		if claimed.has(n) or not ai._holds.has(n) or not ai._foes_at(n).is_empty():
			continue
		var rate: float = ai._hold_rate(armies, n)
		if rate < ai._risk(float(AIPlayer.HOLD_ATTACK_RATE[ai._level])):
			continue
		var p: Province = ai._state.find_province(n)
		if best.is_empty() or rate > float(best.rate) + 0.0001 or (absf(rate - float(best.rate)) <= 0.0001 and p.income > int(best.income)):
			best = {"pid": n, "rate": rate, "income": p.income}
	return best


## Away from any shelter: a safe step into a shelter next door, else one step closer to the nearest shelter (ties: by id). "" when
## there is no safe step that helps.
func _home_step(here: String, armies: Array) -> String:
	var best := ""
	var best_d := int(_dist.get(here, 99))
	for n in ai._nbrs.get(here, []):
		if fights(n) or not ai._safe_at(armies + ai._friends_ending_at(n, armies), n):
			continue
		var d := 0 if shelter_at(n) or _floors.has(n) else int(_dist.get(n, 99))
		if d < best_d:
			best = n
			best_d = d
	return best


static func _coldest(armies: Array) -> int:
	var out := 99
	for a in armies:
		if a.flame >= 0:
			out = mini(out, a.flame)
	return out


## The last word on every army of ours that keeps a flame (§8.2), after every other part of the plan: one that ends the turn out
## of time where a place in reach does better (worth_ending) goes there instead (better_end), with the armies it stands with.
## A fight, a siege, a sally and the armies kept home are left as they are.
func guard() -> void:
	if not on:
		return
	var groups := {}  # "<location>|<destination>" -> armies
	var keys := []
	for a in ai._mine:
		if a.flame < 1 or _committed(a):
			continue
		var dest: String = String(ai._moves.get(a.id, a.location))
		var key := "%s|%s" % [a.location, dest]
		if not groups.has(key):
			groups[key] = []
			keys.append(key)
		groups[key].append(a)
	for key in keys:
		var armies: Array = groups[key]
		var here: String = armies[0].location
		var dest: String = String(ai._moves.get(armies[0].id, here))
		var to := keep_in_time(armies, here, dest)
		if to == dest:
			continue
		for a in armies:
			ai._move(a, to)


## Where `armies` (all at `here`, the plan sending them to `dest`) end the turn so they stay in time (§8.2): `dest` when they are in
## time there or nothing in reach does better, otherwise better_end's place, with a note saying why. AIPlayer._field_moves asks it
## for each group of ours, and guard for every army the other parts of the plan placed.
func keep_in_time(armies: Array, here: String, dest: String) -> String:
	if not on or worth_ending(armies, dest):
		return dest
	var to := better_end(armies, here, dest)
	if to == dest:
		return dest
	var it := "it" if armies.size() == 1 else "they"
	var rather := "hold at %s" % ai._province_name(dest) if dest == here else "go on to %s" % ai._province_name(dest)
	var what := "%s (%s) %s %s rather than %s" % [ai._army_names(armies), _flames_text(armies), "holds at" if to == here else "turns to",
		ai._province_name(to), rather]
	if not in_time(armies, dest):
		_bump("home_in_time")
		ai._note("Home in time: %s: from there %s could no longer reach a harbour before %s flame burns out." % [what, it,
			"its" if armies.size() == 1 else "their"])
	else:
		_bump("harbour_holds" if to == here and keeps_flame(to) else "flame_kept")
		ai._note("Keeping the flame: %s: %s would burn its flame down there with no fight in reach to win%s." % [what, it,
			"" if not keeps_flame(to) else ", and %s keeps it" % ai._province_name(to)])
	return to


## Whether `a` has a job the flame doesn't overrule: it fights where it ends the turn (fights), it holds the capital (a harbour),
## or a siege job of AISieges (a sally, a storm, a siege kept).
func _committed(a: Army) -> bool:
	var dest: String = String(ai._moves.get(a.id, a.location))
	if fights(dest) or dest == String(ai._me.capital):
		return true
	return ai._state.sieges and ai._sieges.engaged(a)


# --- §8.3: where recruits go ----------------------------------------------------------------------------

## The army a recruit of `ut` made at `place` names (RecruitOrder.into, §2.1), so it never cools a hot army and never joins a
## guttering one: "" for a faction that keeps no flame, a commander (it cools nothing), a siege engine or a recruit with the ruler;
## otherwise the lowest-id army of ours that stands at `place` and holds there this turn at exactly the start flame, or a new army
## of its own there (RecruitOrder.NEW_PREFIX and the place's id: one new army a place a turn). `place` "" is the capital.
func into_for(place: String, ut: UnitType) -> String:
	if not on or ut == null or ut.is_commander or SiegeRules.is_engine(ut) or place == RecruitOrder.AT_RULER:
		return ""
	var at: String = place if not place.is_empty() else String(ai._me.capital)
	var start := WickRules.start_flame(ai._state, String(ai._fid))
	for a in ai._mine:  # sorted by id
		if a.location == at and not ai._moves.has(a.id) and a.flame == start:
			return a.id
	return RecruitOrder.NEW_PREFIX + at


## Names the army recruit `order` (of `ut`, made at `place`, a province id) joins: into_for's choice, kept only when the rules accept
## it as it is given (TurnResolver.check_into, the check OrderBook makes); otherwise the order joins as it always did.
func name_army(order: RecruitOrder, place: String, ut: UnitType) -> void:
	if not on or order.is_with_ruler():
		return
	order.into = into_for(place, ut)
	if not order.into.is_empty() and not TurnResolver.check_into(ai._state, String(ai._fid), order, place).is_empty():
		order.into = ""


## The note for this turn's recruits at `place` that form a new army (§8.3, `orders` the recruit orders so far): which hot army of
## ours there they keep from cooling, or which guttering one they keep out of. "" when none forms a new army, or no army of ours
## holds there (a new army is all there could be).
func recruit_note(orders: Array, place: String) -> String:
	if not on:
		return ""
	var group := RecruitOrder.NEW_PREFIX + place
	if not orders.any(func(o): return o is RecruitOrder and o.into == group):
		return ""
	var there: Array = ai._mine.filter(func(a): return a.location == place and not ai._moves.has(a.id) and a.flame >= 0)
	if there.is_empty():
		return ""
	var start := WickRules.start_flame(ai._state, String(ai._fid))
	var hot := there.filter(func(a): return a.flame > start)
	_bump("new_armies")
	if not hot.is_empty():
		return "Recruits at %s form a new army at flame %d: joining %s (%s) would cool %s to flame %d." % [ai._province_name(place), start,
			ai._army_names(hot), _flames_text(hot), "it" if hot.size() == 1 else "them", start]
	var cold := there.filter(func(a): return a.flame < start)
	return "Recruits at %s form a new army at flame %d: %s %s at flame %d, and recruits who joined %s would burn as low." % [
		ai._province_name(place), start, ai._army_names(cold), "burns" if cold.size() == 1 else "burn", _coldest(cold),
		"it" if cold.size() == 1 else "them"]


# --- §8.4: Harvest ------------------------------------------------------------------------------------

## Where our ruler goes to fight for Harvest this turn (§8.4), or "": a ruler of ours with Harvest, in the field (AIPlayer's "field"
## role), goes to a province our armies attack this turn that it can reach in one move, a rival's army before a Free Holds garrison
## (a win over a player raises more), then by id. AIPlayer._ruler_spot still decides whether the odds allow it.
func harvest_fight() -> String:
	if not on or ai._ruler == null:
		return ""
	var f: Faction = ai._me
	if String(RulerRules.ruler_data(f.ruler_type).get("ability", "")) != "harvest":
		return ""
	var here: String = ai._ruler.location
	var best := ""
	var best_player := false
	var targets := {}
	for id in ai._moves:
		targets[String(ai._moves[id])] = true
	var pids: Array = targets.keys()
	pids.sort()
	for pid in pids:
		if pid != here and not ai._nbrs.get(here, []).has(pid):
			continue
		var player: bool = not ai._foes_at(pid).is_empty()
		if not player and not ai._holds.has(pid):
			continue
		if best.is_empty() or (player and not best_player):
			best = pid
			best_player = player
	if not best.is_empty():
		_bump("harvest_fights")
	return best


## Why Harvest is worth the fight, from its data: "a win there raises Wickwardens from the dead (Harvest)".
func harvest_words() -> String:
	var ability := RulerRules.ability_data(ai._me.ruler_type)
	var ut := TurnResolver.recruitable_type(ai._me, String(ability.get("unit", "")))
	return "a win there raises %s from the dead (%s)" % [ut.name if ut != null else "the dead", String(ability.get("name", "Harvest"))]


# --- §8.6: the Wake -------------------------------------------------------------------------------------

## What a capture of `p` is worth on top of the field moves' value (§8.1, §8.6): FUEL_WORTH when it is a fight (a Free Holds
## garrison), and RELIGHT_WORTH when it holds a cold wake of ours, which relights at once. 0 for a faction that keeps no flame.
func capture_bonus(p: Province) -> float:
	if not on or p == null:
		return 0.0
	var out := 0.0
	if ai._holds.has(p.id):
		out += FUEL_WORTH
	if not own_scar(p.id).is_empty():
		out += RELIGHT_WORTH
	return out


## The capture note when `p` holds a cold wake of ours (§3.4's words): "" otherwise.
func relight_note(p: Province) -> String:
	if not on or p == null:
		return ""
	var scar := own_scar(p.id)
	if scar.is_empty():
		return ""
	_bump("relights")
	return "Retaking %s first: our cold wake there relights at once, at %s." % [p.name, MarkRules.stage_name(String(ai._fid), int(scar.stage))]


# --- §8.8: against the Candlewake ----------------------------------------------------------------------

## Our free group `g` ({"loc", "armies"}) against a hot rival army (§8.8): when a rival's army at flame HOT or more, in sight, can
## reach `g`'s province this turn and our odds there as defender (AIPlayer._defense_rate, the forecast) are under DENY_WIN, the
## group denies it the battle. It goes to a fort of ours next door that holds at DENY_WIN or better against what can reach it, else
## to the neighbour out of every hot army's reach where it is safest (the friends that end there with it against the threats next
## to it; ties: nearer our capital, then by id). "" when it holds well enough, or there is nowhere to go.
func deny_step(g: Dictionary) -> String:
	if not against:
		return ""
	var here: String = g.loc
	var armies: Array = g.armies
	var threats: Array = ai._threats_to(here)
	var hot := threats.filter(func(e): return e.flame >= HOT)
	if hot.is_empty():
		return ""
	var rate: float = ai._defense_rate(here, armies, threats)
	if rate >= DENY_WIN:
		return ""
	var fort := ""
	var away := ""
	var away_ratio := -1.0
	var cap: String = String(ai._me.capital)
	for n in ai._nbrs.get(here, []):
		var p: Province = ai._state.find_province(n)
		if p == null or not ai._foes_at(n).is_empty() or ai._holds.has(n):
			continue
		var near: Array = ai._threats_to(n)
		var friends: Array = armies + ai._friends_ending_at(n, armies)
		if p.owner == String(ai._fid) and (p.has_fort or p.fort_level > 0) and fort.is_empty():
			if near.is_empty() or float(ai._defense_rate(n, friends, near)) >= DENY_WIN:
				fort = n
				continue
		if near.any(func(e): return e.flame >= HOT):
			continue
		var r := 99.0 if near.is_empty() else float(ai._ratio(friends, near, ai._ground_bonus(n), 1.0))
		var better := r > away_ratio + 0.0001
		if not better and absf(r - away_ratio) <= 0.0001:
			better = int(ai._d(n, cap)) < int(ai._d(away, cap)) or (int(ai._d(n, cap)) == int(ai._d(away, cap)) and n < away)
		if better:
			away = n
			away_ratio = r
	var to := fort if not fort.is_empty() else away
	if to.is_empty():
		return ""
	_bump("denials")
	var flames := []
	for e in hot:
		flames.append(e.flame)
	ai._note("Denying the battle: %s at %s %s at flame %d and could attack %s, where we would win only %d%%; %s %s to %s%s, so %s burns down waiting." % [
		ai._army_names(hot), ai._places_text(hot), "burns" if hot.size() == 1 else "burn", flames.max(), ai._province_name(here),
		roundi(rate * 100.0), ai._army_names(armies), "pulls back" if armies.size() == 1 else "pull back", ai._province_name(to),
		", behind its walls" if to == fort else ", out of its reach", "it" if hot.size() == 1 else "they"])
	return to


# --- words and counters ---------------------------------------------------------------------------------

## "flame 1", "flames 0 and 1": the flames of `armies`.
static func _flames_text(armies: Array) -> String:
	var flames := []
	for a in armies:
		if a.flame >= 0 and not flames.has(a.flame):
			flames.append(a.flame)
	flames.sort()
	if flames.size() == 1:
		return "flame %d" % flames[0]
	return "flames %s" % RulerRules._and_list(flames.map(func(f): return str(f)))


func _bump(key: String, by: int = 1) -> void:
	ai._stats[key] = int(ai._stats.get(key, 0)) + by
