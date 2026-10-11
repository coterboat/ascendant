class_name OrdersCard
extends CardBase
## UX-3 (design/UX_WAR_TABLE.md §3.4, "until UX-4"): the side panel's "Your orders this turn" list, kept as it was: each order
## with its forecast and a cancel button, King's Roads' other-way button, Storm now under a move into an enemy fort, and the
## gold left after recruits and rituals. The tray's Orders button shows it in the card's place (SelectionCards.open_orders), so
## no order is ever out of reach; UX-4 moves the orders onto the board and into the tray, and this list goes with it.
## The recruit buttons moved to the province card (RecruitSection), and an army's own order to its card (ArmyCard).


## The orders list for `host`'s viewing faction, or a card with just a note when there is no one to give orders.
static func make(host: MapScreen) -> OrdersCard:
	var card := OrdersCard.new()
	card.map = host
	card._build()
	return card


func _init() -> void:
	super()
	name = "OrdersCard"


func _build() -> void:
	var f: Faction = state.find_faction(viewing_faction_id) if state else null
	if orders == null or f == null:
		return
	add_heading("Your orders this turn", 20)
	add_status()
	var texts := orders.order_texts()
	if texts.is_empty():
		add_text("No orders yet. Select one of your armies and press March, then click a neighboring province. Select your capital and press Recruit.",
			"", UiPalette.TEXT_SECONDARY)
	for i in texts.size():
		var row := HBoxContainer.new()
		row.name = "Order_%d" % i
		add_child(row)
		var line := add_order_line(row, i)
		line.custom_minimum_size.x = 300
		var tip := via_tooltip(i)
		if not tip.is_empty():
			# King's Roads: the first way through is picked by province id; the player can choose another.
			var via_button := Button.new()
			via_button.name = "ViaButton"
			via_button.text = "↻"
			via_button.tooltip_text = tip
			via_button.focus_mode = Control.FOCUS_NONE
			via_button.pressed.connect(map.change_via.bind(i))
			link_key(via_button, "road_move")
			row.add_child(via_button)
		add_storm_now_row(self, i, row)
		var cancel := Button.new()
		cancel.name = "CancelButton"
		cancel.text = "✕"
		cancel.tooltip_text = "Cancel this order. Nothing happens until the turn ends, so you can change your mind."
		cancel.focus_mode = Control.FOCUS_NONE
		cancel.pressed.connect(map.cancel_order.bind(i))
		row.add_child(cancel)
	add_gold_after(self)

