extends "res://tests/test_case.gd"
## #125, the UI's share: the battle top bar's terrain and fort chips never overlap the title or the plaques
## (the Simple view and the 3D stage share the bar), and the checkboxes read on the dark panels.

const Fx := preload("res://tests/battle_playback_fixtures.gd")


## The rect the title's words take (it is centred in its label).
func _title_rect(v: BattleSimpleView) -> Rect2:
	var l := v.title_label
	var w := v._font_of(l).get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, v._font_size_of(l, 20)).x
	return Rect2(l.position.x + (l.size.x - w) / 2.0, l.position.y, w, l.size.y)


func _plaque_rect(v: BattleSimpleView, k: int) -> Rect2:
	var l: Label = v.plaque_labels[k]
	var w := minf(v._font_of(l).get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, v._font_size_of(l, 18)).x, l.size.x)
	var x := l.position.x if k == 0 else l.position.x + l.size.x - w
	return Rect2(x, l.position.y, w, l.size.y)


func _check_chips(v: BattleSimpleView, what: String) -> int:
	var placed := 0
	for k in 2:
		var box: HBoxContainer = v.chip_boxes[k]
		if box.get_child_count() == 0:
			continue
		placed += 1
		var r := Rect2(box.position, box.size)
		assert_true(r.size.x >= v.chips_width(box.get_children()) - 0.5, "%s: slot %d's box holds its chips" % [what, k])
		assert_false(r.intersects(_title_rect(v)), "%s: the chips keep off the title (%s vs %s)" % [what, r, _title_rect(v)])
		for j in 2:
			assert_false(r.intersects(_plaque_rect(v, j)), "%s: the chips keep off plaque %d" % [what, j])
		assert_true(r.position.x >= 0.0 and r.end.x <= BattleSimpleView.BASE.x, "%s: inside the bar" % what)
		for c in box.get_children():
			assert_false(String((c as Label).get_meta("full", "")).is_empty(), "%s: every chip keeps its full words" % what)
	return placed


func test_the_chips_never_overlap_the_title_or_a_plaque() -> void:
	var v := BattleSimpleView.new()
	var with_chips := 0
	for name in Fx.names():
		var fx := Fx.battle(name)
		v.show_battle(fx.log, fx.report)
		with_chips += _check_chips(v, name)
	assert_true(with_chips >= 3, "the fort and terrain battles have chips (%d)" % with_chips)
	## the case of #109's shot 06 and worse: hills and a fort, with a long people name on the defender's plaque
	var sg: Dictionary = Fx.battle("round_cap_defender")
	var lg: Dictionary = sg.log.duplicate(true)
	for sd in lg.sides:
		if sd.defender:
			sd["people"] = {"id": "celestial_host", "name": "Celestial Host"}
	v.show_battle(lg, sg.report)
	assert_eq(_check_chips(v, "long plaque"), 1, "the defender's chips are placed")
	var box: HBoxContainer = null
	for k in 2:
		if v.chip_boxes[k].get_child_count() > 0:
			box = v.chip_boxes[k]
	var short_or_moved := false
	for c in box.get_children():
		if (c as Label).text != String((c as Label).get_meta("full")):
			short_or_moved = true
	short_or_moved = short_or_moved or box.position.y > 20.0
	assert_true(short_or_moved, "with no room beside the plaque they take their short words, or the row under the round")
	v.free()
	## the 3D stage shares the bar
	var s := BattleStage3D.new()
	var fort := Fx.battle("round_cap_defender")
	s.show_battle(fort.log, fort.report)
	assert_eq(_check_chips(s, "3D stage"), 1)
	s.free()


static func _lum(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


func test_checkboxes_read_on_the_dark_panels() -> void:
	var theme: Theme = load(ProjectSettings.get_setting("gui/theme/custom"))
	for icon in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		assert_true(theme.has_icon(icon, "CheckBox"), "the theme draws its own %s box" % icon)
	for icon2 in ["checked", "unchecked"]:
		var img: Image = theme.get_icon(icon2, "CheckBox").get_image()
		if img.is_compressed():
			img.decompress()
		var bright := 0.0
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.8:
					bright = maxf(bright, _lum(c))
		var bg := _lum(UiPalette.PANEL_BG)
		var ratio := (bright + 0.05) / (bg + 0.05)
		assert_true(ratio >= 3.0, "the %s box stands out from the panel at 3:1 or more (WCAG non-text contrast: %.1f)" % [icon2, ratio])
	var panel := SettingsPanel.new()
	panel.open(GameSettings.load_from(GameSettings.default_path.get_base_dir().path_join("ui_polish_%d.cfg" % OS.get_process_id())))
	for c in [panel.mute_toggle, panel.reduced_motion_toggle]:
		assert_true((c as CheckBox).get_theme_icon("unchecked") == theme.get_icon("unchecked", "CheckBox"), "%s uses the visible box" % c.name)
	panel.free()
