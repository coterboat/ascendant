extends "res://tests/test_case.gd"
## CW-2 (#253, design/CANDLEWAKE.md §2.1, §2.2, §4.2, §4.3): Wick through whole turns. In the Wick step (after the wake, before
## income) an army that won a battle gains 1 flame; one that fought none loses 1 outside a harbour (a fort it owns, or the Wake's,
## CW-3) and none in one; an army raised this turn skips that loss; Vigil lifts the armies in Mother Tallow's province to her
## floor; the flame stays between 0 and the cap; at 0 the regulars gutter. Recruits cool what they join, and so does a merge;
## Kindling starts them hotter; Tallow Levy prices Wickwardens lower; Half-Death's Harvest raises Wickwardens after a won battle.
## Every number comes from WickRules, the rows and RulerData.

const CROWN := "kingdom"
const WAKE := "candlewake"


func _game(flags: Dictionary = {}, builds: Dictionary = {}) -> GameState:
	var errors := []
	var s := GameState.create(23, [CROWN, WAKE], flags, builds, errors)
	assert_eq(errors, [], "the game builds")
	return s


func _army(s: GameState, owner: String, at: String, types: Array, flame: int = -1) -> Army:
	var f := s.find_faction(owner)
	var a := Army.new()
	a.id = s.new_army_id(owner)
	a.owner = owner
	a.location = at
	for type_id in types:
		var ut := TurnResolver.recruitable_type(f, String(type_id))
		if ut.is_commander:
			a.commander = Unit.new(ut, owner)
		else:
			a.units.append(Unit.new(ut, owner))
	if WickRules.carries_flame(a):
		a.flame = flame if flame >= 0 else WickRules.start_flame(s, owner)
	s.armies.append(a)
	return a


func _turn(s: GameState, orders: Dictionary = {}, game_seed: int = 5) -> Dictionary:
	var r := TurnResolver.resolve(s, orders, game_seed, StubBattleResolver.new())
	assert_true(r.new_state != null, "the turn resolves: %s" % [r.get("errors", [])])
	var errors := []
	assert_true(r.new_state.validate(errors), "the state after the turn validates: %s" % [errors])
	return r


func _events_of(r: Dictionary, type: String, army_id: String = "") -> Array:
	return r.events.filter(func(e): return String(e.type) == type and (army_id.is_empty() or Array(e.armies).has(army_id)))


func _home(s: GameState) -> String:
	return s.find_faction(WAKE).capital


## A province next to the Candlewake's capital with no fort, so no harbour.
func _open_field(s: GameState) -> String:
	for pid in s.find_province(_home(s)).neighbors:
		if not s.find_province(pid).has_fort:
			return pid
	return ""


func test_a_win_feeds_the_flame_once() -> void:
	var s := _game()
	var field := _open_field(s)
	var wake := s.find_army("candlewake-1")
	wake.flame = 1
	_army(s, CROWN, field, ["spearmen"])
	var r := _turn(s, {WAKE: [MoveOrder.new(wake.id, field)]})
	var after: Army = r.new_state.find_army(wake.id)
	assert_eq(after.location, field, "it won and stands there")
	assert_eq(after.flame, 2, "a win: +1")
	var lines := _events_of(r, "flame_changed", wake.id)
	assert_eq(lines.size(), 1, "one net line")
	assert_eq([int(lines[0].numbers.from), int(lines[0].numbers.to)], [1, 2])
	assert_eq(String(lines[0].phase), WickRules.PHASE)
	# At the cap a win changes nothing, and says nothing.
	var s2 := _game()
	var hot := s2.find_army("candlewake-1")
	hot.flame = WickRules.cap(s2, WAKE)
	_army(s2, CROWN, _open_field(s2), ["spearmen"])
	var r2 := _turn(s2, {WAKE: [MoveOrder.new(hot.id, _open_field(s2))]})
	assert_eq(r2.new_state.find_army(hot.id).flame, WickRules.cap(s2, WAKE), "never above the cap")
	assert_eq(_events_of(r2, "flame_changed", hot.id), [], "no change, no line")


func test_idle_outside_a_harbour_loses_one_and_a_harbour_keeps_it() -> void:
	var s := _game()
	var field := _open_field(s)
	var out := _army(s, WAKE, field, ["wickwardens", "wickwardens"], 2)
	var home := s.find_army("candlewake-1")
	home.flame = 2
	assert_true(WickRules.harbour(s, WAKE, _home(s)), "the capital's fort is a harbour")
	assert_false(WickRules.harbour(s, WAKE, field), "an open field is not")
	var r := _turn(s)
	assert_eq(r.new_state.find_army(out.id).flame, 1, "idle outside a harbour: -1")
	assert_eq(r.new_state.find_army(home.id).flame, 2, "idle in a harbour: kept")
	assert_eq(String(_events_of(r, "flame_changed", out.id)[0].numbers.why), "idle")


