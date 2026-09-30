class_name Forecast
## Forecasts the orders UI shows before a player commits. Every number comes from the same
## TurnResolver functions the turn resolution uses, so a forecast can't disagree with the result
## except where it depends on what the other player does (called out in the text).


## Where and when a move arrives, or why it can't be given.
## `other_orders` are that faction's orders already given this turn (to catch a second move).
## Returns {"ok", "reason", "code", "from", "to", "arrival_turn", "enemy_present", "would_capture", "text"}.
static func move(state: GameState, faction_id: String, order: MoveOrder, other_orders: Array = []) -> Dictionary:
	var ordered := {}
	for o in other_orders:
		if o is MoveOrder:
			ordered[o.army_id] = true
	var check := TurnResolver.check_move(state, faction_id, order, ordered)
	if not check.is_empty():
		return {"ok": false, "code": check.code, "reason": check.reason, "text": check.reason}
	var army := state.find_army(order.army_id)
	var here := state.find_province(army.location)
	var dest := state.find_province(order.to)
	var enemies := []
	for a in state.armies:
		if a.location == dest.id and a.owner != faction_id and not enemies.has(a.owner):
			enemies.append(a.owner)
	enemies.sort()
	var arrival := state.current_turn + 1
	var text := "Army %s moves from %s to %s and is there at the start of turn %d." % [army.id, here.name, dest.name, arrival]
	var would_capture := false
	if not enemies.is_empty():
		var names := []
		for fid in enemies:
			names.append(state.find_faction(fid).faction_name)
		text += " %s has an army there: if it stays, you fight a battle and it defends (defenders win ties). If it moves toward you instead, you meet on the border." % " and ".join(names)
	elif dest.owner != faction_id:
		would_capture = true
		text += " %s is undefended: if no enemy army arrives too, you capture it and gain %d gold per turn." % [dest.name, dest.income]
	return {"ok": true, "code": "", "reason": "", "from": here.id, "to": dest.id, "arrival_turn": arrival,
		"enemy_present": not enemies.is_empty(), "would_capture": would_capture, "text": text}


## Gold cost of one unit of `unit_type_id` for `faction_id`, or -1 if they can't recruit it.
static func recruit_cost(state: GameState, faction_id: String, unit_type_id: String) -> int:
	return TurnResolver.recruit_cost(state, faction_id, unit_type_id)


## Gold left after the given recruit orders, paid in order, plus the income expected at the end of
## the turn if no provinces change hands. Rejected recruits are listed with their reasons.
## Returns {"gold_now", "spent", "gold_after", "income", "gold_next_turn", "results", "text"}.
static func gold_after_recruits(state: GameState, faction_id: String, recruit_orders: Array) -> Dictionary:
	var priced := TurnResolver.price_recruits(state, faction_id, recruit_orders)
	var income: int = TurnResolver.income_of(state, faction_id).total
	var text := "Gold %d, recruits cost %d, leaving %d. Income +%d if no provinces change hands, so %d next turn." % [
		priced.gold_before, priced.spent, priced.gold_after, income, priced.gold_after + income]
	for r in priced.results:
		if not r.ok:
			text += " Not recruited: %s" % r.reason
	return {"gold_now": priced.gold_before, "spent": priced.spent, "gold_after": priced.gold_after,
		"income": income, "gold_next_turn": priced.gold_after + income, "results": priced.results, "text": text}
