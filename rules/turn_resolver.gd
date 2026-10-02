class_name TurnResolver
## Deterministic turn resolution. Pure rules code: no nodes, no scenes, no global RNG.
##
##   TurnResolver.resolve(state, orders_by_faction, turn_seed, battle_resolver = null)
##       -> {"new_state": GameState, "events": Array}
##
## `orders_by_faction` maps a faction id (String) to an Array of MoveOrder / RecruitOrder / SacrificeOrder
## (M2-6), in the order that player gave them. `state` is never modified: resolution works on a deep copy. All
## randomness comes from a SeededRNG built from `turn_seed`, so the same state, orders and seed always
## give the same new state and events. If `state` fails validation, new_state is null and the
## plain-language problems are in result["errors"]. `battle_resolver` defaults to the real battle
## rules, AutoBattleResolver; tests may pass StubBattleResolver for simple, predictable battles.
##
## Phase order (fixed, and shown to players as RulesCodex "phase_order"):
##   sacrifice    (games with rulers, M2-6) each faction's Sacrifice order is checked and applied, in
##                faction id order, before any other order is checked, so its mandate counts this turn.
##   orders       every faction's orders are checked; invalid moves are rejected with a reason.
##   movement     all valid moves happen at once. Hostile armies swapping provinces stop on the border.
##   battles      border battles first (sorted by border), then province battles (sorted by province),
##                each decided by the BattleResolver (AutoBattleResolver unless one is passed in).
##                After each battle, the death of any ruler that fought in it is recorded (M2).
##   capture      a province occupied by armies of exactly one faction becomes that faction's.
##   recruitment  recruit orders are checked and paid in the order given, at the faction's capital.
##   income       every faction earns the income of the provinces it owns.
##   rulers       (games with rulers, M2) Mending Light heals, rulers heal, due successors arrive.
##
## Mandates and abilities on the map (M2-4, design/M2_RULER.md §1.4, §2.3; rules in RulerRules; only
## in a game with rulers, so an M1 game resolves exactly as before):
##   King's Roads    a move with a `via` is a road move: checked in orders, then it moves straight from
##                   A to C. It never takes part in a swap (no border battle) and never stops in B. In C
##                   it is an arriving army like any other (it does not hold).
##   Sworn Vassals   capture: after armies capture, each faction with the mandate gains its best neutral
##                   neighbour (RulerRules.vassal_picks); a province two factions pick goes to nobody.
##   Muster Grounds  every price comes from RulerRules.recruit_price (recruit_cost, price_recruits).
##   Warband Muster  recruitment: a recruit with `at` = "ruler" appears with the Ninth Fang, if the Fang
##                   is on the map and stands in a province its faction owns after capture; otherwise
##                   it is cancelled and costs nothing. At most the ability's value per turn.
##   Heavy Tithes,   income: each owned province earns RulerRules.province_income_parts' total.
##   Royal Court
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

const PHASES := ["sacrifice", "orders", "movement", "battles", "capture", "recruitment", "income", "rulers"]


static func resolve(state: GameState, orders_by_faction: Dictionary, turn_seed: int, battle_resolver: BattleResolver = null) -> Dictionary:
	var load_errors := []
	var s := state.deep_copy(load_errors)
	if s == null:
		return {"new_state": null, "events": [], "errors": load_errors}
	var resolver: BattleResolver = battle_resolver if battle_resolver != null else AutoBattleResolver.new()
	var rng := SeededRNG.new(turn_seed)
	var events: Array = []

	_sacrifice_phase(s, orders_by_faction, events)  # M2-6: first, so every other order sees the new mandates

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
	_rulers_phase(s, events)

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
	if not order.via.is_empty():
		var road := _check_road_move(state, faction, army, here, dest, order.via)
		if not road.is_empty():
			return road
	elif here == null or not here.neighbors.has(dest.id):
		var why := "%s is not next to %s. Armies move one neighboring province per turn." % [dest.name, _province_name(state, army.location)]
		if RulerRules.has_mandate(state, faction_id, RulerRules.KINGS_ROADS):
			why += " King's Roads add a second province only through and into land you already own."
		return _reject("not_adjacent", why)
	if already_ordered.has(army.id):
		return _reject("duplicate_move", "The %s already has a move order this turn. Each army moves once per turn." % army_label(state, army))
	return {}


