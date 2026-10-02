class_name MapScreen
extends Control
## The main map screen (issue #5): the M1 map drawn from a GameState, a top bar with the viewing
## player's gold and the turn, and a side panel with the selected province's details.
## Reads the GameState only and never changes it. Every number on screen has a tooltip with its
## breakdown (rules/breakdown.gd) and a plain-language description, ending with the codex entry that
## explains it: right-click (or F1 while hovering) asks for that entry with codex_requested (#8). In the
## map preview, where no game screen listens, the map opens a codex panel of its own.
## Player colours follow the seat: seat_order() is the session's seat order when there is a session.
##
## API for the orders UI and turn flow:
##   set_state(state, viewing_faction_id)  show a state (rebuilds the map; keeps the selection if it still exists)
##   select_province(id)                   select a province and fill the side panel
##   select_army(id)                       select an army (and its province)
##   focus_province(id)                    select a province and flash it to draw the eye
##   preview_move(id)                      hover preview: what clicking `id` would order for the selected army
##   signal province_selected(id), signal army_selected(id), signal orders_changed
##   signal codex_requested(key)           a linked number or term was right-clicked (or F1)
##
## Hooks for the game screen (#7), which hosts this screen for the player at the controls:
##   session                    set it before set_state(): orders then go through GameSession's books
##   intercept_back             true: the back button emits back_requested instead of leaving
##   add_top_bar_control(c)     puts a HUD control in the top bar, just before the back button
##   set_hint(text)             the short help text in the top bar

signal province_selected(province_id: String)
signal army_selected(army_id: String)
## The viewing player's queued orders changed (queued, refused or cancelled).
signal orders_changed
## The back button was pressed while intercept_back is on.
signal back_requested
## A number or term linked to the codex was right-clicked (or F1 was pressed over it).
signal codex_requested(key: String)

const SIDE_PANEL_WIDTH := 400
const TITLE_SCENE := "res://ui/title_screen.tscn"
const CODEX_SCENE := "res://ui/codex_panel.tscn"
## Added to the army strength tooltip: the number is a size guide, the move forecast has the odds.
const STRENGTH_GUIDE := "For your real chances, select one of your armies next to this one and hover its province: the move forecast fights that battle with the full rules and shows the odds."

var state: GameState = null
var viewing_faction_id := ""
var selected_province_id := ""
var selected_army_id := ""
var regions := {}  # province id -> ProvinceRegion
var orders: OrdersController = null  # issue #6: the viewing faction's orders this turn
var session: GameSession = null  # game screen (#7): when set, orders live in the session's books
var intercept_back := false  # game screen (#7): the host confirms before leaving
var status_text := ""  # last order result: the rules' reason when an order was refused
var arrow_layer: Control  # drawn above the regions: one arrow per queued move
var hover_panel: PanelContainer  # hover preview bar at the bottom of the map
var hover_label: Label
var own_codex: CodexPanel = null  # map preview only: opened when no game screen listens for codex_requested

# Scene nodes, looked up by _bind() rather than @onready so the screen also works before it is in
# the tree (tests build it headless, and callers may set_state() before adding it).
var map_view: Control
var map_canvas: Control
var details: VBoxContainer
var faction_label: Label
var gold_label: Label
var turn_label: Label
var hint_label: Label
var back_button: Button


func _ready() -> void:
	_bind()
	if state == null:
		# Opened straight from the title screen: show a fresh default M1 game from player 1's view.
		state = GameState.new()
		viewing_faction_id = state.factions[0].id
	set_state(state, viewing_faction_id)
	_fit_map()


## Shows `new_state` as seen by `faction_id`. Rebuilds every region; the state is only read.
func set_state(new_state: GameState, faction_id: String) -> void:
	if orders == null or orders.state != new_state or orders.faction_id != faction_id or orders.session != session:
		orders = OrdersController.new(new_state, faction_id, session)
		status_text = ""
	state = new_state
	viewing_faction_id = faction_id
	_bind()
	for child in map_canvas.get_children():
		map_canvas.remove_child(child)
		child.queue_free()
	regions.clear()
	var seats := seat_order()
	for p in state.provinces:
		if not MapLayout.has_position(p.id):
			push_error("The map layout has no position for province '%s'." % p.id)
			continue
		var region := ProvinceRegion.new()
		region.setup(state, p, MapLayout.position_of(p.id), seats)
		region.pressed.connect(select_province)
		region.army_pressed.connect(select_army)
		region.codex_requested.connect(request_codex)
		region.mouse_entered.connect(preview_move.bind(p.id))
		region.mouse_exited.connect(clear_preview)
		map_canvas.add_child(region)
		regions[p.id] = region
	map_canvas.queue_redraw()
	arrow_layer.queue_redraw()
	clear_preview()
	_update_top_bar()
	if state.find_province(selected_province_id) == null:
		selected_province_id = ""
	if state.find_army(selected_army_id) == null:
		selected_army_id = ""
	_show_details()


