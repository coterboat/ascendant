class_name AscensionRules
## Research and the paths of ascension (M4, design/M4_ASCENSION.md §2, §3; M4-1, #66). Pure functions over
## GameState and data/paths.gd (PathData): no nodes, no scenes, no randomness. This is the single source
## the resolver, Forecast, Breakdown, RulerRules' unit, income and price numbers, the AI and every screen
## read, so a number can never disagree with itself. Player-facing text: RulesCodex "research*", "path*",
## "node_*", "fork", "oath", "lock_in", "transformation", "forsworn" and the Oaths' economy rules.
##
## Paths are OPT-IN at game setup (§1.3): GameState.with_paths(seed, builds) is the rulers game plus a path
## for every faction (GameState.paths). In any other game every function here reads "no paths": no parts,
## no research, no events, so M1 and M2 games are byte-identical to before.
##
## Reading a faction's path (for M4-2 .. M4-6):
##   has_paths(state)                          the game has paths
##   researched(state, fid)                    node ids, in the order done; researched_turn(state, fid, nid)
##   has_node(state, fid, nid), branch(state, fid)   the sworn side ("celestial_host", ...) or ""
##   research_points(state, fid), research_target(state, fid)   the pool and the target ("" for none).
##                                             The target is PRIVATE (§3.3): only its own faction's screens
##                                             may show it, and no event names it.
##   research_rate(state, fid)                 {"rate", "parts", "capital_held", "others", "text", "short"}
##   node_state(state, fid, nid)               {"state", "code", "reason"}: researched, researching,
##                                             available, needs (with the missing node) or closed (and why)
##   check_research(state, fid, nid)           {} or {"code", "reason"}: the ResearchOrder rule
##   available_nodes(state, fid), path_complete(state, fid)
##   eta(cost, pool, rate)                     turns, counting this one as 1 (§2.3); -1 at rate 0
## The research phase (TurnResolver._research_phase calls these, for each faction in id order):
##   research_step(state, fid, turn)           gain, then complete the target if paid for (in place)
##   apply_node(state, fid, nid, turn)         record it, swear the Oath, apply the §3.4 hp rule
##   set_target(state, fid, nid)               the orders phase, after check_research
##   with_nodes(state, fid, ids)               a copy with those nodes applied (previews, tests)
## Number effects (RulerRules.unit_stats, unit_max_hp, price_mods and province_income_parts add these):
##   unit_parts(state, fid, ut)                {"hp"|"attack"|"defense"|"morale": [part]}, regular units only
##   unit_hp_bonus(state, fid, ut)             the sum of the hp parts
##   price_parts(state, fid, ut)               [part] on the recruit price (Remount Stables, Living Iron)
##   income_parts(state, province)             [part] on a province's income (Market Charters, Tithe of
##                                             Light, Deep Mines, Bounty of the Wild)
##   A part is {"key": "path_<node id>", "node", "name", "value", "note", "codex", "mandate": ""}. ("mandate"
##   is empty so AutoBattleResolver._unit_mods, which keys parts by mandate, reads it without error; M4-3
##   keys path parts by "key".)
## Text: gained_text, done_text, sworn_text, effect_preview, rate_text, closed_reason.

const RESEARCHED := "researched"
const RESEARCHING := "researching"
const AVAILABLE := "available"
const NEEDS := "needs"
const CLOSED := "closed"
## A path part's key, and its factor id in battle reports: "path_crown_arbalests".
const PART_PREFIX := "path_"
## The unit stats a path part can change in unit_parts ("cost" goes through price_parts).
const UNIT_STATS := ["hp", "attack", "defense", "morale"]
## Player-facing words for the unit stats a node changes.
const STAT_WORDS := {"hp": "maximum hit points", "attack": "attack", "defense": "defense", "morale": "morale"}

static var _nodes_by_id := {}


# --- data lookups ---------------------------------------------------------------------------------

## The faction's path: {"id", "name", "codex", "nodes"}, or {} for a faction without one.
static func path_data(faction_id: String) -> Dictionary:
	return PathData.PATHS.get(faction_id, {})


## "the Sunstone Path", or "" for a faction without one.
static func path_name(faction_id: String) -> String:
	return String(path_data(faction_id).get("name", ""))


## The node ids of the faction's path, in data order (the panel's order).
static func node_ids(faction_id: String) -> Array:
	var out := []
	for n in path_data(faction_id).get("nodes", []):
		out.append(n.id)
	return out


## The node with this id, with its "faction" added, or {}.
static func node_data(node_id: String) -> Dictionary:
	if _nodes_by_id.is_empty():
		for fid in PathData.PATHS:
			for n in PathData.PATHS[fid].nodes:
				var copy: Dictionary = n.duplicate(true)
				copy["faction"] = fid
				_nodes_by_id[n.id] = copy
	return _nodes_by_id.get(node_id, {})


