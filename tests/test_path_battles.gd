extends "res://tests/test_case.gd"
## M4-3 (#68), design/M4_ASCENSION.md §4.7, §4.9, §4.10, §9.6: battles with paths. Fixed-seed battles pin
## each new trait (Wings, Iron Hide, Rooted, Lifedrinker), path parts and path morale in battle (the M4-1
## gap: they worked only for a faction with a mandate), Dread Lands, Red Harvest, the "why" and the report's
## people, the battle log additions (validate, verify_draws and cross_check pass on every path battle), the
## odds and the codex. Expected numbers come from data and the resolver's constants, never typed in.

const PB := preload("res://tests/path_battle_fixtures.gd")
const CROWN := "kingdom"
const CLANS := "beasts"
const HOST := ["crown_drillyard", "crown_charters", "crown_oath_dawn", "crown_celestial_host"]
const IRON := ["crown_drillyard", "crown_charters", "crown_oath_forge", "crown_living_iron"]
const WILD := ["beasts_boar_hide", "beasts_raiding", "beasts_oath_grove", "beasts_thorn_wild"]
const PACT := ["beasts_boar_hide", "beasts_raiding", "beasts_oath_blood", "beasts_blood_pact"]


func _checks(r: Dictionary, what: String) -> void:
	assert_eq(BattleLog.validate(r.log), [], "%s: validate" % what)
	assert_eq(BattleLog.verify_draws(r.log), [], "%s: verify_draws" % what)
	assert_eq(BattleLog.cross_check(r.log, r.result.report), [], "%s: cross_check" % what)


func _events(battle_log: Dictionary, t: String) -> Array:
	return battle_log.events.filter(func(e): return e.t == t)


## A fresh battle of `fid_a`'s `ids_a` against `fid_b`'s `ids_b` in `where`, with `nodes` researched by
## `node_fid`, fought on `seed_value`.
func _battle(node_fid: String, nodes: Array, fid_a: String, ids_a: Array, fid_b: String, ids_b: Array, where: String,
		defender: String, seed_value: int, kind := "province") -> Dictionary:
	var s := PB.with_nodes(PB.game(), node_fid, nodes)
	var a := PB.army(s, fid_a, fid_a + "-1", where.get_slice("|", 0), ids_a)
	var b := PB.army(s, fid_b, fid_b + "-2", where.get_slice("|", 0), ids_b)
	var r := PB.fight(s, [a, b], where, defender, seed_value, kind)
	r["state"] = s
	return r


## The first seed in 1..40 on which the battle's top "why" is `factor_id`, won by `winner`: {} if none.
func _top_why(node_fid: String, nodes: Array, fid_a: String, ids_a: Array, fid_b: String, ids_b: Array, where: String,
		factor_id: String, winner: String) -> Dictionary:
	for sd in range(1, 41):
		var r := _battle(node_fid, nodes, fid_a, ids_a, fid_b, ids_b, where, "", sd)
		var factors: Array = r.result.report.factors
		if not factors.is_empty() and factors[0].id == factor_id and r.result.winner == winner:
			r["seed"] = sd
			return r
	return {}


# --- Wings ---------------------------------------------------------------------------------------------

