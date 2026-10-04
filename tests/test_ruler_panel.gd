extends "res://tests/test_case.gd"
## M2-6 (#34): the ruler panel, the sacrifice dialog and the map marks, headless in the M1 UI-test style.
## The Ruler button (only with rulers), every number in the panel equal to its Breakdown with a codex
## link, the enemy ruler read-only, the dialog's preview equal to Forecast.sacrifice and Confirm queueing
## the order, cancel in the orders list naming the orders it removed, the gilt ruler ring on the map
## token, the capital countdown badge while a successor is pending, and no raw ids anywhere on screen.

const GAME_SCENE := "res://ui/game_screen.tscn"
const MAP_SCENE := "res://ui/map_screen.tscn"
const TopBar := preload("res://tests/test_top_bar.gd")
## Ids that must never reach player-facing text (case-sensitive: display names are capitalised).
const RAW_IDS := ["kingdom", "beasts", "crownkeep", "fangridge", "westwatch", "stonegate", "highcrag", "rivermarch",
	"aurel_king", "ever_regent", "thornmane_avatar", "fang_chieftain", "royal_court", "mending_light", "warband_muster",
	"iron_discipline", "drilled_ranks", "royal_armories", "kings_roads", "heavy_tithes", "veteran_levies",
	"muster_grounds", "sworn_vassals", "blood_frenzy", "feast_of_victory", "_"]
## The panel's numbers for a living ruler: label name -> the Breakdown behind it.
const NUMBER_LABELS := ["HpLabel", "AttackLabel", "DefenseLabel", "MoraleLabel", "KeptPowerLabel", "AbilityLabel"]


# --- fixtures -------------------------------------------------------------------------------------

func _game(config: Dictionary) -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	var full := {"players": ["kingdom", "beasts"], "seed": 21}
	full.merge(config, true)
	game.start_game(full)
	return game


func _rulers(builds: Dictionary, seed_value: int = 7) -> GameState:
	var errors := []
	var s := GameState.with_rulers(seed_value, builds, errors)
	assert_eq(errors, [], "the rulers set up")
	return s


func _screen(s: GameState, fid: String) -> MapScreen:
	var screen: MapScreen = load(MAP_SCENE).instantiate()
	screen.set_state(s, fid)
	return screen


func _breakdown_for(state: GameState, fid: String, label_name: String) -> Dictionary:
	match label_name:
		"HpLabel":
			return Breakdown.ruler_stat(state, fid, "hp")
		"AttackLabel":
			return Breakdown.ruler_stat(state, fid, "attack")
		"DefenseLabel":
			return Breakdown.ruler_stat(state, fid, "defense")
		"MoraleLabel":
			return Breakdown.ruler_stat(state, fid, "morale")
		"KeptPowerLabel":
			return Breakdown.kept_power(state, fid)
	return Breakdown.ability_rank(state, fid)


func _assert_no_raw_ids_under(root: Node, what: String) -> void:
	for n in root.find_children("*", "", true, false):
		var text := ""
		if n is Label:
			text = (n as Label).text
		elif n is Button:
			text = (n as Button).text
		if text.strip_edges().is_empty():
			continue
		for id in RAW_IDS:
			assert_false(text.contains(id), "%s: %s shows no raw id '%s': %s" % [what, n.name, id, text])


# --- the Ruler button and the panel -----------------------------------------------------------------

func test_the_ruler_button_shows_only_in_games_with_rulers() -> void:
	var m1 := _game({})
	assert_false(m1.ruler_button.visible, "an M1 game has no Ruler button")
	m1.open_ruler_panel()
	assert_true(m1.map.ruler_panel == null or not m1.map.ruler_panel.visible, "and no panel to open")
	m1.free()
	var game := _game({"rulers": true})
	assert_true(game.ruler_button.visible, "a game with rulers has the Ruler button")
	assert_eq(String(game.ruler_button.get_meta(CodexLink.META)), "ruler")
	game.ruler_button.pressed.emit()
	var panel := game.map.ruler_panel
	assert_true(panel != null and panel.visible, "the button opens the ruler panel")
	assert_eq(String(panel.columns.get_child(0).name), "Column_kingdom", "your ruler first")
	assert_eq(String(panel.columns.get_child(1).name), "Column_beasts", "then the enemy's")
	panel.close_button.pressed.emit()
	assert_false(panel.visible)
	# The ruler's army in the side panel opens it too.
	game.map.select_province("crownkeep")
	var open := game.map.details.find_child("OpenRulerPanel", true, false) as Button
	assert_true(open != null, "the side panel links the ruler panel")
	open.pressed.emit()
	assert_true(panel.visible)
	# The top bar still fits at 1600 px with the extra button.
	var top := TopBar.new()
	top._assert_fits(game.map, "rulers game")
	for f in top.get_failures():
		fail(f)
	game.free()


