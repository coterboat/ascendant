class_name NoticeArt
extends RefCounted
## UX-6 (design/UX_WAR_TABLE.md §5.2): the image of a notice. Every announcement type (ChronicleModel.IMAGES) has its own round medallion.
## UX-ART paints them and drops the files in assets/ui/notices/<image>.png (one per image key; a file named after a kind, like
## battles.png, stands in for every image of that kind that has none of its own). Until a file is there the medallion is the kind's icon
## on a coloured disc, drawn by NoticeMedallion from the colours here, so UX-ART can land with no code change.
##
##   NoticeArt.path_for(image, kind) -> String          the art file for it ("" when there is none)
##   NoticeArt.texture(image, kind, px) -> Texture2D    the painted art as a px-square disc (round, cached), or null
##   NoticeArt.disc(kind) / NoticeArt.ring(tone)        the placeholder's colours

## Where UX-ART's files go (a var so a test can point it at a scratch folder).
static var dir := "res://assets/ui/notices/"
## The disc behind each kind's icon: dark enough for a cream icon to read, and never the only difference between kinds (the icons differ).
const DISC := {
	"needs_you": Color("#6B4F12"), "battles": Color("#6E2B27"), "land": Color("#3C5A2E"), "rulers": Color("#58407A"),
	"magic": Color("#2D4F7A"), "realm": Color("#6A5A3A"), "abroad": Color("#464158"),
}
const RING_GOOD := Color("#72C47A")
const RING_BAD := Color("#F06A64")

## The one icon the set lacks: a flag, for Land (a province taken or lost). Drawn in the same style as UiIcons' files (24-unit grid, 1.7 stroke).
const FLAG_SVG := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"#FFFFFF\" stroke-width=\"1.7\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"M6 21.5 V2.8\"/><path d=\"M6 4 H19.5 L16 8.8 L19.5 13.6 H6\"/></svg>"

static var _cache := {}  # "<path>@<px>" -> Texture2D (or null)
static var _flags := {}  # px -> the flag icon


## A white-stroke icon `px` square, to tint with a modulate colour: UiIcons' icon, or the flag.
static func icon(icon_name: String, px: int) -> Texture2D:
	if icon_name != "flag":
		return UiIcons.icon(icon_name, px)
	if not _flags.has(px):
		var image := Image.new()
		var tex: Texture2D = null
		if image.load_svg_from_string(FLAG_SVG, float(px) / 24.0) == OK and not image.is_empty():
			image.convert(Image.FORMAT_RGBA8)
			var data := image.get_data()
			for i in range(0, data.size(), 4):
				data[i] = 255
				data[i + 1] = 255
				data[i + 2] = 255
			tex = ImageTexture.create_from_image(Image.create_from_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data))
		_flags[px] = tex if tex != null else UiIcons.icon("fortify", px)
	return _flags[px]


static func disc(kind: String) -> Color:
	return DISC.get(kind, UiPalette.NEUTRAL)


## The outcome ring: green for good news, red for bad, "" for none. Colour is never alone: the medallion adds a + or a -.
static func ring(tone: String) -> Color:
	match tone:
		"good":
			return RING_GOOD
		"bad":
			return RING_BAD
	return Color(0, 0, 0, 0)


## The art file for an image key, falling back to its kind's file; "" when neither exists.
static func path_for(image: String, kind: String) -> String:
	for stem in [image, kind]:
		if String(stem).is_empty():
			continue
		var p := "%s%s.png" % [dir, stem]
		if ResourceLoader.exists(p) or FileAccess.file_exists(p):
			return p
	return ""


## The painted art for the medallion as a round `px`-square texture, or null when UX-ART has not painted it yet.
static func texture(image: String, kind: String, px: int) -> Texture2D:
	var p := path_for(image, kind)
	if p.is_empty():
		return null
	var key := "%s@%d" % [p, px]
	if _cache.has(key):
		return _cache[key]
	var img := _load(p)
	var tex: Texture2D = null
	if img != null and not img.is_empty():
		tex = _round(img, px)
	_cache[key] = tex
	return tex


static func _load(p: String) -> Image:
	if ResourceLoader.exists(p):
		var res = load(p)
		if res is Texture2D:
			return (res as Texture2D).get_image()
	if FileAccess.file_exists(p):
		return Image.load_from_file(p)
	return null


## `img` scaled to a px square and cut to a disc with a one-pixel soft edge.
static func _round(img: Image, px: int) -> Texture2D:
	var copy := img.duplicate() as Image
	if copy.is_compressed():
		copy.decompress()
	copy.convert(Image.FORMAT_RGBA8)
	copy.resize(px, px, Image.INTERPOLATE_LANCZOS)
	var r := px * 0.5
	var c := Vector2(r, r)
	for y in px:
		for x in px:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d > r:
				copy.set_pixel(x, y, Color(0, 0, 0, 0))
			elif d > r - 1.0:
				var px_color := copy.get_pixel(x, y)
				px_color.a *= clampf(r - d, 0.0, 1.0)
				copy.set_pixel(x, y, px_color)
	return ImageTexture.create_from_image(copy)


## Forgets what was loaded (tests that drop a file in and out).
static func clear_cache() -> void:
	_cache.clear()
