class_name Forecast
## Forecasts the orders UI shows before a player commits. Every number comes from the same
## TurnResolver functions the turn resolution uses, so a forecast can't disagree with the result
## except where it depends on what the other player does (called out in the text).


## Where and when a move arrives, or why it can't be given.
## `other_orders` are that faction's orders already given this turn (to catch a second move).
## Returns {"ok", "reason", "code", "from", "to", "via", "arrival_turn", "enemy_present", "would_capture",
## "text"}. `arrival_turn` is 1-based like every turn number players see (GameSession.turn_number()):
## an order given on turn current_turn + 1 resolves at its end, so the army is there at the start of
## turn current_turn + 2. A road move (King's Roads, `via` set) arrives in the same turn: "moves by the
## King's Roads through Highcrag and is at Westwatch at the start of turn N" (§2.3).
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
	# The army as the map and the turn report name it (TurnReportText.army_title), from where it stands.
	var label := RulerRules._cap(TurnReportText.army_title(state, army, false))
	var text := "%s moves from %s to %s and is there at the start of turn %d." % [label, here.name, dest.name, arrival]
	if order.is_road_move() and TurnResolver.road_rule(state, faction_id, order) == "forest_stride":
		# M4-2, Forest Stride (§4.8): a road move through a forest you own into another forest.
		text = "%s moves through the forest of %s (Forest Stride) and is at %s at the start of turn %d. On the way it never stops and never fights on a border; if an enemy army moves into %s too, you fight it there." % [
			label, state.find_province(order.via).name, dest.name, arrival, dest.name]
	elif order.is_road_move():
		text = "%s moves by the King's Roads through %s and is at %s at the start of turn %d. On the road it never stops and never fights on a border; if an enemy army moves into %s too, you fight it there." % [
			label, state.find_province(order.via).name, dest.name, arrival, dest.name]
	var would_capture := false
	if state.sieges and dest.fort_level > 0:
		return _fort_move(state, faction_id, order, other_orders, army, here, dest, text, arrival)  # M3c: which row of §3.9
	if not enemies.is_empty():
		var names := []
		for fid in enemies:
			names.append(state.find_faction(fid).faction_name)
		if order.is_road_move():
			text += " %s has an army there: if it stays, you fight a battle and it defends (%s)." % [" and ".join(names), defender_ground(dest)]
		else:
			text += " %s has an army there: if it stays, you fight a battle and it defends (%s). If it moves toward you instead, you meet on the border, where nobody gets terrain." % [
				" and ".join(names), defender_ground(dest)]
	elif dest.owner != faction_id:
		would_capture = true
		text += " %s is undefended: if no enemy army arrives too, you capture it and gain %d gold per turn." % [dest.name, dest.income]
		var raid := AscensionRules.capture_gold(state, faction_id, dest)  # M4-2: Raiding Parties
		if int(raid.gold) > 0:
			text = text.trim_suffix(".") + ", and %d gold at once (%s: %s)." % [int(raid.gold),
				AscensionRules.node_name(String(raid.node)), AscensionRules.times_text(int(raid.times))]
	return {"ok": true, "code": "", "reason": "", "from": here.id, "to": dest.id, "via": order.via, "arrival_turn": arrival,
		"enemy_present": not enemies.is_empty(), "would_capture": would_capture, "text": text}


## M3c (§9.2): the move forecast into a fort in a game with sieges says which row of §3.9 it will be, if the other
## side holds: a siege (and how fast the walls drop), a storm (with a storm order queued), the battle through the
## breach, a relief, an empty fort taken whole, or your own fort. The odds come from battle_odds (the same plan).
## The result adds "siege_row": "besiege" | "storm" | "breach" | "relief" | "empty" | "own".
static func _fort_move(state: GameState, fid: String, order: MoveOrder, others: Array, army: Army, here: Province, dest: Province,
		text: String, arrival: int) -> Dictionary:
	var out := {"ok": true, "code": "", "reason": "", "from": here.id, "to": dest.id, "via": order.via, "arrival_turn": arrival,
		"enemy_present": false, "would_capture": false, "text": text, "siege_row": ""}
	var garrison := SiegeRules.garrison(state, dest.id)
	var enemies := SiegeRules.besiegers(state, dest.id).filter(func(a): return a.owner != fid)
	if dest.owner == fid:
		if not enemies.is_empty():
			out.enemy_present = true
			out.siege_row = "relief"
			var tied := 0
			for o in others:
				if o is SiegeOrder and o.is_sally() and o.with_army == army.id:
					tied += 1
			out.text += " It arrives outside the walls as a relief: it meets the %s siege lines there in the open, where nobody gets walls or ground, and it gets no cover." % \
				RulerRules._possessive(_faction_name(state, enemies[0].owner))
			out.text += " %s." % ("%s from the garrison sally to fight beside it, with their cover" % _count(tied, "army", "armies") if tied > 0
				else "Order the garrison to sally with it to fight together")
		else:
			out.siege_row = "own"
			out.text += " If an enemy army arrives there this turn too, you meet outside the walls, where nobody gets walls or ground."
		return out
	if not garrison.is_empty() and dest.walls <= 0:
		out.enemy_present = true
		out.siege_row = "breach"
		out.text += " Its walls are down: you fight its garrison there at once, through the breach, in the open, where nobody gets the ground and the garrison keeps +%d cover." % \
			FortData.COVER_DEFENSE
		return out
	if not garrison.is_empty():
		out.enemy_present = true
		var storm := false
		for o in others:
			if o is SiegeOrder and o.is_storm() and o.province == dest.id:
				storm = true
		if storm:
			out.siege_row = "storm"
			out.text += " With your storm order it attacks the walls at once: the garrison defends with its walls (%d of %d: +%d defense) and its ground." % [
				dest.walls, SiegeRules.walls_max(dest.fort_level), SiegeRules.walls_defense(dest.walls)]
			return out
		out.siege_row = "besiege"
		var fc := siege(state, fid, dest.id, others + [order])
		out.text += " It doesn't fight there: it besieges %s. %s" % [dest.name, String(fc.text)]
		return out
	out.siege_row = "empty"
	out.would_capture = true
	out.text += " Nobody is inside: you take the %s at %s unopposed (walls %d of %d), unless an enemy army arrives there too, and you can recruit there from turn %d." % [
		SiegeRules.level_word(dest.fort_level), dest.name, dest.walls, SiegeRules.walls_max(dest.fort_level), arrival + FortData.CAPTURE_WAIT]
	var raid := AscensionRules.capture_gold(state, fid, dest)  # M4-2: Raiding Parties
	if int(raid.gold) > 0:
		out.text += " Raiding Parties take %d gold at once." % int(raid.gold)
	return out


## Sworn Vassals (§2.3): the neutral province that joins `faction_id` at the end of this turn, from the
## same RulerRules.vassal_picks the capture phase uses. The board is taken as it will stand if the
## moves in `orders` (the viewer's queued orders) all arrive and every other army holds: armies
## capture the empty provinces they move into, and every province with an army in it is out. `viewer`
## is who reads the text ("you" when it is `faction_id`). Returns {"ok", "province" (id or ""),
## "income", "contested_with" ([faction ids]), "text"}; "ok" is false without the mandate.
static func vassal(state: GameState, faction_id: String, orders: Array = [], viewer: String = "") -> Dictionary:
	var f := state.find_faction(faction_id)
	if f == null or not RulerRules.has_mandate(state, faction_id, RulerRules.SWORN_VASSALS):
		return {"ok": false, "province": "", "income": 0, "contested_with": [], "text": "%s does not have Sworn Vassals." % (
			f.faction_name if f else "That faction")}
	var who := "you" if viewer.is_empty() or viewer == faction_id else f.faction_name
	var board := projected_board(state, orders)
	var picks := RulerRules.vassal_picks(state, board.owners, board.occupied)
	if not picks.picks.has(faction_id):
		return {"ok": true, "province": "", "income": 0, "contested_with": [], "text":
			"Sworn Vassals: no neutral province next to %s land is free of armies, so nobody swears fealty to %s this turn." % [
				"your" if who == "you" else RulerRules._possessive(f.faction_name), who]}
	var p := state.find_province(picks.picks[faction_id])
	var contested: Array = picks.contested.get(p.id, [])
	var others := []
	for fid in contested:
		if fid != faction_id:
			others.append(fid)
	if not others.is_empty():
		var names := []
		for fid in others:
			names.append(state.find_faction(fid).faction_name)
		return {"ok": true, "province": p.id, "income": p.income, "contested_with": others, "text":
			"Sworn Vassals: %s (%d gold) would swear fealty to %s, but the %s Sworn Vassals seeks it too, so it joins nobody this turn unless that changes." % [
				p.name, p.income, who, " and ".join(names.map(func(n): return RulerRules._possessive(n)))]}
	return {"ok": true, "province": p.id, "income": p.income, "contested_with": [], "text":
		"Sworn Vassals: %s (%d gold) swears fealty to %s at the end of this turn, unless an army ends the turn there." % [p.name, p.income, who]}


