extends "res://tests/test_case.gd"
## M5-5 (#116) acceptance, the magic rules model (design/M5_MAGIC_FOG.md §3-§7, §18): the cast legality table with
## its plain reasons, mastery for every caster at every ability rank in every school with the cap, §7.1's blood plan,
## the pin (a queued cast drops its army's move, whichever came first), the running budget shared by recruits and
## rituals, Tithe of Blood and Feast of Victory excluding each other, the spellbook, healing under a curse, Far Sight's
## vision grants and the magic breakdowns. Expected numbers come from MagicData, RulerRules and the map.

const CROWN := "kingdom"
const CLANS := "beasts"


# --- helpers ----------------------------------------------------------------------------------------

## A magic game: the Crown as Regent's Court (the Ever-Regent), the Clans as Blood of the Fang (the Ninth Fang), with
## `nodes` researched ({faction id: [node ids]}), plenty of gold, and a mage of each faction in its starting army.
func _game(nodes: Dictionary = {}, builds: Dictionary = {}) -> GameState:
	var b := {CROWN: "regents_court", CLANS: "blood_of_the_fang"}
	b.merge(builds, true)
	var s := GameState.with_magic(7, b)
	assert_true(s != null, "the magic game starts")
	for fid in nodes:
		s = AscensionRules.with_nodes(s, fid, nodes[fid])
	for f in s.factions:
		f.gold = 200
		var mage := TurnResolver.recruitable_type(f, String(MagicData.MAGES[f.id].id))
		_field_army(s, f.id).units.append(Unit.new(mage, f.id))
	return s


## The faction's starting field army (its first army without the ruler).
func _field_army(s: GameState, fid: String) -> Army:
	for a in s.armies:
		if a.owner == fid and a.ruler == null:
			return a
	return null


func _ruler_army(s: GameState, fid: String) -> Army:
	return RulerRules.ruler_army(s, fid)


## The first province (in id order) exactly `steps` from `from`.
func _at(s: GameState, from: String, steps: int) -> String:
	var d := MagicRules.distances(s, from)
	var ids: Array = d.keys()
	ids.sort()
	for pid in ids:
		if int(d[pid]) == steps:
			return pid
	return ""


func _check(s: GameState, fid: String, order, existing: Array = []) -> Dictionary:
	return OrderBook.check_order(s, fid, order, existing)


func _code(check: Dictionary) -> String:
	return String(check.get("code", ""))


# --- data ---------------------------------------------------------------------------------------------

func test_the_data_has_four_schools_thirteen_spells_and_the_arcana_costs() -> void:
	assert_eq(MagicData.SPELLS.size(), 13, "five battle spells and eight rituals")
	assert_eq(MagicData.SPELLS.values().filter(func(sp): return sp.battle).size(), 5)
	for fid in [CROWN, CLANS]:
		var total := 0
		var by_school := {}
		for n in MagicData.ARCANA[fid]:
			total += int(n.cost)
			by_school[n.school] = int(by_school.get(n.school, 0)) + int(n.cost)
			assert_true(RulesCodex.ENTRIES.has(String(n.codex)), "%s has its codex entry" % n.id)
		for school in by_school:
			assert_eq(by_school[school], 70, "a whole school is 70 research (%s)" % school)
		var tier3 := 0
		for n in MagicData.ARCANA[fid]:
			if n.tier == "III":
				tier3 = int(n.cost)
		assert_eq(total - tier3, 115, "everything a faction can learn: both schools but one greater working")
		assert_eq(MagicData.SPELLBOOK[fid].size(), MagicData.SPELLS.values().filter(func(sp): return sp.battle and MagicRules.schools(fid).has(sp.school)).size(),
			"the default spellbook lists every battle spell of its schools")
	for sid in MagicData.SPELLS:
		assert_true(RulesCodex.ENTRIES.has(String(MagicData.SPELLS[sid].codex)), "%s has its codex entry" % sid)
		assert_false(String(MagicData.SPELLS[sid].text).is_empty(), "%s has its one plain line" % sid)
	for sid in MagicData.SUMMONS:
		assert_true(RulesCodex.ENTRIES.has(String(MagicData.SUMMONS[sid].codex)))
	assert_true(RulesCodex.ENTRIES.has("mandate_tithe_of_blood"))


# --- the cast legality table (§6.1) -----------------------------------------------------------------

