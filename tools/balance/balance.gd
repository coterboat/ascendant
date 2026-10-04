extends RefCounted
## Battle balance helpers (#4), shared by the matchup harness (tools/balance/matchups.gd) and
## tests/test_balance.gd. Pure: builds armies from the real faction data (data/factions.gd) and fights
## seeded battles with the real AutoBattleResolver. Nothing here changes game rules or state.
##
##   var state := Balance.new_state()
##   var row := Balance.batch(state, ["spearmen", "knight_captain"], ["tuskers"], Balance.ground("open"), 200)
##   row.crown_pct  # Aurel Crown's win % over seeds 1..200
##
## Determinism: battle i of a batch is fought on SeededRNG(base_seed + i), so every number the harness
## prints can be replayed exactly.

const CROWN := "kingdom"  # Aurel Crown
const CLANS := "beasts"  # Thornmane Clans

## The ground a batch is fought on. "open": both sides arrived together, so nobody defends and nobody
## gets terrain (the target for the starting-army band). The others name the side that held the
## province (defender) and the province, which sets its terrain and fort.
const GROUNDS := [
	{"key": "open", "label": "Open", "province": "rivermarch", "defender": ""},
	{"key": "plains_crown", "label": "Plains, Crown defends", "province": "rivermarch", "defender": CROWN},
	{"key": "plains_clans", "label": "Plains, Clans defend", "province": "rivermarch", "defender": CLANS},
	{"key": "forest_crown", "label": "Forest, Crown defends", "province": "greenglade", "defender": CROWN},
	{"key": "forest_clans", "label": "Forest, Clans defend", "province": "greenglade", "defender": CLANS},
	{"key": "hills_crown", "label": "Hills, Crown defends", "province": "highcrag", "defender": CROWN},
	{"key": "hills_clans", "label": "Hills, Clans defend", "province": "highcrag", "defender": CLANS},
	{"key": "fort_crown", "label": "Fort, Crown defends", "province": "crownkeep", "defender": CROWN},
	{"key": "fort_clans", "label": "Fort, Clans defend", "province": "fangridge", "defender": CLANS},
]

## Unit order used to fill a mixed army to a budget: line, ranged, elite, line, ranged, line...
const MIX_CYCLE := {
	CROWN: ["spearmen", "crossbowmen", "knights", "spearmen", "crossbowmen", "spearmen"],
	CLANS: ["tuskers", "fangthrowers", "war_bear", "tuskers", "fangthrowers", "tuskers"],
}


## A fresh game state: the real factions and map, with no armies.
static func new_state() -> GameState:
	var s := GameState.new(1)
	s.armies.clear()
	return s


## A fresh game state with rulers (M2-2): `mandates` maps a faction id to the mandate ids it has
## ({CROWN: ["royal_armories"]}); `rulers` maps a faction id to [ruler id, kept power] for a ruler that
## fights beside its army in every battle of a batch (batch's `ruler_fids`). Every faction gets a ruler
## so its mandates count (its default is its first ruler), but only the factions in `rulers` field one.
## No armies. Returns null with the reasons in `errors` when a mandate or ruler doesn't fit the faction.
static func new_state_with(mandates: Dictionary, rulers: Dictionary = {}, errors: Array = []) -> GameState:
	var builds := {}
	for fid in [CROWN, CLANS]:
		var rid: String = rulers[fid][0] if rulers.has(fid) else RulerRules.rulers_for(fid)[0]
		builds[fid] = {"ruler": rid, "mandates": mandates.get(fid, [])}
	var s := GameState.with_rulers(1, builds, errors)
	if s == null:
		return null
	for fid in rulers:
		var f := s.find_faction(fid)
		f.kept_power = clampi(int(rulers[fid][1]), 0, RulerData.POWER_POOL)
		RulerRules.refresh_ruler_type(f)
	s.armies.clear()
	return s


## A fresh state where each faction plays a build preset (M2-8): {CROWN: preset id, CLANS: preset id}.
## Its mandates count, and its ruler at the preset's kept power fights beside its army when batch() gets
## both factions in `ruler_fids`. Null (reasons in `errors`) for an unknown preset or the wrong faction.
static func new_state_presets(presets: Dictionary, errors: Array = []) -> GameState:
	var mandates := {}
	var rulers := {}
	for fid in presets:
		var p := RulerRules.preset_data(str(presets[fid]))
		if p.is_empty() or str(p.faction) != str(fid):
			errors.append("%s is not a preset of %s." % [presets[fid], fid])
			return null
		mandates[fid] = p.mandates.duplicate()
		rulers[fid] = [str(p.ruler), RulerRules.kept_after(p)]
	return new_state_with(mandates, rulers, errors)


