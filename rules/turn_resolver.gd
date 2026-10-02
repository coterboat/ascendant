class_name TurnResolver
## Deterministic turn resolution. Pure rules code: no nodes, no scenes, no global RNG.
##
##   TurnResolver.resolve(state, orders_by_faction, turn_seed, battle_resolver = null)
##       -> {"new_state": GameState, "events": Array}
##
## `orders_by_faction` maps a faction id (String) to an Array of MoveOrder / RecruitOrder, in the
## order that player gave them. `state` is never modified: resolution works on a deep copy. All
## randomness comes from a SeededRNG built from `turn_seed`, so the same state, orders and seed always
## give the same new state and events. If `state` fails validation, new_state is null and the
## plain-language problems are in result["errors"]. `battle_resolver` defaults to the real battle
## rules, AutoBattleResolver; tests may pass StubBattleResolver for simple, predictable battles.
##
## Phase order (fixed, and shown to players as RulesCodex "phase_order"):
##   orders       every faction's orders are checked; invalid moves are rejected with a reason.
##   movement     all valid moves happen at once. Hostile armies swapping provinces stop on the border.
##   battles      border battles first (sorted by border), then province battles (sorted by province),
##                each decided by the BattleResolver (AutoBattleResolver unless one is passed in).
##   capture      a province occupied by armies of exactly one faction becomes that faction's.
##   recruitment  recruit orders are checked and paid in the order given, at the faction's capital.
##   income       every faction earns the income of the provinces it owns.
##
## Collision rules (player-facing text: RulesCodex "move", "same_province", "swap", "hold",
## "defended", "undefended", and the "battle_*" entries):
##   - Armies that leave a province are gone before anyone arrives: moving into a province the enemy
##     just left is not a battle, and "chasing" never causes a fight.
##   - Swap: faction X moves A->B while faction Y moves B->A. Every army moving along that border (both
##     directions) fights one border battle before arriving; nobody defends. The winner's armies
##     complete their moves; the losers are destroyed. The winner may then still meet other armies
##     in its destination province.
##   - Same province: after movement and border battles, any province holding armies of 2+ factions
##     has one battle with all of them. The defender is the one faction whose army was already there
##     and did not move (held). If no faction held (everyone arrived), there is no defender.
##   - Holding vs arriving / moving into a defended province: a battle; the holder is the defender.
##   - Undefended enemy or neutral province: no battle; the capture phase gives it to the mover.
##   - Losing a battle: every army on a losing side is destroyed, whether that side was wiped out,
##     broke and fled (routed), or was an attacker still standing when the round cap ran out. There
##     are no retreats yet. The battle event text says which of these happened to each loser.
##
## Determinism: factions go in sorted id order, armies in sorted id order, provinces in sorted id
## order and borders in sorted "a|b" key order. Within one faction, orders keep the player's order
## (this only decides which recruits get paid first). Nothing depends on Dictionary insertion order
## or on which faction's orders were supplied first.
##
## Every event is a Dictionary:
##   {"type", "phase", "provinces": [ids], "factions": [ids], "armies": [ids], "cause",
##    "numbers": {...}, "text": plain-language sentence for the turn report, "codex": RulesCodex id}
## Ids stay in the structured fields. `text` and rejection reasons only use player-facing names:
## faction and province display names, and armies as army_label() describes them.

const PHASES := ["orders", "movement", "battles", "capture", "recruitment", "income"]


static func resolve(state: GameState, orders_by_faction: Dictionary, turn_seed: int, battle_resolver: BattleResolver = null) -> Dictionary:
	var load_errors := []
	var s := state.deep_copy(load_errors)
	if s == null:
		return {"new_state": null, "events": [], "errors": load_errors}
	var resolver: BattleResolver = battle_resolver if battle_resolver != null else AutoBattleResolver.new()
	var rng := SeededRNG.new(turn_seed)
	var events: Array = []

	var moves: Array = []  # of {"army_id", "faction", "from", "to"}, one per army
	var recruits := {}  # faction id -> Array of orders, in given order
	_collect_orders(s, orders_by_faction, moves, recruits, events)

	var moved := {}  # army ids that left their province this turn (they are not holding)
	for m in moves:
		moved[m.army_id] = true
	var clashes := _movement(s, moves, events)

	var battle_sites := {}  # province id -> true where a province battle happened
	for clash in clashes:
		_border_battle(s, resolver, rng, clash, events)
	_province_battles(s, resolver, rng, moved, battle_sites, events)
	_capture(s, battle_sites, events)
	_recruitment(s, recruits, events)
	_income(s, events)

	s.current_turn += 1
	return {"new_state": s, "events": events}


