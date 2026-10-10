class_name SelectionCards
extends PanelContainer
## UX-3 (design/UX_WAR_TABLE.md §3, issue #206): the selection cards. A province and an army are two distinct sides: click land and
## the province card (ProvinceCard) manages the land, its fort and its recruitment; click an army and the army card (ArmyCard)
## manages troops, where they go, and which armies join. This is the SelectionHost's presenter: it replaces UX-1's temporary
## details card (the side panel's content re-homed), and is the one piece the Table (TableHud) places in the card slot, docked in
## the left column under the guide and the notice, inside the board's safe area.
##
## What it holds, one at a time:
##   "province"   the province card for the selected province
##   "army"       the army card for the selected army
##   "orders"     the orders list (OrdersCard), opened by the tray's Orders button: today's "Your orders this turn" with its cancel
##                buttons, until UX-4 moves orders onto the board. Picking something else shows that card instead.
## and, over any of them while you choose where an army marches, the march strip: "March: pick a province · Esc to cancel", a slim
## strip docked in the card's place (§3.3: no card covers the board while targeting, so there is nothing to dodge). The map screen
## registers it with UiCancel as the "march" layer, so Esc and a right-click on empty board end the targeting and bring the card back.
##
## It is closable: the close button, Esc and a right-click on empty board (UiCancel's "card" step) hide it and put your army back to
## unselected, so a click on a neighbour never gives an order you can't see. The province stays selected: the board's close-up
## depends on it. The tray's Orders button shows the orders list again.
##
## Sections a card opens (Recruit, the fort panel, an army's siege panel) are remembered here by name (section_open /
## open_section), so an order that rebuilds the card keeps them open; they close when another province or army is selected,
## except when the Recruit picker moves between your forts (carry_sections).
##
## The Table's placement protocol (as the temporary card had it): fit(max_height), desired_height(), layout_wanted.

signal closed
## The height it needs changed: the TableHud places it again.
signal layout_wanted
## March targeting began or ended.
signal marching_changed(on: bool)

## The least height the scrolling content is squeezed to (the pinned actions above it never are).
const SCROLL_MIN := 24.0

var map: MapScreen
## Under the header: the card's pinned actions, then the scrolling card. map.details: every control of the open card is under it.
var details: VBoxContainer
var pinned: VBoxContainer  # the open card's action buttons, kept in view (CardBase.pinned_nodes)
var scroll: ScrollContainer
var holder: VBoxContainer  # the open card, in the scroll
var close_button: Button
var back_button: Button
var title_label: Label
## "province", "army", "orders" or "" (nothing shown).
var mode := ""
## Hidden by the player (the close button or UiCancel) until something else is selected.
var dismissed := false
## True while the player picks a march destination: the card is a slim strip.
var marching := false
## The next selection keeps the open sections (the Recruit picker moves between your forts).
var carry_sections := false

var strip: PanelContainer
var strip_label: Label
var strip_note: Label
var strip_cancel: Button

var _box: VBoxContainer
var _header: HBoxContainer
var _kind := ""
var _id := ""
var _province := ""
var _march_army := ""
var _march_turn := -1  # the turn and the seat the pick began in: a new turn or another seat ends it
var _march_viewer := ""
var _return_to_selection := false
var _sections := {}
var _want_queued := false
var _scroll_to := ""


func _init() -> void:
	name = "SelectionCards"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(TableLayout.CARD_W, 0)
	var style := UiPalette.panel_style()
	style.bg_color = Color(UiPalette.PANEL_BG, 0.97)
	style.content_margin_left = 14
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)
	_box = VBoxContainer.new()
	_box.name = "Box"
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 4)
	add_child(_box)
	_header = HBoxContainer.new()
	_header.name = "Header"
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_header)
	title_label = Label.new()
	title_label.name = "CardTitle"
	title_label.text = "Selection"
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	title_label.add_theme_color_override("font_color", UiPalette.TEXT_SECONDARY)
	_header.add_child(title_label)
	back_button = Button.new()
	back_button.name = "BackToCardButton"
	back_button.text = "‹ Back to the card"
	back_button.flat = true
	back_button.visible = false
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	back_button.tooltip_text = "Back to the card of what you selected."
	back_button.pressed.connect(dismiss)
	_header.add_child(back_button)
	close_button = Button.new()
	close_button.name = "CloseCardButton"
	close_button.text = "✕"
	close_button.flat = true
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.tooltip_text = "Close this card (Esc). Click the land or an army again to bring it back, or press Orders to see your orders."
	close_button.pressed.connect(_on_close_pressed)
	_header.add_child(close_button)
	details = VBoxContainer.new()
	details.name = "Details"
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 6)
	_box.add_child(details)
	pinned = VBoxContainer.new()
	pinned.name = "Pinned"
	pinned.add_theme_constant_override("separation", 6)
	details.add_child(pinned)
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(scroll)
	holder = VBoxContainer.new()
	holder.name = "Holder"
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_theme_constant_override("separation", 8)
	scroll.add_child(holder)
	holder.minimum_size_changed.connect(_want_layout)
	pinned.minimum_size_changed.connect(_want_layout)
	_build_strip()


