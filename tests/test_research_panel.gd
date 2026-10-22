extends "res://tests/test_case.gd"
## M4-4 (#69): the research panel, the lock-in preview, the HUD chip, the enemy's read-only path, the turn
## report's own transformation and "needs you" line, and the victory screen's paths, headless in the M1
## UI-test style. Expected numbers come from AscensionRules, Forecast and Breakdown, never hardcoded.

const GAME_SCENE := "res://ui/game_screen.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"
## Ids that must never reach player-facing text (case-sensitive: display names are capitalised).
const RAW_IDS := ["kingdom", "beasts", "crown_", "beasts_", "celestial_host", "living_iron", "thorn_wild", "blood_pact",
	"path_", "hallowed_land", "wild_spreads", "dread_lands", "iron_colossus", "hymn_of_dawn", "forge_tithe",
	"deep_roots", "red_harvest", "heavy_tithes", "kings_roads", "blood_frenzy", "feast_of_victory", "research_order", "_"]


# --- fixtures -------------------------------------------------------------------------------------

func _paths(seed_value: int = 21) -> GameState:
	var errors := []
	var s := GameState.with_paths(seed_value, {}, errors)
	assert_eq(errors, [], "the paths game sets up")
	return s


func _tier1(fid: String) -> Array:
	return AscensionRules.node_ids(fid).filter(func(n): return AscensionRules.node_kind(n) == PathData.TIER1)


## A paths game where `fid` has both tier I nodes (so both Oaths are open).
func _ready_to_swear(fid: String, seed_value: int = 21) -> GameState:
	return AscensionRules.with_nodes(_paths(seed_value), fid, _tier1(fid))


func _panel(s: GameState, fid: String, orders: Array = [], can_order: bool = true) -> ResearchPanel:
	var panel := ResearchPanel.new()
	panel.show_for(s, fid, orders, can_order)
	return panel


## A hotseat game screen playing `s` (through a save, so the session starts from it), at seat 1's orders.
func _game_from(s: GameState, players: Array = [CROWN, CLANS]) -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.start_game({"players": players, "seed": 21, "paths": true})
	var session := GameSession.new(s, players, 21)
	var save := SaveGame.make(session, {}, "manual", "test", 0)
	assert_eq(game.load_game(save), "", "the prepared game loads")
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
	return game


func _game(config: Dictionary = {}) -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	var full := {"players": [CROWN, CLANS], "seed": 21}
	full.merge(config, true)
	game.start_game(full)
	return game


## Every text and tooltip under `node` that is visible, in tree order.
func _visible_text(node: Node) -> String:
	var out := PackedStringArray()
	_collect(node, out)
	return "\n".join(out)


func _collect(node: Node, out: PackedStringArray) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	if node is Control and not (node as Control).tooltip_text.is_empty():
		out.append((node as Control).tooltip_text)
	for c in node.get_children():
		_collect(c, out)


func _assert_no_raw_ids(text: String, what: String) -> void:
	assert_false(text.is_empty(), "%s has text" % what)
	for id in RAW_IDS:
		assert_false(text.contains(id), "%s shows no raw id '%s'" % [what, id])


## Every Label or Button under `root` whose text has a digit carries a breakdown (meta "breakdown") whose
## from_breakdown starts its tooltip and whose total is in the text.
func _assert_numbers_explained(root: Node, what: String) -> int:
	var checked := 0
	for n in root.find_children("*", "", true, false):
		if not (n is Label or n is Button) or not (n as CanvasItem).is_visible_in_tree() and n.is_inside_tree():
			continue
		var text: String = n.text
		if not RegEx.create_from_string("\\d").search(text):
			continue
		if n is Button and (n as Button).text.begins_with("Research:"):
			continue  # the chip is checked on its own
		if n.has_meta("rule_text"):
			continue  # a rule in words (a node's one-line effect, a province rule), explained by its codex link
		checked += 1
		assert_true(n.has_meta("breakdown"), "%s: '%s' (%s) has a breakdown" % [what, text, n.name])
		if not n.has_meta("breakdown"):
			continue
		var b: Dictionary = n.get_meta("breakdown")
		assert_true((n as Control).tooltip_text.begins_with(TooltipText.from_breakdown(b)), "%s: '%s' shows its breakdown on hover" % [what, text])
		assert_eq(Breakdown.sum_of_lines(b), int(b.total), "%s: '%s' breakdown lines sum to its total" % [what, text])
	return checked


