class_name PlanModel
extends RefCounted
## UX-5 (design/UX_WAR_TABLE.md §5.3): the Chronicle's Plan side, as pure code: what the Plan page lists for the person giving
## orders. It reads only an OrdersController (the viewer's own orders this turn, priced and forecast on the state as the viewer sees
## it) and ChronicleModel, so every word is one the tray, the board's marks and the cards already say:
##   - the sentences: the placed orders by their number (the tray's, OrdersController.number_of), then the realm orders. Each is the
##     order's own sentence with its forecast (OrdersController.order_text: the battle odds of a march into a fight, a recruit's price
##     and the gold it leaves, research's finish turn), and its tooltip is the tray token's (OrderMarks.tip: the sentence, the breakdown
##     behind its numbers, the numbering note). Nothing here forecasts anything itself.
##   - the checks: the current-state needs as Needs-you cards, from the one pure function the Read side uses (ChronicleModel.needs and
##     need_items), so an order queued this turn that answers a need takes its card away on both sides. (The spec calls these "today's
##     end-turn warnings"; the game has none besides these needs.)
##   - the gold after the orders (OrdersController.gold_after_recruits, the tray's last token).
##
## A SENTENCE is {"index" (into orders()), "number" (0 for a realm order), "realm", "class" (OrderMarks.class_of), "title" (its class's
## name: "March"), "icon" (UiIcons), "text", "tip", "codex" (its codex entry), "place" (the province its board mark stands in, "" for a
## realm order)}.

## When the seal opens the Plan first: ChronicleSettings.review, and whether this is the player's first game.
static func review_on(mode: String, first_game: bool) -> bool:
	return mode == "always" or (mode == "first_game" and first_game)


## Every order `c` has queued, as sentences: the placed ones by number, then the realm ones in the order they were given.
static func sentences(c: OrdersController) -> Array:
	var out := []
	if c == null or c.state == null:
		return out
	for i in c.placed_indices() + c.realm_indices():
		out.append(sentence(c, int(i)))
	return out


static func sentence(c: OrdersController, index: int) -> Dictionary:
	var o = c.orders()[index]
	var cls := OrderMarks.class_of(o)
	var number := c.number_of(index)
	return {"index": index, "number": number, "realm": number == 0, "class": cls, "title": String(OrderMarks.CLASS_NAME.get(cls, "Order")),
		"icon": String(OrderMarks.CLASS_ICON.get(cls, "orders")), "text": c.order_text(index), "tip": OrderMarks.tip(c, index),
		"codex": TooltipText.codex_for(c.order_codex_kind(index), c.order_breakdown(index)), "place": OrderMarks.place_of(c, index)}


## The checks: the viewer's current-state needs (ChronicleModel.needs, with the orders queued now) as Needs-you announcements.
static func checks(state: GameState, viewer: String, report_turn: int, orders: Array) -> Array:
	if state == null or viewer.is_empty():
		return []
	return ChronicleModel.need_items(ChronicleModel.needs(state, viewer, report_turn, orders), state, report_turn)


## The Plan as the page draws it: {"sentences", "checks", "gold" (the gold after the orders, in words), "gold_tip"}. Empty lists and
## words for nobody (no controller, or nobody in particular looking).
static func build(c: OrdersController, state: GameState, viewer: String, report_turn: int) -> Dictionary:
	if c == null or c.state == null or viewer.is_empty():
		return {"sentences": [], "checks": [], "gold": "", "gold_tip": ""}
	var g := c.gold_after_recruits()
	return {"sentences": sentences(c), "checks": checks(state, viewer, report_turn, c.orders()), "gold": String(g.get("text", "")),
		"gold_tip": TooltipText.from_breakdown(c.gold_breakdown())}