static func node_name(node_id: String) -> String:
	return String(node_data(node_id).get("name", "an unknown node"))


static func node_cost(node_id: String) -> int:
	return int(node_data(node_id).get("cost", 0))


static func node_kind(node_id: String) -> String:
	return String(node_data(node_id).get("kind", ""))


## "tier I", "tier II", "Oath" or "transformation".
static func kind_name(node_id: String) -> String:
	return String(PathData.KIND_NAMES.get(node_kind(node_id), ""))


static func is_ordinary(node_id: String) -> bool:
	return PathData.ORDINARY.has(node_kind(node_id))


static func is_oath(node_id: String) -> bool:
	return node_kind(node_id) == PathData.OATH


static func node_effects(node_id: String) -> Dictionary:
	return node_data(node_id).get("effects", {})


## The node as running text: "the Oath of the Dawn" (Oaths take "the"), "Drillyard".
static func node_ref(node_id: String) -> String:
	return "the " + node_name(node_id) if is_oath(node_id) else node_name(node_id)


static func branch_data(branch_id: String) -> Dictionary:
	return PathData.BRANCHES.get(branch_id, {})


## The people a side of the fork makes: "Celestial Host".
static func branch_name(branch_id: String) -> String:
	return String(branch_data(branch_id).get("name", ""))


## The side as running text: "the Celestial Host", "Living Iron".
static func branch_ref(branch_id: String) -> String:
	return String(branch_data(branch_id).get("ref", branch_name(branch_id)))


## The other side of the faction's fork ("" when `branch_id` isn't one of its sides).
static func other_branch(faction_id: String, branch_id: String) -> String:
	if String(branch_data(branch_id).get("faction", "")) != faction_id:
		return ""
	for b in PathData.BRANCHES:
		if b != branch_id and String(PathData.BRANCHES[b].faction) == faction_id:
			return b
	return ""


## An Oath's economy rule name ("Tithe of Light"), or "".
static func economy_rule_name(node_id: String) -> String:
	return String(PathData.ECONOMY_RULES.get(node_id, {}).get("name", ""))


# --- reading a game -------------------------------------------------------------------------------

static func has_paths(state: GameState) -> bool:
	return state != null and state.paths


## Node ids the faction has researched, in the order done ([] without paths).
static func researched(state: GameState, faction_id: String) -> Array:
	var f: Faction = state.find_faction(faction_id) if has_paths(state) else null
	if f == null:
		return []
	var out := []
	for r in f.researched:
		out.append(String(r.get("node", "")))
	return out


static func has_node(state: GameState, faction_id: String, node_id: String) -> bool:
	return researched(state, faction_id).has(node_id)


## The turn at whose end the node was done, or 0 when it isn't researched.
static func researched_turn(state: GameState, faction_id: String, node_id: String) -> int:
	var f: Faction = state.find_faction(faction_id) if has_paths(state) else null
	if f == null:
		return 0
	for r in f.researched:
		if String(r.get("node", "")) == node_id:
			return int(r.get("turn", 0))
	return 0


## The side of the fork the faction swore to ("celestial_host", ...), or "" before its Oath.
static func branch(state: GameState, faction_id: String) -> String:
	var f: Faction = state.find_faction(faction_id) if has_paths(state) else null
	return f.path_branch if f else ""


static func research_points(state: GameState, faction_id: String) -> int:
	var f: Faction = state.find_faction(faction_id) if has_paths(state) else null
	return f.research_points if f else 0


## The faction's research target, or "". Private to that faction (§3.3).
static func research_target(state: GameState, faction_id: String) -> String:
	var f: Faction = state.find_faction(faction_id) if has_paths(state) else null
	return f.research_target if f else ""


## True when nothing is left to research: every node is researched or closed (§2.2: "Path complete").
static func path_complete(state: GameState, faction_id: String) -> bool:
	if not has_paths(state) or path_data(faction_id).is_empty():
		return false
	for nid in node_ids(faction_id):
		var st := String(node_state(state, faction_id, nid).state)
		if st != RESEARCHED and st != CLOSED:
			return false
	return true


# --- research per turn (§2.1) ---------------------------------------------------------------------