func test_the_cast_legality_table_with_plain_reasons() -> void:
	var s := _game({CLANS: ["briar_snare", "call_the_pack", "bloodbolt", "bloodrot"]})
	var shamans := _field_army(s, CLANS)
	var fang := _ruler_army(s, CLANS)
	var home := shamans.location
	var near := _at(s, home, 2)
	var far := _at(s, home, 3)
	var plain := _at(s, home, 1)
	# A Clans army with no caster: a copy of the field army without its Shaman.
	var bare := Army.new()
	bare.id = s.new_army_id(CLANS)
	bare.owner = CLANS
	bare.location = home
	bare.units.append(Unit.new(s.find_faction(CLANS).unit_types[0], CLANS))
	s.armies.append(bare)
	var rows := [
		# [order, existing, code, a piece of the reason]
		[CastOrder.new("bloodrot", shamans.id, near), [], "", ""],
		[CastOrder.new("bloodrot", shamans.id, far), [], "out_of_range",
			"Bloodrot reaches 2 provinces from the caster. %s is 3 from your army at %s." % [s.find_province(far).name, s.find_province(home).name]],
		[CastOrder.new("bloodrot", shamans.id, home), [], "own_province", "a province that isn't yours"],
		[CastOrder.new("blood_moon", shamans.id, ""), [], "not_known", "You don't know Blood Moon yet."],
		[CastOrder.new("sanctum_ward", shamans.id, home), [], "foreign_ritual", "a school of the Aurel Crown"],
		[CastOrder.new("bloodbolt", shamans.id, near), [], "battle_spell", "Bloodbolt is a battle spell"],
		[CastOrder.new("mud_bath", shamans.id, near), [], "unknown_ritual", "'mud_bath' is not a ritual in this game."],
		[CastOrder.new("bloodrot", bare.id, near), [], "no_caster", "holds no caster for Bloodrot"],
		[CastOrder.new("call_the_pack", fang.id, home, CastOrder.GOLD, 3), [], "no_caster", "holds no caster for Call the Pack"],
		[CastOrder.new("bloodrot", fang.id, near), [], "", ""],
		[CastOrder.new("bloodrot", _field_army(s, CROWN).id, near), [], "not_your_army", "not yours"],
		[CastOrder.new("call_the_pack", shamans.id, home, CastOrder.GOLD, 3), [CastOrder.new("bloodrot", shamans.id, near)], "one_per_army",
			"Your army at %s is already casting Bloodrot this turn." % s.find_province(home).name],
		[CastOrder.new("bloodrot", fang.id, near), [CastOrder.new("bloodrot", shamans.id, plain)], "once_per_faction",
			"You are already casting Bloodrot this turn"],
		[CastOrder.new("call_the_pack", shamans.id, near, CastOrder.GOLD, 3), [], "bad_target", "cast on the caster's own province"],
		[CastOrder.new("call_the_pack", shamans.id, home, CastOrder.GOLD, 2), [], "pack_size", "You can call 3 Thornwolves"],
		[CastOrder.new("call_the_pack", shamans.id, home, CastOrder.GOLD, 4), [], "pack_size", "You can call 3 Thornwolves"],
		[CastOrder.new("call_the_pack", shamans.id, home, CastOrder.GOLD, 3), [], "", ""],
		[CastOrder.new("bloodrot", shamans.id, near, CastOrder.GOLD, 2), [], "no_size", "Only Call the Pack takes a size"],
		[CastOrder.new("bloodrot", shamans.id, near, CastOrder.BLOOD), [], "no_tithe", "Paying in blood needs the mandate Tithe of Blood."],
		[CastOrder.new("bloodrot", shamans.id, near, "silver"), [], "bad_pay", "paid in gold, or in blood"],
		[CastOrder.new("bloodrot", shamans.id, "atlantis"), [], "unknown_target", "'atlantis' is not a province on this map."],
	]
	for row in rows:
		var check := _check(s, CLANS, row[0], row[1])
		assert_eq(_code(check), row[2], "%s: %s" % [row[0].describe(), check])
		if not String(row[3]).is_empty():
			assert_true(String(check.get("reason", "")).contains(row[3]), "%s: %s" % [row[3], check.get("reason", "")])
		for word in [check.get("reason", "")]:
			assert_false(String(word).contains("_") and _code(check) != "unknown_ritual", "no raw id: %s" % word)
	# Far Sight needs no research, and any caster casts it, a mage or a ruler with magic.
	assert_eq(_check(s, CLANS, CastOrder.new("far_sight", shamans.id, far)), {})
	assert_eq(_check(s, CLANS, CastOrder.new("far_sight", fang.id, far)), {})
	assert_eq(_code(_check(s, CLANS, CastOrder.new("far_sight", bare.id, far))), "no_caster")
	assert_eq(_code(_check(s, CLANS, CastOrder.new("far_sight", shamans.id, _at(s, home, 4)))), "out_of_range")