## King's Roads (§2.3): a road move from A (the army's province) through B (`via`) to C (`dest`) is
## legal when the faction has King's Roads, B is next to A, C is next to B, C is not A, and the faction
## owns both B and C in `state` (the start of the turn). {} when legal, otherwise {"code", "reason"}.
static func _check_road_move(state: GameState, faction: Faction, army: Army, here: Province, dest: Province, via_id: String) -> Dictionary:
	var label := army_label(state, army)
	if not RulerRules.has_mandate(state, faction.id, RulerRules.KINGS_ROADS):
		return _reject("no_kings_roads", "Only a faction with King's Roads can move an army two provinces in one turn, so the %s can't go through %s to %s. Armies move one neighboring province per turn." % [
			label, _province_name(state, via_id), dest.name])
	var via := state.find_province(via_id)
	if via == null:
		return _reject("unknown_via", "That road move goes through a place that is not on the map.")
	if here == null or via.id == here.id or not here.neighbors.has(via.id):
		return _reject("via_not_adjacent", "%s is not next to %s, so a road move can't go through it." % [via.name, _province_name(state, army.location)])
	if not via.neighbors.has(dest.id):
		return _reject("road_not_adjacent", "%s is not next to %s, so a road move through %s can't reach it." % [dest.name, via.name, via.name])
	if via.owner != faction.id:
		return _reject("road_not_owned", "King's Roads run only through your own land, and %s is not yours. A road move goes through a province you owned at the start of the turn." % via.name)
	if dest.owner != faction.id:
		return _reject("road_not_owned", "King's Roads run only through your own land, and %s is not yours. Move one province at a time to take it." % dest.name)
	return {}


## Checks a recruit order for `faction_id` with `gold_available` left to spend. Returns {} when
## valid, otherwise {"code", "reason"}. `with_ruler_before` counts the recruits with the ruler already
## paid for this turn (Warband Muster's limit); price_recruits passes it.
static func check_recruit(state: GameState, faction_id: String, order, gold_available: int, with_ruler_before: int = 0) -> Dictionary:
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
	if order.at == RecruitOrder.AT_RULER:
		var field := _check_recruit_with_ruler(state, faction, ut, with_ruler_before)
		if not field.is_empty():
			return field
	elif not order.at.is_empty():
		return _reject("unknown_place", "Recruits are made at your capital, or with your ruler where it stands if it has Warband Muster.")
	else:
		var capital := state.find_province(faction.capital)
		if capital == null or capital.owner != faction_id:
			return _reject("capital_not_held", "You don't hold your capital, %s, so you can't recruit. Retake it first." % _province_name(state, faction.capital))
	var price := RulerRules.recruit_price(state, faction_id, ut)
	if price > gold_available:
		return _reject("not_enough_gold", "%s cost %d gold, but you only have %d gold left." % [ut.name, price, gold_available])
	return {}