func _card_state(panel: ResearchPanel, nid: String) -> String:
	return String(panel.cards[nid].get_meta("state")) if panel.cards.has(nid) else ""


func _label_in(panel: ResearchPanel, nid: String, label_name: String) -> Label:
	return panel.cards[nid].find_child(label_name, true, false) as Label


# --- the panel's states -------------------------------------------------------------------------------

func test_every_card_shows_its_node_state_with_the_plain_reason() -> void:
	var stages := []
	var fresh := _paths()
	stages.append(fresh)
	var one := AscensionRules.with_nodes(fresh, CROWN, ["crown_drillyard"])
	AscensionRules.set_target(one, CROWN, "crown_arbalests")
	stages.append(one)
	var sworn := AscensionRules.with_nodes(fresh, CROWN, ["crown_drillyard", "crown_charters", "crown_oath_dawn"])
	stages.append(sworn)
	var clans := AscensionRules.with_nodes(fresh, CLANS, ["beasts_raiding", "beasts_forest_stride", "beasts_oath_blood", "beasts_blood_pact"])
	stages.append(clans)
	var seen := {}
	for s in stages:
		for fid in [CROWN, CLANS]:
			var panel := _panel(s, fid)
			for nid in AscensionRules.node_ids(fid):
				var st := AscensionRules.node_state(s, fid, nid)
				assert_eq(_card_state(panel, nid), String(st.state), "%s's card shows node_state" % nid)
				seen[String(st.state)] = true
				var state_label := _label_in(panel, nid, "State")
				assert_false(state_label.text.is_empty(), "%s has a state line" % nid)
				if not String(st.reason).is_empty():
					assert_true(state_label.tooltip_text.contains(TooltipText.wrap_text(String(st.reason)).split("\n")[0]), "%s's state explains why: %s" % [nid, st.reason])
				if st.state == AscensionRules.CLOSED:
					var why := _label_in(panel, nid, "Reason")
					assert_true(why != null and why.visible, "a closed node shows its reason on the card")
					if why:
						assert_eq(why.text, String(st.reason))
						assert_true(why.text.begins_with("Closed: you swore"), why.text)
				var can: bool = st.state == AscensionRules.AVAILABLE
				assert_eq(panel.buttons.has(nid) and not panel.buttons[nid].disabled and panel.buttons[nid].text != "What it brings", can,
					"%s can be chosen exactly when it is available" % nid)
			_assert_no_raw_ids(_visible_text(panel), "the panel")
			panel.free()
	for name in [AscensionRules.RESEARCHED, AscensionRules.RESEARCHING, AscensionRules.AVAILABLE, AscensionRules.NEEDS, AscensionRules.CLOSED]:
		assert_true(seen.has(name), "the stages cover a %s node" % name)


## #281 (QA-1): on turn 1 only the capital pays research, and the Research per turn box says so plainly: "Crownkeep 5", not "Crownkeep
## 5, 0 other provinces 0". So does the Researching line ("You gain 5 a turn (Crownkeep 5)").
func test_the_research_box_names_the_capital_alone_before_any_capture() -> void:
	var s := _paths()
	var capital := int(PathData.RESEARCH.capital)
	var cap := s.find_province(s.find_faction(CROWN).capital).name
	AscensionRules.set_target(s, CROWN, "crown_charters")
	var panel := _panel(s, CROWN)
	var parts := panel.sidebar.find_child("RateParts", true, false) as Label
	assert_true(parts != null, "the box says where research comes from")
	if parts:
		assert_eq(parts.text, "%s %d" % [cap, capital])
	var text := panel.sidebar.find_child("TargetText", true, false) as Label
	assert_true(text != null and text.text.contains("You gain %d a turn (%s %d)," % [capital, cap, capital]), text.text if text else "no Researching line")
	# The breakdown behind the box still shows its "0 other provinces: +0" line: a sum, which says where more research would come from.
	assert_true(parts == null or parts.tooltip_text.contains("%s (capital): %d" % [cap, capital]), parts.tooltip_text if parts else "")
	panel.free()


