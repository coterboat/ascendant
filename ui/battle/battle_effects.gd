class_name BattleEffects
extends Control
## Every transient effect of the Simple view's field in one node (M3-3, #58; design/M3_BATTLES.md §4.1, §4.2,
## §4.4, §7.4): floating damage numbers and "miss", impact stars, projectiles with trails, dust puffs and,
## with reduced motion, static impact rings. One _draw() for all of them keeps them to a few draw calls.
## Pools are BattleFx's: an effect that finds its pool full is skipped, since the bars carry the facts.
## Ages are playback seconds (2x and 4x shorten them, pause freezes them); an impact's bright frames are
## counted in real frames (at most BattleFx.BRIGHT_FRAMES, and only when the flash limiter allows).

const NUMBER_LIFE := 0.6
const NUMBER_RISE := 24.0
const IMPACT_LIFE := 0.2
const RING_LIFE := 0.3
const DUST_LIFE := 0.4
const MISS_OVERSHOOT := 40.0

var numbers := BattleFx.Pool.new(BattleFx.MAX_NUMBERS)
var impacts := BattleFx.Pool.new(BattleFx.MAX_IMPACTS)
var projectiles := BattleFx.Pool.new(BattleFx.MAX_PROJECTILES)
var dust := BattleFx.Pool.new(BattleFx.MAX_IMPACTS)
## Counted for tests and the perf readout: bright impact frames drawn so far.
var bright_frames_drawn := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func add_number(pos: Vector2, text: String, col: Color, font_size: int) -> bool:
	return numbers.add({"pos": pos, "text": text, "color": col, "size": font_size, "age": 0.0, "life": NUMBER_LIFE})


## An impact star at `pos` (1.6x for a big hit). `bright`: it may show its bright frames (the flash limiter
## said yes). `ring`: reduced motion's static ring instead of a star.
func add_impact(pos: Vector2, s: float, big: bool, bright: bool, ring: bool) -> bool:
	return impacts.add({"pos": pos, "r": 18.0 * s * (1.6 if big else 1.0), "bright": bright and not ring, "ring": ring, "frames": 0, "age": 0.0,
		"life": RING_LIFE if ring else IMPACT_LIFE})


## A projectile from `from` to `to` taking `life` playback seconds, its apex `arc` x the distance above the
## straight line. A miss flies 40 px on past the target and fades, leaving a dust puff.
func add_projectile(from: Vector2, to: Vector2, life: float, arc: float, kind: String, hit: bool, s: float) -> bool:
	var end := to
	if not hit:
		end = to + (to - from).normalized() * MISS_OVERSHOOT
	return projectiles.add({"from": from, "to": end, "arc": arc, "kind": kind, "hit": hit, "s": s, "age": 0.0, "life": maxf(0.05, life)})


func add_dust(pos: Vector2, s: float) -> bool:
	return dust.add({"pos": pos, "s": s, "age": 0.0, "life": DUST_LIFE})


func active() -> int:
	return numbers.size() + impacts.size() + projectiles.size() + dust.size()


func clear() -> void:
	numbers.clear()
	impacts.clear()
	projectiles.clear()
	dust.clear()
	queue_redraw()


## Ages everything by `dt` playback seconds and counts a real frame for the impacts' bright frames.
func step(dt: float, new_frame: bool = true) -> void:
	var had := active() > 0
	if new_frame:
		for it in impacts.items:
			it.frames = int(it.frames) + 1
	for p in projectiles.items:
		if not p.hit and float(p.age) + dt >= float(p.life):
			add_dust(p.to, float(p.s))
	numbers.age(dt)
	impacts.age(dt)
	projectiles.age(dt)
	dust.age(dt)
	if had or active() > 0:
		queue_redraw()


func _draw() -> void:
	for p in projectiles.items:
		_draw_projectile(p)
	for it in impacts.items:
		_draw_impact(it)
	for d in dust.items:
		var k := float(d.age) / float(d.life)
		for j in 3:
			var off := Vector2((j - 1) * 9.0, -3.0 * j) * float(d.s)
			draw_circle(d.pos + off, (4.0 + 8.0 * k) * float(d.s), Color(0.55, 0.52, 0.48, 0.55 * (1.0 - k)))
	var font := get_theme_default_font()
	for n in numbers.items:
		var k := float(n.age) / float(n.life)
		var pos: Vector2 = n.pos - Vector2(0, NUMBER_RISE * k)
		var a := 1.0 if k < 0.5 else 1.0 - (k - 0.5) / 0.5
		var fs := int(n.size)
		var tw := font.get_string_size(String(n.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := pos - Vector2(tw / 2.0, 0)
		draw_string_outline(font, at, String(n.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(UiPalette.KEYLINE_INK, a))
		draw_string(font, at, String(n.text), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(n.color, a))


## The projectile's position at share `u` of its flight.
static func path_point(p: Dictionary, u: float) -> Vector2:
	var a: Vector2 = p.from
	var b: Vector2 = p.to
	var apex := float(p.arc) * a.distance_to(b)
	return a.lerp(b, u) - Vector2(0, 4.0 * apex * u * (1.0 - u))


func _draw_projectile(p: Dictionary) -> void:
	var u := clampf(float(p.age) / float(p.life), 0.0, 1.0)
	var head := path_point(p, u)
	var dist := maxf(1.0, (p.from as Vector2).distance_to(p.to))
	var tail_u := maxf(0.0, u - 24.0 / dist)
	var col := UiPalette.GILT if p.kind == "arcane" else UiPalette.TEXT_PRIMARY
	var a := 1.0
	if not p.hit:
		var over := MISS_OVERSHOOT / dist
		a = clampf((1.0 - u) / maxf(0.05, over), 0.0, 1.0) if u > 1.0 - over else 1.0
	var steps := 5
	for j in steps:
		var u0 := lerpf(tail_u, u, float(j) / steps)
		var u1 := lerpf(tail_u, u, float(j + 1) / steps)
		draw_line(path_point(p, u0), path_point(p, u1), Color(col, a * float(j + 1) / steps), 1.0 + 3.0 * float(j + 1) / steps)
	var r := 5.0 * float(p.s)
	draw_circle(head, r + 1.5, Color(UiPalette.KEYLINE_INK, a))
	draw_circle(head, r, Color(col, a))


func _draw_impact(it: Dictionary) -> void:
	var k := float(it.age) / float(it.life)
	var r := float(it.r)
	if it.ring:
		draw_arc(it.pos, r * 0.8, 0.0, TAU, 24, Color(UiPalette.TEXT_PRIMARY, 0.7), 2.0)
		return
	# Bright (above 80% opacity) for at most BRIGHT_FRAMES real frames, and only when the limiter allowed it.
	var a := 0.8 * (1.0 - k * k)
	if it.bright and int(it.frames) <= BattleFx.BRIGHT_FRAMES:
		a = 1.0
		bright_frames_drawn += 1
	var star := PackedVector2Array()
	var grow := 0.7 + 0.3 * k
	for j in 16:
		var ang := TAU * j / 16.0 - PI / 2.0
		star.append(it.pos + Vector2(cos(ang), sin(ang)) * r * grow * (1.0 if j % 2 == 0 else 0.42))
	var outline := PackedVector2Array()
	for p in star:
		outline.append(it.pos + (p - it.pos) * 1.12)
	draw_colored_polygon(outline, Color(UiPalette.KEYLINE_INK, minf(1.0, a + 0.2)))
	draw_colored_polygon(star, Color(1, 1, 1, a))
