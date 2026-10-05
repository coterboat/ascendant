extends RefCounted
## The M2 build balance check (#36, design/M2_RULER.md §8.2): AIPlayer plays both seats and only the
## builds differ. autoplay.gd --matrix runs it, prints a pass/miss table for bands A-H and exits 0 only
## when band H (integrity) holds; the other bands are reported.
##
##   godot --headless --path . -s tools/autoplay/autoplay.gd -- --matrix --jobs 8
##
## What is played (cells: one build per seat, one seat order, a run of seeds):
##   B   every Crown preset against every Clans preset, PAIR_GAMES per pairing (half per seat order).
##   A2  the explicit same-ruler builds (A2_RULERS: the ruler keeping all 10, and the ruler with its
##       faction's spend preset's mandates) against every preset of the other faction, PAIR_GAMES per
##       build. A build that is already a preset is not played again: its band B games count.
## A pairing with fewer than MIN_DECISIVE decisive games (finished, not a draw) plays its games again on
## the next seeds, once (§8.2: "double its games"). With --scale the games and that threshold shrink.
##
## Band A, keep vs spend inside one faction, is judged from band B: the engine has exactly two factions,
## each with its own capital, roster, rulers and exclusive mandates, so a same-faction mirror would need
## a second copy of a faction. Instead both builds play the same opponents (the other faction's three
## presets, both seat orders), and their head-to-head is the Bradley-Terry estimate from their odds
## against that common field: P(keep beats spend) = odds_keep / (odds_keep + odds_spend), odds = (wins +
## 1/2) / (losses + 1/2). "A, direct" reports the real keep-vs-spend games of band B (each faction's keep
## preset against the other faction's spend preset, pooled, so the factions cancel). A2 is judged the same
## way. D, E and F are measured on band B's games, G on the direct keep-vs-spend games, H on every game.
##
## Every 10th game (REPLAY_EVERY) is replayed from its JSON record (GameSession.replay) and must reach an
## identical final state. Games are seeded exactly as in autoplay.gd, so any game can be replayed alone:
## `--games 1 --seed S --p1 ai --p2 ai --seat1 F --rulers --builds A,B`.

const Simulator := preload("res://tools/autoplay/simulator.gd")

const FACTIONS := ["kingdom", "beasts"]
const POLICY := "ai"
## Games per preset pairing (band B) and per explicit build (A2), before --scale.
const PAIR_GAMES := 100
## A pairing with fewer decisive games than this (scaled) is played again on the next seeds, once.
const MIN_DECISIVE := 60
const REPLAY_EVERY := 10
## Games in one work item of a parallel run.
const CHUNK := 10
## Band A2's rulers (§8.2): each plays keeping all 10 and spending all 10 (its faction's spend preset).
const A2_RULERS := {"ever_regent": "kingdom", "fang_chieftain": "beasts"}

## The targets of §8.2, so the table and the tests read the same numbers.
const A_BAND := [0.40, 0.60]
const A2_BAND := [0.35, 0.65]
const B_MAX := 0.65
const C_BAND := [0.40, 0.60]
const D_BAND := [0.25, 0.60]
const E_BAND := [10.0, 16.0]
const F_BAND := [0.15, 0.50]
const G_SHARE := 0.55
const G_EARLY := 8
const G_LATE := 12


## The faction's preset of `style` ("keep" | "spend" | "balanced"), or "".
static func preset_of(faction_id: String, style: String) -> String:
	for p in RulerRules.presets_for(faction_id):
		if str(p.style) == style:
			return str(p.id)
	return ""


static func other(faction_id: String) -> String:
	return FACTIONS[1] if faction_id == FACTIONS[0] else FACTIONS[0]


