class_name FogRules
## Fog of war (M5 "magic and fog of war", design/M5_MAGIC_FOG.md §2): what each player can see, and the one
## per-viewer copy of the game every screen, forecast, the 3D board and the computer read. Pure functions over
## GameState and FogData: no nodes, no scenes, no randomness (fog draws nothing).
##
## Fog is a lens, not a rule (§2.1). The resolver never reads GameState.fog. Everything here only decides what a
## player is shown, from the true state, the turn's events and what that player saw before:
##   sight(state, viewer)                   {province id: "clear" | "glimpse" | "veiled"} (§2.3)
##   sources(state, viewer, pid)            why a province is seen, for the tooltip and the Vision map mode
##   round_count(n), share_out(...)         "about 20" and its range, shared out over the types (§2.4)
##   view_state(state, viewer, memory, intel)  the viewer's GameState, built by allow-list (§2.7)
##   new_memory, remember                   last seen (§2.5): derived from the record, never saved
##   new_intel, learn                       what the viewer knows of each rival's build (§2.6)
##   report_for(events, viewer, before, after, memory, intel)   the viewer's turn report (§2.8)
##   view_model, apply_view_events          the per-viewer playback fold: view_before + report = view_after
##
## The observer, OBSERVER ("@observer"), sees the truth: AI-vs-AI watch mode, the autoplay's invariants and the
## victory screen use it. It is a named constant, never a default ("" already means "the faction itself" in
## Forecast and "public text" in the turn report).
##
## The view state (§2.7) is a fresh GameState with is_view set and view_of naming its viewer. It gets only:
##   - provinces: their public fields (owner, terrain, income, neighbours, capital, fort; with sieges the fort's
##     level, walls, builder and who has owned it since when). A construction site shows where the province is in
##     sight; a siege's start turn shows where the view holds both sides' armies, as the siege rules need.
##   - the viewer's own faction and armies, complete, with their true ids.
##   - each rival's public facts (roster, ruler, its status, generation and successor, the side of its fork) and
##     what the viewer knows (intel): known mandates, known path nodes, kept power known or assumed. Gold, research,
##     sacrifices and every counter are zeroed.
##   - rival armies as stand-ins, pooled per (faction, province), with view ids and a view note (Army.seen):
##     exact in clear sight, rounded when glimpsed, remembered when out of sight.
##   - enchantments: the viewer's own, a rival's where it can be seen (with view ids), and every global one.
##   - zeroed counters: rivals' army numbers, the RNG and the seed.
## Anything not copied can't leak, including fields future milestones add. GameState.validate relaxes exactly
## four checks for a view's rivals (GameState.view_relaxes).
##
## M3c sieges under fog (M5-1's calls, since the spec predates sieges; "public or seen"):
##   fort level, walls, fort_by, owned_since, lost   public (forts and owners are public)
##   works (a construction site)                      seen: copied where the province is in clear sight or glimpsed
##   siege_since                                      seen: kept where the view holds both the owner's armies and
##                                                    another faction's (with two factions, every siege is in clear
##                                                    sight of both sides)
##   Army.engines                                     seen in clear sight only: the rival's engines in a province are
##                                                    pooled and spread over its stand-ins (at most 3 each; a siege
##                                                    counts at most FortData.SIEGE.engines_max = 3 anyway). Glimpsed
##                                                    and remembered stand-ins carry none.

const OBSERVER := "@observer"
const CLEAR := "clear"
const GLIMPSE := "glimpse"
const VEILED := "veiled"
const BATTLE_TYPES := ["battle", "border_battle"]


static func has_fog(state: GameState) -> bool:
	return state != null and state.fog


# --- sight (§2.3) -----------------------------------------------------------------------------------

## {province id: "clear" | "glimpse" | "veiled"} for `viewer` on `state`, in province id order. In clear sight:
## provinces it owns, where one of its armies stands, and where its Far Sight is (MagicRules.vision_grants).
## Glimpsed: not clear, and within the range of one of its sight sources (FogData.SIGHT). The observer sees all.
static func sight(state: GameState, viewer: String) -> Dictionary:
	var out := {}
	var ids := _province_ids(state)
	if viewer == OBSERVER:
		for pid in ids:
			out[pid] = CLEAR
		return out
	var clear := _clear_set(state, viewer)
	var seen := {}
	for src in sight_sources(state, viewer):
		for pid in distances(state, String(src.province), int(src.range)):
			seen[pid] = true
	for pid in ids:
		out[pid] = CLEAR if clear.has(pid) else (GLIMPSE if seen.has(pid) else VEILED)
	return out


## The viewer's sight sources (§2.3): [{"kind": "owned" | "fort" | "army" | "far_sight", "province", "range",
## "why" ("" or, for an army, "ruler" | "commander" | "scout"), "army" (an army source's id), "scout" (the scout
## type's name)}], in a fixed order: provinces, then forts, then armies by id, then Far Sight.
static func sight_sources(state: GameState, viewer: String) -> Array:
	var out := []
	for p in _sorted_provinces(state):
		if p.owner == viewer:
			out.append({"kind": "owned", "province": p.id, "range": int(FogData.SIGHT.owned), "why": "", "army": "", "scout": ""})
	for p in _sorted_provinces(state):
		if p.owner == viewer and p.has_fort:
			out.append({"kind": "fort", "province": p.id, "range": int(FogData.SIGHT.fort), "why": "", "army": "", "scout": ""})
	for a in _sorted_armies(state):
		if a.owner != viewer:
			continue
		var s := army_sight(a)
		out.append({"kind": "army", "province": a.location, "range": int(s.range), "why": String(s.why), "army": a.id,
			"scout": String(s.scout)})
	for pid in MagicRules.vision_grants(state, viewer):
		out.append({"kind": "far_sight", "province": String(pid), "range": 0, "why": "", "army": "", "scout": ""})
	return out


## How far one army sees (§2.3): {"range", "why", "scout"}: 2 with a ruler ("ruler"), a commander ("commander")
## or a scout unit ("scout", with the first scout's name), otherwise 1.
static func army_sight(army: Army) -> Dictionary:
	if army.ruler != null:
		return {"range": int(FogData.SIGHT.ruler), "why": "ruler", "scout": ""}
	if army.commander != null:
		return {"range": int(FogData.SIGHT.commander), "why": "commander", "scout": ""}
	for u in army.units:
		if is_scout(u.type):
			return {"range": int(FogData.SIGHT.scout), "why": "scout", "scout": u.type.name}
	return {"range": int(FogData.SIGHT.army), "why": "", "scout": ""}


## A scout sees 2 provinces (§2.3): its type id is in FogData.SCOUTS.
static func is_scout(ut: UnitType) -> bool:
	return ut != null and FogData.SCOUTS.has(ut.id)


## {province id: steps from `from`} for every province at most `max_range` steps away along the neighbour links,
## `from` itself at 0.
static func distances(state: GameState, from: String, max_range: int) -> Dictionary:
	var out := {}
	if state.find_province(from) == null:
		return out
	out[from] = 0
	var frontier := [from]
	for d in range(1, max_range + 1):
		var next := []
		for pid in frontier:
			var p := state.find_province(pid)
			for n in p.neighbors:
				if not out.has(n):
					out[n] = d
					next.append(n)
		frontier = next
	return out


## Why `viewer` sees province `pid` (§2.3, §11.1), for the tooltip and the Vision map mode: [{"kind", "province",
## "range", "distance", "why", "text"}], the clear reasons first. "In clear sight: you own it." / "Glimpsed from
## your army at Highcrag (range 1)." / "Glimpsed from your army at Highcrag, which has Knights (range 2)." Empty
## when it is out of sight.
static func sources(state: GameState, viewer: String, pid: String) -> Array:
	var out := []
	var p := state.find_province(pid)
	if p == null or viewer == OBSERVER:
		return out
	if p.owner == viewer:
		out.append({"kind": "owned", "province": pid, "range": 0, "distance": 0, "why": "", "text": "In clear sight: you own it."})
	for a in _sorted_armies(state):
		if a.owner == viewer and a.location == pid:
			out.append({"kind": "army", "province": pid, "range": 0, "distance": 0, "why": "",
				"text": "In clear sight: your army stands there."})
			break
	if MagicRules.vision_grants(state, viewer).has(pid):
		out.append({"kind": "far_sight", "province": pid, "range": 0, "distance": 0, "why": "",
			"text": "In clear sight: your Far Sight is on it."})
	if not out.is_empty():
		return out
	for src in sight_sources(state, viewer):
		var d = distances(state, String(src.province), int(src.range)).get(pid)
		if d == null:
			continue
		out.append({"kind": src.kind, "province": src.province, "range": src.range, "distance": int(d), "why": src.why,
			"text": _source_text(state, src)})
	return out


## One line on how far `viewer` sees at `pid` (§11.1): the first reason sources() gives, or "Out of sight: ..."
static func sight_text(state: GameState, viewer: String, pid: String) -> String:
	var why := sources(state, viewer, pid)
	if not why.is_empty():
		return String(why[0].text)
	return "Out of sight: none of your land, forts or armies is close enough to see %s." % _province_name(state, pid)


