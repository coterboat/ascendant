class_name ProvinceRegion
extends Control
## One province on the map: a placeholder region filled with its terrain colour, ringed in its
## owner's seat colour (UiPalette: colours follow the seat), with markers for capital and fort, its
## name, its income and its armies.
## Colour is never the only channel (design/STYLE_BIBLE.md 1.1): the owner ring carries the owner's
## seat emblem (Player 1 circle, Player 2 square, nobody a slate shield) and every army badge carries
## its owner's emblem as a light glyph (SeatEmblem).
## Reads the GameState only. Clicking it emits `pressed`; clicking an army badge emits `army_pressed`.
## The region, its income and its army badges link to their codex entries: right-clicking one (or F1)
## emits codex_requested.

signal pressed(province_id: String)
signal army_pressed(army_id: String)
signal codex_requested(key: String)

## Emblem on the owner ring, in the map's design space (the map view scales it up about 1.2x at 1600x900).
const RING_EMBLEM_RADIUS := 9.0
## Army badge emblem box, in design space.
const BADGE_EMBLEM_SIZE := 16.0

var province_id := ""
var selected := false:
	set(value):
		selected = value
		queue_redraw()

var ring_color := Color.WHITE  # the owner's seat colour (slate when unowned)
var owner_seat := -1  # the owner's 0-based seat, which picks the ring emblem; -1 for nobody
## King's Roads (M2): true while the selected army can reach this province by a road move this turn.
## Drawn as a dashed gilt ring inside the region; the tooltip names the way through.
var road_target := false
var _road_via := ""  # the way-through name the road tooltip shows
var _polygon := PackedVector2Array()
var _fill := Color.WHITE
var _is_capital := false
var _has_fort := false
var _east := false
var _base_tooltip := ""

var name_label: Label
var income_label: Label
var army_box: HFlowContainer  # army badges; several armies wrap onto a second row inside the region
## Sworn Vassals (M2): a pennant for the province that joins a faction at the end of the turn, in that
## faction's seat colour (slate when two factions want it); its tooltip is the forecast. null when none.
var vassal_marker: Control = null
var vassal_seat := -2  # the pennant's seat; -1 neutral (contested); -2 no pennant


## Builds the region for `province_id` from `state`. `center` is in the map canvas' design space.
## `seats` is the seat order (faction ids, seat 1 first) that picks the player colours; empty means
## the state's faction order (see UiPalette.owner_color).
func setup(state: GameState, p: Province, center: Vector2, seats: Array = []) -> void:
	province_id = p.id
	name = "Region_%s" % p.id
	var r := MapLayout.radius_of(p)
	position = center - Vector2(r, r)
	size = Vector2(r, r) * 2.0
	custom_minimum_size = size
	_polygon = MapLayout.region_polygon(p.id, Vector2(r, r), r)
	_fill = UiPalette.terrain_color(p.terrain)
	ring_color = UiPalette.owner_color(state, p.owner, seats)
	owner_seat = UiPalette.seat_index(state, p.owner, seats)
	_is_capital = p.is_capital
	_has_fort = p.has_fort
	_east = MapLayout.is_east(p.id)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var owner_name := "nobody (neutral)" if p.owner.is_empty() else state.find_faction(p.owner).faction_name
	tooltip_text = TooltipText.plain("%s: %s, owned by %s" % [p.name, p.terrain.capitalize(), owner_name],
		"%s Click to see its terrain, income and armies." % marks_text(p))
	_base_tooltip = tooltip_text
	CodexLink.attach(self, TooltipText.codex_for("province"), codex_requested.emit)

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

	# What the province earns its owner: its base income, plus Heavy Tithes and Royal Court (M2).
	var income := Breakdown.province_income(state, p.id)
	income_label = _label("%d gold" % int(income.total), 14, UiPalette.GILT)
	income_label.name = "IncomeLabel"
	income_label.mouse_filter = Control.MOUSE_FILTER_PASS
	income_label.tooltip_text = TooltipText.from_breakdown(income)
	CodexLink.attach(income_label, TooltipText.codex_for("province_income", income), codex_requested.emit)
	box.add_child(income_label)

	army_box = HFlowContainer.new()
	army_box.name = "Armies"
	army_box.alignment = FlowContainer.ALIGNMENT_CENTER
	army_box.add_theme_constant_override("h_separation", 4)
	army_box.add_theme_constant_override("v_separation", 2)
	army_box.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(army_box)
	for a in state.armies:
		if a.location == p.id:
			army_box.add_child(_army_badge(state, a, seats))
	queue_redraw()


