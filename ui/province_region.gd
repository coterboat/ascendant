class_name ProvinceRegion
extends Control
## One province on the map: a placeholder region filled with its terrain colour, ringed in its
## owner's colour, with markers for capital and fort, its name, its income and its armies.
## Reads the GameState only. Clicking it emits `pressed`; clicking an army badge emits `army_pressed`.

signal pressed(province_id: String)
signal army_pressed(army_id: String)

var province_id := ""
var selected := false:
	set(value):
		selected = value
		queue_redraw()

var _polygon := PackedVector2Array()
var _fill := Color.WHITE
var _ring := Color.WHITE
var _is_capital := false
var _has_fort := false
var _east := false

var name_label: Label
var income_label: Label
var army_box: HBoxContainer


## Builds the region for `province_id` from `state`. `center` is in the map canvas' design space.
func setup(state: GameState, p: Province, center: Vector2) -> void:
	province_id = p.id
	name = "Region_%s" % p.id
	var r := MapLayout.radius_of(p)
	position = center - Vector2(r, r)
	size = Vector2(r, r) * 2.0
	custom_minimum_size = size
	_polygon = MapLayout.region_polygon(p.id, Vector2(r, r), r)
	_fill = UiPalette.terrain_color(p.terrain)
	_ring = UiPalette.owner_color(state, p.owner)
	_is_capital = p.is_capital
	_has_fort = p.has_fort
	_east = MapLayout.is_east(p.id)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var owner_name := "nobody (neutral)" if p.owner.is_empty() else state.find_faction(p.owner).faction_name
	tooltip_text = TooltipText.plain("%s: %s, owned by %s" % [p.name, p.terrain.capitalize(), owner_name],
		"%s Click to see its details." % MapData.get_terrain_description(p.terrain))

	var box := VBoxContainer.new()
	box.name = "Labels"
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)

	name_label = _label(p.name, 17, UiPalette.TEXT_PRIMARY)
	name_label.name = "NameLabel"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	income_label = _label("%d gold" % p.income, 14, UiPalette.GILT)
	income_label.name = "IncomeLabel"
	income_label.mouse_filter = Control.MOUSE_FILTER_PASS
	income_label.tooltip_text = TooltipText.from_breakdown(Breakdown.province_income(state, p.id))
	box.add_child(income_label)

	army_box = HBoxContainer.new()
	army_box.name = "Armies"
	army_box.alignment = BoxContainer.ALIGNMENT_CENTER
	army_box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(army_box)
	for a in state.armies:
		if a.location == p.id:
			army_box.add_child(_army_badge(state, a))
	queue_redraw()


func _army_badge(state: GameState, a: Army) -> Button:
	var b := Button.new()
	b.name = "Army_%s" % a.id.validate_node_name()
	b.text = "%d units" % a.units.size()
	b.flat = false
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.owner_color(state, a.owner)
	style.border_color = UiPalette.KEYLINE_INK
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 6
	style.content_margin_right = 6
	for s in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(s, style)
	b.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	b.add_theme_color_override("font_hover_color", UiPalette.TEXT_PRIMARY)
	b.tooltip_text = TooltipText.from_breakdown(Breakdown.army_units(state, a.id))
	b.pressed.connect(func(): army_pressed.emit(a.id))
	return b


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", UiPalette.KEYLINE_INK)
	l.add_theme_constant_override("outline_size", 4)
	return l


func _has_point(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point, _polygon)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(province_id)
		accept_event()


func _draw() -> void:
	if _polygon.is_empty():
		return
	draw_colored_polygon(_polygon, _fill)
	var closed := _polygon.duplicate()
	closed.append(_polygon[0])
	# Owner ring with the bible's keylines: ink inside, halo outside, so the colour reads on any terrain.
	draw_polyline(closed, UiPalette.KEYLINE_HALO, 9.0, true)
	draw_polyline(closed, _ring, 6.0, true)
	draw_polyline(closed, UiPalette.KEYLINE_INK, 1.5, true)
	if selected:
		draw_polyline(closed, UiPalette.SELECTION, 3.0, true)
		var grown := PackedVector2Array()
		var c := size / 2.0
		for pt in closed:
			grown.append(c + (pt - c) * 1.1)
		draw_polyline(grown, UiPalette.SELECTION, 3.0, true)
	var r := size.x / 2.0
	if _is_capital:
		_draw_crown(Vector2(r, r * 0.32))
	if _has_fort:
		_draw_fort(Vector2(r * (1.58 if _east else 0.42), r * 1.55))


## Capital marker: a small gilt crown above the name.
func _draw_crown(at: Vector2) -> void:
	var w := 14.0
	var pts := PackedVector2Array([
		at + Vector2(-w, 6), at + Vector2(-w, -6), at + Vector2(-w * 0.5, 0), at + Vector2(0, -9),
		at + Vector2(w * 0.5, 0), at + Vector2(w, -6), at + Vector2(w, 6)])
	draw_colored_polygon(pts, UiPalette.GILT)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, UiPalette.KEYLINE_INK, 1.5, true)


## Fort marker: a small crenellated tower.
func _draw_fort(at: Vector2) -> void:
	var pts := PackedVector2Array([
		at + Vector2(-8, 8), at + Vector2(-8, -6), at + Vector2(-4, -6), at + Vector2(-4, -2),
		at + Vector2(0, -2), at + Vector2(0, -6), at + Vector2(4, -6), at + Vector2(4, -2),
		at + Vector2(8, -2), at + Vector2(8, -6), at + Vector2(8, 8)])
	draw_colored_polygon(pts, UiPalette.TEXT_SECONDARY)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, UiPalette.KEYLINE_INK, 1.5, true)