func select_province(province_id: String) -> void:
	if state == null or state.find_province(province_id) == null:
		return
	# Two-click move: with one of your armies selected, clicking another province orders it there.
	var mover := state.find_army(selected_army_id)
	if mover and orders and mover.owner == viewing_faction_id and mover.location != province_id:
		if queue_move(mover.id, province_id).is_empty():
			return
		# Refused: the reason stays in the status line and the click selects the province as usual.
	else:
		status_text = ""
	clear_preview()
	selected_province_id = province_id
	var army := state.find_army(selected_army_id)
	if army == null or army.location != province_id:
		selected_army_id = ""
	for id in regions:
		regions[id].selected = id == province_id
	_show_details()
	province_selected.emit(province_id)


func select_army(army_id: String) -> void:
	var army: Army = state.find_army(army_id) if state else null
	if army == null:
		return
	selected_army_id = army_id
	select_province(army.location)
	army_selected.emit(army_id)


## Hover preview (#6): with one of your armies selected, shows what clicking `province_id` would
## order (arrival forecast and battle odds, or the rules' reason it can't be ordered) in a bar over the
## map, before you click. Returns the text shown, "" when there is nothing to preview.
func preview_move(province_id: String) -> String:
	_bind()
	var text := ""
	var army: Army = state.find_army(selected_army_id) if state else null
	if orders and army and army.owner == viewing_faction_id and army.location != province_id \
			and state.find_province(province_id) != null:
		text = orders.move_preview(army.id, province_id).text
	hover_label.text = text
	hover_panel.visible = not text.is_empty()
	return text


func clear_preview() -> void:
	if hover_panel:
		hover_label.text = ""
		hover_panel.visible = false


## Game screen hook: adds a HUD control to the top bar, just before the back button.
func add_top_bar_control(control: Control) -> void:
	_bind()
	var row := back_button.get_parent()
	row.add_child(control)
	row.move_child(control, back_button.get_index())


func set_hint(text: String) -> void:
	_bind()
	hint_label.text = text
	hint_label.tooltip_text = TooltipText.wrap_text(text)


## Faction ids in seat order, which pick the player colours: the session's players, or without a
## session the state's faction order (UiPalette.seat_order).
func seat_order() -> Array:
	return UiPalette.seat_order(state, session)


## Asks for the codex entry `key` (a linked number was right-clicked). A host (the game screen)
## listens to codex_requested; with nobody listening (the map preview) the map opens its own codex.
func request_codex(key: String) -> void:
	if not RulesCodex.ENTRIES.has(key):
		return
	if not codex_requested.get_connections().is_empty():
		codex_requested.emit(key)
		return
	if own_codex == null:
		own_codex = load(CODEX_SCENE).instantiate()
		own_codex.name = "Codex"
		var bg := own_codex.get_node_or_null("Background") as PanelContainer
		if bg:
			bg.add_theme_stylebox_override("panel", UiPalette.panel_style())
		add_child(own_codex)
	move_child(own_codex, get_child_count() - 1)
	own_codex.open(key)


## F1 over a linked number opens its codex entry. Only when no host listens: the game screen handles
## F1 itself, for its overlays too. Esc closes the map's own codex in one press.
func _input(event: InputEvent) -> void:
	if own_codex != null and own_codex.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		own_codex.close()
		return
	if not CodexLink.is_open_key(event) or not codex_requested.get_connections().is_empty():
		return
	var key := CodexLink.key_at(get_viewport().gui_get_hovered_control())
	if not key.is_empty():
		get_viewport().set_input_as_handled()
		request_codex(key)


