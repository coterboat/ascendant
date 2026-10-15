extends "res://tests/test_case.gd"
## M5-1 (#112) acceptance, the turn report per viewer (design/M5_MAGIC_FOG.md §2.8, §14, §18):
## - every event type follows the audience table (FogData.AUDIENCE): who sees it whole, who sees a rebuilt version,
##   who sees nothing;
## - a rebuilt event holds only FogData.SAFE_NUMBERS, and its text comes from FogData.TEXT;
## - for each viewer, apply_view_events(view_before, filtered events) equals view_after;
## - participants see their battles whole, with view ids for the armies they didn't own.

const Kit := preload("res://tests/fog_test_kit.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
## Numbers a rebuilt event must never carry (§14).
const NEVER := ["units_changed", "hp_total", "own_text", "gold", "gold_before", "gold_after", "cost", "eta", "army", "armies"]


## Every event type the resolver has, with a sample event for those the fog games may not reach: each sample names
## the Clans as its faction, so the Crown is the "other" viewer. Numbers include private ones the rebuilt events
## must drop.
func _samples(s: GameState) -> Array:
	var secret := {"gold": 12, "units_changed": 3, "hp_total": 40, "own_text": "a secret", "cost": 20}
	var out := []
	var with := func(t: String, provinces: Array, factions: Array, armies: Array, numbers: Dictionary, codex: String = "orders"):
		var n := secret.duplicate()
		n.merge(numbers, true)
		out.append({"type": t, "phase": "x", "provinces": provinces, "factions": factions, "armies": armies, "cause": "test",
			"numbers": n, "text": "The resolver's own words: a secret.", "codex": codex})
	with.call("captured", ["blackwood"], [CLANS, CROWN], ["beasts-1"], {"income": 8, "is_capital": false, "fort_level": 2, "walls": 4, "recruit_from": 5})
	with.call("captured", ["crownkeep"], [CLANS, CROWN], ["beasts-1"], {"income": 12, "is_capital": true})
	with.call("vassal_joined", ["ebonpeak"], [CLANS], [], {"income": 6})
	with.call("vassal_contested", ["thornvale"], [CLANS, CROWN], [], {"income": 6})
	with.call("ruler_died", ["thornvale"], [CLANS], ["beasts-2"], {"ruler": "thornmane_avatar", "kind": "god", "name": "the Great Thornmane",
		"generation": 1, "kept_power": 7, "successor_turn": 9, "successor_power": 5, "won": true})
	with.call("ruler_arrived", ["fangridge"], [CLANS], ["beasts-9"], {"ruler": "thornmane_avatar", "kind": "god", "name": "the Great Thornmane",
		"generation": 2, "kept_power": 5, "max_hp": 50, "attack": 15, "defense": 13, "ability_rank": 2, "hp": 50, "kept_power_before": 7})
	with.call("succession_waiting", ["fangridge"], [CLANS], [], {"successor_turn": 9, "successor_power": 5, "successor_generation": 2})
	with.call("oath_sworn", [], [CLANS], [], {"node": "beasts_oath_grove", "branch": "thorn_wild", "closed": "blood_pact", "turn": 7})
	with.call("transformed", [], [CLANS], [], {"node": "beasts_thorn_wild", "branch": "thorn_wild",
		"renamed": {"fangthrowers": {"from": "Fangthrowers", "to": "Thornthrowers"}}, "new_unit": "briarwardens",
		"province_rule": "wild_spreads", "opens_mandate": "deep_roots", "forswears": "", "turn": 9})
	with.call("wild_spread", ["deepwood"], [CLANS], [], {"province": "deepwood", "from_terrain": "plains", "terrain": "forest", "grown_from": ["wildmoor"]})
	with.call("fort_built", ["ebonpeak"], [CLANS], [], {"level": 1, "walls": 3, "recruits": 2, "recruit_from": 6, "province": "ebonpeak"})
	for t in ["order_rejected", "sacrificed", "recruited", "income", "research_gained", "research_done", "mending", "ruler_healed",
			"path_healed", "raided", "walls_repaired", "construction_started", "construction_halted", "storm_called_off",
			"sally_called_off", "sally_found_nothing", "a_future_event",
			"army_split", "units_transferred", "armies_merged", "commanders_swapped", "army_disbanded"]:  # ARM-1 musters: the owner's alone
		with.call(t, ["fangridge"], [CLANS], ["beasts-1"], {})
	for t in ["siege_started", "walls_damaged", "walls_breached", "siege_lifted", "siege_ended", "construction_razed"]:
		with.call(t, ["blackwood"], [CLANS], ["beasts-1"], {})  # the Crown is not in it here
	with.call("game_over", ["crownkeep"], [CLANS], [], {"winner": CLANS})
	# M5-6, the rituals: a Bastion fort is public; a global ritual is heralded, any other cast is the caster's; a curse's
	# bite goes whole to the faction bitten and rebuilt to the caster it names; the rest are their first faction's.
	with.call("fort_raised", ["ebonpeak"], [CLANS], [], {"province": "ebonpeak", "bastions": 1, "level": 1, "walls": 3})
	with.call("ritual_cast", ["fangridge"], [CLANS], ["beasts-1"], {"ritual": "blood_moon", "until_turn": 6, "global": true})
	with.call("ritual_cast", ["fangridge", "ironspike"], [CLANS], ["beasts-1"], {"ritual": "bloodrot", "until_turn": 6, "global": false})
	with.call("curse_bit", ["fangridge"], [CLANS, CROWN], ["beasts-1"], {"ritual": "bloodrot", "until_turn": 6, "budget": 12,
		"province": "fangridge", "taken": [{"army": "beasts-1", "from": 14, "to": 12}], "total": 2})
	with.call("curse_bit", ["bloodfen"], [CLANS], [], {"ritual": "bloodrot", "until_turn": 6, "budget": 12, "province": "bloodfen"})
	for t in ["ritual_turned_aside", "blood_paid", "enchantment_began", "summoned", "far_sight_reading", "ritual_fell",
			"blessing_healed", "enchantment_ended", "summon_faded"]:
		with.call(t, ["fangridge"], [CLANS, CROWN], ["beasts-1"], {"ritual": "bloodrot"})
	return out


func _expect(e: Dictionary, viewer: String, got: Array, before: GameState) -> void:
	var t := String(e.type)
	var row: Dictionary = FogData.AUDIENCE.get(t, {"whole": "actor", "others": "none"})
	var factions: Array = e.get("factions", [])
	var whole := String(row.whole) == "all" or (String(row.whole) == "factions" and factions.has(viewer)) \
		or (not factions.is_empty() and String(factions[0]) == viewer)
	var what := "%s for %s" % [t, viewer]
	if whole:
		assert_eq(got.size(), 1, "%s: seen whole" % what)
		if got.size() == 1:
			var a: Dictionary = got[0].duplicate(true)
			var b: Dictionary = e.duplicate(true)
			if FogRules.BATTLE_TYPES.has(t):
				for x in [a, b]:
					x.erase("armies")
					x.numbers.erase("destroyed")
			assert_eq(JSON.stringify(a), JSON.stringify(b), "%s: exactly as the resolver wrote it" % what)
		return
	match String(row.others):
		"rebuilt":
			assert_eq(got.size(), 1, "%s: rebuilt" % what)
			if got.size() == 1:
				assert_true(bool(got[0].get("rebuilt", false)) and got[0].type == t, "%s: a rebuilt event" % what)
		"move":
			var seen := String(FogRules.sight(before, viewer).get(String(e.provinces[0]), "veiled")) != "veiled"
			assert_eq(got.size(), 1 if seen else 0, "%s: a move %s" % [what, "seen leaving" if seen else "out of sight"])
		"rebuilt_if_global":  # M5-6: a global ritual is heralded to everyone
			var heralded := bool(e.get("numbers", {}).get("global", false))
			assert_eq(got.size(), 1 if heralded else 0, "%s: %s" % [what, "heralded" if heralded else "nothing"])
			if heralded and got.size() == 1:
				assert_true(bool(got[0].get("rebuilt", false)), "%s: a rebuilt event" % what)
		"rebuilt_named":  # M5-6: rebuilt only for the factions the event names
			var named := factions.has(viewer)
			assert_eq(got.size(), 1 if named else 0, "%s: %s" % [what, "rebuilt" if named else "nothing"])
			if named and got.size() == 1:
				assert_true(bool(got[0].get("rebuilt", false)), "%s: a rebuilt event" % what)
		_:
			assert_eq(got, [], "%s: nothing" % what)


func test_every_event_type_follows_the_audience_table() -> void:
	var types := {}
	for g in Kit.games():
		for t in g.turns:
			for e in t.events:
				for v in Kit.SEATS:
					_expect(e, v, FogRules.filter_events([e], v, t.before, t.after), t.before)
				types[String(e.type)] = true
	var s := GameState.with_sieges(8, {}, {"paths": true})
	s.setup_fog([])
	for e in _samples(s):
		for v in Kit.SEATS:
			_expect(e, v, FogRules.filter_events([e], v, s, s), s)
		types[String(e.type)] = true
	var border := _border_battle_turn()
	for e in border.events:
		for v in Kit.SEATS:
			_expect(e, v, FogRules.filter_events([e], v, border.before, border.after), border.before)
		types[String(e.type)] = true
	for t in FogData.AUDIENCE:
		assert_true(types.has(t), "event type %s was checked" % t)
	for t in ["army_moved", "battle", "captured", "recruited", "income"]:
		assert_true(types.has(t), "the fog games reached %s" % t)


## A real border battle, resolved in a game with fog: two armies swap across the Thornvale-Wildmoor border. The fog
## games need not reach one (since #131 the computer fights none in them), and its numbers are a real battle's.
func _border_battle_turn() -> Dictionary:
	var s := GameState.new(8)
	s.setup_fog([])
	s.armies.clear()
	for spec in [["kingdom-1", CROWN, "thornvale", "spearmen"], ["beasts-1", CLANS, "wildmoor", "war_bear"]]:
		var a := Army.new()
		a.id = spec[0]
		a.owner = spec[1]
		a.location = spec[2]
		a.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction(a.owner), spec[3]), a.owner))
		s.armies.append(a)
	s.find_province("thornvale").owner = CROWN
	s.find_province("wildmoor").owner = CLANS
	var r := TurnResolver.resolve(s, {CROWN: [MoveOrder.new("kingdom-1", "wildmoor")], CLANS: [MoveOrder.new("beasts-1", "thornvale")]},
		1, AutoBattleResolver.new())
	assert_eq(r.events.filter(func(e): return e.type == "border_battle").size(), 1, "the swap fights on the border")
	return {"before": s, "after": r.new_state, "events": r.events}


