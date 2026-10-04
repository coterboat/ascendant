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
##   research     (games with paths, M4) each faction gains research and completes its target once it
##                is paid for (AscensionRules; _research_phase). Research orders set the target in orders.
##   rulers       (games with rulers, M2) Mending Light heals, rulers heal, due successors arrive.
##
## Forts and sieges (M3c, design/M3C_SIEGES.md §6; rules in SiegeRules; only in a game with sieges, so every
## other game resolves exactly as before; phases(state) gives a game's list):
##   orders       Fortify orders are checked (and paid in recruitment); storm and sally orders are checked and
##                recorded after every move order of their faction, against all of its valid moves.
##   battles      at a fort, SiegeRules.next_battle decides each battle: an army that marches into an enemy fort
##                with standing walls and a garrison inside besieges it instead of fighting (§3.2).
##   sieges       (new, between battles and capture) each fort in id order: a siege starts, the walls take
##                siege damage and may be breached; a siege is lifted, or the fort falls; walls repair where no
##                army of another faction stands; construction works where no enemy stands, and a level is done.
##   capture      an empty fort is captured with its level and walls; construction there is razed; owned_since
##                and the retake rule (§2.3), for Sworn Vassals too.
##   recruitment  Fortify orders are paid and their sites started; recruits arrive at the fort they name (`at`),
##                within its limit; siege engines join the first army there with a fighter.
##   income       a cut-off province pays its base income to the besiegers and nothing to its owner.
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
## faction and province display names, and armies as army_label() describes them. `text` is the record's
## sentence and stays exactly as it is (the recorded games' digests hold it, tests/fixtures/main_records.json);
## the turn report writes its own lines from these fields when it is shown (TurnReportText, #55): armies by
## their names for life, battles by the units that fought, and the result of every rejected order.

const PHASES := ["sacrifice", "orders", "movement", "battles", "capture", "recruitment", "income", "rulers"]
## The phases of a game with paths (M4, design/M4_ASCENSION.md §7): PHASES with "research" after income.
## PHASES itself stays the M1/M2 list, which a game without paths resolves exactly as before.
const PATH_PHASES := ["sacrifice", "orders", "movement", "battles", "capture", "recruitment", "income", "research", "rulers"]
## The phase a game with sieges adds after "battles" (M3c, §6). PHASES and PATH_PHASES stay as they are.
const SIEGES_PHASE := "sieges"


## The phases of `state`'s game, in order: PHASES, or PATH_PHASES with paths, and "sieges" after "battles"
## when sieges are on (M3c, §6).
static func phases(state: GameState) -> Array:
	var out: Array = (PATH_PHASES if state != null and state.paths else PHASES).duplicate()
	if state != null and state.sieges:
		out.insert(out.find("battles") + 1, SIEGES_PHASE)
	return out


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
	var recruits := {}  # faction id -> Array of orders, in given order (recruits and, M3c, Fortify orders)
	var siege_orders := {"storms": {}, "sallies": {}}  # M3c: the storms and sallies that passed their checks
	_collect_orders(s, orders_by_faction, moves, recruits, events, siege_orders)

	var moved := {}  # army ids that left their province this turn (they are not holding)
	for m in moves:
		moved[m.army_id] = true
	var clashes := _movement(s, moves, events)

	var battle_sites := {}  # province id -> true where a province battle happened
	for clash in clashes:
		_border_battle(s, resolver, rng, clash, events)
	_province_battles(s, resolver, rng, moved, battle_sites, events, siege_orders)
	_sieges_phase(s, battle_sites, events)  # M3c: games with sieges only
	_capture(s, battle_sites, events)
	_recruitment(s, recruits, events, state)  # Warband Muster gathers where the ruler started the turn
	_income(s, events)
	_research_phase(s, events)  # M4: games with paths only
	_rulers_phase(s, events)

	s.current_turn += 1
	return {"new_state": s, "events": events}


## Seed for the current turn, derived from the game seed and turn number, for callers that don't
## pick their own. Pure: the same state always gives the same seed.
static func seed_for_turn(state: GameState) -> int:
	return state.seed_value * 1000003 + state.current_turn


# --- shared rule checks (also used by OrderBook and Forecast) --------------------------------------

## Checks a move order for `faction_id`. Returns {} when valid, otherwise {"code", "reason"} with a
## plain-language reason. `already_ordered` holds army ids that already have a move this turn. The reasons
## name armies as the map and the turn report do (TurnReportText.army_name: "the Crown's 3rd").
static func check_move(state: GameState, faction_id: String, order: MoveOrder, already_ordered: Dictionary = {}) -> Dictionary:
	var faction := state.find_faction(faction_id)
	if faction == null:
		return _reject("unknown_faction", "Those orders are for a faction that is not in this game.")
	var army := state.find_army(order.army_id)
	if army == null:
		return _reject("unknown_army", "There is no such army on the map. It may have been destroyed, or the order names an army this game never had.")
	if army.owner != faction_id:
		return _reject("not_your_army", "%s at %s belongs to %s, not to %s." % [_army_name(state, army, true), _province_name(state, army.location),
			_faction_name(state, army.owner), faction.faction_name])
	var dest := state.find_province(order.to)
	if dest == null:
		return _reject("unknown_province", "That destination is not a province on the map.")
	if dest.id == army.location:
		return _reject("already_there", "%s is already in %s. To stay put, give it no move order." % [_army_name(state, army, true), dest.name])
	var here := state.find_province(army.location)
	if not order.via.is_empty():
		var road := _check_road_move(state, faction, army, here, dest, order.via)
		if not road.is_empty():
			return road
	elif here == null or not here.neighbors.has(dest.id):
		var why := "%s is not next to %s. Armies move one neighboring province per turn." % [dest.name, _province_name(state, army.location)]
		if RulerRules.has_mandate(state, faction_id, RulerRules.KINGS_ROADS):
			why += " King's Roads add a second province only through and into land you already own."
		if AscensionRules.has_forest_stride(state, faction_id):  # M4-2
			why += " Forest Stride adds a second province only through a forest you own into another forest."
		return _reject("not_adjacent", why)
	if already_ordered.has(army.id):
		return _reject("duplicate_move", "%s already has a move order this turn. Each army moves once per turn." % _army_name(state, army, true))
	return {}


## King's Roads (§2.3): a road move from A (the army's province) through B (`via`) to C (`dest`) is
## legal when the faction has King's Roads, B is next to A, C is next to B, C is not A, and the faction
## owns both B and C in `state` (the start of the turn). {} when legal, otherwise {"code", "reason"}.
## M4-2, Forest Stride (§4.8): the same move is also legal when the faction has Forest Stride, B and C are
## both forest and B is a province it owned at the start of the turn (C may belong to anyone). With both
## rules, either is enough, and the reason names both.
static func _check_road_move(state: GameState, faction: Faction, army: Army, here: Province, dest: Province, via_id: String) -> Dictionary:
	var label := _army_name(state, army)
	var kings := RulerRules.has_mandate(state, faction.id, RulerRules.KINGS_ROADS)
	var stride := AscensionRules.has_forest_stride(state, faction.id)
	if not kings and not stride:
		var why := "Only a faction with King's Roads can move an army two provinces in one turn, so %s can't go through %s to %s. Armies move one neighboring province per turn." % [
			label, _province_name(state, via_id), dest.name]
		if AscensionRules.has_paths(state) and AscensionRules.path_has_forest_stride(faction.id):
			why += " Forest Stride, on your path, lets armies move through a forest you own into another forest."
		return _reject("no_kings_roads", why)
	var via := state.find_province(via_id)
	if via == null:
		return _reject("unknown_via", "That road move goes through a place that is not on the map.")
	if here == null or via.id == here.id or not here.neighbors.has(via.id):
		return _reject("via_not_adjacent", "%s is not next to %s, so a road move can't go through it." % [via.name, _province_name(state, army.location)])
	if not via.neighbors.has(dest.id):
		return _reject("road_not_adjacent", "%s is not next to %s, so a road move through %s can't reach it." % [dest.name, via.name, via.name])
	var kings_why := ""
	if kings:
		if via.owner != faction.id:
			kings_why = "King's Roads run only through your own land, and %s is not yours. A road move goes through a province you owned at the start of the turn." % via.name
		elif dest.owner != faction.id:
			kings_why = "King's Roads run only through your own land, and %s is not yours. Move one province at a time to take it." % dest.name
		if kings_why.is_empty():
			return {}
		if not stride:
			return _reject("road_not_owned", kings_why)
	var stride_why := AscensionRules.forest_stride_why(state, faction.id, via, dest)
	if stride_why.is_empty():
		return {}
	if not kings:
		return _reject("stride_not_forest", stride_why)
	return _reject("road_not_allowed", "Neither King's Roads nor Forest Stride allow this road move. %s %s" % [kings_why, stride_why])


