class_name OrdersController
extends RefCounted
## The orders UI's side of issue #6: the orders of the faction at the controls.
## Holds no rules math. Whether an order is allowed comes from OrderBook.submit (the resolver's own
## checks, with their plain-language reasons) and every forecast number comes from Forecast.
## Only reads the GameState, never changes it.
##
## Two modes:
##   standalone      (map preview, tests) the orders live in this controller's own OrderBook.
##   session-backed  (the game screen, #7) pass a GameSession: the orders live in the session's books,
##                   the single source of truth, so they survive map rebuilds and resolve with the
##                   turn. orders() is empty unless `faction_id` is the session's current player, so
##                   one player's orders can never show up on another player's map.
##
## Sacrifice (M2-6, design/M2_RULER.md §2.4): the sacrifice phase resolves first, so every forecast here
## reads view_state(), the start-of-turn state with the queued Sacrifice order applied (the same copy
## OrderBook checks against). Cancelling an order checks the others again; last_removed() names the ones
## that no longer pass, with the reason.

## Shown instead of battle odds when no enemy army is in the destination (M1 has no fog of war).
const NO_ENEMY_TEXT := "No enemy army there now; enemies may still move in."

var state: GameState
var faction_id := ""
var book := OrderBook.new()
var session: GameSession = null
var _odds_cache := {}  # "army ids>province" -> move_odds() result; the state never changes under us
var _view: GameState = null  # view_state() for the sacrifice in _view_key
var _view_key := ""
var _removed: Array = []  # texts of the orders the last queue or cancel removed (M2-6)


func _init(p_state: GameState = null, p_faction_id: String = "", p_session: GameSession = null) -> void:
	state = p_state
	faction_id = p_faction_id
	session = p_session


## Queues a move. A province two steps away that King's Roads reach is ordered as a road move through
## the first legal province by id (move_order_for). Returns "" when accepted, otherwise the rules' reason
## it was refused.
func queue_move(army_id: String, to_province: String) -> String:
	return _queue(move_order_for(army_id, to_province))


## Queues one recruit at the capital. Returns "" when accepted, otherwise the rules' reason.
func queue_recruit(unit_type_id: String) -> String:
	return _queue(RecruitOrder.new(unit_type_id))


## Queues one recruit with the ruler (Warband Muster: the unit appears where the Ninth Fang ends the
## turn). Returns "" when accepted, otherwise the rules' reason.
func queue_recruit_with_ruler(unit_type_id: String) -> String:
	return _queue(RecruitOrder.new(unit_type_id, RecruitOrder.AT_RULER))


## Queues a Sacrifice order (§2.4): the ruler gives up power for `mandate_id`. Returns "" when accepted,
## otherwise the rules' reason. Orders it makes fail are removed: see last_removed().
func queue_sacrifice(mandate_id: String) -> String:
	return _queue(SacrificeOrder.new(mandate_id))


## The queued Sacrifice order, or null.
func queued_sacrifice() -> SacrificeOrder:
	return RulerRules.queued_sacrifice(orders())


## The state this faction's orders and forecasts read: the start-of-turn state, or a copy with the
## queued Sacrifice order applied (RulerRules.state_after_orders), because the sacrifice phase resolves
## first. Never changes `state`.
func view_state() -> GameState:
	var sac := queued_sacrifice()
	if sac == null or state == null:
		return state
	if _view == null or _view_key != sac.mandate_id:
		_view = RulerRules.state_after_orders(state, faction_id, orders())
		_view_key = sac.mandate_id
	return _view


## Every mandate on this faction's list for the sacrifice dialog (Forecast.sacrifice_options).
func sacrifice_options() -> Array:
	return Forecast.sacrifice_options(state, faction_id, orders())


## The sacrifice dialog's before → after preview for `mandate_id` (Forecast.sacrifice), with this
## faction's other queued orders.
func sacrifice_preview(mandate_id: String) -> Dictionary:
	return Forecast.sacrifice(state, faction_id, mandate_id, orders())


