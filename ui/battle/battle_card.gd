class_name BattleCard
extends Control
## One fighter's card in the Simple view (M3-3, #58; design/M3_BATTLES.md §4.2). It draws itself in one
## node: the unit's portrait (Art), or a placeholder with its initial when the art isn't there; a 3 px
## frame in its seat's colour with ink keylines and the seat's emblem (so colour is never the only channel);
## its status glyphs; its hp bar with the round's pending damage hatched; a ground ellipse; and, for a
## ruler, the gilt ring and its name plate. Hovering shows BattleExplain.explain_fighter for the moment on
## screen (the view sets `explain_source`); right-click or F1 opens its codex entry.
##
## The view owns the card: it sets the live numbers from the BattlePlayer's state (sync()), starts the
## motions (lunge, hit, die, rout, fade, deploy) and calls animate(dt) with playback seconds while one runs.
## With reduced_motion the card never moves: no lunge, no shake, no tip, no slide (§7.4).
## A left click emits `clicked` (M3-4: the view selects the fighter and pins it in the why panel); a
## selected card keeps the white outline.
##
## Its pieces are drawn by static functions (draw_frame, draw_ground, draw_hp_bar, draw_standard,
## draw_plate, draw_glyph, hatch) so the legend (BattleLegend, M3-4) draws every row with the field's own
## code.

signal codex_requested(key: String)
signal clicked(fid: int)

const LUNGE_OUT := 0.12
const LUNGE_BACK := 0.18
const LUNGE_PX := 24.0
const HIT_TIME := 0.15
const HIT_SHAKE_PX := 3.0
const HIT_TINT := 0.4
const DEATH_TIME := 0.4
const DEATH_TIP := 0.21  # radians (12 degrees) toward its own back edge
const FALLEN_ALPHA := 0.4
const ROUT_TIME := 1.0
const FADE_TIME := 0.6
const DEPLOY_PX := 48.0
const GLYPHS := ["shield_wall", "berserk", "blood_frenzy", "pack_leader", "shielded", "exposed", "iron", "aura_up", "aura_down"]

static var _fallen_material: ShaderMaterial = null
static var _emblems := {}  # seat -> ImageTexture of its TOKEN emblem (EMBLEM_TEX px square)
## The baked emblem's size, and the shape's radius inside it (the keylines go 2.5 px further out).
const EMBLEM_TEX := 32
const EMBLEM_R := 12.0

var fid := -1
var fighter: Dictionary = {}
var seat := -1
var color := UiPalette.NEUTRAL
var texture: Texture2D = null
var use_face := false
## +1 faces right (the left side), -1 faces left. Portraits face left, so the left side's are flipped.
var dir := 1
var s := 1.0
var bar_on_top := false
var bar_h := 6.0
var initial := ""
var reduced_motion := false
## () -> String: the hover text for the moment on screen.
var explain_source: Callable
var codex_key := "units"

# The live numbers (from the player's state).
var hp := 0
var max_hp := 1
var pending := 0
var alive := true
var gone := false  # fled or lost: off the field
var glyphs: Array = []
var hovered := false
var selected := false

# Motion.
var home := Vector2.ZERO
var back_x := 0.0
var _lunge_t := -1.0
var _lunge_vec := Vector2.ZERO
var _hit_t := -1.0
var _death_t := -1.0
var _rout_t := -1.0
var _fade_t := -1.0
var _deploy_t := -1.0
var _deploy_len := 1.5
var _tint := 0.0
var _flipped_run := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	focus_mode = Control.FOCUS_NONE


## Sets the card up for fighter `f` of the log, standing at `rect` (field coordinates).
func setup(f: Dictionary, p_seat: int, rect: Rect2, p_dir: int, p_scale: float, p_bar_on_top: bool, p_bar_h: float, p_back_x: float) -> void:
	fighter = f
	fid = int(f.id)
	seat = p_seat
	color = UiPalette.seat_color(p_seat)
	dir = p_dir
	s = p_scale
	bar_on_top = p_bar_on_top
	bar_h = p_bar_h
	back_x = p_back_x
	home = rect.position
	position = home
	size = rect.size
	pivot_offset = Vector2(rect.size.x / 2.0, rect.size.y)
	name = "Card%d" % fid
	if f.role == "ruler":
		texture = Art.ruler_portrait(String(f.get("ruler", {}).get("id", f.type)))
	else:
		texture = Art.portrait(String(f.type), "")
	use_face = s < 0.75
	initial = Art._initials(String(f.name))
	max_hp = maxi(1, int(f.max_hp))
	hp = int(f.hp)
	codex_key = BattleExplain.fighter_codex(f)
	set_meta(CodexLink.META, codex_key)
	# A ruler's name plate may be wider than its card: draw the ruler above its neighbours.
	z_index = 1 if f.role == "ruler" else 0
	tooltip_text = String(f.name)
	mouse_entered.connect(func(): hovered = true; queue_redraw())
	mouse_exited.connect(func(): hovered = false; queue_redraw())