## What `faction_id` gains in this turn's research phase, from the provinces it owns as `state` stands:
## PathData.RESEARCH.capital for its capital, if it holds it, and RESEARCH.province for every other
## province it owns. The research phase runs after captures and Sworn Vassals, so it counts those.
## Returns {"rate", "capital_held", "capital_name", "others", "parts": [{"key", "name", "value", "note"}],
## "text" ("Research 9 a turn: Crownkeep 5 (your capital) and 4 from 4 other provinces"), "short"
## ("Crownkeep 5, 4 other provinces 4")}. Rate 0 without paths.
static func research_rate(state: GameState, faction_id: String) -> Dictionary:
	var f: Faction = state.find_faction(faction_id) if has_paths(state) else null
	if f == null:
		return {"rate": 0, "capital_held": false, "capital_name": "", "others": 0, "parts": [], "text": "", "short": ""}
	var cap := state.find_province(f.capital)
	var cap_name: String = cap.name if cap else "your capital"
	var held := cap != null and cap.owner == faction_id
	var others := 0
	for p in state.provinces:
		if p.owner == faction_id and p.id != f.capital:
			others += 1
	var cap_value := int(PathData.RESEARCH.capital) if held else 0
	var per := int(PathData.RESEARCH.province)
	var parts := [
		{"key": "capital", "name": "%s (capital)" % cap_name, "value": cap_value,
			"note": "%d while you hold your capital" % int(PathData.RESEARCH.capital) if held
				else "not held: your capital yields research only while you hold it"},
		{"key": "provinces", "name": _count(others, "other province", "other provinces"), "value": others * per,
			"note": "%d research for each province you own besides the capital" % per},
	]
	var rate := cap_value + others * per
	var text := "Research %d a turn: %s %d (your capital%s) and %d from %s" % [rate, cap_name, cap_value,
		"" if held else ", not held", others * per, _count(others, "other province", "other provinces")]
	var short := "%s %d, %s %d" % [cap_name, cap_value, _count(others, "other province", "other provinces"), others * per]
	return {"rate": rate, "capital_held": held, "capital_name": cap_name, "others": others, "parts": parts,
		"text": text, "short": short}


## The rate in one line for reasons and forecasts: "you gain 7 a turn".
static func rate_text(state: GameState, faction_id: String) -> String:
	return "you gain %d a turn" % int(research_rate(state, faction_id).rate)


# --- node states and the research order (§2.2, §3.1, §3.3) ----------------------------------------

## The state of `node_id` for `faction_id` now: {"state", "code", "reason"}.
##   researched    done ("Drillyard is already researched (done at the end of turn 3).")
##   researching   the current target, still legal
##   available     legal to research now
##   needs         a prerequisite is missing; code "needs_prerequisite" or "needs_two" (an Oath's any two)
##   closed        the other side of the fork, closed by the Oath it swore; or no node at all (codes
##                 "no_paths", "unknown_faction", "unknown_node", "foreign_node")
## Reasons are plain language for the panel and for a rejected ResearchOrder (§2.2):
##   "Arbalests needs Drillyard first. Drillyard costs 10 research; you have 4 and gain 7 a turn."
static func node_state(state: GameState, faction_id: String, node_id: String) -> Dictionary:
	var f := state.find_faction(faction_id)
	if f == null:
		return _st(CLOSED, "unknown_faction", "Those orders are for a faction that is not in this game.")
	if not has_paths(state):
		return _st(CLOSED, "no_paths", "This game has no paths, so there is nothing to research. Paths are a preview: tick Paths (M4 preview) when you set up a new game.")
	var n := node_data(node_id)
	if n.is_empty():
		return _st(CLOSED, "unknown_node", "'%s' is not something to research in this game." % node_id)
	if String(n.faction) != faction_id:
		return _st(CLOSED, "foreign_node", "%s is on the path of the %s, not of the %s." % [_cap(node_ref(node_id)),
			_faction_name(state, String(n.faction)), f.faction_name])
	var done_turn := researched_turn(state, faction_id, node_id)
	if has_node(state, faction_id, node_id):
		return _st(RESEARCHED, "already_researched", "%s is already researched (done at the end of turn %d)." % [
			_cap(node_ref(node_id)), done_turn] if done_turn > 0 else "%s is already researched." % _cap(node_ref(node_id)))
	var sworn := f.path_branch
	if not String(n.branch).is_empty() and not sworn.is_empty() and String(n.branch) != sworn:
		return _st(CLOSED, "closed", closed_reason(state, faction_id))
	var missing := []
	for r in n.requires:
		if not has_node(state, faction_id, String(r)):
			missing.append(String(r))
	if not missing.is_empty():
		var first := String(missing[0])
		return _st(NEEDS, "needs_prerequisite", "%s needs %s first. %s costs %d research; you have %d and gain %d a turn." % [
			_cap(node_ref(node_id)), node_ref(first), _cap(node_ref(first)), node_cost(first), f.research_points,
			int(research_rate(state, faction_id).rate)])
	var any := int(n.get("requires_any", 0))
	if any > 0:
		var ordinary := []
		var done := []
		for nid in node_ids(faction_id):
			if is_ordinary(nid):
				ordinary.append(node_name(nid))
				if has_node(state, faction_id, nid):
					done.append(node_name(nid))
		if done.size() < any:
			var have := "you have researched none yet" if done.is_empty() \
				else "you have researched %d: %s" % [done.size(), _and_list(done)]
			return _st(NEEDS, "needs_two", "%s needs any %d of the %d ordinary nodes first (%s); %s." % [
				_cap(node_ref(node_id)), any, ordinary.size(), _and_list(ordinary), have])
	if f.research_target == node_id:
		return _st(RESEARCHING, "", "")
	return _st(AVAILABLE, "", "")