## A2's explicit builds: {build id: faction id}, each the ruler keeping 10 and the ruler with its spend
## preset's mandates. A build that is exactly one of the faction's presets maps to that preset's id.
static func a2_builds() -> Array:
	var out := []
	for rid in A2_RULERS:
		var fid: String = A2_RULERS[rid]
		var spend := RulerRules.preset_data(preset_of(fid, "spend"))
		var keep_id := _as_preset(fid, rid, [])
		var spend_id := _as_preset(fid, rid, spend.get("mandates", []))
		out.append({"ruler": rid, "faction": fid, "keep": keep_id, "spend": spend_id})
	return out


## The preset id whose build is exactly `ruler` + `mandates`, or the explicit build id "ruler+m+m".
static func _as_preset(faction_id: String, ruler: String, mandates: Array) -> String:
	var want := mandates.duplicate()
	want.sort()
	for p in RulerRules.presets_for(faction_id):
		var m: Array = p.mandates.duplicate()
		m.sort()
		if str(p.ruler) == ruler and m == want:
			return str(p.id)
	return "+".join([ruler] + mandates)


## The games to play: [{"id", "band", "pairing", "seats": [fid, fid], "builds": [id, id], "games",
## "seed"}]. Cell ids are stable, so a parallel worker finds its cell by id.
static func plan(scale: float = 1.0, base_seed: int = 1) -> Array:
	var cells := []
	var per_order := maxi(1, roundi(PAIR_GAMES * scale / 2.0))
	var crown: Array = RulerRules.presets_for("kingdom").map(func(p): return str(p.id))
	var clans: Array = RulerRules.presets_for("beasts").map(func(p): return str(p.id))
	for c in crown:
		for k in clans:
			var pairing := "%s|%s" % [c, k]
			cells.append({"id": "B:%s:%s" % [c, k], "band": "B", "pairing": pairing, "seats": ["kingdom", "beasts"],
				"builds": [c, k], "games": per_order, "seed": base_seed})
			cells.append({"id": "B:%s:%s" % [k, c], "band": "B", "pairing": pairing, "seats": ["beasts", "kingdom"],
				"builds": [k, c], "games": per_order, "seed": base_seed})
	var per_cell := maxi(1, ceili(PAIR_GAMES * scale / 6.0))
	for a2 in a2_builds():
		for bid in [a2.keep, a2.spend]:
			if not RulerRules.preset_data(str(bid)).is_empty():
				continue  # a preset: band B already plays it against every opponent preset
			var fid: String = a2.faction
			for opp in RulerRules.presets_for(other(fid)):
				# A2's games are doubled per build (all its opponents together), so its "pairing" is the build.
				cells.append({"id": "A2:%s:%s" % [bid, opp.id], "band": "A2", "pairing": str(bid), "seats": [fid, other(fid)],
					"builds": [bid, str(opp.id)], "games": per_cell, "seed": base_seed})
				cells.append({"id": "A2:%s:%s" % [opp.id, bid], "band": "A2", "pairing": str(bid), "seats": [other(fid), fid],
					"builds": [str(opp.id), bid], "games": per_cell, "seed": base_seed})
	return cells


static func find_cell(cells: Array, cell_id: String) -> Dictionary:
	for c in cells:
		if str(c.id) == cell_id:
			return c
	return {}


## Work items for `cells`: [{"cell", "from" (first seed), "count"}], at most CHUNK games each.
## `offset` shifts every cell's seeds (the second run of a pairing that had too few decisive games).
static func work_items(cells: Array, offset_by_cell: Dictionary = {}) -> Array:
	var items := []
	for c in cells:
		var start: int = int(c.seed) + int(offset_by_cell.get(c.id, 0))
		var left: int = int(c.games)
		while left > 0:
			var n := mini(CHUNK, left)
			items.append({"cell": str(c.id), "from": start, "count": n})
			start += n
			left -= n
	return items