func test_the_sidebar_shows_research_per_turn_the_pool_and_the_target() -> void:
	var s := _paths()
	s.find_faction(CROWN).research_points = 4
	AscensionRules.set_target(s, CROWN, "crown_charters")
	var panel := _panel(s, CROWN)
	var rate := panel.sidebar.find_child("RateLabel", true, false) as Label
	var rb := Breakdown.research_rate(s, CROWN)
	assert_true(rate.text.contains(str(int(rb.total))), rate.text)
	assert_eq(int(rate.get_meta("breakdown").total), int(AscensionRules.research_rate(s, CROWN).rate), "the rate is AscensionRules'")
	assert_eq(String(rate.get_meta(CodexLink.META)), "research_points")
	var target := panel.sidebar.find_child("TargetLabel", true, false) as Label
	assert_true(target.text.begins_with("Market Charters: 4 of 10"), target.text)
	var fc := Forecast.research(s, CROWN)
	var text := panel.sidebar.find_child("TargetText", true, false) as Label
	assert_eq(text.text, String(fc.text), "the target's forecast is Forecast.research's")
	for side in ["celestial_host", "living_iron"]:
		var route := panel.sidebar.find_child("Route_%s" % side, true, false) as Label
		assert_true(route != null, "the road to %s is shown" % side)
		if route:
			assert_true(route.text.begins_with(AscensionRules.branch_name(side)), route.text)
	assert_true(_assert_numbers_explained(panel, "sidebar") >= 6, "the panel's numbers were checked")
	panel.free()


# --- queueing goes through the session ---------------------------------------------------------------

func test_research_this_queues_through_the_session_with_its_forecast() -> void:
	var game := _game({"paths": true})
	var hud := game.research_hud
	assert_true(hud.chip.visible, "the chip shows in a paths game")
	assert_true(hud.chip.text.begins_with("Research: choose"), hud.chip.text)
	hud.chip.pressed.emit()
	var panel := hud.panel
	assert_true(panel != null and panel.visible, "the chip opens the research panel")
	assert_eq(panel.viewer_fid, CROWN)
	panel.buttons["crown_drillyard"].pressed.emit()
	var orders := game.session.current_orders()
	assert_eq(orders.size(), 1, "one order queued")
	assert_true(orders[0] is ResearchOrder and orders[0].node_id == "crown_drillyard", "a ResearchOrder in the session's book")
	assert_eq(_card_state(panel, "crown_drillyard"), AscensionRules.RESEARCHING, "the card now reads researching")
	var fc := Forecast.research(game.map.state, CROWN, orders)
	assert_true(panel.status_label.visible and panel.status_label.text.contains(String(fc.text)), "the forecast is in the status line")
	assert_true(hud.chip.text.begins_with("Research: Drillyard"), "the chip follows: %s" % hud.chip.text)
	assert_true(game.end_turn_button.text.contains("1 order"), game.end_turn_button.text)
	var token := game.map.table().tray_slot().token_for(0)
	assert_true(token != null and bool(token.mark.realm) and token.mark["class"] == "research", "the order is a realm token in the tray")
	game.map.show_order(0)  # its card, with the order's line
	var l := game.map.details.find_child("OrderLine", true, false) as Label
	assert_true(l != null and l.text.begins_with("Research: Drillyard"), l.text if l != null else "no order line")
	assert_eq(String(l.get_meta(CodexLink.META)), "research_order")
	# Another choice replaces it: still one research order.
	panel.buttons["crown_charters"].pressed.emit()
	orders = game.session.current_orders()
	assert_eq(orders.size(), 1, "a second research order replaces the first")
	assert_eq(orders[0].node_id, "crown_charters")
	game.free()


