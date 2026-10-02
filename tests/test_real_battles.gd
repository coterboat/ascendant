extends "res://tests/test_case.gd"
## Tests for closing #4: the game fights real battles by default (AutoBattleResolver), and no
## player-facing text still describes the old placeholder battle. Also the luck wording in the "why"
## summary, and that a losing side's destruction is spelled out.


# --- fixtures -------------------------------------------------------------------------------------

## A fresh state with the starting armies replaced by `specs`: [[id, owner, location, [unit ids]], ...].
func _state(specs: Array, owners: Dictionary = {}) -> GameState:
	var s := GameState.new(99)
	s.armies.clear()
	for spec in specs:
		_add_army(s, spec)
	for pid in owners:
		s.find_province(pid).owner = owners[pid]
	return s


func _add_army(s: GameState, spec: Array) -> void:
	var a := Army.new()
	a.id = spec[0]
	a.owner = spec[1]
	a.location = spec[2]
	var f := s.find_faction(a.owner)
	for type_id in spec[3]:
		var ut := TurnResolver.recruitable_type(f, type_id)
		if ut.is_commander:
			a.commander = Unit.new(ut, f.id)
		else:
			a.units.append(Unit.new(ut, f.id))
	s.armies.append(a)


func _battles(events: Array) -> Array:
	return events.filter(func(e): return e.type == "battle" or e.type == "border_battle")


func _side(report: Dictionary, fid: String) -> Dictionary:
	for sr in report.sides:
		if sr.faction == fid:
			return sr
	return {}


func _hp_of(s: GameState, fid: String) -> int:
	var total := 0
	for a in s.armies:
		if a.owner == fid:
			for u in a.units:
				total += u.current_hp
			if a.commander:
				total += a.commander.current_hp
	return total


## Every kind of battle the turn resolver starts, fought with the default resolver over a few seeds:
## a holder against an arrival (forest), two arrivals (hills), and a border swap.
func _default_battle_events() -> Array:
	var out := []
	var cases := [
		[_state([["kingdom-1", "kingdom", "thornvale", ["spearmen", "spearmen", "crossbowmen", "knight_captain"]],
			["beasts-2", "beasts", "wildmoor", ["tuskers", "fangthrowers"]]], {"thornvale": "kingdom"}),
			{"beasts": [MoveOrder.new("beasts-2", "thornvale")]}],
		[_state([["kingdom-1", "kingdom", "crownkeep", ["knights", "spearmen"]],
			["beasts-2", "beasts", "thornvale", ["war_bear"]]]),
			{"kingdom": [MoveOrder.new("kingdom-1", "highcrag")], "beasts": [MoveOrder.new("beasts-2", "highcrag")]}],
		[_state([["kingdom-1", "kingdom", "thornvale", ["spearmen", "crossbowmen"]],
			["beasts-2", "beasts", "wildmoor", ["tuskers"]]], {"thornvale": "kingdom", "wildmoor": "beasts"}),
			{"kingdom": [MoveOrder.new("kingdom-1", "wildmoor")], "beasts": [MoveOrder.new("beasts-2", "thornvale")]}],
	]
	for c in cases:
		for turn_seed in range(1, 9):
			out.append_array(_battles(TurnResolver.resolve(c[0], c[1], turn_seed).events))
	return out


# --- the default is the real battle -------------------------------------------------------------

