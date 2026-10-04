extends "res://tests/test_case.gd"
## M5-1 (#112) acceptance, legality never reads hidden facts (design/M5_MAGIC_FOG.md §2.10, §18): for every order the
## UI can offer, on every turn of 20 fog games and for both seats, OrderBook.check_order gives the same answer
## (accepted, or the same code and reason) on the true state and on the seat's view. An order's legality depends only
## on public facts and the player's own state, so a legal order is never refused because of the view, and a check
## can't leak.

const Kit := preload("res://tests/fog_test_kit.gd")


## Every order the UI can offer `fid` on `s`: moves to each neighbour and road moves through each, recruits of every
## type it might name (at the capital, with the ruler, at each fort it owns), Fortify, storms and sallies, research
## and sacrifices.
func _offers(s: GameState, fid: String) -> Array:
	var out := []
	var f := s.find_faction(fid)
	for a in s.armies:
		if a.owner != fid:
			continue
		var here := s.find_province(a.location)
		for n in here.neighbors:
			out.append(MoveOrder.new(a.id, n))
			for m in s.find_province(n).neighbors:
				if m != a.location:
					out.append(MoveOrder.new(a.id, m, n))
		out.append(SiegeOrder.sally(a.id))
		for b in s.armies:
			if b.owner == fid and b != a:
				out.append(SiegeOrder.sally(a.id, b.id))
	var types: Array = f.unit_types.map(func(ut): return ut.id)
	if f.commander_type != null:
		types.append(f.commander_type.id)
	if s.sieges:
		types.append(String(FortData.engine_for(fid).get("id", "")))
	types.append("warchief" if fid == "kingdom" else "knight_captain")  # another faction's: the UI never offers it, but the check is public
	var places := [RecruitOrder.AT_CAPITAL, RecruitOrder.AT_RULER]
	for p in s.provinces:
		if p.owner == fid and p.has_fort:
			places.append(p.id)
	for t in types:
		for at in places:
			out.append(RecruitOrder.new(t, at))
	for p in s.provinces:
		out.append(FortifyOrder.new(p.id))
		out.append(SiegeOrder.storm(p.id))
	if s.paths:
		for nid in AscensionRules.node_ids(fid):
			out.append(ResearchOrder.new(nid))
	if f.has_ruler():
		for mid in RulerRules.available_mandates(fid, s):
			out.append(SacrificeOrder.new(mid))
	return out


func test_every_order_checks_the_same_on_the_truth_and_on_the_view() -> void:
	var checks := 0
	var refused := 0
	for g in Kit.games():
		for t in g.turns:
			for v in Kit.SEATS:
				var view := FogRules.view_state(t.before, v, t.memory_before[v], t.intel_before[v])
				assert_true(view != null, "%s turn %d, %s: the view builds" % [g.name, t.turn, v])
				if view == null:
					continue
				for o in _offers(t.before, v):
					var truth := OrderBook.check_order(t.before, v, o, [])
					var seen := OrderBook.check_order(view, v, o, [])
					assert_eq(JSON.stringify(seen), JSON.stringify(truth), "%s turn %d, %s: %s" % [g.name, t.turn, v, JSON.stringify(o.to_dict())])
					checks += 1
					if not truth.is_empty():
						refused += 1
				# The seat's real orders, each against the ones it gave before it, as the order book takes them.
				var given := []
				for o in t.orders[v]:
					var truth := OrderBook.check_order(t.before, v, o, given)
					assert_eq(JSON.stringify(OrderBook.check_order(view, v, o, given)), JSON.stringify(truth),
						"%s turn %d, %s: its own order %s" % [g.name, t.turn, v, JSON.stringify(o.to_dict())])
					assert_eq(truth, {}, "the order the seat gave was legal")
					given.append(o)
	assert_true(checks > 10000, "orders checked (%d)" % checks)
	assert_true(refused > 0 and refused < checks, "both legal and illegal orders were checked (%d refused)" % refused)
