extends "res://tests/test_case.gd"
## M2-2 (#30): battles with rulers and mandates (design/M2_RULER.md §1.6, §2.3, §7.4). Fixed-seed tests
## pin each effect: rulers in their ranks (the Ever-Regent under the Volley shield rule, Skirmish reaching
## him), the ruler's +2 morale and the Great Thornmane's Dread, a fallen ruler leaving its army, the ruler
## counted in losses; Iron Discipline, Drilled Ranks, Veteran Levies, Royal Armories, Blood Frenzy and
## Feast of Victory; the "why" naming a mandate or the ruler; the report's ruler fields and the viewer;
## the odds forecast and the sacrifice preview moving with a mandate; same seed, same report; and a
## game without rulers fighting exactly the recorded M1 battle.
##
## Rulers are opt-in: every test here turns them on with GameState.with_rulers, except the M1 record.

const SCENE := "res://ui/battle_report_viewer.tscn"
## Ids that must never reach player-facing text ("_" catches every snake_case id).
const RAW_IDS := ["kingdom", "beasts", "crownkeep", "fangridge", "rivermarch", "thornvale", "wildmoor", "stonegate",
	"blackwood", "westwatch", "greenglade", "highcrag", "aurel_king", "ever_regent", "thornmane_avatar", "fang_chieftain",
	"knight_captain", "war_bear", "spearmen", "tuskers", "fangthrowers", "warchief", "_"]

## The M1 battle recorded on main (896ab57) before this change: TurnResolver.resolve on a state without
## rulers, AutoBattleResolver, seed 4242. A game without rulers must still fight exactly this battle.
const M1_EVENT_TEXT := "In Thornvale, Aurel Crown held against Thornmane Clans. Thornmane Clans (5 fighters), Aurel Crown (5 fighters). Thornmane Clans won after 4 rounds: Thornmane Clans' War Bear roared (-2 morale), and Aurel Crown broke a round sooner than it would have; Aurel Crown broke after losing 68% of its strength (morale 9 holds only to 65%) and fled with 22 hp unspent; even though Aurel Crown's Knight Captain inspired the line. Thornmane Clans lost 3 of 5 fighters; Aurel Crown lost 4 of 5 fighters, and the last one fled. Aurel Crown routed, and its army was destroyed as it fled (5 fighters lost; there are no retreats yet)."
const M1_LINES := [
	"Battle of Thornvale (forest). Thornmane Clans (attacking) with the Thornmane Clans army at Thornvale (4 units, led by Warchief); Aurel Crown (defending) with the Aurel Crown army at Thornvale (4 units, led by Knight Captain).",
	"Round 1: Thornmane Clans dealt 23 damage (5 of 5 hits), Aurel Crown dealt 26 damage (5 of 5 hits). Aurel Crown's Knights charged home for 3 extra damage. Aurel Crown's Spearmen fell. Aurel Crown's Spearmen fell.",
	"Round 2: Thornmane Clans dealt 23 damage (4 of 5 hits), Aurel Crown dealt 15 damage (3 of 3 hits). Thornmane Clans' wounded Tuskers went berserk (+3 attack). Thornmane Clans' Tuskers fell. Aurel Crown's Knights fell.",
	"Round 3: Thornmane Clans dealt 15 damage (3 of 4 hits), Aurel Crown dealt 6 damage (1 of 2 hits). Thornmane Clans' wounded Tuskers went berserk (+3 attack). Thornmane Clans' Fangthrowers fell. Aurel Crown's Crossbowmen fell.",
	"Round 4: Thornmane Clans dealt 4 damage (1 of 3 hits), Aurel Crown dealt 6 damage (1 of 1 hits). Thornmane Clans' wounded Tuskers went berserk (+3 attack). Thornmane Clans' Tuskers fell. Aurel Crown broke and fled after losing 68% of its strength (morale 9 holds only to 65%).",
	"Casualties: Thornmane Clans lost 3 of 5 fighters; Aurel Crown lost 4 of 5 fighters, and the last one fled.",
	"Hits: Thornmane Clans hit 76% of the time (13 of 17; each attack had a 56-76% chance, about 69% on average); Aurel Crown hit 91% of the time (10 of 11; each attack had a 80-90% chance, about 85% on average).",
	"Result: Thornmane Clans won after 4 rounds: the enemy broke and fled.",
	"Why: Thornmane Clans' War Bear roared (-2 morale), and Aurel Crown broke a round sooner than it would have; Aurel Crown broke after losing 68% of its strength (morale 9 holds only to 65%) and fled with 22 hp unspent; even though Aurel Crown's Knight Captain inspired the line.",
	"Aftermath: Aurel Crown routed, and its army was destroyed as it fled (5 fighters lost; there are no retreats yet).",
]
const M1_FACTORS := "Berserk|beasts|7.6;Pack Leader|beasts|5.2;Skirmish|beasts|2.6;Charge|kingdom|2.6;Shield Wall|kingdom|1.5;Volley|kingdom|4.4;commander|kingdom|5.1;terrain|kingdom|6.8;rout|beasts|11.0;Fury|beasts|22.0;morale_commander|kingdom|22.0;morale_Inspire|kingdom|22.0;numbers|beasts|8.2;luck|beasts|2.4;"
const M1_ODDS := "Likely win: Thornmane Clans won 16 of 24 test battles fought with these armies (67%). Main reasons: Thornmane Clans' Warchief (+2 morale); Thornmane Clans has the bigger force (90 hp against 68). Each real battle still has its own rolls."
const M1_STATE_SHA := "27f8a807d8da7993553fbcb7ab06286a81371dd952c50a0f302a80269d14348f"


# --- fixtures -------------------------------------------------------------------------------------

## A game with rulers (`builds` as GameState.with_rulers takes them; the defaults give each faction a
## ruler without mandates), with every army removed: tests place their own. A ruler is never alive
## off the map (GameState.validate, #49), so until _ruler() puts one on the map it counts as dead, with
## its successor due long after any test ends. Off the map it fights in no battle either way.
func _game(builds: Dictionary = {}) -> GameState:
	var all := {"kingdom": {"ruler": "aurel_king", "mandates": []}, "beasts": {"ruler": "fang_chieftain", "mandates": []}}
	for fid in builds:
		all[fid] = builds[fid]
	var errors := []
	var s := GameState.with_rulers(7, all, errors)
	assert_eq(errors, [], "the rulers set up")
	s.armies.clear()
	for f in s.factions:
		f.ruler_status = RulerRules.DEAD
		f.successor_turn = 999
		f.successor_power = f.kept_power
	return s


## An army of `owner` at `location` with these unit and commander ids, every unit at its maximum hp.
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
			var u := Unit.new(ut, owner)
			u.current_hp = RulerRules.unit_max_hp(s, u)
			a.units.append(u)
	s.armies.append(a)
	return a


## `fid`'s ruler at `location` in its own army, alive and at full hp, with `kept` kept power (-1: as built).
func _ruler(s: GameState, fid: String, location: String, kept: int = -1, id: String = "") -> Army:
	var f := s.find_faction(fid)
	if kept >= 0:
		f.kept_power = kept
	f.ruler_status = RulerRules.ALIVE
	f.successor_turn = 0
	f.successor_power = 0
	RulerRules.refresh_ruler_type(f)
	var a := Army.new()
	a.id = id if not id.is_empty() else "%s-9" % fid
	a.owner = fid
	a.location = location
	a.ruler = Unit.new(f.ruler_unit_type, fid)
	s.armies.append(a)
	return a


## Fights every army in `pid` against each other (AutoBattleResolver.fight; armies untouched).
func _fight(s: GameState, pid: String, seed_value: int, defender: String = "", kind: String = "province") -> Dictionary:
	return AutoBattleResolver.fight(_sides_at(s, pid), _ctx(s, pid, defender, kind), SeededRNG.new(seed_value)).result


## The BattleResolver call TurnResolver makes (losses applied to the armies).
func _resolve_battle(s: GameState, pid: String, seed_value: int, defender: String = "") -> Dictionary:
	return AutoBattleResolver.new().resolve_battle({"kind": "province", "provinces": [pid], "defender": defender,
		"sides": _sides_at(s, pid), "state": s}, SeededRNG.new(seed_value))


