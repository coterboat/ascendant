extends "res://tests/test_case.gd"
## M2-3 (#31): ruler death and succession (design/M2_RULER.md §1.5, §1.7, §3, §5, §7.5). Each kind's
## delay and successor power, heir names, death on a losing side vs. falling while the side won, the
## successor at full hp in a new army at the capital, succession waiting for the capital, healing
## amounts (rulers and Mending Light), the turn report's events (codex keys, plain text), replay, the
## victory summary's builds and the simulator's ruler invariants.
##
## Rulers are opt-in: every test here turns them on with GameState.with_rulers. Battles are pinned with
## StubBattleResolver (attack + defense of units and commanders; a lone ruler counts nothing, so the
## ruler's side loses) unless a test says otherwise. "Killed while winning" uses RulerFallsResolver
## below, which stands in for M2-2's battles: there a ruler whose hp reaches 0 leaves its army
## (army.ruler = null). Death is read from the state, never from the battle report, so it works either way.

const Simulator := preload("res://tools/autoplay/simulator.gd")
const Policies := preload("res://tools/autoplay/policies.gd")

## Every event type this ticket adds, with its phase.
const NEW_EVENTS := {"ruler_died": "battles", "mending": "rulers", "ruler_healed": "rulers",
	"ruler_arrived": "rulers", "succession_waiting": "rulers"}
## Ids that must never reach player-facing text (case-sensitive: display names are capitalised).
## Army ids ("kingdom-3") are caught by their faction id.
const RAW_IDS := ["kingdom", "beasts", "crownkeep", "westwatch", "stonegate", "highcrag", "rivermarch", "greenglade",
	"thornvale", "deepwood", "wildmoor", "blackwood", "ebonpeak", "ironspike", "bloodfen", "fangridge",
	"aurel_king", "ever_regent", "thornmane_avatar", "fang_chieftain", "royal_court", "mending_light",
	"warband_muster", "iron_discipline", "drilled_ranks", "royal_armories", "kings_roads", "heavy_tithes",
	"veteran_levies", "blood_frenzy", "feast_of_victory", "_"]


## StubBattleResolver's result, then every ruler on the winning side falls: its army no longer holds
## it, as when a ruler's hp reaches 0 in a battle its side wins (M2-2).
class RulerFallsResolver extends BattleResolver:
	func resolve_battle(battle: Dictionary, rng: SeededRNG) -> Dictionary:
		var result := StubBattleResolver.new().resolve_battle(battle, rng)
		for side in battle.sides:
			if side.faction == result.winner:
				for a in side.armies:
					a.ruler = null
		return result


# --- fixtures -------------------------------------------------------------------------------------

## A game with rulers: `builds` as GameState.with_rulers takes them. Turn `next_turn` is the next to resolve.
func _rulers(builds: Dictionary = {}, next_turn: int = 1, seed_value: int = 7) -> GameState:
	var errors := []
	var s := GameState.with_rulers(seed_value, builds, errors)
	assert_eq(errors, [], "the rulers set up")
	s.current_turn = next_turn - 1
	return s


## A game where `fid`'s ruler is `ruler_id` with `kept` kept power (no mandates), at full hp.
func _ruler_at(fid: String, ruler_id: String, kept: int, next_turn: int = 4) -> GameState:
	var s := _rulers({fid: {"ruler": ruler_id, "mandates": []}}, next_turn)
	var f := s.find_faction(fid)
	f.kept_power = kept
	RulerRules.refresh_ruler(s, fid)
	var unit := RulerRules.ruler_unit(s, fid)
	unit.current_hp = unit.type.hp
	assert_true(s.validate([]), "the fixture is a valid state")
	return s


func _army(s: GameState, id: String, owner: String, location: String, unit_ids: Array) -> Army:
	var a := Army.new()
	a.id = id
	a.owner = owner
	a.location = location
	var f := s.find_faction(owner)
	for type_id in unit_ids:
		var ut := TurnResolver.recruitable_type(f, type_id)
		if ut.is_commander:
			a.commander = Unit.new(ut, owner)
		else:
			a.units.append(Unit.new(ut, owner))
	s.armies.append(a)
	return a


func _enemy(fid: String) -> String:
	return "beasts" if fid == "kingdom" else "kingdom"


## Puts `fid`'s ruler alone at a battle site with a fresh enemy army next to it, and returns the
## enemy's order that attacks it this turn. With StubBattleResolver the ruler's side always loses.
## Kingdom rulers fall at Blackwood (attacked from Ebonpeak), beasts rulers at Stonegate (from Westwatch).
func _ambush(s: GameState, fid: String, units: Array = []) -> Dictionary:
	var enemy := _enemy(fid)
	var site := "blackwood" if fid == "kingdom" else "stonegate"
	var from := "ebonpeak" if fid == "kingdom" else "westwatch"
	for a in s.armies.duplicate():
		if a.location == site or a.location == from:
			s.armies.erase(a)
	RulerRules.ruler_army(s, fid).location = site
	var raider := _army(s, s.new_army_id(enemy), enemy, from,
		units if not units.is_empty() else (["tuskers"] if enemy == "beasts" else ["knights"]))
	return {enemy: [MoveOrder.new(raider.id, site)]}


func _resolve(s: GameState, orders: Dictionary = {}, resolver: BattleResolver = null) -> Dictionary:
	var result := TurnResolver.resolve(s, orders, TurnResolver.seed_for_turn(s),
		resolver if resolver != null else StubBattleResolver.new())
	assert_true(result.new_state != null, "the turn resolves: %s" % str(result.get("errors", [])))
	return result


func _events_of(events: Array, type: String) -> Array:
	return events.filter(func(e): return e.type == type)


## Every event reads plainly: the M1 event shape, a phase the report knows, an existing codex entry,
## and no raw ids in the text.
func _assert_plain(events: Array) -> void:
	for e in events:
		for key in ["type", "phase", "provinces", "factions", "armies", "cause", "numbers", "text", "codex"]:
			assert_true(e.has(key), "event %s has %s" % [e.get("type", "?"), key])
		assert_true(TurnResolver.PHASES.has(e.phase), "%s: phase %s is a resolver phase" % [e.type, e.phase])
		assert_true(GameSession.REPORT_PHASES.has(e.phase), "%s: phase %s is a report phase" % [e.type, e.phase])
		assert_true(RulesCodex.ENTRIES.has(String(e.codex)), "%s carries an existing codex entry (%s)" % [e.type, e.codex])
		assert_false(RulesCodex.text(String(e.codex)).is_empty(), "%s's codex entry has text" % e.type)
		if NEW_EVENTS.has(e.type):
			assert_eq(e.phase, NEW_EVENTS[e.type], "%s is in its phase" % e.type)
		_assert_no_raw_ids(String(e.text), "event %s" % e.type)