func test_the_target_rules_of_every_ritual() -> void:
	var crown_nodes := ["sunlance", "dawn_blessing", "shield_of_law", "sanctum_ward", "crown_drillyard", "crown_charters", "crown_oath_forge", "bastion"]
	var s := _game({CROWN: crown_nodes, CLANS: ["briar_snare", "call_the_pack", "bloodbolt", "bloodrot", "beasts_boar_hide", "beasts_raiding",
		"beasts_oath_grove", "wake_the_greenwrath"]})
	var adepts := _field_army(s, CROWN)
	var home := adepts.location
	var mine := _at(s, home, 1)
	s.find_province(mine).owner = CROWN
	# Dawn Blessing needs an army of yours there; Sanctum Ward only your province.
	assert_eq(_code(_check(s, CROWN, CastOrder.new("dawn_blessing", adepts.id, mine))), "no_army_there")
	assert_eq(_check(s, CROWN, CastOrder.new("dawn_blessing", adepts.id, home)), {})
	assert_eq(_check(s, CROWN, CastOrder.new("sanctum_ward", adepts.id, mine)), {})
	assert_eq(_code(_check(s, CROWN, CastOrder.new("sanctum_ward", adepts.id, _at(s, home, 2)))), "not_own")
	# Bastion: within 1, no fort, at most 2 ever.
	assert_eq(_code(_check(s, CROWN, CastOrder.new("bastion", adepts.id, home))), "has_fort", "the capital has a fort")
	assert_eq(_check(s, CROWN, CastOrder.new("bastion", adepts.id, mine)), {})
	s.find_faction(CROWN).bastions = ["westwatch", "stonegate"]  # two forts raised before, wherever they are now
	var cap := _check(s, CROWN, CastOrder.new("bastion", adepts.id, mine))
	assert_eq(_code(cap), "bastion_cap")
	assert_true(String(cap.reason).contains("You have raised %d Bastion forts" % MagicData.BASTION_CAP), cap.reason)
	# The ritual targets list matches the checks.
	s.find_faction(CROWN).bastions = []
	for pid in MagicRules.ritual_targets(s, CROWN, "sanctum_ward", adepts.id):
		assert_eq(s.find_province(pid).owner, CROWN)
		assert_true(int(MagicRules.distances(s, home)[pid]) <= int(MagicData.SPELLS.sanctum_ward.range))
	# Wake the Greenwrath only in a forest, one at a time; Call the Pack one pack at a time.
	var shamans := _field_army(s, CLANS)
	assert_eq(_code(_check(s, CLANS, CastOrder.new("wake_the_greenwrath", shamans.id, shamans.location))), "not_forest")
	var forest := ""
	for p in s.provinces:
		if p.terrain == "forest" and forest.is_empty():
			forest = p.id
	shamans.location = forest
	assert_eq(_check(s, CLANS, CastOrder.new("wake_the_greenwrath", shamans.id, forest)), {})
	var pack := Army.new()
	pack.id = s.new_army_id(CLANS)
	pack.owner = CLANS
	pack.location = s.find_faction(CLANS).capital
	var wolf := Unit.new(MagicRules.summon_type("thornwolves"), CLANS)
	wolf.until = 4
	pack.units.append(wolf)
	var wrath := Unit.new(MagicRules.summon_type("greenwrath"), CLANS)
	var grove := Army.new()
	grove.id = s.new_army_id(CLANS)
	grove.owner = CLANS
	grove.location = forest
	grove.units.append(wrath)
	s.armies.append_array([pack, grove])
	assert_eq(_code(_check(s, CLANS, CastOrder.new("call_the_pack", shamans.id, forest, CastOrder.GOLD, 3))), "pack_out")
	assert_eq(_code(_check(s, CLANS, CastOrder.new("wake_the_greenwrath", shamans.id, forest))), "summon_awake")


# --- mastery (§3.2) ------------------------------------------------------------------------------------