## Warband Muster (§1.4): a recruit "with the ruler" needs a ruler with the ability, on the map, standing
## in a province its faction owns (checked against `state`: the start of the turn when ordering, after
## capture when resolving), a regular unit (commanders come only from the capital), and room under the
## per-turn limit. The reasons say the recruit costs nothing, because a recruit that fails here at the
## end of the turn is cancelled before anything is paid.
static func _check_recruit_with_ruler(state: GameState, faction: Faction, ut: UnitType, with_ruler_before: int) -> Dictionary:
	var fid := faction.id
	var ability := RulerRules.ability_name(_first_ruler_with(RulerRules.WARBAND_MUSTER))
	if not RulerRules.ruler_has_ability(state, fid, RulerRules.WARBAND_MUSTER):
		if not faction.has_ruler():
			return _reject("no_field_recruits", "Only a ruler with %s can recruit in the field. In this game %s recruits only at its capital." % [ability, faction.faction_name])
		return _reject("no_field_recruits", "Only a ruler with %s can recruit in the field, and %s does not have it. Recruit at your capital instead." % [
			ability, RulerRules.current_name(state, fid)])
	var name := RulerRules._cap(RulerRules.current_name(state, fid))
	var army := RulerRules.ruler_army(state, fid)
	if army == null or faction.ruler_status != RulerRules.ALIVE:
		return _reject("ruler_not_on_map", "%s is not on the map (it has fallen), so nobody can recruit with it; no gold is spent." % name)
	if ut.is_commander:
		var names := []
		for u in faction.unit_types:
			names.append(u.name)
		return _reject("commander_with_ruler", "Commanders come only from your capital. With %s you can recruit regular units: %s." % [
			RulerRules.current_name(state, fid), RulerRules._and_list(names)])
	var limit := RulerRules.field_recruit_limit(state, fid)
	if with_ruler_before >= limit:
		return _reject("ruler_recruit_limit", "%s can recruit %d %s per turn (%s at ability rank %d), and %s already ordered." % [
			name, limit, "unit" if limit == 1 else "units", ability, RulerRules.ability_rank(faction.kept_power),
			"that one is" if with_ruler_before == 1 else "%d are" % with_ruler_before])
	var where := state.find_province(army.location)
	if where == null or where.owner != fid:
		return _reject("ruler_province_not_held", "%s is at %s, which is not yours, so nobody can recruit with it there; no gold is spent." % [
			name, _province_name(state, army.location)])
	return {}


## The first ruler id (in data order) whose ability is `ability_id`, for naming the ability.
static func _first_ruler_with(ability_id: String) -> String:
	for r in RulerData.RULERS:
		if String(r.get("ability", "")) == ability_id:
			return r.id
	return ""


## The unit type `faction` can recruit under this id (its roster or its commander), or null.
static func recruitable_type(faction: Faction, unit_type_id: String) -> UnitType:
	for ut in faction.unit_types:
		if ut.id == unit_type_id:
			return ut
	if faction.commander_type and faction.commander_type.id == unit_type_id:
		return faction.commander_type
	return null


## Gold cost of recruiting `unit_type_id` for `faction_id`, or -1 if they can't recruit that type.
## The price with the faction's mandates (Muster Grounds): RulerRules.recruit_price, the one price
## every screen, forecast and the recruitment phase use.
static func recruit_cost(state: GameState, faction_id: String, unit_type_id: String) -> int:
	var faction := state.find_faction(faction_id)
	if faction == null:
		return -1
	var ut := recruitable_type(faction, unit_type_id)
	return RulerRules.recruit_price(state, faction_id, ut) if ut else -1


## Checks and prices a faction's recruit orders in the order given, spending gold as it goes.
## Used by the recruitment phase and by Forecast, so the forecast always matches the result.
## Recruits at the capital and with the ruler (Warband Muster) share one gold pool and are paid in
## the order given; a recruit that fails a check costs nothing.
## Returns {"gold_before", "spent", "gold_after", "results": [per order: {"ok", "order", "at", and
## either "unit_type", "cost", "gold_after", "province" (where it appears) or "code", "reason"}]}.
static func price_recruits(state: GameState, faction_id: String, orders: Array) -> Dictionary:
	var faction := state.find_faction(faction_id)
	var gold_before := faction.gold if faction else 0
	var gold := gold_before
	var with_ruler := 0
	var results := []
	for order in orders:
		var check := check_recruit(state, faction_id, order, gold, with_ruler)
		var at: String = order.at if order is RecruitOrder else ""
		if check.is_empty():
			var ut := recruitable_type(faction, order.unit_type_id)
			var price := RulerRules.recruit_price(state, faction_id, ut)
			gold -= price
			var province := faction.capital
			if at == RecruitOrder.AT_RULER:
				with_ruler += 1
				province = RulerRules.ruler_army(state, faction_id).location
			results.append({"ok": true, "order": order, "at": at, "unit_type": ut.id, "cost": price, "gold_after": gold,
				"province": province})
		else:
			results.append({"ok": false, "order": order, "at": at, "code": check.code, "reason": check.reason})
	return {"gold_before": gold_before, "spent": gold_before - gold, "gold_after": gold, "results": results}


