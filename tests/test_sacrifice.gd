extends "res://tests/test_case.gd"
## M2-6 (#34): the mid-game sacrifice (design/M2_RULER.md §2.4, §3). The Sacrifice order and its
## serialization, every rejection reason, the sacrifice phase first in the turn (the spec's numbers, the
## ruler's hp rule, Veteran Levies on the map), King's Roads bought by sacrifice allowing a road move the
## same turn, the order re-check when a sacrifice is cancelled (or makes another order fail), the preview
## equal to the resolved result, replay, the succession countdown and the codex.
##
## Rulers are opt-in: every test here turns them on with GameState.with_rulers, except the ones that check
## the M1 game is unchanged. Battles are pinned with StubBattleResolver; most tests fight none.

const Simulator := preload("res://tools/autoplay/simulator.gd")
## Ids that must never reach player-facing text (case-sensitive: display names are capitalised).
const RAW_IDS := ["kingdom", "beasts", "crownkeep", "fangridge", "westwatch", "stonegate", "highcrag", "rivermarch",
	"greenglade", "thornvale", "wildmoor", "deepwood", "blackwood", "ebonpeak", "ironspike", "bloodfen",
	"aurel_king", "ever_regent", "thornmane_avatar", "fang_chieftain", "royal_court", "mending_light", "warband_muster",
	"iron_discipline", "drilled_ranks", "royal_armories", "kings_roads", "heavy_tithes", "veteran_levies",
	"muster_grounds", "sworn_vassals", "blood_frenzy", "feast_of_victory", "_", "-1", "-2", "-3", "-4", "-5"]
## Every number the preview shows for the faction's own ruler and units, compared with the resolved turn.
const RULER_KEYS := ["max_hp", "hp", "attack", "defense", "morale", "ability_rank", "ability_value", "ability_effect"]


# --- fixtures -------------------------------------------------------------------------------------

func _game(builds: Dictionary, seed_value: int = 7) -> GameState:
	var errors := []
	var s := GameState.with_rulers(seed_value, builds, errors)
	assert_eq(errors, [], "the rulers set up")
	return s


## King Corvane keeping all 10 power (the Warrior King preset) against the Clans' balanced build.
func _king_keeps_all(seed_value: int = 7) -> GameState:
	return _game({"kingdom": "warrior_king"}, seed_value)


func _resolve(s: GameState, orders: Dictionary) -> Dictionary:
	var result := TurnResolver.resolve(s, orders, TurnResolver.seed_for_turn(s), StubBattleResolver.new())
	assert_true(result.new_state != null, "the turn resolves: %s" % str(result.get("errors", [])))
	return result


func _of_type(events: Array, type: String) -> Array:
	return events.filter(func(e): return e.type == type)


func _own(s: GameState, fid: String, pids: Array) -> void:
	for pid in pids:
		s.find_province(pid).owner = fid


func _assert_no_raw_ids(text: String, what: String) -> void:
	assert_false(text.strip_edges().is_empty(), "%s has text" % what)
	for id in RAW_IDS:
		assert_false(text.contains(id), "%s names things, not ids ('%s'): %s" % [what, id, text])


# --- the order ------------------------------------------------------------------------------------

func test_the_sacrifice_order_saves_and_loads() -> void:
	var o := SacrificeOrder.new("royal_armories")
	assert_eq(o.to_dict(), {"type": "sacrifice", "mandate": "royal_armories"})
	var back = OrderBook.order_from_dict(JSON.parse_string(JSON.stringify(o.to_dict())))
	assert_true(back is SacrificeOrder, "a sacrifice loads as a SacrificeOrder")
	assert_eq(back.mandate_id, "royal_armories")
	var errors := []
	assert_eq(OrderBook.order_from_dict({"type": "pray"}, errors), null)
	assert_true(String(errors[0]).contains("'sacrifice'"), "the unknown-order message lists sacrifices: %s" % errors[0])
	# The phase order: sacrifice first, rulers last; the report shows them in the same order.
	assert_eq(TurnResolver.PHASES, ["sacrifice", "orders", "movement", "battles", "capture", "recruitment", "income", "rulers"])
	assert_eq(GameSession.REPORT_PHASES, ["sacrifice", "orders", "movement", "battles", "capture", "recruitment", "income", "rulers", "victory"])
	assert_eq(RulerRules.sacrifice_cost("royal_armories"), RulerRules.mandate_cost("royal_armories") + MandateData.SACRIFICE_PREMIUM)


# --- rejections (acceptance: no living ruler, too little power, a second one, owned or foreign) ----

