extends RefCounted
## The M5 balance check for magic and fog (M5-11, #122; design/M5_MAGIC_FOG.md §13.2). AIPlayer plays both seats with paths and
## magic on, and each seat's side of the fork is forced, as in the M4 path matrix (path_matrix.gd). autoplay.gd
## --matrix --magic runs it, prints a pass/miss table for bands G1-G14 and exits 0 only when G12 (earlier games unbroken)
## and G13 (integrity) hold; every other band is reported.
##
##   godot --headless --path . -s tools/autoplay/autoplay.gd -- --matrix --magic --independents --jobs 4
##
## The balance contract plays with independents on (Alex, 10-5): pass --independents. The plain run is report-only.
##
## What is played (cells: one build and one side of the fork per seat, one seat order, a run of seeds):
##   G   every Crown side x every Clans side (4) x every Crown preset x every Clans preset (9) x both seat orders, CELL_GAMES
##       each: 1,800 games, magic on, fog off. A branch pairing with fewer than MIN_DECISIVE decisive games plays its games
##       again on the next seeds, once.
##   GF  the same cells, FOG_GAMES each: 720 games, fog on. The computer is handed its view and nothing else (§10.1).
##       Its no-fog control is the first FOG_GAMES games of the same G cells (same seeds and builds, so the only difference
##       is what each seat sees): no game is played twice.
##   GT  the Tithe pairs (band G9): every Clans preset x every Crown preset x both seat orders x TITHE_GAMES seeds, twice:
##       once with Tithe of Blood for the Clans, once with a test-only mandate of the same price that does nothing
##       (MandateData.TEST_MANDATES), so kept power is the same: 720 games. Sides of the fork are rolled by seed.
##   GB  the scripted Tithe build that bleeds to the floor (policy "ai_bleed"), BLEED_GAMES seeds per cell, same cells as GT.
##   P   the control: the path matrix of M4 (#71, path_matrix.gd), magic off, on the same seeds: 1,800 games.
##   P7  the M2 matrix's games (magic, fog, paths off) with their record digests, for band G12.
##
## The bands are in judge(); their targets are the constants below, so the table and the tests read the same numbers.

const Simulator := preload("res://tools/autoplay/simulator.gd")
const Matrix := preload("res://tools/autoplay/matrix.gd")
const PathMatrix := preload("res://tools/autoplay/path_matrix.gd")
const MagicLog := preload("res://tools/autoplay/magic_log.gd")
const FogProbe := preload("res://tools/autoplay/fog_probe.gd")
const Fixture := preload("res://tools/replay_fixture.gd")

const FACTIONS := ["kingdom", "beasts"]
const POLICY := "ai"
const BLEED_POLICY := "ai_bleed"
const CELL_GAMES := 25
const FOG_GAMES := 10
const TITHE_GAMES := 20
const BLEED_GAMES := 10
const MIN_DECISIVE := 120
const REPLAY_EVERY := 10

## The targets of §13.2.
const G1_RESEARCH := 0.40
const G1_USED := 0.25
const G1_AT_TURN := 10
const G2_SPELL_MAX := 0.25
const G2_RITUAL_MAX := 0.50
const G3_BAND := [0.30, 0.60]
const G5_BAND := [12.0, 25.0]
const G5_CAP_MAX := 0.15
const G6_BAND := [8.0, 12.0]
const G6_BY_TURN := 15
const G6_SHARE := 0.80
const G7_BY_TURN := 14  # Alex 10-9 (§20 question 10): a target turn, relaxed from 10 (the transformation lands on turn 10)
const G7_SHARE := 0.80
const G7_EACH := 0.10
const G8_BAND := [0.04, 0.20]
const G9_DELTA := 0.05
const F_SLACK := 0.05
const G10_MAX := 0.60
const G11_LENGTH := 3.0
const G11_SIGHT := 0.30
const G11_SIGHT_TURN := 8
const G11_FACTIONS := [0.40, 0.60]
const G14_BAND := [1.0, 4.0]

const BANDS := ["G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8", "G9", "G10", "G11", "G12", "G13", "G14"]


# --- the plan --------------------------------------------------------------------------------------------

static func other(faction_id: String) -> String:
	return PathMatrix.other(faction_id)


## The games to play: [{"id", "band" ("G" | "GF" | "GT" | "GB" | "P" | "P7"), "pairing", "seats", "builds", "branches",
## "policies", "paths", "magic", "fog", "tithe", "games", "seed", "turn_cap" (P7 only)}]. Cell ids are stable, so a parallel
## worker finds its cell by id. `fixture` is the P7 fixture (PathMatrix.load_fixture), whose seed and turn cap P7 uses.
static func plan(scale: float = 1.0, base_seed: int = 1, fixture: Dictionary = {}) -> Array:
	var cells := []
	var n := maxi(1, roundi(CELL_GAMES * scale))
	var nf := maxi(1, roundi(FOG_GAMES * scale))
	var nt := maxi(1, roundi(TITHE_GAMES * scale))
	var nb := maxi(1, roundi(BLEED_GAMES * scale))
	var crown: Array = RulerRules.presets_for("kingdom").map(func(p): return str(p.id))
	var clans: Array = RulerRules.presets_for("beasts").map(func(p): return str(p.id))
	for cs in PathMatrix.sides_of("kingdom"):
		for ks in PathMatrix.sides_of("beasts"):
			var pairing := "%s|%s" % [cs, ks]
			for c in crown:
				for k in clans:
					for crown_first in [true, false]:
						var seats := ["kingdom", "beasts"] if crown_first else ["beasts", "kingdom"]
						var builds := [c, k] if crown_first else [k, c]
						var branches := [cs, ks] if crown_first else [ks, cs]
						var tail := "%s+%s:%s+%s" % [branches[0], builds[0], branches[1], builds[1]]
						cells.append(_cell("G:" + tail, "G", pairing, seats, builds, branches, n, base_seed, false, ""))
						cells.append(_cell("GF:" + tail, "GF", pairing, seats, builds, branches, nf, base_seed, true, ""))
	for c in crown:
		for k in clans:
			for crown_first in [true, false]:
				var seats := ["kingdom", "beasts"] if crown_first else ["beasts", "kingdom"]
				var builds := [c, k] if crown_first else [k, c]
				var tail := "%s+%s" % [builds[0], builds[1]]
				for mode in ["tithe", "null"]:
					cells.append(_cell("GT:%s:%s" % [mode, tail], "GT", "tithe", seats, builds, ["", ""], nt, base_seed, false, mode))
				cells.append(_cell("GB:bleed:" + tail, "GB", "tithe", seats, builds, ["", ""], nb, base_seed, false, "bleed"))
	for c in PathMatrix.plan(scale, base_seed, true, fixture):  # the magic-off control (P) and the M2 games (P7)
		cells.append(c)
	return cells


static func _cell(id: String, band: String, pairing: String, seats: Array, builds: Array, branches: Array, games: int, base_seed: int,
		fog: bool, tithe: String) -> Dictionary:
	var policies := []
	for s in seats:
		policies.append(BLEED_POLICY if tithe == "bleed" and s == "beasts" else POLICY)
	return {"id": id, "band": band, "pairing": pairing, "seats": seats, "builds": builds, "branches": branches, "policies": policies,
		"paths": true, "magic": true, "fog": fog, "tithe": tithe, "games": games, "seed": base_seed}


static func find_cell(cells: Array, cell_id: String) -> Dictionary:
	return PathMatrix.find_cell(cells, cell_id)