func _assert_no_raw_ids(text: String, what: String) -> void:
	assert_false(text.strip_edges().is_empty(), "%s has text" % what)
	for id in RAW_IDS:
		assert_false(text.contains(id), "%s shows no raw id '%s': %s" % [what, id, text])


# --- each kind: delay and successor power (§5.2) ----------------------------------------------------

func test_each_kind_returns_after_its_delay_with_its_share_of_kept_power() -> void:
	# [faction, ruler, kept power at death, delay (spec: T+2, T+4, T+1), successor's kept power, name]
	var cases := [
		["kingdom", "aurel_king", 10, 2, 5, "King Corvane II"],
		["kingdom", "aurel_king", 7, 2, 3, "King Corvane II"],  # half, rounded down
		["beasts", "fang_chieftain", 5, 2, 2, "the Tenth Fang"],
		["kingdom", "ever_regent", 6, 4, 6, "the Ever-Regent"],  # the same
		["beasts", "thornmane_avatar", 10, 1, 7, "the Great Thornmane"],  # 3 less
		["beasts", "thornmane_avatar", 2, 1, 0, "the Great Thornmane"],  # never below 0
		["beasts", "thornmane_avatar", 0, 1, 0, "the Great Thornmane"],
	]
	for c in cases:
		var fid: String = c[0]
		var rid: String = c[1]
		var what := "%s dying with %d kept power" % [rid, c[2]]
		var s := _ruler_at(fid, rid, c[2], 4)
		var mandates_before: Array = s.find_faction(fid).mandates.duplicate()
		var died := _resolve(s, _ambush(s, fid))
		var state: GameState = died.new_state
		var f := state.find_faction(fid)
		assert_eq(_events_of(died.events, "ruler_died").size(), 1, "%s: one death event" % what)
		assert_eq(f.ruler_status, RulerRules.DEAD, what)
		assert_eq(f.successor_turn, 4 + c[3], "%s: the successor is due at the end of turn T + %d" % [what, c[3]])
		assert_eq(f.successor_power, c[4], "%s: the successor's kept power" % what)
		assert_eq(f.kept_power, c[2], "%s: kept power stays as it was at death until the successor arrives" % what)
		assert_eq(f.ruler_generation, 1, what)
		assert_eq(f.mandates, mandates_before, "%s: mandates stay" % what)
		assert_eq(RulerRules.ruler_army(state, fid), null, "%s: the ruler's army is gone" % what)
		assert_false(RulerRules.has_living_ruler(state, fid), what)
		for t in range(5, 5 + c[3]):
			var r := _resolve(state)
			state = r.new_state
			f = state.find_faction(fid)
			var arrived := _events_of(r.events, "ruler_arrived")
			if t < 4 + c[3]:
				assert_eq(f.ruler_status, RulerRules.DEAD, "%s: still dead after turn %d" % [what, t])
				assert_eq(arrived, [], "%s: nobody arrives on turn %d" % [what, t])
				assert_eq(RulerRules.ruler_army(state, fid), null)
				continue
			assert_eq(arrived.size(), 1, "%s: the successor arrives at the end of turn %d" % [what, t])
			assert_eq(f.ruler_status, RulerRules.ALIVE, what)
			assert_eq(f.ruler_generation, 2, "%s: the next generation" % what)
			assert_eq(f.kept_power, c[4], what)
			assert_eq([f.successor_turn, f.successor_power], [0, 0], "%s: no successor due any more" % what)
			assert_eq(RulerRules.current_name(state, fid), c[5], what)
			var army := RulerRules.ruler_army(state, fid)
			assert_true(army != null and army.location == f.capital, "%s: at the capital" % what)
			assert_eq(army.ruler.current_hp, RulerRules.stat_value(rid, "hp", c[4]), "%s: at full hp" % what)
			assert_eq(army.ruler.type, f.ruler_unit_type, "%s: stats from the new kept power" % what)
			var e: Dictionary = arrived[0]
			assert_eq(e.codex, RulerData.KINDS[RulerRules.ruler_data(rid).kind].codex, "%s: the kind's codex entry" % what)
			assert_eq([e.numbers.kept_power, e.numbers.kept_power_before, e.numbers.generation], [c[4], c[2], 2])
			assert_true(state.validate([]), what)


func test_kept_power_after_succession_shows_in_the_breakdown() -> void:
	var s := _rulers({"kingdom": {"ruler": "aurel_king", "mandates": ["iron_discipline"]}}, 4)  # keeps 7
	var state: GameState = _resolve(s, _ambush(s, "kingdom")).new_state
	for i in 2:
		state = _resolve(state).new_state
	var b := Breakdown.kept_power(state, "kingdom")
	assert_eq(b.lines.map(func(l): return [l.label, l.value]), [["Power pool", 10], ["Iron Discipline", -3], ["Successions", -4]],
		"the power the succession cost has its own line")
	assert_eq(int(b.total), 3)
	assert_eq(Breakdown.sum_of_lines(b), 3)
	assert_eq(state.find_faction("kingdom").mandates, ["iron_discipline"], "mandates stay")


# --- heir names --------------------------------------------------------------------------------------

func test_heirs_go_down_the_line() -> void:
	# [faction, ruler, kept power, names of generations 2 and 3 as rulers, the heir's crowning sentence starts]
	var cases := [
		["kingdom", "aurel_king", 10, ["King Corvane II", "King Corvane III"],
			["Corvane II was crowned at Crownkeep as King Corvane II with 5 kept power",
				"Corvane III was crowned at Crownkeep as King Corvane III with 2 kept power"]],
		["beasts", "fang_chieftain", 5, ["the Tenth Fang", "the Eleventh Fang"],
			["The Tenth Fang was crowned at Fangridge with 2 kept power", "The Eleventh Fang was crowned at Fangridge with 1 kept power"]],
		["kingdom", "ever_regent", 6, ["the Ever-Regent", "the Ever-Regent"],
			["The Ever-Regent re-formed at Crownkeep with the same 6 kept power", "The Ever-Regent re-formed at Crownkeep with the same 6 kept power"]],
	]
	for c in cases:
		var fid: String = c[0]
		var state := _ruler_at(fid, c[1], c[2], 4)
		for gen in [2, 3]:
			var r := _resolve(state, _ambush(state, fid))
			state = r.new_state
			var death: Dictionary = _events_of(r.events, "ruler_died")[0]
			var heir := RulerRules.heir_name(c[1], gen)
			if RulerRules.ruler_data(c[1]).kind == "mortal":
				assert_true(String(death.text).contains("The line goes on: %s will be crowned at" % heir), death.text)
			var arrival := {}
			for wait in 6:
				var q := _resolve(state)
				state = q.new_state
				var found := _events_of(q.events, "ruler_arrived")
				if not found.is_empty():
					arrival = found[0]
					break
			assert_false(arrival.is_empty(), "%s generation %d arrived" % [c[1], gen])
			if arrival.is_empty():
				return
			assert_eq(RulerRules.current_name(state, fid), c[3][gen - 2], "generation %d" % gen)
			assert_eq(state.find_faction(fid).ruler_generation, gen)
			assert_true(String(arrival.text).begins_with(c[4][gen - 2]), arrival.text)
			var army := RulerRules.ruler_army(state, fid)
			assert_eq(TurnResolver.army_label(state, army), "%s ruler %s at %s" % [state.find_faction(fid).faction_name,
				c[3][gen - 2], state.find_province(state.find_faction(fid).capital).name], "the new ruler's army label")
	assert_eq(RulerRules.heir_name("aurel_king", 4), "Corvane IV")


