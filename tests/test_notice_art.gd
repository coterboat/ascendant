extends "res://tests/test_case.gd"
## UX-6 (design/UX_WAR_TABLE.md §5.2, "An image for every notice"): the medallion's image. Until UX-ART paints them the medallion is the kind's
## icon on a coloured disc; the moment a file named after its medallion type is in assets/ui/notices/ (or one named after its kind, which
## stands in for every type of that kind without a file of its own), the medallion wears it, round, with no code change.

var _saved_dir := ""
var _scratch := ""


func _begin() -> void:
	_saved_dir = NoticeArt.dir
	_scratch = "user://notice_art_test_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(_scratch)
	NoticeArt.dir = _scratch + "/"
	NoticeArt.clear_cache()


func _end() -> void:
	NoticeArt.dir = _saved_dir
	NoticeArt.clear_cache()
	for f in DirAccess.get_files_at(_scratch):
		DirAccess.remove_absolute(_scratch.path_join(f))
	DirAccess.remove_absolute(_scratch)


func _paint(name: String, colour: Color, px: int = 96) -> void:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(colour)
	assert_eq(img.save_png("%s/%s.png" % [_scratch, name]), OK)


func test_the_shipped_folder_has_no_art_yet_and_the_placeholder_stands_in() -> void:
	assert_eq(NoticeArt.dir, "res://assets/ui/notices/")
	var shipped := DirAccess.get_files_at("res://assets/ui/notices") if DirAccess.dir_exists_absolute("res://assets/ui/notices") else PackedStringArray()
	for key in ChronicleModel.image_keys():
		var info := ChronicleModel.image_info(key)
		var m := NoticeMedallion.new({"id": "x", "image": key, "kind": info.kind, "headline": "h", "detail": "d"}, 52.0, true)
		var painted := shipped.has("%s.png" % key) or shipped.has("%s.png" % info.kind)
		assert_eq(m.has_art(), painted, "%s: art only when a file is there" % key)
		m.free()
	for kind in ChronicleModel.KINDS:
		assert_true(NoticeArt.DISC.has(kind), "%s has its disc colour" % kind)
		assert_true(UiIcons.NAMES.has(String(ChronicleModel.KIND_ICONS[kind])) or ChronicleModel.KIND_ICONS[kind] == "flag", "%s has its icon" % kind)


func test_a_file_named_after_the_medallion_type_is_worn_round() -> void:
	_begin()
	assert_eq(NoticeArt.path_for("battle_won", "battles"), "", "nothing yet")
	assert_true(NoticeArt.texture("battle_won", "battles", 52) == null)
	_paint("battle_won", Color(0.9, 0.2, 0.2))
	assert_eq(NoticeArt.path_for("battle_won", "battles"), "%s/battle_won.png" % _scratch)
	var tex := NoticeArt.texture("battle_won", "battles", 52)
	assert_true(tex != null, "the art is loaded")
	assert_eq([tex.get_width(), tex.get_height()], [52, 52], "at the medallion's size")
	var img := tex.get_image()
	assert_true(img.get_pixel(26, 26).a > 0.99 and img.get_pixel(26, 26).r > 0.8, "opaque and painted in the middle")
	assert_true(img.get_pixel(0, 0).a < 0.01 and img.get_pixel(51, 0).a < 0.01 and img.get_pixel(0, 51).a < 0.01, "and cut away at the corners: a disc")
	var m := NoticeMedallion.new({"id": "x", "image": "battle_won", "kind": "battles", "headline": "h", "detail": "d"}, 52.0, true)
	assert_true(m.has_art(), "so the medallion wears it, with no code change")
	m.free()
	_end()


func test_a_file_named_after_a_kind_stands_in_for_its_types_that_have_no_file_of_their_own() -> void:
	_begin()
	_paint("battles", Color(0.2, 0.2, 0.9))
	assert_eq(NoticeArt.path_for("battle_lost", "battles"), "%s/battles.png" % _scratch, "a type with no file of its own wears its kind's")
	assert_eq(NoticeArt.path_for("army_lost", "battles"), "%s/battles.png" % _scratch)
	assert_eq(NoticeArt.path_for("province_taken", "land"), "", "another kind has none")
	_paint("battle_lost", Color(0.1, 0.9, 0.1))
	assert_eq(NoticeArt.path_for("battle_lost", "battles"), "%s/battle_lost.png" % _scratch, "its own file wins over its kind's")
	_end()


func test_the_flag_icon_the_set_lacks_is_drawn_in_its_style() -> void:
	for px in [16, 24, 48]:
		var tex := NoticeArt.icon("flag", px)
		assert_true(tex != null, "a flag at %d px" % px)
		assert_eq([tex.get_width(), tex.get_height()], [px, px])
		var img := tex.get_image()
		var inked := 0
		for y in px:
			for x in px:
				var c := img.get_pixel(x, y)
				if c.a > 0.2:
					inked += 1
					assert_true(c.r > 0.99 and c.g > 0.99 and c.b > 0.99, "a white mask, tinted by the caller")
		assert_true(inked > px, "the flag has ink (%d)" % inked)
	assert_eq(NoticeArt.icon("gold", 24), UiIcons.icon("gold", 24), "every other icon is UiIcons'")
