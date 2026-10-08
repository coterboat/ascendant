class_name AIFog
extends RefCounted
## M5-4 (#115): how the computer plays under fog of war (design/M5_MAGIC_FOG.md §10.1).
##
## The brain is handed its VIEW (FogRules.view_state) and nothing else, so everything it reads is what a person in its
## seat would be shown: its own side whole, and the rival's armies as stand-ins it has sighted or remembers. Nothing
## here reads the true state, a session or the game seed, and nothing draws from an RNG (§10.1: "no new draws"), so
## the same view always gives the same orders. This file holds the three rules that are new under fog:
##
##   * Stale ghosts (MEMORY_TRUST). A remembered army older than 3 turns is dropped from the view, once, before the
##     plan is made (trusted_view). A newer ghost counts as there: "if it is still there" is what a person assumes too.
##   * The capital check against the top of each sighting (top_view, top). A glimpsed army is a shown number with a
##     range ("about 15", which is 13-17). The plan judges attacks against the shown number, which is what a person
##     sees, but its capital checks (the garrison, the recall, the sacrifice, a ruler's safety) count the top of each
##     total, from the view note, so a cheap mixed army cannot bluff it into freezing and a big one cannot hide.
##   * Scouting (scout). When the objective (the hunted army of a #94 stand-off, otherwise the nearest enemy capital)
##     is out of sight or only remembered, the nearest free army of scouts takes one step toward it, if the step is
##     safe by the same odds rule as every other step. (The other half of the rule, Far Sight, is a ritual and belongs
##     to the magic AI; unseen() is the check it shares.)
##
## AIPlayer calls these behind one `is_view` check each, as it calls AISieges behind `state.sieges`: with fog off none
## of this runs, so games are the same as before. Like AISieges, the instance is attached to a brain for one plan.

## Remembered armies older than this many turns are dropped from the view (§10.1: `MEMORY_TRUST = 3`). A ghost seen
## this turn is 0 turns old.
const MEMORY_TRUST := 3

var ai = null  # the AIPlayer planning this turn (untyped: the two classes refer to each other)
## The plan's view with every sighting at the top of its total (top_view), or null when no sighting has anything above
## its shown number. Same armies, ids and places as the plan's state.
var top_state: GameState = null


# --- the view ---------------------------------------------------------------------------------------

## Whether `state` is one player's view of a fog game (FogRules.view_state), as opposed to the true state.
static func is_view(state: GameState) -> bool:
	return state != null and state.is_view and state.fog


## How many turns ago `army` (a stand-in in `view`) was last seen: -1 for anything that is not a remembered army.
static func ghost_age(view: GameState, army: Army) -> int:
	if army == null or String(army.seen.get("level", "")) != FogData.MEMORY:
		return -1
	return maxi(0, view.current_turn - int(army.seen.get("turn", view.current_turn)))


## `view` with the remembered armies older than MEMORY_TRUST turns taken out (§10.1, "stale ghosts"): a copy when any
## go, otherwise `view` itself. A true state, or a view with no old ghost, comes back as it is. `view` is not changed.
static func trusted_view(view: GameState) -> GameState:
	if not is_view(view):
		return view
	var stale := {}
	for a in view.armies:
		if ghost_age(view, a) > MEMORY_TRUST:
			stale[a.id] = true
	if stale.is_empty():
		return view
	var d := view.to_dict()
	# Nothing else names a ghost: a view's blessing lists only stand-ins that are in sight now (FogRules._view_enchantments).
	d["armies"] = d.armies.filter(func(ad): return not stale.has(String(ad.id)))
	var errors := []
	var out := GameState.from_dict(d, errors)
	if out == null:
		push_error("AIFog.trusted_view: the view without its old ghosts does not load: %s" % " ".join(errors))
		return view
	return out


## `view` with every sighting at the top of its range (§2.4, §10.1): for each rival's pool in a province, each type's
## count is raised from the shown number to the top of its range, the total's top shared out by the shown counts
## (the view note's `counts`, which FogRules.glimpse_counts made). The missing fighters join the pool's first stand-in
## at full hp; commanders and rulers are exact already. null when nothing grows (clear sight, or a sighting that is at
## the top of its range already, as "1-2" is). `view` is not changed. The same top Forecast.top_of_range gives a hover.
static func top_view(view: GameState) -> GameState:
	if not is_view(view):
		return null
	var d := view.to_dict()
	var done := {}
	var added := {}  # army index -> the index of its first added unit
	for i in d.armies.size():
		var ad: Dictionary = d.armies[i]
		var note: Dictionary = ad.get("seen", {})
		if note.is_empty() or ad.has("ruler"):
			continue
		var key := "%s|%s" % [ad.owner, ad.location]
		if done.has(key):
			continue
		done[key] = true
		var counts: Dictionary = note.get("counts", {})
		var first: int = ad.units.size()
		for type_id in counts:
			for k in maxi(0, int(counts[type_id].high) - int(counts[type_id].shown)):
				ad.units.append({"type_id": String(type_id), "current_hp": 1, "owner": String(ad.owner)})
		if ad.units.size() > first:
			added[i] = first
	if added.is_empty():
		return null
	var errors := []
	var out := GameState.from_dict(d, errors)
	if out == null:
		push_error("AIFog.top_view: the top of the view does not load: %s" % " ".join(errors))
		return null
	for i in added:
		var units: Array = out.armies[i].units
		for k in range(int(added[i]), units.size()):
			units[k].current_hp = RulerRules.unit_max_hp(out, units[k])
	return out