## Selects a province and flashes its region so the eye finds it (e.g. from a turn report line).
func focus_province(province_id: String) -> void:
	select_province(province_id)
	var region: ProvinceRegion = regions.get(province_id)
	if region and region.is_inside_tree():
		region.modulate = Color(1.6, 1.6, 1.6)
		create_tween().tween_property(region, "modulate", Color.WHITE, 0.6)


# --- layout ---------------------------------------------------------------------------------------

## Finds the scene's nodes and wires their signals, once.
func _bind() -> void:
	if map_view != null:
		return
	map_view = %MapView
	map_canvas = %MapCanvas
	details = %Details
	faction_label = %FactionLabel
	gold_label = %GoldLabel
	turn_label = %TurnLabel
	hint_label = get_node("Layout/TopBar/Row/Hint")
	back_button = %BackButton
	map_view.resized.connect(_fit_map)
	map_canvas.draw.connect(_draw_links)
	back_button.pressed.connect(_on_back_pressed)
	# Order arrows sit above the map canvas (same transform, see _fit_map) so regions don't hide them.
	arrow_layer = Control.new()
	arrow_layer.name = "OrderArrows"
	arrow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow_layer.size = MapLayout.SIZE
	arrow_layer.draw.connect(_draw_order_arrows)
	map_view.add_child(arrow_layer)
	# Hover preview bar along the bottom of the map; grows upwards with its text.
	hover_panel = PanelContainer.new()
	hover_panel.name = "HoverPreview"
	hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiPalette.PANEL_BG, 0.94)
	style.border_color = UiPalette.GILT
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	hover_panel.add_theme_stylebox_override("panel", style)
	hover_panel.anchor_left = 0.0
	hover_panel.anchor_right = 1.0
	hover_panel.anchor_top = 1.0
	hover_panel.anchor_bottom = 1.0
	hover_panel.offset_left = 16
	hover_panel.offset_right = -16
	hover_panel.offset_top = -16
	hover_panel.offset_bottom = -16
	hover_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	map_view.add_child(hover_panel)
	hover_label = Label.new()
	hover_label.name = "HoverLabel"
	hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_label.add_theme_font_size_override("font_size", 17)
	hover_label.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	hover_panel.add_child(hover_label)


## Scales the design-space canvas to fit the map view, centred, keeping its aspect ratio.
func _fit_map() -> void:
	var avail := map_view.size
	if avail.x <= 0 or avail.y <= 0:
		return
	var s: float = min(avail.x / MapLayout.SIZE.x, avail.y / MapLayout.SIZE.y)
	map_canvas.scale = Vector2(s, s)
	map_canvas.position = (avail - MapLayout.SIZE * s) / 2.0
	arrow_layer.scale = map_canvas.scale
	arrow_layer.position = map_canvas.position


## Roads between neighbouring provinces, drawn under the regions.
func _draw_links() -> void:
	if state == null:
		return
	for p in state.provinces:
		for n in p.neighbors:
			if p.id < n and MapLayout.has_position(p.id) and MapLayout.has_position(n):
				var a := MapLayout.position_of(p.id)
				var b := MapLayout.position_of(n)
				map_canvas.draw_line(a, b, UiPalette.KEYLINE_HALO, 9.0, true)
				map_canvas.draw_line(a, b, UiPalette.MAP_INK, 5.0, true)


# --- top bar --------------------------------------------------------------------------------------

func _update_top_bar() -> void:
	var f := state.find_faction(viewing_faction_id)
	var seats := seat_order()
	var seat := seats.find(viewing_faction_id)
	faction_label.text = f.faction_name if f else "Spectator"
	faction_label.add_theme_color_override("font_color", UiPalette.owner_color(state, viewing_faction_id, seats).lightened(0.25))
	faction_label.tooltip_text = ""
	CodexLink.detach(faction_label)
	if f:
		var colour := "" if seat < 0 else " You are Player %d: your provinces and armies are drawn in %s." % [seat + 1, UiPalette.seat_color_name(seat)]
		faction_label.tooltip_text = TooltipText.plain("You are playing %s" % faction_label.text,
			"The map, gold and forecasts are shown from this faction's point of view.%s" % colour)
		CodexLink.attach(faction_label, TooltipText.codex_for("faction"), request_codex)
	if f:
		var g := Breakdown.gold(state, viewing_faction_id)
		var income: int = g.total - f.gold
		gold_label.text = "Gold %d   (+%d per turn)" % [f.gold, income]
		gold_label.tooltip_text = TooltipText.from_breakdown(g)
		CodexLink.attach(gold_label, TooltipText.codex_for("gold", g), request_codex)
	else:
		gold_label.text = ""
		gold_label.tooltip_text = ""
		CodexLink.detach(gold_label)
	# Breakdown.turn is 1-based like every turn players see: its title is the label.
	var t := Breakdown.turn(state)
	turn_label.text = String(t.title)
	turn_label.tooltip_text = TooltipText.from_breakdown(t)
	CodexLink.attach(turn_label, TooltipText.codex_for("turn", t), request_codex)


