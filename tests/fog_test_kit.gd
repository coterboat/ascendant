extends RefCounted
## M5-1 (#112): the fog-proof kit (design/M5_MAGIC_FOG.md §2.7, §18). Not a test file itself (no "test_" prefix):
## tests/test_fog_*.gd preload it.
##
##   games()                       20 seeded fog games, played once per test run and shared: AI vs AI, M1, M2 (rulers),
##                                 M4 (paths) and M3c (sieges with rulers) in turn, each turn kept with the true states
##                                 before and after it, every seat's memory and intel before and after, its report and
##                                 its views.
##   perturb_hidden(state, viewer, seed, keep)   the state with everything hidden from `viewer` changed, and the
##                                 renaming of rival army ids it made: {"state", "rename", "changed"}.
##   two_turn_variations(...)      the two-turn test's generator: the rival's orders varied only in hidden ways.
##   public_facts(...)             what a variation must leave alone to count: owners, forts, terrain, heralds and the
##                                 viewer's own battles.
##
## The perturbation changes (§2.7): out-of-sight rival armies (existence, number, location, merges, splits, units,
## hp, engines), how glimpsed pools divide into armies and each type's true count within the same sighting, wounds and
## engines in a glimpse, how pools in clear sight divide into armies, out-of-sight construction sites, rival gold,
## research pool and target, unknown path nodes and mandates, kept power while the ruler is unseen, and every rival
## army id. `keep` names armies whose make-up the viewer was shown (battles it fought, moves it saw): they keep their
## units and ids.

const Policies := preload("res://tools/autoplay/policies.gd")
const SEATS := ["kingdom", "beasts"]
const GAME_COUNT := 20
const TURNS := 12
const KINDS := ["m1", "m2", "m4", "sieges"]

static var _games: Array = []


## The fog games (played on first use): [{"name", "seed", "kind", "turns": [{"turn" (1-based), "seed", "before",
## "after", "events" (the true report), "orders" ({faction id: [orders]}), "memory_before", "intel_before",
## "memory_after", "intel_after", "report", "view_before", "view_after" (each {faction id: ...})}]}].
static func games() -> Array:
	if _games.is_empty():
		for i in GAME_COUNT:
			_games.append(play(i))
	return _games


## The start of fog game `i`: kind KINDS[i % 4], seed 9001 + 37 i.
static func start_state(i: int) -> GameState:
	var seed_value := 9001 + 37 * i
	var s: GameState
	match KINDS[i % KINDS.size()]:
		"m1":
			s = GameState.new(seed_value)
		"m2":
			s = GameState.with_rulers(seed_value)
		"m4":
			s = GameState.with_paths(seed_value)
		_:
			s = GameState.with_sieges(seed_value, {}, {"rulers": true})
	s.setup_fog([])
	return s


static func play(i: int) -> Dictionary:
	var start := start_state(i)
	var seed_value := start.seed_value
	var session := GameSession.new(start, SEATS, seed_value, AutoBattleResolver.new())
	var policies := []
	var rngs := []
	for seat in SEATS.size():
		var policy = Policies.make("ai")
		policy.configure(seed_value, seat, "")
		policies.append(policy)
		rngs.append(SeededRNG.new(seed_value * 7919 + (seat + 1) * 104729))
	var turns := []
	while not session.is_over() and session.turns_played() < TURNS:
		var t := {"turn": session.turn_number(), "seed": GameSession.turn_seed(seed_value, session.turns_played()),
			"before": session.state(), "orders": {}, "memory_before": {}, "intel_before": {}}
		for fid in SEATS:
			t.memory_before[fid] = session.memory(fid)
			t.intel_before[fid] = session.intel(fid)
		for seat in SEATS.size():
			if session.phase() == GameSession.Phase.HANDOFF:
				session.acknowledge_handoff()
			var fid: String = SEATS[seat]
			var accepted := []
			for o in policies[seat].orders(session.state(), fid, rngs[seat]):
				if session.queue_order(o).is_empty():
					accepted.append(o)
			t.orders[fid] = session.current_orders()
			session.end_turn()
		t["after"] = session.state()
		t["events"] = session.turn_report().events
		for key in ["memory_after", "intel_after", "report", "view_before", "view_after"]:
			t[key] = {}
		for fid in SEATS:
			t.memory_after[fid] = session.memory(fid)
			t.intel_after[fid] = session.intel(fid)
			t.report[fid] = session.turn_report_for(fid).events
			t.view_before[fid] = session.view_before(fid)
			t.view_after[fid] = session.state_for(fid)
		turns.append(t)
	return {"name": "fog_%s_%d" % [KINDS[i % KINDS.size()], seed_value], "seed": seed_value, "kind": KINDS[i % KINDS.size()],
		"turns": turns, "session": session}