## Takes the numbers from fighter state `fs` (BattleTimeline's shape) and its glyphs. Redraws on a change.
func sync(fs: Dictionary, p_glyphs: Array) -> void:
	var now_gone: bool = (fs.fled or fs.lost) and fs.alive
	if int(fs.hp) != hp or int(fs.pending) != pending or bool(fs.alive) != alive or now_gone != gone or p_glyphs != glyphs:
		hp = int(fs.hp)
		pending = int(fs.pending)
		alive = bool(fs.alive)
		gone = now_gone
		glyphs = p_glyphs
		queue_redraw()


## Shows the card as it stands in `fs` with no motion running (after a seek).
func snap(fs: Dictionary, p_glyphs: Array) -> void:
	_lunge_t = -1.0
	_hit_t = -1.0
	_death_t = -1.0
	_rout_t = -1.0
	_fade_t = -1.0
	_deploy_t = -1.0
	_tint = 0.0
	_flipped_run = false
	sync(fs, p_glyphs)
	position = home
	rotation = 0.0
	if not fs.alive:
		_show_fallen(1.0)
	elif fs.fled or fs.lost:
		material = null
		modulate.a = 0.0
		visible = false
	else:
		material = null
		modulate.a = 1.0
		visible = true
	queue_redraw()


func is_animating() -> bool:
	return _lunge_t >= 0.0 or _hit_t >= 0.0 or _death_t >= 0.0 or _rout_t >= 0.0 or _fade_t >= 0.0 or _deploy_t >= 0.0


## The attack's lunge toward `target_center` (field coordinates). None with reduced motion.
func lunge(target_center: Vector2) -> void:
	if reduced_motion:
		return
	var v := target_center - (home + size / 2.0)
	_lunge_vec = v.normalized() * LUNGE_PX * s if v.length() > 0.5 else Vector2(dir * LUNGE_PX * s, 0)
	_lunge_t = 0.0


## Hit: the negative tint (and, without reduced motion, a 3 px shake).
func hit() -> void:
	_hit_t = 0.0


func die() -> void:
	_death_t = 0.0
	material = fallen_material()


## Routed: turns and runs to its back edge, fading (with reduced motion: fades where it stands).
func rout() -> void:
	_rout_t = 0.0
	_flipped_run = not reduced_motion
	queue_redraw()


## Lost with its army (the aftermath): fades out.
func fade_out() -> void:
	if visible and modulate.a > 0.0:
		_fade_t = 0.0


## The deploy step: from DEPLOY_PX behind its place to its place over `length` playback seconds.
func deploy(length: float) -> void:
	if reduced_motion:
		return
	_deploy_len = maxf(0.01, length)
	_deploy_t = 0.0
	position = home - Vector2(dir * DEPLOY_PX * s, 0)