# --- side panel -----------------------------------------------------------------------------------

# --- orders (issue #6) ----------------------------------------------------------------------------

## Queues a move for the viewing faction. Returns "" or the rules' reason (also shown in the panel).
func queue_move(army_id: String, to_province: String) -> String:
	var reason := orders.queue_move(army_id, to_province)
	status_text = reason if not reason.is_empty() else "Move ordered. Armies move when the turn ends; click the cross to cancel."
	_orders_changed()
	return reason


## Queues one recruit at the capital. Returns "" or the rules' reason (also shown in the panel).
func queue_recruit(unit_type_id: String) -> String:
	var reason := orders.queue_recruit(unit_type_id)
	status_text = reason if not reason.is_empty() else "Recruit ordered. It is paid and joins at your capital when the turn ends."
	_orders_changed()
	return reason


func cancel_order(index: int) -> void:
	var reason := orders.cancel(index)
	status_text = reason if not reason.is_empty() else "Order cancelled."
	_orders_changed()


func _orders_changed() -> void:
	if arrow_layer:
		arrow_layer.queue_redraw()
	clear_preview()
	_show_details()
	orders_changed.emit()


## One arrow per queued move, from the army's province to its destination.
func _draw_order_arrows() -> void:
	if orders == null or state == null:
		return
	for o in orders.orders():
		if not (o is MoveOrder):
			continue
		var army := state.find_army(o.army_id)
		if army == null or not MapLayout.has_position(army.location) or not MapLayout.has_position(o.to):
			continue
		var a := MapLayout.position_of(army.location)
		var b := MapLayout.position_of(o.to)
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var start := a + dir * 34.0
		var tip := b - dir * 34.0
		var base := tip - dir * 26.0
		arrow_layer.draw_line(start, base, UiPalette.KEYLINE_HALO, 13.0, true)
		arrow_layer.draw_line(start, base, UiPalette.SELECTION, 7.0, true)
		arrow_layer.draw_colored_polygon(PackedVector2Array([tip + dir * 3.0, base + side * 17.0, base - side * 17.0]), UiPalette.KEYLINE_HALO)
		arrow_layer.draw_colored_polygon(PackedVector2Array([tip, base + side * 13.0, base - side * 13.0]), UiPalette.SELECTION)


## The orders list under the province details: each order with its forecast and a cancel button,
## live gold after recruits, and recruit buttons when your capital is selected.
func _add_orders_section() -> void:
	var f: Faction = state.find_faction(viewing_faction_id) if state else null
	if orders == null or f == null:
		return
	details.add_child(HSeparator.new())
	_add_heading("Your orders this turn", 20)
	if not status_text.is_empty():
		var status := _add_text(status_text, TooltipText.plain("Order check",
			"Orders are checked with the same rules the turn uses, so a refused order would fail at the end of the turn too."), UiPalette.GILT)
		status.name = "StatusLabel"
		_link(status, "order_check")
	var texts := orders.order_texts()
	if texts.is_empty():
		_add_text("No orders yet. Select one of your armies, then click a neighboring province to move it there. Select your capital to recruit.",
			"", UiPalette.TEXT_SECONDARY)
	for i in texts.size():
		var row := HBoxContainer.new()
		row.name = "Order_%d" % i
		details.add_child(row)
		var line := _add_text(texts[i], TooltipText.from_breakdown(orders.order_breakdown(i)), UiPalette.TEXT_PRIMARY, row)
		line.name = "OrderLine"
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.custom_minimum_size.x = 300
		_link(line, orders.order_codex_kind(i))
		var cancel := Button.new()
		cancel.name = "CancelButton"
		cancel.text = "✕"
		cancel.tooltip_text = "Cancel this order. Nothing happens until the turn ends, so you can change your mind."
		cancel.focus_mode = Control.FOCUS_NONE
		cancel.pressed.connect(cancel_order.bind(i))
		row.add_child(cancel)
	var g := orders.gold_after_recruits()
	var gold := _add_text("Gold after recruits: %d" % g.gold_after, TooltipText.from_breakdown(orders.gold_breakdown()), UiPalette.GILT)
	gold.name = "GoldAfterLabel"
	_link(gold, "gold_after_recruits")
	if selected_province_id == f.capital:
		var capital := state.find_province(f.capital)
		_add_heading("Recruit at %s" % capital.name, 18)
		for ut in orders.recruitable_types():
			var b := Button.new()
			b.name = "Recruit_%s" % ut.id.validate_node_name()
			b.text = "Recruit %s (%d gold)" % [ut.name, orders.recruit_cost(ut.id)]
			b.tooltip_text = TooltipText.from_breakdown(orders.recruit_breakdown(ut.id))
			_link(b, "recruit")
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(queue_recruit.bind(ut.id))
			details.add_child(b)


