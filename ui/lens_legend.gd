class_name LensLegend
extends PanelContainer
## UX-7 (#217; design/UX_WAR_TABLE.md §4.0): the legend card of the active map lens, bottom left in the board's safe area (the Table
## places it: TableHud.set_floating("legend", ...), TableLayout gives it its spot). It says the lens's question, its scale (swatches
## that run in lightness, with the pattern that tells them apart without colour) and its totals, then its notes, and how to turn it
## off. On the 2D map it also names the blend effects that are the 3D board's alone. The Sight lens carries the sight legend the
## retired Vision map mode had (FogView.legend_rows, a swatch of the veil for each level). A right-click or F1 opens the lens's codex
## entry. It only draws MapLens.build's legend: it reads nothing else.

const W := TableLayout.LEGEND_W  # the left column's width: it shares the column with the card
const SWATCH := Vector2(30, 16)

var legend := {}
var two_d := false
var body: VBoxContainer
var _open := Callable()


func _init() -> void:
	name = "LensLegend"
	mouse_filter = Control.MOUSE_FILTER_STOP  # a piece of the Table: it takes its own clicks (its hover, its codex link)
	visible = false
	add_theme_stylebox_override("panel", TableHud.plaque_style(10, 8))
	body = VBoxContainer.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 4)
	body.custom_minimum_size = Vector2(W - 24.0, 0)
	add_child(body)


## Shows `p_legend` (MapLens.build's "legend"); `p_two_d` on the 2D map. `open` opens a codex key.
func show_legend(p_legend: Dictionary, p_two_d: bool, open: Callable = Callable()) -> void:
	legend = p_legend
	two_d = p_two_d
	if open.is_valid():
		_open = open
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	if legend.is_empty():
		visible = false
		return
	var head := _label("Title", "%d · %s" % [int(legend.get("n", 0)), String(legend.get("title", ""))], UiPalette.TYPE_NAME, UiPalette.GILT)
	head.add_theme_font_override("font", UiFonts.name())
	body.add_child(head)
	body.add_child(_label("Question", String(legend.get("question", "")), UiPalette.TYPE_BODY, UiPalette.TEXT_PRIMARY))
	body.add_child(_scale(legend.get("scale", {})))
	var rows: Array = legend.get("rows", [])
	if not rows.is_empty():
		body.add_child(_sight_rows(rows))
	for line in legend.get("totals", []):
		body.add_child(_label("Total", String(line), UiPalette.TYPE_SMALL, UiPalette.TEXT_PRIMARY))
	if two_d:  # the blend effects the 2D map leaves to the 3D board, named (§4.0)
		for line in legend.get("notes_2d", []):
			body.add_child(_label("Note2D", String(line), UiPalette.TYPE_SMALL, UiPalette.TEXT_SECONDARY))
	var key := str(int(legend.get("n", 0)))
	body.add_child(_label("Off", "%s again, Esc or ` turns it off. Hover here for more." % key, UiPalette.TYPE_SMALL, UiPalette.TEXT_DISABLED))
	# the notes (how to read it, what it never shows) are the card's hover, so the card stays short beside the selection card
	var notes: Array = (legend.get("notes", []) as Array).duplicate()
	notes.append("Every plate shows the lens value; hover one for its breakdown.")
	tooltip_text = TooltipText.plain("%s lens: %s" % [String(legend.get("title", "")), String(legend.get("question", ""))], " ".join(notes))
	CodexLink.attach(self, String(legend.get("codex", "")), _open if _open.is_valid() else func(_k): pass)
	visible = true
	reset_size()


## Every line of the card, for tests and the fog-leak check.
func text() -> String:
	var out := PackedStringArray()
	for c in body.find_children("*", "Label", true, false):
		out.append((c as Label).text)
	return "\n".join(out)


