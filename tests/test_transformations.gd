extends "res://tests/test_case.gd"
## M4-2 (#67), design/M4_ASCENSION.md §3.4, §4, §6, §9: transformations on the map. The roster change (new
## unit, rename, units on the map, the hp rule, validation and saves), Blood Levy, Raiding Parties, Forest
## Stride, the research phase's province rules (the Wild Spreads, Hallowed Land, the Forges) with their
## forecasts, the mandates a transformation opens and forswears, the new events, the Simulator's invariants
## and a replay through every transformation. Expected numbers come from data, never typed in.

const Simulator := preload("res://tools/autoplay/simulator.gd")
const CROWN := "kingdom"
const CLANS := "beasts"


func _game(seed_value: int = 7, builds: Dictionary = {}) -> GameState:
	var errors := []
	var s := GameState.with_paths(seed_value, builds, errors)
	assert_true(s != null, "a game with paths starts: %s" % ", ".join(errors))
	return s


func _resolve(s: GameState, orders: Dictionary = {}) -> Dictionary:
	var r := TurnResolver.resolve(s, orders, TurnResolver.seed_for_turn(s))
	assert_true(r.new_state != null, "the turn resolves: %s" % ", ".join(r.get("errors", [])))
	return r


func _events(events: Array, type: String, fid: String = "") -> Array:
	return events.filter(func(e): return e.type == type and (fid.is_empty() or e.factions.has(fid)))


func _type(s: GameState, fid: String, type_id: String) -> UnitType:
	return TurnResolver.recruitable_type(s.find_faction(fid), type_id)


func _units_of(s: GameState, fid: String, type_id: String) -> Array:
	var out := []
	for a in s.armies:
		if a.owner == fid:
			for u in a.units:
				if u.type.id == type_id:
					out.append(u)
	return out


## The faction's two tier I nodes and the Oath of `branch_id` (what its transformation needs).
func _before_transformation(fid: String, branch_id: String) -> Array:
	var out := []
	for nid in AscensionRules.node_ids(fid):
		if AscensionRules.node_kind(nid) == PathData.TIER1:
			out.append(nid)
	out.append(String(PathData.BRANCHES[branch_id].oath))
	return out


## A game where `fid` has sworn `branch_id`'s Oath and its transformation completes in the next research
## phase (its target, paid for).
func _about_to_transform(fid: String, branch_id: String, seed_value: int = 7, builds: Dictionary = {}) -> GameState:
	var s := AscensionRules.with_nodes(_game(seed_value, builds), fid, _before_transformation(fid, branch_id))
	var t := String(PathData.BRANCHES[branch_id].transformation)
	s.find_faction(fid).research_target = t
	s.find_faction(fid).research_points = AscensionRules.node_cost(t)
	return s


## A game where `fid` has become `branch_id` already (granted before turn 1).
func _transformed(fid: String, branch_id: String, seed_value: int = 7, builds: Dictionary = {}) -> GameState:
	var ids := _before_transformation(fid, branch_id)
	ids.append(String(PathData.BRANCHES[branch_id].transformation))
	return AscensionRules.with_nodes(_game(seed_value, builds), fid, ids)


func _army(s: GameState, fid: String, at: String, type_ids: Array) -> Army:
	var a := Army.new()
	a.id = s.new_army_id(fid)
	a.owner = fid
	a.location = at
	for tid in type_ids:
		a.units.append(Unit.new(_type(s, fid, tid), fid))
	s.armies.append(a)
	return a


# --- the roster change (acceptance: roster, units on the map and validate agree; saves load identically) ---

