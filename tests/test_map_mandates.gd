extends "res://tests/test_case.gd"
## M2-4 (#32): mandates and abilities on the map (design/M2_RULER.md §1.4, §2.3, §3, §7). King's Roads
## (road moves, the collision rule, two-step destinations in the orders UI), Sworn Vassals (the capture
## phase, the contested rule, the map pennant), Heavy Tithes and Royal Court (income and its
## breakdowns), Muster Grounds (one price everywhere) and Warband Muster (recruits with the Ninth Fang,
## the rank limit, cancellation at no cost, the recruit panel section). Every forecast is checked against
## the resolved turn. Rulers stay opt-in: the M1 game is unchanged, and the AI's M1-style orders still
## pass in a rulers game with mandates.

const MAP_SCENE := "res://ui/map_screen.tscn"
## Ids that must never reach player-facing text (case-sensitive: display names are capitalised).
const RAW_IDS := ["kingdom", "beasts", "crownkeep", "fangridge", "westwatch", "stonegate", "highcrag", "rivermarch",
	"greenglade", "thornvale", "wildmoor", "deepwood", "blackwood", "ebonpeak", "ironspike", "bloodfen", "_"]


# --- fixtures -------------------------------------------------------------------------------------

func _game(builds: Dictionary, seed_value: int = 7) -> GameState:
	var errors := []
	var s := GameState.with_rulers(seed_value, builds, errors)
	assert_true(s != null, "a rulers game starts: %s" % [errors])
	return s


func _own(s: GameState, fid: String, pids: Array) -> void:
	for pid in pids:
		s.find_province(pid).owner = fid


func _add_army(s: GameState, fid: String, at: String, unit_ids: Array) -> Army:
	var a := Army.new()
	a.id = s.new_army_id(fid)
	a.owner = fid
	a.location = at
	var f := s.find_faction(fid)
	for uid in unit_ids:
		a.units.append(Unit.new(TurnResolver.recruitable_type(f, uid), fid))
	s.armies.append(a)
	return a


func _of_type(events: Array, type: String) -> Array:
	return events.filter(func(e): return e.type == type)


func _assert_no_raw_ids(text: String, what: String) -> void:
	assert_false(text.is_empty(), "%s has text" % what)
	for id in RAW_IDS:
		assert_false(text.contains(id), "%s names things, not ids ('%s'): %s" % [what, id, text])


func _screen(s: GameState, fid: String) -> MapScreen:
	var screen: MapScreen = load(MAP_SCENE).instantiate()
	screen.set_state(s, fid)
	return screen


## The Crown with King's Roads (the Regent's Court preset), owning Westwatch, Stonegate and Highcrag
## besides Crownkeep: army 1 at Crownkeep can reach Stonegate by road, through Westwatch.
func _roads_state() -> GameState:
	var s := _game({"kingdom": "regents_court"})
	_own(s, "kingdom", ["westwatch", "stonegate", "highcrag"])
	return s


# --- the default game is still M1 -----------------------------------------------------------------

func test_the_m1_default_game_is_unchanged() -> void:
	var s := GameState.new(5)
	var k := s.find_faction("kingdom")
	var types: Array = []
	types.append_array(k.unit_types)
	types.append(k.commander_type)
	for ut in types:
		assert_eq(TurnResolver.recruit_cost(s, "kingdom", ut.id), ut.cost, "%s keeps its M1 price" % ut.name)
	assert_eq(TurnResolver.income_of(s, "kingdom").total, 12, "M1 income")
	assert_eq(TurnResolver.income_of(s, "kingdom").modifiers, {})
	var b := Breakdown.province_income(s, "crownkeep")
	assert_eq(b.lines.map(func(l): return [l.label, l.value]), [["Base income of Crownkeep", 12], ["Modifiers", 0]])
	assert_eq(RulerRules.road_destinations(s, "kingdom", "kingdom-1"), {})
	assert_eq(RulerRules.field_recruit_limit(s, "beasts"), 0)
	assert_false(Forecast.vassal(s, "kingdom").ok)
	# M1 orders save exactly as before, and old records without "via" or "at" load as M1 orders.
	assert_eq(MoveOrder.new("kingdom-1", "westwatch").to_dict(), {"type": "move", "army": "kingdom-1", "to": "westwatch"})
	assert_eq(RecruitOrder.new("spearmen").to_dict(), {"type": "recruit", "unit_type": "spearmen"})
	var old_move: MoveOrder = OrderBook.order_from_dict({"type": "move", "army": "kingdom-1", "to": "westwatch"})
	assert_eq(old_move.via, "")
	var old_recruit: RecruitOrder = OrderBook.order_from_dict({"type": "recruit", "unit_type": "spearmen"})
	assert_eq(old_recruit.at, "")
	# A turn resolves with M1 texts: plain moves and recruits, income without modifiers, no vassals.
	var result := TurnResolver.resolve(s, {"kingdom": [MoveOrder.new("kingdom-1", "westwatch"), RecruitOrder.new("spearmen")]}, 3,
		StubBattleResolver.new())
	var texts: Array = result.events.map(func(e): return e.text)
	assert_true(texts.has("The Aurel Crown army at Crownkeep (3 units, led by Knight Captain) moved to Westwatch."), str(texts))
	assert_true(texts.has("Aurel Crown recruited Spearmen at Crownkeep for 8 gold (37 gold left). They form a new army: the Aurel Crown army at Crownkeep (1 unit, no commander)."), str(texts))
	for e in result.events:
		assert_false(String(e.text).contains("That includes"), "no income modifiers in M1: %s" % e.text)
		assert_false(String(e.type).begins_with("vassal"), "no Sworn Vassals in M1")
	# An M1 controller orders exactly what it did: a far click stays a refused one-step move.
	var c := OrdersController.new(GameState.new(5), "kingdom")
	assert_eq(c.move_order_for("kingdom-1", "stonegate").via, "")
	assert_eq(c.road_destinations("kingdom-1"), {})
	assert_eq(c.vassal_forecasts(), [])
	assert_false(c.ruler_recruit_info().ok)


