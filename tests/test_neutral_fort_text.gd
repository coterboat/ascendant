extends "res://tests/test_case.gd"
## MVP-3 (#177) item 13: a neutral fort's battle says what the rule does. SiegeRules.next_battle makes the Free Holds
## garrison of a neutral fort the holder: it meets you in the open and defends, so it gets the province's terrain bonus,
## but no walls and no cover (nobody owns the fort to man them). Every line of the battle used to say "nobody holds the
## ground": the opening sentence, both side roles, the chip, the plate over the walls and the caption, and the move
## forecast said the fort would be taken unopposed. Here every one of them follows the rule. The rule itself is not
## changed, and a game without independents is: no "holder" key in any siege block, no new words in any line (the
## byte-identical replays live in test_sieges_off and friends).
## Expected numbers and words come from the data (AutoBattleResolver.TERRAIN, IndependentData), never from this file.

const F := preload("res://tests/siege_fixtures.gd")
const Walls := preload("res://world3d/battle_walls.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const HOLDS := IndependentData.FACTION_ID


## A game with sieges and independents, a Crown army of five next to `fort` (a neutral fort), the way into it made.
func _game(seed_value: int = 13) -> Dictionary:
	var s := GameState.with_sieges(seed_value, {}, {})
	assert_true(s.setup_independents([]))
	var fort := ""
	for p in s.provinces:
		if p.owner.is_empty() and p.fort_level > 0:
			fort = p.id
			break
	assert_ne(fort, "", "the map has a neutral fort")
	var from: String = s.find_province(fort).neighbors[0]
	var neighbor := s.find_province(from)
	if neighbor.owner.is_empty():  # the way in is the Crown's: its garrison is gone
		neighbor.owner = CROWN
		s.armies = s.armies.filter(func(a): return a.id != IndependentData.army_id(from))
	var army := Army.new()
	army.id = s.new_army_id(CROWN)
	army.owner = CROWN
	army.location = from
	for i in 5:
		army.units.append(Unit.new(s.find_faction(CROWN).unit_types[i % 3], CROWN))
	s.armies.append(army)
	return {"state": s, "fort": fort, "army": army}


func _battle(g: Dictionary, seed_value: int = 5) -> Dictionary:
	var result := TurnResolver.resolve(g.state, {CROWN: [MoveOrder.new(g.army.id, g.fort)]}, seed_value, AutoBattleResolver.new())
	for e in result.events:
		if e.type == "battle" and e.provinces.has(g.fort):
			return e
	fail("the move into %s started a battle" % g.fort)
	return {}


func _plan(g: Dictionary) -> Dictionary:
	var s: GameState = g.state
	var moved := {g.army.id: true}
	s.find_army(g.army.id).location = g.fort
	return SiegeRules.next_battle(s, g.fort, moved, {"storms": {}, "sallies": {}})


# --- the rule: what the garrison gets -------------------------------------------------------------------------

func test_the_garrison_is_the_holder_and_the_block_says_which_side() -> void:
	var g := _game()
	var plan := _plan(g)
	assert_eq(String(plan.kind), SiegeRules.OPEN, "a battle in the open, not a storm")
	assert_eq(String(plan.defender), HOLDS, "the Free Holds garrison defends (IND-1)")
	var sides: Array = plan.sides.keys()
	sides.sort()
	assert_eq(int(plan.siege.holder), sides.find(HOLDS), "the block names the garrison's side, in faction id order")
	assert_eq(int(plan.siege.walls_defense), 0, "no walls for the garrison")
	assert_eq(int(plan.siege.cover_defense), 0, "and no cover")
	assert_eq(int(plan.siege.garrison), -1, "nobody owns the fort")


func test_the_garrison_gets_the_terrain_and_nothing_from_the_fort() -> void:
	var g := _game()
	var e := _battle(g)
	var lg: Dictionary = e.numbers.log
	var terrain := String(lg.terrain)
	var holds_side := -1
	for si in lg.sides.size():
		if bool(lg.sides[si].defender):
			holds_side = si
	assert_eq(String(lg.sides[holds_side].faction), HOLDS, "the garrison is the defender")
	var bonus: Dictionary = AutoBattleResolver.TERRAIN.get(terrain, {})
	var on_holder := 0
	for ev in lg.events:
		if ev.t != "attack":
			continue
		var parts: Dictionary = ev.defense.parts
		for key in ["walls", "cover", "fort"]:
			assert_false(parts.has(key), "no %s part in any attack (%s)" % [key, JSON.stringify(parts)])
		var target_side := int(lg.fighters[int(ev.to)].side)
		assert_eq(parts.has("terrain"), target_side == holds_side and int(bonus.get("defense", 0)) > 0,
			"the %s's defense bonus is the garrison's alone" % terrain)
		if target_side == holds_side:
			on_holder += 1
	assert_true(on_holder > 0, "the garrison was attacked")
	assert_eq(BattleLog.validate(lg), [], "the log of the battle is valid with a defender in the open (the holder)")
	assert_eq(JSON.stringify(lg.siege), JSON.stringify(e.numbers.report.siege), "log and report carry the same block")


func test_a_game_without_independents_keeps_the_old_block_and_sentence() -> void:
	# Two real factions meeting at an empty fort: nobody holds the ground, and the block has no "holder" key.
	var s := F.state([["kingdom-1", CROWN, "stonegate", F.units("spearmen", 3)], ["beasts-1", CLANS, "stonegate", F.units("tuskers", 3)]], {})
	var plan := SiegeRules.next_battle(s, "stonegate", {"kingdom-1": true, "beasts-1": true}, {"storms": {}, "sallies": {}})
	assert_eq(String(plan.kind), SiegeRules.OPEN)
	assert_false(plan.siege.has("holder"), "no holder without a garrison")
	var line := AutoBattleResolver.siege_sentence(plan.siege, "Stonegate", ["Aurel Crown", "Thornmane Clans"], "hills")
	assert_eq(line, "At Stonegate, the Aurel Crown and Thornmane Clans arrived together before the empty fort, where nobody holds the ground.")
	assert_eq(FortView.siege_role(plan.siege, 0), "outside the walls")
	assert_eq(FortView.siege_chip(plan.siege).text, "Outside the walls: nobody holds the ground")
	assert_eq(Walls.caption_text(plan.siege, "Stonegate", "hills", ""), "Outside the walls of Stonegate nobody holds the ground: no walls, no terrain, no cover for anyone.")
	assert_eq(Walls.plate_text(plan.siege), "Outside the walls: no cover for anyone")


# --- the lines say it ----------------------------------------------------------------------------------------

func test_the_opening_line_says_the_garrison_held_the_ground_with_its_terrain() -> void:
	var g := _game()
	var e := _battle(g)
	var terrain := String(e.numbers.log.terrain)
	var ground := AutoBattleResolver.ground_words(terrain)
	assert_ne(ground, "", "the terrain has words")
	var first: String = e.numbers.report.lines[0]
	var holds_name := String(g.state.find_faction(HOLDS).faction_name)
	var crown_name := String(g.state.find_faction(CROWN).faction_name)
	var fort_word := String(e.numbers.siege.fort)
	var opening := "At %s, the %s garrison met the %s before its %s, holding the ground (%s)." % [
		String(g.state.find_province(g.fort).name), holds_name, crown_name, fort_word, ground]
	assert_true(first.begins_with(opening), "the report opens: %s" % first)
	assert_true(String(e.text).begins_with(opening), "so does the event's own sentence: %s" % e.text)
	for text in [first, String(e.text)]:
		assert_false(text.contains("nobody holds the ground"), "the old words are gone: %s" % text)
		assert_false(text.contains("empty fort"), text)
	assert_true(first.contains("%s (holding the ground)" % holds_name), "the garrison's side header: %s" % first)
	assert_true(first.contains("%s (attacking)" % crown_name), "the attackers' side header: %s" % first)
	assert_false(first.contains("outside the walls"), "neither side is 'outside the walls': %s" % first)


func test_the_chip_the_roles_the_plate_and_the_caption_follow_the_rule() -> void:
	var g := _game()
	var e := _battle(g)
	var siege: Dictionary = e.numbers.siege
	var holder := int(siege.holder)
	assert_eq(FortView.siege_role(siege, holder), "holding the ground")
	assert_eq(FortView.siege_role(siege, 1 - holder), "attacking")
	for side in 2:
		var meaning := FortView.role_meaning(siege, side)
		assert_false(String(meaning.text).contains("nobody holds the ground"), "side %d: %s" % [side, meaning.text])
		assert_true(RulesCodex.ENTRIES.has(String(meaning.codex)), "its codex entry exists")
	var chip := FortView.siege_chip(siege)
	assert_eq(String(chip.text), "Holds the ground: no walls, no cover")
	assert_false(String(chip.text).contains("nobody holds"), String(chip.text))
	assert_true(RulesCodex.ENTRIES.has(String(chip.codex)))
	assert_true(String(chip.tip).length() > 40, "it explains itself on hover")
	assert_eq(Walls.plate_text(siege), String(chip.text), "the plate over the walls says the same")
	var terrain := String(e.numbers.log.terrain)
	var place := String(g.state.find_province(g.fort).name)
	var caption := Walls.caption_text(siege, place, terrain, "Free Holds")
	assert_true(caption.contains("holds the ground") and caption.contains(AutoBattleResolver.ground_words(terrain)), caption)
	assert_true(caption.contains("no walls") and caption.contains("no cover"), caption)
	assert_false(caption.contains("nobody holds the ground") or caption.contains("no terrain"), caption)


func test_the_battle_view_headers_and_hover_texts_follow_the_rule() -> void:
	var g := _game()
	var e := _battle(g)
	var siege: Dictionary = e.numbers.siege
	var v := BattleSimpleView.new()
	assert_eq(v.show_battle(e.numbers.log, e.numbers.report), "", "the battle plays")
	var sides: Array = e.numbers.log.sides
	for si in sides.size():
		var k := v._slot_of_side(si)
		var role := FortView.siege_role(siege, si)
		assert_eq(String(v.role_chips[k].text), role, "side %d's plate has its role chip: %s" % [si, v.role_chips[k].text])
		assert_true(String(v.plaque_labels[k].tooltip_text).contains(role), "and its tooltip says it: %s" % v.plaque_labels[k].tooltip_text)
	for text in v.visible_texts():
		assert_false(String(text).contains("nobody holds the ground"), "nothing on the screen says so: %s" % text)
		assert_false(String(text).contains("outside the walls"), "nor that anyone is outside the walls: %s" % text)
	v.free()


# --- the move forecast ----------------------------------------------------------------------------------------

func test_the_move_forecast_says_there_is_a_battle_not_an_unopposed_capture() -> void:
	var g := _game()
	var s: GameState = g.state
	var f := Forecast.move(s, CROWN, MoveOrder.new(g.army.id, g.fort), [])
	assert_true(f.ok)
	assert_eq(String(f.siege_row), "holds")
	assert_false(f.would_capture, "a garrison stands in the way: nothing is taken for free")
	assert_true(f.enemy_present)
	var text := String(f.text)
	assert_false(text.contains("unopposed") or text.contains("Nobody is inside"), text)
	var fort := s.find_province(g.fort)
	assert_true(text.contains("holds it for the %s" % IndependentData.FACTION_NAME), text)
	assert_true(text.contains(Forecast.neutral_fort_ground(fort)), "the ground it holds, from the data: %s" % text)
	assert_true(text.contains("no walls, no cover"), text)
	assert_true(text.contains("recruit there from turn %d" % (int(f.arrival_turn) + FortData.CAPTURE_WAIT)), text)
	# The same forecast with the garrison gone (or without independents) is the old one.
	var empty: GameState = s.duplicate_state() if s.has_method("duplicate_state") else GameState.from_dict(s.to_dict())
	empty.armies = empty.armies.filter(func(a): return a.id != IndependentData.army_id(g.fort))
	var f2 := Forecast.move(empty, CROWN, MoveOrder.new(g.army.id, g.fort), [])
	assert_eq(String(f2.siege_row), "empty")
	assert_true(f2.would_capture)
	assert_true(String(f2.text).contains("Nobody is inside"), f2.text)


func test_the_move_preview_and_the_order_line_are_the_garrisons_forecast() -> void:
	var g := _game()
	var s: GameState = g.state
	var ctrl := OrdersController.new(s, CROWN)
	assert_eq(ctrl.siege_kind(g.army.id, g.fort), "", "not a siege, a relief or an empty fort: an ordinary move into a defended province")
	var preview := ctrl.move_preview(g.army.id, g.fort)
	assert_true(preview.ok)
	assert_true(String(preview.text).contains("holds it for the %s" % IndependentData.FACTION_NAME), preview.text)
	assert_false(String(preview.text).contains("Take the fort"), preview.text)
	assert_eq(ctrl.queue_move(g.army.id, g.fort), "", "the move is ordered")
	assert_eq(ctrl.orders().size(), 1, "and listed")
	var line := ctrl.order_text(0)
	assert_true(line.contains("holds it for the %s" % IndependentData.FACTION_NAME), line)
	assert_false(line.contains("Take the fort") or line.contains("unopposed"), line)


# --- the aftermath words -------------------------------------------------------------------------------------

func test_a_players_aftermath_has_no_promise_of_a_feature() -> void:
	var record := "Aurel Crown routed, and its army was destroyed as it fled (5 fighters lost; there are no retreats yet)."
	assert_eq(TurnReportText.readable_aftermath(record), "Aurel Crown routed, and its army was destroyed as it fled (5 fighters lost).")
	assert_eq(TurnReportText.readable_aftermath("It was wiped out (there are no retreats yet)."), "It was wiped out.")
	assert_eq(TurnReportText.readable_aftermath("Nothing to change here."), "Nothing to change here.")
	# The turn report's own loser line (a battle resolved with the real rules): no "no retreats yet" in what the player reads.
	var g := _game()
	var result := TurnResolver.resolve(g.state, {CROWN: [MoveOrder.new(g.army.id, g.fort)]}, 5, AutoBattleResolver.new())
	for e in result.events:
		if e.type == "battle":
			var line := TurnReportText.line(e, result.events, result.new_state)
			assert_false(line.contains("no retreats yet"), line)


# --- item 2: the first garrison battle explains itself -------------------------------------------------------------

## A Crown army marches into the plain neutral province `target` of a game with independents (no sieges): a battle with its garrison.
func _garrison_battle(target: String) -> Dictionary:
	var s := GameState.new(11)
	assert_true(s.setup_independents([]))
	var army: Army = s.armies.filter(func(a): return a.owner == CROWN)[0]
	var result := TurnResolver.resolve(s, {CROWN: [MoveOrder.new(army.id, target)]}, 5, AutoBattleResolver.new())
	for e in result.events:
		if e.type == "battle" and e.provinces.has(target):
			return e
	fail("a battle at %s" % target)
	return {}


func test_the_new_captions_fit_the_strip_under_the_stage() -> void:
	# The caption strip shows the first-battle hint whole; a caption a few characters longer is cut with "...". Every province's
	# own garrison caption and (for a fort) walls caption, with its real terrain and name, stays inside that.
	var room := BattleSimpleView.FIRST_HINT.length() + 5
	var longest := 0
	for p in MapData.PROVINCES:
		var garrison := {"defender": HOLDS, "kind": "province", "terrain": p.terrain, "provinces": [p.id], "fort": bool(p.has_fort),
			"sides": [{"faction": HOLDS, "name": IndependentData.FACTION_NAME}]}
		var line := BattleSimpleView.garrison_caption_for(garrison)
		assert_ne(line, "", "%s has a garrison caption" % p.name)
		longest = maxi(longest, line.length())
		var walls := Walls.caption_text({"kind": "open", "why": "empty", "holder": 0, "cover_defense": 0}, String(p.name), String(p.terrain), IndependentData.FACTION_NAME)
		longest = maxi(longest, walls.length())
		assert_true(line.length() <= room and walls.length() <= room, "%s: %d and %d characters against room for %d" % [p.name, line.length(), walls.length(), room])
	assert_true(longest > 60, "the captions say something (%d characters at most)" % longest)


func test_a_side_the_reader_never_saw_still_has_a_subject() -> void:
	var s := GameState.new(3)
	assert_true(s.setup_independents([]))
	var ctx := {"state": s, "rulers": {}, "owners": {}}
	var side := {"entries": [], "armies": []}
	var subject := TurnReportText._side_subject(side, ctx, HOLDS)
	assert_eq(String(subject.text), "%s army" % TurnReportText._possessive(IndependentData.FACTION_NAME), "named by its faction, not left empty")
	assert_eq(String(TurnReportText._side_subject(side, ctx).text), "", "without a faction there is nothing to say, as before")


func test_the_first_garrison_battle_says_who_the_free_holds_are_and_what_they_hold() -> void:
	var e := _garrison_battle("westwatch")
	var lg: Dictionary = e.numbers.log
	var line := BattleSimpleView.garrison_caption_for(lg)
	assert_ne(line, "", "a battle against a garrison has its caption")
	var ground := AutoBattleResolver.ground_words(String(lg.terrain))
	assert_true(line.contains(IndependentData.FACTION_NAME) and line.contains("Westwatch") and line.contains(ground), line)
	assert_true(line.contains("the neutral land's own fighters"), line)
	# It is on the screen before the first blow, linked to the codex, and gone once the round captions start.
	var v := BattleSimpleView.new()
	assert_eq(v.show_battle(lg, e.numbers.report), "")
	assert_eq(String(v.caption_labels[1].text), line, "under the first caption")
	assert_true(String(v.caption_labels[1].tooltip_text).length() > 80, "with the rule behind it on hover")
	assert_eq(CodexLink.key_at(v.caption_labels[1]), "independents", "and a link to its codex entry")
	v.free()
	# A battle that is not against a garrison has no such line.
	var plain := TurnResolver.resolve(GameState.new(11), {CROWN: [MoveOrder.new("kingdom-1", "westwatch")]}, 5, AutoBattleResolver.new())
	assert_eq(plain.events.filter(func(x): return x.type == "battle").size(), 0, "without independents the neutral province is just taken")
	var between := lg.duplicate(true)
	between.defender = ""
	assert_eq(BattleSimpleView.garrison_caption_for(between), "", "nobody holds it: no line")
	between.defender = CROWN
	assert_eq(BattleSimpleView.garrison_caption_for(between), "", "the Crown holding it: no line")