func test_each_rejection_has_a_plain_reason() -> void:
	var s := _king_keeps_all()
	var book := OrderBook.new()
	# A second sacrifice in one turn.
	assert_eq(book.submit(s, "kingdom", SacrificeOrder.new("royal_armories")), "", "the first sacrifice is accepted")
	var second := book.submit(s, "kingdom", SacrificeOrder.new("veteran_levies"))
	assert_true(second.contains("already gave a Sacrifice order this turn, for Royal Armories"), second)
	assert_true(second.contains("once per turn"), second)
	assert_eq(book.orders_for("kingdom").size(), 1, "the second one is not queued")
	# An owned mandate: the Regent's Court already has Royal Armories.
	var court := _game({"kingdom": "regents_court"})
	var owned := RulerRules.sacrifice_check(court, "kingdom", "royal_armories")
	assert_eq(owned.code, "owned_mandate")
	assert_eq(owned.reason, "The Aurel Crown already has Royal Armories. Each mandate can be taken only once.")
	# A foreign mandate: Blood Frenzy is the Clans'.
	var foreign := RulerRules.sacrifice_check(s, "kingdom", "blood_frenzy")
	assert_eq(foreign.code, "foreign_mandate")
	assert_eq(foreign.reason, "Blood Frenzy is a Thornmane Clans mandate, so the Aurel Crown can't take it, not even by sacrifice.")
	# Too little power: the Iron Crown spent everything before the game.
	var spent := _game({"kingdom": "iron_crown"})
	var poor := RulerRules.sacrifice_check(spent, "kingdom", "kings_roads")
	assert_eq(poor.code, "not_enough_power")
	assert_eq(poor.reason, "King's Roads costs %d power by sacrifice (%d, +%d for a mid-game sacrifice), but King Corvane I keeps only 0." % [
		RulerRules.sacrifice_cost("kings_roads"), RulerRules.mandate_cost("kings_roads"), MandateData.SACRIFICE_PREMIUM])
	# Exactly enough is enough: kept power at least the price + 1, and it may drop to 0.
	var edge := _king_keeps_all()
	edge.find_faction("kingdom").kept_power = RulerRules.sacrifice_cost("royal_armories")
	RulerRules.refresh_ruler(edge, "kingdom")
	assert_eq(RulerRules.sacrifice_check(edge, "kingdom", "royal_armories"), {}, "kept power equal to the cost is enough")
	edge.find_faction("kingdom").kept_power -= 1
	assert_eq(RulerRules.sacrifice_check(edge, "kingdom", "royal_armories").code, "not_enough_power", "one short is not")
	# No living ruler: the King died last turn.
	var dead := _king_keeps_all()
	dead.current_turn = 3
	RulerRules.record_death(dead, "kingdom", 3)
	var no_ruler := RulerRules.sacrifice_check(dead, "kingdom", "royal_armories")
	assert_eq(no_ruler.code, "no_living_ruler")
	assert_eq(no_ruler.reason, "King Corvane I is dead, and only a living ruler can sacrifice power. Corvane II will be crowned at Crownkeep at the end of turn 5.")
	assert_eq(OrderBook.new().submit(dead, "kingdom", SacrificeOrder.new("royal_armories")), no_ruler.reason, "the order book gives the same reason")
	# A game without rulers, and a mandate that doesn't exist.
	assert_eq(RulerRules.sacrifice_check(GameState.new(7), "kingdom", "royal_armories").code, "no_ruler")
	assert_eq(RulerRules.sacrifice_check(s, "kingdom", "golden_throne").reason, "'golden_throne' is not a mandate in this game.")
	for check in [owned, foreign, poor, no_ruler, RulerRules.sacrifice_check(GameState.new(7), "kingdom", "royal_armories")]:
		_assert_no_raw_ids(check.reason, "the %s reason" % check.code)
	_assert_no_raw_ids(second, "the second-sacrifice reason")