# --- King's Roads ---------------------------------------------------------------------------------

func test_road_moves_are_checked_with_plain_reasons() -> void:
	var s := _roads_state()
	assert_eq(TurnResolver.check_move(s, "kingdom", MoveOrder.new("kingdom-1", "stonegate", "westwatch")), {}, "a legal road move")
	assert_eq(RulerRules.road_vias(s, "kingdom", "kingdom-1", "stonegate"), ["westwatch"])
	assert_eq(RulerRules.road_destinations(s, "kingdom", "kingdom-1"), {"stonegate": ["westwatch"]},
		"Thornvale and Greenglade aren't yours, so they are out of road reach")
	var cases := [
		[MoveOrder.new("kingdom-1", "thornvale", "highcrag"), "road_not_owned", "Thornvale is not yours"],
		[MoveOrder.new("kingdom-1", "greenglade", "rivermarch"), "road_not_owned", "Rivermarch is not yours"],
		[MoveOrder.new("kingdom-1", "stonegate", "highcrag"), "road_not_adjacent", "Stonegate is not next to Highcrag"],
		[MoveOrder.new("kingdom-1", "stonegate", "thornvale"), "via_not_adjacent", "Thornvale is not next to Crownkeep"],
		[MoveOrder.new("kingdom-1", "crownkeep", "westwatch"), "already_there", "already in Crownkeep"],
		[MoveOrder.new("kingdom-1", "stonegate", "atlantis"), "unknown_via", "not on the map"],
	]
	for c in cases:
		var check := TurnResolver.check_move(s, "kingdom", c[0])
		assert_eq(check.get("code", ""), c[1], "%s" % c[0].describe())
		assert_true(String(check.get("reason", "")).contains(c[2]), "reason says '%s': %s" % [c[2], check.get("reason", "")])
		_assert_no_raw_ids(String(check.get("reason", "")), "reason for %s" % c[0].describe())
	# Without King's Roads, no road moves; with it, a far one-step move says what roads can do.
	_own(s, "beasts", ["ebonpeak", "blackwood"])
	var no_roads := TurnResolver.check_move(s, "beasts", MoveOrder.new("beasts-2", "blackwood", "ebonpeak"))
	assert_eq(no_roads.code, "no_kings_roads")
	_assert_no_raw_ids(no_roads.reason, "no King's Roads")
	var far := TurnResolver.check_move(s, "kingdom", MoveOrder.new("kingdom-1", "stonegate"))
	assert_eq(far.code, "not_adjacent")
	assert_true(far.reason.contains("King's Roads"), far.reason)
	var m1_far := TurnResolver.check_move(GameState.new(7), "kingdom", MoveOrder.new("kingdom-1", "stonegate"))
	assert_eq(m1_far.reason, "Stonegate is not next to Crownkeep. Armies move one neighboring province per turn.", "M1 text unchanged")
	# One move per army, road or not.
	var book := OrderBook.new()
	assert_eq(book.submit(s, "kingdom", MoveOrder.new("kingdom-1", "stonegate", "westwatch")), "")
	assert_true(book.submit(s, "kingdom", MoveOrder.new("kingdom-1", "highcrag")).contains("already has a move order"))


func test_a_road_move_arrives_in_one_turn_as_forecast() -> void:
	var s := _roads_state()
	var order := MoveOrder.new("kingdom-1", "stonegate", "westwatch")
	var f := Forecast.move(s, "kingdom", order)
	assert_true(f.ok)
	assert_eq(f.via, "westwatch")
	assert_true(f.text.contains("moves by the King's Roads through Westwatch and is at Stonegate at the start of turn 2"), f.text)
	_assert_no_raw_ids(f.text, "road forecast")
	var result := TurnResolver.resolve(s, {"kingdom": [order]}, 11, StubBattleResolver.new())
	var after: GameState = result.new_state
	assert_eq(after.find_army("kingdom-1").location, f.to, "the forecast destination is where it ends")
	assert_eq(after.current_turn + 1, f.arrival_turn, "and it is there at the start of the forecast turn")
	var moved := _of_type(result.events, "army_moved")
	assert_eq(moved.size(), 1)
	assert_eq(moved[0].text, "The Aurel Crown army at Crownkeep (3 units, led by Knight Captain) moved to Stonegate by the King's Roads through Westwatch.")
	assert_eq(moved[0].codex, "road_move")
	assert_eq(moved[0].provinces, ["crownkeep", "westwatch", "stonegate"])
	# The order survives a record round trip, and a replay gives the same state.
	var session := GameSession.new(s, ["kingdom", "beasts"], 4, StubBattleResolver.new())
	assert_eq(session.describe_order("kingdom", order),
		"Move the Aurel Crown army at Crownkeep (3 units, led by Knight Captain) to Stonegate by the King's Roads through Westwatch.")
	assert_eq(session.queue_order(order), "")
	assert_eq(session.end_turn(), "")
	assert_eq(session.acknowledge_handoff(), "")
	assert_eq(session.end_turn(), "")
	var rec: Dictionary = JSON.parse_string(JSON.stringify(session.record()))
	assert_eq(rec.history[0].orders.kingdom[0].via, "westwatch")
	var replayed := GameSession.replay(rec, StubBattleResolver.new())
	assert_eq(replayed.errors, [])
	assert_eq(replayed.state.to_dict(), session.state().to_dict(), "the replay is identical")


