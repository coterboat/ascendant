extends "res://tests/test_case.gd"
## UX-5 (#220; design/UX_WAR_TABLE.md §5.3): the Chronicle's Plan side, the end-of-turn review, headless in the M1 style on built games:
##   - review before sealing on and off: on, the End turn seal opens the Chronicle at Plan and the Plan's seal ends the turn; off, the seal
##     ends it at once; "first_game" is on during the player's first game (the first-game guide's hint not yet seen) and off after;
##   - the sentences: the placed orders by the tray's numbers, then the realm orders; each sentence is OrdersController.order_text (the
##     forecast the tray and the card show, never worked out again here) and its tooltip the tray token's;
##   - the x cancels the right order and the numbers re-flow; a click focuses the order's place and opens its card;
##   - the checks are the current-state needs (ChronicleModel.needs, the Read side's own function), and an order this turn that answers
##     one takes it off (a research order; a storm, a sally, a relief or a march away for a siege);
##   - the seal's pulse for a new player still starts once an order is queued and stops after two turns ended through the Plan;
##   - hotseat: each seat's Plan is its own, and the handoff clears it; watch mode has no Plan;
##   - fog: no sentence or check changes when what the viewer can't see changes.
## Numbers and words come from the rules and the controller, never from this file.

const Sx := preload("res://tests/siege_fixtures.gd")
const GAME_SCENE := "res://ui/game_screen.tscn"
const CROWN := "kingdom"
const CLANS := "beasts"

static var _real_settings_path := ""


# --- fixtures -------------------------------------------------------------------------------------

func _scratch() -> String:
	return "user://plan_page_test_%d" % OS.get_process_id()


## A game screen against the computer (or a hotseat game with `ai` false), its settings in a fresh scratch file (no hints seen: a first
## game), with independents (a garrison to march into) and paths (research, a realm order).
func _game(extra: Dictionary = {}, ai: bool = true, review: String = "never") -> GameScreen:
	DirAccess.make_dir_recursive_absolute(_scratch())
	if _real_settings_path.is_empty():
		_real_settings_path = GameSettings.default_path
	GameSettings.default_path = _scratch().path_join("settings_%d.cfg" % Time.get_ticks_usec())
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game.save_store = SaveStore.new(_scratch())
	var config := {"players": [CROWN, CLANS], "seed": 4242, "independents": true, "paths": true}
	if ai:
		config["ai"] = {CLANS: "normal"}
	config.merge(extra, true)
	game._bind()
	game.chronicle_hud.settings.path = GameSettings.default_path
	game.chronicle_hud.settings.review = review
	game.start_game(config)
	if game.handoff.visible:
		game.handoff.ready_button.pressed.emit()
	return game


func _clean() -> void:
	var dir := _scratch()
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)
	if not _real_settings_path.is_empty():
		GameSettings.default_path = _real_settings_path


## The Crown's turn 1 orders through the map: a march into Westwatch (the Free Holds' garrison: a fight), two recruits at the capital and
## a research target.
func _give_orders(game: GameScreen) -> void:
	var map := game.map
	map.select_army("kingdom-1")
	map.select_province("westwatch")
	map.select_province("crownkeep")
	for i in 2:
		(map.details.find_children("Recruit_*", "Button", true, false)[0] as Button).pressed.emit()
	var node := ""
	for n in AscensionRules.available_nodes(game.session.state(), CROWN):
		node = String(n)
		break
	if not node.is_empty():
		assert_eq(game.session.queue_order(ResearchOrder.new(node)), "", "the research order is accepted")
		map._orders_changed()


func _page(game: GameScreen) -> PlanPage:
	return game.plan_hud.page


# --- review before sealing ------------------------------------------------------------------------

