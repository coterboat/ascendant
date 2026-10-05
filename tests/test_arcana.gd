extends "res://tests/test_case.gd"
## M5-5 (#116) acceptance, the arcana (design/M5_MAGIC_FOG.md §4, §3.2): each faction's magic research through
## AscensionRules (node legality, its own kinds, the Oath gate on tier III), ETA equals completion, the mage gate
## opening on the first spell, and research sold for gold only when nothing is left, and only in magic games.

const CROWN := "kingdom"
const CLANS := "beasts"


func _magic(builds: Dictionary = {}) -> GameState:
	var s := GameState.with_magic(7, builds)
	assert_true(s != null, "the magic game starts")
	return s


func _state_of(s: GameState, fid: String, nid: String) -> Dictionary:
	return AscensionRules.node_state(s, fid, nid)


func test_node_legality_through_the_research_rules() -> void:
	var s := _magic()
	for fid in [CROWN, CLANS]:
		for school in MagicRules.schools(fid):
			var nodes: Array = MagicData.SCHOOLS[school].nodes
			assert_eq(String(_state_of(s, fid, nodes[0]).state), AscensionRules.AVAILABLE, "%s: tier I is open from the start" % nodes[0])
			var t2 := _state_of(s, fid, nodes[1])
			assert_eq(String(t2.state), AscensionRules.NEEDS)
			assert_true(String(t2.reason).begins_with("%s needs %s first." % [AscensionRules.node_name(nodes[1]), AscensionRules.node_name(nodes[0])]), t2.reason)
			assert_eq(String(_state_of(s, fid, nodes[2]).state), AscensionRules.NEEDS, "mastery needs the ritual")
			assert_eq(String(_state_of(s, fid, nodes[3]).state), AscensionRules.NEEDS, "the greater working needs the ritual and the Oath")
			assert_eq(AscensionRules.kind_name(nodes[0]), "tier I spell")
			assert_eq(AscensionRules.kind_name(nodes[2]), "mastery")
			assert_eq(AscensionRules.kind_name(nodes[3]), "tier III greater working")
			assert_true(AscensionRules.is_arcana(nodes[0]))
			assert_false(AscensionRules.is_ordinary(nodes[0]), "arcana nodes are not ordinary path nodes")
	# The path's own rules are untouched: node_ids and path_complete count path nodes only.
	assert_false(AscensionRules.node_ids(CROWN).any(func(n): return AscensionRules.is_arcana(String(n))))
	assert_eq(AscensionRules.arcana_ids(CROWN), MagicRules.arcana_ids(CROWN))
	assert_eq(AscensionRules.arcana_ids(CROWN).size(), 8)
	# A foreign node.
	assert_eq(String(_state_of(s, CROWN, "briar_snare").code), "foreign_node")
	# The Oath gate: swearing the Dawn opens Sunburst once Dawn Blessing is done, and closes Bastion.
	var dawn := AscensionRules.with_nodes(s, CROWN, ["crown_drillyard", "crown_charters", "crown_oath_dawn", "sunlance", "dawn_blessing",
		"shield_of_law", "sanctum_ward"])
	assert_eq(String(_state_of(dawn, CROWN, "sunburst").state), AscensionRules.AVAILABLE)
	var closed := _state_of(dawn, CROWN, "bastion")
	assert_eq(String(closed.state), AscensionRules.CLOSED)
	assert_true(String(closed.reason).contains("only the Oath of the Forge opens Bastion, the greater working of Law"), closed.reason)
	assert_eq(String(_state_of(dawn, CROWN, "sun_mastery").state), AscensionRules.AVAILABLE, "mastery nodes are outside the fork")
	# A research order for an arcana node is checked like any other.
	assert_eq(OrderBook.check_order(s, CROWN, ResearchOrder.new("sunlance"), []), {})
	assert_eq(String(OrderBook.check_order(s, CROWN, ResearchOrder.new("dawn_blessing"), []).code), "needs_prerequisite")
	# Researched arcana pass validation and round-trip; one researched out of order does not load.
	assert_true(dawn.validate([]))
	assert_eq(JSON.stringify(GameState.from_dict(JSON.parse_string(JSON.stringify(dawn.to_dict()))).to_dict()), JSON.stringify(dawn.to_dict()))
	var bad := AscensionRules.with_nodes(s, CROWN, ["dawn_blessing"])
	var errors := []
	assert_false(bad.validate(errors))
	assert_true(errors.any(func(e): return String(e).contains("without Sunlance before it")), str(errors))