## Seed for the current turn, derived from the game seed and turn number, for callers that don't
## pick their own. Pure: the same state always gives the same seed.
static func seed_for_turn(state: GameState) -> int:
	return state.seed_value * 1000003 + state.current_turn


# --- shared rule checks (also used by OrderBook and Forecast) --------------------------------------

## Checks a move order for `faction_id`. Returns {} when valid, otherwise {"code", "reason"} with a
## plain-language reason. `already_ordered` holds army ids that already have a move this turn.
static func check_move(state: GameState, faction_id: String, order: MoveOrder, already_ordered: Dictionary = {}) -> Dictionary:
	var faction := state.find_faction(faction_id)
	if faction == null:
		return _reject("unknown_faction", "Those orders are for a faction that is not in this game.")
	var army := state.find_army(order.army_id)
	if army == null:
		return _reject("unknown_army", "That army no longer exists. It may have been destroyed.")
	if army.owner != faction_id:
		return _reject("not_your_army", "The army at %s belongs to %s, not to %s." % [_province_name(state, army.location), _faction_name(state, army.owner), faction.faction_name])
	var dest := state.find_province(order.to)
	if dest == null:
		return _reject("unknown_province", "That destination is not a province on the map.")
	if dest.id == army.location:
		return _reject("already_there", "The %s is already in %s. To stay put, give it no move order." % [army_label(state, army), dest.name])
	var here := state.find_province(army.location)
	if here == null or not here.neighbors.has(dest.id):
		return _reject("not_adjacent", "%s is not next to %s. Armies move one neighboring province per turn." % [dest.name, _province_name(state, army.location)])
	if already_ordered.has(army.id):
		return _reject("duplicate_move", "The %s already has a move order this turn. Each army moves once per turn." % army_label(state, army))
	return {}


## Checks a recruit order for `faction_id` with `gold_available` left to spend. Returns {} when
## valid, otherwise {"code", "reason"}.
static func check_recruit(state: GameState, faction_id: String, order, gold_available: int) -> Dictionary:
	if not (order is RecruitOrder):
		return _reject("unknown_order", "That is not an order this game knows. Orders are moves and recruits.")
	var faction := state.find_faction(faction_id)
	if faction == null:
		return _reject("unknown_faction", "Those orders are for a faction that is not in this game.")
	var ut := recruitable_type(faction, order.unit_type_id)
	if ut == null:
		for other in state.factions:
			if recruitable_type(other, order.unit_type_id) != null:
				var other_ut := recruitable_type(other, order.unit_type_id)
				return _reject("not_in_roster", "%s belong to %s. %s can only recruit its own units." % [other_ut.name, other.faction_name, faction.faction_name])
		return _reject("unknown_unit_type", "That is not a unit type in this game. Recruit from your faction's roster.")
	var capital := state.find_province(faction.capital)
	if capital == null or capital.owner != faction_id:
		return _reject("capital_not_held", "You don't hold your capital, %s, so you can't recruit. Retake it first." % _province_name(state, faction.capital))
	if ut.cost > gold_available:
		return _reject("not_enough_gold", "%s cost %d gold, but you only have %d gold left." % [ut.name, ut.cost, gold_available])
	return {}


## The unit type `faction` can recruit under this id (its roster or its commander), or null.
static func recruitable_type(faction: Faction, unit_type_id: String) -> UnitType:
	for ut in faction.unit_types:
		if ut.id == unit_type_id:
			return ut
	if faction.commander_type and faction.commander_type.id == unit_type_id:
		return faction.commander_type
	return null


## Gold cost of recruiting `unit_type_id` for `faction_id`, or -1 if they can't recruit that type.
static func recruit_cost(state: GameState, faction_id: String, unit_type_id: String) -> int:
	var faction := state.find_faction(faction_id)
	if faction == null:
		return -1
	var ut := recruitable_type(faction, unit_type_id)
	return ut.cost if ut else -1