func test_each_transformation_changes_the_roster_and_the_units_on_the_map() -> void:
	var checked := 0
	for branch_id in PathData.BRANCHES:
		var fid := String(PathData.BRANCHES[branch_id].faction)
		var nid := String(PathData.BRANCHES[branch_id].transformation)
		var fx := AscensionRules.node_effects(nid)
		var s := _about_to_transform(fid, branch_id)
		var before_max := {}
		for a in s.armies:
			if a.owner == fid:
				for u in a.units:
					before_max[u] = [RulerRules.unit_max_hp(s, u), u.current_hp]
		var roster_before := s.find_faction(fid).unit_types.size()
		var r := _resolve(s)
		var after: GameState = r.new_state
		var f := after.find_faction(fid)
		# The roster: the changed unit keeps its id and takes its new name; the new unit joins it.
		for type_id in fx.rename:
			var ut := _type(after, fid, String(type_id))
			assert_eq(ut.name, String(fx.rename[type_id]), "%s: %s renamed" % [nid, type_id])
			assert_eq(AscensionRules.unit_title(after, fid, ut), "%s (%s of %s)" % [fx.rename[type_id],
				AscensionRules.base_unit_name(fid, String(type_id)), AscensionRules.branch_ref(branch_id)])
			for u in _units_of(after, fid, String(type_id)):
				assert_eq(u.type.name, String(fx.rename[type_id]), "%s: the units on the map are the changed unit" % nid)
		var data: Dictionary = PathData.NEW_UNITS[fx.new_unit]
		var nu := _type(after, fid, String(fx.new_unit))
		assert_true(nu != null, "%s: %s join the roster" % [nid, data.name])
		assert_eq([nu.name, nu.hp, nu.attack, nu.defense, nu.morale, nu.cost, nu.trait_id],
			[data.name, data.hp, data.attack, data.defense, data.morale, data.cost, data.trait])
		assert_false(nu.trait_description.is_empty(), "%s's trait explains itself" % data.name)
		assert_eq(f.unit_types.size(), roster_before + 1)
		assert_eq(AscensionRules.people_name(after, fid), AscensionRules.branch_name(branch_id))
		# The hp rule (§3.4): every unit on the map moved by its max hp change, never below 1.
		var i := 0
		for a in s.armies:
			if a.owner != fid:
				continue
			for u in a.units:
				var now: Unit = after.find_army(a.id).units[a.units.find(u)]
				var delta: int = RulerRules.unit_max_hp(after, now) - int(before_max[u][0])
				assert_eq(now.current_hp, maxi(1, int(before_max[u][1]) + delta), "%s: %s by the hp rule" % [nid, now.type.id])
				i += 1
		assert_true(i > 0)
		# Validation agrees, both ways.
		var errors := []
		assert_true(after.validate(errors), "%s: the state validates: %s" % [nid, ", ".join(errors)])
		var broken := after.deep_copy([])
		var bf := broken.find_faction(fid)
		bf.unit_types = bf.unit_types.filter(func(ut): return ut.id != String(fx.new_unit))
		errors = []
		assert_false(AscensionRules.validate(broken, errors), "%s: a roster without the new unit is refused" % nid)
		assert_true(", ".join(errors).contains("are not on its roster"), ", ".join(errors))
		var undone := after.deep_copy([])
		undone.find_faction(fid).researched = undone.find_faction(fid).researched.filter(func(x): return x.node != nid)
		errors = []
		assert_false(AscensionRules.validate(undone, errors), "%s: a roster ahead of the research is refused" % nid)
		assert_true(", ".join(errors).contains("which brings them") and ", ".join(errors).contains("which renames them"), ", ".join(errors))
		# A save made after it loads identically (to_dict, JSON, from_dict).
		var text := JSON.stringify(after.to_dict())
		var loaded := GameState.from_dict(JSON.parse_string(text), errors)
		assert_true(loaded != null, ", ".join(errors))
		assert_eq(JSON.stringify(loaded.to_dict()), text, "%s: the save loads identically" % nid)
		assert_eq(_type(loaded, fid, String(fx.new_unit)).name, String(data.name))
		# The transformed event, public and to the faction itself.
		var ev := _events(r.events, "transformed", fid)
		assert_eq(ev.size(), 1, "%s makes one transformed event" % nid)
		assert_true(_events(r.events, "research_done", fid).is_empty(), "instead of research_done")
		var e: Dictionary = ev[0]
		assert_eq(e.codex, AscensionRules.node_data(nid).codex)
		assert_eq(e.numbers.new_unit, String(fx.new_unit))
		assert_eq(e.numbers.forswears, String(fx.forswears))
		assert_eq(e.numbers.opens_mandate, String(fx.opens_mandate))
		assert_true(String(e.text).begins_with("The %s has become %s." % [f.faction_name, AscensionRules.branch_ref(branch_id)]), e.text)
		assert_true(String(e.numbers.own_text).begins_with("Your people have become %s." % AscensionRules.branch_ref(branch_id)), e.numbers.own_text)
		for type_id in fx.rename:
			assert_true(String(e.text).contains("are %s now" % fx.rename[type_id]), e.text)
		assert_true(String(e.text).contains("can recruit %s" % data.name) and String(e.text).contains("from turn %d" % (s.current_turn + 2)), e.text)
		assert_true(String(e.text).contains(RulerRules.mandate_name(String(fx.opens_mandate))), e.text)
		assert_false(String(e.text).contains("_"), "no raw ids: %s" % e.text)
		# The new unit can be recruited from the next turn, at the price and hp its forecast gives.
		f.gold = 200
		var fc := Forecast.recruit(after, fid, String(fx.new_unit))
		assert_true(fc.ok, fc.reason)
		var r2 := _resolve(after, {fid: [RecruitOrder.new(String(fx.new_unit))]})
		var rec := _events(r2.events, "recruited", fid)
		assert_eq(rec.size(), 1, "%s are recruited" % data.name)
		assert_eq(int(rec[0].numbers.cost), int(fc.price))
		var recruits := _units_of(r2.new_state, fid, String(fx.new_unit))
		assert_eq(recruits.size(), 1)
		assert_eq(recruits[0].current_hp, int(fc.hp), "%s arrive with the forecast hp" % data.name)
		checked += 1
	assert_eq(checked, PathData.BRANCHES.size(), "all four transformations")


func test_validation_refuses_new_units_without_paths() -> void:
	var s := GameState.with_rulers(7)
	s.find_faction(CROWN).unit_types.append(AscensionRules.new_unit_type("seraphs"))
	var errors := []
	assert_false(AscensionRules.validate(s, errors))
	assert_true(", ".join(errors).contains("Seraphs") and ", ".join(errors).contains("no paths"), ", ".join(errors))


func test_breakdowns_name_the_changed_unit_both_ways() -> void:
	var s := _transformed(CROWN, "celestial_host")
	var b := Breakdown.unit_stat(s, CROWN, "spearmen", "morale")
	assert_eq(b.lines.map(func(l): return l.label), [AscensionRules.base_unit_name(CROWN, "spearmen"),
		AscensionRules.node_name("crown_celestial_host")], "Morale = Spearmen 6 + Celestial Host 2")
	assert_true(String(b.title).contains("Sunspears (Spearmen of the Celestial Host)"), b.title)
	assert_eq(Breakdown.sum_of_lines(b), int(b.total))


# --- the Wild Spreads (acceptance: picks match §4.6 on constructed boards) ----------------------------

## A Clans game with the Thorn Wild, owning exactly `owned` (and its capital); everything else neutral.
func _wild_board(owned: Array) -> GameState:
	var s := _transformed(CLANS, "thorn_wild", 7, {CLANS: "beast_god_unbound"})
	for p in s.provinces:
		if p.owner == CLANS and p.id != "fangridge":
			p.owner = ""
	for pid in owned:
		s.find_province(pid).owner = CLANS
	return s


func _pick_ids(picks: Array) -> Array:
	return picks.map(func(p): return String(p.province))


