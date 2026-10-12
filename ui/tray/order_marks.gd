class_name OrderMarks
extends RefCounted
## UX-4 (design/UX_WAR_TABLE.md §3.4, issue #213): what each queued order of the viewing faction looks like on the board and in the
## tray. Pure: no nodes, and it only reads the OrdersController (which reads the GameState), so the numbers, the places and the words
## are tested without a scene and the two boards and the tray all draw from the same list.
##
## A MARK is one dictionary per queued order, in orders() order:
##   index     the order's index in orders()
##   number    its number: its place among the placed orders plus one, 0 for a realm order (research, spellbook, mandate)
##   class     "march", "recruit", "fortify", "siege" (a storm or a sally), "ritual", "muster" (a split, transfer, merge or swap),
##             "research", "spellbook" or "mandate"
##   realm     true for the three that have no number
##   icon      the UiIcons name the token wears
##   label     the tray token's short words ("Westwatch", "Spearmen", "Merge")
##   board     the board token's short words ("+2 units", "Keep", "Storm"); "" for a march, whose token is its number alone
##   place     the province the order's mark stands in and a click on its token focuses: where the army starts a march, the fort a
##             recruit is made at, the province fortified, stormed or the target of a ritual, the province a muster happens in;
##             "" for a realm order, which stands nowhere
##   army      the army it is about (a march, a sally, a ritual's caster, a muster's source), "" when it has none
##   to, via   a march's destination and the province a road move goes through
##   units     a recruit's one unit
## A BOARD MARK folds every recruit made at one place into one token (several recruits at a capital are one block of ghosts), and
## has "indices", "numbers" and "units" instead of one index and number (board_marks).
##
## A number is a place in the list, never an id: cancelling an order or change_via (which sends a road move to the end) re-flows
## the rest. A new list is read from the controller each time (marks), so nothing here can go stale.

const CLASS_ICON := {
	"march": "march", "recruit": "recruit", "fortify": "walls", "siege": "siege", "ritual": "magic", "muster": "muster",
	"research": "research", "spellbook": "codex", "mandate": "ruler",
}
## The plain name of each class, for a token's tooltip title and its card's header.
const CLASS_NAME := {
	"march": "March", "recruit": "Recruit", "fortify": "Fortify", "siege": "Storm or sally", "ritual": "Ritual", "muster": "Muster",
	"research": "Research", "spellbook": "Battle spellbook", "mandate": "Mandate",
}
## What a tooltip ends with: why the numbers move, and what a token without one is.
const RENUMBER_NOTE := "The numbers are places in this list, not names: cancel an order, or send a road move another way (it goes to the end), and the orders after it move up. Right-click a token, or press its cross, to cancel it."
const REALM_NOTE := "A realm order has no number: you give one a turn, and a new one replaces it in place."
## A label longer than this is cut (the tray token's text; the tooltip has the rest).
const LABEL_MAX := 14


## The class of an order (CLASS_ICON's keys).
static func class_of(order) -> String:
	if order is MoveOrder:
		return "march"
	if order is RecruitOrder:
		return "recruit"
	if order is FortifyOrder:
		return "fortify"
	if order is SiegeOrder:
		return "siege"
	if order is CastOrder:
		return "ritual"
	if order is MusterOrder:
		return "muster"
	if order is ResearchOrder:
		return "research"
	if order is SpellbookOrder:
		return "spellbook"
	if order is SacrificeOrder:
		return "mandate"
	return ""


## Every queued order of `c`'s faction as a mark, in orders() order. [] with no controller or no state.
static func marks(c: OrdersController) -> Array:
	var out := []
	if c == null or c.state == null:
		return out
	var list := c.orders()
	var placed := OrdersController.placed_in(list)
	for i in list.size():
		var o = list[i]
		var cls := class_of(o)
		if cls.is_empty():
			continue
		var m := {"index": i, "number": placed.find(i) + 1, "class": cls, "realm": placed.find(i) < 0, "icon": String(CLASS_ICON[cls]),
			"label": "", "board": "", "place": "", "army": "", "to": "", "via": "", "units": 0}
		_describe(c, i, o, m)
		m["label"] = _cut(String(m.label))
		out.append(m)
	return out


## The mark of the order at `index`, or {} when there is none.
static func mark_at(c: OrdersController, index: int) -> Dictionary:
	for m in marks(c):
		if int(m.index) == index:
			return m
	return {}


## The province an order's mark stands in ("" for a realm order or an order that is no longer there).
static func place_of(c: OrdersController, index: int) -> String:
	return String(mark_at(c, index).get("place", ""))


## The marks the BOARD draws: the realm orders are not on the board; every recruit made at one place is one token; each of the
## others is its own. Each has "indices", "numbers" (ascending) and, for a recruit token, "units", and "board" is its words.
static func board_marks(all: Array) -> Array:
	var out := []
	var by_place := {}
	for m in all:
		if bool(m.realm):
			continue
		var board_mark: Dictionary = (m as Dictionary).duplicate()
		board_mark["indices"] = [int(m.index)]
		board_mark["numbers"] = [int(m.number)]
		if String(m["class"]) == "recruit":
			var key := String(m.place)
			if by_place.has(key):
				var into: Dictionary = by_place[key]
				into.indices.append(int(m.index))
				into.numbers.append(int(m.number))
				into.units = int(into.units) + int(m.units)
				into.board = "+%s" % TooltipText.count(int(into.units), "unit")
				continue
			by_place[key] = board_mark
		out.append(board_mark)
	return out


