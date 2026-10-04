extends "res://tests/test_case.gd"
## M4-1 (#66), design/M4_ASCENSION.md §3.2, §3.4, §9.2: the path's number effects. Stat parts in
## RulerRules.unit_stats / unit_max_hp (and the §3.4 hp rule for units on the map), income lines in
## province_income_parts (Market Charters, Tithe of Light, Deep Mines, Bounty of the Wild), price parts
## (Remount Stables, Living Iron), all in Breakdown, summing to the totals the resolver uses. Plus the
## codex entries and the Paths tick box. Expected numbers come from data, never typed in.

const CROWN := "kingdom"
const CLANS := "beasts"


func _game(seed_value: int = 7, builds: Dictionary = {}) -> GameState:
	var s := GameState.with_paths(seed_value, builds, [])
	assert_true(s != null, "a game with paths starts")
	return s


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


# --- stat parts (acceptance: in unit_stats and Breakdown, summing to the totals) ---------------------

func test_every_unit_effect_is_a_named_part_in_unit_stats_and_breakdown() -> void:
	var checked := 0
	var expected := 0
	for fid in [CROWN, CLANS]:
		for nid in AscensionRules.node_ids(fid):
			var units: Dictionary = AscensionRules.node_effects(nid).get("unit", {})
			for type_id in units:
				expected += units[type_id].size()
				var plain := _game()
				var s := AscensionRules.with_nodes(plain, fid, [nid])
				var before := RulerRules.unit_stats(plain, fid, type_id)
				var after := RulerRules.unit_stats(s, fid, type_id)
				for stat in units[type_id]:
					var value := int(units[type_id][stat])
					assert_eq(int(after[stat]), int(before[stat]) + value, "%s: %s %s" % [nid, type_id, stat])
					var part: Array = after.mods[stat].filter(func(m): return m.get("key", "") == "path_" + nid)
					assert_eq(part.size(), 1, "%s: one named part on %s" % [nid, stat])
					assert_eq(int(part[0].value), value)
					assert_eq(String(part[0].name), AscensionRules.node_name(nid))
					assert_eq(String(part[0].mandate), "", "a path part names no mandate (AutoBattleResolver reads it safely)")
					var b := Breakdown.unit_stat(s, fid, type_id, stat)
					assert_eq(int(b.total), int(after[stat]), "%s %s: the breakdown total" % [type_id, stat])
					assert_eq(Breakdown.sum_of_lines(b), int(b.total), "%s %s: the lines add up" % [type_id, stat])
					var labels: Array = b.lines.map(func(l): return l.label)
					assert_true(labels.has(AscensionRules.node_name(nid)), "%s: the breakdown names %s" % [stat, AscensionRules.node_name(nid)])
					assert_eq(b.codex, "path_node")
					checked += 1
	assert_eq(checked, expected, "every stat each node changes (cost included)")
	assert_true(expected >= 12)