## Income `faction_id` earns from the provinces it owns now: {"total", "by_province": {id: income},
## "base", "modifiers": {"heavy_tithes": gold, "royal_court": gold}, "court_at": province id or ""}.
## Each province's income is RulerRules.province_income_parts' total: its base income plus Heavy
## Tithes and Royal Court (M2). `ruler_at` ({faction id: province id}) moves a ruler for a forecast.
static func income_of(state: GameState, faction_id: String, ruler_at: Dictionary = {}) -> Dictionary:
	var total := 0
	var base := 0
	var by_province := {}
	var modifiers := {}
	var court_at := ""
	for p in _sorted_provinces(state):
		if p.owner == faction_id:
			var parts := RulerRules.province_income_parts(state, p.id, ruler_at)
			total += int(parts.total)
			base += int(parts.base)
			by_province[p.id] = int(parts.total)
			for m in parts.mods:
				modifiers[m.key] = int(modifiers.get(m.key, 0)) + int(m.value)
				if m.key == RulerRules.ROYAL_COURT:
					court_at = p.id
	return {"total": total, "by_province": by_province, "base": base, "modifiers": modifiers, "court_at": court_at}


# --- phases ---------------------------------------------------------------------------------------

## The sacrifice phase, first in the turn (M2-6, #34; design/M2_RULER.md §2.4, §3): each faction's
## Sacrifice order is checked (RulerRules.sacrifice_check) and applied (RulerRules.apply_sacrifice), in
## faction id order, before any other order is checked, so the new mandate already counts in this
## turn's moves, battles, recruits and income. One per faction per turn: a second is rejected. Events:
##   sacrificed      sacrifice   the ruler gave up power for a mandate. Codex "sacrifice".
##   order_rejected  sacrifice   an illegal Sacrifice order, with the reason. Codex "sacrifice".
## In a game without Sacrifice orders nothing happens and no event is added.
static func _sacrifice_phase(s: GameState, orders_by_faction: Dictionary, events: Array) -> void:
	var turn := s.current_turn + 1  # the turn being resolved, as players count it
	for fid in _faction_ids(s):
		var list = orders_by_faction.get(fid, [])
		if not (list is Array):
			continue  # the orders phase reports it
		var done := ""  # the mandate this faction already sacrificed for this turn
		for order in list:
			if not (order is SacrificeOrder):
				continue
			var result := RulerRules.apply_sacrifice(s, fid, order.mandate_id, turn, done)
			if not result.ok:
				events.append(_rejected_event(s, fid, order, result, "sacrifice"))
				continue
			done = order.mandate_id
			var numbers := result.duplicate()
			numbers.erase("ok")
			events.append(_event("sacrificed", "sacrifice", [result.province], [fid], [result.army], "sacrifice", numbers,
				RulerRules.sacrifice_text(s, fid, result), "sacrifice"))


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
				# "via" is set for a road move (King's Roads), "" for a one-step move.
				moves.append({"army_id": army.id, "faction": fid, "from": army.location, "to": order.to,
					"label": army_label(s, army), "via": order.via})
			elif order is RecruitOrder:
				recruits[fid].append(order)  # checked in the recruitment phase, against that phase's state
			elif order is SacrificeOrder:
				continue  # resolved in the sacrifice phase, before these checks (M2-6)
			else:
				events.append(_rejected_event(s, fid, order,
					_reject("unknown_order", "That is not an order this game knows. Orders are moves and recruits."), "orders"))


