class_name OrderCard
extends CardBase
## UX-4 (design/UX_WAR_TABLE.md §3.4, issue #213): the card a tray token (or an order's mark on the board) opens: one queued order, in
## the card's place beside the selection cards. It shows the order as the orders list used to show it: its number and its sentence with
## the forecast, the breakdown behind its numbers on hover, the codex link. Its actions are the ones that order really has:
##   Change route   a road move with another way through (King's Roads; change_via sends it to the end of the list, so it is renumbered)
##   Storm now      under a move into an enemy fort: storm from the march, or besiege (the fort's storm order, one per fort)
##   Change         a realm order (research, spellbook, mandate): opens its panel, and a new choice replaces the old one in place
##   Cancel order   (Cancel muster for a split, merge or swap) takes it back; the orders after it move up one number
## Everything goes back through the map screen's own order API, so every change is checked by the same rules as any click.
##
## The card follows the ORDER, not its number: it holds the order object, so when another order is cancelled and this one's number
## moves up, the card shows its new number. `found` is false when the order is no longer queued (cancelled, or a new turn): the host
## then shows the card it came from.

var order = null
var index := -1
var found := false
var actions: HFlowContainer = null
var cancel_button: Button = null
var route_button: Button = null
var change_button: Button = null


static func make(host: MapScreen, p_order) -> OrderCard:
	var card := OrderCard.new()
	card.map = host
	card.order = p_order
	card._build()
	return card


func _init() -> void:
	super()
	name = "OrderCard"


func _build() -> void:
	index = orders.orders().find(order) if orders != null and order != null else -1
	found = index >= 0
	if not found:
		add_heading("That order is gone", 20)
		add_text("It was cancelled, or the turn ended.", "", UiPalette.TEXT_SECONDARY)
		return
	var mark := OrderMarks.mark_at(orders, index)
	var number := int(mark.get("number", 0))
	var heading := "Order %d · %s" % [number, String(OrderMarks.CLASS_NAME.get(String(mark["class"]), ""))] if number > 0 \
		else "%s · a realm order" % String(OrderMarks.CLASS_NAME.get(String(mark["class"]), ""))
	var title := add_heading(heading, 20)
	title.name = "OrderHeading"
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	title.tooltip_text = TooltipText.plain(heading, OrderMarks.REALM_NOTE if number == 0 else OrderMarks.RENUMBER_NOTE)
	link(title, "order_check")
	add_status()
	var line := add_order_line(self, index)
	line.add_theme_font_size_override("font_size", 16)
	add_storm_now_row(self, index)
	var note := add_text(OrderMarks.REALM_NOTE if number == 0 else "Number %d is this order's place in your list. Cancel or change an order and the ones after it move up." % number,
		TooltipText.plain("Numbers", OrderMarks.RENUMBER_NOTE), UiPalette.TEXT_SECONDARY)
	note.name = "NumberNote"
	note.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	link(note, "order_check")
	_add_actions(mark)


func _add_actions(mark: Dictionary) -> void:
	actions = HFlowContainer.new()
	actions.name = "OrderActions"
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	add_child(actions)
	pinned_nodes.append(actions)
	# Change route: only for a road move with another way through (King's Roads or Forest Stride).
	var tip := via_tooltip(index)
	if not tip.is_empty():
		route_button = action_button("ViaButton", "Change route", "", tip, "road_move")
		route_button.pressed.connect(_change_route)
		actions.add_child(route_button)
	# Change: a realm order opens the panel that sets it; the new choice replaces the old one in place.
	if bool(mark.realm):
		change_button = action_button("ChangeButton", "Change", String(mark.icon), "", _realm_codex(order))
		change_button.tooltip_text = TooltipText.plain("Change", _realm_change_help(order))
		change_button.pressed.connect(_change_realm)
		actions.add_child(change_button)
	var muster := order is MusterOrder
	cancel_button = action_button("CancelButton", "Cancel muster" if muster else "Cancel order", "dismiss", "Cancel this order. Nothing happens until the turn ends, so you can change your mind. The orders after it move up one number.")
	if muster:
		cancel_button.tooltip_text = TooltipText.plain("Cancel muster", "Cancel this split, merge or swap. Orders that rely on it, like a move for the army it formed, go with it, and the status line says which. Nothing happens until the turn ends. The orders after it move up one number.")
	cancel_button.pressed.connect(func(): map.cancel_order(index))
	actions.add_child(cancel_button)


## The codex entry behind a realm order's Change button.
static func _realm_codex(o) -> String:
	if o is ResearchOrder:
		return TooltipText.codex_for("research_order")
	if o is SpellbookOrder:
		return TooltipText.codex_for("spellbook_order")
	return TooltipText.codex_for("sacrifice")


static func _realm_change_help(o) -> String:
	if o is ResearchOrder:
		return "Open the research panel and pick another target: the new pick replaces this one, in place. Nothing is spent until the turn ends."
	if o is SpellbookOrder:
		return "Open the Magic panel and set the battle spellbook again: the new order replaces this one, in place."
	return "Open the sacrifice dialog to pick another mandate: the new pick replaces this one, in place. Nothing is given up until the turn ends."


## King's Roads: sends the road move through its other way. The order goes to the end of the list (renumbered), and the card follows it.
func _change_route() -> void:
	var was: MoveOrder = order
	map.change_via(index)
	var list := orders.orders()
	for i in range(list.size() - 1, -1, -1):
		if list[i] is MoveOrder and list[i].army_id == was.army_id and list[i].to == was.to:
			map.cards.open_order(list[i])
			return


## A realm order's own panel: research and the spellbook have a button in the system row, a mandate its dialog.
func _change_realm() -> void:
	if order is SacrificeOrder:
		map.open_sacrifice_dialog(order.mandate_id)
		return
	var button: Button = map.table().system_button("research" if order is ResearchOrder else "magic")
	if button != null and not button.disabled:
		button.pressed.emit()
