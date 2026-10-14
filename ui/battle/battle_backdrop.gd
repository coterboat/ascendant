class_name BattleBackdrop
extends Control
## The Simple view's field backdrop (M3-3, #58; design/M3_BATTLES.md §3.3): a code sky gradient, the
## horizon (a silhouette 25% darker than the ground: bumps for forest, long curves for hills, flat for plains),
## and the ground: the terrain texture tiled when it exists, the bible's flat terrain colour otherwise, so it
## works with no art at all. A border battle gets plains with a dashed map-ink line down the centre and the
## two province names at its top. A fort is drawn only when someone defends it (only a defender gets its
## bonus): a crenellated wall with a gatehouse in map ink along the horizon of the defender's half.

const SKY_TOP := Color("#A9CBE6")
const SKY_BOTTOM := Color("#E9EEF0")
const HORIZON_H := 100.0

## UX-8: where the horizon runs, from the top (the view lays the backdrop out full-bleed and puts the horizon a little
## below its plates, over the cards' band); HORIZON_H by default.
var horizon := HORIZON_H:
	set(value):
		if absf(value - horizon) > 0.01:
			horizon = value
			queue_redraw()
## UX-8: the width the two sides stand across (the cards' band, narrower than the backdrop while the why panel is
## docked): the border line and the defender's fort are drawn on its halves. 0: the backdrop's own width.
var span_w := 0.0:
	set(value):
		if absf(value - span_w) > 0.01:
			span_w = value
			queue_redraw()
var terrain := "plains"
var border := false
var border_names: Array = []
var fort_on := ""  # "" | "left" | "right": where a defended fort stands
var _texture: Texture2D = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func setup(battle_log: Dictionary, defender_on: String) -> void:
	border = battle_log.get("kind", "province") == "border"
	terrain = "plains" if border or String(battle_log.get("terrain", "")).is_empty() else String(battle_log.terrain)
	_texture = Art.terrain(terrain)
	border_names = []
	if border:
		for pid in battle_log.get("provinces", []):
			border_names.append(province_name(String(pid)))
	fort_on = defender_on if battle_log.get("fort", false) and not defender_on.is_empty() else ""
	queue_redraw()


func has_art() -> bool:
	return _texture != null


## Drops the terrain art: the ground becomes the bible's flat terrain colour.
func clear_art() -> void:
	_texture = null
	queue_redraw()


## A province's player-facing name from the map data (never its id).
static func province_name(pid: String) -> String:
	for p in MapData.PROVINCES:
		if p.id == pid:
			return String(p.name)
	return pid.capitalize()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var ground_col := UiPalette.terrain_color(terrain)
	# Sky.
	var sky := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, horizon), Vector2(0, horizon)])
	draw_polygon(sky, PackedColorArray([SKY_TOP, SKY_TOP, SKY_BOTTOM, SKY_BOTTOM]))
	# Ground.
	var ground := Rect2(0, horizon, w, h - horizon)
	if _texture != null:
		# 50% horizontal and 30% vertical scale, so the ground suggests the high angle (§3.3).
		draw_set_transform(ground.position, 0.0, Vector2(0.5, 0.3))
		draw_texture_rect(_texture, Rect2(Vector2.ZERO, ground.size / Vector2(0.5, 0.3)), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# Calm the tile under the flat anchor colour, so the cards stay what the eye reads first.
		draw_rect(ground, Color(ground_col, 0.7))
	else:
		draw_rect(ground, ground_col)
	# Horizon silhouette, 25% darker than the ground.
	var sil := ground_col.darkened(0.25)
	var pts := PackedVector2Array()
	pts.append(Vector2(0, horizon + 6))
	var steps := 64
	for k in steps + 1:
		var x := w * k / steps
		var y := horizon - 6.0
		match terrain:
			"forest":
				y = horizon - 14.0 - absf(sin(k * 1.7)) * 16.0 - absf(sin(k * 0.45)) * 8.0
			"hills":
				y = horizon - 18.0 - sin(k / float(steps) * TAU * 1.5 + 0.6) * 16.0
		pts.append(Vector2(x, y))
	pts.append(Vector2(w, horizon + 6))
	draw_colored_polygon(pts, sil)
	draw_line(Vector2(0, horizon + 6), Vector2(w, horizon + 6), Color(UiPalette.KEYLINE_INK, 0.35), 2.0)
	# A defended fort behind the defender's back line.
	if not fort_on.is_empty():
		_draw_fort()
	# A border: a dashed map-ink line down the centre with both province names at its top.
	var cw := span_w if span_w > 0.0 else w
	if border:
		var y := horizon + 10.0
		while y < h:
			draw_line(Vector2(cw / 2.0, y), Vector2(cw / 2.0, minf(y + 14.0, h)), Color(UiPalette.MAP_INK, 0.8), 3.0)
			y += 24.0
		var font := get_theme_default_font()
		if border_names.size() == 2:
			var fs := 16
			var left_name := String(border_names[0])
			var lw := font.get_string_size(left_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			_label(font, Vector2(cw / 2.0 - lw - 12.0, horizon + 28.0), left_name, fs)
			_label(font, Vector2(cw / 2.0 + 12.0, horizon + 28.0), String(border_names[1]), fs)


func _label(font: Font, pos: Vector2, text: String, fs: int) -> void:
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, UiPalette.KEYLINE_HALO)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiPalette.MAP_INK)


func _draw_fort() -> void:
	# A wall along the horizon on the defender's half, with a gatehouse: the fort stands behind the
	# defender's ranks without covering a card.
	var w := span_w if span_w > 0.0 else size.x
	var x0 := w / 2.0 + 90.0 if fort_on == "right" else 0.0
	var x1 := w if fort_on == "right" else w / 2.0 - 90.0
	var top := horizon - 42.0
	var base := horizon + 10.0
	var col := Color(UiPalette.MAP_INK, 0.6)
	draw_rect(Rect2(x0, top, x1 - x0, base - top), col)
	var merlon := 12.0
	var x := x0
	while x < x1 - 1.0:
		draw_rect(Rect2(x, top - merlon, minf(merlon, x1 - x), merlon), col)
		x += merlon * 2.0
	var gx := (x0 + x1) / 2.0
	var gw := 70.0
	draw_rect(Rect2(gx - gw / 2.0, top - 26.0, gw, base - top + 26.0), Color(UiPalette.MAP_INK, 0.72))
	for k in 3:
		draw_rect(Rect2(gx - gw / 2.0 + k * 28.0, top - 38.0, 14.0, 12.0), Color(UiPalette.MAP_INK, 0.72))
	draw_rect(Rect2(gx - 14.0, base - 30.0, 28.0, 30.0), Color(UiPalette.KEYLINE_INK, 0.85))
