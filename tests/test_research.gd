extends "res://tests/test_case.gd"
## M4-1 (#66), design/M4_ASCENSION.md §1.3, §2, §3: research and the path rules model. Opt-in setup, the
## path data, every node's legality with plain reasons, the research rate after captures and Sworn Vassals,
## the pool (nothing lost), the research phase and its events, the fork lock and the Oath's auto-target,
## research orders, forecast equals result for every node, round trips and replays. Expected numbers come
## from data/paths.gd, never typed in.

const CROWN := "kingdom"
const CLANS := "beasts"


# --- fixtures -------------------------------------------------------------------------------------

func _game(seed_value: int = 7, builds: Dictionary = {}) -> GameState:
	var errors := []
	var s := GameState.with_paths(seed_value, builds, errors)
	assert_true(s != null, "a game with paths starts: %s" % ", ".join(errors))
	return s


## The faction's node ids of `kind`, in data order.
func _kind(fid: String, kind: String) -> Array:
	var out := []
	for nid in AscensionRules.node_ids(fid):
		if AscensionRules.node_kind(nid) == kind:
			out.append(nid)
	return out


## Gives `fid` these provinces (no armies move).
func _give(s: GameState, fid: String, pids: Array) -> void:
	for pid in pids:
		s.find_province(pid).owner = fid


## The provinces next to each capital, in map order.
func _home(fid: String) -> Array:
	return ["westwatch", "highcrag", "rivermarch"] if fid == CROWN else ["ebonpeak", "ironspike", "bloodfen"]


func _resolve(s: GameState, orders: Dictionary = {}) -> Dictionary:
	var r := TurnResolver.resolve(s, orders, TurnResolver.seed_for_turn(s))
	assert_true(r.new_state != null, "the turn resolves: %s" % ", ".join(r.get("errors", [])))
	return r


func _events(events: Array, type: String, fid: String = "") -> Array:
	return events.filter(func(e): return e.type == type and (fid.is_empty() or e.factions.has(fid)))


## The prerequisites that make `nid` legal: its requires, two tier I nodes for an Oath, and the Oath plus
## two tier I nodes for a transformation.
func _prereqs(fid: String, nid: String) -> Array:
	var n := AscensionRules.node_data(nid)
	var out := []
	if int(n.requires_any) > 0 or AscensionRules.node_kind(nid) == PathData.TRANSFORMATION:
		out.append_array(_kind(fid, PathData.TIER1))
	for r in n.requires:
		if not out.has(r):
			out.append(r)
	return out


# --- setup: opt-in, needs rulers (§1.3) ------------------------------------------------------------

func test_paths_are_opt_in_and_need_rulers() -> void:
	assert_false(GameState.new(3).paths, "the M1 game has no paths")
	assert_false(GameState.with_rulers(3).paths, "the M2 game has no paths")
	var s := _game(3)
	assert_true(s.paths)
	assert_true(AscensionRules.has_paths(s))
	for f in s.factions:
		assert_true(f.has_ruler(), "%s has a ruler: paths need rulers" % f.faction_name)
		assert_eq([f.research_points, f.research_target, f.researched, f.path_branch], [0, "", [], ""])
	var m1 := GameState.new(3)
	var errors := []
	assert_false(m1.setup_paths(errors), "paths can't be set up without rulers")
	assert_true(String(errors[0]).contains("Paths need rulers"), errors[0])
	assert_false(m1.paths, "nothing changed")
	var late := GameState.with_rulers(3)
	late.current_turn = 2
	errors = []
	assert_false(late.setup_paths(errors))
	assert_true(String(errors[0]).contains("before the game starts"), errors[0])
	# An illegal build still fails as in with_rulers.
	errors = []
	assert_eq(GameState.with_paths(3, {CROWN: {"ruler": "nobody"}}, errors), null)
	assert_false(errors.is_empty())


# --- the path data (§3.1, §3.5, §3.6) --------------------------------------------------------------