func test_mastery_for_every_caster_at_every_rank_in_every_school_with_the_cap() -> void:
	var cap := int(MagicData.MASTERY.cap)
	for ruler_id in MagicData.RULER_MAGIC:
		var fid := String(RulerRules.ruler_data(ruler_id).faction)
		var base := GameState.with_magic(7, {fid: {"ruler": ruler_id, "mandates": []}})
		var own: Array = MagicData.RULER_MAGIC[ruler_id].schools
		for school in MagicRules.schools(fid):
			var aligned := String(MagicData.SCHOOLS[school].aligned_branch)
			var path: Array = []
			for n in PathData.PATHS[fid].nodes:
				if n.kind == PathData.TIER1:
					path.append(n.id)
			path.append(String(PathData.BRANCHES[aligned].oath))
			path.append(String(PathData.BRANCHES[aligned].transformation))
			var school_nodes: Array = MagicData.SCHOOLS[school].nodes.slice(0, 3)  # tier I, tier II, mastery
			for setup in [[], path, school_nodes, path + school_nodes]:
				var s := AscensionRules.with_nodes(base, fid, setup)
				var extra := (1 if setup.has(path.back()) else 0) + (1 if setup.has(school_nodes.back()) else 0)
				var mage := MagicRules.mastery_bonus(s, fid, school, MagicRules.MAGE)
				assert_eq(int(mage.value), mini(extra, cap), "a mage in %s with %s" % [school, setup])
				assert_eq(_sum(mage.parts), int(mage.value), "the mage's parts sum")
				for kept in range(0, RulerData.POWER_POOL + 1):
					s.find_faction(fid).kept_power = kept
					var rank := RulerRules.ability_rank(kept)
					var raw := (rank - 1 if own.has(school) else 0) + extra
					var b := MagicRules.mastery_bonus(s, fid, school, MagicRules.RULER)
					assert_eq(int(b.value), mini(raw, cap), "%s, kept %d (rank %d), %s, %s" % [ruler_id, kept, rank, school, setup])
					assert_eq(bool(b.capped), raw > cap)
					assert_eq(_sum(b.parts), int(b.value), "the parts sum to the bonus, the cap included")
					if raw > cap:
						assert_true(b.parts.any(func(p): return p.key == MagicRules.PART_CAP), "the cap is shown")
						var bd := Breakdown.mastery(s, fid, school, MagicRules.RULER)
						assert_eq(Breakdown.sum_of_lines(bd), int(bd.total))
						assert_eq(int(bd.total), cap)
	# Far Sight's common magic has no mastery; a game without magic has none.
	assert_eq(int(MagicRules.mastery_bonus(_game(), CROWN, MagicData.COMMON).value), 0)
	assert_eq(int(MagicRules.mastery_bonus(GameState.with_paths(7), CROWN, "sun").value), 0)


func test_mastery_scales_exactly_its_two_numbers() -> void:
	var game := _game()
	for sid in MagicData.SPELLS:
		var sp: Dictionary = MagicData.SPELLS[sid]
		var per: Dictionary = sp.per_bonus
		for bonus in range(0, int(MagicData.MASTERY.cap) + 1):
			var n := MagicRules.spell_numbers(sid, bonus)
			assert_eq(int(n.value), int(sp.get("value", 0)) + int(per.get("value", 0)) * bonus, "%s value at +%d" % [sid, bonus])
			assert_eq(int(n.count), int(sp.get("count", 0)) + int(per.get("count", 0)) * bonus, "%s count at +%d" % [sid, bonus])
		if sp.battle == false and String(sp.get("summon", "")) != "thornwolves":
			assert_eq(int(MagicRules.price(game, CROWN, sid).gold), int(sp.cost), "%s: mastery never changes a price" % sid)
	assert_eq(int(MagicRules.spell_numbers("briar_snare", 0, true).count), int(MagicData.SPELLS.briar_snare.forest_count), "Briar Snare in a forest")
	# The Ever-Regent's Sunlance with the Celestial Host: "Sunlance 6 = 4 + mastery 2" at rank 2.
	var s := AscensionRules.with_nodes(_game(), CROWN, ["crown_drillyard", "crown_charters", "crown_oath_dawn", "crown_celestial_host"])
	s.find_faction(CROWN).kept_power = 3
	var bd := Breakdown.spell_number(s, CROWN, "sunlance", MagicRules.RULER)
	assert_eq(int(bd.total), int(MagicData.SPELLS.sunlance.value) + 2)
	assert_eq(Breakdown.sum_of_lines(bd), int(bd.total))
	assert_eq(MagicRules.mastery_text(MagicRules.mastery_bonus(s, CROWN, "sun", MagicRules.RULER)),
		"Mastery in Sun +2: ability rank 2 (+1) and Celestial Host (+1)")


# --- Tithe of Blood (§7.1) -------------------------------------------------------------------------------