## Why the other side of the fork is closed: "Closed: you swore the Oath of the Dawn on turn 5, so the
## Oath of the Forge and Living Iron are closed for the rest of the game." "" before an Oath.
static func closed_reason(state: GameState, faction_id: String) -> String:
	var sworn := branch(state, faction_id)
	if sworn.is_empty():
		return ""
	var oath := String(branch_data(sworn).get("oath", ""))
	var other := other_branch(faction_id, sworn)
	return "Closed: you swore %s on turn %d, so %s and %s are closed for the rest of the game." % [node_ref(oath),
		researched_turn(state, faction_id, oath), node_ref(String(branch_data(other).get("oath", ""))), branch_ref(other)]


## {} when `faction_id` may make `node_id` its research target now (a ResearchOrder is legal), otherwise
## {"code", "reason"}: the game has paths, the node is on the faction's path, not yet researched, not
## closed by an Oath it swore, and all its prerequisites were researched by the start of this turn.
## Choosing the node that already is the target is legal (and changes nothing).
static func check_research(state: GameState, faction_id: String, node_id: String) -> Dictionary:
	var st := node_state(state, faction_id, node_id)
	if st.state == AVAILABLE or st.state == RESEARCHING:
		return {}
	return {"code": st.code, "reason": st.reason}


## The nodes the faction may research now (available or the current target), in data order.
static func available_nodes(state: GameState, faction_id: String) -> Array:
	var out := []
	for nid in node_ids(faction_id):
		if check_research(state, faction_id, nid).is_empty():
			out.append(nid)
	return out


## Turns until a node costing `cost` is done with `pool` saved and `rate` a turn, counting the turn being
## ordered as 1 (§2.3): 1 when the pool already covers it, otherwise ceil((cost - pool) / rate). The
## research phase gains before it pays, so a node is done at the end of turn now + eta - 1. -1 when the
## rate is 0 and the pool falls short (it is never done at this rate).
static func eta(cost: int, pool: int, rate: int) -> int:
	if pool >= cost:
		return 1
	if rate <= 0:
		return -1
	return int(ceil(float(cost - pool) / float(rate)))


## The first ResearchOrder in `orders`, or null.
static func queued_research(orders: Array) -> ResearchOrder:
	for o in orders:
		if o is ResearchOrder:
			return o
	return null


# --- the research phase (§2.2 steps 1-3, §3.3, §3.4) ----------------------------------------------

## Makes `node_id` the faction's research target. The orders phase calls it after check_research.
## Nothing moves: the pool simply saves toward the new target (§2.2).
static func set_target(state: GameState, faction_id: String, node_id: String) -> void:
	var f := state.find_faction(faction_id)
	if f != null and has_paths(state):
		f.research_target = node_id


## One faction's research phase, applied to `state` in place, for the turn `turn` (1-based): the pool
## gains research_rate; then, if the target is paid for, its cost is paid and it is done (apply_node).
## At most one node a turn. The target then becomes empty, except after an Oath: its transformation
## becomes the target at once. Points left over stay in the pool, and so do points gained with no target.
## Returns {"faction", "rate", "short", "parts", "pool_before", "gained", "pool_after", "target_before",
## "done" (node id or ""), "cost", "sworn" (the branch an Oath swore, or ""), "target_after", "applied"
## (apply_node's result, or {})}. Nothing happens without paths ({"rate": 0, "done": ""}).
static func research_step(state: GameState, faction_id: String, turn: int) -> Dictionary:
	var f: Faction = state.find_faction(faction_id) if has_paths(state) else null
	if f == null:
		return {"faction": faction_id, "rate": 0, "gained": 0, "done": "", "sworn": "", "applied": {}}
	var rate := research_rate(state, faction_id)
	var before := f.research_points
	f.research_points += int(rate.rate)
	var target := f.research_target
	var out := {"faction": faction_id, "rate": int(rate.rate), "short": rate.short, "parts": rate.parts.duplicate(true),
		"pool_before": before, "gained": int(rate.rate), "pool_after": f.research_points, "target_before": target,
		"done": "", "cost": 0, "sworn": "", "target_after": target, "applied": {}}
	if target.is_empty() or not check_research(state, faction_id, target).is_empty():
		return out
	var cost := node_cost(target)
	if f.research_points < cost:
		return out
	f.research_points -= cost
	out.applied = apply_node(state, faction_id, target, turn)
	out.done = target
	out.cost = cost
	f.research_target = ""
	if is_oath(target):
		out.sworn = String(node_data(target).branch)
		f.research_target = String(branch_data(out.sworn).get("transformation", ""))
	out.pool_after = f.research_points
	out.target_after = f.research_target
	return out