func test_review_on_opens_the_plan_and_its_seal_ends_the_turn() -> void:
	var game := _game({}, true, "always")
	_give_orders(game)
	var turn := game.session.turn_number()
	assert_true(game.plan_hud.review_on(), "review is on")
	game.end_turn_button.pressed.emit()
	assert_eq(game.session.turn_number(), turn, "the seal did not end the turn")
	assert_true(game.chronicle_hud.is_open(), "it opened the Chronicle")
	assert_eq(game.chronicle_hud.column.current_tab(), "plan", "at the Plan")
	assert_true(game.end_turn_button.tooltip_text.contains("Review before sealing is on"), "the seal's tooltip says so")
	game.end_turn_button.pressed.emit()
	assert_eq(game.session.turn_number(), turn, "pressing the seal again only keeps the Plan open")
	assert_false(_page(game).seal_button.disabled)
	_page(game).seal_button.pressed.emit()
	assert_eq(game.session.turn_number(), turn + 1, "the Plan's seal ended the turn")
	game.free()
	_clean()


func test_review_off_ends_the_turn_at_once() -> void:
	var game := _game({}, true, "never")
	_give_orders(game)
	var turn := game.session.turn_number()
	assert_false(game.plan_hud.review_on())
	game.end_turn_button.pressed.emit()
	assert_eq(game.session.turn_number(), turn + 1, "the seal ended the turn")
	assert_false(game.end_turn_button.tooltip_text.contains("Review before sealing is on"))
	game.free()
	_clean()


func test_review_is_on_for_a_first_game_and_off_after() -> void:
	var game := _game({}, true, "first_game")
	assert_true(game.plan_hud.first_game, "no first-game hint seen: this is the first game")
	assert_true(game.plan_hud.review_on(), "so the seal opens the Plan first")
	assert_eq(ChronicleSettings.new("user://nowhere.cfg").review, ChronicleSettings.default_review)
	_give_orders(game)
	var turn := game.session.turn_number()
	game.end_turn_button.pressed.emit()
	assert_eq(game.session.turn_number(), turn, "the seal opened the Plan")
	game.free()
	# A later game: the first-game guide's hint is seen.
	var later := _game({}, true, "first_game")
	GameSettings.mark_hint_seen(GameSettings.HINT_FIRST_GAME)
	later.plan_hud.first_game = not GameSettings.hint_seen(GameSettings.HINT_FIRST_GAME)
	assert_false(later.plan_hud.review_on(), "after the first game it is off")
	_give_orders(later)
	turn = later.session.turn_number()
	later.end_turn_button.pressed.emit()
	assert_eq(later.session.turn_number(), turn + 1, "and the seal ends the turn at once")
	later.free()
	# The setting itself: saved in [chronicle], and the picker in the Plan's foot and in Settings.
	var g2 := _game({}, true, "first_game")
	_page(g2).review_option.item_selected.emit(ChronicleSettings.REVIEWS.find("never"))
	assert_eq(ChronicleSettings.load_from(g2.chronicle_hud.settings.path).review, "never", "the Plan's foot saves it")
	var panel := SettingsPanel.new()
	panel.open(GameSettings.load_from(g2.chronicle_hud.settings.path))
	assert_eq(panel.review_picker.selected, ChronicleSettings.REVIEWS.find("never"), "Settings shows it")
	assert_true(panel.set_review("always"))
	assert_eq(ChronicleSettings.load_from(g2.chronicle_hud.settings.path).review, "always", "and Settings saves it")
	assert_false(panel.set_review("sometimes"), "a value the game does not know is refused")
	assert_false(String(panel.review_picker.tooltip_text).is_empty(), "the row explains itself")
	assert_true(RulesCodex.ENTRIES.has("turn_review"), "and has its codex entry")
	panel.free()
	g2.free()
	_clean()


# --- the sentences -------------------------------------------------------------------------------