func _label(node_name: String, text: String, font_size: int, colour: Color) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(W - 24.0, 0)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The scale: a ramp of swatches with its ends named, or one swatch per thing with its name (Owner's factions, Making's marks).
func _scale(scale: Dictionary) -> Control:
	var steps: Array = scale.get("steps", [])
	if String(scale.get("kind", "")) == "swatches":
		var grid := GridContainer.new()
		grid.name = "Scale"
		grid.columns = 2
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 2)
		for s in steps:
			grid.add_child(_swatch(s))
			var l := _label("Swatch", String(s.get("label", "")), UiPalette.TYPE_SMALL, UiPalette.TEXT_PRIMARY)
			l.custom_minimum_size = Vector2(W - 24.0 - SWATCH.x - 6.0, 0)
			grid.add_child(l)
		return grid
	var box := VBoxContainer.new()
	box.name = "Scale"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 2)
	for s in steps:
		row.add_child(_swatch(s))
	box.add_child(row)
	var ends := HBoxContainer.new()
	ends.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var low := _label("Low", String(scale.get("low", "")), UiPalette.TYPE_SMALL, UiPalette.TEXT_SECONDARY)
	low.custom_minimum_size = Vector2(0, 0)
	low.autowrap_mode = TextServer.AUTOWRAP_OFF
	low.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var high := _label("High", String(scale.get("high", "")), UiPalette.TYPE_SMALL, UiPalette.TEXT_SECONDARY)
	high.custom_minimum_size = Vector2(0, 0)
	high.autowrap_mode = TextServer.AUTOWRAP_OFF
	high.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ends.add_child(low)
	ends.add_child(high)
	box.add_child(ends)
	return box


func _swatch(step: Dictionary) -> Control:
	var sw := _Swatch.new()
	sw.step = step
	return _clipped(sw, SWATCH)


## A swatch inside a clip of its own size, so a hatch drawn past its edge never strays onto the card.
static func _clipped(swatch: Control, at_size: Vector2) -> Control:
	var clip := Control.new()
	clip.name = "Swatch"
	clip.clip_contents = true
	clip.custom_minimum_size = at_size
	clip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.custom_minimum_size = at_size
	clip.add_child(swatch)
	swatch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return clip


## The sight legend's rows (FogView.legend_rows): the veil's swatch for each level, its title and what it means in short.
func _sight_rows(rows: Array) -> Control:
	var grid := GridContainer.new()
	grid.name = "SightRows"
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 2)
	for r in rows:
		grid.add_child(_clipped(ProvinceRegion.legend_swatch(String(r.key)), Vector2(36, 20)))
		var l := _label("SightRow", "%s: %s" % [String(r.title), String(r.short)], UiPalette.TYPE_SMALL, UiPalette.TEXT_SECONDARY)
		l.custom_minimum_size = Vector2(W - 70.0, 0)
		l.tooltip_text = TooltipText.wrap_text(String(r.text))
		grid.add_child(l)
	return grid


## One swatch: its colour, and the mark that says it without colour (a seat emblem, a density of hatching, sigils, rings or pips).
class _Swatch extends Control:
	var step := {}

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var c: Color = step.get("colour", Color.GRAY)
		draw_rect(r, c)
		match String(step.get("pattern", "")):
			"hatch":
				var gap := lerpf(8.0, 3.0, float(step.get("density", 0.5)))
				var x := -size.y
				while x < size.x:
					draw_line(Vector2(x, 0), Vector2(x + size.y, size.y), Color(MapLens.THREAT_INK, 0.9), 1.2, true)
					x += gap
			"sigil":
				draw_arc(r.get_center(), 4.5, 0.0, TAU, 16, Color.WHITE.lerp(c, 0.3), 1.2, true)
			"ring":
				draw_rect(r.grow(-2.0), Color("#FFD27A"), false, 2.0)
			"pips":
				var n := int(step.get("pips", 0))
				for i in n:
					draw_circle(Vector2(5.0 + i * 7.0, size.y * 0.5), 2.6, UiPalette.KEYLINE_INK)
			"circle", "square", "triangle", "diamond", "hexagon", "cross", "shield":
				SeatEmblem.draw_emblem(self, r.get_center(), minf(size.x, size.y) * 0.5 - 2.0, int(step.get("seat", -1)))
		draw_rect(r, UiPalette.KEYLINE_INK, false, 1.0)