## Plain lines for the orders the last queue or cancel removed because they no longer pass ("Road move to
## Westwatch removed: you no longer have King's Roads."); [] when none were.
func last_removed() -> Array:
	return _removed.duplicate()


## The order a click on `to` gives `army_id`: a one-step move to a neighbour, or, for a province further
## away, a road move through the first legal province by id when King's Roads allow one (§2.3).
## Anything else stays a one-step move, which the rules then refuse with their reason.
func move_order_for(army_id: String, to: String) -> MoveOrder:
	var army: Army = state.find_army(army_id) if state else null
	var here: Province = state.find_province(army.location) if army else null
	if here != null and not here.neighbors.has(to):
		var vias := RulerRules.road_vias(view_state(), faction_id, army_id, to)
		if not vias.is_empty():
			return MoveOrder.new(army_id, to, vias[0])
	return MoveOrder.new(army_id, to)


## The provinces two steps away that `army_id` can reach by the King's Roads this turn, {province id:
## [legal vias, sorted]}: the map draws them as road destinations. Empty when the army is not yours,
## already has a move, or your faction has no King's Roads.
func road_destinations(army_id: String) -> Dictionary:
	var army: Army = state.find_army(army_id) if state else null
	if army == null or army.owner != faction_id:
		return {}
	for o in orders():
		if o is MoveOrder and o.army_id == army_id:
			return {}
	return RulerRules.road_destinations(view_state(), faction_id, army_id)


## Every legal way through for the queued road move at `index` ([] for any other order).
func road_vias_at(index: int) -> Array:
	var list := orders()
	if index < 0 or index >= list.size() or not (list[index] is MoveOrder) or not list[index].is_road_move():
		return []
	return RulerRules.road_vias(view_state(), faction_id, list[index].army_id, list[index].to)


## Sends the queued road move at `index` through the next legal province instead (the player's other
## choice, §2.3). The order is given again, so it moves to the end of the list. "" or the reason.
func change_via(index: int) -> String:
	var vias := road_vias_at(index)
	if vias.size() < 2:
		return "This road move has only one way through."
	var o: MoveOrder = orders()[index]
	var next: String = vias[(vias.find(o.via) + 1) % vias.size()]
	var why := cancel(index)
	if not why.is_empty():
		return why
	return _queue(MoveOrder.new(o.army_id, o.to, next))


## Withdraws the order at `index` (as listed by orders()). Returns "" or why it could not. The other
## orders are checked again: cancelling a sacrifice removes the orders that relied on it (last_removed()).
func cancel(index: int) -> String:
	_removed = []
	if session != null:
		var why := _not_my_turn()
		if not why.is_empty():
			return why
		why = session.cancel_order(index)
		_removed = session.removed_orders()
		return why
	_removed = book.cancel(state, faction_id, index).map(func(d): return String(d.text))
	return ""


func orders() -> Array:
	if session != null:
		return session.current_orders() if session.current_player() == faction_id else []
	return book.orders_for(faction_id)


func recruit_orders() -> Array:
	var out := []
	for o in orders():
		if o is RecruitOrder:
			out.append(o)
	return out


## Forecast for a move that is not queued yet (catches a second move for the same army). A province
## two steps away is forecast as the road move a click would order.
func move_forecast(army_id: String, to: String) -> Dictionary:
	return Forecast.move(view_state(), faction_id, move_order_for(army_id, to), orders())