func test_the_wild_spreads_picks_by_income_ties_by_id_never_a_capital() -> void:
	# Bloodfen (plains, next to Deepwood) earns the most of the provinces next to a Clans forest.
	var s := _wild_board(["bloodfen", "deepwood", "ebonpeak", "ironspike", "wildmoor", "blackwood"])
	var picks := AscensionRules.wild_spread_picks(s, CLANS)
	assert_eq(_pick_ids(picks), ["bloodfen"], "the highest base income next to a forest you own")
	assert_eq(picks[0].grown_from, ["deepwood"])
	assert_eq(picks[0].from_terrain, "plains")
	# Ties go to the first by id.
	var tie := s.deep_copy([])
	tie.find_province("blackwood").income = tie.find_province("bloodfen").income
	assert_eq(_pick_ids(AscensionRules.wild_spread_picks(tie, CLANS)), ["blackwood"], "blackwood comes before bloodfen")
	# Capitals never: Fangridge earns the most and touches a Clans forest, but it is a capital.
	var cap := s.deep_copy([])
	cap.find_province("bloodfen").terrain = "forest"
	var cap_picks := _pick_ids(AscensionRules.wild_spread_picks(cap, CLANS, 3))
	assert_false(cap_picks.has("fangridge"), "a capital never grows: %s" % [cap_picks])
	assert_eq(cap_picks[0], "blackwood")
	# None qualifying: no forest of yours, so nothing grows and nothing changes.
	var none := _wild_board(["ebonpeak", "ironspike"])
	assert_eq(AscensionRules.wild_spread_picks(none, CLANS), [])
	var r := _resolve(none)
	assert_true(_events(r.events, "wild_spread").is_empty(), "no event when nothing qualifies")
	for p in none.provinces:
		assert_eq(r.new_state.find_province(p.id).terrain, p.terrain)
	# Neutral and enemy forests don't count: Wildmoor is neutral here.
	var neutral := _wild_board(["ironspike", "blackwood"])
	assert_eq(AscensionRules.wild_spread_picks(neutral, CLANS), [], "a forest you don't own grows nothing")


func test_the_wild_spreads_happens_as_forecast_and_deep_roots_picks_the_second_from_the_first() -> void:
	# Wildmoor is the Clans' only forest: Blackwood (8) grows first; then Ebonpeak, which touches only the
	# new forest of Blackwood, beats Ironspike (5).
	var s := _wild_board(["wildmoor", "ironspike", "blackwood", "ebonpeak"])
	var two := AscensionRules.wild_spread_picks(s, CLANS, 2)
	assert_eq(_pick_ids(two), ["blackwood", "ebonpeak"])
	assert_eq(two[1].grown_from, ["blackwood"], "the second grows from the first")
	# One a turn without Deep Roots: the forecast is the result.
	var fc := Forecast.province_rules(s, CLANS)
	assert_true(fc.ok)
	assert_eq(fc.spread.map(func(p): return p.province), ["blackwood"])
	assert_true(String(fc.spread[0].text).begins_with("Blackwood turns to forest at the end of this turn (the Wild Spreads), if you still hold it and Wildmoor then."), fc.spread[0].text)
	var r := _resolve(s)
	var grown := _events(r.events, "wild_spread", CLANS)
	assert_eq(grown.map(func(e): return e.provinces[0]), ["blackwood"])
	assert_eq(r.new_state.find_province("blackwood").terrain, "forest")
	assert_eq(String(grown[0].codex), "wild_spreads")
	assert_true(String(grown[0].text).begins_with("The Thorn Wild spread into Blackwood."), grown[0].text)
	assert_true(String(grown[0].text).contains("+%d defense" % int(AutoBattleResolver.TERRAIN.forest.defense)), grown[0].text)
	assert_eq(AscensionRules.terrain_note(r.new_state.find_province("blackwood")), "grown by the Wild Spreads; it was hills")
	# Deep Roots, bought by sacrifice this turn, grows two at once, as its forecast says.
	var orders := [SacrificeOrder.new(RulerRules.DEEP_ROOTS)]
	assert_eq(RulerRules.sacrifice_check(s, CLANS, RulerRules.DEEP_ROOTS), {}, "the Thorn Wild opened Deep Roots")
	var fc2 := Forecast.province_rules(s, CLANS, orders)
	assert_eq(fc2.spread.map(func(p): return p.province), ["blackwood", "ebonpeak"])
	var now := Forecast.mandate_now(RulerRules.with_sacrifice(s, CLANS, RulerRules.DEEP_ROOTS), CLANS, RulerRules.DEEP_ROOTS)
	assert_eq(now, "For you now: the Wild Spreads grows Blackwood and Ebonpeak this turn.")
	var r2 := _resolve(s, {CLANS: orders})
	assert_eq(_events(r2.events, "sacrificed", CLANS).size(), 1)
	assert_eq(_events(r2.events, "wild_spread", CLANS).map(func(e): return e.provinces[0]), ["blackwood", "ebonpeak"])
	assert_eq(r2.new_state.find_province("ebonpeak").terrain, "forest")
	# The terrain stays forest after the province is lost.
	var lost: GameState = r2.new_state
	lost.find_province("ebonpeak").owner = ""
	var r3 := _resolve(lost)
	assert_eq(r3.new_state.find_province("ebonpeak").terrain, "forest", "the map remembers who passed")


func test_a_transformation_works_in_the_research_phase_it_completes_and_its_forecast_knows() -> void:
	var s := _about_to_transform(CLANS, "thorn_wild")
	s.find_province("deepwood").owner = CLANS
	s.find_province("bloodfen").owner = CLANS
	var own := Forecast.province_rules(s, CLANS)
	assert_true(own.ok, "your own forecast counts this turn's transformation")
	assert_false(own.spread.is_empty())
	var rival := Forecast.province_rules(s, CLANS, [], CROWN)
	assert_false(rival.ok, "the rival's view never reads your research target")
	var r := _resolve(s)
	assert_eq(_events(r.events, "wild_spread", CLANS).map(func(e): return e.provinces[0]), own.spread.map(func(p): return p.province))
	var types: Array = r.events.filter(func(e): return e.phase == "research" and e.factions.has(CLANS)).map(func(e): return e.type)
	assert_eq(types.slice(0, 3), ["research_gained", "transformed", "wild_spread"], "gain, transform, then the province rule")


# --- Hallowed Land and the Forges (acceptance: they heal exactly as forecast for armies that hold) -----

