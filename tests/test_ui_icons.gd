extends "res://tests/test_case.gd"
## UX-0a (#193): the War Table's icon set (UiIcons, assets/ui/icons/*.svg) and type tokens (UiFonts, the
## type scale in UiPalette). Every icon loads at both sizes as a tintable white mask, the folder and
## UiIcons.NAMES list the same icons, an unknown name gives a visible fallback and a warning, and every
## font token resolves. Expected values come from UiIcons / UiPalette's own constants and the files.

## Pixels with at least this alpha count as drawn.
const INK_ALPHA := 0.5
## A drawn icon covers between these shares of its canvas: not blank, not a filled block.
const MIN_COVERAGE := 0.04
const MAX_COVERAGE := 0.65


## Share of the canvas that is drawn, and whether every pixel with any alpha is pure white.
func _ink(img: Image) -> Dictionary:
	var drawn := 0
	var white := true
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.a >= INK_ALPHA:
				drawn += 1
			if p.a > 0.0 and (p.r < 0.999 or p.g < 0.999 or p.b < 0.999):
				white = false
	return {"coverage": drawn / float(img.get_width() * img.get_height()), "white": white}


func test_every_name_loads_at_both_sizes() -> void:
	UiIcons.warnings = PackedStringArray()
	assert_eq(UiIcons.NAMES.size(), 24, "the set is 24 icons")
	for icon_name in UiIcons.NAMES:
		for px in [UiIcons.SIZE, UiIcons.SIZE_SMALL]:
			var tex := UiIcons.icon(icon_name, px)
			assert_true(tex != null, "%s at %d loads" % [icon_name, px])
			if tex == null:
				continue
			assert_eq(tex.get_size(), Vector2(px, px), "%s at %d is %d px square" % [icon_name, px, px])
			var ink := _ink(tex.get_image())
			assert_true(ink.coverage >= MIN_COVERAGE and ink.coverage <= MAX_COVERAGE,
				"%s at %d draws something sensible (covers %.0f%%)" % [icon_name, px, ink.coverage * 100.0])
			assert_true(ink.white, "%s at %d is a white mask, so modulate can tint it" % [icon_name, px])
	assert_eq(UiIcons.warnings.size(), 0, "no real icon fell back: %s" % str(UiIcons.warnings))
	assert_eq(UiIcons.icon("gold").get_size(), Vector2(UiIcons.SIZE, UiIcons.SIZE), "the default size is 24")


func test_icons_differ_from_each_other_and_from_the_fallback() -> void:
	UiIcons.quiet = true
	var fallback := UiIcons.icon("a-name-with-no-icon").get_image().get_data()
	UiIcons.quiet = false
	var seen := {}
	for icon_name in UiIcons.NAMES:
		var data := UiIcons.icon(icon_name).get_image().get_data()
		assert_ne(data, fallback, "%s is not the fallback" % icon_name)
		assert_false(seen.has(data), "%s does not repeat another icon (it matches %s)" % [icon_name, seen.get(data, "")])
		seen[data] = icon_name


func test_icons_are_cached_per_size() -> void:
	assert_true(UiIcons.icon("gold") == UiIcons.icon("gold"), "the same texture comes back")
	assert_true(UiIcons.icon("gold", 16) == UiIcons.icon("gold", 16), "and at the small size")
	assert_true(UiIcons.icon("gold", 16) != UiIcons.icon("gold", 24), "each size is its own texture")
	assert_eq(UiIcons.icon("gold", 30).get_size(), Vector2(30, 30), "a physical size for a scaled window is exact")


func test_files_and_names_match() -> void:
	var on_disk := PackedStringArray()
	for file in DirAccess.get_files_at(UiIcons.DIR):
		if file.ends_with(".svg"):
			on_disk.append(file.trim_suffix(".svg"))
	on_disk.sort()
	var listed := PackedStringArray(UiIcons.NAMES)
	listed.sort()
	for icon_name in on_disk:
		assert_true(listed.has(icon_name), "%s.svg is in UiIcons.NAMES" % icon_name)
	for icon_name in listed:
		assert_true(on_disk.has(icon_name), "%s is in NAMES and has a file" % icon_name)
	assert_eq(on_disk.size(), listed.size(), "the folder and NAMES list the same number of icons")
	var unique := {}
	for icon_name in UiIcons.NAMES:
		unique[icon_name] = true
		assert_true(icon_name == icon_name.to_lower() and not icon_name.contains(" "), "%s is a lowercase file name" % icon_name)
	assert_eq(unique.size(), UiIcons.NAMES.size(), "NAMES has no duplicates")