func test_each_path_has_the_shape_of_section_3_1() -> void:
	for fid in [CROWN, CLANS]:
		var ids := AscensionRules.node_ids(fid)
		assert_eq(ids.size(), 8, "%s: 8 nodes" % fid)
		var t1 := _kind(fid, PathData.TIER1)
		var t2 := _kind(fid, PathData.TIER2)
		var oaths := _kind(fid, PathData.OATH)
		var forms := _kind(fid, PathData.TRANSFORMATION)
		assert_eq([t1.size(), t2.size(), oaths.size(), forms.size()], [2, 2, 2, 2])
		var names := {}
		for nid in ids:
			var n := AscensionRules.node_data(nid)
			assert_false(names.has(n.name), "%s: names are unique" % n.name)
			names[n.name] = true
			assert_true(RulesCodex.ENTRIES.has(String(n.codex)), "%s has its codex entry %s" % [n.name, n.codex])
			assert_false(String(n.text).is_empty(), "%s has a one-line effect" % n.name)
		for nid in t1:
			assert_eq(AscensionRules.node_data(nid).requires, [], "tier I has no prerequisite")
		for nid in t2:
			var req: Array = AscensionRules.node_data(nid).requires
			assert_eq(req.size(), 1, "tier II needs one node")
			assert_true(t1.has(req[0]), "tier II needs a tier I node")
		assert_true(AscensionRules.node_data(t2[0]).requires != AscensionRules.node_data(t2[1]).requires,
			"each tier II node needs a different tier I node")
		var sides := []
		for oath in oaths:
			var n := AscensionRules.node_data(oath)
			assert_eq(int(n.requires_any), 2, "an Oath needs any two ordinary nodes")
			var side := String(n.branch)
			sides.append(side)
			assert_eq(String(AscensionRules.branch_data(side).faction), fid)
			assert_eq(String(AscensionRules.branch_data(side).oath), oath)
			var form := String(AscensionRules.branch_data(side).transformation)
			assert_true(forms.has(form))
			assert_eq(AscensionRules.node_data(form).requires, [oath], "a transformation needs its own Oath")
			assert_eq(String(AscensionRules.node_data(form).branch), side)
		assert_eq(AscensionRules.other_branch(fid, sides[0]), sides[1])
		assert_eq(AscensionRules.other_branch(fid, sides[1]), sides[0])
		# A full path: the four ordinary nodes, one Oath and its transformation.
		var full := 0
		for nid in t1 + t2:
			full += AscensionRules.node_cost(nid)
		full += AscensionRules.node_cost(oaths[0]) + AscensionRules.node_cost(forms[0])
		assert_eq(full, 100, "%s: the full path is 100 research (§3.1)" % fid)
	assert_eq(PathData.RESEARCH, {"capital": 5, "province": 1}, "§2.1")


func test_path_stat_parts_follow_the_breakpoint_rule() -> void:
	# §3.2: attack parts are always +2; defense parts land on 4k or 4k+1 counting Shield Wall.
	for fid in [CROWN, CLANS]:
		var f := GameState.new(1).find_faction(fid)
		for nid in AscensionRules.node_ids(fid):
			var units: Dictionary = AscensionRules.node_effects(nid).get("unit", {})
			for type_id in units:
				var ut := TurnResolver.recruitable_type(f, type_id)
				assert_true(ut != null and not ut.is_commander, "%s changes a regular unit of its faction" % AscensionRules.node_name(nid))
				if units[type_id].has("attack"):
					assert_eq(int(units[type_id].attack), 2, "%s: attack parts are +2" % AscensionRules.node_name(nid))
					assert_eq((ut.attack + 2) % 2, 1, "attack stays odd")
				if units[type_id].has("defense"):
					var d: int = ut.defense + int(units[type_id].defense)
					var wall := AutoBattleResolver.SHIELD_WALL_DEFENSE if ut.trait_id == AutoBattleResolver.SHIELD_WALL else 0
					assert_true((d + wall) % 4 <= 1, "%s: defense %d lands on 4k or 4k+1" % [AscensionRules.node_name(nid), d + wall])


# --- every node's legality, with plain reasons (acceptance) -----------------------------------------