## Records `node_id` as researched at the end of `turn` and starts its effects (§3.4): an Oath swears its
## side (path_branch), which closes the other side; the units already on the map change at once: a part
## raising maximum hp raises current hp by as much, one lowering it lowers current hp by as much, never
## below 1. Does not check legality (research_step does). Returns {"node", "turn", "branch",
## "units_changed", "hp_change" (per unit, the type's max hp change), "hp_total" (current hp gained or
## lost in all)}.
static func apply_node(state: GameState, faction_id: String, node_id: String, turn: int) -> Dictionary:
	var f := state.find_faction(faction_id)
	var before := []
	for a in state.armies:
		if a.owner != faction_id:
			continue
		for u in a.units:
			before.append([u, RulerRules.unit_max_hp(state, u)])
	f.researched.append({"node": node_id, "turn": turn})
	if is_oath(node_id):
		f.path_branch = String(node_data(node_id).branch)
	var changed := 0
	var total := 0
	for pair in before:
		var u: Unit = pair[0]
		var delta: int = RulerRules.unit_max_hp(state, u) - int(pair[1])
		if delta == 0:
			continue
		var old := u.current_hp
		u.current_hp = maxi(1, old + delta)
		changed += 1
		total += u.current_hp - old
	return {"node": node_id, "turn": turn, "branch": f.path_branch, "units_changed": changed, "hp_total": total}


## A copy of `state` with `ids` researched by `faction_id`, in order, as the research phase would apply
## them at the end of `turn` (default: the state's current turn), without paying for them or checking
## them. For previews (M4-4's lock-in preview) and tests. `state` is never changed.
static func with_nodes(state: GameState, faction_id: String, ids: Array, turn: int = -1) -> GameState:
	var copy := state.deep_copy([])
	if copy == null or not has_paths(copy):
		return copy
	for nid in ids:
		apply_node(copy, faction_id, String(nid), copy.current_turn if turn < 0 else turn)
	return copy


# --- number effects (§3.2) ------------------------------------------------------------------------

## The path parts on a regular unit type's stats: {"hp": [part], "attack": [...], "defense": [...],
## "morale": [...]}, one part per researched node with a `unit` effect on that type, in the order done.
## Empty for commanders, rulers and games without paths. RulerRules.unit_stats adds these.
static func unit_parts(state: GameState, faction_id: String, ut: UnitType) -> Dictionary:
	var out := {"hp": [], "attack": [], "defense": [], "morale": []}
	if ut == null or ut.is_commander or ut.is_ruler or not has_paths(state):
		return out
	for nid in researched(state, faction_id):
		var bonus: Dictionary = node_effects(nid).get("unit", {}).get(ut.id, {})
		for stat in UNIT_STATS:
			if bonus.has(stat):
				out[stat].append(_part(nid, int(bonus[stat]), "path: %s, %s" % [node_name(nid), kind_name(nid)]))
	return out


## The sum of the path's hp parts on `ut` (RulerRules.unit_max_hp adds it).
static func unit_hp_bonus(state: GameState, faction_id: String, ut: UnitType) -> int:
	var total := 0
	for p in unit_parts(state, faction_id, ut).hp:
		total += int(p.value)
	return total


## The path parts on the recruit price of `ut`: a `unit` effect's "cost" (Remount Stables -4 on Knights,
## Living Iron +4). Regular units only. RulerRules.price_mods adds these, so every price on screen and
## the recruitment phase include them.
static func price_parts(state: GameState, faction_id: String, ut: UnitType) -> Array:
	var out := []
	if ut == null or ut.is_commander or ut.is_ruler or not has_paths(state):
		return out
	for nid in researched(state, faction_id):
		var bonus: Dictionary = node_effects(nid).get("unit", {}).get(ut.id, {})
		if bonus.has("cost"):
			out.append(_part(nid, int(bonus.cost), "path: %s, %s" % [node_name(nid), kind_name(nid)]))
	return out


