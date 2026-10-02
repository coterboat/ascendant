class_name Forecast
## Forecasts the orders UI shows before a player commits. Every number comes from the same
## TurnResolver functions the turn resolution uses, so a forecast can't disagree with the result
## except where it depends on what the other player does (called out in the text).


## Where and when a move arrives, or why it can't be given.
## `other_orders` are that faction's orders already given this turn (to catch a second move).
## Returns {"ok", "reason", "code", "from", "to", "arrival_turn", "enemy_present", "would_capture", "text"}.
## `arrival_turn` is 1-based like every turn number players see (GameSession.turn_number()): an
## order given on turn current_turn + 1 resolves at its end, so the army is there at the start of
## turn current_turn + 2.
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
	var arrival := state.current_turn + 2
	var text := "The %s moves to %s and is there at the start of turn %d." % [TurnResolver.army_label(state, army), dest.name, arrival]
	var would_capture := false
	if not enemies.is_empty():
		var names := []
		for fid in enemies:
			names.append(state.find_faction(fid).faction_name)
		text += " %s has an army there: if it stays, you fight a battle and it defends (%s). If it moves toward you instead, you meet on the border, where nobody gets terrain." % [
			" and ".join(names), defender_ground(dest)]
	elif dest.owner != faction_id:
		would_capture = true
		text += " %s is undefended: if no enemy army arrives too, you capture it and gain %d gold per turn." % [dest.name, dest.income]
	return {"ok": true, "code": "", "reason": "", "from": here.id, "to": dest.id, "arrival_turn": arrival,
		"enemy_present": not enemies.is_empty(), "would_capture": would_capture, "text": text}


## What holding `province` gives its defender in battle (RulesCodex "battle_terrain"), from the same
## AutoBattleResolver numbers the battle uses: "the forest gives it +2 defense".
static func defender_ground(province: Province) -> String:
	var bonus: Dictionary = AutoBattleResolver.TERRAIN.get(province.terrain, {})
	var defense: int = bonus.get("defense", 0)
	var attack: int = bonus.get("attack", 0)
	var parts := []
	if defense > 0:
		parts.append("+%d defense" % defense)
	if attack > 0:
		parts.append("+%d attack" % attack)
	var fort := "its fort gives +%d defense" % AutoBattleResolver.FORT_DEFENSE
	if parts.is_empty():
		var open := "open %s give no terrain bonus" % province.terrain
		return "%s, but %s" % [open, fort] if province.has_fort else open
	var verb := "give" if province.terrain.ends_with("s") else "gives"
	var ground := "the %s %s it %s" % [province.terrain, verb, " and ".join(parts)]
	return "%s, and %s" % [ground, fort] if province.has_fort else ground


## Odds of `faction_id` attacking `province_id` with the armies `army_ids` (RulesCodex "battle_odds"):
## the real AutoBattleResolver fought on fixed internal seeds against the enemy armies there now,
## which defend and get the terrain. Returns {"ok", "text", and when ok: "win_rate", "wins",
## "samples", "label" ("likely win" | "close" | "likely loss"), "reasons"}.
static func battle_odds(state: GameState, faction_id: String, army_ids: Array, province_id: String) -> Dictionary:
	var province := state.find_province(province_id)
	if province == null:
		return {"ok": false, "text": "That is not a province on the map."}
	var by_faction := {faction_id: []}
	for id in army_ids:
		var a := state.find_army(id)
		if a != null and a.owner == faction_id:
			by_faction[faction_id].append(a)
	if by_faction[faction_id].is_empty():
		return {"ok": false, "text": "None of those armies can attack."}
	var defenders := []
	for a in state.armies:
		if a.location == province_id and a.owner != faction_id:
			if not by_faction.has(a.owner):
				by_faction[a.owner] = []
				defenders.append(a.owner)
			by_faction[a.owner].append(a)
	if defenders.is_empty():
		return {"ok": false, "text": "No enemy army is in %s, so there is no battle to forecast." % province.name}
	var fids: Array = by_faction.keys()
	fids.sort()
	var sides := []
	for fid in fids:
		sides.append({"faction": fid, "armies": by_faction[fid]})
	var ctx := {"kind": "province", "defender": defenders[0] if defenders.size() == 1 else "", "province": province,
		"province_ids": [province_id], "state": state}
	var odds := AutoBattleResolver.estimate(sides, ctx, faction_id)
	odds["ok"] = true
	return odds


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