## `state` (a rulers game from new_state_with, no armies) with paths on and `nodes` ({fid: [node ids]})
## researched in place (M4-3): their stat and price parts, and the transformation's renamed unit and new
## unit on the roster (AscensionRules.apply_node does that since M4-2; the lines below only fill a gap). Null,
## with the reasons in `errors`, when paths can't be set up. (The harness's state has no armies, not even
## the rulers', which setup_paths' validation reports; only a refusal to turn paths on counts.)
static func with_path_nodes(state: GameState, nodes: Dictionary, errors: Array = []) -> GameState:
	if state == null:
		return null
	var problems := []
	state.setup_paths(problems)
	if not state.paths:
		errors.append_array(problems)
		return null
	for fid in nodes:
		var f := state.find_faction(fid)
		for nid in nodes[fid]:
			if not AscensionRules.has_node(state, fid, nid):
				AscensionRules.apply_node(state, fid, nid, 0)
			var fx := AscensionRules.node_effects(nid)
			var new_unit := String(fx.get("new_unit", ""))
			if not new_unit.is_empty() and TurnResolver.recruitable_type(f, new_unit) == null:
				f.unit_types.append(AscensionRules.new_unit_type(new_unit))
			var renames: Dictionary = fx.get("rename", {})
			for type_id in renames:
				var t := TurnResolver.recruitable_type(f, type_id)
				if t != null:
					t.name = String(renames[type_id])
	return state


## The ruler's army of `owner` at full hp (state with rulers), or null without one.
static func ruler_army(state: GameState, owner: String, id := "") -> Army:
	var f := state.find_faction(owner)
	if f == null or f.ruler_unit_type == null:
		return null
	var a := Army.new()
	a.id = id if not id.is_empty() else owner + "-9"
	a.owner = owner
	a.location = "rivermarch"
	a.ruler = Unit.new(f.ruler_unit_type, owner)
	return a


static func ground(key: String) -> Dictionary:
	for g in GROUNDS:
		if g.key == key:
			return g
	return {}


## An army of `owner` made of `type_ids` (unit and commander type ids). Not added to the state.
static func army(state: GameState, owner: String, type_ids: Array, id := "") -> Army:
	var a := Army.new()
	a.id = id if not id.is_empty() else owner + "-1"
	a.owner = owner
	a.location = "rivermarch"
	var f := state.find_faction(owner)
	for type_id in type_ids:
		var ut := TurnResolver.recruitable_type(f, type_id)
		if ut == null:
			push_error("balance: %s has no unit type %s" % [owner, type_id])
			continue
		if ut.is_commander:
			a.commander = Unit.new(ut, owner)
		else:
			var u := Unit.new(ut, owner)
			u.current_hp = RulerRules.unit_max_hp(state, u)  # Veteran Levies (M2-2); the type's hp without it
			a.units.append(u)
	return a


## Gold cost of recruiting every type in `type_ids` for `owner`.
static func cost(state: GameState, owner: String, type_ids: Array) -> int:
	var total := 0
	for type_id in type_ids:
		total += TurnResolver.recruit_cost(state, owner, type_id)
	return total


## One of each unit type and the commander: the army each faction starts the game with.
static func starting_army(state: GameState, owner: String, with_commander := true) -> Array:
	var f := state.find_faction(owner)
	var ids := []
	for ut in f.unit_types:
		ids.append(ut.id)
	if with_commander and f.commander_type:
		ids.append(f.commander_type.id)
	return ids


## Fills `budget` gold with units in MIX_CYCLE order (skipping a unit it can't afford and taking the
## next affordable one), after `start` (e.g. a commander). Returns type ids.
static func mixed(state: GameState, owner: String, budget: int, start: Array = []) -> Array:
	var ids := start.duplicate()
	var gold := budget - cost(state, owner, ids)
	var cycle: Array = MIX_CYCLE[owner]
	var i := 0
	var misses := 0
	while misses < cycle.size():
		var c := TurnResolver.recruit_cost(state, owner, cycle[i % cycle.size()])
		if c <= gold:
			ids.append(cycle[i % cycle.size()])
			gold -= c
			misses = 0
		else:
			misses += 1
		i += 1
	return ids


