extends "res://tests/test_case.gd"
## Each faction numbers its own armies (#94, after #55's army names): kingdom-1, kingdom-2, beasts-1, ... in
## the order each raises them, never reused. The counters are part of the game state and the save, so a loaded
## game keeps counting; an older save without them takes each faction's next number from its highest army id.


## A state with one recruit order for `fid` at an empty capital, resolved: the new army's id.
func _raise(s: GameState, fid: String) -> Dictionary:
	var cap := s.find_faction(fid).capital
	for a in s.armies:
		if a.owner == fid and a.location == cap and a.ruler == null:
			a.location = s.find_province(cap).neighbors[0]  # out of the way, so the recruit forms a new army
	s.find_faction(fid).gold = 1000
	var r := TurnResolver.resolve(s, {fid: [RecruitOrder.new(s.find_faction(fid).unit_types[0].id)]}, TurnResolver.seed_for_turn(s))
	var made: Array = r.new_state.armies.filter(func(a): return s.find_army(a.id) == null)
	assert_eq(made.size(), 1, "one new army")
	return {"state": r.new_state, "id": made[0].id if not made.is_empty() else ""}


func test_each_faction_counts_its_own_armies_from_one() -> void:
	var s := GameState.new(7)
	assert_eq(s.armies.map(func(a): return a.id), ["kingdom-1", "beasts-1"], "both starting armies are number 1")
	assert_eq(s.next_army_ids, {"kingdom": 2, "beasts": 2})
	var r := GameState.with_rulers(7)
	var ids: Array = r.armies.map(func(a): return a.id)
	assert_eq(ids, ["kingdom-1", "beasts-1", "kingdom-2", "beasts-2"], "the rulers' armies come second")
	assert_eq(TurnReportText.army_name(s, "beasts-1"), "the Clans' 1st", "the Clans' first army is their 1st")
	assert_eq(TurnReportText.army_name(s, "kingdom-1"), "the Crown's 1st")


func test_new_armies_continue_the_count_and_numbers_are_never_reused() -> void:
	var s := GameState.new(7)
	var first := _raise(s, "kingdom")
	assert_eq(first.id, "kingdom-2", "the Crown's next number")
	var second := _raise(first.state, "beasts")
	assert_eq(second.id, "beasts-2", "the Clans count on their own: the Crown's armies don't take their numbers")
	# An army that is gone keeps its number: the next one is never given it again.
	var s3: GameState = second.state
	s3.armies = s3.armies.filter(func(a): return a.id != "kingdom-2")
	var third := _raise(s3, "kingdom")
	assert_eq(third.id, "kingdom-3", "kingdom-2 is gone, and its number is not reused")
	# An id already in use is skipped, so ids stay unique even when the counter is behind.
	var t := GameState.new(7)
	t.next_army_ids["kingdom"] = 1
	assert_eq(t.new_army_id("kingdom"), "kingdom-2")
	assert_eq(t.next_army_ids.kingdom, 3)


func test_the_counters_are_saved_and_loaded() -> void:
	var s: GameState = _raise(GameState.with_rulers(7), "kingdom").state
	var d := s.to_dict()
	assert_eq(d.next_army_ids, {"kingdom": 4, "beasts": 3})
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_true(loaded != null)
	assert_eq(loaded.next_army_ids, s.next_army_ids, "a save keeps each faction's count")
	assert_eq(typeof(loaded.next_army_ids.kingdom), TYPE_INT)
	assert_eq(JSON.stringify(loaded.to_dict()), JSON.stringify(d), "and saves again exactly")
	assert_eq(loaded.new_army_id("kingdom"), "kingdom-4")
	assert_eq(loaded.new_army_id("beasts"), "beasts-3")
	# Deterministic: the same game gives the same ids.
	assert_eq(JSON.stringify(_raise(GameState.with_rulers(7), "kingdom").state.to_dict()), JSON.stringify(d))


func test_an_old_save_without_the_counters_still_loads() -> void:
	# Saves from before #94 kept one counter for the whole map ("next_army_id") and ids from it.
	var s := GameState.new(7)
	var d := s.to_dict()
	d.erase("next_army_ids")
	d["next_army_id"] = 9
	d.armies[0].id = "kingdom-7"
	d.armies[1].id = "beasts-2"
	var errors := []
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(d)), errors)
	assert_eq(errors, [])
	assert_true(loaded != null, "an old save loads")
	assert_eq(loaded.next_army_ids, {"kingdom": 8, "beasts": 3}, "each faction goes on from its highest number")
	assert_eq(loaded.new_army_id("beasts"), "beasts-3")
	assert_false(loaded.to_dict().has("next_army_id"), "saved again, it has the new counters")
	# A faction with no army in an old save starts at 1.
	d.armies.remove_at(1)
	var lone := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(lone.next_army_ids.beasts, 1)
	# A counter of the wrong type is a plain-language load error, not a script error.
	var bad := s.to_dict()
	bad.next_army_ids = "lots"
	var why := []
	assert_eq(GameState.from_dict(bad, why), null)
	assert_false(why.is_empty())