func test_path_parts_stack_with_mandates_and_skip_commanders() -> void:
	# Regent's Court has Royal Armories (+1 attack); Drillyard and the Celestial Host add hp and morale.
	var s := AscensionRules.with_nodes(_game(7, {CROWN: "regents_court"}), CROWN,
		["crown_drillyard", "crown_charters", "crown_arbalests", "crown_oath_dawn", "crown_celestial_host"])
	var spear := _type(s, CROWN, "spearmen")
	var us := RulerRules.unit_stats(s, CROWN, "spearmen")
	assert_eq(us.hp, spear.hp + 3 + 2, "Max hp = Spearmen 8 + Drillyard 3 + Celestial Host 2")
	assert_eq(us.morale, spear.morale + 2, "Morale = Spearmen 6 + Celestial Host 2")
	var hp := Breakdown.unit_stat(s, CROWN, "spearmen", "hp")
	assert_eq(hp.lines.map(func(l): return l.label), ["Spearmen", "Drillyard", "Celestial Host"])
	var xbow := RulerRules.unit_stats(s, CROWN, "crossbowmen")
	var keys: Array = xbow.mods.attack.map(func(m): return m.key)
	assert_eq(keys, ["mandate_royal_armories", "path_crown_arbalests"], "the mandate's part, then the path's")
	assert_eq(xbow.attack, _type(s, CROWN, "crossbowmen").attack + 1 + 2)
	var captain := RulerRules.unit_stats(s, CROWN, "knight_captain")
	assert_eq([captain.hp, captain.attack, captain.morale], [s.find_faction(CROWN).commander_type.hp,
		s.find_faction(CROWN).commander_type.attack, s.find_faction(CROWN).commander_type.morale], "commanders get no path parts")
	# unit_max_hp agrees with unit_stats, for the units on the map too.
	for u in _units_of(s, CROWN, "spearmen"):
		assert_eq(RulerRules.unit_max_hp(s, u), us.hp)
	# Without paths there are no path parts and no morale changes.
	var m2 := RulerRules.unit_stats(GameState.with_rulers(7, {CROWN: "regents_court"}), CROWN, "spearmen")
	assert_eq(m2.morale, spear.morale)
	for stat in m2.mods:
		for m in m2.mods[stat]:
			assert_false(String(m.get("key", "")).begins_with("path_"), "no path part without paths")


func test_units_on_the_map_change_at_once_by_the_hp_rule() -> void:
	# §3.4: a part raising max hp raises current hp by as much; one lowering it lowers it, never below 1.
	# (The Warrior King: no Mending Light to heal the wounded Spearmen in the same turn.)
	var s := _game(7, {CROWN: "warrior_king"})
	var spears := _units_of(s, CROWN, "spearmen")
	spears[0].current_hp = 5
	s.find_faction(CROWN).research_points = 10
	var r := TurnResolver.resolve(s, {CROWN: [ResearchOrder.new("crown_drillyard")]}, 1)
	var after: GameState = r.new_state
	var spear := _type(after, CROWN, "spearmen")
	var now := _units_of(after, CROWN, "spearmen")
	assert_eq(now[0].current_hp, 5 + 3, "a wounded Spearmen gains 3 hit points")
	assert_eq(RulerRules.unit_max_hp(after, now[0]), spear.hp + 3)
	var done: Array = r.events.filter(func(e): return e.type == "research_done")
	assert_eq(int(done[0].numbers.units_changed), spears.size())
	assert_true(String(done[0].text).contains("already on the map gained %d hit points in all" % (3 * spears.size())), done[0].text)
	# The Blood Pact lowers Tuskers' max hp (by 4 since M4-6): full ones lose as much, nobody drops below 1.
	var drop := -int(AscensionRules.node_effects("beasts_blood_pact").unit.tuskers.hp)
	assert_true(drop > 0, "the Blood Pact lowers Tuskers' maximum hp")
	var b := AscensionRules.with_nodes(_game(), CLANS, ["beasts_boar_hide", "beasts_raiding", "beasts_oath_blood"])
	var tuskers := _units_of(b, CLANS, "tuskers")
	assert_eq(tuskers[0].current_hp, _type(b, CLANS, "tuskers").hp + 3, "Boar Hide raised them by 3")
	var full: int = tuskers[0].current_hp
	var applied := AscensionRules.apply_node(b, CLANS, "beasts_blood_pact", 1)
	assert_eq(tuskers[0].current_hp, full - drop)
	assert_eq(int(applied.hp_total), -drop * tuskers.size())
	var c := AscensionRules.with_nodes(_game(), CLANS, ["beasts_boar_hide", "beasts_raiding", "beasts_oath_blood"])
	var hurt: Unit = _units_of(c, CLANS, "tuskers")[0]
	hurt.current_hp = 2
	AscensionRules.apply_node(c, CLANS, "beasts_blood_pact", 1)
	assert_eq(hurt.current_hp, 1, "never below 1")
	# Recruits arrive at the new maximum.
	var rec := _game()
	rec.find_faction(CROWN).research_points = 10
	var t1: GameState = TurnResolver.resolve(rec, {CROWN: [ResearchOrder.new("crown_drillyard")]}, 3).new_state
	var t2: GameState = TurnResolver.resolve(t1, {CROWN: [RecruitOrder.new("spearmen")]}, 4).new_state
	var newest: Unit = _units_of(t2, CROWN, "spearmen").back()
	assert_eq(newest.current_hp, RulerRules.unit_max_hp(t2, newest), "a recruit arrives at the new maximum")
	assert_eq(newest.current_hp, _type(t2, CROWN, "spearmen").hp + 3)