func test_every_number_in_the_ruler_panel_is_its_breakdown_with_a_codex_link() -> void:
	var game := _game({"builds": {"kingdom": "warrior_king", "beasts": "blood_of_the_fang"}})
	game.open_ruler_panel()
	var panel := game.map.ruler_panel
	var state := game.map.state
	for fid in ["kingdom", "beasts"]:
		var col := panel.columns.find_child("Column_%s" % fid, false, false)
		assert_true(col != null, "a column for %s" % fid)
		for label_name in NUMBER_LABELS:
			var l := col.find_child(label_name, true, false) as Label
			assert_true(l != null, "%s shows %s" % [fid, label_name])
			if l == null:
				continue
			var b := _breakdown_for(state, fid, label_name)
			assert_true(l.text.contains(str(int(b.total))), "%s %s shows the breakdown's total %d: %s" % [fid, label_name, int(b.total), l.text])
			assert_true(l.tooltip_text.begins_with(TooltipText.from_breakdown(b)), "%s %s's tooltip is its breakdown" % [fid, label_name])
			assert_eq(String(l.get_meta(CodexLink.META, "")), String(b.codex), "%s %s links its breakdown's codex entry" % [fid, label_name])
			assert_true(l.tooltip_text.replace("\n", " ").ends_with("Codex: %s (right-click or F1 to open)" % RulesCodex.entry(String(b.codex)).title))
		for other in ["RulerName", "KindLabel", "StatusLabel", "SuccessionLabel", "AbilityEffectLabel", "MandatesHeading"]:
			var l := col.find_child(other, true, false) as Label
			assert_true(l != null and RulesCodex.ENTRIES.has(String(l.get_meta(CodexLink.META, ""))), "%s %s links the codex" % [fid, other])
	var own := panel.columns.find_child("Column_kingdom", false, false)
	var enemy := panel.columns.find_child("Column_beasts", false, false)
	assert_eq((own.find_child("KeptPowerLabel", true, false) as Label).text, "Kept power: 10 of 10")
	assert_eq((own.find_child("HpLabel", true, false) as Label).text, "Hit points: 38 of 38")
	assert_eq((enemy.find_child("AbilityLabel", true, false) as Label).text, "Ability: Warband Muster, rank 2 (2 recruits in the field)")
	assert_true(own.find_child("SacrificeButton", true, false) != null, "your column can sacrifice")
	assert_true(enemy.find_child("SacrificeButton", true, false) == null, "the enemy's is read-only")
	assert_true((enemy.find_child("FactionHeading", true, false) as Label).text.contains("read-only"))
	# The enemy's mandates say what each does, for them, with a codex link.
	var row := enemy.find_child("Mandate_iron_discipline", true, false) as Label
	assert_true(row != null, "the enemy's mandates are listed")
	assert_eq(row.text, "Iron Discipline (3 power, chosen before the game)")
	assert_eq(String(row.get_meta(CodexLink.META)), "mandate_iron_discipline")
	assert_true(row.tooltip_text.replace("\n", " ").contains("For the Thornmane Clans now"), row.tooltip_text)
	# Right-clicking a number opens the codex there.
	(own.find_child("KeptPowerLabel", true, false) as Label).gui_input.emit(CodexLink.right_click())
	assert_true(game.codex.visible)
	assert_eq(game.codex.current_key(), "kept_power")
	_assert_no_raw_ids_under(panel, "the ruler panel")
	game.free()


# --- the sacrifice dialog -------------------------------------------------------------------------------

