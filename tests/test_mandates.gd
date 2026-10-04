extends "res://tests/test_case.gd"
## M2-1 (#29): mandates and builds. The §2.2 list and the §6.1 presets, build validation with plain
## reasons, applying builds, the kept power breakdown with sacrifices and successions, unit stats with
## mandates, what later tickets read, and the plain-language checks from_dict makes on ruler data.

## design/M2_RULER.md §2.2: id -> [cost, faction ("" = shared)].
const SPEC_MANDATES := {
	"iron_discipline": [3, ""], "drilled_ranks": [2, ""], "veteran_levies": [3, ""], "heavy_tithes": [4, ""],
	"muster_grounds": [4, ""], "sworn_vassals": [4, ""], "royal_armories": [3, "kingdom"], "kings_roads": [2, "kingdom"],
	"blood_frenzy": [3, "beasts"], "feast_of_victory": [3, "beasts"],
}
## §6.1: preset id -> [faction, ruler, mandates, kept].
const SPEC_PRESETS := {
	"warrior_king": ["kingdom", "aurel_king", [], 10],
	"iron_crown": ["kingdom", "aurel_king", ["royal_armories", "heavy_tithes", "veteran_levies"], 0],
	"regents_court": ["kingdom", "ever_regent", ["royal_armories", "kings_roads"], 5],
	"beast_god_unbound": ["beasts", "thornmane_avatar", [], 10],
	"clan_moot": ["beasts", "fang_chieftain", ["iron_discipline", "blood_frenzy", "sworn_vassals"], 0],
	"blood_of_the_fang": ["beasts", "fang_chieftain", ["iron_discipline", "drilled_ranks"], 5],
}
## Known ids that must not appear in a reason about them (the display name must be used instead).
const KNOWN_IDS := ["kingdom", "beasts", "aurel_king", "ever_regent", "thornmane_avatar", "fang_chieftain",
	"royal_armories", "heavy_tithes", "muster_grounds", "drilled_ranks", "blood_frenzy", "iron_crown", "clan_moot"]


func _assert_plain(reason: String, what: String) -> void:
	assert_false(reason.is_empty(), "%s has a reason" % what)
	assert_true(reason.ends_with("."), "%s reads as a sentence: %s" % [what, reason])
	for id in KNOWN_IDS:
		assert_false(reason.contains(id), "%s names things, not ids ('%s'): %s" % [what, id, reason])


func _only_reason(faction_id: String, build, what: String) -> String:
	var errors := RulerRules.build_errors(faction_id, build)
	assert_eq(errors.size(), 1, "%s gives one reason: %s" % [what, errors])
	if errors.is_empty():
		return ""
	_assert_plain(String(errors[0]), what)
	return String(errors[0])


# --- the data -------------------------------------------------------------------------------------

func test_the_mandate_list_matches_the_spec() -> void:
	assert_eq(MandateData.MANDATES.size(), 10)
	var shared_cost := 0
	for m in MandateData.MANDATES:
		assert_true(SPEC_MANDATES.has(m.id), "%s is in the spec" % m.id)
		assert_eq(m.cost, SPEC_MANDATES[m.id][0], "%s cost" % m.id)
		assert_eq(m.faction, SPEC_MANDATES[m.id][1], "%s is shared or exclusive as in the spec" % m.id)
		assert_false(String(m.name).is_empty() or String(m.effect).is_empty(), "%s has a name and an effect" % m.id)
		assert_false(String(m.effect).contains("_"), "%s's effect has no raw ids" % m.id)
		if String(m.faction).is_empty():
			shared_cost += int(m.cost)
	assert_eq(shared_cost, 20, "the shared six cost 20 (§2.2)")
	assert_eq(MandateData.SACRIFICE_PREMIUM, 1)
	assert_eq(RulerRules.available_mandates("kingdom"), ["iron_discipline", "drilled_ranks", "veteran_levies",
		"heavy_tithes", "muster_grounds", "sworn_vassals", "royal_armories", "kings_roads"])
	assert_eq(RulerRules.available_mandates("beasts"), ["iron_discipline", "drilled_ranks", "veteran_levies",
		"heavy_tithes", "muster_grounds", "sworn_vassals", "blood_frenzy", "feast_of_victory"])
	for fid in ["kingdom", "beasts"]:
		var everything := {"ruler": RulerRules.rulers_for(fid)[0], "mandates": RulerRules.available_mandates(fid)}
		var want: int = {"kingdom": 25, "beasts": 26}[fid]
		assert_eq(RulerRules.build_cost(everything), want, "buying everything costs %d (§2.2), far over the pool" % want)


