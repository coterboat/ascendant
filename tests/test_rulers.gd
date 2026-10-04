extends "res://tests/test_case.gd"
## M2-1 (#29): the ruler model. The §1.3 table for every ruler at kept power 0-10, names and succession
## numbers, the opt-in setup (rulers off by default, army 1 plus the ruler's army at each capital when
## on), round trips, replay with builds, ruler armies in the resolver, labels without raw ids, the
## breakdowns behind every ruler number, the map's ruler lines, and the §7.2 codex entries.

## design/M2_RULER.md §1.3, "Full table (builders test against this)": [hp, attack, defense] rows.
const SPEC_TABLE := {
	"aurel_king": [
		[18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38],
		[9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14],
		[8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13],
	],
	"ever_regent": [
		[14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24],
		[8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18],
		[6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11],
	],
	"thornmane_avatar": [
		[24, 27, 30, 33, 36, 39, 42, 45, 48, 51, 54],
		[8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18],
		[7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12],
	],
	"fang_chieftain": [
		[20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40],
		[9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19],
		[7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12],
	],
}
const SPEC_ABILITY_RANK := [1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4]
## §1.2: faction, kind, battle rank, morale when alone, ability. §1.4: ability values at rank 1-4.
const SPEC_RULERS := {
	"aurel_king": ["kingdom", "mortal", "front", 10, "royal_court", [2, 3, 4, 5]],
	"ever_regent": ["kingdom", "undying", "second", 10, "mending_light", [3, 6, 9, 12]],
	"thornmane_avatar": ["beasts", "god", "front", 14, "dread", [1, 1, 1, 1]],
	"fang_chieftain": ["beasts", "mortal", "front", 12, "warband_muster", [1, 2, 3, 4]],
}
## Every new term in design/M2_RULER.md §7.2.
const M2_CODEX_KEYS := ["ruler", "ruler_power", "kept_power", "ability_rank", "ruler_rank", "ruler_in_battle",
	"ruler_healing", "ruler_army", "ruler_death", "succession", "succession_mortal", "succession_undying",
	"succession_god", "mandates", "sacrifice", "build", "build_presets", "ai_seat", "ruler_aurel_king",
	"ruler_ever_regent", "ruler_thornmane_avatar", "ruler_fang_chieftain", "ability_royal_court",
	"ability_mending_light", "ability_dread", "ability_warband_muster", "mandate_iron_discipline",
	"mandate_drilled_ranks", "mandate_veteran_levies", "mandate_heavy_tithes", "mandate_muster_grounds",
	"mandate_sworn_vassals", "mandate_royal_armories", "mandate_kings_roads", "mandate_blood_frenzy",
	"mandate_feast_of_victory", "road_move", "field_recruit"]
## The M1 save format, which a game without rulers must keep exactly.
const M1_STATE_KEYS := ["armies", "current_turn", "factions", "next_army_id", "provinces", "rng", "seed_value"]
const M1_FACTION_KEYS := ["capital", "commander_type", "gold", "id", "name", "unit_types"]
const M1_ARMY_KEYS := ["commander", "id", "location", "owner", "units"]
const M1_UNIT_TYPE_KEYS := ["attack", "cost", "defense", "hp", "id", "is_commander", "morale", "name", "trait", "trait_description"]
const M1_RECORD_KEYS := ["game_seed", "history", "players", "start_state"]
## Ids that must never reach player-facing text (case-sensitive: display names are capitalised).
const RAW_IDS := ["kingdom", "beasts", "crownkeep", "fangridge", "westwatch", "highcrag", "ebonpeak", "ironspike",
	"aurel_king", "ever_regent", "thornmane_avatar", "fang_chieftain", "royal_armories", "kings_roads",
	"iron_discipline", "drilled_ranks", "regents_court", "blood_of_the_fang", "royal_court", "mending_light",
	"warband_muster", "-1", "-2", "-3", "-4", "-5", "_"]
const STATS := ["hp", "attack", "defense"]


# --- fixtures -------------------------------------------------------------------------------------

func _with_rulers(seed_value: int = 7, builds: Dictionary = {}) -> GameState:
	var errors := []
	var s := GameState.with_rulers(seed_value, builds, errors)
	assert_eq(errors, [], "the rulers set up")
	assert_true(s != null, "a state with rulers")
	return s


func _armies_at(s: GameState, owner: String, location: String) -> Array:
	var out := []
	for a in s.armies:
		if a.owner == owner and a.location == location:
			out.append(a)
	out.sort_custom(func(a, b): return a.id.naturalnocasecmp_to(b.id) < 0)
	return out


func _assert_no_raw_ids(text: String, what: String) -> void:
	assert_false(text.strip_edges().is_empty(), "%s has text" % what)
	for id in RAW_IDS:
		assert_false(text.contains(id), "%s shows no raw id '%s': %s" % [what, id, text])


