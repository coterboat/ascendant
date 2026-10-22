extends RefCounted
## CW-11 (#262, design/CANDLEWAKE.md §9): the Candlewake's balance check. The computer plays every pair of the three factions
## (Crown–Clans as the control, Crown–Candlewake and Clans–Candlewake) with every preset of each side, both seat orders, all six
## systems on (the MVP's defaults), and the bands are judged per pair. Every band is a target range to tune toward, not a hard cap
## (Alex 10-8); the bands are reported pass or miss with the numbers behind them. The faction stays behind its preview box
## until they pass; then the director proposes turning the box on.
##
## Bands (§9), each over the games of a pair, independents on (the contract, Alex 10-5):
##   C3   each pair 40-60% for either faction, over pooled presets and both seat orders (decisive games)
##   W1   the median flame a Candlewake army fights at is 1.3-2.3 (WickLog's battle flames)
##   W2   guttering in 10-40% of Candlewake games; no army spends more than 60% of its turns at its cap (armies seen MIN_ARMY_TURNS+)
##   W3   Harvest raises 10-20% of the Candlewake's force (Red Wake: 20-30%)
##   W6   the Risen are 10-20% of the Candlewake's force
##   W4   the median Wake-Line count at turn 12 is 2 or more; the Wake's gold cost is at most 10% of the income
##   W5   the median decisive Candlewake game lasts 10-16 turns
##   P1c  each Candlewake fork side wins 40-60% of its decisive games
## The force is what the Candlewake fielded: its regular recruits (the simulator's "recruits", commanders left out), the Harvest
## and the Risen.
##
## A result needs the simulator's "wick" log (WickLog, one entry per Wick faction): the matrix reads it, never computes it.

const Simulator := preload("res://tools/autoplay/simulator.gd")
const Matrix := preload("res://tools/autoplay/matrix.gd")

const CANDLEWAKE := "candlewake"
const PAIRS := [["kingdom", "beasts"], ["kingdom", CANDLEWAKE], ["beasts", CANDLEWAKE]]
const POLICY := "ai"
## Games per cell (one preset pairing, one seat order), before --scale.
const CELL_GAMES := 10
const C3_BAND := [0.40, 0.60]
const W1_BAND := [1.3, 2.3]
const W2_GUTTER := [0.10, 0.40]
const W2_CAP_MAX := 0.60
const W3_BAND := [0.10, 0.20]
const W3_RED_BAND := [0.20, 0.30]
const W6_BAND := [0.10, 0.20]
const W4_LINES := 2
const W4_TURN := 12
const W4_COST_MAX := 0.10
const W5_BAND := [10.0, 16.0]
const P1C_BAND := [0.40, 0.60]
## W2's cap clause counts only armies seen this many turns or more: a new army one turn at its cap says nothing.
const MIN_ARMY_TURNS := 5
## The Candlewake's Red Wake side, whose Harvest band is W3_RED_BAND.
const RED_WAKE := "red_wake"


## The cells: for each pair, every preset of the first faction against every preset of the second, in both seat orders.
## [{"id", "pair" ("a|b"), "seats", "builds", "policies", "games", "seed"}]. Cell ids are stable.
static func plan(scale: float = 1.0, base_seed: int = 1) -> Array:
	var cells := []
	var n := maxi(1, roundi(CELL_GAMES * scale))
	for pair in PAIRS:
		var a: Array = RulerRules.presets_for(pair[0]).map(func(p): return str(p.id))
		var b: Array = RulerRules.presets_for(pair[1]).map(func(p): return str(p.id))
		for x in a:
			for y in b:
				for first in [true, false]:
					var seats: Array = [pair[0], pair[1]] if first else [pair[1], pair[0]]
					var builds: Array = [x, y] if first else [y, x]
					cells.append({"id": "W:%s+%s:%s+%s" % [seats[0], builds[0], seats[1], builds[1]], "pair": "%s|%s" % pair,
						"seats": seats, "builds": builds, "policies": [POLICY, POLICY], "games": n, "seed": base_seed})
	return cells