func test_the_resolver_rejects_illegal_sacrifices_in_the_sacrifice_phase() -> void:
	var s := _king_keeps_all()
	# Orders not given through the order book (a hand-made record) are checked again when the turn resolves.
	var result := _resolve(s, {"kingdom": [SacrificeOrder.new("blood_frenzy"), SacrificeOrder.new("royal_armories"),
		SacrificeOrder.new("veteran_levies")]})
	var events: Array = result.events
	var rejected := _of_type(events, "order_rejected")
	assert_eq(rejected.size(), 2, "the foreign mandate and the second sacrifice are rejected")
	for e in rejected:
		assert_eq(e.phase, "sacrifice")
		assert_eq(e.codex, "sacrifice")
		assert_eq(e.provinces, ["crownkeep"], "the event points at the ruler")
		_assert_no_raw_ids(String(e.text), "a rejected sacrifice")
	assert_eq(rejected[0].cause, "foreign_mandate")
	assert_true(String(rejected[0].text).begins_with("Order from Aurel Crown, \"sacrifice power for Blood Frenzy\", was rejected: Blood Frenzy is a Thornmane Clans mandate"), rejected[0].text)
	assert_eq(rejected[1].cause, "second_sacrifice")
	var k: Faction = result.new_state.find_faction("kingdom")
	assert_eq(k.mandates, ["royal_armories"], "only the legal sacrifice happened")
	assert_eq(k.kept_power, 10 - RulerRules.sacrifice_cost("royal_armories"))
	# A Sacrifice order in a game without rulers changes nothing and says why.
	var m1 := _resolve(GameState.new(7), {"kingdom": [SacrificeOrder.new("royal_armories")]})
	var m1_rejected := _of_type(m1.events, "order_rejected")
	assert_eq(m1_rejected.size(), 1)
	assert_eq(m1_rejected[0].cause, "no_ruler")
	assert_eq(OrderBook.new().submit(GameState.new(7), "kingdom", SacrificeOrder.new("royal_armories")),
		"The Aurel Crown has no ruler in this game, so nobody can sacrifice power for a mandate.")


# --- the sacrifice phase ------------------------------------------------------------------------------

func test_a_sacrifice_resolves_first_with_the_spec_numbers() -> void:
	var s := _king_keeps_all()
	var result := _resolve(s, {"kingdom": [MoveOrder.new("kingdom-1", "westwatch"), SacrificeOrder.new("royal_armories")]})
	var events: Array = result.events
	assert_eq(events[0].type, "sacrificed", "the sacrifice is the turn's first event, before any move")
	var e: Dictionary = events[0]
	assert_eq(e.phase, "sacrifice")
	assert_eq(e.codex, "sacrifice")
	assert_eq(e.factions, ["kingdom"])
	assert_eq(e.provinces, ["crownkeep"])
	assert_eq(e.armies, ["kingdom-2"], "the ruler's army")
	assert_eq(e.text, "King Corvane I gave up 4 power for Royal Armories (3, +1 for a mid-game sacrifice). Kept power 10 → 6: hit points 38 of 38 → 30 of 30, attack 14 → 12, defense 13 → 11, Royal Court rank 4 → 3 (+4 gold). Every regular unit of the Aurel Crown now has +1 attack.")
	assert_eq([e.numbers.kept_before, e.numbers.kept_after, e.numbers.cost, e.numbers.price, e.numbers.premium], [10, 6, 4, 3, 1])
	var k: Faction = result.new_state.find_faction("kingdom")
	assert_eq(k.kept_power, 6)
	assert_eq(k.mandates, ["royal_armories"])
	assert_eq(k.sacrifices, [{"turn": 1, "mandate": "royal_armories", "cost": 4}], "recorded with the turn")
	var ruler := RulerRules.ruler_unit(result.new_state, "kingdom")
	assert_eq([ruler.type.hp, ruler.type.attack, ruler.type.defense], [30, 12, 11], "the §1.3 table at 6 kept")
	assert_eq(ruler.current_hp, 30, "hp dropped by as much as the maximum (and the end-of-turn heal is capped there)")
	# The kept power breakdown now has the sacrifice line, and the state is valid and saves.
	var b := Breakdown.kept_power(result.new_state, "kingdom")
	assert_eq(b.lines.map(func(l): return [l.label, l.value]), [["Power pool", 10], ["Royal Armories, sacrificed on turn 1", -4]])
	assert_true(result.new_state.validate([]))
	assert_eq(GameState.from_dict(JSON.parse_string(JSON.stringify(result.new_state.to_dict()))).find_faction("kingdom").sacrifices,
		k.sacrifices, "the record survives JSON")


func test_the_ruler_loses_as_much_hp_as_its_maximum_never_below_1() -> void:
	for case in [[38, 30], [30, 22], [9, 1], [3, 1]]:
		var s := _king_keeps_all()
		RulerRules.ruler_unit(s, "kingdom").current_hp = case[0]
		var info := RulerRules.apply_sacrifice(s, "kingdom", "royal_armories", 1)
		assert_true(info.ok)
		assert_eq(RulerRules.ruler_unit(s, "kingdom").current_hp, case[1], "%d of 38 hp drops by 8 to %d" % case)
		assert_eq([info.hp_before, info.hp_after, info.max_hp_before, info.max_hp_after], [case[0], case[1], 38, 30])
	# The other rulers follow their own tables: the Great Thornmane keeping 10 gives up 4 + 1 for Iron Discipline.
	var god := _game({"beasts": "beast_god_unbound"})
	var info := RulerRules.apply_sacrifice(god, "beasts", "iron_discipline", 1)
	assert_eq([info.kept_after, info.max_hp_after, info.attack_after, info.defense_after, info.rank_after],
		[6, RulerRules.stat_value("thornmane_avatar", "hp", 6), RulerRules.stat_value("thornmane_avatar", "attack", 6),
			RulerRules.stat_value("thornmane_avatar", "defense", 6), RulerRules.ability_rank(6)])
	assert_eq(RulerRules.ruler_unit(god, "beasts").current_hp, RulerRules.stat_value("thornmane_avatar", "hp", 6))