## Advances the motions by `dt` playback seconds. Returns true while one is still running.
func animate(dt: float) -> bool:
	var off := Vector2.ZERO
	if _deploy_t >= 0.0:
		_deploy_t += dt
		var p := clampf(_deploy_t / _deploy_len, 0.0, 1.0)
		off.x -= dir * DEPLOY_PX * s * (1.0 - ease(p, 0.4))
		if p >= 1.0:
			_deploy_t = -1.0
	if _lunge_t >= 0.0:
		_lunge_t += dt
		var k := 0.0
		if _lunge_t < LUNGE_OUT:
			k = _lunge_t / LUNGE_OUT
		elif _lunge_t < LUNGE_OUT + LUNGE_BACK:
			k = 1.0 - (_lunge_t - LUNGE_OUT) / LUNGE_BACK
		else:
			_lunge_t = -1.0
		off += _lunge_vec * k
	if _hit_t >= 0.0:
		_hit_t += dt
		var q := 1.0 - _hit_t / HIT_TIME
		if q <= 0.0:
			_hit_t = -1.0
			_tint = 0.0
		else:
			_tint = HIT_TINT * q
			if not reduced_motion:
				off.x += sin(_hit_t * TAU * 20.0) * HIT_SHAKE_PX * q
		queue_redraw()
	if _death_t >= 0.0:
		_death_t += dt
		var p := clampf(_death_t / DEATH_TIME, 0.0, 1.0)
		_show_fallen(p)
		if p >= 1.0:
			_death_t = -1.0
	if _rout_t >= 0.0:
		_rout_t += dt
		var p := clampf(_rout_t / ROUT_TIME, 0.0, 1.0)
		if not reduced_motion:
			off.x += (back_x - home.x) * ease(p, 1.8)
		modulate.a = 1.0 - p
		if p >= 1.0:
			_rout_t = -1.0
			visible = false
	if _fade_t >= 0.0:
		_fade_t += dt
		var p := clampf(_fade_t / FADE_TIME, 0.0, 1.0)
		modulate.a = minf(modulate.a, 1.0 - p)
		if p >= 1.0:
			_fade_t = -1.0
			visible = false
	if _death_t < 0.0 and alive:
		position = home + off
	elif _death_t >= 0.0:
		position = home + off + Vector2(0, (0.0 if reduced_motion else 6.0 * s) * clampf(_death_t / DEATH_TIME, 0.0, 1.0))
	return is_animating()


func _show_fallen(p: float) -> void:
	material = fallen_material()
	modulate.a = lerpf(1.0, FALLEN_ALPHA, p)
	if not reduced_motion:
		rotation = -dir * DEATH_TIP * p
		position = home + Vector2(0, 6.0 * s * p)
	visible = true


## The shared desaturating material for fallen cards (one material, so fallen cards still batch).
static func fallen_material() -> ShaderMaterial:
	if _fallen_material == null:
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nvoid fragment() {\n\tfloat g = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));\n\tCOLOR.rgb = vec3(g) * 0.9;\n}\n"
		_fallen_material = ShaderMaterial.new()
		_fallen_material.shader = sh
	return _fallen_material


# --- hover and codex ------------------------------------------------------------------------------

func _get_tooltip(_at_position: Vector2) -> String:
	if explain_source.is_valid():
		return String(explain_source.call())
	return tooltip_text


func _gui_input(event: InputEvent) -> void:
	if CodexLink.is_open_click(event):
		if is_inside_tree():
			accept_event()
		codex_requested.emit(codex_key)
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if is_inside_tree():
			accept_event()
		clicked.emit(fid)


# --- drawing --------------------------------------------------------------------------------------

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var ruler: bool = fighter.get("role", "") == "ruler"
	var commander: bool = fighter.get("role", "") == "commander"
	# The ground ellipse at its feet (hidden in a crowd, where the next row stands on it).
	if not bar_on_top and alive:
		draw_ground(self, Vector2(r.size.x / 2.0, r.size.y), Vector2(r.size.x * 0.58, maxf(4.0, 7.0 * s)), color, ruler)
	# Drawn in an order that keeps a card to a few batches: the portrait, then every plain rect (tint, frame,
	# keylines, hp bar), then the baked emblem, then the few polygons (glyphs, a commander's standard).
	var inner := r.grow(-3.0)
	_draw_portrait(inner)
	if _tint > 0.0:
		draw_rect(inner, Color(UiPalette.NEGATIVE, _tint))
	draw_frame(self, r, color, ruler, commander, hovered or selected)
	if alive:
		draw_hp_bar(self, _hp_bar_rect(r), hp, max_hp, pending)
	var er := clampf(7.0 * s, 5.0, 8.0)
	var ec := Vector2(er + 4.0, er + 4.0 + (bar_h + 2.0 if bar_on_top else 0.0))
	var scale_px := er / EMBLEM_R
	draw_texture_rect(emblem_texture(seat), Rect2(ec - Vector2.ONE * EMBLEM_TEX * scale_px / 2.0, Vector2.ONE * EMBLEM_TEX * scale_px), false)
	var gs := clampf(12.0 * s, 9.0, 13.0)
	var gx := r.size.x - gs / 2.0 - 4.0
	var gy := gs / 2.0 + 4.0 + (bar_h + 2.0 if bar_on_top else 0.0)
	for g in glyphs:
		draw_glyph(self, String(g), Vector2(gx, gy), gs)
		gx -= gs + 2.0
		if gx < gs:
			break
	if commander:
		draw_standard(self, Vector2(5.0, r.size.y - 5.0), clampf(14.0 * s, 9.0, 14.0))
	if ruler:
		draw_plate(self, get_theme_default_font(), r, "%s · %d/%d" % [String(fighter.name), hp, max_hp], s, bar_on_top, bar_h)