func test_every_nodes_legality_is_checked_with_plain_reasons() -> void:
	for fid in [CROWN, CLANS]:
		var t1 := _kind(fid, PathData.TIER1)
		var t2 := _kind(fid, PathData.TIER2)
		var oaths := _kind(fid, PathData.OATH)
		var forms := _kind(fid, PathData.TRANSFORMATION)
		var other := CLANS if fid == CROWN else CROWN
		var tier2_of := {}  # tier II -> its tier I
		for nid in t2:
			tier2_of[nid] = String(AscensionRules.node_data(nid).requires[0])
		var rows := []
		# [researched before, node, state, code, words the reason must contain]
		for nid in t1:
			rows.append([[], nid, AscensionRules.AVAILABLE, "", []])
		for nid in t2:
			rows.append([[], nid, AscensionRules.NEEDS, "needs_prerequisite",
				["%s needs %s first" % [AscensionRules.node_name(nid), AscensionRules.node_name(tier2_of[nid])],
				"costs %d research" % AscensionRules.node_cost(tier2_of[nid]), "you have 0 and gain 5 a turn"]])
			rows.append([[tier2_of[nid]], nid, AscensionRules.AVAILABLE, "", []])
		for oath in oaths:
			rows.append([[], oath, AscensionRules.NEEDS, "needs_two", ["needs any 2 of the 4 ordinary nodes", "researched none yet"]])
			rows.append([[t1[0]], oath, AscensionRules.NEEDS, "needs_two", ["researched 1: %s" % AscensionRules.node_name(t1[0])]])
			rows.append([t1, oath, AscensionRules.AVAILABLE, "", []])  # any two: both tier I
			rows.append([[t1[0], t2[0] if tier2_of[t2[0]] == t1[0] else t2[1]], oath, AscensionRules.AVAILABLE, "", []])  # a tier I and its tier II
		for i in forms.size():
			var oath := String(AscensionRules.node_data(forms[i]).requires[0])
			rows.append([t1, forms[i], AscensionRules.NEEDS, "needs_prerequisite", ["needs the %s first" % AscensionRules.node_name(oath)]])
			rows.append([t1 + [oath], forms[i], AscensionRules.AVAILABLE, "", []])
			# Swearing one Oath closes the other Oath and its transformation; ordinary nodes stay open.
			var other_oath: String = oaths[1] if oaths[0] == oath else oaths[0]
			var other_form := String(AscensionRules.branch_data(String(AscensionRules.node_data(other_oath).branch)).transformation)
			for closed in [other_oath, other_form]:
				rows.append([t1 + [oath], closed, AscensionRules.CLOSED, "closed",
					["Closed: you swore the %s on turn" % AscensionRules.node_name(oath), "for the rest of the game"]])
			for open in t2:
				rows.append([t1 + [oath], open, AscensionRules.AVAILABLE, "", []])
		for nid in AscensionRules.node_ids(fid):
			rows.append([[nid] if _prereqs(fid, nid).is_empty() else _prereqs(fid, nid) + [nid], nid, AscensionRules.RESEARCHED,
				"already_researched", ["%s is already researched" % RulerRules._cap(AscensionRules.node_ref(nid))]])
		rows.append([[], AscensionRules.node_ids(other)[0], AscensionRules.CLOSED, "foreign_node", ["on the path of the"]])
		rows.append([[], "no_such_node", AscensionRules.CLOSED, "unknown_node", ["'no_such_node' is not something to research"]])
		for row in rows:
			var s := AscensionRules.with_nodes(_game(), fid, row[0])
			var st := AscensionRules.node_state(s, fid, row[1])
			var what := "%s after %s" % [row[1], row[0]]
			assert_eq(st.state, row[2], "%s: state" % what)
			assert_eq(st.code, row[3], "%s: code" % what)
			for words in row[4]:
				assert_true(String(st.reason).contains(words), "%s: the reason says '%s': %s" % [what, words, st.reason])
			var check := AscensionRules.check_research(s, fid, row[1])
			assert_eq(check.is_empty(), row[2] == AscensionRules.AVAILABLE, "%s: check_research agrees" % what)
			if row[3] != "unknown_node":
				assert_false(String(st.reason).contains("_"), "%s: no raw id in the reason: %s" % [what, st.reason])
	# The current target reads "researching"; a game without paths has nothing to research.
	var s := _game()
	AscensionRules.set_target(s, CROWN, "crown_drillyard")
	assert_eq(AscensionRules.node_state(s, CROWN, "crown_drillyard").state, AscensionRules.RESEARCHING)
	assert_true(AscensionRules.check_research(s, CROWN, "crown_drillyard").is_empty(), "the target stays legal")
	var plain := AscensionRules.check_research(GameState.with_rulers(7), CROWN, "crown_drillyard")
	assert_eq(plain.code, "no_paths")
	assert_true(String(plain.reason).contains("Paths (M4 preview)"), plain.reason)


func test_the_spec_example_reason_reads_as_written() -> void:
	# §2.2: "Arbalests needs Drillyard first. Drillyard costs 10 research; you have 4 and gain 7 a turn."
	var s := _game()
	_give(s, CROWN, ["westwatch", "highcrag"])
	s.find_faction(CROWN).research_points = 4
	assert_eq(AscensionRules.node_state(s, CROWN, "crown_arbalests").reason,
		"Arbalests needs Drillyard first. Drillyard costs 10 research; you have 4 and gain 7 a turn.")


# --- the research rate (acceptance: 5 + other provinces after captures and Sworn Vassals) ----------

func test_research_rate_is_the_capital_plus_one_per_other_province() -> void:
	var s := _game()
	for fid in [CROWN, CLANS]:
		var r := AscensionRules.research_rate(s, fid)
		assert_eq(r.rate, PathData.RESEARCH.capital, "the capital alone")
		_give(s, fid, _home(fid))
		r = AscensionRules.research_rate(s, fid)
		assert_eq(r.rate, PathData.RESEARCH.capital + 3 * PathData.RESEARCH.province)
		var b := Breakdown.research_rate(s, fid)
		assert_eq(int(b.total), r.rate)
		assert_eq(Breakdown.sum_of_lines(b), r.rate, "the breakdown lines add up")
		assert_eq(b.codex, "research_points")
	# A capital you don't hold yields nothing (§2.1).
	s.find_province("crownkeep").owner = CLANS
	var lost := AscensionRules.research_rate(s, CROWN)
	assert_false(lost.capital_held)
	assert_eq(lost.rate, 3 * PathData.RESEARCH.province)
	assert_true(String(lost.parts[0].note).contains("not held"))
	assert_eq(AscensionRules.research_rate(GameState.with_rulers(7), CROWN).rate, 0, "no research without paths")