## Moves every army that isn't in a border clash. Returns the clashes, sorted by border key.
## Road moves (King's Roads) never take part in a swap: only one-step moves meet on a border, so a road
## move always goes straight from A to C.
static func _movement(s: GameState, moves: Array, events: Array) -> Array:
	moves.sort_custom(func(a, b): return a.army_id < b.army_id)
	var by_edge := {}
	for m in moves:
		if not String(m.get("via", "")).is_empty():
			continue
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
		# Never null: an army has one move, so it is in exactly one clash, and earlier battles only
		# removed their own armies.
		sides[m.faction].append(s.find_army(m.army_id))
	var ends := Array(clash.edge.split("|"))
	var winner := _fight(s, resolver, rng, "border", ends, sides, "", events)
	for m in clash.movers:
		if m.faction == winner:
			var army := s.find_army(m.army_id)
			if army == null:
				continue  # on the winning side, but every fighter in it fell: it is gone, not moving
			army.location = m.to
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


## Runs one battle, destroys the losing armies, records the event and any ruler deaths (M2). Returns
## the winner's faction id.
static func _fight(s: GameState, resolver: BattleResolver, rng: SeededRNG, kind: String, province_ids: Array, sides: Dictionary, defender: String, events: Array) -> String:
	var fids: Array = sides.keys()
	fids.sort()
	var rulers_in := _rulers_in_battle(sides)  # M2: whose rulers fight here, to record deaths after
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
			elif a.units.is_empty() and a.commander == null and a.ruler == null:
				destroyed.append(a.id)  # every unit of this winning army fell (a ruler's army holds only its ruler)
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
	_record_ruler_deaths(s, rulers_in, winner, kind, province_ids, events)
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


# --- ruler deaths and the rulers phase (M2-3, #31; design/M2_RULER.md §3, §5, §1.4, §1.7) ----------
# Games with rulers only (GameState.with_rulers): in an M1 game no army holds a ruler, so none of this
# adds an event. The rules and sentences are RulerRules'; these functions make the events:
#   ruler_died          battles   a ruler fell while its side won, or was lost with its side. Codex "ruler_death".
#   mending             rulers    Mending Light healed wounded units and commanders. Codex "ability_mending_light".
#   ruler_healed        rulers    a living ruler healed a quarter of its maximum hp. Codex "ruler_healing".
#   ruler_arrived       rulers    a successor took over at the capital. Codex: the kind's "succession_*".
#   succession_waiting  rulers    a successor is due but the faction doesn't hold its capital. Codex "succession".
# Death is read from the state after the battle, never from the battle report: a ruler is dead when
# its army is gone or no longer holds it, so any battle resolver works.

## The rulers fighting in one battle, before it is fought: [{"faction", "army"}], in faction id order.
static func _rulers_in_battle(sides: Dictionary) -> Array:
	var out := []
	var fids: Array = sides.keys()
	fids.sort()
	for fid in fids:
		for a in sides[fid]:
			if a != null and a.ruler != null:
				out.append({"faction": fid, "army": a.id})
	return out


## After a battle (§5.1): every ruler that fought in it and whose army is gone, or no longer holds it,
## is dead. Records the death (its successor falls due) and adds a ruler_died event in phase "battles".
static func _record_ruler_deaths(s: GameState, rulers_in: Array, winner: String, kind: String, province_ids: Array, events: Array) -> void:
	for r in rulers_in:
		var army := s.find_army(r.army)
		if army != null and army.ruler != null:
			continue  # it still stands
		if army != null and army.units.is_empty() and army.commander == null:
			s.armies.erase(army)  # the ruler's army goes with its ruler (§5.1)
		var info := RulerRules.record_death(s, r.faction, s.current_turn + 1)
		if info.is_empty():
			continue
		var fell: bool = r.faction == winner  # it fell although its side won; otherwise it was lost with its side
		var place: String
		if kind == "border":
			place = "on the border between %s and %s" % [_province_name(s, province_ids[0]), _province_name(s, province_ids[1])]
		else:
			place = "at %s" % _province_name(s, province_ids[0])
		var numbers := info.duplicate()
		numbers["succession_codex"] = numbers.codex  # the event links "ruler_death"; this is the kind's entry
		numbers.erase("codex")
		numbers["won"] = fell
		numbers["winner"] = winner
		numbers["army"] = r.army
		events.append(_event("ruler_died", "battles", province_ids.duplicate(), [r.faction], [r.army],
			"fell_while_winning" if fell else "lost_with_side", numbers,
			RulerRules.death_text(s, r.faction, info, fell, place), "ruler_death"))


