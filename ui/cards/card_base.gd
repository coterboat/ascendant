class_name CardBase
extends VBoxContainer
## UX-3 (design/UX_WAR_TABLE.md §3): the base of the selection cards' content (the army card, the province card, the orders
## list). A card is built for one selection from the map screen's own state and orders, in the style of the side panel it
## replaces: a line of text is a Label whose tooltip is its breakdown, and every number links its codex entry. What a card
## reads is what the map screen shows (the viewer's state, under fog the viewer's view), never anything more; what a button
## does goes back through the map screen's own order API (queue_move, queue_recruit_at, set_storm, cancel_order, ...), so every
## order is checked by the same rules a click always got.
##
## `map` is the screen that shows the card. state, orders and viewing_faction_id are its own, read live.

## A unit's face in a list row, and a recruit button's.
const ROW_PORTRAIT := Vector2(44, 44)

var map: MapScreen
## The controls the card keeps in view whatever its height: its action buttons. SelectionCards lifts them out of the scrolling
## content, under the card's header, so the Table's "nothing a click needs ever hides" holds for the card's first action even when
## the card is squeezed (a card built on its own, in a test, keeps them where they were built).
var pinned_nodes: Array = []
## True for the card of an army of yours: it shows the hover forecast of a march destination in a slot under its actions (SelectionCards).
var wants_forecast := false

var state: GameState:
	get:
		return map.state
var orders: OrdersController:
	get:
		return map.orders
var viewing_faction_id: String:
	get:
		return map.viewing_faction_id


func _init() -> void:
	add_theme_constant_override("separation", 8)


## A line of text with a tooltip (labels with tooltips take the mouse so the tooltip shows), wrapping.
func add_text(text: String, tooltip: String, color: Color = UiPalette.TEXT_PRIMARY, parent: Control = null) -> Label:
	var l := Label.new()
	l.text = text
	l.tooltip_text = tooltip
	l.mouse_filter = Control.MOUSE_FILTER_PASS if not tooltip.is_empty() else Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", color)
	(parent if parent != null else self).add_child(l)
	return l