func test_an_army_raised_this_turn_skips_the_idle_loss() -> void:
	var s := _game()
	var field := _open_field(s)
	var src := _army(s, WAKE, field, ["wickwardens", "wickwardens", "gleaners"], 2)
	var split := MusterOrder.transfer(src.id, "", [0], false, 0)
	var r := _turn(s, {WAKE: [split]})
	var formed: Array = r.new_state.armies.filter(func(a): return a.owner == WAKE and a.location == field and a.id != src.id)
	assert_eq(formed.size(), 1, "the split formed an army")
	assert_eq(formed[0].flame, 2, "a split keeps its flame, and a new army skips the idle loss")
	assert_eq(r.new_state.find_army(src.id).flame, 1, "the army it left lost 1 for idling outside a harbour")


func test_at_flame_zero_the_regulars_gutter_never_below_one() -> void:
	var s := _game()
	var field := _open_field(s)
	var cold := _army(s, WAKE, field, ["wickwardens", "hundred_wick", "lamplighter"], 1)
	cold.units[0].current_hp = 2
	var hp_before: Array = cold.units.map(func(u): return u.current_hp)
	var cmd_before: int = cold.commander.current_hp
	var r := _turn(s)
	var after: Army = r.new_state.find_army(cold.id)
	assert_eq(after.flame, 0, "1 - 1 = 0")
	for i in after.units.size():
		assert_eq(after.units[i].current_hp, maxi(1, int(hp_before[i]) - WickRules.GUTTER_HP), "unit %d gutters, never below 1" % i)
	assert_eq(after.commander.current_hp, cmd_before, "commanders never gutter")
	var g := _events_of(r, "guttered", cold.id)
	assert_eq(g.size(), 1)
	var lost := 0
	for i in after.units.size():
		lost += int(hp_before[i]) - after.units[i].current_hp
	assert_eq(int(g[0].numbers.hp), lost)
	assert_true(String(g[0].text).contains("is guttering"), g[0].text)


func test_vigil_lifts_the_armies_in_mother_tallows_province() -> void:
	for kept in [0, 10]:
		var build := {"ruler": "mother_tallow", "mandates": [] if kept == 10 else ["kindling", "tallow_levy", "heavy_tithes"]}
		var s := _game({"rulers": true}, {WAKE: build})
		var tallow := RulerRules.ruler_army(s, WAKE)
		assert_true(tallow != null, "Mother Tallow travels as her own army")
		assert_eq(tallow.flame, -1, "a ruler's army carries no flame")
		var cold := s.find_army("candlewake-1")
		cold.flame = 0
		var floor := RulerRules.ability_value("mother_tallow", RulerRules.ability_rank(s.find_faction(WAKE).kept_power))
		var r := _turn(s)
		assert_eq(r.new_state.find_army(cold.id).flame, mini(floor, WickRules.VIGIL_MAX), "kept %d: Vigil's floor" % kept)
		assert_eq(String(_events_of(r, "flame_changed", cold.id)[0].numbers.why), "vigil")


func test_recruits_cool_what_they_join_and_kindling_starts_them_hotter() -> void:
	var s := _game()
	var home := s.find_army("candlewake-1")
	home.flame = 3
	s.find_faction(WAKE).gold = 100
	var r := _turn(s, {WAKE: [RecruitOrder.new("wickwardens")]})
	var start := WickRules.start_flame(s, WAKE)
	assert_eq(r.new_state.find_army(home.id).flame, start, "the recruits cooled it to their flame (a harbour keeps it there)")
	var rec: Array = _events_of(r, "recruited")
	assert_eq(rec[0].numbers.flame, {"from": 3, "to": start})
	assert_true(String(rec[0].text).contains("It cools the army from flame 3 to %d." % start), rec[0].text)
	# With Kindling, recruits start at the mandate's flame.
	var k := _game({"rulers": true}, {WAKE: "harvest_moot"})
	var kindled := int(RulerRules.mandate_data("kindling").start_flame)
	assert_eq(WickRules.start_flame(k, WAKE), kindled)
	var kh := k.find_army("candlewake-1")
	kh.flame = 3
	k.find_faction(WAKE).gold = 100
	var rk := _turn(k, {WAKE: [RecruitOrder.new("gleaners")]})
	assert_eq(rk.new_state.find_army(kh.id).flame, kindled, "Kindling's recruits cool it only to %d" % kindled)
	# A commander leads; it cools nothing.
	var c := _game()
	var ch := c.find_army("candlewake-1")
	ch.flame = 3
	ch.commander = null
	c.find_faction(WAKE).gold = 100
	var rc := _turn(c, {WAKE: [RecruitOrder.new("lamplighter")]})
	assert_eq(rc.new_state.find_army(ch.id).flame, 3, "a recruited commander doesn't cool the army it leads")