func test_the_blood_plan_takes_one_soldier_at_a_time() -> void:
	# §7.1's example: Call the Pack with 3 wolves (15), from 6 Tuskers at 14 hp: the first gives 13 (down to 1), the
	# second 2 (down to 12).
	var s := _game({CLANS: ["briar_snare", "call_the_pack"]}, {CLANS: {"ruler": "fang_chieftain", "mandates": ["tithe_of_blood"]}})
	var army := _field_army(s, CLANS)
	var tuskers := TurnResolver.recruitable_type(s.find_faction(CLANS), "tuskers")
	army.units = []
	for i in 6:
		var u := Unit.new(tuskers, CLANS)
		u.current_hp = 14
		army.units.append(u)
	var price := int(MagicRules.price(s, CLANS, "call_the_pack", 3).gold)
	assert_eq(price, 3 * int(MagicData.SPELLS.call_the_pack.cost))
	var plan := MagicRules.blood_plan(s, army.id, price)
	assert_true(plan.ok)
	assert_eq(plan.gives.map(func(g): return [g.index, g.from, g.to, g.gave]), [[0, 14, 1, 13], [1, 14, 12, 2]])
	assert_eq(int(plan.available), 6 * 13)
	# Ties go in army order; the healthiest first; commanders, rulers and summoned creatures never give.
	army.units[3].current_hp = 9
	army.units[0].current_hp = 5
	var mixed := MagicRules.blood_plan(s, army.id, 20)
	assert_eq(mixed.gives.map(func(g): return g.index), [1, 2], "the two healthiest, in army order")
	army.commander = Unit.new(s.find_faction(CLANS).commander_type, CLANS)
	assert_false(MagicRules.blood_plan(s, army.id, 1000).ok, "short of blood: the commander never gives")
	# The cast check: blood needs Tithe of Blood, a mage's army (a ruler pays gold) and enough hp.
	var mage := TurnResolver.recruitable_type(s.find_faction(CLANS), "shamans")
	army.units.append(Unit.new(mage, CLANS))
	assert_eq(_check(s, CLANS, CastOrder.new("call_the_pack", army.id, army.location, CastOrder.BLOOD, 3)), {})
	for u in army.units:
		u.current_hp = 2
	var short := _check(s, CLANS, CastOrder.new("call_the_pack", army.id, army.location, CastOrder.BLOOD, 3))
	assert_eq(_code(short), "short_of_blood")
	assert_true(String(short.reason).contains("can give only 7"), short.reason)
	var fang := _ruler_army(s, CLANS)
	s = AscensionRules.with_nodes(s, CLANS, ["bloodbolt", "bloodrot"])
	assert_eq(_code(_check(s, CLANS, CastOrder.new("bloodrot", fang.id, _at(s, fang.location, 2), CastOrder.BLOOD))), "ruler_pays_gold")


func test_tithe_of_blood_and_feast_of_victory_exclude_each_other() -> void:
	var both := {"ruler": "fang_chieftain", "mandates": ["tithe_of_blood", "feast_of_victory"]}
	var why := "Tithe of Blood can't be held with Feast of Victory: blood given is not taken back."
	assert_true(RulerRules.build_errors(CLANS, both).has(why), str(RulerRules.build_errors(CLANS, both)))
	var errors := []
	assert_eq(GameState.with_magic(7, {CLANS: both}, errors), null, "a build with both is refused")
	assert_true(errors.has(why), str(errors))
	assert_true(RulerRules.build_errors(CLANS, {"ruler": "fang_chieftain", "mandates": ["tithe_of_blood"]}).is_empty())
	assert_eq(RulerRules.build_errors(CROWN, {"ruler": "ever_regent", "mandates": ["tithe_of_blood"]}).size(), 1, "Clans only")
	# By sacrifice, either way round.
	var feast := GameState.with_magic(7, {CLANS: {"ruler": "fang_chieftain", "mandates": ["feast_of_victory"]}})
	var check := RulerRules.sacrifice_check(feast, CLANS, "tithe_of_blood")
	assert_eq(_code(check), "excluded_mandate")
	assert_true(String(check.reason).begins_with(why), check.reason)
	var tithe := GameState.with_magic(7, {CLANS: {"ruler": "fang_chieftain", "mandates": ["tithe_of_blood"]}})
	assert_true(tithe.find_faction(CLANS).mandates.has("tithe_of_blood"), "a magic game starts with Tithe of Blood")
	assert_eq(int(tithe.find_faction(CLANS).kept_power), RulerData.POWER_POOL - int(MandateData.MAGIC_MANDATES[0].cost))
	assert_eq(_code(RulerRules.sacrifice_check(tithe, CLANS, "feast_of_victory")), "excluded_mandate")
	assert_true(RulerRules.available_mandates(CLANS, tithe).has("tithe_of_blood"), "on the sacrifice list in a magic game")
	assert_eq(RulerRules.sacrifice_cost("tithe_of_blood"), int(MandateData.MAGIC_MANDATES[0].cost) + MandateData.SACRIFICE_PREMIUM)
	var plain := GameState.with_magic(7)
	assert_eq(RulerRules.sacrifice_check(plain, CLANS, "tithe_of_blood"), {}, "bought by sacrifice in a magic game")
	# A state holding both doesn't load.
	tithe.find_faction(CLANS).mandates.append("feast_of_victory")
	var bad := []
	assert_false(tithe.validate(bad))
	assert_true(bad.any(func(e): return String(e).contains("which can't be held together")), str(bad))