func _assert_breakdown(b: Dictionary, what: String) -> void:
	assert_eq(Breakdown.sum_of_lines(b), int(b.total), "%s: the lines sum to the total" % what)
	assert_true(RulesCodex.ENTRIES.has(String(b.get("codex", ""))), "%s names a codex entry (%s)" % [what, b.get("codex", "")])
	for text in [String(b.title), String(b.description), String(b.total_label)]:
		_assert_no_raw_ids(text, what)
	for l in b.lines:
		_assert_no_raw_ids(String(l.label), "%s line" % what)


# --- the numbers: §1.1-1.4 ------------------------------------------------------------------------

func test_every_ruler_at_every_kept_power_matches_the_spec_table() -> void:
	assert_eq(RulerData.RULERS.size(), 4, "four rulers")
	for rid in SPEC_TABLE:
		for k in 11:
			var expected := [SPEC_TABLE[rid][0][k], SPEC_TABLE[rid][1][k], SPEC_TABLE[rid][2][k]]
			var stats := RulerRules.ruler_stats(rid, k)
			var ut := RulerRules.make_unit_type(rid, k)
			for i in STATS.size():
				var stat: String = STATS[i]
				var what := "%s %s at %d kept" % [rid, stat, k]
				assert_eq(RulerRules.stat_value(rid, stat, k), expected[i], what)
				assert_eq(stats[stat], expected[i], what + " (ruler_stats)")
				assert_eq(ut.get(stat), expected[i], what + " (its UnitType)")
				var b := Breakdown.ruler_stat_at(rid, stat, k)
				assert_eq(int(b.total), expected[i], what + " (breakdown total)")
				_assert_breakdown(b, what)
			assert_eq(RulerRules.ability_rank(k), SPEC_ABILITY_RANK[k], "ability rank at %d kept" % k)
			assert_eq(stats.ability_rank, SPEC_ABILITY_RANK[k])
			var rank := Breakdown.ability_rank_at(rid, k)
			assert_eq(int(rank.total), SPEC_ABILITY_RANK[k], "%s ability rank breakdown at %d kept" % [rid, k])
			_assert_breakdown(rank, "%s ability rank at %d" % [rid, k])
			assert_true(ut.is_ruler and not ut.is_commander, "a ruler's type is a ruler")
			assert_eq(ut.cost, 0, "rulers are never recruited")
			assert_eq(ut.trait_id, "", "rulers have no trait")
			assert_eq(ut.id, rid)


func test_rulers_kinds_ranks_morale_and_abilities_match_the_spec() -> void:
	for rid in SPEC_RULERS:
		var spec: Array = SPEC_RULERS[rid]
		var r := RulerRules.ruler_data(rid)
		assert_eq(r.faction, spec[0], "%s faction" % rid)
		assert_eq(r.kind, spec[1], "%s kind" % rid)
		assert_eq(RulerRules.battle_rank(rid), spec[2], "%s battle rank" % rid)
		assert_eq(RulerRules.ruler_stats(rid, 5).morale, spec[3], "%s morale when alone" % rid)
		assert_eq(r.ability, spec[4], "%s ability" % rid)
		for rank in range(1, 5):
			assert_eq(RulerRules.ability_value(rid, rank), spec[5][rank - 1], "%s ability at rank %d" % [rid, rank])
		assert_eq(RulerRules.ruler_stats(rid, 0).morale_bonus, 2, "every ruler gives +2 morale while it stands")
		assert_true(RulesCodex.ENTRIES.has(String(RulerData.KINDS[r.kind].codex)), "%s's kind has a codex entry" % rid)
		_assert_no_raw_ids(RulerRules.ability_text(rid, 2), "%s ability text" % rid)
	assert_eq(RulerRules.rulers_for("kingdom"), ["aurel_king", "ever_regent"])
	assert_eq(RulerRules.rulers_for("beasts"), ["thornmane_avatar", "fang_chieftain"])
	assert_eq(RulerData.POWER_POOL, 10)
	assert_eq(RulerRules.ability_text("aurel_king", 2),
		"In the income phase, the province King Corvane I is in earns 3 more gold, if you own it.")