func _sides_at(s: GameState, pid: String) -> Array:
	var by := {}
	for a in s.armies:
		if a.location == pid:
			if not by.has(a.owner):
				by[a.owner] = []
			by[a.owner].append(a)
	var fids: Array = by.keys()
	fids.sort()
	var sides := []
	for fid in fids:
		sides.append({"faction": fid, "armies": by[fid]})
	return sides


func _ctx(s: GameState, pid: String, defender: String = "", kind: String = "province") -> Dictionary:
	return {"kind": kind, "defender": defender, "province": s.find_province(pid), "province_ids": [pid], "state": s}


## The resolver's internal sides for the armies in `pid`, to check one rule at a time.
func _built(s: GameState, pid: String, kind: String = "province") -> Array:
	return AutoBattleResolver._build_sides(_sides_at(s, pid), "", s, kind)


func _side(report: Dictionary, fid: String) -> Dictionary:
	for sr in report.sides:
		if sr.faction == fid:
			return sr
	return {}


func _fighter_named(side: Dictionary, name: String) -> Dictionary:
	for f in side.fighters:
		if f.name == name:
			return f
	return {}


func _ruler_fighter(side: Dictionary) -> Dictionary:
	for f in side.fighters:
		if f.ruler:
			return f
	return {}


func _all_text(report: Dictionary) -> String:
	var parts: Array = report.lines.duplicate()
	parts.append(report.why)
	parts.append(report.summary)
	for f in report.all_factors:
		parts.append(f.text)
		parts.append(f.brief)
	for sr in report.sides:
		parts.append(sr.roster.text)
	return "\n".join(parts)


func _assert_no_raw_ids(text: String, what: String) -> void:
	assert_false(text.strip_edges().is_empty(), "%s has text" % what)
	for id in RAW_IDS:
		assert_false(text.contains(id), "%s shows no raw id '%s': %s" % [what, id, text])


## The first seed in 1..`last` whose report's top "why" is `factor_id`, or -1.
func _seed_with_top(s: GameState, pid: String, factor_id: String, last: int = 200, defender: String = "") -> int:
	for sd in range(1, last + 1):
		var r := _fight(s, pid, sd, defender)
		if not r.report.factors.is_empty() and r.report.factors[0].id == factor_id:
			return sd
	return -1


# --- a game without rulers is the M1 game ------------------------------------------------------------

func test_a_game_without_rulers_fights_the_recorded_m1_battle() -> void:
	var s := GameState.new(99)
	s.armies.clear()
	for spec in [["kingdom-1", "kingdom", "thornvale", ["spearmen", "spearmen", "crossbowmen", "knights", "knight_captain"]],
			["beasts-2", "beasts", "wildmoor", ["tuskers", "tuskers", "fangthrowers", "war_bear", "warchief"]]]:
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
	var before := s.deep_copy()
	var r := TurnResolver.resolve(s, {"beasts": [MoveOrder.new("beasts-2", "thornvale")]}, 4242, AutoBattleResolver.new())
	var battle: Dictionary = r.events.filter(func(e): return e.type == "battle")[0]
	assert_eq(battle.text, M1_EVENT_TEXT, "the battle line is the M1 one")
	assert_eq(battle.numbers.report.lines, M1_LINES, "every report line is the M1 one")
	var factors := ""
	for f in battle.numbers.report.all_factors:
		factors += "%s|%s|%s;" % [f.id, f.faction, str(f.impact)]
	assert_eq(factors, M1_FACTORS, "every factor and its worth is the M1 one")
	assert_eq(JSON.stringify(r.new_state.to_dict()).sha256_text(), M1_STATE_SHA, "the state after the turn is the M1 one")
	for sr in battle.numbers.report.sides:
		assert_false(sr.has("ruler") or sr.has("mandates"), "no ruler or mandate fields without rulers")
		assert_false(sr.roster.has("ruler"))
	assert_false(battle.numbers.report.has("feast"))
	assert_false(battle.numbers.has("rulers_lost"))
	assert_eq(Forecast.battle_odds(before, "beasts", ["beasts-2"], "thornvale").text, M1_ODDS, "the odds are the M1 ones")
	# Mandates only count with a ruler: a faction without one has none, whatever its data says.
	assert_eq(RulerRules.battle_effects(s, "kingdom").mandates, [])
	assert_eq(RulerRules.battle_effects(s, "kingdom").base_hit, AutoBattleResolver.BASE_HIT)


# --- rulers in the ranks (§1.6) -----------------------------------------------------------------------

func test_a_front_rank_ruler_is_targetable_from_round_one() -> void:
	for c in [["kingdom", "aurel_king"], ["beasts", "thornmane_avatar"], ["beasts", "fang_chieftain"]]:
		var fid: String = c[0]
		var enemy := "beasts" if fid == "kingdom" else "kingdom"
		var s := _game({fid: {"ruler": c[1], "mandates": []}})
		_army(s, "%s-1" % fid, fid, "rivermarch", ["spearmen", "spearmen", "spearmen"] if fid == "kingdom" else ["tuskers", "tuskers", "tuskers"])
		_ruler(s, fid, "rivermarch", 5)
		_army(s, "%s-2" % enemy, enemy, "rivermarch", ["tuskers"] if enemy == "beasts" else ["spearmen"])
		var sides := _built(s, "rivermarch")
		var si := 0 if sides[0].faction == fid else 1
		var rf := _ruler_fighter(sides[si])
		assert_eq(rf.tier, 0, "%s stands in the front rank" % c[1])
		var attacker: Dictionary = sides[1 - si].fighters[0]
		assert_true(AutoBattleResolver._targets(sides, 1 - si, [0, 1], attacker).has(rf), "%s can be attacked in round 1" % c[1])
	# And in a real battle the King takes hits in round 1 on some seed.
	var hit_first := false
	for sd in range(1, 40):
		var s := _game()
		_army(s, "kingdom-1", "kingdom", "rivermarch", ["spearmen", "spearmen"])
		_ruler(s, "kingdom", "rivermarch", 0)
		_army(s, "beasts-2", "beasts", "rivermarch", ["tuskers", "tuskers", "tuskers"])
		var sides := _built(s, "rivermarch")
		AutoBattleResolver._fight_round(sides, 1, {"terrain": "plains", "fort": false, "kind": "province"}, SeededRNG.new(sd))
		if _ruler_fighter(sides[1]).hp < _ruler_fighter(sides[1]).max:
			hit_first = true
			break
	assert_true(hit_first, "a front-rank King is hit in the first round")