## The board after this turn's captures if the moves in `orders` arrive and every other army holds
## (the vassal forecast's assumption): {"owners": {province id: owner}, "occupied": {id: true}}. A
## province whose armies all belong to one faction becomes that faction's, as in the capture phase.
static func projected_board(state: GameState, orders: Array = []) -> Dictionary:
	var dest := {}
	for o in orders:
		if o is MoveOrder and state.find_army(o.army_id) != null:
			dest[o.army_id] = o.to
	var owners := {}
	for p in state.provinces:
		owners[p.id] = p.owner
	var factions_at := {}  # province id -> {faction id: true} after the projected moves
	for a in state.armies:
		var at: String = dest.get(a.id, a.location)
		if not factions_at.has(at):
			factions_at[at] = {}
		factions_at[at][a.owner] = true
	var occupied := {}
	for pid in factions_at:
		occupied[pid] = true
		if factions_at[pid].size() == 1:
			owners[pid] = factions_at[pid].keys()[0]
	return {"owners": owners, "occupied": occupied}


## What holding `province` gives its defender in battle (RulesCodex "battle_terrain"), from the same
## AutoBattleResolver numbers the battle uses: "the forest gives it +2 defense".
static func defender_ground(province: Province) -> String:
	if province.fort_level > 0:
		return _fort_ground(province)  # M3c: walls instead of the flat fort bonus
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


## M3c (§4.1): what a fort's ground gives in a game with sieges: its terrain and walls only to a stormed garrison.
## "the hills give it +1 defense and +1 attack, and its walls (6 of 6) +4 defense, but only if stormed".
static func _fort_ground(province: Province) -> String:
	var bonus: Dictionary = AutoBattleResolver.TERRAIN.get(province.terrain, {})
	var parts := []
	if int(bonus.get("defense", 0)) > 0:
		parts.append("+%d defense" % int(bonus.defense))
	if int(bonus.get("attack", 0)) > 0:
		parts.append("+%d attack" % int(bonus.attack))
	var top := SiegeRules.walls_max(province.fort_level)
	var walls := "its walls (%d of %d) +%d defense" % [province.walls, top, SiegeRules.walls_defense(province.walls)] if province.walls > 0 \
		else "its walls are down"
	if parts.is_empty():
		return "open %s give no terrain bonus, and %s, but only if stormed" % [province.terrain, walls] if province.walls > 0 \
			else "open %s give no terrain bonus, and %s" % [province.terrain, walls]
	var verb := "give" if province.terrain.ends_with("s") else "gives"
	if province.walls <= 0:
		return "the %s %s it %s only in a storm, and %s" % [province.terrain, verb, " and ".join(parts), walls]
	return "the %s %s it %s, and %s, but only if stormed" % [province.terrain, verb, " and ".join(parts), walls]


## Odds of `faction_id` attacking `province_id` with the armies `army_ids` (RulesCodex "battle_odds"):
## the real AutoBattleResolver fought on fixed internal seeds against the enemy armies there now,
## which defend and get the terrain. Returns {"ok", "text", and when ok: "win_rate", "wins",
## "samples", "label" ("likely win" | "close" | "likely loss"), "reasons"}.
## In a game with rulers (M2-2) the battle reads `state`, so every side's mandates count, a ruler's army
## among `army_ids` (or among the defenders) fights in its rank, and the Great Thornmane's Dread works:
## the sacrifice preview (sacrifice) fights its queued attacks again on the state after the sacrifice.
## M3c (S-2): at a fort in a game with sieges the odds fight SiegeRules.next_battle's plan (_plan_odds), so they
## read the walls and the open-battle rule; where no battle happens (the armies would besiege) "ok" is false and
## "code" is "siege".
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
	if state.sieges and province.fort_level > 0:
		# M3c (§9.2): at a fort the battle is whatever SiegeRules.next_battle plans, fought as a chain on each seed.
		var moves := []
		for a in by_faction[faction_id]:
			if a.location != province_id:
				moves.append(MoveOrder.new(a.id, province_id))
		var odds := _plan_odds(state, faction_id, province_id, moves, {"storms": {}, "sallies": {}})
		if not odds.ok and odds.get("siege", false):
			odds["code"] = "siege"
			odds["text"] = "No battle this turn: the walls of %s stand and a garrison is inside, so your armies besiege it instead of fighting. Order a storm to attack the walls." % province.name
		return odds
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


## The recruit forecast for one `unit_type_id` (M4-2, §9.4): its price and the hp it arrives with, from the
## same TurnResolver.price_recruits the recruitment phase pays with (Blood Levy: a quarter off the price and
## a quarter of its hp missing). `orders` are the faction's queued orders (a queued sacrifice counts).
## Returns {"ok", "reason", "unit_type", "name", "price", "price_text", "hp", "max_hp", "text"}.
static func recruit(state: GameState, faction_id: String, unit_type_id: String, orders: Array = []) -> Dictionary:
	var view := RulerRules.state_after_orders(state, faction_id, orders)
	var f := view.find_faction(faction_id)
	var ut: UnitType = TurnResolver.recruitable_type(f, unit_type_id) if f else null
	if ut == null:
		return {"ok": false, "reason": "That is not a unit you can recruit.", "text": "That is not a unit you can recruit."}
	var priced := TurnResolver.price_recruits(view, faction_id, [RecruitOrder.new(unit_type_id)])
	var r: Dictionary = priced.results[0]
	var max_hp := int(RulerRules.unit_stats(view, faction_id, unit_type_id).hp)
	var hp := AscensionRules.arrival_hp(view, faction_id, ut, max_hp)
	var text := "%s: %s, arriving with %d of %d hit points." % [ut.name, RulerRules.price_text(view, faction_id, ut), hp, max_hp]
	if hp < max_hp:
		text = "%s: %s. %s" % [ut.name, RulerRules.price_text(view, faction_id, ut),
			AscensionRules.arrival_text(ut, hp, max_hp, AscensionRules.blood_levy_divisor(view, faction_id))]
	return {"ok": bool(r.ok), "reason": String(r.get("reason", "")), "unit_type": ut.id, "name": ut.name,
		"price": RulerRules.recruit_price(view, faction_id, ut), "price_text": RulerRules.price_text(view, faction_id, ut),
		"hp": hp, "max_hp": max_hp, "text": text}


## Gold left after the given recruit orders, paid in order, plus the income expected at the end of
## the turn if no provinces change hands. Rejected recruits are listed with their reasons.
## Prices are the recruitment phase's (Muster Grounds included) and the income is the income phase's
## (Heavy Tithes and Royal Court included). `move_orders` may hold the faction's queued moves: Royal
## Court then counts where the ruler ends the turn (in a province you own now).
## Returns {"gold_now", "spent", "gold_after", "income", "gold_next_turn", "results", "text"}.
static func gold_after_recruits(state: GameState, faction_id: String, recruit_orders: Array, move_orders: Array = []) -> Dictionary:
	var priced := TurnResolver.price_recruits(state, faction_id, recruit_orders)
	var inc := TurnResolver.income_of(state, faction_id, ruler_destination(state, faction_id, move_orders))
	var income: int = inc.total
	var text := "Gold %d, recruits cost %d, leaving %d. Income +%d if no provinces change hands, so %d next turn." % [
		priced.gold_before, priced.spent, priced.gold_after, income, priced.gold_after + income]
	if state.sieges:
		# M3c (§9.2): the gold forecast names cut-off and besieged provinces, on both sides.
		for part in [TurnResolver.income_modifiers_text(state, faction_id, inc, "ends the turn"), TurnResolver.siege_income_text(state, faction_id, inc)]:
			if not String(part).is_empty():
				text += " %s" % part
	elif not inc.modifiers.is_empty():
		text += " %s" % TurnResolver.income_modifiers_text(state, faction_id, inc, "ends the turn")
	for r in priced.results:
		if not r.ok:
			text += " Not recruited: %s" % r.reason
	return {"gold_now": priced.gold_before, "spent": priced.spent, "gold_after": priced.gold_after,
		"income": income, "gold_next_turn": priced.gold_after + income, "results": priced.results, "text": text}


## {faction id: province id} for the faction's ruler when one of `move_orders` moves its army ({}
## otherwise): where the ruler ends the turn, for Royal Court in an income forecast.
static func ruler_destination(state: GameState, faction_id: String, move_orders: Array) -> Dictionary:
	var army := RulerRules.ruler_army(state, faction_id)
	if army == null:
		return {}
	for o in move_orders:
		if o is MoveOrder and o.army_id == army.id:
			return {faction_id: o.to}
	return {}


# --- mid-game sacrifice (M2-6, #34; design/M2_RULER.md §2.4) -----------------------------------------
# The sacrifice dialog's preview. "after" is read from the same copy the sacrifice phase and the order
# checks use (RulerRules.with_sacrifice), so the preview's numbers are the ones the turn resolves with.

