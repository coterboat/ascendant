class_name SeatEmblem
extends Control
## A player's slot emblem (design/STYLE_BIBLE.md 1.1): Player 1 circle, Player 2 square, then triangle,
## diamond, hexagon and Greek cross; nobody (neutral, the bible's independents) a heater shield.
## Colour is never the only channel: wherever a player's colour marks something on the map, on the
## new game screen or on the victory screen, this shape is drawn with it, so the game reads in greyscale.
## UI only. The seat (0-based, -1 for nobody) comes from UiPalette's seat order, like the colour.
##
## Two looks:
##   TOKEN  the seat colour with the bible's keylines (ink inside, light halo outside), for marks on
##          terrain or panels: province rings, the top bar, the new game and victory screens.
##   GLYPH  the bible's glyph colours (light fill, ink outline), for marks drawn on a surface that is
##          already the seat colour (army badges), where a seat-coloured shape would vanish.
##
## As a Control it draws itself centred in its rect; draw_emblem() draws onto any CanvasItem.

enum Look { TOKEN, GLYPH }

const SHAPES := ["circle", "square", "triangle", "diamond", "hexagon", "cross"]
const NOBODY_SHAPE := "shield"

var seat := -1:
	set(value):
		seat = value
		queue_redraw()
var look: Look = Look.TOKEN:
	set(value):
		look = value
		queue_redraw()


func _init(p_seat: int = -1, p_look: Look = Look.TOKEN, p_size: float = 24.0) -> void:
	name = "SeatEmblem"
	seat = p_seat
	look = p_look
	custom_minimum_size = Vector2(p_size, p_size)
	size = custom_minimum_size
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_emblem(self, size * 0.5, minf(size.x, size.y) * 0.5 - 2.0, seat, look)


## The emblem's shape name: "circle" for seat 0 (Player 1), "square" for seat 1, "shield" for nobody.
static func shape_of(seat_index: int) -> String:
	return NOBODY_SHAPE if seat_index < 0 else SHAPES[seat_index % SHAPES.size()]


## Player-facing name of a seat's mark: "Vermilion circle", "Cobalt square", "slate shield".
static func describe(seat_index: int) -> String:
	if seat_index < 0:
		return "slate shield"
	return "%s %s" % [UiPalette.seat_color_name(seat_index), shape_of(seat_index)]


## Draws the emblem of `seat_index` on `ci`, centred on `center`, `radius` from the centre to the
## shape's edge (keylines go outside it).
static func draw_emblem(ci: CanvasItem, center: Vector2, radius: float, seat_index: int, emblem_look: Look = Look.TOKEN) -> void:
	var shape := shape_of(seat_index)
	if emblem_look == Look.GLYPH:
		_fill(ci, shape, center, radius + 1.5, UiPalette.KEYLINE_INK)
		_fill(ci, shape, center, radius, UiPalette.TEXT_PRIMARY)
		return
	_fill(ci, shape, center, radius + 2.5, UiPalette.KEYLINE_HALO)
	_fill(ci, shape, center, radius + 1.5, UiPalette.KEYLINE_INK)
	_fill(ci, shape, center, radius, UiPalette.seat_color(seat_index))


static func _fill(ci: CanvasItem, shape: String, center: Vector2, r: float, color: Color) -> void:
	if shape == "circle":
		ci.draw_circle(center, r, color, true, -1.0, true)
		return
	var pts := PackedVector2Array()
	for p in _outline(shape):
		pts.append(center + p * r)
	ci.draw_colored_polygon(pts, color)


## Unit-radius outline of a shape (clockwise, y down).
static func _outline(shape: String) -> PackedVector2Array:
	match shape:
		"square":
			var s := 0.85
			return PackedVector2Array([Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)])
		"triangle":
			return PackedVector2Array([Vector2(0, -1), Vector2(1, 0.8), Vector2(-1, 0.8)])
		"diamond":
			return PackedVector2Array([Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)])
		"hexagon":
			var hex := PackedVector2Array()
			for i in 6:
				var a := deg_to_rad(-90.0 + 60.0 * i)
				hex.append(Vector2(cos(a), sin(a)))
			return hex
		"cross":
			var w := 0.36
			return PackedVector2Array([Vector2(-w, -1), Vector2(w, -1), Vector2(w, -w), Vector2(1, -w), Vector2(1, w),
				Vector2(w, w), Vector2(w, 1), Vector2(-w, 1), Vector2(-w, w), Vector2(-1, w), Vector2(-1, -w), Vector2(-w, -w)])
		_:  # heater shield: flat top, straight sides curving in to a point at the bottom
			return PackedVector2Array([Vector2(-0.82, -0.88), Vector2(0.82, -0.88), Vector2(0.82, -0.1), Vector2(0.66, 0.42),
				Vector2(0.36, 0.8), Vector2(0, 1), Vector2(-0.36, 0.8), Vector2(-0.66, 0.42), Vector2(-0.82, -0.1)])