func test_the_regent_is_shielded_like_volley_until_the_front_thins_and_skirmish_reaches_him() -> void:
	var s := _game({"kingdom": {"ruler": "ever_regent", "mandates": []}})
	_army(s, "kingdom-1", "kingdom", "rivermarch", ["spearmen", "spearmen", "spearmen"])
	_ruler(s, "kingdom", "rivermarch", 4)
	_army(s, "beasts-2", "beasts", "rivermarch", ["tuskers", "fangthrowers"])
	var sides := _built(s, "rivermarch")
	var crown: Dictionary = sides[1]
	var regent := _ruler_fighter(crown)
	assert_eq(regent.tier, 1, "the Ever-Regent stands in the second rank")
	var tusker := _fighter_named(sides[0], "Tuskers")
	var thrower := _fighter_named(sides[0], "Fangthrowers")
	assert_false(AutoBattleResolver._targets(sides, 0, [0, 1], tusker).has(regent), "three Spearmen shield him from Tuskers")
	assert_true(AutoBattleResolver._targets(sides, 0, [0, 1], thrower).has(regent), "Skirmish reaches him behind the front")
	assert_true(AutoBattleResolver._screened(crown, regent))
	# One Spearman left: one front-rank fighter shields one second-rank fighter, so he is still covered.
	crown.fighters[0].alive = false
	crown.fighters[1].alive = false
	assert_false(AutoBattleResolver._targets(sides, 0, [0, 1], tusker).has(regent), "one Spearman still shields him alone")
	# The front falls: anyone can reach him.
	crown.fighters[2].alive = false
	assert_eq(AutoBattleResolver._targets(sides, 0, [0, 1], tusker), [regent], "with the front gone, he is the target")
	# With Crossbowmen beside him the second rank is bigger: a front of one shields neither.
	var thin := _game({"kingdom": {"ruler": "ever_regent", "mandates": []}})
	_army(thin, "kingdom-1", "kingdom", "rivermarch", ["spearmen", "crossbowmen"])
	_ruler(thin, "kingdom", "rivermarch", 4)
	_army(thin, "beasts-2", "beasts", "rivermarch", ["tuskers"])
	var ts := _built(thin, "rivermarch")
	assert_true(AutoBattleResolver._targets(ts, 0, [0, 1], ts[0].fighters[0]).has(_ruler_fighter(ts[1])),
		"one Spearman can't shield a Crossbowman and the Regent")
	# In real battles behind three Spearmen, Tuskers never touch him while the Spearmen all stand.
	for sd in range(1, 25):
		var b := _game({"kingdom": {"ruler": "ever_regent", "mandates": []}})
		_army(b, "kingdom-1", "kingdom", "rivermarch", ["spearmen", "spearmen", "spearmen"])
		_ruler(b, "kingdom", "rivermarch", 4)
		_army(b, "beasts-2", "beasts", "rivermarch", ["tuskers", "tuskers"])
		var bs := _built(b, "rivermarch")
		AutoBattleResolver._fight_round(bs, 1, {"terrain": "plains", "fort": false, "kind": "province"}, SeededRNG.new(sd))
		assert_eq(_ruler_fighter(bs[1]).hp, _ruler_fighter(bs[1]).max, "seed %d: the Regent is untouched in round 1" % sd)


func test_the_ruler_gives_morale_while_it_stands_and_morale_alone() -> void:
	var s := _game()
	_army(s, "kingdom-1", "kingdom", "rivermarch", ["spearmen", "spearmen", "knight_captain"])
	_ruler(s, "kingdom", "rivermarch", 10)
	_army(s, "beasts-2", "beasts", "rivermarch", ["tuskers"])
	var sides := _built(s, "rivermarch")
	var m := AutoBattleResolver._morale(sides, 1, [0, 1])
	assert_eq(m.parts.get("ruler", 0), RulerData.RULER_MORALE, "+2 while the King stands")
	assert_eq(m.parts.get("commander", 0), AutoBattleResolver.COMMANDER_MORALE, "on top of the commander's +2")
	assert_eq(sides[1].base_morale, 6, "base morale is the units' average: the ruler is not a unit")
	_ruler_fighter(sides[1]).alive = false
	assert_false(AutoBattleResolver._morale(sides, 1, [0, 1]).parts.has("ruler"), "a fallen ruler gives nothing")
	# Alone, a side's base morale is the highest among its commanders and ruler (§1.6).
	var lone := _game({"beasts": {"ruler": "thornmane_avatar", "mandates": []}})
	_ruler(lone, "beasts", "rivermarch", 3)
	_army(lone, "kingdom-1", "kingdom", "rivermarch", ["spearmen"])
	var ls := _built(lone, "rivermarch")
	assert_eq(ls[0].base_morale, RulerRules.ruler_stats("thornmane_avatar", 3).morale, "the avatar's own morale, 14")
	# Pack Leader is for units only: never the ruler.
	var pack := _game()
	_army(pack, "beasts-2", "beasts", "rivermarch", ["tuskers", "warchief"])
	_ruler(pack, "beasts", "rivermarch", 5)
	_army(pack, "kingdom-1", "kingdom", "rivermarch", ["spearmen"])
	var ps := _built(pack, "rivermarch")
	var env := {"terrain": "plains", "fort": false}
	assert_true(AutoBattleResolver._attack(_fighter_named(ps[0], "Tuskers"), ps[0], env).parts.has("Pack Leader"))
	assert_false(AutoBattleResolver._attack(_ruler_fighter(ps[0]), ps[0], env).parts.has("Pack Leader"), "rulers don't get Pack Leader")


func test_dread_works_only_in_the_avatars_province_battles_while_it_stands() -> void:
	var s := _game({"beasts": {"ruler": "thornmane_avatar", "mandates": []}})
	_army(s, "kingdom-1", "kingdom", "rivermarch", ["spearmen", "spearmen", "spearmen"])
	_army(s, "beasts-2", "beasts", "rivermarch", ["tuskers"])
	_ruler(s, "beasts", "rivermarch", 7)  # ability rank 3: Dread 1 (M2-8: 1 at every rank)
	var dread := RulerRules.ability_value("thornmane_avatar", RulerRules.ability_rank(7))
	assert_eq(dread, 1)
	assert_eq(RulerRules.dread_value(s, "beasts"), dread)
	var sides := _built(s, "rivermarch")
	assert_eq(AutoBattleResolver._morale(sides, 1, [0, 1]).parts.get("Dread", 0), -dread, "the Crown loses 1 morale")
	assert_false(AutoBattleResolver._morale(sides, 0, [0, 1]).parts.has("Dread"), "never the avatar's own side")
	_ruler_fighter(sides[0]).alive = false
	assert_false(AutoBattleResolver._morale(sides, 1, [0, 1]).parts.has("Dread"), "not once the avatar has fallen")
	# Not in a border battle.
	var border := _built(s, "rivermarch", "border")
	assert_false(AutoBattleResolver._morale(border, 1, [0, 1]).parts.has("Dread"), "no Dread on a border")
	# Not for another ruler: the Ninth Fang has Warband Muster.
	var fang := _game()
	_army(fang, "kingdom-1", "kingdom", "rivermarch", ["spearmen"])
	_ruler(fang, "beasts", "rivermarch", 10)
	assert_false(AutoBattleResolver._morale(_built(fang, "rivermarch"), 1, [0, 1]).parts.has("Dread"), "only the avatar has Dread")
	# A real battle's morale checks carry it, and the report names it.
	var r := _fight(s, "rivermarch", 3)
	var crown := _side(r.report, "kingdom")
	assert_eq(crown.morale_log[0].parts.get("Dread", 0), -dread, "the Crown's first morale check")
	assert_eq(_side(r.report, "beasts").ruler.dread, dread, "the report says Dread worked")
	assert_false(_side(_fight(s, "rivermarch", 3, "", "border").report, "beasts").ruler.has("dread"), "and not on a border")


func test_a_ruler_that_falls_in_a_winning_battle_leaves_its_army_and_dies() -> void:
	# A 0-kept King beside Knights against a war band: the first seed where he falls but the Crown wins.
	var found := false
	for sd in range(1, 101):
		var s := _game()
		_army(s, "kingdom-1", "kingdom", "rivermarch", ["knights", "knights", "knights", "knight_captain"])
		var king := _ruler(s, "kingdom", "rivermarch", 0, "kingdom-3")
		_army(s, "beasts-2", "beasts", "rivermarch", ["tuskers", "tuskers", "tuskers", "war_bear"])
		var r := _resolve_battle(s, "rivermarch", sd)
		var crown := _side(r.report, "kingdom")
		if r.winner != "kingdom" or not crown.ruler.fell:
			continue
		found = true
		assert_eq(king.ruler, null, "the fallen ruler left its army (M2-3's contract)")
		assert_true(crown.lost.has("King Corvane I"), "he is among the losses")
		assert_true(r.report.lines.any(func(l): return String(l).contains("Aurel Crown's King Corvane I fell.")), "the round line says so")
		var casualty: String = r.report.lines.filter(func(l): return String(l).begins_with("Casualties: "))[0]
		assert_true(casualty.contains("Aurel Crown lost %d of %d fighters" % [crown.fighters_lost, crown.fighters_start]), casualty)
		break
	assert_true(found, "a 0-kept King can fall while his side wins")
	# Through the turn: the death is recorded and the battle line says he fell.
	var t := GameState.with_rulers(7, {"kingdom": {"ruler": "aurel_king", "mandates": ["royal_armories", "heavy_tithes", "veteran_levies"]}}, [])
	t.current_turn = 3
	for a in t.armies.duplicate():
		if a.location == "highcrag":
			t.armies.erase(a)
	var died := false
	for sd in range(1, 80):
		var s := t.deep_copy()
		var raider := _army(s, "beasts-9", "beasts", "highcrag", ["tuskers", "tuskers", "tuskers", "war_bear"])
		var res := TurnResolver.resolve(s, {"beasts": [MoveOrder.new(raider.id, "crownkeep")]}, sd, AutoBattleResolver.new())
		var deaths: Array = res.events.filter(func(e): return e.type == "ruler_died")
		var battle: Array = res.events.filter(func(e): return e.type == "battle")
		if deaths.is_empty() or battle[0].numbers.winner != "kingdom":
			continue
		died = true
		assert_eq(deaths[0].cause, "fell_while_winning")
		assert_true(String(battle[0].text).contains("Aurel Crown won, but King Corvane I fell in the battle."), battle[0].text)
		assert_eq(battle[0].numbers.rulers_lost, 1)
		assert_eq(RulerRules.ruler_army(res.new_state, "kingdom"), null)
		assert_true(res.new_state.validate([]))
		_assert_no_raw_ids(String(battle[0].text), "battle line")
		break
	assert_true(died, "a 0-kept King defending Crownkeep falls on some seed while the Crown wins")