func test_the_research_phase_counts_provinces_after_captures_and_sworn_vassals() -> void:
	# The Clans have Sworn Vassals (Clan Moot), so a neutral province joins them in the capture phase.
	var s := _game(11, {CLANS: "clan_moot"})
	var crown_army := ""
	for a in s.armies:
		if a.owner == CROWN and a.ruler == null:
			crown_army = a.id
	var r := _resolve(s, {CROWN: [MoveOrder.new(crown_army, "westwatch")], CLANS: []})
	var after: GameState = r.new_state
	assert_false(_events(r.events, "captured", CROWN).is_empty(), "the Crown captured Westwatch")
	assert_false(_events(r.events, "vassal_joined", CLANS).is_empty(), "a vassal joined the Clans")
	for fid in [CROWN, CLANS]:
		var owned := 0
		for p in after.provinces:
			if p.owner == fid:
				owned += 1
		var gained := _events(r.events, "research_gained", fid)
		assert_eq(gained.size(), 1, "one research_gained event per faction")
		assert_eq(int(gained[0].numbers.gained), PathData.RESEARCH.capital + (owned - 1) * PathData.RESEARCH.province,
			"%s gained 5 + its other provinces, counted after this turn's captures" % fid)
		assert_eq(after.find_faction(fid).research_points, int(gained[0].numbers.gained))


# --- the pool: nothing is ever lost (acceptance) -----------------------------------------------------

func test_spare_points_are_never_lost_when_the_target_changes() -> void:
	# Both tier I nodes are done, so the targets cost 15 or 20 and the pool can grow while they change.
	var s := AscensionRules.with_nodes(_game(5), CROWN, _kind(CROWN, PathData.TIER1))
	var plan := ["crown_arbalests", "crown_stables", "crown_oath_dawn", "crown_oath_forge", "", "crown_living_iron"]
	var gained_total := 0
	var spent := 0
	var changes := 0
	var pool := 0
	for order_node in plan:
		var orders: Array = [] if order_node.is_empty() else [ResearchOrder.new(order_node)]
		var target := AscensionRules.research_target(s, CROWN)
		if not order_node.is_empty() and not target.is_empty() and target != order_node:
			changes += 1
		assert_eq(s.find_faction(CROWN).research_points, pool, "changing the target moved nothing")
		var r := _resolve(s, {CROWN: orders, CLANS: []})
		assert_true(_events(r.events, "order_rejected", CROWN).is_empty(), "every order in the plan is legal")
		var g: Dictionary = _events(r.events, "research_gained", CROWN)[0]
		gained_total += int(g.numbers.gained)
		var done := _events(r.events, "research_done", CROWN) + _events(r.events, "oath_sworn", CROWN)
		var cost := 0
		for e in done:
			cost += int(e.numbers.cost)
		spent += cost
		s = r.new_state
		assert_eq(s.find_faction(CROWN).research_points, pool + int(g.numbers.gained) - cost, "the pool only gains, and pays for what is done")
		pool = s.find_faction(CROWN).research_points
	assert_eq(changes, 3, "the target changed three times before anything was done")
	assert_eq(AscensionRules.researched(s, CROWN).slice(2), ["crown_oath_forge"], "then the Oath was done")
	assert_eq(AscensionRules.research_target(s, CROWN), "crown_living_iron", "and its transformation is the target")
	assert_eq(s.find_faction(CROWN).research_points + spent, gained_total, "every point gained is in the pool or paid for a node")
	# Points gained with no target stay in the pool too.
	var idle := _game(5)
	for i in 3:
		idle = _resolve(idle).new_state
	assert_eq(idle.find_faction(CLANS).research_points, 3 * PathData.RESEARCH.capital)


# --- the research phase, its events, the fork lock and the Oath's auto-target ----------------------

func test_one_node_a_turn_with_leftovers_carried_over() -> void:
	var s := _game()
	s.find_faction(CROWN).research_points = 100
	var r := _resolve(s, {CROWN: [ResearchOrder.new("crown_drillyard")]})
	var after: GameState = r.new_state
	var f := after.find_faction(CROWN)
	assert_eq(AscensionRules.researched(after, CROWN), ["crown_drillyard"], "only the target is done")
	assert_eq(f.research_points, 100 + PathData.RESEARCH.capital - AscensionRules.node_cost("crown_drillyard"))
	assert_eq(f.research_target, "", "the target is empty after an ordinary node")
	assert_eq(AscensionRules.researched_turn(after, CROWN, "crown_drillyard"), 1, "done at the end of turn 1")
	# The next turn with no new order: nothing more is done, the pool keeps growing.
	var r2 := _resolve(after)
	assert_eq(AscensionRules.researched(r2.new_state, CROWN), ["crown_drillyard"])
	assert_eq(r2.new_state.find_faction(CROWN).research_points, f.research_points + PathData.RESEARCH.capital)