func test_a_road_move_never_fights_on_a_border_or_stops_halfway() -> void:
	# Built on purpose: a Thornmane army stands in Stonegate (still the Crown's at the start of the turn)
	# and steps into Westwatch while the Crown's army goes Crownkeep -> Westwatch -> Stonegate by road.
	# Two one-step moves along that road would meet on the border; a road move never does, and it does
	# not stop or fight in Westwatch either.
	var s := _roads_state()
	var raider := _add_army(s, "beasts", "stonegate", ["tuskers"])
	var orders := {"kingdom": [MoveOrder.new("kingdom-1", "stonegate", "westwatch")], "beasts": [MoveOrder.new(raider.id, "westwatch")]}
	var result := TurnResolver.resolve(s, orders, 12, StubBattleResolver.new())
	var after: GameState = result.new_state
	assert_eq(_of_type(result.events, "border_battle"), [], "no border battle")
	assert_eq(_of_type(result.events, "battle"), [], "and no battle in Westwatch")
	assert_eq(after.find_army("kingdom-1").location, "stonegate")
	assert_eq(after.find_army(raider.id).location, "westwatch")
	# The same two armies with one-step moves along one border do fight there (the M1 swap rule).
	var s2 := _roads_state()
	s2.find_army("kingdom-1").location = "westwatch"
	var raider2 := _add_army(s2, "beasts", "stonegate", ["tuskers"])
	var swap := TurnResolver.resolve(s2, {"kingdom": [MoveOrder.new("kingdom-1", "stonegate")], "beasts": [MoveOrder.new(raider2.id, "westwatch")]},
		12, StubBattleResolver.new())
	assert_eq(_of_type(swap.events, "border_battle").size(), 1, "one-step moves still swap")


func test_a_road_move_into_a_province_an_enemy_also_entered_fights_there_with_no_defender() -> void:
	var s := _roads_state()
	_own(s, "kingdom", ["thornvale"])
	var clan := _add_army(s, "beasts", "wildmoor", ["tuskers", "tuskers"])
	var road := MoveOrder.new("kingdom-1", "thornvale", "highcrag")
	assert_eq(TurnResolver.check_move(s, "kingdom", road), {})
	assert_true(Forecast.move(s, "kingdom", road).text.contains("if an enemy army moves into Thornvale too, you fight it there"))
	var result := TurnResolver.resolve(s, {"kingdom": [road], "beasts": [MoveOrder.new(clan.id, "thornvale")]}, 13, StubBattleResolver.new())
	var battles := _of_type(result.events, "battle")
	assert_eq(battles.size(), 1, "one battle")
	assert_eq(battles[0].provinces, ["thornvale"], "in Thornvale")
	assert_eq(battles[0].numbers.defender, "", "nobody defends")
	assert_eq(battles[0].cause, "arrived_together")
	assert_eq(_of_type(result.events, "border_battle"), [])


func test_orders_ui_offers_two_step_destinations_and_the_way_through() -> void:
	var s := _roads_state()
	var c := OrdersController.new(s, "kingdom")
	assert_eq(c.road_destinations("kingdom-1"), {"stonegate": ["westwatch"]})
	var preview := c.move_preview("kingdom-1", "stonegate")
	assert_true(preview.ok, preview.text)
	assert_true(preview.text.begins_with("Click to order this move."))
	assert_true(preview.text.contains("by the King's Roads through Westwatch"), preview.text)
	assert_eq(c.queue_move("kingdom-1", "stonegate"), "", "a click on a two-step province orders the road move")
	var o: MoveOrder = c.orders()[0]
	assert_eq([o.to, o.via], ["stonegate", "westwatch"])
	assert_true(c.order_texts()[0].contains("by the King's Roads through Westwatch"), c.order_texts()[0])
	assert_eq(c.order_codex_kind(0), "road_move")
	var bd := c.order_breakdown(0)
	assert_eq(int(bd.total), 2, "arrives at the start of turn 2")
	assert_eq(bd.lines[1].label, "Moving two provinces by the King's Roads")
	assert_eq(c.road_destinations("kingdom-1"), {}, "an army with a move has no more road destinations")
	assert_eq(c.road_vias_at(0), ["westwatch"])
	assert_false(c.change_via(0).is_empty(), "only one way through")
	# Two ways through: Thornvale -> Stonegate or Wildmoor -> Blackwood. The first by name is picked,
	# and the player can switch to the other.
	var s2 := _game({"kingdom": "regents_court"})
	s2.find_army("kingdom-1").location = "thornvale"
	_own(s2, "kingdom", ["thornvale", "stonegate", "wildmoor", "blackwood"])
	var c2 := OrdersController.new(s2, "kingdom")
	assert_eq(c2.road_destinations("kingdom-1").get("blackwood", []), ["stonegate", "wildmoor"])
	assert_eq(c2.queue_move("kingdom-1", "blackwood"), "")
	assert_eq(c2.orders()[0].via, "stonegate")
	assert_eq(c2.change_via(0), "")
	assert_eq(c2.orders().size(), 1)
	assert_eq(c2.orders()[0].via, "wildmoor", "the other way through")
	assert_eq(c2.change_via(0), "")
	assert_eq(c2.orders()[0].via, "stonegate", "and back")