func test_the_ruler_is_counted_in_losses() -> void:
	# A lone King against a war band, with the real rules and with the stub.
	var s := GameState.with_rulers(7, {"kingdom": {"ruler": "aurel_king", "mandates": []}}, [])
	s.current_turn = 3
	var king := RulerRules.ruler_army(s, "kingdom")
	for a in s.armies.duplicate():
		if a.location == "blackwood" or a.location == "ebonpeak":
			s.armies.erase(a)
	king.location = "blackwood"
	var raider := _army(s, "beasts-9", "beasts", "ebonpeak", ["war_bear", "war_bear", "tuskers", "warchief"])
	var orders := {"beasts": [MoveOrder.new(raider.id, "blackwood")]}
	var real := TurnResolver.resolve(s, orders, 5, AutoBattleResolver.new())
	var battle: Dictionary = real.events.filter(func(e): return e.type == "battle")[0]
	var crown := _side(battle.numbers.report, "kingdom")
	assert_eq(crown.fighters_start, 1, "the King is a fighter")
	assert_true(String(battle.text).contains("King Corvane I lost"), battle.text)
	assert_false(String(battle.text).contains("0 fighters") or String(battle.text).contains("0 units"), battle.text)
	assert_eq(battle.numbers.rulers_lost, 1)
	var stub := TurnResolver.resolve(s, orders, 5, StubBattleResolver.new())
	var stub_battle: Dictionary = stub.events.filter(func(e): return e.type == "battle")[0]
	assert_true(String(stub_battle.text).contains("lost 1 army (King Corvane I)."), stub_battle.text)
	# Beside an army: the King is named among the fighters lost.
	var s2 := s.deep_copy()
	var guard := _army(s2, "kingdom-8", "kingdom", "blackwood", ["spearmen"])
	var both := TurnResolver.resolve(s2, orders, 5, AutoBattleResolver.new())
	var b2: Dictionary = both.events.filter(func(e): return e.type == "battle")[0]
	if b2.numbers.winner == "beasts":
		assert_true(String(b2.text).contains("2 fighters lost, among them King Corvane I"), b2.text)
	assert_true(String(TurnResolver.resolve(s2, orders, 5, StubBattleResolver.new()).events.filter(
		func(e): return e.type == "battle")[0].text).contains("(1 unit and King Corvane I)"), "the stub line counts both")
	assert_true(guard != null)
	_assert_no_raw_ids(String(battle.text) + String(stub_battle.text) + String(b2.text), "loss lines")


# --- the battle mandates (§2.3) -----------------------------------------------------------------------

func test_iron_discipline_holds_only_while_a_commander_stands() -> void:
	var held_any := false
	for sd in range(1, 80):
		var s := _game({"beasts": {"ruler": "fang_chieftain", "mandates": ["iron_discipline"]}})
		_army(s, "kingdom-1", "kingdom", "rivermarch", ["spearmen", "spearmen", "spearmen", "crossbowmen", "knights", "knight_captain"])
		_army(s, "beasts-2", "beasts", "rivermarch", ["tuskers", "tuskers", "fangthrowers", "fangthrowers", "warchief"])
		var r := _fight(s, "rivermarch", sd)
		var clans := _side(r.report, "beasts")
		var chief_fell := 0
		for round_data in r.report.rounds:
			for h in round_data.highlights:
				if String(h) == "Thornmane Clans' Warchief fell.":
					chief_fell = round_data.round
		for e in clans.morale_log:
			if e.lost_pct < e.break_pct:
				assert_false(e.has("held_by"), "seed %d: nothing to hold in round %d" % [sd, e.round])
				continue
			var chief_standing: bool = chief_fell == 0 or e.round < chief_fell
			# M2-8 (#36): it holds through every round but the last; the round cap is not a way to win.
			if chief_standing and e.round < AutoBattleResolver.ROUND_CAP:
				held_any = true
				assert_eq(e.get("held_by", ""), "Warchief", "seed %d: held in round %d while the Warchief stood" % [sd, e.round])
				assert_false(clans.routed and clans.out_round == e.round, "seed %d: no rout in round %d" % [sd, e.round])
			else:
				assert_false(e.has("held_by"), "seed %d: the usual check once the Warchief fell, or in the last round" % sd)
				assert_true(clans.routed and clans.out_round == e.round, "seed %d: it broke in round %d" % [sd, e.round])
				break
	assert_true(held_any, "Iron Discipline held a line on some seed")
	# Rulers don't count: the Fang alone with the units does not hold the line.
	var s2 := _game({"beasts": {"ruler": "fang_chieftain", "mandates": ["iron_discipline"]}})
	_army(s2, "kingdom-1", "kingdom", "rivermarch", ["spearmen", "spearmen"])
	_army(s2, "beasts-2", "beasts", "rivermarch", ["tuskers"])
	_ruler(s2, "beasts", "rivermarch", 5)
	var sides := _built(s2, "rivermarch")
	assert_true(sides[0].iron, "the Clans have Iron Discipline")
	assert_eq(AutoBattleResolver._iron_holder(sides[0]), "", "the ruler is not a commander")
	for sd in range(1, 30):
		for e in _side(_fight(s2, "rivermarch", sd).report, "beasts").morale_log:
			assert_false(e.has("held_by"), "seed %d: no commander, no hold" % sd)


func test_iron_discipline_does_not_hold_a_defender_through_the_round_cap() -> void:
	# M2-8 (#36): a defender held past its break point by Iron Discipline used to win every battle that
	# reached the round cap (the defender holds there). Now the usual check applies at the end of the
	# last round, so such a line breaks and the attacker wins.
	var found := 0
	for sd in range(1, 400):
		var s := _game({"beasts": {"ruler": "fang_chieftain", "mandates": ["iron_discipline"]}})
		_army(s, "kingdom-1", "kingdom", "fangridge", ["spearmen", "spearmen", "spearmen", "crossbowmen", "crossbowmen", "knights", "knight_captain"])
		_army(s, "beasts-2", "beasts", "fangridge", ["tuskers", "tuskers", "tuskers", "fangthrowers", "fangthrowers", "fangthrowers", "warchief"])
		var r := _fight(s, "fangridge", sd, "beasts")
		var clans := _side(r.report, "beasts")
		if clans.morale_log.size() < AutoBattleResolver.ROUND_CAP:
			continue
		var last: Dictionary = clans.morale_log.back()
		if last.round != AutoBattleResolver.ROUND_CAP or last.lost_pct < last.break_pct:
			continue
		var chief_up := true
		for round_data in r.report.rounds:
			for h in round_data.highlights:
				if String(h) == "Thornmane Clans' Warchief fell.":
					chief_up = false
		if not chief_up:
			continue
		assert_false(last.has("held_by"), "seed %d: not held in the last round" % sd)
		if r.report.end == "mutual":
			continue  # both lines broke in the last round: the larger share left keeps the field, as in M1
		found += 1
		assert_true(clans.routed, "seed %d: the line broke at the end of round %d" % [sd, AutoBattleResolver.ROUND_CAP])
		assert_eq(r.winner, "kingdom", "seed %d: the attacker wins instead of the round cap holding" % sd)
		assert_ne(r.report.end, "round_cap", "seed %d: it was not decided by the round cap" % sd)
		var said := false
		for h in r.report.rounds.back().highlights:
			said = said or String(h).contains("only until the last round")
		assert_true(said, "seed %d: the last round says why the line broke" % sd)
		var earlier: Array = clans.morale_log.filter(func(e): return e.round < AutoBattleResolver.ROUND_CAP and e.lost_pct >= e.break_pct)
		for e in earlier:
			assert_eq(e.get("held_by", ""), "Warchief", "seed %d: held in round %d" % [sd, e.round])
	assert_true(found > 0, "some battle reached the last round with the line held past its break point")


