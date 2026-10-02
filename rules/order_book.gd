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

var _orders := {}  # faction id -> Array of orders, in the order given
var _last_dropped: Array = []  # what the last submit() or cancel() removed: [{"order", "code", "reason", "text"}]


## Adds an order for `faction_id` if it is valid against `state` and the orders already given.
## Returns "" when accepted, otherwise the reason it was rejected. A Sacrifice order may make other
## queued orders fail; they are removed, and last_dropped() says which and why.
func submit(state: GameState, faction_id: String, order) -> String:
	_last_dropped = []
	var check := check_order(state, faction_id, order, orders_for(faction_id))
	if not check.is_empty():
		return check.reason
	if not _orders.has(faction_id):
		_orders[faction_id] = []
	_orders[faction_id].append(order)
	if order is SacrificeOrder:
		_last_dropped = _recheck(state, faction_id)
	return ""


## Withdraws the order at `index` in that faction's list. (cancel() also re-checks the rest.)
func remove(faction_id: String, index: int) -> void:
	if _orders.has(faction_id) and index >= 0 and index < _orders[faction_id].size():
		_orders[faction_id].remove_at(index)


## Withdraws the order at `index` and checks the faction's other orders again against `state`, in the
## order given (§2.4: cancelling a sacrifice removes the orders that relied on it). Returns what was
## removed besides the cancelled order: [{"order", "code", "reason", "text"}], where "text" reads
## "Road move to Westwatch removed: you no longer have King's Roads." Also in last_dropped().
func cancel(state: GameState, faction_id: String, index: int) -> Array:
	_last_dropped = []
	remove(faction_id, index)
	_last_dropped = _recheck(state, faction_id)
	return _last_dropped.duplicate()


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
	if order is RecruitOrder:
		var recruits := []
		for o in existing:
			if o is RecruitOrder:
				recruits.append(o)
		recruits.append(order)
		var last: Dictionary = TurnResolver.price_recruits(board, faction_id, recruits).results.back()
		return {} if last.ok else {"code": last.code, "reason": last.reason}
	return {"code": "unknown_order", "reason": "That is not an order this game knows. Orders are moves, recruits and sacrifices."}


## Checks `orders` again in the order given, as submit() would take them one by one, against the state
## with their (first legal) Sacrifice order applied. Returns {"kept": [orders that pass], "dropped":
## [{"order", "code", "reason", "text"}]}. Pure: `state` and `orders` are not changed.
static func recheck(state: GameState, faction_id: String, orders: Array) -> Dictionary:
	var view := RulerRules.state_after_orders(state, faction_id, orders)
	var kept := []
	var dropped := []
	for order in orders:
		var check := check_order(state, faction_id, order, kept, view)
		if check.is_empty():
			kept.append(order)
		else:
			dropped.append({"order": order, "code": check.code, "reason": check.reason,
				"text": dropped_text(state, faction_id, order, check)})
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
		return "Recruit %s at %s" % [unit, TurnResolver._province_name(state, f.capital) if f else "your capital"]
	if order is SacrificeOrder:
		return "Sacrifice for %s" % RulerRules.mandate_name(order.mandate_id)
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
## {"type": "sacrifice", "mandate": id} (M2-6).
static func order_from_dict(data: Dictionary, errors = null):
	match str(data.get("type", "")):
		"move":
			return MoveOrder.new(str(data.get("army", "")), str(data.get("to", "")), str(data.get("via", "")))
		"recruit":
			return RecruitOrder.new(str(data.get("unit_type", "")), str(data.get("at", "")))
		"sacrifice":
			return SacrificeOrder.new(str(data.get("mandate", "")))
	var msg := "Unknown order type '%s'. Orders are 'move', 'recruit' and 'sacrifice'." % str(data.get("type", ""))
	if errors is Array:
		errors.append(msg)
	else:
		push_error(msg)
	return null


## Replaces the faction's orders with what recheck() keeps and returns what it dropped.
func _recheck(state: GameState, faction_id: String) -> Array:
	if not _orders.has(faction_id):
		return []
	var result := recheck(state, faction_id, _orders[faction_id])
	_orders[faction_id] = result.kept
	return result.dropped