# --- the pin and the running budget (§6.1) -------------------------------------------------------------

func test_a_queued_cast_drops_its_armys_move_whichever_came_first() -> void:
	var s := _game({CLANS: ["bloodbolt", "bloodrot"]})
	var army := _field_army(s, CLANS)
	var to: String = s.find_province(army.location).neighbors[0]
	var target := _at(s, army.location, 2)
	var move := MoveOrder.new(army.id, to)
	var cast := CastOrder.new("bloodrot", army.id, target)
	# The move first: queuing the cast removes it, with its reason.
	var book := OrderBook.new()
	assert_eq(book.submit(s, CLANS, move), "")
	assert_eq(book.submit(s, CLANS, cast), "")
	assert_eq(book.orders_for(CLANS), [cast], "only the cast is left")
	var dropped := book.last_dropped()
	assert_eq(dropped.size(), 1)
	assert_eq(String(dropped[0].text), "Move to %s removed: your army at %s is casting Bloodrot this turn, so it holds." % [
		s.find_province(to).name, s.find_province(army.location).name])
	# The cast first: the move is refused.
	var book2 := OrderBook.new()
	assert_eq(book2.submit(s, CLANS, cast), "")
	var why := book2.submit(s, CLANS, move)
	assert_eq(why, "Your army at %s is casting Bloodrot this turn, so it holds. It can't move this turn." % s.find_province(army.location).name)
	assert_eq(book2.orders_for(CLANS), [cast])
	# A re-check keeps the same answer, whatever the order in the list.
	for orders in [[move, cast], [cast, move]]:
		var r := OrderBook.recheck(s, CLANS, orders)
		assert_eq(r.kept, [cast])
		assert_eq(r.dropped.size(), 1)
		assert_eq(String(r.dropped[0].code), "pinned")
	assert_eq(MagicRules.pinned_armies(s, CLANS, [move, cast]), {army.id: "bloodrot"})
	# Another army's move is untouched, and an illegal cast pins nothing.
	var fang := _ruler_army(s, CLANS)
	var other := MoveOrder.new(fang.id, s.find_province(fang.location).neighbors[0])
	assert_eq(OrderBook.recheck(s, CLANS, [other, cast]).kept, [other, cast])
	assert_eq(MagicRules.pinned_armies(s, CLANS, [CastOrder.new("bloodrot", army.id, army.location)]), {})


func test_recruits_and_rituals_share_one_budget() -> void:
	var s := _game({CLANS: ["bloodbolt", "bloodrot"]})
	var army := _field_army(s, CLANS)
	var target := _at(s, army.location, 2)
	var tuskers := TurnResolver.recruit_cost(s, CLANS, "tuskers")
	var rot := int(MagicRules.price(s, CLANS, "bloodrot").gold)
	s.find_faction(CLANS).gold = rot + tuskers + 1  # one ritual and one recruit fit, not a second recruit
	var cast := CastOrder.new("bloodrot", army.id, target)
	var r1 := RecruitOrder.new("tuskers")
	var r2 := RecruitOrder.new("tuskers")
	# The cast first: the first recruit fits, the second doesn't.
	var book := OrderBook.new()
	assert_eq(book.submit(s, CLANS, cast), "")
	assert_eq(book.submit(s, CLANS, r1), "")
	var no := book.submit(s, CLANS, r2)
	assert_true(no.contains("but you only have 1 gold left"), no)
	# The recruits first: the cast no longer fits, and says why.
	var book2 := OrderBook.new()
	assert_eq(book2.submit(s, CLANS, r1), "")
	assert_eq(book2.submit(s, CLANS, r2), "")
	var why := book2.submit(s, CLANS, cast)
	assert_eq(why, "Bloodrot costs %d gold, but after your queued recruits (%d) you have %d gold left." % [rot, 2 * tuskers, rot + tuskers + 1 - 2 * tuskers])
	# A re-check keeps orders in the order given.
	assert_eq(OrderBook.recheck(s, CLANS, [cast, r1, r2]).kept, [cast, r1])
	assert_eq(OrderBook.recheck(s, CLANS, [r1, r2, cast]).kept, [r1, r2])
	assert_eq(MagicRules.queued_gold(s, CLANS, [cast, r1]), rot)
	# Blood-paid rituals take no gold.
	var tithe := _game({CLANS: ["bloodbolt", "bloodrot"]}, {CLANS: {"ruler": "fang_chieftain", "mandates": ["tithe_of_blood"]}})
	var t_army := _field_army(tithe, CLANS)
	tithe.find_faction(CLANS).gold = 0
	var blood := CastOrder.new("bloodrot", t_army.id, _at(tithe, t_army.location, 2), CastOrder.BLOOD)
	assert_eq(OrderBook.check_order(tithe, CLANS, blood, []), {})
	assert_eq(MagicRules.queued_gold(tithe, CLANS, [blood]), 0)


