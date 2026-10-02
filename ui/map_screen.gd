class_name MapScreen
extends Control
## The main map screen (issue #5): the M1 map drawn from a GameState, a top bar with the viewing
## player's gold and the turn, and a side panel with the selected province's details.
## Reads the GameState only and never changes it. Every number on screen has a tooltip with its
## breakdown (rules/breakdown.gd) and a plain-language description.
##
## API for the orders UI and turn flow:
##   set_state(state, viewing_faction_id)  show a state (rebuilds the map; keeps the selection if it still exists)
##   select_province(id)                   select a province and fill the side panel
##   select_army(id)                       select an army (and its province)
##   focus_province(id)                    select a province and flash it to draw the eye
##   signal province_selected(id), signal army_selected(id)

signal province_selected(province_id: String)
signal army_selected(army_id: String)

const SIDE_PANEL_WIDTH := 400
const TITLE_SCENE := "res://ui/title_screen.tscn"

var state: GameState = null
var viewing_faction_id := ""
var selected_province_id := ""
var selected_army_id := ""
var regions := {}  # province id -> ProvinceRegion
var orders: OrdersController = null  # issue #6: the viewing faction's orders this turn
var status_text := ""  # last order result: the rules' reason when an order was refused
var arrow_layer: Control  # drawn above the regions: one arrow per queued move

# Scene nodes, looked up by _bind() rather than @onready so the screen also works before it is in
# the tree (tests build it headless, and callers may set_state() before adding it).
var map_view: Control
var map_canvas: Control
var details: VBoxContainer
var faction_label: Label
var gold_label: Label
var turn_label: Label
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
	if orders == null or orders.state != new_state or orders.faction_id != faction_id:
		orders = OrdersController.new(new_state, faction_id)
		status_text = ""
	state = new_state
	viewing_faction_id = faction_id
	_bind()
	for child in map_canvas.get_children():
		map_canvas.remove_child(child)
		child.queue_free()
	regions.clear()
	for p in state.provinces:
		if not MapLayout.has_position(p.id):
			push_error("The map layout has no position for province '%s'." % p.id)
			continue
		var region := ProvinceRegion.new()
		region.setup(state, p, MapLayout.position_of(p.id))
		region.pressed.connect(select_province)
		region.army_pressed.connect(select_army)
		map_canvas.add_child(region)
		regions[p.id] = region
	map_canvas.queue_redraw()
	arrow_layer.queue_redraw()
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
	faction_label.text = f.faction_name if f else "Spectator"
	faction_label.add_theme_color_override("font_color", UiPalette.owner_color(state, viewing_faction_id).lightened(0.25))
	faction_label.tooltip_text = TooltipText.plain("You are playing %s" % faction_label.text,
		"The map, gold and forecasts are shown from this faction's point of view.") if f else ""
	if f:
		var g := Breakdown.gold(state, viewing_faction_id)
		var income: int = g.total - f.gold
		gold_label.text = "Gold %d   (+%d per turn)" % [f.gold, income]
		gold_label.tooltip_text = TooltipText.from_breakdown(g)
	else:
		gold_label.text = ""
		gold_label.tooltip_text = ""
	var t := Breakdown.turn(state)
	turn_label.text = "Turn %d" % state.current_turn
	turn_label.tooltip_text = TooltipText.from_breakdown(t)


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
	orders.cancel(index)
	status_text = "Order cancelled."
	_orders_changed()


