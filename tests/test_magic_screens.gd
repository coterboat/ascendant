extends "res://tests/test_case.gd"
## M5-5 (#116) on screen, headless in the M1 UI-test style: the research panel's Magic tab (the arcana as two school
## columns, mastery per school, the battle spellbook queuing a SpellbookOrder through the session), the orders list's
## lines for spellbook and cast orders, the mage's recruit tooltip naming the gate, and the build screen's Tithe of
## Blood row and ruler magic lines in a game with magic only. Expected words and numbers come from MagicRules,
## MagicView, AscensionRules and Breakdown, never hardcoded.

const GAME_SCENE := "res://ui/game_screen.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"
const SEED := 21
## Ids that must never reach player-facing text (display names are capitalised; "_" catches the rest).
const RAW_IDS := ["kingdom", "beasts", "sunlance", "shield_of_law", "briar_snare", "bloodbolt", "dawn_blessing",
	"sanctum_ward", "tithe_of_blood", "feast_of_victory", "ever_regent", "adepts", "shamans", "_"]


func _magic(builds: Dictionary = {}) -> GameState:
	var errors := []
	var s := GameState.with_magic(SEED, builds, errors)
	assert_eq(errors, [], "the magic game sets up")
	return s


## A hotseat magic game screen at seat 1's orders.
func _game() -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.start_game({"players": [CROWN, CLANS], "seed": SEED, "magic": true})
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
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


# --- the UI model ---------------------------------------------------------------------------------

func test_the_magic_view_reads_the_rules() -> void:
	var s := _magic({CROWN: "regents_court"})
	var cols := MagicView.columns(s, CROWN)
	assert_eq(cols.map(func(c): return c.school), MagicRules.schools(CROWN))
	for col in cols:
		assert_eq(col.cards.map(func(c): return c.node), MagicData.SCHOOLS[col.school].nodes, "four cards in data order")
		for c in col.cards:
			assert_eq(String(c.state), String(AscensionRules.node_state(s, CROWN, String(c.node)).state), "%s: the rules' state" % c.node)
			assert_eq(int(c.cost), AscensionRules.node_cost(String(c.node)))
			var delay := Forecast.arcana_delay(s, CROWN, String(c.node))  # M5-8: the hover says what it does to your transformation
			assert_eq(bool(delay.applies), String(c.detail).contains(String(delay.text)) and not String(delay.text).is_empty(), "%s: the delay line" % c.node)
		# Mastery: your mages, and the Ever-Regent in his own schools, each with a breakdown that sums.
		assert_eq(col.mastery.size(), 2, "%s: mages and the Ever-Regent" % col.school)
		for line in col.mastery:
			assert_eq(Breakdown.sum_of_lines(line.breakdown), int(line.breakdown.total))
		assert_eq(col.mastery[1].text, "The Ever-Regent %s" % MagicView._signed(int(MagicRules.mastery_bonus(s, CROWN, col.school, MagicRules.RULER).value)))
	# A spell card's hover gives its numbers with your casters now; a ritual's its price; a mastery node what changes.
	var lance := MagicView.card(s, CROWN, "sunlance")
	var mage_damage := int(MagicRules.spell_numbers("sunlance", int(MagicRules.mastery_bonus(s, CROWN, "sun").value)).value)
	assert_true(String(lance.detail).contains("your mages %d damage" % mage_damage), lance.detail)
	var blessing := MagicView.card(s, CROWN, "dawn_blessing")
	assert_true(String(blessing.detail).contains("for %d gold" % int(MagicRules.price(s, CROWN, "dawn_blessing").gold)), blessing.detail)
	var mastery := MagicView.card(s, CROWN, "sun_mastery")
	assert_true(String(mastery.detail).contains("Your mages: +0 → +1 in the Sun"), mastery.detail)
	_assert_no_raw_ids(" ".join(cols.map(func(c): return " ".join(c.cards.map(func(x): return "%s %s %s %s" % [x.name, x.effect, x.detail, x.state_line])))), "the arcana cards")