## The rulers phase, last in the turn (§3 step 8): Mending Light heals, then every living ruler heals
## a quarter of its maximum hp, then every successor that is due arrives at its capital, or waits for
## it. Each step goes through the factions in id order. No events in a game without rulers.
static func _rulers_phase(s: GameState, events: Array) -> void:
	if not RulerRules.has_rulers(s):
		return
	var turn := s.current_turn + 1  # the turn being resolved, as players count it
	var fids := _faction_ids(s)
	for fid in fids:
		var mend := RulerRules.apply_mending_light(s, fid)
		if mend.healed.is_empty():
			continue
		var armies := []
		for h in mend.healed:
			if not armies.has(h.army):
				armies.append(h.army)
		events.append(_event("mending", "rulers", [mend.province], [fid], armies, "mending_light",
			{"rank": mend.rank, "amount": mend.amount, "total": mend.total, "healed": mend.healed.duplicate(true)},
			RulerRules.mending_text(s, fid, mend, _province_name(s, mend.province)), "ability_mending_light"))
	for fid in fids:
		var heal := RulerRules.heal_ruler(s, fid)
		if int(heal.healed) <= 0:
			continue
		events.append(_event("ruler_healed", "rulers", [heal.province], [fid], [heal.army], "ruler_healing",
			{"healed": heal.healed, "hp_before": heal.hp_before, "hp_after": heal.hp_after, "max_hp": heal.max_hp,
				"share": heal.share},
			RulerRules.healed_text(heal, _province_name(s, heal.province)), "ruler_healing"))
	for fid in fids:
		if not RulerRules.successor_due(s, fid, turn):
			continue
		var info := RulerRules.succession_info(s, fid)
		var army := RulerRules.crown_successor(s, fid, turn)
		if army == null:
			events.append(_event("succession_waiting", "rulers", [info.capital], [fid], [], "capital_not_held",
				{"successor_turn": info.successor_turn, "successor_power": info.successor_power,
					"successor_generation": info.successor_generation},
				RulerRules.waiting_text(s, fid), "succession"))
			continue
		var f := s.find_faction(fid)
		var stats := RulerRules.ruler_stats(f.ruler_type, f.kept_power, f.ruler_generation)
		events.append(_event("ruler_arrived", "rulers", [army.location], [fid], [army.id], "succession",
			{"ruler": f.ruler_type, "kind": info.kind, "name": stats.name, "generation": f.ruler_generation,
				"kept_power": f.kept_power, "kept_power_before": info.kept_power, "hp": army.ruler.current_hp,
				"max_hp": stats.hp, "attack": stats.attack, "defense": stats.defense, "ability_rank": stats.ability_rank,
				"due_turn": info.successor_turn},
			RulerRules.arrival_text(s, fid, int(info.kept_power), turn + 1), String(info.codex)))


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
	_sworn_vassals(s, events)