## Checks and prices a faction's recruit orders in the order given, spending gold as it goes.
## Used by the recruitment phase and by Forecast, so the forecast always matches the result.
## Returns {"gold_before", "spent", "gold_after", "results": [per order: {"ok", "order", and either
## "unit_type", "cost", "gold_after" or "code", "reason"}]}.
static func price_recruits(state: GameState, faction_id: String, orders: Array) -> Dictionary:
	var faction := state.find_faction(faction_id)
	var gold_before := faction.gold if faction else 0
	var gold := gold_before
	var results := []
	for order in orders:
		var check := check_recruit(state, faction_id, order, gold)
		if check.is_empty():
			var ut := recruitable_type(faction, order.unit_type_id)
			gold -= ut.cost
			results.append({"ok": true, "order": order, "unit_type": ut.id, "cost": ut.cost, "gold_after": gold})
		else:
			results.append({"ok": false, "order": order, "code": check.code, "reason": check.reason})
	return {"gold_before": gold_before, "spent": gold_before - gold, "gold_after": gold, "results": results}


## Income `faction_id` earns from the provinces it owns now: {"total", "by_province": {id: income}}.
static func income_of(state: GameState, faction_id: String) -> Dictionary:
	var total := 0
	var by_province := {}
	for p in _sorted_provinces(state):
		if p.owner == faction_id:
			total += p.income
			by_province[p.id] = p.income
	return {"total": total, "by_province": by_province}


# --- phases ---------------------------------------------------------------------------------------

static func _collect_orders(s: GameState, orders_by_faction: Dictionary, moves: Array, recruits: Dictionary, events: Array) -> void:
	var known := _faction_ids(s)
	var unknown: Array = []
	for key in orders_by_faction.keys():
		if not known.has(str(key)):
			unknown.append(str(key))
	unknown.sort()
	for fid in unknown:
		events.append(_event("order_rejected", "orders", [], [fid], [], "unknown_faction", {},
			"Some orders were ignored: they were given for a faction that is not in this game.", "orders"))

	for fid in known:
		var list = orders_by_faction.get(fid, [])
		if not (list is Array):
			events.append(_event("order_rejected", "orders", [], [fid], [], "not_a_list", {},
				"Orders from %s were ignored: they were not a list of orders." % _faction_name(s, fid), "orders"))
			continue
		var ordered := {}
		recruits[fid] = []
		for order in list:
			if order is MoveOrder:
				var check := check_move(s, fid, order, ordered)
				if not check.is_empty():
					events.append(_rejected_event(s, fid, order, check, "orders"))
					continue
				ordered[order.army_id] = true
				var army := s.find_army(order.army_id)
				# Label taken before anyone moves, so it names the province the army leaves from.
				moves.append({"army_id": army.id, "faction": fid, "from": army.location, "to": order.to,
					"label": army_label(s, army)})
			elif order is RecruitOrder:
				recruits[fid].append(order)  # checked in the recruitment phase, against that phase's state
			else:
				events.append(_rejected_event(s, fid, order,
					_reject("unknown_order", "That is not an order this game knows. Orders are moves and recruits."), "orders"))


## Moves every army that isn't in a border clash. Returns the clashes, sorted by border key.
static func _movement(s: GameState, moves: Array, events: Array) -> Array:
	moves.sort_custom(func(a, b): return a.army_id < b.army_id)
	var by_edge := {}
	for m in moves:
		var key := _edge_key(m.from, m.to)
		if not by_edge.has(key):
			by_edge[key] = []
		by_edge[key].append(m)
	var keys: Array = by_edge.keys()
	keys.sort()

	var clashes := []
	var clashing := {}
	for key in keys:
		var group: Array = by_edge[key]
		if _is_swap(group):
			clashes.append({"edge": key, "movers": group})
			for m in group:
				clashing[m.army_id] = true

	for m in moves:
		if clashing.has(m.army_id):
			continue
		s.find_army(m.army_id).location = m.to
		events.append(_moved_event(s, m, "order"))
	return clashes


static func _is_swap(group: Array) -> bool:
	for a in group:
		for b in group:
			if a.from == b.to and a.to == b.from and a.faction != b.faction:
				return true
	return false