## A faction's own numbers this turn on `state`: what the sacrifice preview shows before → after, and
## what its tests compare with the resolved turn. `orders` are the faction's queued orders (Royal Court
## counts where the ruler ends the turn). Returns {"kept_power", "mandates", "ruler_alive", "ruler"
## ({} without a living ruler on the map, otherwise "name", "hp", "max_hp", "attack", "defense",
## "morale", "ability_name", "ability_rank", "ability_value", "ability_effect"), "units" ({unit type id:
## {"name", "hp", "attack", "defense", "cost"}}, the roster and the commander with mandates and prices),
## "unit_hp" ({army id: [current hp of each regular unit]}), "income" (what the income phase pays this
## turn if no provinces change hands), "field_recruits" (Warband Muster's limit)}.
static func faction_numbers(state: GameState, faction_id: String, orders: Array = []) -> Dictionary:
	var f := state.find_faction(faction_id)
	if f == null:
		return {}
	var ruler := {}
	var unit := RulerRules.ruler_unit(state, faction_id)
	if RulerRules.has_living_ruler(state, faction_id) and unit != null:
		var s := RulerRules.ruler_stats(f.ruler_type, f.kept_power, f.ruler_generation)
		ruler = {"name": s.name, "hp": unit.current_hp, "max_hp": unit.type.hp, "attack": unit.type.attack,
			"defense": unit.type.defense, "morale": s.morale, "ability_name": s.ability_name, "ability_rank": s.ability_rank,
			"ability_value": s.ability_value, "ability_effect": RulerRules.ability_effect(f.ruler_type, s.ability_rank)}
	var units := {}
	var types: Array = f.unit_types.duplicate()
	if f.commander_type != null:
		types.append(f.commander_type)
	for ut in types:
		var us := RulerRules.unit_stats(state, faction_id, ut.id)
		units[ut.id] = {"name": us.name, "hp": us.hp, "attack": us.attack, "defense": us.defense, "cost": us.cost}
	var unit_hp := {}
	for a in state.armies:
		if a.owner == faction_id and not a.units.is_empty():
			unit_hp[a.id] = a.units.map(func(u): return u.current_hp)
	var income := TurnResolver.income_of(state, faction_id, ruler_destination(state, faction_id, orders))
	return {"kept_power": f.kept_power if f.has_ruler() else 0, "mandates": f.mandates.duplicate(),
		"ruler_alive": not ruler.is_empty(), "ruler": ruler, "units": units, "unit_hp": unit_hp, "income": int(income.total),
		"field_recruits": RulerRules.field_recruit_limit(state, faction_id)}


## Every mandate on `faction_id`'s list as the sacrifice dialog lists it: [{"mandate", "name", "cost"
## (by sacrifice), "price", "effect", "owned", "ok", "code", "reason"}], in the build screen's order.
## `orders` are the faction's queued orders: a queued Sacrifice order makes every other one wait a turn.
static func sacrifice_options(state: GameState, faction_id: String, orders: Array = []) -> Array:
	var queued := RulerRules.queued_sacrifice(orders)
	var already: String = queued.mandate_id if queued != null else ""
	var out := []
	for mid in RulerRules.available_mandates(faction_id, state):  # M4-2: plus the mandates a transformation opened
		var check := RulerRules.sacrifice_check(state, faction_id, mid, already if mid != already else "")
		if mid == already:
			check = {"code": "queued", "reason": "Queued this turn. Cancel the order in your orders list to choose another mandate."}
		out.append({"mandate": mid, "name": RulerRules.mandate_name(mid), "cost": RulerRules.sacrifice_cost(mid),
			"price": RulerRules.mandate_cost(mid), "effect": String(RulerRules.mandate_data(mid).get("effect", "")),
			"owned": RulerRules.has_mandate(state, faction_id, mid), "ok": check.is_empty(),
			"code": String(check.get("code", "")), "reason": String(check.get("reason", ""))})
	return out


## The sacrifice dialog's preview (§2.4): what sacrificing for `mandate_id` changes in `faction_id`'s own
## numbers this turn, before → after. `orders` are the faction's other queued orders (a queued Sacrifice
## order among them is left out: the preview stands in for it). "before" is faction_numbers on `state`,
## "after" on RulerRules.with_sacrifice, the copy the sacrifice phase and the order checks use, so the
## after numbers are what the turn resolves with. Returns {"ok", "code", "reason", "mandate", "name",
## "cost", "price", "premium", "effect", "before", "after", "rows": [{"key", "label", "before", "after",
## "codex", "breakdown"}], "effects": [plain lines for what has no number], "odds": [{"province", "name",
## "before", "after"}] (every queued attack fought again), "dropped": [queued orders it would remove,
## as plain lines], "text"}. Illegal: "ok" false, with the rules' "code" and "reason".
static func sacrifice(state: GameState, faction_id: String, mandate_id: String, orders: Array = []) -> Dictionary:
	var others := orders.filter(func(o): return not (o is SacrificeOrder))
	var md := RulerRules.mandate_data(mandate_id)
	var out := {"ok": false, "code": "", "reason": "", "mandate": mandate_id, "name": RulerRules.mandate_name(mandate_id),
		"cost": RulerRules.sacrifice_cost(mandate_id), "price": RulerRules.mandate_cost(mandate_id),
		"premium": MandateData.SACRIFICE_PREMIUM, "effect": String(md.get("effect", "")), "before": {}, "after": {},
		"rows": [], "effects": [], "odds": [], "dropped": [], "text": ""}
	var check := RulerRules.sacrifice_check(state, faction_id, mandate_id)
	if not check.is_empty():
		out.code = check.code
		out.reason = check.reason
		out.text = check.reason
		return out
	var after_state := RulerRules.with_sacrifice(state, faction_id, mandate_id)
	var before := faction_numbers(state, faction_id, others)
	var after := faction_numbers(after_state, faction_id, others)
	out.ok = true
	out.before = before
	out.after = after
	out.rows = _sacrifice_rows(after_state, faction_id, mandate_id, before, after)
	out.effects = _sacrifice_effects(after_state, faction_id, mandate_id, others)
	out.odds = _sacrifice_odds(state, after_state, faction_id, others)
	for d in OrderBook.recheck(state, faction_id, others + [SacrificeOrder.new(mandate_id)]).dropped:
		out.dropped.append(String(d.text).replace(" removed: ", " would be removed: "))
	out.text = "%s gives up %d power for %s (%d, +%d for a mid-game sacrifice): kept power %d → %d. It happens first in the turn, so it already counts in this turn's moves, battles, recruits and income." % [
		RulerRules._cap(RulerRules.current_name(state, faction_id)), out.cost, out.name, out.price, out.premium,
		int(before.kept_power), int(after.kept_power)]
	return out


## What a mandate does for `faction_id` right now, in plain words (§7.1: every mandate name says what it
## changes for you), from the rules the turn uses. For a mandate the faction doesn't own yet, pass the
## state after the sacrifice that would buy it. `orders` are its queued orders (Sworn Vassals' forecast);
## `viewer` is who reads it: "you" when it is `faction_id` (or ""), the faction's name otherwise.
static func mandate_now(state: GameState, faction_id: String, mandate_id: String, orders: Array = [], viewer: String = "") -> String:
	var f := state.find_faction(faction_id)
	var md := RulerRules.mandate_data(mandate_id)
	if f == null or md.is_empty():
		return ""
	var own := viewer.is_empty() or viewer == faction_id
	var lead := "For you now" if own else "For the %s now" % f.faction_name
	var their := "your" if own else "its"
	if md.has("units"):
		var parts := []
		for ut in f.unit_types:
			var us := RulerRules.unit_stats(state, faction_id, ut.id)
			var bits := []
			for stat in ["attack", "defense", "hp"]:
				if md.units.has(stat):
					bits.append("%s %d" % [String(RulerRules.UNIT_BONUS_WORDS[stat]), int(us[stat])])
			parts.append("%s %s" % [ut.name, " and ".join(bits)])
		return "%s: %s." % [lead, "; ".join(parts)]
	if md.has("recruit_divisor"):
		var prices := []
		var types: Array = f.unit_types.duplicate()
		if f.commander_type != null:
			types.append(f.commander_type)
		for ut in types:
			prices.append("%s %d" % [ut.name, RulerRules.recruit_price(state, faction_id, ut)])
		return "%s, recruit prices in gold: %s." % [lead, ", ".join(prices)]
	match mandate_id:
		RulerRules.HEAVY_TITHES:
			var owned := 0
			for p in state.provinces:
				if p.owner == faction_id:
					owned += 1
			return "%s: +%d gold per turn, %d from each of %s %s." % [lead, owned * RulerRules.TITHE_GOLD,
				RulerRules.TITHE_GOLD, their, _count(owned, "province")]
		RulerRules.SWORN_VASSALS:
			return vassal(state, faction_id, orders, viewer).text
		RulerRules.KINGS_ROADS:
			var reach := road_reach(state, faction_id)
			if reach.armies == 0:
				return "%s: no army of %s has two of %s provinces in a row ahead of it, so no road move is open this turn." % [
					lead, "yours" if own else "its", their]
			return "%s: %s of %s can reach %s two steps away by road this turn." % [lead,
				_count(reach.armies, "army", "armies"), "yours" if own else "its", _count(reach.provinces, "province")]
		RulerRules.HYMN_OF_DAWN:  # M4-2: the mandates a transformation opens
			var heal := AscensionRules.heal_targets(state, faction_id)
			if heal.is_empty():
				return "%s: it works once %s people have become the Celestial Host." % [lead, their]
			return "%s: Hallowed Land heals %d hit points a turn; this turn %s of %s heal %d in all, if they hold." % [lead,
				int(heal.amount), _count(int(heal.fighters), "wounded fighter"), "yours" if own else "its", int(heal.total)]
		RulerRules.FORGE_TITHE:
			var forts := 0
			var gold := 0
			for p in state.provinces:
				if p.owner == faction_id and RulerRules.forge_tithe_counts(state, p):  # M3c: keeps and citadels with sieges
					forts += 1
					for m in RulerRules.province_income_parts(state, p.id).mods:
						if m.key == RulerRules.FORGE_TITHE:
							gold += int(m.value)
			return "%s: +%d gold per turn from %s %s." % [lead, gold, their, _count(forts, "fort")]
		RulerRules.DEEP_ROOTS:
			var picks := AscensionRules.wild_spread_picks(state, faction_id)
			if picks.is_empty():
				return "%s: no province of %s can grow into forest this turn." % [lead, "yours" if own else "its"]
			return "%s: the Wild Spreads grows %s this turn." % [lead, RulerRules._and_list(picks.map(func(p): return String(p.name)))]
	return "%s: it works in every battle %s fighters are in." % [lead, their]