func test_an_oath_opens_the_lock_in_preview_and_only_swearing_queues_it() -> void:
	var game := _game_from(_ready_to_swear(CROWN))
	var hud := game.research_hud
	hud.open_panel()
	var panel := hud.panel
	var swear: Button = panel.buttons["crown_oath_dawn"]
	assert_true(swear.text.begins_with("Swear"), swear.text)
	swear.pressed.emit()
	assert_true(hud.preview != null and hud.preview.visible, "the Oath opens the lock-in preview")
	assert_eq(game.session.current_orders().size(), 0, "nothing is queued by opening the preview")
	assert_true(hud.preview.title_label.text.begins_with("Swear the Oath of the Dawn? It leads to the Celestial Host and closes Living Iron"), hud.preview.title_label.text)
	hud.preview.back_button.pressed.emit()
	assert_false(hud.preview.visible, "Back closes it")
	assert_eq(game.session.current_orders().size(), 0, "and queues nothing")
	swear.pressed.emit()
	hud.preview.confirm_button.pressed.emit()
	var orders := game.session.current_orders()
	assert_eq(orders.size(), 1, "Swear the Oath queues the research order")
	assert_eq(orders[0].node_id, "crown_oath_dawn")
	assert_false(hud.preview.visible, "and closes the preview")
	assert_eq(_card_state(panel, "crown_oath_dawn"), AscensionRules.RESEARCHING)
	assert_eq(_card_state(panel, "crown_oath_forge"), AscensionRules.AVAILABLE, "nothing is closed until the Oath is done")
	game.free()


# --- the lock-in preview equals the result ---------------------------------------------------------------

## For each of the four sides: the preview's roster, prices and income equal (1) AscensionRules.with_nodes
## applied to the same state, and (2) the state after actually swearing the Oath and completing the
## transformation through GameSession turns, with nobody moving.
func test_the_preview_equals_the_result_for_all_four_transformations() -> void:
	for side in PathData.BRANCHES:
		var fid := String(PathData.BRANCHES[side].faction)
		var oath := String(PathData.BRANCHES[side].oath)
		var trans := String(PathData.BRANCHES[side].transformation)
		var s := _ready_to_swear(fid)
		s.find_faction(fid).research_points = AscensionRules.node_cost(oath) + AscensionRules.node_cost(trans)
		var p := PathView.preview(s, fid, oath)
		assert_true(p.ok, "%s has a preview" % side)
		# (1) with_nodes.
		var expected := AscensionRules.with_nodes(s, fid, [oath, trans])
		AscensionRules.province_rules_step(expected, fid)
		_assert_preview_matches(p, expected, fid, "%s vs with_nodes" % side)
		# (2) Played out: swear the Oath this turn; its transformation becomes the target and completes next turn.
		var session := GameSession.new(s, [CROWN, CLANS], 21)
		assert_eq(session.current_player(), CROWN)
		if fid == CROWN:
			assert_eq(session.queue_research(oath), "")
		assert_eq(session.end_turn(), "")
		session.acknowledge_handoff()
		if fid == CLANS:
			assert_eq(session.queue_research(oath), "")
		assert_eq(session.end_turn(), "")
		assert_eq(AscensionRules.branch(session.state(), fid), side, "%s: the Oath was sworn" % side)
		for i in 2:
			session.acknowledge_handoff()
			assert_eq(session.end_turn(), "")
		session.acknowledge_handoff()
		var result := session.state()
		assert_true(AscensionRules.has_node(result, fid, trans), "%s: the transformation completed" % side)
		_assert_preview_matches(p, result, fid, "%s played out" % side)


