class_name OrderBook
## Collects each faction's orders for one turn (hotseat: player 1 fills theirs, then player 2).
## submit() checks an order with the same rules code the resolver uses and returns a plain-language
## reason when it is rejected ("" when accepted). Nothing resolves until TurnResolver.resolve() is
## called with orders_by_faction(), so both players' orders are resolved together.
##
## Sacrifice orders (M2-6, design/M2_RULER.md §2.4): at most one per faction per turn. Because the
## sacrifice phase resolves first, every other order is checked against the state with the faction's
## queued sacrifice applied (RulerRules.state_after_orders): a road move or a Muster Grounds price may
## rely on a mandate the ruler is sacrificing for. When the sacrifice is cancelled (cancel()), or a new one
## makes an earlier order fail (a lower ability rank allows fewer recruits with the Ninth Fang), the
## other orders are checked again in the order given and the ones that no longer pass are removed, each
## with a plain reason (dropped(), last_dropped()).
##
## Research orders (M4, design/M4_ASCENSION.md §2.2): at most one per faction per turn. Queuing another
## replaces the queued one (it is reported in last_dropped(), "Research Drillyard replaced: ...").
##
## Forts and sieges (M3c, design/M3C_SIEGES.md §12), only in a game with sieges: a Fortify order is priced with
## the recruits, in the order given, from the same gold, one per faction per turn; a recruit may name a fort
## (`at`), counted against that fort's limit. Storm and sally orders (SiegeOrder) are checked against all the
## faction's queued orders, wherever they come in the list: a storm from the march needs a queued move into the
## fort, a sally needs no move for its army. Queuing a move for an army that sallies drops the sally; removing a
## move, by remove() as well as cancel(), checks the faction's storms and sallies again, and a storm that lost
## its move or a tied sally whose relief move is gone is dropped, each with its reason (last_dropped()). With no
## siege orders queued, remove() behaves exactly as before: it drops nothing and leaves last_dropped() alone.

var _orders := {}  # faction id -> Array of orders, in the order given
var _last_dropped: Array = []  # what the last submit() or cancel() removed: [{"order", "code", "reason", "text"}]
var _state: GameState = null  # M3c: the state of the last submit() or cancel(), for remove()'s siege re-check


## Adds an order for `faction_id` if it is valid against `state` and the orders already given.
## Returns "" when accepted, otherwise the reason it was rejected. A Sacrifice order may make other
## queued orders fail; they are removed, and last_dropped() says which and why.
func submit(state: GameState, faction_id: String, order) -> String:
	_last_dropped = []
	_state = state
	var check := check_order(state, faction_id, order, orders_for(faction_id))
	if not check.is_empty():
		return check.reason
	if not _orders.has(faction_id):
		_orders[faction_id] = []
	if order is ResearchOrder:
		_last_dropped = _replace_research(state, faction_id, order)
	_orders[faction_id].append(order)
	if order is SacrificeOrder:
		_last_dropped = _recheck(state, faction_id)
	elif order is MoveOrder and _has_siege_orders(faction_id):
		_last_dropped = _recheck_sieges(state, faction_id)  # M3c: a sally by an army that now moves is dropped
	return ""


## Withdraws the order at `index` in that faction's list. (cancel() also re-checks the rest.)
## M3c: removing a move while storms or sallies are queued checks them again against `state` (the state of the
## last submit() or cancel() when null) and drops those that no longer pass, with their reasons in
## last_dropped(). Without siege orders nothing else changes.
func remove(faction_id: String, index: int, state: GameState = null) -> void:
	var removed = _remove_at(faction_id, index)
	var board: GameState = state if state != null else _state
	if removed is MoveOrder and board != null and _has_siege_orders(faction_id):
		_last_dropped = _recheck_sieges(board, faction_id)


## Withdraws the order at `index` and checks the faction's other orders again against `state`, in the
## order given (§2.4: cancelling a sacrifice removes the orders that relied on it). Returns what was
## removed besides the cancelled order: [{"order", "code", "reason", "text"}], where "text" reads
## "Road move to Westwatch removed: you no longer have King's Roads." Also in last_dropped().
func cancel(state: GameState, faction_id: String, index: int) -> Array:
	_last_dropped = []
	_state = state
	_remove_at(faction_id, index)
	_last_dropped = _recheck(state, faction_id)
	return _last_dropped.duplicate()


## Removes and returns the order at `index` (null when there is none).
func _remove_at(faction_id: String, index: int):
	if _orders.has(faction_id) and index >= 0 and index < _orders[faction_id].size():
		var order = _orders[faction_id][index]
		_orders[faction_id].remove_at(index)
		return order
	return null


## What the last submit() or cancel() removed besides the order it was about ([] when nothing).
func last_dropped() -> Array:
	return _last_dropped.duplicate()


func orders_for(faction_id: String) -> Array:
	return _orders.get(faction_id, []).duplicate()


## Copy of all orders, keyed by faction id, ready for TurnResolver.resolve().
func orders_by_faction() -> Dictionary:
	var out := {}
	for fid in _orders:
		out[fid] = _orders[fid].duplicate()
	return out