func test_the_spellbook_rows_moves_and_switches() -> void:
	var s := _magic({CROWN: "regents_court"})
	var rows := MagicView.spellbook_rows(s, CROWN)
	assert_eq(rows.map(func(r): return r.spell), MagicData.SPELLBOOK[CROWN], "the default order")
	var by := {}
	for r in rows:
		by[r.spell] = r
	assert_eq(by.sunlance.status, "The Ever-Regent: always known", "his own Sunlance, from turn 1")
	assert_eq(by.shield_of_law.status, "not researched (%d research)" % AscensionRules.node_cost("shield_of_law"))
	assert_true(rows[0].first and rows[-1].last)
	var book := MagicView.spellbook(s, CROWN)
	var moved := MagicView.moved(book, "sunlance", -1)
	assert_eq(moved.order, ["sunlance", "sunburst", "shield_of_law"])
	assert_eq(MagicView.moved(moved, "sunlance", -1), moved, "nothing moves past the top")
	var off := MagicView.toggled(moved, "sunburst", false)
	assert_eq(off.off, ["sunburst"])
	assert_eq(MagicView.toggled(off, "sunburst", true).off, [])
	# Every change is a legal SpellbookOrder, and a queued one is what the rows show.
	assert_eq(MagicRules.check_spellbook(s, CROWN, SpellbookOrder.new(off.order, off.off)), {})
	var queued := MagicView.spellbook_rows(s, CROWN, [SpellbookOrder.new(off.order, off.off)])
	assert_eq(queued.map(func(r): return [r.spell, r.on]), [["sunlance", true], ["sunburst", false], ["shield_of_law", true]])
	var corvane := _magic({CROWN: "warrior_king"})
	assert_eq(MagicView.spellbook_rows(corvane, CROWN)[1].status, "not researched (%d research)" % AscensionRules.node_cost("sunlance"),
		"King Corvane knows no Sunlance")
	assert_true(MagicView.casters_text(corvane, CROWN).contains("casts nothing"), MagicView.casters_text(corvane, CROWN))


# --- the research panel's Magic tab ----------------------------------------------------------------

func test_the_magic_tab_shows_only_in_a_magic_game() -> void:
	var paths := GameState.with_paths(SEED)
	var panel := ResearchPanel.new()
	panel.show_for(paths, CROWN)
	assert_false(panel.magic_tab.visible, "no Magic tab without magic")
	panel.show_magic()
	assert_false(panel.showing_magic)
	assert_eq(panel.cards.keys().filter(func(n): return AscensionRules.is_arcana(String(n))), [], "no arcana card")
	panel.free()
	var s := _magic()
	var mp := ResearchPanel.new()
	mp.show_for(s, CLANS)
	assert_true(mp.magic_tab.visible)
	mp.show_magic()
	assert_true(mp.showing_magic)
	assert_eq(mp.cards.keys(), MagicRules.arcana_ids(CLANS), "the Clans' eight arcana cards")
	assert_eq(mp.spellbook_checks.keys(), MagicData.SPELLBOOK[CLANS], "a row per battle spell")
	assert_true(mp.buttons.has("briar_snare") and mp.buttons.has("bloodbolt"), "tier I spells can be researched")
	assert_false(mp.buttons.has("call_the_pack"), "a ritual that needs its spell first has no button")
	var heard := []
	mp.research_requested.connect(func(nid): heard.append(nid))
	(mp.buttons["briar_snare"] as Button).pressed.emit()
	assert_eq(heard, ["briar_snare"])
	var books := []
	mp.spellbook_requested.connect(func(order, off): books.append([order, off]))
	(mp.spellbook_checks["bloodbolt"] as CheckBox).toggled.emit(false)
	assert_eq(books, [[MagicData.SPELLBOOK[CLANS], ["bloodbolt"]]])
	var text := _texts(mp)
	assert_true(text.contains(MagicView.PREVIEW_NOTE), "the tab says what this build of the preview does")
	assert_true(text.contains(MagicRules.mage_gate_reason(s, CLANS, MagicRules.mage_type(CLANS)).get_slice(".", 0)) or text.contains("recruitable once you know a spell"),
		"the mage gate is named")
	_assert_no_raw_ids(text, "the Magic tab")
	mp.show_own()
	assert_false(mp.showing_magic, "back to the path")
	assert_false(mp.cards.keys().any(func(n): return AscensionRules.is_arcana(String(n))))
	mp.free()