func test_presets_match_the_spec_and_are_legal() -> void:
	var seen := 0
	for fid in BuildPresetData.PRESETS:
		assert_eq(BuildPresetData.PRESETS[fid].size(), 3, "three presets for %s" % fid)
		for p in BuildPresetData.PRESETS[fid]:
			seen += 1
			var spec: Array = SPEC_PRESETS[p.id]
			assert_eq(fid, spec[0], "%s faction" % p.id)
			assert_eq(p.ruler, spec[1], "%s ruler" % p.id)
			assert_eq(p.mandates, spec[2], "%s mandates" % p.id)
			assert_eq(RulerRules.kept_after(p.id), spec[3], "%s keeps %d" % [p.id, spec[3]])
			assert_eq(RulerRules.build_errors(fid, p.id), [], "%s is legal" % p.id)
			assert_eq(RulerRules.build_errors(fid, RulerRules.preset_build(p.id)), [], "%s as a build is legal" % p.id)
			for mid in p.ai_sacrifices:
				assert_true(RulerRules.available_mandates(fid).has(mid), "%s's AI sacrifices are on its list" % p.id)
	assert_eq(seen, 6)
	assert_eq(RulerRules.balanced_preset("kingdom"), "regents_court")
	assert_eq(RulerRules.balanced_preset("beasts"), "blood_of_the_fang")
	assert_eq(RulerRules.preset_build("iron_crown"), {"preset": "iron_crown", "ruler": "aurel_king",
		"mandates": ["royal_armories", "heavy_tithes", "veteran_levies"]})


# --- build validation -----------------------------------------------------------------------------

func test_illegal_builds_are_rejected_with_plain_reasons() -> void:
	var over := _only_reason("kingdom", {"ruler": "aurel_king", "mandates": ["royal_armories", "heavy_tithes", "muster_grounds"]}, "over the pool")
	assert_eq(over, "These mandates cost 11 power (Royal Armories 3 + Heavy Tithes 4 + Muster Grounds 4), but the power pool is only 10. Drop mandates worth at least 1 power.")
	var twice := _only_reason("beasts", {"ruler": "fang_chieftain", "mandates": ["drilled_ranks", "drilled_ranks"]}, "a duplicate")
	assert_eq(twice, "Drilled Ranks is in the build twice. Each mandate can be taken only once.")
	var foreign := _only_reason("kingdom", {"ruler": "ever_regent", "mandates": ["blood_frenzy"]}, "another faction's exclusive")
	assert_eq(foreign, "Blood Frenzy is a Thornmane Clans mandate, so the Aurel Crown can't take it.")
	var foreign2 := _only_reason("beasts", {"ruler": "thornmane_avatar", "mandates": ["kings_roads", "drilled_ranks"]}, "the other way")
	assert_eq(foreign2, "King's Roads is an Aurel Crown mandate, so the Thornmane Clans can't take it.")
	assert_eq(_only_reason("beasts", "iron_crown", "the other faction's preset"),
		"Iron Crown is an Aurel Crown preset, not one of the Thornmane Clans'. Its presets are Beast-God Unbound, Clan Moot and Blood of the Fang.")
	var unknown := RulerRules.build_errors("kingdom", {"ruler": "aurel_king", "mandates": ["dragon_pact"]})
	assert_eq(unknown, ["'dragon_pact' is not a mandate in this game."], "an unknown id is named, since it has no name")
	# The ruler: unknown, another faction's, or none.
	assert_eq(_only_reason("kingdom", {"ruler": "the_lich", "mandates": []}, "an unknown ruler").substr(0, 12), "'the_lich' i")
	assert_eq(_only_reason("kingdom", {"ruler": "fang_chieftain", "mandates": []}, "another faction's ruler"),
		"The Ninth Fang leads the Thornmane Clans, not the Aurel Crown. The Aurel Crown can choose King Corvane I or the Ever-Regent.")
	assert_eq(_only_reason("beasts", {"mandates": ["iron_discipline"]}, "no ruler"),
		"No ruler is chosen. The Thornmane Clans can choose the Great Thornmane or the Ninth Fang.")
	# Presets: unknown, or another faction's.
	assert_true(_only_reason("kingdom", "dragon_horde", "an unknown preset").contains("Warrior King, Iron Crown and Regent's Court"))
	assert_eq(_only_reason("kingdom", "clan_moot", "another faction's preset"),
		"Clan Moot is a Thornmane Clans preset, not one of the Aurel Crown's. Its presets are Warrior King, Iron Crown and Regent's Court.")
	# Not a build at all, or a faction that isn't in the game.
	_only_reason("kingdom", 42, "not a build")
	_only_reason("dragons", {"ruler": "aurel_king", "mandates": []}, "an unknown faction")
	_only_reason("kingdom", {"ruler": "aurel_king", "mandates": "royal_armories"}, "mandates that aren't a list")
	# Several problems at once: each gets its reason.
	var many := RulerRules.build_errors("kingdom", {"ruler": "aurel_king",
		"mandates": ["royal_armories", "royal_armories", "blood_frenzy", "heavy_tithes", "muster_grounds"]})
	assert_eq(many.size(), 3, "twice, exclusive, over the pool: %s" % [many])