## The path parts on what `province` earns its owner (§3.2): Market Charters, Deep Mines and Bounty of the
## Wild (income_terrain, by the province's terrain) and Tithe of Light (tithe_per_province, at the owner's
## capital: n gold for every province the owner holds, the capital included). [] for a neutral province
## or a game without paths. RulerRules.province_income_parts adds these (and keeps the total at 0 or more).
static func income_parts(state: GameState, province: Province) -> Array:
	var out := []
	if province == null or province.owner.is_empty() or not has_paths(state):
		return out
	var fid := province.owner
	var f := state.find_faction(fid)
	for nid in researched(state, fid):
		var fx := node_effects(nid)
		var by_terrain: Dictionary = fx.get("income_terrain", {})
		if by_terrain.has(province.terrain):
			var n := int(by_terrain[province.terrain])
			var part := _part(nid, n, "%s: every %s province you own earns %d %s" % [_part_name(nid), province.terrain,
				absi(n), "more" if n >= 0 else "less"])
			out.append(part)
		if fx.has("tithe_per_province") and f != null and province.id == f.capital:
			var owned := 0
			for p in state.provinces:
				if p.owner == fid:
					owned += 1
			var per := int(fx.tithe_per_province)
			out.append(_part(nid, per * owned, "%s: %d gold for each of your %s" % [_part_name(nid), per,
				_count(owned, "province", "provinces")]))
	return out


## The name a part shows ("Market Charters", "Tithe of Light") for a part key or a node id.
static func part_name(key_or_node: String) -> String:
	return _part_name(key_or_node.trim_prefix(PART_PREFIX))


## The RulesCodex entry for a part key or node id: an Oath's economy rule entry, otherwise the node's.
static func part_codex(key_or_node: String) -> String:
	var nid := key_or_node.trim_prefix(PART_PREFIX)
	if PathData.ECONOMY_RULES.has(nid):
		return String(PathData.ECONOMY_RULES[nid].codex)
	return String(node_data(nid).get("codex", "path_node"))


## The one-sentence rule behind a path part (Breakdown's income tooltips): the node's one-line effect.
static func part_rule(key_or_node: String) -> String:
	var nid := key_or_node.trim_prefix(PART_PREFIX)
	var n := node_data(nid)
	if n.is_empty():
		return ""
	var rule := economy_rule_name(nid)
	if not rule.is_empty():
		return "%s (%s): %s" % [rule, node_ref(nid), String(n.text).get_slice(": ", 1)]
	return "%s (path): %s" % [node_name(nid), String(n.text)]


# --- text -----------------------------------------------------------------------------------------

## The research_gained sentence (§9.5), public, so it never names the target (§3.3): "The Aurel Crown
## gained 9 research (Crownkeep 5, 4 other provinces 4)."
static func gained_text(state: GameState, faction_id: String, step: Dictionary) -> String:
	return "%s gained %d research (%s)." % [_cap(_the_faction(state, faction_id)), int(step.get("gained", 0)),
		String(step.get("short", ""))]


## The research_done sentence (§9.5) for a node `faction_id` just completed in `state` (the state after
## it): "Arbalests researched: the Aurel Crown's Crossbowmen now have 13 attack (was 11)." A node whose
## effect has no number to show reads "Raiding Parties researched by the Thornmane Clans: when their armies
## capture ...". `applied` is apply_node's result, for the units already on the map.
static func done_text(state: GameState, faction_id: String, node_id: String, applied: Dictionary = {}) -> String:
	var effect := _effects_now(state, faction_id, node_id, true)
	var fx := node_effects(node_id)
	var text := "%s researched: %s." % [node_name(node_id), effect]
	if not (fx.has("unit") or fx.has("income_terrain") or fx.has("tithe_per_province")):
		text = "%s researched by %s: %s." % [node_name(node_id), _the_faction(state, faction_id), effect]
	var changed := int(applied.get("units_changed", 0))
	if changed > 0:
		var total := int(applied.get("hp_total", 0))
		text += " %s already on the map %s %d hit points in all." % [_cap(_count(changed, "unit", "units")),
			"gained" if total >= 0 else "lost", absi(total)]
	return text


## The oath_sworn sentence (§5): "The Aurel Crown swore the Oath of the Dawn and set out to become the
## Celestial Host. Living Iron is closed to them for the rest of the game. Tithe of Light: Crownkeep now
## earns 1 more gold for every province they own (+7 now). Researching next: Celestial Host, about 3 turns."
static func sworn_text(state: GameState, faction_id: String, node_id: String) -> String:
	var side := String(node_data(node_id).get("branch", ""))
	var other := other_branch(faction_id, side)
	var who := _cap(_the_faction(state, faction_id))
	var text := "%s swore %s and set out to become %s. %s is closed to them for the rest of the game. %s." % [who,
		node_ref(node_id), branch_ref(side), _cap(branch_ref(other)), _effects_now(state, faction_id, node_id, true)]
	var next := String(branch_data(side).get("transformation", ""))
	var f := state.find_faction(faction_id)
	if f != null and f.research_target == next:
		var n := eta(node_cost(next), f.research_points, int(research_rate(state, faction_id).rate))
		text += " Researching next: %s, %s." % [node_name(next), "at this pace never" if n < 0
			else "about %s" % _count(n, "turn", "turns")]
	return text