func test_wings_attacks_a_standing_commander_first_and_any_rank_otherwise() -> void:
	var s := PB.game()
	var clans := PB.army(s, CLANS, "beasts-1", "rivermarch", ["seraphs", "tuskers"])
	var crown := PB.army(s, CROWN, "kingdom-2", "rivermarch", ["spearmen", "spearmen", "spearmen", "crossbowmen"])
	var sides := AutoBattleResolver._build_sides([{"faction": CLANS, "armies": [clans]}, {"faction": CROWN, "armies": [crown]}], "", s)
	var seraph: Dictionary = sides[0].fighters[0]
	var tusker: Dictionary = sides[0].fighters[1]
	assert_eq(seraph.trait, AutoBattleResolver.WINGS)
	var winged := AutoBattleResolver._targets(sides, 0, [0, 1], seraph)
	var plain := AutoBattleResolver._targets(sides, 0, [0, 1], tusker)
	assert_eq(winged.size(), 4, "with no commander, Wings reaches every rank, the shielded Crossbowmen too")
	assert_true(winged.any(func(f): return f.tier == 1), "the second rank")
	assert_eq(plain.size(), 3, "an ordinary attacker reaches only the front rank while it shields the second")
	# With a commander standing behind the line, Wings attacks only the commander.
	var led := PB.army(s, CROWN, "kingdom-3", "rivermarch", ["spearmen", "spearmen", "crossbowmen", "knight_captain"])
	sides = AutoBattleResolver._build_sides([{"faction": CLANS, "armies": [clans]}, {"faction": CROWN, "armies": [led]}], "", s)
	winged = AutoBattleResolver._targets(sides, 0, [0, 1], sides[0].fighters[0])
	assert_eq(winged.map(func(f): return f.name), ["Knight Captain"], "a standing commander first")
	assert_eq(AutoBattleResolver._targets(sides, 0, [0, 1], sides[0].fighters[1]).size(), 2, "ordinary reach is unchanged")
	# In a fought battle (the log): while the Warchief stands every Seraphs attack goes at it; after, any rank.
	var after := 0
	for sd in [1, 2, 3, 4, 5, 6]:
		var r := _battle(CROWN, HOST, CROWN, ["seraphs", "seraphs", "seraphs"], CLANS, ["tuskers", "tuskers", "warchief"], "rivermarch", "", sd)
		var lg: Dictionary = r.log
		var tl := BattleTimeline.build(lg)
		var seraphs := PB.fighters_of(lg, "seraphs")
		var chief: int = PB.fighters_of(lg, "warchief")[0]
		for i in lg.events.size():
			var e: Dictionary = lg.events[i]
			if e.t != "attack" or not seraphs.has(int(e.by)):
				continue
			var chief_up: bool = tl.state_at(i).fighters[chief].alive
			if chief_up:
				assert_eq(int(e.to), chief, "seed %d: the Seraphs strike the standing Warchief" % sd)
			else:
				after += 1
		_checks(r, "Wings seed %d" % sd)
	assert_true(after > 0, "once the Warchief has fallen, the Seraphs attack the rest")


# --- Iron Hide -----------------------------------------------------------------------------------------

func test_iron_hide_takes_one_off_every_hit_and_never_below_one() -> void:
	var hide := {"trait": AutoBattleResolver.IRON_HIDE}
	var other := {"trait": AutoBattleResolver.CHARGE}
	for raw in range(1, 8):
		assert_eq(AutoBattleResolver._dealt(hide, raw), maxi(AutoBattleResolver.MIN_DAMAGE, raw - AutoBattleResolver.IRON_HIDE_DAMAGE), "raw %d" % raw)
		assert_eq(AutoBattleResolver._dealt(other, raw), raw, "no Iron Hide, no change")
	# Fangthrowers' hits on the Iron Colossus: every one 1 less, as a named damage part.
	var r := _battle(CROWN, IRON, CROWN, ["iron_colossus"], CLANS, ["fangthrowers", "fangthrowers", "fangthrowers"], "rivermarch", "", 2)
	var colossus: int = PB.fighters_of(r.log, "iron_colossus")[0]
	var on_it: Array = _events(r.log, "attack").filter(func(e): return int(e.to) == colossus)
	assert_false(on_it.is_empty())
	for e in on_it:
		var raw := AutoBattleResolver.damage(int(e.attack.value), int(e.defense.value))
		assert_eq(int(e.damage), raw - AutoBattleResolver.IRON_HIDE_DAMAGE)
		assert_eq(int(e.bonus[AutoBattleResolver.IRON_HIDE]), -AutoBattleResolver.IRON_HIDE_DAMAGE)
	var hits: int = on_it.filter(func(e): return e.hit).size()
	var crown_side: Dictionary = r.result.report.sides.filter(func(x): return x.faction == CROWN)[0]
	assert_eq(int(crown_side.triggers[AutoBattleResolver.IRON_HIDE]), on_it.size(), "counted on every attack it turned")
	var why: Array = r.result.report.all_factors.filter(func(f): return f.id == AutoBattleResolver.IRON_HIDE)
	assert_true(String(why[0].text).contains("from each of %d hits" % hits), why[0].text)
	_checks(r, "Iron Hide")
	# A hit already at the minimum stays at it: a weak attacker (attack 3) deals 1 a hit, no part.
	var s := PB.with_nodes(PB.game(), CROWN, IRON)
	var big := PB.army(s, CROWN, "kingdom-1", "rivermarch", ["iron_colossus"])
	var weak := UnitType.from_dict({"id": "militia", "name": "Militia", "hp": 8, "attack": 3, "defense": 4, "morale": 6, "cost": 5})
	var mob := PB.army(s, CLANS, "beasts-2", "rivermarch", [])
	for i in 4:
		mob.units.append(Unit.new(weak, CLANS))
	var w := PB.fight(s, [big, mob], "rivermarch", "", 3)
	var big_id: int = PB.fighters_of(w.log, "iron_colossus")[0]
	var weak_hits: Array = _events(w.log, "attack").filter(func(e): return int(e.to) == big_id and e.hit)
	assert_false(weak_hits.is_empty(), "the militia landed hits")
	for e in weak_hits:
		assert_eq(int(e.damage), AutoBattleResolver.MIN_DAMAGE, "never below 1")
		assert_false(e.bonus.has(AutoBattleResolver.IRON_HIDE), "nothing to take off")
	_checks(w, "Iron Hide at the minimum")


