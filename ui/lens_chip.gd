class_name LensChip
extends PanelContainer
## UX-7 (#217; design/UX_WAR_TABLE.md §4.0): a province plate's lens value, while a lens is on. The same chip sits on the 3D board's
## plates (BoardOverlay.set_lens) and on the 2D map's regions (ProvinceRegion.set_lens), so the two boards never disagree: it draws
## MapLens.build's entry for the province. Its icon (UiIcons) or mark says which lens it is without colour: Owner the owner's seat
## emblem, Income a coin, Threat the strength mark, Magic the arcana, Making its pips (up to four, filled in the owner's colour), Sight
## the eye. Its hover is the lens value with its breakdown (MapLens's tooltip), and a right-click or F1 opens the lens's codex entry.
## A nothing-here value (no threat seen, no magic) is drawn faint.

const PIP_R := 4.5
const PIP_GAP := 3.0

var lens_id := ""
var entry := {}
var label: Label
var icon_rect: TextureRect
var emblem: SeatEmblem
var pips: _Pips


## A chip for `entry` (MapLens.build's) of lens `id`; `open` is called with a codex key on a right-click or F1.
static func make(id: String, p_entry: Dictionary, open: Callable = Callable()) -> LensChip:
	var chip := LensChip.new()
	chip.set_entry(id, p_entry, open)
	return chip


func _init() -> void:
	name = "LensValue"
	mouse_filter = Control.MOUSE_FILTER_PASS
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 3)
	add_child(row)
	icon_rect = TextureRect.new()
	icon_rect.name = "Icon"
	icon_rect.custom_minimum_size = Vector2(UiIcons.SIZE_SMALL, UiIcons.SIZE_SMALL)
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_rect)
	emblem = SeatEmblem.new(-1, SeatEmblem.Look.TOKEN, 13.0)
	emblem.name = "Emblem"
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(emblem)
	pips = _Pips.new()
	pips.name = "Pips"
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pips)
	label = Label.new()
	label.name = "Value"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UiFonts.number())
	label.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	row.add_child(label)


func set_entry(id: String, p_entry: Dictionary, open: Callable = Callable()) -> void:
	lens_id = id
	entry = p_entry
	var dim := bool(entry.get("dim", false))
	var tint: Color = entry.get("tint", UiPalette.GILT)
	label.text = String(entry.get("text", ""))
	label.add_theme_color_override("font_color", UiPalette.TEXT_DISABLED if dim else UiPalette.TEXT_PRIMARY)
	var icon_name := String(entry.get("icon", ""))
	icon_rect.visible = not icon_name.is_empty()
	if icon_rect.visible:
		icon_rect.texture = UiIcons.icon(icon_name, UiIcons.SIZE_SMALL)
		icon_rect.modulate = UiPalette.TEXT_DISABLED if dim else _accent(tint)
	emblem.visible = id == "owner"
	if emblem.visible:
		emblem.seat = int(entry.get("seat", -1))
		emblem.queue_redraw()
	pips.visible = int(entry.get("pips", -1)) >= 0
	if pips.visible:
		pips.marks = int(entry.pips)
		pips.colour = entry.get("pip_colour", Color.WHITE)
		pips.custom_minimum_size = Vector2(MapLens.MAKING_MAX * (PIP_R * 2.0 + PIP_GAP) - PIP_GAP + 2.0, PIP_R * 2.0 + 2.0)
		pips.queue_redraw()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiPalette.KEYLINE_INK, 0.78)
	sb.border_color = Color(_accent(tint), 0.35 if dim else 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 5
	sb.content_margin_right = 6
	sb.content_margin_top = 0
	sb.content_margin_bottom = 1
	add_theme_stylebox_override("panel", sb)
	tooltip_text = String(entry.get("tooltip", ""))
	var key := String(MapLens.lens(id).get("codex", ""))
	CodexLink.attach(self, key, open if open.is_valid() else func(_k): pass)
	reset_size()


## The chip's accent: the lens colour, lifted so it reads on the ink plate.
static func _accent(c: Color) -> Color:
	var l := MapLens.luminance(c)
	return c.lerp(Color.WHITE, clampf(0.55 - l, 0.0, 0.5))


## Making's marks: four pips, the first `marks` filled in the owner's colour with an ink keyline, the rest hollow, so the count reads
## without colour.
class _Pips extends Control:
	var marks := 0
	var colour := Color.WHITE

	func _draw() -> void:
		for i in MapLens.MAKING_MAX:
			var c := Vector2(1.0 + LensChip.PIP_R + i * (LensChip.PIP_R * 2.0 + LensChip.PIP_GAP), size.y * 0.5)
			if i < marks:
				draw_circle(c, LensChip.PIP_R + 1.0, UiPalette.KEYLINE_HALO)
				draw_circle(c, LensChip.PIP_R, colour)
				draw_arc(c, LensChip.PIP_R, 0.0, TAU, 16, UiPalette.KEYLINE_INK, 1.2, true)
			else:
				draw_arc(c, LensChip.PIP_R - 0.5, 0.0, TAU, 16, Color(UiPalette.TEXT_SECONDARY, 0.7), 1.2, true)