## Plays one work item ({"cell", "from", "count"}) and returns its results (play_game results without "final_state", each with
## "cell", "band", "pairing", "branches" (the forced sides, in seat order) and "tithe" added). `independents` plays the magic
## cells and the P control with Free Holds garrisons in the neutral provinces (autoplay.gd --matrix --magic --independents);
## band P7's games never have them, since they are compared with M2 records made without.
static func play_item(cells: Array, item: Dictionary, turn_cap: int, probe: Callable = Callable(), independents := false) -> Array:
	var cell := find_cell(cells, str(item.cell))
	var out := []
	if cell.is_empty():
		return out
	if not bool(cell.get("magic", false)):  # P and P7 are the M4 matrix's own cells
		return PathMatrix.play_item(cells, item, turn_cap, probe, independents)
	for i in int(item.count):
		var game_seed: int = int(item.from) + i
		var options := {"rulers": true, "builds": cell.builds.duplicate(), "paths": true, "magic": true, "fog": bool(cell.fog),
			"branches": cell.branches.duplicate(), "tithe": str(cell.tithe), "independents": independents,
			"replay_check": (game_seed - int(cell.seed)) % REPLAY_EVERY == 0}
		var r := Simulator.play_game(game_seed, cell.seats, cell.policies, turn_cap, probe, options)
		r.erase("final_state")
		r["cell"] = str(cell.id)
		r["band"] = str(cell.band)
		r["pairing"] = str(cell.pairing)
		r["branches"] = cell.branches.duplicate()
		r["tithe"] = str(cell.tithe)
		out.append(r)
	return out


## Which branch pairings of the main matrix need their games doubled: {pairing: true} for those with fewer than the scaled
## MIN_DECISIVE decisive games. Only band G doubles.
static func short_pairings(results: Array, scale: float) -> Dictionary:
	var dec := {}
	var seen := {}
	for r in results:
		if str(r.band) != "G":
			continue
		seen[r.pairing] = true
		if Matrix.decisive(r):
			dec[r.pairing] = int(dec.get(r.pairing, 0)) + 1
	var need := ceili(MIN_DECISIVE * scale)
	var out := {}
	for p in seen:
		if int(dec.get(p, 0)) < need:
			out[p] = true
	return out


# --- helpers ---------------------------------------------------------------------------------------------

static func _in(v: float, band: Array) -> bool:
	return v >= float(band[0]) - 0.000001 and v <= float(band[1]) + 0.000001


static func _pct(v: float) -> String:
	return "%d%%" % roundi(100.0 * v)


static func _ratio(n, d) -> float:
	return 0.0 if int(d) == 0 else float(n) / float(d)


static func _pct_of(n, d) -> String:
	return "%s (%d of %d)" % [_pct(_ratio(n, d)), int(n), int(d)]


static func _of(results: Array, band: String) -> Array:
	return results.filter(func(r): return str(r.band) == band)


static func _mlog(r: Dictionary) -> Dictionary:
	return r.get("magic", {})


static func _decisive(results: Array) -> Array:
	return results.filter(func(r): return Matrix.decisive(r))


static func _median_length(results: Array) -> Dictionary:
	return Simulator.stats_of(_decisive(results).map(func(r): return int(r.turns)))


static func _capped(results: Array) -> int:
	return results.filter(func(r): return not bool(r.finished)).size()


## The schools of a faction, in MagicData order.
static func schools_of(faction_id: String) -> Array:
	return MagicData.FACTION_SCHOOLS.get(faction_id, [])


## The battle spell and ritual ids of a school.
static func spells_of_school(school: String) -> Array:
	var out := []
	for sid in MagicData.SPELLS:
		if str(MagicData.SPELLS[sid].school) == school:
			out.append(str(sid))
	return out


## The rituals (not the battle spells), in data order.
static func rituals() -> Array:
	var out := []
	for sid in MagicData.SPELLS:
		if not bool(MagicData.SPELLS[sid].battle):
			out.append(str(sid))
	return out


static func ritual_name(sid: String) -> String:
	return str(MagicData.SPELLS.get(sid, {}).get("name", sid))


static func spell_label(sid: String) -> String:
	return ritual_name(sid)


## Whether `fid` had a caster in game `r`: it bought a mage, or its ruler casts (a ruler with schools).
static func had_caster(r: Dictionary, fid: String) -> bool:
	var mage_id := str(MagicData.MAGES[fid].id)
	if int(r.get("recruits", {}).get(fid, {}).get(mage_id, 0)) > 0:
		return true
	var preset := RulerRules.preset_data(str(r.get("builds", {}).get(fid, "")))
	return not preset.is_empty() and not MagicData.RULER_MAGIC.get(str(preset.ruler), {}).get("schools", []).is_empty()


## A cast row's cost in gold, counting blood at BLOOD_PER_GOLD.
static func _paid(c: Dictionary) -> float:
	return float(c.gold) + float(c.hp) / float(MagicData.BLOOD_PER_GOLD)


## Whether `r`'s game reached `turn`.
static func _reached(r: Dictionary, turn: int) -> bool:
	return int(r.turns) >= turn


# --- judging the bands -------------------------------------------------------------------------------------

## Judges every band. `results` are all games played (G, GF, GT, GB, P and P7); `stray_errors` script errors logged outside games;
## `fixture` the P7 fixture; `records` records_check()'s result ({} to leave the records part out, which then misses).
## Returns {"bands": [{"band", "what", "target", "result", "status" ("pass" | "miss" | "report" | "none"), "detail"}],
## "ok" (G12 and G13 hold), "g12", "g13", "tables": {...}}. A band whose games were not played is "none".
static func judge(results: Array, stray_errors: int = 0, fixture: Dictionary = {}, records: Dictionary = {}) -> Dictionary:
	var g := _of(results, "G")
	var gf := _of(results, "GF")
	var gt := _of(results, "GT")
	var gb := _of(results, "GB")
	var pc := _of(results, "P")
	var m2 := _of(results, "P7")
	var tables := {}
	var bands := []
	bands.append(_g1(g, tables))
	bands.append(_g2(g, gf, tables))
	bands.append(_g3(g, tables))
	bands.append(_g4(g, pc, tables))
	bands.append(_g5(g, pc))
	bands.append(_g6(g, pc))
	bands.append(_g7(g, gf, tables))
	bands.append(_g8(g, tables))
	bands.append(_g9(gt, gb, tables))
	bands.append(_g10(g, tables))
	bands.append(_g11(g, gf, tables))
	var b12 := _g12(g, pc, m2, fixture, records)
	bands.append(b12)
	var b13 := _g13(results, stray_errors)
	bands.append(b13)
	bands.append(_g14(g, tables))
	tables["pairings"] = PathMatrix._pairings(g)
	tables["presets"] = PathMatrix._presets(g)
	tables["control_pairings"] = PathMatrix._pairings(pc)
	return {"bands": bands, "ok": b12.status == "pass" and b13.status == "pass", "g12": b12.status == "pass", "g13": b13.status == "pass",
		"tables": tables, "g_results": g}


static func _band(id: String, what: String, target: String, result: String, status: String, detail: String = "") -> Dictionary:
	return {"band": id, "what": what, "target": target, "result": result, "status": status, "detail": detail}


static func _none(id: String, what: String, target: String, why: String) -> Dictionary:
	return _band(id, what, target, "not played: " + why, "none")


