extends "res://tests/test_case.gd"
## M5-1 (#112) acceptance, the view state (design/M5_MAGIC_FOG.md §2.7, §18): the proof that fog is a lens.
## On 20 seeded fog games (tests/fog_test_kit.gd), for both viewers:
## - snapshot: every third turn, FogTestKit.perturb_hidden changes everything hidden from the viewer (with its memory
##   and intel held fixed), and view_state is byte-identical afterwards, view notes included;
## - report: report_for, given the perturbed true states before and after a turn and the events renamed by the map,
##   gives a byte-identical report;
## - two-turn: the rival's orders varied in hidden ways only (FogTestKit.two_turn_variations; at least 5 variations
##   per game), and the viewer's next view, report, memory and intel are identical;
## - three-turn: a hidden recruit on turn 1 shifts the rival's army numbers, a visible recruit follows on turn 2, and
##   nothing the viewer has on turns 1 to 3 differs (the counter leak the spec's ritual case catches; rituals arrive
##   with M5-6, and a constructed magic state checks enchantment counters here);
## - one case for each of the four relaxed validation checks, for rivals only;
## - the serialized view holds no true rival id, gold, research, unknown mandate or enchantment counter;
## - view.deep_copy() round-trips;
## - Forecast.*, RulerRules.with_sacrifice, OrderBook.check_order, AIPlayer.plan_orders and AIPlayer._scratch_with all
##   run on views.

const Kit := preload("res://tests/fog_test_kit.gd")
const CROWN := "kingdom"
const CLANS := "beasts"


func _json(v) -> String:
	return JSON.stringify(v.to_dict() if v is GameState else v)


# --- the four indistinguishability tests (§2.7) --------------------------------------------------------

func test_snapshot_changing_anything_hidden_changes_no_view() -> void:
	var totals := {}
	var checks := 0
	for g in Kit.games():
		for i in g.turns.size():
			if i % 3 != 2 and i != g.turns.size() - 1:
				continue
			var t: Dictionary = g.turns[i]
			for v in Kit.SEATS:
				var base := FogRules.view_state(t.after, v, t.memory_after[v], t.intel_after[v])
				assert_eq(_json(base), _json(t.view_after[v]), "%s turn %d, %s: the session's view is view_state" % [g.name, t.turn, v])
				for k in 2:
					var p := Kit.perturb_hidden(t.after, v, hash([g.seed, t.turn, v, k]))
					assert_eq(p.errors, [], "%s turn %d, %s: the perturbed state is a valid game" % [g.name, t.turn, v])
					if p.state == null:
						continue
					assert_ne(_json(p.state), _json(t.after), "the truth did change")
					var view := FogRules.view_state(p.state, v, t.memory_after[v], t.intel_after[v])
					assert_eq(_json(view), _json(base), "%s turn %d, %s, perturbation %d: the view is byte-identical" % [g.name, t.turn, v, k])
					checks += 1
					for key in p.changed:
						totals[key] = int(totals.get(key, 0)) + int(p.changed[key])
	assert_true(checks >= 20 * 2 * 2 * 3, "at least three snapshot turns a game, both viewers, two perturbations each (%d)" % checks)
	# Not vacuous: every kind of hidden fact was changed somewhere.
	for key in ["veiled_armies", "glimpse_resplit", "glimpse_counts", "renamed", "gold", "research", "nodes", "mandates", "kept_power", "ruler_moved"]:
		assert_true(int(totals.get(key, 0)) > 0, "the perturbations changed %s (%d times)" % [key, int(totals.get(key, 0))])