## Battle odds for moving `army_id` to `to`, counting every army you have already ordered there.
## Returns {"enemy_present", "odds" (Forecast.battle_odds result, {} when no enemy is there),
## "line" (verdict and main reasons, for the forecast line), "text" (the full odds text, for tooltips)}.
func move_odds(army_id: String, to: String) -> Dictionary:
	var ids := [army_id]
	for o in orders():
		if o is MoveOrder and o.to == to and not ids.has(o.army_id):
			ids.append(o.army_id)
	ids.sort()
	var view := view_state()
	var key := "%s>%s|%s" % [",".join(ids), to, _view_key if view != state else ""]
	if _odds_cache.has(key):
		return _odds_cache[key]
	# Forecast.battle_odds checks for enemy armies there itself (M1 has no fog: all are visible). A queued
	# sacrifice counts: its mandate fights in this turn's battles.
	var odds := Forecast.battle_odds(view, faction_id, ids, to)
	var out := {"enemy_present": false, "odds": {}, "line": NO_ENEMY_TEXT, "text": NO_ENEMY_TEXT}
	if odds.get("ok", false):
		var line := "Battle odds: %s (you won %d of %d test battles)." % [odds.label, odds.wins, odds.samples]
		if not odds.reasons.is_empty():
			line += " Main reasons: %s." % "; ".join(odds.reasons)
		out = {"enemy_present": true, "odds": odds, "line": line, "text": odds.text}
	_odds_cache[key] = out
	return out


## What clicking `to` with `army_id` selected would do, before the click (the map's hover preview):
## {"ok", "text"}. When the move is allowed, the text has the arrival forecast and the battle odds.
func move_preview(army_id: String, to: String) -> Dictionary:
	var f := move_forecast(army_id, to)
	if not f.ok:
		return {"ok": false, "text": "This move can't be ordered: %s" % f.reason}
	return {"ok": true, "text": "Click to order this move. %s %s" % [f.text, move_odds(army_id, to).line]}


## Gold after the queued recruits and the income forecast. Your queued moves count for Royal Court,
## which pays where the King ends the turn.
func gold_after_recruits() -> Dictionary:
	return Forecast.gold_after_recruits(view_state(), faction_id, recruit_orders(), orders())


## The price of one unit, the same the recruitment phase charges (Muster Grounds included).
func recruit_cost(unit_type_id: String) -> int:
	return Forecast.recruit_cost(view_state(), faction_id, unit_type_id)


## "16 gold (20 - Muster Grounds 4)", or "20 gold" when no mandate changes the price.
func price_text(unit_type_id: String) -> String:
	var f := state.find_faction(faction_id)
	var ut: UnitType = TurnResolver.recruitable_type(f, unit_type_id) if f else null
	return RulerRules.price_text(view_state(), faction_id, ut) if ut else ""


## The roster this faction can recruit from at its capital.
func recruitable_types() -> Array:
	var f := state.find_faction(faction_id)
	return f.unit_types.duplicate() if f else []


## The Warband Muster part of the recruit panel (§1.4): {"ok", "army_id", "province", "ruler", "limit",
## "used", "left", "text"} for this faction. "ok" is false when its ruler can't recruit in the field
## (another ruler, no rulers, or not on the map).
func ruler_recruit_info() -> Dictionary:
	var view := view_state()
	var limit := RulerRules.field_recruit_limit(view, faction_id)
	var army := RulerRules.ruler_army(view, faction_id)
	if limit <= 0 or army == null:
		return {"ok": false}
	var used := 0
	for o in orders():
		if o is RecruitOrder and o.is_with_ruler():
			used += 1
	var name := RulerRules.current_name(view, faction_id)
	var f := view.find_faction(faction_id)
	var where := view.find_province(army.location)
	var text := "%s can recruit %d regular %s per turn (Warband Muster at ability rank %d), at the usual prices. They gather at %s, where %s starts this turn, and join your armies there at the end of the turn, even if %s marches on; if you no longer own %s then, or %s has fallen, they are cancelled and cost nothing. Commanders come only from your capital." % [
		RulerRules._cap(name), limit, "unit" if limit == 1 else "units", RulerRules.ability_rank(f.kept_power),
		where.name if where else "off the map", name, name, where.name if where else "it", name]
	return {"ok": true, "army_id": army.id, "province": army.location, "ruler": name, "limit": limit, "used": used,
		"left": maxi(0, limit - used), "text": text}


