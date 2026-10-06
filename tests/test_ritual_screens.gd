extends "res://tests/test_case.gd"
## M5-6 (#117) on screen, headless (the in-game explanation every mechanic ships with): "Cast a ritual…" on an army of
## yours that holds a caster, the cast dialog's rituals, targets, payment, pack size and forecast (MagicRules'
## forecast_ritual, word for word), the cast order's line and tooltip in the orders list, the army panel's blessing and
## fading lines, the province panel's enchantments, and the turn report's rows (one line per ritual, the board beats
## folded in, the Rituals and Enchantments headings). Expected words come from MagicRules and RulesCodex.

const GAME_SCENE := "res://ui/game_screen.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"
## Ids that must never reach player-facing text.
const RAW_IDS := ["kingdom", "beasts", "bloodrot", "call_the_pack", "far_sight", "thornwolves", "tithe_of_blood", "_"]


## A magic game with the Clans as the Ninth Fang holding Tithe of Blood, Bloodrot and Call the Pack known, Shamans and
## Tuskers at Thornvale (two provinces from Crownkeep), 200 gold each.
func _state(fog: bool = false) -> GameState:
	var s := GameState.with_magic(9, {CROWN: "regents_court", CLANS: {"ruler": "fang_chieftain", "mandates": ["tithe_of_blood"]}})
	assert_true(s != null)
	s = AscensionRules.with_nodes(s, CLANS, ["bloodbolt", "bloodrot", "briar_snare", "call_the_pack"])
	if fog:
		s.setup_fog([])
	for f in s.factions:
		f.gold = 200
	var a := Army.new()
	a.id = s.new_army_id(CLANS)
	a.owner = CLANS
	a.location = "thornvale"
	for t in ["shamans", "tuskers", "tuskers", "tuskers"]:
		a.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(CLANS), t, s), CLANS))
	s.armies.append(a)
	s.find_province("thornvale").owner = CLANS
	return s


func _caster(s: GameState) -> String:
	for a in s.armies:
		if a.owner == CLANS and a.location == "thornvale":
			return a.id
	return ""


## The game screen at the Clans' orders (the Clans play seat 1).
func _screen(s: GameState) -> GameScreen:
	var session := GameSession.new(s, [CLANS, CROWN], 9, AutoBattleResolver.new())
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	assert_eq(game.load_game(SaveGame.make(session, {}, SaveGame.MANUAL, "Rituals", 0)), "")
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
	assert_eq(game.session.current_player(), CLANS)
	return game


func _texts(node: Node) -> String:
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
	for id in RAW_IDS:
		assert_false(text.contains(id), "%s shows the raw id '%s'" % [what, id])


func test_an_army_with_a_caster_offers_cast_a_ritual_and_the_dialog_forecasts_it() -> void:
	var s := _state()
	var game := _screen(s)
	var map := game.map
	var army_id := _caster(game.session.state())
	map.select_province("thornvale")
	var buttons := map.details.find_children("CastRitual", "Button", true, false)
	assert_eq(buttons.size(), 1, "one army there holds a caster")
	# The Clans' field army at Fangridge holds no caster: no button there.
	map.select_province("fangridge")
	var field_has := false
	for b in map.details.find_children("CastRitual", "Button", true, false):
		field_has = true
	assert_true(field_has, "the Ninth Fang casts Blood rituals, so the ruler's army offers it")
	map.open_cast_dialog(army_id)
	var dialog := map.cast_dialog
	assert_true(dialog.visible)
	var offered := dialog.options.map(func(o): return String(o.ritual))
	assert_eq(offered, ["call_the_pack", "bloodrot"], "the rituals of its schools; no Far Sight without fog")
	var rot: Dictionary = dialog.options[1]
	assert_true(bool(rot.ok), String(rot.reason))
	assert_true(rot.targets.has("crownkeep"), "the Crown's capital is in reach")
	assert_true(bool(rot.blood), "Tithe of Blood: a Shaman's army may pay in blood")
	dialog.select_ritual("bloodrot")
	dialog.select_target("crownkeep")
	var order := CastOrder.new("bloodrot", army_id, "crownkeep")
	var fc := MagicRules.forecast_ritual(game.session.state(), CLANS, order, [order])
	assert_eq(dialog.shown_forecast(), "\n".join(fc.lines), "the dialog shows the rules' forecast, word for word")
	_assert_no_raw_ids(_texts(dialog), "the cast dialog")
	dialog.set_pay(CastOrder.BLOOD)
	assert_true(dialog.shown_forecast().contains("Paid in blood"), dialog.shown_forecast())
	assert_true(dialog.shown_forecast().contains("Berserk"), "the Tuskers' side effect")
	dialog.confirm()
	assert_false(dialog.visible)
	var queued: Array = game.session.current_orders()
	assert_eq(queued.size(), 1)
	assert_true(queued[0] is CastOrder and queued[0].ritual == "bloodrot" and queued[0].pay == CastOrder.BLOOD)
	# The orders list: the M5-5 line, then what it will do; the hover has the whole forecast.
	var i := map.orders.orders().find(queued[0])
	var line := map.orders.order_text(i)
	assert_true(line.begins_with("Cast Bloodrot on Crownkeep from your army at Thornvale (paid in blood)."), line)
	assert_true(line.contains("No healing at Crownkeep"), "what it will do, in brief: %s" % line)
	assert_true(line.contains("through turn %d" % int(fc.effect.until_turn)), line)
	assert_true(String(map.orders.order_breakdown(i).description).contains("Paid in blood"), "the tooltip has the forecast")
	_assert_no_raw_ids(line, "the order line")
	game.free()