func test_snapshot_in_clear_sight_and_hidden_construction() -> void:
	# A siege puts rival armies in clear sight: the besieged Crown sees the Clans' army at Crownkeep exactly, but not how
	# it is split into armies, its true ids, or a site the Clans build out of sight.
	var s := GameState.with_sieges(21, {}, {"rulers": true})
	s.setup_fog([])
	var clans := s.find_faction(CLANS)
	for a in s.armies:
		if a.owner == CLANS and a.ruler == null:
			a.location = "crownkeep"
			a.engines = 2
			for ut in clans.unit_types:
				a.units.append(Unit.new(ut, CLANS))
	s.current_turn = 3
	s.find_province("crownkeep").siege_since = 3
	for pid in ["ebonpeak", "bloodfen"]:
		s.find_province(pid).owner = CLANS  # land the Clans hold out of the Crown's sight, to build on
	assert_true(s.validate([]), "a siege at Crownkeep")
	var memory := FogRules.new_memory(s, CROWN)
	var intel := FogRules.new_intel(s, CROWN)
	var base := FogRules.view_state(s, CROWN, memory, intel)
	assert_eq(base.find_army("seen-beasts-crownkeep").seen.level, "clear")
	assert_eq(base.find_army("seen-beasts-crownkeep").engines, 2, "engines are seen in clear sight")
	assert_eq(base.find_province("crownkeep").siege_since, 3, "the siege is seen")
	var resplit := 0
	var works := 0
	for k in 12:
		var p := Kit.perturb_hidden(s, CROWN, 700 + k)
		assert_eq(p.errors, [])
		resplit += int(p.changed.clear_resplit)
		works += int(p.changed.works)
		assert_eq(_json(FogRules.view_state(p.state, CROWN, memory, intel)), _json(base), "perturbation %d" % k)
	assert_true(resplit > 0 and works > 0, "pools in clear sight were split again (%d) and hidden sites changed (%d)" % [resplit, works])


func test_report_changing_anything_hidden_changes_no_report() -> void:
	var checks := 0
	for g in Kit.games():
		for i in g.turns.size():
			if i % 3 != 1:
				continue
			var t: Dictionary = g.turns[i]
			for v in Kit.SEATS:
				var base := FogRules.report_for(t.events, v, t.before, t.after, t.memory_before[v], t.intel_before[v])
				assert_eq(JSON.stringify(base), JSON.stringify(t.report[v]), "%s turn %d, %s: the session's report is report_for" % [g.name, t.turn, v])
				var keep := Kit.shown_armies(t.events, v, t.before)
				var seed_value := hash([g.seed, t.turn, v, "report"])
				var pb := Kit.perturb_hidden(t.before, v, seed_value, keep)
				var pa := Kit.perturb_hidden(t.after, v, seed_value, keep)
				assert_eq(pb.errors + pa.errors, [], "%s turn %d, %s: both perturbed states are valid" % [g.name, t.turn, v])
				if pb.state == null or pa.state == null:
					continue
				var rename: Dictionary = pb.rename.duplicate()
				rename.merge(pa.rename)
				var events := Kit.rename_events(t.events, rename)
				var got := FogRules.report_for(events, v, pb.state, pa.state, t.memory_before[v], t.intel_before[v])
				assert_eq(JSON.stringify(got), JSON.stringify(base), "%s turn %d, %s: the report is byte-identical" % [g.name, t.turn, v])
				checks += 1
	assert_true(checks >= 20 * 2 * 3, "report checks ran (%d)" % checks)


func test_two_turn_varying_hidden_orders_changes_nothing_the_viewer_gets() -> void:
	for g in Kit.games():
		var ran := 0
		var tried := 0
		for t in g.turns:
			if ran >= 8:
				break
			var base_result := TurnResolver.resolve(t.before, t.orders, int(t.seed), AutoBattleResolver.new())
			assert_eq(Kit.to_json(base_result.new_state), Kit.to_json(t.after), "%s turn %d resolves again as it was played" % [g.name, t.turn])
			for v in Kit.SEATS:
				var rival := Kit.rival_of(v)
				var sight0 := FogRules.sight(t.before, v)
				var sight1 := FogRules.sight(base_result.new_state, v)
				var base := FogRules.turn_for(base_result.events, v, t.before, base_result.new_state, t.memory_before[v], t.intel_before[v])
				var facts := Kit.public_facts(base_result.new_state, base_result.events, v)
				for variation in Kit.two_turn_variations(t.before, v, t.orders[rival], sight0, sight1, t.intel_before[v]):
					tried += 1
					var orders := {v: t.orders[v], rival: variation.orders}
					var result := TurnResolver.resolve(t.before, orders, int(t.seed), AutoBattleResolver.new())
					if Kit.public_facts(result.new_state, result.events, v) != facts:
						continue  # it changed something public, or a battle the viewer saw: not a hidden variation
					if Kit.to_json(result.new_state) == Kit.to_json(base_result.new_state):
						continue  # it changed nothing at all
					var got := FogRules.turn_for(result.events, v, t.before, result.new_state, t.memory_before[v], t.intel_before[v])
					var what := "%s turn %d, %s, %s" % [g.name, t.turn, v, variation.what]
					assert_eq(JSON.stringify(got.events), JSON.stringify(base.events), "%s: the report" % what)
					assert_eq(JSON.stringify(got.memory), JSON.stringify(base.memory), "%s: the memory" % what)
					assert_eq(JSON.stringify(got.intel), JSON.stringify(base.intel), "%s: the intel" % what)
					assert_eq(_json(got.view_after), _json(base.view_after), "%s: the next view" % what)
					ran += 1
		assert_true(ran >= 5, "%s: at least 5 hidden variations ran (%d of %d tried)" % [g.name, ran, tried])