func test_battles_run_with_path_parts_with_and_without_mandates() -> void:
	# AutoBattleResolver reads unit_stats' parts (M4-3 explains path parts in the "why"); a path part names
	# no mandate, so a battle with path parts runs cleanly whether or not the faction owns a mandate.
	for build in ["regents_court", "warrior_king"]:
		var s := AscensionRules.with_nodes(_game(7, {CROWN: build}), CROWN, ["crown_drillyard", "crown_arbalests"])
		var crown: Army = null
		var clans: Army = null
		for a in s.armies:
			if a.ruler == null and a.owner == CROWN:
				crown = a
			elif a.ruler == null and a.owner == CLANS:
				clans = a
		crown.location = "highcrag"
		clans.location = "thornvale"
		var r := TurnResolver.resolve(s, {CLANS: [MoveOrder.new(clans.id, "highcrag")]}, 9)
		assert_true(r.new_state != null, "%s: the turn resolves" % build)
		var battles: Array = r.events.filter(func(e): return e.type == "battle")
		assert_eq(battles.size(), 1, "%s: the armies fought" % build)
		var battle_log: Dictionary = battles[0].numbers.get("log", {})
		assert_false(battle_log.is_empty(), "%s: the battle has its event log" % build)


# --- income lines (acceptance: in province_income_parts and Breakdown, summing to the totals) -------

func test_income_lines_are_named_parts_that_the_income_phase_pays() -> void:
	var cases := [
		[CROWN, ["crown_charters"], ["crownkeep", "rivermarch", "westwatch"]],
		[CROWN, ["crown_drillyard", "crown_charters", "crown_oath_dawn"], ["crownkeep", "rivermarch", "highcrag"]],
		[CROWN, ["crown_drillyard", "crown_charters", "crown_oath_forge"], ["westwatch", "stonegate", "greenglade", "rivermarch"]],
		[CLANS, ["beasts_boar_hide", "beasts_raiding", "beasts_oath_grove"], ["deepwood", "wildmoor", "bloodfen"]],
	]
	for c in cases:
		var fid: String = c[0]
		var s := AscensionRules.with_nodes(_game(), fid, c[1])
		for pid in c[2]:
			s.find_province(pid).owner = fid
		var owned := 0
		for p in s.provinces:
			if p.owner == fid:
				owned += 1
		var expected_total := 0
		for p in s.provinces:
			if p.owner != fid:
				continue
			var parts := RulerRules.province_income_parts(s, p.id)
			var want := p.income
			for nid in c[1]:
				var fx := AscensionRules.node_effects(nid)
				var by_terrain: Dictionary = fx.get("income_terrain", {})
				want += int(by_terrain.get(p.terrain, 0))
				if fx.has("tithe_per_province") and p.id == s.find_faction(fid).capital:
					want += int(fx.tithe_per_province) * owned
			assert_eq(int(parts.total), maxi(0, want), "%s with %s: the income" % [p.name, c[1]])
			var b := Breakdown.province_income(s, p.id)
			assert_eq(int(b.total), int(parts.total))
			assert_eq(Breakdown.sum_of_lines(b), int(b.total), "%s: the lines add up" % p.name)
			for m in parts.mods:
				if String(m.key).begins_with("path_"):
					assert_true(b.lines.map(func(l): return l.label).has(m.name), "%s: the breakdown names %s" % [p.name, m.name])
					assert_false(String(b.description).contains("_"), "no raw id: %s" % b.description)
			expected_total += int(parts.total)
		var inc := TurnResolver.income_of(s, fid)
		assert_eq(int(inc.total), expected_total)
		assert_eq(int(Breakdown.income(s, fid).total), expected_total)
		assert_eq(Breakdown.sum_of_lines(Breakdown.gold(s, fid)), s.find_faction(fid).gold + expected_total)
		var r := TurnResolver.resolve(s, {}, 5)
		var gold_before := s.find_faction(fid).gold
		assert_eq(r.new_state.find_faction(fid).gold, gold_before + expected_total, "the income phase pays exactly that")
		var ev: Array = r.events.filter(func(e): return e.type == "income" and e.factions.has(fid))
		assert_true(String(ev[0].text).contains("That includes"), "the income event names the path lines: %s" % ev[0].text)
		assert_false(String(ev[0].text).ends_with(" "), "no stray space")