# --- how a ruler dies (§5.1) -------------------------------------------------------------------------

func test_a_ruler_on_the_losing_side_is_lost_with_its_army() -> void:
	var s := _ruler_at("kingdom", "aurel_king", 10, 4)
	var r := _resolve(s, _ambush(s, "kingdom"))
	var types: Array = r.events.map(func(e): return e.type)
	var death_at := types.find("ruler_died")
	assert_true(death_at > 0 and types[death_at - 1] == "battle", "the death is recorded right after its battle: %s" % str(types))
	var e: Dictionary = r.events[death_at]
	assert_eq([e.phase, e.cause, e.codex, e.provinces, e.factions], ["battles", "lost_with_side", "ruler_death", ["blackwood"], ["kingdom"]])
	assert_eq(e.armies, ["kingdom-3"], "the ruler's army")
	assert_false(e.numbers.won)
	assert_eq(e.numbers.winner, "beasts")
	assert_eq([e.numbers.successor_turn, e.numbers.successor_power, e.numbers.heir_name], [6, 5, "Corvane II"])
	assert_eq(e.text, "King Corvane I was lost when the Aurel Crown lost the battle at Blackwood. A ruler on a losing side is lost with its army; there are no retreats yet. The line goes on: Corvane II will be crowned at Crownkeep at the end of turn 6, ready for orders on turn 7, with 5 kept power (half of 10, rounded down). Until then the Aurel Crown has no ruler: no Royal Court, no ruler in battle and no sacrifices.")
	var after: GameState = r.new_state
	assert_eq(after.find_army("kingdom-3"), null, "the ruler's army was destroyed with its side")
	assert_true(after.validate([]))
	_assert_plain(r.events)


func test_a_ruler_lost_in_a_border_battle() -> void:
	var s := _rulers({"kingdom": "warrior_king"}, 3)
	var king := RulerRules.ruler_army(s, "kingdom")
	king.location = "stonegate"
	var raider := _army(s, "beasts-9", "beasts", "blackwood", ["war_bear"])
	var r := _resolve(s, {"kingdom": [MoveOrder.new(king.id, "blackwood")], "beasts": [MoveOrder.new(raider.id, "stonegate")]})
	assert_eq(_events_of(r.events, "border_battle").size(), 1, "they met on the border")
	var e: Dictionary = _events_of(r.events, "ruler_died")[0]
	assert_eq(e.provinces, ["blackwood", "stonegate"])
	assert_true(String(e.text).begins_with("King Corvane I was lost when the Aurel Crown lost the battle on the border between Blackwood and Stonegate."), e.text)
	assert_true(String(e.text).contains("at the end of turn 5, ready for orders on turn 6"), e.text)
	assert_eq(r.new_state.find_army("beasts-9").location, "stonegate", "the winner completed its move")
	_assert_plain(r.events)


func test_a_ruler_that_falls_while_its_side_wins_dies_too() -> void:
	var s := _ruler_at("kingdom", "aurel_king", 4, 5)
	var orders := _ambush(s, "kingdom")
	s.find_army("kingdom-1").location = "blackwood"  # the starting army fights beside the King and wins
	var r := _resolve(s, orders, RulerFallsResolver.new())
	var battle: Dictionary = _events_of(r.events, "battle")[0]
	assert_eq(battle.numbers.winner, "kingdom", "the Aurel Crown won")
	var e: Dictionary = _events_of(r.events, "ruler_died")[0]
	assert_eq([e.cause, e.numbers.won, e.numbers.winner], ["fell_while_winning", true, "kingdom"])
	assert_eq(e.text, "King Corvane I fell in the battle at Blackwood, though the Aurel Crown won it. The line goes on: Corvane II will be crowned at Crownkeep at the end of turn 7, ready for orders on turn 8, with 2 kept power (half of 4, rounded down). Until then the Aurel Crown has no ruler: no Royal Court, no ruler in battle and no sacrifices.")
	var after: GameState = r.new_state
	assert_eq(after.find_faction("kingdom").ruler_status, RulerRules.DEAD)
	assert_eq(after.find_army("kingdom-3"), null, "the fallen ruler's army is removed")
	assert_eq(after.find_army("kingdom-1").location, "blackwood", "the rest of the winning side holds the field")
	assert_eq(after.find_province("blackwood").owner, "kingdom")
	assert_true(after.validate([]))
	_assert_plain(r.events)


func test_deaths_work_with_the_real_battle_rules() -> void:
	# A 0-kept King alone against a war band: he dies whether or not rulers fight yet (M2-2).
	var s := _ruler_at("kingdom", "aurel_king", 0, 4)
	var r := _resolve(s, _ambush(s, "kingdom", ["war_bear", "war_bear", "tuskers", "tuskers", "warchief"]), AutoBattleResolver.new())
	var after: GameState = r.new_state
	assert_eq(RulerRules.ruler_army(after, "kingdom"), null)
	assert_eq(after.find_faction("kingdom").ruler_status, RulerRules.DEAD)
	assert_eq(_events_of(r.events, "ruler_died").size(), 1)
	assert_true(after.validate([]))
	_assert_plain(r.events)


func test_a_ruler_that_survives_is_not_recorded_dead() -> void:
	var s := _rulers({}, 2)
	var regent := RulerRules.ruler_army(s, "kingdom")
	_army(s, "beasts-9", "beasts", "westwatch", ["fangthrowers"])
	var r := _resolve(s, {"beasts": [MoveOrder.new("beasts-9", "crownkeep")]})
	var battles := _events_of(r.events, "battle")
	assert_eq(battles.size(), 1, "the raid on Crownkeep was fought")
	assert_true(battles[0].armies.has(regent.id) and battles[0].armies.has("kingdom-1"),
		"the ruler's army fought beside army 1, on one side (§1.5): %s" % str(battles[0].armies))
	assert_eq(_events_of(r.events, "ruler_died"), [], "the Regent's side won and he still stands")
	assert_eq(RulerRules.ruler_army(r.new_state, "kingdom").id, regent.id)
	assert_eq(r.new_state.find_faction("kingdom").ruler_status, RulerRules.ALIVE)