## The three-turn scenario (§2.7) on the M1 map. The Crown stands at Wildmoor with Spearmen and Crossbowmen (it sees 1);
## the Clans' capital, Fangridge, is two away and out of sight. Turn 1: the Clans march their army to Bloodfen (out of
## sight), and in variation A also recruit Tuskers at the empty capital, forming a new army. Turn 2: the Crown marches to
## Ironspike, next to Fangridge; A's new army slips away to Bloodfen; both variations recruit Fangthrowers at Fangridge,
## a new army whose true id is one higher in A. Turn 3: everyone holds. The Crown's views, reports, memory and intel
## must be identical on every turn, though the Fangthrowers it now glimpses have different true ids.
func _three_turns(hidden_recruit: bool) -> Array:
	var s := GameState.new(31)
	s.setup_fog([])
	var crown := s.find_army("kingdom-1")
	var keep := crown.units.filter(func(u): return u.type.id == "spearmen" or u.type.id == "crossbowmen")
	crown.units.clear()
	for u in keep:
		crown.units.append(u)
	crown.commander = null
	crown.location = "wildmoor"
	s.find_province("wildmoor").owner = CROWN
	assert_true(s.validate([]), "the scenario starts valid")
	var session := GameSession.new(s, [CROWN, CLANS], 31, AutoBattleResolver.new())
	var plan := [
		{CROWN: [], CLANS: [MoveOrder.new("beasts-1", "bloodfen")] + ([RecruitOrder.new("tuskers")] if hidden_recruit else [])},
		{CROWN: [MoveOrder.new("kingdom-1", "ironspike")],
			CLANS: ([MoveOrder.new("beasts-2", "bloodfen")] if hidden_recruit else []) + [RecruitOrder.new("fangthrowers")]},
		{CROWN: [], CLANS: []},
	]
	var out := []
	for turn in plan:
		for fid in [CROWN, CLANS]:
			if session.phase() == GameSession.Phase.HANDOFF:
				session.acknowledge_handoff()
			for o in turn[fid]:
				assert_eq(session.queue_order(o), "", "the scripted order is legal")
			session.end_turn()
		out.append({"view": _json(session.state_for(CROWN)), "before": _json(session.view_before(CROWN)),
			"report": JSON.stringify(session.turn_report_for(CROWN).events), "memory": JSON.stringify(session.memory(CROWN)),
			"intel": JSON.stringify(session.intel(CROWN)), "truth": session.state()})
	return out


func test_three_turn_a_hidden_counter_never_shows() -> void:
	var a := _three_turns(true)
	var b := _three_turns(false)
	# The truth differs: A's Fangthrowers are a later army, and A spent more gold.
	var ids_a: Array = a[2].truth.armies.filter(func(x): return x.owner == CLANS and x.location == "fangridge").map(func(x): return x.id)
	var ids_b: Array = b[2].truth.armies.filter(func(x): return x.owner == CLANS and x.location == "fangridge").map(func(x): return x.id)
	assert_eq(ids_a, ["beasts-3"], "A: the visible army is the Clans' 3rd")
	assert_eq(ids_b, ["beasts-2"], "B: the visible army is the Clans' 2nd")
	assert_true(String(a[2].view).contains("seen-beasts-fangridge"), "the Crown glimpses the Fangthrowers at Fangridge")
	for turn in 3:
		for key in ["view", "before", "report", "memory", "intel"]:
			assert_eq(a[turn][key], b[turn][key], "turn %d: the Crown's %s is identical" % [turn + 1, key])
	for turn in 3:
		assert_false(String(a[turn].view).contains("\"beasts-3\"") or String(a[turn].report).contains("\"beasts-3\""), "no true rival id reaches the Crown")