func clear() -> void:
	_orders.clear()
	_last_dropped = []


## {} when `order` may join `existing` (that faction's orders so far, in the order given), otherwise
## {"code", "reason"}. A Sacrifice order is checked against `state` (the start of the turn); every other
## order against `view`, which defaults to RulerRules.state_after_orders(state, faction_id, existing).
static func check_order(state: GameState, faction_id: String, order, existing: Array, view: GameState = null) -> Dictionary:
	if order is SacrificeOrder:
		var prior := RulerRules.queued_sacrifice(existing)
		return RulerRules.sacrifice_check(state, faction_id, order.mandate_id, prior.mandate_id if prior != null else "")
	var board: GameState = view if view != null else RulerRules.state_after_orders(state, faction_id, existing)
	if order is MoveOrder:
		var ordered := {}
		for o in existing:
			if o is MoveOrder:
				ordered[o.army_id] = true
		return TurnResolver.check_move(board, faction_id, order, ordered)
	if order is RecruitOrder or order is FortifyOrder:
		# Recruits and Fortify orders (M3c) share one gold pool, paid in the order given.
		var recruits := []
		for o in existing:
			if o is RecruitOrder or o is FortifyOrder:
				recruits.append(o)
		recruits.append(order)
		var last: Dictionary = TurnResolver.price_recruits(board, faction_id, recruits).results.back()
		return {} if last.ok else {"code": last.code, "reason": last.reason}
	if order is SiegeOrder:
		# M3c: against every queued move and siege order of the faction, wherever it comes in the list.
		var moves := []
		var given := []
		for o in existing:
			if o is MoveOrder:
				moves.append(o)
			elif o is SiegeOrder:
				given.append(o)
		return SiegeRules.check_siege_order(board, faction_id, order, moves, given)
	if order is ResearchOrder:
		# M4: one per turn, but a new one replaces the queued one (submit), so only the rule is checked here.
		return AscensionRules.check_research(board, faction_id, order.node_id)
	return {"code": "unknown_order", "reason": "That is not an order this game knows. Orders are moves, recruits, sacrifices and research."}


## Checks `orders` again in the order given, as submit() would take them one by one, against the state
## with their (first legal) Sacrifice order applied. Returns {"kept": [orders that pass], "dropped":
## [{"order", "code", "reason", "text"}]}. Pure: `state` and `orders` are not changed.
## M3c: storms and sallies are checked after every other order, against all of those that pass, as the
## resolver checks them after every move; they keep their place in the list.
static func recheck(state: GameState, faction_id: String, orders: Array) -> Dictionary:
	var view := RulerRules.state_after_orders(state, faction_id, orders)
	var kept := []
	var dropped := []
	for order in orders:
		if order is SiegeOrder:
			continue
		var check := check_order(state, faction_id, order, kept, view)
		if check.is_empty():
			kept.append(order)
		else:
			dropped.append({"order": order, "code": check.code, "reason": check.reason,
				"text": dropped_text(state, faction_id, order, check)})
	var passed := {}
	for order in orders:
		if not (order is SiegeOrder):
			continue
		var check := check_order(state, faction_id, order, kept + passed.keys(), view)
		if check.is_empty():
			passed[order] = true
		else:
			dropped.append({"order": order, "code": check.code, "reason": check.reason,
				"text": dropped_text(state, faction_id, order, check)})
	if not passed.is_empty():
		kept = orders.filter(func(o): return kept.has(o) or passed.has(o))
	return {"kept": kept, "dropped": dropped}


## The plain line for an order removed by a re-check: what it was, then why. "Road move to Westwatch
## removed: you no longer have King's Roads."
static func dropped_text(state: GameState, faction_id: String, order, check: Dictionary) -> String:
	var why := String(check.get("reason", ""))
	if String(check.get("code", "")) == "no_kings_roads":
		why = "you no longer have %s." % RulerRules.mandate_name(RulerRules.KINGS_ROADS)
	return "%s removed: %s" % [short_text(state, faction_id, order), why]


## An order in a few words, for lists of removed orders: "Road move to Westwatch", "Move to Highcrag",
## "Recruit Knights at Crownkeep", "Recruit Tuskers with the Ninth Fang", "Sacrifice for Royal Armories".
static func short_text(state: GameState, faction_id: String, order) -> String:
	if order is MoveOrder:
		var to := TurnResolver._province_name(state, order.to)
		if order.is_road_move():
			return "Road move to %s through %s" % [to, TurnResolver._province_name(state, order.via)]
		return "Move to %s" % to
	if order is RecruitOrder:
		var unit := TurnResolver._unit_type_name(state, order.unit_type_id)
		if order.is_with_ruler():
			var who := RulerRules.current_name(state, faction_id)
			return "Recruit %s with %s" % [unit, who if not who.is_empty() else "your ruler"]
		var f := state.find_faction(faction_id)
		if state.sieges and not order.at.is_empty():  # M3c: a recruit at a fort
			return "Recruit %s at %s" % [unit, TurnResolver._province_name(state, order.at)]
		return "Recruit %s at %s" % [unit, TurnResolver._province_name(state, f.capital) if f else "your capital"]
	if order is FortifyOrder:  # M3c
		return "Fortify %s" % TurnResolver._province_name(state, order.province)
	if order is SiegeOrder:  # M3c
		if order.is_storm():
			return "Storm of %s" % TurnResolver._province_name(state, order.province)
		var army := state.find_army(order.army_id)
		return "Sally by the %s" % (TurnResolver.army_label(state, army) if army else "army that no longer exists")
	if order is SacrificeOrder:
		return "Sacrifice for %s" % RulerRules.mandate_name(order.mandate_id)
	if order is ResearchOrder:
		return "Research %s" % AscensionRules.node_name(order.node_id)
	return "An unknown order"