## G1: both schools used. Per faction and school: researched to tier I in 40%+ of the games that reached turn 10, and its spells
## or rituals used (a battle spell cast, or a ritual ordered) in 25%+ of them.
static func _g1(g: Array, tables: Dictionary) -> Dictionary:
	var what := "both schools used"
	var target := "each school researched to tier I in 40%+ of games reaching turn 10, and used in 25%+"
	if g.is_empty():
		return _none("G1", what, target, "no main games")
	var games := g.filter(func(r): return _reached(r, G1_AT_TURN))
	var rows := []
	var ok := true
	var parts := []
	for fid in FACTIONS:
		for school in schools_of(fid):
			var tier_one := str(MagicData.SCHOOLS[school].nodes[0])
			var ids := spells_of_school(school)
			var researched := 0
			var by_ten := 0
			var used := 0
			for r in games:
				var done: Dictionary = _mlog(r).get("arcana", {}).get(fid, {})
				if done.has(tier_one):
					researched += 1
					if int(done[tier_one]) <= G1_AT_TURN:
						by_ten += 1
				var cast := false
				for sid in _mlog(r).get("spells", {}).get(fid, {}):
					if ids.has(str(sid)):
						cast = true
				for c in _mlog(r).get("casts", []):
					if str(c.faction) == fid and ids.has(str(c.ritual)):
						cast = true
				if cast:
					used += 1
			var rs := _ratio(researched, games.size())
			var us := _ratio(used, games.size())
			var pass_row := rs >= G1_RESEARCH - 0.000001 and us >= G1_USED - 0.000001
			ok = ok and pass_row
			rows.append({"faction": fid, "school": school, "games": games.size(), "researched": researched, "by_ten": by_ten, "used": used, "ok": pass_row})
			parts.append("%s %s researched %s, used %s" % [Simulator.faction_name(fid), MagicData.SCHOOLS[school].name, _pct(rs), _pct(us)])
	tables["schools"] = rows
	return _band("G1", what, target, "; ".join(parts), "pass" if ok else "miss",
		"" if ok else "a school below 40% researched or 25% used: " + ", ".join(rows.filter(func(x): return not x.ok).map(func(x): return "%s %s" % [x.faction, x.school])))


## G2: no dominant spell. No spell or ritual is the top "why" factor in more than 25% of battles, and no ritual is more than 50%
## of its faction's rituals.
static func _g2(g: Array, gf: Array, tables: Dictionary) -> Dictionary:
	var what := "no dominant spell"
	var target := "no spell or ritual is the top why factor in over 25% of battles; no ritual over 50% of its faction's rituals"
	if g.is_empty():
		return _none("G2", what, target, "no main games")
	var battles := 0
	var top := {}
	var cited := {}
	for r in g:
		for b in r.battles:
			battles += 1
			var m: Dictionary = b.get("magic", {})
			var sid := MagicLog.spell_of(str(m.get("top", "")))
			if not sid.is_empty():
				top[sid] = int(top.get(sid, 0)) + 1
			var seen := {}
			for f in b.factors:
				var cid := MagicLog.spell_of(str(f.id))
				if not cid.is_empty() and not seen.has(cid):
					seen[cid] = true
					cited[cid] = int(cited.get(cid, 0)) + 1
	var worst_spell := ""
	var worst_share := 0.0
	for sid in top:
		var share := _ratio(top[sid], battles)
		if share > worst_share:
			worst_share = share
			worst_spell = str(sid)
	var casts := {}
	var totals := {}
	for r in g:
		for c in _mlog(r).get("casts", []):
			var key := "%s|%s" % [c.faction, c.ritual]
			casts[key] = int(casts.get(key, 0)) + 1
			totals[c.faction] = int(totals.get(c.faction, 0)) + 1
	var worst_ritual := ""
	var worst_rshare := 0.0
	for key in casts:
		var fid := str(key).split("|")[0]
		var share := _ratio(casts[key], totals[fid])
		if share > worst_rshare:
			worst_rshare = share
			worst_ritual = "%s's %s" % [Simulator.faction_name(fid), ritual_name(str(key).split("|")[1])]
	# The same shares with the fog games added: Far Sight, which needs fog, is the one ritual that dilutes the others (reported).
	var all_casts := casts.duplicate()
	var all_totals := totals.duplicate()
	for r in gf:
		for c in _mlog(r).get("casts", []):
			var key := "%s|%s" % [c.faction, c.ritual]
			all_casts[key] = int(all_casts.get(key, 0)) + 1
			all_totals[c.faction] = int(all_totals.get(c.faction, 0)) + 1
	var with_fog := ""
	if not gf.is_empty():
		var top_key := ""
		var top_share := 0.0
		for key in all_casts:
			var sh := _ratio(all_casts[key], all_totals[str(key).split("|")[0]])
			if sh > top_share:
				top_share = sh
				top_key = key
		with_fog = "with the fog games' Far Sights added, the biggest share is %s's %s %s" % [Simulator.faction_name(str(top_key).split("|")[0]),
			ritual_name(str(top_key).split("|")[1]), _pct(top_share)]
	tables["top_why"] = top
	tables["cited_why"] = cited
	tables["battles"] = battles
	tables["ritual_casts"] = casts
	tables["ritual_totals"] = totals
	var ok := worst_share <= G2_SPELL_MAX + 0.000001 and worst_rshare <= G2_RITUAL_MAX + 0.000001
	return _band("G2", what, target, "top why: %s; biggest ritual share: %s" % [
		"none" if worst_spell.is_empty() else "%s %s of %d battles" % [spell_label(worst_spell), _pct(worst_share), battles],
		"none" if worst_ritual.is_empty() else "%s %s" % [worst_ritual, _pct(worst_rshare)]], "pass" if ok else "miss", with_fog)


## G3 (report): the share of battles with a caster whose "why" names a spell (target 30-60%), and the win rate of the side whose
## spells were worth more.
static func _g3(g: Array, tables: Dictionary) -> Dictionary:
	var what := "magic matters"
	var target := "report (battles with a caster whose why names a spell: 30-60%)"
	if g.is_empty():
		return _none("G3", what, target, "no main games")
	var battles := 0
	var with_caster := 0
	var named := 0
	var named_all := 0
	var larger_won := 0
	var larger := 0
	for r in g:
		for b in r.battles:
			battles += 1
			var m: Dictionary = b.get("magic", {})
			var casters := 0
			for fid in m.get("casters", {}):
				casters += int(m.casters[fid])
			var names: bool = b.factors.any(func(f): return not MagicLog.spell_of(str(f.id)).is_empty())
			if names:
				named_all += 1
			if casters > 0 or not m.get("moon", {}).is_empty():
				with_caster += 1
				if names:
					named += 1
			var worth: Dictionary = m.get("worth", {})
			if worth.size() >= 1 and str(b.winner) != "":
				var best := ""
				var best_v := -1.0
				var tie := false
				for fid in FACTIONS:
					var v := float(worth.get(fid, 0.0))
					if v > best_v + 0.000001:
						best_v = v
						best = fid
						tie = false
					elif absf(v - best_v) <= 0.000001:
						tie = true
				if not tie and best_v > 0.0:
					larger += 1
					if str(b.winner) == best:
						larger_won += 1
	var share := _ratio(named, with_caster)
	tables["g3"] = {"battles": battles, "with_caster": with_caster, "named": named, "named_all": named_all, "larger": larger, "larger_won": larger_won}
	return _band("G3", what, target, "%s of battles with a caster name a spell in their why (%d of %d; %s of all %d battles name one); the side whose spells were worth more won %s" % [
		_pct(share), named, with_caster, _pct(_ratio(named_all, battles)), battles, _pct_of(larger_won, larger)], "report",
		"" if _in(share, G3_BAND) else "outside 30-60%")


## G4: the fork still holds: M4's P1 (each side 40-60%, Bradley-Terry head-to-head per faction) and P2 (no side above 65% against
## another), with magic on; the magic-off control's P1 and P2 beside them.
static func _g4(g: Array, pc: Array, tables: Dictionary) -> Dictionary:
	var what := "the fork still holds (M4's P1 and P2, magic on)"
	var target := "as M4: each side 40-60% (Bradley-Terry); no side over 65% against another"
	if g.is_empty():
		return _none("G4", what, target, "no main games")
	var one := _fork(g)
	var control := _fork(pc) if not pc.is_empty() else {}
	tables["fork"] = one
	tables["fork_control"] = control
	var ok: bool = one.p1_ok and one.p2_ok
	var res: String = "P1 %s; P2 worst %s, %d of %d pairings over" % [one.p1_text, one.worst, one.over, one.pairings]
	var detail := ""
	if not control.is_empty():
		detail = "magic off, the same seeds: P1 %s; P2 worst %s, %d over" % [control.p1_text, control.worst, control.over]
	return _band("G4", what, target, res, "pass" if ok else "miss", detail)