## Which rule a legal road move uses (M4-2): "kings_roads" when King's Roads allow it (as in M2), otherwise
## "forest_stride". "" for a one-step move.
static func road_rule(state: GameState, faction_id: String, order: MoveOrder) -> String:
	if order == null or order.via.is_empty():
		return ""
	var via := state.find_province(order.via)
	var dest := state.find_province(order.to)
	if RulerRules.has_mandate(state, faction_id, RulerRules.KINGS_ROADS) and via != null and dest != null \
			and via.owner == faction_id and dest.owner == faction_id:
		return "kings_roads"
	return "forest_stride"


## The rule's name for text: "King's Roads" or "Forest Stride".
static func road_rule_name(rule: String) -> String:
	return "Forest Stride" if rule == "forest_stride" else "King's Roads"


## Checks a recruit order for `faction_id` with `gold_available` left to spend. Returns {} when
## valid, otherwise {"code", "reason"}. `with_ruler_before` counts the recruits with the ruler already
## paid for this turn (Warband Muster's limit); price_recruits passes it. `start_state` is the state the
## turn started from, where a recruit with the ruler gathers (muster_province); `state` itself when null,
## which is the case whenever orders are checked before the turn resolves.
## M3c, in a game with sieges (§2.3): a recruit is made at a fort, the capital ("" or its id) or another fort
## you own (`at` = its id), within that fort's limit; `at_count` is how many recruits that faction already
## ordered at the same fort this turn (price_recruits counts them). The fort rules are SiegeRules.check_recruit_at.
static func check_recruit(state: GameState, faction_id: String, order, gold_available: int, with_ruler_before: int = 0,
		start_state: GameState = null, at_count: int = 0) -> Dictionary:
	if not (order is RecruitOrder):
		return _reject("unknown_order", "That is not an order this game knows. Orders are moves and recruits.")
	var faction := state.find_faction(faction_id)
	if faction == null:
		return _reject("unknown_faction", "Those orders are for a faction that is not in this game.")
	var ut := recruitable_type(faction, order.unit_type_id, state)
	if ut == null:
		for other in state.factions:
			if recruitable_type(other, order.unit_type_id, state) != null:
				var other_ut := recruitable_type(other, order.unit_type_id, state)
				return _reject("not_in_roster", "%s belong to %s. %s can only recruit its own units." % [other_ut.name, other.faction_name, faction.faction_name])
		return _reject("unknown_unit_type", "That is not a unit type in this game. Recruit from your faction's roster.")
	var at := recruit_at(state, faction, order)
	if at == RecruitOrder.AT_RULER:
		var start := start_state if start_state != null else state
		var field := _check_recruit_with_ruler(state, faction, ut, with_ruler_before, start)
		if not field.is_empty():
			return field
		if state.sieges:  # M3c: no engines with the ruler, and nobody recruits where a siege cuts it off
			if SiegeRules.is_engine(ut):
				return _reject("engine_with_ruler", "%s are recruited only at a keep or a citadel, into an army there, not with %s." % [
					SiegeRules.engine_plural(faction_id), RulerRules.current_name(state, faction_id)])
			var muster := muster_province(start, faction_id)
			if SiegeRules.is_cut_off(start, muster, state.current_turn + 1):
				return _reject("fort_cut_off", "%s is cut off by a siege, so nobody can recruit there this turn, not even with %s; no gold is spent." % [
					_province_name(state, muster), RulerRules.current_name(state, faction_id)])
	elif not at.is_empty():
		if not state.sieges:
			return _reject("unknown_place", "Recruits are made at your capital, or with your ruler where it stands if it has Warband Muster.")
		var fort := SiegeRules.check_recruit_at(state, faction_id, at, ut, at_count, start_state)
		if not fort.is_empty():
			return fort
	else:
		var capital := state.find_province(faction.capital)
		if capital == null or capital.owner != faction_id:
			return _reject("capital_not_held", "You don't hold your capital, %s, so you can't recruit. Retake it first." % _province_name(state, faction.capital))
		if state.sieges:  # M3c: the capital is a fort too, a citadel with its own limit
			var fort := SiegeRules.check_recruit_at(state, faction_id, faction.capital, ut, at_count, start_state)
			if not fort.is_empty():
				return fort
	var price := RulerRules.recruit_price(state, faction_id, ut)
	if price > gold_available:
		return _reject("not_enough_gold", "%s cost %d gold, but you only have %d gold left." % [ut.name, price, gold_available])
	return {}


## Warband Muster (§1.4): a recruit "with the ruler" needs a ruler with the ability, on the map (in
## `state`: the start of the turn when ordering, after battles when resolving), a regular unit (commanders
## come only from the capital), room under the per-turn limit, and the province where the ruler started
## the turn (`start`, see muster_province) still owned by its faction (in `state`, so after capture when
## resolving). The reasons say the recruit costs nothing, because a recruit that fails here at the end
## of the turn is cancelled before anything is paid.
static func _check_recruit_with_ruler(state: GameState, faction: Faction, ut: UnitType, with_ruler_before: int, start: GameState) -> Dictionary:
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
	var at_id := muster_province(start, fid)
	var where := state.find_province(at_id)
	if where == null or where.owner != fid:
		return _reject("ruler_province_not_held", "%s's recruits gather where it starts the turn, at %s, which is not yours, so nobody can recruit with it there; no gold is spent." % [
			name, _province_name(state, at_id)])
	return {}


## Where recruits made with `fid`'s ruler gather and join its armies (Warband Muster, §1.4): the province
## the ruler stands in at the start of the turn, in `start_state`, wherever it goes during the turn
## (follow-up to #36: they no longer appear at the front the ruler moves to). "" without a ruler on the map.
static func muster_province(start_state: GameState, fid: String) -> String:
	var army := RulerRules.ruler_army(start_state, fid) if start_state != null else null
	return army.location if army != null else ""


## The first ruler id (in data order) whose ability is `ability_id`, for naming the ability.
static func _first_ruler_with(ability_id: String) -> String:
	for r in RulerData.RULERS:
		if String(r.get("ability", "")) == ability_id:
			return r.id
	return ""


## The unit type `faction` can recruit under this id (its roster or its commander), or null. M3c: with a
## `state` that has sieges on, also its siege engine (SiegeRules.engine_type), which is never in a roster.
static func recruitable_type(faction: Faction, unit_type_id: String, state: GameState = null) -> UnitType:
	for ut in faction.unit_types:
		if ut.id == unit_type_id:
			return ut
	if faction.commander_type and faction.commander_type.id == unit_type_id:
		return faction.commander_type
	if state != null and state.sieges and String(FortData.engine_for(faction.id).get("id", "")) == unit_type_id:
		return SiegeRules.engine_type(faction.id)
	return null


## Where a recruit order is made (M3c, §2.3): its `at`, except that in a game with sieges an `at` naming the
## faction's own capital is read as "" (the capital). Without sieges it is the order's `at` as given.
static func recruit_at(state: GameState, faction: Faction, order) -> String:
	var at: String = order.at if order is RecruitOrder else ""
	if state != null and state.sieges and faction != null and at == faction.capital:
		return ""
	return at


## Gold cost of recruiting `unit_type_id` for `faction_id`, or -1 if they can't recruit that type.
## The price with the faction's mandates (Muster Grounds): RulerRules.recruit_price, the one price
## every screen, forecast and the recruitment phase use.
static func recruit_cost(state: GameState, faction_id: String, unit_type_id: String) -> int:
	var faction := state.find_faction(faction_id)
	if faction == null:
		return -1
	var ut := recruitable_type(faction, unit_type_id, state)
	return RulerRules.recruit_price(state, faction_id, ut) if ut else -1