func test_rebuilt_events_hold_only_safe_numbers_and_template_text() -> void:
	var checked := 0
	var cases := []
	for g in Kit.games():
		for t in g.turns:
			for v in Kit.SEATS:
				cases.append([t.report[v], t.before, t.after, v])
	var s := GameState.with_sieges(8, {}, {"paths": true})
	s.setup_fog([])
	var samples := _samples(s)
	cases.append([FogRules.filter_events(samples, CROWN, s, s), s, s, CROWN])
	for c in cases:
		var report: Array = c[0]
		var before: GameState = c[1]
		var after: GameState = c[2]
		var viewer: String = c[3]
		for e in report:
			if not bool(e.get("rebuilt", false)):
				continue
			checked += 1
			var key := FogRules.safe_key(e)
			for n in e.numbers:
				assert_true(FogData.SAFE_NUMBERS[key].has(n), "%s carries only safe numbers, not %s" % [e.type, n])
				assert_false(NEVER.has(n), "%s never carries %s" % [e.type, n])
			for aid in e.armies:
				assert_true(FogRules.is_view_id(String(aid)), "%s names armies by view ids only" % e.type)
			if String(e.type) == "army_moved":
				var away := String(FogRules.sight(after, viewer).get(String(e.numbers.to), "veiled")) == "veiled"
				var template := String(FogData.TEXT.move_away if away else FogData.TEXT.move)
				assert_eq(e.text, template.format(FogRules._move_params(e.numbers, before)), "a move's text comes from FogData.TEXT")
				assert_eq([e.view_from, e.view_to], [e.numbers.from, e.numbers.to], "a rebuilt move carries view_from and view_to")
				assert_eq(e.numbers.total.keys(), ["shown", "low", "high", "text"], "its total is a round count")
			else:
				assert_eq(e.text, FogRules.text_for(String(e.type), e.numbers, e.provinces, e.factions, after),
					"%s: its text comes from FogData.TEXT" % e.type)
			assert_false(String(e.text).contains("{") or String(e.text).contains("secret"), "%s: a finished template, nothing private: %s" % [e.type, e.text])
	assert_true(checked > 50, "rebuilt events were checked (%d)" % checked)