func test_a_ruler_crosses_a_border_together_with_its_armies() -> void:
	# §1.5: the ruler fights with every army of yours crossing the same border, and goes on with them.
	var s := _rulers({"kingdom": "warrior_king"}, 3)
	var king := RulerRules.ruler_army(s, "kingdom")
	king.location = "stonegate"
	s.find_army("kingdom-1").location = "stonegate"
	_army(s, "beasts-9", "beasts", "blackwood", ["tuskers"])
	var r := _resolve(s, {"kingdom": [MoveOrder.new(king.id, "blackwood"), MoveOrder.new("kingdom-1", "blackwood")],
		"beasts": [MoveOrder.new("beasts-9", "stonegate")]})
	var border := _events_of(r.events, "border_battle")
	assert_eq(border.size(), 1, "one border battle")
	assert_eq(border[0].armies, ["beasts-9", "kingdom-1", king.id], "both Crown armies on one side, by faction then army")
	assert_eq(border[0].numbers.winner, "kingdom")
	assert_eq(RulerRules.ruler_army(r.new_state, "kingdom").location, "blackwood", "the King completed his move")
	assert_eq(r.new_state.find_army("kingdom-1").location, "blackwood")
	assert_eq(_events_of(r.events, "ruler_died"), [])
	_assert_plain(r.events)


# --- the successor arrives (§5.2) -------------------------------------------------------------------

func test_the_successor_arrives_at_full_hp_in_a_new_army_at_the_capital() -> void:
	var s := _ruler_at("kingdom", "aurel_king", 10, 4)
	var army1_before: Dictionary = s.find_army("kingdom-1").to_dict()
	var state: GameState = _resolve(s, _ambush(s, "kingdom")).new_state
	state = _resolve(state).new_state
	var r := _resolve(state)
	state = r.new_state
	var f := state.find_faction("kingdom")
	var army := RulerRules.ruler_army(state, "kingdom")
	assert_true(army != null, "Corvane II was crowned")
	assert_false(["kingdom-1", "kingdom-3"].has(army.id), "in a new army (%s)" % army.id)
	assert_eq(army.location, "crownkeep")
	assert_true(army.units.is_empty() and army.commander == null, "a ruler's army holds only the ruler")
	assert_eq(army.ruler.current_hp, 28, "King Corvane II at 5 kept power, at his full 28 hp")
	assert_eq(army.ruler.current_hp, army.ruler.type.hp)
	assert_eq(army.ruler.type.name, "King Corvane II")
	assert_eq(state.find_army("kingdom-1").to_dict(), army1_before, "the starting army at the capital is untouched")
	assert_eq(TurnResolver.army_label(state, army), "Aurel Crown ruler King Corvane II at Crownkeep")
	var e: Dictionary = _events_of(r.events, "ruler_arrived")[0]
	assert_eq([e.phase, e.cause, e.codex, e.provinces, e.armies], ["rulers", "succession", "succession_mortal", ["crownkeep"], [army.id]])
	assert_eq(e.text, "Corvane II was crowned at Crownkeep as King Corvane II with 5 kept power: 28 hit points, attack 11, defense 10, Royal Court +3 gold (ability rank 2). The new ruler's army stands at Crownkeep, ready for orders on turn 7.")
	assert_eq(f.ruler_generation, 2)
	assert_true(state.validate([]))
	_assert_plain(r.events)
	# Turn 7: the new King takes orders, and a recruit at the capital joins the starting army, never him.
	assert_eq(TurnResolver.check_move(state, "kingdom", MoveOrder.new(army.id, "highcrag")), {}, "he can be ordered")
	var t7 := _resolve(state, {"kingdom": [MoveOrder.new(army.id, "highcrag"), RecruitOrder.new("spearmen")]})
	var s7: GameState = t7.new_state
	assert_eq(RulerRules.ruler_army(s7, "kingdom").location, "highcrag")
	assert_eq(s7.find_army("kingdom-1").units.size(), s.find_army("kingdom-1").units.size() + 1, "the recruit joined army 1")
	assert_true(String(_events_of(t7.events, "army_moved")[0].text).begins_with("The Aurel Crown ruler King Corvane II at Crownkeep moved to Highcrag"))


func test_succession_waits_until_the_faction_holds_its_capital() -> void:
	var s := _ruler_at("kingdom", "aurel_king", 10, 4)
	var state: GameState = _resolve(s, _ambush(s, "kingdom")).new_state  # dies on turn 4, due at the end of turn 6
	# The Clans take Crownkeep before the heir is due.
	state.armies.erase(state.find_army("kingdom-1"))
	state.find_province("crownkeep").owner = "beasts"
	_army(state, "beasts-30", "beasts", "crownkeep", ["tuskers"])
	state = _resolve(state).new_state  # turn 5
	for t in [6, 7]:
		var r := _resolve(state)
		state = r.new_state
		assert_eq(_events_of(r.events, "ruler_arrived"), [], "no crowning on turn %d" % t)
		var waiting := _events_of(r.events, "succession_waiting")
		assert_eq(waiting.size(), 1, "turn %d says why the heir waits" % t)
		assert_eq([waiting[0].codex, waiting[0].cause, waiting[0].provinces], ["succession", "capital_not_held", ["crownkeep"]])
		assert_eq(waiting[0].text, "Corvane II was due to be crowned at Crownkeep at the end of turn 6, but the Aurel Crown doesn't hold Crownkeep. Successors arrive only at the capital, so this waits until the end of the first turn the Aurel Crown holds Crownkeep again.")
		assert_eq(state.find_faction("kingdom").ruler_status, RulerRules.DEAD)
		assert_eq(state.find_faction("kingdom").successor_turn, 6, "still due, from turn 6")
		_assert_plain(r.events)
		var problems := Simulator.check_invariants(null, state, r.events).filter(func(v): return v.check.begins_with("succ") or v.check.begins_with("ruler"))
		assert_eq(problems, [], "waiting for the capital is not an overdue successor")
	# Turn 8: the Clans leave and an Aurel army retakes the capital; the heir is crowned that evening.
	state.armies.erase(state.find_army("beasts-30"))
	_army(state, "kingdom-31", "kingdom", "westwatch", ["spearmen"])
	var back := _resolve(state, {"kingdom": [MoveOrder.new("kingdom-31", "crownkeep")]})
	state = back.new_state
	assert_eq(state.find_province("crownkeep").owner, "kingdom")
	var arrived := _events_of(back.events, "ruler_arrived")
	assert_eq(arrived.size(), 1, "crowned at the end of the turn Crownkeep was retaken")
	assert_true(String(arrived[0].text).ends_with("ready for orders on turn 9."), arrived[0].text)
	assert_eq(arrived[0].numbers.due_turn, 6)
	assert_eq(RulerRules.ruler_army(state, "kingdom").location, "crownkeep")
	assert_eq(_events_of(back.events, "succession_waiting"), [])
	assert_true(state.validate([]))


# --- healing (§1.7, §1.4) -----------------------------------------------------------------------------