func test_the_spec_income_examples() -> void:
	# §9.2: "Income of Crownkeep = base 12 + Tithe of Light 7 (7 provinces)", "Income of Westwatch 10 = base 6 + Deep Mines 4"
	# (M4-6: Deep Mines +4 on hills, and no longer anything on forests).
	var dawn := AscensionRules.with_nodes(_game(), CROWN, ["crown_drillyard", "crown_charters", "crown_oath_dawn"])
	for pid in ["westwatch", "highcrag", "rivermarch", "stonegate", "greenglade", "thornvale"]:
		dawn.find_province(pid).owner = CROWN
	var cap := RulerRules.province_income_parts(dawn, "crownkeep")
	var tithe: Array = cap.mods.filter(func(m): return m.name == "Tithe of Light")
	assert_eq(int(tithe[0].value), 7, "Tithe of Light +7 for 7 provinces")
	assert_eq(tithe[0].codex, "tithe_of_light")
	var charters: Array = cap.mods.filter(func(m): return m.name == "Market Charters")
	assert_eq(int(charters[0].value), 2, "Crownkeep is plains")
	var forge := AscensionRules.with_nodes(_game(), CROWN, ["crown_drillyard", "crown_charters", "crown_oath_forge"])
	forge.find_province("westwatch").owner = CROWN
	forge.find_province("greenglade").owner = CROWN
	var mines: Dictionary = AscensionRules.node_effects("crown_oath_forge").income_terrain
	var ww := RulerRules.province_income_parts(forge, "westwatch")
	assert_eq(int(ww.total), forge.find_province("westwatch").income + int(mines.hills))
	assert_eq(ww.mods[0].name, "Deep Mines")
	var gg := RulerRules.province_income_parts(forge, "greenglade")
	var on_forest := int(mines.get("forest", 0))
	assert_eq(int(gg.total), forge.find_province("greenglade").income + on_forest, "forests earn %d" % on_forest)
	if on_forest < 0:
		# A province never earns less than 0: a line makes up the difference.
		forge.find_province("greenglade").income = 0
		var floor := RulerRules.province_income_parts(forge, "greenglade")
		assert_eq(int(floor.total), 0)
		var b := Breakdown.province_income(forge, "greenglade")
		assert_eq(Breakdown.sum_of_lines(b), 0)
	else:
		assert_eq(gg.mods, [], "no Deep Mines line on a forest")
	# A neutral province, or another faction's, gets nothing from your path.
	assert_eq(RulerRules.province_income_parts(forge, "thornvale").mods, [])


# --- price parts (acceptance: in unit_stats and Breakdown; the recruitment phase charges them) -------