## Checks and prices a faction's recruit orders in the order given, spending gold as it goes.
## Used by the recruitment phase and by Forecast, so the forecast always matches the result. The
## recruitment phase passes `start_state`, the state the turn started from (where recruits with the ruler
## gather); every check made before the turn resolves leaves it null, so `state` is the start.
## Recruits at the capital and with the ruler (Warband Muster) share one gold pool and are paid in
## the order given; a recruit that fails a check costs nothing.
## Returns {"gold_before", "spent", "gold_after", "results": [per order: {"ok", "order", "at", and
## either "unit_type", "cost", "gold_after", "province" (where it appears) or "code", "reason"}]}.
## M3c, in a game with sieges (§2.3, §2.4, §5): `orders` may mix in Fortify orders, paid in the same order from
## the same gold (a result {"ok", "order", "kind": "fortify", "province", "to", "cost", "gold_after"}); recruits
## are counted per fort against its limit (results add "fort", "count", "limit"); and a siege engine needs an
## army with a fighter at its fort to carry it, one standing there now or one a recruit earlier in the list
## forms, or it is refused at no cost.
static func price_recruits(state: GameState, faction_id: String, orders: Array, start_state: GameState = null) -> Dictionary:
	var start := start_state if start_state != null else state
	var faction := state.find_faction(faction_id)
	var gold_before := faction.gold if faction else 0
	var gold := gold_before
	var with_ruler := 0
	var at_counts := {}  # M3c: fort province id -> recruits ordered there
	var carriers := {}  # M3c: fort province id -> {"room": engines it can still take, "army": a non-ruler army is there}
	var fortified := 0  # M3c: Fortify orders paid
	var results := []
	for order in orders:
		if order is FortifyOrder:
			var fortify := _price_fortify(state, faction_id, order, gold, fortified, start)
			if fortify.ok:
				gold = int(fortify.gold_after)
				fortified += 1
			results.append(fortify)
			continue
		var place := ""  # M3c: the fort a recruit is counted against ("" without sieges and with the ruler)
		var at: String = order.at if order is RecruitOrder else ""
		if state.sieges and order is RecruitOrder and faction != null and at != RecruitOrder.AT_RULER:
			place = SiegeRules.recruit_place(state, faction, recruit_at(state, faction, order))
		var check := check_recruit(state, faction_id, order, gold, with_ruler, start, int(at_counts.get(place, 0)))
		var ut: UnitType = recruitable_type(faction, order.unit_type_id, state) if check.is_empty() else null
		var engine := SiegeRules.is_engine(ut)
		if engine and _carrier_room(state, faction_id, place, carriers) <= 0:
			check = _reject("engine_no_army", "%s need an army at %s to carry them: recruit troops there first, or march an army in. No gold is spent." % [
				SiegeRules.engine_plural(faction_id), _province_name(state, place)])
		if check.is_empty():
			var price := RulerRules.recruit_price(state, faction_id, ut)
			gold -= price
			var province := faction.capital
			if at == RecruitOrder.AT_RULER:
				with_ruler += 1
				province = muster_province(start, faction_id)
			elif not place.is_empty():
				province = place
			# M4-2: the hp it arrives with (Blood Levy: a quarter missing), as _add_recruit gives it.
			var max_hp := 0 if engine else int(RulerRules.unit_stats(state, faction_id, ut.id).hp)
			var result := {"ok": true, "order": order, "at": at, "unit_type": ut.id, "cost": price, "gold_after": gold,
				"province": province, "max_hp": max_hp, "hp": 0 if engine else AscensionRules.arrival_hp(state, faction_id, ut, max_hp)}
			if not place.is_empty():
				at_counts[place] = int(at_counts.get(place, 0)) + 1
				_carrier_room(state, faction_id, place, carriers)
				if engine:
					carriers[place].room = int(carriers[place].room) - 1
				elif not bool(carriers[place].army):
					carriers[place].army = true  # this recruit forms a new army there, which can carry engines
					carriers[place].room = int(carriers[place].room) + FortData.ARMY_ENGINES_MAX
				var level := start.find_province(place).fort_level if start.find_province(place) else 0
				result["fort"] = place
				result["count"] = at_counts[place]
				result["limit"] = SiegeRules.recruit_limit(level)
				result["engine"] = engine
			results.append(result)
		else:
			results.append({"ok": false, "order": order, "at": at, "code": check.code, "reason": check.reason})
	return {"gold_before": gold_before, "spent": gold_before - gold, "gold_after": gold, "results": results}


## A Fortify order's price (M3c, §2.4): its checks (SiegeRules.check_fortify, against the start of the turn and,
## for "still yours", `state`), then the gold. `fortified` counts the Fortify orders already paid this turn.
static func _price_fortify(state: GameState, faction_id: String, order: FortifyOrder, gold: int, fortified: int, start: GameState) -> Dictionary:
	var check := SiegeRules.check_fortify(state, faction_id, order.province, start, fortified)
	var to := SiegeRules.fortify_level(start, order.province)
	var cost := int(SiegeRules.level_data(to).cost)
	if check.is_empty() and cost > gold:
		check = _reject("not_enough_gold", "%s at %s costs %d gold, but you only have %d gold left." % [SiegeRules.level_name(to),
			_province_name(state, order.province), cost, gold])
	if not check.is_empty():
		return {"ok": false, "order": order, "at": "", "kind": "fortify", "province": order.province, "code": check.code, "reason": check.reason}
	return {"ok": true, "order": order, "at": "", "kind": "fortify", "province": order.province, "to": to, "cost": cost,
		"gold_after": gold - cost}


## How many more engines `faction_id`'s armies at `place` can carry (M3c, §5), worked out once from `state` and
## then kept in `carriers` as recruits are priced.
static func _carrier_room(state: GameState, faction_id: String, place: String, carriers: Dictionary) -> int:
	if not carriers.has(place):
		var room := 0
		var army := false
		for a in state.armies:
			if a.owner == faction_id and a.location == place and a.ruler == null:
				army = true
				if SiegeRules.can_carry(a):
					room += FortData.ARMY_ENGINES_MAX - a.engines
		carriers[place] = {"room": room, "army": army}
	return int(carriers[place].room)


## Income `faction_id` earns from the provinces it owns now: {"total", "by_province": {id: income},
## "base", "modifiers": {"heavy_tithes": gold, "royal_court": gold}, "court_at": province id or ""}.
## Each province's income is RulerRules.province_income_parts' total: its base income plus Heavy
## Tithes and Royal Court (M2). `ruler_at` ({faction id: province id}) moves a ruler for a forecast.
## M3c, in a game with sieges (§3.3, §12): a cut-off province pays its owner nothing (its parts carry
## "cut_off"), and its base income goes to the besieging faction, under the key BESIEGED_PREFIX + its id in
## both "modifiers" and "by_province", so base plus every modifier is still the total on both sides.
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
	if state.sieges:
		for pid in besieged_income(state, faction_id):
			var gold := int(state.find_province(pid).income)
			total += gold
			by_province[pid] = gold
			modifiers[BESIEGED_PREFIX + pid] = gold
	return {"total": total, "by_province": by_province, "base": base, "modifiers": modifiers, "court_at": court_at}


## The key of a besieged province's income line on the besieger's side (M3c).
const BESIEGED_PREFIX := "besieged:"


## The provinces whose base income `faction_id` takes this turn because its siege cuts them off (M3c, §3.3), in
## id order. Read after battles when resolving, at the start of the turn for a forecast.
static func besieged_income(state: GameState, faction_id: String) -> Array:
	var out := []
	if not state.sieges:
		return out
	for p in _sorted_provinces(state):
		if p.owner != faction_id and SiegeRules.is_besieged(state, p.id):
			var cut := SiegeRules.cut_off_info(state, p.id)
			if bool(cut.cut_off) and String(cut.besieger) == faction_id:
				out.append(p.id)
	return out


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