## What `node_id` will give `faction_id` once done, with its numbers now (forecasts, the panel), as a
## clause: "your Crossbowmen have 13 attack", "your Knights cost 16 gold", "every plains province you own
## earns 2 more gold (+4 gold a turn now, from Crownkeep and Rivermarch)". Effects that later tickets put
## into play use the node's one-line text.
static func effect_preview(state: GameState, faction_id: String, node_id: String) -> String:
	var copy := with_nodes(state, faction_id, [node_id])
	if copy == null:
		return String(node_data(node_id).get("text", ""))
	return _effects_now(copy, faction_id, node_id, false)


## The node's effects in `state` (where it is researched), as a clause. `past` is for the turn report:
## it names the faction and adds "(was N)" ("the Aurel Crown's Crossbowmen now have 13 attack (was 11)");
## otherwise it speaks to the faction ("your Crossbowmen have 13 attack").
static func _effects_now(state: GameState, faction_id: String, node_id: String, past: bool) -> String:
	var fx := node_effects(node_id)
	var f := state.find_faction(faction_id)
	var clauses := []
	var units: Dictionary = fx.get("unit", {})
	for type_id in units:
		var ut: UnitType = TurnResolver.recruitable_type(f, String(type_id)) if f else null
		if ut == null:
			continue
		var us := RulerRules.unit_stats(state, faction_id, ut.id)
		var has := []
		var verbs := []
		for stat in ["hp", "attack", "defense", "morale"]:
			if units[type_id].has(stat):
				var now := int(us[stat])
				has.append("%d %s%s" % [now, STAT_WORDS[stat], " (was %d)" % (now - int(units[type_id][stat])) if past else ""])
		if not has.is_empty():
			verbs.append("have %s" % _and_list(has))
		if units[type_id].has("cost"):
			var price := int(us.cost)
			verbs.append("cost %d gold%s" % [price, " (was %d)" % (price - int(units[type_id].cost)) if past else ""])
		var whose := "%s %s" % [RulerRules._possessive(_the_faction(state, faction_id)), ut.name] if past else "your %s" % ut.name
		clauses.append("%s %s%s" % [whose, "now " if past else "", _and_list(verbs)])
	var income := 0
	var where := []
	for p in state.provinces:
		if p.owner != faction_id:
			continue
		for part in income_parts(state, p):
			if String(part.node) == node_id and int(part.value) != 0:
				income += int(part.value)
				if not where.has(p.name):
					where.append(p.name)
	var rule := economy_rule_name(node_id)
	var terrains: Dictionary = fx.get("income_terrain", {})
	if not terrains.is_empty():
		var words := []
		for t in terrains:
			var n := int(terrains[t])
			if words.is_empty():
				words.append("every %s province %s %s %d %s gold" % [t, "of %s" % _the_faction(state, faction_id) if past else "you own",
					"now earns" if past else "earns", absi(n), "more" if n >= 0 else "less"])
			else:
				words.append("every %s province %d %s" % [t, absi(n), "more" if n >= 0 else "less"])
		var now_text := "%+d gold a turn now%s" % [income, ", from %s" % _and_list(where) if not where.is_empty() else ""]
		var phrase := ", and ".join(words)
		if past:
			clauses.append("%s%s (%s)" % ["%s: " % rule if not rule.is_empty() else "", phrase, now_text])
		else:
			clauses.append("%s (%s%s)" % [phrase, "%s, " % rule if not rule.is_empty() else "", now_text])
	if fx.has("tithe_per_province"):
		var cap: Province = state.find_province(f.capital) if f else null
		var cap_name: String = cap.name if cap else "your capital"
		if past:
			clauses.append("%s: %s now earns %d more gold for every province they own (%+d now)" % [rule, cap_name,
				int(fx.tithe_per_province), income])
		else:
			clauses.append("%s earns %d more gold for every province you own (%s, %+d now)" % [cap_name,
				int(fx.tithe_per_province), rule, income])
	if clauses.is_empty() or fx.has("capture_gold") or fx.has("blood_levy") or fx.has("forest_stride") or fx.has("new_unit"):
		var text := String(node_data(node_id).get("text", "")).trim_suffix(".")
		if is_oath(node_id):
			text = text.get_slice(". ", 1)  # "Blood Levy: your regular recruits ..."
			if not past and text.contains(": "):
				text = "%s (%s)" % [text.get_slice(": ", 1), text.get_slice(": ", 0)]
		if past:
			text = text.replace("Your ", "Their ").replace("your ", "their ").replace(" you ", " they ")
		if text.begins_with("When ") or text.begins_with("Your ") or text.begins_with("Their "):
			text = text.substr(0, 1).to_lower() + text.substr(1)
		clauses.append(text)
	return "; ".join(clauses)


# --- validation (GameState.validate) --------------------------------------------------------------