func test_default_resolver_is_the_real_one() -> void:
	var s := _state([
		["kingdom-1", "kingdom", "thornvale", ["spearmen", "spearmen", "crossbowmen", "knight_captain"]],
		["beasts-2", "beasts", "wildmoor", ["tuskers", "fangthrowers"]],
	], {"thornvale": "kingdom"})
	var orders := {"beasts": [MoveOrder.new("beasts-2", "thornvale")]}
	var winner_paid := 0
	for turn_seed in range(1, 25):
		var r := TurnResolver.resolve(s, orders, turn_seed)
		var explicit := TurnResolver.resolve(s, orders, turn_seed, AutoBattleResolver.new())
		assert_eq(var_to_str(r.events), var_to_str(explicit.events), "no resolver means AutoBattleResolver (seed %d)" % turn_seed)
		assert_eq(var_to_str(r.new_state.to_dict()), var_to_str(explicit.new_state.to_dict()))
		var battles := _battles(r.events)
		assert_eq(battles.size(), 1)
		var e: Dictionary = battles[0]
		var report: Dictionary = e.numbers.report
		assert_false(report.is_empty(), "the battle report is attached to the event as numbers.report")
		assert_eq(report.winner, e.numbers.winner)
		assert_false(String(report.why).is_empty())
		assert_true(e.text.contains(report.why), "the event text carries the why")
		var winner: String = e.numbers.winner
		var start_hp: int = _side(report, winner).hp_start
		if _side(report, winner).fighters_lost > 0 or _hp_of(r.new_state, winner) < start_hp:
			winner_paid += 1
	# The placeholder battle never cost the winner anything; real battles do.
	assert_true(winner_paid > 0, "a battle can cost the winner units or hp (%d of 24 seeds did)" % winner_paid)


func test_game_session_fights_real_battles_by_default() -> void:
	var s := _state([
		["kingdom-1", "kingdom", "thornvale", ["spearmen", "crossbowmen"]],
		["beasts-2", "beasts", "wildmoor", ["tuskers"]],
	], {"thornvale": "kingdom", "wildmoor": "beasts"})
	var session := GameSession.new(s, ["kingdom", "beasts"], 5)  # no battle resolver passed
	assert_eq(session.setup_errors(), [])
	assert_eq(session.end_turn(), "")
	assert_eq(session.acknowledge_handoff(), "")
	assert_eq(session.queue_order(MoveOrder.new("beasts-2", "thornvale")), "")
	assert_eq(session.end_turn(), "")
	var battles := session.battle_events()
	assert_eq(battles.size(), 1, "the beasts attack the held province")
	if battles.size() == 1:
		assert_false(battles[0].numbers.report.is_empty(), "the session's battle has a real battle report")


# --- no player-facing text describes the placeholder battle ---------------------------------------

## Phrases only the placeholder battle used: ties going to the defender, and "strength N" totals.
const TIE_TO_DEFENDER := "(?i)(wins? ties|ties? go(es)? to the defender|tied?,? the defender|defenders? wins?[^.]*\\btie|strengths? (are|is|were) tied)"


func _player_texts() -> Array:
	var texts := []
	for key in RulesCodex.ENTRIES:
		texts.append(RulesCodex.entry(key).title)
		texts.append(RulesCodex.text(key))
	# Move forecasts into enemy-held provinces of every kind of ground, with and without a fort.
	var s := _state([
		["kingdom-1", "kingdom", "highcrag", ["spearmen"]],
		["kingdom-2", "kingdom", "westwatch", ["spearmen"]],
		["kingdom-3", "kingdom", "rivermarch", ["spearmen"]],
		["beasts-4", "beasts", "thornvale", ["tuskers"]],
		["beasts-5", "beasts", "stonegate", ["tuskers"]],
		["beasts-6", "beasts", "crownkeep", ["tuskers"]],
		["beasts-7", "beasts", "greenglade", ["tuskers"]],
	])
	for order in [MoveOrder.new("kingdom-1", "thornvale"), MoveOrder.new("kingdom-2", "stonegate"),
			MoveOrder.new("kingdom-1", "crownkeep"), MoveOrder.new("kingdom-3", "greenglade")]:
		var f := Forecast.move(s, "kingdom", order)
		assert_true(f.ok and f.enemy_present, f.text)
		texts.append(f.text)
	texts.append(Forecast.battle_odds(s, "kingdom", ["kingdom-1"], "thornvale").text)
	texts.append(Breakdown.army_strength(s, "kingdom-1").description)
	for e in _default_battle_events():
		texts.append(e.text)
		texts.append_array(e.numbers.report.lines)
	return texts