## Army styles for the large-army composition matrix (matchups.gd --compositions): unit type ids
## with weights, filled to a budget by ratio_army().
const STYLES := {
	CROWN: [["Spearmen + Crossbowmen 1:1", [["spearmen", 1], ["crossbowmen", 1]]],
		["Spearmen + Crossbowmen 2:1", [["spearmen", 2], ["crossbowmen", 1]]],
		["Spearmen, Crossbowmen, Knights 1:1:1", [["spearmen", 1], ["crossbowmen", 1], ["knights", 1]]],
		["Knights only", [["knights", 1]]],
		["Spearmen only", [["spearmen", 1]]]],
	CLANS: [["Tuskers only", [["tuskers", 1]]],
		["Tuskers + War Bears 2:1", [["tuskers", 2], ["war_bear", 1]]],
		["Tuskers, Fangthrowers, War Bears 1:1:1", [["tuskers", 1], ["fangthrowers", 1], ["war_bear", 1]]],
		["Fangthrowers only", [["fangthrowers", 1]]],
		["War Bears only", [["war_bear", 1]]]],
}


## Fills `budget` gold (after the commander, when `with_commander`) keeping unit counts in the
## proportions of `weights` ([[type id, weight], ...]): each step adds the affordable type furthest
## below its share. Returns type ids.
static func ratio_army(state: GameState, owner: String, weights: Array, budget: int, with_commander := true) -> Array:
	var ids := []
	if with_commander:
		ids.append(state.find_faction(owner).commander_type.id)
	var gold := budget - cost(state, owner, ids)
	var counts := {}
	for w in weights:
		counts[w[0]] = 0
	while true:
		var pick := ""
		var lowest := INF
		for w in weights:
			if TurnResolver.recruit_cost(state, owner, w[0]) <= gold and float(counts[w[0]]) / w[1] < lowest:
				lowest = float(counts[w[0]]) / w[1]
				pick = w[0]
		if pick.is_empty():
			break
		counts[pick] += 1
		gold -= TurnResolver.recruit_cost(state, owner, pick)
	for w in weights:
		ids.append_array(_repeat(w[0], counts[w[0]]))
	return ids


## Counts [a, b] of two unit types whose total costs are as equal as possible, both within 25% of
## `budget` (closest to the budget on a tie).
static func equal_gold(state: GameState, a_type: String, b_type: String, budget: int) -> Array:
	var ca := TurnResolver.recruit_cost(state, CROWN, a_type)
	var cb := TurnResolver.recruit_cost(state, CLANS, b_type)
	var best := [maxi(1, roundi(float(budget) / ca)), maxi(1, roundi(float(budget) / cb))]
	var best_score := INF
	for na in range(1, 40):
		for nb in range(1, 40):
			var ga := na * ca
			var gb := nb * cb
			if ga < budget * 0.75 or ga > budget * 1.25 or gb < budget * 0.75 or gb > budget * 1.25:
				continue
			var score := absf(ga - gb) / maxf(ga, gb) * 1000.0 + absf(ga + gb - 2.0 * budget) / budget
			if score < best_score:
				best_score = score
				best = [na, nb]
	return best


## The matchups the harness prints, built from the current costs: [{"group", "name", "crown", "clans"}].
static func matchups(state: GameState) -> Array:
	var out := []
	out.append({"group": "starting", "name": "Starting armies",
		"crown": starting_army(state, CROWN), "clans": starting_army(state, CLANS)})
	out.append({"group": "starting", "name": "Starting units, no commanders",
		"crown": starting_army(state, CROWN, false), "clans": starting_army(state, CLANS, false)})
	var crown_types := state.find_faction(CROWN).unit_types
	var clans_types := state.find_faction(CLANS).unit_types
	for a in crown_types:
		for b in clans_types:
			var n := equal_gold(state, a.id, b.id, 100)
			out.append({"group": "pair", "name": "%s vs %s" % [a.name, b.name],
				"crown": _repeat(a.id, n[0]), "clans": _repeat(b.id, n[1])})
	for budget in [50, 100]:
		out.append({"group": "mixed", "name": "Mixed, %d gold" % budget,
			"crown": mixed(state, CROWN, budget), "clans": mixed(state, CLANS, budget)})
	var kc := state.find_faction(CROWN).commander_type.id
	var wc := state.find_faction(CLANS).commander_type.id
	for budget in [75, 125]:
		out.append({"group": "commander", "name": "Commander + mixed, %d gold" % budget,
			"crown": mixed(state, CROWN, budget, [kc]), "clans": mixed(state, CLANS, budget, [wc])})
	out.append({"group": "commander", "name": "Commanders alone", "crown": [kc], "clans": [wc]})
	out.append({"group": "commander", "name": "Commander + 2 line units",
		"crown": [kc, crown_types[0].id, crown_types[0].id], "clans": [wc, clans_types[0].id, clans_types[0].id]})
	return out