static func _fork(res: Array) -> Dictionary:
	var p1_ok := true
	var parts := []
	for fid in FACTIONS:
		var s: Array = PathMatrix.sides_of(fid)
		var ra := PathMatrix.side_record(res, s[0])
		var rb := PathMatrix.side_record(res, s[1])
		var p := Matrix.head_to_head(ra, rb)
		p1_ok = p1_ok and _in(p, PathMatrix.P1_BAND) and _in(1.0 - p, PathMatrix.P1_BAND)
		parts.append("%s %s / %s %s" % [Simulator.side_name(s[0]), _pct(p), Simulator.side_name(s[1]), _pct(1.0 - p)])
	var pairings := PathMatrix._pairings(res)
	var worst := {"share": 0.0, "text": "none"}
	var over := 0
	for pr in pairings:
		var cw := _ratio(pr.crown_wins, pr.decisive)
		for pair in [[cw, pr.crown, pr.clans], [1.0 - cw, pr.clans, pr.crown]]:
			if int(pr.decisive) > 0 and float(pair[0]) > worst.share:
				worst = {"share": float(pair[0]), "text": "%s %s against %s" % [Simulator.side_name(str(pair[1])), _pct(float(pair[0])), Simulator.side_name(str(pair[2]))]}
		if int(pr.decisive) > 0 and maxf(cw, 1.0 - cw) > PathMatrix.P2_MAX + 0.000001:
			over += 1
	return {"p1_ok": p1_ok, "p1_text": "; ".join(parts), "p2_ok": over == 0, "worst": worst.text, "over": over, "pairings": pairings.size()}


## G5: length. Median decisive game 12-25 turns, and at most 15% of games at the turn cap.
static func _g5(g: Array, pc: Array) -> Dictionary:
	var what := "length"
	var target := "median decisive game 12-25 turns; at most 15% at the 60-turn cap"
	if g.is_empty():
		return _none("G5", what, target, "no main games")
	var ls := _median_length(g)
	var capped := _capped(g)
	var share := _ratio(capped, g.size())
	var ok := _in(float(ls.median), G5_BAND) and share <= G5_CAP_MAX + 0.000001
	var detail := ""
	if not pc.is_empty():
		var lc := _median_length(pc)
		detail = "magic off, the same seeds: median %s, %s at the cap" % [Simulator._num(lc.median), _pct_of(_capped(pc), pc.size())]
	var cap_by := PathMatrix._cap_detail(g) if capped > 0 else ""
	return _band("G5", what, target, "median %s (%d-%d); %s at the cap" % [Simulator._num(ls.median), ls.min, ls.max, _pct_of(capped, g.size())],
		"pass" if ok else "miss", "; ".join([detail, cap_by].filter(func(x): return not str(x).is_empty())))


## G6: transformations still happen. Median transformation turn 8-12, and both transformed by turn 15 in 80%+ of the games
## that reach it.
static func _g6(g: Array, pc: Array) -> Dictionary:
	var what := "transformations still happen"
	var target := "median transformation turn 8-12; both transformed by turn 15 in 80%+ of games reaching it"
	if g.is_empty():
		return _none("G6", what, target, "no main games")
	var t := _transform_stats(g)
	var ok: bool = _in(float(t.stats.median), G6_BAND) and t.share >= G6_SHARE - 0.000001
	var detail := ""
	if not pc.is_empty():
		var c := _transform_stats(pc)
		detail = "magic off, the same seeds: median turn %s; both by turn 15 in %s" % [Simulator._num(c.stats.median), _pct_of(c.both, c.reached)]
	return _band("G6", what, target, "median turn %s (%d-%d, %d transformations); both by turn 15 in %s" % [Simulator._num(t.stats.median),
		t.stats.min, t.stats.max, t.stats.n, _pct_of(t.both, t.reached)], "pass" if ok else "miss", detail)


static func _transform_stats(res: Array) -> Dictionary:
	var turns := []
	var reached := 0
	var both := 0
	for r in res:
		var paths: Dictionary = r.get("paths", {})
		var all_by := true
		for fid in paths:
			var tt := int(paths[fid].get("transform_turn", 0))
			if tt > 0:
				turns.append(tt)
			if tt <= 0 or tt > G6_BY_TURN:
				all_by = false
		if int(r.turns) >= G6_BY_TURN:
			reached += 1
			if all_by and paths.size() == FACTIONS.size():
				both += 1
	return {"stats": Simulator.stats_of(turns), "reached": reached, "both": both, "share": _ratio(both, reached)}


## G7: rituals happen. A ritual cast by turn G7_BY_TURN in 80%+ of the games that reach it, and every ritual cast in 10%+ of the games
## where its faction knows it (Far Sight, which every faction with a caster knows, is judged in the fog games).
static func _g7(g: Array, gf: Array, tables: Dictionary) -> Dictionary:
	var what := "rituals happen"
	var target := "a ritual cast by turn %d in 80%%+ of games reaching turn %d; every ritual cast in 10%%+ of the games where its faction knows it" % [G7_BY_TURN, G7_BY_TURN]
	if g.is_empty():
		return _none("G7", what, target, "no main games")
	var reached := g.filter(func(r): return _reached(r, G7_BY_TURN))
	var early := 0
	var per_faction := {}
	for fid in FACTIONS:
		per_faction[fid] = 0
	for r in reached:
		var any := false
		for fid in FACTIONS:
			var cast: bool = _mlog(r).get("casts", []).any(func(c): return str(c.faction) == fid and int(c.turn) <= G7_BY_TURN)
			if cast:
				per_faction[fid] += 1
				any = true
		if any:
			early += 1
	var share := _ratio(early, reached.size())
	var rows := []
	var each_ok := true
	var missing := []
	for fid in FACTIONS:
		for sid in rituals():
			var sp: Dictionary = MagicData.SPELLS[sid]
			var common := str(sp.school) == MagicData.COMMON
			if not common and not MagicData.FACTION_SCHOOLS[fid].has(str(sp.school)):
				continue
			var pool := gf if common else g
			var knows := 0
			var cast := 0
			for r in pool:
				var known: bool = had_caster(r, fid) if common else _mlog(r).get("arcana", {}).get(fid, {}).has(sid)
				if not known:
					continue
				knows += 1
				if _mlog(r).get("casts", []).any(func(c): return str(c.faction) == fid and str(c.ritual) == sid):
					cast += 1
			if common and gf.is_empty():
				continue
			var s := _ratio(cast, knows)
			var row_ok := knows == 0 or s >= G7_EACH - 0.000001
			rows.append({"faction": fid, "ritual": sid, "knows": knows, "cast": cast, "share": s, "ok": row_ok, "fog": common})
			if not row_ok:
				each_ok = false
				missing.append("%s's %s %s" % [Simulator.faction_name(fid), ritual_name(sid), _pct(s)])
	tables["ritual_rows"] = rows
	var ok := share >= G7_SHARE - 0.000001 and each_ok
	var notes := []
	if not missing.is_empty():
		notes.append("below 10%: " + ", ".join(missing))
	# When the first ritual comes: the turn the first cast of a game was made (median), and what the fog games do (Far Sight needs no research).
	var firsts := []
	for r in g:
		var turns: Array = _mlog(r).get("casts", []).map(func(c): return int(c.turn))
		if not turns.is_empty():
			firsts.append(turns.min())
	if not firsts.is_empty():
		var fs := Simulator.stats_of(firsts)
		var later := []
		for by in [G7_BY_TURN - 2, G7_BY_TURN + 2]:
			var reaching := g.filter(func(r): return _reached(r, by))
			var cast_by: int = reaching.filter(func(r): return _mlog(r).get("casts", []).any(func(c): return int(c.turn) <= by)).size()
			later.append("by turn %d in %s" % [by, _pct_of(cast_by, reaching.size())])
		notes.append("the first ritual of a game comes on turn %s (median; %d games cast one; %s of the games that reach it)" % [
			Simulator._num(fs.median), fs.n, ", ".join(later)])
	if not gf.is_empty():
		var fog_reached := gf.filter(func(r): return _reached(r, G7_BY_TURN))
		var fog_early: int = fog_reached.filter(func(r): return _mlog(r).get("casts", []).any(func(c): return int(c.turn) <= G7_BY_TURN)).size()
		notes.append("in the fog games, where Far Sight needs no research, a ritual by turn %d in %s" % [G7_BY_TURN, _pct_of(fog_early, fog_reached.size())])
	return _band("G7", what, target, "a ritual by turn %d in %s (Crown %s, Clans %s); %d of %d rituals below 10%% of the games that know them" % [
		G7_BY_TURN, _pct_of(early, reached.size()), _pct(_ratio(per_faction.kingdom, reached.size())), _pct(_ratio(per_faction.beasts, reached.size())),
		missing.size(), rows.size()], "pass" if ok else "miss", "; ".join(notes))