func test_the_dialog_previews_what_the_forecast_says_and_confirm_queues_the_order() -> void:
	var game := _game({"builds": {"kingdom": "warrior_king"}})
	game.open_ruler_panel()
	var panel := game.map.ruler_panel
	assert_false(panel.sacrifice_button.disabled, "a King keeping 10 can sacrifice")
	panel.sacrifice_button.pressed.emit()
	var dialog := game.map.sacrifice_dialog
	assert_true(dialog != null and dialog.visible, "the button opens the sacrifice dialog")
	(dialog.option_buttons["royal_armories"] as Button).pressed.emit()
	assert_eq(dialog.selected, "royal_armories")
	var forecast := Forecast.sacrifice(game.map.state, "kingdom", "royal_armories", game.session.current_orders())
	var expected: Array = forecast.rows.map(func(r): return {"label": r.label, "before": r.before, "after": r.after})
	assert_eq(dialog.shown_rows(), expected, "the dialog shows the forecast's rows, before and after")
	assert_eq(dialog.shown_rows()[0], {"label": "Kept power", "before": "10", "after": "6"})
	assert_eq(dialog.shown_rows()[1], {"label": "Hit points", "before": "38 of 38", "after": "30 of 30"})
	for cell in dialog.rows_grid.get_children():
		var l := cell as Label
		if l.mouse_filter == Control.MOUSE_FILTER_PASS:
			assert_true(RulesCodex.ENTRIES.has(String(l.get_meta(CodexLink.META, ""))), "row %s links the codex" % l.text)
			assert_true(l.tooltip_text.contains("= "), "row %s has a breakdown" % l.text)
	_assert_no_raw_ids_under(dialog, "the sacrifice dialog")
	assert_eq(game.session.current_orders(), [], "nothing is queued before Confirm")
	dialog.confirm_button.pressed.emit()
	assert_false(dialog.visible)
	var queued: Array = game.session.current_orders()
	assert_eq(queued.size(), 1)
	assert_true(queued[0] is SacrificeOrder and queued[0].mandate_id == "royal_armories", "Confirm queued the Sacrifice order")
	assert_true(game.map.status_text.begins_with("Sacrifice ordered: Royal Armories."), game.map.status_text)
	# The orders list shows it, linked to the codex; the panel shows it queued, and one per turn.
	var line := game.map.details.find_child("Order_0", true, false).find_child("OrderLine", true, false) as Label
	assert_true(line.text.begins_with("Sacrifice for Royal Armories: King Corvane I gives up 4 power (3, +1 for a mid-game sacrifice), keeping 6."), line.text)
	assert_eq(String(line.get_meta(CodexLink.META)), "sacrifice")
	assert_true(line.tooltip_text.contains("= Kept power after: 6"), line.tooltip_text)
	var own := panel.columns.find_child("Column_kingdom", false, false)
	assert_true((own.find_child("QueuedSacrificeLabel", true, false) as Label).text.begins_with("Queued this turn: Royal Armories for 4 power. Kept power 10 → 6"))
	assert_true(panel.sacrifice_button.disabled, "one sacrifice per turn")
	assert_true(game.end_turn_button.text.contains("1 order"), game.end_turn_button.text)
	game.free()


func test_the_dialog_disables_mandates_you_cannot_take_and_says_why() -> void:
	# The Ever-Regent keeping 4, with Royal Armories and Veteran Levies (3 + 3 power).
	var s := _rulers({"kingdom": {"ruler": "ever_regent", "mandates": ["royal_armories", "veteran_levies"]}})
	var map := _screen(s, "kingdom")
	map.open_ruler_panel()
	map.ruler_panel.sacrifice_button.pressed.emit()
	var dialog := map.sacrifice_dialog
	var owned := dialog.option_buttons["royal_armories"] as Button
	assert_true(owned.disabled)
	assert_true(owned.text.ends_with("Yours already."), owned.text)
	var dear := dialog.option_buttons["heavy_tithes"] as Button
	assert_true(dear.disabled)
	assert_true(dear.text.ends_with("Needs 5 power; the Ever-Regent keeps 4."), dear.text)
	assert_true(dear.tooltip_text.contains("keeps only 4"), dear.tooltip_text)
	assert_false((dialog.option_buttons["drilled_ranks"] as Button).disabled, "Drilled Ranks costs 3, which fits")
	assert_eq(dialog.selected, "iron_discipline", "the first mandate that fits is previewed")
	assert_false(dialog.confirm_button.disabled)
	map.free()
	# A dead ruler can't sacrifice: the button is off and the panel says why.
	var dead := _rulers({"kingdom": "warrior_king"})
	dead.current_turn = 3
	RulerRules.record_death(dead, "kingdom", 3)
	var map2 := _screen(dead, "kingdom")
	map2.open_ruler_panel()
	assert_true(map2.ruler_panel.sacrifice_button.disabled)
	var note := map2.ruler_panel.columns.find_child("SacrificeNote", true, false) as Label
	assert_true(note.text.begins_with("King Corvane I is dead, and only a living ruler can sacrifice power."), note.text)
	map2.free()