## M3c: Fortify orders are checked here (SiegeRules.check_fortify) and join `recruits` to be paid in recruitment;
## storm and sally orders are checked after every move order of their faction, against all of its valid moves,
## and the ones that pass are recorded in `siege_orders` ({"storms": {province id: {faction id: true}},
## "sallies": {army id: {"faction", "with"}}}) for the battles phase.
static func _collect_orders(s: GameState, orders_by_faction: Dictionary, moves: Array, recruits: Dictionary, events: Array,
		siege_orders: Dictionary = {}) -> void:
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
		var research_given := ""  # M4: the node of this faction's research order this turn, if any
		var fortify_given := 0  # M3c: Fortify orders that passed this turn
		var valid_moves := []  # M3c: this faction's valid move orders, for its siege orders
		var siege_list := []  # M3c: its storm and sally orders, checked after every move
		recruits[fid] = []
		for order in list:
			if order is MoveOrder:
				var check := check_move(s, fid, order, ordered)
				if not check.is_empty():
					events.append(_rejected_event(s, fid, order, check, "orders"))
					continue
				ordered[order.army_id] = true
				valid_moves.append(order)
				var army := s.find_army(order.army_id)
				# Label taken before anyone moves, so it names the province the army leaves from.
				# "via" is set for a road move (King's Roads), "" for a one-step move.
				moves.append({"army_id": army.id, "faction": fid, "from": army.location, "to": order.to,
					"label": army_label(s, army), "via": order.via, "road": road_rule(s, fid, order)})
			elif order is RecruitOrder:
				recruits[fid].append(order)  # checked in the recruitment phase, against that phase's state
			elif order is FortifyOrder:
				# M3c: checked now, paid in the recruitment phase with the recruits, in the order given.
				var check := SiegeRules.check_fortify(s, fid, order.province, null, fortify_given)
				if not check.is_empty():
					events.append(_rejected_event(s, fid, order, check, "orders"))
					continue
				fortify_given += 1
				recruits[fid].append(order)
			elif order is SiegeOrder:
				siege_list.append(order)  # M3c: checked after every move of this faction, below
			elif order is SacrificeOrder:
				continue  # resolved in the sacrifice phase, before these checks (M2-6)
			elif order is ResearchOrder:
				# M4: sets the research target (silently: the target is private). One per turn.
				var check := _check_research_order(s, fid, order, research_given)
				if not check.is_empty():
					events.append(_rejected_event(s, fid, order, check, "orders"))
					continue
				research_given = order.node_id
				AscensionRules.set_target(s, fid, order.node_id)
			else:
				events.append(_rejected_event(s, fid, order,
					_reject("unknown_order", "That is not an order this game knows. Orders are moves and recruits."), "orders"))
		var given := []
		if not siege_list.is_empty() and not siege_orders.has("storms"):
			siege_orders["storms"] = {}
			siege_orders["sallies"] = {}
		for order in siege_list:
			var check := SiegeRules.check_siege_order(s, fid, order, valid_moves, given)
			if not check.is_empty():
				events.append(_rejected_event(s, fid, order, check, "orders"))
				continue
			given.append(order)
			if order.is_storm():
				if not siege_orders.storms.has(order.province):
					siege_orders.storms[order.province] = {}
				siege_orders.storms[order.province][fid] = true
			else:
				siege_orders.sallies[order.army_id] = {"faction": fid, "with": order.with_army}


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


static func _province_battles(s: GameState, resolver: BattleResolver, rng: SeededRNG, moved: Dictionary, battle_sites: Dictionary, events: Array,
		siege_orders: Dictionary = {}) -> void:
	for p in _sorted_provinces(s):
		if s.sieges and p.fort_level > 0:
			_fort_battles(s, resolver, rng, p, moved, battle_sites, events, siege_orders)  # M3c
			continue
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


## The battles at a fort in a game with sieges (M3c, §3.9): SiegeRules.next_battle, asked again after each battle
## on the armies still standing, decides whether there is one, who fights it and who defends. None at all means
## an enemy besieges a garrison behind standing walls.
static func _fort_battles(s: GameState, resolver: BattleResolver, rng: SeededRNG, p: Province, moved: Dictionary, battle_sites: Dictionary,
		events: Array, siege_orders: Dictionary) -> void:
	var fought := 0
	while true:
		var plan := SiegeRules.next_battle(s, p.id, moved, siege_orders, fought)
		if plan.is_empty():
			return
		_fight(s, resolver, rng, "province", [p.id], plan.sides, String(plan.defender), events)
		battle_sites[p.id] = true
		fought += 1


## Runs one battle, destroys the losing armies, records the event and any ruler deaths (M2). Returns
## the winner's faction id. M3-1: when the resolver gives a battle event log (AutoBattleResolver does),
## the event's numbers carry it as "log", with its id "t<turn>b<index>" and the aftermath event added.
static func _fight(s: GameState, resolver: BattleResolver, rng: SeededRNG, kind: String, province_ids: Array, sides: Dictionary, defender: String, events: Array) -> String:
	var fids: Array = sides.keys()
	fids.sort()
	var rulers_in := _rulers_in_battle(sides)  # M2: whose rulers fight here, to record deaths after
	var ruler_names := {}  # M2-2: army id -> the name of the ruler it holds, read before the battle
	for fid in fids:
		for a in sides[fid]:
			if a.ruler != null:
				ruler_names[a.id] = a.ruler.type.name
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
	var lost_by_faction := {}  # losing faction id -> {"armies", "units" (fighters), "rulers" (names)} destroyed with it
	var winner_wiped := 0  # winning armies whose every unit fell
	var rulers_lost := []  # M2-2: rulers lost with a losing side, by name
	var fallen := []  # M2-2: rulers of the winning side that fell, by name (their armies go with them)
	for fid in fids:
		for a in sides[fid]:
			army_ids.append(a.id)
			if fid != winner:
				destroyed.append(a.id)
				var n: int = a.units.size() + (1 if a.commander else 0)
				units_lost += n
				var lost: Dictionary = lost_by_faction.get(fid, {"armies": 0, "units": 0, "rulers": []})
				var rulers: Array = lost.rulers.duplicate()
				if a.ruler != null:
					rulers.append(a.ruler.type.name)  # the ruler is a fighter too (M2-2)
					rulers_lost.append(a.ruler.type.name)
				lost_by_faction[fid] = {"armies": lost.armies + 1, "units": lost.units + n + (1 if a.ruler else 0), "rulers": rulers}
			elif a.units.is_empty() and a.commander == null and a.ruler == null:
				destroyed.append(a.id)  # every unit of this winning army fell (a ruler's army holds only its ruler)
				if ruler_names.has(a.id):
					fallen.append(ruler_names[a.id])  # its ruler fell (M2-2): the ruler_died event follows
				else:
					winner_wiped += 1
	var survivors: Array[Army] = []
	for a in s.armies:
		if not destroyed.has(a.id):
			survivors.append(a)
	s.armies = survivors

	var strengths: Dictionary = result.get("strengths", {})
	var report: Dictionary = result.get("report", {})
	var harvest: Dictionary = report.get("red_harvest", {})
	if not harvest.is_empty():
		# M4-3: Red Harvest pays the winner for every enemy fighter lost (the aftermath says so).
		var wf := s.find_faction(winner)
		if wf != null:
			wf.gold += int(harvest.get("gold", 0))
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
	var lost_text := "%d %s" % [units_lost, "unit" if units_lost == 1 else "units"]
	if not rulers_lost.is_empty():
		# M2-2: the ruler counts among the losses ("lost 1 army (King Corvane I)").
		lost_text = RulerRules._and_list(rulers_lost) if units_lost == 0 else "%s and %s" % [lost_text, RulerRules._and_list(rulers_lost)]
	var text := "%s %s won: %s. %s lost %d %s (%s)." % [where, _faction_name(s, winner), result.get("why", ""),
		" and ".join(losers), destroyed.size() - fallen.size(), "army" if destroyed.size() - fallen.size() == 1 else "armies", lost_text]
	if not fallen.is_empty():
		text += " %s won, but %s fell." % [_faction_name(s, winner), RulerRules._and_list(fallen)]
	if not report.is_empty():
		# One line with the result and the "why", then what happened to each loser's armies. The full
		# report rides along in numbers.report (#7) and gets the same aftermath as its last line.
		var aftermath := _aftermath(s, report, winner, fids, lost_by_faction, winner_wiped, fallen)
		report["aftermath"] = aftermath
		if report.get("lines") is Array:
			report.lines.append("Aftermath: %s" % aftermath)
		text = "%s %s %s" % [where, report.get("summary", result.get("why", "")), aftermath]

	var numbers := {"strengths": strengths, "winner": winner, "defender": defender, "tie_break": result.get("tie_break", "none"),
		"roll": result.get("roll", 0), "armies_destroyed": destroyed.size(), "units_lost": units_lost,
		"destroyed": destroyed, "why": result.get("why", ""), "report": report}
	if not rulers_lost.is_empty() or not fallen.is_empty():
		numbers["rulers_lost"] = rulers_lost.size() + fallen.size()  # M2-2: only in games with rulers
	if not harvest.is_empty():
		numbers["red_harvest"] = int(harvest.get("gold", 0))  # M4-3: gold paid to the winner
	var battle_log = result.get("log")
	if battle_log is Dictionary and not battle_log.is_empty():
		# M3-1: the battle event log rides beside the report (in memory only: never in the game record).
		# Its id, turn (as players count turns) and index (resolution order), then the aftermath event.
		var index := 0
		for e in events:
			if e.type == "battle" or e.type == "border_battle":
				index += 1
		BattleLog.attach(battle_log, s.current_turn + 1, index, winner, destroyed, String(report.get("aftermath", "")))
		numbers["log"] = battle_log
	events.append(_event("border_battle" if kind == "border" else "battle", "battles", province_ids, fids, army_ids, cause,
		numbers, text, codex))
	_record_ruler_deaths(s, rulers_in, winner, kind, province_ids, events)
	return winner