static func rival_of(fid: String) -> String:
	return SEATS[1] if fid == SEATS[0] else SEATS[0]


static func to_json(state: GameState) -> String:
	return JSON.stringify(state.to_dict()) if state != null else "null"


# --- perturb_hidden (§2.7) -------------------------------------------------------------------------

## The new id of a rival army (a function of the id and the seed alone, so the states before and after a turn rename
## an army the same way).
static func rename_id(id: String, owner: String, seed_value: int) -> String:
	var h := absi(hash("%s|%d" % [id, seed_value])) % 800000
	return "%s-%d" % [owner, 100000 + h]


static func perturb_hidden(state: GameState, viewer: String, seed_value: int, keep: Dictionary = {}) -> Dictionary:
	var rng := SeededRNG.new(seed_value)
	var s := state.deep_copy()
	var sight := FogRules.sight(s, viewer)
	var changed := {"veiled_armies": 0, "glimpse_resplit": 0, "glimpse_counts": 0, "clear_resplit": 0, "mandates": 0,
		"kept_power": 0, "nodes": 0, "gold": 0, "research": 0, "works": 0, "renamed": 0, "ruler_moved": 0}
	for f in s.factions:
		if f.id == viewer:
			continue
		_perturb_faction(s, f, sight, rng, changed)
		_perturb_armies(s, f, sight, rng, keep, changed)
		if s.sieges:
			_perturb_works(s, f, sight, rng, changed)
	# Rename every rival army that wasn't shown (and so isn't kept).
	var rename := {}
	var taken := {}
	for a in s.armies:
		taken[a.id] = true
	for a in s.armies:
		if a.owner == viewer or keep.has(a.id):
			continue
		var new_id := rename_id(a.id, a.owner, seed_value)
		while taken.has(new_id) and new_id != a.id:
			new_id += "7"
		taken[new_id] = true
		rename[a.id] = new_id
		a.id = new_id
		changed.renamed += 1
	for f in s.factions:
		if f.id == viewer:
			continue
		var top := 1
		for a in s.armies:
			if a.owner == f.id:
				top = maxi(top, TurnReportText.army_number(a.id) + 1)
		s.next_army_ids[f.id] = top
	var errors := []
	var out := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())), errors)
	return {"state": out, "rename": rename, "changed": changed, "errors": errors}


static func _perturb_faction(s: GameState, f: Faction, sight: Dictionary, rng: SeededRNG, changed: Dictionary) -> void:
	f.gold = rng.randi_range(0, 250)
	changed.gold += 1
	var ruler_army := RulerRules.ruler_army(s, f.id)
	var ruler_unseen := ruler_army == null or String(sight.get(ruler_army.location, "veiled")) == "veiled"
	if s.paths:
		f.research_points = rng.randi_range(0, 60)
		var known := _known_nodes_of(s, f.id)
		# An unknown ordinary node, researched now (its prerequisites met).
		if rng.randi_range(0, 1) == 1:
			var candidates := []
			for nid in AscensionRules.node_ids(f.id):
				if AscensionRules.is_ordinary(nid) and not known.has(nid) and AscensionRules.check_research(s, f.id, nid).is_empty():
					candidates.append(nid)
			if not candidates.is_empty():
				f.researched.append({"node": candidates[rng.randi_range(0, candidates.size() - 1)], "turn": s.current_turn})
				changed.nodes += 1
		var targets := [""]
		for nid in AscensionRules.node_ids(f.id):
			if AscensionRules.check_research(s, f.id, nid).is_empty():
				targets.append(nid)
		f.research_target = targets[rng.randi_range(0, targets.size() - 1)]
		changed.research += 1
	if not f.has_ruler() or not ruler_unseen:
		return
	# An unknown mandate, bought before the game, and kept power anywhere it may be.
	var spent := 0
	for mid in f.mandates:
		spent += RulerRules.mandate_cost(mid)
	for sac in f.sacrifices:
		spent += MandateData.SACRIFICE_PREMIUM
	if rng.randi_range(0, 1) == 1:
		var options := []
		for mid in RulerRules.available_mandates(f.id):
			var md := RulerRules.mandate_data(mid)
			if f.mandates.has(mid) or md.get("sacrifice_only", false):
				continue
			if spent + int(md.cost) <= RulerData.POWER_POOL:
				options.append(mid)
		if not options.is_empty():
			var pick: String = options[rng.randi_range(0, options.size() - 1)]
			f.mandates.append(pick)
			spent += RulerRules.mandate_cost(pick)
			changed.mandates += 1
	f.kept_power = rng.randi_range(0, maxi(0, RulerData.POWER_POOL - spent))
	changed.kept_power += 1
	RulerRules.refresh_ruler_type(f)
	if ruler_army != null:
		ruler_army.ruler.type = f.ruler_unit_type
		ruler_army.ruler.current_hp = rng.randi_range(1, f.ruler_unit_type.hp)