func test_cancelling_the_sacrifice_in_the_orders_list_says_which_orders_it_removed() -> void:
	var s := _rulers({"kingdom": "warrior_king"})
	for pid in ["westwatch", "stonegate"]:
		s.find_province(pid).owner = "kingdom"
	var map := _screen(s, "kingdom")
	map.select_army("kingdom-1")
	assert_false(map.regions["stonegate"].road_target, "no road rings without King's Roads")
	assert_eq(map.queue_sacrifice("kings_roads"), "")
	map.select_army("kingdom-1")
	assert_true(map.regions["stonegate"].road_target, "the queued sacrifice opens the road at once")
	map.select_province("stonegate")  # the second click orders the road move
	assert_eq(map.orders.orders().size(), 2)
	assert_true(map.orders.orders()[1].is_road_move())
	var cancel := map.details.find_child("Order_0", true, false).find_child("CancelButton", true, false) as Button
	cancel.pressed.emit()
	assert_eq(map.orders.orders(), [], "the road move went with the sacrifice")
	var status := map.details.find_child("StatusLabel", true, false) as Label
	assert_eq(status.text, "Order cancelled. Also removed, because they relied on what changed: Road move to Stonegate through Westwatch removed: you no longer have King's Roads.")
	map.free()


# --- the map: the gilt ruler ring and the capital countdown badge ------------------------------------

