class_name Art
## The one place that knows where the game's art lives (design/ASSET_MANIFEST.md, STYLE_BIBLE.md §4),
## and the small widgets every screen uses to show it. UI only: the rules never see a texture.
##
## Lookups (lazy, cached, never an error): each returns the Texture2D, or null when the file is not
## there yet. A missing file is checked with ResourceLoader.exists() first, so nothing is printed.
##   portrait(unit_type_id, faction_id = "")   a unit's or commander's portrait (384x512, 3:4)
##                                              assets/portraits/<faction>/<unit type id>.webp (a transformation's
##                                              new unit, data/paths.gd NEW_UNITS, and M5's mages and summons,
##                                              data/magic.gd MAGES and SUMMONS, are found by their ids too)
##   variant_portrait(unit_type_id, faction_id, transformation_id)   a transformation's look of a unit it
##                                              changes (M4 §12.1: Sunspears for spearmen in the Celestial Host)
##                                              assets/portraits/<faction>/<unit type id>__<transformation id>.webp
##   unit_portrait(state, faction_id, unit_type_id)   the portrait a faction's unit wears in `state`: its
##                                              transformation's look once researched, else portrait()
##   ruler_portrait(ruler_id)                   assets/portraits/rulers/<ruler id>.webp (data/rulers.gd ids;
##                                              they land in their own PR, the placeholder card shows until then)
##   banner(faction_id)                         assets/banners/<faction>.webp (256x384, hang point top centre)
##   terrain(terrain_id)                        assets/terrain/<terrain>.webp (512x512, seamless)
##   title_backdrop()                           assets/ui/title_backdrop.webp (the title screen's job wires it)
##   spell_icon(key)                            assets/ui/spells/<key>.png (256x256): a spell's or ritual's icon by
##                                              its data/magic.gd SPELLS id, or Tithe of Blood's (ART-M5-2D, #224)
##   codex_plate(codex_key)                     assets/concept/codex/<codex key>.webp (768x768, a vignette on parchment):
##                                              the plate at the top of that codex page (#272), so a plate named after a
##                                              RulesCodex key shows on its page with no code change
## Audio will live under AUDIO_DIR with an audio.json map; the audio job wires it, not this file.
##
## Widgets (Controls that draw themselves, so they cost one node each and never lay out wrongly):
##   portrait_card(unit_type_id, size, faction_id = "", crop = Crop.FULL)   the portrait in a keylined
##        frame; without art, a styled placeholder card (a bust silhouette and the unit's initial)
##   ruler_card(ruler_id, ruler_name, size, faction_id = "")                 the same for a ruler
##   banner_card(faction_id, height)                                         the banner at its own aspect;
##        without art, a plain drawn pennant
##   face(texture)                                                           a square crop around the face
##        (eyes sit 35-41% from the top in every portrait), for icons smaller than 96x128
##   PlateCard                                                               a codex plate whole, at its own aspect and centred
##        on a band of its own parchment as wide as the card (the codex page's plate, #272)

enum Crop { FULL, FACE }

const PORTRAIT_PATH := "res://assets/portraits/%s/%s.webp"
const VARIANT_PORTRAIT_PATH := "res://assets/portraits/%s/%s__%s.webp"
const RULER_PORTRAIT_PATH := "res://assets/portraits/rulers/%s.webp"
const BANNER_PATH := "res://assets/banners/%s.webp"
const TERRAIN_PATH := "res://assets/terrain/%s.webp"
const TITLE_BACKDROP_PATH := "res://assets/ui/title_backdrop.webp"
const SPELL_ICON_PATH := "res://assets/ui/spells/%s.png"
const CODEX_PLATE_PATH := "res://assets/concept/codex/%s.webp"
const AUDIO_DIR := "res://assets/audio/"
## Portraits are 3:4 (384x512).
const PORTRAIT_ASPECT := 0.75
## Banners are 2:3 (256x384).
const BANNER_ASPECT := 2.0 / 3.0
## The face crop of a 384x512 portrait, as fractions of its size: a square from the top that keeps the
## head and the top of the shoulders.
const FACE_REGION := Rect2(0.06, 0.04, 0.88, 0.66)

static var _cache := {}  # path -> Texture2D, or null when the file is missing
static var _faces := {}  # texture -> AtlasTexture
static var _unit_factions := {}  # unit type id -> faction id, from FactionData


# --- lookups --------------------------------------------------------------------------------------