func test_the_sentences_follow_the_trays_numbers_with_the_same_forecasts() -> void:
	var game := _game()
	_give_orders(game)
	game.plan_hud.open_plan()
	var c := game.map.orders
	var shown: Array = _page(game).shown.sentences
	var want := c.placed_indices() + c.realm_indices()
	assert_eq(shown.map(func(s): return int(s.index)), want, "placed orders by number, then the realm orders")
	assert_true(shown.size() >= 3, "the march, two recruits (and research)")
	var marks := OrderMarks.marks(c)
	for s in shown:
		var i := int(s.index)
		assert_eq(int(s.number), c.number_of(i), "order %d: the tray's number" % i)
		assert_eq(int(s.number), int(OrderMarks.mark_at(c, i).number), "and the board's")
		assert_eq(String(s.text), c.order_text(i), "order %d: the controller's sentence, forecast and all" % i)
		assert_eq(String(s.tip), OrderMarks.tip(c, i), "order %d: the tray token's tooltip" % i)
		assert_true(RulesCodex.ENTRIES.has(String(s.codex)), "order %d links a codex entry" % i)
	assert_eq(marks.size(), shown.size(), "every order is a line")
	# the march into the fight carries its battle forecast, the recruit its price, the research its finish turn
	var march := c.orders()[shown[0].index] as MoveOrder
	assert_true(march != null, "order 1 is the march")
	assert_true(String(shown[0].text).contains(String(c.move_odds(march.army_id, march.to).line)), "the march's battle odds")
	# what a line shows: its first sentence, and for the march into a fight the odds as the sentence words them
	for s in shown:
		assert_true(String(s.text).begins_with(String(s.head)), "order %d: the line is the sentence's start" % int(s.index))
		assert_true(String(s.forecast).is_empty() or String(s.text).contains(String(s.forecast)), "order %d: the forecast line is the sentence's own" % int(s.index))
	assert_false(String(shown[0].forecast).is_empty(), "the march into the Free Holds' garrison shows its battle forecast")
	assert_eq(PlanModel.first_sentence("The Crown's 1st (Spearmen. Knights) moves to Westwatch. It arrives turn 2."), "The Crown's 1st (Spearmen. Knights) moves to Westwatch.")
	assert_eq(PlanModel.first_sentence("Gold 1.5 a turn."), "Gold 1.5 a turn.")
	var recruit: Dictionary = shown.filter(func(s): return c.orders()[s.index] is RecruitOrder)[0]
	assert_true(String(recruit.text).contains("%d gold" % c.recruit_cost((c.orders()[recruit.index] as RecruitOrder).unit_type_id)), "the recruit's price")
	var research := shown.filter(func(s): return c.orders()[s.index] is ResearchOrder)
	if not research.is_empty():
		assert_true(bool(research[0].realm) and int(research[0].number) == 0, "research is a realm order, unnumbered, after the placed ones")
		assert_true(String(research[0].text).contains(String(Forecast.research(c.state, CROWN, c.orders()).text)), "with its finish turn")
	# the rows the page draws, in that order
	var rows := _page(game).rows
	assert_eq(rows.map(func(r): return int(r.get_meta("index"))), want)
	assert_eq(String((rows[0] as Control).tooltip_text).split("\n\nCodex: ")[0], String(shown[0].tip), "a row's tooltip is the token's")
	assert_eq(_page(game).gold_label.text, String(c.gold_after_recruits().text), "the foot: gold after the orders")
	game.free()
	_clean()


func test_the_cross_cancels_the_right_order_and_a_click_focuses_it() -> void:
	var game := _game()
	_give_orders(game)
	game.plan_hud.open_plan()
	var c := game.map.orders
	var before := c.orders().map(func(o): return o.describe())
	var second := int(_page(game).rows[1].get_meta("index"))
	var gone := String(before[second])
	(_page(game).rows[1].find_child("Cancel", true, false) as Button).pressed.emit()
	var after := c.orders().map(func(o): return o.describe())
	assert_eq(after.size(), before.size() - 1, "one order fewer")
	assert_false(after.has(gone) and before.count(gone) == 1, "the second line's order is the one cancelled")
	var shown: Array = _page(game).shown.sentences
	assert_eq(shown.map(func(s): return int(s.number)).filter(func(n): return n > 0), range(1, c.placed_count() + 1), "the numbers re-flow")
	assert_eq(_page(game).rows.size(), shown.size(), "the page follows at once")
	# a click on the first line: its place, its card
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	(_page(game).rows[0] as Control).gui_input.emit(press)
	assert_eq(game.map.cards.mode, "order", "the order's card opens")
	assert_eq(game.map.selected_province_id, OrderMarks.place_of(c, int(_page(game).rows[0].get_meta("index"))), "at its place")
	game.free()
	_clean()


# --- the checks ----------------------------------------------------------------------------------