## Plays one work item and returns its results (play_game results without "final_state", each with
## "cell" and "band" added). `probe` files logged errors under each game, as in autoplay.gd. `independents` plays
## every game with Free Holds garrisons in the neutral provinces (IND-1, #142; autoplay.gd --matrix --independents).
static func play_item(cells: Array, item: Dictionary, turn_cap: int, probe: Callable = Callable(), independents := false) -> Array:
	var cell := find_cell(cells, str(item.cell))
	var out := []
	if cell.is_empty():
		return out
	for i in int(item.count):
		var game_seed: int = int(item.from) + i
		# Every REPLAY_EVERY-th game of a cell, its first included, is replayed from its record (band H).
		var options := {"rulers": true, "builds": cell.builds.duplicate(), "replay_check": (game_seed - int(cell.seed)) % REPLAY_EVERY == 0,
			"independents": independents}
		var r := Simulator.play_game(game_seed, cell.seats, [POLICY, POLICY], turn_cap, probe, options)
		r.erase("final_state")
		r["cell"] = str(cell.id)
		r["band"] = str(cell.band)
		r["pairing"] = str(cell.pairing)
		out.append(r)
	return out


static func decisive(r: Dictionary) -> bool:
	return bool(r.finished) and not bool(r.draw) and not str(r.winner).is_empty()


## Which pairings need their games doubled: {pairing: true} for those with fewer than the scaled
## MIN_DECISIVE decisive games.
static func short_pairings(results: Array, scale: float) -> Dictionary:
	var dec := {}
	var seen := {}
	for r in results:
		seen[r.pairing] = true
		if decisive(r):
			dec[r.pairing] = int(dec.get(r.pairing, 0)) + 1
	var need := ceili(MIN_DECISIVE * scale)
	var out := {}
	for p in seen:
		if int(dec.get(p, 0)) < need:
			out[p] = true
	return out


# --- judging the bands -------------------------------------------------------------------------------

## {wins, losses, decisive, games} of builds `ids` (the build ids a faction played) in `results`.
static func _record(results: Array, build_id: String, opponents: Array = []) -> Dictionary:
	var rec := {"wins": 0, "losses": 0, "decisive": 0, "games": 0}
	for r in results:
		var fid := _faction_with(r, build_id)
		if fid.is_empty():
			continue
		if not opponents.is_empty() and not opponents.has(str(r.builds.get(other(fid), ""))):
			continue
		rec.games += 1
		if decisive(r):
			rec.decisive += 1
			if str(r.winner) == fid:
				rec.wins += 1
			else:
				rec.losses += 1
	return rec


static func _faction_with(r: Dictionary, build_id: String) -> String:
	for fid in r.get("builds", {}):
		if str(r.builds[fid]) == build_id:
			return str(fid)
	return ""


## The Bradley-Terry head-to-head of two builds from their records against the same opponents.
static func head_to_head(a: Dictionary, b: Dictionary) -> float:
	var oa: float = (float(a.wins) + 0.5) / (float(a.losses) + 0.5)
	var ob: float = (float(b.wins) + 0.5) / (float(b.losses) + 0.5)
	return oa / (oa + ob)


static func _in(v: float, band: Array) -> bool:
	return v >= float(band[0]) - 0.000001 and v <= float(band[1]) + 0.000001


static func _pct(v: float) -> String:
	return "%d%%" % roundi(100.0 * v)


static func _ratio(n: int, d: int) -> float:
	return 0.0 if d == 0 else float(n) / float(d)