func test_veteran_levies_by_sacrifice_gives_units_on_the_map_their_hit_points_at_once() -> void:
	var s := _king_keeps_all()
	var army := s.find_army("kingdom-1")
	army.units[0].current_hp -= 4  # a wounded unit gains the 2 hit points too, and stays 4 below its new maximum
	var before: Array = army.units.map(func(u): return u.current_hp)
	var commander_hp := army.commander.current_hp
	var result := _resolve(s, {"kingdom": [SacrificeOrder.new("veteran_levies")]})
	var after: Army = result.new_state.find_army("kingdom-1")
	for i in after.units.size():
		var u: Unit = after.units[i]
		assert_eq(u.current_hp, before[i] + 2, "%s gained 2 hit points" % u.type.name)
		assert_eq(RulerRules.unit_max_hp(result.new_state, u), u.type.hp + 2, "its maximum is 2 higher")
	assert_eq(after.commander.current_hp, commander_hp, "commanders are not regular units")
	var e: Dictionary = _of_type(result.events, "sacrificed")[0]
	assert_true(String(e.text).ends_with("Every regular unit of the Aurel Crown now has +2 maximum hit points, and the 3 units already on the map gained 2 hit points at once."), e.text)
	assert_eq([e.numbers.units_gained, e.numbers.hp_gained], [3, 6])
	# The autoplay invariants know the higher maximum.
	var problems := Simulator.check_invariants(s, result.new_state, result.events)
	assert_eq(problems.filter(func(p): return String(p.check) == "unit_hp_above_max"), [], str(problems))


# --- King's Roads by sacrifice (acceptance) -----------------------------------------------------------

## The Crown keeping all its power, owning Westwatch and Stonegate: army 1 at Crownkeep could reach
## Stonegate by road through Westwatch, if it had King's Roads.
func _roads_by_sacrifice() -> GameState:
	var s := _king_keeps_all()
	_own(s, "kingdom", ["westwatch", "stonegate"])
	return s


func test_kings_roads_bought_by_sacrifice_allows_a_road_move_the_same_turn() -> void:
	var s := _roads_by_sacrifice()
	var road := MoveOrder.new("kingdom-1", "stonegate", "westwatch")
	var book := OrderBook.new()
	var refused := book.submit(s, "kingdom", road)
	assert_true(refused.begins_with("Only a faction with King's Roads"), "without it the road move is refused: %s" % refused)
	assert_eq(book.submit(s, "kingdom", SacrificeOrder.new("kings_roads")), "")
	assert_eq(book.submit(s, "kingdom", road), "", "with the sacrifice queued, the road move is accepted")
	# The orders UI offers it too: the controller's view counts the queued sacrifice.
	var c := OrdersController.new(s, "kingdom")
	assert_eq(c.road_destinations("kingdom-1"), {})
	assert_eq(c.queue_sacrifice("kings_roads"), "")
	assert_eq(c.road_destinations("kingdom-1"), {"stonegate": ["westwatch"]}, "road destinations appear at once")
	assert_eq(c.move_order_for("kingdom-1", "stonegate").via, "westwatch")
	assert_true(c.move_forecast("kingdom-1", "stonegate").text.contains("by the King's Roads through Westwatch"))
	# It resolves the same turn, whatever order the two were given in.
	for orders in [book.orders_for("kingdom"), [road, SacrificeOrder.new("kings_roads")]]:
		var result := _resolve(s, {"kingdom": orders})
		assert_eq(_of_type(result.events, "order_rejected"), [], "nothing is rejected")
		var moved := _of_type(result.events, "army_moved")
		assert_eq(moved.size(), 1)
		assert_eq(moved[0].text, "The Aurel Crown army at Crownkeep (3 units, led by Knight Captain) moved to Stonegate by the King's Roads through Westwatch.")
		assert_eq(result.new_state.find_army("kingdom-1").location, "stonegate")
		assert_eq(result.events[0].type, "sacrificed", "the sacrifice came first")


# --- the re-check on cancel (acceptance) ---------------------------------------------------------------