static func _source_text(state: GameState, src: Dictionary) -> String:
	var where := _province_name(state, String(src.province))
	match String(src.kind):
		"owned":
			return "Glimpsed from your land at %s (range %d)." % [where, int(src.range)]
		"fort":
			return "Glimpsed from your fort at %s (range %d)." % [where, int(src.range)]
		"army":
			var with := ""
			match String(src.why):
				"ruler":
					with = ", which has your ruler"
				"commander":
					with = ", which has a commander"
				"scout":
					with = ", which has %s" % String(src.scout)
			return "Glimpsed from your army at %s%s (range %d)." % [where, with, int(src.range)]
	return "Seen through your Far Sight on %s." % where


static func _clear_set(state: GameState, viewer: String) -> Dictionary:
	var out := {}
	for p in state.provinces:
		if p.owner == viewer:
			out[p.id] = true
	for a in state.armies:
		if a.owner == viewer:
			out[a.location] = true
	for pid in MagicRules.vision_grants(state, viewer):
		out[String(pid)] = true
	return out


# --- estimates (§2.4) -------------------------------------------------------------------------------

## The number a glimpse shows for a true total of `n`: 0 for none, FogData.ESTIMATE.few (2) for 1-2, otherwise the
## nearest step of its band (5 below 50, then 10), and at least that step.
static func shown_for(n: int) -> int:
	if n <= 0:
		return 0
	var few := int(FogData.ESTIMATE.few)
	if n <= few:
		return few
	for band in FogData.ESTIMATE.steps:
		var below := int(band.below)
		if below <= 0 or n < below:
			var step := int(band.step)
			return maxi(step, step * floori(float(n + step / 2) / step))
	return n


## A glimpsed total (§2.4): {"shown", "low", "high", "text"}. "low" and "high" are the smallest and largest true
## totals that show the same number, computed, never tabled: "about 5" is 3-7, "about 50" is 48-54, "about 60" is
## 55-64. 1-2 shows as "1-2" and counts as 2; none shows as "none".
static func round_count(n: int) -> Dictionary:
	var m := maxi(0, n)
	var shown := shown_for(m)
	var low := m
	while low > 0 and shown_for(low - 1) == shown:
		low -= 1
	var high := m
	while shown_for(high + 1) == shown:
		high += 1
	var text := "about %d" % shown
	if shown == 0:
		text = String(FogData.ESTIMATE.none_text)
	elif m <= int(FogData.ESTIMATE.few):
		text = String(FogData.ESTIMATE.few_text)
	return {"shown": shown, "low": low, "high": high, "text": text}


## An exact count in the same shape (clear sight, §2.3): {"shown": n, "low": n, "high": n, "text": "n"}.
static func exact_count(n: int) -> Dictionary:
	var m := maxi(0, n)
	return {"shown": m, "low": m, "high": m, "text": str(m)}


## Shares `shown` out over `weights` ([[key, count]], in canonical order, counts above 0) by largest remainders
## (§2.4): each key gets floor(shown x its share), the leftover goes to the largest remainders, ties to the earlier
## key, and every key present gets at least 1 (taken from the largest share, ties from the later key). The shares
## sum to `shown`, or to the number of keys when there are more keys than `shown` (only possible with 6 or more
## types in a pool of 6 or 7, which needs magic's summons). Returns {key: share}, in the weights' order.
static func share_out(shown: int, weights: Array) -> Dictionary:
	var out := {}
	if weights.is_empty():
		return out
	var total := 0
	for w in weights:
		total += int(w[1])
	if total <= 0:
		for w in weights:
			out[w[0]] = 0
		return out
	var target := maxi(shown, weights.size())
	var shares := []
	var rems := []
	var given := 0
	for w in weights:
		var exact := target * int(w[1])
		shares.append(exact / total)
		rems.append(exact % total)
		given += exact / total
	var order := range(weights.size())
	order.sort_custom(func(a, b): return rems[a] > rems[b] or (rems[a] == rems[b] and a < b))
	for i in target - given:
		shares[order[i % order.size()]] += 1
	for i in shares.size():
		while shares[i] < 1:
			var from := -1
			for j in shares.size():
				if shares[j] > 1 and (from < 0 or shares[j] >= shares[from]):
					from = j
			if from < 0:
				break
			shares[from] -= 1
			shares[i] += 1
	for i in weights.size():
		out[weights[i][0]] = shares[i]
	return out


## A glimpsed sighting of unit counts (§2.4): {"total": round_count, "counts": {type id: round count}, "shares":
## {type id: units shown}}. `weights` are [[type id, true count]] in canonical order. The total is rounded, then
## shared out over the types by their true counts; each type's low and high are the total's low and high shared out
## by the shown shares (never by the truth, so nothing finer than the shown shares leaks).
static func glimpse_counts(weights: Array) -> Dictionary:
	var total := 0
	for w in weights:
		total += int(w[1])
	var rc := round_count(total)
	var shares := share_out(int(rc.shown), weights)
	var shown_weights := []
	for w in weights:
		shown_weights.append([w[0], int(shares.get(w[0], 0))])
	var lows := share_out(int(rc.low), shown_weights)
	var highs := share_out(int(rc.high), shown_weights)
	var counts := {}
	for w in weights:
		var k = w[0]
		counts[k] = {"shown": int(shares[k]), "low": int(lows.get(k, 0)), "high": int(highs.get(k, 0)),
			"text": "about %d" % int(shares[k])}
	return {"total": rc, "counts": counts, "shares": shares}


# --- stand-ins (§2.7) -------------------------------------------------------------------------------

## The view id of a stand-in: "seen-<faction>-<province>", plus "-<slot>" ("b", "c2", ..., "ruler").
static func view_id(fid: String, pid: String, slot: String = "") -> String:
	var id := "%s%s-%s" % [FogData.VIEW_PREFIX, fid, pid]
	return id if slot.is_empty() else "%s-%s" % [id, slot]


## True for a view id (a stand-in or a rival enchantment in a view).
static func is_view_id(id: String) -> bool:
	return id.begins_with(FogData.VIEW_PREFIX)


## The canonical order of `fid`'s unit types (§2.4): its roster in order, then any other type (summoned creatures)
## by id. {type id: index}.
static func type_order(state: GameState, fid: String) -> Dictionary:
	var out := {}
	var f := state.find_faction(fid)
	if f != null:
		for ut in f.unit_types:
			out[ut.id] = out.size()
		if f.commander_type != null:
			out[f.commander_type.id] = out.size()
	return out


static func _type_index(order: Dictionary, type_id: String) -> int:
	return int(order.get(type_id, 1000))


## One rival's armies in one province now, pooled (§2.7) at `level` ("clear" or "glimpse") on turn `turn`:
## {"stand_ins": [{"slot", "units": [[type id, hp]], "commander": [type id, hp] or [], "engines", "from": [true army
## ids]}], "ruler": {} or {"hp", "from"}, "counts", "total", "blessed", "level", "turn"}. hp -1 means "at full hp"
## (the view fills in the maximum). Units go in canonical order (roster order, then hp from highest in clear
## sight); nothing about the true order of armies or units survives.
static func pool_now(state: GameState, fid: String, armies: Array, level: String, turn: int) -> Dictionary:
	var order := type_order(state, fid)
	var blessed_ids := _blessed_armies(state, fid)
	var plain := []
	var blessed := []
	var commanders := []
	var engines := 0
	var ruler := {}
	var plain_from := {}
	var blessed_from := {}
	for a in armies:
		if a.ruler != null:
			ruler = {"hp": a.ruler.current_hp, "from": [a.id]}
			continue
		var into: Array = blessed if blessed_ids.has(a.id) else plain
		var from: Dictionary = blessed_from if blessed_ids.has(a.id) else plain_from
		for u in a.units:
			into.append([u.type.id, u.current_hp])
			from[a.id] = true
		if a.commander != null:
			commanders.append([a.commander.type.id, a.commander.current_hp, a.id])
		engines += a.engines
	var by_type := func(x, y):
		var ix := _type_index(order, String(x[0]))
		var iy := _type_index(order, String(y[0]))
		if ix != iy:
			return ix < iy
		if String(x[0]) != String(y[0]):
			return String(x[0]) < String(y[0])
		return int(x[1]) > int(y[1])
	plain.sort_custom(by_type)
	blessed.sort_custom(by_type)
	commanders.sort_custom(by_type)
	var counts := {}
	var total := {}
	var blessed_shown := 0
	if level == CLEAR:
		var n := {}
		for u in plain + blessed:
			n[u[0]] = int(n.get(u[0], 0)) + 1
		for k in _ordered_keys(n, order):
			counts[k] = exact_count(int(n[k]))
		total = exact_count(plain.size() + blessed.size())
		blessed_shown = blessed.size()
	else:
		var gp := glimpse_counts(_weights(plain, order))
		var gb := glimpse_counts(_weights(blessed, order))
		plain = _full_units(gp.shares)
		blessed = _full_units(gb.shares)
		for c in commanders:
			c[1] = -1
		var keys := _ordered_keys(_merge_keys(gp.counts, gb.counts), order)
		for k in keys:
			var a: Dictionary = gp.counts.get(k, {"shown": 0, "low": 0, "high": 0})
			var b: Dictionary = gb.counts.get(k, {"shown": 0, "low": 0, "high": 0})
			var shown := int(a.shown) + int(b.shown)
			counts[k] = {"shown": shown, "low": int(a.low) + int(b.low), "high": int(a.high) + int(b.high), "text": "about %d" % shown}
		total = round_count(_count_units(armies, blessed_ids, false) + _count_units(armies, blessed_ids, true))
		blessed_shown = int(gb.total.shown)
	var stand_ins := []
	if not plain.is_empty() or not commanders.is_empty():
		var from := plain_from.duplicate()
		if not commanders.is_empty():
			from[commanders[0][2]] = true
		stand_ins.append({"slot": "", "units": plain, "commander": [commanders[0][0], commanders[0][1]] if not commanders.is_empty() else [],
			"engines": 0, "from": _sorted_keys(from)})
	if not blessed.is_empty():
		stand_ins.append({"slot": "b", "units": blessed, "commander": [], "engines": 0, "from": _sorted_keys(blessed_from)})
	for i in range(1, commanders.size()):
		stand_ins.append({"slot": "c%d" % (i + 1), "units": [], "commander": [commanders[i][0], commanders[i][1]], "engines": 0,
			"from": [commanders[i][2]]})
	if level == CLEAR and state.sieges and engines > 0:
		for s in stand_ins:
			var take := mini(engines, FortData.ARMY_ENGINES_MAX)
			s.engines = take
			engines -= take
			if engines <= 0:
				break
	if level != CLEAR and not ruler.is_empty():
		ruler.hp = -1
	return {"stand_ins": stand_ins, "ruler": ruler, "counts": counts, "total": total, "blessed": blessed_shown,
		"level": level, "turn": turn}


