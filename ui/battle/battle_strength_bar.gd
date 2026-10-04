class_name BattleStrengthBar
extends Control
## A side's strength bar (M3-3, #58; design/M3_BATTLES.md §4.7, §4.8): hp left as a share of the side's
## starting hp in its seat's colour with keylines and its emblem at the bar's start, the round's pending
## damage as a hatched chunk at the fill's end (so the pattern carries it as well as the colour), and the
## break notch: a white line with ink keylines and two ticks, where the side breaks. "BROKE" (with a broken
## banner) or "NO ONE LEFT" when the side is out, and Iron Discipline's gilt chain on the notch while it
## holds. Mirrored for the right side, so both bars drain toward the centre. The numbers all come from
## BattleExplain.side_strength; this only draws them.

const NOTCH_SLIDE := 0.4
const EMBLEM := 24.0

var seat := -1
var mirrored := false
var fill := 1.0
var pending_share := 0.0
var out := ""
var held := false
var _notch := 0.35
var _notch_from := 0.35
var _notch_to := 0.35
var _notch_t := -1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(520, 22)


## Shows strength `st` (BattleExplain.side_strength). With `slide`, a moved notch slides over 0.4 s.
func set_strength(st: Dictionary, slide: bool = false) -> void:
	fill = clampf(float(st.fill), 0.0, 1.0)
	pending_share = clampf(float(st.pending) / maxf(1.0, float(st.hp_start)), 0.0, fill)
	out = String(st.out)
	held = bool(st.held)
	var n := clampf(float(st.notch), 0.0, 1.0)
	if slide and absf(n - _notch_to) > 0.0001:
		_notch_from = _notch
		_notch_to = n
		_notch_t = 0.0
	elif not slide:
		_notch = n
		_notch_to = n
		_notch_t = -1.0
	queue_redraw()


## The notch's share now (it may be sliding).
func notch() -> float:
	return _notch


func animate(dt: float) -> bool:
	if _notch_t < 0.0:
		return false
	_notch_t += dt
	var p := clampf(_notch_t / NOTCH_SLIDE, 0.0, 1.0)
	_notch = lerpf(_notch_from, _notch_to, ease(p, 0.5))
	if p >= 1.0:
		_notch_t = -1.0
	queue_redraw()
	return _notch_t >= 0.0


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var bar := Rect2(EMBLEM + 6.0, 0.0, r.size.x - EMBLEM - 6.0, r.size.y)
	var em := Vector2(EMBLEM / 2.0, r.size.y / 2.0)
	if mirrored:
		bar.position.x = 0.0
		em.x = r.size.x - EMBLEM / 2.0
	SeatEmblem.draw_emblem(self, em, EMBLEM / 2.0 - 3.0, seat)
	draw_rect(bar.grow(2.0), UiPalette.KEYLINE_HALO)
	draw_rect(bar.grow(1.0), UiPalette.KEYLINE_INK)
	draw_rect(bar, UiPalette.PANEL_BG)
	var w := bar.size.x
	var fill_rect := Rect2(bar.position, Vector2(w * fill, bar.size.y))
	if mirrored:
		fill_rect.position.x = bar.end.x - w * fill
	draw_rect(fill_rect, UiPalette.seat_color(seat))
	if pending_share > 0.0:
		var chunk := Rect2(bar.position.x + w * (fill - pending_share), bar.position.y, w * pending_share, bar.size.y)
		if mirrored:
			chunk.position.x = bar.end.x - w * fill
		BattleCard.hatch(self, chunk, UiPalette.NEGATIVE)
	# The break notch.
	var nx := bar.position.x + w * _notch
	if mirrored:
		nx = bar.end.x - w * _notch
	draw_line(Vector2(nx, bar.position.y - 4.0), Vector2(nx, bar.end.y + 4.0), UiPalette.KEYLINE_INK, 5.0)
	draw_line(Vector2(nx, bar.position.y - 3.0), Vector2(nx, bar.end.y + 3.0), UiPalette.SELECTION, 3.0)
	if held:
		BattleCard.draw_glyph(self, "iron", Vector2(nx, bar.position.y - 2.0), 14.0)
	if not out.is_empty():
		var font := get_theme_default_font()
		var text := "BROKE" if out == "routed" else "NO ONE LEFT"
		var fs := 16
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2(bar.position.x + (bar.size.x - tw) / 2.0, bar.position.y + bar.size.y / 2.0 + fs * 0.35)
		if out == "routed":
			_broken_banner(Vector2(pos.x - 14.0, bar.position.y + bar.size.y / 2.0), 14.0)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, UiPalette.KEYLINE_INK)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiPalette.TEXT_PRIMARY)


## A broken banner: a snapped pole and a torn flag (the glyph that goes with "BROKE").
func _broken_banner(c: Vector2, h: float) -> void:
	var half := h / 2.0
	draw_line(c + Vector2(-half * 0.4, half), c + Vector2(-half * 0.1, -half * 0.1), UiPalette.KEYLINE_INK, 3.0)
	draw_line(c + Vector2(0.0, -half * 0.25), c + Vector2(half * 0.3, -half), UiPalette.KEYLINE_INK, 3.0)
	var flag := PackedVector2Array([c + Vector2(half * 0.3, -half), c + Vector2(half, -half * 0.6), c + Vector2(half * 0.45, -half * 0.25)])
	draw_colored_polygon(flag, UiPalette.NEGATIVE)