func test_ruler_names_and_heirs() -> void:
	assert_eq(RulerRules.ruler_name("aurel_king"), "King Corvane I")
	assert_eq(RulerRules.ruler_name("aurel_king", 2), "King Corvane II")
	assert_eq(RulerRules.ruler_name("aurel_king", 4), "King Corvane IV")
	assert_eq(RulerRules.ruler_name("aurel_king", 14), "King Corvane XIV")
	assert_eq(RulerRules.heir_name("aurel_king", 2), "Corvane II")
	assert_eq(RulerRules.ruler_name("fang_chieftain"), "the Ninth Fang")
	assert_eq(RulerRules.ruler_name("fang_chieftain", 2), "the Tenth Fang")
	assert_eq(RulerRules.ruler_name("fang_chieftain", 3), "the Eleventh Fang")
	assert_eq(RulerRules.ruler_name("fang_chieftain", 12), "the Twentieth Fang")
	assert_eq(RulerRules.ruler_name("fang_chieftain", 13), "the Twenty-first Fang")
	assert_eq(RulerRules.heir_name("fang_chieftain", 2), "the Tenth Fang")
	for g in [1, 2, 5]:
		assert_eq(RulerRules.ruler_name("ever_regent", g), "the Ever-Regent")
		assert_eq(RulerRules.ruler_name("thornmane_avatar", g), "the Great Thornmane")
	assert_eq(RulerRules.make_unit_type("aurel_king", 3, 2).name, "King Corvane II", "the UnitType carries the name")


func test_successors_follow_the_spec() -> void:
	# §5.2: "For a ruler that dies with 10 kept power: the heir has 5, the Regent has 10 again, and the
	# god has 7. With 4 kept: 2, 4 and 1."
	var cases := {"aurel_king": [2, 5, 2], "fang_chieftain": [2, 5, 2], "ever_regent": [4, 10, 4], "thornmane_avatar": [1, 7, 1]}
	for rid in cases:
		var at10 := RulerRules.successor_for(rid, 10, 1)
		var at4 := RulerRules.successor_for(rid, 4, 1)
		assert_eq(at10.delay, cases[rid][0], "%s delay" % rid)
		assert_eq(at10.kept_power, cases[rid][1], "%s successor at 10" % rid)
		assert_eq(at4.kept_power, cases[rid][2], "%s successor at 4" % rid)
		assert_eq(at10.generation, 2)
	assert_eq(RulerRules.successor_for("thornmane_avatar", 2).kept_power, 0, "never below 0")
	assert_eq(RulerRules.successor_for("aurel_king", 7).kept_power, 3, "half, rounded down")
	assert_eq(RulerRules.successor_for("aurel_king", 7).heir_name, "Corvane II")
	var text := RulerRules.succession_text("aurel_king", 4, 1, "Crownkeep")
	assert_true(text.contains("Corvane II is crowned at Crownkeep 2 turns later") and text.contains("now 4, so 2"), text)
	for rid in cases:
		_assert_no_raw_ids(RulerRules.succession_text(rid, 6, 1, "Crownkeep"), "%s succession text" % rid)


# --- setup: off by default, army 1 plus the ruler's army when on -----------------------------------

func test_default_setup_is_the_m1_setup() -> void:
	var s := GameState.new(7)
	assert_false(RulerRules.has_rulers(s), "no rulers unless asked for")
	assert_eq(s.armies.size(), 2, "one starting army per faction, as in M1")
	assert_eq(s.next_army_id, 3)
	for f in s.factions:
		assert_false(f.has_ruler(), "%s has no ruler" % f.faction_name)
		assert_eq(f.mandates, [])
		assert_eq(f.ruler_unit_type, null)
		assert_eq(RulerRules.ruler_army(s, f.id), null)
		var here := _armies_at(s, f.id, f.capital)
		assert_eq(here.size(), 1, "%s capital holds army 1 only" % f.faction_name)
		assert_eq(here[0].units.size(), f.unit_types.size(), "one of each unit")
		assert_true(here[0].commander != null and here[0].ruler == null)
	assert_eq(s.find_army("kingdom-1").location, "crownkeep")
	assert_eq(s.find_army("beasts-2").location, "fangridge")
	# The save format is exactly M1's: no ruler key anywhere.
	var d := s.to_dict()
	var keys: Array = d.keys()
	keys.sort()
	assert_eq(keys, M1_STATE_KEYS)
	for fd in d.factions:
		var fk: Array = fd.keys()
		fk.sort()
		assert_eq(fk, M1_FACTION_KEYS, "faction keys")
		for ud in fd.unit_types + [fd.commander_type]:
			var uk: Array = ud.keys()
			uk.sort()
			assert_eq(uk, M1_UNIT_TYPE_KEYS, "unit type keys")
	for ad in d.armies:
		var ak: Array = ad.keys()
		ak.sort()
		assert_eq(ak, M1_ARMY_KEYS, "army keys")
	# The game screen's default start is the same M1 state, and so is a session's record.
	assert_eq(GameScreen.starting_state({"players": ["kingdom", "beasts"], "seed": 7}).to_dict(), d)
	var session := GameSession.new(s, ["kingdom", "beasts"], 7, StubBattleResolver.new())
	var rk: Array = session.record().keys()
	rk.sort()
	assert_eq(rk, M1_RECORD_KEYS, "an M1 record has no builds")
	assert_eq(session.builds(), {})
	# An M1 save (no ruler keys) loads as a game without rulers.
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_true(loaded != null)
	assert_false(RulerRules.has_rulers(loaded))
	assert_eq(loaded.to_dict(), d)