## King's Roads this turn: how many of `faction_id`'s armies can make a road move, and to how many
## provinces in all: {"armies", "provinces"} (RulerRules.road_destinations for each army).
static func road_reach(state: GameState, faction_id: String) -> Dictionary:
	var armies := 0
	var provinces := {}
	for a in state.armies:
		if a.owner != faction_id:
			continue
		var dests := RulerRules.road_destinations(state, faction_id, a.id)
		if not dests.is_empty():
			armies += 1
			for pid in dests:
				provinces[pid] = true
	return {"armies": armies, "provinces": provinces.size()}


## The preview's rows: the ruler (always), then every unit stat, existing units' hit points, price,
## income and Warband Muster limit the sacrifice changes. Each row carries the after-state's breakdown,
## the numbers behind its texts ("before_value", "after_value") and whether higher is better for you.
static func _sacrifice_rows(after_state: GameState, faction_id: String, mandate_id: String, before: Dictionary, after: Dictionary) -> Array:
	var rows := []
	var entry := String(RulerRules.mandate_data(mandate_id).get("codex", "mandates"))  # the mandate's codex entry
	rows.append(_row("kept_power", "Kept power", str(before.kept_power), str(after.kept_power), "kept_power",
		Breakdown.kept_power(after_state, faction_id), before.kept_power, after.kept_power))
	var rb: Dictionary = before.ruler
	var ra: Dictionary = after.ruler
	rows.append(_row("ruler_hp", "Hit points", "%d of %d" % [rb.hp, rb.max_hp], "%d of %d" % [ra.hp, ra.max_hp], "ruler_power",
		Breakdown.ruler_stat(after_state, faction_id, "hp"), rb.max_hp, ra.max_hp))
	rows.append(_row("ruler_attack", "Attack", str(rb.attack), str(ra.attack), "ruler_power",
		Breakdown.ruler_stat(after_state, faction_id, "attack"), rb.attack, ra.attack))
	rows.append(_row("ruler_defense", "Defense", str(rb.defense), str(ra.defense), "ruler_power",
		Breakdown.ruler_stat(after_state, faction_id, "defense"), rb.defense, ra.defense))
	rows.append(_row("ability", String(ra.ability_name), "rank %d (%s)" % [rb.ability_rank, rb.ability_effect],
		"rank %d (%s)" % [ra.ability_rank, ra.ability_effect], "ability_rank", Breakdown.ability_rank(after_state, faction_id),
		rb.ability_rank, ra.ability_rank))
	var ids: Array = before.units.keys()
	for tid in ids:
		var ub: Dictionary = before.units[tid]
		var ua: Dictionary = after.units.get(tid, ub)
		var was := []
		var now := []
		var first := ""
		var sum_before := 0
		var sum_after := 0
		for stat in ["hp", "attack", "defense"]:
			if int(ub[stat]) != int(ua[stat]):
				was.append("%s %d" % [String(RulerRules.UNIT_BONUS_WORDS[stat]), int(ub[stat])])
				now.append("%s %d" % [String(RulerRules.UNIT_BONUS_WORDS[stat]), int(ua[stat])])
				sum_before += int(ub[stat])
				sum_after += int(ua[stat])
				if first.is_empty():
					first = stat
		if not was.is_empty():
			rows.append(_row("unit_" + String(tid), String(ua.name), ", ".join(was), ", ".join(now), entry,
				Breakdown.unit_stat(after_state, faction_id, String(tid), first), sum_before, sum_after))
	var hp_before := 0
	var hp_after := 0
	var count := 0
	for aid in before.unit_hp:
		for hp in before.unit_hp[aid]:
			hp_before += int(hp)
			count += 1
		for hp in after.unit_hp.get(aid, []):
			hp_after += int(hp)
	if hp_after != hp_before:
		rows.append(_row("unit_hit_points", "Hit points of your %s on the map" % _count(count, "regular unit"),
			"%d in all" % hp_before, "%d in all" % hp_after, entry,
			Breakdown.sacrifice_unit_hp(RulerRules.mandate_name(mandate_id), hp_before, hp_after, count), hp_before, hp_after))
	for tid in ids:
		var cb := int(before.units[tid].cost)
		var ca := int(after.units.get(tid, before.units[tid]).cost)
		if cb != ca:
			rows.append(_row("price_" + String(tid), "Price of %s" % String(before.units[tid].name), "%d gold" % cb, "%d gold" % ca,
				entry, Breakdown.unit_stat(after_state, faction_id, String(tid), "cost"), cb, ca, false))
	if int(before.income) != int(after.income):
		rows.append(_row("income", "Income this turn", "+%d gold" % int(before.income), "+%d gold" % int(after.income), "income",
			Breakdown.income(after_state, faction_id), before.income, after.income))
	if int(before.field_recruits) != int(after.field_recruits):
		rows.append(_row("field_recruits", "Recruits with %s" % String(ra.name),
			"%s per turn" % _count(int(before.field_recruits), "unit"),
			"%s per turn" % _count(int(after.field_recruits), "unit"), "field_recruit",
			Breakdown.ability_rank(after_state, faction_id), before.field_recruits, after.field_recruits))
	return rows


## Lines for what the mandate changes that has no number on its own: road moves, the vassal that will
## join, battle effects, and the two rules every sacrifice follows.
static func _sacrifice_effects(after_state: GameState, faction_id: String, mandate_id: String, orders: Array) -> Array:
	var name := RulerRules.mandate_name(mandate_id)
	var area := String(RulerRules.mandate_data(mandate_id).get("area", ""))
	var out := []
	match mandate_id:
		RulerRules.KINGS_ROADS:
			var reach := road_reach(after_state, faction_id)
			if reach.armies == 0:
				out.append("%s works from this turn on, but right now no army of yours has two of your provinces in a row ahead of it." % name)
			else:
				out.append("%s opens road moves at once: %s of yours can reach %s two steps away this turn." % [name,
					_count(reach.armies, "army", "armies"), _count(reach.provinces, "province")])
		RulerRules.SWORN_VASSALS:
			out.append(vassal(after_state, faction_id, orders).text)
		_:
			if area == "battle":
				out.append("%s counts in this turn's battles too: %s" % [name, String(RulerRules.mandate_data(mandate_id).get("effect", ""))])
	out.append("The ruler's current hit points drop by as much as its maximum, never below 1, and its ability works at the new rank from this turn on.")
	out.append("%s stays for good, even if the ruler dies." % name)
	return out


## Every queued attack (a move into a province with an enemy army in it now), fought again with the
## sacrifice: [{"province", "name", "before", "after", "before_rate", "after_rate"}], by province id.
static func _sacrifice_odds(state: GameState, after_state: GameState, faction_id: String, orders: Array) -> Array:
	var by_dest := {}
	for o in orders:
		if o is MoveOrder and state.find_army(o.army_id) != null:
			if not by_dest.has(o.to):
				by_dest[o.to] = []
			by_dest[o.to].append(o.army_id)
	var dests: Array = by_dest.keys()
	dests.sort()
	var out := []
	for pid in dests:
		var ids: Array = by_dest[pid]
		ids.sort()
		var b := battle_odds(state, faction_id, ids, pid)
		if not b.get("ok", false):
			continue
		var a := battle_odds(after_state, faction_id, ids, pid)
		out.append({"province": pid, "name": state.find_province(pid).name,
			"before": "%s (won %d of %d)" % [b.label, b.wins, b.samples],
			"after": "%s (won %d of %d)" % [a.get("label", ""), a.get("wins", 0), a.get("samples", 0)],
			"before_rate": b.win_rate, "after_rate": a.get("win_rate", 0.0)})
	return out


# --- research (M4-1, #66; design/M4_ASCENSION.md §2.3) ---------------------------------------------

