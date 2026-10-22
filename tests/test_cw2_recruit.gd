extends "res://tests/test_case.gd"
## CW-2 (#253, design/CANDLEWAKE.md §2.1): a recruit order names the army it joins. RecruitOrder.into is an army of yours at the
## recruiting place or "new:<group>"; every order of one group forms one new army, in order, with the lowest new id; it is
## checked when given (OrderBook, plain reasons) and, when it resolves, a named army that is no longer there falls back to a new
## army and the report says so. Without it a recruit joins the first army there by id, and the order saves as before.

const CROWN := "kingdom"
const WAKE := "candlewake"


func _game() -> GameState:
	var errors := []
	var s := GameState.create(31, [CROWN, WAKE], {}, {}, errors)
	assert_eq(errors, [])
	s.find_faction(WAKE).gold = 200
	return s


func _add(s: GameState, at: String, types: Array, flame: int) -> Army:
	var f := s.find_faction(WAKE)
	var a := Army.new()
	a.id = s.new_army_id(WAKE)
	a.owner = WAKE
	a.location = at
	for type_id in types:
		var ut := TurnResolver.recruitable_type(f, String(type_id))
		if ut.is_commander:
			a.commander = Unit.new(ut, WAKE)
		else:
			a.units.append(Unit.new(ut, WAKE))
	a.flame = flame
	s.armies.append(a)
	return a


func _home(s: GameState) -> String:
	return s.find_faction(WAKE).capital


func test_into_saves_only_when_set_and_parses_back() -> void:
	assert_false(RecruitOrder.new("wickwardens").to_dict().has("into"), "an order without it saves as before")
	var o := RecruitOrder.new("wickwardens", "", "new:a")
	assert_eq(o.to_dict().into, "new:a")
	var back = OrderBook.order_from_dict(o.to_dict())
	assert_eq(back.into, "new:a")
	assert_true(back.is_new_army())


func test_a_bad_destination_is_refused_in_plain_words() -> void:
	var s := _game()
	var field: String = s.find_province(_home(s)).neighbors[0]
	var away := _add(s, field, ["wickwardens"], 1)
	var led := s.find_army("candlewake-1")
	var cases := [
		["candlewake-99", "wickwardens", "no army of yours"],
		[away.id, "wickwardens", "is at"],
		[led.id, "lamplighter", "already has a commander"],
		["new:", "wickwardens", "names its group"],
		["new:a b", "wickwardens", "names its group"],
	]
	for c in cases:
		var why := OrderBook.check_order(s, WAKE, RecruitOrder.new(String(c[1]), "", String(c[0])), [])
		assert_false(why.is_empty(), "%s is refused" % c[0])
		assert_true(String(why.get("reason", "")).contains(String(c[2])), "%s: %s" % [c[0], why.get("reason", "")])
		assert_false(String(why.get("reason", "")).contains("candlewake-"), "no raw ids: %s" % why.get("reason", ""))
	assert_eq(OrderBook.check_order(s, WAKE, RecruitOrder.new("wickwardens", "", led.id), []), {}, "an army of yours there")
	assert_eq(OrderBook.check_order(s, WAKE, RecruitOrder.new("wickwardens", "", "new:a"), []), {}, "a new army")


func test_recruits_join_the_army_they_name_and_cool_it() -> void:
	var s := _game()
	var first := s.find_army("candlewake-1")
	first.flame = 1
	var hot := _add(s, _home(s), ["wickwardens"], 3)
	var r := TurnResolver.resolve(s, {WAKE: [RecruitOrder.new("gleaners", "", hot.id)]}, 3, StubBattleResolver.new())
	var after: GameState = r.new_state
	assert_eq(after.find_army(hot.id).units.size(), 2, "they joined the army they named, not the first by id")
	assert_eq(after.find_army(first.id).units.size(), first.units.size(), "the first army by id is left alone")
	assert_eq(after.find_army(hot.id).flame, WickRules.start_flame(s, WAKE), "and cooled it")


func test_a_new_group_forms_one_army_with_the_lowest_new_id() -> void:
	var s := _game()
	var ids := s.peek_army_ids(WAKE, 2)
	var orders := [RecruitOrder.new("wickwardens", "", "new:a"), RecruitOrder.new("gleaners", "", "new:b"),
		RecruitOrder.new("wickwardens", "", "new:a")]
	var r := TurnResolver.resolve(s, {WAKE: orders}, 3, StubBattleResolver.new())
	var after: GameState = r.new_state
	var a: Army = after.find_army(String(ids[0]))
	var b: Army = after.find_army(String(ids[1]))
	assert_eq(a.units.map(func(u): return u.type.id), ["wickwardens", "wickwardens"], "group a: one army, both its recruits")
	assert_eq(b.units.map(func(u): return u.type.id), ["gleaners"], "group b: the next new id")
	assert_eq(a.flame, WickRules.start_flame(s, WAKE), "a new army starts at the start flame")


func test_a_named_army_gone_by_then_falls_back_to_a_new_army_and_says_so() -> void:
	var s := _game()
	var home := _home(s)
	var mover := _add(s, home, ["wickwardens"], 2)
	var field: String = s.find_province(home).neighbors[0]
	# It was there when the order was given, and marches away the same turn.
	assert_eq(OrderBook.check_order(s, WAKE, RecruitOrder.new("gleaners", "", mover.id), []), {})
	var next := String(s.peek_army_ids(WAKE, 1)[0])
	var r := TurnResolver.resolve(s, {WAKE: [MoveOrder.new(mover.id, field), RecruitOrder.new("gleaners", "", mover.id)]}, 3,
		StubBattleResolver.new())
	var after: GameState = r.new_state
	assert_eq(after.find_army(mover.id).units.size(), 1, "the army that left got nothing")
	assert_true(after.find_army(next) != null, "the recruits formed a new army at the recruiting place")
	var rec: Array = r.events.filter(func(e): return String(e.type) == "recruited")
	assert_true(String(rec[0].text).contains("was no longer there to join, so they form a new army"), rec[0].text)


func test_without_into_recruits_join_the_first_army_by_id_as_before() -> void:
	var s := _game()
	var first := s.find_army("candlewake-1")
	var r := TurnResolver.resolve(s, {WAKE: [RecruitOrder.new("gleaners")]}, 3, StubBattleResolver.new())
	assert_eq(r.new_state.find_army(first.id).units.size(), first.units.size() + 1)


func test_the_recruit_forecast_reads_into() -> void:
	var s := _game()
	var hot := _add(s, _home(s), ["wickwardens"], 3)
	var named := Forecast.recruit_at(s, WAKE, "wickwardens", "", [], hot.id)
	assert_true(named.ok and String(named.joins) == hot.id, named.text)
	assert_true(String(named.text).contains("cools it from flame 3"), named.text)
	var fresh := Forecast.recruit_at(s, WAKE, "wickwardens", "", [], "new:a")
	assert_true(fresh.ok and String(fresh.joins).is_empty(), fresh.text)
	assert_true(String(fresh.text).contains("they form a new army there") and String(fresh.text).contains("A new army starts at flame"), fresh.text)
	var bad := Forecast.recruit_at(s, WAKE, "wickwardens", "", [], "candlewake-99")
	assert_false(bad.ok, "a bad destination is refused in the forecast too")