func test_research_events_come_after_income_and_before_rulers() -> void:
	var s := _game()
	s.find_faction(CROWN).research_points = 9
	var r := _resolve(s, {CROWN: [ResearchOrder.new("crown_drillyard")]})
	var phases := []
	for e in r.events:
		assert_true(TurnResolver.PATH_PHASES.has(e.phase), "%s: phase %s is a phase of a game with paths" % [e.type, e.phase])
		assert_true(GameSession.PATH_REPORT_PHASES.has(e.phase))
		phases.append(TurnResolver.PATH_PHASES.find(e.phase))
	var sorted := phases.duplicate()
	sorted.sort()
	assert_eq(phases, sorted, "events come in phase order")
	assert_eq(TurnResolver.PATH_PHASES.find("research"), TurnResolver.PATH_PHASES.find("income") + 1)
	assert_eq(TurnResolver.PATH_PHASES.find("rulers"), TurnResolver.PATH_PHASES.find("research") + 1)
	var gained := _events(r.events, "research_gained")
	assert_eq(gained.size(), 2, "one research_gained per faction")
	assert_eq(gained[0].factions, [CLANS], "factions in id order")
	assert_eq(gained[1].factions, [CROWN])
	var done := _events(r.events, "research_done", CROWN)
	assert_eq(done.size(), 1)
	assert_eq(done[0].codex, "node_crown_drillyard")
	assert_true(String(done[0].text).begins_with("Drillyard researched: the Aurel Crown's Spearmen now have"), done[0].text)
	var spear := TurnResolver.recruitable_type(s.find_faction(CROWN), "spearmen")
	assert_true(String(done[0].text).contains("%d maximum hit points (was %d)" % [spear.hp + 3, spear.hp]), done[0].text)
	assert_eq(String(gained[1].text), "The Aurel Crown gained 5 research (Crownkeep 5, 0 other provinces 0).")


func test_swearing_an_oath_locks_the_fork_and_targets_its_transformation() -> void:
	for fid in [CROWN, CLANS]:
		for oath in _kind(fid, PathData.OATH):
			var s := AscensionRules.with_nodes(_game(), fid, _kind(fid, PathData.TIER1))
			s.find_faction(fid).research_points = 50
			var r := _resolve(s, {fid: [ResearchOrder.new(oath)]})
			var after: GameState = r.new_state
			var side := String(AscensionRules.node_data(oath).branch)
			var form := String(AscensionRules.branch_data(side).transformation)
			var other := AscensionRules.other_branch(fid, side)
			assert_eq(AscensionRules.branch(after, fid), side, "%s swears its side" % oath)
			assert_eq(AscensionRules.research_target(after, fid), form, "its transformation becomes the target at once")
			assert_false(AscensionRules.has_node(after, fid, form), "but it is not done the same turn")
			for closed in [String(AscensionRules.branch_data(other).oath), String(AscensionRules.branch_data(other).transformation)]:
				assert_eq(AscensionRules.node_state(after, fid, closed).state, AscensionRules.CLOSED, "%s is closed" % closed)
			var sworn := _events(r.events, "oath_sworn", fid)
			assert_eq(sworn.size(), 1, "an Oath makes an oath_sworn event")
			assert_true(_events(r.events, "research_done", fid).is_empty(), "and no research_done")
			var text := String(sworn[0].text)
			for words in [AscensionRules.node_name(oath), AscensionRules.branch_name(side), AscensionRules.branch_name(other),
					"for the rest of the game", "Researching next: %s, about" % AscensionRules.node_name(form)]:
				assert_true(text.contains(words), "the sworn text says '%s': %s" % [words, text])
			assert_false(text.contains("_"), "no raw id: %s" % text)
			assert_eq(sworn[0].numbers.branch, side)
			assert_eq(sworn[0].numbers.closed, other)
			assert_eq(AscensionRules.closed_reason(after, fid).begins_with("Closed: you swore the %s on turn 1" % AscensionRules.node_name(oath)), true)
	# §5's example sentence for the Oath of the Dawn with seven provinces.
	var s := AscensionRules.with_nodes(_game(), CROWN, _kind(CROWN, PathData.TIER1))
	_give(s, CROWN, ["westwatch", "highcrag", "rivermarch", "stonegate", "greenglade", "thornvale"])
	s.find_faction(CROWN).research_points = 20
	var r := _resolve(s, {CROWN: [ResearchOrder.new("crown_oath_dawn")]})
	var rate := 5 + 6
	var left := 20 + rate - 20
	var n := AscensionRules.eta(30, left, rate)
	assert_eq(String(_events(r.events, "oath_sworn", CROWN)[0].text),
		"The Aurel Crown swore the Oath of the Dawn and set out to become the Celestial Host. Living Iron is closed to them for the rest of the game. Tithe of Light: Crownkeep now earns 1 more gold for every province they own (+7 now). Researching next: Celestial Host, about %d turns." % n)