static func _known_nodes_of(_s: GameState, _fid: String) -> Dictionary:
	return {}  # nodes the viewer knows are only Oaths and transformations here (they are never added or removed)


static func _perturb_armies(s: GameState, f: Faction, sight: Dictionary, rng: SeededRNG, keep: Dictionary, changed: Dictionary) -> void:
	var veiled_own := []  # out-of-sight provinces the rival owns
	for p in s.provinces:
		if p.owner == f.id and String(sight.get(p.id, "veiled")) == "veiled":
			veiled_own.append(p.id)
	veiled_own.sort()
	var by_place := {}
	for a in s.armies:
		if a.owner != f.id:
			continue
		if not by_place.has(a.location):
			by_place[a.location] = []
		by_place[a.location].append(a)
	var keep_out := []
	for pid in by_place.keys():
		var level := String(sight.get(pid, "veiled"))
		var armies: Array = by_place[pid]
		var held := armies.filter(func(a): return keep.has(a.id))
		if level == "veiled":
			for a in armies:
				if keep.has(a.id):
					continue
				if a.ruler != null:
					if not veiled_own.is_empty():
						a.location = veiled_own[rng.randi_range(0, veiled_own.size() - 1)]
						changed.ruler_moved += 1
					a.ruler.current_hp = rng.randi_range(1, a.ruler.type.hp)
					continue
				s.armies.erase(a)
				changed.veiled_armies += 1
			continue
		if not held.is_empty():
			continue  # a pool the viewer was shown part of keeps its make-up
		var ruler := armies.filter(func(a): return a.ruler != null)
		var rest := armies.filter(func(a): return a.ruler == null)
		for r in ruler:
			if level == "glimpse":
				r.ruler.current_hp = rng.randi_range(1, r.ruler.type.hp)
		if rest.is_empty():
			continue
		var units := []
		var commanders := []
		var engines := 0
		for a in rest:
			for u in a.units:
				units.append(u)
			if a.commander != null:
				commanders.append(a.commander)
			engines += a.engines
			s.armies.erase(a)
		if level == "glimpse":
			units = _recount(s, f, units, rng, changed)
			for u in units:
				u.current_hp = rng.randi_range(1, maxi(1, RulerRules.unit_max_hp(s, u)))
			for c in commanders:
				c.current_hp = rng.randi_range(1, c.type.hp)
			engines = rng.randi_range(0, 2) if s.sieges else 0
			changed.glimpse_resplit += 1
		else:
			changed.clear_resplit += 1
		_deal(s, f, pid, units, commanders, engines, rng)
	# New out-of-sight armies: any number, anywhere the rival owns out of sight.
	if not veiled_own.is_empty():
		for i in rng.randi_range(0, 3):
			var units := []
			for k in rng.randi_range(1, 6):
				var ut: UnitType = f.unit_types[rng.randi_range(0, f.unit_types.size() - 1)]
				var u := Unit.new(ut, f.id)
				u.current_hp = rng.randi_range(1, maxi(1, RulerRules.unit_max_hp(s, u)))
				units.append(u)
			var commanders := []
			if f.commander_type != null and rng.randi_range(0, 2) == 0:
				var c := Unit.new(f.commander_type, f.id)
				c.current_hp = rng.randi_range(1, f.commander_type.hp)
				commanders.append(c)
			_deal(s, f, veiled_own[rng.randi_range(0, veiled_own.size() - 1)], units, commanders,
				rng.randi_range(0, 2) if s.sieges else 0, rng)
			changed.veiled_armies += 1


## New per-type counts for a glimpsed pool's units that show the same sighting (the same rounded total and shares),
## when one can be found; otherwise the same units.
static func _recount(s: GameState, f: Faction, units: Array, rng: SeededRNG, changed: Dictionary) -> Array:
	var order := FogRules.type_order(s, f.id)
	var by_type := {}
	var types := {}
	for u in units:
		by_type[u.type.id] = int(by_type.get(u.type.id, 0)) + 1
		types[u.type.id] = u.type
	var keys := FogRules._ordered_keys(by_type, order)
	var weights := keys.map(func(k): return [k, int(by_type[k])])
	var want := FogRules.glimpse_counts(weights)
	for attempt in 30:
		var trial := []
		for w in weights:
			trial.append([w[0], maxi(1, int(w[1]) + rng.randi_range(-3, 3))])
		var got := FogRules.glimpse_counts(trial)
		if var_to_str(got.counts) == var_to_str(want.counts) and var_to_str(got.total) == var_to_str(want.total) and var_to_str(trial) != var_to_str(weights):
			var out := []
			for w in trial:
				for i in int(w[1]):
					out.append(Unit.new(types[w[0]], f.id))
			changed.glimpse_counts += 1
			return out
	return units