func test_rival_enchantment_ids_never_reach_a_view() -> void:
	# Magic (M5-6) will cast rituals; the counters already exist (M5-0). Two magic states that differ only in a rival
	# ritual cast out of sight (so the visible one's true id is one higher) give the same view.
	var states := []
	for hidden in [true, false]:
		var s := GameState.with_paths(5)
		s.setup_fog([])
		s.magic = true
		s.current_turn = 3
		var clans := s.find_faction(CLANS)
		var es := []
		var n := 0
		if hidden:
			n += 1
			es.append({"id": "beasts-e%d" % n, "ritual": "bloodrot", "faction": CLANS, "kind": "curse", "province": "bloodfen",
				"armies": [], "cast_turn": 2, "until_turn": 5, "bonus": 0, "ending": false})
		n += 1
		es.append({"id": "beasts-e%d" % n, "ritual": "sanctum_ward", "faction": CLANS, "kind": "ward", "province": "westwatch",
			"armies": [], "cast_turn": 3, "until_turn": 4, "bonus": 0, "ending": false})
		n += 1
		es.append({"id": "beasts-e%d" % n, "ritual": "blood_moon", "faction": CLANS, "kind": "global", "province": "",
			"armies": [], "cast_turn": 3, "until_turn": 5, "bonus": 0, "ending": false})
		es.sort_custom(func(x, y): return String(x.id) < String(y.id))
		s.enchantments = es
		clans.enchant_counter = n
		assert_true(s.validate([]), "the magic state is valid")
		states.append(s)
	var views := states.map(func(s): return FogRules.view_state(s, CROWN, FogRules.new_memory(s, CROWN), FogRules.new_intel(s, CROWN)))
	assert_eq(_json(views[0]), _json(views[1]), "the same view: the hidden ritual and the counter are invisible")
	var ids: Array = views[0].enchantments.map(func(e): return e.id)
	assert_eq(ids, ["seen-blood_moon", "seen-sanctum_ward-westwatch"], "a visible rival ward and every global, by view ids")
	assert_eq(views[0].find_faction(CLANS).enchant_counter, 0, "the rival's counter is zeroed")


# --- relaxed checks, one case each, for rivals only (§2.7) ---------------------------------------------

func _view_dict_of(s: GameState, viewer: String) -> Dictionary:
	var d := s.to_dict()
	d["is_view"] = true
	d["view_of"] = viewer
	return d


func _loads(d: Dictionary) -> Array:
	var errors := []
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(d)), errors)
	return [] if loaded != null else (errors if not errors.is_empty() else ["did not load"])


func test_relaxed_check_1_a_rivals_researched_needs_no_prerequisites_or_order() -> void:
	var s := GameState.with_paths(6)
	s.current_turn = 6
	var oath := "beasts_oath_grove"
	var clans := s.find_faction(CLANS)
	clans.researched = [{"node": "beasts_bone_fangs", "turn": 5}, {"node": oath, "turn": 4}]  # out of order, no prerequisites
	clans.path_branch = String(AscensionRules.node_data(oath).branch)
	assert_eq(_loads(_view_dict_of(s, CROWN)), [], "the Crown's view of the Clans holds what it knows")
	var truth := _loads(s.to_dict())
	assert_true(truth.any(func(e): return String(e).contains("without")), "the true game refuses it: %s" % str(truth))
	assert_false(_loads(_view_dict_of(s, CLANS)).is_empty(), "never for the viewer itself")


func test_relaxed_check_2_a_rivals_kept_power_and_sacrifice_only_mandates() -> void:
	var s := GameState.with_paths(6)
	var clans := s.find_faction(CLANS)
	clans.kept_power = RulerData.POWER_POOL  # assumed: the most it could be, with mandates known
	clans.sacrifices = []
	clans.mandates = ["iron_discipline", "red_harvest"]  # red_harvest is sacrifice-only
	RulerRules.refresh_ruler_type(clans)
	RulerRules.ruler_army(s, CLANS).ruler.type = clans.ruler_unit_type
	RulerRules.ruler_army(s, CLANS).ruler.current_hp = clans.ruler_unit_type.hp
	var view_errors := _loads(_view_dict_of(s, CROWN))
	assert_false(view_errors.any(func(e): return String(e).contains("kept power") or String(e).contains("without a sacrifice")),
		"the view relaxes the arithmetic and the sacrifice-only check: %s" % str(view_errors))
	var truth := _loads(s.to_dict())
	assert_true(truth.any(func(e): return String(e).contains("kept power")), "the true game refuses the arithmetic: %s" % str(truth))
	assert_true(truth.any(func(e): return String(e).contains("without a sacrifice")), "and the sacrifice-only mandate")