static func _border_battle(s: GameState, resolver: BattleResolver, rng: SeededRNG, clash: Dictionary, events: Array) -> void:
	var sides := {}
	for m in clash.movers:
		if not sides.has(m.faction):
			sides[m.faction] = []
		sides[m.faction].append(s.find_army(m.army_id))
	var ends := Array(clash.edge.split("|"))
	var winner := _fight(s, resolver, rng, "border", ends, sides, "", events)
	for m in clash.movers:
		if m.faction == winner:
			s.find_army(m.army_id).location = m.to
			events.append(_moved_event(s, m, "won_border_battle"))


static func _province_battles(s: GameState, resolver: BattleResolver, rng: SeededRNG, moved: Dictionary, battle_sites: Dictionary, events: Array) -> void:
	for p in _sorted_provinces(s):
		var sides := {}
		var holders := {}
		for a in _sorted_armies(s):
			if a.location != p.id:
				continue
			if not sides.has(a.owner):
				sides[a.owner] = []
			sides[a.owner].append(a)
			if not moved.has(a.id):
				holders[a.owner] = true
		if sides.size() < 2:
			continue
		var defender: String = holders.keys()[0] if holders.size() == 1 else ""
		_fight(s, resolver, rng, "province", [p.id], sides, defender, events)
		battle_sites[p.id] = true


## Runs one battle, destroys the losing armies, records the event. Returns the winner's faction id.
static func _fight(s: GameState, resolver: BattleResolver, rng: SeededRNG, kind: String, province_ids: Array, sides: Dictionary, defender: String, events: Array) -> String:
	var fids: Array = sides.keys()
	fids.sort()
	var side_list := []
	for fid in fids:
		side_list.append({"faction": fid, "armies": sides[fid]})
	# "state" is read-only context for names and terrain (AutoBattleResolver); resolvers must not change it.
	var battle := {"kind": kind, "provinces": province_ids, "defender": defender, "sides": side_list, "state": s}
	var result := resolver.resolve_battle(battle, rng)
	if not fids.has(result.get("winner", "")):
		# A resolver that names no valid winner falls back to the real battle rules.
		result = AutoBattleResolver.new().resolve_battle(battle, rng)
	var winner: String = result.winner

	var destroyed := []
	var units_lost := 0
	var army_ids := []
	var lost_by_faction := {}  # losing faction id -> {"armies", "units"} destroyed with it
	var winner_wiped := 0  # winning armies whose every unit fell
	for fid in fids:
		for a in sides[fid]:
			army_ids.append(a.id)
			if fid != winner:
				destroyed.append(a.id)
				var n: int = a.units.size() + (1 if a.commander else 0)
				units_lost += n
				var lost: Dictionary = lost_by_faction.get(fid, {"armies": 0, "units": 0})
				lost_by_faction[fid] = {"armies": lost.armies + 1, "units": lost.units + n}
			elif a.units.is_empty() and a.commander == null:
				destroyed.append(a.id)  # every unit of this winning army fell in the battle
				winner_wiped += 1
	var survivors: Array[Army] = []
	for a in s.armies:
		if not destroyed.has(a.id):
			survivors.append(a)
	s.armies = survivors

	var strengths: Dictionary = result.get("strengths", {})
	var report: Dictionary = result.get("report", {})
	var parts := []
	for fid in fids:
		if report.is_empty():
			parts.append("%s (strength %d)" % [_faction_name(s, fid), strengths.get(fid, 0)])
		else:
			for sr in report.sides:
				if sr.faction == fid:
					parts.append("%s (%d %s)" % [_faction_name(s, fid), sr.fighters_start, "fighter" if sr.fighters_start == 1 else "fighters"])
	var where: String
	var cause: String
	var codex: String
	if kind == "border":
		where = "On the border between %s and %s, %s met as they swapped places." % [
			_province_name(s, province_ids[0]), _province_name(s, province_ids[1]), " and ".join(parts)]
		cause = "swap"
		codex = "swap"
	elif defender.is_empty():
		where = "In %s, %s arrived at the same time." % [_province_name(s, province_ids[0]), " and ".join(parts)]
		cause = "arrived_together"
		codex = "same_province"
	else:
		var attackers := []
		for fid in fids:
			if fid != defender:
				attackers.append(_faction_name(s, fid))
		where = "In %s, %s held against %s. %s." % [_province_name(s, province_ids[0]), _faction_name(s, defender),
			" and ".join(attackers), ", ".join(parts)]
		cause = "held_vs_arrival"
		codex = "defended"
	var losers := []
	for fid in fids:
		if fid != winner:
			losers.append(_faction_name(s, fid))
	var text := "%s %s won: %s. %s lost %d %s (%d %s)." % [where, _faction_name(s, winner), result.get("why", ""),
		" and ".join(losers), destroyed.size(), "army" if destroyed.size() == 1 else "armies",
		units_lost, "unit" if units_lost == 1 else "units"]
	if not report.is_empty():
		# One line with the result and the "why", then what happened to each loser's armies. The full
		# report rides along in numbers.report (#7) and gets the same aftermath as its last line.
		var aftermath := _aftermath(s, report, winner, fids, lost_by_faction, winner_wiped)
		report["aftermath"] = aftermath
		if report.get("lines") is Array:
			report.lines.append("Aftermath: %s" % aftermath)
		text = "%s %s %s" % [where, report.get("summary", result.get("why", "")), aftermath]

	events.append(_event("border_battle" if kind == "border" else "battle", "battles", province_ids, fids, army_ids, cause,
		{"strengths": strengths, "winner": winner, "defender": defender, "tie_break": result.get("tie_break", "none"),
			"roll": result.get("roll", 0), "armies_destroyed": destroyed.size(), "units_lost": units_lost,
			"destroyed": destroyed, "why": result.get("why", ""), "report": report},
		text, codex))
	return winner