func test_each_capital_starts_with_army_1_and_the_ruler_army_when_rulers_are_on() -> void:
	var m1 := GameState.new(7)
	var s := _with_rulers(7)
	assert_true(RulerRules.has_rulers(s))
	assert_eq(s.armies.size(), 4, "army 1 and the ruler's army for each faction")
	var expected := {"kingdom": ["kingdom-1", "kingdom-3", "ever_regent", 5, ["royal_armories", "kings_roads"]],
		"beasts": ["beasts-2", "beasts-4", "fang_chieftain", 5, ["iron_discipline", "drilled_ranks"]]}
	for fid in expected:
		var f := s.find_faction(fid)
		var e: Array = expected[fid]
		var here := _armies_at(s, fid, f.capital)
		assert_eq(here.size(), 2, "%s capital holds two armies" % f.faction_name)
		assert_eq(here[0].id, e[0], "army 1 keeps its M1 id")
		assert_eq(here[0].to_dict(), m1.find_army(e[0]).to_dict(), "army 1 is the M1 starting army")
		assert_eq(here[1].id, e[1], "the ruler's army is army 2 at the capital")
		var ruler_army: Army = here[1]
		assert_true(ruler_army.ruler != null, "it holds the ruler")
		assert_true(ruler_army.units.is_empty() and ruler_army.commander == null, "and nothing else")
		assert_eq(RulerRules.ruler_army(s, fid), ruler_army)
		# No build given: the faction's balanced preset.
		assert_eq(f.ruler_type, e[2], "%s balanced preset ruler" % fid)
		assert_eq(f.kept_power, e[3], "%s balanced preset kept power" % fid)
		assert_eq(f.mandates, e[4], "%s balanced preset mandates" % fid)
		assert_eq(f.ruler_generation, 1)
		assert_eq(f.ruler_status, RulerRules.ALIVE)
		assert_eq(f.sacrifices, [])
		var stats := RulerRules.ruler_stats(f.ruler_type, f.kept_power)
		assert_eq(ruler_army.ruler.current_hp, stats.hp, "the ruler starts at full hp")
		assert_eq(ruler_army.ruler.type, f.ruler_unit_type, "its stats are the faction's ruler type")
		assert_eq(ruler_army.ruler.type.attack, stats.attack)
	assert_true(s.validate([]))
	# The rest of the M1 setup is untouched: gold, provinces, the RNG.
	var md := m1.to_dict()
	var sd := s.to_dict()
	assert_eq(sd.provinces, md.provinces)
	assert_eq(sd.rng, md.rng)
	assert_eq(sd.current_turn, 0)
	for i in md.factions.size():
		assert_eq(sd.factions[i].gold, md.factions[i].gold)
	assert_eq(GameScreen.starting_state({"seed": 7, "rulers": true}).to_dict(), sd, "the game screen's opt-in")


func test_builds_given_at_setup_set_the_ruler_from_kept_power() -> void:
	var s := _with_rulers(11, {"kingdom": {"ruler": "aurel_king", "mandates": ["royal_armories", "heavy_tithes"]},
		"beasts": "beast_god_unbound"})
	var k := s.find_faction("kingdom")
	assert_eq(k.kept_power, 3, "10 - 3 - 4")
	assert_eq(RulerRules.ruler_unit(s, "kingdom").type.hp, 24, "King Corvane at 3 kept: 18 + 6")
	assert_eq(RulerRules.ruler_unit(s, "kingdom").type.name, "King Corvane I")
	var b := s.find_faction("beasts")
	assert_eq(b.ruler_type, "thornmane_avatar")
	assert_eq(b.kept_power, 10, "a preset with no mandates keeps 10")
	assert_eq(RulerRules.ruler_unit(s, "beasts").current_hp, 54)
	# An illegal build sets nothing up.
	var errors := []
	assert_eq(GameState.with_rulers(11, {"kingdom": {"ruler": "aurel_king", "mandates": ["blood_frenzy"]}}, errors), null)
	assert_eq(errors.size(), 1, str(errors))
	assert_true(String(errors[0]).contains("Blood Frenzy"), str(errors))
	errors.clear()
	assert_eq(GameState.with_rulers(11, {"dragons": "iron_crown"}, errors), null, "a build for no faction")
	assert_eq(errors, ["A build was given for a faction that is not in this game."])


# --- serialization and replay ---------------------------------------------------------------------