func test_drilled_ranks_makes_the_base_hit_chance_70() -> void:
	var base: int = RulerRules.mandate_data("drilled_ranks").base_hit
	assert_eq(base, 70, "§2.3")
	assert_eq(AutoBattleResolver.hit_chance(9, 8, base), 74)
	assert_eq(AutoBattleResolver.hit_chance(30, 1, base), AutoBattleResolver.MAX_HIT, "the cap stays")
	assert_eq(AutoBattleResolver.hit_chance(1, 30, base), AutoBattleResolver.MIN_HIT, "the floor stays")
	# Spearmen (attack 9) against a War Bear (defense 8): 64% at base, 74% with Drilled Ranks.
	for c in [[[], 64], [["drilled_ranks"], 74]]:
		var s := _game({"kingdom": {"ruler": "aurel_king", "mandates": c[0]}})
		_army(s, "kingdom-1", "kingdom", "rivermarch", ["spearmen", "spearmen", "spearmen"])
		_army(s, "beasts-2", "beasts", "rivermarch", ["war_bear"])
		var crown := _side(_fight(s, "rivermarch", 2).report, "kingdom")
		assert_eq(crown.hit_chance_range, [c[1], c[1]], "%s: every Crown attack had %d%%" % [c[0], c[1]])
	# It counts for the ruler and commanders too ("fighters"), and only for its own side.
	var both := _game({"beasts": {"ruler": "fang_chieftain", "mandates": ["drilled_ranks"]}})
	_army(both, "kingdom-1", "kingdom", "rivermarch", ["spearmen"])
	_army(both, "beasts-2", "beasts", "rivermarch", ["warchief"])
	_ruler(both, "beasts", "rivermarch", 0)
	var sides := _built(both, "rivermarch")
	assert_eq(sides[0].base_hit, 70)
	assert_eq(sides[1].base_hit, AutoBattleResolver.BASE_HIT)
	var r := _fight(both, "rivermarch", 4)
	var clans := _side(r.report, "beasts")
	var expect_lo: int = AutoBattleResolver.hit_chance(RulerRules.ruler_stats("fang_chieftain", 0).attack, 9, 70)
	assert_true(clans.hit_chance_range[0] >= mini(expect_lo, 90), "the Fang and the Warchief hit at the higher base: %s" % [clans.hit_chance_range])
	assert_true(clans.triggers.get("mandate_drilled_ranks", 0) > 0, "Drilled Ranks changed attacks")


func test_veteran_levies_raises_maximum_hp_everywhere() -> void:
	var s := GameState.with_rulers(7, {"kingdom": {"ruler": "aurel_king", "mandates": ["veteran_levies"]}}, [])
	for u in s.find_army("kingdom-1").units:
		assert_eq(u.current_hp, u.type.hp + 2, "the starting %s arrive at the new maximum" % u.type.name)
	assert_eq(s.find_army("kingdom-1").commander.current_hp, s.find_army("kingdom-1").commander.type.hp, "commanders don't get it")
	for u in s.find_army("beasts-2").units:
		assert_eq(u.current_hp, u.type.hp, "the other side has no Veteran Levies")
	assert_true(s.validate([]))
	# Recruits arrive at the new maximum too.
	var r := TurnResolver.resolve(s, {"kingdom": [RecruitOrder.new("spearmen")]}, 3, StubBattleResolver.new())
	var army: Army = r.new_state.find_army("kingdom-1")
	assert_eq(army.units.back().current_hp, army.units.back().type.hp + 2, "a recruit at its maximum")
	# In battle the maximum is the new one: a unit at its type's hp is wounded (Berserk wakes).
	var b := _game({"beasts": {"ruler": "fang_chieftain", "mandates": ["veteran_levies"]}})
	var band := _army(b, "beasts-2", "beasts", "rivermarch", ["tuskers"])
	_army(b, "kingdom-1", "kingdom", "rivermarch", ["spearmen"])
	var sides := _built(b, "rivermarch")
	var tusker := _fighter_named(sides[0], "Tuskers")
	assert_eq(tusker.max, 16)
	assert_false(AutoBattleResolver._attack(tusker, sides[0], {"terrain": "plains", "fort": false}).parts.has("Berserk"), "full at 16")
	band.units[0].current_hp = 14
	tusker = _fighter_named(_built(b, "rivermarch")[0], "Tuskers")
	assert_true(AutoBattleResolver._attack(tusker, sides[0], {"terrain": "plains", "fort": false}).parts.has("Berserk"), "14 of 16 is wounded")
	# Mending Light heals up to the new maximum.
	var m := GameState.with_rulers(7, {"kingdom": {"ruler": "ever_regent", "mandates": ["veteran_levies"]}}, [])
	var spear: Unit = m.find_army("kingdom-1").units[0]
	spear.current_hp = 5
	var mend := RulerRules.apply_mending_light(m, "kingdom")
	assert_eq(spear.current_hp, mini(5 + int(mend.amount), spear.type.hp + 2), "healed toward 10, not 8")


func test_royal_armories_adds_its_parts_from_unit_stats_to_units_only() -> void:
	var s := _game({"kingdom": {"ruler": "aurel_king", "mandates": ["royal_armories"]}})
	_army(s, "kingdom-1", "kingdom", "rivermarch", ["spearmen", "crossbowmen", "knight_captain"])
	_ruler(s, "kingdom", "rivermarch", 6)
	_army(s, "beasts-2", "beasts", "rivermarch", ["tuskers"])
	var sides := _built(s, "rivermarch")
	var env := {"terrain": "plains", "fort": false}
	var tusker := _fighter_named(sides[0], "Tuskers")
	for name in ["Spearmen", "Crossbowmen"]:
		var f := _fighter_named(sides[1], name)
		var us := RulerRules.unit_stats(s, "kingdom", f.type.id)
		var atk := AutoBattleResolver._attack(f, sides[1], env)
		assert_eq(atk.parts.get("mandate_royal_armories", 0), 1, "%s +1 attack" % name)
		assert_eq(atk.value, us.attack, "%s attacks with unit_stats' number" % name)
		var dfn := AutoBattleResolver._defense(f, sides[1], tusker, env)
		assert_false(dfn.parts.has("mandate_royal_armories"), "%s: Royal Armories adds no defense (M2-8, breakpoint-safe)" % name)
		assert_eq(dfn.value - int(dfn.parts.get("Shield Wall", 0)), us.defense, "%s defends with unit_stats' number" % name)
	for f in [_fighter_named(sides[1], "Knight Captain"), _ruler_fighter(sides[1])]:
		assert_false(AutoBattleResolver._attack(f, sides[1], env).parts.has("mandate_royal_armories"), "%s doesn't get it" % f.name)
		assert_false(AutoBattleResolver._defense(f, sides[1], tusker, env).parts.has("mandate_royal_armories"))


