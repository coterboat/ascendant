class_name PathPortrait
extends Control
## A transformed or new unit's portrait until the M4 portraits land (M4-4, #69; design/M4_ASCENSION.md §12.3).
## A changed unit: its base portrait (Art) inside a code-drawn frame in the fork's colour with the fork's
## glyph: a gilt sun ring (Celestial Host), riveted iron (Living Iron), a vine (Thorn Wild) or a blood edge
## (Blood Pact). A new unit: the placeholder card (a bust and the unit's initial) in the same frame. When a
## real portrait lands at assets/portraits/<faction>/<id>.webp, Art shows it inside the frame with no code
## change. The changed unit's own look (asc-3d-paths: Sunspears, Iron Knights, Thornthrowers, Bloodtuskers)
## replaces its base portrait once it lands at assets/portraits/<faction>/<id>__<transformation id>.webp
## (Art.variant_portrait; the transformation is the side of the fork of this faction in `colour`).
## Takes no mouse; the row around it carries the tooltip.
##
##   PathPortrait.make(unit_type_id, faction_id, colour, size)   colour: PathData.BRANCHES "colour"

var colour_key := ""
## True when the card shows the changed unit's own look (its variant portrait), not its base portrait.
var shows_variant := false
var card: Art.PortraitCard
var overlay: Control


static func make(unit_type_id: String, faction_id: String, colour: String, card_size: Vector2) -> PathPortrait:
	var p := PathPortrait.new()
	p.name = "PathPortrait_%s" % unit_type_id.validate_node_name()
	p.colour_key = colour
	p.custom_minimum_size = card_size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var initial := String(PathData.NEW_UNITS.get(unit_type_id, {}).get("name", ""))
	p.card = Art.portrait_card(unit_type_id, card_size, faction_id, Art.Crop.FULL, PathView.FORK_COLOURS.get(colour, UiPalette.GILT))
	var variant := Art.variant_portrait(unit_type_id, faction_id, transformation_of(faction_id, colour))
	if variant != null:
		p.card.texture = variant
		p.shows_variant = true
	if not initial.is_empty():
		p.card.initial = Art._initials(initial)
	p.card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.add_child(p.card)
	p.overlay = Frame.new()
	p.overlay.colour_key = colour
	p.overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.add_child(p.overlay)
	return p


## True when the real portrait is shown inside the frame (not the placeholder card).
func has_art() -> bool:
	return card != null and card.has_art()


## The transformation of `faction_id`'s side of the fork in `colour` (PathData.BRANCHES), or "".
static func transformation_of(faction_id: String, colour: String) -> String:
	for side in PathData.BRANCHES:
		var b: Dictionary = PathData.BRANCHES[side]
		if String(b.get("faction", "")) == faction_id and String(b.get("colour", "")) == colour:
			return String(b.get("transformation", ""))
	return ""


## The fork's frame and glyph, drawn over the card.
class Frame extends Control:
	var colour_key := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c: Color = PathView.FORK_COLOURS.get(colour_key, UiPalette.GILT)
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r.grow(-2.0), c, false, 4.0)
		var s := minf(size.x, size.y)
		match colour_key:
			"gilt":  # a sun ring at the top right
				var at := Vector2(size.x - s * 0.2, s * 0.2)
				draw_arc(at, s * 0.09, 0.0, TAU, 24, c, 2.5, true)
				for i in 8:
					var a := TAU * i / 8.0
					draw_line(at + Vector2.from_angle(a) * s * 0.12, at + Vector2.from_angle(a) * s * 0.17, c, 2.0, true)
			"iron":  # rivets around the frame, with a glowing seam
				for x in [0.08, 0.5, 0.92]:
					for y in [0.06, 0.94]:
						draw_circle(Vector2(size.x * x, size.y * y), maxf(2.5, s * 0.03), c.lightened(0.25))
				draw_line(Vector2(size.x * 0.12, size.y * 0.97), Vector2(size.x * 0.88, size.y * 0.97), Color("#F08A2A"), 2.0)
			"moss":  # a vine along the bottom with leaves
				var pts := PackedVector2Array()
				for i in 21:
					var x := size.x * (0.06 + 0.88 * i / 20.0)
					pts.append(Vector2(x, size.y - s * 0.07 + sin(i * 0.9) * s * 0.03))
				draw_polyline(pts, c, 2.5, true)
				for i in range(2, 20, 5):
					draw_circle(pts[i] + Vector2(0, -s * 0.03), maxf(2.5, s * 0.028), c.lightened(0.2))
			"crimson":  # drips from the top edge
				for x in [0.2, 0.42, 0.66, 0.85]:
					var len := s * (0.08 + 0.05 * fmod(x * 7.0, 1.0))
					draw_line(Vector2(size.x * x, 4.0), Vector2(size.x * x, 4.0 + len), c, 3.0, true)
					draw_circle(Vector2(size.x * x, 4.0 + len), 3.0, c)