## King's Roads (M2): marks this province as a road destination of the selected army (`on`), going
## through `via_name`, or clears the mark. The tooltip says so; clicking orders the road move.
func set_road_target(on: bool, via_name: String = "") -> void:
	if on == road_target and (not on or via_name == _road_via):
		return
	road_target = on
	_road_via = via_name if on else ""
	var text := _base_tooltip
	if on:
		text += "\n\n" + TooltipText.wrap_text("King's Roads: the selected army can reach this province this turn through %s. Click to order the road move (dashed gilt ring)." % via_name)
	tooltip_text = text
	CodexLink.attach(self, TooltipText.codex_for("province"), codex_requested.emit)  # puts the codex line back
	queue_redraw()


## Sworn Vassals (M2): shows a pennant for the faction in `seat` that this province will join at the end
## of the turn (-1: a slate pennant, two factions want it and it joins nobody), with `tooltip` (the
## forecast), or removes it (seat -2).
func set_vassal_mark(seat: int, tooltip: String) -> void:
	vassal_seat = seat
	if seat < -1:
		if vassal_marker != null:
			vassal_marker.queue_free()
			remove_child(vassal_marker)
			vassal_marker = null
		return
	if vassal_marker == null:
		vassal_marker = Control.new()
		vassal_marker.name = "VassalMarker"
		vassal_marker.size = Vector2(28, 30)
		vassal_marker.mouse_filter = Control.MOUSE_FILTER_PASS
		vassal_marker.draw.connect(_draw_pennant)
		var r := size.x / 2.0
		vassal_marker.position = Vector2(r * (0.42 if _east else 1.58), r * 1.5) - vassal_marker.size / 2.0
		add_child(vassal_marker)
	vassal_marker.tooltip_text = tooltip
	CodexLink.attach(vassal_marker, TooltipText.codex_for("vassal"), codex_requested.emit)
	vassal_marker.queue_redraw()


## The Sworn Vassals pennant: a pole and a flag in the joining faction's colour with its emblem.
func _draw_pennant() -> void:
	if vassal_marker == null:
		return
	var colour := UiPalette.NEUTRAL if vassal_seat < 0 else UiPalette.seat_color(vassal_seat)
	var pole_x := 5.0
	vassal_marker.draw_line(Vector2(pole_x, 2), Vector2(pole_x, 29), UiPalette.KEYLINE_INK, 3.0, true)
	var flag := PackedVector2Array([Vector2(pole_x + 1, 3), Vector2(27, 9), Vector2(pole_x + 1, 17)])
	vassal_marker.draw_colored_polygon(flag, colour)
	var closed := flag.duplicate()
	closed.append(flag[0])
	vassal_marker.draw_polyline(closed, UiPalette.KEYLINE_INK, 1.5, true)
	if vassal_seat >= 0:
		SeatEmblem.draw_emblem(vassal_marker, Vector2(pole_x + 8, 10), 3.5, vassal_seat, SeatEmblem.Look.GLYPH)
	else:
		# Contested: a cross over the slate flag.
		vassal_marker.draw_line(Vector2(pole_x + 5, 6), Vector2(pole_x + 12, 14), UiPalette.TEXT_PRIMARY, 2.0, true)
		vassal_marker.draw_line(Vector2(pole_x + 12, 6), Vector2(pole_x + 5, 14), UiPalette.TEXT_PRIMARY, 2.0, true)


## What the ring and markers say, in words: "Player 1's province: Vermilion ring, circle emblem.
## Capital (the crown). Fort (the tower)." Neutral provinces get the slate ring and shield.
func marks_text(p: Province) -> String:
	var text := "Neutral: slate ring, shield emblem." if owner_seat < 0 else "Player %d's province: %s ring, %s emblem." % [
		owner_seat + 1, UiPalette.seat_color_name(owner_seat), SeatEmblem.shape_of(owner_seat)]
	if p.is_capital:
		text += " Capital (the crown)."
	if p.has_fort:
		text += " Fort (the tower)."
	return text