func test_map_screen_marks_road_destinations_and_clicks_order_road_moves() -> void:
	var s := _roads_state()
	var screen := _screen(s, "kingdom")
	assert_false(screen.regions["stonegate"].road_target, "nothing marked before an army is selected")
	screen.select_army("kingdom-1")
	assert_true(screen.regions["stonegate"].road_target, "the two-step destination is marked")
	assert_true(screen.regions["stonegate"].tooltip_text.contains("King's Roads"), screen.regions["stonegate"].tooltip_text)
	assert_true(screen.regions["stonegate"].tooltip_text.contains("Codex: Province"), "its codex link survives")
	for id in ["westwatch", "highcrag", "rivermarch", "thornvale", "crownkeep"]:
		assert_false(screen.regions[id].road_target, "%s is not a road destination" % id)
	assert_true(screen.preview_move("stonegate").contains("by the King's Roads through Westwatch"))
	screen.select_province("stonegate")
	assert_eq(screen.orders.orders().size(), 1, "the click queued the road move")
	assert_eq(screen.orders.orders()[0].via, "westwatch")
	assert_false(screen.regions["stonegate"].road_target, "marks clear once the army has its move")
	var line: Label = screen.details.find_child("OrderLine", true, false)
	assert_true(line != null and line.text.contains("King's Roads"), "the order line says how it goes")
	assert_eq(CodexLink.key_at(line), "road_move")
	assert_true(screen.details.find_child("ViaButton", true, false) == null, "one way through: no switch button")
	screen.free()
	# Two ways through: the order line has a button to take the other one.
	var s2 := _game({"kingdom": "regents_court"})
	s2.find_army("kingdom-1").location = "thornvale"
	_own(s2, "kingdom", ["thornvale", "stonegate", "wildmoor", "blackwood"])
	var screen2 := _screen(s2, "kingdom")
	screen2.select_army("kingdom-1")
	screen2.select_province("blackwood")
	var via: Button = screen2.details.find_child("ViaButton", true, false)
	assert_true(via != null, "a switch button")
	if via:
		assert_true(via.tooltip_text.contains("Wildmoor"), via.tooltip_text)
		via.pressed.emit()
	assert_eq(screen2.orders.orders()[0].via, "wildmoor")
	screen2.free()


# --- Sworn Vassals --------------------------------------------------------------------------------

func test_sworn_vassals_picks_the_best_free_neutral_neighbour() -> void:
	var s := _game({"kingdom": {"ruler": "aurel_king", "mandates": ["sworn_vassals"]}})
	var owners := {}
	for p in s.provinces:
		owners[p.id] = ""
	owners["crownkeep"] = "kingdom"
	owners["highcrag"] = "kingdom"
	# Rivermarch (9) is taken by an army: Westwatch and Thornvale tie at 6, and Thornvale is first by name.
	var picks := RulerRules.vassal_picks(s, owners, {"rivermarch": true})
	assert_eq(picks.joins, {"kingdom": "thornvale"})
	assert_eq(RulerRules.vassal_picks(s, owners, {}).joins, {"kingdom": "rivermarch"}, "the highest income")
	owners["fangridge"] = "beasts"
	assert_false(RulerRules.vassal_picks(s, owners, {}).picks.has("beasts"), "only factions with the mandate")


func test_a_vassal_joins_in_the_capture_phase_as_forecast() -> void:
	var s := _game({"kingdom": {"ruler": "aurel_king", "mandates": ["sworn_vassals"]}})
	var f := Forecast.vassal(s, "kingdom")
	assert_true(f.ok)
	assert_eq(f.province, "rivermarch")
	assert_eq(f.text, "Sworn Vassals: Rivermarch (9 gold) swears fealty to you at the end of this turn, unless an army ends the turn there.")
	var result := TurnResolver.resolve(s, {}, 21, StubBattleResolver.new())
	var after: GameState = result.new_state
	assert_eq(after.find_province(f.province).owner, "kingdom", "the forecast province joined")
	var joined := _of_type(result.events, "vassal_joined")
	assert_eq(joined.size(), 1)
	assert_eq(joined[0].phase, "capture")
	assert_eq(joined[0].codex, "mandate_sworn_vassals")
	assert_eq(joined[0].text, "Rivermarch swore fealty to Aurel Crown (Sworn Vassals) and joined it without a fight. It now pays Aurel Crown 9 gold per turn.")
	var income: Dictionary = _of_type(result.events, "income").filter(func(e): return e.factions == ["kingdom"])[0]
	assert_eq(income.numbers.by_province.get("rivermarch", 0), 9, "it pays its income from this turn on; no gold changes hands for it")
	# An army ending the turn there takes it instead: the forecast counts your queued moves, and the
	# next best neighbour of your land after captures (Greenglade, next to Rivermarch) joins.
	var s2 := _game({"kingdom": {"ruler": "aurel_king", "mandates": ["sworn_vassals"]}})
	var march := [MoveOrder.new("kingdom-1", "rivermarch")]
	var f2 := Forecast.vassal(s2, "kingdom", march)
	assert_eq(f2.province, "greenglade")
	var r2 := TurnResolver.resolve(s2, {"kingdom": march}, 22, StubBattleResolver.new())
	assert_eq(r2.new_state.find_province("rivermarch").owner, "kingdom", "captured by the army")
	assert_eq(r2.new_state.find_province(f2.province).owner, "kingdom", "the forecast vassal joined")


func test_a_contested_vassal_province_goes_to_nobody() -> void:
	var s := _game({"kingdom": {"ruler": "aurel_king", "mandates": ["sworn_vassals"]},
		"beasts": {"ruler": "fang_chieftain", "mandates": ["sworn_vassals"]}})
	_own(s, "kingdom", ["westwatch", "stonegate", "highcrag", "rivermarch", "greenglade"])
	_own(s, "beasts", ["ebonpeak", "blackwood", "ironspike", "wildmoor", "bloodfen", "deepwood"])
	for fid in ["kingdom", "beasts"]:
		var f := Forecast.vassal(s, fid)
		assert_eq(f.province, "thornvale", "%s wants Thornvale" % fid)
		assert_eq(f.contested_with.size(), 1, "and sees the other faction wants it too")
		assert_true(f.text.contains("joins nobody"), f.text)
		_assert_no_raw_ids(f.text, "contested forecast")
	var result := TurnResolver.resolve(s, {}, 23, StubBattleResolver.new())
	assert_eq(result.new_state.find_province("thornvale").owner, "", "nobody gets it")
	assert_eq(_of_type(result.events, "vassal_joined"), [], "and neither picks another")
	var contested := _of_type(result.events, "vassal_contested")
	assert_eq(contested.size(), 1)
	assert_eq(contested[0].factions, ["beasts", "kingdom"])
	assert_eq(contested[0].codex, "mandate_sworn_vassals")
	_assert_no_raw_ids(contested[0].text, "contested event")