func test_an_illegal_build_changes_nothing() -> void:
	var s := GameState.new(3)
	var before := s.to_dict()
	var errors := RulerRules.apply_build(s, "kingdom", {"ruler": "aurel_king", "mandates": ["royal_armories", "heavy_tithes", "muster_grounds"]})
	assert_eq(errors.size(), 1)
	assert_eq(s.to_dict(), before, "nothing changed")
	errors = []
	assert_false(s.setup_rulers({"kingdom": "warrior_king", "beasts": "iron_crown"}, errors), "one bad build stops the setup")
	assert_eq(s.to_dict(), before, "all or nothing")
	assert_eq(errors.size(), 1, str(errors))


func test_an_empty_build_keeps_all_ten() -> void:
	for build in [{"ruler": "aurel_king", "mandates": []}, {"ruler": "aurel_king"}]:
		assert_eq(RulerRules.build_errors("kingdom", build), [], "an empty build is legal")
		assert_eq(RulerRules.kept_after(build), 10)
		var kept := Breakdown.build_kept_power(build)
		assert_eq(int(kept.total), 10)
		assert_eq(kept.lines.size(), 1, "just the pool")
	var s := GameState.with_rulers(3, {"kingdom": {"ruler": "aurel_king", "mandates": []}, "beasts": {"ruler": "thornmane_avatar", "mandates": []}})
	assert_true(s != null)
	assert_eq(s.find_faction("kingdom").kept_power, 10)
	assert_eq(s.find_faction("kingdom").mandates, [])
	assert_eq(RulerRules.ruler_unit(s, "kingdom").type.hp, 38, "King Corvane with 10 kept")
	assert_eq(RulerRules.ruler_unit(s, "beasts").type.attack, 18, "the Great Thornmane with 10 kept")
	# A build applied before turn 1 can be changed again then; after turn 1 it can't.
	assert_eq(RulerRules.apply_build(s, "kingdom", "iron_crown"), [])
	assert_eq(s.find_faction("kingdom").kept_power, 0)
	assert_eq(RulerRules.ruler_unit(s, "kingdom").type.hp, 18)
	assert_eq(s.armies.size(), 4, "the same ruler's army, re-equipped")
	s.current_turn = 1
	var late := RulerRules.apply_build(s, "kingdom", "warrior_king")
	assert_eq(late.size(), 1)
	assert_true(String(late[0]).contains("sacrifice"), str(late))


func test_build_kept_power_breakdown() -> void:
	var b := Breakdown.build_kept_power({"ruler": "ever_regent", "mandates": ["royal_armories", "kings_roads"]})
	assert_eq(b.lines.map(func(l): return [l.label, l.value]), [["Power pool", 10], ["Royal Armories", -3], ["King's Roads", -2]])
	assert_eq(int(b.total), 5)
	assert_eq(Breakdown.sum_of_lines(b), 5)
	assert_eq(String(b.codex), "kept_power")
	assert_eq(int(Breakdown.build_kept_power("clan_moot").total), 0)