## G8: mages bought. Mages are 4-20% of each faction's regular recruits.
static func _g8(g: Array, tables: Dictionary) -> Dictionary:
	var what := "mages bought"
	var target := "mages 4-20% of each faction's regular recruits"
	if g.is_empty():
		return _none("G8", what, target, "no main games")
	var ok := true
	var parts := []
	var rows := {}
	for fid in FACTIONS:
		var mages := 0
		var regulars := 0
		var games_with := 0
		for r in g:
			var rec: Dictionary = r.get("recruits", {}).get(fid, {})
			var m := int(rec.get(str(MagicData.MAGES[fid].id), 0))
			mages += m
			if m > 0:
				games_with += 1
			for tid in rec:
				if not PathMatrix._is_commander(fid, str(tid)):
					regulars += int(rec[tid])
		var s := _ratio(mages, regulars)
		ok = ok and _in(s, G8_BAND)
		rows[fid] = {"mages": mages, "regulars": regulars, "games_with": games_with}
		parts.append("%s %s (%d of %d recruits; mages in %s of games)" % [str(MagicData.MAGES[fid].name), _pct(s), mages, regulars, _pct(_ratio(games_with, g.size()))])
	tables["mages"] = rows
	return _band("G8", what, target, "; ".join(parts), "pass" if ok else "miss")


## G9: Tithe of Blood. In the Tithe pairs, the Clans' win rate with Tithe within 5 points of the null-mandate run; the scripted
## bleeding build reported.
static func _g9(gt: Array, gb: Array, tables: Dictionary) -> Dictionary:
	var what := "Tithe of Blood is fair"
	var target := "Clans win rate with Tithe within 5 points of the null-mandate run; the scripted build reported"
	if gt.is_empty():
		return _none("G9", what, target, "no Tithe pairs")
	var with := gt.filter(func(r): return str(r.tithe) == "tithe")
	var without := gt.filter(func(r): return str(r.tithe) == "null")
	var a := _clans_record(with)
	var b := _clans_record(without)
	var wa := _ratio(a.wins, a.decisive)
	var wb := _ratio(b.wins, b.decisive)
	var delta := wa - wb
	var rows := []
	for k in RulerRules.presets_for("beasts"):
		var kid := str(k.id)
		var ra := _clans_record(with.filter(func(r): return str(r.builds.get("beasts", "")) == kid))
		var rb := _clans_record(without.filter(func(r): return str(r.builds.get("beasts", "")) == kid))
		rows.append({"preset": kid, "with": ra, "without": rb})
	var scripted := _clans_record(gb)
	tables["tithe"] = {"with": a, "without": b, "rows": rows, "bleed": scripted, "with_stats": _tithe_stats(with), "without_stats": _tithe_stats(without),
		"bleed_stats": _tithe_stats(gb)}
	var ok := absf(delta) <= G9_DELTA + 0.000001
	var se := sqrt(wa * (1.0 - wa) / maxf(1.0, float(a.decisive)) + wb * (1.0 - wb) / maxf(1.0, float(b.decisive)))  # one standard error of the difference
	var res := "Clans with Tithe %s, with the null mandate %s: %+.1f points (one standard error: %.1f)" % [_pct_of(a.wins, a.decisive),
		_pct_of(b.wins, b.decisive), 100.0 * delta, 100.0 * se]
	if not gb.is_empty():
		res += "; scripted bleeding build %s" % _pct_of(scripted.wins, scripted.decisive)
	return _band("G9", what, target, res, "pass" if ok else "miss")


## {wins, decisive, games} of the Clans in `res`.
static func _clans_record(res: Array) -> Dictionary:
	var rec := {"wins": 0, "decisive": 0, "games": res.size()}
	for r in res:
		if Matrix.decisive(r):
			rec.decisive += 1
			if str(r.winner) == "beasts":
				rec.wins += 1
	return rec


## What the Clans did with their blood in `res`: {"games", "rituals", "blood" (cast in blood), "hp" (paid), "turns" (mean)}.
static func _tithe_stats(res: Array) -> Dictionary:
	var out := {"games": res.size(), "rituals": 0, "blood": 0, "hp": 0, "turns": 0.0, "wolves": 0}
	var turns := 0
	for r in res:
		turns += int(r.turns)
		for c in _mlog(r).get("casts", []):
			if str(c.faction) != "beasts":
				continue
			out.rituals += 1
			if str(c.pay) == "blood":
				out.blood += 1
				out.hp += int(c.hp)
	out.turns = _ratio(turns, res.size())
	return out


## G10: the Regent. Regent's Court wins at most 60% of its decisive games, and its share of capped games is no higher than the
## other Crown presets' (average).
static func _g10(g: Array, tables: Dictionary) -> Dictionary:
	var what := "the Regent is held"
	var target := "Regent's Court wins at most 60% of its decisive games; its share of capped games no higher than the other Crown presets'"
	if g.is_empty():
		return _none("G10", what, target, "no main games")
	var rows := {}
	for p in RulerRules.presets_for("kingdom"):
		var pid := str(p.id)
		var mine := g.filter(func(r): return str(r.builds.get("kingdom", "")) == pid)
		var dec := 0
		var wins := 0
		for r in mine:
			if Matrix.decisive(r):
				dec += 1
				if str(r.winner) == "kingdom":
					wins += 1
		rows[pid] = {"games": mine.size(), "decisive": dec, "wins": wins, "capped": _capped(mine)}
	tables["crown_presets"] = rows
	var rc: Dictionary = rows.get("regents_court", {"games": 0, "decisive": 0, "wins": 0, "capped": 0})
	var rc_win := _ratio(rc.wins, rc.decisive)
	var rc_cap := _ratio(rc.capped, rc.games)
	var others := 0.0
	var n := 0
	for pid in rows:
		if pid != "regents_court":
			others += _ratio(rows[pid].capped, rows[pid].games)
			n += 1
	var other_cap := others / maxf(1.0, float(n))
	var ok := rc_win <= G10_MAX + 0.000001 and rc_cap <= other_cap + 0.000001
	var parts := []
	for pid in rows:
		parts.append("%s %s of decisive, %s capped" % [Simulator.build_name(str(pid)), _pct(_ratio(rows[pid].wins, rows[pid].decisive)), _pct(_ratio(rows[pid].capped, rows[pid].games))])
	return _band("G10", what, target, "Regent's Court %s of %d decisive, %s capped (the others %s capped on average)" % [_pct(rc_win), rc.decisive,
		_pct(rc_cap), _pct(other_cap)], "pass" if ok else "miss", "Crown win share by preset, as the Crown seat: " + "; ".join(parts))