func test_blood_frenzy_works_only_below_full_hp_and_stacks_with_berserk() -> void:
	var s := _game({"beasts": {"ruler": "fang_chieftain", "mandates": ["blood_frenzy"]}})
	var band := _army(s, "beasts-2", "beasts", "rivermarch", ["tuskers", "fangthrowers", "warchief"])
	var fang := _ruler(s, "beasts", "rivermarch", 4)
	_army(s, "kingdom-1", "kingdom", "rivermarch", ["spearmen"])
	var env := {"terrain": "plains", "fort": false}
	var sides := _built(s, "rivermarch")
	var bonus: int = RulerRules.mandate_data("blood_frenzy").wounded_attack
	assert_eq(bonus, 3)
	for f in sides[0].fighters:
		assert_false(AutoBattleResolver._attack(f, sides[0], env).parts.has("mandate_blood_frenzy"), "%s at full hp: no frenzy" % f.name)
	band.units[0].current_hp -= 1
	band.units[1].current_hp -= 1
	band.commander.current_hp -= 1
	fang.ruler.current_hp -= 1
	sides = _built(s, "rivermarch")
	for f in sides[0].fighters:
		var atk := AutoBattleResolver._attack(f, sides[0], env)
		assert_eq(atk.parts.get("mandate_blood_frenzy", 0), bonus, "wounded %s is in a frenzy" % f.name)
	var tusker := AutoBattleResolver._attack(_fighter_named(sides[0], "Tuskers"), sides[0], env)
	assert_eq(int(tusker.parts.get("Berserk", 0)) + int(tusker.parts.get("mandate_blood_frenzy", 0)), 6, "a wounded Tusker: +6")
	# The enemy's wounds don't count: only the side with the mandate.
	var crown := _fighter_named(sides[1], "Spearmen")
	crown.hp -= 1
	assert_false(AutoBattleResolver._attack(crown, sides[1], env).parts.has("mandate_blood_frenzy"))


func test_feast_of_victory_heals_only_the_winner() -> void:
	var won := false
	var lost := false
	for sd in range(1, 60):
		var s := _game({"beasts": {"ruler": "fang_chieftain", "mandates": ["feast_of_victory"]}})
		var band := _army(s, "beasts-2", "beasts", "rivermarch", ["tuskers", "tuskers", "tuskers", "war_bear"])
		var line := _army(s, "kingdom-1", "kingdom", "rivermarch", ["spearmen", "spearmen", "crossbowmen", "knights"])
		var r := _resolve_battle(s, "rivermarch", sd)
		var clans := _side(r.report, "beasts")
		if r.winner == "beasts":
			for u in band.units:
				assert_eq(u.current_hp, RulerRules.unit_max_hp(s, u), "seed %d: %s healed to full" % [sd, u.type.name])
			var feast: Dictionary = r.report.get("feast", {})
			if not feast.is_empty() and not won:
				won = true
				assert_eq(feast.faction, "beasts", "the winner feasts")
				assert_eq(int(feast.fighters), clans.fighters_start - clans.fighters_lost, "every fighter still standing")
				assert_true(int(feast.healed) > 0, "a Feast is reported only when it healed someone")
		elif r.winner == "kingdom" and not lost:
			lost = true
			assert_false(r.report.has("feast"), "a loser never feasts")
			var wounded := line.units.any(func(u): return u.current_hp < u.type.hp)
			assert_true(wounded or _side(r.report, "kingdom").hp_end == _side(r.report, "kingdom").hp_start,
				"the Crown keeps its wounds: it has no Feast")
		if won and lost:
			break
	assert_true(won and lost, "the sample has a Clans win and a Clans loss")
	# Through the turn: the aftermath line says so.
	var t := GameState.with_rulers(7, {"beasts": {"ruler": "fang_chieftain", "mandates": ["feast_of_victory"]}}, [])
	t.current_turn = 2
	for a in t.armies.duplicate():
		if a.location == "westwatch" or a.location == "stonegate":
			t.armies.erase(a)
	_army(t, "kingdom-8", "kingdom", "westwatch", ["spearmen"])
	_army(t, "beasts-9", "beasts", "stonegate", ["tuskers", "tuskers", "war_bear"])
	var feasted := false
	for sd in range(1, 40):
		var res := TurnResolver.resolve(t, {"beasts": [MoveOrder.new("beasts-9", "westwatch")]}, sd, AutoBattleResolver.new())
		var battle: Dictionary = res.events.filter(func(e): return e.type == "battle")[0]
		if not battle.numbers.report.has("feast"):
			continue
		feasted = true
		assert_true(String(battle.text).contains("Feast of Victory: the Thornmane Clans' "), battle.text)
		assert_true(String(battle.numbers.report.lines.back()).contains("healed to full (+"), battle.numbers.report.lines.back())
		_assert_no_raw_ids(String(battle.text), "feast line")
		for u in res.new_state.find_army("beasts-9").units:
			assert_eq(u.current_hp, u.type.hp, "the winners are whole again")
		assert_true(res.new_state.validate([]))
		break
	assert_true(feasted, "a wounding win feasts")


# --- the "why" (§7.4) ---------------------------------------------------------------------------------

func test_a_constructed_battle_names_a_mandate_as_its_top_why() -> void:
	# Iron Discipline holding the Clans line while its Warchief stands.
	var iron := _game({"beasts": {"ruler": "fang_chieftain", "mandates": ["iron_discipline"]}})
	_army(iron, "kingdom-1", "kingdom", "rivermarch", ["knights", "knights", "knights", "knights", "knights"])
	_army(iron, "beasts-2", "beasts", "rivermarch", ["tuskers", "tuskers", "tuskers", "tuskers", "tuskers", "tuskers", "warchief"])
	var sd := _seed_with_top(iron, "rivermarch", "mandate_iron_discipline", 40)
	assert_true(sd > 0, "Iron Discipline tops the why on some seed")
	if sd > 0:
		var r := _fight(iron, "rivermarch", sd)
		assert_true(String(r.report.why).begins_with("Iron Discipline held the Thornmane Clans line past its breaking point (lost "), r.report.why)
		assert_true(String(r.report.why).contains("while its Warchief stood"), r.report.why)
		_assert_no_raw_ids(_all_text(r.report), "Iron Discipline report")
	# Blood Frenzy driving a wounded band.
	var frenzy := _game({"beasts": {"ruler": "fang_chieftain", "mandates": ["blood_frenzy"]}})
	_army(frenzy, "kingdom-1", "kingdom", "rivermarch", ["spearmen", "spearmen", "spearmen", "spearmen", "crossbowmen", "crossbowmen", "knights", "knights"])
	var band := _army(frenzy, "beasts-2", "beasts", "rivermarch", ["fangthrowers", "fangthrowers", "fangthrowers", "fangthrowers",
		"fangthrowers", "fangthrowers", "war_bear", "war_bear", "war_bear"])
	for u in band.units:
		u.current_hp -= 1
	var fs := _seed_with_top(frenzy, "rivermarch", "mandate_blood_frenzy", 40)
	assert_true(fs > 0, "Blood Frenzy tops the why on some seed")
	if fs > 0:
		var r := _fight(frenzy, "rivermarch", fs)
		assert_true(String(r.report.why).begins_with("Blood Frenzy gave Thornmane Clans' wounded fighters +3 attack, adding about "), r.report.why)
	# Royal Armories: a line of Crossbowmen behind a Spearman against Tuskers.
	var ra := _game({"kingdom": {"ruler": "aurel_king", "mandates": ["royal_armories"]}})
	_army(ra, "kingdom-1", "kingdom", "rivermarch", ["crossbowmen", "crossbowmen", "crossbowmen", "crossbowmen", "spearmen", "crossbowmen"])
	_army(ra, "beasts-2", "beasts", "rivermarch", ["tuskers", "tuskers", "fangthrowers", "tuskers", "tuskers"])
	# M2-8: as +1 attack only (a 4% better hit chance, no damage step) it is named in the why rather than
	# leading it; Iron Discipline and Blood Frenzy above still lead theirs.
	var rs := -1
	for ra_seed in range(1, 61):
		if String(_fight(ra, "rivermarch", ra_seed).report.why).contains("Royal Armories gave every Aurel Crown unit +1 attack, worth about "):
			rs = ra_seed
			break
	assert_true(rs > 0, "Royal Armories is named in the why on some seed")
	if rs > 0:
		var r := _fight(ra, "rivermarch", rs)
		assert_true(r.report.factors.any(func(f): return f.id == "mandate_royal_armories" and f.faction == "kingdom"), "its factor is the Crown's")


