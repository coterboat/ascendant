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

## Shown instead of battle odds when no enemy army is in the destination (M1 has no fog of war).
const NO_ENEMY_TEXT := "No enemy army there now; enemies may still move in."

var state: GameState
var faction_id := ""
var book := OrderBook.new()
var session: GameSession = null
var _odds_cache := {}  # "army ids>province" -> move_odds() result; the state never changes under us


func _init(p_state: GameState = null, p_faction_id: String = "", p_session: GameSession = null) -> void:
	state = p_state
	faction_id = p_faction_id
	session = p_session


## Queues a move. Returns "" when accepted, otherwise the rules' reason it was refused.
func queue_move(army_id: String, to_province: String) -> String:
	if session != null:
		var why := _not_my_turn()
		return why if not why.is_empty() else session.queue_move(army_id, to_province)
	return book.submit(state, faction_id, MoveOrder.new(army_id, to_province))


## Queues one recruit at the capital. Returns "" when accepted, otherwise the rules' reason.
func queue_recruit(unit_type_id: String) -> String:
	if session != null:
		var why := _not_my_turn()
		return why if not why.is_empty() else session.queue_recruit(unit_type_id)
	return book.submit(state, faction_id, RecruitOrder.new(unit_type_id))


## Withdraws the order at `index` (as listed by orders()). Returns "" or why it could not.
func cancel(index: int) -> String:
	if session != null:
		var why := _not_my_turn()
		return why if not why.is_empty() else session.cancel_order(index)
	book.remove(faction_id, index)
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


## Forecast for a move that is not queued yet (catches a second move for the same army).
func move_forecast(army_id: String, to: String) -> Dictionary:
	return Forecast.move(state, faction_id, MoveOrder.new(army_id, to), orders())


## Battle odds for moving `army_id` to `to`, counting every army you have already ordered there.
## Returns {"enemy_present", "odds" (Forecast.battle_odds result, {} when no enemy is there),
## "line" (verdict and main reasons, for the forecast line), "text" (the full odds text, for tooltips)}.
func move_odds(army_id: String, to: String) -> Dictionary:
	var ids := [army_id]
	for o in orders():
		if o is MoveOrder and o.to == to and not ids.has(o.army_id):
			ids.append(o.army_id)
	ids.sort()
	var key := "%s>%s" % [",".join(ids), to]
	if _odds_cache.has(key):
		return _odds_cache[key]
	# Forecast.battle_odds checks for enemy armies there itself (M1 has no fog: all are visible).
	var odds := Forecast.battle_odds(state, faction_id, ids, to)
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


func gold_after_recruits() -> Dictionary:
	return Forecast.gold_after_recruits(state, faction_id, recruit_orders())


func recruit_cost(unit_type_id: String) -> int:
	return Forecast.recruit_cost(state, faction_id, unit_type_id)


## The roster this faction can recruit from at its capital.
func recruitable_types() -> Array:
	var f := state.find_faction(faction_id)
	return f.unit_types.duplicate() if f else []


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
	var r := _recruit_result_at(index)
	if not r.ok:
		return "Not recruited: %s" % r.reason
	return "Recruit one %s at %s for %d gold, leaving %d gold." % [_unit_name(r.unit_type), _capital_name(), r.cost, r.gold_after]


## Breakdown (rules/breakdown.gd shape) behind an order line's numbers, for its tooltip.
func order_breakdown(index: int) -> Dictionary:
	var o = orders()[index]
	if o is MoveOrder:
		var f := _move_forecast_at(index)
		if not f.ok:
			return _bd("Move order", f.reason, [], "Arrives at the start of turn", 0)
		var odds := move_odds(o.army_id, o.to)
		var odds_desc: String = "%s %s" % [odds.text, RulesCodex.text("battle_odds")] if odds.enemy_present else odds.text
		return _bd("Move forecast", "%s %s %s" % [f.text, odds_desc, RulesCodex.text("move")],
			[_line("Turn now", state.current_turn + 1, "turns count from 1"), _line("Moving one province", 1, "armies move one neighboring province per turn")],
			"Arrives at the start of turn", f.arrival_turn)
	var r := _recruit_result_at(index)
	if not r.ok:
		return _bd("Recruit order", r.reason, [], "Gold spent", 0)
	return _bd("Recruit %s" % _unit_name(r.unit_type), "Recruits are paid in the order given. %s" % RulesCodex.text("recruit"),
		[_line("Gold before this recruit", r.gold_after + r.cost, ""), _line("Cost", -r.cost, "")],
		"Gold left after this recruit", r.gold_after)


## Which kind of number an order line is, for its codex link (TooltipText.CODEX): a move into an
## enemy army links to the battle odds, any other move to moving, a recruit to recruiting.
func order_codex_kind(index: int) -> String:
	var list := orders()
	if index < 0 or index >= list.size():
		return ""
	var o = list[index]
	if o is MoveOrder:
		return "move_odds" if move_odds(o.army_id, o.to).enemy_present else "move_order"
	return "recruit"


func gold_breakdown() -> Dictionary:
	var g := gold_after_recruits()
	return _bd("Gold after recruits", g.text, [_line("Gold now", g.gold_now, ""), _line("Queued recruits", -g.spent, "")],
		"Gold after recruits", g.gold_after)


## Tooltip numbers for a recruit button: what one more of this unit would leave you with.
func recruit_breakdown(unit_type_id: String) -> Dictionary:
	var g := gold_after_recruits()
	var cost := recruit_cost(unit_type_id)
	var f := state.find_faction(faction_id)
	var ut: UnitType = TurnResolver.recruitable_type(f, unit_type_id) if f else null
	var desc := "%s %s" % [Breakdown.unit_type_description(ut) if ut else "", RulesCodex.text("recruit")]
	return _bd("Recruit %s" % _unit_name(unit_type_id),
		desc.strip_edges(), [_line("Gold left after queued recruits", g.gold_after, ""), _line("Cost of one %s" % _unit_name(unit_type_id), -cost, "")],
		"Gold left if you recruit it", g.gold_after - cost)


# --- helpers --------------------------------------------------------------------------------------

func _not_my_turn() -> String:
	if session.current_player() == faction_id:
		return ""
	var f: Faction = state.find_faction(faction_id) if state else null
	return "It is not %s's turn, so these orders can't be changed now." % (f.faction_name if f else "this player")


func _move_forecast_at(index: int) -> Dictionary:
	var list := orders()
	var others := list.duplicate()
	others.remove_at(index)
	return Forecast.move(state, faction_id, list[index], others)


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