func test_price_parts_change_what_recruits_cost() -> void:
	var knights_cost := _type(_game(), CROWN, "knights").cost
	var stables := AscensionRules.with_nodes(_game(), CROWN, ["crown_charters", "crown_stables"])
	var k := _type(stables, CROWN, "knights")
	assert_eq(RulerRules.recruit_price(stables, CROWN, k), knights_cost - 4)
	assert_eq(RulerRules.price_text(stables, CROWN, k), "%d gold (%d - Remount Stables 4)" % [knights_cost - 4, knights_cost])
	assert_eq(TurnResolver.recruit_cost(stables, CROWN, "knights"), knights_cost - 4)
	var rise := int(AscensionRules.node_effects("crown_living_iron").unit.knights.cost)
	var iron := AscensionRules.with_nodes(_game(), CROWN, ["crown_drillyard", "crown_charters", "crown_oath_forge", "crown_living_iron"])
	assert_eq(RulerRules.price_text(iron, CROWN, k), "%d gold (%d + Living Iron %d)" % [knights_cost + rise, knights_cost, rise])
	var both := AscensionRules.with_nodes(stables, CROWN, ["crown_oath_forge", "crown_living_iron"])
	assert_eq(RulerRules.recruit_price(both, CROWN, k), knights_cost - 4 + rise, "Remount Stables and the Iron Knights' price rise add up")
	var b := Breakdown.unit_stat(both, CROWN, "knights", "cost")
	assert_eq(int(b.total), knights_cost - 4 + rise)
	assert_eq(Breakdown.sum_of_lines(b), knights_cost - 4 + rise)
	assert_eq(b.lines.map(func(l): return l.label), ["Knights", "Remount Stables", "Living Iron"])
	# With Muster Grounds: a fifth of the base price, then the path's part.
	var muster := AscensionRules.with_nodes(_game(7, {CROWN: {"ruler": "aurel_king", "mandates": ["muster_grounds"]}}), CROWN,
		["crown_charters", "crown_stables"])
	assert_eq(RulerRules.recruit_price(muster, CROWN, k), knights_cost - floori(knights_cost / 5.0) - 4)
	# The recruitment phase charges it.
	var r := TurnResolver.resolve(stables, {CROWN: [RecruitOrder.new("knights")]}, 2)
	var rec: Array = r.events.filter(func(e): return e.type == "recruited")
	assert_eq(int(rec[0].numbers.cost), knights_cost - 4)
	# Commanders and other units are untouched.
	assert_eq(RulerRules.recruit_price(stables, CROWN, stables.find_faction(CROWN).commander_type),
		stables.find_faction(CROWN).commander_type.cost)


# --- the codex (§9.3: research and paths) ------------------------------------------------------------

func test_codex_entries_cover_research_paths_and_every_node() -> void:
	var keys := ["research", "research_points", "research_order", "research_phase", "path", "path_node", "fork", "oath",
		"lock_in", "transformation", "forsworn", "path_kingdom", "path_beasts", "tithe_of_light", "deep_mines", "bounty_of_the_wild"]
	for fid in [CROWN, CLANS]:
		for nid in AscensionRules.node_ids(fid):
			keys.append("node_" + nid)
			assert_eq(String(RulesCodex.entry("node_" + nid).title), AscensionRules.node_name(nid))
			var text := RulesCodex.text("node_" + nid)
			assert_true(text.contains("%d research" % AscensionRules.node_cost(nid)), "%s states its cost" % nid)
			assert_true(text.contains(AscensionRules.kind_name(nid)), "%s states its kind" % nid)
			for r in AscensionRules.node_data(nid).requires:
				assert_true(text.contains(AscensionRules.node_name(r)), "%s names what it needs" % nid)
		assert_eq(String(RulesCodex.entry(AscensionRules.path_data(fid).codex).title), RulerRules._cap(AscensionRules.path_name(fid)))
	for key in keys:
		assert_true(RulesCodex.ENTRIES.has(key), "codex entry %s" % key)
		var e := RulesCodex.entry(key)
		assert_false(String(e.text).contains("_"), "%s: no raw id in the text" % key)
		assert_ne(String(e.title), key)
	# One contiguous block near the end of the entries (M4-2's rule entries follow it directly).
	var all := RulesCodex.ENTRIES.keys()
	var first := all.find(keys[0])
	var tail := all.slice(first, first + keys.size())
	for key in keys:
		assert_true(tail.has(key), "%s is in the M4-1 block" % key)
	# The numbers match the data.
	assert_true(RulesCodex.text("research_points").contains("your capital yields %d while you hold it, and every other province %d" % [
		PathData.RESEARCH.capital, PathData.RESEARCH.province]))
	assert_true(RulesCodex.text("phase_order").contains("research resolves between income and rulers"))
	for key in ["tithe_of_light", "deep_mines", "bounty_of_the_wild"]:
		assert_true(PathData.ECONOMY_RULES.values().map(func(r): return r.codex).has(key))