func test_research_a_spell_and_set_the_spellbook_through_the_game_screen() -> void:
	var game := _game()
	var hud := game.research_hud
	hud.open_panel()
	assert_true(hud.panel.magic_tab.visible)
	hud.panel.show_magic()
	(hud.panel.buttons["sunlance"] as Button).pressed.emit()
	var orders := game.session.current_orders()
	assert_eq(orders.filter(func(o): return o is ResearchOrder).map(func(o): return o.node_id), ["sunlance"], "research queued through the session")
	assert_true(hud.panel.showing_magic, "the tab stays open")
	(hud.panel.spellbook_checks["sunburst"] as CheckBox).toggled.emit(false)
	orders = game.session.current_orders()
	var books := orders.filter(func(o): return o is SpellbookOrder)
	assert_eq(books.size(), 1)
	assert_eq(books[0].off, ["sunburst"])
	assert_true(String(hud.panel.status_label.text).begins_with("Battle spellbook set: "), hud.panel.status_label.text)
	# Again: a new spellbook order replaces the first (one per turn).
	(hud.panel.spellbook_checks["sunburst"] as CheckBox).toggled.emit(true)
	assert_eq(game.session.current_orders().filter(func(o): return o is SpellbookOrder).size(), 1)
	# The orders list reads it, links its codex entry, and its breakdown sums.
	var ctrl := game.map.orders
	var i := ctrl.orders().find(ctrl.orders().filter(func(o): return o is SpellbookOrder)[0])
	assert_true(ctrl.order_text(i).begins_with("Battle spellbook: Sunburst, Sunlance and Shield of Law."), ctrl.order_text(i))
	assert_eq(ctrl.order_codex_kind(i), "spellbook_order")
	assert_eq(TooltipText.CODEX.spellbook_order, "spellbook")
	var bd := ctrl.order_breakdown(i)
	assert_eq(Breakdown.sum_of_lines(bd), int(bd.total))
	game.free()


func test_order_lines_for_casts_and_the_mage_recruit_tooltip() -> void:
	var s := AscensionRules.with_nodes(_magic(), CLANS, ["bloodbolt", "bloodrot"])
	var army: Army = null
	for a in s.armies:
		if a.owner == CLANS and a.ruler != null:
			army = a
	var d := MagicRules.distances(s, army.location)
	var target := ""
	for pid in d:
		if int(d[pid]) == 2 and target.is_empty():
			target = pid
	var cast := CastOrder.new("bloodrot", army.id, target)
	var ctrl := OrdersController.new(s, CLANS)
	assert_eq(ctrl._queue(cast), "", "a standalone controller queues it in its own book")
	var i := ctrl.orders().find(cast)
	assert_true(i >= 0, "the cast is queued")
	var line := ctrl.order_text(i)
	assert_true(line.begins_with("Cast Bloodrot on %s from your army at %s (%d gold)." % [s.find_province(target).name,
		s.find_province(army.location).name, int(MagicRules.price(s, CLANS, "bloodrot").gold)]), line)
	assert_eq(ctrl.order_codex_kind(i), "cast_order")
	var bd := ctrl.order_breakdown(i)
	assert_eq(int(bd.total), int(MagicRules.price(s, CLANS, "bloodrot").gold))
	assert_eq(Breakdown.sum_of_lines(bd), int(bd.total))
	# The mage's recruit tooltip names the gate while no spell is known, and not once one is.
	var fresh := OrdersController.new(_magic(), CROWN)
	var mage_id := String(MagicData.MAGES[CROWN].id)
	var gate := MagicRules.mage_gate_reason(fresh.state, CROWN, MagicRules.mage_type(CROWN))
	assert_true(String(fresh.recruit_breakdown(mage_id).description).begins_with(gate))
	# M5-7: mages cast in battle now, and the card says what the Mage trait does (no longer "fights as a soldier").
	assert_true(String(fresh.recruit_breakdown(mage_id).description).contains(AutoBattleResolver.TRAIT_TEXT[AutoBattleResolver.MAGE]), "the mage card says it casts")
	assert_false(String(fresh.recruit_breakdown(mage_id).description).contains("ordinary soldiers"), "and no longer that it fights as a soldier")
	var learned := OrdersController.new(AscensionRules.with_nodes(_magic(), CROWN, ["sunlance"]), CROWN)
	assert_false(String(learned.recruit_breakdown(mage_id).description).contains(gate))