func test_the_checks_are_the_needs_and_an_answering_order_takes_one_off() -> void:
	var game := _game()
	game.plan_hud.open_plan()
	var st := game.session.state_for(CROWN)
	var turn := game.session.turn_number() - 1
	var want := ChronicleModel.need_items(ChronicleModel.needs(st, CROWN, turn, game.session.current_orders()), st, turn)
	assert_eq(_page(game).shown.checks.map(func(it): return String(it.id)), want.map(func(it): return String(it.id)), "the Read side's needs")
	assert_eq(_page(game).check_cards.size(), want.size(), "one card each")
	var research_need := want.any(func(it): return String(it.need) == "research")
	if research_need:
		assert_false(_page(game).check_cards[0].pin_button.visible, "pinning stays on Read")
	_give_orders(game)
	var now := ChronicleModel.needs(game.session.state_for(CROWN), CROWN, turn, game.session.current_orders())
	assert_false(now.any(func(n): return String(n.key) == "research"), "the research order answered its need")
	assert_eq(_page(game).shown.checks.size(), now.size(), "and the Plan dropped its card")
	game.free()
	_clean()


## The siege needs (FortView.needs_you): a storm, a sally, a relief or a march away answers them; any other order does not.
func test_an_order_that_answers_a_siege_takes_its_need_off() -> void:
	var s := Sx.state([["kingdom-3", CROWN, "blackwood", Sx.units("knights", 4)], ["beasts-5", CLANS, "blackwood", Sx.units("tuskers", 2)],
		["kingdom-4", CROWN, "crownkeep", Sx.units("spearmen", 2)]], {"blackwood": CLANS})
	Sx.set_fort(s, "blackwood", 1)
	assert_true(SiegeRules.siege_stands(s, "blackwood"), "a siege stands at Blackwood")
	var crown := ChronicleModel.needs(s, CROWN, 1)
	assert_eq(crown.filter(func(n): return String(n.key) == "siege.blackwood").size(), 1, "the besieger's need")
	var clans := ChronicleModel.needs(s, CLANS, 1)
	assert_eq(clans.filter(func(n): return String(n.key) == "siege.blackwood").size(), 1, "and the garrison's")
	var away := ""
	for n in s.find_province("blackwood").neighbors:
		away = String(n)
		break
	for pair in [[SiegeOrder.storm("blackwood"), true, "a storm"], [MoveOrder.new("kingdom-3", away), true, "marching away"],
			[MoveOrder.new("kingdom-4", "blackwood"), true, "a relief march into it"], [RecruitOrder.new("spearmen"), false, "a recruit at home"]]:
		var left := ChronicleModel.needs(s, CROWN, 1, [pair[0]]).filter(func(n): return String(n.key) == "siege.blackwood")
		assert_eq(left.is_empty(), bool(pair[1]), "%s %s the besieger's need" % [pair[2], "answers" if pair[1] else "does not answer"])
	assert_true(ChronicleModel.needs(s, CLANS, 1, [SiegeOrder.sally("beasts-5")]).filter(func(n): return String(n.key) == "siege.blackwood").is_empty(),
		"a sally answers the garrison's")


# --- the pulse, hotseat, watch mode, fog -----------------------------------------------------------

func test_the_seal_pulses_for_a_new_player_until_two_turns_are_sealed_through_the_plan() -> void:
	var game := _game({}, true, "first_game")
	assert_false(game.seal_nudging(), "no order yet: no pulse")
	_give_orders(game)
	game._update_hud()
	assert_true(game.seal_nudging(), "an order queued: the seal pulses")
	for k in 2:
		game.end_turn_button.pressed.emit()
		assert_true(game.plan_hud.is_showing(), "turn %d: the seal opens the Plan" % (k + 1))
		_page(game).seal_button.pressed.emit()
		if game.chronicle_hud.is_open():
			game.chronicle_hud.close()
		_give_orders(game)
		game._update_hud()
	assert_false(game.seal_nudging(), "two turns sealed: the pulse rests")
	game.free()
	_clean()