## The road rule of a legal road move of `army_id` to `to` through `via`, by name ("King's Roads" or "Forest
## Stride", M4-2), for the map's road destination marks.
func road_rule_name(army_id: String, to: String, via: String) -> String:
	return TurnResolver.road_rule_name(TurnResolver.road_rule(view_state(), faction_id, MoveOrder.new(army_id, to, via)))


## Every transformation's province rule forecast on the board (M4-2, §9.4), in faction id order:
## Forecast.province_rules for each faction with a rule now (your own counts a transformation your research
## completes this turn; a rival's never reads its private target), plus "faction".
func province_rule_forecasts() -> Array:
	var out := []
	if state == null or not AscensionRules.has_paths(state):
		return out
	var fids := []
	for f in state.factions:
		fids.append(f.id)
	fids.sort()
	for fid in fids:
		var pr := Forecast.province_rules(state, fid, orders() if fid == faction_id else [], faction_id)
		if pr.ok:
			pr["faction"] = fid
			out.append(pr)
	return out


## Every Sworn Vassals forecast on the board (§2.3), one per faction with the mandate, in faction id
## order: Forecast.vassal with this faction's queued moves (other armies hold), plus "faction".
func vassal_forecasts() -> Array:
	var out := []
	if state == null:
		return out
	var view := view_state()  # Sworn Vassals bought by a queued sacrifice joins this turn
	var fids := []
	for f in view.factions:
		if RulerRules.has_mandate(view, f.id, RulerRules.SWORN_VASSALS):
			fids.append(f.id)
	fids.sort()
	for fid in fids:
		var v := Forecast.vassal(view, fid, orders(), faction_id)
		v["faction"] = fid
		out.append(v)
	return out


## One plain-language line per queued order (names, never ids), with its forecast.
func order_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for i in orders().size():
		out.append(order_text(i))
	return out


func order_text(index: int) -> String:
	var list := orders()
	if index < 0 or index >= list.size():
		return ""
	var o = list[index]
	if o is MoveOrder:
		var f := _move_forecast_at(index)
		return "%s %s" % [f.text, move_odds(o.army_id, o.to).line] if f.ok else f.reason
	if o is SacrificeOrder:
		return sacrifice_text(o)
	var r := _recruit_result_at(index)
	if not r.ok:
		return "Not recruited: %s" % r.reason
	if r.at == RecruitOrder.AT_RULER:
		var name := RulerRules.current_name(state, faction_id)
		return "Recruit one %s with %s for %d gold, leaving %d gold. It gathers at %s, where %s starts this turn, and joins your armies there at the end of the turn, if you still own %s then and %s stands; if not, it is cancelled and costs nothing." % [
			_unit_name(r.unit_type), name, r.cost, r.gold_after, _province_name(r.province), name, _province_name(r.province), name] + _arrival_note(r)
	var text := "Recruit one %s at %s for %d gold, leaving %d gold." % [_unit_name(r.unit_type), _capital_name(), r.cost, r.gold_after]
	return text + _arrival_note(r)


## M4-2, Blood Levy (§9.4): " It arrives wounded, 11 of 14 hit points (Blood Levy ...)." for a recruit that
## arrives below its maximum (price_recruits' "hp"), "" otherwise, so other lines read as before.
func _arrival_note(r: Dictionary) -> String:
	if int(r.get("hp", 0)) >= int(r.get("max_hp", 0)):
		return ""
	var f := state.find_faction(faction_id)
	var ut: UnitType = TurnResolver.recruitable_type(f, String(r.unit_type)) if f else null
	return " " + AscensionRules.arrival_text(ut, int(r.hp), int(r.max_hp), AscensionRules.blood_levy_divisor(view_state(), faction_id)).replace("They arrive", "It arrives")


