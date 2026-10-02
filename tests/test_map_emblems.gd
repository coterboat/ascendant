extends "res://tests/test_case.gd"
## Colour is never the only channel (design/STYLE_BIBLE.md 1.1, an accessibility requirement): on the
## map every owner ring and army badge carries its seat's emblem (Player 1 circle, Player 2 square,
## nobody a slate shield), as the new game and victory screens already did. The emblem follows the
## seat, like the colour, so swapping seats swaps the emblems too.

const GAME_SCENE := "res://ui/game_screen.tscn"


func test_shapes_by_seat() -> void:
	assert_eq(SeatEmblem.shape_of(0), "circle", "Player 1")
	assert_eq(SeatEmblem.shape_of(1), "square", "Player 2")
	assert_eq(SeatEmblem.shape_of(-1), "shield", "nobody (the bible's independents)")
	assert_eq(SeatEmblem.describe(0), "Vermilion circle")
	assert_eq(SeatEmblem.describe(1), "Cobalt square")
	assert_eq(SeatEmblem.describe(-1), "slate shield")
	assert_eq(UiPalette.seat_index(GameState.new(), "beasts", ["beasts", "kingdom"]), 0)
	assert_eq(UiPalette.seat_index(GameState.new(), "beasts"), 1, "without seats, the state's order")
	assert_eq(UiPalette.seat_index(GameState.new(), ""), -1, "nobody")
	# The new game and victory screens draw the same emblem.
	var e := VictoryScreen.seat_emblem(1)
	assert_true(e is SeatEmblem and e.seat == 1 and e.look == SeatEmblem.Look.TOKEN)
	e.free()


func test_emblems_on_the_map_for_both_seats() -> void:
	for seats in [["kingdom", "beasts"], ["beasts", "kingdom"]]:
		var game := load(GAME_SCENE).instantiate() as GameScreen
		game.start_game({"players": seats, "seed": 21})
		var map := game.map
		var shapes := {}  # shape -> how many rings show it
		for p in map.state.provinces:
			var region: ProvinceRegion = map.regions[p.id]
			var expected: int = seats.find(p.owner) if not p.owner.is_empty() else -1
			assert_eq(region.owner_seat, expected, "%s: %s ring emblem follows the owner's seat" % [seats, p.name])
			shapes[SeatEmblem.shape_of(region.owner_seat)] = shapes.get(SeatEmblem.shape_of(region.owner_seat), 0) + 1
			assert_true(Rect2(Vector2.ZERO, region.size).has_point(region.emblem_position()), "%s's emblem is drawn on the region" % p.name)
			var mark := "Neutral: slate ring, shield emblem." if expected < 0 else "Player %d's province: %s ring, %s emblem." % [
				expected + 1, UiPalette.seat_color_name(expected), SeatEmblem.shape_of(expected)]
			assert_true(region.tooltip_text.replace("\n", " ").contains(mark), "%s's tooltip says it in words: %s" % [p.name, region.tooltip_text])
		assert_eq(shapes.get("circle", 0), 1, "%s: Player 1's capital shows the circle" % [seats])
		assert_eq(shapes.get("square", 0), 1, "%s: Player 2's capital shows the square" % [seats])
		assert_eq(shapes.get("shield", 0), map.state.provinces.size() - 2, "%s: every neutral province shows the shield" % [seats])
		assert_eq(map.regions["crownkeep"].owner_seat, seats.find("kingdom"))
		assert_eq(map.regions["fangridge"].owner_seat, seats.find("beasts"))

		# Army badges: both seats' starting armies, each with its owner's emblem as a light glyph.
		var seen := {}
		for id in map.regions:
			for badge in map.regions[id].army_box.get_children():
				var army := map.state.find_army(String(badge.name).trim_prefix("Army_"))
				assert_true(army != null, "badge %s belongs to an army" % badge.name)
				if army == null:
					continue
				var emblem := badge.find_child("SeatEmblem", false, false) as SeatEmblem
				assert_true(emblem != null, "%s: the %s badge has an emblem" % [seats, army.id])
				if emblem == null:
					continue
				assert_eq(emblem.seat, seats.find(army.owner), "%s: the badge emblem follows the seat" % [seats])
				assert_eq(emblem.look, SeatEmblem.Look.GLYPH, "a light glyph, readable on the seat colour")
				assert_eq(emblem.mouse_filter, Control.MOUSE_FILTER_IGNORE, "clicks still reach the badge")
				assert_true((badge.get_theme_stylebox("normal") as StyleBoxFlat).content_margin_left >= emblem.custom_minimum_size.x,
					"the badge text starts after the emblem")
				assert_true(badge.tooltip_text.replace("\n", " ").contains(SeatEmblem.shape_of(emblem.seat) + " emblem"), badge.tooltip_text)
				seen[SeatEmblem.shape_of(emblem.seat)] = true
		assert_true(seen.has("circle") and seen.has("square"), "%s: both seats' army badges carry their emblems" % [seats])

		# The top bar shows the player at the controls with their emblem, and hides it when nobody is.
		assert_true(map.faction_emblem.visible)
		assert_eq(map.faction_emblem.seat, 0, "Player 1 has the computer first")
		game.end_turn()
		game.handoff.ready_button.pressed.emit()
		assert_eq(map.faction_emblem.seat, 1, "then Player 2")
		assert_eq(map.faction_label.text, map.state.find_faction(seats[1]).faction_name)
		map.set_state(map.state, "")
		assert_false(map.faction_emblem.visible, "no emblem when nobody's view is shown")
		game.free()