func test_eta_equals_completion_for_an_arcana_node() -> void:
	for target in ["sunlance", "shield_of_law"]:
		var s := _magic()
		var orders := [ResearchOrder.new(target)]
		var fc := Forecast.research(s, CROWN, orders)
		assert_true(fc.ok, str(fc))
		assert_eq(String(fc.target), target)
		assert_eq(int(fc.cost), int(AscensionRules.node_cost(target)))
		var state := s
		var done_turn := 0
		var first := true
		while done_turn == 0 and state.current_turn < 20:
			var r := TurnResolver.resolve(state, {CROWN: orders} if first else {}, TurnResolver.seed_for_turn(state))
			first = false
			for e in r.events:
				if e.type == "research_done" and e.numbers.node == target:
					done_turn = int(e.numbers.turn)
					assert_eq(String(e.codex), String(MagicData.SPELLS[target].codex), "the event links the spell's entry")
					assert_false(String(e.text).contains("_"), "no raw id: %s" % e.text)
			state = r.new_state
		assert_eq(done_turn, int(fc.done_turn), "%s is done on the forecast turn" % target)
		assert_eq(MagicRules.known_spells(state, CROWN), [target])


func test_the_mage_gate_opens_on_the_first_spell() -> void:
	var s := _magic()
	for fid in [CROWN, CLANS]:
		var mage_id := String(MagicData.MAGES[fid].id)
		var mage := TurnResolver.recruitable_type(s.find_faction(fid), mage_id)
		assert_true(mage != null, "%s: the mage is on the roster from turn 1" % fid)
		assert_true(MagicRules.is_mage(mage))
		assert_eq(mage.cost, int(MagicData.MAGES[fid].cost))
		var check := TurnResolver.check_recruit(s, fid, RecruitOrder.new(mage_id), 1000)
		assert_eq(String(check.code), "mage_needs_spell")
		assert_eq(String(check.reason), MagicRules.mage_gate_reason(s, fid, mage))
		assert_eq(String(OrderBook.check_order(s, fid, RecruitOrder.new(mage_id), []).get("code", "")), "mage_needs_spell")
		var first := String(MagicData.SCHOOLS[MagicRules.schools(fid)[1]].nodes[0])  # the second school's spell opens it too
		var learned := AscensionRules.with_nodes(s, fid, [first])
		assert_eq(TurnResolver.check_recruit(learned, fid, RecruitOrder.new(mage_id), 1000), {}, "%s: open once %s is known" % [fid, first])
	assert_eq(MagicRules.mage_gate_reason(s, CROWN, TurnResolver.recruitable_type(s.find_faction(CROWN), "adepts")),
		"The Sunstone Adepts can be recruited once the Aurel Crown knows a spell. Research Sunlance or Shield of Law (10 research). The Ever-Regent's own Sunlance doesn't count.")
	# Researched at the end of a turn, recruited the next: the resolver agrees with the check, and the turn report
	# says the gate opened (§11.2's first spell).
	var r := TurnResolver.resolve(s, {CROWN: [ResearchOrder.new("sunlance")]}, 1)
	var state: GameState = r.new_state
	var done_events: Array = r.events.filter(func(e): return e.type == "research_done")
	while MagicRules.known_spells(state, CROWN).is_empty():
		var step := TurnResolver.resolve(state, {}, TurnResolver.seed_for_turn(state))
		done_events.append_array(step.events.filter(func(e): return e.type == "research_done"))
		state = step.new_state
	assert_eq(done_events.size(), 1)
	var line := String(done_events[0].text)
	var capital := state.find_province(state.find_faction(CROWN).capital).name
	assert_true(line.begins_with("Sunlance researched by the Aurel Crown: a battle spell of the Sun."), line)
	assert_true(line.contains("The Aurel Crown can now recruit Sunstone Adepts at %s, from turn %d." % [capital, int(done_events[0].numbers.turn) + 1]), line)
	var second := AscensionRules.with_nodes(state, CROWN, ["shield_of_law"])
	assert_false(MagicRules.done_text(second, CROWN, "shield_of_law", 3).contains("can now recruit"), "only the first spell opens the gate")
	assert_true(MagicRules.done_text(second, CROWN, "sun_mastery", 3).contains("+1 mastery in the Sun for every caster"))
	state.find_faction(CROWN).gold = 100
	var rec := TurnResolver.resolve(state, {CROWN: [RecruitOrder.new("adepts")]}, TurnResolver.seed_for_turn(state))
	assert_eq(rec.events.filter(func(e): return e.type == "recruited").size(), 1, "the Adepts are recruited")