## Deals `units`, `commanders` (at most one an army) and `engines` into a random number of new armies at `pid`, each
## with a fighter.
static func _deal(s: GameState, f: Faction, pid: String, units: Array, commanders: Array, engines: int, rng: SeededRNG) -> void:
	if units.is_empty() and commanders.is_empty():
		return
	var k := maxi(commanders.size(), 1) + rng.randi_range(0, 2)
	k = mini(k, commanders.size() + units.size())
	var armies := []
	for i in k:
		var a := Army.new()
		a.id = "%s-%d" % [f.id, 900000 + s.armies.size() + armies.size() + rng.randi_range(0, 9999)]
		while s.find_army(a.id) != null or armies.any(func(b): return b.id == a.id):
			a.id += "1"
		a.owner = f.id
		a.location = pid
		armies.append(a)
	for i in commanders.size():
		armies[i].commander = commanders[i]
	var shuffled := units.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	var empty := []
	for a in armies:
		if a.commander == null:
			empty.append(a)
	for a in empty:
		if not shuffled.is_empty():
			a.units.append(shuffled.pop_back())
	for u in shuffled:
		armies[rng.randi_range(0, armies.size() - 1)].units.append(u)
	if s.sieges:
		for a in armies:
			var take := mini(engines, FortData.ARMY_ENGINES_MAX)
			a.engines = take
			engines -= take
	for a in armies:
		if not a.units.is_empty() or a.commander != null:
			s.armies.append(a)


## Out-of-sight construction: the rival starts or drops a site where the viewer can't see it.
static func _perturb_works(s: GameState, f: Faction, sight: Dictionary, rng: SeededRNG, changed: Dictionary) -> void:
	var site := ""
	for p in s.provinces:
		if not p.works.is_empty() and String(p.works.faction) == f.id:
			site = p.id
	if not site.is_empty():
		if String(sight.get(site, "veiled")) == "veiled" and rng.randi_range(0, 1) == 1:
			s.find_province(site).works = {}
			changed.works += 1
		return
	var options := []
	for p in s.provinces:
		if p.owner == f.id and String(sight.get(p.id, "veiled")) == "veiled" and not p.is_capital and p.fort_level < FortData.MAX_BUILT \
				and SiegeRules.besiegers(s, p.id).is_empty():
			options.append(p)
	if options.is_empty() or rng.randi_range(0, 1) == 0:
		return
	var p: Province = options[rng.randi_range(0, options.size() - 1)]
	var to := p.fort_level + 1
	p.works = {"faction": f.id, "to": to, "left": rng.randi_range(1, int(SiegeRules.level_data(to).turns)), "turn": s.current_turn}
	changed.works += 1


## Renames the true army ids in `events` by `rename` (a perturbation's map): "armies" and numbers.destroyed.
static func rename_events(events: Array, rename: Dictionary) -> Array:
	var out := events.duplicate(true)
	for e in out:
		e.armies = e.get("armies", []).map(func(id): return rename.get(String(id), id))
		var numbers: Dictionary = e.get("numbers", {})
		if numbers.has("destroyed"):
			numbers.destroyed = numbers.destroyed.map(func(id): return rename.get(String(id), id))
	return out


## The rival army ids the viewer was shown the make-up of in a turn (§2.8): every army in a battle it fought, and every
## rival army it saw leave a province.
static func shown_armies(events: Array, viewer: String, before: GameState) -> Dictionary:
	var out := {}
	var before_sight := FogRules.sight(before, viewer)
	for e in events:
		var t := String(e.get("type", ""))
		if FogRules.BATTLE_TYPES.has(t) and e.factions.has(viewer):
			for aid in e.armies:
				out[String(aid)] = true
		elif t == "army_moved" and not e.factions.is_empty() and String(e.factions[0]) != viewer \
				and String(before_sight.get(String(e.provinces[0]), "veiled")) != "veiled":
			out[String(e.armies[0])] = true
		elif t == "ruler_died" and not e.armies.is_empty():
			out[String(e.armies[0])] = true
	return out


# --- the two-turn test's generator (§2.7) ------------------------------------------------------------