func test_kept_power_breakdown_counts_sacrifices_and_successions() -> void:
	var s := GameState.with_rulers(8, {"kingdom": "regents_court"})
	var k := s.find_faction("kingdom")
	k.mandates.append("drilled_ranks")
	k.sacrifices = [{"turn": 3, "mandate": "drilled_ranks", "cost": 3}]
	k.kept_power = 2
	RulerRules.refresh_ruler(s, "kingdom")
	assert_true(s.validate([]))
	var b := Breakdown.kept_power(s, "kingdom")
	assert_eq(b.lines.map(func(l): return l.value), [10, -3, -2, -3])
	assert_eq(b.lines[3].label, "Drilled Ranks, sacrificed on turn 3")
	assert_eq(int(b.total), 2)
	# After a succession took the last point, a line says so and the lines still sum to the total.
	k.kept_power = 0
	RulerRules.refresh_ruler(s, "kingdom")
	b = Breakdown.kept_power(s, "kingdom")
	assert_eq(b.lines.back().label, "Successions")
	assert_eq(b.lines.back().value, -2)
	assert_eq(Breakdown.sum_of_lines(b), 0)
	assert_eq(RulerRules.ruler_unit(s, "kingdom").type.hp, 14, "the Regent's stats follow kept power")


# --- what later tickets read ----------------------------------------------------------------------

func test_unit_stats_apply_the_mandates_numbers() -> void:
	var s := GameState.with_rulers(2, {"kingdom": {"ruler": "aurel_king", "mandates": ["royal_armories", "veteran_levies", "muster_grounds"]}})
	var k := s.find_faction("kingdom")
	for ut in k.unit_types:
		var us := RulerRules.unit_stats(s, "kingdom", ut.id)
		assert_true(us.ok)
		assert_eq(us.attack, ut.attack + 1, "%s attack with Royal Armories" % ut.name)
		assert_eq(us.defense, ut.defense, "%s defense: Royal Armories adds attack only (M2-8, breakpoint-safe)" % ut.name)
		assert_eq(us.hp, ut.hp + 2, "%s max hp with Veteran Levies" % ut.name)
		assert_eq(us.cost, ut.cost - floori(ut.cost / 5.0), "%s price with Muster Grounds" % ut.name)
		for stat in ["hp", "attack", "defense", "cost"]:
			var b := Breakdown.unit_stat(s, "kingdom", ut.id, stat)
			assert_eq(int(b.total), us[stat])
			assert_eq(Breakdown.sum_of_lines(b), int(b.total), "%s %s lines sum up" % [ut.name, stat])
			assert_eq(b.lines[0].label, ut.name)
	# Commanders are not regular units: only Muster Grounds touches them. The ruler is not a unit at all.
	var cap := RulerRules.unit_stats(s, "kingdom", k.commander_type.id)
	assert_eq([cap.hp, cap.attack, cap.defense], [k.commander_type.hp, k.commander_type.attack, k.commander_type.defense])
	assert_eq(cap.cost, k.commander_type.cost - floori(k.commander_type.cost / 5.0))
	assert_false(RulerRules.unit_stats(s, "kingdom", "aurel_king").ok, "rulers have no unit stats")
	assert_false(RulerRules.unit_stats(s, "kingdom", "tuskers").ok, "not this faction's unit")
	# §7.1's wording: "Attack 10 = Spearmen 9 + Royal Armories 1".
	var spear := Breakdown.unit_stat(s, "kingdom", "spearmen", "attack")
	assert_eq(spear.lines[1].label, "Royal Armories")
	assert_eq(spear.lines[1].value, 1)
	# Without mandates (or without rulers) the numbers are the unit type's own.
	var plain := RulerRules.unit_stats(GameState.new(2), "kingdom", "knights")
	var knights := TurnResolver.recruitable_type(GameState.new(2).find_faction("kingdom"), "knights")
	assert_eq([plain.hp, plain.attack, plain.defense, plain.cost], [knights.hp, knights.attack, knights.defense, knights.cost])