func test_a_caster_that_knows_no_ritual_offers_none() -> void:
	# The Ever-Regent casts rituals, but the Crown knows none yet and there is no fog (Far Sight is offered only under
	# fog): no button, so the panel never offers an empty dialog. The Magic tab says what to research.
	var s := _state()
	var session := GameSession.new(s, [CROWN, CLANS], 9, AutoBattleResolver.new())
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	assert_eq(game.load_game(SaveGame.make(session, {}, SaveGame.MANUAL, "Crown", 0)), "")
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
	assert_false(MagicRules.casters(game.session.state(), RulerRules.ruler_army(game.session.state(), CROWN)).is_empty(), "the Regent casts")
	game.map.select_province("crownkeep")
	assert_eq(game.map.details.find_children("CastRitual", "Button", true, false), [], "nothing to cast yet")
	game.free()


func test_the_gold_line_counts_queued_rituals_first() -> void:
	# Rituals are paid in the rituals phase, before recruits: the orders panel's gold and each recruit's "leaving" say so.
	var s := _state()
	var ctrl := OrdersController.new(s, CLANS)
	var gold := s.find_faction(CLANS).gold
	assert_eq(ctrl.queue_cast("bloodrot", _caster(s), "crownkeep"), "")
	assert_eq(ctrl.queue_recruit("tuskers"), "")
	var g := ctrl.gold_after_recruits()
	var rot := int(MagicRules.price(s, CLANS, "bloodrot").gold)
	var tusker := TurnResolver.recruit_cost(s, CLANS, "tuskers")
	assert_eq(int(g.rituals), rot)
	assert_eq(int(g.gold_after), gold - rot - tusker)
	var bd := ctrl.gold_breakdown()
	assert_eq(Breakdown.sum_of_lines(bd), int(bd.total), "the lines add up")
	assert_true(String(bd.description).contains("your queued rituals take %d first" % rot), bd.description)
	assert_true(ctrl.order_text(1).contains("leaving %d gold" % (gold - rot - tusker)), ctrl.order_text(1))
	# And the turn agrees.
	var r := TurnResolver.resolve(s, {CLANS: ctrl.orders()}, TurnResolver.seed_for_turn(s))
	var recruited: Dictionary = r.events.filter(func(e): return String(e.type) == "recruited")[0]
	assert_eq(int(recruited.numbers.gold_after), int(g.gold_after))


func test_call_the_pack_offers_its_sizes_and_far_sight_only_under_fog() -> void:
	var s := AscensionRules.with_nodes(_state(true), CLANS, ["wild_mastery"])
	var game := _screen(s)
	var army_id := _caster(game.session.state())
	game.map.open_cast_dialog(army_id, "call_the_pack")
	var dialog := game.map.cast_dialog
	assert_eq(dialog.ritual, "call_the_pack")
	assert_eq(dialog.size_buttons.keys(), [3, 4], "3 up to 3 + Wild mastery")
	dialog.set_wolves(4)
	assert_true(dialog.shown_forecast().contains("4 Thornwolves"), dialog.shown_forecast())
	assert_true(dialog.shown_forecast().contains("%d gold" % (4 * int(MagicData.SPELLS.call_the_pack.cost))), dialog.shown_forecast())
	assert_true(dialog.options.map(func(o): return String(o.ritual)).has("far_sight"), "Far Sight under fog")
	game.free()