func test_no_player_facing_text_says_ties_go_to_the_defender() -> void:
	var tie := RegEx.create_from_string(TIE_TO_DEFENDER)
	var strength_n := RegEx.create_from_string("(?i)strength \\d")
	var texts := _player_texts()
	assert_true(texts.size() > 40, "the scan covers codex, forecasts, tooltips and battle events")
	for t in texts:
		assert_true(tie.search(t) == null, "says ties go to the defender: %s" % t)
		assert_true(strength_n.search(t) == null, "shows a placeholder strength number: %s" % t)
	# The hold entry states the defender's real advantages instead.
	var hold := RulesCodex.text("hold")
	assert_true(hold.contains("terrain") and hold.contains("8 rounds"), hold)


func test_move_forecast_names_the_defenders_real_ground() -> void:
	var s := GameState.new(1)
	assert_eq(Forecast.defender_ground(s.find_province("thornvale")), "the forest gives it +2 defense")
	assert_eq(Forecast.defender_ground(s.find_province("highcrag")), "the hills give it +1 defense and +1 attack")
	assert_eq(Forecast.defender_ground(s.find_province("stonegate")), "the hills give it +1 defense and +1 attack, and its fort gives +2 defense")
	assert_eq(Forecast.defender_ground(s.find_province("rivermarch")), "open plains give no terrain bonus")
	assert_eq(Forecast.defender_ground(s.find_province("crownkeep")), "open plains give no terrain bonus, but its fort gives +2 defense")
	# The numbers are the battle's own.
	assert_eq(AutoBattleResolver.TERRAIN.forest.defense, 2)
	assert_eq(AutoBattleResolver.FORT_DEFENSE, 2)


func test_no_player_facing_codex_entry_describes_the_stub() -> void:
	var stub_phrases := ["placeholder", "stub", "until full battles", "takes no losses", "higher strength wins",
		"strengths are tied", "on a tie the defender", "win ties"]
	for key in RulesCodex.ENTRIES:
		var seen := ("%s %s" % [RulesCodex.entry(key).title, RulesCodex.text(key)]).to_lower()
		for phrase in stub_phrases:
			assert_false(seen.contains(phrase), "codex entry %s describes the placeholder battle (%s)" % [key, phrase])
	# The strength tooltip explains what that number is now: a size guide, not the battle rule.
	var tip: String = Breakdown.army_strength(GameState.new(1), "kingdom-1").description
	assert_eq(tip, RulesCodex.text("army_strength"))
	assert_true(tip.contains("does not decide battles"), tip)


# --- luck is described in the damage terms it is measured in ---------------------------------------

func _possessive(name: String) -> String:
	return name + ("'" if name.ends_with("s") else "'s")


## Checks one luck clause against the report's own numbers. Returns true when the clause names a
## side as doing more damage than average rolls would while that side hit less often than expected.
func _check_luck_clause(text: String, report: Dictionary) -> bool:
	for word in ["favored", "luck was with", "dice", "lucky"]:
		assert_false(text.contains(word), "luck wording claims more than it measures: %s" % text)
	var claims := 0
	var tricky := false
	for sr in report.sides:
		var shown: float = sr.damage_dealt - sr.damage_expected  # the numbers the report shows
		var who := _possessive(sr.name)  # faction names are plain words: nothing to escape
		var main := RegEx.create_from_string("%s hits did about (\\d+) (more|less) damage than average rolls would" % who).search(text)
		var second := RegEx.create_from_string(", and %s about (?:(\\d+) (more|less)|as much)" % who).search(text)
		for m in [main, second]:
			if m == null:
				continue
			claims += 1
			if m.get_string(2).is_empty():
				assert_true(absf(shown) <= 1.0, "%s: 'about as much' but dealt %d against %.1f expected" % [text, sr.damage_dealt, sr.damage_expected])
				continue
			var amount: int = int(m.get_string(1))
			var more: bool = m.get_string(2) == "more"
			assert_true(shown > 0.0 if more else shown < 0.0, "%s: '%s' but dealt %d against %.1f expected" % [text, m.get_string(2), sr.damage_dealt, sr.damage_expected])
			assert_true(absf(absf(shown) - amount) <= 1.0, "%s: about %d, the report shows %.1f" % [text, amount, shown])
			if more and m == main and sr.hit_rate < sr.expected_hit_rate:
				tricky = true
		# Hit rates are separate facts and match the report exactly.
		var rate := "%s %d%% (about %d%% expected)" % [sr.name, sr.hit_rate, sr.expected_hit_rate]
		assert_true(text.contains(rate), "%s: hit rates should include '%s'" % [text, rate])
	if text.contains("both sides' hits did about as much damage"):
		claims += 2
		for sr in report.sides:
			assert_true(absf(sr.damage_dealt - sr.damage_expected) <= 1.0, text)
	assert_eq(claims, 2, "the clause compares two sides in damage: %s" % text)
	return tricky