func test_the_map_marks_the_province_that_will_join() -> void:
	var s := _game({"kingdom": {"ruler": "aurel_king", "mandates": ["sworn_vassals"]}})
	var screen := _screen(s, "kingdom")
	var marker: Control = screen.regions["rivermarch"].vassal_marker
	assert_true(marker != null, "Rivermarch carries the pennant")
	if marker:
		assert_true(marker.tooltip_text.replace("\n", " ").contains(Forecast.vassal(s, "kingdom").text), marker.tooltip_text)
		assert_eq(CodexLink.key_at(marker), "mandate_sworn_vassals")
	assert_eq(screen.regions["rivermarch"].vassal_seat, 0, "in Player 1's colour")
	for id in ["westwatch", "highcrag", "greenglade"]:
		assert_eq(screen.regions[id].vassal_marker, null, "%s has no pennant" % id)
	# Queuing a move into Rivermarch moves the pennant to the next pick.
	screen.select_army("kingdom-1")
	screen.select_province("rivermarch")
	assert_eq(screen.regions["rivermarch"].vassal_marker, null, "the army takes Rivermarch itself")
	assert_true(screen.regions["greenglade"].vassal_marker != null, "Greenglade joins instead")
	screen.free()


# --- Heavy Tithes and Royal Court -----------------------------------------------------------------

func test_heavy_tithes_and_royal_court_in_income_and_breakdowns() -> void:
	# King Corvane keeps 6 (Heavy Tithes costs 4): ability rank 3, so Royal Court is +4 where he is.
	var s := _game({"kingdom": {"ruler": "aurel_king", "mandates": ["heavy_tithes"]}})
	var b := Breakdown.province_income(s, "crownkeep")
	assert_eq(b.lines.map(func(l): return [l.label, l.value]), [["Base income of Crownkeep", 12], ["Heavy Tithes", 1], ["Royal Court", 4]])
	assert_eq(int(b.total), 17)
	assert_eq(Breakdown.sum_of_lines(b), 17)
	assert_true(String(b.lines[2].note).contains("King Corvane I is here, ability rank 3"), b.lines[2].note)
	var gold := Breakdown.gold(s, "kingdom")
	assert_eq(int(gold.total), 45 + 17)
	assert_eq(Breakdown.sum_of_lines(gold), int(gold.total))
	assert_true(String(gold.lines[1].note).contains("Heavy Tithes 1") and String(gold.lines[1].note).contains("Royal Court 4"), gold.lines[1].note)
	var forecast := Forecast.gold_after_recruits(s, "kingdom", [])
	assert_eq(forecast.gold_next_turn, 62)
	var result := TurnResolver.resolve(s, {}, 31, StubBattleResolver.new())
	assert_eq(result.new_state.find_faction("kingdom").gold, forecast.gold_next_turn, "the forecast equals the result")
	var income: Dictionary = _of_type(result.events, "income").filter(func(e): return e.factions == ["kingdom"])[0]
	assert_eq(income.numbers.by_province.crownkeep, int(b.total), "the breakdown equals the province's income")
	assert_eq(income.text, "Aurel Crown earned 17 gold from 1 province (Crownkeep 17). Gold: 45 -> 62. That includes Heavy Tithes +1 (1 for each province) and Royal Court +4 at Crownkeep, where King Corvane I was.")
	# The beasts have neither: their income is the map's.
	assert_eq(Breakdown.province_income(s, "fangridge").lines[1].label, "Modifiers")


func test_royal_court_follows_the_king_and_needs_him_alive() -> void:
	var s := _game({"kingdom": {"ruler": "aurel_king", "mandates": ["heavy_tithes"]}})
	_own(s, "kingdom", ["westwatch"])
	var king := RulerRules.ruler_army(s, "kingdom")
	var ride := [MoveOrder.new(king.id, "westwatch")]
	var forecast := Forecast.gold_after_recruits(s, "kingdom", [], ride)
	assert_eq(forecast.income, 13 + 11, "Crownkeep 12 + 1, Westwatch 6 + 1 + Royal Court 4 where he ends the turn")
	assert_true(forecast.text.contains("Royal Court +4 at Westwatch, where King Corvane I ends the turn"), forecast.text)
	var result := TurnResolver.resolve(s, {"kingdom": ride}, 32, StubBattleResolver.new())
	assert_eq(result.new_state.find_faction("kingdom").gold, forecast.gold_next_turn, "the forecast equals the result")
	# Without the King on the map (fallen), there is no Royal Court.
	var s2 := _game({"kingdom": {"ruler": "aurel_king", "mandates": ["heavy_tithes"]}})
	s2.armies.erase(RulerRules.ruler_army(s2, "kingdom"))
	assert_eq(TurnResolver.income_of(s2, "kingdom").total, 13)
	assert_eq(Breakdown.province_income(s2, "crownkeep").lines.size(), 2)


