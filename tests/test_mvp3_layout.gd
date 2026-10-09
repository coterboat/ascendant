extends "res://tests/test_case.gd"
## MVP-3 (#177), the pieces of the screens and the 3D stage that are pure enough to pin without a window (tests/test_mvp3_polish.gd
## has the screens' texts and tests/test_screens_fit.gd the layout at both sizes):
##   6  PanelFit's pivot puts a shrunk panel's middle on the window's middle, and its corners inside the window;
##   9  a spell's words are kept whole inside the field and apart from each other (BattleStage3D.place_words);
##   10 the woods, rocks and cottages take the ground's veil in a fog game and not otherwise (WorldView.prop_fog_on).
## Numbers come from the panels' own sizes and the stage's own constants, never from this file.

const GAME_SCENE := "res://ui/game_screen.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"
const VS_COMPUTER := {"players": [CROWN, CLANS], "seed": 4242, "ai": {CLANS: "normal"}}


func test_the_pivot_puts_the_panels_middle_on_the_windows() -> void:
	# A 1560x850 panel in a 1280x720 window sits at the top-left of its (min-size) holder: its middle is the panel size / 2.
	var s := PanelFit.scale_for(ResearchPanel.PANEL_SIZE, Vector2(1280, 720))
	assert_true(s < 1.0, "the research panel is too big for a 1280x720 window")
	var middle := ResearchPanel.PANEL_SIZE * 0.5
	var window_middle := Vector2(640, 360)
	var pivot := PanelFit.pivot_for(s, middle, window_middle, Vector2.ZERO)
	var mapped := pivot + (middle - pivot) * s
	assert_true(mapped.is_equal_approx(window_middle), "scaling about the pivot lands the panel's middle on the window's (%s)" % mapped)
	for corner in [Vector2.ZERO, Vector2(ResearchPanel.PANEL_SIZE.x, 0), Vector2(0, ResearchPanel.PANEL_SIZE.y), ResearchPanel.PANEL_SIZE]:
		var p: Vector2 = pivot + (corner - pivot) * s
		assert_true(p.x >= -0.01 and p.y >= -0.01 and p.x <= 1280.01 and p.y <= 720.01, "a corner of the panel is inside the window: %s" % p)
	assert_eq(PanelFit.pivot_for(1.0, middle, window_middle, Vector2.ZERO), Vector2.ZERO, "nothing to scale: no pivot")
	assert_eq(PanelFit.pivot_for(s, middle, window_middle, Vector2(10, 20)), pivot - Vector2(10, 20), "in the holder's own coordinates")


func test_a_spells_words_stay_whole_and_apart() -> void:
	var field := Rect2(Vector2(0, BattleStage3D.WORDS_TOP), Vector2(1200, 600.0 - BattleStage3D.WORDS_TOP))
	var words := Rect2(Vector2(1180, 10), Vector2(150, 20))  # the top-right corner, and wider than the room left
	var placed := BattleStage3D.place_words(words, [], field)
	assert_true(field.encloses(placed), "inside the field, whole: %s in %s" % [placed, field])
	assert_true(placed.position.y >= BattleStage3D.WORDS_TOP, "below the round banner and the toast")
	# Words that all want one spot take a line each, and none leaves the field.
	var taken: Array = []
	for i in 4:
		var r := BattleStage3D.place_words(Rect2(Vector2(300, 200), Vector2(120, 20)), taken, field)
		assert_true(field.encloses(r), "word %d is inside the field" % i)
		for t in taken:
			assert_false((t as Rect2).intersects(r), "word %d does not sit on another: %s against %s" % [i, r, t])
		taken.append(r)
	# Words that start at the top edge, over a number already there, are pushed down, not up out of the field.
	var number := Rect2(Vector2(300, BattleStage3D.WORDS_TOP), Vector2(120, 20))
	var low := BattleStage3D.place_words(Rect2(Vector2(300, 0), Vector2(120, 20)), [number], field)
	assert_true(field.encloses(low) and not low.intersects(number), "pushed down, not out: %s" % low)


func test_the_woods_take_the_grounds_veil_in_a_fog_game_only() -> void:
	for fog in [true, false]:
		var config := VS_COMPUTER.duplicate()
		if fog:
			config["fog"] = true
		var game := load(GAME_SCENE).instantiate() as GameScreen
		game.autosave_enabled = false
		game.start_game(config)
		var b := Board3D.new()
		game.map.set_board(b)
		b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		b.size = Vector2(1200, 836)
		b.build_now()
		assert_eq(b.wv.prop_fog_on, fog, "the woods are veiled with the ground (fog %s)" % fog)
		var mats: Array = b.wv._prop_mats
		assert_true(mats.size() > 0, "the board has wood materials")
		for m in mats:
			var mat := m as ShaderMaterial
			assert_eq(float(mat.get_shader_parameter("prop_fog")), 1.0 if fog else 0.0, "each material follows the ground")
			assert_true(mat.get_shader_parameter("prop_vision") != null and mat.get_shader_parameter("prop_data_n") != null,
				"and reads the ground's vision and province textures")
		game.free()