## Judges every band. `results` are all games played; `stray_errors` script errors logged outside
## games. Returns {"bands": [{"band", "what", "target", "result", "status" ("pass" | "miss" | "report"),
## "detail"}], "h_ok": bool, "pairings": [...], "b_results", "a2_results"}.
static func judge(results: Array, stray_errors: int = 0) -> Dictionary:
	var b_res := results.filter(func(r): return r.band == "B")
	var a2_res := results.filter(func(r): return r.band == "A2")
	var bands := []

	# A: keep vs spend per faction, against the common field of the other faction's presets.
	var a_ok := true
	var a_parts := []
	var a_detail := []
	for fid in FACTIONS:
		var keep := preset_of(fid, "keep")
		var spend := preset_of(fid, "spend")
		var rk := _record(b_res, keep)
		var rs := _record(b_res, spend)
		var p := head_to_head(rk, rs)
		var ok := _in(p, A_BAND) and _in(1.0 - p, A_BAND)
		a_ok = a_ok and ok
		a_parts.append("%s %s / %s %s" % [Simulator.build_name(keep), _pct(p), Simulator.build_name(spend), _pct(1.0 - p)])
		a_detail.append("%s: %s won %d of %d decisive games against the %s presets, %s %d of %d" % [Simulator.faction_name(fid),
			Simulator.build_name(keep), rk.wins, rk.decisive, Simulator.faction_name(other(fid)), Simulator.build_name(spend), rs.wins, rs.decisive])
	bands.append({"band": "A", "what": "both viable: keep vs spend per faction (head-to-head estimated from common opponents)",
		"target": "each 40-60%", "result": "; ".join(a_parts), "status": "pass" if a_ok else "miss", "detail": "; ".join(a_detail) + "."})

	# A, direct: the real keep-vs-spend games (each faction's keep preset against the other's spend preset).
	var direct := _direct_games(b_res)
	var keep_wins := 0
	var n_direct := 0
	for r in direct:
		if decisive(r):
			n_direct += 1
			if _is_keep_winner(r):
				keep_wins += 1
	var kd := _ratio(keep_wins, n_direct)
	bands.append({"band": "A, direct", "what": "keep vs spend, cross-faction pooled (%s vs %s, %s vs %s)" % [
		Simulator.build_name(preset_of("kingdom", "keep")), Simulator.build_name(preset_of("beasts", "spend")),
		Simulator.build_name(preset_of("beasts", "keep")), Simulator.build_name(preset_of("kingdom", "spend"))],
		"target": "report (40-60%)", "result": "keep %s / spend %s of %d decisive" % [_pct(kd), _pct(1.0 - kd), n_direct],
		"status": "report", "detail": ""})

	# A2: the same ruler keeping 10 vs spending 10, against common opponents (report only).
	var a2_parts := []
	var a2_flag := false
	for a2 in a2_builds():
		var pool := b_res + a2_res
		var opp: Array = RulerRules.presets_for(other(a2.faction)).map(func(p): return str(p.id))
		var rk := _record(pool, str(a2.keep), opp)
		var rs := _record(pool, str(a2.spend), opp)
		var p := head_to_head(rk, rs)
		if not _in(p, A2_BAND):
			a2_flag = true
		a2_parts.append("%s keep 10 %s / spend 10 %s (%d and %d decisive)" % [RulerRules.ruler_name(str(a2.ruler)), _pct(p), _pct(1.0 - p), rk.decisive, rs.decisive])
	bands.append({"band": "A2", "what": "same ruler: keep 10 vs spend 10 (explicit builds, common opponents)",
		"target": "report (outside 35-65% goes to the director)", "result": "; ".join(a2_parts),
		"status": "report", "detail": "outside 35-65%: goes to the director" if a2_flag else ""})

	# B: no preset above 65% against any other.
	var pairings := _pairings(b_res)
	var worst := {"share": 0.0, "text": ""}
	var b_ok := true
	for pr in pairings:
		for side in [["a", "a_wins"], ["b", "b_wins"]]:
			var share := _ratio(int(pr[side[1]]), int(pr.decisive))
			if share > worst.share:
				worst = {"share": share, "text": "%s %s against %s" % [Simulator.build_name(str(pr[side[0]])), _pct(share),
					Simulator.build_name(str(pr["b" if side[0] == "a" else "a"]))]}
			if share > B_MAX + 0.000001:
				b_ok = false
	var b_over := pairings.filter(func(pr): return _ratio(maxi(pr.a_wins, pr.b_wins), pr.decisive) > B_MAX + 0.000001).size()
	bands.append({"band": "B", "what": "no dominant preset (9 Crown x Clans pairings)", "target": "none above 65%",
		"result": "worst: %s; %d of %d pairings over" % [worst.text, b_over, pairings.size()], "status": "pass" if b_ok else "miss", "detail": ""})

	# C: factions (report only).
	var crown_w := 0
	var dec_b := 0
	for r in b_res:
		if decisive(r):
			dec_b += 1
			if str(r.winner) == "kingdom":
				crown_w += 1
	var cw := _ratio(crown_w, dec_b)
	bands.append({"band": "C", "what": "factions, band B pooled", "target": "report (each 40-60%)",
		"result": "Aurel Crown %s / Thornmane Clans %s of %d decisive" % [_pct(cw), _pct(1.0 - cw), dec_b],
		"status": "report", "detail": "outside 40-60%: goes to Alex (#25 item 4)" if not _in(cw, C_BAND) else ""})

	# D: rulers matter. A ruler lost in the turn its capital falls dies with the game, so it doesn't show
	# that rulers matter: the band counts deaths before the final turn (all deaths are reported too).
	var to8 := 0
	var died8 := 0
	var died8_all := 0
	for r in b_res:
		if int(r.turns) >= 8:
			to8 += 1
			if not r.ruler_log.deaths.is_empty():
				died8_all += 1
			if r.ruler_log.deaths.any(func(d): return midgame_death(r, d)):
				died8 += 1
	var due := 0
	var arrived := 0
	for r in results:
		due += int(r.get("successors_due", 0))
		arrived += r.ruler_log.arrivals.size()
	var dr := _ratio(died8, to8)
	var d_ok := _in(dr, D_BAND) and arrived >= due
	bands.append({"band": "D", "what": "rulers matter", "target": "a ruler dies (before the game's last turn) in 25-60% of games reaching turn 8; every successor due arrives",
		"result": "%s (%d of %d; %s counting rulers lost with their capital); successors %d of %d due crowned" % [_pct(dr), died8, to8,
			_pct(_ratio(died8_all, to8)), arrived, due],
		"status": "pass" if d_ok else "miss", "detail": ""})

	# E: length.
	var lengths := []
	for r in b_res:
		if decisive(r):
			lengths.append(int(r.turns))
	var ls := Simulator.stats_of(lengths)
	var unfinished := b_res.filter(func(r): return not bool(r.finished)).size()
	bands.append({"band": "E", "what": "length", "target": "median decisive game 10-16 turns",
		"result": "median %s (%d-%d); %d of %d games hit the turn cap" % [Simulator._num(ls.median), ls.min, ls.max, unfinished, b_res.size()],
		"status": "pass" if _in(float(ls.median), E_BAND) else "miss", "detail": ""})

	# F: sacrifice is reachable.
	var with_sac := b_res.filter(func(r): return not r.ruler_log.sacrifices.is_empty()).size()
	var fr := _ratio(with_sac, b_res.size())
	bands.append({"band": "F", "what": "sacrifice is reachable", "target": "the AI sacrifices in 15-50% of games",
		"result": "%s (%d of %d)" % [_pct(fr), with_sac, b_res.size()], "status": "pass" if _in(fr, F_BAND) else "miss", "detail": ""})

	# G: shape (report only), on the direct keep-vs-spend games.
	var early := [0, 0]
	var late := [0, 0]
	for r in direct:
		if not decisive(r):
			continue
		if int(r.turns) <= G_EARLY:
			early[1] += 1
			if _is_keep_winner(r):
				early[0] += 1
		elif int(r.turns) > G_LATE:
			late[1] += 1
			if not _is_keep_winner(r):
				late[0] += 1
	var ge := _ratio(early[0], early[1])
	var gl := _ratio(late[0], late[1])
	bands.append({"band": "G", "what": "shape (keep early, spend late)", "target": "report (keep >= 55% by turn 8; spend >= 55% after turn 12)",
		"result": "keep %s of %d decided by turn 8; spend %s of %d decided after turn 12" % [_pct(ge), early[1], _pct(gl), late[1]],
		"status": "report", "detail": ""})

	# H: integrity, every game.
	var viol := 0
	var errs := 0
	var scr := stray_errors
	var replays := 0
	var replay_bad := []
	var first := ""
	for r in results:
		viol += r.violations.size()
		errs += r.errors.size()
		scr += r.script_errors.size()
		if first.is_empty():
			for key in ["violations", "errors", "script_errors"]:
				if not r[key].is_empty() and first.is_empty():
					first = "seed %d (%s): %s" % [r.seed, r.cell, r[key][0].get("detail", r[key][0].get("check", ""))]
		if not str(r.replay).is_empty():
			replays += 1
			if str(r.replay) != "identical":
				replay_bad.append("seed %d (%s): %s" % [r.seed, r.cell, r.replay])
	var h_ok := viol == 0 and errs == 0 and scr == 0 and replay_bad.is_empty() and replays > 0
	var h_detail := first
	if not replay_bad.is_empty():
		h_detail = ("%s; " % first if not first.is_empty() else "") + replay_bad[0]
	bands.append({"band": "H", "what": "integrity, every game", "target": "0 violations, 0 session errors, 0 script errors; every 10th game replays identically",
		"result": "%d violations, %d session errors, %d script errors; %d of %d replays identical (%d games)" % [viol, errs, scr,
			replays - replay_bad.size(), replays, results.size()], "status": "pass" if h_ok else "miss", "detail": h_detail})
	return {"bands": bands, "h_ok": h_ok, "pairings": pairings, "b_results": b_res, "a2_results": a2_res}