func _assert_preview_matches(p: Dictionary, result: GameState, fid: String, what: String) -> void:
	var f := result.find_faction(fid)
	var roster_ids := []
	for ut in f.unit_types:
		if not ut.is_ruler:
			roster_ids.append(ut.id)
	var shown_ids := []
	for row in p.units:
		shown_ids.append(String(row.type))
		var us := RulerRules.unit_stats(result, fid, String(row.type))
		assert_eq(String(row.name), String(us.name), "%s: %s's name" % [what, row.type])
		for stat in PathView.STATS:
			assert_eq(int(row.cells[stat].after), int(us[stat]), "%s: %s %s" % [what, row.type, stat])
		var ut := TurnResolver.recruitable_type(f, String(row.type))
		assert_eq(int(row.cells.cost.after), RulerRules.recruit_price(result, fid, ut), "%s: %s's price" % [what, row.type])
	assert_eq(shown_ids, roster_ids, "%s: the preview shows the whole roster" % what)
	assert_eq(int(p.economy.after), int(Breakdown.income(result, fid).total), "%s: income per turn" % what)


func test_the_preview_shows_gains_losses_new_unit_and_was_now_numbers() -> void:
	for side in PathData.BRANCHES:
		var fid := String(PathData.BRANCHES[side].faction)
		var oath := String(PathData.BRANCHES[side].oath)
		var trans := String(PathData.BRANCHES[side].transformation)
		var other := AscensionRules.other_branch(fid, side)
		var s := _ready_to_swear(fid)
		var preview := LockInPreview.new()
		preview.show_for(s, fid, oath)
		var fx := AscensionRules.node_effects(trans)
		var gain := _visible_text(preview.gain_box)
		var lose := _visible_text(preview.lose_box)
		assert_true(gain.contains(AscensionRules.economy_rule_name(oath)), "%s: the Oath's economy rule is gained" % side)
		for type_id in fx.rename:
			assert_true(gain.contains(String(fx.rename[type_id])), "%s: the changed unit is gained" % side)
		assert_true(gain.contains(String(PathData.NEW_UNITS[String(fx.new_unit)].name)), "%s: the new unit is gained" % side)
		assert_true(gain.contains(RulerRules.mandate_name(String(fx.opens_mandate))), "%s: the opened mandate" % side)
		assert_true(lose.contains(AscensionRules.economy_rule_name(String(AscensionRules.branch_data(other).oath))), "%s: the other Oath's rule is lost" % side)
		assert_true(lose.contains(AscensionRules.node_name(String(AscensionRules.branch_data(other).transformation))), "%s: the other transformation is lost" % side)
		assert_true(lose.contains(RulerRules.mandate_name(String(fx.forswears))), "%s: the forsworn mandate is named" % side)
		var new_row := preview.roster.find_child("Unit_%s" % String(fx.new_unit), true, false) as Label
		assert_true(new_row != null and new_row.text.ends_with("(new)"), "%s: the new unit's row is marked new" % side)
		for type_id in fx.unit:
			for stat in fx.unit[type_id]:
				var was := preview.roster.find_child("Was_%s_%s" % [type_id, stat], true, false) as Label
				assert_true(was != null, "%s: %s %s shows what it was" % [side, type_id, stat])
		var portraits := preview.look_box.find_children("PathPortrait_*", "", true, false)
		assert_eq(portraits.size(), 2, "%s: the changed and the new unit in the fork's frame" % side)
		## M4's portraits (asc-3d-paths): the changed unit in its own look, the new unit in its portrait
		for pp in portraits:
			assert_true((pp as PathPortrait).has_art(), "%s: %s shows a portrait, not the placeholder" % [side, pp.name])
		for type_id in fx.rename:
			var changed := preview.look_box.find_child("PathPortrait_%s" % type_id, true, false) as PathPortrait
			assert_true(changed != null and changed.shows_variant, "%s: %s shows its %s look" % [side, type_id, trans])
		var added := preview.look_box.find_child("PathPortrait_%s" % String(fx.new_unit), true, false) as PathPortrait
		assert_true(added != null and not added.shows_variant, "%s: the new unit shows its own portrait" % side)
		assert_true(_assert_numbers_explained(preview, "%s preview" % side) >= 20, "%s: the preview's numbers were checked" % side)
		_assert_no_raw_ids(_visible_text(preview), "%s preview" % side)
		preview.free()