func test_a_merge_takes_the_lower_flame_and_says_so() -> void:
	var s := _game()
	var hot := s.find_army("candlewake-1")
	hot.flame = 3
	var cool := _army(s, WAKE, _home(s), ["wickwardens"], 1)
	var r := _turn(s, {WAKE: [MusterOrder.merge(cool.id, hot.id)]})
	assert_eq(r.new_state.find_army(hot.id).flame, 1, "the merged army takes the lower flame")
	var merged: Array = _events_of(r, "armies_merged")
	assert_true(String(merged[0].text).contains("Its flame falls from 3 to 1."), merged[0].text)


func test_tallow_levy_prices_wickwardens_from_its_row() -> void:
	var s := _game({"rulers": true}, {WAKE: "ninth_chandlers_vigil"})
	var f := s.find_faction(WAKE)
	var wick := TurnResolver.recruitable_type(f, "wickwardens")
	assert_eq(RulerRules.recruit_price(s, WAKE, wick), int(RulerRules.mandate_data("tallow_levy").unit_cost.wickwardens))
	assert_eq(RulerRules.recruit_price(s, WAKE, TurnResolver.recruitable_type(f, "gleaners")), TurnResolver.recruitable_type(f, "gleaners").cost,
		"only Wickwardens")


func test_half_deaths_harvest_raises_wickwardens_after_a_won_battle() -> void:
	var s := _game({"rulers": true}, {WAKE: "the_long_procession"})
	var field := _open_field(s)
	var half := RulerRules.ruler_army(s, WAKE)
	var line := s.find_army("candlewake-1")
	_army(s, CROWN, field, ["spearmen"])
	var before := line.units.size()
	var r := _turn(s, {WAKE: [MoveOrder.new(half.id, field), MoveOrder.new(line.id, field)]})
	var raised := RulerRules.ability_value("half_death", RulerRules.ability_rank(s.find_faction(WAKE).kept_power))
	var h := _events_of(r, "harvest")
	assert_eq(h.size(), 1, "one Harvest")
	assert_eq(int(h[0].numbers.count), raised, "its ability's value at its rank")
	assert_eq(r.new_state.find_army(line.id).units.size(), before + raised, "they joined the regular army that fought")
	assert_true(String(h[0].text).begins_with("Half-Death's Harvest raised"), h[0].text)
	# Against only a Free Hold, the reduced Harvest.
	var fh := _game({"rulers": true, "independents": true}, {WAKE: "the_long_procession"})
	var hold := ""
	for pid in fh.find_province(_home(fh)).neighbors:
		if fh.garrison_at(pid) != null:
			hold = pid
	assert_false(hold.is_empty(), "a Free Hold next door")
	var fhalf := RulerRules.ruler_army(fh, WAKE)
	var fline := fh.find_army("candlewake-1")
	var rf := _turn(fh, {WAKE: [MoveOrder.new(fhalf.id, hold), MoveOrder.new(fline.id, hold)]})
	var fhv := _events_of(rf, "harvest")
	if rf.new_state.find_province(hold).owner == WAKE:
		assert_eq(int(fhv[0].numbers.count), int(RulerData.ABILITIES.harvest.free_hold), "a Free Hold yields the reduced Harvest")


func test_battle_facts_read_the_turns_battles() -> void:
	var events := [{"type": "battle", "armies": ["candlewake-1", "kingdom-3"], "numbers": {"destroyed": ["kingdom-3"]}},
		{"type": "border_battle", "armies": ["candlewake-2", "kingdom-4"], "numbers": {"destroyed": ["candlewake-2"]}},
		{"type": "recruited", "armies": ["candlewake-5"], "numbers": {}}]
	var facts := WickRules.battle_facts(events)
	assert_eq(facts.fought.keys(), ["candlewake-1", "kingdom-3", "candlewake-2", "kingdom-4"])
	assert_eq(facts.won.keys(), ["candlewake-1", "kingdom-4"], "the armies that fought and were not destroyed won")