## Whether ruler death `d` ({"faction", "turn"}) of game `r` happened before its last turn: a ruler lost in
## the turn its game ended (its capital fell) doesn't count. In a game stopped by the turn cap, every
## death is mid-game.
static func midgame_death(r: Dictionary, d: Dictionary) -> bool:
	return int(d.turn) < int(r.turns) or not bool(r.finished)


## Band B games between a keep preset and the other faction's spend preset.
static func _direct_games(b_res: Array) -> Array:
	var keep := {preset_of("kingdom", "keep"): true, preset_of("beasts", "keep"): true}
	var spend := {preset_of("kingdom", "spend"): true, preset_of("beasts", "spend"): true}
	return b_res.filter(func(r):
		var ids: Array = r.builds.values().map(func(v): return str(v))
		return ids.size() == 2 and ((keep.has(ids[0]) and spend.has(ids[1])) or (keep.has(ids[1]) and spend.has(ids[0]))))


static func _is_keep_winner(r: Dictionary) -> bool:
	var id := str(r.builds.get(str(r.winner), ""))
	return id == preset_of("kingdom", "keep") or id == preset_of("beasts", "keep")


## Band B per pairing: [{"a" (Crown preset), "b" (Clans preset), "games", "decisive", "a_wins",
## "b_wins", "draws", "unfinished", "median", "endings", "top_ending", "top_label"}], in plan order.
## #131: "endings" counts the distinct ways its games ended (winner and turn: _ending), "top_ending" the games
## that share the most common one and "top_label" names it. Both seats run the same AIPlayer, so the seeds
## differ only in the dice; a pairing whose games mostly end alike swings its band B share to 0% or 100%.
static func _pairings(b_res: Array) -> Array:
	var by := {}
	var order := []
	for r in b_res:
		var key := str(r.pairing)
		if not by.has(key):
			var ids := key.split("|")
			by[key] = {"a": ids[0], "b": ids[1], "games": 0, "decisive": 0, "a_wins": 0, "b_wins": 0, "draws": 0, "unfinished": 0, "lengths": [],
				"ending_counts": {}}
			order.append(key)
		var pr: Dictionary = by[key]
		pr.games += 1
		var ending := _ending(r)
		pr.ending_counts[ending] = int(pr.ending_counts.get(ending, 0)) + 1
		if not bool(r.finished):
			pr.unfinished += 1
		elif bool(r.draw):
			pr.draws += 1
		elif decisive(r):
			pr.decisive += 1
			pr.lengths.append(int(r.turns))
			if str(r.builds.get(str(r.winner), "")) == pr.a:
				pr.a_wins += 1
			else:
				pr.b_wins += 1
	var out := []
	for key in order:
		var pr: Dictionary = by[key]
		pr["median"] = Simulator.stats_of(pr.lengths).median
		var counts: Dictionary = pr.ending_counts
		var keys: Array = counts.keys()
		keys.sort()  # ties go to the first label, so the report is the same on every run
		var top := ""
		for k in keys:
			if top.is_empty() or int(counts[k]) > int(counts[top]):
				top = k
		pr["endings"] = keys.size()
		pr["top_ending"] = int(counts.get(top, 0))
		pr["top_label"] = top
		pr.erase("ending_counts")
		out.append(pr)
	return out