func _show_details() -> void:
	_show_province_details()
	_add_orders_section()


func _show_province_details() -> void:
	_bind()
	for child in details.get_children():
		details.remove_child(child)
		child.queue_free()
	var p: Province = state.find_province(selected_province_id) if state else null
	if p == null:
		_add_heading("No province selected", 22)
		_add_text("Click a province on the map to see its terrain, income, owner and armies.\nHover any number to see where it comes from.",
			"", UiPalette.TEXT_SECONDARY)
		return

	_add_heading(p.name, 28)
	var owner_name := "Nobody (neutral)" if p.owner.is_empty() else state.find_faction(p.owner).faction_name
	var seats := seat_order()
	var owner_label := _add_text("Owner: %s" % owner_name, TooltipText.plain("Owner",
		"The faction that holds %s and earns its income. %s" % [p.name, RulesCodex.text("capture")]))
	owner_label.name = "OwnerLabel"
	owner_label.add_theme_color_override("font_color", UiPalette.owner_color(state, p.owner, seats).lightened(0.3))
	_link(owner_label, "owner")
	var terrain_label := _add_text("Terrain: %s" % p.terrain.capitalize(), TooltipText.plain("Terrain: %s" % p.terrain.capitalize(),
		"%s %s" % [Province.describe("terrain"), MapData.get_terrain_description(p.terrain)]))
	terrain_label.name = "TerrainLabel"
	_link(terrain_label, "terrain")
	var income := Breakdown.province_income(state, p.id)
	var income_label := _add_text("Income: %d gold per turn" % p.income, TooltipText.from_breakdown(income), UiPalette.GILT)
	income_label.name = "IncomeLabel"
	_link(income_label, "province_income", income)
	var capital_text := "No"
	if p.is_capital:
		capital_text = "Yes"
		for f in state.factions:
			if f.capital == p.id:
				capital_text = "Yes, the capital of %s" % f.faction_name
	var capital_label := _add_text("Capital: %s" % capital_text, TooltipText.plain("Capital", "%s %s" % [Province.describe("capital"),
		RulesCodex.text("recruit")]))
	capital_label.name = "CapitalLabel"
	_link(capital_label, "capital")
	var fort_label := _add_text("Fort: %s" % ("Yes" if p.has_fort else "No"), TooltipText.plain("Fort", Province.describe("fort")))
	fort_label.name = "FortLabel"
	_link(fort_label, "fort")
	var names := []
	for n in p.neighbors:
		var np := state.find_province(n)
		names.append(np.name if np else n)
	var neighbors_label := _add_text("Neighbors: %s" % ", ".join(names), TooltipText.plain("Neighbors", RulesCodex.text("move")))
	neighbors_label.name = "NeighborsLabel"
	_link(neighbors_label, "neighbors")

	details.add_child(HSeparator.new())
	_add_heading("Armies here", 20)
	var any := false
	for a in state.armies:
		if a.location == p.id:
			any = true
			_add_army(a)
	if not any:
		var none := _add_text("No armies here.", TooltipText.plain("No armies", RulesCodex.text("undefended")), UiPalette.TEXT_SECONDARY)
		_link(none, "no_armies")