# --- the build screen ------------------------------------------------------------------------------

func _builder(config: Dictionary) -> BuildScreen:
	var b := load(BuildScreen.SCENE).instantiate() as BuildScreen
	b.begin(config)
	if b.step == BuildScreen.Step.HANDOFF:
		b.acknowledge()
	assert_eq(b.step, BuildScreen.Step.BUILDING, "building")
	return b


func test_the_build_screen_offers_tithe_of_blood_only_with_magic() -> void:
	var plain := _builder({"players": [CLANS, CROWN], "seed": SEED, "ai": {CROWN: "normal"}})
	assert_false(plain.mandate_checks.has(MagicRules.TITHE_OF_BLOOD), "no Tithe of Blood without magic")
	for rid in plain.ruler_buttons:
		assert_false((plain._card_labels[rid].magic as Label).visible, "no magic line without magic")
	plain.free()
	var b := _builder({"players": [CLANS, CROWN], "seed": SEED, "ai": {CROWN: "normal"}, "magic": true})
	assert_true(b.mandate_checks.has(MagicRules.TITHE_OF_BLOOD), "the Clans may take Tithe of Blood in a magic game")
	for rid in b.ruler_buttons:
		var l: Label = b._card_labels[rid].magic
		assert_true(l.visible)
		assert_eq(l.text, MagicRules.ruler_line(rid, b._kept()), "%s: the magic line at this kept power" % rid)
	# Feast of Victory and Tithe of Blood exclude each other on the build screen, with the reason.
	b.clear_build()
	assert_true(b.set_mandate(RulerRules.FEAST_OF_VICTORY, true))
	assert_true((b.mandate_checks[MagicRules.TITHE_OF_BLOOD] as CheckBox).disabled)
	var reason: Label = b.mandate_reasons[MagicRules.TITHE_OF_BLOOD]
	assert_eq(reason.text, "Not with %s" % RulerRules.mandate_name(RulerRules.FEAST_OF_VICTORY))
	assert_true(String(reason.tooltip_text).replace("\n", " ").contains("blood given is not taken back"), reason.tooltip_text)
	assert_false(b.set_mandate(MagicRules.TITHE_OF_BLOOD, true), "the screen refuses the pair")
	b.clear_build()
	assert_true(b.set_mandate(MagicRules.TITHE_OF_BLOOD, true))
	assert_true((b.mandate_checks[RulerRules.FEAST_OF_VICTORY] as CheckBox).disabled, "either way round")
	# Locked in, the game starts with it.
	var done := []
	b.finished.connect(func(cfg): done.append(cfg))
	assert_true(b.lock_in())
	assert_eq(done.size(), 1)
	var s := GameScreen.starting_state(done[0])
	assert_true(s != null and s.magic, "a magic game")
	assert_true(s.find_faction(CLANS).mandates.has(MagicRules.TITHE_OF_BLOOD))
	b.free()
	var crown := _builder({"players": [CROWN, CLANS], "seed": SEED, "ai": {CLANS: "normal"}, "magic": true})
	assert_false(crown.mandate_checks.has(MagicRules.TITHE_OF_BLOOD), "Tithe of Blood is the Clans' alone")
	crown.free()