func test_view_before_folded_with_the_report_is_view_after() -> void:
	var folds := 0
	var moved_only := 0
	for g in Kit.games():
		for t in g.turns:
			for v in Kit.SEATS:
				var report: Array = t.report[v]
				var model := FogRules.view_model(t.view_before[v])
				var folded := FogRules.apply_view_events(model, report)
				assert_eq(var_to_str(folded), var_to_str(FogRules.view_model(t.view_after[v])),
					"%s turn %d, %s: playback = state, per viewer" % [g.name, t.turn, v])
				folds += 1
				# The synthetic events come last, and cover only what is left over: an own army that only moved
				# is folded by its move, never redescribed.
				var first_synthetic := -1
				for i in report.size():
					if bool(report[i].get("synthetic", false)):
						if first_synthetic < 0:
							first_synthetic = i
						assert_true(FogData.SYNTHETIC_TYPES.has(String(report[i].type)) and report[i].phase == "view")
					else:
						assert_eq(first_synthetic, -1, "real events come before the synthetic ones")
				for e in report:
					if String(e.type) == "army_moved" and not bool(e.get("rebuilt", false)) and e.factions[0] == v:
						var id := String(e.armies[0])
						var redone := report.filter(func(x): return bool(x.get("synthetic", false)) and x.armies[0] == id)
						var before_counts = model.get(id, {}).get("counts")
						var after_counts = FogRules.view_model(t.view_after[v]).get(id, {}).get("counts")
						if var_to_str(before_counts) == var_to_str(after_counts):
							assert_eq(redone, [], "%s: an own move is folded, not redescribed" % id)
							moved_only += 1
	assert_true(folds >= 20 * 2 * 5, "folds checked (%d)" % folds)
	assert_true(moved_only > 0, "own moves were folded by their events (%d)" % moved_only)