func test_cancelling_the_sacrifice_removes_the_road_move_that_relied_on_it() -> void:
	var s := _roads_by_sacrifice()
	var book := OrderBook.new()
	assert_eq(book.submit(s, "kingdom", SacrificeOrder.new("kings_roads")), "")
	assert_eq(book.submit(s, "kingdom", MoveOrder.new("kingdom-1", "stonegate", "westwatch")), "")
	assert_eq(book.submit(s, "kingdom", MoveOrder.new("kingdom-2", "highcrag")), "", "the ruler's own move doesn't need roads")
	var dropped := book.cancel(s, "kingdom", 0)
	assert_eq(dropped.size(), 1)
	assert_eq(dropped[0].text, "Road move to Stonegate through Westwatch removed: you no longer have King's Roads.")
	assert_eq(dropped[0].code, "no_kings_roads")
	var left := book.orders_for("kingdom")
	assert_eq(left.size(), 1)
	assert_eq(left[0].army_id, "kingdom-2", "the move that never needed the sacrifice stays")
	assert_eq(book.last_dropped().size(), 1)
	# Cancelling an order nothing depends on removes nothing else.
	assert_eq(book.cancel(s, "kingdom", 0), [])
	assert_eq(book.orders_for("kingdom"), [])


func test_cancelling_muster_grounds_removes_the_recruit_it_paid_for() -> void:
	var s := _king_keeps_all()
	var k := s.find_faction("kingdom")
	var knights := TurnResolver.recruitable_type(k, "knights")
	var cheap := RulerRules.recruit_price(RulerRules.with_sacrifice(s, "kingdom", "muster_grounds"), "kingdom", knights)
	assert_true(cheap < knights.cost, "Muster Grounds makes Knights cheaper (%d < %d)" % [cheap, knights.cost])
	k.gold = cheap * 2  # two Knights only at the Muster Grounds price
	var book := OrderBook.new()
	assert_eq(book.submit(s, "kingdom", RecruitOrder.new("knights")), "")
	assert_true(book.submit(s, "kingdom", RecruitOrder.new("knights")).contains("but you only have"), "two are too dear at full price")
	assert_eq(book.submit(s, "kingdom", SacrificeOrder.new("muster_grounds")), "")
	assert_eq(book.submit(s, "kingdom", RecruitOrder.new("knights")), "", "with the sacrifice queued, the second one fits")
	# The resolved turn pays the Muster Grounds price for both.
	var result := _resolve(s, {"kingdom": book.orders_for("kingdom")})
	var recruited := _of_type(result.events, "recruited")
	assert_eq(recruited.map(func(e): return e.numbers.cost), [cheap, cheap])
	# Cancel the sacrifice: the second recruit no longer fits and is removed, with the reason.
	var dropped := book.cancel(s, "kingdom", 1)
	assert_eq(dropped.size(), 1)
	assert_eq(dropped[0].text, "Recruit Knights at Crownkeep removed: Knights cost %d gold, but you only have %d gold left." % [
		knights.cost, cheap * 2 - knights.cost])
	assert_eq(book.orders_for("kingdom").size(), 1, "the first recruit stays")


func test_a_sacrifice_that_lowers_warband_muster_removes_the_recruit_over_the_new_limit() -> void:
	# The Ninth Fang keeping 5 (rank 2: two recruits in the field) sacrifices 4 for Blood Frenzy: rank 1.
	var s := _game({"beasts": {"ruler": "fang_chieftain", "mandates": ["iron_discipline", "veteran_levies"]}})
	s.find_faction("beasts").gold = 200
	var book := OrderBook.new()
	for i in 2:
		assert_eq(book.submit(s, "beasts", RecruitOrder.new("tuskers", RecruitOrder.AT_RULER)), "")
	var preview := Forecast.sacrifice(s, "beasts", "blood_frenzy", book.orders_for("beasts"))
	assert_eq(preview.dropped, ["Recruit Tuskers with the Ninth Fang would be removed: The Ninth Fang can recruit 1 unit per turn (Warband Muster at ability rank 1), and that one is already ordered."],
		"the preview warns before you confirm")
	var row: Array = preview.rows.filter(func(r): return r.key == "field_recruits")
	assert_eq([row[0].before, row[0].after], ["2 units per turn", "1 unit per turn"])
	assert_eq(book.submit(s, "beasts", SacrificeOrder.new("blood_frenzy")), "")
	assert_eq(book.last_dropped().map(func(d): return d.text),
		["Recruit Tuskers with the Ninth Fang removed: The Ninth Fang can recruit 1 unit per turn (Warband Muster at ability rank 1), and that one is already ordered."])
	assert_eq(book.orders_for("beasts").size(), 2, "one recruit and the sacrifice")