## The texture at `path`, loaded once; null (and quiet) when the file is not there.
static func texture(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_cache[path] = tex
	return tex


## The faction a unit type belongs to ("kingdom" for "spearmen"), from the faction data, or for a
## transformation's new unit ("seraphs") from the side of the fork that adds it, or for a mage or a summon
## ("adepts", "thornwolves") from the magic data; "" if none.
static func unit_faction(unit_type_id: String) -> String:
	if _unit_factions.is_empty():
		for f in FactionData.FACTIONS:
			for u in f.unit_types:
				_unit_factions[String(u.id)] = String(f.id)
			_unit_factions[String(f.commander.id)] = String(f.id)
		for ut in IndependentData.UNIT_TYPES:  # IND-2 (#161): the Free Holds' garrison units and their Hold Captain
			_unit_factions[String(ut.id)] = IndependentData.FACTION_ID
		_unit_factions[String(IndependentData.COMMANDER.id)] = IndependentData.FACTION_ID
		for side in PathData.BRANCHES:
			var b: Dictionary = PathData.BRANCHES[side]
			var new_unit := String(AscensionRules.node_effects(String(b.get("transformation", ""))).get("new_unit", ""))
			if not new_unit.is_empty():
				_unit_factions[new_unit] = String(b.get("faction", ""))
		for fid in MagicData.MAGES:  # M5: each faction's mage (ART-M5-2D, #224)
			_unit_factions[String(MagicData.MAGES[fid].id)] = String(fid)
		for sid in MagicData.SUMMONS:  # and the summoned creatures, by their own faction field
			_unit_factions[String(sid)] = String(MagicData.SUMMONS[sid].get("faction", ""))
	return String(_unit_factions.get(unit_type_id, ""))


## A unit's or commander's portrait, or null. `faction_id` is only needed for unit types outside the
## faction data.
static func portrait(unit_type_id: String, faction_id: String = "") -> Texture2D:
	var fid := faction_id if not faction_id.is_empty() else unit_faction(unit_type_id)
	if fid.is_empty() or unit_type_id.is_empty():
		return null
	return texture(PORTRAIT_PATH % [fid, unit_type_id])


## A transformation's look of a unit it changes ("spearmen" in "crown_celestial_host": the Sunspears), or
## null when that portrait isn't there (or the transformation doesn't change the unit, so there is none).
static func variant_portrait(unit_type_id: String, faction_id: String, transformation_id: String) -> Texture2D:
	var fid := faction_id if not faction_id.is_empty() else unit_faction(unit_type_id)
	if fid.is_empty() or unit_type_id.is_empty() or transformation_id.is_empty():
		return null
	return texture(VARIANT_PORTRAIT_PATH % [fid, unit_type_id, transformation_id])


## The portrait `faction_id`'s unit wears in `state`: once the faction has researched a transformation that
## changes the unit (the Celestial Host makes its Spearmen Sunspears), that look; else its own portrait.
static func unit_portrait(state: GameState, faction_id: String, unit_type_id: String) -> Texture2D:
	var fid := faction_id if not faction_id.is_empty() else unit_faction(unit_type_id)
	for side in PathData.BRANCHES:
		var trans := String(PathData.BRANCHES[side].get("transformation", ""))
		if (AscensionRules.node_effects(trans).get("rename", {}) as Dictionary).has(unit_type_id) \
				and AscensionRules.has_node(state, fid, trans):
			var look := variant_portrait(unit_type_id, fid, trans)
			if look != null:
				return look
	return portrait(unit_type_id, fid)


static func ruler_portrait(ruler_id: String) -> Texture2D:
	return null if ruler_id.is_empty() else texture(RULER_PORTRAIT_PATH % ruler_id)


static func banner(faction_id: String) -> Texture2D:
	return null if faction_id.is_empty() else texture(BANNER_PATH % faction_id)


static func terrain(terrain_id: String) -> Texture2D:
	return null if terrain_id.is_empty() else texture(TERRAIN_PATH % terrain_id)


static func title_backdrop() -> Texture2D:
	return texture(TITLE_BACKDROP_PATH)


## A spell's, ritual's or blood mandate's icon (a data/magic.gd SPELLS id, or "tithe_of_blood"), or null when it
## has not landed yet; the screens keep their own drawing until it does.
static func spell_icon(key: String) -> Texture2D:
	if key.is_empty():
		return null
	return texture(SPELL_ICON_PATH % key)


## The plate of the codex page `codex_key` (a RulesCodex.ENTRIES key: "terrain_forest"), or null when that page has none.
static func codex_plate(codex_key: String) -> Texture2D:
	if codex_key.is_empty():
		return null
	return texture(CODEX_PLATE_PATH % codex_key)


## A square crop of a portrait around the face (FACE_REGION), for small icons. Cached per texture.
static func face(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	if _faces.has(tex):
		return _faces[tex]
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	var s := tex.get_size()
	atlas.region = Rect2(FACE_REGION.position * s, FACE_REGION.size * s)
	_faces[tex] = atlas
	return atlas


# --- widgets ----------------------------------------------------------------------------------------

## A unit's portrait card. `size` is the card's minimum size; FULL keeps the 3:4 portrait, FACE crops
## the head for small square icons. `frame` is the border colour (gilt for commanders by default).
static func portrait_card(unit_type_id: String, card_size: Vector2, faction_id: String = "", crop: Crop = Crop.FULL,
		frame: Color = Color(0, 0, 0, 0)) -> PortraitCard:
	var card := PortraitCard.new()
	card.name = "Portrait_%s" % unit_type_id.validate_node_name()
	card.texture = portrait(unit_type_id, faction_id)
	card.crop = crop
	card.custom_minimum_size = card_size
	card.initial = _initials(_unit_name(unit_type_id))
	card.frame = frame if frame.a > 0.0 else (UiPalette.GILT if _is_commander(unit_type_id) else UiPalette.PANEL_BORDER.lightened(0.15))
	return card


## A ruler's portrait card: the art when it has landed, otherwise the placeholder with the ruler's
## initial. Rulers are framed in gilt.
static func ruler_card(ruler_id: String, ruler_name: String, card_size: Vector2, crop: Crop = Crop.FULL) -> PortraitCard:
	var card := PortraitCard.new()
	card.name = "RulerPortrait"
	card.texture = ruler_portrait(ruler_id)
	card.crop = crop
	card.custom_minimum_size = card_size
	card.initial = _initials(ruler_name)
	card.frame = UiPalette.GILT
	card.ruler = true
	return card


## A faction's banner at `height`, 2:3 wide; without art a plain drawn pennant.
static func banner_card(faction_id: String, height: float) -> BannerCard:
	var card := BannerCard.new()
	card.name = "Banner"
	card.texture = banner(faction_id)
	card.custom_minimum_size = Vector2(roundf(height * BANNER_ASPECT), height)
	return card


static func _unit_name(unit_type_id: String) -> String:
	for f in FactionData.FACTIONS:
		for u in f.unit_types:
			if u.id == unit_type_id:
				return String(u.name)
		if f.commander.id == unit_type_id:
			return String(f.commander.name)
	return unit_type_id.capitalize()


static func _is_commander(unit_type_id: String) -> bool:
	for f in FactionData.FACTIONS:
		if f.commander.id == unit_type_id:
			return true
	return false


## "K" for "King Corvane I", "E" for "the Ever-Regent", "W" for "War Bear": the first capitalised word.
static func _initials(text: String) -> String:
	for w in text.replace("-", " ").split(" ", false):
		if w.length() > 0 and w[0] == w[0].to_upper() and w[0] != w[0].to_lower():
			return w[0]
	return text.substr(0, 1).to_upper()


## A portrait in a keylined frame. Draws the art scaled to cover its rect (centred, cropped, never
## stretched), or a placeholder card when the art is missing: the portraits' own deep indigo, a bust
## silhouette and the initial in gilt. Takes no mouse; put the tooltip on the row around it.
class PortraitCard extends Control:
	var texture: Texture2D = null:
		set(value):
			texture = value
			queue_redraw()
	var crop: Art.Crop = Art.Crop.FULL:
		set(value):
			crop = value
			queue_redraw()
	var frame := UiPalette.PANEL_BORDER:
		set(value):
			frame = value
			queue_redraw()
	var initial := ""
	var ruler := false  # a ruler's card: the placeholder shows a crown over the bust
	## A count drawn in a badge at the bottom right ("2" for two of this unit), or 0 for none.
	var count := 0:
		set(value):
			count = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	## True when the art itself is shown (not the placeholder).
	func has_art() -> bool:
		return texture != null

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var inner := r.grow(-2.0)
		draw_rect(r, UiPalette.KEYLINE_INK)
		if texture != null:
			var src := Rect2(Vector2.ZERO, texture.get_size())
			if crop == Art.Crop.FACE:
				src = Rect2(Art.FACE_REGION.position * src.size, Art.FACE_REGION.size * src.size)
			# Cover the rect: crop the source to the rect's aspect, keeping the top (where the face is).
			var want := inner.size.x / maxf(inner.size.y, 1.0)
			var have := src.size.x / maxf(src.size.y, 1.0)
			if have > want:
				var w := src.size.y * want
				src = Rect2(src.position.x + (src.size.x - w) / 2.0, src.position.y, w, src.size.y)
			elif have < want:
				var h := src.size.x / want
				src = Rect2(src.position.x, src.position.y, src.size.x, h)
			draw_texture_rect_region(texture, inner, src)
		else:
			_draw_placeholder(inner)
		draw_rect(r.grow(-1.0), frame, false, 2.0)
		if count > 1:
			_draw_count()

	func _draw_placeholder(r: Rect2) -> void:
		# The portraits' plain softly graded deep indigo background (STYLE_BIBLE.md §6.1 C-portrait).
		draw_rect(r, UiPalette.PANEL_BG.lightened(0.04))
		var band := r
		band.size.y = r.size.y * 0.55
		draw_rect(band, UiPalette.PANEL_RAISED.lightened(0.05))
		var c := r.position + Vector2(r.size.x * 0.5, r.size.y * 0.42)
		var unit := minf(r.size.x, r.size.y / 1.33)
		var shade := UiPalette.PANEL_BORDER.darkened(0.1)
		# Bust: shoulders, then the head.
		var sw := unit * 0.40
		var top := c.y + unit * 0.22
		var bust := PackedVector2Array([
			Vector2(c.x - sw, r.end.y), Vector2(c.x - sw, top + unit * 0.16), Vector2(c.x - sw * 0.7, top + unit * 0.03),
			Vector2(c.x - sw * 0.3, top), Vector2(c.x + sw * 0.3, top), Vector2(c.x + sw * 0.7, top + unit * 0.03),
			Vector2(c.x + sw, top + unit * 0.16), Vector2(c.x + sw, r.end.y)])
		draw_colored_polygon(bust, shade)
		draw_circle(c, unit * 0.2, shade, true, -1.0, true)
		if ruler:
			var w := unit * 0.16
			var y := c.y - unit * 0.25
			var crown := PackedVector2Array([Vector2(c.x - w, y + w * 0.5), Vector2(c.x - w, y - w * 0.4), Vector2(c.x - w * 0.5, y),
				Vector2(c.x, y - w * 0.7), Vector2(c.x + w * 0.5, y), Vector2(c.x + w, y - w * 0.4), Vector2(c.x + w, y + w * 0.5)])
			draw_colored_polygon(crown, UiPalette.GILT.darkened(0.25))
		if not initial.is_empty() and r.size.y >= 40.0:
			# The initial sits on the chest like a monogram, under the head.
			var font := get_theme_default_font()
			var fs := int(clampf(unit * 0.3, 12.0, 40.0))
			var pos := Vector2(r.position.x, minf(top + unit * 0.2 + fs * 0.75, r.end.y - 4.0))
			draw_string_outline(font, pos, initial, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, 4, UiPalette.KEYLINE_INK)
			draw_string(font, pos, initial, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, UiPalette.GILT)

	func _draw_count() -> void:
		var font := get_theme_default_font()
		var fs := int(clampf(size.y * 0.22, 12.0, 18.0))
		var text := "×%d" % count
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0
		var h := fs + 4.0
		var box := Rect2(size.x - w - 2.0, size.y - h - 2.0, w, h)
		draw_rect(box, Color(UiPalette.KEYLINE_INK, 0.88))
		draw_rect(box, UiPalette.GILT, false, 1.0)
		draw_string(font, Vector2(box.position.x + 4.0, box.end.y - 4.0 - fs * 0.08), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiPalette.TEXT_PRIMARY)


## A faction banner drawn at its own 2:3 aspect, centred in its rect, hanging from the top. Without
## art, a plain pennant in the panel colours. Takes no mouse.
class BannerCard extends Control:
	var texture: Texture2D = null:
		set(value):
			texture = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func has_art() -> bool:
		return texture != null

	func _draw() -> void:
		var h := minf(size.y, size.x / Art.BANNER_ASPECT)
		var w := h * Art.BANNER_ASPECT
		var r := Rect2((size.x - w) / 2.0, 0.0, w, h)
		if texture != null:
			draw_texture_rect(texture, r, false)
			return
		# Placeholder pennant: a crossbar and a cloth with a swallowtail.
		var cloth := PackedVector2Array([r.position + Vector2(w * 0.18, h * 0.08), r.position + Vector2(w * 0.82, h * 0.08),
			r.position + Vector2(w * 0.82, h * 0.92), r.position + Vector2(w * 0.5, h * 0.76), r.position + Vector2(w * 0.18, h * 0.92)])
		draw_colored_polygon(cloth, UiPalette.PANEL_RAISED.lightened(0.1))
		var closed := cloth.duplicate()
		closed.append(cloth[0])
		draw_polyline(closed, UiPalette.KEYLINE_INK, 2.0, true)
		draw_line(r.position + Vector2(w * 0.08, h * 0.08), r.position + Vector2(w * 0.92, h * 0.08), UiPalette.GILT, maxf(2.0, h * 0.04), true)


## A codex plate (#272) on the page it illustrates: the plate whole, at its own aspect, as large as the card allows and centred, on
## a band of the plate's own parchment as wide as the card (its edge drawn on outwards), so the vignette spreads across the page as
## one picture, in a keyline. Nothing is cropped or stretched; without a texture it draws nothing. Takes no mouse.
class PlateCard extends Control:
	## The column, as a share of the plate's width in from each side, whose colour is the parchment's on that row.
	const EDGE := 1.0 / 128.0
	## A plate's parchment lightens towards its middle, so on a band of its edge colour its square would show. Within FEATHER of the
	## plate's width from each side, a pixel close to its row's edge colour is drawn as that colour, easing out inwards; a painted
	## pixel (far from the parchment's colour) is left as it is. The band's own draws sample the edge, so they are unchanged.
	const FEATHER := 0.3
	const SHADER := """shader_type canvas_item;
uniform float edge = 0.0078125;
uniform float feather = 0.3;
void fragment() {
	vec4 rim = textureLod(TEXTURE, vec2(UV.x < 0.5 ? edge : 1.0 - edge, UV.y), 0.0);
	float near_side = 1.0 - smoothstep(0.0, feather, min(UV.x, 1.0 - UV.x));
	float paper = 1.0 - smoothstep(0.02, 0.12, distance(COLOR.rgb, rim.rgb));
	COLOR.rgb = mix(COLOR.rgb, rim.rgb, near_side * paper);
}
"""
	static var _blend: ShaderMaterial = null
	var texture: Texture2D = null:
		set(value):
			texture = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if _blend == null:
			var shader := Shader.new()
			shader.code = SHADER
			_blend = ShaderMaterial.new()
			_blend.shader = shader
			_blend.set_shader_parameter("edge", EDGE)
			_blend.set_shader_parameter("feather", FEATHER)
		material = _blend

	func has_art() -> bool:
		return texture != null

	## Where the plate itself is drawn: inside the keyline, as large as fits with its aspect kept, centred.
	func plate_rect() -> Rect2:
		if texture == null:
			return Rect2()
		var inner := Rect2(Vector2.ZERO, size).grow(-2.0)
		var tex_size := texture.get_size()
		var s := minf(inner.size.x / maxf(tex_size.x, 1.0), inner.size.y / maxf(tex_size.y, 1.0))
		var drawn := tex_size * maxf(s, 0.0)
		return Rect2(inner.position + (inner.size - drawn) / 2.0, drawn)

	func _draw() -> void:
		if texture == null:
			return
		var r := Rect2(Vector2.ZERO, size)
		var inner := r.grow(-2.0)
		var at := plate_rect()
		var tex_size := texture.get_size()
		# The band is the plate's own parchment: its corner under everything, then its side columns (EDGE in, clear of any filtering
		# seam) drawn on outwards, so the paper runs on unbroken whatever its shading; the shader eases the plate's sides into it.
		var edge := floorf(tex_size.x * EDGE)
		draw_texture_rect_region(texture, r, Rect2(edge, edge, 1.0, 1.0))
		if at.position.x > inner.position.x + 0.5:
			draw_texture_rect_region(texture, Rect2(inner.position.x, at.position.y, at.position.x - inner.position.x, at.size.y),
				Rect2(edge, 0.0, 1.0, tex_size.y))
			draw_texture_rect_region(texture, Rect2(at.end.x, at.position.y, inner.end.x - at.end.x, at.size.y),
				Rect2(tex_size.x - edge - 1.0, 0.0, 1.0, tex_size.y))
		draw_texture_rect(texture, at, false)
		draw_rect(r.grow(-1.0), UiPalette.PANEL_BORDER.lightened(0.15), false, 2.0)
