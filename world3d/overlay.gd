## The 2D overlay test: ordinary Controls standing on 3D points, through the world's projector
## (world_view.gd project / project3). Each province's name over its stage (a star on a capital,
## a tower on a fort), and over every army a count plate in its owner's colour with the seat's
## emblem, its unit count and a tooltip that says what it is. Full UI integration comes later; this
## proves the 2D UI can follow the 3D land and armies as the camera moves.
extends Control

const Scenario := preload("res://world3d/scenario.gd")

var wv: Node3D
var armies: Node3D
var _labels := {} ## province id -> Label
var _plates := {} ## army id -> PanelContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func build_labels() -> void:
	for l in _labels.values():
		(l as Node).queue_free()
	_labels.clear()
	var t = wv.terrain
	for i in t.ids.size():
		var l := Label.new()
		var mark := ""
		if t.is_capital[i]:
			mark = "★ "
		elif t.has_fort[i]:
			mark = "♜ "
		l.text = mark + str(t.names[i])
		l.add_theme_font_size_override("font_size", 17 if t.is_capital[i] else 15)
		l.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
		l.add_theme_color_override("font_outline_color", UiPalette.KEYLINE_INK)
		l.add_theme_constant_override("outline_size", 6)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		l.tooltip_text = "%s: %s. %s" % [t.names[i], str(t.terrain_of[i]).capitalize(), MapData.get_terrain_description(t.terrain_of[i])]
		add_child(l)
		_labels[t.ids[i]] = l


## Rebuilds the army plates for the state on the map.
func build_plates(s: GameState, seats: Array) -> void:
	for p in _plates.values():
		(p as Node).queue_free()
	_plates.clear()
	for a in s.armies:
		var seat: int = UiPalette.seat_index(s, a.owner, seats)
		var col: Color = UiPalette.seat_color(seat)
		var pc := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiPalette.PANEL_BG
		sb.border_color = col
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 5
		sb.content_margin_right = 7
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		pc.add_theme_stylebox_override("panel", sb)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		pc.add_child(hb)
		var em := Emblem.new()
		em.colour = col
		em.shape = maxi(seat, 0)
		em.custom_minimum_size = Vector2(14, 14)
		em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(em)
		var lb := Label.new()
		lb.text = str(a.units.size()) + (" ⚑" if a.commander != null or a.ruler != null else "")
		lb.add_theme_font_size_override("font_size", 15)
		lb.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
		hb.add_child(lb)
		pc.tooltip_text = _describe(s, a)
		pc.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(pc)
		_plates[a.id] = pc


func _describe(s: GameState, a: Army) -> String:
	var f := s.find_faction(a.owner)
	var counts := {}
	for u in a.units:
		counts[u.type.name] = int(counts.get(u.type.name, 0)) + 1
	var parts: Array = []
	for k in counts.keys():
		parts.append("%d %s" % [counts[k], k])
	var lead := ""
	if a.commander != null:
		lead = ", led by " + a.commander.type.name
	elif a.ruler != null:
		lead = ", the ruler " + a.ruler.type.name
	var pname: String = s.find_province(a.location).name if s.find_province(a.location) != null else a.location
	return "%s army at %s: %s%s.\nEach company of figures is one unit; the flag marks a commander." % [
		f.faction_name if f != null else a.owner, pname, ", ".join(parts) if not parts.is_empty() else "no units", lead]


func _process(_delta: float) -> void:
	if wv == null or wv.terrain == null:
		return
	var t = wv.terrain
	var vp: Vector2 = get_viewport_rect().size
	for id in _labels.keys():
		var l: Label = _labels[id]
		var i: int = t.index_of(id)
		var c: Vector2 = t.centres[i]
		var r: float = t.stage_r[i]
		## the name under the stage (south), so the army's plate above it stays clear
		var s: Vector2 = wv.project(c + Vector2(0, r * (0.95 if t.is_capital[i] else 1.15)), 2.0)
		l.reset_size()
		l.position = s - Vector2(l.size.x * 0.5, 0.0)
		l.visible = s.x > -200 and s.x < vp.x + 200 and s.y > -100 and s.y < vp.y + 100
	if armies == null:
		return
	for id in _plates.keys():
		var pc: PanelContainer = _plates[id]
		if not armies.armies.has(id):
			pc.visible = false
			continue
		var anchor: Vector3 = armies.army_anchor(id)
		if anchor.x < -9999:
			pc.visible = false
			continue
		var s2: Vector2 = wv.project3(anchor)
		pc.reset_size()
		pc.position = s2 - Vector2(pc.size.x * 0.5, pc.size.y)
		pc.visible = s2.x > -100 and s2.x < vp.x + 100 and s2.y > -50 and s2.y < vp.y + 50


## The seat's emblem drawn in code (style bible 1.1): circle, square, triangle, diamond, with
## the bible's keylines (ink inside, a pale halo outside).
class Emblem extends Control:
	var colour := Color.WHITE
	var shape := 0

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 - 1.5
		var halo := UiPalette.KEYLINE_HALO
		var ink := UiPalette.KEYLINE_INK
		match shape:
			0:
				draw_circle(c, r + 1.5, halo)
				draw_circle(c, r, ink)
				draw_circle(c, r - 1.2, colour)
			_:
				var pts := PackedVector2Array()
				if shape == 1:
					pts = PackedVector2Array([c + Vector2(-r, -r), c + Vector2(r, -r), c + Vector2(r, r), c + Vector2(-r, r)])
				elif shape == 2:
					pts = PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, r), c + Vector2(-r, r)])
				else:
					pts = PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
				var big := PackedVector2Array()
				var mid := PackedVector2Array()
				var small := PackedVector2Array()
				for p in pts:
					big.append(c + (p - c) * ((r + 1.5) / r))
					mid.append(p)
					small.append(c + (p - c) * ((r - 1.4) / r))
				draw_colored_polygon(big, halo)
				draw_colored_polygon(mid, ink)
				draw_colored_polygon(small, colour)