func test_the_session_removes_dependent_orders_and_says_why() -> void:
	var s := _roads_by_sacrifice()
	var session := GameSession.new(s, ["kingdom", "beasts"], 7, StubBattleResolver.new())
	assert_eq(session.queue_sacrifice("kings_roads"), "")
	assert_eq(session.queue_order(MoveOrder.new("kingdom-1", "stonegate", "westwatch")), "")
	assert_eq(session.current_order_texts()[0], "Sacrifice: King Corvane I gives up 3 power for King's Roads (2, +1 for a mid-game sacrifice).")
	assert_eq(session.cancel_order(0), "")
	assert_eq(session.removed_orders(), ["Road move to Stonegate through Westwatch removed: you no longer have King's Roads."])
	assert_eq(session.current_orders(), [])
	# Through the orders controller the map uses, the same lines come back.
	var c := OrdersController.new(session.state(), "kingdom", session)
	assert_eq(c.queue_sacrifice("kings_roads"), "")
	assert_eq(c.queue_move("kingdom-1", "stonegate"), "", "a click two steps away orders the road move")
	assert_eq(c.cancel(0), "")
	assert_eq(c.last_removed(), ["Road move to Stonegate through Westwatch removed: you no longer have King's Roads."])


# --- the preview equals the resolved result (acceptance) ---------------------------------------------

## Resolves `s` with `fid`'s sacrifice for `mid` (and `orders`) and checks the preview's "after" numbers
## against the faction's numbers on the resolved state and the turn's income event.
func _assert_preview_is_the_result(s: GameState, fid: String, mid: String, orders: Array = [], check_income: bool = true) -> Dictionary:
	var preview := Forecast.sacrifice(s, fid, mid, orders)
	assert_true(preview.ok, "%s can sacrifice for %s: %s" % [fid, mid, preview.get("reason", "")])
	var result := _resolve(s, {fid: orders + [SacrificeOrder.new(mid)]})
	var resolved := Forecast.faction_numbers(result.new_state, fid, [])
	var after: Dictionary = preview.after
	var what := "%s for %s" % [fid, mid]
	assert_eq(after.kept_power, resolved.kept_power, "%s: kept power" % what)
	assert_eq(after.mandates, resolved.mandates, "%s: mandates" % what)
	for key in RULER_KEYS:
		assert_eq(after.ruler[key], resolved.ruler[key], "%s: the ruler's %s" % [what, key])
	assert_eq(after.units, resolved.units, "%s: every unit's hit points, attack, defense and price" % what)
	assert_eq(after.field_recruits, resolved.field_recruits, "%s: recruits with the ruler" % what)
	for aid in after.unit_hp:
		# Units already there keep their places; a recruit that joins the army is added after them.
		var now: Array = resolved.unit_hp.get(aid, [])
		assert_eq(after.unit_hp[aid], now.slice(0, after.unit_hp[aid].size()), "%s: hit points of the units in %s" % [what, aid])
	if check_income:
		var income: Array = _of_type(result.events, "income").filter(func(e): return e.factions == [fid])
		assert_eq(after.income, income[0].numbers.income, "%s: the income the turn paid" % what)
	# The rows show the same numbers.
	var rows := {}
	for r in preview.rows:
		rows[r.key] = r
		_assert_no_raw_ids(String(r.label), "%s row label" % what)
		assert_true(RulesCodex.ENTRIES.has(String(r.codex)), "%s row %s links an entry" % [what, r.key])
		assert_eq(Breakdown.sum_of_lines(r.breakdown), int(r.breakdown.total), "%s row %s: its breakdown sums up" % [what, r.key])
	assert_eq(rows.kept_power.after, str(resolved.kept_power))
	assert_eq(rows.ruler_hp.after, "%d of %d" % [resolved.ruler.hp, resolved.ruler.max_hp])
	assert_eq(rows.ruler_attack.after, str(resolved.ruler.attack))
	assert_eq(rows.ability.after, "rank %d (%s)" % [resolved.ruler.ability_rank, resolved.ruler.ability_effect])
	for line in preview.effects:
		_assert_no_raw_ids(String(line), "%s effect line" % what)
	return {"preview": preview, "result": result}