func test_the_research_target_is_private() -> void:
	var s := _game()
	var r := _resolve(s, {CROWN: [ResearchOrder.new("crown_charters")]})
	for e in r.events:
		assert_false(String(e.text).contains("Market Charters"), "no event names an unfinished target: %s" % e.text)
		assert_false(JSON.stringify(e.numbers).contains("crown_charters"), "nor its numbers")
	assert_eq(AscensionRules.research_target(r.new_state, CROWN), "crown_charters", "but the target is set")


# --- research orders (§2.2) -------------------------------------------------------------------------

func test_research_orders_save_load_and_replace_each_other() -> void:
	var o := ResearchOrder.new("crown_drillyard")
	assert_eq(o.to_dict(), {"type": "research", "node": "crown_drillyard"})
	var back = OrderBook.order_from_dict(JSON.parse_string(JSON.stringify(o.to_dict())))
	assert_true(back is ResearchOrder, "loads as a ResearchOrder")
	assert_eq(back.node_id, "crown_drillyard")
	var errors := []
	assert_eq(OrderBook.order_from_dict({"type": "pray"}, errors), null)
	assert_true(String(errors[0]).contains("'research'"), errors[0])
	var s := _game()
	var book := OrderBook.new()
	assert_eq(book.submit(s, CROWN, ResearchOrder.new("crown_drillyard")), "")
	assert_eq(book.submit(s, CROWN, ResearchOrder.new("crown_charters")), "", "a second research order replaces the first")
	var orders := book.orders_for(CROWN)
	assert_eq(orders.size(), 1)
	assert_eq(orders[0].node_id, "crown_charters")
	assert_eq(book.last_dropped().size(), 1)
	assert_eq(String(book.last_dropped()[0].text), "Research Drillyard replaced: you chose Market Charters instead.")
	var why := book.submit(s, CROWN, ResearchOrder.new("crown_arbalests"))
	assert_true(why.begins_with("Arbalests needs Drillyard first."), why)
	assert_eq(book.orders_for(CROWN).size(), 1, "a rejected order replaces nothing")
	assert_true(book.submit(GameState.with_rulers(7), CROWN, ResearchOrder.new("crown_drillyard")).contains("no paths"))
	# A list with two research orders (not from an OrderBook): the second is rejected in the orders phase.
	var r := _resolve(s, {CROWN: [ResearchOrder.new("crown_drillyard"), ResearchOrder.new("crown_charters")]})
	var rejected := _events(r.events, "order_rejected", CROWN)
	assert_eq(rejected.size(), 1)
	assert_eq(rejected[0].cause, "second_research")
	assert_eq(rejected[0].codex, "research_order")
	assert_eq(AscensionRules.research_target(r.new_state, CROWN), "crown_drillyard")
	# Without paths a research order is rejected with the reason, and nothing else changes.
	var m2 := _resolve(GameState.with_rulers(7), {CROWN: [ResearchOrder.new("crown_drillyard")]})
	assert_eq(_events(m2.events, "order_rejected", CROWN)[0].cause, "no_paths")
	assert_true(_events(m2.events, "research_gained").is_empty(), "no research events without paths")


func test_the_session_queues_and_describes_research_orders() -> void:
	var s := _game()
	var session := GameSession.new(s, [CROWN, CLANS], 7)
	assert_eq(session.queue_research("crown_drillyard"), "")
	var lines := session.current_order_texts()
	assert_eq(lines.size(), 1)
	var fc := Forecast.research(s, CROWN, [ResearchOrder.new("crown_drillyard")])
	assert_eq(String(lines[0]), "Research Drillyard next (%d research, done at the end of turn %d)." % [fc.cost, fc.done_turn])
	assert_eq(session.queue_research("crown_charters"), "")
	assert_eq(session.current_orders().size(), 1, "one research order per turn")
	assert_eq(session.removed_orders(), ["Research Drillyard replaced: you chose Market Charters instead."])
	assert_true(session.queue_research("crown_oath_dawn").contains("needs any 2"))


# --- forecast equals result (acceptance) -------------------------------------------------------------