## The card's frame: the seat-colour border with ink keylines (gilt inside for a commander), the ruler's
## outer gilt ring, and the white outline of a hovered or selected card.
static func draw_frame(ci: CanvasItem, r: Rect2, col: Color, ruler: bool, commander: bool, highlight: bool) -> void:
	if ruler:
		ci.draw_rect(r.grow(3.0), UiPalette.KEYLINE_INK, false, 1.0)
		ci.draw_rect(r.grow(1.5), UiPalette.GILT, false, 2.0)
	ci.draw_rect(r.grow(-1.5), col, false, 3.0)
	ci.draw_rect(r.grow(-0.5), UiPalette.KEYLINE_INK, false, 1.0)
	ci.draw_rect(r.grow(-3.5), UiPalette.GILT if commander else UiPalette.KEYLINE_INK, false, 1.0)
	if highlight:
		ci.draw_rect(r.grow(2.0), UiPalette.SELECTION, false, 2.0)


## The keylined ground ellipse in the seat's colour under a figure, with the second gilt ring for a ruler.
static func draw_ground(ci: CanvasItem, c: Vector2, rad: Vector2, col: Color, ruler: bool) -> void:
	_ellipse(ci, c, rad + Vector2(1.5, 1.5), UiPalette.KEYLINE_INK, 1.5)
	_ellipse(ci, c, rad, col, 2.0)
	if ruler:
		_ellipse(ci, c, rad + Vector2(4, 3), UiPalette.GILT, 1.5)


func _hp_bar_rect(r: Rect2) -> Rect2:
	if bar_on_top:
		return Rect2(4.0, 4.0, r.size.x - 8.0, bar_h)
	return Rect2(0.0, r.size.y + 3.0, r.size.x, bar_h)


## Seat `seat`'s emblem (SeatEmblem's TOKEN look: the seat colour, an ink keyline and a light halo) baked
## once into a small texture, so a card draws it as one batched quad instead of three polygons. The shape
## is SeatEmblem's own outline, sampled 4 times a pixel.
static func emblem_texture(seat_index: int) -> Texture2D:
	if _emblems.has(seat_index):
		return _emblems[seat_index]
	var img := Image.create(EMBLEM_TEX, EMBLEM_TEX, false, Image.FORMAT_RGBA8)
	var shape := SeatEmblem.shape_of(seat_index)
	var unit := SeatEmblem._outline(shape) if shape != "circle" else PackedVector2Array()
	var layers := [[EMBLEM_R, UiPalette.seat_color(seat_index)], [EMBLEM_R + 1.5, UiPalette.KEYLINE_INK], [EMBLEM_R + 2.5, UiPalette.KEYLINE_HALO]]
	var c := Vector2.ONE * EMBLEM_TEX / 2.0
	var offsets := [Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.25, 0.75), Vector2(0.75, 0.75)]
	for y in EMBLEM_TEX:
		for x in EMBLEM_TEX:
			var acc := Color(0, 0, 0, 0)
			for o in offsets:
				var p: Vector2 = Vector2(x, y) + o - c
				for layer in layers:
					var rad: float = layer[0]
					var inside := p.length() <= rad if unit.is_empty() else Geometry2D.is_point_in_polygon(p / rad, unit)
					if inside:
						var col: Color = layer[1]
						acc += Color(col.r * col.a, col.g * col.a, col.b * col.a, col.a)
						break
			acc /= 4.0
			if acc.a > 0.0:
				img.set_pixel(x, y, Color(acc.r / acc.a, acc.g / acc.a, acc.b / acc.a, acc.a))
	var tex := ImageTexture.create_from_image(img)
	_emblems[seat_index] = tex
	return tex