func test_luck_wording_matches_the_numbers() -> void:
	var matchups := [
		[["knights", "knights", "spearmen"], ["tuskers", "tuskers", "fangthrowers"], "highcrag"],
		[["spearmen", "spearmen", "crossbowmen", "knight_captain"], ["tuskers", "tuskers", "fangthrowers"], "thornvale"],
		[["spearmen", "crossbowmen", "knights", "knight_captain"], ["tuskers", "fangthrowers", "war_bear", "warchief"], "rivermarch"],
		[["crossbowmen", "crossbowmen", "spearmen"], ["war_bear"], "greenglade"],
		[["knights", "spearmen", "spearmen"], ["war_bear", "fangthrowers"], "stonegate"],
	]
	var checked := 0
	var tricky := 0
	for m in matchups:
		for sd in range(1, 41):
			var s := _state([["d-1", "kingdom", m[2], m[0]], ["a-1", "beasts", m[2], m[1]]])
			var r := AutoBattleResolver.resolve(s.find_army("a-1"), s.find_army("d-1"), s.find_province(m[2]), SeededRNG.new(sd), s)
			var report: Dictionary = r.report
			var luck: Array = report.all_factors.filter(func(f): return f.id == "luck")
			assert_eq(luck.size(), 1, "every battle measures luck")
			if luck.is_empty():
				continue
			checked += 1
			if _check_luck_clause(luck[0].text, report):
				tricky += 1
			for f in report.factors:
				if f.id == "luck":
					assert_eq(f.text, luck[0].text, "the why uses the same luck clause")
					assert_true(report.why.contains(f.text))
	assert_eq(checked, 200)
	# The case that used to read "the dice favored X" while X hit less often than expected: big hits
	# landing outweighed small misses. Now it is stated in damage, with the hit rates beside it.
	assert_true(tricky > 0, "the sweep includes a side that did more damage than average while hitting less often")


# --- losing sides are destroyed, and the text says how --------------------------------------------

func test_routed_side_is_destroyed_and_the_text_says_so() -> void:
	var s := _state([
		["kingdom-1", "kingdom", "rivermarch", ["crossbowmen", "crossbowmen", "crossbowmen"]],
		["beasts-2", "beasts", "greenglade", ["war_bear", "warchief"]],
	], {"rivermarch": "kingdom"})
	var routs := 0
	for turn_seed in range(1, 21):
		var r := TurnResolver.resolve(s, {"beasts": [MoveOrder.new("beasts-2", "rivermarch")]}, turn_seed)
		var e: Dictionary = _battles(r.events)[0]
		var k := _side(e.numbers.report, "kingdom")
		if e.numbers.winner != "beasts" or not k.routed:
			continue
		routs += 1
		assert_true(k.hp_end > 0, "a routed side still had fighters standing")
		assert_eq(r.new_state.find_army("kingdom-1"), null, "the routed army is destroyed")
		assert_true(e.numbers.destroyed.has("kingdom-1"))
		assert_true(e.text.contains("Aurel Crown routed, and its army was destroyed as it fled (3 fighters lost; there are no retreats yet)."), e.text)
		var last: String = e.numbers.report.lines.back()
		assert_true(last.begins_with("Aftermath: ") and last.contains("routed") and last.contains("destroyed"), last)
		assert_eq(e.numbers.report.aftermath, last.trim_prefix("Aftermath: "))
	assert_true(routs > 0, "crossbowmen facing a war bear and its warchief break and flee")