## One rival's sighting (§2.4): what `armies` (all of one faction, in one province) show at `level` on turn `turn`:
## {"level", "turn", "total": round count, "counts": {type id: round count}, "blessed", "commanders": [type ids],
## "ruler": the ruler's type id or ""}. Exact in clear sight, rounded and shared out when glimpsed.
static func sighting(state: GameState, fid: String, armies: Array, level: String, turn: int) -> Dictionary:
	var pool := pool_now(state, fid, armies, level, turn)
	var commanders := []
	for s in pool.stand_ins:
		if not s.commander.is_empty():
			commanders.append(String(s.commander[0]))
	var ruler := ""
	for a in armies:
		if a.ruler != null:
			ruler = a.ruler.type.id
	return {"level": level, "turn": turn, "total": pool.total, "counts": pool.counts, "blessed": pool.blessed,
		"commanders": commanders, "ruler": ruler}


static func _count_units(armies: Array, blessed_ids: Dictionary, blessed: bool) -> int:
	var n := 0
	for a in armies:
		if a.ruler == null and blessed_ids.has(a.id) == blessed:
			n += a.units.size()
	return n


static func _weights(units: Array, order: Dictionary) -> Array:
	var n := {}
	for u in units:
		n[u[0]] = int(n.get(u[0], 0)) + 1
	var out := []
	for k in _ordered_keys(n, order):
		out.append([k, int(n[k])])
	return out


static func _full_units(shares: Dictionary) -> Array:
	var out := []
	for k in shares:
		for i in int(shares[k]):
			out.append([k, -1])
	return out