# --- the spellbook (§5.1) ----------------------------------------------------------------------------------

func test_the_spellbook_order_is_checked_set_and_saved() -> void:
	var s := _game()
	assert_eq(MagicRules.spellbook(s, CROWN), {"order": MagicData.SPELLBOOK[CROWN], "off": []}, "the default")
	var cases := [
		[["sunlance", "sunburst"], [], "spell_missing", "leaves out Shield of Law"],
		[["sunlance", "sunlance", "sunburst", "shield_of_law"], [], "spell_twice", "Sunlance is in the spellbook twice."],
		[["sunlance", "sunburst", "shield_of_law", "bloodbolt"], [], "unknown_spell", "Bloodbolt is not one of your battle spells"],
		[["sunlance", "sunburst", "shield_of_law", "dawn_blessing"], [], "unknown_spell", "Dawn Blessing is a ritual"],
		[["sunlance", "sunburst", "shield_of_law"], ["bloodbolt"], "unknown_spell", "Only spells in the spellbook can be switched off"],
		[["sunlance", "sunburst", "shield_of_law"], ["sunburst"], "", ""],
	]
	for c in cases:
		var check := MagicRules.check_spellbook(s, CROWN, SpellbookOrder.new(c[0], c[1]))
		assert_eq(_code(check), c[2], str(c))
		assert_true(String(check.get("reason", "")).contains(c[3]), "%s: %s" % [c[3], check.get("reason", "")])
	# One per turn in the book: a new one replaces it.
	var book := OrderBook.new()
	assert_eq(book.submit(s, CROWN, SpellbookOrder.new(["sunlance", "sunburst", "shield_of_law"], ["sunburst"])), "")
	assert_eq(book.submit(s, CROWN, SpellbookOrder.new(["shield_of_law", "sunlance", "sunburst"])), "")
	assert_eq(book.orders_for(CROWN).size(), 1)
	assert_eq(String(book.last_dropped()[0].text), "Battle spellbook replaced: you set it again.")
	# The orders phase applies it; it persists and round-trips; the default saves as {}.
	var r := TurnResolver.resolve(s, {CROWN: [SpellbookOrder.new(["sunlance", "sunburst", "shield_of_law"], ["sunburst"])]}, 1)
	assert_eq(r.new_state.find_faction(CROWN).spellbook, {"order": ["sunlance", "sunburst", "shield_of_law"], "off": ["sunburst"]})
	var again := TurnResolver.resolve(r.new_state, {}, 2)
	assert_eq(MagicRules.spellbook(again.new_state, CROWN).off, ["sunburst"], "it stays")
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(again.new_state.to_dict())))
	assert_eq(loaded.find_faction(CROWN).spellbook, again.new_state.find_faction(CROWN).spellbook)
	var back := TurnResolver.resolve(again.new_state, {CROWN: [SpellbookOrder.new(MagicData.SPELLBOOK[CROWN])]}, 3)
	assert_eq(back.new_state.find_faction(CROWN).spellbook, {}, "the default again saves as the default")
	# A second spellbook order in the same turn is rejected.
	var two := TurnResolver.resolve(s, {CROWN: [SpellbookOrder.new(MagicData.SPELLBOOK[CROWN]), SpellbookOrder.new(MagicData.SPELLBOOK[CROWN])]}, 1)
	assert_eq(two.events.filter(func(e): return e.type == "order_rejected").map(func(e): return e.cause), ["second_spellbook"])
	# The battle spells each caster casts: a mage what is researched; the Ever-Regent his Sunlance from turn 1.
	assert_eq(MagicRules.battle_spells(s, CROWN, MagicRules.MAGE), [])
	assert_eq(MagicRules.battle_spells(s, CROWN, MagicRules.RULER), ["sunlance"])
	var learned := AscensionRules.with_nodes(s, CROWN, ["shield_of_law"])
	assert_eq(MagicRules.battle_spells(learned, CROWN, MagicRules.RULER), ["sunlance", "shield_of_law"])
	assert_eq(MagicRules.battle_spells(learned, CROWN, MagicRules.MAGE), ["shield_of_law"])
	assert_eq(MagicRules.battle_spells(s, CLANS, MagicRules.RULER), [], "the Ninth Fang casts no battle spell")


