class_name ForecastGlance
extends PanelContainer
## UX-3 (the director's review of #208): the hover forecast of a march destination, compact. It is MapScreen.hover_panel: it holds a mark
## (a UiIcons icon for the kind of move), two or three short lines (MoveGlance), and an "i" button whose tooltip is the full forecast, word for
## word, with the codex entry it links (right-click or F1 on the "i"). It no longer floats over the map: the selection cards adopt it
## (SelectionCards.adopt_forecast) into the slot under an army's actions and into the march strip, so it never covers the board.
##
## `visible` is "a forecast is showing" (the board's dashed path reads it); a forecast whose pointer left the province is `stale` (drawn
## dimmer) and stays until another province is hovered or the selection or the orders change, so the pointer can travel to the "i".
##
## API:
##   show_glance(glance, open_codex)   a MoveGlance.build result: the lines and the full text
##   clear()                           hard: nothing to show
##   set_stale(on)                     the pointer left; keep reading
##   full_text                         the full forecast (OrdersController.move_preview's text), "" when nothing shows
##   lines() -> Array                  the line texts now shown

const ICON_PX := 20
const MAX_LINES := 3

var full_text := ""
var glance := {}
var stale := false
var icon_rect: TextureRect
var info_button: Button
var _lines_box: VBoxContainer


func _init() -> void:
	name = "HoverPreview"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.PANEL_RAISED
	style.border_color = UiPalette.GILT
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	icon_rect = TextureRect.new()
	icon_rect.name = "ForecastIcon"
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon_rect.custom_minimum_size = Vector2(ICON_PX + 2, ICON_PX + 2)
	icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_rect.self_modulate = UiPalette.GILT
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_rect)
	_lines_box = VBoxContainer.new()
	_lines_box.name = "ForecastLines"
	_lines_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lines_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_lines_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines_box.add_theme_constant_override("separation", 0)
	row.add_child(_lines_box)
	info_button = Button.new()
	info_button.name = "ForecastInfo"
	info_button.text = "ⓘ"
	info_button.flat = true
	info_button.focus_mode = Control.FOCUS_NONE
	info_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_button.add_theme_font_size_override("font_size", 18)
	info_button.add_theme_color_override("font_color", UiPalette.LINK)
	info_button.add_theme_color_override("font_hover_color", UiPalette.GILT)
	row.add_child(info_button)


## Shows a MoveGlance.build result. `open_codex` is what a right-click on the "i" calls with its codex key.
func show_glance(g: Dictionary, open_codex: Callable = Callable()) -> void:
	glance = g
	full_text = String(g.get("full", ""))
	for c in _lines_box.get_children():
		_lines_box.remove_child(c)
		c.queue_free()
	var lines: Array = g.get("lines", [])
	for i in mini(lines.size(), MAX_LINES):
		var l := Label.new()
		l.name = "ForecastLine_%d" % i
		l.text = String(lines[i])
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not bool(g.get("ok", true)) and i == 1:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # the rules' reason for a refused destination: two short lines
			l.max_lines_visible = 2
			l.custom_minimum_size.x = 60
		else:
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			l.clip_text = true
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.add_theme_font_size_override("font_size", 15 if i == 0 else UiPalette.TYPE_SMALL)
		l.add_theme_color_override("font_color", (UiPalette.NEGATIVE.lightened(0.25) if not bool(g.get("ok", true)) and i == 1
			else (UiPalette.TEXT_PRIMARY if i == 0 else UiPalette.TEXT_SECONDARY)))
		_lines_box.add_child(l)
	icon_rect.texture = UiIcons.icon(String(g.get("icon", "march")), ICON_PX)
	info_button.tooltip_text = TooltipText.wrap_text(full_text)
	var key := String(g.get("codex", "move"))
	if open_codex.is_valid():
		CodexLink.attach(info_button, key, open_codex)
	set_stale(false)
	visible = true


## Nothing to show: no lines, no text, hidden.
func clear() -> void:
	glance = {}
	full_text = ""
	for c in _lines_box.get_children():
		_lines_box.remove_child(c)
		c.queue_free()
	set_stale(false)
	visible = false


## The pointer left its province: the forecast stays, dimmer, until another province is hovered or the selection or the orders change.
func set_stale(on: bool) -> void:
	stale = on
	modulate = Color(1, 1, 1, 0.72) if on else Color.WHITE


## The texts of the lines now shown.
func lines() -> Array:
	var out := []
	for c in _lines_box.get_children():
		if c is Label and not c.is_queued_for_deletion():
			out.append((c as Label).text)
	return out