func test_each_seat_has_its_own_plan_and_the_handoff_clears_it() -> void:
	var game := _game({}, false, "never")
	assert_eq(game.session.current_player(), CROWN)
	_give_orders(game)
	game.plan_hud.open_plan()
	var crown_lines: Array = _page(game).sentence_texts()
	assert_false(crown_lines.is_empty(), "the Crown's plan")
	game.end_turn()
	assert_true(game.handoff.visible, "the handoff cover")
	assert_true(_page(game).sentence_texts().is_empty(), "nobody is looking: the Plan is empty")
	assert_true(_page(game).seal_button.disabled, "and its seal is off")
	game.handoff.ready_button.pressed.emit()
	assert_eq(game.session.current_player(), CLANS)
	var clans_lines: Array = _page(game).sentence_texts()
	for t in crown_lines:
		assert_false(clans_lines.has(t), "none of the Crown's orders on the Clans' Plan: %s" % t)
	game.map.select_army(String(game.session.state().armies.filter(func(a): return a.owner == CLANS)[0].id))
	var army := game.map.selected_army_id
	var to := String(game.session.state().find_province(game.session.state().find_army(army).location).neighbors[0])
	assert_eq(game.session.queue_order(MoveOrder.new(army, to)), "")
	game.map._orders_changed()
	assert_eq(_page(game).shown.sentences.size(), game.session.current_orders().size(), "the Clans' own orders")
	game.free()
	_clean()


func test_watch_mode_has_no_plan() -> void:
	DirAccess.make_dir_recursive_absolute(_scratch())
	var game := load(GAME_SCENE).instantiate() as GameScreen
	game.autosave_enabled = false
	game._bind()
	game.chronicle_hud.settings.review = "always"
	game.start_game({"players": [CROWN, CLANS], "seed": 4242, "ai": {CROWN: "normal", CLANS: "normal"}})
	assert_true(game.is_watching())
	assert_true(_page(game).sentence_texts().is_empty(), "no Plan")
	var turn := game.session.turn_number()
	game.end_turn_button.pressed.emit()
	assert_eq(game.session.turn_number(), turn + 1, "the seal is Next turn, at once")
	assert_false(game.plan_hud.is_showing())
	game.free()
	_clean()


func test_no_sentence_or_check_says_what_the_viewer_cannot_see() -> void:
	var game := _game({"fog": true}, true, "never")
	_give_orders(game)
	game.plan_hud.open_plan()
	var turn := game.session.turn_number() - 1
	var before: Dictionary = _page(game).shown.duplicate(true)
	assert_false(before.sentences.is_empty())
	assert_eq(_plan_from_a_fresh_view(game, turn).sentences.map(func(s): return s.text), before.sentences.map(func(s): return s.text),
		"a plan built afresh from the Crown's view says the same")
	# Perturb what the Crown can't see: the Clans' armies in veiled land grow, and the Clans' treasury changes.
	var truth: GameState = game.session._state
	var sight := FogRules.sight(truth, CROWN)
	var changed := 0
	for a in truth.armies:
		if a.owner != CLANS or a.units.is_empty() or String(sight.get(a.location, "")) != FogRules.VEILED:
			continue
		a.units.append(Unit.new(a.units[0].type, CLANS))
		changed += 1
	truth.find_faction(CLANS).gold += 77
	assert_true(changed > 0, "some Clans army stands in veiled land")
	var after := _plan_from_a_fresh_view(game, turn)
	assert_eq(after.sentences.map(func(s): return [s.text, s.tip]), before.sentences.map(func(s): return [s.text, s.tip]),
		"the sentences are unchanged (%d hidden armies perturbed)" % changed)
	assert_eq(after.checks.map(func(it): return [it.headline, it.detail]), before.checks.map(func(it): return [it.headline, it.detail]), "and the checks")
	game.free()
	_clean()


## The Plan built from the Crown's view as the session derives it now (its cache of views dropped), with the Crown's orders.
func _plan_from_a_fresh_view(game: GameScreen, turn: int) -> Dictionary:
	game.session._fog_cache.clear()
	var view := game.session.state_for(CROWN)
	return PlanModel.build(OrdersController.new(view, CROWN, game.session), view, CROWN, turn)