# --- the rival's path ----------------------------------------------------------------------------------

## Hotseat: the Crown (seat 1) chooses research, then the Clans (seat 2) open the panel, its enemy tab, the
## ruler panel and the turn report. Everything on screen is the same whatever the Crown chose, after the
## handoff and after the turn resolves: the target never shows.
func test_the_rivals_research_target_is_never_on_screen() -> void:
	var dumps := {}
	var start := AscensionRules.with_nodes(_paths(), CROWN, ["crown_drillyard"])
	assert_true(int(AscensionRules.research_rate(start, CROWN).rate) < AscensionRules.node_cost("crown_charters"),
		"neither target completes this turn, so the turn report is the same either way")
	for target in ["", "crown_arbalests", "crown_charters"]:
		var game := _game_from(start)
		var hud := game.research_hud
		if not target.is_empty():
			assert_eq(game.session.queue_research(target), "")
		game.end_turn()
		assert_true(game.handoff.visible, "hotseat: the handoff cover")
		game.handoff.ready_button.pressed.emit()
		assert_eq(game.session.current_player(), CLANS)
		var texts := PackedStringArray()
		hud.open_panel()
		texts.append(_visible_text(hud.panel))
		hud.panel.show_enemy(CROWN)
		var enemy := _visible_text(hud.panel)
		assert_false(enemy.contains("Researching"), "the enemy tab never says researching")
		assert_false(enemy.contains("Available"), "nor what they could research")
		texts.append(enemy)
		hud.panel.close()
		game.open_ruler_panel()
		texts.append(_visible_text(game.map.ruler_panel))
		game.map.close_ruler_panel()
		texts.append(_visible_text(game.map))
		# The turn resolves; seat 1 then seat 2 again.
		game.end_turn()
		game.handoff.ready_button.pressed.emit()
		game.close_turn_report()
		game.end_turn()
		game.handoff.ready_button.pressed.emit()
		assert_eq(game.session.current_player(), CLANS)
		texts.append(_visible_text(game.report_panel))
		game.close_turn_report()
		hud.open_panel()
		hud.panel.show_enemy(CROWN)
		texts.append(_visible_text(hud.panel))
		texts.append(_visible_text(game.map))
		dumps[target] = "\n".join(texts)
		game.free()
	assert_eq(dumps["crown_arbalests"], dumps[""], "seat 2 sees the same screens whatever seat 1 researches")
	assert_eq(dumps["crown_charters"], dumps[""], "seat 2 sees the same screens whatever seat 1 researches")


