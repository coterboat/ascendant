class_name NumberBadge
extends Control
## UX-6 (design/UX_WAR_TABLE.md §5.2, "Markers"): a small numbered disc. A card in the Chronicle wears one, and the board shows the same
## number at the card's province, so the eye finds where it happened. It never takes the mouse. `pulse()` swells it once.

const SIZE := 24.0

var number := 0


func _init(n: int = 0, px: float = SIZE) -> void:
	number = n
	custom_minimum_size = Vector2(px, px)
	size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = Vector2(px, px) * 0.5


func set_number(n: int) -> void:
	number = n
	queue_redraw()


## A short swell, so a focused marker is easy to find.
func pulse() -> void:
	if not is_inside_tree():
		return
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(1.7, 1.7), 0.16).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BOUNCE)


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5 - 1.0
	var c := size * 0.5
	draw_circle(c, r, UiPalette.GILT)
	draw_arc(c, r, 0.0, TAU, 32, UiPalette.KEYLINE_INK, 2.0, true)
	var font := UiFonts.number()
	var fs := int(r * 1.25)
	var text := str(number)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(font, Vector2(c.x - w.x * 0.5, c.y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiPalette.KEYLINE_INK)