func test_forecast_eta_and_done_turn_equal_the_turn_each_node_completes() -> void:
	var checked := 0
	for fid in [CROWN, CLANS]:
		var ids := AscensionRules.node_ids(fid)
		for i in ids.size():
			var nid := String(ids[i])
			for variant in 2:
				var s := AscensionRules.with_nodes(_game(20 + i), fid, _prereqs(fid, nid))
				_give(s, fid, _home(fid).slice(0, (i + variant) % 4))
				var cost := AscensionRules.node_cost(nid)
				s.find_faction(fid).research_points = (i * 7 + variant * 11) % cost
				var order := ResearchOrder.new(nid)
				var start_turn := s.current_turn
				var fc := Forecast.research(s, fid, [order])
				assert_true(fc.ok, "%s can be researched: %s" % [nid, fc.reason])
				assert_eq(fc.target, nid)
				var as_card := Forecast.research(s, fid, [], nid)
				assert_eq([as_card.eta, as_card.done_turn], [fc.eta, fc.done_turn], "the card's 'if researched next' ETA agrees")
				assert_eq(fc.done_turn, s.current_turn + fc.eta)
				var turn_done := 0
				var then_done := 0
				var orders := {fid: [order]}
				for t in 12:
					var r := _resolve(s, orders)
					orders = {}  # every army holds; the target persists
					s = r.new_state
					var done := _events(r.events, "research_done", fid) + _events(r.events, "oath_sworn", fid)
					for e in done:
						if e.numbers.node == nid:
							turn_done = int(e.numbers.turn)
						elif not fc.then.is_empty() and e.numbers.node == fc.then.node:
							then_done = int(e.numbers.turn)
					if turn_done > 0 and (fc.then.is_empty() or then_done > 0):
						break
				assert_eq(turn_done, fc.done_turn, "%s (pool %d, rate %d): done at the end of the forecast turn" % [nid,
					fc.pool, fc.rate])
				assert_eq(fc.eta, turn_done - start_turn, "the ETA counts the first turn as 1")
				if not fc.then.is_empty():
					assert_eq(then_done, int(fc.then.done_turn), "%s: its transformation is done when forecast" % nid)
				checked += 1
	assert_eq(checked, 32, "every node of both paths, twice")


func test_forecast_text_and_the_progress_breakdown() -> void:
	var s := AscensionRules.with_nodes(_game(), CROWN, ["crown_drillyard"])
	_give(s, CROWN, ["westwatch", "highcrag", "rivermarch", "stonegate"])
	s.find_faction(CROWN).research_points = 12
	s.find_faction(CROWN).research_target = "crown_arbalests"
	var fc := Forecast.research(s, CROWN)
	assert_eq(fc.target, "crown_arbalests", "the current target by default")
	assert_eq(fc.eta, 1)
	assert_eq(fc.carry, 12 + 9 - 15)
	var xbow := int(RulerRules.unit_stats(s, CROWN, "crossbowmen").attack)  # with the build's Royal Armories
	assert_eq(String(fc.text), "Arbalests: 12 of 15 research. You gain 9 a turn (Crownkeep 5, 4 other provinces 4), so it is done at the end of this turn. From turn 2, your Crossbowmen have %d attack. Capturing or losing a province changes the pace by 1 a turn." % (xbow + 2))
	var b := Breakdown.research_progress(s, CROWN)
	assert_eq(int(b.total), 12 + 9)
	assert_eq(Breakdown.sum_of_lines(b), int(b.total))
	assert_true(String(b.description).begins_with("Arbalests needs 15, so it is done at the end of turn 1 and 6 carry over."), b.description)
	# No target: what is waiting. An Oath: what it closes, and the transformation after it ("about").
	s.find_faction(CROWN).research_target = ""
	assert_eq(String(Forecast.research(s, CROWN).text), "Choose what to research: 12 research is waiting, and you gain 9 a turn (Crownkeep 5, 4 other provinces 4).")
	var both := AscensionRules.with_nodes(s, CROWN, ["crown_charters"])
	var oath := Forecast.research(both, CROWN, [], "crown_oath_forge")
	assert_true(String(oath.text).contains("Swearing it closes the Celestial Host for the rest of the game"), oath.text)
	assert_true(String(oath.text).contains("Living Iron then needs 30 more: about turn %d." % int(oath.then.done_turn)), oath.text)
	var bad := Forecast.research(s, CROWN, [], "crown_stables")
	assert_false(bad.ok)
	assert_true(String(bad.text).begins_with("Remount Stables needs Market Charters first."), bad.text)
	# Path complete: everything researched or closed.
	var done := AscensionRules.with_nodes(_game(), CROWN, ["crown_drillyard", "crown_charters", "crown_arbalests", "crown_stables",
		"crown_oath_dawn", "crown_celestial_host"])
	assert_true(AscensionRules.path_complete(done, CROWN))
	assert_true(String(Forecast.research(done, CROWN).text).begins_with("Path complete"))


# --- saving, loading and replaying (acceptance) -------------------------------------------------------

func _researched_state() -> GameState:
	var s := _game(9)
	s.current_turn = 6
	var f := s.find_faction(CROWN)
	f.researched = [{"node": "crown_drillyard", "turn": 2}, {"node": "crown_charters", "turn": 4},
		{"node": "crown_oath_forge", "turn": 6}]
	f.path_branch = "living_iron"
	f.research_target = "crown_living_iron"
	f.research_points = 13
	s.find_faction(CLANS).research_points = 4
	s.find_faction(CLANS).research_target = "beasts_raiding"
	assert_true(s.validate([]), "the hand-made state is valid")
	return s