## What happened to each losing side, one sentence each (RulesCodex "battle_rounds"): its armies are
## destroyed whether it was wiped out, routed, or was still standing when the round cap ran out.
## `report` is an AutoBattleResolver report; `lost_by_faction` counts the armies and fighters removed
## (and names the rulers among them). M2-2: `fallen` names the winner's rulers that fell, and a Feast of
## Victory (report "feast") gets its own sentence.
static func _aftermath(s: GameState, report: Dictionary, winner: String, fids: Array, lost_by_faction: Dictionary, winner_wiped: int,
		fallen: Array = []) -> String:
	var sentences := []
	for fid in fids:
		if fid == winner:
			continue
		var sr := {}
		for side in report.get("sides", []):
			if side.faction == fid:
				sr = side
		var name := _faction_name(s, fid)
		var lost: Dictionary = lost_by_faction.get(fid, {"armies": 0, "units": 0, "rulers": []})
		var one: bool = lost.armies == 1
		var armies: String = "its army was" if one else "its %d armies were" % lost.armies
		# "fighters", as in the battle report: units, commanders and the ruler alike.
		var units := "%d %s lost" % [lost.units, "fighter" if lost.units == 1 else "fighters"]
		var rulers: Array = lost.get("rulers", [])
		if not rulers.is_empty():
			units = ("%s lost" % RulerRules._and_list(rulers)) if lost.units == rulers.size() \
				else "%s, among them %s" % [units, RulerRules._and_list(rulers)]
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
	if not fallen.is_empty():
		sentences.append("%s won, but %s fell in the battle." % [_faction_name(s, winner), RulerRules._and_list(fallen)])
	var feast: Dictionary = report.get("feast", {})
	if not feast.is_empty():
		# Feast of Victory (§2.3): the winner's fighters still standing healed to full.
		var n := int(feast.get("fighters", 0))
		sentences.append("%s: the %s %s healed to full (+%d hp)." % [RulerRules.mandate_name(RulerRules.FEAST_OF_VICTORY),
			RulerRules._possessive(String(feast.get("name", ""))), "only surviving fighter" if n == 1 else "%d surviving fighters" % n,
			int(feast.get("healed", 0))])
	var harvest: Dictionary = report.get("red_harvest", {})
	if not harvest.is_empty():
		# M4-3, §9.5: "Red Harvest: the Thornmane Clans took 23 gold from the 23 enemy fighters lost."
		var lost := int(harvest.get("fighters", 0))
		sentences.append("%s: %s took %d gold from the %s." % [_red_harvest_name(), _the_name(s, winner), int(harvest.get("gold", 0)),
			"enemy fighter lost" if lost == 1 else "%d enemy fighters lost" % lost])
	return " ".join(sentences)


## Red Harvest's name, from its MandateData row when there is one (M4-2 adds it).
static func _red_harvest_name() -> String:
	var md := RulerRules.mandate_data(AutoBattleResolver.RED_HARVEST)
	return String(md.get("name", "Red Harvest"))


## A faction's name in running text with "the" ("the Thornmane Clans"), as the turn report writes it.
static func _the_name(s: GameState, fid: String) -> String:
	return "the " + _faction_name(s, fid)


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


# --- the sieges phase (M3c, #98; design/M3C_SIEGES.md §3.3, §3.10, §2.4-§2.6, §6 step 5) -----------------
# Games with sieges only, after battles and before capture. Each province in id order: SiegeRules.siege_step
# (a siege starts or goes on and the walls drop; it is lifted; or the fort falls), then repair, then
# construction (neither in a fort that fell). No randomness. Events (codex in brackets):
#   siege_started       a siege began: the besiegers, the walls' drop, the cut-off from next turn, the breach turn [siege]
#   walls_damaged       a siege went on and the walls dropped [walls]
#   walls_breached      the walls reached 0 [breach]
#   siege_lifted        only the owner's armies are left (the besiegers left or were beaten) [siege]
#   siege_ended         only enemy armies are left: the fort falls, and capture hands it over [siege]
#   walls_repaired      no army of another faction stands there, and the walls rose by the level [repair]
#   construction_halted an enemy army stands at a construction site, so no work was done [construction]
#   fort_built          the last turn of work was done: the new level stands at full walls [fort_levels]
static func _sieges_phase(s: GameState, battle_sites: Dictionary, events: Array) -> void:
	if not s.sieges:
		return
	var turn := s.current_turn + 1  # the turn being resolved, as players count it
	for p in _sorted_provinces(s):
		var step := SiegeRules.siege_step(s, p.id, turn, battle_sites)
		var kind := String(step.get("kind", ""))
		if not kind.is_empty():
			_siege_events(s, step, turn, events)
		if kind == "fallen":
			continue  # no repair and no work: capture hands the fort over and razes any construction
		var repaired := SiegeRules.repair_step(s, p.id)
		if not repaired.is_empty():
			events.append(_event("walls_repaired", SIEGES_PHASE, [p.id], [p.owner], [], "repair",
				{"from": repaired.from, "to": repaired.to, "amount": repaired.amount, "walls_max": SiegeRules.walls_max(p.fort_level)},
				SiegeRules.repaired_text(s, repaired), "repair"))
		var work := SiegeRules.works_step(s, p.id)
		match String(work.get("kind", "")):
			"halted":
				# With nobody of its owner there, capture razes the site this turn instead (construction_razed).
				if not SiegeRules.owner_armies(s, p.id).is_empty():
					events.append(_event("construction_halted", SIEGES_PHASE, [p.id], [String(work.faction)], [], "enemy_present",
						{"to": work.to, "left": work.left, "turns": work.turns}, SiegeRules.works_text(s, work, turn), "construction"))
			"built":
				events.append(_event("fort_built", SIEGES_PHASE, [p.id], [String(work.faction)], [], "construction",
					{"level": work.to, "walls": work.walls, "recruits": SiegeRules.recruit_limit(int(work.to)), "recruit_from": turn + 1},
					SiegeRules.works_text(s, work, turn), "fort_levels"))


## The events for one siege_step result (see _sieges_phase).
static func _siege_events(s: GameState, step: Dictionary, turn: int, events: Array) -> void:
	var pid := String(step.province)
	var owner := String(step.owner)
	var besieger := String(step.besieger)
	var involved := [besieger, owner] if not besieger.is_empty() else [owner]
	var outside := []
	for a in SiegeRules.besiegers(s, pid):
		outside.append(a.id)
	var numbers := {"owner": owner, "besieger": besieger, "walls_before": step.walls_before, "walls": step.walls,
		"walls_max": step.walls_max, "turn_of_siege": step.turn_of_siege}
	var kind := String(step.kind)
	if kind == "started" or kind == "damaged":
		var dmg: Dictionary = step.damage
		numbers["damage"] = dmg.total
		numbers["damage_parts"] = dmg.parts.duplicate(true)
		numbers["troops"] = dmg.troops
		numbers["engines"] = dmg.engines
		numbers["engines_counted"] = dmg.engines_counted
		numbers["breach_turn"] = SiegeRules.breach_turn(int(step.walls), int(dmg.total), turn + 1) if int(step.walls) > 0 else turn
		var cut := SiegeRules.cut_off_info(s, pid, turn + 1)
		numbers["pickets"] = cut.pickets
		numbers["cut_off_from"] = int(s.find_province(pid).siege_since) + 1 if not bool(cut.pickets) else 0
		if kind == "started":
			events.append(_event("siege_started", SIEGES_PHASE, [pid], involved, outside, kind, numbers, SiegeRules.step_text(s, step, turn),
				"siege"))
		else:
			events.append(_event("walls_damaged", SIEGES_PHASE, [pid], involved, outside, kind, numbers, SiegeRules.step_text(s, step, turn),
				"walls"))
		if bool(step.breached):
			events.append(_event("walls_breached", SIEGES_PHASE, [pid], involved, outside, "breached",
				{"owner": owner, "besieger": besieger, "walls_max": step.walls_max, "battle_turn": turn + 1},
				SiegeRules.breached_text(s, pid, turn), "breach"))
		return
	numbers["why"] = step.why
	var ended := "siege_lifted" if kind == "lifted" else "siege_ended"
	events.append(_event(ended, SIEGES_PHASE, [pid], involved, outside, String(step.why), numbers,
		SiegeRules.step_text(s, step, turn), "siege"))


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
		var numbers := {"income": p.income, "is_capital": not capital_of.is_empty()}
		var razed := {}
		if s.sieges:
			razed = _take_fort(s, p, fid, previous)  # M3c: owned_since, the retake rule, razing
			if p.fort_level > 0:
				text += " " + _fort_capture_text(s, p, fid)
				numbers["fort_level"] = p.fort_level
				numbers["walls"] = p.walls
				numbers["recruit_from"] = maxi(recruit_from_turn(p), s.current_turn + 2)
		events.append(_event("captured", "capture", [p.id], involved, army_ids, cause, numbers, text, "capture"))
		if not razed.is_empty():
			events.append(_event("construction_razed", "capture", [p.id], [fid, String(razed.faction)], army_ids, "captured",
				{"to": razed.to, "left": razed.left, "level": p.fort_level},
				_razed_text(s, p, fid, int(razed.to)), "construction"))
		_raid(s, fid, p, army_ids, events)  # M4-2: Raiding Parties, for captures by armies only
	_sworn_vassals(s, events)