## The research forecast: when a node is done, from the same AscensionRules functions the research phase
## uses. The node is `node_id` ("if researched next", for every card of the panel) or, without it, the
## target the queued ResearchOrder in `orders` sets, or else the faction's current target. Returns {"ok",
## "code", "reason", "rate", "rate_parts", "rate_text", "pool", "target", "name", "cost", "eta" (turns,
## this one counting as 1; -1 if never at this rate), "done_turn" (the 1-based turn it is done at the end
## of; it works from the next), "carry" (research left over then), "then" (for an Oath: {"node", "name",
## "cost", "eta", "done_turn"} of its transformation, "about", because the rate can change), "text"}.
## With no target, "ok" is true, "target" "" and "text" says what is waiting (or "Path complete").
## Forecast equals result: when no province changes hands, the node is done at the end of done_turn.
## The target is private (§3.3): only show this to its own faction.
static func research(state: GameState, faction_id: String, orders: Array = [], node_id: String = "") -> Dictionary:
	var out := {"ok": false, "code": "", "reason": "", "rate": 0, "rate_parts": [], "rate_text": "", "pool": 0, "target": "",
		"name": "", "cost": 0, "eta": 0, "done_turn": 0, "carry": 0, "then": {}, "text": ""}
	var f := state.find_faction(faction_id)
	if f == null or not AscensionRules.has_paths(state):
		var no := AscensionRules.node_state(state, faction_id, node_id)
		out.code = no.code
		out.reason = no.reason
		out.text = no.reason
		return out
	var view := RulerRules.state_after_orders(state, faction_id, orders)
	var rate := AscensionRules.research_rate(view, faction_id)
	var pool := AscensionRules.research_points(view, faction_id)
	var per_turn := int(rate.rate)
	out.rate = per_turn
	out.rate_parts = rate.parts.duplicate(true)
	out.rate_text = rate.text
	out.pool = pool
	var target := node_id
	if target.is_empty():
		var queued := AscensionRules.queued_research(orders)
		if queued != null and AscensionRules.check_research(view, faction_id, queued.node_id).is_empty():
			target = queued.node_id
		else:
			target = AscensionRules.research_target(view, faction_id)
	if target.is_empty():
		out.ok = true
		if AscensionRules.path_complete(view, faction_id):
			out.text = "Path complete: everything on your path is researched or closed. Research keeps saving up (%d now, %d a turn)." % [pool, per_turn]
		else:
			out.text = "Choose what to research: %d research is waiting, and you gain %d a turn (%s)." % [pool, per_turn, rate.short]
		return out
	var check := AscensionRules.check_research(view, faction_id, target)
	out.target = target
	out.name = AscensionRules.node_name(target)
	out.cost = AscensionRules.node_cost(target)
	if not check.is_empty():
		out.code = check.code
		out.reason = check.reason
		out.text = check.reason
		return out
	var cost := int(out.cost)
	var n := AscensionRules.eta(cost, pool, per_turn)
	out.ok = true
	out.eta = n
	var head := "%s: %d of %d research." % [out.name, pool, cost] if pool < cost \
		else "%s: %d research, and you have %d saved." % [out.name, cost, pool]
	var gain := "You gain %d a turn (%s)" % [per_turn, rate.short]
	if n < 0:
		out.done_turn = -1
		out.text = "%s %s, so at this pace it is never done. Hold or retake your capital to research again." % [head, gain]
		return out
	out.done_turn = view.current_turn + n
	out.carry = pool + per_turn * n - cost
	var when := "this turn" if n == 1 else "turn %d, in %s" % [out.done_turn, _count(n, "turn")]
	out.text = "%s %s, so it is done at the end of %s. From turn %d, %s. Capturing or losing a province changes the pace by %d a turn." % [
		head, gain, when, out.done_turn + 1, AscensionRules.effect_preview(view, faction_id, target), int(PathData.RESEARCH.province)]
	if AscensionRules.is_oath(target):
		var side := String(AscensionRules.node_data(target).branch)
		var next := String(AscensionRules.branch_data(side).get("transformation", ""))
		var m := AscensionRules.eta(AscensionRules.node_cost(next), int(out.carry), per_turn)
		out.then = {"node": next, "name": AscensionRules.node_name(next), "cost": AscensionRules.node_cost(next),
			"eta": n + m if m > 0 else -1, "done_turn": out.done_turn + m if m > 0 else -1}
		var other := AscensionRules.other_branch(faction_id, side)
		out.text += " Swearing it closes %s for the rest of the game, but nothing is closed until it is done: until then you can change your research freely." % AscensionRules.branch_ref(other)
		if m > 0:
			out.text += " %s then needs %d more: about turn %d." % [RulerRules._cap(AscensionRules.branch_ref(side)),
				AscensionRules.node_cost(next), int(out.then.done_turn)]
	return out


# --- the transformations' province rules (M4-2, #67; design/M4_ASCENSION.md §4.6, §4.7, §9.4) ---------

## What `faction_id`'s province rule does at the end of this turn, from the same AscensionRules functions
## the research phase runs, for the map: the provinces the Wild Spreads will grow, and the armies Hallowed
## Land or the Forges will heal. The board is taken as it stands (every army holds, nobody captures); a
## transformation this turn's research completes counts, but only when `viewer` is the faction itself (it
## reads the private research target; `orders` are its queued orders). Returns {"ok", "rule", "spread":
## [{"province", "name", "grown_from", "text"}], "heal": AscensionRules.heal_targets' info, "by_army":
## {army id: {"fighters", "total", "amount", "province", "text"}}, "text"}. "ok" is false without a rule.
static func province_rules(state: GameState, faction_id: String, orders: Array = [], viewer: String = "") -> Dictionary:
	var out := {"ok": false, "rule": "", "spread": [], "heal": {}, "by_army": {}, "text": ""}
	var f := state.find_faction(faction_id)
	if f == null or not AscensionRules.has_paths(state):
		return out
	var own := viewer.is_empty() or viewer == faction_id
	var view := RulerRules.state_after_orders(state, faction_id, orders) if own else state
	if own:
		view = AscensionRules.after_research(view, faction_id, orders)
	var rule := AscensionRules.province_rule(view, faction_id)
	if rule.is_empty():
		return out
	out.ok = true
	out.rule = String(rule.id)
	var you := "you" if own else "the %s" % f.faction_name
	var lines := []
	for pick in AscensionRules.wild_spread_picks(view, faction_id):
		var names := []
		for pid in pick.grown_from:
			names.append(view.find_province(String(pid)).name)
		var text := "%s turns to forest at the end of this turn (the Wild Spreads), if %s still hold%s it and %s then." % [
			String(pick.name), you, "" if own else "s", RulerRules._or_list(names)]
		out.spread.append({"province": pick.province, "name": pick.name, "grown_from": pick.grown_from.duplicate(), "text": text})
		lines.append(text)
	var heal := AscensionRules.heal_targets(view, faction_id)
	out.heal = heal
	if not heal.is_empty():
		for h in heal.healed:
			var a: Dictionary = out.by_army.get(h.army, {"fighters": 0, "total": 0, "amount": heal.amount, "province": h.province})
			a.fighters = int(a.fighters) + 1
			a.total = int(a.total) + int(h.after) - int(h.before)
			out.by_army[h.army] = a
		for army_id in out.by_army:
			var a: Dictionary = out.by_army[army_id]
			var each := "to full" if int(heal.amount) <= 0 else "+%d hp each, up to their maximum" % int(heal.amount)
			a.text = "%s: %s heal %d hit points at the end of this turn (%s), if this army ends the turn at %s and %s still hold%s it." % [
				RulerRules._cap(String(heal.name)), _count(int(a.fighters), "wounded fighter"), int(a.total), each,
				view.find_province(String(a.province)).name, you, "" if own else "s"]
			lines.append(a.text)
	out.text = " ".join(lines)
	return out


# --- forts and sieges (M3c, #98; design/M3C_SIEGES.md §9.2) -----------------------------------------
# Every number comes from SiegeRules and TurnResolver.price_recruits, the functions the turn resolves with. The
# odds lines (storm, sally, relief, breach) are S-2's; these say what the walls, the siege damage, the cut-off,
# the gold and the recruit limits will do. Turn numbers follow §9.2: relative and absolute ("in 3 turns (turn
# 11)"), and a breach turn always carries its condition ("if you stay as you are").

## The siege forecast for `faction_id` at the fort `province_id` (§9.2), from its side: the besieger's (its
## armies there, plus those its queued moves in `orders` march in) or the garrison's (it owns the fort).
## Returns {"ok", "code", "reason", "province", "side" ("besieger" | "garrison"), "walls", "walls_max",
## "walls_defense", "besieged" (a siege stands or starts this turn), "starts" (it starts this turn), "damage"
## (SiegeRules.siege_damage's result), "turns_to_breach", "breach_turn" (the turn at whose end the walls reach 0
## if the besiegers stay as they are; -1 without a siege), "cut_off" (now), "cut_off_from" (the first turn it
## is cut off; 0 when it won't be), "pickets", "besieger", "empty" (no garrison: walking in takes it),
## "reach" ([army ids of the other side that can reach the fort this turn]), "text"}.
## Forecast equals result: when no army enters or leaves the province, the walls reach 0 at the end of
## breach_turn and the fort is cut off from cut_off_from.
## M3c S-2: `with_odds` adds the odds lines (they fight the real rules on every test seed, so ask only when they are
## shown): for the besiegers "storm_odds" (storming now), "breach_odds" (against the garrison with its cover, as in a
## sally or at the breach) and "relief_storm_odds" (storming with their nearest relief arriving too); for the
## garrison "storm_odds" (if they storm: the garrison's odds), "sally_odds" (every garrison army but the ruler's
## sallies) and "relief_odds" (your nearest army relieves, with that sally). Each is a storm_odds-shaped result.
static func siege(state: GameState, faction_id: String, province_id: String, orders: Array = [], with_odds: bool = false) -> Dictionary:
	var out := {"ok": false, "code": "", "reason": "", "province": province_id, "side": "", "walls": 0, "walls_max": 0,
		"walls_defense": 0, "besieged": false, "starts": false, "damage": {}, "turns_to_breach": 0, "breach_turn": -1,
		"cut_off": false, "cut_off_from": 0, "pickets": false, "besieger": "", "empty": false, "reach": [], "text": ""}
	var p := state.find_province(province_id)
	if not state.sieges or p == null or p.fort_level <= 0:
		out.code = "no_fort"
		out.reason = "This game is played without forts and sieges." if not state.sieges else "%s has no fort." % (p.name if p else "That place")
		out.text = out.reason
		return out
	var turn := state.current_turn + 1
	out.ok = true
	out.walls = p.walls
	out.walls_max = SiegeRules.walls_max(p.fort_level)
	out.walls_defense = SiegeRules.walls_defense(p.walls)
	if p.owner == faction_id:
		out = _siege_garrison(state, faction_id, p, turn, out)
		if with_odds and out.besieged and p.walls > 0:
			_garrison_odds(state, faction_id, p, out)
		return out
	out = _siege_besieger(state, faction_id, p, turn, orders, out)
	if with_odds and out.besieged:
		_besieger_odds(state, faction_id, p, orders, out)
	return out