# --- casters, healing and sight ------------------------------------------------------------------------------

func test_casters_healing_under_a_curse_and_far_sight() -> void:
	var s := _game()
	var crown := MagicRules.casters(s, _field_army(s, CROWN))
	assert_eq(crown.map(func(c): return c.kind), [MagicRules.MAGE])
	assert_eq(MagicRules.casters(s, _ruler_army(s, CROWN)).map(func(c): return [c.kind, c.battle]), [[MagicRules.RULER, true]], "the Ever-Regent")
	assert_eq(MagicRules.casters(s, _ruler_army(s, CLANS)).map(func(c): return [c.kind, c.battle]), [[MagicRules.RULER, false]], "the Ninth Fang")
	var corvane := GameState.with_magic(7, {CROWN: "warrior_king"})
	assert_eq(MagicRules.casters(corvane, RulerRules.ruler_army(corvane, CROWN)), [], "King Corvane casts nothing")
	# Bloodrot on Crownkeep: the Crown can't heal there; the Clans can, and every other province is clear.
	var home := s.find_faction(CROWN).capital
	s.find_faction(CLANS).enchant_counter = 1
	s.find_faction(CROWN).enchant_counter = 1
	s.enchantments = [
		{"id": "beasts-e1", "ritual": "bloodrot", "faction": CLANS, "kind": "curse", "province": home, "armies": [],
			"cast_turn": 1, "until_turn": 3, "bonus": 0, "ending": false},
		{"id": "kingdom-e1", "ritual": "far_sight", "faction": CROWN, "kind": "sight", "province": "wildmoor", "armies": [],
			"cast_turn": 1, "until_turn": 3, "bonus": 0, "ending": false},
	]
	assert_true(s.validate([]))
	assert_false(MagicRules.can_heal(s, CROWN, home), "cursed")
	assert_true(MagicRules.can_heal(s, CLANS, home), "a curse never hurts its caster's faction")
	assert_true(MagicRules.can_heal(s, CROWN, "wildmoor"))
	assert_true(MagicRules.can_heal(s, CROWN, ""), "a border battle is in no province")
	assert_eq(MagicRules.vision_grants(s, CROWN), ["wildmoor"], "Far Sight grants sight")
	assert_eq(MagicRules.vision_grants(s, CLANS), [])


func test_the_ritual_price_and_research_sold_breakdowns() -> void:
	var s := _game({}, {CLANS: {"ruler": "fang_chieftain", "mandates": ["tithe_of_blood"]}})
	var bd := Breakdown.ritual_price(s, CLANS, "bloodrot")
	assert_eq(int(bd.total), int(MagicData.SPELLS.bloodrot.cost))
	assert_eq(Breakdown.sum_of_lines(bd), int(bd.total))
	assert_true(String(bd.description).contains("Tithe of Blood"), bd.description)
	assert_eq(int(Breakdown.ritual_price(s, CLANS, "call_the_pack", 4).total), 4 * int(MagicData.SPELLS.call_the_pack.cost))
	s.find_faction(CLANS).research_points = 11
	var sold := Breakdown.research_sold(s, CLANS)
	assert_eq(Breakdown.sum_of_lines(sold), int(sold.total))
	assert_eq(int(sold.gold), floori(11.0 / MagicData.RESEARCH_SOLD))
	assert_eq(MagicRules.research_sold(11), {"gold": 5, "research": 10, "left": 1})
	assert_eq(MagicRules.sold_text({"gold": 5, "research": 10, "left": 1}),
		"Nothing is left to research: your scholars sold their learning for 5 gold (10 research). 1 research carried to next turn.")


func _sum(parts: Array) -> int:
	var total := 0
	for p in parts:
		total += int(p.value)
	return total