## M3c (§2.3, §2.5, §3.8): `fid` takes `p` from `previous` ("" for a neutral province). Sets owned_since to the
## turn being resolved, or restores the old standing when `fid` lost it no more than FortData.RETAKE_TURNS turns
## ago; records who lost it; razes a construction site. Returns the razed site ({} when there was none).
static func _take_fort(s: GameState, p: Province, fid: String, previous: String) -> Dictionary:
	var turn := s.current_turn + 1
	var old_since := p.owned_since
	var retaken := not p.lost.is_empty() and String(p.lost.get("faction", "")) == fid \
		and turn <= int(p.lost.get("turn", 0)) + FortData.RETAKE_TURNS
	p.owned_since = int(p.lost.get("owned_since", 0)) if retaken else turn
	p.lost = {"faction": previous, "owned_since": old_since, "turn": turn} if not previous.is_empty() else {}
	var razed := p.works.duplicate()
	p.works = {}
	return razed


## The first turn the owner of `p` may recruit there by the wait after a capture (M3c, §2.3): 1 for an owner from
## the start, otherwise owned_since + FortData.CAPTURE_WAIT + 1 (a fort taken on turn 7 takes recruits from 9).
static func recruit_from_turn(p: Province) -> int:
	return 1 if p.owned_since <= 0 else p.owned_since + FortData.CAPTURE_WAIT + 1


## The captured event's fort clause (§9.4): "It came with its keep (walls 2 of 6): the Thornmane Clans can
## recruit there from turn 9." A fort retaken in time can take recruits from next turn.
static func _fort_capture_text(s: GameState, p: Province, fid: String) -> String:
	var next := s.current_turn + 2
	var from := recruit_from_turn(p)
	var when := "from turn %d" % from
	if from <= next:
		when = "from next turn (%d), since they retook it within %d turns of losing it" % [next, FortData.RETAKE_TURNS]
	return "It came with its %s (walls %d of %d): the %s can recruit there %s." % [SiegeRules.level_word(p.fort_level), p.walls,
		SiegeRules.walls_max(p.fort_level), _faction_name(s, fid), when]


## "The Thornmane Clans razed the half-built keep at Rivermarch when they took it. The palisade stands." (§2.5)
static func _razed_text(s: GameState, p: Province, fid: String, to: int) -> String:
	var text := "The %s razed the half-built %s at %s when they took it." % [_faction_name(s, fid), SiegeRules.level_word(to), p.name]
	if p.fort_level > 0:
		text += " The %s stands." % SiegeRules.level_word(p.fort_level)
	return text


## Raiding Parties (M4-2, §3.6, §7 step 5): when `fid`'s armies capture `p`, it takes n x its base income in
## gold, once. Event:
##   raided  capture  the gold taken. Codex "raiding_parties".
## Nothing without the node (so no event in M1, M2 or a game where nobody has it).
static func _raid(s: GameState, fid: String, p: Province, army_ids: Array, events: Array) -> void:
	var raid := AscensionRules.capture_gold(s, fid, p)
	if int(raid.gold) <= 0:
		return
	var f := s.find_faction(fid)
	var before := f.gold
	f.gold += int(raid.gold)
	events.append(_event("raided", "capture", [p.id], [fid], army_ids.duplicate(), "raiding_parties",
		{"gold": raid.gold, "income": p.income, "times": raid.times, "gold_before": before, "gold_after": f.gold},
		AscensionRules.raided_text(s, fid, p, raid, before, f.gold), "raiding_parties"))


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
		if s.sieges:
			_take_fort(s, p, fid, "")  # M3c: Sworn Vassals sets owned_since too
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


static func _recruitment(s: GameState, recruits: Dictionary, events: Array, start: GameState = null) -> void:
	for fid in _faction_ids(s):
		var list: Array = recruits.get(fid, [])
		if list.is_empty():
			continue
		var faction := s.find_faction(fid)
		var priced := price_recruits(s, fid, list, start)
		faction.gold = priced.gold_after
		for r in priced.results:
			if not r.ok:
				events.append(_rejected_event(s, fid, r.order, r, "recruitment"))
				continue
			if String(r.get("kind", "")) == "fortify":
				_start_works(s, fid, r, events)  # M3c
				continue
			var ut := recruitable_type(faction, r.unit_type, s)
			if SiegeRules.is_engine(ut):
				_recruit_engine(s, faction, ut, r, events)  # M3c
				continue
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
			if r.has("fort"):  # M3c: "at Stonegate (keep, 3 of 4 this turn)"
				how = "at %s (%s, %d of %d this turn)" % [_province_name(s, r.province),
					SiegeRules.level_word(start.find_province(r.province).fort_level if start != null else 0), int(r.count), int(r.limit)]
			if with_ruler:
				# Warband Muster (§7.5): still a "recruited" event, saying with whom and where they gathered.
				how = "with %s at %s, where it started the turn," % [RulerRules.current_name(s, fid), _province_name(s, r.province)]
			var numbers := {"cost": r.cost, "gold_after": r.gold_after, "new_army": placed.created}
			if r.has("fort"):  # M3c: where it was made, and that fort's count this turn
				numbers["fort"] = r.fort
				numbers["count"] = r.count
				numbers["limit"] = r.limit
			var text := "%s recruited %s %s for %d gold (%d gold left). %s" % [faction.faction_name, ut.name, how, r.cost,
				r.gold_after, joined]
			if int(placed.hp) < int(placed.max_hp):
				# M4-2, Blood Levy (§4.5, §9.5): only a recruit that arrives wounded carries these, so M1/M2 events are unchanged.
				numbers["hp"] = placed.hp
				numbers["max_hp"] = placed.max_hp
				numbers["blood_levy"] = AscensionRules.blood_levy_divisor(s, fid)
				text += " " + AscensionRules.arrival_text(ut, int(placed.hp), int(placed.max_hp), int(numbers.blood_levy))
			events.append(_event("recruited", "recruitment", [r.province], [fid], [army.id], "with_ruler" if with_ruler else "order",
				numbers, text, "field_recruit" if with_ruler else "recruit"))


## M3c (§2.4): a paid Fortify order starts its site, with all its turns of work left.
##   construction_started  recruitment  the site, its cost, and when it stands and takes recruits. Codex "fortify".
static func _start_works(s: GameState, fid: String, r: Dictionary, events: Array) -> void:
	var p := s.find_province(String(r.province))
	var to := int(r.to)
	var turns := int(SiegeRules.level_data(to).turns)
	var turn := s.current_turn + 1
	p.works = {"faction": fid, "to": to, "left": turns, "turn": turn}
	var stands := turn + turns
	var text := "The %s began %s at %s for %d gold (%d gold left). It stands at the end of turn %d if no enemy army stands there meanwhile, and takes recruits from turn %d." % [
		_faction_name(s, fid), SiegeRules.fort_phrase(to), p.name, int(r.cost), int(r.gold_after), stands, stands + 1]
	events.append(_event("construction_started", "recruitment", [p.id], [fid], [], "order",
		{"cost": r.cost, "gold_after": r.gold_after, "to": to, "left": turns, "stands": stands, "recruit_from": stands + 1},
		text, "fortify"))