## The besiegers' odds lines (§9.2): storming now, the garrison with its cover (a sally or the breach), and storming
## with their nearest relief arriving too.
static func _besieger_odds(state: GameState, fid: String, p: Province, orders: Array, out: Dictionary) -> void:
	var storm := storm_odds(state, fid, p.id, orders)
	out["storm_odds"] = storm
	if storm.ok:
		out.text += " Storming now: %s." % _odds_words(storm)
	var breach := breach_odds(state, fid, p.id, orders)
	out["breach_odds"] = breach
	if breach.ok:
		out.text += " Against their garrison with its +%d cover, as in a sally or at the breach: %s." % [FortData.COVER_DEFENSE, _odds_words(breach)]
	if not Array(out.reach).is_empty():
		var with_relief := storm_odds(state, fid, p.id, orders, [out.reach[0]])
		out["relief_storm_odds"] = with_relief
		if with_relief.ok:
			out.text += " Storming with their army from %s arriving too: %s." % [state.find_province(state.find_army(String(out.reach[0])).location).name,
				_odds_words(with_relief)]


## The garrison's odds lines (§9.2): if they storm, sallying now, and relief with a sally.
static func _garrison_odds(state: GameState, fid: String, p: Province, out: Dictionary) -> void:
	var besieger := String(out.besieger)
	var storm := storm_odds(state, besieger, p.id, [], [], fid)
	out["storm_odds"] = storm
	if storm.ok:
		out.text += " If they storm this turn, your odds of holding: %s." % _odds_words(storm)
	var garrison := SiegeRules.garrison(state, p.id).filter(func(a): return a.ruler == null).map(func(a): return a.id)
	if not garrison.is_empty():
		var sally := sally_odds(state, fid, garrison)
		out["sally_odds"] = sally
		if sally.ok:
			out.text += " Sallying now with %s: %s." % [_count(garrison.size(), "army", "armies"), _odds_words(sally)]
	if not Array(out.reach).is_empty():
		var move := MoveOrder.new(String(out.reach[0]), p.id)
		var relief := relief_odds(state, fid, move, garrison)
		out["relief_odds"] = relief
		if relief.ok:
			out.text += " Relief from %s%s: %s." % [state.find_province(state.find_army(move.army_id).location).name,
				" with that sally" if not garrison.is_empty() else "", _odds_words(relief)]


static func _siege_besieger(state: GameState, fid: String, p: Province, turn: int, orders: Array, out: Dictionary) -> Dictionary:
	out.side = "besieger"
	var ours := []
	for a in SiegeRules.besiegers(state, p.id):
		if a.owner == fid:
			ours.append(a)
	var arriving := []
	for o in orders:
		if o is MoveOrder and o.to == p.id:
			var a := state.find_army(o.army_id)
			if a != null and a.owner == fid and not ours.has(a):
				arriving.append(a)
	var armies: Array = ours + arriving
	var inside := SiegeRules.garrison(state, p.id)
	var name := p.name
	if armies.is_empty():
		out.text = "You have no army at %s and none marching there this turn. %s" % [name, SiegeRules.walls_text(state, p.id)]
		return out
	if inside.is_empty():
		out.empty = true
		out.text = "You take the %s at %s unopposed (%d of %d walls), unless an enemy army arrives there too. You can recruit there from turn %d." % [
			SiegeRules.level_word(p.fort_level), name, p.walls, int(out.walls_max), turn + FortData.CAPTURE_WAIT + 1]
		return out
	if p.walls <= 0:
		out.text = "%s's walls are down: you fight its garrison there this turn, in the open, with no siege." % name
		return out
	var dmg := SiegeRules.siege_damage(SiegeRules.troops(armies), SiegeRules.engines_of(armies), SiegeRules.engine_plural(fid))
	out.damage = dmg
	out.besieged = true
	out.starts = p.siege_since <= 0
	out.besieger = fid
	out.turns_to_breach = SiegeRules.turns_to_breach(p.walls, int(dmg.total))
	out.breach_turn = SiegeRules.breach_turn(p.walls, int(dmg.total), turn)
	var need := ceili(float(SiegeRules.troops(inside)) / 2.0)
	out.pickets = SiegeRules.troops(armies) < need
	if not out.pickets:
		out.cut_off_from = turn + 1 if out.starts else p.siege_since + 1
		out.cut_off = not out.starts
	var when := SiegeRules.in_turns_text(int(out.breach_turn), turn, true)
	if int(out.breach_turn) > turn:
		when = "at the end of turn %d, in %s" % [int(out.breach_turn), _count(int(out.turns_to_breach), "turn")]
	var text := "%s's walls (%d of %d: +%d if stormed) drop by %d a turn (%s) and reach 0 %s, if you stay as you are." % [name, p.walls,
		int(out.walls_max), int(out.walls_defense), int(dmg.total), SiegeRules.damage_text(dmg), when]
	text += " Storming now meets the walls as they stand (+%d defense for the garrison)." % int(out.walls_defense)
	if out.pickets:
		text += " Your %d troops outside are only pickets, fewer than half the garrison's %d (%d), so %s is not cut off." % [
			SiegeRules.troops(armies), SiegeRules.troops(inside), need, name]
	elif out.starts:
		text += " From next turn (%d) %s is cut off, and its %d gold a turn comes to you." % [turn + 1, name, p.income]
	else:
		text += " %s is cut off: its %d gold a turn comes to you." % [name, p.income]
	var reach := _who_can_reach(state, p, p.owner)
	out.reach = reach
	if not reach.is_empty():
		text += " %s can reach %s this turn." % [_armies_phrase(state, reach, "Their"), name]
	out.text = text
	return out


static func _siege_garrison(state: GameState, fid: String, p: Province, turn: int, out: Dictionary) -> Dictionary:
	out.side = "garrison"
	var theirs := SiegeRules.besiegers(state, p.id)
	var name := p.name
	var reach := _who_can_reach(state, p, fid)
	out.reach = reach
	if theirs.is_empty():
		out.text = "%s is not besieged. %s Walls repair %d a turn while no enemy army is there." % [name,
			SiegeRules.walls_text(state, p.id), SiegeRules.repair_amount(p.fort_level)]
		return out
	out.besieged = true
	out.besieger = SiegeRules.besieging_faction(state, p.id)
	var dmg := SiegeRules.siege_damage(SiegeRules.troops(theirs), SiegeRules.engines_of(theirs), SiegeRules.engine_plural(String(out.besieger)))
	out.damage = dmg
	var cut := SiegeRules.cut_off_info(state, p.id, turn)
	out.cut_off = cut.cut_off
	out.pickets = cut.pickets
	out.cut_off_from = p.siege_since + 1 if not bool(cut.pickets) else 0
	if p.walls <= 0:
		out.text = "Your walls at %s are down: the battle there comes this turn, on its own, in the open, unless one side leaves." % name
		return out
	out.turns_to_breach = SiegeRules.turns_to_breach(p.walls, int(dmg.total))
	out.breach_turn = SiegeRules.breach_turn(p.walls, int(dmg.total), turn)
	var after := maxi(0, p.walls - int(dmg.total))
	var text := "Your walls at %s (%d of %d: +%d if stormed) drop to %d at the end of this turn (%d)" % [name, p.walls, int(out.walls_max),
		int(out.walls_defense), after, turn]
	if int(out.breach_turn) > turn:
		text += " and to 0 at the end of turn %d" % int(out.breach_turn)
	text += " if the besiegers stay as they are (siege damage %d: %s)." % [int(dmg.total), SiegeRules.damage_text(dmg)]
	text += " If they storm this turn, they meet the walls as they stand (+%d defense for your garrison)." % int(out.walls_defense)
	if out.cut_off:
		text += " %s is cut off: nobody can recruit there, and its %d gold goes to the %s." % [name, p.income,
			_faction_name(state, String(out.besieger))]
	elif out.pickets:
		text += " The %d troops outside are only pickets (half of your %d is %d), so %s is not cut off." % [int(cut.besieger_troops),
			int(cut.garrison_troops), int(cut.need), name]
	if not reach.is_empty():
		text += " %s can reach %s this turn: a relief, and your garrison can sally to join it." % [_armies_phrase(state, reach, "Your"), name]
	out.text = text
	return out