func test_no_raw_ids_in_research_text() -> void:
	var s := AscensionRules.with_nodes(_game(), CROWN, ["crown_drillyard"])
	s.find_faction(CROWN).research_points = 40
	s.find_faction(CLANS).research_points = 40
	var texts := []
	for fid in [CROWN, CLANS]:
		for nid in AscensionRules.node_ids(fid):
			var reason := String(AscensionRules.node_state(s, fid, nid).reason)
			if not reason.is_empty():  # available nodes need no reason
				texts.append(reason)
			texts.append(Forecast.research(s, fid, [], nid).text)
			texts.append(AscensionRules.part_rule(nid))
		texts.append(AscensionRules.research_rate(s, fid).text)
		texts.append(Breakdown.research_rate(s, fid).description)
		texts.append(Breakdown.research_progress(s, fid).description)
	var turn := s
	var orders := {CROWN: [ResearchOrder.new("crown_charters")], CLANS: [ResearchOrder.new("beasts_boar_hide")]}
	for t in 4:
		var r := TurnResolver.resolve(turn, orders, t)
		turn = r.new_state
		for e in r.events:
			texts.append(e.text)
		orders = {CROWN: [ResearchOrder.new("crown_oath_forge")], CLANS: [ResearchOrder.new("beasts_raiding")]} if t == 0 \
			else {CLANS: [ResearchOrder.new("beasts_oath_blood")]}
	for text in texts:
		assert_false(String(text).is_empty(), "no empty text")
		assert_false(String(text).contains("_"), "no raw id in: %s" % text)


# --- the Paths tick box (§1.3) -----------------------------------------------------------------------

func test_the_paths_box_needs_rulers_and_starts_a_game_with_paths() -> void:
	var screen := load("res://ui/new_game_screen.tscn").instantiate() as NewGameScreen
	assert_false(screen.paths_on(), "off by default")
	assert_false(screen.config().has("paths"))
	screen.set_paths(true)
	assert_true(screen.paths_on())
	assert_true(screen.rulers_on(), "ticking Paths ticks Rulers")
	assert_eq(screen.config().get("paths"), true)
	assert_eq(screen.config().get("rulers"), true)
	screen.set_rulers(false)
	assert_false(screen.paths_on(), "clearing Rulers clears Paths")
	assert_false(screen.config().has("paths"))
	screen.prefill({"players": [CROWN, CLANS], "seed": 5, "rulers": true, "paths": true})
	assert_true(screen.paths_on(), "a rematch of a game with paths has paths")
	assert_true(String(screen.paths_toggle.tooltip_text).contains("Paths of ascension"), "the tooltip links the codex")
	screen.free()
	var s := GameScreen.starting_state({"players": [CROWN, CLANS], "seed": 5, "rulers": true, "paths": true})
	assert_true(s.paths)
	assert_true(RulerRules.has_rulers(s))
	assert_false(GameScreen.starting_state({"players": [CROWN, CLANS], "seed": 5, "rulers": true}).paths)
