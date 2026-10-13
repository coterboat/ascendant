class_name BattleScrubber
extends Control
## The round scrubber (M3-3, #58; design/M3_BATTLES.md §5.1): one tick per round, the playhead, and a
## key-moment marker at each moment's time, each kind its own shape. Click or drag anywhere to see that
## point of the battle at once (the view seeks the BattlePlayer; no animation replays while dragging).
## Times are seconds at 1x.
## UX-8 (#221, design/UX_WAR_TABLE.md §6): the markers replace the row of moment buttons. Each marker is a moment of this
## battle (a kind it lacks has none): hovering it names the moment, a click jumps to it (moment_pressed; the controls
## jump the player there with the lead-in), a right-click or F1 opens its codex entry. Markers too close to sit side by
## side stack in a second lane above the first.

signal scrubbed(t: float)
signal released
## UX-8: a marker was clicked: marks[index].
signal moment_pressed(index: int)
signal codex_requested(key: String)

const PAD := 16.0
## A marker's size and the reach of its hover and click, in px.
const MARK := 12.0
const MARK_REACH := 8.0
## How far below the top the line sits (the markers' lanes are above it, the round numbers below).
const LINE_FROM_BOTTOM := 14.0
const LANE := 14.0

var duration := 1.0
var time := 0.0:
	set(value):
		if absf(value - time) > 0.0001:
			time = value
			queue_redraw()
var rounds: Array = []  # [{"round", "t"}]
## [{"t", "kind", "text", "tip", "codex", "lane"}]: set_marks() fills "lane".
var marks: Array = []
## The plain reasons for the kinds this battle has no moment of (the moment buttons' disabled tooltips before UX-8).
var missing_lines: Array = []
var hovered := -1
var _dragging := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(160, 48)
	tooltip_text = "Click or drag to see any point of the battle."


## Sets the markers and keeps them apart: in time order, a marker too close to the last one in lane 0 goes up to lane 1,
## and when both lanes are taken there it steps right just enough to stand clear (its "dx").
func set_marks(p_marks: Array) -> void:
	marks = p_marks.duplicate(true)
	marks.sort_custom(func(a, b): return float(a.t) < float(b.t))
	_assign_lanes()
	hovered = -1
	queue_redraw()


func _assign_lanes() -> void:
	var last := [-INF, -INF]
	for m in marks:
		var x := x_of(float(m.t))
		var dx := 0.0
		var lane := 0
		if x - float(last[0]) < MARK + 2.0:
			lane = 1
			if x - float(last[1]) < MARK + 2.0:
				lane = 0 if float(last[0]) <= float(last[1]) else 1
				dx = float(last[lane]) + MARK + 2.0 - x
		m["lane"] = lane
		m["dx"] = dx
		last[lane] = x + dx


func is_dragging() -> bool:
	return _dragging


func line_y() -> float:
	return size.y - LINE_FROM_BOTTOM


func x_of(t: float) -> float:
	return PAD + (size.x - 2.0 * PAD) * clampf(t / maxf(duration, 0.001), 0.0, 1.0)


func t_of(x: float) -> float:
	return clampf((x - PAD) / maxf(1.0, size.x - 2.0 * PAD), 0.0, 1.0) * duration


## Where marker `i` is drawn (its centre, in the scrubber's coordinates).
func mark_point(i: int) -> Vector2:
	var m: Dictionary = marks[i]
	return Vector2(x_of(float(m.t)) + float(m.get("dx", 0.0)), line_y() - LANE - float(m.get("lane", 0)) * LANE)


## The marker under `p`, or -1 (the nearest one within MARK_REACH).
func mark_at(p: Vector2) -> int:
	var best := -1
	var gap := INF
	for i in marks.size():
		var d := p - mark_point(i)
		if absf(d.x) <= MARK_REACH and absf(d.y) <= MARK_REACH and d.length() < gap:
			gap = d.length()
			best = i
	return best


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not marks.is_empty():
		_assign_lanes()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_set_hovered(-1)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		var r := mark_at(mb.position)
		if r >= 0 and RulesCodex.ENTRIES.has(String(marks[r].get("codex", ""))):
			codex_requested.emit(String(marks[r].codex))
			accept_event()
		return
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			var i := mark_at(mb.position)
			if i >= 0:
				moment_pressed.emit(i)
				accept_event()
				return
			_dragging = true
			scrubbed.emit(t_of(mb.position.x))
		elif _dragging:
			_dragging = false
			released.emit()
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		if _dragging:
			scrubbed.emit(t_of(mm.position.x))
			accept_event()
			return
		_set_hovered(mark_at(mm.position))


## F1 over a marker opens its codex entry: CodexLink.key_at reads the hovered marker's key from this meta.
func _set_hovered(i: int) -> void:
	if i == hovered:
		return
	hovered = i
	if i >= 0 and RulesCodex.ENTRIES.has(String(marks[i].get("codex", ""))):
		set_meta(CodexLink.META, String(marks[i].codex))
	elif has_meta(CodexLink.META):
		remove_meta(CodexLink.META)
	queue_redraw()


func _get_tooltip(at_position: Vector2) -> String:
	var i := mark_at(at_position)
	if i >= 0:
		return String(marks[i].get("tip", marks[i].text))
	for r in rounds:
		if absf(x_of(float(r.t)) - at_position.x) <= 6.0:
			return "Round %d starts here.\n\n%s" % [int(r.round), base_tooltip()]
	return base_tooltip()


## The scrubber's own words: how it works, what the markers are, and which key moments this battle doesn't have.
func base_tooltip() -> String:
	var text := tooltip_text + " The marks above the line are the battle's key moments: click one to jump there."
	if not missing_lines.is_empty():
		text += "\n\nNot in this battle:\n" + "\n".join(missing_lines.map(func(l): return TooltipText.wrap_text(String(l))))
	return text


func _draw() -> void:
	var y := line_y()
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
	for i in marks.size():
		var c := mark_point(i)
		if i == hovered:
			draw_circle(c, MARK * 0.85, Color(UiPalette.SELECTION, 0.25))
		draw_moment_icon(self, String(marks[i].kind), c, MARK)
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
		"spell":
			# M5-7: a four-pointed spark.
			var k := h * 0.32
			pts = PackedVector2Array([c + Vector2(0, -h), c + Vector2(k, -k), c + Vector2(h, 0), c + Vector2(k, k), c + Vector2(0, h),
				c + Vector2(-k, k), c + Vector2(-h, 0), c + Vector2(-k, -k)])
			col = UiPalette.GILT
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