func test_another_constructed_battle_names_the_ruler() -> void:
	var s := _game()
	_army(s, "kingdom-1", "kingdom", "thornvale", ["spearmen", "crossbowmen", "knights", "knight_captain"])
	_ruler(s, "kingdom", "thornvale", 10)
	_army(s, "beasts-2", "beasts", "thornvale", ["tuskers", "fangthrowers", "war_bear", "warchief"])
	var sd := _seed_with_top(s, "thornvale", "ruler", 20, "beasts")
	assert_true(sd > 0, "a 10-kept King tops the why")
	var r := _fight(s, "thornvale", sd, "beasts")
	var clause: String = r.report.factors[0].text
	assert_true(clause.begins_with("King Corvane I fought in the front rank and dealt about "), clause)
	var crown := _side(r.report, "kingdom")
	assert_eq(clause, "King Corvane I fought in the front rank and dealt about %d damage%s" % [roundi(crown.ruler.damage_expected),
		" before falling" if crown.ruler.fell else ""], "the clause is the ruler's own expected damage")
	# The Ever-Regent fights from the second rank, and the clause says so.
	var reg := _game({"kingdom": {"ruler": "ever_regent", "mandates": []}})
	_army(reg, "kingdom-1", "kingdom", "rivermarch", ["spearmen", "spearmen", "spearmen", "knight_captain"])
	_ruler(reg, "kingdom", "rivermarch", 10)
	_army(reg, "beasts-2", "beasts", "rivermarch", ["tuskers", "tuskers", "tuskers", "warchief"])
	var rr := _fight(reg, "rivermarch", maxi(1, _seed_with_top(reg, "rivermarch", "ruler", 20)))
	assert_true(String(rr.report.factors[0].text).begins_with("the Ever-Regent fought from the second rank and dealt about "), rr.report.why)
	assert_true(rr.report.lines.has("Why: %s." % ("T" + String(rr.report.why).substr(1))), "capitalised at the start of the line")
	# A 0-kept King who falls: "before falling", and the odds name him.
	_assert_no_raw_ids(_all_text(r.report) + _all_text(rr.report), "ruler reports")
	var odds := AutoBattleResolver.estimate(_sides_at(s, "thornvale"), _ctx(s, "thornvale", "beasts"), "kingdom")
	assert_true(odds.text.contains("King Corvane I (fights in the front rank, +2 morale while it stands)"), odds.text)


func test_report_carries_the_ruler_and_the_mandates() -> void:
	var s := _game({"kingdom": {"ruler": "aurel_king", "mandates": ["royal_armories", "drilled_ranks", "heavy_tithes"]}})
	_army(s, "kingdom-1", "kingdom", "rivermarch", ["spearmen", "spearmen", "knight_captain"])
	_ruler(s, "kingdom", "rivermarch", 4)
	_army(s, "beasts-2", "beasts", "rivermarch", ["tuskers", "tuskers"])
	var r := _fight(s, "rivermarch", 6)
	var crown := _side(r.report, "kingdom")
	var ruler: Dictionary = crown.ruler
	var stats := RulerRules.ruler_stats("aurel_king", 4)
	assert_eq([ruler.id, ruler.name, ruler.rank, ruler.kept_power, ruler.max_hp, ruler.attack, ruler.defense, ruler.hp_start],
		["aurel_king", "King Corvane I", "front", 4, stats.hp, stats.attack, stats.defense, stats.hp])
	assert_eq(ruler.fell, ruler.hp_end == 0)
	assert_true(ruler.has("damage_dealt") and ruler.has("damage_expected") and ruler.has("fell_round"))
	assert_eq(crown.mandates.map(func(m): return m.id), ["royal_armories", "drilled_ranks"], "battle mandates only, in the order taken")
	assert_eq(crown.mandates[0].codex, "mandate_royal_armories")
	assert_eq(crown.roster.text, "Spearmen (2), led by Knight Captain, with King Corvane I")
	assert_eq(crown.roster.ruler, {"id": "aurel_king", "name": "King Corvane I"})
	assert_false(_side(r.report, "beasts").has("ruler"), "the Clans fielded no ruler")
	assert_false(_side(r.report, "beasts").has("mandates"), "and have no battle mandates")
	assert_eq(crown.fighters_start, 4, "two Spearmen, the Knight Captain and the King")
	assert_eq(RulerRules.mandate_battle_text("royal_armories"), "+1 attack for every regular unit")
	assert_eq(RulerRules.mandate_battle_text("drilled_ranks"), "base hit chance 70% instead of 60%")


func test_same_seed_same_report() -> void:
	var make := func() -> GameState:
		var s := _game({"kingdom": {"ruler": "ever_regent", "mandates": ["royal_armories", "veteran_levies"]},
			"beasts": {"ruler": "thornmane_avatar", "mandates": ["iron_discipline", "blood_frenzy", "feast_of_victory"]}})
		_army(s, "kingdom-1", "kingdom", "highcrag", ["spearmen", "spearmen", "crossbowmen", "knights", "knight_captain"])
		_ruler(s, "kingdom", "highcrag", 4)
		_army(s, "beasts-2", "beasts", "highcrag", ["tuskers", "tuskers", "fangthrowers", "war_bear", "warchief"])
		_ruler(s, "beasts", "highcrag", 1)
		return s
	for sd in [1, 7, 19]:
		var a: Dictionary = _resolve_battle(make.call(), "highcrag", sd, "kingdom")
		var b: Dictionary = _resolve_battle(make.call(), "highcrag", sd, "kingdom")
		assert_eq(var_to_str(a.report), var_to_str(b.report), "seed %d: same report" % sd)
		assert_eq(a.winner, b.winner)
	var s: GameState = make.call()
	var before := var_to_str(s.to_dict())
	_fight(s, "highcrag", 3, "kingdom")
	assert_eq(var_to_str(s.to_dict()), before, "fight() changes no army")


# --- odds and the sacrifice preview -------------------------------------------------------------------

func test_battle_odds_change_when_a_mandate_is_added() -> void:
	var rates := {}
	for mids in [[], ["royal_armories"], ["drilled_ranks"]]:
		var s := _game({"kingdom": {"ruler": "aurel_king", "mandates": mids}})
		_army(s, "kingdom-1", "kingdom", "highcrag", ["spearmen", "spearmen", "spearmen", "crossbowmen", "knights"])
		_army(s, "beasts-2", "beasts", "thornvale", ["tuskers", "tuskers", "fangthrowers", "war_bear"])
		var odds := Forecast.battle_odds(s, "kingdom", ["kingdom-1"], "thornvale")
		assert_true(odds.ok, odds.text)
		rates[str(mids)] = odds.win_rate
	assert_true(rates[str(["royal_armories"])] > rates[str([])], "Royal Armories raises the odds: %s" % rates)
	assert_true(rates[str(["drilled_ranks"])] > rates[str([])], "Drilled Ranks raises the odds: %s" % rates)
	# The ruler joining the attack moves them too.
	var s2 := _game()
	_army(s2, "kingdom-1", "kingdom", "highcrag", ["spearmen", "spearmen", "spearmen", "crossbowmen", "knights"])
	var king := _ruler(s2, "kingdom", "highcrag", 10)
	_army(s2, "beasts-2", "beasts", "thornvale", ["tuskers", "tuskers", "fangthrowers", "war_bear"])
	var with_king := Forecast.battle_odds(s2, "kingdom", ["kingdom-1", king.id], "thornvale")
	assert_true(with_king.win_rate > rates[str([])], "the King's sword counts in the odds")
	_assert_no_raw_ids(with_king.text, "odds text")


func test_the_sacrifice_preview_odds_rows_move_with_the_mandate() -> void:
	var s := GameState.with_rulers(7, {"kingdom": "warrior_king"}, [])
	var enemy := _army(s, s.new_army_id("beasts"), "beasts", "westwatch", ["tuskers", "tuskers", "fangthrowers", "war_bear"])
	var preview := Forecast.sacrifice(s, "kingdom", "royal_armories", [MoveOrder.new("kingdom-1", "westwatch")])
	assert_true(preview.ok, preview.text)
	assert_eq(preview.odds.size(), 1)
	assert_true(preview.odds[0].after_rate > preview.odds[0].before_rate,
		"Royal Armories improves the queued attack: %s -> %s" % [preview.odds[0].before, preview.odds[0].after])
	assert_true(enemy != null)