## A state with rulers where every new field is away from its default, and still valid.
func _busy_state() -> GameState:
	var s := _with_rulers(5, {"kingdom": {"ruler": "aurel_king", "mandates": ["royal_armories", "kings_roads"]}})
	s.current_turn = 6
	var k := s.find_faction("kingdom")
	k.mandates.append("drilled_ranks")
	k.sacrifices = [{"turn": 4, "mandate": "drilled_ranks", "cost": 3}]
	k.kept_power = 1
	k.ruler_generation = 2
	RulerRules.refresh_ruler(s, "kingdom")
	var king := RulerRules.ruler_army(s, "kingdom")
	king.location = "highcrag"
	king.ruler.current_hp = 11
	s.find_province("highcrag").owner = "kingdom"
	var b := s.find_faction("beasts")
	b.ruler_status = RulerRules.DEAD
	b.successor_turn = 8
	b.successor_power = 2
	s.armies.erase(RulerRules.ruler_army(s, "beasts"))
	var errors := []
	assert_true(s.validate(errors), str(errors))
	return s


func test_round_trips_keep_every_new_field() -> void:
	var s := _busy_state()
	var d := s.to_dict()
	var kd: Dictionary = d.factions[0] if d.factions[0].id == "kingdom" else d.factions[1]
	assert_eq(kd.ruler_type, "aurel_king")
	assert_eq(kd.kept_power, 1)
	assert_eq(kd.mandates, ["royal_armories", "kings_roads", "drilled_ranks"])
	assert_eq(kd.ruler_generation, 2)
	assert_eq(kd.ruler_status, "alive")
	assert_eq(kd.sacrifices, [{"turn": 4, "mandate": "drilled_ranks", "cost": 3}])
	for copy in [GameState.from_dict(d), GameState.from_dict(JSON.parse_string(JSON.stringify(d))), s.deep_copy()]:
		assert_true(copy != null, "it loads")
		assert_eq(copy.to_dict(), d, "every field survives")
		var k: Faction = copy.find_faction("kingdom")
		assert_eq([k.ruler_type, k.kept_power, k.mandates, k.ruler_generation, k.ruler_status, k.successor_turn,
			k.successor_power, k.sacrifices], ["aurel_king", 1, ["royal_armories", "kings_roads", "drilled_ranks"], 2,
			"alive", 0, 0, [{"turn": 4, "mandate": "drilled_ranks", "cost": 3}]])
		var b: Faction = copy.find_faction("beasts")
		assert_eq([b.ruler_type, b.kept_power, b.ruler_status, b.successor_turn, b.successor_power],
			["fang_chieftain", 5, "dead", 8, 2])
		assert_eq(RulerRules.ruler_army(copy, "beasts"), null, "the dead ruler has no army")
		var king := RulerRules.ruler_army(copy, "kingdom")
		assert_eq(king.location, "highcrag")
		assert_eq(king.ruler.current_hp, 11)
		assert_eq(king.ruler.type, k.ruler_unit_type, "the ruler's type is rebuilt on load")
		assert_eq([king.ruler.type.name, king.ruler.type.hp, king.ruler.type.attack, king.ruler.type.defense],
			["King Corvane II", 20, 9, 8], "from kept power 1 and generation 2")
	# The copy is independent.
	var c := s.deep_copy()
	c.find_faction("kingdom").mandates.append("veteran_levies")
	RulerRules.ruler_unit(c, "kingdom").current_hp = 2
	assert_eq(s.find_faction("kingdom").mandates.size(), 3)
	assert_eq(RulerRules.ruler_unit(s, "kingdom").current_hp, 11)


func test_a_recorded_game_with_builds_replays_to_an_identical_state() -> void:
	var start := _with_rulers(21, {"kingdom": "warrior_king", "beasts": {"ruler": "fang_chieftain", "mandates": ["sworn_vassals"]}})
	var session := GameSession.new(start, ["kingdom", "beasts"], 21, AutoBattleResolver.new())
	assert_eq(session.setup_errors(), [])
	var turns := [
		[[MoveOrder.new("kingdom-1", "westwatch"), RecruitOrder.new("spearmen")], [MoveOrder.new("beasts-4", "ebonpeak")]],
		[[MoveOrder.new("kingdom-3", "highcrag")], [MoveOrder.new("beasts-4", "blackwood"), RecruitOrder.new("tuskers")]],
		[[MoveOrder.new("kingdom-3", "thornvale"), MoveOrder.new("kingdom-1", "stonegate")], [MoveOrder.new("beasts-2", "ironspike")]],
		[[], [MoveOrder.new("beasts-4", "wildmoor")]],
	]
	for t in turns:
		for o in t[0]:
			assert_eq(session.queue_order(o), "", "kingdom order accepted")
		assert_eq(session.end_turn(), "")
		assert_eq(session.acknowledge_handoff(), "")
		for o in t[1]:
			assert_eq(session.queue_order(o), "", "beasts order accepted")
		assert_eq(session.end_turn(), "")
		if session.is_over():
			break
		assert_eq(session.acknowledge_handoff(), "")
	var final := session.state()
	assert_eq(final.find_faction("beasts").mandates, ["sworn_vassals"], "mandates carry through the turns")
	var record := session.record()
	assert_eq(record.builds.kingdom.ruler, "aurel_king")
	assert_eq(record.builds.kingdom.kept_power, 10)
	assert_eq(record.builds.beasts.mandates, ["sworn_vassals"])
	assert_eq(record.builds.beasts.kept_power, 6)
	for rec in [record, JSON.parse_string(JSON.stringify(record))]:
		var replayed := GameSession.replay(rec, AutoBattleResolver.new())
		assert_eq(replayed.errors, [])
		assert_true(replayed.state != null)
		if replayed.state != null:
			assert_eq(replayed.state.to_dict(), final.to_dict(), "the replay is identical")