## Serializable form of all orders, for saved replays.
func to_dict() -> Dictionary:
	var out := {}
	for fid in _orders:
		var list := []
		for o in _orders[fid]:
			list.append(o.to_dict())
		out[fid] = list
	return out


## Rebuilds an orders_by_faction dictionary from to_dict() output. Unknown order types, a faction's
## orders that are not a list and an order that is not a group of named values (#49) are reported in
## plain language (to `errors` when it is an Array, otherwise push_error) and skipped.
static func orders_from_dict(data: Dictionary, errors = null) -> Dictionary:
	var out := {}
	for fid in data:
		var list := []
		var given = data[fid]
		if given != null and Serial.check(given, TYPE_ARRAY, errors, "the orders for '%s'" % fid):
			for i in given.size():
				if not Serial.check(given[i], TYPE_DICTIONARY, errors, "order %d for '%s'" % [i + 1, fid]):
					continue
				var order = order_from_dict(given[i], errors)
				if order != null:
					list.append(order)
		out[str(fid)] = list
	return out


## Old records without "via" or "at" load as M1 orders (design/M2_RULER.md §9). A sacrifice is
## {"type": "sacrifice", "mandate": id} (M2-6), a research order {"type": "research", "node": id} (M4-1).
static func order_from_dict(data: Dictionary, errors = null):
	match str(data.get("type", "")):
		"move":
			return MoveOrder.new(str(data.get("army", "")), str(data.get("to", "")), str(data.get("via", "")))
		"recruit":
			return RecruitOrder.new(str(data.get("unit_type", "")), str(data.get("at", "")))
		"sacrifice":
			return SacrificeOrder.new(str(data.get("mandate", "")))
		"research":
			return ResearchOrder.new(str(data.get("node", "")))
		"fortify":  # M3c
			return FortifyOrder.new(str(data.get("province", "")))
		"siege":  # M3c
			var action := str(data.get("action", ""))
			var target := str(data.get("province", "")) if action == SiegeOrder.STORM else str(data.get("army", ""))
			return SiegeOrder.new(action, target, str(data.get("with", "")))
	var msg := "Unknown order type '%s'. Orders are 'move', 'recruit', 'sacrifice' and 'research'." % str(data.get("type", ""))
	if errors is Array:
		errors.append(msg)
	else:
		push_error(msg)
	return null


## Removes the faction's queued research order, if any, before `order` replaces it (one per turn, §2.2).
## Returns what it removed, as last_dropped() reports it.
func _replace_research(state: GameState, faction_id: String, order: ResearchOrder) -> Array:
	var out := []
	var kept := []
	for o in _orders.get(faction_id, []):
		if o is ResearchOrder:
			out.append({"order": o, "code": "replaced", "reason": "you chose %s instead." % AscensionRules.node_name(order.node_id),
				"text": "%s replaced: you chose %s instead." % [short_text(state, faction_id, o), AscensionRules.node_name(order.node_id)]})
		else:
			kept.append(o)
	_orders[faction_id] = kept
	return out


## Whether the faction has a storm or sally queued (M3c).
func _has_siege_orders(faction_id: String) -> bool:
	for o in _orders.get(faction_id, []):
		if o is SiegeOrder:
			return true
	return false


## M3c: checks the faction's storms and sallies again against its other queued orders (they keep their place)
## and drops those that no longer pass. Returns what it dropped, as last_dropped() reports it.
func _recheck_sieges(state: GameState, faction_id: String) -> Array:
	var view := RulerRules.state_after_orders(state, faction_id, _orders[faction_id])
	var others: Array = _orders[faction_id].filter(func(o): return not (o is SiegeOrder))
	var passed := []
	var dropped := []
	for order in _orders[faction_id]:
		if not (order is SiegeOrder):
			continue
		var check := check_order(state, faction_id, order, others + passed, view)
		if check.is_empty():
			passed.append(order)
		else:
			dropped.append({"order": order, "code": check.code, "reason": check.reason,
				"text": dropped_text(state, faction_id, order, check)})
	_orders[faction_id] = _orders[faction_id].filter(func(o): return not (o is SiegeOrder) or passed.has(o))
	return dropped


## Replaces the faction's orders with what recheck() keeps and returns what it dropped.
func _recheck(state: GameState, faction_id: String) -> Array:
	if not _orders.has(faction_id):
		return []
	var result := recheck(state, faction_id, _orders[faction_id])
	_orders[faction_id] = result.kept
	return result.dropped