## M3c (§5): a paid siege engine joins the first army of the faction at its fort that can carry it (a fighter,
## not a ruler's army, fewer than FortData.ARMY_ENGINES_MAX engines). price_recruits only accepts it when there
## is one.
static func _recruit_engine(s: GameState, faction: Faction, ut: UnitType, r: Dictionary, events: Array) -> void:
	var army: Army = null
	for a in _sorted_armies(s):
		if a.owner == faction.id and a.location == r.province and SiegeRules.can_carry(a):
			army = a
			break
	if army == null:
		return  # price_recruits refuses an engine with no army to carry it, so this can't happen
	army.engines += 1
	var text := "%s recruited %s%s at %s (%s, %d of %d this turn) for %d gold (%d gold left). It joined the %s, which now carries %s." % [
		faction.faction_name, "" if ut.name.ends_with("s") else "a ", ut.name, _province_name(s, r.province), SiegeRules.level_word(s.find_province(r.province).fort_level),
		int(r.get("count", 0)), int(r.get("limit", 0)), r.cost, r.gold_after, army_label(s, army), SiegeRules.engines_text(faction.id, army.engines)]
	events.append(_event("recruited", "recruitment", [r.province], [faction.id], [army.id], "engine",
		{"cost": r.cost, "gold_after": r.gold_after, "new_army": false, "engine": ut.id, "engines": army.engines,
			"fort": r.get("fort", r.province), "count": r.get("count", 0), "limit": r.get("limit", 0)},
		text, SiegeRules.engine_codex(ut.id)))


## Puts a new unit into the faction's first army (by id) at `location` (its capital by default), or a
## new army there. A commander goes to the first army there without one. Recruits never join a ruler's
## army: a ruler travels alone (RulesCodex "ruler_army").
## Returns {"army": the army it joined, "created": true if that army was formed by this recruit, "hp" (the hp
## it arrives with), "max_hp"}. M4-2: under Blood Levy a regular recruit arrives missing a quarter of its hp.
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
	var max_hp := unit.current_hp
	if ut.is_commander:
		army.commander = unit
	else:
		max_hp = RulerRules.unit_max_hp(s, unit)
		unit.current_hp = AscensionRules.arrival_hp(s, faction.id, ut, max_hp)  # M2-2: the maximum; M4-2: Blood Levy
		army.units.append(unit)
	return {"army": army, "created": created, "hp": unit.current_hp, "max_hp": max_hp}


static func _income(s: GameState, events: Array) -> void:
	for fid in _faction_ids(s):
		var faction := s.find_faction(fid)
		var inc := income_of(s, fid)
		var before := faction.gold
		faction.gold += inc.total
		if s.sieges:
			events.append(_siege_income_event(s, fid, inc, before))  # M3c: names cut-off and besieged provinces
			continue
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


## The income event in a game with sieges (M3c, §9.4): the provinces that paid, then the besieged provinces whose
## income the faction took, then each of its cut-off provinces: "Stonegate paid nothing: it is cut off, and its
## 8 gold went to the Thornmane Clans." The numbers add "cut_off" and "besieged" ({province id: gold}).
static func _siege_income_event(s: GameState, fid: String, inc: Dictionary, before: int) -> Dictionary:
	var faction := s.find_faction(fid)
	var parts := []
	var paid := 0
	var cut := {}
	var taken := {}
	for pid in inc.by_province:
		if inc.modifiers.has(BESIEGED_PREFIX + pid):
			taken[pid] = int(inc.by_province[pid])
		elif SiegeRules.is_cut_off(s, pid):
			cut[pid] = int(s.find_province(pid).income)
		else:
			parts.append("%s %d" % [_province_name(s, pid), inc.by_province[pid]])
			paid += 1
	var extra := ""
	if not taken.is_empty():
		var bits := []
		for pid in taken:
			bits.append("%d from besieged %s" % [taken[pid], _province_name(s, pid)])
		extra = " and %s" % RulerRules._and_list(bits)
	var text := "%s earned %d gold from %d %s%s%s. Gold: %d -> %d." % [faction.faction_name, inc.total, paid,
		"province" if paid == 1 else "provinces", "" if parts.is_empty() else " (%s)" % ", ".join(parts), extra, before, faction.gold]
	for pid in cut:
		var info := SiegeRules.cut_off_info(s, pid)
		text += " %s paid nothing: it is cut off, and its %d gold went to the %s." % [_province_name(s, pid), int(cut[pid]),
			_faction_name(s, String(info.besieger))]
	var numbers := {"income": inc.total, "gold_before": before, "gold_after": faction.gold, "by_province": inc.by_province}
	if not inc.modifiers.is_empty():
		var mods := income_modifiers_text(s, fid, inc, "was")
		if not mods.is_empty():
			text += " %s" % mods
		numbers["base"] = inc.base
		numbers["modifiers"] = inc.modifiers
	if not cut.is_empty():
		numbers["cut_off"] = cut
	if not taken.is_empty():
		numbers["besieged"] = taken
	var involved := [fid]
	for pid in cut:
		var by := String(SiegeRules.cut_off_info(s, pid).besieger)
		if not involved.has(by):
			involved.append(by)
	return _event("income", "income", inc.by_province.keys(), involved, [], "owned_provinces", numbers, text, "income" if cut.is_empty() and taken.is_empty() else "cut_off")


## M3c, in a game with sieges (§9.2): "Stonegate pays you nothing: it is cut off, and its 8 gold goes to the
## Thornmane Clans. You take 8 from besieged Blackwood." for an income_of result ("" when no siege touches it).
## `verb_now` is true for a forecast ("pays", "goes", "take"), false for the turn report ("paid", "went", "took").
static func siege_income_text(s: GameState, fid: String, inc: Dictionary, verb_now: bool = true) -> String:
	if not s.sieges:
		return ""
	var bits := []
	for pid in inc.by_province:
		if inc.modifiers.has(BESIEGED_PREFIX + pid):
			bits.append("You %s %d from besieged %s." % ["take" if verb_now else "took", int(inc.by_province[pid]), _province_name(s, pid)])
		elif SiegeRules.is_cut_off(s, pid):
			var info := SiegeRules.cut_off_info(s, pid)
			bits.append("%s %s you nothing: it is cut off, and its %d gold %s to the %s." % [_province_name(s, pid), "pays" if verb_now else "paid",
				s.find_province(pid).income, "goes" if verb_now else "went", _faction_name(s, String(info.besieger))])
	return " ".join(bits)


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
	var forge := int(inc.modifiers.get(RulerRules.FORGE_TITHE, 0))  # M4-2
	if forge > 0:
		parts.append("%s +%d (%d for each %s)" % [RulerRules.mandate_name(RulerRules.FORGE_TITHE), forge,
			AscensionRules.mandate_value(s, fid, "fort_income", 0), "keep or citadel" if s.sieges else "province with a fort"])
	for key in inc.modifiers:  # M4: the path's income lines (Market Charters, Tithe of Light, ...)
		if String(key).begins_with(AscensionRules.PART_PREFIX):
			parts.append("%s %+d" % [AscensionRules.part_name(String(key)), int(inc.modifiers[key])])
	if parts.is_empty():
		return ""
	return "That includes %s." % " and ".join(parts)


# --- research (M4-1, #66; design/M4_ASCENSION.md §2.2, §7) -----------------------------------------
# Only in a game with paths (GameState.paths): research orders set the target in the orders phase, and the
# research phase, after income and before rulers, gains research and completes the target. The rules are
# AscensionRules'. A game without paths has no research orders and no research events.

## A research order's check in the orders phase: AscensionRules.check_research against the state after
## sacrifices, plus "one per turn" (`given` is the node of a research order this faction already gave).
static func _check_research_order(s: GameState, fid: String, order: ResearchOrder, given: String) -> Dictionary:
	if not given.is_empty() and AscensionRules.has_paths(s):
		return _reject("second_research", "You already gave a research order this turn, for %s. Only one research order counts each turn: choosing another replaces it before you end the turn." % AscensionRules.node_name(given))
	return AscensionRules.check_research(s, fid, order.node_id)