func test_rulers_and_mandates_are_readable_for_later_tickets() -> void:
	var s := GameState.with_rulers(6, {"beasts": "clan_moot"})
	assert_eq(RulerRules.kept_power(s, "beasts"), 0)
	assert_eq(RulerRules.mandates(s, "beasts"), ["iron_discipline", "blood_frenzy", "sworn_vassals"])
	assert_true(RulerRules.has_mandate(s, "beasts", "sworn_vassals"))
	assert_false(RulerRules.has_mandate(s, "beasts", "drilled_ranks"))
	assert_eq(RulerRules.current_name(s, "beasts"), "the Ninth Fang")
	assert_eq(RulerRules.ruler_army(s, "beasts").id, "beasts-4")
	assert_eq(RulerRules.ruler_unit(s, "beasts").type.hp, 20)
	assert_eq(RulerRules.build_of(s, "beasts"), {"ruler": "fang_chieftain", "ruler_name": "the Ninth Fang", "kept_power": 0,
		"mandates": ["iron_discipline", "blood_frenzy", "sworn_vassals"],
		"mandate_names": ["Iron Discipline", "Blood Frenzy", "Sworn Vassals"], "status": "alive", "generation": 1})
	var m1 := GameState.new(6)
	assert_eq(RulerRules.kept_power(m1, "beasts"), 0)
	assert_eq(RulerRules.mandates(m1, "beasts"), [])
	assert_eq(RulerRules.ruler_army(m1, "beasts"), null)
	assert_eq(RulerRules.build_of(m1, "beasts"), {})


# --- from_dict rejects bad ruler data in plain language --------------------------------------------

func _rejects(mutate: Callable, phrase: String) -> void:
	var d := GameState.with_rulers(4).to_dict()
	mutate.call(d)
	var errors := []
	var s := GameState.from_dict(d, errors)
	assert_eq(s, null, "rejected: %s" % phrase)
	var joined := " ".join(errors)
	assert_true(joined.contains(phrase), "says '%s': %s" % [phrase, joined])


func _faction(d: Dictionary, fid: String) -> Dictionary:
	for f in d.factions:
		if f.id == fid:
			return f
	return {}


func _ruler_army(d: Dictionary, fid: String) -> Dictionary:
	for a in d.armies:
		if a.owner == fid and a.has("ruler"):
			return a
	return {}


func test_from_dict_rejects_bad_ruler_data_in_plain_language() -> void:
	_rejects(func(d): _faction(d, "kingdom").kept_power = 11, "kept power is always from 0 to 10")
	_rejects(func(d): _faction(d, "kingdom").kept_power = -1, "kept power is always from 0 to 10")
	_rejects(func(d): _faction(d, "kingdom").kept_power = 9, "Kept power never goes up")
	_rejects(func(d): _faction(d, "kingdom").ruler_type = "the_lich", "'the_lich', which is not a ruler")
	_rejects(func(d): _faction(d, "kingdom").ruler_type = "fang_chieftain", "who leads the Thornmane Clans")
	_rejects(func(d): _faction(d, "kingdom").mandates.append("dragon_pact"), "'dragon_pact', which is not a mandate")
	_rejects(func(d): _faction(d, "kingdom").mandates.append("kings_roads"), "has King's Roads twice")
	_rejects(func(d): _faction(d, "kingdom").mandates.append("feast_of_victory"), "Feast of Victory, which only the Thornmane Clans can take")
	_rejects(func(d): _faction(d, "beasts").ruler_status = "sleeping", "either alive or dead")
	_rejects(func(d): _faction(d, "beasts").ruler_status = "dead", "is dead, but its ruler's army is still at Fangridge")
	_rejects(func(d): _ruler_army(d, "kingdom").units.append({"type_id": "spearmen", "current_hp": 10, "owner": "kingdom"}),
		"A ruler travels alone, as its own army")
	_rejects(func(d): _ruler_army(d, "kingdom").ruler.current_hp = 99, "at most its maximum")
	_rejects(func(d): _ruler_army(d, "kingdom").ruler.current_hp = 0, "at least 1")
	var add_twin := func(d):
		var twin: Dictionary = _ruler_army(d, "kingdom").duplicate(true)
		twin.id = "kingdom-9"
		d.armies.append(twin)
	_rejects(add_twin, "at most one living ruler")
	_rejects(func(d): _faction(d, "kingdom").erase("ruler_type"), "has mandates but no ruler")
	var ruler_as_commander := func(d):
		var army: Dictionary = d.armies[0]
		army.commander = {"type_id": "ever_regent", "current_hp": 22, "owner": "kingdom"}
	_rejects(ruler_as_commander, "Rulers are not commanders")