func test_relaxed_check_3_a_rivals_living_ruler_need_not_be_on_the_map() -> void:
	var s := GameState.with_rulers(6)
	s.armies.erase(RulerRules.ruler_army(s, CLANS))
	assert_eq(_loads(_view_dict_of(s, CROWN)), [], "alive, location unknown")
	assert_true(_loads(s.to_dict()).any(func(e): return String(e).contains("alive but has no ruler's army")), "the true game refuses it")
	var mine := GameState.with_rulers(6)
	mine.armies.erase(RulerRules.ruler_army(mine, CROWN))
	assert_false(_loads(_view_dict_of(mine, CROWN)).is_empty(), "never for the viewer's own ruler")
	var view := GameState.from_dict(_view_dict_of(s, CROWN), [])
	assert_true(RulerRules.ruler_alive(view, CLANS) and not RulerRules.has_living_ruler(view, CLANS))
	assert_eq(RulerRules.ruler_whereabouts(view, CLANS).text, "alive, location unknown")
	assert_eq(RulerRules.ruler_whereabouts(s, CROWN).text, "alive, at Crownkeep")


func test_relaxed_check_4_a_rival_stand_ins_summoned_units_carry_no_until() -> void:
	# Summoned creatures arrive with M5-5/M5-6 (MagicData.SUMMONS); M5-5's "a summoned unit must fade" check must skip a
	# view's rivals (GameState.view_relaxes). Stand-ins carry until 0, and such a view loads.
	var s := GameState.with_paths(6)
	s.magic = true
	var clans := s.find_faction(CLANS)
	var wolves := UnitType.new()
	wolves.id = "thornwolves"
	wolves.name = "Thornwolves"
	wolves.hp = 9
	wolves.summoned = true
	clans.unit_types.append(wolves)
	var pack := Army.new()
	pack.id = "seen-beasts-bloodfen"
	pack.owner = CLANS
	pack.location = "bloodfen"
	pack.units.append(Unit.new(wolves, CLANS))  # until 0, as a stand-in carries
	pack.seen = {"level": "glimpse", "turn": 0, "counts": {"thornwolves": FogRules.round_count(1)}, "total": FogRules.round_count(1), "blessed": 0}
	s.armies.append(pack)
	var d := _view_dict_of(s, CROWN)
	assert_eq(_loads(d), [], "a rival's summoned stand-in with until 0 loads in a view")
	assert_true(GameState.from_dict(d, []).view_relaxes(CLANS), "the check is relaxed for the rival")
	assert_false(GameState.from_dict(d, []).view_relaxes(CROWN), "and not for the viewer")


# --- what a view holds (§2.7) ----------------------------------------------------------------------

func test_the_serialized_view_holds_no_true_rival_id_gold_research_or_unknown_mandate() -> void:
	for g in Kit.games():
		for t in g.turns:
			for v in Kit.SEATS:
				var rival := Kit.rival_of(v)
				var view: GameState = t.view_after[v]
				var text := _json(view)
				for a in t.after.armies:
					if a.owner == rival:
						assert_false(text.contains("\"%s\"" % a.id), "%s turn %d, %s: no true rival id %s" % [g.name, t.turn, v, a.id])
				var f := view.find_faction(rival)
				assert_eq([f.gold, f.research_points, f.research_target, f.sacrifices, f.enchant_counter], [0, 0, "", [], 0],
					"%s turn %d, %s: the rival's private numbers are zeroed" % [g.name, t.turn, v])
				var known: Array = t.intel_after[v].get(rival, {}).get("mandates", [])
				for mid in f.mandates:
					assert_true(known.has(mid), "%s turn %d, %s: only known mandates (%s)" % [g.name, t.turn, v, mid])
				for r in f.researched:
					assert_true(t.intel_after[v][rival].nodes.any(func(n): return n.node == r.node), "only known nodes")
				assert_eq(int(view.next_army_ids.get(rival, 1)), 1, "the rival's army count is zeroed")
				assert_eq([view.seed_value, view.rng.get_state()], [0, SeededRNG.new(0).get_state()], "no seed or roll to predict")
				for a in view.armies:
					if a.owner == rival:
						assert_true(FogRules.is_view_id(a.id) and not a.seen.is_empty(), "every rival army is a stand-in with a note")
					else:
						assert_true(a.seen.is_empty() and t.after.find_army(a.id) != null, "the viewer's own armies, by their true ids")