func test_attackers_stopped_by_the_round_cap_are_destroyed() -> void:
	var s := GameState.new(99)
	s.armies.clear()
	# Walls that can barely hurt each other, and never break: nobody wins within 8 rounds.
	for ut in [s.find_faction("kingdom").unit_types[0], s.find_faction("beasts").unit_types[0]]:
		ut.hp = 200
		ut.attack = 1
		ut.defense = 20
		ut.morale = 20
	_add_army(s, ["kingdom-1", "kingdom", "rivermarch", ["spearmen"]])
	_add_army(s, ["beasts-2", "beasts", "greenglade", ["tuskers"]])
	s.find_province("rivermarch").owner = "kingdom"
	var r := TurnResolver.resolve(s, {"beasts": [MoveOrder.new("beasts-2", "rivermarch")]}, 3)
	var e: Dictionary = _battles(r.events)[0]
	assert_eq(e.numbers.report.end, "round_cap")
	assert_eq(e.numbers.winner, "kingdom", "the defender holds at the cap")
	assert_false(_side(e.numbers.report, "beasts").routed, "the attackers were still standing")
	assert_eq(r.new_state.find_army("beasts-2"), null, "and are destroyed anyway")
	assert_true(e.text.contains("Thornmane Clans could not break the defenders within 8 rounds, and its army was destroyed (1 fighter lost; there are no retreats yet)."), e.text)
	assert_true(RulesCodex.text("battle_round_cap").contains("attacking armies are destroyed"))


func test_every_losing_side_is_explained_in_the_event_text() -> void:
	var seen := {}
	for e in _default_battle_events():
		var report: Dictionary = e.numbers.report
		for sr in report.sides:
			if sr.faction == e.numbers.winner:
				continue
			var how := "routed" if sr.routed else ("wiped out" if sr.destroyed else "outlasted")
			seen[how] = true
			if sr.routed:
				assert_true(e.text.contains("%s routed, and" % sr.name) and e.text.contains("destroyed as"), e.text)
			elif sr.destroyed:
				assert_true(e.text.contains("Every fighter %s had there fell" % sr.name) and e.text.contains("wiped out"), e.text)
			else:
				assert_true(e.text.contains(sr.name) and e.text.contains("destroyed"), e.text)
			for a in e.armies:
				if String(a).begins_with(sr.faction + "-"):
					assert_true(e.numbers.destroyed.has(a), "losing army %s is destroyed" % a)
	assert_true(seen.has("routed"), "the sample includes a rout")
	# The codex says the same thing in plain words.
	var rounds := RulesCodex.text("battle_rounds")
	assert_true(rounds.contains("a side that routs is destroyed as it flees"), rounds)
	assert_true(rounds.contains("attackers who have not won after 8 rounds are destroyed too"), rounds)
	assert_true(RulesCodex.text("battle_morale").contains("destroyed as they flee"))


# --- a winning army wiped out in a border battle (crash found by the autoplay simulator, PR #24) ---

## Test double: `winner_id` wins, and the army `wiped_id` on its side loses every fighter.
class WipeOutResolver extends BattleResolver:
	var winner_id := ""
	var wiped_id := ""

	func _init(winner: String, wiped: String) -> void:
		winner_id = winner
		wiped_id = wiped

	func resolve_battle(battle: Dictionary, _rng: SeededRNG) -> Dictionary:
		for side in battle.sides:
			for a in side.armies:
				if a.id == wiped_id:
					a.units.clear()
					a.commander = null
		return {"winner": winner_id, "strengths": {}, "tie_break": "none", "roll": 0, "why": "the test resolver decided it"}