func test_the_enemy_tab_shows_their_public_path() -> void:
	var s := AscensionRules.with_nodes(_paths(), CLANS, ["beasts_boar_hide", "beasts_raiding", "beasts_oath_grove"], 3)
	AscensionRules.set_target(s, CLANS, "beasts_thorn_wild")
	var panel := _panel(s, CROWN)
	panel.show_enemy(CLANS)
	assert_false(panel.is_own())
	for nid in ["beasts_boar_hide", "beasts_raiding", "beasts_oath_grove"]:
		assert_eq(_card_state(panel, nid), AscensionRules.RESEARCHED, "%s is shown researched" % nid)
	assert_eq(_card_state(panel, "beasts_thorn_wild"), "unresearched", "their target reads only 'not researched'")
	assert_eq(_card_state(panel, "beasts_oath_blood"), AscensionRules.CLOSED, "the closed side is public")
	assert_eq(_label_in(panel, "beasts_oath_blood", "State").tooltip_text.split("\n\n")[1].replace("\n", " ").begins_with(
		"The Thornmane Clans swore the Oath of the Grove on turn 3"), true, "it says why, in their words")
	assert_true(panel.buttons.is_empty(), "nothing to press on their path")
	var sworn := panel.sidebar.find_child("SwornLabel", true, false) as Label
	assert_true(sworn.text.begins_with("Sworn to the Thorn Wild (the Oath of the Grove, turn 3)"), sworn.text)
	var rate := panel.sidebar.find_child("RateLabel", true, false) as Label
	assert_true(rate.text.contains(str(int(AscensionRules.research_rate(s, CLANS).rate))), "their research per turn is public")
	assert_true(panel.sidebar.find_child("PoolLabel", true, false) == null, "their pool is not shown")
	assert_true(panel.sidebar.find_child("TargetLabel", true, false) == null, "nor a target")
	_assert_numbers_explained(panel, "enemy tab")
	_assert_no_raw_ids(_visible_text(panel), "enemy tab")
	panel.free()


# --- the chip --------------------------------------------------------------------------------------------

func test_the_chip_appears_only_in_games_with_paths_and_fits_the_top_bar() -> void:
	for config in [{}, {"rulers": true}]:
		var game := _game(config)
		assert_false(game.research_hud.chip.visible, "no chip without paths: %s" % [config])
		game.research_hud.open_panel()
		assert_true(game.research_hud.panel == null, "and no panel to open")
		game.free()
	var game := _game({"paths": true})
	var chip := game.research_hud.chip
	assert_true(chip.visible)
	var c := PathView.chip(game.map.state, CROWN, [])
	assert_eq(chip.text, String(c.text))
	assert_true(chip.tooltip_text.begins_with(TooltipText.from_breakdown(Breakdown.research_progress(game.map.state, CROWN))), "the chip's tooltip is the research breakdown")
	assert_eq(String(chip.get_meta(CodexLink.META)), "research_order")
	var top := preload("res://tests/test_table_hud.gd").new()
	top._assert_fits(game.map, "paths game with the research chip")
	for f in top.get_failures():
		fail(f)
	game.free()


# --- hotseat ---------------------------------------------------------------------------------------------

func test_hotseat_the_panel_and_preview_close_on_handoff() -> void:
	var game := _game_from(_ready_to_swear(CROWN))
	var hud := game.research_hud
	hud.open_panel()
	hud.open_preview("crown_oath_forge")
	assert_true(hud.panel.visible and hud.preview.visible)
	game.end_turn()
	assert_true(game.handoff.visible, "the handoff cover is up")
	assert_false(hud.panel.visible, "the research panel closed on handoff")
	assert_false(hud.preview.visible, "the preview closed on handoff")
	assert_false(hud.chip.visible, "no chip under the cover")
	game.handoff.ready_button.pressed.emit()
	assert_true(hud.chip.visible, "seat 2 has its own chip")
	hud.open_panel()
	assert_eq(hud.panel.viewer_fid, CLANS, "seat 2's panel is the Clans' path")
	assert_eq(hud.panel.showing_fid, CLANS)
	game.free()


# --- the turn report and the victory screen ----------------------------------------------------------------