func test_a_view_deep_copies_exactly() -> void:
	for g in Kit.games():
		var t: Dictionary = g.turns[g.turns.size() / 2]
		for v in Kit.SEATS:
			var view: GameState = t.view_after[v]
			var copy := view.deep_copy([])
			assert_true(copy != null and copy.is_view and copy.view_of == v, "%s: a view copies as a view" % g.name)
			if copy != null:
				assert_eq(_json(copy), _json(view), "%s, %s: deep_copy round-trips byte for byte" % [g.name, v])


func test_the_readers_run_on_views() -> void:
	var ran := 0
	for gi in [0, 1, 2, 3]:
		var g: Dictionary = Kit.games()[gi]
		var t: Dictionary = g.turns[mini(5, g.turns.size() - 1)]
		for v in Kit.SEATS:
			var view: GameState = t.view_after[v]
			var f := view.find_faction(v)
			var own := view.armies.filter(func(a): return a.owner == v)
			var rival := view.armies.filter(func(a): return a.owner != v)
			for a in own:
				for n in view.find_province(a.location).neighbors:
					var o := MoveOrder.new(a.id, n)
					Forecast.move(view, v, o)
					OrderBook.check_order(view, v, o, [])
				Forecast.sally_odds(view, v, [a.id])
			if not own.is_empty():
				var n0 := String(view.find_province(own[0].location).neighbors[0])
				Forecast.battle_odds(view, v, [own[0].id], n0)
				Forecast.relief_odds(view, v, MoveOrder.new(own[0].id, n0))
			for r in rival:
				if not own.is_empty() and r == rival[0]:
					Forecast.battle_odds(view, v, [own[0].id], r.location)  # against a stand-in
				if view.sieges:
					Forecast.siege(view, v, r.location, [], true)
					Forecast.storm_odds(view, v, r.location)
					Forecast.breach_odds(view, v, r.location)
			for ut in f.unit_types:
				Forecast.recruit(view, v, ut.id)
				Forecast.recruit_cost(view, v, ut.id)
				Forecast.recruit_at(view, v, ut.id)
				OrderBook.check_order(view, v, RecruitOrder.new(ut.id), [])
			Forecast.gold_after_recruits(view, v, [])
			Forecast.faction_numbers(view, v)
			Forecast.faction_numbers(view, Kit.rival_of(v))
			Forecast.vassal(view, v)
			Forecast.projected_board(view)
			Forecast.road_reach(view, v)
			Forecast.ruler_destination(view, v, [])
			for p in view.provinces:
				Forecast.defender_ground(p)
				if view.sieges:
					Forecast.fortify(view, v, p.id)
			if f.has_ruler():
				for option in Forecast.sacrifice_options(view, v):
					Forecast.sacrifice(view, v, String(option.mandate))
					Forecast.mandate_now(view, v, String(option.mandate))
					if bool(option.ok):
						var after := RulerRules.with_sacrifice(view, v, String(option.mandate))
						assert_true(after != null, "with_sacrifice runs on a view")
						OrderBook.check_order(view, v, SacrificeOrder.new(String(option.mandate)), [])
			if view.paths:
				Forecast.research(view, v)
				Forecast.province_rules(view, v)
				for nid in AscensionRules.node_ids(v):
					OrderBook.check_order(view, v, ResearchOrder.new(nid), [])
			var ai := AIPlayer.new()
			var orders := ai.plan_orders(view, v, SeededRNG.new(5))
			for o in orders:
				assert_eq(OrderBook.check_order(t.after, v, o, []).get("code", ""), OrderBook.check_order(view, v, o, []).get("code", ""),
					"the computer's order checks the same on the truth")
			ai._begin(view, v, SeededRNG.new(5), "normal")
			if not own.is_empty():
				var scratch := ai._scratch_with([own[0]], String(view.find_province(own[0].location).neighbors[0]))
				assert_true(scratch != null and scratch.is_view, "_scratch_with copies the view")
			ran += 1
	assert_eq(ran, 8, "every reader ran on 8 views: M1, M2, M4 and sieges, both seats")