func test_files_follow_the_house_rules() -> void:
	for icon_name in UiIcons.NAMES:
		var path := "%s%s.svg" % [UiIcons.DIR, icon_name]
		var text := FileAccess.get_file_as_string(path)
		assert_true(text.contains("viewBox=\"0 0 24 24\""), "%s is drawn on the 24-unit grid" % icon_name)
		assert_true(text.contains(UiIcons.STROKE_SOURCE), "%s carries the stroke width the loader adjusts for small sizes" % icon_name)
		assert_true(text.contains("stroke-linecap=\"round\"") and text.contains("stroke-linejoin=\"round\""), "%s has round caps and joins" % icon_name)
		var import_text := FileAccess.get_file_as_string(path + ".import")
		assert_true(import_text.contains("importer=\"keep\""),
			"%s.svg is kept as the source file, not imported at one scale (UiIcons rasterises it per size)" % icon_name)


func test_stroke_stays_solid_at_small_sizes() -> void:
	assert_eq(UiIcons.stroke_for(UiIcons.SIZE), UiIcons.STROKE, "the drawn stroke at 24")
	assert_eq(UiIcons.stroke_for(48), UiIcons.STROKE, "and at larger sizes")
	var small := UiIcons.stroke_for(UiIcons.SIZE_SMALL)
	assert_true(small > UiIcons.STROKE, "wider on the grid at 16")
	assert_true(small * UiIcons.SIZE_SMALL / float(UiIcons.SIZE) >= UiIcons.STROKE_MIN_PX - 0.001,
		"but at least %s px on screen" % UiIcons.STROKE_MIN_PX)


func test_unknown_name_gives_a_visible_fallback_and_one_warning() -> void:
	UiIcons.quiet = true
	var before := UiIcons.warnings.size()
	var tex := UiIcons.icon("no-such-icon")
	assert_true(tex != null, "an unknown name still gives a texture")
	assert_eq(tex.get_size(), Vector2(UiIcons.SIZE, UiIcons.SIZE), "at the size asked for")
	var ink := _ink(tex.get_image())
	assert_true(ink.coverage >= MIN_COVERAGE, "the fallback is drawn, so the hole shows on screen")
	assert_true(ink.white, "and tints like an icon")
	assert_eq(UiIcons.warnings.size(), before + 1, "one warning")
	assert_true(UiIcons.warnings[UiIcons.warnings.size() - 1].contains("no-such-icon"), "that names the icon")
	assert_eq(UiIcons.icon("no-such-icon", 16).get_size(), Vector2(16, 16), "the fallback comes at the small size too")
	UiIcons.icon("no-such-icon")
	assert_eq(UiIcons.warnings.size(), before + 1, "asking again does not warn again")
	assert_eq(UiIcons.icon("").get_size(), Vector2(UiIcons.SIZE, UiIcons.SIZE), "an empty name is just another unknown name")
	assert_eq(UiIcons.icon("../../project", 16).get_size(), Vector2(16, 16), "and a path is never read as a file")
	UiIcons.quiet = false


func test_size_is_clamped_not_a_crash() -> void:
	assert_eq(UiIcons.icon("gold", 0).get_size(), Vector2(UiIcons.SIZE_MIN, UiIcons.SIZE_MIN), "zero is raised to the least size")
	assert_eq(UiIcons.icon("gold", -5).get_size(), Vector2(UiIcons.SIZE_MIN, UiIcons.SIZE_MIN), "so is a negative one")
	assert_eq(UiIcons.icon("gold", 100000).get_size(), Vector2(UiIcons.SIZE_MAX, UiIcons.SIZE_MAX), "a huge one is lowered to the most")