## How game `r` ended, for _pairings' distinct endings: "<winner>, turn N", "draw, turn N" or "unfinished, turn N".
static func _ending(r: Dictionary) -> String:
	var how := "unfinished"
	if decisive(r):
		how = Simulator.faction_name(str(r.winner))
	elif bool(r.finished):
		how = "draw"
	return "%s, turn %d" % [how, int(r.turns)]


## The whole matrix report as markdown: the bands table, band B's pairings, then the autoplay report
## sections (wins by build, deaths and successions, sacrifices, mandate picks, length) for band B and A2.
static func to_markdown(j: Dictionary, header: String = "") -> String:
	var L := []
	L.append("## Build balance check (design/M2_RULER.md §8.2)%s" % ("" if header.is_empty() else ": " + header))
	L.append("")
	L.append("| band | what | target | result | status |")
	L.append("|---|---|---|---|---|")
	for b in j.bands:
		var status: String = {"pass": "**pass**", "miss": "**miss**", "report": "report"}[b.status]
		L.append("| %s | %s | %s | %s | %s |" % [b.band, b.what, b.target, b.result, status])
	var notes: Array = j.bands.filter(func(b): return not str(b.detail).is_empty())
	if not notes.is_empty():
		L.append("")
		for b in notes:
			L.append("- **%s:** %s" % [b.band, b.detail])
	L.append("")
	L.append("### Band B pairings (wins of decisive games)")
	L.append("")
	L.append("| Aurel Crown preset | Thornmane Clans preset | games | decisive | Crown wins | Clans wins | draws | at the cap | median length | distinct endings |")
	L.append("|---|---|---|---|---|---|---|---|---|---|")
	for pr in j.pairings:
		L.append("| %s | %s | %d | %d | %d (%s) | %d (%s) | %d | %d | %s | %d (%d of %d: %s) |" % [Simulator.build_name(pr.a), Simulator.build_name(pr.b), pr.games, pr.decisive,
			pr.a_wins, _pct(_ratio(pr.a_wins, pr.decisive)), pr.b_wins, _pct(_ratio(pr.b_wins, pr.decisive)), pr.draws, pr.unfinished, Simulator._num(pr.median),
			pr.endings, pr.top_ending, pr.games, pr.top_label])
	for part in [["Band B games", j.b_results], ["Band A2 games (explicit builds)", j.a2_results]]:
		if part[1].is_empty():
			continue
		var s := Simulator.summarize(part[1])
		L.append("")
		L.append("### %s: %d" % [part[0], part[1].size()])
		L.append("")
		for line in Simulator.to_markdown(s).split("\n"):
			if line.begins_with("- **Results") or line.begins_with("- **Game length") or line.begins_with("- **Length buckets") \
					or line.begins_with("- **Builds") or line.begins_with("- **Rulers") or line.begins_with("- **Deaths") \
					or line.begins_with("- **Mandate picks") or line.begins_with("- **Battles") or line.begins_with("- **How battles"):
				L.append(line)
	return "\n".join(L)