static func _merge_keys(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	for k in a:
		out[k] = true
	for k in b:
		out[k] = true
	return out


static func _ordered_keys(d: Dictionary, order: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort_custom(func(x, y):
		var ix := _type_index(order, String(x))
		var iy := _type_index(order, String(y))
		return ix < iy if ix != iy else String(x) < String(y))
	return keys


## The ids of `fid`'s armies a blessing of its own covers (magic, §6.4): a blessing's glow is visible.
static func _blessed_armies(state: GameState, fid: String) -> Dictionary:
	var out := {}
	for e in state.enchantments:
		if String(e.get("faction", "")) == fid and String(e.get("kind", "")) == "blessing":
			for aid in e.get("armies", []):
				out[String(aid)] = true
	return out


## The stand-ins of `viewer`'s view of `state` (§2.7), before they become armies, sorted by view id:
## [{"id", "owner", "location", "units", "commander", "ruler" (-1 full, or hp; null for none), "engines", "note",
## "from" (the true army ids pooled into it; [] for a remembered one)}]. Rivals' armies in provinces in sight come
## from the truth; out of sight, from `memory`.
static func stand_ins(state: GameState, viewer: String, view_sight: Dictionary, memory: Dictionary) -> Array:
	var out := []
	var mem_provinces: Dictionary = memory.get("provinces", {})
	var mem_rulers: Dictionary = memory.get("rulers", {})
	for f in _sorted_factions(state):
		if f.id == viewer:
			continue
		var by_place := {}
		for a in _sorted_armies(state):
			if a.owner == f.id:
				if not by_place.has(a.location):
					by_place[a.location] = []
				by_place[a.location].append(a)
		for pid in _province_ids(state):
			var level := String(view_sight.get(pid, VEILED))
			if level != VEILED:
				if not by_place.has(pid):
					continue
				var pool := pool_now(state, f.id, by_place[pid], level, state.current_turn)
				_add_stand_ins(out, f.id, pid, pool, _note(pool, level, state.current_turn), true)
				if not pool.ruler.is_empty():
					out.append(_ruler_stand_in(f.id, pid, int(pool.ruler.hp), level, state.current_turn, pool.ruler.from))
				continue
			var mem: Dictionary = mem_provinces.get(pid, {}).get("pools", {}).get(f.id, {})
			if not mem.is_empty():
				_add_stand_ins(out, f.id, pid, mem, _note(mem, FogData.MEMORY, int(mem.turn)), false)
			var rm: Dictionary = mem_rulers.get(f.id, {})
			if not rm.is_empty() and String(rm.province) == pid and RulerRules.ruler_alive(state, f.id):
				out.append(_ruler_stand_in(f.id, pid, int(rm.hp), FogData.MEMORY, int(rm.turn), []))
	out.sort_custom(func(a, b): return String(a.id) < String(b.id))
	return out


static func _add_stand_ins(out: Array, fid: String, pid: String, pool: Dictionary, note: Dictionary, now: bool) -> void:
	for s in pool.stand_ins:
		out.append({"id": view_id(fid, pid, String(s.slot)), "owner": fid, "location": pid, "units": s.units.duplicate(true),
			"commander": s.commander.duplicate(), "ruler": null, "engines": int(s.get("engines", 0)), "note": note.duplicate(true),
			"from": s.get("from", []).duplicate() if now else []})


static func _ruler_stand_in(fid: String, pid: String, hp: int, level: String, turn: int, from: Array) -> Dictionary:
	return {"id": view_id(fid, pid, "ruler"), "owner": fid, "location": pid, "units": [], "commander": [], "ruler": hp,
		"engines": 0, "note": {"level": level, "turn": turn, "counts": {}, "total": round_count(0), "blessed": 0},
		"from": from.duplicate()}


## The view note (Army.seen) of a pool's stand-ins: its level and turn, and the sighting of its units.
static func _note(pool: Dictionary, level: String, turn: int) -> Dictionary:
	return {"level": level, "turn": turn, "counts": pool.counts.duplicate(true), "total": pool.total.duplicate(),
		"blessed": int(pool.blessed)}


## A pool in its memory form (§2.5): no true ids, nothing but what was shown.
static func _memory_pool(pool: Dictionary, marching: String = "") -> Dictionary:
	var ins := []
	for s in pool.stand_ins:
		ins.append({"slot": s.slot, "units": s.units.duplicate(true), "commander": s.commander.duplicate(), "engines": int(s.engines)})
	return {"turn": int(pool.turn), "level": String(pool.level), "marching": marching, "stand_ins": ins,
		"counts": pool.counts.duplicate(true), "total": pool.total.duplicate(), "blessed": int(pool.blessed)}


# --- the view state (§2.7) ------------------------------------------------------------------------------

## `viewer`'s view of `state` (§2.7): a GameState with is_view set, built by allow-list from the truth, `memory`
## (remember) and `intel` (learn). The observer gets an exact copy of the truth. Pure: `state` is not changed.
static func view_state(state: GameState, viewer: String, memory: Dictionary = {}, intel: Dictionary = {}) -> GameState:
	if state == null:
		return null
	if viewer == OBSERVER:
		return state.deep_copy()
	return build_view(state, viewer, memory, intel).view


## view_state with what went into it: {"view": GameState, "sight": sight(), "stand_ins": stand_ins()}.
static func build_view(state: GameState, viewer: String, memory: Dictionary = {}, intel: Dictionary = {}) -> Dictionary:
	var view_sight := sight(state, viewer)
	var ins := stand_ins(state, viewer, view_sight, memory)
	var truth := state.to_dict()
	var d := {}
	# Provinces: their public fields. A construction site is seen where the province is in sight.
	var provinces := []
	for p in truth.provinces:
		var level := String(view_sight.get(p.id, VEILED))
		var c := {}
		for key in ["id", "name", "terrain", "income", "neighbors", "owner", "is_capital", "has_fort"]:
			c[key] = p[key] if not (p[key] is Array) else p[key].duplicate()
		if state.sieges:
			for key in ["fort_level", "walls", "fort_by"]:
				c[key] = p[key]
			c["works"] = p.works.duplicate() if level != VEILED else {}
			c["siege_since"] = 0  # set below, once the view's armies are known
			c["owned_since"] = p.owned_since
			c["lost"] = p.lost.duplicate()
		provinces.append(c)
	# Factions: the viewer's whole; each rival's public facts and what the viewer knows.
	var factions := []
	for f in truth.factions:
		if f.id == viewer:
			factions.append(f.duplicate(true))
		else:
			factions.append(_rival_faction(state, f, intel.get(f.id, {})))
	# Armies: the viewer's own with their true ids, then the stand-ins.
	var armies := []
	for a in truth.armies:
		if a.owner == viewer:
			armies.append(a.duplicate(true))
	for a in truth.armies:
		if a.owner == IndependentData.FACTION_ID:
			armies.append(a.duplicate(true))  # IND-1 (#142): a Free Holds garrison is public knowledge, wounds and all
	var full := []  # [army index, unit index] of stand-in units shown at full hp
	for s in ins:
		var ad := {"id": s.id, "owner": s.owner, "location": s.location, "units": [], "commander": {}}
		for u in s.units:
			if int(u[1]) < 0:
				full.append([armies.size(), ad.units.size()])
			ad.units.append({"type_id": u[0], "current_hp": maxi(1, int(u[1])), "owner": s.owner})
		if not s.commander.is_empty():
			ad.commander = {"type_id": s.commander[0], "current_hp": int(s.commander[1]), "owner": s.owner}
			if int(s.commander[1]) < 0:
				ad.commander.current_hp = _type_hp(state, s.owner, String(s.commander[0]))
		if s.ruler != null:
			var rf := _faction_dict(factions, String(s.owner))
			var max_hp := int(RulerRules.ruler_stats(String(rf.ruler_type), int(rf.kept_power), int(rf.ruler_generation)).hp)
			var hp := int(s.ruler)
			ad["ruler"] = {"type_id": String(rf.ruler_type), "current_hp": max_hp if hp < 0 else clampi(hp, 1, max_hp), "owner": s.owner}
		if int(s.engines) > 0:
			ad["engines"] = int(s.engines)
		ad["seen"] = s.note.duplicate(true)
		armies.append(ad)
	if state.sieges:
		for c in provinces:
			var p := state.find_province(String(c.id))
			if p.siege_since > 0 and _both_sides_in(armies, String(c.id), String(c.owner)):
				c.siege_since = p.siege_since
	d["provinces"] = provinces
	d["factions"] = factions
	d["armies"] = armies
	d["current_turn"] = state.current_turn
	d["seed_value"] = Serial.int64_to_str(0)
	var next := {}
	for f in state.factions:
		next[f.id] = int(state.next_army_ids.get(f.id, 1)) if f.id == viewer else 1
	d["next_army_ids"] = next
	d["rng"] = SeededRNG.new(0).to_dict()
	if state.paths:
		d["paths"] = true
	if state.sieges:
		d["sieges"] = true
	if state.fog:
		d["fog"] = true
	if state.independents:
		d["independents"] = true
	if state.magic:
		d["magic"] = true
		d["enchantments"] = _view_enchantments(state, viewer, view_sight, ins)
	d["is_view"] = true
	d["view_of"] = viewer
	var errors := []
	var view := GameState.from_dict(d, errors)
	if view == null:
		push_error("FogRules.view_state: the view of %s does not load: %s" % [viewer, " ".join(errors)])
		return {"view": null, "sight": view_sight, "stand_ins": ins}
	for at in full:
		var u: Unit = view.armies[at[0]].units[at[1]]
		u.current_hp = RulerRules.unit_max_hp(view, u)
	return {"view": view, "sight": view_sight, "stand_ins": ins}


## A rival faction in a view (§2.7): public facts, intel, and zeros.
static func _rival_faction(state: GameState, f: Dictionary, known: Dictionary) -> Dictionary:
	var c := {"id": f.id, "name": f.name, "gold": 0, "capital": f.capital, "unit_types": f.unit_types.duplicate(true),
		"commander_type": f.commander_type.duplicate(true)}
	if f.has("ruler_type"):
		var mandates := known_mandates(known)
		c["ruler_type"] = f.ruler_type
		c["kept_power"] = view_kept_power(known, mandates)
		c["mandates"] = mandates
		c["ruler_generation"] = f.ruler_generation
		c["ruler_status"] = f.ruler_status
		c["successor_turn"] = f.successor_turn
		c["successor_power"] = f.successor_power
		c["sacrifices"] = []
	if state.paths:
		c["research_points"] = 0
		c["research_target"] = ""
		c["researched"] = known_nodes(known)
		c["path_branch"] = f.get("path_branch", "")
	if state.magic:
		c["spellbook"] = {}
		c["enchant_counter"] = 0
		c["bastions"] = []
	return c


## The mandates a viewer knows a rival has, sorted by id.
static func known_mandates(known: Dictionary) -> Array:
	var out: Array = Serial.to_string_array(known.get("mandates", []))
	out.sort()
	return out


## The path nodes a viewer knows a rival has researched, sorted by turn then id: [{"node", "turn"}].
static func known_nodes(known: Dictionary) -> Array:
	var out := []
	for n in known.get("nodes", []):
		out.append({"node": String(n.node), "turn": int(n.turn)})
	out.sort_custom(func(a, b): return a.turn < b.turn or (a.turn == b.turn and String(a.node) < String(b.node)))
	return out


## A rival's kept power in a view (§2.6): known, or assumed 10, and never more than 10 minus the cost of the
## mandates the viewer knows (the most it could be).
static func view_kept_power(known: Dictionary, mandates: Array) -> int:
	var cap := RulerData.POWER_POOL
	for mid in mandates:
		cap -= RulerRules.mandate_cost(String(mid))
	cap = maxi(0, cap)
	var kept := int(known.get("kept_power", -1))
	return cap if kept < 0 else mini(kept, cap)


static func _faction_dict(factions: Array, fid: String) -> Dictionary:
	for f in factions:
		if f.id == fid:
			return f
	return {}


static func _type_hp(state: GameState, fid: String, type_id: String) -> int:
	var f := state.find_faction(fid)
	if f == null:
		return 1
	if f.commander_type != null and f.commander_type.id == type_id:
		return f.commander_type.hp
	for ut in f.unit_types:
		if ut.id == type_id:
			return ut.hp
	return 1


static func _both_sides_in(armies: Array, pid: String, owner: String) -> bool:
	if owner.is_empty():
		return false
	var mine := false
	var other := false
	for a in armies:
		if a.location != pid:
			continue
		if a.owner == owner:
			mine = true
		else:
			other = true
	return mine and other


## The enchantments in a view (§2.7): the viewer's own with their true ids; a rival's only where its province, or
## for a blessing one of its armies, is in clear sight or glimpsed, with a view id; every global one.
static func _view_enchantments(state: GameState, viewer: String, view_sight: Dictionary, ins: Array) -> Array:
	var out := []
	for e in state.enchantments:
		var c := MagicRules.enchantment_copy(e)
		if c.faction == viewer:
			out.append(c)
			continue
		var global: bool = c.kind == "global"
		var pid := String(c.province)
		if not global and String(view_sight.get(pid, VEILED)) == VEILED:
			continue
		c.id = "%s%s" % [FogData.VIEW_PREFIX, c.ritual] if global else "%s%s-%s" % [FogData.VIEW_PREFIX, c.ritual, pid]
		var seen_armies := []
		if c.kind == "blessing":
			for s in ins:
				if s.owner == c.faction and String(s.id).ends_with("-b") and not s.from.is_empty():
					for aid in e.get("armies", []):
						if s.from.has(String(aid)) and not seen_armies.has(s.id):
							seen_armies.append(s.id)
		c.armies = seen_armies
		out.append(c)
	out.sort_custom(func(a, b): return String(a.id) < String(b.id))
	return out


# --- memory (§2.5) ------------------------------------------------------------------------------

## The viewer's memory at the start of the game: what it sees of `state` (remember's step 2).
static func new_memory(state: GameState, viewer: String) -> Dictionary:
	return remember({}, viewer, null, state, [])


## The viewer's memory after a resolved turn (§2.5), from its memory before, the true states before and after the
## turn and the resolver's events. Pure and JSON-safe: {"provinces": {province id: {"seen_turn", "seen_level",
## "pools": {faction id: pool}, "fought": {faction id: {"turn", "survivors": {type id: n}, "hp"}}}}, "rulers":
## {faction id: {"province", "turn", "level", "hp" (-1: at full hp)}}}. In order:
##   1. moves seen leaving: a rival move out of a province the viewer could see enters memory where it was seen
##      heading (its first step), if that is out of sight now ("marching" names where it came from);
##   2. what it sees now: every province in sight replaces its pools with the current view (empty if no rival is
##      there); a rival ruler is remembered once, at its latest sighting, and forgotten when seen gone or dead;
##   3. battles it fought: the enemy's survivors where the battle ended, kept beside the current view;
##   4. provinces out of sight keep what they had.
## `sights` may carry the viewer's sight of `before` and `after` ({"before", "after"}) when the caller has them.
static func remember(memory: Dictionary, viewer: String, before: GameState, after: GameState, events: Array, sights: Dictionary = {}) -> Dictionary:
	var out := memory.duplicate(true)
	if not out.has("provinces"):
		out["provinces"] = {}
	if not out.has("rulers"):
		out["rulers"] = {}
	if viewer == OBSERVER or after == null:
		return out
	var turn := after.current_turn
	var after_sight: Dictionary = sights.get("after", {}) if sights.has("after") else sight(after, viewer)
	var before_sight: Dictionary = sights.get("before", {}) if sights.has("before") else (sight(before, viewer) if before != null else {})
	# 1. moves seen leaving
	if before != null:
		var groups := {}
		for e in events:
			if String(e.get("type", "")) != "army_moved" or e.factions.is_empty() or e.armies.is_empty():
				continue
			var fid := String(e.factions[0])
			var from := String(e.provinces[0])
			if fid == viewer or String(before_sight.get(from, VEILED)) == VEILED:
				continue
			var to := String(e.provinces[1])
			var key := "%s|%s" % [fid, to]
			if not groups.has(key):
				groups[key] = {"faction": fid, "to": to, "from": from, "armies": [], "clear": true}
			groups[key].armies.append(String(e.armies[0]))
			if String(before_sight.get(from)) != CLEAR:
				groups[key].clear = false
		var keys := groups.keys()
		keys.sort()
		for key in keys:
			var g: Dictionary = groups[key]
			if String(after_sight.get(g.to, VEILED)) != VEILED:
				continue
			var movers := []
			for aid in g.armies:
				var a := before.find_army(aid)
				if a != null:
					movers.append(a)
			movers.sort_custom(func(a, b): return a.id < b.id)
			var level := CLEAR if g.clear else GLIMPSE
			var pool := pool_now(before, g.faction, movers, level, turn)
			var entry := _memory_entry(out.provinces, g.to)
			if not pool.stand_ins.is_empty():
				entry.pools[g.faction] = _memory_pool(pool, g.from)
			if not pool.ruler.is_empty():
				out.rulers[g.faction] = {"province": g.to, "turn": turn, "level": level, "hp": int(pool.ruler.hp)}
	# 2. what it sees now
	var by_place := {}
	for a in _sorted_armies(after):
		if a.owner != viewer:
			var key := "%s|%s" % [a.owner, a.location]
			if not by_place.has(key):
				by_place[key] = []
			by_place[key].append(a)
	for pid in _province_ids(after):
		var level := String(after_sight.get(pid, VEILED))
		if level == VEILED:
			continue
		var entry := _memory_entry(out.provinces, pid)
		entry.seen_turn = turn
		entry.seen_level = level
		entry.pools = {}
		for f in _sorted_factions(after):
			var key := "%s|%s" % [f.id, pid]
			if f.id == viewer or not by_place.has(key):
				continue
			var pool := pool_now(after, f.id, by_place[key], level, turn)
			if not pool.stand_ins.is_empty():
				entry.pools[f.id] = _memory_pool(pool)
			if not pool.ruler.is_empty():
				out.rulers[f.id] = {"province": pid, "turn": turn, "level": level, "hp": int(pool.ruler.hp)}
	for f in _sorted_factions(after):
		if f.id == viewer or not out.rulers.has(f.id):
			continue
		var rm: Dictionary = out.rulers[f.id]
		var army := RulerRules.ruler_army(after, f.id)
		var seen_there := army != null and army.location == String(rm.province) and int(rm.turn) == turn
		if not RulerRules.ruler_alive(after, f.id) or (String(after_sight.get(String(rm.province), VEILED)) != VEILED and not seen_there):
			out.rulers.erase(f.id)
	# 3. battles it fought
	for e in events:
		if not BATTLE_TYPES.has(String(e.get("type", ""))) or not e.factions.has(viewer):
			continue
		var report: Dictionary = e.numbers.get("report", {})
		var winner := String(e.numbers.get("winner", ""))
		for sr in report.get("sides", []):
			var fid := String(sr.faction)
			if fid == viewer:
				continue
			var site := _battle_end(e, fid, winner, events)
			var survivors := {}
			if fid == winner:
				survivors = _survivors(sr)
			var entry := _memory_entry(out.provinces, site)
			entry.fought[fid] = {"turn": turn, "survivors": survivors, "hp": int(sr.get("hp_end", 0)) if fid == winner else 0}
			if String(after_sight.get(site, VEILED)) == VEILED and fid == winner:
				entry.pools[fid] = _survivor_pool(after, fid, survivors, turn)
	return _canonical_memory(out)


static func _memory_entry(provinces: Dictionary, pid: String) -> Dictionary:
	if not provinces.has(pid):
		provinces[pid] = {"seen_turn": -1, "seen_level": "", "pools": {}, "fought": {}}
	return provinces[pid]


## Where a battle ended for `fid`'s side: the province of a province battle; for a border battle the winner's
## destination (its won_border_battle move), else the first border province.
static func _battle_end(e: Dictionary, fid: String, winner: String, events: Array) -> String:
	if String(e.type) != "border_battle" or fid != winner:
		return String(e.provinces[0])
	for m in events:
		if String(m.get("type", "")) == "army_moved" and String(m.get("cause", "")) == "won_border_battle" \
				and not m.factions.is_empty() and String(m.factions[0]) == fid and not m.armies.is_empty() and e.armies.has(m.armies[0]):
			return String(m.provinces.back())
	return String(e.provinces[0])


## The units of a battle report side still standing at the end (its roster at the start, less the fighters it
## lost): {type id: n}, in roster order. Commanders are counted too.
static func _survivors(sr: Dictionary) -> Dictionary:
	var lost := {}
	for name in sr.get("lost", []):
		lost[String(name)] = int(lost.get(String(name), 0)) + 1
	var out := {}
	var roster: Dictionary = sr.get("roster", {})
	for u in roster.get("units", []):
		var left := int(u.count) - int(lost.get(String(u.name), 0))
		lost[String(u.name)] = maxi(0, int(lost.get(String(u.name), 0)) - int(u.count))
		if left > 0:
			out[String(u.id)] = left
	for c in roster.get("commanders", []):
		if int(lost.get(String(c.name), 0)) > 0:
			lost[String(c.name)] = int(lost[String(c.name)]) - 1
		else:
			out[String(c.id)] = int(out.get(String(c.id), 0)) + 1
	return out


## A remembered pool of a battle's survivors (exact counts, hp unknown one by one: -1).
static func _survivor_pool(state: GameState, fid: String, survivors: Dictionary, turn: int) -> Dictionary:
	var f := state.find_faction(fid)
	var cmd_id := f.commander_type.id if f != null and f.commander_type != null else ""
	var units := []
	var commanders := []
	var counts := {}
	var n := 0
	for k in survivors:
		if String(k) == cmd_id:
			for i in int(survivors[k]):
				commanders.append([k, -1])
			continue
		for i in int(survivors[k]):
			units.append([k, -1])
		counts[k] = exact_count(int(survivors[k]))
		n += int(survivors[k])
	var ins := []
	if not units.is_empty() or not commanders.is_empty():
		ins.append({"slot": "", "units": units, "commander": commanders[0] if not commanders.is_empty() else [], "engines": 0})
	for i in range(1, commanders.size()):
		ins.append({"slot": "c%d" % (i + 1), "units": [], "commander": commanders[i], "engines": 0})
	return {"turn": turn, "level": CLEAR, "marching": "", "stand_ins": ins, "counts": counts, "total": exact_count(n), "blessed": 0}


## Memory with its keys in sorted order, so equal memories serialize to the same bytes.
static func _canonical_memory(memory: Dictionary) -> Dictionary:
	var provinces := {}
	var pids: Array = memory.provinces.keys()
	pids.sort()
	for pid in pids:
		var e: Dictionary = memory.provinces[pid]
		provinces[pid] = {"seen_turn": int(e.seen_turn), "seen_level": String(e.seen_level), "pools": _sorted_dict(e.pools),
			"fought": _sorted_dict(e.fought)}
	return {"provinces": provinces, "rulers": _sorted_dict(memory.rulers)}


static func _sorted_dict(d: Dictionary) -> Dictionary:
	var out := {}
	var keys := d.keys()
	keys.sort()
	for k in keys:
		out[k] = d[k]
	return out


# --- intel (§2.6) -------------------------------------------------------------------------------

## What the viewer knows of each rival at the start: nothing but public facts. {faction id: {"mandates": [],
## "nodes": [], "spells": [], "kept_power": -1 (unknown), "kept_turn": 0}}, with the rulers it already sees learned.
static func new_intel(state: GameState, viewer: String) -> Dictionary:
	return learn({}, viewer, [], state)


## The viewer's intel after a turn (§2.6): one rule, you learn a rival's mandate, path node or spell when something
## you are shown names it. `shown` are the viewer's own filtered events (report_for without the synthetic ones);
## `after` is the true state, read only for rivals' rulers in the viewer's sight (kept power is learned whenever you
## see or fight the ruler, at any sight level, and at its heralded death and succession). Learned facts stay
## learned. Pure and JSON-safe. `after_sight`: the viewer's sight of `after`, when the caller has it.
static func learn(intel: Dictionary, viewer: String, shown: Array, after: GameState, after_sight: Dictionary = {}) -> Dictionary:
	var out := {}
	if viewer == OBSERVER or after == null:
		return intel.duplicate(true)
	for f in _sorted_factions(after):
		if f.id == viewer:
			continue
		var k: Dictionary = intel.get(f.id, {}).duplicate(true)
		for key in ["mandates", "nodes", "spells"]:
			if not k.has(key):
				k[key] = []
		if not k.has("kept_power"):
			k["kept_power"] = -1
		if not k.has("kept_turn"):
			k["kept_turn"] = 0
		out[f.id] = k
	var turn := after.current_turn
	for e in shown:
		var t := String(e.get("type", ""))
		var fid := String(e.factions[0]) if not e.get("factions", []).is_empty() else ""
		if BATTLE_TYPES.has(t):
			var report: Dictionary = e.numbers.get("report", {})
			for sr in report.get("sides", []):
				var sf := String(sr.faction)
				if not out.has(sf):
					continue
				for m in sr.get("mandates", []):
					_learn_mandate(out[sf], String(m.get("id", "")))
				var r: Dictionary = sr.get("ruler", {})
				if not r.is_empty():
					_learn_kept(out[sf], int(r.kept_power), turn)
				for nid in _log_nodes(e.numbers.get("log", {}), sf):
					_learn_node(out[sf], nid, turn)
			continue
		# M5-6 (§2.6): a rival's ritual that fell on your land, or its global ritual heralded, names a spell it knows; a
		# Far Sight reading of its capital gives its mandates, nodes and kept power, as of that turn.
		if t == "ritual_fell" and e.factions.size() > 1 and out.has(String(e.factions[1])):
			if MagicRules.is_arcana(String(e.numbers.get("ritual", ""))):  # Far Sight is no node: every caster knows it
				_learn_node(out[String(e.factions[1])], String(e.numbers.ritual), turn)
			continue
		if t == "far_sight_reading" and out.has(String(e.numbers.get("of", ""))):
			var r: Dictionary = e.numbers.get("reading", {})
			var k: Dictionary = out[String(e.numbers.of)]
			for m in r.get("mandates", []):
				_learn_mandate(k, String(m))
			for nid in r.get("nodes", []):
				_learn_node(k, String(nid), turn)
			if r.has("kept_power"):
				_learn_kept(k, int(r.kept_power), turn)
			continue
		if not out.has(fid) and t != "vassal_contested":
			continue
		match t:
			"vassal_joined":
				_learn_mandate(out[fid], RulerRules.SWORN_VASSALS)
			"vassal_contested":
				for other in e.factions:
					if out.has(String(other)):
						_learn_mandate(out[String(other)], RulerRules.SWORN_VASSALS)
			"oath_sworn", "transformed":
				_learn_node(out[fid], String(e.numbers.get("node", "")), int(e.numbers.get("turn", turn)))
			"ruler_died", "ruler_arrived":
				_learn_kept(out[fid], int(e.numbers.get("kept_power", 0)), turn)
			"ritual_cast":  # M5-6: a rival's global ritual, heralded
				if MagicRules.is_arcana(String(e.numbers.get("ritual", ""))):
					_learn_node(out[fid], String(e.numbers.ritual), turn)
	if after_sight.is_empty():
		after_sight = sight(after, viewer)
	for fid in out:
		var army := RulerRules.ruler_army(after, fid)
		if army != null and String(after_sight.get(army.location, VEILED)) != VEILED:
			_learn_kept(out[fid], RulerRules.kept_power(after, fid), turn)
	for fid in out:
		out[fid].mandates.sort()
		out[fid].nodes.sort_custom(func(a, b): return a.turn < b.turn or (a.turn == b.turn and String(a.node) < String(b.node)))
	return _sorted_dict(out)


static func _learn_mandate(k: Dictionary, mid: String) -> void:
	if not mid.is_empty() and not k.mandates.has(mid):
		k.mandates.append(mid)


static func _learn_node(k: Dictionary, nid: String, turn: int) -> void:
	if nid.is_empty():
		return
	for n in k.nodes:
		if String(n.node) == nid:
			return
	k.nodes.append({"node": nid, "turn": turn})


static func _learn_kept(k: Dictionary, kept: int, turn: int) -> void:
	k.kept_power = kept
	k.kept_turn = turn


## The path nodes of `fid` whose parts worked in a battle (the "path_<node>" parts of its fighters' attack, defense,
## hp and morale in the battle log), sorted.
static func _log_nodes(battle_log, fid: String) -> Array:
	var found := {}
	if not (battle_log is Dictionary) or battle_log.is_empty():
		return []
	var sides := {}
	for s in battle_log.get("sides", []):
		sides[int(s.index)] = String(s.faction)
		if String(s.faction) == fid:
			for key in s.get("base_morale_parts", {}):
				_part_node(found, String(key))
	var side_of := {}
	for f in battle_log.get("fighters", []):
		side_of[int(f.id)] = String(sides.get(int(f.side), ""))
		if String(sides.get(int(f.side), "")) == fid:
			for key in f.get("hp_parts", {}):
				_part_node(found, String(key))
	for ev in battle_log.get("events", []):
		if String(ev.get("t", "")) != "attack":
			continue
		if String(side_of.get(int(ev.get("by", -1)), "")) == fid:
			for key in ev.get("attack", {}).get("parts", {}):
				_part_node(found, String(key))
		if String(side_of.get(int(ev.get("to", -1)), "")) == fid:
			for key in ev.get("defense", {}).get("parts", {}):
				_part_node(found, String(key))
	var out := found.keys()
	out.sort()
	return out


static func _part_node(found: Dictionary, key: String) -> void:
	if key.begins_with(AscensionRules.PART_PREFIX):
		var nid := key.substr(AscensionRules.PART_PREFIX.length())
		if not AscensionRules.node_data(nid).is_empty():
			found[nid] = true


# --- the turn report, per viewer (§2.8) ---------------------------------------------------------------

## `viewer`'s turn report (§2.8): the events it sees whole, rebuilt public events, its pooled view of rival moves it
## saw, then the synthetic events that make the playback fold exact. `before` and `after` are the true states
## around the turn; `memory` and `intel` are the viewer's at the start of the turn. Pure.
static func report_for(events: Array, viewer: String, before: GameState, after: GameState, memory: Dictionary = {},
		intel: Dictionary = {}) -> Array:
	return turn_for(events, viewer, before, after, memory, intel).events


## Everything one viewer's turn makes (§2.5-§2.8): {"events" (report_for), "shown" (the same without the synthetic
## events), "memory", "intel" (after the turn), "view_before", "view_after"}.
static func turn_for(events: Array, viewer: String, before: GameState, after: GameState, memory: Dictionary = {},
		intel: Dictionary = {}) -> Dictionary:
	if viewer == OBSERVER:
		return {"events": events.duplicate(true), "shown": events.duplicate(true), "memory": memory.duplicate(true),
			"intel": intel.duplicate(true), "view_before": before.deep_copy() if before else null,
			"view_after": after.deep_copy() if after else null}
	var built_before := build_view(before, viewer, memory, intel)
	var sights := {"before": built_before.sight, "after": sight(after, viewer)}
	var shown := filter_events(events, viewer, before, after, built_before.stand_ins, sights)
	var memory_after := remember(memory, viewer, before, after, events, sights)
	var intel_after := learn(intel, viewer, shown, after, sights.after)
	var view_after := view_state(after, viewer, memory_after, intel_after)
	var out: Array = shown.duplicate(true)
	out.append_array(synthetic_events(built_before.view, view_after, shown, viewer))
	return {"events": out, "shown": shown, "memory": memory_after, "intel": intel_after, "view_before": built_before.view,
		"view_after": view_after}


## The events of `events` the viewer is shown, before the synthetic ones (§2.8), following FogData.AUDIENCE. `ins`
## are the stand-ins of the viewer's view before the turn (stand_ins()), for the battles' view ids; computed when
## not given. `sights` may carry the viewer's sight of `before` and `after` ({"before", "after"}).
static func filter_events(events: Array, viewer: String, before: GameState, after: GameState, ins = null, sights: Dictionary = {}) -> Array:
	if viewer == OBSERVER:
		return events.duplicate(true)
	var before_sight: Dictionary = sights.get("before", {}) if sights.has("before") else sight(before, viewer)
	var after_sight: Dictionary = sights.get("after", {}) if sights.has("after") else sight(after, viewer)
	if ins == null:
		ins = stand_ins(before, viewer, before_sight, {})  # memory adds only ghosts, which no event names
	var out := []
	var moves := {}  # "phase|faction|from|to" -> index in `out` of its rebuilt move, with the armies pooled so far
	for e in events:
		var t := String(e.get("type", ""))
		var row: Dictionary = FogData.AUDIENCE.get(t, {"whole": "actor", "others": "none"})
		if _sees_whole(row, e, viewer):
			if BATTLE_TYPES.has(t):
				out.append(_participant_battle(e, viewer, before, ins))
			else:
				out.append(e.duplicate(true))
			continue
		match String(row.others):
			"rebuilt":
				out.append(_rebuilt(e, before_sight, after_sight, before, after, ins))
			"rebuilt_if_global":
				if bool(e.get("numbers", {}).get("global", false)):
					out.append(_rebuilt(e, before_sight, after_sight, before, after, ins))
			"rebuilt_named":  # M5-6: only for the factions the event names (a curse's caster hears it bit)
				if e.get("factions", []).has(viewer):
					out.append(_rebuilt(e, before_sight, after_sight, before, after, ins))
			"move":
				if e.get("factions", []).is_empty() or e.get("armies", []).is_empty() or e.get("provinces", []).size() < 2:
					continue
				var from := String(e.provinces[0])
				if String(before_sight.get(from, VEILED)) == VEILED:
					continue
				var key := "%s|%s|%s|%s" % [e.phase, e.factions[0], from, e.provinces[1]]
				if not moves.has(key):
					moves[key] = {"index": out.size(), "armies": [], "event": e}
					out.append({})
				moves[key].armies.append(String(e.armies[0]))
	for key in moves:
		var m: Dictionary = moves[key]
		out[m.index] = _rebuilt_move(m.event, m.armies, before_sight, after_sight, before, after)
	return out


static func _sees_whole(row: Dictionary, e: Dictionary, viewer: String) -> bool:
	var factions: Array = e.get("factions", [])
	match String(row.whole):
		"all":
			return true
		"factions":
			return factions.has(viewer)
	return not factions.is_empty() and String(factions[0]) == viewer


## A battle as a participant sees it (§2.8): the whole event, with its armies and numbers.destroyed rewritten to
## the view ids in the viewer's view before the turn. True ids stay only inside numbers.log (and the report's army
## names): you fought them, so you saw them.
static func _participant_battle(e: Dictionary, viewer: String, before: GameState, ins: Array) -> Dictionary:
	var c: Dictionary = e.duplicate(true)
	var rival := {}
	var own := []
	for aid in e.armies:
		var a := before.find_army(String(aid))
		if a != null and a.owner == viewer:
			own.append(String(aid))
		else:
			rival[String(aid)] = true
	var destroyed := {}
	var own_destroyed := []
	for aid in e.numbers.get("destroyed", []):
		var a := before.find_army(String(aid))
		if a != null and a.owner == viewer:
			own_destroyed.append(String(aid))
		else:
			destroyed[String(aid)] = true
	var seen := []
	var gone := []
	for s in ins:
		if String(s.owner) == viewer or s.from.is_empty():
			continue
		var fought := false
		var all_gone := true
		for aid in s.from:
			if rival.has(aid):
				fought = true
			if not destroyed.has(aid):
				all_gone = false
		if fought:
			seen.append(String(s.id))
		if fought and all_gone:
			gone.append(String(s.id))
	c.armies = own + seen
	c.numbers.destroyed = own_destroyed + gone
	return c


## A public event rebuilt for a viewer it isn't about (§2.8): a new dictionary from FogData.SAFE_NUMBERS, view ids
## and a FogData.TEXT template only. The resolver's own text and numbers never pass through.
static func _rebuilt(e: Dictionary, before_sight: Dictionary, after_sight: Dictionary, before: GameState, after: GameState, ins) -> Dictionary:
	var t := String(e.type)
	var numbers := {}
	for key in FogData.SAFE_NUMBERS.get(t, []):
		if e.numbers.has(key):
			numbers[key] = e.numbers[key] if not (e.numbers[key] is Dictionary or e.numbers[key] is Array) else e.numbers[key].duplicate(true)
	var provinces := []
	for pid in e.get("provinces", []):
		if t == "ritual_cast":
			break  # M5-6: a heralded global ritual never says where it was cast from
		if t != "ruler_died" or String(before_sight.get(pid, VEILED)) != VEILED or String(after_sight.get(pid, VEILED)) != VEILED:
			provinces.append(String(pid))
	var armies := []
	if t == "ruler_died" and ins != null:
		var true_id := String(e.armies[0]) if not e.get("armies", []).is_empty() else ""
		for s in ins:
			if s.ruler != null and s.from.has(true_id):
				armies.append(String(s.id))
	var factions: Array = e.get("factions", []).duplicate()
	return {"type": t, "phase": e.phase, "provinces": provinces, "factions": factions, "armies": armies,
		"cause": String(e.get("cause", "")), "numbers": numbers, "text": text_for(t, numbers, provinces, factions, after),
		"codex": String(e.get("codex", "")), "rebuilt": true}


## One rebuilt move (§2.8): the armies of one rival that left a province the viewer could see by the same first
## step, pooled and rounded at that province's sight level. A two-step road move names only its first step.
static func _rebuilt_move(e: Dictionary, army_ids: Array, before_sight: Dictionary, after_sight: Dictionary, before: GameState,
		after: GameState) -> Dictionary:
	var fid := String(e.factions[0])
	var from := String(e.provinces[0])
	var to := String(e.provinces[1])
	var movers := []
	for aid in army_ids:
		var a := before.find_army(aid)
		if a != null:
			movers.append(a)
	var order := type_order(before, fid)
	var n := 0
	var types := {}
	for a in movers:
		n += a.units.size()
		for u in a.units:
			types[u.type.id] = true
		if a.commander != null:
			types[a.commander.type.id] = true
	var type_list := _ordered_keys(types, order)
	for a in movers:
		if a.ruler != null:
			type_list.append(a.ruler.type.id)
	var total := exact_count(n) if String(before_sight.get(from)) == CLEAR else round_count(n)
	var numbers := {"faction": fid, "from": from, "to": to, "total": total, "types": type_list}
	var away := String(after_sight.get(to, VEILED)) == VEILED
	var text := String(FogData.TEXT.move_away if away else FogData.TEXT.move).format(_move_params(numbers, before))
	return {"type": "army_moved", "phase": e.phase, "provinces": [from, to], "factions": [fid], "armies": [], "cause": "seen",
		"numbers": numbers, "text": text, "codex": "move", "rebuilt": true, "view_from": from, "view_to": to}


static func _move_params(numbers: Dictionary, state: GameState) -> Dictionary:
	var names := []
	for type_id in numbers.types:
		names.append(type_name(state, String(numbers.faction), String(type_id)))
	return {"faction": _the_faction(state, String(numbers.faction)), "from": _province_name(state, String(numbers.from)),
		"to": _province_name(state, String(numbers.to)), "total": String(numbers.total.text), "types": RulerRules._and_list(names)}


## The FogData.SAFE_NUMBERS row an event of the viewer's report is held to (§14): "move" for a rebuilt move.
static func safe_key(e: Dictionary) -> String:
	return "move" if String(e.get("type", "")) == "army_moved" else String(e.get("type", ""))


## The text of a rebuilt event (§2.8), from its FogData.TEXT template filled in with its safe `numbers` and the
## public names of `provinces` and `factions` (read from `state`), and nothing else.
static func text_for(t: String, numbers: Dictionary, provinces: Array, factions: Array, state: GameState) -> String:
	var p := {}
	for k in numbers:
		p[k] = numbers[k]
	p["faction"] = _the_faction(state, String(factions[0])) if not factions.is_empty() else ""
	p["previous"] = _the_faction(state, String(factions[1])) if factions.size() > 1 else ""
	p["factions"] = RulerRules._and_list(factions.map(func(fid): return _the_faction(state, String(fid))))
	var pid := String(numbers.get("province", provinces[0] if not provinces.is_empty() else ""))
	p["province"] = _province_name(state, pid)
	var text := String(FogData.TEXT.get(t, ""))
	match t:
		"captured":
			if factions.size() > 1:
				text += String(FogData.TEXT.captured_lost)
			if bool(numbers.get("is_capital", false)):
				var of := ""
				for f in state.factions:
					if f.capital == pid and (factions.is_empty() or f.id != String(factions[0])):
						of = f.id
				p["previous"] = _the_faction(state, of)
				text += String(FogData.TEXT.captured_capital)
			if int(numbers.get("fort_level", 0)) > 0:
				p["fort"] = SiegeRules.level_word(int(numbers.fort_level))
				p["walls_max"] = SiegeRules.walls_max(int(numbers.fort_level))
				text += String(FogData.TEXT.captured_fort)
		"oath_sworn":
			p["node_ref"] = AscensionRules.node_ref(String(numbers.get("node", "")))
			p["branch_ref"] = AscensionRules.branch_ref(String(numbers.get("branch", "")))
			p["closed_ref"] = AscensionRules.branch_ref(String(numbers.get("closed", "")))
		"transformed":
			p["branch_ref"] = AscensionRules.branch_ref(String(numbers.get("branch", "")))
			p["node_name"] = AscensionRules.node_name(String(numbers.get("node", "")))
			var renamed: Dictionary = numbers.get("renamed", {})
			for old in renamed:  # {type id: {"from", "to"}}
				var names: Dictionary = renamed[old] if renamed[old] is Dictionary else {}
				text += String(FogData.TEXT.transformed_renamed).format({"old_name": String(names.get("from", old)),
					"new_name": String(names.get("to", old))})
			var new_unit := String(numbers.get("new_unit", ""))
			if not new_unit.is_empty():
				p["new_unit_name"] = String(PathData.NEW_UNITS.get(new_unit, {}).get("name", new_unit))
				text += String(FogData.TEXT.transformed_new_unit)
			var opens := String(numbers.get("opens_mandate", ""))
			if not opens.is_empty():
				p["mandate_name"] = RulerRules.mandate_name(opens)
				text += String(FogData.TEXT.transformed_mandate)
		"fort_built":
			p["fort_phrase"] = SiegeRules.fort_phrase(int(numbers.get("level", 0)))
			p["walls_max"] = SiegeRules.walls_max(int(numbers.get("level", 0)))
		"ruler_died", "ruler_arrived":
			p["name"] = RulerRules._cap(String(numbers.get("name", "")))
		"ritual_cast", "ritual_fell", "curse_bit":
			p["ritual"] = MagicRules.spell_name(String(numbers.get("ritual", "")))  # M5-6: the spell's name, never its id
	return text.format(p)


## A unit type's name for players, from `fid`'s roster, commander or ruler (renamed by a transformation, if so).
static func type_name(state: GameState, fid: String, type_id: String) -> String:
	var f := state.find_faction(fid)
	if f != null:
		for ut in f.unit_types:
			if ut.id == type_id:
				return ut.name
		if f.commander_type != null and f.commander_type.id == type_id:
			return f.commander_type.name
		if f.ruler_unit_type != null and f.ruler_unit_type.id == type_id:
			return f.ruler_unit_type.name
	return TurnResolver._unit_type_name(state, type_id)


# --- the playback fold (§2.8) ---------------------------------------------------------------------

## The minimal army model of a view (§2.8): {army id: {"owner", "location", "level" (the view note's level, or
## "own"), "counts": {type id: n} (units, the commander and the ruler)}}, sorted by id.
static func view_model(view: GameState) -> Dictionary:
	var out := {}
	if view == null:
		return out
	var ids := []
	for a in view.armies:
		ids.append(a.id)
	ids.sort()
	for id in ids:
		var a := view.find_army(id)
		var n := {}
		for u in a.units:
			n[u.type.id] = int(n.get(u.type.id, 0)) + 1
		if a.commander != null:
			n[a.commander.type.id] = int(n.get(a.commander.type.id, 0)) + 1
		if a.ruler != null:
			n[a.ruler.type.id] = int(n.get(a.ruler.type.id, 0)) + 1
		out[id] = {"owner": a.owner, "location": a.location, "level": String(a.seen.get("level", "own")), "counts": _sorted_dict(n)}
	return out


## Folds a viewer's report into its army model (§2.8): its own moves move its armies, a battle removes the armies
## in its numbers.destroyed, a ruler's death removes the ruler's army, and the synthetic events set or remove what
## is left over. view_model(view_before) folded with the viewer's report equals view_model(view_after), exactly.
static func apply_view_events(model: Dictionary, events: Array) -> Dictionary:
	var m := model.duplicate(true)
	for e in events:
		var t := String(e.get("type", ""))
		if bool(e.get("synthetic", false)):
			var n: Dictionary = e.numbers
			var id := String(n.view_id)
			if t == "sighting_lost" or bool(n.get("gone", false)):
				m.erase(id)
			else:
				m[id] = {"owner": String(n.owner), "location": String(n.location), "level": String(n.level), "counts": n.counts.duplicate()}
			continue
		match t:
			"army_moved":
				if not e.get("armies", []).is_empty() and m.has(String(e.armies[0])):
					m[String(e.armies[0])].location = String(e.provinces.back())
			"battle", "border_battle":
				for id in e.get("numbers", {}).get("destroyed", []):
					m.erase(String(id))
			"ruler_died":
				if not e.get("armies", []).is_empty():
					m.erase(String(e.armies[0]))
			"army_split", "units_transferred", "armies_merged", "commanders_swapped", "army_disbanded":
				_fold_muster(m, e)  # ARM-1: the viewer's own musters move fighters between its own armies
	return _sorted_dict(m)


## Folds one of the viewer's own muster events into the army model (ARM-1): the fighters it names change armies, a new
## army appears where its source stands, and a disbanded one goes. The synthetic events then add only what is left over.
static func _fold_muster(m: Dictionary, e: Dictionary) -> void:
	var n: Dictionary = e.get("numbers", {})
	match String(e.get("type", "")):
		"army_disbanded":
			m.erase(String(n.get("army", "")))
		"commanders_swapped":
			var a: Dictionary = m.get(String(n.get("a", "")), {})
			var b: Dictionary = m.get(String(n.get("b", "")), {})
			if a.is_empty() or b.is_empty():
				return
			var ac := String(n.get("a_commander", ""))
			var bc := String(n.get("b_commander", ""))
			a["counts"] = _counts_with(a.counts, {ac: -1, bc: 1})
			b["counts"] = _counts_with(b.counts, {bc: -1, ac: 1})
		_:
			var from: Dictionary = m.get(String(n.get("from", "")), {})
			if from.is_empty():
				return
			var moved := {}
			for type_id in n.get("units", []):
				moved[String(type_id)] = int(moved.get(String(type_id), 0)) + 1
			var cmd := String(n.get("commander", ""))
			if not cmd.is_empty():
				moved[cmd] = int(moved.get(cmd, 0)) + 1
			var gone := {}
			for k in moved:
				gone[k] = -int(moved[k])
			from["counts"] = _counts_with(from.counts, gone)
			var to_id := String(n.get("to", ""))
			if m.has(to_id):
				m[to_id]["counts"] = _counts_with(m[to_id].counts, moved)
			else:
				m[to_id] = {"owner": from.owner, "location": from.location, "level": from.level, "counts": _counts_with({}, moved)}


## `counts` ({type id: n}) with `delta` ({type id: change}) added, no zero counts, keys sorted (the model's form).
static func _counts_with(counts: Dictionary, delta: Dictionary) -> Dictionary:
	var out := counts.duplicate()
	for k in delta:
		if String(k).is_empty():
			continue
		var n := int(out.get(k, 0)) + int(delta[k])
		if n > 0:
			out[k] = n
		else:
			out.erase(k)
	return _sorted_dict(out)


## The synthetic events (§2.8): exactly what is left over between view_before folded with `shown` and view_after,
## one per army id in id order: a rival's sighting that appeared or changed ("sighting_changed"), turned into a
## memory ("memory_added") or went ("sighting_lost"); the viewer's own army that changed ("army_changed", "gone"
## when it went). Hidden recruits, a band crossing and a province going out of sight all show up here.
static func synthetic_events(view_before: GameState, view_after: GameState, shown: Array, viewer: String) -> Array:
	var folded := apply_view_events(view_model(view_before), shown)
	var target := view_model(view_after)
	var ids := _merge_keys(folded, target).keys()
	ids.sort()
	var out := []
	for id in ids:
		var a = folded.get(id)
		var b = target.get(id)
		if a != null and b != null and var_to_str(a) == var_to_str(b):
			continue
		var entry: Dictionary = b if b != null else a
		var own := String(entry.owner) == viewer
		var t: String
		var gone := b == null
		if own:
			t = "army_changed"
		elif gone:
			t = "sighting_lost"
		elif String(entry.level) == FogData.MEMORY:
			t = "memory_added"
		else:
			t = "sighting_changed"
		var army := view_after.find_army(id) if not gone and view_after != null else null
		var note: Dictionary = army.seen if army != null else {}
		var numbers := {"view_id": id, "owner": String(entry.owner), "location": String(entry.location), "level": String(entry.level),
			"counts": entry.counts.duplicate(), "turn": int(note.get("turn", view_after.current_turn if view_after else 0))}
		if gone:
			numbers["gone"] = true
		var total := 0
		for k in entry.counts:
			total += int(entry.counts[k])
		var state: GameState = view_after if view_after != null else view_before
		var template := "army_gone" if own and gone else t
		var text := String(FogData.TEXT.get(template, "")).format({"faction": _the_faction(state, String(entry.owner)),
			"province": _province_name(state, String(entry.location)),
			"total": String(note.get("total", {}).get("text", str(total))) if not note.is_empty() else str(total),
			"level": String(FogData.LEVEL_NAMES.get(String(entry.level), entry.level)), "turn": int(numbers.turn)})
		out.append({"type": t, "phase": "view", "provinces": [String(entry.location)], "factions": [String(entry.owner)],
			"armies": [id], "cause": "view", "numbers": numbers, "text": text, "codex": String(FogData.SYNTHETIC_CODEX.get(t, "sight")),
			"synthetic": true})
	return out


# --- helpers ----------------------------------------------------------------------------------------

static func _province_ids(state: GameState) -> Array:
	var out := []
	for p in state.provinces:
		out.append(p.id)
	out.sort()
	return out


static func _sorted_provinces(state: GameState) -> Array:
	var out: Array = state.provinces.duplicate()
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


static func _sorted_factions(state: GameState) -> Array:
	var out: Array = state.factions.duplicate()
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


static func _sorted_armies(state: GameState) -> Array:
	var out: Array = state.armies.duplicate()
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


static func _sorted_keys(d: Dictionary) -> Array:
	var out := d.keys()
	out.sort()
	return out


static func _province_name(state: GameState, pid: String) -> String:
	return TurnResolver._province_name(state, pid)


## "the Thornmane Clans": a faction's name in running text.
static func _the_faction(state: GameState, fid: String) -> String:
	return "the " + TurnResolver._faction_name(state, fid)
