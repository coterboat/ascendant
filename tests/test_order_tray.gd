extends "res://tests/test_case.gd"
## UX-4 (#213; design/UX_WAR_TABLE.md §3.4): orders on the board, numbered, and the tray. What each test pins:
##   the numbering: the placed orders (march, recruit, fortify, storm or siege, ritual, and ARM-1's musters) are numbered by their place
##     among the placed orders as orders() lists them; the realm orders (research, spellbook, mandate) are not, and show as icon tokens
##     after them; a number is no id, so it re-flows when an order is cancelled and when change_via sends a road move to the end;
##   for every class of order: add, replace (the realm orders, in place), cancel and change-via, with the numbers and the tray's tokens
##     checked after each (the pure marks, the tray, the 2D map's and the 3D board's tokens);
##   the tray: hover shows the order's sentence and breakdown and explains the numbering, gold after ends it, past seven tokens it
##     scrolls sideways, below 1600 logical a token keeps its number or icon and the words go to the tooltip;
##   a token's click focuses its place and opens its card (with Change and Cancel), its cross or a right-click cancels, and none of it
##     gives the army a second-click move;
##   OrderSpots: where a token may stand (a free spot, the number alone when there is none, never under the Table).
## The live half, real mouse events at the tokens in a running game, and the numbers' clearance from the plates at the three sizes, is
## tests/tray_probe.gd, run by test_the_live_tray_takes_real_clicks_and_keeps_clear_of_the_plates below.
## Numbers and words come from the data and the rules, never from this file.

