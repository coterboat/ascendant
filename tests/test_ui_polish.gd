extends "res://tests/test_case.gd"
## #125, the UI's share: the battle view's terrain and fort chips never overlap the title or the plates (the Simple view and
## the 3D stage share them; UX-8 moved them to the centre), and the checkboxes read on the dark panels.

const Fx := preload("res://tests/battle_playback_fixtures.gd")


## UX-8 (#221): the terrain and fort chips moved from the side plates to the centre, between the plates. They must fit there
## (their short words when the full ones don't) at every supported size: the centre keeps off both plates and inside the view.
const SIZES := [Vector2(1600, 900), Vector2(1280, 720)]


func _check_chips(v: BattleSimpleView, what: String) -> int:
	var chips := v.conditions.get_children().filter(func(c): return (c as Control).visible)
	var centre := Rect2(v.centre.position, v.centre.size)
	for k in 2:
		var plate := Rect2(v.plates[k].position, v.plates[k].size)
		assert_false(centre.intersects(plate), "%s: the centre keeps off plate %d (%s vs %s)" % [what, k, centre, plate])
		assert_true(plate.position.x >= 0.0 and plate.end.x <= v.view_size().x, "%s: plate %d is inside the view" % [what, k])
	if chips.is_empty():
		return 0
	assert_true(v.chips_width(chips) <= v.centre.size.x - 20.0 + 0.5, "%s: the chips fit the centre (%.0f in %.0f)" % [what, v.chips_width(chips), v.centre.size.x - 20.0])
	for c in chips:
		assert_false(String((c as Label).get_meta("full", "")).is_empty(), "%s: every chip keeps its full words" % what)
		assert_false((c as Label).tooltip_text.is_empty(), "%s: and explains itself" % what)
	return 1


func test_the_chips_never_overlap_the_title_or_a_plaque() -> void:
	for at in SIZES:
		var v := BattleSimpleView.new()
		v.size = at
		var with_chips := 0
		for name in Fx.names():
			var fx := Fx.battle(name)
			v.show_battle(fx.log, fx.report)
			with_chips += _check_chips(v, "%s at %s" % [name, at])
		assert_true(with_chips >= 3, "the fort and terrain battles have chips (%d)" % with_chips)
		## the case of #109's shot 06 and worse: hills and a fort, with a long people name on the defender's plaque
		var sg: Dictionary = Fx.battle("round_cap_defender")
		var lg: Dictionary = sg.log.duplicate(true)
		for sd in lg.sides:
			if sd.defender:
				sd["people"] = {"id": "celestial_host", "name": "Celestial Host"}
		v.show_battle(lg, sg.report)
		assert_eq(_check_chips(v, "long plate at %s" % at), 1, "the defender's chips are placed")
		for k in 2:
			var l: Label = v.plaque_labels[k]
			var w := v._font_of(l).get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, v._font_size_of(l, UiPalette.TYPE_NAME)).x
			assert_true(w <= l.size.x + 0.5 or v._font_size_of(l, 0) == UiPalette.TYPE_SMALL + 1, "%s: plate %d's name fits or is at its smallest" % [at, k])
		v.free()
		## the 3D stage shares the plates and the centre
		var s := BattleStage3D.new()
		s.size = at
		var fort := Fx.battle("round_cap_defender")
		s.show_battle(fort.log, fort.report)
		assert_eq(_check_chips(s, "3D stage at %s" % at), 1)
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


## UX-1 (#194): the Table's text reads on its plaques wherever the board is bright under them. A plaque is the panel colour at 94% over
## the board; the worst board is white. The gold, the turn, the ruler line and the tray's hint keep WCAG's 4.5:1 for normal text against
## that. The seat colours that name a faction (existing: lightened 25% and 30%, test_m1_flow and test_seat_colours pin them) keep 3:1,
## the bar for large text and interface parts, which Cobalt over white is the closest to (4.0:1).
func test_the_tables_text_reads_on_its_plaques_over_the_brightest_board() -> void:
	var style := TableHud.plaque_style()
	var worst := style.bg_color.lerp(Color.WHITE, 1.0 - style.bg_color.a)
	worst.a = 1.0
	var colours := {"gold": UiPalette.GILT, "turn": UiPalette.TEXT_PRIMARY, "ruler line": UiPalette.TEXT_SECONDARY, "tray hint": UiPalette.TEXT_SECONDARY}
	for name in colours:
		var ratio := (_lum(colours[name]) + 0.05) / (_lum(worst) + 0.05)
		assert_true(ratio >= 4.5, "%s reads on a plaque over the brightest board (%.1f:1)" % [name, ratio])
	for seat in 2:
		for pair in [["seat %d's name" % (seat + 1), 0.25], ["seat %d's rival name" % (seat + 1), 0.3]]:
			var c: Color = UiPalette.seat_color(seat).lightened(float(pair[1]))
			var ratio2 := (_lum(c) + 0.05) / (_lum(worst) + 0.05)
			assert_true(ratio2 >= 3.0, "%s reads on a plaque over the brightest board (%.1f:1)" % [pair[0], ratio2])
	var seal_ratio := (_lum(UiPalette.GILT) + 0.05) / (_lum(worst) + 0.05)
	assert_true(seal_ratio >= 4.5, "End turn's gilt reads on the seal (%.1f:1)" % seal_ratio)