func test_hallowed_land_heals_exactly_as_forecast_and_hymn_of_dawn_doubles_it() -> void:
	# The Warrior King has no Mending Light, so nothing else heals the units this turn.
	var s := _transformed(CROWN, "celestial_host", 7, {CROWN: "warrior_king"})
	var home: Army = s.find_army("kingdom-1")
	home.units[0].current_hp = 1
	home.units[2].current_hp = 5
	home.commander.current_hp = 20
	var ruler := RulerRules.ruler_unit(s, CROWN)
	ruler.current_hp = ruler.type.hp - 3
	var fc := Forecast.province_rules(s, CROWN)
	var heal: Dictionary = fc.heal
	var amount := int(AscensionRules.node_effects("crown_celestial_host").province_rule.value)
	assert_eq(int(heal.amount), amount)
	assert_eq(heal.healed.size(), 3, "two units and the commander; the ruler is skipped")
	assert_true(String(fc.by_army["kingdom-1"].text).contains("+%d hp each" % amount), fc.by_army["kingdom-1"].text)
	var r := _resolve(s)
	var after: Army = r.new_state.find_army("kingdom-1")
	var fighters := after.units + [after.commander]
	for h in heal.healed:
		var u: Unit = after.commander if h.commander else after.units[_index_of(s, home, h)]
		assert_eq(u.current_hp, int(h.after), "%s healed as forecast" % h.name)
	assert_eq(fighters.size(), home.units.size() + 1)
	var ev := _events(r.events, "path_healed", CROWN)
	assert_eq(ev.size(), 1)
	assert_eq(int(ev[0].numbers.total), int(heal.total))
	assert_eq(String(ev[0].codex), "hallowed_land")
	assert_true(String(ev[0].text).begins_with("Hallowed Land: 3 wounded fighters of the Aurel Crown healed %d hit points at Crownkeep" % int(heal.total)), ev[0].text)
	# Hymn of Dawn, bought by sacrifice this turn, doubles it at once, as the forecast says.
	var orders := [SacrificeOrder.new(RulerRules.HYMN_OF_DAWN)]
	var mult := int(RulerRules.mandate_data(RulerRules.HYMN_OF_DAWN).heal_multiplier)
	var fc2 := Forecast.province_rules(s, CROWN, orders)
	assert_eq(int(fc2.heal.amount), amount * mult)
	var r2 := _resolve(s, {CROWN: orders})
	var after2: Army = r2.new_state.find_army("kingdom-1")
	for h in fc2.heal.healed:
		var u: Unit = after2.commander if h.commander else after2.units[_index_of(s, home, h)]
		assert_eq(u.current_hp, int(h.after), "%s healed %d" % [h.name, amount * mult])


## The index in `home.units` of the unit a heal entry names (each type appears once in the starting army).
func _index_of(_s: GameState, home: Army, h: Dictionary) -> int:
	for i in home.units.size():
		if home.units[i].type.id == String(h.unit):
			return i
	return -1


func test_the_forges_heal_to_full_only_in_forts_as_forecast() -> void:
	var s := _transformed(CROWN, "living_iron", 7, {CROWN: "warrior_king"})
	s.find_province("westwatch").owner = CROWN  # owned, no fort
	var field := _army(s, CROWN, "westwatch", ["spearmen"])
	field.units[0].current_hp = 2
	var home: Army = s.find_army("kingdom-1")
	home.units[2].current_hp = 3
	var fc := Forecast.province_rules(s, CROWN)
	assert_eq(int(fc.heal.amount), 0, "to full")
	assert_eq(fc.heal.healed.size(), 1, "only the army in the fort")
	assert_false(fc.by_army.has(field.id))
	var r := _resolve(s)
	var max_hp := RulerRules.unit_max_hp(r.new_state, r.new_state.find_army("kingdom-1").units[2])
	assert_eq(r.new_state.find_army("kingdom-1").units[2].current_hp, max_hp)
	assert_eq(int(fc.heal.healed[0].after), max_hp)
	assert_eq(r.new_state.find_army(field.id).units[0].current_hp, 2, "no fort, no heal")
	var ev := _events(r.events, "path_healed", CROWN)
	assert_true(String(ev[0].text).begins_with("The Forges: 1 wounded fighter of the Aurel Crown healed to full at Crownkeep (+%d hit points)." % (max_hp - 3)), ev[0].text)


# --- Blood Levy (acceptance: price and arriving hp equal the recruit forecast) -------------------------