func test_rulers_heal_a_quarter_of_their_maximum_hp_rounded_up() -> void:
	var table := {46: 12, 35: 9, 66: 17, 22: 6, 16: 4, 14: 4, 30: 8, 1: 1}
	for max_hp in table:
		assert_eq(RulerRules.ruler_heal_amount(max_hp), table[max_hp], "a quarter of %d, rounded up" % max_hp)
	var s := _rulers({"kingdom": "warrior_king", "beasts": "beast_god_unbound"}, 3)
	RulerRules.ruler_unit(s, "kingdom").current_hp = 10
	var r := _resolve(s)
	var healed := _events_of(r.events, "ruler_healed")
	assert_eq(healed.size(), 1, "only the wounded King heals; the Thornmane is at full hp")
	var e: Dictionary = healed[0]
	assert_eq([e.phase, e.codex, e.factions, e.provinces], ["rulers", "ruler_healing", ["kingdom"], ["crownkeep"]])
	assert_eq([e.numbers.healed, e.numbers.hp_before, e.numbers.hp_after, e.numbers.max_hp], [10, 10, 20, 38])
	assert_eq(e.text, "King Corvane I healed 10 hit points at Crownkeep (a living ruler heals a quarter of its maximum, rounded up, at the end of every turn): now 20 of 38.")
	assert_eq(RulerRules.ruler_unit(r.new_state, "kingdom").current_hp, 20)
	assert_eq(r.events.back(), e, "the rulers phase comes last")
	_assert_plain(r.events)
	# Never above the maximum.
	var s2: GameState = r.new_state
	RulerRules.ruler_unit(s2, "kingdom").current_hp = 32
	RulerRules.ruler_unit(s2, "beasts").current_hp = 48
	var r2 := _resolve(s2)
	assert_eq(RulerRules.ruler_unit(r2.new_state, "kingdom").current_hp, 38)
	assert_eq(RulerRules.ruler_unit(r2.new_state, "beasts").current_hp, 54)
	assert_eq(_events_of(r2.events, "ruler_healed").map(func(x): return x.numbers.healed), [6, 6], "factions in id order: beasts, kingdom")
	assert_eq(_events_of(r2.events, "ruler_healed").map(func(x): return x.factions[0]), ["beasts", "kingdom"])
	# The Ninth Fang at 5 kept power: 30 maximum, heals 8.
	var s3 := _rulers({"beasts": "blood_of_the_fang"}, 2)
	RulerRules.ruler_unit(s3, "beasts").current_hp = 1
	assert_eq(RulerRules.ruler_unit(_resolve(s3).new_state, "beasts").current_hp, 9)


func test_mending_light_heals_wounded_units_and_commanders_in_the_regents_province() -> void:
	var s := _rulers({}, 3)  # the Ever-Regent at 5 kept power: ability rank 2, heal 6
	var army1 := s.find_army("kingdom-1")
	army1.units[0].current_hp = 3  # Spearmen 3 of 8
	army1.units[1].current_hp = 7  # Crossbowmen 7 of 8
	army1.commander.current_hp = 20  # Knight Captain 20 of 26
	var second := _army(s, "kingdom-20", "kingdom", "crownkeep", ["spearmen"])
	second.units[0].current_hp = 5
	var away := _army(s, "kingdom-21", "kingdom", "westwatch", ["spearmen"])
	away.units[0].current_hp = 2
	RulerRules.ruler_unit(s, "kingdom").current_hp = 10
	var r := _resolve(s)
	var after: GameState = r.new_state
	var a1 := after.find_army("kingdom-1")
	assert_eq([a1.units[0].current_hp, a1.units[1].current_hp, a1.units[2].current_hp, a1.commander.current_hp], [8, 8, 18, 26])
	assert_eq(after.find_army("kingdom-20").units[0].current_hp, 8, "every army of the faction in the Regent's province")
	assert_eq(after.find_army("kingdom-21").units[0].current_hp, 2, "not elsewhere")
	assert_eq(RulerRules.ruler_unit(after, "kingdom").current_hp, 15, "the Regent heals only his own quarter: 10 + 5")
	var types: Array = r.events.map(func(e): return e.type)
	assert_true(types.find("mending") < types.find("ruler_healed"), "Mending Light heals first: %s" % str(types))
	var e: Dictionary = _events_of(r.events, "mending")[0]
	assert_eq([e.phase, e.codex, e.provinces, e.armies], ["rulers", "ability_mending_light", ["crownkeep"], ["kingdom-1", "kingdom-20"]])
	assert_eq([e.numbers.rank, e.numbers.amount, e.numbers.total], [2, 6, 15])
	assert_eq(e.text, "Mending Light (rank 2, heal 6): the Ever-Regent healed 4 wounded fighters of the Aurel Crown at Crownkeep, 15 hit points in all (2 Spearmen +8, Crossbowmen +1, Knight Captain +6).")
	_assert_plain(r.events)
	# Rank 4 at 10 kept power heals 12; a dead Regent and other rulers heal nobody.
	var strong := _ruler_at("kingdom", "ever_regent", 10, 2)
	strong.find_army("kingdom-1").commander.current_hp = 5
	assert_eq(RulerRules.apply_mending_light(strong, "kingdom").amount, 12)
	assert_eq(strong.find_army("kingdom-1").commander.current_hp, 17)
	var dead := _rulers({}, 3)
	dead.find_army("kingdom-1").units[0].current_hp = 3
	RulerRules.record_death(dead, "kingdom", 3)
	assert_eq(RulerRules.apply_mending_light(dead, "kingdom").healed, [], "no living Regent, no Mending Light")
	var king := _rulers({"kingdom": "warrior_king"}, 3)
	king.find_army("kingdom-1").units[0].current_hp = 3
	assert_eq(_events_of(_resolve(king).events, "mending"), [], "King Corvane's ability is Royal Court")


# --- the turn report ---------------------------------------------------------------------------------

