class_name UiIcons
## The War Table's icon set (design/UX_WAR_TABLE.md section 7, UX-0a): 25 hand-written stroke SVGs in
## assets/ui/icons/, one file per name in NAMES, drawn on a 24-unit grid with a 1.7 stroke, round caps
## and joins, and no fills except the dots of "orders" and "needs-you".
##
##   var tex := UiIcons.icon("gold")        # 24 px
##   var small := UiIcons.icon("gold", 16)  # 16 px, for plates
##
## TINTING. Every icon is drawn in ONE colour. The loader paints it white, so the texture is a white
## mask and the caller picks the colour with `modulate` (a TextureRect's `modulate` or `self_modulate`,
## or the colour argument of `draw_texture`): gilt for a heading, UiPalette.TEXT_PRIMARY for a row,
## UiPalette.NEGATIVE for a warning. Whatever stroke colour a file is saved with, the loader replaces it,
## so a file saved with a stray colour cannot break the tint.
##
## CRISPNESS. A texture import has one scale, and 16 is 2/3 of 24, so one import cannot be crisp at both
## sizes. The files are therefore not imported as textures: each carries `importer="keep"` (Godot ships
## the SVG untouched, in the editor and in an export) and this class rasterises it at exactly the size
## asked for, with Image.load_svg_from_string. Each size is its own pixel-exact texture, and the result is
## cached. Under 20 px the stroke is thickened (to 1.4 px on screen, which is 2.1 units at 16 px) so the
## lines stay solid; at 20 px and up it is the drawn 1.7 units. A caller whose window is scaled (the 125%
## setting) can ask for the physical size (30 for a 24 px icon) to stay crisp; the cache keeps each size.
##
## An unknown name, or a file that will not rasterise, gives a boxed cross (so the hole shows on screen)
## and ONE warning per name. It never crashes. Tests that mean to ask for an unknown name set `quiet`.

## The folder the icons live in, and the names in it: a test pins that the two lists match.
const DIR := "res://assets/ui/icons/"
const NAMES: Array[String] = [
	"gold", "income", "walls", "garrison", "sight", "strength", "battle", "research",
	"magic", "ruler", "codex", "turn", "orders", "recruit", "morale", "hp",
	"march", "fortify", "siege", "lens", "chronicle", "pin", "dismiss", "needs-you", "muster",
]

## The size the icons are drawn at, and the small size for plates.
const SIZE := 24
const SIZE_SMALL := 16
## Smallest and largest size icon() will rasterise; anything else is clamped into the range.
const SIZE_MIN := 8
const SIZE_MAX := 256
## Stroke width on the 24-unit grid, and the least it may be on screen: below 20 px the stroke is widened
## to keep STROKE_MIN_PX pixels.
const STROKE := 1.7
const STROKE_MIN_PX := 1.4
const STROKE_SOURCE := "stroke-width=\"1.7\""

## What an unknown name draws: a boxed cross.
const FALLBACK_SVG := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"#FFFFFF\" stroke-width=\"1.7\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><rect x=\"3.5\" y=\"3.5\" width=\"17\" height=\"17\" rx=\"2.5\"/><path d=\"M8 8 L16 16 M16 8 L8 16\"/></svg>"

## True keeps warnings out of the log and only in `warnings` (tests that ask for an unknown name on purpose).
static var quiet := false
## Every warning raised so far, once per name.
static var warnings := PackedStringArray()

static var _cache := {}  # "name@size" -> Texture2D
static var _sources := {}  # name -> the SVG text
static var _warned := {}  # names already warned about


## The icon `name` as a white-stroke texture `size` pixels square, cached. See the header for tinting.
## An unknown name gives the boxed cross and a warning.
##
## Named icon(), not get(): GDScript has no static method called get, because Object.get(property) is
## already an instance method on every class and a static one cannot override it.
static func icon(name: String, size: int = SIZE) -> Texture2D:
	var px := clampi(size, SIZE_MIN, SIZE_MAX)
	var key := "%s@%d" % [name, px]
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	if NAMES.has(name):
		tex = _make(_source(name), px)
		if tex == null:
			_warn(name, "UiIcons: the icon file %s%s.svg would not rasterise; showing the fallback." % [DIR, name])
	else:
		_warn(name, "UiIcons: there is no icon called \"%s\"; showing the fallback. The names are in UiIcons.NAMES." % name)
	if tex == null:
		tex = _make(FALLBACK_SVG, px)
	_cache[key] = tex
	return tex


## The stroke width, in 24-unit grid units, that an icon of `size` pixels is drawn with.
static func stroke_for(size: int) -> float:
	return maxf(STROKE, STROKE_MIN_PX * SIZE / float(clampi(size, SIZE_MIN, SIZE_MAX)))


static func _source(name: String) -> String:
	if not _sources.has(name):
		_sources[name] = FileAccess.get_file_as_string(DIR + name + ".svg")
	return _sources[name]


## The SVG text rasterised at `px` pixels and painted white, or null when it will not rasterise.
static func _make(svg: String, px: int) -> Texture2D:
	if svg.is_empty():
		return null
	var text := svg.replace(STROKE_SOURCE, "stroke-width=\"%s\"" % String.num(stroke_for(px), 2))
	var image := Image.new()
	if image.load_svg_from_string(text, float(px) / SIZE) != OK or image.is_empty():
		return null
	image.convert(Image.FORMAT_RGBA8)
	if image.get_width() != px or image.get_height() != px:
		image.resize(px, px, Image.INTERPOLATE_LANCZOS)
	# White under every pixel: a transparent pixel with dark RGB would fringe the edges once the
	# texture is filtered and tinted.
	var data := image.get_data()
	for i in range(0, data.size(), 4):
		data[i] = 255
		data[i + 1] = 255
		data[i + 2] = 255
	return ImageTexture.create_from_image(Image.create_from_data(px, px, false, Image.FORMAT_RGBA8, data))


static func _warn(name: String, text: String) -> void:
	if _warned.has(name):
		return
	_warned[name] = true
	warnings.append(text)
	if not quiet:
		push_warning(text)