func test_the_turn_report_has_one_line_per_ritual_and_the_magic_headings() -> void:
	var s := _state()
	var army_id := _caster(s)
	var order := CastOrder.new("bloodrot", army_id, "crownkeep", CastOrder.BLOOD)
	var r := TurnResolver.resolve(s, {CLANS: [order]}, TurnResolver.seed_for_turn(s))
	var rows := TurnReportText.rows(r.events, r.new_state, CLANS)
	var types: Array = rows.map(func(row): return String(row.event.type))
	assert_true(types.has("ritual_cast") and types.has("blood_paid") and types.has("curse_bit") and types.has("ritual_fell"))
	assert_false(types.has("enchantment_began"), "the ritual_cast line already says what began")
	for row in rows:
		_assert_no_raw_ids(String(row.text), "the report line %s" % row.event.type)
	assert_eq(TurnReportPanel.PHASE_TITLES.rituals, "Rituals")
	assert_eq(TurnReportPanel.PHASE_TITLES.enchantments, "Enchantments")
	# Every forecast number is in the report: the price, the hit points a turn, the last turn.
	var fc := MagicRules.forecast_ritual(s, CLANS, order, [order])
	var cast: Dictionary = r.events.filter(func(e): return String(e.type) == "ritual_cast")[0]
	assert_true(String(cast.text).contains("%d hit points in blood" % int(fc.effect.hp)), cast.text)
	assert_true(String(cast.text).contains("through turn %d" % int(fc.effect.until_turn)), cast.text)


func test_the_panels_show_blessings_fading_creatures_and_enchantments() -> void:
	var s := _state()
	var army_id := _caster(s)
	var second := Army.new()
	second.id = s.new_army_id(CLANS)
	second.owner = CLANS
	second.location = "thornvale"
	second.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(CLANS), "shamans", s), CLANS))
	s.armies.append(second)
	var r := TurnResolver.resolve(s, {CLANS: [CastOrder.new("bloodrot", second.id, "crownkeep"),
		CastOrder.new("call_the_pack", army_id, "thornvale", CastOrder.GOLD, 3)]}, TurnResolver.seed_for_turn(s))
	assert_true(r.new_state != null)
	var after: GameState = r.new_state
	# Hand the game to the Crown's view: Crownkeep shows the Clans' curse, with its end and effect.
	var session := GameSession.new(after, [CROWN, CLANS], 9, AutoBattleResolver.new())
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	assert_eq(game.load_game(SaveGame.make(session, {}, SaveGame.MANUAL, "Cursed", 0)), "")
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
	game.map.select_province("crownkeep")
	var curse := game.map.details.find_children("Enchantment_bloodrot", "Label", true, false)
	assert_eq(curse.size(), 1, "the curse is on the province panel")
	var label := curse[0] as Label
	var e: Dictionary = after.enchantments.filter(func(x): return String(x.ritual) == "bloodrot")[0]
	assert_true(label.text.contains("through turn %d" % int(e.until_turn)), label.text)
	assert_true(label.tooltip_text.contains("can't heal"), label.tooltip_text)
	_assert_no_raw_ids(label.text + label.tooltip_text, "the enchantment line")
	game.free()
	# The Clans' pack: the army panel says when the wolves fade.
	var clans := GameSession.new(after, [CLANS, CROWN], 9, AutoBattleResolver.new())
	var g2 := load(GAME_SCENE).instantiate() as GameScreen
	g2.autosave_enabled = false
	assert_eq(g2.load_game(SaveGame.make(clans, {}, SaveGame.MANUAL, "Pack", 0)), "")
	if g2.handoff.visible:
		g2.handoff.ready_button.pressed.emit()
	g2.map.select_province("thornvale")
	var fades := g2.map.details.find_children("FadesLine", "Label", true, false)
	assert_eq(fades.size(), 1)
	assert_true((fades[0] as Label).text.begins_with("Thornwolves fade at the end of turn"), (fades[0] as Label).text)
	g2.free()