## The slim strip shown instead of the card while a march destination is picked.
func _build_strip() -> void:
	strip = PanelContainer.new()
	strip.name = "MarchStrip"
	strip.visible = false
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(strip)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	strip.add_child(col)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var icon := TextureRect.new()
	icon.name = "MarchIcon"
	icon.texture = UiIcons.icon("march", 20)
	icon.self_modulate = UiPalette.GILT
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(22, 22)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	strip_label = Label.new()
	strip_label.name = "MarchLabel"
	strip_label.text = "March: pick a province · Esc to cancel"
	strip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	strip_label.add_theme_font_size_override("font_size", UiPalette.TYPE_BODY)
	strip_label.add_theme_color_override("font_color", UiPalette.GILT)
	strip_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(strip_label)
	strip_cancel = Button.new()
	strip_cancel.name = "MarchCancelButton"
	strip_cancel.text = "✕"
	strip_cancel.flat = true
	strip_cancel.focus_mode = Control.FOCUS_NONE
	strip_cancel.tooltip_text = "Stop choosing a destination (Esc). The army stays selected and keeps its place."
	strip_cancel.pressed.connect(end_march)
	row.add_child(strip_cancel)
	strip_note = Label.new()
	strip_note.name = "MarchNote"
	strip_note.visible = false
	strip_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	strip_note.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	strip_note.add_theme_color_override("font_color", UiPalette.NEGATIVE.lightened(0.25))
	strip_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(strip_note)
	strip.minimum_size_changed.connect(_want_layout)


# --- the SelectionHost's presenter ----------------------------------------------------------------

func show_province(province_id: String) -> void:
	_select("province", province_id, province_id)


func show_army(army_id: String, province_id: String) -> void:
	_select("army", army_id, province_id)


func clear_selection() -> void:
	_kind = ""
	_id = ""
	_province = ""
	_end_march(false)
	if mode != "orders":
		mode = ""
		visible = false
	_fill()


## Something it shows changed (an order, a new turn): rebuild; hidden or shown stays as it is (a card the player closed stays closed).
## A march pick ends when the army got its order, or is gone.
func refresh_selection() -> void:
	if marching and not _march_is_live():
		_end_march(false)
	_fill()


## The tray's Orders button: the orders list in the card's place, whatever is selected.
func open_orders() -> void:
	_return_to_selection = visible and not dismissed and (mode == "province" or mode == "army")
	_end_march(false)
	if mode != "orders":
		scroll.scroll_vertical = 0
	mode = "orders"
	dismissed = false
	visible = true
	_fill()


## The close button, Esc, a right-click on empty board: the orders list goes back to the card under it when there is one, and
## otherwise the card hides until something is selected again.
func dismiss() -> void:
	if not visible:
		return
	if mode == "orders" and _return_to_selection and not _kind.is_empty():
		mode = _kind
		_return_to_selection = false
		_fill()
		return
	dismissed = true
	mode = ""
	_return_to_selection = false
	visible = false
	_end_march(false)
	closed.emit()


func is_showing() -> bool:
	return visible


## The close button is Esc's "card" step: the map screen closes the card and puts your army back to unselected.
func _on_close_pressed() -> void:
	if map != null:
		map.dismiss_selection_card()
	else:
		dismiss()


# --- march targeting (§3.3) ---------------------------------------------------------------------------

## The army card's March button: the card folds into the slim strip until a destination is picked or Esc ends it.
func begin_march() -> void:
	if mode != "army" or map == null or map.state == null:
		return
	var a: Army = map.state.find_army(_id)
	if a == null or a.owner != map.viewing_faction_id:
		return
	marching = true
	_march_army = _id
	_march_turn = map.state.current_turn
	_march_viewer = map.viewing_faction_id
	strip_note.visible = false
	strip_note.text = ""
	strip_label.tooltip_text = TooltipText.plain("March", "Click a province next to %s (or, with King's Roads, two away) to order the march: its forecast shows when you hover one. Esc, a right-click on empty board or the cross stops choosing and brings the card back. %s" % [
		TurnReportText.army_name(map.state, a.id, a.owner), RulesCodex.text("move")])
	_apply_marching()
	marching_changed.emit(true)


## Esc, a right-click on empty board or the strip's cross: the card comes back.
func end_march() -> void:
	_end_march(true)


## A destination was refused while picking: the strip says why, and the pick goes on.
func march_refused(reason: String) -> void:
	if not marching:
		return
	strip_note.text = reason
	strip_note.visible = not reason.is_empty()
	_want_layout()


func _end_march(refill: bool) -> void:
	if not marching:
		return
	marching = false
	_march_army = ""
	_apply_marching()
	if refill:
		_fill()
	marching_changed.emit(false)


func _apply_marching() -> void:
	_box.visible = not marching
	strip.visible = marching
	_want_layout()