func test_blood_levy_prices_and_wounded_arrivals_equal_the_recruit_forecast() -> void:
	var s := AscensionRules.with_nodes(_game(7, {CLANS: "blood_of_the_fang"}), CLANS, _before_transformation(CLANS, "blood_pact"))
	var f := s.find_faction(CLANS)
	f.gold = 500
	var n := int(AscensionRules.node_effects("beasts_oath_blood").blood_levy)
	var orders := []
	var expected := []
	for ut in f.unit_types:
		var max_hp := int(RulerRules.unit_stats(s, CLANS, ut.id).hp)
		var fc := Forecast.recruit(s, CLANS, ut.id)
		assert_eq(int(fc.price), ut.cost - floori(float(ut.cost) / n), "%s: a quarter off" % ut.name)
		assert_eq(int(fc.hp), maxi(1, max_hp - floori(float(max_hp) / n)), "%s: a quarter of its hp missing" % ut.name)
		assert_eq(RulerRules.price_text(s, CLANS, ut), "%d gold (%d - Blood Levy %d)" % [fc.price, ut.cost, floori(float(ut.cost) / n)])
		orders.append(RecruitOrder.new(ut.id))
		expected.append(fc)
	var cmd := Forecast.recruit(s, CLANS, f.commander_type.id)
	assert_eq([cmd.price, cmd.hp], [f.commander_type.cost, f.commander_type.hp], "commanders cost and arrive as usual")
	# The Ninth Fang's recruits (Warband Muster) arrive wounded too, where it started the turn.
	orders.append(RecruitOrder.new("tuskers", RecruitOrder.AT_RULER))
	expected.append(Forecast.recruit(s, CLANS, "tuskers"))
	var gold := Forecast.gold_after_recruits(s, CLANS, orders)
	for i in orders.size():
		assert_true(gold.results[i].ok, String(gold.results[i].get("reason", "")))
		assert_eq(int(gold.results[i].hp), int(expected[i].hp), "the gold forecast agrees on the hp")
	var r := _resolve(s, {CLANS: orders})
	var rec := _events(r.events, "recruited", CLANS)
	assert_eq(rec.size(), orders.size())
	for i in rec.size():
		assert_eq(int(rec[i].numbers.cost), int(expected[i].price), "%s paid as forecast" % expected[i].name)
		assert_eq(int(rec[i].numbers.hp), int(expected[i].hp), "%s arrives as forecast" % expected[i].name)
		assert_eq(int(rec[i].numbers.max_hp), int(expected[i].max_hp))
		assert_true(String(rec[i].text).contains("They arrive wounded, %d of %d hit points (Blood Levy" % [expected[i].hp, expected[i].max_hp]), rec[i].text)
	assert_true(String(rec[0].text).contains("so Berserk is already on"), rec[0].text)
	assert_eq(String(rec[orders.size() - 1].codex), "field_recruit")
	# The units on the map have exactly that hp.
	var army: Army = null
	for a in r.new_state.armies:
		if a.owner == CLANS and a.location == "fangridge" and a.ruler == null and a.units.size() > 3:
			army = a
	assert_true(army != null)
	assert_eq(army.units.slice(army.units.size() - orders.size()).map(func(u): return u.current_hp), expected.map(func(e): return int(e.hp)))
	# The Blood Pact's Bloodtuskers keep Tuskers' price and arrive at a quarter less of their lower maximum.
	var pact := AscensionRules.with_nodes(s, CLANS, ["beasts_blood_pact"])
	var bt := Forecast.recruit(pact, CLANS, "tuskers")
	assert_eq(int(bt.price), int(expected[0].price))
	var bmax := int(RulerRules.unit_stats(pact, CLANS, "tuskers").hp)
	assert_eq(int(bt.hp), bmax - floori(float(bmax) / n))
	# Without Blood Levy recruits arrive full and the event is unchanged.
	var plain := _game()
	plain.find_faction(CLANS).gold = 50
	var rp := _resolve(plain, {CLANS: [RecruitOrder.new("tuskers")]})
	var e: Dictionary = _events(rp.events, "recruited", CLANS)[0]
	assert_false(e.numbers.has("hp"), "only a wounded arrival carries hp")
	assert_false(String(e.text).contains("wounded"))


# --- Raiding Parties ---------------------------------------------------------------------------------

func test_raiding_parties_take_gold_on_capture_as_the_move_forecast_says() -> void:
	var s := AscensionRules.with_nodes(_game(7, {CLANS: "beast_god_unbound"}), CLANS, ["beasts_raiding"])
	var times := int(AscensionRules.node_effects("beasts_raiding").capture_gold)
	var bloodfen := s.find_province("bloodfen")
	var move := MoveOrder.new("beasts-2", "bloodfen")
	var fc := Forecast.move(s, CLANS, move)
	assert_true(String(fc.text).contains("and %d gold at once (Raiding Parties: twice its income)" % (times * bloodfen.income)), fc.text)
	var gold_before := s.find_faction(CLANS).gold
	var r := _resolve(s, {CLANS: [move]})
	var raid := _events(r.events, "raided", CLANS)
	assert_eq(raid.size(), 1)
	assert_eq(int(raid[0].numbers.gold), times * bloodfen.income)
	assert_eq(String(raid[0].phase), "capture")
	assert_eq(String(raid[0].codex), "raiding_parties")
	assert_eq(String(raid[0].text), "Raiding Parties: the Thornmane Clans took %d gold from Bloodfen (twice its income). Gold: %d → %d." % [
		times * bloodfen.income, gold_before, gold_before + times * bloodfen.income])
	var income := int(_events(r.events, "income", CLANS)[0].numbers.income)
	assert_eq(r.new_state.find_faction(CLANS).gold, gold_before + times * bloodfen.income + income)
	assert_eq(Simulator.check_invariants(s, r.new_state, r.events), [], "gold accounting counts the raid")
	# Sworn Vassals' joins bring nothing; the Crown without the node takes nothing.
	var vassals := AscensionRules.with_nodes(_game(7, {CLANS: "clan_moot"}), CLANS, ["beasts_raiding"])
	var rv := _resolve(vassals)
	assert_false(_events(rv.events, "vassal_joined", CLANS).is_empty())
	assert_true(_events(rv.events, "raided").is_empty(), "no raid for a province that swore fealty")
	var crown := _resolve(_game(), {CROWN: [MoveOrder.new("kingdom-1", "rivermarch")]})
	assert_true(_events(crown.events, "raided").is_empty())


# --- Forest Stride (acceptance: never fights on a border; into an occupied forest it fights there) ------

func _stride_game() -> GameState:
	var s := AscensionRules.with_nodes(_game(7, {CLANS: "beast_god_unbound"}), CLANS, ["beasts_raiding", "beasts_forest_stride"])
	s.find_province("bloodfen").owner = CLANS
	s.find_province("deepwood").owner = CLANS
	s.find_army("beasts-2").location = "bloodfen"
	return s