# --- Rooted --------------------------------------------------------------------------------------------

func test_rooted_only_in_forest_province_battles() -> void:
	var cases := [
		["greenglade", "", "province", true, 0],  # forest, both arrived
		["greenglade", CROWN, "province", true, 0],  # forest, the Crown holds it: rooted anyway
		["greenglade", CLANS, "province", true, AutoBattleResolver.TERRAIN.forest.defense],  # forest, theirs: terrain too
		["rivermarch", "", "province", false, 0],  # plains
		["highcrag", CLANS, "province", false, AutoBattleResolver.TERRAIN.hills.defense],  # hills
		["greenglade|thornvale", "", "border", false, 0],  # a border between two forests
	]
	for c in cases:
		var r := _battle(CLANS, WILD, CLANS, ["briarwardens"], CROWN, ["spearmen", "crossbowmen"], c[0], c[1], 5, c[2])
		var warden: int = PB.fighters_of(r.log, "briarwardens")[0]
		var on_it: Array = _events(r.log, "attack").filter(func(e): return int(e.to) == warden)
		assert_false(on_it.is_empty(), "%s: attacked" % c[0])
		var base := int(PathData.NEW_UNITS.briarwardens.defense)
		for e in on_it:
			assert_eq(e.defense.parts.has(AutoBattleResolver.ROOTED), c[3], "%s %s: Rooted" % [c[0], c[2]])
			var want: int = base + int(c[4]) + (AutoBattleResolver.ROOTED_DEFENSE if c[3] else 0)
			assert_eq(int(e.defense.value), want, "%s: defense %d" % [c[0], want])
		_checks(r, "Rooted %s" % c[0])


# --- Lifedrinker ---------------------------------------------------------------------------------------

func test_lifedrinker_heals_only_if_standing_after_damage() -> void:
	var heals := 0
	var fell_after_hitting := 0
	for sd in range(1, 31):
		var r := _battle(CLANS, PACT, CLANS, ["bloodsworn", "bloodsworn"], CROWN, ["knights", "spearmen", "spearmen"], "rivermarch", "", sd)
		var lg: Dictionary = r.log
		var drinkers := PB.fighters_of(lg, "bloodsworn")
		var max_hp := int(PathData.NEW_UNITS.bloodsworn.hp)
		for n in range(1, int(r.result.report.rounds_fought) + 1):
			var idx := []
			for i in lg.events.size():
				if lg.events[i].get("n", -1) == n:
					idx.append(i)
			for fid in drinkers:
				var dealt := 0
				for i in idx:
					var e: Dictionary = lg.events[i]
					if e.t == "attack" and int(e.by) == fid and e.hit:
						dealt += int(e.damage)
				var died: bool = idx.any(func(i): return lg.events[i].t == "death" and int(lg.events[i].f) == fid)
				var heal_at: Array = idx.filter(func(i): return lg.events[i].t == "heal" and int(lg.events[i].f) == fid)
				if died:
					assert_true(heal_at.is_empty(), "seed %d round %d: a Bloodsworn that fell heals nothing" % [sd, n])
					if dealt > 0:
						fell_after_hitting += 1
					continue
				if heal_at.is_empty():
					continue
				heals += 1
				var h: Dictionary = lg.events[heal_at[0]]
				assert_eq(int(h.dealt), dealt)
				assert_eq(int(h.to), mini(max_hp, int(h.from) + ceili(float(dealt) / AutoBattleResolver.LIFEDRINK_DIVISOR)), "half, rounded up")
				for i in idx:
					var t: String = lg.events[i].t
					if t == "wound" or t == "death":
						assert_true(i < heal_at[0], "after the round's damage lands")
					elif t == "morale":
						assert_true(i > heal_at[0], "before morale is checked")
		_checks(r, "Lifedrinker seed %d" % sd)
	assert_true(heals > 0, "the Bloodsworn healed")
	assert_true(fell_after_hitting > 0, "and one fell in a round it had hit, healing nothing")