## G11: fog. The fog matrix against its no-fog control (the first games of the same cells): median length within 3 turns; successful
## Far Sights cast in 30%+ of the fog games that reach turn 8; Crown / Clans 40-60% and how often the winner changed (reported).
static func _g11(g: Array, gf: Array, tables: Dictionary) -> Dictionary:
	var what := "fog changes decisions, not fairness"
	var target := "median length within 3 turns of the no-fog control; successful Far Sights in 30%+ of fog games reaching turn 8; Crown / Clans 40-60% and winner changes reported"
	if gf.is_empty():
		return _none("G11", what, target, "no fog games")
	var keys := {}
	for r in gf:
		keys[_key(r)] = r
	var control := g.filter(func(r): return keys.has(_key(r)))
	var by_key := {}
	for r in control:
		by_key[_key(r)] = r
	var lf := _median_length(gf)
	var lc := _median_length(control)
	var diff := absf(float(lf.median) - float(lc.median))
	var reached := gf.filter(func(r): return _reached(r, G11_SIGHT_TURN))
	var seen := 0
	var cast_any := 0
	for r in reached:
		var ok_cast: bool = _mlog(r).get("casts", []).any(func(c): return str(c.ritual) == "far_sight" and str(c.outcome) == "cast" and str(c.blocked).is_empty())
		if ok_cast:
			seen += 1
		if _mlog(r).get("casts", []).any(func(c): return str(c.ritual) == "far_sight"):
			cast_any += 1
	var sight_share := _ratio(seen, reached.size())
	var changed := 0
	var compared := 0
	for k in keys:
		if by_key.has(k):
			compared += 1
			if str(keys[k].winner) != str(by_key[k].winner):
				changed += 1
	var fw := _crown_share(gf)
	var cw := _crown_share(control)
	var scouts := {}
	for fid in FACTIONS:
		var n := 0
		for r in gf:
			var seat: int = r.seats.find(fid)
			if seat >= 0 and int(r.policy_stats[seat].get("scouts", 0)) > 0:
				n += 1
		scouts[fid] = n
	var probes := {"probes": 0, "views": 0, "view_mismatches": 0, "plans": 0, "plan_mismatches": 0, "illegal": 0, "skipped": 0}
	for r in gf:
		for k in probes:
			probes[k] += int(r.get("fog", {}).get(k, 0))
	tables["fog"] = {"games": gf.size(), "control": control.size(), "length_fog": lf, "length_control": lc, "reached_8": reached.size(),
		"far_sight_ok": seen, "far_sight_cast": cast_any, "changed": changed, "compared": compared, "crown_fog": fw, "crown_control": cw,
		"scouts": scouts, "probes": probes, "capped_fog": _capped(gf), "capped_control": _capped(control)}
	var ok := diff <= G11_LENGTH + 0.000001 and sight_share >= G11_SIGHT - 0.000001
	return _band("G11", what, target, "median length %s fog vs %s no fog (%+.1f); successful Far Sights in %s; Crown / Clans %s fog, %s no fog; winner changed in %s" % [
		Simulator._num(lf.median), Simulator._num(lc.median), float(lf.median) - float(lc.median), _pct_of(seen, reached.size()), _crown_text(fw), _crown_text(cw),
		_pct_of(changed, compared)], "pass" if ok else "miss",
		"scouted in a game: Crown %s, Clans %s" % [_pct_of(scouts.kingdom, gf.size()), _pct_of(scouts.beasts, gf.size())])


static func _key(r: Dictionary) -> String:
	return "%s|%d" % [str(r.cell).substr(str(r.cell).find(":") + 1), int(r.seed)]


static func _crown_share(res: Array) -> Dictionary:
	var dec := 0
	var wins := 0
	for r in res:
		if Matrix.decisive(r):
			dec += 1
			if str(r.winner) == "kingdom":
				wins += 1
	return {"wins": wins, "decisive": dec}


static func _crown_text(c: Dictionary) -> String:
	var s := _ratio(c.wins, c.decisive)
	return "%s / %s" % [_pct(s), _pct(1.0 - s)]


## G12: earlier games unbroken. The M2 matrix's games (magic, fog and paths off) have the record digests recorded on main; the
## M1, M2 and M4 fixture records replay byte-identically with the current rules and the computer's rerun orders match (`records`);
## and with magic on, M2's band F (a sacrifice in 15-50% of games) holds. F has missed on main since #131 (the contract config
## plays with independents), so it is judged against the magic-off control too: when F is outside the band in both, magic
## has not broken it if it is within F_SLACK of the control, and the band says so (the literal reading is in the detail).
static func _g12(g: Array, pc: Array, m2: Array, fixture: Dictionary, records: Dictionary) -> Dictionary:
	var what := "earlier games unbroken"
	var target := "M1, M2 and M4 records replay identically and the AI's rerun orders match; M2 games identical to main; with magic on, M2's band F (sacrifices in 15-50% of games) holds"
	var digests: Dictionary = fixture.get("digests", {})
	var same := 0
	var differ := []
	var missing := 0
	for r in m2:
		var key := "%s|%d" % [str(r.cell).trim_prefix("P7:"), int(r.seed)]
		if not digests.has(key):
			missing += 1
		elif str(digests[key]) == str(r.get("record_md5", "")):
			same += 1
		else:
			differ.append(key)
	var with_sac := g.filter(func(r): return not r.ruler_log.sacrifices.is_empty()).size()
	var f_share := _ratio(with_sac, g.size())
	var control_sac := pc.filter(func(r): return not r.ruler_log.sacrifices.is_empty()).size()
	var control_share := _ratio(control_sac, pc.size())
	var in_band := g.is_empty() or _in(f_share, Matrix.F_BAND)
	var held_by_control := not pc.is_empty() and not _in(control_share, Matrix.F_BAND) and f_share <= control_share + F_SLACK + 0.000001
	var f_ok := in_band or held_by_control
	var digests_ok := not m2.is_empty() and same == m2.size()
	var records_ok := bool(records.get("ok", false))
	var parts := ["%d of %d M2 game records identical to main" % [same, m2.size()],
		"fixture records: %s" % ("not checked" if records.is_empty() else ("identical, AI orders match" if records_ok else "DIFFER")),
		"F %s (%d of %d magic games)%s" % [_pct(f_share), with_sac, g.size(), "" if pc.is_empty() else ", %s with magic off (%d of %d)" % [_pct(control_share), control_sac, pc.size()]]]
	var details := []
	if m2.is_empty():
		details.append("no M2 games were played")
	elif digests.is_empty():
		details.append("the fixture %s is missing" % PathMatrix.M2_FIXTURE)
	elif not differ.is_empty():
		details.append("first differing M2 game: %s" % differ[0])
	elif missing > 0:
		details.append("%d M2 games are not in the fixture" % missing)
	if not records.is_empty():
		details.append(str(records.get("text", "")))
	if not f_ok:
		details.append("F is outside 15-50%")
	elif held_by_control and not in_band:
		details.append("F is outside 15-50%% (literally a miss), but so it is with magic off (%s): magic moved it by %+.0f points, within the %d points allowed" % [
			_pct(control_share), 100.0 * (f_share - control_share), roundi(100.0 * F_SLACK)])
	var ok := digests_ok and records_ok and f_ok
	return _band("G12", what, target, "; ".join(parts), "pass" if ok else "miss", "; ".join(details.filter(func(x): return not str(x).is_empty())))