## Every band over `results` (play_game results, each with "pair" added), as rows {"band", "pair", "value", "target", "status"}.
static func judge(results: Array) -> Array:
	var rows := []
	for pair in PAIRS:
		var key := "%s|%s" % pair
		var games := results.filter(func(r): return str(r.get("pair", "")) == key)
		rows.append(c3(games, key))
		if not pair.has(CANDLEWAKE):
			continue
		for row in [w1(games), w2(games), w3(games), w6(games), w4(games), w5(games), p1c(games)]:
			row["pair"] = key
			rows.append(row)
	return rows


static func c3(games: Array, key: String) -> Dictionary:
	var dec := games.filter(func(r): return Matrix.decisive(r))
	var first := key.split("|")[0]
	var share := _ratio(dec.filter(func(r): return str(r.winner) == first).size(), dec.size())
	return _row("C3", key, share, C3_BAND, "%s %s of %d decisive" % [first, _pct(share), dec.size()], not dec.is_empty())


static func w1(games: Array) -> Dictionary:
	var flames := []
	for r in games:
		flames.append_array(_wick(r).get("battle_flames", []))
	var med := float(Simulator.stats_of(flames).median)
	return _row("W1", "", med, W1_BAND, "median flame %.1f over %d army-battles" % [med, flames.size()], not flames.is_empty())


static func w2(games: Array) -> Dictionary:
	var with := 0
	var worst := 0.0
	for r in games:
		var w := _wick(r)
		if int(w.get("guttered", 0)) > 0:
			with += 1
		for aid in w.get("army_turns", {}):
			var seen: Array = w.army_turns[aid]
			if int(seen[0]) >= MIN_ARMY_TURNS:
				worst = maxf(worst, float(seen[1]) / float(seen[0]))
	var share := _ratio(with, games.size())
	var ok := _in(share, W2_GUTTER) and worst <= W2_CAP_MAX
	return {"band": "W2", "value": share, "target": "guttering in %s-%s of games; no army over %s of its turns at the cap" % [
		_pct(W2_GUTTER[0]), _pct(W2_GUTTER[1]), _pct(W2_CAP_MAX)],
		"detail": "guttering in %s of %d games; most turns at the cap %s" % [_pct(share), games.size(), _pct(worst)],
		"status": ("pass" if ok else "miss") if not games.is_empty() else "no games"}


static func w3(games: Array) -> Dictionary:
	var red := games.filter(func(r): return str(r.get("paths", {}).get(CANDLEWAKE, {}).get("branch", "")) == RED_WAKE)
	var other := games.filter(func(r): return not red.has(r))
	var s_other := _force_share(other, "harvest")
	var s_red := _force_share(red, "harvest")
	var ok := (other.is_empty() or _in(s_other, W3_BAND)) and (red.is_empty() or _in(s_red, W3_RED_BAND))
	return {"band": "W3", "value": s_other, "target": "Harvest %s-%s of the force (Red Wake %s-%s)" % [_pct(W3_BAND[0]), _pct(W3_BAND[1]),
		_pct(W3_RED_BAND[0]), _pct(W3_RED_BAND[1])], "detail": "%s (Red Wake %s, %d games)" % [_pct(s_other), _pct(s_red), red.size()],
		"status": ("pass" if ok else "miss") if not games.is_empty() else "no games"}


static func w6(games: Array) -> Dictionary:
	var share := _force_share(games, "risen")
	return _row("W6", "", share, W6_BAND, "the Risen %s of the force" % _pct(share), not games.is_empty())