# --- one plan ---------------------------------------------------------------------------------------

## Called by AIPlayer._begin on every plan: starts afresh.
func attach(p_ai) -> void:
	ai = p_ai
	top_state = null


## Called by AIPlayer._collect_armies, on the plan's state and again when a Sacrifice rebases it: the top of this view.
func refresh() -> void:
	top_state = null
	if ai != null and is_view(ai._state):
		top_state = top_view(ai._state)


## Lets go of the plan's state (AIPlayer calls it when the plan is done).
func end() -> void:
	ai = null
	top_state = null


## `armies` (stand-ins of the plan's state) as the top of their sightings: the same armies, with the fighters that
## bring each total to the top of its range. `armies` itself when the view has no range to climb.
func top(armies: Array) -> Array:
	if top_state == null:
		return armies
	var out := []
	for a in armies:
		var t: Army = top_state.find_army(a.id)
		out.append(t if t != null else a)
	return out


# --- scouting ---------------------------------------------------------------------------------------

## Whether `pid` is out of the viewer's sight in the plan's view: not owned, not under an army or Far Sight, and out of
## every source's range (FogRules.sight). A province that is only remembered counts as out of sight. The magic AI's
## Far Sight rule asks the same question.
func unseen(pid: String) -> bool:
	if ai == null or pid.is_empty() or not is_view(ai._state):
		return false
	return String(FogRules.sight(ai._state, ai._fid).get(pid, FogRules.VEILED)) == FogRules.VEILED


## The province the plan is heading for (§10.1): the army a stand-off hunts, otherwise the nearest enemy capital to the
## main army (AIPlayer._objective_for), or "".
func objective() -> String:
	if ai == null:
		return ""
	if not ai._hunt.is_empty():
		return String(ai._hunt.pid)
	var groups: Array = ai._free_groups()
	return String(ai._objective_for(groups[0].loc)) if not groups.is_empty() else ""


## A scout army (§2.3): a free army whose fighters are all scouts (Knights, Fangthrowers, Seraphs, Thornwolves) with no
## commander. Anything bigger is a fighting army, and keeps its place in the plan.
static func is_scout_army(army: Army) -> bool:
	if army == null or army.ruler != null or army.commander != null or army.units.is_empty():
		return false
	for u in army.units:
		if not FogRules.is_scout(u.type):
			return false
	return true


## Scouting (§10.1), planned after the attacks and before the field moves: when the objective is unseen, the free scout
## army nearest to it (ties: first by id) takes one step toward it, if the step is safe (AIPlayer._safe_at: the known
## threats there are no stronger than SAFE_RATIO allows) and no enemy army is known to stand there. A capital that is
## short of defenders keeps its scouts. At most one army a turn; no draw.
func scout() -> void:
	if ai == null or not is_view(ai._state) or ai._capital_short:
		return
	var target := objective()
	if target.is_empty() or not unseen(target):
		return
	var best: Army = null
	var best_d := 1 << 30
	for a in ai._mine:  # sorted by id
		if ai._busy.has(a.id) or not is_scout_army(a):
			continue
		var d: int = ai._d(a.location, target)
		if d < best_d and d > 1:  # next to it, the army already sees it
			best = a
			best_d = d
	if best == null:
		return
	var step := _step(best, target)
	if step.is_empty():
		return
	ai._move(best, step)
	ai._stats["scouts"] = int(ai._stats.get("scouts", 0)) + 1
	ai._note("Scouting: %s (%s) goes to %s to look toward %s, which is out of our sight." % [
		ai._army_names([best]), ai._units_text([best]), ai._province_name(step), ai._province_name(target)])


## One safe step from the army's province that gets it closer to `target`, or "". Provinces we do not own first (the
## step captures them), then the highest income, then the first by id: no random spread, because scouting draws nothing.
func _step(army: Army, target: String) -> String:
	var here: String = army.location
	var d_here: int = ai._d(here, target)
	var best := ""
	var best_key := -1.0
	for n in ai._nbrs[here]:
		if int(ai._d(n, target)) != d_here - 1 or not ai._foes_at(n).is_empty():
			continue
		if not ai._safe_at([army] + ai._friends_ending_at(n, [army]), n):
			continue
		var p: Province = ai._state.find_province(n)
		var key := float(p.income) + (100.0 if p.owner != ai._fid else 0.0)
		if key > best_key + 0.0001:  # `_nbrs` is sorted by id, so a tie keeps the first
			best = n
			best_key = key
	return best