## Armies of `owner_fid` next to `p` that can reach it this turn by a one-step move (army ids, in id order).
static func _who_can_reach(state: GameState, p: Province, owner_fid: String) -> Array:
	var out := []
	for a in state.armies:
		if a.owner == owner_fid and a.location != p.id and p.neighbors.has(a.location):
			out.append(a.id)
	out.sort()
	return out


## "Your army at Westwatch", "Their armies at Highcrag and Westwatch".
static func _armies_phrase(state: GameState, ids: Array, whose: String) -> String:
	var places := []
	for id in ids:
		var a := state.find_army(String(id))
		var name := state.find_province(a.location).name
		if not places.has(name):
			places.append(name)
	return "%s %s at %s" % [whose, "army" if ids.size() == 1 else "armies", RulerRules._and_list(places)]


# --- odds at forts (M3c S-2, #100; design/M3C_SIEGES.md §9.2) -----------------------------------------
# Every battle at a fort goes through SiegeRules.next_battle, the function the turn resolves with, so the odds
# fight the same plan: the battle outside the walls first, then the storm if the stormers won it, or the battle
# through the breach. On each of AutoBattleResolver's ODDS_SAMPLES seeds the whole chain is fought with the real
# rules (one SeededRNG per seed, as one turn's battles share one), on copies of the armies, the losers removed
# between battles. A plan of one battle gives exactly AutoBattleResolver.estimate's numbers on the same sides. The
# other side's orders are unknown: it holds, unless a function says otherwise.
#
# The API S-3's panels call (stable):
#   storm_odds(state, faction_id, province_id, orders = [], relief = [], viewer = "")
#       `faction_id` storms the fort at `province_id` with its armies there and those its queued moves in `orders`
#       march in; `relief` = ids of the fort owner's armies imagined marching in this turn (the "their army at
#       Highcrag can reach it" line: the battle outside the walls comes first). A win: the fort is taken.
#   sally_odds(state, faction_id, army_ids, orders = [])
#       the armies `army_ids` of `faction_id`'s besieged garrison sally; a move of its own into the fort in `orders`
#       is a relief they sally with. A win: no besieger is left.
#   relief_odds(state, faction_id, move, sally_ids = [], orders = [])
#       the MoveOrder `move` brings a relief into `faction_id`'s own besieged fort, and `sally_ids` sally to join
#       it. A win: no besieger is left.
#   breach_odds(state, faction_id, province_id, orders = [])
#       the battle through the breach if both sides stay as they are (the walls taken as 0): what a sally meets
#       too, since both are open battles where the garrison keeps its cover. A win: the other side is gone.
# Each returns battle_odds' shape: {"ok", "code", "reason", "text", and when ok "win_rate", "wins", "samples",
# "label", "reasons", "battles" (the kinds fought in the first test, in order), "chained" (some test fought more
# than one battle)}. `viewer` (storm_odds) counts the odds for another faction, the garrison's ("you likely hold").

static func storm_odds(state: GameState, faction_id: String, province_id: String, orders: Array = [], relief: Array = [],
		viewer: String = "") -> Dictionary:
	var p := state.find_province(province_id)
	var moves := _own_moves(state, faction_id, orders)
	var check := SiegeRules.check_siege_order(state, faction_id, SiegeOrder.storm(province_id), moves)
	if not check.is_empty():
		return {"ok": false, "code": String(check.code), "reason": String(check.reason), "text": String(check.reason)}
	for id in relief:
		var a := state.find_army(String(id))
		if a != null and a.owner == p.owner and a.location != province_id:
			moves.append(MoveOrder.new(a.id, province_id))
	var orders_at := {"storms": {province_id: {faction_id: true}}, "sallies": {}}
	return _plan_odds(state, viewer if not viewer.is_empty() else faction_id, province_id, moves, orders_at)


static func sally_odds(state: GameState, faction_id: String, army_ids: Array, orders: Array = []) -> Dictionary:
	if army_ids.is_empty():
		return {"ok": false, "code": "no_army", "reason": "No army is sallying.", "text": "No army is sallying."}
	var moves := _own_moves(state, faction_id, orders)
	var first := state.find_army(String(army_ids[0]))
	var pid := first.location if first != null else ""
	var relief := ""
	for m in moves:
		if m.to == pid:
			relief = m.army_id
	var orders_at := {"storms": {}, "sallies": {}}
	var given := []
	for id in army_ids:
		var order := SiegeOrder.sally(String(id), relief)
		var check := SiegeRules.check_siege_order(state, faction_id, order, moves, given)
		if not check.is_empty():
			return {"ok": false, "code": String(check.code), "reason": String(check.reason), "text": String(check.reason)}
		given.append(order)
		orders_at.sallies[String(id)] = {"faction": faction_id, "with": relief, "from": ""}
	return _plan_odds(state, faction_id, pid, moves, orders_at)


static func relief_odds(state: GameState, faction_id: String, move: MoveOrder, sally_ids: Array = [], orders: Array = []) -> Dictionary:
	var check := TurnResolver.check_move(state, faction_id, move)
	if not check.is_empty():
		return {"ok": false, "code": String(check.code), "reason": String(check.reason), "text": String(check.reason)}
	var moves := _own_moves(state, faction_id, orders).filter(func(m): return m.army_id != move.army_id)
	moves.append(move)
	var orders_at := {"storms": {}, "sallies": {}}
	var given := []
	for id in sally_ids:
		var order := SiegeOrder.sally(String(id), move.army_id)
		var sally_check := SiegeRules.check_siege_order(state, faction_id, order, moves, given)
		if not sally_check.is_empty():
			return {"ok": false, "code": String(sally_check.code), "reason": String(sally_check.reason), "text": String(sally_check.reason)}
		given.append(order)
		orders_at.sallies[String(id)] = {"faction": faction_id, "with": move.army_id, "from": ""}
	return _plan_odds(state, faction_id, move.to, moves, orders_at)


static func breach_odds(state: GameState, faction_id: String, province_id: String, orders: Array = []) -> Dictionary:
	var p := state.find_province(province_id)
	if not state.sieges or p == null or p.fort_level <= 0:
		return {"ok": false, "code": "no_fort", "reason": "There is no fort there.", "text": "There is no fort there."}
	return _plan_odds(state, faction_id, province_id, _own_moves(state, faction_id, orders), {"storms": {}, "sallies": {}}, 0)


## `faction_id`'s move orders in `orders` whose army is on the map and its own.
static func _own_moves(state: GameState, faction_id: String, orders: Array) -> Array:
	var out := []
	for o in orders:
		if o is MoveOrder:
			var a := state.find_army(o.army_id)
			if a != null and a.owner == faction_id:
				out.append(o)
	return out


## The odds of `perspective` at the fort `province_id` when `moves` happen and `siege_orders` are given, the walls
## taken as `walls` when it isn't -1 (see the block comment above).
static func _plan_odds(state: GameState, perspective: String, province_id: String, moves: Array, siege_orders: Dictionary,
		walls: int = -1) -> Dictionary:
	var copy := state.deep_copy([])
	if copy == null:
		return {"ok": false, "code": "bad_state", "reason": "The game can't be copied to test this battle.", "text": "The game can't be copied to test this battle."}
	var p := copy.find_province(province_id)
	var moved := {}
	for m in moves:
		var a := copy.find_army(m.army_id)
		if a != null and a.location != m.to:
			a.location = m.to
			moved[a.id] = true
	if walls >= 0:
		p.walls = walls
	var originals: Array[Army] = copy.armies.duplicate()
	var wins := 0
	var scores := {}
	var briefs := {}
	var first := []
	var chained := false
	for i in AutoBattleResolver.ODDS_SAMPLES:
		var armies: Array[Army] = []
		for a in originals:
			armies.append(_clone_army(a))
		copy.armies = armies
		var rng := SeededRNG.new(AutoBattleResolver.odds_seed(i))
		var fought := []
		while true:
			var plan := SiegeRules.next_battle(copy, province_id, moved, siege_orders, fought)
			if plan.is_empty():
				break
			var fids: Array = plan.sides.keys()
			fids.sort()
			var sides_in := []
			for fid in fids:
				sides_in.append({"faction": fid, "armies": plan.sides[fid]})
			var ctx := {"kind": "province", "defender": String(plan.defender), "province": p, "province_ids": [province_id],
				"state": copy, "siege": plan.siege}
			var r := AutoBattleResolver.fight(sides_in, ctx, rng)
			AutoBattleResolver.add_odds_factors(r.result.report, perspective, scores, briefs)
			AutoBattleResolver._apply_losses(r.sides, r.result.winner)
			_remove_losers(copy, sides_in, String(r.result.winner))
			fought.append(String(plan.kind))
		if i == 0:
			first = fought.duplicate()
			if fought.is_empty():
				break
		chained = chained or fought.size() > 1
		if _holds(copy, province_id, perspective):
			wins += 1
	copy.armies = originals
	if first.is_empty():
		var why := "No battle happens at %s this turn as things stand: an army that arrives at a fort with standing walls and a garrison inside besieges it." % p.name
		return {"ok": false, "code": "no_battle", "reason": why, "text": why, "siege": true}
	var out := AutoBattleResolver.odds_summary(wins, scores, briefs, perspective, copy)
	out["ok"] = true
	out["code"] = ""
	out["reason"] = ""
	out["battles"] = first
	out["chained"] = chained
	return out