func test_every_new_event_type_carries_an_existing_codex_entry_and_plain_text() -> void:
	var seen := {}
	var all_events := []
	for c in [["kingdom", "aurel_king", 6], ["kingdom", "ever_regent", 6], ["beasts", "thornmane_avatar", 5], ["beasts", "fang_chieftain", 0]]:
		var state := _ruler_at(c[0], c[1], c[2], 2)
		state.find_army("kingdom-1").units[0].current_hp = 2
		var r := _resolve(state, _ambush(state, c[0]))
		all_events.append_array(r.events)
		state = r.new_state
		RulerRules.ruler_unit(state, _enemy(c[0])).current_hp = 3
		for i in 5:
			r = _resolve(state)
			all_events.append_array(r.events)
			state = r.new_state
	var waiting := _ruler_at("kingdom", "aurel_king", 3, 2)
	var w: GameState = _resolve(waiting, _ambush(waiting, "kingdom")).new_state
	w.find_province("crownkeep").owner = "beasts"
	w.armies.erase(w.find_army("kingdom-1"))
	for i in 3:
		var r := _resolve(w)
		all_events.append_array(r.events)
		w = r.new_state
	var falls := _ruler_at("beasts", "thornmane_avatar", 10, 2)
	var orders := _ambush(falls, "beasts")
	falls.find_army("beasts-2").location = "stonegate"
	all_events.append_array(_resolve(falls, orders, RulerFallsResolver.new()).events)
	for e in all_events:
		seen[e.type] = true
		if e.type == "ruler_died":
			seen["ruler_died/" + e.cause] = true
		if e.type == "ruler_arrived":
			seen["ruler_arrived/" + e.codex] = true
	for key in NEW_EVENTS.keys() + ["ruler_died/lost_with_side", "ruler_died/fell_while_winning", "ruler_arrived/succession_mortal",
			"ruler_arrived/succession_undying", "ruler_arrived/succession_god"]:
		assert_true(seen.has(key), "the scenarios produced %s" % key)
	_assert_plain(all_events)
	var texts := all_events.filter(func(e): return NEW_EVENTS.has(e.type)).map(func(e): return e.text)
	assert_true(texts.has("The Great Thornmane took a new body at Fangridge with 2 kept power, 3 less than before, for good: 30 hit points, attack 10, defense 8, Dread 1 less enemy morale (ability rank 1). The new ruler's army stands at Fangridge, ready for orders on turn 4."), "\n".join(texts))
	assert_true(texts.has("The Tenth Fang was crowned at Fangridge with 0 kept power: 20 hit points, attack 9, defense 7, Warband Muster 1 recruit in the field (ability rank 1). The new ruler's army stands at Fangridge, ready for orders on turn 5."), "\n".join(texts))


func test_the_turn_report_shows_ruler_events_with_their_codex_links() -> void:
	# The report panel renders events from their text and codex keys alone: no UI change is needed.
	var s := _rulers({"kingdom": "warrior_king"}, 6)
	var orders := _ambush(s, "kingdom")
	RulerRules.ruler_unit(s, "beasts").current_hp = 5
	var r := _resolve(s, orders)
	var panel := load("res://ui/turn_report_panel.tscn").instantiate() as TurnReportPanel
	panel.show_report_data({"turn": 6, "header": "Turn 6 results", "events": r.events})
	var texts := panel.event_rows().map(func(b): return b.text)
	var death: Dictionary = _events_of(r.events, "ruler_died")[0]
	var healed: Dictionary = _events_of(r.events, "ruler_healed")[0]
	assert_true(texts.has(death.text), "the death has its row")
	assert_true(texts.has(healed.text), "the healing has its row")
	var keys := panel.codex_buttons().map(func(b): return String(b.get_meta("codex_key")))
	assert_true(keys.has("ruler_death") and keys.has("ruler_healing"), "each has a ? opening its codex entry: %s" % str(keys))
	var heading := panel.rows_box.find_child("Heading_rulers", false, false) as Label
	assert_true(heading != null and heading.text == "Rulers", "the rulers phase has its own heading")
	panel.free()


func test_death_texts_for_each_kind() -> void:
	var regent := _ruler_at("kingdom", "ever_regent", 6, 5)
	var e: Dictionary = _events_of(_resolve(regent, _ambush(regent, "kingdom")).events, "ruler_died")[0]
	assert_eq(e.text, "The Ever-Regent was broken when the Aurel Crown lost the battle at Blackwood. A ruler on a losing side is lost with its army; there are no retreats yet. The Ever-Regent cannot truly die and re-forms at Crownkeep at the end of turn 9, ready for orders on turn 10, with the same 6 kept power. Until then the Aurel Crown has no ruler: no Mending Light, no ruler in battle and no sacrifices.")
	var god := _rulers({"beasts": {"ruler": "thornmane_avatar", "mandates": ["iron_discipline"]}}, 5)
	e = _events_of(_resolve(god, _ambush(god, "beasts")).events, "ruler_died")[0]
	assert_eq(e.text, "The Great Thornmane's body was destroyed when the Thornmane Clans lost the battle at Stonegate. A ruler on a losing side is lost with its army; there are no retreats yet. The god takes a new body at Fangridge at the end of turn 6, ready for orders on turn 7, weaker for good: 4 kept power instead of 7 (3 less, never below 0). Until then the Thornmane Clans has no ruler: no Dread, no ruler in battle and no sacrifices. Its mandates stay.")
	var spent := _ruler_at("beasts", "thornmane_avatar", 0, 5)
	var orders := _ambush(spent, "beasts")
	spent.find_army("beasts-2").location = "stonegate"
	e = _events_of(_resolve(spent, orders, RulerFallsResolver.new()).events, "ruler_died")[0]
	assert_true(String(e.text).begins_with("The Great Thornmane's body was slain in the battle at Stonegate, though the Thornmane Clans won it. The god takes a new body at Fangridge at the end of turn 6, ready for orders on turn 7, with 0 kept power: it had none left to lose"), e.text)
	var fang := _ruler_at("beasts", "fang_chieftain", 3, 5)
	e = _events_of(_resolve(fang, _ambush(fang, "beasts")).events, "ruler_died")[0]
	assert_true(String(e.text).contains("The line goes on: the Tenth Fang will be crowned at Fangridge at the end of turn 7, ready for orders on turn 8, with 1 kept power (half of 3, rounded down). Until then the Thornmane Clans has no ruler: no Warband Muster,"), e.text)


# --- replay ----------------------------------------------------------------------------------------

## A session with rulers where the King and the Thornmane both die and come back: a war band holds
## Highcrag, next to Crownkeep, and a Crown host holds Ironspike, next to Fangridge.
func _session_with_deaths(game_seed: int) -> Dictionary:
	var start := _rulers({"kingdom": "iron_crown",
		"beasts": {"ruler": "thornmane_avatar", "mandates": ["iron_discipline", "blood_frenzy", "feast_of_victory"]}}, 1, game_seed)
	_army(start, "beasts-10", "beasts", "highcrag", ["war_bear", "war_bear", "tuskers", "tuskers", "warchief"])
	_army(start, "kingdom-11", "kingdom", "ironspike", ["knights", "knights", "knights", "knight_captain"])
	start.find_province("highcrag").owner = "beasts"
	start.find_province("ironspike").owner = "kingdom"
	var session := GameSession.new(start, ["kingdom", "beasts"], game_seed, AutoBattleResolver.new())
	assert_eq(session.setup_errors(), [])
	var script := [
		[[MoveOrder.new("kingdom-3", "highcrag")], []],  # turn 1: the 0-kept King rides into the war band
		[[RecruitOrder.new("spearmen")], [MoveOrder.new("beasts-4", "ironspike")]],  # turn 2: the 1-kept god charges the host
		[[], []],
		[[], [RecruitOrder.new("tuskers")]],
		[[], []],
	]
	var reports := []
	for t in script:
		for o in t[0]:
			assert_eq(session.queue_order(o), "", "kingdom order accepted")
		assert_eq(session.end_turn(), "")
		assert_eq(session.acknowledge_handoff(), "")
		for o in t[1]:
			assert_eq(session.queue_order(o), "", "beasts order accepted")
		assert_eq(session.end_turn(), "")
		reports.append(session.turn_report().events)
		if session.is_over():
			break
		assert_eq(session.acknowledge_handoff(), "")
	return {"session": session, "reports": reports}