func test_the_top_bar_and_regions_show_income_with_modifiers() -> void:
	var s := _game({"kingdom": {"ruler": "aurel_king", "mandates": ["heavy_tithes"]}})
	var screen := _screen(s, "kingdom")
	assert_eq(screen.gold_label.text, "Gold 45   (+17 per turn)")
	assert_true(screen.gold_label.tooltip_text.contains("Income from Crownkeep: +17"), screen.gold_label.tooltip_text)
	assert_true(screen.gold_label.tooltip_text.contains("Royal Court"), "the gold tooltip names Royal Court")
	assert_eq(screen.regions["crownkeep"].income_label.text, "17 gold")
	assert_true(screen.regions["crownkeep"].income_label.tooltip_text.contains("Heavy Tithes: +1"), screen.regions["crownkeep"].income_label.tooltip_text)
	screen.select_province("crownkeep")
	var label: Label = screen.details.find_child("IncomeLabel", true, false)
	assert_eq(label.text, "Income: 17 gold per turn")
	screen.free()


# --- Muster Grounds -------------------------------------------------------------------------------

func test_muster_grounds_prices_match_the_spec_everywhere() -> void:
	var s := _game({"kingdom": {"ruler": "aurel_king", "mandates": ["muster_grounds"]},
		"beasts": {"ruler": "fang_chieftain", "mandates": ["muster_grounds"]}})
	# The §2.3 rule, cost minus a fifth of it rounded down, on the #4 balance-pass costs.
	var spec := {"spearmen": 7, "crossbowmen": 8, "knights": 16, "knight_captain": 28,
		"tuskers": 9, "fangthrowers": 7, "war_bear": 18, "warchief": 28}
	for uid in spec:
		var fid := "kingdom" if ["spearmen", "crossbowmen", "knights", "knight_captain"].has(uid) else "beasts"
		assert_eq(TurnResolver.recruit_cost(s, fid, uid), spec[uid], "%s price (§2.3)" % uid)
		assert_eq(Forecast.recruit_cost(s, fid, uid), spec[uid])
		assert_eq(int(Breakdown.unit_stat(s, fid, uid, "cost").total), spec[uid], "the price breakdown agrees")
	# 16 gold buys Knights at 16, which would cost 20 without the mandate.
	s.find_faction("kingdom").gold = 16
	var c := OrdersController.new(s, "kingdom")
	assert_eq(c.queue_recruit("knights"), "")
	assert_eq(c.order_texts()[0], "Recruit one Knights at Crownkeep for 16 gold, leaving 0 gold.")
	assert_true(String(c.order_breakdown(0).lines[1].note).contains("Muster Grounds 4"))
	var g := c.gold_after_recruits()
	assert_eq(g.gold_after, 0)
	var session := GameSession.new(s, ["kingdom", "beasts"], 5, StubBattleResolver.new())
	assert_eq(session.describe_order("kingdom", RecruitOrder.new("knights")), "Recruit Knights at Crownkeep for 16 gold.")
	var result := TurnResolver.resolve(s, {"kingdom": [RecruitOrder.new("knights")]}, 41, StubBattleResolver.new())
	var recruited := _of_type(result.events, "recruited")
	assert_eq(recruited.size(), 1)
	assert_eq(recruited[0].numbers.cost, 16, "the recruitment phase charges the same price")
	assert_eq(recruited[0].numbers.gold_after, g.gold_after, "gold after recruits equals the forecast")
	assert_eq(result.new_state.find_faction("kingdom").gold, g.gold_next_turn, "and so does next turn's gold")
	# The map: recruit buttons and unit tooltips show the same price.
	var screen := _screen(s, "kingdom")
	screen.select_province("crownkeep")
	var button: Button = screen.details.find_child("Recruit_knights", true, false)
	assert_eq(button.text, "Recruit Knights (16 gold)")
	assert_true(button.tooltip_text.contains("16 gold (20 - Muster Grounds 4)"), button.tooltip_text)
	var count := Breakdown.unit_count(s, "kingdom-1", "Knights")
	assert_true(String(count.description).contains("Recruit cost 16 gold (20 - Muster Grounds 4)."), count.description)
	screen.free()


# --- Warband Muster -------------------------------------------------------------------------------

## The Clans' balanced preset (the Ninth Fang, keeping 5: ability rank 2, so 2 recruits per turn), with
## the Fang standing in Ebonpeak, which the Clans own.
func _fang_state() -> GameState:
	var s := _game({"beasts": "blood_of_the_fang"})
	RulerRules.ruler_army(s, "beasts").location = "ebonpeak"
	_own(s, "beasts", ["ebonpeak"])
	return s