static func w4(games: Array) -> Dictionary:
	var lines := []
	var cost := 0
	var income := 0
	for r in games:
		var w := _wick(r)
		if w.get("wake_line_at", {}).has(W4_TURN):
			lines.append(int(w.wake_line_at[W4_TURN]))
		cost += int(w.get("wake_cost", 0))
		income += int(w.get("income", 0))
	var med := float(Simulator.stats_of(lines).median)
	var share := _ratio(cost, income)
	var ok := med >= W4_LINES and share <= W4_COST_MAX
	return {"band": "W4", "value": med, "target": "median Wake-Line at turn %d %d+; the Wake's cost at most %s of income" % [W4_TURN, W4_LINES,
		_pct(W4_COST_MAX)], "detail": "median %.1f over %d games that reached turn %d; cost %s of income" % [med, lines.size(), W4_TURN, _pct(share)],
		"status": ("pass" if ok else "miss") if not lines.is_empty() else "no games"}


static func w5(games: Array) -> Dictionary:
	var turns := games.filter(func(r): return Matrix.decisive(r)).map(func(r): return int(r.turns))
	var med := float(Simulator.stats_of(turns).median)
	return _row("W5", "", med, W5_BAND, "median %.1f turns over %d decisive games" % [med, turns.size()], not turns.is_empty())


static func p1c(games: Array) -> Dictionary:
	var by := {}
	for r in games:
		if not Matrix.decisive(r):
			continue
		var side := str(r.get("paths", {}).get(CANDLEWAKE, {}).get("branch", ""))
		if side.is_empty():
			continue
		var t: Array = by.get(side, [0, 0])
		t[1] += 1
		if str(r.winner) == CANDLEWAKE:
			t[0] += 1
		by[side] = t
	var ok := not by.is_empty()
	var parts := []
	var sides: Array = by.keys()
	sides.sort()
	for side in sides:
		var share := _ratio(by[side][0], by[side][1])
		ok = ok and _in(share, P1C_BAND)
		parts.append("%s %s of %d" % [side, _pct(share), by[side][1]])
	return {"band": "P1c", "value": 0.0, "target": "each fork side %s-%s" % [_pct(P1C_BAND[0]), _pct(P1C_BAND[1])],
		"detail": "; ".join(parts), "status": ("pass" if ok else "miss") if not by.is_empty() else "no games"}


## The share of the Candlewake's force that `key` ("harvest" or "risen") raised over `games`.
static func _force_share(games: Array, key: String) -> float:
	var part := 0
	var force := 0
	for r in games:
		var w := _wick(r)
		part += int(w.get(key, 0))
		force += int(w.get("harvest", 0)) + int(w.get("risen", 0))
		var rec: Dictionary = r.get("recruits", {}).get(CANDLEWAKE, {})
		var cmd := str(FactionData.row(CANDLEWAKE).get("commander", {}).get("id", ""))
		for tid in rec:
			if str(tid) != cmd:
				force += int(rec[tid])
	return _ratio(part, force)


static func _wick(r: Dictionary) -> Dictionary:
	return r.get("wick", {}).get(CANDLEWAKE, {})


## The markdown table of `rows` (judge).
static func table(rows: Array) -> String:
	var L := ["| band | pair | target | measured | status |", "|---|---|---|---|---|"]
	for row in rows:
		L.append("| %s | %s | %s | %s | %s |" % [row.band, str(row.get("pair", "")).replace("|", " vs "), row.target, row.detail, row.status])
	return "\n".join(L)


static func _row(band: String, key: String, value: float, target: Array, detail: String, any: bool) -> Dictionary:
	var fmt := "%s-%s" % [_pct(target[0]), _pct(target[1])] if float(target[1]) <= 1.0 else "%.1f-%.1f" % [target[0], target[1]]
	return {"band": band, "pair": key, "value": value, "target": fmt, "detail": detail,
		"status": ("pass" if _in(value, target) else "miss") if any else "no games"}


static func _in(v: float, band: Array) -> bool:
	return v >= float(band[0]) - 0.000001 and v <= float(band[1]) + 0.000001


static func _ratio(a: int, b: int) -> float:
	return float(a) / float(b) if b > 0 else 0.0


static func _pct(v: float) -> String:
	return "%d%%" % roundi(v * 100.0)