func test_round_trips_keep_every_new_field() -> void:
	var s := _researched_state()
	var d := s.to_dict()
	assert_eq(d.paths, true)
	var fd: Dictionary = d.factions[0] if d.factions[0].id == CROWN else d.factions[1]
	assert_eq(fd.research_points, 13)
	assert_eq(fd.research_target, "crown_living_iron")
	assert_eq(fd.researched, [{"node": "crown_drillyard", "turn": 2}, {"node": "crown_charters", "turn": 4},
		{"node": "crown_oath_forge", "turn": 6}])
	assert_eq(fd.path_branch, "living_iron")
	var errors := []
	var back := GameState.from_dict(d, errors)
	assert_true(back != null, ", ".join(errors))
	assert_eq(back.to_dict(), d, "to_dict / from_dict")
	var json := GameState.from_dict(JSON.parse_string(JSON.stringify(d)), errors)
	assert_true(json != null, ", ".join(errors))
	assert_eq(JSON.stringify(json.to_dict()), JSON.stringify(d), "a JSON round trip")
	assert_eq(s.deep_copy().to_dict(), d, "deep_copy")
	assert_true(json.paths)
	assert_eq(AscensionRules.researched(json, CROWN), ["crown_drillyard", "crown_charters", "crown_oath_forge"])
	assert_eq(AscensionRules.researched_turn(json, CROWN, "crown_charters"), 4)
	assert_eq(AscensionRules.branch(json, CROWN), "living_iron")


func test_bad_research_data_fails_to_load_with_plain_reasons() -> void:
	var cases := [
		["the Aurel Crown has research", func(d): d.erase("paths"), "has research, but this game has no paths"],
		["a node of the other path", func(d): _crown(d).researched.append({"node": "beasts_raiding", "turn": 6}), "not on its path"],
		["twice", func(d): _crown(d).researched.append({"node": "crown_drillyard", "turn": 6}), "twice"],
		["without its prerequisite", func(d): _crown(d).researched.append({"node": "crown_celestial_host", "turn": 6}), "without the Oath of the Dawn before it"],
		["two oaths", func(d): _crown(d).researched.append({"node": "crown_oath_dawn", "turn": 6}), "two Oaths"],
		["wrong branch", func(d): _crown(d).path_branch = "celestial_host", "but its Oaths say it swore to Living Iron"],
		["closed target", func(d): _crown(d).research_target = "crown_celestial_host", "researching something it can't"],
		["future turn", func(d): _crown(d).researched[0].turn = 9, "out of order"],
		["negative pool", func(d): _crown(d).research_points = -2, "never below 0"],
		["wrong type", func(d): _crown(d).research_target = 5, "'research_target' field"],
		["paths without rulers", func(d): _strip_rulers(d), "paths need rulers"],
	]
	for c in cases:
		var d := _researched_state().to_dict()
		c[1].call(d)
		var errors := []
		var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)), errors)
		assert_eq(back, null, "%s: rejected" % c[0])
		var all := " ".join(errors)
		assert_true(all.contains(c[2]), "%s: the reason says '%s': %s" % [c[0], c[2], all])


func _crown(d: Dictionary) -> Dictionary:
	for f in d.factions:
		if f.id == CROWN:
			return f
	return {}


func _strip_rulers(d: Dictionary) -> void:
	for f in d.factions:
		for key in ["ruler_type", "kept_power", "mandates", "ruler_generation", "ruler_status", "successor_turn",
				"successor_power", "sacrifices"]:
			f.erase(key)
	var kept := []
	for a in d.armies:
		if not a.has("ruler"):
			kept.append(a)
	d.armies = kept


func test_a_recorded_game_with_research_replays_to_an_identical_state() -> void:
	var s := _game(13)
	var session := GameSession.new(s, [CROWN, CLANS], 13)
	var done := 0
	for turn in 14:
		for fid in [CROWN, CLANS]:
			if session.phase() == GameSession.Phase.HANDOFF:
				session.acknowledge_handoff()
			var view := session.state()
			var next := AscensionRules.available_nodes(view, fid)
			if AscensionRules.research_target(view, fid).is_empty() and not next.is_empty():
				assert_eq(session.queue_research(String(next[turn % next.size()])), "")
			session.end_turn()
		for e in session.turn_report().events:
			if e.type == "research_done" or e.type == "oath_sworn":
				done += 1
	assert_true(done >= 6, "nodes were researched along the way (%d)" % done)
	var rec := session.record()
	var replayed := GameSession.replay(JSON.parse_string(JSON.stringify(rec)))
	assert_eq(replayed.errors, [])
	assert_eq(JSON.stringify(replayed.state.to_dict()), JSON.stringify(session.state().to_dict()),
		"the replay after a JSON round trip reaches the same state")
	assert_true(replayed.state.paths)
	var history_text := JSON.stringify(rec.history)
	assert_true(history_text.contains("\"type\":\"research\""), "research orders are in the history")