func _add_army(a: Army) -> void:
	var panel := PanelContainer.new()
	panel.name = "Army_%s" % a.id.validate_node_name()
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_RAISED
	style.border_color = UiPalette.SELECTION if a.id == selected_army_id else UiPalette.owner_color(state, a.owner, seat_order())
	style.set_border_width_all(3 if a.id == selected_army_id else 2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	details.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)

	var header := Button.new()
	header.name = "ArmyHeader"
	header.text = TurnResolver.army_label(state, a)
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.focus_mode = Control.FOCUS_NONE
	header.tooltip_text = TooltipText.from_breakdown(Breakdown.army_units(state, a.id)) + "\n\nClick to select this army."
	_link(header, "army_units")
	header.pressed.connect(select_army.bind(a.id))
	box.add_child(header)
	if a.ruler != null:
		# A ruler's army holds only its ruler (M2): show the ruler's numbers instead of units (RulerPanel).
		header.tooltip_text = RulerPanel.summary(state, a) + "\n\nClick to select this army."
		CodexLink.attach(header, "ruler_army", request_codex)
		RulerPanel.fill(box, state, a, request_codex)
		return

	var unit_breakdown := Breakdown.army_units(state, a.id)
	var units := _add_text("Units: %d" % a.units.size(), TooltipText.from_breakdown(unit_breakdown), UiPalette.TEXT_PRIMARY, box)
	units.name = "UnitsLabel"
	_link(units, "army_units", unit_breakdown)
	# A size guide only (RulesCodex "army_strength"): battles use the full rules, and the move forecast
	# has the real odds, so the label says "rough" and the tooltip points at the forecast.
	var sb := Breakdown.army_strength(state, a.id)
	sb.description = "%s %s" % [sb.get("description", ""), STRENGTH_GUIDE]
	var strength := _add_text("Rough strength: %d" % int(sb.total), TooltipText.from_breakdown(sb), UiPalette.TEXT_SECONDARY, box)
	strength.name = "StrengthLabel"
	_link(strength, "army_strength", sb)
	var commander_label: Label
	if a.commander:
		commander_label = _add_text("Commander: %s" % a.commander.type.name, TooltipText.plain("Commander: %s" % a.commander.type.name,
			Breakdown.unit_type_description(a.commander.type)), UiPalette.TEXT_PRIMARY, box)
	else:
		commander_label = _add_text("Commander: none", TooltipText.plain("No commander", "This army has no commander to lead it."),
			UiPalette.TEXT_SECONDARY, box)
	commander_label.name = "CommanderLabel"
	if a.commander:
		_link(commander_label, "commander")
	var seen := []
	for u in a.units:
		if seen.has(u.type.name):
			continue
		seen.append(u.type.name)
		var b := Breakdown.unit_count(state, a.id, u.type.name)
		var count_label := _add_text("    %s x%d" % [u.type.name, b.total], TooltipText.from_breakdown(b), UiPalette.TEXT_SECONDARY, box)
		count_label.name = "UnitCount"
		# Each unit type's codex entry is its trait's (e.g. "Shield Wall (Spearmen)").
		CodexLink.attach(count_label, AutoBattleResolver.codex_id_for_trait(u.type.trait_id), request_codex)


## Links a side panel label to the codex entry for its kind of number (TooltipText.CODEX).
func _link(control: Control, kind: String, breakdown: Dictionary = {}) -> void:
	CodexLink.attach(control, TooltipText.codex_for(kind, breakdown), request_codex)


func _add_heading(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", UiPalette.GILT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(l)
	return l


## Adds a line of text with a tooltip. Labels with tooltips take the mouse so the tooltip shows.
func _add_text(text: String, tooltip: String, color: Color = UiPalette.TEXT_PRIMARY, parent: Control = null) -> Label:
	var l := Label.new()
	l.text = text
	l.tooltip_text = tooltip
	l.mouse_filter = Control.MOUSE_FILTER_PASS if not tooltip.is_empty() else Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", color)
	(parent if parent else details).add_child(l)
	return l


func _on_back_pressed() -> void:
	if intercept_back:
		back_requested.emit()
		return
	get_tree().change_scene_to_file(TITLE_SCENE)