# --- path parts and morale in battle (the M4-1 gap) -----------------------------------------------------

func test_path_parts_and_path_morale_work_with_or_without_mandates() -> void:
	for mandates in [[], ["royal_armories"]]:
		var s := PB.with_nodes(PB.game({CROWN: mandates}), CROWN, ["crown_drillyard", "crown_arbalests"])
		var crown := PB.army(s, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "crossbowmen"])
		var clans := PB.army(s, CLANS, "beasts-2", "rivermarch", ["tuskers", "fangthrowers"])
		var r := PB.fight(s, [crown, clans], "rivermarch", "", 4)
		var xbow: int = PB.fighters_of(r.log, "crossbowmen")[0]
		var shots: Array = _events(r.log, "attack").filter(func(e): return int(e.by) == xbow)
		assert_false(shots.is_empty())
		for e in shots:
			assert_eq(int(e.attack.parts.get("path_crown_arbalests", 0)), int(AscensionRules.node_effects("crown_arbalests").unit.crossbowmen.attack),
				"%s: Arbalests in the attack" % str(mandates))
		var spear: Dictionary = r.log.fighters[PB.fighters_of(r.log, "spearmen")[0]]
		assert_eq(int(spear.hp_parts.get("path_crown_drillyard", 0)), int(AscensionRules.node_effects("crown_drillyard").unit.spearmen.hp))
		_checks(r, "Arbalests %s" % str(mandates))
		# Living Iron's defense on Knights, and the Celestial Host's morale in the base morale.
		var li := PB.with_nodes(PB.game({CROWN: mandates}), CROWN, IRON)
		var k := PB.army(li, CROWN, "kingdom-1", "rivermarch", ["knights"])
		var t := PB.army(li, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers"])
		var lr := PB.fight(li, [k, t], "rivermarch", "", 4)
		var knight: int = PB.fighters_of(lr.log, "knights")[0]
		for e in _events(lr.log, "attack").filter(func(x): return int(x.to) == knight):
			assert_eq(int(e.defense.parts.get("path_crown_living_iron", 0)), int(AscensionRules.node_effects("crown_living_iron").unit.knights.defense))
		var host := PB.with_nodes(PB.game({CROWN: mandates}), CROWN, HOST)
		var sp := PB.army(host, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen", "spearmen", "spearmen"])
		var tk := PB.army(host, CLANS, "beasts-2", "rivermarch", ["tuskers", "tuskers"])
		var hr := PB.fight(host, [sp, tk], "rivermarch", "", 4)
		var spearmen := PB.unit_type(host, CROWN, "spearmen")
		var bonus := int(AscensionRules.node_effects("crown_celestial_host").unit.spearmen.morale)
		var crown_log: Dictionary = hr.log.sides.filter(func(x): return x.faction == CROWN)[0]
		assert_eq(int(crown_log.base_morale), spearmen.morale + bonus, "path morale counts in the base morale")
		assert_eq(crown_log.base_morale_parts, {"path_crown_celestial_host": bonus})
		_checks(hr, "Celestial Host morale %s" % str(mandates))


# --- Dread Lands ---------------------------------------------------------------------------------------

func test_dread_lands_only_in_province_battles_in_provinces_the_blood_pact_owned_at_the_start_of_the_turn() -> void:
	var value := int(AscensionRules.node_effects("beasts_blood_pact").province_rule.value)
	var cases := [
		["bloodfen", CLANS, "province", true],  # their own land
		["rivermarch", CROWN, "province", false],  # the Crown's
		["deepwood", "", "province", false],  # nobody's
		["bloodfen|deepwood", CLANS, "border", false],  # a border, even between their provinces
	]
	for c in cases:
		var s := PB.with_nodes(PB.game(), CLANS, PACT)
		for pid in String(c[0]).split("|"):
			s.find_province(pid).owner = c[1]
		var a := PB.army(s, CROWN, "kingdom-1", String(c[0]).get_slice("|", 0), ["spearmen", "spearmen", "crossbowmen"])
		var b := PB.army(s, CLANS, "beasts-2", String(c[0]).get_slice("|", 0), ["tuskers", "fangthrowers"])
		var r := PB.fight(s, [a, b], c[0], "", 6, c[2])
		for side in r.log.sides:
			var expected := -value if c[3] and side.faction == CROWN else 0
			assert_eq(int(side.start_morale.parts.get(AutoBattleResolver.DREAD_LANDS, 0)), expected, "%s: %s" % [c[0], side.faction])
		for e in _events(r.log, "morale"):
			var faction: String = r.log.sides[int(e.side)].faction
			assert_eq(int(e.parts.get(AutoBattleResolver.DREAD_LANDS, 0)), -value if c[3] and faction == CROWN else 0, "for the whole battle")
		_checks(r, "Dread Lands %s" % c[0])
	# Without the Blood Pact, nothing.
	var plain := PB.game()
	plain.find_province("bloodfen").owner = CLANS
	assert_eq(AutoBattleResolver.dread_lands_value(plain, CLANS, plain.find_province("bloodfen")), 0)
	# Through the turn: both arrive in Bloodfen, which the Clans own with no army there, so it is theirs at the
	# start of the turn. Next turn the Crown holds it, and Dread Lands no longer works there.
	var s := PB.with_nodes(PB.game(), CLANS, PACT)
	s.find_province("bloodfen").owner = CLANS
	PB.army(s, CROWN, "kingdom-1", "deepwood", ["spearmen", "spearmen", "crossbowmen", "knights"])
	PB.army(s, CLANS, "beasts-2", "fangridge", ["fangthrowers"])
	var t1 := TurnResolver.resolve(s, {CROWN: [MoveOrder.new("kingdom-1", "bloodfen")], CLANS: [MoveOrder.new("beasts-2", "bloodfen")]}, 11)
	var b1: Array = t1.events.filter(func(e): return e.type == "battle")
	assert_eq(b1.size(), 1, "they meet in Bloodfen")
	var crown1: Dictionary = b1[0].numbers.report.sides.filter(func(x): return x.faction == CROWN)[0]
	assert_eq(int(crown1.morale_log[0].parts.get(AutoBattleResolver.DREAD_LANDS, 0)), -value, "the Clans' land at the start of the turn")
	assert_eq(int(crown1.get("dread_lands", 0)), 0, "the report's dread_lands is on the Blood Pact's side")
	assert_true(b1[0].numbers.report.lines[1].contains(AutoBattleResolver.DREAD_LANDS), b1[0].numbers.report.lines[1])
	assert_eq(t1.new_state.find_province("bloodfen").owner, CROWN, "the Crown took it")
	var s2: GameState = t1.new_state
	PB.army(s2, CLANS, "beasts-3", "deepwood", ["tuskers", "tuskers", "tuskers"])
	var t2 := TurnResolver.resolve(s2, {CLANS: [MoveOrder.new("beasts-3", "bloodfen")]}, 12)
	var b2: Array = t2.events.filter(func(e): return e.type == "battle")
	assert_eq(b2.size(), 1)
	for side in b2[0].numbers.report.sides:
		assert_false(side.morale_log[0].parts.has(AutoBattleResolver.DREAD_LANDS), "the Crown's land now: no Dread Lands")


# --- Red Harvest ---------------------------------------------------------------------------------------

func test_red_harvest_pays_a_gold_for_every_enemy_fighter_lost() -> void:
	var paid := false
	for sd in range(1, 21):
		# The mandate is set after the copy with_nodes makes: its MandateData row comes with M4-2, and a state
		# that names an unknown mandate doesn't copy. TurnResolver._fight reads the state as it stands.
		var s := PB.with_nodes(PB.game(), CLANS, PACT)
		s.find_faction(CLANS).mandates = [AutoBattleResolver.RED_HARVEST]
		var a := PB.army(s, CLANS, "beasts-1", "bloodfen", ["tuskers", "tuskers", "tuskers", "war_bear"])
		var b := PB.army(s, CROWN, "kingdom-2", "bloodfen", ["spearmen", "crossbowmen"])
		var fighters := b.units.size()
		var gold := s.find_faction(CLANS).gold
		var events := []
		var winner := TurnResolver._fight(s, AutoBattleResolver.new(), SeededRNG.new(sd), "province", ["bloodfen"],
			{CLANS: [a], CROWN: [b]}, CLANS, events)
		var ev: Dictionary = events[0]
		if winner != CLANS:
			assert_eq(s.find_faction(CLANS).gold, gold, "no harvest from a lost battle")
			continue
		var want := fighters * AutoBattleResolver.RED_HARVEST_GOLD
		assert_eq(s.find_faction(CLANS).gold, gold + want, "seed %d: paid" % sd)
		assert_eq(int(ev.numbers.red_harvest), want)
		assert_eq(int(ev.numbers.report.red_harvest.fighters), fighters)
		assert_true(String(ev.text).contains("Red Harvest: the Thornmane Clans took %d gold from the %d enemy fighters lost." % [want, fighters]), ev.text)
		var harvest: Array = _events(ev.numbers.log, "harvest")
		assert_eq(harvest.size(), 1)
		assert_eq(int(harvest[0].gold), want)
		assert_eq(BattleLog.validate(ev.numbers.log), [])
		assert_eq(BattleLog.verify_draws(ev.numbers.log), [])
		assert_eq(BattleLog.cross_check(ev.numbers.log, ev.numbers.report), [])
		paid = true
		break
	assert_true(paid, "a won battle paid the harvest")
	# Without the mandate, nothing.
	var plain := PB.with_nodes(PB.game(), CLANS, PACT)
	var pa := PB.army(plain, CLANS, "beasts-1", "bloodfen", ["tuskers", "tuskers", "tuskers", "war_bear"])
	var pb := PB.army(plain, CROWN, "kingdom-2", "bloodfen", ["spearmen"])
	var r := PB.fight(plain, [pa, pb], "bloodfen", CLANS, 1)
	assert_eq(AutoBattleResolver.red_harvest(r.sides, r.result.winner), {})


# --- the "why", the report and the odds ----------------------------------------------------------------

func test_each_new_trait_and_a_path_part_can_be_a_battles_top_why() -> void:
	var cases := [
		[CROWN, HOST, CROWN, ["seraphs", "seraphs", "seraphs"], CLANS, ["tuskers", "warchief"], "rivermarch", AutoBattleResolver.WINGS, "flew over the line and struck the Warchief"],
		[CROWN, IRON, CROWN, ["iron_colossus"], CLANS, ["fangthrowers", "fangthrowers", "fangthrowers"], "rivermarch", AutoBattleResolver.IRON_HIDE, "%d less damage from each of" % AutoBattleResolver.IRON_HIDE_DAMAGE],
		[CLANS, WILD, CLANS, ["briarwardens"], CROWN, ["knights"], "greenglade", AutoBattleResolver.ROOTED, "rooted in the forest (+%d defense)" % AutoBattleResolver.ROOTED_DEFENSE],
		[CLANS, PACT, CLANS, ["bloodsworn", "bloodsworn", "bloodsworn"], CROWN, ["knights", "knights"], "rivermarch", AutoBattleResolver.LIFEDRINKER, "hp (Lifedrinker)"],
		[CROWN, IRON, CROWN, ["knights", "knights"], CLANS, ["tuskers", "tuskers", "tuskers", "tuskers"], "rivermarch", "path_crown_living_iron", "Living Iron (+%d defense on Aurel Crown's" % int(AscensionRules.node_effects("crown_living_iron").unit.knights.defense)],
		[CROWN, HOST, CROWN, ["spearmen", "spearmen", "spearmen", "spearmen"], CLANS, ["tuskers", "tuskers", "tuskers"], "rivermarch", "morale_path_crown_celestial_host", "the Celestial Host's"],
	]
	for c in cases:
		var r := _top_why(c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[2])
		assert_false(r.is_empty(), "%s tops the why of a battle it won" % c[7])
		if r.is_empty():
			continue
		var top: Dictionary = r.result.report.factors[0]
		assert_true(String(top.text).contains(c[8]), "%s: %s" % [c[7], top.text])
		assert_true(String(r.result.report.why).begins_with(String(top.text)), "the why leads with it")
		assert_false(String(top.get("codex", "")).is_empty(), "%s names its codex entry" % c[7])
		assert_true(RulesCodex.ENTRIES.has(String(top.codex)), "%s: codex %s" % [c[7], top.codex])
		assert_false(String(top.text).contains("_"), "no raw id: %s" % top.text)
		_checks(r, "%s (seed %d)" % [c[7], r.seed])
	# Wings names the commander it took down, with the trait it carried.
	var w := _top_why(CROWN, HOST, CROWN, ["seraphs", "seraphs", "seraphs"], CLANS, ["tuskers", "warchief"], "rivermarch", AutoBattleResolver.WINGS, CROWN)
	var with_kill := false
	for sd in range(1, 41):
		var r := _battle(CROWN, HOST, CROWN, ["seraphs", "seraphs", "seraphs"], CLANS, ["tuskers", "warchief"], "rivermarch", "", sd)
		var f: Array = r.result.report.all_factors.filter(func(x): return x.id == AutoBattleResolver.WINGS and x.faction == CROWN)
		if not f.is_empty() and String(f[0].text).contains("Warchief fell in round") and String(f[0].text).contains("and with it Pack Leader"):
			with_kill = true
			break
	assert_true(with_kill and not w.is_empty(), "the Seraphs' clause says the Warchief fell, and Pack Leader with it")


func test_report_names_the_people_and_the_paths_in_play() -> void:
	var r := _battle(CROWN, HOST, CROWN, ["seraphs", "spearmen"], CLANS, ["tuskers", "warchief"], "rivermarch", "", 3)
	var rep: Dictionary = r.result.report
	var crown: Dictionary = rep.sides.filter(func(x): return x.faction == CROWN)[0]
	var clans: Dictionary = rep.sides.filter(func(x): return x.faction == CLANS)[0]
	assert_eq(crown.people, {"id": "celestial_host", "name": AscensionRules.branch_name("celestial_host")})
	assert_eq(clans.people, {}, "not transformed")
	assert_true(String(rep.lines[0]).contains("Aurel Crown (Celestial Host, arrived)"), rep.lines[0])
	assert_eq(String(rep.lines[1]), "Paths: Aurel Crown fought as the Celestial Host.")
	assert_eq(r.log.sides[0 if r.log.sides[0].faction == CROWN else 1].people, crown.people, "the log's side too")
	assert_true(r.log.get("paths", false))
	# Without paths: no people, no paths line, and the log is the M3-1 schema.
	var m2 := GameState.with_rulers(7, {}, [])
	var keep: Array[Army] = []
	for a in m2.armies:
		if a.ruler != null:
			keep.append(a)
	m2.armies = keep
	var x := PB.army(m2, CROWN, "kingdom-1", "rivermarch", ["spearmen", "spearmen"])
	var y := PB.army(m2, CLANS, "beasts-2", "rivermarch", ["tuskers"])
	var p := PB.fight(m2, [x, y], "rivermarch", "", 3)
	for side in p.result.report.sides:
		assert_false(side.has("people"), "no people without paths")
	assert_false(p.log.has("paths"))
	for side in p.log.sides:
		assert_false(side.has("people") or side.has("base_morale_parts"), "no path keys in an M2 log")
	assert_false(String(p.result.report.lines[1]).begins_with("Paths:"))


func test_same_seed_same_report_and_log() -> void:
	var a := _battle(CLANS, PACT, CLANS, ["bloodsworn", "bloodsworn", "tuskers"], CROWN, ["knights", "spearmen", "crossbowmen"], "bloodfen", "", 9)
	var b := _battle(CLANS, PACT, CLANS, ["bloodsworn", "bloodsworn", "tuskers"], CROWN, ["knights", "spearmen", "crossbowmen"], "bloodfen", "", 9)
	assert_eq(JSON.stringify(a.result.report), JSON.stringify(b.result.report))
	assert_eq(BattleLog.to_json(a.log), BattleLog.to_json(b.log))
	var rt := BattleLog.from_json(BattleLog.to_json(a.log))
	assert_eq(rt.errors, [])
	assert_eq(rt.log, a.log, "the JSON round trip is exact with heals")
	var tl := BattleTimeline.build(a.log)
	var final_hp := BattleLog.final_hp(a.log)
	for i in final_hp.size():
		assert_eq(int(tl.final_state().fighters[i].hp), int(final_hp[i]), "the timeline folds the heals")


func test_forecast_battle_odds_change_when_a_path_part_is_added() -> void:
	var odds := {}
	for nodes in [[], IRON]:
		var s := PB.with_nodes(PB.game(), CROWN, nodes)
		PB.army(s, CROWN, "kingdom-1", "rivermarch", ["knights", "knights"])
		PB.army(s, CLANS, "beasts-2", "greenglade", ["tuskers", "tuskers", "tuskers", "tuskers"])
		odds[nodes.size()] = Forecast.battle_odds(s, CROWN, ["kingdom-1"], "greenglade")
		assert_true(odds[nodes.size()].ok, odds[nodes.size()].text)
	assert_true(int(odds[IRON.size()].wins) > int(odds[0].wins), "Living Iron raises the odds: %s -> %s" % [odds[0].text, odds[IRON.size()].text])
	# Dread Lands counts too: the same attack into the Blood Pact's own land (the Blood Pact changes nothing
	# else about Fangthrowers), so the Crown can only do worse, seed by seed.
	var dread := {}
	for nodes in [[], PACT]:
		var s := PB.with_nodes(PB.game(), CLANS, nodes)
		s.find_province("bloodfen").owner = CLANS
		PB.army(s, CROWN, "kingdom-1", "deepwood", ["spearmen", "spearmen", "crossbowmen"])
		PB.army(s, CLANS, "beasts-2", "bloodfen", ["fangthrowers", "fangthrowers", "fangthrowers"])
		dread[nodes.size()] = Forecast.battle_odds(s, CROWN, ["kingdom-1"], "bloodfen")
	assert_true(int(dread[PACT.size()].wins) <= int(dread[0].wins), "Dread Lands: %s -> %s" % [dread[0].text, dread[PACT.size()].text])


# --- the log, the codex and trait text -----------------------------------------------------------------

func test_validate_catches_a_bad_heal() -> void:
	var r := _battle(CLANS, PACT, CLANS, ["bloodsworn", "bloodsworn", "bloodsworn"], CROWN, ["knights", "knights"], "rivermarch", "", 1)
	var heals: Array = _events(r.log, "heal")
	assert_false(heals.is_empty())
	var bad: Dictionary = r.log.duplicate(true)
	for e in bad.events:
		if e.t == "heal":
			e.to = int(PathData.NEW_UNITS.bloodsworn.hp) + 5
			break
	assert_false(BattleLog.validate(bad).is_empty(), "a heal past the maximum")
	var off: Dictionary = r.log.duplicate(true)
	for e in off.events:
		if e.t == "heal":
			e.to = int(e.to) - 1 if int(e.to) - 1 > int(e.from) else int(e.to)
			e.dealt = int(e.dealt) + 2
			break
	assert_false(BattleLog.cross_check(off, r.result.report).is_empty(), "a heal that doesn't match the round's hits")


func test_trait_text_codex_entries_and_the_new_units() -> void:
	var traits := [AutoBattleResolver.WINGS, AutoBattleResolver.IRON_HIDE, AutoBattleResolver.ROOTED, AutoBattleResolver.LIFEDRINKER]
	for u in PathData.NEW_UNITS.values():
		assert_true(traits.has(String(u.trait)), "%s's trait is one of the four" % u.name)
	var keys := RulesCodex.ENTRIES.keys()
	var after := keys.find("trait_pack_leader")
	for i in traits.size():
		var t: String = traits[i]
		var id := AutoBattleResolver.codex_id_for_trait(t)
		assert_eq(keys[after + 1 + i], id, "%s sits next to the other trait entries" % id)
		assert_true(RulesCodex.text(id).begins_with(AutoBattleResolver.TRAIT_TEXT[t]), "%s starts with its trait text" % id)
		assert_true(AutoBattleResolver.TRAIT_SHORT.has(t))
		assert_false(RulesCodex.text(id).contains("_"), "no raw id in %s" % id)
	assert_true(AutoBattleResolver.TRAIT_TEXT[AutoBattleResolver.IRON_HIDE].contains("%d less damage" % AutoBattleResolver.IRON_HIDE_DAMAGE))
	assert_true(AutoBattleResolver.TRAIT_TEXT[AutoBattleResolver.ROOTED].contains("+%d defense" % AutoBattleResolver.ROOTED_DEFENSE))
	assert_true(AutoBattleResolver.TRAIT_TEXT[AutoBattleResolver.LIFEDRINKER].contains(AutoBattleResolver.SHARE_WORDS[AutoBattleResolver.LIFEDRINK_DIVISOR]))
	var morale := RulesCodex.text("battle_morale")
	assert_true(morale.contains("Dread Lands") and morale.contains("Sunspears"), morale)
	# A new unit's tooltip text is its trait's (the roster M4-2 adds reads TRAIT_TEXT, as data/factions.gd does).
	var s := PB.with_nodes(PB.game(), CROWN, HOST)
	assert_eq(PB.unit_type(s, CROWN, "seraphs").get_trait_desc(), AutoBattleResolver.TRAIT_TEXT[AutoBattleResolver.WINGS])
