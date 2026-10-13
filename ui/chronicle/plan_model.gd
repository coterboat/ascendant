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
## name: "March"), "icon" (UiIcons), "text" (the whole sentence, order_text), "head" (its first sentence: the order itself, with its
## price or finish turn), "forecast" (a march into a fight: the battle odds line as order_text has it, cut to its first sentence; "" for
## the rest), "tip", "codex" (its codex entry), "place" (the province its board mark stands in, "" for a realm order)}. The page shows
## the head and the forecast, the whole sentence and its breakdown on hover: the essential line visible, the rest a hover away.

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
	var text := c.order_text(index)
	var forecast := ""
	if o is MoveOrder:
		var odds := c.move_odds(o.army_id, o.to)
		var line := String(odds.get("line", ""))
		if (bool(odds.get("enemy_present", false)) or bool(odds.get("fog", false))) and line != OrdersController.NO_ENEMY_TEXT and text.contains(line):
			forecast = first_sentence(line).get_slice(" ⓘ", 0).strip_edges()  # the fog forecast's ⓘ: its guesses are in the tooltip
	var head := first_sentence(text)
	if not forecast.is_empty() and head.contains(forecast):
		forecast = ""
	return {"index": index, "number": number, "realm": number == 0, "class": cls, "title": String(OrderMarks.CLASS_NAME.get(cls, "Order")),
		"icon": String(OrderMarks.CLASS_ICON.get(cls, "orders")), "text": text, "head": head, "forecast": forecast,
		"tip": OrderMarks.tip(c, index), "codex": TooltipText.codex_for(c.order_codex_kind(index), c.order_breakdown(index)),
		"place": OrderMarks.place_of(c, index)}


## The first sentence of `text`: up to the first full stop outside brackets that is followed by a space and a capital letter or a digit
## (so "(Spearmen, Knights)" and "1.5" stay whole). The whole text when it is one sentence.
static func first_sentence(text: String) -> String:
	var depth := 0
	for i in text.length():
		var ch := text[i]
		if ch == "(":
			depth += 1
		elif ch == ")":
			depth = maxi(0, depth - 1)
		elif ch == "." and depth == 0 and i + 2 < text.length() and text[i + 1] == " ":
			var nx := text[i + 2]
			if nx == nx.to_upper() and nx != nx.to_lower() or nx.is_valid_int():
				return text.substr(0, i + 1)
	return text


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