func test_research_is_sold_only_when_nothing_is_left_and_only_with_magic() -> void:
	var path := ["crown_drillyard", "crown_charters", "crown_arbalests", "crown_stables", "crown_oath_dawn", "crown_celestial_host"]
	var arcana_but_one := ["sunlance", "dawn_blessing", "sun_mastery", "sunburst", "shield_of_law", "sanctum_ward"]
	var s := AscensionRules.with_nodes(_magic(), CROWN, path + arcana_but_one)
	assert_true(AscensionRules.path_complete(s, CROWN))
	assert_false(AscensionRules.all_complete(s, CROWN), "Law Mastery is left")
	s.find_faction(CROWN).research_points = 40
	var r := TurnResolver.resolve(s, {}, 1)
	assert_eq(r.events.filter(func(e): return e.type == "research_sold").size(), 0, "nothing is sold while a node is left")
	# With Law Mastery researched (Bastion is closed by the Dawn), nothing is left: the pool is sold.
	var done := AscensionRules.with_nodes(s, CROWN, ["law_mastery"])
	assert_true(AscensionRules.all_complete(done, CROWN))
	done.find_faction(CROWN).research_points = 0
	var gold := done.find_faction(CROWN).gold
	var r2 := TurnResolver.resolve(done, {}, 1)
	var sold: Array = r2.events.filter(func(e): return e.type == "research_sold")
	assert_eq(sold.size(), 1)
	var gained := int(AscensionRules.research_rate(done, CROWN).rate)
	var want := MagicRules.research_sold(gained)
	assert_eq(int(sold[0].numbers.gold), int(want.gold))
	assert_eq(int(sold[0].numbers.carried), int(want.left))
	assert_eq(String(sold[0].phase), "research")
	assert_eq(String(sold[0].codex), "research_sold")
	assert_eq(String(sold[0].text), MagicRules.sold_text(done, CROWN, want))
	assert_eq(r2.new_state.find_faction(CROWN).research_points, int(want.left), "the spare point is carried")
	var income := int(TurnResolver.income_of(done, CROWN).total)
	assert_eq(r2.new_state.find_faction(CROWN).gold, gold + income + int(want.gold), "the gold arrives in the research phase")
	# The research forecast and the chip say what happens to research now (MagicRules.research_sold, never redone).
	var fc := Forecast.research(done, CROWN)
	var next := MagicRules.research_sold(AscensionRules.research_points(done, CROWN) + int(AscensionRules.research_rate(done, CROWN).rate))
	assert_true(String(fc.text).contains("your scholars sell %d research for %d gold" % [int(next.research), int(next.gold)]), fc.text)
	assert_eq(String(PathView.chip(done, CROWN).text), "Research\nnothing left")
	assert_eq(PathView.needs_you(done, CROWN), "", "nothing left to choose")
	# Path complete but arcana left: the forecast points at the Magic tab, and the chip asks for a choice.
	assert_true(String(Forecast.research(s, CROWN).text).contains("choose a spell in the Magic tab"), Forecast.research(s, CROWN).text)
	# The same complete path in a game without magic sells nothing: research piles up as in M4.
	var m4 := AscensionRules.with_nodes(GameState.with_paths(7), CROWN, path)
	assert_true(AscensionRules.all_complete(m4, CROWN), "without magic, the path is everything")
	var r3 := TurnResolver.resolve(m4, {}, 1)
	assert_eq(r3.events.filter(func(e): return e.type == "research_sold").size(), 0, "nothing is sold without magic")
	assert_eq(r3.new_state.find_faction(CROWN).research_points, int(AscensionRules.research_rate(m4, CROWN).rate))