## Aurel Crown sends two armies Wildmoor -> Ironspike while Thornmane's War Bear swaps the other way.
func _wipe_out_swap(first_hp := 0) -> Array:
	var s := _state([
		["kingdom-1", "kingdom", "wildmoor", ["spearmen"]],
		["kingdom-2", "kingdom", "wildmoor", ["knights", "knights", "knight_captain"]],
		["beasts-3", "beasts", "ironspike", ["war_bear"]],
	], {"wildmoor": "kingdom", "ironspike": "beasts"})
	if first_hp > 0:
		s.find_army("kingdom-1").units[0].current_hp = first_hp  # wounded in an earlier battle
	var orders := {"kingdom": [MoveOrder.new("kingdom-1", "ironspike"), MoveOrder.new("kingdom-2", "ironspike")],
		"beasts": [MoveOrder.new("beasts-3", "wildmoor")]}
	return [s, orders]


## The turn after a border battle Aurel Crown won while losing the army `wiped`: no crash (the runner
## fails a test on any script error), the survivor completes its move, the wiped army is gone.
func _assert_survivor_moved(r: Dictionary, wiped: String, survivor: String) -> void:
	var ns: GameState = r.new_state
	assert_true(ns != null, "the turn resolved")
	if ns == null:
		return
	assert_eq(ns.find_army(wiped), null, "the wiped-out army %s is gone" % wiped)
	assert_true(ns.find_army(survivor) != null and ns.find_army(survivor).location == "ironspike", "the surviving winner %s completes its move" % survivor)
	assert_eq(ns.find_army("beasts-3"), null, "the loser is destroyed")
	var border: Array = r.events.filter(func(e): return e.type == "border_battle")
	assert_eq(border.size(), 1)
	if border.size() == 1:
		assert_eq(border[0].numbers.winner, "kingdom")
		assert_true(border[0].numbers.destroyed.has(wiped), "the event lists the wiped army as destroyed")
	var moved: Array = r.events.filter(func(e): return e.type == "army_moved")
	assert_eq(moved.map(func(e): return e.armies), [[survivor]], "only the survivor gets a move event")
	if moved.size() == 1:
		assert_eq(moved[0].cause, "won_border_battle")
	assert_eq(ns.find_province("ironspike").owner, "kingdom", "the survivor captures Ironspike")
	assert_eq(ns.find_province("wildmoor").owner, "kingdom", "the War Bear never arrived")


func test_border_battle_winner_with_a_wiped_out_army_still_moves_the_rest() -> void:
	var setup := _wipe_out_swap()
	# Wiping the first mover (by id) used to stop the loop before the second one moved; wiping the
	# second used to crash after the first had moved. Both must work.
	for pair in [["kingdom-1", "kingdom-2"], ["kingdom-2", "kingdom-1"]]:
		var r := TurnResolver.resolve(setup[0], setup[1], 1, WipeOutResolver.new("kingdom", pair[0]))
		_assert_survivor_moved(r, pair[0], pair[1])


func test_real_border_battle_that_wipes_out_a_winning_army() -> void:
	# A wounded lone Spearman (1 hp) marches with Knights and their captain against a War Bear: the
	# Crown wins, and on some seeds the bear's one hit on the spearman wipes that army out.
	var setup := _wipe_out_swap(1)
	var reproduced := 0
	for turn_seed in range(1, 41):
		var r := TurnResolver.resolve(setup[0], setup[1], turn_seed)
		var border: Array = r.events.filter(func(e): return e.type == "border_battle")
		if border.is_empty() or border[0].numbers.winner != "kingdom" or not border[0].numbers.destroyed.has("kingdom-1"):
			continue
		reproduced += 1
		_assert_survivor_moved(r, "kingdom-1", "kingdom-2")
		assert_true(border[0].text.contains("Aurel Crown won, but one of its armies lost every fighter and is gone too."), border[0].text)
	assert_true(reproduced > 0, "some seed wipes out the wounded spearman's army while the Crown wins")