## Breakdown (rules/breakdown.gd shape) behind an order line's numbers, for its tooltip.
func order_breakdown(index: int) -> Dictionary:
	var o = orders()[index]
	if o is SacrificeOrder:
		var b := Breakdown.sacrifice_kept_power(state, faction_id, o.mandate_id)
		b.description = "%s %s %s" % [String(RulerRules.mandate_data(o.mandate_id).get("effect", "")),
			Forecast.mandate_now(view_state(), faction_id, o.mandate_id, orders()), RulesCodex.text("sacrifice")]
		return b
	if o is MoveOrder:
		var f := _move_forecast_at(index)
		if not f.ok:
			return _bd("Move order", f.reason, [], "Arrives at the start of turn", 0)
		var odds := move_odds(o.army_id, o.to)
		var odds_desc: String = "%s %s" % [odds.text, RulesCodex.text("battle_odds")] if odds.enemy_present else odds.text
		var step := _line("Moving one province", 1, "armies move one neighboring province per turn")
		var rule := RulesCodex.text("move")
		if o.is_road_move() and TurnResolver.road_rule(view_state(), faction_id, o) == "forest_stride":
			step = _line("Moving two provinces by Forest Stride", 1, "a road move takes one turn, through a forest you own into another forest")
			rule = RulesCodex.text("forest_stride")
		elif o.is_road_move():
			step = _line("Moving two provinces by the King's Roads", 1, "a road move takes one turn, through land you own")
			rule = RulesCodex.text("road_move")
		if o.is_road_move():
			if road_vias_at(index).size() > 1:
				rule += " Another way through is open: use the button next to this order to change it."
		return _bd("Move forecast", "%s %s %s" % [f.text, odds_desc, rule],
			[_line("Turn now", state.current_turn + 1, "turns count from 1"), step],
			"Arrives at the start of turn", f.arrival_turn)
	var r := _recruit_result_at(index)
	if not r.ok:
		return _bd("Recruit order", r.reason, [], "Gold spent", 0)
	var rules := RulesCodex.text("field_recruit" if r.at == RecruitOrder.AT_RULER else "recruit")
	return _bd("Recruit %s" % _unit_name(r.unit_type), "Recruits are paid in the order given. %s" % rules,
		[_line("Gold before this recruit", r.gold_after + r.cost, ""), _line("Cost", -r.cost, _price_note(r.unit_type))],
		"Gold left after this recruit", r.gold_after)


## Which kind of number an order line is, for its codex link (TooltipText.CODEX): a move into an
## enemy army links to the battle odds, a road move to road moves, any other move to moving, a recruit
## with the ruler to recruiting in the field, any other recruit to recruiting.
func order_codex_kind(index: int) -> String:
	var list := orders()
	if index < 0 or index >= list.size():
		return ""
	var o = list[index]
	if o is SacrificeOrder:
		return "sacrifice"
	if o is MoveOrder:
		if move_odds(o.army_id, o.to).enemy_present:
			return "move_odds"
		return "road_move" if o.is_road_move() else "move_order"
	if o is RecruitOrder and o.is_with_ruler():
		return "field_recruit"
	return "recruit"


func gold_breakdown() -> Dictionary:
	var g := gold_after_recruits()
	return _bd("Gold after recruits", g.text, [_line("Gold now", g.gold_now, ""), _line("Queued recruits", -g.spent, "")],
		"Gold after recruits", g.gold_after)


## Tooltip numbers for a recruit button: what one more of this unit would leave you with. `at` is
## RecruitOrder.AT_RULER for the "Recruit with the Ninth Fang" buttons (Warband Muster).
func recruit_breakdown(unit_type_id: String, at: String = RecruitOrder.AT_CAPITAL) -> Dictionary:
	var g := gold_after_recruits()
	var cost := recruit_cost(unit_type_id)
	var f := state.find_faction(faction_id)
	var ut: UnitType = TurnResolver.recruitable_type(f, unit_type_id) if f else null
	var rules := RulesCodex.text("recruit")
	var title := "Recruit %s" % _unit_name(unit_type_id)
	if at == RecruitOrder.AT_RULER:
		var info := ruler_recruit_info()
		rules = String(info.get("text", RulesCodex.text("field_recruit")))
		title = "Recruit %s with %s" % [_unit_name(unit_type_id), RulerRules.current_name(state, faction_id)]
	var desc := "%s %s" % [Breakdown.unit_type_description(ut, price_text(unit_type_id)) if ut else "", rules]
	var fc := Forecast.recruit(state, faction_id, unit_type_id, orders())  # M4-2: Blood Levy's wounded arrivals
	if fc.ok and int(fc.hp) < int(fc.max_hp):
		desc = "%s %s" % [fc.text, desc]
	return _bd(title, desc.strip_edges(), [_line("Gold left after queued recruits", g.gold_after, ""),
		_line("Cost of one %s" % _unit_name(unit_type_id), -cost, _price_note(unit_type_id))],
		"Gold left if you recruit it", g.gold_after - cost)