# --- the ruler's army in the resolver -------------------------------------------------------------

func test_ruler_army_moves_captures_and_is_labelled_plainly() -> void:
	var s := _with_rulers(3, {"kingdom": "warrior_king"})
	var king := RulerRules.ruler_army(s, "kingdom")
	assert_eq(TurnResolver.army_label(s, king), "Aurel Crown ruler King Corvane I at Crownkeep")
	assert_eq(TurnResolver.army_label(s, RulerRules.ruler_army(s, "beasts")), "Thornmane Clans ruler the Ninth Fang at Fangridge")
	var session := GameSession.new(s, ["kingdom", "beasts"], 3, StubBattleResolver.new())
	assert_eq(session.describe_order("kingdom", MoveOrder.new(king.id, "highcrag")),
		"Move the Aurel Crown ruler King Corvane I at Crownkeep to Highcrag.")
	# Turn 1: the King rides out alone while army 1 stays home; a recruit joins army 1, never the King.
	var result := TurnResolver.resolve(s, {"kingdom": [MoveOrder.new(king.id, "highcrag"), RecruitOrder.new("spearmen")]}, 1,
		StubBattleResolver.new())
	var after: GameState = result.new_state
	assert_eq(RulerRules.ruler_army(after, "kingdom").location, "highcrag")
	assert_eq(after.find_province("highcrag").owner, "kingdom", "a ruler's army captures like any army")
	var texts := []
	for e in result.events:
		texts.append(e.text)
	assert_true(texts.has("The Aurel Crown ruler King Corvane I at Crownkeep moved to Highcrag."), str(texts))
	assert_eq(after.find_army("kingdom-1").units.size(), s.find_army("kingdom-1").units.size() + 1, "the recruit joined army 1")
	# Turn 2: army 1 leaves too, and the King comes home; a recruit forms a new army beside him.
	var r2 := TurnResolver.resolve(after, {"kingdom": [MoveOrder.new("kingdom-1", "westwatch"), MoveOrder.new(king.id, "crownkeep"),
		RecruitOrder.new("spearmen")]}, 2, StubBattleResolver.new())
	var s2: GameState = r2.new_state
	var home := _armies_at(s2, "kingdom", "crownkeep")
	assert_eq(home.size(), 2, "the King and a new army")
	for a in home:
		if a.ruler != null:
			assert_true(a.units.is_empty(), "recruits never join the ruler's army")
		else:
			assert_eq(a.units.size(), 1, "the recruit formed its own army")
	for e in result.events + r2.events:
		_assert_no_raw_ids(e.text, "event %s" % e.type)


func test_a_ruler_army_that_wins_beside_army_1_is_not_removed_as_empty() -> void:
	for resolver in [StubBattleResolver.new(), AutoBattleResolver.new()]:
		var s := _with_rulers(9)
		# A lone Fangthrower attacks the Crown capital, held by army 1 and the Ever-Regent.
		s.armies.erase(s.find_army("beasts-2"))
		var raider := Army.new()
		raider.id = "beasts-9"
		raider.owner = "beasts"
		raider.location = "westwatch"
		raider.units.append(Unit.new(TurnResolver.recruitable_type(s.find_faction("beasts"), "fangthrowers"), "beasts"))
		s.armies.append(raider)
		var result := TurnResolver.resolve(s, {"beasts": [MoveOrder.new("beasts-9", "crownkeep")]}, 4, resolver)
		var after: GameState = result.new_state
		assert_true(after != null, "the turn resolves")
		assert_eq(after.find_army("beasts-9"), null, "the raider lost")
		var regent := RulerRules.ruler_army(after, "kingdom")
		assert_true(regent != null and regent.location == "crownkeep", "the ruler's army is still there")
		assert_true(after.validate([]))