func _army_badge(state: GameState, a: Army, seats: Array) -> Button:
	var b := Button.new()
	b.name = "Army_%s" % a.id.validate_node_name()
	b.text = TooltipText.count(a.units.size(), "unit")
	b.flat = false
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.owner_color(state, a.owner, seats)
	style.border_color = UiPalette.KEYLINE_INK
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 6 + BADGE_EMBLEM_SIZE
	style.content_margin_right = 6
	for s in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(s, style)
	b.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	b.add_theme_color_override("font_hover_color", UiPalette.TEXT_PRIMARY)
	# The owner's emblem as a light glyph at the badge's left, so the badge reads without its colour.
	var seat := UiPalette.seat_index(state, a.owner, seats)
	var emblem := SeatEmblem.new(seat, SeatEmblem.Look.GLYPH, BADGE_EMBLEM_SIZE)
	emblem.anchor_top = 0.5
	emblem.anchor_bottom = 0.5
	emblem.offset_left = 3
	emblem.offset_right = 3 + BADGE_EMBLEM_SIZE
	emblem.offset_top = -BADGE_EMBLEM_SIZE / 2.0
	emblem.offset_bottom = BADGE_EMBLEM_SIZE / 2.0
	b.add_child(emblem)
	var whose := "" if seat < 0 else "Player %d's army (%s badge, %s emblem). " % [seat + 1, UiPalette.seat_color_name(seat), SeatEmblem.shape_of(seat)]
	if a.ruler != null:
		# A ruler's army holds only its ruler (M2): name it and show the ruler's numbers (RulerPanel).
		b.text = RulerPanel.badge_text(a)
		b.tooltip_text = RulerPanel.summary(state, a) + "\n\n" + TooltipText.wrap_text(whose + "Click to select this army.")
		CodexLink.attach(b, "ruler_army", codex_requested.emit)
	else:
		var units := Breakdown.army_units(state, a.id)
		b.tooltip_text = TooltipText.from_breakdown(units) + "\n\n" + TooltipText.wrap_text(whose + "Click to select this army.")
		CodexLink.attach(b, TooltipText.codex_for("army_units", units), codex_requested.emit)
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
	draw_polyline(closed, ring_color, 6.0, true)
	draw_polyline(closed, UiPalette.KEYLINE_INK, 1.5, true)
	if selected:
		draw_polyline(closed, UiPalette.SELECTION, 3.0, true)
		var grown := PackedVector2Array()
		var c := size / 2.0
		for pt in closed:
			grown.append(c + (pt - c) * 1.1)
		draw_polyline(grown, UiPalette.SELECTION, 3.0, true)
	if road_target:
		_draw_road_ring()
	var r := size.x / 2.0
	if _is_capital:
		_draw_crown(Vector2(r, r * 0.32))
	if _has_fort:
		_draw_fort(Vector2(r * (1.58 if _east else 0.42), r * 1.55))
	SeatEmblem.draw_emblem(self, emblem_position(), RING_EMBLEM_RADIUS, owner_seat)


## King's Roads destination: a dashed gilt ring just inside the owner ring, over an ink keyline, so it
## reads on any terrain and is never colour alone (the dashes are the shape cue).
func _draw_road_ring() -> void:
	var c := size / 2.0
	var inner := PackedVector2Array()
	for pt in _polygon:
		inner.append(c + (pt - c) * 0.84)
	for i in inner.size():
		var a := inner[i]
		var b := inner[(i + 1) % inner.size()]
		draw_dashed_line(a, b, UiPalette.KEYLINE_INK, 6.0, 10.0, true)
		draw_dashed_line(a, b, UiPalette.GILT, 3.5, 10.0, true)


## Where the owner emblem sits: on the ring at the upper left (upper right on the mirrored east half),
## like the token emblem at the top-left in the style bible, clear of the crown, the name and the fort.
func emblem_position() -> Vector2:
	var r := size.x / 2.0
	var dir := Vector2(0.7 if _east else -0.7, -0.7).normalized()
	return Vector2(r, r) + dir * r * 0.93


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
