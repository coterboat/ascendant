class_name OrdersController
extends RefCounted
## The orders UI's side of issue #6: wraps an OrderBook for the faction at the controls.
## Holds no rules math. Whether an order is allowed comes from OrderBook.submit (the resolver's own
## checks, with their plain-language reasons) and every forecast number comes from Forecast.
## Only reads the GameState, never changes it.

const ODDS_PENDING := "Battle odds: odds not available yet."

var state: GameState
var faction_id := ""
var book := OrderBook.new()


func _init(p_state: GameState = null, p_faction_id: String = "") -> void:
	state = p_state
	faction_id = p_faction_id


## Queues a move. Returns "" when accepted, otherwise the rules' reason it was refused.
func queue_move(army_id: String, to_province: String) -> String:
	return book.submit(state, faction_id, MoveOrder.new(army_id, to_province))


## Queues one recruit at the capital. Returns "" when accepted, otherwise the rules' reason.
func queue_recruit(unit_type_id: String) -> String:
	return book.submit(state, faction_id, RecruitOrder.new(unit_type_id))


## Withdraws the order at `index` (as listed by orders()).
func cancel(index: int) -> void:
	book.remove(faction_id, index)


func orders() -> Array:
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


func gold_after_recruits() -> Dictionary:
	return Forecast.gold_after_recruits(state, faction_id, recruit_orders())


func recruit_cost(unit_type_id: String) -> int:
	return Forecast.recruit_cost(state, faction_id, unit_type_id)


## The roster this faction can recruit from at its capital.
func recruitable_types() -> Array:
	var f := state.find_faction(faction_id)
	return f.unit_types.duplicate() if f else []


func odds_text() -> String:
	return ODDS_PENDING


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
		return "%s %s" % [f.text, ODDS_PENDING] if f.ok else f.reason
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
		return _bd("Move forecast", "%s %s %s" % [f.text, ODDS_PENDING, RulesCodex.text("move")],
			[_line("Turn now", state.current_turn, ""), _line("Moving one province", 1, "armies move one neighboring province per turn")],
			"Arrives at the start of turn", f.arrival_turn)
	var r := _recruit_result_at(index)
	if not r.ok:
		return _bd("Recruit order", r.reason, [], "Gold spent", 0)
	return _bd("Recruit %s" % _unit_name(r.unit_type), "Recruits are paid in the order given. %s" % RulesCodex.text("recruit"),
		[_line("Gold before this recruit", r.gold_after + r.cost, ""), _line("Cost", -r.cost, "")],
		"Gold left after this recruit", r.gold_after)


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
