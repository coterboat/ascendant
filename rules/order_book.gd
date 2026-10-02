class_name OrderBook
## Collects each faction's orders for one turn (hotseat: player 1 fills theirs, then player 2).
## submit() checks an order with the same rules code the resolver uses and returns a plain-language
## reason when it is rejected ("" when accepted). Nothing resolves until TurnResolver.resolve() is
## called with orders_by_faction(), so both players' orders are resolved together.

var _orders := {}  # faction id -> Array of orders, in the order given


## Adds an order for `faction_id` if it is valid against `state` and the orders already given.
## Returns "" when accepted, otherwise the reason it was rejected.
func submit(state: GameState, faction_id: String, order) -> String:
	var existing := orders_for(faction_id)
	if order is MoveOrder:
		var ordered := {}
		for o in existing:
			if o is MoveOrder:
				ordered[o.army_id] = true
		var check := TurnResolver.check_move(state, faction_id, order, ordered)
		if not check.is_empty():
			return check.reason
	elif order is RecruitOrder:
		var recruits := []
		for o in existing:
			if o is RecruitOrder:
				recruits.append(o)
		recruits.append(order)
		var last: Dictionary = TurnResolver.price_recruits(state, faction_id, recruits).results.back()
		if not last.ok:
			return last.reason
	else:
		return "That is not an order this game knows. Orders are moves and recruits."
	if not _orders.has(faction_id):
		_orders[faction_id] = []
	_orders[faction_id].append(order)
	return ""


## Withdraws the order at `index` in that faction's list.
func remove(faction_id: String, index: int) -> void:
	if _orders.has(faction_id) and index >= 0 and index < _orders[faction_id].size():
		_orders[faction_id].remove_at(index)


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


## Serializable form of all orders, for saved replays.
func to_dict() -> Dictionary:
	var out := {}
	for fid in _orders:
		var list := []
		for o in _orders[fid]:
			list.append(o.to_dict())
		out[fid] = list
	return out


## Rebuilds an orders_by_faction dictionary from to_dict() output. Unknown order types are reported
## in plain language (to `errors` when it is an Array, otherwise push_error) and skipped.
static func orders_from_dict(data: Dictionary, errors = null) -> Dictionary:
	var out := {}
	for fid in data:
		var list := []
		for d in data[fid]:
			var order = order_from_dict(d, errors)
			if order != null:
				list.append(order)
		out[str(fid)] = list
	return out


## Old records without "via" or "at" load as M1 orders (design/M2_RULER.md §9).
static func order_from_dict(data: Dictionary, errors = null):
	match str(data.get("type", "")):
		"move":
			return MoveOrder.new(str(data.get("army", "")), str(data.get("to", "")), str(data.get("via", "")))
		"recruit":
			return RecruitOrder.new(str(data.get("unit_type", "")), str(data.get("at", "")))
	var msg := "Unknown order type '%s'. Orders are 'move' and 'recruit'." % str(data.get("type", ""))
	if errors is Array:
		errors.append(msg)
	else:
		push_error(msg)
	return null