func _march_is_live() -> bool:
	if map == null or map.state == null or mode != "army" or _id != _march_army:
		return false
	if map.state.current_turn != _march_turn or map.viewing_faction_id != _march_viewer:
		return false  # the turn ended, or the table passed to another player: the pick is over
	var a: Army = map.state.find_army(_march_army)
	if a == null or map.orders == null:
		return false
	for o in map.orders.orders():
		if (o is MoveOrder or o is CastOrder) and o.army_id == a.id:
			return false  # it got its order: the march is done
	return true


# --- sections a card opens ----------------------------------------------------------------------------

func section_open(section: String) -> bool:
	return bool(_sections.get(section, false))


## Opens or closes a section of the open card ("recruit", "fort" on a province, "siege" on an army) and rebuilds the card with it.
func open_section(section: String, on: bool = true) -> void:
	if section_open(section) == on:
		return
	_sections[section] = on
	if on:
		_scroll_to = section
	_fill()
	if on and section == "recruit":
		scroll.scroll_vertical = 0  # the section sits right under the action row, at the top: show the card from its top


func open_sections() -> Dictionary:
	return _sections.duplicate()


# --- size -----------------------------------------------------------------------------------------

## Called by the TableHud before it places the card: the card may be at most `max_height` tall; its scroll gets the
## height its content needs up to that.
func fit(max_height: float) -> void:
	var header_h := _header.get_combined_minimum_size().y + 4.0
	var style := get_theme_stylebox("panel")
	var padding := style.get_margin(SIDE_TOP) + style.get_margin(SIDE_BOTTOM)
	# However squeezed, the pinned actions stay whole and the scroll keeps a sliver: the card never grows past the rect it was given.
	var room := maxf(max_height - header_h - padding - _pinned_height(), SCROLL_MIN)
	var want := clampf(holder.get_combined_minimum_size().y, SCROLL_MIN, room)
	if not is_equal_approx(scroll.custom_minimum_size.y, want):
		scroll.custom_minimum_size.y = want


## The height the card asks for now (its content, its header and its padding), before the cap. The strip is as tall as it is.
func desired_height() -> float:
	var style := get_theme_stylebox("panel")
	var padding := style.get_margin(SIDE_TOP) + style.get_margin(SIDE_BOTTOM)
	if marching:
		return strip.get_combined_minimum_size().y + padding
	var header_h := _header.get_combined_minimum_size().y + 4.0
	return holder.get_combined_minimum_size().y + _pinned_height() + header_h + padding


# --- internals ------------------------------------------------------------------------------------

func _select(kind: String, id: String, province: String) -> void:
	var same := kind == _kind and id == _id and province == _province
	if not same and not carry_sections:
		_sections.clear()
	if not same or mode != kind:
		scroll.scroll_vertical = 0  # a new card starts at its top
	carry_sections = false
	_end_march(false)
	_kind = kind
	_id = id
	_province = province
	mode = kind
	dismissed = false
	_return_to_selection = false
	visible = true
	_fill()


## The height of the pinned actions and the gap under them.
func _pinned_height() -> float:
	if not pinned.visible:
		return 0.0
	var h := pinned.get_combined_minimum_size().y
	return h + (float(details.get_theme_constant("separation")) if h > 0.0 else 0.0)


func _fill() -> void:
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	for child in pinned.get_children():
		pinned.remove_child(child)
		child.queue_free()
	back_button.visible = mode == "orders" and _return_to_selection
	if map != null and map.state != null:
		var card: CardBase = null
		match mode:
			"orders":
				card = OrdersCard.make(map)
				title_label.text = "Orders"
			"army":
				card = ArmyCard.make(map, _id)
				title_label.text = "Army"
			"province":
				card = ProvinceCard.make(map, _province)
				title_label.text = "Province"
		if card != null:
			holder.add_child(card)
			_lift_pinned(card)
	pinned.visible = pinned.get_child_count() > 0  # an empty slot would still take the gap under it
	_want_layout()
	if not _scroll_to.is_empty():
		var target := _scroll_to
		_scroll_to = ""
		_scroll_after_layout(target)


## The card's action buttons move out of the scrolling content into the pinned slot above it, in the order the card made them.
func _lift_pinned(card: CardBase) -> void:
	for node in card.pinned_nodes:
		if is_instance_valid(node) and node.get_parent() != null:
			node.get_parent().remove_child(node)
			pinned.add_child(node)


## After an open section was built, scrolls it into view once the containers have sorted it (two frames on; no frames, no scroll,
## in a headless test).
func _scroll_after_layout(section: String) -> void:
	var node_name := {"fort": "FortFrame", "siege": "SiegeFrame"}.get(section, "") as String
	if node_name.is_empty() or not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(details) or not is_instance_valid(scroll):
		return
	var node := details.find_child(node_name, true, false) as Control
	if node != null and node.visible:
		scroll.ensure_control_visible(node)


func _want_layout() -> void:
	if _want_queued:
		return
	_want_queued = true
	_emit_layout.call_deferred()


func _emit_layout() -> void:
	_want_queued = false
	layout_wanted.emit()