func test_a_lone_ruler_army_attacked_before_rulers_fight_keeps_the_state_valid() -> void:
	# Until rulers fight in battles (M2-2) and die properly (M2-3), a lone ruler's army that is attacked
	# loses with its side. The resolver must not break: the state stays valid and mandates stay.
	var s := _with_rulers(12)
	var fang := RulerRules.ruler_army(s, "beasts")
	fang.location = "ebonpeak"
	var result := TurnResolver.resolve(s, {"kingdom": [MoveOrder.new("kingdom-1", "westwatch")],
		"beasts": []}, 8, AutoBattleResolver.new())
	var s2: GameState = result.new_state
	var r2 := TurnResolver.resolve(s2, {"kingdom": [MoveOrder.new("kingdom-1", "stonegate")]}, 9, AutoBattleResolver.new())
	var s3: GameState = r2.new_state
	var r3 := TurnResolver.resolve(s3, {"kingdom": [MoveOrder.new("kingdom-1", "blackwood")]}, 10, AutoBattleResolver.new())
	var s4: GameState = r3.new_state
	var r4 := TurnResolver.resolve(s4, {"kingdom": [MoveOrder.new("kingdom-1", "ebonpeak")]}, 11, AutoBattleResolver.new())
	var s5: GameState = r4.new_state
	assert_true(s5 != null, "the battle resolves")
	assert_eq(RulerRules.ruler_army(s5, "beasts"), null, "the lone ruler's army was lost with its side")
	assert_eq(s5.find_faction("beasts").mandates, ["iron_discipline", "drilled_ranks"], "mandates stay")
	assert_true(s5.deep_copy() != null, "the state is still valid")


# --- breakdowns and the map -----------------------------------------------------------------------

func test_ruler_breakdowns_explain_every_number() -> void:
	var s := _with_rulers(4)
	for fid in ["kingdom", "beasts"]:
		var f := s.find_faction(fid)
		for stat in STATS:
			var b := Breakdown.ruler_stat(s, fid, stat)
			assert_eq(int(b.total), RulerRules.stat_value(f.ruler_type, stat, f.kept_power))
			_assert_breakdown(b, "%s %s" % [fid, stat])
		var m := Breakdown.ruler_stat(s, fid, "morale")
		assert_eq(int(m.total), RulerRules.ruler_stats(f.ruler_type, 0).morale)
		_assert_breakdown(m, "%s morale" % fid)
		var kept := Breakdown.kept_power(s, fid)
		assert_eq(int(kept.total), f.kept_power)
		_assert_breakdown(kept, "%s kept power" % fid)
		var rank := Breakdown.ability_rank(s, fid)
		assert_eq(int(rank.total), RulerRules.ability_rank(f.kept_power))
		_assert_breakdown(rank, "%s ability rank" % fid)
	# §7.1's wording: "Attack 14 = base 9 + 5 from 10 kept power".
	var attack := Breakdown.ruler_stat_at("aurel_king", "attack", 10)
	assert_eq(attack.lines.map(func(l): return l.value), [9, 5])
	assert_eq(attack.lines[1].label, "From 10 kept power")
	assert_eq(attack.title, "Attack of King Corvane I")
	var rank := Breakdown.ability_rank_at("ever_regent", 4)
	assert_eq(rank.lines.map(func(l): return l.value), [1, 1])
	assert_true(String(rank.description).begins_with("Mending Light at rank 2: "), rank.description)
	assert_true(String(rank.description).contains("heals 6 hit points"), rank.description)
	# Kept power: "Kept power 5 = pool 10 - Royal Armories 3 - King's Roads 2".
	var kept := Breakdown.kept_power(s, "kingdom")
	assert_eq(kept.lines.map(func(l): return [l.label, l.value]), [["Power pool", 10], ["Royal Armories", -3], ["King's Roads", -2]])
	# A game without rulers explains that instead.
	var none := Breakdown.kept_power(GameState.new(4), "kingdom")
	assert_eq(int(none.total), 0)
	assert_true(String(none.description).contains("no ruler"))