## What happened to each losing side, one sentence each (RulesCodex "battle_rounds"): its armies are
## destroyed whether it was wiped out, routed, or was still standing when the round cap ran out.
## `report` is an AutoBattleResolver report; `lost_by_faction` counts the armies and units removed.
static func _aftermath(s: GameState, report: Dictionary, winner: String, fids: Array, lost_by_faction: Dictionary, winner_wiped: int) -> String:
	var sentences := []
	for fid in fids:
		if fid == winner:
			continue
		var sr := {}
		for side in report.get("sides", []):
			if side.faction == fid:
				sr = side
		var name := _faction_name(s, fid)
		var lost: Dictionary = lost_by_faction.get(fid, {"armies": 0, "units": 0})
		var one: bool = lost.armies == 1
		var armies: String = "its army was" if one else "its %d armies were" % lost.armies
		# "fighters", as in the battle report: units and commanders alike.
		var units := "%d %s lost" % [lost.units, "fighter" if lost.units == 1 else "fighters"]
		if sr.get("destroyed", false):
			sentences.append("Every fighter %s had there fell: %s wiped out (%s)." % [name, armies, units])
		elif sr.get("routed", false):
			sentences.append("%s routed, and %s destroyed as %s fled (%s; there are no retreats yet)." % [
				name, armies, "it" if one else "they", units])
		elif report.get("end", "") == "round_cap" and report.get("defender", "") == winner:
			sentences.append("%s could not break the defenders within %d rounds, and %s destroyed (%s; there are no retreats yet)." % [
				name, report.get("round_cap", AutoBattleResolver.ROUND_CAP), armies, units])
		else:
			sentences.append("%s had less of its strength left when the battle ended, and %s destroyed (%s; there are no retreats yet)." % [
				name, armies, units])
	if winner_wiped > 0:
		sentences.append("%s won, but %s lost every fighter and %s gone too." % [_faction_name(s, winner),
			"one of its armies" if winner_wiped == 1 else "%d of its armies" % winner_wiped, "is" if winner_wiped == 1 else "are"])
	return " ".join(sentences)