func test_the_preview_equals_the_resolved_result() -> void:
	# King Corvane keeping 10: every Crown mandate, one at a time.
	for mid in ["royal_armories", "veteran_levies", "heavy_tithes", "muster_grounds", "kings_roads", "iron_discipline", "drilled_ranks"]:
		_assert_preview_is_the_result(_king_keeps_all(), "kingdom", mid)
	# The Ever-Regent keeping 4 (Mending Light drops a rank), the Ninth Fang keeping 5 (Warband Muster drops),
	# the Great Thornmane keeping 10.
	_assert_preview_is_the_result(_game({"kingdom": "regents_court"}), "kingdom", "drilled_ranks")
	_assert_preview_is_the_result(_game({"beasts": "blood_of_the_fang"}), "beasts", "veteran_levies")
	_assert_preview_is_the_result(_game({"beasts": "beast_god_unbound"}), "beasts", "feast_of_victory")
	# Royal Armories: the row for every regular unit says +1 attack, from the rules.
	var ra := _assert_preview_is_the_result(_king_keeps_all(), "kingdom", "royal_armories")
	var s := _king_keeps_all()
	for ut in s.find_faction("kingdom").unit_types:
		var row: Array = ra.preview.rows.filter(func(r): return r.key == "unit_" + ut.id)
		assert_eq(row.size(), 1, "%s has a row" % ut.name)
		assert_eq([row[0].before, row[0].after], ["attack %d" % ut.attack, "attack %d" % (ut.attack + 1)])
	assert_true(ra.preview.rows.filter(func(r): return r.key == "unit_knight_captain").is_empty(), "commanders don't get it")
	# Heavy Tithes and Royal Court: the income row is the income the turn pays.
	var ht := _assert_preview_is_the_result(_king_keeps_all(), "kingdom", "heavy_tithes")
	var income_row: Array = ht.preview.rows.filter(func(r): return r.key == "income")
	if income_row.is_empty():
		# Heavy Tithes' +2 at Crownkeep exactly makes up for Royal Court dropping from rank 4 to rank 2.
		assert_eq(ht.preview.before.income, ht.preview.after.income, "no income row when the income doesn't change")
	else:
		assert_eq(income_row[0].after, "+%d gold" % ht.preview.after.income)
	var base := s.find_province("crownkeep").income
	assert_eq(ht.preview.before.income, base + RulerRules.ability_value("aurel_king", 4), "Crownkeep + Royal Court at rank 4")
	assert_eq(ht.preview.after.income, base + RulerRules.TITHE_GOLD + RulerRules.ability_value("aurel_king", 2),
		"Crownkeep + Heavy Tithes + Royal Court at rank 2")


func test_the_preview_counts_queued_orders() -> void:
	# A queued recruit pays the Muster Grounds price the preview shows; the King marching off takes Royal Court with him.
	var s := _king_keeps_all()
	var out := _assert_preview_is_the_result(s, "kingdom", "muster_grounds", [RecruitOrder.new("knights"), MoveOrder.new("kingdom-2", "westwatch")],
		false)
	var recruited: Array = _of_type(out.result.events, "recruited")
	assert_eq(recruited[0].numbers.cost, out.preview.after.units.knights.cost, "the recruit paid the previewed price")
	var price_row: Array = out.preview.rows.filter(func(r): return r.key == "price_knights")
	assert_eq([price_row[0].before, price_row[0].after], ["%d gold" % out.preview.before.units.knights.cost, "%d gold" % recruited[0].numbers.cost])
	# Sworn Vassals: the province the preview names is the one that joins.
	var sv := Forecast.sacrifice(_king_keeps_all(), "kingdom", "sworn_vassals")
	var joined := _of_type(_resolve(_king_keeps_all(), {"kingdom": [SacrificeOrder.new("sworn_vassals")]}).events, "vassal_joined")
	assert_eq(joined.size(), 1, "a vassal joins the turn Sworn Vassals is bought")
	var name: String = _king_keeps_all().find_province(joined[0].provinces[0]).name
	assert_true(sv.effects[0].contains("%s (" % name), "the preview names %s: %s" % [name, sv.effects[0]])
	# Queued attacks are fought again with the change, and an illegal pick previews only its reason.
	var raid := _king_keeps_all()
	var enemy := Army.new()
	enemy.id = raid.new_army_id("beasts")
	enemy.owner = "beasts"
	enemy.location = "westwatch"
	enemy.units.append(Unit.new(TurnResolver.recruitable_type(raid.find_faction("beasts"), "fangthrowers"), "beasts"))
	raid.armies.append(enemy)
	var attack := Forecast.sacrifice(raid, "kingdom", "drilled_ranks", [MoveOrder.new("kingdom-1", "westwatch")])
	assert_eq(attack.odds.size(), 1)
	assert_eq(attack.odds[0].name, "Westwatch")
	assert_true(String(attack.odds[0].before).contains(" of 24)"), attack.odds[0].before)
	var illegal := Forecast.sacrifice(_game({"kingdom": "iron_crown"}), "kingdom", "kings_roads")
	assert_false(illegal.ok)
	assert_eq(illegal.code, "not_enough_power")
	assert_eq(illegal.rows, [])


# --- replay ---------------------------------------------------------------------------------------