func test_warband_muster_recruits_with_the_fang_up_to_its_rank() -> void:
	var s := _fang_state()
	assert_eq(RulerRules.field_recruit_limit(s, "beasts"), 2)
	assert_eq(RulerRules.field_recruit_limit(s, "kingdom"), 0, "the Ever-Regent has no Warband Muster")
	var c := OrdersController.new(s, "beasts")
	var info := c.ruler_recruit_info()
	assert_true(info.ok)
	assert_eq([info.province, info.limit, info.left], ["ebonpeak", 2, 2])
	assert_eq(c.queue_recruit_with_ruler("tuskers"), "")
	assert_eq(c.queue_recruit_with_ruler("fangthrowers"), "")
	var third := c.queue_recruit_with_ruler("war_bear")
	assert_true(third.contains("can recruit 2 units per turn"), third)
	_assert_no_raw_ids(third, "limit reason")
	var commander := c.queue_recruit_with_ruler("warchief")
	assert_true(commander.contains("Commanders come only from your capital"), commander)
	_assert_no_raw_ids(commander, "commander reason")
	assert_eq(c.ruler_recruit_info().left, 0)
	assert_eq(c.order_texts()[0], "Recruit one Tuskers with the Ninth Fang for 11 gold, leaving 34 gold. It joins the Ninth Fang where it ends this turn (now Ebonpeak), if you own that province then; if not, it is cancelled and costs nothing.")
	assert_eq(c.order_codex_kind(0), "field_recruit")
	var g := c.gold_after_recruits()
	assert_eq(g.gold_after, 45 - 11 - 8)
	var kingdom_ruler := TurnResolver.check_recruit(s, "kingdom", RecruitOrder.new("spearmen", RecruitOrder.AT_RULER), 99)
	assert_eq(kingdom_ruler.code, "no_field_recruits")
	_assert_no_raw_ids(kingdom_ruler.reason, "no Warband Muster")
	var result := TurnResolver.resolve(s, {"beasts": c.orders()}, 51, StubBattleResolver.new())
	var after: GameState = result.new_state
	var recruited := _of_type(result.events, "recruited")
	assert_eq(recruited.size(), 2)
	assert_eq(recruited[0].text, "Thornmane Clans recruited Tuskers with the Ninth Fang at Ebonpeak for 11 gold (34 gold left). They form a new army: the Thornmane Clans army at Ebonpeak (1 unit, no commander).")
	assert_eq(recruited[0].codex, "field_recruit")
	assert_eq(recruited[1].provinces, ["ebonpeak"])
	assert_eq(recruited[1].numbers.gold_after, g.gold_after, "gold after recruits equals the forecast")
	assert_eq(after.find_faction("beasts").gold, g.gold_next_turn, "and next turn's gold too")
	assert_true(RulerRules.ruler_army(after, "beasts").units.is_empty(), "recruits never join the Fang's own army")
	var new_army := after.find_army(recruited[0].armies[0])
	assert_eq([new_army.location, new_army.units.size()], ["ebonpeak", 2])
	assert_true(after.validate([]))
	# A record with recruits at the Fang replays identically.
	var rec := {"start_state": s.to_dict(), "players": ["kingdom", "beasts"], "game_seed": "1",
		"history": [{"turn": 1, "seed": "51", "orders": {"beasts": c.orders().map(func(o): return o.to_dict())}}]}
	rec = JSON.parse_string(JSON.stringify(rec))
	assert_eq(rec.history[0].orders.beasts[0].at, "ruler")
	assert_eq(GameSession.replay(rec, StubBattleResolver.new()).state.to_dict(), after.to_dict())


func test_recruits_with_the_fang_are_cancelled_at_no_cost_when_it_falls() -> void:
	var s := _fang_state()
	var host := _add_army(s, "kingdom", "blackwood", ["knights", "knights", "knights", "knights", "knights", "knights", "knights", "knights"])
	_own(s, "kingdom", ["blackwood"])
	var orders := {"beasts": [RecruitOrder.new("tuskers", RecruitOrder.AT_RULER), RecruitOrder.new("fangthrowers", RecruitOrder.AT_RULER)],
		"kingdom": [MoveOrder.new(host.id, "ebonpeak")]}
	assert_eq(Forecast.gold_after_recruits(s, "beasts", orders.beasts).gold_after, 45 - 11 - 8, "both forecast while the Fang stands")
	var result := TurnResolver.resolve(s, orders, 52, StubBattleResolver.new())
	var after: GameState = result.new_state
	assert_eq(RulerRules.ruler_army(after, "beasts"), null, "the Fang fell at Ebonpeak")
	var cancelled := _of_type(result.events, "order_rejected").filter(func(e): return e.phase == "recruitment")
	assert_eq(cancelled.size(), 2, "both recruits are cancelled")
	for e in cancelled:
		assert_eq(e.codex, "field_recruit")
		assert_true(String(e.reason).contains("no gold is spent"), e.reason)
		_assert_no_raw_ids(e.text, "cancelled recruit")
	assert_eq(_of_type(result.events, "recruited"), [])
	var income: Dictionary = _of_type(result.events, "income").filter(func(e): return e.factions == ["beasts"])[0]
	assert_eq(income.numbers.gold_before, 45, "they cost nothing")


func test_recruits_with_the_fang_are_cancelled_at_no_cost_when_its_province_is_not_yours() -> void:
	# The recruitment phase checks the board after capture. Built here: the Fang stands in a province
	# the Clans don't own, so both recruits fail before anything is paid.
	var s := _fang_state()
	s.find_province("ebonpeak").owner = "kingdom"
	var orders := [RecruitOrder.new("tuskers", RecruitOrder.AT_RULER), RecruitOrder.new("tuskers", RecruitOrder.AT_RULER)]
	var priced := TurnResolver.price_recruits(s, "beasts", orders)
	assert_eq(priced.gold_after, priced.gold_before, "nothing is paid")
	for r in priced.results:
		assert_false(r.ok)
		assert_eq(r.code, "ruler_province_not_held")
		assert_true(String(r.reason).contains("Ebonpeak, which is not yours") and String(r.reason).contains("no gold is spent"), r.reason)