func test_forest_stride_legality_reasons_and_forecast() -> void:
	var s := _stride_game()
	assert_eq(TurnResolver.check_move(s, CLANS, MoveOrder.new("beasts-2", "wildmoor", "deepwood")), {}, "through your forest into a neutral forest")
	assert_eq(TurnResolver.check_move(s, CLANS, MoveOrder.new("beasts-2", "greenglade", "deepwood")), {})
	assert_eq(RulerRules.road_destinations(s, CLANS, "beasts-2"), {"greenglade": ["deepwood"], "wildmoor": ["deepwood"]})
	var fc := Forecast.move(s, CLANS, MoveOrder.new("beasts-2", "wildmoor", "deepwood"))
	assert_true(String(fc.text).contains("moves through the forest of Deepwood (Forest Stride) and is at Wildmoor at the start of turn %d" % (s.current_turn + 2)), fc.text)
	assert_eq(TurnResolver.road_rule(s, CLANS, MoveOrder.new("beasts-2", "wildmoor", "deepwood")), "forest_stride")
	# Through a forest you don't own.
	var foreign := s.deep_copy([])
	foreign.find_province("deepwood").owner = ""
	var c := TurnResolver.check_move(foreign, CLANS, MoveOrder.new("beasts-2", "wildmoor", "deepwood"))
	assert_eq(c.code, "stride_not_forest")
	assert_true(String(c.reason).contains("Deepwood is not yours"), c.reason)
	# Through a province that is not forest, or into one.
	var plains := TurnResolver.check_move(s, CLANS, MoveOrder.new("beasts-4", "deepwood", "bloodfen"))
	assert_true(String(plains.reason).contains("Bloodfen is plains"), plains.reason)
	var wood := s.deep_copy([])
	wood.find_army("beasts-2").location = "wildmoor"
	var into := TurnResolver.check_move(wood, CLANS, MoveOrder.new("beasts-2", "bloodfen", "deepwood"))
	assert_true(String(into.reason).contains("ends only in another forest, and Bloodfen is plains"), into.reason)
	# Without the node, the M2 reason, plus a word on Forest Stride in a game with paths.
	var without := _game(7, {CLANS: "beast_god_unbound"})
	without.find_province("deepwood").owner = CLANS
	without.find_army("beasts-2").location = "bloodfen"
	var no := TurnResolver.check_move(without, CLANS, MoveOrder.new("beasts-2", "wildmoor", "deepwood"))
	assert_eq(no.code, "no_kings_roads")
	assert_true(String(no.reason).contains("Forest Stride, on your path"), no.reason)
	assert_eq(RulerRules.road_destinations(without, CLANS, "beasts-2"), {})


func test_a_forest_stride_move_never_fights_on_a_border_and_fights_in_an_occupied_forest() -> void:
	# Crossing: the Crown steps Wildmoor -> Deepwood while the Clans stride Bloodfen -> Deepwood -> Wildmoor.
	var s := _stride_game()
	s.find_province("wildmoor").owner = CROWN
	var crown := _army(s, CROWN, "wildmoor", ["spearmen"])
	var r := _resolve(s, {CLANS: [MoveOrder.new("beasts-2", "wildmoor", "deepwood")], CROWN: [MoveOrder.new(crown.id, "deepwood")]})
	assert_true(_events(r.events, "border_battle").is_empty(), "a Forest Stride move never fights on a border")
	assert_true(_events(r.events, "battle").is_empty())
	assert_eq(r.new_state.find_army("beasts-2").location, "wildmoor")
	assert_eq(r.new_state.find_army(crown.id).location, "deepwood")
	var moved: Array = _events(r.events, "army_moved", CLANS)
	assert_eq(String(moved[0].text), "The %s moved to Wildmoor through the forest of Deepwood (Forest Stride)." % TurnResolver.army_label(s, s.find_army("beasts-2")))
	assert_eq(String(moved[0].codex), "forest_stride")
	# Into an occupied forest: the army holding it defends, and they fight there.
	var o := _stride_game()
	o.find_province("wildmoor").owner = CROWN
	var holder := _army(o, CROWN, "wildmoor", ["spearmen"])
	var r2 := _resolve(o, {CLANS: [MoveOrder.new("beasts-2", "wildmoor", "deepwood")]})
	assert_true(_events(r2.events, "border_battle").is_empty())
	var battles := _events(r2.events, "battle")
	assert_eq(battles.size(), 1, "one battle, in the forest")
	assert_eq(battles[0].provinces, ["wildmoor"])
	assert_eq(String(battles[0].numbers.report.defender), CROWN, "the holder defends")
	assert_true(r2.new_state.find_army(holder.id) == null or r2.new_state.find_army("beasts-2") == null, "the battle was fought")


# --- mandates opened and forsworn (acceptance: forsworn rejected with its reason; an owned one stays) ---

func test_a_forsworn_mandate_is_refused_with_its_reason_and_an_owned_one_stays() -> void:
	var checked := 0
	for branch_id in PathData.BRANCHES:
		var fid := String(PathData.BRANCHES[branch_id].faction)
		var nid := String(PathData.BRANCHES[branch_id].transformation)
		var fx := AscensionRules.node_effects(nid)
		var plain := _game(7, {CROWN: "warrior_king"})  # the Warrior King owns nothing a transformation forswears
		# Before: the opened mandate is closed, with the rule's reason; it is never a pre-game choice.
		var closed := RulerRules.sacrifice_check(plain, fid, String(fx.opens_mandate))
		assert_eq(closed.code, "mandate_not_open", "%s before %s" % [fx.opens_mandate, nid])
		assert_true(String(closed.reason).contains("opens only when"), closed.reason)
		assert_false(RulerRules.available_mandates(fid, plain).has(String(fx.opens_mandate)))
		var build := {"ruler": RulerRules.rulers_for(fid)[0], "mandates": [String(fx.opens_mandate)]}
		assert_false(RulerRules.build_errors(fid, build).is_empty(), "%s is never in a pre-game build" % fx.opens_mandate)
		# After: opened (and on the sacrifice list), and the forsworn one refused with its reason.
		var s := _transformed(fid, branch_id, 7, {CROWN: "warrior_king"})
		assert_eq(RulerRules.sacrifice_check(s, fid, String(fx.opens_mandate)), {}, "%s opens %s" % [nid, fx.opens_mandate])
		assert_true(RulerRules.available_mandates(fid, s).has(String(fx.opens_mandate)))
		var options: Array = Forecast.sacrifice_options(s, fid).map(func(o): return o.mandate)
		assert_true(options.has(String(fx.opens_mandate)), "the sacrifice dialog lists it")
		var f := s.find_faction(fid)
		if not f.mandates.has(String(fx.forswears)):
			var refused := RulerRules.sacrifice_check(s, fid, String(fx.forswears))
			assert_eq(refused.code, "forsworn_mandate")
			assert_eq(String(refused.reason), "%s was forsworn when the %s became %s, so it can no longer be bought by sacrifice. Mandates you already have stay." % [
				RulerRules.mandate_name(String(fx.forswears)), f.faction_name, AscensionRules.branch_ref(branch_id)])
			checked += 1
	assert_eq(checked, PathData.BRANCHES.size())
	# The Iron Crown owns Heavy Tithes; the Celestial Host forswears it, and it stays and keeps paying.
	var owned := _transformed(CROWN, "celestial_host", 7, {CROWN: "iron_crown"})
	assert_true(RulerRules.has_mandate(owned, CROWN, RulerRules.HEAVY_TITHES))
	assert_eq(RulerRules.sacrifice_check(owned, CROWN, RulerRules.HEAVY_TITHES).code, "owned_mandate")
	var keys: Array = RulerRules.province_income_parts(owned, "crownkeep").mods.map(func(m): return m.key)
	assert_true(keys.has(RulerRules.HEAVY_TITHES), "an owned mandate stays: %s" % [keys])
	var r := _resolve(owned)
	assert_true(RulerRules.has_mandate(r.new_state, CROWN, RulerRules.HEAVY_TITHES))
	# A path mandate held without a sacrifice is refused on load.
	var bad := _transformed(CROWN, "celestial_host")
	bad.find_faction(CROWN).mandates.append(RulerRules.HYMN_OF_DAWN)
	var errors := []
	assert_false(bad.validate(errors))
	assert_true(", ".join(errors).contains("Hymn of Dawn without a sacrifice"), ", ".join(errors))