func test_a_replay_with_deaths_and_successions_is_identical() -> void:
	var played := _session_with_deaths(41)
	var session: GameSession = played.session
	var reports: Array = played.reports
	var counts := {}
	for events in reports:
		for e in events:
			counts[e.type] = int(counts.get(e.type, 0)) + 1
		_assert_plain(events)
	assert_eq(counts.get("ruler_died", 0), 2, "the King and the god fell: %s" % str(counts))
	assert_eq(counts.get("ruler_arrived", 0), 2, "and both came back: %s" % str(counts))
	var final := session.state()
	assert_eq(final.find_faction("kingdom").ruler_generation, 2)
	assert_eq(final.find_faction("beasts").ruler_generation, 2)
	var record := session.record()
	for rec in [record, JSON.parse_string(JSON.stringify(record))]:
		var replayed := GameSession.replay(rec, AutoBattleResolver.new())
		assert_eq(replayed.errors, [])
		assert_true(replayed.state != null)
		if replayed.state != null:
			assert_eq(replayed.state.to_dict(), final.to_dict(), "the replay ends in the identical state")
		# Turn by turn, every event is the same too.
		var state := GameState.from_dict(rec.start_state)
		for i in rec.history.size():
			var entry: Dictionary = rec.history[i]
			var errors := []
			var orders := OrderBook.orders_from_dict(entry.orders, errors)
			var r := TurnResolver.resolve(state, orders, Serial.to_int(entry.seed), AutoBattleResolver.new())
			assert_eq(var_to_str(r.events), var_to_str(reports[i]), "turn %d's report replays identically" % (i + 1))
			state = r.new_state
	# The same seed and orders give the same game; the record has the starting builds.
	var again: GameSession = _session_with_deaths(41).session
	assert_eq(again.state().to_dict(), final.to_dict())
	assert_eq(record.builds.kingdom.kept_power, 0)
	assert_eq(record.builds.kingdom.status, "alive", "the record keeps the builds as they started")


# --- the victory summary lists builds (§5.3) ----------------------------------------------------------

func test_the_victory_summary_lists_each_build() -> void:
	var s := _rulers({"kingdom": "warrior_king"}, 6)
	RulerRules.record_death(s, "kingdom", 5)
	s.find_province("fangridge").owner = "kingdom"
	var players := ["kingdom", "beasts"]
	var result := VictoryCheck.check(s, players)
	assert_true(result.over)
	var summary := VictoryCheck.summary(s, players, result, 6, 6, 3)
	assert_eq(summary.builds.keys(), ["kingdom", "beasts"], "in seat order")
	assert_eq([summary.builds.kingdom.ruler_name, summary.builds.kingdom.status, summary.builds.kingdom.kept_power,
		summary.builds.kingdom.rulers_lost], ["King Corvane I", "dead", 10, 1])
	assert_eq([summary.builds.beasts.ruler_name, summary.builds.beasts.kept_power, summary.builds.beasts.mandate_names],
		["the Ninth Fang", 5, ["Iron Discipline", "Drilled Ranks"]])
	assert_true(String(summary.text).ends_with("Builds: Aurel Crown, King Corvane I (dead, 1 ruler lost), 10 kept power, no mandates. Thornmane Clans, the Ninth Fang (alive), 5 kept power, mandates: Iron Discipline and Drilled Ranks."), summary.text)
	assert_eq(summary.event.text, summary.text, "the final turn report says the same")
	_assert_no_raw_ids(String(summary.text), "the victory summary")
	# A successor that lost power shows where it started.
	var s2 := _ruler_at("kingdom", "aurel_king", 10, 4)
	var after: GameState = _resolve(s2, _ambush(s2, "kingdom")).new_state
	after = _resolve(_resolve(after).new_state).new_state
	assert_true(VictoryCheck.builds_text(after, players).begins_with("Builds: Aurel Crown, King Corvane II (alive, 1 ruler lost), 5 kept power (10 at the start), no mandates."),
		VictoryCheck.builds_text(after, players))
	# An M1 game's summary is unchanged: no builds.
	var m1 := GameState.new(6)
	m1.find_province("fangridge").owner = "kingdom"
	var m1_summary := VictoryCheck.summary(m1, players, VictoryCheck.check(m1, players), 6, 6, 3)
	assert_false(m1_summary.has("builds"))
	assert_false(String(m1_summary.text).contains("Builds"))
	assert_eq(VictoryCheck.builds_text(m1, players), "")


func test_a_session_with_rulers_ends_with_the_builds_on_the_victory_screen_text() -> void:
	var start := _rulers({}, 1, 13)
	_army(start, "kingdom-12", "kingdom", "ebonpeak", ["knights", "knights"])
	start.find_army("beasts-2").location = "bloodfen"
	start.find_army("beasts-4").location = "bloodfen"
	var session := GameSession.new(start, ["kingdom", "beasts"], 13, StubBattleResolver.new())
	assert_eq(session.queue_move("kingdom-12", "fangridge"), "")
	assert_eq(session.end_turn(), "")
	assert_eq(session.acknowledge_handoff(), "")
	assert_eq(session.end_turn(), "")
	assert_true(session.is_over(), "Fangridge fell")
	var v := session.victory()
	assert_true(String(v.text).contains("Builds: Aurel Crown, the Ever-Regent (alive), 5 kept power, mandates: Royal Armories and King's Roads."), v.text)
	assert_eq(session.turn_report().events.back().text, v.text)


# --- simulator invariants for ruler armies --------------------------------------------------------------

func _checks(found: Array) -> Array:
	return found.map(func(v): return v.check)


func test_simulator_accepts_ruler_armies_and_successions() -> void:
	var prev := _rulers()
	var next := _rulers()
	next.current_turn = 1
	assert_eq(Simulator.check_invariants(prev, next, []), [], "a ruler-only army is not an empty army")
	# A real turn with a death, then the turns up to the crowning, keep every invariant (real battles:
	# the simulator wants their reports).
	var s := _ruler_at("kingdom", "aurel_king", 0, 4)
	var orders := _ambush(s, "kingdom", ["war_bear", "war_bear", "tuskers", "tuskers", "warchief"])
	var state := s
	for t in 3:
		var r := _resolve(state, orders if t == 0 else {}, AutoBattleResolver.new())
		assert_eq(Simulator.check_invariants(state, r.new_state, r.events), [], "turn %d" % (t + 4))
		if t == 0:
			assert_eq(_events_of(r.events, "ruler_died").size(), 1, "the King fell on turn 4")
		state = r.new_state
	assert_eq(state.find_faction("kingdom").ruler_status, RulerRules.ALIVE, "crowned by the end of turn 6")