func _draw_portrait(r: Rect2) -> void:
	if texture == null:
		draw_rect(r, UiPalette.PANEL_RAISED)
		var font := get_theme_default_font()
		var fs := int(clampf(r.size.y * 0.4, 12.0, 40.0))
		var pos := Vector2(r.position.x, r.position.y + r.size.y * 0.5 + fs * 0.35)
		draw_string_outline(font, pos, initial, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, 4, UiPalette.KEYLINE_INK)
		draw_string(font, pos, initial, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, UiPalette.GILT)
		return
	var src := Rect2(Vector2.ZERO, texture.get_size())
	if use_face:
		src = Rect2(Art.FACE_REGION.position * src.size, Art.FACE_REGION.size * src.size)
	var want := r.size.x / maxf(r.size.y, 1.0)
	var have := src.size.x / maxf(src.size.y, 1.0)
	if have > want:
		var w := src.size.y * want
		src = Rect2(src.position.x + (src.size.x - w) / 2.0, src.position.y, w, src.size.y)
	elif have < want:
		src = Rect2(src.position.x, src.position.y, src.size.x, src.size.x / want)
	var face_right := dir > 0
	if _flipped_run:
		face_right = not face_right
	if face_right:
		# Portraits face left: mirror the art for a card facing right.
		draw_set_transform(Vector2(r.position.x * 2.0 + r.size.x, 0), 0.0, Vector2(-1, 1))
		draw_texture_rect_region(texture, r, src)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect_region(texture, r, src)


## An hp bar in `bar`: ink keyline, the hp left in green, and the damage still to land this round as a
## hatched red chunk at the fill's end (the pattern carries it as well as the colour, §7.4).
static func draw_hp_bar(ci: CanvasItem, bar: Rect2, p_hp: int, p_max_hp: int, p_pending: int) -> void:
	ci.draw_rect(bar.grow(1.0), UiPalette.KEYLINE_INK)
	ci.draw_rect(bar, UiPalette.PANEL_BG)
	var share := clampf(float(p_hp) / maxi(1, p_max_hp), 0.0, 1.0)
	var fill := Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y))
	ci.draw_rect(fill, UiPalette.POSITIVE)
	if p_pending > 0 and p_hp > 0:
		var p_share := clampf(float(mini(p_pending, p_hp)) / maxi(1, p_max_hp), 0.0, share)
		var chunk := Rect2(bar.position.x + bar.size.x * (share - p_share), bar.position.y, bar.size.x * p_share, bar.size.y)
		hatch(ci, chunk, UiPalette.NEGATIVE)


## A ruler's name plate ("King Corvane I · 18/18") centred near the bottom of card rect `r` (near the top
## in a crowd).
static func draw_plate(ci: CanvasItem, font: Font, r: Rect2, text: String, p_s: float, p_bar_on_top: bool, p_bar_h: float) -> void:
	var fs := int(clampf(13.0 * p_s, 12.0, 14.0))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0
	var h := fs + 4.0
	var y := r.position.y + (r.size.y - h - 4.0 if not p_bar_on_top else p_bar_h + 6.0)
	var box := Rect2(r.position.x + (r.size.x - w) / 2.0, y, w, h)
	ci.draw_rect(box, Color(UiPalette.KEYLINE_INK, 0.85))
	ci.draw_rect(box, UiPalette.GILT, false, 1.0)
	ci.draw_string(font, Vector2(box.position.x + 4.0, box.end.y - 4.0 - fs * 0.08), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiPalette.TEXT_PRIMARY)


## A commander's standard: a pole and a gilt pennant, standing on `foot`, `h` px tall.
static func draw_standard(ci: CanvasItem, foot: Vector2, h: float) -> void:
	ci.draw_line(foot, foot - Vector2(0, h), UiPalette.KEYLINE_INK, 2.0)
	var top := foot - Vector2(0, h)
	var flag := PackedVector2Array([top, top + Vector2(h * 0.7, h * 0.18), top + Vector2(0, h * 0.42)])
	ci.draw_colored_polygon(flag, UiPalette.GILT)
	ci.draw_polyline(PackedVector2Array([flag[0], flag[1], flag[2], flag[0]]), UiPalette.KEYLINE_INK, 1.0)