func test_a_game_with_a_sacrifice_replays_from_its_record() -> void:
	var s := _roads_by_sacrifice()
	var session := GameSession.new(s, ["kingdom", "beasts"], 7, StubBattleResolver.new())
	assert_eq(session.queue_sacrifice("kings_roads"), "")
	assert_eq(session.queue_order(MoveOrder.new("kingdom-1", "stonegate", "westwatch")), "")
	assert_eq(session.end_turn(), "")
	session.acknowledge_handoff()
	assert_eq(session.end_turn(), "")
	var report: Array = session.turn_report().events
	assert_eq(report[0].type, "sacrificed")
	assert_eq(report[0].phase, "sacrifice")
	session.acknowledge_handoff()
	assert_eq(session.queue_sacrifice("royal_armories"), "", "another sacrifice the next turn")
	assert_eq(session.end_turn(), "")
	session.acknowledge_handoff()
	assert_eq(session.end_turn(), "")
	var rec := session.record()
	assert_eq(rec.history[0].orders.kingdom[0], {"type": "sacrifice", "mandate": "kings_roads"}, "the record keeps the order")
	var final := session.state()
	assert_eq(final.find_faction("kingdom").kept_power, 10 - 3 - 4)
	assert_eq(final.find_faction("kingdom").sacrifices, [{"turn": 1, "mandate": "kings_roads", "cost": 3},
		{"turn": 2, "mandate": "royal_armories", "cost": 4}])
	for r in [rec, JSON.parse_string(JSON.stringify(rec))]:
		var replay := GameSession.replay(r, StubBattleResolver.new())
		assert_eq(replay.errors, [])
		assert_eq(replay.state.to_dict(), final.to_dict(), "the replay ends in the same state")


# --- the succession countdown (§5.4) ---------------------------------------------------------------

func test_the_countdown_counts_the_turns_until_the_successor_arrives() -> void:
	var cases := [["warrior_king", "kingdom", "heir in 2 turns", "heir in 1 turn"],
		["regents_court", "kingdom", "re-forms in 4 turns", "re-forms in 3 turns"],
		["beast_god_unbound", "beasts", "returns in 1 turn", ""]]
	for c in cases:
		var s := _game({c[1]: c[0]})
		s.current_turn = 3  # the ruler died during turn 3; turn 4 is being ordered
		RulerRules.record_death(s, c[1], 3)
		assert_eq(RulerRules.countdown_text(s, c[1]), c[2], c[0])
		var b := Breakdown.successor_countdown(s, c[1])
		assert_eq(int(b.total), RulerRules.successor_countdown(s, c[1]))
		assert_eq(Breakdown.sum_of_lines(b), int(b.total), "%s: the countdown's lines sum up" % c[0])
		assert_true(RulesCodex.ENTRIES.has(String(b.codex)))
		for l in b.lines:
			_assert_no_raw_ids(String(l.label), "countdown line")
		s.current_turn = 4
		assert_eq(RulerRules.countdown_text(s, c[1]), c[3] if not String(c[3]).is_empty() else "successor waits for the capital", "%s a turn later" % c[0])
	# Alive: no countdown.
	assert_eq(RulerRules.countdown_text(_king_keeps_all(), "kingdom"), "")
	assert_eq(RulerRules.successor_countdown(_king_keeps_all(), "kingdom"), -1)
	assert_eq(RulerRules.ability_short("fang_chieftain", 1), "1 recruit in the field", "the plural is fixed")
	assert_eq(RulerRules.ability_short("fang_chieftain", 2), "2 recruits in the field")
	assert_eq(RulerRules.ability_short("thornmane_avatar", 1), "-1 enemy morale")


# --- the codex ------------------------------------------------------------------------------------

func test_the_codex_states_the_phase_order_and_the_sacrifice_as_coded() -> void:
	var order := RulesCodex.text("phase_order")
	var at := -1
	for i in TurnResolver.PHASES.size():
		var step := "%d. %s" % [i + 1, TurnResolver.PHASES[i]]
		var found := order.find(step)
		assert_true(found > at, "phase_order lists '%s' in order: %s" % [step, order])
		at = found
	var text := RulesCodex.text("sacrifice")
	assert_true(text.contains("plus %d" % MandateData.SACRIFICE_PREMIUM), "the premium")
	assert_true(text.contains("Royal Armories costs %d" % RulerRules.sacrifice_cost("royal_armories")), "the example price")
	assert_true(text.contains("one Sacrifice order per turn"))
	assert_true(text.contains("King's Roads bought this way allows a road move the same turn"))
	assert_true(text.contains("never below 1"))
	assert_true(text.contains("removed"), "the re-check on cancel")
	assert_true(RulesCodex.text("mandate_veteran_levies").contains("Bought by sacrifice, your regular units already on the map gain 2 maximum and 2 current hit points at once"))