## The research phase (§2.2), for each faction in id order: the pool gains this turn's research (5 for the
## capital, 1 for every other province, as the board stands after captures and Sworn Vassals); then, if the
## target is paid for, it is done and its effects start (AscensionRules.research_step). Events:
##   research_gained  research   what the faction gained, from where. One per faction per turn. Public, so
##                               it never names the target (§3.3). Codex "research_points".
##   research_done    research   a node was researched, with its effect in numbers. Codex: the node's entry.
##   oath_sworn       research   an Oath was sworn (instead of research_done): the side, what closed, the
##                               economy rule now, and the transformation now being researched (§5).
##   transformed      research   (M4-2, instead of research_done) a transformation: the roster change, the new
##                               unit, the province rule and the mandates, in public words; numbers carry
##                               "own_text", the same facts spoken to the faction itself (§9.5).
## Then the transformation's province rules (M4-2, §2.2 step 4, AscensionRules.province_rules_step):
##   wild_spread      research   the Wild Spreads turned a province to forest. Codex "wild_spreads".
##   path_healed      research   Hallowed Land or the Forges healed wounded fighters. One per faction.
static func _research_phase(s: GameState, events: Array) -> void:
	if not AscensionRules.has_paths(s):
		return
	var turn := s.current_turn + 1  # the turn being resolved, as players count it
	for fid in _faction_ids(s):
		var step := AscensionRules.research_step(s, fid, turn)
		events.append(_event("research_gained", "research", [], [fid], [], "research",
			{"gained": step.gained, "rate": step.rate, "parts": step.parts, "done": step.done},
			AscensionRules.gained_text(s, fid, step), "research_points"))
		if not String(step.done).is_empty():
			_research_done_event(s, fid, step, turn, events)
		_province_rules(s, fid, events)


## The event for the node `step` completed: oath_sworn, transformed or research_done (see _research_phase).
static func _research_done_event(s: GameState, fid: String, step: Dictionary, turn: int, events: Array) -> void:
	var nid := String(step.done)
	var numbers := {"node": nid, "cost": step.cost, "kind": AscensionRules.node_kind(nid), "turn": turn,
		"units_changed": int(step.applied.get("units_changed", 0)), "hp_total": int(step.applied.get("hp_total", 0))}
	var codex := String(AscensionRules.node_data(nid).codex)
	if not String(step.sworn).is_empty():
		numbers["branch"] = step.sworn
		numbers["closed"] = AscensionRules.other_branch(fid, String(step.sworn))
		events.append(_event("oath_sworn", "research", [], [fid], [], "oath", numbers,
			AscensionRules.sworn_text(s, fid, nid), codex))
	elif AscensionRules.node_kind(nid) == PathData.TRANSFORMATION:
		var fx := AscensionRules.node_effects(nid)
		numbers["branch"] = String(AscensionRules.node_data(nid).branch)
		numbers["renamed"] = step.applied.get("renamed", {}).duplicate(true)
		numbers["new_unit"] = String(step.applied.get("new_unit", ""))
		numbers["province_rule"] = String(fx.get("province_rule", {}).get("id", ""))
		numbers["opens_mandate"] = String(fx.get("opens_mandate", ""))
		numbers["forswears"] = String(fx.get("forswears", ""))
		numbers["own_text"] = AscensionRules.transformed_text(s, fid, nid, turn, true)
		events.append(_event("transformed", "research", [], [fid], [], "transformation", numbers,
			AscensionRules.transformed_text(s, fid, nid, turn, false), codex))
	else:
		events.append(_event("research_done", "research", [], [fid], [], "researched", numbers,
			AscensionRules.done_text(s, fid, nid, step.applied), codex))


## The transformation's province rules for `fid` in the research phase (M4-2), with their events.
static func _province_rules(s: GameState, fid: String, events: Array) -> void:
	var done := AscensionRules.province_rules_step(s, fid)
	for pick in done.spread:
		events.append(_event("wild_spread", "research", [pick.province], [fid], [], "wild_spreads",
			{"province": pick.province, "from_terrain": pick.from_terrain, "terrain": AscensionRules.FOREST,
				"grown_from": pick.grown_from.duplicate()},
			AscensionRules.wild_spread_text(s, fid, pick), "wild_spreads"))
	var healed: Dictionary = done.healed
	if not healed.is_empty() and int(healed.fighters) > 0:
		events.append(_event("path_healed", "research", healed.provinces.duplicate(), [fid], healed.armies.duplicate(),
			String(healed.rule), {"rule": healed.rule, "amount": healed.amount, "fighters": healed.fighters, "total": healed.total,
				"healed": healed.healed.duplicate(true)},
			AscensionRules.healed_text(s, fid, healed), String(healed.codex)))


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
		desc = "move %s to %s" % ["the " + army_label(s, army) if army else "an army that is not on the map",
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
		if s.sieges and not recruit_at(s, f, order).is_empty() and order.at != RecruitOrder.AT_RULER:
			# M3c: a recruit at a fort names it, and the event is placed there.
			desc += " at %s" % _province_name(s, order.at)
			provinces = [order.at]
			codex = "recruit_at_forts"
		if order.at == RecruitOrder.AT_RULER:
			# Warband Muster: name the ruler and put the event where it stands, if it is on the map.
			codex = "field_recruit"
			var ruler := RulerRules.ruler_army(s, fid)
			var who := RulerRules.current_name(s, fid)
			desc += " with %s" % (who if not who.is_empty() else "the ruler")
			if ruler:
				provinces = [ruler.location]
	elif order is ResearchOrder:
		# M4: name the node (or quote an unknown id).
		var node := AscensionRules.node_name(order.node_id) if not AscensionRules.node_data(order.node_id).is_empty() \
			else "'%s'" % order.node_id
		desc = "research %s" % node
		order_dict = order.to_dict()
		codex = "research_order"
	elif order is FortifyOrder:
		# M3c: "fortify Rivermarch (a palisade)".
		desc = "fortify %s" % _province_name(s, order.province)
		var p := s.find_province(order.province)
		if p != null and p.fort_level < FortData.MAX_BUILT:
			desc += " (%s)" % SiegeRules.fort_phrase(p.fort_level + 1)
		provinces = [order.province] if p != null else []
		order_dict = order.to_dict()
		codex = "fortify"
	elif order is SiegeOrder:
		# M3c: "storm Stonegate", "sally out of Stonegate with the ...".
		order_dict = order.to_dict()
		if order.is_storm():
			desc = "storm %s" % _province_name(s, order.province)
			provinces = [order.province] if s.find_province(order.province) != null else []
			codex = "storm"
		else:
			var army := s.find_army(order.army_id)
			desc = "sally out with %s" % ("the " + army_label(s, army) if army else "an army that is not on the map")
			if army:
				provinces = [army.location]
			armies = [order.army_id]
			codex = "sally"
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
	if not via.is_empty() and String(m.get("road", "")) == "forest_stride":
		# M4-2, a Forest Stride road move (§4.8): an "army_moved" event naming the forest it went through.
		return _event("army_moved", "movement", [m.from, via, m.to], [m.faction], [m.army_id], "road_move",
			{"via": via, "rule": "forest_stride"},
			"The %s moved to %s through the forest of %s (Forest Stride)." % [m.label, _province_name(s, m.to), _province_name(s, via)],
			"forest_stride")
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


## An army's name for the order checks' reasons: its name for life, as the map and the turn report call it
## (TurnReportText.army_name, #55), capitalized when it starts the sentence.
static func _army_name(state: GameState, army: Army, start: bool = false) -> String:
	var name := TurnReportText.army_name(state, army.id, army.owner)
	return RulerRules._cap(name) if start else name


## The record's name for an army, used in every event text instead of its id. The record's event text keeps
## it so recorded games replay byte for byte; the turn report, the map and the order checks call armies by
## their names for life instead (TurnReportText):
##   "Aurel Crown army at Crownkeep (3 units, led by Knight Captain)"
##   "Thornmane Clans army at Wildmoor (1 unit, no commander)"
##   "Thornmane Clans army at Fangridge (Warchief alone)"
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
	if n == 0:
		return "%s alone" % army.commander.type.name if army.commander else "no units"
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


## Display name of a unit type from any faction's roster, for text about orders that may be invalid. M3c: the
## siege engines too, in a game with sieges.
static func _unit_type_name(s: GameState, type_id: String) -> String:
	for f in s.factions:
		var ut := recruitable_type(f, type_id, s)
		if ut:
			return ut.name
	return "an unknown unit type"