func test_modulate_tints_the_mask() -> void:
	# The tint is the caller's: a TextureRect's modulate multiplies the white pixels to the colour.
	var rect := TextureRect.new()
	rect.texture = UiIcons.icon("gold")
	rect.modulate = UiPalette.GILT
	assert_eq(rect.modulate, UiPalette.GILT, "modulate takes the gilt colour")
	var white := UiIcons.icon("gold").get_image()
	var inked := Vector2i(-1, -1)
	for y in white.get_height():
		for x in white.get_width():
			if inked.x < 0 and white.get_pixel(x, y).a >= 0.99:
				inked = Vector2i(x, y)
	assert_true(inked.x >= 0, "gold has a solid pixel")
	var tinted := white.get_pixelv(inked) * UiPalette.GILT
	assert_true(is_equal_approx(tinted.r, UiPalette.GILT.r) and is_equal_approx(tinted.g, UiPalette.GILT.g)
		and is_equal_approx(tinted.b, UiPalette.GILT.b), "white times gilt is gilt")
	rect.free()


# --- type tokens ----------------------------------------------------------------------------------------

func _tokens() -> Dictionary:
	return {"title": UiFonts.title(), "name": UiFonts.name(), "body": UiFonts.body(), "number": UiFonts.number()}


func test_font_tokens_resolve() -> void:
	var tokens := _tokens()
	for token in tokens:
		var font: Font = tokens[token]
		assert_true(font != null, "UiFonts.%s() is a Font" % token)
		if font == null:
			continue
		for size in [UiPalette.TYPE_TITLE, UiPalette.TYPE_NAME, UiPalette.TYPE_BODY, UiPalette.TYPE_SMALL, UiPalette.TYPE_NUMBER]:
			var measured := font.get_string_size("Aldermoor 1,240", HORIZONTAL_ALIGNMENT_LEFT, -1, size)
			assert_true(measured.x > 0.0 and measured.y > 0.0, "UiFonts.%s() measures text at %d (%s)" % [token, size, str(measured)])
	assert_true(UiFonts.number() == UiFonts.number(), "number() is built once")


func test_number_font_has_tabular_figures() -> void:
	var font := UiFonts.number()
	for size in [UiPalette.TYPE_NUMBER, UiPalette.TYPE_BODY, UiPalette.TYPE_SMALL]:
		var widths := {}
		for run in ["0000", "1111", "4444", "7777", "8888"]:
			widths[font.get_string_size(run, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x] = run
		assert_eq(widths.size(), 1, "every digit is the same width at %d, so counters do not shimmer (%s)" % [size, str(widths)])
	# The font itself must carry the feature, so UX-0b's fonts cannot lose tabular figures unnoticed.
	var server := TextServerManager.get_primary_interface()
	if server.get_name().contains("Dummy"):
		return
	var tag := server.name_to_tag("tnum")
	for rid in UiFonts.body().get_rids():
		assert_true(server.font_supported_feature_list(rid).has(tag), "the number font's base font supports OpenType \"tnum\"")


func test_type_scale() -> void:
	assert_true(UiPalette.TYPE_TITLE > UiPalette.TYPE_NAME, "title is above name")
	assert_true(UiPalette.TYPE_NAME > UiPalette.TYPE_BODY, "name is above body")
	assert_true(UiPalette.TYPE_BODY > UiPalette.TYPE_SMALL, "body is above small")
	assert_true(UiPalette.TYPE_NUMBER >= UiPalette.TYPE_BODY, "figures are at least body size")
	for size in [UiPalette.TYPE_TITLE, UiPalette.TYPE_NAME, UiPalette.TYPE_BODY, UiPalette.TYPE_SMALL, UiPalette.TYPE_NUMBER]:
		assert_true(size >= 12, "%d is at or above the style bible's 12 px floor (2.1)" % size)


func test_tokens_style_a_label() -> void:
	# The way new HUD pieces use them: a font override and a size override from the type scale.
	var label := Label.new()
	label.text = "Aldermoor"
	label.add_theme_font_override("font", UiFonts.name())
	label.add_theme_font_size_override("font_size", UiPalette.TYPE_NAME)
	assert_true(label.get_theme_font("font") == UiFonts.name(), "the label draws with the name font")
	assert_eq(label.get_theme_font_size("font_size"), UiPalette.TYPE_NAME, "at the name size")
	var name_height := label.get_theme_font("font").get_height(label.get_theme_font_size("font_size"))
	label.add_theme_font_override("font", UiFonts.body())
	label.add_theme_font_size_override("font_size", UiPalette.TYPE_SMALL)
	var small_height := label.get_theme_font("font").get_height(label.get_theme_font_size("font_size"))
	assert_true(small_height < name_height, "a small body line is shorter than a name line (%s < %s)" % [small_height, name_height])
	label.free()