# --- the battle report viewer -------------------------------------------------------------------------

func _viewer() -> BattleReportViewer:
	return load(SCENE).instantiate() as BattleReportViewer


func _labels(node: Node, out: Array = []) -> Array:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return out
	if node is Label:
		out.append(node)
	for c in node.get_children():
		_labels(c, out)
	return out


func test_the_viewer_shows_the_ruler_and_the_mandates_in_who_fought() -> void:
	var s := _game({"kingdom": {"ruler": "aurel_king", "mandates": ["royal_armories", "drilled_ranks"]},
		"beasts": {"ruler": "thornmane_avatar", "mandates": ["iron_discipline"]}})
	_army(s, "kingdom-1", "kingdom", "rivermarch", ["spearmen", "spearmen", "crossbowmen", "knight_captain"])
	_ruler(s, "kingdom", "rivermarch", 2)
	_army(s, "beasts-2", "beasts", "rivermarch", ["tuskers", "fangthrowers", "fangthrowers", "warchief"])
	_ruler(s, "beasts", "rivermarch", 6)
	var r := _resolve_battle(s, "rivermarch", 5)
	var v := _viewer()
	assert_true(v.show_report(r.report, s))
	var sides := v.section("sides")
	var texts: Array = _labels(sides).map(func(l): return l.text)
	var joined := "\n".join(texts)
	assert_true(joined.contains("Ruler: King Corvane I, in the front rank: 22 hit points, attack 10, defense 9 (2 kept power), +2 morale to its side while it stands"), joined)
	assert_true(joined.contains("Ruler: The Great Thornmane, in the front rank:"), joined)
	assert_true(joined.contains("Mandates in play: Royal Armories, Drilled Ranks"), joined)
	assert_true(joined.contains("  Royal Armories: +1 attack for every regular unit"), joined)
	assert_true(joined.contains("Mandates in play: Iron Discipline"), joined)
	assert_true(joined.contains("Dread: every enemy side had 1 less morale while the Great Thornmane stood."), joined)
	assert_true(joined.contains("Roster: Spearmen (2), Crossbowmen, led by Knight Captain, with King Corvane I"), joined)
	for l in _labels(sides):
		if String(l.name) in ["RulerLine", "MandatesLine", "DreadLine", "RulerEnding"]:
			assert_true(CodexLink.key_at(l) != "" and RulesCodex.ENTRIES.has(CodexLink.key_at(l)), "%s links its codex entry" % l.name)
	# Every number explains itself, nothing shows a raw id, and the factors have codex entries.
	var all_text := PackedStringArray()
	for l in _labels(v):
		all_text.append(l.text)
		all_text.append(l.tooltip_text)
		var has_digit := false
		for ch in String(l.text):
			if ch >= "0" and ch <= "9":
				has_digit = true
		if has_digit:
			assert_false(l.tooltip_text.strip_edges().is_empty(), "'%s' has a tooltip" % l.text)
	_assert_no_raw_ids("\n".join(all_text), "viewer")
	for f in r.report.all_factors:
		assert_ne(BattleReportViewer._factor_entry(f.id), "", "factor %s is explained" % f.id)
	v.free()


func test_skirmish_moved_from_terrain_to_its_side() -> void:
	var found := false
	for sd in range(1, 30):
		var s := GameState.new(99)
		s.armies.clear()
		var crown := _army(s, "kingdom-1", "kingdom", "rivermarch", ["spearmen", "spearmen", "spearmen", "crossbowmen"])
		var clans := _army(s, "beasts-2", "beasts", "rivermarch", ["fangthrowers", "fangthrowers", "fangthrowers"])
		var r: Dictionary = AutoBattleResolver.fight([{"faction": "beasts", "armies": [clans]}, {"faction": "kingdom", "armies": [crown]}],
			_ctx(s, "rivermarch", "kingdom"), SeededRNG.new(sd)).result
		if not r.report.all_factors.any(func(f): return f.id == "Skirmish"):
			continue
		found = true
		var v := _viewer()
		v.show_report(r.report, s)
		var terrain := "\n".join(_labels(v.section("terrain")).map(func(l): return l.text))
		assert_false(terrain.contains("Skirmish"), "no Skirmish under terrain: %s" % terrain)
		var sides := "\n".join(_labels(v.section("sides")).map(func(l): return l.text))
		assert_true(sides.contains("Skirmish: Thornmane Clans' Fangthrowers (reaches the second rank)."), sides)
		v.free()
		break
	assert_true(found, "a battle where Skirmish counts")


func test_the_viewer_shows_feast_iron_discipline_and_a_lost_ruler() -> void:
	var iron := _game({"beasts": {"ruler": "fang_chieftain", "mandates": ["iron_discipline", "feast_of_victory"]}})
	_army(iron, "kingdom-1", "kingdom", "rivermarch", ["knights", "knights", "knights", "knights", "knights"])
	_army(iron, "beasts-2", "beasts", "rivermarch", ["tuskers", "tuskers", "tuskers", "tuskers", "tuskers", "tuskers", "warchief"])
	_ruler(iron, "kingdom", "rivermarch", 0)
	var shown := {"iron": false, "feast": false, "lost": false}
	for sd in range(1, 60):
		var s := iron.deep_copy([])
		if s == null:
			s = iron
		var r := _resolve_battle(s, "rivermarch", sd)
		var v := _viewer()
		v.show_report(r.report, s)
		var routs := "\n".join(_labels(v.section("routs")).map(func(l): return l.text))
		var casualties := "\n".join(_labels(v.section("casualties")).map(func(l): return l.text))
		if routs.contains("Iron Discipline held Thornmane Clans in round"):
			shown.iron = true
		if casualties.contains("It won, and Feast of Victory healed its"):
			shown.feast = true
		if casualties.contains("Its ruler, King Corvane I, was lost with it.") or casualties.contains("King Corvane I fell, though its side won"):
			shown.lost = true
		v.free()
		if shown.iron and shown.feast and shown.lost:
			break
	assert_eq(shown, {"iron": true, "feast": true, "lost": true}, "the viewer explains each")


# --- codex --------------------------------------------------------------------------------------------

func test_the_codex_states_the_battle_rules_with_rulers() -> void:
	var rounds := RulesCodex.text("battle_rounds")
	assert_true(rounds.contains("every unit, commander and ruler attacks"), rounds)
	assert_true(rounds.contains("the Ever-Regent in the second rank"), rounds)
	assert_true(RulesCodex.text("battle_hit_chance").contains("%d%% for a side with the Drilled Ranks mandate" % RulerRules.mandate_data("drilled_ranks").base_hit))
	var morale := RulesCodex.text("battle_morale")
	assert_true(morale.contains("ruler adds +%d" % RulerData.RULER_MORALE), morale)
	assert_true(morale.contains("Dread") and morale.contains("Iron Discipline"), morale)
	assert_true(RulesCodex.text("battle_commanders").contains("A ruler is not a commander"))
	var rank := RulesCodex.text("ruler_rank")
	assert_true(rank.contains("at least as many front-rank fighters stand as second-rank ones") and rank.contains("Skirmish"), rank)
	assert_false(rank.contains("only once every front-rank fighter on his side has fallen"), "the old rule is gone")
	assert_true(RulesCodex.text("ability_dread").contains("while the avatar stands"))
	assert_true(RulesCodex.text("mandate_blood_frenzy").contains("+%d attack" % RulerRules.mandate_data("blood_frenzy").wounded_attack))
	assert_true(RulesCodex.text("mandate_drilled_ranks").contains("%d%%" % RulerRules.mandate_data("drilled_ranks").base_hit))
	assert_true(String(RulerRules.mandate_data("drilled_ranks").effect).contains("%d%%" % RulerRules.mandate_data("drilled_ranks").base_hit))
	for id in ["battle_rounds", "battle_morale", "battle_commanders", "battle_hit_chance", "ruler_rank", "ruler_in_battle", "ability_dread"]:
		_assert_no_raw_ids(RulesCodex.text(id), id)