## Checks the path rules a state must keep (§11): without paths, no faction has research; with paths,
## every faction has a ruler (paths need rulers) and a path, its pool is 0 or more, its researched nodes
## are its own, each once, each after its prerequisites, done on turns 0 .. current_turn in order, at most
## one Oath, path_branch is that Oath's side, and its target is legal. Appends plain-language messages to
## `errors` (or push_error when it isn't an Array).
static func validate(state: GameState, errors = null) -> bool:
	var ok := true
	for f in state.factions:
		var name := f.faction_name if not f.faction_name.is_empty() else "A faction"
		if not state.paths:
			if f.research_points != 0 or not f.research_target.is_empty() or not f.researched.is_empty() or not f.path_branch.is_empty():
				_report(errors, "%s has research, but this game has no paths." % name)
				ok = false
			continue
		if not f.has_ruler():
			_report(errors, "%s has no ruler, but paths need rulers: a game with paths gives every faction a ruler." % name)
			ok = false
		if path_data(f.id).is_empty():
			_report(errors, "%s has no path in this game." % name)
			ok = false
			continue
		if f.research_points < 0:
			_report(errors, "%s has %d research saved, but research is never below 0." % [name, f.research_points])
			ok = false
		var seen := {}
		var last_turn := 0
		var oaths := []
		for r in f.researched:
			var nid := String(r.get("node", ""))
			var turn := int(r.get("turn", 0))
			var n := node_data(nid)
			if n.is_empty() or String(n.faction) != f.id:
				_report(errors, "%s has researched '%s', which is not on its path." % [name, nid])
				ok = false
				continue
			if seen.has(nid):
				_report(errors, "%s has researched %s twice. Each node is researched once." % [name, node_ref(nid)])
				ok = false
			for req in n.requires:
				if not seen.has(String(req)):
					_report(errors, "%s has researched %s without %s before it." % [name, node_ref(nid), node_ref(String(req))])
					ok = false
			if int(n.get("requires_any", 0)) > 0:
				var ordinary := 0
				for d in seen:
					if is_ordinary(d):
						ordinary += 1
				if ordinary < int(n.requires_any):
					_report(errors, "%s has researched %s with only %d ordinary nodes before it; it needs %d." % [
						name, node_ref(nid), ordinary, int(n.requires_any)])
					ok = false
			if turn < 0 or turn > state.current_turn or turn < last_turn:
				_report(errors, "%s has researched %s on turn %d, which is out of order (this is turn %d)." % [
					name, node_ref(nid), turn, state.current_turn])
				ok = false
			last_turn = maxi(last_turn, turn)
			if is_oath(nid):
				oaths.append(nid)
			seen[nid] = true
		if oaths.size() > 1:
			_report(errors, "%s has sworn two Oaths. Swearing one closes the other for the rest of the game." % name)
			ok = false
		var expected := String(node_data(String(oaths[0])).branch) if oaths.size() == 1 else ""
		if f.path_branch != expected:
			_report(errors, "%s is sworn to '%s', but its Oaths say %s." % [name, f.path_branch,
				"it swore to %s" % branch_ref(expected) if not expected.is_empty() else "it has sworn none"])
			ok = false
		if not f.research_target.is_empty() and f.path_branch == expected:
			var check := check_research(state, f.id, f.research_target)
			if not check.is_empty():
				_report(errors, "%s is researching something it can't: %s" % [name, String(check.reason)])
				ok = false
	return ok


# --- helpers --------------------------------------------------------------------------------------

static func _part(node_id: String, value: int, note: String) -> Dictionary:
	return {"key": PART_PREFIX + node_id, "node": node_id, "name": _part_name(node_id), "value": value, "note": note,
		"codex": part_codex(node_id), "mandate": ""}


## An Oath's part is named for its economy rule ("Deep Mines"); every other node's for itself.
static func _part_name(node_id: String) -> String:
	var rule := economy_rule_name(node_id)
	return rule if not rule.is_empty() else node_name(node_id)


static func _st(state_name: String, code: String, reason: String) -> Dictionary:
	return {"state": state_name, "code": code, "reason": reason}


static func _count(n: int, singular: String, plural: String) -> String:
	return "%d %s" % [n, singular if n == 1 else plural]


static func _faction_name(state: GameState, faction_id: String) -> String:
	var f := state.find_faction(faction_id)
	return f.faction_name if f else RulerRules._faction_display(faction_id)


## "the Aurel Crown": faction names take "the" in running text.
static func _the_faction(state: GameState, faction_id: String) -> String:
	return "the " + _faction_name(state, faction_id)


static func _cap(text: String) -> String:
	return RulerRules._cap(text)


static func _and_list(items: Array) -> String:
	return RulerRules._and_list(items)


static func _report(errors, msg: String) -> void:
	if errors is Array:
		errors.append(msg)
	else:
		push_error(msg)