func test_simulator_catches_broken_ruler_armies_and_successions() -> void:
	var prev := _rulers()
	var bad := _rulers()
	bad.current_turn = 1
	var regent := RulerRules.ruler_army(bad, "kingdom")
	regent.units.append(Unit.new(bad.find_faction("kingdom").unit_types[0], "kingdom"))
	var twin := Army.new()
	twin.id = "beasts-40"
	twin.owner = "beasts"
	twin.location = "ebonpeak"
	twin.ruler = Unit.new(bad.find_faction("beasts").ruler_unit_type, "beasts")
	bad.armies.append(twin)
	var found := _checks(Simulator.check_invariants(prev, bad, []))
	for expected in ["ruler_army_not_alone", "ruler_army_twice", "validate"]:
		assert_true(found.has(expected), "catches %s: %s" % [expected, found])
	# A living ruler with no army, a death without its event, a dead ruler with no successor due.
	var gone := _rulers()
	gone.current_turn = 1
	gone.armies.erase(RulerRules.ruler_army(gone, "kingdom"))
	var dead := gone.find_faction("beasts")
	gone.armies.erase(RulerRules.ruler_army(gone, "beasts"))
	dead.ruler_status = RulerRules.DEAD
	found = _checks(Simulator.check_invariants(prev, gone, []))
	for expected in ["ruler_missing", "successor_missing", "ruler_events_mismatch"]:
		assert_true(found.has(expected), "catches %s: %s" % [expected, found])
	# A successor overdue while the capital is held.
	var late := _rulers()
	late.current_turn = 6
	late.armies.erase(RulerRules.ruler_army(late, "kingdom"))
	late.find_faction("kingdom").ruler_status = RulerRules.DEAD
	late.find_faction("kingdom").successor_turn = 5
	late.find_faction("kingdom").successor_power = 2
	assert_true(_checks(Simulator.check_invariants(null, late, [])).has("successor_overdue"))
	# An unknown event type is still caught, and the new ones are known.
	for type in NEW_EVENTS:
		assert_false(_checks(Simulator.check_invariants(null, _rulers(), [{"type": type, "phase": NEW_EVENTS[type], "factions": [], "numbers": {}}])).has("event_type_unknown"), type)


func test_games_with_rulers_keep_every_invariant_and_replay_identically() -> void:
	# Bots marching 0-kept rulers about: rulers die and successors arrive. Every turn keeps the
	# simulator's invariants, and every game replays to the same final state.
	var deaths := 0
	var arrivals := 0
	for game_seed in range(3, 11):
		var builds := {"kingdom": "iron_crown", "beasts": "clan_moot"} if game_seed % 2 == 1 \
			else {"kingdom": "regents_court", "beasts": "beast_god_unbound"}
		var start := _rulers(builds, 1, game_seed)
		var seats := ["kingdom", "beasts"]
		var policies := [Policies.make("random" if game_seed % 2 == 1 else "greedy"), Policies.make("random")]
		var rngs := [SeededRNG.new(Simulator.policy_seed(game_seed, 0)), SeededRNG.new(Simulator.policy_seed(game_seed, 1))]
		var session := GameSession.new(start, seats, game_seed, AutoBattleResolver.new())
		var prev := session.state()
		while not session.is_over() and session.turns_played() < 24:
			for seat in 2:
				if session.phase() == GameSession.Phase.HANDOFF:
					session.acknowledge_handoff()
				var view := session.state()
				for o in policies[seat].orders(view, seats[seat], rngs[seat]):
					session.queue_order(o)
				assert_eq(session.end_turn(), "")
			var state := session.state()
			var events: Array = session.turn_report().events
			var problems := Simulator.check_invariants(prev, state, events)
			assert_eq(problems, [], "seed %d turn %d" % [game_seed, session.turns_played()])
			for e in events:
				if e.type == "ruler_died":
					deaths += 1
				elif e.type == "ruler_arrived":
					arrivals += 1
			_assert_plain(events.filter(func(e): return NEW_EVENTS.has(e.type)))
			prev = state
		var replayed := GameSession.replay(session.record(), AutoBattleResolver.new())
		assert_eq(replayed.errors, [], "seed %d replays" % game_seed)
		if replayed.state != null:
			assert_eq(replayed.state.to_dict(), session.state().to_dict(), "seed %d replays identically" % game_seed)
	assert_true(deaths > 0, "rulers died (%d)" % deaths)
	assert_true(arrivals > 0, "successors arrived (%d)" % arrivals)


# --- M1 is unchanged; the codex states the rules ---------------------------------------------------------

func test_an_m1_game_has_no_rulers_phase_events() -> void:
	assert_eq(TurnResolver.PHASES.back(), "rulers", "the rulers phase is the last resolver phase")
	assert_eq(GameSession.REPORT_PHASES.slice(-2), ["rulers", "victory"])
	var s := GameState.new(5)
	s.find_army("kingdom-1").units[0].current_hp = 2  # nobody heals without rulers
	var r := _resolve(s, {"kingdom": [MoveOrder.new("kingdom-1", "westwatch")]})
	assert_eq(r.events.filter(func(e): return e.phase == "rulers"), [])
	assert_eq(r.new_state.find_army("kingdom-1").units[0].current_hp, 2)
	assert_eq(r.events.map(func(e): return e.type), ["army_moved", "captured", "income", "income"])


func test_the_codex_states_the_succession_rules_with_the_datas_numbers() -> void:
	for r in RulerData.RULERS:
		var kind: String = r.kind
		var key: String = RulerData.KINDS[kind].codex
		var delay := int(r.succession.delay)
		var text := RulesCodex.text(key)
		assert_true(text.contains("%d %s later" % [delay, "turn" if delay == 1 else "turns"]), "%s states the %d-turn delay: %s" % [key, delay, text])
		assert_true(RulesCodex.text("succession").contains("%d %s later" % [delay, "turn" if delay == 1 else "turns"]), "succession states %s's delay" % r.id)
	assert_true(RulesCodex.text("succession_god").contains("%d less kept power" % int(RulerRules.ruler_data("thornmane_avatar").succession.minus)))
	assert_true(RulesCodex.text("ruler_healing").contains("a quarter of its maximum hit points, rounded up"))
	assert_true(RulesCodex.text("ruler_healing").contains("heals %d" % RulerRules.ruler_heal_amount(46)))
	assert_true(RulesCodex.text("ruler_death").contains("a ruler on a losing side is lost with its army; there are no retreats yet"), "§5.4's wording")
	for key in ["ruler_death", "succession", "succession_mortal", "succession_undying", "succession_god", "ruler_healing"]:
		assert_false(RulesCodex.text(key).contains("_"), "no raw ids in %s" % key)
