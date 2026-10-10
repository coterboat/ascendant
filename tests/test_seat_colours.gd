extends "res://tests/test_case.gd"
## Player colours follow the seat, not the faction (director's call, design/STYLE_BIBLE.md 1.1):
## Player 1 is Vermilion and Player 2 Cobalt on the map, in the battle report, on the victory screen and
## on the new game screen, so swapping seats swaps the colours everywhere. UiPalette is the one place
## that decides, given the session's seat order.

const VERMILION := Color("#D8432C")
const COBALT := Color("#2D5BD1")


func test_palette_picks_colours_by_seat() -> void:
	assert_eq(UiPalette.seat_color(0), VERMILION)
	assert_eq(UiPalette.seat_color(1), COBALT)
	assert_eq(UiPalette.seat_color(-1), UiPalette.NEUTRAL, "nobody is slate")
	assert_eq(UiPalette.seat_color_name(0), "Vermilion")
	assert_eq(UiPalette.seat_color_name(1), "Cobalt")
	assert_eq(UiPalette.faction_color(["kingdom", "beasts"], "kingdom"), VERMILION)
	assert_eq(UiPalette.faction_color(["beasts", "kingdom"], "kingdom"), COBALT, "swapped seats, swapped colours")
	assert_eq(UiPalette.faction_color(["beasts", "kingdom"], "beasts"), VERMILION)
	assert_eq(UiPalette.faction_color(["beasts", "kingdom"], ""), UiPalette.NEUTRAL, "unowned")
	var s := GameState.new()
	assert_eq(UiPalette.owner_color(s, "beasts"), COBALT, "without seats, the state's faction order (a new game's default seats)")
	assert_eq(UiPalette.owner_color(s, "beasts", ["beasts", "kingdom"]), VERMILION, "the seat order wins")
	var session := GameSession.new(GameState.new(1), ["beasts", "kingdom"], 1)
	assert_eq(UiPalette.seat_order(s, session), ["beasts", "kingdom"], "a session's seat order")
	assert_eq(UiPalette.seat_order(s), ["kingdom", "beasts"], "no session: the state's order")
	assert_eq(UiPalette.seat_order(), ["kingdom", "beasts"], "nothing: the faction data order")


func test_swapped_seats_swap_colours_on_every_screen() -> void:
	for seats in [["kingdom", "beasts"], ["beasts", "kingdom"]]:
		var game := load("res://ui/game_screen.tscn").instantiate() as GameScreen
		game.start_game({"players": seats, "seed": 3})
		var colour := {seats[0]: VERMILION, seats[1]: COBALT}
		# Map: capitals, army badges, the side panel's owner line and army border.
		assert_eq(game.map.regions["crownkeep"].ring_color, colour["kingdom"], "%s: Crownkeep ring" % [seats])
		assert_eq(game.map.regions["fangridge"].ring_color, colour["beasts"], "%s: Fangridge ring" % [seats])
		var badge := game.map.regions["fangridge"].army_box.get_child(0) as Button
		assert_eq((badge.get_theme_stylebox("normal") as StyleBoxFlat).bg_color, colour["beasts"], "%s: army badge" % [seats])
		game.map.select_province("fangridge")
		var owner := game.map.details.find_children("OwnerLabel", "Label", true, false)[0] as Label
		assert_eq(owner.get_theme_color("font_color"), colour["beasts"].lightened(0.3), "%s: owner line" % [seats])
		var listed := game.map.details.find_children("ArmyRow_beasts-1", "PanelContainer", true, false)[0] as PanelContainer
		assert_eq((listed.get_theme_stylebox("panel") as StyleBoxFlat).border_color, colour["beasts"], "%s: army row border" % [seats])
		game.map.select_army("beasts-1")
		var army := game.map.details.find_children("Army_beasts-1", "PanelContainer", true, false)[0] as PanelContainer
		assert_eq((army.get_theme_stylebox("panel") as StyleBoxFlat).border_color, colour["beasts"], "%s: army border" % [seats])
		# Battle report: both sides by seat.
		var s := game.session.state()
		var sides := [{"faction": "beasts", "armies": [s.find_army("beasts-1")]}, {"faction": "kingdom", "armies": [s.find_army("kingdom-1")]}]
		var ctx := {"kind": "province", "defender": "", "province": s.find_province("thornvale"), "province_ids": ["thornvale"], "state": s}
		var report: Dictionary = AutoBattleResolver.fight(sides, ctx, SeededRNG.new(2)).result.report
		game._show_battle_report({"type": "battle", "numbers": {"report": report}, "text": ""})
		for f in seats:
			assert_eq(game.battle_viewer.side_color(f), colour[f], "%s: %s in the battle report" % [seats, f])
		var cards := game.battle_viewer.section("sides").find_child("SideCards", true, false)
		for card in cards.get_children():
			var name_label := card.find_child("SideName", true, false) as Label
			var fid := "kingdom" if name_label.text == "Aurel Crown" else "beasts"
			assert_eq((card.get_theme_stylebox("panel") as StyleBoxFlat).border_color, colour[fid], "%s: %s card" % [seats, name_label.text])
		game.free()


func test_victory_and_new_game_screens_colour_by_seat() -> void:
	var screen := VictoryScreen.new()
	var summary := {"over": true, "winner": "beasts", "draw": false, "turn": 4, "turns_played": 4, "battles": 1,
		"provinces_held": {"beasts": 8, "kingdom": 6}, "captures": [], "text": "Thornmane Clans wins."}
	screen.show_victory(summary, GameState.new(), ["beasts", "kingdom"])
	assert_eq(screen.headline_label.get_theme_color("font_color"), VERMILION.lightened(0.25), "player 1 won: Vermilion headline")
	assert_eq(screen.province_labels()[0].get_theme_color("font_color"), VERMILION.lightened(0.3), "seat 1 row")
	assert_eq(screen.province_labels()[1].get_theme_color("font_color"), COBALT.lightened(0.3), "seat 2 row")
	screen.show_victory(summary, GameState.new(), ["kingdom", "beasts"])
	assert_eq(screen.headline_label.get_theme_color("font_color"), COBALT.lightened(0.25), "player 2 won: Cobalt headline")
	screen.free()

	var setup := NewGameScreen.new()
	assert_eq(setup.seat_labels[0].get_theme_color("font_color"), VERMILION.lightened(0.3), "Player 1 is Vermilion")
	assert_eq(setup.seat_labels[1].get_theme_color("font_color"), COBALT.lightened(0.3), "Player 2 is Cobalt")
	assert_eq(setup.seat_pickers[0].get_theme_color("font_color"), VERMILION.lightened(0.3), "seat 1's faction reads in Vermilion")
	assert_true(setup.faction_labels[0].text.begins_with("Plays in Vermilion. Capital Crownkeep"), setup.faction_labels[0].text)
	setup.swap_seats()
	assert_true(setup.faction_labels[0].text.begins_with("Plays in Vermilion. Capital Fangridge"), "after a swap the other faction is Vermilion: %s" % setup.faction_labels[0].text)
	assert_true(setup.faction_labels[1].text.begins_with("Plays in Cobalt. Capital Crownkeep"), setup.faction_labels[1].text)
	setup.free()