func test_the_turn_report_speaks_to_you_about_your_transformation_and_needs_you() -> void:
	var event := {"type": "transformed", "phase": "research", "factions": [CROWN], "provinces": [], "codex": "node_crown_celestial_host",
		"text": "The Aurel Crown has become the Celestial Host.", "numbers": {"own_text": "Your people have become the Celestial Host."}}
	assert_eq(TurnReportPanel.event_text(event, CROWN), "Your people have become the Celestial Host.")
	assert_eq(TurnReportPanel.event_text(event, CLANS), "The Aurel Crown has become the Celestial Host.")
	assert_eq(TurnReportPanel.event_text(event, ""), "The Aurel Crown has become the Celestial Host.")
	# Played: the Crown transforms; seat 1's report says "Your people", seat 2's says "The Aurel Crown".
	var s := AscensionRules.with_nodes(_paths(), CROWN, _tier1(CROWN) + ["crown_oath_dawn"])
	s.find_faction(CROWN).research_target = "crown_celestial_host"
	s.find_faction(CROWN).research_points = AscensionRules.node_cost("crown_celestial_host")
	var game := _game_from(s)
	game.end_turn()
	game.handoff.ready_button.pressed.emit()
	game.end_turn()
	game.handoff.ready_button.pressed.emit()
	assert_eq(game.session.current_player(), CROWN)
	var own := _visible_text(game.report_panel)
	assert_true(own.contains("Your people have become the Celestial Host."), "seat 1 reads its own transformation")
	var needs := game.report_panel.needs_you_label
	assert_true(needs != null and needs.text.begins_with("Needs you: Choose what to research"), "the needs-you line: nothing is chosen after a transformation")
	game.close_turn_report()
	game.end_turn()
	game.handoff.ready_button.pressed.emit()
	var theirs := _visible_text(game.report_panel)
	assert_false(theirs.contains("Your people have become"), "seat 2 reads the public text")
	assert_true(theirs.contains("The Aurel Crown has become the Celestial Host."), "seat 2 reads the public text")
	game.free()


func test_the_victory_screen_lists_each_factions_path() -> void:
	var s := AscensionRules.with_nodes(_paths(), CROWN, ["crown_drillyard", "crown_charters", "crown_oath_forge", "crown_living_iron"], 0)
	var screen := VictoryScreen.new()
	screen.show_victory({"winner": CROWN, "turn": 9, "turns_played": 9, "battles": 2, "provinces_held": {CROWN: 9, CLANS: 0},
		"captures": [], "text": "The Aurel Crown captured Fangridge."}, s, [CROWN, CLANS])
	assert_true(screen.paths_heading.visible and screen.paths_box.visible, "a paths game lists the paths")
	var crown := screen.paths_box.find_child("Path_kingdom", false, false) as Label
	assert_true(crown.text.begins_with("Aurel Crown: Drillyard (turn 0), Market Charters (turn 0), Oath of the Forge (turn 0), Living Iron (turn 0). Became Living Iron."), crown.text)
	var clans := screen.paths_box.find_child("Path_beasts", false, false) as Label
	assert_true(clans.text.ends_with("nothing researched. Swore no Oath."), clans.text)
	assert_eq(String(crown.get_meta(CodexLink.META)), "path")
	screen.show_victory({"winner": CROWN, "turn": 3, "provinces_held": {}}, GameState.new(), [CROWN, CLANS])
	assert_false(screen.paths_heading.visible, "no paths section without paths")
	screen.free()


func test_the_ruler_panel_names_the_people_and_the_battle_report_names_path_parts() -> void:
	var s := AscensionRules.with_nodes(_paths(), CLANS, ["beasts_boar_hide", "beasts_raiding", "beasts_oath_blood", "beasts_blood_pact"])
	var panel := RulerPanel.new()
	panel.show_for(s, CROWN)
	var heading := panel.columns.find_child("Column_beasts", false, false).find_child("FactionHeading", true, false) as Label
	assert_true(heading.text.ends_with("Thornmane Clans · Blood Pact"), heading.text)
	assert_eq(String(heading.get_meta(CodexLink.META)), "transformation")
	panel.free()
	assert_eq(BattleReportViewer._part_name("path_crown_arbalests"), "Arbalests")
	assert_eq(BattleReportViewer._part_name("path_crown_oath_forge"), "Deep Mines")
	assert_eq(BattleReportViewer._part_entry("path_crown_arbalests"), "node_crown_arbalests")
	assert_true(BattleReportViewer.MORALE_PART_NAMES.has("Dread Lands"))