## Fights `seeds` battles of `crown_ids` against `clans_ids` on `g` (a GROUNDS entry), on seeds
## base_seed + 1 .. base_seed + seeds. Returns {"n", "crown_wins", "crown_pct", "rounds" (mean),
## "ends": {end: n}, "top": {factor key: n}, "cited": {factor key: n}, "reports": [first few reports]}.
## Factor keys are "<factor id>|<faction id>". `ruler_fids` lists the factions whose ruler (new_state_with)
## fights beside their army, in its own army as in the game (M2-2).
static func batch(state: GameState, crown_ids: Array, clans_ids: Array, g: Dictionary, seeds: int, base_seed := 0, keep_reports := 0,
		ruler_fids: Array = []) -> Dictionary:
	var crown := army(state, CROWN, crown_ids, "kingdom-1")
	var clans := army(state, CLANS, clans_ids, "beasts-2")
	var province := state.find_province(g.province)
	crown.location = province.id
	clans.location = province.id
	var sides := [{"faction": CLANS, "armies": [clans]}, {"faction": CROWN, "armies": [crown]}]
	for side in sides:
		if ruler_fids.has(side.faction):
			var ra := ruler_army(state, side.faction, side.faction + "-9")
			if ra != null:
				ra.location = province.id
				side.armies.append(ra)
	var ctx := {"kind": "province", "defender": g.defender, "province": province, "province_ids": [province.id], "state": state}
	var out := {"n": seeds, "crown_wins": 0, "crown_pct": 0.0, "rounds": 0.0, "ends": {}, "top": {}, "cited": {}, "reports": []}
	var rounds := 0
	for i in seeds:
		var r: Dictionary = AutoBattleResolver.fight(sides, ctx, SeededRNG.new(base_seed + i + 1)).result
		var rep: Dictionary = r.report
		if r.winner == CROWN:
			out.crown_wins += 1
		rounds += int(rep.rounds_fought)
		out.ends[rep.end] = int(out.ends.get(rep.end, 0)) + 1
		var seen := {}
		for j in rep.factors.size():
			var f: Dictionary = rep.factors[j]
			var key := "%s|%s" % [f.id, f.faction]
			if j == 0:
				out.top[key] = int(out.top.get(key, 0)) + 1
			if not seen.has(key):
				seen[key] = true
				out.cited[key] = int(out.cited.get(key, 0)) + 1
		if out.reports.size() < keep_reports:
			out.reports.append(rep)
	out.crown_pct = 100.0 * out.crown_wins / maxi(1, seeds)
	out.rounds = float(rounds) / maxi(1, seeds)
	return out


## "Spearmen x2, Crossbowmen + Knight Captain" for a list of type ids of `owner`.
static func describe(state: GameState, owner: String, type_ids: Array) -> String:
	var f := state.find_faction(owner)
	var counts := {}
	var order := []
	var cmd := ""
	for type_id in type_ids:
		var ut := TurnResolver.recruitable_type(f, type_id)
		if ut.is_commander:
			cmd = ut.name
			continue
		if not counts.has(ut.name):
			counts[ut.name] = 0
			order.append(ut.name)
		counts[ut.name] += 1
	var parts := []
	for n in order:
		parts.append(n if counts[n] == 1 else "%s x%d" % [n, counts[n]])
	var text := ", ".join(parts)
	if not cmd.is_empty():
		text = cmd if text.is_empty() else "%s + %s" % [text, cmd]
	return text


static func _repeat(type_id: String, n: int) -> Array:
	var out := []
	for i in n:
		out.append(type_id)
	return out