func _orders_changed() -> void:
	if arrow_layer:
		arrow_layer.queue_redraw()
	_show_details()


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
	var texts := orders.order_texts()
	if texts.is_empty():
		_add_text("No orders yet. Select one of your armies, then click a neighboring province to move it there. Select your capital to recruit.",
			"", UiPalette.TEXT_SECONDARY)
	for i in texts.size():
		var row := HBoxContainer.new()
		row.name = "Order_%d" % i
		details.add_child(row)
		var line := _add_text(texts[i], TooltipText.from_breakdown(orders.order_breakdown(i)), UiPalette.TEXT_PRIMARY, row)
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.custom_minimum_size.x = 300
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
	if selected_province_id == f.capital:
		var capital := state.find_province(f.capital)
		_add_heading("Recruit at %s" % capital.name, 18)
		for ut in orders.recruitable_types():
			var b := Button.new()
			b.name = "Recruit_%s" % ut.id.validate_node_name()
			b.text = "Recruit %s (%d gold)" % [ut.name, orders.recruit_cost(ut.id)]
			b.tooltip_text = TooltipText.from_breakdown(orders.recruit_breakdown(ut.id))
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
	var owner_label := _add_text("Owner: %s" % owner_name, TooltipText.plain("Owner",
		"The faction that holds %s and earns its income. %s" % [p.name, RulesCodex.text("capture")]))
	owner_label.name = "OwnerLabel"
	owner_label.add_theme_color_override("font_color", UiPalette.owner_color(state, p.owner).lightened(0.3))
	var terrain_label := _add_text("Terrain: %s" % p.terrain.capitalize(), TooltipText.plain("Terrain: %s" % p.terrain.capitalize(),
		"%s %s" % [Province.describe("terrain"), MapData.get_terrain_description(p.terrain)]))
	terrain_label.name = "TerrainLabel"
	var income_label := _add_text("Income: %d gold per turn" % p.income,
		TooltipText.from_breakdown(Breakdown.province_income(state, p.id)), UiPalette.GILT)
	income_label.name = "IncomeLabel"
	var capital_text := "No"
	if p.is_capital:
		capital_text = "Yes"
		for f in state.factions:
			if f.capital == p.id:
				capital_text = "Yes, the capital of %s" % f.faction_name
	var capital_label := _add_text("Capital: %s" % capital_text, TooltipText.plain("Capital", "%s %s" % [Province.describe("capital"),
		RulesCodex.text("recruit")]))
	capital_label.name = "CapitalLabel"
	var fort_label := _add_text("Fort: %s" % ("Yes" if p.has_fort else "No"), TooltipText.plain("Fort", Province.describe("fort")))
	fort_label.name = "FortLabel"
	var names := []
	for n in p.neighbors:
		var np := state.find_province(n)
		names.append(np.name if np else n)
	var neighbors_label := _add_text("Neighbors: %s" % ", ".join(names), TooltipText.plain("Neighbors", RulesCodex.text("move")))
	neighbors_label.name = "NeighborsLabel"

	details.add_child(HSeparator.new())
	_add_heading("Armies here", 20)
	var any := false
	for a in state.armies:
		if a.location == p.id:
			any = true
			_add_army(a)
	if not any:
		_add_text("No armies here.", TooltipText.plain("No armies", RulesCodex.text("undefended")), UiPalette.TEXT_SECONDARY)


func _add_army(a: Army) -> void:
	var panel := PanelContainer.new()
	panel.name = "Army_%s" % a.id.validate_node_name()
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_RAISED
	style.border_color = UiPalette.SELECTION if a.id == selected_army_id else UiPalette.owner_color(state, a.owner)
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
	header.pressed.connect(select_army.bind(a.id))
	box.add_child(header)

	var units := _add_text("Units: %d" % a.units.size(), TooltipText.from_breakdown(Breakdown.army_units(state, a.id)), UiPalette.TEXT_PRIMARY, box)
	units.name = "UnitsLabel"
	var strength := _add_text("Strength: %d" % StubBattleResolver.army_strength(a),
		TooltipText.from_breakdown(Breakdown.army_strength(state, a.id)), UiPalette.TEXT_PRIMARY, box)
	strength.name = "StrengthLabel"
	var commander_label: Label
	if a.commander:
		commander_label = _add_text("Commander: %s" % a.commander.type.name, TooltipText.plain("Commander: %s" % a.commander.type.name,
			Breakdown.unit_type_description(a.commander.type)), UiPalette.TEXT_PRIMARY, box)
	else:
		commander_label = _add_text("Commander: none", TooltipText.plain("No commander", "This army has no commander to lead it."),
			UiPalette.TEXT_SECONDARY, box)
	commander_label.name = "CommanderLabel"
	var seen := []
	for u in a.units:
		if seen.has(u.type.name):
			continue
		seen.append(u.type.name)
		var b := Breakdown.unit_count(state, a.id, u.type.name)
		_add_text("    %s x%d" % [u.type.name, b.total], TooltipText.from_breakdown(b), UiPalette.TEXT_SECONDARY, box)


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
	get_tree().change_scene_to_file(TITLE_SCENE)