## G13: integrity, every game. 0 invariant violations (gold and hit point ledgers, summons fading, enchantments ending), session
## errors and script errors; every 10th game replays identically; 0 ritual forecast mismatches for targets in clear sight with
## nothing turned aside; and on every 10th turn of every fog game the snapshot test passes, the computer's orders included.
static func _g13(results: Array, stray_errors: int) -> Dictionary:
	var what := "integrity, every game"
	var target := "0 violations, session errors, script errors, ritual forecast mismatches and snapshot mismatches; every 10th game replays identically"
	var viol := 0
	var errs := 0
	var scr := stray_errors
	var replays := 0
	var replay_bad := []
	var first := ""
	var forecast := {"checks": 0, "mismatches": 0, "turned_aside": 0, "unseen": 0}
	var forecast_first := ""
	var ledger := {"checks": 0, "mismatches": 0}
	var probes := {"probes": 0, "views": 0, "view_mismatches": 0, "plans": 0, "plan_mismatches": 0, "illegal": 0, "skipped": 0}
	var probe_first := ""
	var by_check := {}
	for r in results:
		viol += r.violations.size()
		errs += r.errors.size()
		scr += r.script_errors.size()
		for v in r.violations:
			by_check[str(v.check)] = int(by_check.get(str(v.check), 0)) + 1
		if first.is_empty():
			for key in ["violations", "errors", "script_errors"]:
				if not r[key].is_empty() and first.is_empty():
					first = "seed %d (%s): %s" % [r.seed, r.cell, r[key][0].get("detail", r[key][0].get("check", ""))]
		if not str(r.replay).is_empty():
			replays += 1
			if str(r.replay) != "identical":
				replay_bad.append("seed %d (%s): %s" % [r.seed, r.cell, r.replay])
		var m: Dictionary = r.get("magic", {})
		for k in forecast:
			forecast[k] += int(m.get("forecast", {}).get(k, 0))
		for k in ledger:
			ledger[k] += int(m.get("hp", {}).get(k, 0))
		if forecast_first.is_empty() and not str(m.get("forecast", {}).get("first", "")).is_empty():
			forecast_first = "seed %d (%s): %s" % [r.seed, r.cell, m.forecast.first]
		for k in probes:
			probes[k] += int(r.get("fog", {}).get(k, 0))
		if probe_first.is_empty() and not str(r.get("fog", {}).get("first", "")).is_empty():
			probe_first = "seed %d (%s): %s" % [r.seed, r.cell, r.fog.first]
	var snap_bad: int = probes.view_mismatches + probes.plan_mismatches + probes.illegal
	var ok: bool = viol == 0 and errs == 0 and scr == 0 and replay_bad.is_empty() and replays > 0 and forecast.mismatches == 0 and snap_bad == 0
	var details := []
	for d in [first, forecast_first, probe_first]:
		if not str(d).is_empty():
			details.append(str(d))
	if not replay_bad.is_empty():
		details.append(replay_bad[0])
	if not by_check.is_empty():
		var keys: Array = by_check.keys()
		keys.sort()
		details.append("violations by check: " + ", ".join(keys.map(func(k): return "%s %d" % [k, by_check[k]])))
	return _band("G13", what, target, "%d violations, %d session errors, %d script errors; %d of %d replays identical (%d games); ritual forecasts: %d mismatches in %d checks (%d turned aside, %d out of clear sight set aside); hit point ledger: %d mismatches in %d armies; fog snapshots: %d view, %d plan and %d legality failures in %d views and %d plans (%d skipped)" % [
		viol, errs, scr, replays - replay_bad.size(), replays, results.size(), forecast.mismatches, forecast.checks, forecast.turned_aside, forecast.unseen,
		ledger.mismatches, ledger.checks, probes.view_mismatches, probes.plan_mismatches, probes.illegal, probes.views, probes.plans, probes.skipped],
		"pass" if ok else "miss", "; ".join(details))


## G14 (report, with a target): each ritual's hit points moved per gold over its life, in the main matrix. Dawn Blessing's healing
## and Bloodrot's bites are counted when the enchantments phase moves them, the Blood Moon's healing back in battle; the other
## rituals move no hit points, so they have no value here. Target 1-4; a miss goes to tuning.
static func _g14(g: Array, tables: Dictionary) -> Dictionary:
	var what := "ritual value"
	var target := "report (hit points moved per gold over a ritual's life: 1-4)"
	if g.is_empty():
		return _none("G14", what, target, "no main games")
	var rows := []
	var parts := []
	var misses := []
	for sid in ["dawn_blessing", "bloodrot", "blood_moon"]:
		var gold := 0.0
		var casts := 0
		var moved := 0
		for r in g:
			var m := _mlog(r)
			for c in m.get("casts", []):
				if str(c.ritual) == sid:
					gold += _paid(c)
					if str(c.outcome) == "cast":
						casts += 1
			if sid == "dawn_blessing":
				moved += int(m.get("healed", {}).get(sid, 0))
			elif sid == "bloodrot":
				moved += int(m.get("drained", {}).get(sid, 0))
			else:
				moved += int(m.get("moon", 0))
		var value := 0.0 if gold <= 0.0 else float(moved) / gold
		rows.append({"ritual": sid, "casts": casts, "gold": gold, "moved": moved, "value": value})
		parts.append("%s %.1f hp per gold (%d hp for %d gold, %d casts)" % [ritual_name(sid), value, moved, roundi(gold), casts])
		if casts > 0 and not _in(value, G14_BAND):
			misses.append("%s %.1f" % [ritual_name(sid), value])
	tables["value"] = rows
	return _band("G14", what, target, "; ".join(parts), "report", "outside 1-4: " + ", ".join(misses) if not misses.is_empty() else "")


# --- the records part of G12 ---------------------------------------------------------------------------------

## Replays the earlier fixture records with the current engine and reruns the computer on the M5 base games: {"ok", "text"}.
## tests/fixtures/main_records.json (M1 and M2, recorded for M4-1) and m5_base_records.json (M1, M2 and M4, recorded before magic
## and fog) must replay turn by turn from their stored orders to byte-identical states and events, and the computer, rerun on
## each M5 base game from its spec, must give the stored orders turn by turn.
static func records_check() -> Dictionary:
	var notes := []
	var ok := true
	for path in [Fixture.OUT, Fixture.M5_OUT]:
		var r := Fixture.check_existing(path)
		ok = ok and bool(r.ok)
		notes.append(str(r.text))
	var data = JSON.parse_string(FileAccess.get_file_as_string(Fixture.M5_OUT))
	var reruns := 0
	var rerun_bad := []
	if data is Dictionary:
		for game in data.get("games", []):
			var again := Fixture.play(game.spec)
			var want: Array = game.record.history
			var got: Array = again.record.history
			var same: bool = got.size() == want.size() and again.final_state == game.final_state
			if same:
				for t in want.size():
					if JSON.stringify(JSON.parse_string(JSON.stringify(got[t].orders))) != JSON.stringify(want[t].orders):
						same = false
						break
			reruns += 1
			if not same:
				rerun_bad.append(str(game.name))
	else:
		ok = false
		notes.append("The M5 base records do not load.")
	if not rerun_bad.is_empty():
		ok = false
		notes.append("The computer's rerun differs from the record in: %s." % ", ".join(rerun_bad))
	else:
		notes.append("The computer's rerun of the %d M5 base games gave the recorded orders." % reruns)
	return {"ok": ok, "text": " ".join(notes)}


# --- the report --------------------------------------------------------------------------------------------