const Kit := preload("res://tests/muster_test_kit.gd")
const FortTest := preload("res://tests/test_fort_panel.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const GAME_SCENE := "res://ui/game_screen.tscn"
const MAP_SCENE := "res://ui/map_screen.tscn"
const BOARD_SIZE := Vector2(1200, 836)
const PROBE := "res://tests/tray_probe.gd"
const SCRATCH := "user://tray_probe"


# --- fixtures -------------------------------------------------------------------------------------

## The Clans' game with every system: magic (a caster in an army at Thornvale who knows Bloodrot), forts, plenty of gold, and a second
## army at Fangridge with three units to split.
func _world() -> GameState:
	var s := GameState.with_magic(9, {CROWN: "regents_court", CLANS: {"ruler": "fang_chieftain", "mandates": ["tithe_of_blood"]}})
	s.setup_sieges()
	s = AscensionRules.with_nodes(s, CLANS, ["bloodbolt", "bloodrot", "briar_snare", "call_the_pack"])
	for f in s.factions:
		f.gold = 500
	var caster := Kit.army(s, CLANS, "thornvale", ["shamans", "tuskers", "tuskers", "tuskers"])
	Kit.army(s, CLANS, "fangridge", ["tuskers", "tuskers", "tuskers"])
	s.find_province("thornvale").owner = CLANS
	assert_true(caster != null)
	return s


func _caster(s: GameState) -> String:
	for a in s.armies:
		if a.owner == CLANS and a.location == "thornvale":
			return a.id
	return ""


## The second army at Fangridge (the one to split and to march).
func _spare(s: GameState) -> String:
	for a in s.armies:
		if a.owner == CLANS and a.location == "fangridge" and a.ruler == null:
			return a.id
	return ""


func _first_research(s: GameState, skip: String = "") -> String:
	for n in PathData.PATHS[CLANS].nodes:
		if String(n.id) != skip and AscensionRules.check_research(s, CLANS, String(n.id)).is_empty():
			return String(n.id)
	return ""


## What each class of order does to a controller: [class, add(c, s) -> reason]. The realm classes go through the book (as the research and
## magic panels do, through the session), the mandate through queue_sacrifice.
func _adders(s: GameState) -> Dictionary:
	var spare := _spare(s)
	var east: String = s.find_province("fangridge").neighbors[0]
	return {
		"march": func(c: OrdersController): return c.queue_move(spare, east),
		"recruit": func(c: OrdersController): return c.queue_recruit("tuskers"),
		"fortify": func(c: OrdersController): return c.queue_fortify("thornvale"),
		"ritual": func(c: OrdersController): return c.queue_cast("bloodrot", _caster(s), "crownkeep"),
		"muster": func(c: OrdersController): return c.queue_muster(MusterOrder.transfer(spare, "", [0])),
		"research": func(c: OrdersController): return c.book.submit(s, CLANS, ResearchOrder.new(_first_research(s))),
		"spellbook": func(c: OrdersController): return c.book.submit(s, CLANS, SpellbookOrder.new(MagicRules.spellbook(s, CLANS).order, [])),
		"mandate": func(c: OrdersController): return c.queue_sacrifice(_a_mandate(s)),
	}


func _a_mandate(s: GameState) -> String:
	for o in Forecast.sacrifice_options(s, CLANS, []):
		if bool(o.ok):
			return String(o.mandate)
	return ""


func _tray(c: OrdersController) -> OrderTray:
	var tray := OrderTray.new()
	tray.refresh(c)
	return tray


## The tray's tokens as [number text or "" for a realm token, class].
func _shape(tray: OrderTray) -> Array:
	return tray.tokens().map(func(t): return [(t as OrderToken).chip.text if (t as OrderToken).chip != null else "", String((t as OrderToken).mark["class"])])


# --- numbering ------------------------------------------------------------------------------------

func test_the_placed_orders_are_numbered_and_the_realm_orders_are_not() -> void:
	var placed := [MoveOrder.new("a", "b"), RecruitOrder.new("spearmen"), FortifyOrder.new("p"), SiegeOrder.storm("p"), SiegeOrder.sally("a"),
		CastOrder.new("bloodrot", "a", "p"), MusterOrder.merge("a", "b"), MusterOrder.swap("a", "b"), MusterOrder.transfer("a", "", [0])]
	var realm := [ResearchOrder.new("n"), SpellbookOrder.new([]), SacrificeOrder.new("m")]
	for o in placed:
		assert_true(OrdersController.is_placed(o), "%s is a placed order" % o.describe())
	for o in realm:
		assert_false(OrdersController.is_placed(o), "%s is a realm order" % o.describe())
	var list := [realm[0], placed[0], realm[1], placed[1], realm[2], placed[2]]
	assert_eq(OrdersController.placed_in(list), [1, 3, 5], "the placed orders, by their index in the list")
	assert_eq(OrdersController.realm_in(list), [0, 2, 4], "and the realm orders")
	assert_eq(OrderMarks.class_of(placed[3]), "siege", "a storm and a sally are the siege class")
	assert_eq(OrderMarks.class_of(placed[4]), "siege")
	assert_eq(OrderMarks.CLASS_ICON.keys().size(), 9, "nine classes, each with its icon")
	for cls in OrderMarks.CLASS_ICON:
		assert_true(UiIcons.NAMES.has(OrderMarks.CLASS_ICON[cls]), "%s's icon %s exists in UiIcons" % [cls, OrderMarks.CLASS_ICON[cls]])
	assert_eq(OrderMarks.CLASS_ICON["muster"], "muster", "a muster has its own icon")
	assert_eq(OrderMarks.CLASS_ICON["fortify"], "walls", "a fortify wears the walls icon, a storm or siege the siege icon")
	assert_eq(OrderMarks.CLASS_ICON["siege"], "siege")


func test_a_number_is_a_place_in_the_list_and_reflows() -> void:
	var s := _world()
	var c := OrdersController.new(s, CLANS)
	var add := _adders(s)
	assert_eq(add["recruit"].call(c), "")
	assert_eq(add["march"].call(c), "")
	assert_eq(add["research"].call(c), "")
	assert_eq(add["recruit"].call(c), "")
	assert_eq([c.number_of(0), c.number_of(1), c.number_of(2), c.number_of(3)], [1, 2, 0, 3], "the research between them has no number, and takes none")
	assert_eq([c.index_of_number(1), c.index_of_number(2), c.index_of_number(3), c.index_of_number(4), c.index_of_number(0)], [0, 1, 3, -1, -1])
	assert_eq(c.placed_count(), 3)
	assert_eq(c.placed_indices(), [0, 1, 3])
	assert_eq(c.realm_indices(), [2])
	assert_eq(c.cancel(0), "")  # the first recruit: everything after it moves up
	assert_eq([c.number_of(0), c.number_of(1), c.number_of(2)], [1, 0, 2], "cancelling renumbers: the march is 1, the other recruit 2")
	assert_eq(c.number_of(9), 0, "an index that is no order has no number")


func test_the_marks_say_where_each_order_stands_and_in_what_words() -> void:
	var s := _world()
	var c := OrdersController.new(s, CLANS)
	var add := _adders(s)
	for cls in ["march", "recruit", "fortify", "ritual", "muster"]:
		assert_eq(add[cls].call(c), "", "%s is accepted" % cls)
	var marks := OrderMarks.marks(c)
	assert_eq(marks.map(func(m): return m["class"]), ["march", "recruit", "fortify", "ritual", "muster"])
	assert_eq(marks.map(func(m): return m.number), [1, 2, 3, 4, 5])
	assert_eq(marks.map(func(m): return m.place), ["fangridge", s.find_faction(CLANS).capital, "thornvale", "crownkeep", "fangridge"],
		"a march starts where its army is, a recruit is made at the capital, a fortify is at its province, a ritual at its target, a muster where it happens")
	assert_eq(marks[0].to, s.find_province("fangridge").neighbors[0], "a march knows its destination")
	assert_eq(marks[1].label, TurnResolver.recruitable_type(s.find_faction(CLANS), "tuskers", s).name, "the tray's words for a recruit are the unit's name")
	assert_eq(marks[1].board, "+1 unit", "and the board's are its count")
	assert_eq(marks[2].board, SiegeRules.level_name(1), "a fortify's board words name the walls it raises")
	assert_eq(marks[3].label, MagicRules.spell_name("bloodrot"))
	assert_eq(marks[4].label, "Split", "a split is a split")
	assert_eq(marks[0].board, "", "a march's board token is its number alone")
	for m in marks:
		assert_true(UiIcons.NAMES.has(m.icon), "%s has an icon that exists" % m["class"])
		assert_false(String(m.label).is_empty() or String(m.label).length() > OrderMarks.LABEL_MAX, "%s: a short label (%s)" % [m["class"], m.label])
		assert_true(s.find_province(String(m.place)) != null, "%s has a place on the map" % m["class"])


func test_recruits_at_one_place_are_one_board_token_and_the_others_each_their_own() -> void:
	var s := _world()
	var c := OrdersController.new(s, CLANS)
	var add := _adders(s)
	assert_eq(add["recruit"].call(c), "")  # 1
	assert_eq(add["march"].call(c), "")  # 2
	assert_eq(add["recruit"].call(c), "")  # 3
	assert_eq(add["research"].call(c), "")
	var board := OrderMarks.board_marks(OrderMarks.marks(c))
	assert_eq(board.size(), 2, "the two recruits at the capital are one token; the realm order is not on the board; the march is its own")
	var recruits: Dictionary = board.filter(func(m): return m["class"] == "recruit")[0]
	assert_eq(recruits.numbers, [1, 3], "its numbers are both recruits'")
	assert_eq(recruits.units, 2)
	assert_eq(recruits.board, "+%s" % TooltipText.count(2, "unit"), "+2 units")
	assert_eq(OrderMarks.numbers_text([1, 3]), "1, 3")
	assert_eq(OrderMarks.numbers_text([4, 5, 6]), "4-6")
	assert_eq(OrderMarks.numbers_text([2]), "2")
	assert_eq(OrderMarks.numbers_text([1, 2, 4]), "1, 2, 4")


# --- every class: add, replace, cancel ------------------------------------------------------------------

func test_every_placed_class_adds_numbers_and_cancels_with_its_token() -> void:
	var s := _world()
	var add := _adders(s)
	for cls in ["march", "recruit", "fortify", "ritual", "muster"]:
		var c := OrdersController.new(s, CLANS)
		var tray := _tray(c)
		assert_eq(tray.tokens().size(), 0, "%s: an empty tray to begin with" % cls)
		assert_false(tray.scroll.visible, "%s: and no strip" % cls)
		# add
		assert_eq(add[cls].call(c), "", "%s is accepted" % cls)
		tray.refresh(c)
		assert_eq(_shape(tray), [["1", cls]], "%s: add: one numbered token, number 1" % cls)
		assert_true(c.number_of(0) == 1 and OrderMarks.mark_at(c, 0)["class"] == cls, "%s: and the controller agrees" % cls)
		assert_true(tray.tokens()[0].get_tooltip(Vector2.ZERO).contains("1 · %s" % OrderMarks.CLASS_NAME[cls]), "%s: its tooltip names it: %s" % [cls, tray.tokens()[0].get_tooltip(Vector2.ZERO).left(40)])
		# a second placed order, after it
		assert_eq(add["recruit"].call(c), "", "a recruit after it")
		tray.refresh(c)
		assert_eq(_shape(tray).map(func(x): return x[0]), ["1", "2"], "%s: the recruit is number 2" % cls)
		assert_eq(OrderMarks.board_marks(OrderMarks.marks(c)).map(func(m): return m.numbers), [[1], [2]] if cls != "recruit" else [[1, 2]],
			"%s: on the board the numbers are the same (a recruit folds with a recruit)" % cls)
		# cancel the first: the recruit moves up
		assert_eq(c.cancel(0), "", "%s: cancel" % cls)
		tray.refresh(c)
		assert_eq(_shape(tray), [["1", "recruit"]], "%s: cancel: the recruit is number 1 now" % cls)
		assert_eq(c.number_of(0), 1)
		tray.free()


func test_a_realm_order_is_an_icon_token_after_the_numbered_ones_and_is_replaced_in_place() -> void:
	var s := _world()
	var add := _adders(s)
	for cls in ["research", "spellbook", "mandate"]:
		var c := OrdersController.new(s, CLANS)
		var tray := _tray(c)
		assert_eq(add[cls].call(c), "", "%s is accepted" % cls)
		assert_eq(add["recruit"].call(c), "")
		tray.refresh(c)
		assert_eq(_shape(tray), [["1", "recruit"], ["", cls]], "%s: the numbered recruit first, then the realm token with no number" % cls)
		var token: OrderToken = tray.tokens()[1]
		assert_true(bool(token.mark.realm) and token.chip == null, "%s: an icon token, no number chip" % cls)
		var realm_index: int = c.realm_indices()[0]
		assert_true(token.get_tooltip(Vector2.ZERO).contains("a realm order") and token.get_tooltip(Vector2.ZERO).replace("\n", " ").contains(OrderMarks.REALM_NOTE.left(30)), "%s: and its tooltip says so" % cls)
		assert_eq(c.number_of(realm_index), 0, "%s: it has no number" % cls)
		assert_true(OrderMarks.board_marks(OrderMarks.marks(c)).all(func(m): return m["class"] != cls), "%s: a realm order is not on the board" % cls)
		# replace: research and the spellbook are replaced in place, a second mandate is refused (one a turn)
		if cls == "research":
			var again := _first_research(s, String(c.orders()[0].node_id))
			assert_ne(again, "", "there is a second node to pick")
			assert_eq(c.book.submit(s, CLANS, ResearchOrder.new(again)), "", "a new research pick replaces the old")
			tray.refresh(c)
			assert_eq(_shape(tray), [["1", "recruit"], ["", "research"]], "research: still one realm token, in the same place")
			assert_eq(tray.tokens()[1].label.text, OrderMarks._cut(AscensionRules.node_name(again)), "research: with the new pick's words")
		elif cls == "spellbook":
			var book := MagicRules.spellbook(s, CLANS)
			assert_eq(c.book.submit(s, CLANS, SpellbookOrder.new(book.order, [String(book.order[0])])), "", "a new spellbook replaces the old")
			tray.refresh(c)
			assert_eq(_shape(tray), [["1", "recruit"], ["", "spellbook"]], "spellbook: still one realm token, in the same place")
			assert_eq(c.orders().filter(func(o): return o is SpellbookOrder).size(), 1)
		else:
			assert_false(add["mandate"].call(c).is_empty(), "mandate: a second sacrifice is refused (one per turn)")
			tray.refresh(c)
			assert_eq(_shape(tray), [["1", "recruit"], ["", "mandate"]], "mandate: the one token stays")
		# cancel the realm order: the numbered one is untouched
		assert_eq(c.cancel(c.realm_indices()[0]), "", "%s: cancel" % cls)
		tray.refresh(c)
		assert_eq(_shape(tray), [["1", "recruit"]], "%s: cancel: only the numbered token is left, still number 1" % cls)
		tray.free()


func test_a_storm_and_a_sally_are_numbered_siege_orders_with_their_tokens() -> void:
	var s := FortTest.besieged_keep()
	var clans := OrdersController.new(s, CLANS)
	var tray := _tray(clans)
	assert_eq(clans.queue_recruit("tuskers"), "")
	assert_eq(clans.set_storm("stonegate", true), "", "the besiegers storm the keep")
	tray.refresh(clans)
	assert_eq(_shape(tray), [["1", "recruit"], ["2", "siege"]], "the storm is number 2, a siege token")
	var storm := OrderMarks.mark_at(clans, 1)
	assert_eq([storm.place, storm.board, storm.icon], ["stonegate", "Storm", "siege"], "at the fort, with the siege icon")
	assert_eq(clans.cancel(1), "")
	tray.refresh(clans)
	assert_eq(_shape(tray), [["1", "recruit"]], "cancelled: gone, the recruit is still 1")
	tray.free()
	var crown := OrdersController.new(s, CROWN)
	var tray2 := _tray(crown)
	assert_eq(crown.set_sally("kingdom-3", true), "", "the garrison sallies")
	assert_eq(crown.queue_move("kingdom-7", "stonegate"), "", "the relief marches in")
	tray2.refresh(crown)
	var kinds := _shape(tray2).map(func(x): return x[1])
	assert_true(kinds.has("siege") and kinds.has("march"), "a sally and a march: %s" % [kinds])
	var sally: Dictionary = OrderMarks.marks(crown).filter(func(m): return m["class"] == "siege")[0]
	assert_eq([sally.place, sally.board], ["stonegate", "Sally"], "a sally stands at the fort it comes out of")
	assert_true(sally.number >= 1, "and is numbered")
	for t in tray2.tokens():
		assert_false(String(t.get_tooltip(Vector2.ZERO)).is_empty(), "every token has a tooltip")
	tray2.free()


func test_change_via_sends_a_road_move_to_the_end_and_the_numbers_follow() -> void:
	var s := GameState.with_rulers(7, {CROWN: "regents_court"})
	s.find_army("kingdom-1").location = "thornvale"
	for pid in ["thornvale", "stonegate", "wildmoor", "blackwood"]:
		s.find_province(pid).owner = CROWN
	var c := OrdersController.new(s, CROWN)
	var tray := _tray(c)
	assert_eq(c.queue_move("kingdom-1", "blackwood"), "", "a road move")
	assert_eq(c.queue_recruit(String(c.recruitable_types()[0].id)), "")
	assert_eq(c.queue_recruit(String(c.recruitable_types()[0].id)), "")
	tray.refresh(c)
	assert_eq(_shape(tray), [["1", "march"], ["2", "recruit"], ["3", "recruit"]], "the road move is number 1")
	var via: String = c.orders()[0].via
	assert_eq(c.change_via(0), "", "send it the other way")
	tray.refresh(c)
	assert_ne(c.orders()[2].via, via, "the other way through")
	assert_eq(_shape(tray), [["1", "recruit"], ["2", "recruit"], ["3", "march"]], "it went to the end: the recruits move up and the march is number 3")
	assert_eq(c.number_of(2), 3)
	assert_eq(OrderMarks.mark_at(c, 2).via, c.orders()[2].via, "and its mark follows the new way")
	assert_true(tray.tokens()[2].get_tooltip(Vector2.ZERO).contains("3 · March"), "its tooltip carries the new number")
	assert_true(tray.tokens()[2].get_tooltip(Vector2.ZERO).replace("\n", " ").contains(OrderMarks.RENUMBER_NOTE.left(60)), "and the note that says why numbers move")
	tray.free()


func test_every_class_has_a_board_mark_on_the_2d_map_with_its_number_and_the_tray_in_step() -> void:
	var s := _world()
	var map: MapScreen = load(MAP_SCENE).instantiate()
	map.set_state(s, CLANS)
	var add := _adders(s)
	var spare := _spare(s)
	var east: String = s.find_province("fangridge").neighbors[0]
	var before := map.order_marks_2d.tokens().size()
	assert_eq(before, 0, "no orders: no marks")
	assert_eq(map.queue_move(spare, east), "")
	assert_eq(map.queue_recruit("tuskers"), "")
	assert_eq(map.queue_fortify("thornvale"), "")
	assert_eq(map.queue_cast("bloodrot", _caster(s), "crownkeep"), "")
	assert_eq(map.queue_muster(MusterOrder.transfer(spare, "", [0])), "")
	assert_true(add["research"].call(map.orders) == "", "a research pick")
	map._orders_changed()
	var marks := map.order_marks_2d.tokens()
	assert_eq(marks.map(func(t): return t.chip.text), ["1", "2", "3", "4", "5"], "five marks on the 2D map, numbered like the tray")
	assert_eq(marks.map(func(t): return t.mark["class"]), ["march", "recruit", "fortify", "ritual", "muster"])
	assert_eq(map.table().tray_slot().tokens().size(), 6, "the tray holds those and the realm token")
	map.cancel_order(1)  # the recruit
	assert_eq(map.order_marks_2d.tokens().map(func(t): return t.chip.text), ["1", "2", "3", "4"], "the board's numbers re-flow with the tray's")
	assert_eq(map.table().tray_slot().tokens().map(func(t): return t.chip.text if t.chip != null else ""), ["1", "2", "3", "4", ""])
	map.free()


# --- the tray -------------------------------------------------------------------------------------

func test_hover_shows_the_sentence_and_the_breakdown_and_the_tray_explains_the_numbers() -> void:
	var s := _world()
	var c := OrdersController.new(s, CLANS)
	var add := _adders(s)
	assert_eq(add["march"].call(c), "")
	assert_eq(add["recruit"].call(c), "")
	var tray := _tray(c)
	for i in 2:
		var tip: String = tray.tokens()[i].get_tooltip(Vector2.ZERO)
		assert_true(tip.replace("\n", " ").contains(TooltipText.wrap_text(c.order_text(i)).replace("\n", " ")), "token %d's tooltip has order_text: %s" % [i + 1, tip])
		assert_true(tip.contains(TooltipText.from_breakdown(c.order_breakdown(i)).split("\n")[0]), "and the breakdown's title")
		assert_true(tip.replace("\n", " ").contains("numbers are places in this list"), "and why the numbers move")
	var hud := TableHud.new()
	assert_true(hud.tray.tooltip_text.replace("\n", " ").contains("numbers are places in this list"), "the tray's own tooltip explains the re-numbering")
	hud.free()
	tray.free()


func test_gold_after_ends_the_tray_while_an_order_is_paid_from_gold() -> void:
	var s := _world()
	var c := OrdersController.new(s, CLANS)
	var add := _adders(s)
	assert_eq(add["march"].call(c), "")
	var tray := _tray(c)
	assert_false(tray.gold_box.visible, "a march costs nothing: no gold line")
	assert_eq(add["recruit"].call(c), "")
	tray.refresh(c)
	assert_true(tray.gold_box.visible, "a recruit is paid from gold")
	assert_eq(tray.gold_box.get_index(), tray.get_child_count() - 1, "the gold line ends the tray")
	var after: int = int(c.gold_after_recruits().gold_after)
	assert_eq(tray.gold_label.text, "%d left" % after, "it is Forecast's own number")
	assert_true(tray.gold_box.tooltip_text.begins_with(TooltipText.from_breakdown(c.gold_breakdown())), "with its breakdown")
	assert_eq(CodexLink.key_at(tray.gold_box), TooltipText.codex_for("gold_after_recruits"), "and its codex link")
	tray.set_compact(true)
	assert_eq(tray.gold_label.text, str(after), "compact: the number")
	tray.free()


func test_past_seven_tokens_the_tray_scrolls_sideways() -> void:
	var s := _world()
	var c := OrdersController.new(s, CLANS)
	var tray := _tray(c)
	var counts := []
	for i in 8:  # the capital takes eight recruits a turn
		assert_eq(c.queue_recruit("tuskers"), "", "recruit %d" % (i + 1))
		tray.refresh(c)
		counts.append([tray.tokens().size(), tray.visible_tokens(), tray.scrolls()])
	assert_eq(counts[6], [7, 7, false], "seven tokens: no scroll")
	assert_eq(counts[7], [8, 7, true], "an eighth: seven show and the strip scrolls")
	assert_eq(c.queue_move(_spare(s), s.find_province("fangridge").neighbors[0]), "", "a march is a ninth token")
	tray.refresh(c)
	assert_eq([tray.tokens().size(), tray.visible_tokens(), tray.scrolls()], [9, 7, true])
	assert_eq(tray.scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO, "sideways")
	assert_eq(tray.scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	var width := 0.0
	for k in 7:
		width += tray.tokens()[k].get_combined_minimum_size().x
	width += 6.0 * OrderTray.GAP
	assert_eq(tray.scroll.custom_minimum_size.x, ceilf(width), "the viewport is exactly seven tokens wide")
	assert_eq(_shape(tray).map(func(x): return x[0]), ["1", "2", "3", "4", "5", "6", "7", "8", "9"], "all nine are there to scroll to, numbered in order")
	tray.free()


func test_below_1600_logical_a_token_keeps_its_number_or_icon_and_the_words_go_to_the_tooltip() -> void:
	var s := _world()
	var c := OrdersController.new(s, CLANS)
	var add := _adders(s)
	assert_eq(add["march"].call(c), "")
	assert_eq(add["research"].call(c), "")
	var tray := _tray(c)
	var tooltips := tray.tokens().map(func(t): return t.get_tooltip(Vector2.ZERO))
	for t in tray.tokens():
		assert_true(t.label.visible, "wide: the words show")
	tray.set_compact(true)
	for t in tray.tokens():
		assert_false(t.label.visible, "compact: the words are gone")
		assert_true(t.icon.visible and (t.chip != null or bool(t.mark.realm)), "and the number or the icon stays")
	assert_eq(tray.tokens().map(func(t): return t.get_tooltip(Vector2.ZERO)), tooltips, "the tooltip is the same, so the words are one hover away")
	tray.refresh(c)
	assert_false(tray.tokens()[0].label.visible, "a rebuilt tray stays compact")
	tray.set_compact(false)
	assert_true(tray.tokens()[0].label.visible, "and goes back when the window is wide")
	tray.free()


func test_the_tray_never_holds_another_players_orders() -> void:
	var s := _world()
	var session := GameSession.new(s, [CLANS, CROWN], 9, StubBattleResolver.new())
	var mine := OrdersController.new(session.state(), CLANS, session)
	assert_eq(mine.queue_recruit("tuskers"), "")
	var tray := _tray(mine)
	assert_eq(tray.tokens().size(), 1)
	var theirs := OrdersController.new(session.state(), CROWN, session)
	tray.refresh(theirs)
	assert_eq(tray.tokens().size(), 0, "the other seat's controller shows nothing of seat 1's orders")
	assert_false(tray.scroll.visible or tray.gold_box.visible)
	tray.refresh(null)
	assert_eq(tray.tokens().size(), 0, "and no controller, no tokens")
	tray.free()


# --- the tray in the Table --------------------------------------------------------------------------

func test_the_hint_shows_only_while_the_tray_is_empty() -> void:
	var hud := TableHud.new()
	assert_true(hud.hint_label.visible, "an empty tray shows what to do")
	hud.tray_slot().changed.emit(2)
	assert_false(hud.hint_label.visible, "orders give the tray to the tokens")
	hud.tray_slot().changed.emit(0)
	assert_true(hud.hint_label.visible)
	assert_eq(hud.tray_slot().mouse_filter, Control.MOUSE_FILTER_IGNORE, "the slot is an empty area for the input contract; its tokens take their own clicks")
	hud.free()


func test_the_table_tells_the_tray_when_it_goes_compact() -> void:
	var hud := TableHud.new()
	hud.viewport_override = Vector2(1280, 720)
	hud.relayout()
	assert_true(hud.tray_slot().compact, "below 1600 logical the tray is compact")
	hud.viewport_override = Vector2(1600, 900)
	hud.relayout()
	assert_false(hud.tray_slot().compact)
	hud.free()


# --- a click on a token ------------------------------------------------------------------------------

func _game() -> GameScreen:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.start_game({"players": [CROWN, CLANS], "seed": 4242, "ai": {CLANS: "normal"}})
	return game


func test_a_click_on_a_token_focuses_its_place_and_opens_its_card_without_giving_the_army_a_move() -> void:
	var game := _game()
	var map := game.map
	map.select_army("kingdom-1")
	map.select_province("westwatch")  # the march (1)
	map.select_province("crownkeep")
	(map.details.find_children("Recruit_*", "Button", true, false)[0] as Button).pressed.emit()  # a recruit (2)
	map.select_army("kingdom-1")  # an army of yours is selected, and a token is clicked: its place must not read as a march target
	map.table().tray_slot().token_for(1).pressed.emit(1)
	assert_eq(map.cards.mode, "order", "the order's card")
	assert_eq(map.selected_province_id, "crownkeep", "its place is selected")
	assert_eq(map.selected_army_id, "", "the army is not, so no second click ordered anything")
	assert_eq(game.session.current_orders().size(), 2, "and no new order was given")
	assert_true(map.cards.visible and _has_button(map.details, "CancelButton"), "the card has Cancel")
	assert_true(_has_label(map.details, "Order 2 · Recruit"), "and says which order it is")
	# the march's card: a click on its token
	map.table().tray_slot().token_for(0).pressed.emit(0)
	assert_true(_has_label(map.details, "Order 1 · March"))
	assert_false(_has_button(map.details, "ViaButton"), "a plain march has no Change route")
	game.free()


func _has_button(root: Node, node_name: String) -> bool:
	return not root.find_children(node_name, "Button", true, false).is_empty()


func _has_label(root: Node, text: String) -> bool:
	return root.find_children("*", "Label", true, false).any(func(l): return (l as Label).text == text)


func test_the_cross_and_a_right_click_cancel_and_the_numbers_reflow() -> void:
	var game := _game()
	var map := game.map
	map.select_army("kingdom-1")
	map.select_province("westwatch")
	map.select_province("crownkeep")
	for i in 2:
		(map.details.find_children("Recruit_*", "Button", true, false)[0] as Button).pressed.emit()
	var tray := map.table().tray_slot()
	assert_eq(_shape(tray), [["1", "march"], ["2", "recruit"], ["3", "recruit"]])
	# a right-click on the second token
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	tray.tokens()[1].gui_input.emit(right)
	assert_eq(_shape(tray), [["1", "march"], ["2", "recruit"]], "a right-click cancelled #2; the next recruit is #2 now")
	assert_eq(game.session.current_orders().size(), 2)
	# a left click on the cross of the first
	tray.tokens()[0].cross.pressed.emit()
	assert_eq(_shape(tray), [["1", "recruit"]], "the cross cancelled the march; the recruit is #1")
	assert_eq(game.map.status_text.begins_with("Order cancelled"), true)
	# a left click anywhere else on a token is not a cancel
	var left := InputEventMouseButton.new()
	left.button_index = MOUSE_BUTTON_LEFT
	left.pressed = true
	tray.tokens()[0].gui_input.emit(left)
	assert_eq(game.session.current_orders().size(), 1, "a left click opens the card and cancels nothing")
	assert_eq(map.cards.mode, "order")
	game.free()


func test_the_order_card_follows_its_order_and_its_change_buttons_are_the_ones_the_order_has() -> void:
	var s := GameState.with_rulers(7, {CROWN: "regents_court"})
	s.find_army("kingdom-1").location = "thornvale"
	for pid in ["thornvale", "stonegate", "wildmoor", "blackwood"]:
		s.find_province(pid).owner = CROWN
	var map: MapScreen = load(MAP_SCENE).instantiate()
	map.set_state(s, CROWN)
	map.select_army("kingdom-1")
	map.select_province("blackwood")  # a road move (1)
	map.queue_recruit(String(map.orders.recruitable_types()[0].id))  # (2)
	map.show_order(0)
	assert_true(_has_label(map.details, "Order 1 · March"))
	var via: Button = map.details.find_child("ViaButton", true, false)
	assert_true(via != null and via.text == "Change route", "a road move offers Change route")
	via.pressed.emit()
	assert_eq(map.cards.mode, "order", "the card follows the order it changed")
	assert_true(_has_label(map.details, "Order 2 · March"), "which is number 2 now, the recruit having moved up")
	map.show_order(0)
	assert_true(_has_label(map.details, "Order 1 · Recruit"))
	assert_false(_has_button(map.details, "ViaButton"), "a recruit has no route to change")
	(map.details.find_child("CancelButton", true, false) as Button).pressed.emit()
	assert_eq(map.orders.orders().size(), 1)
	assert_eq(map.cards.mode, "province", "cancelling closes the card: the card under it comes back")
	map.free()


func test_a_realm_orders_card_changes_it_through_its_own_panel() -> void:
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.start_game({"players": [CROWN, CLANS], "seed": 4242, "ai": {CLANS: "normal"}, "rulers": true, "paths": true})
	var map := game.map
	var hud := game.research_hud
	assert_eq(game.session.queue_order(ResearchOrder.new(_first_crown_research(game.session.state()))), "")
	map._orders_changed()
	var token := map.table().tray_slot().token_for(0)
	assert_true(bool(token.mark.realm), "research is a realm token")
	token.pressed.emit(0)
	assert_eq(map.cards.mode, "order")
	assert_true(_has_label(map.details, "Research · a realm order"))
	var change: Button = map.details.find_child("ChangeButton", true, false)
	assert_true(change != null, "Change opens the panel")
	assert_true(hud.panel == null or not hud.panel.visible)
	change.pressed.emit()
	assert_true(hud.panel != null and hud.panel.visible, "the research panel is open, to pick another target (the new pick replaces this one in place)")
	game.free()


func _first_crown_research(s: GameState) -> String:
	for n in PathData.PATHS[CROWN].nodes:
		if AscensionRules.check_research(s, CROWN, String(n.id)).is_empty():
			return String(n.id)
	return ""


# --- the 3D board ------------------------------------------------------------------------------------

func _board_for(state: GameState, viewer: String) -> Board3D:
	var map: MapScreen = load(MAP_SCENE).instantiate()
	map.set_state(state, viewer)
	var b := Board3D.new()
	map.set_board(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	b.size = BOARD_SIZE
	b.build_now()
	b.fit_whole(true)
	b.wv.rig = b.goal.duplicate()
	for k in 30:
		b._camera(1.0 / 30.0)
	return b


func test_the_3d_board_marks_every_placed_order_with_its_number_and_a_split_with_its_march() -> void:
	var s := Kit.game("rulers")
	var b := _board_for(s, CROWN)
	var map: MapScreen = b.map
	assert_eq(b.overlay.order_marks().size(), 0, "no orders: no marks")
	assert_eq(map.queue_muster(MusterOrder.transfer("kingdom-1", "", [0, 1])), "", "the split (1)")
	assert_eq(map.queue_move("kingdom-3", "westwatch"), "", "the new army's march (2)")
	assert_eq(map.queue_move("kingdom-1", "highcrag"), "", "the old army's march (3)")
	var kinds := [String(map.orders.recruitable_types()[0].id), String(map.orders.recruitable_types()[0].id)]
	for t in kinds:
		assert_eq(map.queue_recruit(t), "")  # (4, 5)
	var marks: Array = b.overlay.order_marks()
	assert_eq(marks.map(func(t): return t.chip.text), ["1", "2", "3", "4, 5"], "a token for each order, the two recruits folded into one: %s" % [marks.map(func(t): return t.mark["class"])])
	assert_eq(marks.map(func(t): return t.mark["class"]), ["muster", "march", "march", "recruit"])
	assert_eq(marks[1].mark.place, "crownkeep", "the new army's march starts where it was split off, though its formation stands only once the turn resolves")
	assert_eq(marks[1].mark.army, "kingdom-3")
	assert_eq(marks[3].label.text, "+2 units", "the recruit token: the number and the count")
	assert_false(marks[1].label.visible or marks[1].icon.visible, "a march's token is its number alone")
	assert_eq(marks[0].icon.texture, UiIcons.icon("muster", OrderToken.ICON_PX), "a split wears the muster icon")
	for t in marks:
		assert_false(String(t.get_tooltip(Vector2.ZERO)).is_empty(), "every board token has a tooltip")
		assert_eq(t.get_parent(), b.overlay)
	# cancel the split: its march goes with it, and the numbers re-flow on the board
	map.cancel_order(0)
	marks = b.overlay.order_marks()
	assert_eq(marks.map(func(t): return t.chip.text), ["1", "2, 3"], "the old army's march is 1 and the recruits 2 and 3: %s" % [marks.map(func(t): return t.mark["class"])])
	_free_board(b)


func _free_board(b: Board3D) -> void:
	var map: Node = b.map
	if map != null:
		map.free()
	elif is_instance_valid(b):
		b.free()


func test_a_click_on_a_board_token_opens_its_card_and_a_right_click_cancels() -> void:
	var s := Kit.game("rulers")
	var b := _board_for(s, CROWN)
	var map: MapScreen = b.map
	assert_eq(map.queue_move("kingdom-1", "westwatch"), "")
	assert_eq(map.queue_recruit(String(map.orders.recruitable_types()[0].id)), "")
	var tokens: Array = b.overlay.order_marks()
	assert_eq(tokens.size(), 2)
	map.select_army("kingdom-1")
	tokens[1].pressed.emit(1)
	assert_eq(map.cards.mode, "order", "a click on the board token opens the order's card, as the tray's token does")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	b.overlay.order_marks()[0].gui_input.emit(right)
	assert_eq(map.orders.orders().size(), 1, "a right-click cancels it from the board too")
	assert_eq(b.overlay.order_marks().map(func(t): return t.chip.text), ["1"], "and the recruit is number 1")
	_free_board(b)


func test_a_hotseat_seat_never_sees_the_last_seats_tokens_on_its_board() -> void:
	var game := _game()
	game.use_board("3d")
	var b: Board3D = game.map.board
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	b.size = BOARD_SIZE
	b.build_now()
	game.map.queue_move("kingdom-1", "westwatch")
	assert_eq(b.overlay.order_marks().size(), 1, "seat 1 sees its own order's mark")
	game.end_turn()
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
	assert_eq(b.overlay.order_marks().size(), 0, "the next seat has none of seat 1's marks")
	game.free()


# --- OrderSpots --------------------------------------------------------------------------------------

func test_a_token_takes_the_first_free_spot_and_never_one_under_a_taken_rect() -> void:
	var sz := Vector2(40, 20)
	var bounds := Rect2(0, 0, 400, 300)
	var spots := OrderSpots.ring_spots(Vector2(200, 150), 30.0, 20.0, sz)
	assert_eq(spots.size(), OrderSpots.ANGLES.size() * OrderSpots.RINGS.size())
	assert_eq(OrderSpots.free_spot(spots, [], bounds), spots[0], "nothing in the way: the first spot")
	var taken := [spots[0]]
	var next := OrderSpots.free_spot(spots, taken, bounds)
	assert_ne(next, spots[0], "the first is taken: the next free one")
	assert_false((spots[0] as Rect2).intersects(next), "which is clear of it")
	# every spot taken: strict finds none, the lenient pick overlaps least
	var all := spots.map(func(r): return (r as Rect2).grow(1.0))
	assert_eq(OrderSpots.free_spot(spots, all, bounds, true).size, Vector2.ZERO, "strict: no free spot, nothing")
	assert_true(OrderSpots.free_spot(spots, all, bounds, false).size.x > 0.0, "lenient: the least bad spot")
	# off screen spots are never taken; a spot that pokes out is moved in
	assert_eq(OrderSpots.free_spot([Rect2(-500, -500, 40, 20)], [], bounds).size, Vector2.ZERO, "a spot off the screen is no spot")
	assert_eq(OrderSpots.free_spot([Rect2(385, 10, 40, 20)], [], bounds), Rect2(360, 10, 40, 20), "one that pokes out is moved in")
	# the Table's pieces weigh four times: the lenient pick keeps out from under them
	var heavy := [Rect2(190, 140, 20, 20)]
	var open := Rect2(0, 0, 40, 20)
	var under := Rect2(180, 130, 40, 40)
	assert_eq(OrderSpots.free_spot([under, open], [under.grow(2.0), open.grow(2.0)], bounds, false, heavy), open, "the spot under a Table piece loses to one over a plate")


func test_a_march_number_steps_off_its_arrow_when_the_arrow_is_taken() -> void:
	var pts := PackedVector2Array([Vector2(100, 100), Vector2(300, 100)])
	var sz := Vector2(22, 22)
	var spots := OrderSpots.path_spots(pts, sz)
	assert_eq(spots.size(), OrderSpots.PATH_FRACTIONS.size() * OrderSpots.PATH_OFFSETS.size())
	assert_eq((spots[0] as Rect2).get_center(), Vector2(200, 100), "the middle of the arrow first")
	var on_arrow := spots.slice(0, OrderSpots.PATH_FRACTIONS.size())
	var blocker := Rect2(100, 90, 200, 20)  # a plate all along the arrow
	var pick := OrderSpots.free_spot(spots, [blocker], Rect2(0, 0, 400, 300), true)
	assert_true(pick.size.x > 0.0 and not pick.intersects(blocker), "the number stood off the arrow, clear of the plate")
	assert_false(on_arrow.has(pick), "from the offsets, not the arrow's own stretch")
	assert_eq(OrderSpots.path_spots(PackedVector2Array([Vector2(1, 1)]), sz), [], "no arrow, no spots")


func test_the_muster_icon_is_in_the_set() -> void:
	assert_true(UiIcons.NAMES.has("muster"))
	assert_eq(UiIcons.icon("muster", 20).get_size(), Vector2(20, 20))
	assert_true(FileAccess.file_exists("%smuster.svg" % UiIcons.DIR) and FileAccess.file_exists("%smuster.svg.import" % UiIcons.DIR))


# --- the live tray -------------------------------------------------------------------------------------

## The runner's tests run before the scene tree is live, so no mouse event is routed in them: tests/tray_probe.gd is a real (headless)
## main loop in a child process that stages a turn (a split, a march for the new army, a march, recruits and a research pick) on a whole
## game screen, at the three sizes, on the 3D board and on the 2D map; measures every token against the plates and the Table; and pushes
## real mouse events at the tray's tokens.
func test_the_live_tray_takes_real_clicks_and_keeps_clear_of_the_plates() -> void:
	var cmd := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", PROBE]
	var output := []
	var code := OS.execute(OS.get_executable_path(), cmd, output, true)
	var text := "\n".join(output)
	var passed := 0
	var failed := []
	for line in text.split("\n"):
		if line.begins_with("PASS "):
			passed += 1
		elif line.begins_with("FAIL "):
			failed.append(line)
	assert_true(passed >= 40, "the probe ran its checks (exit code %d, %d passed): %s" % [code, passed, text.right(800)])
	assert_eq(failed, [], "no check of the live tray failed")
	assert_true(text.contains("TRAY_PROBE OK"), "and it said so")
	if DirAccess.dir_exists_absolute(SCRATCH):
		for sub in DirAccess.get_directories_at(SCRATCH):
			for f in DirAccess.get_files_at(SCRATCH.path_join(sub)):
				DirAccess.remove_absolute(SCRATCH.path_join(sub).path_join(f))
			DirAccess.remove_absolute(SCRATCH.path_join(sub))
		for f in DirAccess.get_files_at(SCRATCH):
			DirAccess.remove_absolute(SCRATCH.path_join(f))
		DirAccess.remove_absolute(SCRATCH)