## Sworn Vassals (§2.3), after the army captures: each faction with the mandate gains its best neutral
## neighbour (RulerRules.vassal_picks on the board as it now stands). A province two factions pick
## joins nobody. No gold changes hands.
static func _sworn_vassals(s: GameState, events: Array) -> void:
	var board := RulerRules.board_now(s)
	var picks := RulerRules.vassal_picks(s, board.owners, board.occupied)
	var joining: Array = picks.joins.keys()
	joining.sort()
	for fid in joining:
		var p := s.find_province(picks.joins[fid])
		p.owner = fid
		var name := _faction_name(s, fid)
		events.append(_event("vassal_joined", "capture", [p.id], [fid], [], "sworn_vassals", {"income": p.income},
			"%s swore fealty to %s (Sworn Vassals) and joined it without a fight. It now pays %s %d gold per turn." % [
				p.name, name, name, p.income], "mandate_sworn_vassals"))
	var contested: Array = picks.contested.keys()
	contested.sort()
	for pid in contested:
		var fids: Array = picks.contested[pid]
		var names := []
		for fid in fids:
			names.append(_faction_name(s, fid))
		events.append(_event("vassal_contested", "capture", [pid], fids, [], "sworn_vassals_contested",
			{"income": s.find_province(pid).income},
			"%s was sought by both %s through Sworn Vassals, so it joined nobody this turn. Neither picks another province this turn." % [
				_province_name(s, pid), " and ".join(names)], "mandate_sworn_vassals"))


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
			var with_ruler: bool = r.at == RecruitOrder.AT_RULER
			var placed := _add_recruit(s, faction, ut, r.province)
			var army: Army = placed.army
			var joined: String
			if placed.created:
				joined = "They form a new army: the %s." % army_label(s, army)
			elif ut.is_commander:
				joined = "They now lead the %s." % army_label(s, army)
			else:
				joined = "They joined the %s." % army_label(s, army)
			var how := "at %s" % _province_name(s, r.province)
			if with_ruler:
				# Warband Muster (§7.5): still a "recruited" event, saying with whom and where.
				how = "with %s at %s" % [RulerRules.current_name(s, fid), _province_name(s, r.province)]
			events.append(_event("recruited", "recruitment", [r.province], [fid], [army.id], "with_ruler" if with_ruler else "order",
				{"cost": r.cost, "gold_after": r.gold_after, "new_army": placed.created},
				"%s recruited %s %s for %d gold (%d gold left). %s" % [faction.faction_name, ut.name, how, r.cost,
					r.gold_after, joined],
				"field_recruit" if with_ruler else "recruit"))


## Puts a new unit into the faction's first army (by id) at `location` (its capital by default), or a
## new army there. A commander goes to the first army there without one. Recruits never join a ruler's
## army: a ruler travels alone (RulesCodex "ruler_army").
## Returns {"army": the army it joined, "created": true if that army was formed by this recruit}.
static func _add_recruit(s: GameState, faction: Faction, ut: UnitType, location: String = "") -> Dictionary:
	var where := faction.capital if location.is_empty() else location
	var army: Army = null
	var created := false
	for a in _sorted_armies(s):
		if a.owner == faction.id and a.location == where and a.ruler == null and (not ut.is_commander or a.commander == null):
			army = a
			break
	if army == null:
		army = Army.new()
		army.id = s.new_army_id(faction.id)
		army.owner = faction.id
		army.location = where
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
		var numbers := {"income": inc.total, "gold_before": before, "gold_after": faction.gold, "by_province": inc.by_province}
		if not inc.modifiers.is_empty():
			# M2: say what Heavy Tithes and Royal Court added (an M1 game has no modifiers, so its text is unchanged).
			text += " %s" % income_modifiers_text(s, fid, inc, "was")
			numbers["base"] = inc.base
			numbers["modifiers"] = inc.modifiers
		events.append(_event("income", "income", inc.by_province.keys(), [fid], [], "owned_provinces", numbers, text, "income"))