func test_forge_tithe_pays_every_fort_you_own() -> void:
	var s := _transformed(CROWN, "living_iron", 7, {CROWN: "warrior_king"})
	var gold := int(RulerRules.mandate_data(RulerRules.FORGE_TITHE).fort_income)
	var r := _resolve(s, {CROWN: [SacrificeOrder.new(RulerRules.FORGE_TITHE)]})
	var after: GameState = r.new_state
	var parts := RulerRules.province_income_parts(after, "crownkeep")
	var tithe: Array = parts.mods.filter(func(m): return m.key == RulerRules.FORGE_TITHE)
	assert_eq(tithe.size(), 1)
	assert_eq(int(tithe[0].value), gold)
	var b := Breakdown.province_income(after, "crownkeep")
	assert_eq(Breakdown.sum_of_lines(b), int(b.total))
	var inc: Dictionary = _events(r.events, "income", CROWN)[0]
	assert_eq(int(inc.numbers.by_province.crownkeep), int(parts.total), "the income phase pays it this turn")
	assert_true(String(inc.text).contains("Forge Tithe +%d" % gold), inc.text)
	# No fort, no tithe.
	after.find_province("westwatch").owner = CROWN
	assert_true(RulerRules.province_income_parts(after, "westwatch").mods.filter(func(m): return m.key == RulerRules.FORGE_TITHE).is_empty())


# --- replay, invariants, codex, paths off --------------------------------------------------------------

var _seen_types := {}  # event types the replay sessions made, with counts


## Plays a session where the Crown becomes `crown_branch` and the Clans `clans_branch` (research paid for
## up front), with wounded units for the heals, then returns it after `turns` turns.
func _session_through(crown_branch: String, clans_branch: String, turns: int) -> GameSession:
	var s := _game(21, {CROWN: "warrior_king", CLANS: "blood_of_the_fang"})
	for fid in [CROWN, CLANS]:
		s.find_faction(fid).research_points = 200
		s.find_faction(fid).gold = 150
	for a in s.armies:
		for u in a.units:
			u.current_hp = maxi(1, u.current_hp - 4)
	for pid in ["bloodfen", "deepwood", "wildmoor", "ironspike", "ebonpeak"]:
		s.find_province(pid).owner = CLANS
	for pid in ["westwatch", "stonegate", "highcrag"]:
		s.find_province(pid).owner = CROWN
	var plan := {CROWN: _before_transformation(CROWN, crown_branch), CLANS: _before_transformation(CLANS, clans_branch)}
	var session := GameSession.new(s, [CROWN, CLANS], 21)
	for turn in turns:
		var prev := session.state()
		for fid in [CROWN, CLANS]:
			if session.phase() == GameSession.Phase.HANDOFF:
				session.acknowledge_handoff()
			var view := session.state()
			if AscensionRules.research_target(view, fid).is_empty():
				for nid in plan[fid]:
					if AscensionRules.check_research(view, fid, nid).is_empty():
						assert_eq(session.queue_research(String(nid)), "")
						break
			var f := view.find_faction(fid)
			for ut in f.unit_types:
				if PathData.NEW_UNITS.has(ut.id):
					session.queue_order(RecruitOrder.new(ut.id))
			if fid == CLANS and turn == 1:
				session.queue_order(RecruitOrder.new("tuskers", RecruitOrder.AT_RULER))
			session.end_turn()
		var found := Simulator.check_invariants(prev, session.state(), session.turn_report().events)
		assert_eq(found, [], "turn %d keeps every invariant" % (turn + 1))
		for e in session.turn_report().events:
			_seen_types[String(e.type)] = int(_seen_types.get(String(e.type), 0)) + 1
	return session


func test_a_replay_through_every_transformation_is_identical() -> void:
	var seen := {}
	for pair in [["celestial_host", "thorn_wild"], ["living_iron", "blood_pact"]]:
		var session := _session_through(pair[0], pair[1], 7)
		var state := session.state()
		for fid in [CROWN, CLANS]:
			seen[AscensionRules.branch(state, fid)] = AscensionRules.people_name(state, fid)
		var rec := session.record()
		var replayed := GameSession.replay(JSON.parse_string(JSON.stringify(rec)))
		assert_eq(replayed.errors, [])
		assert_eq(JSON.stringify(replayed.state.to_dict()), JSON.stringify(state.to_dict()), "%s: the replay is identical" % [pair])
		# A save made after the transformations loads identically.
		var save := SaveGame.make(session, {}, SaveGame.MANUAL, "test", 0)
		var restored := SaveGame.restore(JSON.parse_string(JSON.stringify(save)))
		assert_eq(restored.errors, [])
		assert_eq(JSON.stringify(restored.session.state().to_dict()), JSON.stringify(state.to_dict()), "%s: the save loads identically" % [pair])
	for branch_id in PathData.BRANCHES:
		assert_eq(String(seen.get(branch_id, "")), AscensionRules.branch_name(branch_id), "%s was reached" % branch_id)
	for t in ["transformed", "oath_sworn", "wild_spread", "path_healed"]:
		assert_true(int(_seen_types.get(t, 0)) > 0, "the replayed games include %s events: %s" % [t, _seen_types])
	assert_eq(int(_seen_types.get("transformed", 0)), 4, "each transformation once")