# --- helpers --------------------------------------------------------------------------------------

## Queues `order` through the session's books (session-backed) or this controller's own book.
func _queue(order) -> String:
	_removed = []
	if session != null:
		var why := _not_my_turn()
		if not why.is_empty():
			return why
		why = session.queue_order(order)
		_removed = session.removed_orders()
		return why
	var reason := book.submit(state, faction_id, order)
	_removed = book.last_dropped().map(func(d): return String(d.text))
	return reason


## The orders list's line for a queued Sacrifice order.
func sacrifice_text(order: SacrificeOrder) -> String:
	var mid := order.mandate_id
	var kept := RulerRules.kept_power(state, faction_id)
	return "Sacrifice for %s: %s gives up %d power (%d, +%d for a mid-game sacrifice), keeping %d. It resolves first, so it already counts for your other orders this turn." % [
		RulerRules.mandate_name(mid), RulerRules._cap(RulerRules.current_name(state, faction_id)), RulerRules.sacrifice_cost(mid),
		RulerRules.mandate_cost(mid), MandateData.SACRIFICE_PREMIUM, kept - RulerRules.sacrifice_cost(mid)]


## The price breakdown as a line note when a mandate changes the price ("16 gold (20 - Muster Grounds
## 4)"), "" otherwise, so an M1 tooltip reads exactly as before.
func _price_note(unit_type_id: String) -> String:
	var f := state.find_faction(faction_id)
	var ut: UnitType = TurnResolver.recruitable_type(f, unit_type_id) if f else null
	return price_text(unit_type_id) if ut and not RulerRules.price_mods(view_state(), faction_id, ut).is_empty() else ""


func _province_name(province_id: String) -> String:
	var p: Province = state.find_province(province_id) if state else null
	return p.name if p else "a place not on the map"

func _not_my_turn() -> String:
	if session.current_player() == faction_id:
		return ""
	var f: Faction = state.find_faction(faction_id) if state else null
	return "It is not %s's turn, so these orders can't be changed now." % (f.faction_name if f else "this player")


func _move_forecast_at(index: int) -> Dictionary:
	var list := orders()
	var others := list.duplicate()
	others.remove_at(index)
	return Forecast.move(view_state(), faction_id, list[index], others)


func _recruit_result_at(index: int) -> Dictionary:
	var list := orders()
	var k := 0
	for i in index:
		if list[i] is RecruitOrder:
			k += 1
	return gold_after_recruits().results[k]


func _unit_name(unit_type_id: String) -> String:
	var f := state.find_faction(faction_id)
	var ut: UnitType = TurnResolver.recruitable_type(f, unit_type_id) if f else null
	return ut.name if ut else "unknown unit"


func _capital_name() -> String:
	var f := state.find_faction(faction_id)
	var p: Province = state.find_province(f.capital) if f else null
	return p.name if p else "your capital"


static func _bd(title: String, description: String, lines: Array, total_label: String, total: int) -> Dictionary:
	return {"title": title, "description": description, "lines": lines, "total_label": total_label, "total": total}


static func _line(label: String, value: int, note: String) -> Dictionary:
	return {"label": label, "value": value, "note": note}