## Variations of the rival's orders for one turn that the viewer can't see: [{"what", "orders" (the rival's orders)}].
## Only: recruits at a rival capital out of sight both times, moves by armies with no other orders between
## rival-owned provinces out of sight both times, research orders, and sacrifices for mandates the viewer doesn't know
## (while the rival's ruler is out of sight both times). `sight0` and `sight1` are the viewer's sight at the start of
## this turn and of the next.
static func two_turn_variations(before: GameState, viewer: String, rival_orders: Array, sight0: Dictionary, sight1: Dictionary,
		intel: Dictionary) -> Array:
	var rival := rival_of(viewer)
	var f := before.find_faction(rival)
	var hidden := func(pid: String) -> bool:
		return String(sight0.get(pid, "veiled")) == "veiled" and String(sight1.get(pid, "veiled")) == "veiled"
	var out := []
	var capital := before.find_province(f.capital)
	if capital != null and capital.owner == rival and hidden.call(f.capital):
		var without := rival_orders.filter(func(o): return not (o is RecruitOrder))
		if without.size() != rival_orders.size():
			out.append({"what": "no recruits at a hidden capital", "orders": without})
		var more := rival_orders.duplicate()
		for ut in f.unit_types:
			more.append(RecruitOrder.new(ut.id))
		out.append({"what": "more recruits at a hidden capital", "orders": more})
	var ordered := {}
	for o in rival_orders:
		if o is MoveOrder:
			ordered[o.army_id] = true
	var moves_out := rival_orders.filter(func(o):
		if not (o is MoveOrder):
			return true
		var a := before.find_army(o.army_id)
		var dest := before.find_province(o.to)
		return a == null or dest == null or not (hidden.call(a.location) and hidden.call(o.to) and dest.owner == rival \
			and before.find_province(a.location).owner == rival))
	if moves_out.size() != rival_orders.size():
		out.append({"what": "hidden moves dropped", "orders": moves_out})
	var extra := rival_orders.duplicate()
	var added := 0
	for a in before.armies:
		if a.owner != rival or ordered.has(a.id) or not hidden.call(a.location) or before.find_province(a.location).owner != rival:
			continue
		for n in before.find_province(a.location).neighbors:
			var dest := before.find_province(n)
			if dest.owner == rival and hidden.call(n):
				extra.append(MoveOrder.new(a.id, n))
				added += 1
				break
	if added > 0:
		out.append({"what": "hidden moves added", "orders": extra})
	if before.paths:
		var others := rival_orders.filter(func(o): return not (o is ResearchOrder))
		for nid in AscensionRules.node_ids(rival):
			if AscensionRules.check_research(before, rival, nid).is_empty() and AscensionRules.is_ordinary(nid):
				var with := others.duplicate()
				with.append(ResearchOrder.new(nid))
				out.append({"what": "research %s" % nid, "orders": with})
				break
	if f.has_ruler():
		var ruler := RulerRules.ruler_army(before, rival)
		var known: Array = intel.get(rival, {}).get("mandates", [])
		if ruler != null and hidden.call(ruler.location) and not rival_orders.any(func(o): return o is SacrificeOrder):
			for mid in RulerRules.available_mandates(rival, before):
				if not known.has(mid) and RulerRules.sacrifice_check(before, rival, mid, "").is_empty():
					var with := [SacrificeOrder.new(mid)]
					with.append_array(rival_orders)
					out.append({"what": "sacrifice for %s" % mid, "orders": with})
					break
	return out


## What a variation must not change to count (§2.7): owners, forts, terrain, the heralds the viewer reads, and the
## battles the viewer fought (it saw those whole). A JSON string.
static func public_facts(after: GameState, events: Array, viewer: String) -> String:
	var provinces := []
	for p in after.provinces:
		provinces.append([p.id, p.owner, p.terrain, p.has_fort, p.fort_level, p.walls])
	var seen := []
	for e in events:
		var row: Dictionary = FogData.AUDIENCE.get(String(e.type), {})
		if FogRules.BATTLE_TYPES.has(String(e.type)) and e.factions.has(viewer):
			var c: Dictionary = e.duplicate(true)
			c.numbers.erase("log")
			seen.append(c)
		elif String(row.get("others", "")) == "rebuilt" and not e.factions.is_empty() and String(e.factions[0]) != viewer:
			var safe := {}
			for key in FogData.SAFE_NUMBERS.get(String(e.type), []):
				if e.numbers.has(key):
					safe[key] = e.numbers[key]
			seen.append([e.type, e.provinces, e.factions, safe])
	return JSON.stringify([provinces, seen])