static func _capture(s: GameState, battle_sites: Dictionary, events: Array) -> void:
	for p in _sorted_provinces(s):
		var occupants := {}
		var army_ids := []
		for a in _sorted_armies(s):
			if a.location == p.id:
				occupants[a.owner] = true
				army_ids.append(a.id)
		if occupants.size() != 1:
			continue
		var fid: String = occupants.keys()[0]
		if p.owner == fid:
			continue
		var previous: String = p.owner
		p.owner = fid
		var cause: String
		var how: String
		if battle_sites.has(p.id):
			cause = "battle_victory"
			how = "after winning the battle there"
		elif previous.is_empty():
			cause = "undefended_neutral"
			how = "unopposed (it was neutral)"
		else:
			cause = "undefended_enemy"
			how = "unopposed (no %s army was there to defend it)" % _faction_name(s, previous)
		var capital_of := ""
		for f in _sorted_factions(s):
			if f.capital == p.id and f.id != fid:
				capital_of = f.id
		var text := "%s captured %s %s. It now pays %s %d gold per turn." % [_faction_name(s, fid), p.name, how,
			_faction_name(s, fid), p.income]
		if not previous.is_empty():
			text += " %s lost it." % _faction_name(s, previous)
		if not capital_of.is_empty():
			text += " This is the capital of %s: they cannot recruit until they retake it." % _faction_name(s, capital_of)
		var involved := [fid] if previous.is_empty() else [fid, previous]
		events.append(_event("captured", "capture", [p.id], involved, army_ids, cause,
			{"income": p.income, "is_capital": not capital_of.is_empty()}, text, "capture"))


static func _recruitment(s: GameState, recruits: Dictionary, events: Array) -> void:
	for fid in _faction_ids(s):
		var list: Array = recruits.get(fid, [])
		if list.is_empty():
			continue
		var faction := s.find_faction(fid)
		var priced := price_recruits(s, fid, list)
		faction.gold = priced.gold_after
		for r in priced.results:
			if not r.ok:
				events.append(_rejected_event(s, fid, r.order, r, "recruitment"))
				continue
			var ut := recruitable_type(faction, r.unit_type)
			var placed := _add_recruit(s, faction, ut)
			var army: Army = placed.army
			var joined: String
			if placed.created:
				joined = "They form a new army: the %s." % army_label(s, army)
			elif ut.is_commander:
				joined = "They now lead the %s." % army_label(s, army)
			else:
				joined = "They joined the %s." % army_label(s, army)
			events.append(_event("recruited", "recruitment", [faction.capital], [fid], [army.id], "order",
				{"cost": r.cost, "gold_after": r.gold_after, "new_army": placed.created},
				"%s recruited %s at %s for %d gold (%d gold left). %s" % [faction.faction_name, ut.name,
					_province_name(s, faction.capital), r.cost, r.gold_after, joined],
				"recruit"))


## Puts a new unit into the faction's first army (by id) at its capital, or a new army there.
## A commander goes to the first army at the capital without one.
## Returns {"army": the army it joined, "created": true if that army was formed by this recruit}.
static func _add_recruit(s: GameState, faction: Faction, ut: UnitType) -> Dictionary:
	var army: Army = null
	var created := false
	for a in _sorted_armies(s):
		if a.owner == faction.id and a.location == faction.capital and (not ut.is_commander or a.commander == null):
			army = a
			break
	if army == null:
		army = Army.new()
		army.id = s.new_army_id(faction.id)
		army.owner = faction.id
		army.location = faction.capital
		s.armies.append(army)
		created = true
	var unit := Unit.new(ut, faction.id)
	if ut.is_commander:
		army.commander = unit
	else:
		army.units.append(unit)
	return {"army": army, "created": created}


static func _income(s: GameState, events: Array) -> void:
	for fid in _faction_ids(s):
		var faction := s.find_faction(fid)
		var inc := income_of(s, fid)
		var before := faction.gold
		faction.gold += inc.total
		var parts := []
		for pid in inc.by_province:
			parts.append("%s %d" % [_province_name(s, pid), inc.by_province[pid]])
		var count: int = inc.by_province.size()
		var text := "%s earned %d gold from %d %s%s. Gold: %d -> %d." % [faction.faction_name, inc.total, count,
			"province" if count == 1 else "provinces", "" if parts.is_empty() else " (%s)" % ", ".join(parts), before, faction.gold]
		events.append(_event("income", "income", inc.by_province.keys(), [fid], [], "owned_provinces",
			{"income": inc.total, "gold_before": before, "gold_after": faction.gold, "by_province": inc.by_province},
			text, "income"))


# --- helpers --------------------------------------------------------------------------------------

static func _event(type: String, phase: String, provinces: Array, factions: Array, armies: Array, cause: String, numbers: Dictionary, text: String, codex: String) -> Dictionary:
	return {"type": type, "phase": phase, "provinces": provinces, "factions": factions, "armies": armies,
		"cause": cause, "numbers": numbers, "text": text, "codex": codex}