## "That includes Heavy Tithes +5 (1 for each province) and Royal Court +2 at Crownkeep, where King
## Corvane I was." for an income_of result with modifiers ("" without). `ruler_verb` fits the tense:
## "was" in the turn report, "ends the turn" in a forecast.
static func income_modifiers_text(s: GameState, fid: String, inc: Dictionary, ruler_verb: String = "is") -> String:
	var parts := []
	var tithes := int(inc.modifiers.get(RulerRules.HEAVY_TITHES, 0))
	if tithes > 0:
		parts.append("Heavy Tithes +%d (%d for each province)" % [tithes, RulerRules.TITHE_GOLD])
	var court := int(inc.modifiers.get(RulerRules.ROYAL_COURT, 0))
	if court > 0:
		var f := s.find_faction(fid)
		parts.append("%s +%d at %s, where %s %s" % [RulerRules.ability_name(f.ruler_type), court,
			_province_name(s, inc.court_at), RulerRules.current_name(s, fid), ruler_verb])
	if parts.is_empty():
		return ""
	return "That includes %s." % " and ".join(parts)


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
	var codex := "orders"
	if order is MoveOrder:
		var army := s.find_army(order.army_id)
		desc = "move %s to %s" % ["the " + army_label(s, army) if army else "an army that no longer exists",
			_province_name(s, order.to)]
		provinces = [order.to]
		armies = [order.army_id]
		order_dict = order.to_dict()
		codex = "move"
		if not order.via.is_empty():
			desc += " through %s" % _province_name(s, order.via)
			codex = "road_move"
	elif order is RecruitOrder:
		desc = "recruit %s" % _unit_type_name(s, order.unit_type_id)
		var f := s.find_faction(fid)
		if f:
			provinces = [f.capital]
		order_dict = order.to_dict()
		codex = "recruit"
		if order.at == RecruitOrder.AT_RULER:
			# Warband Muster: name the ruler and put the event where it stands, if it is on the map.
			codex = "field_recruit"
			var ruler := RulerRules.ruler_army(s, fid)
			var who := RulerRules.current_name(s, fid)
			desc += " with %s" % (who if not who.is_empty() else "the ruler")
			if ruler:
				provinces = [ruler.location]
	elif order is SacrificeOrder:
		# M2-6: name the mandate (or quote an unknown id) and put the event where the ruler stands.
		var mandate := RulerRules.mandate_name(order.mandate_id) if not RulerRules.mandate_data(order.mandate_id).is_empty() \
			else "'%s'" % order.mandate_id
		desc = "sacrifice power for %s" % mandate
		order_dict = order.to_dict()
		codex = "sacrifice"
		var ruler_army := RulerRules.ruler_army(s, fid)
		var owner := s.find_faction(fid)
		if ruler_army:
			provinces = [ruler_army.location]
		elif owner:
			provinces = [owner.capital]
	var ev := _event("order_rejected", phase, provinces, [fid], armies, check.code, {},
		"Order from %s, \"%s\", was rejected: %s" % [_faction_name(s, fid), desc, check.reason], codex)
	ev["order"] = order_dict
	ev["reason"] = check.reason
	return ev


static func _moved_event(s: GameState, m: Dictionary, cause: String) -> Dictionary:
	var via := String(m.get("via", ""))
	if not via.is_empty():
		# A road move (King's Roads, §7.5): still an "army_moved" event, saying which way it went.
		return _event("army_moved", "movement", [m.from, via, m.to], [m.faction], [m.army_id], "road_move", {"via": via},
			"The %s moved to %s by the King's Roads through %s." % [m.label, _province_name(s, m.to), _province_name(s, via)],
			"road_move")
	var text := "The %s moved to %s." % [m.label, _province_name(s, m.to)]
	if cause == "won_border_battle":
		text = "The %s won the border battle and completed its move to %s." % [m.label, _province_name(s, m.to)]
	return _event("army_moved", "battles" if cause == "won_border_battle" else "movement", [m.from, m.to], [m.faction],
		[m.army_id], cause, {}, text, "move")


## Player-facing name for an army, used in every event text and reason instead of its id:
##   "Aurel Crown army at Crownkeep (3 units, led by Knight Captain)"
##   "Thornmane Clans army at Wildmoor (1 unit, no commander)"
##   "Aurel Crown ruler King Corvane I at Crownkeep"   (a ruler's army: it holds only the ruler, M2)
## The unit count excludes the commander. Only when another army of the same faction in the same
## province would get exactly the same label, an ordinal is put in front ("first ...", "second ..."),
## counting those look-alike armies in order of creation (natural sort of their ids), so the label is
## deterministic. Callers add the article: "The %s moved to ...".
static func army_label(s: GameState, army: Army) -> String:
	if army.ruler != null:
		# A faction has at most one ruler, so this label is never shared (RulesCodex "ruler_army").
		return "%s ruler %s at %s" % [_faction_name(s, army.owner), army.ruler.type.name, _province_name(s, army.location)]
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
	if army.ruler != null:
		return "ruler %s" % army.ruler.type.name
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