## The whole report as markdown: the bands table, then the details behind each band.
static func to_markdown(j: Dictionary, header: String = "") -> String:
	var L := []
	var t: Dictionary = j.tables
	L.append("## Magic and fog balance check (design/M5_MAGIC_FOG.md §13.2)%s" % ("" if header.is_empty() else ": " + header))
	L.append("")
	L.append("| band | what | target | result | status |")
	L.append("|---|---|---|---|---|")
	for b in j.bands:
		var status: String = {"pass": "**pass**", "miss": "**miss**", "report": "report", "none": "not played"}[b.status]
		L.append("| %s | %s | %s | %s | %s |" % [b.band, b.what, b.target, b.result, status])
	var notes: Array = j.bands.filter(func(b): return not str(b.detail).is_empty())
	if not notes.is_empty():
		L.append("")
		for b in notes:
			L.append("- **%s:** %s" % [b.band, b.detail])
	L.append("")
	L.append("Exit code: %s (G12 %s, G13 %s)." % ["0" if j.ok else "1", "holds" if j.g12 else "misses", "holds" if j.g13 else "misses"])
	if t.has("schools"):
		L.append("")
		L.append("### Schools (G1): games reaching turn %d" % G1_AT_TURN)
		L.append("")
		L.append("| faction | school | games | tier I researched | by turn %d | used in a game | |" % G1_AT_TURN)
		L.append("|---|---|---|---|---|---|---|")
		for s in t.schools:
			L.append("| %s | %s | %d | %s | %s | %s | %s |" % [Simulator.faction_name(s.faction), MagicData.SCHOOLS[s.school].name, s.games,
				_pct_of(s.researched, s.games), _pct_of(s.by_ten, s.games), _pct_of(s.used, s.games), "" if s.ok else "**miss**"])
	if t.has("ritual_casts"):
		L.append("")
		L.append("### Rituals cast (G2, G7), main matrix")
		L.append("")
		L.append("| faction | ritual | casts | share of the faction's rituals | games that know it | games it was cast in |")
		L.append("|---|---|---|---|---|---|")
		var rr: Array = t.get("ritual_rows", [])
		for row in rr:
			var key := "%s|%s" % [row.faction, row.ritual]
			L.append("| %s | %s | %d | %s | %d | %s |" % [Simulator.faction_name(row.faction), ritual_name(row.ritual) + (" (fog games)" if bool(row.get("fog", false)) else ""), int(t.ritual_casts.get(key, 0)),
				_pct(_ratio(t.ritual_casts.get(key, 0), t.ritual_totals.get(row.faction, 0))), row.knows, _pct_of(row.cast, row.knows)])
		L.append("")
		L.append("### Top \"why\" factor, by spell or ritual (G2): %d battles" % int(t.get("battles", 0)))
		L.append("")
		var ids: Array = t.top_why.keys()
		for sid in t.cited_why.keys():
			if not ids.has(sid):
				ids.append(sid)
		ids.sort_custom(func(a, b): return int(t.top_why.get(a, 0)) > int(t.top_why.get(b, 0)) if int(t.top_why.get(a, 0)) != int(t.top_why.get(b, 0)) else str(a) < str(b))
		L.append("| spell or ritual | top why factor in | named in a battle's why |")
		L.append("|---|---|---|")
		for sid in ids:
			L.append("| %s | %s | %s |" % [spell_label(str(sid)), _pct_of(t.top_why.get(sid, 0), t.battles), _pct_of(t.cited_why.get(sid, 0), t.battles)])
	if t.has("mages"):
		L.append("")
		L.append("### Mages (G8)")
		L.append("")
		for fid in FACTIONS:
			var m: Dictionary = t.mages[fid]
			L.append("- %s: %d mages among %d regular recruits (%s); mages bought in %d games." % [Simulator.faction_name(fid), m.mages, m.regulars,
				_pct(_ratio(m.mages, m.regulars)), m.games_with])
	if t.has("value"):
		L.append("")
		L.append("### Ritual value (G14)")
		L.append("")
		L.append("| ritual | casts | gold paid | hp moved | hp per gold |")
		L.append("|---|---|---|---|---|")
		for v in t.value:
			L.append("| %s | %d | %d | %d | %.2f |" % [ritual_name(v.ritual), v.casts, roundi(v.gold), v.moved, v.value])
	if t.has("fork"):
		L.append("")
		L.append("### Side pairings (G4), main matrix (wins of decisive games)")
		L.append("")
		L.append("| Aurel Crown side | Thornmane Clans side | games | decisive | Crown wins | Clans wins | draws | at the cap | median length |")
		L.append("|---|---|---|---|---|---|---|---|---|")
		for pr in t.pairings:
			L.append("| %s | %s | %d | %d | %d (%s) | %d (%s) | %d | %d | %s |" % [Simulator.side_name(pr.crown), Simulator.side_name(pr.clans), pr.games,
				pr.decisive, pr.crown_wins, _pct(_ratio(pr.crown_wins, pr.decisive)), pr.clans_wins, _pct(_ratio(pr.clans_wins, pr.decisive)),
				pr.draws, pr.unfinished, Simulator._num(pr.median)])
		L.append("")
		L.append("### Sides by preset (G4, G10), main matrix")
		L.append("")
		L.append("| side | preset | games | won | at the cap |")
		L.append("|---|---|---|---|---|")
		for p in t.presets:
			L.append("| %s | %s | %d | %s | %d |" % [Simulator.side_name(p.side), Simulator.build_name(p.preset), p.games, _pct_of(p.wins, p.decisive), p.capped])
	if t.has("tithe"):
		var ti: Dictionary = t.tithe
		L.append("")
		L.append("### Tithe of Blood (G9)")
		L.append("")
		L.append("| Clans preset | with Tithe: won | with the null mandate: won | difference |")
		L.append("|---|---|---|---|")
		for row in ti.rows:
			L.append("| %s | %s | %s | %+.1f |" % [Simulator.build_name(row.preset), _pct_of(row.with.wins, row.with.decisive),
				_pct_of(row.without.wins, row.without.decisive), 100.0 * (_ratio(row.with.wins, row.with.decisive) - _ratio(row.without.wins, row.without.decisive))])
		L.append("")
		for k in ["with", "without", "bleed"]:
			var s: Dictionary = ti["%s_stats" % k]
			if int(s.games) == 0:
				continue
			L.append("- **%s** (%d games, mean length %.1f turns): the Clans cast %d rituals, %d in blood (%d hit points)." % [
				{"with": "Tithe of Blood", "without": "Null mandate", "bleed": "Scripted bleeding build"}[k], s.games, s.turns, s.rituals, s.blood, s.hp])
		if int(ti.bleed.games) > 0:
			L.append("- Scripted bleeding build: the Clans won %s of decisive games (against the same Crown presets and seeds as the pairs)." % _pct_of(ti.bleed.wins, ti.bleed.decisive))
	if t.has("fog"):
		var f: Dictionary = t.fog
		L.append("")
		L.append("### Fog (G11)")
		L.append("")
		L.append("- Fog games: %d; the no-fog control (the same cells and seeds): %d." % [f.games, f.control])
		L.append("- Median decisive length: %s with fog, %s without; at the cap %d with fog, %d without." % [Simulator._num(f.length_fog.median),
			Simulator._num(f.length_control.median), f.capped_fog, f.capped_control])
		L.append("- Far Sights: successful in %s of the fog games that reached turn %d (cast in %d)." % [_pct_of(f.far_sight_ok, f.reached_8), G11_SIGHT_TURN, f.far_sight_cast])
		L.append("- Crown / Clans: %s with fog, %s without. The winner changed in %s of the games that can be compared." % [_crown_text(f.crown_fog),
			_crown_text(f.crown_control), _pct_of(f.changed, f.compared)])
		L.append("- Games where the faction sent a scout: Crown %s, Clans %s." % [_pct_of(f.scouts.kingdom, f.games), _pct_of(f.scouts.beasts, f.games)])
		L.append("- Snapshot probes (every %dth turn): %d turns, %d views and %d computer plans compared; %d view, %d plan and %d legality failures (%d skipped)." % [
			FogProbe.PROBE_EVERY, f.probes.probes, f.probes.views, f.probes.plans, f.probes.view_mismatches, f.probes.plan_mismatches, f.probes.illegal, f.probes.skipped])
	if t.has("g3"):
		var g3: Dictionary = t.g3
		L.append("")
		L.append("### Magic in battle (G3)")
		L.append("")
		L.append("- %d battles; %d had a caster; a spell is named in the why of %d of those (%d of all battles)." % [g3.battles, g3.with_caster, g3.named, g3.named_all])
		L.append("- The side whose spells were worth more won %s of the %d battles where the two differ." % [_pct(_ratio(g3.larger_won, g3.larger)), g3.larger])
	return "\n".join(L)