static func _reject(code: String, reason: String) -> Dictionary:
	return {"code": code, "reason": reason}


static func _rejected_event(s: GameState, fid: String, order, check: Dictionary, phase: String) -> Dictionary:
	var provinces := []
	var armies := []
	var desc := "unknown order"
	var order_dict := {}
	if order is MoveOrder:
		var army := s.find_army(order.army_id)
		desc = "move %s to %s" % ["the " + army_label(s, army) if army else "an army that no longer exists",
			_province_name(s, order.to)]
		provinces = [order.to]
		armies = [order.army_id]
		order_dict = order.to_dict()
	elif order is RecruitOrder:
		desc = "recruit %s" % _unit_type_name(s, order.unit_type_id)
		var f := s.find_faction(fid)
		if f:
			provinces = [f.capital]
		order_dict = order.to_dict()
	var ev := _event("order_rejected", phase, provinces, [fid], armies, check.code, {},
		"Order from %s, \"%s\", was rejected: %s" % [_faction_name(s, fid), desc, check.reason],
		"recruit" if order is RecruitOrder else ("move" if order is MoveOrder else "orders"))
	ev["order"] = order_dict
	ev["reason"] = check.reason
	return ev


static func _moved_event(s: GameState, m: Dictionary, cause: String) -> Dictionary:
	var text := "The %s moved to %s." % [m.label, _province_name(s, m.to)]
	if cause == "won_border_battle":
		text = "The %s won the border battle and completed its move to %s." % [m.label, _province_name(s, m.to)]
	return _event("army_moved", "battles" if cause == "won_border_battle" else "movement", [m.from, m.to], [m.faction],
		[m.army_id], cause, {}, text, "move")


## Player-facing name for an army, used in every event text and reason instead of its id:
##   "Aurel Crown army at Crownkeep (3 units, led by Knight Captain)"
##   "Thornmane Clans army at Wildmoor (1 unit, no commander)"
## The unit count excludes the commander. Only when another army of the same faction in the same
## province would get exactly the same label, an ordinal is put in front ("first ...", "second ..."),
## counting those look-alike armies in order of creation (natural sort of their ids), so the label is
## deterministic. Callers add the article: "The %s moved to ...".
static func army_label(s: GameState, army: Army) -> String:
	var detail := _army_detail(army)
	var twins := []
	for a in s.armies:
		if a.owner == army.owner and a.location == army.location and _army_detail(a) == detail:
			twins.append(a.id)
	var label := "%s army at %s (%s)" % [_faction_name(s, army.owner), _province_name(s, army.location), detail]
	if twins.size() > 1:
		twins.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
		label = "%s %s" % [_ordinal(twins.find(army.id) + 1), label]
	return label


static func _army_detail(army: Army) -> String:
	var n := army.units.size()
	var detail := "%d %s" % [n, "unit" if n == 1 else "units"]
	return detail + (", led by %s" % army.commander.type.name if army.commander else ", no commander")


static func _ordinal(n: int) -> String:
	const WORDS := ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]
	if n >= 1 and n <= WORDS.size():
		return WORDS[n - 1]
	return "number %d" % n


static func _edge_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


static func _faction_ids(s: GameState) -> Array:
	var ids := []
	for f in s.factions:
		ids.append(f.id)
	ids.sort()
	return ids


static func _sorted_factions(s: GameState) -> Array:
	var out: Array = s.factions.duplicate()
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


static func _sorted_provinces(s: GameState) -> Array:
	var out: Array = s.provinces.duplicate()
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


static func _sorted_armies(s: GameState) -> Array:
	var out: Array = s.armies.duplicate()
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


static func _faction_name(s: GameState, fid: String) -> String:
	var f := s.find_faction(fid)
	return f.faction_name if f else "an unknown faction"


static func _province_name(s: GameState, pid: String) -> String:
	var p := s.find_province(pid)
	return p.name if p else "a place not on the map"


## Display name of a unit type from any faction's roster, for text about orders that may be invalid.
static func _unit_type_name(s: GameState, type_id: String) -> String:
	for f in s.factions:
		var ut := recruitable_type(f, type_id)
		if ut:
			return ut.name
	return "an unknown unit type"