static func _ellipse(ci: CanvasItem, c: Vector2, rad: Vector2, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for k in 25:
		var a := TAU * k / 24.0
		pts.append(c + Vector2(cos(a) * rad.x, sin(a) * rad.y))
	ci.draw_polyline(pts, col, width, true)


## Diagonal hatching in `col` over `r` (pending damage: the pattern carries it as well as the colour).
static func hatch(ci: CanvasItem, r: Rect2, col: Color) -> void:
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	ci.draw_rect(r, Color(col, 0.45))
	var step := 4.0
	var x0 := r.position.x - r.size.y
	while x0 < r.end.x:
		# A 45-degree stroke from (x0, bottom) up to (x0 + height, top), clipped to the rect's sides.
		var p0 := Vector2(x0, r.end.y)
		var p1 := Vector2(x0 + r.size.y, r.position.y)
		if p0.x < r.position.x:
			p0 = Vector2(r.position.x, r.end.y - (r.position.x - x0))
		if p1.x > r.end.x:
			p1 = Vector2(r.end.x, r.position.y + (p1.x - r.end.x))
		if p1.x > p0.x:
			ci.draw_line(p0, p1, col, 1.5)
		x0 += step


## Draws status glyph `kind` (one of GLYPHS) centred on `c`, `size` px across, with an ink keyline. Shapes,
## not colours alone, carry each meaning (§7.4); the legend (M3-4) can draw them with this same function.
static func draw_glyph(ci: CanvasItem, kind: String, c: Vector2, size: float) -> void:
	var h := size / 2.0
	var ink := UiPalette.KEYLINE_INK
	match kind:
		"shield_wall":
			var pts := _shape(SeatEmblem._outline("shield"), c, h)
			ci.draw_colored_polygon(_shape(SeatEmblem._outline("shield"), c, h + 1.5), ink)
			ci.draw_colored_polygon(pts, UiPalette.TEXT_PRIMARY)
		"shielded":
			ci.draw_colored_polygon(_shape(SeatEmblem._outline("shield"), c, h + 1.5), ink)
			ci.draw_colored_polygon(_shape(SeatEmblem._outline("shield"), c, h), UiPalette.LINK)
		"berserk":
			var star := PackedVector2Array()
			for k in 8:
				var a := TAU * k / 8.0 - PI / 2.0
				star.append(c + Vector2(cos(a), sin(a)) * (h if k % 2 == 0 else h * 0.45))
			ci.draw_colored_polygon(_grow(star, c, 1.5), ink)
			ci.draw_colored_polygon(star, UiPalette.NEGATIVE)
		"blood_frenzy":
			var drop := PackedVector2Array([c + Vector2(0, -h), c + Vector2(h * 0.7, h * 0.2), c + Vector2(0, h), c + Vector2(-h * 0.7, h * 0.2)])
			ci.draw_colored_polygon(_grow(drop, c, 1.5), ink)
			ci.draw_colored_polygon(drop, Color("#B0201C"))
		"pack_leader":
			var chev := PackedVector2Array([c + Vector2(-h, h * 0.5), c + Vector2(0, -h * 0.6), c + Vector2(h, h * 0.5), c + Vector2(h * 0.55, h * 0.8),
				c + Vector2(0, h * 0.0), c + Vector2(-h * 0.55, h * 0.8)])
			ci.draw_colored_polygon(_grow(chev, c, 1.5), ink)
			ci.draw_colored_polygon(chev, UiPalette.GILT)
		"exposed":
			var tri := PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, h * 0.8), c + Vector2(-h, h * 0.8)])
			ci.draw_colored_polygon(_grow(tri, c, 1.5), ink)
			ci.draw_colored_polygon(tri, Color("#F0A23C"))
			ci.draw_line(c + Vector2(0, -h * 0.35), c + Vector2(0, h * 0.25), ink, maxf(1.5, size * 0.12))
			ci.draw_circle(c + Vector2(0, h * 0.55), maxf(1.0, size * 0.07), ink)
		"iron":
			ci.draw_circle(c + Vector2(-h * 0.4, 0), h * 0.55, ink, false, 3.0)
			ci.draw_circle(c + Vector2(h * 0.4, 0), h * 0.55, ink, false, 3.0)
			ci.draw_circle(c + Vector2(-h * 0.4, 0), h * 0.55, UiPalette.GILT, false, 1.5)
			ci.draw_circle(c + Vector2(h * 0.4, 0), h * 0.55, UiPalette.GILT, false, 1.5)
		"aura_up", "aura_down":
			var up := kind == "aura_up"
			var tri := PackedVector2Array([c + Vector2(0, -h if up else h), c + Vector2(h, h * 0.7 if up else -h * 0.7),
				c + Vector2(-h, h * 0.7 if up else -h * 0.7)])
			ci.draw_colored_polygon(_grow(tri, c, 1.5), ink)
			ci.draw_colored_polygon(tri, UiPalette.POSITIVE if up else UiPalette.NEGATIVE)


static func _shape(unit: PackedVector2Array, c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in unit:
		out.append(c + p * r)
	return out


static func _grow(pts: PackedVector2Array, c: Vector2, by: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		var v := p - c
		out.append(c + v + v.normalized() * by if v.length() > 0.01 else p)
	return out