## "3", "3, 6", "3-5": a token's number or numbers in words.
static func numbers_text(numbers: Array) -> String:
	var parts := []
	var i := 0
	while i < numbers.size():
		var j := i
		while j + 1 < numbers.size() and int(numbers[j + 1]) == int(numbers[j]) + 1:
			j += 1
		parts.append(str(numbers[i]) if j == i else ("%d, %d" % [numbers[i], numbers[j]] if j == i + 1 else "%d-%d" % [numbers[i], numbers[j]]))
		i = j + 1
	return ", ".join(parts)


## A token's tooltip: its title ("2 · March" or "Research: a realm order"), the order's sentence with its forecast (order_text), the
## breakdown behind its numbers (order_breakdown), and the note that explains the numbering.
static func tip(c: OrdersController, index: int) -> String:
	var list := c.orders()
	if index < 0 or index >= list.size():
		return ""
	var cls := class_of(list[index])
	var number := c.number_of(index)
	var head := "%d · %s" % [number, String(CLASS_NAME.get(cls, ""))] if number > 0 else "%s · a realm order" % String(CLASS_NAME.get(cls, ""))
	var out := [head, "", TooltipText.wrap_text(c.order_text(index)), "", TooltipText.from_breakdown(c.order_breakdown(index)), "",
		TooltipText.wrap_text(REALM_NOTE if number == 0 else RENUMBER_NOTE)]
	return "\n".join(out)


## The tooltip of a board token that folds several recruits (OrderMarks.board_marks): its numbers, each order's sentence, and what the
## gold comes to.
static func group_tip(c: OrdersController, board_mark: Dictionary) -> String:
	var out := ["%s · %s" % [numbers_text(board_mark.numbers), String(CLASS_NAME.get(String(board_mark["class"]), ""))], ""]
	for i in board_mark.indices:
		out.append(TooltipText.wrap_text("%d. %s" % [c.number_of(int(i)), c.order_text(int(i))]))
		out.append("")
	out.append(TooltipText.wrap_text(String(c.gold_after_recruits().text)))
	out.append("")
	out.append(TooltipText.wrap_text(RENUMBER_NOTE))
	return "\n".join(out)


# --- what each class says -------------------------------------------------------------------------------------------

static func _describe(c: OrdersController, i: int, o, m: Dictionary) -> void:
	var st: GameState = c.state
	var board: GameState = c.view_state()
	if o is MoveOrder:
		var a: Army = board.find_army(o.army_id)
		m.army = o.army_id
		m.to = o.to
		m.via = o.via if o.is_road_move() else ""
		m.place = a.location if a != null else ""
		m.label = _pname(st, o.to)
		m.board = ""  # the board shows only its number, in the middle of the arrow
	elif o is RecruitOrder:
		m.place = recruit_place(c, o)
		m.units = 1
		m.label = _unit_name(c, o.unit_type_id)
		m.board = "+1 unit"
	elif o is FortifyOrder:
		var p: Province = st.find_province(o.province)
		m.place = o.province
		m.label = _pname(st, o.province)
		m.board = SiegeRules.level_name(mini((p.fort_level if p != null else 0) + 1, FortData.MAX_BUILT))
	elif o is SiegeOrder:
		var where: String = o.province
		if o.is_sally():
			var a2: Army = board.find_army(o.army_id)
			m.army = o.army_id
			where = a2.location if a2 != null else ""
		m.place = where
		m.board = "Storm" if o.is_storm() else "Sally"
		m.label = "%s %s" % [m.board, _pname(st, where)]
	elif o is CastOrder:
		var a3: Army = board.find_army(o.army_id)
		m.army = o.army_id
		m.place = o.target if not o.target.is_empty() else (a3.location if a3 != null else "")
		m.label = MagicRules.spell_name(o.ritual)
		m.board = m.label
	elif o is MusterOrder:
		var before: GameState = c.muster_board_before(i)
		var from_army: Army = before.find_army(o.from_army)
		m.army = o.from_army
		m.place = from_army.location if from_army != null else ""
		m.label = muster_word(o)
		m.board = m.label
	elif o is ResearchOrder:
		m.label = AscensionRules.node_name(o.node_id)
	elif o is SpellbookOrder:
		m.label = "Spellbook"
	elif o is SacrificeOrder:
		m.label = RulerRules.mandate_name(o.mandate_id)


## "Split", "Transfer", "Merge" or "Swap": what a muster does, in one word.
static func muster_word(o: MusterOrder) -> String:
	match o.kind:
		MusterOrder.MERGE:
			return "Merge"
		MusterOrder.SWAP:
			return "Swap"
	return "Split" if o.is_new_army() else "Transfer"


## Where a recruit order is made (the board's ghost block stands there): the capital, a fort of the faction's, or where the ruler is
## (Warband Muster). Plan_of_orders in the 3D board reads the same rule.
static func recruit_place(c: OrdersController, o: RecruitOrder) -> String:
	var st: GameState = c.state
	var f: Faction = st.find_faction(c.faction_id)
	if f == null:
		return ""
	if o.is_with_ruler():
		var ra := RulerRules.ruler_army(st, c.faction_id)
		return ra.location if ra != null else ""
	if st.sieges:
		return SiegeRules.recruit_place(st, f, TurnResolver.recruit_at(st, f, o))
	return f.capital


static func _pname(st: GameState, province_id: String) -> String:
	var p: Province = st.find_province(province_id) if st != null else null
	return p.name if p != null else ""


static func _unit_name(c: OrdersController, unit_type_id: String) -> String:
	var f: Faction = c.state.find_faction(c.faction_id)
	var ut: UnitType = TurnResolver.recruitable_type(f, unit_type_id, c.state) if f != null else null
	return ut.name if ut != null else "Unit"


static func _cut(text: String) -> String:
	return text if text.length() <= LABEL_MAX else text.left(LABEL_MAX - 1).strip_edges() + "…"
