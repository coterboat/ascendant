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
	paint(self, Rect2(Vector2.ZERO, size), seat, mirrored, fill, pending_share, _notch, out, held)


## Draws a strength bar into `r` of `ci` (the legend draws its rows with this same function): the seat's
## emblem at the bar's start, the fill in the seat's colour, the hatched pending chunk, the break notch at
## share `notch_share` (with Iron Discipline's chain while `is_held`) and BROKE / NO ONE LEFT when `out_kind`
## is "routed" / "destroyed".
static func paint(ci: CanvasItem, r: Rect2, p_seat: int, p_mirrored: bool, p_fill: float, p_pending: float, notch_share: float,
		out_kind: String, is_held: bool) -> void:
	var bar := Rect2(r.position.x + EMBLEM + 6.0, r.position.y, r.size.x - EMBLEM - 6.0, r.size.y)
	var em := Vector2(r.position.x + EMBLEM / 2.0, r.position.y + r.size.y / 2.0)
	if p_mirrored:
		bar.position.x = r.position.x
		em.x = r.end.x - EMBLEM / 2.0
	SeatEmblem.draw_emblem(ci, em, EMBLEM / 2.0 - 3.0, p_seat)
	ci.draw_rect(bar.grow(2.0), UiPalette.KEYLINE_HALO)
	ci.draw_rect(bar.grow(1.0), UiPalette.KEYLINE_INK)
	ci.draw_rect(bar, UiPalette.PANEL_BG)
	var w := bar.size.x
	var fill_rect := Rect2(bar.position, Vector2(w * p_fill, bar.size.y))
	if p_mirrored:
		fill_rect.position.x = bar.end.x - w * p_fill
	ci.draw_rect(fill_rect, UiPalette.seat_color(p_seat))
	if p_pending > 0.0:
		var chunk := Rect2(bar.position.x + w * (p_fill - p_pending), bar.position.y, w * p_pending, bar.size.y)
		if p_mirrored:
			chunk.position.x = bar.end.x - w * p_fill
		BattleCard.hatch(ci, chunk, UiPalette.NEGATIVE)
	var nx := bar.position.x + w * notch_share
	if p_mirrored:
		nx = bar.end.x - w * notch_share
	draw_notch(ci, nx, bar.position.y, bar.end.y, is_held)
	if not out_kind.is_empty():
		var font: Font = (ci as Control).get_theme_default_font() if ci is Control else ThemeDB.fallback_font
		var text := "BROKE" if out_kind == "routed" else "NO ONE LEFT"
		var fs := 16 if r.size.y >= 18.0 else 10  # 10 only in the legend's small swatches
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2(bar.position.x + (bar.size.x - tw) / 2.0, bar.position.y + bar.size.y / 2.0 + fs * 0.35)
		if out_kind == "routed":
			draw_broken_banner(ci, Vector2(pos.x - 14.0, bar.position.y + bar.size.y / 2.0), 14.0)
		ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, UiPalette.KEYLINE_INK)
		ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiPalette.TEXT_PRIMARY)


## The break notch at x `nx` from `top` to `bottom`: a white line with ink keylines, and Iron Discipline's
## gilt chain on it while it holds a side.
static func draw_notch(ci: CanvasItem, nx: float, top: float, bottom: float, is_held: bool) -> void:
	ci.draw_line(Vector2(nx, top - 4.0), Vector2(nx, bottom + 4.0), UiPalette.KEYLINE_INK, 5.0)
	ci.draw_line(Vector2(nx, top - 3.0), Vector2(nx, bottom + 3.0), UiPalette.SELECTION, 3.0)
	if is_held:
		BattleCard.draw_glyph(ci, "iron", Vector2(nx, top - 2.0), 14.0)


## A broken banner: a snapped pole and a torn flag (the glyph that goes with "BROKE").
static func draw_broken_banner(ci: CanvasItem, c: Vector2, h: float) -> void:
	var half := h / 2.0
	ci.draw_line(c + Vector2(-half * 0.4, half), c + Vector2(-half * 0.1, -half * 0.1), UiPalette.KEYLINE_INK, 3.0)
	ci.draw_line(c + Vector2(0.0, -half * 0.25), c + Vector2(half * 0.3, -half), UiPalette.KEYLINE_INK, 3.0)
	var flag := PackedVector2Array([c + Vector2(half * 0.3, -half), c + Vector2(half, -half * 0.6), c + Vector2(half * 0.45, -half * 0.25)])
	ci.draw_colored_polygon(flag, UiPalette.NEGATIVE)


## The look of a side's morale tag under its bar ("-4 morale: the Knight Captain fell. Morale check:
## holds"): gilt text with an ink outline, so it reads over the field. The view's tags and the legend's
## row both use it.
static func style_tag(l: Label, font_size: int = 16) -> void:
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", UiPalette.GILT)
	l.add_theme_color_override("font_outline_color", UiPalette.KEYLINE_INK)
	l.add_theme_constant_override("outline_size", 4)