func add_heading(text: String, font_size: int, parent: Control = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", UiPalette.GILT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(parent if parent != null else self).add_child(l)
	return l


## Links a label to the codex entry for its kind of number (TooltipText.CODEX).
func link(control: Control, kind: String, breakdown: Dictionary = {}) -> void:
	CodexLink.attach(control, TooltipText.codex_for(kind, breakdown), map.request_codex)


## Links a control to the codex entry `key` itself.
func link_key(control: Control, key: String) -> void:
	CodexLink.attach(control, key, map.request_codex)


## The last order's result, as the side panel showed it: the rules' reason when an order was refused, or what was ordered.
## Nothing when there is nothing to say.
func add_status() -> Label:
	if map.status_text.is_empty():
		return null
	var status := add_text(map.status_text, TooltipText.plain("Order check",
		"Orders are checked with the same rules the turn uses, so a refused order would fail at the end of the turn too."), UiPalette.GILT)
	status.name = "StatusLabel"
	link(status, "order_check")
	return status


## A row in a card: the unit's portrait (its face, with a count badge for more than one), then the caller's label. Returns the row.
func unit_row(parent: Control, unit_type_id: String, faction_id: String, count: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "UnitRow_%s" % unit_type_id.validate_node_name()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var card := Art.portrait_card(unit_type_id, ROW_PORTRAIT, faction_id, Art.Crop.FACE)
	card.texture = Art.unit_portrait(state, faction_id, unit_type_id)
	card.count = count
	row.add_child(card)
	return row


## A raised card around a section, with a coloured border.
static func raised_style(border: Color, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_RAISED
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	return style


## An action button of a card: an icon (UX-0a's UiIcons) and a word, tinted with the button's colours, and the explanation.
func action_button(node_name: String, label: String, icon_name: String, tooltip: String, codex_key: String = "") -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = label
	if not icon_name.is_empty():
		b.icon = UiIcons.icon(icon_name, 20)
		b.expand_icon = false
		b.add_theme_color_override("icon_normal_color", UiPalette.TEXT_PRIMARY)
		b.add_theme_color_override("icon_hover_color", UiPalette.GILT)
		b.add_theme_color_override("icon_pressed_color", UiPalette.GILT)
		b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.4))
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tooltip
	b.add_theme_font_size_override("font_size", UiPalette.TYPE_BODY)
	b.custom_minimum_size = Vector2(0, 36)
	if not codex_key.is_empty():
		link_key(b, codex_key)
	return b


# --- order lines (the orders list and the army card share them) --------------------------------------

## One order's line in `parent`: its text with the forecast, the breakdown as its tooltip, linked to its codex entry. Named
## OrderLine, as the side panel's was. Returns the label.
func add_order_line(parent: Control, index: int) -> Label:
	var line := add_text(orders.order_texts()[index], TooltipText.from_breakdown(orders.order_breakdown(index)), UiPalette.TEXT_PRIMARY, parent)
	line.name = "OrderLine"
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	link(line, orders.order_codex_kind(index))
	return line


## M3c S-3: under the line of a move into an enemy fort, "Besiege, or Storm now": the fort's storm (one per fort). `after` is the
## node the row goes after in `parent`; it is added at the end when null.
func add_storm_now_row(parent: Control, index: int, after: Node = null) -> HBoxContainer:
	var besieged := orders.storm_target(index)
	if besieged.is_empty():
		return null
	var sub := HBoxContainer.new()
	sub.name = "StormNowRow_%d" % index
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(16, 0)
	sub.add_child(pad)
	sub.add_child(storm_now_toggle(besieged))
	parent.add_child(sub)
	if after != null and after.get_parent() == parent:
		parent.move_child(sub, after.get_index() + 1)
	return sub


## M3c S-3: "Storm now" on the order line of a move into an enemy fort: the fort's storm (one per fort).
func storm_now_toggle(province_id: String) -> CheckBox:
	var t := CheckBox.new()
	t.name = "StormNowToggle"
	t.text = "Storm now"
	t.focus_mode = Control.FOCUS_NONE
	t.button_pressed = orders.storm_index(province_id) >= 0
	var check := orders.storm_check(province_id)
	var p := state.find_province(province_id)
	var tip := "Off: your armies besiege %s and the walls drop each turn. On: every army of yours there storms it this turn, from the march, against its walls (+%d defense) and its %s." % [
		p.name, SiegeRules.walls_defense(p.walls), p.terrain]
	if not check.is_empty():
		t.disabled = true
		tip = "%s %s" % [String(check.reason), tip]
	t.tooltip_text = TooltipText.plain("Besiege or storm now", "%s %s" % [tip, RulesCodex.text("storm")])
	CodexLink.attach(t, "storm", map.request_codex)
	t.toggled.connect(func(on: bool): map.set_storm(province_id, on))
	return t


## King's Roads: the road move at `index` offers another way through. Returns the button's tooltip text ("" when there is none).
func via_tooltip(index: int) -> String:
	var vias := orders.road_vias_at(index)
	if vias.size() < 2:
		return ""
	var o: MoveOrder = orders.orders()[index]
	var next: String = vias[(vias.find(o.via) + 1) % vias.size()]
	return TooltipText.plain("Another way through",
		"This road move goes through %s. Click to go through %s instead; it arrives at the same time either way. %s" % [
			state.find_province(o.via).name, state.find_province(next).name, RulesCodex.text("road_move")])


## "Gold after recruits: 38" with its breakdown: the orders list ends with it and so does the recruit section.
func add_gold_after(parent: Control) -> Label:
	var g := orders.gold_after_recruits()
	var gold := add_text("%s: %d" % ["Gold after recruits and rituals" if int(g.get("rituals", 0)) > 0 else "Gold after recruits", g.gold_after],
		TooltipText.from_breakdown(orders.gold_breakdown()), UiPalette.GILT, parent)
	gold.name = "GoldAfterLabel"
	link(gold, "gold_after_recruits")
	return gold