func test_the_ruler_army_badge_wears_the_gilt_ring() -> void:
	var map := _screen(_rulers({}), "kingdom")
	for pid in ["crownkeep", "fangridge"]:
		var badges: Array = map.regions[pid].army_box.get_children()
		var rings := 0
		for b in badges:
			var ring: Node = b.find_child("RulerRing", false, false)
			if (b as Button).text == "Ruler":
				assert_true(ring != null, "the ruler's badge at %s has the gilt ring" % pid)
				assert_eq((ring as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "the ring never takes the click")
				assert_true((b as Button).tooltip_text.contains("gilt ring"), "its tooltip says what the ring means")
				rings += 1
			else:
				assert_true(ring == null, "army 1 has no ring")
		assert_eq(rings, 1)
	map.free()
	var m1 := _screen(GameState.new(7), "kingdom")
	for b in m1.regions["crownkeep"].army_box.get_children():
		assert_true(b.find_child("RulerRing", false, false) == null, "no rings in an M1 game")
	m1.free()


func test_the_capital_shows_a_countdown_while_a_successor_is_pending() -> void:
	var s := _rulers({"kingdom": "warrior_king"})
	s.current_turn = 3
	RulerRules.record_death(s, "kingdom", 3)  # the King died during turn 3: Corvane II at the end of turn 5
	var map := _screen(s, "kingdom")
	var badge: Label = map.regions["crownkeep"].countdown_badge
	assert_true(badge != null, "Crownkeep shows the countdown")
	assert_eq(badge.text, "heir in 2 turns")
	assert_eq(String(badge.get_meta(CodexLink.META)), "succession_mortal")
	assert_true(badge.tooltip_text.begins_with(TooltipText.from_breakdown(Breakdown.successor_countdown(s, "kingdom"))))
	assert_true(badge.tooltip_text.contains("= Turns until it arrives, this one included: 2"), badge.tooltip_text)
	assert_true(map.regions["fangridge"].countdown_badge == null, "the living Fang's capital has none")
	# The ruler panel says the same, and what the heir will have.
	map.open_ruler_panel()
	var col := map.ruler_panel.columns.find_child("Column_kingdom", false, false)
	assert_eq((col.find_child("CountdownLabel", true, false) as Label).text, "Dead: heir in 2 turns")
	assert_eq((col.find_child("SuccessorLabel", true, false) as Label).text, "Corvane II will be crowned at Crownkeep at the end of turn 5.")
	assert_eq((col.find_child("SuccessorHpLabel", true, false) as Label).text, "Hit points: %d" % RulerRules.stat_value("aurel_king", "hp", 5))
	_assert_no_raw_ids_under(map.ruler_panel, "the panel of a dead ruler")
	map.free()
	# A turn later it counts down; once the heir is crowned the badge is gone.
	var next: GameState = TurnResolver.resolve(s, {}, 1, StubBattleResolver.new()).new_state
	var map2 := _screen(next, "kingdom")
	assert_eq(map2.regions["crownkeep"].countdown_badge.text, "heir in 1 turn")
	map2.free()
	var crowned: GameState = TurnResolver.resolve(next, {}, 2, StubBattleResolver.new()).new_state
	assert_true(RulerRules.has_living_ruler(crowned, "kingdom"), "Corvane II was crowned")
	var map3 := _screen(crowned, "kingdom")
	assert_true(map3.regions["crownkeep"].countdown_badge == null, "no countdown once the heir is crowned")
	map3.free()


func test_the_enemy_column_reads_its_mandates_in_the_third_person() -> void:
	var map := _screen(_rulers({"kingdom": "warrior_king", "beasts": "clan_moot"}), "kingdom")
	map.open_ruler_panel()
	var enemy := map.ruler_panel.columns.find_child("Column_beasts", false, false)
	var expected := {"iron_discipline": "Its side never breaks (routs) while one of its commanders in that battle stands, except at the end of the last round.",
		"blood_frenzy": "Its fighters below full hit points have +3 attack. A Tusker's Berserk adds to it, for +6.",
		"sworn_vassals": "Each turn, one neutral province next to its land swears fealty and joins it."}
	for mid in expected:
		var l := enemy.find_child("MandateEffect_%s" % mid, true, false) as Label
		assert_true(l != null, "%s is listed" % mid)
		assert_eq(l.text.strip_edges(), expected[mid])
	map.free()
	# Your own column keeps the rule as written.
	var own_map := _screen(_rulers({"beasts": "clan_moot"}), "beasts")
	own_map.open_ruler_panel()
	var own := own_map.ruler_panel.columns.find_child("Column_beasts", false, false)
	assert_eq((own.find_child("MandateEffect_iron_discipline", true, false) as Label).text.strip_edges(),
		String(RulerRules.mandate_data("iron_discipline").effect))
	own_map.free()


func test_the_panel_says_when_no_mandate_fits_and_explains_a_sacrificed_mandate() -> void:
	# The Iron Crown spent all 10 before the game: nothing fits.
	var spent := _screen(_rulers({"kingdom": "iron_crown"}), "kingdom")
	spent.open_ruler_panel()
	assert_true(spent.ruler_panel.sacrifice_button.disabled)
	var note := spent.ruler_panel.columns.find_child("SacrificeNote", true, false) as Label
	var cheapest := 99
	for mid in RulerRules.available_mandates("kingdom"):
		if not ["royal_armories", "heavy_tithes", "veteran_levies"].has(mid):
			cheapest = mini(cheapest, RulerRules.sacrifice_cost(mid))
	assert_eq(note.text, "No mandate fits: the cheapest one left costs %d power by sacrifice, and King Corvane I keeps 0." % cheapest)
	spent.free()
	# A mandate bought by sacrifice says so, with its cost's breakdown.
	var s := _rulers({"kingdom": "warrior_king"})
	var after: GameState = TurnResolver.resolve(s, {"kingdom": [SacrificeOrder.new("royal_armories")]}, 1, StubBattleResolver.new()).new_state
	var map := _screen(after, "kingdom")
	map.open_ruler_panel()
	var col := map.ruler_panel.columns.find_child("Column_kingdom", false, false)
	var row := col.find_child("Mandate_royal_armories", true, false) as Label
	assert_eq(row.text, "Royal Armories (4 power, sacrificed for on turn 1)")
	assert_true(row.tooltip_text.begins_with(TooltipText.from_breakdown(Breakdown.sacrifice_cost("royal_armories"))), row.tooltip_text)
	var kept := col.find_child("KeptPowerLabel", true, false) as Label
	assert_eq(kept.text, "Kept power: 6 of 10")
	assert_true(kept.tooltip_text.contains("Royal Armories, sacrificed on turn 1: -4"), kept.tooltip_text)
	map.free()
