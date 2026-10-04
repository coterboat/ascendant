class_name BattleScrubber
extends Control
## The round scrubber (M3-3, #58; design/M3_BATTLES.md §5.1): one tick per round, the playhead, and a
## key-moment marker at each moment's time, each kind its own shape. Click or drag anywhere to see that
## point of the battle at once (the view seeks the BattlePlayer; no animation replays while dragging).
## Hovering a marker names the moment. Times are seconds at 1x.

signal scrubbed(t: float)
signal released

const PAD := 16.0

var duration := 1.0
var time := 0.0:
	set(value):
		if absf(value - time) > 0.0001:
			time = value
			queue_redraw()
var rounds: Array = []  # [{"round", "t"}]
var marks: Array = []  # [{"t", "kind", "text"}]
var _dragging := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(1200, 40)
	tooltip_text = "Click or drag to see any point of the battle."


func is_dragging() -> bool:
	return _dragging


func x_of(t: float) -> float:
	return PAD + (size.x - 2.0 * PAD) * clampf(t / maxf(duration, 0.001), 0.0, 1.0)


func t_of(x: float) -> float:
	return clampf((x - PAD) / maxf(1.0, size.x - 2.0 * PAD), 0.0, 1.0) * duration


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_dragging = true
			scrubbed.emit(t_of(mb.position.x))
		elif _dragging:
			_dragging = false
			released.emit()
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _dragging:
		scrubbed.emit(t_of(mm.position.x))
		accept_event()


func _get_tooltip(at_position: Vector2) -> String:
	for m in marks:
		if absf(x_of(float(m.t)) - at_position.x) <= 8.0 and at_position.y < size.y * 0.6:
			return TooltipText.wrap_text(String(m.text)) + "\n\nClick to jump there."
	for r in rounds:
		if absf(x_of(float(r.t)) - at_position.x) <= 6.0:
			return "Round %d starts here.\n\nClick or drag to see any point of the battle." % int(r.round)
	return tooltip_text


func _draw() -> void:
	var y := size.y * 0.62
	var x0 := PAD
	var x1 := size.x - PAD
	draw_line(Vector2(x0, y), Vector2(x1, y), UiPalette.KEYLINE_INK, 8.0)
	draw_line(Vector2(x0, y), Vector2(x1, y), UiPalette.PANEL_BORDER, 4.0)
	draw_line(Vector2(x0, y), Vector2(x_of(time), y), UiPalette.GILT, 4.0)
	var font := get_theme_default_font()
	for r in rounds:
		var x := x_of(float(r.t))
		draw_line(Vector2(x, y - 7.0), Vector2(x, y + 7.0), UiPalette.TEXT_SECONDARY, 2.0)
		draw_string(font, Vector2(x + 3.0, size.y - 1.0), str(int(r.round)), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiPalette.TEXT_SECONDARY)
	for m in marks:
		draw_moment_icon(self, String(m.kind), Vector2(x_of(float(m.t)), y - 14.0), 12.0)
	var px := x_of(time)
	draw_circle(Vector2(px, y), 8.0, UiPalette.KEYLINE_INK)
	draw_circle(Vector2(px, y), 6.0, UiPalette.TEXT_PRIMARY)


## A key moment's marker (each kind its own shape, §7.1): first to fall a drop, charge a chevron, a ruler's
## fall a crown, the turning point a diamond, a rout a broken banner.
static func draw_moment_icon(ci: CanvasItem, kind: String, c: Vector2, size: float) -> void:
	var h := size / 2.0
	var ink := UiPalette.KEYLINE_INK
	var pts := PackedVector2Array()
	var col := UiPalette.TEXT_PRIMARY
	match kind:
		"first_blood":
			pts = PackedVector2Array([c + Vector2(0, -h), c + Vector2(h * 0.75, h * 0.25), c + Vector2(0, h), c + Vector2(-h * 0.75, h * 0.25)])
			col = UiPalette.NEGATIVE
		"charge":
			pts = PackedVector2Array([c + Vector2(-h, -h), c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, h), c + Vector2(0, 0)])
			col = UiPalette.GILT
		"ruler_falls":
			pts = PackedVector2Array([c + Vector2(-h, h * 0.6), c + Vector2(-h, -h * 0.5), c + Vector2(-h * 0.45, 0), c + Vector2(0, -h),
				c + Vector2(h * 0.45, 0), c + Vector2(h, -h * 0.5), c + Vector2(h, h * 0.6)])
			col = UiPalette.GILT
		"turning_point":
			pts = PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)])
			col = UiPalette.TEXT_PRIMARY
		_:
			pts = PackedVector2Array([c + Vector2(-h * 0.6, -h), c + Vector2(h, -h * 0.55), c + Vector2(-h * 0.1, -h * 0.1), c + Vector2(h * 0.2, h),
				c + Vector2(-h * 0.6, h)])
			col = UiPalette.NEGATIVE
	var outline := PackedVector2Array()
	for p in pts:
		var v := p - c
		outline.append(c + v + v.normalized() * 1.5 if v.length() > 0.01 else p)
	ci.draw_colored_polygon(outline, ink)
	ci.draw_colored_polygon(pts, col)