func test_participants_see_battles_whole_with_view_ids() -> void:
	var battles := 0
	for g in Kit.games():
		for t in g.turns:
			for v in Kit.SEATS:
				var before_ids := {}
				for a in t.view_before[v].armies:
					before_ids[a.id] = true
				for e in t.report[v]:
					if not FogRules.BATTLE_TYPES.has(String(e.type)):
						continue
					battles += 1
					assert_true(e.factions.has(v), "only a participant sees a battle")
					for aid in e.armies:
						assert_true(before_ids.has(String(aid)), "%s: battle armies are ids of the view before the turn (%s)" % [g.name, aid])
						if not FogRules.is_view_id(String(aid)):
							assert_eq(t.before.find_army(String(aid)).owner, v, "a true id is the viewer's own army")
					for aid in e.numbers.destroyed:
						assert_true(e.armies.has(aid), "destroyed armies are among the battle's armies")
					assert_true(e.numbers.has("log") and e.numbers.has("report"), "the whole battle: report and log")
	assert_true(battles > 10, "battles were checked (%d)" % battles)


func test_the_observer_gets_the_truth() -> void:
	var g: Dictionary = Kit.games()[1]
	var t: Dictionary = g.turns[g.turns.size() - 1]
	assert_eq(JSON.stringify(FogRules.report_for(t.events, FogRules.OBSERVER, t.before, t.after)), JSON.stringify(t.events))
	assert_eq(Kit.to_json(FogRules.view_state(t.after, FogRules.OBSERVER)), Kit.to_json(t.after))
	var session: GameSession = g.session
	assert_eq(JSON.stringify(session.turn_report_for(FogRules.OBSERVER)), JSON.stringify(session.turn_report()))
	assert_eq(Kit.to_json(session.state_for(FogRules.OBSERVER)), Kit.to_json(session.state()))