func test_ruler_army_on_the_map_reads_plainly_and_explains_every_number() -> void:
	var game := load("res://ui/game_screen.tscn").instantiate() as GameScreen
	game.start_game({"players": ["kingdom", "beasts"], "seed": 99, "rulers": true})
	var map := game.map
	assert_true(RulerRules.has_rulers(map.state), "the game screen started a game with rulers")
	map.select_province("crownkeep")
	var panel := map.details.find_child("Army_kingdom-3", true, false)
	assert_true(panel != null, "the ruler's army is listed in the side panel")
	var header := panel.find_child("ArmyHeader", true, false) as Button
	assert_eq(header.text, "Aurel Crown ruler the Ever-Regent at Crownkeep")
	assert_eq(String(header.get_meta(CodexLink.META)), "ruler_army")
	var numbers := 0
	for node_name in ["RulerLabel", "RulerHpLabel", "RulerAttackLabel", "RulerDefenseLabel", "RulerMoraleLabel",
			"KeptPowerLabel", "AbilityLabel", "MandatesLabel", "SuccessionLabel"]:
		var l := panel.find_child(node_name, true, false) as Label
		assert_true(l != null, "%s is shown" % node_name)
		if l == null:
			continue
		var key := String(l.get_meta(CodexLink.META, ""))
		assert_true(RulesCodex.ENTRIES.has(key), "%s links an existing codex entry (%s)" % [node_name, key])
		assert_true(l.tooltip_text.replace("\n", " ").ends_with("Codex: %s (right-click or F1 to open)" % RulesCodex.entry(key).title),
			"%s's tooltip ends with its codex entry" % node_name)
		_assert_no_raw_ids(l.text, node_name)
		var has_digit := false
		for ch in l.text:
			if ch >= "0" and ch <= "9":
				has_digit = true
		if has_digit:
			numbers += 1
			assert_true(l.tooltip_text.contains("= "), "%s's tooltip shows a breakdown total: %s" % [node_name, l.tooltip_text])
	assert_true(numbers >= 6, "hit points, attack, defense, morale, kept power and ability rank (%d)" % numbers)
	assert_eq((panel.find_child("RulerHpLabel", true, false) as Label).text, "Hit points: 19 of 19")
	assert_eq((panel.find_child("KeptPowerLabel", true, false) as Label).text, "Kept power: 5 of 10")
	assert_eq((panel.find_child("AbilityLabel", true, false) as Label).text, "Ability: Mending Light, rank 2 (heal 6)")
	assert_eq((panel.find_child("MandatesLabel", true, false) as Label).text, "Mandates: Royal Armories, King's Roads")
	_assert_no_raw_ids(header.tooltip_text, "the ruler's summary")
	# The province badge names the ruler's army instead of counting units.
	var badges: Array = map.regions["crownkeep"].army_box.get_children()
	assert_eq(badges.size(), 2)
	var ruler_badge: Button = badges.filter(func(b): return b.text == "Ruler")[0]
	assert_eq(String(ruler_badge.get_meta(CodexLink.META)), "ruler_army")
	assert_true(ruler_badge.tooltip_text.contains("Aurel Crown ruler the Ever-Regent at Crownkeep"), ruler_badge.tooltip_text)
	assert_true(ruler_badge.tooltip_text.contains("Hit points 19 of 19, attack 13, defense 8"), ruler_badge.tooltip_text)
	# Right-clicking a ruler number opens the codex there.
	var kept_label := panel.find_child("KeptPowerLabel", true, false) as Label
	kept_label.gui_input.emit(CodexLink.right_click())
	assert_true(game.codex.visible)
	assert_eq(game.codex.current_key(), "kept_power")
	game.free()


# --- codex ----------------------------------------------------------------------------------------

func test_every_m2_codex_entry_exists_in_one_block() -> void:
	var keys: Array = RulesCodex.ENTRIES.keys()
	for key in M2_CODEX_KEYS:
		assert_true(RulesCodex.ENTRIES.has(key), "codex entry %s exists" % key)
		assert_false(String(RulesCodex.entry(key).get("title", "")).is_empty(), "%s has a title" % key)
		assert_true(RulesCodex.text(key).length() > 40, "%s has text" % key)
	var first := keys.find(M2_CODEX_KEYS[0])
	assert_eq(keys.slice(first, first + M2_CODEX_KEYS.size()), M2_CODEX_KEYS, "one contiguous block, in §7.2 order")
	# Every codex id the data names exists, and the per-ruler entries carry the data's numbers.
	for r in RulerData.RULERS:
		var text := RulesCodex.text("ruler_" + r.id)
		assert_true(text.contains(RulerRules.ability_name(r.id)), "%s's entry names its ability" % r.id)
		assert_true(text.contains("Hit points %d" % RulerRules.stat_value(r.id, "hp", 0)), "%s's entry has its base hp" % r.id)
		assert_true(text.contains("%d hit points" % RulerRules.stat_value(r.id, "hp", 10)), "%s's entry has its hp at 10 kept" % r.id)
		assert_true(RulesCodex.ENTRIES.has("ability_" + String(r.ability)), "%s's ability has an entry" % r.id)
	for m in MandateData.MANDATES:
		assert_true(RulesCodex.ENTRIES.has(String(m.codex)), "%s has a codex entry" % m.id)
		assert_eq(String(RulesCodex.entry(m.codex).title), String(m.name))
		assert_true(RulesCodex.text(m.codex).contains("%d power" % int(m.cost)), "%s's entry states its cost" % m.id)
		assert_true(RulesCodex.text("mandates").contains(String(m.name)), "the mandates entry names %s" % m.name)
	for fid in BuildPresetData.PRESETS:
		for p in BuildPresetData.PRESETS[fid]:
			assert_true(RulesCodex.text("build_presets").contains(String(p.name)), "the presets entry names %s" % p.name)