func test_the_simulator_flags_terrain_that_changes_without_the_wild() -> void:
	var s := _game()
	var r := _resolve(s)
	var tampered: GameState = r.new_state.deep_copy([])
	tampered.find_province("bloodfen").terrain = "forest"
	var found: Array = Simulator.check_invariants(s, tampered, r.events)
	assert_true(found.map(func(x): return x.check).has("terrain_changed"), "%s" % [found])
	for t in ["research_gained", "transformed", "wild_spread", "path_healed", "raided"]:
		assert_true(Simulator.PATH_EVENT_TYPES.has(t))


func test_codex_entries_for_every_rule_and_mandate_follow_the_m4_1_block() -> void:
	var keys := ["blood_levy", "raiding_parties", "forest_stride", "hallowed_land", "the_forges", "wild_spreads", "dread_lands"]
	for m in MandateData.PATH_MANDATES:
		keys.append(String(m.codex))
		assert_true(RulesCodex.text(m.codex).contains("%d power" % int(m.cost)), "%s states its cost" % m.id)
		assert_eq(String(RulesCodex.entry(m.codex).title), String(m.name))
		assert_true(m.sacrifice_only)
		assert_eq(AscensionRules.opening_node(m.id), String(m.path))
		assert_eq(String(AscensionRules.node_effects(String(m.path)).opens_mandate), String(m.id), "%s opens %s" % [m.path, m.id])
	for rid in PathData.PROVINCE_RULES:
		assert_true(keys.has(String(PathData.PROVINCE_RULES[rid].codex)))
	assert_true(keys.has(String(PathData.ECONOMY_RULES.beasts_oath_blood.codex)))
	for key in keys:
		assert_true(RulesCodex.ENTRIES.has(key), "codex entry %s" % key)
		assert_false(String(RulesCodex.text(key)).contains("_"), "%s: no raw id" % key)
	var all := RulesCodex.ENTRIES.keys()
	var start := all.find("bounty_of_the_wild") + 1
	assert_eq(all.slice(start, start + keys.size()), keys, "one block, directly after M4-1's")
	assert_true(RulesCodex.text("wild_spreads").contains("+%d defense" % int(AutoBattleResolver.TERRAIN.forest.defense)))
	assert_true(RulesCodex.text("blood_levy").contains(AscensionRules._fraction_word(int(AscensionRules.node_effects("beasts_oath_blood").blood_levy))))
	assert_true(RulesCodex.text("road_move").contains("Forest Stride"))


func test_without_paths_the_mandate_lists_and_checks_are_as_before() -> void:
	var s := GameState.with_rulers(7)
	for fid in [CROWN, CLANS]:
		assert_eq(RulerRules.available_mandates(fid, s), RulerRules.available_mandates(fid))
	assert_eq(MandateData.MANDATES.size(), 10, "the path mandates live in their own list")
	assert_eq(RulerRules.sacrifice_check(s, CROWN, RulerRules.HYMN_OF_DAWN).code, "mandate_not_open")
	assert_eq(AscensionRules.wild_spread_picks(s, CLANS, 2), [])
	assert_false(Forecast.province_rules(s, CROWN).ok)


# --- the map (headless): the Wild Spreads sprout, heal notes and Forest Stride destinations ------------

func test_the_map_marks_the_wild_the_heals_and_forest_stride_destinations() -> void:
	var s := _wild_board(["wildmoor", "ironspike", "blackwood", "deepwood", "bloodfen"])
	s = AscensionRules.with_nodes(s, CLANS, ["beasts_forest_stride"])
	s.find_army("beasts-2").location = "bloodfen"
	s.find_army("beasts-2").units[0].current_hp = 1
	var screen: MapScreen = load("res://ui/map_screen.tscn").instantiate()
	screen.set_state(s, CLANS)
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	var picks := _pick_ids(AscensionRules.wild_spread_picks(s, CLANS))
	assert_eq(picks.size(), 1)
	for id in screen.regions:
		var marked: bool = screen.regions[id].wild_marker != null
		assert_eq(marked, picks.has(id), "%s: the sprout marks exactly the province that grows" % id)
	var mark: Control = screen.regions[picks[0]].wild_marker
	assert_true(mark.tooltip_text.replace("\n", " ").contains("turns to forest at the end of this turn"), mark.tooltip_text)
	screen.select_army("beasts-2")
	var region: ProvinceRegion = screen.regions["wildmoor"]
	assert_true(region.road_target, "Forest Stride reaches Wildmoor through Deepwood")
	assert_true(region.tooltip_text.replace("\n", " ").contains("Forest Stride: the selected army can reach this province this turn through Deepwood"), region.tooltip_text)
	screen.get_parent().remove_child(screen)
	screen.free()
	# Hallowed Land's heal note on the wounded army's badge.
	var c := _transformed(CROWN, "celestial_host", 7, {CROWN: "warrior_king"})
	c.find_army("kingdom-1").units[0].current_hp = 1
	var crown_screen: MapScreen = load("res://ui/map_screen.tscn").instantiate()
	crown_screen.set_state(c, CROWN)
	(Engine.get_main_loop() as SceneTree).root.add_child(crown_screen)
	var badge := crown_screen.regions["crownkeep"].army_box.get_node_or_null("Army_kingdom-1") as Button
	assert_true(badge != null)
	assert_true(badge.tooltip_text.replace("\n", " ").contains("Hallowed Land: 1 wounded fighter heal"), badge.tooltip_text)
	crown_screen.get_parent().remove_child(crown_screen)
	crown_screen.free()