## TEXT-1 (#240): a seen move counts every fighter it names, its commanders and its ruler too (as a battle's "fighters" are), and its words
## agree with the count. A ruler marching alone read "(none fighters: the Ninth Fang)", and a War Bear with its Warchief and its ruler
## "(1-2 fighters: War Bear, Warchief and the Ninth Fang)". Real moves of the Clans' ruler, alone and with an army and its commander,
## out of a province the Crown sees, at each sight level the map gives: the count's range holds the number of names, and never says none.
func test_a_seen_move_counts_every_fighter_it_names() -> void:
	var checked := 0
	for level in [FogRules.CLEAR, FogRules.GLIMPSE]:
		for with_army in [false, true]:
			var s := GameState.with_rulers(95)
			s.setup_fog([])
			var spot := _seen_spot(s, level)
			if spot.is_empty():
				continue
			var ruler := RulerRules.ruler_army(s, CLANS)
			var moving: Array = [ruler]
			if with_army:
				for a in s.armies:
					if a.owner == CLANS and a.ruler == null and a.commander != null and not a.units.is_empty():
						moving.append(a)
						break
				assert_eq(moving.size(), 2, "the Clans have an army with a commander")
			var orders := []
			for a in moving:
				(a as Army).location = spot.from
				orders.append(MoveOrder.new((a as Army).id, spot.to))
			var r := TurnResolver.resolve(s, {CROWN: [], CLANS: orders}, 1, AutoBattleResolver.new())
			var seen := FogRules.filter_events(r.events, CROWN, s, r.new_state).filter(func(e): return String(e.type) == "army_moved")
			var what := "%s, %s" % [level, "the ruler with an army" if with_army else "the ruler alone"]
			assert_eq(seen.size(), 1, "%s: the Crown sees one move" % what)
			if seen.is_empty():
				continue
			var e: Dictionary = seen[0]
			var named: int = (e.numbers.types as Array).size()
			var fighters := 0
			for a in moving:
				fighters += (a as Army).units.size() + (1 if (a as Army).commander != null else 0) + (1 if (a as Army).ruler != null else 0)
			assert_true(int(e.numbers.total.low) <= fighters and fighters <= int(e.numbers.total.high), "%s: the count holds its %d fighters: %s" % [what, fighters, e.text])
			assert_true(int(e.numbers.total.high) >= named, "%s: and every one of the %d kinds it names: %s" % [what, named, e.text])
			assert_false(String(e.text).contains("none") or String(e.text).contains("1 fighters"), "%s: the words agree with the count: %s" % [what, e.text])
			checked += 1
	assert_true(checked >= 2, "moves were checked (%d)" % checked)


## A province the Crown sees at `level` with a neighbour the Clans can march into without a fight: {"from", "to"}, or {} when none.
func _seen_spot(s: GameState, level: String) -> Dictionary:
	var sight := FogRules.sight(s, CROWN)
	for p in s.provinces:
		if String(sight.get(p.id, "")) != level or p.owner == CROWN:
			continue
		for n in p.neighbors:
			var q := s.find_province(n)
			if q.owner == CROWN or s.armies.any(func(a): return a.location == n):
				continue
			return {"from": p.id, "to": n}
	return {}