## A copy of `a` (its units at their hit points) that a test battle can wound and destroy.
static func _clone_army(a: Army) -> Army:
	var c := Army.new()
	c.id = a.id
	c.owner = a.owner
	c.location = a.location
	c.engines = a.engines
	for u in a.units:
		c.units.append(_clone_unit(u))
	if a.commander != null:
		c.commander = _clone_unit(a.commander)
	if a.ruler != null:
		c.ruler = _clone_unit(a.ruler)
	return c


static func _clone_unit(u: Unit) -> Unit:
	var c := Unit.new(u.type, u.owner)
	c.current_hp = u.current_hp
	return c


## After a test battle, as TurnResolver._fight does: every army of a losing side goes, and so does a winning army
## whose every fighter fell.
static func _remove_losers(state: GameState, sides_in: Array, winner: String) -> void:
	var gone := {}
	for side in sides_in:
		for a in side.armies:
			if side.faction != winner or (a.units.is_empty() and a.commander == null and a.ruler == null):
				gone[a.id] = true
	var kept: Array[Army] = []
	for a in state.armies:
		if not gone.has(a.id):
			kept.append(a)
	state.armies = kept


## True when `fid` has an army at `province_id` and no other faction has.
static func _holds(state: GameState, province_id: String, fid: String) -> bool:
	var mine := false
	for a in state.armies:
		if a.location != province_id:
			continue
		if a.owner != fid:
			return false
		mine = true
	return mine


## "likely win (21 of 24)".
static func _odds_words(odds: Dictionary) -> String:
	return "%s (%d of %d test battles won)" % [String(odds.label), int(odds.wins), int(odds.samples)]


## The Fortify forecast for `province_id` (§9.2): what the next level costs, when it stands, when it takes
## recruits and how long its walls hold. `orders` are the faction's queued orders: their recruits and Fortify
## orders are paid first, in the order given. Returns {"ok", "code", "reason", "province", "level", "cost",
## "gold_left", "stands" (the turn it stands at the end of), "recruit_from", "recruits", "walls", "text"}.
## Forecast equals result: if no enemy army stands there meanwhile, the level stands at the end of `stands`.
static func fortify(state: GameState, faction_id: String, province_id: String, orders: Array = []) -> Dictionary:
	var out := {"ok": false, "code": "", "reason": "", "province": province_id, "level": 0, "cost": 0, "gold_left": 0,
		"stands": 0, "recruit_from": 0, "recruits": 0, "walls": 0, "text": ""}
	var view := RulerRules.state_after_orders(state, faction_id, orders)
	var paid := orders.filter(func(o): return o is RecruitOrder or o is FortifyOrder)
	var priced := TurnResolver.price_recruits(view, faction_id, paid + [FortifyOrder.new(province_id)])
	var r: Dictionary = priced.results.back()
	if not r.ok:
		out.code = String(r.code)
		out.reason = String(r.reason)
		out.text = out.reason
		return out
	var p := view.find_province(province_id)
	var to := int(r.to)
	var turn := view.current_turn + 1
	var turns := int(SiegeRules.level_data(to).turns)
	var walls := SiegeRules.walls_max(to)
	var s := FortData.SIEGE
	var big := int(s.per_troops) * int(s.troops_max)  # troops for the most siege damage from troops
	var raid_turns := SiegeRules.turns_to_breach(walls, int(s.camp))
	var army_turns := SiegeRules.turns_to_breach(walls, int(s.camp) + int(s.troops_max))
	out.ok = true
	out.level = to
	out.cost = int(r.cost)
	out.gold_left = int(r.gold_after)
	out.stands = turn + turns
	out.recruit_from = turn + turns + 1
	out.recruits = SiegeRules.recruit_limit(to)
	out.walls = walls
	out.text = "%s at %s: %d gold now (%d left after your recruits). Built at the end of turn %d if no enemy army stands there; you can recruit %d a turn there from turn %d. Walls %d: against a raid they hold %s, against %d or more troops %s, and they give +%d defense only if stormed. You can build one fort at a time." % [
		SiegeRules.level_name(to), p.name, out.cost, out.gold_left, out.stands, out.recruits, out.recruit_from, walls,
		_count(raid_turns, "turn"), big, _count(army_turns, "turn"), SiegeRules.walls_defense(walls)]
	return out


## The recruit forecast at a fort (§9.2): "Spearmen at Stonegate (3 of 4 this turn): they join the Aurel Crown
## army there." `at` is where (RecruitOrder.at: "" for the capital, or a fort's id); `orders` the faction's
## queued orders, paid first. For a siege engine it says which army carries it, and what one more engine
## changes at each siege that faction keeps now. Returns {"ok", "code", "reason", "unit_type", "name", "fort",
## "count", "limit", "price", "joins" (the army's id, "" for a new army), "text"}.
static func recruit_at(state: GameState, faction_id: String, unit_type_id: String, at: String = "", orders: Array = []) -> Dictionary:
	var out := {"ok": false, "code": "", "reason": "", "unit_type": unit_type_id, "name": "", "fort": "", "count": 0, "limit": 0,
		"price": 0, "joins": "", "text": ""}
	var view := RulerRules.state_after_orders(state, faction_id, orders)
	var f := view.find_faction(faction_id)
	var ut: UnitType = TurnResolver.recruitable_type(f, unit_type_id, view) if f else null
	if ut == null:
		out.code = "unknown_unit_type"
		out.reason = "That is not a unit you can recruit."
		out.text = out.reason
		return out
	out.name = ut.name
	var paid := orders.filter(func(o): return o is RecruitOrder or o is FortifyOrder)
	var priced := TurnResolver.price_recruits(view, faction_id, paid + [RecruitOrder.new(unit_type_id, at)])
	var r: Dictionary = priced.results.back()
	if not r.ok:
		out.code = String(r.code)
		out.reason = String(r.reason)
		out.text = out.reason
		return out
	out.ok = true
	out.price = int(r.cost)
	var place := String(r.province)
	out.fort = place
	out.count = int(r.get("count", 0))
	out.limit = int(r.get("limit", 0))
	var where := view.find_province(place).name
	var head := "%s at %s (%d of %d this turn)" % [ut.name, where, out.count, out.limit] if view.sieges else "%s at %s" % [ut.name, where]
	var joins: Army = null
	for a in TurnResolver._sorted_armies(view):
		if a.owner != faction_id or a.location != place or a.ruler != null:
			continue
		if SiegeRules.is_engine(ut) and not SiegeRules.can_carry(a):
			continue
		if ut.is_commander and a.commander != null:
			continue
		joins = a
		break
	out.joins = joins.id if joins != null else ""
	if SiegeRules.is_engine(ut):
		var who := TurnReportText.army_title(view, joins, false) if joins != null else "the army a recruit forms there first"
		out.text = "%s: %d gold; it joins %s. %s" % [head, out.price, who, FortData.ENGINE_RULE]
		for pid in _sieges_of(view, faction_id):
			var p := view.find_province(pid)
			var mine := SiegeRules.besiegers(view, pid).filter(func(a): return a.owner == faction_id)
			var now := SiegeRules.siege_damage(SiegeRules.troops(mine), SiegeRules.engines_of(mine))
			var more := SiegeRules.siege_damage(SiegeRules.troops(mine), SiegeRules.engines_of(mine) + 1)
			var n_now := SiegeRules.turns_to_breach(p.walls, int(now.total))
			var n_more := SiegeRules.turns_to_breach(p.walls, int(more.total))
			if int(more.total) > int(now.total):
				out.text += " Brought to %s, it would raise the siege damage there from %d to %d: the walls would drop to 0 in %s instead of %s." % [
					p.name, int(now.total), int(more.total), _count(n_more, "turn"), _count(n_now, "turn")]
			else:
				out.text += " Brought to %s, it would change nothing there: your %d troops there work at most %d engines, and at most %d count." % [
					p.name, SiegeRules.troops(mine), SiegeRules.troops(mine) / int(FortData.SIEGE.troops_per_engine), int(FortData.SIEGE.engines_max)]
		return out
	if joins != null:
		var verb := "lead" if ut.is_commander else "join"
		out.text = "%s: they %s %s." % [head, verb, TurnReportText.army_title(view, joins, false)]
	else:
		out.text = "%s: they form a new army there." % head
	return out


## The forts `faction_id` besieges now, in id order.
static func _sieges_of(state: GameState, faction_id: String) -> Array:
	var out := []
	for p in TurnResolver._sorted_provinces(state):
		if p.owner != faction_id and SiegeRules.is_besieged(state, p.id) and SiegeRules.besieging_faction(state, p.id) == faction_id:
			out.append(p.id)
	return out


static func _faction_name(state: GameState, fid: String) -> String:
	var f := state.find_faction(fid)
	return f.faction_name if f else ""


static func _row(key: String, label: String, before: String, after: String, codex: String, breakdown: Dictionary,
		before_value: int = 0, after_value: int = 0, higher_is_better: bool = true) -> Dictionary:
	return {"key": key, "label": label, "before": before, "after": after, "codex": codex, "breakdown": breakdown,
		"before_value": before_value, "after_value": after_value, "higher_is_better": higher_is_better}


## "1 unit", "3 units": a count with its noun in the right number.
static func _count(n: int, singular: String, plural: String = "") -> String:
	return "%d %s" % [n, singular if n == 1 else (plural if not plural.is_empty() else singular + "s")]