func test_recruit_panel_has_a_section_for_the_fang() -> void:
	var s := _fang_state()
	var screen := _screen(s, "beasts")
	screen.select_province("fangridge")
	assert_true(screen.details.find_child("Recruit_tuskers", true, false) != null, "capital recruits at Fangridge")
	assert_true(screen.details.find_child("RulerRecruitHeading", true, false) == null, "the Fang is not here")
	screen.select_province("ebonpeak")
	var heading: Label = screen.details.find_child("RulerRecruitHeading", true, false)
	assert_true(heading != null, "the Fang's province has the section")
	if heading == null:
		screen.free()
		return
	assert_eq(heading.text, "Recruit with the Ninth Fang")
	assert_true(screen.details.find_child("Recruit_tuskers", true, false) == null, "no capital buttons away from the capital")
	var left: Label = screen.details.find_child("RulerRecruitLeft", true, false)
	assert_eq(left.text, "2 of 2 left this turn (Warband Muster)")
	assert_eq(CodexLink.key_at(left), "field_recruit")
	var button: Button = screen.details.find_child("RecruitWithRuler_tuskers", true, false)
	assert_eq(button.text, "Recruit Tuskers with the Ninth Fang (11 gold)")
	assert_true(String(screen.orders.recruit_breakdown("tuskers", RecruitOrder.AT_RULER).description).contains("Warband Muster at ability rank 2"))
	assert_true(button.tooltip_text.begins_with("Recruit Tuskers with the Ninth Fang"), button.tooltip_text)
	button.pressed.emit()
	button = screen.details.find_child("RecruitWithRuler_war_bear", true, false)
	button.pressed.emit()
	assert_eq(screen.orders.orders().size(), 2)
	assert_true(screen.orders.orders()[0].is_with_ruler())
	button = screen.details.find_child("RecruitWithRuler_tuskers", true, false)
	assert_true(button.disabled, "the limit is reached")
	left = screen.details.find_child("RulerRecruitLeft", true, false)
	assert_eq(left.text, "0 of 2 left this turn (Warband Muster)")
	screen.free()
	# With the Fang at the capital, both sections show.
	var home := _game({"beasts": "blood_of_the_fang"})
	var screen2 := _screen(home, "beasts")
	screen2.select_province("fangridge")
	assert_true(screen2.details.find_child("Recruit_tuskers", true, false) != null)
	assert_true(screen2.details.find_child("RecruitWithRuler_tuskers", true, false) != null)
	screen2.free()


# --- codex, plain language and the AI -------------------------------------------------------------

func test_codex_entries_match_the_code() -> void:
	var court := RulesCodex.text("ability_royal_court")
	for rank in range(1, 5):
		assert_true(court.contains("%d" % RulerRules.ability_value("aurel_king", rank)), "Royal Court rank %d value" % rank)
	assert_true(RulesCodex.text("mandate_heavy_tithes").contains("1 more gold"))
	var muster := RulesCodex.text("mandate_muster_grounds")
	var s := _game({"kingdom": {"ruler": "aurel_king", "mandates": ["muster_grounds"]},
		"beasts": {"ruler": "fang_chieftain", "mandates": ["muster_grounds"]}})
	for f in s.factions:
		var types: Array = []
		types.append_array(f.unit_types)
		types.append(f.commander_type)
		for ut in types:
			assert_true(muster.contains("%s %d" % [ut.name, TurnResolver.recruit_cost(s, f.id, ut.id)]), "the entry lists %s's price" % ut.name)
	assert_true(RulesCodex.text("mandate_sworn_vassals").contains("neither gets it"))
	assert_true(RulesCodex.text("mandate_kings_roads").contains("never fights on a border"))
	assert_true(RulesCodex.text("road_move").contains("nobody defending"))
	assert_true(RulesCodex.text("ability_warband_muster").contains("cancelled and cost nothing"))
	for key in TooltipText.CODEX:
		assert_true(RulesCodex.ENTRIES.has(TooltipText.CODEX[key]), "%s links an entry" % key)


func test_new_texts_name_things_not_ids() -> void:
	var s := _game({"kingdom": {"ruler": "aurel_king", "mandates": ["kings_roads", "heavy_tithes", "sworn_vassals"]},
		"beasts": {"ruler": "fang_chieftain", "mandates": ["muster_grounds", "sworn_vassals"]}})
	_own(s, "kingdom", ["westwatch", "stonegate"])
	var c := OrdersController.new(s, "kingdom")
	assert_eq(c.queue_move("kingdom-1", "stonegate"), "")
	assert_eq(c.queue_recruit("knights"), "")
	var b := OrdersController.new(s, "beasts")
	assert_eq(b.queue_recruit_with_ruler("tuskers"), "")
	var texts := []
	texts.append_array(c.order_texts())
	texts.append_array(b.order_texts())
	texts.append(c.gold_after_recruits().text)
	texts.append(b.ruler_recruit_info().text)
	for v in c.vassal_forecasts():
		texts.append(v.text)
	texts.append(Breakdown.gold(s, "kingdom").description)
	for i in c.orders().size():
		texts.append(c.order_breakdown(i).description)
	var result := TurnResolver.resolve(s, {"kingdom": c.orders(), "beasts": b.orders()}, 61, StubBattleResolver.new())
	for e in result.events:
		texts.append(e.text)
	for t in texts:
		_assert_no_raw_ids(String(t), "text")


func test_the_ai_still_gives_valid_orders_in_a_rulers_game_with_mandates() -> void:
	var s := _game({"kingdom": {"ruler": "aurel_king", "mandates": ["kings_roads", "muster_grounds", "heavy_tithes"]},
		"beasts": {"ruler": "fang_chieftain", "mandates": ["sworn_vassals", "muster_grounds"]}}, 17)
	var ai := AIPlayer.new()
	for turn in 4:
		var orders := {}
		for fid in ["kingdom", "beasts"]:
			var planned := ai.plan_orders(s, fid, SeededRNG.new(1000 + turn * 2 + (1 if fid == "beasts" else 0)))
			var book := OrderBook.new()
			for o in planned:
				var why := book.submit(s, fid, o)
				assert_eq(why, "", "turn %d: the AI's order for %s is valid (%s)" % [turn + 1, fid, o.describe()])
			orders[fid] = book.orders_for(fid)
		var result := TurnResolver.resolve(s, orders, 7000 + turn)
		assert_true(result.new_state != null, "turn %d resolves" % (turn + 1))
		for e in result.events:
			assert_ne(e.type, "order_rejected", "turn %d: nothing the AI ordered is rejected: %s" % [turn + 1, e.text])
		s = result.new_state
